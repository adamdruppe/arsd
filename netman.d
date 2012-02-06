// This is a little core I wrote a few years ago to write custom tcp servers
// in D. It only works on Linux, doesn't care much for efficiency, and uses
// select() to handle multiple connections in a single thread.

// It is my hope that someday soon, Phobos will get a network module that
// can completely replace this. But, until that happens, this little thing
// is better than nothing.

// See httpd.d for a (pretty bad) http server built on this, or rtud.d
// for a real time update helper program that also uses it.

// If anyone is interested, I also have chat (including TOC protocol to be
// a little AIM client) and minimal gui (version one of my D windowing system
// idea... which is still on my todo list, but it's going to be aeons before
// it's remotely usable  at the rate I'm going) built on this module.

module arsd.netman;

version(linux):

import std.c.linux.linux;
import std.c.linux.socket;

static import std.string;
static import std.c.string;
static import std.stdio;
static import std.conv;

alias std.c.linux.socket sock;
alias std.c.linux.linux linux;

enum int PF_INET = 2;
enum int AF_INET = PF_INET;


int max(int a, int b){ return a > b ? a : b; }

class ConnectionException : Exception {
	this(string message, Connection conn) {
		msg = message;
		c = conn;
		super(message);
	}

	string msg;
    public:
	Connection c;
	override string toString() {
		return msg;
	}
}


class NetworkManager {
	// you might want to override this to construct subclasses of connection
  protected:
	Connection allocConnection(int port) {
		if(auto a = port in allocs)
			return (*a)();
		assert(0);
	}
	Connection allocOutgoingConnection(int port){
		if(auto a = port in allocs)
			return (*a)();
		return new Connection();
		assert(0);
	}


  public:
//	void openSerialPort();
	this() {
		if(!handledSignal) {
			handledSignal = true;
			signal(SIGPIPE, SIG_IGN);
		}
	}
	static bool handledSignal = false;

	void setConnectionSpawner(int port, Connection delegate() c) {
		assert(c !is null);
		allocs[port] = c;
	}
	
	void setConnectionSpawner(int port, Connection function() c) {
		setConnectionSpawner(port, { return c(); });
	}


	size_t numActiveConnections(){
		return connections.length;
	}

	Connection connect(string ipaddr, ushort port){
		Connection c = allocOutgoingConnection(port);

		c.parentManager = this;

		hostent* h;
		sockaddr_in addr;

		h = gethostbyname(std.string.toStringz(ipaddr));
		if(h is null)
			throw new Exception("gethostbyname");

		int s = socket(PF_INET, SOCK_STREAM, 0);
		if(s == -1)
			throw new Exception("socket");

		scope(failure)
			close(s);

		addr.sin_family = AF_INET;
		addr.sin_port = htons(port);
		std.c.string.memcpy(&addr.sin_addr.s_addr, h.h_addr, h.h_length);
	
		if(sock.connect(s, cast(sockaddr*) &addr, addr.sizeof) == -1)
			throw new Exception("connect");

		addConnection(c, s, cast(sockaddr) addr, port);
		c.onConnect();

		return c;
	}

	void openStdin() {
		Connection c = allocConnection(0);

		c.parentManager = this;

		sockaddr addr;

		addConnection(c, 0, addr, 0);
	}


	void listen(ushort port, int queue = 4){
		int s = socket(PF_INET, SOCK_STREAM, 0);
		if(s == -1)
			throw new Exception("socket");
		scope(failure)
			close(s);

		sockaddr_in addr;
		addr.sin_family = AF_INET;
		addr.sin_port = htons(port);
		addr.sin_addr.s_addr = INADDR_ANY;

// HACKISH
int on = 1;
setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, on.sizeof);
// end hack

		
		if(bind(s, cast(sockaddr*) &addr, addr.sizeof) == -1)
			throw new Exception("bind");

		if(sock.listen(s, queue) == -1)
			throw new Exception("listen");

		listenings.length = listenings.length + 1;

		listenings[$-1].s = s;
		listenings[$-1].port = port;
	}

	/// returns true if stuff happened, false if timed out
	/// timeout of 0 means wait forever - set it to -1 if you want it to return immediately
	bool proceed(int timeout = 0){
		//events to handle: data ready to read, timeout, new connection, connection error
		// stuff to do: write data

		fd_set rdfs;
		fd_set writefs;
		timeval tv;

		FD_ZERO(&rdfs);
		FD_ZERO(&writefs);

		int biggest = -1;

		foreach(connection; connections){
			if(connection.socket == -1)
				continue;
			if(connection.writeBufferLength > 0)
				FD_SET(connection.socket, &writefs);

			FD_SET(connection.socket, &rdfs);
			biggest = max(biggest, connection.socket);
		}

		foreach(c; listenings){
			FD_SET(c.s, &rdfs);
			biggest = max(biggest, c.s);
		}


		if(timeout == -1)
		tv.tv_sec = 0;
		else
		tv.tv_sec = timeout;
		tv.tv_usec = 0;

	int ret;
		if(timeout == 0)
			ret = linux.select(biggest + 1, &rdfs, &writefs, null, null);
		else
			ret = linux.select(biggest + 1, &rdfs, &writefs, null, &tv);

		if(ret == -1)
			throw new Exception("select");

		if(ret) {
			// data ready somewhere


			foreach(connection; connections){
				if(connection.socket == -1)
					continue;
				if(connection.writeBufferLength > 0)
					if(FD_ISSET(connection.socket, &writefs)){
						auto b = connection.writeBuffer[connection.writeBufferPosition..(connection.writeBufferPosition+connection.writeBufferLength)];
						//auto num = send(connection.socket, b.ptr, b.length, 0);
						auto num = write(connection.socket, b.ptr, b.length);
						if(num < 0)
							throw new ConnectionException("send", connection);

						connection.writeBufferLength -= num;
						if(connection.writeBufferLength > 0)
							connection.writeBufferPosition += num;
						else
							connection.writeBufferPosition = 0;

					connection.timeOfLastActivity = now;
					}
				if(FD_ISSET(connection.socket, &rdfs)){
					size_t s = connection.readBufferPosition + connection.readBufferLength;
					s += 1024;
					if(connection.readBuffer.length < s)
						connection.readBuffer.length = s;
					//auto size = recv(connection.socket, connection.readBuffer.ptr + connection.readBufferPosition + connection.readBufferLength, 1024, 0);
					//std.stdio.writefln("read buffer length: %s", connection.readBufferLength);
					auto size = read(connection.socket, connection.readBuffer.ptr + connection.readBufferPosition + connection.readBufferLength, 1024);
					if(size == 0){
						connection.disconnectQueued = true;
						connection.reason = "size == 0";
					}
					else if (size < 0)
						throw new ConnectionException("recv", connection);
					else {
						connection.readBufferLength += size;
						connection.onDataReceived();
					}

					connection.timeOfLastActivity = now;
				}
			}

			foreach(c; listenings){
				if(FD_ISSET(c.s, &rdfs)){
					uint i;
					sockaddr addr;
					i = addr.sizeof;
					int s = accept(c.s, &addr, &i);

					if(s == -1)
						throw new Exception("accept");

					version(threaded_connections) {
						auto con = allocConnection(c.port);
						con.socket = s;
						con.addr = addr;
						con.port = c.port;
						auto t = new ConnectionThread(con);
						t.start();
					} else {
						auto con = allocConnection(c.port);
						con.parentManager = this;
						addConnection(con, s, addr, c.port);
						con.onRemoteConnect();
					}
				}
			}



			// One last run through the connections to remove any stale ones...
			for(int a = 0; a < connections.length; a++) {
				if( /* HACK */ connections[a].socket != 0 && /* END HACK */
				connectionTimeOut && (now-connections[a].timeOfLastActivity) > connectionTimeOut){
					connections[a].disconnectQueued = true;
					connections[a].reason = "stale";
				}
				if(connections[a].disconnectQueued && connections[a].writeBufferLength == 0)
					connections[a].disconnectNow();

				if(connections[a].socket == -1){
					for(int b = a; b < connections.length-1; b++)
						connections[b] = connections[b+1];
					connections.length = connections.length - 1;
					a--;
				}
			}

		} else {
			// timed out
			return false;
		}

		return true;
	}


	// FIXME: for some reason, this whole timeout thing doesn't actually work correctly.

	int connectionTimeOut = 0;//152;

  private:
	Connection delegate()[int] allocs;

	void addConnection(Connection c, int s, sockaddr addr, int port){
		c.socket = s;
		c.addr = addr;
		c.port = port;

		if(c.socket < 0)
			throw new Exception("don't add bad sockets");
		connections.length = connections.length + 1;
		connections[$-1] = c;
	}

	struct ListeningSocket{
		int s;
		int port;
	}

	ListeningSocket[] listenings;
	Connection[] connections;
}


// You should only ever construct these in the allocConnection delegate for the manager.
// Otherwise it will probably crash/
class Connection {
  public:

	NetworkManager parentManager;

	protected this(){ timeOfLastActivity = now; }

	string reason;

	~this(){
		disconnectNow(false);
	}

	void disconnectNow(bool cod = true){
		if(socket >= 0){
			close(socket);
			socket = -1;
			if(cod)
				onDisconnect();
		}
	}

	void disconnect() {
		disconnectQueued = true;
	}

	// Writes the pending data to the socket now instead of waiting for the manager to proceed
	void flush(){

	}

	// reads the requested amount now, blocking until you get it all.
	void fetch(int amount){

	}

	void write(const(void)[] data){
		if(socket < 0)
			throw new ConnectionException("cannot write to a closed connection", this);

		size_t newEnd = writeBufferPosition + writeBufferLength + data.length;

		if(newEnd >= writeBuffer.length)
			writeBuffer.length = newEnd;

		writeBuffer[writeBufferLength..newEnd] = cast(const(ubyte)[]) data[0..$];

		writeBufferLength += data.length;
	}


	const(ubyte)[] read(){
		if(socket < 0)
			return null;

		auto d = readBuffer[readBufferPosition..(readBufferPosition + readBufferLength)];
		rofl = readBufferPosition;
		copter = readBufferLength;

		return d;
	}

	private size_t rofl, copter;

	void changeReadPosition(int p) {
		//assert(p <= copter);
		//std.stdio.writefln("%d from %d of %d", p, readBufferPosition, readBufferLength);
		readBufferLength = copter - p;
		readBufferPosition = rofl + p;
		//std.stdio.writefln("became %d of %d", readBufferPosition, readBufferLength);
	}

	void resetRead(){
		readBufferLength = 0;
		readBufferPosition = 0;
	}


	// These events should be reimplemented by subclasses

	void onDataReceived(){
		// read() the data and process it
		// then resetRead() to prepare for the next batch
		resetRead;
	}

	// we just connected to someone
	void onConnect(){

	}

	// someone just connected to us
	void onRemoteConnect(){
		onConnect();
	}

	void onDisconnect(){
	}

	bool ready() {
		return socket != -1;
	}

	string peerAddress() {
		if(addr.sa_family != 2)
			throw new ConnectionException("peerAddress not supported for this connection", this);

		return std.conv.to!string(cast(const(ubyte)[]) addr.sa_data[2..6],
			"", ".", ""
		);

	}
/*
	ushort peerPort() {

	}
*/
	int fd() { return socket; }
  private:
	int socket = -1;

	ubyte[] writeBuffer;
	ubyte[] readBuffer;

	size_t writeBufferPosition;
	size_t writeBufferLength;

	size_t readBufferPosition;
	size_t readBufferLength;

	bool disconnectQueued;

	sockaddr addr;
	int port;

	int timeOfLastActivity;
}


import std.date;
int now() {
        return cast(int) getUTCtime();
}



version(threaded_connections) {
	import core.thread;
	import std.stdio : writeln;
	class ConnectionThread : Thread {
		Connection connection;
		this(Connection c) {
			connection = c;
			super(&run);
		}

		void run() {
			scope(exit)
				connection.disconnectNow();
			auto manager = new NetworkManager();
			connection.parentManager = manager;
			manager.addConnection(connection, connection.socket, connection.addr, connection.port);
			while(manager.proceed()) {}
		}
	}
}
