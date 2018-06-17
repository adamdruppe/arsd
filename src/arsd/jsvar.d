/*
	FIXME:
		pointer to member functions can give a way to wrap things

		we'll pass it an opaque object as this and it will unpack and call the method

		we can also auto-generate getters and setters for properties with this method

		and constructors, so the script can create class objects too
*/


/++
	jsvar provides a D type called [var] that works similarly to the same in Javascript.

	It is weakly (even weaker than JS, frequently returning null rather than throwing on
	an invalid operation) and dynamically typed, but interops pretty easily with D itself:

	---
	var a = 10;
	a ~= "20";
		assert(a == "1020");

	var a = function(int b, int c) { return b+c; };
	// note the second set of () is because of broken @property
	assert(a()(10,20) == 30);

	var a = var.emptyObject;
	a.foo = 30;
	assert(a["foo"] == 30);

	var b = json!q{
		"foo":12,
		"bar":{"hey":[1,2,3,"lol"]}
	};

	assert(b.bar.hey[1] == 2);
	---


	You can also use [var.fromJson], a static method, to quickly and easily
	read json or [var.toJson] to write it.

	Also, if you combine this with my [arsd.script] module, you get pretty
	easy interop with a little scripting language that resembles a cross between
	D and Javascript - just like you can write in D itself using this type.


	Properties:
	$(LIST
		* note that @property doesn't work right in D, so the opDispatch properties
		  will require double parenthesis to call as functions.

		* Properties inside a var itself are set specially:
			obj.propName._object = new PropertyPrototype(getter, setter);
	)

	D structs can be turned to vars, but it is a copy.

	Wrapping D native objects is coming later, the current ways suck. I really needed
	properties to do them sanely at all, and now I have it. A native wrapped object will
	also need to be set with _object prolly.
+/
module arsd.jsvar;

version=new_std_json;

import std.stdio;
static import std.array;
import std.traits;
import std.conv;
import std.json;

// uda for wrapping classes
enum scriptable = "arsd_jsvar_compatible";

/*
	PrototypeObject FIXME:
		make undefined variables reaction overloadable in PrototypeObject, not just a switch

	script FIXME:

	the Expression should keep scriptFilename and lineNumber around for error messages

	it should consistently throw on missing semicolons

	*) in operator

	*) nesting comments, `` string literals
	*) opDispatch overloading
	*) properties???//
		a.prop on the rhs => a.prop()
		a.prop on the lhs => a.prop(rhs);
		if opAssign, it can just do a.prop(a.prop().opBinary!op(rhs));

		But, how do we mark properties in var? Can we make them work this way in D too?
	0) add global functions to the object (or at least provide a convenience function to make a pre-populated global object)
	1) ensure operator precedence is sane
	2) a++ would prolly be nice, and def -a
	4) switches?
	10) __FILE__ and __LINE__ as default function arguments should work like in D
	16) stack traces on script exceptions
	17) an exception type that we can create in the script

	14) import???????/ it could just attach a particular object to the local scope, and the module decl just giving the local scope a name
		there could be a super-global object that is the prototype of the "global" used here
		then you import, and it pulls moduleGlobal.prototype = superGlobal.modulename... or soemthing.

		to get the vars out in D, you'd have to be aware of this, since you pass the superglobal
		hmmm maybe not worth it

		though maybe to export vars there could be an explicit export namespace or something.


	6) gotos? labels? labeled break/continue?
	18) what about something like ruby's blocks or macros? parsing foo(arg) { code } is easy enough, but how would we use it?

	var FIXME:

	user defined operator overloading on objects, including opCall, opApply, and more
	flesh out prototype objects for Array, String, and Function

	looserOpEquals

	it would be nice if delegates on native types could work
*/


/*
	Script notes:

	the one type is var. It works just like the var type in D from arsd.jsvar.
	(it might be fun to try to add other types, and match D a little better here! We could allow implicit conversion to and from var, but not on the other types, they could get static checking. But for now it is only var. BTW auto is an alias for var right now)

	There is no comma operator, but you can use a scope as an expression: a++, b++; can be written as {a++;b++;}
*/

version(test_script)
	struct Foop {
		int a = 12;
		string n = "hate";
		void speak() { writeln(n, " ", a); n = "love"; writeln(n, " is what it is now"); }
		void speak2() { writeln("speak2 ", n, " ", a); }
	}
version(test_script)
void main() {
import arsd.script;
writeln(interpret("x*x + 3*x;", var(["x":3])));

	{
	var a = var.emptyObject;
	a.qweq = 12;
	}

	// the WrappedNativeObject is disgusting
	// but works. sort of.
	/*
	Foop foop2;

	var foop;
	foop._object = new WrappedNativeObject!Foop(foop2);

	foop.speak()();
	foop.a = 25;
	writeln(foop.n);
	foop.speak2()();
	return;
	*/

	import arsd.script;
	struct Test {
		int a = 10;
		string name = "ten";
	}

	auto globals = var.emptyObject;
	globals.lol = 100;
	globals.rofl = 23;

	globals.arrtest = var.emptyArray;

	globals.write._function = (var _this, var[] args) {
		string s;
		foreach(a; args)
			s ~= a.get!string;
		writeln("script said: ", s);
		return var(null);
	};

	// call D defined functions in script
	globals.func = (var a, var b) { writeln("Hello, world! You are : ", a, " and ", b); };

	globals.ex = () { throw new ScriptRuntimeException("test", 1); };

	globals.fun = { return var({ writeln("hello inside!"); }); };

	import std.file;
	writeln(interpret(readText("scripttest_code.d"), globals));

	globals.ten = 10.0;
	globals.five = 5.0;
	writeln(interpret(q{
		var a = json!q{ };
		a.b = json!q{ };
		a.b.c = 10;
		a;
	}, globals));

	/*
	globals.minigui = json!q{};
	import arsd.minigui;
	globals.minigui.createWindow = {
		var v;
		auto mw = new MainWindow();
		v._object = new OpaqueNativeObject!(MainWindow)(mw);
		v.loop = { mw.loop(); };
		return v;
	};
	*/

	repl(globals);

	writeln("BACK IN D!");
	globals.c()(10); // call script defined functions in D (note: this runs the interpreter)

	//writeln(globals._getMember("lol", false));
	return;

	var k,l ;

	var j = json!q{
		"hello": {
			"data":[1,2,"giggle",4]
		},
		"world":20
	};

	writeln(j.hello.data[2]);


	Test t;
	var rofl = t;
	writeln(rofl.name);
	writeln(rofl.a);

	rofl.a = "20";
	rofl.name = "twenty";

	t = rofl.get!Test;
	writeln(t);

	var a1 = 10;
	a1 -= "5";
	a1 /= 2;

	writeln(a1);

	var a = 10;
	var b = 20;
	a = b;

	b = 30;
	a += 100.2;
	writeln(a);

	var c = var.emptyObject;
	c.a = b;

	var d = c;
	d.b = 50;

	writeln(c.b);

	writeln(d.toJson());

	var e = a + b;
	writeln(a, " + ", b, " = ", e);

	e = function(var lol) {
		writeln("hello with ",lol,"!");
		return lol + 10;
	};

	writeln(e("15"));

	if(var("ass") > 100)
		writeln(var("10") / "3");
}

template json(string s) {
	// ctfe doesn't support the unions std.json uses :(
	//enum json = var.fromJsonObject(s);

	// FIXME we should at least validate string s at compile time
	var json() {
		return var.fromJson("{" ~ s ~ "}");
	}
}

// literals

// var a = varArray(10, "cool", 2);
// assert(a[0] == 10); assert(a[1] == "cool"); assert(a[2] == 2);
var varArray(T...)(T t) {
	var a = var.emptyArray;
	foreach(arg; t)
		a ~= var(arg);
	return a;
}

// var a = varObject("cool", 10, "bar", "baz");
// assert(a.cool == 10 && a.bar == "baz");
var varObject(T...)(T t) {
	var a = var.emptyObject;

	string lastString;
	foreach(idx, arg; t) {
		static if(idx % 2 == 0) {
			lastString = arg;
		} else {
			assert(lastString !is null);
			a[lastString] = arg;
			lastString = null;
		}
	}
	return a;
}


private real stringToNumber(string s) {
	real r;
	try {
		r = to!real(s);
	} catch (Exception e) {
		r = real.nan;
	}

	return r;
}

private bool realIsInteger(real r) {
	return (r == cast(long) r);
}

// helper template for operator overloading
private var _op(alias _this, alias this2, string op, T)(T t) if(op == "~") {
	static if(is(T == var)) {
		if(t.payloadType() == var.Type.Array)
			return _op!(_this, this2, op)(t._payload._array);
		else if(t.payloadType() == var.Type.String)
			return _op!(_this, this2, op)(t._payload._string);
		//else
			//return _op!(_this, this2, op)(t.get!string);
	}

	if(this2.payloadType() == var.Type.Array) {
		auto l = this2._payload._array;
		static if(isArray!T && !isSomeString!T)
			foreach(item; t)
				l ~= var(item);
		else
			l ~= var(t);

		_this._type = var.Type.Array;
		_this._payload._array = l;
		return _this;
	} else if(this2.payloadType() == var.Type.String) {
		auto l = this2._payload._string;
		l ~= var(t).get!string; // is this right?
		_this._type = var.Type.String;
		_this._payload._string = l;
		return _this;
	} else {
		auto l = this2.get!string;
		l ~= var(t).get!string;
		_this._type = var.Type.String;
		_this._payload._string = l;
		return _this;
	}

	assert(0);

}

// FIXME: maybe the bitops should be moved out to another function like ~ is
private var _op(alias _this, alias this2, string op, T)(T t) if(op != "~") {
	static if(is(T == var)) {
		if(t.payloadType() == var.Type.Integral)
			return _op!(_this, this2, op)(t._payload._integral);
		if(t.payloadType() == var.Type.Floating)
			return _op!(_this, this2, op)(t._payload._floating);
		if(t.payloadType() == var.Type.String)
			return _op!(_this, this2, op)(t._payload._string);
		assert(0, to!string(t.payloadType()));
	} else {
		if(this2.payloadType() == var.Type.Integral) {
			auto l = this2._payload._integral;
			static if(isIntegral!T) {
				mixin("l "~op~"= t;");
				_this._type = var.Type.Integral;
				_this._payload._integral = l;
				return _this;
			} else static if(isFloatingPoint!T) {
				static if(op == "&" || op == "|" || op == "^") {
					this2._type = var.Type.Integral;
					long f = l;
					mixin("f "~op~"= cast(long) t;");
					_this._type = var.Type.Integral;
					_this._payload._integral = f;
				} else {
					this2._type = var.Type.Floating;
					real f = l;
					mixin("f "~op~"= t;");
					_this._type = var.Type.Floating;
					_this._payload._floating = f;
				}
				return _this;
			} else static if(isSomeString!T) {
				auto rhs = stringToNumber(t);
				if(realIsInteger(rhs)) {
					mixin("l "~op~"= cast(long) rhs;");
					_this._type = var.Type.Integral;
					_this._payload._integral = l;
				} else{
					static if(op == "&" || op == "|" || op == "^") {
						long f = l;
						mixin("f "~op~"= cast(long) rhs;");
						_this._type = var.Type.Integral;
						_this._payload._integral = f;
					} else {
						real f = l;
						mixin("f "~op~"= rhs;");
						_this._type = var.Type.Floating;
						_this._payload._floating = f;
					}
				}
				return _this;

			}
		} else if(this2.payloadType() == var.Type.Floating) {
			auto f = this._payload._floating;

			static if(isIntegral!T || isFloatingPoint!T) {
				static if(op == "&" || op == "|" || op == "^") {
					long argh = cast(long) f;
					mixin("argh "~op~"= cast(long) t;");
					_this._type = var.Type.Integral;
					_this._payload._integral = argh;
				} else {
					mixin("f "~op~"= t;");
					_this._type = var.Type.Floating;
					_this._payload._floating = f;
				}
				return _this;
			} else static if(isSomeString!T) {
				auto rhs = stringToNumber(t);

				static if(op == "&" || op == "|" || op == "^") {
					long pain = cast(long) f;
					mixin("pain "~op~"= cast(long) rhs;");
					_this._type = var.Type.Integral;
					_this._payload._floating = pain;
				} else {
					mixin("f "~op~"= rhs;");
					_this._type = var.Type.Floating;
					_this._payload._floating = f;
				}
				return _this;
			} else static assert(0);
		} else if(this2.payloadType() == var.Type.String) {
			static if(op == "&" || op == "|" || op == "^") {
				long r = cast(long) stringToNumber(this2._payload._string);
				long rhs;
			} else {
				real r = stringToNumber(this2._payload._string);
				real rhs;
			}

			static if(isSomeString!T) {
				rhs = cast(typeof(rhs)) stringToNumber(t);
			} else {
				rhs = to!(typeof(rhs))(t);
			}

			mixin("r " ~ op ~ "= rhs;");

			static if(is(typeof(r) == real)) {
				_this._type = var.Type.Floating;
				_this._payload._floating = r;
			} else static if(is(typeof(r) == long)) {
				_this._type = var.Type.Integral;
				_this._payload._integral = r;
			} else static assert(0);
			return _this;
		} else {
			// the operation is nonsensical, we should throw or ignore it
			var i = 0;
			return i;
		}
	}

	assert(0);
}


///
struct var {
	public this(T)(T t) {
		static if(is(T == var))
			this = t;
		else
			this.opAssign(t);
	}

	public var _copy() {
		final switch(payloadType()) {
			case Type.Integral:
			case Type.Boolean:
			case Type.Floating:
			case Type.Function:
			case Type.String:
				// since strings are immutable, we can pretend they are value types too
				return this; // value types don't need anything special to be copied

			case Type.Array:
				var cp;
				cp = this._payload._array[];
				return cp;
			case Type.Object:
				var cp;
				if(this._payload._object !is null)
					cp._object = this._payload._object.copy;
				return cp;
		}
	}

	public bool opCast(T:bool)() {
		final switch(this._type) {
			case Type.Object:
				return this._payload._object !is null;
			case Type.Array:
				return this._payload._array.length != 0;
			case Type.String:
				return this._payload._string.length != 0;
			case Type.Integral:
				return this._payload._integral != 0;
			case Type.Floating:
				return this._payload._floating != 0;
			case Type.Boolean:
				return this._payload._boolean;
			case Type.Function:
				return this._payload._function !is null;
		}
	}

	public int opApply(scope int delegate(ref var) dg) {
		foreach(i, item; this)
			if(auto result = dg(item))
				return result;
		return 0;
	}

	public int opApply(scope int delegate(var, ref var) dg) {
		if(this.payloadType() == Type.Array) {
			foreach(i, ref v; this._payload._array)
				if(auto result = dg(var(i), v))
					return result;
		} else if(this.payloadType() == Type.Object && this._payload._object !is null) {
			// FIXME: if it offers input range primitives, we should use them
			// FIXME: user defined opApply on the object
			foreach(k, ref v; this._payload._object)
				if(auto result = dg(var(k), v))
					return result;
		} else if(this.payloadType() == Type.String) {
			// this is to prevent us from allocating a new string on each character, hopefully limiting that massively
			static immutable string chars = makeAscii!();

			foreach(i, dchar c; this._payload._string) {
				var lol = "";
				if(c < 128)
					lol._payload._string = chars[c .. c + 1];
				else
					lol._payload._string = to!string(""d ~ c); // blargh, how slow can we go?
				if(auto result = dg(var(i), lol))
					return result;
			}
		}
		// throw invalid foreach aggregate

		return 0;
	}


	public T opCast(T)() {
		return this.get!T;
	}

	public auto ref putInto(T)(ref T t) {
		return t = this.get!T;
	}

	// if it is var, we'll just blit it over
	public var opAssign(T)(T t) if(!is(T == var)) {
		static if(isFloatingPoint!T) {
			this._type = Type.Floating;
			this._payload._floating = t;
		} else static if(isIntegral!T) {
			this._type = Type.Integral;
			this._payload._integral = t;
		} else static if(isCallable!T) {
			this._type = Type.Function;
			static if(is(T == typeof(this._payload._function))) {
				this._payload._function = t;
			} else
			this._payload._function = delegate var(var _this, var[] args) {
				var ret;

				ParameterTypeTuple!T fargs;
				foreach(idx, a; fargs) {
					if(idx == args.length)
						break;
					cast(Unqual!(typeof(a))) fargs[idx] = args[idx].get!(typeof(a));
				}

				static if(is(ReturnType!t == void)) {
					t(fargs);
				} else {
					ret = t(fargs);
				}

				return ret;
			};
		} else static if(isSomeString!T) {
			this._type = Type.String;
			this._payload._string = to!string(t);
		} else static if(is(T : PrototypeObject)) {
			// support direct assignment of pre-made implementation objects
			// so prewrapped stuff can be easily passed.
			this._type = Type.Object;
			this._payload._object = t;
		} else static if(is(T == class) || .isScriptableOpaque!T) {
			// auto-wrap other classes with reference semantics
			this._type = Type.Object;
			this._payload._object = wrapOpaquely(t);
		} else static if(is(T == struct) || isAssociativeArray!T) {
			// copy structs and assoc arrays by value into a var object
			this._type = Type.Object;
			auto obj = new PrototypeObject();
			this._payload._object = obj;

			static if(is(T == struct))
			foreach(member; __traits(allMembers, T)) {
				static if(__traits(compiles, __traits(getMember, t, member))) {
					static if(is(typeof(__traits(getMember, t, member)) == function)) {
						// skipping these because the delegate we get isn't going to work anyway; the object may be dead and certainly won't be updated
						//this[member] = &__traits(getMember, proxyObject, member);
					} else
						this[member] = __traits(getMember, t, member);
				}
			} else {
				// assoc array
				foreach(l, v; t) {
					this[var(l)] = var(v);
				}
			}
		} else static if(isArray!T) {
			this._type = Type.Array;
			var[] arr;
			arr.length = t.length;
			static if(!is(T == void[])) // we can't append a void array but it is nice to support x = [];
				foreach(i, item; t)
					arr[i] = var(item);
			this._payload._array = arr;
		} else static if(is(T == bool)) {
			this._type = Type.Boolean;
			this._payload._boolean = t;
		} else static if(isSomeChar!T) {
			this._type = Type.String;
			this._payload._string = "";
			import std.utf;
			char[4] ugh;
			auto size = encode(ugh, t);
			this._payload._string = ugh[0..size].idup;
		}// else static assert(0, "unsupported type");

		return this;
	}

	public size_t opDollar() {
		return this.length().get!size_t;
	}

	public var opOpAssign(string op, T)(T t) {
		if(payloadType() == Type.Object) {
			var* operator = this._payload._object._peekMember("opOpAssign", true);
			if(operator !is null && operator._type == Type.Function)
				return operator.call(this, op, t);
		}

		return _op!(this, this, op, T)(t);
	}

	public var opUnary(string op : "-")() {
		static assert(op == "-");
		final switch(payloadType()) {
			case Type.Object:
			case Type.Array:
			case Type.Boolean:
			case Type.String:
			case Type.Function:
				assert(0); // FIXME
			break;
			case Type.Integral:
				return var(-this.get!long);
			case Type.Floating:
				return var(-this.get!double);
		}
	}

	public var opBinary(string op, T)(T t) {
		var n;
		if(payloadType() == Type.Object) {
			var* operator = this._payload._object._peekMember("opBinary", true);
			if(operator !is null && operator._type == Type.Function) {
				return operator.call(this, op, t);
			}
		}
		return _op!(n, this, op, T)(t);
	}

	public var opBinaryRight(string op, T)(T s) {
		return var(s).opBinary!op(this);
	}

	// this in foo
	public var* opBinary(string op : "in", T)(T s) {
		var rhs = var(s);
		return rhs.opBinaryRight!"in"(this);
	}

	// foo in this
	public var* opBinaryRight(string op : "in", T)(T s) {
		// this needs to be an object
		return var(s).get!string in this._object._properties;
	}

	public var apply(var _this, var[] args) {
		if(this.payloadType() == Type.Function) {
			if(this._payload._function is null) {
				version(jsvar_throw)
					throw new DynamicTypeException(this, Type.Function);
				else
					return var(null);
			}
			return this._payload._function(_this, args);
		} else if(this.payloadType() == Type.Object) {
			if(this._payload._object is null) {
				version(jsvar_throw)
					throw new DynamicTypeException(this, Type.Function);
				else
					return var(null);
			}
			var* operator = this._payload._object._peekMember("opCall", true);
			if(operator !is null && operator._type == Type.Function)
				return operator.apply(_this, args);
		}

		version(jsvar_throw)
			throw new DynamicTypeException(this, Type.Function);

		if(this.payloadType() == Type.Integral || this.payloadType() == Type.Floating) {
			if(args.length)
				return var(this.get!double * args[0].get!double);
		}

		//return this;
		return var(null);
	}

	public var call(T...)(var _this, T t) {
		var[] args;
		foreach(a; t) {
			args ~= var(a);
		}
		return this.apply(_this, args);
	}

	public var opCall(T...)(T t) {
		return this.call(this, t);
	}

	/*
	public var applyWithMagicLocals(var _this, var[] args, var[string] magicLocals) {

	}
	*/

	public string toString() {
		return this.get!string;
	}

	public T get(T)() if(!is(T == void)) {
		static if(is(T == var)) {
			return this;
		} else static if(__traits(compiles, T.fromJsVar(var.init))) {
			return T.fromJsVar(this);
		} else static if(__traits(compiles, T(this))) {
			return T(this);
		} else static if(__traits(compiles, new T(this))) {
			return new T(this);
		} else
		final switch(payloadType) {
			case Type.Boolean:
				static if(is(T == bool))
					return this._payload._boolean;
				else static if(isFloatingPoint!T || isIntegral!T)
					return cast(T) (this._payload._boolean ? 1 : 0); // the cast is for enums, I don't like this so FIXME
				else static if(isSomeString!T)
					return this._payload._boolean ? "true" : "false";
				else
				return T.init;
			case Type.Object:
				static if(isAssociativeArray!T) {
					T ret;
					if(this._payload._object !is null)
					foreach(k, v; this._payload._object._properties)
						ret[to!(KeyType!T)(k)] = v.get!(ValueType!T);

					return ret;
				} else static if(is(T : PrototypeObject)) {
					// they are requesting an implementation object, just give it to them
					return cast(T) this._payload._object;
				} else static if(isScriptableOpaque!(Unqual!T)) {
					if(auto wno = cast(WrappedOpaque!(Unqual!T)) this._payload._object) {
						return wno.wrapping();
					}
					static if(is(T == R*, R))
					if(auto wno = cast(WrappedOpaque!(Unqual!(R))) this._payload._object) {
						return wno.wrapping();
					}
					throw new DynamicTypeException(this, Type.Object); // FIXME: could be better
				} else static if(is(T == struct) || is(T == class)) {
					// first, we'll try to give them back the native object we have, if we have one
					static if(is(T : Object)) {
						if(auto wno = cast(WrappedNativeObject) this._payload._object) {
							auto no = cast(T) wno.getObject();
							if(no !is null)
								return no;
						}

						// FIXME: this is kinda weird.
						return null;
					} else {

						// failing that, generic struct or class getting: try to fill in the fields by name
						T t;
						bool initialized = true;
						static if(is(T == class)) {
							static if(__traits(compiles, new T()))
								t = new T();
							else
								initialized = false;
						}


						if(initialized)
						foreach(i, a; t.tupleof) {
							cast(Unqual!(typeof((a)))) t.tupleof[i] = this[t.tupleof[i].stringof[2..$]].get!(typeof(a));
						}

						return t;
					}
				} else static if(isSomeString!T) {
					if(this._object !is null)
						return this._object.toString();
					return "null";
				} else
					return T.init;
			case Type.Integral:
				static if(isFloatingPoint!T || isIntegral!T)
					return to!T(this._payload._integral);
				else static if(isSomeString!T)
					return to!string(this._payload._integral);
				else
					return T.init;
			case Type.Floating:
				static if(isFloatingPoint!T || isIntegral!T)
					return to!T(this._payload._floating);
				else static if(isSomeString!T)
					return to!string(this._payload._floating);
				else
					return T.init;
			case Type.String:
				static if(__traits(compiles, to!T(this._payload._string))) {
					try {
						return to!T(this._payload._string);
					} catch (Exception e) { return T.init; }
				} else
					return T.init;
			case Type.Array:
				import std.range;
				auto pl = this._payload._array;
				static if(isSomeString!T) {
					return to!string(pl);
				} else static if(isArray!T) {
					T ret;
					static if(is(ElementType!T == void)) {
						static assert(0, "try wrapping the function to get rid of void[] args");
						//alias getType = ubyte;
					} else
						alias getType = ElementType!T;
					foreach(item; pl)
						ret ~= item.get!(getType);
					return ret;
				} else
					return T.init;
				// is it sane to translate anything else?
			case Type.Function:
				static if(isSomeString!T)
					return "<function>";
				else static if(isDelegate!T) {
					// making a local copy because otherwise the delegate might refer to a struct on the stack and get corrupted later or something
					auto func = this._payload._function;

					// the static helper lets me pass specific variables to the closure
					static T helper(typeof(func) func) {
						return delegate ReturnType!T (ParameterTypeTuple!T args) {
							var[] arr;
							foreach(arg; args)
								arr ~= var(arg);
							var ret = func(var(null), arr);
							static if(is(ReturnType!T == void))
								return;
							else
								return ret.get!(ReturnType!T);
						};
					}

					return helper(func);

				} else
					return T.init;
				// FIXME: we just might be able to do better for both of these
			//break;
		}
	}

	public T nullCoalesce(T)(T t) {
		if(_type == Type.Object && _payload._object is null)
			return t;
		return this.get!T;
	}

	public int opCmp(T)(T t) {
		auto f = this.get!real;
		static if(is(T == var))
			auto r = t.get!real;
		else
			auto r = t;
		return cast(int)(f - r);
	}

	public bool opEquals(T)(T t) {
		return this.opEquals(var(t));
	}

	public bool opEquals(T:var)(T t) const {
		// FIXME: should this be == or === ?
		if(this._type != t._type)
			return false;
		final switch(this._type) {
			case Type.Object:
				return _payload._object is t._payload._object;
			case Type.Integral:
				return _payload._integral == t._payload._integral;
			case Type.Boolean:
				return _payload._boolean == t._payload._boolean;
			case Type.Floating:
				return _payload._floating == t._payload._floating; // FIXME: approxEquals?
			case Type.String:
				return _payload._string == t._payload._string;
			case Type.Function:
				return _payload._function is t._payload._function;
			case Type.Array:
				return _payload._array == t._payload._array;
		}
		assert(0);
	}

	public enum Type {
		Object, Array, Integral, Floating, String, Function, Boolean
	}

	public Type payloadType() {
		return _type;
	}

	private Type _type;

	private union Payload {
		PrototypeObject _object;
		var[] _array;
		long _integral;
		real _floating;
		string _string;
		bool _boolean;
		var delegate(var _this, var[] args) _function;
	}

	public void _function(var delegate(var, var[]) f) {
		this._payload._function = f;
		this._type = Type.Function;
	}

	/*
	public void _function(var function(var, var[]) f) {
		var delegate(var, var[]) dg;
		dg.ptr = null;
		dg.funcptr = f;
		this._function = dg;
	}
	*/

	public void _object(PrototypeObject obj) {
		this._type = Type.Object;
		this._payload._object = obj;
	}

	public PrototypeObject _object() {
		if(this._type == Type.Object)
			return this._payload._object;
		return null;
	}

	package Payload _payload;

	private void _requireType(Type t, string file = __FILE__, size_t line = __LINE__){
		if(this.payloadType() != t)
			throw new DynamicTypeException(this, t, file, line);
	}

	public var opSlice(var e1, var e2) {
		return this.opSlice(e1.get!ptrdiff_t, e2.get!ptrdiff_t);
	}

	public var opSlice(ptrdiff_t e1, ptrdiff_t e2) {
		if(this.payloadType() == Type.Array) {
			if(e1 > _payload._array.length)
				e1 = _payload._array.length;
			if(e2 > _payload._array.length)
				e2 = _payload._array.length;
			return var(_payload._array[e1 .. e2]);
		}
		if(this.payloadType() == Type.String) {
			if(e1 > _payload._string.length)
				e1 = _payload._string.length;
			if(e2 > _payload._string.length)
				e2 = _payload._string.length;
			return var(_payload._string[e1 .. e2]);
		}
		if(this.payloadType() == Type.Object) {
			var operator = this["opSlice"];
			if(operator._type == Type.Function) {
				return operator.call(this, e1, e2);
			}
		}

		// might be worth throwing here too
		return var(null);
	}

	public @property ref var opDispatch(string name, string file = __FILE__, size_t line = __LINE__)() {
		return this[name];
	}

	public @property ref var opDispatch(string name, string file = __FILE__, size_t line = __LINE__, T)(T r) {
		return this.opIndexAssign!T(r, name);
	}

	public ref var opIndex(var name, string file = __FILE__, size_t line = __LINE__) {
		return opIndex(name.get!string, file, line);
	}

	public ref var opIndexAssign(T)(T t, var name, string file = __FILE__, size_t line = __LINE__) {
		return opIndexAssign(t, name.get!string, file, line);
	}

	public ref var opIndex(string name, string file = __FILE__, size_t line = __LINE__) {
		// if name is numeric, we should convert to int
		if(name.length && name[0] >= '0' && name[0] <= '9')
			return opIndex(to!size_t(name), file, line);

		if(this.payloadType() != Type.Object && name == "prototype")
			return prototype();

		if(name == "typeof") {
			var* tmp = new var;
			*tmp = to!string(this.payloadType());
			return *tmp;
		}

		if(name == "toJson") {
			var* tmp = new var;
			*tmp = to!string(this.toJson());
			return *tmp;
		}

		if(name == "length" && this.payloadType() == Type.String) {
			var* tmp = new var;
			*tmp = _payload._string.length;
			return *tmp;
		}
		if(name == "length" && this.payloadType() == Type.Array) {
			var* tmp = new var;
			*tmp = _payload._array.length;
			return *tmp;
		}
		if(name == "__prop" && this.payloadType() == Type.Object) {
			var* tmp = new var;
			(*tmp)._function = delegate var(var _this, var[] args) {
				if(args.length == 0)
					return var(null);
				if(args.length == 1) {
					auto peek = this._payload._object._peekMember(args[0].get!string, false);
					if(peek is null)
						return var(null);
					else
						return *peek;
				}
				if(args.length == 2) {
					auto peek = this._payload._object._peekMember(args[0].get!string, false);
					if(peek is null) {
						this._payload._object._properties[args[0].get!string] = args[1];
						return var(null);
					} else {
						*peek = args[1];
						return *peek;
					}

				}
				throw new Exception("too many args");
			};
			return *tmp;
		}

		PrototypeObject from;
		if(this.payloadType() == Type.Object)
			from = _payload._object;
		else {
			var pt = this.prototype();
			assert(pt.payloadType() == Type.Object);
			from = pt._payload._object;
		}

		if(from is null) {
			version(jsvar_throw)
				throw new DynamicTypeException(var(null), Type.Object, file, line);
			else
				return *(new var);
		}
		return from._getMember(name, true, false, file, line);
	}

	public ref var opIndexAssign(T)(T t, string name, string file = __FILE__, size_t line = __LINE__) {
		if(name.length && name[0] >= '0' && name[0] <= '9')
			return opIndexAssign(t, to!size_t(name), file, line);
		_requireType(Type.Object); // FIXME?
		if(_payload._object is null)
			throw new DynamicTypeException(var(null), Type.Object, file, line);

		return this._payload._object._setMember(name, var(t), false, false, false, file, line);
	}

	public ref var opIndexAssignNoOverload(T)(T t, string name, string file = __FILE__, size_t line = __LINE__) {
		if(name.length && name[0] >= '0' && name[0] <= '9')
			return opIndexAssign(t, to!size_t(name), file, line);
		_requireType(Type.Object); // FIXME?
		if(_payload._object is null)
			throw new DynamicTypeException(var(null), Type.Object, file, line);

		return this._payload._object._setMember(name, var(t), false, false, true, file, line);
	}


	public ref var opIndex(size_t idx, string file = __FILE__, size_t line = __LINE__) {
		if(_type == Type.Array) {
			auto arr = this._payload._array;
			if(idx < arr.length)
				return arr[idx];
		} else if(_type == Type.Object) {
			// objects might overload opIndex
			var* n = new var();
			if("opIndex" in this)
				*n = this["opIndex"](idx);
			return *n;
		}
		version(jsvar_throw)
			throw new DynamicTypeException(this, Type.Array, file, line);
		var* n = new var();
		return *n;
	}

	public ref var opIndexAssign(T)(T t, size_t idx, string file = __FILE__, size_t line = __LINE__) {
		if(_type == Type.Array) {
			alias arr = this._payload._array;
			if(idx >= this._payload._array.length)
				this._payload._array.length = idx + 1;
			this._payload._array[idx] = t;
			return this._payload._array[idx];
		}
		version(jsvar_throw)
			throw new DynamicTypeException(this, Type.Array, file, line);
		var* n = new var();
		return *n;
	}

	ref var _getOwnProperty(string name, string file = __FILE__, size_t line = __LINE__) {
		if(_type == Type.Object) {
			if(_payload._object !is null) {
				auto peek = this._payload._object._peekMember(name, false);
				if(peek !is null)
					return *peek;
			}
		}
		version(jsvar_throw)
			throw new DynamicTypeException(this, Type.Object, file, line);
		var* n = new var();
		return *n;
	}

	@property static var emptyObject(PrototypeObject prototype = null) {
		var v;
		v._type = Type.Object;
		v._payload._object = new PrototypeObject();
		v._payload._object.prototype = prototype;
		return v;
	}

	@property PrototypeObject prototypeObject() {
		var v = prototype();
		if(v._type == Type.Object)
			return v._payload._object;
		return null;
	}

	// what I call prototype is more like what Mozilla calls __proto__, but tbh I think this is better so meh
	@property ref var prototype() {
		static var _arrayPrototype;
		static var _functionPrototype;
		static var _stringPrototype;

		final switch(payloadType()) {
			case Type.Array:
				assert(_arrayPrototype._type == Type.Object);
				if(_arrayPrototype._payload._object is null) {
					_arrayPrototype._object = new PrototypeObject();
				}

				return _arrayPrototype;
			case Type.Function:
				assert(_functionPrototype._type == Type.Object);
				if(_functionPrototype._payload._object is null) {
					_functionPrototype._object = new PrototypeObject();
				}

				return _functionPrototype;
			case Type.String:
				assert(_stringPrototype._type == Type.Object);
				if(_stringPrototype._payload._object is null) {
					auto p = new PrototypeObject();
					_stringPrototype._object = p;

					var replaceFunction;
					replaceFunction._type = Type.Function;
					replaceFunction._function = (var _this, var[] args) {
						string s = _this.toString();
						import std.array : replace;
						return var(std.array.replace(s,
							args[0].toString(),
							args[1].toString()));
					};

					p._properties["replace"] = replaceFunction;
				}

				return _stringPrototype;
			case Type.Object:
				if(_payload._object)
					return _payload._object._prototype;
				// FIXME: should we do a generic object prototype?
			break;
			case Type.Integral:
			case Type.Floating:
			case Type.Boolean:
				// these types don't have prototypes
		}


		var* v = new var(null);
		return *v;
	}

	@property static var emptyArray() {
		var v;
		v._type = Type.Array;
		return v;
	}

	static var fromJson(string json) {
		auto decoded = parseJSON(json);
		return var.fromJsonValue(decoded);
	}

	static var fromJsonValue(JSONValue v) {
		var ret;

		final switch(v.type) {
			case JSON_TYPE.STRING:
				ret = v.str;
			break;
			case JSON_TYPE.UINTEGER:
				ret = v.uinteger;
			break;
			case JSON_TYPE.INTEGER:
				ret = v.integer;
			break;
			case JSON_TYPE.FLOAT:
				ret = v.floating;
			break;
			case JSON_TYPE.OBJECT:
				ret = var.emptyObject;
				foreach(k, val; v.object) {
					ret[k] = var.fromJsonValue(val);
				}
			break;
			case JSON_TYPE.ARRAY:
				ret = var.emptyArray;
				ret._payload._array.length = v.array.length;
				foreach(idx, item; v.array) {
					ret._payload._array[idx] = var.fromJsonValue(item);
				}
			break;
			case JSON_TYPE.TRUE:
				ret = true;
			break;
			case JSON_TYPE.FALSE:
				ret = false;
			break;
			case JSON_TYPE.NULL:
				ret = null;
			break;
		}

		return ret;
	}

	string toJson() {
		auto v = toJsonValue();
		return toJSON(v);
	}

	JSONValue toJsonValue() {
		JSONValue val;
		final switch(payloadType()) {
			case Type.Boolean:
				version(new_std_json)
					val = this._payload._boolean;
				else {
					if(this._payload._boolean)
						val.type = JSON_TYPE.TRUE;
					else
						val.type = JSON_TYPE.FALSE;
				}
			break;
			case Type.Object:
				version(new_std_json) {
					if(_payload._object is null) {
						val = null;
					} else {
						val = _payload._object.toJsonValue();
					}
				} else {
					if(_payload._object is null) {
						val.type = JSON_TYPE.NULL;
					} else {
						val.type = JSON_TYPE.OBJECT;
						foreach(k, v; _payload._object._properties)
							val.object[k] = v.toJsonValue();
					}
				}
			break;
			case Type.String:
				version(new_std_json) { } else {
					val.type = JSON_TYPE.STRING;
				}
				val.str = _payload._string;
			break;
			case Type.Integral:
				version(new_std_json) { } else {
					val.type = JSON_TYPE.INTEGER;
				}
				val.integer = _payload._integral;
			break;
			case Type.Floating:
				version(new_std_json) { } else {
					val.type = JSON_TYPE.FLOAT;
				}
				val.floating = _payload._floating;
			break;
			case Type.Array:
				auto a = _payload._array;
				JSONValue[] tmp;
				tmp.length = a.length;
				foreach(i, v; a) {
					tmp[i] = v.toJsonValue();
				}

				version(new_std_json) {
					val = tmp;
				} else {
					val.type = JSON_TYPE.ARRAY;
					val.array = tmp;
				}
			break;
			case Type.Function:
				version(new_std_json)
					val = null;
				else
					val.type = JSON_TYPE.NULL; // ideally we would just skip it entirely...
			break;
		}
		return val;
	}
}

class PrototypeObject {
	string name;
	var _prototype;

	package PrototypeObject _secondary; // HACK don't use this

	PrototypeObject prototype() {
		if(_prototype.payloadType() == var.Type.Object)
			return _prototype._payload._object;
		return null;
	}

	PrototypeObject prototype(PrototypeObject set) {
		this._prototype._object = set;
		return set;
	}

	override string toString() {

		var* ts = _peekMember("toString", true);
		if(ts) {
			var _this;
			_this._object = this;
			return (*ts).call(_this).get!string;
		}

		JSONValue val;
		version(new_std_json) {
			JSONValue[string] tmp;
			foreach(k, v; this._properties)
				tmp[k] = v.toJsonValue();
			val.object = tmp;
		} else {
			val.type = JSON_TYPE.OBJECT;
			foreach(k, v; this._properties)
				val.object[k] = v.toJsonValue();
		}

		return toJSON(val);
	}

	var[string] _properties;

	PrototypeObject copy() {
		auto n = new PrototypeObject();
		n.prototype = this.prototype;
		n.name = this.name;
		foreach(k, v; _properties) {
			n._properties[k] = v._copy;
		}
		return n;
	}

	PrototypeObject copyPropertiesFrom(PrototypeObject p) {
		foreach(k, v; p._properties) {
			this._properties[k] = v._copy;
		}
		return this;
	}

	var* _peekMember(string name, bool recurse) {
		if(name == "prototype")
			return &_prototype;

		auto curr = this;

		// for the secondary hack
		bool triedOne = false;
		// for the secondary hack
		PrototypeObject possibleSecondary;

		tryAgain:
		do {
			auto prop = name in curr._properties;
			if(prop is null) {
				// the secondary hack is to do more scoping in the script, it is really hackish
				if(possibleSecondary is null)
					possibleSecondary = curr._secondary;

				if(!recurse)
					break;
				else
					curr = curr.prototype;
			} else
				return prop;
		} while(curr);

		if(possibleSecondary !is null) {
			curr = possibleSecondary;
			if(!triedOne) {
				triedOne = true;
				goto tryAgain;
			}
		}

		return null;
	}

	// FIXME: maybe throw something else
	/*package*/ ref var _getMember(string name, bool recurse, bool throwOnFailure, string file = __FILE__, size_t line = __LINE__) {
		var* mem = _peekMember(name, recurse);

		if(mem !is null) {
			// If it is a property, we need to call the getter on it
			if((*mem).payloadType == var.Type.Object && cast(PropertyPrototype) (*mem)._payload._object) {
				auto prop = cast(PropertyPrototype) (*mem)._payload._object;
				return prop.get;
			}
			return *mem;
		}

		mem = _peekMember("opIndex", recurse);
		if(mem !is null) {
			auto n = new var;
			*n = ((*mem)(name));
			return *n;
		}

		// if we're here, the property was not found, so let's implicitly create it
		if(throwOnFailure)
			throw new Exception("no such property " ~ name, file, line);
		var n;
		this._properties[name] = n;
		return this._properties[name];
	}

	// FIXME: maybe throw something else
	/*package*/ ref var _setMember(string name, var t, bool recurse, bool throwOnFailure, bool suppressOverloading, string file = __FILE__, size_t line = __LINE__) {
		var* mem = _peekMember(name, recurse);

		if(mem !is null) {
			// Property check - the setter should be proxied over to it
			if((*mem).payloadType == var.Type.Object && cast(PropertyPrototype) (*mem)._payload._object) {
				auto prop = cast(PropertyPrototype) (*mem)._payload._object;
				return prop.set(t);
			}
			*mem = t;
			return *mem;
		}

		if(!suppressOverloading) {
			mem = _peekMember("opIndexAssign", true);
			if(mem !is null) {
				auto n = new var;
				*n = ((*mem)(t, name));
				return *n;
			}
		}

		// if we're here, the property was not found, so let's implicitly create it
		if(throwOnFailure)
			throw new Exception("no such property " ~ name, file, line);
		this._properties[name] = t;
		return this._properties[name];
	}

	JSONValue toJsonValue() {
		JSONValue val;
		JSONValue[string] tmp;
		foreach(k, v; this._properties)
			tmp[k] = v.toJsonValue();
		val = tmp;
		return val;
	}

	public int opApply(scope int delegate(var, ref var) dg) {
		foreach(k, v; this._properties) {
			if(v.payloadType == var.Type.Object && cast(PropertyPrototype) v._payload._object)
				v = (cast(PropertyPrototype) v._payload._object).get;
			if(auto result = dg(var(k), v))
				return result;
		}
		return 0;
	}
}

// A property is a special type of object that can only be set by assigning
// one of these instances to foo.child._object. When foo.child is accessed and it
// is an instance of PropertyPrototype, it will return the getter. When foo.child is
// set (excluding direct assignments through _type), it will call the setter.
class PropertyPrototype : PrototypeObject {
	var delegate() getter;
	void delegate(var) setter;
	this(var delegate() getter, void delegate(var) setter) {
		this.getter = getter;
		this.setter = setter;
	}

	override string toString() {
		return get.toString();
	}

	ref var get() {
		var* g = new var();
		*g = getter();
		return *g;
	}

	ref var set(var t) {
		setter(t);
		return get;
	}

	override JSONValue toJsonValue() {
		return get.toJsonValue();
	}
}


class DynamicTypeException : Exception {
	this(var v, var.Type required, string file = __FILE__, size_t line = __LINE__) {
		import std.string;
		if(v.payloadType() == required)
			super(format("Tried to use null as a %s", required), file, line);
		else
			super(format("Tried to use %s as a %s", v.payloadType(), required), file, line);
	}
}

template makeAscii() {
	string helper() {
		string s;
		foreach(i; 0 .. 128)
			s ~= cast(char) i;
		return s;
	}

	enum makeAscii = helper();
}

// just a base class we can reference when looking for native objects
class WrappedNativeObject : PrototypeObject {
	TypeInfo wrappedType;
	abstract Object getObject();
}

template helper(alias T) { alias helper = T; }

/++
	Wraps a class. If you are manually managing the memory, remember the jsvar may keep a reference to the object; don't free it!

	To use this: `var a = wrapNativeObject(your_d_object);` OR `var a = your_d_object`;

	By default, it will wrap all methods and members with a public or greater protection level. The second template parameter can filter things differently. FIXME implement this

	That may be done automatically with `opAssign` in the future.
+/
WrappedNativeObject wrapNativeObject(Class)(Class obj) if(is(Class == class)) {
	import std.meta;
	return new class WrappedNativeObject {
		override Object getObject() {
			return obj;
		}

		this() {
			wrappedType = typeid(obj);
			// wrap the other methods
			// and wrap members as scriptable properties

			foreach(memberName; __traits(allMembers, Class)) static if(is(typeof(__traits(getMember, obj, memberName)) type)) {
				static if(is(type == function)) {
					foreach(idx, overload; AliasSeq!(__traits(getOverloads, obj, memberName))) static if(.isScriptable!(__traits(getAttributes, overload))()) {
						auto helper = &__traits(getOverloads, obj, memberName)[idx];
						_properties[memberName] = (Parameters!helper args) {
							return __traits(getOverloads, obj, memberName)[idx](args);
						};
					}
				} else {
					static if(.isScriptable!(__traits(getAttributes, __traits(getMember, Class, memberName)))())
					// if it has a type but is not a function, it is prolly a member
					_properties[memberName] = new PropertyPrototype(
						() => var(__traits(getMember, obj, memberName)),
						(var v) {
							// read-only property hack
							static if(__traits(compiles, __traits(getMember, obj, memberName) = v.get!(type)))
							__traits(getMember, obj, memberName) = v.get!(type);
						});
				}
			}
		}
	};
}

import std.traits;
class WrappedOpaque(T) : PrototypeObject if(isPointer!T) {
	T wrapped;
	this(T t) {
		wrapped = t;
	}
	T wrapping() {
		return wrapped;
	}
}
class WrappedOpaque(T) : PrototypeObject if(!isPointer!T) {
	T* wrapped;
	this(T t) {
		wrapped = new T;
		(cast() *wrapped) = t;
	}
	this(T* t) {
		wrapped = t;
	}
	T* wrapping() {
		return wrapped;
	}
}

WrappedOpaque!Obj wrapOpaquely(Obj)(Obj obj) {
	return new WrappedOpaque!Obj(obj);
}

/**
	Wraps an opaque struct pointer in a module with ufcs functions
*/
WrappedNativeObject wrapUfcs(alias Module, Type)(Type obj) {
	import std.meta;
	return new class WrappedNativeObject {
		override Object getObject() {
			return null; // not actually an object! but close to
		}

		this() {
			wrappedType = typeid(Type);
			// wrap the other methods
			// and wrap members as scriptable properties

			foreach(memberName; __traits(allMembers, Module)) static if(is(typeof(__traits(getMember, Module, memberName)) type)) {
				static if(is(type == function)) {
					foreach(idx, overload; AliasSeq!(__traits(getOverloads, Module, memberName))) static if(.isScriptable!(__traits(getAttributes, overload))()) {
						auto helper = &__traits(getOverloads, Module, memberName)[idx];
						static if(Parameters!helper.length >= 1 && is(Parameters!helper[0] == Type)) {
							// this staticMap is a bit of a hack so it can handle `in float`... liable to break with others, i'm sure
							_properties[memberName] = (staticMap!(Unqual, Parameters!helper[1 .. $]) args) {
								return __traits(getOverloads, Module, memberName)[idx](obj, args);
							};
						}
					}
				}
			}
		}
	};
}

bool isScriptable(attributes...)() {
	foreach(attribute; attributes) {
		static if(is(typeof(attribute) == string)) {
			static if(attribute == scriptable) {
				return true;
			}
		}
	}
	return false;
}

bool isScriptableOpaque(T)() {
	static if(is(typeof(T.isOpaqueStruct) == bool))
		return T.isOpaqueStruct == true;
	return false;
}


/// Wraps a struct by reference. The pointer is stored - be sure the struct doesn't get freed or go out of scope!
///
/// BTW: structs by value can be put in vars with var.opAssign and var.get. It will generate an object with the same fields. The difference is changes to the jsvar won't be reflected in the original struct and native methods won't work if you do it that way.
WrappedNativeObject wrapNativeObject(Struct)(Struct* obj) if(is(Struct == struct)) {
	return null; // FIXME
}
