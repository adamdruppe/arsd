/++
	My old event loop helper library for Linux. Not recommended for new projects.

	History:
		Originally written January 2013, then basically abandoned in 2016.

		Some of public interface rewritten to use [arsd.core] and the rest deleted on October 28, 2026 (v13.0). I still suggest you not use this anymore though.
+/
module arsd.eventloop;

import arsd.core;

import std.traits;

/// Send a message to the event loop
public void send(T)(T t) {
	getThisThreadEventLoop.onNextTick(() { sendSync(t); });
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


// we send custom events as type+pointer pairs. The type is sent as a hash of the mangled name, so we get a unique integer for anything, including any user defined types.
template typehash(T...) {
	void delegate(T) tmp;
	enum typehash = hashOf(tmp.mangleof.ptr, tmp.mangleof.length);
}

private WrappedListener[][hash_t] listeners;
private WrappedListener[] idleHandlers;

private ICoreEventLoop.UnregisterToken arsdCoreIdleHandler;

/// Valid event listeners must be callable and take exactly one argument. The type of argument determines the type of event.
template isValidEventListener(T) {
	enum bool isValidEventListener = isCallable!T && ParameterTypeTuple!(T).length == 1;
}

private enum backingSize = (void*).sizeof + hash_t.sizeof;

/// Calls this function once every time the event system is idle
public void addOnIdle(T)(T t) if(isCallable!T && ParameterTypeTuple!(T).length == 0) {
	idleHandlers ~= wrap(t);

	if(idleHandlers.length == 1)
		arsdCoreIdleHandler = getThisThreadEventLoop().addDelegateOnLoopIteration(&runIdleHandlers);
}

private bool runIdleHandlers() {
	foreach(idleHandler; idleHandlers)
		idleHandler.call(null);
	return false;
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

	if(idleHandlers.length == 0) {
		if(arsdCoreIdleHandler)
			arsdCoreIdleHandler.unregister();
	}
}

/// An opaque type to reference an active timer
struct TimerHandle {
	UserModeTimer umt;
}

/// Sets a timer, one-shot by default. Count tells how many times the timer will fire. Set to zero for a continuously firing timer
public TimerHandle setTimeout(T)(T t, int msecsWait, int count = 1) if(isCallable!T && ParameterTypeTuple!(T).length == 0) {
	import core.time;
	UserModeTimer umt;
	umt = new UserModeTimer(() {
		t();
		if(count > 0) {
			count--;
			if(count <= 0)
				umt.cancel();
		}
	}, msecs(msecsWait), count == 1 ? false : true /* recurring */);

	return TimerHandle(umt);
}

/// Sets a continuously firing interval. It will call the function as close to the interval as it can, but it won't let triggers stack up.
public TimerHandle setInterval(T)(T t, int msecsInterval)  if(isCallable!T && ParameterTypeTuple!(T).length == 0) {
	return setTimeout(t, msecsInterval, 0);
}

/// Clears a timer
public void clearTimeout(TimerHandle handle) {
	handle.umt.cancel();
}

public void clearInterval(TimerHandle handle) {
	clearTimeout(handle);
}

/// Sends an exit event to the loop. The loop will break when it sees this event, ignoring any events after that point.
public void exit() @nogc {
	auto hack = function() {
		getThisThreadEventLoop().onNextTick(() { getThisThreadEventLoop().exitApplication(); });
	};
	auto lol = cast(void function() @nogc) hack;
	lol();
}

/// Sends a message to the listeners immediately, bypassing the event loop
public void sendSync(T)(T t) {
	auto hash = typehash!T;
	auto ptr  = cast(void*) &t;
	dispatchToListenerWithPtr(hash, ptr);
}

import core.stdc.stdlib;

/// Runs the loop, dispatching events to registered listeners as they come in
public void loop() {
	getThisThreadEventLoop().run(() => false);
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
				((ParameterTypeTuple!(T).length == 1 && is(ParameterTypeTuple!(T)[0] == FileType)))
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



/* **** */
// hash function

// the following is copy/pasted from druntime src/rt/util/hash.d
// is that available as an import somewhere in the stdlib?

version( X86 )
    version = HasUnalignedOps;
version( X86_64 )
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


version(Posix):

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
		addListener(&lowLevelHupHandler);
		addListener(&lowLevelWriteHandler);
		addListener(&lowLevelErrorHandler);
		handlersActive = true;
	}

	private void deactivateHandlers() {
		if(!handlersActive)
			return;

		removeListener(&lowLevelErrorHandler);
		removeListener(&lowLevelHupHandler);
		removeListener(&lowLevelWriteHandler);
		removeListener(&lowLevelReadHandler);
		handlersActive = false;
	}

	~this() {
		deactivateHandlers();
	}

	private WrappedListener getHandler(OsFileHandle fd, int idx)
		in { assert(idx >= 0 && idx < 3); }
	do {
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
	private void lowLevelHupHandler(FileHup ev) {
		doHandler(ev.fd, 2);
	}

	/// You can add a file to listen to here. Files can be OS handles or Phobos types. The handlers can be null, meaning use the default
	/// (see: setDefaultHandler), or callables with zero or one argument. If they take an argument, it will be the file being handled at this time.
	public void addFile(FileType, ReadEventHandler, WriteEventHandler, ErrorEventHandler)
		(FileType handle, ReadEventHandler readEventHandler = null, WriteEventHandler writeEventHandler = null, ErrorEventHandler errorEventHandler = null, bool edgeTriggered = true)
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

		int events;

		if(readEventHandler !is null) {
			handlerSet[0] = wrap(readEventHandler);
			events |= FileEvents.read;
		}
		if(writeEventHandler !is null) {
			handlerSet[1] = wrap(writeEventHandler);
			events |= FileEvents.write;
		}
		if(errorEventHandler !is null)
			handlerSet[2] = wrap(errorEventHandler);

		listeners[handle] = handlerSet;


		// addFileToLoop(handle, events, edgeTriggered);
		// FIXME: finish this section

		assert(readEventHandler is null || writeEventHandler is null); // arsd.core doesn't really support both rn because it doesn't actually edge trigger FIXME
		auto tok = getThisThreadEventLoop().registerFd(handle);
		static if(!is(ReadEventHandler == typeof(null))) {
			tok.subscribeToEvents(true, false, true, new CallbackHelper(() { readEventHandler(handle); }));
		}
		else static if(!is(WriteEventHandler == typeof(null)))
			static assert(0);

		cast(void) (unregisterTokens[handle] = tok);
	}

	public void removeFile(OsFileHandle handle) {
		listeners.remove(handle);
		unregisterTokens[handle].unregister();
		unregisterTokens.remove(handle);
	}

	ICoreEventLoop.UnregisterToken[OsFileHandle] unregisterTokens;

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

import unix = core.sys.posix.unistd;
import fcntl = core.sys.posix.fcntl;
import core.stdc.errno;
alias int OsFileHandle;

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

/// This is a low level event that is dispatched when a listened file (see: addFileToLoop) has a hang up event
struct FileHup {
	OsFileHandle fd; // file handle;
}

private FileEventDispatcher fileEventDispatcher;

/// To add listeners for file events on a specific file dispatcher, use this.
/// See FileEventDispatcher.addFile for the parameters
///
/// When you get an event that a file is ready, you MUST read all of it until
/// exhausted (that is, read until it would block - you could use select() for
/// this or set the file to nonblocking mode) because you only get an event
/// when the state changes. Failure to read it all will leave whatever is left
/// in the buffer sitting there unnoticed until even more stuff comes in.
///
/// Bugs: As of October 28, 2026 this ONLY supports read listeners and they MUST have a single parameter, `int fd`. This might change back to the way it was in the past.
public void addFileEventListeners(T...)(T t) {// if(__traits(compiles, fileEventDispatcher.addFile(t))) {
	fileEventDispatcher.addFile(t);
}

/// Removes the file from event handling. you MUST do this while the file is still open! if you close it first, this will throw bad file descriptor
public void removeFileEventListeners(OsFileHandle handle) {
	fileEventDispatcher.removeFile(handle);
}

/// If you add a file to the event loop, which events are you interested in?
public enum FileEvents : int {
	read = 1, /// the file is ready to be read from
	write = 2, /// the file is ready to be written to
}

version(none) {


/// Adds a file handle to the event loop. When the handle has data available to read
/// (if events & FileEvents.read) or write (if events & FileEvents.write), a message
/// FileReadyToRead and/or FileReadyToWrite will be dispatched.
///
/// note: the file you add should be nonblocking and you should be sure anything in the
/// buffers is already handled, since you won't get events for data that already exists

// FIXME: do we want to be able to pass a function pointer to be a special handler?
public void addFileToLoop(OsFileHandle fd, /* FileEvents */ int events, bool edgeTriggered = true) {
	addFileToLoopImplementation(fd, events, edgeTriggered);
}


	private void addFileToLoopImplementation(int fd, int events, bool edgeTriggered = true) @system {
		epoll_event ev = void;

		ev.events = 0;

		// I don't remember why I made it edge triggered in the first
		// place as that requires a bit more care to do correctly and I don't
		// think I've ever taken that kind of care. I'm going to try switching it
		// to level triggered (the event fires whenever the loop goes through and
		// there's still data available) and see if things work better.

		// OK I'm turning it back on because otherwise unhandled events
		// cause an infinite loop. So when an event comes, you MUST starve
		// the read to get all your info in a timely fashion. Gonna document this.
		if(edgeTriggered)
			ev.events = EPOLLET; // edge triggered

		// Oh I think I know why I did this: if it is level triggered
		// and the data is not actually handled, it infinite loops
		// on it. So either way, the application needs to do its thing:
		// either consume all available data every single time it is
		// triggered - read until you get EAGAIN, OR make sure that
		// data is never ignored; that every trigger leads to at LEAST
		// ONE read.
		//
		// With writes, it is important to be extremely careful with
		// level triggered - a file is often ready to write, especially
		// if you aren't actually using it! I like to do blocking
		// writes with non-blocking reads, so any level-triggered epoll
		// on write is probably not what I want.
		//
		// Bottom line is this is a kinda leaky abstraction either way
		// and we all need to understand what is going on to make the
		// best of it. Also watch your CPU usage for infinite loops!

		if(events & FileEvents.read)
			ev.events |= EPOLLIN;
		if(events & FileEvents.write)
			ev.events |= EPOLLOUT;
		ev.data.fd = fd;
		epoll_ctl(epoll, EPOLL_CTL_ADD, fd, &ev);
	}
}

