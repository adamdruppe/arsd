/**
	This is CLIENT only at this point. Don't try to
	bind/accept with these.

	FIXME: Windows isn't implemented

	On Windows, it uses Microsoft schannel so it doesn't
	need openssl or gnutls as a dependency.

	On other platforms, it uses the openssl api, which should
	work with both openssl and gnutls.


	btw, interesting:
	http://msdn.microsoft.com/en-us/library/windows/desktop/aa364510%28v=vs.85%29.aspx
*/


public import std.socket;

// see also:
// http://msdn.microsoft.com/en-us/library/aa380536%28v=vs.85%29.aspx

// import deimos.openssl.ssl;

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
		void SSL_free(SSL*);
		void SSL_CTX_free(SSL_CTX*);

		void SSL_set_verify(SSL*, int, void*);
		enum SSL_VERIFY_NONE = 0;

		SSL_METHOD* SSLv3_client_method();
		SSL_METHOD* TLS_client_method();
		SSL_METHOD* SSLv23_client_method();

		void ERR_print_errors_fp(FILE*);
	}

	import core.stdc.stdio;

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
		private void initSsl(bool verifyPeer) {
			ctx = SSL_CTX_new(SSLv23_client_method());
			assert(ctx !is null);

			ssl = SSL_new(ctx);
			if(!verifyPeer)
				SSL_set_verify(ssl, SSL_VERIFY_NONE, null);
			SSL_set_fd(ssl, this.handle);
		}

		@trusted
		override void connect(Address to) {
			super.connect(to);
			if(SSL_connect(ssl) == -1) {
				ERR_print_errors_fp(stderr);
				int i;
				printf("wtf\n");
				scanf("%d\n", i);
				throw new Exception("ssl connect");
			}
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

		this(AddressFamily af, SocketType type = SocketType.STREAM, bool verifyPeer = true) {
			super(af, type);
			initSsl(verifyPeer);
		}

		this(socket_t sock, AddressFamily af) {
			super(sock, af);
			initSsl(true);
		}

		~this() {
			SSL_free(ssl);
			SSL_CTX_free(ctx);
		}
	}
}

version(ssl_test)
void main() {
	auto sock = new SslClientSocket(AddressFamily.INET);
	sock.connect(new InternetAddress("localhost", 443));
	sock.send("GET / HTTP/1.0\r\n\r\n");
	import std.stdio;
	char[1024] buffer;
	writeln(buffer[0 .. sock.receive(buffer)]);
}
