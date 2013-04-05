module arsd.http;

version(with_openssl) {
	pragma(lib, "crypto");
	pragma(lib, "ssl");
}


/**
	Gets a textual document, ignoring headers. Throws on non-text or error.
*/
string get(string url) {
	auto hr = httpRequest("GET", url);
	if(hr.code != 200)
		throw new Exception(format("HTTP answered %d instead of 200 on %s", hr.code, url));
	if(hr.contentType.indexOf("text/") == -1)
		throw new Exception(hr.contentType ~ " is bad content for conversion to string");
	return cast(string) hr.content;

}

static import std.uri;

string post(string url, string[string] args) {
	string content;

	foreach(name, arg; args) {
		if(content.length)
			content ~= "&";
		content ~= std.uri.encode(name) ~ "=" ~ std.uri.encode(arg);
	}

	auto hr = httpRequest("POST", url, cast(ubyte[]) content, ["Content-Type: application/x-www-form-urlencoded"]);
	if(hr.code != 200)
		throw new Exception(format("HTTP answered %d instead of 200", hr.code));
	if(hr.contentType.indexOf("text/") == -1)
		throw new Exception(hr.contentType ~ " is bad content for conversion to string");

	return cast(string) hr.content;
}

struct HttpResponse {
	int code;
	string contentType;
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

HttpResponse httpRequest(string method, string uri, const(ubyte)[] content = null, string headers[] = null) {
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


	HttpResponse response = doHttpRequestOnHelpers(write, read, method, uri, content, headers, u.useHttps);

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
HttpResponse doHttpRequestOnHelpers(void delegate(string) write, char[] delegate() read, string method, string uri, const(ubyte)[] content = null, string headers[] = null, bool https = false) 
	in {
		assert(method == "POST" || method == "GET");
	}
body {
	auto u = UriParts(uri);





	write(format("%s %s HTTP/1.1\r\n", method, u.path));
	write(format("Host: %s\r\n", u.host));
	write(format("Connection: close\r\n"));
	if(content !is null)
		write(format("Content-Length: %d\r\n", content.length));
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
					if((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z')) {
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
								val = cc - 'A';

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
					a+= 2; // skipping a 13 10
					start = a;
					state = 0;
				break;
				case 3: // reading footers
					goto done; // FIXME
				break;
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
