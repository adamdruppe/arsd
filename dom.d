// FIXME: add classList. it is a live list and removes whitespace and duplicates when you use it.
// FIXME: xml namespace support???
// FIXME: https://developer.mozilla.org/en-US/docs/Web/API/Element/insertAdjacentHTML
// FIXME: parentElement is parentNode that skips DocumentFragment etc but will be hard to work in with my compatibility...

// FIXME: the scriptable list is quite arbitrary


// xml entity references?!

/++
	This is an html DOM implementation, started with cloning
	what the browser offers in Javascript, but going well beyond
	it in convenience.

	If you can do it in Javascript, you can probably do it with
	this module, and much more.

	---
	import arsd.dom;

	void main() {
		auto document = new Document("<html><p>paragraph</p></html>");
		writeln(document.querySelector("p"));
		document.root.innerHTML = "<p>hey</p>";
		writeln(document);
	}
	---

	BTW: this file optionally depends on `arsd.characterencodings`, to
	help it correctly read files from the internet. You should be able to
	get characterencodings.d from the same place you got this file.

	If you want it to stand alone, just always use the `Document.parseUtf8`
	function or the constructor that takes a string.

	Symbol_groups:

	core_functionality =

	These members provide core functionality. The members on these classes
	will provide most your direct interaction.

	bonus_functionality =

	These provide additional functionality for special use cases.

	implementations =

	These provide implementations of other functionality.
+/
module arsd.dom;

// FIXME: support the css standard namespace thing in the selectors too

version(with_arsd_jsvar)
	import arsd.jsvar;
else {
	enum scriptable = "arsd_jsvar_compatible";
}

// this is only meant to be used at compile time, as a filter for opDispatch
// lists the attributes we want to allow without the use of .attr
bool isConvenientAttribute(string name) {
	static immutable list = [
		"name", "id", "href", "value",
		"checked", "selected", "type",
		"src", "content", "pattern",
		"placeholder", "required", "alt",
		"rel",
		"method", "action", "enctype"
	];
	foreach(l; list)
		if(name == l) return true;
	return false;
}


// FIXME: something like <ol>spam <ol> with no closing </ol> should read the second tag as the closer in garbage mode
// FIXME: failing to close a paragraph sometimes messes things up too

// FIXME: it would be kinda cool to have some support for internal DTDs
// and maybe XPath as well, to some extent
/*
	we could do
	meh this sux

	auto xpath = XPath(element);

	     // get the first p
	xpath.p[0].a["href"]
*/


/// The main document interface, including a html parser.
/// Group: core_functionality
class Document : FileResource {
	/// Convenience method for web scraping. Requires [arsd.http2] to be
	/// included in the build as well as [arsd.characterencodings].
	static Document fromUrl()(string url, bool strictMode = false) {
		import arsd.http2;
		auto client = new HttpClient();

		auto req = client.navigateTo(Uri(url), HttpVerb.GET);
		auto res = req.waitForCompletion();

		auto document = new Document();
		if(strictMode) {
			document.parse(cast(string) res.content, true, true, res.contentTypeCharset);
		} else {
			document.parseGarbage(cast(string) res.content);
		}

		return document;
	}

	///.
	this(string data, bool caseSensitive = false, bool strict = false) {
		parseUtf8(data, caseSensitive, strict);
	}

	/**
		Creates an empty document. It has *nothing* in it at all.
	*/
	this() {

	}

	/// This is just something I'm toying with. Right now, you use opIndex to put in css selectors.
	/// It returns a struct that forwards calls to all elements it holds, and returns itself so you
	/// can chain it.
	///
	/// Example: document["p"].innerText("hello").addClass("modified");
	///
	/// Equivalent to: foreach(e; document.getElementsBySelector("p")) { e.innerText("hello"); e.addClas("modified"); }
	///
	/// Note: always use function calls (not property syntax) and don't use toString in there for best results.
	///
	/// You can also do things like: document["p"]["b"] though tbh I'm not sure why since the selector string can do all that anyway. Maybe
	/// you could put in some kind of custom filter function tho.
	ElementCollection opIndex(string selector) {
		auto e = ElementCollection(this.root);
		return e[selector];
	}

	string _contentType = "text/html; charset=utf-8";

	/// If you're using this for some other kind of XML, you can
	/// set the content type here.
	///
	/// Note: this has no impact on the function of this class.
	/// It is only used if the document is sent via a protocol like HTTP.
	///
	/// This may be called by parse() if it recognizes the data. Otherwise,
	/// if you don't set it, it assumes text/html; charset=utf-8.
	@property string contentType(string mimeType) {
		_contentType = mimeType;
		return _contentType;
	}

	/// implementing the FileResource interface, useful for sending via
	/// http automatically.
	@property string filename() const { return null; }

	/// implementing the FileResource interface, useful for sending via
	/// http automatically.
	override @property string contentType() const {
		return _contentType;
	}

	/// implementing the FileResource interface; it calls toString.
	override immutable(ubyte)[] getData() const {
		return cast(immutable(ubyte)[]) this.toString();
	}


	/// Concatenates any consecutive text nodes
	/*
	void normalize() {

	}
	*/

	/// This will set delegates for parseSaw* (note: this overwrites anything else you set, and you setting subsequently will overwrite this) that add those things to the dom tree when it sees them.
	/// Call this before calling parse().

	/// Note this will also preserve the prolog and doctype from the original file, if there was one.
	void enableAddingSpecialTagsToDom() {
		parseSawComment = (string) => true;
		parseSawAspCode = (string) => true;
		parseSawPhpCode = (string) => true;
		parseSawQuestionInstruction = (string) => true;
		parseSawBangInstruction = (string) => true;
	}

	/// If the parser sees a html comment, it will call this callback
	/// <!-- comment --> will call parseSawComment(" comment ")
	/// Return true if you want the node appended to the document.
	bool delegate(string) parseSawComment;

	/// If the parser sees <% asp code... %>, it will call this callback.
	/// It will be passed "% asp code... %" or "%= asp code .. %"
	/// Return true if you want the node appended to the document.
	bool delegate(string) parseSawAspCode;

	/// If the parser sees <?php php code... ?>, it will call this callback.
	/// It will be passed "?php php code... ?" or "?= asp code .. ?"
	/// Note: dom.d cannot identify  the other php <? code ?> short format.
	/// Return true if you want the node appended to the document.
	bool delegate(string) parseSawPhpCode;

	/// if it sees a <?xxx> that is not php or asp
	/// it calls this function with the contents.
	/// <?SOMETHING foo> calls parseSawQuestionInstruction("?SOMETHING foo")
	/// Unlike the php/asp ones, this ends on the first > it sees, without requiring ?>.
	/// Return true if you want the node appended to the document.
	bool delegate(string) parseSawQuestionInstruction;

	/// if it sees a <! that is not CDATA or comment (CDATA is handled automatically and comments call parseSawComment),
	/// it calls this function with the contents.
	/// <!SOMETHING foo> calls parseSawBangInstruction("SOMETHING foo")
	/// Return true if you want the node appended to the document.
	bool delegate(string) parseSawBangInstruction;

	/// Given the kind of garbage you find on the Internet, try to make sense of it.
	/// Equivalent to document.parse(data, false, false, null);
	/// (Case-insensitive, non-strict, determine character encoding from the data.)

	/// NOTE: this makes no attempt at added security.
	///
	/// It is a template so it lazily imports characterencodings.
	void parseGarbage()(string data) {
		parse(data, false, false, null);
	}

	/// Parses well-formed UTF-8, case-sensitive, XML or XHTML
	/// Will throw exceptions on things like unclosed tags.
	void parseStrict(string data) {
		parseStream(toUtf8Stream(data), true, true);
	}

	/// Parses well-formed UTF-8 in loose mode (by default). Tries to correct
	/// tag soup, but does NOT try to correct bad character encodings.
	///
	/// They will still throw an exception.
	void parseUtf8(string data, bool caseSensitive = false, bool strict = false) {
		parseStream(toUtf8Stream(data), caseSensitive, strict);
	}

	// this is a template so we get lazy import behavior
	Utf8Stream handleDataEncoding()(in string rawdata, string dataEncoding, bool strict) {
		import arsd.characterencodings;
		// gotta determine the data encoding. If you know it, pass it in above to skip all this.
		if(dataEncoding is null) {
			dataEncoding = tryToDetermineEncoding(cast(const(ubyte[])) rawdata);
			// it can't tell... probably a random 8 bit encoding. Let's check the document itself.
			// Now, XML and HTML can both list encoding in the document, but we can't really parse
			// it here without changing a lot of code until we know the encoding. So I'm going to
			// do some hackish string checking.
			if(dataEncoding is null) {
				auto dataAsBytes = cast(immutable(ubyte)[]) rawdata;
				// first, look for an XML prolog
				auto idx = indexOfBytes(dataAsBytes, cast(immutable ubyte[]) "encoding=\"");
				if(idx != -1) {
					idx += "encoding=\"".length;
					// we're probably past the prolog if it's this far in; we might be looking at
					// content. Forget about it.
					if(idx > 100)
						idx = -1;
				}
				// if that fails, we're looking for Content-Type http-equiv or a meta charset (see html5)..
				if(idx == -1) {
					idx = indexOfBytes(dataAsBytes, cast(immutable ubyte[]) "charset=");
					if(idx != -1) {
						idx += "charset=".length;
						if(dataAsBytes[idx] == '"')
							idx++;
					}
				}

				// found something in either branch...
				if(idx != -1) {
					// read till a quote or about 12 chars, whichever comes first...
					auto end = idx;
					while(end < dataAsBytes.length && dataAsBytes[end] != '"' && end - idx < 12)
						end++;

					dataEncoding = cast(string) dataAsBytes[idx .. end];
				}
				// otherwise, we just don't know.
			}
		}

		if(dataEncoding is null) {
			if(strict)
				throw new MarkupException("I couldn't figure out the encoding of this document.");
			else
			// if we really don't know by here, it means we already tried UTF-8,
			// looked for utf 16 and 32 byte order marks, and looked for xml or meta
			// tags... let's assume it's Windows-1252, since that's probably the most
			// common aside from utf that wouldn't be labeled.

			dataEncoding = "Windows 1252";
		}

		// and now, go ahead and convert it.

		string data;

		if(!strict) {
			// if we're in non-strict mode, we need to check
			// the document for mislabeling too; sometimes
			// web documents will say they are utf-8, but aren't
			// actually properly encoded. If it fails to validate,
			// we'll assume it's actually Windows encoding - the most
			// likely candidate for mislabeled garbage.
			dataEncoding = dataEncoding.toLower();
			dataEncoding = dataEncoding.replace(" ", "");
			dataEncoding = dataEncoding.replace("-", "");
			dataEncoding = dataEncoding.replace("_", "");
			if(dataEncoding == "utf8") {
				try {
					validate(rawdata);
				} catch(UTFException e) {
					dataEncoding = "Windows 1252";
				}
			}
		}

		if(dataEncoding != "UTF-8") {
			if(strict)
				data = convertToUtf8(cast(immutable(ubyte)[]) rawdata, dataEncoding);
			else {
				try {
					data = convertToUtf8(cast(immutable(ubyte)[]) rawdata, dataEncoding);
				} catch(Exception e) {
					data = convertToUtf8(cast(immutable(ubyte)[]) rawdata, "Windows 1252");
				}
			}
		} else
			data = rawdata;

		return toUtf8Stream(data);
	}

	private
	Utf8Stream toUtf8Stream(in string rawdata) {
		string data = rawdata;
		static if(is(Utf8Stream == string))
			return data;
		else
			return new Utf8Stream(data);
	}

	/++
		List of elements that can be assumed to be self-closed
		in this document. The default for a Document are a hard-coded
		list of ones appropriate for HTML. For [XmlDocument], it defaults
		to empty. You can modify this after construction but before parsing.

		History:
			Added February 8, 2021 (included in dub release 9.2)
	+/
	string[] selfClosedElements = htmlSelfClosedElements;

	/**
		Take XMLish data and try to make the DOM tree out of it.

		The goal isn't to be perfect, but to just be good enough to
		approximate Javascript's behavior.

		If strict, it throws on something that doesn't make sense.
		(Examples: mismatched tags. It doesn't validate!)
		If not strict, it tries to recover anyway, and only throws
		when something is REALLY unworkable.

		If strict is false, it uses a magic list of tags that needn't
		be closed. If you are writing a document specifically for this,
		try to avoid such - use self closed tags at least. Easier to parse.

		The dataEncoding argument can be used to pass a specific
		charset encoding for automatic conversion. If null (which is NOT
		the default!), it tries to determine from the data itself,
		using the xml prolog or meta tags, and assumes UTF-8 if unsure.

		If this assumption is wrong, it can throw on non-ascii
		characters!


		Note that it previously assumed the data was encoded as UTF-8, which
		is why the dataEncoding argument defaults to that.

		So it shouldn't break backward compatibility.

		But, if you want the best behavior on wild data - figuring it out from the document
		instead of assuming - you'll probably want to change that argument to null.

		This is a template so it lazily imports arsd.characterencodings, which is required
		to fix up data encodings.

		If you are sure the encoding is good, try parseUtf8 or parseStrict to avoid the
		dependency. If it is data from the Internet though, a random website, the encoding
		is often a lie. This function, if dataEncoding == null, can correct for that, or
		you can try parseGarbage. In those cases, arsd.characterencodings is required to
		compile.
	*/
	void parse()(in string rawdata, bool caseSensitive = false, bool strict = false, string dataEncoding = "UTF-8") {
		auto data = handleDataEncoding(rawdata, dataEncoding, strict);
		parseStream(data, caseSensitive, strict);
	}

	// note: this work best in strict mode, unless data is just a simple string wrapper
	void parseStream(Utf8Stream data, bool caseSensitive = false, bool strict = false) {
		// FIXME: this parser could be faster; it's in the top ten biggest tree times according to the profiler
		// of my big app.

		assert(data !is null);

		// go through character by character.
		// if you see a <, consider it a tag.
		// name goes until the first non tagname character
		// then see if it self closes or has an attribute

		// if not in a tag, anything not a tag is a big text
		// node child. It ends as soon as it sees a <

		// Whitespace in text or attributes is preserved, but not between attributes

		// &amp; and friends are converted when I know them, left the same otherwise


		// this it should already be done correctly.. so I'm leaving it off to net a ~10% speed boost on my typical test file (really)
		//validate(data); // it *must* be UTF-8 for this to work correctly

		sizediff_t pos = 0;

		clear();

		loose = !caseSensitive;

		bool sawImproperNesting = false;
		bool paragraphHackfixRequired = false;

		int getLineNumber(sizediff_t p) {
			int line = 1;
			foreach(c; data[0..p])
				if(c == '\n')
					line++;
			return line;
		}

		void parseError(string message) {
			throw new MarkupException(format("char %d (line %d): %s", pos, getLineNumber(pos), message));
		}

		bool eatWhitespace() {
			bool ateAny = false;
			while(pos < data.length && data[pos].isSimpleWhite) {
				pos++;
				ateAny = true;
			}
			return ateAny;
		}

		string readTagName() {
			// remember to include : for namespaces
			// basically just keep going until >, /, or whitespace
			auto start = pos;
			while(data[pos] != '>' && data[pos] != '/' && !data[pos].isSimpleWhite)
			{
				pos++;
				if(pos == data.length) {
					if(strict)
						throw new Exception("tag name incomplete when file ended");
					else
						break;
				}
			}

			if(!caseSensitive)
				return toLower(data[start..pos]);
			else
				return data[start..pos];
		}

		string readAttributeName() {
			// remember to include : for namespaces
			// basically just keep going until >, /, or whitespace
			auto start = pos;
			while(data[pos] != '>' && data[pos] != '/'  && data[pos] != '=' && !data[pos].isSimpleWhite)
			{
				if(data[pos] == '<') {
					if(strict)
						throw new MarkupException("The character < can never appear in an attribute name. Line " ~ to!string(getLineNumber(pos)));
					else
						break; // e.g. <a href="something" <img src="poo" /></a>. The > should have been after the href, but some shitty files don't do that right and the browser handles it, so we will too, by pretending the > was indeed there
				}
				pos++;
				if(pos == data.length) {
					if(strict)
						throw new Exception("unterminated attribute name");
					else
						break;
				}
			}

			if(!caseSensitive)
				return toLower(data[start..pos]);
			else
				return data[start..pos];
		}

		string readAttributeValue() {
			if(pos >= data.length) {
				if(strict)
					throw new Exception("no attribute value before end of file");
				else
					return null;
			}
			switch(data[pos]) {
				case '\'':
				case '"':
					auto started = pos;
					char end = data[pos];
					pos++;
					auto start = pos;
					while(pos < data.length && data[pos] != end)
						pos++;
					if(strict && pos == data.length)
						throw new MarkupException("Unclosed attribute value, started on char " ~ to!string(started));
					string v = htmlEntitiesDecode(data[start..pos], strict);
					pos++; // skip over the end
				return v;
				default:
					if(strict)
						parseError("Attributes must be quoted");
					// read until whitespace or terminator (/> or >)
					auto start = pos;
					while(
						pos < data.length &&
						data[pos] != '>' &&
						// unquoted attributes might be urls, so gotta be careful with them and self-closed elements
						!(data[pos] == '/' && pos + 1 < data.length && data[pos+1] == '>') &&
						!data[pos].isSimpleWhite)
							pos++;

					string v = htmlEntitiesDecode(data[start..pos], strict);
					// don't skip the end - we'll need it later
					return v;
			}
		}

		TextNode readTextNode() {
			auto start = pos;
			while(pos < data.length && data[pos] != '<') {
				pos++;
			}

			return TextNode.fromUndecodedString(this, data[start..pos]);
		}

		// this is obsolete!
		RawSource readCDataNode() {
			auto start = pos;
			while(pos < data.length && data[pos] != '<') {
				pos++;
			}

			return new RawSource(this, data[start..pos]);
		}


		struct Ele {
			int type; // element or closing tag or nothing
				/*
					type == 0 means regular node, self-closed (element is valid)
					type == 1 means closing tag (payload is the tag name, element may be valid)
					type == 2 means you should ignore it completely
					type == 3 means it is a special element that should be appended, if possible, e.g. a <!DOCTYPE> that was chosen to be kept, php code, or comment. It will be appended at the current element if inside the root, and to a special document area if not
					type == 4 means the document was totally empty
				*/
			Element element; // for type == 0 or type == 3
			string payload; // for type == 1
		}
		// recursively read a tag
		Ele readElement(string[] parentChain = null) {
			// FIXME: this is the slowest function in this module, by far, even in strict mode.
			// Loose mode should perform decently, but strict mode is the important one.
			if(!strict && parentChain is null)
				parentChain = [];

			static string[] recentAutoClosedTags;

			if(pos >= data.length)
			{
				if(strict) {
					throw new MarkupException("Gone over the input (is there no root element or did it never close?), chain: " ~ to!string(parentChain));
				} else {
					if(parentChain.length)
						return Ele(1, null, parentChain[0]); // in loose mode, we just assume the document has ended
					else
						return Ele(4); // signal emptiness upstream
				}
			}

			if(data[pos] != '<') {
				return Ele(0, readTextNode(), null);
			}

			enforce(data[pos] == '<');
			pos++;
			if(pos == data.length) {
				if(strict)
					throw new MarkupException("Found trailing < at end of file");
				// if not strict, we'll just skip the switch
			} else
			switch(data[pos]) {
				// I don't care about these, so I just want to skip them
				case '!': // might be a comment, a doctype, or a special instruction
					pos++;

						// FIXME: we should store these in the tree too
						// though I like having it stripped out tbh.

					if(pos == data.length) {
						if(strict)
							throw new MarkupException("<! opened at end of file");
					} else if(data[pos] == '-' && (pos + 1 < data.length) && data[pos+1] == '-') {
						// comment
						pos += 2;

						// FIXME: technically, a comment is anything
						// between -- and -- inside a <!> block.
						// so in <!-- test -- lol> , the " lol" is NOT a comment
						// and should probably be handled differently in here, but for now
						// I'll just keep running until --> since that's the common way

						auto commentStart = pos;
						while(pos+3 < data.length && data[pos..pos+3] != "-->")
							pos++;

						auto end = commentStart;

						if(pos + 3 >= data.length) {
							if(strict)
								throw new MarkupException("unclosed comment");
							end = data.length;
							pos = data.length;
						} else {
							end = pos;
							assert(data[pos] == '-');
							pos++;
							assert(data[pos] == '-');
							pos++;
							assert(data[pos] == '>');
							pos++;
						}

						if(parseSawComment !is null)
							if(parseSawComment(data[commentStart .. end])) {
								return Ele(3, new HtmlComment(this, data[commentStart .. end]), null);
							}
					} else if(pos + 7 <= data.length && data[pos..pos + 7] == "[CDATA[") {
						pos += 7;

						auto cdataStart = pos;

						ptrdiff_t end = -1;
						typeof(end) cdataEnd;

						if(pos < data.length) {
							// cdata isn't allowed to nest, so this should be generally ok, as long as it is found
							end = data[pos .. $].indexOf("]]>");
						}

						if(end == -1) {
							if(strict)
								throw new MarkupException("Unclosed CDATA section");
							end = pos;
							cdataEnd = pos;
						} else {
							cdataEnd = pos + end;
							pos = cdataEnd + 3;
						}

						return Ele(0, new TextNode(this, data[cdataStart .. cdataEnd]), null);
					} else {
						auto start = pos;
						while(pos < data.length && data[pos] != '>')
							pos++;

						auto bangEnds = pos;
						if(pos == data.length) {
							if(strict)
								throw new MarkupException("unclosed processing instruction (<!xxx>)");
						} else pos++; // skipping the >

						if(parseSawBangInstruction !is null)
							if(parseSawBangInstruction(data[start .. bangEnds])) {
								// FIXME: these should be able to modify the parser state,
								// doing things like adding entities, somehow.

								return Ele(3, new BangInstruction(this, data[start .. bangEnds]), null);
							}
					}

					/*
					if(pos < data.length && data[pos] == '>')
						pos++; // skip the >
					else
						assert(!strict);
					*/
				break;
				case '%':
				case '?':
					/*
						Here's what we want to support:

						<% asp code %>
						<%= asp code %>
						<?php php code ?>
						<?= php code ?>

						The contents don't really matter, just if it opens with
						one of the above for, it ends on the two char terminator.

						<?something>
							this is NOT php code
							because I've seen this in the wild: <?EM-dummyText>

							This could be php with shorttags which would be cut off
							prematurely because if(a >) - that > counts as the close
							of the tag, but since dom.d can't tell the difference
							between that and the <?EM> real world example, it will
							not try to look for the ?> ending.

						The difference between this and the asp/php stuff is that it
						ends on >, not ?>. ONLY <?php or <?= ends on ?>. The rest end
						on >.
					*/

					char end = data[pos];
					auto started = pos;
					bool isAsp = end == '%';
					int currentIndex = 0;
					bool isPhp = false;
					bool isEqualTag = false;
					int phpCount = 0;

				    more:
					pos++; // skip the start
					if(pos == data.length) {
						if(strict)
							throw new MarkupException("Unclosed <"~end~" by end of file");
					} else {
						currentIndex++;
						if(currentIndex == 1 && data[pos] == '=') {
							if(!isAsp)
								isPhp = true;
							isEqualTag = true;
							goto more;
						}
						if(currentIndex == 1 && data[pos] == 'p')
							phpCount++;
						if(currentIndex == 2 && data[pos] == 'h')
							phpCount++;
						if(currentIndex == 3 && data[pos] == 'p' && phpCount == 2)
							isPhp = true;

						if(data[pos] == '>') {
							if((isAsp || isPhp) && data[pos - 1] != end)
								goto more;
							// otherwise we're done
						} else
							goto more;
					}

					//writefln("%s: %s", isAsp ? "ASP" : isPhp ? "PHP" : "<? ", data[started .. pos]);
					auto code = data[started .. pos];


					assert((pos < data.length && data[pos] == '>') || (!strict && pos == data.length));
					if(pos < data.length)
						pos++; // get past the >

					if(isAsp && parseSawAspCode !is null) {
						if(parseSawAspCode(code)) {
							return Ele(3, new AspCode(this, code), null);
						}
					} else if(isPhp && parseSawPhpCode !is null) {
						if(parseSawPhpCode(code)) {
							return Ele(3, new PhpCode(this, code), null);
						}
					} else if(!isAsp && !isPhp && parseSawQuestionInstruction !is null) {
						if(parseSawQuestionInstruction(code)) {
							return Ele(3, new QuestionInstruction(this, code), null);
						}
					}
				break;
				case '/': // closing an element
					pos++; // skip the start
					auto p = pos;
					while(pos < data.length && data[pos] != '>')
						pos++;
					//writefln("</%s>", data[p..pos]);
					if(pos == data.length && data[pos-1] != '>') {
						if(strict)
							throw new MarkupException("File ended before closing tag had a required >");
						else
							data ~= ">"; // just hack it in
					}
					pos++; // skip the '>'

					string tname = data[p..pos-1];
					if(!caseSensitive)
						tname = tname.toLower();

				return Ele(1, null, tname); // closing tag reports itself here
				case ' ': // assume it isn't a real element...
					if(strict) {
						parseError("bad markup - improperly placed <");
						assert(0); // parseError always throws
					} else
						return Ele(0, TextNode.fromUndecodedString(this, "<"), null);
				default:

					if(!strict) {
						// what about something that kinda looks like a tag, but isn't?
						auto nextTag = data[pos .. $].indexOf("<");
						auto closeTag = data[pos .. $].indexOf(">");
						if(closeTag != -1 && nextTag != -1)
							if(nextTag < closeTag) {
								// since attribute names cannot possibly have a < in them, we'll look for an equal since it might be an attribute value... and even in garbage mode, it'd have to be a quoted one realistically

								auto equal = data[pos .. $].indexOf("=\"");
								if(equal != -1 && equal < closeTag) {
									// this MIGHT be ok, soldier on
								} else {
									// definitely no good, this must be a (horribly distorted) text node
									pos++; // skip the < we're on - don't want text node to end prematurely
									auto node = readTextNode();
									node.contents = "<" ~ node.contents; // put this back
									return Ele(0, node, null);
								}
							}
					}

					string tagName = readTagName();
					string[string] attributes;

					Ele addTag(bool selfClosed) {
						if(selfClosed)
							pos++;
						else {
							if(!strict)
								if(tagName.isInArray(selfClosedElements))
									// these are de-facto self closed
									selfClosed = true;
						}

						import std.algorithm.comparison;

						if(strict) {
						enforce(data[pos] == '>', format("got %s when expecting > (possible missing attribute name)\nContext:\n%s", data[pos], data[max(0, pos - 100) .. min(data.length, pos + 100)]));
						} else {
							// if we got here, it's probably because a slash was in an
							// unquoted attribute - don't trust the selfClosed value
							if(!selfClosed)
								selfClosed = tagName.isInArray(selfClosedElements);

							while(pos < data.length && data[pos] != '>')
								pos++;

							if(pos >= data.length) {
								// the tag never closed
								assert(data.length != 0);
								pos = data.length - 1; // rewinding so it hits the end at the bottom..
							}
						}

						auto whereThisTagStarted = pos; // for better error messages

						pos++;

						auto e = createElement(tagName);
						e.attributes = attributes;
						version(dom_node_indexes) {
							if(e.dataset.nodeIndex.length == 0)
								e.dataset.nodeIndex = to!string(&(e.attributes));
						}
						e.selfClosed = selfClosed;
						e.parseAttributes();


						// HACK to handle script and style as a raw data section as it is in HTML browsers
						if(tagName == "script" || tagName == "style") {
							if(!selfClosed) {
								string closer = "</" ~ tagName ~ ">";
								ptrdiff_t ending;
								if(pos >= data.length)
									ending = -1;
								else
									ending = indexOf(data[pos..$], closer);

								ending = indexOf(data[pos..$], closer, 0, (loose ? CaseSensitive.no : CaseSensitive.yes));
								/*
								if(loose && ending == -1 && pos < data.length)
									ending = indexOf(data[pos..$], closer.toUpper());
								*/
								if(ending == -1) {
									if(strict)
										throw new Exception("tag " ~ tagName ~ " never closed");
									else {
										// let's call it totally empty and do the rest of the file as text. doing it as html could still result in some weird stuff like if(a<4) being read as <4 being a tag so it comes out if(a<4></4> and other weirdness) It is either a closed script tag or the rest of the file is forfeit.
										if(pos < data.length) {
											e = new TextNode(this, data[pos .. $]);
											pos = data.length;
										}
									}
								} else {
									ending += pos;
									e.innerRawSource = data[pos..ending];
									pos = ending + closer.length;
								}
							}
							return Ele(0, e, null);
						}

						bool closed = selfClosed;

						void considerHtmlParagraphHack(Element n) {
							assert(!strict);
							if(e.tagName == "p" && e.tagName == n.tagName) {
								// html lets you write <p> para 1 <p> para 1
								// but in the dom tree, they should be siblings, not children.
								paragraphHackfixRequired = true;
							}
						}

						//writef("<%s>", tagName);
						while(!closed) {
							Ele n;
							if(strict)
								n = readElement();
							else
								n = readElement(parentChain ~ tagName);

							if(n.type == 4) return n; // the document is empty

							if(n.type == 3 && n.element !is null) {
								// special node, append if possible
								if(e !is null)
									e.appendChild(n.element);
								else
									piecesBeforeRoot ~= n.element;
							} else if(n.type == 0) {
								if(!strict)
									considerHtmlParagraphHack(n.element);
								e.appendChild(n.element);
							} else if(n.type == 1) {
								bool found = false;
								if(n.payload != tagName) {
									if(strict)
										parseError(format("mismatched tag: </%s> != <%s> (opened on line %d)", n.payload, tagName, getLineNumber(whereThisTagStarted)));
									else {
										sawImproperNesting = true;
										// this is so we don't drop several levels of awful markup
										if(n.element) {
											if(!strict)
												considerHtmlParagraphHack(n.element);
											e.appendChild(n.element);
											n.element = null;
										}

										// is the element open somewhere up the chain?
										foreach(i, parent; parentChain)
											if(parent == n.payload) {
												recentAutoClosedTags ~= tagName;
												// just rotating it so we don't inadvertently break stuff with vile crap
												if(recentAutoClosedTags.length > 4)
													recentAutoClosedTags = recentAutoClosedTags[1 .. $];

												n.element = e;
												return n;
											}

										// if not, this is a text node; we can't fix it up...

										// If it's already in the tree somewhere, assume it is closed by algorithm
										// and we shouldn't output it - odds are the user just flipped a couple tags
										foreach(ele; e.tree) {
											if(ele.tagName == n.payload) {
												found = true;
												break;
											}
										}

										foreach(ele; recentAutoClosedTags) {
											if(ele == n.payload) {
												found = true;
												break;
											}
										}

										if(!found) // if not found in the tree though, it's probably just text
										e.appendChild(TextNode.fromUndecodedString(this, "</"~n.payload~">"));
									}
								} else {
									if(n.element) {
										if(!strict)
											considerHtmlParagraphHack(n.element);
										e.appendChild(n.element);
									}
								}

								if(n.payload == tagName) // in strict mode, this is always true
									closed = true;
							} else { /*throw new Exception("wtf " ~ tagName);*/ }
						}
						//writef("</%s>\n", tagName);
						return Ele(0, e, null);
					}

					// if a tag was opened but not closed by end of file, we can arrive here
					if(!strict && pos >= data.length)
						return addTag(false);
					//else if(strict) assert(0); // should be caught before

					switch(data[pos]) {
						default: assert(0);
						case '/': // self closing tag
							return addTag(true);
						case '>':
							return addTag(false);
						case ' ':
						case '\t':
						case '\n':
						case '\r':
							// there might be attributes...
							moreAttributes:
							eatWhitespace();

							// same deal as above the switch....
							if(!strict && pos >= data.length)
								return addTag(false);

							if(strict && pos >= data.length)
								throw new MarkupException("tag open, didn't find > before end of file");

							switch(data[pos]) {
								case '/': // self closing tag
									return addTag(true);
								case '>': // closed tag; open -- we now read the contents
									return addTag(false);
								default: // it is an attribute
									string attrName = readAttributeName();
									string attrValue = attrName;

									bool ateAny = eatWhitespace();
									if(strict && ateAny)
										throw new MarkupException("inappropriate whitespace after attribute name");

									if(pos >= data.length) {
										if(strict)
											assert(0, "this should have thrown in readAttributeName");
										else {
											data ~= ">";
											goto blankValue;
										}
									}
									if(data[pos] == '=') {
										pos++;

										ateAny = eatWhitespace();
										if(strict && ateAny)
											throw new MarkupException("inappropriate whitespace after attribute equals");

										attrValue = readAttributeValue();

										eatWhitespace();
									}

									blankValue:

									if(strict && attrName in attributes)
										throw new MarkupException("Repeated attribute: " ~ attrName);

									if(attrName.strip().length)
										attributes[attrName] = attrValue;
									else if(strict) throw new MarkupException("wtf, zero length attribute name");

									if(!strict && pos < data.length && data[pos] == '<') {
										// this is the broken tag that doesn't have a > at the end
										data = data[0 .. pos] ~ ">" ~ data[pos.. $];
										// let's insert one as a hack
										goto case '>';
									}

									goto moreAttributes;
							}
					}
			}

			return Ele(2, null, null); // this is a <! or <? thing that got ignored prolly.
			//assert(0);
		}

		eatWhitespace();
		Ele r;
		do {
			r = readElement(); // there SHOULD only be one element...

			if(r.type == 3 && r.element !is null)
				piecesBeforeRoot ~= r.element;

			if(r.type == 4)
				break; // the document is completely empty...
		} while (r.type != 0 || r.element.nodeType != 1); // we look past the xml prologue and doctype; root only begins on a regular node

		root = r.element;

		if(!strict) // in strict mode, we'll just ignore stuff after the xml
		while(r.type != 4) {
			r = readElement();
			if(r.type != 4 && r.type != 2) { // if not empty and not ignored
				if(r.element !is null)
					piecesAfterRoot ~= r.element;
			}
		}

		if(root is null)
		{
			if(strict)
				assert(0, "empty document should be impossible in strict mode");
			else
				parseUtf8(`<html><head></head><body></body></html>`); // fill in a dummy document in loose mode since that's what browsers do
		}

		if(paragraphHackfixRequired) {
			assert(!strict); // this should never happen in strict mode; it ought to never set the hack flag...

			// in loose mode, we can see some "bad" nesting (it's valid html, but poorly formed xml).
			// It's hard to handle above though because my code sucks. So, we'll fix it here.

			// Where to insert based on the parent (for mixed closed/unclosed <p> tags). See #120
			// Kind of inefficient because we can't detect when we recurse back out of a node.
			Element[Element] insertLocations;
			auto iterator = root.tree;
			foreach(ele; iterator) {
				if(ele.parentNode is null)
					continue;

				if(ele.tagName == "p" && ele.parentNode.tagName == ele.tagName) {
					auto shouldBePreviousSibling = ele.parentNode;
					auto holder = shouldBePreviousSibling.parentNode; // this is the two element's mutual holder...
					if (auto p = holder in insertLocations) {
						shouldBePreviousSibling = *p;
						assert(shouldBePreviousSibling.parentNode is holder);
					}
					ele = holder.insertAfter(shouldBePreviousSibling, ele.removeFromTree());
					insertLocations[holder] = ele;
					iterator.currentKilled(); // the current branch can be skipped; we'll hit it soon anyway since it's now next up.
				}
			}
		}
	}

	/* end massive parse function */

	/// Gets the <title> element's innerText, if one exists
	@property string title() {
		bool doesItMatch(Element e) {
			return (e.tagName == "title");
		}

		auto e = findFirst(&doesItMatch);
		if(e)
			return e.innerText();
		return "";
	}

	/// Sets the title of the page, creating a <title> element if needed.
	@property void title(string t) {
		bool doesItMatch(Element e) {
			return (e.tagName == "title");
		}

		auto e = findFirst(&doesItMatch);

		if(!e) {
			e = createElement("title");
			auto heads = getElementsByTagName("head");
			if(heads.length)
				heads[0].appendChild(e);
		}

		if(e)
			e.innerText = t;
	}

	// FIXME: would it work to alias root this; ???? might be a good idea
	/// These functions all forward to the root element. See the documentation in the Element class.
	Element getElementById(string id) {
		return root.getElementById(id);
	}

	/// ditto
	final SomeElementType requireElementById(SomeElementType = Element)(string id, string file = __FILE__, size_t line = __LINE__)
		if( is(SomeElementType : Element))
		out(ret) { assert(ret !is null); }
	body {
		return root.requireElementById!(SomeElementType)(id, file, line);
	}

	/// ditto
	final SomeElementType requireSelector(SomeElementType = Element)(string selector, string file = __FILE__, size_t line = __LINE__)
		if( is(SomeElementType : Element))
		out(ret) { assert(ret !is null); }
	body {
		auto e = cast(SomeElementType) querySelector(selector);
		if(e is null)
			throw new ElementNotFoundException(SomeElementType.stringof, selector, this.root, file, line);
		return e;
	}

	final MaybeNullElement!SomeElementType optionSelector(SomeElementType = Element)(string selector, string file = __FILE__, size_t line = __LINE__)
		if(is(SomeElementType : Element))
	{
		auto e = cast(SomeElementType) querySelector(selector);
		return MaybeNullElement!SomeElementType(e);
	}

	/// ditto
	@scriptable
	Element querySelector(string selector) {
		// see comment below on Document.querySelectorAll
		auto s = Selector(selector);//, !loose);
		foreach(ref comp; s.components)
			if(comp.parts.length && comp.parts[0].separation == 0)
				comp.parts[0].separation = -1;
		foreach(e; s.getMatchingElementsLazy(this.root))
			return e;
		return null;

	}

	/// ditto
	@scriptable
	Element[] querySelectorAll(string selector) {
		// In standards-compliant code, the document is slightly magical
		// in that it is a pseudoelement at top level. It should actually
		// match the root as one of its children.
		//
		// In versions of dom.d before Dec 29 2019, this worked because
		// querySelectorAll was willing to return itself. With that bug fix
		// (search "arbitrary id asduiwh" in this file for associated unittest)
		// this would have failed. Hence adding back the root if it matches the
		// selector itself.
		//
		// I'd love to do this better later.

		auto s = Selector(selector);//, !loose);
		foreach(ref comp; s.components)
			if(comp.parts.length && comp.parts[0].separation == 0)
				comp.parts[0].separation = -1;
		return s.getMatchingElements(this.root);
	}

	/// ditto
	deprecated("use querySelectorAll instead")
	Element[] getElementsBySelector(string selector) {
		return root.getElementsBySelector(selector);
	}

	/// ditto
	@scriptable
	Element[] getElementsByTagName(string tag) {
		return root.getElementsByTagName(tag);
	}

	/// ditto
	@scriptable
	Element[] getElementsByClassName(string tag) {
		return root.getElementsByClassName(tag);
	}

	/** FIXME: btw, this could just be a lazy range...... */
	Element getFirstElementByTagName(string tag) {
		if(loose)
			tag = tag.toLower();
		bool doesItMatch(Element e) {
			return e.tagName == tag;
		}
		return findFirst(&doesItMatch);
	}

	/// This returns the <body> element, if there is one. (It different than Javascript, where it is called 'body', because body is a keyword in D.)
	Element mainBody() {
		return getFirstElementByTagName("body");
	}

	/// this uses a weird thing... it's [name=] if no colon and
	/// [property=] if colon
	string getMeta(string name) {
		string thing = name.indexOf(":") == -1 ? "name" : "property";
		auto e = querySelector("head meta["~thing~"="~name~"]");
		if(e is null)
			return null;
		return e.content;
	}

	/// Sets a meta tag in the document header. It is kinda hacky to work easily for both Facebook open graph and traditional html meta tags/
	void setMeta(string name, string value) {
		string thing = name.indexOf(":") == -1 ? "name" : "property";
		auto e = querySelector("head meta["~thing~"="~name~"]");
		if(e is null) {
			e = requireSelector("head").addChild("meta");
			e.setAttribute(thing, name);
		}

		e.content = value;
	}

	///.
	Form[] forms() {
		return cast(Form[]) getElementsByTagName("form");
	}

	///.
	Form createForm()
		out(ret) {
			assert(ret !is null);
		}
	body {
		return cast(Form) createElement("form");
	}

	///.
	Element createElement(string name) {
		if(loose)
			name = name.toLower();

		auto e = Element.make(name, null, null, selfClosedElements);
		e.parentDocument = this;

		return e;

//		return new Element(this, name, null, selfClosed);
	}

	///.
	Element createFragment() {
		return new DocumentFragment(this);
	}

	///.
	Element createTextNode(string content) {
		return new TextNode(this, content);
	}


	///.
	Element findFirst(bool delegate(Element) doesItMatch) {
		if(root is null)
			return null;
		Element result;

		bool goThroughElement(Element e) {
			if(doesItMatch(e)) {
				result = e;
				return true;
			}

			foreach(child; e.children) {
				if(goThroughElement(child))
					return true;
			}

			return false;
		}

		goThroughElement(root);

		return result;
	}

	///.
	void clear() {
		root = null;
		loose = false;
	}

	///.
	void setProlog(string d) {
		_prolog = d;
		prologWasSet = true;
	}

	///.
	private string _prolog = "<!DOCTYPE html>\n";
	private bool prologWasSet = false; // set to true if the user changed it

	@property string prolog() const {
		// if the user explicitly changed it, do what they want
		// or if we didn't keep/find stuff from the document itself,
		// we'll use the builtin one as a default.
		if(prologWasSet || piecesBeforeRoot.length == 0)
			return _prolog;

		string p;
		foreach(e; piecesBeforeRoot)
			p ~= e.toString() ~ "\n";
		return p;
	}

	///.
	override string toString() const {
		return prolog ~ root.toString();
	}

	/++
		Writes it out with whitespace for easier eyeball debugging

		Do NOT use for anything other than eyeball debugging,
		because whitespace may be significant content in XML.
	+/
	string toPrettyString(bool insertComments = false, int indentationLevel = 0, string indentWith = "\t") const {
		import std.string;
		string s = prolog.strip;

		/*
		if(insertComments) s ~= "<!--";
		s ~= "\n";
		if(insertComments) s ~= "-->";
		*/

		s ~= root.toPrettyString(insertComments, indentationLevel, indentWith);
		foreach(a; piecesAfterRoot)
			s ~= a.toPrettyString(insertComments, indentationLevel, indentWith);
		return s;
	}

	///.
	Element root;

	/// if these were kept, this is stuff that appeared before the root element, such as <?xml version ?> decls and <!DOCTYPE>s
	Element[] piecesBeforeRoot;

	/// stuff after the root, only stored in non-strict mode and not used in toString, but available in case you want it
	Element[] piecesAfterRoot;

	///.
	bool loose;



	// what follows are for mutation events that you can observe
	void delegate(DomMutationEvent)[] eventObservers;

	void dispatchMutationEvent(DomMutationEvent e) {
		foreach(o; eventObservers)
			o(e);
	}
}

/// This represents almost everything in the DOM.
/// Group: core_functionality
class Element {
	/// Returns a collection of elements by selector.
	/// See: [Document.opIndex]
	ElementCollection opIndex(string selector) {
		auto e = ElementCollection(this);
		return e[selector];
	}

	/++
		Returns the child node with the particular index.

		Be aware that child nodes include text nodes, including
		whitespace-only nodes.
	+/
	Element opIndex(size_t index) {
		if(index >= children.length)
			return null;
		return this.children[index];
	}

	/// Calls getElementById, but throws instead of returning null if the element is not found. You can also ask for a specific subclass of Element to dynamically cast to, which also throws if it cannot be done.
	final SomeElementType requireElementById(SomeElementType = Element)(string id, string file = __FILE__, size_t line = __LINE__)
	if(
		is(SomeElementType : Element)
	)
	out(ret) {
		assert(ret !is null);
	}
	body {
		auto e = cast(SomeElementType) getElementById(id);
		if(e is null)
			throw new ElementNotFoundException(SomeElementType.stringof, "id=" ~ id, this, file, line);
		return e;
	}

	/// ditto but with selectors instead of ids
	final SomeElementType requireSelector(SomeElementType = Element)(string selector, string file = __FILE__, size_t line = __LINE__)
	if(
		is(SomeElementType : Element)
	)
	out(ret) {
		assert(ret !is null);
	}
	body {
		auto e = cast(SomeElementType) querySelector(selector);
		if(e is null)
			throw new ElementNotFoundException(SomeElementType.stringof, selector, this, file, line);
		return e;
	}


	/++
		If a matching selector is found, it returns that Element. Otherwise, the returned object returns null for all methods.
	+/
	final MaybeNullElement!SomeElementType optionSelector(SomeElementType = Element)(string selector, string file = __FILE__, size_t line = __LINE__)
		if(is(SomeElementType : Element))
	{
		auto e = cast(SomeElementType) querySelector(selector);
		return MaybeNullElement!SomeElementType(e);
	}



	/// get all the classes on this element
	@property string[] classes() {
		return split(className, " ");
	}

	/// Adds a string to the class attribute. The class attribute is used a lot in CSS.
	@scriptable
	Element addClass(string c) {
		if(hasClass(c))
			return this; // don't add it twice

		string cn = getAttribute("class");
		if(cn.length == 0) {
			setAttribute("class", c);
			return this;
		} else {
			setAttribute("class", cn ~ " " ~ c);
		}

		return this;
	}

	/// Removes a particular class name.
	@scriptable
	Element removeClass(string c) {
		if(!hasClass(c))
			return this;
		string n;
		foreach(name; classes) {
			if(c == name)
				continue; // cut it out
			if(n.length)
				n ~= " ";
			n ~= name;
		}

		className = n.strip();

		return this;
	}

	/// Returns whether the given class appears in this element.
	bool hasClass(string c) {
		string cn = className;

		auto idx = cn.indexOf(c);
		if(idx == -1)
			return false;

		foreach(cla; cn.split(" "))
			if(cla == c)
				return true;
		return false;

		/*
		int rightSide = idx + c.length;

		bool checkRight() {
			if(rightSide == cn.length)
				return true; // it's the only class
			else if(iswhite(cn[rightSide]))
				return true;
			return false; // this is a substring of something else..
		}

		if(idx == 0) {
			return checkRight();
		} else {
			if(!iswhite(cn[idx - 1]))
				return false; // substring
			return checkRight();
		}

		assert(0);
		*/
	}


	/* *******************************
		  DOM Mutation
	*********************************/
	/// convenience function to quickly add a tag with some text or
	/// other relevant info (for example, it's a src for an <img> element
	/// instead of inner text)
	Element addChild(string tagName, string childInfo = null, string childInfo2 = null)
		in {
			assert(tagName !is null);
		}
		out(e) {
			//assert(e.parentNode is this);
			//assert(e.parentDocument is this.parentDocument);
		}
	body {
		auto e = Element.make(tagName, childInfo, childInfo2);
		// FIXME (maybe): if the thing is self closed, we might want to go ahead and
		// return the parent. That will break existing code though.
		return appendChild(e);
	}

	/// Another convenience function. Adds a child directly after the current one, returning
	/// the new child.
	///
	/// Between this, addChild, and parentNode, you can build a tree as a single expression.
	Element addSibling(string tagName, string childInfo = null, string childInfo2 = null)
		in {
			assert(tagName !is null);
			assert(parentNode !is null);
		}
		out(e) {
			assert(e.parentNode is this.parentNode);
			assert(e.parentDocument is this.parentDocument);
		}
	body {
		auto e = Element.make(tagName, childInfo, childInfo2);
		return parentNode.insertAfter(this, e);
	}

	///
	Element addSibling(Element e) {
		return parentNode.insertAfter(this, e);
	}

	///
	Element addChild(Element e) {
		return this.appendChild(e);
	}

	/// Convenience function to append text intermixed with other children.
	/// For example: div.addChildren("You can visit my website by ", new Link("mysite.com", "clicking here"), ".");
	/// or div.addChildren("Hello, ", user.name, "!");

	/// See also: appendHtml. This might be a bit simpler though because you don't have to think about escaping.
	void addChildren(T...)(T t) {
		foreach(item; t) {
			static if(is(item : Element))
				appendChild(item);
			else static if (is(isSomeString!(item)))
				appendText(to!string(item));
			else static assert(0, "Cannot pass " ~ typeof(item).stringof ~ " to addChildren");
		}
	}

	///.
	Element addChild(string tagName, Element firstChild, string info2 = null)
	in {
		assert(firstChild !is null);
	}
	out(ret) {
		assert(ret !is null);
		assert(ret.parentNode is this);
		assert(firstChild.parentNode is ret);

		assert(ret.parentDocument is this.parentDocument);
		//assert(firstChild.parentDocument is this.parentDocument);
	}
	body {
		auto e = Element.make(tagName, "", info2);
		e.appendChild(firstChild);
		this.appendChild(e);
		return e;
	}

	///
	Element addChild(string tagName, in Html innerHtml, string info2 = null)
	in {
	}
	out(ret) {
		assert(ret !is null);
		assert((cast(DocumentFragment) this !is null) || (ret.parentNode is this), ret.toString);// e.parentNode ? e.parentNode.toString : "null");
		assert(ret.parentDocument is this.parentDocument);
	}
	body {
		auto e = Element.make(tagName, "", info2);
		this.appendChild(e);
		e.innerHTML = innerHtml.source;
		return e;
	}


	/// .
	void appendChildren(Element[] children) {
		foreach(ele; children)
			appendChild(ele);
	}

	///.
	void reparent(Element newParent)
		in {
			assert(newParent !is null);
			assert(parentNode !is null);
		}
		out {
			assert(this.parentNode is newParent);
			//assert(isInArray(this, newParent.children));
		}
	body {
		parentNode.removeChild(this);
		newParent.appendChild(this);
	}

	/**
		Strips this tag out of the document, putting its inner html
		as children of the parent.

		For example, given: `<p>hello <b>there</b></p>`, if you
		call `stripOut` on the `b` element, you'll be left with
		`<p>hello there<p>`.

		The idea here is to make it easy to get rid of garbage
		markup you aren't interested in.
	*/
	void stripOut()
		in {
			assert(parentNode !is null);
		}
		out {
			assert(parentNode is null);
			assert(children.length == 0);
		}
	body {
		foreach(c; children)
			c.parentNode = null; // remove the parent
		if(children.length)
			parentNode.replaceChild(this, this.children);
		else
			parentNode.removeChild(this);
		this.children.length = 0; // we reparented them all above
	}

	/// shorthand for `this.parentNode.removeChild(this)` with `parentNode` `null` check
	/// if the element already isn't in a tree, it does nothing.
	Element removeFromTree()
		in {

		}
		out(var) {
			assert(this.parentNode is null);
			assert(var is this);
		}
	body {
		if(this.parentNode is null)
			return this;

		this.parentNode.removeChild(this);

		return this;
	}

	/++
		Wraps this element inside the given element.
		It's like `this.replaceWith(what); what.appendchild(this);`

		Given: `<b>cool</b>`, if you call `b.wrapIn(new Link("site.com", "my site is "));`
		you'll end up with: `<a href="site.com">my site is <b>cool</b></a>`.
	+/
	Element wrapIn(Element what)
		in {
			assert(what !is null);
		}
		out(ret) {
			assert(this.parentNode is what);
			assert(ret is what);
		}
	body {
		this.replaceWith(what);
		what.appendChild(this);

		return what;
	}

	/// Replaces this element with something else in the tree.
	Element replaceWith(Element e)
	in {
		assert(this.parentNode !is null);
	}
	body {
		e.removeFromTree();
		this.parentNode.replaceChild(this, e);
		return e;
	}

	/**
		Splits the className into an array of each class given
	*/
	string[] classNames() const {
		return className().split(" ");
	}

	/**
		Fetches the first consecutive text nodes concatenated together.


		`firstInnerText` of `<example>some text<span>more text</span></example>` is `some text`. It stops at the first child tag encountered.

		See_also: [directText], [innerText]
	*/
	string firstInnerText() const {
		string s;
		foreach(child; children) {
			if(child.nodeType != NodeType.Text)
				break;

			s ~= child.nodeValue();
		}
		return s;
	}


	/**
		Returns the text directly under this element.
		

		Unlike [innerText], it does not recurse, and unlike [firstInnerText], it continues
		past child tags. So, `<example>some <b>bold</b> text</example>`
		will return `some  text` because it only gets the text, skipping non-text children.

		See_also: [firstInnerText], [innerText]
	*/
	@property string directText() {
		string ret;
		foreach(e; children) {
			if(e.nodeType == NodeType.Text)
				ret ~= e.nodeValue();
		}

		return ret;
	}

	/**
		Sets the direct text, without modifying other child nodes.


		Unlike [innerText], this does *not* remove existing elements in the element.

		It only replaces the first text node it sees.

		If there are no text nodes, it calls [appendText].

		So, given `<div><img />text here</div>`, it will keep the `<img />`, and replace the `text here`.
	*/
	@property void directText(string text) {
		foreach(e; children) {
			if(e.nodeType == NodeType.Text) {
				auto it = cast(TextNode) e;
				it.contents = text;
				return;
			}
		}

		appendText(text);
	}

	// do nothing, this is primarily a virtual hook
	// for links and forms
	void setValue(string field, string value) { }


	// this is a thing so i can remove observer support if it gets slow
	// I have not implemented all these yet
	private void sendObserverEvent(DomMutationOperations operation, string s1 = null, string s2 = null, Element r = null, Element r2 = null) {
		if(parentDocument is null) return;
		DomMutationEvent me;
		me.operation = operation;
		me.target = this;
		me.relatedString = s1;
		me.relatedString2 = s2;
		me.related = r;
		me.related2 = r2;
		parentDocument.dispatchMutationEvent(me);
	}

	// putting all the members up front

	// this ought to be private. don't use it directly.
	Element[] children;

	/// The name of the tag. Remember, changing this doesn't change the dynamic type of the object.
	string tagName;

	/// This is where the attributes are actually stored. You should use getAttribute, setAttribute, and hasAttribute instead.
	string[string] attributes;

	/// In XML, it is valid to write <tag /> for all elements with no children, but that breaks HTML, so I don't do it here.
	/// Instead, this flag tells if it should be. It is based on the source document's notation and a html element list.
	private bool selfClosed;

	/// Get the parent Document object that contains this element.
	/// It may be null, so remember to check for that.
	Document parentDocument;

	///.
	inout(Element) parentNode() inout {
		auto p = _parentNode;

		if(cast(DocumentFragment) p)
			return p._parentNode;

		return p;
	}

	//protected
	Element parentNode(Element e) {
		return _parentNode = e;
	}

	private Element _parentNode;

	// the next few methods are for implementing interactive kind of things
	private CssStyle _computedStyle;

	// these are here for event handlers. Don't forget that this library never fires events.
	// (I'm thinking about putting this in a version statement so you don't have the baggage. The instance size of this class is 56 bytes right now.)
	EventHandler[][string] bubblingEventHandlers;
	EventHandler[][string] capturingEventHandlers;
	EventHandler[string] defaultEventHandlers;

	void addEventListener(string event, EventHandler handler, bool useCapture = false) {
		if(event.length > 2 && event[0..2] == "on")
			event = event[2 .. $];

		if(useCapture)
			capturingEventHandlers[event] ~= handler;
		else
			bubblingEventHandlers[event] ~= handler;
	}


	// and now methods

	/++
		Convenience function to try to do the right thing for HTML. This is the main way I create elements.

		History:
			On February 8, 2021, the `selfClosedElements` parameter was added. Previously, it used a private
			immutable global list for HTML. It still defaults to the same list, but you can change it now via
			the parameter.
	+/
	static Element make(string tagName, string childInfo = null, string childInfo2 = null, const string[] selfClosedElements = htmlSelfClosedElements) {
		bool selfClosed = tagName.isInArray(selfClosedElements);

		Element e;
		// want to create the right kind of object for the given tag...
		switch(tagName) {
			case "#text":
				e = new TextNode(null, childInfo);
				return e;
			// break;
			case "table":
				e = new Table(null);
			break;
			case "a":
				e = new Link(null);
			break;
			case "form":
				e = new Form(null);
			break;
			case "tr":
				e = new TableRow(null);
			break;
			case "td", "th":
				e = new TableCell(null, tagName);
			break;
			default:
				e = new Element(null, tagName, null, selfClosed); // parent document should be set elsewhere
		}

		// make sure all the stuff is constructed properly FIXME: should probably be in all the right constructors too
		e.tagName = tagName;
		e.selfClosed = selfClosed;

		if(childInfo !is null)
			switch(tagName) {
				/* html5 convenience tags */
				case "audio":
					if(childInfo.length)
						e.addChild("source", childInfo);
					if(childInfo2 !is null)
						e.appendText(childInfo2);
				break;
				case "source":
					e.src = childInfo;
					if(childInfo2 !is null)
						e.type = childInfo2;
				break;
				/* regular html 4 stuff */
				case "img":
					e.src = childInfo;
					if(childInfo2 !is null)
						e.alt = childInfo2;
				break;
				case "link":
					e.href = childInfo;
					if(childInfo2 !is null)
						e.rel = childInfo2;
				break;
				case "option":
					e.innerText = childInfo;
					if(childInfo2 !is null)
						e.value = childInfo2;
				break;
				case "input":
					e.type = "hidden";
					e.name = childInfo;
					if(childInfo2 !is null)
						e.value = childInfo2;
				break;
				case "button":
					e.innerText = childInfo;
					if(childInfo2 !is null)
						e.type = childInfo2;
				break;
				case "a":
					e.innerText = childInfo;
					if(childInfo2 !is null)
						e.href = childInfo2;
				break;
				case "script":
				case "style":
					e.innerRawSource = childInfo;
				break;
				case "meta":
					e.name = childInfo;
					if(childInfo2 !is null)
						e.content = childInfo2;
				break;
				/* generically, assume we were passed text and perhaps class */
				default:
					e.innerText = childInfo;
					if(childInfo2.length)
						e.className = childInfo2;
			}

		return e;
	}

	static Element make(string tagName, in Html innerHtml, string childInfo2 = null) {
		// FIXME: childInfo2 is ignored when info1 is null
		auto m = Element.make(tagName, "not null"[0..0], childInfo2);
		m.innerHTML = innerHtml.source;
		return m;
	}

	static Element make(string tagName, Element child, string childInfo2 = null) {
		auto m = Element.make(tagName, cast(string) null, childInfo2);
		m.appendChild(child);
		return m;
	}


	/// Generally, you don't want to call this yourself - use Element.make or document.createElement instead.
	this(Document _parentDocument, string _tagName, string[string] _attributes = null, bool _selfClosed = false) {
		parentDocument = _parentDocument;
		tagName = _tagName;
		if(_attributes !is null)
			attributes = _attributes;
		selfClosed = _selfClosed;

		version(dom_node_indexes)
			this.dataset.nodeIndex = to!string(&(this.attributes));

		assert(_tagName.indexOf(" ") == -1);//, "<" ~ _tagName ~ "> is invalid");
	}

	/++
		Convenience constructor when you don't care about the parentDocument. Note this might break things on the document.
		Note also that without a parent document, elements are always in strict, case-sensitive mode.

		History:
			On February 8, 2021, the `selfClosedElements` parameter was added. It defaults to the same behavior as
			before: using the hard-coded list of HTML elements, but it can now be overridden. If you use
			[Document.createElement], it will use the list set for the current document. Otherwise, you can pass
			something here if you like.
	+/
	this(string _tagName, string[string] _attributes = null, const string[] selfClosedElements = htmlSelfClosedElements) {
		tagName = _tagName;
		if(_attributes !is null)
			attributes = _attributes;
		selfClosed = tagName.isInArray(selfClosedElements);

		// this is meant to reserve some memory. It makes a small, but consistent improvement.
		//children.length = 8;
		//children.length = 0;

		version(dom_node_indexes)
			this.dataset.nodeIndex = to!string(&(this.attributes));
	}

	private this(Document _parentDocument) {
		parentDocument = _parentDocument;

		version(dom_node_indexes)
			this.dataset.nodeIndex = to!string(&(this.attributes));
	}


	/* *******************************
	       Navigating the DOM
	*********************************/

	/// Returns the first child of this element. If it has no children, returns null.
	/// Remember, text nodes are children too.
	@property Element firstChild() {
		return children.length ? children[0] : null;
	}

	///
	@property Element lastChild() {
		return children.length ? children[$ - 1] : null;
	}
	
	/// UNTESTED
	/// the next element you would encounter if you were reading it in the source
	Element nextInSource() {
		auto n = firstChild;
		if(n is null)
			n = nextSibling();
		if(n is null) {
			auto p = this.parentNode;
			while(p !is null && n is null) {
				n = p.nextSibling;
			}
		}

		return n;
	}

	/// UNTESTED
	/// ditto
	Element previousInSource() {
		auto p = previousSibling;
		if(p is null) {
			auto par = parentNode;
			if(par)
				p = par.lastChild;
			if(p is null)
				p = par;
		}
		return p;
	}

	///.
	@property Element previousElementSibling() {
		return previousSibling("*");
	}

	///.
	@property Element previousSibling(string tagName = null) {
		if(this.parentNode is null)
			return null;
		Element ps = null;
		foreach(e; this.parentNode.childNodes) {
			if(e is this)
				break;
			if(tagName == "*" && e.nodeType != NodeType.Text) {
				ps = e;
			} else if(tagName is null || e.tagName == tagName)
				ps = e;
		}

		return ps;
	}

	///.
	@property Element nextElementSibling() {
		return nextSibling("*");
	}

	///.
	@property Element nextSibling(string tagName = null) {
		if(this.parentNode is null)
			return null;
		Element ns = null;
		bool mightBe = false;
		foreach(e; this.parentNode.childNodes) {
			if(e is this) {
				mightBe = true;
				continue;
			}
			if(mightBe) {
				if(tagName == "*" && e.nodeType != NodeType.Text) {
					ns = e;
					break;
				}
				if(tagName is null || e.tagName == tagName) {
					ns = e;
					break;
				}
			}
		}

		return ns;
	}


	/// Gets the nearest node, going up the chain, with the given tagName
	/// May return null or throw.
	T getParent(T = Element)(string tagName = null) if(is(T : Element)) {
		if(tagName is null) {
			static if(is(T == Form))
				tagName = "form";
			else static if(is(T == Table))
				tagName = "table";
			else static if(is(T == Link))
				tagName == "a";
		}

		auto par = this.parentNode;
		while(par !is null) {
			if(tagName is null || par.tagName == tagName)
				break;
			par = par.parentNode;
		}

		static if(!is(T == Element)) {
			auto t = cast(T) par;
			if(t is null)
				throw new ElementNotFoundException("", tagName ~ " parent not found", this);
		} else
			auto t = par;

		return t;
	}

	///.
	Element getElementById(string id) {
		// FIXME: I use this function a lot, and it's kinda slow
		// not terribly slow, but not great.
		foreach(e; tree)
			if(e.id == id)
				return e;
		return null;
	}

	/++
		Returns a child element that matches the given `selector`.

		Note: you can give multiple selectors, separated by commas.
	 	It will return the first match it finds.
	+/
	@scriptable
	Element querySelector(string selector) {
		Selector s = Selector(selector);
		foreach(ele; tree)
			if(s.matchesElement(ele))
				return ele;
		return null;
	}

	/// a more standards-compliant alias for getElementsBySelector
	@scriptable
	Element[] querySelectorAll(string selector) {
		return getElementsBySelector(selector);
	}

	/// If the element matches the given selector. Previously known as `matchesSelector`.
	@scriptable
	bool matches(string selector) {
		/+
		bool caseSensitiveTags = true;
		if(parentDocument && parentDocument.loose)
			caseSensitiveTags = false;
		+/

		Selector s = Selector(selector);
		return s.matchesElement(this);
	}

	/// Returns itself or the closest parent that matches the given selector, or null if none found
	/// See_also: https://developer.mozilla.org/en-US/docs/Web/API/Element/closest
	@scriptable
	Element closest(string selector) {
		Element e = this;
		while(e !is null) {
			if(e.matches(selector))
				return e;
			e = e.parentNode;
		}
		return null;
	}

	/**
		Returns elements that match the given CSS selector

		* -- all, default if nothing else is there

		tag#id.class.class.class:pseudo[attrib=what][attrib=what] OP selector

		It is all additive

		OP

		space = descendant
		>     = direct descendant
		+     = sibling (E+F Matches any F element immediately preceded by a sibling element E)

		[foo]        Foo is present as an attribute
		[foo="warning"]   Matches any E element whose "foo" attribute value is exactly equal to "warning".
		E[foo~="warning"] Matches any E element whose "foo" attribute value is a list of space-separated values, one of which is exactly equal to "warning"
		E[lang|="en"] Matches any E element whose "lang" attribute has a hyphen-separated list of values beginning (from the left) with "en".

		[item$=sdas] ends with
		[item^-sdsad] begins with

		Quotes are optional here.

		Pseudos:
			:first-child
			:last-child
			:link (same as a[href] for our purposes here)


		There can be commas separating the selector. A comma separated list result is OR'd onto the main.



		This ONLY cares about elements. text, etc, are ignored


		There should be two functions: given element, does it match the selector? and given a selector, give me all the elements
	*/
	Element[] getElementsBySelector(string selector) {
		// FIXME: this function could probably use some performance attention
		// ... but only mildly so according to the profiler in the big scheme of things; probably negligible in a big app.


		bool caseSensitiveTags = true;
		if(parentDocument && parentDocument.loose)
			caseSensitiveTags = false;

		Element[] ret;
		foreach(sel; parseSelectorString(selector, caseSensitiveTags))
			ret ~= sel.getElements(this);
		return ret;
	}

	/// .
	Element[] getElementsByClassName(string cn) {
		// is this correct?
		return getElementsBySelector("." ~ cn);
	}

	///.
	Element[] getElementsByTagName(string tag) {
		if(parentDocument && parentDocument.loose)
			tag = tag.toLower();
		Element[] ret;
		foreach(e; tree)
			if(e.tagName == tag)
				ret ~= e;
		return ret;
	}


	/* *******************************
	          Attributes
	*********************************/

	/**
		Gets the given attribute value, or null if the
		attribute is not set.

		Note that the returned string is decoded, so it no longer contains any xml entities.
	*/
	@scriptable
	string getAttribute(string name) const {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();
		auto e = name in attributes;
		if(e)
			return *e;
		else
			return null;
	}

	/**
		Sets an attribute. Returns this for easy chaining
	*/
	@scriptable
	Element setAttribute(string name, string value) {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();

		// I never use this shit legitimately and neither should you
		auto it = name.toLower();
		if(it == "href" || it == "src") {
			auto v = value.strip().toLower();
			if(v.startsWith("vbscript:"))
				value = value[9..$];
			if(v.startsWith("javascript:"))
				value = value[11..$];
		}

		attributes[name] = value;

		sendObserverEvent(DomMutationOperations.setAttribute, name, value);

		return this;
	}

	/**
		Returns if the attribute exists.
	*/
	@scriptable
	bool hasAttribute(string name) {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();

		if(name in attributes)
			return true;
		else
			return false;
	}

	/**
		Removes the given attribute from the element.
	*/
	@scriptable
	Element removeAttribute(string name)
	out(ret) {
		assert(ret is this);
	}
	body {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();
		if(name in attributes)
			attributes.remove(name);

		sendObserverEvent(DomMutationOperations.removeAttribute, name);
		return this;
	}

	/**
		Gets the class attribute's contents. Returns
		an empty string if it has no class.
	*/
	@property string className() const {
		auto c = getAttribute("class");
		if(c is null)
			return "";
		return c;
	}

	///.
	@property Element className(string c) {
		setAttribute("class", c);
		return this;
	}

	/**
		Provides easy access to common HTML attributes, object style.

		---
		auto element = Element.make("a");
		a.href = "cool.html"; // this is the same as a.setAttribute("href", "cool.html");
		string where = a.href; // same as a.getAttribute("href");
		---

	*/
	@property string opDispatch(string name)(string v = null) if(isConvenientAttribute(name)) {
		if(v !is null)
			setAttribute(name, v);
		return getAttribute(name);
	}

	/**
		Old access to attributes. Use [attrs] instead.

		DEPRECATED: generally open opDispatch caused a lot of unforeseen trouble with compile time duck typing and UFCS extensions.
		so I want to remove it. A small whitelist of attributes is still allowed, but others are not.
		
		Instead, use element.attrs.attribute, element.attrs["attribute"],
		or element.getAttribute("attribute")/element.setAttribute("attribute").
	*/
	@property string opDispatch(string name)(string v = null) if(!isConvenientAttribute(name)) {
		static assert(0, "Don't use " ~ name ~ " direct on Element, instead use element.attrs.attributeName");
	}

	/*
	// this would be nice for convenience, but it broke the getter above.
	@property void opDispatch(string name)(bool boolean) if(name != "popFront") {
		if(boolean)
			setAttribute(name, name);
		else
			removeAttribute(name);
	}
	*/

	/**
		Returns the element's children.
	*/
	@property const(Element[]) childNodes() const {
		return children;
	}

	/// Mutable version of the same
	@property Element[] childNodes() { // FIXME: the above should be inout
		return children;
	}

	/++
		HTML5's dataset property. It is an alternate view into attributes with the data- prefix.
		Given `<a data-my-property="cool" />`, we get `assert(a.dataset.myProperty == "cool");`
	+/
	@property DataSet dataset() {
		return DataSet(this);
	}

	/++
		Gives dot/opIndex access to attributes
		---
		ele.attrs.largeSrc = "foo"; // same as ele.setAttribute("largeSrc", "foo")
		---
	+/
	@property AttributeSet attrs() {
		return AttributeSet(this);
	}

	/++
		Provides both string and object style (like in Javascript) access to the style attribute.

		---
		element.style.color = "red"; // translates into setting `color: red;` in the `style` attribute
		---
	+/
	@property ElementStyle style() {
		return ElementStyle(this);
	}

	/++
		This sets the style attribute with a string.
	+/
	@property ElementStyle style(string s) {
		this.setAttribute("style", s);
		return this.style;
	}

	private void parseAttributes(string[] whichOnes = null) {
/+
		if(whichOnes is null)
			whichOnes = attributes.keys;
		foreach(attr; whichOnes) {
			switch(attr) {
				case "id":

				break;
				case "class":

				break;
				case "style":

				break;
				default:
					// we don't care about it
			}
		}
+/
	}


	// if you change something here, it won't apply... FIXME const? but changing it would be nice if it applies to the style attribute too though you should use style there.
	/// Don't use this.
	@property CssStyle computedStyle() {
		if(_computedStyle is null) {
			auto style = this.getAttribute("style");
		/* we'll treat shitty old html attributes as css here */
			if(this.hasAttribute("width"))
				style ~= "; width: " ~ this.attrs.width;
			if(this.hasAttribute("height"))
				style ~= "; height: " ~ this.attrs.height;
			if(this.hasAttribute("bgcolor"))
				style ~= "; background-color: " ~ this.attrs.bgcolor;
			if(this.tagName == "body" && this.hasAttribute("text"))
				style ~= "; color: " ~ this.attrs.text;
			if(this.hasAttribute("color"))
				style ~= "; color: " ~ this.attrs.color;
		/* done */


			_computedStyle = new CssStyle(null, style); // gives at least something to work with
		}
		return _computedStyle;
	}

	/// These properties are useless in most cases, but if you write a layout engine on top of this lib, they may be good
	version(browser) {
		void* expansionHook; ///ditto
		int offsetWidth; ///ditto
		int offsetHeight; ///ditto
		int offsetLeft; ///ditto
		int offsetTop; ///ditto
		Element offsetParent; ///ditto
		bool hasLayout; ///ditto
		int zIndex; ///ditto

		///ditto
		int absoluteLeft() {
			int a = offsetLeft;
			auto p = offsetParent;
			while(p) {
				a += p.offsetLeft;
				p = p.offsetParent;
			}

			return a;
		}

		///ditto
		int absoluteTop() {
			int a = offsetTop;
			auto p = offsetParent;
			while(p) {
				a += p.offsetTop;
				p = p.offsetParent;
			}

			return a;
		}
	}

	// Back to the regular dom functions

    public:


	/* *******************************
	          DOM Mutation
	*********************************/

	/// Removes all inner content from the tag; all child text and elements are gone.
	void removeAllChildren()
		out {
			assert(this.children.length == 0);
		}
	body {
		children = null;
	}

	/// History: added June 13, 2020
	Element appendSibling(Element e) {
		parentNode.insertAfter(this, e);
		return e;
	}

	/// History: added June 13, 2020
	Element prependSibling(Element e) {
		parentNode.insertBefore(this, e);
		return e;
	}


    	/++
		Appends the given element to this one. If it already has a parent, it is removed from that tree and moved to this one.

		See_also: https://developer.mozilla.org/en-US/docs/Web/API/Node/appendChild

		History:
			Prior to 1 Jan 2020 (git tag v4.4.1 and below), it required that the given element must not have a parent already. This was in violation of standard, so it changed the behavior to remove it from the existing parent and instead move it here.
	+/
	Element appendChild(Element e)
		in {
			assert(e !is null);
		}
		out (ret) {
			assert((cast(DocumentFragment) this !is null) || (e.parentNode is this), e.toString);// e.parentNode ? e.parentNode.toString : "null");
			assert(e.parentDocument is this.parentDocument);
			assert(e is ret);
		}
	body {
		if(e.parentNode !is null)
			e.parentNode.removeChild(e);

		selfClosed = false;
		e.parentNode = this;
		e.parentDocument = this.parentDocument;
		if(auto frag = cast(DocumentFragment) e)
			children ~= frag.children;
		else
			children ~= e;

		sendObserverEvent(DomMutationOperations.appendChild, null, null, e);

		return e;
	}

	/// Inserts the second element to this node, right before the first param
	Element insertBefore(in Element where, Element what)
		in {
			assert(where !is null);
			assert(where.parentNode is this);
			assert(what !is null);
			assert(what.parentNode is null);
		}
		out (ret) {
			assert(where.parentNode is this);
			assert(what.parentNode is this);

			assert(what.parentDocument is this.parentDocument);
			assert(ret is what);
		}
	body {
		foreach(i, e; children) {
			if(e is where) {
				if(auto frag = cast(DocumentFragment) what)
					children = children[0..i] ~ frag.children ~ children[i..$];
				else
					children = children[0..i] ~ what ~ children[i..$];
				what.parentDocument = this.parentDocument;
				what.parentNode = this;
				return what;
			}
		}

		return what;

		assert(0);
	}

	/++
		Inserts the given element `what` as a sibling of the `this` element, after the element `where` in the parent node.
	+/
	Element insertAfter(in Element where, Element what)
		in {
			assert(where !is null);
			assert(where.parentNode is this);
			assert(what !is null);
			assert(what.parentNode is null);
		}
		out (ret) {
			assert(where.parentNode is this);
			assert(what.parentNode is this);
			assert(what.parentDocument is this.parentDocument);
			assert(ret is what);
		}
	body {
		foreach(i, e; children) {
			if(e is where) {
				if(auto frag = cast(DocumentFragment) what)
					children = children[0 .. i + 1] ~ what.children ~ children[i + 1 .. $];
				else
					children = children[0 .. i + 1] ~ what ~ children[i + 1 .. $];
				what.parentNode = this;
				what.parentDocument = this.parentDocument;
				return what;
			}
		}

		return what;

		assert(0);
	}

	/// swaps one child for a new thing. Returns the old child which is now parentless.
	Element swapNode(Element child, Element replacement)
		in {
			assert(child !is null);
			assert(replacement !is null);
			assert(child.parentNode is this);
		}
		out(ret) {
			assert(ret is child);
			assert(ret.parentNode is null);
			assert(replacement.parentNode is this);
			assert(replacement.parentDocument is this.parentDocument);
		}
	body {
		foreach(ref c; this.children)
			if(c is child) {
				c.parentNode = null;
				c = replacement;
				c.parentNode = this;
				c.parentDocument = this.parentDocument;
				return child;
			}
		assert(0);
	}


	/++
		Appends the given to the node.


		Calling `e.appendText(" hi")` on `<example>text <b>bold</b></example>`
		yields `<example>text <b>bold</b> hi</example>`.

		See_Also:
			[firstInnerText], [directText], [innerText], [appendChild]
	+/
	@scriptable
	Element appendText(string text) {
		Element e = new TextNode(parentDocument, text);
		appendChild(e);
		return this;
	}

	/++
		Returns child elements which are of a tag type (excludes text, comments, etc.).


		childElements of `<example>text <b>bold</b></example>` is just the `<b>` tag.

		Params:
			tagName = filter results to only the child elements with the given tag name.
	+/
	@property Element[] childElements(string tagName = null) {
		Element[] ret;
		foreach(c; children)
			if(c.nodeType == 1 && (tagName is null || c.tagName == tagName))
				ret ~= c;
		return ret;
	}

	/++
		Appends the given html to the element, returning the elements appended


		This is similar to `element.innerHTML += "html string";` in Javascript.
	+/
	@scriptable
	Element[] appendHtml(string html) {
		Document d = new Document("<root>" ~ html ~ "</root>");
		return stealChildren(d.root);
	}


	///.
	void insertChildAfter(Element child, Element where)
		in {
			assert(child !is null);
			assert(where !is null);
			assert(where.parentNode is this);
			assert(!selfClosed);
			//assert(isInArray(where, children));
		}
		out {
			assert(child.parentNode is this);
			assert(where.parentNode is this);
			//assert(isInArray(where, children));
			//assert(isInArray(child, children));
		}
	body {
		foreach(ref i, c; children) {
			if(c is where) {
				i++;
				if(auto frag = cast(DocumentFragment) child)
					children = children[0..i] ~ child.children ~ children[i..$];
				else
					children = children[0..i] ~ child ~ children[i..$];
				child.parentNode = this;
				child.parentDocument = this.parentDocument;
				break;
			}
		}
	}

	/++
		Reparents all the child elements of `e` to `this`, leaving `e` childless.

		Params:
			e = the element whose children you want to steal
			position = an existing child element in `this` before which you want the stolen children to be inserted. If `null`, it will append the stolen children at the end of our current children.
	+/
	Element[] stealChildren(Element e, Element position = null)
		in {
			assert(!selfClosed);
			assert(e !is null);
			//if(position !is null)
				//assert(isInArray(position, children));
		}
		out (ret) {
			assert(e.children.length == 0);
			// all the parentNode is this checks fail because DocumentFragments do not appear in the parent tree, they are invisible...
			version(none)
			debug foreach(child; ret) {
				assert(child.parentNode is this);
				assert(child.parentDocument is this.parentDocument);
			}
		}
	body {
		foreach(c; e.children) {
			c.parentNode = this;
			c.parentDocument = this.parentDocument;
		}
		if(position is null)
			children ~= e.children;
		else {
			foreach(i, child; children) {
				if(child is position) {
					children = children[0..i] ~
						e.children ~
						children[i..$];
					break;
				}
			}
		}

		auto ret = e.children[];
		e.children.length = 0;

		return ret;
	}

    	/// Puts the current element first in our children list. The given element must not have a parent already.
	Element prependChild(Element e)
		in {
			assert(e.parentNode is null);
			assert(!selfClosed);
		}
		out {
			assert(e.parentNode is this);
			assert(e.parentDocument is this.parentDocument);
			assert(children[0] is e);
		}
	body {
		e.parentNode = this;
		e.parentDocument = this.parentDocument;
		if(auto frag = cast(DocumentFragment) e)
			children = e.children ~ children;
		else
			children = e ~ children;
		return e;
	}


	/**
		Returns a string containing all child elements, formatted such that it could be pasted into
		an XML file.
	*/
	@property string innerHTML(Appender!string where = appender!string()) const {
		if(children is null)
			return "";

		auto start = where.data.length;

		foreach(child; children) {
			assert(child !is null);

			child.writeToAppender(where);
		}

		return where.data[start .. $];
	}

	/**
		Takes some html and replaces the element's children with the tree made from the string.
	*/
	@property Element innerHTML(string html, bool strict = false) {
		if(html.length)
			selfClosed = false;

		if(html.length == 0) {
			// I often say innerHTML = ""; as a shortcut to clear it out,
			// so let's optimize that slightly.
			removeAllChildren();
			return this;
		}

		auto doc = new Document();
		doc.parseUtf8("<innerhtml>" ~ html ~ "</innerhtml>", strict, strict); // FIXME: this should preserve the strictness of the parent document

		children = doc.root.children;
		foreach(c; children) {
			c.parentNode = this;
			c.parentDocument = this.parentDocument;
		}

		reparentTreeDocuments();

		doc.root.children = null;

		return this;
	}

	/// ditto
	@property Element innerHTML(Html html) {
		return this.innerHTML = html.source;
	}

	private void reparentTreeDocuments() {
		foreach(c; this.tree)
			c.parentDocument = this.parentDocument;
	}

	/**
		Replaces this node with the given html string, which is parsed

		Note: this invalidates the this reference, since it is removed
		from the tree.

		Returns the new children that replace this.
	*/
	@property Element[] outerHTML(string html) {
		auto doc = new Document();
		doc.parseUtf8("<innerhtml>" ~ html ~ "</innerhtml>"); // FIXME: needs to preserve the strictness

		children = doc.root.children;
		foreach(c; children) {
			c.parentNode = this;
			c.parentDocument = this.parentDocument;
		}


		reparentTreeDocuments();


		stripOut();

		return doc.root.children;
	}

	/++
		Returns all the html for this element, including the tag itself.

		This is equivalent to calling toString().
	+/
	@property string outerHTML() {
		return this.toString();
	}

	/// This sets the inner content of the element *without* trying to parse it.
	/// You can inject any code in there; this serves as an escape hatch from the dom.
	///
	/// The only times you might actually need it are for < style > and < script > tags in html.
	/// Other than that, innerHTML and/or innerText should do the job.
	@property void innerRawSource(string rawSource) {
		children.length = 0;
		auto rs = new RawSource(parentDocument, rawSource);
		rs.parentNode = this;

		children ~= rs;
	}

	///.
	Element replaceChild(Element find, Element replace)
		in {
			assert(find !is null);
			assert(replace !is null);
			assert(replace.parentNode is null);
		}
		out(ret) {
			assert(ret is replace);
			assert(replace.parentNode is this);
			assert(replace.parentDocument is this.parentDocument);
			assert(find.parentNode is null);
		}
	body {
		// FIXME
		//if(auto frag = cast(DocumentFragment) replace)
			//return this.replaceChild(frag, replace.children);
		for(int i = 0; i < children.length; i++) {
			if(children[i] is find) {
				replace.parentNode = this;
				children[i].parentNode = null;
				children[i] = replace;
				replace.parentDocument = this.parentDocument;
				return replace;
			}
		}

		throw new Exception("no such child");
	}

	/**
		Replaces the given element with a whole group.
	*/
	void replaceChild(Element find, Element[] replace)
		in {
			assert(find !is null);
			assert(replace !is null);
			assert(find.parentNode is this);
			debug foreach(r; replace)
				assert(r.parentNode is null);
		}
		out {
			assert(find.parentNode is null);
			assert(children.length >= replace.length);
			debug foreach(child; children)
				assert(child !is find);
			debug foreach(r; replace)
				assert(r.parentNode is this);
		}
	body {
		if(replace.length == 0) {
			removeChild(find);
			return;
		}
		assert(replace.length);
		for(int i = 0; i < children.length; i++) {
			if(children[i] is find) {
				children[i].parentNode = null; // this element should now be dead
				children[i] = replace[0];
				foreach(e; replace) {
					e.parentNode = this;
					e.parentDocument = this.parentDocument;
				}

				children = .insertAfter(children, i, replace[1..$]);

				return;
			}
		}

		throw new Exception("no such child");
	}


	/**
		Removes the given child from this list.

		Returns the removed element.
	*/
	Element removeChild(Element c)
		in {
			assert(c !is null);
			assert(c.parentNode is this);
		}
		out {
			debug foreach(child; children)
				assert(child !is c);
			assert(c.parentNode is null);
		}
	body {
		foreach(i, e; children) {
			if(e is c) {
				children = children[0..i] ~ children [i+1..$];
				c.parentNode = null;
				return c;
			}
		}

		throw new Exception("no such child");
	}

	/// This removes all the children from this element, returning the old list.
	Element[] removeChildren()
		out (ret) {
			assert(children.length == 0);
			debug foreach(r; ret)
				assert(r.parentNode is null);
		}
	body {
		Element[] oldChildren = children.dup;
		foreach(c; oldChildren)
			c.parentNode = null;

		children.length = 0;

		return oldChildren;
	}

	/**
		Fetch the inside text, with all tags stripped out.

		<p>cool <b>api</b> &amp; code dude<p>
		innerText of that is "cool api & code dude".

		This does not match what real innerText does!
		http://perfectionkills.com/the-poor-misunderstood-innerText/

		It is more like textContent.
	*/
	@scriptable
	@property string innerText() const {
		string s;
		foreach(child; children) {
			if(child.nodeType != NodeType.Text)
				s ~= child.innerText;
			else
				s ~= child.nodeValue();
		}
		return s;
	}

	///
	alias textContent = innerText;

	/**
		Sets the inside text, replacing all children. You don't
		have to worry about entity encoding.
	*/
	@scriptable
	@property void innerText(string text) {
		selfClosed = false;
		Element e = new TextNode(parentDocument, text);
		e.parentNode = this;
		children = [e];
	}

	/**
		Strips this node out of the document, replacing it with the given text
	*/
	@property void outerText(string text) {
		parentNode.replaceChild(this, new TextNode(parentDocument, text));
	}

	/**
		Same result as innerText; the tag with all inner tags stripped out
	*/
	@property string outerText() const {
		return innerText;
	}


	/* *******************************
	          Miscellaneous
	*********************************/

	/// This is a full clone of the element. Alias for cloneNode(true) now. Don't extend it.
	@property Element cloned()
	/+
		out(ret) {
			// FIXME: not sure why these fail...
			assert(ret.children.length == this.children.length, format("%d %d", ret.children.length, this.children.length));
			assert(ret.tagName == this.tagName);
		}
	body {
	+/
	{
		return this.cloneNode(true);
	}

	/// Clones the node. If deepClone is true, clone all inner tags too. If false, only do this tag (and its attributes), but it will have no contents.
	Element cloneNode(bool deepClone) {
		auto e = Element.make(this.tagName);
		e.parentDocument = this.parentDocument;
		e.attributes = this.attributes.aadup;
		e.selfClosed = this.selfClosed;

		if(deepClone) {
			foreach(child; children) {
				e.appendChild(child.cloneNode(true));
			}
		}
		

		return e;
	}

	/// W3C DOM interface. Only really meaningful on [TextNode] instances, but the interface is present on the base class.
	string nodeValue() const {
		return "";
	}

	// should return int
	///.
	@property int nodeType() const {
		return 1;
	}


	invariant () {
		assert(tagName.indexOf(" ") == -1);

		if(children !is null)
		debug foreach(child; children) {
		//	assert(parentNode !is null);
			assert(child !is null);
	//		assert(child.parentNode is this, format("%s is not a parent of %s (it thought it was %s)", tagName, child.tagName, child.parentNode is null ? "null" : child.parentNode.tagName));
			assert(child !is this);
			//assert(child !is parentNode);
		}

		/+ // only depend on parentNode's accuracy if you shuffle things around and use the top elements - where the contracts guarantee it on out
		if(parentNode !is null) {
			// if you have a parent, you should share the same parentDocument; this is appendChild()'s job
			auto lol = cast(TextNode) this;
			assert(parentDocument is parentNode.parentDocument, lol is null ? this.tagName : lol.contents);
		}
		+/
		//assert(parentDocument !is null); // no more; if it is present, we use it, but it is not required
		// reason is so you can create these without needing a reference to the document
	}

	/**
		Turns the whole element, including tag, attributes, and children, into a string which could be pasted into
		an XML file.
	*/
	override string toString() const {
		return writeToAppender();
	}

	protected string toPrettyStringIndent(bool insertComments, int indentationLevel, string indentWith) const {
		if(indentWith is null)
			return null;
		string s;

		if(insertComments) s ~= "<!--";
		s ~= "\n";
		foreach(indent; 0 .. indentationLevel)
			s ~= indentWith;
		if(insertComments) s ~= "-->";

		return s;
	}

	/++
		Writes out with formatting. Be warned: formatting changes the contents. Use ONLY
		for eyeball debugging.
	+/
	string toPrettyString(bool insertComments = false, int indentationLevel = 0, string indentWith = "\t") const {

		// first step is to concatenate any consecutive text nodes to simplify
		// the white space analysis. this changes the tree! but i'm allowed since
		// the comment always says it changes the comments
		//
		// actually i'm not allowed cuz it is const so i will cheat and lie
		/+
		TextNode lastTextChild = null;
		for(int a = 0; a < this.children.length; a++) {
			auto child = this.children[a];
			if(auto tn = cast(TextNode) child) {
				if(lastTextChild) {
					lastTextChild.contents ~= tn.contents;
					for(int b = a; b < this.children.length - 1; b++)
						this.children[b] = this.children[b + 1];
					this.children = this.children[0 .. $-1];
				} else {
					lastTextChild = tn;
				}
			} else {
				lastTextChild = null;
			}
		}
		+/

		const(Element)[] children;

		TextNode lastTextChild = null;
		for(int a = 0; a < this.children.length; a++) {
			auto child = this.children[a];
			if(auto tn = cast(const(TextNode)) child) {
				if(lastTextChild !is null) {
					lastTextChild.contents ~= tn.contents;
				} else {
					lastTextChild = new TextNode("");
					lastTextChild.parentNode = cast(Element) this;
					lastTextChild.contents ~= tn.contents;
					children ~= lastTextChild;
				}
			} else {
				lastTextChild = null;
				children ~= child;
			}
		}

		string s = toPrettyStringIndent(insertComments, indentationLevel, indentWith);

		s ~= "<";
		s ~= tagName;

		// i sort these for consistent output. might be more legible
		// but especially it keeps it the same for diff purposes.
		import std.algorithm : sort;
		auto keys = sort(attributes.keys);
		foreach(n; keys) {
			auto v = attributes[n];
			s ~= " ";
			s ~= n;
			s ~= "=\"";
			s ~= htmlEntitiesEncode(v);
			s ~= "\"";
		}

		if(selfClosed){
			s ~= " />";
			return s;
		}

		s ~= ">";

		// for simple `<collection><item>text</item><item>text</item></collection>`, let's
		// just keep them on the same line
		if(tagName.isInArray(inlineElements) || allAreInlineHtml(children)) {
			foreach(child; children) {
				s ~= child.toString();//toPrettyString(false, 0, null);
			}
		} else {
			foreach(child; children) {
				assert(child !is null);

				s ~= child.toPrettyString(insertComments, indentationLevel + 1, indentWith);
			}

			s ~= toPrettyStringIndent(insertComments, indentationLevel, indentWith);
		}

		s ~= "</";
		s ~= tagName;
		s ~= ">";

		return s;
	}

	/+
	/// Writes out the opening tag only, if applicable.
	string writeTagOnly(Appender!string where = appender!string()) const {
	+/

	/// This is the actual implementation used by toString. You can pass it a preallocated buffer to save some time.
	/// Note: the ordering of attributes in the string is undefined.
	/// Returns the string it creates.
	string writeToAppender(Appender!string where = appender!string()) const {
		assert(tagName !is null);

		where.reserve((this.children.length + 1) * 512);

		auto start = where.data.length;

		where.put("<");
		where.put(tagName);

		import std.algorithm : sort;
		auto keys = sort(attributes.keys);
		foreach(n; keys) {
			auto v = attributes[n]; // I am sorting these for convenience with another project. order of AAs is undefined, so I'm allowed to do it.... and it is still undefined, I might change it back later.
			//assert(v !is null);
			where.put(" ");
			where.put(n);
			where.put("=\"");
			htmlEntitiesEncode(v, where);
			where.put("\"");
		}

		if(selfClosed){
			where.put(" />");
			return where.data[start .. $];
		}

		where.put('>');

		innerHTML(where);

		where.put("</");
		where.put(tagName);
		where.put('>');

		return where.data[start .. $];
	}

	/**
		Returns a lazy range of all its children, recursively.
	*/
	@property ElementStream tree() {
		return new ElementStream(this);
	}

	// I moved these from Form because they are generally useful.
	// Ideally, I'd put them in arsd.html and use UFCS, but that doesn't work with the opDispatch here.
	/// Tags: HTML, HTML5
	// FIXME: add overloads for other label types...
	Element addField(string label, string name, string type = "text", FormFieldOptions fieldOptions = FormFieldOptions.none) {
		auto fs = this;
		auto i = fs.addChild("label");

		if(!(type == "checkbox" || type == "radio"))
			i.addChild("span", label);

		Element input;
		if(type == "textarea")
			input = i.addChild("textarea").
			setAttribute("name", name).
			setAttribute("rows", "6");
		else
			input = i.addChild("input").
			setAttribute("name", name).
			setAttribute("type", type);

		if(type == "checkbox" || type == "radio")
			i.addChild("span", label);

		// these are html 5 attributes; you'll have to implement fallbacks elsewhere. In Javascript or maybe I'll add a magic thing to html.d later.
		fieldOptions.applyToElement(input);
		return i;
	}

	Element addField(Element label, string name, string type = "text", FormFieldOptions fieldOptions = FormFieldOptions.none) {
		auto fs = this;
		auto i = fs.addChild("label");
		i.addChild(label);
		Element input;
		if(type == "textarea")
			input = i.addChild("textarea").
			setAttribute("name", name).
			setAttribute("rows", "6");
		else
			input = i.addChild("input").
			setAttribute("name", name).
			setAttribute("type", type);

		// these are html 5 attributes; you'll have to implement fallbacks elsewhere. In Javascript or maybe I'll add a magic thing to html.d later.
		fieldOptions.applyToElement(input);
		return i;
	}

	Element addField(string label, string name, FormFieldOptions fieldOptions) {
		return addField(label, name, "text", fieldOptions);
	}

	Element addField(string label, string name, string[string] options, FormFieldOptions fieldOptions = FormFieldOptions.none) {
		auto fs = this;
		auto i = fs.addChild("label");
		i.addChild("span", label);
		auto sel = i.addChild("select").setAttribute("name", name);

		foreach(k, opt; options)
			sel.addChild("option", opt, k);

		// FIXME: implement requirements somehow

		return i;
	}

	Element addSubmitButton(string label = null) {
		auto t = this;
		auto holder = t.addChild("div");
		holder.addClass("submit-holder");
		auto i = holder.addChild("input");
		i.type = "submit";
		if(label.length)
			i.value = label;
		return holder;
	}

}

// FIXME: since Document loosens the input requirements, it should probably be the sub class...
/// Specializes Document for handling generic XML. (always uses strict mode, uses xml mime type and file header)
/// Group: core_functionality
class XmlDocument : Document {
	this(string data) {
		selfClosedElements = null;
		contentType = "text/xml; charset=utf-8";
		_prolog = `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n";

		parseStrict(data);
	}
}




import std.string;

/* domconvenience follows { */

/// finds comments that match the given txt. Case insensitive, strips whitespace.
/// Group: core_functionality
Element[] findComments(Document document, string txt) {
	return findComments(document.root, txt);
}

/// ditto
Element[] findComments(Element element, string txt) {
	txt = txt.strip().toLower();
	Element[] ret;

	foreach(comment; element.getElementsByTagName("#comment")) {
		string t = comment.nodeValue().strip().toLower();
		if(t == txt)
			ret ~= comment;
	}

	return ret;
}

/// An option type that propagates null. See: [Element.optionSelector]
/// Group: implementations
struct MaybeNullElement(SomeElementType) {
	this(SomeElementType ele) {
		this.element = ele;
	}
	SomeElementType element;

	/// Forwards to the element, wit a null check inserted that propagates null.
	auto opDispatch(string method, T...)(T args) {
		alias type = typeof(__traits(getMember, element, method)(args));
		static if(is(type : Element)) {
			if(element is null)
				return MaybeNullElement!type(null);
			return __traits(getMember, element, method)(args);
		} else static if(is(type == string)) {
			if(element is null)
				return cast(string) null;
			return __traits(getMember, element, method)(args);
		} else static if(is(type == void)) {
			if(element is null)
				return;
			__traits(getMember, element, method)(args);
		} else {
			static assert(0);
		}
	}

	/// Allows implicit casting to the wrapped element.
	alias element this;
}

/++
	A collection of elements which forwards methods to the children.
+/
/// Group: implementations
struct ElementCollection {
	///
	this(Element e) {
		elements = [e];
	}

	///
	this(Element e, string selector) {
		elements = e.querySelectorAll(selector);
	}

	///
	this(Element[] e) {
		elements = e;
	}

	Element[] elements;
	//alias elements this; // let it implicitly convert to the underlying array

	///
	ElementCollection opIndex(string selector) {
		ElementCollection ec;
		foreach(e; elements)
			ec.elements ~= e.getElementsBySelector(selector);
		return ec;
	}

	///
	Element opIndex(int i) {
		return elements[i];
	}

	/// if you slice it, give the underlying array for easy forwarding of the
	/// collection to range expecting algorithms or looping over.
	Element[] opSlice() {
		return elements;
	}

	/// And input range primitives so we can foreach over this
	void popFront() {
		elements = elements[1..$];
	}

	/// ditto
	Element front() {
		return elements[0];
	}

	/// ditto
	bool empty() {
		return !elements.length;
	}

	/++
		Collects strings from the collection, concatenating them together
		Kinda like running reduce and ~= on it.

		---
		document["p"].collect!"innerText";
		---
	+/
	string collect(string method)(string separator = "") {
		string text;
		foreach(e; elements) {
			text ~= mixin("e." ~ method);
			text ~= separator;
		}
		return text;
	}

	/// Forward method calls to each individual [Element|element] of the collection
	/// returns this so it can be chained.
	ElementCollection opDispatch(string name, T...)(T t) {
		foreach(e; elements) {
			mixin("e." ~ name)(t);
		}
		return this;
	}

	/++
		Calls [Element.wrapIn] on each member of the collection, but clones the argument `what` for each one.
	+/
	ElementCollection wrapIn(Element what) {
		foreach(e; elements) {
			e.wrapIn(what.cloneNode(false));
		}

		return this;
	}

	/// Concatenates two ElementCollection together.
	ElementCollection opBinary(string op : "~")(ElementCollection rhs) {
		return ElementCollection(this.elements ~ rhs.elements);
	}
}


/// this puts in operators and opDispatch to handle string indexes and properties, forwarding to get and set functions.
/// Group: implementations
mixin template JavascriptStyleDispatch() {
	///
	string opDispatch(string name)(string v = null) if(name != "popFront") { // popFront will make this look like a range. Do not want.
		if(v !is null)
			return set(name, v);
		return get(name);
	}

	///
	string opIndex(string key) const {
		return get(key);
	}

	///
	string opIndexAssign(string value, string field) {
		return set(field, value);
	}

	// FIXME: doesn't seem to work
	string* opBinary(string op)(string key)  if(op == "in") {
		return key in fields;
	}
}

/// A proxy object to do the Element class' dataset property. See Element.dataset for more info.
///
/// Do not create this object directly.
/// Group: implementations
struct DataSet {
	///
	this(Element e) {
		this._element = e;
	}

	private Element _element;
	///
	string set(string name, string value) {
		_element.setAttribute("data-" ~ unCamelCase(name), value);
		return value;
	}

	///
	string get(string name) const {
		return _element.getAttribute("data-" ~ unCamelCase(name));
	}

	///
	mixin JavascriptStyleDispatch!();
}

/// Proxy object for attributes which will replace the main opDispatch eventually
/// Group: implementations
struct AttributeSet {
	///
	this(Element e) {
		this._element = e;
	}

	private Element _element;
	///
	string set(string name, string value) {
		_element.setAttribute(name, value);
		return value;
	}

	///
	string get(string name) const {
		return _element.getAttribute(name);
	}

	///
	mixin JavascriptStyleDispatch!();
}



/// for style, i want to be able to set it with a string like a plain attribute,
/// but also be able to do properties Javascript style.

/// Group: implementations
struct ElementStyle {
	this(Element parent) {
		_element = parent;
	}

	Element _element;

	@property ref inout(string) _attribute() inout {
		auto s = "style" in _element.attributes;
		if(s is null) {
			auto e = cast() _element; // const_cast
			e.attributes["style"] = ""; // we need something to reference
			s = cast(inout) ("style" in e.attributes);
		}

		assert(s !is null);
		return *s;
	}

	alias _attribute this; // this is meant to allow element.style = element.style ~ " string "; to still work.

	string set(string name, string value) {
		if(name.length == 0)
			return value;
		if(name == "cssFloat")
			name = "float";
		else
			name = unCamelCase(name);
		auto r = rules();
		r[name] = value;

		_attribute = "";
		foreach(k, v; r) {
			if(v is null || v.length == 0) /* css can't do empty rules anyway so we'll use that to remove */
				continue;
			if(_attribute.length)
				_attribute ~= " ";
			_attribute ~= k ~ ": " ~ v ~ ";";
		}

		_element.setAttribute("style", _attribute); // this is to trigger the observer call

		return value;
	}
	string get(string name) const {
		if(name == "cssFloat")
			name = "float";
		else
			name = unCamelCase(name);
		auto r = rules();
		if(name in r)
			return r[name];
		return null;
	}

	string[string] rules() const {
		string[string] ret;
		foreach(rule;  _attribute.split(";")) {
			rule = rule.strip();
			if(rule.length == 0)
				continue;
			auto idx = rule.indexOf(":");
			if(idx == -1)
				ret[rule] = "";
			else {
				auto name = rule[0 .. idx].strip();
				auto value = rule[idx + 1 .. $].strip();

				ret[name] = value;
			}
		}

		return ret;
	}

	mixin JavascriptStyleDispatch!();
}

/// Converts a camel cased propertyName to a css style dashed property-name
string unCamelCase(string a) {
	string ret;
	foreach(c; a)
		if((c >= 'A' && c <= 'Z'))
			ret ~= "-" ~ toLower("" ~ c)[0];
		else
			ret ~= c;
	return ret;
}

/// Translates a css style property-name to a camel cased propertyName
string camelCase(string a) {
	string ret;
	bool justSawDash = false;
	foreach(c; a)
		if(c == '-') {
			justSawDash = true;
		} else {
			if(justSawDash) {
				justSawDash = false;
				ret ~= toUpper("" ~ c);
			} else
				ret ~= c;
		}
	return ret;
}









// domconvenience ends }











// @safe:

// NOTE: do *NOT* override toString on Element subclasses. It won't work.
// Instead, override writeToAppender();

// FIXME: should I keep processing instructions like <?blah ?> and <!-- blah --> (comments too lol)? I *want* them stripped out of most my output, but I want to be able to parse and create them too.

// Stripping them is useful for reading php as html.... but adding them
// is good for building php.

// I need to maintain compatibility with the way it is now too.

import std.string;
import std.exception;
import std.uri;
import std.array;
import std.range;

//import std.stdio;

// tag soup works for most the crap I know now! If you have two bad closing tags back to back, it might erase one, but meh
// that's rarer than the flipped closing tags that hack fixes so I'm ok with it. (Odds are it should be erased anyway; it's
// most likely a typo so I say kill kill kill.


/++
	This might belong in another module, but it represents a file with a mime type and some data.
	Document implements this interface with type = text/html (see Document.contentType for more info)
	and data = document.toString, so you can return Documents anywhere web.d expects FileResources.
+/
/// Group: bonus_functionality
interface FileResource {
	/// the content-type of the file. e.g. "text/html; charset=utf-8" or "image/png"
	@property string contentType() const;
	/// the data
	immutable(ubyte)[] getData() const;
	/++
		filename, return null if none

		History:
			Added December 25, 2020
	+/
	@property string filename() const;
}




///.
/// Group: bonus_functionality
enum NodeType { Text = 3 }


/// You can use this to do an easy null check or a dynamic cast+null check on any element.
/// Group: core_functionality
T require(T = Element, string file = __FILE__, int line = __LINE__)(Element e) if(is(T : Element))
	in {}
	out(ret) { assert(ret !is null); }
body {
	auto ret = cast(T) e;
	if(ret is null)
		throw new ElementNotFoundException(T.stringof, "passed value", e, file, line);
	return ret;
}


///.
/// Group: core_functionality
class DocumentFragment : Element {
	///.
	this(Document _parentDocument) {
		tagName = "#fragment";
		super(_parentDocument);
	}

	/++
		Creates a document fragment from the given HTML. Note that the HTML is assumed to close all tags contained inside it.

		Since: March 29, 2018 (or git tagged v2.1.0)
	+/
	this(Html html) {
		this(null);

		this.innerHTML = html.source;
	}

	///.
	override string writeToAppender(Appender!string where = appender!string()) const {
		return this.innerHTML(where);
	}

	override string toPrettyString(bool insertComments, int indentationLevel, string indentWith) const {
		string s;
		foreach(child; children)
			s ~= child.toPrettyString(insertComments, indentationLevel, indentWith);
		return s;
	}

	/// DocumentFragments don't really exist in a dom, so they ignore themselves in parent nodes
	/*
	override inout(Element) parentNode() inout {
		return children.length ? children[0].parentNode : null;
	}
	*/
	override Element parentNode(Element p) {
		this._parentNode = p;
		foreach(child; children)
			child.parentNode = p;
		return p;
	}
}

/// Given text, encode all html entities on it - &, <, >, and ". This function also
/// encodes all 8 bit characters as entities, thus ensuring the resultant text will work
/// even if your charset isn't set right. You can suppress with by setting encodeNonAscii = false
///
/// The output parameter can be given to append to an existing buffer. You don't have to
/// pass one; regardless, the return value will be usable for you, with just the data encoded.
/// Group: core_functionality
string htmlEntitiesEncode(string data, Appender!string output = appender!string(), bool encodeNonAscii = true) {
	// if there's no entities, we can save a lot of time by not bothering with the
	// decoding loop. This check cuts the net toString time by better than half in my test.
	// let me know if it made your tests worse though, since if you use an entity in just about
	// every location, the check will add time... but I suspect the average experience is like mine
	// since the check gives up as soon as it can anyway.

	bool shortcut = true;
	foreach(char c; data) {
		// non ascii chars are always higher than 127 in utf8; we'd better go to the full decoder if we see it.
		if(c == '<' || c == '>' || c == '"' || c == '&' || (encodeNonAscii && cast(uint) c > 127)) {
			shortcut = false; // there's actual work to be done
			break;
		}
	}

	if(shortcut) {
		output.put(data);
		return data;
	}

	auto start = output.data.length;

	output.reserve(data.length + 64); // grab some extra space for the encoded entities

	foreach(dchar d; data) {
		if(d == '&')
			output.put("&amp;");
		else if (d == '<')
			output.put("&lt;");
		else if (d == '>')
			output.put("&gt;");
		else if (d == '\"')
			output.put("&quot;");
//		else if (d == '\'')
//			output.put("&#39;"); // if you are in an attribute, it might be important to encode for the same reason as double quotes
			// FIXME: should I encode apostrophes too? as &#39;... I could also do space but if your html is so bad that it doesn't
			// quote attributes at all, maybe you deserve the xss. Encoding spaces will make everything really ugly so meh
			// idk about apostrophes though. Might be worth it, might not.
		else if (!encodeNonAscii || (d < 128 && d > 0))
			output.put(d);
		else
			output.put("&#" ~ std.conv.to!string(cast(int) d) ~ ";");
	}

	//assert(output !is null); // this fails on empty attributes.....
	return output.data[start .. $];

//	data = data.replace("\u00a0", "&nbsp;");
}

/// An alias for htmlEntitiesEncode; it works for xml too
/// Group: core_functionality
string xmlEntitiesEncode(string data) {
	return htmlEntitiesEncode(data);
}

/// This helper function is used for decoding html entities. It has a hard-coded list of entities and characters.
/// Group: core_functionality
dchar parseEntity(in dchar[] entity) {
	switch(entity[1..$-1]) {
		case "quot":
			return '"';
		case "apos":
			return '\'';
		case "lt":
			return '<';
		case "gt":
			return '>';
		case "amp":
			return '&';
		// the next are html rather than xml

		// Retrieved from https://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
		// Only entities that resolve to U+0009 ~ U+1D56B are stated.
		case "Tab": return '\u0009';
		case "NewLine": return '\u000A';
		case "excl": return '\u0021';
		case "QUOT": return '\u0022';
		case "num": return '\u0023';
		case "dollar": return '\u0024';
		case "percnt": return '\u0025';
		case "AMP": return '\u0026';
		case "lpar": return '\u0028';
		case "rpar": return '\u0029';
		case "ast": case "midast": return '\u002A';
		case "plus": return '\u002B';
		case "comma": return '\u002C';
		case "period": return '\u002E';
		case "sol": return '\u002F';
		case "colon": return '\u003A';
		case "semi": return '\u003B';
		case "LT": return '\u003C';
		case "equals": return '\u003D';
		case "GT": return '\u003E';
		case "quest": return '\u003F';
		case "commat": return '\u0040';
		case "lsqb": case "lbrack": return '\u005B';
		case "bsol": return '\u005C';
		case "rsqb": case "rbrack": return '\u005D';
		case "Hat": return '\u005E';
		case "lowbar": case "UnderBar": return '\u005F';
		case "grave": case "DiacriticalGrave": return '\u0060';
		case "lcub": case "lbrace": return '\u007B';
		case "verbar": case "vert": case "VerticalLine": return '\u007C';
		case "rcub": case "rbrace": return '\u007D';
		case "nbsp": case "NonBreakingSpace": return '\u00A0';
		case "iexcl": return '\u00A1';
		case "cent": return '\u00A2';
		case "pound": return '\u00A3';
		case "curren": return '\u00A4';
		case "yen": return '\u00A5';
		case "brvbar": return '\u00A6';
		case "sect": return '\u00A7';
		case "Dot": case "die": case "DoubleDot": case "uml": return '\u00A8';
		case "copy": case "COPY": return '\u00A9';
		case "ordf": return '\u00AA';
		case "laquo": return '\u00AB';
		case "not": return '\u00AC';
		case "shy": return '\u00AD';
		case "reg": case "circledR": case "REG": return '\u00AE';
		case "macr": case "strns": return '\u00AF';
		case "deg": return '\u00B0';
		case "plusmn": case "pm": case "PlusMinus": return '\u00B1';
		case "sup2": return '\u00B2';
		case "sup3": return '\u00B3';
		case "acute": case "DiacriticalAcute": return '\u00B4';
		case "micro": return '\u00B5';
		case "para": return '\u00B6';
		case "middot": case "centerdot": case "CenterDot": return '\u00B7';
		case "cedil": case "Cedilla": return '\u00B8';
		case "sup1": return '\u00B9';
		case "ordm": return '\u00BA';
		case "raquo": return '\u00BB';
		case "frac14": return '\u00BC';
		case "frac12": case "half": return '\u00BD';
		case "frac34": return '\u00BE';
		case "iquest": return '\u00BF';
		case "Agrave": return '\u00C0';
		case "Aacute": return '\u00C1';
		case "Acirc": return '\u00C2';
		case "Atilde": return '\u00C3';
		case "Auml": return '\u00C4';
		case "Aring": case "angst": return '\u00C5';
		case "AElig": return '\u00C6';
		case "Ccedil": return '\u00C7';
		case "Egrave": return '\u00C8';
		case "Eacute": return '\u00C9';
		case "Ecirc": return '\u00CA';
		case "Euml": return '\u00CB';
		case "Igrave": return '\u00CC';
		case "Iacute": return '\u00CD';
		case "Icirc": return '\u00CE';
		case "Iuml": return '\u00CF';
		case "ETH": return '\u00D0';
		case "Ntilde": return '\u00D1';
		case "Ograve": return '\u00D2';
		case "Oacute": return '\u00D3';
		case "Ocirc": return '\u00D4';
		case "Otilde": return '\u00D5';
		case "Ouml": return '\u00D6';
		case "times": return '\u00D7';
		case "Oslash": return '\u00D8';
		case "Ugrave": return '\u00D9';
		case "Uacute": return '\u00DA';
		case "Ucirc": return '\u00DB';
		case "Uuml": return '\u00DC';
		case "Yacute": return '\u00DD';
		case "THORN": return '\u00DE';
		case "szlig": return '\u00DF';
		case "agrave": return '\u00E0';
		case "aacute": return '\u00E1';
		case "acirc": return '\u00E2';
		case "atilde": return '\u00E3';
		case "auml": return '\u00E4';
		case "aring": return '\u00E5';
		case "aelig": return '\u00E6';
		case "ccedil": return '\u00E7';
		case "egrave": return '\u00E8';
		case "eacute": return '\u00E9';
		case "ecirc": return '\u00EA';
		case "euml": return '\u00EB';
		case "igrave": return '\u00EC';
		case "iacute": return '\u00ED';
		case "icirc": return '\u00EE';
		case "iuml": return '\u00EF';
		case "eth": return '\u00F0';
		case "ntilde": return '\u00F1';
		case "ograve": return '\u00F2';
		case "oacute": return '\u00F3';
		case "ocirc": return '\u00F4';
		case "otilde": return '\u00F5';
		case "ouml": return '\u00F6';
		case "divide": case "div": return '\u00F7';
		case "oslash": return '\u00F8';
		case "ugrave": return '\u00F9';
		case "uacute": return '\u00FA';
		case "ucirc": return '\u00FB';
		case "uuml": return '\u00FC';
		case "yacute": return '\u00FD';
		case "thorn": return '\u00FE';
		case "yuml": return '\u00FF';
		case "Amacr": return '\u0100';
		case "amacr": return '\u0101';
		case "Abreve": return '\u0102';
		case "abreve": return '\u0103';
		case "Aogon": return '\u0104';
		case "aogon": return '\u0105';
		case "Cacute": return '\u0106';
		case "cacute": return '\u0107';
		case "Ccirc": return '\u0108';
		case "ccirc": return '\u0109';
		case "Cdot": return '\u010A';
		case "cdot": return '\u010B';
		case "Ccaron": return '\u010C';
		case "ccaron": return '\u010D';
		case "Dcaron": return '\u010E';
		case "dcaron": return '\u010F';
		case "Dstrok": return '\u0110';
		case "dstrok": return '\u0111';
		case "Emacr": return '\u0112';
		case "emacr": return '\u0113';
		case "Edot": return '\u0116';
		case "edot": return '\u0117';
		case "Eogon": return '\u0118';
		case "eogon": return '\u0119';
		case "Ecaron": return '\u011A';
		case "ecaron": return '\u011B';
		case "Gcirc": return '\u011C';
		case "gcirc": return '\u011D';
		case "Gbreve": return '\u011E';
		case "gbreve": return '\u011F';
		case "Gdot": return '\u0120';
		case "gdot": return '\u0121';
		case "Gcedil": return '\u0122';
		case "Hcirc": return '\u0124';
		case "hcirc": return '\u0125';
		case "Hstrok": return '\u0126';
		case "hstrok": return '\u0127';
		case "Itilde": return '\u0128';
		case "itilde": return '\u0129';
		case "Imacr": return '\u012A';
		case "imacr": return '\u012B';
		case "Iogon": return '\u012E';
		case "iogon": return '\u012F';
		case "Idot": return '\u0130';
		case "imath": case "inodot": return '\u0131';
		case "IJlig": return '\u0132';
		case "ijlig": return '\u0133';
		case "Jcirc": return '\u0134';
		case "jcirc": return '\u0135';
		case "Kcedil": return '\u0136';
		case "kcedil": return '\u0137';
		case "kgreen": return '\u0138';
		case "Lacute": return '\u0139';
		case "lacute": return '\u013A';
		case "Lcedil": return '\u013B';
		case "lcedil": return '\u013C';
		case "Lcaron": return '\u013D';
		case "lcaron": return '\u013E';
		case "Lmidot": return '\u013F';
		case "lmidot": return '\u0140';
		case "Lstrok": return '\u0141';
		case "lstrok": return '\u0142';
		case "Nacute": return '\u0143';
		case "nacute": return '\u0144';
		case "Ncedil": return '\u0145';
		case "ncedil": return '\u0146';
		case "Ncaron": return '\u0147';
		case "ncaron": return '\u0148';
		case "napos": return '\u0149';
		case "ENG": return '\u014A';
		case "eng": return '\u014B';
		case "Omacr": return '\u014C';
		case "omacr": return '\u014D';
		case "Odblac": return '\u0150';
		case "odblac": return '\u0151';
		case "OElig": return '\u0152';
		case "oelig": return '\u0153';
		case "Racute": return '\u0154';
		case "racute": return '\u0155';
		case "Rcedil": return '\u0156';
		case "rcedil": return '\u0157';
		case "Rcaron": return '\u0158';
		case "rcaron": return '\u0159';
		case "Sacute": return '\u015A';
		case "sacute": return '\u015B';
		case "Scirc": return '\u015C';
		case "scirc": return '\u015D';
		case "Scedil": return '\u015E';
		case "scedil": return '\u015F';
		case "Scaron": return '\u0160';
		case "scaron": return '\u0161';
		case "Tcedil": return '\u0162';
		case "tcedil": return '\u0163';
		case "Tcaron": return '\u0164';
		case "tcaron": return '\u0165';
		case "Tstrok": return '\u0166';
		case "tstrok": return '\u0167';
		case "Utilde": return '\u0168';
		case "utilde": return '\u0169';
		case "Umacr": return '\u016A';
		case "umacr": return '\u016B';
		case "Ubreve": return '\u016C';
		case "ubreve": return '\u016D';
		case "Uring": return '\u016E';
		case "uring": return '\u016F';
		case "Udblac": return '\u0170';
		case "udblac": return '\u0171';
		case "Uogon": return '\u0172';
		case "uogon": return '\u0173';
		case "Wcirc": return '\u0174';
		case "wcirc": return '\u0175';
		case "Ycirc": return '\u0176';
		case "ycirc": return '\u0177';
		case "Yuml": return '\u0178';
		case "Zacute": return '\u0179';
		case "zacute": return '\u017A';
		case "Zdot": return '\u017B';
		case "zdot": return '\u017C';
		case "Zcaron": return '\u017D';
		case "zcaron": return '\u017E';
		case "fnof": return '\u0192';
		case "imped": return '\u01B5';
		case "gacute": return '\u01F5';
		case "jmath": return '\u0237';
		case "circ": return '\u02C6';
		case "caron": case "Hacek": return '\u02C7';
		case "breve": case "Breve": return '\u02D8';
		case "dot": case "DiacriticalDot": return '\u02D9';
		case "ring": return '\u02DA';
		case "ogon": return '\u02DB';
		case "tilde": case "DiacriticalTilde": return '\u02DC';
		case "dblac": case "DiacriticalDoubleAcute": return '\u02DD';
		case "DownBreve": return '\u0311';
		case "Alpha": return '\u0391';
		case "Beta": return '\u0392';
		case "Gamma": return '\u0393';
		case "Delta": return '\u0394';
		case "Epsilon": return '\u0395';
		case "Zeta": return '\u0396';
		case "Eta": return '\u0397';
		case "Theta": return '\u0398';
		case "Iota": return '\u0399';
		case "Kappa": return '\u039A';
		case "Lambda": return '\u039B';
		case "Mu": return '\u039C';
		case "Nu": return '\u039D';
		case "Xi": return '\u039E';
		case "Omicron": return '\u039F';
		case "Pi": return '\u03A0';
		case "Rho": return '\u03A1';
		case "Sigma": return '\u03A3';
		case "Tau": return '\u03A4';
		case "Upsilon": return '\u03A5';
		case "Phi": return '\u03A6';
		case "Chi": return '\u03A7';
		case "Psi": return '\u03A8';
		case "Omega": case "ohm": return '\u03A9';
		case "alpha": return '\u03B1';
		case "beta": return '\u03B2';
		case "gamma": return '\u03B3';
		case "delta": return '\u03B4';
		case "epsi": case "epsilon": return '\u03B5';
		case "zeta": return '\u03B6';
		case "eta": return '\u03B7';
		case "theta": return '\u03B8';
		case "iota": return '\u03B9';
		case "kappa": return '\u03BA';
		case "lambda": return '\u03BB';
		case "mu": return '\u03BC';
		case "nu": return '\u03BD';
		case "xi": return '\u03BE';
		case "omicron": return '\u03BF';
		case "pi": return '\u03C0';
		case "rho": return '\u03C1';
		case "sigmav": case "varsigma": case "sigmaf": return '\u03C2';
		case "sigma": return '\u03C3';
		case "tau": return '\u03C4';
		case "upsi": case "upsilon": return '\u03C5';
		case "phi": return '\u03C6';
		case "chi": return '\u03C7';
		case "psi": return '\u03C8';
		case "omega": return '\u03C9';
		case "thetav": case "vartheta": case "thetasym": return '\u03D1';
		case "Upsi": case "upsih": return '\u03D2';
		case "straightphi": case "phiv": case "varphi": return '\u03D5';
		case "piv": case "varpi": return '\u03D6';
		case "Gammad": return '\u03DC';
		case "gammad": case "digamma": return '\u03DD';
		case "kappav": case "varkappa": return '\u03F0';
		case "rhov": case "varrho": return '\u03F1';
		case "epsiv": case "varepsilon": case "straightepsilon": return '\u03F5';
		case "bepsi": case "backepsilon": return '\u03F6';
		case "IOcy": return '\u0401';
		case "DJcy": return '\u0402';
		case "GJcy": return '\u0403';
		case "Jukcy": return '\u0404';
		case "DScy": return '\u0405';
		case "Iukcy": return '\u0406';
		case "YIcy": return '\u0407';
		case "Jsercy": return '\u0408';
		case "LJcy": return '\u0409';
		case "NJcy": return '\u040A';
		case "TSHcy": return '\u040B';
		case "KJcy": return '\u040C';
		case "Ubrcy": return '\u040E';
		case "DZcy": return '\u040F';
		case "Acy": return '\u0410';
		case "Bcy": return '\u0411';
		case "Vcy": return '\u0412';
		case "Gcy": return '\u0413';
		case "Dcy": return '\u0414';
		case "IEcy": return '\u0415';
		case "ZHcy": return '\u0416';
		case "Zcy": return '\u0417';
		case "Icy": return '\u0418';
		case "Jcy": return '\u0419';
		case "Kcy": return '\u041A';
		case "Lcy": return '\u041B';
		case "Mcy": return '\u041C';
		case "Ncy": return '\u041D';
		case "Ocy": return '\u041E';
		case "Pcy": return '\u041F';
		case "Rcy": return '\u0420';
		case "Scy": return '\u0421';
		case "Tcy": return '\u0422';
		case "Ucy": return '\u0423';
		case "Fcy": return '\u0424';
		case "KHcy": return '\u0425';
		case "TScy": return '\u0426';
		case "CHcy": return '\u0427';
		case "SHcy": return '\u0428';
		case "SHCHcy": return '\u0429';
		case "HARDcy": return '\u042A';
		case "Ycy": return '\u042B';
		case "SOFTcy": return '\u042C';
		case "Ecy": return '\u042D';
		case "YUcy": return '\u042E';
		case "YAcy": return '\u042F';
		case "acy": return '\u0430';
		case "bcy": return '\u0431';
		case "vcy": return '\u0432';
		case "gcy": return '\u0433';
		case "dcy": return '\u0434';
		case "iecy": return '\u0435';
		case "zhcy": return '\u0436';
		case "zcy": return '\u0437';
		case "icy": return '\u0438';
		case "jcy": return '\u0439';
		case "kcy": return '\u043A';
		case "lcy": return '\u043B';
		case "mcy": return '\u043C';
		case "ncy": return '\u043D';
		case "ocy": return '\u043E';
		case "pcy": return '\u043F';
		case "rcy": return '\u0440';
		case "scy": return '\u0441';
		case "tcy": return '\u0442';
		case "ucy": return '\u0443';
		case "fcy": return '\u0444';
		case "khcy": return '\u0445';
		case "tscy": return '\u0446';
		case "chcy": return '\u0447';
		case "shcy": return '\u0448';
		case "shchcy": return '\u0449';
		case "hardcy": return '\u044A';
		case "ycy": return '\u044B';
		case "softcy": return '\u044C';
		case "ecy": return '\u044D';
		case "yucy": return '\u044E';
		case "yacy": return '\u044F';
		case "iocy": return '\u0451';
		case "djcy": return '\u0452';
		case "gjcy": return '\u0453';
		case "jukcy": return '\u0454';
		case "dscy": return '\u0455';
		case "iukcy": return '\u0456';
		case "yicy": return '\u0457';
		case "jsercy": return '\u0458';
		case "ljcy": return '\u0459';
		case "njcy": return '\u045A';
		case "tshcy": return '\u045B';
		case "kjcy": return '\u045C';
		case "ubrcy": return '\u045E';
		case "dzcy": return '\u045F';
		case "ensp": return '\u2002';
		case "emsp": return '\u2003';
		case "emsp13": return '\u2004';
		case "emsp14": return '\u2005';
		case "numsp": return '\u2007';
		case "puncsp": return '\u2008';
		case "thinsp": case "ThinSpace": return '\u2009';
		case "hairsp": case "VeryThinSpace": return '\u200A';
		case "ZeroWidthSpace": case "NegativeVeryThinSpace": case "NegativeThinSpace": case "NegativeMediumSpace": case "NegativeThickSpace": return '\u200B';
		case "zwnj": return '\u200C';
		case "zwj": return '\u200D';
		case "lrm": return '\u200E';
		case "rlm": return '\u200F';
		case "hyphen": case "dash": return '\u2010';
		case "ndash": return '\u2013';
		case "mdash": return '\u2014';
		case "horbar": return '\u2015';
		case "Verbar": case "Vert": return '\u2016';
		case "lsquo": case "OpenCurlyQuote": return '\u2018';
		case "rsquo": case "rsquor": case "CloseCurlyQuote": return '\u2019';
		case "lsquor": case "sbquo": return '\u201A';
		case "ldquo": case "OpenCurlyDoubleQuote": return '\u201C';
		case "rdquo": case "rdquor": case "CloseCurlyDoubleQuote": return '\u201D';
		case "ldquor": case "bdquo": return '\u201E';
		case "dagger": return '\u2020';
		case "Dagger": case "ddagger": return '\u2021';
		case "bull": case "bullet": return '\u2022';
		case "nldr": return '\u2025';
		case "hellip": case "mldr": return '\u2026';
		case "permil": return '\u2030';
		case "pertenk": return '\u2031';
		case "prime": return '\u2032';
		case "Prime": return '\u2033';
		case "tprime": return '\u2034';
		case "bprime": case "backprime": return '\u2035';
		case "lsaquo": return '\u2039';
		case "rsaquo": return '\u203A';
		case "oline": case "OverBar": return '\u203E';
		case "caret": return '\u2041';
		case "hybull": return '\u2043';
		case "frasl": return '\u2044';
		case "bsemi": return '\u204F';
		case "qprime": return '\u2057';
		case "MediumSpace": return '\u205F';
		case "NoBreak": return '\u2060';
		case "ApplyFunction": case "af": return '\u2061';
		case "InvisibleTimes": case "it": return '\u2062';
		case "InvisibleComma": case "ic": return '\u2063';
		case "euro": return '\u20AC';
		case "tdot": case "TripleDot": return '\u20DB';
		case "DotDot": return '\u20DC';
		case "Copf": case "complexes": return '\u2102';
		case "incare": return '\u2105';
		case "gscr": return '\u210A';
		case "hamilt": case "HilbertSpace": case "Hscr": return '\u210B';
		case "Hfr": case "Poincareplane": return '\u210C';
		case "quaternions": case "Hopf": return '\u210D';
		case "planckh": return '\u210E';
		case "planck": case "hbar": case "plankv": case "hslash": return '\u210F';
		case "Iscr": case "imagline": return '\u2110';
		case "image": case "Im": case "imagpart": case "Ifr": return '\u2111';
		case "Lscr": case "lagran": case "Laplacetrf": return '\u2112';
		case "ell": return '\u2113';
		case "Nopf": case "naturals": return '\u2115';
		case "numero": return '\u2116';
		case "copysr": return '\u2117';
		case "weierp": case "wp": return '\u2118';
		case "Popf": case "primes": return '\u2119';
		case "rationals": case "Qopf": return '\u211A';
		case "Rscr": case "realine": return '\u211B';
		case "real": case "Re": case "realpart": case "Rfr": return '\u211C';
		case "reals": case "Ropf": return '\u211D';
		case "rx": return '\u211E';
		case "trade": case "TRADE": return '\u2122';
		case "integers": case "Zopf": return '\u2124';
		case "mho": return '\u2127';
		case "Zfr": case "zeetrf": return '\u2128';
		case "iiota": return '\u2129';
		case "bernou": case "Bernoullis": case "Bscr": return '\u212C';
		case "Cfr": case "Cayleys": return '\u212D';
		case "escr": return '\u212F';
		case "Escr": case "expectation": return '\u2130';
		case "Fscr": case "Fouriertrf": return '\u2131';
		case "phmmat": case "Mellintrf": case "Mscr": return '\u2133';
		case "order": case "orderof": case "oscr": return '\u2134';
		case "alefsym": case "aleph": return '\u2135';
		case "beth": return '\u2136';
		case "gimel": return '\u2137';
		case "daleth": return '\u2138';
		case "CapitalDifferentialD": case "DD": return '\u2145';
		case "DifferentialD": case "dd": return '\u2146';
		case "ExponentialE": case "exponentiale": case "ee": return '\u2147';
		case "ImaginaryI": case "ii": return '\u2148';
		case "frac13": return '\u2153';
		case "frac23": return '\u2154';
		case "frac15": return '\u2155';
		case "frac25": return '\u2156';
		case "frac35": return '\u2157';
		case "frac45": return '\u2158';
		case "frac16": return '\u2159';
		case "frac56": return '\u215A';
		case "frac18": return '\u215B';
		case "frac38": return '\u215C';
		case "frac58": return '\u215D';
		case "frac78": return '\u215E';
		case "larr": case "leftarrow": case "LeftArrow": case "slarr": case "ShortLeftArrow": return '\u2190';
		case "uarr": case "uparrow": case "UpArrow": case "ShortUpArrow": return '\u2191';
		case "rarr": case "rightarrow": case "RightArrow": case "srarr": case "ShortRightArrow": return '\u2192';
		case "darr": case "downarrow": case "DownArrow": case "ShortDownArrow": return '\u2193';
		case "harr": case "leftrightarrow": case "LeftRightArrow": return '\u2194';
		case "varr": case "updownarrow": case "UpDownArrow": return '\u2195';
		case "nwarr": case "UpperLeftArrow": case "nwarrow": return '\u2196';
		case "nearr": case "UpperRightArrow": case "nearrow": return '\u2197';
		case "searr": case "searrow": case "LowerRightArrow": return '\u2198';
		case "swarr": case "swarrow": case "LowerLeftArrow": return '\u2199';
		case "nlarr": case "nleftarrow": return '\u219A';
		case "nrarr": case "nrightarrow": return '\u219B';
		case "rarrw": case "rightsquigarrow": return '\u219D';
		case "Larr": case "twoheadleftarrow": return '\u219E';
		case "Uarr": return '\u219F';
		case "Rarr": case "twoheadrightarrow": return '\u21A0';
		case "Darr": return '\u21A1';
		case "larrtl": case "leftarrowtail": return '\u21A2';
		case "rarrtl": case "rightarrowtail": return '\u21A3';
		case "LeftTeeArrow": case "mapstoleft": return '\u21A4';
		case "UpTeeArrow": case "mapstoup": return '\u21A5';
		case "map": case "RightTeeArrow": case "mapsto": return '\u21A6';
		case "DownTeeArrow": case "mapstodown": return '\u21A7';
		case "larrhk": case "hookleftarrow": return '\u21A9';
		case "rarrhk": case "hookrightarrow": return '\u21AA';
		case "larrlp": case "looparrowleft": return '\u21AB';
		case "rarrlp": case "looparrowright": return '\u21AC';
		case "harrw": case "leftrightsquigarrow": return '\u21AD';
		case "nharr": case "nleftrightarrow": return '\u21AE';
		case "lsh": case "Lsh": return '\u21B0';
		case "rsh": case "Rsh": return '\u21B1';
		case "ldsh": return '\u21B2';
		case "rdsh": return '\u21B3';
		case "crarr": return '\u21B5';
		case "cularr": case "curvearrowleft": return '\u21B6';
		case "curarr": case "curvearrowright": return '\u21B7';
		case "olarr": case "circlearrowleft": return '\u21BA';
		case "orarr": case "circlearrowright": return '\u21BB';
		case "lharu": case "LeftVector": case "leftharpoonup": return '\u21BC';
		case "lhard": case "leftharpoondown": case "DownLeftVector": return '\u21BD';
		case "uharr": case "upharpoonright": case "RightUpVector": return '\u21BE';
		case "uharl": case "upharpoonleft": case "LeftUpVector": return '\u21BF';
		case "rharu": case "RightVector": case "rightharpoonup": return '\u21C0';
		case "rhard": case "rightharpoondown": case "DownRightVector": return '\u21C1';
		case "dharr": case "RightDownVector": case "downharpoonright": return '\u21C2';
		case "dharl": case "LeftDownVector": case "downharpoonleft": return '\u21C3';
		case "rlarr": case "rightleftarrows": case "RightArrowLeftArrow": return '\u21C4';
		case "udarr": case "UpArrowDownArrow": return '\u21C5';
		case "lrarr": case "leftrightarrows": case "LeftArrowRightArrow": return '\u21C6';
		case "llarr": case "leftleftarrows": return '\u21C7';
		case "uuarr": case "upuparrows": return '\u21C8';
		case "rrarr": case "rightrightarrows": return '\u21C9';
		case "ddarr": case "downdownarrows": return '\u21CA';
		case "lrhar": case "ReverseEquilibrium": case "leftrightharpoons": return '\u21CB';
		case "rlhar": case "rightleftharpoons": case "Equilibrium": return '\u21CC';
		case "nlArr": case "nLeftarrow": return '\u21CD';
		case "nhArr": case "nLeftrightarrow": return '\u21CE';
		case "nrArr": case "nRightarrow": return '\u21CF';
		case "lArr": case "Leftarrow": case "DoubleLeftArrow": return '\u21D0';
		case "uArr": case "Uparrow": case "DoubleUpArrow": return '\u21D1';
		case "rArr": case "Rightarrow": case "Implies": case "DoubleRightArrow": return '\u21D2';
		case "dArr": case "Downarrow": case "DoubleDownArrow": return '\u21D3';
		case "hArr": case "Leftrightarrow": case "DoubleLeftRightArrow": case "iff": return '\u21D4';
		case "vArr": case "Updownarrow": case "DoubleUpDownArrow": return '\u21D5';
		case "nwArr": return '\u21D6';
		case "neArr": return '\u21D7';
		case "seArr": return '\u21D8';
		case "swArr": return '\u21D9';
		case "lAarr": case "Lleftarrow": return '\u21DA';
		case "rAarr": case "Rrightarrow": return '\u21DB';
		case "zigrarr": return '\u21DD';
		case "larrb": case "LeftArrowBar": return '\u21E4';
		case "rarrb": case "RightArrowBar": return '\u21E5';
		case "duarr": case "DownArrowUpArrow": return '\u21F5';
		case "loarr": return '\u21FD';
		case "roarr": return '\u21FE';
		case "hoarr": return '\u21FF';
		case "forall": case "ForAll": return '\u2200';
		case "comp": case "complement": return '\u2201';
		case "part": case "PartialD": return '\u2202';
		case "exist": case "Exists": return '\u2203';
		case "nexist": case "NotExists": case "nexists": return '\u2204';
		case "empty": case "emptyset": case "emptyv": case "varnothing": return '\u2205';
		case "nabla": case "Del": return '\u2207';
		case "isin": case "isinv": case "Element": case "in": return '\u2208';
		case "notin": case "NotElement": case "notinva": return '\u2209';
		case "niv": case "ReverseElement": case "ni": case "SuchThat": return '\u220B';
		case "notni": case "notniva": case "NotReverseElement": return '\u220C';
		case "prod": case "Product": return '\u220F';
		case "coprod": case "Coproduct": return '\u2210';
		case "sum": case "Sum": return '\u2211';
		case "minus": return '\u2212';
		case "mnplus": case "mp": case "MinusPlus": return '\u2213';
		case "plusdo": case "dotplus": return '\u2214';
		case "setmn": case "setminus": case "Backslash": case "ssetmn": case "smallsetminus": return '\u2216';
		case "lowast": return '\u2217';
		case "compfn": case "SmallCircle": return '\u2218';
		case "radic": case "Sqrt": return '\u221A';
		case "prop": case "propto": case "Proportional": case "vprop": case "varpropto": return '\u221D';
		case "infin": return '\u221E';
		case "angrt": return '\u221F';
		case "ang": case "angle": return '\u2220';
		case "angmsd": case "measuredangle": return '\u2221';
		case "angsph": return '\u2222';
		case "mid": case "VerticalBar": case "smid": case "shortmid": return '\u2223';
		case "nmid": case "NotVerticalBar": case "nsmid": case "nshortmid": return '\u2224';
		case "par": case "parallel": case "DoubleVerticalBar": case "spar": case "shortparallel": return '\u2225';
		case "npar": case "nparallel": case "NotDoubleVerticalBar": case "nspar": case "nshortparallel": return '\u2226';
		case "and": case "wedge": return '\u2227';
		case "or": case "vee": return '\u2228';
		case "cap": return '\u2229';
		case "cup": return '\u222A';
		case "int": case "Integral": return '\u222B';
		case "Int": return '\u222C';
		case "tint": case "iiint": return '\u222D';
		case "conint": case "oint": case "ContourIntegral": return '\u222E';
		case "Conint": case "DoubleContourIntegral": return '\u222F';
		case "Cconint": return '\u2230';
		case "cwint": return '\u2231';
		case "cwconint": case "ClockwiseContourIntegral": return '\u2232';
		case "awconint": case "CounterClockwiseContourIntegral": return '\u2233';
		case "there4": case "therefore": case "Therefore": return '\u2234';
		case "becaus": case "because": case "Because": return '\u2235';
		case "ratio": return '\u2236';
		case "Colon": case "Proportion": return '\u2237';
		case "minusd": case "dotminus": return '\u2238';
		case "mDDot": return '\u223A';
		case "homtht": return '\u223B';
		case "sim": case "Tilde": case "thksim": case "thicksim": return '\u223C';
		case "bsim": case "backsim": return '\u223D';
		case "ac": case "mstpos": return '\u223E';
		case "acd": return '\u223F';
		case "wreath": case "VerticalTilde": case "wr": return '\u2240';
		case "nsim": case "NotTilde": return '\u2241';
		case "esim": case "EqualTilde": case "eqsim": return '\u2242';
		case "sime": case "TildeEqual": case "simeq": return '\u2243';
		case "nsime": case "nsimeq": case "NotTildeEqual": return '\u2244';
		case "cong": case "TildeFullEqual": return '\u2245';
		case "simne": return '\u2246';
		case "ncong": case "NotTildeFullEqual": return '\u2247';
		case "asymp": case "ap": case "TildeTilde": case "approx": case "thkap": case "thickapprox": return '\u2248';
		case "nap": case "NotTildeTilde": case "napprox": return '\u2249';
		case "ape": case "approxeq": return '\u224A';
		case "apid": return '\u224B';
		case "bcong": case "backcong": return '\u224C';
		case "asympeq": case "CupCap": return '\u224D';
		case "bump": case "HumpDownHump": case "Bumpeq": return '\u224E';
		case "bumpe": case "HumpEqual": case "bumpeq": return '\u224F';
		case "esdot": case "DotEqual": case "doteq": return '\u2250';
		case "eDot": case "doteqdot": return '\u2251';
		case "efDot": case "fallingdotseq": return '\u2252';
		case "erDot": case "risingdotseq": return '\u2253';
		case "colone": case "coloneq": case "Assign": return '\u2254';
		case "ecolon": case "eqcolon": return '\u2255';
		case "ecir": case "eqcirc": return '\u2256';
		case "cire": case "circeq": return '\u2257';
		case "wedgeq": return '\u2259';
		case "veeeq": return '\u225A';
		case "trie": case "triangleq": return '\u225C';
		case "equest": case "questeq": return '\u225F';
		case "ne": case "NotEqual": return '\u2260';
		case "equiv": case "Congruent": return '\u2261';
		case "nequiv": case "NotCongruent": return '\u2262';
		case "le": case "leq": return '\u2264';
		case "ge": case "GreaterEqual": case "geq": return '\u2265';
		case "lE": case "LessFullEqual": case "leqq": return '\u2266';
		case "gE": case "GreaterFullEqual": case "geqq": return '\u2267';
		case "lnE": case "lneqq": return '\u2268';
		case "gnE": case "gneqq": return '\u2269';
		case "Lt": case "NestedLessLess": case "ll": return '\u226A';
		case "Gt": case "NestedGreaterGreater": case "gg": return '\u226B';
		case "twixt": case "between": return '\u226C';
		case "NotCupCap": return '\u226D';
		case "nlt": case "NotLess": case "nless": return '\u226E';
		case "ngt": case "NotGreater": case "ngtr": return '\u226F';
		case "nle": case "NotLessEqual": case "nleq": return '\u2270';
		case "nge": case "NotGreaterEqual": case "ngeq": return '\u2271';
		case "lsim": case "LessTilde": case "lesssim": return '\u2272';
		case "gsim": case "gtrsim": case "GreaterTilde": return '\u2273';
		case "nlsim": case "NotLessTilde": return '\u2274';
		case "ngsim": case "NotGreaterTilde": return '\u2275';
		case "lg": case "lessgtr": case "LessGreater": return '\u2276';
		case "gl": case "gtrless": case "GreaterLess": return '\u2277';
		case "ntlg": case "NotLessGreater": return '\u2278';
		case "ntgl": case "NotGreaterLess": return '\u2279';
		case "pr": case "Precedes": case "prec": return '\u227A';
		case "sc": case "Succeeds": case "succ": return '\u227B';
		case "prcue": case "PrecedesSlantEqual": case "preccurlyeq": return '\u227C';
		case "sccue": case "SucceedsSlantEqual": case "succcurlyeq": return '\u227D';
		case "prsim": case "precsim": case "PrecedesTilde": return '\u227E';
		case "scsim": case "succsim": case "SucceedsTilde": return '\u227F';
		case "npr": case "nprec": case "NotPrecedes": return '\u2280';
		case "nsc": case "nsucc": case "NotSucceeds": return '\u2281';
		case "sub": case "subset": return '\u2282';
		case "sup": case "supset": case "Superset": return '\u2283';
		case "nsub": return '\u2284';
		case "nsup": return '\u2285';
		case "sube": case "SubsetEqual": case "subseteq": return '\u2286';
		case "supe": case "supseteq": case "SupersetEqual": return '\u2287';
		case "nsube": case "nsubseteq": case "NotSubsetEqual": return '\u2288';
		case "nsupe": case "nsupseteq": case "NotSupersetEqual": return '\u2289';
		case "subne": case "subsetneq": return '\u228A';
		case "supne": case "supsetneq": return '\u228B';
		case "cupdot": return '\u228D';
		case "uplus": case "UnionPlus": return '\u228E';
		case "sqsub": case "SquareSubset": case "sqsubset": return '\u228F';
		case "sqsup": case "SquareSuperset": case "sqsupset": return '\u2290';
		case "sqsube": case "SquareSubsetEqual": case "sqsubseteq": return '\u2291';
		case "sqsupe": case "SquareSupersetEqual": case "sqsupseteq": return '\u2292';
		case "sqcap": case "SquareIntersection": return '\u2293';
		case "sqcup": case "SquareUnion": return '\u2294';
		case "oplus": case "CirclePlus": return '\u2295';
		case "ominus": case "CircleMinus": return '\u2296';
		case "otimes": case "CircleTimes": return '\u2297';
		case "osol": return '\u2298';
		case "odot": case "CircleDot": return '\u2299';
		case "ocir": case "circledcirc": return '\u229A';
		case "oast": case "circledast": return '\u229B';
		case "odash": case "circleddash": return '\u229D';
		case "plusb": case "boxplus": return '\u229E';
		case "minusb": case "boxminus": return '\u229F';
		case "timesb": case "boxtimes": return '\u22A0';
		case "sdotb": case "dotsquare": return '\u22A1';
		case "vdash": case "RightTee": return '\u22A2';
		case "dashv": case "LeftTee": return '\u22A3';
		case "top": case "DownTee": return '\u22A4';
		case "bottom": case "bot": case "perp": case "UpTee": return '\u22A5';
		case "models": return '\u22A7';
		case "vDash": case "DoubleRightTee": return '\u22A8';
		case "Vdash": return '\u22A9';
		case "Vvdash": return '\u22AA';
		case "VDash": return '\u22AB';
		case "nvdash": return '\u22AC';
		case "nvDash": return '\u22AD';
		case "nVdash": return '\u22AE';
		case "nVDash": return '\u22AF';
		case "prurel": return '\u22B0';
		case "vltri": case "vartriangleleft": case "LeftTriangle": return '\u22B2';
		case "vrtri": case "vartriangleright": case "RightTriangle": return '\u22B3';
		case "ltrie": case "trianglelefteq": case "LeftTriangleEqual": return '\u22B4';
		case "rtrie": case "trianglerighteq": case "RightTriangleEqual": return '\u22B5';
		case "origof": return '\u22B6';
		case "imof": return '\u22B7';
		case "mumap": case "multimap": return '\u22B8';
		case "hercon": return '\u22B9';
		case "intcal": case "intercal": return '\u22BA';
		case "veebar": return '\u22BB';
		case "barvee": return '\u22BD';
		case "angrtvb": return '\u22BE';
		case "lrtri": return '\u22BF';
		case "xwedge": case "Wedge": case "bigwedge": return '\u22C0';
		case "xvee": case "Vee": case "bigvee": return '\u22C1';
		case "xcap": case "Intersection": case "bigcap": return '\u22C2';
		case "xcup": case "Union": case "bigcup": return '\u22C3';
		case "diam": case "diamond": case "Diamond": return '\u22C4';
		case "sdot": return '\u22C5';
		case "sstarf": case "Star": return '\u22C6';
		case "divonx": case "divideontimes": return '\u22C7';
		case "bowtie": return '\u22C8';
		case "ltimes": return '\u22C9';
		case "rtimes": return '\u22CA';
		case "lthree": case "leftthreetimes": return '\u22CB';
		case "rthree": case "rightthreetimes": return '\u22CC';
		case "bsime": case "backsimeq": return '\u22CD';
		case "cuvee": case "curlyvee": return '\u22CE';
		case "cuwed": case "curlywedge": return '\u22CF';
		case "Sub": case "Subset": return '\u22D0';
		case "Sup": case "Supset": return '\u22D1';
		case "Cap": return '\u22D2';
		case "Cup": return '\u22D3';
		case "fork": case "pitchfork": return '\u22D4';
		case "epar": return '\u22D5';
		case "ltdot": case "lessdot": return '\u22D6';
		case "gtdot": case "gtrdot": return '\u22D7';
		case "Ll": return '\u22D8';
		case "Gg": case "ggg": return '\u22D9';
		case "leg": case "LessEqualGreater": case "lesseqgtr": return '\u22DA';
		case "gel": case "gtreqless": case "GreaterEqualLess": return '\u22DB';
		case "cuepr": case "curlyeqprec": return '\u22DE';
		case "cuesc": case "curlyeqsucc": return '\u22DF';
		case "nprcue": case "NotPrecedesSlantEqual": return '\u22E0';
		case "nsccue": case "NotSucceedsSlantEqual": return '\u22E1';
		case "nsqsube": case "NotSquareSubsetEqual": return '\u22E2';
		case "nsqsupe": case "NotSquareSupersetEqual": return '\u22E3';
		case "lnsim": return '\u22E6';
		case "gnsim": return '\u22E7';
		case "prnsim": case "precnsim": return '\u22E8';
		case "scnsim": case "succnsim": return '\u22E9';
		case "nltri": case "ntriangleleft": case "NotLeftTriangle": return '\u22EA';
		case "nrtri": case "ntriangleright": case "NotRightTriangle": return '\u22EB';
		case "nltrie": case "ntrianglelefteq": case "NotLeftTriangleEqual": return '\u22EC';
		case "nrtrie": case "ntrianglerighteq": case "NotRightTriangleEqual": return '\u22ED';
		case "vellip": return '\u22EE';
		case "ctdot": return '\u22EF';
		case "utdot": return '\u22F0';
		case "dtdot": return '\u22F1';
		case "disin": return '\u22F2';
		case "isinsv": return '\u22F3';
		case "isins": return '\u22F4';
		case "isindot": return '\u22F5';
		case "notinvc": return '\u22F6';
		case "notinvb": return '\u22F7';
		case "isinE": return '\u22F9';
		case "nisd": return '\u22FA';
		case "xnis": return '\u22FB';
		case "nis": return '\u22FC';
		case "notnivc": return '\u22FD';
		case "notnivb": return '\u22FE';
		case "barwed": case "barwedge": return '\u2305';
		case "Barwed": case "doublebarwedge": return '\u2306';
		case "lceil": case "LeftCeiling": return '\u2308';
		case "rceil": case "RightCeiling": return '\u2309';
		case "lfloor": case "LeftFloor": return '\u230A';
		case "rfloor": case "RightFloor": return '\u230B';
		case "drcrop": return '\u230C';
		case "dlcrop": return '\u230D';
		case "urcrop": return '\u230E';
		case "ulcrop": return '\u230F';
		case "bnot": return '\u2310';
		case "profline": return '\u2312';
		case "profsurf": return '\u2313';
		case "telrec": return '\u2315';
		case "target": return '\u2316';
		case "ulcorn": case "ulcorner": return '\u231C';
		case "urcorn": case "urcorner": return '\u231D';
		case "dlcorn": case "llcorner": return '\u231E';
		case "drcorn": case "lrcorner": return '\u231F';
		case "frown": case "sfrown": return '\u2322';
		case "smile": case "ssmile": return '\u2323';
		case "cylcty": return '\u232D';
		case "profalar": return '\u232E';
		case "topbot": return '\u2336';
		case "ovbar": return '\u233D';
		case "solbar": return '\u233F';
		case "angzarr": return '\u237C';
		case "lmoust": case "lmoustache": return '\u23B0';
		case "rmoust": case "rmoustache": return '\u23B1';
		case "tbrk": case "OverBracket": return '\u23B4';
		case "bbrk": case "UnderBracket": return '\u23B5';
		case "bbrktbrk": return '\u23B6';
		case "OverParenthesis": return '\u23DC';
		case "UnderParenthesis": return '\u23DD';
		case "OverBrace": return '\u23DE';
		case "UnderBrace": return '\u23DF';
		case "trpezium": return '\u23E2';
		case "elinters": return '\u23E7';
		case "blank": return '\u2423';
		case "oS": case "circledS": return '\u24C8';
		case "boxh": case "HorizontalLine": return '\u2500';
		case "boxv": return '\u2502';
		case "boxdr": return '\u250C';
		case "boxdl": return '\u2510';
		case "boxur": return '\u2514';
		case "boxul": return '\u2518';
		case "boxvr": return '\u251C';
		case "boxvl": return '\u2524';
		case "boxhd": return '\u252C';
		case "boxhu": return '\u2534';
		case "boxvh": return '\u253C';
		case "boxH": return '\u2550';
		case "boxV": return '\u2551';
		case "boxdR": return '\u2552';
		case "boxDr": return '\u2553';
		case "boxDR": return '\u2554';
		case "boxdL": return '\u2555';
		case "boxDl": return '\u2556';
		case "boxDL": return '\u2557';
		case "boxuR": return '\u2558';
		case "boxUr": return '\u2559';
		case "boxUR": return '\u255A';
		case "boxuL": return '\u255B';
		case "boxUl": return '\u255C';
		case "boxUL": return '\u255D';
		case "boxvR": return '\u255E';
		case "boxVr": return '\u255F';
		case "boxVR": return '\u2560';
		case "boxvL": return '\u2561';
		case "boxVl": return '\u2562';
		case "boxVL": return '\u2563';
		case "boxHd": return '\u2564';
		case "boxhD": return '\u2565';
		case "boxHD": return '\u2566';
		case "boxHu": return '\u2567';
		case "boxhU": return '\u2568';
		case "boxHU": return '\u2569';
		case "boxvH": return '\u256A';
		case "boxVh": return '\u256B';
		case "boxVH": return '\u256C';
		case "uhblk": return '\u2580';
		case "lhblk": return '\u2584';
		case "block": return '\u2588';
		case "blk14": return '\u2591';
		case "blk12": return '\u2592';
		case "blk34": return '\u2593';
		case "squ": case "square": case "Square": return '\u25A1';
		case "squf": case "squarf": case "blacksquare": case "FilledVerySmallSquare": return '\u25AA';
		case "EmptyVerySmallSquare": return '\u25AB';
		case "rect": return '\u25AD';
		case "marker": return '\u25AE';
		case "fltns": return '\u25B1';
		case "xutri": case "bigtriangleup": return '\u25B3';
		case "utrif": case "blacktriangle": return '\u25B4';
		case "utri": case "triangle": return '\u25B5';
		case "rtrif": case "blacktriangleright": return '\u25B8';
		case "rtri": case "triangleright": return '\u25B9';
		case "xdtri": case "bigtriangledown": return '\u25BD';
		case "dtrif": case "blacktriangledown": return '\u25BE';
		case "dtri": case "triangledown": return '\u25BF';
		case "ltrif": case "blacktriangleleft": return '\u25C2';
		case "ltri": case "triangleleft": return '\u25C3';
		case "loz": case "lozenge": return '\u25CA';
		case "cir": return '\u25CB';
		case "tridot": return '\u25EC';
		case "xcirc": case "bigcirc": return '\u25EF';
		case "ultri": return '\u25F8';
		case "urtri": return '\u25F9';
		case "lltri": return '\u25FA';
		case "EmptySmallSquare": return '\u25FB';
		case "FilledSmallSquare": return '\u25FC';
		case "starf": case "bigstar": return '\u2605';
		case "star": return '\u2606';
		case "phone": return '\u260E';
		case "female": return '\u2640';
		case "male": return '\u2642';
		case "spades": case "spadesuit": return '\u2660';
		case "clubs": case "clubsuit": return '\u2663';
		case "hearts": case "heartsuit": return '\u2665';
		case "diams": case "diamondsuit": return '\u2666';
		case "sung": return '\u266A';
		case "flat": return '\u266D';
		case "natur": case "natural": return '\u266E';
		case "sharp": return '\u266F';
		case "check": case "checkmark": return '\u2713';
		case "cross": return '\u2717';
		case "malt": case "maltese": return '\u2720';
		case "sext": return '\u2736';
		case "VerticalSeparator": return '\u2758';
		case "lbbrk": return '\u2772';
		case "rbbrk": return '\u2773';
		case "bsolhsub": return '\u27C8';
		case "suphsol": return '\u27C9';
		case "lobrk": case "LeftDoubleBracket": return '\u27E6';
		case "robrk": case "RightDoubleBracket": return '\u27E7';
		case "lang": case "LeftAngleBracket": case "langle": return '\u27E8';
		case "rang": case "RightAngleBracket": case "rangle": return '\u27E9';
		case "Lang": return '\u27EA';
		case "Rang": return '\u27EB';
		case "loang": return '\u27EC';
		case "roang": return '\u27ED';
		case "xlarr": case "longleftarrow": case "LongLeftArrow": return '\u27F5';
		case "xrarr": case "longrightarrow": case "LongRightArrow": return '\u27F6';
		case "xharr": case "longleftrightarrow": case "LongLeftRightArrow": return '\u27F7';
		case "xlArr": case "Longleftarrow": case "DoubleLongLeftArrow": return '\u27F8';
		case "xrArr": case "Longrightarrow": case "DoubleLongRightArrow": return '\u27F9';
		case "xhArr": case "Longleftrightarrow": case "DoubleLongLeftRightArrow": return '\u27FA';
		case "xmap": case "longmapsto": return '\u27FC';
		case "dzigrarr": return '\u27FF';
		case "nvlArr": return '\u2902';
		case "nvrArr": return '\u2903';
		case "nvHarr": return '\u2904';
		case "Map": return '\u2905';
		case "lbarr": return '\u290C';
		case "rbarr": case "bkarow": return '\u290D';
		case "lBarr": return '\u290E';
		case "rBarr": case "dbkarow": return '\u290F';
		case "RBarr": case "drbkarow": return '\u2910';
		case "DDotrahd": return '\u2911';
		case "UpArrowBar": return '\u2912';
		case "DownArrowBar": return '\u2913';
		case "Rarrtl": return '\u2916';
		case "latail": return '\u2919';
		case "ratail": return '\u291A';
		case "lAtail": return '\u291B';
		case "rAtail": return '\u291C';
		case "larrfs": return '\u291D';
		case "rarrfs": return '\u291E';
		case "larrbfs": return '\u291F';
		case "rarrbfs": return '\u2920';
		case "nwarhk": return '\u2923';
		case "nearhk": return '\u2924';
		case "searhk": case "hksearow": return '\u2925';
		case "swarhk": case "hkswarow": return '\u2926';
		case "nwnear": return '\u2927';
		case "nesear": case "toea": return '\u2928';
		case "seswar": case "tosa": return '\u2929';
		case "swnwar": return '\u292A';
		case "rarrc": return '\u2933';
		case "cudarrr": return '\u2935';
		case "ldca": return '\u2936';
		case "rdca": return '\u2937';
		case "cudarrl": return '\u2938';
		case "larrpl": return '\u2939';
		case "curarrm": return '\u293C';
		case "cularrp": return '\u293D';
		case "rarrpl": return '\u2945';
		case "harrcir": return '\u2948';
		case "Uarrocir": return '\u2949';
		case "lurdshar": return '\u294A';
		case "ldrushar": return '\u294B';
		case "LeftRightVector": return '\u294E';
		case "RightUpDownVector": return '\u294F';
		case "DownLeftRightVector": return '\u2950';
		case "LeftUpDownVector": return '\u2951';
		case "LeftVectorBar": return '\u2952';
		case "RightVectorBar": return '\u2953';
		case "RightUpVectorBar": return '\u2954';
		case "RightDownVectorBar": return '\u2955';
		case "DownLeftVectorBar": return '\u2956';
		case "DownRightVectorBar": return '\u2957';
		case "LeftUpVectorBar": return '\u2958';
		case "LeftDownVectorBar": return '\u2959';
		case "LeftTeeVector": return '\u295A';
		case "RightTeeVector": return '\u295B';
		case "RightUpTeeVector": return '\u295C';
		case "RightDownTeeVector": return '\u295D';
		case "DownLeftTeeVector": return '\u295E';
		case "DownRightTeeVector": return '\u295F';
		case "LeftUpTeeVector": return '\u2960';
		case "LeftDownTeeVector": return '\u2961';
		case "lHar": return '\u2962';
		case "uHar": return '\u2963';
		case "rHar": return '\u2964';
		case "dHar": return '\u2965';
		case "luruhar": return '\u2966';
		case "ldrdhar": return '\u2967';
		case "ruluhar": return '\u2968';
		case "rdldhar": return '\u2969';
		case "lharul": return '\u296A';
		case "llhard": return '\u296B';
		case "rharul": return '\u296C';
		case "lrhard": return '\u296D';
		case "udhar": case "UpEquilibrium": return '\u296E';
		case "duhar": case "ReverseUpEquilibrium": return '\u296F';
		case "RoundImplies": return '\u2970';
		case "erarr": return '\u2971';
		case "simrarr": return '\u2972';
		case "larrsim": return '\u2973';
		case "rarrsim": return '\u2974';
		case "rarrap": return '\u2975';
		case "ltlarr": return '\u2976';
		case "gtrarr": return '\u2978';
		case "subrarr": return '\u2979';
		case "suplarr": return '\u297B';
		case "lfisht": return '\u297C';
		case "rfisht": return '\u297D';
		case "ufisht": return '\u297E';
		case "dfisht": return '\u297F';
		case "lopar": return '\u2985';
		case "ropar": return '\u2986';
		case "lbrke": return '\u298B';
		case "rbrke": return '\u298C';
		case "lbrkslu": return '\u298D';
		case "rbrksld": return '\u298E';
		case "lbrksld": return '\u298F';
		case "rbrkslu": return '\u2990';
		case "langd": return '\u2991';
		case "rangd": return '\u2992';
		case "lparlt": return '\u2993';
		case "rpargt": return '\u2994';
		case "gtlPar": return '\u2995';
		case "ltrPar": return '\u2996';
		case "vzigzag": return '\u299A';
		case "vangrt": return '\u299C';
		case "angrtvbd": return '\u299D';
		case "ange": return '\u29A4';
		case "range": return '\u29A5';
		case "dwangle": return '\u29A6';
		case "uwangle": return '\u29A7';
		case "angmsdaa": return '\u29A8';
		case "angmsdab": return '\u29A9';
		case "angmsdac": return '\u29AA';
		case "angmsdad": return '\u29AB';
		case "angmsdae": return '\u29AC';
		case "angmsdaf": return '\u29AD';
		case "angmsdag": return '\u29AE';
		case "angmsdah": return '\u29AF';
		case "bemptyv": return '\u29B0';
		case "demptyv": return '\u29B1';
		case "cemptyv": return '\u29B2';
		case "raemptyv": return '\u29B3';
		case "laemptyv": return '\u29B4';
		case "ohbar": return '\u29B5';
		case "omid": return '\u29B6';
		case "opar": return '\u29B7';
		case "operp": return '\u29B9';
		case "olcross": return '\u29BB';
		case "odsold": return '\u29BC';
		case "olcir": return '\u29BE';
		case "ofcir": return '\u29BF';
		case "olt": return '\u29C0';
		case "ogt": return '\u29C1';
		case "cirscir": return '\u29C2';
		case "cirE": return '\u29C3';
		case "solb": return '\u29C4';
		case "bsolb": return '\u29C5';
		case "boxbox": return '\u29C9';
		case "trisb": return '\u29CD';
		case "rtriltri": return '\u29CE';
		case "LeftTriangleBar": return '\u29CF';
		case "RightTriangleBar": return '\u29D0';
		case "iinfin": return '\u29DC';
		case "infintie": return '\u29DD';
		case "nvinfin": return '\u29DE';
		case "eparsl": return '\u29E3';
		case "smeparsl": return '\u29E4';
		case "eqvparsl": return '\u29E5';
		case "lozf": case "blacklozenge": return '\u29EB';
		case "RuleDelayed": return '\u29F4';
		case "dsol": return '\u29F6';
		case "xodot": case "bigodot": return '\u2A00';
		case "xoplus": case "bigoplus": return '\u2A01';
		case "xotime": case "bigotimes": return '\u2A02';
		case "xuplus": case "biguplus": return '\u2A04';
		case "xsqcup": case "bigsqcup": return '\u2A06';
		case "qint": case "iiiint": return '\u2A0C';
		case "fpartint": return '\u2A0D';
		case "cirfnint": return '\u2A10';
		case "awint": return '\u2A11';
		case "rppolint": return '\u2A12';
		case "scpolint": return '\u2A13';
		case "npolint": return '\u2A14';
		case "pointint": return '\u2A15';
		case "quatint": return '\u2A16';
		case "intlarhk": return '\u2A17';
		case "pluscir": return '\u2A22';
		case "plusacir": return '\u2A23';
		case "simplus": return '\u2A24';
		case "plusdu": return '\u2A25';
		case "plussim": return '\u2A26';
		case "plustwo": return '\u2A27';
		case "mcomma": return '\u2A29';
		case "minusdu": return '\u2A2A';
		case "loplus": return '\u2A2D';
		case "roplus": return '\u2A2E';
		case "Cross": return '\u2A2F';
		case "timesd": return '\u2A30';
		case "timesbar": return '\u2A31';
		case "smashp": return '\u2A33';
		case "lotimes": return '\u2A34';
		case "rotimes": return '\u2A35';
		case "otimesas": return '\u2A36';
		case "Otimes": return '\u2A37';
		case "odiv": return '\u2A38';
		case "triplus": return '\u2A39';
		case "triminus": return '\u2A3A';
		case "tritime": return '\u2A3B';
		case "iprod": case "intprod": return '\u2A3C';
		case "amalg": return '\u2A3F';
		case "capdot": return '\u2A40';
		case "ncup": return '\u2A42';
		case "ncap": return '\u2A43';
		case "capand": return '\u2A44';
		case "cupor": return '\u2A45';
		case "cupcap": return '\u2A46';
		case "capcup": return '\u2A47';
		case "cupbrcap": return '\u2A48';
		case "capbrcup": return '\u2A49';
		case "cupcup": return '\u2A4A';
		case "capcap": return '\u2A4B';
		case "ccups": return '\u2A4C';
		case "ccaps": return '\u2A4D';
		case "ccupssm": return '\u2A50';
		case "And": return '\u2A53';
		case "Or": return '\u2A54';
		case "andand": return '\u2A55';
		case "oror": return '\u2A56';
		case "orslope": return '\u2A57';
		case "andslope": return '\u2A58';
		case "andv": return '\u2A5A';
		case "orv": return '\u2A5B';
		case "andd": return '\u2A5C';
		case "ord": return '\u2A5D';
		case "wedbar": return '\u2A5F';
		case "sdote": return '\u2A66';
		case "simdot": return '\u2A6A';
		case "congdot": return '\u2A6D';
		case "easter": return '\u2A6E';
		case "apacir": return '\u2A6F';
		case "apE": return '\u2A70';
		case "eplus": return '\u2A71';
		case "pluse": return '\u2A72';
		case "Esim": return '\u2A73';
		case "Colone": return '\u2A74';
		case "Equal": return '\u2A75';
		case "eDDot": case "ddotseq": return '\u2A77';
		case "equivDD": return '\u2A78';
		case "ltcir": return '\u2A79';
		case "gtcir": return '\u2A7A';
		case "ltquest": return '\u2A7B';
		case "gtquest": return '\u2A7C';
		case "les": case "LessSlantEqual": case "leqslant": return '\u2A7D';
		case "ges": case "GreaterSlantEqual": case "geqslant": return '\u2A7E';
		case "lesdot": return '\u2A7F';
		case "gesdot": return '\u2A80';
		case "lesdoto": return '\u2A81';
		case "gesdoto": return '\u2A82';
		case "lesdotor": return '\u2A83';
		case "gesdotol": return '\u2A84';
		case "lap": case "lessapprox": return '\u2A85';
		case "gap": case "gtrapprox": return '\u2A86';
		case "lne": case "lneq": return '\u2A87';
		case "gne": case "gneq": return '\u2A88';
		case "lnap": case "lnapprox": return '\u2A89';
		case "gnap": case "gnapprox": return '\u2A8A';
		case "lEg": case "lesseqqgtr": return '\u2A8B';
		case "gEl": case "gtreqqless": return '\u2A8C';
		case "lsime": return '\u2A8D';
		case "gsime": return '\u2A8E';
		case "lsimg": return '\u2A8F';
		case "gsiml": return '\u2A90';
		case "lgE": return '\u2A91';
		case "glE": return '\u2A92';
		case "lesges": return '\u2A93';
		case "gesles": return '\u2A94';
		case "els": case "eqslantless": return '\u2A95';
		case "egs": case "eqslantgtr": return '\u2A96';
		case "elsdot": return '\u2A97';
		case "egsdot": return '\u2A98';
		case "el": return '\u2A99';
		case "eg": return '\u2A9A';
		case "siml": return '\u2A9D';
		case "simg": return '\u2A9E';
		case "simlE": return '\u2A9F';
		case "simgE": return '\u2AA0';
		case "LessLess": return '\u2AA1';
		case "GreaterGreater": return '\u2AA2';
		case "glj": return '\u2AA4';
		case "gla": return '\u2AA5';
		case "ltcc": return '\u2AA6';
		case "gtcc": return '\u2AA7';
		case "lescc": return '\u2AA8';
		case "gescc": return '\u2AA9';
		case "smt": return '\u2AAA';
		case "lat": return '\u2AAB';
		case "smte": return '\u2AAC';
		case "late": return '\u2AAD';
		case "bumpE": return '\u2AAE';
		case "pre": case "preceq": case "PrecedesEqual": return '\u2AAF';
		case "sce": case "succeq": case "SucceedsEqual": return '\u2AB0';
		case "prE": return '\u2AB3';
		case "scE": return '\u2AB4';
		case "prnE": case "precneqq": return '\u2AB5';
		case "scnE": case "succneqq": return '\u2AB6';
		case "prap": case "precapprox": return '\u2AB7';
		case "scap": case "succapprox": return '\u2AB8';
		case "prnap": case "precnapprox": return '\u2AB9';
		case "scnap": case "succnapprox": return '\u2ABA';
		case "Pr": return '\u2ABB';
		case "Sc": return '\u2ABC';
		case "subdot": return '\u2ABD';
		case "supdot": return '\u2ABE';
		case "subplus": return '\u2ABF';
		case "supplus": return '\u2AC0';
		case "submult": return '\u2AC1';
		case "supmult": return '\u2AC2';
		case "subedot": return '\u2AC3';
		case "supedot": return '\u2AC4';
		case "subE": case "subseteqq": return '\u2AC5';
		case "supE": case "supseteqq": return '\u2AC6';
		case "subsim": return '\u2AC7';
		case "supsim": return '\u2AC8';
		case "subnE": case "subsetneqq": return '\u2ACB';
		case "supnE": case "supsetneqq": return '\u2ACC';
		case "csub": return '\u2ACF';
		case "csup": return '\u2AD0';
		case "csube": return '\u2AD1';
		case "csupe": return '\u2AD2';
		case "subsup": return '\u2AD3';
		case "supsub": return '\u2AD4';
		case "subsub": return '\u2AD5';
		case "supsup": return '\u2AD6';
		case "suphsub": return '\u2AD7';
		case "supdsub": return '\u2AD8';
		case "forkv": return '\u2AD9';
		case "topfork": return '\u2ADA';
		case "mlcp": return '\u2ADB';
		case "Dashv": case "DoubleLeftTee": return '\u2AE4';
		case "Vdashl": return '\u2AE6';
		case "Barv": return '\u2AE7';
		case "vBar": return '\u2AE8';
		case "vBarv": return '\u2AE9';
		case "Vbar": return '\u2AEB';
		case "Not": return '\u2AEC';
		case "bNot": return '\u2AED';
		case "rnmid": return '\u2AEE';
		case "cirmid": return '\u2AEF';
		case "midcir": return '\u2AF0';
		case "topcir": return '\u2AF1';
		case "nhpar": return '\u2AF2';
		case "parsim": return '\u2AF3';
		case "parsl": return '\u2AFD';
		case "fflig": return '\uFB00';
		case "filig": return '\uFB01';
		case "fllig": return '\uFB02';
		case "ffilig": return '\uFB03';
		case "ffllig": return '\uFB04';
		case "Ascr": return '\U0001D49C';
		case "Cscr": return '\U0001D49E';
		case "Dscr": return '\U0001D49F';
		case "Gscr": return '\U0001D4A2';
		case "Jscr": return '\U0001D4A5';
		case "Kscr": return '\U0001D4A6';
		case "Nscr": return '\U0001D4A9';
		case "Oscr": return '\U0001D4AA';
		case "Pscr": return '\U0001D4AB';
		case "Qscr": return '\U0001D4AC';
		case "Sscr": return '\U0001D4AE';
		case "Tscr": return '\U0001D4AF';
		case "Uscr": return '\U0001D4B0';
		case "Vscr": return '\U0001D4B1';
		case "Wscr": return '\U0001D4B2';
		case "Xscr": return '\U0001D4B3';
		case "Yscr": return '\U0001D4B4';
		case "Zscr": return '\U0001D4B5';
		case "ascr": return '\U0001D4B6';
		case "bscr": return '\U0001D4B7';
		case "cscr": return '\U0001D4B8';
		case "dscr": return '\U0001D4B9';
		case "fscr": return '\U0001D4BB';
		case "hscr": return '\U0001D4BD';
		case "iscr": return '\U0001D4BE';
		case "jscr": return '\U0001D4BF';
		case "kscr": return '\U0001D4C0';
		case "lscr": return '\U0001D4C1';
		case "mscr": return '\U0001D4C2';
		case "nscr": return '\U0001D4C3';
		case "pscr": return '\U0001D4C5';
		case "qscr": return '\U0001D4C6';
		case "rscr": return '\U0001D4C7';
		case "sscr": return '\U0001D4C8';
		case "tscr": return '\U0001D4C9';
		case "uscr": return '\U0001D4CA';
		case "vscr": return '\U0001D4CB';
		case "wscr": return '\U0001D4CC';
		case "xscr": return '\U0001D4CD';
		case "yscr": return '\U0001D4CE';
		case "zscr": return '\U0001D4CF';
		case "Afr": return '\U0001D504';
		case "Bfr": return '\U0001D505';
		case "Dfr": return '\U0001D507';
		case "Efr": return '\U0001D508';
		case "Ffr": return '\U0001D509';
		case "Gfr": return '\U0001D50A';
		case "Jfr": return '\U0001D50D';
		case "Kfr": return '\U0001D50E';
		case "Lfr": return '\U0001D50F';
		case "Mfr": return '\U0001D510';
		case "Nfr": return '\U0001D511';
		case "Ofr": return '\U0001D512';
		case "Pfr": return '\U0001D513';
		case "Qfr": return '\U0001D514';
		case "Sfr": return '\U0001D516';
		case "Tfr": return '\U0001D517';
		case "Ufr": return '\U0001D518';
		case "Vfr": return '\U0001D519';
		case "Wfr": return '\U0001D51A';
		case "Xfr": return '\U0001D51B';
		case "Yfr": return '\U0001D51C';
		case "afr": return '\U0001D51E';
		case "bfr": return '\U0001D51F';
		case "cfr": return '\U0001D520';
		case "dfr": return '\U0001D521';
		case "efr": return '\U0001D522';
		case "ffr": return '\U0001D523';
		case "gfr": return '\U0001D524';
		case "hfr": return '\U0001D525';
		case "ifr": return '\U0001D526';
		case "jfr": return '\U0001D527';
		case "kfr": return '\U0001D528';
		case "lfr": return '\U0001D529';
		case "mfr": return '\U0001D52A';
		case "nfr": return '\U0001D52B';
		case "ofr": return '\U0001D52C';
		case "pfr": return '\U0001D52D';
		case "qfr": return '\U0001D52E';
		case "rfr": return '\U0001D52F';
		case "sfr": return '\U0001D530';
		case "tfr": return '\U0001D531';
		case "ufr": return '\U0001D532';
		case "vfr": return '\U0001D533';
		case "wfr": return '\U0001D534';
		case "xfr": return '\U0001D535';
		case "yfr": return '\U0001D536';
		case "zfr": return '\U0001D537';
		case "Aopf": return '\U0001D538';
		case "Bopf": return '\U0001D539';
		case "Dopf": return '\U0001D53B';
		case "Eopf": return '\U0001D53C';
		case "Fopf": return '\U0001D53D';
		case "Gopf": return '\U0001D53E';
		case "Iopf": return '\U0001D540';
		case "Jopf": return '\U0001D541';
		case "Kopf": return '\U0001D542';
		case "Lopf": return '\U0001D543';
		case "Mopf": return '\U0001D544';
		case "Oopf": return '\U0001D546';
		case "Sopf": return '\U0001D54A';
		case "Topf": return '\U0001D54B';
		case "Uopf": return '\U0001D54C';
		case "Vopf": return '\U0001D54D';
		case "Wopf": return '\U0001D54E';
		case "Xopf": return '\U0001D54F';
		case "Yopf": return '\U0001D550';
		case "aopf": return '\U0001D552';
		case "bopf": return '\U0001D553';
		case "copf": return '\U0001D554';
		case "dopf": return '\U0001D555';
		case "eopf": return '\U0001D556';
		case "fopf": return '\U0001D557';
		case "gopf": return '\U0001D558';
		case "hopf": return '\U0001D559';
		case "iopf": return '\U0001D55A';
		case "jopf": return '\U0001D55B';
		case "kopf": return '\U0001D55C';
		case "lopf": return '\U0001D55D';
		case "mopf": return '\U0001D55E';
		case "nopf": return '\U0001D55F';
		case "oopf": return '\U0001D560';
		case "popf": return '\U0001D561';
		case "qopf": return '\U0001D562';
		case "ropf": return '\U0001D563';
		case "sopf": return '\U0001D564';
		case "topf": return '\U0001D565';
		case "uopf": return '\U0001D566';
		case "vopf": return '\U0001D567';
		case "wopf": return '\U0001D568';
		case "xopf": return '\U0001D569';
		case "yopf": return '\U0001D56A';
		case "zopf": return '\U0001D56B';

		// and handling numeric entities
		default:
			if(entity[1] == '#') {
				if(entity[2] == 'x' /*|| (!strict && entity[2] == 'X')*/) {
					auto hex = entity[3..$-1];

					auto p = intFromHex(to!string(hex).toLower());
					return cast(dchar) p;
				} else {
					auto decimal = entity[2..$-1];

					// dealing with broken html entities
					while(decimal.length && (decimal[0] < '0' || decimal[0] >   '9'))
						decimal = decimal[1 .. $];

					if(decimal.length == 0)
						return ' '; // this is really broken html
					// done with dealing with broken stuff

					auto p = std.conv.to!int(decimal);
					return cast(dchar) p;
				}
			} else
				return '\ufffd'; // replacement character diamond thing
	}

	assert(0);
}

import std.utf;
import std.stdio;

/// This takes a string of raw HTML and decodes the entities into a nice D utf-8 string.
/// By default, it uses loose mode - it will try to return a useful string from garbage input too.
/// Set the second parameter to true if you'd prefer it to strictly throw exceptions on garbage input.
/// Group: core_functionality
string htmlEntitiesDecode(string data, bool strict = false) {
	// this check makes a *big* difference; about a 50% improvement of parse speed on my test.
	if(data.indexOf("&") == -1) // all html entities begin with &
		return data; // if there are no entities in here, we can return the original slice and save some time

	char[] a; // this seems to do a *better* job than appender!

	char[4] buffer;

	bool tryingEntity = false;
	dchar[16] entityBeingTried;
	int entityBeingTriedLength = 0;
	int entityAttemptIndex = 0;

	foreach(dchar ch; data) {
		if(tryingEntity) {
			entityAttemptIndex++;
			entityBeingTried[entityBeingTriedLength++] = ch;

			// I saw some crappy html in the wild that looked like &0&#1111; this tries to handle that.
			if(ch == '&') {
				if(strict)
					throw new Exception("unterminated entity; & inside another at " ~ to!string(entityBeingTried[0 .. entityBeingTriedLength]));

				// if not strict, let's try to parse both.

				if(entityBeingTried[0 .. entityBeingTriedLength] == "&&")
					a ~= "&"; // double amp means keep the first one, still try to parse the next one
				else
					a ~= buffer[0.. std.utf.encode(buffer, parseEntity(entityBeingTried[0 .. entityBeingTriedLength]))];

				// tryingEntity is still true
				entityBeingTriedLength = 1;
				entityAttemptIndex = 0; // restarting o this
			} else
			if(ch == ';') {
				tryingEntity = false;
				a ~= buffer[0.. std.utf.encode(buffer, parseEntity(entityBeingTried[0 .. entityBeingTriedLength]))];
			} else if(ch == ' ') {
				// e.g. you &amp i
				if(strict)
					throw new Exception("unterminated entity at " ~ to!string(entityBeingTried[0 .. entityBeingTriedLength]));
				else {
					tryingEntity = false;
					a ~= to!(char[])(entityBeingTried[0 .. entityBeingTriedLength]);
				}
			} else {
				if(entityAttemptIndex >= 9) {
					if(strict)
						throw new Exception("unterminated entity at " ~ to!string(entityBeingTried[0 .. entityBeingTriedLength]));
					else {
						tryingEntity = false;
						a ~= to!(char[])(entityBeingTried[0 .. entityBeingTriedLength]);
					}
				}
			}
		} else {
			if(ch == '&') {
				tryingEntity = true;
				entityBeingTriedLength = 0;
				entityBeingTried[entityBeingTriedLength++] = ch;
				entityAttemptIndex = 0;
			} else {
				a ~= buffer[0 .. std.utf.encode(buffer, ch)];
			}
		}
	}

	if(tryingEntity) {
		if(strict)
			throw new Exception("unterminated entity at " ~ to!string(entityBeingTried[0 .. entityBeingTriedLength]));

		// otherwise, let's try to recover, at least so we don't drop any data
		a ~= to!string(entityBeingTried[0 .. entityBeingTriedLength]);
		// FIXME: what if we have "cool &amp"? should we try to parse it?
	}

	return cast(string) a; // assumeUnique is actually kinda slow, lol
}

/// Group: implementations
abstract class SpecialElement : Element {
	this(Document _parentDocument) {
		super(_parentDocument);
	}

	///.
	override Element appendChild(Element e) {
		assert(0, "Cannot append to a special node");
	}

	///.
	@property override int nodeType() const {
		return 100;
	}
}

///.
/// Group: implementations
class RawSource : SpecialElement {
	///.
	this(Document _parentDocument, string s) {
		super(_parentDocument);
		source = s;
		tagName = "#raw";
	}

	///.
	override string nodeValue() const {
		return this.toString();
	}

	///.
	override string writeToAppender(Appender!string where = appender!string()) const {
		where.put(source);
		return source;
	}

	override string toPrettyString(bool, int, string) const {
		return source;
	}


	override RawSource cloneNode(bool deep) {
		return new RawSource(parentDocument, source);
	}

	///.
	string source;
}

/// Group: implementations
abstract class ServerSideCode : SpecialElement {
	this(Document _parentDocument, string type) {
		super(_parentDocument);
		tagName = "#" ~ type;
	}

	///.
	override string nodeValue() const {
		return this.source;
	}

	///.
	override string writeToAppender(Appender!string where = appender!string()) const {
		auto start = where.data.length;
		where.put("<");
		where.put(source);
		where.put(">");
		return where.data[start .. $];
	}

	override string toPrettyString(bool, int, string) const {
		return "<" ~ source ~ ">";
	}

	///.
	string source;
}

///.
/// Group: implementations
class PhpCode : ServerSideCode {
	///.
	this(Document _parentDocument, string s) {
		super(_parentDocument, "php");
		source = s;
	}

	override PhpCode cloneNode(bool deep) {
		return new PhpCode(parentDocument, source);
	}
}

///.
/// Group: implementations
class AspCode : ServerSideCode {
	///.
	this(Document _parentDocument, string s) {
		super(_parentDocument, "asp");
		source = s;
	}

	override AspCode cloneNode(bool deep) {
		return new AspCode(parentDocument, source);
	}
}

///.
/// Group: implementations
class BangInstruction : SpecialElement {
	///.
	this(Document _parentDocument, string s) {
		super(_parentDocument);
		source = s;
		tagName = "#bpi";
	}

	///.
	override string nodeValue() const {
		return this.source;
	}

	override BangInstruction cloneNode(bool deep) {
		return new BangInstruction(parentDocument, source);
	}

	///.
	override string writeToAppender(Appender!string where = appender!string()) const {
		auto start = where.data.length;
		where.put("<!");
		where.put(source);
		where.put(">");
		return where.data[start .. $];
	}

	override string toPrettyString(bool, int, string) const {
		string s;
		s ~= "<!";
		s ~= source;
		s ~= ">";
		return s;
	}

	///.
	string source;
}

///.
/// Group: implementations
class QuestionInstruction : SpecialElement {
	///.
	this(Document _parentDocument, string s) {
		super(_parentDocument);
		source = s;
		tagName = "#qpi";
	}

	override QuestionInstruction cloneNode(bool deep) {
		return new QuestionInstruction(parentDocument, source);
	}

	///.
	override string nodeValue() const {
		return this.source;
	}

	///.
	override string writeToAppender(Appender!string where = appender!string()) const {
		auto start = where.data.length;
		where.put("<");
		where.put(source);
		where.put(">");
		return where.data[start .. $];
	}

	override string toPrettyString(bool, int, string) const {
		string s;
		s ~= "<";
		s ~= source;
		s ~= ">";
		return s;
	}


	///.
	string source;
}

///.
/// Group: implementations
class HtmlComment : SpecialElement {
	///.
	this(Document _parentDocument, string s) {
		super(_parentDocument);
		source = s;
		tagName = "#comment";
	}

	override HtmlComment cloneNode(bool deep) {
		return new HtmlComment(parentDocument, source);
	}

	///.
	override string nodeValue() const {
		return this.source;
	}

	///.
	override string writeToAppender(Appender!string where = appender!string()) const {
		auto start = where.data.length;
		where.put("<!--");
		where.put(source);
		where.put("-->");
		return where.data[start .. $];
	}

	override string toPrettyString(bool, int, string) const {
		string s;
		s ~= "<!--";
		s ~= source;
		s ~= "-->";
		return s;
	}


	///.
	string source;
}




///.
/// Group: implementations
class TextNode : Element {
  public:
	///.
	this(Document _parentDocument, string e) {
		super(_parentDocument);
		contents = e;
		tagName = "#text";
	}

	///
	this(string e) {
		this(null, e);
	}

	string opDispatch(string name)(string v = null) if(0) { return null; } // text nodes don't have attributes

	///.
	static TextNode fromUndecodedString(Document _parentDocument, string html) {
		auto e = new TextNode(_parentDocument, "");
		e.contents = htmlEntitiesDecode(html, _parentDocument is null ? false : !_parentDocument.loose);
		return e;
	}

	///.
	override @property TextNode cloneNode(bool deep) {
		auto n = new TextNode(parentDocument, contents);
		return n;
	}

	///.
	override string nodeValue() const {
		return this.contents; //toString();
	}

	///.
	@property override int nodeType() const {
		return NodeType.Text;
	}

	///.
	override string writeToAppender(Appender!string where = appender!string()) const {
		string s;
		if(contents.length)
			s = htmlEntitiesEncode(contents, where);
		else
			s = "";

		assert(s !is null);
		return s;
	}

	override string toPrettyString(bool insertComments = false, int indentationLevel = 0, string indentWith = "\t") const {
		string s;

		string contents = this.contents;
		// we will first collapse the whitespace per html
		// sort of. note this can break stuff yo!!!!
		if(this.parentNode is null || this.parentNode.tagName != "pre") {
			string n = "";
			bool lastWasWhitespace = indentationLevel > 0;
			foreach(char c; contents) {
				if(c.isSimpleWhite) {
					if(!lastWasWhitespace)
						n ~= ' ';
					lastWasWhitespace = true;
				} else {
					n ~= c;
					lastWasWhitespace = false;
				}
			}

			contents = n;
		}

		if(this.parentNode !is null && this.parentNode.tagName != "p") {
			contents = contents.strip;
		}

		auto e = htmlEntitiesEncode(contents);
		import std.algorithm.iteration : splitter;
		bool first = true;
		foreach(line; splitter(e, "\n")) {
			if(first) {
				s ~= toPrettyStringIndent(insertComments, indentationLevel, indentWith);
				first = false;
			} else {
				s ~= "\n";
				if(insertComments)
					s ~= "<!--";
				foreach(i; 0 .. indentationLevel)
					s ~= "\t";
				if(insertComments)
					s ~= "-->";
			}
			s ~= line.stripRight;
		}
		return s;
	}

	///.
	override Element appendChild(Element e) {
		assert(0, "Cannot append to a text node");
	}

	///.
	string contents;
	// alias contents content; // I just mistype this a lot,
}

/**
	There are subclasses of Element offering improved helper
	functions for the element in HTML.
*/

///.
/// Group: implementations
class Link : Element {

	///.
	this(Document _parentDocument) {
		super(_parentDocument);
		this.tagName = "a";
	}


	///.
	this(string href, string text) {
		super("a");
		setAttribute("href", href);
		innerText = text;
	}
/+
	/// Returns everything in the href EXCEPT the query string
	@property string targetSansQuery() {

	}

	///.
	@property string domainName() {

	}

	///.
	@property string path
+/
	/// This gets a variable from the URL's query string.
	string getValue(string name) {
		auto vars = variablesHash();
		if(name in vars)
			return vars[name];
		return null;
	}

	private string[string] variablesHash() {
		string href = getAttribute("href");
		if(href is null)
			return null;

		auto ques = href.indexOf("?");
		string str = "";
		if(ques != -1) {
			str = href[ques+1..$];

			auto fragment = str.indexOf("#");
			if(fragment != -1)
				str = str[0..fragment];
		}

		string[] variables = str.split("&");

		string[string] hash;

		foreach(var; variables) {
			auto index = var.indexOf("=");
			if(index == -1)
				hash[var] = "";
			else {
				hash[decodeComponent(var[0..index])] = decodeComponent(var[index + 1 .. $]);
			}
		}

		return hash;
	}

	///.
	/*private*/ void updateQueryString(string[string] vars) {
		string href = getAttribute("href");

		auto question = href.indexOf("?");
		if(question != -1)
			href = href[0..question];

		string frag = "";
		auto fragment = href.indexOf("#");
		if(fragment != -1) {
			frag = href[fragment..$];
			href = href[0..fragment];
		}

		string query = "?";
		bool first = true;
		foreach(name, value; vars) {
			if(!first)
				query ~= "&";
			else
				first = false;

			query ~= encodeComponent(name);
			if(value.length)
				query ~= "=" ~ encodeComponent(value);
		}

		if(query != "?")
			href ~= query;

		href ~= frag;

		setAttribute("href", href);
	}

	/// Sets or adds the variable with the given name to the given value
	/// It automatically URI encodes the values and takes care of the ? and &.
	override void setValue(string name, string variable) {
		auto vars = variablesHash();
		vars[name] = variable;

		updateQueryString(vars);
	}

	/// Removes the given variable from the query string
	void removeValue(string name) {
		auto vars = variablesHash();
		vars.remove(name);

		updateQueryString(vars);
	}

	/*
	///.
	override string toString() {

	}

	///.
	override string getAttribute(string name) {
		if(name == "href") {

		} else
			return super.getAttribute(name);
	}
	*/
}

///.
/// Group: implementations
class Form : Element {

	///.
	this(Document _parentDocument) {
		super(_parentDocument);
		tagName = "form";
	}

	override Element addField(string label, string name, string type = "text", FormFieldOptions fieldOptions = FormFieldOptions.none) {
		auto t = this.querySelector("fieldset div");
		if(t is null)
			return super.addField(label, name, type, fieldOptions);
		else
			return t.addField(label, name, type, fieldOptions);
	}

	override Element addField(string label, string name, FormFieldOptions fieldOptions) {
		auto type = "text";
		auto t = this.querySelector("fieldset div");
		if(t is null)
			return super.addField(label, name, type, fieldOptions);
		else
			return t.addField(label, name, type, fieldOptions);
	}

	override Element addField(string label, string name, string[string] options, FormFieldOptions fieldOptions = FormFieldOptions.none) {
		auto t = this.querySelector("fieldset div");
		if(t is null)
			return super.addField(label, name, options, fieldOptions);
		else
			return t.addField(label, name, options, fieldOptions);
	}

	override void setValue(string field, string value) {
		setValue(field, value, true);
	}

	// FIXME: doesn't handle arrays; multiple fields can have the same name

	/// Set's the form field's value. For input boxes, this sets the value attribute. For
	/// textareas, it sets the innerText. For radio boxes and select boxes, it removes
	/// the checked/selected attribute from all, and adds it to the one matching the value.
	/// For checkboxes, if the value is non-null and not empty, it checks the box.

	/// If you set a value that doesn't exist, it throws an exception if makeNew is false.
	/// Otherwise, it makes a new input with type=hidden to keep the value.
	void setValue(string field, string value, bool makeNew) {
		auto eles = getField(field);
		if(eles.length == 0) {
			if(makeNew) {
				addInput(field, value);
				return;
			} else
				throw new Exception("form field does not exist");
		}

		if(eles.length == 1) {
			auto e = eles[0];
			switch(e.tagName) {
				default: assert(0);
				case "textarea":
					e.innerText = value;
				break;
				case "input":
					string type = e.getAttribute("type");
					if(type is null) {
						e.value = value;
						return;
					}
					switch(type) {
						case "checkbox":
						case "radio":
							if(value.length && value != "false")
								e.setAttribute("checked", "checked");
							else
								e.removeAttribute("checked");
						break;
						default:
							e.value = value;
							return;
					}
				break;
				case "select":
					bool found = false;
					foreach(child; e.tree) {
						if(child.tagName != "option")
							continue;
						string val = child.getAttribute("value");
						if(val is null)
							val = child.innerText;
						if(val == value) {
							child.setAttribute("selected", "selected");
							found = true;
						} else
							child.removeAttribute("selected");
					}

					if(!found) {
						e.addChild("option", value)
						.setAttribute("selected", "selected");
					}
				break;
			}
		} else {
			// assume radio boxes
			foreach(e; eles) {
				string val = e.getAttribute("value");
				//if(val is null)
				//	throw new Exception("don't know what to do with radio boxes with null value");
				if(val == value)
					e.setAttribute("checked", "checked");
				else
					e.removeAttribute("checked");
			}
		}
	}

	/// This takes an array of strings and adds hidden <input> elements for each one of them. Unlike setValue,
	/// it makes no attempt to find and modify existing elements in the form to the new values.
	void addValueArray(string key, string[] arrayOfValues) {
		foreach(arr; arrayOfValues)
			addChild("input", key, arr);
	}

	/// Gets the value of the field; what would be given if it submitted right now. (so
	/// it handles select boxes and radio buttons too). For checkboxes, if a value isn't
	/// given, but it is checked, it returns "checked", since null and "" are indistinguishable
	string getValue(string field) {
		auto eles = getField(field);
		if(eles.length == 0)
			return "";
		if(eles.length == 1) {
			auto e = eles[0];
			switch(e.tagName) {
				default: assert(0);
				case "input":
					if(e.type == "checkbox") {
						if(e.checked)
							return e.value.length ? e.value : "checked";
						return "";
					} else
						return e.value;
				case "textarea":
					return e.innerText;
				case "select":
					foreach(child; e.tree) {
						if(child.tagName != "option")
							continue;
						if(child.selected)
							return child.value;
					}
				break;
			}
		} else {
			// assuming radio
			foreach(e; eles) {
				if(e.checked)
					return e.value;
			}
		}

		return "";
	}

	// FIXME: doesn't handle multiple elements with the same name (except radio buttons)
	///.
	string getPostableData() {
		bool[string] namesDone;

		string ret;
		bool outputted = false;

		foreach(e; getElementsBySelector("[name]")) {
			if(e.name in namesDone)
				continue;

			if(outputted)
				ret ~= "&";
			else
				outputted = true;

			ret ~= std.uri.encodeComponent(e.name) ~ "=" ~ std.uri.encodeComponent(getValue(e.name));

			namesDone[e.name] = true;
		}

		return ret;
	}

	/// Gets the actual elements with the given name
	Element[] getField(string name) {
		Element[] ret;
		foreach(e; tree) {
			if(e.name == name)
				ret ~= e;
		}
		return ret;
	}

	/// Grabs the <label> with the given for tag, if there is one.
	Element getLabel(string forId) {
		foreach(e; tree)
			if(e.tagName == "label" && e.getAttribute("for") == forId)
				return e;
		return null;
	}

	/// Adds a new INPUT field to the end of the form with the given attributes.
	Element addInput(string name, string value, string type = "hidden") {
		auto e = new Element(parentDocument, "input", null, true);
		e.name = name;
		e.value = value;
		e.type = type;

		appendChild(e);

		return e;
	}

	/// Removes the given field from the form. It finds the element and knocks it right out.
	void removeField(string name) {
		foreach(e; getField(name))
			e.parentNode.removeChild(e);
	}

	/+
	/// Returns all form members.
	@property Element[] elements() {

	}

	///.
	string opDispatch(string name)(string v = null)
		// filter things that should actually be attributes on the form
		if( name != "method" && name != "action" && name != "enctype"
		 && name != "style"  && name != "name" && name != "id" && name != "class")
	{

	}
	+/
/+
	void submit() {
		// take its elements and submit them through http
	}
+/
}

import std.conv;

///.
/// Group: implementations
class Table : Element {

	///.
	this(Document _parentDocument) {
		super(_parentDocument);
		tagName = "table";
	}

	/// Creates an element with the given type and content.
	Element th(T)(T t) {
		Element e;
		if(parentDocument !is null)
			e = parentDocument.createElement("th");
		else
			e = Element.make("th");
		static if(is(T == Html))
			e.innerHTML = t;
		else
			e.innerText = to!string(t);
		return e;
	}

	/// ditto
	Element td(T)(T t) {
		Element e;
		if(parentDocument !is null)
			e = parentDocument.createElement("td");
		else
			e = Element.make("td");
		static if(is(T == Html))
			e.innerHTML = t;
		else
			e.innerText = to!string(t);
		return e;
	}

	/// .
	Element appendHeaderRow(T...)(T t) {
		return appendRowInternal("th", "thead", t);
	}

	/// .
	Element appendFooterRow(T...)(T t) {
		return appendRowInternal("td", "tfoot", t);
	}

	/// .
	Element appendRow(T...)(T t) {
		return appendRowInternal("td", "tbody", t);
	}

	void addColumnClasses(string[] classes...) {
		auto grid = getGrid();
		foreach(row; grid)
		foreach(i, cl; classes) {
			if(cl.length)
			if(i < row.length)
				row[i].addClass(cl);
		}
	}

	private Element appendRowInternal(T...)(string innerType, string findType, T t) {
		Element row = Element.make("tr");

		foreach(e; t) {
			static if(is(typeof(e) : Element)) {
				if(e.tagName == "td" || e.tagName == "th")
					row.appendChild(e);
				else {
					Element a = Element.make(innerType);

					a.appendChild(e);

					row.appendChild(a);
				}
			} else static if(is(typeof(e) == Html)) {
				Element a = Element.make(innerType);
				a.innerHTML = e.source;
				row.appendChild(a);
			} else static if(is(typeof(e) == Element[])) {
				Element a = Element.make(innerType);
				foreach(ele; e)
					a.appendChild(ele);
				row.appendChild(a);
			} else static if(is(typeof(e) == string[])) {
				foreach(ele; e) {
					Element a = Element.make(innerType);
					a.innerText = to!string(ele);
					row.appendChild(a);
				}
			} else {
				Element a = Element.make(innerType);
				a.innerText = to!string(e);
				row.appendChild(a);
			}
		}

		foreach(e; children) {
			if(e.tagName == findType) {
				e.appendChild(row);
				return row;
			}
		}

		// the type was not found if we are here... let's add it so it is well-formed
		auto lol = this.addChild(findType);
		lol.appendChild(row);

		return row;
	}

	///.
	Element captionElement() {
		Element cap;
		foreach(c; children) {
			if(c.tagName == "caption") {
				cap = c;
				break;
			}
		}

		if(cap is null) {
			cap = Element.make("caption");
			appendChild(cap);
		}

		return cap;
	}

	///.
	@property string caption() {
		return captionElement().innerText;
	}

	///.
	@property void caption(string text) {
		captionElement().innerText = text;
	}

	/// Gets the logical layout of the table as a rectangular grid of
	/// cells. It considers rowspan and colspan. A cell with a large
	/// span is represented in the grid by being referenced several times.
	/// The tablePortition parameter can get just a <thead>, <tbody>, or
	/// <tfoot> portion if you pass one.
	///
	/// Note: the rectangular grid might include null cells.
	///
	/// This is kinda expensive so you should call once when you want the grid,
	/// then do lookups on the returned array.
	TableCell[][] getGrid(Element tablePortition = null)
		in {
			if(tablePortition is null)
				assert(tablePortition is null);
			else {
				assert(tablePortition !is null);
				assert(tablePortition.parentNode is this);
				assert(
					tablePortition.tagName == "tbody"
					||
					tablePortition.tagName == "tfoot"
					||
					tablePortition.tagName == "thead"
				);
			}
		}
	body {
		if(tablePortition is null)
			tablePortition = this;

		TableCell[][] ret;

		// FIXME: will also return rows of sub tables!
		auto rows = tablePortition.getElementsByTagName("tr");
		ret.length = rows.length;

		int maxLength = 0;

		int insertCell(int row, int position, TableCell cell) {
			if(row >= ret.length)
				return position; // not supposed to happen - a rowspan is prolly too big.

			if(position == -1) {
				position++;
				foreach(item; ret[row]) {
					if(item is null)
						break;
					position++;
				}
			}

			if(position < ret[row].length)
				ret[row][position] = cell;
			else
				foreach(i; ret[row].length .. position + 1) {
					if(i == position)
						ret[row] ~= cell;
					else
						ret[row] ~= null;
				}
			return position;
		}

		foreach(i, rowElement; rows) {
			auto row = cast(TableRow) rowElement;
			assert(row !is null);
			assert(i < ret.length);

			int position = 0;
			foreach(cellElement; rowElement.childNodes) {
				auto cell = cast(TableCell) cellElement;
				if(cell is null)
					continue;

				// FIXME: colspan == 0 or rowspan == 0
				// is supposed to mean fill in the rest of
				// the table, not skip it
				foreach(int j; 0 .. cell.colspan) {
					foreach(int k; 0 .. cell.rowspan)
						// if the first row, always append.
						insertCell(k + cast(int) i, k == 0 ? -1 : position, cell);
					position++;
				}
			}

			if(ret[i].length > maxLength)
				maxLength = cast(int) ret[i].length;
		}

		// want to ensure it's rectangular
		foreach(ref r; ret) {
			foreach(i; r.length .. maxLength)
				r ~= null;
		}

		return ret;
	}
}

/// Represents a table row element - a <tr>
/// Group: implementations
class TableRow : Element {
	///.
	this(Document _parentDocument) {
		super(_parentDocument);
		tagName = "tr";
	}

	// FIXME: the standard says there should be a lot more in here,
	// but meh, I never use it and it's a pain to implement.
}

/// Represents anything that can be a table cell - <td> or <th> html.
/// Group: implementations
class TableCell : Element {
	///.
	this(Document _parentDocument, string _tagName) {
		super(_parentDocument, _tagName);
	}

	@property int rowspan() const {
		int ret = 1;
		auto it = getAttribute("rowspan");
		if(it.length)
			ret = to!int(it);
		return ret;
	}

	@property int colspan() const {
		int ret = 1;
		auto it = getAttribute("colspan");
		if(it.length)
			ret = to!int(it);
		return ret;
	}

	@property int rowspan(int i) {
		setAttribute("rowspan", to!string(i));
		return i;
	}

	@property int colspan(int i) {
		setAttribute("colspan", to!string(i));
		return i;
	}

}


///.
/// Group: implementations
class MarkupException : Exception {

	///.
	this(string message, string file = __FILE__, size_t line = __LINE__) {
		super(message, file, line);
	}
}

/// This is used when you are using one of the require variants of navigation, and no matching element can be found in the tree.
/// Group: implementations
class ElementNotFoundException : Exception {

	/// type == kind of element you were looking for and search == a selector describing the search.
	this(string type, string search, Element searchContext, string file = __FILE__, size_t line = __LINE__) {
		this.searchContext = searchContext;
		super("Element of type '"~type~"' matching {"~search~"} not found.", file, line);
	}

	Element searchContext;
}

/// The html struct is used to differentiate between regular text nodes and html in certain functions
///
/// Easiest way to construct it is like this: `auto html = Html("<p>hello</p>");`
/// Group: core_functionality
struct Html {
	/// This string holds the actual html. Use it to retrieve the contents.
	string source;
}

// for the observers
enum DomMutationOperations {
	setAttribute,
	removeAttribute,
	appendChild, // tagname, attributes[], innerHTML
	insertBefore,
	truncateChildren,
	removeChild,
	appendHtml,
	replaceHtml,
	appendText,
	replaceText,
	replaceTextOnly
}

// and for observers too
struct DomMutationEvent {
	DomMutationOperations operation;
	Element target;
	Element related; // what this means differs with the operation
	Element related2;
	string relatedString;
	string relatedString2;
}


private immutable static string[] htmlSelfClosedElements = [
	// html 4
	"img", "hr", "input", "br", "col", "link", "meta",
	// html 5
	"source" ];

private immutable static string[] inlineElements = [
	"span", "strong", "em", "b", "i", "a"
];


static import std.conv;

///.
int intFromHex(string hex) {
	int place = 1;
	int value = 0;
	for(sizediff_t a = hex.length - 1; a >= 0; a--) {
		int v;
		char q = hex[a];
		if( q >= '0' && q <= '9')
			v = q - '0';
		else if (q >= 'a' && q <= 'f')
			v = q - 'a' + 10;
		else throw new Exception("Illegal hex character: " ~ q);

		value += v * place;

		place *= 16;
	}

	return value;
}


// CSS selector handling

// EXTENSIONS
// dd - dt means get the dt directly before that dd (opposite of +)                  NOT IMPLEMENTED
// dd -- dt means rewind siblings until you hit a dt, go as far as you need to       NOT IMPLEMENTED
// dt < dl means get the parent of that dt iff it is a dl (usable for "get a dt that are direct children of dl")
// dt << dl  means go as far up as needed to find a dl (you have an element and want its containers)      NOT IMPLEMENTED
// :first  means to stop at the first hit, don't do more (so p + p == p ~ p:first



// CSS4 draft currently says you can change the subject (the element actually returned) by putting a ! at the end of it.
// That might be useful to implement, though I do have parent selectors too.

		///.
		static immutable string[] selectorTokens = [
			// It is important that the 2 character possibilities go first here for accurate lexing
		    "~=", "*=", "|=", "^=", "$=", "!=", // "::" should be there too for full standard
		    "::", ">>",
		    "<<", // my any-parent extension (reciprocal of whitespace)
		    // " - ", // previous-sibling extension (whitespace required to disambiguate tag-names)
		    ".", ">", "+", "*", ":", "[", "]", "=", "\"", "#", ",", " ", "~", "<", "(", ")"
		]; // other is white space or a name.

		///.
		sizediff_t idToken(string str, sizediff_t position) {
			sizediff_t tid = -1;
			char c = str[position];
			foreach(a, token; selectorTokens)

				if(c == token[0]) {
					if(token.length > 1) {
						if(position + 1 >= str.length   ||   str[position+1] != token[1])
							continue; // not this token
					}
					tid = a;
					break;
				}
			return tid;
		}

	///.
	// look, ma, no phobos!
	// new lexer by ketmar
	string[] lexSelector (string selstr) {

		static sizediff_t idToken (string str, size_t stpos) {
			char c = str[stpos];
			foreach (sizediff_t tidx, immutable token; selectorTokens) {
				if (c == token[0]) {
					if (token.length > 1) {
						assert(token.length == 2, token); // we don't have 3-char tokens yet
						if (str.length-stpos < 2 || str[stpos+1] != token[1]) continue;
					}
					return tidx;
				}
			}
			return -1;
		}

		// skip spaces and comments
		static string removeLeadingBlanks (string str) {
			size_t curpos = 0;
			while (curpos < str.length) {
				immutable char ch = str[curpos];
				// this can overflow on 4GB strings on 32-bit; 'cmon, don't be silly, nobody cares!
				if (ch == '/' && str.length-curpos > 1 && str[curpos+1] == '*') {
					// comment
					curpos += 2;
					while (curpos < str.length) {
						if (str[curpos] == '*' && str.length-curpos > 1 && str[curpos+1] == '/') {
							curpos += 2;
							break;
						}
						++curpos;
					}
				} else if (ch < 32) { // The < instead of <= is INTENTIONAL. See note from adr below.
					++curpos;

					// FROM ADR: This does NOT catch ' '! Spaces have semantic meaning in CSS! While
					// "foo bar" is clear, and can only have one meaning, consider ".foo .bar".
					// That is not the same as ".foo.bar". If the space is stripped, important
					// information is lost, despite the tokens being separatable anyway.
					//
					// The parser really needs to be aware of the presence of a space.
				} else {
					break;
				}
			}
			return str[curpos..$];
		}

		static bool isBlankAt() (string str, size_t pos) {
			// we should consider unicode spaces too, but... unicode sux anyway.
			return
				(pos < str.length && // in string
				 (str[pos] <= 32 || // space
					(str.length-pos > 1 && str[pos] == '/' && str[pos+1] == '*'))); // comment
		}

		string[] tokens;
		// lexx it!
		while ((selstr = removeLeadingBlanks(selstr)).length > 0) {
			if(selstr[0] == '\"' || selstr[0] == '\'') {
				auto end = selstr[0];
				auto pos = 1;
				bool escaping;
				while(pos < selstr.length && !escaping && selstr[pos] != end) {
					if(escaping)
						escaping = false;
					else if(selstr[pos] == '\\')
						escaping = true;
					pos++;
				}

				// FIXME: do better unescaping
				tokens ~= selstr[1 .. pos].replace(`\"`, `"`).replace(`\'`, `'`).replace(`\\`, `\`);
				if(pos+1 >= selstr.length)
					assert(0, selstr);
				selstr = selstr[pos + 1.. $];
				continue;
			}


			// no tokens starts with escape
			immutable tid = idToken(selstr, 0);
			if (tid >= 0) {
				// special token
				tokens ~= selectorTokens[tid]; // it's funnier this way
				selstr = selstr[selectorTokens[tid].length..$];
				continue;
			}
			// from start to space or special token
			size_t escapePos = size_t.max;
			size_t curpos = 0; // i can has chizburger^w escape at the start
			while (curpos < selstr.length) {
				if (selstr[curpos] == '\\') {
					// this is escape, just skip it and next char
					if (escapePos == size_t.max) escapePos = curpos;
					curpos = (selstr.length-curpos >= 2 ? curpos+2 : selstr.length);
				} else {
					if (isBlankAt(selstr, curpos) || idToken(selstr, curpos) >= 0) break;
					++curpos;
				}
			}
			// identifier
			if (escapePos != size_t.max) {
				// i hate it when it happens
				string id = selstr[0..escapePos];
				while (escapePos < curpos) {
					if (curpos-escapePos < 2) break;
					id ~= selstr[escapePos+1]; // escaped char
					escapePos += 2;
					immutable stp = escapePos;
					while (escapePos < curpos && selstr[escapePos] != '\\') ++escapePos;
					if (escapePos > stp) id ~= selstr[stp..escapePos];
				}
				if (id.length > 0) tokens ~= id;
			} else {
				tokens ~= selstr[0..curpos];
			}
			selstr = selstr[curpos..$];
		}
		return tokens;
	}
	version(unittest_domd_lexer) unittest {
		assert(lexSelector(r" test\=me  /*d*/") == [r"test=me"]);
		assert(lexSelector(r"div/**/. id") == ["div", ".", "id"]);
		assert(lexSelector(r" < <") == ["<", "<"]);
		assert(lexSelector(r" <<") == ["<<"]);
		assert(lexSelector(r" <</") == ["<<", "/"]);
		assert(lexSelector(r" <</*") == ["<<"]);
		assert(lexSelector(r" <\</*") == ["<", "<"]);
		assert(lexSelector(r"heh\") == ["heh"]);
		assert(lexSelector(r"alice \") == ["alice"]);
		assert(lexSelector(r"alice,is#best") == ["alice", ",", "is", "#", "best"]);
	}

	///.
	struct SelectorPart {
		string tagNameFilter; ///.
		string[] attributesPresent; /// [attr]
		string[2][] attributesEqual; /// [attr=value]
		string[2][] attributesStartsWith; /// [attr^=value]
		string[2][] attributesEndsWith; /// [attr$=value]
		// split it on space, then match to these
		string[2][] attributesIncludesSeparatedBySpaces; /// [attr~=value]
		// split it on dash, then match to these
		string[2][] attributesIncludesSeparatedByDashes; /// [attr|=value]
		string[2][] attributesInclude; /// [attr*=value]
		string[2][] attributesNotEqual; /// [attr!=value] -- extension by me

		string[] hasSelectors; /// :has(this)
		string[] notSelectors; /// :not(this)

		string[] isSelectors; /// :is(this)
		string[] whereSelectors; /// :where(this)

		ParsedNth[] nthOfType; /// .
		ParsedNth[] nthLastOfType; /// .
		ParsedNth[] nthChild; /// .

		bool firstChild; ///.
		bool lastChild; ///.

		bool firstOfType; /// .
		bool lastOfType; /// .

		bool emptyElement; ///.
		bool whitespaceOnly; ///
		bool oddChild; ///.
		bool evenChild; ///.

		bool scopeElement; /// the css :scope thing; matches just the `this` element. NOT IMPLEMENTED

		bool rootElement; ///.

		int separation = -1; /// -1 == only itself; the null selector, 0 == tree, 1 == childNodes, 2 == childAfter, 3 == youngerSibling, 4 == parentOf

		bool isCleanSlateExceptSeparation() {
			auto cp = this;
			cp.separation = -1;
			return cp is SelectorPart.init;
		}

		///.
		string toString() {
			string ret;
			switch(separation) {
				default: assert(0);
				case -1: break;
				case 0: ret ~= " "; break;
				case 1: ret ~= " > "; break;
				case 2: ret ~= " + "; break;
				case 3: ret ~= " ~ "; break;
				case 4: ret ~= " < "; break;
			}
			ret ~= tagNameFilter;
			foreach(a; attributesPresent) ret ~= "[" ~ a ~ "]";
			foreach(a; attributesEqual) ret ~= "[" ~ a[0] ~ "=\"" ~ a[1] ~ "\"]";
			foreach(a; attributesEndsWith) ret ~= "[" ~ a[0] ~ "$=\"" ~ a[1] ~ "\"]";
			foreach(a; attributesStartsWith) ret ~= "[" ~ a[0] ~ "^=\"" ~ a[1] ~ "\"]";
			foreach(a; attributesNotEqual) ret ~= "[" ~ a[0] ~ "!=\"" ~ a[1] ~ "\"]";
			foreach(a; attributesInclude) ret ~= "[" ~ a[0] ~ "*=\"" ~ a[1] ~ "\"]";
			foreach(a; attributesIncludesSeparatedByDashes) ret ~= "[" ~ a[0] ~ "|=\"" ~ a[1] ~ "\"]";
			foreach(a; attributesIncludesSeparatedBySpaces) ret ~= "[" ~ a[0] ~ "~=\"" ~ a[1] ~ "\"]";

			foreach(a; notSelectors) ret ~= ":not(" ~ a ~ ")";
			foreach(a; hasSelectors) ret ~= ":has(" ~ a ~ ")";

			foreach(a; isSelectors) ret ~= ":is(" ~ a ~ ")";
			foreach(a; whereSelectors) ret ~= ":where(" ~ a ~ ")";

			foreach(a; nthChild) ret ~= ":nth-child(" ~ a.toString ~ ")";
			foreach(a; nthOfType) ret ~= ":nth-of-type(" ~ a.toString ~ ")";
			foreach(a; nthLastOfType) ret ~= ":nth-last-of-type(" ~ a.toString ~ ")";

			if(firstChild) ret ~= ":first-child";
			if(lastChild) ret ~= ":last-child";
			if(firstOfType) ret ~= ":first-of-type";
			if(lastOfType) ret ~= ":last-of-type";
			if(emptyElement) ret ~= ":empty";
			if(whitespaceOnly) ret ~= ":whitespace-only";
			if(oddChild) ret ~= ":odd-child";
			if(evenChild) ret ~= ":even-child";
			if(rootElement) ret ~= ":root";
			if(scopeElement) ret ~= ":scope";

			return ret;
		}

		// USEFUL
		///.
		bool matchElement(Element e) {
			// FIXME: this can be called a lot of times, and really add up in times according to the profiler.
			// Each individual call is reasonably fast already, but it adds up.
			if(e is null) return false;
			if(e.nodeType != 1) return false;

			if(tagNameFilter != "" && tagNameFilter != "*")
				if(e.tagName != tagNameFilter)
					return false;
			if(firstChild) {
				if(e.parentNode is null)
					return false;
				if(e.parentNode.childElements[0] !is e)
					return false;
			}
			if(lastChild) {
				if(e.parentNode is null)
					return false;
				auto ce = e.parentNode.childElements;
				if(ce[$-1] !is e)
					return false;
			}
			if(firstOfType) {
				if(e.parentNode is null)
					return false;
				auto ce = e.parentNode.childElements;
				foreach(c; ce) {
					if(c.tagName == e.tagName) {
						if(c is e)
							return true;
						else
							return false;
					}
				}
			}
			if(lastOfType) {
				if(e.parentNode is null)
					return false;
				auto ce = e.parentNode.childElements;
				foreach_reverse(c; ce) {
					if(c.tagName == e.tagName) {
						if(c is e)
							return true;
						else
							return false;
					}
				}
			}
			/+
			if(scopeElement) {
				if(e !is this_)
					return false;
			}
			+/
			if(emptyElement) {
				if(e.children.length)
					return false;
			}
			if(whitespaceOnly) {
				if(e.innerText.strip.length)
					return false;
			}
			if(rootElement) {
				if(e.parentNode !is null)
					return false;
			}
			if(oddChild || evenChild) {
				if(e.parentNode is null)
					return false;
				foreach(i, child; e.parentNode.childElements) {
					if(child is e) {
						if(oddChild && !(i&1))
							return false;
						if(evenChild && (i&1))
							return false;
						break;
					}
				}
			}

			bool matchWithSeparator(string attr, string value, string separator) {
				foreach(s; attr.split(separator))
					if(s == value)
						return true;
				return false;
			}

			foreach(a; attributesPresent)
				if(a !in e.attributes)
					return false;
			foreach(a; attributesEqual)
				if(a[0] !in e.attributes || e.attributes[a[0]] != a[1])
					return false;
			foreach(a; attributesNotEqual)
				// FIXME: maybe it should say null counts... this just bit me.
				// I did [attr][attr!=value] to work around.
				//
				// if it's null, it's not equal, right?
				//if(a[0] !in e.attributes || e.attributes[a[0]] == a[1])
				if(e.getAttribute(a[0]) == a[1])
					return false;
			foreach(a; attributesInclude)
				if(a[0] !in e.attributes || (e.attributes[a[0]].indexOf(a[1]) == -1))
					return false;
			foreach(a; attributesStartsWith)
				if(a[0] !in e.attributes || !e.attributes[a[0]].startsWith(a[1]))
					return false;
			foreach(a; attributesEndsWith)
				if(a[0] !in e.attributes || !e.attributes[a[0]].endsWith(a[1]))
					return false;
			foreach(a; attributesIncludesSeparatedBySpaces)
				if(a[0] !in e.attributes || !matchWithSeparator(e.attributes[a[0]], a[1], " "))
					return false;
			foreach(a; attributesIncludesSeparatedByDashes)
				if(a[0] !in e.attributes || !matchWithSeparator(e.attributes[a[0]], a[1], "-"))
					return false;
			foreach(a; hasSelectors) {
				if(e.querySelector(a) is null)
					return false;
			}
			foreach(a; notSelectors) {
				auto sel = Selector(a);
				if(sel.matchesElement(e))
					return false;
			}
			foreach(a; isSelectors) {
				auto sel = Selector(a);
				if(!sel.matchesElement(e))
					return false;
			}
			foreach(a; whereSelectors) {
				auto sel = Selector(a);
				if(!sel.matchesElement(e))
					return false;
			}

			foreach(a; nthChild) {
				if(e.parentNode is null)
					return false;

				auto among = e.parentNode.childElements;

				if(!a.solvesFor(among, e))
					return false;
			}
			foreach(a; nthOfType) {
				if(e.parentNode is null)
					return false;

				auto among = e.parentNode.childElements(e.tagName);

				if(!a.solvesFor(among, e))
					return false;
			}
			foreach(a; nthLastOfType) {
				if(e.parentNode is null)
					return false;

				auto among = retro(e.parentNode.childElements(e.tagName));

				if(!a.solvesFor(among, e))
					return false;
			}

			return true;
		}
	}

	struct ParsedNth {
		int multiplier;
		int adder;

		string of;

		this(string text) {
			auto original = text;
			consumeWhitespace(text);
			if(text.startsWith("odd")) {
				multiplier = 2;
				adder = 1;

				text = text[3 .. $];
			} else if(text.startsWith("even")) {
				multiplier = 2;
				adder = 1;

				text = text[4 .. $];
			} else {
				int n = (text.length && text[0] == 'n') ? 1 : parseNumber(text);
				consumeWhitespace(text);
				if(text.length && text[0] == 'n') {
					multiplier = n;
					text = text[1 .. $];
					consumeWhitespace(text);
					if(text.length) {
						if(text[0] == '+') {
							text = text[1 .. $];
							adder = parseNumber(text);
						} else if(text[0] == '-') {
							text = text[1 .. $];
							adder = -parseNumber(text);
						} else if(text[0] == 'o') {
							// continue, this is handled below
						} else
							throw new Exception("invalid css string at " ~ text ~ " in " ~ original);
					}
				} else {
					adder = n;
				}
			}

			consumeWhitespace(text);
			if(text.startsWith("of")) {
				text = text[2 .. $];
				consumeWhitespace(text);
				of = text[0 .. $];
			}
		}

		string toString() {
			return format("%dn%s%d%s%s", multiplier, adder >= 0 ? "+" : "", adder, of.length ? " of " : "", of);
		}

		bool solvesFor(R)(R elements, Element e) {
			int idx = 1;
			bool found = false;
			foreach(ele; elements) {
				if(of.length) {
					auto sel = Selector(of);
					if(!sel.matchesElement(ele))
						continue;
				}
				if(ele is e) {
					found = true;
					break;
				}
				idx++;
			}
			if(!found) return false;

			// multiplier* n + adder = idx
			// if there is a solution for integral n, it matches

			idx -= adder;
			if(multiplier) {
				if(idx % multiplier == 0)
					return true;
			} else {
				return idx == 0;
			}
			return false;
		}

		private void consumeWhitespace(ref string text) {
			while(text.length && text[0] == ' ')
				text = text[1 .. $];
		}

		private int parseNumber(ref string text) {
			consumeWhitespace(text);
			if(text.length == 0) return 0;
			bool negative = text[0] == '-';
			if(text[0] == '+')
				text = text[1 .. $];
			if(negative) text = text[1 .. $];
			int i = 0;
			while(i < text.length && (text[i] >= '0' && text[i] <= '9'))
				i++;
			if(i == 0)
				return 0;
			int cool = to!int(text[0 .. i]);
			text = text[i .. $];
			return negative ? -cool : cool;
		}
	}

	// USEFUL
	///.
	Element[] getElementsBySelectorParts(Element start, SelectorPart[] parts) {
		Element[] ret;
		if(!parts.length) {
			return [start]; // the null selector only matches the start point; it
				// is what terminates the recursion
		}

		auto part = parts[0];
		//writeln("checking ", part, " against ", start, " with ", part.separation);
		switch(part.separation) {
			default: assert(0);
			case -1:
			case 0: // tree
				foreach(e; start.tree) {
					if(part.separation == 0 && start is e)
						continue; // space doesn't match itself!
					if(part.matchElement(e)) {
						ret ~= getElementsBySelectorParts(e, parts[1..$]);
					}
				}
			break;
			case 1: // children
				foreach(e; start.childNodes) {
					if(part.matchElement(e)) {
						ret ~= getElementsBySelectorParts(e, parts[1..$]);
					}
				}
			break;
			case 2: // next-sibling
				auto e = start.nextSibling("*");
				if(part.matchElement(e))
					ret ~= getElementsBySelectorParts(e, parts[1..$]);
			break;
			case 3: // younger sibling
				auto tmp = start.parentNode;
				if(tmp !is null) {
					sizediff_t pos = -1;
					auto children = tmp.childElements;
					foreach(i, child; children) {
						if(child is start) {
							pos = i;
							break;
						}
					}
					assert(pos != -1);
					foreach(e; children[pos+1..$]) {
						if(part.matchElement(e))
							ret ~= getElementsBySelectorParts(e, parts[1..$]);
					}
				}
			break;
			case 4: // immediate parent node, an extension of mine to walk back up the tree
				auto e = start.parentNode;
				if(part.matchElement(e)) {
					ret ~= getElementsBySelectorParts(e, parts[1..$]);
				}
				/*
					Example of usefulness:

					Consider you have an HTML table. If you want to get all rows that have a th, you can do:

					table th < tr

					Get all th descendants of the table, then walk back up the tree to fetch their parent tr nodes
				*/
			break;
			case 5: // any parent note, another extension of mine to go up the tree (backward of the whitespace operator)
				/*
					Like with the < operator, this is best used to find some parent of a particular known element.

					Say you have an anchor inside a
				*/
		}

		return ret;
	}

	/++
		Represents a parsed CSS selector. You never have to use this directly, but you can if you know it is going to be reused a lot to avoid a bit of repeat parsing.

		See_Also:
			$(LIST
				* [Element.querySelector]
				* [Element.querySelectorAll]
				* [Element.matches]
				* [Element.closest]
				* [Document.querySelector]
				* [Document.querySelectorAll]
			)
	+/
	/// Group: core_functionality
	struct Selector {
		SelectorComponent[] components;
		string original;
		/++
			Parses the selector string and constructs the usable structure.
		+/
		this(string cssSelector) {
			components = parseSelectorString(cssSelector);
			original = cssSelector;
		}

		/++
			Returns true if the given element matches this selector,
			considered relative to an arbitrary element.

			You can do a form of lazy [Element.querySelectorAll|querySelectorAll] by using this
			with [std.algorithm.iteration.filter]:

			---
			Selector sel = Selector("foo > bar");
			auto lazySelectorRange = element.tree.filter!(e => sel.matchElement(e))(document.root);
			---
		+/
		bool matchesElement(Element e, Element relativeTo = null) {
			foreach(component; components)
				if(component.matchElement(e, relativeTo))
					return true;

			return false;
		}

		/++
			Reciprocal of [Element.querySelectorAll]
		+/
		Element[] getMatchingElements(Element start) {
			Element[] ret;
			foreach(component; components)
				ret ~= getElementsBySelectorParts(start, component.parts);
			return removeDuplicates(ret);
		}

		/++
			Like [getMatchingElements], but returns a lazy range. Be careful
			about mutating the dom as you iterate through this.
		+/
		auto getMatchingElementsLazy(Element start, Element relativeTo = null) {
			import std.algorithm.iteration;
			return start.tree.filter!(a => this.matchesElement(a, relativeTo));
		}


		/// Returns the string this was built from
		string toString() {
			return original;
		}

		/++
			Returns a string from the parsed result


			(may not match the original, this is mostly for debugging right now but in the future might be useful for pretty-printing)
		+/
		string parsedToString() {
			string ret;

			foreach(idx, component; components) {
				if(idx) ret ~= ", ";
				ret ~= component.toString();
			}

			return ret;
		}
	}

	///.
	struct SelectorComponent {
		///.
		SelectorPart[] parts;

		///.
		string toString() {
			string ret;
			foreach(part; parts)
				ret ~= part.toString();
			return ret;
		}

		// USEFUL
		///.
		Element[] getElements(Element start) {
			return removeDuplicates(getElementsBySelectorParts(start, parts));
		}

		// USEFUL (but not implemented)
		/// If relativeTo == null, it assumes the root of the parent document.
		bool matchElement(Element e, Element relativeTo = null) {
			if(e is null) return false;
			Element where = e;
			int lastSeparation = -1;

			auto lparts = parts;

			if(parts.length && parts[0].separation > 0) {
				// if it starts with a non-trivial separator, inject
				// a "*" matcher to act as a root. for cases like document.querySelector("> body")
				// which implies html

				// there is probably a MUCH better way to do this.
				auto dummy = SelectorPart.init;
				dummy.tagNameFilter = "*";
				dummy.separation = 0;
				lparts = dummy ~ lparts;
			}

			foreach(part; retro(lparts)) {

				 // writeln("matching ", where, " with ", part, " via ", lastSeparation);
				 // writeln(parts);

				if(lastSeparation == -1) {
					if(!part.matchElement(where))
						return false;
				} else if(lastSeparation == 0) { // generic parent
					// need to go up the whole chain
					where = where.parentNode;

					while(where !is null) {
						if(part.matchElement(where))
							break;

						if(where is relativeTo)
							return false;

						where = where.parentNode;
					}

					if(where is null)
						return false;
				} else if(lastSeparation == 1) { // the > operator
					where = where.parentNode;

					if(!part.matchElement(where))
						return false;
				} else if(lastSeparation == 2) { // the + operator
				//writeln("WHERE", where, " ", part);
					where = where.previousSibling("*");

					if(!part.matchElement(where))
						return false;
				} else if(lastSeparation == 3) { // the ~ operator
					where = where.previousSibling("*");
					while(where !is null) {
						if(part.matchElement(where))
							break;

						if(where is relativeTo)
							return false;

						where = where.previousSibling("*");
					}

					if(where is null)
						return false;
				} else if(lastSeparation == 4) { // my bad idea extension < operator, don't use this anymore
					// FIXME
				}

				lastSeparation = part.separation;

				if(where is relativeTo)
					return false; // at end of line, if we aren't done by now, the match fails
			}
			return true; // if we got here, it is a success
		}

		// the string should NOT have commas. Use parseSelectorString for that instead
		///.
		static SelectorComponent fromString(string selector) {
			return parseSelector(lexSelector(selector));
		}
	}

	///.
	SelectorComponent[] parseSelectorString(string selector, bool caseSensitiveTags = true) {
		SelectorComponent[] ret;
		auto tokens = lexSelector(selector); // this will parse commas too
		// and now do comma-separated slices (i haz phobosophobia!)
		int parensCount = 0;
		while (tokens.length > 0) {
			size_t end = 0;
			while (end < tokens.length && (parensCount > 0 || tokens[end] != ",")) {
				if(tokens[end] == "(") parensCount++;
				if(tokens[end] == ")") parensCount--;
				++end;
			}
			if (end > 0) ret ~= parseSelector(tokens[0..end], caseSensitiveTags);
			if (tokens.length-end < 2) break;
			tokens = tokens[end+1..$];
		}
		return ret;
	}

	///.
	SelectorComponent parseSelector(string[] tokens, bool caseSensitiveTags = true) {
		SelectorComponent s;

		SelectorPart current;
		void commit() {
			// might as well skip null items
			if(!current.isCleanSlateExceptSeparation()) {
				s.parts ~= current;
				current = current.init; // start right over
			}
		}
		enum State {
			Starting,
			ReadingClass,
			ReadingId,
			ReadingAttributeSelector,
			ReadingAttributeComparison,
			ExpectingAttributeCloser,
			ReadingPseudoClass,
			ReadingAttributeValue,

			SkippingFunctionalSelector,
		}
		State state = State.Starting;
		string attributeName, attributeValue, attributeComparison;
		int parensCount;
		foreach(idx, token; tokens) {
			string readFunctionalSelector() {
				string s;
				if(tokens[idx + 1] != "(")
					throw new Exception("parse error");
				int pc = 1;
				foreach(t; tokens[idx + 2 .. $]) {
					if(t == "(")
						pc++;
					if(t == ")")
						pc--;
					if(pc == 0)
						break;
					s ~= t;
				}

				return s;
			}

			sizediff_t tid = -1;
			foreach(i, item; selectorTokens)
				if(token == item) {
					tid = i;
					break;
				}
			final switch(state) {
				case State.Starting: // fresh, might be reading an operator or a tagname
					if(tid == -1) {
						if(!caseSensitiveTags)
							token = token.toLower();

						if(current.isCleanSlateExceptSeparation()) {
							current.tagNameFilter = token;
							// default thing, see comment under "*" below
							if(current.separation == -1) current.separation = 0;
						} else {
							// if it was already set, we must see two thingies
							// separated by whitespace...
							commit();
							current.separation = 0; // tree
							current.tagNameFilter = token;
						}
					} else {
						// Selector operators
						switch(token) {
							case "*":
								current.tagNameFilter = "*";
								// the idea here is if we haven't actually set a separation
								// yet (e.g. the > operator), it should assume the generic
								// whitespace (descendant) mode to avoid matching self with -1
								if(current.separation == -1) current.separation = 0;
							break;
							case " ":
								// If some other separation has already been set,
								// this is irrelevant whitespace, so we should skip it.
								// this happens in the case of "foo > bar" for example.
								if(current.isCleanSlateExceptSeparation() && current.separation > 0)
									continue;
								commit();
								current.separation = 0; // tree
							break;
							case ">>":
								commit();
								current.separation = 0; // alternate syntax for tree from html5 css
							break;
							case ">":
								commit();
								current.separation = 1; // child
							break;
							case "+":
								commit();
								current.separation = 2; // sibling directly after
							break;
							case "~":
								commit();
								current.separation = 3; // any sibling after
							break;
							case "<":
								commit();
								current.separation = 4; // immediate parent of
							break;
							case "[":
								state = State.ReadingAttributeSelector;
								if(current.separation == -1) current.separation = 0;
							break;
							case ".":
								state = State.ReadingClass;
								if(current.separation == -1) current.separation = 0;
							break;
							case "#":
								state = State.ReadingId;
								if(current.separation == -1) current.separation = 0;
							break;
							case ":":
							case "::":
								state = State.ReadingPseudoClass;
								if(current.separation == -1) current.separation = 0;
							break;

							default:
								assert(0, token);
						}
					}
				break;
				case State.ReadingClass:
					current.attributesIncludesSeparatedBySpaces ~= ["class", token];
					state = State.Starting;
				break;
				case State.ReadingId:
					current.attributesEqual ~= ["id", token];
					state = State.Starting;
				break;
				case State.ReadingPseudoClass:
					switch(token) {
						case "first-of-type":
							current.firstOfType = true;
						break;
						case "last-of-type":
							current.lastOfType = true;
						break;
						case "only-of-type":
							current.firstOfType = true;
							current.lastOfType = true;
						break;
						case "first-child":
							current.firstChild = true;
						break;
						case "last-child":
							current.lastChild = true;
						break;
						case "only-child":
							current.firstChild = true;
							current.lastChild = true;
						break;
						case "scope":
							current.scopeElement = true;
						break;
						case "empty":
							// one with no children
							current.emptyElement = true;
						break;
						case "whitespace-only":
							current.whitespaceOnly = true;
						break;
						case "link":
							current.attributesPresent ~= "href";
						break;
						case "root":
							current.rootElement = true;
						break;
						case "nth-child":
							current.nthChild ~= ParsedNth(readFunctionalSelector());
							state = State.SkippingFunctionalSelector;
						continue;
						case "nth-of-type":
							current.nthOfType ~= ParsedNth(readFunctionalSelector());
							state = State.SkippingFunctionalSelector;
						continue;
						case "nth-last-of-type":
							current.nthLastOfType ~= ParsedNth(readFunctionalSelector());
							state = State.SkippingFunctionalSelector;
						continue;
						case "is":
							state = State.SkippingFunctionalSelector;
							current.isSelectors ~= readFunctionalSelector();
						continue; // now the rest of the parser skips past the parens we just handled
						case "where":
							state = State.SkippingFunctionalSelector;
							current.whereSelectors ~= readFunctionalSelector();
						continue; // now the rest of the parser skips past the parens we just handled
						case "not":
							state = State.SkippingFunctionalSelector;
							current.notSelectors ~= readFunctionalSelector();
						continue; // now the rest of the parser skips past the parens we just handled
						case "has":
							state = State.SkippingFunctionalSelector;
							current.hasSelectors ~= readFunctionalSelector();
						continue; // now the rest of the parser skips past the parens we just handled
						// back to standards though not quite right lol
						case "disabled":
							current.attributesPresent ~= "disabled";
						break;
						case "checked":
							current.attributesPresent ~= "checked";
						break;

						case "visited", "active", "hover", "target", "focus", "selected":
							current.attributesPresent ~= "nothing";
							// FIXME
						/+
						// extensions not implemented
						//case "text": // takes the text in the element and wraps it in an element, returning it
						+/
							goto case;
						case "before", "after":
							current.attributesPresent ~= "FIXME";

						break;
						// My extensions
						case "odd-child":
							current.oddChild = true;
						break;
						case "even-child":
							current.evenChild = true;
						break;
						default:
							//if(token.indexOf("lang") == -1)
							//assert(0, token);
						break;
					}
					state = State.Starting;
				break;
				case State.SkippingFunctionalSelector:
					if(token == "(") {
						parensCount++;
					} else if(token == ")") {
						parensCount--;
					}

					if(parensCount == 0)
						state = State.Starting;
				break;
				case State.ReadingAttributeSelector:
					attributeName = token;
					attributeComparison = null;
					attributeValue = null;
					state = State.ReadingAttributeComparison;
				break;
				case State.ReadingAttributeComparison:
					// FIXME: these things really should be quotable in the proper lexer...
					if(token != "]") {
						if(token.indexOf("=") == -1) {
							// not a comparison; consider it
							// part of the attribute
							attributeValue ~= token;
						} else {
							attributeComparison = token;
							state = State.ReadingAttributeValue;
						}
						break;
					}
					goto case;
				case State.ExpectingAttributeCloser:
					if(token != "]") {
						// not the closer; consider it part of comparison
						if(attributeComparison == "")
							attributeName ~= token;
						else
							attributeValue ~= token;
						break;
					}

					// Selector operators
					switch(attributeComparison) {
						default: assert(0);
						case "":
							current.attributesPresent ~= attributeName;
						break;
						case "=":
							current.attributesEqual ~= [attributeName, attributeValue];
						break;
						case "|=":
							current.attributesIncludesSeparatedByDashes ~= [attributeName, attributeValue];
						break;
						case "~=":
							current.attributesIncludesSeparatedBySpaces ~= [attributeName, attributeValue];
						break;
						case "$=":
							current.attributesEndsWith ~= [attributeName, attributeValue];
						break;
						case "^=":
							current.attributesStartsWith ~= [attributeName, attributeValue];
						break;
						case "*=":
							current.attributesInclude ~= [attributeName, attributeValue];
						break;
						case "!=":
							current.attributesNotEqual ~= [attributeName, attributeValue];
						break;
					}

					state = State.Starting;
				break;
				case State.ReadingAttributeValue:
					attributeValue = token;
					state = State.ExpectingAttributeCloser;
				break;
			}
		}

		commit();

		return s;
	}

///.
Element[] removeDuplicates(Element[] input) {
	Element[] ret;

	bool[Element] already;
	foreach(e; input) {
		if(e in already) continue;
		already[e] = true;
		ret ~= e;
	}

	return ret;
}

// done with CSS selector handling


// FIXME: use the better parser from html.d
/// This is probably not useful to you unless you're writing a browser or something like that.
/// It represents a *computed* style, like what the browser gives you after applying stylesheets, inline styles, and html attributes.
/// From here, you can start to make a layout engine for the box model and have a css aware browser.
class CssStyle {
	///.
	this(string rule, string content) {
		rule = rule.strip();
		content = content.strip();

		if(content.length == 0)
			return;

		originatingRule = rule;
		originatingSpecificity = getSpecificityOfRule(rule); // FIXME: if there's commas, this won't actually work!

		foreach(part; content.split(";")) {
			part = part.strip();
			if(part.length == 0)
				continue;
			auto idx = part.indexOf(":");
			if(idx == -1)
				continue;
				//throw new Exception("Bad css rule (no colon): " ~ part);

			Property p;

			p.name = part[0 .. idx].strip();
			p.value = part[idx + 1 .. $].replace("! important", "!important").replace("!important", "").strip(); // FIXME don't drop important
			p.givenExplicitly = true;
			p.specificity = originatingSpecificity;

			properties ~= p;
		}

		foreach(property; properties)
			expandShortForm(property, originatingSpecificity);
	}

	///.
	Specificity getSpecificityOfRule(string rule) {
		Specificity s;
		if(rule.length == 0) { // inline
		//	s.important = 2;
		} else {
			// FIXME
		}

		return s;
	}

	string originatingRule; ///.
	Specificity originatingSpecificity; ///.

	///.
	union Specificity {
		uint score; ///.
		// version(little_endian)
		///.
		struct {
			ubyte tags; ///.
			ubyte classes; ///.
			ubyte ids; ///.
			ubyte important; /// 0 = none, 1 = stylesheet author, 2 = inline style, 3 = user important
		}
	}

	///.
	struct Property {
		bool givenExplicitly; /// this is false if for example the user said "padding" and this is "padding-left"
		string name; ///.
		string value; ///.
		Specificity specificity; ///.
		// do we care about the original source rule?
	}

	///.
	Property[] properties;

	///.
	string opDispatch(string nameGiven)(string value = null) if(nameGiven != "popFront") {
		string name = unCamelCase(nameGiven);
		if(value is null)
			return getValue(name);
		else
			return setValue(name, value, 0x02000000 /* inline specificity */);
	}

	/// takes dash style name
	string getValue(string name) {
		foreach(property; properties)
			if(property.name == name)
				return property.value;
		return null;
	}

	/// takes dash style name
	string setValue(string name, string value, Specificity newSpecificity, bool explicit = true) {
		value = value.replace("! important", "!important");
		if(value.indexOf("!important") != -1) {
			newSpecificity.important = 1; // FIXME
			value = value.replace("!important", "").strip();
		}

		foreach(ref property; properties)
			if(property.name == name) {
				if(newSpecificity.score >= property.specificity.score) {
					property.givenExplicitly = explicit;
					expandShortForm(property, newSpecificity);
					return (property.value = value);
				} else {
					if(name == "display")
					{}//writeln("Not setting ", name, " to ", value, " because ", newSpecificity.score, " < ", property.specificity.score);
					return value; // do nothing - the specificity is too low
				}
			}

		// it's not here...

		Property p;
		p.givenExplicitly = true;
		p.name = name;
		p.value = value;
		p.specificity = originatingSpecificity;

		properties ~= p;
		expandShortForm(p, originatingSpecificity);

		return value;
	}

	private void expandQuadShort(string name, string value, Specificity specificity) {
		auto parts = value.split(" ");
		switch(parts.length) {
			case 1:
				setValue(name ~"-left", parts[0], specificity, false);
				setValue(name ~"-right", parts[0], specificity, false);
				setValue(name ~"-top", parts[0], specificity, false);
				setValue(name ~"-bottom", parts[0], specificity, false);
			break;
			case 2:
				setValue(name ~"-left", parts[1], specificity, false);
				setValue(name ~"-right", parts[1], specificity, false);
				setValue(name ~"-top", parts[0], specificity, false);
				setValue(name ~"-bottom", parts[0], specificity, false);
			break;
			case 3:
				setValue(name ~"-top", parts[0], specificity, false);
				setValue(name ~"-right", parts[1], specificity, false);
				setValue(name ~"-bottom", parts[2], specificity, false);
				setValue(name ~"-left", parts[2], specificity, false);

			break;
			case 4:
				setValue(name ~"-top", parts[0], specificity, false);
				setValue(name ~"-right", parts[1], specificity, false);
				setValue(name ~"-bottom", parts[2], specificity, false);
				setValue(name ~"-left", parts[3], specificity, false);
			break;
			default:
				assert(0, value);
		}
	}

	///.
	void expandShortForm(Property p, Specificity specificity) {
		switch(p.name) {
			case "margin":
			case "padding":
				expandQuadShort(p.name, p.value, specificity);
			break;
			case "border":
			case "outline":
				setValue(p.name ~ "-left", p.value, specificity, false);
				setValue(p.name ~ "-right", p.value, specificity, false);
				setValue(p.name ~ "-top", p.value, specificity, false);
				setValue(p.name ~ "-bottom", p.value, specificity, false);
			break;

			case "border-top":
			case "border-bottom":
			case "border-left":
			case "border-right":
			case "outline-top":
			case "outline-bottom":
			case "outline-left":
			case "outline-right":

			default: {}
		}
	}

	///.
	override string toString() {
		string ret;
		if(originatingRule.length)
			ret = originatingRule ~ " {";

		foreach(property; properties) {
			if(!property.givenExplicitly)
				continue; // skip the inferred shit

			if(originatingRule.length)
				ret ~= "\n\t";
			else
				ret ~= " ";

			ret ~= property.name ~ ": " ~ property.value ~ ";";
		}

		if(originatingRule.length)
			ret ~= "\n}\n";

		return ret;
	}
}

string cssUrl(string url) {
	return "url(\"" ~ url ~ "\")";
}

/// This probably isn't useful, unless you're writing a browser or something like that.
/// You might want to look at arsd.html for css macro, nesting, etc., or just use standard css
/// as text.
///
/// The idea, however, is to represent a kind of CSS object model, complete with specificity,
/// that you can apply to your documents to build the complete computedStyle object.
class StyleSheet {
	///.
	CssStyle[] rules;

	///.
	this(string source) {
		// FIXME: handle @ rules and probably could improve lexer
		// add nesting?
		int state;
		string currentRule;
		string currentValue;

		string* currentThing = &currentRule;
		foreach(c; source) {
			handle: switch(state) {
				default: assert(0);
				case 0: // starting - we assume we're reading a rule
					switch(c) {
						case '@':
							state = 4;
						break;
						case '/':
							state = 1;
						break;
						case '{':
							currentThing = &currentValue;
						break;
						case '}':
							if(currentThing is &currentValue) {
								rules ~= new CssStyle(currentRule, currentValue);

								currentRule = "";
								currentValue = "";

								currentThing = &currentRule;
							} else {
								// idk what is going on here.
								// check sveit.com to reproduce
								currentRule = "";
								currentValue = "";
							}
						break;
						default:
							(*currentThing) ~= c;
					}
				break;
				case 1: // expecting *
					if(c == '*')
						state = 2;
					else {
						state = 0;
						(*currentThing) ~= "/" ~ c;
					}
				break;
				case 2: // inside comment
					if(c == '*')
						state = 3;
				break;
				case 3: // expecting / to end comment
					if(c == '/')
						state = 0;
					else
						state = 2; // it's just a comment so no need to append
				break;
				case 4:
					if(c == '{')
						state = 5;
					if(c == ';')
						state = 0; // just skipping import
				break;
				case 5:
					if(c == '}')
						state = 0; // skipping font face probably
			}
		}
	}

	/// Run through the document and apply this stylesheet to it. The computedStyle member will be accurate after this call
	void apply(Document document) {
		foreach(rule; rules) {
			if(rule.originatingRule.length == 0)
				continue; // this shouldn't happen here in a stylesheet
			foreach(element; document.querySelectorAll(rule.originatingRule)) {
				// note: this should be a different object than the inline style
				// since givenExplicitly is likely destroyed here
				auto current = element.computedStyle;

				foreach(item; rule.properties)
					current.setValue(item.name, item.value, item.specificity);
			}
		}
	}
}


/// This is kinda private; just a little utility container for use by the ElementStream class.
final class Stack(T) {
	this() {
		internalLength = 0;
		arr = initialBuffer[];
	}

	///.
	void push(T t) {
		if(internalLength >= arr.length) {
			auto oldarr = arr;
			if(arr.length < 4096)
				arr = new T[arr.length * 2];
			else
				arr = new T[arr.length + 4096];
			arr[0 .. oldarr.length] = oldarr[];
		}

		arr[internalLength] = t;
		internalLength++;
	}

	///.
	T pop() {
		assert(internalLength);
		internalLength--;
		return arr[internalLength];
	}

	///.
	T peek() {
		assert(internalLength);
		return arr[internalLength - 1];
	}

	///.
	@property bool empty() {
		return internalLength ? false : true;
	}

	///.
	private T[] arr;
	private size_t internalLength;
	private T[64] initialBuffer;
	// the static array is allocated with this object, so if we have a small stack (which we prolly do; dom trees usually aren't insanely deep),
	// using this saves us a bunch of trips to the GC. In my last profiling, I got about a 50x improvement in the push()
	// function thanks to this, and push() was actually one of the slowest individual functions in the code!
}

/// This is the lazy range that walks the tree for you. It tries to go in the lexical order of the source: node, then children from first to last, each recursively.
final class ElementStream {

	///.
	@property Element front() {
		return current.element;
	}

	/// Use Element.tree instead.
	this(Element start) {
		current.element = start;
		current.childPosition = -1;
		isEmpty = false;
		stack = new Stack!(Current);
	}

	/*
		Handle it
		handle its children

	*/

	///.
	void popFront() {
	    more:
	    	if(isEmpty) return;

		// FIXME: the profiler says this function is somewhat slow (noticeable because it can be called a lot of times)

		current.childPosition++;
		if(current.childPosition >= current.element.children.length) {
			if(stack.empty())
				isEmpty = true;
			else {
				current = stack.pop();
				goto more;
			}
		} else {
			stack.push(current);
			current.element = current.element.children[current.childPosition];
			current.childPosition = -1;
		}
	}

	/// You should call this when you remove an element from the tree. It then doesn't recurse into that node and adjusts the current position, keeping the range stable.
	void currentKilled() {
		if(stack.empty) // should never happen
			isEmpty = true;
		else {
			current = stack.pop();
			current.childPosition--; // when it is killed, the parent is brought back a lil so when we popFront, this is then right
		}
	}

	///.
	@property bool empty() {
		return isEmpty;
	}

	private:

	struct Current {
		Element element;
		int childPosition;
	}

	Current current;

	Stack!(Current) stack;

	bool isEmpty;
}



// unbelievable.
// Don't use any of these in your own code. Instead, try to use phobos or roll your own, as I might kill these at any time.
sizediff_t indexOfBytes(immutable(ubyte)[] haystack, immutable(ubyte)[] needle) {
	static import std.algorithm;
	auto found = std.algorithm.find(haystack, needle);
	if(found.length == 0)
		return -1;
	return haystack.length - found.length;
}

private T[] insertAfter(T)(T[] arr, int position, T[] what) {
	assert(position < arr.length);
	T[] ret;
	ret.length = arr.length + what.length;
	int a = 0;
	foreach(i; arr[0..position+1])
		ret[a++] = i;

	foreach(i; what)
		ret[a++] = i;

	foreach(i; arr[position+1..$])
		ret[a++] = i;

	return ret;
}

package bool isInArray(T)(T item, T[] arr) {
	foreach(i; arr)
		if(item == i)
			return true;
	return false;
}

private string[string] aadup(in string[string] arr) {
	string[string] ret;
	foreach(k, v; arr)
		ret[k] = v;
	return ret;
}

// dom event support, if you want to use it

/// used for DOM events
alias EventHandler = void delegate(Element handlerAttachedTo, Event event);

/// This is a DOM event, like in javascript. Note that this library never fires events - it is only here for you to use if you want it.
class Event {
	this(string eventName, Element target) {
		this.eventName = eventName;
		this.srcElement = target;
	}

	/// Prevents the default event handler (if there is one) from being called
	void preventDefault() {
		defaultPrevented = true;
	}

	/// Stops the event propagation immediately.
	void stopPropagation() {
		propagationStopped = true;
	}

	bool defaultPrevented;
	bool propagationStopped;
	string eventName;

	Element srcElement;
	alias srcElement target;

	Element relatedTarget;

	int clientX;
	int clientY;

	int button;

	bool isBubbling;

	/// this sends it only to the target. If you want propagation, use dispatch() instead.
	void send() {
		if(srcElement is null)
			return;

		auto e = srcElement;

		if(eventName in e.bubblingEventHandlers)
		foreach(handler; e.bubblingEventHandlers[eventName])
			handler(e, this);

		if(!defaultPrevented)
			if(eventName in e.defaultEventHandlers)
				e.defaultEventHandlers[eventName](e, this);
	}

	/// this dispatches the element using the capture -> target -> bubble process
	void dispatch() {
		if(srcElement is null)
			return;

		// first capture, then bubble

		Element[] chain;
		Element curr = srcElement;
		while(curr) {
			auto l = curr;
			chain ~= l;
			curr = curr.parentNode;

		}

		isBubbling = false;

		foreach(e; chain.retro()) {
			if(eventName in e.capturingEventHandlers)
			foreach(handler; e.capturingEventHandlers[eventName])
				handler(e, this);

			// the default on capture should really be to always do nothing

			//if(!defaultPrevented)
			//	if(eventName in e.defaultEventHandlers)
			//		e.defaultEventHandlers[eventName](e.element, this);

			if(propagationStopped)
				break;
		}

		isBubbling = true;
		if(!propagationStopped)
		foreach(e; chain) {
			if(eventName in e.bubblingEventHandlers)
			foreach(handler; e.bubblingEventHandlers[eventName])
				handler(e, this);

			if(propagationStopped)
				break;
		}

		if(!defaultPrevented)
		foreach(e; chain) {
				if(eventName in e.defaultEventHandlers)
					e.defaultEventHandlers[eventName](e, this);
		}
	}
}

struct FormFieldOptions {
	// usable for any

	/// this is a regex pattern used to validate the field
	string pattern;
	/// must the field be filled in? Even with a regex, it can be submitted blank if this is false.
	bool isRequired;
	/// this is displayed as an example to the user
	string placeholder;

	// usable for numeric ones


	// convenience methods to quickly get some options
	@property static FormFieldOptions none() {
		FormFieldOptions f;
		return f;
	}

	static FormFieldOptions required() {
		FormFieldOptions f;
		f.isRequired = true;
		return f;
	}

	static FormFieldOptions regex(string pattern, bool required = false) {
		FormFieldOptions f;
		f.pattern = pattern;
		f.isRequired = required;
		return f;
	}

	static FormFieldOptions fromElement(Element e) {
		FormFieldOptions f;
		if(e.hasAttribute("required"))
			f.isRequired = true;
		if(e.hasAttribute("pattern"))
			f.pattern = e.pattern;
		if(e.hasAttribute("placeholder"))
			f.placeholder = e.placeholder;
		return f;
	}

	Element applyToElement(Element e) {
		if(this.isRequired)
			e.required = "required";
		if(this.pattern.length)
			e.pattern = this.pattern;
		if(this.placeholder.length)
			e.placeholder = this.placeholder;
		return e;
	}
}

// this needs to look just like a string, but can expand as needed
version(no_dom_stream)
alias string Utf8Stream;
else
class Utf8Stream {
	protected:
		// these two should be overridden in subclasses to actually do the stream magic
		string getMore() {
			if(getMoreHelper !is null)
				return getMoreHelper();
			return null;
		}

		bool hasMore() {
			if(hasMoreHelper !is null)
				return hasMoreHelper();
			return false;
		}
		// the rest should be ok

	public:
		this(string d) {
			this.data = d;
		}

		this(string delegate() getMoreHelper, bool delegate() hasMoreHelper) {
			this.getMoreHelper = getMoreHelper;
			this.hasMoreHelper = hasMoreHelper;

			if(hasMore())
				this.data ~= getMore();

			stdout.flush();
		}

		@property final size_t length() {
			// the parser checks length primarily directly before accessing the next character
			// so this is the place we'll hook to append more if possible and needed.
			if(lastIdx + 1 >= data.length && hasMore()) {
				data ~= getMore();
			}
			return data.length;
		}

		final char opIndex(size_t idx) {
			if(idx > lastIdx)
				lastIdx = idx;
			return data[idx];
		}

		final string opSlice(size_t start, size_t end) {
			if(end > lastIdx)
				lastIdx = end;
			return data[start .. end];
		}

		final size_t opDollar() {
			return length();
		}

		final Utf8Stream opBinary(string op : "~")(string s) {
			this.data ~= s;
			return this;
		}

		final Utf8Stream opOpAssign(string op : "~")(string s) {
			this.data ~= s;
			return this;
		}

		final Utf8Stream opAssign(string rhs) {
			this.data = rhs;
			return this;
		}
	private:
		string data;

		size_t lastIdx;

		bool delegate() hasMoreHelper;
		string delegate() getMoreHelper;


		/+
		// used to maybe clear some old stuff
		// you might have to remove elements parsed with it too since they can hold slices into the
		// old stuff, preventing gc
		void dropFront(int bytes) {
			posAdjustment += bytes;
			data = data[bytes .. $];
		}

		int posAdjustment;
		+/
}

void fillForm(T)(Form form, T obj, string name) { 
	import arsd.database; 
	fillData((k, v) => form.setValue(k, v), obj, name); 
} 


/+
/+
Syntax:

Tag: tagname#id.class
Tree: Tag(Children, comma, separated...)
Children: Tee or Variable
Variable: $varname with optional |funcname following.

If a variable has a tree after it, it breaks the variable down:
	* if array, foreach it does the tree
	* if struct, it breaks down the member variables

stolen from georgy on irc, see: https://github.com/georgy7/stringplate
+/
struct Stringplate {
	/++

	+/
	this(string s) {

	}

	/++

	+/
	Element expand(T...)(T vars) {
		return null;
	}
}
///
unittest {
	auto stringplate = Stringplate("#bar(.foo($foo), .baz($baz))");
	assert(stringplate.expand.innerHTML == `<div id="bar"><div class="foo">$foo</div><div class="baz">$baz</div></div>`);
}
+/

bool allAreInlineHtml(const(Element)[] children) {
	foreach(child; children) {
		if(child.nodeType == NodeType.Text && child.nodeValue.strip.length) {
			// cool
		} else if(child.tagName.isInArray(inlineElements) && allAreInlineHtml(child.children)) {
			// cool
		} else {
			// prolly block
			return false;
		}
	}
	return true;
}

private bool isSimpleWhite(dchar c) {
	return c == ' ' || c == '\r' || c == '\n' || c == '\t';
}

unittest {
	// Test for issue #120
	string s = `<html>
	<body>
		<P>AN
		<P>bubbles</P>
		<P>giggles</P>
	</body>
</html>`;
	auto doc = new Document();
	doc.parseUtf8(s, false, false);
	auto s2 = doc.toString();
	assert(
			s2.indexOf("bubbles") < s2.indexOf("giggles"),
			"paragraph order incorrect:\n" ~ s2);
}

unittest {
	// test for suncarpet email dec 24 2019
	// arbitrary id asduiwh
	auto document = new Document("<html>
        <head>
                <meta charset=\"utf-8\"></meta>
                <title>Element.querySelector Test</title>
        </head>
        <body>
                <div id=\"foo\">
                        <div>Foo</div>
                        <div>Bar</div>
                </div>
        </body>
</html>");

	auto doc = document;

	assert(doc.querySelectorAll("div div").length == 2);
	assert(doc.querySelector("div").querySelectorAll("div").length == 2);
	assert(doc.querySelectorAll("> html").length == 0);
	assert(doc.querySelector("head").querySelectorAll("> title").length == 1);
	assert(doc.querySelector("head").querySelectorAll("> meta[charset]").length == 1);


	assert(doc.root.matches("html"));
	assert(!doc.root.matches("nothtml"));
	assert(doc.querySelector("#foo > div").matches("div"));
	assert(doc.querySelector("body > #foo").matches("#foo"));

	assert(doc.root.querySelectorAll(":root > body").length == 0); // the root has no CHILD root!
	assert(doc.querySelectorAll(":root > body").length == 1); // but the DOCUMENT does
	assert(doc.querySelectorAll(" > body").length == 1); //  should mean the same thing
	assert(doc.root.querySelectorAll(" > body").length == 1); // the root of HTML has this
	assert(doc.root.querySelectorAll(" > html").length == 0); // but not this

	// also confirming the querySelector works via the mdn definition
	auto foo = doc.requireSelector("#foo");
	assert(foo.querySelector("#foo > div") !is null);
	assert(foo.querySelector("body #foo > div") !is null);

	// this is SUPPOSED to work according to the spec but never has in dom.d since it limits the scope.
	// the new css :scope thing is designed to bring this in. and meh idk if i even care.
	//assert(foo.querySelectorAll("#foo > div").length == 2);
}

unittest {
	// based on https://developer.mozilla.org/en-US/docs/Web/API/Element/closest example
	auto document = new Document(`<article>
  <div id="div-01">Here is div-01
    <div id="div-02">Here is div-02
      <div id="div-03">Here is div-03</div>
    </div>
  </div>
</article>`, true, true);

	auto el = document.getElementById("div-03");
	assert(el.closest("#div-02").id == "div-02");
	assert(el.closest("div div").id == "div-03");
	assert(el.closest("article > div").id == "div-01");
	assert(el.closest(":not(div)").tagName == "article");

	assert(el.closest("p") is null);
	assert(el.closest("p, div") is el);
}

unittest {
	// https://developer.mozilla.org/en-US/docs/Web/CSS/:is
	auto document = new Document(`<test>
		<div class="foo"><p>cool</p><span>bar</span></div>
		<main><p>two</p></main>
	</test>`);

	assert(document.querySelectorAll(":is(.foo, main) p").length == 2);
	assert(document.querySelector("div:where(.foo)") !is null);
}

unittest {
immutable string html = q{
<root>
<div class="roundedbox">
 <table>
  <caption class="boxheader">Recent Reviews</caption>
  <tr>
   <th>Game</th>
   <th>User</th>
   <th>Rating</th>
   <th>Created</th>
  </tr>

  <tr>
   <td>June 13, 2020 15:10</td>
   <td><a href="/reviews/8833">[Show]</a></td>
  </tr>

  <tr>
   <td>June 13, 2020 15:02</td>
   <td><a href="/reviews/8832">[Show]</a></td>
  </tr>

  <tr>
   <td>June 13, 2020 14:41</td>
   <td><a href="/reviews/8831">[Show]</a></td>
  </tr>
 </table>
</div>
</root>
};

  auto doc = new Document(cast(string)html);
  // this should select the second table row, but...
  auto rd = doc.root.querySelector(`div.roundedbox > table > caption.boxheader + tr + tr + tr > td > a[href^=/reviews/]`);
  assert(rd !is null);
  assert(rd.href == "/reviews/8832");

  rd = doc.querySelector(`div.roundedbox > table > caption.boxheader + tr + tr + tr > td > a[href^=/reviews/]`);
  assert(rd !is null);
  assert(rd.href == "/reviews/8832");
}

unittest {
	try {
		auto doc = new XmlDocument("<testxmlns:foo=\"/\"></test>");
		assert(0);
	} catch(Exception e) {
		// good; it should throw an exception, not an error.
	}
}

/*
Copyright: Adam D. Ruppe, 2010 - 2021
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions by Nick Sabalausky, Trass3r, and ketmar among others

        Copyright Adam D. Ruppe 2010-2021.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
        http://www.boost.org/LICENSE_1_0.txt)
*/


