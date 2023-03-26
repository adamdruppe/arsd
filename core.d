/++
	Shared core functionality including exception helpers, library loader, event loop, and possibly more. Maybe command line processor and uda helper and some basic shared annotation types.

	I'll probably move the url, websocket, and ssl stuff in here too as they are often shared.

	If you use this directly outside the arsd library, you might consider using `static import` since names in here are likely to clash with Phobos if you use them together. `static import` will let you easily disambiguate and avoid name conflict errors if I add more here. Some names even clash deliberately to remind me to avoid some antipatterns inside the arsd modules!

	History:
		Added March 2023 (dub v11.0). Several functions were migrated in here at that time, noted individually. Members without a note were added with the module.
+/
module arsd.core;

// see for useful info: https://devblogs.microsoft.com/dotnet/how-async-await-really-works/

import core.thread;
import core.volatile;
import core.atomic;
import core.time;

import core.stdc.errno;

import core.attribute;
static if(!__traits(hasMember, core.attribute, "mustuse"))
	enum mustuse;

// FIXME: add an arena allocator? can do task local destruction maybe.

// the three implementations are windows, epoll, and kqueue
version(Windows) {
	version=Arsd_core_windows;

	import core.sys.windows.windows;
	import core.sys.windows.windef;
} else version(linux) {
	version=Arsd_core_epoll;

	version=Arsd_core_has_cloexec;
} else version(FreeBSD) {
	version=Arsd_core_kqueue;

	import core.sys.freebsd.sys.event;
} else version(OSX) {
	version=Arsd_core_kqueue;

	import core.sys.darwin.sys.event;
}

version(Posix) {
	import core.sys.posix.signal;
}

// FIXME: the exceptions should actually give some explanatory text too (at least sometimes)

/+
	=========================
	GENERAL UTILITY FUNCTIONS
	=========================
+/

// enum stringz : const(char)* { init = null }

/++
	A wrapper around a `const(char)*` to indicate that it is a zero-terminated C string.
+/
struct stringz {
	private const(char)* raw;

	/++
		Wraps the given pointer in the struct. Note that it retains a copy of the pointer.
	+/
	this(const(char)* raw) {
		this.raw = raw;
	}

	/++
		Returns the original raw pointer back out.
	+/
	const(char)* ptr() const {
		return raw;
	}

	/++
		Borrows a slice of the pointer up to the zero terminator.
	+/
	const(char)[] borrow() const {
		if(raw is null)
			return null;

		const(char)* p = raw;
		int length;
		while(*p++) length++;

		return raw[0 .. length];
	}
}

/++
	This is a dummy type to indicate the end of normal arguments and the beginning of the file/line inferred args.  It is meant to ensure you don't accidentally send a string that is interpreted as a filename when it was meant to be a normal argument to the function and trigger the wrong overload.
+/
struct ArgSentinel {}

/++
	A trivial wrapper around C's malloc that creates a D slice. It multiples n by T.sizeof and returns the slice of the pointer from 0 to n.

	Please note that the ptr might be null - it is your responsibility to check that, same as normal malloc. Check `ret is null` specifically, since `ret.length` will always be `n`, even if the `malloc` failed.

	Remember to `free` the returned pointer with `core.stdc.stdlib.free(ret.ptr);`

	$(TIP
		I strongly recommend you simply use the normal garbage collector unless you have a very specific reason not to.
	)

	See_Also:
		[mallocedStringz]
+/
T[] mallocSlice(T)(size_t n) {
	import c = core.stdc.stdlib;

	return (cast(T*) c.malloc(n * T.sizeof))[0 .. n];
}

/++
	Uses C's malloc to allocate a copy of `original` with an attached zero terminator. It may return a slice with a `null` pointer (but non-zero length!) if `malloc` fails and you are responsible for freeing the returned pointer with `core.stdc.stdlib.free(ret.ptr)`.

	$(TIP
		I strongly recommend you use [CharzBuffer] or Phobos' [std.string.toStringz] instead unless there's a special reason not to.
	)

	See_Also:
		[CharzBuffer] for a generally better alternative. You should only use `mallocedStringz` where `CharzBuffer` cannot be used (e.g. when druntime is not usable or you have no stack space for the temporary buffer).

		[mallocSlice] is the function this function calls, so the notes in its documentation applies here too.
+/
char[] mallocedStringz(in char[] original) {
	auto slice = mallocSlice!char(original.length + 1);
	if(slice is null)
		return null;
	slice[0 .. original.length] = original[];
	slice[original.length] = 0;
	return slice;
}

/++
	Basically a `scope class` you can return from a function or embed in another aggregate.
+/
struct OwnedClass(Class) {
	ubyte[__traits(classInstanceSize, Class)] rawData;

	static OwnedClass!Class defaultConstructed() {
		OwnedClass!Class i = OwnedClass!Class.init;
		i.initializeRawData();
		return i;
	}

	private void initializeRawData() @trusted {
		if(!this)
			rawData[] = cast(ubyte[]) typeid(Class).initializer[];
	}

	this(T...)(T t) {
		initializeRawData();
		rawInstance.__ctor(t);
	}

	bool opCast(T : bool)() @trusted {
		return !(*(cast(void**) rawData.ptr) is null);
	}

	@disable this();
	@disable this(this);

	Class rawInstance() return @trusted {
		if(!this)
			throw new Exception("null");
		return cast(Class) rawData.ptr;
	}

	alias rawInstance this;

	~this() @trusted {
		if(this)
			.destroy(rawInstance());
	}
}



version(Posix)
package(arsd) void makeNonBlocking(int fd) {
	import core.sys.posix.fcntl;
	auto flags = fcntl(fd, F_GETFL, 0);
	if(flags == -1)
		throw new ErrnoApiException("fcntl get", errno);
	flags |= O_NONBLOCK;
	auto s = fcntl(fd, F_SETFL, flags);
	if(s == -1)
		throw new ErrnoApiException("fcntl set", errno);
}

version(Posix)
package(arsd) void setCloExec(int fd) {
	import core.sys.posix.fcntl;
	auto flags = fcntl(fd, F_GETFD, 0);
	if(flags == -1)
		throw new ErrnoApiException("fcntl get", errno);
	flags |= FD_CLOEXEC;
	auto s = fcntl(fd, F_SETFD, flags);
	if(s == -1)
		throw new ErrnoApiException("fcntl set", errno);
}


/++
	A helper object for temporarily constructing a string appropriate for the Windows API from a D UTF-8 string.


	It will use a small internal static buffer is possible, and allocate a new buffer if the string is too big.

	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
version(Windows)
struct WCharzBuffer {
	private wchar[] buffer;
	private wchar[128] staticBuffer = void;

	/// Length of the string, excluding the zero terminator.
	size_t length() {
		return buffer.length;
	}

	// Returns the pointer to the internal buffer. You must assume its lifetime is less than that of the WCharzBuffer. It is zero-terminated.
	wchar* ptr() {
		return buffer.ptr;
	}

	/// Returns the slice of the internal buffer, excluding the zero terminator (though there is one present right off the end of the slice). You must assume its lifetime is less than that of the WCharzBuffer.
	wchar[] slice() {
		return buffer;
	}

	/// Copies it into a static array of wchars
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

/++
	Alternative for toStringz

	History:
		Added March 18, 2023 (dub v11.0)
+/
struct CharzBuffer {
	private char[] buffer;
	private char[128] staticBuffer = void;

	/// Length of the string, excluding the zero terminator.
	size_t length() {
		assert(buffer.length > 0);
		return buffer.length - 1;
	}

	// Returns the pointer to the internal buffer. You must assume its lifetime is less than that of the CharzBuffer. It is zero-terminated.
	char* ptr() {
		return buffer.ptr;
	}

	/// Returns the slice of the internal buffer, excluding the zero terminator (though there is one present right off the end of the slice). You must assume its lifetime is less than that of the CharzBuffer.
	char[] slice() {
		assert(buffer.length > 0);
		return buffer[0 .. $-1];
	}

	/// Copies it into a static array of chars
	void copyInto(R)(ref R r) {
		static if(is(R == char[N], size_t N)) {
			r[0 .. this.length] = slice[];
			r[this.length] = 0;
		} else static assert(0, "can only copy into char[n], not " ~ R.stringof);
	}

	@disable this();
	@disable this(this);

	/++
		Copies `data` into the CharzBuffer, allocating a new one if needed, and zero-terminates it.
	+/
	this(in char[] data) {
		if(data.length + 1 > staticBuffer.length)
			buffer = new char[](data.length + 1);
		else
			buffer = staticBuffer[];

		buffer[0 .. data.length] = data[];
		buffer[data.length] = 0;
	}
}

/++
	Given the string `str`, converts it to a string compatible with the Windows API and puts the result in `buffer`, returning the slice of `buffer` actually used. `buffer` must be at least [sizeOfConvertedWstring] elements long.

	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
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

/++
	Converts the Windows API string `str` to a D UTF-8 string, storing it in `buffer`. Returns the slice of `buffer` actually used.

	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
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

/++
	Converts the Windows API string `str` to a newly-allocated D UTF-8 string.

	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
version(Windows)
string makeUtf8StringFromWindowsString(in wchar[] str) {
	char[] buffer;
	auto got = WideCharToMultiByte(CP_UTF8, 0, str.ptr, cast(int) str.length, null, 0, null, null);
	buffer.length = got;

	// it is unique because we just allocated it above!
	return cast(string) makeUtf8StringFromWindowsString(str, buffer);
}

/// ditto
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

// only used from minigui rn
package int findIndexOfZero(in wchar[] str) {
	foreach(idx, wchar ch; str)
		if(ch == 0)
			return cast(int) idx;
	return cast(int) str.length;
}
package int findIndexOfZero(in char[] str) {
	foreach(idx, char ch; str)
		if(ch == 0)
			return cast(int) idx;
	return cast(int) str.length;
}

/++
	Returns a minimum buffer length to hold the string `s` with the given conversions. It might be slightly larger than necessary, but is guaranteed to be big enough to hold it.

	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
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

/++
	Used by [makeWindowsString] and [WCharzBuffer]

	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
version(Windows)
enum WindowsStringConversionFlags : int {
	/++
		Append a zero terminator to the string.
	+/
	zeroTerminate = 1,
	/++
		Converts newlines from \n to \r\n.
	+/
	convertNewLines = 2,
}

/++
	An int printing function that doesn't need to import Phobos. Can do some of the things std.conv.to and std.format.format do.

	The buffer must be sized to hold the converted number. 32 chars is enough for most anything.

	Returns: the slice of `buffer` containing the converted number.
+/
char[] intToString(long value, char[] buffer, IntToStringArgs args = IntToStringArgs.init) {
	const int radix = args.radix ? args.radix : 10;
	const int digitsPad = args.padTo;
	const int groupSize = args.groupSize;

	int pos;

	if(value < 0) {
		buffer[pos++] = '-';
		value = -value;
	}

	int start = pos;
	int digitCount;

	do {
		auto remainder = value % radix;
		value = value / radix;

		buffer[pos++] = cast(char) (remainder < 10 ? (remainder + '0') : (remainder - 10 + args.ten));
		digitCount++;
	} while(value);

	if(digitsPad > 0) {
		while(digitCount < digitsPad) {
			buffer[pos++] = args.padWith;
			digitCount++;
		}
	}

	assert(pos >= 1);
	assert(pos - start > 0);

	auto reverseSlice = buffer[start .. pos];
	for(int i = 0; i < reverseSlice.length / 2; i++) {
		auto paired = cast(int) reverseSlice.length - i - 1;
		char tmp = reverseSlice[i];
		reverseSlice[i] = reverseSlice[paired];
		reverseSlice[paired] = tmp;
	}

	return buffer[0 .. pos];
}

/// ditto
struct IntToStringArgs {
	private {
		ubyte padTo;
		char padWith;
		ubyte radix;
		char ten;
		ubyte groupSize;
		char separator;
	}

	IntToStringArgs withPadding(int padTo, char padWith = '0') {
		IntToStringArgs args = this;
		args.padTo = cast(ubyte) padTo;
		args.padWith = padWith;
		return args;
	}

	IntToStringArgs withRadix(int radix, char ten = 'a') {
		IntToStringArgs args = this;
		args.radix = cast(ubyte) radix;
		args.ten = ten;
		return args;
	}

	IntToStringArgs withGroupSeparator(int groupSize, char separator = '_') {
		IntToStringArgs args = this;
		args.groupSize = cast(ubyte) groupSize;
		args.separator = separator;
		return args;
	}
}

unittest {
	char[32] buffer;
	assert(intToString(0, buffer[]) == "0");
	assert(intToString(-1, buffer[]) == "-1");
	assert(intToString(-132, buffer[]) == "-132");
	assert(intToString(-1932, buffer[]) == "-1932");
	assert(intToString(1, buffer[]) == "1");
	assert(intToString(132, buffer[]) == "132");
	assert(intToString(1932, buffer[]) == "1932");

	assert(intToString(0x1, buffer[], IntToStringArgs().withRadix(16)) == "1");
	assert(intToString(0x1b, buffer[], IntToStringArgs().withRadix(16)) == "1b");
	assert(intToString(0xef1, buffer[], IntToStringArgs().withRadix(16)) == "ef1");

	assert(intToString(0xef1, buffer[], IntToStringArgs().withRadix(16).withPadding(8)) == "00000ef1");
	assert(intToString(-0xef1, buffer[], IntToStringArgs().withRadix(16).withPadding(8)) == "-00000ef1");
	assert(intToString(-0xef1, buffer[], IntToStringArgs().withRadix(16, 'A').withPadding(8, ' ')) == "-     EF1");
}

/++
	History:
		Moved from color.d to core.d in March 2023 (dub v11.0).
+/
nothrow @safe @nogc pure
inout(char)[] stripInternal(return inout(char)[] s) {
	foreach(i, char c; s)
		if(c != ' ' && c != '\t' && c != '\n' && c != '\r') {
			s = s[i .. $];
			break;
		}
	for(int a = cast(int)(s.length - 1); a > 0; a--) {
		char c = s[a];
		if(c != ' ' && c != '\t' && c != '\n' && c != '\r') {
			s = s[0 .. a + 1];
			break;
		}
	}

	return s;
}

/++
	Shortcut for converting some types to string without invoking Phobos (but it will as a last resort).

	History:
		Moved from color.d to core.d in March 2023 (dub v11.0).
+/
string toStringInternal(T)(T t) {
	char[32] buffer;
	static if(is(T : string))
		return t;
	else static if(is(T : long))
		return intToString(t, buffer[]).idup;
	else {
		import std.conv;
		return to!string(t);
	}
}

/++
	This populates a struct from a list of values (or other expressions, but it only looks at the values) based on types of the members, with one exception: `bool` members.. maybe.

	It is intended for collecting a record of relevant UDAs off a symbol in a single call like this:

	---
		struct Name {
			string n;
		}

		struct Validator {
			string regex;
		}

		struct FormInfo {
			Name name;
			Validator validator;
		}

		@Name("foo") @Validator(".*")
		void foo() {}

		auto info = populateFromUdas!(FormInfo, __traits(getAttributes, foo));
		assert(info.name == Name("foo"));
		assert(info.validator == Validator(".*"));
	---

	Note that instead of UDAs, you can also pass a variadic argument list and get the same result, but the function is `populateFromArgs` and you pass them as the runtime list to bypass "args cannot be evaluated at compile time" errors:

	---
		void foo(T...)(T t) {
			auto info = populateFromArgs!(FormInfo)(t);
			// assuming the call below
			assert(info.name == Name("foo"));
			assert(info.validator == Validator(".*"));
		}

		foo(Name("foo"), Validator(".*"));
	---

	The benefit of this over constructing the struct directly is that the arguments can be reordered or missing. Its value is diminished with named arguments in the language.
+/
template populateFromUdas(Struct, UDAs...) {
	enum Struct populateFromUdas = () {
		Struct ret;
		foreach(memberName; __traits(allMembers, Struct)) {
			alias memberType = typeof(__traits(getMember, Struct, memberName));
			foreach(uda; UDAs) {
				static if(is(memberType == PresenceOf!a, a)) {
					static if(__traits(isSame, a, uda))
						__traits(getMember, ret, memberName) = true;
				}
				else
				static if(is(typeof(uda) : memberType)) {
					__traits(getMember, ret, memberName) = uda;
				}
			}
		}

		return ret;
	}();
}

/// ditto
Struct populateFromArgs(Struct, Args...)(Args args) {
	Struct ret;
	foreach(memberName; __traits(allMembers, Struct)) {
		alias memberType = typeof(__traits(getMember, Struct, memberName));
		foreach(arg; args) {
			static if(is(typeof(arg == memberType))) {
				__traits(getMember, ret, memberName) = arg;
			}
		}
	}

	return ret;
}

/// ditto
struct PresenceOf(alias a) {
	bool there;
	alias there this;
}

///
unittest {
	enum a;
	enum b;
	struct Name { string name; }
	struct Info {
		Name n;
		PresenceOf!a athere;
		PresenceOf!b bthere;
		int c;
	}

	void test() @a @Name("test") {}

	auto info = populateFromUdas!(Info, __traits(getAttributes, test));
	assert(info.n == Name("test")); // but present ones are in there
	assert(info.athere == true); // non-values can be tested with PresenceOf!it, which works like a bool
	assert(info.bthere == false);
	assert(info.c == 0); // absent thing will keep the default value
}

/++
	Declares a delegate property with several setters to allow for handlers that don't care about the arguments.

	Throughout the arsd library, you will often see types of these to indicate that you can set listeners with or without arguments. If you care about the details of the callback event, you can set a delegate that declares them. And if you don't, you can set one that doesn't even declare them and it will be ignored.
+/
struct FlexibleDelegate(DelegateType) {
	// please note that Parameters and ReturnType are public now!
	static if(is(DelegateType FunctionType == delegate))
	static if(is(FunctionType Parameters == __parameters))
	static if(is(DelegateType ReturnType == return)) {

		/++
			Calls the currently set delegate.

			Diagnostics:
				If the callback delegate has not been set, this may cause a null pointer dereference.
		+/
		ReturnType opCall(Parameters args) {
			return dg(args);
		}

		/++
			Use `if(thing)` to check if the delegate is null or not.
		+/
		bool opCast(T : bool)() {
			return dg !is null;
		}

		/++
			These opAssign overloads are what puts the flexibility in the flexible delegate.

			Bugs:
				The other overloads do not keep attributes like `nothrow` on the `dg` parameter, making them unusable if `DelegateType` requires them. I consider the attributes more trouble than they're worth anyway, and the language's poor support for composing them doesn't help any. I have no need for them and thus no plans to add them in the overloads at this time.
		+/
		void opAssign(DelegateType dg) {
			this.dg = dg;
		}

		/// ditto
		void opAssign(ReturnType delegate() dg) {
			this.dg = (Parameters ignored) => dg();
		}

		/// ditto
		void opAssign(ReturnType function(Parameters params) dg) {
			this.dg = (Parameters params) => dg(params);
		}

		/// ditto
		void opAssign(ReturnType function() dg) {
			this.dg = (Parameters ignored) => dg();
		}

		/// ditto
		void opAssign(typeof(null) explicitNull) {
			this.dg = null;
		}

		private DelegateType dg;
	}
	else static assert(0, DelegateType.stringof ~ " failed return value check");
	else static assert(0, DelegateType.stringof ~ " failed parameters check");
	else static assert(0, DelegateType.stringof ~ " failed delegate check");
}

/++

+/
unittest {
	// you don't have to put the arguments in a struct, but i recommend
	// you do as it is more future proof - you can add more info to the
	// struct without breaking user code that consumes it.
	struct MyEventArguments {

	}

	// then you declare it just adding FlexibleDelegate!() around the
	// plain delegate type you'd normally use
	FlexibleDelegate!(void delegate(MyEventArguments args)) callback;

	// until you set it, it will be null and thus be false in any boolean check
	assert(!callback);

	// can set it to the properly typed thing
	callback = delegate(MyEventArguments args) {};

	// and now it is no longer null
	assert(callback);

	// or if you don't care about the args, you can leave them off
	callback = () {};

	// and it works if the compiler types you as a function instead of delegate too
	// (which happens automatically if you don't access any local state or if you
	// explicitly define it as a function)

	callback = function(MyEventArguments args) { };

	// can set it back to null explicitly if you ever wanted
	callback = null;

	// the reflection info used internally also happens to be exposed publicly
	// which can actually sometimes be nice so if the language changes, i'll change
	// the code to keep this working.
	static assert(is(callback.ReturnType == void));

	// which can be convenient if the params is an annoying type since you can
	// consistently use something like this too
	callback = (callback.Parameters params) {};

	// check for null and call it pretty normally
	if(callback)
		callback(MyEventArguments());
}

/+
	======================
	ERROR HANDLING HELPERS
	======================
+/

/+ +
	arsd code shouldn't be using Exception. Really, I don't think any code should be - instead, construct an appropriate object with structured information.

	If you want to catch someone else's Exception, use `catch(object.Exception e)`.
+/
//package deprecated struct Exception {}


/++
	Base class representing my exceptions. You should almost never work with this directly, but you might catch it as a generic thing. Catch it before generic `object.Exception` or `object.Throwable` in any catch chains.


	$(H3 General guidelines for exceptions)

	The purpose of an exception is to cancel a task that has proven to be impossible and give the programmer enough information to use at a higher level to decide what to do about it.

	Cancelling a task is accomplished with the `throw` keyword. The transmission of information to a higher level is done by the language runtime. The decision point is marked by the `catch` keyword. The part missing - the job of the `Exception` class you construct and throw - is to gather the information that will be useful at a later decision point.

	It is thus important that you gather as much useful information as possible and keep it in a way that the code catching the exception can still interpret it when constructing an exception. Other concerns are secondary to this to this primary goal.

	With this in mind, here's some guidelines for exception handling in arsd code.

	$(H4 Allocations and lifetimes)

	Don't get clever with exception allocations. You don't know what the catcher is going to do with an exception and you don't want the error handling scheme to introduce its own tricky bugs. Remember, an exception object's first job is to deliver useful information up the call chain in a way this code can use it. You don't know what this code is or what it is going to do.

	Keep your memory management schemes simple and let the garbage collector do its job.

	$(LIST
		* All thrown exceptions should be allocated with the `new` keyword.

		* Members inside the exception should be value types or have infinite lifetime (that is, be GC managed).

		* While this document is concerned with throwing, you might want to add additional information to an in-flight exception, and this is done by catching, so you need to know how that works too, and there is a global compiler switch that can change things, so even inside arsd we can't completely avoid its implications.

		DIP1008's presence complicates things a bit on the catch side - if you catch an exception and return it from a function, remember to `ex.refcount = ex.refcount + 1;` so you don't introduce more use-after-free woes for those unfortunate souls.
	)

	$(H4 Error strings)

	Strings can deliver useful information to people reading the message, but are often suboptimal for delivering useful information to other chunks of code. Remember, an exception's first job is to be caught by another block of code. Printing to users is a last resort; even if you want a user-readable error message, an exception is not the ideal way to deliver one since it is constructed in the guts of a failed task, without the higher level context of what the user was actually trying to do. User error messages ought to be made from information in the exception, combined with higher level knowledge. This is best done in a `catch` block, not a `throw` statement.

	As such, I recommend that you:

	$(LIST
		* Don't concatenate error strings at the throw site. Instead, pass the data you would have used to build the string as actual data to the constructor. This lets catchers see the original data without having to try to extract it from a string. For unique data, you will likely need a unique exception type. More on this in the next section.

		* Don't construct error strings in a constructor either, for the same reason. Pass the useful data up the call chain, as exception members, to the maximum extent possible. Exception: if you are passed some data with a temporary lifetime that is important enough to pass up the chain. You may `.idup` or `to!string` to preserve as much data as you can before it is lost, but still store it in a separate member of the Exception subclass object.

		* $(I Do) construct strings out of public members in [getAdditionalPrintableInformation]. When this is called, the user has requested as much relevant information as reasonable in string format. Still, avoid concatenation - it lets you pass as many key/value pairs as you like to the caller. They can concatenate as needed. However, note the words "public members" - everything you do in `getAdditionalPrintableInformation` ought to also be possible for code that caught your exception via your public methods and properties.
	)

	$(H4 Subclasses)

	Any exception with unique data types should be a unique class. Whenever practical, this should be one you write and document at the top-level of a module. But I know we get lazy - me too - and this is why in standard D we'd often fall back to `throw new Exception("some string " ~ some info)`. To help resist these urges, I offer some helper functions to use instead that better achieve the key goal of exceptions - passing structured data up a call chain - while still being convenient to write.

	See: [ArsdException], [Win32Enforce]

+/
class ArsdExceptionBase : object.Exception {
	/++
		Don't call this except from other exceptions; this is essentially an abstract class.

		Params:
			operation = the specific operation that failed, throwing the exception
	+/
	package this(string operation, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		super(operation, file, line, next);
	}

	/++
		The toString method will print out several components:

		$(LIST
			* The file, line, static message, and object class name from the constructor. You can access these independently with the members `file`, `line`, `msg`, and [printableExceptionName].
			* The generic category codes stored with this exception
			* Additional members stored with the exception child classes (e.g. platform error codes, associated function arguments)
			* The stack trace associated with the exception. You can access these lines independently with `foreach` over the `info` member.
		)

		This is meant to be read by the developer, not end users. You should wrap your user-relevant tasks in a try/catch block and construct more appropriate error messages from context available there, using the individual properties of the exception to add richness.
	+/
	final override void toString(scope void delegate(in char[]) sink) const {
		// class name and info from constructor
		sink(printableExceptionName);
		sink("@");
		sink(file);
		sink("(");
		char[16] buffer;
		sink(intToString(line, buffer[]));
		sink("): ");
		sink(message);

		getAdditionalPrintableInformation((string name, in char[] value) {
			sink("\n");
			sink(name);
			sink(": ");
			sink(value);
		});

		// full stack trace
		sink("\n----------------\n");
		foreach(str; info) {
			sink(str);
			sink("\n");
		}
	}
	/// ditto
	final override string toString() {
		string s;
		toString((in char[] chunk) { s ~= chunk; });
		return s;
	}

	/++
		Users might like to see additional information with the exception. API consumers should pull this out of properties on your child class, but the parent class might not be able to deal with the arbitrary types at runtime the children can introduce, so bringing them all down to strings simplifies that.

		Overrides should always call `super.getAdditionalPrintableInformation(sink);` before adding additional information by calling the sink with other arguments afterward.

		You should spare no expense in preparing this information - translate error codes, build rich strings, whatever it takes - to make the information here useful to the reader.
	+/
	void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {

	}

	/++
		This is the name of the exception class, suitable for printing. This should be static data (e.g. a string literal). Override it in subclasses.
	+/
	string printableExceptionName() const {
		return typeid(this).name;
	}

	/// deliberately hiding `Throwable.msg`. Use [message] and [toString] instead.
	@disable final void msg() {}

	override const(char)[] message() const {
		return super.msg;
	}
}

/++
	You can catch an ArsdException to get its passed arguments out.

	You can pass either a base class or a string as `Type`.

	See the examples for how to use it.
+/
template ArsdException(alias Type, DataTuple...) {
	static if(DataTuple.length)
		alias Parent = ArsdException!(Type, DataTuple[0 .. $-1]);
	else
		alias Parent = ArsdExceptionBase;

	class ArsdException : Parent {
		DataTuple data;

		this(DataTuple data, string file = __FILE__, size_t line = __LINE__) {
			this.data = data;
			static if(is(Parent == ArsdExceptionBase))
				super(null, file, line);
			else
				super(data[0 .. $-1], file, line);
		}

		static opCall(R...)(R r, string file = __FILE__, size_t line = __LINE__) {
			return new ArsdException!(Type, DataTuple, R)(r, file, line);
		}

		override string printableExceptionName() const {
			static if(DataTuple.length)
				enum str = "ArsdException!(" ~ Type.stringof ~ ", " ~ DataTuple.stringof[1 .. $-1] ~ ")";
			else
				enum str = "ArsdException!" ~ Type.stringof;
			return str;
		}

		override void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {
			ArsdExceptionBase.getAdditionalPrintableInformation(sink);

			foreach(idx, datum; data) {
				enum int lol = cast(int) idx;
				enum key = "[" ~ lol.stringof ~ "] " ~ DataTuple[idx].stringof;
				sink(key, toStringInternal(datum));
			}
		}
	}
}

/// This example shows how you can throw and catch the ad-hoc exception types.
unittest {
	// you can throw and catch by matching the string and argument types
	try {
		// throw it with parenthesis after the template args (it uses opCall to construct)
		throw ArsdException!"Test"();
		// you could also `throw new ArsdException!"test";`, but that gets harder with args
		// as we'll see in the following example
		assert(0); // remove from docs
	} catch(ArsdException!"Test" e) { // catch it without them
		// this has no useful information except for the type
		// but you can catch it like this and it is still more than generic Exception
	}

	// an exception's job is to deliver useful information up the chain
	// and you can do that easily by passing arguments:

	try {
		throw ArsdException!"Test"(4, "four");
		// you could also `throw new ArsdException!("Test", int, string)(4, "four")`
		// but now you start to see how the opCall convenience constructor simplifies things
		assert(0); // remove from docs
	} catch(ArsdException!("Test", int, string) e) { // catch it and use info by specifying types
		assert(e.data[0] == 4); // and extract arguments like this
		assert(e.data[1] == "four");
	}

	// a throw site can add additional information without breaking code that catches just some
	// generally speaking, each additional argument creates a new subclass on top of the previous args
	// so you can cast

	try {
		throw ArsdException!"Test"(4, "four", 9);
		assert(0); // remove from docs
	} catch(ArsdException!("Test", int, string) e) { // this catch still works
		assert(e.data[0] == 4);
		assert(e.data[1] == "four");
		// but if you were to print it, all the members would be there
		// import std.stdio; writeln(e); // would show something like:
		/+
			ArsdException!("Test", int, string, int)@file.d(line):
			[0] int: 4
			[1] string: four
			[2] int: 9
		+/
		// indicating that there's additional information available if you wanted to process it

		// and meanwhile:
		ArsdException!("Test", int) e2 = e; // this implicit cast works thanks to the parent-child relationship
		ArsdException!"Test" e3 = e; // this works too, the base type/string still matches

		// so catching those types would work too
	}
}

/++
	A tagged union that holds an error code from system apis, meaning one from Windows GetLastError() or C's errno.

	You construct it with `SystemErrorCode(thing)` and the overloaded constructor tags and stores it.
+/
struct SystemErrorCode {
	///
	enum Type {
		errno, ///
		win32 ///
	}

	const Type type; ///
	const int code; /// You should technically cast it back to DWORD if it is a win32 code

	/++
		C/unix error are typed as signed ints...
		Windows' errors are typed DWORD, aka unsigned...

		so just passing them straight up will pick the right overload here to set the tag.
	+/
	this(int errno) {
		this.type = Type.errno;
		this.code = errno;
	}

	/// ditto
	this(uint win32) {
		this.type = Type.win32;
		this.code = win32;
	}

	/++
		Constructs a string containing both the code and the explanation string.
	+/
	string toString() const {
		return codeAsString ~ " " ~ errorString;
	}

	/++
		The numeric code itself as a string.

		See [errorString] for a text explanation of the code.
	+/
	string codeAsString() const {
		char[16] buffer;
		final switch(type) {
			case Type.errno:
				return intToString(code, buffer[]).idup;
			case Type.win32:
				buffer[0 .. 2] = "0x";
				return buffer[0 .. 2 + intToString(code, buffer[2 .. $], IntToStringArgs().withRadix(16).withPadding(8)).length].idup;
		}
	}

	/++
		A text explanation of the code. See [codeAsString] for a string representation of the numeric representation.
	+/
	string errorString() const {
		final switch(type) {
			case Type.errno:
				import core.stdc.string;
				auto strptr = strerror(code);
				auto orig = strptr;
				int len;
				while(*strptr++) {
					len++;
				}

				return orig[0 .. len].idup;
			case Type.win32:
				version(Windows) {
					wchar[256] buffer;
					auto size = FormatMessageW(
						FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
						null,
						code,
						MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
						buffer.ptr,
						buffer.length,
						null
					);

					return makeUtf8StringFromWindowsString(buffer[0 .. size]).stripInternal;
				} else {
					return null;
				}
		}
	}
}

/++

+/
class SystemApiException : ArsdExceptionBase {
	this(string msg, int originalErrorNo, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this(msg, SystemErrorCode(originalErrorNo), file, line, next);
	}

	version(Windows)
	this(string msg, DWORD windowsError, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this(msg, SystemErrorCode(windowsError), file, line, next);
	}

	this(string msg, SystemErrorCode code, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this.errorCode = code;

		super(msg, file, line, next);
	}

	/++

	+/
	const SystemErrorCode errorCode;

	override void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {
		super.getAdditionalPrintableInformation(sink);
		sink("Error code", errorCode.toString());
	}

}

/++
	The low level use of this would look like `throw new WindowsApiException("MsgWaitForMultipleObjectsEx", GetLastError())` but it is meant to be used from higher level things like [Win32Enforce].

	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
alias WindowsApiException = SystemApiException;

/++
	History:
		Moved from simpledisplay.d to core.d in March 2023 (dub v11.0).
+/
alias ErrnoApiException = SystemApiException;

/++
	Calls the C API function `fn`. If it returns an error value, it throws an [ErrnoApiException] (or subclass) after getting `errno`.
+/
template ErrnoEnforce(alias fn, alias errorValue = void) {
	static if(is(typeof(fn) Return == return))
	static if(is(typeof(fn) Params == __parameters)) {
		static if(is(errorValue == void)) {
			static if(is(typeof(null) : Return))
				enum errorValueToUse = null;
			else static if(is(Return : long))
				enum errorValueToUse = -1;
			else
				static assert(0, "Please pass the error value");
		} else {
			enum errorValueToUse = errorValue;
		}

		Return ErrnoEnforce(Params params, ArgSentinel sentinel = ArgSentinel.init, string file = __FILE__, size_t line = __LINE__) {
			import core.stdc.errno;

			Return value = fn(params);

			if(value == errorValueToUse) {
				throw new ErrnoApiException(__traits(identifier, fn), errno, file, line);
			}

			return value;
		}
	}
}

version(Windows) {
	/++
		Calls the Windows API function `fn`. If it returns an error value, it throws a [WindowsApiException] (or subclass) after calling `GetLastError()`.
	+/
	template Win32Enforce(alias fn, alias errorValue = void) {
		static if(is(typeof(fn) Return == return))
		static if(is(typeof(fn) Params == __parameters)) {
			static if(is(errorValue == void)) {
				static if(is(Return == BOOL))
					enum errorValueToUse = false;
				else static if(is(Return : HANDLE))
					enum errorValueToUse = NULL;
				else static if(is(Return == DWORD))
					enum errorValueToUse = cast(DWORD) 0xffffffff;
				else
					static assert(0, "Please pass the error value");
			} else {
				enum errorValueToUse = errorValue;
			}

			Return Win32Enforce(Params params, ArgSentinel sentinel = ArgSentinel.init, string file = __FILE__, size_t line = __LINE__) {
				import core.sys.windows.winbase;

				Return value = fn(params);

				if(value == errorValueToUse) {
					auto error = GetLastError();
					throw new WindowsApiException(__traits(identifier, fn), error, file, line);
				}

				return value;
			}
		}
	}

}

/+
	===============
	EVENT LOOP CORE
	===============
+/

/+
	UI threads
		need to get window messages in addition to all the other jobs
	I/O Worker threads
		need to get commands for read/writes, run them, and send the reply back. not necessary on Windows
		if interrupted, check cancel flags.
	CPU Worker threads
		gets functions, runs them, send reply back. should send a cancel flag to periodically check
	Task worker threads
		runs fibers and multiplexes them


	General procedure:
		issue the read/write command
		if it would block on linux, epoll associate it. otherwise do the callback immediately

		callbacks have default affinity to the current thread, meaning their callbacks always run here
		accepts can usually be dispatched to any available thread tho

	//  In other words, a single thread can be associated with, at most, one I/O completion port.

	Realistically, IOCP only used if there is no thread affinity. If there is, just do overlapped w/ sleepex.


	case study: http server

	1) main thread starts the server. it does an accept loop with no thread affinity. the main thread does NOT check the global queue (the iocp/global epoll)
	2) connections come in and are assigned to first available thread via the iocp/global epoll
	3) these run local event loops until the connection task is finished

	EVENT LOOP TYPES:
		1) main ui thread - MsgWaitForMultipleObjectsEx / epoll on the local ui. it does NOT check the any worker thread thing!
			The main ui thread should never terminate until the program is ready to close.
			You can have additional ui threads in theory but im not really gonna support that in full; most things will assume there is just the one. simpledisplay's gui thread is the primary if it exists. (and sdpy will prolly continue to be threaded the way it is now)

			The biggest complication is the TerminalDirectToEmulator, where the primary ui thread is NOT the thread that runs `main`
		2) worker thread GetQueuedCompletionStatusEx / epoll on the local thread fd and the global epoll fd
		3) local event loop - check local things only. SleepEx / epoll on local thread fd. This more of a compatibility hack for `waitForCompletion` outside a fiber.

		i'll use:
			* QueueUserAPC to send interruptions to a worker thread
			* PostQueuedCompletionStatus is to send interruptions to any available thread.
			* PostMessage to a window
			* ??? to a fiber task

		I also need a way to de-duplicate events in the queue so if you try to push the same thing it won't trigger multiple times.... I might want to keep a duplicate of the thing... really, what I'd do is post the "event wake up" message and keep the queue in my own thing. (WM_PAINT auto-coalesces)

		Destructors need to be able to post messages back to a specific task to queue thread-affinity cleanup. This must be GC safe.

		A task might want to wait on certain events. If the task is a fiber, it yields and gets called upon the event. If the task is a thread, it really has to call the event loop... which can be a loop of loops we want to avoid. `waitForCompletion` is more often gonna be used just to run the loop at top level tho... it might not even check for the global info availability so it'd run the local thing only.

		APCs should not themselves enter an alterable wait cuz it can stack overflow. So generally speaking, they should avoid calling fibers or other event loops.
+/

/++
	You can also pass a handle to a specific thread, if you have one.
+/
enum ThreadToRunIn {
	/++
		The callback should be only run by the same thread that set it.
	+/
	CurrentThread,
	/++
		The UI thread is a special one - it is the supervisor of the workers and the controller of gui and console handles. It is the first thread to call [arsd_core_init] actively running an event loop unless there is a thread that has actively asserted the ui supervisor role. FIXME is this true after i implemen it?

		A ui thread should be always quickly responsive to new events.

		There should only be one main ui thread, in which simpledisplay and minigui can be used.

		Other threads can run like ui threads, but are considered temporary and only concerned with their own needs (it is the default style of loop
		for an undeclared thread but will not receive messages from other threads unless there is no other option)


		Ad-Hoc thread - something running an event loop that isn't another thing
		Controller thread - running an explicit event loop instance set as not a task runner or blocking worker
		UI thread - simpledisplay's event loop, which it will require remain live for the duration of the program (running two .eventLoops without a parent EventLoop instance will become illegal, throwing at runtime if it happens telling people to change their code

		Windows HANDLES will always be listened on the thread itself that is requesting, UNLESS it is a worker/helper thread, in which case it goes to a coordinator thread. since it prolly can't rely on the parent per se this will have to be one created by arsd core init, UNLESS the parent is inside an explicit EventLoop structure.

		All use the MsgWaitForMultipleObjectsEx pattern


	+/
	UiThread,
	/++
		The callback can be called from any available worker thread. It will be added to a global queue and the first thread to see it will run it.

		These will not run on the UI thread unless there is no other option on the platform (and all platforms this lib supports have other options).

		These are expected to run cooperatively multitasked things; functions that frequently yield as they wait on other tasks. Think a fiber.

		A task runner should be generally responsive to new events.
	+/
	AnyAvailableTaskRunnerThread,
	/++
		These are expected to run longer blocking, but independent operations. Think an individual function with no context.

		A blocking worker can wait hundreds of milliseconds between checking for new events.
	+/
	AnyAvailableBlockingWorkerThread,
	/++
		The callback will be duplicated across all threads known to the arsd.core event loop.

		It adds it to an immutable queue that each thread will go through... might just replace with an exit() function.


		so to cancel all associated tasks for like a web server, it could just have the tasks atomicAdd to a counter and subtract when they are finished. Then you have a single semaphore you signal the number of times you have an active thing and wait for them to acknowledge it.

		threads should report when they start running the loop and they really should report when they terminate but that isn't reliable


		hmmm what if: all user-created threads (the public api) count as ui threads. only ones created in here are task runners or helpers. ui threads can wait on a global event to exit.

		there's still prolly be one "the" ui thread, which does the handle listening on windows and is the one sdpy wants.
	+/
	BroadcastToAllThreads,
}

/++
	Initializes the arsd core event loop and creates its worker threads. You don't actually have to call this, since the first use of an arsd.core function that requires it will call it implicitly, but calling it yourself gives you a chance to control the configuration more explicitly if you want to.
+/
void arsd_core_init(int numberOfWorkers = 0) {

}

version(Windows)
class WindowsHandleReader_ex {
	// Windows handles are always dispatched to the main ui thread, which can then send a command back to a worker thread to run the callback if needed
	this(HANDLE handle) {}
}

version(Posix)
class PosixFdReader_ex {
	// posix readers can just register with whatever instance we want to handle the callback
}

/++

+/
interface ICoreEventLoop {
	/++
		Runs the event loop for this thread until the `until` delegate returns `true`.
	+/
	final void run(scope bool delegate() until) {
		while(!until()) {
			runOnce();
		}
	}

	/++
		Runs a single iteration of the event loop for this thread. It will return when the first thing happens, but that thing might be totally uninteresting to anyone, or it might trigger significant work you'll wait on.
	+/
	void runOnce();

	// to send messages between threads, i'll queue up a function that just call dispatchMessage. can embed the arg inside the callback helper prolly.
	// tho i might prefer to actually do messages w/ run payloads so it is easier to deduplicate i can still dedupe by insepcting the call args so idk

	version(Arsd_core_epoll) {
		@mustuse
		static struct UnregisterToken {
			private CoreEventLoopImplementation impl;
			private int fd;
			private CallbackHelper cb;

			/++
				Unregisters the file descriptor from the event loop and releases the reference to the callback held by the event loop (which will probably free it).

				You must call this when you're done. Normally, this will be right before you close the fd (Which is often after the other side closes it, meaning you got a 0 length read).
			+/
			void unregister() {
				assert(impl !is null, "Cannot reuse unregister token");
				impl.unregisterFd(fd);
				cb.release();
				this = typeof(this).init;
			}
		}

		@mustuse
		static struct RearmToken {
			private CoreEventLoopImplementation impl;
			private int fd;
			private CallbackHelper cb;
			private uint flags;

			/++
				Calls [UnregisterToken.unregister]
			+/
			void unregister() {
				assert(impl !is null, "cannot reuse rearm token after unregistering it");
				impl.unregisterFd(fd);
				cb.release();
				this = typeof(this).init;
			}

			/++
				Rearms the event so you will get another callback next time it is ready.
			+/
			void rearm() {
				assert(impl !is null, "cannot reuse rearm token after unregistering it");
				impl.rearmFd(this);
			}
		}

		UnregisterToken addCallbackOnFdReadable(int fd, CallbackHelper cb);
		RearmToken addCallbackOnFdReadableOneShot(int fd, CallbackHelper cb);
	}

	version(Arsd_core_kqueue) {
		// can be a do-nothing here since the event is one off
		@mustuse
		static struct UnregisterToken {
			void unregister() {}
		}

		UnregisterToken addCallbackOnFdReadable(int fd, CallbackHelper cb);
	}
}

/++
	Get the event loop associated with this thread
+/
ICoreEventLoop getThisThreadEventLoop(EventLoopType type = EventLoopType.AdHoc) {
	static ICoreEventLoop loop;
	if(loop is null)
		loop = new CoreEventLoopImplementation();
	return loop;
}

/++
	The internal types that will be exposed through other api things.
+/
package(arsd) enum EventLoopType {
	/++
		The event loop is being run temporarily and the thread doesn't promise to keep running it.
	+/
	AdHoc,
	/++
		The event loop struct has been instantiated at top level. Its destructor will run when the
		function exits, which is only at the end of the entire block of work it is responsible for.

		It must be in scope for the whole time the arsd event loop functions are expected to be used
		(meaning it should generally be top-level in `main`)
	+/
	Explicit,
	/++
		A specialization of `Explicit`, so all the same rules apply there, but this is specifically the event loop coming from simpledisplay or minigui. It will run for the duration of the UI's existence.
	+/
	Ui,
	/++
		A special event loop specifically for threads that listen to the task runner queue and handle I/O events from running tasks. Typically, a task runner runs cooperatively multitasked coroutines (so they prefer not to block the whole thread).
	+/
	TaskRunner,
	/++
		A special event loop specifically for threads that listen to the helper function request queue. Helper functions are expected to run independently for a somewhat long time (them blocking the thread for some time is normal) and send a reply message back to the requester.
	+/
	HelperWorker
}

/+
	Tasks are given an object to talk to their parent... can be a dialog where it is like

	sendBuffer
	waitForWordToProceed

	in a loop


	Tasks are assigned to a worker thread and may share it with other tasks.
+/


// the GC may not be able to see this! remember, it can be hidden inside kernel buffers
private class CallbackHelper {
	import core.memory;

	void call() {
		if(callback)
			callback();
	}

	void delegate() callback;
	void*[3] argsStore;

	void addref() {
		atomicOp!"+="(refcount, 1);
	}

	void release() {
		if(atomicOp!"-="(refcount, 1) <= 0) {
			if(flags & 1)
				GC.removeRoot(cast(void*) this);
		}
	}

	private shared(int) refcount;
	private uint flags;

	this(void function() callback) {
		this( () { callback(); } );
	}

	this(void delegate() callback, bool addRoot = true) {
		if(addRoot) {
			GC.addRoot(cast(void*) this);
			this.flags |= 1;
		}

		this.addref();
		this.callback = callback;
	}
}

/++
	This represents a file. Technically, file paths aren't actually strings (for example, on Linux, they need not be valid utf-8, while a D string is supposed to be), even though we almost always use them like that.

	This type is meant to represent a filename / path. I might not keep it around.
+/
struct FilePath {
	string path;
}

/++
	Represents a generic async, waitable request.
+/
class AsyncOperationRequest {
	/++
		Actually issues the request, starting the operation.
	+/
	abstract void start();
	/++
		Cancels the request. This will cause `isComplete` to return true once the cancellation has been processed, but [AsyncOperationResponse.wasSuccessful] will return `false` (unless it completed before the cancellation was processed, in which case it is still allowed to finish successfully).

		After cancelling a request, you should still wait for it to complete to ensure that the task has actually released its resources before doing anything else on it.

		Once a cancellation request has been sent, it cannot be undone.
	+/
	abstract void cancel();

	/++
		Returns `true` if the operation has been completed. It may be completed successfully, cancelled, or have errored out - to check this, call [waitForCompletion] and check the members on the response object.
	+/
	abstract bool isComplete();
	/++
		Waits until the request has completed - successfully or otherwise - and returns the response object. It will run an ad-hoc event loop that may call other callbacks while waiting.

		The response object may be embedded in the request object - do not reuse the request until you are finished with the response and do not keep the response around longer than you keep the request.


		Note to implementers: all subclasses should override this and return their specific response object. You can use the top-level `waitForFirstToCompleteByIndex` function with a single-element static array to help with the implementation.
	+/
	abstract AsyncOperationResponse waitForCompletion();

	/++

	+/
	// abstract void repeat();
}

/++

+/
abstract class AsyncOperationResponse {
	/++
		Returns true if the request completed successfully, finishing what it was supposed to.

		Should be set to `false` if the request was cancelled before completing or encountered an error.
	+/
	abstract bool wasSuccessful();
}

/++
	It returns the $(I request) so you can identify it more easily. `request.waitForCompletion()` is guaranteed to return the response without any actual wait, since it is already complete when this function returns.

	Please note that "completion" is not necessary successful completion; a request being cancelled or encountering an error also counts as it being completed.

	The `waitForFirstToCompleteByIndex` version instead returns the index of the array entry that completed first.

	It is your responsibility to remove the completed request from the array before calling the function again, since any request already completed will always be immediately returned.

	You might prefer using [asTheyComplete], which will give each request as it completes and loop over until all of them are complete.

	Returns:
		`null` or `requests.length` if none completed before returning.
+/
AsyncOperationRequest waitForFirstToComplete(AsyncOperationRequest[] requests...) {
	auto idx = waitForFirstToCompleteByIndex(requests);
	if(idx == requests.length)
		return null;
	return requests[idx];
}
/// ditto
size_t waitForFirstToCompleteByIndex(AsyncOperationRequest[] requests...) {
	size_t helper() {
		foreach(idx, request; requests)
			if(request.isComplete())
				return idx;
		return requests.length;
	}

	auto idx = helper();
	// if one is already done, return it
	if(idx != requests.length)
		return idx;

	// otherwise, run the ad-hoc event loop until one is
	// FIXME: what if we are inside a fiber?
	auto el = getThisThreadEventLoop();
	el.run(() => (idx = helper()) != requests.length);

	return idx;
}

/++
	Waits for all the `requests` to complete, giving each one through the range interface as it completes.

	This meant to be used in a foreach loop.

	The `requests` array and its contents must remain valid for the lifetime of the returned range. Its contents may be shuffled as the requests complete (the implementation works through an unstable sort+remove).
+/
AsTheyCompleteRange asTheyComplete(AsyncOperationRequest[] requests...) {
	return AsTheyCompleteRange(requests);
}
/// ditto
struct AsTheyCompleteRange {
	AsyncOperationRequest[] requests;

	this(AsyncOperationRequest[] requests) {
		this.requests = requests;

		if(requests.length == 0)
			return;

		// wait for first one to complete, then move it to the front of the array
		moveFirstCompleteToFront();
	}

	private void moveFirstCompleteToFront() {
		auto idx = waitForFirstToCompleteByIndex(requests);

		auto tmp = requests[0];
		requests[0] = requests[idx];
		requests[idx] = tmp;
	}

	bool empty() {
		return requests.length == 0;
	}

	void popFront() {
		assert(!empty);
		/+
			this needs to
			1) remove the front of the array as being already processed (unless it is the initial priming call)
			2) wait for one of them to complete
			3) move the complete one to the front of the array
		+/

		requests[0] = requests[$-1];
		requests = requests[0 .. $-1];

		if(requests.length)
			moveFirstCompleteToFront();
	}

	AsyncOperationRequest front() {
		return requests[0];
	}
}

version(Windows) {
	alias NativeFileHandle = HANDLE; ///
	alias NativeSocketHandle = SOCKET; ///
	alias NativePipeHandle = HANDLE; ///
} else version(Posix) {
	alias NativeFileHandle = int; ///
	alias NativeSocketHandle = int; ///
	alias NativePipeHandle = int; ///
}

/++

+/
final class SyncFile {
	private {
		NativeFileHandle handle;
	}

	/++
	+/
	enum OpenMode {
		readOnly, /// C's "r", the file is read
		writeWithTruncation, /// C's "w", the file is blanked upon opening so it only holds what you write
		appendOnly, /// C's "a", writes will always be appended to the file
		readAndWrite /// C's "r+", writes will overwrite existing parts of the file based on where you seek (default is at the beginning)
	}

	/++
	+/
	enum RequirePreexisting {
		no,
		yes
	}

	/++

	+/
	ubyte[] read(scope ubyte[] buffer) {
		return null;
	}

	/++

	+/
	void write(in void[] buffer) {
	}

	enum Seek {
		current,
		fromBeginning,
		fromEnd
	}

	// Seeking/telling/sizing is not permitted when appending and some files don't support it
	void seek(long where, Seek fromWhence) {}

	long tell() { return 0; }

	long size() { return 0; }

	// note that there is no fsync thing, instead use the special flag.

	/+
	enum SpecialFlags {
		randomAccessExpected, /// FILE_FLAG_SEQUENTIAL_SCAN is turned off
		skipCache, /// O_DSYNC, FILE_FLAG_NO_BUFFERING and maybe WRITE_THROUGH. note that metadata still goes through the cache, FlushFileBuffers and fsync can still do those
		temporary, /// FILE_ATTRIBUTE_TEMPORARY on Windows, idk how to specify on linux
		deleteWhenClosed, /// Windows has a flag for this but idk if it is of any real use
	}
	+/

	/++

	+/
	this(FilePath filename, OpenMode mode = OpenMode.readOnly, RequirePreexisting require = RequirePreexisting.no) {
		version(Windows) {
			DWORD access;
			DWORD creation;

			final switch(mode) {
				case OpenMode.readOnly:
					access = GENERIC_READ;
					creation = OPEN_EXISTING;
				break;
				case OpenMode.writeWithTruncation:
					access = GENERIC_WRITE;

					final switch(require) {
						case RequirePreexisting.no:
							creation = CREATE_ALWAYS;
						break;
						case RequirePreexisting.yes:
							creation = TRUNCATE_EXISTING;
						break;
					}
				break;
				case OpenMode.appendOnly:
					access = FILE_APPEND_DATA;

					final switch(require) {
						case RequirePreexisting.no:
							creation = CREATE_ALWAYS;
						break;
						case RequirePreexisting.yes:
							creation = OPEN_EXISTING;
						break;
					}
				break;
				case OpenMode.readAndWrite:
					access = GENERIC_READ | GENERIC_WRITE;

					final switch(require) {
						case RequirePreexisting.no:
							creation = CREATE_NEW;
						break;
						case RequirePreexisting.yes:
							creation = OPEN_EXISTING;
						break;
					}
				break;
			}

			WCharzBuffer wname = WCharzBuffer(filename.path);

			auto handle = CreateFileW(
				wname.ptr,
				access,
				FILE_SHARE_READ,
				null,
				creation,
				FILE_ATTRIBUTE_NORMAL,/* | FILE_FLAG_OVERLAPPED,*/
				null
			);

			if(handle == INVALID_HANDLE_VALUE) {
				// FIXME: throw the filename and other params here too
				throw new WindowsApiException("CreateFileW", GetLastError());
			}

			this.handle = handle;
		} else version(Posix) {
			import core.sys.posix.unistd;
			import core.sys.posix.fcntl;

			CharzBuffer namez = CharzBuffer(filename.path);
			int flags;

			// FIXME does mac not have cloexec for real or is this just a druntime problem?????
			version(Arsd_core_has_cloexec) {
				flags = O_CLOEXEC;
			} else {
				scope(success)
					setCloExec(this.handle);
			}

			final switch(mode) {
				case OpenMode.readOnly:
					flags |= O_RDONLY;
				break;
				case OpenMode.writeWithTruncation:
					flags |= O_WRONLY | O_TRUNC;

					final switch(require) {
						case RequirePreexisting.no:
							flags |= O_CREAT;
						break;
						case RequirePreexisting.yes:
						break;
					}
				break;
				case OpenMode.appendOnly:
					flags |= O_APPEND;

					final switch(require) {
						case RequirePreexisting.no:
							flags |= O_CREAT;
						break;
						case RequirePreexisting.yes:
						break;
					}
				break;
				case OpenMode.readAndWrite:
					flags |= O_RDWR;

					final switch(require) {
						case RequirePreexisting.no:
							flags |= O_CREAT;
						break;
						case RequirePreexisting.yes:
						break;
					}
				break;
			}

			int fd = open(namez.ptr, flags, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
			if(fd == -1)
				throw new ErrnoApiException("open", errno);

			this.handle = fd;
		}
	}

	/++

	+/
	this(NativeFileHandle handleToWrap) {
		this.handle = handleToWrap;
	}

	/++

	+/
	void close() {
		version(Windows) {
			Win32Enforce!CloseHandle(handle);
			handle = null;
		} else version(Posix) {
			import unix = core.sys.posix.unistd;
			import core.sys.posix.fcntl;

			ErrnoEnforce!(unix.close)(handle);
			handle = -1;
		}
	}
}

version(none)
void main() {
	auto file = new AsyncFile(FilePath("test.txt"), AsyncFile.OpenMode.write, AsyncFile.PreserveContents.truncateIfWriting, AsyncFile.RequirePreexisting.yes);

	auto buffer = cast(ubyte[]) "hello";
	auto wr = new AsyncWriteRequest(file, buffer);
	wr.start();

	wr.waitForCompletion();

	file.close();
}

mixin template OverlappedIoRequest(Response) {
	private {
		SyncFile file;
		ubyte[] buffer;

		OwnedClass!Response response;

		version(Windows) {
			OVERLAPPED overlapped;

			extern(Windows)
			static void overlappedCompletionRoutine(DWORD dwErrorCode, DWORD dwNumberOfBytesTransferred, LPOVERLAPPED lpOverlapped) {
				typeof(this) rr = cast(typeof(this)) (cast(void*) lpOverlapped - typeof(this).overlapped.offsetof);

				// this will queue our CallbackHelper and that should be run at the end of the event loop after it is woken up by the APC run
			}
		}

		bool started;
	}

	override void cancel() {
		version(Windows) {
			Win32Enforce!CancelIoEx(file.handle, &overlapped);
		} else version(Posix) {
			// FIXME
		}
	}

	override bool isComplete() {
		version(Windows) {
			return HasOverlappedIoCompleted(&overlapped);
		} else version(Posix) {
			return true;

		}
	}

	override Response waitForCompletion() {
		if(!started)
			start();

		version(Windows) {
			SleepEx(INFINITE, true);

			//DWORD numberTransferred;
			//Win32Enforce!GetOverlappedResult(file.handle, &overlapped, &numberTransferred, true);
		} else version(Posix) {

		}

		return response;
	}
}

/++
	You can write to a file asynchronously by creating one of these.
+/
final class AsyncWriteRequest : AsyncOperationRequest {
	mixin OverlappedIoRequest!AsyncWriteResponse;

	this() {
		response = typeof(response).defaultConstructed;
	}

	override void start() {
	}

	/++

	+/
	void repeat() {
		// FIXME
	}
}

class AsyncWriteResponse : AsyncOperationResponse {
	override bool wasSuccessful() {
		return false;
	}
}


final class AsyncReadRequest : AsyncOperationRequest {
	mixin OverlappedIoRequest!AsyncReadResponse;

	/++
		The file must have the overlapped flag enabled on Windows and the nonblock flag set on Posix.

		The buffer MUST NOT be touched by you - not used by another request, modified, read, or freed, including letting a static array going out of scope - until this request's `isComplete` returns `true`.

		The offset pointer is shared between this and other requests.
	+/
	this(NativeFileHandle file, ubyte[] buffer, shared(long)* offset) {
		response = typeof(response).defaultConstructed;
	}

	override void start() {
		version(Windows) {
			auto ret = ReadFileEx(file.handle, buffer.ptr, cast(DWORD) buffer.length, &overlapped, &overlappedCompletionRoutine);
			// need to check GetLastError

			// ReadFileEx always queues, even if it completed synchronously. I *could* check the get overlapped result and sleepex here but i'm prolly better off just letting the event loop do its thing anyway.
		} else version(Posix) {
			import core.sys.posix.unistd;

			// first try to just do it
			auto ret = read(file.handle, buffer.ptr, buffer.length);

			// then if it doesn't complete synchronously, need to event loop register

			// if we are inside a fiber task, it can simply yield and call the fiber in the callback
			// when we return here, it tries to read again

			// if not inside, we need to ensure the buffer remains valid and set a callback... and return.
			// the callback must retry the read

			// generally, the callback must satisfy the read somehow they set the callback to trigger the result object's completion handler
		}
	}
	/++
		Cancels the request. This will cause `isComplete` to return true once the cancellation has been processed, but [AsyncOperationResponse.wasSuccessful] will return `false` (unless it completed before the cancellation was processed, in which case it is still allowed to finish successfully).

		After cancelling a request, you should still wait for it to complete to ensure that the task has actually released its resources before doing anything else on it.

		Once a cancellation request has been sent, it cannot be undone.
	+/
	override void cancel() {

	}

	/++
		Returns `true` if the operation has been completed. It may be completed successfully, cancelled, or have errored out - to check this, call [waitForCompletion] and check the members on the response object.
	+/
	override bool isComplete() {
		return false;
	}
	/++
		Waits until the request has completed - successfully or otherwise - and returns the response object.

		The response object may be embedded in the request object - do not reuse the request until you are finished with the response and do not keep the response around longer than you keep the request.


		Note to implementers: all subclasses should override this and return their specific response object. You can use the top-level `waitForFirstToCompleteByIndex` function with a single-element static array to help with the implementation.
	+/
	override AsyncOperationResponse waitForCompletion() {
		return response;
	}

	/++

	+/
	// abstract void repeat();
}

class AsyncReadResponse : AsyncOperationResponse {
	override bool wasSuccessful() {
		return false;
	}
}

/+
	Tasks:
		startTask()
		startSubTask() - what if it just did this when it knows it is being run from inside a task?
		runHelperFunction() - whomever it reports to is the parent
+/

private class CoreEventLoopImplementation : ICoreEventLoop {

	version(Arsd_core_kqueue) {
		void runOnce() {
			kevent_t[16] ev;
			//timespec tout = timespec(1, 0);
			auto nev = kevent(kqueuefd, null, 0, ev.ptr, ev.length, null/*&tout*/);
			if(nev == -1) {
				// FIXME: EINTR
				throw new SystemApiException("kevent", errno);
			} else if(nev == 0) {
				// timeout
			} else {
				foreach(event; ev[0 .. nev]) {
					if(event.filter == EVFILT_SIGNAL) {
						// FIXME: I could prolly do this better tbh
						markSignalOccurred(cast(int) event.ident);
						signalChecker();
					} else {
						// FIXME: event.filter more specific?
						CallbackHelper cb = cast(CallbackHelper) event.udata;
						cb.call();
					}
				}
			}
		}

		// FIXME: idk how to make one event that multiple kqueues can listen to w/o being shared
		// maybe a shared kqueue could work that the thread kqueue listen to (which i rejected for
		// epoll cuz it caused thundering herd problems but maybe it'd work here)

		UnregisterToken addCallbackOnFdReadable(int fd, CallbackHelper cb) {
			kevent_t ev;

			EV_SET(&ev, fd, EVFILT_READ, EV_ADD | EV_ENABLE/* | EV_ONESHOT*/, 0, 0, cast(void*) cb);

			ErrnoEnforce!kevent(kqueuefd, &ev, 1, null, 0, null);

			return UnregisterToken();
		}

		private void triggerGlobalEvent() {
			ubyte a;
			import core.sys.posix.unistd;
			write(kqueueGlobalFd[1], &a, 1);
		}

		private this() {
			kqueuefd = ErrnoEnforce!kqueue();
			setCloExec(kqueuefd); // FIXME O_CLOEXEC

			if(kqueueGlobalFd[0] == 0) {
				import core.sys.posix.unistd;
				pipe(kqueueGlobalFd);

				signal(SIGINT, SIG_IGN); // FIXME
			}

			kevent_t ev;

			EV_SET(&ev, SIGCHLD, EVFILT_SIGNAL, EV_ADD | EV_ENABLE, 0, 0, null);
			ErrnoEnforce!kevent(kqueuefd, &ev, 1, null, 0, null);
			EV_SET(&ev, SIGINT, EVFILT_SIGNAL, EV_ADD | EV_ENABLE, 0, 0, null);
			ErrnoEnforce!kevent(kqueuefd, &ev, 1, null, 0, null);

			globalEventSent = new CallbackHelper(&readGlobalEvent);
			EV_SET(&ev, kqueueGlobalFd[0], EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, cast(void*) globalEventSent);
			ErrnoEnforce!kevent(kqueuefd, &ev, 1, null, 0, null);
		}

		private int kqueuefd = -1;

		private CallbackHelper globalEventSent;
		void readGlobalEvent() {
			kevent_t event;

			import core.sys.posix.unistd;
			ubyte a;
			read(kqueueGlobalFd[0], &a, 1);

			// FIXME: the thread is woken up, now we need to check the circualr buffer queue
		}

		private __gshared int[2] kqueueGlobalFd;
	}

	/+
		// this setup  needs no extra allocation
		auto op = read(file, buffer);
		op.oncomplete = &thisfiber.call;
		op.start();
		thisfiber.yield();
		auto result = op.waitForCompletion(); // guaranteed to return instantly thanks to previous setup

		can generically abstract that into:

		auto result = thisTask.await(read(file, buffer));


		You MUST NOT use buffer in any way - not read, modify, deallocate, reuse, anything - until the PendingOperation is complete.

		Note that PendingOperation may just be a wrapper around an internally allocated object reference... but then if you do a waitForFirstToComplete what happens?

		those could of course just take the value type things
	+/


	version(Arsd_core_windows) {
		// all event loops share the one iocp, Windows
		// manages how to do it
		__gshared HANDLE iocpTaskRunners;
		__gshared HANDLE iocpWorkers;
		// i think to terminate i just have to post the message at least once for every thread i know about, maybe a few more times for threads i don't know about.

		bool isWorker; // if it is a worker we wait on the iocp, if not we wait on msg

		void runOnce() {
			if(isWorker) {
				// this function is only supported on Windows Vista and up, so using this
				// means dropping support for XP.
				//GetQueuedCompletionStatusEx();
			} else {
				//MsgWaitForMultipleObjectsEx();
				if(true) {
					// handle: timeout
					// HANDLE ready, forward message
					// window messages
					// also sleepex if needed
				}
			}
		}
	}

	version(Posix) {
		private __gshared uint sigChildHappened = 0;
		private __gshared uint sigIntrHappened = 0;

		static void signalChecker() {
			if(cas(&sigChildHappened, 1, 0)) {
				while(true) { // multiple children could have exited before we processed the notification

					import core.sys.posix.sys.wait;

					int status;
					auto pid = waitpid(-1, &status, WNOHANG);
					if(pid == -1) {
						import core.stdc.errno;
						auto errno = errno;
						if(errno == ECHILD)
							break; // also all done, there are no children left
						// no need to check EINTR since we set WNOHANG
						throw new ErrnoApiException("waitpid", errno);
					}
					if(pid == 0)
						break; // all done, all children are still running

					// look up the pid for one of our objects
					// if it is found, inform it of its status
					// and then inform its controlling thread
					// to wake up so it can check its waitForCompletion,
					// trigger its callbacks, etc.

					ExternalProcess.recordChildTerminated(pid, status);
				}

			}
			if(cas(&sigIntrHappened, 1, 0)) {
				// FIXME
				import core.stdc.stdlib;
				exit(0);
			}
		}

		/++
			Informs the arsd.core system that the given signal happened. You can call this from inside a signal handler.
		+/
		public static void markSignalOccurred(int sigNumber) nothrow {
			import core.sys.posix.unistd;

			if(sigNumber == SIGCHLD)
				volatileStore(&sigChildHappened, 1);
			if(sigNumber == SIGINT)
				volatileStore(&sigIntrHappened, 1);

			version(Arsd_core_epoll) {
				ulong writeValue = 1;
				write(signalPipeFd, &writeValue, writeValue.sizeof);
			}
		}
	}

	version(Arsd_core_epoll) {

		import core.sys.linux.epoll;
		import core.sys.linux.sys.eventfd;

		private this() {

			if(!globalsInitialized) {
				synchronized {
					if(!globalsInitialized) {
						// blocking signals is problematic because it is inherited by child processes
						// and that can be problematic for general purpose stuff so i use a self pipe
						// here. though since it is linux, im using an eventfd instead just to notify
						signalPipeFd = ErrnoEnforce!eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
						signalReaderCallback = new CallbackHelper(&signalReader);

						runInTaskRunnerQueue = new CallbackQueue("task runners", true);
						runInHelperThreadQueue = new CallbackQueue("helper threads", true);

						setSignalHandlers();

						globalsInitialized = true;
					}
				}
			}

			epollfd = epoll_create1(EPOLL_CLOEXEC);

			// FIXME: ensure UI events get top priority

			// global listeners

			// FIXME: i should prolly keep the tokens and release them when tearing down.

			cast(void) addCallbackOnFdReadable(signalPipeFd, signalReaderCallback);
			if(true) { // FIXME: if this is a task runner vs helper thread vs ui thread
				cast(void) addCallbackOnFdReadable(runInTaskRunnerQueue.fd, runInTaskRunnerQueue.callback);
				runInTaskRunnerQueue.callback.addref();
			} else {
				cast(void) addCallbackOnFdReadable(runInHelperThreadQueue.fd, runInHelperThreadQueue.callback);
				runInHelperThreadQueue.callback.addref();
			}

			// local listener
			thisThreadQueue = new CallbackQueue("this thread", false);
			cast(void) addCallbackOnFdReadable(thisThreadQueue.fd, thisThreadQueue.callback);

			// what are we going to do about timers?
		}

		void teardown() {
			import core.sys.posix.fcntl;
			import core.sys.posix.unistd;

			close(epollfd);
			epollfd = -1;

			thisThreadQueue.teardown();

			// FIXME: should prolly free anything left in the callback queue, tho those could also be GC managed tbh.
		}

		static void teardownGlobals() {
			import core.sys.posix.fcntl;
			import core.sys.posix.unistd;

			synchronized {
				restoreSignalHandlers();
				close(signalPipeFd);
				signalReaderCallback.release();

				runInTaskRunnerQueue.teardown();
				runInHelperThreadQueue.teardown();

				globalsInitialized = false;
			}

		}


		private static final class CallbackQueue {
			int fd = -1;
			string name;
			CallbackHelper callback;
			SynchronizedCircularBuffer!CallbackHelper queue;

			this(string name, bool dequeueIsShared) {
				this.name = name;
				queue = typeof(queue)(this);

				fd = ErrnoEnforce!eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK | (dequeueIsShared ? EFD_SEMAPHORE : 0));

				callback = new CallbackHelper(dequeueIsShared ? &sharedDequeueCb : &threadLocalDequeueCb);
			}

			bool resetEvent() {
				import core.sys.posix.unistd;
				ulong count;
				return read(fd, &count, count.sizeof) == count.sizeof;
			}

			void sharedDequeueCb() {
				if(resetEvent()) {
					auto cb = queue.dequeue();
					cb.call();
					cb.release();
				}
			}

			void threadLocalDequeueCb() {
				CallbackHelper[16] buffer;
				foreach(cb; queue.dequeueSeveral(buffer[], () { resetEvent(); })) {
					cb.call();
					cb.release();
				}
			}

			void enqueue(CallbackHelper cb) {
				if(queue.enqueue(cb)) {
					import core.sys.posix.unistd;
					ulong count = 1;
					ErrnoEnforce!write(fd, &count, count.sizeof);
				} else {
					throw new ArsdException!"queue is full"(name);
				}
			}

			void teardown() {
				import core.sys.posix.fcntl;
				import core.sys.posix.unistd;

				close(fd);
				fd = -1;

				callback.release();
			}

			alias queue this;
		}

		// there's a global instance of this we refer back to
		private __gshared {
			bool globalsInitialized;

			CallbackHelper signalReaderCallback;

			CallbackQueue runInTaskRunnerQueue;
			CallbackQueue runInHelperThreadQueue;

			int exitEventFd = -1; // FIXME: implement
		}

		// and then the local loop
		private {
			int epollfd = -1;

			CallbackQueue thisThreadQueue;
		}

		// signal stuff {
		import core.sys.posix.signal;

		private __gshared sigaction_t oldSigIntr;
		private __gshared sigaction_t oldSigChld;
		private __gshared sigaction_t oldSigPipe;

		private __gshared int signalPipeFd = -1;
		// sigpipe not important, i handle errors on the writes

		public static void setSignalHandlers() {
			static extern(C) void interruptHandler(int sigNumber) nothrow {
				markSignalOccurred(sigNumber);

				/+
				// calling the old handler is non-trivial since there can be ignore
				// or default or a plain handler or a sigaction 3 arg handler and i
				// i don't think it is worth teh complication
				sigaction_t* oldHandler;
				if(sigNumber == SIGCHLD)
					oldHandler = &oldSigChld;
				else if(sigNumber == SIGINT)
					oldHandler = &oldSigIntr;
				if(oldHandler && oldHandler.sa_handler)
					oldHandler
				+/
			}

			sigaction_t n;
			n.sa_handler = &interruptHandler;
			n.sa_mask = cast(sigset_t) 0;
			n.sa_flags = 0;
			sigaction(SIGINT, &n, &oldSigIntr);
			sigaction(SIGCHLD, &n, &oldSigChld);

			n.sa_handler = SIG_IGN;
			sigaction(SIGPIPE, &n, &oldSigPipe);
		}

		public static void restoreSignalHandlers() {
			sigaction(SIGINT, &oldSigIntr, null);
			sigaction(SIGCHLD, &oldSigChld, null);
			sigaction(SIGPIPE, &oldSigPipe, null);
		}

		private static void signalReader() {
			import core.sys.posix.unistd;
			ulong number;
			read(signalPipeFd, &number, number.sizeof);

			signalChecker();
		}
		// signal stuff done }

		// the any thread poll is just registered in the this thread poll w/ exclusive. nobody actaully epoll_waits
		// on the global one directly.

		void runOnce() {
			epoll_event[16] events;
			auto ret = epoll_wait(epollfd, events.ptr, cast(int) events.length, -1); // FIXME: timeout
			if(ret == -1) {
				import core.stdc.errno;
				if(errno == EINTR) {
					return;
				}
				throw new ErrnoApiException("epoll_wait", errno);
			} else if(ret == 0) {
				// timeout
			} else {
				// loop events and call associated callbacks
				foreach(event; events[0 .. ret]) {
					auto flags = event.events;
					auto cbObject = cast(CallbackHelper) event.data.ptr;

					// FIXME: or if it is an error...
					// EPOLLERR - write end of pipe when read end closed or other error. and EPOLLHUP - terminal hangup or read end when write end close (but it will give 0 reading after that soon anyway)

					cbObject.call();
				}
			}
		}

		// building blocks for low-level integration with the loop

		UnregisterToken addCallbackOnFdReadable(int fd, CallbackHelper cb) {
			epoll_event event;
			event.data.ptr = cast(void*) cb;
			event.events = EPOLLIN | EPOLLEXCLUSIVE;
			if(epoll_ctl(epollfd, EPOLL_CTL_ADD, fd, &event) == -1)
				throw new ErrnoApiException("epoll_ctl", errno);

			return UnregisterToken(this, fd, cb);
		}

		/++
			Adds a one-off callback that you can optionally rearm when it happens.
		+/
		RearmToken addCallbackOnFdReadableOneShot(int fd, CallbackHelper cb) {
			epoll_event event;
			event.data.ptr = cast(void*) cb;
			event.events = EPOLLIN | EPOLLONESHOT;
			if(epoll_ctl(epollfd, EPOLL_CTL_ADD, fd, &event) == -1)
				throw new ErrnoApiException("epoll_ctl", errno);

			return RearmToken(this, fd, cb, EPOLLIN | EPOLLONESHOT);
		}

		private void unregisterFd(int fd) {
			epoll_event event;
			if(epoll_ctl(epollfd, EPOLL_CTL_DEL, fd, &event) == -1)
				throw new ErrnoApiException("epoll_ctl", errno);
		}

		private void rearmFd(RearmToken token) {
			epoll_event event;
			event.data.ptr = cast(void*) token.cb;
			event.events = token.flags;
			if(epoll_ctl(epollfd, EPOLL_CTL_MOD, token.fd, &event) == -1)
				throw new ErrnoApiException("epoll_ctl", errno);
		}

		// Disk files will have to be sent as messages to a worker to do the read and report back a completion packet.
	}

	version(Arsd_core_kqueue) {
		// FIXME
	}

	// cross platform adapters
	void setTimeout() {}
	void addFileOrDirectoryChangeListener(FilePath name, uint flags, bool recursive = false) {}
}

// deduplication???????//
bool postMessage(ThreadToRunIn destination, void delegate() code) {
	return false;
}
bool postMessage(ThreadToRunIn destination, Object message) {
	return false;
}

// to test the mailboxes
/+
void main() {
	/+
	import std.stdio;
	Thread[4] pool;

	bool shouldExit;

	static int received;

	static void tester() {
		received++;
		//writeln(cast(void*) Thread.getThis, " ", received);
	}

	foreach(ref thread; pool) {
		thread = new Thread(() {
			getThisThreadEventLoop().run(() {
				return shouldExit;
			});
		});
		thread.start();
	}

	getThisThreadEventLoop(); // ensure it is all initialized before proceeding. FIXME: i should have an ensure initialized function i do on most the public apis.

	int lol;

	try
	foreach(i; 0 .. 6000) {
		CoreEventLoopImplementation.runInTaskRunnerQueue.enqueue(new CallbackHelper(&tester));
		lol = cast(int) i;
	}
	catch(ArsdExceptionBase e)  {
		Thread.sleep(50.msecs);
		writeln(e);
		writeln(lol);
	}

	import core.stdc.stdlib;
	exit(0);

	version(none)
	foreach(i; 0 .. 100)
		CoreEventLoopImplementation.runInTaskRunnerQueue.enqueue(new CallbackHelper(&tester));


	foreach(ref thread; pool) {
		thread.join();
	}
	+/


	static int received;

	static void tester() {
		received++;
		//writeln(cast(void*) Thread.getThis, " ", received);
	}



	auto ev = cast(CoreEventLoopImplementation) getThisThreadEventLoop();
	foreach(i; 0 .. 100)
		ev.thisThreadQueue.enqueue(new CallbackHelper(&tester));
	foreach(i; 0 .. 100 / 16 + 1)
	ev.runOnce();
	import std.conv;
	assert(received == 100, to!string(received));

}
+/

/++
	This is primarily a helper for the event queues. It is public in the hope it might be useful,
	but subject to change without notice; I will treat breaking it the same as if it is private.
	(That said, it is a simple little utility that does its job, so it is unlikely to change much.
	The biggest change would probably be letting it grow and changing from inline to dynamic array.)

	It is a fixed-size ring buffer that synchronizes on a given object you give it in the constructor.

	After enqueuing something, you should probably set an event to notify the other threads. This is left
	as an exercise to you (or another wrapper).
+/
struct SynchronizedCircularBuffer(T, size_t maxSize = 128) {
	private T[maxSize] ring;
	private int front;
	private int back;

	private Object synchronizedOn;

	@disable this();

	/++
		The Object's monitor is used to synchronize the methods in here.
	+/
	this(Object synchronizedOn) {
		this.synchronizedOn = synchronizedOn;
	}

	/++
		Note the potential race condition between calling this and actually dequeuing something. You might
		want to acquire the lock on the object before calling this (nested synchronized things are allowed
		as long as the same thread is the one doing it).
	+/
	bool isEmpty() {
		synchronized(this.synchronizedOn) {
			return front == back;
		}
	}

	/++
		Note the potential race condition between calling this and actually queuing something.
	+/
	bool isFull() {
		synchronized(this.synchronizedOn) {
			return isFullUnsynchronized();
		}
	}

	private bool isFullUnsynchronized() nothrow const {
		return ((back + 1) % ring.length) == front;

	}

	/++
		If this returns true, you should signal listening threads (with an event or a semaphore,
		depending on how you dequeue it). If it returns false, the queue was full and your thing
		was NOT added. You might wait and retry later (you could set up another event to signal it
		has been read and wait for that, or maybe try on a timer), or just fail and throw an exception
		or to abandon the message.
	+/
	bool enqueue(T what) {
		synchronized(this.synchronizedOn) {
			if(isFullUnsynchronized())
				return false;
			ring[(back++) % ring.length] = what;
			return true;
		}
	}

	private T dequeueUnsynchronized() nothrow {
		assert(front != back);
		return ring[(front++) % ring.length];
	}

	/++
		If you are using a semaphore to signal, you can call this once for each count of it
		and you can do that separately from this call (though they should be paired).

		If you are using an event, you should use [dequeueSeveral] instead to drain it.
	+/
	T dequeue() {
		synchronized(this.synchronizedOn) {
			return dequeueUnsynchronized();
		}
	}

	/++
		Note that if you use a semaphore to signal waiting threads, you should probably not call this.

		If you use a set/reset event, there's a potential race condition between the dequeue and event
		reset. This is why the `runInsideLockIfEmpty` delegate is there - when it is empty, before it
		unlocks, it will give you a chance to reset the event. Otherwise, it can remain set to indicate
		that there's still pending data in the queue.
	+/
	T[] dequeueSeveral(return T[] buffer, scope void delegate() runInsideLockIfEmpty = null) {
		int pos;
		synchronized(this.synchronizedOn) {
			while(pos < buffer.length && front != back) {
				buffer[pos++] = dequeueUnsynchronized();
			}
			if(front == back && runInsideLockIfEmpty !is null)
				runInsideLockIfEmpty();
		}
		return buffer[0 .. pos];
	}
}

unittest {
	Object object = new Object();
	auto queue = SynchronizedCircularBuffer!CallbackHelper(object);
	assert(queue.isEmpty);
	foreach(i; 0 .. queue.ring.length - 1)
		queue.enqueue(cast(CallbackHelper) cast(void*) i);
	assert(queue.isFull);

	foreach(i; 0 .. queue.ring.length - 1)
		assert(queue.dequeue() is (cast(CallbackHelper) cast(void*) i));
	assert(queue.isEmpty);

	foreach(i; 0 .. queue.ring.length - 1)
		queue.enqueue(cast(CallbackHelper) cast(void*) i);
	assert(queue.isFull);

	CallbackHelper[] buffer = new CallbackHelper[](300);
	auto got = queue.dequeueSeveral(buffer);
	assert(got.length == queue.ring.length - 1);
	assert(queue.isEmpty);
	foreach(i, item; got)
		assert(item is (cast(CallbackHelper) cast(void*) i));

	foreach(i; 0 .. 8)
		queue.enqueue(cast(CallbackHelper) cast(void*) i);
	buffer = new CallbackHelper[](4);
	got = queue.dequeueSeveral(buffer);
	assert(got.length == 4);
	foreach(i, item; got)
		assert(item is (cast(CallbackHelper) cast(void*) i));
	got = queue.dequeueSeveral(buffer);
	assert(got.length == 4);
	foreach(i, item; got)
		assert(item is (cast(CallbackHelper) cast(void*) (i+4)));
	got = queue.dequeueSeveral(buffer);
	assert(got.length == 0);
	assert(queue.isEmpty);
}

/++

+/
enum ByteOrder {
	irrelevant,
	littleEndian,
	bigEndian,
}

class WritableStream {
	this(size_t bufferSize) {
	}

	void put(T)() {}

	void flush() {}

	bool isClosed() { return true; }

	// hasRoomInBuffer
	// canFlush
	// waitUntilCanFlush

	// flushImpl
	// markFinished / close - tells the other end you're done
}

/++
	A stream can be used by just one task at a time, but one task can consume multiple streams.

	Streams may be populated by async sources (in which case they must be called from a fiber task),
	from a function generating the data on demand (including an input range), from memory, or from a synchronous file.

	A stream of heterogeneous types is compatible with input ranges.
+/
class ReadableStream {

	this() {

	}

	T get(T)(ByteOrder byteOrder = ByteOrder.irrelevant) {
		if(byteOrder == ByteOrder.irrelevant && T.sizeof > 1)
			throw new ArsdException!"byte order must be specified for a type that is bigger than one byte";

		while(bufferedLength() < T.sizeof)
			waitForAdditionalData();

		static if(T.sizeof == 1) {
			ubyte ret = consumeOneByte();
			return *cast(T*) &ret;
		} else {
			static if(T.sizeof == 8)
				ulong ret;
			else static if(T.sizeof == 4)
				uint ret;
			else static if(T.sizeof == 2)
				ushort ret;
			else static assert(0, "unimplemented type, try using just the basic types");

			if(byteOrder == ByteOrder.littleEndian) {
				typeof(ret) buffer;
				foreach(b; 0 .. T.sizeof) {
					buffer = consumeOneByte();
					buffer <<= T.sizeof * 8 - 8;

					ret >>= 8;
					ret |= buffer;
				}
			} else {
				foreach(b; 0 .. T.sizeof) {
					ret <<= 8;
					ret |= consumeOneByte();
				}
			}

			return *cast(T*) &ret;
		}
	}

	// if the stream is closed before getting the length or the terminator, should we send partial stuff
	// or just throw?
	T get(T : E[], E)(size_t length, ByteOrder elementByteOrder = ByteOrder.irrelevant) {
		if(byteOrder == ByteOrder.irrelevant && E.sizeof > 1)
			throw new ArsdException!"byte order must be specified for a type that is bigger than one byte";

		while(bufferedLength() < length * E.sizeof)
			waitForAdditionalData();

		T ret;

		// FIXME

		return ret;

	}

	T get(T : E[], E)(scope bool delegate(E e) isTerminatingSentinel, ByteOrder elementByteOrder = ByteOrder.irrelevant) {
		if(byteOrder == ByteOrder.irrelevant && E.sizeof > 1)
			throw new ArsdException!"byte order must be specified for a type that is bigger than one byte";

		assert(0, "Not implemented");
	}

	/++

	+/
	bool isClosed() {
		return isClosed_;
	}

	// Control side of things

	private bool isClosed_;

	/++
		Feeds data into the stream, which can be consumed by `get`. If a task is waiting for more
		data to satisfy its get requests, this will trigger those tasks to resume.

		If you feed it empty data, it will mark the stream as closed.
	+/
	void feedData(ubyte[] data) {
		if(data.length == 0)
			isClosed_ = true;

		currentBuffer = data;
		// this is a borrowed buffer, so we won't keep the reference long term
		scope(exit)
			currentBuffer = null;

		if(waitingTask !is null) {
			waitingTask.call();
		}
	}

	/++
		You basically have to use this thing from a task
	+/
	protected void waitForAdditionalData() {
		Fiber task = Fiber.getThis;

		assert(task !is null);

		if(waitingTask !is null && waitingTask !is task)
			throw new ArsdException!"streams can only have one waiting task";

		// copy any pending data in our buffer to the longer-term buffer
		if(currentBuffer.length)
			leftoverBuffer ~= currentBuffer;

		waitingTask = task;
		task.yield();
	}

	private Fiber waitingTask;
	private ubyte[] leftoverBuffer;
	private ubyte[] currentBuffer;

	private size_t bufferedLength() {
		return leftoverBuffer.length + currentBuffer.length;
	}

	private ubyte consumeOneByte() {
		ubyte b;
		if(leftoverBuffer.length) {
			b = leftoverBuffer[0];
			leftoverBuffer = leftoverBuffer[1 .. $];
		} else if(currentBuffer.length) {
			b = currentBuffer[0];
			currentBuffer = currentBuffer[1 .. $];
		} else {
			assert(0, "consuming off an empty buffer is impossible");
		}

		return b;
	}
}

unittest {
	auto stream = new ReadableStream();

	int position;
	char[16] errorBuffer;

	auto fiber = new Fiber(() {
		position = 1;
		int a = stream.get!int(ByteOrder.littleEndian);
		assert(a == 10, intToString(a, errorBuffer[]));
		position = 2;
		ubyte b = stream.get!ubyte;
		assert(b == 33);
		position = 3;
	});

	fiber.call();
	assert(position == 1);
	stream.feedData([10, 0, 0, 0]);
	assert(position == 2);
	stream.feedData([33]);
	assert(position == 3);
}

/++
	You might use this like:

	---
	auto proc = new ExternalProcess();
	auto stdoutStream = new ReadableStream();

	// to use a stream you can make one and have a task consume it
	runTask({
		while(!stdoutStream.isClosed) {
			auto line = stdoutStream.get!string(e => e == '\n');
		}
	});

	// then make the process feed into the stream
	proc.onStdoutAvailable = (got) {
		stdoutStream.feedData(got); // send it to the stream for processing
		stdout.rawWrite(got); // forward it through to our own thing
		// could also append it to a buffer to return it on complete
	};
	proc.start();
	---

	Please note that this does not currently and I have no plans as of this writing to add support for any kind of direct file descriptor passing. It always pipes them back to the parent for processing. If you don't want this, call the lower level functions yourself; the reason this class is here is to aid integration in the arsd.core event loop.

	Of course, I might change my mind on this.
+/
class ExternalProcess {

	private static version(Posix) {
		__gshared ExternalProcess[pid_t] activeChildren;

		void recordChildCreated(pid_t pid, ExternalProcess proc) {
			synchronized(typeid(ExternalProcess)) {
				activeChildren[pid] = proc;
			}
		}

		void recordChildTerminated(pid_t pid, int status) {
			synchronized(typeid(ExternalProcess)) {
				if(pid in activeChildren) {
					auto ac = activeChildren[pid];
					ac.completed = true;
					ac.status = status;
					activeChildren.remove(pid);
				}
			}
		}
	}

	// FIXME: config to pass through a shell or not

	/++
		This is the native version for Windows.
	+/
	this(string program, string commandLine) {
	}

	this(string commandLine) {
		version(Posix) {
			assert(0, "not implemented command line to posix args yet");
		}

	}

	this(string[] args) {
		version(Posix) {
			this.program = FilePath(args[0]);
			this.args = args;
		}

	}

	/++
		This is the native version for Posix.
	+/
	this(FilePath program, string[] args) {
		version(Posix) {
			this.program = program;
			this.args = args;
		}
	}

	// you can modify these before calling start
	int stdoutBufferSize = 32 * 1024;
	int stderrBufferSize = 8 * 1024;

	void start() {
		version(Posix) {
			int ret;

			int[2] stdinPipes;
			ret = pipe(stdinPipes);
			if(ret == -1)
				throw new ErrnoApiException("stdin pipe", errno);

			scope(failure) {
				close(stdinPipes[0]);
				close(stdinPipes[1]);
			}

			stdinFd = stdinPipes[1];

			int[2] stdoutPipes;
			ret = pipe(stdoutPipes);
			if(ret == -1)
				throw new ErrnoApiException("stdout pipe", errno);

			scope(failure) {
				close(stdoutPipes[0]);
				close(stdoutPipes[1]);
			}

			stdoutFd = stdoutPipes[0];

			int[2] stderrPipes;
			ret = pipe(stderrPipes);
			if(ret == -1)
				throw new ErrnoApiException("stderr pipe", errno);

			scope(failure) {
				close(stderrPipes[0]);
				close(stderrPipes[1]);
			}

			stderrFd = stderrPipes[0];


			int[2] errorReportPipes;
			ret = pipe(errorReportPipes);
			if(ret == -1)
				throw new ErrnoApiException("error reporting pipe", errno);

			scope(failure) {
				close(errorReportPipes[0]);
				close(errorReportPipes[1]);
			}

			setCloExec(errorReportPipes[0]);
			setCloExec(errorReportPipes[1]);

			auto forkRet = fork();
			if(forkRet == -1)
				throw new ErrnoApiException("fork", errno);

			if(forkRet == 0) {
				// child side

				// FIXME can we do more error checking that is actually useful here?
				// these operations are virtually guaranteed to succeed given the setup anyway.

				// FIXME pty too

				void fail(int step) {
					import core.stdc.errno;
					auto code = errno;

					// report the info back to the parent then exit

					int[2] msg = [step, code];
					auto ret = write(errorReportPipes[1], msg.ptr, msg.sizeof);

					// but if this fails there's not much we can do...

					import core.stdc.stdlib;
					exit(1);
				}

				// dup2 closes the fd it is replacing automatically
				dup2(stdinPipes[0], 0);
				dup2(stdoutPipes[1], 1);
				dup2(stderrPipes[1], 2);

				// don't need either of the original pipe fds anymore
				close(stdinPipes[0]);
				close(stdinPipes[1]);
				close(stdoutPipes[0]);
				close(stdoutPipes[1]);
				close(stderrPipes[0]);
				close(stderrPipes[1]);

				// the error reporting pipe will be closed upon exec since we set cloexec before fork
				// and everything else should have cloexec set too hopefully.

				if(beforeExec)
					beforeExec();

				// i'm not sure that a fully-initialized druntime is still usable
				// after a fork(), so i'm gonna stick to the C lib in here.

				const(char)* file = mallocedStringz(program.path).ptr;
				if(file is null)
					fail(1);
				const(char)*[] argv = mallocSlice!(const(char)*)(args.length + 1);
				if(argv is null)
					fail(2);
				foreach(idx, arg; args) {
					argv[idx] = mallocedStringz(args[idx]).ptr;
					if(argv[idx] is null)
						fail(3);
				}
				argv[args.length] = null;

				auto rete = execvp/*e*/(file, argv.ptr/*, envp*/);
				if(rete == -1) {
					fail(4);
				} else {
					// unreachable code, exec never returns if it succeeds
					assert(0);
				}
			} else {
				pid = forkRet;

				recordChildCreated(pid, this);

				// close our copy of the write side of the error reporting pipe
				// so the read will immediately give eof when the fork closes it too
				ErrnoEnforce!close(errorReportPipes[1]);

				int[2] msg;
				// this will block to wait for it to actually either start up or fail to exec (which should be near instant)
				auto val = read(errorReportPipes[0], msg.ptr, msg.sizeof);

				if(val == -1)
					throw new ErrnoApiException("read error report", errno);

				if(val == msg.sizeof) {
					// error happened
					// FIXME: keep the step part of the error report too
					throw new ErrnoApiException("exec", msg[1]);
				} else if(val == 0) {
					// pipe closed, meaning exec succeeded
				} else {
					assert(0); // never supposed to happen
				}

				// set the ones we keep to close upon future execs
				// FIXME should i set NOBLOCK at this time too? prolly should
				setCloExec(stdinPipes[1]);
				setCloExec(stdoutPipes[0]);
				setCloExec(stderrPipes[0]);

				// and close the others
				ErrnoEnforce!close(stdinPipes[0]);
				ErrnoEnforce!close(stdoutPipes[1]);
				ErrnoEnforce!close(stderrPipes[1]);

				ErrnoEnforce!close(errorReportPipes[0]);

				// and now register the ones we need to read with the event loop so it can call the callbacks
				// also need to listen to SIGCHLD to queue up the terminated callback. FIXME

				stdoutUnregisterToken = getThisThreadEventLoop().addCallbackOnFdReadable(stdoutFd, new CallbackHelper(&stdoutReadable));
			}
		}
	}

	private version(Posix) {
		import core.sys.posix.unistd;
		import core.sys.posix.fcntl;

		int stdinFd = -1;
		int stdoutFd = -1;
		int stderrFd = -1;

		ICoreEventLoop.UnregisterToken stdoutUnregisterToken;

		pid_t pid = -1;

		public void delegate() beforeExec;

		FilePath program;
		string[] args;

		void stdoutReadable() {
			ubyte[1024] buffer;
			auto ret = read(stdoutFd, buffer.ptr, buffer.length);
			if(ret == -1)
				throw new ErrnoApiException("read", errno);
			if(onStdoutAvailable) {
				onStdoutAvailable(buffer[0 .. ret]);
			}

			if(ret == 0) {
				stdoutUnregisterToken.unregister();

				close(stdoutFd);
				stdoutFd = -1;
			}
		}
	}

	void waitForCompletion() {
		getThisThreadEventLoop().run(&this.isComplete);
	}

	bool isComplete() {
		return completed;
	}

	bool completed;
	int status = int.min;

	/++
		If blocking, it will block the current task until the write succeeds.

		Write `null` as data to close the pipe. Once the pipe is closed, you must not try to write to it again.
	+/
	void writeToStdin(in void[] data) {
		version(Posix) {
			if(data is null) {
				close(stdinFd);
				stdinFd = -1;
			} else {
				// FIXME: check the return value again and queue async writes
				auto ret = write(stdinFd, data.ptr, data.length);
				if(ret == -1)
					throw new ErrnoApiException("write", errno);
			}
		}

	}

	void delegate(ubyte[] got) onStdoutAvailable;
	void delegate(ubyte[] got) onStderrAvailable;
	void delegate(int code) onTermination;

	// pty?
}

// FIXME: comment this out
///+
unittest {
	auto proc = new ExternalProcess(FilePath("/bin/cat"), ["/bin/cat"]);

	getThisThreadEventLoop(); // initialize it

	int c = 0;
	proc.onStdoutAvailable = delegate(ubyte[] got) {
		if(c == 0)
			assert(cast(string) got == "hello!");
		else
			assert(got.length == 0);
			// import std.stdio; writeln(got);
		c++;
	};

	proc.start();

	assert(proc.pid != -1);


	import std.stdio;
	Thread[4] pool;

	bool shouldExit;

	static int received;

	static void tester() {
		received++;
		//writeln(cast(void*) Thread.getThis, " ", received);
	}

	foreach(ref thread; pool) {
		thread = new Thread(() {
			getThisThreadEventLoop().run(() {
				return shouldExit;
			});
		});
		thread.start();
	}



	proc.writeToStdin("hello!");
	proc.writeToStdin(null); // closes the pipe

	proc.waitForCompletion();

	assert(proc.status == 0);

	assert(c == 2);
}
//+/

// to test the thundering herd on signal handling
version(none)
unittest {
	Thread[4] pool;
	foreach(ref thread; pool) {
		thread = new class Thread {
			this() {
				super({
					int count;
					getThisThreadEventLoop().run(() {
						if(count > 4) return true;
						count++;
						return false;
					});
				});
			}
		};
		thread.start();
	}
	foreach(ref thread; pool) {
		thread.join();
	}
}

/+

STDIO

	/++
		Please note using this will create a compile-time dependency on [arsd.terminal]

		It works correctly on Windows, using the correct functions to write unicode to the console.
		even allocating a console if needed. If the output has been redirected to a file or pipe, it
		writes UTF-8.


so my writeln replacement:

1) if the std output handle is null, alloc one
2) if it is a character device, write out the proper Unicode text.
3) otherwise write out UTF-8.... maybe with a BOM but maybe not. it is tricky to know what the other end of a pipe expects...
[8:15 AM]
im actually tempted to make the write binary to stdout functions throw an exception if it is a character console / interactive terminal instead of letting you spam it right out
[8:16 AM]
of course you can still cheat by casting binary data to string and using the write string function (and this might be appropriate sometimes) but there kinda is a legit difference between a text output and a binary output device

Stdout can represent either

	+/
	void writeln(){} {

	}

	stderr?

	/++
		Please note using this will create a compile-time dependency on [arsd.terminal]

		It can be called from a task.

		It works correctly on Windows and is user friendly on Linux (using arsd.terminal.getline)
		while also working if stdin has been redirected (where arsd.terminal itself would throw)


so say you run a program on an interactive terminal. the program tries to open the stdin binary stream

instead of throwing, the prompt could change to indicate the binary data is expected and you can feed it in either by typing it up,,,,  or running some command like maybe <file.bin to have the library do what the shell would have done and feed that to the rest of the program

	+/
	string readln()() {

	}


	// if using stdio as a binary output thing you can pretend it is a file w/ stream capability
	struct File {
		WritableStream ostream;
		ReadableStream istream;

		ulong tell;
		void seek(ulong to) {}

		void sync();
		void close();
	}

	// these are a bit special because if it actually is an interactive character device, it might be different than other files and even different than other pipes.
	WritableStream stdoutStream() { return null; }
	WritableStream stderrStream() { return null; }
	ReadableStream stdinStream() { return null; }

+/


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

// Should return both the object and the index in the array!
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

private version(Windows) extern(Windows) {
	BOOL CancelIoEx(HANDLE, LPOVERLAPPED);
}
