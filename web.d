module arsd.web;

// FIXME: if a method has a default value of a non-primitive type,
// it's still liable to screw everything else.

/*
	Reasonably easy CSRF plan:

	A csrf token can be associated with the entire session, and
	saved in the session file.

	Each form outputs the token, and it is added as a parameter to
	the script thingy somewhere.

	It need only be sent on POST items. Your app should handle proper
	get and post separation.
*/

/*
	Future directions for web stuff:

	an improved css:
		add definition nesting
		add importing things from another definition

		Implemented: see html.d

	All css improvements are done via simple text rewriting. Aside
	from the nesting, it'd just be a simple macro system.


	Struct input functions:
		static typeof(this) fromWebString(string fromUrl) {}

	Automatic form functions:
		static Element makeFormElement(Document document) {}


	javascript:
		I'd like to add functions and do static analysis actually.
		I can't believe I just said that though.

		But the stuff I'd analyze is checking it against the
		D functions, recognizing that JS is loosely typed.

		So basically it can do a grep for simple stuff:

			CoolApi.xxxxxxx

			if xxxxxxx isn't a function in CoolApi (the name
			it knows from the server), it can flag a compile
			error.

			Might not be able to catch usage all the time
			but could catch typo names.

*/

/*
	FIXME: in params on the wrapped functions generally don't work
		(can't modify const)

	Running from the command line:

	./myapp function positional args....
	./myapp --format=json function 

	./myapp --make-nested-call


	Formatting data:

	CoolApi.myFunc().getFormat('Element', [...same as get...]);

	You should also be able to ask for json, but with a particular format available as toString

	format("json", "html") -- gets json, but each object has it's own toString. Actually, the object adds
		a member called formattedSecondarily that is the other thing.
	Note: the array itself cannot be changed in format, only it's members.
	Note: the literal string of the formatted object is often returned. This may more than double the bandwidth of the call

	Note: BUG: it only works with built in formats right now when doing secondary


	// formats are: text, html, json, table, and xml
	// except json, they are all represented as strings in json values

	string    toString        -> formatting as text
	Element   makeHtmlElement -> making it html (same as fragment)
	JSONValue makeJsonValue   -> formatting to json
	Table     makeHtmlTable   -> making a table
	(not implemented) toXml   -> making it into an xml document


	Arrays can be handled too:

	static (converts to) string makeHtmlArray(typeof(this)[] arr);


	Envelope format:

	document (default), json, none
*/

import std.exception;
public import arsd.dom;
public import arsd.cgi; // you have to import this in the actual usage file or else it won't link; surely a compiler bug
import arsd.sha;

public import std.string;
public import std.array;
public import std.stdio : writefln;
public import std.conv;
import std.random;

import std.datetime;

public import std.range;

public import std.traits;
import std.json;

/// This gets your site's base link. note it's really only good if you are using FancyMain.
string getSiteLink(Cgi cgi) {
	return cgi.requestUri[0.. cgi.requestUri.indexOf(cgi.scriptName) + cgi.scriptName.length + 1 /* for the slash at the end */];
}

/// use this in a function parameter if you want the automatic form to render
/// it as a textarea
/// FIXME: this should really be an annotation on the parameter... somehow
struct Text {
	string content;
	alias content this;
}

/// This is the JSON envelope format
struct Envelope {
	bool success; /// did the call succeed? false if it threw an exception
	string type; /// static type of the return value
	string errorMessage; /// if !success, this is exception.msg
	string userData; /// null unless the user request included passedThroughUserData

	// use result.str if the format was anything other than json
	JSONValue result; /// the return value of the function

	debug string dFullString; /// exception.toString - includes stack trace, etc. Only available in debug mode for privacy reasons.
}

/// Info about the current request - more specialized than the cgi object directly
struct RequestInfo {
	string mainSitePath; /// the bottom-most ApiProvider's path in this request
	string objectBasePath; /// the top-most resolved path in the current request

	FunctionInfo currentFunction; /// what function is being called according to the url?

	string requestedFormat; /// the format the returned data was requested to be sent
	string requestedEnvelopeFormat; /// the format the data is to be wrapped in
}

/+
string linkTo(alias func, T...)(T args) {
	auto reflection = __traits(parent, func).reflection;
	assert(reflection !is null);

	auto name = func.stringof;
	auto idx = name.indexOf("(");
	if(idx != -1)
		name = name[0 .. idx];

	auto funinfo = reflection.functions[name];

	return funinfo.originalName;
}
+/

/// this is there so there's a common runtime type for all callables
class WebDotDBaseType {
	Cgi cgi; /// lower level access to the request

	/// Override this if you want to do something special to the document
	/// You should probably call super._postProcess at some point since I
	/// might add some default transformations here.

	/// By default, it forwards the document root to _postProcess(Element).
	void _postProcess(Document document) {
		if(document !is null && document.root !is null)
			_postProcessElement(document.root);
	}

	/// Override this to do something special to returned HTML Elements.
	/// This is ONLY run if the return type is(: Element). It is NOT run
	/// if the return type is(: Document).
	void _postProcessElement(Element element) {} // why the fuck doesn't overloading actually work?

	/// convenience function to enforce that the current method is POST.
	/// You should use this if you are going to commit to the database or something.
	void ensurePost() {
		assert(cgi !is null);
		enforce(cgi.requestMethod == Cgi.RequestMethod.POST);
	}
}

/// This is meant to beautify and check links and javascripts to call web.d functions.
/// FIXME: this function sucks.
string linkCall(alias Func, Args...)(Args args) {
	static if(!__traits(compiles, Func(args))) {
		static assert(0, "Your function call doesn't compile. If you need client side dynamic data, try building the call as a string.");
	}

	// FIXME: this link won't work from other parts of the site...

	//string script = __traits(parent, Func).stringof;
	auto href = __traits(identifier, Func) ~ "?";

	bool outputted = false;
	foreach(i, arg; args) {
		if(outputted) {
			href ~= "&";
		} else
			outputted = true;

		href ~= std.uri.encodeComponent("positional-arg-" ~ to!string(i));
		href ~= "=";
		href ~= to!string(arg); // FIXME: this is wrong for all but the simplest types
	}

	return href;

}

/// This is meant to beautify and check links and javascripts to call web.d functions.
/// This function works pretty ok. You're going to want to append a string to the return
/// value to actually call .get() or whatever; it only does the name and arglist.
string jsCall(alias Func, Args...)(Args args) /*if(is(__traits(parent, Func) : WebDotDBaseType))*/ {
	static if(!__traits(compiles, Func(args))) {
		static assert(0, "Your function call doesn't compile. If you need client side dynamic data, try building the call as a string.");
	}

	string script = __traits(parent, Func).stringof;
	script ~= "." ~ __traits(identifier, Func) ~ "(";

	bool outputted = false;
	foreach(arg; args) {
		if(outputted) {
			script ~= ",";
		} else
			outputted = true;

		script ~= toJson(arg);
	}

	script ~= ")";
	return script;
}

/// Everything should derive from this instead of the old struct namespace used before
/// Your class must provide a default constructor.
class ApiProvider : WebDotDBaseType {
	private ApiProvider builtInFunctions;

	Session session; // note: may be null

	/// override this to change cross-site request forgery checks.
	///
	/// To perform a csrf check, call ensureGoodPost(); in your code.
	///
	/// It throws a PermissionDeniedException if the check fails.
	/// This might change later to make catching it easier.
	///
	/// If there is no session object, the test always succeeds. This lets you opt
	/// out of the system.
	///
	/// If the session is null, it does nothing. FancyMain makes a session for you.
	/// If you are doing manual run(), it is your responsibility to create a session
	/// and attach it to each primary object.
	///
	/// NOTE: it is important for you use ensureGoodPost() on any data changing things!
	/// This function alone is a no-op on non-POST methods, so there's no real protection
	/// without ensuring POST when making changes.
	///
	// FIXME: if someone is OAuth authorized, a csrf token should not really be necessary.
	// This check is done automatically right now, and doesn't account for that. I guess
	// people could override it in a subclass though. (Which they might have to since there's
	// no oauth integration at this level right now anyway. Nor may there ever be; it's kinda
	// high level. Perhaps I'll provide an oauth based subclass later on.)
	protected void checkCsrfToken() {
		assert(cgi !is null);
		if(cgi.requestMethod == Cgi.RequestMethod.POST) {
			auto tokenInfo = _getCsrfInfo();
			if(tokenInfo is null)
				return; // not doing checks

			void fail() {
				throw new PermissionDeniedException("CSRF token test failed");
			}

			// expiration is handled by the session itself expiring (in the Session class)

			if(tokenInfo["key"] !in cgi.post)
				fail();
			if(cgi.post[tokenInfo["key"]] != tokenInfo["token"])
				fail();
		}
	}

	/// Shorthand for ensurePost and checkCsrfToken. You should use this on non-indempotent 
	/// functions. Override it if doing some custom checking.
	void ensureGoodPost() {
		ensurePost();
		checkCsrfToken();
	}

	// gotta make sure this isn't callable externally! Oh lol that'd defeat the point...
	/// Gets the CSRF info (an associative array with key and token inside at least) from the session.
	/// Note that the actual token is generated by the Session class.
	protected string[string] _getCsrfInfo() {
		if(session is null)
			return null;
		return decodeVariablesSingle(session.csrfToken);
	}

	/// Adds CSRF tokens to the document for use by script (required by the Javascript API)
	/// and then calls addCsrfTokens(document.root) to add them to all POST forms as well.
	protected void addCsrfTokens(Document document) {
		if(document is null)
			return;
		auto bod = document.mainBody;
		if(!bod.hasAttribute("data-csrf-key")) {
			auto tokenInfo = _getCsrfInfo();
			if(tokenInfo is null)
				return;
			if(bod !is null) {
				bod.setAttribute("data-csrf-key", tokenInfo["key"]);
				bod.setAttribute("data-csrf-token", tokenInfo["token"]);
			}

			addCsrfTokens(document.root);
		}
	}

	/// we have to add these things to the document...
	override void _postProcess(Document document) {
		addCsrfTokens(document);
		super._postProcess(document);
	}

	/// This adds CSRF tokens to all forms in the tree
	protected void addCsrfTokens(Element element) {
		if(element is null)
			return;
		auto tokenInfo = _getCsrfInfo();
		if(tokenInfo is null)
			return;

		foreach(formElement; element.getElementsByTagName("form")) {
			if(formElement.method != "POST" && formElement.method != "post")
				continue;
			auto form = cast(Form) formElement;
			assert(form !is null);

			form.setValue(tokenInfo["key"], tokenInfo["token"]);
		}
	}

	// and added to ajax forms..
	override void _postProcessElement(Element element) {
		addCsrfTokens(element);
		super._postProcessElement(element);
	}


	// FIXME: the static is meant to be a performance improvement, but it breaks child modules' reflection!
	/*static */immutable(ReflectionInfo)* reflection;
	string _baseUrl; // filled based on where this is called from on this request

	RequestInfo currentRequest; // FIXME: actually fill this in

	/// Override this if you have initialization work that must be done *after* cgi and reflection is ready.
	/// It should be used instead of the constructor for most work.
	void _initialize() {}

	/// This one is called at least once per call. (_initialize is only called once per process)
	void _initializePerCall() {}

	/// Returns the stylesheet for this module. Use it to encapsulate the needed info for your output so the module is more easily reusable
	/// Override this to provide your own stylesheet. (of course, you can always provide it via _catchAll or any standard css file/style element too.)
	string _style() const {
		return null;
	}

	/// Returns the combined stylesheet of all child modules and this module
	string stylesheet() const {
		string ret;
		foreach(i; reflection.objects) {
			if(i.instantiation !is null)
				ret ~= i.instantiation.stylesheet();
		}

		ret ~= _style();
		return ret;
	}

	/// This tentatively redirects the user - depends on the envelope fomat
	void redirect(string location, bool important = false) {
		auto f = cgi.request("envelopeFormat", "document");
		if(f == "document" || f == "redirect")
			cgi.setResponseLocation(location, important);
	}

	/// Returns a list of links to all functions in this class or sub-classes
	/// You can expose it publicly with alias: "alias _sitemap sitemap;" for example.
	Element _sitemap() {
		auto container = _getGenericContainer();

		void writeFunctions(Element list, in ReflectionInfo* reflection, string base) {
			string[string] handled;
			foreach(key, func; reflection.functions) {
				if(func.originalName in handled)
					continue;
				handled[func.originalName] = func.originalName;

				// skip these since the root is what this is there for
				if(func.originalName == "GET" || func.originalName == "POST")
					continue;

				// the builtins aren't interesting either
				if(key.startsWith("builtin."))
					continue;

				if(func.originalName.length)
					list.addChild("li", new Link(base ~ func.name, beautify(func.originalName)));
			}

			handled = null;
			foreach(obj; reflection.objects) {
				if(obj.name in handled)
					continue;
				handled[obj.name] = obj.name;

				auto li = list.addChild("li", new Link(base ~ obj.name, obj.name));

				auto ul = li.addChild("ul");
				writeFunctions(ul, obj, base ~ obj.name ~ "/");
			}
		}

		auto list = container.addChild("ul");
		auto starting = _baseUrl;
		if(starting is null)
			starting = cgi.scriptName ~ cgi.pathInfo; // FIXME
		writeFunctions(list, reflection, starting ~ "/");

		return list.parentNode.removeChild(list);
	}

	/// If the user goes to your program without specifying a path, this function is called.
	// FIXME: should it return document? That's kinda a pain in the butt.
	Document _defaultPage() {
		throw new Exception("no default");
	}

	/// When the html document envelope is used, this function is used to get a html element
	/// where the return value is appended.

	/// It's the main function to override to provide custom HTML templates.
	Element _getGenericContainer()
	out(ret) {
		assert(ret !is null);
	}
	body {
		auto document = new Document("<!DOCTYPE html><html><head><title></title><style>.format-row { display: none; }</style><link rel=\"stylesheet\" href=\"styles.css\" /></head><body><div id=\"body\"></div><script src=\"functions.js\"></script></body></html>", true, true);
		if(this.reflection !is null)
			document.title = this.reflection.name;
		auto container = document.getElementById("body");
		return container;
	}

	/// If the given url path didn't match a function, it is passed to this function
	/// for further handling. By default, it throws a NoSuchPageException.

	/// Overriding it might be useful if you want to serve generic filenames or an opDispatch kind of thing.
	/// (opDispatch itself won't work because it's name argument needs to be known at compile time!)
	///
	/// Note that you can return Documents here as they implement
	/// the FileResource interface too.
	FileResource _catchAll(string path) {
		throw new NoSuchPageException(_errorMessageForCatchAll);
	}

	private string _errorMessageForCatchAll;
	private FileResource _catchallEntry(string path, string funName, string errorMessage) {
		if(!errorMessage.length) {
			/*
			string allFuncs, allObjs;
			foreach(n, f; reflection.functions)
				allFuncs ~= n ~ "\n";
			foreach(n, f; reflection.objects)
				allObjs ~= n ~ "\n";
			errorMessage =  "no such function " ~ funName ~ "\n functions are:\n" ~ allFuncs ~ "\n\nObjects are:\n" ~ allObjs;
			*/

			errorMessage = "No such page: " ~ funName;
		}

		_errorMessageForCatchAll = errorMessage;

		return _catchAll(path);
	}


	/// When in website mode, you can use this to beautify the error message
	Document delegate(Throwable) _errorFunction;
}

/// Implement subclasses of this inside your main provider class to do a more object
/// oriented site.
class ApiObject : WebDotDBaseType {
	/* abstract this(ApiProvider parent, string identifier) */

	/// Override this to make json out of this object
	JSONValue makeJsonValue() {
		return toJsonValue(null);
	}
}

class DataFile : FileResource {
	this(string contentType, immutable(void)[] contents) {
		_contentType = contentType;
		_content = contents;
	}

	private string _contentType;
	private immutable(void)[] _content;

	string contentType() const {
		return _contentType;
	}

	immutable(ubyte)[] getData() const {
		return cast(immutable(ubyte)[]) _content;
	}
}

/// Describes the info collected about your class
struct ReflectionInfo {
	immutable(FunctionInfo)*[string] functions; /// the methods
	EnumInfo[string] enums; /// .
	StructInfo[string] structs; ///.
	const(ReflectionInfo)*[string] objects; /// ApiObjects and ApiProviders

	bool needsInstantiation; // internal - does the object exist or should it be new'd before referenced?

	ApiProvider instantiation; // internal (for now) - reference to the actual object being described

	WebDotDBaseType delegate(string) instantiate;

	// the overall namespace
	string name; /// this is also used as the object name in the JS api


	// these might go away.

	string defaultOutputFormat = "html";
	int versionOfOutputFormat = 2; // change this in your constructor if you still need the (deprecated) old behavior
	// bool apiMode = false; // no longer used - if format is json, apiMode behavior is assumed. if format is html, it is not.
				// FIXME: what if you want the data formatted server side, but still in a json envelope?
				// should add format-payload:
}

/// describes an enum, iff based on int as the underlying type
struct EnumInfo {
	string name; ///.
	int[] values; ///.
	string[] names; ///.
}

/// describes a plain data struct
struct StructInfo {
	string name; ///.
	// a struct is sort of like a function constructor...
	StructMemberInfo[] members; ///.
}

///.
struct StructMemberInfo {
	string name; ///.
	string staticType; ///.
	string defaultValue; ///.
}

///.
struct FunctionInfo {
	WrapperFunction dispatcher; /// this is the actual function called when a request comes to it - it turns a string[][string] into the actual args and formats the return value

	const(ReflectionInfo)* parentObject;

	// should I also offer dispatchers for other formats like Variant[]?

	string name; /// the URL friendly name
	string originalName; /// the original name in code

	//string uriPath;

	Parameter[] parameters; ///.

	string returnType; ///. static type to string
	bool returnTypeIsDocument; // internal used when wrapping
	bool returnTypeIsElement; // internal used when wrapping

	Document delegate(in string[string] args) createForm; /// This is used if you want a custom form - normally, on insufficient parameters, an automatic form is created. But if there's a functionName_Form method, it is used instead. FIXME: this used to work but not sure if it still does
}

/// Function parameter
struct Parameter {
	string name; /// name (not always accurate)
	string value; // ???

	string type; /// type of HTML element to create when asking
	string staticType; /// original type
	string validator; /// FIXME

	bool hasDefault; /// if there was a default defined in the function
	string defaultValue; /// the default value defined in D, but as a string, if present

	// for radio and select boxes
	string[] options; /// possible options for selects
	string[] optionValues; ///.

	Element function(Document, string) makeFormElement;
}

// these are all filthy hacks

template isEnum(alias T) if(is(T)) {
	static if (is(T == enum))
		enum bool isEnum = true;
	else
		enum bool isEnum = false;
}

// WTF, shouldn't is(T == xxx) already do this?
template isEnum(T) if(!is(T)) {
	enum bool isEnum = false;
}

template isStruct(alias T) if(is(T)) {
	static if (is(T == struct))
		enum bool isStruct = true;
	else
		enum bool isStruct = false;
}

// WTF
template isStruct(T) if(!is(T)) {
	enum bool isStruct = false;
}


template isApiObject(alias T) if(is(T)) {
	static if (is(T : ApiObject))
		enum bool isApiObject = true;
	else
		enum bool isApiObject = false;
}

// WTF
template isApiObject(T) if(!is(T)) {
	enum bool isApiObject = false;
}

template isApiProvider(alias T) if(is(T)) {
	static if (is(T : ApiProvider))
		enum bool isApiProvider = true;
	else
		enum bool isApiProvider = false;
}

// WTF
template isApiProvider(T) if(!is(T)) {
	enum bool isApiProvider = false;
}


template Passthrough(T) {
	T Passthrough;
}

template PassthroughType(T) {
	alias T PassthroughType;
}

// sets up the reflection object. now called automatically so you probably don't have to mess with it
immutable(ReflectionInfo*) prepareReflection(alias PM)(PM instantiation) if(is(PM : ApiProvider) || is(PM: ApiObject) ) {
	return prepareReflectionImpl!(PM, PM)(instantiation);
}

// FIXME: this doubles the compile time and can add megabytes to the executable.
immutable(ReflectionInfo*) prepareReflectionImpl(alias PM, alias Parent)(Parent instantiation)
	if(is(PM : WebDotDBaseType) && is(Parent : ApiProvider))
{

	assert(instantiation !is null);

	ReflectionInfo* reflection = new ReflectionInfo;
	reflection.name = PM.stringof;

	static if(is(PM: ApiObject)) {
		reflection.needsInstantiation = true;
		reflection.instantiate = delegate WebDotDBaseType(string i) {
			auto n = new PM(instantiation, i);
			return n;
		};
	} else {
		reflection.instantiation = instantiation;

		static if(!is(PM : BuiltInFunctions)) {
			auto builtins = new BuiltInFunctions(instantiation, reflection);
			instantiation.builtInFunctions = builtins;
			foreach(k, v; builtins.reflection.functions)
				reflection.functions["builtin." ~ k] = v;
		}
	}

	static if(is(PM : ApiProvider)) {{ // double because I want a new scope
		auto f = new FunctionInfo;
		f.parentObject = reflection;
		f.dispatcher = generateWrapper!(PM, "_defaultPage", PM._defaultPage)(reflection, instantiation);
		f.returnTypeIsDocument = true;
		reflection.functions["/"] = cast(immutable) f;

		/+
		// catchAll here too
		f = new FunctionInfo;
		f.parentObject = reflection;
		f.dispatcher = generateWrapper!(PM, "_catchAll", PM._catchAll)(reflection, instantiation);
		f.returnTypeIsDocument = true;
		reflection.functions["/_catchAll"] = cast(immutable) f;
		+/
	}}

	// derivedMembers is changed from allMembers
	foreach(member; __traits(derivedMembers, PM)) {
	static if(member[0] != '_') {
		// FIXME: the filthiest of all hacks...
		static if(!__traits(compiles, 
			!is(typeof(__traits(getMember, PM, member)) == function) &&
			isEnum!(__traits(getMember, PM, member))))
		continue; // must be a data member or something...
		else
		// DONE WITH FILTHIEST OF ALL HACKS

		//if(member.length == 0)
		//	continue;
		static if(
			!is(typeof(__traits(getMember, PM, member)) == function) &&
			isEnum!(__traits(getMember, PM, member))
		) {
			EnumInfo i;
			i.name = member;
			foreach(m; __traits(allMembers, __traits(getMember, PM, member))) {
				i.names  ~= m;
				i.values ~= cast(int) __traits(getMember, __traits(getMember, PM, member), m);
			}

			reflection.enums[member] = i;

		} else static if(
			!is(typeof(__traits(getMember, PM, member)) == function) &&
			isStruct!(__traits(getMember, PM, member))
		) {
			StructInfo i;
			i.name = member;

			typeof(Passthrough!(__traits(getMember, PM, member))) s;
			foreach(idx, m; s.tupleof) {
				StructMemberInfo mem;

				mem.name = s.tupleof[idx].stringof[2..$];
				mem.staticType = typeof(m).stringof;

				mem.defaultValue = null; // FIXME

				i.members ~= mem;
			}

			reflection.structs[member] = i;
		} else static if(
			is(typeof(__traits(getMember, PM, member)) == function)
				&&
				(
				member.length < 5 ||
				(
				member[$ - 5 .. $] != "_Page" &&
				member[$ - 5 .. $] != "_Form") &&
				!(member.length > 16 && member[$ - 16 .. $] == "_PermissionCheck")
		)) {
			FunctionInfo* f = new FunctionInfo;
			ParameterTypeTuple!(__traits(getMember, PM, member)) fargs;

			f.returnType = ReturnType!(__traits(getMember, PM, member)).stringof;
			f.returnTypeIsDocument = is(ReturnType!(__traits(getMember, PM, member)) : Document);
			f.returnTypeIsElement = is(ReturnType!(__traits(getMember, PM, member)) : Element);

			f.parentObject = reflection;

			f.name = toUrlName(member);
			f.originalName = member;

			assert(instantiation !is null);
			f.dispatcher = generateWrapper!(PM, member, __traits(getMember, PM, member))(reflection, instantiation);

			//f.uriPath = f.originalName;

			auto namesAndDefaults = parameterInfoImpl!(__traits(getMember, PM, member));
			auto names = namesAndDefaults[0];
			auto defaults = namesAndDefaults[1];
			assert(names.length == defaults.length);

			foreach(idx, param; fargs) {
				if(idx >= names.length)
					assert(0, to!string(idx) ~ " " ~ to!string(names));

				Parameter p = reflectParam!(typeof(param))();

				p.name = names[idx];
				auto d = defaults[idx];
				p.defaultValue = d == "null" ? "" : d;
				p.hasDefault = d.length > 0;

				f.parameters ~= p;
			}

			static if(__traits(hasMember, PM, member ~ "_Form")) {
				f.createForm = &__traits(getMember, instantiation, member ~ "_Form");
			}

			reflection.functions[f.name] = cast(immutable) (f);
			// also offer the original name if it doesn't
			// conflict
			//if(f.originalName !in reflection.functions)
			reflection.functions[f.originalName] = cast(immutable) (f);
		}
		else static if(
			!is(typeof(__traits(getMember, PM, member)) == function) &&
			isApiObject!(__traits(getMember, PM, member))
		) {
			reflection.objects[member] = prepareReflectionImpl!(
				__traits(getMember, PM, member), Parent)
				(instantiation);
		} else static if( // child ApiProviders are like child modules
			!is(typeof(__traits(getMember, PM, member)) == function) &&
			isApiProvider!(__traits(getMember, PM, member))
		) {
			PassthroughType!(__traits(getMember, PM, member)) i;
			static if(__traits(compiles, i = new typeof(i)(instantiation)))
				i = new typeof(i)(instantiation);
			else
				i = new typeof(i)();
			auto r = prepareReflectionImpl!(__traits(getMember, PM, member), typeof(i))(i);
			i.reflection = cast(immutable) r;
			reflection.objects[member] = r;
			if(toLower(member) !in reflection.objects) // web filenames are often lowercase too
				reflection.objects[member.toLower] = r;
		}
	}
	}

	return cast(immutable) reflection;
}

Parameter reflectParam(param)() {
	Parameter p;

	p.staticType = param.stringof;

	static if( __traits(compiles, p.makeFormElement = &(param.makeFormElement))) {
		p.makeFormElement = &(param.makeFormElement);
	} else static if( __traits(compiles, PM.makeFormElement!(param)(null, null))) {
		alias PM.makeFormElement!(param) LOL;
		p.makeFormElement = &LOL;
	} else static if( is( param == enum )) {
		p.type = "select";

		foreach(opt; __traits(allMembers, param)) {
			p.options ~= opt;
			p.optionValues ~= to!string(__traits(getMember, param, opt));
		}
	} else static if (is(param == bool)) {
		p.type = "checkbox";
	} else static if (is(Unqual!(param) == Cgi.UploadedFile)) {
		p.type = "file";
	} else static if(is(Unqual!(param) == Text)) {
		p.type = "textarea";
	} else {
		p.type = "text";
	}

	return p;
}

struct CallInfo {
	string objectIdentifier;
	immutable(FunctionInfo)* func;
	void delegate(Document)[] postProcessors;
}

class NonCanonicalUrlException : Exception {
	this(CanonicalUrlOption option, string properUrl = null) {
		this.howToFix = option;
		this.properUrl = properUrl;
		super("The given URL needs this fix: " ~ to!string(option) ~ " " ~ properUrl);
	}

	CanonicalUrlOption howToFix;
	string properUrl;
}

enum CanonicalUrlOption {
	cutTrailingSlash,
	addTrailingSlash
}


CallInfo parseUrl(in ReflectionInfo* reflection, string url, string defaultFunction, in bool hasTrailingSlash) {
	CallInfo info;

	if(url.length && url[0] == '/')
		url = url[1 .. $];

	if(reflection.needsInstantiation) {
		// FIXME: support object identifiers that span more than one slash... maybe
		auto idx = url.indexOf("/");
		if(idx != -1) {
			info.objectIdentifier = url[0 .. idx];
			url = url[idx + 1 .. $];
		} else {
			info.objectIdentifier = url;
			url = null;
		}
	}

	string name;
	auto idx = url.indexOf("/");
	if(idx != -1) {
		name = url[0 .. idx];
		url = url[idx + 1 .. $];
	} else {
		name = url;
		url = null;
	}

	bool usingDefault = false;
	if(name.length == 0) {
		name = defaultFunction;
		usingDefault = true;
		if(name !in reflection.functions)
			name = "/"; // should call _defaultPage
	}

	if(reflection.instantiation !is null)
		info.postProcessors ~= &(reflection.instantiation._postProcess);

	if(name in reflection.functions) {
		info.func = reflection.functions[name];

		// if we're using a default thing, we need as slash on the end so relative links work
		if(usingDefault) {
			if(!hasTrailingSlash)
				throw new NonCanonicalUrlException(CanonicalUrlOption.addTrailingSlash);
		} else {
			if(hasTrailingSlash)
				throw new NonCanonicalUrlException(CanonicalUrlOption.cutTrailingSlash);
		}
	}

	if(name in reflection.objects) {
		info = parseUrl(reflection.objects[name], url, defaultFunction, hasTrailingSlash);
	}

	return info;
}

/// If you're not using FancyMain, this is the go-to function to do most the work.
/// instantiation should be an object of your ApiProvider type.
/// pathInfoStartingPoint is used to make a slice of it, incase you already consumed part of the path info before you called this.

void run(Provider)(Cgi cgi, Provider instantiation, size_t pathInfoStartingPoint = 0) if(is(Provider : ApiProvider)) {
	assert(instantiation !is null);

	if(instantiation.reflection is null) {
		instantiation.reflection = prepareReflection!(Provider)(instantiation);
		instantiation.cgi = cgi;
		instantiation._initialize();
		// FIXME: what about initializing child objects?
	}

	auto reflection = instantiation.reflection;
	instantiation._baseUrl = cgi.scriptName ~ cgi.pathInfo[0 .. pathInfoStartingPoint];

	// everything assumes the url isn't empty...
	if(cgi.pathInfo.length < pathInfoStartingPoint + 1) {
		cgi.setResponseLocation(cgi.scriptName ~ cgi.pathInfo ~ "/" ~ (cgi.queryString.length ? "?" ~ cgi.queryString : ""));
		return;
	}

	// kinda a hack, but this kind of thing should be available anyway
	string funName = cgi.pathInfo[pathInfoStartingPoint + 1..$];
	if(funName == "functions.js") {
		cgi.gzipResponse = true;
		cgi.setResponseContentType("text/javascript");
		cgi.write(makeJavascriptApi(reflection, replace(cast(string) cgi.requestUri, "functions.js", "")), true);
		cgi.close();
		return;
	}
	if(funName == "styles.css") {
		cgi.gzipResponse = true;
		cgi.setResponseContentType("text/css");
		cgi.write(instantiation.stylesheet(), true);
		cgi.close();
		return;
	}

	CallInfo info;

	try
		info = parseUrl(reflection, cgi.pathInfo[pathInfoStartingPoint + 1 .. $], to!string(cgi.requestMethod), cgi.pathInfo[$-1] == '/');
	catch(NonCanonicalUrlException e) {
		final switch(e.howToFix) {
			case CanonicalUrlOption.cutTrailingSlash:
				cgi.setResponseLocation(cgi.scriptName ~ cgi.pathInfo[0 .. $ - 1] ~
					(cgi.queryString.length ? ("?" ~ cgi.queryString) : ""));
			break;
			case CanonicalUrlOption.addTrailingSlash:
				cgi.setResponseLocation(cgi.scriptName ~ cgi.pathInfo ~ "/" ~
					(cgi.queryString.length ? ("?" ~ cgi.queryString) : ""));
			break;
		}

		return;
	}

	auto fun = info.func;
	auto instantiator = info.objectIdentifier;

	Envelope result;
	result.userData = cgi.request("passedThroughUserData");

	auto envelopeFormat = cgi.request("envelopeFormat", "document");

	WebDotDBaseType base = instantiation;
	WebDotDBaseType realObject = instantiation;
	if(instantiator.length == 0)
	if(fun !is null && fun.parentObject !is null && fun.parentObject.instantiation !is null)
		realObject = fun.parentObject.instantiation;

	// FIXME
	if(cgi.pathInfo.indexOf("builtin.") != -1 && instantiation.builtInFunctions !is null)
		base = instantiation.builtInFunctions;

	try {
		if(fun is null) {
			auto d = instantiation._catchallEntry(
				cgi.pathInfo[pathInfoStartingPoint + 1..$],
				funName,
				"");

			result.success = true;

			if(d !is null) {
				auto doc = cast(Document) d;
				if(doc)
					instantiation._postProcess(doc);

				cgi.setResponseContentType(d.contentType());
				cgi.write(d.getData(), true);
			}

			// we did everything we need above...
			envelopeFormat = "no-processing";
			goto do_nothing_else;
		}

		assert(fun !is null);
		assert(fun.dispatcher !is null);
		assert(cgi !is null);


		if(instantiator.length) {
			assert(fun !is null);
			assert(fun.parentObject !is null);
			assert(fun.parentObject.instantiate !is null);
			realObject = fun.parentObject.instantiate(instantiator);
		}


		result.type = fun.returnType;

		string format = cgi.request("format", reflection.defaultOutputFormat);
		string secondaryFormat = cgi.request("secondaryFormat", "");
		if(secondaryFormat.length == 0) secondaryFormat = null;

		JSONValue res;

		// FIXME: hackalicious garbage. kill.
		string[][string] want = cast(string[][string]) (cgi.requestMethod == Cgi.RequestMethod.POST ? cgi.postArray : cgi.getArray);
		version(fb_inside_hack) {
			if(cgi.referrer.indexOf("apps.facebook.com") != -1) {
				auto idx = cgi.referrer.indexOf("?");
				if(idx != -1 && cgi.referrer[idx + 1 .. $] != cgi.queryString) {
					// so fucking broken
					cgi.setResponseLocation(cgi.scriptName ~ cgi.pathInfo ~ cgi.referrer[idx .. $]);
					return;
				}
			}
			if(cgi.requestMethod == Cgi.RequestMethod.POST) {
				foreach(k, v; cgi.getArray)
					want[k] = cast(string[]) v;
				foreach(k, v; cgi.postArray)
					want[k] = cast(string[]) v;
			}
		}

		realObject.cgi = cgi;
		res = fun.dispatcher(cgi, realObject, want, format, secondaryFormat);

				//if(cgi)
				//	cgi.setResponseContentType("application/json");
		result.success = true;
		result.result = res;

		do_nothing_else: {}
	}
	catch (Throwable e) {
		result.success = false;
		result.errorMessage = e.msg;
		result.type = e.classinfo.name;
		debug result.dFullString = e.toString();

		if(envelopeFormat == "document" || envelopeFormat == "html") {
			auto ipe = cast(InsufficientParametersException) e;
			if(ipe !is null) {
				assert(fun !is null);
				Form form;
				 if(fun.createForm !is null) {
					// go ahead and use it to make the form page
					auto doc = fun.createForm(cgi.requestMethod == Cgi.RequestMethod.POST ? cgi.post : cgi.get);

					form = doc.requireSelector!Form("form.created-by-create-form, form.automatic-form, form");
				} else {
					Parameter[] params = (cast(Parameter[])fun.parameters).dup;
					foreach(i, p; fun.parameters) {
						string value = "";
						if(p.name in cgi.get)
							value = cgi.get[p.name];
						if(p.name in cgi.post)
							value = cgi.post[p.name];
						params[i].value = value;
					}

					form = createAutomaticForm(new Document("<html></html>", true, true), fun);// params, beautify(fun.originalName));
					foreach(k, v; cgi.get)
						form.setValue(k, v);

					instantiation.addCsrfTokens(form);
					form.setValue("envelopeFormat", envelopeFormat);

					auto n = form.getElementById("function-name");
					if(n)
						n.innerText = beautify(fun.originalName);

					// FIXME: I like having something, but it needs to not
					// show it on the first user load.
					// form.prependChild(Element.make("p", ipe.msg));
				}

				assert(form !is null);

				foreach(k, v; cgi.get)
					form.setValue(k, v); // carry what we have for params over

				result.result.str = form.toString();
			} else {
				auto fourOhFour = cast(NoSuchPageException) e;
				if(fourOhFour !is null)
					cgi.setResponseStatus("404 File Not Found");

				if(instantiation._errorFunction !is null) {
					auto document = instantiation._errorFunction(e);
					if(document is null)
						goto gotnull;
					result.result.str = (document.toString());
				} else {
				gotnull:
					auto code = Element.make("div");
					code.addClass("exception-error-message");
					code.addChild("p", e.msg);
					debug code.addChild("pre", e.toString());

					result.result.str = (code.toString());
				}
			}
		}
	} finally {
		switch(envelopeFormat) {
			case "no-processing":
				break;
			case "redirect":
				auto redirect = cgi.request("_arsd_redirect_location", cgi.referrer);

				// FIXME: is this safe? it'd make XSS super easy
				// add result to url

				if(!result.success)
					goto case "none";

				cgi.setResponseLocation(redirect, false);
			break;
			case "json":
				// this makes firefox ugly
				//cgi.setResponseContentType("application/json");
				auto json = toJsonValue(result);
				cgi.write(toJSON(&json), true);
			break;
			case "none":
				cgi.setResponseContentType("text/plain");

				if(result.success) {
					if(result.result.type == JSON_TYPE.STRING) {
						cgi.write(result.result.str, true);
					} else {
						cgi.write(toJSON(&result.result), true);
					}
				} else {
					cgi.write(result.errorMessage, true);
				}
			break;
			case "document":
			case "html":
			default:
				cgi.setResponseContentType("text/html; charset=utf-8");

				if(result.result.type == JSON_TYPE.STRING) {
					auto returned = result.result.str;

					if(envelopeFormat != "html") {
						Document document;
						if(result.success && fun !is null && fun.returnTypeIsDocument && returned.length) {
							// probably not super efficient...
							document = new TemplatedDocument(returned);
						} else {
							auto e = instantiation._getGenericContainer();
							document = e.parentDocument;
							// FIXME: a wee bit slow, esp if func return element
							e.innerHTML = returned;
							if(fun !is null)
							e.setAttribute("data-from-function", fun.originalName);
						}

						if(document !is null) {
							if(envelopeFormat == "document") {
								// forming a nice chain here...
								// FIXME: this isn't actually a nice chain!
								bool[void delegate(Document)] run;

								auto postProcessors = info.postProcessors;
								if(base !is instantiation)
									postProcessors ~= &(instantiation._postProcess);
								postProcessors ~= &(base._postProcess);
								foreach(pp; postProcessors) {
									if(pp in run)
										continue;
									run[pp] = true;
									pp(document);
								}
							}

							returned = document.toString;
						}
					}

					cgi.write(returned, true);
				} else
					cgi.write(htmlEntitiesEncode(toJSON(&result.result)), true);
			break;
		}

		cgi.close();
	}
}

class BuiltInFunctions : ApiProvider {
	const(ReflectionInfo)* workingFor;
	ApiProvider basedOn;
	this(ApiProvider basedOn, in ReflectionInfo* other) {
		this.basedOn = basedOn;
		workingFor = other;
		if(this.reflection is null)
			this.reflection = prepareReflection!(BuiltInFunctions)(this);

		assert(this.reflection !is null);
	}

	Form getAutomaticForm(string method) {
		if(method !in workingFor.functions)
			throw new Exception("no such method " ~ method);
		auto f = workingFor.functions[method];

		Form form;
		if(f.createForm !is null) {
			form = f.createForm(null).requireSelector!Form("form");
		} else
			form = createAutomaticForm(new Document("<html></html>", true, true), f);
		auto idx = basedOn.cgi.requestUri.indexOf("builtin.getAutomaticForm");
		if(idx == -1)
			idx = basedOn.cgi.requestUri.indexOf("builtin.get-automatic-form");
		assert(idx != -1);
		form.action = basedOn.cgi.requestUri[0 .. idx] ~ form.action; // make sure it works across the site

		return form;
	}
}

	// what about some built in functions?
		/+
		// Built-ins
		// Basic integer operations
		builtin.opAdd
		builtin.opSub
		builtin.opMul
		builtin.opDiv

		// Basic array operations
		builtin.opConcat 			// use to combine calls easily
		builtin.opIndex
		builtin.opSlice
		builtin.length

		// Basic floating point operations
		builtin.round
		builtin.floor
		builtin.ceil

		// Basic object operations
		builtin.getMember

		// Basic functional operations
		builtin.filter 				// use to slice down on stuff to transfer
		builtin.map 				// call a server function on a whole array
		builtin.reduce

		// Access to the html items
		builtin.getAutomaticForm(method)
		+/


/// fancier wrapper to cgi.d's GenericMain - does most the work for you, so you can just write your class and be done with it
/// Note it creates a session for you too, and will write to the disk - a csrf token. Compile with -version=no_automatic_session
/// to disable this.
mixin template FancyMain(T, Args...) {
	mixin CustomCgiFancyMain!(Cgi, T, Args);
}


/// Like FancyMain, but you can pass a custom subclass of Cgi
mixin template CustomCgiFancyMain(CustomCgi, T, Args...) if(is(CustomCgi : Cgi)) {
	void fancyMainFunction(Cgi cgi) { //string[] args) {
//		auto cgi = new Cgi;

		// there must be a trailing slash for relative links..
		if(cgi.pathInfo.length == 0) {
			cgi.setResponseLocation(cgi.requestUri ~ "/");
			cgi.close();
			return;
		}

		// FIXME: won't work for multiple objects
		T instantiation = new T();
		auto reflection = prepareReflection!(T)(instantiation);

		version(no_automatic_session) {}
		else {
			auto session = new Session(cgi);
			scope(exit) session.commit();
			instantiation.session = session;
		}

		run(cgi, instantiation);
/+
		if(args.length > 1) {
			string[string][] namedArgs;
			foreach(arg; args[2..$]) {
				auto lol = arg.indexOf("=");
				if(lol == -1)
					throw new Exception("use named args for all params");
				//namedArgs[arg[0..lol]] = arg[lol+1..$]; // FIXME
			}

			if(!(args[1] in reflection.functions)) {
				throw new Exception("No such function");
			}

			//writefln("%s", reflection.functions[args[1]].dispatcher(null, namedArgs, "string"));
		} else {
+/
//		}		
	}

	mixin CustomCgiMain!(CustomCgi, fancyMainFunction, Args);
}

/// Given a function from reflection, build a form to ask for it's params
Form createAutomaticForm(Document document, in FunctionInfo* func, string[string] fieldTypes = null) {
	return createAutomaticForm(document, func.name, func.parameters, beautify(func.originalName), "POST", fieldTypes);
}

/// ditto
// FIXME: should there be something to prevent the pre-filled options from url? It's convenient but
// someone might use it to trick people into submitting badness too. I'm leaning toward meh.
Form createAutomaticForm(Document document, string action, in Parameter[] parameters, string submitText = "Submit", string method = "POST", string[string] fieldTypes = null) {
	auto form = cast(Form) Element.make("form");
	form.parentDocument = document;
	form.addClass("automatic-form");

	form.action = action;

	assert(form !is null);
	form.method = method;


	auto fieldset = form.addChild("fieldset");
	auto legend = fieldset.addChild("legend", submitText);

	auto table = cast(Table) fieldset.addChild("table");
	assert(table !is null);

	table.addChild("tbody");

	static int count = 0;

	foreach(param; parameters) {
		Element input;

		if(param.makeFormElement !is null) {
			input = param.makeFormElement(document, param.name);
			goto gotelement;
		}

		string type = param.type;
		if(param.name in fieldTypes)
			type = fieldTypes[param.name];
		
		if(type == "select") {
			input = Element.make("select");

			foreach(idx, opt; param.options) {
				auto option = Element.make("option");
				option.name = opt;
				option.value = param.optionValues[idx];

				option.innerText = beautify(opt);

				if(option.value == param.value)
					option.selected = "selected";

				input.appendChild(option);
			}

			input.name = param.name;
		} else if (type == "radio") {
			assert(0, "FIXME");
		} else {
			if(type.startsWith("textarea")) {
				input = Element.make("textarea");
				input.name = param.name;
				input.innerText = param.value;

				input.rows = "7";

				auto idx = type.indexOf("-");
				if(idx != -1) {
					idx++;
					input.rows = type[idx .. $];
				}
			} else {
				input = Element.make("input");

				// hack to support common naming convention
				if(type == "text" && param.name.toLower.indexOf("password") != -1)
					input.type = "password";
				else
					input.type = type;
				input.name = param.name;
				input.value = param.value;

				if(type == "file") {
					form.method = "POST";
					form.enctype = "multipart/form-data";
				}
			}
		}

		gotelement:

		string n = param.name ~ "_auto-form-" ~ to!string(count);

		input.id = n;

		if(type == "hidden") {
			form.appendChild(input);
		} else {
			auto th = Element.make("th");
			auto label = Element.make("label");
			label.setAttribute("for", n); 
			label.innerText = beautify(param.name) ~ ": ";
			th.appendChild(label);

			table.appendRow(th, input);
		}

		count++;
	}

	auto fmt = Element.make("select");
	fmt.name = "format";
	fmt.addChild("option", "html").setAttribute("value", "html");
	fmt.addChild("option", "table").setAttribute("value", "table");
	fmt.addChild("option", "json").setAttribute("value", "json");
	fmt.addChild("option", "string").setAttribute("value", "string");
	auto th = table.th("");
	th.addChild("label", "Format:");

	table.appendRow(th, fmt).className = "format-row";


	auto submit = Element.make("input");
	submit.value = submitText;
	submit.type = "submit";

	table.appendRow(Html("&nbsp;"), submit);

//	form.setValue("format", reflection.defaultOutputFormat);

	return form;
}


/* *
 * Returns the parameter names of the given function
 * 
 * Params:
 *     func = the function alias to get the parameter names of
 *     
 * Returns: an array of strings containing the parameter names 
 */
/+
string parameterNamesOf( alias fn )( ) {
    string fullName = typeof(&fn).stringof;

    int pos = fullName.lastIndexOf( ')' );
    int end = pos;
    int count = 0;
    do {
        if ( fullName[pos] == ')' ) {
            count++;
        } else if ( fullName[pos] == '(' ) {
            count--;
        }
        pos--;
    } while ( count > 0 );

    return fullName[pos+2..end];
}
+/

 
template parameterNamesOf (alias func) {
        const parameterNamesOf = parameterInfoImpl!(func)[0];
}

// FIXME: I lost about a second on compile time after adding support for defaults :-(
template parameterDefaultsOf (alias func) {
        const parameterDefaultsOf = parameterInfoImpl!(func)[1];
}

bool parameterHasDefault(alias func)(int p) {
        auto a = parameterDefaultsOf!(func);
	if(a.length == 0)
		return false;
	return a[p].length > 0;
}

string parameterDefaultOf (alias func)(int paramNum) {
        auto a = parameterDefaultsOf!(func);
	return a[paramNum];
}

sizediff_t indexOfNew(string s, char a) {
	foreach(i, c; s)
		if(c == a)
			return i;
	return -1;
}

sizediff_t lastIndexOfNew(string s, char a) {
	for(sizediff_t i = s.length; i > 0; i--)
		if(s[i - 1] == a)
			return i - 1;
	return -1;
}
 

// FIXME: a problem here is the compiler only keeps one stringof
// for a particular type
//
// so if you have void a(string a, string b); and void b(string b, string c),
// both a() and b() will show up as params == ["a", "b"]!
//
// 
private string[][2] parameterInfoImpl (alias func) ()
{
        string funcStr = typeof(func).stringof; // this might fix the fixme above...
						// it used to be typeof(&func).stringof

        auto start = funcStr.indexOfNew('(');
        auto end = funcStr.lastIndexOfNew(')');

	assert(start != -1);
	assert(end != -1);
        
        const firstPattern = ' ';
        const secondPattern = ',';
        
        funcStr = funcStr[start + 1 .. end];
        
        if (funcStr == "") // no parameters
                return [null, null];
                
        funcStr ~= secondPattern;
        
        string token;
        string[] arr;
        
        foreach (c ; funcStr)
        {               
                if (c != firstPattern && c != secondPattern)
                        token ~= c;
                
                else
                {                       
                        if (token)
                                arr ~= token;
                        
                        token = null;
                }                       
        }
        
        if (arr.length == 1)
                return [arr, [""]];
        
        string[] result;
	string[] defaults;
        bool skip = false;

	bool gettingDefault = false;

	string currentName = "";
	string currentDefault = "";
        
        foreach (str ; arr)
        {
		if(str == "=") {
			gettingDefault = true;
			continue;
		}

		if(gettingDefault) {
			assert(str.length);
			currentDefault = str;
			gettingDefault = false;
			continue;
		}

                skip = !skip;
                
                if (skip) {
			if(currentName.length) {
				result ~= currentName;
				defaults ~= currentDefault;
				currentName = null;
			}
                        continue;
		}

		currentName = str;
        }

	if(currentName !is null) {
		result ~= currentName;
		defaults ~= currentDefault;
	}

	assert(result.length == defaults.length);
        
        return [result, defaults];
}
/////////////////////////////////

/// Formats any given type as HTML. In custom types, you can write Element makeHtmlElement(Document document = null); to provide
/// custom html. (the default arg is important - it won't necessarily pass a Document in at all, and since it's silently duck typed,
/// not having that means your function won't be called and you can be left wondering WTF is going on.)

/// Alternatively, static Element makeHtmlArray(T[]) if you want to make a whole list of them. By default, it will just concat a bunch of individual
/// elements though.
string toHtml(T)(T a) {
	string ret;

	static if(is(T == typeof(null)))
		ret = null;
	else static if(is(T : Document)) {
		if(a is null)
			ret = null;
		else
			ret = a.toString();
	} else
	static if(isArray!(T) && !isSomeString!(T)) {
		static if(__traits(compiles, typeof(T[0]).makeHtmlArray(a)))
			ret = to!string(typeof(T[0]).makeHtmlArray(a));
		else
		foreach(v; a)
			ret ~= toHtml(v);
	} else static if(is(T : Element))
		ret = a.toString();
	else static if(__traits(compiles, a.makeHtmlElement().toString()))
		ret = a.makeHtmlElement().toString();
	else static if(is(T == Html))
		ret = a.source;
	else {
		auto str = to!string(a);
		if(str.indexOf("\t") == -1)
			ret = std.array.replace(htmlEntitiesEncode(str), "\n", "<br />\n");
		else // if there's tabs in it, output it as code or something; the tabs are probably there for a reason.
			ret = "<pre>" ~ htmlEntitiesEncode(str) ~ "</pre>";
	}

	return ret;
}

/// Translates a given type to a JSON string.

/// TIP: if you're building a Javascript function call by strings, toJson("your string"); will build a nicely escaped string for you of any type.
string toJson(T)(T a) {
	auto v = toJsonValue(a);
	return toJSON(&v);
}

// FIXME: are the explicit instantiations of this necessary?
/// like toHtml - it makes a json value of any given type.

/// It can be used generically, or it can be passed an ApiProvider so you can do a secondary custom
/// format. (it calls api.formatAs!(type)(typeRequestString)). Why would you want that? Maybe
/// your javascript wants to do work with a proper object,but wants to append it to the document too.
/// Asking for json with secondary format = html means the server will provide both to you.

/// Implement JSONValue makeJsonValue() in your struct or class to provide 100% custom Json.

/// Elements from DOM are turned into JSON strings of the element's html.
JSONValue toJsonValue(T, R = ApiProvider)(T a, string formatToStringAs = null, R api = null)
	if(is(R : ApiProvider))
{
	JSONValue val;
	static if(is(T == typeof(null)) || is(T == void*)) {
		/* void* goes here too because we don't know how to make it work... */
		val.type = JSON_TYPE.NULL;
	} else static if(is(T == JSONValue)) {
		val = a;
	} else static if(__traits(compiles, val = a.makeJsonValue())) {
		val = a.makeJsonValue();
	// FIXME: free function to emulate UFCS?

	// FIXME: should we special case something like struct Html?
	} else static if(is(T : Element)) {
		if(a is null) {
			val.type = JSON_TYPE.NULL;
		} else {
			val.type = JSON_TYPE.STRING;
			val.str = a.toString();
		}
	} else static if(isIntegral!(T)) {
		val.type = JSON_TYPE.INTEGER;
		val.integer = to!long(a);
	} else static if(isFloatingPoint!(T)) {
		val.type = JSON_TYPE.FLOAT;
		val.floating = to!real(a);
	} else static if(isPointer!(T)) {
		if(a is null) {
			val.type = JSON_TYPE.NULL;
		} else {
			val = toJsonValue!(typeof(*a), R)(*a, formatToStringAs, api);
		}
	} else static if(is(T == bool)) {
		if(a == true)
			val.type = JSON_TYPE.TRUE;
		if(a == false)
			val.type = JSON_TYPE.FALSE;
	} else static if(isSomeString!(T)) {
		val.type = JSON_TYPE.STRING;
		val.str = to!string(a);
	} else static if(isAssociativeArray!(T)) {
		val.type = JSON_TYPE.OBJECT;
		foreach(k, v; a) {
			val.object[to!string(k)] = toJsonValue!(typeof(v), R)(v, formatToStringAs, api);
		}
	} else static if(isArray!(T)) {
		val.type = JSON_TYPE.ARRAY;
		val.array.length = a.length;
		foreach(i, v; a) {
			val.array[i] = toJsonValue!(typeof(v), R)(v, formatToStringAs, api);
		}
	} else static if(is(T == struct)) { // also can do all members of a struct...
		val.type = JSON_TYPE.OBJECT;

		foreach(i, member; a.tupleof) {
			string name = a.tupleof[i].stringof[2..$];
			static if(a.tupleof[i].stringof[2] != '_')
				val.object[name] = toJsonValue!(typeof(member), R)(member, formatToStringAs, api);
		}
			// HACK: bug in dmd can give debug members in a non-debug build
			//static if(__traits(compiles, __traits(getMember, a, member)))
	} else { /* our catch all is to just do strings */
		val.type = JSON_TYPE.STRING;
		val.str = to!string(a);
		// FIXME: handle enums
	}


	// don't want json because it could recurse
	if(val.type == JSON_TYPE.OBJECT && formatToStringAs !is null && formatToStringAs != "json") {
		JSONValue formatted;
		formatted.type = JSON_TYPE.STRING;

		formatAs!(T, R)(a, formatToStringAs, api, &formatted, null /* only doing one level of special formatting */);
		assert(formatted.type == JSON_TYPE.STRING);
		val.object["formattedSecondarily"] = formatted;
	}

	return val;
}

/+
Document toXml(T)(T t) {
	auto xml = new Document;
	xml.parse(emptyTag(T.stringof), true, true);
	xml.prolog = `<?xml version="1.0" encoding="UTF-8" ?>` ~ "\n";

	xml.root = toXmlElement(xml, t);
	return xml;
}

Element toXmlElement(T)(Document document, T t) {
	Element val;
	static if(is(T == Document)) {
		val = t.root;
	//} else static if(__traits(compiles, a.makeJsonValue())) {
	//	val = a.makeJsonValue();
	} else static if(is(T : Element)) {
		if(t is null) {
			val = document.createElement("value");
			val.innerText = "null";
			val.setAttribute("isNull", "true");
		} else
			val = t;
	} else static if(is(T == void*)) {
			val = document.createElement("value");
			val.innerText = "null";
			val.setAttribute("isNull", "true");
	} else static if(isPointer!(T)) {
		if(t is null) {
			val = document.createElement("value");
			val.innerText = "null";
			val.setAttribute("isNull", "true");
		} else {
			val = toXmlElement(document, *t);
		}
	} else static if(isAssociativeArray!(T)) {
		val = document.createElement("value");
		foreach(k, v; t) {
			auto e = document.createElement(to!string(k));
			e.appendChild(toXmlElement(document, v));
			val.appendChild(e);
		}
	} else static if(isSomeString!(T)) {
		val = document.createTextNode(to!string(t));
	} else static if(isArray!(T)) {
		val = document.createElement("array");
		foreach(i, v; t) {
			auto e = document.createElement("item");
			e.appendChild(toXmlElement(document, v));
			val.appendChild(e);
		}
	} else static if(is(T == struct)) { // also can do all members of a struct...
		val = document.createElement(T.stringof);
		foreach(member; __traits(allMembers, T)) {
			if(member[0] == '_') continue; // FIXME: skip member functions
			auto e = document.createElement(member);
			e.appendChild(toXmlElement(document, __traits(getMember, t, member)));
			val.appendChild(e);
		}
	} else { /* our catch all is to just do strings */
		val = document.createTextNode(to!string(t));
		// FIXME: handle enums
	}

	return val;
}
+/


/// throw this if your function needs something that is missing.

/// Done automatically by the wrapper function
class InsufficientParametersException : Exception {
	this(string functionName, string msg) {
		super(functionName ~ ": " ~ msg);
	}
}

/// throw this if a paramater is invalid. Automatic forms may present this to the user in a new form. (FIXME: implement that)
class InvalidParameterException : Exception {
	this(string param, string value, string expected) {
		super("bad param: " ~ param ~ ". got: " ~ value ~ ". Expected: " ~expected);
	}
}

/// convenience for throwing InvalidParameterExceptions
void badParameter(alias T)(string expected = "") {
	throw new InvalidParameterException(T.stringof, T, expected);
}

/// throw this if the user's access is denied
class PermissionDeniedException : Exception {
	this(string msg, string file = __FILE__, int line = __LINE__) {
		super(msg, file, line);
	}
}

/// throw if the request path is not found. Done automatically by the default catch all handler.
class NoSuchPageException : Exception {
	this(string msg, string file = __FILE__, int line = __LINE__) {
		super(msg, file, line);
	}
}


type fromUrlParam(type)(string ofInterest) {
	type ret;

	static if(isArray!(type) && !isSomeString!(type)) {
		// how do we get an array out of a simple string?
		// FIXME
	} else static if(__traits(compiles, ret = type.fromWebString(ofInterest))) { // for custom object handling...
		ret = type.fromWebString(ofInterest);
	} else static if(is(type : Element)) {
		auto doc = new Document(ofInterest, true, true);

		ret = doc.root;
	} else static if(is(type : Text)) {
		ret = ofInterest;
	} else static if(is(type : DateTime)) {
		ret = DateTime.fromISOString(ofInterest);
	}
	/*
	else static if(is(type : struct)) {
		static assert(0, "struct not supported yet");
	}
	*/
	else {
		// enum should be handled by this too
		ret = to!type(ofInterest);
	} // FIXME: can we support classes?

	return ret;
}

/// turns a string array from the URL into a proper D type
type fromUrlParam(type)(string[] ofInterest) {
	type ret;

	// Arrays in a query string are sent as the name repeating...
	static if(isArray!(type) && !isSomeString!(type)) {
		foreach(a; ofInterest) {
			ret ~= fromUrlParam!(ElementType!(type))(a);
		}
	} else
		ret = fromUrlParam!type(ofInterest[$-1]);

	return ret;
}

auto getMemberDelegate(alias ObjectType, string member)(ObjectType object) if(is(ObjectType : WebDotDBaseType)) {
	if(object is null)
		throw new NoSuchPageException("no such object " ~ ObjectType.stringof);
	return &__traits(getMember, object, member);
}

/// generates the massive wrapper function for each of your class' methods.
/// it is responsible for turning strings to params and return values back to strings.
WrapperFunction generateWrapper(alias ObjectType, string funName, alias f, R)(ReflectionInfo* reflection, R api)
	if(is(R: ApiProvider) && (is(ObjectType : WebDotDBaseType)) )
{
	JSONValue wrapper(Cgi cgi, WebDotDBaseType object, in string[][string] sargs, in string format, in string secondaryFormat = null) {

		JSONValue returnValue;
		returnValue.type = JSON_TYPE.STRING;

		auto instantiation = getMemberDelegate!(ObjectType, funName)(cast(ObjectType) object);

		api._initializePerCall();

		ParameterTypeTuple!(f) args;

		// Actually calling the function
		// FIXME: default parameters
		foreach(i, type; ParameterTypeTuple!(f)) {
			string name = parameterNamesOf!(f)[i];

			// We want to check the named argument first. If it's not there,
			// try the positional arguments
			string using = name;
			if(name !in sargs)
				using = "positional-arg-" ~ to!string(i);

			// FIXME: if it's a struct, we should do it's pieces independently here

			static if(is(type == bool)) {
				// bool is special cased because HTML checkboxes don't send anything if it isn't checked
				if(using in sargs) {
					if(
					sargs[using][$-1] != "false" &&
					sargs[using][$-1] != "False" &&
					sargs[using][$-1] != "FALSE" &&
					sargs[using][$-1] != "0"
					)
					args[i] = true; // FIXME: should try looking at the value
				}
				else
					args[i] = false;

				// FIXME: what if the default is true?
			} else static if(is(Unqual!(type) == Cgi.UploadedFile)) {
				if(using !in cgi.files)
					throw new InsufficientParametersException(funName, "file " ~ using ~ " is not present");
				args[i] = cast()  cgi.files[using]; // casting away const for the assignment to compile FIXME: shouldn't be needed
			} else {
				if(using !in sargs) {
					static if(parameterHasDefault!(f)(i)) {
						args[i] = mixin(parameterDefaultOf!(f)(i));
					} else {
						throw new InsufficientParametersException(funName, "arg " ~ name ~ " is not present");
					}
				} else {

					// We now check the type reported by the client, if there is one
					// Right now, only one type is supported: ServerResult, which means
					// it's actually a nested function call

					string[] ofInterest = cast(string[]) sargs[using]; // I'm changing the reference, but not the underlying stuff, so this cast is ok

					if(using ~ "-type" in sargs) {
						string reportedType = sargs[using ~ "-type"][$-1];
						if(reportedType == "ServerResult") {

							// FIXME: doesn't handle functions that return
							// compound types (structs, arrays, etc)

							ofInterest = null;

							string str = sargs[using][$-1];
							auto idx = str.indexOf("?");
							string callingName, callingArguments;
							if(idx == -1) {
								callingName = str;
							} else {
								callingName = str[0..idx];
								callingArguments = str[idx + 1 .. $];
							}

							// find it in reflection
							ofInterest ~= reflection.functions[callingName].
								dispatcher(cgi, null, decodeVariables(callingArguments), "string").str;
						}
					}


					args[i] = fromUrlParam!type(ofInterest);
				}
			}
		}

		static if(!is(ReturnType!f == void))
			ReturnType!(f) ret;
		else
			void* ret;

		static if(!is(ReturnType!f == void))
			ret = instantiation(args);
		else
			instantiation(args);

		static if(is(ReturnType!f : Element)) {
			if(ret is null)
				return returnValue; // HACK to handle null returns
			// we need to make sure that it's not called again when _postProcess(Document) is called!
			// FIXME: is this right?
			if(cgi.request("envelopeFormat", "document") != "document")
				api._postProcessElement(ret); // need to post process the element here so it works in ajax modes.
		}

		formatAs(ret, format, api, &returnValue, secondaryFormat);

		return returnValue;
	}

	return &wrapper;
}


/// This is the function called to turn return values into strings.

/// Implement a template called customFormat in your apiprovider class to make special formats.

/// Otherwise, this provides the defaults of html, table, json, etc.

/// call it like so: JSONValue returnValue; formatAs(value, this, returnValue, "type");

// FIXME: it's awkward to call manually due to the JSONValue ref thing. Returning a string would be mega nice.
string formatAs(T, R)(T ret, string format, R api = null, JSONValue* returnValue = null, string formatJsonToStringAs = null) if(is(R : ApiProvider)) {
	string retstr;
	if(api !is null) {
		static if(__traits(compiles, api.customFormat(ret, format))) {
			auto customFormatted = api.customFormat(ret, format);
			if(customFormatted !is null) {
				if(returnValue !is null)
					returnValue.str = customFormatted;
				return customFormatted;
			}
		}
	} 
	switch(format) {
		case "html":
			retstr = toHtml(ret);
			if(returnValue !is null)
				returnValue.str = retstr;
		break;
		case "string": // FIXME: this is the most expensive part of the compile! Two seconds in one of my apps.
		/+
			static if(__traits(compiles, to!string(ret))) {
				retstr = to!string(ret);
				if(returnValue !is null)
					returnValue.str = retstr;
			}
			else goto badType;
		+/
			goto badType; // FIXME
		case "json":
			assert(returnValue !is null);
			*returnValue = toJsonValue!(typeof(ret), R)(ret, formatJsonToStringAs, api);
		break;
		case "table":
			auto document = new Document("<root></root>");
			static if(__traits(compiles, structToTable(document, ret)))
			{
				retstr = structToTable(document, ret).toString();
				if(returnValue !is null)
					returnValue.str = retstr;
				break;
			}
			else
				goto badType;
		default:
			badType:
			throw new Exception("Couldn't get result as " ~ format);
	}

	return retstr;
}


private string emptyTag(string rootName) {
	return ("<" ~ rootName ~ "></" ~ rootName ~ ">");
}


/// The definition of the beastly wrapper function
alias JSONValue delegate(Cgi cgi, WebDotDBaseType, in string[][string] args, in string format, in string secondaryFormat = null) WrapperFunction;

/// tries to take a URL name and turn it into a human natural name. so get rid of slashes, capitalize, etc.
string urlToBeauty(string url) {
	string u = url.replace("/", "");

	string ret;

	bool capitalize = true;
	foreach(c; u) {
		if(capitalize) {
			ret ~= ("" ~ c).toUpper;
			capitalize = false;
		} else {
			if(c == '-') {
				ret ~= " ";
				capitalize = true;
			} else
				ret ~= c;
		}
	}

	return ret;
}

/// turns camelCase into dash-separated
string toUrlName(string name) {
	string res;
	foreach(c; name) {
		if(c >= 'a' && c <= 'z')
			res ~= c;
		else {
			res ~= '-';
			if(c >= 'A' && c <= 'Z')
				res ~= c + 0x20;
			else
				res ~= c;
		}
	}
	return res;
}

/// turns camelCase into human presentable capitalized words with spaces
string beautify(string name) {
	string n;

				// all caps names shouldn't get spaces
	if(name.length == 0 || name.toUpper() == name)
		return name;

	n ~= toUpper(name[0..1]);

	dchar last;
	foreach(dchar c; name[1..$]) {
		if((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
			if(last != ' ')
				n ~= " ";
		}

		if(c == '_')
			n ~= " ";
		else
			n ~= c;
		last = c;
	}
	return n;
}






import std.md5;
import core.stdc.stdlib;
import core.stdc.time;
import std.file;

/// meant to give a generic useful hook for sessions. kinda sucks at this point.
/// use the Session class instead. If you just construct it, the sessionId property
/// works fine. Don't set any data and it won't save any file.
deprecated string getSessionId(Cgi cgi) {
	string token; // FIXME: should this actually be static? it seems wrong
	if(token is null) {
		if("_sess_id" in cgi.cookies)
			token = cgi.cookies["_sess_id"];
		else {
			auto tmp = uniform(0, int.max);
			token = to!string(tmp);

			cgi.setCookie("_sess_id", token, /*60 * 8 * 1000*/ 0, "/", null, true);
		}
	}

	return getDigestString(cgi.remoteAddress ~ "\r\n" ~ cgi.userAgent ~ "\r\n" ~ token);
}

version(Posix) {
	static import linux = std.c.linux.linux;
}

/// Provides some persistent storage, kinda like PHP
/// But, you have to manually commit() the data back to a file.
/// You might want to put this in a scope(exit) block or something like that.
class Session {
	/// Loads the session if available, and creates one if not.
	/// May write a session id cookie to the passed cgi object.
	this(Cgi cgi, string cookieName = "_sess_id", bool useFile = true) {
		// assert(cgi.https); // you want this for best security, but I won't be an ass and require it.
		this._cookieName = cookieName;
		this.cgi = cgi;
		bool isNew = false;
		string token;
		if(cookieName in cgi.cookies && cgi.cookies[cookieName].length)
			token = cgi.cookies[cookieName];
		else {
			if("x-arsd-session-override" in cgi.requestHeaders) {
				loadSpecialSession(cgi);
				return;
			} else {
				// there is no session; make a new one.
				token = makeNewCookie();
				isNew = true;
			}
		}

		makeSessionId(token);

		if(useFile)
			reload();
		if(isNew)
			addDefaults();
	}

	/// This loads a session that the user requests, without the normal
	/// checks. The idea is to allow debugging or local request sharing.
	///
	/// It is private because you never have to call it yourself, but read on
	/// to understand how it works and some potential security concerns.
	///
	/// It loads the requested session read-only (it does not commit),
	/// if and only if the request asked for the correct hash and id.
	///
	/// If they have enough info to build the correct hash, they must
	/// already know the contents of the file, so there should be no
	/// risk of data contamination here. (A traditional session hijack
	/// is surely much easier.)
	///
	/// It is possible for them to forge a request as a particular user
	/// if they can read the file, but otherwise not write. For that reason,
	/// especially with this functionality here, it is very important for you
	/// to lock down your session files. If on a shared host, be sure each user's
	/// processes run as separate operating system users, so the file permissions
	/// set in commit() actually help you.
	///
	/// If you can't reasonably protect the session file, compile this out with
	/// -version=no_session_override and only access unauthenticated functions
	/// from other languages. They can still read your sessions, and potentially
	/// hijack it, but it will at least be a little harder.
	///
	/// Also, don't use this over the open internet at all. It's supposed
	/// to be local only. If someone sniffs the request, hijacking it
	/// becomes very easy; even easier than a normal session id since they just reply it.
	/// (you should really ssl encrypt all sessions for any real protection btw)
	private void loadSpecialSession(Cgi cgi) {
		version(no_session_override)
			throw new Exception("You cannot access sessions this way.");
		else {
			// the header goes full-session-id;file-contents-hash
			auto info = split(cgi.requestHeaders["x-arsd-session-override"], ";");

			_sessionId = info[0];
			auto hash = info[1];

			if(_sessionId.length == 0 || !std.file.exists(getFilePath())) {
				// there is no session
				_readOnly = true;
				return;
			}

			// FIXME: race condition if the session changes?
			enforce(hashToString(SHA256(readText(getFilePath()))) == hash);
			_readOnly = true;
			reload();
		}
	}

	private void addDefaults() {
		set("csrfToken", generateCsrfToken());

		// this is there to help control access to someone requesting a specific session id (helpful for debugging or local access from other languages)
		// the idea is if there's some random stuff in there that you can only know if you have access to the file, it doesn't hurt to load that
		// session, since they have to be able to read it to know this value anyway, so you aren't giving them anything they don't already have.
		set("randomRandomness", to!string(uniform(0, ulong.max)));
	}

	private string makeSessionId(string cookieToken) {
		_sessionId = hashToString(SHA256(cgi.remoteAddress ~ "\r\n" ~ cgi.userAgent ~ "\r\n" ~ cookieToken));
		return _sessionId;
	}

	private string generateCsrfToken() {
		string[string] csrf;

		csrf["key"] = to!string(uniform(0, ulong.max));
		csrf["token"] = to!string(uniform(0, ulong.max));

		return encodeVariables(csrf);
	}

	// don't forget to make the new session id and set a new csrfToken after this too.
	private string makeNewCookie() {
		auto tmp = uniform(0, ulong.max);
		auto token = to!string(tmp);
		// FIXME: path, domain?
		setLoginCookie(cgi, _cookieName, token);

		return token;
	}

	/// Kill the current session. It wipes out the disk file and memory, and
	/// changes the session ID.
	///
	/// You should do this if the user's authentication info changes
	/// at all.
	void invalidate() {
		setLoginCookie(cgi, _cookieName, "");
		clear();

		regenerateId();
	}

	/// Creates a new cookie, session id, and csrf token, deleting the old disk data.
	/// If you call commit() after doing this, it will save your existing data back to disk.
	/// (If you don't commit, the data will be lost when this object is deleted.)
	void regenerateId() {
		// we want to clean up the old file, but keep the data we have in memory.
		if(std.file.exists(getFilePath()))
			std.file.remove(getFilePath());

		// and new cookie -> new session id -> new csrf token
		makeSessionId(makeNewCookie());
		addDefaults();

		if(hasData)
			changed = true;
			
	}

	/// Clears the session data from both memory and disk.
	/// The session id is not changed by this function. To change it,
	/// use invalidate() if you want to clear data and change the ID
	/// or regenerateId() if you want to change the session ID, but not change the data.
	///
	/// Odds are, invalidate() is what you really want.
	void clear() {
		if(std.file.exists(getFilePath()))
			std.file.remove(getFilePath());
		data = null;
		_hasData = false;
		changed = false;
	}

	// FIXME: what about expiring a session id and perhaps issuing a new
	// one? They should automatically invalidate at some point.

	// Both an idle timeout and a forced reauth timeout is good to offer.
	// perhaps a helper function to do it in js too?


	// I also want some way to attach to a session if you have root
	// on the server, for convenience of debugging...

	string sessionId() const {
		return _sessionId;
	}

	bool hasData() const {
		return _hasData;
	}

	/// like opIn
	bool hasKey(string key) const {
		auto ptr = key in data;
		if(ptr is null)
			return false;
		else
			return true;
	}

	/// get/set for strings
	string opDispatch(string name)(string v = null) if(name != "popFront") {
		if(v !is null)
			set(name, v);
		if(hasKey(name))
			return get(name);
		return null;
	}

	string opIndex(string key) const {
		return get(key);
	}

	string opIndexAssign(string value, string field) {
		set(field, value);
		return value;
	}

	// FIXME: doesn't seem to work
	string* opBinary(string op)(string key)  if(op == "in") {
		return key in fields;
	}

	void set(string key, string value) {
		data[key] = value;
		_hasData = true;
		changed = true;
	}

	string get(string key) const {
		if(key !in data)
			throw new Exception("No such key in session: " ~ key);
		return data[key];
	}

	private string getFilePath() const {
		string path = getTempDirectory();
		path ~= "arsd_session_file_" ~ sessionId;

		return path;
	}

	// FIXME: there's a race condition here - if the user is using the session
	// from two windows, one might write to it as we're executing, and we won't
	// see the difference.... meaning we'll write the old data back.

	/// Discards your changes, reloading the session data from the disk file.
	void reload() {
		data = null;
		auto path = getFilePath();
		try {
			_hasData = true;
			auto json = std.file.readText(getFilePath());

			auto obj = parseJSON(json);
			enforce(obj.type == JSON_TYPE.OBJECT);
			foreach(k, v; obj.object) {
				string ret;
				final switch(v.type) {
					case JSON_TYPE.STRING:
						ret = v.str;
					break;
					case JSON_TYPE.INTEGER:
						ret = to!string(v.integer);
					break;
					case JSON_TYPE.FLOAT:
						ret = to!string(v.floating);
					break;
					case JSON_TYPE.OBJECT:
					case JSON_TYPE.ARRAY:
						enforce(0, "invalid session data");
					break;
					case JSON_TYPE.TRUE:
						ret = "true";
					break;
					case JSON_TYPE.FALSE:
						ret = "false";
					break;
					case JSON_TYPE.NULL:
						ret = null;
					break;
				}

				data[k] = ret;
			}
		} catch(Exception e) {
			// it's a bad session...
			_hasData = false;
			data = null;
			if(std.file.exists(path))
				std.file.remove(path);
		}
	}

	// FIXME: there's a race condition here - if the user is using the session
	// from two windows, one might write to it as we're executing, and we won't
	// see the difference.... meaning we'll write the old data back.

	/// Commits your changes back to disk.
	void commit(bool force = false) {
		if(_readOnly)
			return;
		if(force || changed) {
			std.file.write(getFilePath(), toJson(data));
			changed = false;
			// We have to make sure that only we can read this file,
			// since otherwise, on shared hosts, our session data might be
			// easily stolen. Note: if your shared host doesn't have different
			// users on the operating system for each user, it's still possible
			// for them to access this file and hijack your session!
			version(Posix)
				enforce(linux.chmod(toStringz(getFilePath()), octal!600) == 0, "chmod failed");
			// FIXME: ensure the file's read permissions are locked down
			// on Windows too.
		}
	}

	private string[string] data;
	private bool _hasData;
	private bool changed;
	private bool _readOnly;
	private string _sessionId;
	private string _cookieName;
	private Cgi cgi; // used to regenerate cookies, etc.

	//private Variant[string] data;
	/*
	Variant* opBinary(string op)(string key)  if(op == "in") {
		return key in data;
	}

	T get(T)(string key) {
		if(key !in data)
			throw new Exception(key ~ " not in session data");

		return data[key].coerce!T;
	}

	void set(T)(string key, T t) {
		Variant v;
		v = t;
		data[key] = t;
	}
	*/
}

/// sets a site-wide cookie, meant to simplify login code. Note: you often might not want a side wide cookie, but I usually do since my projects need single sessions across multiple thingies, hence, this.
void setLoginCookie(Cgi cgi, string name, string value) {
	cgi.setCookie(name, value, 0, "/", null, true);
}



immutable(string[]) monthNames = [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December"
];

immutable(string[]) weekdayNames = [
	"Sunday",
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday"
];


// this might be temporary
struct TemplateFilters {
	string date(string replacement, string[], in Element, string) {
		auto dateTicks = to!time_t(replacement);
		auto date = SysTime( unixTimeToStdTime(dateTicks/1_000) );
		
		auto day = date.day;
		auto year = date.year;
		auto month = monthNames[date.month];
		replacement = format("%s %d, %d", month, day, year);

		return replacement;
	}

	string uri(string replacement, string[], in Element, string) {
		return std.uri.encodeComponent(replacement);
	}

	string js(string replacement, string[], in Element, string) {
		return toJson(replacement);
	}

	static auto defaultThings() {
		string delegate(string, string[], in Element, string)[string] pipeFunctions;
		TemplateFilters filters;

		if("date" !in pipeFunctions)
			pipeFunctions["date"] = &filters.date;
		if("uri" !in pipeFunctions)
			pipeFunctions["uri"] = &filters.uri;
		if("js" !in pipeFunctions)
			pipeFunctions["js"] = &filters.js;
		return pipeFunctions;
	}
}


void applyTemplateToElement(
	Element e,
	in string[string] vars,
	in string delegate(string, string[], in Element, string)[string] pipeFunctions = TemplateFilters.defaultThings())
{

	foreach(ele; e.tree) {
		auto tc = cast(TextNode) ele;
		if(tc !is null) {
			// text nodes have no attributes, but they do have text we might replace.
			tc.contents = htmlTemplateWithData(tc.contents, vars, pipeFunctions, false);
		} else {
			auto rs = cast(RawSource) ele;
			if(rs !is null)
				rs.source = htmlTemplateWithData(rs.source, vars, pipeFunctions, true); /* FIXME: might be wrong... */
			// if it is not a text node, it has no text where templating is valid, except the attributes
			// note: text nodes have no attributes, which is why this is in the separate branch.
			foreach(k, v; ele.attributes) {
				if(k == "href" || k == "src") {
					// FIXME: HACK this should be properly context sensitive..
					v = v.replace("%7B%24", "{$");
					v = v.replace("%7D", "}");
				}
				ele.attributes[k] = htmlTemplateWithData(v, vars, pipeFunctions, false);
			}
		}
	}
}

// this thing sucks a little less now.
// set useHtml to false if you're working on internal data (such as TextNode.contents, or attribute);
// it should only be set to true if you're doing input that has already been ran through toString or something.
// NOTE: I'm probably going to change the pipe function thing a bit more, but I'm basically happy with it now.
string htmlTemplateWithData(in string text, in string[string] vars, in string delegate(string, string[], in Element, string)[string] pipeFunctions, bool useHtml) {
	if(text is null)
		return null;

	int state = 0;

	string newText = null;

	size_t nameStart;
	size_t replacementStart;
	size_t lastAppend = 0;

	string name = null;
	bool replacementPresent = false;
	string replacement = null;
	string currentPipe = null;

	foreach(i, c; text) {
		void stepHandler() {
			if(name is null)
				name = text[nameStart .. i];
			else if(nameStart != i)
				currentPipe = text[nameStart .. i];

			nameStart = i + 1;

			auto it = name in vars;
			if(it !is null) {
				replacement = *it;
				replacementPresent = true;
			}
		}

		void pipeHandler() {
			if(currentPipe is null || replacement is null)
				return;

			if(currentPipe in pipeFunctions) {
				replacement = pipeFunctions[currentPipe](replacement, null, null, null); // FIXME context
				// string, string[], in Element, string
			}

			currentPipe = null;
		}

		switch(state) {
			default: assert(0);
			case 0:
				if(c == '{') {
					replacementStart = i;
					state++;
					replacementPresent = false;
				}
			break;
			case 1:
				if(c == '$')
					state++;
				else
					state--; // not a variable
			break;
			case 2: // just started seeing a name
				if(c == '}') {
					state = 0; // empty names aren't allowed; ignore it
				} else {
					nameStart = i;
					name = null;
					state++;
				}
			break;
			case 3: // reading a name
				// the pipe operator lets us filter the text
				if(c == '|') {
					pipeHandler();
					stepHandler();
				} else if(c == '}') {
					// just finished reading it, let's do our replacement.
					pipeHandler(); // anything that was there
					stepHandler(); // might make a new pipe if the first...
					pipeHandler(); // new names/pipes since this is the last go
					if(name !is null && replacementPresent /*&& replacement !is null*/) {
						newText ~= text[lastAppend .. replacementStart];
						if(useHtml)
							replacement = htmlEntitiesEncode(replacement).replace("\n", "<br />");
						newText ~= replacement;
						lastAppend = i + 1;
						replacement = null;
					}

					state = 0;
				}
			break;
		}
	}

	if(newText is null)
		newText = text; // nothing was found, so no need to risk allocating anything...
	else
		newText ~= text[lastAppend .. $]; // make sure we have everything here

	return newText;
}

/// a specialization of Document that: a) is always in strict mode and b) provides some template variable text replacement, in addition to DOM manips. The variable text is valid in text nodes and attribute values. It takes the format of {$variable}, where variable is a key into the vars member.
class TemplatedDocument : Document {
	override string toString() const {
		if(this.root !is null)
			applyTemplateToElement(cast() this.root, vars, viewFunctions); /* FIXME: I shouldn't cast away const, since it's rude to modify an object in any toString.... but that's what I'm doing for now */

		return super.toString();
	}

	public:
		string[string] vars; /// use this to set up the string replacements. document.vars["name"] = "adam"; then in doc, <p>hellp, {$name}.</p>. Note the vars are converted lazily at toString time and are always HTML escaped.
		/// In the html templates, you can write {$varname} or {$varname|func} (or {$varname|func arg arg|func} and so on). This holds the functions available these. The TemplatedDocument constructor puts in a handful of generic ones.
		string delegate(string, string[], in Element, string)[string] viewFunctions;


		this(string src) {
			super();
			parse(src, true, true);
		}

		this() { }

		void delegate(TemplatedDocument)[] preToStringFilters;
		void delegate(ref string)[] postToStringFilters;
}

/// a convenience function to do filters on your doc and write it out. kinda useless still at this point.
void writeDocument(Cgi cgi, TemplatedDocument document) {
	foreach(f; document.preToStringFilters)
		f(document);

	auto s = document.toString();

	foreach(f; document.postToStringFilters)
		f(s);

	cgi.write(s);
}

/* Password helpers */

/// These added a dependency on arsd.sha, but hashing passwords is somewhat useful in a lot of apps so I figured it was worth it.
/// use this to make the hash to put in the database...
string makeSaltedPasswordHash(string userSuppliedPassword, string salt = null) {
	if(salt is null)
		salt = to!string(uniform(0, int.max));

		// FIXME: sha256 is actually not ideal for this, but meh it's what i have.
	return hashToString(SHA256(salt ~ userSuppliedPassword)) ~ ":" ~ salt;
}

/// and use this to check it.
bool checkPassword(string saltedPasswordHash, string userSuppliedPassword) {
	auto parts = saltedPasswordHash.split(":");

	return makeSaltedPasswordHash(userSuppliedPassword, parts[1]) == saltedPasswordHash;
}


/// implements the "table" format option. Works on structs and associative arrays (string[string][])
Table structToTable(T)(Document document, T arr, string[] fieldsToSkip = null) if(isArray!(T) && !isAssociativeArray!(T)) {
	auto t = cast(Table) document.createElement("table");
	t.border = "1";

	static if(is(T == string[string][])) {
			string[string] allKeys;
			foreach(row; arr) {
				foreach(k; row.keys)
					allKeys[k] = k;
			}

			auto sortedKeys = allKeys.keys.sort;
			Element tr;

			auto thead = t.addChild("thead");
			auto tbody = t.addChild("tbody");

			tr = thead.addChild("tr");
			foreach(key; sortedKeys)
				tr.addChild("th", key);

			bool odd = true;
			foreach(row; arr) {
				tr = tbody.addChild("tr");
				foreach(k; sortedKeys) {
					tr.addChild("td", k in row ? row[k] : "");
				}
				if(odd)
					tr.addClass("odd");

				odd = !odd;
			}
	} else static if(is(typeof(T[0]) == struct)) {
		{
			auto thead = t.addChild("thead");
			auto tr = thead.addChild("tr");
			auto s = arr[0];
			foreach(idx, member; s.tupleof)
				tr.addChild("th", s.tupleof[idx].stringof[2..$]);
		}

		bool odd = true;
		auto tbody = t.addChild("tbody");
		foreach(s; arr) {
			auto tr = tbody.addChild("tr");
			foreach(member; s.tupleof) {
				tr.addChild("td", to!string(member));
			}

			if(odd)
				tr.addClass("odd");

			odd = !odd;
		}
	} else static assert(0);

	return t;
}

// this one handles horizontal tables showing just one item
/// does a name/field table for just a singular object
Table structToTable(T)(Document document, T s, string[] fieldsToSkip = null) if(!isArray!(T) || isAssociativeArray!(T)) {
	static if(__traits(compiles, s.makeHtmlTable(document)))
		return s.makeHtmlTable(document);
	else {

		auto t = cast(Table) document.createElement("table");

		static if(is(T == struct)) {
			main: foreach(i, member; s.tupleof) {
				string name = s.tupleof[i].stringof[2..$];
				foreach(f; fieldsToSkip)
					if(name == f)
						continue main;

				string nameS = name.idup;
				name = "";
				foreach(idx, c; nameS) {
					if(c >= 'A' && c <= 'Z')
						name ~= " " ~ c;
					else if(c == '_')
						name ~= " ";
					else
						name ~= c;
				}

				t.appendRow(t.th(name.capitalize),
					to!string(member));
			}
		} else static if(is(T == string[string])) {
			foreach(k, v; s){
				t.appendRow(t.th(k), v);
			}
		} else static assert(0);

		return t;
	}
}


/// This uses reflection info to generate Javascript that can call the server with some ease.
/// Also includes javascript base (see bottom of this file)
string makeJavascriptApi(const ReflectionInfo* mod, string base, bool isNested = false) {
	assert(mod !is null);

	string script;

	if(isNested)
		script = `'`~mod.name~`': {
	"_apiBase":'`~base~`',`;
	else
		script = `var `~mod.name~` = {
	"_apiBase":'`~base~`',`;

	script ~= javascriptBase;

	script ~= "\n\t";

	bool[string] alreadyDone;

	bool outp = false;

	foreach(s; mod.enums) {
		if(outp)
			script ~= ",\n\t";
		else
			outp = true;

		script ~= "'"~s.name~"': {\n";

		bool outp2 = false;
		foreach(i, n; s.names) {
			if(outp2)
				script ~= ",\n";
			else
				outp2 = true;

			// auto v = s.values[i];
			auto v = "'" ~ n ~ "'"; // we actually want to use the name here because to!enum() uses member name.

			script ~= "\t\t'"~n~"':" ~ to!string(v);
		}

		script ~= "\n\t}";
	}

	foreach(s; mod.structs) {
		if(outp)
			script ~= ",\n\t";
		else
			outp = true;

		script ~= "'"~s.name~"': function(";

		bool outp2 = false;
		foreach(n; s.members) {
			if(outp2)
				script ~= ", ";
			else
				outp2 = true;

			script ~= n.name;

		}		
		script ~= ") { return {\n";

		outp2 = false;

		script ~= "\t\t'_arsdTypeOf':'"~s.name~"'";
		if(s.members.length)
			script ~= ",";
		script ~= " // metadata, ought to be read only\n";

		// outp2 is still false because I put the comma above
		foreach(n; s.members) {
			if(outp2)
				script ~= ",\n";
			else
				outp2 = true;

			auto v = n.defaultValue;

			script ~= "\t\t'"~n.name~"': (typeof "~n.name~" == 'undefined') ? "~n.name~" : '" ~ to!string(v) ~ "'";
		}

		script ~= "\n\t}; }";
	}

	// FIXME: it should output the classes too
	foreach(obj; mod.objects) {
		if(outp)
			script ~= ",\n\t";
		else
			outp = true;

		script ~= makeJavascriptApi(obj, base ~ obj.name ~ "/", true);
	}

	foreach(key, func; mod.functions) {
		if(func.originalName in alreadyDone)
			continue; // there's url friendly and code friendly, only need one

		alreadyDone[func.originalName] = true;

		if(outp)
			script ~= ",\n\t";
		else
			outp = true;


		string args;
		string obj;
		bool outputted = false;
		/+
		foreach(i, arg; func.parameters) {
			if(outputted) {
				args ~= ",";
				obj ~= ",";
			} else
				outputted = true;

			args ~= arg.name;

			// FIXME: we could probably do better checks here too like on type
			obj ~= `'`~arg.name~`':(typeof `~arg.name ~ ` == "undefined" ? this._raiseError('InsufficientParametersException', '`~func.originalName~`: argument `~to!string(i) ~ " (" ~ arg.staticType~` `~arg.name~`) is not present') : `~arg.name~`)`;
		}
		+/

		/*
		if(outputted)
			args ~= ",";
		args ~= "callback";
		*/

		script ~= `'` ~ func.originalName ~ `'`;
		script ~= ":";
		script ~= `function(`~args~`) {`;
		if(obj.length)
		script ~= `
		var argumentsObject = {
			`~obj~`
		};
		return this._serverCall('`~key~`', argumentsObject, '`~func.returnType~`');`;
		else
		script ~= `
		return this._serverCall('`~key~`', arguments, '`~func.returnType~`');`;

		script ~= `
	}`;
	}

	script ~= "\n}";

	// some global stuff to put in
	if(!isNested)
	script ~= `
		if(typeof arsdGlobalStuffLoadedForWebDotD == "undefined") {
			arsdGlobalStuffLoadedForWebDotD = true;
			var oldObjectDotPrototypeDotToString = Object.prototype.toString;
			Object.prototype.toString = function() {
				if(this.formattedSecondarily)
					return this.formattedSecondarily;

				return  oldObjectDotPrototypeDotToString.call(this);
			}
		}
	`;

	return script;
}


debug string javascriptBase = `
	// change this in your script to get fewer error popups
	"_debugMode":true,` ~ javascriptBaseImpl;
else string javascriptBase = `
	// change this in your script to get more details in errors
	"_debugMode":false,` ~ javascriptBaseImpl;

/// The Javascript code used in the generated JS API.
/**
	It provides the foundation to calling the server via background requests
	and handling the response in callbacks. (ajax style stuffs).

	The names with a leading underscore are meant to be private.


	Generally:

	YourClassName.yourMethodName(args...).operation(args);


	CoolApi.getABox("red").useToReplace(document.getElementById("playground"));

	for example.

	When you call a method, it doesn't make the server request. Instead, it returns
	an object describing the call. This means you can manipulate it (such as requesting
	a custom format), pass it as an argument to other functions (thus saving http requests)
	and finally call it at the end.

	The operations are:
		get(callback, args to callback...);

		See below.

		useToReplace(element) // pass an element reference. Example: useToReplace(document.querySelector(".name"));
		useToReplace(element ID : string) // you pass a string, it calls document.getElementById for you

		useToReplace sets the given element's innerHTML to the return value. The return value is automatically requested
		to be formatted as HTML.

		appendTo(element)
		appendTo(element ID : String)

		Adds the return value, as HTML, to the given element's inner html.

		useToReplaceElement(element)

		Replaces the given element entirely with the return value. (basically element.outerHTML = returnValue;)

		useToFillForm(form)

		Takes an object. Loop through the members, setting the form.elements[key].value = value.

		Does not work if the return value is not a javascript object (so use it if your function returns a struct or string[string])

		getSync()

		Does a synchronous get and returns the server response. Not recommended.

	get() :

		The generic get() function is the most generic operation to get a response. It's arguments implement
		partial application for you, so you can pass just about any callback to it.

		Despite the name, the underlying operation may be HTTP GET or HTTP POST. This is determined from the
		function's server side attributes. (FIXME: implement smarter thing. Currently it actually does it by name - if
		the function name starts with get, do get. Else, do POST.)


		Usage:

		CoolApi.getABox('red').get(alert); // calls alert(returnedValue);  so pops up the returned value

		CoolApi.getABox('red').get(fadeOut, this); // calls fadeOut(this, returnedValue);


		Since JS functions generally ignore extra params, this lets you call just about anything:

		CoolApi.getABox('red').get(alert, "Success"); // pops a box saying "Success", ignoring the actual return value


		Passing arguments to the functions let you reuse a lot of things that might not have been designed with this in mind.
		If you use arsd.js, there's other little functions that let you turn properties into callbacks too.


		Passing "this" to a callback via get is useful too since inside the callback, this probably won't refer to what you
		wanted. As an argument though, it all remains sane.




	Error Handling:

		D exceptions are translated into Javascript exceptions by the serverCall function. They are thrown, but since it's
		async, catching them is painful.

		It will probably show up in your browser's error console, or you can set the returned object's onerror function
		to something to handle it callback style. FIXME: not sure if this actually works right!
*/
// FIXME: this should probably be rewritten to make a constructable prototype object instead of a literal.
enum string javascriptBaseImpl = q{
	"_doRequest": function(url, args, callback, method, async) {
		var xmlHttp;
		try {   
			xmlHttp=new XMLHttpRequest();
		}     
		catch (e) {
			try {
				xmlHttp=new ActiveXObject("Msxml2.XMLHTTP");
			}
			catch (e) {
				xmlHttp=new ActiveXObject("Microsoft.XMLHTTP");
			}
		}

		if(async)
		xmlHttp.onreadystatechange=function() {
			if(xmlHttp.readyState==4) {
				// either if the function is nor available or if it returns a good result, we're set.
				// it might get to this point without the headers if the request was aborted
				if(callback && (!xmlHttp.getAllResponseHeaders || xmlHttp.getAllResponseHeaders())) {
					callback(xmlHttp.responseText, xmlHttp.responseXML);
				}
			}
		}

		var argString = this._getArgString(args);
		if(method == "GET" && url.indexOf("?") == -1)
			url = url + "?" + argString;

		xmlHttp.open(method, url, async);

		var a = "";

		if(method == "POST") {
			xmlHttp.setRequestHeader("Content-type","application/x-www-form-urlencoded");
			a = argString;
			// adding the CSRF stuff, if necessary
			var csrfKey = document.body.getAttribute("data-csrf-key");
			var csrfToken = document.body.getAttribute("data-csrf-token");
			if(csrfKey && csrfKey.length > 0 && csrfToken && csrfToken.length > 0) {
				if(a.length > 0)
					a += "&";
				a += encodeURIComponent(csrfKey) + "=" + encodeURIComponent(csrfToken);
			}
		} else {
			xmlHttp.setRequestHeader("Content-type", "text/plain");
		}

		xmlHttp.send(a);

		if(!async && callback) {
			xmlHttp.timeout = 500;
			return callback(xmlHttp.responseText, xmlHttp.responseXML);
		}
		return xmlHttp;
	},

	"_raiseError":function(type, message) {
		var error = new Error(message);
		error.name = type;
		throw error;
	},

	"_getUriRelativeToBase":function(name, args) {
		var str = name;
		var argsStr = this._getArgString(args);
		if(argsStr.length)
			str += "?" + argsStr;

		return str;
	},

	"_getArgString":function(args) {
		var a = "";
		var outputted = false;
		var i; // wow Javascript sucks! god damned global loop variables
		for(i in args) {
			if(outputted) {
				a += "&";
			} else outputted = true;
			var arg = args[i];
			var argType = "";
			// Make sure the types are all sane

			if(arg && arg._arsdTypeOf && arg._arsdTypeOf == "ServerResult") {
				argType = arg._arsdTypeOf;
				arg = this._getUriRelativeToBase(arg._serverFunction, arg._serverArguments);

				// this arg is a nested server call
				a += encodeURIComponent(i) + "=";
				a += encodeURIComponent(arg);
			} else if(arg && arg.length && typeof arg != "string") {
				// FIXME: are we sure this is actually an array? It might be an object with a length property...

				var outputtedHere = false;
				for(var idx = 0; idx < arg.length; idx++) {
					if(outputtedHere) {
						a += "&";
					} else outputtedHere = true;

					// FIXME: ought to be recursive
					a += encodeURIComponent(i) + "=";
					a += encodeURIComponent(arg[idx]);
				}
			} else {
				// a regular argument
				a += encodeURIComponent(i) + "=";
				a += encodeURIComponent(arg);
			}
			// else if: handle arrays and objects too

			if(argType.length > 0) {
				a += "&";
				a += encodeURIComponent(i + "-type") + "=";
				a += encodeURIComponent(argType);
			}
		}

		return a;
	},

	"_onError":function(error) {
		throw error;
	},

	/// returns an object that can be used to get the actual response from the server
 	"_serverCall": function (name, passedArgs, returnType) {
		var me = this; // this is the Api object
		var args;
		// FIXME: is there some way to tell arguments apart from other objects? dynamic languages suck.
		if(!passedArgs.length)
			args = passedArgs;
		else {
			args = new Object();
			for(var a = 0; a < passedArgs.length; a++)
				args["positional-arg-" + a] = passedArgs[a];
		}
		return {
			// type info metadata
			"_arsdTypeOf":"ServerResult",
			"_staticType":(typeof returnType == "undefined" ? null : returnType),

			// Info about the thing
			"_serverFunction":name,
			"_serverArguments":args,

			// lower level implementation
			"_get":function(callback, onError, async) {
				var resObj = this;
				if(args == null)
					args = {};
				if(!args.format)
					args.format = "json";
				args.envelopeFormat = "json";
				return me._doRequest(me._apiBase + name, args, function(t, xml) {
					/*
					if(me._debugMode) {
						try {
							var obj = eval("(" + t + ")");
						} catch(e) {
							alert("Bad server json: " + e +
								"\nOn page: " + (me._apiBase + name) +
								"\nGot:\n" + t);
						}
					} else {
					*/
						var obj = eval("(" + t + ")");
					//}

					if(obj.success) {
						if(typeof callback == "function")
							callback(obj.result);
						else if(typeof resObj.onSuccess == "function") {
							resObj.onSuccess(obj.result);
						} else if(typeof me.onSuccess == "function") { // do we really want this?
							me.onSuccess(obj.result);
						} else {
							// can we automatically handle it?
							// If it's an element, we should replace innerHTML by ID if possible
							// if a callback is given and it's a string, that's an id. Return type of element
							// should replace that id. return type of string should be appended
							// FIXME: meh just do something here.
						}

						return obj.result;
					} else {
						// how should we handle the error? I guess throwing is better than nothing
						// but should there be an error callback too?
						var error = new Error(obj.errorMessage);
						error.name = obj.type;
						error.functionUrl = me._apiBase + name;
						error.functionArgs = args;
						error.errorMessage = obj.errorMessage;

						// myFunction.caller should be available and checked too
						// btw arguments.callee is like this for functions

						if(me._debugMode) {
							var ourMessage = obj.type + ": " + obj.errorMessage +
								"\nOn: " + me._apiBase + name;
							if(args.toSource)
								ourMessage += args.toSource();
							if(args.stack)
								ourMessage += "\n" + args.stack;

							error.message = ourMessage;

							// alert(ourMessage);
						}

						if(onError) // local override first...
							return onError(error);
						else if(resObj.onError) // then this object
							return resObj.onError(error);
						else if(me._onError) // then the global object
							return me._onError(error);

						throw error; // if all else fails...
					}

					// assert(0); // not reached
				}, (name.indexOf("get") == 0) ? "GET" : "POST", async); // FIXME: hack: naming convention used to figure out method to use
			},

			// should pop open the thing in HTML format
			// "popup":null, // FIXME not implemented

			"onError":null, // null means call the global one

			"onSuccess":null, // a generic callback. generally pass something to get instead.

			"formatSet":false, // is the format overridden?

			// gets the result. Works automatically if you don't pass a callback.
			// You can also curry arguments to your callback by listing them here. The
			// result is put on the end of the arg list to the callback
			"get":function(callbackObj) {
				var callback = null;
				var errorCb = null;
				var callbackThis = null;
				if(callbackObj) {
					if(typeof callbackObj == "function")
						callback = callbackObj;
					else {
						if(callbackObj.length) {
							// array
							callback = callbackObj[0];

							if(callbackObj.length >= 2)
								errorCb = callbackObj[1];
						} else {
							if(callbackObj.onSuccess)
								callback = callbackObj.onSuccess;
							if(callbackObj.onError)
								errorCb = callbackObj.onError;
							if(callbackObj.self)
								callbackThis = callbackObj.self;
							else
								callbackThis = callbackObj;
						}
					}
				}
				if(arguments.length > 1) {
					var ourArguments = [];
					for(var a = 1; a < arguments.length; a++)
						ourArguments.push(arguments[a]);

					function cb(obj, xml) {
						ourArguments.push(obj);
						ourArguments.push(xml);

						// that null is the this object inside the function... can
						// we make that work?
						return callback.apply(callbackThis, ourArguments);
					}

					function cberr(err) {
						ourArguments.unshift(err);

						// that null is the this object inside the function... can
						// we make that work?
						return errorCb.apply(callbackThis, ourArguments);
					}


					this._get(cb, errorCb ? cberr : null, true);
				} else {
					this._get(callback, errorCb, true);
				}
			},

			// If you need a particular format, use this.
			"getFormat":function(format /* , same args as get... */) {
				this.format(format);
				var forwardedArgs = [];
				for(var a = 1; a < arguments.length; a++)
					forwardedArgs.push(arguments[a]);
				this.get.apply(this, forwardedArgs);
			},

			// sets the format of the request so normal get uses it
			// myapi.someFunction().format('table').get(...);
			// see also: getFormat and getHtml
			// the secondaryFormat only makes sense if format is json. It
			// sets the format returned by object.toString() in the returned objects.
			"format":function(format, secondaryFormat) {
				if(args == null)
					args = {};
				args.format = format;

				if(typeof secondaryFormat == "string" && secondaryFormat) {
					if(format != "json")
						me._raiseError("AssertError", "secondaryFormat only works if format == json");
					args.secondaryFormat = secondaryFormat;
				}

				this.formatSet = true;
				return this;
			},

			"getHtml":function(/* args to get... */) {
				this.format("html");
				this.get.apply(this, arguments);
			},

			// FIXME: add post aliases

			// don't use unless you're deploying to localhost or something
			"getSync":function() {
				function cb(obj) {
					// no nothing, we're returning the value below
				}

				return this._get(cb, null, false);
			},
			// takes the result and appends it as html to the given element

			// FIXME: have a type override
			"appendTo":function(what) {
				if(!this.formatSet)
					this.format("html");
				this.get(me._appendContent(what));
			},
			// use it to replace the content of the given element
			"useToReplace":function(what) {
				if(!this.formatSet)
					this.format("html");
				this.get(me._replaceContent(what));
			},
			// use to replace the given element altogether
			"useToReplaceElement":function(what) {
				if(!this.formatSet)
					this.format("html");
				this.get(me._replaceElement(what));
			},
			"useToFillForm":function(what) {
				this.get(me._fillForm(what));
			}
			// runAsScript has been removed, use get(eval) instead
			// FIXME: might be nice to have an automatic popin function too
		};
	},

	"_fillForm": function(what) {
		var e = this._getElement(what);
		if(this._isListOfNodes(e))
			alert("FIXME: list of forms not implemented");
		else return function(obj) {
			if(e.elements && typeof obj == "object") {
				for(i in obj)
					if(e.elements[i])
						e.elements[i].value = obj[i]; // FIXME: what about checkboxes, selects, etc?
			} else
				throw new Error("unsupported response");
		};
	},

	"_getElement": function(what) {
		// FIXME: what about jQuery users? If they do useToReplace($("whatever")), we ought to do what we can with it for the most seamless experience even if I loathe that bloat.
		// though I guess they should be ok in doing $("whatever")[0] or maybe $("whatever").get() so not too awful really.
		var e;
		if(typeof what == "string")
			e = document.getElementById(what);
		else
			e = what;

		return e;
	},

	"_isListOfNodes": function(what) {
		// length is on both arrays and lists, but some elements
		// have it too. We disambiguate with getAttribute
		return (what && (what.length && !what.getAttribute))
	},

	// These are some convenience functions to use as callbacks
	"_replaceContent": function(what) {
		var e = this._getElement(what);
		if(this._isListOfNodes(e))
			return function(obj) {
				for(var a = 0; a < obj.length; a++) {
					if( (e[a].tagName.toLowerCase() == "input"
						&&
						e[a].getAttribute("type") == "text")
						||
						e[a].tagName.toLowerCase() == "textarea")
					{
						e[a].value = obj;
					} else
						e[a].innerHTML = obj;
				}
			}
		else
			return function(obj) {
				if( (e.tagName.toLowerCase() == "input"
					&&
					e.getAttribute("type") == "text")
					||
					e.tagName.toLowerCase() == "textarea")
				{
					e.value = obj;
				} else
					e.innerHTML = obj;
			}
	},

	// note: what must be only a single element, FIXME: could check the static type
	"_replaceElement": function(what) {
		var e = this._getElement(what);
		if(this._isListOfNodes(e))
			throw new Error("Can only replace individual elements since removal from a list may be unstable.");
		return function(obj) {
			var n = document.createElement("div");
			n.innerHTML = obj;

			if(n.firstChild) {
				e.parentNode.replaceChild(n.firstChild, e);
			} else {
				e.parentNode.removeChild(e);
			}
		}
	},

	"_appendContent": function(what) {
		var e = this._getElement(what);
		if(this._isListOfNodes(e)) // FIXME: repeating myself...
			return function(obj) {
				for(var a = 0; a < e.length; a++)
					e[a].innerHTML += obj;
			}
		else
			return function(obj) {
				e.innerHTML += obj;
			}
	},
};


/*



Note for future: dom.d makes working with html easy, since you can
do various forms of post processing on it to make custom formats
among other things.

I'm considering adding similar stuff for CSS and Javascript.
dom.d now has some more css support - you can apply a stylesheet
to a document and get the computed style and do some minor changes
programmically. StyleSheet : css file :: Document : html file.

My css lexer/parser is still pretty crappy though. Also, I'm
not sure it's worth going all the way here.

I'm doing some of it to support my little browser, but for server
side programs, I'm not sure how useful it is to do this kind of
thing.

A simple textual macro would be more useful for css than a 
struct for it.... I kinda want nested declarations and some
functions (the sass thing from ruby is kinda nice in some ways).

But I'm fairly meh on it anyway.


For javascript, I wouldn't mind having a D style foreach in it.
But is it worth it writing a fancy javascript AST thingy just
for that?

Aside from that, I don't mind the language with how sparingly I
use it though. Besides, writing:

CoolApi.doSomething("asds").appendTo('element');

really isn't bad anyway.


The benefit for html was very easy and big. I'm not so sure about
css and js.
*/

/*
Copyright: Adam D. Ruppe, 2010 - 2012
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions by Nick Sabalausky

        Copyright Adam D. Ruppe 2010-2012.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
        http://www.boost.org/LICENSE_1_0.txt)
*/
