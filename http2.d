// Copyright 2013-2020, Adam D. Ruppe.
/++
	This is version 2 of my http/1.1 client implementation.
	
	
	It has no dependencies for basic operation, but does require OpenSSL
	libraries (or compatible) to be support HTTPS. Compile with
	`-version=with_openssl` to enable such support.
	
	http2.d, despite its name, does NOT implement HTTP/2.0, but this
	shouldn't matter for 99.9% of usage, since all servers will continue
	to support HTTP/1.1 for a very long time.

+/
module arsd.http2;

// FIXME: I think I want to disable sigpipe here too.

import std.uri : encodeComponent;

debug(arsd_http2_verbose) debug=arsd_http2;

debug(arsd_http2) import std.stdio : writeln;

version=arsd_http_internal_implementation;

version(without_openssl) {}
else {
version=use_openssl;
version=with_openssl;
version(older_openssl) {} else
version=newer_openssl;
}

version(arsd_http_winhttp_implementation) {
	pragma(lib, "winhttp")
	import core.sys.windows.winhttp;
	// FIXME: alter the dub package file too

	// https://docs.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpreaddata
	// https://docs.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpsendrequest
	// https://docs.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpopenrequest
	// https://docs.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpconnect
}



/++
	Demonstrates core functionality, using the [HttpClient],
	[HttpRequest] (returned by [HttpClient.navigateTo|client.navigateTo]),
	and [HttpResponse] (returned by [HttpRequest.waitForCompletion|request.waitForCompletion]).

+/
unittest {
	import arsd.http2;

	void main() {
		auto client = new HttpClient();
		auto request = client.navigateTo(Uri("http://dlang.org/"));
		auto response = request.waitForCompletion();

		string returnedHtml = response.contentText;
	}
}

// FIXME: multipart encoded file uploads needs implementation
// future: do web client api stuff

debug import std.stdio;

import std.socket;
import core.time;

// FIXME: check Transfer-Encoding: gzip always

version(with_openssl) {
	//pragma(lib, "crypto");
	//pragma(lib, "ssl");
}

/+
HttpRequest httpRequest(string method, string url, ubyte[] content, string[string] content) {
	return null;
}
+/

/**
	auto request = get("http://arsdnet.net/");
	request.send();

	auto response = get("http://arsdnet.net/").waitForCompletion();
*/
HttpRequest get(string url) {
	auto client = new HttpClient();
	auto request = client.navigateTo(Uri(url));
	return request;
}

/**
	Do not forget to call `waitForCompletion()` on the returned object!
*/
HttpRequest post(string url, string[string] req) {
	auto client = new HttpClient();
	ubyte[] bdata;
	foreach(k, v; req) {
		if(bdata.length)
			bdata ~= cast(ubyte[]) "&";
		bdata ~= cast(ubyte[]) encodeComponent(k);
		bdata ~= cast(ubyte[]) "=";
		bdata ~= cast(ubyte[]) encodeComponent(v);
	}
	auto request = client.request(Uri(url), HttpVerb.POST, bdata, "application/x-www-form-urlencoded");
	return request;
}

/// gets the text off a url. basic operation only.
string getText(string url) {
	auto request = get(url);
	auto response = request.waitForCompletion();
	return cast(string) response.content;
}

/+
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

///
struct HttpResponse {
	int code; ///
	string codeText; ///

	string httpVersion; ///

	string statusLine; ///

	string contentType; /// The content type header
	string location; /// The location header

	/// the charset out of content type, if present. `null` if not.
	string contentTypeCharset() {
		auto idx = contentType.indexOf("charset=");
		if(idx == -1)
			return null;
		auto c = contentType[idx + "charset=".length .. $].strip;
		if(c.length)
			return c;
		return null;
	}

	string[string] cookies; /// Names and values of cookies set in the response.

	string[] headers; /// Array of all headers returned.
	string[string] headersHash; ///

	ubyte[] content; /// The raw content returned in the response body.
	string contentText; /// [content], but casted to string (for convenience)

	/++
		returns `new Document(this.contentText)`. Requires [arsd.dom].
	+/
	auto contentDom()() {
		import arsd.dom;
		return new Document(this.contentText);

	}

	/++
		returns `var.fromJson(this.contentText)`. Requires [arsd.jsvar].
	+/
	auto contentJson()() {
		import arsd.jsvar;
		return var.fromJson(this.contentText);
	}

	HttpRequestParameters requestParameters; ///

	LinkHeader[] linksStored;
	bool linksLazilyParsed;

	/// Returns links header sorted by "rel" attribute.
	/// It returns a new array on each call.
	LinkHeader[string] linksHash() {
		auto links = this.links();
		LinkHeader[string] ret;
		foreach(link; links)
			ret[link.rel] = link;
		return ret;
	}

	/// Returns the Link header, parsed.
	LinkHeader[] links() {
		if(linksLazilyParsed)
			return linksStored;
		linksLazilyParsed = true;
		LinkHeader[] ret;

		auto hdrPtr = "Link" in headersHash;
		if(hdrPtr is null)
			return ret;

		auto header = *hdrPtr;

		LinkHeader current;

		while(header.length) {
			char ch = header[0];

			if(ch == '<') {
				// read url
				header = header[1 .. $];
				size_t idx;
				while(idx < header.length && header[idx] != '>')
					idx++;
				current.url = header[0 .. idx];
				header = header[idx .. $];
			} else if(ch == ';') {
				// read attribute
				header = header[1 .. $];
				header = header.stripLeft;

				size_t idx;
				while(idx < header.length && header[idx] != '=')
					idx++;

				string name = header[0 .. idx];
				header = header[idx + 1 .. $];

				string value;

				if(header.length && header[0] == '"') {
					// quoted value
					header = header[1 .. $];
					idx = 0;
					while(idx < header.length && header[idx] != '\"')
						idx++;
					value = header[0 .. idx];
					header = header[idx .. $];

				} else if(header.length) {
					// unquoted value
					idx = 0;
					while(idx < header.length && header[idx] != ',' && header[idx] != ' ' && header[idx] != ';')
						idx++;

					value = header[0 .. idx];
					header = header[idx .. $].stripLeft;
				}

				name = name.toLower;
				if(name == "rel")
					current.rel = value;
				else
					current.attributes[name] = value;

			} else if(ch == ',') {
				// start another
				ret ~= current;
				current = LinkHeader.init;
			} else if(ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') {
				// ignore
			}

			header = header[1 .. $];
		}

		ret ~= current;

		linksStored = ret;

		return ret;
	}
}

///
struct LinkHeader {
	string url; ///
	string rel; ///
	string[string] attributes; /// like title, rev, media, whatever attributes
}

import std.string;
static import std.algorithm;
import std.conv;
import std.range;


private AddressFamily family(string unixSocketPath) {
	if(unixSocketPath.length)
		return AddressFamily.UNIX;
	else // FIXME: what about ipv6?
		return AddressFamily.INET;
}

version(Windows)
private class UnixAddress : Address {
	this(string) {
		throw new Exception("No unix address support on this system in lib yet :(");
	}
	override sockaddr* name() { assert(0); }
	override const(sockaddr)* name() const { assert(0); }
	override int nameLen() const { assert(0); }
}


// Copy pasta from cgi.d, then stripped down. unix path thing added tho
///
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

	private string unixSocketPath = null;
	/// Indicates it should be accessed through a unix socket instead of regular tcp. Returns new version without modifying this object.
	Uri viaUnixSocket(string path) const {
		Uri copy = this;
		copy.unixSocketPath = path;
		return copy;
	}

	/// Goes through a unix socket in the abstract namespace (linux only). Returns new version without modifying this object.
	version(linux)
	Uri viaAbstractSocket(string path) const {
		Uri copy = this;
		copy.unixSocketPath = "\0" ~ path;
		return copy;
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

		n.removeDots();

		// if still basically talking to the same thing, we should inherit the unix path
		// too since basically the unix path is saying for this service, always use this override.
		if(n.host == baseUrl.host && n.scheme == baseUrl.scheme && n.port == baseUrl.port)
			n.unixSocketPath = baseUrl.unixSocketPath;

		return n;
	}

	void removeDots() {
		auto parts = this.path.split("/");
		string[] toKeep;
		foreach(part; parts) {
			if(part == ".") {
				continue;
			} else if(part == "..") {
				toKeep = toKeep[0 .. $-1];
				continue;
			} else {
				toKeep ~= part;
			}
		}

		this.path = toKeep.join("/");
	}

}

/*
void main(string args[]) {
	write(post("http://arsdnet.net/bugs.php", ["test" : "hey", "again" : "what"]));
}
*/

///
struct BasicAuth {
	string username; ///
	string password; ///
}

/**
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

	/// Automatically follow a redirection?
	bool followLocation = false;

	this() {
	}

	///
	this(Uri where, HttpVerb method) {
		populateFromInfo(where, method);
	}

	/// Final url after any redirections
	string finalUrl;

	void populateFromInfo(Uri where, HttpVerb method) {
		auto parts = where;
		finalUrl = where.toString();
		requestParameters.method = method;
		requestParameters.unixSocketPath = where.unixSocketPath;
		requestParameters.host = parts.host;
		requestParameters.port = cast(ushort) parts.port;
		requestParameters.ssl = parts.scheme == "https";
		if(parts.port == 0)
			requestParameters.port = requestParameters.ssl ? 443 : 80;
		requestParameters.uri = parts.path.length ? parts.path : "/";
		if(parts.query.length) {
			requestParameters.uri ~= "?";
			requestParameters.uri ~= parts.query;
		}
	}

	~this() {
	}

	ubyte[] sendBuffer;

	HttpResponse responseData;
	private HttpClient parentClient;

	size_t bodyBytesSent;
	size_t bodyBytesReceived;

	State state_;
	State state() { return state_; }
	State state(State s) {
		assert(state_ != State.complete);
		return state_ = s;
	}
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
		sendPrivate(true);
	}

	private void sendPrivate(bool advance) {
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
		if(requestParameters.contentType.length)
			headers ~= "Content-Type: "~requestParameters.contentType~"\r\n";
		if(requestParameters.authorization.length)
			headers ~= "Authorization: "~requestParameters.authorization~"\r\n";
		if(requestParameters.bodyData.length)
			headers ~= "Content-Length: "~to!string(requestParameters.bodyData.length)~"\r\n";
		if(requestParameters.acceptGzip)
			headers ~= "Accept-Encoding: gzip\r\n";
		if(requestParameters.keepAlive)
			headers ~= "Connection: keep-alive\r\n";

		foreach(header; requestParameters.headers)
			headers ~= header ~ "\r\n";

		headers ~= "\r\n";

		sendBuffer = cast(ubyte[]) headers ~ requestParameters.bodyData;

		// import std.stdio; writeln("******* ", sendBuffer);

		responseData = HttpResponse.init;
		responseData.requestParameters = requestParameters;
		bodyBytesSent = 0;
		bodyBytesReceived = 0;
		state = State.pendingAvailableConnection;

		bool alreadyPending = false;
		foreach(req; pending)
			if(req is this) {
				alreadyPending = true;
				break;
			}
		if(!alreadyPending) {
			pending ~= this;
		}

		if(advance)
			HttpRequest.advanceConnections();
	}


	/// Waits for the request to finish or timeout, whichever comes first.
	HttpResponse waitForCompletion() {
		while(state != State.aborted && state != State.complete) {
			if(state == State.unsent)
				send();
			if(auto err = HttpRequest.advanceConnections())
				throw new Exception("waitForCompletion got err " ~ to!string(err));
		}

		return responseData;
	}

	/// Aborts this request.
	void abort() {
		this.state = State.aborted;
		// FIXME
	}

	HttpRequestParameters requestParameters; ///

	version(arsd_http_winhttp_implementation) {
		public static void resetInternals() {

		}

		static assert(0, "implementation not finished");
	}


	version(arsd_http_internal_implementation) {
	private static {
		// we manage the actual connections. When a request is made on a particular
		// host, we try to reuse connections. We may open more than one connection per
		// host to do parallel requests.
		//
		// The key is the *domain name* and the port. Multiple domains on the same address will have separate connections.
		Socket[][string] socketsPerHost;

		void loseSocket(string host, ushort port, bool ssl, Socket s) {
			import std.string;
			auto key = format("http%s://%s:%s", ssl ? "s" : "", host, port);

			if(auto list = key in socketsPerHost) {
				for(int a = 0; a < (*list).length; a++) {
					if((*list)[a] is s) {

						for(int b = a; b < (*list).length - 1; b++)
							(*list)[b] = (*list)[b+1];
						(*list) = (*list)[0 .. $-1];
						break;
					}
				}
			}
		}

		Socket getOpenSocketOnHost(string host, ushort port, bool ssl, string unixSocketPath) {

			Socket openNewConnection() {
				Socket socket;
				if(ssl) {
					version(with_openssl)
						socket = new SslClientSocket(family(unixSocketPath), SocketType.STREAM, host);
					else
						throw new Exception("SSL not compiled in");
				} else
					socket = new Socket(family(unixSocketPath), SocketType.STREAM);

				if(unixSocketPath) {
					import std.stdio; writeln(cast(ubyte[]) unixSocketPath);
					socket.connect(new UnixAddress(unixSocketPath));
				} else {
					// FIXME: i should prolly do ipv6 if available too.
					socket.connect(new InternetAddress(host, port));
				}

				debug(arsd_http2) writeln("opening to ", host, ":", port, " ", cast(void*) socket);
				assert(socket.handle() !is socket_t.init);
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
						static SocketSet readSet = null;
						if(readSet is null)
							readSet = new SocketSet();
						readSet.reset();
						assert(socket.handle() !is socket_t.init, socket is null ? "null" : socket.toString());
						readSet.add(socket);
						auto got = Socket.select(readSet, null, null, 5.msecs /* timeout */);
						if(got > 0) {
							// we can read something off this... but there aren't
							// any active requests. Assume it is EOF and open a new one

							socket.close();
							loseSocket(host, port, ssl, socket);
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


		int advanceConnections() {
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

				auto socket = getOpenSocketOnHost(pc.requestParameters.host, pc.requestParameters.port, pc.requestParameters.ssl, pc.requestParameters.unixSocketPath);

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

			bool hadOne = false;

			// active requests need to be read or written to
			foreach(sock, request; activeRequestOnSocket) {
				// check the other sockets just for EOF, if they close, take them out of our list,
				// we'll reopen if needed upon request.
				readSet.add(sock);
				hadOne = true;
				if(request.state == State.sendingHeaders || request.state == State.sendingBody) {
					writeSet.add(sock);
					hadOne = true;
				}
			}

			if(!hadOne)
				return 1; // automatic timeout, nothing to do

			tryAgain:
			auto selectGot = Socket.select(readSet, writeSet, null, 10.seconds /* timeout */);
			if(selectGot == 0) { /* timeout */
				// timeout
				return 1;
			} else if(selectGot == -1) { /* interrupted */
				/*
				version(Posix) {
					import core.stdc.errno;
					if(errno != EINTR)
						throw new Exception("select error: " ~ to!string(errno));
				}
				*/
				goto tryAgain;
			} else { /* ready */
				Socket[16] inactive;
				int inactiveCount = 0;
				foreach(sock, request; activeRequestOnSocket) {
					if(readSet.isSet(sock)) {
						keep_going:
						auto got = sock.receive(buffer);
						debug(arsd_http2_verbose) writeln("====PACKET ",got,"=====",cast(string)buffer[0 .. got],"===/PACKET===");
						if(got < 0) {
							throw new Exception("receive error");
						} else if(got == 0) {
							// remote side disconnected
							debug(arsd_http2) writeln("remote disconnect");
							if(request.state != State.complete)
								request.state = State.aborted;
							inactive[inactiveCount++] = sock;
							sock.close();
							loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
						} else {
							// data available
							auto stillAlive = request.handleIncomingData(buffer[0 .. got]);

							if(!stillAlive || request.state == HttpRequest.State.complete || request.state == HttpRequest.State.aborted) {
								//import std.stdio; writeln(cast(void*) sock, " ", stillAlive, " ", request.state);
								inactive[inactiveCount++] = sock;
								continue;
							// reuse the socket for another pending request, if we can
							}
						}

						if(request.onDataReceived)
							request.onDataReceived(request);

						version(with_openssl)
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
						debug(arsd_http2_verbose) writeln(cast(void*) sock, "<send>", cast(string) request.sendBuffer, "</send>");
						if(sent <= 0)
							throw new Exception("send error " ~ lastSocketError);
						request.sendBuffer = request.sendBuffer[sent .. $];
						if(request.sendBuffer.length == 0) {
							request.state = State.waitingForResponse;
						}
					}
				}

				foreach(s; inactive[0 .. inactiveCount]) {
					debug(arsd_http2) writeln("removing socket from active list ", cast(void*) s);
					activeRequestOnSocket.remove(s);
				}
			}

			// we've completed a request, are there any more pending connection? if so, send them now

			return 0;
		}
	}

	public static void resetInternals() {
		socketsPerHost = null;
		activeRequestOnSocket = null;
		pending = null;

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

	const(ubyte)[] leftoverDataFromLastTime;

	bool handleIncomingData(scope const ubyte[] dataIn) {
		bool stillAlive = true;
		debug(arsd_http2) writeln("handleIncomingData, state: ", state);
		if(state == State.waitingForResponse) {
			state = State.readingHeaders;
			headerReadingState = HeaderReadingState.init;
			bodyReadingState = BodyReadingState.init;
		}

		const(ubyte)[] data;
		if(leftoverDataFromLastTime.length)
			data = leftoverDataFromLastTime ~ dataIn[];
		else
			data = dataIn[];

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
					if(colon + 1 == header.length || colon + 2 == header.length) // assuming a space there
						return; // empty header, idk
					assert(colon + 2 < header.length, header);
					auto value = header[colon + 2 .. $]; // skipping the colon itself and the following space

					switch(name) {
						case "Connection":
						case "connection":
							if(value == "close")
								closeSocketWhenComplete = true;
						break;
						case "Content-Type":
						case "content-type":
							responseData.contentType = value;
						break;
						case "Location":
						case "location":
							responseData.location = value;
						break;
						case "Content-Length":
						case "content-length":
							bodyReadingState.contentLengthRemaining = to!int(value);
						break;
						case "Transfer-Encoding":
						case "transfer-encoding":
							// note that if it is gzipped, it zips first, then chunks the compressed stream.
							// so we should always dechunk first, then feed into the decompressor
							if(value.strip == "chunked")
								bodyReadingState.isChunked = true;
							else throw new Exception("Unknown Transfer-Encoding: " ~ value);
						break;
						case "Content-Encoding":
						case "content-encoding":
							if(value == "gzip") {
								bodyReadingState.isGzipped = true;
								uncompress = new UnCompress();
							} else if(value == "deflate") {
								bodyReadingState.isDeflated = true;
								uncompress = new UnCompress();
							} else throw new Exception("Unknown Content-Encoding: " ~ value);
						break;
						case "Set-Cookie":
						case "set-cookie":
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
								assert(a != 0, cast(string) data);
								for(int b = a-1; b >= 0; b--) {
									char cc = data[b];
									if(cc >= 'a' && cc <= 'z')
										cc -= 0x20;
									int val = 0;
									if(cc >= '0' && cc <= '9')
										val = cc - '0';
									else
										val = cc - 'A' + 10;

									assert(val >= 0 && val <= 15, to!string(val));
									bodyReadingState.contentLengthRemaining += power * val;
									power *= 16;
								}
								debug(arsd_http2_verbose) writeln("Chunk length: ", bodyReadingState.contentLengthRemaining);
								bodyReadingState.chunkedState = 1;
								data = data[a + 1 .. $];
								goto start_over;
							}
						break;
						case 1: // reading until end of line
							char c = data[a];
							if(c == '\n') {
								if(bodyReadingState.contentLengthRemaining == 0)
									bodyReadingState.chunkedState = 5;
								else
									bodyReadingState.chunkedState = 2;
							}
							data = data[a + 1 .. $];
							goto start_over;
						case 2: // reading data
							auto can = a + bodyReadingState.contentLengthRemaining;
							if(can > data.length)
								can = cast(int) data.length;

							auto newData = data[a .. can];
							data = data[can .. $];

							//if(bodyReadingState.isGzipped || bodyReadingState.isDeflated)
							//	responseData.content ~= cast(ubyte[]) uncompress.uncompress(data[a .. can]);
							//else
								responseData.content ~= newData;

							bodyReadingState.contentLengthRemaining -= newData.length;
							debug(arsd_http2_verbose) writeln("clr: ", bodyReadingState.contentLengthRemaining, " " , a, " ", can);
							assert(bodyReadingState.contentLengthRemaining >= 0);
							if(bodyReadingState.contentLengthRemaining == 0) {
								bodyReadingState.chunkedState = 3;
							} else {
								// will continue grabbing more
							}
							goto start_over;
						case 3: // reading 13/10
							assert(data[a] == 13);
							bodyReadingState.chunkedState++;
							data = data[a + 1 .. $];
							goto start_over;
						case 4: // reading 10 at end of packet
							assert(data[a] == 10);
							data = data[a + 1 .. $];
							bodyReadingState.chunkedState = 0;
							goto start_over;
						case 5: // reading footers
							//goto done; // FIXME
							state = State.complete;

							bodyReadingState.chunkedState = 0;

							while(data[a] != 10)
								a++;
							data = data[a + 1 .. $];

							if(bodyReadingState.isGzipped || bodyReadingState.isDeflated) {
								auto n = uncompress.uncompress(responseData.content);
								n ~= uncompress.flush();
								responseData.content = cast(ubyte[]) n;
							}

							//	responseData.content ~= cast(ubyte[]) uncompress.flush();

							responseData.contentText = cast(string) responseData.content;

							goto done;
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
				//assert(data.length <= bodyReadingState.contentLengthRemaining, format("%d <= %d\n%s", data.length, bodyReadingState.contentLengthRemaining, cast(string)data));
				int use = cast(int) data.length;
				if(use > bodyReadingState.contentLengthRemaining)
					use = bodyReadingState.contentLengthRemaining;
				bodyReadingState.contentLengthRemaining -= use;
				data = data[use .. $];
				if(bodyReadingState.contentLengthRemaining == 0) {
					if(bodyReadingState.isGzipped || bodyReadingState.isDeflated) {
						auto n = uncompress.uncompress(responseData.content);
						n ~= uncompress.flush();
						responseData.content = cast(ubyte[]) n;
						//responseData.content ~= cast(ubyte[]) uncompress.flush();
					}
					if(followLocation && responseData.location.length) {
						static bool first = true;
						//version(DigitalMars) if(!first) asm { int 3; }
						populateFromInfo(Uri(responseData.location), HttpVerb.GET);
						import std.stdio; writeln("redirected to ", responseData.location);
						first = false;
						responseData = HttpResponse.init;
						headerReadingState = HeaderReadingState.init;
						bodyReadingState = BodyReadingState.init;
						state = State.unsent;
						stillAlive = false;
						sendPrivate(false);
					} else {
						state = State.complete;
						responseData.contentText = cast(string) responseData.content;
						// FIXME
						//if(closeSocketWhenComplete)
							//socket.close();
					}
				}
			}
		}

		if(data.length)
			leftoverDataFromLastTime = data.dup;
		else
			leftoverDataFromLastTime = null;

		return stillAlive;
	}

	}
}

///
struct HttpRequestParameters {
	// Duration timeout;

	// debugging
	bool useHttp11 = true; ///
	bool acceptGzip = true; ///
	bool keepAlive = true; ///

	// the request itself
	HttpVerb method; ///
	string host; ///
	ushort port; ///
	string uri; ///

	bool ssl; ///

	string userAgent; ///
	string authorization; ///

	string[string] cookies; ///

	string[] headers; /// do not duplicate host, content-length, content-type, or any others that have a specific property

	string contentType; ///
	ubyte[] bodyData; ///

	string unixSocketPath;
}

interface IHttpClient {

}

///
enum HttpVerb {
	///
	GET,
	///
	HEAD,
	///
	POST,
	///
	PUT,
	///
	DELETE,
	///
	OPTIONS,
	///
	TRACE,
	///
	CONNECT,
	///
	PATCH,
	///
	MERGE
}

/**
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
	bool useHttp11 = true; ///
	bool acceptGzip = true; ///
	bool keepAlive = true; ///

	///
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

		request.followLocation = true;

		request.requestParameters.userAgent = userAgent;
		request.requestParameters.authorization = authorization;

		request.requestParameters.useHttp11 = this.useHttp11;
		request.requestParameters.acceptGzip = this.acceptGzip;
		request.requestParameters.keepAlive = this.keepAlive;

		return request;
	}

	/++
		Creates a request without updating the current url state
		(but will still save cookies btw)

	+/
	HttpRequest request(Uri uri, HttpVerb method = HttpVerb.GET, ubyte[] bodyData = null, string contentType = null) {
		auto request = new HttpRequest(uri, method);

		request.requestParameters.userAgent = userAgent;
		request.requestParameters.authorization = authorization;

		request.requestParameters.useHttp11 = this.useHttp11;
		request.requestParameters.acceptGzip = this.acceptGzip;
		request.requestParameters.keepAlive = this.keepAlive;

		request.requestParameters.bodyData = bodyData;
		request.requestParameters.contentType = contentType;

		return request;

	}

	/// ditto
	HttpRequest request(Uri uri, FormData fd, HttpVerb method = HttpVerb.POST) {
		return request(uri, method, fd.toBytes, fd.contentType);
	}


	private Uri currentUrl;
	private string currentDomain;

	this(ICache cache = null) {

	}

	// FIXME: add proxy
	// FIXME: some kind of caching

	///
	void setCookie(string name, string value, string domain = null) {
		if(domain == null)
			domain = currentDomain;

		cookies[domain][name] = value;
	}

	///
	void clearCookies(string domain = null) {
		if(domain is null)
			cookies = null;
		else
			cookies[domain] = null;
	}

	// If you set these, they will be pre-filled on all requests made with this client
	string userAgent = "D arsd.html2"; ///
	string authorization; ///

	/* inter-request state */
	string[string][string] cookies;
}

interface ICache {
	HttpResponse* getCachedResponse(HttpRequestParameters request);
}

// / Provides caching behavior similar to a real web browser
class HttpCache : ICache {
	HttpResponse* getCachedResponse(HttpRequestParameters request) {
		return null;
	}
}

// / Gives simple maximum age caching, ignoring the actual http headers
class SimpleCache : ICache {
	HttpResponse* getCachedResponse(HttpRequestParameters request) {
		return null;
	}
}

///
struct HttpCookie {
	string name; ///
	string value; ///
	string domain; ///
	string path; ///
	//SysTime expirationDate; ///
	bool secure; ///
	bool httpOnly; ///
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


// From sslsocket.d, but this is the maintained version!
version(use_openssl) {
	alias SslClientSocket = OpenSslSocket;

	// macros in the original C
	SSL_METHOD* SSLv23_client_method() {
		if(ossllib.SSLv23_client_method)
			return ossllib.SSLv23_client_method();
		else
			return ossllib.TLS_client_method();
	}

	struct SSL {}
	struct SSL_CTX {}
	struct SSL_METHOD {}
	enum SSL_VERIFY_NONE = 0;

	struct ossllib {
		__gshared static extern(C) {
			/* these are only on older openssl versions { */
				int function() SSL_library_init;
				void function() SSL_load_error_strings;
				SSL_METHOD* function() SSLv23_client_method;
			/* } */

			void function(ulong, void*) OPENSSL_init_ssl;

			SSL_CTX* function(const SSL_METHOD*) SSL_CTX_new;
			SSL* function(SSL_CTX*) SSL_new;
			int function(SSL*, int) SSL_set_fd;
			int function(SSL*) SSL_connect;
			int function(SSL*, const void*, int) SSL_write;
			int function(SSL*, void*, int) SSL_read;
			@trusted nothrow @nogc int function(SSL*) SSL_shutdown;
			void function(SSL*) SSL_free;
			void function(SSL_CTX*) SSL_CTX_free;

			int function(const SSL*) SSL_pending;

			void function(SSL*, int, void*) SSL_set_verify;

			void function(SSL*, int, c_long, void*) SSL_ctrl;

			SSL_METHOD* function() SSLv3_client_method;
			SSL_METHOD* function() TLS_client_method;

		}
	}

	import core.stdc.config;

	struct eallib {
		__gshared static extern(C) {
			/* these are only on older openssl versions { */
				void function() OpenSSL_add_all_ciphers;
				void function() OpenSSL_add_all_digests;
			/* } */

			void function(ulong, void*) OPENSSL_init_crypto;

			void function(FILE*) ERR_print_errors_fp;
		}
	}


	SSL_CTX* SSL_CTX_new(const SSL_METHOD* a) {
		if(ossllib.SSL_CTX_new)
			return ossllib.SSL_CTX_new(a);
		else throw new Exception("SSL_CTX_new not loaded");
	}
	SSL* SSL_new(SSL_CTX* a) {
		if(ossllib.SSL_new)
			return ossllib.SSL_new(a);
		else throw new Exception("SSL_new not loaded");
	}
	int SSL_set_fd(SSL* a, int b) {
		if(ossllib.SSL_set_fd)
			return ossllib.SSL_set_fd(a, b);
		else throw new Exception("SSL_set_fd not loaded");
	}
	int SSL_connect(SSL* a) {
		if(ossllib.SSL_connect)
			return ossllib.SSL_connect(a);
		else throw new Exception("SSL_connect not loaded");
	}
	int SSL_write(SSL* a, const void* b, int c) {
		if(ossllib.SSL_write)
			return ossllib.SSL_write(a, b, c);
		else throw new Exception("SSL_write not loaded");
	}
	int SSL_read(SSL* a, void* b, int c) {
		if(ossllib.SSL_read)
			return ossllib.SSL_read(a, b, c);
		else throw new Exception("SSL_read not loaded");
	}
	@trusted nothrow @nogc int SSL_shutdown(SSL* a) {
		if(ossllib.SSL_shutdown)
			return ossllib.SSL_shutdown(a);
		assert(0);
	}
	void SSL_free(SSL* a) {
		if(ossllib.SSL_free)
			return ossllib.SSL_free(a);
		else throw new Exception("SSL_free not loaded");
	}
	void SSL_CTX_free(SSL_CTX* a) {
		if(ossllib.SSL_CTX_free)
			return ossllib.SSL_CTX_free(a);
		else throw new Exception("SSL_CTX_free not loaded");
	}

	int SSL_pending(const SSL* a) {
		if(ossllib.SSL_pending)
			return ossllib.SSL_pending(a);
		else throw new Exception("SSL_pending not loaded");
	}
	void SSL_set_verify(SSL* a, int b, void* c) {
		if(ossllib.SSL_set_verify)
			return ossllib.SSL_set_verify(a, b, c);
		else throw new Exception("SSL_set_verify not loaded");
	}
	void SSL_set_tlsext_host_name(SSL* a, const char* b) {
		if(ossllib.SSL_ctrl)
			return ossllib.SSL_ctrl(a, 55 /*SSL_CTRL_SET_TLSEXT_HOSTNAME*/, 0 /*TLSEXT_NAMETYPE_host_name*/, cast(void*) b);
		else throw new Exception("SSL_set_tlsext_host_name not loaded");
	}

	SSL_METHOD* SSLv3_client_method() {
		if(ossllib.SSLv3_client_method)
			return ossllib.SSLv3_client_method();
		else throw new Exception("SSLv3_client_method not loaded");
	}
	SSL_METHOD* TLS_client_method() {
		if(ossllib.TLS_client_method)
			return ossllib.TLS_client_method();
		else throw new Exception("TLS_client_method not loaded");
	}
	void ERR_print_errors_fp(FILE* a) {
		if(eallib.ERR_print_errors_fp)
			return eallib.ERR_print_errors_fp(a);
		else throw new Exception("ERR_print_errors_fp not loaded");
	}


	private __gshared void* ossllib_handle;
	version(Windows)
		private __gshared void* oeaylib_handle;
	else
		alias oeaylib_handle = ossllib_handle;
	version(Posix)
		private import core.sys.posix.dlfcn;
	else version(Windows)
		private import core.sys.windows.windows;

	import core.stdc.stdio;

	shared static this() {
		version(Posix)
			ossllib_handle = dlopen("libssl.so", RTLD_NOW);
		else version(Windows) {
			ossllib_handle = LoadLibraryW("libssl32.dll"w.ptr);
			oeaylib_handle = LoadLibraryW("libeay32.dll"w.ptr);
		}

		if(ossllib_handle is null)
			throw new Exception("ssl fail open");

		foreach(memberName; __traits(allMembers, ossllib)) {
			alias t = typeof(__traits(getMember, ossllib, memberName));
			version(Posix)
				__traits(getMember, ossllib, memberName) = cast(t) dlsym(ossllib_handle, memberName);
			else version(Windows) {
				__traits(getMember, ossllib, memberName) = cast(t) GetProcAddress(ossllib_handle, memberName);
			}
		}

		foreach(memberName; __traits(allMembers, eallib)) {
			alias t = typeof(__traits(getMember, eallib, memberName));
			version(Posix)
				__traits(getMember, eallib, memberName) = cast(t) dlsym(oeaylib_handle, memberName);
			else version(Windows) {
				__traits(getMember, eallib, memberName) = cast(t) GetProcAddress(oeaylib_handle, memberName);
			}
		}


		if(ossllib.SSL_library_init)
			ossllib.SSL_library_init();
		else if(ossllib.OPENSSL_init_ssl)
			ossllib.OPENSSL_init_ssl(0, null);
		else throw new Exception("couldn't init openssl");

		if(eallib.OpenSSL_add_all_ciphers) {
			eallib.OpenSSL_add_all_ciphers();
			if(eallib.OpenSSL_add_all_digests is null)
				throw new Exception("no add digests");
			eallib.OpenSSL_add_all_digests();
		} else if(eallib.OPENSSL_init_crypto)
			eallib.OPENSSL_init_crypto(0 /*OPENSSL_INIT_ADD_ALL_CIPHERS and ALL_DIGESTS together*/, null);
		else throw new Exception("couldn't init crypto openssl");

		if(ossllib.SSL_load_error_strings)
			ossllib.SSL_load_error_strings();
		else if(ossllib.OPENSSL_init_ssl)
			ossllib.OPENSSL_init_ssl(0x00200000L, null);
		else throw new Exception("couldn't load openssl errors");
	}

	/+
		// I'm just gonna let the OS clean this up on process termination because otherwise SSL_free
		// might have trouble being run from the GC after this module is unloaded.
	shared static ~this() {
		if(ossllib_handle) {
			version(Windows) {
				FreeLibrary(oeaylib_handle);
				FreeLibrary(ossllib_handle);
			} else version(Posix)
				dlclose(ossllib_handle);
			ossllib_handle = null;
		}
		ossllib.tupleof = ossllib.tupleof.init;
	}
	+/

	//pragma(lib, "crypto");
	//pragma(lib, "ssl");

	class OpenSslSocket : Socket {
		private SSL* ssl;
		private SSL_CTX* ctx;
		private void initSsl(bool verifyPeer, string hostname) {
			ctx = SSL_CTX_new(SSLv23_client_method());
			assert(ctx !is null);

			ssl = SSL_new(ctx);

			if(hostname.length)
			SSL_set_tlsext_host_name(ssl, toStringz(hostname));

			if(!verifyPeer)
				SSL_set_verify(ssl, SSL_VERIFY_NONE, null);
			SSL_set_fd(ssl, cast(int) this.handle); // on win64 it is necessary to truncate, but the value is never large anyway see http://openssl.6102.n7.nabble.com/Sockets-windows-64-bit-td36169.html
		}

		bool dataPending() {
			return SSL_pending(ssl) > 0;
		}

		@trusted
		override void connect(Address to) {
			super.connect(to);
			if(SSL_connect(ssl) == -1) {
				ERR_print_errors_fp(core.stdc.stdio.stderr);
				int i;
				//printf("wtf\n");
				//scanf("%d\n", i);
				throw new Exception("ssl connect");
			}
		}
		
		@trusted
		override ptrdiff_t send(scope const(void)[] buf, SocketFlags flags) {
		//import std.stdio;writeln(cast(string) buf);
			auto retval = SSL_write(ssl, buf.ptr, cast(uint) buf.length);
			if(retval == -1) {
				ERR_print_errors_fp(core.stdc.stdio.stderr);
				int i;
				//printf("wtf\n");
				//scanf("%d\n", i);
				throw new Exception("ssl send");
			}
			return retval;

		}
		override ptrdiff_t send(scope const(void)[] buf) {
			return send(buf, SocketFlags.NONE);
		}
		@trusted
		override ptrdiff_t receive(scope void[] buf, SocketFlags flags) {
			auto retval = SSL_read(ssl, buf.ptr, cast(int)buf.length);
			if(retval == -1) {
				ERR_print_errors_fp(core.stdc.stdio.stderr);
				int i;
				//printf("wtf\n");
				//scanf("%d\n", i);
				throw new Exception("ssl send");
			}
			return retval;
		}
		override ptrdiff_t receive(scope void[] buf) {
			return receive(buf, SocketFlags.NONE);
		}

		this(AddressFamily af, SocketType type = SocketType.STREAM, string hostname = null, bool verifyPeer = true) {
			super(af, type);
			initSsl(verifyPeer, hostname);
		}

		override void close() {
			if(ssl) SSL_shutdown(ssl);
			super.close();
		}

		this(socket_t sock, AddressFamily af, string hostname) {
			super(sock, af);
			initSsl(true, hostname);
		}

		~this() {
			SSL_free(ssl);
			SSL_CTX_free(ctx);
			ssl = null;
		}
	}
}

/++
	An experimental component for working with REST apis. Note that it
	is a zero-argument template, so to create one, use `new HttpApiClient!()(args..)`
	or you will get "HttpApiClient is used as a type" compile errors.

	This will probably not work for you yet, and I might change it significantly.

	Requires [arsd.jsvar].


	Here's a snippet to create a pull request on GitHub to Phobos:

	---
	auto github = new HttpApiClient!()("https://api.github.com/", "your personal api token here");

	// create the arguments object
	// see: https://developer.github.com/v3/pulls/#create-a-pull-request
	var args = var.emptyObject;
	args.title = "My Pull Request";
	args.head = "yourusername:" ~ branchName;
	args.base = "master";
	// note it is ["body"] instead of .body because `body` is a D keyword
	args["body"] = "My cool PR is opened by the API!";
	args.maintainer_can_modify = true;

	// this translates to `repos/dlang/phobos/pulls` and sends a POST request,
	// containing `args` as json, then immediately grabs the json result and extracts
	// the value `html_url` from it. `prUrl` is typed `var`, from arsd.jsvar.
	auto prUrl = github.rest.repos.dlang.phobos.pulls.POST(args).result.html_url;

	writeln("Created: ", prUrl);
	---

	Why use this instead of just building the URL? Well, of course you can! This just makes
	it a bit more convenient than string concatenation and manages a few headers for you.

	Subtypes could potentially add static type checks too.
+/
class HttpApiClient() {
	import arsd.jsvar;

	HttpClient httpClient;

	alias HttpApiClientType = typeof(this);

	string urlBase;
	string oauth2Token;
	string submittedContentType;

	/++
		Params:

		urlBase = The base url for the api. Tends to be something like `https://api.example.com/v2/` or similar.
		oauth2Token = the authorization token for the service. You'll have to get it from somewhere else.
		submittedContentType = the content-type of POST, PUT, etc. bodies.
	+/
	this(string urlBase, string oauth2Token, string submittedContentType = "application/json") {
		httpClient = new HttpClient();

		assert(urlBase[0] == 'h');
		assert(urlBase[$-1] == '/');

		this.urlBase = urlBase;
		this.oauth2Token = oauth2Token;
		this.submittedContentType = submittedContentType;
	}

	///
	static struct HttpRequestWrapper {
		HttpApiClientType apiClient; ///
		HttpRequest request; ///
		HttpResponse _response;

		///
		this(HttpApiClientType apiClient, HttpRequest request) {
			this.apiClient = apiClient;
			this.request = request;
		}

		/// Returns the full [HttpResponse] object so you can inspect the headers
		@property HttpResponse response() {
			if(_response is HttpResponse.init)
				_response = request.waitForCompletion();
			return _response;
		}

		/++
			Returns the parsed JSON from the body of the response.

			Throws on non-2xx responses.
		+/
		var result() {
			return apiClient.throwOnError(response);
		}

		alias request this;
	}

	///
	HttpRequestWrapper request(string uri, HttpVerb requestMethod = HttpVerb.GET, ubyte[] bodyBytes = null) {
		if(uri[0] == '/')
			uri = uri[1 .. $];

		auto u = Uri(uri).basedOn(Uri(urlBase));

		auto req = httpClient.navigateTo(u, requestMethod);

		if(oauth2Token.length)
			req.requestParameters.headers ~= "Authorization: Bearer " ~ oauth2Token;
		req.requestParameters.contentType = submittedContentType;
		req.requestParameters.bodyData = bodyBytes;

		return HttpRequestWrapper(this, req);
	}

	///
	var throwOnError(HttpResponse res) {
		if(res.code < 200 || res.code >= 300)
			throw new Exception(res.codeText ~ " " ~ res.contentText);

		var response = var.fromJson(res.contentText);
		if(response.errors) {
			throw new Exception(response.errors.toJson());
		}

		return response;
	}

	///
	@property RestBuilder rest() {
		return RestBuilder(this, null, null);
	}

	// hipchat.rest.room["Tech Team"].history
        // gives: "/room/Tech%20Team/history"
	//
	// hipchat.rest.room["Tech Team"].history("page", "12)
	///
	static struct RestBuilder {
		HttpApiClientType apiClient;
		string[] pathParts;
		string[2][] queryParts;
		this(HttpApiClientType apiClient, string[] pathParts, string[2][] queryParts) {
			this.apiClient = apiClient;
			this.pathParts = pathParts;
			this.queryParts = queryParts;
		}

		RestBuilder _SELF() {
			return this;
		}

		/// The args are so you can call opCall on the returned
		/// object, despite @property being broken af in D.
		RestBuilder opDispatch(string str, T)(string n, T v) {
			return RestBuilder(apiClient, pathParts ~ str, queryParts ~ [n, to!string(v)]);
		}

		///
		RestBuilder opDispatch(string str)() {
			return RestBuilder(apiClient, pathParts ~ str, queryParts);
		}


		///
		RestBuilder opIndex(string str) {
			return RestBuilder(apiClient, pathParts ~ str, queryParts);
		}
		///
		RestBuilder opIndex(var str) {
			return RestBuilder(apiClient, pathParts ~ str.get!string, queryParts);
		}
		///
		RestBuilder opIndex(int i) {
			return RestBuilder(apiClient, pathParts ~ to!string(i), queryParts);
		}

		///
		RestBuilder opCall(T)(string name, T value) {
			return RestBuilder(apiClient, pathParts, queryParts ~ [name, to!string(value)]);
		}

		///
		string toUri() {
			import std.uri;
			string result;
			foreach(idx, part; pathParts) {
				if(idx)
					result ~= "/";
				result ~= encodeComponent(part);
			}
			result ~= "?";
			foreach(idx, part; queryParts) {
				if(idx)
					result ~= "&";
				result ~= encodeComponent(part[0]);
				result ~= "=";
				result ~= encodeComponent(part[1]);
			}

			return result;
		}

		///
		final HttpRequestWrapper GET() { return _EXECUTE(HttpVerb.GET, this.toUri(), ToBytesResult.init); }
		/// ditto
		final HttpRequestWrapper DELETE() { return _EXECUTE(HttpVerb.DELETE, this.toUri(), ToBytesResult.init); }

		// need to be able to send: JSON, urlencoded, multipart/form-data, and raw stuff.
		/// ditto
		final HttpRequestWrapper POST(T...)(T t) { return _EXECUTE(HttpVerb.POST, this.toUri(), toBytes(t)); }
		/// ditto
		final HttpRequestWrapper PATCH(T...)(T t) { return _EXECUTE(HttpVerb.PATCH, this.toUri(), toBytes(t)); }
		/// ditto
		final HttpRequestWrapper PUT(T...)(T t) { return _EXECUTE(HttpVerb.PUT, this.toUri(), toBytes(t)); }

		struct ToBytesResult {
			ubyte[] bytes;
			string contentType;
		}

		private ToBytesResult toBytes(T...)(T t) {
			import std.conv : to;
			static if(T.length == 0)
				return ToBytesResult(null, null);
			else static if(T.length == 1 && is(T[0] == var))
				return ToBytesResult(cast(ubyte[]) t[0].toJson(), "application/json"); // json data
			else static if(T.length == 1 && (is(T[0] == string) || is(T[0] == ubyte[])))
				return ToBytesResult(cast(ubyte[]) t[0], null); // raw data
			else static if(T.length == 1 && is(T[0] : FormData))
				return ToBytesResult(t[0].toBytes, t[0].contentType);
			else static if(T.length > 1 && T.length % 2 == 0 && is(T[0] == string)) {
				// string -> value pairs for a POST request
				string answer;
				foreach(idx, val; t) {
					static if(idx % 2 == 0) {
						if(answer.length)
							answer ~= "&";
						answer ~= encodeComponent(val); // it had better be a string! lol
						answer ~= "=";
					} else {
						answer ~= encodeComponent(to!string(val));
					}
				}

				return ToBytesResult(cast(ubyte[]) answer, "application/x-www-form-urlencoded");
			}
			else
				static assert(0); // FIXME

		}

		HttpRequestWrapper _EXECUTE(HttpVerb verb, string uri, ubyte[] bodyBytes) {
			return apiClient.request(uri, verb, bodyBytes);
		}

		HttpRequestWrapper _EXECUTE(HttpVerb verb, string uri, ToBytesResult tbr) {
			auto r = apiClient.request(uri, verb, tbr.bytes);
			if(tbr.contentType !is null)
				r.requestParameters.contentType = tbr.contentType;
			return r;
		}
	}
}


// see also: arsd.cgi.encodeVariables
/// Creates a multipart/form-data object that is suitable for file uploads and other kinds of POST
class FormData {
	struct MimePart {
		string name;
		const(void)[] data;
		string contentType;
		string filename;
	}

	MimePart[] parts;

	///
	void append(string key, in void[] value, string contentType = null, string filename = null) {
		parts ~= MimePart(key, value, contentType, filename);
	}

	private string boundary = "0016e64be86203dd36047610926a"; // FIXME

	string contentType() {
		return "multipart/form-data; boundary=" ~ boundary;
	}

	///
	ubyte[] toBytes() {
		string data;

		foreach(part; parts) {
			data ~= "--" ~ boundary ~ "\r\n";
			data ~= "Content-Disposition: form-data; name=\""~part.name~"\"";
			if(part.filename !is null)
				data ~= "; filename=\""~part.filename~"\"";
			data ~= "\r\n";
			if(part.contentType !is null)
				data ~= "Content-Type: " ~ part.contentType ~ "\r\n";
			data ~= "\r\n";

			data ~= cast(string) part.data;

			data ~= "\r\n";
		}

		data ~= "--" ~ boundary ~ "--\r\n";

		return cast(ubyte[]) data;
	}
}

private bool bicmp(in ubyte[] item, in char[] search) {
	if(item.length != search.length) return false;

	foreach(i; 0 .. item.length) {
		ubyte a = item[i];
		ubyte b = search[i];
		if(a >= 'A' && a <= 'Z')
			a += 32;
		//if(b >= 'A' && b <= 'Z')
			//b += 32;
		if(a != b)
			return false;
	}

	return true;
}

/++
	WebSocket client, based on the browser api, though also with other api options.

	---
		auto ws = new WebSocket(URI("ws://...."));

		ws.onmessage = (in char[] msg) {
			ws.send("a reply");
		};

		ws.connect();

		WebSocket.eventLoop();
	---

	Symbol_groups:
		foundational =
			Used with all API styles.

		browser_api =
			API based on the standard in the browser.

		event_loop_integration =
			Integrating with external event loops is done through static functions. You should
			call these BEFORE doing anything else with the WebSocket module or class.

			$(PITFALL NOT IMPLEMENTED)
			---
				WebSocket.setEventLoopProxy(arsd.simpledisplay.EventLoop.proxy.tupleof);
				// or something like that. it is not implemented yet.
			---
			$(PITFALL NOT IMPLEMENTED)

		blocking_api =
			The blocking API is best used when you only need basic functionality with a single connection.

			---
			WebSocketFrame msg;
			do {
				// FIXME good demo
			} while(msg);
			---

			Or to check for blocks before calling:

			---
			try_to_process_more:
			while(ws.isMessageBuffered()) {
				auto msg = ws.waitForNextMessage();
				// process msg
			}
			if(ws.isDataPending()) {
				ws.lowLevelReceive();
				goto try_to_process_more;
			} else {
				// nothing ready, you can do other things
				// or at least sleep a while before trying
				// to process more.
				if(ws.readyState == WebSocket.OPEN) {
					Thread.sleep(1.seconds);
					goto try_to_process_more;
				}
			}
			---
			
+/
class WebSocket {
	private Uri uri;
	private string[string] cookies;
	private string origin;

	private string host;
	private ushort port;
	private bool ssl;

	/++
		wss://echo.websocket.org
	+/
	/// Group: foundational
	this(Uri uri, Config config = Config.init)
		//in (uri.scheme == "ws" || uri.scheme == "wss")
		in { assert(uri.scheme == "ws" || uri.scheme == "wss"); } do
	{
		this.uri = uri;
		this.config = config;

		this.receiveBuffer = new ubyte[](config.initialReceiveBufferSize);

		host = uri.host;
		ssl = uri.scheme == "wss";
		port = cast(ushort) (uri.port ? uri.port : ssl ? 443 : 80);

		if(ssl) {
			version(with_openssl)
				socket = new SslClientSocket(family(uri.unixSocketPath), SocketType.STREAM, host);
			else
				throw new Exception("SSL not compiled in");
		} else
			socket = new Socket(family(uri.unixSocketPath), SocketType.STREAM);

	}

	/++

	+/
	/// Group: foundational
	void connect() {
		if(uri.unixSocketPath)
			socket.connect(new UnixAddress(uri.unixSocketPath));
		else
			socket.connect(new InternetAddress(host, port)); // FIXME: ipv6 support...
		// FIXME: websocket handshake could and really should be async too.

		auto uri = this.uri.path.length ? this.uri.path : "/";
		if(this.uri.query.length) {
			uri ~= "?";
			uri ~= this.uri.query;
		}

		// the headers really shouldn't be bigger than this, at least
		// the chunks i need to process
		ubyte[4096] buffer;
		size_t pos;

		void append(in char[][] items...) {
			foreach(what; items) {
				buffer[pos .. pos + what.length] = cast(ubyte[]) what[];
				pos += what.length;
			}
		}

		append("GET ", uri, " HTTP/1.1\r\n");
		append("Host: ", this.uri.host, "\r\n");

		append("Upgrade: websocket\r\n");
		append("Connection: Upgrade\r\n");
		append("Sec-WebSocket-Version: 13\r\n");

		// FIXME: randomize this
		append("Sec-WebSocket-Key: x3JEHMbDL1EzLkh9GBhXDw==\r\n");

		if(config.protocol.length)
			append("Sec-WebSocket-Protocol: ", config.protocol, "\r\n");
		if(config.origin.length)
			append("Origin: ", origin, "\r\n");

		append("\r\n");

		auto remaining = buffer[0 .. pos];
		//import std.stdio; writeln(host, " " , port, " ", cast(string) remaining);
		while(remaining.length) {
			auto r = socket.send(remaining);
			if(r < 0)
				throw new Exception(lastSocketError());
			if(r == 0)
				throw new Exception("unexpected connection termination");
			remaining = remaining[r .. $];
		}

		// the response shouldn't be especially large at this point, just
		// headers for the most part. gonna try to get it in the stack buffer.
		// then copy stuff after headers, if any, to the frame buffer.
		ubyte[] used;

		void more() {
			auto r = socket.receive(buffer[used.length .. $]);

			if(r < 0)
				throw new Exception(lastSocketError());
			if(r == 0)
				throw new Exception("unexpected connection termination");
			//import std.stdio;writef("%s", cast(string) buffer[used.length .. used.length + r]);

			used = buffer[0 .. used.length + r];
		}

		more();

		import std.algorithm;
		if(!used.startsWith(cast(ubyte[]) "HTTP/1.1 101"))
			throw new Exception("didn't get a websocket answer");
		// skip the status line
		while(used.length && used[0] != '\n')
			used = used[1 .. $];

		if(used.length == 0)
			throw new Exception("wtf");

		if(used.length < 1)
			more();

		used = used[1 .. $]; // skip the \n

		if(used.length == 0)
			more();

		// checks on the protocol from ehaders
		bool isWebsocket;
		bool isUpgrade;
		const(ubyte)[] protocol;
		const(ubyte)[] accept;

		while(used.length) {
			if(used.length >= 2 && used[0] == '\r' && used[1] == '\n') {
				used = used[2 .. $];
				break; // all done
			}
			int idxColon;
			while(idxColon < used.length && used[idxColon] != ':')
				idxColon++;
			if(idxColon == used.length)
				more();
			auto idxStart = idxColon + 1;
			while(idxStart < used.length && used[idxStart] == ' ')
				idxStart++;
			if(idxStart == used.length)
				more();
			auto idxEnd = idxStart;
			while(idxEnd < used.length && used[idxEnd] != '\r')
				idxEnd++;
			if(idxEnd == used.length)
				more();

			auto headerName = used[0 .. idxColon];
			auto headerValue = used[idxStart .. idxEnd];

			// move past this header
			used = used[idxEnd .. $];
			// and the \r\n
			if(2 <= used.length)
				used = used[2 .. $];

			if(headerName.bicmp("upgrade")) {
				if(headerValue.bicmp("websocket"))
					isWebsocket = true;
			} else if(headerName.bicmp("connection")) {
				if(headerValue.bicmp("upgrade"))
					isUpgrade = true;
			} else if(headerName.bicmp("sec-websocket-accept")) {
				accept = headerValue;
			} else if(headerName.bicmp("sec-websocket-protocol")) {
				protocol = headerValue;
			}

			if(!used.length) {
				more();
			}
		}


		if(!isWebsocket)
			throw new Exception("didn't answer as websocket");
		if(!isUpgrade)
			throw new Exception("didn't answer as upgrade");


		// FIXME: check protocol if config requested one
		// FIXME: check accept for the right hash

		receiveBuffer[0 .. used.length] = used[];
		receiveBufferUsedLength = used.length;

		readyState_ = OPEN;

		if(onopen)
			onopen();

		registerActiveSocket(this);
	}

	/++
		Is data pending on the socket? Also check [isMessageBuffered] to see if there
		is already a message in memory too.

		If this returns `true`, you can call [lowLevelReceive], then try [isMessageBuffered]
		again.
	+/
	/// Group: blocking_api
	public bool isDataPending(Duration timeout = 0.seconds) {
		static SocketSet readSet;
		if(readSet is null)
			readSet = new SocketSet();

		version(with_openssl)
		if(auto s = cast(SslClientSocket) socket) {
			// select doesn't handle the case with stuff
			// left in the ssl buffer so i'm checking it separately
			if(s.dataPending()) {
				return true;
			}
		}

		readSet.add(socket);

		//tryAgain:
		auto selectGot = Socket.select(readSet, null, null, timeout);
		if(selectGot == 0) { /* timeout */
			// timeout
			return false;
		} else if(selectGot == -1) { /* interrupted */
			return false;
		} else { /* ready */
			if(readSet.isSet(socket)) {
				return true;
			}
		}

		return false;
	}

	private void llsend(ubyte[] d) {
		while(d.length) {
			auto r = socket.send(d);
			if(r <= 0) throw new Exception("wtf");
			d = d[r .. $];
		}
	}

	private void llclose() {
		socket.shutdown(SocketShutdown.SEND);
	}

	/++
		Waits for more data off the low-level socket and adds it to the pending buffer.

		Returns `true` if the connection is still active.
	+/
	/// Group: blocking_api
	public bool lowLevelReceive() {
		auto r = socket.receive(receiveBuffer[receiveBufferUsedLength .. $]);
		if(r == 0)
			return false;
		if(r <= 0)
			throw new Exception("wtf");
		receiveBufferUsedLength += r;
		return true;
	}

	private Socket socket;

	/* copy/paste section { */

	private int readyState_;
	private ubyte[] receiveBuffer;
	private size_t receiveBufferUsedLength;

	private Config config;

	enum CONNECTING = 0; /// Socket has been created. The connection is not yet open.
	enum OPEN = 1; /// The connection is open and ready to communicate.
	enum CLOSING = 2; /// The connection is in the process of closing.
	enum CLOSED = 3; /// The connection is closed or couldn't be opened.

	/++

	+/
	/// Group: foundational
	static struct Config {
		/++
			These control the size of the receive buffer.

			It starts at the initial size, will temporarily
			balloon up to the maximum size, and will reuse
			a buffer up to the likely size.

			Anything larger than the maximum size will cause
			the connection to be aborted and an exception thrown.
			This is to protect you against a peer trying to
			exhaust your memory, while keeping the user-level
			processing simple.
		+/
		size_t initialReceiveBufferSize = 4096;
		size_t likelyReceiveBufferSize = 4096; /// ditto
		size_t maximumReceiveBufferSize = 10 * 1024 * 1024; /// ditto

		/++
			Maximum combined size of a message.
		+/
		size_t maximumMessageSize = 10 * 1024 * 1024;

		string[string] cookies; /// Cookies to send with the initial request. cookies[name] = value;
		string origin; /// Origin URL to send with the handshake, if desired.
		string protocol; /// the protocol header, if desired.

		int pingFrequency = 5000; /// Amount of time (in msecs) of idleness after which to send an automatic ping
	}

	/++
		Returns one of [CONNECTING], [OPEN], [CLOSING], or [CLOSED].
	+/
	int readyState() {
		return readyState_;
	}

	/++
		Closes the connection, sending a graceful teardown message to the other side.
	+/
	/// Group: foundational
	void close(int code = 0, string reason = null)
		//in (reason.length < 123)
		in { assert(reason.length < 123); } do
	{
		if(readyState_ != OPEN)
			return; // it cool, we done
		WebSocketFrame wss;
		wss.fin = true;
		wss.opcode = WebSocketOpcode.close;
		wss.data = cast(ubyte[]) reason;
		wss.send(&llsend);

		readyState_ = CLOSING;

		llclose();
	}

	/++
		Sends a ping message to the server. This is done automatically by the library if you set a non-zero [Config.pingFrequency], but you can also send extra pings explicitly as well with this function.
	+/
	/// Group: foundational
	void ping() {
		WebSocketFrame wss;
		wss.fin = true;
		wss.opcode = WebSocketOpcode.ping;
		wss.send(&llsend);
	}

	// automatically handled....
	void pong() {
		WebSocketFrame wss;
		wss.fin = true;
		wss.opcode = WebSocketOpcode.pong;
		wss.send(&llsend);
	}

	/++
		Sends a text message through the websocket.
	+/
	/// Group: foundational
	void send(in char[] textData) {
		WebSocketFrame wss;
		wss.fin = true;
		wss.opcode = WebSocketOpcode.text;
		wss.data = cast(ubyte[]) textData;
		wss.send(&llsend);
	}

	/++
		Sends a binary message through the websocket.
	+/
	/// Group: foundational
	void send(in ubyte[] binaryData) {
		WebSocketFrame wss;
		wss.fin = true;
		wss.opcode = WebSocketOpcode.binary;
		wss.data = cast(ubyte[]) binaryData;
		wss.send(&llsend);
	}

	/++
		Waits for and returns the next complete message on the socket.

		Note that the onmessage function is still called, right before
		this returns.
	+/
	/// Group: blocking_api
	public WebSocketFrame waitForNextMessage() {
		do {
			auto m = processOnce();
			if(m.populated)
				return m;
		} while(lowLevelReceive());

		return WebSocketFrame.init; // FIXME? maybe.
	}

	/++
		Tells if [waitForNextMessage] would block.
	+/
	/// Group: blocking_api
	public bool waitForNextMessageWouldBlock() {
		checkAgain:
		if(isMessageBuffered())
			return false;
		if(!isDataPending())
			return true;
		while(isDataPending())
			lowLevelReceive();
		goto checkAgain;
	}

	/++
		Is there a message in the buffer already?
		If `true`, [waitForNextMessage] is guaranteed to return immediately.
		If `false`, check [isDataPending] as the next step.
	+/
	/// Group: blocking_api
	public bool isMessageBuffered() {
		ubyte[] d = receiveBuffer[0 .. receiveBufferUsedLength];
		auto s = d;
		if(d.length) {
			auto orig = d;
			auto m = WebSocketFrame.read(d);
			// that's how it indicates that it needs more data
			if(d !is orig)
				return true;
		}

		return false;
	}

	private ubyte continuingType;
	private ubyte[] continuingData;
	//private size_t continuingDataLength;

	private WebSocketFrame processOnce() {
		ubyte[] d = receiveBuffer[0 .. receiveBufferUsedLength];
		auto s = d;
		// FIXME: handle continuation frames more efficiently. it should really just reuse the receive buffer.
		WebSocketFrame m;
		if(d.length) {
			auto orig = d;
			m = WebSocketFrame.read(d);
			// that's how it indicates that it needs more data
			if(d is orig)
				return WebSocketFrame.init;
			switch(m.opcode) {
				case WebSocketOpcode.continuation:
					if(continuingData.length + m.data.length > config.maximumMessageSize)
						throw new Exception("message size exceeded");

					continuingData ~= m.data;
					if(m.fin) {
						if(ontextmessage)
							ontextmessage(cast(char[]) continuingData);
						if(onbinarymessage)
							onbinarymessage(continuingData);

						continuingData = null;
					}
				break;
				case WebSocketOpcode.text:
					if(m.fin) {
						if(ontextmessage)
							ontextmessage(m.textData);
					} else {
						continuingType = m.opcode;
						//continuingDataLength = 0;
						continuingData = null;
						continuingData ~= m.data;
					}
				break;
				case WebSocketOpcode.binary:
					if(m.fin) {
						if(onbinarymessage)
							onbinarymessage(m.data);
					} else {
						continuingType = m.opcode;
						//continuingDataLength = 0;
						continuingData = null;
						continuingData ~= m.data;
					}
				break;
				case WebSocketOpcode.close:
					readyState_ = CLOSED;
					if(onclose)
						onclose();

					unregisterActiveSocket(this);
				break;
				case WebSocketOpcode.ping:
					pong();
				break;
				case WebSocketOpcode.pong:
					// just really references it is still alive, nbd.
				break;
				default: // ignore though i could and perhaps should throw too
			}
		}
		receiveBufferUsedLength -= s.length - d.length;

		return m;
	}

	private void autoprocess() {
		// FIXME
		do {
			processOnce();
		} while(lowLevelReceive());
	}


	void delegate() onclose; ///
	void delegate() onerror; ///
	void delegate(in char[]) ontextmessage; ///
	void delegate(in ubyte[]) onbinarymessage; ///
	void delegate() onopen; ///

	/++

	+/
	/// Group: browser_api
	void onmessage(void delegate(in char[]) dg) {
		ontextmessage = dg;
	}

	/// ditto
	void onmessage(void delegate(in ubyte[]) dg) {
		onbinarymessage = dg;
	}

	/* } end copy/paste */

	/*
	const int bufferedAmount // amount pending
	const string extensions

	const string protocol
	const string url
	*/

	static {
		/++

		+/
		void eventLoop() {

			static SocketSet readSet;

			if(readSet is null)
				readSet = new SocketSet();

			loopExited = false;

			outermost: while(!loopExited) {
				readSet.reset();

				bool hadAny;
				foreach(sock; activeSockets) {
					readSet.add(sock.socket);
					hadAny = true;
				}

				if(!hadAny)
					return;

				tryAgain:
				auto selectGot = Socket.select(readSet, null, null, 10.seconds /* timeout */);
				if(selectGot == 0) { /* timeout */
					// timeout
					goto tryAgain;
				} else if(selectGot == -1) { /* interrupted */
					goto tryAgain;
				} else {
					foreach(sock; activeSockets) {
						if(readSet.isSet(sock.socket)) {
							if(!sock.lowLevelReceive()) {
								sock.readyState_ = CLOSED;
								unregisterActiveSocket(sock);
								continue outermost;
							}
							while(sock.processOnce().populated) {}
							selectGot--;
							if(selectGot <= 0)
								break;
						}
					}
				}
			}
		}

		private bool loopExited;
		/++

		+/
		void exitEventLoop() {
			loopExited = true;
		}

		WebSocket[] activeSockets;
		void registerActiveSocket(WebSocket s) {
			activeSockets ~= s;
		}
		void unregisterActiveSocket(WebSocket s) {
			foreach(i, a; activeSockets)
				if(s is a) {
					activeSockets[i] = activeSockets[$-1];
					activeSockets = activeSockets[0 .. $-1];
					break;
				}
		}
	}
}

/* copy/paste from cgi.d */
public {
	enum WebSocketOpcode : ubyte {
		continuation = 0,
		text = 1,
		binary = 2,
		// 3, 4, 5, 6, 7 RESERVED
		close = 8,
		ping = 9,
		pong = 10,
		// 11,12,13,14,15 RESERVED
	}

	public struct WebSocketFrame {
		private bool populated;
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

		static WebSocketFrame simpleMessage(WebSocketOpcode opcode, void[] data) {
			WebSocketFrame msg;
			msg.fin = true;
			msg.opcode = opcode;
			msg.data = cast(ubyte[]) data;

			return msg;
		}

		private void send(scope void delegate(ubyte[]) llsend) {
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

			//assert(!masked, "masking key not properly implemented");
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
			llsend(headerScratch[0 .. headerScratchPos]);
			llsend(data);
		}

		static WebSocketFrame read(ref ubyte[] d) {
			WebSocketFrame msg;

			auto orig = d;

			WebSocketFrame needsMoreData() {
				d = orig;
				return WebSocketFrame.init;
			}

			if(d.length < 2)
				return needsMoreData();

			ubyte b = d[0];

			msg.populated = true;

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

				if(d.length < 2) return needsMoreData();

				foreach(i; 0 .. 2) {
					msg.realLength |= d[0] << ((1-i) * 8);
					d = d[1 .. $];
				}
			} else if(msg.lengthIndicator == 0x7f) {
				// 64 bit length
				msg.realLength = 0;

				if(d.length < 8) return needsMoreData();

				foreach(i; 0 .. 8) {
					msg.realLength |= d[0] << ((7-i) * 8);
					d = d[1 .. $];
				}
			} else {
				// 7 bit length
				msg.realLength = msg.lengthIndicator;
			}

			if(msg.masked) {

				if(d.length < 4) return needsMoreData();

				msg.maskingKey = d[0 .. 4];
				d = d[4 .. $];
			}

			if(msg.realLength > d.length) {
				return needsMoreData();
			}

			msg.data = d[0 .. cast(size_t) msg.realLength];
			d = d[cast(size_t) msg.realLength .. $];

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

/+
	so the url params are arguments. it knows the request
	internally. other params are properties on the req

	names may have different paths... those will just add ForSomething i think.

	auto req = api.listMergeRequests
	req.page = 10;

	or
		req.page(1)
		.bar("foo")

	req.execute();


	everything in the response is nullable access through the
	dynamic object, just with property getters there. need to make
	it static generated tho

	other messages may be: isPresent and getDynamic


	AND/OR what about doing it like the rails objects

	BroadcastMessage.get(4)
	// various properties

	// it lists what you updated

	BroadcastMessage.foo().bar().put(5)
+/
