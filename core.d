/++
	Shared core functionality including exception helpers, library loader, event loop, and possibly more.
+/
module arsd.core;

/++
	This is a dummy type to indicate the end of normal arguments and the beginning of the file/line inferred args.
	It is meant to ensure you don't accidentally send a string that is interpreted as a filename when it was meant
	to be a normal argument to the function and trigger the wrong overload.
+/
struct ArgSentinel {}



version(Windows)
struct WCharzBuffer {
	wchar[] buffer;
	wchar[256] staticBuffer = void;

	size_t length() {
		return buffer.length;
	}

	wchar* ptr() {
		return buffer.ptr;
	}

	wchar[] slice() {
		return buffer;
	}

	void copyInto(R)(ref R r) {
		static if(is(R == wchar[N], size_t N)) {
			r[0 .. this.length] = slice[];
			r[this.length] = 0;
		} else static assert(0, "can only copy into wchar[n], not " ~ R.stringof);
	}

	/++
		conversionFlags = [WindowsStringConversionFlags]
	+/
	this(in char[] data, int conversionFlags = 0) {
		conversionFlags |= WindowsStringConversionFlags.zeroTerminate; // this ALWAYS zero terminates cuz of its name
		auto sz = sizeOfConvertedWstring(data, conversionFlags);
		if(sz > staticBuffer.length)
			buffer = new wchar[](sz);
		else
			buffer = staticBuffer[];

		buffer = makeWindowsString(data, buffer, conversionFlags);
	}
}

version(Windows)
int sizeOfConvertedWstring(in char[] s, int conversionFlags) {
	int size = 0;

	if(conversionFlags & WindowsStringConversionFlags.convertNewLines) {
		// need to convert line endings, which means the length will get bigger.

		// BTW I betcha this could be faster with some simd stuff.
		char last;
		foreach(char ch; s) {
			if(ch == 10 && last != 13)
				size++; // will add a 13 before it...
			size++;
			last = ch;
		}
	} else {
		// no conversion necessary, just estimate based on length
		/*
			I don't think there's any string with a longer length
			in code units when encoded in UTF-16 than it has in UTF-8.
			This will probably over allocate, but that's OK.
		*/
		size = cast(int) s.length;
	}

	if(conversionFlags & WindowsStringConversionFlags.zeroTerminate)
		size++;

	return size;
}

version(Windows)
enum WindowsStringConversionFlags : int {
	zeroTerminate = 1,
	convertNewLines = 2,
}

version(Windows)
class WindowsApiException : object.Exception {
	char[256] buffer;
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		assert(msg.length < 100);

		auto error = GetLastError();
		buffer[0 .. msg.length] = msg;
		buffer[msg.length] = ' ';

		int pos = cast(int) msg.length + 1;

		if(error == 0)
			buffer[pos++] = '0';
		else {

			auto ec = error;
			auto init = pos;
			while(ec) {
				buffer[pos++] = (ec % 10) + '0';
				ec /= 10;
			}

			buffer[pos++] = ' ';

			size_t size = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), &(buffer[pos]), cast(DWORD) buffer.length - pos, null);

			pos += size;
		}


		super(cast(string) buffer[0 .. pos], file, line, next);
	}
}

class ErrnoApiException : object.Exception {
	char[256] buffer;
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		assert(msg.length < 100);

		import core.stdc.errno;
		auto error = errno;
		buffer[0 .. msg.length] = msg;
		buffer[msg.length] = ' ';

		int pos = cast(int) msg.length + 1;

		if(error == 0)
			buffer[pos++] = '0';
		else {
			auto init = pos;
			while(error) {
				buffer[pos++] = (error % 10) + '0';
				error /= 10;
			}
			for(int i = 0; i < (pos - init) / 2; i++) {
				char c = buffer[i + init];
				buffer[i + init] = buffer[pos - (i + init) - 1];
				buffer[pos - (i + init) - 1] = c;
			}
		}


		super(cast(string) buffer[0 .. pos], file, line, next);
	}

}

version(Windows)
wchar[] makeWindowsString(in char[] str, wchar[] buffer, int conversionFlags = WindowsStringConversionFlags.zeroTerminate) {
	if(str.length == 0)
		return null;

	int pos = 0;
	dchar last;
	foreach(dchar c; str) {
		if(c <= 0xFFFF) {
			if((conversionFlags & WindowsStringConversionFlags.convertNewLines) && c == 10 && last != 13)
				buffer[pos++] = 13;
			buffer[pos++] = cast(wchar) c;
		} else if(c <= 0x10FFFF) {
			buffer[pos++] = cast(wchar)((((c - 0x10000) >> 10) & 0x3FF) + 0xD800);
			buffer[pos++] = cast(wchar)(((c - 0x10000) & 0x3FF) + 0xDC00);
		}

		last = c;
	}

	if(conversionFlags & WindowsStringConversionFlags.zeroTerminate) {
		buffer[pos] = 0;
	}

	return buffer[0 .. pos];
}

version(Windows)
char[] makeUtf8StringFromWindowsString(in wchar[] str, char[] buffer) {
	if(str.length == 0)
		return null;

	auto got = WideCharToMultiByte(CP_UTF8, 0, str.ptr, cast(int) str.length, buffer.ptr, cast(int) buffer.length, null, null);
	if(got == 0) {
		if(GetLastError() == ERROR_INSUFFICIENT_BUFFER)
			throw new object.Exception("not enough buffer");
		else
			throw new object.Exception("conversion"); // FIXME: GetLastError
	}
	return buffer[0 .. got];
}

version(Windows)
string makeUtf8StringFromWindowsString(in wchar[] str) {
	char[] buffer;
	auto got = WideCharToMultiByte(CP_UTF8, 0, str.ptr, cast(int) str.length, null, 0, null, null);
	buffer.length = got;

	// it is unique because we just allocated it above!
	return cast(string) makeUtf8StringFromWindowsString(str, buffer);
}

version(Windows)
string makeUtf8StringFromWindowsString(wchar* str) {
	char[] buffer;
	auto got = WideCharToMultiByte(CP_UTF8, 0, str, -1, null, 0, null, null);
	buffer.length = got;

	got = WideCharToMultiByte(CP_UTF8, 0, str, -1, buffer.ptr, cast(int) buffer.length, null, null);
	if(got == 0) {
		if(GetLastError() == ERROR_INSUFFICIENT_BUFFER)
			throw new object.Exception("not enough buffer");
		else
			throw new object.Exception("conversion"); // FIXME: GetLastError
	}
	return cast(string) buffer[0 .. got];
}

int findIndexOfZero(in wchar[] str) {
	foreach(idx, wchar ch; str)
		if(ch == 0)
			return cast(int) idx;
	return cast(int) str.length;
}
int findIndexOfZero(in char[] str) {
	foreach(idx, char ch; str)
		if(ch == 0)
			return cast(int) idx;
	return cast(int) str.length;
}

package deprecated struct Exception {}

/++

+/
class ArsdException : object.Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		super(msg, file, line, next);
	}
	final override string toString() {
		return super.toString();
	}
	// msg?
}

version(Windows) {
	import core.sys.windows.windows;

	import core.sys.windows.windef;

	/++
		throw new Win32ApiException("MsgWaitForMultipleObjectsEx", GetLastError())
	+/
	class Win32ApiException : object.Exception {
		this(string operation, DWORD errorCode, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
			import core.sys.windows.windows;

			wchar[256] buffer;
			auto size = FormatMessageW(
				FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
				null,
				errorCode,
				MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
				buffer.ptr,
				buffer.length,
				null
			);

			super(operation ~ " failed with code " ~ makeUtf8StringFromWindowsString(buffer[0 .. size]), file, line, next);
		}
	}

	template Win32Enforce(alias fn) {
		static if(is(typeof(fn) Return == return))
		static if(is(typeof(fn) Params == __parameters)) {
			static if(is(Return == BOOL))
				enum errorValue = false;
			else
				enum errorValue = cast(DWORD) 0xffffffff;

			Return Win32Enforce(Params params, ArgSentinel sentinel = ArgSentinel.init, string file = __FILE__, size_t line = __LINE__) {
				import core.sys.windows.winbase;

				Return value = fn(params);

				if(value == errorValue) {
					throw new Win32ApiException(__traits(identifier, fn), GetLastError(), file, line);
				}

				return value;
			}
		}
	}

}

/+


/+
	Druntime appears to have stuff for darwin, freebsd. I might have to add some for openbsd here and maybe netbsd if i care to test it.
+/

/+

	arsd_core_init(number_of_worker_threads)

	Building-block things wanted for the event loop integration:
		* ui
			* windows
			* terminal / console
		* generic
			* adopt fd
			* adopt windows handle
		* shared lib
			* load
		* timers (relative and real time)
			* create
			* update
			* cancel
		* file/directory watches
			* file created
			* file deleted
			* file modified
		* file ops
			* open
			* close
			* read
			* write
			* seek
			* sendfile on linux
			* let completion handlers run in the io worker thread instead of signaling back
		* pipe ops (anonymous or named)
			* create
			* read
			* write
			* get info about other side of the pipe
		* network ops (stream + datagram, ip, ipv6, unix)
			* address look up
			* connect
			* start tls
			* listen
			* send
			* receive
			* get peer info
		* process ops
			* spawn
			* notifications when it is terminated or fork or execs
			* send signal
			* i/o pipes
		* thread ops (isDaemon?)
			* spawn
			* talk to its event loop
			* termination notification
		* signals
			* ctrl+c is the only one i really care about but the others might be made available too. sigchld needs to be done as an impl detail of process ops.
		* custom messages
			* should be able to send messages from finalizers...

		* want to make sure i can stream stuff on top of it all too.

		========

		These things all refer back to a task-local thing that queues the tasks. If it is a fiber, it uses that
		and if it is a thread it uses that...

		tls IArsdCoreEventLoop curentTaskInterface; // this yields on the wait for calls. the fiber swapper will swap this too.
		tls IArsdCoreEventLoop currentThreadInterface; // this blocks on the event loop

		shared IArsdCoreEventLoop currentProcessInterface; // this dispatches to any available thread
+/


/+
	You might have configurable tasks that do not auto-start, e.g. httprequest. maybe @mustUse on those

	then some that do auto-start, e.g. setTimeout


	timeouts: duration, MonoTime, or SysTime? duration is just a timer monotime auto-adjusts the when, systime sets a real time timerfd

	tasks can be set to:
		thread affinity - this, any, specific reference
		reports to - defaults to this, can also pass down a parent reference. if reports to dies, all its subordinates are cancelled.


	you can send a message to a task... maybe maybe just to a task runner (which is itself a task?)

	auto file = readFile(x);
	auto timeout = setTimeout(y);
	auto completed = waitForFirstToCompleteThenCancelOthers(file, timeout);
	if(completed == 0) {
		file....
	} else {
		timeout....
	}

	/+
		A task will run on a thread (with possible migration), and report to a task.
	+/

	// a compute task is run on a helper thread
	auto task = computeTask((shared(bool)* cancellationRequested) {
		// or pass in a yield thing... prolly a TaskController which has cancellationRequested and yield controls as well as send message to parent (sync or async)

		// you'd periodically send messages back to the parent
	}, RunOn.AnyAvailable, Affinity.CanMigrate);

	auto task = Task((TaskController controller) {
		foreach(x, 0 .. 1000) {
			if(x % 10 == 0)
				controller.yield(); // periodically yield control, which also checks for cancellation for us
			// do some work

			controller.sendMessage(...);
			controller.sendProgress(x); // yields it for a foreach stream kind of thing
		}

		return something; // automatically sends the something as the result in a TaskFinished message
	});

	foreach(item; task) // waitsForProgress, sendProgress sends an item and the final return sends an item
		{}


		see ~/test/task.d

	// an io task is run locally via the event loops
	auto task2 = ioTask(() {

	});



	waitForEvent
+/

/+
	Most functions should prolly take a thread arg too, which defaults
	to this thread, but you can also pass it a reference, or a "any available" thing.

	This can be a ufcs overload
+/

import core.time;

interface SemiSynchronousTask {

}

struct TimeoutCompletionResult {
	bool completed;

	bool opCast(T : bool)() {
		return completed;
	}
}

struct Timeout {
	void reschedule(Duration when) {

	}

	void cancel() {

	}

	TimeoutCompletionResult waitForCompletion() {
		return TimeoutCompletionResult(false);
	}
}

Timeout setTimeout(void delegate() dg, int msecs, int permittedJitter = 20) {
	return Timeout.init;
}

void clearTimeout(Timeout timeout) {
	timeout.cancel();
}

void createInterval() {}
void clearInterval() {}

/++
	Schedules a task at the given wall clock time.
+/
void scheduleTask() {}

struct IoOperationCompletionResult {
	enum Status {
		cancelled,
		completed
	}

	Status status;

	int error;
	int bytesWritten;

	bool opCast(T : bool)() {
		return status == Status.completed;
	}
}

struct IoOperation {
	void cancel() {}

	IoOperationCompletionResult waitForCompletion() {
		return IoOperationCompletionResult.init;
	}

	// could contain a scoped class in here too so it stack allocated
}

Result waitForFirstToComplete(Operation[]...) {}

IoOperation read(IoHandle handle, ubyte[] buffer

/+
	class IoOperation {}

	// an io operation and its buffer must not be modified or freed
	// in between a call to enqueue and a call to waitForCompletion
	// if you used the whenComplete callback, make sure it is NOT gc'd or scope thing goes out of scope in the mean time
	// if its dtor runs, it'd be forced to be cancelled...

	scope IoOperation op = new IoOperation(buffer_size);
	op.start();
	op.waitForCompletion();
+/

/+
	will want:
		read, write
		send, recv

		cancel

		open file, open (named or anonymous) pipe, open process
		connect, accept
		SSL
		close

		postEvent
		postAPC? like run in gui thread / async
		waitForEvent ? needs to handle a timeout and a cancellation. would only work in the fiber task api.

		waitForSuccess

		interrupt handler

		onPosixReadReadiness
		onPosixWriteReadiness

		onWindowsHandleReadiness
			- but they're one-offs so you gotta reregister for each event
+/



/+
arsd.core.uda

you define a model struct with the types you want to extract

you get it with like Model extract(Model, UDAs...)(Model default)

defaultModel!alias > defaultModel!Type(defaultModel("identifier"))










so while i laid there sleep deprived i did think a lil more on some uda stuff. it isn't especially novel but a combination of a few other techniques

you might be like

struct MyUdas {
    DbName name;
    DbIgnore ignore;
}

elsewhere

foreach(alias; allMembers) {
     auto udas = getUdas!(MyUdas, __traits(getAttributes, alias))(MyUdas(DbName(__traits(identifier, alias))));
}


so you pass the expected type and the attributes as the template params, then the runtime params are the default values for the given types

so what the thing does essentially is just sets the values of the given thing to the udas based on type then returns the modified instance

so the end result is you keep the last ones. it wouldn't report errors if multiple things added but it p simple to understand, simple to document (even though the default values are not in the struct itself, you can put ddocs in them), and uses the tricks to minimize generated code size
+/

+/
