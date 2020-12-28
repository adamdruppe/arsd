/++
	 A bare-bones, dead simple incoming SMTP server with zero outbound mail support. Intended for applications that want to process inbound email on a VM or something.


	 $(H2 Alternatives)

	 You can also run a real email server and process messages as they are delivered with a biff notification or get them from imap or something too.

	 History:
	 	Written December 26, 2020, in a little over one hour. Don't expect much from it!
+/
module arsd.mailserver;

import arsd.fibersocket;
import arsd.email;

///
struct SmtpServerConfig {
	//string iface = null;
	ushort port = 25;
	string hostname;
}

///
void serveSmtp(FiberManager fm, SmtpServerConfig config, void delegate(string[] recipients, IncomingEmailMessage) handler) {
	fm.listenTcp4(config.port, (Socket socket) {
		ubyte[512] buffer;
		ubyte[] at;
		const(ubyte)[] readLine() {
			top:
			int index = -1;
			foreach(idx, b; at) {
				if(b == 10) {
					index = cast(int) idx;
					break;
				}
			}
			if(index != -1) {
				auto got = at[0 .. index];
				at = at[index + 1 .. $];
				if(got.length) {
					if(got[$-1] == '\n')
						got = got[0 .. $-1];
					if(got[$-1] == '\r')
						got = got[0 .. $-1];
				}
				return got;
			}
			if(at.ptr is buffer.ptr && at.length < buffer.length) {
				auto got = socket.receive(buffer[at.length .. $]);
				if(got < 0) {
					socket.close();
					return null;
				} if(got == 0) {
					socket.close();
					return null;
				} else {
					at = buffer[0 .. at.length + got];
					goto top;
				}
			} else {
				// no space
				if(at.ptr is buffer.ptr)
					at = at.dup;

				auto got = socket.receive(buffer[]);
				if(got <= 0) {
					socket.close();
					return null;
				} else {
					at ~= buffer[0 .. got];
					goto top;
				}
			}

			assert(0);
		}

		socket.sendAll("220 " ~ config.hostname ~ " SMTP arsd_mailserver\r\n"); // ESMTP?

		immutable(ubyte)[][] msgLines;
		string[] recipients;

		loop: while(socket.isAlive()) {
			auto line = readLine();
			if(line is null) {
				socket.close();
				break;
			}

			if(line.length < 4) {
				socket.sendAll("500 Unknown command");
				continue;
			}

			switch(cast(string) line[0 .. 4]) {
				case "HELO":
					socket.sendAll("250 " ~ config.hostname ~ " Hello, good to see you\r\n");
				break;
				case "EHLO":
					goto default; // FIXME
				case "MAIL":
					// MAIL FROM:<email address>
					// 501 5.1.7 Syntax error in mailbox address "me@a?example.com.arsdnet.net" (non-printable character)

					if(line.length < 11 || line[0 .. 10] != "MAIL FROM:") {
						socket.sendAll("501 Syntax error");
						continue;
					}

					line = line[10 .. $];
					if(line[0] == '<') {
						if(line[$-1] != '>') {
							socket.sendAll("501 Syntax error");
							continue;
						}

						line = line[1 .. $-1];
					}

					string currentDate; // FIXME
					msgLines ~= cast(immutable(ubyte)[]) ("From " ~ cast(string) line ~ "  " ~ currentDate);
					msgLines ~= cast(immutable(ubyte)[]) ("Received: from " ~ socket.remoteAddress.toString);

					socket.sendAll("250 OK\r\n");
				break;
				case "RCPT":
					// RCPT TO:<...>

					if(line.length < 9 || line[0 .. 8] != "RCPT TO:") {
						socket.sendAll("501 Syntax error");
						continue;
					}

					line = line[8 .. $];
					if(line[0] == '<') {
						if(line[$-1] != '>') {
							socket.sendAll("501 Syntax error");
							continue;
						}

						line = line[1 .. $-1];
					}

					recipients ~= (cast(char[]) line).idup;

					socket.sendAll("250 OK\r\n");
				break;
				case "DATA":
					socket.sendAll("354 Enter mail, end with . on line by itself\r\n");

					more_lines:
					line = readLine();

					if(line == ".") {
						handler(recipients, new IncomingEmailMessage(msgLines));
						socket.sendAll("250 OK\r\n");
					} else if(line is null) {
						socket.close();
						break loop;
					} else {
						msgLines ~= line.idup;
						goto more_lines;
					}
				break;
				case "QUIT":
					socket.sendAll("221 Bye\r\n");
					socket.close();
				break;
				default:
					socket.sendAll("500 5.5.1 Command unrecognized\r\n");
			}
		}
	});
}

version(Demo)
void main() {
	auto fm = new FiberManager;

	fm.serveSmtp(SmtpServerConfig(9025), (string[] recipients, IncomingEmailMessage iem) {
		import std.stdio;
		writeln(recipients);
		writeln(iem.subject);
		writeln(iem.textMessageBody);
	});

	fm.run;
}
