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
		* Supports structs as well (… as classes and interfaces).
		* No clutter – this library is a single, readily comprehensible file.
		* No external dependencies. $(I Only the D standard library is used.)
	)


	### About Dependency Injection

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

	#### Declaration of dependencies

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

	#### Retrieval of dependencies

	Getting the dependencies from the container into the service object is where the DI framework comes in.
	While the user could manually retrieve them from the container and pass them to the constructor
	(i.e. `new LoginService( container.get!PasswordHashUtil(), container.get!Logger(), container.get!DatabaseClient() )`,
	this would get tedious quickly.
	The framework comes to the resuce.

	---
	auto di = new DI();
	// …

	LoginService service = di.resolve!LoginService();
	---

	#### Registration of dependencies

	But where did the `PasswordHashUtil`, the `Logger` and the `DatabaseClient` come from?
	How did they get into the DI container?

	##### Standalone dependencies

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

	###### Custom dependency registrations

	In case a user-provided `PasswordHashUtil` instance has been registered in advance,
	the framework will skip the construction and use that one instead.

	##### Transitive dependencies

	Aka $(I dependencies of a dependency).

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

	###### Custom dependency registrations

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

	##### Complex dependencies

	Unlike the dependencies shown in the previous two chapters, however,
	the `DatabaseClient` doesn’t depend on a bunch of other services.
	Instead it is constructed from four strings (socket, username, password, database name).

	While the injection of a `DatabaseClient` into dependent services principally works like before,
	the framework cannot instantiate a new one by itself.
	Hence it is that an instance has to be registered with the framework in advance.
	A user-created `DatabaseClient` can provided by passing it to [oceandrift.di.DI.register|register()].

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


	### Unconventional use

	This chapter deals with solutions to overcome the conventions of the framework.
	(Malicious gossip has it that these are “design limitations”. Don’t listen to them…)

	#### Injecting non-singleton instances

	Non-singleton objects are sometimes also called “transient” or “prototype”.

	By default, the framework will instantiate a singleton instance for each dependency type
	and use it for all dependent objects.

	When this behavior is not desired, it’s recommended to instantiate a new object in the constructor.
	Check out [oceandrift.di.DI.makeNew|makeNew!(T)].

	$(TIP
		The DI framework can inject a reference to itself.

		---
		public this(
			DI di,
		) {
			this.dependency = di.makeNew!Dependency();
		}
		---
	)

	Alternatively, one could also create a factory type and use that as a dependency instead.

	#### Injecting dependencies that are primitive/unsupported types

	The recommended way to inject primitives types (like integers, booleans, floating-point numbers, or enums)
	or other unsupported types (e.g. strings, other arrays, associative arrays, class pointers or pointers in general)
	is to wrap them in a struct.

	For pointers, deferencing them might also be an option.




	Examples:

	### Bootstrapping

	Bootstrapping the framework is as simple as:

	---
	auto di = new DI();
	---
 +/
module oceandrift.di;

/++
	### Extended version of the front-page example
 +/
@safe unittest {
	static  // exclude from docs
	class Dependency {
	}

	static  // exclude from docs
	class Foo {
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
	### User-supplied dependency instances

	$(BLOCKQUOTE
		How about types the framework cannot construct on its own?

		… or instaces that have been constructed in before and could be reused?
	)
 +/
@safe unittest {
	static  // exclude from docs
	class Dependency {
		private int number;

		public this(int number) {
			this.number = number;
		}
	}

	static  // exclude from docs
	class Foo {
		private Dependency d;

		public this(Dependency d) {
			this.d = d;
		}
	}

	auto di = new DI(); // exclude from docs

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

/++
	### Injecting dependencies that are interfaces

	It’s really straightforward:
	Tell the framework which implementation type to use for dependencies of an interface type.
 +/
@system unittest {
	static  // exclude from docs
	interface Logger {
		void log(string message);
	}

	static  // exclude from docs
	class StdLogger : Logger {
		private int lines = 0;

		void log(string message) {
			++lines;
			// …writeln(message);…
		}
	}

	static  // exclude from docs
	class Service {
		private Logger logger;

		this(Logger logger) {
			this.logger = logger;
		}

		void doSomething() {
			this.logger.log("Did something.");
		}

	}

	auto di = new DI(); // exclude from docs

	// Register `StdLogger` as the implementation to construct for the
	// `Logger` interface.
	di.registerInterface!(Logger, StdLogger);

	// Now the framework is set up to
	// construct an instance of the `Service` class.
	Service service1 = di.resolve!Service();

	// Our service instance is using the `StdLogger` implementation
	// that has been registered a few lines above.
	service1.doSomething();
	service1.doSomething();
	assert(di.resolve!StdLogger().lines == 2);
}

/++
	### Injecting dependencies that are interfaces (Part II)

	What if we had a type with a complex constructor,
	one that the framework cannot instantiate on its own?
 +/
@system unittest {
	static  // exclude from docs
	interface Logger {
		void log(string message);
	}

	static  // exclude from docs
	class FileLogger : Logger {
		private int lines = 0;

		this(string logFilePath) {
			// …
		}

		void log(string message) {
			++lines;
			// …
		}
	}

	static  // exclude from docs
	class Service {
		private Logger logger;

		this(Logger logger) {
			this.logger = logger;
		}

		void doSomething() {
			this.logger.log("Did something.");
		}

	}

	auto di = new DI(); // exclude from docs

	// Easy. Construct one and register it with the framework.
	auto fileLogger = new FileLogger("/dev/null");
	di.registerInterface!Logger(fileLogger);

	// Now the framework is set up to
	// retrieve an instance of the `Service` class.
	Service service2 = di.resolve!Service();

	// Just for the record:
	// The file logger starts with a line count of `0`.
	assert(fileLogger.lines == 0);

	// Let’s use the service and see whether the supplied logger is used.
	service2.doSomething();
	assert(fileLogger.lines == 1); // alright!
}

/++
	### DI-constructor generator

	> All that typing gets tedious quickly, doesn’t it?

	The framework can generate all the constructor boilerplate.
	It’s as easy as:

	$(NUMBERED_LIST
		* Annotate all dependency fields with [dependency|@dependency].
		* Add `mixin` [DIConstructor] to your type.
		  This generates a constructor with a parameter for each `@dependency` field
		  and a body that assigns the values to the corresponding fields.
	)
 +/
@safe unittest {
	static  // exclude from docs
	class Dependency1 {
	}

	static  // exclude from docs
	class Dependency2 {
	}

	static  // exclude from docs
	class Foo {
		// Mark dependencies with the attribute `@dependency`:
		private @dependency {
			Dependency1 d1;
			Dependency2 d2;
		}

		// Let the framework generate the constructor:
		mixin DIConstructor;
	}

	auto di = new DI();
	Foo foo = di.resolve!Foo();

	// It works:
	assert(foo.d1 !is null);
	assert(foo.d2 !is null);
}

import std.conv : to;
import std.traits : Parameters;

private enum bool isClass(T) = (is(T == class));
private enum bool isInterface(T) = (is(T == interface));
private enum bool isStruct(T) = (is(T == struct));
private enum bool isStructPointer(T) = (is(typeof(*T) == struct));

private enum bool hasConstructors(T) = __traits(hasMember, T, "__ctor");

private template getConstructors(T) if (hasConstructors!T) {
	alias getConstructors = __traits(getOverloads, T, "__ctor");
}

private template hasParentClass(T) if (isClass!T) {
	static if (is(T Parents == super) && Parents.length)
		enum hasParentClass = true;
	else
		enum hasParentClass = false;
}

private template ParentClass(T) if (isClass!T) {
	static if (is(T Parents == super) && Parents.length)
		alias ParentClass = Parents[0];
	else
		static assert(0, "No parent class for type `" ~ T.stringof ~ "`.");
}

unittest {
	static class Parent {
	}

	static class Child : Parent {
	}

	static class GrandChild : Child {
	}

	static assert(hasParentClass!Parent);
	static assert(hasParentClass!Child);
	static assert(hasParentClass!GrandChild);

	static assert(is(ParentClass!Parent == Object));
	static assert(is(ParentClass!Child == Parent));
	static assert(is(ParentClass!GrandChild == Child));
}

private template MemberSymbols(alias T, args...) {
	import std.meta;

	alias MemberSymbols = AliasSeq!();
	static foreach (arg; args) {
		MemberSymbols = AliasSeq!(MemberSymbols, __traits(getMember, T, arg));
	}
}

unittest {
	static class Dings {
		int x;
		string y;
	}

	alias mSyms = MemberSymbols!(Dings, "x", "y");
	assert(mSyms.length == 2);
	assert(is(typeof(mSyms[0]) == int));
	assert(is(typeof(mSyms[1]) == string));
}

private template DerivedMemberSymbols(T, args...) {
	alias DerivedMemberSymbols = MemberSymbols!(T, __traits(derivedMembers, T));
}

unittest {
	static class Dings {
		int x;
		string y;
	}

	alias mSyms = DerivedMemberSymbols!(Dings);
	assert(mSyms.length == 2);
	assert(is(typeof(mSyms[0]) == int));
	assert(is(typeof(mSyms[1]) == string));
}

private template callerParameterListString(params...) {
	private string impl() {
		string r = "";
		foreach (idx, P; params) {
			static if (isStruct!P) {
				r ~= '*';
			}
			r ~= "param" ~ idx.to!string() ~ ',';
		}
		return r;
	}

	enum callerParameterListString = impl();
}

private {
	template keyOf(T) if (isClass!T || isInterface!T || isStructPointer!T) {
		private static immutable string keyOf = T.mangleof;
	}

	template keyOf(T) if (isStruct!T) {
		private static immutable string keyOf = keyOf!(T*);
	}
}

/++
	Determines whether a type `T` is supported to be used as dependency by the framework.

	Currently this includes:
	$(LIST
		* Classes – `class`
		* Interfaces – `interface`
		* Structs – `struct`
		* Struct pointers – `struct*`
	)

	See_Also:
		[isConstructableByDI] that determines whether a type can be constructed by the framework on its own.
 +/
public enum bool isSupportedDependencyType(T) = (isClass!T || isInterface!T || isStruct!T || isStructPointer!T);

/++
	Determines whether a type `T` is denied for user registration.
 +/
public enum bool isForbiddenType(T) = is(T == Container) || is(T == DI);

/++
	Determines whether a type `T` is applicable for user registration.
 +/
public enum bool isntForbiddenType(T) = !(isForbiddenType!T);

/++
	Determines $(I why) a type `T` is not constructable by the DI framework.

	Returns:
	$(LIST
		* `string` = reason
		* `null` = is constructable, in fact
	)
 +/
public template determineWhyNotConstructableByDI(T) {

	/// ditto
	public static immutable string determineWhyNotConstructableByDI = impl();

	private string impl() {
		static if (isSupportedDependencyType!T == false) {
			return "DI cannot construct an instance of type `"
				~ T.stringof
				~ "` that is not a supported dependency type in the first place.";
		} else static if (isInterface!T) {
			return "DI cannot construct an instance of type `"
				~ T.stringof
				~ "` that is an `interface`.";
		} else static if (hasConstructors!T == false) {
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
						~ " `"
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

@safe unittest {
	class Class {
	}

	class ClassWithIntegerParamCtor {
		this(int) {
		}
	}

	interface Interface {
	}

	struct Struct {
	}

	assert(isConstructableByDI!Class);
	assert(isConstructableByDI!ClassWithIntegerParamCtor == false);
	assert(isConstructableByDI!Interface == false);
	assert(isConstructableByDI!Struct);
	assert(isConstructableByDI!int == false);
	assert(isConstructableByDI!string == false);
	assert(isConstructableByDI!(int[]) == false);
}

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
		Returns a stored value by class, interface or struct-pointer type
	 +/
	T get(T)() @nogc if (isClass!T || isInterface!T || isStructPointer!T) {
		return getTImpl!T();
	}

	/++
		Returns a stored value by struct
	 +/
	T* get(T)() @nogc if (isStruct!T) {
		return getTImpl!(T*)();
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
	void set(T)(T value) if ((isClass!T || isInterface!T) && (isntForbiddenType!T)) {
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

	This is the flagship class of the framework.
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

	private auto resolveImpl(T)() if (isSupportedDependencyType!T) {
		pragma(inline, true);

		auto instance = _container.get!T();

		if (instance is null) {
			instance = this.makeNew!T();
			this.register!T = instance;
		}

		return instance;
	}

	/++
		Returns the singleton instance of the requested type.

		Automatically constructs a new one if needed.
	 +/
	T resolve(T)() if (isClass!T || isInterface!T || isStructPointer!T) {
		return this.resolveImpl!T();
	}

	/// ditto
	T* resolve(T)() if (isStruct!T) {
		return this.resolveImpl!(T*)();
	}

	/++
		Stores the provided instance of type `T` in the DI container.
		This registered instance will be injected for dependencies of type `T`.

		$(TIP
			This function can be used to supply instances of types the DI framework cannot construct on its own
			for further use by the DI.

			Nonetheless, types must be [isSupportedDependencyType|supported dependency types].
		)

		$(NOTE
			Overrides a previously stored instance if applicable.
		)

		See_Also:
			[registerInterface] to setup which implementation class (resp. instance)
			to inject for dependencies that specify an $(I interface) instead of a concrete type.
	 +/
	void register(T)(T value) @safe pure nothrow {
		static assert(
			isClass!T || isInterface!T || isStructPointer!T,
			"Cannot store instance of type `" ~ T.stringof ~ "`. Not a class, interface or struct-pointer."
		);
		static assert(
			isntForbiddenType!T,
			"Cannot override the referenced framework instance of type `" ~ T.stringof ~ "`."
		);

		_container.set(value);
	}

	/++
		Stores the provided instance of type `TClass` in the DI container
		to be injected for dependencies of both types `TInterface` and `TClass` later.
	 +/
	void registerInterface(TInterface, TClass)(TClass value) @safe pure nothrow {
		this.register!TClass(value);
		this.register!TInterface(value);
	}

	/// ditto
	void registerInterface(TInterface, TClass)() {
		this.registerInterface!(TInterface, TClass)(
			this.resolve!TClass()
		);
	}

	private T* makeNew(T)() if (isStruct!T) {
		return new T();
	}

	private T makeNew(T)() if (isStructPointer!T) {
		return new typeof(*T)();
	}

	/++
		Instantiates a new instance of the specified type `T`.

		Dependencies will be assigned from the underlying container.
	 +/
	T makeNew(T)() if (isClass!T || isInterface!T) {
		static if (isConstructableByDI!T == false) {
			// not constructable --> crash
			assert(false, determineWhyNotConstructableByDI!T);
		} else {
			// construct
			return this.makeNewImpl!T();
		}
	}

	private {
		T makeNewImplWithDependencies(T)() {
			pragma(inline, true);

			alias ctors = getConstructors!T;
			static assert(ctors.length == 1, "Seems like there's a bug in `isConstructableByDI`.");
			alias ctorParams = Parameters!(ctors[0]);

			static foreach (idx, P; ctorParams) {
				static if (isStruct!P) {
					version (diNoPassByValue) {
						static assert(
							false,
							"Passing dependency #"
								~ idx.to!string()
								~ " `"
								~ P.stringof
								~ "` by value (copy) to `"
								~ T.stringof
								~ "`.\n            Use a pointer (`"
								~ P.stringof
								~ "*`) instead. [`-version=diNoPassByValue`]"
						);
					}
					mixin(`P* param` ~ idx.to!string() ~ ';');
				} else {
					mixin(`P param` ~ idx.to!string() ~ ';');
				}

				mixin(`param` ~ idx.to!string()) = this.resolve!P();
			}

			return mixin(`new T(` ~ callerParameterListString!(ctorParams) ~ `)`);
		}

		T makeNewImpl(T)() {
			pragma(inline, true);

			static if (hasConstructors!T) {
				return this.makeNewImplWithDependencies!T();
			} else {
				// There is no explicit ctor available, use default one.
				return new T();
			}
		}
	}
}

/++
	UDA to mark fields as dependency for $(I Field Assignment Constructor Application).
 +/
enum dependency;

private template hasDependencyUDA(alias T) {
	import std.traits : hasUDA;

	enum hasDependencyUDA = hasUDA!(T, dependency);
}

// undocumented
enum _diConstructorUDA;

/++
	Generates a constructor with a parameter for each [dependency|@dependency] field
	and assigns the passed value to the corresponding field.
 +/
mixin template DIConstructor() {
	import oceandrift.di : dependency, diConstructorString, _diConstructorUDA;

	mixin(diConstructorString!(typeof(this)));
}

/++
	Generates code for a constructor with a parameter for each [dependency|@dependency] field
	and assigns the passed value to the corresponding field.

	---
	class MyType {
		mixin(diConstructorString!(typeof(this)));
	}
	---

	See_Also: [DIConstructor]
 +/
template diConstructorString(T) {
	private string impl() {
		import std.meta;
		import std.traits;

		alias deps = Filter!(hasDependencyUDA, DerivedMemberSymbols!T);

		static if (isStruct!T && (deps.length == 0)) {
			return "";
		} else {
			string r = "public this(";

			// determine parent dependencies
			static if (isClass!T && hasParentClass!T) {
				alias parentCtor = getSymbolsByUDA!(ParentClass!T, _diConstructorUDA);
				static assert(parentCtor.length <= 1, "Misuse of @_diConstructorUDA detected.");

				static if (parentCtor.length == 1) {
					alias depsParent = ParameterIdentifierTuple!parentCtor;
				} else {
					enum depsParent = [];
				}
			} else {
				enum depsParent = [];
			}

			// parent ctor params
			static foreach (d; depsParent) {
				r ~= "typeof(super." ~ d ~ ")" ~ d ~ ",";
			}

			// params
			static foreach (d; deps) {
				r ~= "typeof(this." ~ __traits(identifier, d) ~ ")" ~ __traits(identifier, d) ~ ",";
			}

			r ~= ")@_diConstructorUDA @safe pure nothrow @nogc{";

			// parent ctor
			static if (depsParent.length > 0) {
				r ~= "super(";
				static foreach (d; depsParent) {
					r ~= d ~ ',';
				}
				r ~= ");";
			}

			// assignments
			static foreach (d; deps) {
				r ~= "this." ~ __traits(identifier, d) ~ '=' ~ __traits(identifier, d) ~ ';';
			}

			r ~= '}';

			return r;
		}
	}

	// undocumented
	enum string diConstructorString = impl();
}

@safe unittest {
	static class Point {
		mixin DIConstructor;
	@dependency:
		int x;
		int y;
	}

	const p = new Point(12, 24);
	assert(p.x == 12);
	assert(p.y == 24);
}

@safe unittest {
	static class Point {
		mixin DIConstructor;
		int x;
		int y;
	}

	const p = new Point();
}

@safe unittest {
	static struct Point {
		mixin DIConstructor;
	private @dependency:
		int x;
		int y;
	}

	const p = Point(12, 24);
	assert(p.x == 12);
	assert(p.y == 24);
}

@safe unittest {
	static struct Point {
		mixin DIConstructor;
		int x;
		int y;
	}

	const p = Point();
}

@safe unittest {
	static class Point {
		mixin DIConstructor;
		int x;
		int y;
	}

	const p = new Point();
}

@safe unittest {
	static class Point {
		mixin DIConstructor;
	@dependency:
		const int x;
		const int y;
	}

	const p = new Point(1, 2);
	assert(p.x == 1);
	assert(p.y == 2);
}

@safe unittest {
	static class Dimension1 {
		mixin DIConstructor;
	@dependency:
		int x;
	}

	static class Dimension2 : Dimension1 {
		mixin DIConstructor;
	@dependency:
		int y;
	}

	static class Dimension3 : Dimension2 {
		mixin DIConstructor;
	@dependency:
		int z;
	}

	const d1 = new Dimension1(8);
	assert(d1.x == 8);

	const d2 = new Dimension2(12, 24);
	assert(d2.x == 12);
	assert(d2.y == 24);

	const d3 = new Dimension3(1, 5, 9);
	assert(d3.x == 1);
	assert(d3.y == 5);
	assert(d3.z == 9);
}

// == Container Tests

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

// == DI Tests

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

@safe unittest {
	static struct Bar {
		int i = 10;
	}

	static class Foo {
		Bar bar;

		this(Bar bar) {
			this.bar = bar;
		}
	}

	auto di = new DI();
	Bar* bar = di.resolve!Bar();
	bar.i = 2;

	Foo foo = di.resolve!Foo();
	bar.i = 3;
	assert(foo.bar.i == 2);
}

@safe unittest {
	static class H1 {
	}

	static class H2 {
		this(H1 d) {
		}
	}

	static class H3 {
		this(H2 d) {
		}
	}

	static class H4 {
		this(H3 d) {
		}
	}

	static class H5 {
		this(H4 d, H1 d2) {
		}
	}

	static class H6 {
		this(H5 d) {
		}
	}

	auto di = new DI();
	H6 h6 = di.resolve!H6();
	assert(h6 !is null);
}
