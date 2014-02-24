public import std.socket;

// see also:
// http://msdn.microsoft.com/en-us/library/aa380536%28v=vs.85%29.aspx

import deimos.openssl.ssl;

static this() {
	SSL_library_init();
	OpenSSL_add_all_algorithms();
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

	override void connect(Address to) {
		super.connect(to);
		if(SSL_connect(ssl) == -1)
			throw new Exception("ssl connect");
	}

	override ptrdiff_t send(const(void)[] buf, SocketFlags flags) {
		return SSL_write(ssl, buf.ptr, cast(uint) buf.length);
	}
	override ptrdiff_t send(const(void)[] buf) {
		return send(buf, SocketFlags.NONE);
	}
	override ptrdiff_t receive(void[] buf, SocketFlags flags) {
		return SSL_read(ssl, buf.ptr, buf.length);
	}
	override ptrdiff_t receive(void[] buf) {
		return receive(buf, SocketFlags.NONE);
	}

	this(AddressFamily af) {
		super(af, SocketType.STREAM);
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

version(ssl_test)
void main() {
	auto sock = new OpenSslSocket(AddressFamily.INET);
	sock.connect(new InternetAddress("localhost", 443));
	sock.send("GET / HTTP/1.0\r\n\r\n");
	import std.stdio;
	char[1024] buffer;
	writeln(buffer[0 .. sock.receive(buffer)]);
}
