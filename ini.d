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
		Token front() inout {
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
		typeof(this) save() inout {
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

@safe unittest {

	static immutable document = `; This is a comment.
[section1]
s1key1 = value1
s1key2 = value2

; Another comment

[section no.2]
s2key1  = "value3"
s2key2	 =	 value no.4
`;

	auto parser = IniParser!()(document);
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
