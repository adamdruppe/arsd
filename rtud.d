/**
	OBSOLETE: This provides a kind of real time updates that can be consumed
	by javascript (and probably other things eventually). Superseded by
	new functionality built into [arsd.cgi].

	First, you compile the server app. dmd -version=standalone_rtud -version=rtud_daemon

	Run it. It's pretty generic; probably don't have to modify it
	but you always can. It's useful to have a long running process
	anyway.

	But then you'll want an intermediary between this and the javascript.
	Use the handleListenerGateway() function in your cgi app for that.
	You can pass it a channel prefix for things like user ids.

	In your javascript, use EventListener("path to gateway");
	And addEventListener(type, function, false);

	Note: this javascript does not work in all browsers, but
	real time updates should really be optional anyway.

	I might add a traditional ajax fallback but still, it's all
	js so be sure it's non-essential if possible.


	And in your app, as events happen, use in D:
		auto stream = new UpdateStream(channel);
		stream.sendMessage(type, message);

	and the helper app will push it all out. You might want to wrap
	some of this in try/catch since if the helper app dies, this will
	throw since it can't connect.


	I found using user names as channels is good stuff. Then your JS
	doesn't provide a channel at all - your helper app gives it through
	the channel prefix argument.
*/
module arsd.rtud;

import std.string;
import std.array : replace;
import std.conv;
import std.date;


class UpdateStream {
	File net;
	string channel;

	this(string channel) {
		net = openNetwork("localhost", 7071);
		this.channel = channel;
	}

	~this() {
		net.close();
	}

	void deleteMessage(string messageId) {
		import arsd.cgi; // : encodeVariables;
		string message = encodeVariables([
			"id" : messageId,
			"operation" : "delete"
		]);

		net.writeln(message);
		net.flush();
	}

	void sendMessage(string eventType, string messageText, long ttl = 2500) {
		import arsd.cgi; // : encodeVariables;
		string message = encodeVariables([
			//"operation" : "post",
			//"id" : ????,
			"channel" : channel,
			"type" : eventType,
			"data" : messageText,
			"ttl" : to!string(ttl)
		]);

		net.writeln(message);
		net.flush();
	}
}

/+
		if("channels" in message) {
		if("last-message-id" in message)
		if("minimum-time" in message)
		if("close-time" in message)
+/

version(D_Version2) {
	static import linux = core.sys.posix.unistd;
	static import sock = core.sys.posix.sys.socket;
} else {
	static import linux = std.c.linux.linux;
	static import sock = std.c.linux.socket;
}

int openNetworkFd(string host, ushort port) {
	import std.exception;
	auto h = enforce( sock.gethostbyname(std.string.toStringz(host)),
		new StdioException("gethostbyname"));

	int s = sock.socket(sock.AF_INET, sock.SOCK_STREAM, 0);
	enforce(s != -1, new StdioException("socket"));

	scope(failure) {
	    linux.close(s);
	}

	sock.sockaddr_in addr;

	addr.sin_family = sock.AF_INET;
	addr.sin_port = sock.htons(port);
	std.c.string.memcpy(&addr.sin_addr.s_addr, h.h_addr, h.h_length);

	enforce(sock.connect(s, cast(sock.sockaddr*) &addr, addr.sizeof) != -1,
		new StdioException("Connect failed"));

	return s;
}

void writeToFd(int fd, string s) {
	again:
	auto num = linux.write(fd, s.ptr, s.length);
	if(num < 0)
		throw new Exception("couldn't write");
	if(num == 0)
		return;
	s = s[num .. $];
	if(s.length)
		goto again;
}

__gshared bool deathRequested = false;
extern(C)
void requestDeath(int sig) {
	deathRequested = true;
}

import arsd.cgi;
/// The throttledConnection param is useful for helping to get
/// around browser connection limitations.

/// If the user opens a bunch of tabs, these long standing
/// connections can hit the per-host connection limit, breaking
/// navigation until the connection times out.

/// The throttle option sets a long retry period and polls
/// instead of waits. This sucks, but sucks less than your whole
/// site hanging because the browser is queuing your connections!
int handleListenerGateway(Cgi cgi, string channelPrefix, bool throttledConnection = false) {
	cgi.setCache(false);

	import core.sys.posix.signal;
	sigaction_t act;
	// I want all zero everywhere else; the read() must not automatically restart for this to work.
	act.sa_handler = &requestDeath;

	if(linux.sigaction(linux.SIGTERM, &act, null) != 0)
		throw new Exception("sig err");

	auto f = openNetworkFd("localhost", 7070);
	scope(exit) linux.close(f);

	string[string] variables;

	variables["channel"] = channelPrefix ~ ("channel" in cgi.get ? cgi.get["channel"] : "");
	if("minimum-time" in cgi.get)
		variables["minimum-time"] = cgi.get["minimum-time"];
	if("last-message-id" in cgi.get)
		variables["last-message-id"] = cgi.get["last-message-id"];

	bool isSse;

	if(cgi.accept == "text/event-stream") {
		cgi.setResponseContentType("text/event-stream");
		isSse = true;
		if(cgi.lastEventId.length)
			variables["last-message-id"] = cgi.lastEventId;

		if(throttledConnection) {
			cgi.write("retry: 15000\n");
		} else {
			cgi.write(":\n"); // the comment ensures apache doesn't skip us
		}

		cgi.flush(); // sending the headers along
	} else {
		// gotta handle it as ajax polling
		variables["close-time"] = "0"; // ask for long polling
	}


	if(throttledConnection)
		variables["close-time"] = "-1"; // close immediately

	writeToFd(f, encodeVariables(variables) ~ "\n");

	string wegot;

	string[4096] buffer;

	for(; !deathRequested ;) {
		auto num = linux.read(f, buffer.ptr, buffer.length);
		if(num < 0)
			throw new Exception("read error");
		if(num == 0)
			break;

		auto chunk = buffer[0 .. num];
		if(isSse) {
			cgi.write(chunk);
			cgi.flush();
		} else {
			wegot ~= cast(string) chunk;
		}
	}

	// this is to support older browsers
	if(!isSse && !deathRequested) {
		// we have to parse it out and reformat for plain cgi...
		auto lol = parseMessages(wegot);
		//cgi.setResponseContentType("text/json");
		// FIXME gotta reorganize my json stuff
		//cgi.write(toJson(lol));
		return 1;
	}

	return 0;
}

struct Message {
	string type;
	string id;
	string data;
	long timestamp;
	long ttl;

	string operation;
}


Message[] getMessages(string channel, string eventTypeFilter = null, long maxAge = 0) {
	auto f = openNetworkFd("localhost", 7070);
	scope(exit) linux.close(f);

	string[string] variables;

	variables["channel"] = channel;
	if(maxAge)
		variables["minimum-time"] = to!string(getUtcTime() - maxAge);

	variables["close-time"] = "-1"; // close immediately

	writeToFd(f, encodeVariables(variables) ~ "\n");

	string wegot;

	string[4096] buffer;

	for(;;) {
		auto num = linux.read(f, buffer.ptr, buffer.length);
		if(num < 0)
			throw new Exception("read error");
		if(num == 0)
			break;

		auto chunk = buffer[0 .. num];
		wegot ~= cast(string) chunk;
	}

	return parseMessages(wegot, eventTypeFilter);
}

Message[] parseMessages(string wegot, string eventTypeFilter = null) {
	// gotta parse this since rtud writes out the format for browsers
	Message[] ret;
	foreach(message; wegot.split("\n\n")) {
		Message m;
		foreach(line; message.split("\n")) {
			if(line.length == 0)
				throw new Exception("wtf");
			if(line[0] == ':')
				line = line[1 .. $];

			if(line.length == 0)
				continue; // just an empty comment

			auto idx = line.indexOf(":");
			if(idx == -1)
				continue; // probably just a comment

			if(idx + 2 > line.length)
				continue; // probably just a comment too

			auto name = line[0 .. idx];
			auto data = line[idx + 2 .. $];

			switch(name) {
				default: break; // do nothing
				case "timestamp":
					if(data.length)
					m.timestamp = to!long(data);
				break;
				case "ttl":
					if(data.length)
					m.ttl = to!long(data);
				break;
				case "operation":
					m.operation = data;
				break;
				case "id":
					m.id = data;
				break;
				case "event":
					m.type = data;
				break;
				case "data":
					m.data ~= data;
				break;
			}
		}
		if(eventTypeFilter is null || eventTypeFilter == m.type)
			ret ~= m;
	}

	return ret;
}


version(rtud_daemon) :

import arsd.netman;

// Real time update daemon
/*
	You push messages out to channels, where they are held for a certain length of time.

	It can also do state with listener updates.

	Clients ask for messages since a time, and if there are none, you hold the connection until something arrives.


	There should be D and Javascript apis for pushing and receiving.


	JS:

	var updateObject = RealTimeUpdate();

	updateObject.someMessage = function(msg) {
		// react to it
	}

	updateObject.listen(channel);

	updateObject.send(message, args); // probably shouldn't need this from JS
*/

/*
	Incoming Packet format is x-www-urlencoded. There must be no new lines
	in there - be sure to url encode them.

	A message is separated by newlines.
*/

class RtudConnection : Connection {
	RealTimeUpdateDaemon daemon;

	this(RealTimeUpdateDaemon daemon) {
		this.daemon = daemon;
	}

	override void onDataReceived() {
		import arsd.cgi;// : decodeVariables;
		try_again:
			auto data = cast(string) read();

			auto index = data.indexOf("\n");
			if(index == -1)
				return; // wait for more data

			auto messageRaw = data[0 .. index];
			changeReadPosition(index + 1);

			auto message = decodeVariables(messageRaw);

			handleMessage(message);
		goto try_again;
	}

	invariant() {
		assert(daemon !is null);
	}

	abstract void handleMessage(string[][string] message);
}

class NotificationConnection : RtudConnection {
	this(RealTimeUpdateDaemon daemon) {
		super(daemon);
		closeTime = long.max;
	}

	long closeTime;

	/// send: what channels you're interested in, a minimum time,
	/// and a close time.
	/// if the close time is negative, you are just polling curiously.
	/// if it is zero, it will close after your next batch. (long polling)
	/// anything else stays open for as long as it can in there.

	override void handleMessage(string[][string] message) {
		Channel*[] channels;

		if("channels" in message) {
			foreach(ch; message["channels"]) {
				auto channel = daemon.getChannel(ch);
				channels ~= channel;
				channel.subscribeTo(this);
			}
		}

		if("channel" in message) {
			auto channel = daemon.getChannel(message["channel"][$-1]);
			channels ~= channel;
			channel.subscribeTo(this);
		}

		import std.algorithm;
		import std.range;

		Message*[] backMessages;

		if("last-message-id" in message) {
			auto lastMessageId = message["last-message-id"][$-1];
			foreach(channel; channels)
				backMessages ~= channel.messages;

			auto bm = sort!"a.timestamp < b.timestamp"(backMessages);

			backMessages = array(find!("a.id == b")(bm, lastMessageId));
			while(backMessages.length && backMessages[0].id == lastMessageId)
				backMessages = backMessages[1 .. $]; // the last message is the one they got

			//writeln("backed up from ", lastMessageId, " is");
			//foreach(msg; backMessages)
				//writeln(*msg);
		} else if("minimum-time" in message) {
			foreach(channel; channels)
				backMessages ~= channel.messages;

			auto bm = sort!"a.timestamp < b.timestamp"(backMessages);

			backMessages = array(find!("a.timestamp >= b")(bm, to!long(message["minimum-time"][$-1])));
		}

		if("close-time" in message)
			closeTime = to!long(message["close-time"][$-1]);

		// send the back messages immediately
		daemon.writeMessagesTo(backMessages, this, "backed-up");

//		if(closeTime > 0 && closeTime != long.max)
//			closeTime = getUtcTime() + closeTime; // FIXME: do i use this? Should I use this?
	}

	override void onDisconnect() {
		daemon.removeConnection(this);
	}

}

class DataConnection : RtudConnection {
	this(RealTimeUpdateDaemon daemon) {
		super(daemon);
	}

	override void handleMessage(string[][string] message) {
		string getStr(string key, string def) {
			if(key in message) {
				auto s = message[key][$ - 1];
				if(s.length)
					return s;
			}
			return def;
		}

		string operation =  getStr("operation", "post");

		Message* m = daemon.getMessage(getStr("id", null));
		switch(operation) {
			default: throw new Exception("unknown operation " ~ operation); break;
			case "delete":
				daemon.deleteMessage(m);
			break;
			case "edit":
			case "post":
				// we have to create the message and send it out
				m.type = getStr("type", "message");
				m.data = getStr("data", "");
				m.timestamp = to!long(getStr("timestamp", to!string(getUtcTime())));
				m.ttl = to!long(getStr("ttl", "1000"));
		}

		assert(m !is null);

		if("channels" in message)
		foreach(ch; message["channels"]) {
			auto channel = daemon.getChannel(ch);
			assert(channel !is null);
			channel.writeMessage(m, operation);
		}

		if("channel" in message) {
			auto channel = daemon.getChannel(message["channel"][$-1]);
			channel.writeMessage(m, operation);
		}
	}
}

struct Channel {
	string id;
	Message*[] messages;

	// a poor man's set...
	NotificationConnection[NotificationConnection] listeningConnections;


	RealTimeUpdateDaemon daemon;

	void writeMessage(Message* message, string operation) {
		messages ~= message;
		foreach(k, v; listeningConnections)
			daemon.writeMessagesTo([message], v, operation);
	}

	void subscribeTo(NotificationConnection c) {
		listeningConnections[c] = c;
	}
}


class RealTimeUpdateDaemon : NetworkManager {
	this() {
		super();
		setConnectionSpawner(7070, &createNotificationConnection);
		listen(7070);
		setConnectionSpawner(7071, &createDataConnection);
		listen(7071);
	}

	private Channel*[string] channels;
	private Message*[string] messages;

	Message* getMessage(string id) {
		if(id.length && id in messages)
			return messages[id];

		if(id.length == 0)
			id = to!string(getUtcTime());

		longerId:
		if(id in messages) {
			id ~= "-";
			goto longerId;
		}


		auto message = new Message;
		message.id = id;
		messages[id] = message;

		//writeln("NEW MESSAGE: ", *message);

		return message;
	}

	void deleteMessage(Message* m) {
		messages.remove(m.id);
		foreach(k, v; channels)
		foreach(i, msg; v.messages) {
			if(msg is m) {
				v.messages = v.messages[0 .. i] ~ v.messages[i + 1 .. $];
				break;
			}
		}
	}

	Channel* getChannel(string id) {
		if(id in channels)
			return channels[id];

		auto c = new Channel;
		c.daemon = this;
		c.id = id;
		channels[id] = c;
		return c;
	}

	void writeMessagesTo(Message*[] messages, NotificationConnection connection, string operation) {
		foreach(messageMain; messages) {
			if(messageMain.timestamp + messageMain.ttl < getUtcTime)
				deleteMessage(messageMain); // too old, kill it
			Message message = *messageMain;
			message.operation = operation;

			// this should never happen, but just in case
			replace(message.type, "\n", "");
			connection.write(":timestamp: " ~ to!string(message.timestamp) ~ "\n");
			connection.write(":ttl: " ~ to!string(message.ttl) ~ "\n");
			connection.write(":operation: " ~ message.operation ~ "\n");
			if(message.id.length)
				connection.write("id: " ~ message.id ~ "\n");
			connection.write("event: " ~ message.type ~ "\n");
			connection.write("data: " ~ replace(message.data, "\n", "\ndata: ") ~ "\n");
			connection.write("\n");
		}

		if(connection.closeTime <= 0) // FIXME: other times?
			if(connection.closeTime != 0 || messages.length)
				connection.disconnect(); // note this actually queues a disconnect, so we cool
	}

	void removeConnection(NotificationConnection connection) {
		foreach(channel; channels)
			channel.listeningConnections.remove(connection);
	}

	Connection createNotificationConnection() {
		return new NotificationConnection(this);
	}

	Connection createDataConnection() {
		return new DataConnection(this);
	}
}

void rtudMain() {
	auto netman = new RealTimeUpdateDaemon;

	bool proceed = true;

	while(proceed)
		try
			proceed = netman.proceed();
		catch(ConnectionException e) {
		writeln(e.toString());
			e.c.disconnectNow();
		}
		catch(Throwable e) {


		writeln(e.toString());
		}
}

version(standalone_rtud)
void main() {
	rtudMain();
}
