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
alias CommonReturnOfOverloads(alias fn) = CommonType!(staticMap!(ReturnType, __traits(getOverloads, __traits(parent, fn), __traits(identifier, fn))));

/// See details on the [arsd.mvd] page.
CommonReturnOfOverloads!fn mvd(alias fn, T...)(T args) {
	typeof(return) delegate() bestMatch;
	int bestScore;

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
			throw new Exception("ambiguous overload selection with args"); // FIXME: show the things
		if(score > bestScore) {
			bestMatch = () {
				static if(is(typeof(return) == void))
					overload(pargs);
				else
					return overload(pargs);
			};
			bestScore = score;
		}
	}

	if(bestMatch is null)
		throw new Exception("no match existed");

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
	}

	with(Wrapper) {
		assert(mvd!foo(new Object, new Object) == 1);
		assert(mvd!foo(new MyClass, new DerivedClass) == 2);
		assert(mvd!foo(new DerivedClass, new DerivedClass) == 3);
		assert(mvd!foo(new OtherClass, new OtherClass) == 1);
		assert(mvd!foo(new OtherClass, new MyClass) == 1);
		assert(mvd!foo(new DerivedClass, new DerivedClass) == 3);
		assert(mvd!foo(new OtherClass, new MyClass) == 1);
	}
}
