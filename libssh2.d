/++
	Minimal bindings for libssh2. (just what I needed for my terminal emulator, but I'd accept more, and even wrappers if you wanted to.)

	Just link with it on Linux, but it'll need a couple dlls and a lib on windows.
+/
module arsd.libssh2;

version(libssh_example)
void main() {
	import std.socket;

	if(libssh2_init(0))
		throw new Exception("libssh2_init");
	scope(exit)
		libssh2_exit();

	auto socket = new Socket(AddressFamily.INET, SocketType.STREAM);
	socket.connect(new InternetAddress("localhost", 22));
	scope(exit) socket.close();

	auto session = libssh2_session_init_ex(null, null, null, null);
	if(session is null) throw new Exception("init session");
	scope(exit)
		libssh2_session_disconnect_ex(session, 0, "normal", "EN");

	if(libssh2_session_handshake(session, socket.handle))
		throw new Exception("handshake");

	auto fingerprint = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_SHA1);

	/*
	import core.stdc.stdio;
	for(int i = 0; i < 20; i++)
		printf("%02X ", fingerprint[i]);
	*/

	/*
	auto got = libssh2_userauth_list(session, "me", 2);
	if(got is null) throw new Exception("list");
	import core.stdc.stdio;
	printf("%s\n", got);
	*/

	if(auto err = libssh2_userauth_publickey_fromfile_ex(session, "me".ptr, "me".length, "/home/me/.ssh/id_rsa.pub", "/home/me/.ssh/id_rsa", null))
		throw new Exception("auth");


	auto channel = libssh2_channel_open_ex(session, "session".ptr, "session".length, LIBSSH2_CHANNEL_WINDOW_DEFAULT, LIBSSH2_CHANNEL_PACKET_DEFAULT, null, 0);

	if(channel is null)
		throw new Exception("channel open");

	scope(exit)
		libssh2_channel_free(channel);

	libssh2_channel_setenv_ex(channel, "ELVISBG".dup.ptr, "ELVISBG".length, "dark".ptr, "dark".length);

	if(libssh2_channel_request_pty_ex(channel, "xterm", "xterm".length, null, 0, 80, 24, 0, 0))
		throw new Exception("pty");

	if(libssh2_channel_process_startup(channel, "shell".ptr, "shell".length, null, 0))
		throw new Exception("process_startup");

	libssh2_keepalive_config(session, 0, 60);
	libssh2_session_set_blocking(session, 0);


	char[1024] buffer;
	again:
	auto got = libssh2_channel_read_ex(channel, 0, buffer.ptr, buffer.length);
	if(got == LIBSSH2_ERROR_EAGAIN) {
		import core.thread;
		Thread.sleep(msecs(500));
		goto again;
	}

	import std.stdio;
	writeln(buffer[0 .. got]);
}




alias socket_t = int;

version(Windows) {
	pragma(lib, "libssh2");
} else {
	pragma(lib, "ssh2");
}

version(X86)
	alias ssize_t = int;
else version(X86_64)
	alias ssize_t = long;

extern(C) {
	struct LIBSSH2_SESSION {}
	LIBSSH2_SESSION* libssh2_session_init_ex(void* myalloc, void* myfree, void* myrealloc, void* abstract_);

	int libssh2_session_handshake(LIBSSH2_SESSION* session, socket_t socket);

	enum int LIBSSH2_HOSTKEY_HASH_MD5 = 1;
	enum int LIBSSH2_HOSTKEY_HASH_SHA1 = 2;
	const(char)* libssh2_hostkey_hash(LIBSSH2_SESSION*, int hash_type);

	int libssh2_userauth_publickey_fromfile_ex(
		LIBSSH2_SESSION* session,
		const char *username,
		uint ousername_len,
		const char *publickey,
		const char *privatekey,
		const char *passphrase);

	struct LIBSSH2_CHANNEL {}
	LIBSSH2_CHANNEL* libssh2_channel_open_ex(
		LIBSSH2_SESSION *session,
		const char *channel_type,
		uint channel_type_len,
		uint window_size,
		uint packet_size,
		const char *message,
		uint message_len); 
	// channel_open_session calls the above

	int libssh2_channel_setenv_ex(
		LIBSSH2_CHANNEL* channel,
		char* varname,
		uint varname_len,
		const char *value,
		uint value_len);

	enum LIBSSH2_CHANNEL_WINDOW_DEFAULT = (256*1024);
	enum LIBSSH2_CHANNEL_PACKET_DEFAULT = 32768;

	int libssh2_channel_request_pty_ex(LIBSSH2_CHANNEL *channel, const char *term, uint term_len, const char *modes, uint modes_len, int width, int height, int width_px, int height_px); 

	int libssh2_channel_process_startup(
		LIBSSH2_CHANNEL* channel,
		const char *request,
		uint request_len,
		const char *message,
		uint message_len);
 

	int libssh2_channel_free(LIBSSH2_CHANNEL *channel); 
	int libssh2_session_disconnect_ex(LIBSSH2_SESSION *session, int reason, const char *description, const char *lang); 
	int libssh2_session_free(LIBSSH2_SESSION *session); 

	int libssh2_init(int flags);
	void libssh2_exit();

	// stream_id 0 == normal, 1 == error.
	ssize_t libssh2_channel_read_ex(LIBSSH2_CHANNEL *channel, int stream_id, void *buf, size_t buflen);

	ssize_t libssh2_channel_write_ex(LIBSSH2_CHANNEL *channel,
                                  int stream_id, const(void)* buf,
                                  size_t buflen);

	void libssh2_session_set_blocking(LIBSSH2_SESSION* session, int blocking);

	void libssh2_keepalive_config(LIBSSH2_SESSION *session,
		int want_reply,
		uint interval);

	int libssh2_keepalive_send(LIBSSH2_SESSION *session,
		int *seconds_to_next);

	LIBSSH2_CHANNEL * libssh2_channel_direct_tcpip_ex(LIBSSH2_SESSION *session, const char *host, int port, const char *shost, int sport); 

	int libssh2_channel_request_pty_size_ex(LIBSSH2_CHANNEL *channel,
		int width, int height,
		int width_px,
		int height_px);

	char *
 libssh2_userauth_list(LIBSSH2_SESSION *session, const char *username,
                       uint username_len);

	int libssh2_channel_eof(LIBSSH2_CHANNEL*);
	int libssh2_channel_close(LIBSSH2_CHANNEL*);
	int libssh2_channel_wait_closed(LIBSSH2_CHANNEL *channel);

	enum LIBSSH2_ERROR_EAGAIN = -37;

	int libssh2_session_flag(LIBSSH2_SESSION*, int, int);
	enum LIBSSH2_FLAG_SIGPIPE = 1;
	enum LIBSSH2_FLAG_COMPRESS = 2;

}
