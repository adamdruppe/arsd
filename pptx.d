/++
	Bare minimum support for reading Microsoft PowerPoint files.

	History:
		Added February 19, 2025
+/
module arsd.pptx;

// see ~/zip/ppt

import arsd.core;
import arsd.zip;
import arsd.dom;
import arsd.color;

/++

+/
class PptxFile {
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

	/// public for now but idk forever.
	PptxSlide[] slides;

	private string[string] contentTypes;
	private struct Relationship {
		string id;
		string type;
		string target;
	}
	private Relationship[string] relationships;

	private void load() {
		loadXml("[Content_Types].xml", (document) {
			foreach(element; document.querySelectorAll("Override"))
				contentTypes[element.attrs.PartName] = element.attrs.ContentType;
		});
		loadXml("ppt/_rels/presentation.xml.rels", (document) {
			foreach(element; document.querySelectorAll("Relationship"))
				relationships[element.attrs.Id] = Relationship(element.attrs.Id, element.attrs.Type, element.attrs.Target);
		});

		loadXml("ppt/presentation.xml", (document) {
			this.document = document;

			foreach(element; document.querySelectorAll("p\\:sldIdLst p\\:sldId"))
				loadXml("ppt/" ~ relationships[element.getAttribute("r:id")].target, (document) {
					slides ~= new PptxSlide(this, document);
				});
		});

		// then there's slide masters and layouts and idk what that is yet
	}

	private void loadXml(string filename, scope void delegate(XmlDocument document) handler) {
		auto document = new XmlDocument(cast(string) zipFile.getContent(filename));
		handler(document);
	}

}

class PptxSlide {
	private PptxFile file;
	private XmlDocument document;
	private this(PptxFile file, XmlDocument document) {
		this.file = file;
		this.document = document;
	}

	/++
	+/
	string toPlainText() {
		// FIXME: need to handle at least some of the layout
		return document.root.innerText;
	}
}
