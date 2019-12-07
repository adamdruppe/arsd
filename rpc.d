/// I never finished this. The idea is to use CT reflection to make calling another process feel as simple as calling in-process objects. Will come eventually but no promises.
module arsd.rpc;

/*
	FIXME:
		1) integrate with arsd.eventloop
		2) make it easy to use with other processes; pipe to a process and talk to it that way. perhaps with shared memory too?
		3) extend the serialization capabilities
*/

///+ //example usage
interface ExampleNetworkFunctions {
	string sayHello(string name);
	int add(int a, int b);
	S2 structTest(S1);
	void die();
}
 
// the server must implement the interface
class ExampleServer : ExampleNetworkFunctions {
	override string sayHello(string name) {
		return "Hello, " ~ name;
	}

	override int add(int a, int b) {
		return a+b;
	}

	override S2 structTest(S1 a) {
		return S2(a.name, a.number);
	}

	override void die() {
		throw new Exception("death requested");
	}

	mixin NetworkServer!ExampleNetworkFunctions;
}

struct S1 {
	int number;
	string name;
}

struct S2 {
	string name;
	int number;
}

import std.stdio;
void main(string[] args) {
	if(args.length > 1) {
		auto client = makeNetworkClient!ExampleNetworkFunctions("localhost", 5005);
		// these work like the interface above, but instead of returning the value,
		// they take callbacks for success (where the arg is the retval)
		// and failure (the arg is the exception)
		client.sayHello("whoa", (a) { writeln(a); }, null);
		client.add(1,2, (a) { writeln(a); }, null);
		client.add(10,20, (a) { writeln(a); }, null);
		client.structTest(S1(20, "cool!"), (a) { writeln(a.name, " -- ", a.number); }, null);
		client.die(delegate () { writeln("shouldn't happen"); }, delegate(a) { writeln(a); });
		client.eventLoop();

		/*
		auto client = makeNetworkClient!(ExampleNetworkFunctions, false)("localhost", 5005);
		writeln(client.sayHello("whoa"));
		writeln(client.add(1, 2));
		client.die();
		writeln(client.add(1, 2));
		*/
	} else {
		auto server = new ExampleServer(5005);
		server.eventLoop();
	}
}
//+/

mixin template NetworkServer(Interface) {
	import std.socket;
	private Socket socket;
	public this(ushort port) {
		socket = new TcpSocket();
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.bind(new InternetAddress(port));
		socket.listen(16);
	}

	final public void eventLoop() {
		auto check = new SocketSet();
		Socket[] connections;
		connections.reserve(16);
		ubyte[4096] buffer;

		while(true) {
			check.reset();
			check.add(socket);
			foreach(connection; connections) {
				check.add(connection);
			}

			if(Socket.select(check, null, null)) {
				if(check.isSet(socket)) {
					connections ~= socket.accept();
				}

				foreach(connection; connections) {
					if(check.isSet(connection)) {
						auto gotNum = connection.receive(buffer);
						if(gotNum == 0) {
							// connection is closed, we could remove it from the list
						} else {
							auto got = buffer[0 .. gotNum];
							another:
							int length, functionNumber, sequenceNumber;
							got = deserializeInto(got, length);
							got = deserializeInto(got, functionNumber);
							got = deserializeInto(got, sequenceNumber);

							//writeln("got ", sequenceNumber, " calling ", functionNumber);

							auto remaining = got[length .. $];
							got = got[0 .. length];
							import std.conv;
							assert(length == got.length, to!string(length) ~ " != " ~ to!string(got.length)); // FIXME: what if it doesn't all come at once?
							callByNumber(functionNumber, sequenceNumber, got, connection);

							if(remaining.length) {
								got = remaining;
								goto another;
							}
						}
					}
				}
			}
		}
	}

	final private void callByNumber(int functionNumber, int sequenceNumber, const(ubyte)[] buffer, Socket connection) {
		ubyte[4096] sendBuffer;
		int length = 12;
		// length, sequence, success
		serialize(sendBuffer[4 .. 8], sequenceNumber);
		string callCode() {
			import std.conv;
			import std.traits;
			string code;
			foreach(memIdx, member; __traits(allMembers, Interface)) {
				code ~= "\t\tcase " ~ to!string(memIdx + 1) ~ ":\n";
				alias mem = PassThrough!(__traits(getMember, Interface, member));
				// we need to deserialize the arguments, call the function, and send back the response (if there is one)
				string argsString;
				foreach(i, arg; ParameterTypeTuple!mem) {
					if(i)
						argsString ~= ", ";
					auto istr = to!string(i);
					code ~= "\t\t\t" ~ arg.stringof ~ " arg" ~ istr ~ ";\n";
					code ~= "\t\t\tbuffer = deserializeInto(buffer, arg" ~ istr ~ ");\n";

					argsString ~= "arg" ~ istr;
				}

				// the call
				static if(is(ReturnType!mem == void)) {
					code ~= "\n\t\t\t" ~ member ~ "(" ~ argsString ~ ");\n";
				} else {
					// call and return answer
					code ~= "\n\t\t\tauto ret = " ~ member ~ "(" ~ argsString ~ ");\n";

					code ~= "\t\t\tserialize(sendBuffer[8 .. 12], cast(int) 1);\n"; // yes success
					code ~= "\t\t\tauto serialized = serialize(sendBuffer[12 .. $], ret);\n";
					code ~= "\t\t\tserialize(sendBuffer[0 .. 4], cast(int) serialized.length);\n";
					code ~= "\t\t\tlength += serialized.length;\n";
				}
				code ~= "\t\tbreak;\n";
			}
			return code;
		}

		try {
			switch(functionNumber) {
				default: assert(0, "unknown function");
				//pragma(msg, callCode());
				mixin(callCode());
			}
		} catch(Throwable t) {
			//writeln("thrown: ", t);
			serialize(sendBuffer[8 .. 12], cast(int) 0); // no success

			auto place = sendBuffer[12 .. $];
			int l;
			auto s = serialize(place, t.msg);
			place = place[s.length .. $];
			l += s.length;
			s = serialize(place, t.file);
			place = place[s.length .. $];
			l += s.length;
			s = serialize(place, t.line);
			place = place[s.length .. $];
			l += s.length;

			serialize(sendBuffer[0 .. 4], l);
			length += l;
		}

		if(length != 12) // if there is a response...
			connection.send(sendBuffer[0 .. length]);
	}
}

template PassThrough(alias a) {
	alias PassThrough = a;
}

// general FIXME: what if we run out of buffer space?

// returns the part of the buffer that was actually used
final public ubyte[] serialize(T)(ubyte[] buffer, in T s) {
	auto original = buffer;
	size_t totalLength = 0;
	import std.traits;
	static if(isArray!T) {
		/* length */ {
			auto used = serialize(buffer, cast(int)  s.length);
			totalLength += used.length;
			buffer = buffer[used.length .. $];
		}
		foreach(i; s) {
			auto used = serialize(buffer, i);
			totalLength += used.length;
			buffer = buffer[used.length .. $];
		}
	} else static if(isPointer!T) {
		static assert(0, "no pointers allowed");
	} else static if(!hasIndirections!T) {
		// covers int, float, char, etc. most the builtins
		import std.string;
		assert(buffer.length >= T.sizeof, format("%s won't fit in %s buffer", T.stringof, buffer.length));
		buffer[0 .. T.sizeof] = (cast(ubyte*)&s)[0 .. T.sizeof];
		totalLength += T.sizeof;
		buffer = buffer[T.sizeof .. $];
	} else {
		// structs, classes, etc.
		foreach(i, t; s.tupleof) {
			auto used = serialize(buffer, t);
			totalLength += used.length;
			buffer = buffer[used.length .. $];
		}
	}

	return original[0 .. totalLength];
}

// returns the remaining part of the buffer
final public inout(ubyte)[] deserializeInto(T)(inout(ubyte)[] buffer, ref T s) {
	import std.traits;

	static if(isArray!T) {
		size_t length;
		buffer = deserializeInto(buffer, length);
		s.length = length;
		foreach(i; 0 .. length)
			buffer = deserializeInto(buffer, s[i]);
	} else static if(isPointer!T) {
		static assert(0, "no pointers allowed");
	} else static if(!hasIndirections!T) {
		// covers int, float, char, etc. most the builtins
		(cast(ubyte*)(&s))[0 .. T.sizeof] = buffer[0 .. T.sizeof];
		buffer = buffer[T.sizeof .. $];
	} else {
		// structs, classes, etc.
		foreach(i, t; s.tupleof) {
			buffer = deserializeInto(buffer, s.tupleof[i]);
		}
	}

	return buffer;
}

mixin template NetworkClient(Interface, bool useAsync = true) {
	private static string createClass() {
		// this doesn't actually inherit from the interface because
		// the return value needs to be handled async
		string code;// = `final class Class /*: ` ~ Interface.stringof ~ `*/ {`;
		code ~= "\n\timport std.socket;";
		code ~= "\n\tprivate Socket socket;";
		if(useAsync) {
			code ~= "\n\tprivate void delegate(const(ubyte)[] buffer)[uint] onSuccesses;";
			code ~= "\n\tprivate void delegate(const(ubyte)[] buffer)[uint] onErrors;";
		}
		code ~= "\n\tprivate uint lastSequenceNumber;";
		code ~= q{
	private this(string host, ushort port) {
		this.socket = new TcpSocket();
		this.socket.connect(new InternetAddress(host, port));
	}
	};

		if(useAsync)
		code ~= q{
	final public void eventLoop() {
		ubyte[4096] buffer;
		bool open = true;

		do {
			auto gotNum = socket.receive(buffer);
			if(gotNum == 0) {
				open = false;
				break;
			}
			while(gotNum < 9) {
				auto g2 = socket.receive(buffer[gotNum .. $]);
				if(g2 == 0) {
					open = false;
					break;
				}
				gotNum += g2;
			}

			auto got = buffer[0 .. gotNum];
			another:
			uint length, seq;
			uint success;
			got = deserializeInto(got, length);
			got = deserializeInto(got, seq);
			got = deserializeInto(got, success);
			auto more = got[length .. $];

			if(got.length >= length) {
				if(success) {
					auto s = (seq in onSuccesses);
					if(s !is null && *s !is null)
						(*s)(got);
				} else {
					auto s = (seq in onErrors);
					if(s !is null && *s !is null)
						(*s)(got);
				}
			}

			if(more.length) {
				got = more;
				goto another;
			}
		} while(open);
	}
	};
		code ~= "\n\tpublic:\n";

		foreach(memIdx, member; __traits(allMembers, Interface)) {
			import std.traits;
			alias mem = PassThrough!(__traits(getMember, Interface, member));
			string type;
			if(useAsync)
				type = "void";
			else {
				static if(is(ReturnType!mem == void))
					type = "void";
				else
					type = (ReturnType!mem).stringof;
			}
			code ~= "\t\tfinal "~type~" " ~ member ~ "(";
			bool hadArgument = false;
			import std.conv;
			// arguments
			foreach(i, arg; ParameterTypeTuple!mem) {
				if(hadArgument)
					code ~= ", ";
				// FIXME: this is one place the arg can get unknown if we don't have all the imports
				code ~= arg.stringof ~ " arg" ~ to!string(i);
				hadArgument = true;
			}

			if(useAsync) {
				if(hadArgument)
					code ~= ", ";

				static if(is(ReturnType!mem == void))
					code ~= "void delegate() onSuccess";
				else
					code ~= "void delegate("~(ReturnType!mem).stringof~") onSuccess";
				code ~= ", ";
				code ~= "void delegate(Throwable) onError";
			}
			code ~= ") {\n";
			code ~= "auto seq = ++lastSequenceNumber;";
		if(useAsync)
		code ~= q{
			#line 252
			onSuccesses[seq] = (const(ubyte)[] buffer) {
				onSuccesses.remove(seq);
				onErrors.remove(seq);

				import std.traits;

				static if(is(ParameterTypeTuple!(typeof(onSuccess)) == void)) {
					if(onSuccess !is null)
						onSuccess();
				} else {
					ParameterTypeTuple!(typeof(onSuccess)) args;
					foreach(i, arg; args)
						buffer = deserializeInto(buffer, args[i]);
					if(onSuccess !is null)
						onSuccess(args);
				}
			};
			onErrors[seq] = (const(ubyte)[] buffer) {
				onSuccesses.remove(seq);
				onErrors.remove(seq);
				auto t = new Throwable("");
				buffer = deserializeInto(buffer, t.msg);
				buffer = deserializeInto(buffer, t.file);
				buffer = deserializeInto(buffer, t.line);

				if(onError !is null)
					onError(t);
			};
		};

		code ~= q{
			#line 283
			ubyte[4096] bufferBase;
			auto buffer = bufferBase[12 .. $]; // leaving room for size, func number, and seq number
			ubyte[] serialized;
			int used;
		};
			// preparing the request
			foreach(i, arg; ParameterTypeTuple!mem) {
				code ~= "\t\t\tserialized = serialize(buffer, arg" ~ to!string(i) ~ ");\n";
				code ~= "\t\t\tused += serialized.length;\n";
				code ~= "\t\t\tbuffer = buffer[serialized.length .. $];\n";
			}

			code ~= "\t\t\tserialize(bufferBase[0 .. 4], used);\n";
			code ~= "\t\t\tserialize(bufferBase[4 .. 8], " ~ to!string(memIdx + 1) ~ ");\n";
			code ~= "\t\t\tserialize(bufferBase[8 .. 12], seq);\n";

			// FIXME: what if it doesn't all send at once?
			code ~= "\t\t\tsocket.send(bufferBase[0 .. 12 + used]);\n";
			//code ~= `writeln("sending ", bufferBase[0 .. 12 + used]);`;

		if(!useAsync)
		code ~= q{
			ubyte[4096] dbuffer;
			bool open = true;
			static if(is(typeof(return) == void)) {

			} else
				typeof(return) returned;

			auto gotNum = socket.receive(dbuffer);
			if(gotNum == 0) {
				open = false;
				throw new Exception("connection closed");
			}
			while(gotNum < 9) {
				auto g2 = socket.receive(dbuffer[gotNum .. $]);
				if(g2 == 0) {
					open = false;
					break;
				}
				gotNum += g2;
			}

			auto got = dbuffer[0 .. gotNum];
			another:
			uint length;
			uint success;
			got = deserializeInto(got, length);
			got = deserializeInto(got, seq);
			got = deserializeInto(got, success);
			auto more = got[length .. $];

			if(got.length >= length) {
				if(success) {
					/*
					auto s = (seq in onSuccesses);
					if(s !is null && *s !is null)
						(*s)(got);
					*/
					static if(is(typeof(return) == void)) {
					} else {
						got = deserializeInto(got, returned);
					}
				} else {
					/*
					auto s = (seq in onErrors);
					if(s !is null && *s !is null)
						(*s)(got);
					*/
					auto t = new Throwable("");
					got = deserializeInto(got, t.msg);
					got = deserializeInto(got, t.file);
					got = deserializeInto(got, t.line);
					throw t;
				}
			}

			if(more.length) {
				got = more;
				goto another;
			}
			static if(is(typeof(return) == void)) {

			} else
				return returned;
		};

			code ~= "}\n";
			code ~= "\n";
		}
		//code ~= `}`;
		return code;
	}

	//pragma(msg, createClass()); // for debugging help
	mixin(createClass());
}

auto makeNetworkClient(Interface, bool useAsync = true)(string host, ushort port) {
	class Thing {
		mixin NetworkClient!(Interface, useAsync);
	}

	return new Thing(host, port);
}

// the protocol is:
/*

client connects
	ulong interface hash

handshake complete

messages:

	uint messageLength
	uint sequence number
	ushort function number, 0 is reserved for interface check
	serialized arguments....



server responds with answers:

	uint messageLength
	uint re: sequence number
	ubyte, 1 == success, 0 == error
	serialized return value

*/
