// dmd -g -ofscripttest -unittest -main script.d jsvar.d && ./scripttest
/*

FIXME: fix `(new A()).b`


	FIXME: i kinda do want a catch type filter e.g. catch(Exception f)
		and perhaps overloads



	For type annotations, maybe it can statically match later, but right now
	it just forbids any assignment to that variable that isn't that type.

	I'll have to define int, float, etc though as basic types.



	FIXME: I also kinda want implicit construction of structs at times.

	REPL plan:
		easy movement to/from a real editor
		can edit a specific function
		repl is a different set of globals
		maybe ctrl+enter to execute vs insert another line


		write state to file
		read state from file
			state consists of all variables and source to functions.
			maybe need @retained for a variable that is meant to keep
			its value between loads?

		ddoc????
		udas?!?!?!

	Steal Ruby's [regex, capture] maybe

	and the => operator too

	I kinda like the javascript foo`blargh` template literals too.

	++ and -- are not implemented.

*/

/++
	A small script interpreter that builds on [arsd.jsvar] to be easily embedded inside and to have has easy
	two-way interop with the host D program.  The script language it implements is based on a hybrid of D and Javascript.
	The type the language uses is based directly on [var] from [arsd.jsvar].

	The interpreter is slightly buggy and poorly documented, but the basic functionality works well and much of
	your existing knowledge from Javascript will carry over, making it hopefully easy to use right out of the box.
	See the [#examples] to quickly get the feel of the script language as well as the interop.

	I haven't benchmarked it, but I expect it is pretty slow. My goal is to see what is possible for easy interoperability
	with dynamic functionality and D rather than speed.


	$(TIP
		A goal of this language is to blur the line between D and script, but
		in the examples below, which are generated from D unit tests,
		the non-italics code is D, and the italics is the script. Notice
		how it is a string passed to the [interpret] function.

		In some smaller, stand-alone code samples, there will be a tag "adrscript"
		in the upper right of the box to indicate it is script. Otherwise, it
		is D.
	)

	Installation_instructions:
	This script interpreter is contained entirely in two files: jsvar.d and script.d. Download both of them
	and add them to your project. Then, `import arsd.script;`, declare and populate a `var globals = var.emptyObject;`,
	and `interpret("some code", globals);` in D.

	There's nothing else to it, no complicated build, no external dependencies.

	$(CONSOLE
		$ wget https://raw.githubusercontent.com/adamdruppe/arsd/master/script.d
		$ wget https://raw.githubusercontent.com/adamdruppe/arsd/master/jsvar.d

		$ dmd yourfile.d script.d jsvar.d
	)

	Script_features:

	OVERVIEW
	$(LIST
	* Can subclass D objects in script. See [http://dpldocs.info/this-week-in-d/Blog.Posted_2020_04_27.html#subclasses-in-script
	* easy interop with D thanks to arsd.jsvar. When interpreting, pass a var object to use as globals.
		This object also contains the global state when interpretation is done.
	* mostly familiar syntax, hybrid of D and Javascript
	* simple implementation is moderately small and fairly easy to hack on (though it gets messier by the day), but it isn't made for speed.
	)

	SPECIFICS
	$(LIST
	// * Allows identifiers-with-dashes. To do subtraction, put spaces around the minus sign.
	* Allows identifiers starting with a dollar sign.
	* string literals come in "foo" or 'foo', like Javascript, or `raw string` like D. Also come as “nested “double quotes” are an option!”
	* double quoted string literals can do Ruby-style interpolation: "Hello, #{name}".
	* mixin aka eval (does it at runtime, so more like eval than mixin, but I want it to look like D)
	* scope guards, like in D
	* Built-in assert() which prints its source and its arguments
	* try/catch/finally/throw
		You can use try as an expression without any following catch to return the exception:

		```adrscript
		var a = try throw "exception";; // the double ; is because one closes the try, the second closes the var
		// a is now the thrown exception
		```
	* for/while/foreach
	* D style operators: +-/* on all numeric types, ~ on strings and arrays, |&^ on integers.
		Operators can coerce types as needed: 10 ~ "hey" == "10hey". 10 + "3" == 13.
		Any math, except bitwise math, with a floating point component returns a floating point component, but pure int math is done as ints (unlike Javascript btw).
		Any bitwise math coerces to int.

		So you can do some type coercion like this:

		```adrscript
		a = a|0; // forces to int
		a = "" ~ a; // forces to string
		a = a+0.0; // coerces to float
		```

		Though casting is probably better.
	* Type coercion via cast, similarly to D.
		```adrscript
		var a = "12";
		a.typeof == "String";
		a = cast(int) a;
		a.typeof == "Integral";
		a == 12;
		```

		Supported types for casting to: int/long (both actually an alias for long, because of how var works), float/double/real, string, char/dchar (these return *integral* types), and arrays, int[], string[], and float[].

		This forwards directly to the D function var.opCast.

	* some operator overloading on objects, passing opBinary(op, rhs), length, and perhaps others through like they would be in D.
		opIndex(name)
		opIndexAssign(value, name) // same order as D, might some day support [n1, n2] => (value, n1, n2)

		obj.__prop("name", value); // bypasses operator overloading, useful for use inside the opIndexAssign especially

		Note: if opIndex is not overloaded, getting a non-existent member will actually add it to the member. This might be a bug but is needed right now in the D impl for nice chaining. Or is it? FIXME

		FIXME: it doesn't do opIndex with multiple args.
	* if/else
	* array slicing, but note that slices are rvalues currently
	* variables must start with A-Z, a-z, _, or $, then must be [A-Za-z0-9_]*.
		(The $ can also stand alone, and this is a special thing when slicing, so you probably shouldn't use it at all.).
		Variable names that start with __ are reserved and you shouldn't use them.
	* int, float, string, array, bool, and `#{}` (previously known as `json!q{}` aka object) literals
	* var.prototype, var.typeof. prototype works more like Mozilla's __proto__ than standard javascript prototype.
	* the `|>` pipeline operator
	* classes:
		```adrscript
		// inheritance works
		class Foo : bar {
			// constructors, D style
			this(var a) { ctor.... }

			// static vars go on the auto created prototype
			static var b = 10;

			// instance vars go on this instance itself
			var instancevar = 20;

			// "virtual" functions can be overridden kinda like you expect in D, though there is no override keyword
			function virt() {
				b = 30; // lexical scoping is supported for static variables and functions

				// but be sure to use this. as a prefix for any class defined instance variables in here
				this.instancevar = 10;
			}
		}

		var foo = new Foo(12);

		foo.newFunc = function() { this.derived = 0; }; // this is ok too, and scoping, including 'this', works like in Javascript
		```

		You can also use 'new' on another object to get a copy of it.
	* return, break, continue, but currently cannot do labeled breaks and continues
	* __FILE__, __LINE__, but currently not as default arguments for D behavior (they always evaluate at the definition point)
	* most everything are expressions, though note this is pretty buggy! But as a consequence:
		for(var a = 0, b = 0; a < 10; a+=1, b+=1) {}
		won't work but this will:
		for(var a = 0, b = 0; a < 10; {a+=1; b+=1}) {}

		You can encase things in {} anywhere instead of a comma operator, and it works kinda similarly.

		{} creates a new scope inside it and returns the last value evaluated.
	* functions:
		var fn = function(args...) expr;
		or
		function fn(args....) expr;

		Special function local variables:
			_arguments = var[] of the arguments passed
			_thisfunc = reference to the function itself
			this = reference to the object on which it is being called - note this is like Javascript, not D.

		args can say var if you want, but don't have to
		default arguments supported in any position
		when calling, you can use the default keyword to use the default value in any position
	* macros:
		A macro is defined just like a function, except with the
		macro keyword instead of the function keyword. The difference
		is a macro must interpret its own arguments - it is passed
		AST objects instead of values. Still a WIP.
	)


	Todo_list:

	I also have a wishlist here that I may do in the future, but don't expect them any time soon.

FIXME: maybe some kind of splat operator too. choose([1,2,3]...) expands to choose(1,2,3)

make sure superclass ctors are called

   FIXME: prettier stack trace when sent to D

   FIXME: support more escape things in strings like \n, \t etc.

   FIXME: add easy to use premade packages for the global object.

   FIXME: the debugger statement from javascript might be cool to throw in too.

   FIXME: add continuations or something too - actually doing it with fibers works pretty well

   FIXME: Also ability to get source code for function something so you can mixin.

   FIXME: add COM support on Windows ????


	Might be nice:
		varargs
		lambdas - maybe without function keyword and the x => foo syntax from D.

	Author:
		Adam D. Ruppe

	History:
		November 17, 2023: added support for hex, octal, and binary literals and added _ separators in numbers.

		September 1, 2020: added overloading for functions and type matching in `catch` blocks among other bug fixes

		April 28, 2020: added `#{}` as an alternative to the `json!q{}` syntax for object literals. Also fixed unary `!` operator.

		April 26, 2020: added `switch`, fixed precedence bug, fixed doc issues and added some unittests

		Started writing it in July 2013. Yes, a basic precedence issue was there for almost SEVEN YEARS. You can use this as a toy but please don't use it for anything too serious, it really is very poorly written and not intelligently designed at all.
+/
module arsd.script;

/++
	This example shows the basics of how to interact with the script.
	The string enclosed in `q{ .. }` is the script language source.

	The [var] type comes from [arsd.jsvar] and provides a dynamic type
	to D. It is the same type used in the script language and is weakly
	typed, providing operator overloads to work with many D types seamlessly.

	However, if you do need to convert it to a static type, such as if passing
	to a function, you can use `get!T` to get a static type out of it.
+/
unittest {
	var globals = var.emptyObject;
	globals.x = 25; // we can set variables on the global object
	globals.name = "script.d"; // of various types
	// and we can make native functions available to the script
	globals.sum = (int a, int b) {
		return a + b;
	};

	// This is the source code of the script. It is similar
	// to javascript with pieces borrowed from D, so should
	// be pretty familiar.
	string scriptSource = q{
		function foo() {
			return 13;
		}

		var a = foo() + 12;
		assert(a == 25);

		// you can also access the D globals from the script
		assert(x == 25);
		assert(name == "script.d");

		// as well as call D functions set via globals:
		assert(sum(5, 6) == 11);

		// I will also set a function to call from D
		function bar(str) {
			// unlike Javascript though, we use the D style
			// concatenation operator.
			return str ~ " concatenation";
		}
	};

	// once you have the globals set up, you call the interpreter
	// with one simple function.
	interpret(scriptSource, globals);

	// finally, globals defined from the script are accessible here too:
	// however, notice the two sets of parenthesis: the first is because
	// @property is broken in D. The second set calls the function and you
	// can pass values to it.
	assert(globals.foo()() == 13);

	assert(globals.bar()("test") == "test concatenation");

	// this shows how to convert the var back to a D static type.
	int x = globals.x.get!int;
}

/++
	$(H3 Macros)

	Macros are like functions, but instead of evaluating their arguments at
	the call site and passing value, the AST nodes are passed right in. Calling
	the node evaluates the argument and yields the result (this is similar to
	to `lazy` parameters in D), and they also have methods like `toSourceCode`,
	`type`, and `interpolate`, which forwards to the given string.

	The language also supports macros and custom interpolation functions. This
	example shows an interpolation string being passed to a macro and used
	with a custom interpolation string.

	You might use this to encode interpolated things or something like that.
+/
unittest {
	var globals = var.emptyObject;
	interpret(q{
		macro test(x) {
			return x.interpolate(function(str) {
				return str ~ "test";
			});
		}

		var a = "cool";
		assert(test("hey #{a}") == "hey cooltest");
	}, globals);
}

/++
	$(H3 Classes demo)

	See also: [arsd.jsvar.subclassable] for more interop with D classes.
+/
unittest {
	var globals = var.emptyObject;
	interpret(q{
		class Base {
			function foo() { return "Base"; }
			function set() { this.a = 10; }
			function get() { return this.a; } // this MUST be used for instance variables though as they do not exist in static lookup
			function test() { return foo(); } // I did NOT use `this` here which means it does STATIC lookup!
							// kinda like mixin templates in D lol.
			var a = 5;
			static var b = 10; // static vars are attached to the class specifically
		}
		class Child : Base {
			function foo() {
				assert(super.foo() == "Base");
				return "Child";
			};
			function set() { this.a = 7; }
			function get2() { return this.a; }
			var a = 9;
		}

		var c = new Child();
		assert(c.foo() == "Child");

		assert(c.test() == "Base"); // static lookup of methods if you don't use `this`

		/*
		// these would pass in D, but do NOT pass here because of dynamic variable lookup in script.
		assert(c.get() == 5);
		assert(c.get2() == 9);
		c.set();
		assert(c.get() == 5); // parent instance is separate
		assert(c.get2() == 7);
		*/

		// showing the shared vars now.... I personally prefer the D way but meh, this lang
		// is an unholy cross of D and Javascript so that means it sucks sometimes.
		assert(c.get() == c.get2());
		c.set();
		assert(c.get2() == 7);
		assert(c.get() == c.get2());

		// super, on the other hand, must always be looked up statically, or else this
		// next example with infinite recurse and smash the stack.
		class Third : Child { }
		var t = new Third();
		assert(t.foo() == "Child");
	}, globals);
}

/++
	$(H3 Properties from D)

	Note that it is not possible yet to define a property function from the script language.
+/
unittest {
	static class Test {
		// the @scriptable is required to make it accessible
		@scriptable int a;

		@scriptable @property int ro() { return 30; }

		int _b = 20;
		@scriptable @property int b() { return _b; }
		@scriptable @property int b(int val) { return _b = val; }
	}

	Test test = new Test;

	test.a = 15;

	var globals = var.emptyObject;
	globals.test = test;
	// but once it is @scriptable, both read and write works from here:
	interpret(q{
		assert(test.a == 15);
		test.a = 10;
		assert(test.a == 10);

		assert(test.ro == 30); // @property functions from D wrapped too
		test.ro = 40;
		assert(test.ro == 30); // setting it does nothing though

		assert(test.b == 20); // reader still works if read/write available too
		test.b = 25;
		assert(test.b == 25); // writer action reflected

		// however other opAssign operators are not implemented correctly on properties at this time so this fails!
		//test.b *= 2;
		//assert(test.b == 50);
	}, globals);

	// and update seen back in D
	assert(test.a == 10); // on the original native object
	assert(test.b == 25);

	assert(globals.test.a == 10); // and via the var accessor for member var
	assert(globals.test.b == 25); // as well as @property func
}


public import arsd.jsvar;

import std.stdio;
import std.traits;
import std.conv;
import std.json;

import std.array;
import std.range;

/* **************************************
  script to follow
****************************************/

/++
	A base class for exceptions that can never be caught by scripts;
	throwing it from a function called from a script is guaranteed to
	bubble all the way up to your [interpret] call..
	(scripts can also never catch Error btw)

	History:
		Added on April 24, 2020 (v7.3.0)
+/
class NonScriptCatchableException : Exception {
	import std.exception;
	///
	mixin basicExceptionCtors;
}

//class TEST : Throwable {this() { super("lol"); }}

/// Thrown on script syntax errors and the sort.
class ScriptCompileException : Exception {
	string s;
	int lineNumber;
	this(string msg, string s, int lineNumber, string file = __FILE__, size_t line = __LINE__) {
		this.s = s;
		this.lineNumber = lineNumber;
		super(to!string(lineNumber) ~ ": " ~ msg, file, line);
	}
}

/// Thrown on things like interpretation failures.
class ScriptRuntimeException : Exception {
	string s;
	int lineNumber;
	this(string msg, string s, int lineNumber, string file = __FILE__, size_t line = __LINE__) {
		this.s = s;
		this.lineNumber = lineNumber;
		super(to!string(lineNumber) ~ ": " ~ msg, file, line);
	}
}

/// This represents an exception thrown by `throw x;` inside the script as it is interpreted.
class ScriptException : Exception {
	///
	var payload;
	///
	ScriptLocation loc;
	///
	ScriptLocation[] callStack;
	this(var payload, ScriptLocation loc, string file = __FILE__, size_t line = __LINE__) {
		this.payload = payload;
		if(loc.scriptFilename.length == 0)
			loc.scriptFilename = "user_script";
		this.loc = loc;
		super(loc.scriptFilename ~ "@" ~ to!string(loc.lineNumber) ~ ": " ~ to!string(payload), file, line);
	}

	/*
	override string toString() {
		return loc.scriptFilename ~ "@" ~ to!string(loc.lineNumber) ~ ": " ~ payload.get!string ~ to!string(callStack);
	}
	*/

	// might be nice to take a D exception and put a script stack trace in there too......
	// also need toString to show the callStack
}

struct ScriptToken {
	enum Type { identifier, keyword, symbol, string, int_number, hex_number, binary_number, oct_number, float_number }
	Type type;
	string str;
	string scriptFilename;
	int lineNumber;

	string wasSpecial;
}

	// these need to be ordered from longest to shortest
	// some of these aren't actually used, like struct and goto right now, but I want them reserved for later
private enum string[] keywords = [
	"function", "continue",
	"__FILE__", "__LINE__", // these two are special to the lexer
	"foreach", "json!q{", "default", "finally",
	"return", "static", "struct", "import", "module", "assert", "switch",
	"while", "catch", "throw", "scope", "break", "class", "false", "mixin", "macro", "super",
	// "this" is just treated as just a magic identifier.....
	"auto", // provided as an alias for var right now, may change later
	"null", "else", "true", "eval", "goto", "enum", "case", "cast",
	"var", "for", "try", "new",
	"if", "do",
];
private enum string[] symbols = [
	">>>", // FIXME
	"//", "/*", "/+",
	"&&", "||",
	"+=", "-=", "*=", "/=", "~=",  "==", "<=", ">=","!=", "%=",
	"&=", "|=", "^=",
	"#{",
	"..",
	"<<", ">>", // FIXME
	"|>",
	"=>", // FIXME
	"?", ".",",",";",":",
	"[", "]", "{", "}", "(", ")",
	"&", "|", "^",
	"+", "-", "*", "/", "=", "<", ">","~","!","%"
];

// we need reference semantics on this all the time
class TokenStream(TextStream) {
	TextStream textStream;
	string text;
	int lineNumber = 1;
	string scriptFilename;

	void advance(ptrdiff_t size) {
		foreach(i; 0 .. size) {
			if(text.empty)
				break;
			if(text[0] == '\n')
				lineNumber ++;
			text = text[1 .. $];
			// text.popFront(); // don't want this because it pops too much trying to do its own UTF-8, which we already handled!
		}
	}

	this(TextStream ts, string fn) {
		textStream = ts;
		scriptFilename = fn;
		text = textStream.front;
		popFront;
	}

	ScriptToken next;

	// FIXME: might be worth changing this so i can peek far enough ahead to do () => expr lambdas.
	ScriptToken peek;
	bool peeked;
	void pushFront(ScriptToken f) {
		peek = f;
		peeked = true;
	}

	ScriptToken front() {
		if(peeked)
			return peek;
		else
			return next;
	}

	bool empty() {
		advanceSkips();
		return text.length == 0 && textStream.empty && !peeked;
	}

	int skipNext;
	void advanceSkips() {
		if(skipNext) {
			skipNext--;
			popFront();
		}
	}

	void popFront() {
		if(peeked) {
			peeked = false;
			return;
		}

		assert(!empty);
		mainLoop:
		while(text.length) {
			ScriptToken token;
			token.lineNumber = lineNumber;
			token.scriptFilename = scriptFilename;

			if(text[0] == ' ' || text[0] == '\t' || text[0] == '\n' || text[0] == '\r') {
				advance(1);
				continue;
			} else if(text[0] >= '0' && text[0] <= '9') {
				int radix = 10;
				if(text.length > 2 && text[0] == '0') {
					if(text[1] == 'x' || text[1] == 'X')
						radix = 16;
					if(text[1] == 'b')
						radix = 2;
					if(text[1] == 'o')
						radix = 8;

					if(radix != 10)
						text = text[2 .. $];
				}

				int pos;
				bool sawDot;
				while(pos < text.length && (
					(text[pos] >= '0' && text[pos] <= '9')
					|| (text[pos] >= 'A' && text[pos] <= 'F')
					|| (text[pos] >= 'a' && text[pos] <= 'f')
					|| text[pos] == '_'
					|| text[pos] == '.'
				)) {
					if(text[pos] == '.') {
						if(sawDot)
							break;
						else
							sawDot = true;
					}
					pos++;
				}

				if(text[pos - 1] == '.') {
					// This is something like "1.x", which is *not* a floating literal; it is UFCS on an int
					sawDot = false;
					pos --;
				}

				token.type = sawDot ? ScriptToken.Type.float_number : ScriptToken.Type.int_number;
				if(radix == 2) token.type = ScriptToken.Type.binary_number;
				if(radix == 8) token.type = ScriptToken.Type.oct_number;
				if(radix == 16) token.type = ScriptToken.Type.hex_number;
				token.str = text[0 .. pos];
				advance(pos);
			} else if((text[0] >= 'a' && text[0] <= 'z') || (text[0] == '_') || (text[0] >= 'A' && text[0] <= 'Z') || text[0] == '$') {
				bool found = false;
				foreach(keyword; keywords)
					if(text.length >= keyword.length && text[0 .. keyword.length] == keyword &&
						// making sure this isn't an identifier that starts with a keyword
						(text.length == keyword.length || !(
							(
								(text[keyword.length] >= '0' && text[keyword.length] <= '9') ||
								(text[keyword.length] >= 'a' && text[keyword.length] <= 'z') ||
								(text[keyword.length] == '_') ||
								(text[keyword.length] >= 'A' && text[keyword.length] <= 'Z')
							)
						)))
					{
						found = true;
						if(keyword == "__FILE__") {
							token.type = ScriptToken.Type.string;
							token.str = to!string(token.scriptFilename);
							token.wasSpecial = keyword;
						} else if(keyword == "__LINE__") {
							token.type = ScriptToken.Type.int_number;
							token.str = to!string(token.lineNumber);
							token.wasSpecial = keyword;
						} else {
							token.type = ScriptToken.Type.keyword;
							// auto is done as an alias to var in the lexer just so D habits work there too
							if(keyword == "auto") {
								token.str = "var";
								token.wasSpecial = keyword;
							} else
								token.str = keyword;
						}
						advance(keyword.length);
						break;
					}

				if(!found) {
					token.type = ScriptToken.Type.identifier;
					int pos;
					if(text[0] == '$')
						pos++;

					while(pos < text.length
						&& ((text[pos] >= 'a' && text[pos] <= 'z') ||
							(text[pos] == '_') ||
							//(pos != 0 && text[pos] == '-') || // allow mid-identifier dashes for this-kind-of-name. For subtraction, add a space.
							(text[pos] >= 'A' && text[pos] <= 'Z') ||
							(text[pos] >= '0' && text[pos] <= '9')))
					{
						pos++;
					}

					token.str = text[0 .. pos];
					advance(pos);
				}
			} else if(text[0] == '"' || text[0] == '\'' || text[0] == '`' ||
				// Also supporting double curly quoted strings: “foo” which nest. This is the utf 8 coding:
				(text.length >= 3 && text[0] == 0xe2 && text[1] == 0x80 && text[2] == 0x9c))
			{
				char end = text[0]; // support single quote and double quote strings the same
				int openCurlyQuoteCount = (end == 0xe2) ? 1 : 0;
				bool escapingAllowed = end != '`'; // `` strings are raw, they don't support escapes. the others do.
				token.type = ScriptToken.Type.string;
				int pos = openCurlyQuoteCount ? 3 : 1; // skip the opening dchar
				int started = pos;
				bool escaped = false;
				bool mustCopy = false;

				bool allowInterpolation = text[0] == '"';

				bool atEnd() {
					if(pos == text.length)
						return false;
					if(openCurlyQuoteCount) {
						if(openCurlyQuoteCount == 1)
							return (pos + 3 <= text.length && text[pos] == 0xe2 && text[pos+1] == 0x80 && text[pos+2] == 0x9d); // ”
						else // greater than one means we nest
							return false;
					} else
						return text[pos] == end;
				}

				bool interpolationDetected = false;
				bool inInterpolate = false;
				int interpolateCount = 0;

				while(pos < text.length && (escaped || inInterpolate || !atEnd())) {
					if(inInterpolate) {
						if(text[pos] == '{')
							interpolateCount++;
						else if(text[pos] == '}') {
							interpolateCount--;
							if(interpolateCount == 0)
								inInterpolate = false;
						}
						pos++;
						continue;
					}

					if(escaped) {
						mustCopy = true;
						escaped = false;
					} else {
						if(text[pos] == '\\' && escapingAllowed)
							escaped = true;
						if(allowInterpolation && text[pos] == '#' && pos + 1 < text.length  && text[pos + 1] == '{') {
							interpolationDetected = true;
							inInterpolate = true;
						}
						if(openCurlyQuoteCount) {
							// also need to count curly quotes to support nesting
							if(pos + 3 <= text.length && text[pos+0] == 0xe2 && text[pos+1] == 0x80 && text[pos+2] == 0x9c) // “
								openCurlyQuoteCount++;
							if(pos + 3 <= text.length && text[pos+0] == 0xe2 && text[pos+1] == 0x80 && text[pos+2] == 0x9d) // ”
								openCurlyQuoteCount--;
						}
					}
					pos++;
				}

				if(pos == text.length && (escaped || inInterpolate || !atEnd()))
					throw new ScriptCompileException("Unclosed string literal", token.scriptFilename, token.lineNumber);

				if(mustCopy) {
					// there must be something escaped in there, so we need
					// to copy it and properly handle those cases
					string copy;
					copy.reserve(pos + 4);

					escaped = false;
					int readingUnicode;
					dchar uniChar = 0;

					int hexCharToInt(dchar ch) {
						if(ch >= '0' && ch <= '9')
							return ch - '0';
						if(ch >= 'a' && ch <= 'f')
							return ch - 'a' + 10;
						if(ch >= 'A' && ch <= 'F')
							return ch - 'A' + 10;
						throw new ScriptCompileException("Invalid hex char in \\u unicode section: " ~ cast(char) ch, token.scriptFilename, token.lineNumber);
					}

					foreach(idx, dchar ch; text[started .. pos]) {
						if(readingUnicode) {
							if(readingUnicode == 4 && ch == '{') {
								readingUnicode = 5;
								continue;
							}
							if(readingUnicode == 5 && ch == '}') {
								readingUnicode = 1;
							} else {
								uniChar <<= 4;
								uniChar |= hexCharToInt(ch);
							}
							if(readingUnicode != 5)
								readingUnicode--;
							if(readingUnicode == 0)
								copy ~= uniChar;
							continue;
						}
						if(escaped) {
							escaped = false;
							switch(ch) {
								case '\\': copy ~= "\\"; break;
								case 'n': copy ~= "\n"; break;
								case 'r': copy ~= "\r"; break;
								case 'a': copy ~= "\a"; break;
								case 't': copy ~= "\t"; break;
								case '#': copy ~= "#"; break;
								case '"': copy ~= "\""; break;
								case 'u': readingUnicode = 4; uniChar = 0; break;
								case '\'': copy ~= "'"; break;
								default:
									throw new ScriptCompileException("Unknown escape char " ~ cast(char) ch, token.scriptFilename, token.lineNumber);
							}
							continue;
						} else if(ch == '\\') {
							escaped = true;
							continue;
						}
						copy ~= ch;
					}

					token.str = copy;
				} else {
					token.str = text[started .. pos];
				}
				if(interpolationDetected)
					token.wasSpecial = "\"";
				advance(pos + ((end == 0xe2) ? 3 : 1)); // skip the closing " too
			} else {
				// let's check all symbols
				bool found = false;
				foreach(symbol; symbols)
					if(text.length >= symbol.length && text[0 .. symbol.length] == symbol) {

						if(symbol == "//") {
							// one line comment
							int pos = 0;
							while(pos < text.length && text[pos] != '\n' && text[0] != '\r')
								pos++;
							advance(pos);
							continue mainLoop;
						} else if(symbol == "/*") {
							int pos = 0;
							while(pos + 1 < text.length && text[pos..pos+2] != "*/")
								pos++;

							if(pos + 1 == text.length)
								throw new ScriptCompileException("unclosed /* */ comment", token.scriptFilename, lineNumber);

							advance(pos + 2);
							continue mainLoop;

						} else if(symbol == "/+") {
							int open = 0;
							int pos = 0;
							while(pos + 1 < text.length) {
								if(text[pos..pos+2] == "/+") {
									open++;
									pos++;
								} else if(text[pos..pos+2] == "+/") {
									open--;
									pos++;
									if(open == 0)
										break;
								}
								pos++;
							}

							if(pos + 1 == text.length)
								throw new ScriptCompileException("unclosed /+ +/ comment", token.scriptFilename, lineNumber);

							advance(pos + 1);
							continue mainLoop;
						}
						// FIXME: documentation comments

						found = true;
						token.type = ScriptToken.Type.symbol;
						token.str = symbol;
						advance(symbol.length);
						break;
					}

				if(!found) {
					// FIXME: make sure this gives a valid utf-8 sequence
					throw new ScriptCompileException("unknown token " ~ text[0], token.scriptFilename, lineNumber);
				}
			}

			next = token;
			return;
		}

		textStream.popFront();
		if(!textStream.empty()) {
			text = textStream.front;
			goto mainLoop;
		}

		return;
	}

}

TokenStream!TextStream lexScript(TextStream)(TextStream textStream, string scriptFilename) if(is(ElementType!TextStream == string)) {
	return new TokenStream!TextStream(textStream, scriptFilename);
}

class MacroPrototype : PrototypeObject {
	var func;

	// macros are basically functions that get special treatment for their arguments
	// they are passed as AST objects instead of interpreted
	// calling an AST object will interpret it in the script
	this(var func) {
		this.func = func;
		this._properties["opCall"] = (var _this, var[] args) {
			return func.apply(_this, args);
		};
	}
}

alias helper(alias T) = T;
// alternative to virtual function for converting the expression objects to script objects
void addChildElementsOfExpressionToScriptExpressionObject(ClassInfo c, Expression _thisin, PrototypeObject sc, ref var obj) {
	foreach(itemName; __traits(allMembers, mixin(__MODULE__)))
	static if(__traits(compiles, __traits(getMember, mixin(__MODULE__), itemName))) {
		alias Class = helper!(__traits(getMember, mixin(__MODULE__), itemName));
		static if(is(Class : Expression)) if(c == typeid(Class)) {
			auto _this = cast(Class) _thisin;
			foreach(memberName; __traits(allMembers, Class)) {
				alias member = helper!(__traits(getMember, Class, memberName));

				static if(is(typeof(member) : Expression)) {
					auto lol = __traits(getMember, _this, memberName);
					if(lol is null)
						obj[memberName] = null;
					else
						obj[memberName] = lol.toScriptExpressionObject(sc);
				}
				static if(is(typeof(member) : Expression[])) {
					obj[memberName] = var.emptyArray;
					foreach(m; __traits(getMember, _this, memberName))
						if(m !is null)
							obj[memberName] ~= m.toScriptExpressionObject(sc);
						else
							obj[memberName] ~= null;
				}
				static if(is(typeof(member) : string) || is(typeof(member) : long) || is(typeof(member) : real) || is(typeof(member) : bool)) {
					obj[memberName] = __traits(getMember, _this, memberName);
				}
			}
		}
	}
}

struct InterpretResult {
	var value;
	PrototypeObject sc;
	enum FlowControl { Normal, Return, Continue, Break, Goto }
	FlowControl flowControl;
	string flowControlDetails; // which label
}

class Expression {
	abstract InterpretResult interpret(PrototypeObject sc);

	// this returns an AST object that can be inspected and possibly altered
	// by the script. Calling the returned object will interpret the object in
	// the original scope passed
	var toScriptExpressionObject(PrototypeObject sc) {
		var obj = var.emptyObject;

		obj["type"] = typeid(this).name;
		obj["toSourceCode"] = (var _this, var[] args) {
			Expression e = this;
			return var(e.toString());
		};
		obj["opCall"] = (var _this, var[] args) {
			Expression e = this;
			// FIXME: if they changed the properties in the
			// script, we should update them here too.
			return e.interpret(sc).value;
		};
		obj["interpolate"] = (var _this, var[] args) {
			StringLiteralExpression e = cast(StringLiteralExpression) this;
			if(!e)
				return var(null);
			return e.interpolate(args.length ? args[0] : var(null), sc);
		};


		// adding structure is going to be a little bit magical
		// I could have done this with a virtual function, but I'm lazy.
		addChildElementsOfExpressionToScriptExpressionObject(typeid(this), this, sc, obj);

		return obj;
	}

	string toInterpretedString(PrototypeObject sc) {
		return toString();
	}
}

class MixinExpression : Expression {
	Expression e1;
	this(Expression e1) {
		this.e1 = e1;
	}

	override string toString() { return "mixin(" ~ e1.toString() ~ ")"; }

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(.interpret(e1.interpret(sc).value.get!string ~ ";", sc), sc);
	}
}

class StringLiteralExpression : Expression {
	string content;
	bool allowInterpolation;

	ScriptToken token;

	override string toString() {
		import std.string : replace;
		return "\"" ~ content.replace(`\`, `\\`).replace("\"", "\\\"") ~ "\"";
	}

	this(ScriptToken token) {
		this.token = token;
		this(token.str);
		if(token.wasSpecial == "\"")
			allowInterpolation = true;

	}

	this(string s) {
		content = s;
	}

	var interpolate(var funcObj, PrototypeObject sc) {
		import std.string : indexOf;
		if(allowInterpolation) {
			string r;

			auto c = content;
			auto idx = c.indexOf("#{");
			while(idx != -1) {
				r ~= c[0 .. idx];
				c = c[idx + 2 .. $];
				idx = 0;
				int open = 1;
				while(idx < c.length) {
					if(c[idx] == '}')
						open--;
					else if(c[idx] == '{')
						open++;
					if(open == 0)
						break;
					idx++;
				}
				if(open != 0)
					throw new ScriptRuntimeException("Unclosed interpolation thing", token.scriptFilename, token.lineNumber);
				auto code = c[0 .. idx];

				var result = .interpret(code, sc);

				if(funcObj == var(null))
					r ~= result.get!string;
				else
					r ~= funcObj(result).get!string;

				c = c[idx + 1 .. $];
				idx = c.indexOf("#{");
			}

			r ~= c;
			return var(r);
		} else {
			return var(content);
		}
	}

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(interpolate(var(null), sc), sc);
	}
}

class BoolLiteralExpression : Expression {
	bool literal;
	this(string l) {
		literal = to!bool(l);
	}

	override string toString() { return to!string(literal); }

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(var(literal), sc);
	}
}

class IntLiteralExpression : Expression {
	long literal;

	this(string s, int radix) {
		literal = to!long(s.replace("_", ""), radix);
	}

	override string toString() { return to!string(literal); }

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(var(literal), sc);
	}
}
class FloatLiteralExpression : Expression {
	this(string s) {
		literal = to!real(s.replace("_", ""));
	}
	real literal;
	override string toString() { return to!string(literal); }
	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(var(literal), sc);
	}
}
class NullLiteralExpression : Expression {
	this() {}
	override string toString() { return "null"; }

	override InterpretResult interpret(PrototypeObject sc) {
		var n;
		return InterpretResult(n, sc);
	}
}
class NegationExpression : Expression {
	Expression e;
	this(Expression e) { this.e = e;}
	override string toString() { return "-" ~ e.toString(); }

	override InterpretResult interpret(PrototypeObject sc) {
		var n = e.interpret(sc).value;
		return InterpretResult(-n, sc);
	}
}
class NotExpression : Expression {
	Expression e;
	this(Expression e) { this.e = e;}
	override string toString() { return "!" ~ e.toString(); }

	override InterpretResult interpret(PrototypeObject sc) {
		var n = e.interpret(sc).value;
		return InterpretResult(var(!n), sc);
	}
}
class BitFlipExpression : Expression {
	Expression e;
	this(Expression e) { this.e = e;}
	override string toString() { return "~" ~ e.toString(); }

	override InterpretResult interpret(PrototypeObject sc) {
		var n = e.interpret(sc).value;
		// possible FIXME given the size. but it is fuzzy when dynamic..
		return InterpretResult(var(~(n.get!long)), sc);
	}
}

class ArrayLiteralExpression : Expression {
	this() {}

	override string toString() {
		string s = "[";
		foreach(i, ele; elements) {
			if(i) s ~= ", ";
			s ~= ele.toString();
		}
		s ~= "]";
		return s;
	}

	Expression[] elements;
	override InterpretResult interpret(PrototypeObject sc) {
		var n = var.emptyArray;
		foreach(i, element; elements)
			n[i] = element.interpret(sc).value;
		return InterpretResult(n, sc);
	}
}
class ObjectLiteralExpression : Expression {
	Expression[string] elements;

	override string toString() {
		string s = "#{";
		bool first = true;
		foreach(k, e; elements) {
			if(first)
				first = false;
			else
				s ~= ", ";

			s ~= "\"" ~ k ~ "\":"; // FIXME: escape if needed
			s ~= e.toString();
		}

		s ~= "}";
		return s;
	}

	PrototypeObject backing;
	this(PrototypeObject backing = null) {
		this.backing = backing;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var n;
		if(backing is null)
			n = var.emptyObject;
		else
			n._object = backing;

		foreach(k, v; elements)
			n[k] = v.interpret(sc).value;

		return InterpretResult(n, sc);
	}
}
class FunctionLiteralExpression : Expression {
	this() {
		// we want this to not be null at all when we're interpreting since it is used as a comparison for a magic operation
		if(DefaultArgumentDummyObject is null)
			DefaultArgumentDummyObject = new PrototypeObject();
	}

	this(VariableDeclaration args, Expression bod, PrototypeObject lexicalScope = null) {
		this();
		this.arguments = args;
		this.functionBody = bod;
		this.lexicalScope = lexicalScope;
	}

	override string toString() {
		string s = (isMacro ? "macro" : "function") ~ " (";
		if(arguments !is null)
			s ~= arguments.toString();

		s ~= ") ";
		s ~= functionBody.toString();
		return s;
	}

	/*
		function identifier (arg list) expression

		so
		var e = function foo() 10; // valid
		var e = function foo() { return 10; } // also valid

		// the return value is just the last expression's result that was evaluated
		// to return void, be sure to do a "return;" at the end of the function
	*/
	VariableDeclaration arguments;
	Expression functionBody; // can be a ScopeExpression btw

	PrototypeObject lexicalScope;

	bool isMacro;

	override InterpretResult interpret(PrototypeObject sc) {
		assert(DefaultArgumentDummyObject !is null);
		var v;
		v._metadata = new ScriptFunctionMetadata(this);
		v._function = (var _this, var[] args) {
			auto argumentsScope = new PrototypeObject();
			PrototypeObject scToUse;
			if(lexicalScope is null)
				scToUse = sc;
			else {
				scToUse = lexicalScope;
				scToUse._secondary = sc;
			}

			argumentsScope.prototype = scToUse;

			argumentsScope._getMember("this", false, false) = _this;
			argumentsScope._getMember("_arguments", false, false) = args;
			argumentsScope._getMember("_thisfunc", false, false) = v;

			if(arguments)
			foreach(i, identifier; arguments.identifiers) {
				argumentsScope._getMember(identifier, false, false); // create it in this scope...
				if(i < args.length && !(args[i].payloadType() == var.Type.Object && args[i]._payload._object is DefaultArgumentDummyObject))
					argumentsScope._getMember(identifier, false, true) = args[i];
				else
				if(arguments.initializers[i] !is null)
					argumentsScope._getMember(identifier, false, true) = arguments.initializers[i].interpret(sc).value;
			}

			if(functionBody !is null)
				return functionBody.interpret(argumentsScope).value;
			else {
				assert(0);
			}
		};
		if(isMacro) {
			var n = var.emptyObject;
			n._object = new MacroPrototype(v);
			v = n;
		}
		return InterpretResult(v, sc);
	}
}

class CastExpression : Expression {
	string type;
	Expression e1;

	override string toString() {
		return "cast(" ~ type ~ ") " ~ e1.toString();
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var n = e1.interpret(sc).value;
		switch(type) {
			foreach(possibleType; CtList!("int", "long", "float", "double", "real", "char", "dchar", "string", "int[]", "string[]", "float[]")) {
			case possibleType:
				n = mixin("cast(" ~ possibleType ~ ") n");
			break;
			}
			default:
				// FIXME, we can probably cast other types like classes here.
		}

		return InterpretResult(n, sc);
	}
}

class VariableDeclaration : Expression {
	string[] identifiers;
	Expression[] initializers;
	string[] typeSpecifiers;

	this() {}

	override string toString() {
		string s = "";
		foreach(i, ident; identifiers) {
			if(i)
				s ~= ", ";
			s ~= "var ";
			if(typeSpecifiers[i].length) {
				s ~= typeSpecifiers[i];
				s ~= " ";
			}
			s ~= ident;
			if(initializers[i] !is null)
				s ~= " = " ~ initializers[i].toString();
		}
		return s;
	}


	override InterpretResult interpret(PrototypeObject sc) {
		var n;

		foreach(i, identifier; identifiers) {
			n = sc._getMember(identifier, false, false);
			auto initializer = initializers[i];
			if(initializer) {
				n = initializer.interpret(sc).value;
				sc._getMember(identifier, false, false) = n;
			}
		}
		return InterpretResult(n, sc);
	}
}

class FunctionDeclaration : Expression {
	DotVarExpression where;
	string ident;
	FunctionLiteralExpression expr;

	this(DotVarExpression where, string ident, FunctionLiteralExpression expr) {
		this.where = where;
		this.ident = ident;
		this.expr = expr;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var n = expr.interpret(sc).value;

		var replacement;

		if(expr.isMacro) {
			// can't overload macros
			replacement = n;
		} else {
			var got;

			if(where is null) {
				got = sc._getMember(ident, false, false);
			} else {
				got = where.interpret(sc).value;
			}

			OverloadSet os = got.get!OverloadSet;
			if(os is null) {
				os = new OverloadSet;
			}

			os.addOverload(OverloadSet.Overload(expr.arguments ? toTypes(expr.arguments.typeSpecifiers, sc) : null, n));

			replacement = var(os);
		}

		if(where is null) {
			sc._getMember(ident, false, false) = replacement;
		} else {
			where.setVar(sc, replacement, false, true);
		}

		return InterpretResult(n, sc);
	}

	override string toString() {
		string s = (expr.isMacro ? "macro" : "function") ~ " ";
		s ~= ident;
		s ~= "(";
		if(expr.arguments !is null)
			s ~= expr.arguments.toString();

		s ~= ") ";
		s ~= expr.functionBody.toString();

		return s;
	}
}

template CtList(T...) { alias CtList = T; }

class BinaryExpression : Expression {
	string op;
	Expression e1;
	Expression e2;

	override string toString() {
		return e1.toString() ~ " " ~ op ~ " " ~ e2.toString();
	}

	override string toInterpretedString(PrototypeObject sc) {
		return e1.toInterpretedString(sc) ~ " " ~ op ~ " " ~ e2.toInterpretedString(sc);
	}

	this(string op, Expression e1, Expression e2) {
		this.op = op;
		this.e1 = e1;
		this.e2 = e2;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var left = e1.interpret(sc).value;
		var right = e2.interpret(sc).value;

		//writeln(left, " "~op~" ", right);

		var n;
		sw: switch(op) {
			// I would actually kinda prefer this to be static foreach, but normal
			// tuple foreach here has broaded compiler compatibility.
			foreach(ctOp; CtList!("+", "-", "*", "/", "==", "!=", "<=", ">=", ">", "<", "~", "&&", "||", "&", "|", "^", "%", ">>", "<<", ">>>")) // FIXME
			case ctOp: {
				n = mixin("left "~ctOp~" right");
				break sw;
			}
			default:
				assert(0, op);
		}

		return InterpretResult(n, sc);
	}
}

class OpAssignExpression : Expression {
	string op;
	Expression e1;
	Expression e2;

	this(string op, Expression e1, Expression e2) {
		this.op = op;
		this.e1 = e1;
		this.e2 = e2;
	}

	override string toString() {
		return e1.toString() ~ " " ~ op ~ "= " ~ e2.toString();
	}

	override InterpretResult interpret(PrototypeObject sc) {

		auto v = cast(VariableExpression) e1;
		if(v is null)
			throw new ScriptRuntimeException("not an lvalue", null, 0 /* FIXME */);

		var right = e2.interpret(sc).value;

		//writeln(left, " "~op~"= ", right);

		var n;
		foreach(ctOp; CtList!("+=", "-=", "*=", "/=", "~=", "&=", "|=", "^=", "%="))
			if(ctOp[0..1] == op)
				n = mixin("v.getVar(sc, true, true) "~ctOp~" right");

		// FIXME: ensure the variable is updated in scope too

		return InterpretResult(n, sc);

	}
}

class PipelineExpression : Expression {
	Expression e1;
	Expression e2;
	CallExpression ce;
	ScriptLocation loc;

	this(ScriptLocation loc, Expression e1, Expression e2) {
		this.loc = loc;
		this.e1 = e1;
		this.e2 = e2;

		if(auto ce = cast(CallExpression) e2) {
			this.ce = new CallExpression(loc, ce.func);
			this.ce.arguments = [e1] ~ ce.arguments;
		} else {
			this.ce = new CallExpression(loc, e2);
			this.ce.arguments ~= e1;
		}
	}

	override string toString() { return e1.toString() ~ " |> " ~ e2.toString(); }

	override InterpretResult interpret(PrototypeObject sc) {
		return ce.interpret(sc);
	}
}

class AssignExpression : Expression {
	Expression e1;
	Expression e2;
	bool suppressOverloading;

	this(Expression e1, Expression e2, bool suppressOverloading = false) {
		this.e1 = e1;
		this.e2 = e2;
		this.suppressOverloading = suppressOverloading;
	}

	override string toString() { return e1.toString() ~ " = " ~ e2.toString(); }

	override InterpretResult interpret(PrototypeObject sc) {
		auto v = cast(VariableExpression) e1;
		if(v is null)
			throw new ScriptRuntimeException("not an lvalue", null, 0 /* FIXME */);

		auto ret = v.setVar(sc, e2 is null ? var(null) : e2.interpret(sc).value, false, suppressOverloading);

		return InterpretResult(ret, sc);
	}
}
class VariableExpression : Expression {
	string identifier;
	ScriptLocation loc;

	this(string identifier, ScriptLocation loc = ScriptLocation.init) {
		this.identifier = identifier;
		this.loc = loc;
	}

	override string toString() {
		return identifier;
	}

	override string toInterpretedString(PrototypeObject sc) {
		return getVar(sc).get!string;
	}

	ref var getVar(PrototypeObject sc, bool recurse = true, bool returnRawProperty = false) {
		try {
			return sc._getMember(identifier, true /* FIXME: recurse?? */, true, returnRawProperty);
		} catch(DynamicTypeException dte) {
			dte.callStack ~= loc;
			throw dte;
		}
	}

	ref var setVar(PrototypeObject sc, var t, bool recurse = true, bool suppressOverloading = false) {
		return sc._setMember(identifier, t, true /* FIXME: recurse?? */, true, suppressOverloading);
	}

	ref var getVarFrom(PrototypeObject sc, ref var v, bool returnRawProperty) {
		if(returnRawProperty) {
			if(v.payloadType == var.Type.Object)
				return v._payload._object._getMember(identifier, true, false, returnRawProperty);
		}

		return v[identifier];
	}

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(getVar(sc), sc);
	}
}

class SuperExpression : Expression {
	VariableExpression dot;
	string origDot;
	this(VariableExpression dot) {
		if(dot !is null) {
			origDot = dot.identifier;
			//dot.identifier = "__super_" ~ dot.identifier; // omg this is so bad
		}
		this.dot = dot;
	}

	override string toString() {
		if(dot is null)
			return "super";
		else
			return "super." ~ origDot;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var a = sc._getMember("super", true, true);
		if(a._object is null)
			throw new Exception("null proto for super");
		PrototypeObject proto = a._object.prototype;
		if(proto is null)
			throw new Exception("no super");
		//proto = proto.prototype;

		if(dot !is null)
			a = proto._getMember(dot.identifier, true, true);
		else
			a = proto._getMember("__ctor", true, true);
		return InterpretResult(a, sc);
	}
}

class DotVarExpression : VariableExpression {
	Expression e1;
	VariableExpression e2;
	bool recurse = true;

	this(Expression e1) {
		this.e1 = e1;
		super(null);
	}

	this(Expression e1, VariableExpression e2, bool recurse = true) {
		this.e1 = e1;
		this.e2 = e2;
		this.recurse = recurse;
		//assert(typeid(e2) == typeid(VariableExpression));
		super("<do not use>");//e1.identifier ~ "." ~ e2.identifier);
	}

	override string toString() {
		return e1.toString() ~ "." ~ e2.toString();
	}

	override ref var getVar(PrototypeObject sc, bool recurse = true, bool returnRawProperty = false) {
		if(!this.recurse) {
			// this is a special hack...
			if(auto ve = cast(VariableExpression) e1) {
				return ve.getVar(sc)._getOwnProperty(e2.identifier);
			}
			assert(0);
		}

		if(e2.identifier == "__source") {
			auto val = e1.interpret(sc).value;
			if(auto meta = cast(ScriptFunctionMetadata) val._metadata)
				return *(new var(meta.convertToString()));
			else
				return *(new var(val.toJson()));
		}

		if(auto ve = cast(VariableExpression) e1) {
			return this.getVarFrom(sc, ve.getVar(sc, recurse), returnRawProperty);
		} else if(cast(StringLiteralExpression) e1 && e2.identifier == "interpolate") {
			auto se = cast(StringLiteralExpression) e1;
			var* functor = new var;
			//if(!se.allowInterpolation)
				//throw new ScriptRuntimeException("Cannot interpolate this string", se.token.lineNumber);
			(*functor)._function = (var _this, var[] args) {
				return se.interpolate(args.length ? args[0] : var(null), sc);
			};
			return *functor;
		} else {
			// make a temporary for the lhs
			auto v = new var();
			*v = e1.interpret(sc).value;
			return this.getVarFrom(sc, *v, returnRawProperty);
		}
	}

	override ref var setVar(PrototypeObject sc, var t, bool recurse = true, bool suppressOverloading = false) {
		if(suppressOverloading)
			return e1.interpret(sc).value.opIndexAssignNoOverload(t, e2.identifier);
		else
			return e1.interpret(sc).value.opIndexAssign(t, e2.identifier);
	}


	override ref var getVarFrom(PrototypeObject sc, ref var v, bool returnRawProperty) {
		return e2.getVarFrom(sc, v, returnRawProperty);
	}

	override string toInterpretedString(PrototypeObject sc) {
		return getVar(sc).get!string;
	}
}

class IndexExpression : VariableExpression {
	Expression e1;
	Expression e2;

	this(Expression e1, Expression e2) {
		this.e1 = e1;
		this.e2 = e2;
		super(null);
	}

	override string toString() {
		return e1.toString() ~ "[" ~ e2.toString() ~ "]";
	}

	override ref var getVar(PrototypeObject sc, bool recurse = true, bool returnRawProperty = false) {
		if(auto ve = cast(VariableExpression) e1)
			return ve.getVar(sc, recurse, returnRawProperty)[e2.interpret(sc).value];
		else {
			auto v = new var();
			*v = e1.interpret(sc).value;
			return this.getVarFrom(sc, *v, returnRawProperty);
		}
	}

	override ref var setVar(PrototypeObject sc, var t, bool recurse = true, bool suppressOverloading = false) {
        	return getVar(sc,recurse) = t;
	}
}

class SliceExpression : Expression {
	// e1[e2 .. e3]
	Expression e1;
	Expression e2;
	Expression e3;

	this(Expression e1, Expression e2, Expression e3) {
		this.e1 = e1;
		this.e2 = e2;
		this.e3 = e3;
	}

	override string toString() {
		return e1.toString() ~ "[" ~ e2.toString() ~ " .. " ~ e3.toString() ~ "]";
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var lhs = e1.interpret(sc).value;

		auto specialScope = new PrototypeObject();
		specialScope.prototype = sc;
		specialScope._getMember("$", false, false) = lhs.length;

		return InterpretResult(lhs[e2.interpret(specialScope).value .. e3.interpret(specialScope).value], sc);
	}
}


class LoopControlExpression : Expression {
	InterpretResult.FlowControl op;
	this(string op) {
		if(op == "continue")
			this.op = InterpretResult.FlowControl.Continue;
		else if(op == "break")
			this.op = InterpretResult.FlowControl.Break;
		else assert(0, op);
	}

	override string toString() {
		import std.string;
		return to!string(this.op).toLower();
	}

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(var(null), sc, op);
	}
}


class ReturnExpression : Expression {
	Expression value;

	this(Expression v) {
		value = v;
	}

	override string toString() { return "return " ~ value.toString(); }

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(value.interpret(sc).value, sc, InterpretResult.FlowControl.Return);
	}
}

class ScopeExpression : Expression {
	this(Expression[] expressions) {
		this.expressions = expressions;
	}

	Expression[] expressions;

	override string toString() {
		string s;
		s = "{\n";
		foreach(expr; expressions) {
			s ~= "\t";
			s ~= expr.toString();
			s ~= ";\n";
		}
		s ~= "}";
		return s;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var ret;

		auto innerScope = new PrototypeObject();
		innerScope.prototype = sc;

		innerScope._getMember("__scope_exit", false, false) = var.emptyArray;
		innerScope._getMember("__scope_success", false, false) = var.emptyArray;
		innerScope._getMember("__scope_failure", false, false) = var.emptyArray;

		scope(exit) {
			foreach(func; innerScope._getMember("__scope_exit", false, true))
				func();
		}
		scope(success) {
			foreach(func; innerScope._getMember("__scope_success", false, true))
				func();
		}
		scope(failure) {
			foreach(func; innerScope._getMember("__scope_failure", false, true))
				func();
		}

		foreach(expression; expressions) {
			auto res = expression.interpret(innerScope);
			ret = res.value;
			if(res.flowControl != InterpretResult.FlowControl.Normal)
				return InterpretResult(ret, sc, res.flowControl);
		}
		return InterpretResult(ret, sc);
	}
}

class SwitchExpression : Expression {
	Expression expr;
	CaseExpression[] cases;
	CaseExpression default_;

	override InterpretResult interpret(PrototypeObject sc) {
		auto e = expr.interpret(sc);

		bool hitAny;
		bool fallingThrough;
		bool secondRun;

		var last;

		again:
		foreach(c; cases) {
			if(!secondRun && !fallingThrough && c is default_) continue;
			if(fallingThrough || (secondRun && c is default_) || c.condition.interpret(sc) == e) {
				fallingThrough = false;
				if(!secondRun)
					hitAny = true;
				InterpretResult ret;
				expr_loop: foreach(exp; c.expressions) {
					ret = exp.interpret(sc);
					with(InterpretResult.FlowControl)
					final switch(ret.flowControl) {
						case Normal:
							last = ret.value;
						break;
						case Return:
						case Goto:
							return ret;
						case Continue:
							fallingThrough = true;
							break expr_loop;
						case Break:
							return InterpretResult(last, sc);
					}
				}

				if(!fallingThrough)
					break;
			}
		}

		if(!hitAny && !secondRun) {
			secondRun = true;
			goto again;
		}

		return InterpretResult(last, sc);
	}
}

class CaseExpression : Expression {
	this(Expression condition) {
		this.condition = condition;
	}
	Expression condition;
	Expression[] expressions;

	override string toString() {
		string code;
		if(condition is null)
			code = "default:";
		else
			code = "case " ~ condition.toString() ~ ":";

		foreach(expr; expressions)
			code ~= "\n" ~ expr.toString() ~ ";";

		return code;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		// I did this inline up in the SwitchExpression above. maybe insane?!
		assert(0);
	}
}

unittest {
	interpret(q{
		var a = 10;
		// case and break should work
		var brk;

		// var brk = switch doesn't parse, but this will.....
		// (I kinda went everything is an expression but not all the way. this code SUX.)
		brk = switch(a) {
			case 10:
				a = 30;
			break;
			case 30:
				a = 40;
			break;
			default:
				a = 0;
		}

		assert(a == 30);
		assert(brk == 30); // value of switch set to last expression evaled inside

		// so should default
		switch(a) {
			case 20:
				a = 40;
			break;
			default:
				a = 40;
		}

		assert(a == 40);

		switch(a) {
			case 40:
				a = 50;
			case 60: // no implicit fallthrough in this lang...
				a = 60;
		}

		assert(a == 50);

		var ret;

		ret = switch(a) {
			case 50:
				a = 60;
				continue; // request fallthrough. D uses "goto case", but I haven't implemented any goto yet so continue is best fit
			case 90:
				a = 70;
		}

		assert(a == 70); // the explicit `continue` requests fallthrough behavior
		assert(ret == 70);
	});
}

unittest {
	// overloads
	interpret(q{
		function foo(int a) { return 10 + a; }
		function foo(float a) { return 100 + a; }
		function foo(string a) { return "string " ~ a; }

		assert(foo(4) == 14);
		assert(foo(4.5) == 104.5);
		assert(foo("test") == "string test");

		// can redefine specific override
		function foo(int a) { return a; }
		assert(foo(4) == 4);
		// leaving others in place
		assert(foo(4.5) == 104.5);
		assert(foo("test") == "string test");
	});
}

unittest {
	// catching objects
	interpret(q{
		class Foo {}
		class Bar : Foo {}

		var res = try throw new Bar(); catch(Bar b) { 2 } catch(e) { 1 };
		assert(res == 2);

		var res = try throw new Foo(); catch(Bar b) { 2 } catch(e) { 1 };
		assert(res == 1);

		var res = try throw Foo; catch(Foo b) { 2 } catch(e) { 1 };
		assert(res == 2);
	});
}

unittest {
	// ternary precedence
	interpret(q{
		assert(0 == 0 ? true : false == true);
		assert((0 == 0) ? true : false == true);
		// lol FIXME
		//assert(((0 == 0) ? true : false) == true);
	});
}

unittest {
	// new nested class
	interpret(q{
		class A {}
		A.b = class B { var c; this(a) { this.c = a; } }
		var c = new A.b(5);
		assert(A.b.c == null);
		assert(c.c == 5);
	});
}

unittest {
	interpret(q{
		assert(0x10 == 16);
		assert(0o10 == 8);
		assert(0b10 == 2);
		assert(10 == 10);
		assert(10_10 == 1010);
	});
}

class ForeachExpression : Expression {
	VariableDeclaration decl;
	Expression subject;
	Expression subject2;
	Expression loopBody;

	override string toString() {
		return "foreach(" ~ decl.toString() ~ "; " ~ subject.toString() ~ ((subject2 is null) ? "" : (".." ~ subject2.toString)) ~ ") " ~ loopBody.toString();
	}

	override InterpretResult interpret(PrototypeObject sc) {
		var result;

		assert(loopBody !is null);

		auto loopScope = new PrototypeObject();
		loopScope.prototype = sc;

		InterpretResult.FlowControl flowControl;

		static string doLoopBody() { return q{
			if(decl.identifiers.length > 1) {
				sc._getMember(decl.identifiers[0], false, false) = i;
				sc._getMember(decl.identifiers[1], false, false) = item;
			} else {
				sc._getMember(decl.identifiers[0], false, false) = item;
			}

			auto res = loopBody.interpret(loopScope);
			result = res.value;
			flowControl = res.flowControl;
			if(flowControl == InterpretResult.FlowControl.Break)
				break;
			if(flowControl == InterpretResult.FlowControl.Return)
				break;
			//if(flowControl == InterpretResult.FlowControl.Continue)
				// this is fine, we still want to do the advancement
		};}

		var what = subject.interpret(sc).value;
		var termination = subject2 is null ? var(null) : subject2.interpret(sc).value;
		if(what.payloadType == var.Type.Integral && subject2 is null) {
			// loop from 0 to what
			int end = what.get!int;
			foreach(item; 0 .. end) {
				auto i = item;
				mixin(doLoopBody());
			}
		} else if(what.payloadType == var.Type.Integral && termination.payloadType == var.Type.Integral) {
			// loop what .. termination
			int start = what.get!int;
			int end = termination.get!int;
			int stride;
			if(end < start) {
				stride = -1;
			} else {
				stride = 1;
			}
			int i = -1;
			for(int item = start; item != end; item += stride) {
				i++;
				mixin(doLoopBody());
			}
		} else {
			if(subject2 !is null)
				throw new ScriptRuntimeException("foreach( a .. b ) invalid unless a is an integer", null, 0); // FIXME
			foreach(i, item; what) {
				mixin(doLoopBody());
			}
		}

		if(flowControl != InterpretResult.FlowControl.Return)
			flowControl = InterpretResult.FlowControl.Normal;

		return InterpretResult(result, sc, flowControl);
	}
}

class ForExpression : Expression {
	Expression initialization;
	Expression condition;
	Expression advancement;
	Expression loopBody;

	this() {}

	override InterpretResult interpret(PrototypeObject sc) {
		var result;

		assert(loopBody !is null);

		auto loopScope = new PrototypeObject();
		loopScope.prototype = sc;
		if(initialization !is null)
			initialization.interpret(loopScope);

		InterpretResult.FlowControl flowControl;

		static string doLoopBody() { return q{
			auto res = loopBody.interpret(loopScope);
			result = res.value;
			flowControl = res.flowControl;
			if(flowControl == InterpretResult.FlowControl.Break)
				break;
			if(flowControl == InterpretResult.FlowControl.Return)
				break;
			//if(flowControl == InterpretResult.FlowControl.Continue)
				// this is fine, we still want to do the advancement
			if(advancement)
				advancement.interpret(loopScope);
		};}

		if(condition !is null) {
			while(condition.interpret(loopScope).value) {
				mixin(doLoopBody());
			}
		} else
			while(true) {
				mixin(doLoopBody());
			}

		if(flowControl != InterpretResult.FlowControl.Return)
			flowControl = InterpretResult.FlowControl.Normal;

		return InterpretResult(result, sc, flowControl);
	}

	override string toString() {
		string code = "for(";
		if(initialization !is null)
			code ~= initialization.toString();
		code ~= "; ";
		if(condition !is null)
			code ~= condition.toString();
		code ~= "; ";
		if(advancement !is null)
			code ~= advancement.toString();
		code ~= ") ";
		code ~= loopBody.toString();

		return code;
	}
}

class IfExpression : Expression {
	Expression condition;
	Expression ifTrue;
	Expression ifFalse;

	this() {}

	override InterpretResult interpret(PrototypeObject sc) {
		InterpretResult result;
		assert(condition !is null);

		auto ifScope = new PrototypeObject();
		ifScope.prototype = sc;

		if(condition.interpret(ifScope).value) {
			if(ifTrue !is null)
				result = ifTrue.interpret(ifScope);
		} else {
			if(ifFalse !is null)
				result = ifFalse.interpret(ifScope);
		}
		return InterpretResult(result.value, sc, result.flowControl);
	}

	override string toString() {
		string code = "if ";
		code ~= condition.toString();
		code ~= " ";
		if(ifTrue !is null)
			code ~= ifTrue.toString();
		else
			code ~= " { }";
		if(ifFalse !is null)
			code ~= " else " ~ ifFalse.toString();
		return code;
	}
}

class TernaryExpression : Expression {
	Expression condition;
	Expression ifTrue;
	Expression ifFalse;

	this() {}

	override InterpretResult interpret(PrototypeObject sc) {
		InterpretResult result;
		assert(condition !is null);

		auto ifScope = new PrototypeObject();
		ifScope.prototype = sc;

		if(condition.interpret(ifScope).value) {
			result = ifTrue.interpret(ifScope);
		} else {
			result = ifFalse.interpret(ifScope);
		}
		return InterpretResult(result.value, sc, result.flowControl);
	}

	override string toString() {
		string code = "";
		code ~= condition.toString();
		code ~= " ? ";
		code ~= ifTrue.toString();
		code ~= " : ";
		code ~= ifFalse.toString();
		return code;
	}
}

// this is kinda like a placement new, and currently isn't exposed inside the language,
// but is used for class inheritance
class ShallowCopyExpression : Expression {
	Expression e1;
	Expression e2;

	this(Expression e1, Expression e2) {
		this.e1 = e1;
		this.e2 = e2;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		auto v = cast(VariableExpression) e1;
		if(v is null)
			throw new ScriptRuntimeException("not an lvalue", null, 0 /* FIXME */);

		v.getVar(sc, false)._object.copyPropertiesFrom(e2.interpret(sc).value._object);

		return InterpretResult(var(null), sc);
	}

}

class NewExpression : Expression {
	Expression what;
	Expression[] args;
	this(Expression w) {
		what = w;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		assert(what !is null);

		var[] args;
		foreach(arg; this.args)
			args ~= arg.interpret(sc).value;

		var original = what.interpret(sc).value;
		var n = original._copy_new;
		if(n.payloadType() == var.Type.Object) {
			var ctor = original.prototype ? original.prototype._getOwnProperty("__ctor") : var(null);
			if(ctor)
				ctor.apply(n, args);
		}

		return InterpretResult(n, sc);
	}
}

class ThrowExpression : Expression {
	Expression whatToThrow;
	ScriptToken where;

	this(Expression e, ScriptToken where) {
		whatToThrow = e;
		this.where = where;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		assert(whatToThrow !is null);
		throw new ScriptException(whatToThrow.interpret(sc).value, ScriptLocation(where.scriptFilename, where.lineNumber));
		assert(0);
	}
}

bool isCompatibleType(var v, string specifier, PrototypeObject sc) {
	var t = toType(specifier, sc);
	auto score = typeCompatibilityScore(v, t);
	return score > 0;
}

var toType(string specifier, PrototypeObject sc) {
	switch(specifier) {
		case "int", "long": return var(0);
		case "float", "double": return var(0.0);
		case "string": return var("");
		default:
			auto got = sc._peekMember(specifier, true);
			if(got)
				return *got;
			else
				return var.init;
	}
}

var[] toTypes(string[] specifiers, PrototypeObject sc) {
	var[] arr;
	foreach(s; specifiers)
		arr ~= toType(s, sc);
	return arr;
}


class ExceptionBlockExpression : Expression {
	Expression tryExpression;

	string[] catchVarDecls;
	string[] catchVarTypeSpecifiers;
	Expression[] catchExpressions;

	Expression[] finallyExpressions;

	override InterpretResult interpret(PrototypeObject sc) {
		InterpretResult result;
		result.sc = sc;
		assert(tryExpression !is null);
		assert(catchVarDecls.length == catchExpressions.length);

		void caught(var ex) {
			if(catchExpressions.length)
			foreach(i, ce; catchExpressions) {
				if(catchVarTypeSpecifiers[i].length == 0 || isCompatibleType(ex, catchVarTypeSpecifiers[i], sc)) {
					auto catchScope = new PrototypeObject();
					catchScope.prototype = sc;
					catchScope._getMember(catchVarDecls[i], false, false) = ex;

					result = ce.interpret(catchScope);
					break;
				}
			} else
				result = InterpretResult(ex, sc);
		}

		if(catchExpressions.length || (catchExpressions.length == 0 && finallyExpressions.length == 0))
			try {
				result = tryExpression.interpret(sc);
			} catch(NonScriptCatchableException e) {
				// the script cannot catch these so it continues up regardless
				throw e;
			} catch(ScriptException e) {
				// FIXME: what about the other information here? idk.
				caught(e.payload);
			} catch(Exception e) {
				var ex = var.emptyObject;
				ex.type = typeid(e).name;
				ex.msg = e.msg;
				ex.file = e.file;
				ex.line = e.line;

				caught(ex);
			} finally {
				foreach(fe; finallyExpressions)
					result = fe.interpret(sc);
			}
		else
			try {
				result = tryExpression.interpret(sc);
			} finally {
				foreach(fe; finallyExpressions)
					result = fe.interpret(sc);
			}

		return result;
	}
}

class ParentheticalExpression : Expression {
	Expression inside;
	this(Expression inside) {
		this.inside = inside;
	}

	override string toString() {
		return "(" ~ inside.toString() ~ ")";
	}

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(inside.interpret(sc).value, sc);
	}
}

class AssertKeyword : Expression {
	ScriptToken token;
	this(ScriptToken token) {
		this.token = token;
	}
	override string toString() {
		return "assert";
	}

	override InterpretResult interpret(PrototypeObject sc) {
		if(AssertKeywordObject is null)
			AssertKeywordObject = new PrototypeObject();
		var dummy;
		dummy._object = AssertKeywordObject;
		return InterpretResult(dummy, sc);
	}
}

PrototypeObject AssertKeywordObject;
PrototypeObject DefaultArgumentDummyObject;

class CallExpression : Expression {
	Expression func;
	Expression[] arguments;
	ScriptLocation loc;

	override string toString() {
		string s = func.toString() ~ "(";
		foreach(i, arg; arguments) {
			if(i) s ~= ", ";
			s ~= arg.toString();
		}

		s ~= ")";
		return s;
	}

	this(ScriptLocation loc, Expression func) {
		this.loc = loc;
		this.func = func;
	}

	override string toInterpretedString(PrototypeObject sc) {
		return interpret(sc).value.get!string;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		if(auto asrt = cast(AssertKeyword) func) {
			auto assertExpression = arguments[0];
			Expression assertString;
			if(arguments.length > 1)
				assertString = arguments[1];

			var v = assertExpression.interpret(sc).value;

			if(!v)
				throw new ScriptException(
					var(this.toString() ~ " failed, got: " ~ assertExpression.toInterpretedString(sc)),
					ScriptLocation(asrt.token.scriptFilename, asrt.token.lineNumber));

			return InterpretResult(v, sc);
		}

		auto f = func.interpret(sc).value;
		bool isMacro =  (f.payloadType == var.Type.Object && ((cast(MacroPrototype) f._payload._object) !is null));
		var[] args;
		foreach(argument; arguments)
			if(argument !is null) {
				if(isMacro) // macro, pass the argument as an expression object
					args ~= argument.toScriptExpressionObject(sc);
				else // regular function, interpret the arguments
					args ~= argument.interpret(sc).value;
			} else {
				if(DefaultArgumentDummyObject is null)
					DefaultArgumentDummyObject = new PrototypeObject();

				var dummy;
				dummy._object = DefaultArgumentDummyObject;

				args ~= dummy;
			}

		var _this;
		if(auto dve = cast(DotVarExpression) func) {
			_this = dve.e1.interpret(sc).value;
		} else if(auto ide = cast(IndexExpression) func) {
			_this = ide.interpret(sc).value;
		} else if(auto se = cast(SuperExpression) func) {
			// super things are passed this object despite looking things up on the prototype
			// so it calls the correct instance
			_this = sc._getMember("this", true, true);
		}

		try {
			return InterpretResult(f.apply(_this, args), sc);
		} catch(DynamicTypeException dte) {
			dte.callStack ~= loc;
			throw dte;
		} catch(ScriptException se) {
			se.callStack ~= loc;
			throw se;
		}
	}
}

ScriptToken requireNextToken(MyTokenStreamHere)(ref MyTokenStreamHere tokens, ScriptToken.Type type, string str = null, string file = __FILE__, size_t line = __LINE__) {
	if(tokens.empty)
		throw new ScriptCompileException("script ended prematurely", null, 0, file, line);
	auto next = tokens.front;
	if(next.type != type || (str !is null && next.str != str))
		throw new ScriptCompileException("unexpected '"~next.str~"' while expecting " ~ to!string(type) ~ " " ~ str, next.scriptFilename, next.lineNumber, file, line);

	tokens.popFront();
	return next;
}

bool peekNextToken(MyTokenStreamHere)(MyTokenStreamHere tokens, ScriptToken.Type type, string str = null, string file = __FILE__, size_t line = __LINE__) {
	if(tokens.empty)
		return false;
	auto next = tokens.front;
	if(next.type != type || (str !is null && next.str != str))
		return false;
	return true;
}

VariableExpression parseVariableName(MyTokenStreamHere)(ref MyTokenStreamHere tokens) {
	assert(!tokens.empty);
	auto token = tokens.front;
	if(token.type == ScriptToken.Type.identifier) {
		tokens.popFront();
		return new VariableExpression(token.str, ScriptLocation(token.scriptFilename, token.lineNumber));
	}
	throw new ScriptCompileException("Found "~token.str~" when expecting identifier", token.scriptFilename, token.lineNumber);
}

Expression parseDottedVariableName(MyTokenStreamHere)(ref MyTokenStreamHere tokens) {
	assert(!tokens.empty);

	auto ve = parseVariableName(tokens);

	auto token = tokens.front;
	if(token.type == ScriptToken.Type.symbol && token.str == ".") {
		tokens.popFront();
		return new DotVarExpression(ve, parseVariableName(tokens));
	}
	return ve;
}


Expression parsePart(MyTokenStreamHere)(ref MyTokenStreamHere tokens) {
	if(!tokens.empty) {
		auto token = tokens.front;

		Expression e;

		if(token.str == "super") {
			tokens.popFront();
			VariableExpression dot;
			if(!tokens.empty && tokens.front.str == ".") {
				tokens.popFront();
				dot = parseVariableName(tokens);
			}
			e = new SuperExpression(dot);
		}
		else if(token.type == ScriptToken.Type.identifier)
			e = parseVariableName(tokens);
		else if(token.type == ScriptToken.Type.symbol && (token.str == "-" || token.str == "+" || token.str == "!" || token.str == "~")) {
			auto op = token.str;
			tokens.popFront();

			e = parsePart(tokens);
			if(op == "-")
				e = new NegationExpression(e);
			else if(op == "!")
				e = new NotExpression(e);
			else if(op == "~")
				e = new BitFlipExpression(e);
		} else {
			tokens.popFront();

			if(token.type == ScriptToken.Type.int_number)
				e = new IntLiteralExpression(token.str, 10);
			else if(token.type == ScriptToken.Type.oct_number)
				e = new IntLiteralExpression(token.str, 8);
			else if(token.type == ScriptToken.Type.hex_number)
				e = new IntLiteralExpression(token.str, 16);
			else if(token.type == ScriptToken.Type.binary_number)
				e = new IntLiteralExpression(token.str, 2);
			else if(token.type == ScriptToken.Type.float_number)
				e = new FloatLiteralExpression(token.str);
			else if(token.type == ScriptToken.Type.string)
				e = new StringLiteralExpression(token);
			else if(token.type == ScriptToken.Type.symbol || token.type == ScriptToken.Type.keyword) {
				switch(token.str) {
					case "true":
					case "false":
						e = new BoolLiteralExpression(token.str);
					break;
					case "new":
						// FIXME: why is this needed here? maybe it should be here instead of parseExpression
						tokens.pushFront(token);
						return parseExpression(tokens);
					case "(":
						//tokens.popFront();
						auto parenthetical = new ParentheticalExpression(parseExpression(tokens));
						tokens.requireNextToken(ScriptToken.Type.symbol, ")");

						if(tokens.peekNextToken(ScriptToken.Type.symbol, "(")) {
							// we have a function call, e.g. (test)()
							return parseFunctionCall(tokens, parenthetical);
						} else
							return parenthetical;
					case "[":
						// array literal
						auto arr = new ArrayLiteralExpression();

						bool first = true;
						moreElements:
						if(tokens.empty)
							throw new ScriptCompileException("unexpected end of file when reading array literal", token.scriptFilename, token.lineNumber);

						auto peek = tokens.front;
						if(peek.type == ScriptToken.Type.symbol && peek.str == "]") {
							tokens.popFront();
							return arr;
						}

						if(!first)
							tokens.requireNextToken(ScriptToken.Type.symbol, ",");
						else
							first = false;

						arr.elements ~= parseExpression(tokens);

						goto moreElements;
					case "json!q{":
					case "#{":
						// json object literal
						auto obj = new ObjectLiteralExpression();
						/*
							these go

							string or ident which is the key
							then a colon
							then an expression which is the value

							then optionally a comma

							then either } which finishes it, or another key
						*/

						if(tokens.empty)
							throw new ScriptCompileException("unexpected end of file when reading object literal", token.scriptFilename, token.lineNumber);

						moreKeys:
						auto key = tokens.front;
						tokens.popFront();
						if(key.type == ScriptToken.Type.symbol && key.str == "}") {
							// all done!
							e = obj;
							break;
						}
						if(key.type != ScriptToken.Type.string && key.type != ScriptToken.Type.identifier) {
							throw new ScriptCompileException("unexpected '"~key.str~"' when reading object literal", key.scriptFilename, key.lineNumber);

						}

						tokens.requireNextToken(ScriptToken.Type.symbol, ":");

						auto value = parseExpression(tokens);
						if(tokens.empty)
							throw new ScriptCompileException("unclosed object literal", key.scriptFilename, key.lineNumber);

						if(tokens.peekNextToken(ScriptToken.Type.symbol, ","))
							tokens.popFront();

						obj.elements[key.str] = value;

						goto moreKeys;
					case "macro":
					case "function":
						tokens.requireNextToken(ScriptToken.Type.symbol, "(");

						auto exp = new FunctionLiteralExpression();
						if(!tokens.peekNextToken(ScriptToken.Type.symbol, ")"))
							exp.arguments = parseVariableDeclaration(tokens, ")");

						tokens.requireNextToken(ScriptToken.Type.symbol, ")");

						exp.functionBody = parseExpression(tokens);
						exp.isMacro = token.str == "macro";

						e = exp;
					break;
					case "null":
						e = new NullLiteralExpression();
					break;
					case "mixin":
					case "eval":
						tokens.requireNextToken(ScriptToken.Type.symbol, "(");
						e = new MixinExpression(parseExpression(tokens));
						tokens.requireNextToken(ScriptToken.Type.symbol, ")");
					break;
					default:
						goto unknown;
				}
			} else {
				unknown:
				throw new ScriptCompileException("unexpected '"~token.str~"' when reading ident", token.scriptFilename, token.lineNumber);
			}
		}

		funcLoop: while(!tokens.empty) {
			auto peek = tokens.front;
			if(peek.type == ScriptToken.Type.symbol) {
				switch(peek.str) {
					case "(":
						e = parseFunctionCall(tokens, e);
					break;
					case "[":
						tokens.popFront();
						auto e1 = parseExpression(tokens);
						if(tokens.peekNextToken(ScriptToken.Type.symbol, "..")) {
							tokens.popFront();
							e = new SliceExpression(e, e1, parseExpression(tokens));
						} else {
							e = new IndexExpression(e, e1);
						}
						tokens.requireNextToken(ScriptToken.Type.symbol, "]");
					break;
					case ".":
						tokens.popFront();
						e = new DotVarExpression(e, parseVariableName(tokens));
					break;
					default:
						return e; // we don't know, punt it elsewhere
				}
			} else return e; // again, we don't know, so just punt it down the line
		}
		return e;
	}

	throw new ScriptCompileException("Ran out of tokens when trying to parsePart", null, 0);
}

Expression parseArguments(MyTokenStreamHere)(ref MyTokenStreamHere tokens, Expression exp, ref Expression[] where) {
	// arguments.
	auto peek = tokens.front;
	if(peek.type == ScriptToken.Type.symbol && peek.str == ")") {
		tokens.popFront();
		return exp;
	}

	moreArguments:

	if(tokens.peekNextToken(ScriptToken.Type.keyword, "default")) {
		tokens.popFront();
		where ~= null;
	} else {
		where ~= parseExpression(tokens);
	}

	if(tokens.empty)
		throw new ScriptCompileException("unexpected end of file when parsing call expression", peek.scriptFilename, peek.lineNumber);
	peek = tokens.front;
	if(peek.type == ScriptToken.Type.symbol && peek.str == ",") {
		tokens.popFront();
		goto moreArguments;
	} else if(peek.type == ScriptToken.Type.symbol && peek.str == ")") {
		tokens.popFront();
		return exp;
	} else
		throw new ScriptCompileException("unexpected '"~peek.str~"' when reading argument list", peek.scriptFilename, peek.lineNumber);

}

Expression parseFunctionCall(MyTokenStreamHere)(ref MyTokenStreamHere tokens, Expression e) {
	assert(!tokens.empty);
	auto peek = tokens.front;
	auto exp = new CallExpression(ScriptLocation(peek.scriptFilename, peek.lineNumber), e);

	assert(peek.str == "(");

	tokens.popFront();
	if(tokens.empty)
		throw new ScriptCompileException("unexpected end of file when parsing call expression", peek.scriptFilename, peek.lineNumber);
	return parseArguments(tokens, exp, exp.arguments);
}

Expression parseFactor(MyTokenStreamHere)(ref MyTokenStreamHere tokens) {
	auto e1 = parsePart(tokens);
	loop: while(!tokens.empty) {
		auto peek = tokens.front;

		if(peek.type == ScriptToken.Type.symbol) {
			switch(peek.str) {
				case "<<":
				case ">>":
				case ">>>":
				case "*":
				case "/":
				case "%":
					tokens.popFront();
					e1 = new BinaryExpression(peek.str, e1, parsePart(tokens));
				break;
				default:
					break loop;
			}
		} else throw new Exception("Got " ~ peek.str ~ " when expecting symbol");
	}

	return e1;
}

Expression parseAddend(MyTokenStreamHere)(ref MyTokenStreamHere tokens) {
	auto e1 = parseFactor(tokens);
	loop: while(!tokens.empty) {
		auto peek = tokens.front;

		if(peek.type == ScriptToken.Type.symbol) {
			switch(peek.str) {
				case "..": // possible FIXME
				case ")": // possible FIXME
				case "]": // possible FIXME
				case "}": // possible FIXME
				case ",": // possible FIXME these are passed on to the next thing
				case ";":
				case ":": // idk
				case "?":
					return e1;

				case "|>":
					tokens.popFront();
					e1 = new PipelineExpression(ScriptLocation(peek.scriptFilename, peek.lineNumber), e1, parseFactor(tokens));
				break;
				case ".":
					tokens.popFront();
					e1 = new DotVarExpression(e1, parseVariableName(tokens));
				break;
				case "=":
					tokens.popFront();
					return new AssignExpression(e1, parseExpression(tokens));
				case "&&": // thanks to mzfhhhh for fix
				case "||":
					tokens.popFront();
					e1 = new BinaryExpression(peek.str, e1, parseExpression(tokens));
					break;
				case "~":
					// FIXME: make sure this has the right associativity

				case "&":
				case "|":
				case "^":

				case "&=":
				case "|=":
				case "^=":

				case "+":
				case "-":

				case "==":
				case "!=":
				case "<=":
				case ">=":
				case "<":
				case ">":
					tokens.popFront();
					e1 = new BinaryExpression(peek.str, e1, parseFactor(tokens));
					break;
				case "+=":
				case "-=":
				case "*=":
				case "/=":
				case "~=":
				case "%=":
					tokens.popFront();
					return new OpAssignExpression(peek.str[0..1], e1, parseExpression(tokens));
				default:
					throw new ScriptCompileException("Parse error, unexpected " ~ peek.str ~ " when looking for operator", peek.scriptFilename, peek.lineNumber);
			}
		//} else if(peek.type == ScriptToken.Type.identifier || peek.type == ScriptToken.Type.number) {
			//return parseFactor(tokens);
		} else
			throw new ScriptCompileException("Parse error, unexpected '" ~ peek.str ~ "'", peek.scriptFilename, peek.lineNumber);
	}

	return e1;
}

Expression parseExpression(MyTokenStreamHere)(ref MyTokenStreamHere tokens, bool consumeEnd = false) {
	Expression ret;
	ScriptToken first;
	string expectedEnd = ";";
	//auto e1 = parseFactor(tokens);

		while(tokens.peekNextToken(ScriptToken.Type.symbol, ";")) {
			tokens.popFront();
		}
	if(!tokens.empty) {
		first = tokens.front;
		if(tokens.peekNextToken(ScriptToken.Type.symbol, "{")) {
			auto start = tokens.front;
			tokens.popFront();
			auto e = parseCompoundStatement(tokens, start.lineNumber, "}").array;
			ret = new ScopeExpression(e);
			expectedEnd = null; // {} don't need ; at the end
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "scope")) {
			auto start = tokens.front;
			tokens.popFront();
			tokens.requireNextToken(ScriptToken.Type.symbol, "(");

			auto ident = tokens.requireNextToken(ScriptToken.Type.identifier);
			switch(ident.str) {
				case "success":
				case "failure":
				case "exit":
				break;
				default:
					throw new ScriptCompileException("unexpected " ~ ident.str ~ ". valid scope(idents) are success, failure, and exit", ident.scriptFilename, ident.lineNumber);
			}

			tokens.requireNextToken(ScriptToken.Type.symbol, ")");

			string i = "__scope_" ~ ident.str;
			auto literal = new FunctionLiteralExpression();
			literal.functionBody = parseExpression(tokens);

			auto e = new OpAssignExpression("~", new VariableExpression(i), literal);
			ret = e;
		}/+ else if(tokens.peekNextToken(ScriptToken.Type.symbol, "(")) {
			auto start = tokens.front;
			tokens.popFront();
			auto parenthetical = new ParentheticalExpression(parseExpression(tokens));

			tokens.requireNextToken(ScriptToken.Type.symbol, ")");
			if(tokens.peekNextToken(ScriptToken.Type.symbol, "(")) {
				// we have a function call, e.g. (test)()
				ret = parseFunctionCall(tokens, parenthetical);
			} else
				ret = parenthetical;
		}+/ else if(tokens.peekNextToken(ScriptToken.Type.keyword, "new")) {
			auto start = tokens.front;
			tokens.popFront();

			auto expr = parseDottedVariableName(tokens);
			auto ne = new NewExpression(expr);
			if(tokens.peekNextToken(ScriptToken.Type.symbol, "(")) {
				tokens.popFront();
				parseArguments(tokens, ne, ne.args);
			}

			ret = ne;
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "class")) {
			auto start = tokens.front;
			tokens.popFront();

			Expression[] expressions;

			// the way classes work is they are actually object literals with a different syntax. new foo then just copies it
			/*
				we create a prototype object
				we create an object, with that prototype

				set all functions and static stuff to the prototype
				the rest goes to the object

				the expression returns the object we made
			*/

			auto vars = new VariableDeclaration();
			vars.identifiers = ["__proto", "__obj"];

			auto staticScopeBacking = new PrototypeObject();
			auto instanceScopeBacking = new PrototypeObject();

			vars.initializers = [new ObjectLiteralExpression(staticScopeBacking), new ObjectLiteralExpression(instanceScopeBacking)];
			expressions ~= vars;

			 // FIXME: operators need to have their this be bound somehow since it isn't passed
			 // OR the op rewrite could pass this

			expressions ~= new AssignExpression(
				new DotVarExpression(new VariableExpression("__obj"), new VariableExpression("prototype")),
				new VariableExpression("__proto"));

			auto classIdent = tokens.requireNextToken(ScriptToken.Type.identifier);

			expressions ~= new AssignExpression(
				new DotVarExpression(new VariableExpression("__proto"), new VariableExpression("__classname")),
				new StringLiteralExpression(classIdent.str));

			if(tokens.peekNextToken(ScriptToken.Type.symbol, ":")) {
				tokens.popFront();
				auto inheritFrom = tokens.requireNextToken(ScriptToken.Type.identifier);

				// we set our prototype to the Foo prototype, thereby inheriting any static data that way (includes functions)
				// the inheritFrom object itself carries instance  data that we need to copy onto our instance
				expressions ~= new AssignExpression(
					new DotVarExpression(new VariableExpression("__proto"), new VariableExpression("prototype")),
					new DotVarExpression(new VariableExpression(inheritFrom.str), new VariableExpression("prototype")));

				expressions ~= new AssignExpression(
					new DotVarExpression(new VariableExpression("__proto"), new VariableExpression("super")),
					new VariableExpression(inheritFrom.str)
				);

				// and copying the instance initializer from the parent
				expressions ~= new ShallowCopyExpression(new VariableExpression("__obj"), new VariableExpression(inheritFrom.str));
			}

			tokens.requireNextToken(ScriptToken.Type.symbol, "{");

			void addVarDecl(VariableDeclaration decl, string o) {
				foreach(i, ident; decl.identifiers) {
					// FIXME: make sure this goes on the instance, never the prototype!
					expressions ~= new AssignExpression(
						new DotVarExpression(
							new VariableExpression(o),
							new VariableExpression(ident),
							false),
						decl.initializers[i],
						true // no overloading because otherwise an early opIndexAssign can mess up the decls
					);
				}
			}

			// FIXME: we could actually add private vars and just put them in this scope. maybe

			while(!tokens.peekNextToken(ScriptToken.Type.symbol, "}")) {
				if(tokens.peekNextToken(ScriptToken.Type.symbol, ";")) {
					tokens.popFront();
					continue;
				}

				if(tokens.peekNextToken(ScriptToken.Type.identifier, "this")) {
					// ctor
					tokens.popFront();
					tokens.requireNextToken(ScriptToken.Type.symbol, "(");
					auto args = parseVariableDeclaration(tokens, ")");
					tokens.requireNextToken(ScriptToken.Type.symbol, ")");
					auto bod = parseExpression(tokens);

					expressions ~= new AssignExpression(
						new DotVarExpression(
							new VariableExpression("__proto"),
							new VariableExpression("__ctor")),
						new FunctionLiteralExpression(args, bod, staticScopeBacking));
				} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "var")) {
					// instance variable
					auto decl = parseVariableDeclaration(tokens, ";");
					addVarDecl(decl, "__obj");
				} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "static")) {
					// prototype var
					tokens.popFront();
					auto decl = parseVariableDeclaration(tokens, ";");
					addVarDecl(decl, "__proto");
				} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "function")) {
					// prototype function
					tokens.popFront();
					auto ident = tokens.requireNextToken(ScriptToken.Type.identifier);

					tokens.requireNextToken(ScriptToken.Type.symbol, "(");
					VariableDeclaration args;
					if(!tokens.peekNextToken(ScriptToken.Type.symbol, ")"))
						args = parseVariableDeclaration(tokens, ")");
					tokens.requireNextToken(ScriptToken.Type.symbol, ")");
					auto bod = parseExpression(tokens);

					expressions ~= new FunctionDeclaration(
						new DotVarExpression(
							new VariableExpression("__proto"),
							new VariableExpression(ident.str),
							false),
						ident.str,
						new FunctionLiteralExpression(args, bod, staticScopeBacking)
					);
				} else throw new ScriptCompileException("Unexpected " ~ tokens.front.str ~ " when reading class decl", tokens.front.scriptFilename, tokens.front.lineNumber);
			}

			tokens.requireNextToken(ScriptToken.Type.symbol, "}");

			// returning he object from the scope...
			expressions ~= new VariableExpression("__obj");

			auto scopeExpr = new ScopeExpression(expressions);
			auto classVarExpr = new VariableDeclaration();
			classVarExpr.identifiers = [classIdent.str];
			classVarExpr.initializers = [scopeExpr];

			ret = classVarExpr;
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "if")) {
			tokens.popFront();
			auto e = new IfExpression();
			tokens.requireNextToken(ScriptToken.Type.symbol, "(");
			e.condition = parseExpression(tokens);
			tokens.requireNextToken(ScriptToken.Type.symbol, ")");
			e.ifTrue = parseExpression(tokens);
			if(tokens.peekNextToken(ScriptToken.Type.symbol, ";")) {
				tokens.popFront();
			}
			if(tokens.peekNextToken(ScriptToken.Type.keyword, "else")) {
				tokens.popFront();
				e.ifFalse = parseExpression(tokens);
			}
			ret = e;
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "switch")) {
			tokens.popFront();
			auto e = new SwitchExpression();
			tokens.requireNextToken(ScriptToken.Type.symbol, "(");
			e.expr = parseExpression(tokens);
			tokens.requireNextToken(ScriptToken.Type.symbol, ")");

			tokens.requireNextToken(ScriptToken.Type.symbol, "{");

			while(!tokens.peekNextToken(ScriptToken.Type.symbol, "}")) {

				if(tokens.peekNextToken(ScriptToken.Type.keyword, "case")) {
					auto start = tokens.front;
					tokens.popFront();
					auto c = new CaseExpression(parseExpression(tokens));
					e.cases ~= c;
					tokens.requireNextToken(ScriptToken.Type.symbol, ":");

					while(!tokens.peekNextToken(ScriptToken.Type.keyword, "default") && !tokens.peekNextToken(ScriptToken.Type.keyword, "case") && !tokens.peekNextToken(ScriptToken.Type.symbol, "}")) {
						c.expressions ~= parseStatement(tokens);
						while(tokens.peekNextToken(ScriptToken.Type.symbol, ";"))
							tokens.popFront();
					}
				} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "default")) {
					tokens.popFront();
					tokens.requireNextToken(ScriptToken.Type.symbol, ":");

					auto c = new CaseExpression(null);

					while(!tokens.peekNextToken(ScriptToken.Type.keyword, "case") && !tokens.peekNextToken(ScriptToken.Type.symbol, "}")) {
						c.expressions ~= parseStatement(tokens);
						while(tokens.peekNextToken(ScriptToken.Type.symbol, ";"))
							tokens.popFront();
					}

					e.cases ~= c;
					e.default_ = c;
				} else throw new ScriptCompileException("A switch statement must consists of cases and a default, nothing else ", tokens.front.scriptFilename, tokens.front.lineNumber);
			}

			tokens.requireNextToken(ScriptToken.Type.symbol, "}");
			expectedEnd = "";

			ret = e;

		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "foreach")) {
			tokens.popFront();
			auto e = new ForeachExpression();
			tokens.requireNextToken(ScriptToken.Type.symbol, "(");
			e.decl = parseVariableDeclaration(tokens, ";");
			tokens.requireNextToken(ScriptToken.Type.symbol, ";");
			e.subject = parseExpression(tokens);

			if(tokens.peekNextToken(ScriptToken.Type.symbol, "..")) {
				tokens.popFront;
				e.subject2 = parseExpression(tokens);
			}

			tokens.requireNextToken(ScriptToken.Type.symbol, ")");
			e.loopBody = parseExpression(tokens);
			ret = e;

			expectedEnd = "";
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "cast")) {
			tokens.popFront();
			auto e = new CastExpression();

			tokens.requireNextToken(ScriptToken.Type.symbol, "(");
			e.type = tokens.requireNextToken(ScriptToken.Type.identifier).str;
			if(tokens.peekNextToken(ScriptToken.Type.symbol, "[")) {
				e.type ~= "[]";
				tokens.popFront();
				tokens.requireNextToken(ScriptToken.Type.symbol, "]");
			}
			tokens.requireNextToken(ScriptToken.Type.symbol, ")");

			e.e1 = parseExpression(tokens);
			ret = e;
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "for")) {
			tokens.popFront();
			auto e = new ForExpression();
			tokens.requireNextToken(ScriptToken.Type.symbol, "(");
			e.initialization = parseStatement(tokens, ";");

			tokens.requireNextToken(ScriptToken.Type.symbol, ";");

			e.condition = parseExpression(tokens);
			tokens.requireNextToken(ScriptToken.Type.symbol, ";");
			e.advancement = parseExpression(tokens);
			tokens.requireNextToken(ScriptToken.Type.symbol, ")");
			e.loopBody = parseExpression(tokens);

			ret = e;

			expectedEnd = "";
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "while")) {
			tokens.popFront();
			auto e = new ForExpression();

			tokens.requireNextToken(ScriptToken.Type.symbol, "(");
			e.condition = parseExpression(tokens);
			tokens.requireNextToken(ScriptToken.Type.symbol, ")");

			e.loopBody = parseExpression(tokens);

			ret = e;
			expectedEnd = "";
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "break") || tokens.peekNextToken(ScriptToken.Type.keyword, "continue")) {
			auto token = tokens.front;
			tokens.popFront();
			ret = new LoopControlExpression(token.str);
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "return")) {
			tokens.popFront();
			Expression retVal;
			if(tokens.peekNextToken(ScriptToken.Type.symbol, ";"))
				retVal = new NullLiteralExpression();
			else
				retVal = parseExpression(tokens);
			ret = new ReturnExpression(retVal);
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "throw")) {
			auto token = tokens.front;
			tokens.popFront();
			ret = new ThrowExpression(parseExpression(tokens), token);
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "try")) {
			auto tryToken = tokens.front;
			auto e = new ExceptionBlockExpression();
			tokens.popFront();
			e.tryExpression = parseExpression(tokens, true);

			bool hadFinally = false;
			while(tokens.peekNextToken(ScriptToken.Type.keyword, "catch")) {
				if(hadFinally)
					throw new ScriptCompileException("Catch must come before finally", tokens.front.scriptFilename, tokens.front.lineNumber);
				tokens.popFront();
				tokens.requireNextToken(ScriptToken.Type.symbol, "(");
				if(tokens.peekNextToken(ScriptToken.Type.keyword, "var"))
					tokens.popFront();

				auto ident = tokens.requireNextToken(ScriptToken.Type.identifier);
				if(tokens.empty) throw new ScriptCompileException("Catch specifier not closed", ident.scriptFilename, ident.lineNumber);
				auto next = tokens.front;
				if(next.type == ScriptToken.Type.identifier) {
					auto type = ident;
					ident = next;

					e.catchVarTypeSpecifiers ~= type.str;
					e.catchVarDecls ~= ident.str;

					tokens.popFront();

					tokens.requireNextToken(ScriptToken.Type.symbol, ")");
				} else {
					e.catchVarTypeSpecifiers ~= null;
					e.catchVarDecls ~= ident.str;
					if(next.type != ScriptToken.Type.symbol || next.str != ")")
						throw new ScriptCompileException("ss Unexpected " ~ next.str ~ " when expecting ')'", next.scriptFilename, next.lineNumber);
					tokens.popFront();
				}
				e.catchExpressions ~= parseExpression(tokens);
			}
			while(tokens.peekNextToken(ScriptToken.Type.keyword, "finally")) {
				hadFinally = true;
				tokens.popFront();
				e.finallyExpressions ~= parseExpression(tokens);
			}

			//if(!hadSomething)
				//throw new ScriptCompileException("Parse error, missing finally or catch after try", tryToken.lineNumber);

			ret = e;
		} else {
			ret = parseAddend(tokens);
		}

		if(!tokens.empty && tokens.peekNextToken(ScriptToken.Type.symbol, "?")) {
			auto e = new TernaryExpression();
			e.condition = ret;
			tokens.requireNextToken(ScriptToken.Type.symbol, "?");
			e.ifTrue = parseExpression(tokens);
			tokens.requireNextToken(ScriptToken.Type.symbol, ":");
			e.ifFalse = parseExpression(tokens);
			ret = e;
		}
	} else {
		//assert(0);
		// return null;
		throw new ScriptCompileException("Parse error, unexpected end of input when reading expression", null, 0);//token.lineNumber);
	}

	//writeln("parsed expression ", ret.toString());

	if(expectedEnd.length && tokens.empty && consumeEnd) // going loose on final ; at the end of input for repl convenience
		throw new ScriptCompileException("Parse error, unexpected end of input when reading expression, expecting " ~ expectedEnd, first.scriptFilename, first.lineNumber);

	if(expectedEnd.length && consumeEnd) {
		 if(tokens.peekNextToken(ScriptToken.Type.symbol, expectedEnd))
			 tokens.popFront();
		// FIXME
		//if(tokens.front.type != ScriptToken.Type.symbol && tokens.front.str != expectedEnd)
			//throw new ScriptCompileException("Parse error, missing "~expectedEnd~" at end of expression (starting on "~to!string(first.lineNumber)~"). Saw "~tokens.front.str~" instead", tokens.front.lineNumber);
	//	tokens = tokens[1 .. $];
	}

	return ret;
}

VariableDeclaration parseVariableDeclaration(MyTokenStreamHere)(ref MyTokenStreamHere tokens, string termination) {
	VariableDeclaration decl = new VariableDeclaration();
	bool equalOk;
	anotherVar:
	assert(!tokens.empty);

	auto firstToken = tokens.front;

	// var a, var b is acceptable
	if(tokens.peekNextToken(ScriptToken.Type.keyword, "var"))
		tokens.popFront();

	equalOk= true;
	if(tokens.empty)
		throw new ScriptCompileException("Parse error, dangling var at end of file", firstToken.scriptFilename, firstToken.lineNumber);

	string type;

	auto next = tokens.front;
	tokens.popFront;
	if(tokens.empty)
		throw new ScriptCompileException("Parse error, incomplete var declaration at end of file", firstToken.scriptFilename, firstToken.lineNumber);
	auto next2 = tokens.front;

	ScriptToken typeSpecifier;

	/* if there's two identifiers back to back, it is a type specifier. otherwise just a name */

	if(next.type == ScriptToken.Type.identifier && next2.type == ScriptToken.Type.identifier) {
		// type ident;
		typeSpecifier = next;
		next = next2;
		// get past the type
		tokens.popFront();
	} else {
		// no type, just carry on with the next thing
	}

	Expression initializer;
	auto identifier = next;
	if(identifier.type != ScriptToken.Type.identifier)
		throw new ScriptCompileException("Parse error, found '"~identifier.str~"' when expecting var identifier", identifier.scriptFilename, identifier.lineNumber);

	//tokens.popFront();

	tryTermination:
	if(tokens.empty)
		throw new ScriptCompileException("Parse error, missing ; after var declaration at end of file", firstToken.scriptFilename, firstToken.lineNumber);

	auto peek = tokens.front;
	if(peek.type == ScriptToken.Type.symbol) {
		if(peek.str == "=") {
			if(!equalOk)
				throw new ScriptCompileException("Parse error, unexpected '"~identifier.str~"' after reading var initializer", peek.scriptFilename, peek.lineNumber);
			equalOk = false;
			tokens.popFront();
			initializer = parseExpression(tokens);
			goto tryTermination;
		} else if(peek.str == ",") {
			tokens.popFront();
			decl.identifiers ~= identifier.str;
			decl.initializers ~= initializer;
			decl.typeSpecifiers ~= typeSpecifier.str;
			goto anotherVar;
		} else if(peek.str == termination) {
			decl.identifiers ~= identifier.str;
			decl.initializers ~= initializer;
			decl.typeSpecifiers ~= typeSpecifier.str;
			//tokens = tokens[1 .. $];
			// we're done!
		} else
			throw new ScriptCompileException("Parse error, unexpected '"~peek.str~"' when reading var declaration symbol", peek.scriptFilename, peek.lineNumber);
	} else
		throw new ScriptCompileException("Parse error, unexpected non-symbol '"~peek.str~"' when reading var declaration", peek.scriptFilename, peek.lineNumber);

	return decl;
}

Expression parseStatement(MyTokenStreamHere)(ref MyTokenStreamHere tokens, string terminatingSymbol = null) {
	skip: // FIXME
	if(tokens.empty)
		return null;

	if(terminatingSymbol !is null && (tokens.front.type == ScriptToken.Type.symbol && tokens.front.str == terminatingSymbol))
		return null; // we're done

	auto token = tokens.front;

	// tokens = tokens[1 .. $];
	final switch(token.type) {
		case ScriptToken.Type.keyword:
		case ScriptToken.Type.symbol:
			switch(token.str) {
				// assert
				case "assert":
					tokens.popFront();

					return parseFunctionCall(tokens, new AssertKeyword(token));

				//break;
				// declarations
				case "var":
					return parseVariableDeclaration(tokens, ";");
				case ";":
					tokens.popFront(); // FIXME
					goto skip;
				// literals
				case "function":
				case "macro":
					// function can be a literal, or a declaration.

					tokens.popFront(); // we're peeking ahead

					if(tokens.peekNextToken(ScriptToken.Type.identifier)) {
						// decl style, rewrite it into var ident = function style
						// tokens.popFront(); // skipping the function keyword // already done above with the popFront
						auto ident = tokens.front;
						tokens.popFront();

						tokens.requireNextToken(ScriptToken.Type.symbol, "(");

						auto exp = new FunctionLiteralExpression();
						if(!tokens.peekNextToken(ScriptToken.Type.symbol, ")"))
							exp.arguments = parseVariableDeclaration(tokens, ")");
						tokens.requireNextToken(ScriptToken.Type.symbol, ")");

						exp.functionBody = parseExpression(tokens);

						// a ; should NOT be required here btw

						exp.isMacro = token.str == "macro";

						auto e = new FunctionDeclaration(null, ident.str, exp);

						return e;

					} else {
						tokens.pushFront(token); // put it back since everyone expects us to have done that
						goto case; // handle it like any other expression
					}

				case "true":
				case "false":

				case "json!{":
				case "#{":
				case "[":
				case "(":
				case "null":

				// scope
				case "{":
				case "scope":

				case "cast":

				// classes
				case "class":
				case "new":

				case "super":

				// flow control
				case "if":
				case "while":
				case "for":
				case "foreach":
				case "switch":

				// exceptions
				case "try":
				case "throw":

				// evals
				case "eval":
				case "mixin":

				// flow
				case "continue":
				case "break":
				case "return":
					return parseExpression(tokens);
				// unary prefix operators
				case "!":
				case "~":
				case "-":
					return parseExpression(tokens);

				// BTW add custom object operator overloading to struct var
				// and custom property overloading to PrototypeObject

				default:
					// whatever else keyword or operator related is actually illegal here
					throw new ScriptCompileException("Parse error, unexpected " ~ token.str, token.scriptFilename, token.lineNumber);
			}
		// break;
		case ScriptToken.Type.identifier:
		case ScriptToken.Type.string:
		case ScriptToken.Type.int_number:
		case ScriptToken.Type.float_number:
		case ScriptToken.Type.binary_number:
		case ScriptToken.Type.hex_number:
		case ScriptToken.Type.oct_number:
			return parseExpression(tokens);
	}

	assert(0);
}

unittest {
	interpret(q{
		var a = 5;
		var b = false;
		assert(a == 5 || b);
	});
}
unittest {
	interpret(q{
		var a = 5;
		var b = false;
		assert(((a == 5) || b));
	});
}

unittest {
	interpret(q{
		var a = 10 - 5 - 5;
		assert(a == 0);
	});
}

unittest {
	interpret(q{
		var a = 5;
		while(a > 0) { a-=1; }

		if(a) { a } else { a }
	});
}


struct CompoundStatementRange(MyTokenStreamHere) {
	// FIXME: if MyTokenStreamHere is not a class, this fails!
	MyTokenStreamHere tokens;
	int startingLine;
	string terminatingSymbol;
	bool isEmpty;

	this(MyTokenStreamHere t, int startingLine, string terminatingSymbol) {
		tokens = t;
		this.startingLine = startingLine;
		this.terminatingSymbol = terminatingSymbol;
		popFront();
	}

	bool empty() {
		return isEmpty;
	}

	Expression got;

	Expression front() {
		return got;
	}

	void popFront() {
		while(!tokens.empty && (terminatingSymbol is null || !(tokens.front.type == ScriptToken.Type.symbol && tokens.front.str == terminatingSymbol))) {
			auto n = parseStatement(tokens, terminatingSymbol);
			if(n is null)
				continue;
			got = n;
			return;
		}

		if(tokens.empty && terminatingSymbol !is null) {
			throw new ScriptCompileException("Reached end of file while trying to reach matching " ~ terminatingSymbol, null, startingLine);
		}

		if(terminatingSymbol !is null) {
			assert(tokens.front.str == terminatingSymbol);
			tokens.skipNext++;
		}

		isEmpty = true;
	}
}

CompoundStatementRange!MyTokenStreamHere
//Expression[]
parseCompoundStatement(MyTokenStreamHere)(ref MyTokenStreamHere tokens, int startingLine = 1, string terminatingSymbol = null) {
	return (CompoundStatementRange!MyTokenStreamHere(tokens, startingLine, terminatingSymbol));
}

auto parseScript(MyTokenStreamHere)(MyTokenStreamHere tokens) {
	/*
		the language's grammar is simple enough

		maybe flow control should be statements though lol. they might not make sense inside.

		Expressions:
			var identifier;
			var identifier = initializer;
			var identifier, identifier2

			return expression;
			return ;

			json!{ object literal }

			{ scope expression }

			[ array literal ]
			other literal
			function (arg list) other expression

			( expression ) // parenthesized expression
			operator expression  // unary expression

			expression operator expression // binary expression
			expression (other expression... args) // function call

		Binary Operator precedence :
			. []
			* /
			+ -
			~
			< > == !=
			=
	*/

	return parseCompoundStatement(tokens);
}

var interpretExpressions(ExpressionStream)(ExpressionStream expressions, PrototypeObject variables) if(is(ElementType!ExpressionStream == Expression)) {
	assert(variables !is null);
	var ret;
	foreach(expression; expressions) {
		auto res = expression.interpret(variables);
		variables = res.sc;
		ret = res.value;
	}
	return ret;
}

var interpretStream(MyTokenStreamHere)(MyTokenStreamHere tokens, PrototypeObject variables) if(is(ElementType!MyTokenStreamHere == ScriptToken)) {
	assert(variables !is null);
	// this is an entry point that all others lead to, right before getting to interpretExpressions...

	return interpretExpressions(parseScript(tokens), variables);
}

var interpretStream(MyTokenStreamHere)(MyTokenStreamHere tokens, var variables) if(is(ElementType!MyTokenStreamHere == ScriptToken)) {
	return interpretStream(tokens,
		(variables.payloadType() == var.Type.Object && variables._payload._object !is null) ? variables._payload._object : new PrototypeObject());
}

var interpret(string code, PrototypeObject variables, string scriptFilename = null) {
	assert(variables !is null);
	return interpretStream(lexScript(repeat(code, 1), scriptFilename), variables);
}

/++
	This is likely your main entry point to the interpreter. It will interpret the script code
	given, with the given global variable object (which will be modified by the script, meaning
	you can pass it to subsequent calls to `interpret` to store context), and return the result
	of the last expression given.

	---
	var globals = var.emptyObject; // the global object must be an object of some type
	globals.x = 10;
	globals.y = 15;
	// you can also set global functions through this same style, etc

	var result = interpret(`x + y`, globals);
	assert(result == 25);
	---


	$(TIP
		If you want to just call a script function, interpret the definition of it,
		then just call it through the `globals` object you passed to it.

		---
		var globals = var.emptyObject;
		interpret(`function foo(name) { return "hello, " ~ name ~ "!"; }`, globals);
		var result = globals.foo()("world");
		assert(result == "hello, world!");
		---
	)

	Params:
		code = the script source code you want to interpret
		scriptFilename = the filename of the script, if you want to provide it. Gives nicer error messages if you provide one.
		variables = The global object of the script context. It will be modified by the user script.

	Returns:
		the result of the last expression evaluated by the script engine
+/
var interpret(string code, var variables = null, string scriptFilename = null, string file = __FILE__, size_t line = __LINE__) {
	if(scriptFilename is null)
		scriptFilename = file ~ "@" ~ to!string(line);
	return interpretStream(
		lexScript(repeat(code, 1), scriptFilename),
		(variables.payloadType() == var.Type.Object && variables._payload._object !is null) ? variables._payload._object : new PrototypeObject());
}

///
var interpretFile(File file, var globals) {
	import std.algorithm;
	return interpretStream(lexScript(file.byLine.map!((a) => a.idup), file.name),
		(globals.payloadType() == var.Type.Object && globals._payload._object !is null) ? globals._payload._object : new PrototypeObject());
}

/// Enhanced repl uses arsd.terminal for better ux. Added April 26, 2020. Default just uses std.stdio.
void repl(bool enhanced = false)(var globals) {
	static if(enhanced) {
		import arsd.terminal;
		Terminal terminal = Terminal(ConsoleOutputMode.linear);
		auto lines() {
			struct Range {
				string line;
				string front() { return line; }
				bool empty() { return line is null; }
				void popFront() { line = terminal.getline(": "); terminal.writeln(); }
			}
			Range r;
			r.popFront();
			return r;

		}

		void writeln(T...)(T t) {
			terminal.writeln(t);
			terminal.flush();
		}
	} else {
		import std.stdio;
		auto lines() { return stdin.byLine; }
	}

	bool exited;
	if(globals == null)
		globals = var.emptyObject;
	globals.exit = () { exited = true; };

	import std.algorithm;
	auto variables = (globals.payloadType() == var.Type.Object && globals._payload._object !is null) ? globals._payload._object : new PrototypeObject();

	// we chain to ensure the priming popFront succeeds so we don't throw here
	auto tokens = lexScript(
		chain(["var __skipme = 0;"], map!((a) => a.idup)(lines))
	, "stdin");
	auto expressions = parseScript(tokens);

	while(!exited && !expressions.empty) {
		try {
			expressions.popFront;
			auto expression = expressions.front;
			auto res = expression.interpret(variables);
			variables = res.sc;
			writeln(">>> ", res.value);
		} catch(ScriptCompileException e) {
			writeln("*+* ", e.msg);
			tokens.popFront(); // skip the one we threw on...
		} catch(Exception e) {
			writeln("*** ", e.msg);
		}
	}
}

class ScriptFunctionMetadata : VarMetadata {
	FunctionLiteralExpression fle;
	this(FunctionLiteralExpression fle) {
		this.fle = fle;
	}

	string convertToString() {
		return fle.toString();
	}
}
