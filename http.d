module arsd.http;

import std.stdio;


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

	this(string uri) {
		original = uri;
		if(uri[0..7] != "http://")
			throw new Exception("You must use an absolute, unencrypted URL.");

		int posSlash = uri[7..$].indexOf("/");
		if(posSlash != -1)
			posSlash += 7;

		if(posSlash == -1)
			posSlash = uri.length;

		int posColon = uri[7..$].indexOf(":");
		if(posColon != -1)
			posColon += 7;

		port = 80;

		if(posColon != -1 && posColon < posSlash) {
			host = uri[7..posColon];
			port = to!ushort(uri[posColon+1..posSlash]);
		} else
			host = uri[7..posSlash];

		path = uri[posSlash..$];
		if(path == "")
			path = "/";
	}
}

HttpResponse httpRequest(string method, string uri, const(ubyte)[] content = null, string headers[] = null) {
	auto u = UriParts(uri);
	auto f = openNetwork(u.host, u.port);

	return doHttpRequestOnFile(f, method, uri, content, headers);
}

/**
	Executes a generic http request, returning the full result. The correct formatting
	of the parameters are the caller's responsibility. Content-Length is added automatically,
	but YOU must give Content-Type!
*/
HttpResponse doHttpRequestOnFile(File f, string method, string uri, const(ubyte)[] content = null, string headers[] = null) 
	in {
		assert(method == "POST" || method == "GET");
	}
body {
	auto u = UriParts(uri);

	f.writefln("%s %s HTTP/1.1", method, u.path);
	f.writefln("Host: %s", u.host);
	f.writefln("Connection: close");
	if(content !is null)
		f.writefln("Content-Length: %d", content.length);
	if(headers !is null)
		foreach(header; headers)
			f.writefln("%s", header);
	f.writefln("");
	if(content !is null)
		f.rawWrite(content);


	HttpResponse hr;
 cont:
	string l = f.readln();
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

	foreach(line; f.byLine) {
		if(line.length <= 1)
			break;
		hr.headers ~= line.idup;
		if(line.startsWith("Content-Type: "))
			hr.contentType = line[14..$-1].idup;
		if(line.startsWith("Transfer-Encoding: chunked"))
			chunked = true;
	}

	ubyte[] response;
	foreach(ubyte[] chunk; f.byChunk(4096)) {
		response ~= chunk;
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
			switch(state) {
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
