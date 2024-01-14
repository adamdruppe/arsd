/+
	== oceandrift/di ==
	Copyright Elias Batek 2024.
	Distributed under the Boost Software License, Version 1.0.
 +/
/++
	Lightweight Dependency Injection (DI) framework

		$(LIST
		* Inversion of Control (IoC).
		* Convention over configuration.
		* Injects dependencies via constructor parameters.
		* Supports structs as well (… as classes).
		* No clutter – this library is a single, readily comprehensible file.
		* No external dependencies. $(I Only the D standard library is used.)
	)


	## About Dependency Injection

	$(SIDEBAR
		Dependency Injection is commonly abbreviated as $(B DI).
	)

	$(BLOCKQUOTE
		How does it work?
	)

	Dependency instances only need to be created once and can be used for all other dependent objects.
	As there is only one object of each type, these instances can be called “singletons”.

	They can be stored in one big repository, the [DIContainer|dependency container],
	and retrieved later as needed.

	### Declaration of dependencies

	One of the most useful ways to specify the dependencies of a type (as in `class` or `struct`)
	is to declare a constructor with them as parameters.

	---
	// Example: `LoginService` depends on `PasswordHashUtil`, `DatabaseClient` and `Logger`.
	class LoginService {
		public this(
			PasswordHashUtil passwordHashUtil,
			DatabaseClient databaseClient,
			Logger logger,
		) {
			// …
		}
	}
	---

	### Retrieval of dependencies

	Getting the dependencies from the container into the service object is where the DI framework comes in.
	While the user could manually retrieve them from the container and pass them to the constructor
	(i.e. `new LoginService(container.get!PasswordHashUtil(), container.get!Logger(), container.get!DatabaseClient())`,
	this would get tedious quickly.
	The framework comes to the resuce.

	---
	auto di = new DI();
	// …

	LoginService service = di.resolve!LoginService();
	---

	### Registration of dependencies

	But where did the `PasswordHashUtil`, the `Logger` and the `DatabaseClient` come from?
	How did they get into the DI container?

	#### Standalone dependencies

	Let’s assume the `PasswordHashUtil` has zero dependencies itself – it is a self-contained service class.
	Its constructor has either no parameters
	or isn’t declared explicitly (and it uses the implicit default constructor).

	The DI framework can easily construct a singleton instance (of the dependency type) on the fly.
	This happens automatically the first time one is needed.

	---
	class PasswordHashUtil {
		public string hash(string password) { /* … */ }
		public bool verify(string hash, string userPassword) { /* … */ }
	}
	---

	##### Custom dependency registrations

	In case a user-provided `PasswordHashUtil` instance has been registered in advance,
	the framework will skip the construction and use that one instead.

	#### Transitive dependencies

	Aka “dependencies of a dependency”.

	The 2nd dependency of the aforementioned `LoginService` is `Logger`.
	For illustration purposes, we’ll assume the `Logger` class depends on `Formatter`,
	a type that implements formatting facilities.
	`Logger` is dependency-less class (like `PasswordHashUtil` was).

	The DI framework will retrieve a `Formatter` before it can construct the `Logger`.
	Since `Formatter` has not dependencies, the framework can construct it as mentioned in the previous chapter.
	If it there is one in the dependency container already, it will be used instead
	(and the construction will be skipped).

	The next step is to construct a `Logger` which receives the `Formatter` through its constructor.

	---
	class Logger {
		public this(Formatter formatter) {
			// …
		}
		public void log(string message) { /* … */ }
	}
	---

	##### Custom dependency registrations

	In case a user-provided `Logger` instance has been registered in advance,
	the framework will skip all construction steps and use that one instead.

	$(NOTE
		If the user-provided `Logger` uses a $(B different) `Formatter` than the one in the dependency container,
		the `Logger` of the resulting `LoginService` will use said different `Formatter`,
		not the one from the container.

		This has no impact on a direct dependencies of `Logger`.
		If `Logger` itself depended on `Formatter`, it would still receive the one from the dependency container.
		Which in turn would lead to `LoginService.formatter` being different to `Logger.formatter`.

		Logically, this distinction would be no longer relevant, if the user registered their `Formatter` instance
		with the framework in addition to their custom `Logger` one.
	)

	#### Complex dependencies

	Unlike the dependencies shown in the previous two chapters, however,
	the `DatabaseClient` doesn’t depend on a bunch of other services.
	Instead it is constructed from four strings (socket, username, password, database name).

	While the injection of a `DatabaseClient` into dependent services principally works like before,
	the framework cannot instantiate a new one by itself.
	Hence it is that an instance has to be registered with the framework in advance.
	A user-created `DatabaseClient` can provided by passing it to [oceandrift.di.DI.register|DI.register(…)].

	The framework will pick up on it later, when it constructs `LoginService`
	or, failing that, if no custom instance has been registered beforehand,
	crash the program as soon as it falls back to instantiating one on its own.

	---
	class DatabaseClient {
		public this(
			string socket,
			string username,
			string password,
			string databaseName,
		) {
			// …
		}
		public Statement prepare(string sql) { /* … */ }
		public void disconnect() { /* … */ }
	}

	// Construct a DatabaseClient and register it with the DI framework.
	auto databaseClient = new DatabaseClient(cfg.socket, cfg,username, cfg.password, cfg.dbName);
	di.register(databaseClient);
	---


	## Unconventional use

	This chapter deals with solutions to overcome the conventions of the framework.
	(Malicious gossip has it that these are “design limitations”. Don’t listen to them…)

	### Injecting non-singleton instances

	Non-singleton objects are sometimes also called “transient” or “prototype”.

	By default, the framework will instantiate a singleton instance for each dependency type
	and use it for all dependent objects.

	When this behavior is not desired, it’s recommended to instantiate a new object in the constructor.
	Check out [oceandrift.di.DI.makeNew|makeNew!T()].

	$(TIP
		The DI framework can inject a reference to itself.
		---
		public this(
			DI di,
		) {
			this.dependency = DI.makeNew!Dependency();
		}
		---
	)

	Alternatively, one could also create a factory type and use that as a dependency instead.

	### Injecting dependencies that are primitive/unsupported types

	The recommended way to inject primitives types (like integers, booleans, floating-point numbers, or enums)
	or other unsupported types (e.g. strings, other arrays, associative arrays, class pointers or pointers in general)
	is to wrap them in a struct.

	For pointers, deferencing them might also be an option.
 +/
module oceandrift.di;

import std.conv : to;
import std.traits : Parameters;

/++
	Extended version of the front-page example
 +/
@safe unittest {
	static class Dependency {
	}

	static class Foo {
		private Dependency d;

		public this(Dependency d) {
			this.d = d;
		}
	}

	// Bootstrap the DI framework.
	auto di = new DI();

	// Then let it resolve the whole dependency tree
	// and construct dependencies as needed.
	Foo foo = di.resolve!Foo();

	// The DI framework has constructed a new instance of `Dependency`
	// and supplied it to the constructor of `Foo`.
	assert(foo.d !is null);
}

/++
	User-supplied dependency instances

	$(BLOCKQUOTE
		How about types the framework cannot construct on its own?

		… or instaces that have been constructed in before and could be reused?
	)
 +/
@safe unittest {
	static class Dependency {
		private int number;

		public this(int number) {
			this.number = number;
		}
	}

	static class Foo {
		private Dependency d;

		public this(Dependency d) {
			this.d = d;
		}
	}

	// Bootstrap the DI framework.
	auto di = new DI();

	// Construct an instance of the dependency manually.
	// Then register it with the framework.
	auto dep = new Dependency(128);
	di.register(dep);

	// alternative syntax variants (They all come down to the same thing.):
	di.register!Dependency(dep);
	di.register!Dependency = dep;

	// Resolve dependencies of `Foo` and create instance.
	Foo foo = di.resolve!Foo();

	// The DI framework constructed a new instance of `Dependency`
	// and supplied it to the constructor of `Foo`.
	assert(foo.d !is null);
}

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
	Determines whether a type `T` is supported to be used as dependency by the framework.

	Currently this includes:
	$(LIST
		* Classes – `class`
		* Structs – `struct`
		* Struct pointers – `struct*`
	)

	See_Also:
		[isConstructableByDI] that determines whether a type can be constructed by the framework on its own.
 +/
public enum bool isSupportedDependencyType(T) = (isClass!T || isStruct!T || isStructPointer!T);

/++
	Determines $(B why) a type `T` is not constructable by the DI framework.

	Returns:
		string = reason
		null = is constructable, in fact
 +/
public template determineWhyNotConstructableByDI(T) {

	/// ditto
	public static immutable string determineWhyNotConstructableByDI = impl();

	private string impl() {
		if (isSupportedDependencyType!T == false) {
			return "DI cannot construct an instance of type `"
				~ T.stringof
				~ "` that is not a supported dependency type (struct/) in the first place.";
		}

		static if (hasConstructors!T == false) {
			return null;
		} else {
			alias ctors = getConstructors!T;
			if (ctors.length > 1) {
				return "DI cannot construct an instance of type `"
					~ T.stringof
					~ "` with multiple constructors.";
			}

			alias params = Parameters!(ctors[0]);
			foreach (idx, P; params) {
				if (isSupportedDependencyType!P == false) {
					// Trick the detection of unreachable statements found in older compilers.
					bool neverTrue = false;
					if (neverTrue) {
						break;
					}

					return "DI cannot construct an instance of type `"
						~ T.stringof
						~ "` because its dependency #"
						~ idx.to!string
						~ " of type `"
						~ P.stringof
						~ "` is not a supported type.";
				}
			}

			return null;
		}
	}
}

/++
	Determines whether a type `T` is constructable by the DI framework.

	See_Also:
		[isSupportedDependencyType] that determines whether a type can be used as a dependency.
 +/
public enum bool isConstructableByDI(T) = (determineWhyNotConstructableByDI!T is null);

/++
	Dependency Container

	Used to store singleton instances of dependency types.
	This is the underlying container implementation used by [DI].
 +/
private final class Container {
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

/// ditto
public alias DIContainer = Container;

/++
	Dependency Injection
 +/
final class DI {
	private {
		Container _container;
	}

	///
	this(DIContainer container) @safe pure nothrow {
		// main ctor
		_container = container;
		_container.setDI = this;
	}

	///
	this() @safe pure nothrow {
		this(new Container());
	}

	/++
		Returns the singleton instance of the requested type.

		Automatically constructs a new one if needed.
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

	/// ditto
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

		$(TIP
			This function can be used to supply instances of types the DI framework cannot construct on its own
			for further use by the DI.

			Nonetheless, types must be [isSupportedDependencyType|supported dependency types].
		)

		$(NOTE
			Overrides a previously stored instance if applicable.
		)
	 +/
	void register(T)(T value) @safe pure nothrow {
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

	///
	alias store = register;

	private T* makeNew(T)() if (isStruct!T) {
		return new T();
	}

	/++
		Instantiates a new instance of the specified type `T`.

		Dependencies will be assigned from the underlying container.
	 +/
	T makeNew(T)() if (isClass!T) {
		// crash if not constructable
		static if (determineWhyNotConstructableByDI!T !is null) {
			assert(false, determineWhyNotConstructableByDI!T);
		} else {
			static if (hasConstructors!T == false) {
				return new T();
			} else {
				alias ctors = getConstructors!T;
				static assert(ctors.length == 1, "Seems like there's a bug in `determineWhyNotConstructableByDI`.");

				alias params = Parameters!(ctors[0]);

				static foreach (idx, P; params) {
					static if (isClass!P || isStructPointer!P) {
						mixin(`P param` ~ idx.to!string() ~ ';');
						mixin(`param` ~ idx.to!string()) = this.resolve!P();
					} else static if (isStruct!P) {
						pragma(
							msg,
							"DI Warning: Passing struct instance by value to constructor parameter " ~ idx.to!string() ~ " (`"
								~ P.stringof ~ "`) of type `" ~ T.stringof ~ "`."
						);
						mixin(`P param` ~ idx.to!string() ~ ';');
						mixin(`param` ~ idx.to!string()) = *this.resolve!P();
					} else {
						static assert(ctors.length == 1, "Seems like there's a bug in `determineWhyNotConstructableByDI`.");
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
}

@safe unittest {
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

@safe unittest {
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
