/++
	Future public interface to the Uri struct and encode/decode component functions.

	History:
		Added May 26, 2025
+/
module arsd.uri;

import arsd.core;

import arsd.conv;
import arsd.string;

alias encodeUriComponent = arsd.core.encodeUriComponent;
alias decodeUriComponent = arsd.core.decodeUriComponent;

// phobos compatibility names
alias encodeComponent = encodeUriComponent;
alias decodeComponent = decodeUriComponent;

// FIXME: merge and pull Uri struct from http2 and cgi. maybe via core.

// might also put base64 in here....



/++
	Represents a URI. It offers named access to the components and relative uri resolution, though as a user of the library, you'd mostly just construct it like `Uri("http://example.com/index.html")`.

	History:
		Moved from duplication in [arsd.cgi] and [arsd.http2] to arsd.uri on November 2, 2025.
+/
struct Uri {
	UriString toUriString() {
		return UriString(toString());
	}

	alias toUriString this; // blargh idk a url really is a string, but should it be implicit?

	// scheme://userinfo@host:port/path?query#fragment

	string scheme; /// e.g. "http" in "http://example.com/"
	string userinfo; /// the username (and possibly a password) in the uri
	string host; /// the domain name. note it may be an ip address or have percent encoding too.
	int port; /// port number, if given. Will be zero if a port was not explicitly given
	string path; /// e.g. "/folder/file.html" in "http://example.com/folder/file.html"
	string query; /// the stuff after the ? in a uri
	string fragment; /// the stuff after the # in a uri.

	// cgi.d specific.......
	// idk if i want to keep these, since the functions they wrap are used many, many, many times in existing code, so this is either an unnecessary alias or a gratuitous break of compatibility
	// the decode ones need to keep different names anyway because we can't overload on return values...
	static string encode(string s) { return encodeUriComponent(s); }
	static string encode(string[string] s) { return encodeVariables(s); }
	static string encode(string[][string] s) { return encodeVariables(s); }

	/++
		Parses an existing uri string (which should be pre-validated) into this further detailed structure.

		History:
			Added November 2, 2025.
	+/
	this(UriString uriString) {
		this(uriString.toString());
	}

	/++
		Transforms an interpolated expression sequence into a uri, encoding as appropriate as it reads.

		History:
			Added November 2, 2025.
	+/
	this(Args...)(InterpolationHeader header, Args args, InterpolationFooter footer) {
		// will need to use iraw here for some cases. paths may partially encoded but still allow slashes, prolly needs a type.
		// so like $(path(x)) or $(queryString(x)) or maybe isemi or something. or make user split it into a string[] then recombine here....
		string thing;
		foreach(arg; args) {
			static if(is(typeof(arg) == InterpolationHeader))
				{}
			else
			static if(is(typeof(arg) == InterpolationFooter))
				{}
			else
			static if(is(typeof(arg) == InterpolatedLiteral!part, string part))
				thing ~= part;
			else
			static if(is(typeof(arg) == InterpolatedExpression!code, string code))
				{}
			else
			static if(is(typeof(arg) == iraw))
				thing ~= iraw.s;
			else
				thing ~= encodeUriComponent(to!string(arg));

		}

		this(thing);
	}

	unittest {
		string bar = "12/";
		string baz = "&omg";
		auto uri = Uri(i"http://example.com/foo/$bar?thing=$baz");

		assert(uri.toString() == "http://example.com/foo/12%2F?thing=%26omg");
	}

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

	package string unixSocketPath = null;
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

	// these are like javascript's location.search and location.hash
	string search() const {
		return query.length ? ("?" ~ query) : "";
	}
	string hash() const {
		return fragment.length ? ("#" ~ fragment) : "";
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
				idx2 = authority.indexOf("]");
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
		if(n.scheme.length == 0) {
			n.scheme = baseUrl.scheme;
			if(n.host.length == 0) {
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

		uri = Uri("http://127.0.0.1/");
		assert(uri.host == "127.0.0.1");
		assert(uri.port == 0);

		uri = Uri("http://127.0.0.1:123/");
		assert(uri.host == "127.0.0.1");
		assert(uri.port == 123);

		uri = Uri("http://[ff:ff::0]/");
		assert(uri.host == "[ff:ff::0]");

		uri = Uri("http://[ff:ff::0]:123/");
		assert(uri.host == "[ff:ff::0]");
		assert(uri.port == 123);
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

		url = Uri("/test/bar");
		assert(Uri("./").basedOn(url) == "/test/", Uri("./").basedOn(url));
		assert(Uri("../").basedOn(url) == "/");

		url = Uri("http://example.com/");
		assert(Uri("../foo").basedOn(url) == "http://example.com/foo");

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
}

/// Makes a data:// uri that can be used as links in most newer browsers (IE8+).
string makeDataUrl()(string mimeType, in void[] data) {
	import std.base64; // FIXME then i can remove the () template
	auto data64 = Base64.encode(cast(const(ubyte[])) data);
	return "data:" ~ mimeType ~ ";base64," ~ cast(string)(data64);
}

/// breaks down a url encoded string
string[][string] decodeVariables(string data, string separator = "&", string[]* namesInOrder = null, string[]* valuesInOrder = null) {
	auto vars = data.split(separator);
	string[][string] _get;
	foreach(var; vars) {
		auto equal = var.indexOf("=");
		string name;
		string value;
		if(equal == -1) {
			name = decodeUriComponent(var);
			value = "";
		} else {
			//_get[decodeUriComponent(var[0..equal])] ~= decodeUriComponent(var[equal + 1 .. $].replace("+", " "));
			// stupid + -> space conversion.
			name = decodeUriComponent(var[0..equal].replace("+", " "));
			value = decodeUriComponent(var[equal + 1 .. $].replace("+", " "));
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

		ret ~= encodeUriComponent(k) ~ "=" ~ encodeUriComponent(v);
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
			ret ~= encodeUriComponent(k) ~ "=" ~ encodeUriComponent(v);
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


char[2] toHexUpper(ubyte num) {
	char[2] ret = 0;
	ret[0] = num / 16;
	ret[1] = num % 16;
	ret[0] += cast(char)(ret[0] >= 10 ? 'A' : '0');
	ret[1] += cast(char)(ret[1] >= 10 ? 'A' : '0');
	return ret;
}


