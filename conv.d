/++
	A simplified version of `std.conv` with better error messages and faster compiles for supported types.

	History:
		Added May 22, 2025
+/
module arsd.conv;

static import arsd.core;

// FIXME: thousands separator for int to string (and float to string)
// FIXME: intToStringArgs
// FIXME: floatToStringArgs

/++
	Converts a string into the other given type. Throws on failure.
+/
T to(T)(scope const(char)[] str) {
	static if(is(T == enum)) {
		switch(str) {
			default:
				throw new EnumConvException(T.stringof, str.idup);
			foreach(memberName; __traits(allMembers, T))
			case memberName:
				return __traits(getMember, T, memberName);
		}

	}
	else
	static if(is(T : long)) {
		// FIXME: unsigned? overflowing? radix? keep reading or stop on invalid char?
		StringToIntArgs args;
		args.unsigned = __traits(isUnsigned, T);
		long v = stringToInt(str, args);
		T ret = cast(T) v;
		if(ret != v)
			throw new StringToIntConvException("overflow", 0, str.idup, 0);
		return ret;
	}
	else
	static if(is(T : double)) {
		import core.stdc.stdlib;
		import core.stdc.errno;
		arsd.core.CharzBuffer z = str;
		char* end;
		errno = 0;
		double res = strtod(z.ptr, &end);
		if(end !is (z.ptr + z.length) || errno) {
			string msg = errno == ERANGE ? "Over/underflow" : "Invalid input";
			throw new StringToIntConvException(msg, 10, str.idup, end - z.ptr);
		}

		return res;
	}
	else
	{
		static assert(0, "Unsupported type: " ~ T.stringof);
	}
}

/++
	Converts any given value to a string. The format of the string is unspecified; it is meant for a human reader and might be overridden by types.
+/
string to(T:string, From)(From value) {
	static if(is(From == enum))
		return arsd.core.enumNameForValue(value);
	else
		return arsd.core.toStringInternal(value);
}

/++
	Converts ints to other types of ints or enums
+/
T to(T)(long value) {
	static if(is(T == enum))
		return cast(T) value; // FIXME check if the value is actually in range
	else
		return checkedConversion!T(value);
}

/+
T to(T, F)(F value) if(!is(F : const(char)[])) {
	// if the language allows implicit conversion, let it do its thing
	static if(is(T : F)) {
		return value;
	}
	else
	// integral type conversions do checked things
	static if(is(T : long) && is(F : long)) {
		return checkedConversion!T(value);
	}
	else
	// array to array conversion: try to convert the individual elements, allocating a new return value.
	static if(is(T : TE[], TE) && is(F : FE[], FE)) {
		F ret = new F(value.length);
		foreach(i, e; value)
			ret[i] = to!TE(e);
		return ret;
	}
	else
		static assert(0, "Unsupported conversion types");
}
+/

unittest {
	assert(to!int("5") == 5);
	assert(to!int("35") == 35);
	assert(to!string(35) == "35");
	assert(to!int("0xA35d") == 0xA35d);
	assert(to!int("0b11001001") == 0b11001001);
	assert(to!int("0o777") == 511 /*0o777*/);

	assert(to!ubyte("255") == 255);
	assert(to!ulong("18446744073709551615") == ulong.max);

	void expectedToThrow(T...)(lazy T items) {
		int count;
		string messages;
		static foreach(idx, item; items) {
			try {
				auto result = item;
				if(messages.length)
					messages ~= ",";
				messages ~= idx.stringof[0..$-2];
			} catch(StringToIntConvException e) {
				// passed the test; it was supposed to throw.
				 // arsd.core.writeln(e);
				count++;
			}
		}

		assert(count == T.length, "Arg(s) " ~ messages ~ " did not throw");
	}

	expectedToThrow(
		to!uint("-44"), // negative number to unsigned reuslt
		to!int("add"), // invalid base 10 chars
		to!byte("129"), // wrapped to negative
		to!int("0p4a0"), // invalid radix prefix
		to!int("5000000000"), // doesn't fit in int
		to!ulong("6000000000000000000900"), // overflow when reading into the ulong buffer
	);
}

/++

+/
class ConvException : arsd.core.ArsdExceptionBase {
	this(string msg, string file, size_t line) {
		super(msg, file, line);
	}
}

/++

+/
class ValueOutOfRangeException : ConvException {
	this(string type, long userSuppliedValue, long minimumAcceptableValue, long maximumAcceptableValue, string file = __FILE__, size_t line = __LINE__) {
		this.type = type;
		this.userSuppliedValue = userSuppliedValue;
		this.minimumAcceptableValue = minimumAcceptableValue;
		this.maximumAcceptableValue = maximumAcceptableValue;
		super("Value was out of range", file, line);
	}

	string type;
	long userSuppliedValue;
	long minimumAcceptableValue;
	long maximumAcceptableValue;

	override void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {
		sink("type", type);
		sink("userSuppliedValue", arsd.core.toStringInternal(userSuppliedValue));
		sink("minimumAcceptableValue", arsd.core.toStringInternal(minimumAcceptableValue));
		sink("maximumAcceptableValue", arsd.core.toStringInternal(maximumAcceptableValue));
	}
}

/++

+/
class EnumConvException : ConvException {
	this(string type, string userSuppliedValue, string file = __FILE__, size_t line = __LINE__) {
		this.type = type;
		this.userSuppliedValue = userSuppliedValue;

		super("No such enum value", file, line);

	}
	string type;
	string userSuppliedValue;

	override void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {
		sink("type", type);
		sink("userSuppliedValue", userSuppliedValue);
	}
}

unittest {
	enum A { a, b, c }
	// to!A("d");
}


/++

+/
class StringToIntConvException : arsd.core.ArsdExceptionBase /*InvalidDataException*/ {
	this(string msg, int radix, string userInput, size_t offset, string file = __FILE__, size_t line = __LINE__) {
		this.radix = radix;
		this.userInput = userInput;
		this.offset = offset;

		super(msg, file, line);
	}

	override void getAdditionalPrintableInformation(scope void delegate(string name, in char[] value) sink) const {
		sink("radix", arsd.core.toStringInternal(radix));
		sink("userInput", arsd.core.toStringInternal(userInput));
		if(offset < userInput.length)
		sink("offset", arsd.core.toStringInternal(offset) ~ " ('" ~ userInput[offset] ~ "')");

	}

	///
	int radix;
	///
	string userInput;
	///
	size_t offset;
}

/++
	if radix is 0, guess from 0o, 0x, 0b prefixes.
+/
long stringToInt(scope const(char)[] str, StringToIntArgs args = StringToIntArgs.init) {
	long accumulator;

	auto original = str;

	Exception exception(string msg, size_t loopOffset = 0, string file = __FILE__, size_t line = __LINE__) {
		return new StringToIntConvException(msg, args.radix, original.dup, loopOffset + str.ptr - original.ptr, file, line);
	}

	if(str.length == 0)
		throw exception("empty string");

	bool isNegative;
	if(str[0] == '-') {
		if(args.unsigned)
			throw exception("negative number given, but unsigned result desired");

		isNegative = true;
		str = str[1 .. $];
	}

	if(str.length == 0)
		throw exception("just a dash");

	if(str[0] == '0') {
		if(str.length > 1 && (str[1] == 'b' || str[1] == 'x' || str[1] == 'o')) {
			if(args.radix != 0) {
				throw exception("string had specified base, but the radix arg was already supplied");
			}

			switch(str[1]) {
				case 'b':
					args.radix = 2;
				break;
				case 'o':
					args.radix = 8;
				break;
				case 'x':
					args.radix = 16;
				break;
				default:
					assert(0);
			}

			str = str[2 .. $];

			if(str.length == 0)
				throw exception("just a prefix");
		}
	}

	if(args.radix == 0)
		args.radix = 10;

	foreach(idx, char ch; str) {

		if(ch && ch == args.ignoredSeparator)
			continue;

		auto before = accumulator;

		accumulator *= args.radix;

		int value = -1;
		if(ch >= '0' && ch <= '9') {
			value = ch - '0';
		} else {
			ch |= 32;
			if(ch >= 'a' && ch <= 'z')
				value = ch - 'a' + 10;
		}

		if(value < 0)
			throw exception("invalid char", idx);
		if(value >= args.radix)
			throw exception("invalid char for given radix", idx);

		accumulator += value;
		if(args.unsigned) {
			auto b = cast(ulong) before;
			auto a = cast(ulong) accumulator;
			if(a < b)
				throw exception("value too big to fit in unsigned buffer", idx);
		} else {
			if(accumulator < before && !args.unsigned)
				throw exception("value too big to fit in signed buffer", idx);
		}
	}

	if(isNegative)
		accumulator = -accumulator;

	return accumulator;
}

/// ditto
struct StringToIntArgs {
	int radix;
	bool unsigned;
	char ignoredSeparator = 0;
}

/++
	Converts two integer types, returning the min/max of the desired type if the given value is out of range for it.
+/
T saturatingConversion(T)(long value) {
	static assert(is(T : long), "Only works on integer types");

	static if(is(T == ulong)) // the special case to try to handle the full range there
		ulong mv = cast(ulong) value;
	else
		long mv = value;

	if(mv > T.max)
		return T.max;
	else if(value < T.min)
		return T.min;
	else
		return cast(T) value;
}

unittest {
	assert(saturatingConversion!ubyte(256) == 255);
	assert(saturatingConversion!byte(256) == 127);
	assert(saturatingConversion!byte(-256) == -128);

	assert(saturatingConversion!ulong(0) == 0);
	assert(saturatingConversion!long(-5) == -5);

	assert(saturatingConversion!uint(-5) == 0);

	// assert(saturatingConversion!ulong(-5) == 0); // it can't catch this since the -5 is indistinguishable from the large ulong value here
}

/++
	Truncates off bits that won't fit; equivalent to a built-in cast operation (you can just use a cast instead if you want).
+/
T truncatingConversion(T)(long value) {
	static assert(is(T : long), "Only works on integer types");

	return cast(T) value;

}

/++
	Converts two integer types, throwing an exception if the given value is out of range for it.
+/
T checkedConversion(T)(long value, long minimumAcceptableValue = T.min, long maximumAcceptableValue = T.max) {
	static assert(is(T : long), "Only works on integer types");

	if(value > maximumAcceptableValue)
		throw new ValueOutOfRangeException(T.stringof, value, minimumAcceptableValue, maximumAcceptableValue);
	else if(value < minimumAcceptableValue)
		throw new ValueOutOfRangeException(T.stringof, value, minimumAcceptableValue, maximumAcceptableValue);
	else
		return cast(T) value;
}
/// ditto
T checkedConversion(T:ulong)(ulong value, ulong minimumAcceptableValue = T.min, ulong maximumAcceptableValue = T.max) {
	if(value > maximumAcceptableValue)
		throw new ValueOutOfRangeException(T.stringof, value, minimumAcceptableValue, maximumAcceptableValue);
	else if(value < minimumAcceptableValue)
		throw new ValueOutOfRangeException(T.stringof, value, minimumAcceptableValue, maximumAcceptableValue);
	else
		return cast(T) value;
}

unittest {
	try {
		assert(checkedConversion!byte(155));
		assert(0);
	} catch(ValueOutOfRangeException e) {

	}
}
