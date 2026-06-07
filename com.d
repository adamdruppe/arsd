/++
	Code for COM interop on Windows. You can use it to consume
	COM objects (including several objects from .net assemblies)
	and to create COM servers with a natural D interface.

	This code is not well tested, don't rely on it yet. But even
	in its incomplete state it might help in some cases. Strings
	and integers work pretty ok.

	You can use it to interoperate with Word and Excel:

	---
	void wordmain() {
		// gets the name of the open Word instance, if there is one
		// getComObject gets the currently registered open one, and the
		// "false" here means do not create a new one if none exists
		// (try changing it to true to open a hidden Word)
		auto wrd = getComObject("Word.Application", false);
		writeln(wrd.ActiveDocument.Name.getD!string);
	}

	void excelmain() {
		// create anew Excel instance and put some stuff in it
		auto xlApp = createComObject("Excel.Application");
		try {
			xlApp.Visible() = 1;
			xlApp.Workbooks.Add()();

			xlApp.ActiveSheet.Cells()(1, 1).Value() = "D can do it";
			xlApp.ActiveWorkbook.ActiveSheet.Cells()(1,2).Value() = "but come on";

			writeln("success");
			readln();

			xlApp.ActiveWorkbook.Close()(0);
		} catch(Exception e) {
			writeln(e.toString);
			writeln("waiting"); // let the user see before it closes
			readln();
		}
		xlApp.Quit()();
	}
	---

	The extra parenthesis there are to work around D's broken `@property` attribute, you need one at the end before a = or call operator.

	Or you can work with your own custom code:

	```c#
	namespace Cool {
		public class Test {

			static void Main() {
				System.Console.WriteLine("hello!");
			}

			public int test() { return 4; }
			public int test2(int a) { return 10 + a; }
			public string hi(string s) { return "hello, " + s; }
		}
	}
	```

	Compile it into a library like normal, then `regasm` it to register the
	assembly... then the following D code will work:

	---
	import arsd.com;

	interface CsharpTest {
		int test();
		int test2(int a);
		string hi(string s);
	}

	void main() {
		auto obj = createComObject!CsharpTest("Cool.Test"); // early-bind dynamic version
		//auto obj = createComObject("Cool.Test"); // late-bind dynamic version

		import std.stdio;
		writeln(obj.test()); // early-bind already knows the signature
		writeln(obj.test2(12));
		writeln(obj.hi("D"));
		//writeln(obj.test!int()); // late-bind needs help
		//writeln(obj.opDispatch!("test", int)());
	}
	---

	I'll show a COM server example later. It is cool to call D objects
	from JScript and such.
+/
module arsd.com;

import arsd.core;

version(Windows):

// for arrays to/from IDispatch use SAFEARRAY
// see https://stackoverflow.com/questions/295067/passing-an-array-using-com

// for exceptions
// see: https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-erref/705fb797-2175-4a90-b5a3-3918024b10b8
// see: https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-erref/0c0bcf55-277e-4120-b5dc-f6115fc8dc38

/+
	see: program\cs\comtest.d on the laptop.

	as administrator: from program\cs
	c:\Windows\Microsoft.NEt\Framework64\v4.0.30319\regasm.exe /regfile /codebase test.dll

	note: use the 64 bit register for 64 bit programs (Framework64)
	use 32 for 32 bit program (\Framework\)

	sn -k key.snk
	program\cs\makefile

	test.js in there shows it form wsh too

	i can make it work through IDispatch easily enough, though
	ideally you'd have a real interface, that requires cooperation
	that the idispatch doesn't thanks to .net doing it for us.

	passing other objects should work too btw thanks to idispatch
	in the variants... not sure about arrays tho

	and then fully dynamic can be done with opDispatch for teh lulz.
+/

/+
	createComObject returns the wrapped one
		wrapping can go dynamic if it is wrapping IDispatch
		some other IUnknown gets minimal wrapping (Translate formats)
		all wrappers can return lower level stuff on demand. like LL!string maybe is actually an RAII BSTR.

		i also want variant to jsvar and stuff like that.
	createRawComObject returns the IUnknown raw one
+/

public import core.sys.windows.windows;
public import core.sys.windows.com;
public import core.sys.windows.wtypes;
public import core.sys.windows.oaidl;

import core.stdc.string;
import core.atomic;

pragma(lib, "advapi32");
pragma(lib, "uuid");
pragma(lib, "ole32");
pragma(lib, "oleaut32");
pragma(lib, "user32");

/* Attributes that help with automation */

///
static immutable struct ComGuid {
	///
	this(GUID g) { this.guid = g; }
	///
	this(string g) { guid = stringToGuid(g); }
	GUID guid;
}

GUID stringToGuid(string g) {
	return GUID.init; // FIXME
}

bool hasGuidAttribute(T)() {
	bool has = false;
	foreach(attr; __traits(getAttributes, T))
		static if(is(typeof(attr) == ComGuid))
			has = true;
	return has;
}

template getGuidAttribute(T) {
	static ComGuid helper() {
		foreach(attr; __traits(getAttributes, T))
			static if(is(typeof(attr) == ComGuid))
				return attr;
		assert(0);
	}
	__gshared static immutable getGuidAttribute = helper();
}


/* COM CLIENT CODE */

__gshared int coInitializeCalled;
shared static ~this() {
	CoFreeUnusedLibraries();
	if(coInitializeCalled) {
		CoUninitialize();
		coInitializeCalled--;
	}
}

///
void initializeClassicCom(bool multiThreaded = false) {
	if(coInitializeCalled)
		return;

	ComCheck(CoInitializeEx(null, multiThreaded ? COINIT_MULTITHREADED : COINIT_APARTMENTTHREADED),
		"COM initialization failed");

	coInitializeCalled++;
}

///
bool ComCheck(HRESULT hr, string desc) {
	if(FAILED(hr))
		throw new ComException(hr, desc);
	return true;
}

///
class ComException : WindowsApiException {
	this(HRESULT hr, string desc, string file = __FILE__, size_t line = __LINE__) {
		this.hr = hr;
		super(desc, cast(DWORD) hr, null, file, line);
	}

	HRESULT hr;
}

template Dify(T) {
	static if(is(T : IUnknown)) {
		// FIXME
		static assert(0);
	} else {
		alias Dify = T;
	}
}

struct ComResult {
	VARIANT result;

	ComProperty opDispatch(string memberName)() {
		auto newComObject = (result.vt == 9) ? result.pdispVal : null;

		DISPID dispid;

		if(newComObject !is null) {
			import std.conv;
			wchar*[1] names = [(to!wstring(memberName) ~ "\0"w).dup.ptr];
			ComCheck(newComObject.GetIDsOfNames(&GUID_NULL, names.ptr, 1, LOCALE_SYSTEM_DEFAULT, &dispid), "Look up name " ~ memberName);
		} else throw new Exception("cannot get member of non-object");

		return ComProperty(newComObject, dispid, memberName);
	}

	T getD(T)() {
		return getFromVariant!T(result);
	}

}

struct ComProperty {
	IDispatch innerComObject_;
	DISPID dispid;
	string name;

	this(IDispatch a, DISPID c, string name) {
		this.innerComObject_ = a;
		this.dispid = c;
		this.name = name;
	}

	T getD(T)() {
		auto res = _fetchProperty();
		return res.getD!T;
	}

	ComResult _fetchProperty() {
		DISPPARAMS disp_params;

		VARIANT result;
		EXCEPINFO einfo;
		uint argError;

		auto hr =innerComObject_.Invoke(
			dispid,
			&GUID_NULL, LOCALE_SYSTEM_DEFAULT, // whatever
			DISPATCH_PROPERTYGET,
			&disp_params,
			&result,
			&einfo, // exception info
			&argError // arg error
		);//, "Invoke");

		if (Exception e = exceptionFromComResult(hr, einfo, argError, "Property get")) {
			throw e;
		}

		return ComResult(result);
	}

	ComProperty opDispatch(string memberName)() {
		return _fetchProperty().opDispatch!memberName;
	}

	T opAssign(T)(T rhs) {
		DISPPARAMS disp_params;

		VARIANT[1] vargs;
		vargs[0] = toComVariant(rhs);
		disp_params.rgvarg = vargs.ptr;
		disp_params.cNamedArgs = 1;
		disp_params.cArgs = 1;
		DISPID dispidNamed = DISPID_PROPERTYPUT;
		disp_params.rgdispidNamedArgs = &dispidNamed;

		VARIANT result;
		EXCEPINFO einfo;
		uint argError;

		auto hr =innerComObject_.Invoke(
			dispid,
			&GUID_NULL, LOCALE_SYSTEM_DEFAULT, // whatever
			DISPATCH_PROPERTYPUT,
			&disp_params,
			&result,
			&einfo, // exception info
			&argError // arg error
		);//, "Invoke");

		VariantClear(&vargs[0]);

		if (Exception e = exceptionFromComResult(hr, einfo, argError, "Property put")) {
			throw e;
		}

		return rhs;
	}

	ComResult opCall(Args...)(Args args) {
		return callWithNamedArgs!Args(null, args);
	}

	/// Call with named arguments
	///
	/// Note that all positional arguments are always followed by all named arguments.
	///
	/// So to call: `Com.f(10, 20, A: 30, B: 40)`, invoke this function as follows:
	/// ---
	/// Com.f().callWithNamedArgs(["A", "B"], 10, 20, 30, 40);
	/// ---
	/// Argument names are case-insensitive
	ComResult callWithNamedArgs(Args...)(string[] argNames, Args args) {
		DISPPARAMS disp_params;

		static if (args.length) {
			VARIANT[args.length] vargs;
			foreach(idx, arg; args) {
				// lol it is put in backwards way to explain MSFT
				vargs[$ - 1 - idx] = toComVariant(arg);
			}

			disp_params.rgvarg = vargs.ptr;
			disp_params.cArgs = cast(int) args.length;

			if (argNames.length > 0) {
				wchar*[Args.length + 1] namesW;
				// GetIDsOfNames wants Method name at index 0 followed by parameter names.
				// Order of passing named args is up to us, but it's standard to also put them backwards,
				// and we've already done so with values in `vargs`, so we continue this trend
				// with dispatch IDs of names
				import std.conv: to;
				namesW[0] = (to!wstring(this.name) ~ "\0"w).dup.ptr;
				foreach (i; 0 .. argNames.length) {
					namesW[i + 1] = (to!wstring(argNames[$ - 1 - i]) ~ "\0"w).dup.ptr;
				}
				DISPID[Args.length + 1] dispIds;
				innerComObject_.GetIDsOfNames(
					&GUID_NULL, namesW.ptr, cast(uint) (1 + argNames.length), LOCALE_SYSTEM_DEFAULT, dispIds.ptr
				).ComCheck("Unknown parameter name");

				// Strip Member name at index 0
				disp_params.cNamedArgs = cast(uint) argNames.length;
				disp_params.rgdispidNamedArgs = &dispIds[1];
			}
		}

		VARIANT result;
		EXCEPINFO einfo;
		uint argError;

		//ComCheck(innerComObject_.Invoke(
		auto hr =innerComObject_.Invoke(
			dispid,
			&GUID_NULL, LOCALE_SYSTEM_DEFAULT, // whatever
			DISPATCH_METHOD,// PROPERTYPUT, //DISPATCH_METHOD,
			&disp_params,
			&result,
			&einfo, // exception info
			&argError // arg error
		);//, "Invoke");

		if(hr == 0x80020003) { // method not found
			// FIXME idk how to tell the difference between a method and a property from the outside..
			hr =innerComObject_.Invoke(
				dispid,
				&GUID_NULL, LOCALE_SYSTEM_DEFAULT, // whatever
				DISPATCH_PROPERTYGET,// PROPERTYPUT, //DISPATCH_METHOD,
				&disp_params,
				&result,
				&einfo, // exception info
				&argError // arg error
			);//, "Invoke");
		}

		static if(args.length) {
			foreach (ref v; vargs[]) {
				VariantClear(&v);
			}
		}

		if (Exception e = exceptionFromComResult(hr, einfo, argError, "Call")) {
			throw e;
		}

		return ComResult(result);
	}
}

/// Returns: `null` on success, a D Exception created from `einfo` and `argError`
/// in case the COM return `hr` signals failure
private Exception exceptionFromComResult(HRESULT hr, ref EXCEPINFO einfo, uint argError, string action)
{
	import std.conv;
	if(FAILED(hr)) {
		if(hr == DISP_E_EXCEPTION) {
			auto code = einfo.scode ? einfo.scode : einfo.wCode;
			string source;
			string description;
			if(einfo.bstrSource) {
				// this is really a wchar[] but it needs to be freed so....
				source = einfo.bstrSource[0 .. SysStringLen(einfo.bstrSource)].to!string;
				SysFreeString(einfo.bstrSource);
			}
			if(einfo.bstrDescription) {
				description = einfo.bstrDescription[0 .. SysStringLen(einfo.bstrDescription)].to!string;
				SysFreeString(einfo.bstrDescription);
			}
			if(einfo.bstrHelpFile) {
				// FIXME: we could prolly use this too
				SysFreeString(einfo.bstrHelpFile);
				// and dwHelpContext
			}

			throw new ComException(code, description ~ " (from com source " ~ source ~ ")");

		} else {
			throw new ComException(hr, action ~ " failed " ~ to!string(argError));
		}
	}
	return null;
}

///
struct ComClient(DVersion, ComVersion = IDispatch) {
	ComVersion innerComObject_;
	this(ComVersion t) {
		this.innerComObject_ = t;
	}
	this(this) {
		if(innerComObject_)
			innerComObject_.AddRef();
	}
	~this() {
		if(innerComObject_)
			innerComObject_.Release();
	}

	// note that COM doesn't really support overloading so this
	// don't even attempt it. C# will export as name_N where N
	// is the index of the overload (except for 1) but...

	static if(is(DVersion == Dynamic))
	ComProperty opDispatch(string memberName)() {
		// FIXME: this can be cached and reused, even done ahead of time
		DISPID dispid;

		import std.conv;
		wchar*[1] names = [(to!wstring(memberName) ~ "\0"w).dup.ptr];
		ComCheck(innerComObject_.GetIDsOfNames(&GUID_NULL, names.ptr, 1, LOCALE_SYSTEM_DEFAULT, &dispid), "Look up name");

		return ComProperty(this.innerComObject_, dispid, memberName);
	}

	/+
	static if(is(DVersion == Dynamic))
	template opDispatch(string name) {
		template opDispatch(Ret = void) {
			Ret opDispatch(Args...)(Args args) {
				return dispatchMethodImpl!(name, Ret)(args);
			}
		}
	}
	+/

	static if(is(ComVersion == IDispatch))
	template dispatchMethodImpl(string memberName, Ret = void) {
		Ret dispatchMethodImpl(Args...)(Args args) {
			static if(is(ComVersion == IDispatch)) {

				// FIXME: this can be cached and reused, even done ahead of time
				DISPID dispid;

				import std.conv;
				wchar*[1] names = [(to!wstring(memberName) ~ "\0"w).dup.ptr];
				ComCheck(innerComObject_.GetIDsOfNames(&GUID_NULL, names.ptr, 1, LOCALE_SYSTEM_DEFAULT, &dispid), "Look up name");

				DISPPARAMS disp_params;

				static if(args.length) {
					VARIANT[args.length] vargs;
					foreach(idx, arg; args) {
						// lol it is put in backwards way to explain MSFT
						vargs[$ - 1 - idx] = toComVariant(arg);
					}

					disp_params.rgvarg = vargs.ptr;
					disp_params.cArgs = cast(int) args.length;
				}

				VARIANT result;
				EXCEPINFO einfo;
				uint argError;

				//ComCheck(innerComObject_.Invoke(
				auto hr =innerComObject_.Invoke(
					dispid,
					&GUID_NULL, LOCALE_SYSTEM_DEFAULT, // whatever
					DISPATCH_METHOD,// PROPERTYPUT, //DISPATCH_METHOD,
					&disp_params,
					&result,
					&einfo, // exception info
					&argError // arg error
				);//, "Invoke");

				static if (args.length) {
					foreach (ref v; vargs[]) {
						VariantClear(&v);
					}
				}

				if (Exception e = exceptionFromComResult(hr, einfo, argError, "Call")) {
					throw e;
				}

				return getFromVariant!(typeof(return))(result);
			} else {
				static assert(0); // FIXME
			}

		}
	}

	// so note that if I were to just make this a class, it'd inherit
	// attributes from the D interface... but I want the RAII struct...
	// could do a class with a wrapper and alias this though. but meh.
	import std.traits;
	static foreach(memberName; __traits(allMembers, DVersion)) {
	static foreach(idx, overload; __traits(getOverloads, DVersion, memberName)) {
		mixin(q{ReturnType!overload }~memberName~q{(Parameters!overload args) {
			return dispatchMethodImpl!(memberName, typeof(return))(args);
		}
		});
	}
	}
}

VARIANT toComVariant(T)(T arg) {
	VARIANT ret;
	static if(is(T : VARIANT)) {
		ret = arg;
	} else static if(is(T : ComClient!(Dynamic, IDispatch))) {
		ret.vt = VARENUM.VT_DISPATCH;
		ret.pdispVal = arg.innerComObject_;
	} else static if(is(T : ComProperty)) {
		ret = arg._fetchProperty();
	} else static if (is(T : ComResult)) {
		ret = arg.result;
	} else static if(is(T : IDispatch)) {
		ret.vt = VARENUM.VT_DISPATCH;
		ret.pdispVal = arg;
	} else static if(is(T : int)) {
		ret.vt = VARENUM.VT_I4;
		ret.intVal = arg;
	} else static if(is(T : long)) {
		ret.vt = VARENUM.VT_I8;
		ret.llVal = arg;
	} else static if(is(T : double)) {
		ret.vt = VARENUM.VT_R8;
		ret.dblVal = arg;
	} else static if(is(T : const(char)[])) {
		ret.vt = VARENUM.VT_BSTR;
		import std.utf;
		ret.bstrVal = SysAllocString(toUTFz!(wchar*)(arg));
	} else static if (is(T : E[], E)) {
		auto sizes = ndArrayDimensions!uint(arg);
		SAFEARRAYBOUND[sizes.length] saBound;
		foreach (i; 0 .. sizes.length) {
			saBound[i].lLbound = 0;
			saBound[i].cElements = sizes[i];
		}
		enum vt = vtFromDType!E;
		SAFEARRAY* sa = SafeArrayCreate(vt, saBound.length, saBound.ptr);
		int[sizes.length] indices;
		void fill(int dim, T)(T val) {
			static if (dim >= indices.length) {
				static if (vt == VARENUM.VT_BSTR) {
					import std.utf;
					SafeArrayPutElement(sa, indices.ptr, SysAllocString(toUTFz!(wchar*)(val)));
				} else {
					SafeArrayPutElement(sa, indices.ptr, &val);
				}
				return;
			} else {
				foreach (i; 0 .. val.length) {
					indices[dim] = cast(int) i;
					fill!(dim + 1)(val[i]);
				}
			}
		}
		fill!(0)(arg);
		ret.vt = VARENUM.VT_ARRAY | vt;
		ret.parray = sa;
	} else static assert(0, "Unsupported type (yet) " ~ T.stringof);

	return ret;
}

/// Returns: for any multi-dimensional array, a static array of `length` values for each dimension.
/// Strings are not considered arrays because they have the VT_BSTR type instead of VT_ARRAY
private auto ndArrayDimensions(I, T)(T arg) {
	static if (!is(T : const(char)[]) && (is(T == E[], E) || is(T == E[n], E, int n))) {
        alias A = typeof(ndArrayDimensions!I(arg[0]));
        I[1 + A.length] res = 0;
        if (arg.length != 0) {
            auto s = ndArrayDimensions!I(arg[0]);
            res[1 .. $] = s[];
        }
        res[0] = cast(I) arg.length;
		return res;
	} else {
		I[0] res;
		return res;
	}
}

unittest {
	auto x = new float[][][](2, 3, 5);
	assert(ndArrayDimensions!uint(x) == [2, 3, 5]);
    short[4][][5] y;
    y[0].length = 3;
    assert(ndArrayDimensions!uint(y) == [5, 3, 4]);
}

/// Get VARENUM tag for basic type T
private template vtFromDType(T) {
	static if (is(T == short)) {
		enum vtFromDType = VARENUM.VT_I2;
	} else static if(is(T == int)) {
		enum vtFromDType = VARENUM.VT_I4;
	} else static if (is(T == float)) {
		enum vtFromDType = VARENUM.VT_R4;
	} else static if (is(T == double)) {
		enum vtFromDType = VARENUM.VT_R8;
	} else static if(is(T == bool)) {
		enum vtFromDType = VARENUM.VT_BOOL;
	} else static if (is(T : const(char)[])) {
		enum vtFromDType = VARENUM.VT_BSTR;
	} else static if (is(T == E[], E)) {
		enum vtFromDType = vtFromDType!E;
	} else {
		static assert(0, "don't know VARENUM for " ~ T.stringof);
	}
}

/*
	If you want to do self-registration:

	if(dll_regserver("filename.dll", 1) == 0) {
		scope(exit)
			dll_regserver("filename.dll", 0);
		// use it
	}
*/

// note that HKEY_CLASSES_ROOT\pretty name\CLSID has the guid

// note: https://en.wikipedia.org/wiki/Component_Object_Model#Registration-free_COM

GUID guidForClassName(wstring c) {
	GUID id;
	ComCheck(CLSIDFromProgID((c ~ "\0").ptr, &id), "Name lookup failed");
	return id;
}

interface Dynamic {}

/++
	Create a COM object. The passed interface should be a child of IUnknown and from core.sys.windows or have a ComGuid UDA, or be something else entirely and you get dynamic binding.

	The string version can take a GUID in the form of {xxxxx-xx-xxxx-xxxxxxxx} or a name it looks up in the registry.
	The overload takes a GUID object (e.g. CLSID_XXXX from the Windows headers or one you write in yourself).

	It will return a wrapper to the COM object that conforms to a D translation of the COM interface with automatic refcounting.
+/
// FIXME: or you can request a fully dynamic version via opDispatch. That will have to be a thing
auto createComObject(T = Dynamic)(wstring c) {
	return createComObject!(T)(guidForClassName(c));
}
/// ditto
auto createComObject(T = Dynamic)(GUID classId) {
	initializeClassicCom();

	static if(is(T : IUnknown) && hasGuidAttribute!T) {
		enum useIDispatch = false;
		auto iid = getGuidAttribute!(T).guid;
	// FIXME the below condition is just woof
	} else static if(is(T : IUnknown) && is(typeof(mixin("core.sys.windows.IID_" ~ T.stringof)))) {
		enum useIDispatch = false;
		auto iid = mixin("core.sys.windows.IID_" ~ T.stringof);
	} else {
		enum useIDispatch = true;
		auto iid = IID_IDispatch;
	}

	static if(useIDispatch) {
		IDispatch obj;
	} else {
		static assert(is(T : IUnknown));
		T obj;
	}

	ComCheck(CoCreateInstance(&classId, null, CLSCTX_INPROC_SERVER/*|CLSCTX_INPROC_HANDLER*/|CLSCTX_LOCAL_SERVER, &iid, cast(void**) &obj), "Failed to create object");
	// FIXME: if this fails we might retry with inproc_handler.

	return ComClient!(Dify!T, typeof(obj))(obj);
}

/// ditto
auto getComObject(T = Dynamic)(wstring c, bool tryCreateIfGetFails = true) {
	initializeClassicCom();

	auto guid = guidForClassName(c);

	auto get() {
		auto iid = IID_IDispatch;
		IUnknown obj;
		ComCheck(GetActiveObject(&guid, null, &obj), "Get Object"); // code 0x800401e3 is operation unavailable if it isn't there i think
		if(obj is null)
			throw new Exception("null");

		IDispatch disp;
		ComCheck(obj.QueryInterface(&iid, cast(void**) &disp), "QueryInterface");

		auto client = ComClient!(Dify!T, typeof(disp))(disp);
		disp.AddRef();
		return client;
	}

	if(tryCreateIfGetFails)
		try
			return get();
		catch(Exception e)
			return createComObject(guid);
	else
		return get();
}


// FIXME: add one to get by ProgID rather than always guid
// FIXME: add a dynamic com object that uses IDispatch

/* COM SERVER CODE */

T getFromVariant(T)(VARIANT arg) {
	import std.traits;
	import std.conv;
	static if(is(T == void)) {
		return;
	} else static if(is(T == int)) {
		if(arg.vt == VARENUM.VT_I4)
			return arg.intVal;
	} else static if (is(T == float)) {
		if(arg.vt == VARENUM.VT_R4)
			return arg.fltVal;
	} else static if (is(T == double)) {
		if(arg.vt == VARENUM.VT_R8)
			return arg.dblVal;
	} else static if(is(T == bool)) {
		if(arg.vt == VARENUM.VT_BOOL)
			return arg.boolVal ? true : false;
	} else static if(is(T == string)) {
		if(arg.vt == VARENUM.VT_BSTR) {
			auto str = arg.bstrVal;
			scope(exit) SysFreeString(str);
			return to!string(str[0 .. SysStringLen(str)]);
		}
	} else static if(is(T == IDispatch)) {
		if(arg.vt == VARENUM.VT_DISPATCH)
			return arg.pdispVal;
	} else static if(is(T : IUnknown)) {
		// if(arg.vt == 13)
		static assert(0);
	} else static if(is(T == ComClient!(D, I), D, I)) {
		if(arg.vt == VARENUM.VT_DISPATCH)
			return ComClient!(D, I)(arg.pdispVal);
	} else static if(is(T == E[], E)) {
		if(arg.vt & 0x2000) {
			auto elevt = arg.vt & ~0x2000;
			auto a = arg.parray;
			scope(exit) SafeArrayDestroy(a);

			auto bounds = a.rgsabound.ptr[0 .. a.cDims];

			auto hr = SafeArrayLock(a);
			if(SUCCEEDED(hr)) {
				scope(exit) SafeArrayUnlock(a);

				// BTW this is where things get interesting with the
				// mid-level wrapper. it can avoid these copies

				// maybe i should check bounds.lLbound too.....

				static if(is(E == int)) {
					if(elevt == 3) {
						assert(a.cbElements == E.sizeof);
						return (cast(E*)a.pvData)[0 .. bounds[0].cElements].dup;
					}
				} else static if(is(E == string)) {
					if(elevt == 8) {
						//assert(a.cbElements == E.sizeof);
						//return (cast(E*)a.pvData)[0 .. bounds[0].cElements].dup;

						string[] ret;
						foreach(item; (cast(BSTR*) a.pvData)[0 .. bounds[0].cElements]) {
							auto str = item;
							scope(exit) SysFreeString(str);
							ret ~= to!string(str[0 .. SysStringLen(str)]);
						}
						return ret;
					}
				}

			}
		}
	}
	throw new Exception("Type mismatch, needed "~ T.stringof ~" got " ~ to!string(cast(VARENUM) arg.vt));
	assert(0);
}

/// Mixin to a low-level COM implementation class
mixin template IDispatchImpl() {
	override HRESULT GetIDsOfNames( REFIID riid, OLECHAR ** rgszNames, UINT cNames, LCID lcid, DISPID * rgDispId) {
		if(cNames == 0)
			return DISP_E_UNKNOWNNAME;

		char[256] buffer;
		auto want = oleCharsToString(buffer, rgszNames[0]);
		foreach(idx, member; __traits(allMembers, typeof(this))) {
			if(member == want) {
				rgDispId[0] = idx + 1;
				return S_OK;
			}
		}
		return DISP_E_UNKNOWNNAME;
	}

	override HRESULT GetTypeInfoCount(UINT* i) { *i = 0; return S_OK; }
	override HRESULT GetTypeInfo(UINT i, LCID l, LPTYPEINFO* p) { *p = null; return S_OK; }
	override HRESULT Invoke(DISPID dispIdMember, REFIID reserved, LCID locale, WORD wFlags, DISPPARAMS* params, VARIANT* result, EXCEPINFO* except, UINT* argErr) {
	// wFlags == 1 function call
	// wFlags == 2 property getter
	// wFlags == 4 property setter
		foreach(idx, member; __traits(allMembers, typeof(this))) {
			if(idx + 1 == dispIdMember) {
			static if(is(typeof(__traits(getMember, this, member)) == function))
				try {
					import std.traits;
					ParameterTypeTuple!(__traits(getMember, this, member)) args;
					alias argsStc = ParameterStorageClassTuple!(__traits(getMember, this, member));

					static if(argsStc.length >= 1 && argsStc[0] == ParameterStorageClass.out_) {
						// the return value is often the first out param
						typeof(args[0]) returnedValue;

						if(params !is null) {
							assert(params.cNamedArgs == 0); // FIXME

							if(params.cArgs < args.length - 1)
								return DISP_E_BADPARAMCOUNT;

							foreach(aidx, arg; args[1 .. $])
								args[1 + aidx] = getFromVariant!(typeof(arg))(params.rgvarg[aidx]);
						}

						static if(is(ReturnType!(__traits(getMember, this, member)) == void)) {
							__traits(getMember, this, member)(returnedValue, args[1 .. $]);
						} else {
							auto returned = __traits(getMember, this, member)(returnedValue, args[1 .. $]);
							// FIXME: it probably returns HRESULT so we should forward that or something.
						}

						if(result !is null) {
							static if(argsStc.length >= 1 && argsStc[0] == ParameterStorageClass.out_) {
								result.vt = 3; // int
								result.intVal = returnedValue;
							}
						}
					} else {

						if(params !is null) {
							assert(params.cNamedArgs == 0); // FIXME
							if(params.cArgs < args.length)
								return DISP_E_BADPARAMCOUNT;
							foreach(aidx, arg; args)
								args[aidx] = getFromVariant!(typeof(arg))(params.rgvarg[aidx]);
						}

						// no return value of note (just HRESULT at most)
						static if(is(ReturnType!(__traits(getMember, this, member)) == void)) {
							__traits(getMember, this, member)(args);
						} else {
							auto returned = __traits(getMember, this, member)(args);
							// FIXME: it probably returns HRESULT so we should forward that or something.
						}
					}

					return S_OK;
				} catch(Throwable e) {
					// FIXME: fill in the exception info
					if(except !is null) {
						except.scode = 1;
						import std.utf;
						except.bstrDescription = SysAllocString(toUTFz!(wchar*)(e.toString()));
						except.bstrSource = SysAllocString("amazing"w.ptr);
					}
					return DISP_E_EXCEPTION;
				}
			}
		}

		return DISP_E_MEMBERNOTFOUND;
	}
}

/// Mixin to a low-level COM implementation class
mixin template ComObjectImpl() {
protected:
	IUnknown m_pUnkOuter;       // Controlling unknown
	PFNDESTROYED m_pfnDestroy;          // To call on closure

    /*
     *  pUnkOuter       LPUNKNOWN of a controlling unknown.
     *  pfnDestroy      PFNDESTROYED to call when an object
     *                  is destroyed.
     */
	public this(IUnknown pUnkOuter, PFNDESTROYED pfnDestroy) {
		m_pUnkOuter  = pUnkOuter;
		m_pfnDestroy = pfnDestroy;
	}

	~this() {
		//MessageBoxA(null, "CHello.~this()", null, MB_OK);
	}

	// Note: you can implement your own Init along with this mixin template and your function will automatically override this one
    /*
     *  Performs any intialization of a CHello that's prone to failure
     *  that we also use internally before exposing the object outside.
     * Return Value:
     *  BOOL            true if the function is successful,
     *                  false otherwise.
     */
	public BOOL Init() {
		//MessageBoxA(null, "CHello.Init()", null, MB_OK);
		return true;
	}


	public
	override HRESULT QueryInterface(const (IID)*riid, LPVOID *ppv) {
		// wchar[200] lol; auto got = StringFromGUID2(riid, lol.ptr, lol.length); import std.conv;
		//MessageBoxA(null, toStringz("CHello.QueryInterface(g: "~to!string(lol[0 .. got])~")"), null, MB_OK);

		assert(ppv !is null);
		*ppv = null;

		import std.traits;
		foreach(iface; InterfacesTuple!(typeof(this))) {
			static if(hasGuidAttribute!iface()) {
				auto guid = getGuidAttribute!iface;
				if(*riid == guid.guid) {
					*ppv = cast(void*) cast(iface) this;
					break;
				}
			} else static if(is(iface == IUnknown)) {
				if (IID_IUnknown == *riid) {
					*ppv = cast(void*) cast(IUnknown) this;
					break;
				}
			} else static if(is(iface == IDispatch)) {
				if (IID_IDispatch == *riid) {
					*ppv = cast(void*) cast(IDispatch) this;
					break;
				}
			}
		}

		if(*ppv !is null) {
			AddRef();
			return NOERROR;
		} else {
			return E_NOINTERFACE;
		}
	}

	public
	extern(Windows) ULONG AddRef() {
		import core.atomic;
		return atomicOp!"+="(*cast(shared)&count, 1);
	}

	public
	extern(Windows) ULONG Release() {
		import core.atomic;
		LONG lRef = atomicOp!"-="(*cast(shared)&count, 1);
		if (lRef == 0) {
			// free object

			/*
			* Tell the housing that an object is going away so it can
			* shut down if appropriate.
			*/
			//MessageBoxA(null, "CHello Destroy()", null, MB_OK);

			if (m_pfnDestroy)
				(*m_pfnDestroy)();

			// delete this;
			return 0;


			// If we delete this object, then the postinvariant called upon
			// return from Release() will fail.
			// Just let the GC reap it.
			//delete this;

			return 0;
		}

		return cast(ULONG)lRef;
	}

	LONG count = 0;             // object reference count

}




// Type for an object-destroyed callback
alias void function() PFNDESTROYED;

// This class factory object creates Hello objects.
class ClassFactory(Class) : IClassFactory {
	extern (Windows) :

	// IUnknown members
	override HRESULT QueryInterface(const (IID)*riid, LPVOID *ppv) {
		if (IID_IUnknown == *riid) {
			*ppv = cast(void*) cast(IUnknown) this;
		}
		else if (IID_IClassFactory == *riid) {
			*ppv = cast(void*) cast(IClassFactory) this;
		}
		else {
			*ppv = null;
			return E_NOINTERFACE;
		}

		AddRef();
		return NOERROR;
	}

	LONG count = 0;             // object reference count
	ULONG AddRef() {
		return atomicOp!"+="(*cast(shared)&count, 1);
	}

	ULONG Release() {
		return atomicOp!"-="(*cast(shared)&count, 1);
	}

	// IClassFactory members
	override HRESULT CreateInstance(IUnknown pUnkOuter, IID*riid, LPVOID *ppvObj) {
		HRESULT hr;

		*ppvObj = null;
		hr      = E_OUTOFMEMORY;

		// Verify that a controlling unknown asks for IUnknown
		if (null !is pUnkOuter && IID_IUnknown == *riid)
			return CLASS_E_NOAGGREGATION;

		// Create the object passing function to notify on destruction.
		auto pObj = new Class(pUnkOuter, &ObjectDestroyed);

		if (!pObj) {
			MessageBoxA(null, "null", null, 0);
			return hr;
		}

		if (pObj.Init()) {
			hr = pObj.QueryInterface(riid, ppvObj);
		}

		// Kill the object if initial creation or Init failed.
		if (FAILED(hr))
			delete pObj;
		else
			g_cObj++;

		return hr;
	}

	HRESULT LockServer(BOOL fLock) {
		//MessageBoxA(null, "CHelloClassFactory.LockServer()", null, MB_OK);

		if (fLock)
			g_cLock++;
		else
			g_cLock--;

		return NOERROR;
	}
}
__gshared ULONG g_cLock=0;
__gshared ULONG g_cObj =0;

/*
 * ObjectDestroyed
 *
 * Purpose:
 *  Function for the Hello object to call when it gets destroyed.
 *  Since we're in a DLL we only track the number of objects here,
 *  letting DllCanUnloadNow take care of the rest.
 */

extern (D) void ObjectDestroyed()
{
    //MessageBoxA(null, "ObjectDestroyed()", null, MB_OK);
    g_cObj--;
}


char[] oleCharsToString(char[] buffer, OLECHAR* chars) @system {
	auto c = cast(wchar*) chars;
	auto orig = c;

	size_t len = 0;
	while(*c) {
		len++;
		c++;
	}

	auto c2 = orig[0 .. len];
	int blen;
	foreach(ch; c2) {
		// FIXME breaks for non-ascii
		assert(ch < 127);
		buffer[blen] = cast(char) ch;
		blen++;
	}

	return buffer[0 .. blen];
}


// usage: mixin ComServerMain!(CHello, CLSID_Hello, "Hello", "1.0");
mixin template ComServerMain(Class, string progId, string ver) {
	static assert(hasGuidAttribute!Class, "Add a @ComGuid(GUID()) to your class");

	__gshared HINSTANCE g_hInst;

	// initializing the runtime can fail on Windows XP when called via regsvr32...

	extern (Windows)
	BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved) {
		import core.sys.windows.dll;
		g_hInst = hInstance;

		switch (ulReason) {
			case DLL_PROCESS_ATTACH:
				return dll_process_attach(hInstance, true);
			break;
			case DLL_THREAD_ATTACH:
				dll_thread_attach(true, true);
			break;
			case DLL_PROCESS_DETACH:
				dll_process_detach(hInstance, true);
			break;

			case DLL_THREAD_DETACH:
				return dll_thread_detach(true, true);
			break;

			default:
				assert(0);
		}

		return true;
	}

	/*
	 * DllGetClassObject
	 *
	 * Purpose:
	 *  Provides an IClassFactory for a given CLSID that this DLL is
	 *  registered to support.  This DLL is placed under the CLSID
	 *  in the registration database as the InProcServer.
	 *
	 * Parameters:
	 *  clsID           REFCLSID that identifies the class factory
	 *                  desired.  Since this parameter is passed this
	 *                  DLL can handle any number of objects simply
	 *                  by returning different class factories here
	 *                  for different CLSIDs.
	 *
	 *  riid            REFIID specifying the interface the caller wants
	 *                  on the class object, usually IID_ClassFactory.
	 *
	 *  ppv             LPVOID * in which to return the interface
	 *                  pointer.
	 *
	 * Return Value:
	 *  HRESULT         NOERROR on success, otherwise an error code.
	 */
	pragma(mangle, "DllGetClassObject")
	export
	extern(Windows)
	HRESULT DllGetClassObject(CLSID* rclsid, IID* riid, LPVOID* ppv) {
		HRESULT hr;
		ClassFactory!Class pObj;

		//MessageBoxA(null, "DllGetClassObject()", null, MB_OK);

		// printf("DllGetClassObject()\n");

		if (clsid != *rclsid)
			return E_FAIL;

		pObj = new ClassFactory!Class();

		if (!pObj)
			return E_OUTOFMEMORY;

		hr = pObj.QueryInterface(riid, ppv);

		if (FAILED(hr))
			delete pObj;

		return hr;
	}

	/*
	 *  Answers if the DLL can be freed, that is, if there are no
	 *  references to anything this DLL provides.
	 *
	 * Return Value:
	 *  BOOL            true if nothing is using us, false otherwise.
	 */
	pragma(mangle, "DllCanUnloadNow")
	extern(Windows)
	HRESULT DllCanUnloadNow() {
		SCODE sc;

		//MessageBoxA(null, "DllCanUnloadNow()", null, MB_OK);

		// Any locks or objects?
		sc = (0 == g_cObj && 0 == g_cLock) ? S_OK : S_FALSE;
		return sc;
	}

	static immutable clsid = getGuidAttribute!Class.guid;

	/*
	 *  Instructs the server to create its own registry entries
	 *
	 * Return Value:
	 *  HRESULT         NOERROR if registration successful, error
	 *                  otherwise.
	 */
	pragma(mangle, "DllRegisterServer")
	extern(Windows)
	HRESULT DllRegisterServer() {
		char[128] szID;
		char[128] szCLSID;
		char[512] szModule;

		// Create some base key strings.
		MessageBoxA(null, "DllRegisterServer", null, MB_OK);
		auto len = StringFromGUID2(&clsid, cast(LPOLESTR) szID, 128);
		unicode2ansi(szID.ptr);
		szID[len] = 0;

		//MessageBoxA(null, toStringz("DllRegisterServer("~szID[0 .. len] ~")"), null, MB_OK);

		strcpy(szCLSID.ptr, "CLSID\\");
		strcat(szCLSID.ptr, szID.ptr);

		char[200] partialBuffer;
		partialBuffer[0 .. progId.length] = progId[];
		partialBuffer[progId.length] = 0;
		auto partial = partialBuffer.ptr;

		char[200] fullBuffer;
		fullBuffer[0 .. progId.length] = progId[];
		fullBuffer[progId.length .. progId.length + ver.length] = ver[];
		fullBuffer[progId.length + ver.length] = 0;
		auto full = fullBuffer.ptr;

		// Create ProgID keys
		SetKeyAndValue(full, null, "Hello Object");
		SetKeyAndValue(full, "CLSID", szID.ptr);

		// Create VersionIndependentProgID keys
		SetKeyAndValue(partial, null, "Hello Object");
		SetKeyAndValue(partial, "CurVer", full);
		SetKeyAndValue(partial, "CLSID", szID.ptr);

		// Create entries under CLSID
		SetKeyAndValue(szCLSID.ptr, null, "Hello Object");
		SetKeyAndValue(szCLSID.ptr, "ProgID", full);
		SetKeyAndValue(szCLSID.ptr, "VersionIndependentProgID", partial);
		SetKeyAndValue(szCLSID.ptr, "NotInsertable", null);

		GetModuleFileNameA(g_hInst, szModule.ptr, szModule.length);

		SetKeyAndValue(szCLSID.ptr, "InprocServer32", szModule.ptr);
		return NOERROR;
	}

	/*
	 * Purpose:
	 *  Instructs the server to remove its own registry entries
	 *
	 * Return Value:
	 *  HRESULT         NOERROR if registration successful, error
	 *                  otherwise.
	 */
	pragma(mangle, "DllUnregisterServer")
	extern(Windows)
	HRESULT DllUnregisterServer() {
		char[128] szID;
		char[128] szCLSID;
		char[256] szTemp;

		MessageBoxA(null, "DllUnregisterServer()", null, MB_OK);

		// Create some base key strings.
		StringFromGUID2(&clsid, cast(LPOLESTR) szID, 128);
		unicode2ansi(szID.ptr);
		strcpy(szCLSID.ptr, "CLSID\\");
		strcat(szCLSID.ptr, szID.ptr);

		TmpStr tmp;
		tmp.append(progId);
		tmp.append("\\CurVer");
		RegDeleteKeyA(HKEY_CLASSES_ROOT, tmp.getPtr());
		tmp.clear();
		tmp.append(progId);
		tmp.append("\\CLSID");
		RegDeleteKeyA(HKEY_CLASSES_ROOT, tmp.getPtr());
		tmp.clear();
		tmp.append(progId);
		RegDeleteKeyA(HKEY_CLASSES_ROOT, tmp.getPtr());

		tmp.clear();
		tmp.append(progId);
		tmp.append(ver);
		tmp.append("\\CLSID");
		RegDeleteKeyA(HKEY_CLASSES_ROOT, tmp.getPtr());
		tmp.clear();
		tmp.append(progId);
		tmp.append(ver);
		RegDeleteKeyA(HKEY_CLASSES_ROOT, tmp.getPtr());

		strcpy(szTemp.ptr, szCLSID.ptr);
		strcat(szTemp.ptr, "\\");
		strcat(szTemp.ptr, "ProgID");
		RegDeleteKeyA(HKEY_CLASSES_ROOT, szTemp.ptr);

		strcpy(szTemp.ptr, szCLSID.ptr);
		strcat(szTemp.ptr, "\\");
		strcat(szTemp.ptr, "VersionIndependentProgID");
		RegDeleteKeyA(HKEY_CLASSES_ROOT, szTemp.ptr);

		strcpy(szTemp.ptr, szCLSID.ptr);
		strcat(szTemp.ptr, "\\");
		strcat(szTemp.ptr, "NotInsertable");
		RegDeleteKeyA(HKEY_CLASSES_ROOT, szTemp.ptr);

		strcpy(szTemp.ptr, szCLSID.ptr);
		strcat(szTemp.ptr, "\\");
		strcat(szTemp.ptr, "InprocServer32");
		RegDeleteKeyA(HKEY_CLASSES_ROOT, szTemp.ptr);

		RegDeleteKeyA(HKEY_CLASSES_ROOT, szCLSID.ptr);
		return NOERROR;
	}
}

/*
 * SetKeyAndValue
 *
 * Purpose:
 *  Private helper function for DllRegisterServer that creates
 *  a key, sets a value, and closes that key.
 *
 * Parameters:
 *  pszKey          LPTSTR to the name of the key
 *  pszSubkey       LPTSTR ro the name of a subkey
 *  pszValue        LPTSTR to the value to store
 *
 * Return Value:
 *  BOOL            true if successful, false otherwise.
 */
BOOL SetKeyAndValue(LPCSTR pszKey, LPCSTR pszSubkey, LPCSTR pszValue)
{
    HKEY hKey;
    char[256] szKey;
    BOOL result;

    strcpy(szKey.ptr, pszKey);

    if (pszSubkey)
    {
	strcat(szKey.ptr, "\\");
	strcat(szKey.ptr, pszSubkey);
    }

    result = true;

    if (ERROR_SUCCESS != RegCreateKeyExA(HKEY_CLASSES_ROOT,
					  szKey.ptr, 0, null, REG_OPTION_NON_VOLATILE,
					  KEY_ALL_ACCESS, null, &hKey, null))
	result = false;
    else
    {
	if (null != pszValue)
	{
	    if (RegSetValueExA(hKey, null, 0, REG_SZ, cast(BYTE *) pszValue,
                           cast(uint)((strlen(pszValue) + 1) * char.sizeof)) != ERROR_SUCCESS)
		result = false;
	}

	if (RegCloseKey(hKey) != ERROR_SUCCESS)
	    result = false;
    }

    if (!result)
	MessageBoxA(null, "SetKeyAndValue() failed", null, MB_OK);

    return result;
}

void unicode2ansi(char *s) @system
{
    wchar *w;

    for (w = cast(wchar *) s; *w; w++)
	*s++ = cast(char)*w;

    *s = 0;
}

/**************************************
 * Register/unregister a DLL server.
 * Input:
 *      flag    !=0: register
 *              ==0: unregister
 * Returns:
 *      0       success
 *      !=0     failure
 */

extern (Windows) alias HRESULT function() pfn_t;

int dll_regserver(const (char) *dllname, int flag) {
	char *fn = flag ? cast(char*) "DllRegisterServer"
		: cast(char*) "DllUnregisterServer";
	int result = 1;
	pfn_t pfn;
	HINSTANCE hMod;

	if (SUCCEEDED(CoInitialize(null))) {
		hMod=LoadLibraryA(dllname);

		if (hMod > cast(HINSTANCE) HINSTANCE_ERROR) {
			pfn = cast(pfn_t)(GetProcAddress(hMod, fn));

			if (pfn && SUCCEEDED((*pfn)()))
				result = 0;

			CoFreeLibrary(hMod);
			CoUninitialize();
		}
	}

	return result;
}

struct TmpStr {
	char[256] buffer;
	int length;
	void clear() { length = 0; }
	char* getPtr() return {
		buffer[length] = 0;
		return buffer.ptr;
	}

	void append(string s) {
		buffer[length .. length + s.length] = s[];
		length += s.length;
	}
}

/+
        Goals:

        * Use RoInitialize if present, OleInitialize or CoInitializeEx if not.
                (if RoInitialize is present, webview can use Edge too, otherwise
                gonna go single threaded for MSHTML. maybe you can require it via
                a version switch)

                or i could say this is simply not compatible with webview but meh.

        * idl2d ready to rock
        * RAII objects in use with natural auto-gen wrappers
        * Natural implementations type-checking the interface

        so like given

        interface Foo : IUnknown {
                HRESULT test(BSTR a, out int b);
        }

        you can

        alias EasyCom!Foo Foo;
        Foo f = Foo.make; // or whatever
        int b = f.test("cool"); // throws if it doesn't return OK

        class MyFoo : ImplementsCom!(Foo) {
                int test(string a) { return 5; }
        }

        and then you still use it through the interface.

        ImplementsCom takes the interface and translates it into
        a regular D interface for type checking.
        and then makes a proxy class to forward stuff. unless i can
        rig it with abstract methods

        class MyNewThing : IsCom!(MyNewThing) {
                // indicates this implementation ought to
                // become the interface
        }

        (basically in either case it converts the class to a COM
        wrapper, then asserts it actually implements the required
        interface)



        or what if i had a private implementation of the interface
        in the base class, auto-generated. then abstract hooks for
        the other things.
+/

/++

module com;

import com2;

interface Refcounting {
        void AddRef();
        void Release();
}

interface Test : Refcounting {
        void test();
}

interface Test2 : Refcounting {
        void test2();
}

class Foo : Implements!Test, Implements!Test2 {
        override void test() {
                import std.stdio;
                writeln("amazing");
        }

        void test2() {}

        mixin Refcounts;
}
mixin RegisterComImplementation!(Foo, "some-guid");

void main() {
        auto foo = new Foo();
        auto c = foo.getComProxy();
        c.test();

}

+/

/++

module com2;

/+
        The COM interface's implementation is done by a
        generated class, forwarding it to the other D
        implementation

        if it implements IDispatch then it can do the dynamic
        thing too automatically!
+/

template Implements(Interface) {
        private static class Helper : Interface {
                Implements i;
                this(Implements i) {
                        this.i = i;
                }

                static foreach(memberName; __traits(allMembers, Interface))
                mixin(q{ void } ~ memberName ~ q{ () {
                        import std.stdio; writeln("wrapper begin");
                        __traits(getMember, i, memberName)();
                        writeln("wrapper end");
                }});
        }

        interface Implements {
                final Helper getComProxy() {
                        return new Helper(this);
                }

                static foreach(memberName; __traits(allMembers, Interface))
                mixin(q{ void } ~ memberName ~ q{ (); });

                mixin template Refcounts() {
                        int refcount;
                        void AddRef() { refcount ++; }
                        void Release() { refcount--; }
                }
        }
}

// the guid may also be a UDA on Class, but you do need to register your implementations
mixin template RegisterComImplementation(Class, string guid = null) {

}

// wraps the interface with D-friendly type and provides RAII for the object
struct ComClient(I) {}
// eg: alias XmlDocument = ComClient!IXmlDocument;
// then you get it through a com factory

ComClient!I getCom(T)(string guid) { return ComClient!I(); }

+/
