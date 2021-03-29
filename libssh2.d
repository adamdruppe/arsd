/++
	Minimal bindings for libssh2. (just what I needed for my terminal emulator, but I'd accept more, and even wrappers if you wanted to.)

	Just link with it on Linux, but it'll need a couple dlls and a lib on windows.
+/
module arsd.libssh2;

// some day: https://libssh2.org/examples/x11.html
// and https://stackoverflow.com/questions/1580750/example-code-of-libssh2-being-used-for-port-forwarding#_=_

version(libssh_sftp_example)
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

	if(auto err = libssh2_userauth_publickey_fromfile_ex(session, "me".ptr, "me".length, "/home/me/.ssh/id_rsa.pub", "/home/me/.ssh/id_rsa", null))
		throw new Exception("auth");


	auto channel = libssh2_channel_open_ex(session, "session".ptr, "session".length, LIBSSH2_CHANNEL_WINDOW_DEFAULT, LIBSSH2_CHANNEL_PACKET_DEFAULT, null, 0);

	if(channel is null)
		throw new Exception("channel open");

	scope(exit)
		libssh2_channel_free(channel);

	auto sftp_session = libssh2_sftp_init(session);
	if(sftp_session is null)
		throw new Exception("no sftp");
	scope(exit) libssh2_sftp_shutdown(sftp_session);

	libssh2_session_set_blocking(session, 1);

	auto filename = "/home/me/arsd/libssh2.d";
	auto handle = libssh2_sftp_open_ex(sftp_session, filename.ptr, cast(int) filename.length, LIBSSH2_FXF_READ, 0, LIBSSH2_SFTP_OPENFILE);
	if(handle is null) throw new Exception("no file");
	scope(exit) libssh2_sftp_close_handle(handle);

	char[1024] buffer;
	again:
	auto got = libssh2_sftp_read(handle, buffer.ptr, buffer.length);

	import std.stdio;
	writeln(buffer[0 .. got]);
	if(got > 0)
		goto again;
}


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

import core.stdc.config;

extern(C) {
	struct LIBSSH2_SESSION {}
	LIBSSH2_SESSION* libssh2_session_init_ex(void* myalloc, void* myfree, void* myrealloc, void* abstract_);

	int libssh2_session_handshake(LIBSSH2_SESSION* session, socket_t socket);

	enum int LIBSSH2_HOSTKEY_HASH_MD5 = 1;
	enum int LIBSSH2_HOSTKEY_HASH_SHA1 = 2;
	const(char)* libssh2_hostkey_hash(LIBSSH2_SESSION*, int hash_type);

	/* sftp */
	struct LIBSSH2_SFTP {}
	struct LIBSSH2_SFTP_HANDLE {}
	LIBSSH2_SFTP* libssh2_sftp_init(LIBSSH2_SESSION *session);
	int libssh2_sftp_shutdown(LIBSSH2_SFTP *sftp); 
	c_ulong libssh2_sftp_last_error(LIBSSH2_SFTP *sftp); 
	int libssh2_sftp_close_handle(LIBSSH2_SFTP_HANDLE *handle);
	int libssh2_sftp_shutdown(LIBSSH2_SFTP *sftp);

	enum LIBSSH2_SFTP_OPENFILE = 0;
	enum LIBSSH2_SFTP_OPENDIR = 1;

	/* Flags for rename_ex() */
	enum LIBSSH2_SFTP_RENAME_OVERWRITE = 0x00000001;
	enum LIBSSH2_SFTP_RENAME_ATOMIC = 0x00000002;
	enum LIBSSH2_SFTP_RENAME_NATIVE = 0x00000004;

	/* Flags for stat_ex() */
	enum LIBSSH2_SFTP_STAT = 0;
	enum LIBSSH2_SFTP_LSTAT = 1;
	enum LIBSSH2_SFTP_SETSTAT = 2;

	/* Flags for symlink_ex() */
	enum LIBSSH2_SFTP_SYMLINK = 0;
	enum LIBSSH2_SFTP_READLINK = 1;
	enum LIBSSH2_SFTP_REALPATH = 2;

	/* Flags for sftp_mkdir() */
	enum LIBSSH2_SFTP_DEFAULT_MODE = -1;

	/* SFTP attribute flag bits */
	enum LIBSSH2_SFTP_ATTR_SIZE = 0x00000001;
	enum LIBSSH2_SFTP_ATTR_UIDGID = 0x00000002;
	enum LIBSSH2_SFTP_ATTR_PERMISSIONS = 0x00000004;
	enum LIBSSH2_SFTP_ATTR_ACMODTIME = 0x00000008;
	enum LIBSSH2_SFTP_ATTR_EXTENDED = 0x80000000;

	/* SFTP statvfs flag bits */
	enum LIBSSH2_SFTP_ST_RDONLY = 0x00000001;
	enum LIBSSH2_SFTP_ST_NOSUID = 0x00000002;

	enum LIBSSH2_SFTP_TYPE_REGULAR = 1;
	enum LIBSSH2_SFTP_TYPE_DIRECTORY = 2;
	enum LIBSSH2_SFTP_TYPE_SYMLINK = 3;
	enum LIBSSH2_SFTP_TYPE_SPECIAL = 4;
	enum LIBSSH2_SFTP_TYPE_UNKNOWN = 5;
	enum LIBSSH2_SFTP_TYPE_SOCKET = 6;
	enum LIBSSH2_SFTP_TYPE_CHAR_DEVICE = 7;
	enum LIBSSH2_SFTP_TYPE_BLOCK_DEVICE = 8;
	enum LIBSSH2_SFTP_TYPE_FIFO = 9;


	/* File type */
	enum LIBSSH2_SFTP_S_IFMT = 0xF000;     /* type of file mask */
	enum LIBSSH2_SFTP_S_IFIFO = 0x1000;     /* named pipe (fifo) */
	enum LIBSSH2_SFTP_S_IFCHR = 0x2000;     /* character special */
	enum LIBSSH2_SFTP_S_IFDIR = 0x4000;     /* directory */
	enum LIBSSH2_SFTP_S_IFBLK = 0x6000;     /* block special */
	enum LIBSSH2_SFTP_S_IFREG = 0x8000;     /* regular */
	enum LIBSSH2_SFTP_S_IFLNK = 0xA000;     /* symbolic link */
	enum LIBSSH2_SFTP_S_IFSOCK = 0xC000;     /* socket */

	enum LIBSSH2_FXF_READ = 0x00000001;
	enum LIBSSH2_FXF_WRITE = 0x00000002;
	enum LIBSSH2_FXF_APPEND = 0x00000004;
	enum LIBSSH2_FXF_CREAT = 0x00000008;
	enum LIBSSH2_FXF_TRUNC = 0x00000010;
	enum LIBSSH2_FXF_EXCL = 0x00000020;

	enum LIBSSH2_FX {
		OK = 0,
		EOF = 1,
		NO_SUCH_FILE = 2,
		PERMISSION_DENIED = 3,
		FAILURE = 4,
		BAD_MESSAGE = 5,
		NO_CONNECTION = 6,
		CONNECTION_LOST = 7,
		OP_UNSUPPORTED = 8,
		INVALID_HANDLE = 9,
		NO_SUCH_PATH = 10,
		FILE_ALREADY_EXISTS = 11,
		WRITE_PROTECT = 12,
		NO_MEDIA = 13,
		NO_SPACE_ON_FILESYSTEM = 14,
		QUOTA_EXCEEDED = 15,
		UNKNOWN_PRINCIPAL = 16,
		LOCK_CONFLICT = 17,
		DIR_NOT_EMPTY = 18,
		NOT_A_DIRECTORY = 19,
		INVALID_FILENAME = 20,
		LINK_LOOP = 21,
	}

	LIBSSH2_SFTP_HANDLE * libssh2_sftp_open_ex(LIBSSH2_SFTP *sftp, const char *filename, uint filename_len, c_ulong flags, c_long mode, int open_type);


	ssize_t libssh2_sftp_read(LIBSSH2_SFTP_HANDLE *handle, char *buffer, size_t buffer_maxlen); 
	ssize_t libssh2_sftp_write(LIBSSH2_SFTP_HANDLE *handle, const char *buffer, size_t count);

	enum LIBSSH2_SFTP_ATTR {
		SIZE            = 0x00000001,
		UIDGID          = 0x00000002,
		PERMISSIONS     = 0x00000004,
		ACMODTIME       = 0x00000008,
		EXTENDED        = 0x80000000,
	}

	struct LIBSSH2_SFTP_ATTRIBUTES {
		c_ulong flags; // see LIBSSH2_SFTP_ATTR

		ulong filesize;
		c_ulong uid, gid;
		c_ulong permissions;
		c_ulong atime, mtime;
	}

	int libssh2_sftp_readdir_ex(LIBSSH2_SFTP_HANDLE *handle,
                        char *buffer, size_t buffer_maxlen,
                        char *longentry, size_t longentry_maxlen, // longentry is just a user-friendly display
                        LIBSSH2_SFTP_ATTRIBUTES *attrs);
	int libssh2_sftp_stat_ex(LIBSSH2_SFTP *sftp,
					     const char *path,
					     uint,
					     int stat_type,
					     LIBSSH2_SFTP_ATTRIBUTES *attrs);
	int libssh2_sftp_fstatvfs(LIBSSH2_SFTP_HANDLE *handle,
					      LIBSSH2_SFTP_STATVFS *st);
	int libssh2_sftp_statvfs(LIBSSH2_SFTP *sftp,
					     const char *path,
					     size_t path_len,
					     LIBSSH2_SFTP_STATVFS *st);
	int libssh2_sftp_rmdir_ex(LIBSSH2_SFTP *sftp,
					      const char *path,
					      uint);
	int libssh2_sftp_mkdir_ex(LIBSSH2_SFTP *sftp,
					      const char *path,
					      uint, c_long mode);
	int libssh2_sftp_unlink_ex(LIBSSH2_SFTP *sftp,
					       const char *filename,
					       uint);
	int libssh2_sftp_symlink_ex(LIBSSH2_SFTP *sftp,
						const char *path,
						uint,
						char *target,
						uint,
						int link_type);
	int libssh2_sftp_rename_ex(LIBSSH2_SFTP *sftp,
					       const char *source_filename,
					       uint,
					       const char *dest_filename,
					       uint,
					       c_long flags);

	struct LIBSSH2_SFTP_STATVFS {
		ulong  f_bsize;    /* file system block size */
		ulong  f_frsize;   /* fragment size */
		ulong  f_blocks;   /* size of fs in f_frsize units */
		ulong  f_bfree;    /* # free blocks */
		ulong  f_bavail;   /* # free blocks for non-root */
		ulong  f_files;    /* # inodes */
		ulong  f_ffree;    /* # free inodes */
		ulong  f_favail;   /* # free inodes for non-root */
		ulong  f_fsid;     /* file system ID */
		ulong  f_flag;     /* mount flags */
		ulong  f_namemax;  /* maximum filename length */
	}


	/* end sftp */

	int libssh2_userauth_password_ex(LIBSSH2_SESSION *session,
                    const char *username,
                    uint username_len,
                    const char *password,
                    uint password_len,
		    void* passwd_change_cb);
                    //LIBSSH2_PASSWD_CHANGEREQ_FUNC((*passwd_change_cb)));

	//int libssh2_userauth_password(LIBSSH2_SESSION*, const char* username, const char* password);
	int libssh2_userauth_publickey_fromfile_ex(
		LIBSSH2_SESSION* session,
		const char *username,
		uint ousername_len,
		const char *publickey,
		const char *privatekey,
		const char *passphrase);

	struct LIBSSH2_LISTENER {}
	LIBSSH2_LISTENER * libssh2_channel_forward_listen_ex(LIBSSH2_SESSION *session, const char *host,
		  int port, int *bound_port,
		  int queue_maxsize);
	int libssh2_channel_forward_cancel(LIBSSH2_LISTENER *listener);
	LIBSSH2_CHANNEL * libssh2_channel_forward_accept(LIBSSH2_LISTENER *listener);
	LIBSSH2_CHANNEL * libssh2_channel_direct_tcpip_ex(LIBSSH2_SESSION *session, const char *host,
                                int port, const char *shost, int sport);

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


	int libssh2_channel_x11_req_ex(LIBSSH2_CHANNEL *channel,
                                           int single_connection,
                                           const char *auth_proto,
                                           const char *auth_cookie,
                                           int screen_number);


int libssh2_channel_get_exit_status(LIBSSH2_CHANNEL* channel);
int libssh2_channel_get_exit_signal(LIBSSH2_CHANNEL *channel, char **exitsignal, size_t *exitsignal_len, char **errmsg, size_t *errmsg_len, char **langtag, size_t *langtag_len); 

int libssh2_channel_send_eof(LIBSSH2_CHANNEL *channel);

}
