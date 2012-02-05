// This thing sucks. It's primarily to prove that cgi.d *can* work
// with an embedded http server without much difficulty, so you aren't
// tied to CGI if you don't want to be, even if you have a huge codebase
// built on cgi.d already.

// But this particular module is no where near ready for serious use.
// (it does do reasonably well under controlled conditions though)

module arsd.httpd;

public import arsd.cgi;

import arsd.netman;

import std.range;

/*

import arsd.curl;
void handler(Cgi cgi) {
	cgi.write("hello world!");
	cgi.close();
}

void main() {
	serveHttp(&handler, 5000);
}

*/

void serveHttp(CustomCgi)(void function(Cgi) requestHandler, ushort port) if(is(CustomCgi: Cgi)) {
	auto netman = new NetMan!(CustomCgi)(requestHandler);
	netman.listen(port);
	for(;;)
		try
			netman.proceed();
		catch(ConnectionException e)
			e.c.disconnectNow();
		catch(Exception e)
			writefln("Exception: %s", e.toString());
}

class NetMan(CustomCgi) : NetworkManager /*if(is(CustomCgi : Cgi))*/ {
	void function(Cgi) requestHandler;

	this(void function(Cgi) requestHandler) {
		this.requestHandler = requestHandler;
	}

	override Connection allocConnection(int port) {
		return new HttpdConnection!CustomCgi(requestHandler);
	}
}

class HttpdConnection(CustomCgi) : Connection /* if(is(CustomCgi : Cgi)) */ {
	// The way this rolls is to get the whole thing in memory, then pass it off to Cgi to do the rest

	this(void function(Cgi) requestHandler) {
		handler = requestHandler;
	}

	void function(Cgi) handler;

	int state;
	string[] headers;
	immutable(ubyte)[] data;
	int contentLength;
	bool chunked;
	int chunkSize = 0;
	string separator = "\r\n";
	bool closeConnection;

	void log(in ubyte[] a) {
		data ~= a;
	}

	void finishRequest() {
		state = 0;
		separator = "\r\n";

		// writeln("FINISHED");

		scope(exit) {
			if(closeConnection)
				disconnect();
			closeConnection = false;
		}

		Cgi cgi;

		try {
		cgi = new CustomCgi(headers, data, peerAddress(),
			cast(void delegate(const(ubyte)[])) &this.write);
		} catch(Throwable t) {
			write("HTTP/1.1 400 Bad Request\r\n");
			write("Content-Type: text/plain\r\n");
			write("Connection: close\r\n");
			write("\r\n");
			write(t.toString());

			return;
		}

		try {
			handler(cgi);
			cgi.close();
			cgi.dispose();
		} catch(Throwable e) {
			cgi.setResponseStatus("500 Internal Server Error");
			cgi.write(e.toString());
			cgi.close();
			cgi.dispose();

			return;
		}
	}

	override void onDataReceived(){
		auto a = read();

		// writeln("data received ", state, "\n", cast(string) a);

	more:
		switch(state) {
			default: assert(0);
			case 0: // reading the headers
				// while it's supposed to be \r\n, we want
				// to be permissive here to avoid hanging if
				// the wrong thing comes.
				try_again:
				int l = locationOf(a, separator ~ separator);
				if(l == -1) {
					if(separator.length > 1) {
						separator = "\n";
						goto try_again;
					} else {
						separator = "\r\n";
					}

					return; // not enough data
				}
				changeReadPosition(l+separator.length * 2); // we're now at the beginning of the data

				data.length = 0;
				contentLength = 0;

				string hdrs = cast(string) a[0..l].idup;
				a = read(); // advance ourselves
				headers = hdrs.split(separator);

				chunked = false;

				if(headers.length == 0) {
					disconnect();
					return;
				}

				if(headers[0].indexOf("HTTP/1.0") != -1)
					closeConnection = true; // always one request per connection with 1.0

				foreach(ref h; headers[1..$]) {
					int colon = h.indexOf(":");
					if(colon == -1)
						throw new Exception("Http headers need colons");
					string name = h[0..colon].tolower;
					string value = h[colon+2..$]; // FIXME?

					switch(name) {
					    case "transfer-encoding":
					    	if(value == "chunked")
							chunked = true;
					    break;
					    case "content-length":
						contentLength = to!int(value);
					    break;
					    case "connection":
						if(value == "close")
							closeConnection = true;
					    break;
					    default:
					    	// leave it unmolested for passthrough
					}
				}

				// forward the header and advance our state
				state = 1;
		//	break; // fall through to read some more data if we have any
			case 1: // reading Content-Length type data
				// We need to read up the data we have, and write it out as a chunk.
				if(!chunked) {
					if(a.length <= contentLength) {
						log(a);
						contentLength -= a.length;
						resetRead();
						// we just finished it off, terminate the chunks
						if(contentLength == 0) {
							finishRequest();
						}
					} else {
						// we actually have *more* here than we need....
						log(a[0..contentLength]);
						contentLength = 0;
						finishRequest();

						changeReadPosition(contentLength);
						a = read();
						// we're done
						goto more; // see if we can make use of the rest of the data
					}
				} else {
					// decode it, modify it, then reencode it
					// If here, we are at the beginning of a chunk.
					int loc = locationOf(a, "\r\n");
					if(loc == -1) {
						return; // don't have the length
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
						return; // need more data
					}
					changeReadPosition(loc+2); // skips the chunk header
					a = read();

					if(chunkSize == 0) { // we're done with the response
						state = 3;
						goto more;
					} else {
						state = 2;
						goto more;
					}

					resetRead();
				}
			break;
			case 2: // reading a chunk
				// if we got here, will change must be true....
				if(a.length < chunkSize + 2) {
					return; // we want to handle the whole chunk at once
				}

				log(a[0..chunkSize]);

				state = 1;

				if(a.length > chunkSize + 2) {
					assert(a[chunkSize] == 13);
					assert(a[chunkSize+1] == 10);
					changeReadPosition(chunkSize + 2); // skip the \r\n
					a = read();
					chunkSize = 0;
					state = 1;
					goto more;
				} else {
					chunkSize = 0;
					resetRead();
				}
			break;
			case 3: // reading footers
				// if we got here, will change must be true....
				int loc = locationOf(a, "\r\n");
				if(loc == -1) {
					return; // not done yet
				} else {
					assert(loc == 0);
					changeReadPosition(loc+2); // FIXME: should handle footers properly
					finishRequest();
					a = read();

					goto more;
				}
			break;
		}
	}
}
