/++
	My old com helper code. I haven't used it for years.
+/
module arsd.comhelpers;

/+
	see: program\comtest.d on the laptop.

	as administrator: from program\cs
	c:\Windows\Microsoft.NEt\Framework64\v4.0.30319\regasm.exe /regfile /codebase test.dll

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

version(Windows):

import core.sys.windows.windows;
import core.sys.windows.com;
import core.sys.windows.oaidl;

public import core.stdc.string;
import core.atomic;

pragma(lib, "advapi32");
pragma(lib, "uuid");
pragma(lib, "ole32");
pragma(lib, "oleaut32");


/* Attributes that help with automation */

static immutable struct ComGuid {
	GUID guid;
}

bool hasGuidAttribute(T)() {
	foreach(attr; __traits(getAttributes, T))
		static if(is(typeof(attr) == ComGuid))
			return true;
	return false;
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
static ~this() {
	CoFreeUnusedLibraries();
	if(coInitializeCalled) {
		CoUninitialize();
		coInitializeCalled--;
	}
}
void initializeCom() {
	if(coInitializeCalled)
		return;

	/*
	// Make sure COM is the right version
	auto dwVer = CoBuildVersion();

	if (rmm != HIWORD(dwVer))
		throw new Exception("Incorrect OLE 2 version number\n");
	*/

	auto hr = CoInitialize(null);

	if (FAILED(hr))
		throw new Exception("OLE 2 failed to initialize\n");

	coInitializeCalled++;
}

struct AutoComPtr(T) {
	T t;
	this(T t) {
		this.t = t;
	}
	this(this) {
		t.AddRef();
	}
	~this() {
		t.Release();
	}
	alias t this;
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

/// Create a COM object. the string params are GUID literals that i mixin (this sux i know)
/// or if the interface has no IID it will try to IDispatch it
/// or you can request a fully dynamic version via opDispatch.
/// note i can try `import core.sys.windows.uuid; IID_IDispatch` for example to generically look up ones from the system if they are not attached and come from the windows namespace
AutoComPtr!T createObject(T, string iidStr = null)(GUID classId) {
	initializeCom();

	static if(iidStr == null) {
		auto iid = getGuidAttribute!(T).guid;
	} else
		auto iid = mixin(iidStr);

	T obj;

	auto hr = CoCreateInstance(&classId, null, CLSCTX_INPROC_SERVER, &iid, cast(void**) &obj);
	import std.format;
	if(FAILED(hr))
		throw new Exception("Failed to create object " ~ format("%08x", hr));

	return AutoComPtr!T(obj);
}


// FIXME: add one to get by ProgID rather than always guid
// FIXME: add a dynamic com object that uses IDispatch


/* COM SERVER CODE */

T getFromVariant(T)(VARIANT arg) {
	import std.traits;
	import std.conv;
	static if(is(T == int)) {
		if(arg.vt == 3)
			return arg.intVal;
	} else static if(is(T == string)) {
		if(arg.vt == 8) {
			auto str = arg.bstrVal;
			return to!string(str[0 .. SysStringLen(str)]);
		}
	} else static if(is(T == IDispatch)) {
		if(arg.vt == 9)
			return arg.pdispVal;
	}
	throw new Exception("Type mismatch, needed "~ T.stringof ~"got " ~ to!string(arg.vt));
	assert(0);
}

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
						except.wCode = 1;
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

extern (C)
{
	void rt_init();
	void rt_term();
	void gc_init();
	void gc_term();
}


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
	char* getPtr() {
		buffer[length] = 0;
		return buffer.ptr;
	}

	void append(string s) {
		buffer[length .. length + s.length] = s[];
		length += s.length;
	}
}


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
