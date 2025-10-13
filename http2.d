// Copyright 2013-2022, Adam D. Ruppe.

// FIXME: websocket proxy support
// FIXME: ipv6 support

// FIXME: headers are supposed to be case insensitive. ugh.

/++
	This is version 2 of my http/1.1 client implementation.


	It has no dependencies for basic operation, but does require OpenSSL
	libraries (or compatible) to support HTTPS. This dynamically loaded
	on-demand (meaning it won't be loaded if you don't use it, but if you do
	use it, the openssl dynamic libraries must be found in the system search path).

	On Windows, you can bundle the openssl dlls with your exe and they will be picked
	up when distributed.

	You can compile with `-version=without_openssl` to entirely disable ssl support.

	http2.d, despite its name, does NOT implement HTTP/2.0, but this
	shouldn't matter for 99.9% of usage, since all servers will continue
	to support HTTP/1.1 for a very long time.

	History:
		Automatic `100 Continue` handling was added on September 28, 2021. It doesn't
		set the Expect header, so it isn't supposed to happen, but plenty of web servers
		don't follow the standard anyway.

		A dependency on [arsd.core] was added on March 19, 2023 (dub v11.0). Previously,
		module was stand-alone. You will have add the `core.d` file from the arsd repo
		to your build now if you are managing the files and builds yourself.

		The benefits of this dependency include some simplified implementation code which
		makes it easier for me to add more api conveniences, better exceptions with more
		information, and better event loop integration with other arsd modules beyond
		just the simpledisplay adapters available previously. The new integration can
		also make things like heartbeat timers easier for you to code.
+/
module arsd.http2;

///
unittest {
	import arsd.http2;

	void main() {
		auto client = new HttpClient();

		auto request = client.request(Uri("http://dlang.org/"));
		auto response = request.waitForCompletion();

		import std.stdio;
		writeln(response.contentText);
		writeln(response.code, " ", response.codeText);
		writeln(response.contentType);
	}

	version(arsd_http2_integration_test) main(); // exclude from docs
}

/+
// arsd core is now default but you can opt out for a lil while
version(no_arsd_core) {

} else {
	version=use_arsd_core;
}
+/

static import arsd.core;

// FIXME: I think I want to disable sigpipe here too.

import arsd.core : encodeUriComponent, decodeUriComponent;

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

	// https://github.com/curl/curl/blob/master/lib/vtls/schannel.c
	// https://docs.microsoft.com/en-us/windows/win32/secauthn/creating-an-schannel-security-context


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

private __gshared bool defaultVerifyPeer_ = true;

void defaultVerifyPeer(bool v) {
	defaultVerifyPeer_ = v;
}

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
		bdata ~= cast(ubyte[]) encodeUriComponent(k);
		bdata ~= cast(ubyte[]) "=";
		bdata ~= cast(ubyte[]) encodeUriComponent(v);
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

string post(string url, string[string] args, string[string] cookies = null) {
	string content;

	foreach(name, arg; args) {
		if(content.length)
			content ~= "&";
		content ~= encodeUriComponent(name) ~ "=" ~ encodeUriComponent(arg);
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
	/++
		The HTTP response code, if the response was completed, or some value < 100 if it was aborted or failed.

		Code 0 - initial value, nothing happened
		Code 1 - you called request.abort
		Code 2 - connection refused
		Code 3 - connection succeeded, but server disconnected early
		Code 4 - server sent corrupted response (or this code has a bug and processed it wrong)
		Code 5 - request timed out

		Code >= 100 - a HTTP response
	+/
	int code;
	string codeText; ///

	string httpVersion; ///

	string statusLine; ///

	string contentType; /// The *full* content type header. See also [contentTypeMimeType] and [contentTypeCharset].
	string location; /// The location header

	/++

		History:
			Added December 5, 2020 (version 9.1)
	+/
	bool wasSuccessful() {
		return code >= 200 && code < 400;
	}

	/++
		Returns the mime type part of the [contentType] header.

		History:
			Added July 25, 2022 (version 10.9)
	+/
	string contentTypeMimeType() {
		auto idx = contentType.indexOf(";");
		if(idx == -1)
			return contentType;

		return contentType[0 .. idx].strip;
	}

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

	/++
		Names and values of cookies set in the response.

		History:
			Prior to July 5, 2021 (dub v10.2), this was a public field instead of a property. I did
			not consider this a breaking change since the intended use is completely compatible with the
			property, and it was not actually implemented properly before anyway.
	+/
	@property string[string] cookies() const {
		string[string] ret;
		foreach(cookie; cookiesDetails)
			ret[cookie.name] = cookie.value;
		return ret;
	}
	/++
		The full parsed-out information of cookies set in the response.

		History:
			Added July 5, 2021 (dub v10.2).
	+/
	@property CookieHeader[] cookiesDetails() inout {
		CookieHeader[] ret;
		foreach(header; headers) {
			if(auto content = header.isHttpHeader("set-cookie")) {
				// format: name=value, value might be double quoted. it MIGHT be url encoded, but im not going to attempt that since the RFC is silent.
				// then there's optionally ; attr=value after that. attributes need not have a value

				CookieHeader cookie;

				auto remaining = content;

				cookie_name:
				foreach(idx, ch; remaining) {
					if(ch == '=') {
						cookie.name = remaining[0 .. idx].idup_if_needed;
						remaining = remaining[idx + 1 .. $];
						break;
					}
				}

				cookie_value:

				{
					auto idx = remaining.indexOf(";");
					if(idx == -1) {
						cookie.value = remaining.idup_if_needed;
						remaining = remaining[$..$];
					} else {
						cookie.value = remaining[0 .. idx].idup_if_needed;
						remaining = remaining[idx + 1 .. $].stripLeft;
					}

					if(cookie.value.length > 2 && cookie.value[0] == '"' && cookie.value[$-1] == '"')
						cookie.value = cookie.value[1 .. $ - 1];
				}

				cookie_attributes:

				while(remaining.length) {
					string name;
					foreach(idx, ch; remaining) {
						if(ch == '=') {
							name = remaining[0 .. idx].idup_if_needed;
							remaining = remaining[idx + 1 .. $];

							string value;

							foreach(idx2, ch2; remaining) {
								if(ch2 == ';') {
									value = remaining[0 .. idx2].idup_if_needed;
									remaining = remaining[idx2 + 1 .. $].stripLeft;
									break;
								}
							}

							if(value is null) {
								value = remaining.idup_if_needed;
								remaining = remaining[$ .. $];
							}

							cookie.attributes[name] = value;
							continue cookie_attributes;
						} else if(ch == ';') {
							name = remaining[0 .. idx].idup_if_needed;
							remaining = remaining[idx + 1 .. $].stripLeft;
							cookie.attributes[name] = "";
							continue cookie_attributes;
						}
					}

					if(remaining.length) {
						cookie.attributes[remaining.idup_if_needed] = "";
						remaining = remaining[$..$];

					}
				}

				ret ~= cookie;
			}
		}
		return ret;
	}

	string[] headers; /// Array of all headers returned.
	string[string] headersHash; ///

	ubyte[] content; /// The raw content returned in the response body.
	string contentText; /// [content], but casted to string (for convenience)

	alias responseText = contentText; // just cuz I do this so often.
	//alias body = content;

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

	HttpResponse deepCopy() const {
		HttpResponse h = cast(HttpResponse) this;
		h.headers = h.headers.dup;
		h.headersHash = h.headersHash.dup;
		h.content = h.content.dup;
		h.linksStored = h.linksStored.dup;
		return h;
	}

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

		auto hdrPtr = "link" in headersHash;
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
				if(idx + 1 < header.length)
					header = header[idx + 1 .. $];
				else
					header = header[$ .. $];

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

			if(header.length)
				header = header[1 .. $];
		}

		ret ~= current;

		linksStored = ret;

		return ret;
	}
}

/+
	headerName MUST be all lower case and NOT have the colon on it

	returns slice of the input thing after the header name
+/
private inout(char)[] isHttpHeader(inout(char)[] thing, const(char)[] headerName) {
	foreach(idx, ch; thing) {
		if(idx < headerName.length) {
			if(headerName[idx] == '-' && ch != '-')
				return null;
			if((ch | ' ') != headerName[idx])
				return null;
		} else if(idx == headerName.length) {
			if(ch != ':')
				return null;
		} else {
			return thing[idx .. $].strip;
		}
	}
	return null;
}

private string idup_if_needed(string s) { return s; }
private string idup_if_needed(const(char)[] s) { return s.idup; }

unittest {
	assert("Cookie: foo=bar".isHttpHeader("cookie") == "foo=bar");
	assert("cookie: foo=bar".isHttpHeader("cookie") == "foo=bar");
	assert("cOOkie: foo=bar".isHttpHeader("cookie") == "foo=bar");
	assert("Set-Cookie: foo=bar".isHttpHeader("set-cookie") == "foo=bar");
	assert(!"".isHttpHeader("cookie"));
}

///
struct LinkHeader {
	string url; ///
	string rel; ///
	string[string] attributes; /// like title, rev, media, whatever attributes
}

/++
	History:
		Added July 5, 2021
+/
struct CookieHeader {
	string name;
	string value;
	string[string] attributes;

	// max-age
	// expires
	// httponly
	// secure
	// samesite
	// path
	// domain
	// partitioned ?

	// also want cookiejar features here with settings to save session cookies or not

	// storing in file: http://kb.mozillazine.org/Cookies.txt (second arg in practice true if first arg starts with . it seems)
	// or better yet sqlite: http://kb.mozillazine.org/Cookies.sqlite
	// should be able to import/export from either upon request
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
/++
	Represents a URI. It offers named access to the components and relative uri resolution, though as a user of the library, you'd mostly just construct it like `Uri("http://example.com/index.html")`.
+/
struct Uri {
	alias toString this; // blargh idk a url really is a string, but should it be implicit?

	// scheme://userinfo@host:port/path?query#fragment

	string scheme; /// e.g. "http" in "http://example.com/"
	string userinfo; /// the username (and possibly a password) in the uri
	string host; /// the domain name
	int port; /// port number, if given. Will be zero if a port was not explicitly given
	string path; /// e.g. "/folder/file.html" in "http://example.com/folder/file.html"
	string query; /// the stuff after the ? in a uri
	string fragment; /// the stuff after the # in a uri.

	/// Breaks down a uri string to its components
	this(string uri) {
		size_t lastGoodIndex;
		foreach(char ch; uri) {
			if(ch > 127) {
				break;
			}
			lastGoodIndex++;
		}

		string replacement = uri[0 .. lastGoodIndex];
		foreach(char ch; uri[lastGoodIndex .. $]) {
			if(ch > 127) {
				// need to percent-encode any non-ascii in it
				char[3] buffer;
				buffer[0] = '%';

				auto first = ch / 16;
				auto second = ch % 16;
				first += (first >= 10) ? ('A'-10) : '0';
				second += (second >= 10) ? ('A'-10) : '0';

				buffer[1] = cast(char) first;
				buffer[2] = cast(char) second;

				replacement ~= buffer[];
			} else {
				replacement ~= ch;
			}
		}

		reparse(replacement);
	}

	/// Returns `port` if set, otherwise if scheme is https 443, otherwise always 80
	int effectivePort() const @property nothrow pure @safe @nogc {
		return port != 0 ? port
			: scheme == "https" ? 443 : 80;
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

			if(authority.length && authority[0] == '[') {
				// ipv6 address special casing
				idx2 = authority.indexOf(']');
				if(idx2 != -1) {
					auto end = authority[idx2 + 1 .. $];
					if(end.length && end[0] == ':')
						idx2 = idx2 + 1;
					else
						idx2 = -1;
				}
			} else {
				idx2 = authority.indexOf(":");
			}

			if(idx2 == -1) {
				port = 0; // 0 means not specified; we should use the default for the scheme
				host = authority;
			} else {
				host = authority[0 .. idx2];
				if(idx2 + 1 < authority.length)
					port = to!int(authority[idx2 + 1 .. $]);
				else
					port = 0;
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
		if(n.scheme == "data")
			return n;
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

	/++
		Resolves ../ and ./ parts of the path. Used in the implementation of [basedOn] and you could also use it to normalize things.
	+/
	void removeDots() {
		auto parts = this.path.split("/");
		string[] toKeep;
		foreach(part; parts) {
			if(part == ".") {
				continue;
			} else if(part == "..") {
				//if(toKeep.length > 1)
					toKeep = toKeep[0 .. $-1];
				//else
					//toKeep = [""];
				continue;
			} else {
				//if(toKeep.length && toKeep[$-1].length == 0 && part.length == 0)
					//continue; // skip a `//` situation
				toKeep ~= part;
			}
		}

		auto path = toKeep.join("/");
		if(path.length && path[0] != '/')
			path = "/" ~ path;

		this.path = path;
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

class ProxyException : Exception {
	this(string msg) {super(msg); }
}

/**
	Represents a HTTP request. You usually create these through a [HttpClient].


	---
	auto request = new HttpRequest(); // note that when there's no associated client, some features may not work
	// normally you'd instead do `new HttpClient(); client.request(...)`
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
	---
*/
class HttpRequest {

	/// Automatically follow a redirection?
	bool followLocation = false;

	/++
		Maximum number of redirections to follow (used only if [followLocation] is set to true). Will resolve with an error if a single request has more than this number of redirections. The default value is currently 10, but may change without notice. If you need a specific value, be sure to call this function.

		If you want unlimited redirects, call it with `int.max`. If you set it to 0 but set [followLocation] to `true`, any attempt at redirection will abort the request. To disable automatically following redirection, set [followLocation] to `false` so you can process the 30x code yourself as a completed request.

		History:
			Added July 27, 2022 (dub v10.9)
	+/
	void setMaximumNumberOfRedirects(int max = 10) {
		maximumNumberOfRedirectsRemaining = max;
	}

	private int maximumNumberOfRedirectsRemaining;

	/++
		Set to `true` to automatically retain cookies in the associated [HttpClient] from this request.
		Note that you must have constructed the request from a `HttpClient` or at least passed one into the
		constructor for this to have any effect.

		Bugs:
			See [HttpClient.retainCookies] for important caveats.

		History:
			Added July 5, 2021 (dub v10.2)
	+/
	bool retainCookies = false;

	private HttpClient client;

	this() {
	}

	///
	this(HttpClient client, Uri where, HttpVerb method, ICache cache = null, Duration timeout = 10.seconds, string proxy = null) {
		this.client = client;
		populateFromInfo(where, method);
		setTimeout(timeout);
		this.cache = cache;
		this.proxy = proxy;

		setMaximumNumberOfRedirects();
	}


	/// ditto
	this(Uri where, HttpVerb method, ICache cache = null, Duration timeout = 10.seconds, string proxy = null) {
		this(null, where, method, cache, timeout, proxy);
	}

	/++
		Adds the given header to the request, without checking for duplicates or similar.

		History:
			Added October 8, 2025. Previously, you'd have to do `request.requestParameters.headers ~= "Name: Value"` (which is exactly what this does, but less conveniently).
	+/
	void addHeader(string name, string value) {
		this.requestParameters.headers ~= name ~ ": " ~ value;
	}

	/++
		Sets the timeout from inactivity on the request. This is the amount of time that passes with no send or receive activity on the request before it fails with "request timed out" error.

		History:
			Added March 31, 2021
	+/
	void setTimeout(Duration timeout) {
		this.requestParameters.timeoutFromInactivity = timeout;
		this.timeoutFromInactivity = MonoTime.currTime + this.requestParameters.timeoutFromInactivity;
	}

	/++
		Set to `true` to gzip the request body when sending to the server. This is often not supported, and thus turned off
		by default.


		If a server doesn't support this, you MAY get an http error or it might just do the wrong thing.
		By spec, it is supposed to be code "415 Unsupported Media Type", but there's no guarantee they
		will do that correctly since many servers will simply have never considered this possibility. Request
		compression is quite rare, so before using this, ensure your server supports it by checking its documentation
		or asking its administrator. (Or running a test, but remember, it might just do the wrong thing and not issue
		an appropriate error, or the config may change in the future.)

		History:
			Added August 6, 2024 (dub v11.5)
	+/
	void gzipBody(bool want) {
		this.requestParameters.gzipBody = want;
	}

	private MonoTime timeoutFromInactivity;

	private Uri where;

	private ICache cache;

	/++
		Proxy to use for this request. It should be a URL or `null`.

		This must be sent before you call [send].

		History:
			Added April 12, 2021 (dub v9.5)
	+/
	string proxy;

	/++
		For https connections, if this is `true`, it will fail to connect if the TLS certificate can not be
		verified. Setting this to `false` will skip this check and allow the connection to continue anyway.

		When the [HttpRequest] is constructed from a [HttpClient], it will inherit the value from the client
		instead of using the `= true` here. You can change this value any time before you call [send] (which
		is done implicitly if you call [waitForCompletion]).

		History:
			Added April 5, 2022 (dub v10.8)

			Prior to this, it always used the global (but undocumented) `defaultVerifyPeer` setting, and sometimes
			even if it was true, it would skip the verification. Now, it always respects this local setting.
	+/
	bool verifyPeer = true;


	/// Final url after any redirections
	string finalUrl;

	void populateFromInfo(Uri where, HttpVerb method) {
		auto parts = where.basedOn(this.where);
		this.where = parts;
		finalUrl = where.toString();
		requestParameters.method = method;
		requestParameters.unixSocketPath = where.unixSocketPath;
		requestParameters.host = parts.host;
		requestParameters.port = cast(ushort) parts.effectivePort;
		requestParameters.ssl = parts.scheme == "https";
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
	final State state() { return state_; }
	final State state(State s) {
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

		/// connect has been called, but we're waiting on word of success
		connecting,

		/// connecting a ssl, needing this
		sslConnectPendingRead,
		/// ditto
		sslConnectPendingWrite,

		/// The headers are being sent now
		sendingHeaders,

		// FIXME: allow Expect: 100-continue and separate the body send

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

		if(cache !is null) {
			auto res = cache.getCachedResponse(this.requestParameters);
			if(res !is null) {
				state = State.complete;
				responseData = (*res).deepCopy();
				return;
			}
		}

		if(this.where.scheme == "data") {
			void error(string content) {
				responseData.code = 400;
				responseData.codeText = "Bad Request";
				responseData.contentType = "text/plain";
				responseData.content = cast(ubyte[]) content;
				responseData.contentText = content;
				state = State.complete;
				return;
			}

			auto thing = this.where.path;
			// format is: type,data
			// type can have ;base64
			auto comma = thing.indexOf(",");
			if(comma == -1)
				return error("Invalid data uri, no comma found");

			auto type = thing[0 .. comma];
			auto data = thing[comma + 1 .. $];
			if(type.length == 0)
				type = "text/plain";

			auto bdata = cast(ubyte[]) decodeUriComponent(data);

			if(type.indexOf(";base64") != -1) {
				import std.base64;
				try {
					bdata = Base64.decode(bdata);
				} catch(Exception e) {
					return error(e.msg);
				}
			}

			responseData.code = 200;
			responseData.codeText = "OK";
			responseData.contentType = type;
			responseData.content = bdata;
			responseData.contentText = cast(string) responseData.content;
			state = State.complete;
			return;
		}

		string headers;

		headers ~= to!string(requestParameters.method);
		headers ~= " ";
		if(proxy.length && !requestParameters.ssl) {
			// if we're doing a http proxy, we need to send a complete, absolute uri
			// so reconstruct it
			headers ~= "http://";
			headers ~= requestParameters.host;
			if(requestParameters.port != 80) {
				headers ~= ":";
				headers ~= to!string(requestParameters.port);
			}
		}

		headers ~= requestParameters.uri;

		if(requestParameters.useHttp11)
			headers ~= " HTTP/1.1\r\n";
		else
			headers ~= " HTTP/1.0\r\n";

		// the whole authority section is supposed to be there, but curl doesn't send if default port
		// so I'll copy what they do
		headers ~= "Host: ";
		headers ~= requestParameters.host;
		if(requestParameters.port != 80 && requestParameters.port != 443) {
			headers ~= ":";
			headers ~= to!string(requestParameters.port);
		}
		headers ~= "\r\n";

		bool specSaysRequestAlwaysHasBody =
			requestParameters.method == HttpVerb.POST ||
			requestParameters.method == HttpVerb.PUT ||
			requestParameters.method == HttpVerb.PATCH;

		if(requestParameters.userAgent.length)
			headers ~= "User-Agent: "~requestParameters.userAgent~"\r\n";
		if(requestParameters.contentType.length)
			headers ~= "Content-Type: "~requestParameters.contentType~"\r\n";
		if(requestParameters.authorization.length)
			headers ~= "Authorization: "~requestParameters.authorization~"\r\n";
		if(requestParameters.bodyData.length || specSaysRequestAlwaysHasBody)
			headers ~= "Content-Length: "~to!string(requestParameters.bodyData.length)~"\r\n";
		if(requestParameters.acceptGzip)
			headers ~= "Accept-Encoding: gzip\r\n";
		if(requestParameters.keepAlive)
			headers ~= "Connection: keep-alive\r\n";

		string cookieHeader;
		foreach(name, value; requestParameters.cookies) {
			if(cookieHeader is null)
				cookieHeader = "Cookie: ";
			else
				cookieHeader ~= "; ";
			cookieHeader ~= name;
			cookieHeader ~= "=";
			cookieHeader ~= value;
		}

		if(cookieHeader !is null) {
			cookieHeader ~= "\r\n";
			headers ~= cookieHeader;
		}

		foreach(header; requestParameters.headers)
			headers ~= header ~ "\r\n";

		const(ubyte)[] bodyToSend = requestParameters.bodyData;
		if(requestParameters.gzipBody) {
			headers ~= "Content-Encoding: gzip\r\n";
			auto c = new Compress(HeaderFormat.gzip);

			auto data = c.compress(bodyToSend);
			data ~= c.flush();
			bodyToSend = cast(ubyte[]) data;
		}

		headers ~= "\r\n";

		// FIXME: separate this for 100 continue
		sendBuffer = cast(ubyte[]) headers ~ bodyToSend;

		// import std.stdio; writeln("******* ", cast(string) sendBuffer);

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
			HttpRequest.advanceConnections(0.seconds);//requestParameters.timeoutFromInactivity); // doing async so no block here
	}


	/// Waits for the request to finish or timeout, whichever comes first.
	HttpResponse waitForCompletion() {
		while(state != State.aborted && state != State.complete) {
			if(state == State.unsent) {
				send();
				continue;
			}
			if(auto err = HttpRequest.advanceConnections(requestParameters.timeoutFromInactivity)) {
				switch(err) {
					case 1: throw new Exception("HttpRequest.advanceConnections returned 1: all connections timed out");
					case 2: throw new Exception("HttpRequest.advanceConnections returned 2: nothing to do");
					case 3: continue; // EINTR
					default: throw new Exception("HttpRequest.advanceConnections got err " ~ to!string(err));
				}
			}
		}

		if(state == State.complete && responseData.code >= 200)
			if(cache !is null)
				cache.cacheResponse(this.requestParameters, this.responseData);

		return responseData;
	}

	/// Aborts this request.
	void abort() {
		this.state = State.aborted;
		this.responseData.code = 1;
		this.responseData.codeText = "request.abort called";
		// the actual cancellation happens in the event loop
	}

	HttpRequestParameters requestParameters; ///

	version(arsd_http_winhttp_implementation) {
		public static void resetInternals() {

		}

		static assert(0, "implementation not finished");
	}


	version(arsd_http_internal_implementation) {

	/++
		Changes the limit of number of open, inactive sockets. Reusing connections can provide a significant
		performance improvement, but the operating system can also impose a global limit on the number of open
		sockets and/or files that you don't want to run into. This lets you choose a balance right for you.


		When the total number of cached, inactive sockets approaches this maximum, it will check for ones closed by the
		server first. If there are none already closed by the server, it will select sockets at random from its connection
		cache and close them to make room for the new ones.

		Please note:

		$(LIST
			* there is always a limit of six open sockets per domain, per the common practice suggested by the http standard
			* the limit given here is thread-local. If you run multiple http clients/requests from multiple threads, don't set this too high or you might bump into the global limit from the OS.
			* setting this too low can waste connections because the server might close them, but they will never be garbage collected since my current implementation won't check for dead connections except when it thinks it is running close to the limit.
		)

		Setting it just right for your use case may provide an up to 10x performance boost.

		This implementation is subject to change. If it does, I'll document it, but may not bump the version number.

		History:
			Added August 10, 2022 (dub v10.9)
	+/
	static void setConnectionCacheSize(int max = 32) {
		connectionCacheSize = max;
	}

	private static {
		// we manage the actual connections. When a request is made on a particular
		// host, we try to reuse connections. We may open more than one connection per
		// host to do parallel requests.
		//
		// The key is the *domain name* and the port. Multiple domains on the same address will have separate connections.
		Socket[][string] socketsPerHost;

		// only one request can be active on a given socket (at least HTTP < 2.0) so this is that
		HttpRequest[Socket] activeRequestOnSocket;
		HttpRequest[] pending; // and these are the requests that are waiting

		int cachedSockets;
		int connectionCacheSize = 32;

		/+
			This is a somewhat expensive, but essential operation. If it isn't used in a heavy
			application, you'll risk running out of file descriptors.
		+/
		void cleanOldSockets() {
			static struct CloseCandidate {
				string key;
				Socket socket;
			}

			CloseCandidate[36] closeCandidates;
			int closeCandidatesPosition;

			outer: foreach(key, sockets; socketsPerHost) {
				foreach(socket; sockets) {
					if(socket in activeRequestOnSocket)
						continue; // it is still in use; we can't close it

					closeCandidates[closeCandidatesPosition++] = CloseCandidate(key, socket);
					if(closeCandidatesPosition == closeCandidates.length)
						break outer;
				}
			}

			auto cc = closeCandidates[0 .. closeCandidatesPosition];

			if(cc.length == 0)
				return; // no candidates to even examine

			// has the server closed any of these? if so, we also close and drop them
			static SocketSet readSet = null;
			if(readSet is null)
				readSet = new SocketSet();
			readSet.reset();

			foreach(candidate; cc) {
				readSet.add(candidate.socket);
			}

			int closeCount;

			auto got = Socket.select(readSet, null, null, 0.msecs /* timeout, want it small since we just checking for eof */);
			if(got > 0) {
				foreach(ref candidate; cc) {
					if(readSet.isSet(candidate.socket)) {
						// if we can read when it isn't in use, that means eof; the
						// server closed it.
						candidate.socket.close();
						loseSocketByKey(candidate.key, candidate.socket);
						closeCount++;
					}
				}
				debug(arsd_http2) writeln(closeCount, " from inactivity");
			} else {
				// and if not, of the remaining ones, close a few just at random to bring us back beneath the arbitrary limit.

				while(cc.length > 0 && (cachedSockets - closeCount) > connectionCacheSize) {
					import std.random;
					auto idx = uniform(0, cc.length);

					cc[idx].socket.close();
					loseSocketByKey(cc[idx].key, cc[idx].socket);

					cc[idx] = cc[$ - 1];
					cc = cc[0 .. $-1];
					closeCount++;
				}
				debug(arsd_http2) writeln(closeCount, " from randomness");
			}

			cachedSockets -= closeCount;
		}

		void loseSocketByKey(string key, Socket s) {
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

		void loseSocket(string host, ushort port, bool ssl, Socket s) {
			import std.string;
			auto key = format("http%s://%s:%s", ssl ? "s" : "", host, port);

			loseSocketByKey(key, s);
		}

		Socket getOpenSocketOnHost(string proxy, string host, ushort port, bool ssl, string unixSocketPath, bool verifyPeer) {
			Socket openNewConnection() {
				Socket socket;
				if(ssl) {
					version(with_openssl) {
						loadOpenSsl();
						socket = new SslClientSocket(family(unixSocketPath), SocketType.STREAM, host, verifyPeer);
						socket.blocking = false;
					} else
						throw new Exception("SSL not compiled in");
				} else {
					socket = new Socket(family(unixSocketPath), SocketType.STREAM);
					socket.blocking = false;
				}

				socket.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);

				// FIXME: connect timeout?
				if(unixSocketPath) {
					import std.stdio; writeln(cast(ubyte[]) unixSocketPath);
					socket.connect(new UnixAddress(unixSocketPath));
				} else {
					// FIXME: i should prolly do ipv6 if available too.
					if(host.length == 0) // this could arguably also be an in contract since it is user error, but the exception is good enough
						throw new Exception("No host given for request");
					if(proxy.length) {
						if(proxy.indexOf("//") == -1)
							proxy = "http://" ~ proxy;
						auto proxyurl = Uri(proxy);

						//auto proxyhttps = proxyurl.scheme == "https";
						enum proxyhttps = false; // this isn't properly implemented and might never be necessary anyway so meh

						// the precise types here are important to help with overload
						// resolution of the devirtualized call!
						Address pa = new InternetAddress(proxyurl.host, proxyurl.port ? cast(ushort) proxyurl.port : 80);

						debug(arsd_http2) writeln("using proxy ", pa.toString());

						if(proxyhttps) {
							socket.connect(pa);
						} else {
							// the proxy never actually starts TLS, but if the request is tls then we need to CONNECT then upgrade the connection
							// using the parent class functions let us bypass the encryption
							socket.Socket.connect(pa);
						}

						socket.blocking = true; // FIXME total hack to simplify the code here since it isn't really using the event loop yet

						string message;
						if(ssl) {
							auto hostName =  host ~ ":" ~ to!string(port);
							message = "CONNECT " ~ hostName ~ " HTTP/1.1\r\n";
							message ~= "Host: " ~ hostName ~ "\r\n";
							if(proxyurl.userinfo.length) {
								import std.base64;
								message ~= "Proxy-Authorization: Basic " ~ Base64.encode(cast(ubyte[]) proxyurl.userinfo) ~ "\r\n";
							}
							message ~= "\r\n";

							// FIXME: what if proxy times out? should be reasonably fast too.
							if(proxyhttps) {
								socket.send(message, SocketFlags.NONE);
							} else {
								socket.Socket.send(message, SocketFlags.NONE);
							}

							ubyte[1024] recvBuffer;
							// and last time
							ptrdiff_t rcvGot;
							if(proxyhttps) {
								rcvGot = socket.receive(recvBuffer[], SocketFlags.NONE);
								// bool verifyPeer = true;
								//(cast(OpenSslSocket)socket).freeSsl();
								//(cast(OpenSslSocket)socket).initSsl(verifyPeer, host);
							} else {
								rcvGot = socket.Socket.receive(recvBuffer[], SocketFlags.NONE);
							}

							if(rcvGot == -1)
								throw new ProxyException("proxy receive error");
							auto got = cast(string) recvBuffer[0 .. rcvGot];
							auto expect = "HTTP/1.1 200";
							if(got.length < expect.length || (got[0 .. expect.length] != expect && got[0 .. expect.length] != "HTTP/1.0 200"))
								throw new ProxyException("Proxy rejected request: " ~ got[0 .. expect.length <= got.length ? expect.length : got.length]);

							if(proxyhttps) {
								//(cast(OpenSslSocket)socket).do_ssl_connect();
							} else {
								(cast(OpenSslSocket)socket).do_ssl_connect();
							}
						} else {
						}
					} else {
						socket.connect(new InternetAddress(host, port));
					}
				}

				debug(arsd_http2) writeln("opening to ", host, ":", port, " ", cast(void*) socket, " ssl=", ssl);
				assert(socket.handle() !is socket_t.init);
				return socket;
			}

			// import std.stdio; writeln(cachedSockets);
			if(cachedSockets > connectionCacheSize)
				cleanOldSockets();

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
						assert(socket !is null);
						assert(socket.handle() !is socket_t.init, socket is null ? "null" : socket.toString());
						readSet.add(socket);
						auto got = Socket.select(readSet, null, null, 0.msecs /* timeout, want it small since we just checking for eof */);
						if(got > 0) {
							// we can read something off this... but there aren't
							// any active requests. Assume it is EOF and open a new one

							socket.close();
							loseSocket(host, port, ssl, socket);
							goto openNew;
						}
						cachedSockets--;
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

		// stuff used by advanceConnections
		SocketSet readSet;
		SocketSet writeSet;
		private ubyte[] reusableBuffer;

		/+
			Generic event loop registration:

				handle, operation (read/write), buffer (on posix it *might* be stack if a select loop), timeout (in real time), callback when op completed.

				....basically Windows style. Then it translates internally.

				It should tell the thing if the buffer is reused or not
		+/

		/++
			This is made public for rudimentary event loop integration, but is still
			basically an internal detail. Try not to use it if you have another way.

			This does a single iteration of the internal select()-based processing loop.


			Future directions:
				I want to merge the internal use of [WebSocket.eventLoop] with this;
				[advanceConnections] does just one run on the loop, whereas eventLoop
				runs it until all connections are closed. But they'd both process both
				pending http requests and active websockets.

				After that, I want to be able to integrate in other event loops too.
				One might be to simply to reactor callbacks, then perhaps Windows overlapped
				i/o (that's just going to be tricky to retrofit into the existing select()-based
				code). It could then go fiber just by calling the resume function too.

				The hard part is ensuring I keep this file stand-alone while offering these
				things.

				This `advanceConnections` call will probably continue to work now that it is
				public, but it may not be wholly compatible with all the future features; you'd
				have to pick either the internal event loop or an external one you integrate, but not
				mix them.

			History:
				This has been included in the library since almost day one, but
				it was private until April 13, 2021 (dub v9.5).

			Params:
				maximumTimeout = the maximum time it will wait in select(). It may return much sooner than this if a connection timed out in the mean time.
				automaticallyRetryOnInterruption = internally loop on EINTR.

			Returns:

				0 = no error, work may remain so you should call `advanceConnections` again when you can

				1 = passed `maximumTimeout` reached with no work done, yet requests are still in the queue. You may call `advanceConnections` again.

				2 = no work to do, no point calling it again unless you've added new requests. Your program may exit if you have nothing to add since it means everything requested is now done.

				3 = EINTR occurred on select(), you should check your interrupt flags if you set a signal handler, then call `advanceConnections` again if you aren't exiting. Only occurs if `automaticallyRetryOnInterruption` is set to `false` (the default when it is called externally).

				any other value should be considered a non-recoverable error if you want to be forward compatible as I reserve the right to add more values later.
		+/
		public int advanceConnections(Duration maximumTimeout = 10.seconds, bool automaticallyRetryOnInterruption = false) {
			debug(arsd_http2_verbose) writeln("advancing");
			if(readSet is null)
				readSet = new SocketSet();
			if(writeSet is null)
				writeSet = new SocketSet();

			if(reusableBuffer is null)
				reusableBuffer = new ubyte[](32 * 1024);
			ubyte[] buffer = reusableBuffer;

			HttpRequest[16] removeFromPending;
			size_t removeFromPendingCount = 0;

			bool hadAbortedRequest;

			// are there pending requests? let's try to send them
			foreach(idx, pc; pending) {
				if(removeFromPendingCount == removeFromPending.length)
					break;

				if(pc.state == HttpRequest.State.aborted) {
					removeFromPending[removeFromPendingCount++] = pc;
					hadAbortedRequest = true;
					continue;
				}

				Socket socket;

				try {
					socket = getOpenSocketOnHost(pc.proxy, pc.requestParameters.host, pc.requestParameters.port, pc.requestParameters.ssl, pc.requestParameters.unixSocketPath, pc.verifyPeer);
				} catch(ProxyException e) {
					// connection refused or timed out (I should disambiguate somehow)...
					pc.state = HttpRequest.State.aborted;

					pc.responseData.code = 2;
					pc.responseData.codeText = e.msg ~ " from " ~ pc.proxy;

					hadAbortedRequest = true;

					removeFromPending[removeFromPendingCount++] = pc;
					continue;

				} catch(SocketException e) {
					// connection refused or timed out (I should disambiguate somehow)...
					pc.state = HttpRequest.State.aborted;

					pc.responseData.code = 2;
					pc.responseData.codeText = pc.proxy.length ? ("connection failed to proxy " ~ pc.proxy) : "connection failed";

					hadAbortedRequest = true;

					removeFromPending[removeFromPendingCount++] = pc;
					continue;
				} catch(Exception e) {
					// connection failed due to other user error or SSL (i should disambiguate somehow)...
					pc.state = HttpRequest.State.aborted;

					pc.responseData.code = 2;
					pc.responseData.codeText = e.msg;

					hadAbortedRequest = true;

					removeFromPending[removeFromPendingCount++] = pc;
					continue;

				}

				if(socket !is null) {
					activeRequestOnSocket[socket] = pc;
					assert(pc.sendBuffer.length);
					pc.state = State.connecting;

					removeFromPending[removeFromPendingCount++] = pc;
				}
			}

			import std.algorithm : remove;
			foreach(rp; removeFromPending[0 .. removeFromPendingCount]) {
				if(rp.onDataReceived) rp.onDataReceived(rp);
				pending = pending.remove!((a) => a is rp)();
			}

			tryAgain:

			Socket[16] inactive;
			int inactiveCount = 0;
			void killInactives() {
				foreach(s; inactive[0 .. inactiveCount]) {
					debug(arsd_http2) writeln("removing socket from active list ", cast(void*) s);
					activeRequestOnSocket.remove(s);
					cachedSockets++;
				}
			}


			readSet.reset();
			writeSet.reset();

			bool hadOne = false;

			auto minTimeout = maximumTimeout;
			auto now = MonoTime.currTime;

			// active requests need to be read or written to
			foreach(sock, request; activeRequestOnSocket) {

				if(request.state == State.aborted) {
					inactive[inactiveCount++] = sock;
					sock.close();
					loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
					hadAbortedRequest = true;
					if(request.onDataReceived) request.onDataReceived(request);
					continue;
				}

				// check the other sockets just for EOF, if they close, take them out of our list,
				// we'll reopen if needed upon request.
				readSet.add(sock);
				hadOne = true;

				Duration timeo;
				if(request.timeoutFromInactivity <= now)
					timeo = 0.seconds;
				else
					timeo = request.timeoutFromInactivity - now;

				if(timeo < minTimeout)
					minTimeout = timeo;

				if(request.state == State.connecting || request.state == State.sslConnectPendingWrite || request.state == State.sendingHeaders || request.state == State.sendingBody) {
					writeSet.add(sock);
					hadOne = true;
				}
			}

			if(!hadOne) {
				if(hadAbortedRequest) {
					killInactives();
					return 0; // something got aborted, that's progress
				}
				return 2; // automatic timeout, nothing to do
			}

			auto selectGot = Socket.select(readSet, writeSet, null, minTimeout);
			if(selectGot == 0) { /* timeout */
				now = MonoTime.currTime;
				bool anyWorkDone = false;
				foreach(sock, request; activeRequestOnSocket) {

					if(request.timeoutFromInactivity <= now) {
						request.state = HttpRequest.State.aborted;
						request.responseData.code = 5;
						if(request.state == State.connecting)
							request.responseData.codeText = "Connect timed out";
						else
							request.responseData.codeText = "Request timed out";

						inactive[inactiveCount++] = sock;
						sock.close();
						loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
						anyWorkDone = true;

						if(request.onDataReceived) request.onDataReceived(request);
					}
				}
				killInactives();
				return anyWorkDone ? 0 : 1;
				// return 1; was an error to time out but now im making it on the individual request
			} else if(selectGot == -1) { /* interrupted */
				/*
				version(Posix) {
					import core.stdc.errno;
					if(errno != EINTR)
						throw new Exception("select error: " ~ to!string(errno));
				}
				*/
				if(automaticallyRetryOnInterruption)
					goto tryAgain;
				else
					return 3;
			} else { /* ready */

				void sslProceed(HttpRequest request, SslClientSocket s) {
					try {
						auto code = s.do_ssl_connect();
						switch(code) {
							case 0:
								request.state = State.sendingHeaders;
							break;
							case SSL_ERROR_WANT_READ:
								request.state = State.sslConnectPendingRead;
							break;
							case SSL_ERROR_WANT_WRITE:
								request.state = State.sslConnectPendingWrite;
							break;
							default:
								assert(0);
						}
					} catch(Exception e) {
						request.state = State.aborted;

						request.responseData.code = 2;
						request.responseData.codeText = e.msg;
						inactive[inactiveCount++] = s;
						s.close();
						loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, s);
						if(request.onDataReceived) request.onDataReceived(request);
					}
				}


				foreach(sock, request; activeRequestOnSocket) {
					// always need to try to send first in part because http works that way but
					// also because openssl will sometimes leave something ready to read even if we haven't
					// sent yet (probably leftover data from the crypto negotiation) and if that happens ssl
					// is liable to block forever hogging the connection and not letting it send...
					if(request.state == State.connecting)
					if(writeSet.isSet(sock) || readSet.isSet(sock)) {
						import core.stdc.stdint;
						int32_t error;
						int retopt = sock.getOption(SocketOptionLevel.SOCKET, SocketOption.ERROR, error);
						if(retopt < 0 || error != 0) {
							request.state = State.aborted;

							request.responseData.code = 2;
							try {
								request.responseData.codeText = "connection failed - " ~ formatSocketError(error);
							} catch(Exception e) {
								request.responseData.codeText = "connection failed";
							}
							inactive[inactiveCount++] = sock;
							sock.close();
							loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
							if(request.onDataReceived) request.onDataReceived(request);
							continue;
						} else {
							if(auto s = cast(SslClientSocket) sock) {
								sslProceed(request, s);
								continue;
							} else {
								request.state = State.sendingHeaders;
							}
						}
					}

					if(request.state == State.sslConnectPendingRead)
					if(readSet.isSet(sock)) {
						sslProceed(request, cast(SslClientSocket) sock);
						continue;
					}
					if(request.state == State.sslConnectPendingWrite)
					if(writeSet.isSet(sock)) {
						sslProceed(request, cast(SslClientSocket) sock);
						continue;
					}

					if(request.state == State.sendingHeaders || request.state == State.sendingBody)
					if(writeSet.isSet(sock)) {
						request.timeoutFromInactivity = MonoTime.currTime + request.requestParameters.timeoutFromInactivity;
						assert(request.sendBuffer.length);
						auto sent = sock.send(request.sendBuffer);
						debug(arsd_http2_verbose) writeln(cast(void*) sock, "<send>", cast(string) request.sendBuffer, "</send>");
						if(sent <= 0) {
							if(wouldHaveBlocked())
								continue;

							request.state = State.aborted;

							request.responseData.code = 3;
							request.responseData.codeText = "send failed to server: " ~ lastSocketError(sock);
							inactive[inactiveCount++] = sock;
							sock.close();
							loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
							if(request.onDataReceived) request.onDataReceived(request);
							continue;

						}
						request.sendBuffer = request.sendBuffer[sent .. $];
						if(request.sendBuffer.length == 0) {
							request.state = State.waitingForResponse;

							debug(arsd_http2_verbose) writeln("all sent");
						}
						if(request.onDataReceived) request.onDataReceived(request);
					}


					if(readSet.isSet(sock)) {
						keep_going:
						request.timeoutFromInactivity = MonoTime.currTime + request.requestParameters.timeoutFromInactivity;
						auto got = sock.receive(buffer);
						debug(arsd_http2_verbose) { if(got < 0) writeln(lastSocketError(sock)); else writeln("====PACKET ",got,"=====",cast(string)buffer[0 .. got],"===/PACKET==="); }
						if(got < 0) {
							if(wouldHaveBlocked())
								continue;
							debug(arsd_http2) writeln("receive error");
							if(request.state != State.complete) {
								request.state = State.aborted;

								request.responseData.code = 3;
								request.responseData.codeText = "receive error from server: " ~ lastSocketError(sock);
							}
							inactive[inactiveCount++] = sock;
							sock.close();
							loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
						} else if(got == 0) {
							// remote side disconnected
							debug(arsd_http2) writeln("remote disconnect");
							if(request.state != State.complete) {
								request.state = State.aborted;

								request.responseData.code = 3;
								request.responseData.codeText = "server disconnected";
							}
							inactive[inactiveCount++] = sock;
							sock.close();
							loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
						} else {
							// data available
							bool stillAlive;

							try {
								stillAlive = request.handleIncomingData(buffer[0 .. got]);
								/+
									state needs to be set and public
									requestData.content/contentText needs to be around
									you need to be able to clear the content and keep processing for things like event sources.
									also need to be able to abort it.

									and btw it should prolly just have evnet source as a pre-packaged thing.
								+/
							} catch (Exception e) {
								debug(arsd_http2_verbose) { import std.stdio; writeln(e); }
								request.state = HttpRequest.State.aborted;
								request.responseData.code = 4;
								request.responseData.codeText = e.msg;

								inactive[inactiveCount++] = sock;
								sock.close();
								loseSocket(request.requestParameters.host, request.requestParameters.port, request.requestParameters.ssl, sock);
							}

							if(!stillAlive || request.state == HttpRequest.State.complete || request.state == HttpRequest.State.aborted) {
								//import std.stdio; writeln(cast(void*) sock, " ", stillAlive, " ", request.state);
								inactive[inactiveCount++] = sock;
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
				}
			}

			killInactives();

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
					if(parts.empty)
						throw new Exception("Corrupted response, bad status line");
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
					if(colon < 0 || colon >= header.length)
						return;
					auto name = toLower(header[0 .. colon]);
					auto value = header[colon + 1 .. $].strip; // skip colon and strip whitespace

					switch(name) {
						case "connection":
							if(value == "close")
								closeSocketWhenComplete = true;
						break;
						case "content-type":
							responseData.contentType = value;
						break;
						case "location":
							responseData.location = value;
						break;
						case "content-length":
							bodyReadingState.contentLengthRemaining = to!int(value);
							// preallocate the buffer for a bit of a performance boost
							responseData.content.reserve(bodyReadingState.contentLengthRemaining);
						break;
						case "transfer-encoding":
							// note that if it is gzipped, it zips first, then chunks the compressed stream.
							// so we should always dechunk first, then feed into the decompressor
							if(value == "chunked")
								bodyReadingState.isChunked = true;
							else throw new Exception("Unknown Transfer-Encoding: " ~ value);
						break;
						case "content-encoding":
							if(value == "gzip") {
								bodyReadingState.isGzipped = true;
								uncompress = new UnCompress();
							} else if(value == "deflate") {
								bodyReadingState.isDeflated = true;
								uncompress = new UnCompress();
							} else throw new Exception("Unknown Content-Encoding: " ~ value);
						break;
						case "set-cookie":
							// handled elsewhere fyi
						break;
						default:
							// ignore
					}

					responseData.headersHash[name] = value;
				}
			}

			size_t position = 0;
			for(position = 0; position < data.length; position++) {
				if(headerReadingState.readingLineContinuation) {
					if(data[position] == ' ' || data[position] == '\t')
						continue;
					headerReadingState.readingLineContinuation = false;
				}

				if(headerReadingState.atStartOfLine) {
					headerReadingState.atStartOfLine = false;
					// FIXME it being \r should never happen... and i don't think it does
					if(data[position] == '\r' || data[position] == '\n') {
						// done with headers

						position++; // skip the \r

						if(responseData.headers.length)
							parseLastHeader();

						if(responseData.code >= 100 && responseData.code < 200) {
							// "100 Continue" - we should continue uploading request data at this point
							// "101 Switching Protocols" - websocket, not expected here...
							// "102 Processing" - server still working, keep the connection alive
							// "103 Early Hints" - can have useful Link headers etc
							//
							// and other unrecognized ones can just safely be skipped

							// FIXME: the headers shouldn't actually be reset; 103 Early Hints
							// can give useful headers we want to keep

							responseData.headers = null;
							headerReadingState.atStartOfLine = true;

							continue; // the \n will be skipped by the for loop advance
						}

						if(this.requestParameters.method == HttpVerb.HEAD)
							state = State.complete;
						else
							state = State.readingBody;

						// skip the \n before we break
						position++;

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
								if(a == 0)
									break; // just wait for more data
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

							int footerReadingState = 0;
							int footerSize;

							while(footerReadingState != 2 && a < data.length) {
								// import std.stdio; writeln(footerReadingState, " ", footerSize, " ", data);
								switch(footerReadingState) {
									case 0:
										if(data[a] == 13)
											footerReadingState++;
										else
											footerSize++;
									break;
									case 1:
										if(data[a] == 10) {
											if(footerSize == 0) {
												// all done, time to break
												footerReadingState++;

											} else {
												// actually had a footer, try to read another
												footerReadingState = 0;
												footerSize = 0;
											}
										} else {
											throw new Exception("bad footer thing");
										}
									break;
									default:
										assert(0);
								}

								a++;
							}

							if(footerReadingState != 2)
								break start_over; // haven't hit the end of the thing yet

							bodyReadingState.chunkedState = 0;
							data = data[a .. $];

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

			} else {
				//if(bodyReadingState.isGzipped || bodyReadingState.isDeflated)
				//	responseData.content ~= cast(ubyte[]) uncompress.uncompress(data);
				//else
					responseData.content ~= data;
				//assert(data.length <= bodyReadingState.contentLengthRemaining, format("%d <= %d\n%s", data.length, bodyReadingState.contentLengthRemaining, cast(string)data));
				{
					int use = cast(int) data.length;
					if(use > bodyReadingState.contentLengthRemaining)
						use = bodyReadingState.contentLengthRemaining;
					bodyReadingState.contentLengthRemaining -= use;
					data = data[use .. $];
				}
				if(bodyReadingState.contentLengthRemaining == 0) {
					if(bodyReadingState.isGzipped || bodyReadingState.isDeflated) {
						// import std.stdio; writeln(responseData.content.length, " ", responseData.content[0 .. 2], " .. ", responseData.content[$-2 .. $]);
						auto n = uncompress.uncompress(responseData.content);
						n ~= uncompress.flush();
						responseData.content = cast(ubyte[]) n;
						responseData.contentText = cast(string) responseData.content;
						//responseData.content ~= cast(ubyte[]) uncompress.flush();
					} else {
						responseData.contentText = cast(string) responseData.content;
					}

					done:

					if(retainCookies && client !is null) {
						client.retainCookies(responseData);
					}

					if(followLocation && responseData.location.length) {
						if(maximumNumberOfRedirectsRemaining <= 0) {
							throw new Exception("Maximum number of redirects exceeded");
						} else {
							maximumNumberOfRedirectsRemaining--;
						}

						static bool first = true;
						//version(DigitalMars) if(!first) asm { int 3; }
						debug(arsd_http2) writeln("redirecting to ", responseData.location);
						populateFromInfo(Uri(responseData.location), HttpVerb.GET);
						//import std.stdio; writeln("redirected to ", responseData.location);
						first = false;
						responseData = HttpResponse.init;
						headerReadingState = HeaderReadingState.init;
						bodyReadingState = BodyReadingState.init;
						if(client !is null) {
							// FIXME: this won't clear cookies that were cleared in another request
							client.populateCookies(this); // they might have changed in the previous redirection cycle!
						}
						state = State.unsent;
						stillAlive = false;
						sendPrivate(false);
					} else {
						state = State.complete;
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

/++
	Waits for the first of the given requests to be either aborted or completed.
	Returns the first one in that state, or `null` if the operation was interrupted
	or reached the given timeout before any completed. (If it returns null even before
	the timeout, it might be because the user pressed ctrl+c, so you should consider
	checking if you should cancel the operation. If not, you can simply call it again
	with the same arguments to start waiting again.)

	You MUST check for null, even if you don't specify a timeout!

	Note that if an individual request times out before any others request, it will
	return that timed out request, since that counts as completion.

	If the return is not null, you should call `waitForCompletion` on the given request
	to get the response out. It will not have to wait since it is guaranteed to be
	finished when returned by this function; that will just give you the cached response.

	(I thought about just having it return the response, but tying a response back to
	a request is harder than just getting the original request object back and taking
	the response out of it.)

	Please note: if a request in the set has already completed or been aborted, it will
	always return the first one it sees upon calling the function. You may wish to remove
	them from the list before calling the function.

	History:
		Added December 24, 2021 (dub v10.5)
+/
HttpRequest waitForFirstToComplete(Duration timeout, HttpRequest[] requests...) {

	foreach(request; requests) {
		if(request.state == HttpRequest.State.unsent)
			request.send();
		else if(request.state == HttpRequest.State.complete)
			return request;
		else if(request.state == HttpRequest.State.aborted)
			return request;
	}

	while(true) {
		if(auto err = HttpRequest.advanceConnections(timeout)) {
			switch(err) {
				case 1: return null;
				case 2: throw new Exception("HttpRequest.advanceConnections returned 2: nothing to do");
				case 3: return null;
				default: throw new Exception("HttpRequest.advanceConnections got err " ~ to!string(err));
			}
		}

		foreach(request; requests) {
			if(request.state == HttpRequest.State.aborted || request.state == HttpRequest.State.complete) {
				request.waitForCompletion();
				return request;
			}
		}

	}
}

/// ditto
HttpRequest waitForFirstToComplete(HttpRequest[] requests...) {
	return waitForFirstToComplete(1.weeks, requests);
}

/++
	An input range that runs [waitForFirstToComplete] but only returning each request once.
	Before you loop over it, you can set some properties to customize behavior.

	If it times out or is interrupted, it will prematurely run empty. You can set the delegate
	to process this.

	Implementation note: each iteration through the loop does a O(n) check over each item remaining.
	This shouldn't matter, but if it does become an issue for you, let me know.

	History:
		Added December 24, 2021 (dub v10.5)
+/
struct HttpRequestsAsTheyComplete {
	/++
		Seeds it with an overall timeout and the initial requests.
		It will send all the requests before returning, then will process
		the responses as they come.

		Please note that it modifies the array of requests you pass in! It
		will keep a reference to it and reorder items on each call of popFront.
		You might want to pass a duplicate if you have another purpose for your
		array and don't want to see it shuffled.
	+/
	this(Duration timeout, HttpRequest[] requests) {
		remainingRequests = requests;
		this.timeout = timeout;
		popFront();
	}

	/++
		You can set this delegate to decide how to handle an interruption. Returning true
		from this will keep working. Returning false will terminate the loop.

		If this is null, an interruption will always terminate the loop.

		Note that interruptions can be caused by the garbage collector being triggered by
		another thread as well as by user action. If you don't set a SIGINT handler, it
		might be reasonable to always return true here.
	+/
	bool delegate() onInterruption;

	private HttpRequest[] remainingRequests;

	/// The timeout you set in the constructor. You can change it if you want.
	Duration timeout;

	/++
		Adds another request to the work queue. It is safe to call this from inside the loop
		as you process other requests.
	+/
	void appendRequest(HttpRequest request) {
		remainingRequests ~= request;
	}

	/++
		If the loop exited, it might be due to an interruption or a time out. If you like, you
		can call this to pick up the work again,

		If it returns `false`, the work is indeed all finished and you should not re-enter the loop.

		---
		auto range = HttpRequestsAsTheyComplete(10.seconds, your_requests);
		process_loop: foreach(req; range) {
			// process req
		}
		// make sure we weren't interrupted because the user requested we cancel!
		// but then try to re-enter the range if possible
		if(!user_quit && range.reenter()) {
			// there's still something unprocessed in there
			// range.reenter returning true means it is no longer
			// empty, so we should try to loop over it again
			goto process_loop; // re-enter the loop
		}
		---
	+/
	bool reenter() {
		if(remainingRequests.length == 0)
			return false;
		empty = false;
		popFront();
		return true;
	}

	/// Standard range primitives. I reserve the right to change the variables to read-only properties in the future without notice.
	HttpRequest front;

	/// ditto
	bool empty;

	/// ditto
	void popFront() {
		resume:
		if(remainingRequests.length == 0) {
			empty = true;
			return;
		}

		front = waitForFirstToComplete(timeout, remainingRequests);

		if(front is null) {
			if(onInterruption) {
				if(onInterruption())
					goto resume;
			}
			empty = true;
			return;
		}
		foreach(idx, req; remainingRequests) {
			if(req is front) {
				remainingRequests[idx] = remainingRequests[$ - 1];
				remainingRequests = remainingRequests[0 .. $ - 1];
				return;
			}
		}
	}
}

//
struct HttpRequestParameters {
	// FIXME: implement these
	//Duration timeoutTotal; // the whole request must finish in this time or else it fails,even if data is still trickling in
	Duration timeoutFromInactivity; // if there's no activity in this time it dies. basically the socket receive timeout

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

	string unixSocketPath; ///

	bool gzipBody; ///
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

/++
	Supported file formats for [HttpClient.setClientCert]. These are loaded by OpenSSL
	in the current implementation.

	History:
		Added February 3, 2022 (dub v10.6)
+/
enum CertificateFileFormat {
	guess, /// try to guess the format from the file name and/or contents
	pem, /// the files are specifically in PEM format
	der /// the files are specifically in DER format
}

/++
	HttpClient keeps cookies, location, and some other state to reuse connections, when possible, like a web browser.
	You can use it as your entry point to make http requests.

	See the example on [arsd.http2#examples].
+/
class HttpClient {
	/* Protocol restrictions, useful to disable when debugging servers */
	bool useHttp11 = true; ///
	bool acceptGzip = true; ///
	bool keepAlive = true; ///

	/++
		Sets the client certificate used as a log in identifier on https connections.
		The certificate and key must be unencrypted at this time and both must be in
		the same file format.

		Bugs:
			The current implementation sets the filenames into a static variable,
			meaning it is shared across all clients and connections.

			Errors in the cert or key are only reported if the server reports an
			authentication failure. Make sure you are passing correct filenames
			and formats of you do see a failure.

		History:
			Added February 2, 2022 (dub v10.6)
	+/
	void setClientCertificate(string certFilename, string keyFilename, CertificateFileFormat certFormat = CertificateFileFormat.guess) {
		this.certFilename = certFilename;
		this.keyFilename = keyFilename;
		this.certFormat = certFormat;
	}

	/++
		Sets whether [HttpRequest]s created through this object (with [navigateTo], [request], etc.), will have the
		value of [HttpRequest.verifyPeer] of true or false upon construction.

		History:
			Added April 5, 2022 (dub v10.8). Previously, there was an undocumented global value used.
	+/
	bool defaultVerifyPeer = true;

	/++
		Adds a header to be automatically appended to each request created through this client.

		If you add duplicate headers, it will add multiple copies.

		You should NOT use this to add headers that can be set through other properties like [userAgent], [authorization], or [setCookie].

		History:
			Added July 12, 2023
	+/
	void addDefaultHeader(string key, string value) {
		defaultHeaders ~= key ~ ": " ~ value;
	}

	private string[] defaultHeaders;

	// FIXME: getCookies api
	// FIXME: an easy way to download files

	// FIXME: try to not make these static
	private static string certFilename;
	private static string keyFilename;
	private static CertificateFileFormat certFormat;

	///
	@property Uri location() {
		return currentUrl;
	}

	/++
		Default timeout for requests created on this client.

		History:
			Added March 31, 2021
	+/
	Duration defaultTimeout = 10.seconds;

	/++
		High level function that works similarly to entering a url
		into a browser.

		Follows locations, retain cookies, updates the current url, etc.
	+/
	HttpRequest navigateTo(Uri where, HttpVerb method = HttpVerb.GET) {
		currentUrl = where.basedOn(currentUrl);
		currentDomain = where.host;

		auto request = this.request(currentUrl, method);
		request.followLocation = true;
		request.retainCookies = true;

		return request;
	}

	/++
		Creates a request without updating the current url state. If you want to save cookies, either call [retainCookies] with the response yourself
		or set [HttpRequest.retainCookies|request.retainCookies] to `true` on the returned object. But see important implementation shortcomings on [retainCookies].

		To upload files, you can use the [FormData] overload.
	+/
	HttpRequest request(Uri uri, HttpVerb method = HttpVerb.GET, ubyte[] bodyData = null, string contentType = null) {
		string proxyToUse = getProxyFor(uri);

		auto request = new HttpRequest(this, uri, method, cache, defaultTimeout, proxyToUse);

		request.verifyPeer = this.defaultVerifyPeer;

		request.requestParameters.userAgent = userAgent;
		request.requestParameters.authorization = authorization;

		request.requestParameters.useHttp11 = this.useHttp11;
		request.requestParameters.acceptGzip = this.acceptGzip;
		request.requestParameters.keepAlive = this.keepAlive;

		request.requestParameters.bodyData = bodyData;
		request.requestParameters.contentType = contentType;

		request.requestParameters.headers = this.defaultHeaders;

		populateCookies(request);

		return request;
	}

	/// ditto
	HttpRequest request(Uri uri, FormData fd, HttpVerb method = HttpVerb.POST) {
		return request(uri, method, fd.toBytes, fd.contentType);
	}


	private void populateCookies(HttpRequest request) {
		// FIXME: what about expiration and the like? or domain/path checks? or Secure checks?
		// FIXME: is uri.host correct? i think it should include port number too. what fun.
		if(auto cookies = ""/*uri.host*/ in this.cookies) {
			foreach(cookie; *cookies)
				request.requestParameters.cookies[cookie.name] = cookie.value;
		}
	}

	private Uri currentUrl;
	private string currentDomain;
	private ICache cache;

	/++

	+/
	this(ICache cache = null) {
		this.defaultVerifyPeer = .defaultVerifyPeer_;
		this.cache = cache;
		loadDefaultProxy();
	}

	/++
		Loads the system-default proxy. Note that the constructor does this automatically
		so you should rarely need to call this explicitly.

		The environment variables are used, if present, on all operating systems.

		History:
			no_proxy support added April 13, 2022

			Added April 12, 2021 (included in dub v9.5)

		Bugs:
			On Windows, it does NOT currently check the IE settings, but I do intend to
			implement that in the future. When I do, it will be classified as a bug fix,
			NOT a breaking change.
	+/
	void loadDefaultProxy() {
		import std.process;
		httpProxy = environment.get("http_proxy", environment.get("HTTP_PROXY", null));
		httpsProxy = environment.get("https_proxy", environment.get("HTTPS_PROXY", null));
		auto noProxy = environment.get("no_proxy", environment.get("NO_PROXY", null));
		if (noProxy.length) {
			proxyIgnore = noProxy.split(",");
			foreach (ref rule; proxyIgnore)
				rule = rule.strip;
		}

		// FIXME: on Windows, I should use the Internet Explorer proxy settings
	}

	/++
		Checks if the given uri should be proxied according to the httpProxy, httpsProxy, proxyIgnore
		variables and returns either httpProxy, httpsProxy or null.

		If neither `httpProxy` or `httpsProxy` are set this always returns `null`. Same if `proxyIgnore`
		contains `*`.

		DNS is not resolved for proxyIgnore IPs, only IPs match IPs and hosts match hosts.
	+/
	string getProxyFor(Uri uri) {
		string proxyToUse;
		switch(uri.scheme) {
			case "http":
				proxyToUse = httpProxy;
			break;
			case "https":
				proxyToUse = httpsProxy;
			break;
			default:
				proxyToUse = null;
		}

		if (proxyToUse.length) {
			foreach (ignore; proxyIgnore) {
				if (matchProxyIgnore(ignore, uri)) {
					return null;
				}
			}
		}

		return proxyToUse;
	}

	/// Returns -1 on error, otherwise the IP as uint. Parsing is very strict.
	private static long tryParseIPv4(scope const(char)[] s) nothrow {
		import std.algorithm : findSplit, all;
		import std.ascii : isDigit;

		static int parseNum(scope const(char)[] num) nothrow {
			if (num.length < 1 || num.length > 3 || !num.representation.all!isDigit)
				return -1;
			try {
				auto ret = num.to!int;
				return ret > 255 ? -1 : ret;
			} catch (Exception) {
				assert(false);
			}
		}

		if (s.length < "0.0.0.0".length || s.length > "255.255.255.255".length)
			return -1;
		auto firstPair = s.findSplit(".");
		auto secondPair = firstPair[2].findSplit(".");
		auto thirdPair = secondPair[2].findSplit(".");
		auto a = parseNum(firstPair[0]);
		auto b = parseNum(secondPair[0]);
		auto c = parseNum(thirdPair[0]);
		auto d = parseNum(thirdPair[2]);
		if (a < 0 || b < 0 || c < 0 || d < 0)
			return -1;
		return (cast(uint)a << 24) | (b << 16) | (c << 8) | (d);
	}

	unittest {
		assert(tryParseIPv4("0.0.0.0") == 0);
		assert(tryParseIPv4("127.0.0.1") == 0x7f000001);
		assert(tryParseIPv4("162.217.114.56") == 0xa2d97238);
		assert(tryParseIPv4("256.0.0.1") == -1);
		assert(tryParseIPv4("0.0.0.-2") == -1);
		assert(tryParseIPv4("0.0.0.a") == -1);
		assert(tryParseIPv4("0.0.0") == -1);
		assert(tryParseIPv4("0.0.0.0.0") == -1);
	}

	/++
		Returns true if the given no_proxy rule matches the uri.

		Invalid IP ranges are silently ignored and return false.

		See $(LREF proxyIgnore).
	+/
	static bool matchProxyIgnore(scope const(char)[] rule, scope const Uri uri) nothrow {
		import std.algorithm;
		import std.ascii : isDigit;
		import std.uni : sicmp;

		string uriHost = uri.host;
		if (uriHost.length && uriHost[$ - 1] == '.')
			uriHost = uriHost[0 .. $ - 1];

		if (rule == "*")
			return true;
		while (rule.length && rule[0] == '.') rule = rule[1 .. $];

		static int parsePort(scope const(char)[] portStr) nothrow {
			if (portStr.length < 1 || portStr.length > 5 || !portStr.representation.all!isDigit)
				return -1;
			try {
				return portStr.to!int;
			} catch (Exception) {
				assert(false, "to!int should succeed");
			}
		}

		if (sicmp(rule, uriHost) == 0
			|| (uriHost.length > rule.length
				&& sicmp(rule, uriHost[$ - rule.length .. $]) == 0
				&& uriHost[$ - rule.length - 1] == '.'))
			return true;

		if (rule.startsWith("[")) { // IPv6
			// below code is basically nothrow lastIndexOfAny("]:")
			ptrdiff_t lastColon = cast(ptrdiff_t) rule.length - 1;
			while (lastColon >= 0) {
				if (rule[lastColon] == ']' || rule[lastColon] == ':')
					break;
				lastColon--;
			}
			if (lastColon == -1)
				return false; // malformed

			if (rule[lastColon] == ':') { // match with port
				auto port = parsePort(rule[lastColon + 1 .. $]);
				if (port != -1) {
					if (uri.effectivePort != port.to!int)
						return false;
					return uriHost == rule[0 .. lastColon];
				}
			}
			// exact match of host already done above
		} else {
			auto slash = rule.lastIndexOfNothrow('/');
			if (slash == -1) { // no IP range
				auto colon = rule.lastIndexOfNothrow(':');
				auto host = colon == -1 ? rule : rule[0 .. colon];
				auto port = colon != -1 ? parsePort(rule[colon + 1 .. $]) : -1;
				auto ip = tryParseIPv4(host);
				if (ip == -1) { // not an IPv4, test for host with port
					return port != -1
						&& uri.effectivePort == port
						&& uriHost == host;
				} else {
					// perform IPv4 equals
					auto other = tryParseIPv4(uriHost);
					if (other == -1)
						return false; // rule == IPv4, uri != IPv4
					if (port != -1)
						return uri.effectivePort == port
							&& uriHost == host;
					else
						return uriHost == host;
				}
			} else {
				auto maskStr = rule[slash + 1 .. $];
				auto ip = tryParseIPv4(rule[0 .. slash]);
				if (ip == -1)
					return false;
				if (maskStr.length && maskStr.length < 3 && maskStr.representation.all!isDigit) {
					// IPv4 range match
					int mask;
					try {
						mask = maskStr.to!int;
					} catch (Exception) {
						assert(false);
					}

					auto other = tryParseIPv4(uriHost);
					if (other == -1)
						return false; // rule == IPv4, uri != IPv4

					if (mask == 0) // matches all
						return true;
					if (mask > 32) // matches none
						return false;

					auto shift = 32 - mask;
					return cast(uint)other >> shift
						== cast(uint)ip >> shift;
				}
			}
		}
		return false;
	}

	unittest {
		assert(matchProxyIgnore("0.0.0.0/0", Uri("http://127.0.0.1:80/a")));
		assert(matchProxyIgnore("0.0.0.0/0", Uri("http://127.0.0.1/a")));
		assert(!matchProxyIgnore("0.0.0.0/0", Uri("https://dlang.org/a")));
		assert(matchProxyIgnore("*", Uri("https://dlang.org/a")));
		assert(matchProxyIgnore("127.0.0.0/8", Uri("http://127.0.0.1:80/a")));
		assert(matchProxyIgnore("127.0.0.0/8", Uri("http://127.0.0.1/a")));
		assert(matchProxyIgnore("127.0.0.1", Uri("http://127.0.0.1:1234/a")));
		assert(!matchProxyIgnore("127.0.0.1:80", Uri("http://127.0.0.1:1234/a")));
		assert(!matchProxyIgnore("127.0.0.1/8", Uri("http://localhost/a"))); // no DNS resolution / guessing
		assert(!matchProxyIgnore("0.0.0.0/1", Uri("http://localhost/a"))
			&& !matchProxyIgnore("128.0.0.0/1", Uri("http://localhost/a"))); // no DNS resolution / guessing 2
		foreach (m; 1 .. 32) {
			assert(matchProxyIgnore(text("127.0.0.1/", m), Uri("http://127.0.0.1/a")));
			assert(!matchProxyIgnore(text("127.0.0.1/", m), Uri("http://128.0.0.1/a")));
			bool expectedMatch = m <= 24;
			assert(expectedMatch == matchProxyIgnore(text("127.0.1.0/", m), Uri("http://127.0.1.128/a")), m.to!string);
		}
		assert(matchProxyIgnore("localhost", Uri("http://localhost/a")));
		assert(matchProxyIgnore("localhost", Uri("http://foo.localhost/a")));
		assert(matchProxyIgnore("localhost", Uri("http://foo.localhost./a")));
		assert(matchProxyIgnore(".localhost", Uri("http://localhost/a")));
		assert(matchProxyIgnore(".localhost", Uri("http://foo.localhost/a")));
		assert(matchProxyIgnore(".localhost", Uri("http://foo.localhost./a")));
		assert(!matchProxyIgnore("foo.localhost", Uri("http://localhost/a")));
		assert(matchProxyIgnore("foo.localhost", Uri("http://foo.localhost/a")));
		assert(matchProxyIgnore("foo.localhost", Uri("http://foo.localhost./a")));
		assert(!matchProxyIgnore("bar.localhost", Uri("http://localhost/a")));
		assert(!matchProxyIgnore("bar.localhost", Uri("http://foo.localhost/a")));
		assert(!matchProxyIgnore("bar.localhost", Uri("http://foo.localhost./a")));
		assert(!matchProxyIgnore("bar.localhost", Uri("http://bbar.localhost./a")));
		assert(matchProxyIgnore("[::1]", Uri("http://[::1]/a")));
		assert(!matchProxyIgnore("[::1]", Uri("http://[::2]/a")));
		assert(matchProxyIgnore("[::1]:80", Uri("http://[::1]/a")));
		assert(!matchProxyIgnore("[::1]:443", Uri("http://[::1]/a")));
		assert(!matchProxyIgnore("[::1]:80", Uri("https://[::1]/a")));
		assert(matchProxyIgnore("[::1]:443", Uri("https://[::1]/a")));
		assert(matchProxyIgnore("google.com", Uri("https://GOOGLE.COM/a")));
	}

	/++
		Proxies to use for requests. The [HttpClient] constructor will set these to the system values,
		then you can reset it to `null` if you want to override and not use the proxy after all, or you
		can set it after construction to whatever.

		The proxy from the client will be automatically set to the requests performed through it. You can
		also override on a per-request basis by creating the request and setting the `proxy` field there
		before sending it.

		History:
			Added April 12, 2021 (included in dub v9.5)
	+/
	string httpProxy;
	/// ditto
	string httpsProxy;
	/++
		List of hosts or ips, optionally including a port, where not to proxy.

		Each entry may be one of the following formats:
		- `127.0.0.1` (IPv4, any port)
		- `127.0.0.1:1234` (IPv4, specific port)
		- `127.0.0.1/8` (IPv4 range / CIDR block, any port)
		- `[::1]` (IPv6, any port)
		- `[::1]:1234` (IPv6, specific port)
		- `*` (all hosts and ports, basically don't proxy at all anymore)
		- `.domain.name`, `domain.name` (don't proxy the specified domain,
			leading dots are stripped and subdomains are also not proxied)
		- `.domain.name:1234`, `domain.name:1234` (same as above, with specific port)

		No DNS resolution or regex is done in this list.

		See https://about.gitlab.com/blog/2021/01/27/we-need-to-talk-no-proxy/

		History:
			Added April 13, 2022
	+/
	string[] proxyIgnore;

	/// See [retainCookies] for important caveats.
	void setCookie(string name, string value, string domain = null) {
		CookieHeader ch;

		ch.name = name;
		ch.value = value;

		setCookie(ch, domain);
	}

	/// ditto
	void setCookie(CookieHeader ch, string domain = null) {
		if(domain is null)
			domain = currentDomain;

		// FIXME: figure all this out or else cookies liable to get too long, in addition to the overwriting and oversharing issues in long scraping sessions
		cookies[""/*domain*/] ~= ch;
	}

	/++
		[HttpClient] does NOT automatically store cookies. You must explicitly retain them from a response by calling this method.

		Examples:
			---
			import arsd.http2;
			void main() {
				auto client = new HttpClient();
				auto setRequest = client.request(Uri("http://arsdnet.net/cgi-bin/cookies/set"));
				auto setResponse = setRequest.waitForCompletion();

				auto request = client.request(Uri("http://arsdnet.net/cgi-bin/cookies/get"));
				auto response = request.waitForCompletion();

				// the cookie wasn't explicitly retained, so the server echos back nothing
				assert(response.responseText.length == 0);

				// now keep the cookies from our original set
				client.retainCookies(setResponse);

				request = client.request(Uri("http://arsdnet.net/cgi-bin/cookies/get"));
				response = request.waitForCompletion();

				// now it matches
				assert(response.responseText.length && response.responseText == setResponse.cookies["example-cookie"]);
			}
			---

		Bugs:
			It does NOT currently implement domain / path / secure separation nor cookie expiration. It assumes that if you call this function, you're ok with it.

			You may want to use separate HttpClient instances if any sharing is unacceptable at this time.

		History:
			Added July 5, 2021 (dub v10.2)
	+/
	void retainCookies(HttpResponse fromResponse) {
		foreach(name, value; fromResponse.cookies)
			setCookie(name, value);
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
	private CookieHeader[][string] cookies;
}

private ptrdiff_t lastIndexOfNothrow(T)(scope T[] arr, T value) nothrow
{
	ptrdiff_t ret = cast(ptrdiff_t)arr.length - 1;
	while (ret >= 0) {
		if (arr[ret] == value)
			return ret;
		ret--;
	}
	return ret;
}

interface ICache {
	/++
		The client is about to make the given `request`. It will ALWAYS pass it to the cache object first so you can decide if you want to and can provide a response. You should probably check the appropriate headers to see if you should even attempt to look up on the cache (HttpClient does NOT do this to give maximum flexibility to the cache implementor).

		Return null if the cache does not provide.
	+/
	const(HttpResponse)* getCachedResponse(HttpRequestParameters request);

	/++
		The given request has received the given response. The implementing class needs to decide if it wants to cache or not. Return true if it was added, false if you chose not to.

		You may wish to examine headers, etc., in making the decision. The HttpClient will ALWAYS pass a request/response to this.
	+/
	bool cacheResponse(HttpRequestParameters request, HttpResponse response);
}

/+
// / Provides caching behavior similar to a real web browser
class HttpCache : ICache {
	const(HttpResponse)* getCachedResponse(HttpRequestParameters request) {
		return null;
	}
}

// / Gives simple maximum age caching, ignoring the actual http headers
class SimpleCache : ICache {
	const(HttpResponse)* getCachedResponse(HttpRequestParameters request) {
		return null;
	}
}
+/

/++
	A pseudo-cache to provide a mock server. Construct one of these,
	populate it with test responses, and pass it to [HttpClient] to
	do a network-free test.

	You should populate it with the [populate] method. Any request not
	pre-populated will return a "server refused connection" response.
+/
class HttpMockProvider : ICache {
	/+ +

	+/
	version(none)
	this(Uri baseUrl, string defaultResponseContentType) {

	}

	this() {}

	HttpResponse defaultResponse;

	/// Implementation of the ICache interface. Hijacks all requests to return a pre-populated response or "server disconnected".
	const(HttpResponse)* getCachedResponse(HttpRequestParameters request) {
		import std.conv;
		auto defaultPort = request.ssl ? 443 : 80;
		string identifier = text(
			request.method, " ",
			request.ssl ? "https" : "http", "://",
			request.host,
			(request.port && request.port != defaultPort) ? (":" ~ to!string(request.port)) : "",
			request.uri
		);

		if(auto res = identifier in population)
			return res;
		return &defaultResponse;
	}

	/// Implementation of the ICache interface. We never actually cache anything here since it is all about mock responses, not actually caching real data.
	bool cacheResponse(HttpRequestParameters request, HttpResponse response) {
		return false;
	}

	/++
		Convenience method to populate simple responses. For more complex
		work, use one of the other overloads where you build complete objects
		yourself.

		Params:
			request = a verb and complete URL to mock as one string.
			For example "GET http://example.com/". If you provide only
			a partial URL, it will be based on the `baseUrl` you gave
			in the `HttpMockProvider` constructor.

			responseCode = the HTTP response code, like 200 or 404.

			response = the response body as a string. It is assumed
			to be of the `defaultResponseContentType` you passed in the
			`HttpMockProvider` constructor.
	+/
	void populate(string request, int responseCode, string response) {

		// FIXME: absolute-ize the URL in the request

		HttpResponse r;
		r.code = responseCode;
		r.codeText = getHttpCodeText(r.code);

		r.content = cast(ubyte[]) response;
		r.contentText = response;

		population[request] = r;
	}

	version(none)
	void populate(string method, string url, HttpResponse response) {
		// FIXME
	}

	private HttpResponse[string] population;
}

// modified from the one in cgi.d to just have the text
private static string getHttpCodeText(int code) pure nothrow @nogc {
	switch(code) {
		// this module's proprietary extensions
		case 0: return null;
		case 1: return "request.abort called";
		case 2: return "connection failed";
		case 3: return "server disconnected";
		case 4: return "exception thrown"; // actually should be some other thing
		case 5: return "Request timed out";

		// * * * standard ones * * *

		// 1xx skipped since they shouldn't happen

		//
		case 200: return "OK";
		case 201: return "Created";
		case 202: return "Accepted";
		case 203: return "Non-Authoritative Information";
		case 204: return "No Content";
		case 205: return "Reset Content";
		//
		case 300: return "Multiple Choices";
		case 301: return "Moved Permanently";
		case 302: return "Found";
		case 303: return "See Other";
		case 307: return "Temporary Redirect";
		case 308: return "Permanent Redirect";
		//
		case 400: return "Bad Request";
		case 403: return "Forbidden";
		case 404: return "Not Found";
		case 405: return "Method Not Allowed";
		case 406: return "Not Acceptable";
		case 409: return "Conflict";
		case 410: return "Gone";
		//
		case 500: return "Internal Server Error";
		case 501: return "Not Implemented";
		case 502: return "Bad Gateway";
		case 503: return "Service Unavailable";
		//
		default: assert(0, "Unsupported http code");
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

string lastSocketError(Socket sock) {
	import std.socket;
	version(use_openssl) {
		if(auto s = cast(OpenSslSocket) sock)
			if(s.lastSocketError.length)
				return s.lastSocketError;
	}
	return std.socket.lastSocketError();
}

// From sslsocket.d, but this is the maintained version!
version(use_openssl) {
	alias SslClientSocket = OpenSslSocket;

	// CRL = Certificate Revocation List
	static immutable string[] sslErrorCodes = [
		"OK (code 0)",
		"Unspecified SSL/TLS error (code 1)",
		"Unable to get TLS issuer certificate (code 2)",
		"Unable to get TLS CRL (code 3)",
		"Unable to decrypt TLS certificate signature (code 4)",
		"Unable to decrypt TLS CRL signature (code 5)",
		"Unable to decode TLS issuer public key (code 6)",
		"TLS certificate signature failure (code 7)",
		"TLS CRL signature failure (code 8)",
		"TLS certificate not yet valid (code 9)",
		"TLS certificate expired (code 10)",
		"TLS CRL not yet valid (code 11)",
		"TLS CRL expired (code 12)",
		"TLS error in certificate not before field (code 13)",
		"TLS error in certificate not after field (code 14)",
		"TLS error in CRL last update field (code 15)",
		"TLS error in CRL next update field (code 16)",
		"TLS system out of memory (code 17)",
		"TLS certificate is self-signed (code 18)",
		"Self-signed certificate in TLS chain (code 19)",
		"Unable to get TLS issuer certificate locally (code 20)",
		"Unable to verify TLS leaf signature (code 21)",
		"TLS certificate chain too long (code 22)",
		"TLS certificate was revoked (code 23)",
		"TLS CA is invalid (code 24)",
		"TLS error: path length exceeded (code 25)",
		"TLS error: invalid purpose (code 26)",
		"TLS error: certificate untrusted (code 27)",
		"TLS error: certificate rejected (code 28)",
	];

	string getOpenSslErrorCode(long error) {
		if(error == 62)
			return "TLS certificate host name mismatch";

		if(error < 0 || error >= sslErrorCodes.length)
			return "SSL/TLS error code " ~ to!string(error);
		return sslErrorCodes[cast(size_t) error];
	}

	struct SSL;
	struct SSL_CTX;
	struct SSL_METHOD;
	struct X509_STORE_CTX;
	enum SSL_VERIFY_NONE = 0;
	enum SSL_VERIFY_PEER = 1;

	// copy it into the buf[0 .. size] and return actual length you read.
	// rwflag == 0 when reading, 1 when writing.
	extern(C) alias pem_password_cb = int function(char* buffer, int bufferSize, int rwflag, void* userPointer);
	extern(C) alias print_errors_cb = int function(const char*, size_t, void*);
	extern(C) alias client_cert_cb = int function(SSL *ssl, X509 **x509, EVP_PKEY **pkey);
	extern(C) alias keylog_cb = void function(SSL*, char*);

	struct X509;
	struct X509_STORE;
	struct EVP_PKEY;
	struct X509_VERIFY_PARAM;

	import core.stdc.config;

	enum SSL_ERROR_WANT_READ = 2;
	enum SSL_ERROR_WANT_WRITE = 3;

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
			void function(SSL*) @nogc nothrow SSL_free;
			void function(SSL_CTX*) @nogc nothrow SSL_CTX_free;

			int function(const SSL*) SSL_pending;
			int function (const SSL *ssl, int ret) SSL_get_error;

			void function(SSL*, int, void*) SSL_set_verify;

			void function(SSL*, int, c_long, void*) SSL_ctrl;

			SSL_METHOD* function() SSLv3_client_method;
			SSL_METHOD* function() TLS_client_method;

			void function(SSL_CTX*, void function(SSL*, char* line)) SSL_CTX_set_keylog_callback;

			int function(SSL_CTX*) SSL_CTX_set_default_verify_paths;

			X509_STORE* function(SSL_CTX*) SSL_CTX_get_cert_store;
			c_long function(const SSL* ssl) SSL_get_verify_result;

			X509_VERIFY_PARAM* function(const SSL*) SSL_get0_param;

			/+
			SSL_CTX_load_verify_locations
			SSL_CTX_set_client_CA_list
			+/

			// client cert things
			void function (SSL_CTX *ctx, int function(SSL *ssl, X509 **x509, EVP_PKEY **pkey)) SSL_CTX_set_client_cert_cb;
		}
	}

	struct eallib {
		__gshared static extern(C) {
			/* these are only on older openssl versions { */
				void function() OpenSSL_add_all_ciphers;
				void function() OpenSSL_add_all_digests;
			/* } */

			const(char)* function(int) OpenSSL_version;

			void function(ulong, void*) OPENSSL_init_crypto;

			void function(print_errors_cb, void*) ERR_print_errors_cb;

			void function(X509*) X509_free;
			int function(X509_STORE*, X509*) X509_STORE_add_cert;


			X509* function(FILE *fp, X509 **x, pem_password_cb *cb, void *u) PEM_read_X509;
			EVP_PKEY* function(FILE *fp, EVP_PKEY **x, pem_password_cb *cb, void* userPointer) PEM_read_PrivateKey;

			EVP_PKEY* function(FILE *fp, EVP_PKEY **a) d2i_PrivateKey_fp;
			X509* function(FILE *fp, X509 **x) d2i_X509_fp;

			X509* function(X509** a, const(ubyte*)* pp, c_long length) d2i_X509;
			int function(X509* a, ubyte** o) i2d_X509;

			int function(X509_VERIFY_PARAM* a, const char* b, size_t l) X509_VERIFY_PARAM_set1_host;

			X509* function(X509_STORE_CTX *ctx) X509_STORE_CTX_get_current_cert;
			int function(X509_STORE_CTX *ctx) X509_STORE_CTX_get_error;
		}
	}

	struct OpenSSL {
		static:

		static Error notLoadedError;
		static this() {
			notLoadedError = new object.Error("will be overwritten");
		}

		template opDispatch(string name) {
			auto opDispatch(T...)(T t) {
				static if(__traits(hasMember, ossllib, name)) {
					auto ptr = __traits(getMember, ossllib, name);
				} else static if(__traits(hasMember, eallib, name)) {
					auto ptr = __traits(getMember, eallib, name);
				} else static assert(0);

				if(ptr is null) {
					notLoadedError.msg = name;
					throw notLoadedError;//(name ~ " not loaded");
				}
				return ptr(t);
			}
		}

		// macros in the original C
		SSL_METHOD* SSLv23_client_method() {
			if(ossllib.SSLv23_client_method)
				return ossllib.SSLv23_client_method();
			else
				return ossllib.TLS_client_method();
		}

		void SSL_set_tlsext_host_name(SSL* a, const char* b) {
			if(ossllib.SSL_ctrl)
				return ossllib.SSL_ctrl(a, 55 /*SSL_CTRL_SET_TLSEXT_HOSTNAME*/, 0 /*TLSEXT_NAMETYPE_host_name*/, cast(void*) b);
			else throw new Exception("SSL_set_tlsext_host_name not loaded");
		}

		// special case
		@trusted nothrow @nogc int SSL_shutdown(SSL* a) {
			if(ossllib.SSL_shutdown)
				return ossllib.SSL_shutdown(a);
			assert(0);
		}

		void SSL_CTX_keylog_cb_func(SSL_CTX* ctx, keylog_cb func) {
			// this isn't in openssl 1.0 and is non-essential, so it is allowed to fail.
			if(ossllib.SSL_CTX_set_keylog_callback)
				ossllib.SSL_CTX_set_keylog_callback(ctx, func);
			//else throw new Exception("SSL_CTX_keylog_cb_func not loaded");
		}

	}

	extern(C)
	int collectSslErrors(const char* ptr, size_t len, void* user) @trusted {
		string* s = cast(string*) user;

		(*s) ~= ptr[0 .. len];

		return 0;
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
	import arsd.core : SynchronizableObject;

	private __gshared SynchronizableObject loadSslMutex = new SynchronizableObject;
	private __gshared bool sslLoaded = false;

	void loadOpenSsl() {
		if(sslLoaded)
			return;
	synchronized(loadSslMutex) {

		version(Posix) {
			version(OSX) {
				static immutable string[] ossllibs = [
					"libssl.46.dylib",
					"libssl.44.dylib",
					"libssl.43.dylib",
					"libssl.35.dylib",
					"libssl.1.1.dylib",
					"libssl.dylib",
					"/usr/local/opt/openssl/lib/libssl.1.0.0.dylib",
				];
			} else {
				static immutable string[] ossllibs = [
					"libssl.so.3",
					"libssl.so.1.1",
					"libssl.so.1.0.2",
					"libssl.so.1.0.1",
					"libssl.so.1.0.0",
					"libssl.so",
				];
			}

			foreach(lib; ossllibs) {
				ossllib_handle = dlopen(lib.ptr, RTLD_NOW);
				if(ossllib_handle !is null) break;
			}
		} else version(Windows) {
			version(X86_64) {
				ossllib_handle = LoadLibraryW("libssl-1_1-x64.dll"w.ptr);
				oeaylib_handle = LoadLibraryW("libcrypto-1_1-x64.dll"w.ptr);
			}

			static immutable wstring[] ossllibs = [
				"libssl-3-x64.dll"w,
				"libssl-3.dll"w,
				"libssl-1_1.dll"w,
				"libssl32.dll"w,
			];

			if(ossllib_handle is null)
			foreach(lib; ossllibs) {
				ossllib_handle = LoadLibraryW(lib.ptr);
				if(ossllib_handle !is null) break;
			}

			static immutable wstring[] eaylibs = [
				"libcrypto-3-x64.dll"w,
				"libcrypto-3.dll"w,
				"libcrypto-1_1.dll"w,
				"libeay32.dll",
			];

			if(oeaylib_handle is null)
			foreach(lib; eaylibs) {
				oeaylib_handle = LoadLibraryW(lib.ptr);
				if (oeaylib_handle !is null) break;
			}

			if(ossllib_handle is null) {
				ossllib_handle = LoadLibraryW("ssleay32.dll"w.ptr);
				oeaylib_handle = ossllib_handle;
			}
		}

		if(ossllib_handle is null)
			throw new Exception("libssl library not found");
		if(oeaylib_handle is null)
			throw new Exception("libeay32 library not found");

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

		sslLoaded = true;
	}
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
	extern(C)
	void write_to_file(SSL* ssl, char* line)
	{
		import std.stdio;
		import std.string;
		import std.process : environment;
		string logfile = environment.get("SSLKEYLOGFILE");
		if (logfile !is null)
		{
			auto f = std.stdio.File(logfile, "a+");
			f.writeln(fromStringz(line));
			f.close();
		}
	}

	class OpenSslSocket : Socket {
		private SSL* ssl;
		private SSL_CTX* ctx;
		private void initSsl(bool verifyPeer, string hostname) {
			ctx = OpenSSL.SSL_CTX_new(OpenSSL.SSLv23_client_method());
			assert(ctx !is null);

			debug OpenSSL.SSL_CTX_keylog_cb_func(ctx, &write_to_file);
			ssl = OpenSSL.SSL_new(ctx);

			if(hostname.length) {
				OpenSSL.SSL_set_tlsext_host_name(ssl, toStringz(hostname));
				if(verifyPeer)
					OpenSSL.X509_VERIFY_PARAM_set1_host(OpenSSL.SSL_get0_param(ssl), hostname.ptr, hostname.length);
			}

			if(verifyPeer) {
				OpenSSL.SSL_CTX_set_default_verify_paths(ctx);

				version(Windows) {
					loadCertificatesFromRegistry(ctx);
				}

				OpenSSL.SSL_set_verify(ssl, SSL_VERIFY_PEER, &verifyCertificateFromRegistryArsdHttp);
			} else
				OpenSSL.SSL_set_verify(ssl, SSL_VERIFY_NONE, null);

			OpenSSL.SSL_set_fd(ssl, cast(int) this.handle); // on win64 it is necessary to truncate, but the value is never large anyway see http://openssl.6102.n7.nabble.com/Sockets-windows-64-bit-td36169.html


			OpenSSL.SSL_CTX_set_client_cert_cb(ctx, &cb);
		}

		extern(C)
		static int cb(SSL* ssl, X509** x509, EVP_PKEY** pkey) {
			if(HttpClient.certFilename.length && HttpClient.keyFilename.length) {
				FILE* fpCert = fopen((HttpClient.certFilename ~ "\0").ptr, "rb");
				if(fpCert is null)
					return 0;
				scope(exit)
					fclose(fpCert);
				FILE* fpKey = fopen((HttpClient.keyFilename ~ "\0").ptr, "rb");
				if(fpKey is null)
					return 0;
				scope(exit)
					fclose(fpKey);

				with(CertificateFileFormat)
				final switch(HttpClient.certFormat) {
					case guess:
						if(HttpClient.certFilename.endsWith(".pem") || HttpClient.keyFilename.endsWith(".pem"))
							goto case pem;
						else
							goto case der;
					case pem:
						*x509 = OpenSSL.PEM_read_X509(fpCert, null, null, null);
						*pkey = OpenSSL.PEM_read_PrivateKey(fpKey, null, null, null);
					break;
					case der:
						*x509 = OpenSSL.d2i_X509_fp(fpCert, null);
						*pkey = OpenSSL.d2i_PrivateKey_fp(fpKey, null);
					break;
				}

				return 1;
			}

			return 0;
		}

		final bool dataPending() {
			return OpenSSL.SSL_pending(ssl) > 0;
		}

		@trusted
		override void connect(Address to) {
			super.connect(to);
			if(blocking) {
				do_ssl_connect();
			}
		}

		private string lastSocketError;

		@trusted
		// returns true if it is finished, false if it would have blocked, throws if there's an error
		int do_ssl_connect() {
			if(OpenSSL.SSL_connect(ssl) == -1) {

				auto errCode = OpenSSL.SSL_get_error(ssl, -1);
				if(errCode == SSL_ERROR_WANT_READ || errCode == SSL_ERROR_WANT_WRITE) {
					return errCode;
				}

				string str;
				OpenSSL.ERR_print_errors_cb(&collectSslErrors, &str);

				auto err = OpenSSL.SSL_get_verify_result(ssl);
				this.lastSocketError = str ~ " " ~ getOpenSslErrorCode(err);

				throw new Exception("Secure connect failed: " ~ getOpenSslErrorCode(err));
			} else this.lastSocketError = null;

			return 0;
		}

		@trusted
		override ptrdiff_t send(scope const(void)[] buf, SocketFlags flags) {
		//import std.stdio;writeln(cast(string) buf);
			debug(arsd_http2_verbose) writeln("ssl writing ", buf.length);
			auto retval = OpenSSL.SSL_write(ssl, buf.ptr, cast(uint) buf.length);

			// don't need to throw anymore since it is checked elsewhere
			// code useful sometimes for debugging hence commenting instead of deleting
			if(retval == -1) {
				string str;
				OpenSSL.ERR_print_errors_cb(&collectSslErrors, &str);
				this.lastSocketError = str;

				// throw new Exception("ssl send failed " ~ str);
			} else this.lastSocketError = null;
			return retval;

		}
		override ptrdiff_t send(scope const(void)[] buf) {
			return send(buf, SocketFlags.NONE);
		}
		@trusted
		override ptrdiff_t receive(scope void[] buf, SocketFlags flags) {

			debug(arsd_http2_verbose) writeln("ssl_read before");
			auto retval = OpenSSL.SSL_read(ssl, buf.ptr, cast(int)buf.length);
			debug(arsd_http2_verbose) writeln("ssl_read after");

			// don't need to throw anymore since it is checked elsewhere
			// code useful sometimes for debugging hence commenting instead of deleting
			if(retval == -1) {

				string str;
				OpenSSL.ERR_print_errors_cb(&collectSslErrors, &str);
				this.lastSocketError = str;

				// throw new Exception("ssl receive failed " ~ str);
			} else this.lastSocketError = null;
			return retval;
		}
		override ptrdiff_t receive(scope void[] buf) {
			return receive(buf, SocketFlags.NONE);
		}

		this(AddressFamily af, SocketType type = SocketType.STREAM, string hostname = null, bool verifyPeer = true) {
			version(Windows) __traits(getMember, this, "_blocking") = true; // lol longstanding phobos bug setting this to false on init
			super(af, type);
			initSsl(verifyPeer, hostname);
		}

		override void close() scope @trusted {
			if(ssl) OpenSSL.SSL_shutdown(ssl);
			super.close();
			freeSsl();
		}

		this(socket_t sock, AddressFamily af, string hostname, bool verifyPeer = true) {
			super(sock, af);
			initSsl(verifyPeer, hostname);
		}

		void freeSsl() @nogc nothrow {
			if(ssl is null)
				return;
			OpenSSL.SSL_free(ssl);
			OpenSSL.SSL_CTX_free(ctx);
			ssl = null;
			ctx = null;
		}

		~this() {
			freeSsl();
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

	/+
		Fun fact, you can also write that:

		var args = [
			"title": "My Pull Request".var,
			"head": "yourusername:" ~ branchName.var,
			"base" : "master".var,
			"body" : "My cool PR is opened by the API!".var,
			"maintainer_can_modify": true.var
		];

		Note the .var constructor calls in there. If everything is the same type, you actually don't need that, but here since there's strings and bools, D won't allow the literal without explicit constructors to align them all.
	+/

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
	string authType = "Bearer";

	/++
		Params:

		urlBase = The base url for the api. Tends to be something like `https://api.example.com/v2/` or similar.
		oauth2Token = the authorization token for the service. You'll have to get it from somewhere else.
		submittedContentType = the content-type of POST, PUT, etc. bodies.
		httpClient = an injected http client, or null if you want to use a default-constructed one

		History:
			The `httpClient` param was added on December 26, 2020.
	+/
	this(string urlBase, string oauth2Token, string submittedContentType = "application/json", HttpClient httpClient = null) {
		if(httpClient is null)
			this.httpClient = new HttpClient();
		else
			this.httpClient = httpClient;

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
			req.requestParameters.headers ~= "Authorization: "~ authType ~" " ~ oauth2Token;
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
			string result;
			foreach(idx, part; pathParts) {
				if(idx)
					result ~= "/";
				result ~= encodeUriComponent(part);
			}
			result ~= "?";
			foreach(idx, part; queryParts) {
				if(idx)
					result ~= "&";
				result ~= encodeUriComponent(part[0]);
				result ~= "=";
				result ~= encodeUriComponent(part[1]);
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
						answer ~= encodeUriComponent(val); // it had better be a string! lol
						answer ~= "=";
					} else {
						answer ~= encodeUriComponent(to!string(val));
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
/++
	Creates a multipart/form-data object that is suitable for file uploads and other kinds of POST.

	It has a set of names and values of mime components. Names can be repeated. They will be presented in the same order in which you add them. You will mostly want to use the [append] method.

	You can pass this directly to [HttpClient.request].

	Based on: https://developer.mozilla.org/en-US/docs/Web/API/FormData

	---
		auto fd = new FormData();
		// add some data, plain string first
		fd.append("name", "Adam");
		// then a file
		fd.append("photo", std.file.read("adam.jpg"), "image/jpeg", "adam.jpg");

		// post it!
		auto client = new HttpClient();
		client.request(Uri("http://example.com/people"), fd).waitForCompletion();
	---

	History:
		Added June 8, 2018
+/
class FormData {
	static struct MimePart {
		string name;
		const(void)[] data;
		string contentType;
		string filename;
	}

	private MimePart[] parts;
	private string boundary = "0016e64be86203dd36047610926a"; // FIXME

	/++
		Appends the given entry to the request. This can be a simple key/value pair of strings or file uploads.

		For a simple key/value pair, leave `contentType` and `filename` as `null`.

		For file uploads, please note that many servers require filename be given for a file upload and it may not allow you to put in a path. I suggest using [std.path.baseName] to strip off path information from a file you are loading.

		The `contentType` is generally verified by servers for file uploads.
	+/
	void append(string key, const(void)[] value, string contentType = null, string filename = null) {
		parts ~= MimePart(key, value, contentType, filename);
	}

	/++
		Deletes any entries from the set with the given key.

		History:
			Added June 7, 2023 (dub v11.0)
	+/
	void deleteKey(string key) {
		MimePart[] newParts;
		foreach(part; parts)
			if(part.name != key)
				newParts ~= part;
		parts = newParts;
	}

	/++
		Returns the first entry with the given key, or `MimePart.init` if there is nothing.

		History:
			Added June 7, 2023 (dub v11.0)
	+/
	MimePart get(string key) {
		foreach(part; parts)
			if(part.name == key)
				return part;
		return MimePart.init;
	}

	/++
		Returns the all entries with the given key.

		History:
			Added June 7, 2023 (dub v11.0)
	+/
	MimePart[] getAll(string key) {
		MimePart[] answer;
		foreach(part; parts)
			if(part.name == key)
				answer ~= part;
		return answer;
	}

	/++
		Returns true if the given key exists in the set.

		History:
			Added June 7, 2023 (dub v11.0)
	+/
	bool has(string key) {
		return get(key).name == key;
	}

	/++
		Sets the given key to the given value if it exists, or appends it if it doesn't.

		You probably want [append] instead.

		See_Also:
			[append]

		History:
			Added June 7, 2023 (dub v11.0)
	+/
	void set(string key, const(void)[] value, string contentType, string filename) {
		foreach(ref part; parts)
			if(part.name == key) {
				part.data = value;
				part.contentType = contentType;
				part.filename = filename;
				return;
			}

		append(key, value, contentType, filename);
	}

	/++
		Returns all the current entries in the object.

		History:
			Added June 7, 2023 (dub v11.0)
	+/
	MimePart[] entries() {
		return parts;
	}

	// FIXME:
	// keys iterator
	// values iterator

	/++
		Gets the content type header that should be set in the request. This includes the type and boundary that is applicable to the [toBytes] method.
	+/
	string contentType() {
		return "multipart/form-data; boundary=" ~ boundary;
	}

	/++
		Returns bytes applicable for the body of this request. Use the [contentType] method to get the appropriate content type header with the right boundary.
	+/
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
		import arsd.http2;

		void main() {
			auto ws = new WebSocket(Uri("ws://...."));

			ws.onmessage = (in char[] msg) {
				ws.send("a reply");
			};

			ws.connect();

			WebSocket.eventLoop();
		}
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

	private string host;
	private ushort port;
	private bool ssl;

	// used to decide if we mask outgoing msgs
	private bool isClient;

	private MonoTime timeoutFromInactivity;
	private MonoTime nextPing;

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
			version(with_openssl) {
				loadOpenSsl();
				socket = new SslClientSocket(family(uri.unixSocketPath), SocketType.STREAM, host, config.verifyPeer);
			} else
				throw new Exception("SSL not compiled in");
		} else
			socket = new Socket(family(uri.unixSocketPath), SocketType.STREAM);

		socket.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
		cookies = config.cookies;
	}

	/++

	+/
	/// Group: foundational
	void connect() {
		this.isClient = true;

		socket.blocking = false;

		if(uri.unixSocketPath)
			socket.connect(new UnixAddress(uri.unixSocketPath));
		else
			socket.connect(new InternetAddress(host, port)); // FIXME: ipv6 support...


		auto readSet = new SocketSet();
		auto writeSet = new SocketSet();

		readSet.reset();
		writeSet.reset();

		readSet.add(socket);
		writeSet.add(socket);

		auto selectGot = Socket.select(readSet, writeSet, null, config.timeoutFromInactivity);
		if(selectGot == -1) {
			// interrupted

			throw new Exception("Websocket connection interrupted - retry might succeed");
		} else if(selectGot == 0) {
			// time out
			socket.close();
			throw new Exception("Websocket connection timed out");
		} else {
			if(writeSet.isSet(socket) || readSet.isSet(socket)) {
				import core.stdc.stdint;
				int32_t error;
				int retopt = socket.getOption(SocketOptionLevel.SOCKET, SocketOption.ERROR, error);
				if(retopt < 0 || error != 0) {
					socket.close();
					throw new Exception("Websocket connection failed - " ~ formatSocketError(error));
				} else {
					// FIXME: websocket handshake could and really should be async too.
					socket.blocking = true; // just convenience
					if(auto s = cast(SslClientSocket) socket) {
						s.do_ssl_connect();
					} else {
						// we're ready
					}
				}
			}
		}

		auto uri = this.uri.path.length ? this.uri.path : "/";
		if(this.uri.query.length) {
			uri ~= "?";
			uri ~= this.uri.query;
		}

		// the headers really shouldn't be bigger than this, at least
		// the chunks i need to process
		ubyte[4096] bufferBacking = void;
		ubyte[] buffer = bufferBacking[];
		size_t pos;

		void append(in char[][] items...) {
			foreach(what; items) {
				if((pos + what.length) > buffer.length) {
					buffer.length += 4096;
				}
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
		if(cookies.length > 0) {
			append("Cookie: ");
			bool first=true;
			foreach(k,v;cookies) {
				if(first) first = false;
				else append("; ");
				append(k);
				append("=");
				append(v);
			}
			append("\r\n");
		}
		/*
		//This is equivalent but has dependencies
		import std.format;
		import std.algorithm : map;
		append(format("cookie: %-(%s %)\r\n",cookies.byKeyValue.map!(t=>format("%s=%s",t.key,t.value))));
		*/

		if(config.protocol.length)
			append("Sec-WebSocket-Protocol: ", config.protocol, "\r\n");
		if(config.origin.length)
			append("Origin: ", config.origin, "\r\n");

		foreach(h; config.additionalHeaders) {
			append(h);
			append("\r\n");
		}

		append("\r\n");

		auto remaining = buffer[0 .. pos];
		//import std.stdio; writeln(host, " " , port, " ", cast(string) remaining);
		while(remaining.length) {
			auto r = socket.send(remaining);
			if(r < 0)
				throw new Exception(lastSocketError(socket));
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
				throw new Exception(lastSocketError(socket));
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
			throw new Exception("Remote server disconnected or didn't send enough information");

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

		nextPing = MonoTime.currTime + config.pingFrequency.msecs;
		timeoutFromInactivity = MonoTime.currTime + config.timeoutFromInactivity;

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

		readSet.reset();

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
		if(readyState == CONNECTING)
			throw new Exception("WebSocket not connected when trying to send. Did you forget to call connect(); ?");
			//connect();
			//import std.stdio; writeln("LLSEND: ", d);
		while(d.length) {
			auto r = socket.send(d);
			if(r < 0 && wouldHaveBlocked()) {
				// FIXME: i should register for a write wakeup
				version(use_arsd_core) assert(0);
				import core.thread;
				Thread.sleep(1.msecs);
				continue;
			}
			//import core.stdc.errno; import std.stdio; writeln(errno);
			if(r <= 0) {
				// import std.stdio; writeln(GetLastError());
				throw new Exception("Socket send failed");
			}
			d = d[r .. $];
		}
	}

	private void llclose() {
		// import std.stdio; writeln("LLCLOSE");
		socket.shutdown(SocketShutdown.SEND);
	}

	/++
		Waits for more data off the low-level socket and adds it to the pending buffer.

		Returns `true` if the connection is still active.
	+/
	/// Group: blocking_api
	public bool lowLevelReceive() {
		if(readyState == CONNECTING)
			throw new Exception("WebSocket not connected when trying to receive. Did you forget to call connect(); ?");
		if (receiveBufferUsedLength == receiveBuffer.length)
		{
			if (receiveBuffer.length == config.maximumReceiveBufferSize)
				throw new Exception("Maximum receive buffer size exhausted");

			import std.algorithm : min;
			receiveBuffer.length = min(receiveBuffer.length + config.initialReceiveBufferSize,
				config.maximumReceiveBufferSize);
		}
		auto r = socket.receive(receiveBuffer[receiveBufferUsedLength .. $]);
		if(r == 0)
			return false;
		if(r < 0 && wouldHaveBlocked())
			return true;
		if(r <= 0) {
			//import std.stdio; writeln(WSAGetLastError());
			return false;
		}
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

		/++
			Additional headers to put in the HTTP request. These should be formatted `Name: value`, like for example:

			---
			Config config;
			config.additionalHeaders ~= "Authorization: Bearer your_auth_token_here";
			---

			History:
				Added February 19, 2021 (included in dub version 9.2)
		+/
		string[] additionalHeaders;

		/++
			Amount of time (in msecs) of idleness after which to send an automatic ping

			Please note how this interacts with [timeoutFromInactivity] - a ping counts as activity that
			keeps the socket alive.
		+/
		int pingFrequency = 5000;

		/++
			Amount of time to disconnect when there's no activity. Note that automatic pings will keep the connection alive; this timeout only occurs if there's absolutely nothing, including no responses to websocket ping frames. Since the default [pingFrequency] is only seconds, this one minute should never elapse unless the connection is actually dead.

			The one thing to keep in mind is if your program is busy and doesn't check input, it might consider this a time out since there's no activity. The reason is that your program was busy rather than a connection failure, but it doesn't care. You should avoid long processing periods anyway though!

			History:
				Added March 31, 2021 (included in dub version 9.4)
		+/
		Duration timeoutFromInactivity = 1.minutes;

		/++
			For https connections, if this is `true`, it will fail to connect if the TLS certificate can not be
			verified. Setting this to `false` will skip this check and allow the connection to continue anyway.

			History:
				Added April 5, 2022 (dub v10.8)

				Prior to this, it always used the global (but undocumented) `defaultVerifyPeer` setting, and sometimes
				even if it was true, it would skip the verification. Now, it always respects this local setting.
		+/
		bool verifyPeer = true;
	}

	/++
		Returns one of [CONNECTING], [OPEN], [CLOSING], or [CLOSED].
	+/
	int readyState() {
		return readyState_;
	}

	/++
		Closes the connection, sending a graceful teardown message to the other side.
		If you provide no arguments, it sends code 1000, normal closure. If you provide
		a code, you should also provide a short reason string.

		Params:
			code = reason code.

			0-999 are invalid.
			1000-2999 are defined by the RFC. [https://www.rfc-editor.org/rfc/rfc6455.html#section-7.4.1]
				1000 - normal finish
				1001 - endpoint going away
				1002 - protocol error
				1003 - unacceptable data received (e.g. binary message when you can't handle it)
				1004 - reserved
				1005 - missing status code (should not be set except by implementations)
				1006 - abnormal connection closure (should only be set by implementations)
				1007 - inconsistent data received (i.e. utf-8 decode error in text message)
				1008 - policy violation
				1009 - received message too big
				1010 - client aborting due to required extension being unsupported by the server
				1011 - server had unexpected failure
				1015 - reserved for TLS handshake failure
			3000-3999 are to be registered with IANA.
			4000-4999 are private-use custom codes depending on the application. These are what you'd most commonly set here.

			reason = <= 123 bytes of human-readable reason text, used for logs and debugging

		History:
			The default `code` was changed to 1000 on January 9, 2023. Previously it was 0,
			but also ignored anyway.

			On May 11, 2024, the optional arguments were changed to overloads since if you provide a code, you should also provide a reason.
	+/
	/// Group: foundational
	void close() {
		close(1000, null);
	}

	/// ditto
	void close(int code, string reason)
		//in (reason.length < 123)
		in { assert(reason.length <= 123); } do
	{
		if(readyState_ != OPEN)
			return; // it cool, we done
		WebSocketFrame wss;
		wss.fin = true;
		wss.masked = this.isClient;
		wss.opcode = WebSocketOpcode.close;
		wss.data = [ubyte((code >> 8) & 0xff), ubyte(code & 0xff)] ~ cast(ubyte[]) reason.dup;
		wss.send(&llsend);

		readyState_ = CLOSING;

		closeCalled = true;

		llclose();
	}

	deprecated("If you provide a code, please also provide a reason string") void close(int code) {
		close(code, null);
	}


	private bool closeCalled;

	/++
		Sends a ping message to the server. This is done automatically by the library if you set a non-zero [Config.pingFrequency], but you can also send extra pings explicitly as well with this function.
	+/
	/// Group: foundational
	void ping(in ubyte[] data = null) {
		WebSocketFrame wss;
		wss.fin = true;
		wss.masked = this.isClient;
		wss.opcode = WebSocketOpcode.ping;
		if(data !is null) wss.data = data.dup;
		wss.send(&llsend);
	}

	/++
		Sends a pong message to the server. This is normally done automatically in response to pings.
	+/
	/// Group: foundational
	void pong(in ubyte[] data = null) {
		WebSocketFrame wss;
		wss.fin = true;
		wss.masked = this.isClient;
		wss.opcode = WebSocketOpcode.pong;
		if(data !is null) wss.data = data.dup;
		wss.send(&llsend);
	}

	/++
		Sends a text message through the websocket.
	+/
	/// Group: foundational
	void send(in char[] textData) {
		WebSocketFrame wss;
		wss.fin = true;
		wss.masked = this.isClient;
		wss.opcode = WebSocketOpcode.text;
		wss.data = cast(ubyte[]) textData.dup;
		wss.send(&llsend);
	}

	/++
		Sends a binary message through the websocket.
	+/
	/// Group: foundational
	void send(in ubyte[] binaryData) {
		WebSocketFrame wss;
		wss.masked = this.isClient;
		wss.fin = true;
		wss.opcode = WebSocketOpcode.binary;
		wss.data = cast(ubyte[]) binaryData.dup;
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
			if(lowLevelReceive() == false)
				return false;
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
			m.unmaskInPlace();
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

					//import std.stdio; writeln("closed ", cast(string) m.data);

					ushort code = CloseEvent.StandardCloseCodes.noStatusCodePresent;
					const(char)[] reason;

					if(m.data.length >= 2) {
						code = (m.data[0] << 8) | m.data[1];
						reason = (cast(char[]) m.data[2 .. $]);
					}

					if(onclose)
						onclose(CloseEvent(code, reason, true));

					// if we receive one and haven't sent one back we're supposed to echo it back and close.
					if(!closeCalled)
						close(code, reason.idup);

					readyState_ = CLOSED;

					unregisterActiveSocket(this);
					socket.close();
				break;
				case WebSocketOpcode.ping:
					// import std.stdio; writeln("ping received ", m.data);
					pong(m.data);
				break;
				case WebSocketOpcode.pong:
					// import std.stdio; writeln("pong received ", m.data);
					// just really references it is still alive, nbd.
				break;
				default: // ignore though i could and perhaps should throw too
			}
		}

		if(d.length) {
			m.data = m.data.dup();
		}

		import core.stdc.string;
		memmove(receiveBuffer.ptr, d.ptr, d.length);
		receiveBufferUsedLength = d.length;

		return m;
	}

	private void autoprocess() {
		// FIXME
		do {
			processOnce();
		} while(lowLevelReceive());
	}

	/++
		Arguments for the close event. The `code` and `reason` are provided from the close message on the websocket, if they are present. The spec says code 1000 indicates a normal, default reason close, but reserves the code range from 3000-5000 for future definition; the 3000s can be registered with IANA and the 4000's are application private use. The `reason` should be user readable, but not displayed to the end user. `wasClean` is true if the server actually sent a close event, false if it just disconnected.

		$(PITFALL
			The `reason` argument references a temporary buffer and there's no guarantee it will remain valid once your callback returns. It may be freed and will very likely be overwritten. If you want to keep the reason beyond the callback, make sure you `.idup` it.
		)

		History:
			Added March 19, 2023 (dub v11.0).
	+/
	static struct CloseEvent {
		ushort code;
		const(char)[] reason;
		bool wasClean;

		string extendedErrorInformationUnstable;

		/++
			See https://www.rfc-editor.org/rfc/rfc6455#section-7.4.1 for details.
		+/
		enum StandardCloseCodes {
			purposeFulfilled = 1000,
			goingAway = 1001,
			protocolError = 1002,
			unacceptableData = 1003, // e.g. got text message when you can only handle binary
			Reserved = 1004,
			noStatusCodePresent = 1005, // not set by endpoint.
			abnormalClosure = 1006, // not set by endpoint. closed without a Close control. FIXME: maybe keep a copy of errno around for these
			inconsistentData = 1007, // e.g. utf8 validation failed
			genericPolicyViolation = 1008,
			messageTooBig = 1009,
			clientRequiredExtensionMissing = 1010, // only the client should send this
			unnexpectedCondition = 1011,
			unverifiedCertificate = 1015, // not set by client
		}

		string toString() {
			return cast(string) (arsd.core.toStringInternal(code) ~ ": " ~ reason);
		}
	}

	/++
		The `CloseEvent` you get references a temporary buffer that may be overwritten after your handler returns. If you want to keep it or the `event.reason` member, remember to `.idup` it.

		History:
			The `CloseEvent` was changed to a [arsd.core.FlexibleDelegate] on March 19, 2023 (dub v11.0). Before that, `onclose` was a public member of type `void delegate()`. This change means setters still work with or without the [CloseEvent] argument.

			Your onclose method is now also called on abnormal terminations. Check the `wasClean` member of the `CloseEvent` to know if it came from a close frame or other cause.
	+/
	arsd.core.FlexibleDelegate!(void delegate(CloseEvent event)) onclose;
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

	// returns true if still active
	private static bool readyToRead(WebSocket sock) {
		sock.timeoutFromInactivity = MonoTime.currTime + sock.config.timeoutFromInactivity;
		if(!sock.lowLevelReceive()) {
			sock.readyState_ = CLOSED;

			if(sock.onerror)
				sock.onerror();

			if(sock.onclose)
				sock.onclose(CloseEvent(CloseEvent.StandardCloseCodes.abnormalClosure, "Connection lost", false, lastSocketError(sock.socket)));

			unregisterActiveSocket(sock);
			sock.socket.close();
			return false;
		}
		while(sock.processOnce().populated) {}
		return true;
	}

	// returns true if still active, false if not
	private static bool timeoutAndPingCheck(WebSocket sock, MonoTime now, Duration* minimumTimeoutForSelect) {
		auto diff = sock.timeoutFromInactivity - now;
		if(diff <= 0.msecs) {
			// it timed out
			if(sock.onerror)
				sock.onerror();

			if(sock.onclose)
				sock.onclose(CloseEvent(CloseEvent.StandardCloseCodes.abnormalClosure, "Connection timed out", false, null));

			sock.readyState_ = CLOSED;
			unregisterActiveSocket(sock);
			sock.socket.close();
			return false;
		}

		if(minimumTimeoutForSelect && diff < *minimumTimeoutForSelect)
			*minimumTimeoutForSelect = diff;

		diff = sock.nextPing - now;

		if(diff <= 0.msecs) {
			//sock.send(`{"action": "ping"}`);
			sock.ping();
			sock.nextPing = now + sock.config.pingFrequency.msecs;
		} else {
			if(minimumTimeoutForSelect && diff < *minimumTimeoutForSelect)
				*minimumTimeoutForSelect = diff;
		}

		return true;
	}

	/*
	const int bufferedAmount // amount pending
	const string extensions

	const string protocol
	const string url
	*/

	static {
		/++
			Runs an event loop with all known websockets on this thread until all websockets
			are closed or unregistered, or until you call [exitEventLoop], or set `*localLoopExited`
			to false (please note it may take a few seconds until it checks that flag again; it may
			not exit immediately).

			History:
				The `localLoopExited` parameter was added August 22, 2022 (dub v10.9)

			See_Also:
				[addToSimpledisplayEventLoop]
		+/
		void eventLoop(shared(bool)* localLoopExited = null) {
			import core.atomic;
			atomicOp!"+="(numberOfEventLoops, 1);
			scope(exit) {
				if(atomicOp!"-="(numberOfEventLoops, 1) <= 0)
					loopExited = false; // reset it so we can reenter
			}

			version(use_arsd_core) {
				loopExited = false;

				import arsd.core;
				getThisThreadEventLoop().run(() => WebSocket.activeSockets.length == 0 || loopExited || (localLoopExited !is null && *localLoopExited == true));
			} else {
				static SocketSet readSet;

				if(readSet is null)
					readSet = new SocketSet();

				loopExited = false;

				outermost: while(!loopExited && (localLoopExited is null || (*localLoopExited == false))) {
					readSet.reset();

					Duration timeout = 3.seconds;

					auto now = MonoTime.currTime;
					bool hadAny;
					foreach(sock; activeSockets) {
						if(!timeoutAndPingCheck(sock, now, &timeout))
							continue outermost;

						readSet.add(sock.socket);
						hadAny = true;
					}

					if(!hadAny) {
						// import std.stdio; writeln("had none");
						return;
					}

					tryAgain:
						// import std.stdio; writeln(timeout);
					auto selectGot = Socket.select(readSet, null, null, timeout);
					if(selectGot == 0) { /* timeout */
						// timeout
						continue; // it will be handled at the top of the loop
					} else if(selectGot == -1) { /* interrupted */
						goto tryAgain;
					} else {
						foreach(sock; activeSockets) {
							if(readSet.isSet(sock.socket)) {
								if(!readyToRead(sock))
									continue outermost;
								selectGot--;
								if(selectGot <= 0)
									break;
							}
						}
					}
				}
			}
		}

		private static shared(int) numberOfEventLoops;

		private __gshared bool loopExited;
		/++
			Exits all running [WebSocket.eventLoop]s next time they loop around. You can call this from a signal handler or another thread.

			Please note they may not loop around to check the flag for several seconds. Any new event loops will exit immediately until
			all current ones are closed. Once all event loops are exited, the flag is cleared and you can start the loop again.

			This function is likely to be deprecated in the future due to its quirks and imprecise name.
		+/
		void exitEventLoop() {
			loopExited = true;
		}

		WebSocket[] activeSockets;

		void registerActiveSocket(WebSocket s) {
			// ensure it isn't already there...
			assert(s !is null);
			if(s.registered)
				return;
			s.activeSocketArrayIndex = activeSockets.length;
			activeSockets ~= s;
			s.registered = true;
			version(use_arsd_core) {
				version(Posix)
				s.unregisterToken = arsd.core.getThisThreadEventLoop().addCallbackOnFdReadable(s.socket.handle, new arsd.core.CallbackHelper(() { s.readyToRead(s); }));
			}
		}
		void unregisterActiveSocket(WebSocket s) {
			version(use_arsd_core) {
				s.unregisterToken.unregister();
			}

			auto i = s.activeSocketArrayIndex;
			assert(activeSockets[i] is s);

			activeSockets[i] = activeSockets[$-1];
			activeSockets[i].activeSocketArrayIndex = i;
			activeSockets = activeSockets[0 .. $-1];
			activeSockets.assumeSafeAppend();
			s.registered = false;
		}
	}

	private bool registered;
	private size_t activeSocketArrayIndex;
	version(use_arsd_core) {
		static import arsd.core;
		arsd.core.ICoreEventLoop.UnregisterToken unregisterToken;
	}
}

private template imported(string mod) {
	mixin(`import imported = ` ~ mod ~ `;`);
}

/++
	Warning: you should call this AFTER websocket.connect or else it might throw on connect because the function sets nonblocking mode and the connect function doesn't handle that well (it throws on the "would block" condition in that function. easier to just do that first)
+/
template addToSimpledisplayEventLoop() {
	import arsd.simpledisplay;
	void addToSimpledisplayEventLoop(WebSocket ws, imported!"arsd.simpledisplay".SimpleWindow window) {
		version(use_arsd_core)
			return; // already done implicitly

		version(Windows)
		auto event = WSACreateEvent();
		// FIXME: supposed to close event too

		void midprocess() {
			version(Windows)
				ResetEvent(event);
			if(!ws.lowLevelReceive()) {
				ws.readyState_ = WebSocket.CLOSED;
				WebSocket.unregisterActiveSocket(ws);
				ws.socket.close();
				return;
			}
			while(ws.processOnce().populated) {}
		}

		version(Posix) {
			auto reader = new PosixFdReader(&midprocess, ws.socket.handle);
		} else version(none) {
			if(WSAAsyncSelect(ws.socket.handle, window.hwnd, WM_USER + 150, FD_CLOSE | FD_READ))
				throw new Exception("WSAAsyncSelect");

                        window.handleNativeEvent = delegate int(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
                                if(hwnd !is window.impl.hwnd)
                                        return 1; // we don't care...
                                switch(msg) {
                                        case WM_USER + 150: // socket activity
                                                switch(LOWORD(lParam)) {
                                                        case FD_READ:
                                                        case FD_CLOSE:
								midprocess();
                                                        break;
                                                        default:
                                                                // nothing
                                                }
                                        break;
                                        default: return 1; // not handled, pass it on
                                }
                                return 0;
                        };

		} else version(Windows) {
			ws.socket.blocking = false; // the WSAEventSelect does this anyway and doing it here lets phobos know about it.
			//CreateEvent(null, 0, 0, null);
			if(!event) {
				throw new Exception("WSACreateEvent");
			}
			if(WSAEventSelect(ws.socket.handle, event, 1/*FD_READ*/ | (1<<5)/*FD_CLOSE*/)) {
				//import std.stdio; writeln(WSAGetLastError());
				throw new Exception("WSAEventSelect");
			}

			auto handle = new WindowsHandleReader(&midprocess, event);

			/+
			static class Ready {}

			Ready thisr = new Ready;

			justCommunication.addEventListener((Ready r) {
				if(r is thisr)
					midprocess();
			});

			import core.thread;
			auto thread = new Thread({
				while(true) {
					WSAWaitForMultipleEvents(1, &event, true, -1/*WSA_INFINITE*/, false);
					justCommunication.postEvent(thisr);
				}
			});
			thread.isDaemon = true;
			thread.start;
			+/

		} else static assert(0, "unsupported OS");
	}
}

version(Windows) {
        import core.sys.windows.windows;
        import core.sys.windows.winsock2;
}

version(none) {
        extern(Windows) int WSAAsyncSelect(SOCKET, HWND, uint, int);
        enum int FD_CLOSE = 1 << 5;
        enum int FD_READ = 1 << 0;
        enum int WM_USER = 1024;
}

version(Windows) {
	import core.stdc.config;
	extern(Windows)
	int WSAEventSelect(SOCKET, HANDLE /* to an Event */, c_long);

	extern(Windows)
	HANDLE WSACreateEvent();

	extern(Windows)
	DWORD WSAWaitForMultipleEvents(DWORD, HANDLE*, BOOL, DWORD, BOOL);
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

		static WebSocketFrame simpleMessage(WebSocketOpcode opcode, in void[] data) {
			WebSocketFrame msg;
			msg.fin = true;
			msg.opcode = opcode;
			msg.data = cast(ubyte[]) data.dup; // it is mutated below when masked, so need to be cautious and copy it, sigh

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
				} else if(realLength > 125) {
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
				import std.random;
				foreach(ref item; maskingKey)
					item = uniform(ubyte.min, ubyte.max);
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
			if(data.length)
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
					msg.realLength |= ulong(d[0]) << ((7-i) * 8);
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

			return msg;
		}

		void unmaskInPlace() {
			if(this.masked) {
				int keyIdx = 0;
				foreach(i; 0 .. this.data.length) {
					this.data[i] = this.data[i] ^ this.maskingKey[keyIdx];
					if(keyIdx == 3)
						keyIdx = 0;
					else
						keyIdx++;
				}
			}
		}

		char[] textData() {
			return cast(char[]) data;
		}
	}
}

private extern(C)
int verifyCertificateFromRegistryArsdHttp(int preverify_ok, X509_STORE_CTX* ctx) {
	version(Windows) {
		if(preverify_ok)
			return 1;

		auto err_cert = OpenSSL.X509_STORE_CTX_get_current_cert(ctx);
		auto err = OpenSSL.X509_STORE_CTX_get_error(ctx);

		if(err == 62)
			return 0; // hostname mismatch is an error we can trust; that means OpenSSL already found the certificate and rejected it

		auto len = OpenSSL.i2d_X509(err_cert, null);
		if(len == -1)
			return 0;
		ubyte[] buffer = new ubyte[](len);
		auto ptr = buffer.ptr;
		len = OpenSSL.i2d_X509(err_cert, &ptr);
		if(len != buffer.length)
			return 0;


		CERT_CHAIN_PARA thing;
		thing.cbSize = thing.sizeof;
		auto context = CertCreateCertificateContext(X509_ASN_ENCODING, buffer.ptr, cast(int) buffer.length);
		if(context is null)
			return 0;
		scope(exit) CertFreeCertificateContext(context);

		PCCERT_CHAIN_CONTEXT chain;
		if(CertGetCertificateChain(null, context, null, null, &thing, 0, null, &chain)) {
			scope(exit)
				CertFreeCertificateChain(chain);

			DWORD errorStatus = chain.TrustStatus.dwErrorStatus;

			if(errorStatus == 0)
				return 1; // Windows approved it, OK carry on
			// otherwise, sustain OpenSSL's original ruling
		}

		return 0;
	} else {
		return preverify_ok;
	}
}


version(Windows) {
	pragma(lib, "crypt32");
	import core.sys.windows.wincrypt;
	extern(Windows) {
		PCCERT_CONTEXT CertEnumCertificatesInStore(HCERTSTORE hCertStore, PCCERT_CONTEXT pPrevCertContext);
		// BOOL CertGetCertificateChain(HCERTCHAINENGINE hChainEngine, PCCERT_CONTEXT pCertContext, LPFILETIME pTime, HCERTSTORE hAdditionalStore, PCERT_CHAIN_PARA pChainPara, DWORD dwFlags, LPVOID pvReserved, PCCERT_CHAIN_CONTEXT *ppChainContext);
		PCCERT_CONTEXT CertCreateCertificateContext(DWORD dwCertEncodingType, const BYTE *pbCertEncoded, DWORD cbCertEncoded);
	}

	void loadCertificatesFromRegistry(SSL_CTX* ctx) {
		auto store = CertOpenSystemStore(0, "ROOT");
		if(store is null) {
			// import std.stdio; writeln("failed");
			return;
		}
		scope(exit)
			CertCloseStore(store, 0);

		X509_STORE* ssl_store = OpenSSL.SSL_CTX_get_cert_store(ctx);
		PCCERT_CONTEXT c;
		while((c = CertEnumCertificatesInStore(store, c)) !is null) {
			FILETIME na = c.pCertInfo.NotAfter;
			SYSTEMTIME st;
			FileTimeToSystemTime(&na, &st);

			/+
			_CRYPTOAPI_BLOB i = cast() c.pCertInfo.Issuer;

			char[256] buffer;
			auto p = CertNameToStrA(X509_ASN_ENCODING, &i, CERT_SIMPLE_NAME_STR, buffer.ptr, cast(int) buffer.length);
			import std.stdio; writeln(buffer[0 .. p]);
			+/

			if(st.wYear <= 2021) {
				// see: https://www.openssl.org/blog/blog/2021/09/13/LetsEncryptRootCertExpire/
				continue; // no point keeping an expired root cert and it can break Let's Encrypt anyway
			}

			const(ubyte)* thing = c.pbCertEncoded;
			auto x509 = OpenSSL.d2i_X509(null, &thing, c.cbCertEncoded);
			if (x509) {
				auto success = OpenSSL.X509_STORE_add_cert(ssl_store, x509);
				//if(!success)
					//writeln("FAILED HERE");
				OpenSSL.X509_free(x509);
			} else {
				//writeln("FAILED");
			}
		}

		CertFreeCertificateContext(c);

		// import core.stdc.stdio; printf("%s\n", OpenSSL.OpenSSL_version(0));
	}


	// because i use the FILE* in PEM_read_X509 and friends
	// gotta use this to bridge the MS C runtime functions
	// might be able to just change those to only use the BIO versions
	// instead

	// only on MS C runtime
	version(CRuntime_Microsoft) {} else version=no_openssl_applink;

	version(no_openssl_applink) {} else {
		private extern(C) {
			void _open();
			void _read();
			void _write();
			void _lseek();
			void _close();
			int _fileno(FILE*);
			int _setmode(int, int);
		}
	export extern(C) void** OPENSSL_Applink() {
		import core.stdc.stdio;

		static extern(C) void* app_stdin() { return cast(void*) stdin; }
		static extern(C) void* app_stdout() { return cast(void*) stdout; }
		static extern(C) void* app_stderr() { return cast(void*) stderr; }
		static extern(C) int app_feof(FILE* fp) { return feof(fp); }
		static extern(C) int app_ferror(FILE* fp) { return ferror(fp); }
		static extern(C) void app_clearerr(FILE* fp) { return clearerr(fp); }
		static extern(C) int app_fileno(FILE* fp) { return _fileno(fp); }
		static extern(C) int app_fsetmod(FILE* fp, char mod) {
			return _setmode(_fileno(fp), mod == 'b' ? _O_BINARY : _O_TEXT);
		}

		static immutable void*[] table = [
			cast(void*) 22, // applink max

			&app_stdin,
			&app_stdout,
			&app_stderr,
			&fprintf,
			&fgets,
			&fread,
			&fwrite,
			&app_fsetmod,
			&app_feof,
			&fclose,

			&fopen,
			&fseek,
			&ftell,
			&fflush,
			&app_ferror,
			&app_clearerr,
			&app_fileno,

			&_open,
			&_read,
			&_write,
			&_lseek,
			&_close,
		];
		static assert(table.length == 23);

		return cast(void**) table.ptr;
	}
	}
}

unittest {
	auto client = new HttpClient();
	auto response = client.navigateTo(Uri("data:,Hello%2C%20World%21")).waitForCompletion();
	assert(response.contentTypeMimeType == "text/plain", response.contentType);
	assert(response.contentText == "Hello, World!", response.contentText);

	response = client.navigateTo(Uri("data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==")).waitForCompletion();
	assert(response.contentTypeMimeType == "text/plain", response.contentType);
	assert(response.contentText == "Hello, World!", response.contentText);

	response = client.navigateTo(Uri("data:text/html,%3Ch1%3EHello%2C%20World%21%3C%2Fh1%3E")).waitForCompletion();
	assert(response.contentTypeMimeType == "text/html", response.contentType);
	assert(response.contentText == "<h1>Hello, World!</h1>", response.contentText);
}

version(arsd_http2_unittests)
unittest {
	import core.thread;

	static void server() {
		import std.socket;
		auto socket = new TcpSocket();
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.bind(new InternetAddress(12346));
		socket.listen(1);
		auto s = socket.accept();
		socket.close();

		ubyte[1024] thing;
		auto g = s.receive(thing[]);

		/+
		string response = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 9\r\n\r\nHello!!??";
		auto packetSize = 2;
		+/

		auto packetSize = 1;
		string response = "HTTP/1.1 200 OK\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n6\r\nHello!\r\n0\r\n\r\n";

		while(response.length) {
			s.send(response[0 .. packetSize]);
			response = response[packetSize .. $];
			//import std.stdio; writeln(response);
		}

		s.close();
	}

	auto thread = new Thread(&server);
	thread.start;

	Thread.sleep(200.msecs);

	auto response = get("http://localhost:12346/").waitForCompletion;
	assert(response.code == 200);
	//import std.stdio; writeln(response);

	foreach(site; ["https://dlang.org/", "http://arsdnet.net", "https://phobos.dpldocs.info"]) {
		response = get(site).waitForCompletion;
		assert(response.code == 200);
	}

	thread.join;
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
