module arsd.email;

import std.net.curl;
pragma(lib, "curl");

import std.base64;
import std.string;

// SEE ALSO: std.net.curl.SMTP

struct RelayInfo {
	string server;
	string username;
	string password;
}

class EmailMessage {
	void setHeader(string name, string value) {
		headers ~= name ~ ": " ~ value;
	}

	string[] to;
	string[] cc;
	string[] bcc;
	string from;
	string replyTo;
	string inReplyTo;
	string textBody;
	string htmlBody;
	string subject;

	string[] headers;

	private bool isMime = false;
	private bool isHtml = false;

	void setTextBody(string text) {
		textBody = text;
	}
	void setHtmlBody(string html) {
		isMime = true;
		isHtml = true;
		htmlBody = html;

		import arsd.htmltotext;
		if(textBody is null)
			textBody = htmlToText(html);
	}

	struct MimeAttachment {
		string type;
		string filename;
		const(void)[] content;
		string id;
	}

	const(MimeAttachment)[] attachments;

	void addAttachment(string mimeType, string filename, in void[] content, string id = null) {
		isMime = true;
		attachments ~= MimeAttachment(mimeType, filename, content, id);
	}

	// in the html, use img src="cid:ID_GIVEN_HERE"
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

	void send(RelayInfo mailServer = RelayInfo("smtp://localhost")) {
		auto smtp = new SMTP(mailServer.server);
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
