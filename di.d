/++
	Lightweight Dependency Injection (DI) framework
 +/
module oceandrift.di;

import std.conv : to;
import std.traits : Parameters;

private enum bool isClass(T) = (is(T == class));
private enum bool isStruct(T) = (is(T == struct));
private enum bool isStructPointer(T) = (is(typeof(*T) == struct));

private enum bool hasConstructors(T) = __traits(hasMember, T, "__ctor");

private template getConstructors(T) if (hasConstructors!T) {
	alias getConstructors = __traits(getOverloads, T, "__ctor");
}

private {
	template keyOf(T) if (isClass!T) {
		private static immutable string keyOf = T.mangleof;
	}

	template keyOf(T) if (isStruct!T) {
		private static immutable string keyOf = (T*).mangleof;
	}

	template keyOf(T) if (isStructPointer!T) {
		private static immutable string keyOf = T.mangleof;
	}
}

/++
	Container for singleton instances
 +/
final class Container {
@safe pure nothrow:

	private {
		alias voidptr = void*;
		voidptr[string] _data;
	}

	///
	public this() {
		this.setSelf();
	}

	// CAUTION: This function cannot be exposed publicly for @safe-ty guarantees
	private void** getPtr(string key) @nogc {
		return (key in _data);
	}

	/++
		Returns a stored value by key
	 +/
	void* get(string key) @nogc {
		void** ptrptr = (key in _data);
		if (ptrptr is null) {
			return null;
		}

		return *ptrptr;
	}

	private T getTImpl(T)() @nogc {
		void* ptr = this.get(keyOf!T);
		return (function(void* ptr) @trusted => cast(T) ptr)(ptr);
	}

	/++
		Returns a stored value by class
	 +/
	T get(T)() @nogc if (isClass!T) {
		return getTImpl!T();
	}

	/++
		Returns a stored value by struct
	 +/
	T* get(T)() @nogc if (isStruct!T) {
		return getTImpl!(T*);
	}

	/++
		Determines whether a value matching the provided key is stored
	 +/
	bool has(string key) @nogc {
		return (this.get(key) !is null);
	}

	/// ditto
	bool has(T)() @nogc {
		return this.has(keyOf!T);
	}

	// CAUTION: This function cannot be exposed publicly for @safe-ty guarantees
	private void set(string key, void* value) {
		_data[key] = value;
	}

	private void setTImpl(T)(T value) {
		pragma(inline, true);
		void* ptr = (function(T value) @trusted => cast(void*) value)(value);
		this.set(keyOf!T, ptr);
	}

	/++
		Stores the provided class instance
	 +/
	void set(T)(T value) if (isClass!T && !is(T == Container) && !is(T == DI)) {
		this.setTImpl!T(value);
	}

	/++
		Stores the provided pointer to a struct instance
	 +/
	void set(T)(T* value) if (isStruct!T) {
		this.setTImpl!(T*)(value);
	}

	private void setSelf() {
		this.setTImpl!Container(this);
	}

	private void setDI(DI value) {
		this.setTImpl!DI(value);
	}
}

/++
	Dependency Injection
 +/
final class DI {
	private {
		Container _container;
	}

	///
	this(Container container) @safe pure nothrow {
		// main ctor
		_container = container;
		_container.setDI = this;
	}

	///
	this() @safe pure nothrow {
		this(new Container());
	}

	/++
	 +/
	auto resolve(T)() if (false) {
		static assert(
			isClass!T || isStruct!T,
			"Cannot resolve instance of type `" ~ T.stringof ~ "`. Not a class or struct."
		);

		void** ptrptr = _container.getPtr(keyOf!T);
		if (ptrptr !is null) {
			return ((void* ptr) @trusted => cast(T)*ptr)(*ptrptr);
		}

		return _container.get!T();
	}

	/++
	 +/
	T resolve(T)() if (isClass!T) {
		void** ptrptr = _container.getPtr(keyOf!T);
		if (ptrptr !is null) {
			return (function(void* ptr) @trusted => cast(T) ptr)(*ptrptr);
		}

		T instance = this.makeNew!T();
		this.store!T = instance;

		return instance;
	}

	/++
	 +/
	T* resolve(T)() if (isStruct!T) {
		void** ptrptr = _container.getPtr(keyOf!T);
		if (ptrptr !is null) {
			return ((void* ptr) @trusted => cast(T*) ptr)(*ptrptr);
		}

		T* instance = this.makeNew!T();
		this.store!(T*) = instance;

		return _container.get!T();
	}

	/++
		Stores the provided instance of type `T` in the DI container.

		Overrides the previously stored instance if applicable.
	 +/
	void store(T)(T value) @safe pure nothrow {
		static assert(
			isClass!T || isStructPointer!T,
			"Cannot store instance of type `" ~ T.stringof ~ "`. Not a class or struct-pointer."
		);
		static assert(
			!is(T == Container),
			"Cannot override the referenced Container instance."
		);
		static assert(
			!is(T == DI),
			"Cannot override the referenced DI instance."
		);

		_container.set(value);
	}

	private T* makeNew(T)() if (isStruct!T) {
		return new T();
	}

	/++ 
	 +/
	T makeNew(T)() if (isClass!T) {
		static if (!hasConstructors!(T)) {
			return new T();
		} else {
			alias ctors = getConstructors!T;
			static assert(
				ctors.length <= 1,
				"DI cannot instantiate object of class `" ~ T.stringof ~ "` which has multiple constructors."
			);

			alias params = Parameters!(ctors[0]);

			static foreach (idx, P; params) {
				static if (isClass!P || isStructPointer!P) {
					mixin(`P param` ~ idx.to!string() ~ ';');
					mixin(`param` ~ idx.to!string()) = this.resolve!P();
				} else static if (isStruct!P) {
					pragma(
						msg,
						"DI Warning: Passing struct instance by value to parameter `"
							~ P.stringof ~ "` of type `" ~ T.stringof ~ "`."
					);
					mixin(`P param` ~ idx.to!string() ~ ';');
					mixin(`param` ~ idx.to!string()) = *this.resolve!P();
				} else {
					static assert(false, "Cannot resolve a value for constructor parameter " ~ idx ~ "");
				}
			}

			enum paramList = (function() {
					string r = "";
					foreach (idx, p; params) {
						r ~= "param" ~ idx.to!string() ~ ',';
					}
					return r;
				})();

			return mixin(`new T(` ~ paramList ~ `)`);
		}
	}
}

unittest {
	static struct Foo {
		int i = 10;
	}

	static class Bar {
		int i = 10;
	}

	auto c = new Container();
	assert(c.has!Foo() == false);
	assert(c.has!Bar() == false);
	assert(c.get!Foo() is null);
	assert(c.get!Bar() is null);

	auto origFoo = new Foo();
	origFoo.i = 2;
	auto origBar = new Bar();
	origBar.i = 3;

	c.set(origFoo);
	c.set(origBar);
	assert(c.has!Foo());
	assert(c.has!Bar());
	assert(c.get!Foo() !is null);
	assert(c.get!Bar() !is null);

	auto cFoo = c.get!Foo();
	auto cBar = c.get!Bar();
	assert(cFoo.i == 2);
	assert(cBar.i == 3);
	assert(cFoo is origFoo);
	assert(cBar is origBar);

	cFoo.i = 4;
	assert(origFoo.i == 4);

	c.set!Foo(null);
	assert(c.has!Foo() == false);

	c.set!Bar(null);
	assert(c.has!Bar() == false);
}

unittest {
	static class Bar {
		int i = 10;
	}

	static class Foo {
		Bar bar;

		this(Bar bar) {
			this.bar = bar;
		}
	}

	auto di = new DI();
	Foo foo = di.resolve!Foo();
	assert(foo !is null);
	assert(foo.bar !is null);

	// Test singleton behavior
	assert(foo.bar.i == 10);
	Bar bar = di.resolve!Bar();
	bar.i = 2;
	assert(foo.bar.i == 2);
}
