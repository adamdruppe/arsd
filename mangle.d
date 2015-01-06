module mangle;

import std.conv;

static immutable string[23] primitives = [
	"char", // a
	"bool", // b
	"creal", // c
	"double", // d
	"real", // e
	"float", // f
	"byte", // g
	"ubyte", // h
	"int", // i
	"ireal", // j
	"uint", // k
	"long", // l
	"ulong", // m
	null, // n
	"ifloat", // o
	"idouble", // p
	"cfloat", // q
	"cdouble", // r
	"short", // s
	"ushort", // t
	"wchar", // u
	"void", // v
	"dchar", // w
];

// FIXME: using this will allocate at *runtime*! Unbelievable.
// it does that even if everything is enum
auto dTokensPain() {
	immutable p = cast(immutable(string[])) primitives[];
	string[] ret;
	foreach(i; (sort!"a.length > b.length"(
	p~
[
	"(",
	")",
	".",
	",",
	"!",
	"[",
	"]",
	"*",
	"const",
	"immutable",
	"shared",
	"extern",
]))) { ret ~= i; }

	return ret;
}

static immutable string[] dTokens = dTokensPain();


char manglePrimitive(in char[] t) {
	foreach(i, p; primitives)
		if(p == t)
			return cast(char) ('a' + i);
	return 0;
}

import std.algorithm;
import std.array;

bool isIdentifierChar(char c) {
	// FIXME: match the D spec
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

struct StackArray(Type, size_t capacity) {
	Type[capacity] buffer;
	size_t length;
	Type[] slice() { return buffer[0 .. length]; }
	void opOpAssign(string op : "~")(Type rhs, string file = __FILE__, size_t line = __LINE__) {
		if(length >= capacity) {
			throw new Error("no more room", file, line);
		}
		buffer[length] = rhs;
		length++;
	}
}

char[] mangle(const(char)[] decl, char[] buffer) {


	StackArray!(const(char)[], 128) tokensBuffer;
	main: while(decl.length) {
		if(decl[0] == ' ' || decl[0] == '\t' || decl[0] == '\n') {
			decl = decl[1 .. $];
			continue;
		}

		foreach(token; dTokens) {
			if(token is null) continue;
			if(decl.length >= token.length && decl[0 .. token.length] == token) {
				// make sure this isn't an identifier that coincidentally starts with a keyword
				if(decl.length == token.length || !token[$ - 1].isIdentifierChar() || !decl[token.length].isIdentifierChar()) {
					tokensBuffer ~= token;
					decl = decl[token.length .. $];
					continue main;
				}
			}
		}

		// could be an identifier or literal

		int pos = 0;
		while(pos < decl.length && decl[pos].isIdentifierChar)
			pos++;
		tokensBuffer ~= decl[0 .. pos];
		decl = decl[pos .. $];
		continue main;

		// FIXME: literals should be handled too
	}

	assert(decl.length == 0); // we should have consumed all the input into tokens

	auto tokens = tokensBuffer.slice();


	char[64] returnTypeBuffer;
	auto returnType = parseAndMangleType(tokens, returnTypeBuffer);
	char[256] nameBuffer;
	auto name = parseName(tokens, nameBuffer[]);
	StackArray!(const(char)[], 64) arguments;
	// FIXME: templates and other types of thing should be handled
	assert(tokens[0] == "(", "other stuff not implemented " ~ tokens[0]);
	tokens = tokens[1 .. $];

	char[64][32] argTypeBuffers;
	int i = 0;

	while(tokens[0] != ")") {
		arguments ~= parseAndMangleType(tokens, argTypeBuffers[i]);
		i++;
		if(tokens[0] == ",")
			tokens = tokens[1 .. $];
	}

	assert(tokens[0] == ")", "other stuff not implemented");

	return mangleFunction(name, returnType, arguments.slice(), buffer);
}

char[] parseName(ref const(char)[][] tokens, char[] nameBuffer) {
	size_t where = 0;
	more:
	nameBuffer[where .. where + tokens[0].length] = tokens[0][];
	where += tokens[0].length;
	tokens = tokens[1 .. $];
	if(tokens.length && tokens[0] == ".") {
		tokens = tokens[1 .. $];
		nameBuffer[where++] = '.';
		goto more;
	}

	return nameBuffer[0 .. where];
}

char[] intToString(int i, char[] buffer) {
	int pos = cast(int) buffer.length - 1;

	if(i == 0) {
		buffer[pos] = '0';
		pos--;
	}

	while(pos > 0 && i) {
		buffer[pos] = (i % 10) + '0';
		pos--;
		i /= 10;
	}

	return buffer[pos + 1 .. $];
}



char[] mangleName(in char[] name, char[] buffer) {
	import std.algorithm;
	import std.conv;

	auto parts = name.splitter(".");

	int bufferPos = 0;
	foreach(part; parts) {
		char[16] numberBuffer;
		auto number = intToString(cast(int) part.length, numberBuffer);

		buffer[bufferPos .. bufferPos + number.length] = number[];
		bufferPos += number.length;

		buffer[bufferPos .. bufferPos + part.length] = part[];
		bufferPos += part.length;
	}

	return buffer[0 .. bufferPos];
}

char[] mangleFunction(in char[] name, in char[] returnTypeMangled, in char[][] argumentsMangle, char[] buffer) {
	int bufferPos = 0;
	buffer[bufferPos++] = '_';
	buffer[bufferPos++] = 'D';

	char[256] nameBuffer;
	auto mn = mangleName(name, nameBuffer);
	buffer[bufferPos .. bufferPos + mn.length] = mn[];
	bufferPos += mn.length;

	buffer[bufferPos++] = 'F';
	foreach(arg; argumentsMangle) {
		buffer[bufferPos .. bufferPos + arg.length] = arg[];
		bufferPos += arg.length;
	}
	buffer[bufferPos++] = 'Z';
	buffer[bufferPos .. bufferPos + returnTypeMangled.length] = returnTypeMangled[];
	bufferPos += returnTypeMangled.length;

	return buffer[0 .. bufferPos];
}

char[] parseAndMangleType(ref const(char)[][] tokens, char[] buffer) {
	assert(tokens.length);

	int bufferPos = 0;

	void prepend(char p) {
		for(int i = bufferPos; i > 0; i--) {
			buffer[i] = buffer[i - 1];
		}
		buffer[0] = p;
		bufferPos++;
	}

	// FIXME: handle all the random D type constructors
	if(tokens[0] == "const" || tokens[0] == "immutable") {
		if(tokens[0] == "const")
			buffer[bufferPos++] = 'x';
		else if(tokens[0] == "immutable")
			buffer[bufferPos++] = 'y';
		tokens = tokens[1 .. $];
		assert(tokens[0] == "(");
		tokens = tokens[1 .. $];
		auto next = parseAndMangleType(tokens, buffer[bufferPos .. $]);
		bufferPos += next.length;
		assert(tokens[0] == ")");
		tokens = tokens[1 .. $];
	} else {
		char primitive = manglePrimitive(tokens[0]);
		if(primitive) {
			buffer[bufferPos++] = primitive;
			tokens = tokens[1 .. $];
		} else {
			// probably a struct or something, parse it as an identifier
			// FIXME
			char[256] nameBuffer;
			auto name = parseName(tokens, nameBuffer[]);

			char[256] mangledNameBuffer;
			auto mn = mangleName(name, mangledNameBuffer);

			buffer[bufferPos++] = 'S';
			buffer[bufferPos .. bufferPos + mn.length] = mn[];
			bufferPos += mn.length;
		}
	}

	while(tokens.length) {
		if(tokens[0] == "[") {
			tokens = tokens[1 .. $];
			prepend('A');
			assert(tokens[0] == "]", "other array not implemented");
			tokens = tokens[1 .. $];
		} else if(tokens[0] == "*") {
			prepend('P');
			tokens = tokens[1 .. $];
		} else break;
	}

	return buffer[0 .. bufferPos];
}

version(unittest) {
	int foo(int, string, int);
	string foo2(long, char[], int);
	struct S { int a; string b; }
	S foo3(S, S, string, long, int, S, int[], char[][]);
	long testcomplex(int, const(const(char)[]*)[], long);
}

unittest {
	import core.demangle;
	char[512] buffer;

	import std.stdio;
	assert(mangle(demangle(foo.mangleof), buffer) == foo.mangleof);
	assert(mangle(demangle(foo2.mangleof), buffer) == foo2.mangleof);
	assert(mangle(demangle(foo3.mangleof), buffer) == foo3.mangleof);

	assert(mangle(demangle(testcomplex.mangleof), buffer) == testcomplex.mangleof);
	// FIXME: these all fail if the functions are defined inside the unittest{} block
	// so still something wrong parsing those complex names or something
}

// _D6test303fooFiAyaZi
// _D6test303fooFiAyaZi

version(unittest)
void main(string[] args) {

	char[512] buffer;
	import std.stdio;
	if(args.length > 1)
		writeln(mangle(args[1], buffer));
	else
		writeln(mangle("int test30.foo(int, immutable(char)[])", buffer));
		//mangle("int test30.foo(int, immutable(char)[])", buffer);
}
