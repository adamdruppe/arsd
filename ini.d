/+
	== arsd.ini ==
	Copyright Elias Batek (0xEAB) 2025.
	Distributed under the Boost Software License, Version 1.0.
+/
/++
	INI configuration file support

	This module provides a configurable INI parser with support for multiple
	“dialects” of the format.

	---
	import arsd.ini;

	IniDocument!string parseIniFile(string filePath) {
		import std.file : readText;
		return parseIniDocument(readText(filePath));
	}
	---
 +/
module arsd.ini;

///
@safe unittest {
	// INI example data (e.g. from an `autorun.inf` file)
	static immutable string rawIniData =
		"[autorun]\n"
		~ "open=setup.exe\n"
		~ "icon=setup.exe,0\n";

	// Parse the document into an associative array:
	string[string][string] data = parseIniAA(rawIniData);

	string open = data["autorun"]["open"];
	string icon = data["autorun"]["icon"];

	assert(open == "setup.exe");
	assert(icon == "setup.exe,0");
}

/++
	Determines whether a type `T` is a string type compatible with this library. 
 +/
enum isCompatibleString(T) = (is(T == string) || is(T == const(char)[]) || is(T == char[]));

//dfmt off
/++
	Feature set to be understood by the parser.

	---
	enum myDialect = (IniDialect.defaults | IniDialect.inlineComments);
	---
 +/
enum IniDialect : ulong {
	/++
		Minimum feature set.

		No comments, no extras, no nothing.
		Only sections, keys and values.
		Everything fits into these categories from a certain point of view.
	 +/
	lite                                    = 0,

	/++
		Parse line comments (starting with `;`).

		```ini
		; This is a line comment.
		;This one too.

		key = value ;But this isn't one.
		```
	 +/
	lineComments                            = 0b_0000_0000_0000_0001,

	/++
		Parse inline comments (starting with `;`).

		```ini
		key1 = value2 ; Inline comment.
		key2 = value2 ;Inline comment.
		key3 = value3; Inline comment.
		;Not a true inline comment (but technically equivalent).
		```
	 +/
	inlineComments                          = 0b_0000_0000_0000_0011,

	/++
		Parse line comments starting with `#`.

		```ini
		# This is a comment.
		#Too.
		key = value # Not a line comment.
		```
	 +/
	hashLineComments                        = 0b_0000_0000_0000_0100,

	/++
		Parse inline comments starting with `#`.

		```ini
		key1 = value2 # Inline comment.
		key2 = value2 #Inline comment.
		key3 = value3# Inline comment.
		#Not a true inline comment (but technically equivalent).
		```
	 +/
	hashInlineComments                      = 0b_0000_0000_0000_1100,

	/++
		Parse quoted strings.

		```ini
		key1 = non-quoted value
		key2 = "quoted value"

		"quoted key" = value
		non-quoted key = value

		"another key" = "another value"

		multi line = "line 1
		line 2"
		```
	 +/
	quotedStrings                           = 0b_0000_0000_0001_0000,

	/++
		Parse quoted strings using single-quotes.

		```ini
		key1 = non-quoted value
		key2 = 'quoted value'

		'quoted key' = value
		non-quoted key = value

		'another key' = 'another value'

		multi line = 'line 1
		line 2'
		```
	 +/
	singleQuoteQuotedStrings                = 0b_0000_0000_0010_0000,

	/++
		Parse key/value pairs separated with a colon (`:`).

		```ini
		key: value
		key= value
		```
	 +/
	colonKeys                               = 0b_0000_0000_0100_0000,

	/++
		Concats substrings and emits them as a single token.

		$(LIST
			* For a mutable `char[]` input,
			  this will rewrite the data in the input array.
			* For a non-mutable `immutable(char)[]` (=`string`) or `const(char)[]` input,
			  this will allocate a new array with the GC.
		)

		```ini
		key = "Value1" "Value2"
		; → Value1Value2
		```
	 +/
	concatSubstrings                        = 0b_0000_0001_0000_0000,

	/++
		Evaluates escape sequences in the input string.

		$(LIST
			* For a mutable `char[]` input,
			  this will rewrite the data in the input array.
			* For a non-mutable `immutable(char)[]` (=`string`) or `const(char)[]` input,
			  this will allocate a new array with the GC.
		)

		$(SMALL_TABLE
			Special escape sequences
			`\\` | Backslash
			`\0` | Null character
			`\n` | Line feed
			`\r` | Carriage return
			`\t` | Tabulator
		)

		```ini
		key1 = Line 1\nLine 2
		; → Line 1
		;   Line 2

		key2 = One \\ and one \;
		; → One \ and one ;
		```
	 +/
	escapeSequences                         = 0b_0000_0010_0000_0000,

	/++
		Folds lines on escaped linebreaks.

		$(LIST
			* For a mutable `char[]` input,
			  this will rewrite the data in the input array.
			* For a non-mutable `immutable(char)[]` (=`string`) or `const(char)[]` input,
			  this will allocate a new array with the GC.
		)

		```ini
		key1 = word1\
		word2
		; → word1word2

		key2 = foo \
		bar
		; → foo bar
		```
	 +/
	lineFolding                             = 0b_0000_0100_0000_0000,

	/++
		Imitates the behavior of the INI parser implementation found in PHP.

		$(WARNING
			This preset may be adjusted without further notice in the future
			in cases where it increases alignment with PHP’s implementation.
		)
	 +/
	presetPhp                               = (
	                                              lineComments
	                                            | inlineComments
	                                            | hashLineComments
	                                            | hashInlineComments
	                                            | quotedStrings
	                                            | singleQuoteQuotedStrings
	                                            | concatSubstrings
	                                        ),

	///
	presetDefaults                          = (
	                                              lineComments
	                                            | quotedStrings
	                                            | singleQuoteQuotedStrings
	                                        ),

	///
	defaults = presetDefaults,
}
//dfmt on

private bool hasFeature(ulong dialect, ulong feature) @safe pure nothrow @nogc {
	return ((dialect & feature) > 0);
}

/++
	Type of a token (as output by the parser)
 +/
public enum IniTokenType {
	/// indicates an error
	invalid = 0,

	/// insignificant whitespace
	whitespace,
	/// section header opening bracket
	bracketOpen,
	/// section header closing bracket
	bracketClose,
	/// key/value separator, e.g. '='
	keyValueSeparator,
	/// line break, i.e. LF, CRLF or CR
	lineBreak,

	/// text comment
	comment,

	/// item key data
	key,
	/// item value data
	value,
	/// section name data
	sectionHeader,
}

/++
	Token of INI data (as output by the parser)
 +/
struct IniToken(string) if (isCompatibleString!string) {
	///
	IniTokenType type;

	/++
		Content
	 +/
	string data;
}

private alias TokenType = IniTokenType;
private alias Dialect = IniDialect;

private enum LocationState {
	newLine,
	key,
	preValue,
	inValue,
	sectionHeader,
}

private enum OperatingMode {
	mut,
	dup,
}

private enum OperatingMode operatingMode(string) = (is(string == char[]))
	? OperatingMode.mut : OperatingMode.dup;

/++
	Low-level INI parser

	See_also:
		$(LIST
			* [IniFilteredParser]
			* [parseIniDocument]
			* [parseIniAA]
		)
 +/
struct IniParser(
	IniDialect dialect = IniDialect.defaults,
	string = immutable(char)[],
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

		static if (dialect.hasFeature(Dialect.concatSubstrings)) {
			bool _bypassConcatSubstrings = false;
		}
	}

@safe pure nothrow:

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

		bool isOnFinalChar() const @nogc {
			pragma(inline, true);
			return (_source.length == 1);
		}

		bool isAtStartOfLineOrEquivalent() @nogc {
			return (_locationState == LocationState.newLine);
		}

		Token makeToken(TokenType type, size_t length) @nogc {
			auto token = Token(type, _source[0 .. length]);
			_source = _source[length .. $];
			return token;
		}

		Token makeToken(TokenType type, size_t length, size_t skip) @nogc {
			_source = _source[skip .. $];
			return this.makeToken(type, length);
		}

		Token lexWhitespace() @nogc {
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

		Token lexComment() @nogc {
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

		Token lexSubstringImpl(TokenType tokenType)() {

			enum Result {
				end,
				endChomp,
				regular,
				whitespace,
			}

			enum QuotedString : ubyte {
				none = 0,
				regular,
				single,
			}

			// dfmt off
			enum hasAnyQuotedString = (
				dialect.hasFeature(Dialect.quotedStrings) ||
				dialect.hasFeature(Dialect.singleQuoteQuotedStrings)
			);
			// dfmt on

			static if (hasAnyQuotedString) {
				auto inQuotedString = QuotedString.none;
			}
			static if (dialect.hasFeature(Dialect.quotedStrings)) {
				if (_source[0] == '"') {
					inQuotedString = QuotedString.regular;

					// chomp quote initiator
					_source = _source[1 .. $];
				}
			}
			static if (dialect.hasFeature(Dialect.singleQuoteQuotedStrings)) {
				if (_source[0] == '\'') {
					inQuotedString = QuotedString.single;

					// chomp quote initiator
					_source = _source[1 .. $];
				}
			}
			static if (!hasAnyQuotedString) {
				enum inQuotedString = QuotedString.none;
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
					return (inQuotedString != QuotedString.none)
						? Result.regular : Result.whitespace;

				case '\x0A':
				case '\x0D':
					return (inQuotedString != QuotedString.none)
						? Result.regular : Result.endChomp;

				case '"':
					static if (dialect.hasFeature(Dialect.quotedStrings)) {
						// dfmt off
						return (inQuotedString == QuotedString.regular)
							? Result.end
							: (inQuotedString == QuotedString.single)
								? Result.regular
								: Result.endChomp;
						// dfmt on
					} else {
						return Result.regular;
					}

				case '\'':
					static if (dialect.hasFeature(Dialect.singleQuoteQuotedStrings)) {
						return (inQuotedString != QuotedString.regular)
							? Result.end : Result.regular;
					} else {
						return Result.regular;
					}

				case '#':
					if (dialect.hasFeature(Dialect.hashInlineComments)) {
						return (inQuotedString != QuotedString.none)
							? Result.regular : Result.endChomp;
					} else {
						return Result.regular;
					}

				case ';':
					if (dialect.hasFeature(Dialect.inlineComments)) {
						return (inQuotedString != QuotedString.none)
							? Result.regular : Result.endChomp;
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
						return (inQuotedString != QuotedString.none)
							? Result.regular : Result.end;
					} else {
						return Result.regular;
					}

				case ']':
					static if (tokenType == TokenType.sectionHeader) {
						return (inQuotedString != QuotedString.none)
							? Result.regular : Result.end;
					} else {
						return Result.regular;
					}
				}

				assert(false, "Bug: This should have been unreachable.");
			}

			ptrdiff_t idxLastText = -1;
			ptrdiff_t idxCutoff = -1;
			foreach (immutable idx, const c; _source) {
				const status = nextChar(c);

				if (status == Result.end) {
					if (idxLastText < 0) {
						idxLastText = (idx - 1);
					}
					break;
				} else if (status == Result.endChomp) {
					idxCutoff = idx;
					break;
				} else if (status == Result.whitespace) {
					continue;
				}

				idxLastText = idx;
			}

			const idxEOT = (idxLastText + 1);
			auto token = Token(tokenType, _source[0 .. idxEOT]);

			// "double-quote quoted": cut off any whitespace afterwards
			if (inQuotedString == QuotedString.regular) {
				const idxEOQ = (idxEOT + 1);
				if (_source.length > idxEOQ) {
					foreach (immutable idx, c; _source[idxEOQ .. $]) {
						switch (c) {
						case '\x09':
						case '\x0B':
						case '\x0C':
						case ' ':
							continue;

						default:
							// EOT because Q is cut off later
							idxCutoff = idxEOT + idx;
							break;
						}
						break;
					}
				}
			}

			const idxNextToken = (idxCutoff >= 0) ? idxCutoff : idxEOT;
			_source = _source[idxNextToken .. $];

			if (inQuotedString != QuotedString.none) {
				if (_source.length > 0) {
					// chomp quote terminator
					_source = _source[1 .. $];
				}
			}

			return token;
		}

		Token lexSubstring() {
			final switch (_locationState) {
			case LocationState.newLine:
			case LocationState.key:
				return this.lexSubstringImpl!(TokenType.key);

			case LocationState.preValue:
				_locationState = LocationState.inValue;
				goto case LocationState.inValue;

			case LocationState.inValue:
				return this.lexSubstringImpl!(TokenType.value);

			case LocationState.sectionHeader:
				return this.lexSubstringImpl!(TokenType.sectionHeader);
			}
		}

		static if (dialect.hasFeature(Dialect.concatSubstrings)) {
			Token lexSubstringsImpl(TokenType tokenType)() {
				static if (operatingMode!string == OperatingMode.mut) {
					auto originalSource = _source;
				}

				Token token = this.lexSubstringImpl!tokenType();

				auto next = this.save();
				next._bypassConcatSubstrings = true;
				next.popFront();

				static if (operatingMode!string == OperatingMode.mut) {
					import arsd.core : isSliceOf;

					if (!token.data.isSliceOf(originalSource)) {
						assert(false, "Memory corruption bug.");
					}

					const ptrdiff_t tokenDataOffset = (() @trusted => token.data.ptr - originalSource.ptr)();
					auto mutSource = originalSource[tokenDataOffset .. $];
					size_t mutOffset = token.data.length;
				}

				while (!next.empty) {
					if (next.front.type != tokenType) {
						break;
					}

					static if (operatingMode!string == OperatingMode.dup) {
						token.data ~= next.front.data;
					}
					static if (operatingMode!string == OperatingMode.mut) {
						foreach (const c; next.front.data) {
							mutSource[mutOffset] = c;
							++mutOffset;
						}
						token.data = mutSource[0 .. mutOffset];
					}

					_source = next._source;
					_locationState = next._locationState;
					next.popFront();
				}

				return token;
			}

			Token lexSubstrings() {
				final switch (_locationState) {
				case LocationState.newLine:
				case LocationState.key:
					return this.lexSubstringsImpl!(TokenType.key);

				case LocationState.preValue:
					_locationState = LocationState.inValue;
					goto case LocationState.inValue;

				case LocationState.inValue:
					return this.lexSubstringsImpl!(TokenType.value);

				case LocationState.sectionHeader:
					return this.lexSubstringsImpl!(TokenType.sectionHeader);
				}
			}
		}

		Token lexText() {
			static if (dialect.hasFeature(Dialect.concatSubstrings)) {
				if (!_bypassConcatSubstrings) {
					return this.lexSubstrings();
				}
			}

			return this.lexSubstring();
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
				if (_locationState == LocationState.inValue) {
					return this.lexText();
				}
				return this.lexWhitespace();

			case ':':
				static if (dialect.hasFeature(Dialect.colonKeys)) {
					goto case '=';
				}
				return this.lexText();

			case '=':
				_locationState = LocationState.preValue;
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
					static if (dialect.hasFeature(Dialect.hashInlineComments)) {
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

/++
	Low-level INI parser with filtered output

	This wrapper will only supply tokens of these types:

	$(LIST
		* IniTokenType.key
		* IniTokenType.value
		* IniTokenType.sectionHeader
		* IniTokenType.invalid
	)

	See_also:
		$(LIST
			* [IniParser]
			* [parseIniDocument]
			* [parseIniAA]
		)
 +/
struct IniFilteredParser(
	IniDialect dialect = IniDialect.defaults,
	string = immutable(char)[],
) {
	///
	public alias Token = IniToken!string;

	private IniParser!(dialect, string) _parser;

public @safe pure nothrow:

	///
	public this(IniParser!(dialect, string) parser) {
		_parser = parser;
	}

	///
	public this(string rawIni) {
		auto parser = IniParser!(dialect, string)(rawIni);
		this(parser);
	}

	///
	bool empty() const => _parser.empty;

	///
	inout(Token) front() inout => _parser.front;

	///
	void popFront() {
		_parser.popFront();
		_parser.skipIrrelevant(true);
	}

	///
	inout(typeof(this)) save() inout {
		return this;
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
	const myDialect = (IniDialect.defaults | IniDialect.inlineComments);

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

@safe unittest {
	static immutable rawIni = "#not-a = comment";
	auto parser = makeIniParser(rawIni);

	assert(!parser.empty);
	assert(parser.front == parser.Token(TokenType.key, "#not-a"));

	parser.popFront();
	assert(!parser.skipIrrelevant());
	assert(parser.front == parser.Token(TokenType.value, "comment"));

	parser.popFront();
	assert(parser.empty);
}

@safe unittest {
	static immutable rawIni = "#actually_a = comment\r\n\t#another one\r\n\t\t ; oh, and a third one";
	enum dialect = (Dialect.hashLineComments | Dialect.lineComments);
	auto parser = makeIniParser!dialect(rawIni);

	assert(!parser.empty);
	assert(parser.front == parser.Token(TokenType.comment, "actually_a = comment"));

	parser.popFront();
	assert(!parser.skipIrrelevant(false));
	assert(parser.front == parser.Token(TokenType.comment, "another one"));

	parser.popFront();
	assert(!parser.skipIrrelevant(false));
	assert(parser.front == parser.Token(TokenType.comment, " oh, and a third one"));

	parser.popFront();
	assert(parser.empty);
}

@safe unittest {
	static immutable rawIni = ";not a = line comment\nkey = value ;not-a-comment \nfoo = bar # not a comment\t";
	enum dialect = Dialect.lite;
	auto parser = makeIniParser!dialect(rawIni);

	{
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, ";not a"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "line comment"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front.type == TokenType.key);

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "value ;not-a-comment"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front.type == TokenType.key);

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "bar # not a comment"));
	}
}

@safe unittest {
	static immutable rawIni = "; line comment 0\t\n\nkey = value ; comment-1\nfoo = bar #comment 2\n";
	enum dialect = (Dialect.inlineComments | Dialect.hashInlineComments);
	auto parser = makeIniParser!dialect(rawIni);

	{
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.comment, " line comment 0\t"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant(false));
		assert(parser.front.type == TokenType.key);

		parser.popFront();
		assert(!parser.skipIrrelevant(false));
		assert(parser.front == parser.Token(TokenType.value, "value"));

		parser.popFront();
		assert(!parser.skipIrrelevant(false));
		assert(parser.front == parser.Token(TokenType.comment, " comment-1"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant(false));
		assert(parser.front.type == TokenType.key);

		parser.popFront();
		assert(!parser.skipIrrelevant(false));
		assert(parser.front == parser.Token(TokenType.value, "bar"));

		parser.popFront();
		assert(!parser.skipIrrelevant(false));
		assert(parser.front == parser.Token(TokenType.comment, "comment 2"));
	}

	parser.popFront();
	assert(parser.skipIrrelevant(false));
}

@safe unittest {
	static immutable rawIni = "key = value;inline";
	enum dialect = Dialect.inlineComments;
	auto parser = makeIniParser!dialect(rawIni);

	assert(!parser.empty);
	parser.front == parser.Token(TokenType.key, "key");

	parser.popFront();
	assert(!parser.skipIrrelevant(false));
	parser.front == parser.Token(TokenType.value, "value");

	parser.popFront();
	assert(!parser.skipIrrelevant(false));
	parser.front == parser.Token(TokenType.comment, "inline");

	parser.popFront();
	assert(parser.empty);
}

@safe unittest {
	static immutable rawIni = "key: value\n"
		~ "foo= bar\n"
		~ "lol :rofl\n"
		~ "Oachkatzl : -Schwoaf\n"
		~ `"Schüler:innen": 10`;
	enum dialect = (Dialect.colonKeys | Dialect.quotedStrings);
	auto parser = makeIniParser!dialect(rawIni);

	{
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "key"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "value"));

	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.key, "foo"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "bar"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.key, "lol"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "rofl"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.key, "Oachkatzl"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "-Schwoaf"));
	}

	{
		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.key, "Schüler:innen"));

		parser.popFront();
		assert(!parser.skipIrrelevant());
		assert(parser.front == parser.Token(TokenType.value, "10"));
	}

	parser.popFront();
	assert(parser.skipIrrelevant());
}

@safe unittest {
	static immutable rawIni =
		"\"foo=bar\"=foobar\n"
		~ "'foo = bar' = foo_bar\n"
		~ "foo = \"bar\"\n"
		~ "foo = 'bar'\n"
		~ "foo = ' bar '\n"
		~ "foo = \" bar \"\n"
		~ "multi_line = 'line1\nline2'\n"
		~ "syntax = \"error";
	enum dialect = (Dialect.quotedStrings | Dialect.singleQuoteQuotedStrings);
	auto parser = makeIniFilteredParser!dialect(rawIni);

	{
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "foo=bar"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, "foobar"));

	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "foo = bar"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, "foo_bar"));
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "foo"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, "bar"));
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "foo"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, "bar"));
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "foo"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, " bar "));
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "foo"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, " bar "));
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "multi_line"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, "line1\nline2"));
	}

	{
		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.key, "syntax"));

		parser.popFront();
		assert(!parser.empty);
		assert(parser.front == parser.Token(TokenType.value, "error"));
	}

	parser.popFront();
	assert(parser.empty);
}

/++
	Convenience function to create a low-level parser

	$(TIP
		Unlike with the constructor of [IniParser],
		the compiler is able to infer the `string` template parameter.
	)

	See_also:
		[makeIniFilteredParser]
 +/
IniParser!(dialect, string) makeIniParser(
	IniDialect dialect = IniDialect.defaults,
	string,
)(
	string rawIni,
) @safe pure nothrow if (isCompatibleString!string) {
	return IniParser!(dialect, string)(rawIni);
}

///
@safe unittest {
	string regular;
	auto parser1 = makeIniParser(regular);
	assert(parser1.empty); // exclude from docs

	char[] mutable;
	auto parser2 = makeIniParser(mutable);
	assert(parser2.empty); // exclude from docs

	const(char)[] constChars;
	auto parser3 = makeIniParser(constChars);
	assert(parser3.empty); // exclude from docs
}

/++
	Convenience function to create a low-level filtered parser

	$(TIP
		Unlike with the constructor of [IniFilteredParser],
		the compiler is able to infer the `string` template parameter.
	)

	See_also:
		[makeIniParser]
 +/
IniFilteredParser!(dialect, string) makeIniFilteredParser(
	IniDialect dialect = IniDialect.defaults,
	string,
)(
	string rawIni,
) @safe pure nothrow if (isCompatibleString!string) {
	return IniFilteredParser!(dialect, string)(rawIni);
}

///
@safe unittest {
	string regular;
	auto parser1 = makeIniFilteredParser(regular);
	assert(parser1.empty); // exclude from docs

	char[] mutable;
	auto parser2 = makeIniFilteredParser(mutable);
	assert(parser2.empty); // exclude from docs

	const(char)[] constChars;
	auto parser3 = makeIniFilteredParser(constChars);
	assert(parser3.empty); // exclude from docs
}

// undocumented
debug {
	void writelnTokens(IniDialect dialect, string)(IniParser!(dialect, string) parser) @safe {
		import std.stdio : writeln;

		foreach (token; parser) {
			writeln(token);
		}
	}

	void writelnTokens(IniDialect dialect, string)(IniFilteredParser!(dialect, string) parser) @safe {
		import std.stdio : writeln;

		foreach (token; parser) {
			writeln(token);
		}
	}
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

@safe unittest {
	static immutable demoData = `
0 = a 'b'
1 = a "b"
2 = 'a' b
3 = "a" b
`;

	enum dialect = (Dialect.concatSubstrings | Dialect.quotedStrings | Dialect.singleQuoteQuotedStrings);
	auto doc = parseIniDocument!dialect(demoData);
	assert(doc.sections[0].items[0].value == "a b");
	assert(doc.sections[0].items[1].value == "ab");
	assert(doc.sections[0].items[2].value == "a b");
	assert(doc.sections[0].items[3].value == "ab");
}

/++
	Parses an INI string into an associate array.

	$(LIST
		* Duplicate keys cause values to get overwritten.
		* Sections with the same name are merged.
	)

	See_also:
		[parseIniDocument]
 +/
string[string][string] parseIniAA(IniDialect dialect = IniDialect.defaults, string)(string rawIni) @safe pure nothrow {
	static if (is(string == immutable(char)[])) {
		immutable(char)[] toString(string key) => key;
	} else {
		immutable(char)[] toString(string key) => key.idup;
	}

	auto parser = IniParser!(dialect, string)(rawIni);

	string[string][string] document;
	string[string] section;

	string sectionName = null;
	string keyName = null;
	string value = null;

	void commitKeyValuePair(string nextKey) {
		if (keyName !is null) {
			section[toString(keyName)] = value;
		}

		keyName = nextKey;
		value = null;
	}

	void setValue(string nextValue) {
		value = nextValue;
	}

	void commitSection(string nextSection) {
		commitKeyValuePair(null);
		if ((sectionName !is null) || (section.length > 0)) {
			document[toString(sectionName)] = section;
			section = null;
		}

		if (nextSection !is null) {
			auto existingSection = nextSection in document;
			if (existingSection !is null) {
				section = *existingSection;
			}

			sectionName = nextSection;
		}
	}

	while (!parser.skipIrrelevant()) {
		switch (parser.front.type) with (TokenType) {

		case key:
			commitKeyValuePair(parser.front.data);
			break;

		case value:
			setValue(parser.front.data);
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

@safe unittest {
	static immutable demoData = `[1]
key = "value1" "value2"
[2]
0 = a b
1 = 'a' b
2 = a 'b'
3 = a "b"
4 = "a" 'b'
5 = 'a' "b"
6 = "a" "b"
7 = 'a' 'b'
8 = 'a' "b" 'c'
`;

	enum dialect = (Dialect.concatSubstrings | Dialect.quotedStrings | Dialect.singleQuoteQuotedStrings);
	auto aa = parseIniAA!(dialect, char[])(demoData.dup);

	assert(aa.length == 2);
	assert(!(null in aa));
	assert("1" in aa);
	assert("2" in aa);
	assert(aa["1"]["key"] == "value1value2");
	assert(aa["2"]["0"] == "a b");
	assert(aa["2"]["1"] == "a b");
	assert(aa["2"]["2"] == "a b");
	assert(aa["2"]["3"] == "ab");
	assert(aa["2"]["4"] == "ab");
	assert(aa["2"]["5"] == "ab");
	assert(aa["2"]["6"] == "ab");
	assert(aa["2"]["7"] == "a b");
	assert(aa["2"]["8"] == "abc");
}

@safe unittest {
	static immutable string demoData = `[1]
key = "value1" "value2"
[2]
0 = a b
1 = 'a' b
2 = a 'b'
3 = a "b"
4 = "a" 'b'
5 = 'a' "b"
6 = "a" "b"
7 = 'a' 'b'
8 = 'a' "b" 'c'
`;

	enum dialect = (Dialect.concatSubstrings | Dialect.quotedStrings | Dialect.singleQuoteQuotedStrings);
	auto aa = parseIniAA!dialect(demoData);

	assert(aa.length == 2);
	assert(!(null in aa));
	assert("1" in aa);
	assert("2" in aa);
	assert(aa["1"]["key"] == "value1value2");
	assert(aa["2"]["0"] == "a b");
	assert(aa["2"]["1"] == "a b");
	assert(aa["2"]["2"] == "a b");
	assert(aa["2"]["3"] == "ab");
	assert(aa["2"]["4"] == "ab");
	assert(aa["2"]["5"] == "ab");
	assert(aa["2"]["6"] == "ab");
	assert(aa["2"]["7"] == "a b");
	assert(aa["2"]["8"] == "abc");
}

@safe unittest {
	static immutable string demoData = `
0 = "a" b
1 = "a" 'b'
2 = a "b"
3 = 'a' "b"
`;

	enum dialect = (Dialect.concatSubstrings | Dialect.singleQuoteQuotedStrings);
	auto aa = parseIniAA!dialect(demoData);

	assert(aa.length == 1);
	assert(aa[null]["0"] == `"a" b`);
	assert(aa[null]["1"] == `"a" b`);
	assert(aa[null]["2"] == `a "b"`);
	assert(aa[null]["3"] == `a "b"`);
}

@safe unittest {
	static immutable const(char)[] demoData = `[1]
key = original
no2 = kept
[2]
key = original
key = overwritten
[1]
key = merged and overwritten
`;

	enum dialect = Dialect.concatSubstrings;
	auto aa = parseIniAA!dialect(demoData);

	assert(aa.length == 2);
	assert(!(null in aa));
	assert("1" in aa);
	assert("2" in aa);
	assert(aa["1"]["key"] == "merged and overwritten");
	assert(aa["1"]["no2"] == "kept");
	assert(aa["2"]["key"] == "overwritten");
}
