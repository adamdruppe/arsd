/+
	== arsd.ini ==
	Copyright Elias Batek (0xEAB) 2025.
	Distributed under the Boost Software License, Version 1.0.
+/
/++
	INI configuration file support
 +/
module arsd.ini;

/++
	Determines whether a type `T` is a string type compatible with this library. 
 +/
enum isCompatibleString(T) = (is(T == string) || is(T == const(char)[]) || is(T == char[]));

//dfmt off
///
enum IniDialect : ulong {
	lite                                    = 0,
	lineComments                            = 0b_0000_0000_0000_0001,
	inlineComments                          = 0b_0000_0000_0000_0011,
	hashLineComments                        = 0b_0000_0000_0000_0100,
	hashInLineComments                      = 0b_0000_0000_0000_1100,
	escapeSequences                         = 0b_0000_0000_0001_0000,
	lineFolding                             = 0b_0000_0000_0010_0000,
	quotedStrings                           = 0b_0000_0000_0100_0000,
	arrays                                  = 0b_0000_0000_1000_0000,
	colonKeys                               = 0b_0000_0001_0000_0000,
	defaults                                = (lineComments | quotedStrings), 
}
//dfmt on

private bool hasFeature(ulong dialect, ulong feature) @safe pure nothrow @nogc {
	return ((dialect & feature) > 0);
}

///
public enum IniTokenType {
	invalid = 0,

	whitespace,
	bracketOpen,
	bracketClose,
	keyValueSeparator,
	lineBreak,

	comment,

	key,
	value,
	sectionHeader,
}

///
struct IniToken(string) if (isCompatibleString!string) {

	///
	IniTokenType type;

	///
	string data;
}

private alias TokenType = IniTokenType;
private alias Dialect = IniDialect;

private enum LocationState {
	newLine,
	key,
	value,
	sectionHeader,
}

/++
	Low-level INI parser

	See_also:
		$(LIST
			* [parseIniDocument]
			* [parseIniAA]
		)
 +/
struct IniParser(
	IniDialect dialect = IniDialect.defaults,
	string = immutable(char)[]
) if (isCompatibleString!string) {

	public {
		///
		alias Token = IniToken!string;
	}

	private {
		string _source;
		Token _front;
		bool _empty = true;

		LocationState _locationState = LocationState.newLine;
	}

@safe pure nothrow @nogc:

	///
	public this(string rawIni) {
		_source = rawIni;
		_empty = false;

		this.popFront();
	}

	// Range API
	public {

		///
		bool empty() const {
			return _empty;
		}

		///
		inout(Token) front() inout {
			return _front;
		}

		///
		void popFront() {
			if (_source.length == 0) {
				_empty = true;
				return;
			}

			_front = this.fetchFront();
		}

		///
		inout(typeof(this)) save() inout {
			return this;
		}
	}

	// extras
	public {

		/++
			Skips tokens that are irrelevant for further processing

			Returns:
				true = if there are no further tokens,
					i.e. whether the range is empty now
		 +/
		bool skipIrrelevant(bool skipComments = true) {
			static bool isIrrelevant(const TokenType type, const bool skipComments) {
				pragma(inline, true);

				final switch (type) with (TokenType) {
				case invalid:
					return false;

				case whitespace:
				case bracketOpen:
				case bracketClose:
				case keyValueSeparator:
				case lineBreak:
					return true;

				case comment:
					return skipComments;

				case sectionHeader:
				case key:
				case value:
					return false;
				}
			}

			while (!this.empty) {
				const irrelevant = isIrrelevant(_front.type, skipComments);

				if (!irrelevant) {
					return false;
				}

				this.popFront();
			}

			return true;
		}
	}

	private {

		bool isOnFinalChar() const {
			pragma(inline, true);
			return (_source.length == 1);
		}

		bool isAtStartOfLineOrEquivalent() {
			return (_locationState == LocationState.newLine);
		}

		Token makeToken(TokenType type, size_t length) {
			auto token = Token(type, _source[0 .. length]);
			_source = _source[length .. $];
			return token;
		}

		Token makeToken(TokenType type, size_t length, size_t skip) {
			_source = _source[skip .. $];
			return this.makeToken(type, length);
		}

		Token lexWhitespace() {
			foreach (immutable idxM1, const c; _source[1 .. $]) {
				switch (c) {
				case '\x09':
				case '\x0B':
				case '\x0C':
				case ' ':
					break;

				default:
					return this.makeToken(TokenType.whitespace, (idxM1 + 1));
				}
			}

			// all whitespace
			return this.makeToken(TokenType.whitespace, _source.length);
		}

		Token lexComment() {
			foreach (immutable idxM1, const c; _source[1 .. $]) {
				switch (c) {
				default:
					break;

				case '\x0A':
				case '\x0D':
					return this.makeToken(TokenType.comment, idxM1, 1);
				}
			}

			return this.makeToken(TokenType.comment, (-1 + _source.length), 1);
		}

		Token lexTextImpl(TokenType tokenType)() {

			enum Result {
				end,
				regular,
				whitespace,
			}

			static if (dialect.hasFeature(Dialect.quotedStrings)) {
				bool inQuotedString = false;

				if (_source[0] == '"') {
					inQuotedString = true;

					// chomp quote initiator
					_source = _source[1 .. $];
				}
			} else {
				enum inQuotedString = false;
			}

			Result nextChar(const char c) @safe pure nothrow @nogc {
				pragma(inline, true);

				switch (c) {
				default:
					return Result.regular;

				case '\x09':
				case '\x0B':
				case '\x0C':
				case ' ':
					return (inQuotedString) ? Result.regular : Result.whitespace;

				case '\x0A':
				case '\x0D':
					return (inQuotedString)
						? Result.regular : Result.end;

				case '"':
					return (inQuotedString)
						? Result.end : Result.regular;

				case '#':
					if (dialect.hasFeature(Dialect.hashInLineComments)) {
						return (inQuotedString)
							? Result.regular : Result.end;
					} else {
						return Result.regular;
					}

				case ';':
					if (dialect.hasFeature(Dialect.inlineComments)) {
						return (inQuotedString)
							? Result.regular : Result.end;
					} else {
						return Result.regular;
					}

				case ':':
					static if (dialect.hasFeature(Dialect.colonKeys)) {
						goto case '=';
					} else {
						return Result.regular;
					}

				case '=':
					static if (tokenType == TokenType.key) {
						return (inQuotedString)
							? Result.regular : Result.end;
					} else {
						return Result.regular;
					}

				case ']':
					static if (tokenType == TokenType.sectionHeader) {
						return (inQuotedString)
							? Result.regular : Result.end;
					} else {
						return Result.regular;
					}
				}

				assert(false, "Bug: This should have been unreachable.");
			}

			size_t idxLastText = 0;
			foreach (immutable idx, const c; _source) {
				const status = nextChar(c);

				if (status == Result.end) {
					break;
				} else if (status == Result.whitespace) {
					continue;
				}

				idxLastText = idx;
			}

			const idxEOT = (idxLastText + 1);
			auto token = Token(tokenType, _source[0 .. idxEOT]);
			_source = _source[idxEOT .. $];

			if (inQuotedString) {
				// chomp quote terminator
				_source = _source[1 .. $];
			}

			return token;
		}

		Token lexText() {
			final switch (_locationState) {
			case LocationState.newLine:
			case LocationState.key:
				return this.lexTextImpl!(TokenType.key);

			case LocationState.value:
				return this.lexTextImpl!(TokenType.value);

			case LocationState.sectionHeader:
				return this.lexTextImpl!(TokenType.sectionHeader);
			}
		}

		Token fetchFront() {
			switch (_source[0]) {

			default:
				return this.lexText();

			case '\x0A': {
					_locationState = LocationState.newLine;
					return this.makeToken(TokenType.lineBreak, 1);
				}

			case '\x0D': {
					_locationState = LocationState.newLine;

					// CR<EOF>?
					if (this.isOnFinalChar) {
						return this.makeToken(TokenType.lineBreak, 1);
					}

					// CRLF?
					if (_source[1] == '\x0A') {
						return this.makeToken(TokenType.lineBreak, 2);
					}

					// CR
					return this.makeToken(TokenType.lineBreak, 1);
				}

			case '\x09':
			case '\x0B':
			case '\x0C':
			case ' ':
				return this.lexWhitespace();

			case ':':
				static if (dialect.hasFeature(Dialect.colonKeys)) {
					goto case '=';
				}
				return this.lexText();

			case '=':
				_locationState = LocationState.value;
				return this.makeToken(TokenType.keyValueSeparator, 1);

			case '[':
				_locationState = LocationState.sectionHeader;
				return this.makeToken(TokenType.bracketOpen, 1);

			case ']':
				_locationState = LocationState.key;
				return this.makeToken(TokenType.bracketClose, 1);

			case ';': {
					static if (dialect.hasFeature(Dialect.inlineComments)) {
						return this.lexComment();
					} else static if (dialect.hasFeature(Dialect.lineComments)) {
						if (this.isAtStartOfLineOrEquivalent) {
							return this.lexComment();
						}
						return this.lexText();
					} else {
						return this.lexText();
					}
				}

			case '#': {
					static if (dialect.hasFeature(Dialect.hashInLineComments)) {
						return this.lexComment();
					} else static if (dialect.hasFeature(Dialect.hashLineComments)) {
						if (this.isAtStartOfLineOrEquivalent) {
							return this.lexComment();
						}
						return this.lexText();
					} else {
						return this.lexText();
					}
				}
			}
		}
	}
}

///
@safe unittest {
	// INI document (demo data)
	static immutable string rawIniDocument = `; This is a comment.
[section1]
foo = bar ;another comment
oachkatzl = schwoaf ;try pronouncing that
`;

	// Combine feature flags to build the required dialect.
	const myDialect = (Dialect.defaults | Dialect.inlineComments);

	// Instantiate a new parser and supply our document string.
	auto parser = IniParser!(myDialect)(rawIniDocument);

	int comments = 0;
	int sections = 0;
	int keys = 0;
	int values = 0;

	// Process token by token.
	foreach (const parser.Token token; parser) {
		if (token.type == IniTokenType.comment) {
			++comments;
		}
		if (token.type == IniTokenType.sectionHeader) {
			++sections;
		}
		if (token.type == IniTokenType.key) {
			++keys;
		}
		if (token.type == IniTokenType.value) {
			++values;
		}
	}

	assert(comments == 3);
	assert(sections == 1);
	assert(keys == 2);
	assert(values == 2);
}

@safe unittest {
	static immutable string rawIniDocument = `; This is a comment.
[section1]
s1key1 = value1
s1key2 = value2

; Another comment

[section no.2]
s2key1  = "value3"
s2key2	 =	 value no.4
`;

	auto parser = IniParser!()(rawIniDocument);
	alias Token = typeof(parser).Token;

	{
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.comment, " This is a comment."));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front.type == TokenType.lineBreak);
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.bracketOpen, "["));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.sectionHeader, "section1"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.bracketClose, "]"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front.type == TokenType.lineBreak);
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.key, "s1key1"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.whitespace, " "));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.keyValueSeparator, "="));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.whitespace, " "));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.value, "value1"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front.type == TokenType.lineBreak);
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.key, "s1key2"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.value, "value2"), parser.front.data);

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front.type == TokenType.lineBreak);
	}

	{
		assert(!parser.skipIrrelevant());
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.sectionHeader, "section no.2"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.key, "s2key1"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.value, "value3"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.key, "s2key2"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(!parser.empty);
		assert(parser.front == Token(TokenType.value, "value no.4"));
	}

	parser.popFront();
	assert(parser.skipIrrelevant());
	assert(parser.empty());
}

/++
	Data entry of an INI document
 +/
struct IniKeyValuePair(string) if (isCompatibleString!string) {
	///
	string key;

	///
	string value;
}

/++
	Section of an INI document

	$(NOTE
		Data entries from the document’s root – i.e. those with no designated section –
		are stored in a section with its `name` set to `null`.
	)
 +/
struct IniSection(string) if (isCompatibleString!string) {
	///
	alias KeyValuePair = IniKeyValuePair!string;

	/++
		Name of the section

		Also known as “key”.
	 +/
	string name;

	/++
		Data entries of the section
	 +/
	KeyValuePair[] items;
}

/++
	DOM representation of an INI document
 +/
struct IniDocument(string) if (isCompatibleString!string) {
	///
	alias Section = IniSection!string;

	/++
		Sections of the document

		$(NOTE
			Data entries from the document’s root – i.e. those with no designated section –
			are stored in a section with its `name` set to `null`.

			If there are no named sections in a document, there will be only a single section with no name (`null`).
		)
	 +/
	Section[] sections;
}

/++
	Parses an INI string into a document ("DOM").

	See_also:
		[parseIniAA]
 +/
IniDocument!string parseIniDocument(IniDialect dialect = IniDialect.defaults, string)(string rawIni) @safe pure nothrow
if (isCompatibleString!string) {
	alias Document = IniDocument!string;
	alias Section = IniSection!string;
	alias KeyValuePair = IniKeyValuePair!string;

	auto parser = IniParser!(dialect, string)(rawIni);

	auto document = Document(null);
	auto section = Section(null, null);
	auto kvp = KeyValuePair(null, null);

	void commitKeyValuePair(string nextKey = null) {
		if (kvp.key !is null) {
			section.items ~= kvp;
		}
		kvp = KeyValuePair(nextKey, null);
	}

	void commitSection(string nextSectionName) {
		commitKeyValuePair(null);

		const isNamelessAndEmpty = (
			(section.name is null)
				&& (section.items.length == 0)
		);

		if (!isNamelessAndEmpty) {
			document.sections ~= section;
		}

		if (nextSectionName !is null) {
			section = Section(nextSectionName, null);
		}
	}

	while (!parser.skipIrrelevant()) {
		switch (parser.front.type) with (TokenType) {

		case key:
			commitKeyValuePair(parser.front.data);
			break;

		case value:
			kvp.value = parser.front.data;
			break;

		case sectionHeader:
			commitSection(parser.front.data);
			break;

		default:
			assert(false, "Unexpected parsing error."); // TODO
		}

		parser.popFront();
	}

	commitSection(null);

	return document;
}

///
@safe unittest {
	// INI document (demo data)
	static immutable string iniString = `; This is a comment.

Oachkatzlschwoaf = Seriously, try pronouncing this :P

[Section #1]
foo = bar
d = rocks

; Another comment

[Section No.2]
name    = Walter Bright
company = "Digital Mars"
`;

	// Parse the document.
	auto doc = parseIniDocument(iniString);

	version (none) // exclude from docs
	// …is equivalent to:
	auto doc = parseIniDocument!(IniDialect.defaults)(iniString);

	assert(doc.sections.length == 3);

	// "Root" section (no name):
	assert(doc.sections[0].name is null);
	assert(doc.sections[0].items == [
		IniKeyValuePair!string("Oachkatzlschwoaf", "Seriously, try pronouncing this :P"),
	]);

	// A section with a name:
	assert(doc.sections[1].name == "Section #1");
	assert(doc.sections[1].items.length == 2);
	assert(doc.sections[1].items[0] == IniKeyValuePair!string("foo", "bar"));
	assert(doc.sections[1].items[1] == IniKeyValuePair!string("d", "rocks"));

	// Another section:
	assert(doc.sections[2].name == "Section No.2");
	assert(doc.sections[2].items == [
		IniKeyValuePair!string("name", "Walter Bright"),
		IniKeyValuePair!string("company", "Digital Mars"),
	]);
}

@safe unittest {
	auto doc = parseIniDocument("");
	assert(doc.sections == []);

	doc = parseIniDocument(";Comment\n;Comment2\n");
	assert(doc.sections == []);
}

@safe unittest {
	char[] mutable = ['f', 'o', 'o', '=', 'b', 'a', 'r', '\n'];

	auto doc = parseIniDocument(mutable);
	assert(doc.sections[0].items[0].key == "foo");
	assert(doc.sections[0].items[0].value == "bar");

	// is mutable
	static assert(is(typeof(doc.sections[0].items[0].value) == char[]));
}

/++
	Parses an INI string into an associate array.

	See_also:
		[parseIniDocument]
 +/
string[string][string] parseIniAA(IniDialect dialect = IniDialect.defaults, string)(string rawIni) @safe pure nothrow {
	// TODO: duplicate handling
	auto parser = IniParser!(dialect, string)(rawIni);

	string[string][string] document;
	string[string] section;

	string sectionName = null;
	string keyName = null;

	void commitSection() {
		sectionName = null;
	}

	while (!parser.skipIrrelevant()) {
		switch (parser.front.type) with (TokenType) {

		case key:
			keyName = parser.front.data;
			break;

		case value:
			section[keyName] = parser.front.data;
			break;

		case sectionHeader:
			if ((sectionName !is null) || (section.length > 0)) {
				document[sectionName] = section;
				section = null;
			}
			sectionName = parser.front.data;
			break;

		default:
			assert(false, "Unexpected parsing error."); // TODO
		}

		parser.popFront();
	}

	if ((sectionName !is null) || (section.length > 0)) {
		document[sectionName] = section;
	}

	return document;
}

///
@safe unittest {
	// INI document
	static immutable string demoData = `; This is a comment.

Oachkatzlschwoaf = Seriously, try pronouncing this :P

[Section #1]
foo = bar
d = rocks

; Another comment

[Section No.2]
name    = Walter Bright
company = "Digital Mars"
website = <https://digitalmars.com/>
;email  = "noreply@example.org"
`;

	// Parse the document into an associative array.
	auto aa = parseIniAA(demoData);

	assert(aa.length == 3);

	assert(aa[null].length == 1);
	assert(aa[null]["Oachkatzlschwoaf"] == "Seriously, try pronouncing this :P");

	assert(aa["Section #1"].length == 2);
	assert(aa["Section #1"]["foo"] == "bar");
	assert(aa["Section #1"]["d"] == "rocks");

	string[string] section2 = aa["Section No.2"];
	assert(section2.length == 3);
	assert(section2["name"] == "Walter Bright");
	assert(section2["company"] == "Digital Mars");
	assert(section2["website"] == "<https://digitalmars.com/>");

	// "email" is commented out
	assert(!("email" in section2));
}
