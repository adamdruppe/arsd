/**
   FIXME: Also ability to get source code for function something so you can mixin.

	Script features:

	FIXME: add COM support on Windows

	OVERVIEW
	* easy interop with D thanks to arsd.jsvar. When interpreting, pass a var object to use as globals.
		This object also contains the global state when interpretation is done.
	* mostly familiar syntax, hybrid of D and Javascript
	* simple implementation is moderately small and fairly easy to hack on (though it gets messier by the day), but it isn't made for speed.

	SPECIFICS
	* mixin aka eval (does it at runtime, so more like eval than mixin, but I want it to look like D)
	* scope guards, like in D
	* try/catch/finally/throw
		You can use try as an expression without any following catch to return the exception:

		var a = try throw "exception";; // the double ; is because one closes the try, the second closes the var
		// a is now the thrown exception
	* for/while/foreach
	* D style operators: +-/* on all numeric types, ~ on strings and arrays, |&^ on integers.
		Operators can coerce types as needed: 10 ~ "hey" == "10hey". 10 + "3" == 13.
		Any math, except bitwise math, with a floating point component returns a floating point component, but pure int math is done as ints (unlike Javascript btw).
		Any bitwise math coerces to int.

		So you can do some type coercion like this:

		a = a|0; // forces to int
		a = "" ~ a; // forces to string
		a = a+0.0; // coerces to float

		Though casting is probably better.
	* Type coercion via cast, similarly to D.
		var a = "12";
		a.typeof == "String";
		a = cast(int) a;
		a.typeof == "Integral";
		a == 12;

		Supported types for casting to: int/long (both actually an alias for long, because of how var works), float/double/real, string, char/dchar (these return *integral* types), and arrays, int[], string[], and float[].

		This forwards directly to the D function var.opCast.

	* some operator overloading on objects, passing opBinary(op, rhs), length, and perhaps others through like they would be in D.
		opIndex(name)
		opIndexAssign(value, name) // same order as D, might some day support [n1, n2] => (value, n1, n2)

		obj.__prop("name", value); // bypasses operator overloading, useful for use inside the opIndexAssign especially

		Note: if opIndex is not overloaded, getting a non-existent member will actually add it to the member. This might be a bug but is needed right now in the D impl for nice chaining. Or is it? FIXME
	* if/else
	* array slicing, but note that slices are rvalues currently
	* variables must start with A-Z, a-z, _, or $, then must be [A-Za-z0-9_]*.
		(The $ can also stand alone, and this is a special thing when slicing, so you probably shouldn't use it at all.).
		Variable names that start with __ are reserved and you shouldn't use them.
	* int, float, string, array, bool, and json!q{} literals
	* var.prototype, var.typeof. prototype works more like Mozilla's __proto__ than standard javascript prototype.
	* classes:
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



	FIXME:
		* make sure superclass ctors are called
	Might be nice:
		varargs
		lambdas
*/
module arsd.script;

public import arsd.jsvar;

import std.stdio;
import std.traits;
import std.conv;
import std.json;

import std.array;
import std.range;

/***************************************
  script to follow
****************************************/

class ScriptCompileException : Exception {
	this(string msg, int lineNumber, string file = __FILE__, size_t line = __LINE__) {
		super(to!string(lineNumber) ~ ": " ~ msg, file, line);
	}
}

class ScriptRuntimeException : Exception {
	this(string msg, int lineNumber, string file = __FILE__, size_t line = __LINE__) {
		super(to!string(lineNumber) ~ ": " ~ msg, file, line);
	}
}

class ScriptException : Exception {
	var payload;
	int lineNumber;
	this(var payload, int lineNumber, string file = __FILE__, size_t line = __LINE__) {
		this.payload = payload;
		this.lineNumber = lineNumber;
		super("script@" ~ to!string(lineNumber) ~ ": " ~ to!string(payload), file, line);
	}

	override string toString() {
		return "script@" ~ to!string(lineNumber) ~ ": " ~ payload.get!string;
	}
}

struct ScriptToken {
	enum Type { identifier, keyword, symbol, string, int_number, float_number }
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
	"while", "catch", "throw", "scope", "break", "super", "class", "false", "mixin", "super", "macro",
	"auto", // provided as an alias for var right now, may change later
	"null", "else", "true", "eval", "goto", "enum", "case", "cast",
	"var", "for", "try", "new",
	"if", "do",
];
private enum string[] symbols = [
	"//", "/*", "/+",
	"&&", "||",
	"+=", "-=", "*=", "/=", "~=",  "==", "<=", ">=","!=",
	"&=", "|=", "^=",
	"..",
	".",",",";",":",
	"[", "]", "{", "}", "(", ")",
	"&", "|", "^",
	"+", "-", "*", "/", "=", "<", ">","~","!",
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
			text.popFront();
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

			if(text[0] == ' ' || text[0] == '\t' || text[0] == '\n') {
				advance(1);
				continue;
			} else if(text[0] >= '0' && text[0] <= '9') {
				int pos;
				bool sawDot;
				while(pos < text.length && ((text[pos] >= '0' && text[pos] <= '9') || text[pos] == '.')) {
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
							(text[pos] >= 'A' && text[pos] <= 'Z') ||
							(text[pos] >= '0' && text[pos] <= '9')))
					{
						pos++;
					}

					token.str = text[0 .. pos];
					advance(pos);
				}
			} else if(text[0] == '"') {
				token.type = ScriptToken.Type.string;
				int pos = 1; // skip the opening "
				bool escaped = false;
				// FIXME: escaping doesn't do the right thing lol. we should slice if we can, copy if not
				while(pos < text.length && (escaped || text[pos] != '"')) {
					if(escaped)
						escaped = false;
					else
						if(text[pos] == '\\')
							escaped = true;
					pos++;
				}

				token.str = text[1 .. pos];
				advance(pos + 1); // skip the closing " too
			} else {
				// let's check all symbols
				bool found = false;
				foreach(symbol; symbols)
					if(text.length >= symbol.length && text[0 .. symbol.length] == symbol) {

						if(symbol == "//") {
							// one line comment
							int pos = 0;
							while(pos < text.length && text[pos] != '\n')
								pos++;
							advance(pos);
							continue mainLoop;
						} else if(symbol == "/*") {
							int pos = 0;
							while(pos + 1 < text.length && text[pos..pos+2] != "*/")
								pos++;

							if(pos + 1 == text.length)
								throw new ScriptCompileException("unclosed /* */ comment", lineNumber);

							advance(pos + 2);
							continue mainLoop;

						} else if(symbol == "/+") {
							// FIXME: nesting comment
						}

						found = true;
						token.type = ScriptToken.Type.symbol;
						token.str = symbol;
						advance(symbol.length);
						break;
					}

				if(!found) {
					// FIXME: make sure this gives a valid utf-8 sequence
					throw new ScriptCompileException("unknown token " ~ text[0], lineNumber);
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
			// FIXME: if they changed the properties in the
			// script, we should update them here too.
			return var(e.toString());
		};
		obj["opCall"] = (var _this, var[] args) {
			Expression e = this;
			// FIXME: if they changed the properties in the
			// script, we should update them here too.
			return e.interpret(sc).value;
		};

		// adding structure is going to be a little bit magical
		// I could have done this with a virtual function, but I'm lazy.
		addChildElementsOfExpressionToScriptExpressionObject(typeid(this), this, sc, obj);

		return obj;
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
	string literal;

	override string toString() {
		import std.string : replace;
		return `"` ~ literal.replace("\\", "\\\\").replace("\"", "\\\"") ~ "\"";
	}

	this(string s) {
		char[] unescaped;
		int lastPos;
		bool changed = false;
		bool inEscape = false;
		foreach(pos, char c; s) {
			if(c == '\\') {
				if(!changed) {
					changed = true;
					unescaped.reserve(s.length);
				}
				unescaped ~= s[lastPos .. pos];
				inEscape = true;
				continue;
			}
			if(inEscape) {
				lastPos = pos + 1;
				inEscape = false;
				switch(c) {
					case 'n':
						unescaped ~= '\n';
					break;
					case 't':
						unescaped ~= '\t';
					break;
					case '\\':
						unescaped ~= '\\';
					break;
					default: throw new ScriptCompileException("literal escape unknown " ~ c, 0, null, 0);
				}
			}
		}

		if(changed)
			literal = cast(string) unescaped;
		else
			literal = s;
	}

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(var(literal), sc);
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

	this(string s) {
		literal = to!long(s);
	}

	override string toString() { return to!string(literal); }

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(var(literal), sc);
	}
}
class FloatLiteralExpression : Expression {
	this(string s) {
		literal = to!real(s);
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
		string s = "json!q{";
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
		foreach(possibleType; CtList!("int", "long", "float", "double", "real", "char", "dchar", "string", "int[]", "string[]", "float[]")) {
			if(type == possibleType)
				n = mixin("cast(" ~ possibleType ~ ") n");
		}

		return InterpretResult(n, sc);
	}
}

class VariableDeclaration : Expression {
	string[] identifiers;
	Expression[] initializers;

	this() {}

	override string toString() {
		string s = "";
		foreach(i, ident; identifiers) {
			if(i)
				s ~= ", ";
			s ~= "var " ~ ident;
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

template CtList(T...) { alias CtList = T; }

class BinaryExpression : Expression {
	string op;
	Expression e1;
	Expression e2;

	override string toString() {
		return e1.toString() ~ " " ~ op ~ " " ~ e2.toString();
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
		foreach(ctOp; CtList!("+", "-", "*", "/", "==", "!=", "<=", ">=", ">", "<", "~", "&&", "||", "&", "|", "^"))
			if(ctOp == op) {
				n = mixin("left "~ctOp~" right");
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
			throw new ScriptRuntimeException("not an lvalue", 0 /* FIXME */);

		var right = e2.interpret(sc).value;

		//writeln(left, " "~op~"= ", right);

		var n;
		foreach(ctOp; CtList!("+=", "-=", "*=", "/=", "~=", "&=", "|=", "^="))
			if(ctOp[0..1] == op)
				n = mixin("v.getVar(sc) "~ctOp~" right");

		// FIXME: ensure the variable is updated in scope too

		return InterpretResult(n, sc);

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
			throw new ScriptRuntimeException("not an lvalue", 0 /* FIXME */);

		auto ret = v.setVar(sc, e2.interpret(sc).value, false, suppressOverloading);

		return InterpretResult(ret, sc);
	}
}


class UnaryExpression : Expression {
	string op;
	Expression e;
	// FIXME

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult();
	}
}

class VariableExpression : Expression {
	string identifier;

	this(string identifier) {
		this.identifier = identifier;
	}

	override string toString() {
		return identifier;
	}

	ref var getVar(PrototypeObject sc, bool recurse = true) {
		return sc._getMember(identifier, true /* FIXME: recurse?? */, true);
	}

	ref var setVar(PrototypeObject sc, var t, bool recurse = true, bool suppressOverloading = false) {
		return sc._setMember(identifier, t, true /* FIXME: recurse?? */, true, suppressOverloading);
	}

	ref var getVarFrom(PrototypeObject sc, ref var v) {
		return v[identifier];
	}

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(getVar(sc), sc);
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

	override ref var getVar(PrototypeObject sc, bool recurse = true) {
		if(!this.recurse) {
			// this is a special hack...
			if(auto ve = cast(VariableExpression) e1) {
				return ve.getVar(sc)._getOwnProperty(e2.identifier);
			}
			assert(0);
		}

		if(auto ve = cast(VariableExpression) e1)
			return this.getVarFrom(sc, ve.getVar(sc, recurse));
		else {
			// make a temporary for the lhs
			auto v = new var();
			*v = e1.interpret(sc).value;
			return this.getVarFrom(sc, *v);
		}
	}

	override ref var setVar(PrototypeObject sc, var t, bool recurse = true, bool suppressOverloading = false) {
		if(suppressOverloading)
			return e1.interpret(sc).value.opIndexAssignNoOverload(t, e2.identifier);
		else
			return e1.interpret(sc).value.opIndexAssign(t, e2.identifier);
	}


	override ref var getVarFrom(PrototypeObject sc, ref var v) {
		return e2.getVarFrom(sc, v);
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

	override ref var getVar(PrototypeObject sc, bool recurse = true) {
		if(auto ve = cast(VariableExpression) e1)
			return ve.getVar(sc, recurse)[e2.interpret(sc).value];
		else {
			auto v = new var();
			*v = e1.interpret(sc).value;
			return this.getVarFrom(sc, *v);
		}
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

class ForeachExpression : Expression {
	VariableDeclaration decl;
	Expression subject;
	Expression loopBody;

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
		foreach(i, item; what) {
			mixin(doLoopBody());
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
		string code = "if(";
		code ~= condition.toString();
		code ~= ") ";
		if(ifTrue !is null)
			code ~= ifTrue.toString();
		else
			code ~= " { }";
		if(ifFalse !is null)
			code ~= " else " ~ ifFalse.toString();
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
			throw new ScriptRuntimeException("not an lvalue", 0 /* FIXME */);

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
		var n = original._copy;
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
		throw new ScriptException(whatToThrow.interpret(sc).value, where.lineNumber);
		assert(0);
	}
}

class ExceptionBlockExpression : Expression {
	Expression tryExpression;

	string[] catchVarDecls;
	Expression[] catchExpressions;

	Expression[] finallyExpressions;

	override InterpretResult interpret(PrototypeObject sc) {
		InterpretResult result;
		result.sc = sc;
		assert(tryExpression !is null);
		assert(catchVarDecls.length == catchExpressions.length);

		if(catchExpressions.length || (catchExpressions.length == 0 && finallyExpressions.length == 0))
			try {
				result = tryExpression.interpret(sc);
			} catch(Exception e) {
				var ex = var.emptyObject;
				ex.type = typeid(e).name;
				ex.msg = e.msg;
				ex.file = e.file;
				ex.line = e.line;

				// FIXME: this only allows one but it might be nice to actually do different types at some point
				if(catchExpressions.length)
				foreach(i, ce; catchExpressions) {
					auto catchScope = new PrototypeObject();
					catchScope.prototype = sc;
					catchScope._getMember(catchVarDecls[i], false, false) = ex;

					result = ce.interpret(catchScope);
				} else
					result = InterpretResult(ex, sc);
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

	override InterpretResult interpret(PrototypeObject sc) {
		return InterpretResult(inside.interpret(sc).value, sc);
	}
}

PrototypeObject DefaultArgumentDummyObject;

class CallExpression : Expression {
	Expression func;
	Expression[] arguments;

	override string toString() {
		string s = func.toString() ~ "(";
		foreach(i, arg; arguments) {
			if(i) s ~= ", ";
			s ~= arg.toString();
		}

		s ~= ")";
		return s;
	}

	this(Expression func) {
		this.func = func;
	}

	override InterpretResult interpret(PrototypeObject sc) {
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
		} else if(auto ide = cast(IndexExpression) func)
			_this = ide.interpret(sc).value;

		return InterpretResult(f.apply(_this, args), sc);
	}
}

ScriptToken requireNextToken(MyTokenStreamHere)(ref MyTokenStreamHere tokens, ScriptToken.Type type, string str = null, string file = __FILE__, size_t line = __LINE__) {
	if(tokens.empty)
		throw new ScriptCompileException("script ended prematurely", 0, file, line);
	auto next = tokens.front;
	if(next.type != type || (str !is null && next.str != str))
		throw new ScriptCompileException("unexpected '"~next.str~"'", next.lineNumber, file, line);

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
		return new VariableExpression(token.str);
	}
	throw new ScriptCompileException("Found "~token.str~" when expecting identifier", token.lineNumber);
}

Expression parsePart(MyTokenStreamHere)(ref MyTokenStreamHere tokens) {
	if(!tokens.empty) {
		auto token = tokens.front;

		Expression e;
		if(token.type == ScriptToken.Type.identifier)
			e = parseVariableName(tokens);
		else {
			tokens.popFront();

			if(token.type == ScriptToken.Type.int_number)
				e = new IntLiteralExpression(token.str);
			else if(token.type == ScriptToken.Type.float_number)
				e = new FloatLiteralExpression(token.str);
			else if(token.type == ScriptToken.Type.string)
				e = new StringLiteralExpression(token.str);
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
						return parenthetical;
					case "[":
						// array literal
						auto arr = new ArrayLiteralExpression();

						bool first = true;
						moreElements:
						if(tokens.empty)
							throw new ScriptCompileException("unexpected end of file when reading array literal", token.lineNumber);

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
							throw new ScriptCompileException("unexpected end of file when reading object literal", token.lineNumber);

						moreKeys:
						auto key = tokens.front;
						tokens.popFront();
						if(key.type == ScriptToken.Type.symbol && key.str == "}") {
							// all done!
							e = obj;
							break;
						}
						if(key.type != ScriptToken.Type.string && key.type != ScriptToken.Type.identifier) {
							throw new ScriptCompileException("unexpected '"~key.str~"' when reading object literal", key.lineNumber);

						}

						tokens.requireNextToken(ScriptToken.Type.symbol, ":");

						auto value = parseExpression(tokens);
						if(tokens.empty)
							throw new ScriptCompileException("unclosed object literal", key.lineNumber);

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
				throw new ScriptCompileException("unexpected '"~token.str~"' when reading ident", token.lineNumber);
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
	assert(0, to!string(tokens));
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
		throw new ScriptCompileException("unexpected end of file when parsing call expression", peek.lineNumber);
	peek = tokens.front;
	if(peek.type == ScriptToken.Type.symbol && peek.str == ",") {
		tokens.popFront();
		goto moreArguments;
	} else if(peek.type == ScriptToken.Type.symbol && peek.str == ")") {
		tokens.popFront();
		return exp;
	} else
		throw new ScriptCompileException("unexpected '"~peek.str~"' when reading argument list", peek.lineNumber);

}

Expression parseFunctionCall(MyTokenStreamHere)(ref MyTokenStreamHere tokens, Expression e) {
	assert(!tokens.empty);
	auto peek = tokens.front;
	auto exp = new CallExpression(e);
	tokens.popFront();
	if(tokens.empty)
		throw new ScriptCompileException("unexpected end of file when parsing call expression", peek.lineNumber);
	return parseArguments(tokens, exp, exp.arguments);
}

Expression parseFactor(MyTokenStreamHere)(ref MyTokenStreamHere tokens) {
	auto e1 = parsePart(tokens);
	loop: while(!tokens.empty) {
		auto peek = tokens.front;

		if(peek.type == ScriptToken.Type.symbol) {
			switch(peek.str) {
				case "*":
				case "/":
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
					return e1;

				case ".":
					tokens.popFront();
					e1 = new DotVarExpression(e1, parseVariableName(tokens));
				break;
				case "=":
					tokens.popFront();
					return new AssignExpression(e1, parseExpression(tokens));
				case "~":
					// FIXME: make sure this has the right associativity

				case "&&": // FIXME: precedence?
				case "||":

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
					tokens.popFront();
					return new OpAssignExpression(peek.str[0..1], e1, parseExpression(tokens));
				default:
					throw new ScriptCompileException("Parse error, unexpected " ~ peek.str ~ " when looking for operator", peek.lineNumber);
			}
		//} else if(peek.type == ScriptToken.Type.identifier || peek.type == ScriptToken.Type.number) {
			//return parseFactor(tokens);
		} else
			throw new ScriptCompileException("Parse error, unexpected '" ~ peek.str ~ "'", peek.lineNumber);
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
					throw new ScriptCompileException("unexpected " ~ ident.str ~ ". valid scope(idents) are success, failure, and exit", ident.lineNumber);
			}

			tokens.requireNextToken(ScriptToken.Type.symbol, ")");

			string i = "__scope_" ~ ident.str;
			auto literal = new FunctionLiteralExpression();
			literal.functionBody = parseExpression(tokens);

			auto e = new OpAssignExpression("~", new VariableExpression(i), literal);
			ret = e;
		} else if(tokens.peekNextToken(ScriptToken.Type.symbol, "(")) {
			auto start = tokens.front;
			tokens.popFront();
			auto parenthetical = new ParentheticalExpression(parseExpression(tokens));
			tokens.requireNextToken(ScriptToken.Type.symbol, ")");
			if(tokens.peekNextToken(ScriptToken.Type.symbol, "(")) {
				// we have a function call, e.g. (test)()
				ret = parseFunctionCall(tokens, parenthetical);
			} else
				ret = parenthetical;
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "new")) {
			auto start = tokens.front;
			tokens.popFront();

			auto expr = parseVariableName(tokens);
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
					auto args = parseVariableDeclaration(tokens, ")");
					tokens.requireNextToken(ScriptToken.Type.symbol, ")");
					auto bod = parseExpression(tokens);

					expressions ~= new AssignExpression(
						new DotVarExpression(
							new VariableExpression("__proto"),
							new VariableExpression(ident.str),
							false),
						new FunctionLiteralExpression(args, bod, staticScopeBacking));
				} else throw new ScriptCompileException("Unexpected " ~ tokens.front.str ~ " when reading class decl", tokens.front.lineNumber);
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
			e.condition = parseExpression(tokens);
			e.ifTrue = parseExpression(tokens);
			if(tokens.peekNextToken(ScriptToken.Type.symbol, ";")) {
				tokens.popFront();
			}
			if(tokens.peekNextToken(ScriptToken.Type.keyword, "else")) {
				tokens.popFront();
				e.ifFalse = parseExpression(tokens);
			}
			ret = e;
		} else if(tokens.peekNextToken(ScriptToken.Type.keyword, "foreach")) {
			tokens.popFront();
			auto e = new ForeachExpression();
			tokens.requireNextToken(ScriptToken.Type.symbol, "(");
			e.decl = parseVariableDeclaration(tokens, ";");
			tokens.requireNextToken(ScriptToken.Type.symbol, ";");
			e.subject = parseExpression(tokens);
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
			e.condition = parseExpression(tokens);
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

			bool hadSomething = false;
			while(tokens.peekNextToken(ScriptToken.Type.keyword, "catch")) {
				if(hadSomething)
					throw new ScriptCompileException("Only one catch block is allowed currently ", tokens.front.lineNumber);
				hadSomething = true;
				tokens.popFront();
				tokens.requireNextToken(ScriptToken.Type.symbol, "(");
				if(tokens.peekNextToken(ScriptToken.Type.keyword, "var"))
					tokens.popFront();
				auto ident = tokens.requireNextToken(ScriptToken.Type.identifier);
				e.catchVarDecls ~= ident.str;
				tokens.requireNextToken(ScriptToken.Type.symbol, ")");
				e.catchExpressions ~= parseExpression(tokens);
			}
			while(tokens.peekNextToken(ScriptToken.Type.keyword, "finally")) {
				hadSomething = true;
				tokens.popFront();
				e.finallyExpressions ~= parseExpression(tokens);
			}

			//if(!hadSomething)
				//throw new ScriptCompileException("Parse error, missing finally or catch after try", tryToken.lineNumber);

			ret = e;
		} else
			ret = parseAddend(tokens);
	} else {
		assert(0);
		// return null;
	//	throw new ScriptCompileException("Parse error, unexpected end of input when reading expression", token.lineNumber);
	}

	//writeln("parsed expression ", ret.toString());

	if(expectedEnd.length && tokens.empty)
		throw new ScriptCompileException("Parse error, unexpected end of input when reading expression, expecting " ~ expectedEnd, first.lineNumber);

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
		throw new ScriptCompileException("Parse error, dangling var at end of file", firstToken.lineNumber);

	Expression initializer;
	auto identifier = tokens.front;
	if(identifier.type != ScriptToken.Type.identifier)
		throw new ScriptCompileException("Parse error, found '"~identifier.str~"' when expecting var identifier", identifier.lineNumber);

	tokens.popFront();

	tryTermination:
	if(tokens.empty)
		throw new ScriptCompileException("Parse error, missing ; after var declaration at end of file", firstToken.lineNumber);

	auto peek = tokens.front;
	if(peek.type == ScriptToken.Type.symbol) {
		if(peek.str == "=") {
			if(!equalOk)
				throw new ScriptCompileException("Parse error, unexpected '"~identifier.str~"' after reading var initializer", peek.lineNumber);
			equalOk = false;
			tokens.popFront();
			initializer = parseExpression(tokens);
			goto tryTermination;
		} else if(peek.str == ",") {
			tokens.popFront();
			decl.identifiers ~= identifier.str;
			decl.initializers ~= initializer;
			goto anotherVar;
		} else if(peek.str == termination) {
			decl.identifiers ~= identifier.str;
			decl.initializers ~= initializer;
			//tokens = tokens[1 .. $];
			// we're done!
		} else
			throw new ScriptCompileException("Parse error, unexpected '"~peek.str~"' when reading var declaration", peek.lineNumber);
	} else
		throw new ScriptCompileException("Parse error, unexpected '"~peek.str~"' when reading var declaration", peek.lineNumber);

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

						auto e = new VariableDeclaration();
						e.identifiers ~= ident.str;
						e.initializers ~= exp;

						exp.isMacro = token.str == "macro";

						return e;

					} else {
						tokens.pushFront(token); // put it back since everyone expects us to have done that
						goto case; // handle it like any other expression
					}
				case "json!{":
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

				// flow control
				case "if":
				case "while":
				case "for":
				case "foreach":

				// exceptions
				case "try":
				case "throw":

				// flow
				case "continue":
				case "break":
				case "return":
					return parseExpression(tokens);
				// unary prefix operators
				case "!":
				case "~":
				case "-":

				// BTW add custom object operator overloading to struct var
				// and custom property overloading to PrototypeObject

				default:
					// whatever else keyword or operator related is actually illegal here
					throw new ScriptCompileException("Parse error, unexpected " ~ token.str, token.lineNumber);
			}
		// break;
		case ScriptToken.Type.identifier:
		case ScriptToken.Type.string:
		case ScriptToken.Type.int_number:
		case ScriptToken.Type.float_number:
			return parseExpression(tokens);
	}

	assert(0);
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
			throw new ScriptCompileException("Reached end of file while trying to reach matching " ~ terminatingSymbol, startingLine);
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

var interpret(string code, var variables = null, string scriptFilename = null) {
	return interpretStream(
		lexScript(repeat(code, 1), scriptFilename),
		(variables.payloadType() == var.Type.Object && variables._payload._object !is null) ? variables._payload._object : new PrototypeObject());
}

var interpretFile(File file, var globals) {
	import std.algorithm;
	return interpretStream(lexScript(file.byLine.map!((a) => a.idup), file.name),
		(globals.payloadType() == var.Type.Object && globals._payload._object !is null) ? globals._payload._object : new PrototypeObject());
}

void repl(var globals) {
	import std.stdio;
	import std.algorithm;
	auto variables = (globals.payloadType() == var.Type.Object && globals._payload._object !is null) ? globals._payload._object : new PrototypeObject();

	// we chain to ensure the priming popFront succeeds so we don't throw here
	auto tokens = lexScript(
		chain(["var __skipme = 0;"], map!((a) => a.idup)(stdin.byLine))
	, "stdin");
	auto expressions = parseScript(tokens);

	while(!expressions.empty) {
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
