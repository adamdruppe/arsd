// FIXME: if an exception is thrown, we shouldn't necessarily cache...
/++
	Provides a uniform server-side API for CGI, FastCGI, SCGI, and HTTP web applications.

	---
	import arsd.cgi;

	// Instead of writing your own main(), you should write a function
	// that takes a Cgi param, and use mixin GenericMain
	// for maximum compatibility with different web servers.
	void hello(Cgi cgi) {
		cgi.write("Hello, world!");
	}

	mixin GenericMain!hello;
	---

	Concepts:
		Input: get, post, request(), files, cookies, pathInfo, requestMethod, and HTTP headers (headers, userAgent, referrer, accept, authorization, lastEventId
		Output: cgi.write(), cgi.header(), cgi.setResponseStatus, cgi.setResponseContentType, gzipResponse
		Cookies: setCookie, clearCookie, cookie, cookies
		Caching: cgi.setResponseExpires, cgi.updateResponseExpires, cgi.setCache
		Redirections: cgi.setResponseLocation
		Other Information: remoteAddress, https, port, scriptName, requestUri, getCurrentCompleteUri, onRequestBodyDataReceived
		Overriding behavior: handleIncomingDataChunk, prepareForIncomingDataChunks, cleanUpPostDataState

		Installing: Apache, IIS, CGI, FastCGI, SCGI, embedded HTTPD (not recommended for production use)

	Guide_for_PHP_users:
		If you are coming from PHP, here's a quick guide to help you get started:

		$_GET["var"] == cgi.get["var"]
		$_POST["var"] == cgi.post["var"]
		$_COOKIE["var"] == cgi.cookies["var"]

		In PHP, you can give a form element a name like "something[]", and then
		$_POST["something"] gives an array. In D, you can use whatever name
		you want, and access an array of values with the cgi.getArray["name"] and
		cgi.postArray["name"] members.

		echo("hello"); == cgi.write("hello");

		$_SERVER["REMOTE_ADDR"] == cgi.remoteAddress
		$_SERVER["HTTP_HOST"] == cgi.host

	See_Also:

	You may also want to see dom.d, web.d, and html.d for more code for making
	web applications. database.d, mysql.d, postgres.d, and sqlite.d can help in
	accessing databases.

	If you are looking to access a web application via HTTP, try curl.d.
+/
module arsd.cgi;

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

	import std.c.windows.windows;
static:

	static this() {
		// Set stdin to binary mode
		setmode(std.stdio.stdin.fileno(), 0x8000);
	}

	T[] rawRead(T)(T[] buf) {
		uint bytesRead;
		auto result = ReadFile(GetStdHandle(STD_INPUT_HANDLE), buf.ptr, buf.length * T.sizeof, &bytesRead, null);

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
		// this is an extension for when the method is not specified and you want to assume
		CommandLine }



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

*/

	/** Initializes it with command line arguments (for easy testing) */
	this(string[] args) {
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

		foreach(arg; args[1 .. $]) {
			if(arg.startsWith("--")) {
				nextArgIs = arg[2 .. $];
			} else if(nextArgIs.length) {
				switch(nextArgIs) {
					case "cookie":
						auto info = breakUp(arg);
						if(_cookie.length)
							_cookie ~= "; ";
						_cookie ~= std.uri.encodeComponent(info[0]) ~ "=" ~ std.uri.encodeComponent(info[1]);
					break;
					case "port":
						port = to!int(arg);
					break;
					case "referrer":
						referrer = arg;
					break;
					case "remote-address":
						remoteAddress = arg;
					break;
					case "user-agent":
						userAgent = arg;
					break;
					case "authorization":
						authorization = arg;
					break;
					case "userpass":
						authorization = "Basic " ~ Base64.encode(cast(immutable(ubyte)[]) (arg)).idup;
					break;
					case "accept":
						accept = arg;
					break;
					case "last-event-id":
						lastEventId = arg;
					break;
					case "https":
						if(arg == "yes")
							https = true;
					break;
					case "header":
						string thing, other;
						auto idx = arg.indexOf(":");
						if(idx == -1)
							throw new Exception("need a colon in a http header");
						thing = arg[0 .. idx];
						other = arg[idx + 1.. $];
						_headers[thing.strip.toLower()] = other.strip;
					break;
					case "host":
						host = arg;
					break;
					default:
						// skip, we don't know it but that's ok, it might be used elsewhere so no error
				}

				nextArgIs = null;
			} else if(lookingForMethod) {
				lookingForMethod = false;
				lookingForUri = true;

				if(arg.toLower() == "commandline")
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
					queryString = arg[idx + 1 .. $];
				}
			} else {
				// it is an argument of some sort
				if(requestMethod == Cgi.RequestMethod.POST) {
					auto parts = breakUp(arg);
					_post[parts[0]] ~= parts[1];
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
		getArray = cast(immutable) decodeVariables(queryString);
		get = keepLastOf(getArray);

		postArray = cast(immutable) _post;
		post = keepLastOf(_post);

		// FIXME
		filesArray = null;
		files = null;

		isCalledWithCommandLineArguments = true;
	}

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
		isCalledWithCommandLineArguments = false;
		rawDataOutput = _rawDataOutput;
		flushDelegate = _flush;
		auto getenv = delegate string(string var) {
			if(env is null)
				return .getenv(var);
			auto e = var in env;
			if(e is null)
				return null;
			return *e;
		};

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


		get = getGetVariables();
		auto ugh = decodeVariables(queryString);
		getArray = assumeUnique(ugh);


		// NOTE: on shitpache, you need to specifically forward this
		authorization = getenv("HTTP_AUTHORIZATION");
		// this is a hack because Apache is a shitload of fuck and
		// refuses to send the real header to us. Compatible
		// programs should send both the standard and X- versions

		// NOTE: if you have access to .htaccess or httpd.conf, you can make this
		// unnecessary with mod_rewrite, so it is commented

		//if(authorization.length == 0) // if the std is there, use it
		//	authorization = getenv("HTTP_X_AUTHORIZATION");

		if(getenv("SERVER_PORT").length)
			port = to!int(getenv("SERVER_PORT"));
		else
			port = 0; // this was probably called from the command line

		auto ae = getenv("HTTP_ACCEPT_ENCODING");
		if(ae.length && ae.indexOf("gzip") != -1)
			acceptsGzip = true;

		accept = getenv("HTTP_ACCEPT");
		lastEventId = getenv("HTTP_LAST_EVENT_ID");

		auto ka = getenv("HTTP_CONNECTION");
		if(ka.length && ka.toLower().indexOf("keep-alive") != -1)
			keepAliveRequested = true;

		auto rm = getenv("REQUEST_METHOD");
		if(rm.length)
			requestMethod = to!RequestMethod(getenv("REQUEST_METHOD"));
		else
			requestMethod = RequestMethod.CommandLine;

						// FIXME: hack on REDIRECT_HTTPS; this is there because the work app uses mod_rewrite which loses the https flag! So I set it with [E=HTTPS=%HTTPS] or whatever but then it gets translated to here so i want it to still work. This is arguably wrong but meh.
		https = (getenv("HTTPS") == "on" || getenv("REDIRECT_HTTPS") == "on");

		// FIXME: DOCUMENT_ROOT?

		// FIXME: what about PUT?
		if(requestMethod == RequestMethod.POST) {
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
				cleanUpPostDataState();
			}

			version(preserveData)
				originalPostData = data;
		}
		// fixme: remote_user script name
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

			ulong expectedLength;
			ulong contentConsumed;
			immutable(ubyte)[] buffer;

			// multipart parsing state
			int whatDoWeWant;
			bool weHaveAPart;
			string[] thisOnesHeaders;
			immutable(ubyte)[] thisOnesData;

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

		if(pps.contentType == "application/x-www-form-urlencoded") {
			pps.isMultipart = false;
		} else if(pps.contentType == "multipart/form-data") {
			pps.isMultipart = true;
			enforce(pps.boundary.length, "no boundary");
		} else {
			// FIXME: should set a http error code too
			throw new Exception("unknown request content type");
		}
	}

	// handles streaming POST data. If you handle some other content type, you should
	// override this. If the data isn't the content type you want, you ought to call
	// super.handleIncomingDataChunk so regular forms and files still work.

	// FIXME: I do some copying in here that I'm pretty sure is unnecessary, and the
	// file stuff I'm sure is inefficient. But, my guess is the real bottleneck is network
	// input anyway, so I'm not going to get too worked up about it right now.
	protected void handleIncomingDataChunk(const(ubyte)[] chunk) {
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
				} else
					pps._post[pps.piece.name] ~= cast(string) pps.piece.content;

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
			// application/x-www-form-urlencoded

				// not using maxContentLength because that might be cranked up to allow
				// large file uploads. We can handle them, but a huge post[] isn't any good.
			if(pps.buffer.length + chunk.length > 8 * 1024 * 1024) // surely this is plenty big enough
				throw new Exception("wtf is up with such a gigantic form submission????");

			pps.buffer ~= chunk;
			// simple handling, but it works... until someone bombs us with gigabytes of crap at least...
			if(pps.buffer.length == pps.expectedLength)
				pps._post = decodeVariables(cast(string) pps.buffer);
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

		NOTE: If you are behind a reverse proxy, the values here might not be what you expect.... FIXME somehow.

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


		int headerNumber = 0;
		foreach(line; al.splitter(inputData.front()[0 .. idx], "\r\n"))
		if(line.length) {
			headerNumber++;
			auto header = cast(string) line.idup;
			if(headerNumber == 1) {
				// request line
				auto parts = header.split(" ");
				requestMethod = to!RequestMethod(parts[0]);
				requestUri = parts[1];

				scriptName = requestUri[0 .. pathInfoStarts];

				auto question = requestUri.indexOf("?");
				if(question == -1) {
					queryString = "";
					pathInfo = requestUri[pathInfoStarts..$];
				} else {
					queryString = requestUri[question+1..$];
					pathInfo = requestUri[pathInfoStarts..question];
				}

				get = getGetVariables();
				auto ugh = decodeVariables(queryString);
				getArray = assumeUnique(ugh);

				if(header.indexOf("HTTP/1.0") != -1) {
					http10 = true;
					autoBuffer = true;
					if(closeConnection)
						*closeConnection = true;
				}
			} else {
				// other header
				auto colon = header.indexOf(":");
				if(colon == -1)
					throw new Exception("HTTP headers should have a colon!");
				string name = header[0..colon].toLower;
				string value = header[colon+2..$]; // skip the colon and the space

				requestHeadersHere[name] = value;

				switch(name) {
					case "accept":
						accept = value;
					break;
					case "connection":
						if(value == "close" && closeConnection)
							*closeConnection = true;
						if(value.toLower().indexOf("keep-alive") != -1)
							keepAliveRequested = true;
					break;
					case "transfer-encoding":
						if(value == "chunked")
							isChunked = true;
					break;
					case "last-event-id":
						lastEventId = value;
					break;
					case "authorization":
						authorization = value;
					break;
					case "content-type":
						contentType = value;
					break;
					case "content-length":
						contentLength = to!size_t(value);
					break;
					case "host":
						host = value;
					break;
					case "accept-encoding":
						if(value.indexOf("gzip") != -1)
							acceptsGzip = true;
					break;
					case "user-agent":
						userAgent = value;
					break;
					case "referer":
						referrer = value;
					break;
					case "cookie":
						cookie ~= value;
					break;
					default:
						// ignore it
				}

			}
		}

		inputData.consume(idx + 4);
		// done

		requestHeaders = assumeUnique(requestHeadersHere);

		cookiesArray = getCookieArray();
		cookies = keepLastOf(cookiesArray);

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
			foreach(dataChunk; dataByChunk)
				handleIncomingDataChunk(dataChunk);
			postArray = assumeUnique(pps._post);
			filesArray = assumeUnique(pps._files);
			files = keepLastOf(filesArray);
			post = keepLastOf(postArray);
			cleanUpPostDataState();
		}
	}

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

	// this function only exists because of the with_cgi_packed thing, which is
	// a filthy hack I put in here for a work app. Which still depends on it, so it
	// stays for now. But I want to remove it.
	private immutable(string[string]) getGetVariables() {
		if(queryString.length) {
			auto _get = decodeVariablesSingle(queryString);

			// Some sites are shit and don't let you handle multiple parameters.
			// If so, compile this in and encode it as a single parameter
			version(with_cgi_packed) {
				auto idx = pathInfo.indexOf("PACKED");
				if(idx != -1) {
					auto pi = pathInfo[idx + "PACKED".length .. $];

					auto _unpacked = decodeVariables(
						cast(string) base64UrlDecode(pi));

					foreach(k, v; _unpacked)
						_get[k] = v[$-1];
					// possible problem: it used to cut PACKED off the path info
					// but it doesn't now. I want to kill this crap anyway though.
				}

				if("arsd_packed_data" in getArray) {
					auto _unpacked = decodeVariables(
						cast(string) base64UrlDecode(getArray["arsd_packed_data"][0]));

					foreach(k, v; _unpacked)
						_get[k] = v[$-1];
				}
			}

			return assumeUnique(_get);
		}

		return null;
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
			port == defaultPort ? "" : ":" ~ to!string(port),
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
		string cookie = name ~ "=";
		cookie ~= data;
		if(path !is null)
			cookie ~= "; path=" ~ path;
		// FIXME: should I just be using max-age here? (also in cache below)
		if(expiresIn != 0)
			cookie ~= "; expires=" ~ printDate(cast(DateTime) Clock.currTime + dur!"msecs"(expiresIn));
		if(domain !is null)
			cookie ~= "; domain=" ~ domain;
		if(secure == true)
			cookie ~= "; Secure";
		if(httpOnly == true )
			cookie ~= "; HttpOnly";

		responseCookies ~= cookie;
	}
	private string[] responseCookies;

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
		if(nph) { // we're responsible for setting the date too according to http 1.1
			hd ~= "Date: " ~ printDate(cast(DateTime) Clock.currTime);
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

		if(customHeaders !is null)
			hd ~= customHeaders;

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
						rawDataOutput(makeChunk(cast(const(ubyte)[]) t));
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

	/* Internal state flags */
	private bool outputtedResponseData;
	private bool noCache = true;

	/** What follows is data gotten from the HTTP request. It is all fully immutable,
	    partially because it logically is (your code doesn't change what the user requested...)
	    and partially because I hate how bad programs in PHP change those superglobals to do
	    all kinds of hard to follow ugliness. I don't want that to ever happen in D.

	    For some of these, you'll want to refer to the http or cgi specs for more details.
	*/
	immutable(string[string]) requestHeaders; /// All the raw headers in the request as name/value pairs. The name is stored as all lower case, but otherwise the same as it is in HTTP; words separated by dashes. For example, "cookie" or "accept-encoding". Many HTTP headers have specialized variables below for more convenience and static name checking; you should generally try to use them.

	immutable(char[]) host; 	/// The hostname in the request. If one program serves multiple domains, you can use this to differentiate between them.
	immutable(char[]) userAgent; 	/// The browser's user-agent string. Can be used to identify the browser.
	immutable(char[]) pathInfo; 	/// This is any stuff sent after your program's name on the url, but before the query string. For example, suppose your program is named "app". If the user goes to site.com/app, pathInfo is empty. But, he can also go to site.com/app/some/sub/path; treating your program like a virtual folder. In this case, pathInfo == "/some/sub/path".
	immutable(char[]) scriptName;   /// The full base path of your program, as seen by the user. If your program is located at site.com/programs/apps, scriptName == "/programs/apps".
	immutable(char[]) authorization; /// The full authorization string from the header, undigested. Useful for implementing auth schemes such as OAuth 1.0. Note that some web servers do not forward this to the app without taking extra steps. See requireBasicAuth's comment for more info.
	immutable(char[]) accept; 	/// The HTTP accept header is the user agent telling what content types it is willing to accept. This is often */*; they accept everything, so it's not terribly useful. (The similar sounding Accept-Encoding header is handled automatically for chunking and gzipping. Simply set gzipResponse = true and cgi.d handles the details, zipping if the user's browser is willing to accept it.
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
		import std.regex;
		// from RFC 3986
		enum ctr = ctRegex!r"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?";
		auto m = match(uri, ctr);
		if(m) {
			scheme = m.captures[2];
			auto authority = m.captures[4];

			auto idx = authority.indexOf("@");
			if(idx != -1) {
				userinfo = authority[0 .. idx];
				authority = authority[idx + 1 .. $];
			}

			idx = authority.indexOf(":");
			if(idx == -1) {
				port = 0; // 0 means not specified; we should use the default for the scheme
				host = authority;
			} else {
				host = authority[0 .. idx];
				port = to!int(authority[idx + 1 .. $]);
			}

			path = m.captures[5];
			query = m.captures[7];
			fragment = m.captures[9];
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

		url = Uri("#anchor"); // everything should remain the same except the anchor

		url = Uri("//example.com"); // same protocol, but different server. the path here should be blank.

		url = Uri("//example.com/example.html"); // same protocol, but different server and path

		url = Uri("http://example.com/test.html"); // completely absolute link should never be modified

		url = Uri("http://example.com"); // completely absolute link should never be modified, even if it has no path

		// FIXME: add something for port too
	}
}


/*
	for session, see web.d
*/

/// breaks down a url encoded string
string[][string] decodeVariables(string data, string separator = "&") {
	auto vars = data.split(separator);
	string[][string] _get;
	foreach(var; vars) {
		auto equal = var.indexOf("=");
		if(equal == -1) {
			_get[decodeComponent(var)] ~= "";
		} else {
			//_get[decodeComponent(var[0..equal])] ~= decodeComponent(var[equal + 1 .. $].replace("+", " "));
			// stupid + -> space conversion.
			_get[decodeComponent(var[0..equal].replace("+", " "))] ~= decodeComponent(var[equal + 1 .. $].replace("+", " "));
		}
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


// http helper functions

// for chunked responses (which embedded http does whenever possible)
const(ubyte)[] makeChunk(const(ubyte)[] data) {
	const(ubyte)[] ret;

	ret = cast(const(ubyte)[]) toHex(cast(int) data.length);
	ret ~= cast(const(ubyte)[]) "\r\n";
	ret ~= data;
	ret ~= cast(const(ubyte)[]) "\r\n";

	return ret;
}

string toHex(int num) {
	string ret;
	while(num) {
		int v = num % 16;
		num /= 16;
		char d = cast(char) ((v < 10) ? v + '0' : (v-10) + 'a');
		ret ~= d;
	}

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
		version(netman_httpd) {
			import arsd.httpd;
			// what about forwarding the other constructor args?
			// this probably needs a whole redoing...
			serveHttp!CustomCgi(&fun, listeningPort(8080));//5005);
			return;
		} else
		version(embedded_httpd) {
			auto manager = new ListeningConnectionManager(listeningPort(8085));
			foreach(connection; manager) {
				scope(failure) {
					// catch all for other errors
					sendAll(connection, plainHttpError(false, "500 Internal Server Error", null));
					connection.close();
				}
				bool closeConnection;
				auto ir = new BufferedInputRange(connection);

				while(!ir.empty) {
					Cgi cgi;
					try {
						cgi = new CustomCgi(ir, &closeConnection);
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
					}
				}
			}
		} else
		version(scgi) {
			import std.exception;
			import al = std.algorithm;
			auto manager = new ListeningConnectionManager(listeningPort(4000));

			// this threads...
			foreach(connection; manager) {
				// and now we can buffer
				scope(failure)
					connection.close();

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
					}

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
				} catch(Throwable t) {
					sendAll(connection, plainHttpError(true, "400 Bad Request", t));
					connection.close();
					continue; // this connection is dead
				}
				assert(cgi !is null);
				scope(exit) cgi.dispose();
				try {
					fun(cgi);
					cgi.close();
				} catch(Throwable t) {
					// no std err
					if(!handleException(cgi, t)) {
						connection.close();
						continue;
					}
				}
			}
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
			while(FCGX_Accept(&input, &output, &error, &env) >= 0) {
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
					continue;
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
						continue;
				}
			}
		} else {
			// standard CGI is the default version
			Cgi cgi;
			try {
				cgi = new CustomCgi(maxContentLength);
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


version(with_cgi_packed) {
// This is temporary until Phobos supports base64
immutable(ubyte)[] base64UrlDecode(string e) {
	string encoded = e.idup;
	while (encoded.length % 4) {
		encoded ~= "="; // add padding
	}

	// convert base64 URL to standard base 64
	encoded = encoded.replace("-", "+");
	encoded = encoded.replace("_", "/");

	return cast(immutable(ubyte)[]) Base64.decode(encoded);
}
	// should be set as arsd_packed_data
	string packedDataEncode(in string[string] variables) {
		string result;

		bool outputted = false;
		foreach(k, v; variables) {
			if(outputted)
				result ~= "&";
			else
				outputted = true;

			result ~= std.uri.encodeComponent(k) ~ "=" ~ std.uri.encodeComponent(v);
		}

		result = cast(string) Base64.encode(cast(ubyte[]) result);

		// url variant
		result.replace("=", "");
		result.replace("+", "-");
		result.replace("/", "_");

		return result;
	}
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

		alias char** FCGX_ParamArray;

		c_int FCGX_Accept(FCGX_Stream** stdin, FCGX_Stream** stdout, FCGX_Stream** stderr, FCGX_ParamArray* envp);
		c_int FCGX_GetChar(FCGX_Stream* stream);
		c_int FCGX_PutStr(const ubyte* str, c_int n, FCGX_Stream* stream);
		int FCGX_HasSeenEOF(FCGX_Stream* stream);
		c_int FCGX_FFlush(FCGX_Stream *stream);
	}
}


/* This might go int a separate module eventually. It is a network input helper class. */

import std.socket;

// it is a class primarily for reference semantics
// I might change this interface
class BufferedInputRange {
	this(Socket source, ubyte[] buffer = null) {
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
	void popFront(size_t maxBytesToConsume = 0 /*size_t.max*/, size_t minBytesToSettleFor = 0) {
		if(sourceClosed)
			throw new Exception("can't get any more data from a closed source");
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
			auto ret = source.receive(freeSpace);
			if(ret == Socket.ERROR)
				throw new Exception("uh oh"); // FIXME
			if(ret == 0) {
				sourceClosed = true;
				return;
			}

			view = underlyingBuffer[underlyingBuffer.ptr - view.ptr .. view.length + ret];
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
		if(view.length == 0)
			view = underlyingBuffer[0 .. 0]; // go ahead and reuse the beginning
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

/**
	To use this thing:

	auto manager = new ListeningConnectionManager(80);
	foreach(connection; manager) {
		// work with connection
		// note: each connection may get its own thread, so this is a kind of concurrent foreach.

		// this can have implications if you access local variables in the function, as they are
		// implicitly shared!

		// FIXME: break does not work
	}


	I suggest you use BufferedInputRange(connection) to handle the input. As a packet
	comes in, you will get control. You can just continue; though to fetch more.


	FIXME: should I offer an event based async thing like netman did too? Yeah, probably.
*/
class ListeningConnectionManager {
	this(ushort port) {
		listener = new TcpSocket();
		listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		listener.bind(new InternetAddress(port));
		listener.listen(10);
	}

	Socket listener;

	bool running;
	void quit() {
		running = false;
	}

	int opApply(scope CMT dg) {
		running = true;
		shared(int) loopBroken;

		while(!loopBroken && running) {
			auto sn = listener.accept();
			try {
				auto thread = new ConnectionThread(sn, &loopBroken, dg);
				thread.start();
				// loopBroken = dg(sn);
			} catch(Exception e) {
				// if a connection goes wrong, we want to just say no, but try to carry on unless it is an Error of some sort (in which case, we'll die. You might want an external helper program to revive the server when it dies)
				sn.close();
			}
		}

		return loopBroken;
	}
}

// helper function to send a lot to a socket. Since this blocks for the buffer (possibly several times), you should probably call it in a separate thread or something.
void sendAll(Socket s, const(void)[] data) {
	if(data.length == 0) return;
	ptrdiff_t amount;
	do {
		amount = s.send(data);
		if(amount == Socket.ERROR)
			throw new Exception("wtf in send: " ~ lastSocketError);
		assert(amount > 0);
		data = data[amount .. $];
	} while(data.length);
}

alias int delegate(Socket) CMT;

import core.thread;
class ConnectionThread : Thread {
	this(Socket s, shared(int)* breakSignifier, CMT dg) {
		this.s = s;
	 	this.breakSignifier = breakSignifier;
		this.dg = dg;
		super(&run);
	}

	void run() {
		scope(exit) {
			// I don't want to double close it, and it does this on close() according to source
			// might be fragile, but meh
			if(s.handle() != socket_t.init)
				s.close();
		}
		if(auto result = dg(s)) {
			*breakSignifier = result;
		}
	}

	Socket s;
	shared(int)* breakSignifier;
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
	static import linux = std.c.linux.linux;
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
			auto a = ir.front();

			if(a.length <= atMost) {
				f = a;
				atMost -= a.length;
				a = ir.consume(a.length);
				if(atMost != 0)
					ir.popFront();
			} else {
				// we actually have *more* here than we need....
				f = a[0..atMost];
				atMost = 0;
				ir.consume(atMost);
			}
		}
	};
}


/*
Copyright: Adam D. Ruppe, 2008 - 2012
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe

	Copyright Adam D. Ruppe 2008 - 2012.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
	http://www.boost.org/LICENSE_1_0.txt)
*/
