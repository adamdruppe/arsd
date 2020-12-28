/++
	Fiber-based socket i/o built on Phobos' std.socket and Socket.select without any other dependencies.


	This is meant to be a single-threaded event-driven basic network server.

	---
	void main() {
		auto fm = new FiberManager();
		// little tcp echo server
		// exits when it gets "QUIT" on the socket.
		Socket listener;
		listener = fm.listenTcp6(6660, (Socket conn) {
			while(true) {
				char[128] buffer;
				auto ret = conn.receive(buffer[]);
				// keeps the Phobos interface so...
				if(ret <= 0) // ...still need to check return values
					break;
				auto got = buffer[0 .. ret];
				if(got.length >= 4 && got[0 .. 4] == "QUIT") {
					listener.close();
					break;
				} else {
					conn.send(got);
				}
			}
			conn.close();
		});

		// simultaneously listen for and echo UDP packets
		fm.makeFiber( () {
			auto sock = fm.bindUdp4(9999);
			char[128] buffer;
			Address addr;
			while(true) {
				auto ret = sock.receiveFrom(buffer[], addr);
				if(ret <= 0)
					break;
				import std.stdio;
				auto got = buffer[0 .. ret];
				// print it to the console
				writeln("Received UDP ", got);
				// send the echo
				sock.sendTo(got, addr);

				if(got.length > 4 && got[0 .. 4] == "QUIT") {
					break; // stop processing udp when told to quit too
				}
			}
		}).call(); // need to call it the first time ourselves to get it started

		// run the events. This keeps going until there are no more registered events;
		// so when all registered sockets are closed or abandoned.
		//
		// So this will return when both QUIT messages are received and all clients disconnect.
		import std.stdio;
		writeln("Entering.");

		fm.run();

		writeln("Exiting.");
	}
	---

	Note that DNS address lookups here may still block the whole thread, but other methods on `Socket` are overridden in the subclass ([FiberSocket]) to `yield` appropriately, so you should be able to reuse most existing code that uses Phobos' Socket with little to no modification. However, since it keeps the same interface as the original object, remember you still need to check your return values!

	There's two big differences:

	$(NUMBERED_LIST
		* You should not modify the `blocking` flag on the Sockets. It is already set for you and changing it will... probably not hurt, but definitely won't help.

		* You shouldn't construct the Sockets yourself, nor call `connect` or `listen` on them. Instead, use the methods in the [FiberManager] class. It will ensure you get the right objects initialized in the right way with the minimum amount of blocking.

		The `listen` family of functions accept a delegate that is called per each connection in a fresh fiber. The `connect` family of functions can only be used from inside an existing fiber - if you do it in a connection handler from listening, it is already set up. If it is from your main thread though, you'll get an assert error unless you make your own fiber ahead of time. [FiberManager.makeFiber] can construct one for you, or you can call `new Fiber(...)` from `import core.thread.fiber` yourself. Put all the work with the connection inside that fiber so the manager can do its work most efficiently.
	)

	There's several convenience functions to construct addresses for you too, or you may simply do `getAddress` or `new InternetAddress` and friends from `std.socket` yourself.

	$(H2 Conceptual Overview)

	A socket is a common programming object for communication over a network. Phobos has support for the basics and you can read more about that in my blog socket tutorial: http://dpldocs.info/this-week-in-d/Blog.Posted_2019_11_11.html

	A lot of things describe [core.thread.fiber.Fiber|fibers] as lightweight threads, and that's not wrong, but I think that actually overcomplicates them. I prefer to think of a fiber as a function that can pause itself. You call it like a function, you write it like a function, but instead of always completing and returning, it can [core.thread.fiber.Fiber.yield|yield], which is putting itself on pause and returning to the caller. The caller then has a chance to resume the function when it chooses to simply by [core.thread.fiber.Fiber.call|calling] it again, and it picks up where it left off, or the caller can [core.thread.fiber.Fiber.reset|reset] the fiber function to the beginning and start over.

	Fiber-based async i/o thus isn't as complicated as it sounds. The basic idea is you just write an ordinary function in the same style as if you were doing linear, blocking i/o calls, but instead of actually blocking, you register a callback to be woken up when the call can succeed, then yield yourself. This callback you register is simply your own fiber resume method; the event loop picks up where you left off.

	With Phobos sockets (and most Unix i/o functions), you then retry the operation that would have blocked and carry on because the callback is triggered when the operation is ready. If you're using another async system, like Windows' Overlapped I/O callbacks, it is actually even easier, since that callback happens when the operation has already completed. In those cases, you register the fiber's resume function as the event callback, then yield. When you wake up, you can immediately carry on.

	When a fiber is woken up, it continues executing from the last `yield` call. Just think of `yield` as being a pause button you press.

	Understanding how it works means you can translate any callback-based i/o system to use fibers, since it would always follow that same pattern: register the fiber resume method, then yield. If it is a callback when the operation is ready, try it again when you wake up (so right after yield, you can loop back to the call), or if it is a callback when the operation is complete, you can immediately use the result when you wake up (so right after yield, you use it).

	How does the event loop work? How do you know what fiber runs next? See, this is where the "lightweight thread" explanation complicates things. With a thread, the operating system is responsible for scheduling them and might even run several simultaneously. Fibers are much simpler: again, think of them as just being a function that can pause itself. Like with an ordinary function, just one runs at a time (in your thread anyway, of course adding threads can complicate fibers like it can complicate any other function). Like with an ordinary function, YOU choose which one you want to call and when. And when a fiber `yield`s, it is very much like an ordinary function `return`ing - it passes control back to you, the caller. The only difference is the Fiber object remembers where the function was when it yielded, so you can ask it to pick up where it left off.

	The event loop therefore doesn't look all that special. If you've used `Socket.select` before, you'll recognize most of it. (`select` can be tricky to use though, `epoll` based code is actually simpler and more efficient... but this module only wanted to use Phobos' std.socket on its own. Besides, `select` still isn't that complicated, is cross-platform, and performs well enough for most tasks anyway.) It has a list of active sockets that it adds to either a read or write set, it calls the select function, then it loops back over and handles the events, if set. The only special thing is the event handler resumes the fiber instead of some other action.

	I encourage you to view the source of this file and try to follow along. It isn't terribly long and can hopefully help to introduce you to a new world of possibilities. You can use Fibers in other cases too, for example, the game I'm working on uses them in enemy scripts. It sets up their action, then yields and lets the player take their turn. When it is the computer's turn again, the script fiber resumes. Same principle, simple code once you get to know it.

	$(H2 Limitations)
	`Socket.select` has a limit on the number of pending sockets at any time, and since you have to loop through them each iteration, it can get slow with huge numbers of concurrent connections. I'd note that you probably will not see this problem, but it certainly can happen. Similarly, there's `new` allocations for each socket and virtual calls throughout, which, again, probably will be good enough for you, but this module is not C10K+ "web scale".

	It also cannot be combined with other event loops in the same thread. But, since the [FiberManager] only uses the thread you give it, you might consider running it here and other things along side in their own threads.

	Credits:
		vibe.d is the first time I recall even hearing of fibers and is the direct inspiration for this.

	History:
		Written December 26, 2020. First included in arsd-official dub release 9.1.

	License:
		BSL-1.0, same as Phobos
+/
module arsd.fibersocket; // previously known as "centivibe" since it provides like 1/100th the functionality of vibe.d

public import std.socket;
import core.thread.fiber;

/// just because I forget how to enable this, trivial helper function
void allowBroadcast(Socket socket) {
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
}

/// Convenience function to loop and send until it it all sent or an error occurs.
ptrdiff_t sendAll(Socket s, scope const(void)[] data) {
	auto ol = data.length;
	while(data.length) {
		auto ret = s.send(data);
		if(ret <= 0)
			return ret;
		data = data[ret .. $];
	}
	return ol;
}

/++
	Subclass of Phobos' socket that basically works the same way, except it yields back to the [FiberManager] when it would have blocked.

	You should not modify the `blocking` flag on these and generally not construct them, connect them, or listen on them yourself (let [FiberManager] do the setup for you), but otherwise they work the same as the original Phobos [std.socket.Socket] and implement the very same interface. You can call the exact same functions with original Sockets or FiberSockets.
+/
class FiberSocket : Socket {
	enum PendingOperation {
		none, read, write
	}

	protected this(FiberManager fm) pure nothrow @safe {
		this.fm = fm;
		super();
	}

	/// You should probably call the helper functions in [FiberManager] instead.
	this(FiberManager fm, AddressFamily af, SocketType st, Fiber fiber) {
		assert(fm !is null);

		this.fm = fm;
		this.fiber = fiber;
		super(af, st);
		this.blocking = false;
	}

	void callFiber() {
		fiber.call();
	}

	private FiberManager fm;
	private Fiber fiber;
	private PendingOperation pendingOperation;

	private void queue(PendingOperation op) @trusted nothrow {
		pendingOperation = op;
		fm.pendingSockets ~= this;
		fiber.yield();
	}

	protected override Socket accepting() pure nothrow {
		return new FiberSocket(fm);
	}

	private ptrdiff_t magic(scope ptrdiff_t delegate() @safe what, PendingOperation op) @trusted {
		try_again:
		auto r = what();
		if(r == -1 && wouldHaveBlocked()) {
			queue(op);
			goto try_again;
		}
		return r;
	}
	
	/// Yielding override of the Phobos interface
	override ptrdiff_t send(const(void)[] buf, SocketFlags flags) {
		return magic( () { return super.send(buf, flags); }, PendingOperation.write);
	}
	/// ditto
	override ptrdiff_t receive(void[] buf, SocketFlags flags) {
		return magic( () { return super.receive(buf, flags); }, PendingOperation.read);
	}

	/// ditto
	override ptrdiff_t receiveFrom(void[] buf, SocketFlags flags, ref Address from) @trusted {
		return magic( () { return super.receiveFrom(buf, flags, from); }, PendingOperation.read);
	}
	/// ditto
	override ptrdiff_t receiveFrom(void[] buf, SocketFlags flags) @trusted {
		return magic( () { return super.receiveFrom(buf, flags); }, PendingOperation.read);
	}
	/// ditto
	override ptrdiff_t sendTo(const(void)[] buf, SocketFlags flags, Address to) @trusted {
		return magic( () { return super.sendTo(buf, flags, to); }, PendingOperation.write);
	}
	/// ditto
	override ptrdiff_t sendTo(const(void)[] buf, SocketFlags flags) @trusted {
		return magic( () { return super.sendTo(buf, flags); }, PendingOperation.write);
	}

	// lol overload sets
	/// The Phobos overloads are still available too, they forward to the overrides in this class and thus work the same way.
	alias send = typeof(super).send;
	/// ditto
	alias receive = typeof(super).receive;
	/// ditto
	alias sendTo = typeof(super).sendTo;
	/// ditto
	alias receiveFrom = typeof(super).receiveFrom;
}

/++
	The FiberManager is responsible for running your socket event loop and dispatching events to your fibers. It is your main point of interaction with this library.

	Generally, a `FiberManager` will exist in your `main` function and take over that thread when you call [run]. You construct one, set up your listeners, etc., then call `run` and let it do its thing.
+/
class FiberManager {
	private FiberSocket[] pendingSockets;

	private size_t defaultFiberStackSize;

	/++
		Params:
			defaultFiberStackSize = size, in bytes, of the fiber stacks [makeFiber] returns. If 0 (the default), use the druntime default.
	+/
	this(size_t defaultFiberStackSize = 0) {
		this.defaultFiberStackSize = defaultFiberStackSize;
	}

	/++
		Convenience function to make a worker fiber based on the manager's configuration.

		This is used internally when connections come in.
	+/
	public Fiber makeFiber(void delegate() fn) {
		return defaultFiberStackSize ? new Fiber(fn, defaultFiberStackSize) : new Fiber(fn);
	}

	/++
		Convenience functions for creating listening sockets. These are trivial forwarders to [listenStream], constructing the appropriate [std.socket.Address] object for you. Note the address lookup does NOT at this time use the fiber io and may thus block your thread.

		You can `close` the returned socket when you want to stop listening, or just ignore it if you want to listen for the whole duration of the program.
	+/
	final Socket listenTcp6(ushort port, void delegate(Socket) connectionHandler, int backlog = 8) {
		return listenStream(new Internet6Address(port), connectionHandler, backlog);
	}

	/// ditto
	final Socket listenTcp6(string address, ushort port, void delegate(Socket) connectionHandler, int backlog = 8) {
		return listenStream(new Internet6Address(address, port), connectionHandler, backlog);
	}

	/// ditto
	final Socket listenTcp4(ushort port, void delegate(Socket) connectionHandler, int backlog = 8) {
		return listenStream(new InternetAddress(port), connectionHandler, backlog);
	}

	/// ditto
	final Socket listenTcp4(string address, ushort port, void delegate(Socket) connectionHandler, int backlog = 8) {
		return listenStream(new InternetAddress(address, port), connectionHandler, backlog);
	}

	/// ditto
	version(Posix)
	final Socket listenUnix(string path, void delegate(Socket) connectionHandler, int backlog = 8) {
		return listenStream(new UnixAddress(path), connectionHandler, backlog);
	}

	/++
		Core listen function for streaming connection-oriented sockets (TCP, etc.)


		It will:

		$(LIST
			* Create a [FiberSocket]
			* Create fibers on it for each incoming connection which call your `connectionHandler`
			* Bind to the given `Address`
			* Call `socket.listen(backlog)`
			* Start `accept`ing connections.
		)

		Returns: the listening socket. You shouldn't do much with this except maybe `close` it when you are done.
	+/
	Socket listenStream(Address addr, void delegate(Socket) connectionHandler, int backlog) {
		assert(connectionHandler !is null, "null connectionHandler passed to a listenTcp function");

		FiberSocket socket;

		socket = new FiberSocket(this, addr.addressFamily, SocketType.STREAM, makeFiber(
			delegate() {
				while(socket.isAlive()) {
					socket.queue(FiberSocket.PendingOperation.read); // put fiber on hold until ready to accept

					auto ns = cast(FiberSocket) socket.accept();
					ns.blocking = false;
					ns.fiber = makeFiber(delegate() {
						connectionHandler(ns);
					});
					// need to get the new connection started
					ns.fiber.call();
				}
			}
		));
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.bind(addr);
		socket.blocking = false;
		socket.listen(backlog);

		socket.callFiber();

		return socket;
	}

	/++
		Convenience functions that forward to [connectStream] for the given protocol. They connect, send, and receive in an async manner, but do not create their own fibers - you must already be in one when you call this function.


		Connections only work if you are already in a fiber. This is the case in a connectionHandler, but not from your main function. You'll have to make your own worker fiber. (But tbh if you only have one connection anyway, you might as well use a standard Socket.)

		If you are already in a connection handler set in the listen family of functions, you're all set - those are automatically in fibers. If you are in main though, you need to make a worker fiber.

		Making a worker fiber is simple enough. You can do it with `new Fiber` or with [FiberManager.makeFiber] (the latter just calls the former with a size argument set up in the FiberManager constructor).

		---
		auto fm = new FiberManager();
		fm.makeFiber(() {
			auto socket = fm.connectTcp4(...);

			socket.send(...);
		}).call(); // you must call it the first time yourself so it self-registers
		---

		OR

		---
		import core.thread.fiber;

		auto fiber = new Fiber(() {
			auto socket = fm.connectTcp4(...);
			// do stuff in here
		}).call(); // same deal, still need to call it the first time yourself to give it a chance to self-register
		---
	+/
	final Socket connectTcp4(string address, ushort port) {
		return connectStream(new InternetAddress(address, port));
	}

	/// ditto
	final Socket connectTcp6(string address, ushort port) {
		return connectStream(new Internet6Address(address, port));
	}

	/// ditto
	version(Posix)
	final Socket connectUnix(string path) {
		return connectStream(new UnixAddress(path));
	}

	/++
		Connects a streaming socket to the given address that will yield to this FiberManager instead of blocking.

	+/
	Socket connectStream(Address address) {
		assert(Fiber.getThis !is null, "connect functions can only be used from inside preexisting fibers");
		FiberSocket socket = new FiberSocket(this, address.addressFamily, SocketType.STREAM, Fiber.getThis);
		socket.connect(address);
		socket.queue(FiberSocket.PendingOperation.write); // wait for it to connect
		scope(failure)
			socket.close();
		// and ensure the connection was successful before proceeding
		int result;
		if(socket.getOption(SocketOptionLevel.SOCKET, SocketOption.ERROR, result) < 0)
			throw new Exception("get socket error failed");
		if(result != 0)
			throw new Exception("Connect failed");
		return socket;
	}

	/++
		These are convenience functions that forward to [bindDatagram].

		UDP sockets don't connect per se, but the basically work the same as [connectStream]. See the caveat about requiring a premade Fiber from that page.
	+/
	Socket bindUdp4(string address, ushort port) {
		return bindDatagram(new InternetAddress(address, port));
	}
	/// ditto
	Socket bindUdp4(ushort port) {
		return bindDatagram(new InternetAddress(port));
	}
	/// ditto
	Socket bindUdp6(string address, ushort port) {
		return bindDatagram(new Internet6Address(address, port));
	}
	/// ditto
	Socket bindUdp6(ushort port) {
		return bindDatagram(new Internet6Address(port));
	}

	/++
		Only valid from inside a worker fiber, see [makeFiber].

		---
		fm.makeFiber(() {
			auto sock = fm.bindDatagram(new InternetAddress(5555));
			sock.receiveFrom(....);
		}).call(); // remember to call it the first time or it will never start!
	+/
	Socket bindDatagram(Address address) {
		assert(Fiber.getThis !is null, "bind datagram functions can only be used from inside preexisting fibers");
		FiberSocket socket = new FiberSocket(this, address.addressFamily, SocketType.DGRAM, Fiber.getThis);
		socket.bind(address);
		return socket;
	}

	/++
		Runs the program and manages the fibers and connections for you, calling the appropriate functions when new events arrive.

		Returns when no connections are left open.
	+/
	void run() {
		auto readSet = new SocketSet;
		auto writeSet = new SocketSet;
		while(true) {
			readSet.reset();
			writeSet.reset();
			int added;
			for(int idx = 0; idx < pendingSockets.length; idx++) {
				auto pending = pendingSockets[idx];
				if(!pending.isAlive()) {
					// order not important here since we haven't done any real work yet
					// really it shouldn't even be on the list.
					pendingSockets[idx] = pendingSockets[$-1];
					pendingSockets = pendingSockets[0 .. $-1];
					pendingSockets.assumeSafeAppend();
					idx--;
					continue;
				}
				final switch(pending.pendingOperation) {
					case FiberSocket.PendingOperation.none:
						assert(0); // why is this object on this list?!
					case FiberSocket.PendingOperation.write:
						writeSet.add(pending);
						added++;
						break;
					case FiberSocket.PendingOperation.read:
						readSet.add(pending);
						added++;
						break;
				}
			}
			if(added == 0)
				return; // no work to do, all connections closed
			auto eventCount = Socket.select(readSet, writeSet, null);//, 5.seconds);
			if(eventCount == -1)
				continue;
			for(int idx = 0; idx < pendingSockets.length && eventCount > 0; idx++) {
				auto pending = pendingSockets[idx];
				SocketSet toCheck;
				final switch(pending.pendingOperation) {
					case FiberSocket.PendingOperation.none:
						break;
					case FiberSocket.PendingOperation.write:
						toCheck = writeSet;
						break;
					case FiberSocket.PendingOperation.read:
						toCheck = readSet;
						break;
				}
				if(toCheck is null)
					continue;

				if(toCheck.isSet(pending)) {
					eventCount--;
					import std.algorithm.mutation;
					// the order is fairly important since previous calls can append to
					// this again, and we want to be sure we process the ones in this batch
					// before seeing anything from the next batch.
					pendingSockets = remove!(SwapStrategy.stable)(pendingSockets, idx);
					pendingSockets.assumeSafeAppend();
					idx--; // the slot we used to have is now different, so it needs to be reprocessed
					pending.fiber.call();
				}
			}
		}
	}
}
