module arsd.eventloop;

/* **** */
// Loop implementation
// FIXME: much of this is posix or even linux specific, but we ideally want the same interface across all operating systems, though not necessarily even a remotely similar implementation

import std.traits;

// we send custom events as type+pointer pairs. The type is sent as a hash of the mangled name, so we get a unique integer for anything, including any user defined types.
template typehash(T...) {
	void delegate(T) tmp;
	enum typehash = hashOf(tmp.mangleof.ptr, tmp.mangleof.length);
}

private WrappedListener[][hash_t] listeners;
private WrappedListener[] idleHandlers;

/// Valid event listeners must be callable and take exactly one argument. The type of argument determines the type of event.
template isValidEventListener(T) {
	enum bool isValidEventListener = isCallable!T && ParameterTypeTuple!(T).length == 1;
}

private enum backingSize = (void*).sizeof + hash_t.sizeof;

/// Calls this function once every time the event system is idle
public void addOnIdle(T)(T t) if(isCallable!T && ParameterTypeTuple!(T).length == 0) {
	idleHandlers ~= wrap(t);
}

/// Removes an idle handler (added with addOnIdle)
public void removeOnIdle(T)(T t) if(isCallable!T && ParameterTypeTuple!(T).length == 0) {
	auto pair = getPtrPair(t);
	foreach(idx, listener; idleHandlers) {
		if(listener.matches(pair)) {
			idleHandlers = idleHandlers[0 .. idx] ~ idleHandlers[idx + 1 .. $];
			break;
		}
	}
}

/// Sends an exit event to the loop. The loop will break when it sees this event, ignoring any events after that point.
public void exit() {
	ubyte[backingSize] bufferBacking = 0; // a null message means exit...

	writeToEventPipe(bufferBacking);
}

void writeToEventPipe(ubyte[backingSize] bufferBacking) {
	ubyte[] buffer = bufferBacking[];
	while(buffer.length) {
		auto written = unix.write(pipes[1], buffer.ptr, buffer.length);
		if(written == 0)
			assert(0); // wtf
		else if(written == -1) {
			if(errno == EAGAIN || errno == EWOULDBLOCK) {
				// this should never happen here, because the messages
				// are virtually guaranteed to be smaller than the pipe buffer
				// ...unless there's like a thousand messages, which is a WTF anyway
				import std.string;
				assert(0, format("EAGAIN on %d", buffer.length));
			} else
				throw new Exception("write");
		} else {
			assert(written <= buffer.length);
			buffer = buffer[written .. $];
		}
	}
}

/// Adds an event listener. Event listeners must be functions that take exactly one argument.
public void addListener(T)(T t) if(isValidEventListener!T) {
	auto hash = typehash!(ParameterTypeTuple!(T)[0]);
	listeners[typehash!(ParameterTypeTuple!(T)[0])] ~= wrap(t);
}

/// Removes an event listener. Returns true if the event was actually found.
public bool removeListener(T)(T t) if(isValidEventListener!T) {
	auto hash = typehash!(ParameterTypeTuple!(T)[0]);
	auto list = hash in listeners;

	auto pair = getPtrPair(t);

	if(list !is null)
	foreach(idx, ref listener; *list) {
		if(listener.matches(pair)) {
			(*list) = (*list)[0 .. idx] ~ (*list)[idx + 1 .. $];
			return true;
		}
	}
	return false;
}

/// Sends a message to the listeners immediately, bypassing the event loop
public void sendSync(T)(T t) {
	auto hash = typehash!T;
	auto ptr  = cast(void*) &t;
	dispatchToListenerWithPtr(hash, ptr);
}

/// Send a message to the event loop
public void send(T)(T t) {
	// FIXME: we need to cycle the buffer position back so we can reuse this as the message is received
	// (if you want to keep a message, it is your responsibility to make your own copy, unless it is a pointer itself)
	//static ubyte[1024] copyBuffer;
	//static size_t copyBufferPosition;

	// for now we'll use the gc
	size_t copyBufferPosition = 0;
	auto copyBuffer = new ubyte[](T.sizeof);


	auto hash = typehash!T;
	//auto ptr  = (cast(void*) &t);

	// we have to copy the data off the stack so the pointer is still usable later
	// we use a static buffer to avoid more allocations
	// (if the data is big, it probably isn't on the stack anyway. hopefully!)
	auto ptr = cast(void*) (copyBuffer.ptr + copyBufferPosition);

	copyBuffer[copyBufferPosition .. copyBufferPosition + T.sizeof] = (cast(ubyte*)(&t))[0 .. T.sizeof];
	copyBufferPosition += T.sizeof;

	// then we send it as a hash+ptr pair

	ubyte[hash.sizeof + ptr.sizeof] buffer;
	buffer[0 .. hash.sizeof] = (cast(ubyte*)(&hash))[0 .. hash.sizeof];
	buffer[hash.sizeof .. $] = (cast(ubyte*)(&ptr ))[0 .. ptr .sizeof];

	writeToEventPipe(buffer);
}

/// Runs the loop, dispatching events to registered listeners as they come in
public void loop() {
	// get whatever is in there now, so we are clear for edge triggering
	if(readFromEventPipe() == false)
		return; // already got an exit

	loopImplementation();
}

public template isValidFileEventDispatcherHandler(T, FileType) {
	static if(is(T == typeof(null)))
		enum bool isValidFileEventDispatcherHandler = true;
	else {
		enum bool isValidFileEventDispatcherHandler = (
			is(T == typeof(null))
			||
			(
				isCallable!T
				&&
				(ParameterTypeTuple!(T).length == 0 ||
					(ParameterTypeTuple!(T).length == 1 && is(ParameterTypeTuple!(T)[0] == FileType)))
			)
		);
	}
}

private template templateCheckHelper(bool condition, string error) {
	static if(!condition) {
		static assert(0, error);
	}
	enum bool templateCheckHelper = condition;
}

/// Since the lowest level event for files only allows one handler, but can send events that require a variety of different responses,
/// the FileEventDispatcher is available to make this easer.
///
/// Instead of filtering yourself, you can add files to one of these with handlers for read, write, and error on that specific handle.
/// These handlers must take either zero arguments or exactly one argument, which will be the file being handled.
public struct FileEventDispatcher {
	private WrappedListener[3][OsFileHandle] listeners;
	private WrappedListener[3] defaultHandlers;

	private bool handlersActive;

	private void activateHandlers() {
		if(handlersActive)
			return;

		addListener(&lowLevelReadHandler);
		addListener(&lowLevelWriteHandler);
		addListener(&lowLevelErrorHandler);
		handlersActive = true;
	}

	private void deactivateHandlers() {
		if(!handlersActive)
			return;

		removeListener(&lowLevelErrorHandler);
		removeListener(&lowLevelWriteHandler);
		removeListener(&lowLevelReadHandler);
		handlersActive = false;
	}

	~this() {
		deactivateHandlers();
	}

	private WrappedListener getHandler(OsFileHandle fd, int idx)
		in { assert(idx >= 0 && idx < 3); }
	body {
		auto handlersPtr = fd in listeners;
		if(handlersPtr is null)
			return null; // we don't handle this function

		auto handler = (*handlersPtr)[idx];
		if(handler is null)
			handler = defaultHandlers[idx];

		return handler;
	}

	private void doHandler(OsFileHandle fd, int idx) {
		auto handler = getHandler(fd, idx);
		if(handler is null)
			return;
		handler.call(&fd);
	}

	private void lowLevelReadHandler(FileReadyToRead ev) {
		doHandler(ev.fd, 0);
	}

	private void lowLevelWriteHandler(FileReadyToWrite ev) {
		doHandler(ev.fd, 1);
	}

	private void lowLevelErrorHandler(FileError ev) {
		doHandler(ev.fd, 2);
	}

	/// You can add a file to listen to here. Files can be OS handles or Phobos types. The handlers can be null, meaning use the default
	/// (see: setDefaultHandler), or callables with zero or one argument. If they take an argument, it will be the file being handled at this time.
	public void addFile(FileType, ReadEventHandler, WriteEventHandler, ErrorEventHandler)
		(FileType handle, ReadEventHandler readEventHandler = null, WriteEventHandler writeEventHandler = null, ErrorEventHandler errorEventHandler = null)
		if(
			// FIXME: we should be able to take other Phobos types too, and correctly translate them up above
			templateCheckHelper!(is(FileType == OsFileHandle), "The FileType must be an operating system file handle")
			&&
			templateCheckHelper!(isValidFileEventDispatcherHandler!(ReadEventHandler, FileType), "The ReadEventHandler was not valid")
			&&
			templateCheckHelper!(isValidFileEventDispatcherHandler!(WriteEventHandler, FileType), "The WriteEventHandler was not valid")
			&&
			templateCheckHelper!(isValidFileEventDispatcherHandler!(ErrorEventHandler, FileType), "The ErrorEventHandler was not valid")
		)
	{
		if(!handlersActive)
			activateHandlers();

		WrappedListener[3] handlerSet;

		if(readEventHandler !is null)
			handlerSet[0] = wrap(readEventHandler);
		if(writeEventHandler !is null)
			handlerSet[0] = wrap(writeEventHandler);
		if(errorEventHandler !is null)
			handlerSet[0] = wrap(errorEventHandler);

		listeners[handle] = handlerSet;

		addFileToLoop(handle, FileEvents.read | FileEvents.write);
	}

	public void removeFile(OsFileHandle handle) {
		listeners.remove(handle);
	}

	/// What should this default handler work on?
	public enum HandlerDuty {
		read = 0, /// read events
		write = 1, /// write events
		error = 2, /// error events
	}

	/// Sets a default handler, used for file events where the custom handler on addFile was null
	public void setDefaultHandler(T)(HandlerDuty duty, T handler) if(isValidFileEventDispatcherHandler!(T, OsFileHandle)) {
		auto idx = cast(int) duty;

		defaultHandlers[idx] = wrap(handler);
	}

}

private FileEventDispatcher fileEventDispatcher;

/// To add listeners for file events on a specific file dispatcher, use this.
/// See FileEventDispatcher.addFile for the parameters
public void addFileEventListeners(T...)(T t) {// if(__traits(compiles, fileEventDispatcher.addFile(t))) {
	fileEventDispatcher.addFile!(T)(t);
}

/// Removes the file from event handling
public void removeFileEventListeners(OsFileHandle handle) {
	fileEventDispatcher.removeFile(handle);
}

/// If you add a file to the event loop, which events are you interested in?
public enum FileEvents : int {
	read = 1, /// the file is ready to be read from
	write = 2 /// the file is ready to be written to
}

/// Adds a file handle to the event loop. When the handle has data available to read
/// (if events & FileEvents.read) or write (if events & FileEvents.write), a message
/// FileReadyToRead and/or FileReadyToWrite will be dispatched.
///
/// note: the file you add should be nonblocking and you should be sure anything in the
/// buffers is already handled, since you won't get events for data that already exists

// FIXME: do we want to be able to pass a function pointer to be a special handler?
public void addFileToLoop(OsFileHandle fd, /* FileEvents */ int events) {
	if(insideLoop) {
		addFileToLoopImplementation(fd, events);
	} else {
		backFilesForLoop ~= BackFilesForLoop(fd, events);
	}
}

// this is so we can add files to the loop before the loop actually exists without the user
// needing to know that
private struct BackFilesForLoop {
	OsFileHandle file;
	int events;
}

private BackFilesForLoop[] backFilesForLoop;

// Make sure we're caught up on any files added before we started looping
private void addBackFilesToLoop() {
	assert(insideLoop);
	foreach(bf; backFilesForLoop) {
		addFileToLoop(bf.file, bf.events);
	}

	backFilesForLoop = null;
}

/*
	addOnIdle(function) is similar to calling setInterval(function, 0)

	auto id = setTimeout(function, wait)
	clearTimeout(id)

	auto id = setInterval(function, call at least after)
	clearInterval(0)

*/

private bool insideLoop = false;

version(linux) {
	void makeNonBlocking(int fd) {
		auto flags = fcntl.fcntl(fd, fcntl.F_GETFL, 0);
		if(flags == -1)
			throw new Exception("fcntl get");
		flags |= fcntl.O_NONBLOCK;
		auto s = fcntl.fcntl(fd, fcntl.F_SETFL, flags);
		if(s == -1)
			throw new Exception("fcntl set");
	}

	int epoll = -1;

	private void addFileToLoopImplementation(int fd, int events) {
		epoll_event ev;

		ev.events = EPOLL_EVENTS.EPOLLET; // edge triggered

		if(events & FileEvents.read)
			ev.events |= EPOLL_EVENTS.EPOLLIN;
		if(events & FileEvents.write)
			ev.events |= EPOLL_EVENTS.EPOLLOUT;
		ev.data.fd = fd;
		epoll_ctl(epoll, EPOLL_CTL_ADD, fd, &ev);
	}


	private void loopImplementation() {
		insideLoop = true;
		scope(exit)
			insideLoop = false;

		epoll = epoll_create1(0);
		if(epoll == -1)
			throw new Exception("epoll_create1");
		scope(exit) {
			unix.close(epoll);
			epoll = -1;
		}

		// anything done before the loop is open needs to be caught up on
		addBackFilesToLoop();

		addFileToLoop(pipes[0], FileEvents.read);

		epoll_event[16] events;

		outer_loop: for(;;) {
			auto nfds = epoll_wait(epoll, events.ptr, events.length, -1 /* wait forever, otherwise in milliseconds */);
			moreEvents:
			if(nfds == -1)
				throw new Exception("epoll_wait");

			foreach(n; 0 .. nfds) {
				auto fd = events[n].data.fd;
				if(fd == pipes[0]) {
					if(readFromEventPipe() == false)
						break outer_loop;
				} else {
					auto flags = events[n].events;
					if(flags & EPOLL_EVENTS.EPOLLIN)
						sendSync(FileReadyToRead(fd));
					if(flags & EPOLL_EVENTS.EPOLLOUT)
						sendSync(FileReadyToWrite(fd));
					if((flags & EPOLL_EVENTS.EPOLLERR) || (flags & EPOLL_EVENTS.EPOLLHUP))
						sendSync(FileError(fd));
				}
			}

			nfds = epoll_wait(epoll, events.ptr, events.length, 0 /* no wait */);
			if(nfds != 0)
				goto moreEvents;
			// no immediate events means we're idle for now, run those functions
			foreach(idleHandler; idleHandlers)
				idleHandler.call(null);
		}
	}
}

private bool readFromEventPipe() {
	hash_t hash;
	void* ptr;

	ubyte[hash.sizeof + ptr.sizeof] buffer;

	for(;;) {
		auto read = unix.read(pipes[0], buffer.ptr, buffer.length);
		if(read == -1) {
			if(errno == EAGAIN)
				break; // we got it all
			throw new Exception("read");
		} else if(read == 0) {
			assert(0); // this is never supposed to happen
		} else {
			assert(read == buffer.length);

			hash = * cast(hash_t*)(cast(void*) (buffer[0 .. hash_t.sizeof]));
			ptr  = * cast(void** )(cast(void*) (buffer[hash_t.sizeof .. hash_t.sizeof + (void*).sizeof]));

			if(hash == 0 && ptr is null)
				return false;

			dispatchToListenerWithPtr(hash, ptr);
		}
	}
	return true;
}

private interface WrappedListener {
	// to call the function...
	void call(void* ptr);

	// and this checks if it matches a given callable, used for removing listeners
	bool matches(void*[2] pair);
}

private WrappedListener wrap(T)(T t) {
	static if(is(T == typeof(null)))
		return null;
	else {
		return new class WrappedListener {
			override void call(void* ptr) {
				enum arity = ParameterTypeTuple!(T).length;
				static if(arity == 1)
					t(*(cast(ParameterTypeTuple!(T)[0]*) ptr));
				else static if(arity == 0)
					t();
				else static assert(0, "bad number of arguments");
			}

			override bool matches(void*[2] pair) {
				return pair == getPtrPair(t);
			}
		};
	}
}

private void*[2] getPtrPair(T)(T t) {
	void* funcptr, frameptr;
	static if(is(T == delegate)) {
		funcptr = cast(void*) t.funcptr;
		frameptr = t.ptr;
	} else static if(is(T == function)) {
		// FIXME: why doesn't it use this branch when given a function?
		funcptr = cast(void*) t;
		frameptr = null;
	} else {
		// FIXME: perhaps we should use something else...
		funcptr = cast(void*) t;
		frameptr = null;
	}

	return [funcptr, frameptr];
}

private void dispatchToListenerWithPtr(hash_t hash, void* ptr) {
	auto funclist = hash in listeners;
	if(funclist is null)
		return;
	foreach(func; *funclist) {
		if(func !is null)
			func.call(ptr);
	}
}

import unix = core.sys.posix.unistd;
import fcntl = core.sys.posix.fcntl;
import core.stdc.errno;
alias int OsFileHandle;
private int[2] pipes;
private void openEventPipes() {
	unix.pipe(pipes);
	makeNonBlocking(pipes[0]);
	makeNonBlocking(pipes[1]);
}
static this() {
	openEventPipes();
}

/* **** */
// system events

// FIXME: we probably want some kind of mid level events that dispatch based on file handle too; a better addFileToLoop might have delegates for each type of event right then and there. But this should not be required because such might be too fat and slow for certain applications

/// This is a low level event that is dispatched when a listened file (see: addFileToLoop) is ready to be read
/// You should read as much as possible without blocking from the file now, as a future event may not be fired for left over data
struct FileReadyToRead {
	OsFileHandle fd; // file handle
}

/// This is a low level event that is dispatched when a listened file (see: addFileToLoop) is ready to be written to
struct FileReadyToWrite {
	OsFileHandle fd; // file handle;
}

/// This is a low level event that is dispatched when a listened file (see: addFileToLoop) has an error
struct FileError {
	OsFileHandle fd; // file handle;
}

/* **** */
// epoll

version(linux) {
	extern(C):

	alias int c_int; // FIXME for 64 bit

	alias uint uint32_t;
	alias ulong uint64_t;

	union epoll_data {
		void    *ptr;
		int      fd;
		uint32_t u32;
		uint64_t u64;
	}

	struct epoll_event {
		uint32_t   events;    /* Epoll events */
		epoll_data data;      /* User data variable */
	}

	enum EPOLL_CTL_ADD = 1;
	enum EPOLL_CTL_DEL = 2;
	enum EPOLL_CTL_MOD = 3;


	import std.conv : octal;
	enum {
		EPOLL_CLOEXEC = octal!"2000000",
		EPOLL_NONBLOCK = octal!"4000"
	}

	enum EPOLL_EVENTS {
		EPOLLIN = 0x001,
		EPOLLPRI = 0x002,
		EPOLLOUT = 0x004,
		EPOLLRDNORM = 0x040,
		EPOLLRDBAND = 0x080,
		EPOLLWRNORM = 0x100,
		EPOLLWRBAND = 0x200,
		EPOLLMSG = 0x400,
		EPOLLERR = 0x008,
		EPOLLHUP = 0x010,
		EPOLLRDHUP = 0x2000,
		EPOLLONESHOT = (1 << 30),
		EPOLLET = (1 << 31)
	}

	int epoll_create1(int flags);
	int epoll_ctl(int epfd, int op, int fd, epoll_event* event);
	int epoll_wait(int epfd, epoll_event* events, int maxevents, int timeout);
}

/* **** */
// test program

struct Test {}
import std.stdio;

void listenInt(int a) {
	writeln("here lol");
}

version(eventloop_demo)
void main() {
/*
	addFileToLoop(0, FileEvents.read); // add stdin data to our event loop

	addListener((FileReadyToRead fr) {
		ubyte[100] buffer;
		auto got = unix.read(0, buffer.ptr, buffer.length);
		if(got == -1)
			throw new Exception("wtf");
		if(got == 0)
			exit;
		else
			writeln(fr.fd, " sent ", cast(string) buffer[0 .. got]);
	});
*/
	FileEventDispatcher dispatcher;

	dispatcher.addFile(0, (int fd) {
		ubyte[100] buffer;
		auto got = unix.read(fd, buffer.ptr, buffer.length);
		if(got == -1)
			throw new Exception("wtf");
		if(got == 0)
			exit;
		else
			writeln(fd, " sent ", cast(string) buffer[0 .. got]);
	}, null, null);

	addListener(&listenInt);
	sendSync(10);
	removeListener(&listenInt);
	addListener(delegate void(int a) { writeln("got ", a); });
	addListener(delegate void(File a) { writeln("got ", a); });
	send(20);
	send(stdin);

	loop();
}

/* **** */
// hash function

// the following is copy/pasted from druntime src/rt/util/hash.d
// is that available as an import somewhere in the stdlib?


version( X86 )
    version = AnyX86;
version( X86_64 )
    version = AnyX86;
version( AnyX86 )
    version = HasUnalignedOps;


@trusted pure nothrow
hash_t hashOf( const (void)* buf, size_t len, hash_t seed = 0 )
{
    /*
     * This is Paul Hsieh's SuperFastHash algorithm, described here:
     *   http://www.azillionmonkeys.com/qed/hash.html
     * It is protected by the following open source license:
     *   http://www.azillionmonkeys.com/qed/weblicense.html
     */
    static uint get16bits( const (ubyte)* x ) pure nothrow
    {
        // CTFE doesn't support casting ubyte* -> ushort*, so revert to
        // per-byte access when in CTFE.
        version( HasUnalignedOps )
        {
            if (!__ctfe)
                return *cast(ushort*) x;
        }

        return ((cast(uint) x[1]) << 8) + (cast(uint) x[0]);
    }

    // NOTE: SuperFastHash normally starts with a zero hash value.  The seed
    //       value was incorporated to allow chaining.
    auto data = cast(const (ubyte)*) buf;
    auto hash = seed;
    int  rem;

    if( len <= 0 || data is null )
        return 0;

    rem = len & 3;
    len >>= 2;

    for( ; len > 0; len-- )
    {
        hash += get16bits( data );
        auto tmp = (get16bits( data + 2 ) << 11) ^ hash;
        hash  = (hash << 16) ^ tmp;
        data += 2 * ushort.sizeof;
        hash += hash >> 11;
    }

    switch( rem )
    {
    case 3: hash += get16bits( data );
            hash ^= hash << 16;
            hash ^= data[ushort.sizeof] << 18;
            hash += hash >> 11;
            break;
    case 2: hash += get16bits( data );
            hash ^= hash << 11;
            hash += hash >> 17;
            break;
    case 1: hash += *data;
            hash ^= hash << 10;
            hash += hash >> 1;
            break;
     default:
            break;
    }

    /* Force "avalanching" of final 127 bits */
    hash ^= hash << 3;
    hash += hash >> 5;
    hash ^= hash << 4;
    hash += hash >> 17;
    hash ^= hash << 25;
    hash += hash >> 6;

    return hash;
}


