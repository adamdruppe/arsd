/++
	Bare minimum support for reading Microsoft Word files.

	History:
		Added February 19, 2025
+/
module arsd.docx;

import arsd.core;
import arsd.zip;
import arsd.dom;
import arsd.color;

/++

+/
class DocxFile {
	private ZipFile zipFile;
	private XmlDocument document;

	/++

	+/
	this(FilePath file) {
		this.zipFile = new ZipFile(file);

		load();
	}

	/// ditto
	this(immutable(ubyte)[] rawData) {
		this.zipFile = new ZipFile(rawData);

		load();
	}

	/++
		Converts the document to a plain text string that gives you
		the jist of the document that you can view in a plain editor.

		Most formatting is stripped out.
	+/
	string toPlainText() {
		string ret;
		foreach(paragraph; document.querySelectorAll("w\\:p")) {
			if(ret.length)
				ret ~= "\n\n";
			ret ~= paragraph.innerText;
		}
		return ret;
	}

	// FIXME: to RTF, markdown, html, and terminal sequences might also be useful.

	private void load() {
		loadXml("word/document.xml", (document) {
			this.document = document;
		});
	}

	private void loadXml(string filename, scope void delegate(XmlDocument document) handler) {
		auto document = new XmlDocument(cast(string) zipFile.getContent(filename));
		handler(document);
	}

}
