/++
	$(PITFALL
		Please note: the api and behavior of this module is not externally stable at this time. See the documentation on specific functions for details.
	)

	Shared core functionality including exception helpers, library loader, event loop, and possibly more. Maybe command line processor and uda helper and some basic shared annotation types.

	I'll probably move the url, websocket, and ssl stuff in here too as they are often shared. Maybe a small internationalization helper type (a hook for external implementation) and COM helpers too. I might move the process helpers out to their own module - even things in here are not considered stable to library users at this time!

	If you use this directly outside the arsd library despite its current instability caveats, you might consider using `static import` since names in here are likely to clash with Phobos if you use them together. `static import` will let you easily disambiguate and avoid name conflict errors if I add more here. Some names even clash deliberately to remind me to avoid some antipatterns inside the arsd modules!

	## Contributor notes

	arsd.core should be focused on things that enable interoperability primarily and secondarily increased code quality between other, otherwise independent arsd modules. As a foundational library, it is not permitted to import anything outside the druntime `core` namespace, except in templates and examples not normally compiled in. This keeps it independent and avoids transitive dependency spillover to end users while also keeping compile speeds fast. To help keep builds snappy, also avoid significant use of ctfe inside this module.

	On my linux computer, `dmd -unittest -main core.d` takes about a quarter second to run. We do not want this to grow.

	`@safe` compatibility is ok when it isn't too big of a hassle. `@nogc` is a non-goal. I might accept it on some of the trivial functions but if it means changing the logic in any way to support, you will need a compelling argument to justify it. The arsd libs are supposed to be reliable and easy to use. That said, of course, don't be unnecessarily wasteful - if you can easily provide a reliable and easy to use way to let advanced users do their thing without hurting the other cases, let's discuss it.

	If functionality is not needed by multiple existing arsd modules, consider adding a new module instead of adding it to the core.

	Unittests should generally be hidden behind a special version guard so they don't interfere with end user tests.

	History:
		Added March 2023 (dub v11.0). Several functions were migrated in here at that time, noted individually. Members without a note were added with the module.
+/
module arsd.core;

/+
	Intended to be Supported OSes:
		* Windows (at least Vista, MAYBE XP)
		* Linux
		* FreeBSD 14 (maybe 13 too)
		* Mac OS

	Eventually also:
		* ios
		* OpenBSD
		* Android
		* maybe apple watch os?
+/


static if(__traits(compiles, () { import core.interpolation; })) {
	import core.interpolation;

	alias InterpolationHeader    = core.interpolation.InterpolationHeader;
	alias InterpolationFooter    = core.interpolation.InterpolationFooter;
	alias InterpolatedLiteral    = core.interpolation.InterpolatedLiteral;
	alias InterpolatedExpression = core.interpolation.InterpolatedExpression;
} else {
	// polyfill for old versions
	struct InterpolationHeader {}
	struct InterpolationFooter {}
	struct InterpolatedLiteral(string literal) {}
	struct InterpolatedExpression(string code) {}
}

// arsd core is now default but you can opt out for a lil while
version(no_arsd_core) {

} else {
	version=use_arsd_core;
}

version(use_arsd_core)
	enum use_arsd_core = true;
else
	enum use_arsd_core = false;

import core.attribute;
static if(__traits(hasMember, core.attribute, "implicit"))
	alias implicit = core.attribute.implicit;
else
	enum implicit;

static if(__traits(hasMember, core.attribute, "standalone"))
	alias standalone = core.attribute.standalone;
else
	enum standalone;



// FIXME: add callbacks on file open for tracing dependencies dynamically

// see for useful info: https://devblogs.microsoft.com/dotnet/how-async-await-really-works/

// see: https://wiki.openssl.org/index.php/Simple_TLS_Server

// see: When you only want to track changes on a file or directory, be sure to open it using the O_EVTONLY flag.

///ArsdUseCustomRuntime is used since other derived work from WebAssembly may be used and thus specified in the CLI
version(Emscripten) {
	version = EmptyEventLoop;
	version = EmptyCoreEvent;
	version = HasTimer;
} else version(WebAssembly) version = ArsdUseCustomRuntime;
else

// note that kqueue might run an i/o loop on mac, ios, etc. but then NSApp.run on the io thread
// but on bsd, you want the kqueue loop in i/o too....

version(ArsdUseCustomRuntime)
{
	version = UseStdioWriteln;
}
else
{
	version(D_OpenD) {
		version(OSX)
			version=OSXCocoa;
		version(iOS)
			version=OSXCocoa;
	}

	version = HasFile;
	version = HasSocket;
	version = HasThread;
	import core.stdc.errno;

	version(Windows)
		version = HasTimer;
	version(linux)
		version = HasTimer;
	version(OSXCocoa)
		version = HasTimer;
}

version(HasThread)
{
	import core.thread;
	import core.volatile;
	import core.atomic;
}
else
{
	// polyfill for missing core.time
	/*
	struct Duration {
		static Duration max() { return Duration(); }
	}
	struct MonoTime {}
	*/
}

import core.time;

version(OSXCocoa) {
	version(ArsdNoCocoa)
		enum bool UseCocoa = false;
	else {
		version=UseCocoa;
		enum bool UseCocoa = true;
	}
} else
	enum bool UseCocoa = false;

import core.attribute;
static if(!__traits(hasMember, core.attribute, "mustuse"))
	enum mustuse;

// FIXME: add an arena allocator? can do task local destruction maybe.

// the three implementations are windows, epoll, and kqueue

version(Emscripten)  {
	import core.stdc.errno;
	import core.atomic;
	import core.volatile;

} else version(Windows) {
	version=Arsd_core_windows;

	// import core.sys.windows.windows;
	import core.sys.windows.winbase;
	import core.sys.windows.windef;
	import core.sys.windows.winnls;
	import core.sys.windows.winuser;
	import core.sys.windows.winsock2;

	pragma(lib, "user32");
	pragma(lib, "ws2_32");
} else version(linux) {
	version=Arsd_core_epoll;

	static if(__VERSION__ >= 2098) {
		version=Arsd_core_has_cloexec;
	}
} else version(FreeBSD) {
	version=Arsd_core_kqueue;

	import core.sys.freebsd.sys.event;

	// the version in druntime doesn't have the default arg making it a pain to use when the freebsd
	// version adds a new field
	extern(D) void EV_SET(kevent_t* kevp, typeof(kevent_t.tupleof) args = kevent_t.tupleof.init)
	{
	    *kevp = kevent_t(args);
	}
} else version(DragonFlyBSD) {
	// NOT ACTUALLY TESTED
	version=Arsd_core_kqueue;

	import core.sys.dragonflybsd.sys.event;
} else version(NetBSD) {
	// NOT ACTUALLY TESTED
	version=Arsd_core_kqueue;

	import core.sys.netbsd.sys.event;
} else version(OpenBSD) {
	version=Arsd_core_kqueue;

	// THIS FILE DOESN'T ACTUALLY EXIST, WE NEED TO MAKE IT
	import core.sys.openbsd.sys.event;
} else version(OSX) {
	version=Arsd_core_dispatch;

	import core.sys.darwin.sys.event;
} else version(iOS) {
	version=Arsd_core_dispatch;

	import core.sys.darwin.sys.event;
}

// FIXME: pragma(linkerDirective, "-framework", "Cocoa") works in ldc
static if(UseCocoa)
	enum CocoaAvailable = true;
else
	enum CocoaAvailable = false;

version(D_OpenD) {
	static if(UseCocoa) {
		pragma(linkerDirective, "-framework", "Cocoa");
		pragma(linkerDirective, "-framework", "QuartzCore");
	}
} else {
	static if(UseCocoa)
	version(LDC) {
		pragma(linkerDirective, "-framework", "Cocoa");
		pragma(linkerDirective, "-framework", "QuartzCore");
	}
}

version(Posix) {
	import core.sys.posix.signal;
	import core.sys.posix.unistd;

	version(Emscripten) {} else {
	import core.sys.posix.sys.un;
	import core.sys.posix.sys.socket;
	import core.sys.posix.netinet.in_;
	}
}

// FIXME: the exceptions should actually give some explanatory text too (at least sometimes)

/+
	=========================
	GENERAL UTILITY FUNCTIONS
	=========================
+/

/++
	Casts value `v` to type `T`.

	$(TIP
		This is a helper function for readability purposes.
		The idea is to make type-casting as accessible as `to()` from `std.conv`.
	)

	---
	int i =  cast(int)(foo * bar);
	int i = castTo!int(foo * bar);

	int j = cast(int) round(floatValue);
	int j = round(floatValue).castTo!int;

	int k = cast(int) floatValue  + foobar;
	int k = floatValue.castTo!int + foobar;

	auto m = Point(
		cast(int) calc(a.x, b.x),
		cast(int) calc(a.y, b.y),
	);
	auto m = Point(
		calc(a.x, b.x).castTo!int,
		calc(a.y, b.y).castTo!int,
	);
	---

	History:
		Added on April 24, 2024.
		Renamed from `typeCast` to `castTo` on May 24, 2024.
 +/
auto ref T castTo(T, S)(auto ref S v) {
	return cast(T) v;
}

///
alias typeCast = castTo;

/++
	Treats the memory of one variable as if it is the type of another variable.

	History:
		Added January 20, 2025
+/
ref T reinterpretCast(T, V)(return ref V value) @system {
	return *cast(T*)& value;
}

/++
	Determines whether `needle` is a slice of `haystack`.

	History:
		Added on February 11, 2025.
 +/
bool isSliceOf(T1, T2)(scope const(T1)[] needle, scope const(T2)[] haystack) @trusted pure nothrow @nogc {
	return (
		needle.ptr >= haystack.ptr
		&& ((needle.ptr + needle.length) <= (haystack.ptr + haystack.length))
	);
}

///
@safe unittest {
	string        s0 = "01234";
	const(char)[] s1 = s0[1 .. $];
	const(void)[] s2 = s1.castTo!(const(void)[]);
	string        s3 = s1.idup;

	assert( s0.isSliceOf(s0));
	assert( s1.isSliceOf(s0));
	assert( s2.isSliceOf(s0));
	assert(!s3.isSliceOf(s0));

	assert(!s0.isSliceOf(s1));
	assert( s1.isSliceOf(s1));
	assert( s2.isSliceOf(s1));
	assert(!s3.isSliceOf(s1));

	assert(!s0.isSliceOf(s2));
	assert( s1.isSliceOf(s2));
	assert( s2.isSliceOf(s2));
	assert(!s3.isSliceOf(s2));

	assert(!s0.isSliceOf(s3));
	assert(!s1.isSliceOf(s3));
	assert(!s2.isSliceOf(s3));
	assert( s3.isSliceOf(s3));

	assert(s1.length == 4);
	assert(s1[0 .. 0].isSliceOf(s1));
	assert(s1[0 .. 1].isSliceOf(s1));
	assert(s1[1 .. 2].isSliceOf(s1));
	assert(s1[1 .. 3].isSliceOf(s1));
	assert(s1[1 .. $].isSliceOf(s1));
	assert(s1[$ .. $].isSliceOf(s1));
}

/++
	Does math as a 64 bit number, but saturates at int.min and int.max when converting back to a 32 bit int.

	History:
		Added January 1, 2025
+/
alias NonOverflowingInt = NonOverflowingIntBase!(int.min, int.max);

/// ditto
alias NonOverflowingUint = NonOverflowingIntBase!(0, int.max);

/// ditto
struct NonOverflowingIntBase(int min, int max) {
	this(long v) {
		this.value = v;
	}

	private long value;

	NonOverflowingInt opBinary(string op)(long rhs) {
		return NonOverflowingInt(mixin("this.value", op, "rhs"));
	}
	NonOverflowingInt opBinary(string op)(NonOverflowingInt rhs) {
		return this.opBinary!op(rhs.value);
	}
	NonOverflowingInt opUnary(string op)() {
		return NonOverflowingInt(mixin(op, "this.value"));
	}
	NonOverflowingInt opOpAssign(string op)(long rhs) {
		return this = this.opBinary!(op)(rhs);
	}
	NonOverflowingInt opOpAssign(string op)(NonOverflowingInt rhs) {
		return this = this.opBinary!(op)(rhs.value);
	}

	int getValue() const {
		if(value < min)
			return min;
		else if(value > max)
			return max;
		return cast(int) value;
	}

	alias getValue this;
}

unittest {
	assert(-5.NonOverflowingInt - int.max == int.min);
	assert(-5.NonOverflowingInt + 5 == 0);

	assert(NonOverflowingInt(5) + int.max - 5 == int.max);
	assert(NonOverflowingInt(5) + int.max - int.max - 5 == 0); // it truncates at the end of the op chain, not at intermediates
	assert(NonOverflowingInt(0) + int.max * 2L == int.max); // note the L there is required to pass since the order of operations means mul done before it gets to the NonOverflowingInt controls
}

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
		Borrows a slice of the pointer up to (but not including) the zero terminator.
	+/
	const(char)[] borrow() const @system {
		if(raw is null)
			return null;

		const(char)* p = raw;
		int length;
		while(*p++) length++;

		return raw[0 .. length];
	}
}

/+
/++
	A runtime tagged union, aka a sumtype.

	History:
		Added February 15, 2025
+/
struct Union(T...) {
	private uint contains_;
	private union {
		private T payload;
	}

	static foreach(index, type; T)
	@implicit public this(type t) {
		contains_ = index;
		payload[index] = t;
	}

	bool contains(Part)() const {
		static assert(indexFor!Part != -1);
		return contains_ == indexFor!Part;
	}

	inout(Part) get(Part)() inout {
		if(!contains!Part) {
			throw new ArsdException!"Dynamic type mismatch"(indexFor!Part, contains_);
		}
		return payload[indexFor!Part];
	}

	private int indexFor(Part)() {
		foreach(idx, thing; T)
			static if(is(T == Part))
				return idx;
		return -1;
	}
}
+/

/+
	DateTime
		year: 16 bits (-32k to +32k)
		month: 4 bits
		day: 5 bits

		hour: 5 bits
		minute: 6 bits
		second: 6 bits

		total: 25 bits + 17 bits = 42 bits

		fractional seconds: 10 bits

		accuracy flags: date_valid | time_valid = 2 bits

		54 bits used, 8 bits remain. reserve 1 for signed.

		would need 11 bits for minute-precise dt offset but meh.
+/

/++
	A packed date/time/datetime representation added for use with LimitedVariant.

	You should probably not use this much directly, it is mostly an internal storage representation.
+/
struct PackedDateTime {
	private ulong packedData;

	string toString() const {
		char[64] buffer;
		size_t pos;

		if(hasDate) {
			pos += intToString(year, buffer[pos .. $], IntToStringArgs().withPadding(4)).length;
			buffer[pos++] = '-';
			pos += intToString(month, buffer[pos .. $], IntToStringArgs().withPadding(2)).length;
			buffer[pos++] = '-';
			pos += intToString(day, buffer[pos .. $], IntToStringArgs().withPadding(2)).length;
		}

		if(hasTime) {
			if(pos)
				buffer[pos++] = 'T';

			pos += intToString(hours, buffer[pos .. $], IntToStringArgs().withPadding(2)).length;
			buffer[pos++] = ':';
			pos += intToString(minutes, buffer[pos .. $], IntToStringArgs().withPadding(2)).length;
			buffer[pos++] = ':';
			pos += intToString(seconds, buffer[pos .. $], IntToStringArgs().withPadding(2)).length;
			if(fractionalSeconds) {
				buffer[pos++] = '.';
				pos += intToString(fractionalSeconds, buffer[pos .. $], IntToStringArgs().withPadding(4)).length;
			}
		}

		return buffer[0 .. pos].idup;
	}

	/++
	+/
	int fractionalSeconds() const { return getFromMask(00, 10); }
	/// ditto
	void fractionalSeconds(int a) {     setWithMask(a, 00, 10); }

	/// ditto
	int  seconds() const          { return getFromMask(10,  6); }
	/// ditto
	void seconds(int a)           {     setWithMask(a, 10,  6); }
	/// ditto
	int  minutes() const          { return getFromMask(16,  6); }
	/// ditto
	void minutes(int a)           {     setWithMask(a, 16,  6); }
	/// ditto
	int  hours() const            { return getFromMask(22,  5); }
	/// ditto
	void hours(int a)             {     setWithMask(a, 22,  5); }

	/// ditto
	int  day() const              { return getFromMask(27,  5); }
	/// ditto
	void day(int a)               {     setWithMask(a, 27,  5); }
	/// ditto
	int  month() const            { return getFromMask(32,  4); }
	/// ditto
	void month(int a)             {     setWithMask(a, 32,  4); }
	/// ditto
	int  year() const             { return getFromMask(36, 16); }
	/// ditto
	void year(int a)              {     setWithMask(a, 36, 16); }

	/// ditto
	bool hasTime() const          { return cast(bool) getFromMask(52,  1); }
	/// ditto
	void hasTime(bool a)          {     setWithMask(a, 52,  1); }
	/// ditto
	bool hasDate() const          { return cast(bool) getFromMask(53,  1); }
	/// ditto
	void hasDate(bool a)          {     setWithMask(a, 53,  1); }

	private void setWithMask(int a, int bitOffset, int bitCount) {
		auto mask = (1UL << bitCount) - 1;

		packedData &= ~(mask << bitOffset);
		packedData |= (a & mask) << bitOffset;
	}

	private int getFromMask(int bitOffset, int bitCount) const {
		ulong packedData = this.packedData;
		packedData >>= bitOffset;

		ulong mask = (1UL << bitCount) - 1;

		return cast(int) (packedData & mask);
	}
}

unittest {
	PackedDateTime dt;
	dt.hours = 14;
	dt.minutes = 30;
	dt.seconds = 25;
	dt.hasTime = true;

	assert(dt.toString() == "14:30:25", dt.toString());

	dt.hasTime = false;
	dt.year = 2024;
	dt.month = 5;
	dt.day = 31;
	dt.hasDate = true;

	assert(dt.toString() == "2024-05-31", dt.toString());
	dt.hasTime = true;
	assert(dt.toString() == "2024-05-31T14:30:25", dt.toString());
}

/++
	Basically a Phobos SysTime but standing alone as a simple 64 bit integer (but wrapped) for compatibility with LimitedVariant.
+/
struct SimplifiedUtcTimestamp {
	long timestamp;

	string toString() const {
		import core.stdc.time;
		char[128] buffer;
		auto ut = toUnixTime();
		tm* t = gmtime(&ut);
		if(t is null)
			return "null time";

		return buffer[0 .. strftime(buffer.ptr, buffer.length, "%Y-%m-%dT%H:%M:%SZ", t)].idup;
	}

	version(Windows)
		alias time_t = int;

	static SimplifiedUtcTimestamp fromUnixTime(time_t t) {
		return SimplifiedUtcTimestamp(621_355_968_000_000_000L + t * 1_000_000_000L / 100);
	}

	time_t toUnixTime() const {
		return cast(time_t) ((timestamp - 621_355_968_000_000_000L) / 1_000_000_0); // hnsec = 7 digits
	}
}

unittest {
	SimplifiedUtcTimestamp sut = SimplifiedUtcTimestamp.fromUnixTime(86_400);
	assert(sut.toString() == "1970-01-02T00:00:00Z");
}

/++
	A limited variant to hold just a few types. It is made for the use of packing a small amount of extra data into error messages and some transit across virtual function boundaries.
+/
/+
	ALL OF THESE ARE SUBJECT TO CHANGE

	* if length and ptr are both 0, it is null
	* if ptr == 1, length is an integer
	* if ptr == 2, length is an unsigned integer (suggest printing in hex)
	* if ptr == 3, length is a combination of flags (suggest printing in binary)
	* if ptr == 4, length is a unix permission thing (suggest printing in octal)
	* if ptr == 5, length is a double float
	* if ptr == 6, length is an Object ref (reinterpret casted to void*)

	* if ptr == 7, length is a ticks count (from MonoTime)
	* if ptr == 8, length is a utc timestamp (hnsecs)
	* if ptr == 9, length is a duration (signed hnsecs)
	* if ptr == 10, length is a date or date time (bit packed, see flags in data to determine if it is a Date, Time, or DateTime)
	* if ptr == 11, length is a dchar
	* if ptr == 12, length is a bool (redundant to int?)

	13, 14 reserved. prolly decimals. (4, 8 digits after decimal)

	* if ptr == 15, length must be 0. this holds an empty, non-null, SSO string.
	* if ptr >= 16 && < 24, length is reinterpret-casted a small string of length of (ptr & 0x7) + 1

	* if length == size_t.max, ptr is interpreted as a stringz
	* if ptr >= 1024, it is a non-null D string or byte array. It is a string if the length high bit is clear, a byte array if it is set. the length is what is left after you mask that out.

	All other ptr values are reserved for future expansion.

	It basically can store:
		null
			type details = must be 0
		int (actually long)
			type details = formatting hints
		float (actually double)
			type details = formatting hints
		dchar (actually enum - upper half is the type tag, lower half is the member tag)
			type details = ???
		decimal
			type details = precision specifier
		object
			type details = ???
		timestamp
			type details: ticks, utc timestamp, relative duration

		sso
		stringz

		or it is bytes or a string; a normal D array (just bytes has a high bit set on length).

	But there are subtypes of some of those; ints can just have formatting hints attached.
		Could reserve 0-7 as low level type flag (null, int, float, pointer, object)
		15-24 still can be the sso thing

		We have 10 bits really.

		00000 00000
		????? OOLLL

		The ????? are type details bits.

	64 bits decmial to 4 points of precision needs... 14 bits for the small part (so max of 4 digits)? so 50 bits for the big part (max of about 1 quadrillion)
		...actually it can just be a dollars * 10000 + cents * 100.

+/
struct LimitedVariant {

	/++

	+/
	enum Contains {
		null_,
		intDecimal,
		intHex,
		intBinary,
		intOctal,
		double_,
		object,

		monoTime,
		utcTimestamp,
		duration,
		dateTime,

		// FIXME boolean? char? decimal?
		// could do enums by way of a pointer but kinda iffy

		// maybe some kind of prefixed string too for stuff like xml and json or enums etc.

		// fyi can also use stringzs or length-prefixed string pointers
		emptySso,
		stringSso,
		stringz,
		string,
		bytes,

		invalid,
	}

	/++
		Each datum stored in the LimitedVariant has a tag associated with it.

		Each tag belongs to one or more data families.
	+/
	Contains contains() const {
		auto tag = cast(size_t) ptr;
		if(ptr is null && length is null)
			return Contains.null_;
		else switch(tag) {
			case 1: return Contains.intDecimal;
			case 2: return Contains.intHex;
			case 3: return Contains.intBinary;
			case 4: return Contains.intOctal;
			case 5: return Contains.double_;
			case 6: return Contains.object;

			case 7: return Contains.monoTime;
			case 8: return Contains.utcTimestamp;
			case 9: return Contains.duration;
			case 10: return Contains.dateTime;

			case 15: return length is null ? Contains.emptySso : Contains.invalid;
			default:
				if(tag >= 16 && tag < 24) {
					return Contains.stringSso;
				} else if(tag >= 1024) {
					if(cast(size_t) length == size_t.max)
						return Contains.stringz;
					else
						return isHighBitSet ? Contains.bytes : Contains.string;
				} else {
					return Contains.invalid;
				}
		}
	}

	/// ditto
	bool containsNull() const {
		return contains() == Contains.null_;
	}

	/// ditto
	bool containsInt() const {
		with(Contains)
		switch(contains) {
			case intDecimal, intHex, intBinary, intOctal:
				return true;
			default:
				return false;
		}
	}

	// all specializations of int...

	/// ditto
	bool containsMonoTime() const {
		return contains() == Contains.monoTime;
	}
	/// ditto
	bool containsUtcTimestamp() const {
		return contains() == Contains.utcTimestamp;
	}
	/// ditto
	bool containsDuration() const {
		return contains() == Contains.duration;
	}
	/// ditto
	bool containsDateTime() const {
		return contains() == Contains.dateTime;
	}

	// done int specializations

	/// ditto
	bool containsString() const {
		with(Contains)
		switch(contains) {
			case null_, emptySso, stringSso, string:
			case stringz:
				return true;
			default:
				return false;
		}
	}

	/// ditto
	bool containsDouble() const {
		with(Contains)
		switch(contains) {
			case double_:
				return true;
			default:
				return false;
		}
	}

	/// ditto
	bool containsBytes() const {
		with(Contains)
		switch(contains) {
			case bytes, null_:
				return true;
			default:
				return false;
		}
	}

	private const(void)* length;
	private const(ubyte)* ptr;

	private void Throw() const {
		throw ArsdException!"LimitedVariant"(cast(size_t) length, cast(size_t) ptr);
	}

	private bool isHighBitSet() const {
		return (cast(size_t) length >> (size_t.sizeof * 8 - 1) & 0x1) != 0;
	}

	/++
		getString gets a reference to the string stored internally, see [toString] to get a string representation or whatever is inside.

	+/
	const(char)[] getString() const return {
		with(Contains)
		switch(contains()) {
			case null_:
				return null;
			case emptySso:
				return (cast(const(char)*) ptr)[0 .. 0]; // zero length, non-null
			case stringSso:
				auto len = ((cast(size_t) ptr) & 0x7) + 1;
				return (cast(char*) &length)[0 .. len];
			case string:
				return (cast(const(char)*) ptr)[0 .. cast(size_t) length];
			case stringz:
				return arsd.core.stringz(cast(char*) ptr).borrow;
			default:
				Throw(); assert(0);
		}
	}

	/// ditto
	long getInt() const {
		if(containsInt)
			return cast(long) length;
		else
			Throw();
		assert(0);
	}

	/// ditto
	double getDouble() const {
		if(containsDouble) {
			floathack hack;
			hack.e = cast(void*) length; // casting away const
			return hack.d;
		} else
			Throw();
		assert(0);
	}

	/// ditto
	const(ubyte)[] getBytes() const {
		with(Contains)
		switch(contains()) {
			case null_:
				return null;
			case bytes:
				return ptr[0 .. (cast(size_t) length) & ((1UL << (size_t.sizeof * 8 - 1)) - 1)];
			default:
				Throw(); assert(0);
		}
	}

	/// ditto
	Object getObject() const {
		with(Contains)
		switch(contains()) {
			case null_:
				return null;
			case object:
				return cast(Object) length; // FIXME const correctness sigh
			default:
				Throw(); assert(0);
		}
	}

	/// ditto
	MonoTime getMonoTime() const {
		if(containsMonoTime) {
			MonoTime time;
			__traits(getMember, time, "_ticks") = cast(long) length;
			return time;
		} else
			Throw();
		assert(0);
	}
	/// ditto
	SimplifiedUtcTimestamp getUtcTimestamp() const {
		if(containsUtcTimestamp)
			return SimplifiedUtcTimestamp(cast(long) length);
		else
			Throw();
		assert(0);
	}
	/// ditto
	Duration getDuration() const {
		if(containsDuration)
			return hnsecs(cast(long) length);
		else
			Throw();
		assert(0);
	}
	/// ditto
	PackedDateTime getDateTime() const {
		if(containsDateTime)
			return PackedDateTime(cast(long) length);
		else
			Throw();
		assert(0);
	}


	/++

	+/
	string toString() const {

		string intHelper(string prefix, int radix) {
			char[128] buffer;
			buffer[0 .. prefix.length] = prefix[];
			char[] toUse = buffer[prefix.length .. $];

			auto got = intToString(getInt(), toUse[], IntToStringArgs().withRadix(radix));

			return buffer[0 .. prefix.length + got.length].idup;
		}

		with(Contains)
		final switch(contains()) {
			case null_:
				return "<null>";
			case intDecimal:
				return intHelper("", 10);
			case intHex:
				return intHelper("0x", 16);
			case intBinary:
				return intHelper("0b", 2);
			case intOctal:
				return intHelper("0o", 8);
			case emptySso, stringSso, string, stringz:
				return getString().idup;
			case bytes:
				auto b = getBytes();

				return "<bytes>"; // FIXME
			case object:
				auto o = getObject();
				return o is null ? "null" : o.toString();
			case monoTime:
				return getMonoTime.toString();
			case utcTimestamp:
				return getUtcTimestamp().toString();
			case duration:
				return getDuration().toString();
			case dateTime:
				return getDateTime().toString();
			case double_:
				auto d = getDouble();

				import core.stdc.stdio;
				char[64] buffer;
				auto count = snprintf(buffer.ptr, buffer.length, "%.17lf", d);
				return buffer[0 .. count].idup;
			case invalid:
				return "<invalid>";
		}
	}

	/++
		Note for integral types that are not `int` and `long` (for example, `short` or `ubyte`), you might want to explicitly convert them to `int`.
	+/
	this(string s) {
		ptr = cast(const(ubyte)*) s.ptr;
		length = cast(void*) s.length;
	}

	/// ditto
	this(const(char)* stringz) {
		if(stringz !is null) {
			ptr = cast(const(ubyte)*) stringz;
			length = cast(void*) size_t.max;
		} else {
			ptr = null;
			length = null;
		}
	}

	/// ditto
	this(const(ubyte)[] b) {
		ptr = cast(const(ubyte)*) b.ptr;
		length = cast(void*) (b.length | (1UL << (size_t.sizeof * 8 - 1)));
	}

	/// ditto
	this(long l, int base = 10) {
		int tag;
		switch(base) {
			case 10: tag = 1; break;
			case 16: tag = 2; break;
			case  2: tag = 3; break;
			case  8: tag = 4; break;
			default: assert(0, "You passed an invalid base to LimitedVariant");
		}
		ptr = cast(ubyte*) tag;
		length = cast(void*) l;
	}

	/// ditto
	this(int i, int base = 10) {
		this(cast(long) i, base);
	}

	/// ditto
	this(bool i) {
		// FIXME?
		this(cast(long) i);
	}

	/// ditto
	this(double d) {
		// the reinterpret cast hack crashes dmd! omg
		ptr = cast(ubyte*) 5;

		floathack h;
		h.d = d;

		this.length = h.e;
	}

	/// ditto
	this(Object o) {
		this.ptr = cast(ubyte*) 6;
		this.length = cast(void*) o;
	}

	/// ditto
	this(MonoTime a) {
		this.ptr = cast(ubyte*) 7;
		this.length = cast(void*) a.ticks;
	}

	/// ditto
	this(SimplifiedUtcTimestamp a) {
		this.ptr = cast(ubyte*) 8;
		this.length = cast(void*) a.timestamp;
	}

	/// ditto
	this(Duration a) {
		this.ptr = cast(ubyte*) 9;
		this.length = cast(void*) a.total!"hnsecs";
	}

	/// ditto
	this(PackedDateTime a) {
		this.ptr = cast(ubyte*) 10;
		this.length = cast(void*) a.packedData;
	}
}

unittest {
	LimitedVariant v = LimitedVariant("foo");
	assert(v.containsString());
	assert(!v.containsInt());
	assert(v.getString() == "foo");

	LimitedVariant v2 = LimitedVariant(4);
	assert(v2.containsInt());
	assert(!v2.containsString());
	assert(v2.getInt() == 4);

	LimitedVariant v3 = LimitedVariant(cast(ubyte[]) [1, 2, 3]);
	assert(v3.containsBytes());
	assert(!v3.containsString());
	assert(v3.getBytes() == [1, 2, 3]);
}

private union floathack {
	// in 32 bit we'll use float instead since it at least fits in the void*
	static if(double.sizeof == (void*).sizeof) {
		double d;
	} else {
		float d;
	}
	void* e;
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

// might move RecyclableMemory here

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
		buffer = buffer[0 .. data.length + 1];
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
	int groupCount;

	do {
		auto remainder = value % radix;
		value = value / radix;

		if(groupSize && groupCount == groupSize) {
			buffer[pos++] = args.separator;
			groupCount = 0;
		}

		buffer[pos++] = cast(char) (remainder < 10 ? (remainder + '0') : (remainder - 10 + args.ten));
		groupCount++;
		digitCount++;
	} while(value);

	if(digitsPad > 0) {
		while(digitCount < digitsPad) {
			if(groupSize && groupCount == groupSize) {
				buffer[pos++] = args.separator;
				groupCount = 0;
			}
			buffer[pos++] = args.padWith;
			digitCount++;
			groupCount++;
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

struct FloatToStringArgs {
	private {
		// whole number component
		ubyte padTo;
		char padWith;
		ubyte groupSize;
		char separator;

		// for the fractional component
		ubyte minimumPrecision =  0; // will always show at least this many digits after the decimal (if it is 0 there may be no decimal)
		ubyte maximumPrecision = 32; // will round to this many after the decimal

		bool useScientificNotation; // if this is true, note the whole number component will always be exactly one digit, so the pad stuff applies to the exponent only and it assumes pad with zero's to two digits
	}

	FloatToStringArgs withPadding(int padTo, char padWith = '0') {
		FloatToStringArgs args = this;
		args.padTo = cast(ubyte) padTo;
		args.padWith = padWith;
		return args;
	}

	FloatToStringArgs withGroupSeparator(int groupSize, char separator = '_') {
		FloatToStringArgs args = this;
		args.groupSize = cast(ubyte) groupSize;
		args.separator = separator;
		return args;
	}

	FloatToStringArgs withPrecision(int minDigits, int maxDigits = 0) {
		FloatToStringArgs args = this;
		args.minimumPrecision = cast(ubyte) minDigits;
		if(maxDigits < minDigits)
			maxDigits = minDigits;
		args.maximumPrecision = cast(ubyte) maxDigits;
		return args;
	}

	FloatToStringArgs withScientificNotation(bool enabled) {
		FloatToStringArgs args = this;
		args.useScientificNotation = enabled;
		return args;
	}
}

char[] floatToString(double value, char[] buffer, FloatToStringArgs args = FloatToStringArgs.init) {
	// actually doing this is pretty painful, so gonna pawn it off on the C lib
	import core.stdc.stdio;
	// FIXME: what if there's a locale in place that changes the decimal point?
	auto ret = snprintf(buffer.ptr, buffer.length, args.useScientificNotation ? "%.*e" : "%.*f", args.maximumPrecision, value);
	if(!args.useScientificNotation && (args.padTo || args.groupSize)) {
		char[32] scratch = void;
		auto idx = buffer[0 .. ret].indexOf(".");

		int digitsOutput = 0;
		int digitsGrouped = 0;
		if(idx > 0) {
			// there is a whole number component
			int pos = cast(int) scratch.length;

			auto splitPoint = idx;

			while(idx) {
				if(args.groupSize && digitsGrouped == args.groupSize) {
					scratch[--pos] = args.separator;
					digitsGrouped = 0;
				}
				scratch[--pos] = buffer[--idx];

				digitsOutput++;
				digitsGrouped++;
			}

			if(args.padTo)
			while(digitsOutput < args.padTo) {
				if(args.groupSize && digitsGrouped == args.groupSize) {
					scratch[--pos] = args.separator;
					digitsGrouped = 0;
				}

				scratch[--pos] = args.padWith;

				digitsOutput++;
				digitsGrouped++;
			}

			char[32] remainingBuffer;
			remainingBuffer[0 .. ret - splitPoint]= buffer[splitPoint .. ret];

			buffer[0 .. scratch.length - pos] = scratch[pos .. $];
			buffer[scratch.length - pos .. scratch.length - pos + ret - splitPoint] = remainingBuffer[0 .. ret - splitPoint];

			ret = cast(int) scratch.length - pos + ret - splitPoint;
		}
	}
	// FIXME: if maximum precision....?
	return buffer[0 .. ret];
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

	assert(intToString(4000, buffer[], IntToStringArgs().withPadding(4).withGroupSeparator(3, ',')) == "4,000");
	assert(intToString(400, buffer[], IntToStringArgs().withPadding(4).withGroupSeparator(3, ',')) == "0,400");

	const pi = 3.14159256358979;
	assert(floatToString(pi, buffer[], FloatToStringArgs().withPrecision(3)) == "3.142");
	assert(floatToString(pi, buffer[], FloatToStringArgs().withPrecision(2)) == "3.14");
	assert(floatToString(pi, buffer[], FloatToStringArgs().withPrecision(0)) == "3");

	assert(floatToString(4.0, buffer[], FloatToStringArgs().withPrecision(0)) == "4");
	assert(floatToString(4.0, buffer[], FloatToStringArgs().withPrecision(3)) == "4.000");

	assert(floatToString(4.0, buffer[], FloatToStringArgs().withPadding(3).withPrecision(3)) == "004.000");
	assert(floatToString(4.0, buffer[], FloatToStringArgs().withPadding(3).withGroupSeparator(3, ',').withPrecision(3)) == "004.000");
	assert(floatToString(4.0, buffer[], FloatToStringArgs().withPadding(4).withGroupSeparator(3, ',').withPrecision(3)) == "0,004.000");
	assert(floatToString(4000.0, buffer[], FloatToStringArgs().withPadding(4).withGroupSeparator(3, ',').withPrecision(3)) == "4,000.000");

	assert(floatToString(pi*10, buffer[], FloatToStringArgs().withPrecision(2).withScientificNotation(true)) == "3.14e+01");
}

/++
	History:
		Moved from color.d to core.d in March 2023 (dub v11.0).
+/
nothrow @safe @nogc pure
inout(char)[] stripInternal(return inout(char)[] s) {
	bool isAllWhitespace = true;
	foreach(i, char c; s)
		if(c != ' ' && c != '\t' && c != '\n' && c != '\r') {
			s = s[i .. $];
			isAllWhitespace = false;
			break;
		}

	if(isAllWhitespace)
		return s[$..$];

	for(int a = cast(int)(s.length - 1); a > 0; a--) {
		char c = s[a];
		if(c != ' ' && c != '\t' && c != '\n' && c != '\r') {
			s = s[0 .. a + 1];
			break;
		}
	}

	return s;
}

/// ditto
nothrow @safe @nogc pure
inout(char)[] stripRightInternal(return inout(char)[] s) {
	bool isAllWhitespace = true;
	foreach_reverse(a, c; s) {
		if(c != ' ' && c != '\t' && c != '\n' && c != '\r') {
			s = s[0 .. a + 1];
			isAllWhitespace = false;
			break;
		}
	}
	if(isAllWhitespace)
		s = s[0..0];

	return s;

}

/++
	Shortcut for converting some types to string without invoking Phobos (but it may as a last resort).

	History:
		Moved from color.d to core.d in March 2023 (dub v11.0).
+/
string toStringInternal(T)(T t) {
	return writeGuts(null, null, null, false, &makeString, t);
	/+
	char[64] buffer;
	static if(is(typeof(t.toString) : string))
		return t.toString();
	else static if(is(T : string))
		return t;
	else static if(is(T == enum)) {
		switch(t) {
			foreach(memberName; __traits(allMembers, T)) {
				case __traits(getMember, T, memberName):
					return memberName;
			}
			default:
				return "<unknown>";
		}
	} else static if(is(T : long)) {
		return intToString(t, buffer[]).idup;
	} else static if(is(T : const E[], E)) {
		string ret = "[";
		foreach(idx, e; t) {
			if(idx)
				ret ~= ", ";
			ret ~= toStringInternal(e);
		}
		ret ~= "]";
		return ret;
	} else static if(is(T : double)) {
		import core.stdc.stdio;
		auto ret = snprintf(buffer.ptr, buffer.length, "%f", t);
		return buffer[0 .. ret].idup;
	} else {
		static assert(0, T.stringof ~ " makes compile too slow");
		// import std.conv; return to!string(t);
	}
	+/
}

/++

+/
string flagsToString(Flags)(ulong value) {
	string r;

	void add(string memberName) {
		if(r.length)
			r ~= " | ";
		r ~= memberName;
	}

	string none = "<none>";

	foreach(memberName; __traits(allMembers, Flags)) {
		auto flag = cast(ulong) __traits(getMember, Flags, memberName);
		if(flag) {
			if((value & flag) == flag)
				add(memberName);
		} else {
			none = memberName;
		}
	}

	if(r.length == 0)
		r = none;

	return r;
}

unittest {
	enum MyFlags {
		none = 0,
		a = 1,
		b = 2
	}

	assert(flagsToString!MyFlags(3) == "a | b");
	assert(flagsToString!MyFlags(0) == "none");
	assert(flagsToString!MyFlags(2) == "b");
}

private enum dchar replacementDchar = '\uFFFD';

package size_t encodeUtf8(out char[4] buf, dchar c) @safe pure {
    if (c <= 0x7F)
    {
        assert(isValidDchar(c));
        buf[0] = cast(char) c;
        return 1;
    }
    if (c <= 0x7FF)
    {
        assert(isValidDchar(c));
        buf[0] = cast(char)(0xC0 | (c >> 6));
        buf[1] = cast(char)(0x80 | (c & 0x3F));
        return 2;
    }
    if (c <= 0xFFFF)
    {
        if (0xD800 <= c && c <= 0xDFFF)
            c = replacementDchar;

        assert(isValidDchar(c));
    L3:
        buf[0] = cast(char)(0xE0 | (c >> 12));
        buf[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buf[2] = cast(char)(0x80 | (c & 0x3F));
        return 3;
    }
    if (c <= 0x10FFFF)
    {
        assert(isValidDchar(c));
        buf[0] = cast(char)(0xF0 | (c >> 18));
        buf[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
        buf[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buf[3] = cast(char)(0x80 | (c & 0x3F));
        return 4;
    }

    assert(!isValidDchar(c));
    c = replacementDchar;
    goto L3;
}



private bool isValidDchar(dchar c) pure nothrow @safe @nogc
{
    return c < 0xD800 || (c > 0xDFFF && c <= 0x10FFFF);
}

// technically s is octets but meh
package string encodeUriComponent(string s) {
	char[3] encodeChar(char c) {
		char[3] buffer;
		buffer[0] = '%';

		enum hexchars = "0123456789ABCDEF";
		buffer[1] = hexchars[c >> 4];
		buffer[2] = hexchars[c & 0x0f];

		return buffer;
	}

	string n;
	size_t previous = 0;
	foreach(idx, char ch; s) {
		if(
			(ch >= 'A' && ch <= 'Z')
			||
			(ch >= 'a' && ch <= 'z')
			||
			(ch >= '0' && ch <= '9')
			|| ch == '-' || ch == '_' || ch == '.' || ch == '~' // unreserved set
			|| ch == '!' || ch == '*' || ch == '\''|| ch == '(' || ch == ')' // subdelims but allowed in uri component (phobos also no encode them)
		) {
			// does not need encoding
		} else {
			n ~= s[previous .. idx];
			n ~= encodeChar(ch);
			previous = idx + 1;
		}
	}

	if(n.length) {
		n ~= s[previous .. $];
		return n;
	} else {
		return s; // nothing needed encoding
	}
}
unittest {
	assert(encodeUriComponent("foo") == "foo");
	assert(encodeUriComponent("f33Ao") == "f33Ao");
	assert(encodeUriComponent("/") == "%2F");
	assert(encodeUriComponent("/foo") == "%2Ffoo");
	assert(encodeUriComponent("foo/") == "foo%2F");
	assert(encodeUriComponent("foo/bar") == "foo%2Fbar");
	assert(encodeUriComponent("foo/bar/") == "foo%2Fbar%2F");
}

// FIXME: I think if translatePlusToSpace we're supposed to do newline normalization too
package string decodeUriComponent(string s, bool translatePlusToSpace = false) {
	int skipping = 0;
	size_t previous = 0;
	string n = null;
	foreach(idx, char ch; s) {
		if(skipping) {
			skipping--;
			continue;
		}

		if(ch == '%') {
			int hexDecode(char c) {
				if(c >= 'A' && c <= 'F')
					return c - 'A' + 10;
				else if(c >= 'a' && c <= 'f')
					return c - 'a' + 10;
				else if(c >= '0' && c <= '9')
					return c - '0' + 0;
				else
					throw ArsdException!"Invalid percent-encoding"("Invalid char encountered", idx, s);
			}

			skipping = 2;
			n ~= s[previous .. idx];

			if(idx + 2 >= s.length)
				throw ArsdException!"Invalid percent-encoding"("End of string reached", idx, s);

			n ~= (hexDecode(s[idx + 1]) << 4) | hexDecode(s[idx + 2]);

			previous = idx + 3;
		} else if(translatePlusToSpace && ch == '+') {
			n ~= s[previous .. idx];
			n ~= " ";
			previous = idx + 1;
		}
	}

	if(n.length) {
		n ~= s[previous .. $];
		return n;
	} else {
		return s; // nothing needed decoding
	}
}

unittest {
	assert(decodeUriComponent("foo") == "foo");
	assert(decodeUriComponent("%2F") == "/");
	assert(decodeUriComponent("%2f") == "/");
	assert(decodeUriComponent("%2Ffoo") == "/foo");
	assert(decodeUriComponent("foo%2F") == "foo/");
	assert(decodeUriComponent("foo%2Fbar") == "foo/bar");
	assert(decodeUriComponent("foo%2Fbar%2F") == "foo/bar/");
	assert(decodeUriComponent("%2F%2F%2F") == "///");

	assert(decodeUriComponent("+") == "+");
	assert(decodeUriComponent("+", true) == " ");
}

public auto toDelegate(T)(T t) {
	// static assert(is(T == function)); // lol idk how to do what i actually want here

	static if(is(T Return == return))
	static if(is(typeof(*T) Params == __parameters)) {
		static struct Wrapper {
			Return call(Params params) {
				return (cast(T) &this)(params);
			}
		}
		return &((cast(Wrapper*) t).call);
	} else static assert(0, "could not get params; is it already a delegate you can pass directly?");
	else static assert(0, "could not get return value, if it is a functor maybe try getting a delegate with `&yourobj.opCall` instead of toDelegate(yourobj)");
}

@system unittest {
	int function(int) fn;
	fn = (a) { return a; };

	int delegate(int) dg = toDelegate(fn);

	assert(dg.ptr is fn); // it stores the original function as the context pointer
	assert(dg.funcptr !is fn); // which is called through a lil trampoline
	assert(dg(5) == 5); // and forwards the args correctly
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

+/
class InvalidArgumentsException : ArsdExceptionBase {
	static struct InvalidArgument {
		string name;
		string description;
		LimitedVariant givenValue;
	}

	InvalidArgument[] invalidArguments;

	this(InvalidArgument[] invalidArguments, string functionName = __PRETTY_FUNCTION__, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this.invalidArguments = invalidArguments;
		super(functionName, file, line, next);
	}

	this(string argumentName, string argumentDescription, LimitedVariant givenArgumentValue = LimitedVariant.init, string functionName = __PRETTY_FUNCTION__, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this([
			InvalidArgument(argumentName, argumentDescription, givenArgumentValue)
		], functionName, file, line, next);
	}

	this(string argumentName, string argumentDescription, string functionName = __PRETTY_FUNCTION__, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this(argumentName, argumentDescription, LimitedVariant.init, functionName, file, line, next);
	}

	override void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {
		// FIXME: print the details better
		foreach(arg; invalidArguments)
			sink(arg.name, arg.givenValue.toString ~ " - " ~ arg.description);
	}
}

/++
	Base class for when you've requested a feature that is not available. It may not be available because it is possible, but not yet implemented, or it might be because it is impossible on your operating system.
+/
class FeatureUnavailableException : ArsdExceptionBase {
	this(string featureName = __PRETTY_FUNCTION__, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		super(featureName, file, line, next);
	}
}

/++
	This means the feature could be done, but I haven't gotten around to implementing it yet. If you email me, I might be able to add it somewhat quickly and get back to you.
+/
class NotYetImplementedException : FeatureUnavailableException {
	this(string featureName = __PRETTY_FUNCTION__, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		super(featureName, file, line, next);
	}

}

/++
	This means the feature is not supported by your current operating system. You might be able to get it in an update, but you might just have to find an alternate way of doing things.
+/
class NotSupportedException : FeatureUnavailableException {
	this(string featureName, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		super(featureName, file, line, next);
	}
}

/++
	This is a generic exception with attached arguments. It is used when I had to throw something but didn't want to write a new class.

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
		Returns if the code indicated success.

		Please note that many calls do not actually set a code to success, but rather just don't touch it. Thus this may only be true on `init`.
	+/
	bool wasSuccessful() const {
		final switch(type) {
			case Type.errno:
				return this.code == 0;
			case Type.win32:
				return this.code == 0;
		}
	}

	/++
		Constructs a string containing both the code and the explanation string.
	+/
	string toString() const {
		return "[" ~ codeAsString ~ "] " ~ errorString;
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
				return buffer[0 .. 2 + intToString(cast(uint) code, buffer[2 .. $], IntToStringArgs().withRadix(16).withPadding(8)).length].idup;
		}
	}

	/++
		A text explanation of the code. See [codeAsString] for a string representation of the numeric representation.
	+/
	string errorString() const @trusted {
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
struct SavedArgument {
	string name;
	LimitedVariant value;
}

/++

+/
class SystemApiException : ArsdExceptionBase {
	this(string msg, int originalErrorNo, scope SavedArgument[] args = null, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this(msg, SystemErrorCode(originalErrorNo), args, file, line, next);
	}

	version(Windows)
	this(string msg, DWORD windowsError, scope SavedArgument[] args = null, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this(msg, SystemErrorCode(windowsError), args, file, line, next);
	}

	this(string msg, SystemErrorCode code, SavedArgument[] args = null, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this.errorCode = code;

		// discard stuff that won't fit
		if(args.length > this.args.length)
			args = args[0 .. this.args.length];

		this.args[0 .. args.length] = args[];

		super(msg, file, line, next);
	}

	/++

	+/
	const SystemErrorCode errorCode;

	/++

	+/
	const SavedArgument[8] args;

	override void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {
		super.getAdditionalPrintableInformation(sink);
		sink("Error code", errorCode.toString());

		foreach(arg; args)
			if(arg.name !is null)
				sink(arg.name, arg.value.toString());
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
				SavedArgument[] args; // FIXME
				/+
				static foreach(idx; 0 .. Params.length)
					args ~= SavedArgument(
						__traits(identifier, Params[idx .. idx + 1]),
						params[idx]
					);
				+/
				throw new ErrnoApiException(__traits(identifier, fn), errno, args, file, line);
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
				Return value = fn(params);

				if(value == errorValueToUse) {
					auto error = GetLastError();
					SavedArgument[] args; // FIXME
					throw new WindowsApiException(__traits(identifier, fn), error, args, file, line);
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
		UI thread - simpledisplay's event loop, which it will require remain live for the duration of the program (running two .eventLoops without a parent EventLoop instance will become illegal, throwing at runtime if it happens telling people to change their code)

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
		while(!exitApplicationRequested && !until()) {
			runOnce();
		}
	}

	private __gshared bool exitApplicationRequested;

	final static void exitApplication() {
		exitApplicationRequested = true;
		// FIXME: wake up all the threads
	}

	/++
		Returns details from a call to [runOnce]. Use the named methods here for details, or it can be used in a `while` loop directly thanks to its `opCast` automatic conversion to `bool`.

		History:
			Added December 28, 2023
	+/
	static struct RunOnceResult {
		enum Possibilities {
			CarryOn,
			LocalExit,
			GlobalExit,
			Interrupted

		}
		Possibilities result;

		/++
			Returns `true` if the event loop should generally continue.

			Might be false if the local loop was exited or if the application is supposed to exit. If this is `false`, check [applicationExitRequested] to determine if you should move on to other work or start your final cleanup process.
		+/
		bool shouldContinue() const {
			return result == Possibilities.CarryOn;
		}

		/++
			Returns `true` if [ICoreEventLoop.exitApplication] was called during this event, or if the user or operating system has requested the application exit.

			Details might be available through other means.
		+/
		bool applicationExitRequested() const {
			return result == Possibilities.GlobalExit;
		}

		/++
			Returns [shouldContinue] when used in a context for an implicit bool (e.g. `if` statements).
		+/
		bool opCast(T : bool)() const {
			reutrn shouldContinue();
		}
	}

	/++
		Runs a single iteration of the event loop for this thread. It will return when the first thing happens, but that thing might be totally uninteresting to anyone, or it might trigger significant work you'll wait on.

		Note that running this externally instead of `run` gives only the $(I illusion) of control. You're actually better off setting a recurring timer if you need things to run on a clock tick, or a single-shot timer for a one time event. They're more likely to be called on schedule inside this function than outside it.

		Parameters:
			timeout = a timeout value for an idle loop. There is no guarantee you won't return earlier or later than this; the function might run longer than the timeout if it has work to do. Pass `Duration.max` (the default) for an infinite duration timeout (but remember, once it finds work to do, including a false-positive wakeup or interruption by the operating system, it will return early anyway).

		History:
			Prior to December 28, 2023, it returned `void` and took no arguments. This change is breaking, but since the entire module is documented as unstable, it was permitted to happen as that document provided prior notice.
	+/
	RunOnceResult runOnce(Duration timeout = Duration.max);

	/++
		Adds a delegate to be called on each loop iteration, called based on the `timingFlags`.


		The order in which the delegates are called is undefined and may change with each iteration of the loop. Additionally, when and how many times a loop iterates is undefined; multiple events might be handled by each iteration, or sometimes, nothing will be handled and it woke up spuriously. Your delegates need to be ok with all of this.

		Parameters:
			dg = the delegate to call
			timingFlags =
				0: never actually run the function; it can assert error if you pass this
				1: run before each loop OS wait call
				2: run after each loop OS wait call
				3: run both before and after each OS wait call
				4: single shot? NOT IMPLEMENTED
				8: no-coalesce? NOT IMPLEMENTED (if after was just run, it will skip the before loops unless this flag is set)

		FIXME: it should return a handle you can use to unregister it
	+/
	void addDelegateOnLoopIteration(void delegate() dg, uint timingFlags);

	final void addDelegateOnLoopIteration(void function() dg, uint timingFlags) {
		if(timingFlags == 0)
			assert(0, "would never run");
		addDelegateOnLoopIteration(toDelegate(dg), timingFlags);
	}

	// to send messages between threads, i'll queue up a function that just call dispatchMessage. can embed the arg inside the callback helper prolly.
	// tho i might prefer to actually do messages w/ run payloads so it is easier to deduplicate i can still dedupe by insepcting the call args so idk

	version(Posix) {
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

				version(Arsd_core_epoll) {
					impl.unregisterFd(fd);
				} else version(Arsd_core_dispatch) {
					throw new NotYetImplementedException();
				} else version(Arsd_core_kqueue) {
					// intentionally blank - all registrations are one-shot there
					// FIXME: actually it might not have gone off yet, in that case we do need to delete the filter
				} else version(EmptyCoreEvent) {

				}
				else static assert(0);

				cb.release();
				this = typeof(this).init;
			}
		}

		@mustuse
		static struct RearmToken {
			private bool readable;
			private CoreEventLoopImplementation impl;
			private int fd;
			private CallbackHelper cb;
			private uint flags;

			/++
				Calls [UnregisterToken.unregister]
			+/
			void unregister() {
				assert(impl !is null, "cannot reuse rearm token after unregistering it");

				version(Arsd_core_epoll) {
					impl.unregisterFd(fd);
				} else version(Arsd_core_dispatch) {
					throw new NotYetImplementedException();
				} else version(Arsd_core_kqueue) {
					// intentionally blank - all registrations are one-shot there
					// FIXME: actually it might not have gone off yet, in that case we do need to delete the filter
				} else version(EmptyCoreEvent) {

				} else static assert(0);

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
		RearmToken addCallbackOnFdWritableOneShot(int fd, CallbackHelper cb);
	}

	version(Windows) {
		@mustuse
		static struct UnregisterToken {
			private CoreEventLoopImplementation impl;
			private HANDLE handle;
			private CallbackHelper cb;

			/++
				Unregisters the handle from the event loop and releases the reference to the callback held by the event loop (which will probably free it).

				You must call this when you're done. Normally, this will be right before you close the handle.
			+/
			void unregister() {
				assert(impl !is null, "Cannot reuse unregister token");

				impl.unregisterHandle(handle, cb);

				cb.release();
				this = typeof(this).init;
			}
		}

		UnregisterToken addCallbackOnHandleReady(HANDLE handle, CallbackHelper cb);
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

/+
private ThreadLocalGcRoots gcRoots;

private struct ThreadLocalGcRoots {
	// it actually would be kinda cool if i could tell the GC
	// that only part of this array is actually used so it can skip
	// scanning the rest. but meh.
	const(void)*[] roots;

	void* add(const(void)* what) {
		roots ~= what;
		return &roots[$-1];
	}
}
+/

// the GC may not be able to see this! remember, it can be hidden inside kernel buffers
package(arsd) class CallbackHelper {
	import core.memory;

	void call() {
		if(callback)
			callback();
	}

	void delegate() callback;
	void*[3] argsStore;

	void addref() {
		version(HasThread)
		atomicOp!"+="(refcount, 1);
	}

	void release() {
		version(HasThread)
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
		version(HasThread)
		if(addRoot) {
			GC.addRoot(cast(void*) this);
			this.flags |= 1;
		}

		this.addref();
		this.callback = callback;
	}
}

inout(char)[] trimSlashesRight(inout(char)[] txt) {
	//if(txt.length && (txt[0] == '/' || txt[0] == '\\'))
		//txt = txt[1 .. $];

	if(txt.length && (txt[$-1] == '/' || txt[$-1] == '\\'))
		txt = txt[0 .. $-1];

	return txt;
}

enum TreatAsWindowsPath {
	guess,
	ifVersionWindows,
	yes,
	no,
}

// FIXME add uri from cgi/http2 and make sure the relative methods are reasonable compatible

/++
	This represents a file. Technically, file paths aren't actually strings (for example, on Linux, they need not be valid utf-8, while a D string is supposed to be), even though we almost always use them like that.

	This type is meant to represent a filename / path. I might not keep it around.
+/
struct FilePath {
	private string path;

	this(string path) {
		this.path = path;
	}

	bool isNull() const {
		return path is null;
	}

	bool opCast(T:bool)() const {
		return !isNull;
	}

	string toString() const {
		return path;
	}

	//alias toString this;

	/+ +++++++++++++++++ +/
	/+  String analysis  +/
	/+ +++++++++++++++++ +/

	FilePath makeAbsolute(FilePath base, TreatAsWindowsPath treatAsWindowsPath = TreatAsWindowsPath.guess) const {
		if(base.path.length == 0)
			return this.removeExtraParts();
		if(base.path[$-1] != '/' && base.path[$-1] != '\\')
			base.path ~= '/';

		bool isWindowsPath;
		final switch(treatAsWindowsPath) {
			case TreatAsWindowsPath.guess:
			case TreatAsWindowsPath.yes:
				isWindowsPath = true;
			break;
			case TreatAsWindowsPath.no:
				isWindowsPath = false;
			break;
			case TreatAsWindowsPath.ifVersionWindows:
				version(Windows)
					isWindowsPath = true;
				else
					isWindowsPath = false;
			break;
		}
		if(isWindowsPath) {
			if(this.isUNC)
				return this.removeExtraParts();
			if(this.driveName)
				return this.removeExtraParts();
			if(this.path.length >= 1 && (this.path[0] == '/' || this.path[0] == '\\')) {
				// drive-relative path, take the drive from the base
				return FilePath(base.driveName ~ this.path).removeExtraParts();
			}
			// otherwise, take the dir name from the base and add us onto it
			return FilePath(base.directoryName ~ this.path).removeExtraParts();
		} else {
			if(this.path.length >= 1 && this.path[0] == '/')
				return this.removeExtraParts();
			else
				return FilePath(base.directoryName ~ this.path).removeExtraParts();
		}
	}

	// dg returns true to continue, false to break
	void foreachPathComponent(scope bool delegate(size_t index, in char[] component) dg) const {
		size_t start;
		size_t skip;
		if(isUNC()) {
			dg(start, this.path[start .. 2]);
			start = 2;
			skip = 2;
		}
		foreach(idx, ch; this.path) {
			if(skip) { skip--; continue; }
			if(ch == '/' || ch == '\\') {
				if(!dg(start, this.path[start .. idx + 1]))
					return;
				start = idx + 1;
			}
		}
		if(start != path.length)
			dg(start, this.path[start .. $]);
	}

	// remove cases of // or /. or /.. Only valid to call this on an absolute path.
	private FilePath removeExtraParts() const {
		bool changeNeeded;
		foreachPathComponent((idx, component) {
			auto name = component.trimSlashesRight;
			if(name.length == 0 && idx != 0)
				changeNeeded = true;
			if(name == "." || name == "..")
				changeNeeded = true;
			return !changeNeeded;
		});

		if(!changeNeeded)
			return this;

		string newPath;
		foreachPathComponent((idx, component) {
			auto name = component.trimSlashesRight;
			if(component == `\\`) // must preserve unc paths
				newPath ~= component;
			else if(name.length == 0 && idx != 0)
				{}
			else if(name == ".")
				{}
			else if(name == "..") {
				// remove the previous component, unless it is the first component
				auto sofar = FilePath(newPath);
				size_t previousComponentIndex;
				sofar.foreachPathComponent((idx2, component2) {
					if(idx2 != newPath.length)
						previousComponentIndex = idx2;
					return true;
				});

				if(previousComponentIndex && previousComponentIndex != newPath.length) {
					newPath = newPath[0 .. previousComponentIndex];
					//newPath.assumeSafeAppend();
				}
			} else {
				newPath ~= component;
			}

			return true;
		});

		return FilePath(newPath);
	}

	// assuming we're looking at a Windows path...
	bool isUNC() const {
		return (path.length > 2 && path[0 .. 2] == `\\`);
	}

	// assuming we're looking at a Windows path...
	string driveName() const {
		if(path.length < 2)
			return null;
		if((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) {
			if(path[1] == ':') {
				if(path.length == 2 || path[2] == '\\' || path[2] == '/')
					return path[0 .. 2];
			}
		}
		return null;
	}

	/+
	bool isAbsolute() {
		if(path.length && path[0] == '/')
			return true;

	}

	FilePath relativeTo() {

	}

	bool matchesGlobPattern(string globPattern) {

	}

	this(string directoryName, string filename) {}
	this(string directoryName, string basename, string extension) {}

	// remove ./, ../, stuff like that
	FilePath normalize(FilePath relativeTo) {}
	+/

	/++
		Returns the path with the directory cut off.
	+/
	string filename() {
		foreach_reverse(idx, ch; path) {
			if(ch == '\\' || ch == '/')
				return path[idx + 1 .. $];
		}
		return path;
	}

	/++
		Returns the path with the filename cut off.
	+/
	string directoryName() {
		auto fn = this.filename();
		if(fn is path)
			return null;
		return path[0 .. $ - fn.length];
	}

	/++
		Returns the file extension, if present, including the last dot.
	+/
	string extension() {
		foreach_reverse(idx, ch; path) {
			if(ch == '.')
				return path[idx .. $];
		}
		return null;
	}

	/++
		Guesses the media (aka mime) content type from the file extension for this path.

		Only has a few things supported. Returns null if it doesn't know.

		History:
			Moved from arsd.cgi to arsd.core.FilePath on October 28, 2024
	+/
	string contentTypeFromFileExtension() {
		switch(this.extension) {
			// images
			case ".png":
				return "image/png";
			case ".apng":
				return "image/apng";
			case ".svg":
				return "image/svg+xml";
			case ".jpg":
			case ".jpeg":
				return "image/jpeg";

			case ".txt":
				return "text/plain";

			case ".html":
				return "text/html";
			case ".css":
				return "text/css";
			case ".js":
				return "application/javascript";
			case ".wasm":
				return "application/wasm";

			case ".mp3":
				return "audio/mpeg";

			case ".pdf":
				return "application/pdf";

			default:
				return null;
		}
	}
}

unittest {
	FilePath fn;

	fn = FilePath("dir/name.ext");
	assert(fn.directoryName == "dir/");
	assert(fn.filename == "name.ext");
	assert(fn.extension == ".ext");

	fn = FilePath(null);
	assert(fn.directoryName is null);
	assert(fn.filename is null);
	assert(fn.extension is null);

	fn = FilePath("file.txt");
	assert(fn.directoryName is null);
	assert(fn.filename == "file.txt");
	assert(fn.extension == ".txt");

	fn = FilePath("dir/");
	assert(fn.directoryName == "dir/");
	assert(fn.filename == "");
	assert(fn.extension is null);

	assert(fn.makeAbsolute(FilePath("/")).path == "/dir/");
	assert(fn.makeAbsolute(FilePath("file.txt")).path == "file.txt/dir/"); // FilePaths as a base are ALWAYS treated as a directory
	assert(FilePath("file.txt").makeAbsolute(fn).path == "dir/file.txt");

	assert(FilePath("c:/file.txt").makeAbsolute(FilePath("d:/")).path == "c:/file.txt");
	assert(FilePath("../file.txt").makeAbsolute(FilePath("d:/")).path == "d:/file.txt");

	assert(FilePath("../file.txt").makeAbsolute(FilePath("d:/foo")).path == "d:/file.txt");
	assert(FilePath("../file.txt").makeAbsolute(FilePath("d:/")).path == "d:/file.txt");
	assert(FilePath("../file.txt").makeAbsolute(FilePath("/home/me")).path == "/home/file.txt");
	assert(FilePath("../file.txt").makeAbsolute(FilePath(`\\arsd\me`)).path == `\\arsd\file.txt`);
	assert(FilePath("../../file.txt").makeAbsolute(FilePath("/home/me")).path == "/file.txt");
	assert(FilePath("../../../file.txt").makeAbsolute(FilePath("/home/me")).path == "/file.txt");

	assert(FilePath("test/").makeAbsolute(FilePath("/home/me/")).path == "/home/me/test/");
	assert(FilePath("/home/me/test/").makeAbsolute(FilePath("/home/me/test/")).path == "/home/me/test/");
}

version(HasFile)
/++
	History:
		Added January 2, 2024
+/
FilePath getCurrentWorkingDirectory() {
	version(Windows) {
		wchar[256] staticBuffer;
		wchar[] buffer = staticBuffer[];

		try_again:
		auto ret = GetCurrentDirectoryW(cast(DWORD) buffer.length, buffer.ptr);
		if(ret == 0)
			throw new WindowsApiException("GetCurrentDirectoryW", GetLastError());
		if(ret < buffer.length) {
			return FilePath(makeUtf8StringFromWindowsString(buffer[0 .. ret]));
		} else {
			buffer.length = ret;
			goto try_again;
		}
	} else version(Posix) {
		char[128] staticBuffer;
		char[] buffer = staticBuffer[];

		try_again:
		auto ret = getcwd(buffer.ptr, buffer.length);
		if(ret is null && errno == ERANGE && buffer.length < 4096 / 2) {
			buffer.length = buffer.length * 2;
			goto try_again;
		} else if(ret is null) {
			throw new ErrnoApiException("getcwd", errno);
		}
		return FilePath(stringz(ret).borrow.idup);
	} else
		assert(0, "Not implemented");
}

/+
struct FilePathGeneric {

}

struct FilePathWin32 {

}

struct FilePathPosix {

}

struct FilePathWindowsUnc {

}

version(Windows)
	alias FilePath = FilePathWin32;
else
	alias FilePath = FilePathPosix;
+/


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
interface AsyncOperationResponse {
	/++
		Returns true if the request completed successfully, finishing what it was supposed to.

		Should be set to `false` if the request was cancelled before completing or encountered an error.
	+/
	bool wasSuccessful();
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
	An `AbstractFile` represents a file handle on the operating system level. You cannot do much with it.
+/
version(HasFile) class AbstractFile {
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

	/+
	enum SpecialFlags {
		randomAccessExpected, /// FILE_FLAG_SEQUENTIAL_SCAN is turned off and posix_fadvise(POSIX_FADV_SEQUENTIAL)
		skipCache, /// O_DSYNC, FILE_FLAG_NO_BUFFERING and maybe WRITE_THROUGH. note that metadata still goes through the cache, FlushFileBuffers and fsync can still do those
		temporary, /// FILE_ATTRIBUTE_TEMPORARY on Windows, idk how to specify on linux. also FILE_FLAG_DELETE_ON_CLOSE can be combined to make a (almost) all memory file. kinda like a private anonymous mmap i believe.
		deleteWhenClosed, /// Windows has a flag for this but idk if it is of any real use
		async, /// open it in overlapped mode, all reads and writes must then provide an offset. Only implemented on Windows
	}
	+/

	/++

	+/
	protected this(bool async, FilePath filename, OpenMode mode = OpenMode.readOnly, RequirePreexisting require = RequirePreexisting.no, uint specialFlags = 0) {
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
				FILE_ATTRIBUTE_NORMAL | (async ? FILE_FLAG_OVERLAPPED : 0),
				null
			);

			if(handle == INVALID_HANDLE_VALUE) {
				// FIXME: throw the filename and other params here too
				SavedArgument[3] args;
				args[0] = SavedArgument("filename", LimitedVariant(filename.path));
				args[1] = SavedArgument("access", LimitedVariant(access, 2));
				args[2] = SavedArgument("requirePreexisting", LimitedVariant(require == RequirePreexisting.yes));
				throw new WindowsApiException("CreateFileW", GetLastError(), args[]);
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

			if(async)
				flags |= O_NONBLOCK;

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

			auto perms = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
			int fd = open(namez.ptr, flags, perms);
			if(fd == -1) {
				SavedArgument[3] args;
				args[0] = SavedArgument("filename", LimitedVariant(filename.path));
				args[1] = SavedArgument("flags", LimitedVariant(flags, 2));
				args[2] = SavedArgument("perms", LimitedVariant(perms, 8));
				throw new ErrnoApiException("open", errno, args[]);
			}

			this.handle = fd;
		}
	}

	/++

	+/
	private this(NativeFileHandle handleToWrap) {
		this.handle = handleToWrap;
	}

	// only available on some types of file
	long size() { return 0; }

	// note that there is no fsync thing, instead use the special flag.

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

/++

+/
version(HasFile) class File : AbstractFile {

	/++
		Opens a file in synchronous access mode.

		The permission mask is on used on posix systems FIXME: implement it
	+/
	this(FilePath filename, OpenMode mode = OpenMode.readOnly, RequirePreexisting require = RequirePreexisting.no, uint specialFlags = 0, uint permMask = 0) {
		super(false, filename, mode, require, specialFlags);
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
	// also not permitted in async mode
	void seek(long where, Seek fromWhence) {}
	long tell() { return 0; }
}

/++
	 Only one operation can be pending at any time in the current implementation.
+/
version(HasFile) class AsyncFile : AbstractFile {
	/++
		Opens a file in asynchronous access mode.
	+/
	this(FilePath filename, OpenMode mode = OpenMode.readOnly, RequirePreexisting require = RequirePreexisting.no, uint specialFlags = 0, uint permissionMask = 0) {
		// FIXME: implement permissionMask
		super(true, filename, mode, require, specialFlags);
	}

	package(arsd) this(NativeFileHandle adoptPreSetup) {
		super(adoptPreSetup);
	}

	///
	AsyncReadRequest read(ubyte[] buffer, long offset = 0) {
		return new AsyncReadRequest(this, buffer, offset);
	}

	///
	AsyncWriteRequest write(const(void)[] buffer, long offset = 0) {
		return new AsyncWriteRequest(this, cast(ubyte[]) buffer, offset);
	}

}
else class AsyncFile {
	package(arsd) this(NativeFileHandle adoptPreSetup) {}
}

/++
	Reads or writes a file in one call. It might internally yield, but is generally blocking if it returns values. The callback ones depend on the implementation.

	Tip: prefer the callback ones. If settings where async is possible, it will do async, and if not, it will sync.

	NOT FULLY IMPLEMENTED
+/
void writeFile(string filename, const(void)[] contents) {
	// FIXME: stop using the C lib and start error checking
	import core.stdc.stdio;
	CharzBuffer fn = filename;
	auto file = fopen(fn.ptr, "wb");
	if(file is null)
		throw new ErrnoApiException("fopen", errno, [SavedArgument("filename", LimitedVariant(filename))]);
	fwrite(contents.ptr, 1, contents.length, file);
	fclose(file);
}

/// ditto
const(ubyte[]) readBinaryFile(string filename) {
	// FIXME: stop using the C lib and check for more errors

	import core.stdc.stdio;
	CharzBuffer fn = filename;
	auto file = fopen(fn.ptr, "rb");
	if(file is null)
		throw new ErrnoApiException("fopen", errno, [SavedArgument("filename", LimitedVariant(filename))]);
	ubyte[] buffer = new ubyte[](64 * 1024);
	ubyte[] contents;

	while(true) {
		auto ret = fread(buffer.ptr, 1, buffer.length, file);
		if(ret < buffer.length) {
			if(contents is null)
				contents = buffer[0 .. ret];
			else
				contents ~= buffer[0 .. ret];
			break;
		} else {
			contents ~= buffer[0 .. ret];
		}
	}
	fclose(file);

	return contents;
}

/// ditto
string readTextFile(string filename, string fileEncoding = null) {
	return cast(string) readBinaryFile(filename);
}

/+
private Class recycleObject(Class, Args...)(Class objectToRecycle, Args args) {
	if(objectToRecycle is null)
		return new Class(args);
	// destroy nulls out the vtable which is the first thing in the object
	// so if it hasn't already been destroyed, we'll do it here
	if((*cast(void**) objectToRecycle) !is null) {
		assert(typeid(objectToRecycle) is typeid(Class)); // to make sure we're actually recycling the right kind of object
		.destroy(objectToRecycle);
	}

	// then go ahead and reinitialize it
	ubyte[] rawData = (cast(ubyte*) cast(void*) objectToRecycle)[0 .. __traits(classInstanceSize, Class)];
	rawData[] = (cast(ubyte[]) typeid(Class).initializer)[];

	objectToRecycle.__ctor(args);

	return objectToRecycle;
}
+/

/+
/++
	Preallocates a class object without initializing it.

	This is suitable *only* for passing to one of the functions in here that takes a preallocated object for recycling.
+/
Class preallocate(Class)() {
	import core.memory;
	// FIXME: can i pass NO_SCAN here?
	return cast(Class) GC.calloc(__traits(classInstanceSize, Class), 0, typeid(Class));
}

OwnedClass!Class preallocateOnStack(Class)() {

}
+/

// thanks for a random person on stack overflow for this function
version(Windows)
BOOL MyCreatePipeEx(
	PHANDLE lpReadPipe,
	PHANDLE lpWritePipe,
	LPSECURITY_ATTRIBUTES lpPipeAttributes,
	DWORD nSize,
	DWORD dwReadMode,
	DWORD dwWriteMode
)
{
	HANDLE ReadPipeHandle, WritePipeHandle;
	DWORD dwError;
	CHAR[MAX_PATH] PipeNameBuffer;

	if (nSize == 0) {
		nSize = 4096;
	}

	// FIXME: should be atomic op and gshared
	static shared(int) PipeSerialNumber = 0;

	import core.stdc.string;
	import core.stdc.stdio;

	sprintf(PipeNameBuffer.ptr,
		"\\\\.\\Pipe\\ArsdCoreAnonymousPipe.%08x.%08x".ptr,
		GetCurrentProcessId(),
		atomicOp!"+="(PipeSerialNumber, 1)
	);

	ReadPipeHandle = CreateNamedPipeA(
		PipeNameBuffer.ptr,
		1/*PIPE_ACCESS_INBOUND*/ | dwReadMode,
		0/*PIPE_TYPE_BYTE*/ | 0/*PIPE_WAIT*/,
		1,             // Number of pipes
		nSize,         // Out buffer size
		nSize,         // In buffer size
		120 * 1000,    // Timeout in ms
		lpPipeAttributes
	);

	if (! ReadPipeHandle) {
		return FALSE;
	}

	WritePipeHandle = CreateFileA(
		PipeNameBuffer.ptr,
		GENERIC_WRITE,
		0,                         // No sharing
		lpPipeAttributes,
		OPEN_EXISTING,
		FILE_ATTRIBUTE_NORMAL | dwWriteMode,
		null                       // Template file
	);

	if (INVALID_HANDLE_VALUE == WritePipeHandle) {
		dwError = GetLastError();
		CloseHandle( ReadPipeHandle );
		SetLastError(dwError);
		return FALSE;
	}

	*lpReadPipe = ReadPipeHandle;
	*lpWritePipe = WritePipeHandle;
	return( TRUE );
}



/+

	// this is probably useless.

/++
	Creates a pair of anonymous pipes ready for async operations.

	You can pass some preallocated objects to recycle if you like.
+/
AsyncAnonymousPipe[2] anonymousPipePair(AsyncAnonymousPipe[2] preallocatedObjects = [null, null], bool inheritable = false) {
	version(Posix) {
		int[2] fds;
		auto ret = pipe(fds);

		if(ret == -1)
			throw new SystemApiException("pipe", errno);

		// FIXME: do we want them inheritable? and do we want both sides to be async?
		if(!inheritable) {
			setCloExec(fds[0]);
			setCloExec(fds[1]);
		}
		// if it is inherited, do we actually want it non-blocking?
		makeNonBlocking(fds[0]);
		makeNonBlocking(fds[1]);

		return [
			recycleObject(preallocatedObjects[0], fds[0]),
			recycleObject(preallocatedObjects[1], fds[1]),
		];
	} else version(Windows) {
		HANDLE rp, wp;
		// FIXME: do we want them inheritable? and do we want both sides to be async?
		if(!MyCreatePipeEx(&rp, &wp, null, 0, FILE_FLAG_OVERLAPPED, FILE_FLAG_OVERLAPPED))
			throw new SystemApiException("MyCreatePipeEx", GetLastError());
		return [
			recycleObject(preallocatedObjects[0], rp),
			recycleObject(preallocatedObjects[1], wp),
		];
	} else throw ArsdException!"NotYetImplemented"();
}
	// on posix, just do pipe() w/ non block
	// on windows, do an overlapped named pipe server, connect, stop listening, return pair.
+/

/+
class NamedPipe : AsyncFile {

}
+/

/++
	A named pipe ready to accept connections.

	A Windows named pipe is an IPC mechanism usable on local machines or across a Windows network.
+/
version(Windows)
class NamedPipeServer {
	// unix domain socket or windows named pipe

	// Promise!AsyncAnonymousPipe connect;
	// Promise!AsyncAnonymousPipe accept;

	// when a new connection arrives, it calls your callback
	// can be on a specific thread or on any thread
}

private version(Windows) extern(Windows) {
	const(char)* inet_ntop(int, const void*, char*, socklen_t);
}

/++
	Some functions that return arrays allow you to provide your own buffer. These are indicated in the type system as `UserProvidedBuffer!Type`, and you get to decide what you want to happen if the buffer is too small via the [OnOutOfSpace] parameter.

	These are usually optional, since an empty user provided buffer with the default policy of reallocate will also work fine for whatever needs to be returned, thanks to the garbage collector taking care of it for you.

	The API inside `UserProvidedBuffer` is all private to the arsd library implementation; your job is just to provide the buffer to it with [provideBuffer] or a constructor call and decide on your on-out-of-space policy.

	$(TIP
		To properly size a buffer, I suggest looking at what covers about 80% of cases. Trying to cover everything often leads to wasted buffer space, and if you use a reallocate policy it can cover the rest. You might be surprised how far just two elements can go!
	)

	History:
		Added August 4, 2023 (dub v11.0)
+/
struct UserProvidedBuffer(T) {
	private T[] buffer;
	private int actualLength;
	private OnOutOfSpace policy;

	/++

	+/
	public this(scope T[] buffer, OnOutOfSpace policy = OnOutOfSpace.reallocate) {
		this.buffer = buffer;
		this.policy = policy;
	}

	package(arsd) bool append(T item) {
		if(actualLength < buffer.length) {
			buffer[actualLength++] = item;
			return true;
		} else final switch(policy) {
			case OnOutOfSpace.discard:
				return false;
			case OnOutOfSpace.exception:
				throw ArsdException!"Buffer out of space"(buffer.length, actualLength);
			case OnOutOfSpace.reallocate:
				buffer ~= item;
				actualLength++;
				return true;
		}
	}

	package(arsd) T[] slice() {
		return buffer[0 .. actualLength];
	}
}

/// ditto
UserProvidedBuffer!T provideBuffer(T)(scope T[] buffer, OnOutOfSpace policy = OnOutOfSpace.reallocate) {
	return UserProvidedBuffer!T(buffer, policy);
}

/++
	Possible policies for [UserProvidedBuffer]s that run out of space.
+/
enum OnOutOfSpace {
	reallocate, /// reallocate the buffer with the GC to make room
	discard, /// discard all contents that do not fit in your provided buffer
	exception, /// throw an exception if there is data that would not fit in your provided buffer
}



/+
	The GC can be called from any thread, and a lot of cleanup must be done
	on the gui thread. Since the GC can interrupt any locks - including being
	triggered inside a critical section - it is vital to avoid deadlocks to get
	these functions called from the right place.

	If the buffer overflows, things are going to get leaked. I'm kinda ok with that
	right now.

	The cleanup function is run when the event loop gets around to it, which is just
	whenever there's something there after it has been woken up for other work. It does
	NOT wake up the loop itself - can't risk doing that from inside the GC in another thread.
	(Well actually it might be ok but i don't wanna mess with it right now.)
+/
package(arsd) struct CleanupQueue {
	import core.stdc.stdlib;

	void queue(alias func, T...)(T args) {
		static struct Args {
			T args;
		}
		static struct RealJob {
			Job j;
			Args a;
		}
		static void call(Job* data) {
			auto rj = cast(RealJob*) data;
			func(rj.a.args);
		}

		RealJob* thing = cast(RealJob*) malloc(RealJob.sizeof);
		thing.j.call = &call;
		thing.a.args = args;

		buffer[tail++] = cast(Job*) thing;

		// FIXME: set overflowed
	}

	void process() {
		const tail = this.tail;

		while(tail != head) {
			Job* job = cast(Job*) buffer[head++];
			job.call(job);
			free(job);
		}

		if(overflowed)
			throw new object.Exception("cleanup overflowed");
	}

	private:

	ubyte tail; // must ONLY be written by queue
	ubyte head; // must ONLY be written by process
	bool overflowed;

	static struct Job {
		void function(Job*) call;
	}

	void*[256] buffer;
}
package(arsd) __gshared CleanupQueue cleanupQueue;




/++
	A timer that will trigger your function on a given interval.


	You create a timer with an interval and a callback. It will continue
	to fire on the interval until it is destroyed.

	---
	auto timer = new Timer(50, { it happened!; });
	timer.destroy();
	---

	Timers can only be expected to fire when the event loop is running and only
	once per iteration through the event loop.

	History:
		Prior to December 9, 2020, a timer pulse set too high with a handler too
		slow could lock up the event loop. It now guarantees other things will
		get a chance to run between timer calls, even if that means not keeping up
		with the requested interval.

		Originally part of arsd.simpledisplay, this code was integrated into
		arsd.core on May 26, 2024 (committed on June 10).
+/
version(HasTimer)
class Timer {
	// FIXME: absolute time vs relative time
	// FIXME: real time?

	// FIXME: I might add overloads for ones that take a count of
	// how many elapsed since last time (on Windows, it will divide
	// the ticks thing given, on Linux it is just available) and
	// maybe one that takes an instance of the Timer itself too


	/++
		Creates an initialized, but unarmed timer. You must call other methods later.
	+/
	this(bool actuallyInitialize = true) {
		if(actuallyInitialize)
			initialize();
	}

	private void initialize() {
		version(Windows) {
			handle = CreateWaitableTimer(null, false, null);
			if(handle is null)
				throw new WindowsApiException("CreateWaitableTimer", GetLastError());
			cbh = new CallbackHelper(&trigger);
		} else version(Emscripten) {
			assert(0);
		} else version(linux) {
			import core.sys.linux.timerfd;

			fd = timerfd_create(CLOCK_MONOTONIC, 0);
			if(fd == -1)
				throw new Exception("timer create failed");

			auto el = getThisThreadEventLoop(EventLoopType.Ui);
			unregisterToken = el.addCallbackOnFdReadable(fd, new CallbackHelper(&trigger));
		} else throw new NotYetImplementedException();
		// FIXME: freebsd 12 has timer_fd and netbsd 10 too
	}

	/++
	+/
	void setPulseCallback(void delegate() onPulse) {
		assert(onPulse !is null);
		this.onPulse = onPulse;
	}

	/++
	+/
	void changeTime(int intervalInMilliseconds, bool repeats) {
		this.intervalInMilliseconds = intervalInMilliseconds;
		this.repeats = repeats;
		changeTimeInternal(intervalInMilliseconds, repeats);
	}

	private void changeTimeInternal(int intervalInMilliseconds, bool repeats) {
		version(Windows)
		{
			LARGE_INTEGER initialTime;
			initialTime.QuadPart = -intervalInMilliseconds * 10000000L / 1000; // Windows wants hnsecs, we have msecs
			if(!SetWaitableTimer(handle, &initialTime, repeats ? intervalInMilliseconds : 0, &timerCallback, cast(void*) cbh, false))
				throw new WindowsApiException("SetWaitableTimer", GetLastError());
		} else version(Emscripten) {
			assert(0);
		} else version(linux) {
			import core.sys.linux.timerfd;

			itimerspec value = makeItimerspec(intervalInMilliseconds, repeats);
			if(timerfd_settime(fd, 0, &value, null) == -1) {
				throw new ErrnoApiException("couldn't change pulse timer", errno);
			}
		} else {
			throw new NotYetImplementedException();
		}
		// FIXME: freebsd 12 has timer_fd and netbsd 10 too
	}

	/++
	+/
	void pause() {
		// FIXME this kinda makes little sense tbh
		// when it restarts, it won't be on the same rhythm as it was at first...
		changeTimeInternal(0, false);
	}

	/++
	+/
	void unpause() {
		changeTimeInternal(this.intervalInMilliseconds, this.repeats);
	}

	/++
	+/
	void cancel() {
		version(Windows)
			CancelWaitableTimer(handle);
		else
			changeTime(0, false);
	}


	/++
		Create a timer with a callback when it triggers.
	+/
	this(int intervalInMilliseconds, void delegate() onPulse, bool repeats = true) @trusted {
		assert(onPulse !is null);

		initialize();
		setPulseCallback(onPulse);
		changeTime(intervalInMilliseconds, repeats);
	}

	/++
		Sets a one-of timer that happens some time after the given timestamp, then destroys itself
	+/
	this(SimplifiedUtcTimestamp when, void delegate() onTimeArrived) {
		import core.stdc.time;
		auto ts = when.toUnixTime;
		auto now = time(null);
		if(ts <= now) {
			this(false);
			onTimeArrived();
		} else {
			// FIXME: should use the OS facilities to set the actual time on the real time clock
			auto dis = this;
			this(cast(int)(ts - now) * 1000, () {
				onTimeArrived();
				dis.cancel();
				dis.dispose();
			}, false);
		}
	}

	version(Windows) {} else {
		ICoreEventLoop.UnregisterToken unregisterToken;
	}

	// just cuz I sometimes call it this.
	alias dispose = destroy;

	/++
		Stop and destroy the timer object.

		You should not use it again after destroying it.
	+/
	void destroy() {
		version(Windows) {
			cbh.release();
		} else {
			unregisterToken.unregister();
		}

		version(Windows) {
			staticDestroy(handle);
			handle = null;
		} else version(linux) {
			staticDestroy(fd);
			fd = -1;
		} else throw new NotYetImplementedException();
	}

	~this() {
		version(Windows) {} else
			cleanupQueue.queue!unregister(unregisterToken);
		version(Windows) { if(handle)
			cleanupQueue.queue!staticDestroy(handle);
		} else version(linux) { if(fd != -1)
			cleanupQueue.queue!staticDestroy(fd);
		}
	}


	private:

	version(Windows)
	static void staticDestroy(HANDLE handle) {
		if(handle) {
			// KillTimer(null, handle);
			CancelWaitableTimer(cast(void*)handle);
			CloseHandle(handle);
		}
	}
	else version(linux)
	static void staticDestroy(int fd) @system {
		if(fd != -1) {
			import unix = core.sys.posix.unistd;

			unix.close(fd);
		}
	}

	version(Windows) {} else
	static void unregister(arsd.core.ICoreEventLoop.UnregisterToken urt) {
		if(urt.impl !is null)
			urt.unregister();
	}


	void delegate() onPulse;
	int intervalInMilliseconds;
	bool repeats;

	int lastEventLoopRoundTriggered;

	version(linux) {
		static auto makeItimerspec(int intervalInMilliseconds, bool repeats) {
			import core.sys.linux.timerfd;

			itimerspec value;
			value.it_value.tv_sec = cast(int) (intervalInMilliseconds / 1000);
			value.it_value.tv_nsec = (intervalInMilliseconds % 1000) * 1000_000;

			if(repeats) {
				value.it_interval.tv_sec = cast(int) (intervalInMilliseconds / 1000);
				value.it_interval.tv_nsec = (intervalInMilliseconds % 1000) * 1000_000;
			}

			return value;
		}
	}

	void trigger() {
		version(linux) {
			import unix = core.sys.posix.unistd;
			long val;
			unix.read(fd, &val, val.sizeof); // gotta clear the pipe
		} else version(Windows) {
			if(this.lastEventLoopRoundTriggered == eventLoopRound)
				return; // never try to actually run faster than the event loop
			lastEventLoopRoundTriggered = eventLoopRound;
		} else throw new NotYetImplementedException();

		if(onPulse)
			onPulse();
	}

	version(Windows)
		extern(Windows)
		//static void timerCallback(HWND, UINT, UINT_PTR timer, DWORD dwTime) nothrow {
		static void timerCallback(void* timer, DWORD lowTime, DWORD hiTime) nothrow {
			auto cbh = cast(CallbackHelper) timer;
			try
				cbh.call();
			catch(Throwable e) { sdpy_abort(e); assert(0); }
		}

	version(Windows) {
		HANDLE handle;
		CallbackHelper cbh;
	} else version(linux) {
		int fd = -1;
	} else static if(UseCocoa) {
	} else static assert(0, "timer not supported");
}

version(Windows)
	private void sdpy_abort(Throwable e) nothrow {
		try
			MessageBoxA(null, (e.toString() ~ "\0").ptr, "Exception caught in WndProc", 0);
		catch(Exception e)
			MessageBoxA(null, "Exception.toString threw too!", "Exception caught in WndProc", 0);
		ExitProcess(1);
	}


private int eventLoopRound = -1; // so things that assume 0 still work eg lastEventLoopRoundTriggered



/++
	For functions that give you an unknown address, you can use this to hold it.

	Can get:
		ip4
		ip6
		unix
		abstract_

		name lookup for connect (stream or dgram)
			request canonical name?

		interface lookup for bind (stream or dgram)
+/
version(HasSocket) struct SocketAddress {
	import core.sys.posix.netdb;

	/++
		Provides the set of addresses to listen on all supported protocols on the machine for the given interfaces. `localhost` only listens on the loopback interface, whereas `allInterfaces` will listen on loopback as well as the others on the system (meaning it may be publicly exposed to the internet).

		If you provide a buffer, I recommend using one of length two, so `SocketAddress[2]`, since this usually provides one address for ipv4 and one for ipv6.
	+/
	static SocketAddress[] localhost(ushort port, return UserProvidedBuffer!SocketAddress buffer = null) {
		buffer.append(ip6("::1", port));
		buffer.append(ip4("127.0.0.1", port));
		return buffer.slice;
	}

	/// ditto
	static SocketAddress[] allInterfaces(ushort port, return UserProvidedBuffer!SocketAddress buffer = null) {
		char[16] str;
		return allInterfaces(intToString(port, str[]), buffer);
	}

	/// ditto
	static SocketAddress[] allInterfaces(scope const char[] serviceOrPort, return UserProvidedBuffer!SocketAddress buffer = null) {
		addrinfo hints;
		hints.ai_flags = AI_PASSIVE;
		hints.ai_socktype = SOCK_STREAM; // just to filter it down a little tbh
		return get(null, serviceOrPort, &hints, buffer);
	}

	/++
		Returns a single address object for the given protocol and parameters.

		You probably should generally prefer [get], [localhost], or [allInterfaces] to have more flexible code.
	+/
	static SocketAddress ip4(scope const char[] address, ushort port, bool forListening = false) {
		return getSingleAddress(AF_INET, AI_NUMERICHOST | (forListening ? AI_PASSIVE : 0), address, port);
	}

	/// ditto
	static SocketAddress ip4(ushort port) {
		return ip4(null, port, true);
	}

	/// ditto
	static SocketAddress ip6(scope const char[] address, ushort port, bool forListening = false) {
		return getSingleAddress(AF_INET6, AI_NUMERICHOST | (forListening ? AI_PASSIVE : 0), address, port);
	}

	/// ditto
	static SocketAddress ip6(ushort port) {
		return ip6(null, port, true);
	}

	/// ditto
	static SocketAddress unix(scope const char[] path) {
		// FIXME
		SocketAddress addr;
		return addr;
	}

	/// ditto
	static SocketAddress abstract_(scope const char[] path) {
		char[190] buffer = void;
		buffer[0] = 0;
		buffer[1 .. path.length] = path[];
		return unix(buffer[0 .. 1 + path.length]);
	}

	private static SocketAddress getSingleAddress(int family, int flags, scope const char[] address, ushort port) {
		addrinfo hints;
		hints.ai_family = family;
		hints.ai_flags = flags;

		char[16] portBuffer;
		char[] portString = intToString(port, portBuffer[]);

		SocketAddress[1] addr;
		auto res = get(address, portString, &hints, provideBuffer(addr[]));
		if(res.length == 0)
			throw ArsdException!"bad address"(address.idup, port);
		return res[0];
	}

	/++
		Calls `getaddrinfo` and returns the array of results. It will populate the data into the buffer you provide, if you provide one, otherwise it will allocate its own.
	+/
	static SocketAddress[] get(scope const char[] nodeName, scope const char[] serviceOrPort, addrinfo* hints = null, return UserProvidedBuffer!SocketAddress buffer = null, scope bool delegate(scope addrinfo* ai) filter = null) @trusted {
		addrinfo* res;
		CharzBuffer node = nodeName;
		CharzBuffer service = serviceOrPort;
		auto ret = getaddrinfo(nodeName is null ? null : node.ptr, serviceOrPort is null ? null : service.ptr, hints, &res);
		if(ret == 0) {
			auto current = res;
			while(current) {
				if(filter is null || filter(current)) {
					SocketAddress addr;
					addr.addrlen = cast(socklen_t) current.ai_addrlen;
					switch(current.ai_family) {
						case AF_INET:
							addr.in4 = * cast(sockaddr_in*) current.ai_addr;
							break;
						case AF_INET6:
							addr.in6 = * cast(sockaddr_in6*) current.ai_addr;
							break;
						case AF_UNIX:
							addr.unix_address = * cast(sockaddr_un*) current.ai_addr;
							break;
						default:
							// skip
					}

					if(!buffer.append(addr))
						break;
				}

				current = current.ai_next;
			}

			freeaddrinfo(res);
		} else {
			version(Windows) {
				throw new WindowsApiException("getaddrinfo", ret);
			} else {
				const char* error = gai_strerror(ret);
			}
		}

		return buffer.slice;
	}

	/++
		Returns a string representation of the address that identifies it in a custom format.

		$(LIST
			* Unix domain socket addresses are their path prefixed with "unix:", unless they are in the abstract namespace, in which case it is prefixed with "abstract:" and the zero is trimmed out. For example, "unix:/tmp/pipe".

			* IPv4 addresses are written in dotted decimal followed by a colon and the port number. For example, "127.0.0.1:8080".

			* IPv6 addresses are written in colon separated hex format, but enclosed in brackets, then followed by the colon and port number. For example, "[::1]:8080".
		)
	+/
	string toString() const @trusted {
		char[200] buffer;
		switch(address.sa_family) {
			case AF_INET:
				auto writable = stringz(inet_ntop(address.sa_family, &in4.sin_addr, buffer.ptr, buffer.length));
				auto it = writable.borrow;
				buffer[it.length] = ':';
				auto numbers = intToString(port, buffer[it.length + 1 .. $]);
				return buffer[0 .. it.length + 1 + numbers.length].idup;
			case AF_INET6:
				buffer[0] = '[';
				auto writable = stringz(inet_ntop(address.sa_family, &in6.sin6_addr, buffer.ptr + 1, buffer.length - 1));
				auto it = writable.borrow;
				buffer[it.length + 1] = ']';
				buffer[it.length + 2] = ':';
				auto numbers = intToString(port, buffer[it.length + 3 .. $]);
				return buffer[0 .. it.length + 3 + numbers.length].idup;
			case AF_UNIX:
				// FIXME: it might be abstract in which case stringz is wrong!!!!!
				auto writable = stringz(cast(char*) unix_address.sun_path.ptr).borrow;
				if(writable.length == 0)
					return "unix:";
				string prefix = writable[0] == 0 ? "abstract:" : "unix:";
				buffer[0 .. prefix.length] = prefix[];
				buffer[prefix.length .. prefix.length + writable.length] = writable[writable[0] == 0 ? 1 : 0 .. $];
				return buffer.idup;
			case AF_UNSPEC:
				return "<unspecified address>";
			default:
				return "<unsupported address>"; // FIXME
		}
	}

	ushort port() const @trusted {
		switch(address.sa_family) {
			case AF_INET:
				return ntohs(in4.sin_port);
			case AF_INET6:
				return ntohs(in6.sin6_port);
			default:
				return 0;
		}
	}

	/+
	@safe unittest {
		SocketAddress[4] buffer;
		foreach(addr; SocketAddress.get("arsdnet.net", "http", null, provideBuffer(buffer[])))
			writeln(addr.toString());
	}
	+/

	/+
	unittest {
		// writeln(SocketAddress.ip4(null, 4444, true));
		// writeln(SocketAddress.ip4("400.3.2.1", 4444));
		// writeln(SocketAddress.ip4("bar", 4444));
		foreach(addr; localhost(4444))
			writeln(addr.toString());
	}
	+/

	socklen_t addrlen = typeof(this).sizeof - socklen_t.sizeof; // the size of the union below

	union {
		sockaddr address;

		sockaddr_storage storage;

		sockaddr_in in4;
		sockaddr_in6 in6;

		sockaddr_un unix_address;
	}

	/+
	this(string node, string serviceOrPort, int family = 0) {
		// need to populate the approrpiate address and the length and make sure you set sa_family
	}
	+/

	int domain() {
		return address.sa_family;
	}
	sockaddr* rawAddr() return {
		return &address;
	}
	socklen_t rawAddrLength() {
		return addrlen;
	}

	// FIXME it is AF_BLUETOOTH
	// see: https://people.csail.mit.edu/albert/bluez-intro/x79.html
	// see: https://learn.microsoft.com/en-us/windows/win32/Bluetooth/bluetooth-programming-with-windows-sockets
}

private version(Windows) {
	struct sockaddr_un {
		ushort sun_family;
		char[108] sun_path;
	}
}

version(HasFile) class AsyncSocket : AsyncFile {
	// otherwise: accept, bind, connect, shutdown, close.

	static auto lastError() {
		version(Windows)
			return WSAGetLastError();
		else
			return errno;
	}

	static bool wouldHaveBlocked() {
		auto error = lastError;
		version(Windows) {
			return error == WSAEWOULDBLOCK || error == WSAETIMEDOUT;
		} else {
			return error == EAGAIN || error == EWOULDBLOCK;
		}
	}

	version(Windows)
		enum INVALID = INVALID_SOCKET;
	else
		enum INVALID = -1;

	// type is mostly SOCK_STREAM or SOCK_DGRAM
	/++
		Creates a socket compatible with the given address. It does not actually connect or bind, nor store the address. You will want to pass it again to those functions:

		---
		auto socket = new Socket(address, Socket.Type.Stream);
		socket.connect(address).waitForCompletion();
		---
	+/
	this(SocketAddress address, int type, int protocol = 0) {
		// need to look up these values for linux
		// type |= SOCK_NONBLOCK | SOCK_CLOEXEC;

		handle_ = socket(address.domain(), type, protocol);
		if(handle == INVALID)
			throw new SystemApiException("socket", lastError());

		super(cast(NativeFileHandle) handle); // I think that cast is ok on Windows... i think

		version(Posix) {
			makeNonBlocking(handle);
			setCloExec(handle);
		}

		if(address.domain == AF_INET6) {
			int opt = 1;
			setsockopt(handle, IPPROTO_IPV6 /*SOL_IPV6*/, IPV6_V6ONLY, &opt, opt.sizeof);
		}

		// FIXME: chekc for broadcast

		// FIXME: REUSEADDR ?

		// FIXME: also set NO_DELAY prolly
		// int opt = 1;
		// setsockopt(handle, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
	}

	/++
		Enabling NODELAY can give latency improvements if you are managing buffers on your end
	+/
	void setNoDelay(bool enabled) {

	}

	/++

		`allowQuickRestart` will set the SO_REUSEADDR on unix and SO_DONTLINGER on Windows,
		allowing the application to be quickly restarted despite there still potentially being
		pending data in the tcp stack.

		See https://stackoverflow.com/questions/3229860/what-is-the-meaning-of-so-reuseaddr-setsockopt-option-linux for more information.

		If you already set your appropriate socket options or value correctness and reliability of the network stream over restart speed, leave this at the default `false`.
	+/
	void bind(SocketAddress address, bool allowQuickRestart = false) {
		if(allowQuickRestart) {
			// FIXME
		}

		auto ret = .bind(handle, address.rawAddr, address.rawAddrLength);
		if(ret == -1)
			throw new SystemApiException("bind", lastError);
	}

	/++
		You must call [bind] before this.

		The backlog should be set to a value where your application can reliably catch up on the backlog in a reasonable amount of time under average load. It is meant to smooth over short duration bursts and making it too big will leave clients hanging - which might cause them to try to reconnect, thinking things got lost in transit, adding to your impossible backlog.

		I personally tend to set this to be two per worker thread unless I have actual real world measurements saying to do something else. It is a bit arbitrary and not based on legitimate reasoning, it just seems to work for me (perhaps just because it has never really been put to the test).
	+/
	void listen(int backlog) {
		auto ret = .listen(handle, backlog);
		if(ret == -1)
			throw new SystemApiException("listen", lastError);
	}

	/++
	+/
	void shutdown(int how) {
		auto ret = .shutdown(handle, how);
		if(ret == -1)
			throw new SystemApiException("shutdown", lastError);
	}

	/++
	+/
	override void close() {
		version(Windows)
			closesocket(handle);
		else
			.close(handle);
		handle_ = -1;
	}

	/++
		You can also construct your own request externally to control the memory more.
	+/
	AsyncConnectRequest connect(SocketAddress address, ubyte[] bufferToSend = null) {
		return new AsyncConnectRequest(this, address, bufferToSend);
	}

	/++
		You can also construct your own request externally to control the memory more.
	+/
	AsyncAcceptRequest accept() {
		return new AsyncAcceptRequest(this);
	}

	// note that send is just sendto w/ a null address
	// and receive is just receivefrom w/ a null address
	/++
		You can also construct your own request externally to control the memory more.
	+/
	AsyncSendRequest send(const(ubyte)[] buffer, int flags = 0) {
		return new AsyncSendRequest(this, buffer, null, flags);
	}

	/++
		You can also construct your own request externally to control the memory more.
	+/
	AsyncReceiveRequest receive(ubyte[] buffer, int flags = 0) {
		return new AsyncReceiveRequest(this, buffer, null, flags);
	}

	/++
		You can also construct your own request externally to control the memory more.
	+/
	AsyncSendRequest sendTo(const(ubyte)[] buffer, SocketAddress* address, int flags = 0) {
		return new AsyncSendRequest(this, buffer, address, flags);
	}
	/++
		You can also construct your own request externally to control the memory more.
	+/
	AsyncReceiveRequest receiveFrom(ubyte[] buffer, SocketAddress* address, int flags = 0) {
		return new AsyncReceiveRequest(this, buffer, address, flags);
	}

	/++
	+/
	SocketAddress localAddress() {
		SocketAddress addr;
		getsockname(handle, &addr.address, &addr.addrlen);
		return addr;
	}
	/++
	+/
	SocketAddress peerAddress() {
		SocketAddress addr;
		getpeername(handle, &addr.address, &addr.addrlen);
		return addr;
	}

	// for unix sockets on unix only: send/receive fd, get peer creds

	/++

	+/
	final NativeSocketHandle handle() {
		return handle_;
	}

	private NativeSocketHandle handle_;
}

/++
	Initiates a connection request and optionally sends initial data as soon as possible.

	Calls `ConnectEx` on Windows and emulates it on other systems.

	The entire buffer is sent before the operation is considered complete.

	NOT IMPLEMENTED / NOT STABLE
+/
version(HasSocket) class AsyncConnectRequest : AsyncOperationRequest {
	// FIXME: i should take a list of addresses and take the first one that succeeds, so a getaddrinfo can be sent straight in.
	this(AsyncSocket socket, SocketAddress address, ubyte[] dataToWrite) {

	}

	override void start() {}
	override void cancel() {}
	override bool isComplete() { return true; }
	override AsyncConnectResponse waitForCompletion() { assert(0); }
}
/++
+/
version(HasSocket) class AsyncConnectResponse : AsyncOperationResponse {
	const SystemErrorCode errorCode;

	this(SystemErrorCode errorCode) {
		this.errorCode = errorCode;
	}

	override bool wasSuccessful() {
		return errorCode.wasSuccessful;
	}

}

// FIXME: TransmitFile/sendfile support

/++
	Calls `AcceptEx` on Windows and emulates it on other systems.

	NOT IMPLEMENTED / NOT STABLE
+/
version(HasSocket) class AsyncAcceptRequest : AsyncOperationRequest {
	AsyncSocket socket;

	override void start() {}
	override void cancel() {}
	override bool isComplete() { return true; }
	override AsyncConnectResponse waitForCompletion() { assert(0); }


	struct LowLevelOperation {
		AsyncSocket file;
		ubyte[] buffer;
		SocketAddress* address;

		this(typeof(this.tupleof) args) {
			this.tupleof = args;
		}

		version(Windows) {
			auto opCall(OVERLAPPED* overlapped, LPOVERLAPPED_COMPLETION_ROUTINE ocr) {
				WSABUF buf;
				buf.len = cast(int) buffer.length;
				buf.buf = cast(typeof(buf.buf)) buffer.ptr;

				uint flags;

				if(address is null)
					return WSARecv(file.handle, &buf, 1, null, &flags, overlapped, ocr);
				else {
					return WSARecvFrom(file.handle, &buf, 1, null, &flags, &(address.address), &(address.addrlen), overlapped, ocr);
				}
			}
		} else {
			auto opCall() {
				int flags;
				if(address is null)
					return core.sys.posix.sys.socket.recv(file.handle, buffer.ptr, buffer.length, flags);
				else
					return core.sys.posix.sys.socket.recvfrom(file.handle, buffer.ptr, buffer.length, flags, &(address.address), &(address.addrlen));
			}
		}

		string errorString() {
			return "Receive";
		}
	}
	mixin OverlappedIoRequest!(AsyncAcceptResponse, LowLevelOperation);

	this(AsyncSocket socket, ubyte[] buffer = null, SocketAddress* address = null) {
		llo = LowLevelOperation(socket, buffer, address);
		this.response = typeof(this.response).defaultConstructed;
	}

	// can also look up the local address
}
/++
+/
version(HasSocket) class AsyncAcceptResponse : AsyncOperationResponse {
	AsyncSocket newSocket;
	const SystemErrorCode errorCode;

	this(SystemErrorCode errorCode, ubyte[] buffer) {
		this.errorCode = errorCode;
	}

	this(AsyncSocket newSocket, SystemErrorCode errorCode) {
		this.newSocket = newSocket;
		this.errorCode = errorCode;
	}

	override bool wasSuccessful() {
		return errorCode.wasSuccessful;
	}
}

/++
+/
version(HasSocket) class AsyncReceiveRequest : AsyncOperationRequest {
	struct LowLevelOperation {
		AsyncSocket file;
		ubyte[] buffer;
		int flags;
		SocketAddress* address;

		this(typeof(this.tupleof) args) {
			this.tupleof = args;
		}

		version(Windows) {
			auto opCall(OVERLAPPED* overlapped, LPOVERLAPPED_COMPLETION_ROUTINE ocr) {
				WSABUF buf;
				buf.len = cast(int) buffer.length;
				buf.buf = cast(typeof(buf.buf)) buffer.ptr;

				uint flags = this.flags;

				if(address is null)
					return WSARecv(file.handle, &buf, 1, null, &flags, overlapped, ocr);
				else {
					return WSARecvFrom(file.handle, &buf, 1, null, &flags, &(address.address), &(address.addrlen), overlapped, ocr);
				}
			}
		} else {
			auto opCall() {
				if(address is null)
					return core.sys.posix.sys.socket.recv(file.handle, buffer.ptr, buffer.length, flags);
				else
					return core.sys.posix.sys.socket.recvfrom(file.handle, buffer.ptr, buffer.length, flags, &(address.address), &(address.addrlen));
			}
		}

		string errorString() {
			return "Receive";
		}
	}
	mixin OverlappedIoRequest!(AsyncReceiveResponse, LowLevelOperation);

	this(AsyncSocket socket, ubyte[] buffer, SocketAddress* address, int flags) {
		llo = LowLevelOperation(socket, buffer, flags, address);
		this.response = typeof(this.response).defaultConstructed;
	}

}
/++
+/
version(HasSocket) class AsyncReceiveResponse : AsyncOperationResponse {
	const ubyte[] bufferWritten;
	const SystemErrorCode errorCode;

	this(SystemErrorCode errorCode, const(ubyte)[] bufferWritten) {
		this.errorCode = errorCode;
		this.bufferWritten = bufferWritten;
	}

	override bool wasSuccessful() {
		return errorCode.wasSuccessful;
	}
}

/++
+/
version(HasSocket) class AsyncSendRequest : AsyncOperationRequest {
	struct LowLevelOperation {
		AsyncSocket file;
		const(ubyte)[] buffer;
		int flags;
		SocketAddress* address;

		this(typeof(this.tupleof) args) {
			this.tupleof = args;
		}

		version(Windows) {
			auto opCall(OVERLAPPED* overlapped, LPOVERLAPPED_COMPLETION_ROUTINE ocr) {
				WSABUF buf;
				buf.len = cast(int) buffer.length;
				buf.buf = cast(typeof(buf.buf)) buffer.ptr;

				if(address is null)
					return WSASend(file.handle, &buf, 1, null, flags, overlapped, ocr);
				else {
					return WSASendTo(file.handle, &buf, 1, null, flags, address.rawAddr, address.rawAddrLength, overlapped, ocr);
				}
			}
		} else {
			auto opCall() {
				if(address is null)
					return core.sys.posix.sys.socket.send(file.handle, buffer.ptr, buffer.length, flags);
				else
					return core.sys.posix.sys.socket.sendto(file.handle, buffer.ptr, buffer.length, flags, address.rawAddr, address.rawAddrLength);
			}
		}

		string errorString() {
			return "Send";
		}
	}
	mixin OverlappedIoRequest!(AsyncSendResponse, LowLevelOperation);

	this(AsyncSocket socket, const(ubyte)[] buffer, SocketAddress* address, int flags) {
		llo = LowLevelOperation(socket, buffer, flags, address);
		this.response = typeof(this.response).defaultConstructed;
	}
}

/++
+/
version(HasSocket) class AsyncSendResponse : AsyncOperationResponse {
	const ubyte[] bufferWritten;
	const SystemErrorCode errorCode;

	this(SystemErrorCode errorCode, const(ubyte)[] bufferWritten) {
		this.errorCode = errorCode;
		this.bufferWritten = bufferWritten;
	}

	override bool wasSuccessful() {
		return errorCode.wasSuccessful;
	}

}

/++
	A set of sockets bound and ready to accept connections on worker threads.

	Depending on the specified address, it can be tcp, tcpv6, unix domain, or all of the above.

	NOT IMPLEMENTED / NOT STABLE
+/
version(HasSocket) class StreamServer {
	AsyncSocket[] sockets;

	this(SocketAddress[] listenTo, int backlog = 8) {
		foreach(listen; listenTo) {
			auto socket = new AsyncSocket(listen, SOCK_STREAM);

			// FIXME: allInterfaces for ipv6 also covers ipv4 so the bind can fail...
			// so we have to permit it to fail w/ address in use if we know we already
			// are listening to ipv6

			// or there is a setsockopt ipv6 only thing i could set.

			socket.bind(listen);
			socket.listen(backlog);
			sockets ~= socket;

			// writeln(socket.localAddress.port);
		}

		// i have to start accepting on each thread for each socket...
	}
	// when a new connection arrives, it calls your callback
	// can be on a specific thread or on any thread


	void start() {
		foreach(socket; sockets) {
			auto request = socket.accept();
			request.start();
		}
	}
}

/+
unittest {
	auto ss = new StreamServer(SocketAddress.localhost(0));
}
+/

/++
	A socket bound and ready to use receiveFrom

	Depending on the address, it can be udp or unix domain.

	NOT IMPLEMENTED / NOT STABLE
+/
version(HasSocket) class DatagramListener {
	// whenever a udp message arrives, it calls your callback
	// can be on a specific thread or on any thread

	// UDP is realistically just an async read on the bound socket
	// just it can get the "from" data out and might need the "more in packet" flag
}

/++
	Just in case I decide to change the implementation some day.
+/
version(HasFile) alias AsyncAnonymousPipe = AsyncFile;


// AsyncAnonymousPipe connectNamedPipe(AsyncAnonymousPipe preallocated, string name)

// unix fifos are considered just non-seekable files and have no special support in the lib; open them as a regular file w/ the async flag.

// DIRECTORY LISTINGS
	// not async, so if you want that, do it in a helper thread
	// just a convenient function to have (tho phobos has a decent one too, importing it expensive af)

/++
	Note that the order of items called for your delegate is undefined; if you want it sorted, you'll have to collect and sort yourself. But it *might* be sorted by the OS (on Windows, it almost always is), so consider that when choosing a sorting algorithm.

	History:
		previously in minigui as a private function. Moved to arsd.core on April 3, 2023
+/
version(HasFile) GetFilesResult getFiles(string directory, scope void delegate(string name, bool isDirectory) dg) {
	// FIXME: my buffers here aren't great lol

	SavedArgument[1] argsForException() {
		return [
			SavedArgument("directory", LimitedVariant(directory)),
		];
	}

	version(Windows) {
		WIN32_FIND_DATA data;
		// FIXME: if directory ends with / or \\ ?
		WCharzBuffer search = WCharzBuffer(directory ~ "/*");
		auto handle = FindFirstFileW(search.ptr, &data);
		scope(exit) if(handle !is INVALID_HANDLE_VALUE) FindClose(handle);
		if(handle is INVALID_HANDLE_VALUE) {
			if(GetLastError() == ERROR_FILE_NOT_FOUND)
				return GetFilesResult.fileNotFound;
			throw new WindowsApiException("FindFirstFileW", GetLastError(), argsForException()[]);
		}

		try_more:

		string name = makeUtf8StringFromWindowsString(data.cFileName[0 .. findIndexOfZero(data.cFileName[])]);

		/+
  FILETIME ftLastWriteTime;
  DWORD    nFileSizeHigh;
  DWORD    nFileSizeLow;

  but these not available on linux w/o statting each file!
		+/

		dg(name, (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? true : false);

		auto ret = FindNextFileW(handle, &data);
		if(ret == 0) {
			if(GetLastError() == ERROR_NO_MORE_FILES)
				return GetFilesResult.success;
			throw new WindowsApiException("FindNextFileW", GetLastError(), argsForException()[]);
		}

		goto try_more;

	} else version(Posix) {
		import core.sys.posix.dirent;
		import core.stdc.errno;
		auto dir = opendir((directory ~ "\0").ptr);
		scope(exit)
			if(dir) closedir(dir);
		if(dir is null)
			throw new ErrnoApiException("opendir", errno, argsForException());

		auto dirent = readdir(dir);
		if(dirent is null)
			return GetFilesResult.fileNotFound;

		try_more:

		string name = dirent.d_name[0 .. findIndexOfZero(dirent.d_name[])].idup;

		dg(name, dirent.d_type == DT_DIR);

		dirent = readdir(dir);
		if(dirent is null)
			return GetFilesResult.success;

		goto try_more;
	} else static assert(0);
}

/// ditto
enum GetFilesResult {
	success,
	fileNotFound
}

/++
	This is currently a simplified glob where only the * wildcard in the first or last position gets special treatment or a single * in the middle.

	More things may be added later to be more like what Phobos supports.
+/
bool matchesFilePattern(scope const(char)[] name, scope const(char)[] pattern) {
	if(pattern.length == 0)
		return false;
	if(pattern == "*")
		return true;
	if(pattern.length > 2 && pattern[0] == '*' && pattern[$-1] == '*') {
		// if the rest of pattern appears in name, it is good
		return name.indexOf(pattern[1 .. $-1]) != -1;
	} else if(pattern[0] == '*') {
		// if the rest of pattern is at end of name, it is good
		return name.endsWith(pattern[1 .. $]);
	} else if(pattern[$-1] == '*') {
		// if the rest of pattern is at start of name, it is good
		return name.startsWith(pattern[0 .. $-1]);
	} else if(pattern.length >= 3) {
		auto idx = pattern.indexOf("*");
		if(idx != -1) {
			auto lhs = pattern[0 .. idx];
			auto rhs = pattern[idx + 1 .. $];
			if(name.length >= lhs.length + rhs.length) {
				return name.startsWith(lhs) && name.endsWith(rhs);
			} else {
				return false;
			}
		}
	}

	return name == pattern;
}

unittest {
	assert("test.html".matchesFilePattern("*"));
	assert("test.html".matchesFilePattern("*.html"));
	assert("test.html".matchesFilePattern("*.*"));
	assert("test.html".matchesFilePattern("test.*"));
	assert(!"test.html".matchesFilePattern("pest.*"));
	assert(!"test.html".matchesFilePattern("*.dhtml"));

	assert("test.html".matchesFilePattern("t*.html"));
	assert(!"test.html".matchesFilePattern("e*.html"));
}

package(arsd) int indexOf(scope const(char)[] haystack, scope const(char)[] needle) {
	if(haystack.length < needle.length)
		return -1;
	if(haystack == needle)
		return 0;
	foreach(i; 0 .. haystack.length - needle.length + 1)
		if(haystack[i .. i + needle.length] == needle)
			return cast(int) i;
	return -1;
}

package(arsd) int indexOf(scope const(ubyte)[] haystack, scope const(char)[] needle) {
	return indexOf(cast(const(char)[]) haystack, needle);
}

unittest {
	assert("foo".indexOf("f") == 0);
	assert("foo".indexOf("o") == 1);
	assert("foo".indexOf("foo") == 0);
	assert("foo".indexOf("oo") == 1);
	assert("foo".indexOf("fo") == 0);
	assert("foo".indexOf("boo") == -1);
	assert("foo".indexOf("food") == -1);
}

package(arsd) bool endsWith(scope const(char)[] haystack, scope const(char)[] needle) {
	if(needle.length > haystack.length)
		return false;
	return haystack[$ - needle.length .. $] == needle;
}

unittest {
	assert("foo".endsWith("o"));
	assert("foo".endsWith("oo"));
	assert("foo".endsWith("foo"));
	assert(!"foo".endsWith("food"));
	assert(!"foo".endsWith("d"));
}

package(arsd) bool startsWith(scope const(char)[] haystack, scope const(char)[] needle) {
	if(needle.length > haystack.length)
		return false;
	return haystack[0 .. needle.length] == needle;
}

unittest {
	assert("foo".startsWith("f"));
	assert("foo".startsWith("fo"));
	assert("foo".startsWith("foo"));
	assert(!"foo".startsWith("food"));
	assert(!"foo".startsWith("d"));
}


// FILE/DIR WATCHES
	// linux does it by name, windows and bsd do it by handle/descriptor
	// dispatches change event to either your thread or maybe the any task` queue.

/++
	PARTIALLY IMPLEMENTED / NOT STABLE

+/
class DirectoryWatcher {
	private {
		version(Arsd_core_windows) {
			OVERLAPPED overlapped;
			HANDLE hDirectory;
			ubyte[] buffer;

			extern(Windows)
			static void overlappedCompletionRoutine(DWORD dwErrorCode, DWORD dwNumberOfBytesTransferred, LPOVERLAPPED lpOverlapped) @system {
				typeof(this) rr = cast(typeof(this)) (cast(void*) lpOverlapped - typeof(this).overlapped.offsetof);

				// dwErrorCode
				auto response = rr.buffer[0 .. dwNumberOfBytesTransferred];

				while(response.length) {
					auto fni = cast(FILE_NOTIFY_INFORMATION*) response.ptr;
					auto filename = fni.FileName[0 .. fni.FileNameLength];

					if(fni.NextEntryOffset)
						response = response[fni.NextEntryOffset .. $];
					else
						response = response[$..$];

					// FIXME: I think I need to pin every overlapped op while it is pending
					// and unpin it when it is returned. GC.addRoot... but i don't wanna do that
					// every op so i guess i should do a refcount scheme similar to the other callback helper.

					rr.changeHandler(
						FilePath(makeUtf8StringFromWindowsString(filename)), // FIXME: this is a relative path
						ChangeOperation.unknown // FIXME this is fni.Action
					);
				}

				rr.requestRead();
			}

			void requestRead() {
				DWORD ignored;
				if(!ReadDirectoryChangesW(
					hDirectory,
					buffer.ptr,
					cast(int) buffer.length,
					recursive,
					FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_CREATION | FILE_NOTIFY_CHANGE_FILE_NAME,
					&ignored,
					&overlapped,
					&overlappedCompletionRoutine
				)) {
					auto error = GetLastError();
					/+
					if(error == ERROR_IO_PENDING) {
						// not expected here, the docs say it returns true when queued
					}
					+/

					throw new SystemApiException("ReadDirectoryChangesW", error);
				}
			}
		} else version(Arsd_core_epoll) {
			static int inotifyfd = -1; // this is TLS since it is associated with the thread's event loop
			static ICoreEventLoop.UnregisterToken inotifyToken;
			static CallbackHelper inotifycb;
			static DirectoryWatcher[int] watchMappings;

			static ~this() {
				if(inotifyfd != -1) {
					close(inotifyfd);
					inotifyfd = -1;
				}
			}

			import core.sys.linux.sys.inotify;

			int watchId = -1;

			static void inotifyReady() {
				// read from it
				ubyte[256 /* NAME_MAX + 1 */ + inotify_event.sizeof] sbuffer;

				auto ret = read(inotifyfd, sbuffer.ptr, sbuffer.length);
				if(ret == -1) {
					auto errno = errno;
					if(errno == EAGAIN || errno == EWOULDBLOCK)
						return;
					throw new SystemApiException("read inotify", errno);
				} else if(ret == 0) {
					assert(0, "I don't think this is ever supposed to happen");
				}

				auto buffer = sbuffer[0 .. ret];

				while(buffer.length > 0) {
					inotify_event* event = cast(inotify_event*) buffer.ptr;
					buffer = buffer[inotify_event.sizeof .. $];
					char[] filename = cast(char[]) buffer[0 .. event.len];
					buffer = buffer[event.len .. $];

					// note that filename is padded with zeroes, so it is actually a stringz

					if(auto obj = event.wd in watchMappings) {
						(*obj).changeHandler(
							FilePath(stringz(filename.ptr).borrow.idup), // FIXME: this is a relative path
							ChangeOperation.unknown // FIXME
						);
					} else {
						// it has probably already been removed
					}
				}
			}
		} else version(Arsd_core_kqueue) {
			int fd;
			CallbackHelper cb;
		}

		FilePath path;
		string globPattern;
		bool recursive;
		void delegate(FilePath filename, ChangeOperation op) changeHandler;
	}

	enum ChangeOperation {
		unknown,
		deleted, // NOTE_DELETE, IN_DELETE, FILE_NOTIFY_CHANGE_FILE_NAME
		written, // NOTE_WRITE / NOTE_EXTEND / NOTE_TRUNCATE, IN_MODIFY, FILE_NOTIFY_CHANGE_LAST_WRITE / FILE_NOTIFY_CHANGE_SIZE
		renamed, // NOTE_RENAME, the moved from/to in linux, FILE_NOTIFY_CHANGE_FILE_NAME
		metadataChanged // NOTE_ATTRIB, IN_ATTRIB, FILE_NOTIFY_CHANGE_ATTRIBUTES

		// there is a NOTE_OPEN on freebsd 13, and the access change on Windows. and an open thing on linux. so maybe i can do note open/note_read too.
	}

	/+
		Windows and Linux work best when you watch directories. The operating system tells you the name of files as they change.

		BSD doesn't support this. You can only get names and reports when a file is modified by watching specific files. AS such, when you watch a directory on those systems, your delegate will be called with a null path. Cross-platform applications should check for this and not assume the name is always usable.

		inotify is kinda clearly the best of the bunch, with Windows in second place, and kqueue dead last.


		If path to watch is a directory, it signals when a file inside the directory (only one layer deep) is created or modified. This is the most efficient on Windows and Linux.

		If a path is a file, it only signals when that specific file is written. This is most efficient on BSD.


		The delegate is called when something happens. Note that the path modified may not be accurate on all systems when you are watching a directory.
	+/

	/++
		Watches a directory and its contents. If the `globPattern` is `null`, it will not attempt to add child items but also will not filter it, meaning you will be left with platform-specific behavior.

		On Windows, the globPattern is just used to filter events.

		On Linux, the `recursive` flag, if set, will cause it to add additional OS-level watches for each subdirectory.

		On BSD, anything other than a null pattern will cause a directory scan to add files to the watch list.

		For best results, use the most limited thing you need, as watches can get quite involved on the bsd systems.

		Newly added files and subdirectories may not be automatically added in all cases, meaning if it is added and then subsequently modified, you might miss a notification.

		If the event queue is too busy, the OS may skip a notification.

		You should always offer some way for the user to force a refresh and not rely on notifications being present; they are a convenience when they work, not an always reliable method.
	+/
	this(FilePath directoryToWatch, string globPattern, bool recursive, void delegate(FilePath pathModified, ChangeOperation op) dg) {
		this.path = directoryToWatch;
		this.globPattern = globPattern;
		this.recursive = recursive;
		this.changeHandler = dg;

		version(Arsd_core_windows) {
			WCharzBuffer wname = directoryToWatch.path;
			buffer = new ubyte[](1024);
			hDirectory = CreateFileW(
				wname.ptr,
				GENERIC_READ,
				FILE_SHARE_READ,
				null,
				OPEN_EXISTING,
				FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED | FILE_FLAG_BACKUP_SEMANTICS,
				null
			);
			if(hDirectory == INVALID_HANDLE_VALUE)
				throw new SystemApiException("CreateFileW", GetLastError());

			requestRead();
		} else version(Arsd_core_epoll) {
			auto el = getThisThreadEventLoop();

			// no need for sync because it is thread-local
			if(inotifyfd == -1) {
				inotifyfd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
				if(inotifyfd == -1)
					throw new SystemApiException("inotify_init1", errno);

				inotifycb = new CallbackHelper(&inotifyReady);
				inotifyToken = el.addCallbackOnFdReadable(inotifyfd, inotifycb);
			}

			uint event_mask = IN_CREATE | IN_MODIFY  | IN_DELETE; // FIXME
			CharzBuffer dtw = directoryToWatch.path;
			auto watchId = inotify_add_watch(inotifyfd, dtw.ptr, event_mask);
			if(watchId < -1)
				throw new SystemApiException("inotify_add_watch", errno, [SavedArgument("path", LimitedVariant(directoryToWatch.path))]);

			watchMappings[watchId] = this;

			// FIXME: recursive needs to add child things individually

		} else version(Arsd_core_kqueue) {
			auto el = cast(CoreEventLoopImplementation) getThisThreadEventLoop();

			// FIXME: need to scan for globPattern
			// when a new file is added, i'll have to diff my list to detect it and open it too
			// and recursive might need to scan down too.

			kevent_t ev;

			import core.sys.posix.fcntl;
			CharzBuffer buffer = CharzBuffer(directoryToWatch.path);
			fd = ErrnoEnforce!open(buffer.ptr, O_RDONLY);
			setCloExec(fd);

			cb = new CallbackHelper(&triggered);

			EV_SET(&ev, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE | EV_CLEAR, NOTE_WRITE, 0, cast(void*) cb);
			ErrnoEnforce!kevent(el.kqueuefd, &ev, 1, null, 0, null);
		} else assert(0, "Not yet implemented for this platform");
	}

	private void triggered() {
		writeln("triggered");
	}

	void dispose() {
		version(Arsd_core_windows) {
			CloseHandle(hDirectory);
		} else version(Arsd_core_epoll) {
			watchMappings.remove(watchId); // I could also do this on the IN_IGNORE notification but idk
			inotify_rm_watch(inotifyfd, watchId);
		} else version(Arsd_core_kqueue) {
			ErrnoEnforce!close(fd);
			fd = -1;
		}
	}
}

version(none)
void main() {

	// auto file = new AsyncFile(FilePath("test.txt"), AsyncFile.OpenMode.writeWithTruncation, AsyncFile.RequirePreexisting.yes);

	/+
	getFiles("c:/windows\\", (string filename, bool isDirectory) {
		writeln(filename, " ", isDirectory ? "[dir]": "[file]");
	});
	+/

	auto w = new DirectoryWatcher(FilePath("."), "*", false, (path, op) {
		writeln(path.path);
	});
	getThisThreadEventLoop().run(() => false);
}

/++
	This starts up a local pipe. If it is already claimed, it just communicates with the existing one through the interface.
+/
class SingleInstanceApplication {
	// FIXME
}

version(none)
void main() {

	auto file = new AsyncFile(FilePath("test.txt"), AsyncFile.OpenMode.writeWithTruncation, AsyncFile.RequirePreexisting.yes);

	auto buffer = cast(ubyte[]) "hello";
	auto wr = new AsyncWriteRequest(file, buffer, 0);
	wr.start();

	wr.waitForCompletion();

	file.close();
}

/++
	Implementation details of some requests. You shouldn't need to know any of this, the interface is all public.
+/
mixin template OverlappedIoRequest(Response, LowLevelOperation) {
	private {
		LowLevelOperation llo;

		OwnedClass!Response response;

		version(Windows) {
			OVERLAPPED overlapped;

			extern(Windows)
			static void overlappedCompletionRoutine(DWORD dwErrorCode, DWORD dwNumberOfBytesTransferred, LPOVERLAPPED lpOverlapped) @system {
				typeof(this) rr = cast(typeof(this)) (cast(void*) lpOverlapped - typeof(this).overlapped.offsetof);

				rr.response = typeof(rr.response)(SystemErrorCode(dwErrorCode), rr.llo.buffer[0 .. dwNumberOfBytesTransferred]);
				rr.state_ = State.complete;

				if(rr.oncomplete)
					rr.oncomplete(rr);

				// FIXME: on complete?
				// this will queue our CallbackHelper and that should be run at the end of the event loop after it is woken up by the APC run
			}
		}

		version(Posix) {
			ICoreEventLoop.RearmToken eventRegistration;
			CallbackHelper cb;

			final CallbackHelper getCb() {
				if(cb is null)
					cb = new CallbackHelper(&cbImpl);
				return cb;
			}

			final void cbImpl() {
				// it is ready to complete, time to do it
				auto ret = llo();
				markCompleted(ret, errno);
			}

			void markCompleted(long ret, int errno) {
				// maybe i should queue an apc to actually do it, to ensure the event loop has cycled... FIXME
				if(ret == -1)
					response = typeof(response)(SystemErrorCode(errno), null);
				else
					response = typeof(response)(SystemErrorCode(0), llo.buffer[0 .. cast(size_t) ret]);
				state_ = State.complete;

				if(oncomplete)
					oncomplete(this);
			}
		}
	}

	enum State {
		unused,
		started,
		inProgress,
		complete
	}
	private State state_;

	override void start() {
		assert(state_ == State.unused);

		state_ = State.started;

		version(Windows) {
			if(llo(&overlapped, &overlappedCompletionRoutine)) {
				// all good, though GetLastError() might have some informative info
				//writeln(GetLastError());
			} else {
				// operation failed, the operation is always ReadFileEx or WriteFileEx so it won't give the io pending thing here
				// should i issue error async? idk
				state_ = State.complete;
				throw new SystemApiException(llo.errorString(), GetLastError());
			}

			// ReadFileEx always queues, even if it completed synchronously. I *could* check the get overlapped result and sleepex here but i'm prolly better off just letting the event loop do its thing anyway.
		} else version(Posix) {

			// first try to just do it
			auto ret = llo();

			auto errno = errno;
			if(ret == -1 && (errno == EAGAIN || errno == EWOULDBLOCK)) { // unable to complete right now, register and try when it is ready
				if(eventRegistration is typeof(eventRegistration).init)
					eventRegistration = getThisThreadEventLoop().addCallbackOnFdReadableOneShot(this.llo.file.handle, this.getCb);
				else
					eventRegistration.rearm();
			} else {
				// i could set errors sync or async and since it couldn't even start, i think a sync exception is the right way
				if(ret == -1)
					throw new SystemApiException(llo.errorString(), errno);
				markCompleted(ret, errno); // it completed synchronously (if it is an error nor not is handled by the completion handler)
			}
		}
	}

	override void cancel() {
		if(state_ == State.complete)
			return; // it has already finished, just leave it alone, no point discarding what is already done
		version(Windows) {
			if(state_ != State.unused)
				Win32Enforce!CancelIoEx(llo.file.AbstractFile.handle, &overlapped);
			// Windows will notify us when the cancellation is complete, so we need to wait for that before updating the state
		} else version(Posix) {
			if(state_ != State.unused)
				eventRegistration.unregister();
			markCompleted(-1, ECANCELED);
		}
	}

	override bool isComplete() {
		// just always let the event loop do it instead
		return state_ == State.complete;

		/+
		version(Windows) {
			return HasOverlappedIoCompleted(&overlapped);
		} else version(Posix) {
			return state_ == State.complete;

		}
		+/
	}

	override Response waitForCompletion() {
		if(state_ == State.unused)
			start();

		// FIXME: if we are inside a fiber, we can set a oncomplete callback and then yield instead...
		if(state_ != State.complete)
			getThisThreadEventLoop().run(&isComplete);

		/+
		version(Windows) {
			SleepEx(INFINITE, true);

			//DWORD numberTransferred;
			//Win32Enforce!GetOverlappedResult(file.handle, &overlapped, &numberTransferred, true);
		} else version(Posix) {
			getThisThreadEventLoop().run(&isComplete);
		}
		+/

		return response;
	}

	/++
		Repeats the operation, restarting the request.

		This must only be called when the operation has already completed.
	+/
	void repeat() {
		if(state_ != State.complete)
			throw new Exception("wrong use, cannot repeat if not complete");
		state_ = State.unused;
		start();
	}

	void delegate(typeof(this) t) oncomplete;
}

/++
	You can write to a file asynchronously by creating one of these.
+/
version(HasSocket) final class AsyncWriteRequest : AsyncOperationRequest {
	struct LowLevelOperation {
		AsyncFile file;
		ubyte[] buffer;
		long offset;

		this(typeof(this.tupleof) args) {
			this.tupleof = args;
		}

		version(Windows) {
			auto opCall(OVERLAPPED* overlapped, LPOVERLAPPED_COMPLETION_ROUTINE ocr) {
				overlapped.Offset = (cast(ulong) offset) & 0xffff_ffff;
				overlapped.OffsetHigh = ((cast(ulong) offset) >> 32) & 0xffff_ffff;
				return WriteFileEx(file.handle, buffer.ptr, cast(int) buffer.length, overlapped, ocr);
			}
		} else {
			auto opCall() {
				return core.sys.posix.unistd.write(file.handle, buffer.ptr, buffer.length);
			}
		}

		string errorString() {
			return "Write";
		}
	}
	mixin OverlappedIoRequest!(AsyncWriteResponse, LowLevelOperation);

	this(AsyncFile file, ubyte[] buffer, long offset) {
		this.llo = LowLevelOperation(file, buffer, offset);
		response = typeof(response).defaultConstructed;
	}
}

/++

+/
class AsyncWriteResponse : AsyncOperationResponse {
	const ubyte[] bufferWritten;
	const SystemErrorCode errorCode;

	this(SystemErrorCode errorCode, const(ubyte)[] bufferWritten) {
		this.errorCode = errorCode;
		this.bufferWritten = bufferWritten;
	}

	override bool wasSuccessful() {
		return errorCode.wasSuccessful;
	}
}

// FIXME: on Windows, you may want two operations outstanding at once
// so there's no delay between sequential ops. this system currently makes that
// impossible since epoll won't let you register twice...

// FIXME: if an op completes synchronously, and oncomplete calls repeat
// you can get infinite recursion into the stack...

/++

+/
version(HasSocket) final class AsyncReadRequest : AsyncOperationRequest {
	struct LowLevelOperation {
		AsyncFile file;
		ubyte[] buffer;
		long offset;

		this(typeof(this.tupleof) args) {
			this.tupleof = args;
		}

		version(Windows) {
			auto opCall(OVERLAPPED* overlapped, LPOVERLAPPED_COMPLETION_ROUTINE ocr) {
				overlapped.Offset = (cast(ulong) offset) & 0xffff_ffff;
				overlapped.OffsetHigh = ((cast(ulong) offset) >> 32) & 0xffff_ffff;
				return ReadFileEx(file.handle, buffer.ptr, cast(int) buffer.length, overlapped, ocr);
			}
		} else {
			auto opCall() {
				return core.sys.posix.unistd.read(file.handle, buffer.ptr, buffer.length);
			}
		}

		string errorString() {
			return "Read";
		}
	}
	mixin OverlappedIoRequest!(AsyncReadResponse, LowLevelOperation);

	/++
		The file must have the overlapped flag enabled on Windows and the nonblock flag set on Posix.

		The buffer MUST NOT be touched by you - not used by another request, modified, read, or freed, including letting a static array going out of scope - until this request's `isComplete` returns `true`.

		The offset is where to start reading a disk file. For all other types of files, pass 0.
	+/
	this(AsyncFile file, ubyte[] buffer, long offset) {
		this.llo = LowLevelOperation(file, buffer, offset);
		response = typeof(response).defaultConstructed;
	}

	/++

	+/
	// abstract void repeat();
}

/++

+/
class AsyncReadResponse : AsyncOperationResponse {
	const ubyte[] bufferRead;
	const SystemErrorCode errorCode;

	this(SystemErrorCode errorCode, const(ubyte)[] bufferRead) {
		this.errorCode = errorCode;
		this.bufferRead = bufferRead;
	}

	override bool wasSuccessful() {
		return errorCode.wasSuccessful;
	}
}

/+
	Tasks:
		startTask()
		startSubTask() - what if it just did this when it knows it is being run from inside a task?
		runHelperFunction() - whomever it reports to is the parent
+/

version(HasThread) class SchedulableTask : Fiber {
	private void delegate() dg;

	// linked list stuff
	private static SchedulableTask taskRoot;
	private SchedulableTask previous;
	private SchedulableTask next;

	// need the controlling thread to know how to wake it up if it receives a message
	private Thread controllingThread;

	// the api

	this(void delegate() dg) {
		assert(dg !is null);

		this.dg = dg;
		super(&taskRunner);

		if(taskRoot !is null) {
			this.next = taskRoot;
			taskRoot.previous = this;
		}
		taskRoot = this;
	}

	/+
	enum BehaviorOnCtrlC {
		ignore,
		cancel,
		deliverMessage
	}
	+/

	private bool cancelled;

	public void cancel() {
		this.cancelled = true;
		// if this is running, we can throw immediately
		// otherwise if we're calling from an appropriate thread, we can call it immediately
		// otherwise we need to queue a wakeup to its own thread.
		// tbh we should prolly just queue it every time
	}

	private void taskRunner() {
		try {
			dg();
		} catch(TaskCancelledException tce) {
			// this space intentionally left blank;
			// the purpose of this exception is to just
			// let the fiber's destructors run before we
			// let it die.
		} catch(Throwable t) {
			if(taskUncaughtException is null) {
				throw t;
			} else {
				taskUncaughtException(t);
			}
		} finally {
			if(this is taskRoot) {
				taskRoot = taskRoot.next;
				if(taskRoot !is null)
					taskRoot.previous = null;
			} else {
				assert(this.previous !is null);
				assert(this.previous.next is this);
				this.previous.next = this.next;
				if(this.next !is null)
					this.next.previous = this.previous;
			}
		}
	}
}

/++

+/
void delegate(Throwable t) taskUncaughtException;

/++
	Gets an object that lets you control a schedulable task (which is a specialization of a fiber) and can be used in an `if` statement.

	---
		if(auto controller = inSchedulableTask()) {
			controller.yieldUntilReadable(...);
		}
	---

	History:
		Added August 11, 2023 (dub v11.1)
+/
version(HasThread) SchedulableTaskController inSchedulableTask() {
	import core.thread.fiber;

	if(auto fiber = Fiber.getThis) {
		return SchedulableTaskController(cast(SchedulableTask) fiber);
	}

	return SchedulableTaskController(null);
}

/// ditto
version(HasThread) struct SchedulableTaskController {
	private this(SchedulableTask fiber) {
		this.fiber = fiber;
	}

	private SchedulableTask fiber;

	/++

	+/
	bool opCast(T : bool)() {
		return fiber !is null;
	}

	/++

	+/
	version(Posix)
	void yieldUntilReadable(NativeFileHandle handle) {
		assert(fiber !is null);

		auto cb = new CallbackHelper(() { fiber.call(); });

		// FIXME: if the fd is already registered in this thread it can throw...
		version(Windows)
			auto rearmToken = getThisThreadEventLoop().addCallbackOnFdReadableOneShot(handle, cb);
		else
			auto rearmToken = getThisThreadEventLoop().addCallbackOnFdReadableOneShot(handle, cb);

		// FIXME: this is only valid if the fiber is only ever going to run in this thread!
		fiber.yield();

		rearmToken.unregister();

		// what if there are other messages, like a ctrl+c?
		if(fiber.cancelled)
			throw new TaskCancelledException();
	}

	version(Windows)
	void yieldUntilSignaled(NativeFileHandle handle) {
		// add it to the WaitForMultipleObjects thing w/ a cb
	}
}

class TaskCancelledException : object.Exception {
	this() {
		super("Task cancelled");
	}
}

version(HasThread) private class CoreWorkerThread : Thread {
	this(EventLoopType type) {
		this.type = type;

		// task runners are supposed to have smallish stacks since they either just run a single callback or call into fibers
		// the helper runners might be a bit bigger tho
		super(&run);
	}
	void run() {
		eventLoop = getThisThreadEventLoop(this.type);
		atomicOp!"+="(startedCount, 1);
		atomicOp!"+="(runningCount, 1);
		scope(exit) {
			atomicOp!"-="(runningCount, 1);
		}

		eventLoop.run(() => cancelled);
	}

	private bool cancelled;

	void cancel() {
		cancelled = true;
	}

	EventLoopType type;
	ICoreEventLoop eventLoop;

	__gshared static {
		CoreWorkerThread[] taskRunners;
		CoreWorkerThread[] helperRunners;
		ICoreEventLoop mainThreadLoop;

		// for the helper function thing on the bsds i could have my own little circular buffer of availability

		shared(int) startedCount;
		shared(int) runningCount;

		bool started;

		void setup(int numberOfTaskRunners, int numberOfHelpers) {
			assert(!started);
			synchronized {
				mainThreadLoop = getThisThreadEventLoop();

				foreach(i; 0 .. numberOfTaskRunners) {
					auto nt = new CoreWorkerThread(EventLoopType.TaskRunner);
					taskRunners ~= nt;
					nt.start();
				}
				foreach(i; 0 .. numberOfHelpers) {
					auto nt = new CoreWorkerThread(EventLoopType.HelperWorker);
					helperRunners ~= nt;
					nt.start();
				}

				const expectedCount = numberOfHelpers + numberOfTaskRunners;

				while(startedCount < expectedCount) {
					Thread.yield();
				}

				started = true;
			}
		}

		void cancelAll() {
			foreach(runner; taskRunners)
				runner.cancel();
			foreach(runner; helperRunners)
				runner.cancel();

		}
	}
}

private int numberOfCpus() {
	return 4; // FIXME
}

/++
	To opt in to the full functionality of this module with customization opportunity, create one and only one of these objects that is valid for exactly the lifetime of the application.

	Normally, this means writing a main like this:

	---
	import arsd.core;
	void main() {
		ArsdCoreApplication app = ArsdCoreApplication("Your app name");

		// do your setup here

		// the rest of your code here
	}
	---

	Its destructor runs the event loop then waits to for the workers to finish to clean them up.
+/
// FIXME: single instance?
version(HasThread) struct ArsdCoreApplication {
	private ICoreEventLoop impl;

	/++
		default number of threads is to split your cpus between blocking function runners and task runners
	+/
	this(string applicationName) {
		auto num = numberOfCpus();
		num /= 2;
		if(num <= 0)
			num = 1;
		this(applicationName, num, num);
	}

	/++

	+/
	this(string applicationName, int numberOfTaskRunners, int numberOfHelpers) {
		impl = getThisThreadEventLoop(EventLoopType.Explicit);
		CoreWorkerThread.setup(numberOfTaskRunners, numberOfHelpers);
	}

	@disable this();
	@disable this(this);
	/++
		This must be deterministically destroyed.
	+/
	@disable new();

	~this() {
		if(!alreadyRun)
			run();
		exitApplication();
		waitForWorkersToExit(3000);
	}

	void exitApplication() {
		CoreWorkerThread.cancelAll();
	}

	void waitForWorkersToExit(int timeoutMilliseconds) {

	}

	private bool alreadyRun;

	void run() {
		impl.run(() => false);
		alreadyRun = true;
	}
}


private class CoreEventLoopImplementation : ICoreEventLoop {
	version(EmptyEventLoop) RunOnceResult runOnce(Duration timeout = Duration.max) { return RunOnceResult(RunOnceResult.Possibilities.LocalExit); }
	version(EmptyCoreEvent)
	{
		UnregisterToken addCallbackOnFdReadable(int fd, CallbackHelper cb){return typeof(return).init;}
		RearmToken addCallbackOnFdReadableOneShot(int fd, CallbackHelper cb){return typeof(return).init;}
		RearmToken addCallbackOnFdWritableOneShot(int fd, CallbackHelper cb){return typeof(return).init;}
		private void rearmFd(RearmToken token) {}
	}


	private {
		static struct LoopIterationDelegate {
			void delegate() dg;
			uint flags;
		}
		LoopIterationDelegate[] loopIterationDelegates;

		void runLoopIterationDelegates(bool isAfter) {
			foreach(lid; loopIterationDelegates)
				if((!isAfter && (lid.flags & 1)) || (isAfter && (lid.flags & 2)))
					lid.dg();
		}
	}

	void addDelegateOnLoopIteration(void delegate() dg, uint timingFlags) {
		loopIterationDelegates ~= LoopIterationDelegate(dg, timingFlags);
	}

	version(Arsd_core_dispatch) {

		private NSRunLoop ttrl;

		private this() {
			ttrl = NSRunLoop.currentRunLoop;
		}

			// FIXME: this lies!! it runs until completion
		RunOnceResult runOnce(Duration timeout = Duration.max) {
			scope(exit) eventLoopRound++;

			// FIXME: autorelease pool

			if(false /*isWorker*/) {
				runLoopIterationDelegates(false);

				// FIXME: timeout is wrong
				auto retValue = ttrl.runMode(NSDefaultRunLoopMode, beforeDate: NSDate.distantFuture);
				if(retValue == false)
					throw new Exception("could not start run loop");

				runLoopIterationDelegates(true);

				// NSApp.run();
				// exitApplication();
				//return RunOnceResult(RunOnceResult.Possibilities.GlobalExit);
				return RunOnceResult(RunOnceResult.Possibilities.CarryOn);
			} else {
				// ui thread needs to pump nsapp events...
				runLoopIterationDelegates(false);

				auto timeoutNs = NSDate.distantFuture; // FIXME timeout here, future means no timeout

				again:
				NSEvent event = NSApp.nextEventMatchingMask(
					NSEventMask.NSEventMaskAny,
					timeoutNs,
					NSDefaultRunLoopMode,
					true
				);
				if(event !is null) {
					NSApp.sendEvent(event);
					timeoutNs = NSDate.distantPast; // only keep going if it won't block; we just want to clear the queue
					goto again;
				}

				runLoopIterationDelegates(true);
				return RunOnceResult(RunOnceResult.Possibilities.CarryOn);
			}
		}

		UnregisterToken addCallbackOnFdReadable(int fd, CallbackHelper cb) {
			auto input_src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_main_queue());
			// FIXME: can the GC reap this prematurely?
			auto b = block(() {
				cb.call();
			});
			// FIXME: should prolly free it eventually idk
			import core.memory;
			GC.addRoot(b);

			dispatch_source_set_event_handler(input_src, b);
			// dispatch_source_set_cancel_handler(input_src,  ^{ close(my_file); });
			dispatch_resume(input_src);

			return UnregisterToken(this, fd, cb);

		}
		RearmToken addCallbackOnFdReadableOneShot(int fd, CallbackHelper cb) {
			throw new NotYetImplementedException();
		}
		RearmToken addCallbackOnFdWritableOneShot(int fd, CallbackHelper cb) {
			throw new NotYetImplementedException();
		}
		private void rearmFd(RearmToken token) {
			if(token.readable)
				cast(void) addCallbackOnFdReadableOneShot(token.fd, token.cb);
			else
				cast(void) addCallbackOnFdWritableOneShot(token.fd, token.cb);
		}
	}

	version(Arsd_core_kqueue) {
		// this thread apc dispatches go as a custom event to the queue
		// the other queues go through one byte at a time pipes (barf). freebsd 13 and newest nbsd have eventfd too tho so maybe i can use them but the other kqueue systems don't.

		RunOnceResult runOnce(Duration timeout = Duration.max) {
			scope(exit) eventLoopRound++;

			runLoopIterationDelegates(false);

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

			runLoopIterationDelegates(true);

			return RunOnceResult(RunOnceResult.Possibilities.CarryOn);
		}

		// FIXME: idk how to make one event that multiple kqueues can listen to w/o being shared
		// maybe a shared kqueue could work that the thread kqueue listen to (which i rejected for
		// epoll cuz it caused thundering herd problems but maybe it'd work here)

		UnregisterToken addCallbackOnFdReadable(int fd, CallbackHelper cb) {
			kevent_t ev;

			EV_SET(&ev, fd, EVFILT_READ, EV_ADD | EV_ENABLE/* | EV_ONESHOT*/, 0, 0, cast(void*) cb);

			ErrnoEnforce!kevent(kqueuefd, &ev, 1, null, 0, null);

			return UnregisterToken(this, fd, cb);
		}

		RearmToken addCallbackOnFdReadableOneShot(int fd, CallbackHelper cb) {
			kevent_t ev;

			EV_SET(&ev, fd, EVFILT_READ, EV_ADD | EV_ENABLE/* | EV_ONESHOT*/, 0, 0, cast(void*) cb);

			ErrnoEnforce!kevent(kqueuefd, &ev, 1, null, 0, null);

			return RearmToken(true, this, fd, cb, 0);
		}

		RearmToken addCallbackOnFdWritableOneShot(int fd, CallbackHelper cb) {
			kevent_t ev;

			EV_SET(&ev, fd, EVFILT_WRITE, EV_ADD | EV_ENABLE/* | EV_ONESHOT*/, 0, 0, cast(void*) cb);

			ErrnoEnforce!kevent(kqueuefd, &ev, 1, null, 0, null);

			return RearmToken(false, this, fd, cb, 0);
		}

		private void rearmFd(RearmToken token) {
			if(token.readable)
				cast(void) addCallbackOnFdReadableOneShot(token.fd, token.cb);
			else
				cast(void) addCallbackOnFdWritableOneShot(token.fd, token.cb);
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
				setCloExec(kqueueGlobalFd[0]);
				setCloExec(kqueueGlobalFd[1]);

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

		HANDLE[] handles;
		CallbackHelper[] handlesCbs;

		void unregisterHandle(HANDLE handle, CallbackHelper cb) {
			foreach(idx, h; handles)
				if(h is handle && handlesCbs[idx] is cb) {
					handles[idx] = handles[$-1];
					handles = handles[0 .. $-1].assumeSafeAppend;

					handlesCbs[idx] = handlesCbs[$-1];
					handlesCbs = handlesCbs[0 .. $-1].assumeSafeAppend;
				}
		}

		UnregisterToken addCallbackOnHandleReady(HANDLE handle, CallbackHelper cb) {
			handles ~= handle;
			handlesCbs ~= cb;

			return UnregisterToken(this, handle, cb);
		}

		// i think to terminate i just have to post the message at least once for every thread i know about, maybe a few more times for threads i don't know about.

		bool isWorker; // if it is a worker we wait on the iocp, if not we wait on msg

		RunOnceResult runOnce(Duration timeout = Duration.max) {
			scope(exit) eventLoopRound++;

			runLoopIterationDelegates(false);

			if(isWorker) {
				// this function is only supported on Windows Vista and up, so using this
				// means dropping support for XP.
				//GetQueuedCompletionStatusEx();
				assert(0); // FIXME
			} else {
				auto wto = 0;

				auto waitResult = MsgWaitForMultipleObjectsEx(
					cast(int) handles.length, handles.ptr,
					(wto == 0 ? INFINITE : wto), /* timeout */
					0x04FF, /* QS_ALLINPUT */
					0x0002 /* MWMO_ALERTABLE */ | 0x0004 /* MWMO_INPUTAVAILABLE */);

				enum WAIT_OBJECT_0 = 0;
				if(waitResult >= WAIT_OBJECT_0 && waitResult < handles.length + WAIT_OBJECT_0) {
					auto h = handles[waitResult - WAIT_OBJECT_0];
					auto cb = handlesCbs[waitResult - WAIT_OBJECT_0];
					cb.call();
				} else if(waitResult == handles.length + WAIT_OBJECT_0) {
					// message ready
					int count;
					MSG message;
					while(PeekMessage(&message, null, 0, 0, PM_NOREMOVE)) { // need to peek since sometimes MsgWaitForMultipleObjectsEx returns even though GetMessage can block. tbh i don't fully understand it but the docs say it is foreground activation
						auto ret = GetMessage(&message, null, 0, 0);
						if(ret == -1)
							throw new WindowsApiException("GetMessage", GetLastError());
						TranslateMessage(&message);
						DispatchMessage(&message);

						count++;
						if(count > 10)
							break; // take the opportunity to catch up on other events

						if(ret == 0) { // WM_QUIT
							exitApplication();
						}
					}
				} else if(waitResult == 0x000000C0L /* WAIT_IO_COMPLETION */) {
					SleepEx(0, true); // I call this to give it a chance to do stuff like async io
				} else if(waitResult == 258L /* WAIT_TIMEOUT */) {
					// timeout, should never happen since we aren't using it
				} else if(waitResult == 0xFFFFFFFF) {
						// failed
						throw new WindowsApiException("MsgWaitForMultipleObjectsEx", GetLastError());
				} else {
					// idk....
				}
			}

			runLoopIterationDelegates(true);

			return RunOnceResult(RunOnceResult.Possibilities.CarryOn);
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

		/+ // i call it explicitly at the thread exit instead, but worker threads aren't really supposed to exit generally speaking till process done anyway
		static ~this() {
			teardown();
		}
		+/

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

		RunOnceResult runOnce(Duration timeout = Duration.max) {
			scope(exit) eventLoopRound++;

			runLoopIterationDelegates(false);

			epoll_event[16] events;
			auto ret = epoll_wait(epollfd, events.ptr, cast(int) events.length, -1); // FIXME: timeout
			if(ret == -1) {
				import core.stdc.errno;
				if(errno == EINTR) {
					return RunOnceResult(RunOnceResult.Possibilities.Interrupted);
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

			runLoopIterationDelegates(true);

			return RunOnceResult(RunOnceResult.Possibilities.CarryOn);
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

			return RearmToken(true, this, fd, cb, EPOLLIN | EPOLLONESHOT);
		}

		/++
			Adds a one-off callback that you can optionally rearm when it happens.
		+/
		RearmToken addCallbackOnFdWritableOneShot(int fd, CallbackHelper cb) {
			epoll_event event;
			event.data.ptr = cast(void*) cb;
			event.events = EPOLLOUT | EPOLLONESHOT;
			if(epoll_ctl(epollfd, EPOLL_CTL_ADD, fd, &event) == -1)
				throw new ErrnoApiException("epoll_ctl", errno);

			return RearmToken(false, this, fd, cb, EPOLLOUT | EPOLLONESHOT);
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

/+
void main() {
	// FIXME: the offset doesn't seem to be done right
	auto file = new AsyncFile(FilePath("test.txt"), AsyncFile.OpenMode.writeWithTruncation);
	file.write("hello", 10).waitForCompletion();
}
+/

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

/++
	A class to help write a stream of binary data to some target.

	NOT YET FUNCTIONAL
+/
class WritableStream {
	/++

	+/
	this(size_t bufferSize) {
		this(new ubyte[](bufferSize));
	}

	/// ditto
	this(ubyte[] buffer) {
		this.buffer = buffer;
	}

	/++

	+/
	final void put(T)(T value, ByteOrder byteOrder = ByteOrder.irrelevant, string file = __FILE__, size_t line = __LINE__) {
		static if(T.sizeof == 8)
			ulong b;
		else static if(T.sizeof == 4)
			uint b;
		else static if(T.sizeof == 2)
			ushort b;
		else static if(T.sizeof == 1)
			ubyte b;
		else static assert(0, "unimplemented type, try using just the basic types");

		if(byteOrder == ByteOrder.irrelevant && T.sizeof > 1)
			throw new InvalidArgumentsException("byteOrder", "byte order must be specified for type " ~ T.stringof ~ " because it is bigger than one byte", "WritableStream.put", file, line);

		final switch(byteOrder) {
			case ByteOrder.irrelevant:
				writeOneByte(b);
			break;
			case ByteOrder.littleEndian:
				foreach(i; 0 .. T.sizeof) {
					writeOneByte(b & 0xff);
					b >>= 8;
				}
			break;
			case ByteOrder.bigEndian:
				int amount = T.sizeof * 8 - 8;
				foreach(i; 0 .. T.sizeof) {
					writeOneByte((b >> amount) & 0xff);
					amount -= 8;
				}
			break;
		}
	}

	/// ditto
	final void put(T : E[], E)(T value, ByteOrder elementByteOrder = ByteOrder.irrelevant, string file = __FILE__, size_t line = __LINE__) {
		foreach(item; value)
			put(item, elementByteOrder, file, line);
	}

	/++
		Performs a final flush() call, then marks the stream as closed, meaning no further data will be written to it.
	+/
	void close() {
		isClosed_ = true;
	}

	/++
		Writes what is currently in the buffer to the target and waits for the target to accept it.
		Please note: if you are subclassing this to go to a different target
	+/
	void flush() {}

	/++
		Returns true if either you closed it or if the receiving end closed their side, indicating they
		don't want any more data.
	+/
	bool isClosed() {
		return isClosed_;
	}

	// hasRoomInBuffer
	// canFlush
	// waitUntilCanFlush

	// flushImpl
	// markFinished / close - tells the other end you're done

	private final writeOneByte(ubyte value) {
		if(bufferPosition == buffer.length)
			flush();

		buffer[bufferPosition++] = value;
	}


	private {
		ubyte[] buffer;
		int bufferPosition;
		bool isClosed_;
	}
}

/++
	A stream can be used by just one task at a time, but one task can consume multiple streams.

	Streams may be populated by async sources (in which case they must be called from a fiber task),
	from a function generating the data on demand (including an input range), from memory, or from a synchronous file.

	A stream of heterogeneous types is compatible with input ranges.

	It reads binary data.
+/
version(HasThread) class ReadableStream {

	this() {

	}

	/++
		Gets data of the specified type `T` off the stream. The byte order of the T on the stream must be specified unless it is irrelevant (e.g. single byte entries).

		---
		// get an int out of a big endian stream
		int i = stream.get!int(ByteOrder.bigEndian);

		// get i bytes off the stream
		ubyte[] data = stream.get!(ubyte[])(i);
		---
	+/
	final T get(T)(ByteOrder byteOrder = ByteOrder.irrelevant, string file = __FILE__, size_t line = __LINE__) {
		if(byteOrder == ByteOrder.irrelevant && T.sizeof > 1)
			throw new InvalidArgumentsException("byteOrder", "byte order must be specified for type " ~ T.stringof ~ " because it is bigger than one byte", "ReadableStream.get", file, line);

		// FIXME: what if it is a struct?

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

	/// ditto
	final T get(T : E[], E)(size_t length, ByteOrder elementByteOrder = ByteOrder.irrelevant, string file = __FILE__, size_t line = __LINE__) {
		if(elementByteOrder == ByteOrder.irrelevant && E.sizeof > 1)
			throw new InvalidArgumentsException("elementByteOrder", "byte order must be specified for type " ~ E.stringof ~ " because it is bigger than one byte", "ReadableStream.get", file, line);

		// if the stream is closed before getting the length or the terminator, should we send partial stuff
		// or just throw?

		while(bufferedLength() < length * E.sizeof)
			waitForAdditionalData();

		T ret;

		ret.length = length;

		if(false && elementByteOrder == ByteOrder.irrelevant) {
			// ret[] =
			// FIXME: can prolly optimize
		} else {
			foreach(i; 0 .. length)
				ret[i] = get!E(elementByteOrder);
		}

		return ret;

	}

	/// ditto
	final T get(T : E[], E)(scope bool delegate(E e) isTerminatingSentinel, ByteOrder elementByteOrder = ByteOrder.irrelevant, string file = __FILE__, size_t line = __LINE__) {
		if(elementByteOrder == ByteOrder.irrelevant && E.sizeof > 1)
			throw new InvalidArgumentsException("elementByteOrder", "byte order must be specified for type " ~ E.stringof ~ " because it is bigger than one byte", "ReadableStream.get", file, line);

		T ret;

		do {
			try
				ret ~= get!E(elementByteOrder);
			catch(ArsdException!"is already closed" ae)
				return ret;
		} while(!isTerminatingSentinel(ret[$-1]));

		return ret[0 .. $-1]; // cut off the terminating sentinel
	}

	/++

	+/
	bool isClosed() {
		return isClosed_ && currentBuffer.length == 0 && leftoverBuffer.length == 0;
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
		if(isClosed_)
			throw ArsdException!("is already closed")();

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

// FIXME: do a stringstream too

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

		// ubyte[] c = stream.get!(ubyte[])(3);
		// int[] d = stream.get!(int[])(3);
	});

	fiber.call();
	assert(position == 1);
	stream.feedData([10, 0, 0, 0]);
	assert(position == 2);
	stream.feedData([33]);
	assert(position == 3);

	// stream.feedData([1,2,3]);
	// stream.feedData([1,2,3,4,1,2,3,4,1,2,3,4]);
}

/++
	UNSTABLE, NOT FULLY IMPLEMENTED. DO NOT USE YET.

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

	Please note that this does not currently and I have no plans as of this writing to add support for any kind of direct file descriptor passing. It always pipes them back to the parent for processing. If you don't want this, call the lower level functions yourself; the reason this class is here is to aid integration in the arsd.core event loop. Of course, I might change my mind on this.
+/
class ExternalProcess /*: AsyncOperationRequest*/ {

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
					ac.markComplete(status);
					activeChildren.remove(pid);
				}
			}
		}
	}

	// FIXME: config to pass through a shell or not

	/++
		This is the native version for Windows.
	+/
	version(Windows)
	this(FilePath program, string commandLine) {
		version(Posix) {
			assert(0, "not implemented command line to posix args yet");
		} else version(Windows) {
			this.program = program;
			this.commandLine = commandLine;
		}
		else throw new NotYetImplementedException();
	}

	/+
	this(string commandLine) {
		version(Posix) {
			assert(0, "not implemented command line to posix args yet");
		}
		else throw new NotYetImplementedException();
	}

	this(string[] args) {
		version(Posix) {
			this.program = FilePath(args[0]);
			this.args = args;
		}
		else throw new NotYetImplementedException();
	}
	+/

	/++
		This is the native version for Posix.
	+/
	version(Posix)
	this(FilePath program, string[] args) {
		version(Posix) {
			this.program = program;
			this.args = args;
		}
		else throw new NotYetImplementedException();
	}

	/++

	+/
	void start() {
		version(Posix) {
			getThisThreadEventLoop(); // ensure it is initialized

			int ret;

			int[2] stdinPipes;
			ret = pipe(stdinPipes);
			if(ret == -1)
				throw new ErrnoApiException("stdin pipe", errno);

			scope(failure) {
				close(stdinPipes[0]);
				close(stdinPipes[1]);
			}

			auto stdinFd = stdinPipes[1];

			int[2] stdoutPipes;
			ret = pipe(stdoutPipes);
			if(ret == -1)
				throw new ErrnoApiException("stdout pipe", errno);

			scope(failure) {
				close(stdoutPipes[0]);
				close(stdoutPipes[1]);
			}

			auto stdoutFd = stdoutPipes[0];

			int[2] stderrPipes;
			ret = pipe(stderrPipes);
			if(ret == -1)
				throw new ErrnoApiException("stderr pipe", errno);

			scope(failure) {
				close(stderrPipes[0]);
				close(stderrPipes[1]);
			}

			auto stderrFd = stderrPipes[0];


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

				makeNonBlocking(stdinFd);
				makeNonBlocking(stdoutFd);
				makeNonBlocking(stderrFd);

				_stdin = new AsyncFile(stdinFd);
				_stdout = new AsyncFile(stdoutFd);
				_stderr = new AsyncFile(stderrFd);
			}
		} else version(Windows) {
			WCharzBuffer program = this.program.path;
			WCharzBuffer cmdLine = this.commandLine;

			PROCESS_INFORMATION pi;
			STARTUPINFOW startupInfo;

			SECURITY_ATTRIBUTES saAttr;
			saAttr.nLength = SECURITY_ATTRIBUTES.sizeof;
			saAttr.bInheritHandle = true;
			saAttr.lpSecurityDescriptor = null;

			HANDLE inreadPipe;
			HANDLE inwritePipe;
			if(MyCreatePipeEx(&inreadPipe, &inwritePipe, &saAttr, 0, 0, FILE_FLAG_OVERLAPPED) == 0)
				throw new WindowsApiException("CreatePipe", GetLastError());
			if(!SetHandleInformation(inwritePipe, 1/*HANDLE_FLAG_INHERIT*/, 0))
				throw new WindowsApiException("SetHandleInformation", GetLastError());

			HANDLE outreadPipe;
			HANDLE outwritePipe;
			if(MyCreatePipeEx(&outreadPipe, &outwritePipe, &saAttr, 0, FILE_FLAG_OVERLAPPED, 0) == 0)
				throw new WindowsApiException("CreatePipe", GetLastError());
			if(!SetHandleInformation(outreadPipe, 1/*HANDLE_FLAG_INHERIT*/, 0))
				throw new WindowsApiException("SetHandleInformation", GetLastError());

			HANDLE errreadPipe;
			HANDLE errwritePipe;
			if(MyCreatePipeEx(&errreadPipe, &errwritePipe, &saAttr, 0, FILE_FLAG_OVERLAPPED, 0) == 0)
				throw new WindowsApiException("CreatePipe", GetLastError());
			if(!SetHandleInformation(errreadPipe, 1/*HANDLE_FLAG_INHERIT*/, 0))
				throw new WindowsApiException("SetHandleInformation", GetLastError());

			startupInfo.cb = startupInfo.sizeof;
			startupInfo.dwFlags = STARTF_USESTDHANDLES;
			startupInfo.hStdInput = inreadPipe;
			startupInfo.hStdOutput = outwritePipe;
			startupInfo.hStdError = errwritePipe;

			auto result = CreateProcessW(
				program.ptr,
				cmdLine.ptr,
				null, // process attributes
				null, // thread attributes
				true, // inherit handles; necessary for the std in/out/err ones to work
				0, // dwCreationFlags FIXME might be useful to change
				null, // environment, might be worth changing
				null, // current directory
				&startupInfo,
				&pi
			);

			if(!result)
				throw new WindowsApiException("CreateProcessW", GetLastError());

			_stdin = new AsyncFile(inwritePipe);
			_stdout = new AsyncFile(outreadPipe);
			_stderr = new AsyncFile(errreadPipe);

			Win32Enforce!CloseHandle(inreadPipe);
			Win32Enforce!CloseHandle(outwritePipe);
			Win32Enforce!CloseHandle(errwritePipe);

			Win32Enforce!CloseHandle(pi.hThread);

			handle = pi.hProcess;

			procRegistration = getThisThreadEventLoop.addCallbackOnHandleReady(handle, new CallbackHelper(&almostComplete));
		}
	}

	version(Windows) {
		private HANDLE handle;
		private FilePath program;
		private string commandLine;
		private ICoreEventLoop.UnregisterToken procRegistration;

		private final void almostComplete() {
			// GetProcessTimes lol
			Win32Enforce!GetExitCodeProcess(handle, cast(uint*) &_status);

			markComplete(_status);

			procRegistration.unregister();
			CloseHandle(handle);
			this.completed = true;
		}
	} else version(Posix) {
		import core.sys.posix.unistd;
		import core.sys.posix.fcntl;

		private pid_t pid = -1;

		public void delegate() beforeExec;

		private FilePath program;
		private string[] args;
	}

	private final void markComplete(int status) {
		completed = true;
		_status = status;

		if(oncomplete)
			oncomplete(this);
	}


	private AsyncFile _stdin;
	private AsyncFile _stdout;
	private AsyncFile _stderr;

	/++

	+/
	AsyncFile stdin() {
		return _stdin;
	}
	/// ditto
	AsyncFile stdout() {
		return _stdout;
	}
	/// ditto
	AsyncFile stderr() {
		return _stderr;
	}

	/++
	+/
	void waitForCompletion() {
		getThisThreadEventLoop().run(&this.isComplete);
	}

	/++
	+/
	bool isComplete() {
		return completed;
	}

	private bool completed;
	private int _status = int.min;

	/++
	+/
	int status() {
		return _status;
	}

	// void delegate(int code) onTermination;

	void delegate(ExternalProcess) oncomplete;

	// pty?
}

// FIXME: comment this out
/+
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

	proc.writeToStdin("hello!");
	proc.writeToStdin(null); // closes the pipe

	proc.waitForCompletion();

	assert(proc.status == 0);

	assert(c == 2);

	// writeln("here");
}
+/

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
	================
	LOGGER FRAMEWORK
	================
+/
/++
	DO NOT USE THIS YET IT IS NOT FUNCTIONAL NOR STABLE


	The arsd.core logger works differently than many in that it works as a ring buffer of objects that are consumed (or missed; buffer overruns are possible) by a different thread instead of strings written to some file.

	A library (or an application) defines a log source. They write to this source.

	Applications then define log listeners, zero or more, which reads from various sources and does something with them.

	Log calls, in this sense, are quite similar to asynchronous events that can be subscribed to by event handlers. The difference is events are generally not dropped - they might coalesce but are usually not just plain dropped in a buffer overrun - whereas logs can be. If the log consumer can't keep up, the details are just lost. The log producer will not wait for the consumer to catch up.


	An application can also set a default subscriber which applies to all log objects throughout.

	All log message objects must be capable of being converted to strings and to json.

	Ad-hoc messages can be done with interpolated sequences.

	Messages automatically get a timestamp. They can also have file/line and maybe even a call stack.

	Examples:
	---
		auto logger = new shared LoggerOf!GenericEmbeddableInterpolatedSequence;

		mylogger.info(i"$this heartbeat");
	---

	History:
		Added May 27, 2024

		Not actually implemented until February 6, 2025, when it changed from mixin template to class.
+/
class LoggerOf(T, size_t bufferSize = 16) {
	private LoggedMessage!T[bufferSize] ring;
	private ulong writeBufferPosition;

	import core.sync.mutex;
	import core.sync.condition;

	private Mutex mutex;
	private Condition condition;
	private bool active;
	private int listenerCount;

	this() shared {
		mutex = new shared Mutex(cast(LoggerOf) this);
		condition = new shared Condition(mutex);
		active = true;
	}

	/++
		Closes the log channel and waits for all listeners to finish pending work before returning.

		Once the logger is closed, it cannot be used again.

		You should close any logger you attached listeners to before returning from `main()`.
	+/
	void close() shared {
		synchronized(this) {
			active = false;
			condition.notifyAll();

			while(listenerCount > 0) {
				condition.wait();
			}
		}
	}

	/++

		Examples:

		---
		// to write all messages to the console
		logger.addListener((message, missedMessageCount) {
			writeln(message);
		});
		---

		---
		// to only write warnings and errors
		logger.addListener((message, missedMessageCount) {
			if(message.level >= LogLevel.warn)
				writeln(message);
		});
		---

		---
		// to ignore messages from arsd.core
		logger.addListener((message, missedMessageCount) {
			if(message.sourceLocation.moduleName != "arsd.core")
				writeln(message);
		});
		---
	+/
	LogListenerController addListener(void delegate(LoggedMessage!T message, int missedMessages) dg) shared {
		static class Listener : Thread, LogListenerController {
			shared LoggerOf logger;
			ulong readBufferPosition;
			void delegate(LoggedMessage!T, int) dg;

			bool connected;

			import core.sync.event;
			Event event;

			this(shared LoggerOf logger, void delegate(LoggedMessage!T msg, int) dg) {
				this.dg = dg;
				this.logger = logger;
				this.connected = true;
				this.isDaemon = true;

				auto us = cast(LoggerOf) logger;
				synchronized(logger)
					us.listenerCount++;

				event.initialize(true, false);
				super(&run);
			}

			void disconnect() {
				this.connected = false;
			}

			void run() {
				auto us = cast(LoggerOf) logger;
				/+
				// can't do this due to https://github.com/ldc-developers/ldc/issues/4837
				// so doing the try/catch below and putting this under it
				scope(exit) {
					synchronized(logger) {
						us.listenerCount--;
						logger.condition.notifyAll();
					}
					// mark us as complete for other listeners waiting as well
					event.set();
				}
				+/

				try {

					LoggedMessage!T[bufferSize] buffer;
					do {
						int missedMessages = 0;
						long n;
						synchronized(logger) {
							while(logger.active && connected && logger.writeBufferPosition <= readBufferPosition) {
								logger.condition.wait();
							}

							n = us.writeBufferPosition - readBufferPosition;
							if(n > bufferSize) {
								// we missed something...
								missedMessages = cast(int) (n - bufferSize);
								readBufferPosition = us.writeBufferPosition - bufferSize;
								n = bufferSize;
							}
							auto startPos = readBufferPosition % bufferSize;
							auto endPos = us.writeBufferPosition % bufferSize;
							if(endPos > startPos) {
								buffer[0 .. cast(size_t) n] = us.ring[cast(size_t) startPos .. cast(size_t) endPos];
							} else {
								auto ourSplit = us.ring.length - startPos;
								buffer[0 .. cast(size_t) ourSplit] = us.ring[cast(size_t) startPos .. $];
								buffer[cast(size_t) ourSplit .. cast(size_t) (ourSplit + endPos)] = us.ring[0 .. cast(size_t) endPos];
							}
							readBufferPosition = us.writeBufferPosition;
						}
						foreach(item; buffer[0 .. cast(size_t) n]) {
							if(!connected)
								break;
							dg(item, missedMessages);
							missedMessages = 0;
						}
					} while(logger.active && connected);

				} catch(Throwable t) {
					// i guess i could try to log the exception for other listeners to pick up...

				}

				synchronized(logger) {
					us.listenerCount--;
					logger.condition.notifyAll();
				}
				// mark us as complete for other listeners waiting as well
				event.set();

			}

			void waitForCompletion() {
				event.wait();
			}
		}

		auto listener = new Listener(this, dg);
		listener.start();

		return listener;
	}

	void log(LoggedMessage!T message) shared {
		synchronized(this) {
			auto unshared = cast() this;
			unshared.ring[writeBufferPosition % bufferSize] = message;
			unshared.writeBufferPosition += 1;

			// import std.stdio; std.stdio.writeln(message);
			condition.notifyAll();
		}
	}

	/// ditto
	void log(LogLevel level, T message, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
		import core.stdc.time;
		log(LoggedMessage!T(level, sourceLocation, SimplifiedUtcTimestamp.fromUnixTime(time(null)), Thread.getThis(), message));
	}

	/// ditto
	void info(T message, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
		log(LogLevel.info, message, sourceLocation);
	}
	/// ditto
	void trace(T message, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
		log(LogLevel.trace, message, sourceLocation);
	}
	/// ditto
	void warn(T message, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
		log(LogLevel.warn, message, sourceLocation);
	}
	/// ditto
	void error(T message, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
		log(LogLevel.error, message, sourceLocation);
	}

	static if(is(T == GenericEmbeddableInterpolatedSequence)) {
		pragma(inline, true)
		final void info(T...)(InterpolationHeader header, T message, InterpolationFooter footer, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
			log(LogLevel.info, GenericEmbeddableInterpolatedSequence(header, message, footer), sourceLocation);
		}
		pragma(inline, true)
		final void trace(T...)(InterpolationHeader header, T message, InterpolationFooter footer, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
			log(LogLevel.trace, GenericEmbeddableInterpolatedSequence(header, message, footer), sourceLocation);
		}
		pragma(inline, true)
		final void warn(T...)(InterpolationHeader header, T message, InterpolationFooter footer, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
			log(LogLevel.warn, GenericEmbeddableInterpolatedSequence(header, message, footer), sourceLocation);
		}
		pragma(inline, true)
		final void error(T...)(InterpolationHeader header, T message, InterpolationFooter footer, SourceLocation sourceLocation = SourceLocation(__MODULE__, __LINE__)) shared {
			log(LogLevel.error, GenericEmbeddableInterpolatedSequence(header, message, footer), sourceLocation);
		}
	}
}

/// ditto
interface LogListenerController {
	/++
		Disconnects from the log producer as soon as possible, possibly leaving messages
		behind in the log buffer. Once disconnected, the log listener will terminate
		asynchronously and cannot be reused. Use [waitForCompletion] to block your thread
		until the termination is complete.
	+/
	void disconnect();

	/++
		Waits for the listener to finish its pending work and terminate. You should call
		[disconnect] first to make it start to exit.
	+/
	void waitForCompletion();
}

/// ditto
struct SourceLocation {
	string moduleName;
	size_t line;
}

/// ditto
struct LoggedMessage(T) {
	LogLevel level;
	SourceLocation sourceLocation;
	SimplifiedUtcTimestamp timestamp;
	Thread originatingThread;
	T message;

	// process id can be assumed by the listener,
	// since it is always the same; logs are sent and received by the same process.

	string toString() {
		string ret;

		ret ~= sourceLocation.moduleName;
		ret ~= ":";
		ret ~= toStringInternal(sourceLocation.line);
		ret ~= " ";
		if(originatingThread) {
			char[16] buffer;
			ret ~= originatingThread.name.length ? originatingThread.name : intToString(cast(long) originatingThread.id, buffer, IntToStringArgs().withRadix(16));
		}
		ret ~= "[";
		ret ~= toStringInternal(level);
		ret ~= "] ";
		ret ~= timestamp.toString();
		ret ~= " ";
		ret ~= message.toString();

		return ret;
	}
	// callstack?
}

/// ditto
enum LogLevel {
	trace,
	info,
	warn,
	error,
}

private shared(LoggerOf!GenericEmbeddableInterpolatedSequence) _commonLogger;
shared(LoggerOf!GenericEmbeddableInterpolatedSequence) logger() {
	if(_commonLogger is null) {
		synchronized {
			if(_commonLogger is null)
				_commonLogger = new shared LoggerOf!GenericEmbeddableInterpolatedSequence;
		}
	}

	return _commonLogger;
}

/++
	Makes note of an exception you catch and otherwise ignore.

	History:
		Added April 17, 2025
+/
void logSwallowedException(Exception e) {
	logger.error(InterpolationHeader(), e.toString(), InterpolationFooter());
}

/+
// using this requires a newish compiler so we just uncomment when necessary
unittest {
	void main() {
		auto logger = logger;// new shared LoggerOf!GenericEmbeddableInterpolatedSequence;
		LogListenerController l1;
		l1 = logger.addListener((msg, missedCount) {
			if(missedCount)
				writeln("T1: missed ", missedCount);
			writeln("T1:" ~msg.toString());
			//Thread.sleep(500.msecs);
			//l1.disconnect();
				Thread.sleep(1.msecs);
		});
		foreach(n; 0 .. 200) {
			logger.info(i"hello world $n");
			if(n % 6 == 0)
				Thread.sleep(1.msecs);
		}

		logger.addListener((msg, missedCount) {
			if(missedCount) writeln("T2 missed ", missedCount);
			writeln("T2:" ~msg.toString());
		});

		Thread.sleep(500.msecs);
		l1.disconnect;
		l1.waitForCompletion;

		logger.close();
	}
	//main;
}
+/

/+
	=====================
	TRANSLATION FRAMEWORK
	=====================
+/

/++
	Represents a translatable string.


	This depends on interpolated expression sequences to be ergonomic to use and in most cases, a function that uses this should take it as `tstring name...`; a typesafe variadic (this is also why it is a class rather than a struct - D only supports this particular feature on classes).

	You can use `null` as a tstring. You can also construct it with UFCS: `i"foo".tstring`.

	The actual translation engine should be set on the application level.

	It is possible to get all translatable string templates compiled into the application at runtime.

	History:
		Added June 23, 2024
+/
class tstring {
	private GenericEmbeddableInterpolatedSequence geis;

	/++
		For a case where there is no plural specialization.
	+/
	this(Args...)(InterpolationHeader hdr, Args args, InterpolationFooter ftr) {
		geis = GenericEmbeddableInterpolatedSequence(hdr, args, ftr);
		tstringTemplateProcessor!(Args.length, Args) tp;
	}

	/+
	/++
		When here is a plural specialization this passes the default one.
	+/
	this(SArgs..., Pargs...)(
		InterpolationHeader shdr, SArgs singularArgs, InterpolationFooter sftr,
		InterpolationHeader phdr, PArgs pluralArgs, InterpolationFooter pftr
	)
	{
		geis = GenericEmbeddableInterpolatedSequence(shdr, singularArgs, sftr);
		//geis = GenericEmbeddableInterpolatedSequence(phdr, pluralArgs, pftr);

		tstringTemplateProcessor!(Args.length, Args) tp;
	}
	+/

	final override string toString() {
		if(this is null)
			return null;
		if(translationEngine !is null)
			return translationEngine.translate(geis);
		else
			return geis.toString();
	}

	static tstring opCall(Args...)(InterpolationHeader hdr, Args args, InterpolationFooter ftr) {
		return new tstring(hdr, args, ftr);
	}

	/+ +++ +/

	private static shared(TranslationEngine) translationEngine_ = null;

	static shared(TranslationEngine) translationEngine() {
		return translationEngine_;
	}

	static void translationEngine(shared TranslationEngine e) {
		translationEngine_ = e;
		if(e !is null) {
			auto item = first;
			while(item) {
				e.handleTemplate(*item);
				item = item.next;
			}
		}
	}

	public struct TranslatableElement {
		string templ;
		string pluralTempl;

		TranslatableElement* next;
	}

	static __gshared TranslatableElement* first;

	// FIXME: the template should be identified to the engine somehow

	private static enum templateStringFor(Args...) = () {
		int count;
		string templ;
		foreach(arg; Args) {
			static if(is(arg == InterpolatedLiteral!str, string str))
				templ ~= str;
			else static if(is(arg == InterpolatedExpression!code, string code))
				templ ~= "{" ~ cast(char)(++count + '0') ~ "}";
		}
		return templ;
	}();

	// this is here to inject static ctors so we can build up a runtime list from ct data
	private static struct tstringTemplateProcessor(size_t pluralBegins, Args...) {
		static __gshared TranslatableElement e = TranslatableElement(
			templateStringFor!(Args[0 .. pluralBegins]),
			templateStringFor!(Args[pluralBegins .. $]),
			null /* next, filled in by the static ctor below */);

		@standalone @system
		shared static this() {
			e.next = first;
			first = &e;
		}
	}
}

/// ditto
class TranslationEngine {
	string translate(GenericEmbeddableInterpolatedSequence geis) shared {
		return geis.toString();
	}

	/++
		If the translation engine has been set early in the module
		construction process (which it should be!)
	+/
	void handleTemplate(tstring.TranslatableElement t) shared {
	}
}

private static template WillFitInGeis(Args...) {
	static int lengthRequired() {
		int place;
		foreach(arg; Args) {
			static if(is(arg == InterpolatedLiteral!str, string str)) {
				if(place & 1) // can't put string in the data slot
					place++;
				place++;
			} else static if(is(arg == InterpolationHeader) || is(arg == InterpolationFooter) || is(arg == InterpolatedExpression!code, string code)) {
				// no storage required
			} else {
				if((place & 1) == 0) // can't put data in the string slot
					place++;
				place++;
			}
		}

		if(place & 1)
			place++;
		return place / 2;
	}

	enum WillFitInGeis = lengthRequired() <= GenericEmbeddableInterpolatedSequence.seq.length;
}


/+
	For making an array of istrings basically; it moves their CT magic to RT dynamic type.
+/
struct GenericEmbeddableInterpolatedSequence {
	static struct Element {
		string str; // these are pointers to string literals every time
		LimitedVariant lv;
	}

	Element[8] seq;

	this(Args...)(InterpolationHeader, Args args, InterpolationFooter) {
		int place;
		bool stringUsedInPlace;
		bool overflowed;

		static assert(WillFitInGeis!(Args), "Your interpolated elements will not fit in the generic buffer.");

		foreach(arg; args) {
			static if(is(typeof(arg) == InterpolatedLiteral!str, string str)) {
				if(stringUsedInPlace) {
					place++;
					stringUsedInPlace = false;
				}

				if(place == seq.length) {
					overflowed = true;
					break;
				}
				seq[place].str = str;
				stringUsedInPlace = true;
			} else static if(is(typeof(arg) == InterpolationHeader) || is(typeof(arg) == InterpolationFooter)) {
				static assert(0, "Cannot embed interpolated sequences");
			} else static if(is(typeof(arg) == InterpolatedExpression!code, string code)) {
				// irrelevant
			} else {
				if(place == seq.length) {
					overflowed = true;
					break;
				}
				seq[place].lv = LimitedVariant(arg);
				place++;
				stringUsedInPlace = false;
			}
		}
	}

	string toString() {
		string s;
		foreach(item; seq) {
			if(item.str !is null)
				s ~= item.str;
			if(!item.lv.containsNull())
				s ~= item.lv.toString();
		}
		return s;
	}
}

/+
	=================
	STDIO REPLACEMENT
	=================
+/

private void appendToBuffer(ref char[] buffer, ref int pos, scope const(char)[] what) {
	auto required = pos + what.length;
	if(buffer.length < required)
		buffer.length = required;
	buffer[pos .. pos + what.length] = what[];
	pos += what.length;
}

private void appendToBuffer(ref char[] buffer, ref int pos, long what) {
	if(buffer.length < pos + 32)
		buffer.length = pos + 32;
	auto sliced = intToString(what, buffer[pos .. $]);
	pos += sliced.length;
}

private void appendToBuffer(ref char[] buffer, ref int pos, double what) {
	if(buffer.length < pos + 32)
		buffer.length = pos + 32;
	auto sliced = floatToString(what, buffer[pos .. $]);
	pos += sliced.length;
}


/++
	You can use `mixin(dumpParams);` to put out a debug print of your current function call w/ params.
+/
enum string dumpParams = q{
	{
		import arsd.core;
		arsd.core.dumpParamsImpl(__FUNCTION__, __traits(parameters));
	}
};

/// Don't call this directly, use `mixin(dumpParams);` instead
public void dumpParamsImpl(T...)(string func, T args) {
	writeGuts(func ~ "(", ")\n", ", ", false, &actuallyWriteToStdout, args);
}

/++
	A `writeln` that actually works, at least for some basic types.

	It works correctly on Windows, using the correct functions to write unicode to the console.  even allocating a console if needed. If the output has been redirected to a file or pipe, it writes UTF-8.

	This always does text. See also WritableStream and WritableTextStream when they are implemented.
+/
void writeln(T...)(T t) {
	writeGuts(null, "\n", null, false, &actuallyWriteToStdout, t);
}

///
void writelnStderr(T...)(T t) {
	writeGuts(null, "\n", null, false, &actuallyWriteToStderr, t);
}

/++

+/
package(arsd) string enumNameForValue(T)(T t) {
	switch(t) {
		foreach(memberName; __traits(allMembers, T)) {
			case __traits(getMember, T, memberName):
				return memberName;
		}
		default:
			return "<unknown>";
	}
}

/+
	Purposes:
		* debugging
		* writing
		* converting single value to string?
+/
private string writeGuts(T...)(string prefix, string suffix, string argSeparator, bool printInterpolatedCode, string function(scope char[] result) writer, T t) {
	char[256] bufferBacking;
	char[] buffer = bufferBacking[];
	int pos;

	if(prefix.length)
		appendToBuffer(buffer, pos, prefix);

	foreach(i, arg; t) {
		static if(i)
		if(argSeparator.length)
			appendToBuffer(buffer, pos, argSeparator);

		static if(is(typeof(arg) Base == enum)) {
			appendToBuffer(buffer, pos, typeof(arg).stringof);
			appendToBuffer(buffer, pos, ".");
			appendToBuffer(buffer, pos, enumNameForValue(arg));
			appendToBuffer(buffer, pos, "(");
			appendToBuffer(buffer, pos, cast(Base) arg);
			appendToBuffer(buffer, pos, ")");
		} else static if(is(typeof(arg) : const char[])) {
			appendToBuffer(buffer, pos, arg);
		} else static if(is(typeof(arg) : stringz)) {
			appendToBuffer(buffer, pos, arg.borrow);
		} else static if(is(typeof(arg) : long)) {
			appendToBuffer(buffer, pos, arg);
		} else static if(is(typeof(arg) : double)) {
			appendToBuffer(buffer, pos, arg);
		} else static if(is(typeof(arg) == InterpolatedExpression!code, string code)) {
			if(printInterpolatedCode) {
				appendToBuffer(buffer, pos, code);
				appendToBuffer(buffer, pos, " = ");
			}
		} else static if(is(typeof(arg.toString()) : const char[])) {
			appendToBuffer(buffer, pos, arg.toString());
		} else static if(is(typeof(arg) A == struct)) {
			appendToBuffer(buffer, pos, A.stringof);
			appendToBuffer(buffer, pos, "(");
			foreach(idx, item; arg.tupleof) {
				if(idx)
					appendToBuffer(buffer, pos, ", ");
				appendToBuffer(buffer, pos, __traits(identifier, arg.tupleof[idx]));
				appendToBuffer(buffer, pos, ": ");
				appendToBuffer(buffer, pos, item);
			}
			appendToBuffer(buffer, pos, ")");
		} else static if(is(typeof(arg) == E[], E)) {
			appendToBuffer(buffer, pos, "[");
			foreach(idx, item; arg) {
				if(idx)
					appendToBuffer(buffer, pos, ", ");
				appendToBuffer(buffer, pos, item);
			}
			appendToBuffer(buffer, pos, "]");
		} else {
			appendToBuffer(buffer, pos, "<" ~ typeof(arg).stringof ~ ">");
		}
	}

	if(suffix.length)
		appendToBuffer(buffer, pos, suffix);

	return writer(buffer[0 .. pos]);
}

debug void dump(T...)(T t, string file = __FILE__, size_t line = __LINE__) {
	string separator;
	static if(T.length && is(T[0] == InterpolationHeader))
		separator = null;
	else
		separator = "; ";

	writeGuts(file ~ ":" ~ toStringInternal(line) ~ ": ", "\n", separator, true, &actuallyWriteToStdout, t);
}

private string makeString(scope char[] buffer) @safe {
	return buffer.idup;
}
private string actuallyWriteToStdout(scope char[] buffer) @safe {
	return actuallyWriteToStdHandle(1, buffer);
}
private string actuallyWriteToStderr(scope char[] buffer) @safe {
	return actuallyWriteToStdHandle(2, buffer);
}
private string actuallyWriteToStdHandle(int whichOne, scope char[] buffer) @trusted {
	version(UseStdioWriteln)
	{
		import std.stdio;
		(whichOne == 1 ? stdout : stderr).writeln(buffer);
	}
	else version(Windows) {
		import core.sys.windows.wincon;

		auto h = whichOne == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE;

		auto hStdOut = GetStdHandle(h);
		if(hStdOut == null || hStdOut == INVALID_HANDLE_VALUE) {
			AllocConsole();
			hStdOut = GetStdHandle(h);
		}

		if(GetFileType(hStdOut) == FILE_TYPE_CHAR) {
			wchar[256] wbuffer;
			auto toWrite = makeWindowsString(buffer, wbuffer, WindowsStringConversionFlags.convertNewLines);

			DWORD written;
			WriteConsoleW(hStdOut, toWrite.ptr, cast(DWORD) toWrite.length, &written, null);
		} else {
			DWORD written;
			WriteFile(hStdOut, buffer.ptr, cast(DWORD) buffer.length, &written, null);
		}
	} else {
		import unix = core.sys.posix.unistd;
		unix.write(whichOne, buffer.ptr, buffer.length);
	}

	return null;
}

/+

STDIO

	/++
		Please note using this will create a compile-time dependency on [arsd.terminal]



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
			* sendfile on linux, TransmitFile on Windows
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
static assert(0);
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

package(arsd) version(Windows) extern(Windows) {
	BOOL CancelIoEx(HANDLE, LPOVERLAPPED);

	struct WSABUF {
		ULONG len;
		ubyte* buf;
	}
	alias LPWSABUF = WSABUF*;

	// https://learn.microsoft.com/en-us/windows/win32/api/winsock2/ns-winsock2-wsaoverlapped
	// "The WSAOVERLAPPED structure is compatible with the Windows OVERLAPPED structure."
	// so ima lie here in the bindings.

	int WSASend(SOCKET, LPWSABUF, DWORD, LPDWORD, DWORD, LPOVERLAPPED, LPOVERLAPPED_COMPLETION_ROUTINE);
	int WSASendTo(SOCKET, LPWSABUF, DWORD, LPDWORD, DWORD, const sockaddr*, int, LPOVERLAPPED, LPOVERLAPPED_COMPLETION_ROUTINE);

	int WSARecv(SOCKET, LPWSABUF, DWORD, LPDWORD, LPDWORD, LPOVERLAPPED, LPOVERLAPPED_COMPLETION_ROUTINE);
	int WSARecvFrom(SOCKET, LPWSABUF, DWORD, LPDWORD, LPDWORD, sockaddr*, LPINT, LPOVERLAPPED, LPOVERLAPPED_COMPLETION_ROUTINE);
}

package(arsd) version(UseCocoa) {

/* Copy/paste chunk from Jacob Carlborg { */
// from https://raw.githubusercontent.com/jacob-carlborg/druntime/550edd0a64f0eb2c4f35d3ec3d88e26b40ac779e/src/core/stdc/clang_block.d
// with comments stripped (see docs in the original link), code reformatted, and some names changed to avoid potential conflicts

// note these should always be passed by pointer!

import core.stdc.config;
struct ObjCBlock(R = void, Params...) {
private:
	alias extern(C) R function(ObjCBlock*, Params) Invoke;

	void* isa;
	int flags;
	int reserved = 0;
	Invoke invoke;
	Descriptor* descriptor;

	// Imported variables go here
	R delegate(Params) dg;

	this(void* isa, int flags, Invoke invoke, R delegate(Params) dg) {
		this.isa = isa;
		this.flags = flags;
		this.invoke = invoke;
		this.descriptor = &.objcblock_descriptor;

		// FIXME: is this needed or not? it could be held by the OS and not be visible to GC i think
		// import core.memory; GC.addRoot(dg.ptr);

		this.dg = dg;
	}
}
ObjCBlock!(R, Params) blockOnStack(R, Params...)(R delegate(Params) dg) {
	static if (Params.length == 0)
		enum flags = 0x50000000;
	else
		enum flags = 0x40000000;

	return ObjCBlock!(R, Params)(&_NSConcreteStackBlock, flags, &objcblock_invoke!(R, Params), dg);
}
ObjCBlock!(R, Params)* block(R, Params...)(R delegate(Params) dg) {
	static if (Params.length == 0)
		enum flags = 0x50000000;
	else
		enum flags = 0x40000000;

	return new ObjCBlock!(R, Params)(&_NSConcreteStackBlock, flags, &objcblock_invoke!(R, Params), dg);
}

private struct Descriptor {
    c_ulong reserved;
    c_ulong size;
    const(char)* signature;
}
private extern(C) extern __gshared void*[32] _NSConcreteStackBlock;
private __gshared auto objcblock_descriptor = Descriptor(0, ObjCBlock!().sizeof);
private extern(C) R objcblock_invoke(R, Args...)(ObjCBlock!(R, Args)* block, Args args) {
    return block.dg(args);
}


/* End copy/paste chunk from Jacob Carlborg } */


/+
To let Cocoa know that you intend to use multiple threads, all you have to do is spawn a single thread using the NSThread class and let that thread immediately exit. Your thread entry point need not do anything. Just the act of spawning a thread using NSThread is enough to ensure that the locks needed by the Cocoa frameworks are put in place.

If you are not sure if Cocoa thinks your application is multithreaded or not, you can use the isMultiThreaded method of NSThread to check.
+/


	struct DeifiedNSString {
		char[16] sso;
		const(char)[] str;

		this(NSString s) {
			auto len = s.length;
			if(len <= sso.length / 4)
				str = sso[];
			else
				str = new char[](len * 4);

			NSUInteger count;
			NSRange leftover;
			auto ret = s.getBytes(cast(char*) str.ptr, str.length, &count, NSStringEncoding.NSUTF8StringEncoding, NSStringEncodingConversionOptions.none, NSRange(0, len), &leftover);
			if(ret)
				str = str[0 .. count];
			else
				throw new Exception("uh oh");
		}
	}

	extern (Objective-C) {
		import core.attribute; // : selector, optional;

		alias NSUInteger = size_t;
		alias NSInteger = ptrdiff_t;
		alias unichar = wchar;
		struct SEL_;
		alias SEL_* SEL;
		// this is called plain `id` in objective C but i fear mistakes with that in D. like sure it is a type instead of a variable like most things called id but i still think it is weird. i might change my mind later.
		alias void* NSid; // FIXME? the docs say this is a pointer to an instance of a class, but that is not necessary a child of NSObject

		extern class NSObject {
			static NSObject alloc() @selector("alloc");
			NSObject init() @selector("init");

			void retain() @selector("retain");
			void release() @selector("release");
			void autorelease() @selector("autorelease");

			void performSelectorOnMainThread(SEL aSelector, NSid arg, bool waitUntilDone) @selector("performSelectorOnMainThread:withObject:waitUntilDone:");
		}

		// this is some kind of generic in objc...
		extern class NSArray : NSObject {
			static NSArray arrayWithObjects(NSid* objects, NSUInteger count) @selector("arrayWithObjects:count:");
		}

		extern class NSString : NSObject {
			override static NSString alloc() @selector("alloc");
			override NSString init() @selector("init");

			NSString initWithUTF8String(const scope char* str) @selector("initWithUTF8String:");

			NSString initWithBytes(
				const(ubyte)* bytes,
				NSUInteger length,
				NSStringEncoding encoding
			) @selector("initWithBytes:length:encoding:");

			unichar characterAtIndex(NSUInteger index) @selector("characterAtIndex:");
			NSUInteger length() @selector("length");
			const char* UTF8String() @selector("UTF8String");

			void getCharacters(wchar* buffer, NSRange range) @selector("getCharacters:range:");

			bool getBytes(void* buffer, NSUInteger maxBufferCount, NSUInteger* usedBufferCount, NSStringEncoding encoding, NSStringEncodingConversionOptions options, NSRange range, NSRange* leftover) @selector("getBytes:maxLength:usedLength:encoding:options:range:remainingRange:");

			CGSize sizeWithAttributes(NSDictionary attrs) @selector("sizeWithAttributes:");
		}

		// FIXME: it is a generic in objc with <KeyType, ObjectType>
		extern class NSDictionary : NSObject {
			static NSDictionary dictionaryWithObject(NSObject object, NSid key) @selector("dictionaryWithObject:forKey:");
			// static NSDictionary initWithObjects(NSArray objects, NSArray forKeys) @selector("initWithObjects:forKeys:");
		}

		alias NSAttributedStringKey = NSString;
		/* const */extern __gshared NSAttributedStringKey NSFontAttributeName;

		struct NSRange {
			NSUInteger loc;
			NSUInteger len;
		}

		enum NSStringEncodingConversionOptions : NSInteger {
			none = 0,
			NSAllowLossyEncodingConversion = 1,
			NSExternalRepresentationEncodingConversion = 2
		}

		enum NSEventType {
			idk

		}

		enum NSEventModifierFlags : NSUInteger {
			NSEventModifierFlagCapsLock = 1 << 16,
			NSEventModifierFlagShift = 1 << 17,
			NSEventModifierFlagControl = 1 << 18,
			NSEventModifierFlagOption = 1 << 19, // aka Alt
			NSEventModifierFlagCommand = 1 << 20, // aka super
			NSEventModifierFlagNumericPad = 1 << 21,
			NSEventModifierFlagHelp = 1 << 22,
			NSEventModifierFlagFunction = 1 << 23,
			NSEventModifierFlagDeviceIndependentFlagsMask = 0xffff0000UL
		}

		version(OSX)
		extern class NSEvent : NSObject {
			NSEventType type() @selector("type");

			NSPoint locationInWindow() @selector("locationInWindow");
			NSTimeInterval timestamp() @selector("timestamp");
			NSWindow window() @selector("window"); // note: nullable
			NSEventModifierFlags modifierFlags() @selector("modifierFlags");

			NSString characters() @selector("characters");
			NSString charactersIgnoringModifiers() @selector("charactersIgnoringModifiers");
			ushort keyCode() @selector("keyCode");
			ushort specialKey() @selector("specialKey");

			static NSUInteger pressedMouseButtons() @selector("pressedMouseButtons");
			NSPoint locationInWindow() @selector("locationInWindow"); // in screen coordinates
			static NSPoint mouseLocation() @selector("mouseLocation"); // in screen coordinates
			NSInteger buttonNumber() @selector("buttonNumber");

			CGFloat deltaX() @selector("deltaX");
			CGFloat deltaY() @selector("deltaY");
			CGFloat deltaZ() @selector("deltaZ");

			bool hasPreciseScrollingDeltas() @selector("hasPreciseScrollingDeltas");

			CGFloat scrollingDeltaX() @selector("scrollingDeltaX");
			CGFloat scrollingDeltaY() @selector("scrollingDeltaY");

			// @property(getter=isDirectionInvertedFromDevice, readonly) BOOL directionInvertedFromDevice;
		}

		extern /* final */ class NSTimer : NSObject { // the docs say don't subclass this, but making it final breaks the bridge
			override static NSTimer alloc() @selector("alloc");
			override NSTimer init() @selector("init");

			static NSTimer schedule(NSTimeInterval timeIntervalInSeconds, NSid target, SEL selector, NSid userInfo, bool repeats) @selector("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:");

			void fire() @selector("fire");
			void invalidate() @selector("invalidate");

			bool valid() @selector("isValid");
			// @property(copy) NSDate *fireDate;
			NSTimeInterval timeInterval() @selector("timeInterval");
			NSid userInfo() @selector("userInfo");

			NSTimeInterval tolerance() @selector("tolerance");
			NSTimeInterval tolerance(NSTimeInterval) @selector("setTolerance:");
		}

		alias NSTimeInterval = double;

		version(OSX)
		extern class NSResponder : NSObject {
			NSMenu menu() @selector("menu");
			void menu(NSMenu menu) @selector("setMenu:");

			void keyDown(NSEvent event) @selector("keyDown:");
			void keyUp(NSEvent event) @selector("keyUp:");

			// - (void)interpretKeyEvents:(NSArray<NSEvent *> *)eventArray;

			void mouseDown(NSEvent event) @selector("mouseDown:");
			void mouseDragged(NSEvent event) @selector("mouseDragged:");
			void mouseUp(NSEvent event) @selector("mouseUp:");
			void mouseMoved(NSEvent event) @selector("mouseMoved:");
			void mouseEntered(NSEvent event) @selector("mouseEntered:");
			void mouseExited(NSEvent event) @selector("mouseExited:");

			void rightMouseDown(NSEvent event) @selector("rightMouseDown:");
			void rightMouseDragged(NSEvent event) @selector("rightMouseDragged:");
			void rightMouseUp(NSEvent event) @selector("rightMouseUp:");

			void otherMouseDown(NSEvent event) @selector("otherMouseDown:");
			void otherMouseDragged(NSEvent event) @selector("otherMouseDragged:");
			void otherMouseUp(NSEvent event) @selector("otherMouseUp:");

			void scrollWheel(NSEvent event) @selector("scrollWheel:");

			// touch events should also be here btw among others
		}

		version(OSX)
		extern class NSApplication : NSResponder {
			static NSApplication shared_() @selector("sharedApplication");

			NSApplicationDelegate delegate_() @selector("delegate");
			void delegate_(NSApplicationDelegate) @selector("setDelegate:");

			bool setActivationPolicy(NSApplicationActivationPolicy activationPolicy) @selector("setActivationPolicy:");

			void activateIgnoringOtherApps(bool flag) @selector("activateIgnoringOtherApps:");

			@property NSMenu mainMenu() @selector("mainMenu");
			@property NSMenu mainMenu(NSMenu) @selector("setMainMenu:");

			void run() @selector("run");

			void stop(NSid sender) @selector("stop:");

			void finishLaunching() @selector("finishLaunching");

			void terminate(void*) @selector("terminate:");

			void sendEvent(NSEvent event) @selector("sendEvent:");
			NSEvent nextEventMatchingMask(
				NSEventMask mask,
				NSDate untilDate,
				NSRunLoopMode inMode,
				bool dequeue
			) @selector("nextEventMatchingMask:untilDate:inMode:dequeue:");
		}

		enum NSEventMask : ulong {
			NSEventMaskAny = ulong.max
		}

		version(OSX)
		extern class NSRunLoop : NSObject {
			static @property NSRunLoop currentRunLoop() @selector("currentRunLoop");
			static @property NSRunLoop mainRunLoop() @selector("mainRunLoop");
			bool runMode(NSRunLoopMode mode, NSDate beforeDate) @selector("runMode:beforeDate:");
		}

		alias NSRunLoopMode = NSString;

		extern __gshared NSRunLoopMode NSDefaultRunLoopMode;

		version(OSX)
		extern class NSDate : NSObject {
			static @property NSDate distantFuture() @selector("distantFuture");
			static @property NSDate distantPast() @selector("distantPast");
			static @property NSDate now() @selector("now");

		}

		version(OSX)
		extern interface NSApplicationDelegate {
			void applicationWillFinishLaunching(NSNotification notification) @selector("applicationWillFinishLaunching:");
			void applicationDidFinishLaunching(NSNotification notification) @selector("applicationDidFinishLaunching:");
			bool applicationShouldTerminateAfterLastWindowClosed(NSNotification notification) @selector("applicationShouldTerminateAfterLastWindowClosed:");
		}

		extern class NSNotification : NSObject {
			@property NSid object() @selector("object");
		}

		enum NSApplicationActivationPolicy : ptrdiff_t {
			/* The application is an ordinary app that appears in the Dock and may have a user interface.  This is the default for bundled apps, unless overridden in the Info.plist. */
			regular,

			/* The application does not appear in the Dock and does not have a menu bar, but it may be activated programmatically or by clicking on one of its windows.  This corresponds to LSUIElement=1 in the Info.plist. */
			accessory,

			/* The application does not appear in the Dock and may not create windows or be activated.  This corresponds to LSBackgroundOnly=1 in the Info.plist.  This is also the default for unbundled executables that do not have Info.plists. */
			prohibited
		}

		extern class NSGraphicsContext : NSObject {
			static NSGraphicsContext currentContext() @selector("currentContext");
			NSGraphicsContext graphicsPort() @selector("graphicsPort");
		}

		version(OSX)
		extern class NSMenu : NSObject {
			override static NSMenu alloc() @selector("alloc");

			override NSMenu init() @selector("init");
			NSMenu init(NSString title) @selector("initWithTitle:");

			void setSubmenu(NSMenu menu, NSMenuItem item) @selector("setSubmenu:forItem:");
			void addItem(NSMenuItem newItem) @selector("addItem:");

			NSMenuItem addItem(
				NSString title,
				SEL selector,
				NSString charCode
			) @selector("addItemWithTitle:action:keyEquivalent:");
		}

		version(OSX)
		extern class NSMenuItem : NSObject {
			override static NSMenuItem alloc() @selector("alloc");
			override NSMenuItem init() @selector("init");

			NSMenuItem init(
				NSString title,
				SEL selector,
				NSString charCode
			) @selector("initWithTitle:action:keyEquivalent:");

			void enabled(bool) @selector("setEnabled:");

			NSResponder target(NSResponder) @selector("setTarget:");
		}

		enum NSWindowStyleMask : size_t {
			borderless = 0,
			titled = 1 << 0,
			closable = 1 << 1,
			miniaturizable = 1 << 2,
			resizable	= 1 << 3,

			/* Specifies a window with textured background. Textured windows generally don't draw a top border line under the titlebar/toolbar. To get that line, use the NSUnifiedTitleAndToolbarWindowMask mask.
			 */
			texturedBackground = 1 << 8,

			/* Specifies a window whose titlebar and toolbar have a unified look - that is, a continuous background. Under the titlebar and toolbar a horizontal separator line will appear.
			 */
			unifiedTitleAndToolbar = 1 << 12,

			/* When set, the window will appear full screen. This mask is automatically toggled when toggleFullScreen: is called.
			 */
			fullScreen = 1 << 14,

			/* If set, the contentView will consume the full size of the window; it can be combined with other window style masks, but is only respected for windows with a titlebar.
			 Utilizing this mask opts-in to layer-backing. Utilize the contentLayoutRect or auto-layout contentLayoutGuide to layout views underneath the titlebar/toolbar area.
			 */
			fullSizeContentView = 1 << 15,

			/* The following are only applicable for NSPanel (or a subclass thereof)
			 */
			utilityWindow			= 1 << 4,
			docModalWindow		 = 1 << 6,
			nonactivatingPanel		= 1 << 7, // Specifies that a panel that does not activate the owning application
			hUDWindow = 1 << 13 // Specifies a heads up display panel
		}

		version(OSX)
		extern class NSWindow : NSObject {
			override static NSWindow alloc() @selector("alloc");

			override NSWindow init() @selector("init");

			NSWindow initWithContentRect(
				NSRect contentRect,
				NSWindowStyleMask style,
				NSBackingStoreType bufferingType,
				bool flag
			) @selector("initWithContentRect:styleMask:backing:defer:");

			void makeKeyAndOrderFront(NSid sender) @selector("makeKeyAndOrderFront:");
			NSView contentView() @selector("contentView");
			void contentView(NSView view) @selector("setContentView:");
			void orderFrontRegardless() @selector("orderFrontRegardless");
			void center() @selector("center");

			NSRect frame() @selector("frame");

			NSRect contentRectForFrameRect(NSRect frameRect) @selector("contentRectForFrameRect:");
			NSRect frameRectForContentRect(NSRect contentRect) @selector("frameRectForContentRect:");

			NSString title() @selector("title");
			void title(NSString value) @selector("setTitle:");

			void close() @selector("close");

			NSWindowDelegate delegate_() @selector("delegate");
			void delegate_(NSWindowDelegate) @selector("setDelegate:");

			void setBackgroundColor(NSColor color) @selector("setBackgroundColor:");

			void setIsVisible(bool b) @selector("setIsVisible:");
		}

		version(OSX)
		extern interface NSWindowDelegate {
			@optional:
			void windowDidResize(NSNotification notification) @selector("windowDidResize:");

			NSSize windowWillResize(NSWindow sender, NSSize frameSize) @selector("windowWillResize:toSize:");

			void windowWillClose(NSNotification notification) @selector("windowWillClose:");
		}

		version(OSX)
		extern class NSView : NSResponder {
			//override NSView init() @selector("init");
			NSView initWithFrame(NSRect frameRect) @selector("initWithFrame:");

			void addSubview(NSView view) @selector("addSubview:");

			bool wantsLayer() @selector("wantsLayer");
			void wantsLayer(bool value) @selector("setWantsLayer:");

			CALayer layer() @selector("layer");
			void uiDelegate(NSObject) @selector("setUIDelegate:");

			void drawRect(NSRect rect) @selector("drawRect:");
			bool isFlipped() @selector("isFlipped");
			bool acceptsFirstResponder() @selector("acceptsFirstResponder");
			bool setNeedsDisplay(bool) @selector("setNeedsDisplay:");

			// DO NOT USE: https://issues.dlang.org/show_bug.cgi?id=19017
			// an asm { pop RAX; } after getting the struct can kinda hack around this but still
			@property NSRect frame() @selector("frame");
			@property NSRect frame(NSRect rect) @selector("setFrame:");

			void setFrameSize(NSSize newSize) @selector("setFrameSize:");
			void setFrameOrigin(NSPoint newOrigin) @selector("setFrameOrigin:");

			void addSubview(NSView what) @selector("addSubview:");
			void removeFromSuperview() @selector("removeFromSuperview");
		}

		extern class NSFont : NSObject {
			void set() @selector("set"); // sets it into the current graphics context
			void setInContext(NSGraphicsContext context) @selector("setInContext:");

			static NSFont fontWithName(NSString fontName, CGFloat fontSize) @selector("fontWithName:size:");
			// fontWithDescriptor too
			// fontWithName and matrix too
			static NSFont systemFontOfSize(CGFloat fontSize) @selector("systemFontOfSize:");
			// among others

			@property CGFloat pointSize() @selector("pointSize");
			@property bool isFixedPitch() @selector("isFixedPitch");
			// fontDescriptor
			@property NSString displayName() @selector("displayName");

			@property CGFloat ascender() @selector("ascender");
			@property CGFloat descender() @selector("descender"); // note it is negative
			@property CGFloat capHeight() @selector("capHeight");
			@property CGFloat leading() @selector("leading");
			@property CGFloat xHeight() @selector("xHeight");
			// among many more
		}

		extern class NSColor : NSObject {
			override static NSColor alloc() @selector("alloc");
			static NSColor redColor() @selector("redColor");
			static NSColor whiteColor() @selector("whiteColor");

			CGColorRef CGColor() @selector("CGColor");
		}

		extern class CALayer : NSObject {
			CGFloat borderWidth() @selector("borderWidth");
			void borderWidth(CGFloat value) @selector("setBorderWidth:");

			CGColorRef borderColor() @selector("borderColor");
			void borderColor(CGColorRef) @selector("setBorderColor:");
		}


		version(OSX)
		extern class NSViewController : NSObject {
			NSView view() @selector("view");
			void view(NSView view) @selector("setView:");
		}

		enum NSBackingStoreType : size_t {
			retained = 0,
			nonretained = 1,
			buffered = 2
		}

		enum NSStringEncoding : NSUInteger {
			NSASCIIStringEncoding = 1,		/* 0..127 only */
			NSUTF8StringEncoding = 4,
			NSUnicodeStringEncoding = 10,

			NSUTF16StringEncoding = NSUnicodeStringEncoding,
			NSUTF16BigEndianStringEncoding = 0x90000100,
			NSUTF16LittleEndianStringEncoding = 0x94000100,
			NSUTF32StringEncoding = 0x8c000100,
			NSUTF32BigEndianStringEncoding = 0x98000100,
			NSUTF32LittleEndianStringEncoding = 0x9c000100
		}


		struct CGColor;
		alias CGColorRef = CGColor*;

		// note on the watch os it is float, not double
		alias CGFloat = double;

		struct NSPoint {
			CGFloat x;
			CGFloat y;
		}

		struct NSSize {
			CGFloat width;
			CGFloat height;
		}

		struct NSRect {
			NSPoint origin;
			NSSize size;
		}

		alias NSPoint CGPoint;
		alias NSSize CGSize;
		alias NSRect CGRect;

		pragma(inline, true) NSPoint NSMakePoint(CGFloat x, CGFloat y) {
			NSPoint p;
			p.x = x;
			p.y = y;
			return p;
		}

		pragma(inline, true) NSSize NSMakeSize(CGFloat w, CGFloat h) {
			NSSize s;
			s.width = w;
			s.height = h;
			return s;
		}

		pragma(inline, true) NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
			NSRect r;
			r.origin.x = x;
			r.origin.y = y;
			r.size.width = w;
			r.size.height = h;
			return r;
		}


	}

	// helper raii refcount object
	static if(UseCocoa)
	struct MacString {
		union {
			// must be wrapped cuz of bug in dmd
			// referencing an init symbol when it should
			// just be null. but the union makes it work
			NSString s;
		}

		// FIXME: if a string literal it would be kinda nice to use
		// the other function. but meh

		this(scope const char[] str) {
			this.s = NSString.alloc.initWithBytes(
				cast(const(ubyte)*) str.ptr,
				str.length,
				NSStringEncoding.NSUTF8StringEncoding
			);
		}

		NSString borrow() {
			return s;
		}

		this(this) {
			if(s !is null)
				s.retain();
		}

		~this() {
			if(s !is null) {
				s.release();
				s = null;
			}
		}
	}

	extern(C) void NSLog(NSString, ...);
	extern(C) SEL sel_registerName(const(char)* str);

	version(OSX)
	extern (Objective-C) __gshared NSApplication NSApp_;

	version(OSX)
	NSApplication NSApp() {
		if(NSApp_ is null)
			NSApp_ = NSApplication.shared_;
		return NSApp_;
	}

	version(DigitalMars) {
	// hacks to work around compiler bug
	extern(C) __gshared void* _D4arsd4core17NSGraphicsContext7__ClassZ = null;
	extern(C) __gshared void* _D4arsd4core6NSView7__ClassZ = null;
	extern(C) __gshared void* _D4arsd4core8NSWindow7__ClassZ = null;
	}



	extern(C) { // grand central dispatch bindings

		// /Library/Developer/CommandLineTools/SDKs/MacOSX13.1.sdk/usr/include/dispatch
		// https://swiftlang.github.io/swift-corelibs-libdispatch/tutorial/
		// https://man.freebsd.org/cgi/man.cgi?query=dispatch_main&sektion=3&apropos=0&manpath=macOS+14.3.1

		struct dispatch_source_type_s {}
		private __gshared immutable extern {
			dispatch_source_type_s _dispatch_source_type_timer;
			dispatch_source_type_s _dispatch_source_type_proc;
			dispatch_source_type_s _dispatch_source_type_signal;
			dispatch_source_type_s _dispatch_source_type_read;
			dispatch_source_type_s _dispatch_source_type_write;
			dispatch_source_type_s _dispatch_source_type_vnode;
			// also memory pressure and some others
		}

		immutable DISPATCH_SOURCE_TYPE_TIMER = &_dispatch_source_type_timer;
		immutable DISPATCH_SOURCE_TYPE_PROC = &_dispatch_source_type_proc;
		immutable DISPATCH_SOURCE_TYPE_SIGNAL = &_dispatch_source_type_signal;
		immutable DISPATCH_SOURCE_TYPE_READ = &_dispatch_source_type_read;
		immutable DISPATCH_SOURCE_TYPE_WRITE = &_dispatch_source_type_write;
		immutable DISPATCH_SOURCE_TYPE_VNODE = &_dispatch_source_type_vnode;
		// also are some for internal data change things and a couple others

		enum DISPATCH_PROC_EXIT = 0x80000000; // process exited
		enum DISPATCH_PROC_FORK = 0x40000000; // it forked
		enum DISPATCH_PROC_EXEC = 0x20000000; // it execed
		enum DISPATCH_PROC_SIGNAL = 0x08000000; // it received a signal

		enum DISPATCH_VNODE_DELETE = 0x1;
		enum DISPATCH_VNODE_WRITE = 0x2;
		enum DISPATCH_VNODE_EXTEND = 0x4;
		enum DISPATCH_VNODE_ATTRIB = 0x8;
		enum DISPATCH_VNODE_LINK = 0x10;
		enum DISPATCH_VNODE_RENAME = 0x20;
		enum DISPATCH_VNODE_REVOKE = 0x40;
		enum DISPATCH_VNODE_FUNLOCK = 0x100;

		private struct dispatch_source_s;
		private struct dispatch_queue_s {}

		alias dispatch_source_type_t = const(dispatch_source_type_s)*;

		alias dispatch_source_t = dispatch_source_s*; // NSObject<OS_dispatch_source>
		alias dispatch_queue_t = dispatch_queue_s*; // NSObject<OS_dispatch_queue>
		alias dispatch_object_t = void*; // actually a "transparent union" of the dispatch_source_t, dispatch_queue_t, and others
		alias dispatch_block_t = ObjCBlock!(void)*;
		static if(void*.sizeof == 8)
			alias uintptr_t = ulong;
		else
			alias uintptr_t = uint;

		dispatch_source_t dispatch_source_create(dispatch_source_type_t type, uintptr_t handle, c_ulong mask, dispatch_queue_t queue);
		void dispatch_source_set_event_handler(dispatch_source_t source, dispatch_block_t handler);
		void dispatch_source_set_cancel_handler(dispatch_source_t source, dispatch_block_t handler);
		void dispatch_source_cancel(dispatch_source_t source);

		// DISPATCH_DECL_SUBCLASS(dispatch_queue_main, dispatch_queue_serial);
		// dispatch_queue_t dispatch_get_main_queue();

		extern __gshared dispatch_queue_s _dispatch_main_q;

		extern(D) dispatch_queue_t dispatch_get_main_queue() {
			return &_dispatch_main_q;
		}

		// FIXME: what is dispatch_time_t ???
		// dispatch_time
		// dispatch_walltime

		// void dispatch_source_set_timer(dispatch_source_t source, dispatch_time_t start, ulong interval, ulong leeway);

		void dispatch_retain(dispatch_object_t object);
		void dispatch_release(dispatch_object_t object);

		void dispatch_resume(dispatch_object_t object);
		void dispatch_pause(dispatch_object_t object);

		void* dispatch_get_context(dispatch_object_t object);
		void dispatch_set_context(dispatch_object_t object, void* context);

		// sends a function to the given queue
		void dispatch_sync(dispatch_queue_t queue, scope dispatch_block_t block);
		void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);

	} // grand central dispatch bindings

}
