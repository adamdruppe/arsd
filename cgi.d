module arsd.cgi;

// FIXME: the location header is supposed to be an absolute url I guess.

// FIXME: would be cool to flush part of a dom document before complete
// somehow in here and dom.d.


// FIXME: 100 Continue in the nph section? Probably belongs on the
// httpd class though.

public import std.string;
import std.uri;
import std.exception;
import std.base64;
static import std.algorithm;
public import std.stdio;
import std.datetime;
public import std.conv;
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
	this(long maxContentLength = 5_000_000,
		string[string] env = null,
		const(ubyte)[] delegate() readdata = null,
		void delegate(const(ubyte)[]) _rawDataOutput = null,
		void delegate() _flush = null
		) { super(maxContentLength, env, readdata, _rawDataOutput, _flush); }
	
	this(string[] headers, immutable(ubyte)[] data, string address, void delegate(const(ubyte)[]) _rawDataOutput = null, int pathInfoStarts = 0, void delegate() _flush = null) {
		super(headers, data, address, _rawDataOutput, pathInfoStarts, _flush);
	}
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

string makeDataUrl(string mimeType, in void[] data) {
	auto data64 = Base64.encode(cast(const(ubyte[])) data);
	return "data:" ~ mimeType ~ ";base64," ~ assumeUnique(data64);
}


/// The main interface with the web request
class Cgi {
  public:
	enum RequestMethod { GET, HEAD, POST, PUT, DELETE, // GET and POST are the ones that really work
		// these are defined in the standard, but idk if they are useful for anything
		OPTIONS, TRACE, CONNECT,
		// this is an extension for when the method is not specified and you want to assume
		CommandLine }

	/** Initializes it using the CGI (or FastCGI) interface */
	this(long maxContentLength = 5_000_000,
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

		https = getenv("HTTPS") == "on";

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


			if(readdata is null)
				foreach(ubyte[] chunk; stdin.byChunk(iis ? contentLength : 4096)) { // FIXME: maybe it should pass the range directly to the parser
					if(chunk.length > contentLength) {
						handleIncomingDataChunk(chunk[0..contentLength]);
						amountReceived += contentLength;
						contentLength = 0;
						break;
					} else {
						handleIncomingDataChunk(chunk);
						contentLength -= chunk.length;
						amountReceived += chunk.length;
					}
					if(contentLength == 0)
						break;

					onRequestBodyDataReceived(amountReceived, originalContentLength);
				}
				else {
					// we have a custom data source..
					auto chunk = readdata();
					while(chunk.length) {
						// FIXME: DRY
						if(chunk.length > contentLength) {
							handleIncomingDataChunk(chunk[0..contentLength]);
							amountReceived += contentLength;
							contentLength = 0;
							break;
						} else {
							handleIncomingDataChunk(chunk);
							contentLength -= chunk.length;
							amountReceived += chunk.length;
						}
						if(contentLength == 0)
							break;

						chunk = readdata();
						onRequestBodyDataReceived(amountReceived, originalContentLength);
					}
				}

				onRequestBodyDataReceived(amountReceived, originalContentLength);
				postArray = assumeUnique(pps._post);
				files = assumeUnique(pps._files);
				post = keepLastOf(postArray);
				cleanUpPostDataState();
			}

			version(preserveData)
				originalPostData = data;
//			mixin(createVariableHashes());
		}
		// fixme: remote_user script name
	}

	/// Cleans up any temporary files. Do not use the object
	/// after calling this.
	///
	/// NOTE: it is called automatically by GenericMain
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
			UploadedFile[string] _files;
		}

		PostParserState pps;
	}

	// given a content type and length, decide what we're going to do with the data..
	void prepareForIncomingDataChunks(string contentType, ulong contentLength) {
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
	void handleIncomingDataChunk(const(ubyte)[] chunk) {
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
					pps._files[pps.piece.name] = pps.piece;
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
					if(pps.buffer.length + chunk.length > 70 * 1024) // they should be < 1 kb really....
						throw new Exception("wtf is up with the huge mime part headers");

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

	void cleanUpPostDataState() {
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

	/** Initializes it from some almost* raw HTTP request data
		headers[0] should be the "GET / HTTP/1.1" line

		* Note the data should /not/ be chunked at this point.

		headers: each http header, excluding the \r\n at the end, but including the request line at headers[0]
		data: the request data (usually POST variables)
		address: the remote IP
		_rawDataOutput: delegate to accept response data. If not null, this is called for all data output, which
			will include HTTP headers and the status line. The data may also be chunked; it is already suitable for
			being sent directly down the wire.

			If null, the data is sent to stdout.



		FIXME: data should be able to be streaming, for large files
			indeed, it should probably just take a file descriptor
			or two and do all the work itself.
	*/
	this(string[] headers, immutable(ubyte)[] data, string address, void delegate(const(ubyte)[]) _rawDataOutput = null, int pathInfoStarts = 0, void delegate() _flush = null) {
		auto parts = headers[0].split(" ");

		https = false;
		port = 80; // FIXME

		rawDataOutput = _rawDataOutput;
		flushDelegate = _flush;
		nph = true;

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

		remoteAddress = address;

		if(headers[0].indexOf("HTTP/1.0") != -1) {
			http10 = true;
			autoBuffer = true;
		}

		string contentType = "";

		string[string] requestHeadersHere;

		foreach(header; headers[1..$]) {
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
				case "last-event-id":
					lastEventId = value;
				break;
				case "authorization":
					authorization = value;
				break;
				case "content-type":
					contentType = value;
				break;
				case "connection":
					if(value.toLower().indexOf("keep-alive") != -1)
						keepAliveRequested = true;
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

		requestHeaders = assumeUnique(requestHeadersHere);

		cookiesArray = getCookieArray();
		cookies = keepLastOf(cookiesArray);
		if(data.length) {
			prepareForIncomingDataChunks(contentType, data.length);
			for(size_t block = 0; block < data.length; block += 4096)
				handleIncomingDataChunk(data[block .. ((block+4096 > data.length) ? data.length : block + 4096)]);
			postArray = assumeUnique(pps._post);
			files = assumeUnique(pps._files);
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

	/// This represents a file the user uploaded via a POST request.
	struct UploadedFile {
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

	/// This gets a full url for the current request, including port, protocol, host, path, and query
	string getCurrentCompleteUri() const {
		return format("http%s://%s%s%s",
			https ? "s" : "",
			host,
			port == 80 ? "" : ":" ~ to!string(port),
			requestUri);
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
	void setResponseLocation(string uri, bool important = true) {
		if(!important && isCurrentResponseLocationImportant)
			return; // important redirects always override unimportant ones

		assert(!outputtedResponseData);
		responseStatus = "302 Found";
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
	void write(const(void)[] t, bool isAll = false) {
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
					if(nph && responseChunked)
						rawDataOutput(makeChunk(cast(const(ubyte)[]) t));
					else
						rawDataOutput(cast(const(ubyte)[]) t);
				else
					stdout.rawWrite(t);
			}
		}
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
			write("");

		// writing auto buffered data
		if(requestMethod != RequestMethod.HEAD && autoBuffer) {
			if(!nph)
				stdout.rawWrite(outputBuffer);
			else
				write(outputBuffer, true); // tell it this is everything
		}

		// closing the last chunk...
		if(nph && rawDataOutput !is null && responseChunked)
			rawDataOutput(cast(const(ubyte)[]) "0\r\n\r\n");

		closed = true;
	}

	// Closes without doing anything, shouldn't be used often
	void rawClose() {
		closed = true;
	}

	/// Gets a request variable as a specific type, or the default value of it isn't there
	/// or isn't convertable to the request type. Checks both GET and POST variables.
	T request(T = string)(in string name, in T def = T.init) const nothrow {
		try {
			return
				(name in post) ? to!T(post[name]) :
				(name in get)  ? to!T(get[name]) :
				def;
		} catch(Exception e) { return def; }
	}

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
	immutable(UploadedFile[string]) files; /// Represents user uploaded files. When making a file upload form, be sure to follow the standard: set method="POST" and enctype="multipart/form-data" in your html <form> tag attributes. The key into this array is the name attribute on your input tag, just like with other post variables. See the comments on the UploadedFile struct for more information about the data inside, including important notes on max size and content location.

	/// Use these if you expect multiple items submitted with the same name. btw, assert(get[name] is getArray[name][$-1); should pass. Same for post and cookies.
	/// the order of the arrays is the order the data arrives
	immutable(string[][string]) getArray; /// like get, but an array of values per name
	immutable(string[][string]) postArray; /// ditto for post
	immutable(string[][string]) cookiesArray; /// ditto for cookies

	// FIXME: what about multiple files with the same name?
  private:
	//RequestMethod _requestMethod;
}


// should this be a separate module? Probably, but that's a hassle.

/// Represents a url that can be broken down or built up through properties
// FIXME: finish this
struct Url {
	string uri;
	alias uri this;

	this(string uri) {
		this.uri = uri;
	}

	string toString() {
		return uri;
	}

	/// Returns a new absolute Url given a base. It treats this one as
	/// relative where possible, but absolute if not. (If protocol, domain, or
	/// other info is not set, the new one inherits it from the base.)
	Url basedOn(in Url baseUrl) const {
		Url n = this;

		// if anything is given in the existing url, we don't use the base anymore.
		if(n.protocol is null) {
			n.protocol = baseUrl.protocol;
			if(n.server is null) {
				n.server = baseUrl.server;
				if(n.port == 0) {
					n.port = baseUrl.port;
					if(n.path.length > 0 && n.path[0] != '/') {
						n.path = baseUrl.path[0 .. baseUrl.path.lastIndexOf("/") + 1] ~ n.path;
					}
				}
			}
		}

		n.uri = n.toString();

		return n;
	}

	// This can sometimes be a big pain in the butt for me, so lots of copy/paste here to cover
	// the possibilities.
	unittest {
		auto url = Url("cool.html"); // checking relative links
		assert(url.basedOn(Url("http://test.com/what/test.html")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Url("https://test.com/what/test.html")) == "https://test.com/what/cool.html");
		assert(url.basedOn(Url("http://test.com/what/")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Url("http://test.com/")) == "http://test.com/cool.html");
		assert(url.basedOn(Url("http://test.com")) == "http://test.com/cool.html");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b&c=d")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b&c=d#what")) == "http://test.com/what/cool.html");
		assert(url.basedOn(Url("http://test.com")) == "http://test.com/cool.html");

		url = Url("/something/cool.html"); // same server, different path
		assert(url.basedOn(Url("http://test.com/what/test.html")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Url("https://test.com/what/test.html")) == "https://test.com/something/cool.html");
		assert(url.basedOn(Url("http://test.com/what/")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Url("http://test.com/")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Url("http://test.com")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b&c=d")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b&c=d#what")) == "http://test.com/something/cool.html");
		assert(url.basedOn(Url("http://test.com")) == "http://test.com/something/cool.html");

		url = Url("?query=answer"); // same path. server, protocol, and port, just different query string and fragment
		assert(url.basedOn(Url("http://test.com/what/test.html")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Url("https://test.com/what/test.html")) == "https://test.com/what/test.html?query=answer");
		assert(url.basedOn(Url("http://test.com/what/")) == "http://test.com/what/?query=answer");
		assert(url.basedOn(Url("http://test.com/")) == "http://test.com/?query=answer");
		assert(url.basedOn(Url("http://test.com")) == "http://test.com?query=answer");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b&c=d")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Url("http://test.com/what/test.html?a=b&c=d#what")) == "http://test.com/what/test.html?query=answer");
		assert(url.basedOn(Url("http://test.com")) == "http://test.com?query=answer");

		url = Url("#anchor"); // everything should remain the same except the anchor

		url = Url("//example.com"); // same protocol, but different server. the path here should be blank.

		url = Url("//example.com/example.html"); // same protocol, but different server and path

		url = Url("http://example.com/test.html"); // completely absolute link should never be modified

		url = Url("http://example.com"); // completely absolute link should never be modified, even if it has no path

		// FIXME: add something for port too


	}

	string protocol;
	string server;
	int port;
	string path;
	string query;
	string fragment;
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
mixin template GenericMain(alias fun, T...) {
	mixin CustomCgiMain!(Cgi, fun, T);
}

/// If you want to use a subclass of Cgi with generic main, use this mixin.
mixin template CustomCgiMain(CustomCgi, alias fun, T...) if(is(CustomCgi : Cgi)) {
	// kinda hacky - the T... is passed to Cgi's constructor in standard cgi mode, and ignored elsewhere
version(embedded_httpd)
	import arsd.httpd;

	void main() {
		version(embedded_httpd) {
			// what about forwarding the other constructor args?
			// this probably needs a whole redoing...
			serveHttp!CustomCgi(&fun, 8080);//5005);
			return;
		}

		version(fastcgi) {
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

				string getFcgiEnvVar(string what) {
					if(what in fcgienv)
						return fcgienv[what];
					return "";
				}

				void flushFcgi() {
					FCGX_FFlush(output);
				}

				auto cgi = new CustomCgi(5_000_000, fcgienv, &getFcgiChunk, &writeFcgi, &flushFcgi);
				try {
					fun(cgi);
					cgi.close();
					cgi.dispose();
				} catch(Throwable t) {
					if(1) { // !cgi.isClosed) 
						auto msg = t.toString;
						FCGX_PutStr(cast(ubyte*) msg.ptr, msg.length, error);
						msg = "Status: 500 Internal Server Error\n";
						msg ~= "Content-Type: text/plain\n\n";
						debug msg ~= t.toString;
						else  msg ~= "An unexpected error has occurred.";

						FCGX_PutStr(cast(ubyte*) msg.ptr, msg.length, output);
					}
				}
			}

			return;
		}

		auto cgi = new CustomCgi(T);

		try {
			fun(cgi);
			cgi.close();
			cgi.dispose();
		} catch (Throwable c) {
			// if the thing is closed, the app probably wrote an error message already, don't do it again.
			//if(cgi.isClosed)
				//goto doNothing;

			// FIXME: this sucks
			string message = "An unexpected error has occurred.";

			debug message = c.toString();

			writefln("Status: 500 Internal Server Error\nContent-Type: text/html\n\n%s", "<html><head><title>Internal Server Error</title></head><body><br><br><br><br><code><pre>"~(std.array.replace(std.array.replace(message, "<", "&lt;"), ">", "&gt;"))~"</pre></code></body></html>");

			string str = c.toString();
			// wtf it is bitching about a conflict with std.algorithm... out of the blue.
			auto idx = std.string.indexOf(str, "\n");
			if(idx != -1)
				str = str[0..idx];

			doNothing:

			stderr.writeln(str);
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
      writeln(typeid(immutable(Cgi.UploadedFile)[immutable(char)[]]));
      writeln(typeid(immutable(char[])[immutable(char)[]]));
      // this is getting kinda ridiculous btw. Moving assoc arrays
      // to the library is the pain that keeps on coming.

      // eh this broke the build on the work server
      // writeln(typeid(immutable(char)[][immutable(string[])]));
      writeln(typeid(immutable(string[])[immutable(char)[]]));
}





version(fastcgi) {
	pragma(lib, "fcgi");
	extern(C) {

	struct FCGX_Stream {
		ubyte* rdNext;
		ubyte* wrNext;
		ubyte* stop;
		ubyte* stopUnget;
		int isReader;
		int isClosed;
		int wasFCloseCalled;
		int FCGI_errno;
		void* function(FCGX_Stream* stream) fillBuffProc;
		void* function(FCGX_Stream* stream, int doClose) emptyBuffProc;
		void* data;
	}

	alias char** FCGX_ParamArray;

	int FCGX_Accept(FCGX_Stream** stdin, FCGX_Stream** stdout, FCGX_Stream** stderr, FCGX_ParamArray* envp);
	int FCGX_GetChar(FCGX_Stream* stream);
	int FCGX_PutStr(const ubyte* str, int n, FCGX_Stream* stream);
	int FCGX_HasSeenEOF(FCGX_Stream* stream);
	int FCGX_FFlush(FCGX_Stream *stream);


	}
}


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

// I FUCKING HATE that the Phobos managers decided to replace std.date with code that had
// no idea what kinds of things std.date was useful for.
//
// And to add insult to injury, they are going to remove the tiny olive branch the new
// module offered. Whatever, I want it at least some of it.

long sysTimeToDTime(in SysTime sysTime) {
    return convert!("hnsecs", "msecs")(sysTime.stdTime - 621355968000000000L);
}

long getUtcTime() { // renamed primarily to avoid conflict with std.date itself
	return sysTimeToDTime(Clock.currTime(UTC()));
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
