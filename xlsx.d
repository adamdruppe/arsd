/++
	Some support for the Microsoft Excel Spreadsheet file format.

	Don't expect much from it.

	Some code is borrowed from the xlsxreader package.

	History:
		Added February 13, 2025

	See_Also:
		https://github.com/symmetryinvestments/xlsxd which supports writing xlsx files. I might add write support here too someday but I kinda doubt it.
+/
module arsd.xlsx;

// See also Robert's impl: https://github.com/symmetryinvestments/xlsxreader/blob/master/source/xlsxreader.d

import arsd.core;
import arsd.zip;
import arsd.dom;
import arsd.color;

import std.conv;

/+
struct XlsxCell {
	string type;
	string formula;
	string value;
}
+/

struct CellReference {
	string name;

	static CellReference fromInts(int column, int row) {
		string ret;

		string piece;
		do {
			piece ~= cast(char)(column % 26 + 'A');
			column /= 26;
		} while(column);

		foreach_reverse(ch; piece)
			ret ~= ch;
		piece = null;

		do {
			piece ~= cast(char)(row % 10 + '0');
			row /= 10;
		} while(row);

		foreach_reverse(ch; piece)
			ret ~= ch;
		piece = null;

		return CellReference(ret);
	}

	int toColumnIndex() {
		int accumulator;
		foreach(ch; name) {
			if(ch < 'A' || ch > 'Z')
				break;
			accumulator *= 26;
			accumulator += ch - 'A';
		}
		return accumulator;
	}

	int toRowIndex() {
		int accumulator;
		foreach(ch; name) {
			if(ch >= 'A' && ch <= 'Z')
				continue;
			accumulator *= 10;
			accumulator += ch - '0';
		}
		return accumulator;
	}
}

/++

+/
class XlsxSheet {
	private string name_;
	private XlsxFile file;
	private XmlDocument document;
	private this(XlsxFile file, string name, XmlDocument document) {
		this.file = file;
		this.name_ = name;
		this.document = document;

		this.dimension = document.requireSelector("worksheet > dimension").getAttribute("ref");
		// there's also sheetView with selection, activeCell, etc
		// and cols with widths and such

		auto ul = this.upperLeft;
		this.minRow = ul.toRowIndex;
		this.minColumn = ul.toColumnIndex;

		auto lr = this.lowerRight;
		this.maxRow = lr.toRowIndex + 1;
		this.maxColumn = lr.toColumnIndex + 1;
	}

	private string dimension;

	private int minRow;
	private int minColumn;
	private int maxRow;
	private int maxColumn;

	/++
	+/
	Size size() {
		return Size(maxColumn - minColumn, maxRow - minRow);
	}

	private CellReference upperLeft() {
		foreach(idx, ch; dimension)
			if(ch == ':')
				return CellReference(dimension[0 .. idx]);
		assert(0);
	}

	private CellReference lowerRight() {
		foreach(idx, ch; dimension)
			if(ch == ':')
				return CellReference(dimension[idx + 1 .. $]);
		assert(0);
	}

	// opIndex could be like sheet["A1:B4"] and sheet["A1", "B4"] and stuff maybe.

	/++
	+/
	string name() {
		return name_;
	}

	/++
		Suitable for passing to [arsd.csv.toCsv]
	+/
	string[][] toStringGrid() {
		// FIXME: this crashes on opend dmd!
		// string[][] ret = new string[][](size.height, size.width);

		string[][] ret;
		ret.length = size.height;
		foreach(ref row; ret)
			row.length = size.width;

		//alloc done

		foreach(int rowIdx, row; ret)
		foreach(int cellIdx, ref cell; row) {
			string cellReference = CellReference.fromInts(cellIdx + minColumn, rowIdx + minRow).name;
			// FIXME: i should prolly read left to right here at least and not iterate the whole document over and over
			auto element = document.querySelector("c[r=\""~cellReference~"\"]");
			if(element is null)
				continue;
			string v = element.requireSelector("v").textContent;
			if(element.attrs.t == "s")
				v = file.sharedStrings[v.to!int()];
			cell = v;
		}
		return ret;
	}
}

/++

+/
class XlsxFile {
	private ZipFile zipFile;

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
	+/
	int sheetCount() {
		return cast(int) sheetsInternal.length;
	}

	/++
	+/
	string[] sheetNames() {
		string[] ret;
		foreach(sheet; sheetsInternal)
			ret ~= sheet.name;
		return ret;
	}

	/++
	+/
	XlsxSheet getSheet(string name) {
		foreach(ref sheet; sheetsInternal)
			if(sheet.name == name)
				return getSheetParsed(sheet);
		return null;

	}

	/// ditto
	XlsxSheet getSheet(int indexZeroBased) {
		// FIXME: if it is out of range do what?
		return getSheetParsed(sheetsInternal[indexZeroBased]);
	}

	// docProps/core.xml has creator, last modified, etc.

	private string[string] contentTypes;
	private struct Relationship {
		string id;
		string type;
		string target;
	}
	private Relationship[string] relationships;
	private string[] sharedStrings;

	private struct SheetInternal {
		string name;
		string id;
		string rel;

		XmlDocument cached;
		XlsxSheet parsed;
	}
	private SheetInternal[] sheetsInternal;

	private XmlDocument getSheetXml(ref SheetInternal sheet) {
		if(sheet.cached is null)
			loadXml("xl/" ~ relationships[sheet.rel].target, (document) { sheet.cached = document; });

		return sheet.cached;
	}

	private XlsxSheet getSheetParsed(ref SheetInternal sheet) {
		if(sheet.parsed is null)
			sheet.parsed = new XlsxSheet(this, sheet.name, getSheetXml(sheet));

		return sheet.parsed;
	}


	private void load() {
		loadXml("[Content_Types].xml", (document) {
			foreach(element; document.querySelectorAll("Override"))
				contentTypes[element.attrs.PartName] = element.attrs.ContentType;
		});

		loadXml("xl/_rels/workbook.xml.rels", (document) {
			foreach(element; document.querySelectorAll("Relationship"))
				relationships[element.attrs.Id] = Relationship(element.attrs.Id, element.attrs.Type, element.attrs.Target);
		});

		loadXml("xl/sharedStrings.xml", (document) {
			foreach(element; document.querySelectorAll("si t"))
				sharedStrings ~= element.textContent;
		});

		loadXml("xl/workbook.xml", (document) {
			foreach(element; document.querySelectorAll("sheets > sheet")) {
				sheetsInternal ~= SheetInternal(element.attrs.name, element.attrs.sheetId, element.getAttribute("r:id"));
			}
		});
	}

	private void loadXml(string filename, scope void delegate(XmlDocument document) handler) {
		auto document = new XmlDocument(cast(string) zipFile.getContent(filename));
		handler(document);
	}
}
