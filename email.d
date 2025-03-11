/++
	Create MIME emails with things like HTML, attachments, and send with convenience wrappers around std.net.curl's SMTP function, or read email from an mbox file.

	For preparing and sending outgoing email, see [EmailMessage]. For processing incoming email or opening .eml files, mbox files, etc., see [IncomingEmailMessage].

	History:
		Originally released as open source on August 11, 2012. The last-modified date of its predecessor file was January 2011.

		Many of the public string members were overhauled on May 13, 2024. Compatibility methods are provided so your code will hopefully still work, but this also results in some stricter adherence to email encoding rules, so you should retest if you update after then.

	Future_Directions:
		I might merge `IncomingEmailMessage` and `EmailMessage` some day, it seems silly to have them completely separate like this.
+/
module arsd.email;

import std.net.curl;

import std.base64;
import std.string;
import std.range;
import std.utf;
import std.array;
import std.algorithm.iteration;

import arsd.characterencodings;

public import arsd.core : FilePath;

//         import std.uuid;
// smtpMessageBoundary = randomUUID().toString();

// SEE ALSO: std.net.curl.SMTP

/++
	Credentials for a SMTP relay, as passed to [std.net.curl.SMTP].
+/
struct RelayInfo {
	/++
		Should be as a url, such as `smtp://example.com` or `smtps://example.com`. You normally want smtp:// - even if you want TLS encryption, smtp uses STARTTLS so it gets that. smtps will only work if the server supports tls from the start, which is not always the case.
	+/
	string server;
	string username; ///
	string password; ///
}

/++
	Representation of an email attachment.
+/
struct MimeAttachment {
	string type; /// e.g. `text/plain`
	string filename; ///
	const(ubyte)[] content; ///
	string id; ///
}

///
enum ToType {
	to,
	cc,
	bcc
}

/++
	Structured representation of email users, including the name and email address as separate components.

	`EmailRecipient` represents a single user, and `RecipientList` represents multiple users. A "recipient" may also be a from or reply to address.


	`RecipientList` is a wrapper over `EmailRecipient[]` that provides overloads that take string arguments, for compatibility for users of previous versions of the `arsd.email` api. It should generally work as you expect if you just pretend it is a normal array though (and if it doesn't, you can get the internal array via the `recipients` member.)

	History:
		Added May 13, 2024 (dub v12.0) to replace the old plain, public strings and arrays of strings.
+/
struct EmailRecipient {
	/++
		The email user's name. It should not have quotes or any other encoding.

		For example, `Adam D. Ruppe`.
	+/
	string name;
	/++
		The email address. It should not have brackets or any other encoding.

		For example, `destructionator@gmail.com`.
	+/
	string address;

	/++
		Returns a string representing this email address, in a format suitable for inclusion in a message about to be saved or transmitted.

		In many cases, this is easy to read for people too, but not in all cases.
	+/
	string toProtocolString(string linesep = "\r\n") {
		if(name.length)
			return "\"" ~ encodeEmailHeaderContentForTransmit(name, linesep) ~ "\" <" ~ address ~ ">";
		return address;
	}

	/++
		Returns a string representing this email address, in a format suitable for being read by people. This is not necessarily reversible.
	+/
	string toReadableString() {
		if(name.length)
			return "\"" ~ name ~ "\" <" ~ address ~ ">";
		return address;
	}

	/++
		Construct an `EmailRecipient` either from a name and address (preferred!) or from an encoded string as found in an email header.

		Examples:

		`EmailRecipient("Adam D. Ruppe", "destructionator@gmail.com")` or `EmailRecipient(`"Adam D. Ruppe" <destructionator@gmail.com>`);
	+/
	this(string name, string address) {
		this.name = name;
		this.address = address;
	}

	/// ditto
	this(string str) {
		this = str;
	}

	/++
		Provided for compatibility for users of old versions of `arsd.email` - does implicit conversion from `EmailRecipient` to a plain string (in protocol format), as was present in previous versions of the api.
	+/
	alias toProtocolString this;

	/// ditto
	void opAssign(string str) {
		auto idx = str.indexOf("<");
		if(idx == -1) {
			name = null;
			address = str;
		} else {
			name = decodeEncodedWord(unquote(str[0 .. idx].strip));
			address = str[idx + 1 .. $ - 1];
		}

	}
}

/// ditto
struct RecipientList {
	EmailRecipient[] recipients;

	void opAssign(string[] strings) {
		recipients = null;
		foreach(s; strings)
			recipients ~= EmailRecipient(s);
	}
	void opAssign(EmailRecipient[] recpts) {
		this.recipients = recpts;
	}

	void opOpAssign(string op : "~")(EmailRecipient r) {
		recipients ~= r;
	}
	void opOpAssign(string op : "~")(string s) {
		recipients ~= EmailRecipient(s);
	}
	int opApply(int delegate(size_t idx, EmailRecipient rcp) dg) {
		foreach(idx, item; recipients)
			if(auto result = dg(idx, item))
				return result;
		return 0;
	}
	int opApply(int delegate(EmailRecipient rcp) dg) {
		foreach(item; recipients)
			if(auto result = dg(item))
				return result;
		return 0;
	}

	size_t length() {
		return recipients.length;
	}

	string toProtocolString(string linesep = "\r\n") {
		string ret;
		foreach(idx, item; recipients) {
			if(idx)
				ret ~= ", ";
			ret ~= item.toProtocolString(linesep);
		}
		return ret;
	}

	EmailRecipient front() { return recipients[0]; }
	void popFront() { recipients = recipients[1 .. $]; }
	bool empty() { return recipients.length == 0; }
	RecipientList save() { return this; }
}

private string unquote(string s) {
	if(s.length == 0)
		return s;
	if(s[0] != '"')
		return s;
	s = s[1 .. $-1]; // strip the quotes
	// FIXME: possible to have \" escapes in there too
	return s;
}

private struct CaseInsensitiveString {
	string actual;

	size_t toHash() const {
		string l = actual.toLower;
		return typeid(string).getHash(&l);
	}
	bool opEquals(ref const typeof(this) s) const {
		return icmp(s.actual, this.actual) == 0;
	}
	bool opEquals(string s) const {
		return icmp(s, this.actual) == 0;
	}

	alias actual this;
}

/++
	A type that acts similarly to a `string[string]` to hold email headers in a case-insensitive way.
+/
struct HeadersHash {
	string[CaseInsensitiveString] hash;

	string opIndex(string key) const {
		return hash[CaseInsensitiveString(key)];
	}
	string opIndexAssign(string value, string key) {
		return hash[CaseInsensitiveString(key)] = value;
	}
	inout(string)* opBinaryRight(string op : "in")(string key) inout {
		return CaseInsensitiveString(key) in hash;
	}
	alias hash this;
}

unittest {
	HeadersHash h;
	h["From"] = "test";
	h["from"] = "other";
	foreach(k, v; h) {
		assert(k == "From");
		assert(v == "other");
	}

	assert("from" in h);
	assert("From" in h);
	assert(h["from"] == "other");

	const(HeadersHash) ch = HeadersHash([CaseInsensitiveString("From") : "test"]);
	assert(ch["from"] == "test");
	assert("From" in ch);
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

	History:
		This class got an API overhaul on May 13, 2024. Some undocumented members were removed, and some public members got changed (albeit in a mostly compatible way).
+/
class EmailMessage {
	/++
		Adds a custom header to the message. The header name should not include a colon and must not duplicate a header set elsewhere in the class; for example, do not use this to set `To`, and instead use the [to] field.

		Setting the same header multiple times will overwrite the old value. It will not set duplicate headers and does not retain the specific order of which you added headers.

		History:
			Prior to May 13, 2024, this assumed the value was previously encoded. This worked most the time but also left open the possibility of incorrectly encoded values, including the possibility of injecting inappropriate headers.

			Since May 13, 2024, it now encodes the header content internally. You should NOT pass pre-encoded values to this function anymore.

			It also would previously allow you to set repeated headers like `Subject` or `To`. These now throw exceptions.

			It previously also allowed duplicate headers. Adding the same thing twice will now silently overwrite the old value instead.
	+/
	void setHeader(string name, string value, string file = __FILE__, size_t line = __LINE__) {
		import arsd.core;
		if(name.length == 0)
			throw new InvalidArgumentsException("name", "name cannot be an empty string", LimitedVariant(name), "setHeader", file, line);
		if(name.indexOf(":") != -1)
			throw new InvalidArgumentsException("name", "do not put a colon in the header name", LimitedVariant(name), "setHeader", file, line);
		if(!headerSettableThroughAA(name))
			throw new InvalidArgumentsException("name", "use named methods/properties for this header instead of setHeader", LimitedVariant(name), "setHeader", file, line);

		headers_[name] = value;
	}

	protected bool headerSettableThroughAA(string name) {
		switch(name.toLower) {
			case "to", "cc", "bcc":
			case "from", "reply-to", "in-reply-to":
			case "subject":
			case "content-type", "content-transfer-encoding", "mime-version":
			case "received", "return-path": // set by the MTA
				return false;
			default:
				return true;
		}
	}

	/++
		Recipients of the message. You can use operator `~=` to add people to this list, or you can also use [addRecipient] to achieve the same result.

		---
		message.to ~= EmailRecipient("Adam D. Ruppe", "destructionator@gmail.com");
		message.cc ~= EmailRecipient("John Doe", "john.doe@example.com");
		// or, same result as the above two lines:
		message.addRecipient("Adam D. Ruppe", "destructionator@gmail.com");
		message.addRecipient("John Doe", "john.doe@example.com", ToType.cc);

		// or, the old style code that still works, but is not recommended, since
		// it is harder to encode properly for anything except pure ascii names:
		message.to ~= `"Adam D. Ruppe" <destructionator@gmail.com>`
		---

		History:
			On May 13, 2024, the types of these changed. Before, they were `public string[]`; plain string arrays. This put the burden of proper encoding on the user, increasing the probability of bugs. Now, they are [RecipientList]s - internally, an array of `EmailRecipient` objects, but with a wrapper to provide compatibility with the old string-based api.
	+/
	RecipientList to;
	/// ditto
	RecipientList cc;
	/// ditto
	RecipientList bcc;

	/++
		Represents the `From:` and `Reply-To:` header values in the email.


		Note that the `from` member is the "From:" header, which is not necessarily the same as the "envelope from". The "envelope from" is set by the email server usually based on your login credentials. The email server may or may not require these to match.

		History:
			On May 13, 2024, the types of these changed from plain `string` to [EmailRecipient], to try to get the encoding easier to use correctly. `EmailRecipient` offers overloads for string parameters for compatibility, so your code should not need changing, however if you use non-ascii characters in your names, you should retest to ensure it still works correctly.
	+/
	EmailRecipient from;
	/// ditto
	EmailRecipient replyTo;
	/// The `Subject:` header value in the email.
	string subject;
	/// The `In-Reply-to:` header value. This should be set to the same value as the `Message-ID` header from the message you're replying to.
	string inReplyTo;

	private string textBody_;
	private string htmlBody_;

	private HeadersHash headers_;

	/++
		Gets and sets the current text body.

		History:
			Prior to May 13, 2024, this was a simple `public string` member, but still had a [setTextBody] method too. It now is a public property that works through that method.
	+/
	string textBody() {
		return textBody_;
	}
	/// ditto
	void textBody(string text) {
		setTextBody(text);
	}
	/++
		Gets the current html body, if any.

		There is no setter for this property, use [setHtmlBody] instead.

		History:
			Prior to May 13, 2024, this was a simple `public string` member. This let you easily get the `EmailMessage` object into an inconsistent state.
	+/
	string htmlBody() {
		return htmlBody_;
	}

	/++
		If you use the send method with an SMTP server, you don't want to change this.
		While RFC 2045 mandates CRLF as a lineseperator, there are some edge-cases where this won't work.
		When passing the E-Mail string to a unix program which handles communication with the SMTP server, some (i.e. qmail)
		expect the system lineseperator (LF) instead.
		Notably, the google mail REST API will choke on CRLF lineseps and produce strange emails (as of 2024).

		Do not change this after calling other methods, since it might break presaved values.
	+/
	string linesep = "\r\n";

	/++
		History:
			Added May 13, 2024
	+/
	this(string linesep = "\r\n") {
		this.linesep = linesep;
	}

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

	/++
		Sets the plain text body of the email. You can also separately call [setHtmlBody] to set a HTML body.
	+/
	void setTextBody(string text) {
		textBody_ = text.strip;
	}
	/++
		Sets the HTML body to the mail, which can support rich text, inline images (see [addInlineImage]), etc.

		Automatically sets a text fallback if you haven't already, unless you pass `false` as the `addFallback` template value. Adding the fallback requires [arsd.htmltotext].

		History:
			The `addFallback` parameter was added on May 13, 2024.
	+/
	void setHtmlBody(bool addFallback = true)(string html) {
		isMime = true;
		isHtml = true;
		htmlBody_ = html;

		static if(addFallback) {
			import arsd.htmltotext;
			if(textBody_ is null)
				textBody_ = htmlToText(html);
		}
	}

	const(MimeAttachment)[] attachments;

	/++
		The attachmentFileName is what is shown to the user, not the file on your sending computer. It should NOT have a path in it.
		If you want a filename from your computer, try [addFileAsAttachment].

		The `mimeType` can be excluded if the filename has a common extension supported by the library.

		---
			message.addAttachment("text/plain", "something.txt", std.file.read("/path/to/local/something.txt"));
		---

		History:
			The overload without `mimeType` was added October 28, 2024.

			The parameter `attachmentFileName` was previously called `filename`. This was changed for clarity and consistency with other overloads on October 28, 2024.
	+/
	void addAttachment(string mimeType, string attachmentFileName, const void[] content, string id = null) {
		isMime = true;
		attachments ~= MimeAttachment(mimeType, attachmentFileName, cast(const(ubyte)[]) content, id);
	}


	/// ditto
	void addAttachment(string attachmentFileName, const void[] content, string id = null) {
		import arsd.core;
		addAttachment(FilePath(attachmentFileName).contentTypeFromFileExtension, attachmentFileName, content, id);
	}

	/++
		Reads the local file and attaches it.

		If `attachmentFileName` is null, it uses the filename of `localFileName`, without the directory.

		If `mimeType` is null, it guesses one based on the local file name's file extension.

		If these cannot be determined, it will throw an `InvalidArgumentsException`.

		History:
			Added October 28, 2024
	+/
	void addFileAsAttachment(FilePath localFileName, string attachmentFileName = null, string mimeType = null, string id = null) {
		if(mimeType is null)
			mimeType = localFileName.contentTypeFromFileExtension;
		if(attachmentFileName is null)
			attachmentFileName = localFileName.filename;

		import std.file;

		addAttachment(mimeType, attachmentFileName, std.file.read(localFileName.toString()), id);

		// see also: curl.h :1877    CURLOPT(CURLOPT_XOAUTH2_BEARER, CURLOPTTYPE_STRINGPOINT, 220),
		// also option to force STARTTLS
	}

	/// in the html, use img src="cid:ID_GIVEN_HERE"
	void addInlineImage(string id, string mimeType, string filename, const void[] content) {
		assert(isHtml);
		isMime = true;
		inlineImages ~= MimeAttachment(mimeType, filename, cast(const(ubyte)[]) content, id);
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

		string[] headers;
		foreach(k, v; this.headers_) {
			if(headerSettableThroughAA(k))
				headers ~= k ~ ": " ~ encodeEmailHeaderContentForTransmit(v, this.linesep);
		}

		if(to.length)
			headers ~= "To: " ~ to.toProtocolString(this.linesep);
		if(cc.length)
			headers ~= "Cc: " ~ cc.toProtocolString(this.linesep);

		if(from.length)
			headers ~= "From: " ~ from.toProtocolString(this.linesep);

			//assert(0, headers[$-1]);

		if(subject !is null)
			headers ~= "Subject: " ~ encodeEmailHeaderContentForTransmit(subject, this.linesep);
		if(replyTo !is null)
			headers ~= "Reply-To: " ~ replyTo.toProtocolString(this.linesep);
		if(inReplyTo !is null)
			headers ~= "In-Reply-To: " ~ encodeEmailHeaderContentForTransmit(inReplyTo, this.linesep);

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
				enum NO_TRANSFER_ENCODING = "Content-Transfer-Encoding: 8bit";
				if(isHtml) {
					auto alternative = new MimeContainer("multipart/alternative");
					alternative.stuff ~= new MimeContainer("text/plain; charset=UTF-8", textBody_).with_header(NO_TRANSFER_ENCODING);
					alternative.stuff ~= new MimeContainer("text/html; charset=UTF-8", htmlBody_).with_header(NO_TRANSFER_ENCODING);
					mimeMessage = alternative;
				} else {
					mimeMessage = new MimeContainer("text/plain; charset=UTF-8", textBody_).with_header(NO_TRANSFER_ENCODING);
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
						mimeAttachment.content = encodeBase64Mime(cast(const(ubyte)[]) attachment.content, this.linesep);

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
						mimeAttachment.headers ~= "Content-Disposition: attachment; filename=\""~encodeEmailHeaderContentForTransmit(attachment.filename, this.linesep)~"\"";
						mimeAttachment.headers ~= "Content-Transfer-Encoding: base64";
						if(attachment.id.length)
							mimeAttachment.headers ~= "Content-ID: <" ~ attachment.id ~ ">";

						mimeAttachment.content = encodeBase64Mime(cast(const(ubyte)[]) attachment.content, this.linesep);

						mimeMixed.stuff ~= mimeAttachment;
					}
				}
			}

			headers ~= top.contentType;
			msgContent = top.toMimeString(true, this.linesep);
		} else {
			headers ~= "Content-Type: text/plain; charset=UTF-8";
			msgContent = textBody_;
		}


		string msg;
		msg.reserve(htmlBody_.length + textBody_.length + 1024);

		foreach(header; headers)
			msg ~= header ~ this.linesep;
		if(msg.length) // has headers
			msg ~= this.linesep;

		msg ~= msgContent;

		return msg;
	}

	/// Sends via a given SMTP relay
	void send(RelayInfo mailServer = RelayInfo("smtp://localhost")) {
		auto smtp = SMTP(mailServer.server);

		smtp.verifyHost = false;
		smtp.verifyPeer = false;
		//smtp.verbose = true;

		{
			// std.net.curl doesn't work well with STARTTLS if you don't
			// put smtps://... and if you do, it errors if you can't start
			// with a TLS connection from the beginning.

			// This change allows ssl if it can.
			import std.net.curl;
			import etc.c.curl;
			smtp.handle.set(CurlOption.use_ssl, CurlUseSSL.tryssl);
		}

		if(mailServer.username.length)
			smtp.setAuthentication(mailServer.username, mailServer.password);

		const(char)[][] allRecipients;
		void processPerson(string person) {
			auto idx = person.indexOf("<");
			if(idx == -1)
				allRecipients ~= person;
			else {
				person = person[idx + 1 .. $];
				idx = person.indexOf(">");
				if(idx != -1)
					person = person[0 .. idx];

				allRecipients ~= person;
			}
		}
		foreach(person; to) processPerson(person);
		foreach(person; cc) processPerson(person);
		foreach(person; bcc) processPerson(person);

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
	msg.textBody_ = message;
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
		if(type == "multipart/mixed" && stuff.length == 1)
			return stuff[0].toMimeAttachment;

		MimeAttachment att;
		att.type = type;
		if(att.type == "application/octet-stream" && filename.length == 0 && name.length > 0 ) {
			att.filename = name;
		} else {
			att.filename = filename;
		}
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

					string[4] filenames_found;

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
									// FIXME: https://datatracker.ietf.org/doc/html/rfc2184#section-3 is what it is SUPPOSED to do
									case "filename*0":
										filenames_found[0] = v;
									break;
									case "filename*1":
										filenames_found[1] = v;
									break;
									case "filename*2":
										filenames_found[2] = v;
									break;
									case "filename*3":
										filenames_found[3] = v;
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

					if (filenames_found[0] != "") {
						foreach (string v; filenames_found) {
							this.filename ~= v;
						}
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


	string toMimeString(bool isRoot = false, string linesep="\r\n") {
		string ret;

		if(!isRoot) {
			ret ~= contentType;
			foreach(header; headers) {
				ret ~= linesep;
				ret ~= encodeEmailHeaderForTransmit(header, linesep);
			}
			ret ~= linesep ~ linesep;
		}

		ret ~= content;

		foreach(idx, thing; stuff) {
			assert(boundary.length);
			ret ~= linesep ~ "--" ~ boundary ~ linesep;
			ret ~= thing.toMimeString(false, linesep);
		}

		if(boundary.length)
			ret ~= linesep ~ "--" ~ boundary ~ "--";

		return ret;
	}
}

import std.algorithm : startsWith;
/++
	Represents a single email from an incoming or saved source consisting of the raw data. Such saved sources include mbox files (which are several concatenated together, see [MboxMessages] for a full reader of these files), .eml files, and Maildir entries.
+/
class IncomingEmailMessage : EmailMessage {
	/++
		Various constructors for parsing an email message.


		The `ref immutable(ubyte)[][]` one is designed for reading a pre-loaded mbox file. It updates the ref variable to the point at the next message in the file as it processes. You probably should use [MboxMessages] in a `foreach` loop instead of calling this directly most the time.

		The `string[]` one takes an ascii or utf-8 file of a single email pre-split into lines.

		The `immutable(ubyte)[]` one is designed for reading an individual message in its own file in the easiest way. Try `new IncomingEmailMessage(cast(immutable(ubyte)[]) std.file.read("filename.eml"));` to use this. You can also use `IncomingEmailMessage.fromFile("filename.eml")` as well.

		History:
			The `immutable(ubyte)[]` overload for a single file was added on May 14, 2024.
	+/
	this(ref immutable(ubyte)[][] mboxLines, bool asmbox=true) @trusted {

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

			auto originalHeaderName = headerName;
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
				this.to ~= headerContent;
			} else if(headerName == "subject") {
				this.subject = headerContent;
			} else if(headerName == "content-transfer-encoding") {
				contentTransferEncoding = headerContent;
			}

			headers_[originalHeaderName] = headerContent;
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
						this.htmlBody_ ~= line ~ "\n";
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
						this.textBody_ ~= line ~ "\n";
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
					this.htmlBody_ = part.textContent;
				break;
				case "text/plain":
					this.textBody_ = part.textContent;
				break;
				case "multipart/alternative":
					foreach(p; part.stuff) {
						if(p.type == "text/html")
							this.htmlBody_ = p.textContent;
						else if(p.type == "text/plain")
							this.textBody_ = p.textContent;
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
					if(this.textBody_.length)
						this.textBody_ = convertToUtf8Lossy(decodeQuotedPrintable(this.textBody_), charset);
					if(this.htmlBody_.length)
						this.htmlBody_ = convertToUtf8Lossy(decodeQuotedPrintable(this.htmlBody_), charset);
				break;
				case "base64":
					if(this.textBody_.length) {
						this.textBody_ = this.textBody_.decodeBase64Mime.convertToUtf8Lossy(charset);
					}
					if(this.htmlBody_.length) {
						this.htmlBody_ = this.htmlBody_.decodeBase64Mime.convertToUtf8Lossy(charset);
					}

				break;
				default:
					// nothing needed
			}
		}

		if(this.htmlBody_.length > 0 && this.textBody_.length == 0) {
			import arsd.htmltotext;
			this.textBody_ = htmlToText(this.htmlBody_);
			textAutoConverted = true;
		}
	}

	/// ditto
	this(string[] lines) {
		auto lns = cast(immutable(ubyte)[][])lines;
		this(lns, false);
	}

	/// ditto
	this(immutable(ubyte)[] fileContent) {
		auto lns = splitLinesWithoutDecoding(fileContent);
		this(lns, false);
	}

	/++
		Convenience method that takes a filename instead of the content.

		Its implementation is simply `return new IncomingEmailMessage(cast(immutable(ubyte)[]) std.file.read(filename));`
		(though i reserve the right to use a different file loading library later, still the same idea)

		History:
			Added May 14, 2024
	+/
	static IncomingEmailMessage fromFile(string filename) {
		import std.file;
		return new IncomingEmailMessage(cast(immutable(ubyte)[]) std.file.read(filename));
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

	/++
		Allows access to the headers in the email as a key/value hash.

		The hash allows access as if it was case-insensitive, but it also still keeps the original case when you loop through it.

		Bugs:
			Duplicate headers are lost in the current implementation; only the most recent copy of any given name is retained.
	+/
	const(HeadersHash) headers() {
		return headers_;
	}

	/++
		Returns the message body as either HTML or text. Gives the same results as through the parent interface, [EmailMessage.htmlBody] and [EmailMessage.textBody].

		If the message was multipart/alternative, both of these will be populated with content from the message. They are supposed to be both the same, but not all senders respect this so you might want to check both anyway.

		If the message was just plain text, `htmlMessageBody` will be `null` and `textMessageBody` will have the original message.

		If the message was just HTML, `htmlMessageBody` contains the original message and `textMessageBody` will contain an automatically converted version (using [arsd.htmltotext]). [textAutoConverted] will be set to `true`.

		History:
			Were public strings until May 14, 2024, when it was changed to property getters instead.
	+/
	string htmlMessageBody() {
		return this.htmlBody_;
	}
	/// ditto
	string textMessageBody() {
		return this.textBody_;
	}
	/// ditto
	bool textAutoConverted;

	// gpg signature fields
	string gpgalg; ///
	string gpgproto; ///
	MimePart gpgmime; ///

	///
	string fromEmailAddress() {
		return from.address;
	}

	///
	string toEmailAddress() {
		if(to.recipients.length)
			return to.recipients[0].address;
		return null;
	}
}

/++
	An mbox file is a concatenated list of individual email messages. This is a range of messages given the content of one of those files.
+/
struct MboxMessages {
	immutable(ubyte)[][] linesRemaining;

	///
	this(immutable(ubyte)[] data) {
		linesRemaining = splitLinesWithoutDecoding(data);
		popFront();
	}

	IncomingEmailMessage currentFront;

	///
	IncomingEmailMessage front() {
		return currentFront;
	}

	///
	bool empty() {
		return currentFront is null;
	}

	///
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
		else if(encoding == "B" || encoding == "b") {
			decodedText = cast(typeof(decodedText)) Base64.decode(encodedText);
		} else
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

/// Add header UFCS helper
auto with_header(MimeContainer container, string header){
	container.headers ~= header;
	return container;
}

/// Base64 range encoder UFCS helper.
alias base64encode = Base64.encoder;

/// Base64 encoded data with line length of 76 as mandated by RFC 2045 Section 6.8
string encodeBase64Mime(const(ubyte[]) content, string LINESEP = "\r\n") {
	enum LINE_LENGTH = 76;
	/// Only 6 bit of every byte are used; log2(64) = 6
	enum int SOURCE_CHUNK_LENGTH = LINE_LENGTH * 6/8;

	return cast(immutable(char[]))content.chunks(SOURCE_CHUNK_LENGTH).base64encode.join(LINESEP);
}


/// Base64 range decoder UFCS helper.
alias base64decode = Base64.decoder;

/// Base64 decoder, ignoring linebreaks which are mandated by RFC2045
immutable(ubyte[]) decodeBase64Mime(string encodedPart) {
	return cast(immutable(ubyte[])) encodedPart
		.byChar // prevent Autodecoding, which will break Base64 decoder. Since its base64, it's guarenteed to be 7bit ascii
		.filter!((c) => (c != '\r') & (c != '\n'))
		.base64decode
		.array;
}

unittest {
	// Mime base64 roundtrip
	import std.algorithm.comparison;
	string source = chain(
		repeat('n', 1200), //long line
		"\r\n",
		"äöü\r\n",
		"ඞ\rn",
		).byChar.array;
	assert( source.representation.encodeBase64Mime.decodeBase64Mime.equal(source));
}

unittest {
	import std.algorithm;
	import std.string;
	// Mime message roundtrip
	auto mail = new EmailMessage();
	mail.to = ["recipient@example.org"];
	mail.from = "sender@example.org";
	mail.subject = "Subject";

	auto text = cast(string) chain(
			repeat('n', 1200),
			"\r\n",
			"äöü\r\n",
			"ඞ\r\nlast",
			).byChar.array;
	mail.setTextBody(text);
	mail.addAttachment("text/plain", "attachment.txt", text.representation);
	// In case binary and plaintext get handled differently one day
	mail.addAttachment("application/octet-stream", "attachment.bin", text.representation);

	auto result = new IncomingEmailMessage(mail.toString().split("\r\n"));

	assert(result.subject.equal(mail.subject));
	assert(mail.to.canFind(result.to));
	assert(result.from == mail.from.toString);

	// This roundtrip works modulo trailing newline on the parsed message and LF vs CRLF
	assert(result.textMessageBody.replace("\n", "\r\n").stripRight().equal(mail.textBody_));
	assert(result.attachments.equal(mail.attachments));
}

private bool hasAllPrintableAscii(in char[] s) {
	foreach(ch; s) {
		if(ch < 32)
			return false;
		if(ch >= 127)
			return false;
	}
	return true;
}

private string encodeEmailHeaderContentForTransmit(string value, string linesep, bool prechecked = false) {
	if(!prechecked && value.length < 998 && hasAllPrintableAscii(value))
		return value;

	return "=?UTF-8?B?" ~
		encodeBase64Mime(cast(const(ubyte)[]) value, "?=" ~ linesep ~ " =?UTF-8?B?") ~
		"?=";
}

private string encodeEmailHeaderForTransmit(string completeHeader, string linesep) {
	if(completeHeader.length < 998 && hasAllPrintableAscii(completeHeader))
		return completeHeader;

	// note that we are here if there's a newline embedded in the content as well
	auto colon = completeHeader.indexOf(":");
	if(colon == -1) // should never happen!
		throw new Exception("invalid email header - no colon in " ~ completeHeader); // but exception instead of assert since this might happen as result of public data manip

	auto name = completeHeader[0 .. colon + 1];
	if(!hasAllPrintableAscii(name)) // should never happen!
		throw new Exception("invalid email header - improper name: " ~ name); // ditto

	auto value = completeHeader[colon + 1 .. $].strip;

	return
		name ~
		" " ~ // i like that leading space after the colon but it was stripped out of value
		encodeEmailHeaderContentForTransmit(value, linesep, true);
}

unittest {
	auto linesep = "\r\n";
	string test = "Subject: This is an ordinary subject line with no special characters and not exceeding the maximum line length limit.";
	assert(test is encodeEmailHeaderForTransmit(test, linesep)); // returned by identity

	test = "Subject: foo\nbar";
	assert(test !is encodeEmailHeaderForTransmit(test, linesep)); // a newline forces encoding
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
