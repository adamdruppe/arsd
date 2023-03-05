/++
	OBSOLETE: Old version of my http implementation. Do not use this, instead use [arsd.http2].

	I no longer work on this, use http2.d instead.
+/
/*deprecated*/ module arsd.http; // adrdox apparently loses the comment above with deprecated, i need to fix that over there.

import std.socket;

// FIXME: check Transfer-Encoding: gzip always

version(with_openssl) {
	pragma(lib, "crypto");
	pragma(lib, "ssl");
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

struct HttpResponse {
	int code;
	string contentType;
	string[string] cookies;
	string[] headers;
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

HttpResponse httpRequest(string method, string uri, const(ubyte)[] content = null, string[string] cookies = null, string[] headers = null) {
	import std.socket;

	auto u = UriParts(uri);
	// auto f = openNetwork(u.host, u.port);
	auto f = new TcpSocket();
	f.connect(new InternetAddress(u.host, u.port));

	void delegate(string) write = (string d) {
		f.send(d);
	};

	char[4096] readBuffer; // rawRead actually blocks until it can fill up the whole buffer... which is broken as far as http goes so one char at a time i guess. slow lol
	char[] delegate() read = () {
		size_t num = f.receive(readBuffer);
		return readBuffer[0..num];
	};

	version(with_openssl) {
		import deimos.openssl.ssl;
		SSL* ssl;
		SSL_CTX* ctx;
		if(u.useHttps) {
			void sslAssert(bool ret){
				if (!ret){
					throw new Exception("SSL_ERROR");
				}
			}
			SSL_library_init();
			OpenSSL_add_all_algorithms();
			SSL_load_error_strings();

			ctx = SSL_CTX_new(SSLv3_client_method());
			sslAssert(!(ctx is null));

			ssl = SSL_new(ctx);
			SSL_set_fd(ssl, f.handle);
			sslAssert(SSL_connect(ssl) != -1);

			write = (string d) {
				SSL_write(ssl, d.ptr, cast(uint)d.length);
			};

			read = () {
				auto len = SSL_read(ssl, readBuffer.ptr, readBuffer.length);
				return readBuffer[0 .. len];
			};
		}
	}


	HttpResponse response = doHttpRequestOnHelpers(write, read, method, uri, content, cookies, headers, u.useHttps);

	version(with_openssl) {
		if(u.useHttps) {
			SSL_free(ssl);
			SSL_CTX_free(ctx);
		}
	}

	return response;
}

/**
	Executes a generic http request, returning the full result. The correct formatting
	of the parameters are the caller's responsibility. Content-Length is added automatically,
	but YOU must give Content-Type!
*/
HttpResponse doHttpRequestOnHelpers(void delegate(string) write, char[] delegate() read, string method, string uri, const(ubyte)[] content = null, string[string] cookies = null, string[] headers = null, bool https = false)
	in {
		assert(method == "POST" || method == "GET");
	}
do {
	auto u = UriParts(uri);





	write(format("%s %s HTTP/1.1\r\n", method, u.path));
	write(format("Host: %s\r\n", u.host));
	write(format("Connection: close\r\n"));
	if(content !is null)
		write(format("Content-Length: %d\r\n", content.length));

	if(cookies !is null) {
		string cookieHeader = "Cookie: ";
		bool first = true;
		foreach(k, v; cookies) {
			if(first)
				first = false;
			else
				cookieHeader ~= "; ";
			cookieHeader ~= std.uri.encodeComponent(k) ~ "=" ~ std.uri.encodeComponent(v);
		}

		write(format("%s\r\n", cookieHeader));
	}

	if(headers !is null)
		foreach(header; headers)
			write(format("%s\r\n", header));
	write("\r\n");
	if(content !is null)
		write(cast(string) content);


	string buffer;

	string readln() {
		auto idx = buffer.indexOf("\r\n");
		if(idx == -1) {
			auto more = read();
			if(more.length == 0) { // end of file or something
				auto ret = buffer;
				buffer = null;
				return ret;
			}
			buffer ~= more;
			return readln();
		}
		auto ret = buffer[0 .. idx + 2]; // + the \r\n
		if(idx + 2 < buffer.length)
			buffer = buffer[idx + 2 .. $];
		else
			buffer = null;
		return ret;
	}

	HttpResponse hr;
 cont:
	string l = readln();
	if(l[0..9] != "HTTP/1.1 ")
		throw new Exception("Not talking to a http server");

	hr.code = to!int(l[9..12]); // HTTP/1.1 ### OK

	if(hr.code == 100) { // continue
		do {
			l = readln();
		} while(l.length > 1);

		goto cont;
	}

	bool chunked = false;

	auto line = readln();
	while(line.length) {
		if(line.strip.length == 0)
			break;
		hr.headers ~= line;
		if(line.startsWith("Content-Type: "))
			hr.contentType = line[14..$-1];
		if(line.startsWith("Set-Cookie: ")) {
			auto hdr = line["Set-Cookie: ".length .. $-1];
			auto semi = hdr.indexOf(";");
			if(semi != -1)
				hdr = hdr[0 .. semi];

			auto equal = hdr.indexOf("=");
			string name, value;
			if(equal == -1) {
				name = hdr;
				// doesn't this mean erase the cookie?
			} else {
				name = hdr[0 .. equal];
				value = hdr[equal + 1 .. $];
			}

			name = std.uri.decodeComponent(name);
			value = std.uri.decodeComponent(value);

			hr.cookies[name] = value;
		}
		if(line.startsWith("Transfer-Encoding: chunked"))
			chunked = true;
		line = readln();
	}

	// there might be leftover stuff in the line buffer
	ubyte[] response = cast(ubyte[]) buffer.dup;
	auto part = read();
	while(part.length) {
		response ~= part;
		part = read();
	}

	if(chunked) {
		// read the hex length, stopping at a \r\n, ignoring everything between the new line but after the first non-valid hex character
		// read binary data of that length. it is our content
		// repeat until a zero sized chunk
		// then read footers as headers.

		int state = 0;
		int size;
		int start = 0;
		for(int a = 0; a < response.length; a++) {
			final switch(state) {
				case 0: // reading hex
					char c = response[a];
					if((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
						// just keep reading
					} else {
						int power = 1;
						size = 0;
						for(int b = a-1; b >= start; b--) {
							char cc = response[b];
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
						state++;
						continue;
					}
				break;
				case 1: // reading until end of line
					char c = response[a];
					if(c == '\n') {
						if(size == 0)
							state = 3;
						else
							state = 2;
					}
				break;
				case 2: // reading data
					hr.content ~= response[a..a+size];
					a += size;
					a+= 1; // skipping a 13 10
					start = a + 1;
					state = 0;
				break;
				case 3: // reading footers
					goto done; // FIXME
			}
		}
	} else
		hr.content = response;
	done:

	return hr;
}


/*
void main(string args[]) {
	write(post("http://arsdnet.net/bugs.php", ["test" : "hey", "again" : "what"]));
}
*/

version(none):

struct Url {
	string url;
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

		// only one request can be active on a given socket (at least HTTP < 2.0) so this is that
		HttpRequest[Socket] activeRequestOnSocket;
		HttpRequest[] pending; // and these are the requests that are waiting

		SocketSet readSet;


		void advanceConnections() {
			if(readSet is null)
				readSet = new SocketSet();

			// are there pending requests? let's try to send them

			readSet.reset();

			// active requests need to be read or written to
			foreach(sock, request; activeRequestOnSocket)
				readSet.add(sock);

			// check the other sockets just for EOF, if they close, take them out of our list,
			// we'll reopen if needed upon request.

			auto got = Socket.select(readSet, writeSet, null, 10.seconds /* timeout */);
			if(got == 0) /* timeout */
				{}
			else
			if(got == -1) /* interrupted */
				{}
			else /* ready */
				{}

			// call select(), do what needs to be done
			// no requests are active, send the ones pending connection now
			// we've completed a request, are there any more pending connection? if so, send them now

			auto readSet = new SocketSet();
		}
	}

	this() {
		addConnection(this);
	}

	~this() {
		removeConnection(this);
	}

	HttpResponse responseData;
	HttpRequestParameters parameters;
	private HttpClient parentClient;

	size_t bodyBytesSent;
	size_t bodyBytesReceived;

	State state;
	/// Called when data is received. Check the state to see what data is available.
	void delegate(AsynchronousHttpRequest) onDataReceived;

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

		responseData = HttpResponse.init;
		bodyBytesSent = 0;
		bodyBytesReceived = 0;
		state = State.pendingAvailableConnection;

		HttpResponse.advanceConnections();
	}


	/// Waits for the request to finish or timeout, whichever comes furst.
	HttpResponse waitForCompletion() {
		while(state != State.aborted && state != State.complete)
			HttpResponse.advanceConnections();
		return responseData;
	}

	/// Aborts this request.
	/// Due to the nature of the HTTP protocol, aborting one request will result in all subsequent requests made on this same connection to be aborted as well.
	void abort() {
		parentClient.close();
	}
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
	AsynchronousHttpRequest navigateTo(Url where) {
		currentUrl = where.basedOn(currentUrl);
		assert(0);
	}

	private Url currentUrl;

	this() {

	}

	this(Url url) {
		open(url);
	}

	this(string host, ushort port = 80, bool useSsl = false) {
		open(host, port);
	}

	// FIXME: add proxy
	// FIXME: some kind of caching

	void open(Url url) {

	}

	void open(string host, ushort port = 80, bool useSsl = false) {

	}

	void close() {
		socket.close();
	}

	void setCookie(string name, string value) {

	}

	void clearCookies() {

	}

	HttpResponse sendSynchronously() {
		auto request = sendAsynchronously();
		return request.waitForCompletion();
	}

	AsynchronousHttpRequest sendAsynchronously() {

	}

	string method;
	string host;
	ushort port;
	string uri;

	string[] headers;
	ubyte[] requestBody;

	string userAgent;

	/* inter-request state */
	string[string] cookies;
}

// FIXME: websocket
