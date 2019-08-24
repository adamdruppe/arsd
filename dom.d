// FIXME: add classList
// FIXME: add matchesSelector - standard name is `matches`. also `closest` walks up to find the parent that matches
// FIXME: https://developer.mozilla.org/en-US/docs/Web/API/Element/insertAdjacentHTML
// FIXME: appendChild should not fail if the thing already has a parent; it should just automatically remove it per standard.

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
class Document : FileResource {
	/// Convenience method for web scraping. Requires [arsd.http2] to be
	/// included in the build as well as [arsd.characterencodings].
	static Document fromUrl()(string url) {
		import arsd.http2;
		auto client = new HttpClient();

		auto req = client.navigateTo(Uri(url), HttpVerb.GET);
		auto res = req.waitForCompletion();

		auto document = new Document();
		document.parseGarbage(cast(string) res.content);

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
					if(strict)
						parseError("bad markup - improperly placed <");
					else
						return Ele(0, TextNode.fromUndecodedString(this, "<"), null);
				break;
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

						if(strict)
						enforce(data[pos] == '>', format("got %s when expecting > (possible missing attribute name)\nContext:\n%s", data[pos], data[pos - 100 .. pos + 100]));
						else {
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
		return root.requireSelector!(SomeElementType)(selector, file, line);
	}

	final MaybeNullElement!SomeElementType optionSelector(SomeElementType = Element)(string selector, string file = __FILE__, size_t line = __LINE__)
		if(is(SomeElementType : Element))
	{
		return root.optionSelector!(SomeElementType)(selector, file, line);
	}


	/// ditto
	Element querySelector(string selector) {
		return root.querySelector(selector);
	}

	/// ditto
	Element[] querySelectorAll(string selector) {
		return root.querySelectorAll(selector);
	}

	/// ditto
	Element[] getElementsBySelector(string selector) {
		return root.getElementsBySelector(selector);
	}

	/// ditto
	Element[] getElementsByTagName(string tag) {
		return root.getElementsByTagName(tag);
	}

	/// ditto
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

		auto e = Element.make(name);
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
		string s = prolog;

		if(insertComments) s ~= "<!--";
		s ~= "\n";
		if(insertComments) s ~= "-->";

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
			assert(e.parentNode is this);
			assert(e.parentDocument is this.parentDocument);
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

	/// Convenience function to try to do the right thing for HTML. This is the main
	/// way I create elements.
	static Element make(string tagName, string childInfo = null, string childInfo2 = null) {
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

	/// Convenience constructor when you don't care about the parentDocument. Note this might break things on the document.
	/// Note also that without a parent document, elements are always in strict, case-sensitive mode.
	this(string _tagName, string[string] _attributes = null) {
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
	@property Element previousSibling(string tagName = null) {
		if(this.parentNode is null)
			return null;
		Element ps = null;
		foreach(e; this.parentNode.childNodes) {
			if(e is this)
				break;
			if(tagName == "*" && e.nodeType != NodeType.Text) {
				ps = e;
				break;
			}
			if(tagName is null || e.tagName == tagName)
				ps = e;
		}

		return ps;
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

	/// Note: you can give multiple selectors, separated by commas.
	/// It will return the first match it finds.
	@scriptable
	Element querySelector(string selector) {
		// FIXME: inefficient; it gets all results just to discard most of them
		auto list = getElementsBySelector(selector);
		if(list.length == 0)
			return null;
		return list[0];
	}

	/// a more standards-compliant alias for getElementsBySelector
	Element[] querySelectorAll(string selector) {
		return getElementsBySelector(selector);
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


    	/// Appends the given element to this one. The given element must not have a parent already.
	Element appendChild(Element e)
		in {
			assert(e !is null);
			assert(e.parentNode is null, e.parentNode.toString);
		}
		out (ret) {
			assert((cast(DocumentFragment) this !is null) || (e.parentNode is this), e.toString);// e.parentNode ? e.parentNode.toString : "null");
			assert(e.parentDocument is this.parentDocument);
			assert(e is ret);
		}
	body {
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
class XmlDocument : Document {
	this(string data) {
		contentType = "text/xml; charset=utf-8";
		_prolog = `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n";

		parseStrict(data);
	}
}




import std.string;

/* domconvenience follows { */

/// finds comments that match the given txt. Case insensitive, strips whitespace.
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

	/// Forward method calls to each individual element of the collection
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
interface FileResource {
	/// the content-type of the file. e.g. "text/html; charset=utf-8" or "image/png"
	@property string contentType() const;
	/// the data
	immutable(ubyte)[] getData() const;
}




///.
enum NodeType { Text = 3 }


/// You can use this to do an easy null check or a dynamic cast+null check on any element.
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
string xmlEntitiesEncode(string data) {
	return htmlEntitiesEncode(data);
}

/// This helper function is used for decoding html entities. It has a hard-coded list of entities and characters.
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

		case "Agrave": return '\u00C0';
		case "Aacute": return '\u00C1';
		case "Acirc": return '\u00C2';
		case "Atilde": return '\u00C3';
		case "Auml": return '\u00C4';
		case "Aring": return '\u00C5';
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
		case "oslash": return '\u00F8';
		case "ugrave": return '\u00F9';
		case "uacute": return '\u00FA';
		case "ucirc": return '\u00FB';
		case "uuml": return '\u00FC';
		case "yacute": return '\u00FD';
		case "thorn": return '\u00FE';
		case "yuml": return '\u00FF';
		case "nbsp": return '\u00A0';
		case "iexcl": return '\u00A1';
		case "cent": return '\u00A2';
		case "pound": return '\u00A3';
		case "curren": return '\u00A4';
		case "yen": return '\u00A5';
		case "brvbar": return '\u00A6';
		case "sect": return '\u00A7';
		case "uml": return '\u00A8';
		case "copy": return '\u00A9';
		case "ordf": return '\u00AA';
		case "laquo": return '\u00AB';
		case "not": return '\u00AC';
		case "shy": return '\u00AD';
		case "reg": return '\u00AE';
		case "ldquo": return '\u201c';
		case "rdquo": return '\u201d';
		case "macr": return '\u00AF';
		case "deg": return '\u00B0';
		case "plusmn": return '\u00B1';
		case "sup2": return '\u00B2';
		case "sup3": return '\u00B3';
		case "acute": return '\u00B4';
		case "micro": return '\u00B5';
		case "para": return '\u00B6';
		case "middot": return '\u00B7';
		case "cedil": return '\u00B8';
		case "sup1": return '\u00B9';
		case "ordm": return '\u00BA';
		case "raquo": return '\u00BB';
		case "frac14": return '\u00BC';
		case "frac12": return '\u00BD';
		case "frac34": return '\u00BE';
		case "iquest": return '\u00BF';
		case "times": return '\u00D7';
		case "divide": return '\u00F7';
		case "OElig": return '\u0152';
		case "oelig": return '\u0153';
		case "Scaron": return '\u0160';
		case "scaron": return '\u0161';
		case "Yuml": return '\u0178';
		case "fnof": return '\u0192';
		case "circ": return '\u02C6';
		case "tilde": return '\u02DC';
		case "trade": return '\u2122';
		case "euro": return '\u20AC';

		case "hellip": return '\u2026';
		case "ndash": return '\u2013';
		case "mdash": return '\u2014';
		case "lsquo": return '\u2018';
		case "rsquo": return '\u2019';

		case "Omicron": return '\u039f'; 
		case "omicron": return '\u03bf'; 

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
class MarkupException : Exception {

	///.
	this(string message, string file = __FILE__, size_t line = __LINE__) {
		super(message, file, line);
	}
}

/// This is used when you are using one of the require variants of navigation, and no matching element can be found in the tree.
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


private immutable static string[] selfClosedElements = [
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
		Represents a parsed CSS selector.

		See_Also:
			[Element.querySelector]
			[Element.querySelectorAll]
			[Document.querySelector]
			[Document.querySelectorAll]
	+/
	struct Selector {
		SelectorComponent[] components;
		string original;
		/++
			Parses the selector string and returns the usable structure.
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
			foreach(part; retro(parts)) {

				// writeln("matching ", where, " with ", part, " via ", lastSeparation);

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
		while (tokens.length > 0) {
			size_t end = 0;
			while (end < tokens.length && tokens[end] != ",") ++end;
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
							break;
							case ".":
								state = State.ReadingClass;
							break;
							case "#":
								state = State.ReadingId;
							break;
							case ":":
							case "::":
								state = State.ReadingPseudoClass;
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
						/*
						// defined in the standard, but I don't implement it
						case "not":
						*/
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

/*
Copyright: Adam D. Ruppe, 2010 - 2019
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions by Nick Sabalausky, Trass3r, and ketmar among others

        Copyright Adam D. Ruppe 2010-2019.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
        http://www.boost.org/LICENSE_1_0.txt)
*/


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
