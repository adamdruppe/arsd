// FIXME: if an exception is thrown, we shouldn't necessarily cache...
// FIXME: there's some annoying duplication of code in the various versioned mains

// FIXME: I might make a cgi proxy class which can change things; the underlying one is still immutable
// but the later one can edit and simplify the api. You'd have to use the subclass tho!

/*
void foo(int f, @("test") string s) {}

void main() {
	static if(is(typeof(foo) Params == __parameters))
		//pragma(msg, __traits(getAttributes, Params[0]));
		pragma(msg, __traits(getAttributes, Params[1..2]));
	else
		pragma(msg, "fail");
}
*/

// Note: spawn-fcgi can help with fastcgi on nginx

// FIXME: to do: add openssl optionally
// make sure embedded_httpd doesn't send two answers if one writes() then dies

// future direction: websocket as a separate process that you can sendfile to for an async passoff of those long-lived connections

/*
	Session manager process: it spawns a new process, passing a
	command line argument, to just be a little key/value store
	of some serializable struct. On Windows, it CreateProcess.
	On Linux, it can just fork or maybe fork/exec. The session
	key is in a cookie.

	Server-side event process: spawns an async manager. You can
	push stuff out to channel ids and the clients listen to it.

	websocket process: spawns an async handler. They can talk to
	each other or get info from a cgi request.

	Tempting to put web.d 2.0 in here. It would:
		* map urls and form generation to functions
		* have data presentation magic
		* do the skeleton stuff like 1.0
		* auto-cache generated stuff in files (at least if pure?)
		* introspect functions in json for consumers


	https://linux.die.net/man/3/posix_spawn
*/

/++
	Provides a uniform server-side API for CGI, FastCGI, SCGI, and HTTP web applications.

	---
	import arsd.cgi;

	// Instead of writing your own main(), you should write a function
	// that takes a Cgi param, and use mixin GenericMain
	// for maximum compatibility with different web servers.
	void hello(Cgi cgi) {
		cgi.setResponseContentType("text/plain");

		if("name" in cgi.get)
			cgi.write("Hello, " ~ cgi.get["name"]);
		else
			cgi.write("Hello, world!");
	}

	mixin GenericMain!hello;
	---


	Compile_versions:

		-version=plain_cgi
			The default - a traditional, plain CGI executable will be generated.
		-version=fastcgi
			A FastCGI executable will be generated.
		-version=scgi
			A SCGI (SimpleCGI) executable will be generated.
		-version=embedded_httpd
			A HTTP server will be embedded in the generated executable.
		-version=embedded_httpd_threads
			The embedded HTTP server will use a single process with a thread pool.
		-version=embedded_httpd_processes
			The embedded HTTP server will use a prefork style process pool.

		-version=cgi_with_websocket
			The CGI class has websocket server support.

		-version=with_openssl # not currently used

		-version=embedded_httpd_processes_accept_after_fork
			It will call accept() in each child process, after forking. This is currently the only option, though I am experimenting with other ideas.

		-version=cgi_embedded_sessions
			The session server will be embedded in the cgi.d server process
		-version=cgi_session_server_process
			The session will be provided in a separate process, provided by cgi.d.

	Compile_and_run:
	
	For CGI, `dmd yourfile.d cgi.d` then put the executable in your cgi-bin directory.

	For FastCGI: `dmd yourfile.d cgi.d -version=fastcgi` and run it. spawn-fcgi helps on nginx. You can put the file in the directory for Apache. On IIS, run it with a port on the command line.

	For SCGI: `dmd yourfile.d cgi.d -version=scgi` and run the executable, providing a port number on the command line.

	For an embedded HTTP server, run `dmd yourfile.d cgi.d -version=embedded_httpd` and run the generated program. It listens on port 8085 by default. You can change this on the command line with the --port option when running your program.

	You can also simulate a request by passing parameters on the command line, like:

	$(CONSOLE
	./yourprogram GET / name=adr
	)

	And it will print the result to stdout.

	CGI_Setup_tips:

	On Apache, you may do `SetHandler cgi-script` in your `.htaccess` file.

	Integration_tips:

	cgi.d works well with dom.d for generating html. You may also use web.d for other utilities and automatic api wrapping.

	dom.d usage:

	---
		import arsd.cgi;
		import arsd.dom;

		void hello_dom(Cgi cgi) {
			auto document = new Document();

			static import std.file;
			// parse the file in strict mode, requiring it to be well-formed UTF-8 XHTML
			// (You'll appreciate this if you've ever had to deal with a missing </div>
			// or something in a php or erb template before that would randomly mess up
			// the output in your browser. Just check it and throw an exception early!)
			//
			// You could also hard-code a template or load one at compile time with an
			// import expression, but you might appreciate making it a regular file
			// because that means it can be more easily edited by the frontend team and
			// they can see their changes without needing to recompile the program.
			//
			// Note on CTFE: if you do choose to load a static file at compile time,
			// you *can* parse it in CTFE using enum, which will cause it to throw at
			// compile time, which is kinda cool too. Be careful in modifying that document,
			// though, as it will be a static instance. You might want to clone on on demand,
			// or perhaps modify it lazily as you print it out. (Try element.tree, it returns
			// a range of elements which you could send through std.algorithm functions. But
			// since my selector implementation doesn't work on that level yet, you'll find that
			// harder to use. Of course, you could make a static list of matching elements and
			// then use a simple e is e2 predicate... :) )
			document.parseUtf8(std.file.read("your_template.html"), true, true);

			// fill in data using DOM functions, so placing it is in the hands of HTML
			// and it will be properly encoded as text too.
			//
			// Plain html templates can't run server side logic, but I think that's a
			// good thing - it keeps them simple. You may choose to extend the html,
			// but I think it is best to try to stick to standard elements and fill them
			// in with requested data with IDs or class names. A further benefit of
			// this is the designer can also highlight data based on sources in the CSS.
			//
			// However, all of dom.d is available, so you can format your data however
			// you like. You can do partial templates with innerHTML too, or perhaps better,
			// injecting cloned nodes from a partial document.
			//
			// There's a lot of possibilities.
			document["#name"].innerText = cgi.request("name", "default name");

			// send the document to the browser. The second argument to `cgi.write`
			// indicates that this is all the data at once, enabling a few small
			// optimizations.
			cgi.write(document.toString(), true);
		}
	---

	Concepts:
		Input: [Cgi.get], [Cgi.post], [Cgi.request], [Cgi.files], [Cgi.cookies], [Cgi.pathInfo], [Cgi.requestMethod],
		       and HTTP headers ([Cgi.headers], [Cgi.userAgent], [Cgi.referrer], [Cgi.accept], [Cgi.authorization], [Cgi.lastEventId])

		Output: [Cgi.write], [Cgi.header], [Cgi.setResponseStatus], [Cgi.setResponseContentType], [Cgi.gzipResponse]

		Cookies: [Cgi.setCookie], [Cgi.clearCookie], [Cgi.cookie], [Cgi.cookies]

		Caching: [Cgi.setResponseExpires], [Cgi.updateResponseExpires], [Cgi.setCache]

		Redirections: [Cgi.setResponseLocation]

		Other Information: [Cgi.remoteAddress], [Cgi.https], [Cgi.port], [Cgi.scriptName], [Cgi.requestUri], [Cgi.getCurrentCompleteUri], [Cgi.onRequestBodyDataReceived]

		Overriding behavior: [Cgi.handleIncomingDataChunk], [Cgi.prepareForIncomingDataChunks], [Cgi.cleanUpPostDataState]

		Installing: Apache, IIS, CGI, FastCGI, SCGI, embedded HTTPD (not recommended for production use)

	Guide_for_PHP_users:
		If you are coming from PHP, here's a quick guide to help you get started:

		$(SIDE_BY_SIDE
			$(COLUMN
				```php
				<?php
					$foo = $_POST["foo"];
					$bar = $_GET["bar"];
					$baz = $_COOKIE["baz"];

					$user_ip = $_SERVER["REMOTE_ADDR"];
					$host = $_SERVER["HTTP_HOST"];
					$path = $_SERVER["PATH_INFO"];

					setcookie("baz", "some value");

					echo "hello!";
				?>
				```
			)
			$(COLUMN
				---
				import arsd.cgi;
				void app(Cgi cgi) {
					string foo = cgi.post["foo"];
					string bar = cgi.get["bar"];
					string baz = cgi.cookies["baz"];

					string user_ip = cgi.remoteAddress;
					string host = cgi.host;
					string path = cgi.pathInfo;

					cgi.setCookie("baz", "some value");

					cgi.write("hello!");
				}

				mixin GenericMain!app
				---
			)
		)

		$(H3 Array elements)


		In PHP, you can give a form element a name like `"something[]"`, and then
		`$_POST["something"]` gives an array. In D, you can use whatever name
		you want, and access an array of values with the `cgi.getArray["name"]` and
		`cgi.postArray["name"]` members.

		$(H3 Databases)

		PHP has a lot of stuff in its standard library. cgi.d doesn't include most
		of these, but the rest of my arsd repository has much of it. For example,
		to access a MySQL database, download `database.d` and `mysql.d` from my
		github repo, and try this code (assuming, of course, your database is
		set up):

		---
		import arsd.cgi;
		import arsd.mysql;

		void app(Cgi cgi) {
			auto database = new MySql("localhost", "username", "password", "database_name");
			foreach(row; mysql.query("SELECT count(id) FROM people"))
				cgi.write(row[0] ~ " people in database");
		}

		mixin GenericMain!app;
		---

		Similar modules are available for PostgreSQL, Microsoft SQL Server, and SQLite databases,
		implementing the same basic interface.

	See_Also:

	You may also want to see [arsd.dom], [arsd.web], and [arsd.html] for more code for making
	web applications.

	For working with json, try [arsd.jsvar].
	
	[arsd.database], [arsd.mysql], [arsd.postgres], [arsd.mssql], and [arsd.sqlite] can help in
	accessing databases.

	If you are looking to access a web application via HTTP, try [std.net.curl], [arsd.curl], or [arsd.http2].

	Copyright:

	cgi.d copyright 2008-2019, Adam D. Ruppe. Provided under the Boost Software License.

	Yes, this file is almost ten years old, and yes, it is still actively maintained and used.
+/
module arsd.cgi;

static import std.file;

// for a single thread, linear request thing, use:
// -version=embedded_httpd_threads -version=cgi_no_threads

version(embedded_httpd) {
	version(linux)
		version=embedded_httpd_processes;
	else {
		version=embedded_httpd_threads;
	}

	/*
	version(with_openssl) {
		pragma(lib, "crypto");
		pragma(lib, "ssl");
	}
	*/
}

version(embedded_httpd_processes)
	version=embedded_httpd_processes_accept_after_fork; // I am getting much better average performance on this, so just keeping it. But the other way MIGHT help keep the variation down so i wanna keep the code to play with later

version(embedded_httpd_threads) {
	//  unless the user overrides the default..
	version(cgi_session_server_process)
		{}
	else
		version=cgi_embedded_sessions;
}
version(scgi) {
	//  unless the user overrides the default..
	version(cgi_session_server_process)
		{}
	else
		version=cgi_embedded_sessions;
}

// fall back if the other is not defined so we can cleanly version it below
version(cgi_embedded_sessions) {}
else version=cgi_session_server_process;


version=cgi_with_websocket;

enum long defaultMaxContentLength = 5_000_000;

/*

	To do a file download offer in the browser:

    cgi.setResponseContentType("text/csv");
    cgi.header("Content-Disposition: attachment; filename=\"customers.csv\"");
*/

// FIXME: the location header is supposed to be an absolute url I guess.

// FIXME: would be cool to flush part of a dom document before complete
// somehow in here and dom.d.


// FIXME: 100 Continue in the nph section? Probably belongs on the
// httpd class though.

// these are public so you can mixin GenericMain.
// FIXME: use a function level import instead!
public import std.string;
public import std.stdio;
public import std.conv;
import std.uri;
import std.uni;
import std.algorithm.comparison;
import std.algorithm.searching;
import std.exception;
import std.base64;
static import std.algorithm;
import std.datetime;
import std.range;

import std.process;

import std.zlib;


T[] consume(T)(T[] range, int count) {
	if(count > range.length)
		count = range.length;
	return range[count..$];
}

int locationOf(T)(T[] data, string item) {
	const(ubyte[]) d = cast(const(ubyte[])) data;
	const(ubyte[]) i = cast(const(ubyte[])) item;

	for(int a = 0; a < d.length; a++) {
		if(a + i.length > d.length)
			return -1;
		if(d[a..a+i.length] == i)
			return a;
	}

	return -1;
}

/// If you are doing a custom cgi class, mixing this in can take care of
/// the required constructors for you
mixin template ForwardCgiConstructors() {
	this(long maxContentLength = defaultMaxContentLength,
		string[string] env = null,
		const(ubyte)[] delegate() readdata = null,
		void delegate(const(ubyte)[]) _rawDataOutput = null,
		void delegate() _flush = null
		) { super(maxContentLength, env, readdata, _rawDataOutput, _flush); }

	this(string[] args) { super(args); }

	this(
		BufferedInputRange inputData,
		string address, ushort _port,
		int pathInfoStarts = 0,
		bool _https = false,
		void delegate(const(ubyte)[]) _rawDataOutput = null,
		void delegate() _flush = null,
		// this pointer tells if the connection is supposed to be closed after we handle this
		bool* closeConnection = null)
	{
		super(inputData, address, _port, pathInfoStarts, _https, _rawDataOutput, _flush, closeConnection);
	}

	this(BufferedInputRange ir, bool* closeConnection) { super(ir, closeConnection); }
}


 
version(Windows) {
// FIXME: ugly hack to solve stdin exception problems on Windows:
// reading stdin results in StdioException (Bad file descriptor)
// this is probably due to http://d.puremagic.com/issues/show_bug.cgi?id=3425
private struct stdin {
	struct ByChunk { // Replicates std.stdio.ByChunk
	private:
		ubyte[] chunk_;
	public:
		this(size_t size)
		in {
			assert(size, "size must be larger than 0");
		}
		body {
			chunk_ = new ubyte[](size);
			popFront();
		}

		@property bool empty() const {
			return !std.stdio.stdin.isOpen || std.stdio.stdin.eof; // Ugly, but seems to do the job
		}
		@property nothrow ubyte[] front() {	return chunk_; }
		void popFront()	{
			enforce(!empty, "Cannot call popFront on empty range");
			chunk_ = stdin.rawRead(chunk_);
		}
	}

	import core.sys.windows.windows;
static:

	static this() {
		// Set stdin to binary mode
		version(Win64)
		_setmode(std.stdio.stdin.fileno(), 0x8000);
		else
		setmode(std.stdio.stdin.fileno(), 0x8000);
	}

	T[] rawRead(T)(T[] buf) {
		uint bytesRead;
		auto result = ReadFile(GetStdHandle(STD_INPUT_HANDLE), buf.ptr, cast(int) (buf.length * T.sizeof), &bytesRead, null);

		if (!result) {
			auto err = GetLastError();
			if (err == 38/*ERROR_HANDLE_EOF*/ || err == 109/*ERROR_BROKEN_PIPE*/) // 'good' errors meaning end of input
				return buf[0..0];
			// Some other error, throw it

			char* buffer;
			scope(exit) LocalFree(buffer);

			// FORMAT_MESSAGE_ALLOCATE_BUFFER	= 0x00000100
			// FORMAT_MESSAGE_FROM_SYSTEM		= 0x00001000
			FormatMessageA(0x1100, null, err, 0, cast(char*)&buffer, 256, null);
			throw new Exception(to!string(buffer));
		}
		enforce(!(bytesRead % T.sizeof), "I/O error");
		return buf[0..bytesRead / T.sizeof];
	}

	auto byChunk(size_t sz) { return ByChunk(sz); }
}
}

/// The main interface with the web request
class Cgi {
  public:
	/// the methods a request can be
	enum RequestMethod { GET, HEAD, POST, PUT, DELETE, // GET and POST are the ones that really work
		// these are defined in the standard, but idk if they are useful for anything
		OPTIONS, TRACE, CONNECT,
		// These seem new, I have only recently seen them
		PATCH, MERGE,
		// this is an extension for when the method is not specified and you want to assume
		CommandLine }


	/+
	/++
		Cgi provides a per-request memory pool

	+/
	void[] allocateMemory(size_t nBytes) {

	}

	/// ditto
	void[] reallocateMemory(void[] old, size_t nBytes) {

	}

	/// ditto
	void freeMemory(void[] memory) {

	}
	+/


/*
	import core.runtime;
	auto args = Runtime.args();

	we can call the app a few ways:

	1) set up the environment variables and call the app (manually simulating CGI)
	2) simulate a call automatically:
		./app method 'uri'

		for example:
			./app get /path?arg arg2=something

	  Anything on the uri is treated as query string etc

	  on get method, further args are appended to the query string (encoded automatically)
	  on post method, further args are done as post


	  @name means import from file "name". if name == -, it uses stdin
	  (so info=@- means set info to the value of stdin)


	  Other arguments include:
	  	--cookie name=value (these are all concated together)
		--header 'X-Something: cool'
		--referrer 'something'
		--port 80
		--remote-address some.ip.address.here
		--https yes
		--user-agent 'something'
		--userpass 'user:pass'
		--authorization 'Basic base64encoded_user:pass'
		--accept 'content' // FIXME: better example
		--last-event-id 'something'
		--host 'something.com'

	  Non-simulation arguments:
	  	--port xxx listening port for non-cgi things (valid for the cgi interfaces)
		--listening-host  the ip address the application should listen on

*/

	/** Initializes it with command line arguments (for easy testing) */
	this(string[] args) {
		// these are all set locally so the loop works
		// without triggering errors in dmd 2.064
		// we go ahead and set them at the end of it to the this version
		int port;
		string referrer;
		string remoteAddress;
		string userAgent;
		string authorization;
		string origin;
		string accept;
		string lastEventId;
		bool https;
		string host;
		RequestMethod requestMethod;
		string requestUri;
		string pathInfo;
		string queryString;

		bool lookingForMethod;
		bool lookingForUri;
		string nextArgIs;

		string _cookie;
		string _queryString;
		string[][string] _post;
		string[string] _headers;

		string[] breakUp(string s) {
			string k, v;
			auto idx = s.indexOf("=");
			if(idx == -1) {
				k = s;
			} else {
				k = s[0 .. idx];
				v = s[idx + 1 .. $];
			}

			return [k, v];
		}

		lookingForMethod = true;

		scriptName = args[0];
		scriptFileName = args[0];

		environmentVariables = cast(const) environment.toAA;

		string[] allPostNamesInOrder;
		string[] allPostValuesInOrder;

		foreach(arg; args[1 .. $]) {
			if(arg.startsWith("--")) {
				nextArgIs = arg[2 .. $];
			} else if(nextArgIs.length) {
				if (nextArgIs == "cookie") {
					auto info = breakUp(arg);
					if(_cookie.length)
						_cookie ~= "; ";
					_cookie ~= std.uri.encodeComponent(info[0]) ~ "=" ~ std.uri.encodeComponent(info[1]);
				}
				else if (nextArgIs == "port") {
					port = to!int(arg);
				}
				else if (nextArgIs == "referrer") {
					referrer = arg;
				}
				else if (nextArgIs == "remote-address") {
					remoteAddress = arg;
				}
				else if (nextArgIs == "user-agent") {
					userAgent = arg;
				}
				else if (nextArgIs == "authorization") {
					authorization = arg;
				}
				else if (nextArgIs == "userpass") {
					authorization = "Basic " ~ Base64.encode(cast(immutable(ubyte)[]) (arg)).idup;
				}
				else if (nextArgIs == "origin") {
					origin = arg;
				}
				else if (nextArgIs == "accept") {
					accept = arg;
				}
				else if (nextArgIs == "last-event-id") {
					lastEventId = arg;
				}
				else if (nextArgIs == "https") {
					if(arg == "yes")
						https = true;
				}
				else if (nextArgIs == "header") {
					string thing, other;
					auto idx = arg.indexOf(":");
					if(idx == -1)
						throw new Exception("need a colon in a http header");
					thing = arg[0 .. idx];
					other = arg[idx + 1.. $];
					_headers[thing.strip.toLower()] = other.strip;
				}
				else if (nextArgIs == "host") {
					host = arg;
				}
				// else
				// skip, we don't know it but that's ok, it might be used elsewhere so no error

				nextArgIs = null;
			} else if(lookingForMethod) {
				lookingForMethod = false;
				lookingForUri = true;

				if(arg.asLowerCase().equal("commandline"))
					requestMethod = RequestMethod.CommandLine;
				else
					requestMethod = to!RequestMethod(arg.toUpper());
			} else if(lookingForUri) {
				lookingForUri = false;

				requestUri = arg;

				auto idx = arg.indexOf("?");
				if(idx == -1)
					pathInfo = arg;
				else {
					pathInfo = arg[0 .. idx];
					_queryString = arg[idx + 1 .. $];
				}
			} else {
				// it is an argument of some sort
				if(requestMethod == Cgi.RequestMethod.POST || requestMethod == Cgi.RequestMethod.PATCH || requestMethod == Cgi.RequestMethod.PUT) {
					auto parts = breakUp(arg);
					_post[parts[0]] ~= parts[1];
					allPostNamesInOrder ~= parts[0];
					allPostValuesInOrder ~= parts[1];
				} else {
					if(_queryString.length)
						_queryString ~= "&";
					auto parts = breakUp(arg);
					_queryString ~= std.uri.encodeComponent(parts[0]) ~ "=" ~ std.uri.encodeComponent(parts[1]);
				}
			}
		}

		acceptsGzip = false;
		keepAliveRequested = false;
		requestHeaders = cast(immutable) _headers;

		cookie = _cookie;
		cookiesArray =  getCookieArray();
		cookies = keepLastOf(cookiesArray);

		queryString = _queryString;
		getArray = cast(immutable) decodeVariables(queryString, "&", &allGetNamesInOrder, &allGetValuesInOrder);
		get = keepLastOf(getArray);

		postArray = cast(immutable) _post;
		post = keepLastOf(_post);

		// FIXME
		filesArray = null;
		files = null;

		isCalledWithCommandLineArguments = true;

		this.port = port;
		this.referrer = referrer;
		this.remoteAddress = remoteAddress;
		this.userAgent = userAgent;
		this.authorization = authorization;
		this.origin = origin;
		this.accept = accept;
		this.lastEventId = lastEventId;
		this.https = https;
		this.host = host;
		this.requestMethod = requestMethod;
		this.requestUri = requestUri;
		this.pathInfo = pathInfo;
		this.queryString = queryString;
		this.postJson = null;
	}

	private {
		string[] allPostNamesInOrder;
		string[] allPostValuesInOrder;
		string[] allGetNamesInOrder;
		string[] allGetValuesInOrder;
	}

	CgiConnectionHandle getOutputFileHandle() {
		return _outputFileHandle;
	}

	CgiConnectionHandle _outputFileHandle = INVALID_CGI_CONNECTION_HANDLE;

	/** Initializes it using a CGI or CGI-like interface */
	this(long maxContentLength = defaultMaxContentLength,
		// use this to override the environment variable listing
		in string[string] env = null,
		// and this should return a chunk of data. return empty when done
		const(ubyte)[] delegate() readdata = null,
		// finally, use this to do custom output if needed
		void delegate(const(ubyte)[]) _rawDataOutput = null,
		// to flush teh custom output
		void delegate() _flush = null
		)
	{

		// these are all set locally so the loop works
		// without triggering errors in dmd 2.064
		// we go ahead and set them at the end of it to the this version
		int port;
		string referrer;
		string remoteAddress;
		string userAgent;
		string authorization;
		string origin;
		string accept;
		string lastEventId;
		bool https;
		string host;
		RequestMethod requestMethod;
		string requestUri;
		string pathInfo;
		string queryString;



		isCalledWithCommandLineArguments = false;
		rawDataOutput = _rawDataOutput;
		flushDelegate = _flush;
		auto getenv = delegate string(string var) {
			if(env is null)
				return std.process.environment.get(var);
			auto e = var in env;
			if(e is null)
				return null;
			return *e;
		};

		environmentVariables = env is null ?
			cast(const) environment.toAA :
			env;

		// fetching all the request headers
		string[string] requestHeadersHere;
		foreach(k, v; env is null ? cast(const) environment.toAA() : env) {
			if(k.startsWith("HTTP_")) {
				requestHeadersHere[replace(k["HTTP_".length .. $].toLower(), "_", "-")] = v;
			}
		}

		this.requestHeaders = assumeUnique(requestHeadersHere);

		requestUri = getenv("REQUEST_URI");

		cookie = getenv("HTTP_COOKIE");
		cookiesArray = getCookieArray();
		cookies = keepLastOf(cookiesArray);

		referrer = getenv("HTTP_REFERER");
		userAgent = getenv("HTTP_USER_AGENT");
		remoteAddress = getenv("REMOTE_ADDR");
		host = getenv("HTTP_HOST");
		pathInfo = getenv("PATH_INFO");

		queryString = getenv("QUERY_STRING");
		scriptName = getenv("SCRIPT_NAME");
		{
			import core.runtime;
			auto sfn = getenv("SCRIPT_FILENAME");
			scriptFileName = sfn.length ? sfn : Runtime.args[0];
		}

		bool iis = false;

		// Because IIS doesn't pass requestUri, we simulate it here if it's empty.
		if(requestUri.length == 0) {
			// IIS sometimes includes the script name as part of the path info - we don't want that
			if(pathInfo.length >= scriptName.length && (pathInfo[0 .. scriptName.length] == scriptName))
				pathInfo = pathInfo[scriptName.length .. $];

			requestUri = scriptName ~ pathInfo ~ (queryString.length ? ("?" ~ queryString) : "");

			iis = true; // FIXME HACK - used in byChunk below - see bugzilla 6339

			// FIXME: this works for apache and iis... but what about others?
		}


		auto ugh = decodeVariables(queryString, "&", &allGetNamesInOrder, &allGetValuesInOrder);
		getArray = assumeUnique(ugh);
		get = keepLastOf(getArray);


		// NOTE: on shitpache, you need to specifically forward this
		authorization = getenv("HTTP_AUTHORIZATION");
		// this is a hack because Apache is a shitload of fuck and
		// refuses to send the real header to us. Compatible
		// programs should send both the standard and X- versions

		// NOTE: if you have access to .htaccess or httpd.conf, you can make this
		// unnecessary with mod_rewrite, so it is commented

		//if(authorization.length == 0) // if the std is there, use it
		//	authorization = getenv("HTTP_X_AUTHORIZATION");

		// the REDIRECT_HTTPS check is here because with an Apache hack, the port can become wrong
		if(getenv("SERVER_PORT").length && getenv("REDIRECT_HTTPS") != "on")
			port = to!int(getenv("SERVER_PORT"));
		else
			port = 0; // this was probably called from the command line

		auto ae = getenv("HTTP_ACCEPT_ENCODING");
		if(ae.length && ae.indexOf("gzip") != -1)
			acceptsGzip = true;

		accept = getenv("HTTP_ACCEPT");
		lastEventId = getenv("HTTP_LAST_EVENT_ID");

		auto ka = getenv("HTTP_CONNECTION");
		if(ka.length && ka.asLowerCase().canFind("keep-alive"))
			keepAliveRequested = true;

		auto or = getenv("HTTP_ORIGIN");
			origin = or;

		auto rm = getenv("REQUEST_METHOD");
		if(rm.length)
			requestMethod = to!RequestMethod(getenv("REQUEST_METHOD"));
		else
			requestMethod = RequestMethod.CommandLine;

						// FIXME: hack on REDIRECT_HTTPS; this is there because the work app uses mod_rewrite which loses the https flag! So I set it with [E=HTTPS=%HTTPS] or whatever but then it gets translated to here so i want it to still work. This is arguably wrong but meh.
		https = (getenv("HTTPS") == "on" || getenv("REDIRECT_HTTPS") == "on");

		// FIXME: DOCUMENT_ROOT?

		// FIXME: what about PUT?
		if(requestMethod == RequestMethod.POST || requestMethod == Cgi.RequestMethod.PATCH || requestMethod == Cgi.RequestMethod.PUT) {
			version(preserveData) // a hack to make forwarding simpler
				immutable(ubyte)[] data;
			size_t amountReceived = 0;
			auto contentType = getenv("CONTENT_TYPE");

			// FIXME: is this ever not going to be set? I guess it depends
			// on if the server de-chunks and buffers... seems like it has potential
			// to be slow if they did that. The spec says it is always there though.
			// And it has worked reliably for me all year in the live environment,
			// but some servers might be different.
			auto contentLength = to!size_t(getenv("CONTENT_LENGTH"));

			immutable originalContentLength = contentLength;
			if(contentLength) {
				if(maxContentLength > 0 && contentLength > maxContentLength) {
					setResponseStatus("413 Request entity too large");
					write("You tried to upload a file that is too large.");
					close();
					throw new Exception("POST too large");
				}
				prepareForIncomingDataChunks(contentType, contentLength);


				int processChunk(in ubyte[] chunk) {
					if(chunk.length > contentLength) {
						handleIncomingDataChunk(chunk[0..contentLength]);
						amountReceived += contentLength;
						contentLength = 0;
						return 1;
					} else {
						handleIncomingDataChunk(chunk);
						contentLength -= chunk.length;
						amountReceived += chunk.length;
					}
					if(contentLength == 0)
						return 1;

					onRequestBodyDataReceived(amountReceived, originalContentLength);
					return 0;
				}


				if(readdata is null) {
					foreach(ubyte[] chunk; stdin.byChunk(iis ? contentLength : 4096))
						if(processChunk(chunk))
							break;
				} else {
					// we have a custom data source..
					auto chunk = readdata();
					while(chunk.length) {
						if(processChunk(chunk))
							break;
						chunk = readdata();
					}
				}

				onRequestBodyDataReceived(amountReceived, originalContentLength);
				postArray = assumeUnique(pps._post);
				filesArray = assumeUnique(pps._files);
				files = keepLastOf(filesArray);
				post = keepLastOf(postArray);
				this.postJson = pps.postJson;
				cleanUpPostDataState();
			}

			version(preserveData)
				originalPostData = data;
		}
		// fixme: remote_user script name


		this.port = port;
		this.referrer = referrer;
		this.remoteAddress = remoteAddress;
		this.userAgent = userAgent;
		this.authorization = authorization;
		this.origin = origin;
		this.accept = accept;
		this.lastEventId = lastEventId;
		this.https = https;
		this.host = host;
		this.requestMethod = requestMethod;
		this.requestUri = requestUri;
		this.pathInfo = pathInfo;
		this.queryString = queryString;
	}

	/// Cleans up any temporary files. Do not use the object
	/// after calling this.
	///
	/// NOTE: it is called automatically by GenericMain
	// FIXME: this should be called if the constructor fails too, if it has created some garbage...
	void dispose() {
		foreach(file; files) {
			if(!file.contentInMemory)
				if(std.file.exists(file.contentFilename))
					std.file.remove(file.contentFilename);
		}
	}

	private {
		struct PostParserState {
			string contentType;
			string boundary;
			string localBoundary; // the ones used at the end or something lol
			bool isMultipart;
			bool isJson;

			ulong expectedLength;
			ulong contentConsumed;
			immutable(ubyte)[] buffer;

			// multipart parsing state
			int whatDoWeWant;
			bool weHaveAPart;
			string[] thisOnesHeaders;
			immutable(ubyte)[] thisOnesData;

			string postJson;

			UploadedFile piece;
			bool isFile = false;

			size_t memoryCommitted;

			// do NOT keep mutable references to these anywhere!
			// I assume they are unique in the constructor once we're all done getting data.
			string[][string] _post;
			UploadedFile[][string] _files;
		}

		PostParserState pps;
	}

	/// This represents a file the user uploaded via a POST request.
	static struct UploadedFile {
		/// If you want to create one of these structs for yourself from some data,
		/// use this function.
		static UploadedFile fromData(immutable(void)[] data, string name = null) {
			Cgi.UploadedFile f;
			f.filename = name;
			f.content = cast(immutable(ubyte)[]) data;
			f.contentInMemory = true;
			return f;
		}

		string name; 		/// The name of the form element.
		string filename; 	/// The filename the user set.
		string contentType; 	/// The MIME type the user's browser reported. (Not reliable.)

		/**
			For small files, cgi.d will buffer the uploaded file in memory, and make it
			directly accessible to you through the content member. I find this very convenient
			and somewhat efficient, since it can avoid hitting the disk entirely. (I
			often want to inspect and modify the file anyway!)

			I find the file is very large, it is undesirable to eat that much memory just
			for a file buffer. In those cases, if you pass a large enough value for maxContentLength
			to the constructor so they are accepted, cgi.d will write the content to a temporary
			file that you can re-read later.

			You can override this behavior by subclassing Cgi and overriding the protected
			handlePostChunk method. Note that the object is not initialized when you
			write that method - the http headers are available, but the cgi.post method
			is not. You may parse the file as it streams in using this method.


			Anyway, if the file is small enough to be in memory, contentInMemory will be
			set to true, and the content is available in the content member.

			If not, contentInMemory will be set to false, and the content saved in a file,
			whose name will be available in the contentFilename member.


			Tip: if you know you are always dealing with small files, and want the convenience
			of ignoring this member, construct Cgi with a small maxContentLength. Then, if
			a large file comes in, it simply throws an exception (and HTTP error response)
			instead of trying to handle it.

			The default value of maxContentLength in the constructor is for small files.
		*/
		bool contentInMemory = true; // the default ought to always be true
		immutable(ubyte)[] content; /// The actual content of the file, if contentInMemory == true
		string contentFilename; /// the file where we dumped the content, if contentInMemory == false. Note that if you want to keep it, you MUST move the file, since otherwise it is considered garbage when cgi is disposed.

		///
		ulong fileSize() {
			if(contentInMemory)
				return content.length;
			import std.file;
			return std.file.getSize(contentFilename);

		}


		///
		void writeToFile(string filenameToSaveTo) {
			import std.file;
			if(contentInMemory)
				std.file.write(filenameToSaveTo, content);
			else
				std.file.rename(contentFilename, filenameToSaveTo);
		}
	}

	// given a content type and length, decide what we're going to do with the data..
	protected void prepareForIncomingDataChunks(string contentType, ulong contentLength) {
		pps.expectedLength = contentLength;

		auto terminator = contentType.indexOf(";");
		if(terminator == -1)
			terminator = contentType.length;

		pps.contentType = contentType[0 .. terminator];
		auto b = contentType[terminator .. $];
		if(b.length) {
			auto idx = b.indexOf("boundary=");
			if(idx != -1) {
				pps.boundary = b[idx + "boundary=".length .. $];
				pps.localBoundary = "\r\n--" ~ pps.boundary;
			}
		}

		// while a content type SHOULD be sent according to the RFC, it is
		// not required. We're told we SHOULD guess by looking at the content
		// but it seems to me that this only happens when it is urlencoded.
		if(pps.contentType == "application/x-www-form-urlencoded" || pps.contentType == "") {
			pps.isMultipart = false;
		} else if(pps.contentType == "multipart/form-data") {
			pps.isMultipart = true;
			enforce(pps.boundary.length, "no boundary");
		} else if(pps.contentType == "text/plain") {
			pps.isMultipart = false;
			pps.isJson = true; // FIXME: hack, it isn't actually this
		} else if(pps.contentType == "text/xml") { // FIXME: what if we used this as a fallback?
			pps.isMultipart = false;
			pps.isJson = true; // FIXME: hack, it isn't actually this
		} else if(pps.contentType == "application/json") {
			pps.isJson = true;
			pps.isMultipart = false;
		//} else if(pps.contentType == "application/json") {
			//pps.isJson = true;
		} else {
			// FIXME: should set a http error code too
			throw new Exception("unknown request content type: " ~ pps.contentType);
		}
	}

	// handles streaming POST data. If you handle some other content type, you should
	// override this. If the data isn't the content type you want, you ought to call
	// super.handleIncomingDataChunk so regular forms and files still work.

	// FIXME: I do some copying in here that I'm pretty sure is unnecessary, and the
	// file stuff I'm sure is inefficient. But, my guess is the real bottleneck is network
	// input anyway, so I'm not going to get too worked up about it right now.
	protected void handleIncomingDataChunk(const(ubyte)[] chunk) {
		if(chunk.length == 0)
			return;
		assert(chunk.length <= 32 * 1024 * 1024); // we use chunk size as a memory constraint thing, so
							// if we're passed big chunks, it might throw unnecessarily.
							// just pass it smaller chunks at a time.
		if(pps.isMultipart) {
			// multipart/form-data


			void pieceHasNewContent() {
				// we just grew the piece's buffer. Do we have to switch to file backing?
				if(pps.piece.contentInMemory) {
					if(pps.piece.content.length <= 10 * 1024 * 1024)
						// meh, I'm ok with it.
						return;
					else {
						// this is too big.
						if(!pps.isFile)
							throw new Exception("Request entity too large"); // a variable this big is kinda ridiculous, just reject it.
						else {
							// a file this large is probably acceptable though... let's use a backing file.
							pps.piece.contentInMemory = false;
							// FIXME: say... how do we intend to delete these things? cgi.dispose perhaps.

							int count = 0;
							pps.piece.contentFilename = getTempDirectory() ~ "arsd_cgi_uploaded_file_" ~ to!string(getUtcTime()) ~ "-" ~ to!string(count);
							// odds are this loop will never be entered, but we want it just in case.
							while(std.file.exists(pps.piece.contentFilename)) {
								count++;
								pps.piece.contentFilename = getTempDirectory() ~ "arsd_cgi_uploaded_file_" ~ to!string(getUtcTime()) ~ "-" ~ to!string(count);
							}
							// I hope this creates the file pretty quickly, or the loop might be useless...
							// FIXME: maybe I should write some kind of custom transaction here.
							std.file.write(pps.piece.contentFilename, pps.piece.content);

							pps.piece.content = null;
						}
					}
				} else {
					// it's already in a file, so just append it to what we have
					if(pps.piece.content.length) {
						// FIXME: this is surely very inefficient... we'll be calling this by 4kb chunk...
						std.file.append(pps.piece.contentFilename, pps.piece.content);
						pps.piece.content = null;
					}
				}
			}


			void commitPart() {
				if(!pps.weHaveAPart)
					return;

				pieceHasNewContent(); // be sure the new content is handled every time

				if(pps.isFile) {
					// I'm not sure if other environments put files in post or not...
					// I used to not do it, but I think I should, since it is there...
					pps._post[pps.piece.name] ~= pps.piece.filename;
					pps._files[pps.piece.name] ~= pps.piece;

					allPostNamesInOrder ~= pps.piece.name;
					allPostValuesInOrder ~= pps.piece.filename;
				} else {
					pps._post[pps.piece.name] ~= cast(string) pps.piece.content;

					allPostNamesInOrder ~= pps.piece.name;
					allPostValuesInOrder ~= cast(string) pps.piece.content;
				}

				/*
				stderr.writeln("RECEIVED: ", pps.piece.name, "=", 
					pps.piece.content.length < 1000
					?
					to!string(pps.piece.content)
					:
					"too long");
				*/

				// FIXME: the limit here
				pps.memoryCommitted += pps.piece.content.length;

				pps.weHaveAPart = false;
				pps.whatDoWeWant = 1;
				pps.thisOnesHeaders = null;
				pps.thisOnesData = null;

				pps.piece = UploadedFile.init;
				pps.isFile = false;
			}

			void acceptChunk() {
				pps.buffer ~= chunk;
				chunk = null; // we've consumed it into the buffer, so keeping it just brings confusion
			}

			immutable(ubyte)[] consume(size_t howMuch) {
				pps.contentConsumed += howMuch;
				auto ret = pps.buffer[0 .. howMuch];
				pps.buffer = pps.buffer[howMuch .. $];
				return ret;
			}

			dataConsumptionLoop: do {
			switch(pps.whatDoWeWant) {
				default: assert(0);
				case 0:
					acceptChunk();
					// the format begins with two extra leading dashes, then we should be at the boundary
					if(pps.buffer.length < 2)
						return;
					assert(pps.buffer[0] == '-', "no leading dash");
					consume(1);
					assert(pps.buffer[0] == '-', "no second leading dash");
					consume(1);

					pps.whatDoWeWant = 1;
					goto case 1;
				/* fallthrough */
				case 1: // looking for headers
					// here, we should be lined up right at the boundary, which is followed by a \r\n

					// want to keep the buffer under control in case we're under attack
					//stderr.writeln("here once");
					//if(pps.buffer.length + chunk.length > 70 * 1024) // they should be < 1 kb really....
					//	throw new Exception("wtf is up with the huge mime part headers");

					acceptChunk();

					if(pps.buffer.length < pps.boundary.length)
						return; // not enough data, since there should always be a boundary here at least

					if(pps.contentConsumed + pps.boundary.length + 6 == pps.expectedLength) {
						assert(pps.buffer.length == pps.boundary.length + 4 + 2); // --, --, and \r\n
						// we *should* be at the end here!
						assert(pps.buffer[0] == '-');
						consume(1);
						assert(pps.buffer[0] == '-');
						consume(1);

						// the message is terminated by --BOUNDARY--\r\n (after a \r\n leading to the boundary)
						assert(pps.buffer[0 .. pps.boundary.length] == cast(const(ubyte[])) pps.boundary,
							"not lined up on boundary " ~ pps.boundary);
						consume(pps.boundary.length);

						assert(pps.buffer[0] == '-');
						consume(1);
						assert(pps.buffer[0] == '-');
						consume(1);

						assert(pps.buffer[0] == '\r');
						consume(1);
						assert(pps.buffer[0] == '\n');
						consume(1);

						assert(pps.buffer.length == 0);
						assert(pps.contentConsumed == pps.expectedLength);
						break dataConsumptionLoop; // we're done!
					} else {
						// we're not done yet. We should be lined up on a boundary.

						// But, we want to ensure the headers are here before we consume anything!
						auto headerEndLocation = locationOf(pps.buffer, "\r\n\r\n");
						if(headerEndLocation == -1)
							return; // they *should* all be here, so we can handle them all at once.

						assert(pps.buffer[0 .. pps.boundary.length] == cast(const(ubyte[])) pps.boundary,
							"not lined up on boundary " ~ pps.boundary);

						consume(pps.boundary.length);
						// the boundary is always followed by a \r\n
						assert(pps.buffer[0] == '\r');
						consume(1);
						assert(pps.buffer[0] == '\n');
						consume(1);
					}

					// re-running since by consuming the boundary, we invalidate the old index.
					auto headerEndLocation = locationOf(pps.buffer, "\r\n\r\n");
					assert(headerEndLocation >= 0, "no header");
					auto thisOnesHeaders = pps.buffer[0..headerEndLocation];

					consume(headerEndLocation + 4); // The +4 is the \r\n\r\n that caps it off

					pps.thisOnesHeaders = split(cast(string) thisOnesHeaders, "\r\n");

					// now we'll parse the headers
					foreach(h; pps.thisOnesHeaders) {
						auto p = h.indexOf(":");
						assert(p != -1, "no colon in header, got " ~ to!string(pps.thisOnesHeaders));
						string hn = h[0..p];
						string hv = h[p+2..$];

						switch(hn.toLower) {
							default: assert(0);
							case "content-disposition":
								auto info = hv.split("; ");
								foreach(i; info[1..$]) { // skipping the form-data
									auto o = i.split("="); // FIXME
									string pn = o[0];
									string pv = o[1][1..$-1];

									if(pn == "name") {
										pps.piece.name = pv;
									} else if (pn == "filename") {
										pps.piece.filename = pv;
										pps.isFile = true;
									}
								}
							break;
							case "content-type":
								pps.piece.contentType = hv;
							break;
						}
					}

					pps.whatDoWeWant++; // move to the next step - the data
				break;
				case 2:
					// when we get here, pps.buffer should contain our first chunk of data

					if(pps.buffer.length + chunk.length > 8 * 1024 * 1024) // we might buffer quite a bit but not much
						throw new Exception("wtf is up with the huge mime part buffer");

					acceptChunk();

					// so the trick is, we want to process all the data up to the boundary,
					// but what if the chunk's end cuts the boundary off? If we're unsure, we
					// want to wait for the next chunk. We start by looking for the whole boundary
					// in the buffer somewhere.

					auto boundaryLocation = locationOf(pps.buffer, pps.localBoundary);
					// assert(boundaryLocation != -1, "should have seen "~to!string(cast(ubyte[]) pps.localBoundary)~" in " ~ to!string(pps.buffer));
					if(boundaryLocation != -1) {
						// this is easy - we can see it in it's entirety!

						pps.piece.content ~= consume(boundaryLocation);

						assert(pps.buffer[0] == '\r');
						consume(1);
						assert(pps.buffer[0] == '\n');
						consume(1);
						assert(pps.buffer[0] == '-');
						consume(1);
						assert(pps.buffer[0] == '-');
						consume(1);
						// the boundary here is always preceded by \r\n--, which is why we used localBoundary instead of boundary to locate it. Cut that off.
						pps.weHaveAPart = true;
						pps.whatDoWeWant = 1; // back to getting headers for the next part

						commitPart(); // we're done here
					} else {
						// we can't see the whole thing, but what if there's a partial boundary?

						enforce(pps.localBoundary.length < 128); // the boundary ought to be less than a line...
						assert(pps.localBoundary.length > 1); // should already be sane but just in case
						bool potentialBoundaryFound = false;

						boundaryCheck: for(int a = 1; a < pps.localBoundary.length; a++) {
							// we grow the boundary a bit each time. If we think it looks the
							// same, better pull another chunk to be sure it's not the end.
							// Starting small because exiting the loop early is desirable, since
							// we're not keeping any ambiguity and 1 / 256 chance of exiting is
							// the best we can do.
							if(a > pps.buffer.length)
								break; // FIXME: is this right?
							assert(a <= pps.buffer.length);
							assert(a > 0);
							if(std.algorithm.endsWith(pps.buffer, pps.localBoundary[0 .. a])) {
								// ok, there *might* be a boundary here, so let's
								// not treat the end as data yet. The rest is good to
								// use though, since if there was a boundary there, we'd
								// have handled it up above after locationOf.

								pps.piece.content ~= pps.buffer[0 .. $ - a];
								consume(pps.buffer.length - a);
								pieceHasNewContent();
								potentialBoundaryFound = true;
								break boundaryCheck;
							}
						}

						if(!potentialBoundaryFound) {
							// we can consume the whole thing
							pps.piece.content ~= pps.buffer;
							pieceHasNewContent();
							consume(pps.buffer.length);
						} else {
							// we found a possible boundary, but there was
							// insufficient data to be sure.
							assert(pps.buffer == cast(const(ubyte[])) pps.localBoundary[0 .. pps.buffer.length]);

							return; // wait for the next chunk.
						}
					}
			}
			} while(pps.buffer.length);

			// btw all boundaries except the first should have a \r\n before them
		} else {
			// application/x-www-form-urlencoded and application/json

				// not using maxContentLength because that might be cranked up to allow
				// large file uploads. We can handle them, but a huge post[] isn't any good.
			if(pps.buffer.length + chunk.length > 8 * 1024 * 1024) // surely this is plenty big enough
				throw new Exception("wtf is up with such a gigantic form submission????");

			pps.buffer ~= chunk;

			// simple handling, but it works... until someone bombs us with gigabytes of crap at least...
			if(pps.buffer.length == pps.expectedLength) {
				if(pps.isJson)
					pps.postJson = cast(string) pps.buffer;
				else
					pps._post = decodeVariables(cast(string) pps.buffer, "&", &allPostNamesInOrder, &allPostValuesInOrder);
				version(preserveData)
					originalPostData = pps.buffer;
			} else {
				// just for debugging
			}
		}
	}

	protected void cleanUpPostDataState() {
		pps = PostParserState.init;
	}

	/// you can override this function to somehow react
	/// to an upload in progress.
	///
	/// Take note that parts of the CGI object is not yet
	/// initialized! Stuff from HTTP headers, including get[], is usable.
	/// But, none of post[] is usable, and you cannot write here. That's
	/// why this method is const - mutating the object won't do much anyway.
	///
	/// My idea here was so you can output a progress bar or
	/// something to a cooperative client (see arsd.rtud for a potential helper)
	///
	/// The default is to do nothing. Subclass cgi and use the 
	/// CustomCgiMain mixin to do something here.
	void onRequestBodyDataReceived(size_t receivedSoFar, size_t totalExpected) const {
		// This space intentionally left blank.
	}

	/// Initializes the cgi from completely raw HTTP data. The ir must have a Socket source.
	/// *closeConnection will be set to true if you should close the connection after handling this request
	this(BufferedInputRange ir, bool* closeConnection) {
		isCalledWithCommandLineArguments = false;
		import al = std.algorithm;

		immutable(ubyte)[] data;

		void rdo(const(ubyte)[] d) {
			sendAll(ir.source, d);
		}

		this(ir, ir.source.remoteAddress().toString(), 80 /* FIXME */, 0, false, &rdo, null, closeConnection);
	}

	/**
		Initializes it from raw HTTP request data. GenericMain uses this when you compile with -version=embedded_httpd.

		NOTE: If you are behind a reverse proxy, the values here might not be what you expect.... it will use X-Forwarded-For for remote IP and X-Forwarded-Host for host

		Params:
			inputData = the incoming data, including headers and other raw http data.
				When the constructor exits, it will leave this range exactly at the start of
				the next request on the connection (if there is one).

			address = the IP address of the remote user
			_port = the port number of the connection
			pathInfoStarts = the offset into the path component of the http header where the SCRIPT_NAME ends and the PATH_INFO begins.
			_https = if this connection is encrypted (note that the input data must not actually be encrypted)
			_rawDataOutput = delegate to accept response data. It should write to the socket or whatever; Cgi does all the needed processing to speak http.
			_flush = if _rawDataOutput buffers, this delegate should flush the buffer down the wire
			closeConnection = if the request asks to close the connection, *closeConnection == true.
	*/
	this(
		BufferedInputRange inputData,
//		string[] headers, immutable(ubyte)[] data,
		string address, ushort _port,
		int pathInfoStarts = 0, // use this if you know the script name, like if this is in a folder in a bigger web environment
		bool _https = false,
		void delegate(const(ubyte)[]) _rawDataOutput = null,
		void delegate() _flush = null,
		// this pointer tells if the connection is supposed to be closed after we handle this
		bool* closeConnection = null)
	{
		// these are all set locally so the loop works
		// without triggering errors in dmd 2.064
		// we go ahead and set them at the end of it to the this version
		int port;
		string referrer;
		string remoteAddress;
		string userAgent;
		string authorization;
		string origin;
		string accept;
		string lastEventId;
		bool https;
		string host;
		RequestMethod requestMethod;
		string requestUri;
		string pathInfo;
		string queryString;
		string scriptName;
		string[string] get;
		string[][string] getArray;
		bool keepAliveRequested;
		bool acceptsGzip;
		string cookie;



		environmentVariables = cast(const) environment.toAA;

		idlol = inputData;

		isCalledWithCommandLineArguments = false;

		https = _https;
		port = _port;

		rawDataOutput = _rawDataOutput;
		flushDelegate = _flush;
		nph = true;

		remoteAddress = address;

		// streaming parser
		import al = std.algorithm;

			// FIXME: tis cast is technically wrong, but Phobos deprecated al.indexOf... for some reason.
		auto idx = indexOf(cast(string) inputData.front(), "\r\n\r\n");
		while(idx == -1) {
			inputData.popFront(0);
			idx = indexOf(cast(string) inputData.front(), "\r\n\r\n");
		}

		assert(idx != -1);


		string contentType = "";
		string[string] requestHeadersHere;

		size_t contentLength;

		bool isChunked;

		{
			import core.runtime;
			scriptFileName = Runtime.args[0];
		}


		int headerNumber = 0;
		foreach(line; al.splitter(inputData.front()[0 .. idx], "\r\n"))
		if(line.length) {
			headerNumber++;
			auto header = cast(string) line.idup;
			if(headerNumber == 1) {
				// request line
				auto parts = al.splitter(header, " ");
				requestMethod = to!RequestMethod(parts.front);
				parts.popFront();
				requestUri = parts.front;

				scriptName = requestUri[0 .. pathInfoStarts];

				auto question = requestUri.indexOf("?");
				if(question == -1) {
					queryString = "";
					// FIXME: double check, this might be wrong since it could be url encoded
					pathInfo = requestUri[pathInfoStarts..$];
				} else {
					queryString = requestUri[question+1..$];
					pathInfo = requestUri[pathInfoStarts..question];
				}

				auto ugh = decodeVariables(queryString, "&", &allGetNamesInOrder, &allGetValuesInOrder);
				getArray = cast(string[][string]) assumeUnique(ugh);

				if(header.indexOf("HTTP/1.0") != -1) {
					http10 = true;
					autoBuffer = true;
					if(closeConnection) {
						// on http 1.0, close is assumed (unlike http/1.1 where we assume keep alive)
						*closeConnection = true;
					}
				}
			} else {
				// other header
				auto colon = header.indexOf(":");
				if(colon == -1)
					throw new Exception("HTTP headers should have a colon!");
				string name = header[0..colon].toLower;
				string value = header[colon+2..$]; // skip the colon and the space

				requestHeadersHere[name] = value;

				if (name == "accept") {
					accept = value;
				}
				else if (name == "origin") {
					origin = value;
				}
				else if (name == "connection") {
					if(value == "close" && closeConnection)
						*closeConnection = true;
					if(value.asLowerCase().canFind("keep-alive")) {
						keepAliveRequested = true;

						// on http 1.0, the connection is closed by default,
						// but not if they request keep-alive. then we don't close
						// anymore - undoing the set above
						if(http10 && closeConnection) {
							*closeConnection = false;
						}
					}
				}
				else if (name == "transfer-encoding") {
					if(value == "chunked")
						isChunked = true;
				}
				else if (name == "last-event-id") {
					lastEventId = value;
				}
				else if (name == "authorization") {
					authorization = value;
				}
				else if (name == "content-type") {
					contentType = value;
				}
				else if (name == "content-length") {
					contentLength = to!size_t(value);
				}
				else if (name == "x-forwarded-for") {
					remoteAddress = value;
				}
				else if (name == "x-forwarded-host" || name == "host") {
					host = value;
				}
				else if (name == "accept-encoding") {
					if(value.indexOf("gzip") != -1)
						acceptsGzip = true;
				}
				else if (name == "user-agent") {
					userAgent = value;
				}
				else if (name == "referer") {
					referrer = value;
				}
				else if (name == "cookie") {
					cookie ~= value;
				}
				// else
				// ignore it

			}
		}

		inputData.consume(idx + 4);
		// done

		requestHeaders = assumeUnique(requestHeadersHere);

		ByChunkRange dataByChunk;

		// reading Content-Length type data
		// We need to read up the data we have, and write it out as a chunk.
		if(!isChunked) {
			dataByChunk = byChunk(inputData, contentLength);
		} else {
			// chunked requests happen, but not every day. Since we need to know
			// the content length (for now, maybe that should change), we'll buffer
			// the whole thing here instead of parse streaming. (I think this is what Apache does anyway in cgi modes)
			auto data = dechunk(inputData);

			// set the range here
			dataByChunk = byChunk(data);
			contentLength = data.length;
		}

		assert(dataByChunk !is null);

		if(contentLength) {
			prepareForIncomingDataChunks(contentType, contentLength);
			foreach(dataChunk; dataByChunk) {
				handleIncomingDataChunk(dataChunk);
			}
			postArray = assumeUnique(pps._post);
			filesArray = assumeUnique(pps._files);
			files = keepLastOf(filesArray);
			post = keepLastOf(postArray);
			postJson = pps.postJson;
			cleanUpPostDataState();
		}

		this.port = port;
		this.referrer = referrer;
		this.remoteAddress = remoteAddress;
		this.userAgent = userAgent;
		this.authorization = authorization;
		this.origin = origin;
		this.accept = accept;
		this.lastEventId = lastEventId;
		this.https = https;
		this.host = host;
		this.requestMethod = requestMethod;
		this.requestUri = requestUri;
		this.pathInfo = pathInfo;
		this.queryString = queryString;

		this.scriptName = scriptName;
		this.get = keepLastOf(getArray);
		this.getArray = cast(immutable) getArray;
		this.keepAliveRequested = keepAliveRequested;
		this.acceptsGzip = acceptsGzip;
		this.cookie = cookie;

		cookiesArray = getCookieArray();
		cookies = keepLastOf(cookiesArray);

	}
	BufferedInputRange idlol;

	private immutable(string[string]) keepLastOf(in string[][string] arr) {
		string[string] ca;
		foreach(k, v; arr)
			ca[k] = v[$-1];

		return assumeUnique(ca);
	}

	// FIXME duplication
	private immutable(UploadedFile[string]) keepLastOf(in UploadedFile[][string] arr) {
		UploadedFile[string] ca;
		foreach(k, v; arr)
			ca[k] = v[$-1];

		return assumeUnique(ca);
	}


	private immutable(string[][string]) getCookieArray() {
		auto forTheLoveOfGod = decodeVariables(cookie, "; ");
		return assumeUnique(forTheLoveOfGod);
	}

	/// Very simple method to require a basic auth username and password.
	/// If the http request doesn't include the required credentials, it throws a
	/// HTTP 401 error, and an exception.
	///
	/// Note: basic auth does not provide great security, especially over unencrypted HTTP;
	/// the user's credentials are sent in plain text on every request.
	///
	/// If you are using Apache, the HTTP_AUTHORIZATION variable may not be sent to the
	/// application. Either use Apache's built in methods for basic authentication, or add
	/// something along these lines to your server configuration:
	///
	///      RewriteEngine On 
	///      RewriteCond %{HTTP:Authorization} ^(.*) 
	///      RewriteRule ^(.*) - [E=HTTP_AUTHORIZATION:%1]
	///
	/// To ensure the necessary data is available to cgi.d.
	void requireBasicAuth(string user, string pass, string message = null) {
		if(authorization != "Basic " ~ Base64.encode(cast(immutable(ubyte)[]) (user ~ ":" ~ pass))) {
			setResponseStatus("401 Authorization Required");
			header ("WWW-Authenticate: Basic realm=\""~message~"\"");
			close();
			throw new Exception("Not authorized; got " ~ authorization);
		}
	}

	/// Very simple caching controls - setCache(false) means it will never be cached. Good for rapidly updated or sensitive sites.
	/// setCache(true) means it will always be cached for as long as possible. Best for static content.
	/// Use setResponseExpires and updateResponseExpires for more control
	void setCache(bool allowCaching) {
		noCache = !allowCaching;
	}

	/// Set to true and use cgi.write(data, true); to send a gzipped response to browsers
	/// who can accept it
	bool gzipResponse;

	immutable bool acceptsGzip;
	immutable bool keepAliveRequested;

	/// Set to true if and only if this was initialized with command line arguments
	immutable bool isCalledWithCommandLineArguments;

	/// This gets a full url for the current request, including port, protocol, host, path, and query
	string getCurrentCompleteUri() const {
		ushort defaultPort = https ? 443 : 80;

		return format("http%s://%s%s%s",
			https ? "s" : "",
			host,
			(!port || port == defaultPort) ? "" : ":" ~ to!string(port),
			requestUri);
	}

	/// You can override this if your site base url isn't the same as the script name
	string logicalScriptName() const {
		return scriptName;
	}

	/// Sets the HTTP status of the response. For example, "404 File Not Found" or "500 Internal Server Error".
	/// It assumes "200 OK", and automatically changes to "302 Found" if you call setResponseLocation().
	/// Note setResponseStatus() must be called *before* you write() any data to the output.
	void setResponseStatus(string status) {
		assert(!outputtedResponseData);
		responseStatus = status;
	}
	private string responseStatus = null;

	/// Returns true if it is still possible to output headers
	bool canOutputHeaders() {
		return !isClosed && !outputtedResponseData;
	}

	/// Sets the location header, which the browser will redirect the user to automatically.
	/// Note setResponseLocation() must be called *before* you write() any data to the output.
	/// The optional important argument is used if it's a default suggestion rather than something to insist upon.
	void setResponseLocation(string uri, bool important = true, string status = null) {
		if(!important && isCurrentResponseLocationImportant)
			return; // important redirects always override unimportant ones

		if(uri is null) {
			responseStatus = "200 OK";
			responseLocation = null;
			isCurrentResponseLocationImportant = important;
			return; // this just cancels the redirect
		}

		assert(!outputtedResponseData);
		if(status is null)
			responseStatus = "302 Found";
		else
			responseStatus = status;

		responseLocation = uri.strip;
		isCurrentResponseLocationImportant = important;
	}
	protected string responseLocation = null;
	private bool isCurrentResponseLocationImportant = false;

	/// Sets the Expires: http header. See also: updateResponseExpires, setPublicCaching
	/// The parameter is in unix_timestamp * 1000. Try setResponseExpires(getUTCtime() + SOME AMOUNT) for normal use.
	/// Note: the when parameter is different than setCookie's expire parameter.
	void setResponseExpires(long when, bool isPublic = false) {
		responseExpires = when;
		setCache(true); // need to enable caching so the date has meaning

		responseIsPublic = isPublic;
	}
	private long responseExpires = long.min;
	private bool responseIsPublic = false;

	/// This is like setResponseExpires, but it can be called multiple times. The setting most in the past is the one kept.
	/// If you have multiple functions, they all might call updateResponseExpires about their own return value. The program
	/// output as a whole is as cacheable as the least cachable part in the chain.

	/// setCache(false) always overrides this - it is, by definition, the strictest anti-cache statement available. If your site outputs sensitive user data, you should probably call setCache(false) when you do, to ensure no other functions will cache the content, as it may be a privacy risk.
	/// Conversely, setting here overrides setCache(true), since any expiration date is in the past of infinity.
	void updateResponseExpires(long when, bool isPublic) {
		if(responseExpires == long.min)
			setResponseExpires(when, isPublic);
		else if(when < responseExpires)
			setResponseExpires(when, responseIsPublic && isPublic); // if any part of it is private, it all is
	}

	/*
	/// Set to true if you want the result to be cached publically - that is, is the content shared?
	/// Should generally be false if the user is logged in. It assumes private cache only.
	/// setCache(true) also turns on public caching, and setCache(false) sets to private.
	void setPublicCaching(bool allowPublicCaches) {
		publicCaching = allowPublicCaches;
	}
	private bool publicCaching = false;
	*/

	/// Sets an HTTP cookie, automatically encoding the data to the correct string.
	/// expiresIn is how many milliseconds in the future the cookie will expire.
	/// TIP: to make a cookie accessible from subdomains, set the domain to .yourdomain.com.
	/// Note setCookie() must be called *before* you write() any data to the output.
	void setCookie(string name, string data, long expiresIn = 0, string path = null, string domain = null, bool httpOnly = false, bool secure = false) {
		assert(!outputtedResponseData);
		string cookie = std.uri.encodeComponent(name) ~ "=";
		cookie ~= std.uri.encodeComponent(data);
		if(path !is null)
			cookie ~= "; path=" ~ path;
		// FIXME: should I just be using max-age here? (also in cache below)
		if(expiresIn != 0)
			cookie ~= "; expires=" ~ printDate(cast(DateTime) Clock.currTime(UTC()) + dur!"msecs"(expiresIn));
		if(domain !is null)
			cookie ~= "; domain=" ~ domain;
		if(secure == true)
			cookie ~= "; Secure";
		if(httpOnly == true )
			cookie ~= "; HttpOnly";

		if(auto idx = name in cookieIndexes) {
			responseCookies[*idx] = cookie;
		} else {
			cookieIndexes[name] = responseCookies.length;
			responseCookies ~= cookie;
		}
	}
	private string[] responseCookies;
	private size_t[string] cookieIndexes;

	/// Clears a previously set cookie with the given name, path, and domain.
	void clearCookie(string name, string path = null, string domain = null) {
		assert(!outputtedResponseData);
		setCookie(name, "", 1, path, domain);
	}

	/// Sets the content type of the response, for example "text/html" (the default) for HTML, or "image/png" for a PNG image
	void setResponseContentType(string ct) {
		assert(!outputtedResponseData);
		responseContentType = ct;
	}
	private string responseContentType = null;

	/// Adds a custom header. It should be the name: value, but without any line terminator.
	/// For example: header("X-My-Header: Some value");
	/// Note you should use the specialized functions in this object if possible to avoid
	/// duplicates in the output.
	void header(string h) {
		customHeaders ~= h;
	}

	private string[] customHeaders;
	private bool websocketMode;

	void flushHeaders(const(void)[] t, bool isAll = false) {
		string[] hd;
		// Flush the headers
		if(responseStatus !is null) {
			if(nph) {
				if(http10)
					hd ~= "HTTP/1.0 " ~ responseStatus;
				else
					hd ~= "HTTP/1.1 " ~ responseStatus;
			} else
				hd ~= "Status: " ~ responseStatus;
		} else if (nph) {
			if(http10)
				hd ~= "HTTP/1.0 200 OK";
			else
				hd ~= "HTTP/1.1 200 OK";
		}

		if(websocketMode)
			goto websocket;

		if(nph) { // we're responsible for setting the date too according to http 1.1
			hd ~= "Date: " ~ printDate(cast(DateTime) Clock.currTime(UTC()));
		}

		// FIXME: what if the user wants to set his own content-length?
		// The custom header function can do it, so maybe that's best.
		// Or we could reuse the isAll param.
		if(responseLocation !is null) {
			hd ~= "Location: " ~ responseLocation;
		}
		if(!noCache && responseExpires != long.min) { // an explicit expiration date is set
			auto expires = SysTime(unixTimeToStdTime(cast(int)(responseExpires / 1000)), UTC());
			hd ~= "Expires: " ~ printDate(
				cast(DateTime) expires);
			// FIXME: assuming everything is private unless you use nocache - generally right for dynamic pages, but not necessarily
			hd ~= "Cache-Control: "~(responseIsPublic ? "public" : "private")~", no-cache=\"set-cookie, set-cookie2\"";
		}
		if(responseCookies !is null && responseCookies.length > 0) {
			foreach(c; responseCookies)
				hd ~= "Set-Cookie: " ~ c;
		}
		if(noCache) { // we specifically do not want caching (this is actually the default)
			hd ~= "Cache-Control: private, no-cache=\"set-cookie\"";
			hd ~= "Expires: 0";
			hd ~= "Pragma: no-cache";
		} else {
			if(responseExpires == long.min) { // caching was enabled, but without a date set - that means assume cache forever
				hd ~= "Cache-Control: public";
				hd ~= "Expires: Tue, 31 Dec 2030 14:00:00 GMT"; // FIXME: should not be more than one year in the future
			}
		}
		if(responseContentType !is null) {
			hd ~= "Content-Type: " ~ responseContentType;
		} else
			hd ~= "Content-Type: text/html; charset=utf-8";

		if(gzipResponse && acceptsGzip && isAll) { // FIXME: isAll really shouldn't be necessary
			hd ~= "Content-Encoding: gzip";
		}


		if(!isAll) {
			if(nph && !http10) {
				hd ~= "Transfer-Encoding: chunked";
				responseChunked = true;
			}
		} else {
			hd ~= "Content-Length: " ~ to!string(t.length);
			if(nph && keepAliveRequested) {
				hd ~= "Connection: Keep-Alive";
			}
		}

		websocket:
		if(customHeaders !is null)
			hd ~= customHeaders;

		// FIXME: what about duplicated headers?

		foreach(h; hd) {
			if(rawDataOutput !is null)
				rawDataOutput(cast(const(ubyte)[]) (h ~ "\r\n"));
			else
				writeln(h);
		}
		if(rawDataOutput !is null)
			rawDataOutput(cast(const(ubyte)[]) ("\r\n"));
		else
			writeln("");

		outputtedResponseData = true;
	}

	/// Writes the data to the output, flushing headers if they have not yet been sent.
	void write(const(void)[] t, bool isAll = false, bool maybeAutoClose = true) {
		assert(!closed, "Output has already been closed");

		if(gzipResponse && acceptsGzip && isAll) { // FIXME: isAll really shouldn't be necessary
			// actually gzip the data here

			auto c = new Compress(HeaderFormat.gzip); // want gzip

			auto data = c.compress(t);
			data ~= c.flush();

			// std.file.write("/tmp/last-item", data);

			t = data;
		}

		if(!outputtedResponseData && (!autoBuffer || isAll)) {
			flushHeaders(t, isAll);
		}

		if(requestMethod != RequestMethod.HEAD && t.length > 0) {
			if (autoBuffer) {
				outputBuffer ~= cast(ubyte[]) t;
			}
			if(!autoBuffer || isAll) {
				if(rawDataOutput !is null)
					if(nph && responseChunked) {
						//rawDataOutput(makeChunk(cast(const(ubyte)[]) t));
						// we're making the chunk here instead of in a function
						// to avoid unneeded gc pressure
						rawDataOutput(cast(const(ubyte)[]) toHex(t.length));
						rawDataOutput(cast(const(ubyte)[]) "\r\n");
						rawDataOutput(cast(const(ubyte)[]) t);
						rawDataOutput(cast(const(ubyte)[]) "\r\n");


					} else {
						rawDataOutput(cast(const(ubyte)[]) t);
					}
				else
					stdout.rawWrite(t);
			}
		}

		if(maybeAutoClose && isAll)
			close(); // if you say it is all, that means we're definitely done
				// maybeAutoClose can be false though to avoid this (important if you call from inside close()!
	}

	void flush() {
		if(rawDataOutput is null)
			stdout.flush();
		else if(flushDelegate !is null)
			flushDelegate();
	}

	version(autoBuffer)
		bool autoBuffer = true;
	else
		bool autoBuffer = false;
	ubyte[] outputBuffer;

	/// Flushes the buffers to the network, signifying that you are done.
	/// You should always call this explicitly when you are done outputting data.
	void close() {
		if(closed)
			return; // don't double close

		if(!outputtedResponseData)
			write("", false, false);

		// writing auto buffered data
		if(requestMethod != RequestMethod.HEAD && autoBuffer) {
			if(!nph)
				stdout.rawWrite(outputBuffer);
			else
				write(outputBuffer, true, false); // tell it this is everything
		}

		// closing the last chunk...
		if(nph && rawDataOutput !is null && responseChunked)
			rawDataOutput(cast(const(ubyte)[]) "0\r\n\r\n");

		if(flushDelegate)
			flushDelegate();

		closed = true;
	}

	// Closes without doing anything, shouldn't be used often
	void rawClose() {
		closed = true;
	}

	/++
		Gets a request variable as a specific type, or the default value of it isn't there
		or isn't convertible to the request type.
		
		Checks both GET and POST variables, preferring the POST variable, if available.

		A nice trick is using the default value to choose the type:

		---
			/*
				The return value will match the type of the default.
				Here, I gave 10 as a default, so the return value will
				be an int.

				If the user-supplied value cannot be converted to the
				requested type, you will get the default value back.
			*/
			int a = cgi.request("number", 10);

			if(cgi.get["number"] == "11")
				assert(a == 11); // conversion succeeds

			if("number" !in cgi.get)
				assert(a == 10); // no value means you can't convert - give the default

			if(cgi.get["number"] == "twelve")
				assert(a == 10); // conversion from string to int would fail, so we get the default
		---

		You can use an enum as an easy whitelist, too:

		---
			enum Operations {
				add, remove, query
			}

			auto op = cgi.request("op", Operations.query);

			if(cgi.get["op"] == "add")
				assert(op == Operations.add);
			if(cgi.get["op"] == "remove")
				assert(op == Operations.remove);
			if(cgi.get["op"] == "query")
				assert(op == Operations.query);

			if(cgi.get["op"] == "random string")
				assert(op == Operations.query); // the value can't be converted to the enum, so we get the default
		---
	+/
	T request(T = string)(in string name, in T def = T.init) const nothrow {
		try {
			return
				(name in post) ? to!T(post[name]) :
				(name in get)  ? to!T(get[name]) :
				def;
		} catch(Exception e) { return def; }
	}

	/// Is the output already closed?
	bool isClosed() const {
		return closed;
	}

	/* Hooks for redirecting input and output */
	private void delegate(const(ubyte)[]) rawDataOutput = null;
	private void delegate() flushDelegate = null;

	/* This info is used when handling a more raw HTTP protocol */
	private bool nph;
	private bool http10;
	private bool closed;
	private bool responseChunked = false;

	version(preserveData) // note: this can eat lots of memory; don't use unless you're sure you need it.
	immutable(ubyte)[] originalPostData;

	public immutable string postJson;

	/* Internal state flags */
	private bool outputtedResponseData;
	private bool noCache = true;

	const(string[string]) environmentVariables;

	/** What follows is data gotten from the HTTP request. It is all fully immutable,
	    partially because it logically is (your code doesn't change what the user requested...)
	    and partially because I hate how bad programs in PHP change those superglobals to do
	    all kinds of hard to follow ugliness. I don't want that to ever happen in D.

	    For some of these, you'll want to refer to the http or cgi specs for more details.
	*/
	immutable(string[string]) requestHeaders; /// All the raw headers in the request as name/value pairs. The name is stored as all lower case, but otherwise the same as it is in HTTP; words separated by dashes. For example, "cookie" or "accept-encoding". Many HTTP headers have specialized variables below for more convenience and static name checking; you should generally try to use them.

	immutable(char[]) host; 	/// The hostname in the request. If one program serves multiple domains, you can use this to differentiate between them.
	immutable(char[]) origin; 	/// The origin header in the request, if present. Some HTML5 cross-domain apis set this and you should check it on those cross domain requests and websockets.
	immutable(char[]) userAgent; 	/// The browser's user-agent string. Can be used to identify the browser.
	immutable(char[]) pathInfo; 	/// This is any stuff sent after your program's name on the url, but before the query string. For example, suppose your program is named "app". If the user goes to site.com/app, pathInfo is empty. But, he can also go to site.com/app/some/sub/path; treating your program like a virtual folder. In this case, pathInfo == "/some/sub/path".
	immutable(char[]) scriptName;   /// The full base path of your program, as seen by the user. If your program is located at site.com/programs/apps, scriptName == "/programs/apps".
	immutable(char[]) scriptFileName;   /// The physical filename of your script
	immutable(char[]) authorization; /// The full authorization string from the header, undigested. Useful for implementing auth schemes such as OAuth 1.0. Note that some web servers do not forward this to the app without taking extra steps. See requireBasicAuth's comment for more info.
	immutable(char[]) accept; 	/// The HTTP accept header is the user agent telling what content types it is willing to accept. This is often */*; they accept everything, so it's not terribly useful. (The similar sounding Accept-Encoding header is handled automatically for chunking and gzipping. Simply set gzipResponse = true and cgi.d handles the details, zipping if the user's browser is willing to accept it.)
	immutable(char[]) lastEventId; 	/// The HTML 5 draft includes an EventSource() object that connects to the server, and remains open to take a stream of events. My arsd.rtud module can help with the server side part of that. The Last-Event-Id http header is defined in the draft to help handle loss of connection. When the browser reconnects to you, it sets this header to the last event id it saw, so you can catch it up. This member has the contents of that header.

	immutable(RequestMethod) requestMethod; /// The HTTP request verb: GET, POST, etc. It is represented as an enum in cgi.d (which, like many enums, you can convert back to string with std.conv.to()). A HTTP GET is supposed to, according to the spec, not have side effects; a user can GET something over and over again and always have the same result. On all requests, the get[] and getArray[] members may be filled in. The post[] and postArray[] members are only filled in on POST methods.
	immutable(char[]) queryString; 	/// The unparsed content of the request query string - the stuff after the ? in your URL. See get[] and getArray[] for a parse view of it. Sometimes, the unparsed string is useful though if you want a custom format of data up there (probably not a good idea, unless it is really simple, like "?username" perhaps.)
	immutable(char[]) cookie; 	/// The unparsed content of the Cookie: header in the request. See also the cookies[string] member for a parsed view of the data.
	/** The Referer header from the request. (It is misspelled in the HTTP spec, and thus the actual request and cgi specs too, but I spelled the word correctly here because that's sane. The spec's misspelling is an implementation detail.) It contains the site url that referred the user to your program; the site that linked to you, or if you're serving images, the site that has you as an image. Also, if you're in an iframe, the referrer is the site that is framing you.

	Important note: if the user copy/pastes your url, this is blank, and, just like with all other user data, their browsers can also lie to you. Don't rely on it for real security.
	*/
	immutable(char[]) referrer;
	immutable(char[]) requestUri; 	/// The full url if the current request, excluding the protocol and host. requestUri == scriptName ~ pathInfo ~ (queryString.length ? "?" ~ queryString : "");

	immutable(char[]) remoteAddress; /// The IP address of the user, as we see it. (Might not match the IP of the user's computer due to things like proxies and NAT.) 

	immutable bool https; 	/// Was the request encrypted via https?
	immutable int port; 	/// On what TCP port number did the server receive the request?

	/** Here come the parsed request variables - the things that come close to PHP's _GET, _POST, etc. superglobals in content. */

	immutable(string[string]) get; 	/// The data from your query string in the url, only showing the last string of each name. If you want to handle multiple values with the same name, use getArray. This only works right if the query string is x-www-form-urlencoded; the default you see on the web with name=value pairs separated by the & character.
	immutable(string[string]) post; /// The data from the request's body, on POST requests. It parses application/x-www-form-urlencoded data (used by most web requests, including typical forms), and multipart/form-data requests (used by file uploads on web forms) into the same container, so you can always access them the same way. It makes no attempt to parse other content types. If you want to accept an XML Post body (for a web api perhaps), you'll need to handle the raw data yourself.
	immutable(string[string]) cookies; /// Separates out the cookie header into individual name/value pairs (which is how you set them!)

	/**
		Represents user uploaded files.
		
		When making a file upload form, be sure to follow the standard: set method="POST" and enctype="multipart/form-data" in your html <form> tag attributes. The key into this array is the name attribute on your input tag, just like with other post variables. See the comments on the UploadedFile struct for more information about the data inside, including important notes on max size and content location.
	*/
	immutable(UploadedFile[][string]) filesArray;
	immutable(UploadedFile[string]) files;

	/// Use these if you expect multiple items submitted with the same name. btw, assert(get[name] is getArray[name][$-1); should pass. Same for post and cookies.
	/// the order of the arrays is the order the data arrives
	immutable(string[][string]) getArray; /// like get, but an array of values per name
	immutable(string[][string]) postArray; /// ditto for post
	immutable(string[][string]) cookiesArray; /// ditto for cookies

	// convenience function for appending to a uri without extra ?
	// matches the name and effect of javascript's location.search property
	string search() const {
		if(queryString.length)
			return "?" ~ queryString;
		return "";
	}

	// FIXME: what about multiple files with the same name?
  private:
	//RequestMethod _requestMethod;
}

/// use this for testing or other isolated things
Cgi dummyCgi(Cgi.RequestMethod method = Cgi.RequestMethod.GET, string url = null, in ubyte[] data = null, void delegate(const(ubyte)[]) outputSink = null) {
	// we want to ignore, not use stdout
	if(outputSink is null)
		outputSink = delegate void(const(ubyte)[]) { };

	string[string] env;
	env["REQUEST_METHOD"] = to!string(method);
	env["CONTENT_LENGTH"] = to!string(data.length);

	auto cgi = new Cgi(
		0,
		env,
		{ return data; },
		outputSink,
		null);

	return cgi;
}


// should this be a separate module? Probably, but that's a hassle.

/// Makes a data:// uri that can be used as links in most newer browsers (IE8+).
string makeDataUrl(string mimeType, in void[] data) {
	auto data64 = Base64.encode(cast(const(ubyte[])) data);
	return "data:" ~ mimeType ~ ";base64," ~ assumeUnique(data64);
}

// FIXME: I don't think this class correctly decodes/encodes the individual parts
/// Represents a url that can be broken down or built up through properties
struct Uri {
	alias toString this; // blargh idk a url really is a string, but should it be implicit?

	// scheme//userinfo@host:port/path?query#fragment

	string scheme; /// e.g. "http" in "http://example.com/"
	string userinfo; /// the username (and possibly a password) in the uri
	string host; /// the domain name
	int port; /// port number, if given. Will be zero if a port was not explicitly given
	string path; /// e.g. "/folder/file.html" in "http://example.com/folder/file.html"
	string query; /// the stuff after the ? in a uri
	string fragment; /// the stuff after the # in a uri.

	// idk if i want to keep these, since the functions they wrap are used many, many, many times in existing code, so this is either an unnecessary alias or a gratuitous break of compatibility
	// the decode ones need to keep different names anyway because we can't overload on return values...
	static string encode(string s) { return std.uri.encodeComponent(s); }
	static string encode(string[string] s) { return encodeVariables(s); }
	static string encode(string[][string] s) { return encodeVariables(s); }

	/// Breaks down a uri string to its components
	this(string uri) {
		reparse(uri);
	}

	private void reparse(string uri) {
		// from RFC 3986
		// the ctRegex triples the compile time and makes ugly errors for no real benefit
		// it was a nice experiment but just not worth it.
		// enum ctr = ctRegex!r"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?";
		/*
			Captures:
				0 = whole url
				1 = scheme, with :
				2 = scheme, no :
				3 = authority, with //
				4 = authority, no //
				5 = path
				6 = query string, with ?
				7 = query string, no ?
				8 = anchor, with #
				9 = anchor, no #
		*/
		// Yikes, even regular, non-CT regex is also unacceptably slow to compile. 1.9s on my computer!
		// instead, I will DIY and cut that down to 0.6s on the same computer.
		/*

				Note that authority is
					user:password@domain:port
				where the user:password@ part is optional, and the :port is optional.

				Regex translation:

				Scheme cannot have :, /, ?, or # in it, and must have one or more chars and end in a :. It is optional, but must be first.
				Authority must start with //, but cannot have any other /, ?, or # in it. It is optional.
				Path cannot have any ? or # in it. It is optional.
				Query must start with ? and must not have # in it. It is optional.
				Anchor must start with # and can have anything else in it to end of string. It is optional.
		*/

		this = Uri.init; // reset all state

		// empty uri = nothing special
		if(uri.length == 0) {
			return;
		}

		size_t idx;

		scheme_loop: foreach(char c; uri[idx .. $]) {
			switch(c) {
				case ':':
				case '/':
				case '?':
				case '#':
					break scheme_loop;
				default:
			}
			idx++;
		}

		if(idx == 0 && uri[idx] == ':') {
			// this is actually a path! we skip way ahead
			goto path_loop;
		}

		if(idx == uri.length) {
			// the whole thing is a path, apparently
			path = uri;
			return;
		}

		if(idx > 0 && uri[idx] == ':') {
			scheme = uri[0 .. idx];
			idx++;
		} else {
			// we need to rewind; it found a / but no :, so the whole thing is prolly a path...
			idx = 0;
		}

		if(idx + 2 < uri.length && uri[idx .. idx + 2] == "//") {
			// we have an authority....
			idx += 2;

			auto authority_start = idx;
			authority_loop: foreach(char c; uri[idx .. $]) {
				switch(c) {
					case '/':
					case '?':
					case '#':
						break authority_loop;
					default:
				}
				idx++;
			}

			auto authority = uri[authority_start .. idx];

			auto idx2 = authority.indexOf("@");
			if(idx2 != -1) {
				userinfo = authority[0 .. idx2];
				authority = authority[idx2 + 1 .. $];
			}

			idx2 = authority.indexOf(":");
			if(idx2 == -1) {
				port = 0; // 0 means not specified; we should use the default for the scheme
				host = authority;
			} else {
				host = authority[0 .. idx2];
				port = to!int(authority[idx2 + 1 .. $]);
			}
		}

		path_loop:
		auto path_start = idx;
		
		foreach(char c; uri[idx .. $]) {
			if(c == '?' || c == '#')
				break;
			idx++;
		}

		path = uri[path_start .. idx];

		if(idx == uri.length)
			return; // nothing more to examine...

		if(uri[idx] == '?') {
			idx++;
			auto query_start = idx;
			foreach(char c; uri[idx .. $]) {
				if(c == '#')
					break;
				idx++;
			}
			query = uri[query_start .. idx];
		}

		if(idx < uri.length && uri[idx] == '#') {
			idx++;
			fragment = uri[idx .. $];
		}

		// uriInvalidated = false;
	}

	private string rebuildUri() const {
		string ret;
		if(scheme.length)
			ret ~= scheme ~ ":";
		if(userinfo.length || host.length)
			ret ~= "//";
		if(userinfo.length)
			ret ~= userinfo ~ "@";
		if(host.length)
			ret ~= host;
		if(port)
			ret ~= ":" ~ to!string(port);

		ret ~= path;

		if(query.length)
			ret ~= "?" ~ query;

		if(fragment.length)
			ret ~= "#" ~ fragment;

		// uri = ret;
		// uriInvalidated = false;
		return ret;
	}

	/// Converts the broken down parts back into a complete string
	string toString() const {
		// if(uriInvalidated)
			return rebuildUri();
	}

	/// Returns a new absolute Uri given a base. It treats this one as
	/// relative where possible, but absolute if not. (If protocol, domain, or
	/// other info is not set, the new one inherits it from the base.)
	///
	/// Browsers use a function like this to figure out links in html.
	Uri basedOn(in Uri baseUrl) const {
		Uri n = this; // copies
		// n.uriInvalidated = true; // make sure we regenerate...

		// userinfo is not inherited... is this wrong?

		// if anything is given in the existing url, we don't use the base anymore.
		if(n.scheme.empty) {
			n.scheme = baseUrl.scheme;
			if(n.host.empty) {
				n.host = baseUrl.host;
				if(n.port == 0) {
					n.port = baseUrl.port;
					if(n.path.length > 0 && n.path[0] != '/') {
						auto b = baseUrl.path[0 .. baseUrl.path.lastIndexOf("/") + 1];
						if(b.length == 0)
							b = "/";
						n.path = b ~ n.path;
					} else if(n.path.length == 0) {
						n.path = baseUrl.path;
					}
				}
			}
		}

		return n;
	}

	unittest {
		auto uri = Uri("test.html");
		assert(uri.path == "test.html");
		uri = Uri("path/1/lol");
		assert(uri.path == "path/1/lol");
		uri = Uri("http://me@example.com");
		assert(uri.scheme == "http");
		assert(uri.userinfo == "me");
		assert(uri.host == "example.com");
		uri = Uri("http://example.com/#a");
		assert(uri.scheme == "http");
		assert(uri.host == "example.com");
		assert(uri.fragment == "a");
		uri = Uri("#foo");
		assert(uri.fragment == "foo");
		uri = Uri("?lol");
		assert(uri.query == "lol");
		uri = Uri("#foo?lol");
		assert(uri.fragment == "foo?lol");
		uri = Uri("?lol#foo");
		assert(uri.fragment == "foo");
		assert(uri.query == "lol");
	}

	// This can sometimes be a big pain in the butt for me, so lots of copy/paste here to cover
	// the possibilities.
	unittest {
		auto url = Uri("cool.html"); // checking relative links

		assert(url.basedOn(Uri("http://test.com/what/test.html")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Uri("https://test.com/what/test.html")) == "https://test.com/what/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Uri("http://test.com/")) == "http://test.com/cool.html");
		assert(url.basedOn(Uri("http://test.com")) == "http://test.com/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b&c=d")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b&c=d#what")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Uri("http://test.com")) == "http://test.com/cool.html");

		url = Uri("/something/cool.html"); // same server, different path
		assert(url.basedOn(Uri("http://test.com/what/test.html")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Uri("https://test.com/what/test.html")) == "https://test.com/something/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Uri("http://test.com/")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Uri("http://test.com")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b&c=d")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b&c=d#what")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Uri("http://test.com")) == "http://test.com/something/cool.html");

		url = Uri("?query=answer"); // same path. server, protocol, and port, just different query string and fragment
		assert(url.basedOn(Uri("http://test.com/what/test.html")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Uri("https://test.com/what/test.html")) == "https://test.com/what/test.html?query=answer");
		assert(url.basedOn(Uri("http://test.com/what/")) == "http://test.com/what/?query=answer");
		assert(url.basedOn(Uri("http://test.com/")) == "http://test.com/?query=answer");
		assert(url.basedOn(Uri("http://test.com")) == "http://test.com?query=answer");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b&c=d")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Uri("http://test.com/what/test.html?a=b&c=d#what")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Uri("http://test.com")) == "http://test.com?query=answer");

		//auto uriBefore = url;
		url = Uri("#anchor"); // everything should remain the same except the anchor
		//uriBefore.anchor = "anchor");
		//assert(url == uriBefore);

		url = Uri("//example.com"); // same protocol, but different server. the path here should be blank.

		url = Uri("//example.com/example.html"); // same protocol, but different server and path

		url = Uri("http://example.com/test.html"); // completely absolute link should never be modified

		url = Uri("http://example.com"); // completely absolute link should never be modified, even if it has no path

		// FIXME: add something for port too
	}

	// these are like javascript's location.search and location.hash
	string search() const {
		return query.length ? ("?" ~ query) : "";
	}
	string hash() const {
		return fragment.length ? ("#" ~ fragment) : "";
	}
}


/*
	for session, see web.d
*/

/// breaks down a url encoded string
string[][string] decodeVariables(string data, string separator = "&", string[]* namesInOrder = null, string[]* valuesInOrder = null) {
	auto vars = data.split(separator);
	string[][string] _get;
	foreach(var; vars) {
		auto equal = var.indexOf("=");
		string name;
		string value;
		if(equal == -1) {
			name = decodeComponent(var);
			value = "";
		} else {
			//_get[decodeComponent(var[0..equal])] ~= decodeComponent(var[equal + 1 .. $].replace("+", " "));
			// stupid + -> space conversion.
			name = decodeComponent(var[0..equal].replace("+", " "));
			value = decodeComponent(var[equal + 1 .. $].replace("+", " "));
		}

		_get[name] ~= value;
		if(namesInOrder)
			(*namesInOrder) ~= name;
		if(valuesInOrder)
			(*valuesInOrder) ~= value;
	}
	return _get;
}

/// breaks down a url encoded string, but only returns the last value of any array
string[string] decodeVariablesSingle(string data) {
	string[string] va;
	auto varArray = decodeVariables(data);
	foreach(k, v; varArray)
		va[k] = v[$-1];

	return va;
}

/// url encodes the whole string
string encodeVariables(in string[string] data) {
	string ret;

	bool outputted = false;
	foreach(k, v; data) {
		if(outputted)
			ret ~= "&";
		else
			outputted = true;

		ret ~= std.uri.encodeComponent(k) ~ "=" ~ std.uri.encodeComponent(v);
	}

	return ret;
}

/// url encodes a whole string
string encodeVariables(in string[][string] data) {
	string ret;

	bool outputted = false;
	foreach(k, arr; data) {
		foreach(v; arr) {
			if(outputted)
				ret ~= "&";
			else
				outputted = true;
			ret ~= std.uri.encodeComponent(k) ~ "=" ~ std.uri.encodeComponent(v);
		}
	}

	return ret;
}

/// Encodes all but the explicitly unreserved characters per rfc 3986
/// Alphanumeric and -_.~ are the only ones left unencoded
/// name is borrowed from php
string rawurlencode(in char[] data) {
	string ret;
	ret.reserve(data.length * 2);
	foreach(char c; data) {
		if(
			(c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') ||
			c == '-' || c == '_' || c == '.' || c == '~')
		{
			ret ~= c;
		} else {
			ret ~= '%';
			// since we iterate on char, this should give us the octets of the full utf8 string
			ret ~= toHexUpper(c);
		}
	}

	return ret;
}


// http helper functions

// for chunked responses (which embedded http does whenever possible)
version(none) // this is moved up above to avoid making a copy of the data
const(ubyte)[] makeChunk(const(ubyte)[] data) {
	const(ubyte)[] ret;

	ret = cast(const(ubyte)[]) toHex(data.length);
	ret ~= cast(const(ubyte)[]) "\r\n";
	ret ~= data;
	ret ~= cast(const(ubyte)[]) "\r\n";

	return ret;
}

string toHex(long num) {
	string ret;
	while(num) {
		int v = num % 16;
		num /= 16;
		char d = cast(char) ((v < 10) ? v + '0' : (v-10) + 'a');
		ret ~= d;
	}

	return to!string(array(ret.retro));
}

string toHexUpper(long num) {
	string ret;
	while(num) {
		int v = num % 16;
		num /= 16;
		char d = cast(char) ((v < 10) ? v + '0' : (v-10) + 'A');
		ret ~= d;
	}

	if(ret.length == 1)
		ret ~= "0"; // url encoding requires two digits and that's what this function is used for...

	return to!string(array(ret.retro));
}


// the generic mixins

/// Use this instead of writing your own main
mixin template GenericMain(alias fun, long maxContentLength = defaultMaxContentLength) {
	mixin CustomCgiMain!(Cgi, fun, maxContentLength);
}

private string simpleHtmlEncode(string s) {
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\n", "<br />\n");
}

string messageFromException(Throwable t) {
	string message;
	if(t !is null) {
		debug message = t.toString();
		else  message = "An unexpected error has occurred.";
	} else {
		message = "Unknown error";
	}
	return message;
}

string plainHttpError(bool isCgi, string type, Throwable t) {
	auto message = messageFromException(t);
	message = simpleHtmlEncode(message);

	return format("%s %s\r\nContent-Length: %s\r\n\r\n%s",
		isCgi ? "Status:" : "HTTP/1.0",
		type, message.length, message);
}

// returns true if we were able to recover reasonably
bool handleException(Cgi cgi, Throwable t) {
	if(cgi.isClosed) {
		// if the channel has been explicitly closed, we can't handle it here
		return true;
	}

	if(cgi.outputtedResponseData) {
		// the headers are sent, but the channel is open... since it closes if all was sent, we can append an error message here.
		return false; // but I don't want to, since I don't know what condition the output is in; I don't want to inject something (nor check the content-type for that matter. So we say it was not a clean handling.
	} else {
		// no headers are sent, we can send a full blown error and recover
		cgi.setCache(false);
		cgi.setResponseContentType("text/html");
		cgi.setResponseLocation(null); // cancel the redirect
		cgi.setResponseStatus("500 Internal Server Error");
		cgi.write(simpleHtmlEncode(messageFromException(t)));
		cgi.close();
		return true;
	}
}

bool isCgiRequestMethod(string s) {
	s = s.toUpper();
	if(s == "COMMANDLINE")
		return true;
	foreach(member; __traits(allMembers, Cgi.RequestMethod))
		if(s == member)
			return true;
	return false;
}

/// If you want to use a subclass of Cgi with generic main, use this mixin.
mixin template CustomCgiMain(CustomCgi, alias fun, long maxContentLength = defaultMaxContentLength) if(is(CustomCgi : Cgi)) {
	// kinda hacky - the T... is passed to Cgi's constructor in standard cgi mode, and ignored elsewhere
	void main(string[] args) {
		cgiMainImpl!(fun, CustomCgi, maxContentLength)(args);
	}
}

version(embedded_httpd_processes)
	int processPoolSize = 8;

void cgiMainImpl(alias fun, CustomCgi = Cgi, long maxContentLength = defaultMaxContentLength)(string[] args) if(is(CustomCgi : Cgi)) {
	if(args.length > 1) {
		// run the special separate processes if needed
		switch(args[1]) {
			case "--websocket-server":
				runWebsocketServer();
				return;
			case "--session-server":
				runSessionServer();
				return;
			case "--event-server":
				runEventServer();
				return;
			default:
				// intentionally blank - do nothing and carry on to run normally
		}
	}

	// we support command line thing for easy testing everywhere
	// it needs to be called ./app method uri [other args...]
	if(args.length >= 3 && isCgiRequestMethod(args[1])) {
		Cgi cgi = new CustomCgi(args);
		scope(exit) cgi.dispose();
		fun(cgi);
		cgi.close();
		return;
	}


	ushort listeningPort(ushort def) {
		bool found = false;
		foreach(arg; args) {
			if(found)
				return to!ushort(arg);
			if(arg == "--port" || arg == "-p" || arg == "/port" || arg == "--listening-port")
				found = true;
		}
		return def;
	}

	string listeningHost() {
		bool found = false;
		foreach(arg; args) {
			if(found)
				return arg;
			if(arg == "--listening-host" || arg == "-h" || arg == "/listening-host")
				found = true;
		}
		return "";
	}
	version(netman_httpd) {
		import arsd.httpd;
		// what about forwarding the other constructor args?
		// this probably needs a whole redoing...
		serveHttp!CustomCgi(&fun, listeningPort(8080));//5005);
		return;
	} else
	version(embedded_httpd_processes) {
		import core.sys.posix.unistd;
		import core.sys.posix.sys.socket;
		import core.sys.posix.netinet.in_;
		//import std.c.linux.socket;

		int sock = socket(AF_INET, SOCK_STREAM, 0);
		if(sock == -1)
			throw new Exception("socket");

		{
			sockaddr_in addr;
			addr.sin_family = AF_INET;
			addr.sin_port = htons(listeningPort(8085));
			auto lh = listeningHost();
			if(lh.length) {
				if(inet_pton(AF_INET, lh.toStringz(), &addr.sin_addr.s_addr) != 1)
					throw new Exception("bad listening host given, please use an IP address.\nExample: --listening-host 127.0.0.1 means listen only on Localhost.\nExample: --listening-host 0.0.0.0 means listen on all interfaces.\nOr you can pass any other single numeric IPv4 address.");
			} else
				addr.sin_addr.s_addr = INADDR_ANY;

			// HACKISH
			int on = 1;
			setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &on, on.sizeof);
			// end hack

			
			if(bind(sock, cast(sockaddr*) &addr, addr.sizeof) == -1) {
				close(sock);
				throw new Exception("bind");
			}

			// FIXME: if this queue is full, it will just ignore it
			// and wait for the client to retransmit it. This is an
			// obnoxious timeout condition there.
			if(sock.listen(128) == -1) {
				close(sock);
				throw new Exception("listen");
			}
		}

		version(embedded_httpd_processes_accept_after_fork) {} else {
			int pipeReadFd;
			int pipeWriteFd;

			{
				int[2] pipeFd;
				if(socketpair(AF_UNIX, SOCK_DGRAM, 0, pipeFd)) {
					import core.stdc.errno;
					throw new Exception("pipe failed " ~ to!string(errno));
				}

				pipeReadFd = pipeFd[0];
				pipeWriteFd = pipeFd[1];
			}
		}


		int processCount;
		pid_t newPid;
		reopen:
		while(processCount < processPoolSize) {
			newPid = fork();
			if(newPid == 0) {
				// start serving on the socket
				//ubyte[4096] backingBuffer;
				for(;;) {
					bool closeConnection;
					uint i;
					sockaddr addr;
					i = addr.sizeof;
					version(embedded_httpd_processes_accept_after_fork) {
						int s = accept(sock, &addr, &i);
						int opt = 1;
						import core.sys.posix.netinet.tcp;
						// the Cgi class does internal buffering, so disabling this
						// helps with latency in many cases...
						setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
					} else {
						int s;
						auto readret = read_fd(pipeReadFd, &s, s.sizeof, &s);
						if(readret != s.sizeof) {
							import core.stdc.errno;
							throw new Exception("pipe read failed " ~ to!string(errno));
						}

						//writeln("process ", getpid(), " got socket ", s);
					}

					try {

						if(s == -1)
							throw new Exception("accept");

						scope(failure) close(s);
						//ubyte[__traits(classInstanceSize, BufferedInputRange)] bufferedRangeContainer;
						auto ir = new BufferedInputRange(s);
						//auto ir = emplace!BufferedInputRange(bufferedRangeContainer, s, backingBuffer);

						while(!ir.empty) {
							ubyte[__traits(classInstanceSize, CustomCgi)] cgiContainer;

							Cgi cgi;
							try {
								cgi = new CustomCgi(ir, &closeConnection);
								cgi._outputFileHandle = s;
								// if we have a single process and the browser tries to leave the connection open while concurrently requesting another, it will block everything an deadlock since there's no other server to accept it. By closing after each request in this situation, it tells the browser to serialize for us.
								if(processPoolSize <= 1)
									closeConnection = true;
								//cgi = emplace!CustomCgi(cgiContainer, ir, &closeConnection);
							} catch(Throwable t) {
								// a construction error is either bad code or bad request; bad request is what it should be since this is bug free :P
								// anyway let's kill the connection
								stderr.writeln(t.toString());
								sendAll(ir.source, plainHttpError(false, "400 Bad Request", t));
								closeConnection = true;
								break;
							}
							assert(cgi !is null);
							scope(exit)
								cgi.dispose();

							try {
								fun(cgi);
								cgi.close();
							} catch(ConnectionException ce) {
								closeConnection = true;
							} catch(Throwable t) {
								// a processing error can be recovered from
								stderr.writeln(t.toString);
								if(!handleException(cgi, t))
									closeConnection = true;
							}

							if(closeConnection) {
								ir.source.close();
								break;
							} else {
								if(!ir.empty)
									ir.popFront(); // get the next
								else if(ir.sourceClosed) {
									ir.source.close();
								}
							}
						}

						ir.source.close();
					} catch(Throwable t) {
						debug writeln(t);
						// most likely cause is a timeout
					}
				}
			} else {
				processCount++;
			}
		}

		// the parent should wait for its children...
		if(newPid) {
			import core.sys.posix.sys.wait;

			version(embedded_httpd_processes_accept_after_fork) {} else {
				import core.sys.posix.sys.select;
				int[] fdQueue;
				while(true) {
					// writeln("select call");
					int nfds = pipeWriteFd;
					if(sock > pipeWriteFd)
						nfds = sock;
					nfds += 1;
					fd_set read_fds;
					fd_set write_fds;
					FD_ZERO(&read_fds);
					FD_ZERO(&write_fds);
					FD_SET(sock, &read_fds);
					if(fdQueue.length)
						FD_SET(pipeWriteFd, &write_fds);
					auto ret = select(nfds, &read_fds, &write_fds, null, null);
					if(ret == -1) {
						import core.stdc.errno;
						if(errno == EINTR)
							goto try_wait;
						else
							throw new Exception("wtf select");
					}

					int s = -1;
					if(FD_ISSET(sock, &read_fds)) {
						uint i;
						sockaddr addr;
						i = addr.sizeof;
						s = accept(sock, &addr, &i);
						import core.sys.posix.netinet.tcp;
						int opt = 1;
						setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
					}

					if(FD_ISSET(pipeWriteFd, &write_fds)) {
						if(s == -1 && fdQueue.length) {
							s = fdQueue[0];
							fdQueue = fdQueue[1 .. $]; // FIXME reuse buffer
						}
						write_fd(pipeWriteFd, &s, s.sizeof, s);
						close(s); // we are done with it, let the other process take ownership
					} else
						fdQueue ~= s;
				}
			}

			try_wait:

			int status;
			while(-1 != wait(&status)) {
				import std.stdio; writeln("Process died ", status);
				processCount--;
				goto reopen;
			}
			close(sock);
		}
	} else
	version(embedded_httpd_threads) {
		auto manager = new ListeningConnectionManager(listeningHost(), listeningPort(8085), &doThreadHttpConnection!(CustomCgi, fun));
		manager.listen();
	} else
	version(scgi) {
		import std.exception;
		import al = std.algorithm;
		auto manager = new ListeningConnectionManager(listeningHost(), listeningPort(4000), &doThreadScgiConnection!(CustomCgi, fun, maxContentLength));
		manager.listen();
	} else
	version(fastcgi) {
		//         SetHandler fcgid-script
		FCGX_Stream* input, output, error;
		FCGX_ParamArray env;



		const(ubyte)[] getFcgiChunk() {
			const(ubyte)[] ret;
			while(FCGX_HasSeenEOF(input) != -1)
				ret ~= cast(ubyte) FCGX_GetChar(input);
			return ret;
		}

		void writeFcgi(const(ubyte)[] data) {
			FCGX_PutStr(data.ptr, data.length, output);
		}

		void doARequest() {
			string[string] fcgienv;

			for(auto e = env; e !is null && *e !is null; e++) {
				string cur = to!string(*e);
				auto idx = cur.indexOf("=");
				string name, value;
				if(idx == -1)
					name = cur;
				else {
					name = cur[0 .. idx];
					value = cur[idx + 1 .. $];
				}

				fcgienv[name] = value;
			}

			void flushFcgi() {
				FCGX_FFlush(output);
			}

			Cgi cgi;
			try {
				cgi = new CustomCgi(maxContentLength, fcgienv, &getFcgiChunk, &writeFcgi, &flushFcgi);
			} catch(Throwable t) {
				FCGX_PutStr(cast(ubyte*) t.msg.ptr, t.msg.length, error);
				writeFcgi(cast(const(ubyte)[]) plainHttpError(true, "400 Bad Request", t));
				return; //continue;
			}
			assert(cgi !is null);
			scope(exit) cgi.dispose();
			try {
				fun(cgi);
				cgi.close();
			} catch(Throwable t) {
				// log it to the error stream
				FCGX_PutStr(cast(ubyte*) t.msg.ptr, t.msg.length, error);
				// handle it for the user, if we can
				if(!handleException(cgi, t))
					return; // continue;
			}
		}

		auto lp = listeningPort(0);
		FCGX_Request request;
		if(lp) {
			// if a listening port was specified on the command line, we want to spawn ourself
			// (needed for nginx without spawn-fcgi, e.g. on Windows)
			FCGX_Init();
			auto sock = FCGX_OpenSocket(toStringz(listeningHost() ~ ":" ~ to!string(lp)), 12);
			if(sock < 0)
				throw new Exception("Couldn't listen on the port");
			FCGX_InitRequest(&request, sock, 0);
			while(FCGX_Accept_r(&request) >= 0) {
				input = request.inStream;
				output = request.outStream;
				error = request.errStream;
				env = request.envp;
				doARequest();
			}
		} else {
			// otherwise, assume the httpd is doing it (the case for Apache, IIS, and Lighttpd)
			// using the version with a global variable since we are separate processes anyway
			while(FCGX_Accept(&input, &output, &error, &env) >= 0) {
				doARequest();
			}
		}
	} else {
		// standard CGI is the default version
		Cgi cgi;
		try {
			cgi = new CustomCgi(maxContentLength);
			version(Posix)
				cgi._outputFileHandle = 1; // stdout
			else version(Windows)
				cgi._outputFileHandle = GetStdHandle(STD_OUTPUT_HANDLE);
			else static assert(0);
		} catch(Throwable t) {
			stderr.writeln(t.msg);
			// the real http server will probably handle this;
			// most likely, this is a bug in Cgi. But, oh well.
			stdout.write(plainHttpError(true, "400 Bad Request", t));
			return;
		}
		assert(cgi !is null);
		scope(exit) cgi.dispose();

		try {
			fun(cgi);
			cgi.close();
		} catch (Throwable t) {
			stderr.writeln(t.msg);
			if(!handleException(cgi, t))
				return;
		}
	}
}

version(embedded_httpd_threads)
void doThreadHttpConnection(CustomCgi, alias fun)(Socket connection) {
	scope(failure) {
		// catch all for other errors
		sendAll(connection, plainHttpError(false, "500 Internal Server Error", null));
		connection.close();
	}

	connection.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(10));

	bool closeConnection;
	auto ir = new BufferedInputRange(connection);

	while(!ir.empty) {
		Cgi cgi;
		try {
			cgi = new CustomCgi(ir, &closeConnection);
			cgi._outputFileHandle = connection.handle;
		} catch(ConnectionException ce) {
			// broken pipe or something, just abort the connection
			closeConnection = true;
			break;
		} catch(Throwable t) {
			// a construction error is either bad code or bad request; bad request is what it should be since this is bug free :P
			// anyway let's kill the connection
			stderr.writeln(t.toString());
			sendAll(connection, plainHttpError(false, "400 Bad Request", t));
			closeConnection = true;
			break;
		}
		assert(cgi !is null);
		scope(exit)
			cgi.dispose();

		try {
			fun(cgi);
			cgi.close();
		} catch(ConnectionException ce) {
			// broken pipe or something, just abort the connection
			closeConnection = true;
		} catch(Throwable t) {
			// a processing error can be recovered from
			stderr.writeln(t.toString);
			if(!handleException(cgi, t))
				closeConnection = true;
		}

		if(closeConnection) {
			connection.close();
			break;
		} else {
			if(!ir.empty)
				ir.popFront(); // get the next
			else if(ir.sourceClosed)
				ir.source.close();
		}
	}

	ir.source.close();
}

version(scgi)
void doThreadScgiConnection(CustomCgi, alias fun, long maxContentLength)(Socket connection) {
	// and now we can buffer
	scope(failure)
		connection.close();

	import al = std.algorithm;

	size_t size;

	string[string] headers;

	auto range = new BufferedInputRange(connection);
	more_data:
	auto chunk = range.front();
	// waiting for colon for header length
	auto idx = indexOf(cast(string) chunk, ':');
	if(idx == -1) {
		range.popFront();
		goto more_data;
	}

	size = to!size_t(cast(string) chunk[0 .. idx]);
	chunk = range.consume(idx + 1);
	// reading headers
	if(chunk.length < size)
		range.popFront(0, size + 1);
	// we are now guaranteed to have enough
	chunk = range.front();
	assert(chunk.length > size);

	idx = 0;
	string key;
	string value;
	foreach(part; al.splitter(chunk, '\0')) {
		if(idx & 1) { // odd is value
			value = cast(string)(part.idup);
			headers[key] = value; // commit
		} else
			key = cast(string)(part.idup);
		idx++;
	}

	enforce(chunk[size] == ','); // the terminator

	range.consume(size + 1);
	// reading data
	// this will be done by Cgi

	const(ubyte)[] getScgiChunk() {
		// we are already primed
		auto data = range.front();
		if(data.length == 0 && !range.sourceClosed) {
			range.popFront(0);
			data = range.front();
		} else if (range.sourceClosed)
			range.source.close();

		return data;
	}

	void writeScgi(const(ubyte)[] data) {
		sendAll(connection, data);
	}

	void flushScgi() {
		// I don't *think* I have to do anything....
	}

	Cgi cgi;
	try {
		cgi = new CustomCgi(maxContentLength, headers, &getScgiChunk, &writeScgi, &flushScgi);
		cgi._outputFileHandle = connection.handle;
	} catch(Throwable t) {
		sendAll(connection, plainHttpError(true, "400 Bad Request", t));
		connection.close();
		return; // this connection is dead
	}
	assert(cgi !is null);
	scope(exit) cgi.dispose();
	try {
		fun(cgi);
		cgi.close();
		connection.close();
	} catch(Throwable t) {
		// no std err
		if(!handleException(cgi, t)) {
			connection.close();
			return;
		}
	}
}

string printDate(DateTime date) {
	return format(
		"%.3s, %02d %.3s %d %02d:%02d:%02d GMT", // could be UTC too
		to!string(date.dayOfWeek).capitalize,
		date.day,
		to!string(date.month).capitalize,
		date.year,
		date.hour,
		date.minute,
		date.second);
}


// Referencing this gigantic typeid seems to remind the compiler
// to actually put the symbol in the object file. I guess the immutable
// assoc array array isn't actually included in druntime
void hackAroundLinkerError() {
      writeln(typeid(const(immutable(char)[][])[immutable(char)[]]));
      writeln(typeid(immutable(char)[][][immutable(char)[]]));
      writeln(typeid(Cgi.UploadedFile[immutable(char)[]]));
      writeln(typeid(Cgi.UploadedFile[][immutable(char)[]]));
      writeln(typeid(immutable(Cgi.UploadedFile)[immutable(char)[]]));
      writeln(typeid(immutable(Cgi.UploadedFile[])[immutable(char)[]]));
      writeln(typeid(immutable(char[])[immutable(char)[]]));
      // this is getting kinda ridiculous btw. Moving assoc arrays
      // to the library is the pain that keeps on coming.

      // eh this broke the build on the work server
      // writeln(typeid(immutable(char)[][immutable(string[])]));
      writeln(typeid(immutable(string[])[immutable(char)[]]));
}





version(fastcgi) {
	pragma(lib, "fcgi");

	static if(size_t.sizeof == 8) // 64 bit
		alias long c_int;
	else
		alias int c_int;

	extern(C) {
		struct FCGX_Stream {
			ubyte* rdNext;
			ubyte* wrNext;
			ubyte* stop;
			ubyte* stopUnget;
			c_int isReader;
			c_int isClosed;
			c_int wasFCloseCalled;
			c_int FCGI_errno;
			void* function(FCGX_Stream* stream) fillBuffProc;
			void* function(FCGX_Stream* stream, c_int doClose) emptyBuffProc;
			void* data;
		}

		// note: this is meant to be opaque, so don't access it directly
		struct FCGX_Request {
			int requestId;
			int role;
			FCGX_Stream* inStream;
			FCGX_Stream* outStream;
			FCGX_Stream* errStream;
			char** envp;
			void* paramsPtr;
			int ipcFd;
			int isBeginProcessed;
			int keepConnection;
			int appStatus;
			int nWriters;
			int flags;
			int listen_sock;
		}

		int FCGX_InitRequest(FCGX_Request *request, int sock, int flags);
		void FCGX_Init();

		int FCGX_Accept_r(FCGX_Request *request);


		alias char** FCGX_ParamArray;

		c_int FCGX_Accept(FCGX_Stream** stdin, FCGX_Stream** stdout, FCGX_Stream** stderr, FCGX_ParamArray* envp);
		c_int FCGX_GetChar(FCGX_Stream* stream);
		c_int FCGX_PutStr(const ubyte* str, c_int n, FCGX_Stream* stream);
		int FCGX_HasSeenEOF(FCGX_Stream* stream);
		c_int FCGX_FFlush(FCGX_Stream *stream);

		int FCGX_OpenSocket(in char*, int);
	}
}


/* This might go int a separate module eventually. It is a network input helper class. */

import std.socket;

// it is a class primarily for reference semantics
// I might change this interface
/// This is NOT ACTUALLY an input range! It is too different. Historical mistake kinda.
class BufferedInputRange {
	version(Posix)
	this(int source, ubyte[] buffer = null) {
		this(new Socket(cast(socket_t) source, AddressFamily.INET), buffer);
	}

	this(Socket source, ubyte[] buffer = null) {
		// if they connect but never send stuff to us, we don't want it wasting the process
		// so setting a time out
		source.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(3));
		this.source = source;
		if(buffer is null) {
			underlyingBuffer = new ubyte[4096];
			allowGrowth = true;
		} else {
			underlyingBuffer = buffer;
		}

		assert(underlyingBuffer.length);

		// we assume view.ptr is always inside underlyingBuffer
		view = underlyingBuffer[0 .. 0];

		popFront(); // prime
	}

	/**
		A slight difference from regular ranges is you can give it the maximum
		number of bytes to consume.

		IMPORTANT NOTE: the default is to consume nothing, so if you don't call
		consume() yourself and use a regular foreach, it will infinitely loop!

		The default is to do what a normal range does, and consume the whole buffer
		and wait for additional input.

		You can also specify 0, to append to the buffer, or any other number
		to remove the front n bytes and wait for more.
	*/
	void popFront(size_t maxBytesToConsume = 0 /*size_t.max*/, size_t minBytesToSettleFor = 0, bool skipConsume = false) {
		if(sourceClosed)
			throw new Exception("can't get any more data from a closed source");
		if(!skipConsume)
			consume(maxBytesToConsume);

		// we might have to grow the buffer
		if(minBytesToSettleFor > underlyingBuffer.length || view.length == underlyingBuffer.length) {
			if(allowGrowth) {
				auto viewStart = view.ptr - underlyingBuffer.ptr;
				size_t growth = 4096;
				// make sure we have enough for what we're being asked for
				if(minBytesToSettleFor - underlyingBuffer.length > growth)
					growth = minBytesToSettleFor - underlyingBuffer.length;
				underlyingBuffer.length += growth;
				view = underlyingBuffer[viewStart .. view.length];
			} else
				throw new Exception("No room left in the buffer");
		}

		do {
			auto freeSpace = underlyingBuffer[underlyingBuffer.ptr - view.ptr + view.length .. $];
			try_again:
			auto ret = source.receive(freeSpace);
			if(ret == Socket.ERROR) {
				if(wouldHaveBlocked()) {
					// gonna treat a timeout here as a close
					sourceClosed = true;
					return;
				}
				version(Posix) {
					import core.stdc.errno;
					if(errno == EINTR || errno == EAGAIN) {
						goto try_again;
					}
				}
				throw new Exception(lastSocketError); // FIXME
			}
			if(ret == 0) {
				sourceClosed = true;
				return;
			}

			view = underlyingBuffer[view.ptr - underlyingBuffer.ptr .. view.length + ret];
		} while(view.length < minBytesToSettleFor);
	}

	/// Removes n bytes from the front of the buffer, and returns the new buffer slice.
	/// You might want to idup the data you are consuming if you store it, since it may
	/// be overwritten on the new popFront.
	///
	/// You do not need to call this if you always want to wait for more data when you
	/// consume some.
	ubyte[] consume(size_t bytes) {
		view = view[bytes > $ ? $ : bytes .. $];
		if(view.length == 0) {
			view = underlyingBuffer[0 .. 0]; // go ahead and reuse the beginning
			/*
			writeln("HERE");
			popFront(0, 0, true); // try to load more if we can, checks if the source is closed
			writeln(cast(string)front);
			writeln("DONE");
			*/
		}
		return front;
	}

	bool empty() {
		return sourceClosed && view.length == 0;
	}

	ubyte[] front() {
		return view;
	}

	invariant() {
		assert(view.ptr >= underlyingBuffer.ptr);
		// it should never be equal, since if that happens view ought to be empty, and thus reusing the buffer
		assert(view.ptr < underlyingBuffer.ptr + underlyingBuffer.length);
	}

	ubyte[] underlyingBuffer;
	bool allowGrowth;
	ubyte[] view;
	Socket source;
	bool sourceClosed;
}

import core.sync.semaphore;
import core.atomic;

/**
	To use this thing:

	void handler(Socket s) { do something... }
	auto manager = new ListeningConnectionManager("127.0.0.1", 80, &handler);
	manager.listen();

	I suggest you use BufferedInputRange(connection) to handle the input. As a packet
	comes in, you will get control. You can just continue; though to fetch more.


	FIXME: should I offer an event based async thing like netman did too? Yeah, probably.
*/
class ListeningConnectionManager {
	Semaphore semaphore;
	Socket[256] queue;
	shared(ubyte) nextIndexFront;
	ubyte nextIndexBack;
	shared(int) queueLength;

	void listen() {
		running = true;
		shared(int) loopBroken;

		version(cgi_no_threads) {
			// NEVER USE THIS
			// it exists only for debugging and other special occasions

			// the thread mode is faster and less likely to stall the whole
			// thing when a request is slow
			while(!loopBroken && running) {
				auto sn = listener.accept();
				try {
					handler(sn);
				} catch(Exception e) {
					// if a connection goes wrong, we want to just say no, but try to carry on unless it is an Error of some sort (in which case, we'll die. You might want an external helper program to revive the server when it dies)
					sn.close();
				}
			}
		} else {
			semaphore = new Semaphore();

			ConnectionThread[16] threads;
			foreach(ref thread; threads) {
				thread = new ConnectionThread(this, handler);
				thread.start();
			}

			while(!loopBroken && running) {
				auto sn = listener.accept();
				// disable Nagle's algorithm to avoid a 40ms delay when we send/recv
				// on the socket because we do some buffering internally. I think this helps,
				// certainly does for small requests, and I think it does for larger ones too
				sn.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
				while(queueLength >= queue.length)
					Thread.sleep(1.msecs);
				synchronized(this) {
					queue[nextIndexBack] = sn;
					nextIndexBack++;
					atomicOp!"+="(queueLength, 1);
				}
				semaphore.notify();

				foreach(thread; threads) {
					if(!thread.isRunning) {
						thread.join();
					}
				}
			}
		}
	}

	this(string host, ushort port, void function(Socket) handler) {
		this.handler = handler;
		listener = new TcpSocket();
		listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		listener.bind(host.length ? parseAddress(host, port) : new InternetAddress(port));
		listener.listen(128);
	}

	Socket listener;
	void function(Socket) handler;

	bool running;
	void quit() {
		running = false;
	}
}

// helper function to send a lot to a socket. Since this blocks for the buffer (possibly several times), you should probably call it in a separate thread or something.
void sendAll(Socket s, const(void)[] data, string file = __FILE__, size_t line = __LINE__) {
	if(data.length == 0) return;
	ptrdiff_t amount;
	do {
		amount = s.send(data);
		if(amount == Socket.ERROR)
			throw new ConnectionException(s, lastSocketError, file, line);
		assert(amount > 0);
		data = data[amount .. $];
	} while(data.length);
}

class ConnectionException : Exception {
	Socket socket;
	this(Socket s, string msg, string file = __FILE__, size_t line = __LINE__) {
		this.socket = s;
		super(msg, file, line);
	}
}

alias void function(Socket) CMT;

import core.thread;
class ConnectionThread : Thread {
	this(ListeningConnectionManager lcm, CMT dg) {
		this.lcm = lcm;
		this.dg = dg;
		super(&run);
	}

	void run() {
		while(true) {
			lcm.semaphore.wait();
			Socket socket;
			synchronized(lcm) {
				auto idx = lcm.nextIndexFront;
				socket = lcm.queue[idx];
				lcm.queue[idx] = null;
				atomicOp!"+="(lcm.nextIndexFront, 1);
				atomicOp!"-="(lcm.queueLength, 1);
			}
			try
				dg(socket);
			catch(Exception e)
				socket.close();
		}
	}

	ListeningConnectionManager lcm;
	CMT dg;
}

/* Done with network helper */

/* Helpers for doing temporary files. Used both here and in web.d */

version(Windows) {
	import core.sys.windows.windows;
	extern(Windows) DWORD GetTempPathW(DWORD, LPWSTR);
	alias GetTempPathW GetTempPath;
}

version(Posix) {
	static import linux = core.sys.posix.unistd;
}

string getTempDirectory() {
	string path;
	version(Windows) {
		wchar[1024] buffer;
		auto len = GetTempPath(1024, buffer.ptr);
		if(len == 0)
			throw new Exception("couldn't find a temporary path");

		auto b = buffer[0 .. len];

		path = to!string(b);
	} else
		path = "/tmp/";

	return path;
}


// I like std.date. These functions help keep my old code and data working with phobos changing.

long sysTimeToDTime(in SysTime sysTime) {
    return convert!("hnsecs", "msecs")(sysTime.stdTime - 621355968000000000L);
}

long dateTimeToDTime(in DateTime dt) {
	return sysTimeToDTime(cast(SysTime) dt);
}

long getUtcTime() { // renamed primarily to avoid conflict with std.date itself
	return sysTimeToDTime(Clock.currTime(UTC()));
}

// NOTE: new SimpleTimeZone(minutes); can perhaps work with the getTimezoneOffset() JS trick
SysTime dTimeToSysTime(long dTime, immutable TimeZone tz = null) {
	immutable hnsecs = convert!("msecs", "hnsecs")(dTime) + 621355968000000000L;
	return SysTime(hnsecs, tz);
}



// this is a helper to read HTTP transfer-encoding: chunked responses
immutable(ubyte[]) dechunk(BufferedInputRange ir) {
	immutable(ubyte)[] ret;

	another_chunk:
	// If here, we are at the beginning of a chunk.
	auto a = ir.front();
	int chunkSize;
	int loc = locationOf(a, "\r\n");
	while(loc == -1) {
		ir.popFront();
		a = ir.front();
		loc = locationOf(a, "\r\n");
	}

	string hex;
	hex = "";
	for(int i = 0; i < loc; i++) {
		char c = a[i];
		if(c >= 'A' && c <= 'Z')
			c += 0x20;
		if((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z')) {
			hex ~= c;
		} else {
			break;
		}
	}

	assert(hex.length);

	int power = 1;
	int size = 0;
	foreach(cc1; retro(hex)) {
		dchar cc = cc1;
		if(cc >= 'a' && cc <= 'z')
			cc -= 0x20;
		int val = 0;
		if(cc >= '0' && cc <= '9')
			val = cc - '0';
		else
			val = cc - 'A' + 10;

		size += power * val;
		power *= 16;
	}

	chunkSize = size;
	assert(size >= 0);

	if(loc + 2 > a.length) {
		ir.popFront(0, a.length + loc + 2);
		a = ir.front();
	}

	a = ir.consume(loc + 2);

	if(chunkSize == 0) { // we're done with the response
		// if we got here, will change must be true....
		more_footers:
		loc = locationOf(a, "\r\n");
		if(loc == -1) {
			ir.popFront();
			a = ir.front;
			goto more_footers;
		} else {
			assert(loc == 0);
			ir.consume(loc + 2);
			goto finish;
		}
	} else {
		// if we got here, will change must be true....
		if(a.length < chunkSize + 2) {
			ir.popFront(0, chunkSize + 2);
			a = ir.front();
		}

		ret ~= (a[0..chunkSize]);

		if(!(a.length > chunkSize + 2)) {
			ir.popFront(0, chunkSize + 2);
			a = ir.front();
		}
		assert(a[chunkSize] == 13);
		assert(a[chunkSize+1] == 10);
		a = ir.consume(chunkSize + 2);
		chunkSize = 0;
		goto another_chunk;
	}

	finish:
	return ret;
}

// I want to be able to get data from multiple sources the same way...
interface ByChunkRange {
	bool empty();
	void popFront();
	const(ubyte)[] front();
}

ByChunkRange byChunk(const(ubyte)[] data) {
	return new class ByChunkRange {
		override bool empty() {
			return !data.length;
		}

		override void popFront() {
			if(data.length > 4096)
				data = data[4096 .. $];
			else
				data = null;
		}

		override const(ubyte)[] front() {
			return data[0 .. $ > 4096 ? 4096 : $];
		}
	};
}

ByChunkRange byChunk(BufferedInputRange ir, size_t atMost) {
	const(ubyte)[] f;

	f = ir.front;
	if(f.length > atMost)
		f = f[0 .. atMost];

	return new class ByChunkRange {
		override bool empty() {
			return atMost == 0;
		}

		override const(ubyte)[] front() {
			return f;
		}

		override void popFront() {
			ir.consume(f.length);
			atMost -= f.length;
			auto a = ir.front();

			if(a.length <= atMost) {
				f = a;
				atMost -= a.length;
				a = ir.consume(a.length);
				if(atMost != 0)
					ir.popFront();
				if(f.length == 0) {
					f = ir.front();
				}
			} else {
				// we actually have *more* here than we need....
				f = a[0..atMost];
				atMost = 0;
				ir.consume(atMost);
			}
		}
	};
}

version(cgi_with_websocket) {
	// http://tools.ietf.org/html/rfc6455

	/**
		WEBSOCKET SUPPORT:

		Full example:
		---
			import arsd.cgi;

			void websocketEcho(Cgi cgi) {
				if(cgi.websocketRequested()) {
					if(cgi.origin != "http://arsdnet.net")
						throw new Exception("bad origin");
					auto websocket = cgi.acceptWebsocket();

					websocket.send("hello");
					websocket.send(" world!");

					auto msg = websocket.recv();
					while(msg.opcode != WebSocketOpcode.close) {
						if(msg.opcode == WebSocketOpcode.text) {
							websocket.send(msg.textData);
						} else if(msg.opcode == WebSocketOpcode.binary) {
							websocket.send(msg.data);
						}

						msg = websocket.recv();
					}

					websocket.close();
				} else assert(0, "i want a web socket!");
			}

			mixin GenericMain!websocketEcho;
		---
	*/

	class WebSocket {
		Cgi cgi;

		private this(Cgi cgi) {
			this.cgi = cgi;
		}

		// returns true if data available, false if it timed out
		bool recvAvailable(Duration timeout = dur!"msecs"(0)) {
			Socket socket = cgi.idlol.source;

			auto check = new SocketSet();
			check.add(socket);

			auto got = Socket.select(check, null, null, timeout);
			if(got > 0)
				return true;
			return false;
		}

		// note: this blocks
		WebSocketMessage recv() {
			// FIXME: should we automatically handle pings and pongs?
			assert(!cgi.idlol.empty());
			cgi.idlol.popFront(0);

			WebSocketMessage message;

			auto info = cgi.idlol.front();

			// FIXME: read should prolly take the whole range so it can request more if needed
			// read should also go ahead and consume the range
			message = WebSocketMessage.read(info);

			cgi.idlol.consume(info.length);

			return message;
		}

		void send(in char[] text) {
			// I cast away const here because I know this msg is private and it doesn't write
			// to that buffer unless masking is set... which it isn't, so we're ok.
			auto msg = WebSocketMessage.simpleMessage(WebSocketOpcode.text, cast(void[]) text);
			msg.send(cgi);
		}

		void send(in ubyte[] binary) {
			// I cast away const here because I know this msg is private and it doesn't write
			// to that buffer unless masking is set... which it isn't, so we're ok.
			auto msg = WebSocketMessage.simpleMessage(WebSocketOpcode.binary, cast(void[]) binary);
			msg.send(cgi);
		}

		void close() {
			auto msg = WebSocketMessage.simpleMessage(WebSocketOpcode.close, null);
			msg.send(cgi);
		}

		void ping() {
			auto msg = WebSocketMessage.simpleMessage(WebSocketOpcode.ping, null);
			msg.send(cgi);
		}

		void pong() {
			auto msg = WebSocketMessage.simpleMessage(WebSocketOpcode.pong, null);
			msg.send(cgi);
		}
	}

	bool websocketRequested(Cgi cgi) {
		return
			"sec-websocket-key" in cgi.requestHeaders
			&&
			"connection" in cgi.requestHeaders &&
				cgi.requestHeaders["connection"].asLowerCase().canFind("upgrade")
			&&
			"upgrade" in cgi.requestHeaders &&
				cgi.requestHeaders["upgrade"].asLowerCase().equal("websocket")
			;
	}

	WebSocket acceptWebsocket(Cgi cgi) {
		assert(!cgi.closed);
		assert(!cgi.outputtedResponseData);
		cgi.setResponseStatus("101 Web Socket Protocol Handshake");
		cgi.header("Upgrade: WebSocket");
		cgi.header("Connection: upgrade");

		string key = cgi.requestHeaders["sec-websocket-key"];
		key ~= "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"; // the defined guid from the websocket spec

		import std.digest.sha;
		auto hash = sha1Of(key);
		auto accept = Base64.encode(hash);

		cgi.header(("Sec-WebSocket-Accept: " ~ accept).idup);

		cgi.websocketMode = true;
		cgi.write("");

		cgi.flush();

		return new WebSocket(cgi);
	}

	// FIXME: implement websocket extension frames
	// get websocket to work on other modes, not just embedded_httpd

	enum WebSocketOpcode : ubyte {
		text = 1,
		binary = 2,
		// 3, 4, 5, 6, 7 RESERVED
		close = 8,
		ping = 9,
		pong = 10,
		// 11,12,13,14,15 RESERVED
	}

	struct WebSocketMessage {
		bool fin;
		bool rsv1;
		bool rsv2;
		bool rsv3;
		WebSocketOpcode opcode; // 4 bits
		bool masked;
		ubyte lengthIndicator; // don't set this when building one to send
		ulong realLength; // don't use when sending
		ubyte[4] maskingKey; // don't set this when sending
		ubyte[] data;

		static WebSocketMessage simpleMessage(WebSocketOpcode opcode, void[] data) {
			WebSocketMessage msg;
			msg.fin = true;
			msg.opcode = opcode;
			msg.data = cast(ubyte[]) data;

			return msg;
		}

		private void send(Cgi cgi) {
			ubyte[64] headerScratch;
			int headerScratchPos = 0;

			realLength = data.length;

			{
				ubyte b1;
				b1 |= cast(ubyte) opcode;
				b1 |= rsv3 ? (1 << 4) : 0;
				b1 |= rsv2 ? (1 << 5) : 0;
				b1 |= rsv1 ? (1 << 6) : 0;
				b1 |= fin  ? (1 << 7) : 0;

				headerScratch[0] = b1;
				headerScratchPos++;
			}

			{
				headerScratchPos++; // we'll set header[1] at the end of this
				auto rlc = realLength;
				ubyte b2;
				b2 |= masked ? (1 << 7) : 0;

				assert(headerScratchPos == 2);

				if(realLength > 65535) {
					// use 64 bit length
					b2 |= 0x7f;

					// FIXME: double check endinaness
					foreach(i; 0 .. 8) {
						headerScratch[2 + 7 - i] = rlc & 0x0ff;
						rlc >>>= 8;
					}

					headerScratchPos += 8;
				} else if(realLength > 127) {
					// use 16 bit length
					b2 |= 0x7e;

					// FIXME: double check endinaness
					foreach(i; 0 .. 2) {
						headerScratch[2 + 1 - i] = rlc & 0x0ff;
						rlc >>>= 8;
					}

					headerScratchPos += 2;
				} else {
					// use 7 bit length
					b2 |= realLength & 0b_0111_1111;
				}

				headerScratch[1] = b2;
			}

			assert(!masked, "masking key not properly implemented");
			if(masked) {
				// FIXME: randomize this
				headerScratch[headerScratchPos .. headerScratchPos + 4] = maskingKey[];
				headerScratchPos += 4;

				// we'll just mask it in place...
				int keyIdx = 0;
				foreach(i; 0 .. data.length) {
					data[i] = data[i] ^ maskingKey[keyIdx];
					if(keyIdx == 3)
						keyIdx = 0;
					else
						keyIdx++;
				}
			}

			//writeln("SENDING ", headerScratch[0 .. headerScratchPos], data);
			cgi.write(headerScratch[0 .. headerScratchPos]);
			cgi.write(data);
			cgi.flush();
		}

		static WebSocketMessage read(ubyte[] d) {
			WebSocketMessage msg;
			assert(d.length >= 2);

			ubyte b = d[0];

			msg.opcode = cast(WebSocketOpcode) (b & 0x0f);
			b >>= 4;
			msg.rsv3 = b & 0x01;
			b >>= 1;
			msg.rsv2 = b & 0x01;
			b >>= 1;
			msg.rsv1 = b & 0x01;
			b >>= 1;
			msg.fin = b & 0x01;

			b = d[1];
			msg.masked = (b & 0b1000_0000) ? true : false;
			msg.lengthIndicator = b & 0b0111_1111;

			d = d[2 .. $];

			if(msg.lengthIndicator == 0x7e) {
				// 16 bit length
				msg.realLength = 0;

				foreach(i; 0 .. 2) {
					msg.realLength |= d[0] << ((1-i) * 8);
					d = d[1 .. $];
				}
			} else if(msg.lengthIndicator == 0x7f) {
				// 64 bit length
				msg.realLength = 0;

				foreach(i; 0 .. 8) {
					msg.realLength |= d[0] << ((7-i) * 8);
					d = d[1 .. $];
				}
			} else {
				// 7 bit length
				msg.realLength = msg.lengthIndicator;
			}

			if(msg.masked) {
				msg.maskingKey = d[0 .. 4];
				d = d[4 .. $];
			}

			msg.data = d[0 .. $];

			if(msg.masked) {
				// let's just unmask it now
				int keyIdx = 0;
				foreach(i; 0 .. msg.data.length) {
					msg.data[i] = msg.data[i] ^ msg.maskingKey[keyIdx];
					if(keyIdx == 3)
						keyIdx = 0;
					else
						keyIdx++;
				}
			}

			return msg;
		}

		char[] textData() {
			return cast(char[]) data;
		}
	}

}


version(Windows)
{
    version(CRuntime_DigitalMars)
    {
        extern(C) int setmode(int, int) nothrow @nogc;
    }
    else version(CRuntime_Microsoft)
    {
        extern(C) int _setmode(int, int) nothrow @nogc;
        alias setmode = _setmode;
    }
    else static assert(0);
}

version(Posix)
private extern(C) int posix_spawn(pid_t*, const char*, void*, void*, const char**, const char**);


// FIXME: these aren't quite public yet.
//private:

// template for laziness
void startWebsocketServer()() {
	version(linux) {
		import core.sys.posix.unistd;
		pid_t pid;
		const(char)*[16] args;
		args[0] = "ARSD_CGI_WEBSOCKET_SERVER";
		args[1] = "--websocket-server";
		posix_spawn(&pid, "/proc/self/exe",
			null,
			null,
			args.ptr,
			null // env
		);
	} else version(Windows) {
		wchar[2048] filename;
		auto len = GetModuleFileNameW(null, filename.ptr, cast(DWORD) filename.length);
		if(len == 0 || len == filename.length)
			throw new Exception("could not get process name to start helper server");

		STARTUPINFOW startupInfo;
		startupInfo.cb = cast(DWORD) startupInfo.sizeof;
		PROCESS_INFORMATION processInfo;

		// I *MIGHT* need to run it as a new job or a service...
		auto ret = CreateProcessW(
			filename.ptr,
			"--websocket-server"w,
			null, // process attributes
			null, // thread attributes
			false, // inherit handles
			0, // creation flags
			null, // environment
			null, // working directory
			&startupInfo,
			&processInfo
		);

		if(!ret)
			throw new Exception("create process failed");

		// when done with those, if we set them
		/*
		CloseHandle(hStdInput);
		CloseHandle(hStdOutput);
		CloseHandle(hStdError);
		*/

	} else static assert(0, "Websocket server not implemented on this system yet (email me, i can prolly do it if you need it)");
}

// template for laziness
/*
	The websocket server is a single-process, single-thread, event
	I/O thing. It is passed websockets from other CGI processes
	and is then responsible for handling their messages and responses.
	Note that the CGI process is responsible for websocket setup,
	including authentication, etc.

	It also gets data sent to it by other processes and is responsible
	for distributing that, as necessary.
*/
void runWebsocketServer()() {
	assert(0, "not implemented");
}

void sendToWebsocketServer(WebSocket ws, string group) {
	assert(0, "not implemented");
}

void sendToWebsocketServer(string content, string group) {
	assert(0, "not implemented");
}


void runEventServer()() {
	runAddonServer("/tmp/arsd_cgi_event_server", new EventSourceServerImplementation());
}

version(Posix) {
	alias LocalServerConnectionHandle = int;
	alias CgiConnectionHandle = int;
	alias SocketConnectionHandle = int;

	enum INVALID_CGI_CONNECTION_HANDLE = -1;
} else version(Windows) {
	alias LocalServerConnectionHandle = HANDLE;
	version(embedded_httpd) {
		alias CgiConnectionHandle = SOCKET;
		enum INVALID_CGI_CONNECTION_HANDLE = INVALID_SOCKET;
	} else version(fastcgi) {
		alias CgiConnectionHandle = void*; // Doesn't actually work! But I don't want compile to fail pointlessly at this point.
		enum INVALID_CGI_CONNECTION_HANDLE = null;
	} else version(scgi) {
		alias CgiConnectionHandle = HANDLE;
		enum INVALID_CGI_CONNECTION_HANDLE = null;
	} else { /* version(plain_cgi) */
		alias CgiConnectionHandle = HANDLE;
		enum INVALID_CGI_CONNECTION_HANDLE = null;
	}
	alias SocketConnectionHandle = SOCKET;
}

LocalServerConnectionHandle openLocalServerConnection(string name) {
	version(Posix) {
		import core.sys.posix.unistd;
		import core.sys.posix.sys.un;

		int sock = socket(AF_UNIX, SOCK_STREAM, 0);
		if(sock == -1)
			throw new Exception("socket " ~ to!string(errno));

		scope(failure)
			close(sock);

		// add-on server processes are assumed to be local, and thus will
		// use unix domain sockets. Besides, I want to pass sockets to them,
		// so it basically must be local (except for the session server, but meh).
		sockaddr_un addr;
		addr.sun_family = AF_UNIX;
		version(linux) {
			// on linux, we will use the abstract namespace
			addr.sun_path[0] = 0;
			addr.sun_path[1 .. name.length + 1] = cast(typeof(addr.sun_path[])) name[];
		} else {
			// but otherwise, just use a file cuz we must.
			addr.sun_path[0 .. name.length] = cast(typeof(addr.sun_path[])) name[];
		}

		if(connect(sock, cast(sockaddr*) &addr, addr.sizeof) == -1)
			throw new Exception("connect " ~ to!string(errno));

		return sock;
	} else version(Windows) {
		return null; // FIXME
	}
}

void closeLocalServerConnection(LocalServerConnectionHandle handle) {
	version(Posix) {
		import core.sys.posix.unistd;
		close(handle);
	} else version(Windows)
		CloseHandle(handle);
}

void runSessionServer()() {
	runAddonServer("/tmp/arsd_session_server", new BasicDataServerImplementation());
}

version(Posix)
private void makeNonBlocking(int fd) {
	import core.sys.posix.fcntl;
	auto flags = fcntl(fd, F_GETFL, 0);
	if(flags == -1)
		throw new Exception("fcntl get");
	flags |= O_NONBLOCK;
	auto s = fcntl(fd, F_SETFL, flags);
	if(s == -1)
		throw new Exception("fcntl set");
}

import core.stdc.errno;

struct IoOp {
	@disable this();
	@disable this(this);

	/*
		So we want to be able to eventually handle generic sockets too.
	*/

	enum Read = 1;
	enum Write = 2;
	enum Accept = 3;
	enum ReadSocketHandle = 4;

	// Your handler may be called in a different thread than the one that initiated the IO request!
	// It is also possible to have multiple io requests being called simultaneously. Use proper thread safety caution.
	private void delegate(IoOp*, int) handler;
	private void delegate(IoOp*) closeHandler;
	private void delegate(IoOp*) completeHandler;
	private int internalFd;
	private int operation;
	private int bufferLengthAllocated;
	private int bufferLengthUsed;
	private ubyte[1] internalBuffer; // it can be overallocated!

	ubyte[] allocatedBuffer() {
		return internalBuffer.ptr[0 .. bufferLengthAllocated];
	}

	ubyte[] usedBuffer() {
		return allocatedBuffer[0 .. bufferLengthUsed];
	}

	void reset() {
		bufferLengthUsed = 0;
	}

	int fd() {
		return internalFd;
	}
}

IoOp* allocateIoOp(int fd, int operation, int bufferSize, void delegate(IoOp*, int) handler) {
	import core.stdc.stdlib;

	auto ptr = malloc(IoOp.sizeof + bufferSize);
	if(ptr is null)
		assert(0); // out of memory!

	auto op = cast(IoOp*) ptr;

	op.handler = handler;
	op.internalFd = fd;
	op.operation = operation;
	op.bufferLengthAllocated = bufferSize;
	op.bufferLengthUsed = 0;

	return op;
}

void freeIoOp(ref IoOp* ptr) {
	import core.stdc.stdlib;
	free(ptr);
	ptr = null;
}

version(Posix)
void nonBlockingWrite(EventIoServer eis, int connection, const void[] data) {
	import core.sys.posix.unistd;

	auto ret = write(connection, data.ptr, data.length);
	if(ret != data.length) {
		if(ret == 0 || errno == EPIPE) {
			// the file is closed, remove it
			eis.fileClosed(connection);
		} else
			throw new Exception("alas " ~ to!string(ret) ~ " " ~ to!string(errno)); // FIXME
	}
}
version(Windows)
void nonBlockingWrite(EventIoServer eis, int connection, const void[] data) {
	// FIXME
}

bool isInvalidHandle(CgiConnectionHandle h) {
	return h == INVALID_CGI_CONNECTION_HANDLE;
}

/++
	You can customize your server by subclassing the appropriate server. Then, register your
	subclass at compile time with the [registerEventIoServer] template, or implement your own
	main function and call it yourself.
	
	$(TIP If you make your subclass a `final class`, there is a slight performance improvement.)
+/
interface EventIoServer {
	void handleLocalConnectionData(IoOp* op, int receivedFd);
	void handleLocalConnectionClose(IoOp* op);
	void handleLocalConnectionComplete(IoOp* op);
	void wait_timeout();
	void fileClosed(int fd);
}

// the sink should buffer it
private void serialize(T)(scope void delegate(ubyte[]) sink, T t) {
	static if(is(T == struct)) {
		foreach(member; __traits(allMembers, T))
			serialize(sink, __traits(getMember, t, member));
	} else static if(is(T : int)) {
		// no need to think of endianness just because this is only used
		// for local, same-machine stuff anyway. thanks private lol
		sink((cast(ubyte*) &t)[0 .. t.sizeof]);
	} else static if(is(T == string) || is(T : const(ubyte)[])) {
		// these are common enough to optimize
		int len = cast(int) t.length; // want length consistent size tho, in case 32 bit program sends to 64 bit server, etc.
		sink((cast(ubyte*) &len)[0 .. int.sizeof]);
		sink(cast(ubyte[]) t[]);
	} else static if(is(T : A[], A)) {
		// generic array is less optimal but still prolly ok
		int len = cast(int) t.length;
		sink((cast(ubyte*) &len)[0 .. int.sizeof]);
		foreach(item; t)
			serialize(sink, item);
	} else static assert(0, T.stringof);
}

// all may be stack buffers, so use cautio
private void deserialize(T)(scope ubyte[] delegate(int sz) get, scope void delegate(T) dg) {
	static if(is(T == struct)) {
		T t;
		foreach(member; __traits(allMembers, T))
			deserialize!(typeof(__traits(getMember, T, member)))(get, (mbr) { __traits(getMember, t, member) = mbr; });
		dg(t);
	} else static if(is(T : int)) {
		// no need to think of endianness just because this is only used
		// for local, same-machine stuff anyway. thanks private lol
		T t;
		auto data = get(t.sizeof);
		t = (cast(T[]) data)[0];
		dg(t);
	} else static if(is(T == string) || is(T : const(ubyte)[])) {
		// these are common enough to optimize
		int len;
		auto data = get(len.sizeof);
		len = (cast(int[]) data)[0];

		/*
		typeof(T[0])[2000] stackBuffer;
		T buffer;

		if(len < stackBuffer.length)
			buffer = stackBuffer[0 .. len];
		else
			buffer = new T(len);

		data = get(len * typeof(T[0]).sizeof);
		*/

		T t = cast(T) get(len * cast(int) typeof(T.init[0]).sizeof);

		dg(t);

	} else static assert(0, T.stringof);
}

unittest {
	serialize((ubyte[] b) {
		deserialize!int( sz => b[0 .. sz], (t) { assert(t == 1); });
	}, 1);
	serialize((ubyte[] b) {
		deserialize!int( sz => b[0 .. sz], (t) { assert(t == 56674); });
	}, 56674);
	ubyte[1000] buffer;
	int bufferPoint;
	void add(ubyte[] b) {
		buffer[bufferPoint ..  bufferPoint + b.length] = b[];
		bufferPoint += b.length;
	}
	ubyte[] get(int sz) {
		auto b = buffer[bufferPoint .. bufferPoint + sz];
		bufferPoint += sz;
		return b;
	}
	serialize(&add, "test here");
	bufferPoint = 0;
	deserialize!string(&get, (t) { assert(t == "test here"); });
	bufferPoint = 0;

	struct Foo {
		int a;
		ubyte c;
		string d;
	}
	serialize(&add, Foo(403, 37, "amazing"));
	bufferPoint = 0;
	deserialize!Foo(&get, (t) {
		assert(t.a == 403);
		assert(t.c == 37);
		assert(t.d == "amazing");
	});
	bufferPoint = 0;
}

/*
	Here's the way the RPC interface works:

	You define the interface that lists the functions you can call on the remote process.
	The interface may also have static methods for convenience. These forward to a singleton
	instance of an auto-generated class, which actually sends the args over the pipe.

	An impl class actually implements it. A receiving server deserializes down the pipe and
	calls methods on the class.

	I went with the interface to get some nice compiler checking and documentation stuff.

	I could have skipped the interface and just implemented it all from the server class definition
	itself, but then the usage may call the method instead of rpcing it; I just like having the user
	interface and the implementation separate so you aren't tempted to `new impl` to call the methods.


	I fiddled with newlines in the mixin string to ensure the assert line numbers matched up to the source code line number. Idk why dmd didn't do this automatically, but it was important to me.

	Realistically though the bodies would just be
		connection.call(this.mangleof, args...) sooooo.

	FIXME: overloads aren't supported
*/

mixin template ImplementRpcClientInterface(T, string serverPath) {
	static import std.traits;

	// derivedMembers on an interface seems to give exactly what I want: the virtual functions we need to implement. so I am just going to use it directly without more filtering.
	static foreach(idx, member; __traits(derivedMembers, T)) {
	static if(__traits(isVirtualFunction, __traits(getMember, T, member)))
		mixin( q{
		std.traits.ReturnType!(__traits(getMember, T, member))
		} ~ member ~ q{(std.traits.Parameters!(__traits(getMember, T, member)) params)
		{
			SerializationBuffer buffer;
			auto i = cast(ushort) idx;
			serialize(&buffer.sink, i);
			serialize(&buffer.sink, __traits(getMember, T, member).mangleof);
			foreach(param; params)
				serialize(&buffer.sink, param);

			auto sendable = buffer.sendable;

			version(Posix) {{
				auto ret = send(connectionHandle, sendable.ptr, sendable.length, 0);
				assert(ret == sendable.length);
			}} // FIXME Windows impl

			static if(!is(typeof(return) == void)) {
				// there is a return value; we need to wait for it too
				version(Posix) {
					ubyte[3000] revBuffer;
					auto ret = recv(connectionHandle, revBuffer.ptr, revBuffer.length, 0);
					auto got = revBuffer[0 .. ret];

					int dataLocation;
					ubyte[] grab(int sz) {
						auto d = got[dataLocation .. dataLocation + sz];
						dataLocation += sz;
						return d;
					}

					typeof(return) retu;
					deserialize!(typeof(return))(&grab, (a) { retu = a; });
					return retu;
				} else {
					// FIXME Windows impl
					return typeof(return).init;
				}

			}
		}});
	}

	private static typeof(this) singletonInstance;
	private LocalServerConnectionHandle connectionHandle;

	static typeof(this) connection() {
		if(singletonInstance is null) {
			singletonInstance = new typeof(this)();
			singletonInstance.connect();
		}
		return singletonInstance;
	}

	void connect() {
		connectionHandle = openLocalServerConnection(serverPath);
	}

	void disconnect() {
		closeLocalServerConnection(connectionHandle);
	}
}

void dispatchRpcServer(Interface, Class)(Class this_, ubyte[] data, int fd) if(is(Class : Interface)) {
	ushort calledIdx;
	string calledFunction;

	int dataLocation;
	ubyte[] grab(int sz) {
		auto d = data[dataLocation .. dataLocation + sz];
		dataLocation += sz;
		return d;
	}

	again:

	deserialize!ushort(&grab, (a) { calledIdx = a; });
	deserialize!string(&grab, (a) { calledFunction = a; });

	import std.traits;

	sw: switch(calledIdx) {
		static foreach(idx, memberName; __traits(derivedMembers, Interface))
		static if(__traits(isVirtualFunction, __traits(getMember, Interface, memberName))) {
			case idx:
				assert(calledFunction == __traits(getMember, Interface, memberName).mangleof);

				Parameters!(__traits(getMember, Interface, memberName)) params;
				foreach(ref param; params)
					deserialize!(typeof(param))(&grab, (a) { param = a; });

				static if(is(ReturnType!(__traits(getMember, Interface, memberName)) == void)) {
					__traits(getMember, this_, memberName)(params);
				} else {
					auto ret = __traits(getMember, this_, memberName)(params);
					SerializationBuffer buffer;
					serialize(&buffer.sink, ret);

					auto sendable = buffer.sendable;

					version(Posix) {
						auto r = send(fd, sendable.ptr, sendable.length, 0);
						assert(r == sendable.length);
					} // FIXME Windows impl
				}
			break sw;
		}
		default: assert(0);
	}

	if(dataLocation != data.length)
		goto again;
}


private struct SerializationBuffer {
	ubyte[2048] bufferBacking;
	int bufferLocation;
	void sink(scope ubyte[] data) {
		bufferBacking[bufferLocation .. bufferLocation + data.length] = data[];
		bufferLocation += data.length;
	}

	ubyte[] sendable() {
		return bufferBacking[0 .. bufferLocation];
	}
}

/*
	FIXME:
		add a version command line arg
		version data in the library
		management gui as external program

		at server with event_fd for each run
		use .mangleof in the at function name

		i think the at server will have to:
			pipe args to the child
			collect child output for logging
			get child return value for logging

			on windows timers work differently. idk how to best combine with the io stuff.

			will have to have dump and restore too, so i can restart without losing stuff.
*/

/++

+/
interface BasicDataServer {
	///
	void createSession(string sessionId, int lifetime);
	///
	void renewSession(string sessionId, int lifetime);
	///
	void destroySession(string sessionId);
	///
	void renameSession(string oldSessionId, string newSessionId);

	///
	void setSessionData(string sessionId, string dataKey, string dataValue);
	///
	string getSessionData(string sessionId, string dataKey);

	///
	static BasicDataServerConnection connection() {
		return BasicDataServerConnection.connection();
	}
}

class BasicDataServerConnection : BasicDataServer {
	mixin ImplementRpcClientInterface!(BasicDataServer, "/tmp/arsd_session_server");
}

final class BasicDataServerImplementation : BasicDataServer, EventIoServer {

	void createSession(string sessionId, int lifetime) {
		sessions[sessionId.idup] = Session(lifetime);
	}
	void destroySession(string sessionId) {
		sessions.remove(sessionId);
	}
	void renewSession(string sessionId, int lifetime) {
		sessions[sessionId].lifetime = lifetime;
	}
	void renameSession(string oldSessionId, string newSessionId) {
		sessions[newSessionId.idup] = sessions[oldSessionId];
		sessions.remove(oldSessionId);
	}
	void setSessionData(string sessionId, string dataKey, string dataValue) {
		sessions[sessionId].values[dataKey.idup] = dataValue.idup;
	}
	string getSessionData(string sessionId, string dataKey) {
		return sessions[sessionId].values[dataKey];
	}


	protected:

	struct Session {
		int lifetime;

		string[string] values;
	}

	Session[string] sessions;

	void handleLocalConnectionData(IoOp* op, int receivedFd) {
		auto data = op.usedBuffer;
		dispatchRpcServer!BasicDataServer(this, data, op.fd);
	}

	void handleLocalConnectionClose(IoOp* op) {} // doesn't really matter, this is a fairly stateless go
	void handleLocalConnectionComplete(IoOp* op) {} // again, irrelevant
	void wait_timeout() {}
	void fileClosed(int fd) {} // stateless so irrelevant
}

/++

+/
struct ScheduledJobHelper {
	private string func;
	private string[] args;

	/++
		Schedules the job to be run at the given time.
	+/
	void at(DateTime when, immutable TimeZone timezone = UTC()) {

	}

	/++
		Schedules the job to run at least after the specified delay.
	+/
	void delay(Duration delay) {

	}

	/++
		Runs the job in the background ASAP.

		$(NOTE It may run in a background thread. Don't segfault!)
	+/
	void runNowInBackground() {
		//delay(0);
	}

	/++
		Schedules the job to recur on the given pattern.
	+/
	version(none)
	void recur(string spec) {

	}
}

/++
	First step to schedule a job on the scheduled job server.

	You MUST set details on the returned object to actually do anything!
+/
ScheduledJobHelper schedule(alias fn, T...)(T args) {
	return ScheduledJobHelper();
}

///
interface ScheduledJobServer {
	///
	int scheduleJob(int whenIs, int when, string executable, string func, string[] args);
	///
	void cancelJob(int jobId);
}

class ScheduledJobServerConnection : ScheduledJobServer {
	mixin ImplementRpcClientInterface!(ScheduledJobServer, "/tmp/arsd_scheduled_job_server");
}

///
interface EventSourceServer {
	/++
		sends this cgi request to the event server so it will be fed events. You should not do anything else with the cgi object after this.

		$(WARNING This API is extremely unstable. I might change it or remove it without notice.)

		See_Also:
			[sendEvent]
	+/
	public static void adoptConnection(Cgi cgi, in char[] eventUrl) {
		/*
			If lastEventId is missing or empty, you just get new events as they come.

			If it is set from something else, it sends all since then (that are still alive)
			down the pipe immediately.

			The reason it can come from the header is that's what the standard defines for
			browser reconnects. The reason it can come from a query string is just convenience
			in catching up in a user-defined manner.

			The reason the header overrides the query string is if the browser tries to reconnect,
			it will send the header AND the query (it reconnects to the same url), so we just
			want to do the restart thing.

			Note that if you ask for "0" as the lastEventId, it will get ALL still living events.
		*/
		string lastEventId = cgi.lastEventId;
		if(lastEventId.length == 0 && "lastEventId" in cgi.get)
			lastEventId = cgi.get["lastEventId"];

		cgi.setResponseContentType("text/event-stream");
		cgi.write(":\n", false); // to initialize the chunking and send headers before keeping the fd for later
		cgi.flush();

		cgi.closed = true;
		auto s = openLocalServerConnection("/tmp/arsd_cgi_event_server");
		scope(exit)
			closeLocalServerConnection(s);

		version(fastcgi)
			throw new Exception("sending fcgi connections not supported");

		auto fd = cgi.getOutputFileHandle();
		if(isInvalidHandle(fd))
			throw new Exception("bad fd from cgi!");

		EventSourceServerImplementation.SendableEventConnection sec;
		sec.populate(cgi.responseChunked, eventUrl, lastEventId);

		version(Posix) {
			auto res = write_fd(s, cast(void*) &sec, sec.sizeof, fd);
			assert(res == sec.sizeof);
		} else version(Windows) {
			// FIXME
		}
	}

	/++
		Sends an event to the event server, starting it if necessary. The event server will distribute it to any listening clients, and store it for `lifetime` seconds for any later listening clients to catch up later.

		$(WARNING This API is extremely unstable. I might change it or remove it without notice.)

		Params:
			url = A string identifying this event "bucket". Listening clients must also connect to this same string. I called it `url` because I envision it being just passed as the url of the request.
			event = the event type string, which is used in the Javascript addEventListener API on EventSource
			data = the event data. Available in JS as `event.data`.
			lifetime = the amount of time to keep this event for replaying on the event server.

		See_Also:
			[sendEventToEventServer]
	+/
	public static void sendEvent(string url, string event, string data, int lifetime) {
		auto s = openLocalServerConnection("/tmp/arsd_cgi_event_server");
		scope(exit)
			closeLocalServerConnection(s);

		EventSourceServerImplementation.SendableEvent sev;
		sev.populate(url, event, data, lifetime);

		version(Posix) {
			auto ret = send(s, &sev, sev.sizeof, 0);
			assert(ret == sev.sizeof);
		} else version(Windows) {
			// FIXME
		}
	}

	/++
		Messages sent to `url` will also be sent to anyone listening on `forwardUrl`.

		See_Also: [disconnect]
	+/
	void connect(string url, string forwardUrl);

	/++
		Disconnects `forwardUrl` from `url`

		See_Also: [connect]
	+/
	void disconnect(string url, string forwardUrl);
}

///
final class EventSourceServerImplementation : EventSourceServer, EventIoServer {

	protected:

	void connect(string url, string forwardUrl) {
		pipes[url] ~= forwardUrl;
	}
	void disconnect(string url, string forwardUrl) {
		auto t = url in pipes;
		if(t is null)
			return;
		foreach(idx, n; (*t))
			if(n == forwardUrl) {
				(*t)[idx] = (*t)[$-1];
				(*t) = (*t)[0 .. $-1];
				break;
			}
	}

	void handleLocalConnectionData(IoOp* op, int receivedFd) {
		if(receivedFd != -1) {
			//writeln("GOT FD ", receivedFd, " -- ", op.usedBuffer);

			//core.sys.posix.unistd.write(receivedFd, "hello".ptr, 5);

			SendableEventConnection* got = cast(SendableEventConnection*) op.usedBuffer.ptr;

			auto url = got.url.idup;
			eventConnectionsByUrl[url] ~= EventConnection(receivedFd, got.responseChunked > 0 ? true : false);

			// FIXME: catch up on past messages here
		} else {
			auto data = op.usedBuffer;
			auto event = cast(SendableEvent*) data.ptr;

			if(event.magic == 0xdeadbeef) {
				handleInputEvent(event);

				if(event.url in pipes)
				foreach(pipe; pipes[event.url]) {
					event.url = pipe;
					handleInputEvent(event);
				}
			} else {
				dispatchRpcServer!EventSourceServer(this, data, op.fd);
			}
		}
	}
	void handleLocalConnectionClose(IoOp* op) {}
	void handleLocalConnectionComplete(IoOp* op) {}

	void wait_timeout() {
		// just keeping alive
		foreach(url, connections; eventConnectionsByUrl)
		foreach(connection; connections)
			if(connection.needsChunking)
				nonBlockingWrite(this, connection.fd, "2\r\n:\n");
			else
				nonBlockingWrite(this, connection.fd, ":\n");
	}

	void fileClosed(int fd) {
		outer: foreach(url, ref connections; eventConnectionsByUrl) {
			foreach(idx, conn; connections) {
				if(fd == conn.fd) {
					connections[idx] = connections[$-1];
					connections = connections[0 .. $ - 1];
					continue outer;
				}
			}
		}
	}



	private:


	struct SendableEventConnection {
		ubyte responseChunked;

		int urlLength;
		char[256] urlBuffer = 0;

		int lastEventIdLength;
		char[32] lastEventIdBuffer = 0;

		char[] url() {
			return urlBuffer[0 .. urlLength];
		}
		void url(in char[] u) {
			urlBuffer[0 .. u.length] = u[];
			urlLength = cast(int) u.length;
		}
		char[] lastEventId() {
			return lastEventIdBuffer[0 .. lastEventIdLength];
		}
		void populate(bool responseChunked, in char[] url, in char[] lastEventId)
		in {
			assert(url.length < this.urlBuffer.length);
			assert(lastEventId.length < this.lastEventIdBuffer.length);
		}
		do {
			this.responseChunked = responseChunked ? 1 : 0;
			this.urlLength = cast(int) url.length;
			this.lastEventIdLength = cast(int) lastEventId.length;

			this.urlBuffer[0 .. url.length] = url[];
			this.lastEventIdBuffer[0 .. lastEventId.length] = lastEventId[];
		}
	}

	struct SendableEvent {
		int magic = 0xdeadbeef;
		int urlLength;
		char[256] urlBuffer = 0;
		int typeLength;
		char[32] typeBuffer = 0;
		int messageLength;
		char[2048] messageBuffer = 0;
		int _lifetime;

		char[] message() {
			return messageBuffer[0 .. messageLength];
		}
		char[] type() {
			return typeBuffer[0 .. typeLength];
		}
		char[] url() {
			return urlBuffer[0 .. urlLength];
		}
		void url(in char[] u) {
			urlBuffer[0 .. u.length] = u[];
			urlLength = cast(int) u.length;
		}
		int lifetime() {
			return _lifetime;
		}

		///
		void populate(string url, string type, string message, int lifetime)
		in {
			assert(url.length < this.urlBuffer.length);
			assert(type.length < this.typeBuffer.length);
			assert(message.length < this.messageBuffer.length);
		}
		do {
			this.urlLength = cast(int) url.length;
			this.typeLength = cast(int) type.length;
			this.messageLength = cast(int) message.length;
			this._lifetime = lifetime;

			this.urlBuffer[0 .. url.length] = url[];
			this.typeBuffer[0 .. type.length] = type[];
			this.messageBuffer[0 .. message.length] = message[];
		}
	}

	struct EventConnection {
		int fd;
		bool needsChunking;
	}

	private EventConnection[][string] eventConnectionsByUrl;
	private string[][string] pipes;

	private void handleInputEvent(scope SendableEvent* event) {
		static int eventId;

		static struct StoredEvent {
			int id;
			string type;
			string message;
			int lifetimeRemaining;
		}

		StoredEvent[][string] byUrl;

		int thisId = ++eventId;

		if(event.lifetime)
			byUrl[event.url.idup] ~= StoredEvent(thisId, event.type.idup, event.message.idup, event.lifetime);

		auto connectionsPtr = event.url in eventConnectionsByUrl;
		EventConnection[] connections;
		if(connectionsPtr is null)
			return;
		else
			connections = *connectionsPtr;

		char[4096] buffer;
		char[] formattedMessage;

		void append(const char[] a) {
			// the 6's here are to leave room for a HTTP chunk header, if it proves necessary
			buffer[6 + formattedMessage.length .. 6 + formattedMessage.length + a.length] = a[];
			formattedMessage = buffer[6 .. 6 + formattedMessage.length + a.length];
		}

		import std.algorithm.iteration;

		if(connections.length) {
			append("id: ");
			append(to!string(thisId));
			append("\n");

			append("event: ");
			append(event.type);
			append("\n");

			foreach(line; event.message.splitter("\n")) {
				append("data: ");
				append(line);
				append("\n");
			}

			append("\n");
		}

		// chunk it for HTTP!
		auto len = toHex(formattedMessage.length);
		buffer[4 .. 6] = "\r\n"[];
		buffer[4 - len.length .. 4] = len[];

		auto chunkedMessage = buffer[4 - len.length .. 6 + formattedMessage.length];
		// done

		// FIXME: send back requests when needed
		// FIXME: send a single ":\n" every 15 seconds to keep alive

		foreach(connection; connections) {
			if(connection.needsChunking)
				nonBlockingWrite(this, connection.fd, chunkedMessage);
			else
				nonBlockingWrite(this, connection.fd, formattedMessage);
		}
	}
}

void runAddonServer(EIS)(string localListenerName, EIS eis) if(is(EIS : EventIoServer)) {
	version(Posix) {

		import core.sys.posix.unistd;
		import core.sys.posix.fcntl;
		import core.sys.posix.sys.un;

		import core.sys.posix.signal;
		signal(SIGPIPE, SIG_IGN);

		int sock = socket(AF_UNIX, SOCK_STREAM, 0);
		if(sock == -1)
			throw new Exception("socket " ~ to!string(errno));

		scope(failure)
			close(sock);

		// add-on server processes are assumed to be local, and thus will
		// use unix domain sockets. Besides, I want to pass sockets to them,
		// so it basically must be local (except for the session server, but meh).
		sockaddr_un addr;
		addr.sun_family = AF_UNIX;
		version(linux) {
			// on linux, we will use the abstract namespace
			addr.sun_path[0] = 0;
			addr.sun_path[1 .. localListenerName.length + 1] = cast(typeof(addr.sun_path[])) localListenerName[];
		} else {
			// but otherwise, just use a file cuz we must.
			addr.sun_path[0 .. localListenerName.length] = cast(typeof(addr.sun_path[])) localListenerName[];
		}

		if(bind(sock, cast(sockaddr*) &addr, addr.sizeof) == -1)
			throw new Exception("bind " ~ to!string(errno));

		if(listen(sock, 128) == -1)
			throw new Exception("listen " ~ to!string(errno));

		version(linux) {

			makeNonBlocking(sock);

			import core.sys.linux.epoll;
			auto epoll_fd = epoll_create1(EPOLL_CLOEXEC);
			if(epoll_fd == -1)
				throw new Exception("epoll_create1 " ~ to!string(errno));
			scope(failure)
				close(epoll_fd);

			auto acceptOp = allocateIoOp(sock, IoOp.Read, 0, null);
			scope(exit)
				freeIoOp(acceptOp);

			epoll_event ev;
			ev.events = EPOLLIN | EPOLLET;
			ev.data.ptr = acceptOp;
			if(epoll_ctl(epoll_fd, EPOLL_CTL_ADD, sock, &ev) == -1)
				throw new Exception("epoll_ctl " ~ to!string(errno));

			epoll_event[64] events;

			while(true) {

				// FIXME: it should actually do a timerfd that runs on any thing that hasn't been run recently

				int timeout_milliseconds = 15000; //  -1; // infinite
				//writeln("waiting for ", name);
				auto nfds = epoll_wait(epoll_fd, events.ptr, events.length, timeout_milliseconds);
				if(nfds == -1) {
					if(errno == EINTR)
						continue;
					throw new Exception("epoll_wait " ~ to!string(errno));
				}

				if(nfds == 0) {
					eis.wait_timeout();
				}

				foreach(idx; 0 .. nfds) {
					auto flags = events[idx].events;
					auto ioop = cast(IoOp*) events[idx].data.ptr;

					//writeln(flags, " ", ioop.fd);

					if(ioop.fd == sock && (flags & EPOLLIN)) {
						// on edge triggering, it is important that we get it all
						while(true) {
							auto size = cast(uint) addr.sizeof;
							auto ns = accept(sock, cast(sockaddr*) &addr, &size);
							if(ns == -1) {
								if(errno == EAGAIN || errno == EWOULDBLOCK) {
									// all done, got it all
									break;
								}
								throw new Exception("accept " ~ to!string(errno));
							}

							makeNonBlocking(ns);
							epoll_event nev;
							nev.events = EPOLLIN | EPOLLET;
							auto niop = allocateIoOp(ns, IoOp.ReadSocketHandle, 4096, &eis.handleLocalConnectionData);
							niop.closeHandler = &eis.handleLocalConnectionClose;
							niop.completeHandler = &eis.handleLocalConnectionComplete;
							scope(failure) freeIoOp(niop);
							nev.data.ptr = niop;
							if(epoll_ctl(epoll_fd, EPOLL_CTL_ADD, ns, &nev) == -1)
								throw new Exception("epoll_ctl " ~ to!string(errno));
						}
					} else if(ioop.operation == IoOp.ReadSocketHandle) {
						while(true) {
							int in_fd;
							auto got = read_fd(ioop.fd, ioop.allocatedBuffer.ptr, ioop.allocatedBuffer.length, &in_fd);
							if(got == -1) {
								if(errno == EAGAIN || errno == EWOULDBLOCK) {
									// all done, got it all
									if(ioop.completeHandler)
										ioop.completeHandler(ioop);
									break;
								}
								throw new Exception("recv " ~ to!string(errno));
							}

							if(got == 0) {
								if(ioop.closeHandler)
									ioop.closeHandler(ioop);
								close(ioop.fd);
								freeIoOp(ioop);
								break;
							}

							ioop.bufferLengthUsed = cast(int) got;
							ioop.handler(ioop, in_fd);
						}
					} else if(ioop.operation == IoOp.Read) {
						while(true) {
							auto got = recv(ioop.fd, ioop.allocatedBuffer.ptr, ioop.allocatedBuffer.length, 0);
							if(got == -1) {
								if(errno == EAGAIN || errno == EWOULDBLOCK) {
									// all done, got it all
									if(ioop.completeHandler)
										ioop.completeHandler(ioop);
									break;
								}
								throw new Exception("recv " ~ to!string(errno));
							}

							if(got == 0) {
								if(ioop.closeHandler)
									ioop.closeHandler(ioop);
								close(ioop.fd);
								freeIoOp(ioop);
								break;
							}

							ioop.bufferLengthUsed = cast(int) got;
							ioop.handler(ioop, -1);
						}
					}

					// EPOLLHUP?
				}
			}
		} else {
			// this isn't seriously implemented.
			static assert(0);
		}
	} else version(Windows) {

		// set up a named pipe
		// https://msdn.microsoft.com/en-us/library/windows/desktop/ms724251(v=vs.85).aspx
		// https://docs.microsoft.com/en-us/windows/desktop/api/winsock2/nf-winsock2-wsaduplicatesocketw
		// https://docs.microsoft.com/en-us/windows/desktop/api/winbase/nf-winbase-getnamedpipeserverprocessid

	} else static assert(0);
}


version(Posix)
// copied from the web and ported from C
// see https://stackoverflow.com/questions/2358684/can-i-share-a-file-descriptor-to-another-process-on-linux-or-are-they-local-to-t
ssize_t write_fd(int fd, void *ptr, size_t nbytes, int sendfd) {
	msghdr msg;
	iovec[1] iov;

	union ControlUnion {
		cmsghdr cm;
		char[CMSG_SPACE(int.sizeof)] control;
	}

	ControlUnion control_un;
	cmsghdr* cmptr;

	msg.msg_control = control_un.control.ptr;
	msg.msg_controllen = control_un.control.length;

	cmptr = CMSG_FIRSTHDR(&msg);
	cmptr.cmsg_len = CMSG_LEN(int.sizeof);
	cmptr.cmsg_level = SOL_SOCKET;
	cmptr.cmsg_type = SCM_RIGHTS;
	*(cast(int *) CMSG_DATA(cmptr)) = sendfd;

	msg.msg_name = null;
	msg.msg_namelen = 0;

	iov[0].iov_base = ptr;
	iov[0].iov_len = nbytes;
	msg.msg_iov = iov.ptr;
	msg.msg_iovlen = 1;

	return sendmsg(fd, &msg, 0);
}

version(Posix)
// copied from the web and ported from C
ssize_t read_fd(int fd, void *ptr, size_t nbytes, int *recvfd) {
	msghdr msg;
	iovec[1] iov;
	ssize_t n;
	int newfd;

	union ControlUnion {
		cmsghdr cm;
		char[CMSG_SPACE(int.sizeof)] control;
	}
	ControlUnion control_un;
	cmsghdr* cmptr;

	msg.msg_control = control_un.control.ptr;
	msg.msg_controllen = control_un.control.length;

	msg.msg_name = null;
	msg.msg_namelen = 0;

	iov[0].iov_base = ptr;
	iov[0].iov_len = nbytes;
	msg.msg_iov = iov.ptr;
	msg.msg_iovlen = 1;

	if ( (n = recvmsg(fd, &msg, 0)) <= 0)
		return n;

	if ( (cmptr = CMSG_FIRSTHDR(&msg)) != null &&
			cmptr.cmsg_len == CMSG_LEN(int.sizeof)) {
		if (cmptr.cmsg_level != SOL_SOCKET)
			throw new Exception("control level != SOL_SOCKET");
		if (cmptr.cmsg_type != SCM_RIGHTS)
			throw new Exception("control type != SCM_RIGHTS");
		*recvfd = *(cast(int *) CMSG_DATA(cmptr));
	} else
		*recvfd = -1;       /* descriptor was not passed */

	return n;
}
/* end read_fd */


/*
	Event source stuff

	The api is:

	sendEvent(string url, string type, string data, int timeout = 60*10);

	attachEventListener(string url, int fd, lastId)


	It just sends to all attached listeners, and stores it until the timeout
	for replaying via lastEventId.
*/

/*
	Session process stuff

	it stores it all. the cgi object has a session object that can grab it

	session may be done in the same process if possible, there is a version
	switch to choose if you want to override.
*/

struct DispatcherDefinition(alias dispatchHandler) {// if(is(typeof(dispatchHandler("str", Cgi.init) == bool))) { // bool delegate(string urlPrefix, Cgi cgi) dispatchHandler;
	alias handler = dispatchHandler;
	string urlPrefix;
	bool rejectFurther;
}

private string urlify(string name) {
	return name;
}

private string beautify(string name) {
	char[160] buffer;
	int bufferIndex = 0;
	bool shouldCap = true;
	bool shouldSpace;
	bool lastWasCap;
	foreach(idx, char ch; name) {
		if(bufferIndex == buffer.length) return name; // out of space, just give up, not that important

		if(ch >= 'A' && ch <= 'Z') {
			if(lastWasCap) {
				// two caps in a row, don't change. Prolly acronym.
			} else {
				if(idx)
					shouldSpace = true; // new word, add space
			}

			lastWasCap = true;
		}

		if(shouldSpace) {
			buffer[bufferIndex++] = ' ';
			if(bufferIndex == buffer.length) return name; // out of space, just give up, not that important
		}
		if(shouldCap) {
			if(ch >= 'a' && ch <= 'z')
				ch -= 32;
			shouldCap = false;
		}
		buffer[bufferIndex++] = ch;
	}
	return buffer[0 .. bufferIndex].idup;
}

/+
	Argument conversions: for the most part, it is to!Thing(string).

	But arrays and structs are a bit different. Arrays come from the cgi array. Thus
	they are passed

	arr=foo&arr=bar <-- notice the same name.

	Structs are first declared with an empty thing, then have their members set individually,
	with dot notation. The members are not required, just the initial declaration.

	struct Foo {
		int a;
		string b;
	}
	void test(Foo foo){}

	foo&foo.a=5&foo.b=str <-- the first foo declares the arg, the others set the members

	Arrays of structs use this declaration.

	void test(Foo[] foo) {}

	foo&foo.a=5&foo.b=bar&foo&foo.a=9

	You can use a hidden input field in HTML forms to achieve this. The value of the naked name
	declaration is ignored.

	Mind that order matters! The declaration MUST come first in the string.

	Arrays of struct members follow this rule recursively.

	struct Foo {
		int[] a;
	}

	foo&foo.a=1&foo.a=2&foo&foo.a=1


	Associative arrays are formatted with brackets, after a declaration, like structs:

	foo&foo[key]=value&foo[other_key]=value


	Note: for maximum compatibility with outside code, keep your types simple. Some libraries
	do not support the strict ordering requirements to work with these struct protocols.

	FIXME: also perhaps accept application/json to better work with outside trash.


	Return values are also auto-formatted according to user-requested type:
		for json, it loops over and converts.
		for html, basic types are strings. Arrays are <ol>. Structs are <dl>. Arrays of structs are tables!
+/

// returns an arsd.dom.Element
static auto elementFor(T)(string displayName, string name) {
	import arsd.dom;
	import std.traits;

	auto div = Element.make("div");
	div.addClass("form-field");

	static if(is(T == struct)) {
		if(displayName !is null)
			div.addChild("span", displayName, "label-text");
		auto fieldset = div.addChild("fieldset");
		fieldset.addChild("legend", beautify(T.stringof)); // FIXME
		fieldset.addChild("input", name);
		static foreach(idx, memberName; __traits(allMembers, T))
		static if(__traits(compiles, __traits(getMember, T, memberName).offsetof)) {
			fieldset.appendChild(elementFor!(typeof(__traits(getMember, T, memberName)))(beautify(memberName), name ~ "." ~ memberName));
		}
	} else static if(isSomeString!T || isIntegral!T || isFloatingPoint!T) {
		Element lbl;
		if(displayName !is null) {
			lbl = div.addChild("label");
			lbl.addChild("span", displayName, "label-text");
			lbl.appendText(" ");
		} else {
			lbl = div;
		}
		auto i = lbl.addChild("input", name);
		i.attrs.name = name;
		static if(isSomeString!T)
			i.attrs.type = "text";
		else
			i.attrs.type = "number";
		i.attrs.value = to!string(T.init);
	} else static if(is(T == K[], K)) {
		auto templ = div.addChild("template");
		templ.appendChild(elementFor!(K)(null, name));
		if(displayName !is null)
			div.addChild("span", displayName, "label-text");
		auto btn = div.addChild("button");
		btn.addClass("add-array-button");
		btn.attrs.type = "button";
		btn.innerText = "Add";
		btn.attrs.onclick = q{
			var a = document.importNode(this.parentNode.firstChild.content, true);
			this.parentNode.insertBefore(a, this);
		};
	} else static if(is(T == V[K], K, V)) {
		div.innerText = "assoc array not implemented for automatic form at this time";
	} else {
		static assert(0, "unsupported type for cgi call " ~ T.stringof);
	}


	return div;
}

// actually returns an arsd.dom.Form
auto createAutomaticFormForFunction(alias method, T)(T dg) {
	import arsd.dom;

	auto form = cast(Form) Element.make("form");

	form.addClass("automatic-form");

	form.addChild("h3", beautify(__traits(identifier, method)));

	import std.traits;

	//Parameters!method params;
	//alias idents = ParameterIdentifierTuple!method;
	//alias defaults = ParameterDefaults!method;

	static if(is(typeof(method) P == __parameters))
	static foreach(idx, _; P) {{
		alias param = P[idx .. idx + 1];
		string displayName = beautify(__traits(identifier, param));
		static foreach(attr; __traits(getAttributes, param))
			static if(is(typeof(attr) == DisplayName))
				displayName = attr.name;
		form.appendChild(elementFor!(param)(displayName, __traits(identifier, param)));
	}}

	form.addChild("div", Html(`<input type="submit" value="Submit" />`), "submit-button-holder");

	return form;
}

// actually returns an arsd.dom.Form
auto createAutomaticFormForObject(T)(T obj) {
	import arsd.dom;

	auto form = cast(Form) Element.make("form");

	form.addClass("automatic-form");

	form.addChild("h3", beautify(__traits(identifier, T)));

	import std.traits;

	//Parameters!method params;
	//alias idents = ParameterIdentifierTuple!method;
	//alias defaults = ParameterDefaults!method;

	static foreach(idx, memberName; __traits(derivedMembers, T)) {{
	static if(__traits(compiles, __traits(getMember, obj, memberName).offsetof)) {
		string displayName = beautify(memberName);
		static foreach(attr; __traits(getAttributes,  __traits(getMember, T, memberName)))
			static if(is(typeof(attr) == DisplayName))
				displayName = attr.name;
		form.appendChild(elementFor!(typeof(__traits(getMember, T, memberName)))(displayName, memberName));

		form.setValue(memberName, to!string(__traits(getMember, obj, memberName)));
	}}}

	form.addChild("div", Html(`<input type="submit" value="Submit" />`), "submit-button-holder");

	return form;
}

/*
string urlFor(alias func)() {
	return __traits(identifier, func);
}
*/

/++
	UDA: The name displayed to the user in auto-generated HTML.

	Default is `beautify(identifier)`.
+/
struct DisplayName {
	string name;
}

/++
	UDA: The name used in the URL or web parameter.

	Default is `urlify(identifier)` for functions and `identifier` for parameters and data members.
+/
struct UrlName {
	string name;
}

class MissingArgumentException : Exception {
	string functionName;
	string argumentName;
	string argumentType;

	this(string functionName, string argumentName, string argumentType, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		this.functionName = functionName;
		this.argumentName = argumentName;
		this.argumentType = argumentType;

		super("Missing Argument", file, line, next);
	}
}

auto callFromCgi(alias method, T)(T dg, Cgi cgi) {

	// FIXME: any array of structs should also be settable or gettable from csv as well.

	// FIXME: think more about checkboxes and bools.

	import std.traits;

	Parameters!method params;
	alias idents = ParameterIdentifierTuple!method;
	alias defaults = ParameterDefaults!method;

	const(string)[] names;
	const(string)[] values;

	// first, check for missing arguments and initialize to defaults if necessary
	static foreach(idx, param; params) {{
		auto ident = idents[idx];
		if(cgi.requestMethod == Cgi.RequestMethod.POST) {
			if(ident !in cgi.post) {
				static if(is(defaults[idx] == void))
					throw new MissingArgumentException(__traits(identifier, method), ident, typeof(param).stringof);
				else
					params[idx] = defaults[idx];
			}
		} else {
			if(ident !in cgi.get) {
				static if(is(defaults[idx] == void))
					throw new MissingArgumentException(__traits(identifier, method), ident, typeof(param).stringof);
				else
					params[idx] = defaults[idx];
			}
		}
	}}

	// second, parse the arguments in order to build up arrays, etc.

	static bool setVariable(T)(string name, string paramName, T* what, string value) {
		static if(is(T == struct)) {
			if(name == paramName) {
				*what = T.init;
				return true;
			} else {
				// could be a child
				if(name[paramName.length] == '.') {
					paramName = name[paramName.length + 1 .. $];
					name = paramName;
					int p = 0;
					foreach(ch; paramName) {
						if(ch == '.' || ch == '[')
							break;
						p++;
					}

					// set the child member
					switch(paramName) {
						static foreach(idx, memberName; __traits(allMembers, T))
						static if(__traits(compiles, __traits(getMember, T, memberName).offsetof)) {
							// data member!
							case memberName:
								return setVariable(name, paramName, &(__traits(getMember, *what, memberName)), value);
						}
						default:
							// ok, not a member
					}
				}
			}
		} else static if(isSomeString!T || isIntegral!T || isFloatingPoint!T) {
			*what = to!T(value);
			return true;
		} else static if(is(T == K[], K)) {
			K tmp;
			if(name == paramName) {
				// direct - set and append
				if(setVariable(name, paramName, &tmp, value)) {
					(*what) ~= tmp;
					return true;
				} else {
					return false;
				}
			} else {
				// child, append to last element
				// FIXME: what about range violations???
				auto ptr = &(*what)[(*what).length - 1];
				return setVariable(name, paramName, ptr, value);

			}
		} else static if(is(T == V[K], K, V)) {
			// assoc array, name[key] is valid
			if(name == paramName) {
				// no action necessary
				return true;
			} else if(name[paramName.length] == '[') {
				int count = 1;
				auto idx = paramName.length + 1;
				while(idx < name.length && count > 0) {
					if(name[idx] == '[')
						count++;
					else if(name[idx] == ']') {
						count--;
						if(count == 0) break;
					}
					idx++;
				}
				if(idx == name.length)
					return false; // malformed

				auto insideBrackets = name[paramName.length + 1 .. idx];
				auto afterName = name[idx + 1 .. $];

				auto k = to!K(insideBrackets);
				V v;

				name = name[0 .. paramName.length];
				writeln(name, afterName, " ", paramName);

				auto ret = setVariable(name ~ afterName, paramName, &v, value);
				if(ret) {
					(*what)[k] = v;
					return true;
				}
			}
		} else {
			static assert(0, "unsupported type for cgi call " ~ T.stringof);
		}

		return false;
	}

	void setArgument(string name, string value) {
		int p;
		foreach(ch; name) {
			if(ch == '.' || ch == '[')
				break;
			p++;
		}

		auto paramName = name[0 .. p];

		sw: switch(paramName) {
			static foreach(idx, param; params) {
				case idents[idx]:
					setVariable(name, paramName, &params[idx], value);
				break sw;
			}
			default:
				// ignore; not relevant argument
		}
	}

	if(cgi.requestMethod == Cgi.RequestMethod.POST) {
		names = cgi.allPostNamesInOrder;
		values = cgi.allPostValuesInOrder;
	} else {
		names = cgi.allGetNamesInOrder;
		values = cgi.allGetValuesInOrder;
	}

	foreach(idx, name; names) {
		setArgument(name, values[idx]);
	}

	static if(is(ReturnType!method == void)) {
		typeof(null) ret;
		dg(params);
	} else {
		auto ret = dg(params);
	}

	// FIXME: format return values
	// options are: json, html, csv.
	// also may need to wrap in envelope format: none, html, or json.
	return ret;
}

auto formatReturnValueAsHtml(T)(T t) {
	import arsd.dom;
	import std.traits;

	static if(is(T == typeof(null))) {
		return Element.make("span");
	} else static if(isIntegral!T || isSomeString!T || isFloatingPoint!T) {
		return Element.make("span", to!string(t), "automatic-data-display");
	} else static if(is(T == V[K], K, V)) {
		auto dl = Element.make("dl");
		dl.addClass("automatic-data-display");
		foreach(k, v; t) {
			dl.addChild("dt", to!string(k));
			dl.addChild("dd", formatReturnValueAsHtml(v));
		}
		return dl;
	} else static if(is(T == struct)) {
		auto dl = Element.make("dl");
		dl.addClass("automatic-data-display");

		static foreach(idx, memberName; __traits(allMembers, T))
		static if(__traits(compiles, __traits(getMember, T, memberName).offsetof)) {
			dl.addChild("dt", memberName);
			dl.addChild("dt", formatReturnValueAsHtml(__traits(getMember, t, memberName)));
		}

		return dl;
	} else static if(is(T == E[], E)) {
		static if(is(E : RestObject!Proxy, Proxy)) {
			// treat RestObject similar to struct
			auto table = cast(Table) Element.make("table");
			table.addClass("automatic-data-display");
			string[] names;
			static foreach(idx, memberName; __traits(derivedMembers, E))
			static if(__traits(compiles, __traits(getMember, E, memberName).offsetof)) {
				names ~= beautify(memberName);
			}
			table.appendHeaderRow(names);

			foreach(l; t) {
				auto tr = table.appendRow();
				static foreach(idx, memberName; __traits(derivedMembers, E))
				static if(__traits(compiles, __traits(getMember, E, memberName).offsetof)) {
					static if(memberName == "id") {
						string val = to!string(__traits(getMember, l, memberName));
						tr.addChild("td", Element.make("a", val, E.stringof.toLower ~ "s/" ~ val)); // FIXME
					} else {
						tr.addChild("td", formatReturnValueAsHtml(__traits(getMember, l, memberName)));
					}
				}
			}

			return table;
		} else static if(is(E == struct)) {
			// an array of structs is kinda special in that I like
			// having those formatted as tables.
			auto table = cast(Table) Element.make("table");
			table.addClass("automatic-data-display");
			string[] names;
			static foreach(idx, memberName; __traits(allMembers, E))
			static if(__traits(compiles, __traits(getMember, E, memberName).offsetof)) {
				names ~= beautify(memberName);
			}
			table.appendHeaderRow(names);

			foreach(l; t) {
				auto tr = table.appendRow();
				static foreach(idx, memberName; __traits(allMembers, E))
				static if(__traits(compiles, __traits(getMember, E, memberName).offsetof)) {
					tr.addChild("td", formatReturnValueAsHtml(__traits(getMember, l, memberName)));
				}
			}

			return table;
		} else {
			// otherwise, I will just make a list.
			auto ol = Element.make("ol");
			ol.addClass("automatic-data-display");
			foreach(e; t)
				ol.addChild("li", formatReturnValueAsHtml(e));
			return ol;
		}
	} else static assert(0, "bad return value for cgi call " ~ T.stringof);

	assert(0);
}

/++
	A web presenter is responsible for rendering things to HTML to be usable
	in a web browser.

	They are passed as template arguments to the base classes of [WebObject]

	FIXME
+/
class WebPresenter() {

}

/++
	The base class for the [dispatcher] function and object support.
+/
class WebObject(Helper = void) {
	Cgi cgi;
	void initialize(Cgi cgi) {
		this.cgi = cgi;
	}

	string script() {
		return `
		`;
	}

	string style() {
		return `
			:root {
				--mild-border: #ccc;
				--middle-border: #999;
				--accent-color: #e8e8e8;
				--sidebar-color: #f2f2f2;
			}
		` ~ genericFormStyling() ~ genericSiteStyling();
	}

	string genericFormStyling() {
		return `
			table.automatic-data-display {
				border-collapse: collapse;
				border: solid 1px var(--mild-border);
			}

			table.automatic-data-display td {
				vertical-align: top;
				border: solid 1px var(--mild-border);
				padding: 2px 4px;
			}

			table.automatic-data-display th {
				border: solid 1px var(--mild-border);
				border-bottom: solid 1px var(--middle-border);
				padding: 2px 4px;
			}

			ol.automatic-data-display {
				margin: 0px;
				list-style-position: inside;
				padding: 0px;
			}

			.automatic-form {
				max-width: 600px;
			}

			.form-field {
				margin: 0.5em;
				padding-left: 0.5em;
			}

			.label-text {
				display: block;
				font-weight: bold;
				margin-left: -0.5em;
			}

			.add-array-button {

			}
		`;
	}

	string genericSiteStyling() {
		return `
			* { box-sizing: border-box; }
			html, body { margin: 0px; }
			body {
				font-family: sans-serif;
			}
			#header {
				background: var(--accent-color);
				height: 64px;
			}
			#footer {
				background: var(--accent-color);
				height: 64px;
			}
			#main-site {
				display: flex;
			}
			#container {
				flex: 1 1 auto;
				order: 2;
				min-height: calc(100vh - 64px - 64px);
				padding: 4px;
				padding-left: 1em;
			}
			#sidebar {
				flex: 0 0 16em;
				order: 1;
				background: var(--sidebar-color);
			}
		`;
	}

	import arsd.dom;
	Element htmlContainer() {
		auto document = new Document(`<!DOCTYPE html>
<html>
<head>
	<title>D Application</title>
	<link rel="stylesheet" href="style.css" />
</head>
<body>
	<div id="header"></div>
	<div id="main-site">
		<div id="container"></div>
		<div id="sidebar"></div>
	</div>
	<div id="footer"></div>
	<script src="script.js"></script>
</body>
</html>`, true, true);

		return document.requireElementById("container");
	}
}

/++
	Serves a class' methods, as a kind of low-state RPC over the web. To be used with [dispatcher].

	Usage of this function will add a dependency on [arsd.dom] and [arsd.jsvar].

	FIXME: explain this better
+/
auto serveApi(T)(string urlPrefix) {
	assert(urlPrefix[$ - 1] == '/');

	import arsd.dom;
	import arsd.jsvar;

	static bool handler(string urlPrefix, Cgi cgi) {

		auto obj = new T();
		obj.initialize(cgi);

		switch(cgi.pathInfo[urlPrefix.length .. $]) {
			static foreach(methodName; __traits(derivedMembers, T)){{
			static if(is(typeof(__traits(getMember, T, methodName)) P == __parameters))
			{
				case urlify(methodName):
					switch(cgi.request("format", "html")) {
						case "html":
							auto container = obj.htmlContainer();
							try {
								auto ret = callFromCgi!(__traits(getMember, obj, methodName))(&__traits(getMember, obj, methodName), cgi);
								container.appendChild(formatReturnValueAsHtml(ret));
							} catch(MissingArgumentException mae) {
								container.appendChild(Element.make("p", "Argument `" ~ mae.argumentName ~ "` of type `" ~ mae.argumentType ~ "` is missing"));
								container.appendChild(createAutomaticFormForFunction!(__traits(getMember, obj, methodName))(&__traits(getMember, obj, methodName)));
							}
							cgi.write(container.parentDocument.toString(), true);
						break;
						case "json":
							auto ret = callFromCgi!(__traits(getMember, obj, methodName))(&__traits(getMember, obj, methodName), cgi);
							var json = ret;
							var envelope = var.emptyObject;
							envelope.success = true;
							envelope.result = json;
							envelope.error = null;
							cgi.setResponseContentType("application/json");
							cgi.write(envelope.toJson(), true);

						break;
						default:
					}
				return true;
			}
			}}
			case "script.js":
				cgi.setResponseContentType("text/javascript");
				cgi.gzipResponse = true;
				cgi.write(obj.script(), true);
				return true;
			case "style.css":
				cgi.setResponseContentType("text/css");
				cgi.gzipResponse = true;
				cgi.write(obj.style(), true);
				return true;
			default:
				return false;
		}
	
		assert(0);
	}
	return DispatcherDefinition!handler(urlPrefix, false);
}


	enum AccessCheck {
		allowed,
		denied,
		nonExistant,
	}

	enum Operation {
		show,
		create,
		replace,
		remove,
		update
	}

	enum UpdateResult {
		accessDenied,
		noSuchResource,
		success,
		failure,
		unnecessary
	}

	enum ValidationResult {
		valid,
		invalid
	}


/++
	The base of all REST objects, to be used with [serveRestObject] and [serveRestCollectionOf].
+/
class RestObject(Helper = void) : WebObject!Helper {

	import arsd.dom;
	import arsd.jsvar;

	/// Prepare the object to be shown.
	void show() {}
	/// ditto
	void show(string urlId) {
		load(urlId);
		show();
	}

	ValidationResult delegate(typeof(this)) validateFromReflection;
	Element delegate(typeof(this)) toHtmlFromReflection;
	var delegate(typeof(this)) toJsonFromReflection;

	/// Override this to provide access control to this object.
	AccessCheck accessCheck(string urlId, Operation operation) {
		return AccessCheck.allowed;
	}

	ValidationResult validate() {
		if(validateFromReflection !is null)
			return validateFromReflection(this);
		return ValidationResult.valid;
	}

	// The functions with more arguments are the low-level ones,
	// they forward to the ones with fewer arguments by default.

	// POST on a parent collection - this is called from a collection class after the members are updated
	/++
		Given a populated object, this creates a new entry. Returns the url identifier
		of the new object.
	+/
	string create(scope void delegate() applyChanges) {
		return null;
	}

	void replace() {
		save();
	}
	void replace(string urlId, scope void delegate() applyChanges) {
		load(urlId);
		applyChanges();
		replace();
	}

	void update(string[] fieldList) {
		save();
	}
	void update(string urlId, scope void delegate() applyChanges, string[] fieldList) {
		load(urlId);
		applyChanges();
		update(fieldList);
	}

	void remove() {}

	void remove(string urlId) {
		load(urlId);
		remove();
	}

	abstract void load(string urlId);
	abstract void save();

	Element toHtml() {
		if(toHtmlFromReflection)
			return toHtmlFromReflection(this);
		else
			assert(0);
	}

	var toJson() {
		if(toJsonFromReflection)
			return toJsonFromReflection(this);
		else
			assert(0);
	}

	/+
	auto structOf(this This) {

	}
	+/
}

/++
	Responsible for displaying stuff as HTML. You can put this into your own aggregate
	and override it. Use forwarding and specialization to customize it.
+/
mixin template Presenter() {

}

/++
	Base class for REST collections.
+/
class CollectionOf(Obj, Helper = void) : RestObject!(Helper) {
	/// You might subclass this and use the cgi object's query params
	/// to implement a search filter, for example.
	///
	/// FIXME: design a way to auto-generate that form
	/// (other than using the WebObject thing above lol
	// it'll prolly just be some searchParams UDA or maybe an enum.
	//
	// pagination too perhaps.
	//
	// and sorting too
	IndexResult index() { return IndexResult.init; }

	string[] sortableFields() { return null; }
	string[] searchableFields() { return null; }

	struct IndexResult {
		Obj[] results;

		string[] sortableFields;

		string previousPageIdentifier;
		string nextPageIdentifier;
		string firstPageIdentifier;
		string lastPageIdentifier;

		int numberOfPages;
	}

	override string create(scope void delegate() applyChanges) { assert(0); }
	override void load(string urlId) { assert(0); }
	override void save() { assert(0); }
	override void show() {
		index();
	}
	override void show(string urlId) {
		show();
	}

	/// Proxy POST requests (create calls) to the child collection
	alias PostProxy = Obj;
}

/++
	Serves a REST object, similar to a Ruby on Rails resource.

	You put data members in your class. cgi.d will automatically make something out of those.

	It will call your constructor with the ID from the URL. This may be null.
	It will then populate the data members from the request.
	It will then call a method, if present, telling what happened. You don't need to write these!
	It finally returns a reply.

	Your methods are passed a list of fields it actually set.

	The URL mapping - despite my general skepticism of the wisdom - matches up with what most REST
	APIs I have used seem to follow. (I REALLY want to put trailing slashes on it though. Works better
	with relative linking. But meh.)

	GET /items -> index. all values not set.
	GET /items/id -> get. only ID will be set, other params ignored.
	POST /items -> create. values set as given
	PUT /items/id -> replace. values set as given
		or POST /items/id with cgi.post["_method"] (thus urlencoded or multipart content-type) set to "PUT" to work around browser/html limitation
		a GET with cgi.get["_method"] (in the url) set to "PUT" will render a form.
	PATCH /items/id -> update. values set as given, list of changed fields passed
		or POST /items/id with cgi.post["_method"] == "PATCH"
	DELETE /items/id -> destroy. only ID guaranteed to be set
		or POST /items/id with cgi.post["_method"] == "DELETE"

	Following the stupid convention, there will never be a trailing slash here, and if it is there, it will
	redirect you away from it.

	API clients should set the `Accept` HTTP header to application/json or the cgi.get["_format"] = "json" var.

	I will also let you change the default, if you must.

	// One add-on is validation. You can issue a HTTP GET to a resource with _method = VALIDATE to check potential changes.

	You can define sub-resources on your object inside the object. These sub-resources are also REST objects
	that follow the same thing. They may be individual resources or collections themselves.

	Your class is expected to have at least the following methods:

	FIXME: i kinda wanna add a routes object to the initialize call

	create
		Create returns the new address on success, some code on failure.
	show
	index
	update
	remove

	You will want to be able to customize the HTTP, HTML, and JSON returns but generally shouldn't have to - the defaults
	should usually work. The returned JSON will include a field "href" on all returned objects along with "id". Or omething like that.

	Usage of this function will add a dependency on [arsd.dom] and [arsd.jsvar].

	NOT IMPLEMENTED


	Really, a collection is a resource with a bunch of subresources.

		GET /items
			index because it is GET on the top resource

		GET /items/foo
			item but different than items?

		class Items {

		}

	... but meh, a collection can be automated. not worth making it
	a separate thing, let's look at a real example. Users has many
	items and a virtual one, /users/current.

	the individual users have properties and two sub-resources:
	session, which is just one, and comments, a collection.

	class User : RestObject!() { // no parent
		int id;
		string name;

		// the default implementations of the urlId ones is to call load(that_id) then call the arg-less one.
		// but you can override them to do it differently.

		// any member which is of type RestObject can be linked automatically via href btw.

		void show() {}
		void show(string urlId) {} // automated! GET of this specific thing
		void create() {} // POST on a parent collection - this is called from a collection class after the members are updated
		void replace(string urlId) {} // this is the PUT; really, it just updates all fields.
		void update(string urlId, string[] fieldList) {} // PATCH, it updates some fields.
		void remove(string urlId) {} // DELETE

		void load(string urlId) {} // the default implementation of show() populates the id, then

		this() {}

		mixin Subresource!Session;
		mixin Subresource!Comment;
	}

	class Session : RestObject!() {
		// the parent object may not be fully constructed/loaded
		this(User parent) {}

	}

	class Comment : CollectionOf!Comment {
		this(User parent) {}
	}

	class Users : CollectionOf!User {
		// but you don't strictly need ANYTHING on a collection; it will just... collect. Implement the subobjects.
		void index() {} // GET on this specific thing; just like show really, just different name for the different semantics.
		User create() {} // You MAY implement this, but the default is to create a new object, populate it from args, and then call create() on the child
	}

+/
auto serveRestObject(T)(string urlPrefix) {
	assert(urlPrefix[$ - 1] != '/', "Do NOT use a trailing slash on REST objects.");
	static bool handler(string urlPrefix, Cgi cgi) {
		string url = cgi.pathInfo[urlPrefix.length .. $];

		if(url.length && url[$ - 1] == '/') {
			// remove the final slash...
			cgi.setResponseLocation(cgi.scriptName ~ cgi.pathInfo[0 .. $ - 1]);
			return true;
		}

		return restObjectServeHandler!T(cgi, url);

	}
	return DispatcherDefinition!handler(urlPrefix, false);
}

/// Convenience method for serving a collection. It will be named the same
/// as type T, just with an s at the end. If you need any further, just
/// write the class yourself.
auto serveRestCollectionOf(T)(string urlPrefix) {
	mixin(`static class `~T.stringof~`s : CollectionOf!(T) {}`);
	return serveRestObject!(mixin(T.stringof ~ "s"))(urlPrefix);
}

bool restObjectServeHandler(T)(Cgi cgi, string url) {
	string urlId = null;
	if(url.length && url[0] == '/') {
		// asking for a subobject
		urlId = url[1 .. $];
		foreach(idx, ch; urlId) {
			if(ch == '/') {
				urlId = urlId[0 .. idx];
				break;
			}
		}
	}

	// FIXME handle other subresources

	static if(is(T : CollectionOf!(C, P), C, P)) {
		if(urlId !is null) {
			return restObjectServeHandler!C(cgi, url); // FIXME?  urlId);
		}
	}

	// FIXME: support precondition failed, if-modified-since, expectation failed, etc.

	auto obj = new T();
	obj.toHtmlFromReflection = delegate(t) {
		import arsd.dom;
		auto div = Element.make("div");
		div.addClass("Dclass_" ~ T.stringof);
		div.dataset.url = urlId;
		bool first = true;
		static foreach(idx, memberName; __traits(derivedMembers, T))
		static if(__traits(compiles, __traits(getMember, obj, memberName).offsetof)) {
			if(!first) div.addChild("br"); else first = false;
			div.appendChild(formatReturnValueAsHtml(__traits(getMember, obj, memberName)));
		}
		return div;
	};
	obj.toJsonFromReflection = delegate(t) {
		import arsd.jsvar;
		var v = var.emptyObject();
		static foreach(idx, memberName; __traits(derivedMembers, T))
		static if(__traits(compiles, __traits(getMember, obj, memberName).offsetof)) {
			v[memberName] = __traits(getMember, obj, memberName);
		}
		return v;
	};
	obj.validateFromReflection = delegate(t) {
		// FIXME
		return ValidationResult.valid;
	};
	obj.initialize(cgi);
	// FIXME: populate reflection info delegates


	// FIXME: I am not happy with this.
	switch(urlId) {
		case "script.js":
			cgi.setResponseContentType("text/javascript");
			cgi.gzipResponse = true;
			cgi.write(obj.script(), true);
			return true;
		case "style.css":
			cgi.setResponseContentType("text/css");
			cgi.gzipResponse = true;
			cgi.write(obj.style(), true);
			return true;
		default:
			// intentionally blank
	}




	static void applyChangesTemplate(Obj)(Cgi cgi, Obj obj) {
		static foreach(idx, memberName; __traits(derivedMembers, Obj))
		static if(__traits(compiles, __traits(getMember, obj, memberName).offsetof)) {
			__traits(getMember, obj, memberName) = cgi.request(memberName, __traits(getMember, obj, memberName));
		}
	}
	void applyChanges() {
		applyChangesTemplate(cgi, obj);
	}

	string[] modifiedList;

	void writeObject(bool addFormLinks) {
		if(cgi.request("format") == "json") {
			cgi.setResponseContentType("application/json");
			cgi.write(obj.toJson().toString, true);
		} else {
			auto container = obj.htmlContainer();
			if(addFormLinks) {
				static if(is(T : CollectionOf!(C, P), C, P))
				container.appendHtml(`
					<form>
						<button type="submit" name="_method" value="POST">Create New</button>
					</form>
				`);
				else
				container.appendHtml(`
					<form>
						<button type="submit" name="_method" value="PATCH">Edit</button>
						<button type="submit" name="_method" value="DELETE">Delete</button>
					</form>
				`);
			}
			container.appendChild(obj.toHtml());
			cgi.write(container.parentDocument.toString, true);
		}
	}

	// FIXME: I think I need a set type in here....
	// it will be nice to pass sets of members.

	switch(cgi.requestMethod) {
		case Cgi.RequestMethod.GET:
			// I could prolly use template this parameters in the implementation above for some reflection stuff.
			// sure, it doesn't automatically work in subclasses... but I instantiate here anyway...

			// automatic forms here for usable basic auto site from browser.
			// even if the format is json, it could actually send out the links and formats, but really there i'ma be meh.
			switch(cgi.request("_method", "GET")) {
				case "GET":
					static if(is(T : CollectionOf!(C, P), C, P)) {
						auto results = obj.index();
						if(cgi.request("format", "html") == "html") {
							auto container = obj.htmlContainer();
							auto html = formatReturnValueAsHtml(results.results);
							container.appendHtml(`
								<form>
									<button type="submit" name="_method" value="POST">Create New</button>
								</form>
							`);

							container.appendChild(html);
							cgi.write(container.parentDocument.toString, true);
						} else {
							cgi.setResponseContentType("application/json");
							import arsd.jsvar;
							var json = var.emptyArray;
							foreach(r; results.results) {
								var o = var.emptyObject;
								static foreach(idx, memberName; __traits(derivedMembers, typeof(r)))
								static if(__traits(compiles, __traits(getMember, r, memberName).offsetof)) {
									o[memberName] = __traits(getMember, r, memberName);
								}

								json ~= o;
							}
							cgi.write(json.toJson(), true);
						}
					} else {
						obj.show(urlId);
						writeObject(true);
					}
				break;
				case "PATCH":
					obj.load(urlId);
				goto case;
				case "PUT":
				case "POST":
					// an editing form for the object
					auto container = obj.htmlContainer();
					static if(__traits(compiles, () { auto o = new obj.PostProxy(); })) {
						auto form = (cgi.request("_method") == "POST") ? createAutomaticFormForObject(new obj.PostProxy()) : createAutomaticFormForObject(obj);
					} else {
						auto form = createAutomaticFormForObject(obj);
					}
					form.attrs.method = "POST";
					form.setValue("_method", cgi.request("_method", "GET"));
					container.appendChild(form);
					cgi.write(container.parentDocument.toString(), true);
				break;
				case "DELETE":
					// FIXME: a delete form for the object (can be phrased "are you sure?")
					auto container = obj.htmlContainer();
					container.appendHtml(`
						<form method="POST">
							Are you sure you want to delete this item?
							<input type="hidden" name="_method" value="DELETE" />
							<input type="submit" value="Yes, Delete It" />
						</form>

					`);
					cgi.write(container.parentDocument.toString(), true);
				break;
				default:
					cgi.write("bad method\n", true);
			}
		break;
		case Cgi.RequestMethod.POST:
			// this is to allow compatibility with HTML forms
			switch(cgi.request("_method", "POST")) {
				case "PUT":
					goto PUT;
				case "PATCH":
					goto PATCH;
				case "DELETE":
					goto DELETE;
				case "POST":
					static if(__traits(compiles, () { auto o = new obj.PostProxy(); })) {
						auto p = new obj.PostProxy();
						void specialApplyChanges() {
							applyChangesTemplate(cgi, p);
						}
						string n = p.create(&specialApplyChanges);
					} else {
						string n = obj.create(&applyChanges);
					}

					auto newUrl = cgi.scriptName ~ cgi.pathInfo ~ "/" ~ n;
					cgi.setResponseLocation(newUrl);
					cgi.setResponseStatus("201 Created");
					cgi.write(`The object has been created.`);
				break;
				default:
					cgi.write("bad method\n", true);
			}
			// FIXME this should be valid on the collection, but not the child....
			// 303 See Other
		break;
		case Cgi.RequestMethod.PUT:
		PUT:
			obj.replace(urlId, &applyChanges);
			writeObject(false);
		break;
		case Cgi.RequestMethod.PATCH:
		PATCH:
			obj.update(urlId, &applyChanges, modifiedList);
			writeObject(false);
		break;
		case Cgi.RequestMethod.DELETE:
		DELETE:
			obj.remove(urlId);
			cgi.setResponseStatus("204 No Content");
		break;
		default:
			// FIXME: OPTIONS, HEAD
	}

	return true;
}

/+
struct SetOfFields(T) {
	private void[0][string] storage;
	void set(string what) {
		//storage[what] = 
	}
	void unset(string what) {}
	void setAll() {}
	void unsetAll() {}
	bool isPresent(string what) { return false; }
}
+/

/+
enum readonly;
enum hideonindex;
+/

/++
	Serves a static file. To be used with [dispatcher].
+/
auto serveStaticFile(string urlPrefix, string filename = null, string contentType = null) {
	if(filename is null)
		filename = urlPrefix[1 .. $];
	if(contentType is null) {

	}
	static bool handler(string urlPrefix, Cgi cgi) {
		//cgi.setResponseContentType(contentType);
		//cgi.write(std.file.read(filename), true);
		cgi.write(std.file.read(urlPrefix[1 .. $]), true);
		return true;
	}
	return DispatcherDefinition!handler(urlPrefix, true);
}

auto serveRedirect(string urlPrefix, string redirectTo) {
	// FIXME
}

/+
/++
	See [serveStaticFile] if you want to serve a file off disk.
+/
auto serveStaticData(string urlPrefix, const(void)[] data, string contentType) {

}
+/

/++
	A URL dispatcher.

	---
	if(cgi.dispatcher!(
		"/api/".serveApi!MyApiClass,
		"/objects/lol".serveRestObject!MyRestObject,
		"/file.js".serveStaticFile,
	)) return;
	---
+/
bool dispatcher(definitions...)(Cgi cgi) {
	// I can prolly make this more efficient later but meh.
	foreach(definition; definitions) {
		if(definition.rejectFurther) {
			if(cgi.pathInfo == definition.urlPrefix) {
				auto ret = definition.handler(definition.urlPrefix, cgi);
				if(ret)
					return true;
			}
		} else if(cgi.pathInfo.startsWith(definition.urlPrefix)) {
			auto ret = definition.handler(definition.urlPrefix, cgi);
			if(ret)
				return true;
		}
	}
	return false;
}

/+
/++
	This is the beginnings of my web.d 2.0 - it dispatches web requests to a class object.

	It relies on jsvar.d and dom.d.


	You can get javascript out of it to call. The generated functions need to look
	like

	function name(a,b,c,d,e) {
		return _call("name", {"realName":a,"sds":b});
	}

	And _call returns an object you can call or set up or whatever.
+/
bool apiDispatcher()(Cgi cgi) {
	import arsd.jsvar;
	import arsd.dom;
}
+/
/*
Copyright: Adam D. Ruppe, 2008 - 2019
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe

	Copyright Adam D. Ruppe 2008 - 2019.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
	http://www.boost.org/LICENSE_1_0.txt)
*/
