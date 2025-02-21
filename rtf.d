/++
	Some support for the RTF file format - rich text format, like produced by Windows WordPad.

	History:
		Added February 13, 2025
+/
module arsd.rtf;

// https://www.biblioscape.com/rtf15_spec.htm
// https://latex2rtf.sourceforge.net/rtfspec_62.html
// https://en.wikipedia.org/wiki/Rich_Text_Format

// spacing is in "twips" or 1/20 of a point (as in text size unit). aka 1/1440th of an inch.

import arsd.core;
import arsd.color;

/++

+/
struct RtfDocument {
	RtfGroup root;

	/++
		There are two helper functions to process a RTF file: one that does minimal processing
		and sends you the data as it appears in the file, and one that sends you preprocessed
		results upon significant state changes.

		The former makes you do more work, but also exposes (almost) the whole file to you (it is still partially processed). The latter lets you just get down to business processing the text, but is not a complete implementation.
	+/
	void process(void delegate(RtfPiece piece, ref RtfState state) dg) {
		recurseIntoGroup(root, RtfState.init, dg);
	}

	private static void recurseIntoGroup(RtfGroup group, RtfState parentState, void delegate(RtfPiece piece, ref RtfState state) dg) {
		// might need to copy...
		RtfState state = parentState;
		auto newDestination = group.destination;
		if(newDestination.length)
			state.currentDestination = newDestination;

		foreach(piece; group.pieces) {
			if(piece.contains == RtfPiece.Contains.group) {
				recurseIntoGroup(piece.group, state, dg);
			} else {
				dg(piece, state);
			}
		}

	}

	//Color[] colorTable;
	//Object[] fontTable;
}

/// ditto
RtfDocument readRtfFromString(const(char)[] s) {
	return readRtfFromBytes(cast(const(ubyte)[]) s);
}

/// ditto
RtfDocument readRtfFromBytes(const(ubyte)[] s) {
	RtfDocument document;

	if(s.length < 7)
		throw new ArsdException!"not a RTF file"("too short");
	if((cast(char[]) s[0..6]) != `{\rtf1`)
		throw new ArsdException!"not a RTF file"("wrong magic number");

	document.root = parseRtfGroup(s);

	return document;
}

/// ditto
struct RtfState {
	string currentDestination;
}

unittest {
	auto document = readRtfFromString("{\\rtf1Hello\nWorld}");
	//import std.file; auto document = readRtfFromString(readText("/home/me/test.rtf"));
	document.process((piece, ref state) {
		final switch(piece.contains) {
			case RtfPiece.Contains.controlWord:
				// writeln(state.currentDestination, ": ", piece.controlWord);
			break;
			case RtfPiece.Contains.text:
				// writeln(state.currentDestination, ": ", piece.text);
			break;
			case RtfPiece.Contains.group:
				assert(0);
		}
	});

	// writeln(toPlainText(document));
}

string toPlainText(RtfDocument document) {
	string ret;
	document.process((piece, ref state) {
		if(state.currentDestination.length)
			return;

		final switch(piece.contains) {
			case RtfPiece.Contains.controlWord:
				if(piece.controlWord.letterSequence == "par")
					ret ~= "\n\n";
				else if(piece.controlWord.toDchar != dchar.init)
					ret ~= piece.controlWord.toDchar;
			break;
			case RtfPiece.Contains.text:
				ret ~= piece.text;
			break;
			case RtfPiece.Contains.group:
				assert(0);
		}
	});

	return ret;
}

private RtfGroup parseRtfGroup(ref const(ubyte)[] s) {
	RtfGroup group;

	assert(s[0] == '{');
	s = s[1 .. $];
	if(s.length == 0)
		throw new ArsdException!"bad RTF file"("premature end after {");
	while(s[0] != '}') {
		group.pieces ~= parseRtfPiece(s);
		if(s.length == 0)
			throw new ArsdException!"bad RTF file"("premature end before {");
	}
	s = s[1 .. $];
	return group;
}

private RtfPiece parseRtfPiece(ref const(ubyte)[] s) {
	while(true)
	switch(s[0]) {
		case '\\':
			return RtfPiece(parseRtfControlWord(s));
		case '{':
			return RtfPiece(parseRtfGroup(s));
		case '\t':
			s = s[1 .. $];
			return RtfPiece(RtfControlWord.tab);
		case '\r':
		case '\n':
			// skip irrelevant characters
			s = s[1 .. $];
			continue;
		default:
			return RtfPiece(parseRtfText(s));
	}
}

private RtfControlWord parseRtfControlWord(ref const(ubyte)[] s) {
	assert(s[0] == '\\');
	s = s[1 .. $];

	if(s.length == 0)
		throw new ArsdException!"bad RTF file"("premature end after \\");

	RtfControlWord ret;

	size_t pos;
	do {
		pos++;
	} while(pos < s.length && isAlpha(cast(char) s[pos]));

	ret.letterSequence = (cast(const char[]) s)[0 .. pos].idup;
	s = s[pos .. $];

	if(isAlpha(ret.letterSequence[0])) {
		if(s.length == 0)
			throw new ArsdException!"bad RTF file"("premature end after control word");

		int readNumber() {
			if(s.length == 0)
				throw new ArsdException!"bad RTF file"("premature end when reading number");
			int count;
			while(s[count] >= '0' && s[count] <= '9')
				count++;
			if(count == 0)
				throw new ArsdException!"bad RTF file"("expected negative number, got something else");

			auto buffer = cast(const(char)[]) s[0 .. count];
			s = s[count .. $];

			int accumulator;
			foreach(ch; buffer) {
				accumulator *= 10;
				accumulator += ch - '0';
			}

			return accumulator;
		}

		if(s[0] == '-') {
			ret.hadNumber = true;
			s = s[1 .. $];
			ret.number = - readNumber();

			// negative number
		} else if(s[0] >= '0' && s[0] <= '9') {
			// non-negative number
			ret.hadNumber = true;
			ret.number = readNumber();
		}

		if(s[0] == ' ') {
			ret.hadSpaceAtEnd = true;
			s = s[1 .. $];
		}

	} else {
		// it was a control symbol
		if(ret.letterSequence == "\r" || ret.letterSequence == "\n")
			ret.letterSequence = "par";
	}

	return ret;
}

private string parseRtfText(ref const(ubyte)[] s) {
	size_t end = s.length;
	foreach(idx, ch; s) {
		if(ch == '\\' || ch == '{' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '}') {
			end = idx;
			break;
		}
	}
	auto ret = s[0 .. end];
	s = s[end .. $];

	// FIXME: charset conversion?
	return (cast(const char[]) ret).idup;
}

// \r and \n chars w/o a \\ before them are ignored. but \ at the end of al ine is a \par
// \t is read but you should use \tab generally
// when reading, ima translate the ascii tab to \tab control word
// and ignore
struct RtfPiece {
	/++
	+/
	Contains contains() {
		return contains_;
	}
	/// ditto
	enum Contains {
		controlWord,
		group,
		text
	}

	this(RtfControlWord cw) {
		this.controlWord_ = cw;
		this.contains_ = Contains.controlWord;
	}
	this(RtfGroup g) {
		this.group_ = g;
		this.contains_ = Contains.group;
	}
	this(string s) {
		this.text_ = s;
		this.contains_ = Contains.text;
	}

	/++
	+/
	RtfControlWord controlWord() {
		if(contains != Contains.controlWord)
			throw ArsdException!"RtfPiece type mismatch"(contains);
		return controlWord_;
	}
	/++
	+/
	RtfGroup group() {
		if(contains != Contains.group)
			throw ArsdException!"RtfPiece type mismatch"(contains);
		return group_;
	}
	/++
	+/
	string text() {
		if(contains != Contains.text)
			throw ArsdException!"RtfPiece type mismatch"(contains);
		return text_;
	}

	private Contains contains_;

	private union {
		RtfControlWord controlWord_;
		RtfGroup group_;
		string text_;
	}
}

// a \word thing
struct RtfControlWord {
	bool hadSpaceAtEnd;
	bool hadNumber;
	string letterSequence; // what the word is
	int number;

	bool isDestination() {
		switch(letterSequence) {
			case
			"author", "comment", "subject", "title",
			"buptim", "creatim", "printim", "revtim",
			"doccomm",
			"footer", "footerf", "footerl", "footerr",
			"footnote",
			"ftncn", "ftnsep", "ftnsepc",
			"header", "headerf", "headerl", "headerr",
			"info", "keywords", "operator",
			"pict",
			"private",
			"rxe",
			"stylesheet",
			"tc",
			"txe",
			"xe":
				return true;
			case "colortbl":
				return true;
			case "fonttbl":
				return true;

			default: return false;
		}
	}

	dchar toDchar() {
		switch(letterSequence) {
			case "{": return '{';
			case "}": return '}';
			case `\`: return '\\';
			case "~": return '\&nbsp;';
			case "tab": return '\t';
			case "line": return '\n';
			default: return dchar.init;
		}
	}

	bool isTurnOn() {
		return !hadNumber || number != 0;
	}

	// take no delimiters
	bool isControlSymbol() {
		// if true, the letterSequence is the symbol
		return letterSequence.length && !isAlpha(letterSequence[0]);
	}

	// letterSequence == ~ is a non breaking space

	static RtfControlWord tab() {
		RtfControlWord w;
		w.letterSequence = "tab";
		return w;
	}
}

private bool isAlpha(char c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

// a { ... } thing
struct RtfGroup {
	RtfPiece[] pieces;

	string destination() {
		return isStarred() ?
			((pieces.length > 1 && pieces[1].contains == RtfPiece.Contains.controlWord) ? pieces[1].controlWord.letterSequence : null)
			: ((pieces.length && pieces[0].contains == RtfPiece.Contains.controlWord && pieces[0].controlWord.isDestination) ? pieces[0].controlWord.letterSequence : null);
	}

	bool isStarred() {
		return (pieces.length && pieces[0].contains == RtfPiece.Contains.controlWord && pieces[0].controlWord.letterSequence == "*");
	}
}

/+
	\pard = paragraph defaults
+/
