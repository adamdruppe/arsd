/++
	Provides easy interoperability with Java code through JNI.

	Given this Java:
	```java
		class Hello {
			public native void hi(String s);
			public native String stringFromJNI();
			public native String returnNull();
			public native void throwException();
			static {
				System.loadLibrary("myjni");
			}
			public static void main(String[] args) {
				System.out.println("Hello from Java!");
				Hello h = new Hello();
				// we can pass data back and forth normally
				h.hi("jni");
				System.out.println(h.stringFromJNI());
				System.out.println(h.returnNull()); // it can handle null too
				// and even forward exceptions (sort of, it puts it in a RuntimeException right now)
				h.throwException();
			}
		}
	```

	And this D:
	---
		import arsd.jni;

		// if it was in a Java package, you'd pass that
		// in the string here instead of "".
		final class Hello : JavaClass!("", Hello) {

			@Export string stringFromJNI() {
				return "hey, D returned this";
			}

			@Export string returnNull() {
				return null;
			}

			@Export void throwException() {
				throw new Exception("exception from D");
			}

			@Export void hi(string name) {
				import std.stdio;
				writefln("hello from D, %s", name);
			}
		}
	---

	We can:
	$(CONSOLE
		$ javac Hello.java
		$ dmd -shared myjni.d jni.d # compile into a shared lib
		$ LD_LIBRARY_PATH=. java Hello
		Hello from Java!
		hello from D, jni
		hey, D returned this
		null
		Exception in thread "main" java.lang.RuntimeException: object.Exception@myjni.d(14): exception from D
		----------------
		??:? void myjni.Hello.throwException() [0x7f51d86dc17b]
		??:? Java_Hello_throwException [0x7f51d86dd3e0]
		??:? [0x7f51dd018406]
		??:? [0x7f51dd007ffc]
		??:? [0x7f51dd0004e6]
		??:? [0x7f51f16b0709]
		??:? [0x7f51f16c1339]
		??:? [0x7f51f16d208d]
		??:? [0x7f51f1f97058]
		??:? [0x7f51f1fae06a]
			at Hello.throwException(Native Method)
			at Hello.main(Hello.java:17)
	)

	Exact details subject to change, especially of how I pass the exceptions over.

	Calling Java methods from D coming later.


	While you can write pretty ordinary looking D code, there's some things to keep in mind for safety and efficiency.

	$(WARNING
		ALL references passed to you through Java, including
		arrays, objects, and even the `this` pointer, MUST NOT
		be stored outside the lifetime of the immediate function
		they were passed to!

		You may be able to get the D compiler to help you with
		this with the scope attribute, but regardless, don't
		do it.
	)

	It is YOUR responsibility to make sure parameter and return types
	match between D and Java. The library will `static assert` given
	unrepresentable types, but it cannot see what Java actually expects.
	Getting this wrong can lead to memory corruption and crashes.

	$(TIP
		When possible, use `wstring` instead of `string` when
		working with Java APIs. `wstring` matches the format
		of Java's `String` so it avoids a conversion step.
	)

	All [JavaClass] sub-objects should be marked `final` on the D
	side. Java may subclass them, but D can't (at least not now).

	Do not use default arguments on the exported methods. No promise
	the wrapper will do what you want when called from Java.

	You may choose to only import JavaClass from here to minimize the 
	namespace pollution.

	Constructing Java objects works and it will pin it. Just remember
	that `this` inside a method is still subject to escaping restrictions!
	
+/
module arsd.jni;

// FIXME: in general i didn't handle overloads at all

// see: https://developer.android.com/training/articles/perf-jni.html

// FIXME: do these work on Windows?
// FIXME: put this in a mixin instead of assuming it is needed/wanted?
pragma(crt_constructor)
extern(C)
void initializeDRuntime() {
	import core.runtime;
	//import core.stdc.stdio; printf("here\n");
	Runtime.initialize();
}

pragma(crt_destructor)
extern(C)
void uninitializeDRuntime() {
	import core.runtime;
	//import core.stdc.stdio; printf("gone\n");
	Runtime.terminate();
}

/+
extern(C)
jint JNI_OnLoad(JavaVM* vm, void* reserved) {
	// can also return JNI_ERR
/+

    JNIEnv* env;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }

    // Find your class. JNI_OnLoad is called from the correct class loader context for this to work.
    jclass c = env->FindClass("com/example/app/package/MyClass");
    if (c == nullptr) return JNI_ERR;

    // Register your class' native methods.
    static const JNINativeMethod methods[] = {
        {"nativeFoo", "()V", reinterpret_cast(nativeFoo)},
        {"nativeBar", "(Ljava/lang/String;I)Z", reinterpret_cast(nativeBar)},
    };
    int rc = env->RegisterNatives(c, methods, sizeof(methods)/sizeof(JNINativeMethod));
    if (rc != JNI_OK) return rc;

+/

	return JNI_VERSION_1_6;
}
extern(C)
void JNI_OnUnload(JavaVM* vm, void* reserved) {
	// FIXME: the cached _jmethodIDs need to all be cleared out too
}
+/

// need this for Import functions
JNIEnv* activeEnv;
struct ActivateJniEnv {
	// this will put it on a call stack so it will be
	// sane through re-entrant situations 
	JNIEnv* old;
	this(JNIEnv* e) {
		old = activeEnv;
		activeEnv = e;
	}

	~this() {
		activeEnv = old;
	}
}

// FIXME make a start JVM function and figure out threads...


private void exceptionCheck(JNIEnv* env) {
	if((*env).ExceptionCheck(env)) {
		// ExceptionDescribe // prints it to stderr, not that interesting
		jthrowable thrown = (*env).ExceptionOccurred(env);
		// do I need to free thrown?
		(*env).ExceptionClear(env);

		throw new Exception("Java threw");
	}
}

private enum ImportImplementationString = q{
		static if(is(typeof(return) == void)) {
			(*env).CallSTATICVoidMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
		} else static if(is(typeof(return) == int)) {
			auto ret = (*env).CallSTATICIntMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) == long)) {
			auto ret = (*env).CallSTATICLongMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) == float)) {
			auto ret = (*env).CallSTATICFloatMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) == double)) {
			auto ret = (*env).CallSTATICDoubleMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) == bool)) {
			auto ret = (*env).CallSTATICBooleanMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) == byte)) {
			auto ret = (*env).CallSTATICByteMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) == wchar)) {
			auto ret = (*env).CallSTATICCharMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else {
			static assert(0, "Unsupported return type for JNI " ~ typeof(return).stringof);
				//return DDataToJni(env, __traits(getMember, dobj, __traits(identifier, method))(JavaParamsToD!(Parameters!method)(env, args).args));
		}
};

private mixin template JavaImportImpl(T, alias method) {
	import std.traits;

	private static jmethodID _jmethodID;

	static if(__traits(identifier, method) == "__ctor")
	pragma(mangle, method.mangleof)
	private static T implementation(Parameters!method args, T this_) {
		auto env = activeEnv;
		if(env is null)
			throw new Exception("JNI not active in this thread");

		if(!_jmethodID) {
			jclass jc;
			if(!internalJavaClassHandle_) {
				jc = (*env).FindClass(env, (T._javaParameterString[1 .. $-1] ~ "\0").ptr);
				if(!jc)
					throw new Exception("Cannot find Java class " ~ T._javaParameterString[1 .. $-1]);
				internalJavaClassHandle_ = jc;
			} else {
				jc = internalJavaClassHandle_;
			}
			_jmethodID = (*env).GetMethodID(env, jc,
				"<init>",
				// java method string is (args)ret
				("(" ~ DTypesToJniString!(typeof(args)) ~ ")V\0").ptr
			);

			if(!_jmethodID)
				throw new Exception("Cannot find static Java method " ~ T.stringof ~ "." ~ __traits(identifier, method));
		}

		auto o = (*env).NewObject(env, internalJavaClassHandle_, _jmethodID, DDataToJni(env, args).args);
		this_.internalJavaHandle_ = o;
		return this_;
	}
	else static if(__traits(isStaticFunction, method))
	pragma(mangle, method.mangleof)
	private static ReturnType!method implementation(Parameters!method args) {
		auto env = activeEnv;
		if(env is null)
			throw new Exception("JNI not active in this thread");

		if(!_jmethodID) {
			jclass jc;
			if(!internalJavaClassHandle_) {
				jc = (*env).FindClass(env, (T._javaParameterString[1 .. $-1] ~ "\0").ptr);
				if(!jc)
					throw new Exception("Cannot find Java class " ~ T._javaParameterString[1 .. $-1]);
				internalJavaClassHandle_ = jc;
			} else {
				jc = internalJavaClassHandle_;
			}
			_jmethodID = (*env).GetStaticMethodID(env, jc,
				__traits(identifier, method).ptr,
				// java method string is (args)ret
				("(" ~ DTypesToJniString!(typeof(args)) ~ ")" ~ DTypesToJniString!(typeof(return)) ~ "\0").ptr
			);

			if(!_jmethodID)
				throw new Exception("Cannot find static Java method " ~ T.stringof ~ "." ~ __traits(identifier, method));
		}

		auto jobj = internalJavaClassHandle_;

		import std.string;
		mixin(ImportImplementationString.replace("STATIC", "Static"));
	}
	else
	pragma(mangle, method.mangleof)
	private static ReturnType!method implementation(Parameters!method args, T this_) {
		auto env = activeEnv;
		if(env is null)
			throw new Exception("JNI not active in this thread");

		auto jobj = this_.getJavaHandle();
		if(!_jmethodID) {
			auto jc = (*env).GetObjectClass(env, jobj);
			_jmethodID = (*env).GetMethodID(env, jc,
				__traits(identifier, method).ptr,
				// java method string is (args)ret
				("(" ~ DTypesToJniString!(typeof(args)) ~ ")" ~ DTypesToJniString!(typeof(return)) ~ "\0").ptr
			);

			if(!_jmethodID)
				throw new Exception("Cannot find Java method " ~ T.stringof ~ "." ~ __traits(identifier, method));
		}

		import std.string;
		mixin(ImportImplementationString.replace("STATIC", ""));
	}
}

private template DTypesToJniString(Types...) {
	static if(Types.length == 0)
		string DTypesToJniString = "";
	else static if(Types.length == 1) {
		alias T = Types[0];

		static if(is(T == void))
			string DTypesToJniString = "V";
		else static if(is(T == string))
			string DTypesToJniString = "Ljava/lang/String;";
		else static if(is(T == wstring))
			string DTypesToJniString = "Ljava/lang/String;";
		else static if(is(T == int))
			string DTypesToJniString = "I";
		else static if(is(T == bool))
			string DTypesToJniString = "Z";
		else static if(is(T == byte))
			string DTypesToJniString = "B";
		else static if(is(T == wchar))
			string DTypesToJniString = "C";
		else static if(is(T == short))
			string DTypesToJniString = "S";
		else static if(is(T == long))
			string DTypesToJniString = "J";
		else static if(is(T == float))
			string DTypesToJniString = "F";
		else static if(is(T == double))
			string DTypesToJniString = "D";
		else static if(is(T == size_t))
			string DTypesToJniString = "I"; // possible FIXME...
		else static if(is(T == IJavaObject))
			string DTypesToJniString = "LObject;"; // FIXME?
		else static if(is(T : IJavaObject)) // child of this but a concrete type
			string DTypesToJniString = T._javaParameterString;
		/+ // FIXME they are just "[" ~ element type string
		else static if(is(T == IJavaObject[]))
			string DTypesToJniString = jobjectArray;
		else static if(is(T == bool[]))
			string DTypesToJniString = jbooleanArray;
		else static if(is(T == byte[]))
			string DTypesToJniString = jbyteArray;
		else static if(is(T == wchar[]))
			string DTypesToJniString = jcharArray;
		else static if(is(T == short[]))
			string DTypesToJniString = jshortArray;
		else static if(is(T == int[]))
			string DTypesToJniString = jintArray;
		else static if(is(T == long[]))
			string DTypesToJniString = jlongArray;
		else static if(is(T == float[]))
			string DTypesToJniString = jfloatArray;
		else static if(is(T == double[]))
			string DTypesToJniString = jdoubleArray;
		+/
		else static assert(0, "Unsupported type for JNI call " ~ T.stringof);
	} else {
		import std.typecons;
		string DTypesToJni = DTypesToJni!(Types[0]) ~ DTypesToJni(Types[1 .. $]);
	}
}


private template DTypesToJni(Types...) {
	static if(Types.length == 0)
		alias DTypesToJni = Types;
	else static if(Types.length == 1) {
		alias T = Types[0];

		static if(is(T == void))
			alias DTypesToJni = void;
		else static if(is(T == string))
			alias DTypesToJni = jstring;
		else static if(is(T == wstring))
			alias DTypesToJni = jstring;
		else static if(is(T == int))
			alias DTypesToJni = jint;
		else static if(is(T == bool))
			alias DTypesToJni = jboolean;
		else static if(is(T == byte))
			alias DTypesToJni = jbyte;
		else static if(is(T == wchar))
			alias DTypesToJni = jchar;
		else static if(is(T == short))
			alias DTypesToJni = jshort;
		else static if(is(T == long))
			alias DTypesToJni = jlong;
		else static if(is(T == float))
			alias DTypesToJni = jfloat;
		else static if(is(T == double))
			alias DTypesToJni = jdouble;
		else static if(is(T == size_t))
			alias DTypesToJni = jsize;
		else static if(is(T : IJavaObject))
			alias DTypesToJni = jobject;
		else static if(is(T == IJavaObject[]))
			alias DTypesToJni = jobjectArray;
		else static if(is(T == bool[]))
			alias DTypesToJni = jbooleanArray;
		else static if(is(T == byte[]))
			alias DTypesToJni = jbyteArray;
		else static if(is(T == wchar[]))
			alias DTypesToJni = jcharArray;
		else static if(is(T == short[]))
			alias DTypesToJni = jshortArray;
		else static if(is(T == int[]))
			alias DTypesToJni = jintArray;
		else static if(is(T == long[]))
			alias DTypesToJni = jlongArray;
		else static if(is(T == float[]))
			alias DTypesToJni = jfloatArray;
		else static if(is(T == double[]))
			alias DTypesToJni = jdoubleArray;
		else static assert(0, "Unsupported type for JNI " ~ T.stringof);
	} else {
		import std.typecons;
		alias DTypesToJni = AliasSeq!(DTypesToJni!(Types[0]), DTypesToJni(Types[1 .. $]));
	}
}

auto DDataToJni(T...)(JNIEnv* env, T data) {
	import std.meta;
	struct Tmp {
		AliasSeq!(DTypesToJni!(T)) args;
	}

	Tmp t;
	foreach(idx, ref arg; t.args)
		arg = DDatumToJni(env, data[idx]);
	return t;
}

auto DDatumToJni(T)(JNIEnv* env, T data) {
	static if(is(T == void))
		static assert(0);
	else static if(is(T == string)) {
		if(data is null)
			return null;
		wchar[1024] buffer;
		const(wchar)[] translated;
		if(data.length < 1024) {
			size_t len;
			foreach(wchar ch; data)
				buffer[len++] = ch;
			translated = buffer[0 .. len];
		} else {
			import std.conv;
			translated = to!wstring(data);
		}
		// Java copies the buffer so it is perfectly fine to return here now
		return (*env).NewString(env, translated.ptr, cast(jsize) translated.length);
	} else static if(is(T == wstring))
		return (*env).NewString(env, data.ptr, cast(jsize) data.length);
	else static if(is(T == int)) return data;
	else static if(is(T == bool)) return data;
	else static if(is(T == byte)) return data;
	else static if(is(T == wchar)) return data;
	else static if(is(T == short)) return data;
	else static if(is(T == long)) return data;
	else static if(is(T == float)) return data;
	else static if(is(T == double)) return data;
	else static if(is(T == size_t)) return cast(int) data;
	else static if(is(T : IJavaObject)) return data.getJavaHandle();
	else static assert(0, "Unsupported type " ~ T.stringof);
	/* // FIXME: finish these.
	else static if(is(T == IJavaObject[]))
		alias DTypesToJni = jobjectArray;
	else static if(is(T == bool[]))
		alias DTypesToJni = jbooleanArray;
	else static if(is(T == byte[]))
		alias DTypesToJni = jbyteArray;
	else static if(is(T == wchar[]))
		alias DTypesToJni = jcharArray;
	else static if(is(T == short[]))
		alias DTypesToJni = jshortArray;
	else static if(is(T == int[]))
		alias DTypesToJni = jintArray;
	else static if(is(T == long[]))
		alias DTypesToJni = jlongArray;
	else static if(is(T == float[]))
		alias DTypesToJni = jfloatArray;
	else static if(is(T == double[]))
		alias DTypesToJni = jdoubleArray;
	*/

}

private struct JavaParamsToD(Spec...) {
	import std.meta;

	Spec args;
	AliasSeq!(DTypesToJni!Spec) jargs;
	JNIEnv* env;

	~this() {
		// import core.stdc.stdio; printf("dtor\n");

		// any time we sliced the Java object directly, we need to clean it up
		// so this must stay in sync with the constructor's logic
		foreach(idx, arg; args) {
			static if(is(typeof(arg) == wstring)) {
				// also need to check for null. not allowed to release null
				if(arg.ptr !is null) {
					auto jarg = jargs[idx];
					(*env).ReleaseStringChars(env, jarg, arg.ptr);
				}
			}
		}
	}

	this(JNIEnv* env, AliasSeq!(DTypesToJni!Spec) jargs) {
		this.jargs = jargs;
		this.env = env;

		foreach(idx, ref arg; args) {
			auto jarg = jargs[idx];
			alias T = typeof(arg);
			alias J = typeof(jarg);

			static if(__traits(compiles, arg = jarg))
				arg = jarg;
			else static if(is(T == size_t)) {
				static assert(is(J == jsize));
				arg = cast(size_t) jarg;
			} else static if(is(T == string) || is(T == wstring)) {
				static assert(is(J == jstring));
				auto len = (*env).GetStringLength(env, jarg);
				auto ptr = (*env).GetStringChars(env, jarg, null);
				// java strings are immutable so this should be fine
				// just remember the lifetime limitation... which is also
				// why i am ok
				static if(is(T == wstring)) {
					if(ptr !is null)
						arg = ptr[0 .. len];
				} else {
					/*
					// I actually can't do this little buffer here
					// because this helper function will return before
					// it is used. yikes.
					char[1024] buffer;
					int blen;
					if(len < buffer.length / 4) {
						foreach(char c; ptr[0 .. len])
							buffer[blen++] = c;
						arg = buffer[0 .. blen];
					} else {
						arg = to!string(ptr[0 .. len]);
					}
					*/
					import std.conv;
					if(ptr !is null) {
						arg = to!string(ptr[0 .. len]);
						(*env).ReleaseStringChars(env, jarg, ptr);
					}
				}
			}
			// FIXME other types of arrays
			//else static if(is(T : IJavaObject)) return data.getJavaHandle(); // create the D object, hook in the handle, do some kind of type check from the Java class name.
			else static assert(0, "Unimplemented/unsupported type " ~ T.stringof);

		}
	}
}

void jniRethrow(JNIEnv* env, Throwable t) {
	(*env).ThrowNew(
		env,
		(*env).FindClass(env, "java/lang/RuntimeException"),
		(t.toString() ~ "\0").ptr
	);
}

private mixin template JavaExportImpl(T, alias method) {
	import std.traits;
	import std.string;

	static if(__traits(identifier, method) == "__ctor")
		static assert(0, "Cannot export D constructors");

	static private string JniMangle() {
		// this actually breaks with -betterC though so does a lot more so meh.
		static if(is(T : JavaClass!(JP, P), string JP, P))
			return "Java_" ~replace(JP, ".", "_") ~ (JP.length ? "_" : "") ~ P.stringof ~ "_" ~ __traits(identifier, method);
		else static assert(0);
	}

	extern(C)
	pragma(mangle, JniMangle())
	// I need it in the DLL, but want it to be not accessible from outside... alas.
	export /*private*/ static DTypesToJni!(ReturnType!method) privateJniImplementation(JNIEnv* env, jobject obj, DTypesToJni!(Parameters!method) args) {
		// set it up in the thread for future calls
		ActivateJniEnv thing = ActivateJniEnv(env);

		// FIXME: pull the same D object again if possible... though idk
		ubyte[__traits(classInstanceSize, T)] byteBuffer;
		byteBuffer[] = (cast(const(ubyte)[]) typeid(T).initializer())[];

		// I specifically do NOT call the constructor here, since those may forward to Java and make things ugly!
		// The init value is cool as-is.

		auto dobj = cast(T) byteBuffer.ptr;
		dobj.internalJavaHandle_ = obj;

		// getMember(identifer) is weird but i want to get the method on this
		// particular instance and it feels less hacky than doing the delegate

		static if(is(typeof(return) == void)) {
			try {
				__traits(getMember, dobj, __traits(identifier, method))(JavaParamsToD!(Parameters!method)(env, args).args);
			} catch(Throwable t) {
				jniRethrow(env, t);
			}
		} else {
			try {
				return DDatumToJni(env, __traits(getMember, dobj, __traits(identifier, method))(JavaParamsToD!(Parameters!method)(env, args).args));
			} catch(Throwable t) {
				jniRethrow(env, t);
				return typeof(return).init; // still required to return...
			}
		}
	}
}

/++
	This is really used by the [JavaClass] class below to give a base for all Java classes.
	You can use it for that too, but you really shouldn't try to implement it yourself
	(it doesn't do much anyway).
+/
interface IJavaObject {
	/// Remember the returned object is a TEMPORARY local reference!
	protected jobject getJavaHandle();
}

/++
	This is the base class you inherit from in D classes that represent Java classes.
	You can then mark your methods @Import if they are implemented in Java and you want
	to call them from D, or @Export if they are implemented in D and want to be called
	as a `native` method from Java.

	Methods marked without either of these signifiers are not associated with Java.

	You should not expect any instance data on these to survive function calls, since
	associating it back with Java across calls may be impossible.
+/
class JavaClass(string javaPackage, CRTP) : IJavaObject {

	static assert(__traits(isFinalClass, CRTP), "Java classes must be final on the D side and " ~ CRTP.stringof ~ " is not");

	enum Import; /// UDA to indicate you are importing the method from Java. Do NOT put a body on these methods.
	enum Export; /// UDA to indicate you are exporting the method to Java. Put a D implementation body on these.

	static foreach(memberName; __traits(derivedMembers, CRTP))
	static foreach(attr; __traits(getAttributes, __traits(getMember, CRTP, memberName))) {
		static if(is(attr == Import))
			mixin JavaImportImpl!(CRTP, __traits(getMember, CRTP, memberName));
		else static if(is(attr == Export))
			mixin JavaExportImpl!(CRTP, __traits(getMember, CRTP, memberName));
		else static if(memberName == "__ctor")
			static assert("JavaClasses can only be constructed by Java. Try making a constructor in Java, then make an @Import this(args); here.");
	}

	protected jobject internalJavaHandle_;
	protected jobject getJavaHandle() { return internalJavaHandle_; }

	protected static jclass internalJavaClassHandle_;

	static import std.string;
	static if(javaPackage.length)
		public static immutable string _javaParameterString = "L" ~ std.string.replace(javaPackage, ".", "/") ~ "/" ~ CRTP.stringof ~ ";";
	else
		public static immutable string _javaParameterString = "L" ~ CRTP.stringof ~ ";";
}

















// Mechanically translated <jni.h> header below.
// You can use it yourself if you need low level access to JNI.



import core.stdc.stdarg;

//version (Android):
extern (C):
@system:
nothrow:
@nogc:

alias bool jboolean;
alias byte jbyte;
alias wchar jchar;
alias short jshort;
alias int jint;
alias long jlong;
alias float jfloat;
alias double jdouble;
alias jint jsize;
alias void* jobject;
alias jobject jclass;
alias jobject jstring;
alias jobject jarray;
alias jarray jobjectArray;
alias jarray jbooleanArray;
alias jarray jbyteArray;
alias jarray jcharArray;
alias jarray jshortArray;
alias jarray jintArray;
alias jarray jlongArray;
alias jarray jfloatArray;
alias jarray jdoubleArray;
alias jobject jthrowable;
alias jobject jweak;
alias _jfieldID* jfieldID;
alias _jmethodID* jmethodID;
alias const(JNINativeInterface)* C_JNIEnv;
alias const(JNINativeInterface)* JNIEnv;
alias const(JNIInvokeInterface)* JavaVM;

enum jobjectRefType
{
    JNIInvalidRefType = 0,
    JNILocalRefType = 1,
    JNIGlobalRefType = 2,
    JNIWeakGlobalRefType = 3
}

enum JNI_FALSE = 0;
enum JNI_TRUE = 1;
enum JNI_VERSION_1_1 = 0x00010001;
enum JNI_VERSION_1_2 = 0x00010002;
enum JNI_VERSION_1_4 = 0x00010004;
enum JNI_VERSION_1_6 = 0x00010006;
enum JNI_OK = 0;
enum JNI_ERR = -1;
enum JNI_EDETACHED = -2;
enum JNI_EVERSION = -3;
enum JNI_COMMIT = 1; 
enum JNI_ABORT = 2; 

struct JNINativeMethod
{
    const(char)* name;
    const(char)* signature;
    void* fnPtr;
}

struct JNINativeInterface
{
    void* reserved0;
    void* reserved1;
    void* reserved2;
    void* reserved3;
    jint function(JNIEnv*) GetVersion;
    jclass function(JNIEnv*, const(char)*, jobject, const(jbyte)*, jsize) DefineClass;
    jclass function(JNIEnv*, const(char)*) FindClass;
    jmethodID function(JNIEnv*, jobject) FromReflectedMethod;
    jfieldID function(JNIEnv*, jobject) FromReflectedField;
    jobject function(JNIEnv*, jclass, jmethodID, jboolean) ToReflectedMethod;
    jclass function(JNIEnv*, jclass) GetSuperclass;
    jboolean function(JNIEnv*, jclass, jclass) IsAssignableFrom;
    jobject function(JNIEnv*, jclass, jfieldID, jboolean) ToReflectedField;
    jint function(JNIEnv*, jthrowable) Throw;
    jint function(JNIEnv*, jclass, const(char)*) ThrowNew;
    jthrowable function(JNIEnv*) ExceptionOccurred;
    void function(JNIEnv*) ExceptionDescribe;
    void function(JNIEnv*) ExceptionClear;
    void function(JNIEnv*, const(char)*) FatalError;
    jint function(JNIEnv*, jint) PushLocalFrame;
    jobject function(JNIEnv*, jobject) PopLocalFrame;
    jobject function(JNIEnv*, jobject) NewGlobalRef;
    void function(JNIEnv*, jobject) DeleteGlobalRef;
    void function(JNIEnv*, jobject) DeleteLocalRef;
    jboolean function(JNIEnv*, jobject, jobject) IsSameObject;
    jobject function(JNIEnv*, jobject) NewLocalRef;
    jint function(JNIEnv*, jint) EnsureLocalCapacity;
    jobject function(JNIEnv*, jclass) AllocObject;
    jobject function(JNIEnv*, jclass, jmethodID, ...) NewObject;
    jobject function(JNIEnv*, jclass, jmethodID, va_list) NewObjectV;
    jobject function(JNIEnv*, jclass, jmethodID, jvalue*) NewObjectA;
    jclass function(JNIEnv*, jobject) GetObjectClass;
    jboolean function(JNIEnv*, jobject, jclass) IsInstanceOf;
    jmethodID function(JNIEnv*, jclass, const(char)*, const(char)*) GetMethodID;
    jobject function(JNIEnv*, jobject, jmethodID, ...) CallObjectMethod;
    jobject function(JNIEnv*, jobject, jmethodID, va_list) CallObjectMethodV;
    jobject function(JNIEnv*, jobject, jmethodID, jvalue*) CallObjectMethodA;
    jboolean function(JNIEnv*, jobject, jmethodID, ...) CallBooleanMethod;
    jboolean function(JNIEnv*, jobject, jmethodID, va_list) CallBooleanMethodV;
    jboolean function(JNIEnv*, jobject, jmethodID, jvalue*) CallBooleanMethodA;
    jbyte function(JNIEnv*, jobject, jmethodID, ...) CallByteMethod;
    jbyte function(JNIEnv*, jobject, jmethodID, va_list) CallByteMethodV;
    jbyte function(JNIEnv*, jobject, jmethodID, jvalue*) CallByteMethodA;
    jchar function(JNIEnv*, jobject, jmethodID, ...) CallCharMethod;
    jchar function(JNIEnv*, jobject, jmethodID, va_list) CallCharMethodV;
    jchar function(JNIEnv*, jobject, jmethodID, jvalue*) CallCharMethodA;
    jshort function(JNIEnv*, jobject, jmethodID, ...) CallShortMethod;
    jshort function(JNIEnv*, jobject, jmethodID, va_list) CallShortMethodV;
    jshort function(JNIEnv*, jobject, jmethodID, jvalue*) CallShortMethodA;
    jint function(JNIEnv*, jobject, jmethodID, ...) CallIntMethod;
    jint function(JNIEnv*, jobject, jmethodID, va_list) CallIntMethodV;
    jint function(JNIEnv*, jobject, jmethodID, jvalue*) CallIntMethodA;
    jlong function(JNIEnv*, jobject, jmethodID, ...) CallLongMethod;
    jlong function(JNIEnv*, jobject, jmethodID, va_list) CallLongMethodV;
    jlong function(JNIEnv*, jobject, jmethodID, jvalue*) CallLongMethodA;
    jfloat function(JNIEnv*, jobject, jmethodID, ...) CallFloatMethod;
    jfloat function(JNIEnv*, jobject, jmethodID, va_list) CallFloatMethodV;
    jfloat function(JNIEnv*, jobject, jmethodID, jvalue*) CallFloatMethodA;
    jdouble function(JNIEnv*, jobject, jmethodID, ...) CallDoubleMethod;
    jdouble function(JNIEnv*, jobject, jmethodID, va_list) CallDoubleMethodV;
    jdouble function(JNIEnv*, jobject, jmethodID, jvalue*) CallDoubleMethodA;
    void function(JNIEnv*, jobject, jmethodID, ...) CallVoidMethod;
    void function(JNIEnv*, jobject, jmethodID, va_list) CallVoidMethodV;
    void function(JNIEnv*, jobject, jmethodID, jvalue*) CallVoidMethodA;
    jobject function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualObjectMethod;
    jobject function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualObjectMethodV;
    jobject function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualObjectMethodA;
    jboolean function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualBooleanMethod;
    jboolean function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualBooleanMethodV;
    jboolean function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualBooleanMethodA;
    jbyte function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualByteMethod;
    jbyte function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualByteMethodV;
    jbyte function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualByteMethodA;
    jchar function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualCharMethod;
    jchar function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualCharMethodV;
    jchar function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualCharMethodA;
    jshort function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualShortMethod;
    jshort function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualShortMethodV;
    jshort function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualShortMethodA;
    jint function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualIntMethod;
    jint function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualIntMethodV;
    jint function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualIntMethodA;
    jlong function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualLongMethod;
    jlong function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualLongMethodV;
    jlong function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualLongMethodA;
    jfloat function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualFloatMethod;
    jfloat function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualFloatMethodV;
    jfloat function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualFloatMethodA;
    jdouble function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualDoubleMethod;
    jdouble function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualDoubleMethodV;
    jdouble function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualDoubleMethodA;
    void function(JNIEnv*, jobject, jclass, jmethodID, ...) CallNonvirtualVoidMethod;
    void function(JNIEnv*, jobject, jclass, jmethodID, va_list) CallNonvirtualVoidMethodV;
    void function(JNIEnv*, jobject, jclass, jmethodID, jvalue*) CallNonvirtualVoidMethodA;
    jfieldID function(JNIEnv*, jclass, const(char)*, const(char)*) GetFieldID;
    jobject function(JNIEnv*, jobject, jfieldID) GetObjectField;
    jboolean function(JNIEnv*, jobject, jfieldID) GetBooleanField;
    jbyte function(JNIEnv*, jobject, jfieldID) GetByteField;
    jchar function(JNIEnv*, jobject, jfieldID) GetCharField;
    jshort function(JNIEnv*, jobject, jfieldID) GetShortField;
    jint function(JNIEnv*, jobject, jfieldID) GetIntField;
    jlong function(JNIEnv*, jobject, jfieldID) GetLongField;
    jfloat function(JNIEnv*, jobject, jfieldID) GetFloatField;
    jdouble function(JNIEnv*, jobject, jfieldID) GetDoubleField;
    void function(JNIEnv*, jobject, jfieldID, jobject) SetObjectField;
    void function(JNIEnv*, jobject, jfieldID, jboolean) SetBooleanField;
    void function(JNIEnv*, jobject, jfieldID, jbyte) SetByteField;
    void function(JNIEnv*, jobject, jfieldID, jchar) SetCharField;
    void function(JNIEnv*, jobject, jfieldID, jshort) SetShortField;
    void function(JNIEnv*, jobject, jfieldID, jint) SetIntField;
    void function(JNIEnv*, jobject, jfieldID, jlong) SetLongField;
    void function(JNIEnv*, jobject, jfieldID, jfloat) SetFloatField;
    void function(JNIEnv*, jobject, jfieldID, jdouble) SetDoubleField;
    jmethodID function(JNIEnv*, jclass, const(char)*, const(char)*) GetStaticMethodID;
    jobject function(JNIEnv*, jclass, jmethodID, ...) CallStaticObjectMethod;
    jobject function(JNIEnv*, jclass, jmethodID, va_list) CallStaticObjectMethodV;
    jobject function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticObjectMethodA;
    jboolean function(JNIEnv*, jclass, jmethodID, ...) CallStaticBooleanMethod;
    jboolean function(JNIEnv*, jclass, jmethodID, va_list) CallStaticBooleanMethodV;
    jboolean function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticBooleanMethodA;
    jbyte function(JNIEnv*, jclass, jmethodID, ...) CallStaticByteMethod;
    jbyte function(JNIEnv*, jclass, jmethodID, va_list) CallStaticByteMethodV;
    jbyte function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticByteMethodA;
    jchar function(JNIEnv*, jclass, jmethodID, ...) CallStaticCharMethod;
    jchar function(JNIEnv*, jclass, jmethodID, va_list) CallStaticCharMethodV;
    jchar function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticCharMethodA;
    jshort function(JNIEnv*, jclass, jmethodID, ...) CallStaticShortMethod;
    jshort function(JNIEnv*, jclass, jmethodID, va_list) CallStaticShortMethodV;
    jshort function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticShortMethodA;
    jint function(JNIEnv*, jclass, jmethodID, ...) CallStaticIntMethod;
    jint function(JNIEnv*, jclass, jmethodID, va_list) CallStaticIntMethodV;
    jint function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticIntMethodA;
    jlong function(JNIEnv*, jclass, jmethodID, ...) CallStaticLongMethod;
    jlong function(JNIEnv*, jclass, jmethodID, va_list) CallStaticLongMethodV;
    jlong function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticLongMethodA;
    jfloat function(JNIEnv*, jclass, jmethodID, ...) CallStaticFloatMethod;
    jfloat function(JNIEnv*, jclass, jmethodID, va_list) CallStaticFloatMethodV;
    jfloat function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticFloatMethodA;
    jdouble function(JNIEnv*, jclass, jmethodID, ...) CallStaticDoubleMethod;
    jdouble function(JNIEnv*, jclass, jmethodID, va_list) CallStaticDoubleMethodV;
    jdouble function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticDoubleMethodA;
    void function(JNIEnv*, jclass, jmethodID, ...) CallStaticVoidMethod;
    void function(JNIEnv*, jclass, jmethodID, va_list) CallStaticVoidMethodV;
    void function(JNIEnv*, jclass, jmethodID, jvalue*) CallStaticVoidMethodA;
    jfieldID function(JNIEnv*, jclass, const(char)*, const(char)*) GetStaticFieldID;
    jobject function(JNIEnv*, jclass, jfieldID) GetStaticObjectField;
    jboolean function(JNIEnv*, jclass, jfieldID) GetStaticBooleanField;
    jbyte function(JNIEnv*, jclass, jfieldID) GetStaticByteField;
    jchar function(JNIEnv*, jclass, jfieldID) GetStaticCharField;
    jshort function(JNIEnv*, jclass, jfieldID) GetStaticShortField;
    jint function(JNIEnv*, jclass, jfieldID) GetStaticIntField;
    jlong function(JNIEnv*, jclass, jfieldID) GetStaticLongField;
    jfloat function(JNIEnv*, jclass, jfieldID) GetStaticFloatField;
    jdouble function(JNIEnv*, jclass, jfieldID) GetStaticDoubleField;
    void function(JNIEnv*, jclass, jfieldID, jobject) SetStaticObjectField;
    void function(JNIEnv*, jclass, jfieldID, jboolean) SetStaticBooleanField;
    void function(JNIEnv*, jclass, jfieldID, jbyte) SetStaticByteField;
    void function(JNIEnv*, jclass, jfieldID, jchar) SetStaticCharField;
    void function(JNIEnv*, jclass, jfieldID, jshort) SetStaticShortField;
    void function(JNIEnv*, jclass, jfieldID, jint) SetStaticIntField;
    void function(JNIEnv*, jclass, jfieldID, jlong) SetStaticLongField;
    void function(JNIEnv*, jclass, jfieldID, jfloat) SetStaticFloatField;
    void function(JNIEnv*, jclass, jfieldID, jdouble) SetStaticDoubleField;
    jstring function(JNIEnv*, const(jchar)*, jsize) NewString;
    jsize function(JNIEnv*, jstring) GetStringLength;
    const(jchar)* function(JNIEnv*, jstring, jboolean*) GetStringChars;
    void function(JNIEnv*, jstring, const(jchar)*) ReleaseStringChars;
    jstring function(JNIEnv*, const(char)*) NewStringUTF;
    jsize function(JNIEnv*, jstring) GetStringUTFLength;
    const(char)* function(JNIEnv*, jstring, jboolean*) GetStringUTFChars;
    void function(JNIEnv*, jstring, const(char)*) ReleaseStringUTFChars;
    jsize function(JNIEnv*, jarray) GetArrayLength;
    jobjectArray function(JNIEnv*, jsize, jclass, jobject) NewObjectArray;
    jobject function(JNIEnv*, jobjectArray, jsize) GetObjectArrayElement;
    void function(JNIEnv*, jobjectArray, jsize, jobject) SetObjectArrayElement;
    jbooleanArray function(JNIEnv*, jsize) NewBooleanArray;
    jbyteArray function(JNIEnv*, jsize) NewByteArray;
    jcharArray function(JNIEnv*, jsize) NewCharArray;
    jshortArray function(JNIEnv*, jsize) NewShortArray;
    jintArray function(JNIEnv*, jsize) NewIntArray;
    jlongArray function(JNIEnv*, jsize) NewLongArray;
    jfloatArray function(JNIEnv*, jsize) NewFloatArray;
    jdoubleArray function(JNIEnv*, jsize) NewDoubleArray;
    jboolean* function(JNIEnv*, jbooleanArray, jboolean*) GetBooleanArrayElements;
    jbyte* function(JNIEnv*, jbyteArray, jboolean*) GetByteArrayElements;
    jchar* function(JNIEnv*, jcharArray, jboolean*) GetCharArrayElements;
    jshort* function(JNIEnv*, jshortArray, jboolean*) GetShortArrayElements;
    jint* function(JNIEnv*, jintArray, jboolean*) GetIntArrayElements;
    jlong* function(JNIEnv*, jlongArray, jboolean*) GetLongArrayElements;
    jfloat* function(JNIEnv*, jfloatArray, jboolean*) GetFloatArrayElements;
    jdouble* function(JNIEnv*, jdoubleArray, jboolean*) GetDoubleArrayElements;
    void function(JNIEnv*, jbooleanArray, jboolean*, jint) ReleaseBooleanArrayElements;
    void function(JNIEnv*, jbyteArray, jbyte*, jint) ReleaseByteArrayElements;
    void function(JNIEnv*, jcharArray, jchar*, jint) ReleaseCharArrayElements;
    void function(JNIEnv*, jshortArray, jshort*, jint) ReleaseShortArrayElements;
    void function(JNIEnv*, jintArray, jint*, jint) ReleaseIntArrayElements;
    void function(JNIEnv*, jlongArray, jlong*, jint) ReleaseLongArrayElements;
    void function(JNIEnv*, jfloatArray, jfloat*, jint) ReleaseFloatArrayElements;
    void function(JNIEnv*, jdoubleArray, jdouble*, jint) ReleaseDoubleArrayElements;
    void function(JNIEnv*, jbooleanArray, jsize, jsize, jboolean*) GetBooleanArrayRegion;
    void function(JNIEnv*, jbyteArray, jsize, jsize, jbyte*) GetByteArrayRegion;
    void function(JNIEnv*, jcharArray, jsize, jsize, jchar*) GetCharArrayRegion;
    void function(JNIEnv*, jshortArray, jsize, jsize, jshort*) GetShortArrayRegion;
    void function(JNIEnv*, jintArray, jsize, jsize, jint*) GetIntArrayRegion;
    void function(JNIEnv*, jlongArray, jsize, jsize, jlong*) GetLongArrayRegion;
    void function(JNIEnv*, jfloatArray, jsize, jsize, jfloat*) GetFloatArrayRegion;
    void function(JNIEnv*, jdoubleArray, jsize, jsize, jdouble*) GetDoubleArrayRegion;
    void function(JNIEnv*, jbooleanArray, jsize, jsize, const(jboolean)*) SetBooleanArrayRegion;
    void function(JNIEnv*, jbyteArray, jsize, jsize, const(jbyte)*) SetByteArrayRegion;
    void function(JNIEnv*, jcharArray, jsize, jsize, const(jchar)*) SetCharArrayRegion;
    void function(JNIEnv*, jshortArray, jsize, jsize, const(jshort)*) SetShortArrayRegion;
    void function(JNIEnv*, jintArray, jsize, jsize, const(jint)*) SetIntArrayRegion;
    void function(JNIEnv*, jlongArray, jsize, jsize, const(jlong)*) SetLongArrayRegion;
    void function(JNIEnv*, jfloatArray, jsize, jsize, const(jfloat)*) SetFloatArrayRegion;
    void function(JNIEnv*, jdoubleArray, jsize, jsize, const(jdouble)*) SetDoubleArrayRegion;
    jint function(JNIEnv*, jclass, const(JNINativeMethod)*, jint) RegisterNatives;
    jint function(JNIEnv*, jclass) UnregisterNatives;
    jint function(JNIEnv*, jobject) MonitorEnter;
    jint function(JNIEnv*, jobject) MonitorExit;
    jint function(JNIEnv*, JavaVM**) GetJavaVM;
    void function(JNIEnv*, jstring, jsize, jsize, jchar*) GetStringRegion;
    void function(JNIEnv*, jstring, jsize, jsize, char*) GetStringUTFRegion;
    void* function(JNIEnv*, jarray, jboolean*) GetPrimitiveArrayCritical;
    void function(JNIEnv*, jarray, void*, jint) ReleasePrimitiveArrayCritical;
    const(jchar)* function(JNIEnv*, jstring, jboolean*) GetStringCritical;
    void function(JNIEnv*, jstring, const(jchar)*) ReleaseStringCritical;
    jweak function(JNIEnv*, jobject) NewWeakGlobalRef;
    void function(JNIEnv*, jweak) DeleteWeakGlobalRef;
    jboolean function(JNIEnv*) ExceptionCheck;
    jobject function(JNIEnv*, void*, jlong) NewDirectByteBuffer;
    void* function(JNIEnv*, jobject) GetDirectBufferAddress;
    jlong function(JNIEnv*, jobject) GetDirectBufferCapacity;
    jobjectRefType function(JNIEnv*, jobject) GetObjectRefType;
}

struct _JNIEnv
{
    const(JNINativeInterface)* functions;
}

struct JNIInvokeInterface
{
    void* reserved0;
    void* reserved1;
    void* reserved2;
    jint function(JavaVM*) DestroyJavaVM;
    jint function(JavaVM*, JNIEnv**, void*) AttachCurrentThread;
    jint function(JavaVM*) DetachCurrentThread;
    jint function(JavaVM*, void**, jint) GetEnv;
    jint function(JavaVM*, JNIEnv**, void*) AttachCurrentThreadAsDaemon;
}

struct _JavaVM
{
    const(JNIInvokeInterface)* functions;
}

struct JavaVMAttachArgs
{
    jint version_;
    const(char)* name;
    jobject group;
}

struct JavaVMOption
{
    const(char)* optionString;
    void* extraInfo;
}

struct JavaVMInitArgs
{
    jint version_;
    jint nOptions;
    JavaVMOption* options;
    jboolean ignoreUnrecognized;
}

struct _jfieldID;
struct _jmethodID;

union jvalue
{
    jboolean z;
    jbyte b;
    jchar c;
    jshort s;
    jint i;
    jlong j;
    jfloat f;
    jdouble d;
    jobject l;
}
