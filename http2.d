// Copyright 2013, Adam D. Ruppe.
module arsd.http2;

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
}

import std.string;
static import std.algorithm;
import std.conv;

struct UriParts {
	string original;
	string method;
	string host;
	ushort port;
	string path;

	bool useHttps;

	this(string uri) {
		original = uri;

		if(uri[0 .. 8] == "https://")
			useHttps = true;
		else
		if(uri[0..7] != "http://")
			throw new Exception("You must use an absolute, http or https URL.");

		version(with_openssl) {} else
		if(useHttps)
			throw new Exception("openssl support not compiled in try -version=with_openssl");

		int start = useHttps ? 8 : 7;

		auto posSlash = uri[start..$].indexOf("/");
		if(posSlash != -1)
			posSlash += start;

		if(posSlash == -1)
			posSlash = uri.length;

		auto posColon = uri[start..$].indexOf(":");
		if(posColon != -1)
			posColon += start;

		if(useHttps)
			port = 443;
		else
			port = 80;

		if(posColon != -1 && posColon < posSlash) {
			host = uri[start..posColon];
			port = to!ushort(uri[posColon+1..posSlash]);
		} else
			host = uri[start..posSlash];

		path = uri[posSlash..$];
		if(path == "")
			path = "/";
	}
}

/*
void main(string args[]) {
	write(post("http://arsdnet.net/bugs.php", ["test" : "hey", "again" : "what"]));
}
*/

struct Url {
	string url;

	Url basedOn(Url url) { return url; }
}

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
		// The key is the *domain name*. Multiple domains on the same address will have separate connections.
		Socket[][string] socketsPerHost;

		Socket getOpenSocketOnHost(string host, ushort port) {
			// FIXME: port

			Socket openNewConnection() {
				auto socket = new Socket(AddressFamily.INET, SocketType.STREAM);
				socket.connect(new InternetAddress(host, port));
				return socket;
			}

			if(auto hostListing = host in socketsPerHost) {
				// try to find an available socket that is already open
				foreach(socket; *hostListing) {
					if(socket !in activeRequestOnSocket)
						return socket;
				}

				// if not too many already open, go ahead and do a new one
				if((*hostListing).length < 6) {
					auto socket = openNewConnection();
					(*hostListing) ~= socket;
					return socket;
				} else
					return null; // too many, you'll have to wait
			}

			auto socket = openNewConnection();
			socketsPerHost[host] ~= socket;
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

				auto socket = getOpenSocketOnHost(pc.requestParameters.host, 80);

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
						auto got = sock.receive(buffer);
						if(got < 0) {
							throw new Exception("receive error");
						} else if(got == 0) {
							// remote side disconnected
							request.state = State.aborted;
							inactive[inactiveCount++] = sock;
							// FIXME remove the socket from the list
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

				foreach(s; inactive[0 .. inactiveCount])
					activeRequestOnSocket.remove(s);
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
					responseData.codeText = parts.front();
				} else {
					// parse the new header
					auto header = responseData.headers[$-1];

					auto colon = header.indexOf(":");
					if(colon == -1)
						return;
					auto name = header[0 .. colon];
					auto value = header[colon + 2 .. $]; // skipping the colon itself and the following space

					switch(name) {
						case "Content-Type":
							responseData.contentType = value;
						break;
						case "Content-Length":
							bodyReadingState.contentLengthRemaining = to!int(value);
						break;
						case "Transfer-Encoding":
							// note that if it is gzipped, it zips first, then chunks the compressed stream.
							// so we should always dechunk first, then feed into the decompressor
							if(value == "chunked")
								bodyReadingState.isChunked = true;
							else throw new Exception("Unknown Transfer-Encoding: " ~ value);
						break;
						case "Content-Encoding":
							if(value == "gzip")
								bodyReadingState.isGzipped = true;
							else if(value == "deflate")
								bodyReadingState.isDeflated = true;
							else throw new Exception("Unknown Content-Encoding: " ~ value);
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
							// FIXME: gunzip
							responseData.content ~= data[a .. a + bodyReadingState.contentLengthRemaining];

							a += bodyReadingState.contentLengthRemaining;
							a += 1; // skipping a 13 10
							data = data[a+1 .. $];
							bodyReadingState.chunkedState = 0;
							goto start_over;
						break;
						case 3: // reading footers
							goto done; // FIXME
						break;
					}
				}

				done:
				state = State.complete;
			} else {
				// FIXME: gunzip
				responseData.content ~= data;
				assert(data.length <= bodyReadingState.contentLengthRemaining);
				bodyReadingState.contentLengthRemaining -= data.length;
				if(bodyReadingState.contentLengthRemaining == 0)
					state = State.complete;
			}
		}
	}

	this() {
	}

	this(Url where) {
		auto parts = UriParts(where.url);
		requestParameters.method = HttpVerb.GET;
		requestParameters.host = parts.host;
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
		sendBuffer = cast(ubyte[]) ("GET "~requestParameters.uri~" HTTP/1.1\r\nHost: "~requestParameters.host~"\r\n\r\n");

		responseData = HttpResponse.init;
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
	Duration timeout;

	// debugging
	bool useHttp11 = true;
	bool acceptGzip = true;

	// the request itself
	HttpVerb method;
	string host;
	string uri;

	string userAgent;

	string[string] cookies;

	string[] headers; /// do not duplicate host, content-length, content-type, or any others that have a specific property

	string contentType;
	ubyte[] bodyData;
}

interface IHttpClient {

}

enum HttpVerb { GET, HEAD, POST, PUT, DELETE, OPTIONS, TRACE, CONNECT }

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
	bool useGzip = true;

	/// Automatically follow a redirection?
	bool followLocation = false;

	@property Url location() {
		return currentUrl;
	}

	/// High level function that works similarly to entering a url
	/// into a browser.
	///
	/// Follows locations, updates the current url.
	HttpRequest navigateTo(Url where) {
		currentUrl = where.basedOn(currentUrl);
		currentUrl = where;
		auto parts = UriParts(where.url);
		currentDomain = parts.host;
		auto request = new HttpRequest(currentUrl);
		return request;
	}

	private Url currentUrl;
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

	string userAgent = "D std.net.html";

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

void main() {
	import std.stdio;
	auto client = new HttpClient();
	auto request = client.navigateTo(Url("http://localhost/chunked.php"));
	request.send();
	auto request2 = client.navigateTo(Url("http://dlang.org/"));
	request2.send();

	{
	auto response = request2.waitForCompletion();
	write(cast(string) response.content);
	}

	auto response = request.waitForCompletion();
	write(cast(string) response.content);

	writeln(HttpRequest.socketsPerHost);
}
