module arsd.email;

import std.net.curl;
pragma(lib, "curl");

import std.base64;

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
	}

	const(MimeAttachment)[] attachments;

	void addAttachment(string mimeType, string filename, in void[] content) {
		isMime = true;
		attachments ~= MimeAttachment(mimeType, filename, content);
	}


	override string toString() {
		string boundary = "0016e64be86203dd36047610926a"; // FIXME

		assert(!isHtml || (isHtml && isMime));

		auto headers = this.headers;

		string toHeader = "To: ";
		bool toHeaderOutputted = false;
		foreach(t; to) {
			if(toHeaderOutputted)
				toHeader ~= ", ";
			else
				toHeaderOutputted = true;

			toHeader ~= t;
		}

		if(to.length)
			headers ~= toHeader;

		if(subject !is null)
			headers ~= "Subject: " ~ subject;

		if(isMime)
			headers ~= "MIME-Version: 1.0";

		if(attachments.length)
			headers ~= "Content-Type: multipart/mixed; boundary=" ~ boundary;
		else if(isHtml)
			headers ~= "Content-Type: multipart/alternative; boundary=" ~ boundary;
		else
			headers ~= "Content-Type: text/plain; charset=UTF-8";

		string msg;
		msg.reserve(htmlBody.length + textBody.length + 1024);

		foreach(header; headers)
			msg ~= header ~ "\r\n";
		if(msg.length) // has headers
			msg ~= "\r\n";

		if(isMime) {
			msg ~= "--" ~ boundary ~ "\r\n";
			msg ~= "Content-Type: text/plain; charset=UTF-8\r\n\r\n";
		}

		msg ~= textBody;

		if(isMime)
			msg ~= "\r\n--" ~ boundary;
		if(isHtml) {
			msg ~= "\r\n";
			msg ~= "Content-Type: text/html; charset=UTF-8\r\n\r\n";
			msg ~= htmlBody;
			msg ~= "\r\n--" ~ boundary;
		}

		foreach(attachment; attachments) {
			assert(isMime);
			msg ~= "\r\n";
			msg ~= "Content-Type: " ~ attachment.type ~ "\r\n";
			msg ~= "Content-Disposition: attachment; filename=\""~attachment.filename~"\"\r\n";
			msg ~= "Content-Transfer-Encoding: base64\r\n";
			msg ~= "\r\n";
			msg ~= Base64.encode(cast(const(ubyte)[]) attachment.content);
			msg ~= "\r\n--" ~ boundary;
		}

		if(isMime)
			msg ~= "--\r\n";

		return msg;
	}

	void send(RelayInfo mailServer = RelayInfo("smtp://localhost")) {
		auto smtp = new SMTP(mailServer.server);
		if(mailServer.username.length)
			smtp.setAuthentication(mailServer.username, mailServer.password);
		const(char)[][] allRecipients = cast(const(char)[][]) (to ~ cc ~ bcc); // WTF cast
		smtp.mailTo(allRecipients);
		smtp.mailFrom = from;
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
