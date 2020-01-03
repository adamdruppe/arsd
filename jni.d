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

	It is also possible to call Java methods and create Java objects from D with the `@Import` uda.


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

/*
	New Java classes:

	class Foo : extends!Bar {

		mixin stuff;
	}
	mixin stuff;

	The `extends` template creates a wrapper that calls the nonvirtual
	methods, so `super()` just works.

	receiving an object should perhaps always give a subclass that is javafied;
	calls the virtuals, unless of course it is final.

	dynamic downcasts of java objects will probably never work.
*/

/+
	For interfaces:

	Java interfaces should just inherit from IJavaObject. Otherwise they
	work as normal in D. The final class is responsible for setting @Import
	and @Export on the methods and declaring they are implemented.

	Note that you can define D interfaces as well, that are not necessarily
	known to Java. If your interface uses IJavaObject though, it assumes
	that there is some kind of relationship. (mismatching this is not
	necessarily fatal, but may cause runtime exceptions or compile errors.)

	For parent classes:

	The CRTP limits this. May switch to mixin template... but right now
	the third argument to JavaClass declares the parent. It will alias this
	to a thing that returns the casted (well, realistically, reconstructed) version.
+/

/+
	FIXME: D lambdas might be automagically wrapped in a Java class... will
	need to know what parent class Java expects and which method to override.
+/

// FIXME: if user defines an interface with the appropriate RAII return values,
// it should let them do that for more efficiency
// e.g. @Import Manual!(int[]) getJavaArray();

/+
	So in Java, a lambda expression is turned into an anonymous class
	that implements the one abstract method in the required interface.

	In D, they are a different type. And with no implicit construction I
	can't convert automatically.

	But I could prolly do something like javaLambda!Interface(x => foo)
	but woof that isn't so much different than an anonymous class anymore.
+/

/+
final class CharSequence : JavaClass!("java.lang", CharSequence) {
	@Import string toString(); // this triggers a dmd segfault! whoa. FIXME dmd
}
+/

/++
	Java's String class implements its CharSequence interface. D's
	string is not a class at all, so it cannot directly do that. Instead,
	this translation of the interface has static methods to return a dummy
	class wrapping D's string.
+/
interface CharSequence : JavaInterface!("java.lang", CharSequence) {
	///
	static CharSequence fromDString(string data) {
		auto env = activeEnv;
		assert(env !is null);

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
		return dummyClass!(typeof(this))((*env).NewString(env, translated.ptr, cast(jsize) translated.length));
	}
	///
	static CharSequence fromDString(wstring data) {
		auto env = activeEnv;
		assert(env !is null);
		return dummyClass!(typeof(this))((*env).NewString(env, data.ptr, cast(jsize) data.length));
	}
}

/++
	Indicates that your interface represents an interface in Java.

	Use this on the declaration, then your other classes can implement
	it fairly normally (just with the @Import and @Export annotations added
	in the appropriate places). D will require something be filled in on the
	child classes so be sure to copy the @Import declarations there.

	---
	interface IFoo : JavaInterface!("com.example", IFoo) {
		string whatever();
	}

	final class Foo : IFoo, JavaClass!("com.example", Foo) {
		// need to tell D that the implementation exists, just in Java.
		// (This actually generates the D implementation that just forwards to the existing java method)
		@Import string whatever();
	}
	---
+/
interface JavaInterface(string javaPackage, CRTP) : IJavaObject {
	mixin JavaPackageId!(javaPackage, CRTP);
}

/// I may not keep this. But for now if you need a dummy class in D
/// to represent some object that implements this interface in Java,
/// you can use this. The dummy class assumes all interface methods are @Imported.
static T dummyClass(T)(jobject obj) {
	return new class T {
		jobject getJavaHandle() { return obj; }
	};
}


/++
	Can be used as a UDA for methods or classes where the D name
	and the Java name don't match (for example, if it happens to be
	a D keyword).

	---
	@JavaName("version")
	@Import int version_();
	---
+/
struct JavaName {
	string name;
}

private string getJavaName(alias a)() {
	string name = __traits(identifier, a);
	static foreach(attr; __traits(getAttributes, a))
		static if(is(typeof(attr) == JavaName))
			name = attr.name;
	return name;
}

/+ Java class file definitions { +/
// see: https://docs.oracle.com/javase/specs/jvms/se8/html/jvms-4.html#jvms-4.6

version(WithClassLoadSupport) {
import arsd.declarativeloader;

/// translator.
void jarToD()(string jarPath, string dPackagePrefix, string outputDirectory, JavaTranslationConfig jtc, bool delegate(string className) classFilter = null) {
	import std.zip;
	import std.file;
	import std.algorithm;

	auto zip = new ZipArchive(read(jarPath));

	foreach(name, am; zip.directory) {
		if(name.endsWith(".class")) {
			// FIXME: use classFilter
			zip.expand(am);
			rawClassBytesToD(cast(ubyte[]) am.expandedData, dPackagePrefix, outputDirectory, jtc);
			am.expandedData = null; // let the GC take it if it wants
		}
	}
}

private inout(char)[] fixupKeywordsInJavaPackageName(inout(char)[] s) {
	import std.string;
	s ~= "."; // lol i suck
	s = s.replace(".function.", ".function_.");
	s = s.replace(".ref.", ".ref_.");
	return s[0 .. $-1]; // god i am such a bad programmer
}

private inout(char)[] fixupJavaClassName(inout(char)[] s) {
	if(s == "Throwable" || s == "Object" || s == "Exception" || s == "Error" || s == "TypeInfo")
		s = cast(typeof(s)) "Java" ~ s;
	return s;
}

/// For the translator
struct JavaTranslationConfig {
	/// List the Java methods, imported to D.
	bool doImports;
	/// List the native methods, assuming they should be exported from D
	bool doExports;
	/// Put implementations inline. If false, this separates interface from impl for quicker builds with dmd -i.
	bool inlineImplementations;
	/// Treat native functions as imports, otherwise fills in as exports. Make sure doImports == true.
	bool nativesAreImports = true;
}

/// translator.
void rawClassBytesToD()(ubyte[] classBytes, string dPackagePrefix, string outputDirectory, JavaTranslationConfig jtc) {
	import std.file;
	import std.path;
	import std.algorithm;
	import std.array;
	import std.string;

	ClassFile cf;
	cf.loadFrom!ClassFile(classBytes);

	const(char)[] javaPackage;
	const(char)[] lastClassName;

	const(char)[] originalJavaPackage;
	const(char)[] originalClassName;

	const(char)[] cn = cf.className;
	auto idx = cn.lastIndexOf("/");
	if(idx != -1) {
		javaPackage = cn[0 .. idx].replace("$", "_").replace("/", ".").fixupKeywordsInJavaPackageName;
		lastClassName = cn[idx + 1 .. $];
		originalJavaPackage = cn[0 .. idx].replace("/", ".");
		originalClassName = lastClassName;
	} else {
		lastClassName = cn;
		originalJavaPackage = "";
		originalClassName = lastClassName;
	}

	lastClassName = lastClassName.replace("$", "_"); // NOTE rughs strings in this file
	lastClassName = fixupJavaClassName(lastClassName);

	auto filename = (outputDirectory.length ? (outputDirectory ~ "/") : "")
		~ (dPackagePrefix.length ? (dPackagePrefix.replace(".", "/") ~ "/") : "")
		~ javaPackage.replace(".", "/");
	mkdirRecurse(filename);
	if(filename.length)
		filename ~= "/";
	filename ~= lastClassName ~ ".d";


	string dco;

	auto thisModule = cast(string)((dPackagePrefix.length ? (dPackagePrefix ~ ".") : "") ~ javaPackage);
	if(thisModule.length && thisModule[$-1] != '.')
		thisModule ~= ".";
	thisModule ~= lastClassName;

	bool isInterface = (cf.access_flags & 0x0200) ? true : false;

	if(jtc.inlineImplementations) {
		dco = "module " ~ thisModule ~ ";\n\n";
	} else {
		dco ~= "module " ~ thisModule ~ "_d_interface;\n";
	}

	dco ~= "import arsd.jni : IJavaObjectImplementation, JavaPackageId, JavaName, IJavaObject, ImportExportImpl;\n\n";

	string[string] javaPackages;

	string dc;
	if(lastClassName != originalClassName)
		dc ~= "@JavaName(\""~originalClassName~"\")\n";

	// so overriding Java classes from D is iffy and with separate implementation
	// non final leads to linker errors anyway...
	dc ~= (isInterface ? "interface " : "final class ") ~ lastClassName ~ " : IJavaObject {\n";
	foreach(method; cf.methodsListing) {
		bool native = (method.flags & 0x0100) ? true : false;
		if(jtc.nativesAreImports) {
			if(!jtc.doImports)
				continue;
		} else {
			if(native && !jtc.doExports)
				continue;
			if(!native && !jtc.doImports)
				continue;
		}
		auto port = native ? "@Export" : "@Import";
		if(method.flags & 1) { // public

			if(method.flags & 0x0008)
				port ~= " static";

			auto name = method.name;

			// FIXME: maybe check name for other D keywords but since so many overlap with java I think we will be ok most the time for now
			if(name == "debug" || name == "delete" || name == "with" || name == "version" || name == "cast" || name == "union" || name == "align" || name == "alias" ||  name == "in" || name == "out" || name == "toString") {
				// toString is special btw in order to avoid a dmd bug
				port ~= " @JavaName(\""~name~"\")";
				name ~= "_";
			}

			// NOTE rughs strings in this file
			name = name.replace("$", "_");

			bool ctor = name == "<init>";

			auto sig = method.signature;

			auto lidx = sig.lastIndexOf(")");
			assert(lidx != -1);
			auto retJava = sig[lidx + 1 .. $];
			auto argsJava = sig[1 .. lidx];

			string ret = ctor ? "" : javaSignatureToDTypeString(retJava, javaPackages);
			string args = javaSignatureToDTypeString(argsJava, javaPackages);

			if(!jtc.inlineImplementations) {
				if(ctor && args.length == 0)
					continue; // FIXME skipping default ctor to avoid factory from trying to get to it in separate compilation
			}

			dc ~= "\t"~port~" " ~ ret ~ (ret.length ? " " : "") ~ (ctor ? "this" : name) ~ "("~args~")"~(native ? " {}" : ";")~"\n";
		}
	}

	foreach(pkg, prefix; javaPackages) {
		auto m = (dPackagePrefix.length ? (dPackagePrefix ~ ".") : "") ~ pkg;
		// keeping thisModule because of the prefix nonsense
		//if(m == thisModule)
			//continue;
		if(jtc.inlineImplementations)
			dco ~= "import " ~ prefix ~ " = " ~ m ~ ";\n";
		else
			dco ~= "import " ~ prefix ~ " = " ~ m ~ "_d_interface;\n";
	}
	if(javaPackages.keys.length)
		dco ~= "\n";
	dco ~= dc;

	if(!isInterface)
		dco ~= "\tmixin IJavaObjectImplementation!(false);\n";
	dco ~= "\tmixin JavaPackageId!(\""~originalJavaPackage.replace("/", ".")~"\", \""~originalClassName~"\");\n";

	dco ~= "}\n";

	if(jtc.inlineImplementations) {
		if(!isInterface)
			dco ~= "\nmixin ImportExportImpl!"~lastClassName~";\n";
		std.file.write(filename, dco);
	} else {
		string impl;
		impl ~= "module " ~ thisModule ~ ";\n";
		impl ~= "public import " ~ thisModule ~ "_d_interface;\n\n";
		if(!isInterface) {
			impl ~= "import arsd.jni : ImportExportImpl;\n";
			impl ~= "mixin ImportExportImpl!"~lastClassName~";\n";
		}

		std.file.write(filename, impl);
		std.file.write(filename[0 .. $-2] ~ "_d_interface.d", dco);
	}
}

string javaSignatureToDTypeString(ref const(char)[] js, ref string[string] javaPackages) {
	string all;

	while(js.length) {
		string type;
		switch(js[0]) {
			case '[':
				js = js[1 .. $];
				type = javaSignatureToDTypeString(js, javaPackages);
				type ~= "[]";
			break;
			case 'L':
				import std.string;
				auto idx = js.indexOf(";");
				type = js[1 .. idx].idup;
				js = js[idx + 1 .. $];

				if(type == "java/lang/String") {
					type = "string"; // or could be wstring...
				} else if(type == "java/lang/Object") {
					type = "IJavaObject";
				} else { 
					// NOTE rughs strings in this file
					type = type.replace("$", "_");

					string jp, cn, dm;

					idx = type.lastIndexOf("/");
					if(idx != -1) {
						jp = type[0 .. idx].replace("/", ".").fixupKeywordsInJavaPackageName;
						cn = type[idx + 1 .. $].fixupJavaClassName;
						dm = jp ~ "." ~ cn;
					} else {
						cn = type;
						dm = jp;
					}

					string prefix;
					if(auto n = dm in javaPackages) {
						prefix = *n;
					} else {
						import std.conv;
						// FIXME: this scheme sucks, would prefer something deterministic
						prefix = "import" ~ to!string(javaPackages.keys.length);

						javaPackages[dm] = prefix;
					}

					type = prefix ~ (prefix.length ? ".":"") ~ cn;
				}
			break;
			case 'V': js = js[1 .. $]; type = "void"; break;
			case 'Z': js = js[1 .. $]; type = "bool"; break;
			case 'B': js = js[1 .. $]; type = "byte"; break;
			case 'C': js = js[1 .. $]; type = "wchar"; break;
			case 'S': js = js[1 .. $]; type = "short"; break;
			case 'J': js = js[1 .. $]; type = "long"; break;
			case 'F': js = js[1 .. $]; type = "float"; break;
			case 'D': js = js[1 .. $]; type = "double"; break;
			case 'I': js = js[1 .. $]; type = "int"; break;
			default: assert(0);
		}

		if(all.length) all ~= ", ";
		all ~= type;
	}

	return all;
}

struct cp_info {

	enum CONSTANT_Class = 7; // sizeof = 2
	struct CONSTANT_Class_info {
		@BigEndian:
		ushort name_index;
	}
	enum CONSTANT_Fieldref = 9; // sizeof = 4
	struct CONSTANT_Fieldref_info {
		@BigEndian:
		ushort class_index;
		ushort name_and_type_index;
	}
	enum CONSTANT_Methodref = 10; // sizeof = 4
	struct CONSTANT_Methodref_info {
		@BigEndian:
		ushort class_index;
		ushort name_and_type_index;
	}
	enum CONSTANT_InterfaceMethodref = 11; // sizeof = 4
	struct CONSTANT_InterfaceMethodref_info {
		@BigEndian:
		ushort class_index;
		ushort name_and_type_index;
	}
	enum CONSTANT_String = 8; // sizeof = 2
	struct CONSTANT_String_info {
		@BigEndian:
		ushort string_index;
	}
	enum CONSTANT_Integer = 3; // sizeof = 4
	struct CONSTANT_Integer_info {
		@BigEndian:
		int bytes;
	}
	enum CONSTANT_Float = 4; // sizeof = 4
	struct CONSTANT_Float_info {
		@BigEndian:
		float bytes;
	}
	enum CONSTANT_Long = 5; // sizeof = 8, but eats two slots
	struct CONSTANT_Long_info {
		@BigEndian:
		long bytes;
	}
	enum CONSTANT_Double = 6; // sizeof = 8, but eats two slots
	struct CONSTANT_Double_info {
		@BigEndian:
		double bytes;
	}
	enum CONSTANT_NameAndType = 12; // sizeof = 2
	struct CONSTANT_NameAndType_info {
		@BigEndian:
		ushort name_index;
		ushort descriptor_index;
	}
	enum CONSTANT_Utf8 = 1; // sizeof = 2 + length
	struct CONSTANT_Utf8_info {
		@BigEndian:
		ushort length;
		@NumElements!length char[] bytes; // actually modified UTF-8 but meh
	}
	enum CONSTANT_MethodHandle = 15; // sizeof = 3
	struct CONSTANT_MethodHandle_info {
		@BigEndian:
		ubyte reference_kind;
		ushort reference_index;
	}
	enum CONSTANT_MethodType = 16; // sizeof = 2; descriptor index
	struct CONSTANT_MethodType_info {
		@BigEndian:
		ushort descriptor_index;
	}
	enum CONSTANT_InvokeDynamic = 18; // sizeof = 4
	struct CONSTANT_InvokeDynamic_info {
		@BigEndian:
		ushort bootstrap_method_attr_index;
		ushort name_and_type_index;
	}

	ubyte   tag;
	@Tagged!(tag)
	union Info {
		@Tag(CONSTANT_Class) CONSTANT_Class_info class_info;
		@Tag(CONSTANT_Fieldref) CONSTANT_Fieldref_info fieldref_info;
		@Tag(CONSTANT_Methodref) CONSTANT_Methodref_info methodref_info;
		@Tag(CONSTANT_InterfaceMethodref) CONSTANT_InterfaceMethodref_info interfaceMethodref_info;
		@Tag(CONSTANT_String) CONSTANT_String_info string_info;
		@Tag(CONSTANT_Integer) CONSTANT_Integer_info integer_info;
		@Tag(CONSTANT_Float) CONSTANT_Float_info float_info;
		@Tag(CONSTANT_Long) CONSTANT_Long_info long_info;
		@Tag(CONSTANT_Double) CONSTANT_Double_info double_info;
		@Tag(CONSTANT_NameAndType) CONSTANT_NameAndType_info nameAndType_info;
		@Tag(CONSTANT_Utf8) CONSTANT_Utf8_info utf8_info;
		@Tag(CONSTANT_MethodHandle) CONSTANT_MethodHandle_info methodHandle_info;
		@Tag(CONSTANT_MethodType) CONSTANT_MethodType_info methodType_info;
		@Tag(CONSTANT_InvokeDynamic) CONSTANT_InvokeDynamic_info invokeDynamic_info;
	}
	Info info;

	bool takesTwoSlots() {
		return (tag == CONSTANT_Long || tag == CONSTANT_Double);
	}
}

struct field_info {
	@BigEndian:

	enum ACC_PUBLIC = 0x0001;
	enum ACC_PRIVATE = 0x0002;
	enum ACC_PROTECTED = 0x0004;
	enum ACC_STATIC = 0x0008;
	enum ACC_FINAL = 0x0010;
	enum ACC_VOLATILE = 0x0040;
	enum ACC_TRANSIENT = 0x0080;
	enum ACC_SYNTHETIC = 0x1000;
	enum ACC_ENUM = 0x4000;

	ushort access_flags;
	ushort name_index;
	ushort descriptor_index;
	ushort attributes_count;
	@NumElements!attributes_count attribute_info[] attributes;
}

struct method_info {
	@BigEndian:
	ushort access_flags;
	ushort name_index;
	ushort descriptor_index;
	ushort attributes_count;
	@NumElements!attributes_count attribute_info[] attributes;

	enum ACC_PUBLIC = 0x0001;
	enum ACC_PRIVATE = 0x0002;
	enum ACC_PROTECTED = 0x0004;
	enum ACC_STATIC = 0x0008;
	enum ACC_FINAL = 0x0010;
	enum ACC_SYNCHRONIZED = 0x0020;
	enum ACC_BRIDGE = 0x0040;
	enum ACC_VARARGS = 0x0080;
	enum ACC_NATIVE = 0x0100;
	enum ACC_ABSTRACT = 0x0400;
	enum ACC_STRICT = 0x0800;
	enum ACC_SYNTHETIC = 0x1000;
}

struct attribute_info {
	@BigEndian:
	ushort attribute_name_index;
	uint attribute_length;
	@NumBytes!attribute_length ubyte[] info;
}

struct ClassFile {
	@BigEndian:


	enum ACC_PUBLIC     = 0x0001;
	enum ACC_FINAL      = 0x0010;
	enum ACC_SUPER      = 0x0020;
	enum ACC_INTERFACE  = 0x0200;
	enum ACC_ABSTRACT   = 0x0400;
	enum ACC_SYNTHETIC  = 0x1000;
	enum ACC_ANNOTATION = 0x2000;
	enum ACC_ENUM       = 0x4000;

	const(char)[] className() {
		return this.constant(this.constant(this.this_class).info.class_info.name_index).info.utf8_info.bytes;
	}

	const(char)[] superclassName() {
		return this.constant(this.constant(this.super_class).info.class_info.name_index).info.utf8_info.bytes;
	}

	Method[] methodsListing() {
		Method[] ms;
		foreach(met; this.methods) {
			Method m;
			m.name = this.constant(met.name_index).info.utf8_info.bytes;
			m.signature = this.constant(met.descriptor_index).info.utf8_info.bytes;
			m.flags = met.access_flags;
			ms ~= m;
		}
		return ms;
	}

	static struct Method {
		const(char)[] name;
		const(char)[] signature;
		ushort flags;
	}


	@MustBe(0xcafebabe) uint           magic;
	ushort         minor_version;
	ushort         major_version;
	ushort         constant_pool_count_;
	// the zeroth item of the constant pool is null, but not actually in the file.
	ushort constant_pool_count() { return cast(ushort)(constant_pool_count_ - 1); }
	auto constant(ushort number) {
		if(number == 0) throw new Exception("invalid");
		return constant_pool[number - 1];
	}
	@NumElements!constant_pool_count cp_info[]        constant_pool;
	ushort         access_flags;
	ushort         this_class;
	ushort         super_class;
	ushort         interfaces_count;
	@NumElements!interfaces_count ushort[]         interfaces;
	ushort         fields_count;
	@NumElements!fields_count field_info[]     fields;
	ushort         methods_count;
	@NumElements!methods_count method_info[]    methods;
	ushort         attributes_count;
	@NumElements!attributes_count attribute_info[] attributes;
}

}

/+ } end java class file definitions +/

// semi-FIXME: java.lang.CharSequence is the interface for String. We should support that just as well.
// possibly other boxed types too, like Integer. 
// FIXME: in general, handle substituting subclasses for interfaces nicely

// FIXME: solve the globalref/pin issue with the type system

// 

// FIXME: what about the parent class of the java object? Best we can probably do is an interface but perhaps it could be auto-generated by the JavaClass magic. It could take the list and just copy the @Import items.

// FIXME: interfaces? I think a Java interface should just generally be turned into a D interface, but also including the IJavaObject. Basically just write D. No @Import or @Export on this level.
// Just needs a package name somewhere....
//
// Then the D compiler forces you to declare an implementation of it, and that can be @Import.

/+
	FIXME lol if i wanted to try defining a new class in D..... you don't even need a trampoline method. Java and native methods can override each other!!!


	Perhaps could be like final class AllNew : JavaClass("package", AllNew, true) {
	 @Virtual void foo() {} // defines it here, but Java can override
	 @Override void bar() {} // overrides existing thing with new impl
	}
	and then @Import and @Export continues to work the same way.
+/

// FIXME: speaking of hacking bytecode we could prolly  read signatures out of a .class file too.
// and generate D classes :P

// see: https://developer.android.com/training/articles/perf-jni.html

// I doubt I can do anything with Java generics through this except doing it as an object array but maybe a FIXME?

//pragma(crt_constructor) // fyi
//pragma(crt_destructor)

extern(System)
export jint JNI_OnLoad(JavaVM* vm, void* reserved) {
	try {
		import core.runtime;
		// note this is OK if it is already initialized
		// since it refcounts
		Runtime.initialize();
	} catch(Throwable t) {
		return JNI_ERR;
	}

	activeJvm = vm;

	JNIEnv* env;
	if ((*vm).GetEnv(vm, cast(void**) &env, JNI_VERSION_1_6) != JNI_OK) {
		return JNI_ERR;
	}

	try {
		foreach(init; classInitializers_)
			if(init(env) != 0)
				return JNI_ERR;
		foreach(init; newClassInitializers_)
			if(init(env) != 0)
				return JNI_ERR;
	} catch(Throwable t) {
		import core.stdc.stdio;
		fprintf(stderr, "%s", (t.toString ~ "\n").ptr);
		return JNI_ERR;
	}

	return JNI_VERSION_1_6;
}
extern(System)
export void JNI_OnUnload(JavaVM* vm, void* reserved) {
	activeJvm = null;
	import core.runtime;
	try {
		// note the refcount is upped in JNI_OnLoad
		Runtime.terminate();
	} catch(Throwable t) {
		import core.stdc.stdlib;
		abort();
	}
}

__gshared JavaVM* activeJvm;

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

// FIXME figure out threads...

/++
	Creates a JVM for use when `main` is in D. Keep the returned
	struct around until you are done with it. While this struct
	is live, you can use imported Java classes and methods almost
	as if they were written in D.

	If `main` is in Java, this is not necessary and should not be
	used.


	This function will try to load the jvm with dynamic runtime
	linking. For this to succeed:

	On Windows, make sure the path to `jvm.dll` is in your `PATH`
	environment variable, or installed system wide. For example:

	$(CONSOLE
		set PATH=%PATH%;c:\users\me\program\jdk-13.0.1\bin\server
	)

	On Linux (and I think Mac), set `LD_LIBRARY_PATH` environment
	variable to include the path to `libjvm.so`.

	$(CONSOLE
		export LD_LIBRARY_PATH=/home/me/jdk-13.0.1/bin/server
		--- or maybe ---
		LD_LIBRARY_PATH=/opt/android/android-studio/jre/jre/lib/amd64/server ./myjvm
	)

	Failure to do this will throw an exception along the lines of
	"no jvm dll" in the message. That error can also be thrown if
	you have a 32 bit program but try to load a 64 bit JVM, or vice
	versa.
+/
auto createJvm()() {
	version(Windows)
		import core.sys.windows.windows;
	else
		import core.sys.posix.dlfcn;

	static struct JVM {
		ActivateJniEnv e;
		JavaVM* pvm;
		void* jvmdll;

		@disable this(this);

		~this() {
			if(pvm)
				(*pvm).DestroyJavaVM(pvm);
			activeJvm = null;

			version(Windows) {
				if(jvmdll) FreeLibrary(jvmdll);
			} else {
				if(jvmdll) dlclose(jvmdll);
			}
		}
	}

	JavaVM* pvm;
	JNIEnv* env;

	JavaVMInitArgs vm_args;
	JavaVMOption[0] options;

	//options[0].optionString = "-Djava.compiler=NONE";           /* disable JIT */
	//options[1].optionString = "-verbose:jni";                   /* print JNI-related messages */
	//options[1].optionString = `-Djava.class.path=c:\Users\me\program\jni\`; /* user classes */
	//options[2].optionString = `-Djava.library.path=c:\Users\me\program\jdk-13.0.1\lib\`;  /* set native library path */

	vm_args.version_ = JNI_VERSION_1_6;
	vm_args.options = options.ptr;
	vm_args.nOptions = cast(int) options.length;
	vm_args.ignoreUnrecognized = true;

	//import std.process;
	//environment["PATH"] = environment["PATH"] ~ `;c:\users\me\program\jdk-13.0.1\bin\server`;

	version(Windows)
		auto jvmdll = LoadLibraryW("jvm.dll"w.ptr);
	else
		auto jvmdll = dlopen("libjvm.so", RTLD_LAZY);

	if(jvmdll is null)
		throw new Exception("no jvm dll");

	version(Windows)
		auto fn = cast(typeof(&JNI_CreateJavaVM)) GetProcAddress(jvmdll, "JNI_CreateJavaVM");
	else
		auto fn = cast(typeof(&JNI_CreateJavaVM)) dlsym(jvmdll, "JNI_CreateJavaVM");

	if(fn is null)
		throw new Exception("no fun");

	auto res = fn(&pvm, cast(void**) &env, &vm_args);//, args);
	if(res != JNI_OK)
		throw new Exception("create jvm failed"); // FIXME: throw res);

	activeJvm = pvm;

	return JVM(ActivateJniEnv(env), pvm, jvmdll);
}

version(Windows)
private extern(Windows) bool SetDllDirectoryW(wstring);


@JavaName("Throwable")
final class JavaThrowable : JavaClass!("java.lang", JavaThrowable) {
	@Import string getMessage();
	@Import StackTraceElement[] getStackTrace();
}

final class StackTraceElement : JavaClass!("java.lang", StackTraceElement) {
	@Import this(string declaringClass, string methodName, string fileName, int lineNumber);
	@Import string getClassName();
	@Import string getFileName();
	@Import int getLineNumber();
	@Import string getMethodName();
	@Import bool isNativeMethod();
}

private void exceptionCheck(JNIEnv* env) {
	if((*env).ExceptionCheck(env)) {
		(*env).ExceptionDescribe(env); // prints it to stderr, not that interesting
		jthrowable thrown = (*env).ExceptionOccurred(env);
		// do I need to free thrown?
		(*env).ExceptionClear(env);

		// FIXME
		throw new Exception("Java threw");
	}
}

private enum ImportImplementationString = q{
		static if(is(typeof(return) == void)) {
			(*env).CallSTATICVoidMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
		} else static if(is(typeof(return) == string) || is(typeof(return) == wstring)) {
			// I can't just use JavaParamsToD here btw because of lifetime worries.
			// maybe i should fix it down there though because there is a lot of duplication

			auto jret = (*env).CallSTATICObjectMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);

			typeof(return) ret;

			auto len = (*env).GetStringLength(env, jret);
			auto ptr = (*env).GetStringChars(env, jret, null);
			static if(is(T == wstring)) {
				if(ptr !is null) {
					ret = ptr[0 .. len].idup;
					(*env).ReleaseStringChars(env, jret, ptr);
				}
			} else {
				import std.conv;
				if(ptr !is null) {
					ret = to!string(ptr[0 .. len]);
					(*env).ReleaseStringChars(env, jret, ptr);
				}
			}

			return ret;
		} else static if(is(typeof(return) == int)) {
			auto ret = (*env).CallSTATICIntMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) == short)) {
			auto ret = (*env).CallSTATICShortMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return ret;
		} else static if(is(typeof(return) : IJavaObject)) {
			auto ret = (*env).CallSTATICObjectMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);
			return fromExistingJavaObject!(typeof(return))(ret);
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
		} else static if(is(typeof(return) == E[], E)) {
			// Java arrays are represented as objects
			auto jarr = (*env).CallSTATICObjectMethod(env, jobj, _jmethodID, DDataToJni(env, args).args);
			exceptionCheck(env);

			auto len = (*env).GetArrayLength(env, jarr);
			static if(is(E == int)) {
				auto eles = (*env).GetIntArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseIntArrayElements(env, jarr, eles, 0);
			} else static if(is(E == bool)) {
				auto eles = (*env).GetBooleanArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseBooleanArrayElements(env, jarr, eles, 0);
			} else static if(is(E == long)) {
				auto eles = (*env).GetLongArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseLongArrayElements(env, jarr, eles, 0);
			} else static if(is(E == short)) {
				auto eles = (*env).GetShortArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseShortArrayElements(env, jarr, eles, 0);
			} else static if(is(E == wchar)) {
				auto eles = (*env).GetCharArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseCharArrayElements(env, jarr, eles, 0);
			} else static if(is(E == float)) {
				auto eles = (*env).GetFloatArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseFloatArrayElements(env, jarr, eles, 0);
			} else static if(is(E == double)) {
				auto eles = (*env).GetDoubleArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseDoubleArrayElements(env, jarr, eles, 0);
			} else static if(is(E == byte)) {
				auto eles = (*env).GetByteArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseByteArrayElements(env, jarr, eles, 0);
			} else static if(is(E == string)) {
				/*
				auto eles = (*env).GetByteArrayElements(env, jarr, null);
				auto res = eles[0 .. len];
				(*env).ReleaseByteArrayElements(env, jarr, eles, 0);
				*/
				string[] res; // FIXME
			} else static if(is(E : IJavaObject)) {
				// FIXME: implement this
				typeof(return) res = null;
			} else static if(true) {
				E[] res; // FIXME FIXME
			} else static assert(0, E.stringof ~ " not supported array element type yet"); // FIXME handle object arrays too. which would also prolly include arrays of arrays.

			return res;
		} else {
			static assert(0, "Unsupported return type for JNI: " ~ typeof(return).stringof);
				//return DDataToJni(env, __traits(getMember, dobj, __traits(identifier, method))(JavaParamsToD!(Parameters!method)(env, args).args));
		}
};

import std.string;
static immutable ImportImplementationString_static = ImportImplementationString.replace("STATIC", "Static");
static immutable ImportImplementationString_not = ImportImplementationString.replace("STATIC", "");

private mixin template JavaImportImpl(T, alias method, size_t overloadIndex) {
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
			if(!T.internalJavaClassHandle_) {
				jc = (*env).FindClass(env, (T._javaParameterString[1 .. $-1] ~ "\0").ptr);
				if(!jc)
					throw new Exception("Cannot find Java class " ~ T._javaParameterString[1 .. $-1]);
				T.internalJavaClassHandle_ = jc;
			} else {
				jc = T.internalJavaClassHandle_;
			}
			_jmethodID = (*env).GetMethodID(env, jc,
				"<init>",
				// java method string is (args)ret
				("(" ~ DTypesToJniString!(typeof(args)) ~ ")V\0").ptr
			);

			if(!_jmethodID)
				throw new Exception("Cannot find static Java method " ~ T.stringof ~ "." ~ __traits(identifier, method));
		}

		auto o = (*env).NewObject(env, T.internalJavaClassHandle_, _jmethodID, DDataToJni(env, args).args);
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
			if(!T.internalJavaClassHandle_) {
				jc = (*env).FindClass(env, (T._javaParameterString[1 .. $-1] ~ "\0").ptr);
				if(!jc)
					throw new Exception("Cannot find Java class " ~ T._javaParameterString[1 .. $-1]);
				T.internalJavaClassHandle_ = jc;
			} else {
				jc = T.internalJavaClassHandle_;
			}
			_jmethodID = (*env).GetStaticMethodID(env, jc,
				getJavaName!method.ptr,
				// java method string is (args)ret
				("(" ~ DTypesToJniString!(typeof(args)) ~ ")" ~ DTypesToJniString!(typeof(return)) ~ "\0").ptr
			);

			if(!_jmethodID)
				throw new Exception("Cannot find static Java method " ~ T.stringof ~ "." ~ __traits(identifier, method));
		}

		auto jobj = T.internalJavaClassHandle_;

		mixin(ImportImplementationString_static);
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
			// just a note: jc is an instance of java.lang.Class
			// and we could call getName on it to fetch a String to ID it
			_jmethodID = (*env).GetMethodID(env, jc,
				getJavaName!method.ptr,
				// java method string is (args)ret
				("(" ~ DTypesToJniString!(typeof(args)) ~ ")" ~ DTypesToJniString!(typeof(return)) ~ "\0").ptr
			);

			if(!_jmethodID)
				throw new Exception("Cannot find Java method " ~ T.stringof ~ "." ~ __traits(identifier, method));
		}

		mixin(ImportImplementationString_not);
	}
}

private template DTypesToJniString(Types...) {
	static if(Types.length == 0)
		enum string DTypesToJniString = "";
	else static if(Types.length == 1) {
		alias T = Types[0];

		static if(is(T == void))
			enum string DTypesToJniString = "V";
		else static if(is(T == string)) {
			enum string DTypesToJniString = "Ljava/lang/String;";
		} else static if(is(T == wstring))
			enum string DTypesToJniString = "Ljava/lang/String;";
		else static if(is(T == int))
			enum string DTypesToJniString = "I";
		else static if(is(T == bool))
			enum string DTypesToJniString = "Z";
		else static if(is(T == byte))
			enum string DTypesToJniString = "B";
		else static if(is(T == wchar))
			enum string DTypesToJniString = "C";
		else static if(is(T == short))
			enum string DTypesToJniString = "S";
		else static if(is(T == long))
			enum string DTypesToJniString = "J";
		else static if(is(T == float))
			enum string DTypesToJniString = "F";
		else static if(is(T == double))
			enum string DTypesToJniString = "D";
		else static if(is(T == size_t))
			enum string DTypesToJniString = "I"; // possible FIXME...
		else static if(is(T == IJavaObject))
			enum string DTypesToJniString = "LObject;"; // FIXME?
		else static if(is(T : IJavaObject)) // child of this but a concrete type
			enum string DTypesToJniString = T._javaParameterString;
		else static if(is(T == E[], E))
			enum string DTypesToJniString = "[" ~ DTypesToJniString!E;
		else static assert(0, "Unsupported type for JNI call " ~ T.stringof);
	} else {
		private string helper() {
			string s;
			foreach(Type; Types)
				s ~= DTypesToJniString!Type;
			return s;
		}
		enum string DTypesToJniString = helper;
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
		else static if(is(T == string[])) // prolly FIXME
			alias DTypesToJni = jobjectArray;
		else static if(is(T == E[], E)) // FIXME!!!!!!!
			alias DTypesToJni = jobjectArray;
		else static assert(0, "Unsupported type for JNI: " ~ T.stringof);
	} else {
		import std.meta;
		// FIXME: write about this later if you forget the ! on the final DTypesToJni, dmd
		// says "error: recursive template expansion". woof.
		alias DTypesToJni = AliasSeq!(DTypesToJni!(Types[0]), DTypesToJni!(Types[1 .. $]));
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
	else static if(is(T : IJavaObject)) return data is null ? null : data.getJavaHandle();


	else static if(is(T == string[])) return null; // FIXME!!!

	else static if(is(T == IJavaObject[])) return null; // FIXME!!!
	else static if(is(T == bool[])) return null; // FIXME!!!
	else static if(is(T == byte[])) return null; // FIXME!!!
	else static if(is(T == wchar[])) return null; // FIXME!!!
	else static if(is(T == short[])) return null; // FIXME!!!
	else static if(is(T == int[])) return null; // FIXME!!!
	else static if(is(T == long[])) return null; // FIXME!!!
	else static if(is(T == float[])) return null; // FIXME!!!
	else static if(is(T == double[])) return null; // FIXME!!!
	else static if(is(T == E[], E)) return null; // FIXME!!!


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
			// FIXME other types of arrays
			} else static if(is(T : IJavaObject)) {
				arg = fromExistingJavaObject!T(jarg);
			}
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

private mixin template JavaExportImpl(T, alias method, size_t overloadIndex) {
	import std.traits;
	import std.string;

	static if(__traits(identifier, method) == "__ctor")
		static assert(0, "Cannot export D constructors");

	extern(System)
	private static DTypesToJni!(ReturnType!method) privateJniImplementation(JNIEnv* env, jobject obj, DTypesToJni!(Parameters!method) args) {
		// set it up in the thread for future calls
		ActivateJniEnv thing = ActivateJniEnv(env);

		static if(__traits(isStaticFunction, method)) {
			alias dobj = T;
			jclass jc = obj;
		} else {
			// FIXME: pull the same D object again if possible... though idk
			ubyte[__traits(classInstanceSize, T)] byteBuffer;
			byteBuffer[] = (cast(const(ubyte)[]) typeid(T).initializer())[];

			// I specifically do NOT call the constructor here, since those may forward to Java and make things ugly!
			// The init value is cool as-is.

			auto dobj = cast(T) byteBuffer.ptr;
			dobj.internalJavaHandle_ = obj;
		}

		// getMember(identifer) is weird but i want to get the method on this
		// particular instance and it feels less hacky than doing the delegate

		static if(is(typeof(return) == void)) {
			try {
				__traits(getOverloads, dobj, __traits(identifier, method))[overloadIndex](JavaParamsToD!(Parameters!method)(env, args).args);
			} catch(Throwable t) {
				jniRethrow(env, t);
			}
		} else {
			try {
				return DDatumToJni(env, __traits(getOverloads, dobj, __traits(identifier, method))[overloadIndex](JavaParamsToD!(Parameters!method)(env, args).args));
			} catch(Throwable t) {
				jniRethrow(env, t);
				return typeof(return).init; // still required to return...
			}
		}
	}


	shared static this() {
		T.nativeMethodsData_ ~= JNINativeMethod(
			getJavaName!method.ptr,
			("(" ~ DTypesToJniString!(Parameters!method) ~ ")" ~ DTypesToJniString!(ReturnType!method) ~ "\0").ptr,
			&privateJniImplementation
		);
	}
}

/++
	This is really used by the [JavaClass] class below to give a base for all Java classes.
	You can use it for that too, but you really shouldn't try to implement it yourself
	(it doesn't do much anyway and the other code in here assumes the presence of IJavaObject
	on an object also means various internal static members of JavaClass are present too).
+/
interface IJavaObject {
	/// Remember the returned object is a TEMPORARY local reference!
	protected jobject getJavaHandle();

	enum Import; /// UDA to indicate you are importing the method from Java. Do NOT put a body on these methods. Only put these on implementation classes, not interfaces.
	enum Export; /// UDA to indicate you are exporting the method to Java. Put a D implementation body on these. Only put these on implementation classes, not interfaces.

}

static T fromExistingJavaObject(T)(jobject o) if(is(T : IJavaObject) && !is(T == interface)) {
	import core.memory;
	auto ptr = GC.malloc(__traits(classInstanceSize, T));
	ptr[0 .. __traits(classInstanceSize, T)] = typeid(T).initializer[];
	auto obj = cast(T) ptr;
	obj.internalJavaHandle_ = o;
	return obj;
}

static auto fromExistingJavaObject(T)(jobject o) if(is(T == interface)) {
	static class Dummy : IJavaObject {
		mixin IJavaObjectImplementation!(false);
		mixin JavaPackageId!("java.lang", "Object");
	}
	return cast(T) cast(void*) fromExistingJavaObject!Dummy(o); // FIXME this is so wrong
}


mixin template ImportExportImpl(Class) {
	static import arsd.jni;
	private static arsd.jni.JavaBridge!(Class) _javaDBridge;
}

class JavaBridge(Class) {
	static foreach(memberName; __traits(derivedMembers, Class)) {
		// validations
		static if(is(typeof(__traits(getMember, Class, memberName).offsetof)))
			static assert(1, "Data members in D on Java classes are not reliable because they cannot be consistently associated back to their corresponding Java classes through JNI without major runtime expense."); // FIXME
		else static if(memberName == "__ctor")
			static assert("JavaClasses can only be constructed by Java. Try making a constructor in Java, then make an @Import this(args); here.");

		// implementations
		static foreach(oi, overload; __traits(getOverloads, Class, memberName))
		static foreach(attr; __traits(getAttributes, overload)) {
			static if(is(attr == IJavaObject.Import))
				mixin JavaImportImpl!(Class, overload, oi);
			else static if(is(attr == IJavaObject.Export))
				mixin JavaExportImpl!(Class, overload, oi);
		}
	}
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
class JavaClass(string javaPackage, CRTP, Parent = void, bool isNewClass = false) : IJavaObject {

	static assert(__traits(isFinalClass, CRTP), "Java classes must be final on the D side and " ~ CRTP.stringof ~ " is not");

	/+
	/++
		D constructors on Java objects don't work right, so this is disabled to ensure
		you don't try it. However note that you can `@Import` constructors from Java and
		create objects in D that way.
	+/
	@disable this(){}
	+/

	mixin ImportExportImpl!CRTP;
	mixin IJavaObjectImplementation!(isNewClass);
	mixin JavaPackageId!(javaPackage, CRTP);
}

mixin template IJavaObjectImplementation(bool isNewClass) {
	static import arsd.jni;

	/*protected*/ arsd.jni.jobject internalJavaHandle_;
	/*protected*/ arsd.jni.jobject getJavaHandle() { return internalJavaHandle_; }

	__gshared static /*protected*/ /*immutable*/ arsd.jni.JNINativeMethod[] nativeMethodsData_;
	/*protected*/ static arsd.jni.jclass internalJavaClassHandle_;
	protected static int initializeInJvm_(arsd.jni.JNIEnv* env) {

		import core.stdc.stdio;

		static if(isNewClass) {
			auto aje = arsd.jni.ActivateJniEnv(env);

			import std.file;
			auto bytes = cast(byte[]) read("Test2.class");
			import std.array;
			bytes = bytes.replace(cast(byte[]) "Test2", cast(byte[]) "Test3");
			auto loader = arsd.jni.ClassLoader.getSystemClassLoader().getJavaHandle();

			internalJavaClassHandle_ = (*env).DefineClass(env, "wtf/Test3", loader, bytes.ptr, cast(int) bytes.length);
		} else {
			internalJavaClassHandle_ = (*env).FindClass(env, (_javaParameterString[1 .. $-1] ~ "\0").ptr);
		}

		if(!internalJavaClassHandle_) {
			(*env).ExceptionDescribe(env);
			(*env).ExceptionClear(env);
			fprintf(stderr, "Cannot %s Java class for %s\n", isNewClass ? "create".ptr : "find".ptr, typeof(this).stringof.ptr);
			return 1;
		}

		if(nativeMethodsData_.length)
		if((*env).RegisterNatives(env, internalJavaClassHandle_, nativeMethodsData_.ptr, cast(int) nativeMethodsData_.length)) {
			(*env).ExceptionDescribe(env);
			(*env).ExceptionClear(env);
			fprintf(stderr, ("RegisterNatives failed for " ~ typeof(this).stringof));
			return 1;
		}
		return 0;
	}
	shared static this() {
		static if(isNewClass)
			arsd.jni.newClassInitializers_ ~= &initializeInJvm_;
		else
			arsd.jni.classInitializers_ ~= &initializeInJvm_;
	}
}

mixin template JavaPackageId(string javaPackage, CRTP) {
	static import std.string;
	static if(javaPackage.length)
		public static immutable string _javaParameterString = "L" ~ std.string.replace(javaPackage, ".", "/") ~ "/" ~ getJavaName!CRTP ~ ";";
	else
		public static immutable string _javaParameterString = "L" ~ getJavaName!CRTP ~ ";";
}

mixin template JavaPackageId(string javaPackage, string javaClassName) {
	static import std.string;
	static if(javaPackage.length)
		public static immutable string _javaParameterString = "L" ~ std.string.replace(javaPackage, ".", "/") ~ "/" ~ javaClassName ~ ";";
	else
		public static immutable string _javaParameterString = "L" ~ javaClassName ~ ";";
}



__gshared /* immutable */ int function(JNIEnv* env)[] classInitializers_;
__gshared /* immutable */ int function(JNIEnv* env)[] newClassInitializers_;

final class ClassLoader : JavaClass!("java.lang", ClassLoader) {
	@Import static ClassLoader getSystemClassLoader();
}














// Mechanically translated <jni.h> header below.
// You can use it yourself if you need low level access to JNI.



import core.stdc.stdarg;

//version (Android):
extern (System):
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
enum JNI_VERSION_1_8 = 0x00010008;

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

jint JNI_GetDefaultJavaVMInitArgs(void *args);
jint JNI_CreateJavaVM(JavaVM **pvm, void **penv, void *args);
jint JNI_GetCreatedJavaVMs(JavaVM **, jsize, jsize *);

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

/*
	Copyright 2019-2020, Adam D. Ruppe.
	Boost license. or whatever.
	Most work done in December 2019.
*/
