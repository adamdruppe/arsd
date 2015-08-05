/*
	Exceptions 2.0
*/

interface ThrowableBase {
	void fly(string file = __FILE__, size_t line = __LINE__); // should be built into the compiler's throw statement

	// override these as needed
	void printMembers(scope void delegate(in char[]) sink) const; // Tip: use mixin PrintMembers; instead of doing it yourself
	void getHumanReadableMessage(scope void delegate(in char[]) sink) const; // the exception name should give this generally but it is nice if you have an error code that needs translation or something else that isn't obvious from the name
	void printName(scope void delegate(in char[]) sink) const; // only need to override this if you aren't happy with RTTI's name field

	// just call this when you are ready
	void toString(scope void delegate(in char[]) sink) const;
}

mixin template ThrowableBaseImplementation() {
	// This sets file and line at the throw point instead of in the ctor
	// thereby separating allocation from error information - call this and
	// file+line will be set then allowing you to reuse exception objects easier
	void fly(string file = __FILE__, size_t line = __LINE__) {
		this.file = file;
		this.line = line;
		throw this;
	}

	// You don't really need this - the class name and members should give all the
	// necessary info, but it can be nice in cases like a Windows or errno exception
	// where the code isn't necessarily as at-a-glance easy as the string from GetLastError.
	/* virtual */ void getHumanReadableMessage(scope void delegate(in char[]) sink) const {
		sink(msg); // for backward compatibility
	}

	// This prints the really useful info to the user, the members' values.
	// You don't have to write this typically, instead use the mixin below.
	/* virtual */ void printMembers(scope void delegate(in char[]) sink) const {
		// this is done with the mixin from derived classes
	}

	/* virtual */ void printName(scope void delegate(in char[]) sink) const {
		sink(typeid(this).name); // FIXME: would be nice if eponymous templates didn't spew the name twice
	}

	override void toString(scope void delegate(in char[]) sink) const {
		char[32] tmpBuff = void; 
		printName(sink);
		sink("@"); sink(file); 
		sink("("); sink(line.sizeToTempString(tmpBuff[])); sink(")"); 
		sink(": "); getHumanReadableMessage(sink);
		sink("\n");
		printMembers(sink);
		if (info) { 
			try { 
				sink("----------------"); 
				foreach (t; info) { 
					sink("\n"); sink(t); 
				} 
			} 
			catch (Throwable) { 
				// ignore more errors 
			} 
		}  
	}

}

class ExceptionBase : Exception, ThrowableBase {
	// Hugely simplified ctor - nothing is even needed
	this() {
		super("");
	}

	mixin ThrowableBaseImplementation;
}

class ErrorBase : Error, ThrowableBase {
	this() { super(""); }
	mixin ThrowableBaseImplementation;
}

// Mix this into your derived class to print all its members automatically for easier debugging!
mixin template PrintMembers() {
	override void printMembers(scope void delegate(in char[]) sink) const {
		foreach(memberName; __traits(derivedMembers, typeof(this))) {
			static if(is(typeof(__traits(getMember, this, memberName))) && !is(typeof(__traits(getMember, typeof(this), memberName)) == function)) {
				sink("\t");
				sink(memberName);
				sink(" = ");
				static if(is(typeof(__traits(getMember, this, memberName)) : const(char)[]))
					sink(__traits(getMember, this, memberName));
				else static if(is(typeof(__traits(getMember, this, memberName)) : long)) {
					char[32] tmpBuff = void; 
					sink(sizeToTempString(__traits(getMember, this, memberName), tmpBuff));
				} // else pragma(msg, typeof(__traits(getMember, this, memberName)));
				sink("\n");
			}
		}

		super.printMembers(sink);
	}
}

// The class name SHOULD obviate this but you can also add another message if you like.
// You can also just override the getHumanReadableMessage yourself in cases like calling strerror
mixin template StaticHumanReadableMessage(string s) {
	override void getHumanReadableMessage(scope void delegate(in char[]) sink) const {
		sink(s);
	}
}




/*
	Enforce 2.0
*/

interface DynamicException {
	/*
	TypeInfo getArgumentType(size_t idx);
	void*    getArgumentData(size_t idx);
	string   getArgumentAsString(size_t idx);
	*/
}

template enforceBase(ExceptionBaseClass, string failureCondition = "ret is null") {
	auto enforceBase(alias func, string file = __FILE__, size_t line = __LINE__, T...)(T args) {
		auto ret = func(args);
		if(mixin(failureCondition)) {
			class C : ExceptionBaseClass, DynamicException {
				T args;
				this(T args) {
					this.args = args;
				}

				override void printMembers(scope void delegate(in char[]) sink) const {
					import std.traits;
					import std.conv;
					foreach(idx, arg; args) {
						sink("\t");
						sink(ParameterIdentifierTuple!func[idx]);
						sink(" = ");
						sink(to!string(arg));
						sink("\n");
					}
					sink("\treturn value = ");
					sink(to!string(ret));
					sink("\n");
				}

				override void printName(scope void delegate(in char[]) sink) const {
					sink(__traits(identifier, ExceptionBaseClass));
				}

				override void getHumanReadableMessage(scope void delegate(in char[]) sink) const {
					sink(__traits(identifier, func));
					sink(" call failed");
				}
			}
			
			auto exception = new C(args);
			exception.file = file;
			exception.line = line;
			throw exception;
		}

		return ret;
	}
}

/// Raises an exception given a set of local variables to print out
void raise(ExceptionBaseClass, T...)(string file = __FILE__, size_t line = __LINE__) {
	class C : ExceptionBaseClass, DynamicException {
		override void printMembers(scope void delegate(in char[]) sink) const {
			import std.conv;
			foreach(idx, arg; T) {
				sink("\t");
				sink(__traits(identifier, T[idx]));
				sink(" = ");
				sink(to!string(arg));
				sink("\n");
			}
		}

		override void printName(scope void delegate(in char[]) sink) const {
			sink(__traits(identifier, ExceptionBaseClass));
		}
	}
	
	auto exception = new C();
	exception.file = file;
	exception.line = line;
	throw exception;
}

const(char)[] sizeToTempString(long size, char[] buffer) {
	size_t pos = buffer.length - 1;
	bool negative = size < 0;
	if(size < 0)
		size = -size;
	while(size) {
		buffer[pos] = size % 10 + '0';
		size /= 10;
		pos--;
	}
	if(negative) {
		buffer[pos] = '-';
		pos--;
	}
	return buffer[pos + 1 .. $];
}

/////////////////////////////
/* USAGE EXAMPLE FOLLOWS */
/////////////////////////////


// Make sure there's sane base classes for things that take
// various types. For example, RangeError might be thrown for
// any type of index, but we might just catch any kind of range error.
//
// The base class gives us an easy catch point for the category.
class MyRangeError : ErrorBase {
	// unnecessary but kinda nice to have static error message
	mixin StaticHumanReadableMessage!"Index out of bounds";
}

// Now, we do a new class for each error condition that can happen
// inheriting from a convenient catch-all base class for our error type
// (which might be ExceptionBase itself btw)
class TypedRangeError(T) : MyRangeError {
	// Error details are stored as DATA MEMBERS
	// do NOT convert them to a string yourself
	this(T index) {
		this.index = index;
	}

	mixin StaticHumanReadableMessage!(T.stringof ~ " index out of bounds");

	// The data members can be easily inspected to learn more
	// about the error, perhaps even to retry it programmatically
	// and this also avoids the need to do something like call to!string
	// and string concatenation functions at the construction point.
	//
	// Yea, this gives more info AND is allocation-free. What's not to love?
	//
	// Templated ones can be a pain just because of the need to specify it to
	// catch or cast, but it will always at least be available in the printed string.
	T index;

	// Then, mixin PrintMembers uses D's reflection to do all the messy toString
	// data sink nonsense for you. Do this in each subclass where you add more
	// data members (which out to be generally all of them, more info is good.
	mixin PrintMembers;
}

version(exception_2_example) {

	// We can pass pre-constructed exceptions to functions and get good file/line and stacktrace info!
	void stackExample(ThrowableBase exception) {
		// throw it now (custom function cuz I change the behavior a wee bit)
		exception.fly(); // ideally, I'd change the throw statement to call this function for you to set up line and file
	}

	void main() {
		int a = 230;
		string file = "lol";
		static class BadValues : ExceptionBase {}
		//raise!(BadValues, a, file);

		alias enforce = enforceBase!ExceptionBase;

		import core.stdc.stdio;
		auto fp = enforce!fopen("nofile.txt".ptr, "rb".ptr);


		// construct, passing it error details as data, not strings.
		auto exception = new TypedRangeError!int(4); // exception construction is separated from file/line setting
		stackExample(exception); // so you can allocate/construct in one place, then set and throw somewhere else
	}
}
