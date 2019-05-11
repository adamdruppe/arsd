///
module arsd.email;

import std.net.curl;
pragma(lib, "curl");

import std.base64;
import std.string;

import arsd.characterencodings;

// SEE ALSO: std.net.curl.SMTP

///
struct RelayInfo {
	string server; ///
	string username; ///
	string password; ///
}

///
struct MimeAttachment {
	string type; ///
	string filename; ///
	const(void)[] content; ///
	string id; ///
}

///
enum ToType {
	to,
	cc,
	bcc
}


/++
	For OUTGOING email


	To use:

	---
	auto message = new EmailMessage();
	message.to ~= "someuser@example.com";
	message.from = "youremail@example.com";
	message.subject = "My Subject";
	message.setTextBody("hi there");
	//message.toString(); // get string to send externally
	message.send(); // send via some relay
	// may also set replyTo, etc
	---
+/
class EmailMessage {
	///
	void setHeader(string name, string value) {
		headers ~= name ~ ": " ~ value;
	}

	string[] to;  ///
	string[] cc;  ///
	string[] bcc;  ///
	string from;  ///
	string replyTo;  ///
	string inReplyTo;  ///
	string textBody;
	string htmlBody;
	string subject;  ///

	string[] headers;

	private bool isMime = false;
	private bool isHtml = false;

	///
	void addRecipient(string name, string email, ToType how = ToType.to) {
		addRecipient(`"`~name~`" <`~email~`>`, how);
	}

	///
	void addRecipient(string who, ToType how = ToType.to) {
		final switch(how) {
			case ToType.to:
				to ~= who;
			break;
			case ToType.cc:
				cc ~= who;
			break;
			case ToType.bcc:
				bcc ~= who;
			break;
		}
	}

	///
	void setTextBody(string text) {
		textBody = text.strip;
	}
	/// automatically sets a text fallback if you haven't already
	void setHtmlBody()(string html) {
		isMime = true;
		isHtml = true;
		htmlBody = html;

		import arsd.htmltotext;
		if(textBody is null)
			textBody = htmlToText(html);
	}

	const(MimeAttachment)[] attachments;

	/++
		The filename is what is shown to the user, not the file on your sending computer. It should NOT have a path in it.

		---
			message.addAttachment("text/plain", "something.txt", std.file.read("/path/to/local/something.txt"));
		---
	+/
	void addAttachment(string mimeType, string filename, in void[] content, string id = null) {
		isMime = true;
		attachments ~= MimeAttachment(mimeType, filename, content, id);
	}

	/// in the html, use img src="cid:ID_GIVEN_HERE"
	void addInlineImage(string id, string mimeType, string filename, in void[] content) {
		assert(isHtml);
		isMime = true;
		inlineImages ~= MimeAttachment(mimeType, filename, content, id);
	}

	const(MimeAttachment)[] inlineImages;


	/* we should build out the mime thingy
		related
			mixed
			alternate
	*/

	/// Returns the MIME formatted email string, including encoded attachments
	override string toString() {
		assert(!isHtml || (isHtml && isMime));

		auto headers = this.headers;

		if(to.length)
			headers ~= "To: " ~ join(to, ", ");
		if(cc.length)
			headers ~= "Cc: " ~ join(cc, ", ");

		if(from.length)
			headers ~= "From: " ~ from;

		if(subject !is null)
			headers ~= "Subject: " ~ subject;
		if(replyTo !is null)
			headers ~= "Reply-To: " ~ replyTo;
		if(inReplyTo !is null)
			headers ~= "In-Reply-To: " ~ inReplyTo;

		if(isMime)
			headers ~= "MIME-Version: 1.0";

	/+
		if(inlineImages.length) {
			headers ~= "Content-Type: multipart/related; boundary=" ~ boundary;
			// so we put the alternative inside asthe first attachment with as seconary boundary
			// then we do the images
		} else
		if(attachments.length)
			headers ~= "Content-Type: multipart/mixed; boundary=" ~ boundary;
		else if(isHtml)
			headers ~= "Content-Type: multipart/alternative; boundary=" ~ boundary;
		else
			headers ~= "Content-Type: text/plain; charset=UTF-8";
	+/


		string msgContent;

		if(isMime) {
			MimeContainer top;

			{
				MimeContainer mimeMessage;
				if(isHtml) {
					auto alternative = new MimeContainer("multipart/alternative");
					alternative.stuff ~= new MimeContainer("text/plain; charset=UTF-8", textBody);
					alternative.stuff ~= new MimeContainer("text/html; charset=UTF-8", htmlBody);
					mimeMessage = alternative;
				} else {
					mimeMessage = new MimeContainer("text/plain; charset=UTF-8", textBody);
				}
				top = mimeMessage;
			}

			{
				MimeContainer mimeRelated;
				if(inlineImages.length) {
					mimeRelated = new MimeContainer("multipart/related");

					mimeRelated.stuff ~= top;
					top = mimeRelated;

					foreach(attachment; inlineImages) {
						auto mimeAttachment = new MimeContainer(attachment.type ~ "; name=\""~attachment.filename~"\"");
						mimeAttachment.headers ~= "Content-Transfer-Encoding: base64";
						mimeAttachment.headers ~= "Content-ID: <" ~ attachment.id ~ ">";
						mimeAttachment.content = Base64.encode(cast(const(ubyte)[]) attachment.content);

						mimeRelated.stuff ~= mimeAttachment;
					}
				}
			}

			{
				MimeContainer mimeMixed;
				if(attachments.length) {
					mimeMixed = new MimeContainer("multipart/mixed");

					mimeMixed.stuff ~= top;
					top = mimeMixed;

					foreach(attachment; attachments) {
						auto mimeAttachment = new MimeContainer(attachment.type);
						mimeAttachment.headers ~= "Content-Disposition: attachment; filename=\""~attachment.filename~"\"";
						mimeAttachment.headers ~= "Content-Transfer-Encoding: base64";
						if(attachment.id.length)
							mimeAttachment.headers ~= "Content-ID: <" ~ attachment.id ~ ">";

						mimeAttachment.content = Base64.encode(cast(const(ubyte)[]) attachment.content);

						mimeMixed.stuff ~= mimeAttachment;
					}
				}
			}

			headers ~= top.contentType;
			msgContent = top.toMimeString(true);
		} else {
			headers ~= "Content-Type: text/plain; charset=UTF-8";
			msgContent = textBody;
		}


		string msg;
		msg.reserve(htmlBody.length + textBody.length + 1024);

		foreach(header; headers)
			msg ~= header ~ "\r\n";
		if(msg.length) // has headers
			msg ~= "\r\n";

		msg ~= msgContent;

		return msg;
	}

	/// Sends via a given SMTP relay
	void send(RelayInfo mailServer = RelayInfo("smtp://localhost")) {
		auto smtp = SMTP(mailServer.server);

		smtp.verifyHost = false;
		smtp.verifyPeer = false;
		// smtp.verbose = true;
		if(mailServer.username.length)
			smtp.setAuthentication(mailServer.username, mailServer.password);
		const(char)[][] allRecipients = cast(const(char)[][]) (to ~ cc ~ bcc); // WTF cast
		smtp.mailTo(allRecipients);

		auto mailFrom = from;
		auto idx = mailFrom.indexOf("<");
		if(idx != -1)
			mailFrom = mailFrom[idx + 1 .. $];
		idx = mailFrom.indexOf(">");
		if(idx != -1)
			mailFrom = mailFrom[0 .. idx];

		smtp.mailFrom = mailFrom;
		smtp.message = this.toString();
		smtp.perform();
	}
}

///
void email(string to, string subject, string message, string from, RelayInfo mailServer = RelayInfo("smtp://localhost")) {
	auto msg = new EmailMessage();
	msg.from = from;
	msg.to = [to];
	msg.subject = subject;
	msg.textBody = message;
	msg.send(mailServer);
}

// private:

import std.conv;

/// for reading
class MimePart {
	string[] headers;
	immutable(ubyte)[] content;
	immutable(ubyte)[] encodedContent; // usually valid only for GPG, and will be cleared by creator; canonical form
	string textContent;
	MimePart[] stuff;

	string name;
	string charset;
	string type;
	string transferEncoding;
	string disposition;
	string id;
	string filename;
	// gpg signatures
	string gpgalg;
	string gpgproto;

	MimeAttachment toMimeAttachment() {
		MimeAttachment att;
		att.type = type;
		att.filename = filename;
		att.id = id;
		att.content = content;
		return att;
	}

	this(immutable(ubyte)[][] lines, string contentType = null) {
		string boundary;

		void parseContentType(string content) {
			//{ import std.stdio; writeln("c=[", content, "]"); }
			foreach(k, v; breakUpHeaderParts(content)) {
				//{ import std.stdio; writeln("  k=[", k, "]; v=[", v, "]"); }
				switch(k) {
					case "root":
						type = v;
					break;
					case "name":
						name = v;
					break;
					case "charset":
						charset = v;
					break;
					case "boundary":
						boundary = v;
					break;
					default:
					case "micalg":
						gpgalg = v;
					break;
					case "protocol":
						gpgproto = v;
					break;
				}
			}
		}

		if(contentType is null) {
			// read headers immediately...
			auto copyOfLines = lines;
			immutable(ubyte)[] currentHeader;

			void commitHeader() {
				if(currentHeader.length == 0)
					return;
				string h = decodeEncodedWord(cast(string) currentHeader);
				headers ~= h;
				currentHeader = null;

				auto idx = h.indexOf(":");
				if(idx != -1) {
					auto name = h[0 .. idx].strip.toLower;
					auto content = h[idx + 1 .. $].strip;

					switch(name) {
						case "content-type":
							parseContentType(content);
						break;
						case "content-transfer-encoding":
							transferEncoding = content.toLower;
						break;
						case "content-disposition":
							foreach(k, v; breakUpHeaderParts(content)) {
								switch(k) {
									case "root":
										disposition = v;
									break;
									case "filename":
										filename = v;
									break;
									default:
								}
							}
						break;
						case "content-id":
							id = content;
						break;
						default:
					}
				}
			}

			foreach(line; copyOfLines) {
				lines = lines[1 .. $];
				if(line.length == 0)
					break;

				if(line[0] == ' ' || line[0] == '\t')
					currentHeader ~= (cast(string) line).stripLeft();
				else {
					if(currentHeader.length) {
						commitHeader();
					}
					currentHeader = line;
				}
			}

			commitHeader();
		} else {
			parseContentType(contentType);
		}

		// if it is multipart, find the start boundary. we'll break it up and fill in stuff
		// otherwise, all the data that follows is just content

		if(boundary.length) {
			immutable(ubyte)[][] partLines;
			bool inPart;
			foreach(line; lines) {
				if(line.startsWith("--" ~ boundary)) {
					if(inPart)
						stuff ~= new MimePart(partLines);
					inPart = true;
					partLines = null;

					if(line == "--" ~ boundary ~ "--")
						break; // all done
				}

				if(inPart) {
					partLines ~= line;
				} else {
					content ~= line ~ '\n';
				}
			}
		} else {
			foreach(line; lines) {
				content ~= line;

				if(transferEncoding != "base64")
					content ~= '\n';
			}
		}

		// store encoded content for GPG (should be cleared by caller if necessary)
		encodedContent = content;

		// decode the content..
		switch(transferEncoding) {
			case "base64":
				content = Base64.decode(cast(string) content);
			break;
			case "quoted-printable":
				content = decodeQuotedPrintable(cast(string) content);
			break;
			default:
				// no change needed (I hope)
		}

		if(type.indexOf("text/") == 0) {
			if(charset.length == 0)
				charset = "latin1";
			textContent = convertToUtf8Lossy(content, charset);
		}
	}
}

string[string] breakUpHeaderParts(string headerContent) {
	string[string] ret;

	string currentName = "root";
	string currentContent;
	bool inQuote = false;
	bool gettingName = false;
	bool ignoringSpaces = false;
	foreach(char c; headerContent) {
		if(ignoringSpaces) {
			if(c == ' ')
				continue;
			else
				ignoringSpaces = false;
		}

		if(gettingName) {
			if(c == '=') {
				gettingName = false;
				continue;
			}
			currentName ~= c;
		}

		if(c == '"') {
			inQuote = !inQuote;
			continue;
		}

		if(!inQuote && c == ';') {
			ret[currentName] = currentContent;
			ignoringSpaces = true;
			currentName = null;
			currentContent = null;

			gettingName = true;
			continue;
		}

		if(!gettingName)
			currentContent ~= c;
	}

	if(currentName.length)
		ret[currentName] = currentContent;

	return ret;
}

// for writing
class MimeContainer {
	private static int sequence;

	immutable string _contentType;
	immutable string boundary;

	string[] headers; // NOT including content-type
	string content;
	MimeContainer[] stuff;

	this(string contentType, string content = null) {
		this._contentType = contentType;
		this.content = content;
		sequence++;
		if(_contentType.indexOf("multipart/") == 0)
			boundary = "0016e64be86203dd36047610926a" ~ to!string(sequence);
	}

	@property string contentType() {
		string ct = "Content-Type: "~_contentType;
		if(boundary.length)
			ct ~= "; boundary=" ~ boundary;
		return ct;
	}


	string toMimeString(bool isRoot = false) {
		string ret;

		if(!isRoot) {
			ret ~= contentType;
			foreach(header; headers) {
				ret ~= "\r\n";
				ret ~= header;
			}
			ret ~= "\r\n\r\n";
		}

		ret ~= content;

		foreach(idx, thing; stuff) {
			assert(boundary.length);
			ret ~= "\r\n--" ~ boundary ~ "\r\n";
			ret ~= thing.toMimeString(false);
		}

		if(boundary.length)
			ret ~= "\r\n--" ~ boundary ~ "--";

		return ret;
	}
}

import std.algorithm : startsWith;
///
class IncomingEmailMessage {
	///
	this(string[] lines) {
		auto lns = cast(immutable(ubyte)[][])lines;
		this(lns, false);
	}

	///
	this(ref immutable(ubyte)[][] mboxLines, bool asmbox=true) {

		enum ParseState {
			lookingForFrom,
			readingHeaders,
			readingBody
		}

		auto state = (asmbox ? ParseState.lookingForFrom : ParseState.readingHeaders);
		string contentType;

		bool isMultipart;
		bool isHtml;
		immutable(ubyte)[][] mimeLines;

		string charset = "latin-1";

		string contentTransferEncoding;

		string headerName;
		string headerContent;
		void commitHeader() {
			if(headerName is null)
				return;

			headerName = headerName.toLower();
			headerContent = headerContent.strip();

			headerContent = decodeEncodedWord(headerContent);

			if(headerName == "content-type") {
				contentType = headerContent;
				if(contentType.indexOf("multipart/") != -1)
					isMultipart = true;
				else if(contentType.indexOf("text/html") != -1)
					isHtml = true;

				auto charsetIdx = contentType.indexOf("charset=");
				if(charsetIdx != -1) {
					string cs = contentType[charsetIdx + "charset=".length .. $];
					if(cs.length && cs[0] == '\"')
						cs = cs[1 .. $];

					auto quoteIdx = cs.indexOf("\"");
					if(quoteIdx != -1)
						cs = cs[0 .. quoteIdx];
					auto semicolonIdx = cs.indexOf(";");
					if(semicolonIdx != -1)
						cs = cs[0 .. semicolonIdx];

					cs = cs.strip();
					if(cs.length)
						charset = cs.toLower();
				}
			} else if(headerName == "from") {
				this.from = headerContent;
			} else if(headerName == "to") {
				this.to = headerContent;
			} else if(headerName == "subject") {
				this.subject = headerContent;
			} else if(headerName == "content-transfer-encoding") {
				contentTransferEncoding = headerContent;
			}

			headers[headerName] = headerContent;
			headerName = null;
			headerContent = null;
		}

		lineLoop: while(mboxLines.length) {
			// this can needlessly convert headers too, but that won't harm anything since they are 7 bit anyway
			auto line = convertToUtf8Lossy(mboxLines[0], charset);
			auto origline = line;
			line = line.stripRight;

			final switch(state) {
				case ParseState.lookingForFrom:
					if(line.startsWith("From "))
						state = ParseState.readingHeaders;
				break;
				case ParseState.readingHeaders:
					if(line.length == 0) {
						commitHeader();
						state = ParseState.readingBody;
					} else {
						if(line[0] == ' ' || line[0] == '\t') {
							headerContent ~= " " ~ line.stripLeft();
						} else {
							commitHeader();

							auto idx = line.indexOf(":");
							if(idx == -1)
								headerName = line;
							else {
								headerName = line[0 .. idx];
								headerContent = line[idx + 1 .. $].stripLeft();
							}
						}
					}
				break;
				case ParseState.readingBody:
					if (asmbox) {
						if(line.startsWith("From ")) {
							break lineLoop; // we're at the beginning of the next messsage
						}
						if(line.startsWith(">>From") || line.startsWith(">From")) {
							line = line[1 .. $];
						}
					}

					if(isMultipart) {
						mimeLines ~= mboxLines[0];
					} else if(isHtml) {
						// html with no alternative and no attachments
						htmlMessageBody ~= line ~ "\n";
					} else {
						// plain text!
						// we want trailing spaces for "format=flowed", for example, so...
						line = origline;
						size_t epos = line.length;
						while (epos > 0) {
							char ch = line.ptr[epos-1];
							if (ch >= ' ' || ch == '\t') break;
							--epos;
						}
						line = line.ptr[0..epos];
						textMessageBody ~= line ~ "\n";
					}
				break;
			}

			mboxLines = mboxLines[1 .. $];
		}

		if(mimeLines.length) {
			auto part = new MimePart(mimeLines, contentType);
			deeperInTheMimeTree:
			switch(part.type) {
				case "text/html":
					htmlMessageBody = part.textContent;
				break;
				case "text/plain":
					textMessageBody = part.textContent;
				break;
				case "multipart/alternative":
					foreach(p; part.stuff) {
						if(p.type == "text/html")
							htmlMessageBody = p.textContent;
						else if(p.type == "text/plain")
							textMessageBody = p.textContent;
					}
				break;
				case "multipart/related":
					// the first one is the message itself
					// after that comes attachments that can be rendered inline
					if(part.stuff.length) {
						auto msg = part.stuff[0];
						foreach(thing; part.stuff[1 .. $]) {
							// FIXME: should this be special?
							attachments ~= thing.toMimeAttachment();
						}
						part = msg;
						goto deeperInTheMimeTree;
					}
				break;
				case "multipart/mixed":
					if(part.stuff.length) {
						auto msg = part.stuff[0];
						foreach(thing; part.stuff[1 .. $]) {
							attachments ~= thing.toMimeAttachment();
						}
						part = msg;
						goto deeperInTheMimeTree;
					}

					// FIXME: the more proper way is:
					// check the disposition
					// if none, concat it to make a text message body
					// if inline it is prolly an image to be concated in the other body
					// if attachment, it is an attachment
				break;
				case "multipart/signed":
					// FIXME: it would be cool to actually check the signature
					if (part.stuff.length) {
						auto msg = part.stuff[0];
						//{ import std.stdio; writeln("hdrs: ", part.stuff[0].headers); }
						gpgalg = part.gpgalg;
						gpgproto = part.gpgproto;
						gpgmime = part;
						foreach (thing; part.stuff[1 .. $]) {
							attachments ~= thing.toMimeAttachment();
						}
						part = msg;
						goto deeperInTheMimeTree;
					}
				break;
				default:
					// FIXME: correctly handle more
					if(part.stuff.length) {
						part = part.stuff[0];
						goto deeperInTheMimeTree;
					}
			}
		} else {
			switch(contentTransferEncoding) {
				case "quoted-printable":
					if(textMessageBody.length)
						textMessageBody = convertToUtf8Lossy(decodeQuotedPrintable(textMessageBody), charset);
					if(htmlMessageBody.length)
						htmlMessageBody = convertToUtf8Lossy(decodeQuotedPrintable(htmlMessageBody), charset);
				break;
				case "base64":
					if(textMessageBody.length) {
						// alas, phobos' base64 decoder cannot accept ranges, so we have to allocate here
						char[] mmb;
						mmb.reserve(textMessageBody.length);
						foreach (char ch; textMessageBody) if (ch > ' ' && ch < 127) mmb ~= ch;
						textMessageBody = convertToUtf8Lossy(Base64.decode(mmb), charset);
					}
					if(htmlMessageBody.length) {
						// alas, phobos' base64 decoder cannot accept ranges, so we have to allocate here
						char[] mmb;
						mmb.reserve(htmlMessageBody.length);
						foreach (char ch; htmlMessageBody) if (ch > ' ' && ch < 127) mmb ~= ch;
						htmlMessageBody = convertToUtf8Lossy(Base64.decode(mmb), charset);
					}

				break;
				default:
					// nothing needed
			}
		}

		if(htmlMessageBody.length > 0 && textMessageBody.length == 0) {
			import arsd.htmltotext;
			textMessageBody = htmlToText(htmlMessageBody);
			textAutoConverted = true;
		}
	}

	///
	@property bool hasGPGSignature () const nothrow @trusted @nogc {
		MimePart mime = cast(MimePart)gpgmime; // sorry
		if (mime is null) return false;
		if (mime.type != "multipart/signed") return false;
		if (mime.stuff.length != 2) return false;
		if (mime.stuff[1].type != "application/pgp-signature") return false;
		if (mime.stuff[0].type.length <= 5 && mime.stuff[0].type[0..5] != "text/") return false;
		return true;
	}

	///
	ubyte[] extractGPGData () const nothrow @trusted {
		if (!hasGPGSignature) return null;
		MimePart mime = cast(MimePart)gpgmime; // sorry
		char[] res;
		res.reserve(mime.stuff[0].encodedContent.length); // more, actually
		foreach (string s; mime.stuff[0].headers[1..$]) {
			while (s.length && s[$-1] <= ' ') s = s[0..$-1];
			if (s.length == 0) return null; // wtf?! empty headers?
			res ~= s;
			res ~= "\r\n";
		}
		res ~= "\r\n";
		// extract content (see rfc3156)
		size_t pos = 0;
		auto ctt = mime.stuff[0].encodedContent;
		// last CR/LF is a part of mime signature, actually, so remove it
		if (ctt.length && ctt[$-1] == '\n') {
			ctt = ctt[0..$-1];
			if (ctt.length && ctt[$-1] == '\r') ctt = ctt[0..$-1];
		}
		while (pos < ctt.length) {
			auto epos = pos;
			while (epos < ctt.length && ctt.ptr[epos] != '\n') ++epos;
			auto xpos = epos;
			while (xpos > pos && ctt.ptr[xpos-1] <= ' ') --xpos; // according to rfc
			res ~= ctt[pos..xpos].dup;
			res ~= "\r\n"; // according to rfc
			pos = epos+1;
		}
		return cast(ubyte[])res;
	}

	///
	immutable(ubyte)[] extractGPGSignature () const nothrow @safe @nogc {
		if (!hasGPGSignature) return null;
		return gpgmime.stuff[1].content;
	}

	string[string] headers; ///

	string subject; ///

	string htmlMessageBody; ///
	string textMessageBody; ///

	string from; ///
	string to; ///

	bool textAutoConverted; ///

	MimeAttachment[] attachments; ///

	// gpg signature fields
	string gpgalg; ///
	string gpgproto; ///
	MimePart gpgmime; ///

	string fromEmailAddress() {
		auto i = from.indexOf("<");
		if(i == -1)
			return from;
		auto e = from.indexOf(">");
		return from[i + 1 .. e];
	}

	string toEmailAddress() {
		auto i = to.indexOf("<");
		if(i == -1)
			return to;
		auto e = to.indexOf(">");
		return to[i + 1 .. e];
	}
}

struct MboxMessages {
	immutable(ubyte)[][] linesRemaining;

	this(immutable(ubyte)[] data) {
		linesRemaining = splitLinesWithoutDecoding(data);
		popFront();
	}

	IncomingEmailMessage currentFront;

	IncomingEmailMessage front() {
		return currentFront;
	}

	bool empty() {
		return currentFront is null;
	}

	void popFront() {
		if(linesRemaining.length)
			currentFront = new IncomingEmailMessage(linesRemaining);
		else
			currentFront = null;
	}
}

///
MboxMessages processMboxData(immutable(ubyte)[] data) {
	return MboxMessages(data);
}

immutable(ubyte)[][] splitLinesWithoutDecoding(immutable(ubyte)[] data) {
	immutable(ubyte)[][] ret;

	size_t starting = 0;
	bool justSaw13 = false;
	foreach(idx, b; data) {
		if(b == 13)
			justSaw13 = true;

		if(b == 10) {
			auto use = idx;
			if(justSaw13)
				use--;

			ret ~= data[starting .. use];
			starting = idx + 1;
		}

		if(b != 13)
			justSaw13 = false;
	}

	if(starting < data.length)
		ret ~= data[starting .. $];

	return ret;
}

string decodeEncodedWord(string data) {
	string originalData = data;

	auto delimiter = data.indexOf("=?");
	if(delimiter == -1)
		return data;

	string ret;

	while(delimiter != -1) {
		ret ~= data[0 .. delimiter];
		data = data[delimiter + 2 .. $];

		string charset;
		string encoding;
		string encodedText;

		// FIXME: the insane things should probably throw an
		// exception that keeps a copy of orignal data for use later

		auto questionMark = data.indexOf("?");
		if(questionMark == -1) return originalData; // not sane

		charset = data[0 .. questionMark];
		data = data[questionMark + 1 .. $];

		questionMark = data.indexOf("?");
		if(questionMark == -1) return originalData; // not sane

		encoding = data[0 .. questionMark];
		data = data[questionMark + 1 .. $];

		questionMark = data.indexOf("?=");
		if(questionMark == -1) return originalData; // not sane

		encodedText = data[0 .. questionMark];
		data = data[questionMark + 2 .. $];

		delimiter = data.indexOf("=?");
		if (delimiter == 1 && data[0] == ' ') {
			// a single space between encoded words must be ignored because it is
			// used to separate multiple encoded words (RFC2047 says CRLF SPACE but a most clients
			// just use a space)
			data = data[1..$];
			delimiter = 0;
		}

		immutable(ubyte)[] decodedText;
		if(encoding == "Q" || encoding == "q")
			decodedText = decodeQuotedPrintable(encodedText);
		else if(encoding == "B" || encoding == "b")
			decodedText = cast(typeof(decodedText)) Base64.decode(encodedText);
		else
			return originalData; // wtf

		ret ~= convertToUtf8Lossy(decodedText, charset);
	}

	ret ~= data; // keep the rest since there could be trailing stuff

	return ret;
}

immutable(ubyte)[] decodeQuotedPrintable(string text) {
	immutable(ubyte)[] ret;

	int state = 0;
	ubyte hexByte;
	foreach(b; cast(immutable(ubyte)[]) text) {
		switch(state) {
			case 0:
				if(b == '=') {
					state++;
					hexByte = 0;
				} else if (b == '_') { // RFC2047 4.2.2: a _ may be used to represent a space
					ret ~= ' ';
				} else
					ret ~= b;
			break;
			case 1:
				if(b == '\n') {
					state = 0;
					continue;
				}
				goto case;
			case 2:
				int value;
				if(b >= '0' && b <= '9')
					value = b - '0';
				else if(b >= 'A' && b <= 'F')
					value = b - 'A' + 10;
				else if(b >= 'a' && b <= 'f')
					value = b - 'a' + 10;
				if(state == 1) {
					hexByte |= value << 4;
					state++;
				} else {
					hexByte |= value;
					ret ~= hexByte;
					state = 0;
				}
			break;
			default: assert(0);
		}
	}

	return ret;
}

/+
void main() {
	import std.file;
	import std.stdio;

	auto data = cast(immutable(ubyte)[]) std.file.read("/home/me/test_email_data");
	foreach(message; processMboxData(data)) {
		writeln(message.subject);
		writeln(message.textMessageBody);
		writeln("**************** END MESSSAGE **************");
	}
}
+/
