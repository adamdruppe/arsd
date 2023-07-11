/++
	mvd stands for Multiple Virtual Dispatch. It lets you
	write functions that take any number of arguments of
	objects and match based on the dynamic type of each
	of them.

	---
	void foo(Object a, Object b) {} // 1
	void foo(MyClass b, Object b) {} // 2
	void foo(DerivedClass a, MyClass b) {} // 3

	Object a = new MyClass();
	Object b = new Object();

	mvd!foo(a, b); // will call overload #2
	---

	The return values must be compatible; [mvd] will return
	the least specialized static type of the return values
	(most likely the shared base class type of all return types,
	or `void` if there isn't one).

	All non-class/interface types should be compatible among overloads.
	Otherwise you are liable to get compile errors. (Or it might work,
	that's up to the compiler's discretion.)
+/
module arsd.mvd;

import std.traits;

/// This exists just to make the documentation of [mvd] nicer looking.
template CommonReturnOfOverloads(alias fn) {
	alias overloads = __traits(getOverloads, __traits(parent, fn), __traits(identifier, fn));
	static if (overloads.length == 1) {
		alias CommonReturnOfOverloads = ReturnType!(overloads[0]);
	}
	else {
		alias CommonReturnOfOverloads = CommonType!(staticMap!(ReturnType, overloads));
	}
}

/// See details on the [arsd.mvd] page.
CommonReturnOfOverloads!fn mvd(alias fn, T...)(T args) {
	return mvdObj!fn(null, args);
}

CommonReturnOfOverloads!fn mvdObj(alias fn, This, T...)(This this_, T args) {
	typeof(return) delegate() bestMatch;
	int bestScore;

	string argsStr() {
		string s;
		foreach(arg; args) {
			if(s.length)
				s ~= ", ";
			static if (is(typeof(arg) == class)) {
				if (arg is null) {
					s ~= "null " ~ typeof(arg).stringof;
				} else {
					s ~= typeid(arg).name;
				}
			} else {
				s ~= typeof(arg).stringof;
			}
		}
		return s;
	}

	ov: foreach(overload; __traits(getOverloads, __traits(parent, fn), __traits(identifier, fn))) {
		Parameters!overload pargs;
		int score = 0;
		foreach(idx, parg; pargs) {
			alias t = typeof(parg);
			static if(is(t == interface) || is(t == class)) {
				pargs[idx] = cast(typeof(parg)) args[idx];
				if(args[idx] !is null && pargs[idx] is null)
					continue ov; // failed cast, forget it
				else
					score += BaseClassesTuple!t.length + 1;
			} else
				pargs[idx] = args[idx];
		}
		if(score == bestScore)
			throw new Exception("ambiguous overload selection with args (" ~ argsStr ~ ")");
		if(score > bestScore) {
			bestMatch = () {
				static if(is(typeof(return) == void))
					__traits(child, this_, overload)(pargs);
				else
					return __traits(child, this_, overload)(pargs);
			};
			bestScore = score;
		}
	}

	if(bestMatch is null)
		throw new Exception("no match existed with args (" ~ argsStr ~ ")");

	return bestMatch();
}

///
unittest {

	class MyClass {}
	class DerivedClass : MyClass {}
	class OtherClass {}

	static struct Wrapper {
		static: // this is just a namespace cuz D doesn't allow overloading inside unittest
		int foo(Object a, Object b) { return 1; }
		int foo(MyClass a, Object b) { return 2; }
		int foo(DerivedClass a, MyClass b) { return 3; }

		int bar(MyClass a) { return 4; }
	}

	with(Wrapper) {
		assert(mvd!foo(new Object, new Object) == 1);
		assert(mvd!foo(new MyClass, new DerivedClass) == 2);
		assert(mvd!foo(new DerivedClass, new DerivedClass) == 3);
		assert(mvd!foo(new OtherClass, new OtherClass) == 1);
		assert(mvd!foo(new OtherClass, new MyClass) == 1);
		assert(mvd!foo(new DerivedClass, new DerivedClass) == 3);
		assert(mvd!foo(new OtherClass, new MyClass) == 1);

		//mvd!bar(new OtherClass);
	}
}

///
unittest {

	class MyClass {}
	class DerivedClass : MyClass {}
	class OtherClass {}

	class Wrapper {
		int x;

		int foo(Object a, Object b) { return x + 1; }
		int foo(MyClass a, Object b) { return x + 2; }
		int foo(DerivedClass a, MyClass b) { return x + 3; }

		int bar(MyClass a) { return x + 4; }
	}

	Wrapper wrapper = new Wrapper;
	wrapper.x = 20;
	assert(wrapper.mvdObj!(wrapper.foo)(new Object, new Object) == 21);
	assert(wrapper.mvdObj!(wrapper.foo)(new MyClass, new DerivedClass) == 22);
	assert(wrapper.mvdObj!(wrapper.foo)(new DerivedClass, new DerivedClass) == 23);
	assert(wrapper.mvdObj!(wrapper.foo)(new OtherClass, new OtherClass) == 21);
	assert(wrapper.mvdObj!(wrapper.foo)(new OtherClass, new MyClass) == 21);
	assert(wrapper.mvdObj!(wrapper.foo)(new DerivedClass, new DerivedClass) == 23);
	assert(wrapper.mvdObj!(wrapper.foo)(new OtherClass, new MyClass) == 21);

	//mvd!bar(new OtherClass);
}

///
unittest {
	class MyClass {}

	static bool success = false;

	static struct Wrapper {
		static:
		void foo(MyClass a) { success = true; }
	}

	with(Wrapper) {
		mvd!foo(new MyClass);
		assert(success);
	}
}
