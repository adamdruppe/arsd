// Copyright 2013, Adam D. Ruppe.
module arsd.http2;

debug import std.stdio;

import std.socket;
import core.time;

// FIXME: check Transfer-Encoding: gzip always

version(with_openssl) {
	pragma(lib, "crypto");
	pragma(lib, "ssl");
}

/+
HttpRequest httpRequest(string method, string url, ubyte[] content, string[string] content) {
	return null;
}

/**
	auto request = get("http://arsdnet.net/");
	request.send();

	auto response = get("http://arsdnet.net/").waitForCompletion();
*/
HttpRequest get(string url) {
	auto request = new HttpRequest();
	return request;
}

string getText(string url) {
	auto request = get(url);
	auto response = request.waitForCompletion();
	return cast(string) response.content;
}

ubyte[] getBinary(string url, string[string] cookies = null) {
	auto hr = httpRequest("GET", url, null, cookies);
	if(hr.code != 200)
		throw new Exception(format("HTTP answered %d instead of 200 on %s", hr.code, url));
	return hr.content;
}

/**
	Gets a textual document, ignoring headers. Throws on non-text or error.
*/
string get(string url, string[string] cookies = null) {
	auto hr = httpRequest("GET", url, null, cookies);
	if(hr.code != 200)
		throw new Exception(format("HTTP answered %d instead of 200 on %s", hr.code, url));
	if(hr.contentType.indexOf("text/") == -1)
		throw new Exception(hr.contentType ~ " is bad content for conversion to string");
	return cast(string) hr.content;

}

static import std.uri;

string post(string url, string[string] args, string[string] cookies = null) {
	string content;

	foreach(name, arg; args) {
		if(content.length)
			content ~= "&";
		content ~= std.uri.encode(name) ~ "=" ~ std.uri.encode(arg);
	}

	auto hr = httpRequest("POST", url, cast(ubyte[]) content, cookies, ["Content-Type: application/x-www-form-urlencoded"]);
	if(hr.code != 200)
		throw new Exception(format("HTTP answered %d instead of 200", hr.code));
	if(hr.contentType.indexOf("text/") == -1)
		throw new Exception(hr.contentType ~ " is bad content for conversion to string");

	return cast(string) hr.content;
}
+/

struct HttpResponse {
	int code;
	string codeText;

	string httpVersion;

	string statusLine;

	string contentType;

	string[string] cookies;

	string[] headers;
	string[string] headersHash;

	ubyte[] content;
	string contentText;

	HttpRequestParameters requestParameters;
}

import std.string;
static import std.algorithm;
import std.conv;
import std.range;



// Copy pasta from cgi.d, then stripped down
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

	/// Breaks down a uri string to its components
	this(string uri) {
		reparse(uri);
	}

	private void reparse(string uri) {
		import std.regex;
		// from RFC 3986

		// the ctRegex triples the compile time and makes ugly errors for no real benefit
		// it was a nice experiment but just not worth it.
		// enum ctr = ctRegex!r"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?";
		auto ctr = regex(r"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?");

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
}

/*
void main(string args[]) {
	write(post("http://arsdnet.net/bugs.php", ["test" : "hey", "again" : "what"]));
}
*/

struct BasicAuth {
	string username;
	string password;
}

/*
	When you send something, it creates a request
	and sends it asynchronously. The request object

	auto request = new HttpRequest();
	// set any properties here

	// synchronous usage
	auto reply = request.perform();

	// async usage, type 1:
	request.send();
	request2.send();

	// wait until the first one is done, with the second one still in-flight
	auto response = request.waitForCompletion();


	// async usage, type 2:
	request.onDataReceived = (HttpRequest hr) {
		if(hr.state == HttpRequest.State.complete) {
			// use hr.responseData
		}
	};
	request.send(); // send, using the callback

	// before terminating, be sure you wait for your requests to finish!

	request.waitForCompletion();

*/

class HttpRequest {
	private static {
		// we manage the actual connections. When a request is made on a particular
		// host, we try to reuse connections. We may open more than one connection per
		// host to do parallel requests.
		//
		// The key is the *domain name* and the port. Multiple domains on the same address will have separate connections.
		Socket[][string] socketsPerHost;

		void loseSocket(string host, ushort port, Socket s) {
			import std.string;
			auto key = format("%s:%s", host, port);

			if(auto list = key in socketsPerHost) {
				for(int a = 0; a < (*list).length; a++) {
					if((*list)[a] is s) {

						for(int b = a; b < (*list).length - 1; b++)
							(*list)[b] = (*list)[b+1];
						(*list).length = (*list).length - 1;
						break;
					}
				}
			}
		}

		Socket getOpenSocketOnHost(string host, ushort port, bool ssl) {
			Socket openNewConnection() {
				Socket socket;
				if(ssl)
					socket = new SslClientSocket(AddressFamily.INET, SocketType.STREAM);
				else
					socket = new Socket(AddressFamily.INET, SocketType.STREAM);

				socket.connect(new InternetAddress(host, port));
				debug writeln("opening to ", host, ":", port);
				return socket;
			}

			import std.string;
			auto key = format("http%s://%s:%s", ssl ? "s" : "", host, port);

			if(auto hostListing = key in socketsPerHost) {
				// try to find an available socket that is already open
				foreach(socket; *hostListing) {
					if(socket !in activeRequestOnSocket) {
						// let's see if it has closed since we last tried
						// e.g. a server timeout or something. If so, we need
						// to lose this one and immediately open a new one.
						SocketSet readSet = new SocketSet();
						readSet.reset();
						readSet.add(socket);
						auto got = Socket.select(readSet, null, null, 5.msecs /* timeout */);
						if(got > 0) {
							// we can read something off this... but there aren't
							// any active requests. Assume it is EOF and open a new one

							socket.close();
							loseSocket(host, port, socket);
							goto openNew;
						}
						return socket;
					}
				}

				// if not too many already open, go ahead and do a new one
				if((*hostListing).length < 6) {
					auto socket = openNewConnection();
					(*hostListing) ~= socket;
					return socket;
				} else
					return null; // too many, you'll have to wait
			}

			openNew:

			auto socket = openNewConnection();
			socketsPerHost[key] ~= socket;
			return socket;
		}

		// only one request can be active on a given socket (at least HTTP < 2.0) so this is that
		HttpRequest[Socket] activeRequestOnSocket;
		HttpRequest[] pending; // and these are the requests that are waiting

		SocketSet readSet;
		SocketSet writeSet;


		void advanceConnections() {
			if(readSet is null)
				readSet = new SocketSet();
			if(writeSet is null)
				writeSet = new SocketSet();

			ubyte[2048] buffer;

			HttpRequest[16] removeFromPending;
			size_t removeFromPendingCount = 0;

			// are there pending requests? let's try to send them
			foreach(idx, pc; pending) {
				if(removeFromPendingCount == removeFromPending.length)
					break;

				if(pc.state == HttpRequest.State.aborted) {
					removeFromPending[removeFromPendingCount++] = pc;
					continue;
				}

				auto socket = getOpenSocketOnHost(pc.requestParameters.host, pc.requestParameters.port, pc.requestParameters.ssl);

				if(socket !is null) {
					activeRequestOnSocket[socket] = pc;
					assert(pc.sendBuffer.length);
					pc.state = State.sendingHeaders;

					removeFromPending[removeFromPendingCount++] = pc;
				}
			}

			import std.algorithm : remove;
			foreach(rp; removeFromPending[0 .. removeFromPendingCount])
				pending = pending.remove!((a) => a is rp)();

			readSet.reset();
			writeSet.reset();

			// active requests need to be read or written to
			foreach(sock, request; activeRequestOnSocket) {
				// check the other sockets just for EOF, if they close, take them out of our list,
				// we'll reopen if needed upon request.
				readSet.add(sock);
				if(request.state == State.sendingHeaders || request.state == State.sendingBody)
					writeSet.add(sock);
			}

			tryAgain:
			auto got = Socket.select(readSet, writeSet, null, 10.seconds /* timeout */);
			if(got == 0) { /* timeout */
				// timeout
			} else if(got == -1) /* interrupted */
				goto tryAgain;
			else { /* ready */
				Socket[16] inactive;
				int inactiveCount = 0;
				foreach(sock, request; activeRequestOnSocket) {
					if(readSet.isSet(sock)) {
						keep_going:
						auto got = sock.receive(buffer);
						if(got < 0) {
							throw new Exception("receive error");
						} else if(got == 0) {
							// remote side disconnected
							debug writeln("remote disconnect");
							request.state = State.aborted;
							inactive[inactiveCount++] = sock;
							loseSocket(request.requestParameters.host, request.requestParameters.port, sock);
						} else {
							// data available
							request.handleIncomingData(buffer[0 .. got]);

							if(request.state == HttpRequest.State.complete) {
								inactive[inactiveCount++] = sock;
							// reuse the socket for another pending request, if we can
							}
						}

						if(request.onDataReceived)
							request.onDataReceived(request);

						if(auto s = cast(SslClientSocket) sock) {
							// select doesn't handle the case with stuff
							// left in the ssl buffer so i'm checking it separately
							if(s.dataPending()) {
								goto keep_going;
							}
						}
					}

					if(request.state == State.sendingHeaders || request.state == State.sendingBody)
					if(writeSet.isSet(sock)) {
						assert(request.sendBuffer.length);
						auto sent = sock.send(request.sendBuffer);
						if(sent <= 0)
							throw new Exception("send error " ~ lastSocketError);
						request.sendBuffer = request.sendBuffer[sent .. $];
						request.state = State.waitingForResponse;
					}
				}

				foreach(s; inactive[0 .. inactiveCount]) {
					debug writeln("removing socket from active list");
					activeRequestOnSocket.remove(s);
				}
			}

			// we've completed a request, are there any more pending connection? if so, send them now
		}
	}

	struct HeaderReadingState {
		bool justSawLf;
		bool justSawCr;
		bool atStartOfLine = true;
		bool readingLineContinuation;
	}
	HeaderReadingState headerReadingState;

	struct BodyReadingState {
		bool isGzipped;
		bool isDeflated;

		bool isChunked;
		int chunkedState;

		// used for the chunk size if it is chunked
		int contentLengthRemaining;
	}
	BodyReadingState bodyReadingState;

	bool closeSocketWhenComplete;

	import std.zlib;
	UnCompress uncompress;

	void handleIncomingData(scope const ubyte[] dataIn) {
		if(state == State.waitingForResponse) {
			state = State.readingHeaders;
			headerReadingState = HeaderReadingState.init;
			bodyReadingState = BodyReadingState.init;
		}

		const(ubyte)[] data = dataIn[];

		if(state == State.readingHeaders) {
			void parseLastHeader() {
				assert(responseData.headers.length);
				if(responseData.headers.length == 1) {
					responseData.statusLine = responseData.headers[0];
					import std.algorithm;
					auto parts = responseData.statusLine.splitter(" ");
					responseData.httpVersion = parts.front;
					parts.popFront();
					responseData.code = to!int(parts.front());
					parts.popFront();
					responseData.codeText = "";
					while(!parts.empty) {
						// FIXME: this sucks!
						responseData.codeText ~= parts.front();
						parts.popFront();
						if(!parts.empty)
							responseData.codeText ~= " ";
					}
				} else {
					// parse the new header
					auto header = responseData.headers[$-1];

					auto colon = header.indexOf(":");
					if(colon == -1)
						return;
					auto name = header[0 .. colon];
					auto value = header[colon + 2 .. $]; // skipping the colon itself and the following space

					switch(name) {
						case "Connection":
							if(value == "close")
								closeSocketWhenComplete = true;
						break;
						case "Content-Type":
							responseData.contentType = value;
						break;
						case "Content-Length":
							bodyReadingState.contentLengthRemaining = to!int(value);
						break;
						case "Transfer-Encoding":
							// note that if it is gzipped, it zips first, then chunks the compressed stream.
							// so we should always dechunk first, then feed into the decompressor
							if(value.strip == "chunked")
								bodyReadingState.isChunked = true;
							else throw new Exception("Unknown Transfer-Encoding: " ~ value);
						break;
						case "Content-Encoding":
							if(value == "gzip") {
								bodyReadingState.isGzipped = true;
								uncompress = new UnCompress();
							} else if(value == "deflate") {
								bodyReadingState.isDeflated = true;
								uncompress = new UnCompress();
							} else throw new Exception("Unknown Content-Encoding: " ~ value);
						break;
						case "Set-Cookie":
							// FIXME handle
						break;
						default:
							// ignore
					}

					responseData.headersHash[name] = value;
				}
			}

			size_t position = 0;
			for(position = 0; position < dataIn.length; position++) {
				if(headerReadingState.readingLineContinuation) {
					if(data[position] == ' ' || data[position] == '\t')
						continue;
					headerReadingState.readingLineContinuation = false;
				}

				if(headerReadingState.atStartOfLine) {
					headerReadingState.atStartOfLine = false;
					if(data[position] == '\r' || data[position] == '\n') {
						// done with headers
						if(data[position] == '\r' && (position + 1) < data.length && data[position + 1] == '\n')
							position++;
						state = State.readingBody;
						position++; // skip the newline
						break;
					} else if(data[position] == ' ' || data[position] == '\t') {
						// line continuation, ignore all whitespace and collapse it into a space
						headerReadingState.readingLineContinuation = true;
						responseData.headers[$-1] ~= ' ';
					} else {
						// new header
						if(responseData.headers.length)
							parseLastHeader();
						responseData.headers ~= "";
					}
				}

				if(data[position] == '\r') {
					headerReadingState.justSawCr = true;
					continue;
				} else
					headerReadingState.justSawCr = false;

				if(data[position] == '\n') {
					headerReadingState.justSawLf = true;
					headerReadingState.atStartOfLine = true;
					continue;
				} else 
					headerReadingState.justSawLf = false;

				responseData.headers[$-1] ~= data[position];
			}

			parseLastHeader();
			data = data[position .. $];
		}

		if(state == State.readingBody) {
			if(bodyReadingState.isChunked) {
				// read the hex length, stopping at a \r\n, ignoring everything between the new line but after the first non-valid hex character
				// read binary data of that length. it is our content
				// repeat until a zero sized chunk
				// then read footers as headers.

				start_over:
				for(int a = 0; a < data.length; a++) {
					final switch(bodyReadingState.chunkedState) {
						case 0: // reading hex
							char c = data[a];
							if((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
								// just keep reading
							} else {
								int power = 1;
								bodyReadingState.contentLengthRemaining = 0;
								for(int b = a-1; b >= 0; b--) {
									char cc = data[b];
									if(cc >= 'a' && cc <= 'z')
										cc -= 0x20;
									int val = 0;
									if(cc >= '0' && cc <= '9')
										val = cc - '0';
									else
										val = cc - 'A' + 10;

									bodyReadingState.contentLengthRemaining += power * val;
									power *= 16;
								}
								bodyReadingState.chunkedState++;
								continue;
							}
						break;
						case 1: // reading until end of line
							char c = data[a];
							if(c == '\n') {
								if(bodyReadingState.contentLengthRemaining == 0)
									bodyReadingState.chunkedState = 3;
								else
									bodyReadingState.chunkedState = 2;
							}
						break;
						case 2: // reading data
							auto can = a + bodyReadingState.contentLengthRemaining;
							if(can > data.length)
								can = cast(int) data.length;

							//if(bodyReadingState.isGzipped || bodyReadingState.isDeflated)
							//	responseData.content ~= cast(ubyte[]) uncompress.uncompress(data[a .. can]);
							//else
								responseData.content ~= data[a .. can];

							bodyReadingState.contentLengthRemaining -= can - a;
							a += can - a;
							if(bodyReadingState.contentLengthRemaining == 0) {
								a += 1; // skipping a 13 10
								bodyReadingState.chunkedState = 0;
								data = data[a+1 .. $];
							} else {
								data = data[a .. $];
							}
							goto start_over;
						case 3: // reading footers
							//goto done; // FIXME
							state = State.complete;

							auto n = uncompress.uncompress(responseData.content);
							n ~= uncompress.flush();
							responseData.content = cast(ubyte[]) n;

							//if(bodyReadingState.isGzipped || bodyReadingState.isDeflated)
							//	responseData.content ~= cast(ubyte[]) uncompress.flush();

							responseData.contentText = cast(string) responseData.content;
					}
				}

				done:
				// FIXME
				//if(closeSocketWhenComplete)
					//socket.close();
			} else {
				//if(bodyReadingState.isGzipped || bodyReadingState.isDeflated)
				//	responseData.content ~= cast(ubyte[]) uncompress.uncompress(data);
				//else
					responseData.content ~= data;
				assert(data.length <= bodyReadingState.contentLengthRemaining);
				bodyReadingState.contentLengthRemaining -= data.length;
				if(bodyReadingState.contentLengthRemaining == 0) {
					if(bodyReadingState.isGzipped || bodyReadingState.isDeflated) {
						auto n = uncompress.uncompress(responseData.content);
						n ~= uncompress.flush();
						responseData.content = cast(ubyte[]) n;
						//responseData.content ~= cast(ubyte[]) uncompress.flush();
					}
					state = State.complete;
					responseData.contentText = cast(string) responseData.content;
					// FIXME
					//if(closeSocketWhenComplete)
						//socket.close();
				}
			}
		}
	}

	this() {
	}

	this(Uri where, HttpVerb method) {
		auto parts = where;
		requestParameters.method = method;
		requestParameters.host = parts.host;
		requestParameters.port = cast(ushort) parts.port;
		requestParameters.ssl = parts.scheme == "https";
		if(parts.port == 0)
			requestParameters.port = requestParameters.ssl ? 443 : 80;
		requestParameters.uri = parts.path;
	}

	~this() {
	}

	ubyte[] sendBuffer;

	HttpResponse responseData;
	HttpRequestParameters parameters;
	private HttpClient parentClient;

	size_t bodyBytesSent;
	size_t bodyBytesReceived;

	State state;
	/// Called when data is received. Check the state to see what data is available.
	void delegate(HttpRequest) onDataReceived;

	enum State {
		/// The request has not yet been sent
		unsent,

		/// The send() method has been called, but no data is
		/// sent on the socket yet because the connection is busy.
		pendingAvailableConnection,

		/// The headers are being sent now
		sendingHeaders,

		/// The body is being sent now
		sendingBody,

		/// The request has been sent but we haven't received any response yet
		waitingForResponse,

		/// We have received some data and are currently receiving headers
		readingHeaders,

		/// All headers are available but we're still waiting on the body
		readingBody,

		/// The request is complete.
		complete,

		/// The request is aborted, either by the abort() method, or as a result of the server disconnecting
		aborted
	}

	/// Sends now and waits for the request to finish, returning the response.
	HttpResponse perform() {
		send();
		return waitForCompletion();
	}

	/// Sends the request asynchronously.
	void send() {
		if(state != State.unsent && state != State.aborted)
			return; // already sent
		string headers;

		headers ~= to!string(requestParameters.method) ~ " "~requestParameters.uri;
		if(requestParameters.useHttp11)
			headers ~= " HTTP/1.1\r\n";
		else
			headers ~= " HTTP/1.0\r\n";
		headers ~= "Host: "~requestParameters.host~"\r\n";
		if(requestParameters.userAgent.length)
			headers ~= "User-Agent: "~requestParameters.userAgent~"\r\n";
		if(requestParameters.authorization.length)
			headers ~= "Authorization: "~requestParameters.authorization~"\r\n";
		if(requestParameters.bodyData.length)
			headers ~= "Content-Length: "~to!string(requestParameters.bodyData.length)~"\r\n";
		if(requestParameters.acceptGzip)
			headers ~= "Accept-Encoding: gzip\r\n";

		foreach(header; requestParameters.headers)
			headers ~= header ~ "\r\n";

		headers ~= "\r\n";

		sendBuffer = cast(ubyte[]) headers ~ requestParameters.bodyData;

		responseData = HttpResponse.init;
		responseData.requestParameters = requestParameters;
		bodyBytesSent = 0;
		bodyBytesReceived = 0;
		state = State.pendingAvailableConnection;

		pending ~= this;

		HttpRequest.advanceConnections();
	}


	/// Waits for the request to finish or timeout, whichever comes furst.
	HttpResponse waitForCompletion() {
		while(state != State.aborted && state != State.complete) {
			if(state == State.unsent)
				send();
			HttpRequest.advanceConnections();
		}

		return responseData;
	}

	/// Aborts this request.
	void abort() {
		this.state = State.aborted;
		// FIXME
	}

	HttpRequestParameters requestParameters;
}

struct HttpRequestParameters {
	// Duration timeout;

	// debugging
	bool useHttp11 = true;
	bool acceptGzip = true;

	// the request itself
	HttpVerb method;
	string host;
	ushort port;
	string uri;

	bool ssl;

	string userAgent;
	string authorization;

	string[string] cookies;

	string[] headers; /// do not duplicate host, content-length, content-type, or any others that have a specific property

	string contentType;
	ubyte[] bodyData;
}

interface IHttpClient {

}

enum HttpVerb { GET, HEAD, POST, PUT, DELETE, OPTIONS, TRACE, CONNECT, PATCH, MERGE }

/*
	Usage:

	auto client = new HttpClient("localhost", 80);
	// relative links work based on the current url
	client.get("foo/bar");
	client.get("baz"); // gets foo/baz

	auto request = client.get("rofl");
	auto response = request.waitForCompletion();
*/

/// HttpClient keeps cookies, location, and some other state to reuse connections, when possible, like a web browser.
class HttpClient {
	/* Protocol restrictions, useful to disable when debugging servers */
	bool useHttp11 = true;
	bool acceptGzip = true;

	/// Automatically follow a redirection?
	bool followLocation = false;

	@property Uri location() {
		return currentUrl;
	}

	/// High level function that works similarly to entering a url
	/// into a browser.
	///
	/// Follows locations, updates the current url.
	HttpRequest navigateTo(Uri where, HttpVerb method = HttpVerb.GET) {
		currentUrl = where.basedOn(currentUrl);
		currentDomain = where.host;
		auto request = new HttpRequest(currentUrl, method);

		request.requestParameters.userAgent = userAgent;
		request.requestParameters.authorization = authorization;

		request.requestParameters.useHttp11 = this.useHttp11;
		request.requestParameters.acceptGzip = this.acceptGzip;

		return request;
	}

	private Uri currentUrl;
	private string currentDomain;

	this(ICache cache = null) {

	}

	// FIXME: add proxy
	// FIXME: some kind of caching

	void setCookie(string name, string value, string domain = null) {
		if(domain == null)
			domain = currentDomain;

		cookies[domain][name] = value;
	}

	void clearCookies(string domain = null) {
		if(domain is null)
			cookies = null;
		else
			cookies[domain] = null;
	}

	// If you set these, they will be pre-filled on all requests made with this client
	string userAgent = "D arsd.html2";
	string authorization;

	/* inter-request state */
	string[string][string] cookies;
}

interface ICache {
	HttpResponse* getCachedResponse(HttpRequestParameters request);
}

/// Provides caching behavior similar to a real web browser
class HttpCache : ICache {
	HttpResponse* getCachedResponse(HttpRequestParameters request) {
		return null;
	}
}

/// Gives simple maximum age caching, ignoring the actual http headers
class SimpleCache : ICache {
	HttpResponse* getCachedResponse(HttpRequestParameters request) {
		return null;
	}
}

struct HttpCookie {
	string name;
	string value;
	string domain;
	string path;
	//SysTime expirationDate;
	bool secure;
	bool httpOnly;
}

// FIXME: websocket

version(testing)
void main() {
	import std.stdio;
	auto client = new HttpClient();
	auto request = client.navigateTo(Uri("http://localhost/chunked.php"));
	request.send();
	auto request2 = client.navigateTo(Uri("http://dlang.org/"));
	request2.send();

	{
	auto response = request2.waitForCompletion();
	//write(cast(string) response.content);
	}

	auto response = request.waitForCompletion();
	write(cast(string) response.content);

	writeln(HttpRequest.socketsPerHost);
}


// From sslsocket.d

version=use_openssl;

version(use_openssl) {
	alias SslClientSocket = OpenSslSocket;

	extern(C) {
		int SSL_library_init();
		void OpenSSL_add_all_ciphers();
		void OpenSSL_add_all_digests();
		void SSL_load_error_strings();

		struct SSL {}
		struct SSL_CTX {}
		struct SSL_METHOD {}

		SSL_CTX* SSL_CTX_new(const SSL_METHOD* method);
		SSL* SSL_new(SSL_CTX*);
		int SSL_set_fd(SSL*, int);
		int SSL_connect(SSL*);
		int SSL_write(SSL*, const void*, int);
		int SSL_read(SSL*, void*, int);
		int SSL_pending(const SSL*);
		void SSL_free(SSL*);
		void SSL_CTX_free(SSL_CTX*);

		SSL_METHOD* SSLv3_client_method();
	}

	shared static this() {
		SSL_library_init();
		OpenSSL_add_all_ciphers();
		OpenSSL_add_all_digests();
		SSL_load_error_strings();
	}

	pragma(lib, "crypto");
	pragma(lib, "ssl");

	class OpenSslSocket : Socket {
		private SSL* ssl;
		private SSL_CTX* ctx;
		private void initSsl() {
			ctx = SSL_CTX_new(SSLv3_client_method());
			assert(ctx !is null);

			ssl = SSL_new(ctx);
			SSL_set_fd(ssl, this.handle);
		}

		bool dataPending() {
			return SSL_pending(ssl) > 0;
		}

		@trusted
		override void connect(Address to) {
			super.connect(to);
			if(SSL_connect(ssl) == -1)
				throw new Exception("ssl connect");
		}
		
		@trusted
		override ptrdiff_t send(const(void)[] buf, SocketFlags flags) {
			return SSL_write(ssl, buf.ptr, cast(uint) buf.length);
		}
		override ptrdiff_t send(const(void)[] buf) {
			return send(buf, SocketFlags.NONE);
		}
		@trusted
		override ptrdiff_t receive(void[] buf, SocketFlags flags) {
			return SSL_read(ssl, buf.ptr, cast(int)buf.length);
		}
		override ptrdiff_t receive(void[] buf) {
			return receive(buf, SocketFlags.NONE);
		}

		this(AddressFamily af, SocketType type = SocketType.STREAM) {
			super(af, type);
			initSsl();
		}

		this(socket_t sock, AddressFamily af) {
			super(sock, af);
			initSsl();
		}

		~this() {
			SSL_free(ssl);
			SSL_CTX_free(ctx);
		}
	}
}
