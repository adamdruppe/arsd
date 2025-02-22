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

static import arsd.core;
import arsd.core : encodeUriComponent, decodeUriComponent;

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


/++
	The main document interface, including a html or xml parser.

	There's three main ways to create a Document:

	If you want to parse something and inspect the tags, you can use the [this|constructor]:
	---
		// create and parse some HTML in one call
		auto document = new Document("<html></html>");

		// or some XML
		auto document = new Document("<xml></xml>", true, true); // strict mode enabled

		// or better yet:
		auto document = new XmlDocument("<xml></xml>"); // specialized subclass
	---

	If you want to download something and parse it in one call, the [fromUrl] static function can help:
	---
		auto document = Document.fromUrl("http://dlang.org/");
	---
	(note that this requires my [arsd.characterencodings] and [arsd.http2] libraries)

	And, if you need to inspect things like `<%= foo %>` tags and comments, you can add them to the dom like this, with the [enableAddingSpecialTagsToDom]
	and [parseUtf8] or [parseGarbage] functions:
	---
		auto document = new Document();
		document.enableAddingSpecialTagsToDom();
		document.parseUtf8("<example></example>", true, true); // changes the trues to false to switch from xml to html mode
	---

	You can also modify things like [selfClosedElements] and [rawSourceElements] before calling the `parse` family of functions to do further advanced tasks.

	However you parse it, it will put a few things into special variables.

	[root] contains the root document.
	[prolog] contains the instructions before the root (like `<!DOCTYPE html>`). To keep the original things, you will need to [enableAddingSpecialTagsToDom] first, otherwise the library will return generic strings in there. [piecesBeforeRoot] will have other parsed instructions, if [enableAddingSpecialTagsToDom] is called.
	[piecesAfterRoot] will contain any xml-looking data after the root tag is closed.

	Most often though, you will not need to look at any of that data, since `Document` itself has methods like [querySelector], [appendChild], and more which will forward to the root [Element] for you.
+/
/// Group: core_functionality
class Document : FileResource, DomParent {
	inout(Document) asDocument() inout { return this; }
	inout(Element) asElement() inout { return null; }

	/++
		These three functions, `processTagOpen`, `processTagClose`, and `processNodeWhileParsing`, allow you to process elements as they are parsed and choose to not append them to the dom tree.


		`processTagOpen` is called as soon as it reads the tag name and attributes into the passed `Element` structure, in order
		of appearance in the file. `processTagClose` is called similarly, when that tag has been closed. In between, all descendant
		nodes - including tags as well as text and other nodes - are passed to `processNodeWhileParsing`. Finally, after `processTagClose`,
		the node itself is passed to `processNodeWhileParsing` only after its children.

		So, given:

		```xml
		<thing>
			<child>
				<grandchild></grandchild>
			</child>
		</thing>
		```

		It would call:

		$(NUMBERED_LIST
			* processTagOpen(thing)
			* processNodeWhileParsing(thing, whitespace text) // the newlines, spaces, and tabs between the thing tag and child tag
			* processTagOpen(child)
			* processNodeWhileParsing(child, whitespace text)
			* processTagOpen(grandchild)
			* processTagClose(grandchild)
			* processNodeWhileParsing(child, grandchild)
			* processNodeWhileParsing(child, whitespace text) // whitespace after the grandchild
			* processTagClose(child)
			* processNodeWhileParsing(thing, child)
			* processNodeWhileParsing(thing, whitespace text)
			* processTagClose(thing)
		)

		The Element objects passed to those functions are the same ones you'd see; the tag open and tag close calls receive the same
		object, so you can compare them with the `is` operator if you want.

		The default behavior of each function is that `processTagOpen` and `processTagClose` do nothing.
		`processNodeWhileParsing`'s default behavior is to call `parent.appendChild(child)`, in order to
		build the dom tree. If you do not want the dom tree, you can do override this function to do nothing.

		If you do not choose to append child to parent in `processNodeWhileParsing`, the garbage collector is free to clean up
		the node even as the document is not finished parsing, allowing memory use to stay lower. Memory use will tend to scale
		approximately with the max depth in the element tree rather the entire document size.

		To cancel processing before the end of a document, you'll have to throw an exception and catch it at your call to parse.
		There is no other way to stop early and there are no concrete plans to add one.

		There are several approaches to use this: you might might use `processTagOpen` and `processTagClose` to keep a stack or
		other state variables to process nodes as they come and never add them to the actual tree. You might also build partial
		subtrees to use all the convenient methods in `processTagClose`, but then not add that particular node to the rest of the
		tree to keep memory usage down.

		Examples:

			Suppose you have a large array of items under the root element you'd like to process individually, without
			taking all the items into memory at once. You can do that with code like this:
			---
			import arsd.dom;
			class MyStream : XmlDocument {
				this(string s) { super(s); } // need to forward the constructor we use

				override void processNodeWhileParsing(Element parent, Element child) {
					// don't append anything to the root node, since we don't need them
					// all in the tree - that'd take too much memory -
					// but still build any subtree for each individual item for ease of processing
					if(parent is root)
						return;
					else
						super.processNodeWhileParsing(parent, child);
				}

				int count;
				override void processTagClose(Element element) {
					if(element.tagName == "item") {
						// process the element here with all the regular dom functions on `element`
						count++;
						// can still use dom functions on the subtree we built
						assert(element.requireSelector("name").textContent == "sample");
					}
				}
			}

			void main() {
				// generate an example file with a million items
				string xml = "<list>";
				foreach(i; 0 .. 1_000_000) {
					xml ~= "<item><name>sample</name><type>example</type></item>";
				}
				xml ~= "</list>";

				auto document = new MyStream(xml);
				assert(document.count == 1_000_000);
			}
			---

			This example runs in about 1/10th of the memory and 2/3 of the time on my computer relative to a default [XmlDocument] full tree dom.

			By overriding these three functions to fit the specific document and processing requirements you have, you might realize even bigger
			gains over the normal full document tree while still getting most the benefits of the convenient dom functions.

			Tip: if you use a [Utf8Stream] instead of a string, you might be able to bring the memory use further down. The easiest way to do that
			is something like this when loading from a file:

			---
			import std.stdio;
			auto file = File("filename.xml", "rb");
			auto textStream = new Utf8Stream(() {
				 // get more
				 auto buffer = new char[](32 * 1024);
				 return cast(string) file.rawRead(buffer);
			}, () {
				 // has more
				 return !file.eof;
			});

			auto document = new XmlDocument(textStream);
			---

			You'll need to forward a constructor in your subclasses that takes `Utf8Stream` too if you want to subclass to override the streaming parsing functions.

			Note that if you do save parts of the document strings or objects, it might prevent the GC from freeing that string block anyway, since dom.d will often slice into its buffer while parsing instead of copying strings. It will depend on your specific case to know if this actually saves memory or not for you.

		Bugs:
			Even if you use a [Utf8Stream] to feed data and decline to append to the tree, the entire xml text is likely to
			end up in memory anyway.

		See_Also:
			[Document#examples]'s high level streaming example.

		History:
			`processNodeWhileParsing` was added January 6, 2023.

			`processTagOpen` and `processTagClose` were added February 21, 2025.
	+/
	void processTagOpen(Element what) {
	}

	/// ditto
	void processTagClose(Element what) {
	}

	/// ditto
	void processNodeWhileParsing(Element parent, Element child) {
		parent.appendChild(child);
	}

	/++
		Convenience method for web scraping. Requires [arsd.http2] to be
		included in the build as well as [arsd.characterencodings].

		This will download the file from the given url and create a document
		off it, using a strict constructor or a [parseGarbage], depending on
		the value of `strictMode`.
	+/
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

	/++
		Creates a document with the given source data. If you want HTML behavior, use `caseSensitive` and `struct` set to `false`. For XML mode, set them to `true`.

		Please note that anything after the root element will be found in [piecesAfterRoot]. Comments, processing instructions, and other special tags will be stripped out b default. You can customize this by using the zero-argument constructor and setting callbacks on the [parseSawComment], [parseSawBangInstruction], [parseSawAspCode], [parseSawPhpCode], and [parseSawQuestionInstruction] members, then calling one of the [parseUtf8], [parseGarbage], or [parse] functions. Calling the convenience method, [enableAddingSpecialTagsToDom], will enable all those things at once.

		See_Also:
			[parseGarbage]
			[parseUtf8]
			[parseUrl]
	+/
	this(string data, bool caseSensitive = false, bool strict = false) {
		parseUtf8(data, caseSensitive, strict);
	}

	/**
		Creates an empty document. It has *nothing* in it at all, ready.
	*/
	this() {

	}

	/++
		This is just something I'm toying with. Right now, you use opIndex to put in css selectors.
		It returns a struct that forwards calls to all elements it holds, and returns itself so you
		can chain it.

		Example: document["p"].innerText("hello").addClass("modified");

		Equivalent to: foreach(e; document.getElementsBySelector("p")) { e.innerText("hello"); e.addClas("modified"); }

		Note: always use function calls (not property syntax) and don't use toString in there for best results.

		You can also do things like: document["p"]["b"] though tbh I'm not sure why since the selector string can do all that anyway. Maybe
		you could put in some kind of custom filter function tho.
	+/
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


	/*
	/// Concatenates any consecutive text nodes
	void normalize() {

	}
	*/

	/// This will set delegates for parseSaw* (note: this overwrites anything else you set, and you setting subsequently will overwrite this) that add those things to the dom tree when it sees them.
	/// Call this before calling parse().

	/++
		Adds objects to the dom representing things normally stripped out during the default parse, like comments, `<!instructions>`, `<% code%>`, and `<? code?>` all at once.

		Note this will also preserve the prolog and doctype from the original file, if there was one.

		See_Also:
			[parseSawComment]
			[parseSawAspCode]
			[parseSawPhpCode]
			[parseSawQuestionInstruction]
			[parseSawBangInstruction]
	+/
	void enableAddingSpecialTagsToDom() {
		parseSawComment = (string) => true;
		parseSawAspCode = (string) => true;
		parseSawPhpCode = (string) => true;
		parseSawQuestionInstruction = (string) => true;
		parseSawBangInstruction = (string) => true;
	}

	/// If the parser sees a html comment, it will call this callback
	/// <!-- comment --> will call parseSawComment(" comment ")
	/// Return true if you want the node appended to the document. It will be in a [HtmlComment] object.
	bool delegate(string) parseSawComment;

	/// If the parser sees <% asp code... %>, it will call this callback.
	/// It will be passed "% asp code... %" or "%= asp code .. %"
	/// Return true if you want the node appended to the document. It will be in an [AspCode] object.
	bool delegate(string) parseSawAspCode;

	/// If the parser sees <?php php code... ?>, it will call this callback.
	/// It will be passed "?php php code... ?" or "?= asp code .. ?"
	/// Note: dom.d cannot identify  the other php <? code ?> short format.
	/// Return true if you want the node appended to the document. It will be in a [PhpCode] object.
	bool delegate(string) parseSawPhpCode;

	/// if it sees a <?xxx> that is not php or asp
	/// it calls this function with the contents.
	/// <?SOMETHING foo> calls parseSawQuestionInstruction("?SOMETHING foo")
	/// Unlike the php/asp ones, this ends on the first > it sees, without requiring ?>.
	/// Return true if you want the node appended to the document. It will be in a [QuestionInstruction] object.
	bool delegate(string) parseSawQuestionInstruction;

	/// if it sees a <! that is not CDATA or comment (CDATA is handled automatically and comments call parseSawComment),
	/// it calls this function with the contents.
	/// <!SOMETHING foo> calls parseSawBangInstruction("SOMETHING foo")
	/// Return true if you want the node appended to the document. It will be in a [BangInstruction] object.
	bool delegate(string) parseSawBangInstruction;

	/// Given the kind of garbage you find on the Internet, try to make sense of it.
	/// Equivalent to document.parse(data, false, false, null);
	/// (Case-insensitive, non-strict, determine character encoding from the data.)

	/// NOTE: this makes no attempt at added security, but it will try to recover from anything instead of throwing.
	///
	/// It is a template so it lazily imports characterencodings.
	void parseGarbage()(string data) {
		parse(data, false, false, null);
	}

	/// Parses well-formed UTF-8, case-sensitive, XML or XHTML
	/// Will throw exceptions on things like unclosed tags.
	void parseStrict(string data, bool pureXmlMode = false) {
		parseStream(toUtf8Stream(data), true, true, pureXmlMode);
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

			Changed from `string[]` to `immutable(string)[]` on
			February 4, 2024 (dub v11.5) to plug a hole discovered
			by the OpenD compiler's diagnostics.
	+/
	immutable(string)[] selfClosedElements = htmlSelfClosedElements;

	/++
		List of elements that contain raw CDATA content for this
		document, e.g. `<script>` and `<style>` for HTML. The parser
		will read until the closing string and put everything else
		in a [RawSource] object for future processing, not trying to
		do any further child nodes or attributes, etc.

		History:
			Added February 4, 2024 (dub v11.5)

	+/
	immutable(string)[] rawSourceElements = htmlRawSourceElements;

	/++
		List of elements that are considered inline for pretty printing.
		The default for a Document are hard-coded to something appropriate
		for HTML. For [XmlDocument], it defaults to empty. You can modify
		this after construction but before parsing.

		History:
			Added June 21, 2021 (included in dub release 10.1)

			Changed from `string[]` to `immutable(string)[]` on
			February 4, 2024 (dub v11.5) to plug a hole discovered
			by the OpenD compiler's diagnostics.
	+/
	immutable(string)[] inlineElements = htmlInlineElements;

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
	void parseStream(Utf8Stream data, bool caseSensitive = false, bool strict = false, bool pureXmlMode = false) {
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
		bool nonNestableHackRequired = false;

		int getLineNumber(sizediff_t p) {
			return data.getLineNumber(p);
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

			data.markDataDiscardable(pos);

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
					if(!strict)
						tname = tname.strip;
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
					AttributesHolder attributes;

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
						enforce(data[pos] == '>', format("got %s when expecting > (possible missing attribute name)\nContext:\n%s", data[pos], data[max(0, pos - data.contextToKeep) .. min(data.length, pos + data.contextToKeep)]));
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

						// might temporarily set root to the first element we encounter,
						// then the final root element assignment will be at the end of the parse,
						// when the recursive work is complete.
						if(this.root is null)
							this.root = e;
						this.processTagOpen(e);
						scope(exit)
							this.processTagClose(e);


						// HACK to handle script and style as a raw data section as it is in HTML browsers
						if(!pureXmlMode && tagName.isInArray(rawSourceElements)) {
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

						void considerHtmlNonNestableElementHack(Element n) {
							assert(!strict);
							if(!canNestElementsInHtml(e.tagName, n.tagName)) {
								// html lets you write <p> para 1 <p> para 1
								// but in the dom tree, they should be siblings, not children.
								nonNestableHackRequired = true;
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
									processNodeWhileParsing(e, n.element);
								else
									piecesBeforeRoot ~= n.element;
							} else if(n.type == 0) {
								if(!strict)
									considerHtmlNonNestableElementHack(n.element);
								processNodeWhileParsing(e, n.element);
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
												considerHtmlNonNestableElementHack(n.element);
											processNodeWhileParsing(e, n.element);
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

										/+
											// COMMENTED OUT BLOCK
											// dom.d used to replace improper close tags with their
											// text so they'd be visible in the output. the html
											// spec says to just ignore them, and browsers do indeed
											// seem to jsut ignore them, even checking back on IE6.
											// so i guess i was wrong to do this (tho tbh i find it kinda
											// useful to call out an obvious mistake in the source...
											// but for calling out obvious mistakes, just use strict
											// mode.)

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
										processNodeWhileParsing(e, TextNode.fromUndecodedString(this, "</"~n.payload~">"));

										+/
									}
								} else {
									if(n.element) {
										if(!strict)
											considerHtmlNonNestableElementHack(n.element);
										processNodeWhileParsing(e, n.element);
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
									// the spec allows this too, sigh https://www.w3.org/TR/REC-xml/#NT-Eq
									//if(strict && ateAny)
										//throw new MarkupException("inappropriate whitespace after attribute name");

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
										// the spec actually allows this!
										//if(strict && ateAny)
											//throw new MarkupException("inappropriate whitespace after attribute equals");

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
		if(root !is null)
			root.parent_ = this;

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

		if(nonNestableHackRequired) {
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

				if(!canNestElementsInHtml(ele.parentNode.tagName, ele.tagName)) {
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
	do {
		return root.requireElementById!(SomeElementType)(id, file, line);
	}

	/// ditto
	final SomeElementType requireSelector(SomeElementType = Element)(string selector, string file = __FILE__, size_t line = __LINE__)
		if( is(SomeElementType : Element))
		out(ret) { assert(ret !is null); }
	do {
		auto e = cast(SomeElementType) querySelector(selector);
		if(e is null)
			throw new ElementNotFoundException(SomeElementType.stringof, selector, this.root, file, line);
		return e;
	}

	/// ditto
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
		return s.getMatchingElements(this.root, null);
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

	/++
		This returns the <body> element, if there is one. (It different than Javascript, where it is called 'body', because body used to be a keyword in D.)

		History:
			`body` alias added February 26, 2024
	+/
	Element mainBody() {
		return getFirstElementByTagName("body");
	}

	/// ditto
	alias body = mainBody;

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
	do {
		return cast(Form) createElement("form");
	}

	///.
	Element createElement(string name) {
		if(loose)
			name = name.toLower();

		auto e = Element.make(name, null, null, selfClosedElements);

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

	private string _prolog = "<!DOCTYPE html>\n";
	private bool prologWasSet = false; // set to true if the user changed it

	/++
		Returns or sets the string before the root element. This is, for example,
		`<!DOCTYPE html>\n` or similar.
	+/
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

	/// ditto
	void setProlog(string d) {
		_prolog = d;
		prologWasSet = true;
	}

	/++
		Returns the document as string form. Please note that if there is anything in [piecesAfterRoot],
		they are discarded. If you want to add them to the file, loop over that and append it yourself
		(but remember xml isn't supposed to have anything after the root element).
	+/
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

		s ~= root.toPrettyStringImpl(insertComments, indentationLevel, indentWith);
		foreach(a; piecesAfterRoot)
			s ~= a.toPrettyStringImpl(insertComments, indentationLevel, indentWith);
		return s;
	}

	/// The root element, like `<html>`. Most the methods on Document forward to this object.
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

/++
	Basic parsing of HTML tag soup

	If you simply make a `new Document("some string")` or use [Document.fromUrl] to automatically
	download a page (that's function is shorthand for `new Document(arsd.http2.get(your_given_url).contentText)`),
	the Document parser will assume it is broken HTML. It will try to fix up things like charset messes, missing
	closing tags, flipped tags, inconsistent letter cases, and other forms of commonly found HTML on the web.

	It isn't exactly the same as what a HTML5 web browser does in all cases, but it usually it, and where it
	disagrees, it is still usually good enough (but sometimes a bug).
+/
unittest {
	auto document = new Document(`<html><body><p>hello <P>there`);
	// this will automatically try to normalize the html and fix up broken tags, etc
	// so notice how it added the missing closing tags here and made them all lower case
	assert(document.toString() == "<!DOCTYPE html>\n<html><body><p>hello </p><p>there</p></body></html>", document.toString());
}

/++
	Stricter parsing of HTML

	When you are writing the HTML yourself, you can remove most ambiguity by making it throw exceptions instead
	of trying to automatically fix up things basic parsing tries to do. Using strict mode accomplishes this.

	This will help guarantee that you have well-formed HTML, which means it is going to parse a lot more reliably
	by all users - browsers, dom.d, other libraries, all behave better with well-formed input... people too!

	(note it is not a full *validator*, just a well-formedness checker. Full validation is a lot more work for very
	little benefit in my experience, so I stopped here.)
+/
unittest {
	try {
		auto document = new Document(`<html><body><p>hello <P>there`, true, true); // turns on strict and case sensitive mode to ctor
		assert(0); // never reached, the constructor will throw because strict mode is turned on
	} catch(Exception e) {

	}

	// you can also create the object first, then use the [parseStrict] method
	auto document = new Document;
	document.parseStrict(`<foo></foo>`); // this is invalid html - no such foo tag - but it is well-formed, since it is opened and closed properly, so it passes

}

/++
	Custom HTML extensions

	dom.d is a custom HTML parser, which means you can add custom HTML extensions to it too. It normally reads
	and discards things like ASP style `<% ... %>` code as well as XML processing instruction / PHP style embeds `<? ... ?>`
	but you can keep this data if you call a function to opt into it in before parsing.

	Additionally, you can add special tags to be read like `<script>` to preserve its insides for future processing
	via the `.innerRawSource` member.
+/
unittest {
	auto document = new Document; // construct an empty thing first
	document.enableAddingSpecialTagsToDom(); // add the special tags like <% ... %> etc
	document.rawSourceElements ~= "embedded-plaintext"; // tell it we want a custom

	document.parseStrict(`<html>
		<% some asp code %>
		<script>embedded && javascript</script>
		<embedded-plaintext>my <custom> plaintext & stuff</embedded-plaintext>
	</html>`);

	// please note that if we did `document.toString()` right now, the original source - almost your same
	// string you passed to parseStrict - would be spit back out. Meaning the embedded-plaintext still has its
	// special text inside it. Another parser won't understand how to use this! So if you want to pass this
	// document somewhere else, you need to do some transformations.
	//
	// This differs from cases like CDATA sections, which dom.d will automatically convert into plain html entities
	// on the output that can be read by anyone.

	assert(document.root.tagName == "html"); // the root element is normal

	int foundCount;
	// now let's loop through the whole tree
	foreach(element; document.root.tree) {
		// the asp thing will be in
		if(auto asp = cast(AspCode) element) {
			// you use the `asp.source` member to get the code for these
			assert(asp.source == "% some asp code %");
			foundCount++;
		} else if(element.tagName == "script") {
			// and for raw source elements - script, style, or the ones you add,
			// you use the innerHTML method to get the code inside
			assert(element.innerHTML == "embedded && javascript");
			foundCount++;
		} else if(element.tagName == "embedded-plaintext") {
			// and innerHTML again
			assert(element.innerHTML == "my <custom> plaintext & stuff");
			foundCount++;
		}

	}

	assert(foundCount == 3);

	// writeln(document.toString());
}

// FIXME: <textarea> contents are treated kinda special in html5 as well...

/++
	Demoing CDATA, entities, and non-ascii characters.

	The previous example mentioned CDATA, let's show you what that does too. These are all read in as plain strings accessible in the DOM - there is no CDATA, no entities once you get inside the object model - but when you convert back into a string, it will normalize them in a particular way.

	This is not exactly standards compliant completely in and out thanks to it doing some transformations... but I find it more useful - it reads the data in consistently and writes it out consistently, both in ways that work well for interop. Take a look:
+/
unittest {
	auto document = new Document(`<html>
		<p>¤ is a non-ascii character. It will be converted to a numbered entity in string output.</p>
		<p>&curren; is the same thing, but as a named entity. It also will be changed to a numbered entity in string output.</p>
		<p><![CDATA[xml cdata segments, which can contain <tag> looking things, are converted to encode the embedded special-to-xml characters to entities too.]]></p>
	</html>`, true, true); // strict mode turned on

	// Inside the object model, things are simplified to D strings.
	auto paragraphs = document.querySelectorAll("p");
	// no surprise on the first paragraph, we wrote it with the character, and it is still there in the D string
	assert(paragraphs[0].textContent == "¤ is a non-ascii character. It will be converted to a numbered entity in string output.");
	// but note on the second paragraph, the entity has been converted to the appropriate *character* in the object
	assert(paragraphs[1].textContent == "¤ is the same thing, but as a named entity. It also will be changed to a numbered entity in string output.");
	// and the CDATA bit is completely gone from the DOM; it just read it in as a text node. The txt content shows the text as a plain string:
	assert(paragraphs[2].textContent == "xml cdata segments, which can contain <tag> looking things, are converted to encode the embedded special-to-xml characters to entities too.");
	// and the dom node beneath it is just a single text node; no trace of the original CDATA detail is left after parsing.
	assert(paragraphs[2].childNodes.length == 1 && paragraphs[2].childNodes[0].nodeType == NodeType.Text);

	// And now, in the output string, we can see they are normalized thusly:
	assert(document.toString() == "<!DOCTYPE html>\n<html>
		<p>&#164; is a non-ascii character. It will be converted to a numbered entity in string output.</p>
		<p>&#164; is the same thing, but as a named entity. It also will be changed to a numbered entity in string output.</p>
		<p>xml cdata segments, which can contain &lt;tag&gt; looking things, are converted to encode the embedded special-to-xml characters to entities too.</p>
	</html>");
}

/++
	Streaming parsing

	dom.d normally takes a big string and returns a big DOM object tree - hence its name. This is usually the simplest
	code to read and write, so I prefer to stick to that, but if you wanna jump through a few hoops, you can still make
	dom.d work with streams.

	It is awkward - again, dom.d's whole design is based on building the dom tree, but you can do it if you're willing to
	subclass a little and trust the garbage collector. Here's how.
+/
unittest {
	bool encountered;
	class StreamDocument : Document {
		// the normal behavior for this function is to `parent.appendChild(child)`
		// but we can override to read it as it is processed and not append it
		override void processNodeWhileParsing(Element parent, Element child) {
			if(child.tagName == "bar")
				encountered = true;
			// note that each element's object is created but then discarded as garbage.
			// the GC will take care of it, even with a large document, whereas the normal
			// object tree could become quite large.
		}

		this() {
			super("<foo><bar></bar></foo>");
		}
	}

	auto test = new StreamDocument();
	assert(encountered); // it should have been seen
	assert(test.querySelector("bar") is null); // but not appended to the dom node, since we didn't append it
}

/++
	Basic parsing of XML.

	dom.d is not technically a standards-compliant xml parser and doesn't implement all xml features,
	but its stricter parse options together with turning off HTML's special tag handling (e.g. treating
	`<script>` and `<style>` the same as any other tag) gets close enough to work fine for a great many
	use cases.

	For more information, see [XmlDocument].
+/
unittest {
	auto xml = new XmlDocument(`<my-stuff>hello</my-stuff>`);
}

bool canNestElementsInHtml(string parentTagName, string childTagName) {
	switch(parentTagName) {
		case "p", "h1", "h2", "h3", "h4", "h5", "h6":
			// only should include "phrasing content"
			switch(childTagName) {
				case "p", "dl", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6":
					return false;
				default: return true;
			}
		case "dt", "dd":
			switch(childTagName) {
				case "dd", "dt":
					return false;
				default: return true;
			}
		default:
			return true;
	}
}

interface DomParent {
	inout(Document) asDocument() inout;
	inout(Element) asElement() inout;
}

/++
	This represents almost everything in the DOM and offers a lot of inspection and manipulation functions. Element, or its subclasses, are what makes the dom tree.
+/
/// Group: core_functionality
class Element : DomParent {
	inout(Document) asDocument() inout { return null; }
	inout(Element) asElement() inout { return this; }

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
	do {
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
	do {
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
	@property string[] classes() const {
		// FIXME: remove blank names
		auto cs = split(className, " ");
		foreach(ref c; cs)
			c = c.strip();
		return cs;
	}

	/++
		The object [classList] returns.
	+/
	static struct ClassListHelper {
		Element this_;
		this(inout(Element) this_) inout {
			this.this_ = this_;
		}

		///
		bool contains(string cn) const {
			return this_.hasClass(cn);
		}

		///
		void add(string cn) {
			this_.addClass(cn);
		}

		///
		void remove(string cn) {
			this_.removeClass(cn);
		}

		///
		void toggle(string cn) {
			if(contains(cn))
				remove(cn);
			else
				add(cn);
		}

		// this thing supposed to be iterable in javascript but idk how i want to do it in D. meh
		/+
		string[] opIndex() const {
			return this_.classes;
		}
		+/
	}

	/++
		Returns a helper object to work with classes, just like javascript.

		History:
			Added August 25, 2022
	+/
	@property inout(ClassListHelper) classList() inout {
		return inout(ClassListHelper)(this);
	}
	// FIXME: classList is supposed to whitespace and duplicates when you use it. need to test.

	unittest {
		Element element = Element.make("div");
		element.classList.add("foo");
		assert(element.classList.contains("foo"));
		element.classList.remove("foo");
		assert(!element.classList.contains("foo"));
		element.classList.toggle("bar");
		assert(element.classList.contains("bar"));
	}

	/// ditto
	alias classNames = classes;


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
	bool hasClass(string c) const {
		string cn = className;

		auto idx = cn.indexOf(c);
		if(idx == -1)
			return false;

		foreach(cla; cn.split(" "))
			if(cla.strip == c)
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
	/++
		Family of convenience functions to quickly add a tag with some text or
		other relevant info (for example, it's a src for an <img> element
		instead of inner text). They forward to [Element.make] then calls [appendChild].

		---
		div.addChild("span", "hello there");
		div.addChild("div", Html("<p>children of the div</p>"));
		---
	+/
	Element addChild(string tagName, string childInfo = null, string childInfo2 = null)
		in {
			assert(tagName !is null);
		}
		out(e) {
			//assert(e.parentNode is this);
			//assert(e.parentDocument is this.parentDocument);
		}
	do {
		auto e = Element.make(tagName, childInfo, childInfo2);
		// FIXME (maybe): if the thing is self closed, we might want to go ahead and
		// return the parent. That will break existing code though.
		return appendChild(e);
	}

	/// ditto
	Element addChild(Element e) {
		return this.appendChild(e);
	}

	/// ditto
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
	do {
		auto e = Element.make(tagName, "", info2);
		e.appendChild(firstChild);
		this.appendChild(e);
		return e;
	}

	/// ditto
	Element addChild(string tagName, in Html innerHtml, string info2 = null)
	in {
	}
	out(ret) {
		assert(ret !is null);
		assert((cast(DocumentFragment) this !is null) || (ret.parentNode is this), ret.toString);// e.parentNode ? e.parentNode.toString : "null");
		assert(ret.parentDocument is this.parentDocument);
	}
	do {
		auto e = Element.make(tagName, "", info2);
		this.appendChild(e);
		e.innerHTML = innerHtml.source;
		return e;
	}


	/// Another convenience function. Adds a child directly after the current one, returning
	/// the new child.
	///
	/// Between this, addChild, and parentNode, you can build a tree as a single expression.
	/// See_Also: [addChild]
	Element addSibling(string tagName, string childInfo = null, string childInfo2 = null)
		in {
			assert(tagName !is null);
			assert(parentNode !is null);
		}
		out(e) {
			assert(e.parentNode is this.parentNode);
			assert(e.parentDocument is this.parentDocument);
		}
	do {
		auto e = Element.make(tagName, childInfo, childInfo2);
		return parentNode.insertAfter(this, e);
	}

	/// ditto
	Element addSibling(Element e) {
		return parentNode.insertAfter(this, e);
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

	/// Appends the list of children to this element.
	void appendChildren(Element[] children) {
		foreach(ele; children)
			appendChild(ele);
	}

	/// Removes this element form its current parent and appends it to the given `newParent`.
	void reparent(Element newParent)
		in {
			assert(newParent !is null);
			assert(parentNode !is null);
		}
		out {
			assert(this.parentNode is newParent);
			//assert(isInArray(this, newParent.children));
		}
	do {
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
	do {
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
	do {
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
	do {
		this.replaceWith(what);
		what.appendChild(this);

		return what;
	}

	/// Replaces this element with something else in the tree.
	Element replaceWith(Element e)
	in {
		assert(this.parentNode !is null);
	}
	do {
		e.removeFromTree();
		this.parentNode.replaceChild(this, e);
		return e;
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
	void setValue(string field, string[] value) { }


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

	/++
		This is where the attributes are actually stored. You should use getAttribute, setAttribute, and hasAttribute instead.

		History:
			`AttributesHolder` replaced `string[string]` on August 22, 2024
	+/
	AttributesHolder attributes;

	/// In XML, it is valid to write <tag /> for all elements with no children, but that breaks HTML, so I don't do it here.
	/// Instead, this flag tells if it should be. It is based on the source document's notation and a html element list.
	private bool selfClosed;

	private DomParent parent_;

	/// Get the parent Document object that contains this element.
	/// It may be null, so remember to check for that.
	@property inout(Document) parentDocument() inout {
		if(this.parent_ is null)
			return null;
		auto p = cast() this.parent_.asElement;
		auto prev = cast() this;
		while(p) {
			prev = p;
			if(p.parent_ is null)
				return null;
			p = cast() p.parent_.asElement;
		}
		return cast(inout) prev.parent_.asDocument;
	}

	/*deprecated*/ @property void parentDocument(Document doc) {
		parent_ = doc;
	}

	/// Returns the parent node in the tree this element is attached to.
	inout(Element) parentNode() inout {
		if(parent_ is null)
			return null;

		auto p = parent_.asElement;

		if(cast(DocumentFragment) p) {
			if(p.parent_ is null)
				return null;
			else
				return p.parent_.asElement;
		}

		return p;
	}

	//protected
	Element parentNode(Element e) {
		parent_ = e;
		return e;
	}

	// these are here for event handlers. Don't forget that this library never fires events.
	// (I'm thinking about putting this in a version statement so you don't have the baggage. The instance size of this class is 56 bytes right now.)

	version(dom_with_events) {
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
	}


	// and now methods

	/++
		Convenience function to try to do the right thing for HTML. This is the main way I create elements.

		History:
			On February 8, 2021, the `selfClosedElements` parameter was added. Previously, it used a private
			immutable global list for HTML. It still defaults to the same list, but you can change it now via
			the parameter.
		See_Also:
			[addChild], [addSibling]
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

	/// ditto
	static Element make(string tagName, in Html innerHtml, string childInfo2 = null) {
		// FIXME: childInfo2 is ignored when info1 is null
		auto m = Element.make(tagName, "not null"[0..0], childInfo2);
		m.innerHTML = innerHtml.source;
		return m;
	}

	/// ditto
	static Element make(string tagName, Element child, string childInfo2 = null) {
		auto m = Element.make(tagName, cast(string) null, childInfo2);
		m.appendChild(child);
		return m;
	}


	/// Generally, you don't want to call this yourself - use Element.make or document.createElement instead.
	this(Document _parentDocument, string _tagName, string[string] _attributes = null, bool _selfClosed = false) {
		tagName = _tagName;
		foreach(k, v; _attributes)
			attributes[k] = v;
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
		foreach(k, v; _attributes)
			attributes[k] = v;
		selfClosed = tagName.isInArray(selfClosedElements);

		// this is meant to reserve some memory. It makes a small, but consistent improvement.
		//children.length = 8;
		//children.length = 0;

		version(dom_node_indexes)
			this.dataset.nodeIndex = to!string(&(this.attributes));
	}

	private this(Document _parentDocument) {
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

	/// Returns the last child of the element, or null if it has no children. Remember, text nodes are children too.
	@property Element lastChild() {
		return children.length ? children[$ - 1] : null;
	}

	// FIXME UNTESTED
	/// the next or previous element you would encounter if you were reading it in the source. May be a text node or other special non-tag object if you enabled them.
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

	/++
		Returns the next or previous sibling that is not a text node. Please note: the behavior with comments is subject to change. Currently, it will return a comment or other nodes if it is in the tree (if you enabled it with [Document.enableAddingSpecialTagsToDom] or [Document.parseSawComment]) and not if you didn't, but the implementation will probably change at some point to skip them regardless.

		Equivalent to [previousSibling]/[nextSibling]("*").

		Please note it may return `null`.
	+/
	@property Element previousElementSibling() {
		return previousSibling("*");
	}

	/// ditto
	@property Element nextElementSibling() {
		return nextSibling("*");
	}

	/++
		Returns the next or previous sibling matching the `tagName` filter. The default filter of `null` will return the first sibling it sees, even if it is a comment or text node, or anything else. A filter of `"*"` will match any tag with a name. Otherwise, the string must match the [tagName] of the sibling you want to find.
	+/
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

	/// ditto
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


	/++
		Gets the nearest node, going up the chain, with the given tagName
		May return null or throw. The type `T` will specify a subclass like
		[Form], [Table], or [Link], which it will cast for you when found.
	+/
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

	/++
		Searches this element and the tree of elements under it for one matching the given `id` attribute.
	+/
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

		Tip: to use namespaces, escape the colon in the name:

		---
			element.querySelector(`ns\:tag`); // the backticks are raw strings then the backslash is interpreted by querySelector
		---
	+/
	@scriptable
	Element querySelector(string selector) {
		Selector s = Selector(selector);

		foreach(ref comp; s.components)
			if(comp.parts.length && comp.parts[0].separation > 0) {
				// this is illegal in standard dom, but i use it a lot
				// gonna insert a :scope thing

				SelectorPart part;
				part.separation = -1;
				part.scopeElement = true;
				comp.parts = part ~ comp.parts;
			}

		foreach(ele; tree)
			if(s.matchesElement(ele, this))
				return ele;
		return null;
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

		The name `getElementsBySelector` was the original name, written back before the name `querySelector` was standardized (this library is older than you might think!), but they do the same thing..
	*/
	@scriptable
	Element[] querySelectorAll(string selector) {
		// FIXME: this function could probably use some performance attention
		// ... but only mildly so according to the profiler in the big scheme of things; probably negligible in a big app.


		bool caseSensitiveTags = true;
		if(parentDocument && parentDocument.loose)
			caseSensitiveTags = false;

		Element[] ret;
		foreach(sel; parseSelectorString(selector, caseSensitiveTags))
			ret ~= sel.getElements(this, null);
		return ret;
	}

	/// ditto
	alias getElementsBySelector = querySelectorAll;

	/++
		Returns child elements that have the given class name or tag name.

		Please note the standard specifies this should return a live node list. This means, in Javascript for example, if you loop over the value returned by getElementsByTagName and getElementsByClassName and remove the elements, the length of the list will decrease. When I implemented this, I figured that was more trouble than it was worth and returned a plain array instead. By the time I had the infrastructure to make it simple, I didn't want to do the breaking change.

		So these is incompatible with Javascript in the face of live dom mutation and will likely remain so.
	+/
	Element[] getElementsByClassName(string cn) {
		// is this correct?
		return getElementsBySelector("." ~ cn);
	}

	/// ditto
	Element[] getElementsByTagName(string tag) {
		if(parentDocument && parentDocument.loose)
			tag = tag.toLower();
		Element[] ret;
		foreach(e; tree)
			if(e.tagName == tag || tag == "*")
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
		return attributes.get(name, null);
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
	do {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();
		if(name in attributes)
			attributes.remove(name);

		sendObserverEvent(DomMutationOperations.removeAttribute, name);
		return this;
	}

	/**
		Gets or sets the class attribute's contents. Returns
		an empty string if it has no class.
	*/
	@property string className() const {
		auto c = getAttribute("class");
		if(c is null)
			return "";
		return c;
	}

	/// ditto
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
	@property inout(Element[]) childNodes() inout {
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

	// the next few methods are for implementing interactive kind of things
	private CssStyle _computedStyle;

	/// Don't use this. It can try to parse out the style element but it isn't complete and if I get back to it, it won't be for a while.
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


			_computedStyle = computedStyleFactory(this);
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
	do {
		foreach(child; children)
			child.parentNode = null;
		children = null;
	}

	/++
		Adds a sibling element before or after this one in the dom.

		History: added June 13, 2020
	+/
	Element appendSibling(Element e) {
		parentNode.insertAfter(this, e);
		return e;
	}

	/// ditto
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
			assert(e !is this);
		}
		out (ret) {
			assert((cast(DocumentFragment) this !is null) || (e.parentNode is this), e.toString);// e.parentNode ? e.parentNode.toString : "null");
			assert(e.parentDocument is this.parentDocument);
			assert(e is ret);
		}
	do {
		if(e.parentNode !is null)
			e.parentNode.removeChild(e);

		selfClosed = false;
		if(auto frag = cast(DocumentFragment) e)
			children ~= frag.children;
		else
			children ~= e;

		e.parentNode = this;

		/+
		foreach(item; e.tree)
			item.parentDocument = this.parentDocument;
		+/

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
	do {
		foreach(i, e; children) {
			if(e is where) {
				if(auto frag = cast(DocumentFragment) what) {
					children = children[0..i] ~ frag.children ~ children[i..$];
					foreach(child; frag.children)
						child.parentNode = this;
				} else {
					children = children[0..i] ~ what ~ children[i..$];
				}
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
	do {
		foreach(i, e; children) {
			if(e is where) {
				if(auto frag = cast(DocumentFragment) what) {
					children = children[0 .. i + 1] ~ what.children ~ children[i + 1 .. $];
					foreach(child; frag.children)
						child.parentNode = this;
				} else
					children = children[0 .. i + 1] ~ what ~ children[i + 1 .. $];
				what.parentNode = this;
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
	do {
		foreach(ref c; this.children)
			if(c is child) {
				c.parentNode = null;
				c = replacement;
				c.parentNode = this;
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

	/++
		Returns `this` for use inside `with` expressions.

		History:
			Added December 20, 2024
	+/
	inout(Element) self() inout pure @nogc nothrow @safe scope return {
		return this;
	}

	/++
		Inserts a child under this element after the element `where`.
	+/
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
	do {
		foreach(ref i, c; children) {
			if(c is where) {
				i++;
				if(auto frag = cast(DocumentFragment) child) {
					children = children[0..i] ~ child.children ~ children[i..$];
					//foreach(child; frag.children)
						//child.parentNode = this;
				} else
					children = children[0..i] ~ child ~ children[i..$];
				child.parentNode = this;
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
	do {
		foreach(c; e.children) {
			c.parentNode = this;
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
	do {
		if(auto frag = cast(DocumentFragment) e) {
			children = e.children ~ children;
			foreach(child; frag.children)
				child.parentNode = this;
		} else
			children = e ~ children;
		e.parentNode = this;
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
		}

		doc.root.children = null;

		return this;
	}

	/// ditto
	@property Element innerHTML(Html html) {
		return this.innerHTML = html.source;
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
		}

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
		children ~= rs;
		rs.parentNode = this;
	}

	/++
		Replaces the element `find`, which must be a child of `this`, with the element `replace`, which must have no parent.
	+/
	Element replaceChild(Element find, Element replace)
		in {
			assert(find !is null);
			assert(find.parentNode is this);
			assert(replace !is null);
			assert(replace.parentNode is null);
		}
		out(ret) {
			assert(ret is replace);
			assert(replace.parentNode is this);
			assert(replace.parentDocument is this.parentDocument);
			assert(find.parentNode is null);
		}
	do {
		// FIXME
		//if(auto frag = cast(DocumentFragment) replace)
			//return this.replaceChild(frag, replace.children);
		for(int i = 0; i < children.length; i++) {
			if(children[i] is find) {
				replace.parentNode = this;
				children[i].parentNode = null;
				children[i] = replace;
				return replace;
			}
		}

		throw new Exception("no such child ");// ~  find.toString ~ " among " ~ typeid(this).toString);//.toString ~ " magic \n\n\n" ~ find.parentNode.toString);
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
	do {
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
	do {
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
	do {
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

		It is more like [textContent].

		See_Also:
			[visibleText], which is closer to what the real `innerText`
			does.
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

	/// ditto
	alias textContent = innerText;

	/++
		Gets the element's visible text, similar to how it would look assuming
		the document was HTML being displayed by a browser. This means it will
		attempt whitespace normalization (unless it is a `<pre>` tag), add `\n`
		characters for `<br>` tags, and I reserve the right to make it process
		additional css and tags in the future.

		If you need specific output, use the more stable [textContent] property
		or iterate yourself with [tree] or a recursive function with [children].

		History:
			Added March 25, 2022 (dub v10.8)
	+/
	string visibleText() const {
		return this.visibleTextHelper(this.tagName == "pre");
	}

	private string visibleTextHelper(bool pre) const {
		string result;
		foreach(thing; this.children) {
			if(thing.nodeType == NodeType.Text)
				result ~= pre ? thing.nodeValue : normalizeWhitespace(thing.nodeValue);
			else if(thing.tagName == "br")
				result ~= "\n";
			else
				result ~= thing.visibleTextHelper(pre || thing.tagName == "pre");
		}
		return result;
	}

	/**
		Sets the inside text, replacing all children. You don't
		have to worry about entity encoding.
	*/
	@scriptable
	@property void innerText(string text) {
		selfClosed = false;
		Element e = new TextNode(parentDocument, text);
		children = [e];
		e.parentNode = this;
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
	do {
	+/
	{
		return this.cloneNode(true);
	}

	/// Clones the node. If deepClone is true, clone all inner tags too. If false, only do this tag (and its attributes), but it will have no contents.
	Element cloneNode(bool deepClone) {
		auto e = Element.make(this.tagName);
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
		debug assert(tagName.indexOf(" ") == -1);

		// commented cuz it gets into recursive pain and eff dat.
		/+
		if(children !is null)
		foreach(child; children) {
		//	assert(parentNode !is null);
			assert(child !is null);
			assert(child.parent_.asElement is this, format("%s is not a parent of %s (it thought it was %s)", tagName, child.tagName, child.parent_.asElement is null ? "null" : child.parent_.asElement.tagName));
			assert(child !is this);
			//assert(child !is parentNode);
		}
		+/

		/+
		// this isn't helping
		if(parent_ && parent_.asElement) {
			bool found = false;
			foreach(child; parent_.asElement.children)
				if(child is this)
					found = true;
			assert(found, format("%s lists %s as parent, but it is not in children", typeid(this), typeid(this.parent_.asElement)));
		}
		+/

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

	/++
		Returns if the node would be printed to string as `<tag />` or `<tag></tag>`. In other words, if it has no non-empty text nodes and no element nodes. Please note that whitespace text nodes are NOT considered empty; `Html("<tag> </tag>").isEmpty == false`.


		The value is undefined if there are comment or processing instruction nodes. The current implementation returns false if it sees those, assuming the nodes haven't been stripped out during parsing. But I'm not married to the current implementation and reserve the right to change it without notice.

		History:
			Added December 3, 2021 (dub v10.5)

	+/
	public bool isEmpty() const {
		foreach(child; this.children) {
			// any non-text node is of course not empty since that's a tag
			if(child.nodeType != NodeType.Text)
				return false;
			// or a text node is empty if it is is a null or empty string, so this length check fixes that
			if(child.nodeValue.length)
				return false;
		}

		return true;
	}

	protected string toPrettyStringIndent(bool insertComments, int indentationLevel, string indentWith) const {
		if(indentWith is null)
			return null;

		// at the top we don't have anything to really do
		//if(parent_ is null)
			//return null;

			// I've used isEmpty before but this other check seems better....
			//|| this.isEmpty())

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

		$(PITFALL
			This function is not stable. Its interface and output may change without
			notice. The only promise I make is that it will continue to make a best-
			effort attempt at being useful for debugging by human eyes.

			I have used it in the past for diffing html documents, but even then, it
			might change between versions. If it is useful, great, but beware; this
			use is at your own risk.
		)

		History:
			On November 19, 2021, I changed this to `final`. If you were overriding it,
			change our override to `toPrettyStringImpl` instead. It now just calls
			`toPrettyStringImpl.strip` to be an entry point for a stand-alone call.

			If you are calling it as part of another implementation, you might want to
			change that call to `toPrettyStringImpl` as well.

			I am NOT considering this a breaking change since this function is documented
			to only be used for eyeball debugging anyway, which means the exact format is
			not specified and the override behavior can generally not be relied upon.

			(And I find it extremely unlikely anyone was subclassing anyway, but if you were,
			email me, and we'll see what we can do. I'd like to know at least.)

			I reserve the right to make future changes in the future without considering
			them breaking as well.
	+/
	final string toPrettyString(bool insertComments = false, int indentationLevel = 0, string indentWith = "\t") const {
		return toPrettyStringImpl(insertComments, indentationLevel, indentWith).strip;
	}

	string toPrettyStringImpl(bool insertComments = false, int indentationLevel = 0, string indentWith = "\t") const {

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

		auto inlineElements = (parentDocument is null ? null : parentDocument.inlineElements);

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

		if(isEmpty) {
			// no work needed, this is empty so don't indent just for a blank line
		} else if(children.length == 1 && children[0].isEmpty) {
			// just one empty one, can put it inline too
			s ~= children[0].toString();
		} else if(tagName.isInArray(inlineElements) || allAreInlineHtml(children, inlineElements)) {
			foreach(child; children) {
				s ~= child.toString();//toPrettyString(false, 0, null);
			}
		} else {
			foreach(child; children) {
				assert(child !is null);

				s ~= child.toPrettyStringImpl(insertComments, indentationLevel + 1, indentWith);
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

	/++
		This is the actual implementation used by toString. You can pass it a preallocated buffer to save some time.
		Note: the ordering of attributes in the string is undefined.
		Returns the string it creates.

		Implementation_Notes:
			The order of attributes printed by this function is undefined, as permitted by the XML spec. You should NOT rely on any implementation detail noted here.

			However, in practice, between June 14, 2019 and August 22, 2024, it actually did sort attributes by key name. After August 22, 2024, it changed to track attribute append order and will print them back out in the order in which the keys were first seen.

			This is subject to change again at any time. Use [toPrettyString] if you want a defined output (toPrettyString always sorts by name for consistent diffing).
	+/
	string writeToAppender(Appender!string where = appender!string()) const {
		assert(tagName !is null);

		where.reserve((this.children.length + 1) * 512);

		auto start = where.data.length;

		where.put("<");
		where.put(tagName);

		/+
		import std.algorithm : sort;
		auto keys = sort(attributes.keys);
		foreach(n; keys) {
			auto v = attributes[n]; // I am sorting these for convenience with another project. order of AAs is undefined, so I'm allowed to do it.... and it is still undefined, I might change it back later.
		+/
		foreach(n, v; attributes) {
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
	// FIXME: add overloads for other label types...
	/++
		Adds a form field to this element, normally a `<input>` but `type` can also be `"textarea"`.

		This is fairly html specific and the label uses my style. I recommend you view the source before you use it to better understand what it does.
	+/
	/// Tags: HTML, HTML5
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

	/// ditto
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

	/// ditto
	Element addField(string label, string name, FormFieldOptions fieldOptions) {
		return addField(label, name, "text", fieldOptions);
	}

	/// ditto
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

	/// ditto
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

// computedStyle could argubaly be removed to bring size down
//pragma(msg, __traits(classInstanceSize, Element));
//pragma(msg, Element.tupleof);

// FIXME: since Document loosens the input requirements, it should probably be the sub class...
/++
	Specializes Document for handling generic XML. (always uses strict mode, uses xml mime type and file header)

	History:
		On December 16, 2022, it disabled the special case treatment of `<script>` and `<style>` that [Document]
		does for HTML. To get the old behavior back, add `, true` to your constructor call.
+/
/// Group: core_functionality
class XmlDocument : Document {
	/++
		Constructs a stricter-mode XML parser and parses the given data source.

		History:
			The `Utf8Stream` version of the constructor was added on February 22, 2025.
	+/
	this(string data, bool enableHtmlHacks = false) {
		this(new Utf8Stream(data), enableHtmlHacks);
	}

	/// ditto
	this(Utf8Stream data, bool enableHtmlHacks = false) {
		selfClosedElements = null;
		inlineElements = null;
		rawSourceElements = null;
		contentType = "text/xml; charset=utf-8";
		_prolog = `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n";

		parseStream(data, true, true, !enableHtmlHacks);
	}
}

unittest {
	// FIXME: i should also make XmlDocument do different entities than just html too.
	auto str = "<html><style>foo {}</style><script>void function() { a < b; }</script></html>";
	auto document = new Document(str, true, true);
	assert(document.requireSelector("style").children[0].tagName == "#raw");
	assert(document.requireSelector("script").children[0].tagName == "#raw");
	try {
		auto xml = new XmlDocument(str);
		assert(0);
	} catch(MarkupException e) {
		// failure expected, script special case is not valid XML without a dtd (which isn't here)
	}
	//assert(xml.requireSelector("style").children[0].tagName == "#raw");
	//assert(xml.requireSelector("script").children[0].tagName == "#raw");
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
	/// Generally, you shouldn't create this yourself, since you can use [Element.attrs] instead.
	this(Element e) {
		this._element = e;
	}

	private Element _element;
	/++
		Sets a `value` for attribute with `name`. If the attribute doesn't exist, this will create it, even if `value` is `null`.
	+/
	string set(string name, string value) {
		_element.setAttribute(name, value);
		return value;
	}

	/++
		Provides support for testing presence of an attribute with the `in` operator.

		History:
			Added December 16, 2020 (dub v10.10)
	+/
	auto opBinaryRight(string op : "in")(string name) const
	{
		return name in _element.attributes;
	}
	///
	unittest
	{
		auto doc = new XmlDocument(`<test attr="test"/>`);
		assert("attr" in doc.root.attrs);
		assert("test" !in doc.root.attrs);
	}

	/++
		Returns the value of attribute `name`, or `null` if doesn't exist
	+/
	string get(string name) const {
		return _element.getAttribute(name);
	}

	///
	mixin JavascriptStyleDispatch!();
}

private struct InternalAttribute {
	// variable length structure
	private InternalAttribute* next;
	private uint totalLength;
	private ushort keyLength;
	private char[0] chars;

	// this really should be immutable tbh
	inout(char)[] key() inout return {
		return chars.ptr[0 .. keyLength];
	}

	inout(char)[] value() inout return {
		return chars.ptr[keyLength .. totalLength];
	}

	static InternalAttribute* make(in char[] key, in char[] value) {
		// old code was
		//auto data = new ubyte[](InternalAttribute.sizeof + key.length + value.length);
		//GC.addRange(data.ptr, data.length); // MUST add the range to scan it!

		import core.memory;
		// but this code is a bit better, notice we did NOT set the NO_SCAN attribute because of the presence of the next pointer
		// (this can sometimes be a pessimization over the separate strings but meh, most of these attributes are supposed to be small)
		auto obj = cast(InternalAttribute*) GC.calloc(InternalAttribute.sizeof + key.length + value.length);

		// assert(key.length > 0);

		obj.totalLength = cast(uint) (key.length + value.length);
		obj.keyLength = cast(ushort) key.length;
		if(key.length != obj.keyLength)
			throw new Exception("attribute key overflow");
		if(key.length + value.length != obj.totalLength)
			throw new Exception("attribute length overflow");

		obj.key[] = key[];
		obj.value[] = value[];

		return obj;
	}

	// FIXME: disable default ctor and op new
}

import core.exception;

struct AttributesHolder {
	private @system InternalAttribute* attributes;

	/+
	invariant() {
		const(InternalAttribute)* wtf = attributes;
		while(wtf) {
			assert(wtf != cast(void*) 1);
			assert(wtf.keyLength != 0);
			import std.stdio; writeln(wtf.key, "=", wtf.value);
			wtf = wtf.next;
		}
	}
	+/

	/+
		It is legal to do foo["key", "default"] to call it with no error...
	+/
	string opIndex(scope const char[] key) const {
		auto found = find(key);
		if(found is null)
			throw new RangeError(key.idup); // FIXME
		return cast(string) found.value;
	}

	string get(scope const char[] key, string returnedIfKeyNotFound = null) const {
		auto attr = this.find(key);
		if(attr is null)
			return returnedIfKeyNotFound;
		else
			return cast(string) attr.value;
	}

	private string[] keys() const {
		string[] ret;
		foreach(k, v; this)
			ret ~= k;
		return ret;
	}

	/+
		If this were to return a string* it'd be tricky cuz someone could try to rebind it, which is impossible.

		This is a breaking change. You can get a similar result though with [get].
	+/
	bool opBinaryRight(string op : "in")(scope const char[] key) const {
		return find(key) !is null;
	}

	private inout(InternalAttribute)* find(scope const char[] key) inout @trusted {
		inout(InternalAttribute)* current = attributes;
		while(current) {
			// assert(current > cast(void*) 1);
			if(current.key == key)
				return current;
			current = current.next;
		}
		return null;
	}

	void remove(scope const char[] key) @trusted {
		if(attributes is null)
			return;
		auto current = attributes;
		InternalAttribute* previous;
		while(current) {
			if(current.key == key)
				break;
			previous = current;
			current = current.next;
		}
		if(current is null)
			return;
		if(previous is null)
			attributes = current.next;
		else
			previous.next = current.next;
		// assert(previous.next != cast(void*) 1);
		// assert(attributes != cast(void*) 1);
	}

	void opIndexAssign(scope const char[] value, scope const char[] key) @trusted {
		if(attributes is null) {
			attributes = InternalAttribute.make(key, value);
			return;
		}
		auto current = attributes;

		if(current.key == key) {
			if(current.value != value) {
				auto replacement = InternalAttribute.make(key, value);
				attributes = replacement;
				replacement.next = current.next;
		// assert(replacement.next != cast(void*) 1);
		// assert(attributes != cast(void*) 1);
			}
			return;
		}

		while(current.next) {
			if(current.next.key == key) {
				if(current.next.value == value)
					return; // replacing immutable value with self, no change
				break;
			}
			current = current.next;
		}
		assert(current !is null);

		auto replacement = InternalAttribute.make(key, value);
		if(current.next !is null)
			replacement.next = current.next.next;
		current.next = replacement;
		// assert(current.next != cast(void*) 1);
		// assert(replacement.next != cast(void*) 1);
	}

	int opApply(int delegate(string key, string value) dg) const @trusted {
		const(InternalAttribute)* current = attributes;
		while(current !is null) {
			if(auto res = dg(cast(string) current.key, cast(string) current.value))
				return res;
			current = current.next;
		}
		return 0;
	}
}

unittest {
	AttributesHolder holder;
	holder["one"] = "1";
	holder["two"] = "2";
	holder["three"] = "3";

	{
		assert("one" in holder);
		assert("two" in holder);
		assert("three" in holder);
		assert("four" !in holder);

		int count;
		foreach(k, v; holder) {
			switch(count) {
				case 0: assert(k == "one" && v == "1"); break;
				case 1: assert(k == "two" && v == "2"); break;
				case 2: assert(k == "three" && v == "3"); break;
				default: assert(0);
			}
			count++;
		}
	}

	holder["two"] = "dos";

	{
		assert("one" in holder);
		assert("two" in holder);
		assert("three" in holder);
		assert("four" !in holder);

		int count;
		foreach(k, v; holder) {
			switch(count) {
				case 0: assert(k == "one" && v == "1"); break;
				case 1: assert(k == "two" && v == "dos"); break;
				case 2: assert(k == "three" && v == "3"); break;
				default: assert(0);
			}
			count++;
		}
	}

	holder["four"] = "4";

	{
		assert("one" in holder);
		assert("two" in holder);
		assert("three" in holder);
		assert("four" in holder);

		int count;
		foreach(k, v; holder) {
			switch(count) {
				case 0: assert(k == "one" && v == "1"); break;
				case 1: assert(k == "two" && v == "dos"); break;
				case 2: assert(k == "three" && v == "3"); break;
				case 3: assert(k == "four" && v == "4"); break;
				default: assert(0);
			}
			count++;
		}
	}
}

/// for style, i want to be able to set it with a string like a plain attribute,
/// but also be able to do properties Javascript style.

/// Group: implementations
struct ElementStyle {
	this(Element parent) {
		_element = parent;
		_attribute = _element.getAttribute("style");
		originalAttribute = _attribute;
	}

	~this() {
		if(_attribute !is originalAttribute)
			_element.setAttribute("style", _attribute);
	}

	Element _element;
	string _attribute;
	string originalAttribute;

	/+
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
	+/

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
do {
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

	override string toPrettyStringImpl(bool insertComments, int indentationLevel, string indentWith) const {
		string s;
		foreach(child; children)
			s ~= child.toPrettyStringImpl(insertComments, indentationLevel, indentWith);
		return s;
	}

	/// DocumentFragments don't really exist in a dom, so they ignore themselves in parent nodes
	/*
	override inout(Element) parentNode() inout {
		return children.length ? children[0].parentNode : null;
	}
	*/
	/+
	override Element parentNode(Element p) {
		this.parentNode = p;
		foreach(child; children)
			child.parentNode = p;
		return p;
	}
	+/
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

	char[128] buffer;
	int bpos;
	foreach(char c; entity[1 .. $-1])
		buffer[bpos++] = c;
	char[] entityAsString = buffer[0 .. bpos];

	int min = 0;
	int max = cast(int) availableEntities.length;

	keep_looking:
	if(min + 1 < max) {
		int spot = (max - min) / 2 + min;
		if(availableEntities[spot] == entityAsString) {
			return availableEntitiesValues[spot];
		} else if(entityAsString < availableEntities[spot]) {
			max = spot;
			goto keep_looking;
		} else {
			min = spot;
			goto keep_looking;
		}
	}

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

					while(decimal.length && (decimal[$-1] < '0' || decimal[$-1] >   '9'))
						decimal = decimal[0 .. $ - 1];

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

unittest {
	// not in the binary search
	assert(parseEntity("&quot;"d) == '"');

	// numeric value
	assert(parseEntity("&#x0534;") == '\u0534');

	// not found at all
	assert(parseEntity("&asdasdasd;"d) == '\ufffd');

	// random values in the bin search
	assert(parseEntity("&Tab;"d) == '\t');
	assert(parseEntity("&raquo;"d) == '\&raquo;');

	// near the middle and edges of the bin search
	assert(parseEntity("&ascr;"d) == '\U0001d4b6');
	assert(parseEntity("&ast;"d) == '\u002a');
	assert(parseEntity("&AElig;"d) == '\u00c6');
	assert(parseEntity("&zwnj;"d) == '\u200c');
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
	bool tryingNumericEntity = false;
	bool tryingHexEntity = false;
	dchar[16] entityBeingTried;
	int entityBeingTriedLength = 0;
	int entityAttemptIndex = 0;

	foreach(dchar ch; data) {
		if(tryingEntity) {
			entityAttemptIndex++;
			entityBeingTried[entityBeingTriedLength++] = ch;

			if(entityBeingTriedLength == 2 && ch == '#') {
				tryingNumericEntity = true;
				continue;
			} else if(tryingNumericEntity && entityBeingTriedLength == 3 && ch == 'x') {
				tryingHexEntity = true;
				continue;
			}

			// I saw some crappy html in the wild that looked like &0&#1111; this tries to handle that.
			if(ch == '&') {
				if(strict)
					throw new Exception("unterminated entity; & inside another at " ~ to!string(entityBeingTried[0 .. entityBeingTriedLength]));

				// if not strict, let's try to parse both.

				if(entityBeingTried[0 .. entityBeingTriedLength] == "&&") {
					a ~= "&"; // double amp means keep the first one, still try to parse the next one
				} else {
					auto ch2 = parseEntity(entityBeingTried[0 .. entityBeingTriedLength]);
					if(ch2 == '\ufffd') { // either someone put this in intentionally (lol) or we failed to get it
						// but either way, just abort and keep the plain text
						foreach(char c; entityBeingTried[0 .. entityBeingTriedLength - 1]) // cut off the & we're on now
							a ~= c;
					} else {
						a ~= buffer[0.. std.utf.encode(buffer, ch2)];
					}
				}

				// tryingEntity is still true
				goto new_entity;
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
					a ~= to!(char[])(entityBeingTried[0 .. entityBeingTriedLength - 1]);
					a ~= buffer[0 .. std.utf.encode(buffer, ch)];
				}
			} else {
				if(tryingNumericEntity) {
					if(ch < '0' || ch > '9') {
						if(tryingHexEntity) {
							if(ch < 'A')
								goto trouble;
							if(ch > 'Z' && ch < 'a')
								goto trouble;
							if(ch > 'z')
								goto trouble;
						} else {
							trouble:
							if(strict)
								throw new Exception("unterminated entity at " ~ to!string(entityBeingTried[0 .. entityBeingTriedLength]));
							tryingEntity = false;
							a ~= buffer[0.. std.utf.encode(buffer, parseEntity(entityBeingTried[0 .. entityBeingTriedLength]))];
							a ~= ch;
							continue;
						}
					}
				}


				if(entityAttemptIndex >= 9) {
					done:
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
				new_entity:
				tryingEntity = true;
				tryingNumericEntity = false;
				tryingHexEntity = false;
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

unittest {
	// error recovery
	assert(htmlEntitiesDecode("&lt;&foo") == "<&foo"); // unterminated turned back to thing
	assert(htmlEntitiesDecode("&lt&foo") == "<&foo"); // semi-terminated... parse and carry on (is this really sane?)
	assert(htmlEntitiesDecode("loc&#61en_us&tracknum&#61;111") == "loc=en_us&tracknum=111"); // a bit of both, seen in a real life email
	assert(htmlEntitiesDecode("&amp test") == "&amp test"); // unterminated, just abort

	// in strict mode all of these should fail
	try { assert(htmlEntitiesDecode("&lt;&foo", true) == "<&foo"); assert(0); } catch(Exception e) { }
	try { assert(htmlEntitiesDecode("&lt&foo", true) == "<&foo"); assert(0); } catch(Exception e) { }
	try { assert(htmlEntitiesDecode("loc&#61en_us&tracknum&#61;111", true) == "<&foo"); assert(0); } catch(Exception e) { }
	try { assert(htmlEntitiesDecode("&amp test", true) == "& test"); assert(0); } catch(Exception e) { }

	// correct cases that should pass the same in strict or loose mode
	foreach(strict; [false, true]) {
		assert(htmlEntitiesDecode("&amp;hello&raquo; win", strict) == "&hello\&raquo; win");
	}
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

	override string toPrettyStringImpl(bool, int, string) const {
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

	override string toPrettyStringImpl(bool, int, string) const {
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

	override string toPrettyStringImpl(bool, int, string) const {
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

	override string toPrettyStringImpl(bool, int, string) const {
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

	override string toPrettyStringImpl(bool, int, string) const {
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

	override string toPrettyStringImpl(bool insertComments = false, int indentationLevel = 0, string indentWith = "\t") const {
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

/++
	Represents a HTML link. This provides some convenience methods for manipulating query strings, but otherwise is sthe same Element interface.

	Please note this object may not be used for all `<a>` tags.
+/
/// Group: implementations
class Link : Element {

	/++
		Constructs `<a href="that href">that text</a>`.
	+/
	this(string href, string text) {
		super("a");
		setAttribute("href", href);
		innerText = text;
	}

	/// ditto
	this(Document _parentDocument) {
		super(_parentDocument);
		this.tagName = "a";
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
				hash[decodeUriComponent(var[0..index])] = decodeUriComponent(var[index + 1 .. $]);
			}
		}

		return hash;
	}

	/// Replaces all the stuff after a ? in the link at once with the given assoc array values.
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

			query ~= encodeUriComponent(name);
			if(value.length)
				query ~= "=" ~ encodeUriComponent(value);
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

	override void setValue(string name, string[] variable) {
		assert(0, "not implemented FIXME");
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

/++
	Represents a HTML form. This slightly specializes Element to add a few more convenience methods for adding and extracting form data.

	Please note this object may not be used for all `<form>` tags.
+/
/// Group: implementations
class Form : Element {

	///.
	this(Document _parentDocument) {
		super(_parentDocument);
		tagName = "form";
	}

	/// Overrides of the base class implementations that more confirm to *my* conventions when writing form html.
	override Element addField(string label, string name, string type = "text", FormFieldOptions fieldOptions = FormFieldOptions.none) {
		auto t = this.querySelector("fieldset div");
		if(t is null)
			return super.addField(label, name, type, fieldOptions);
		else
			return t.addField(label, name, type, fieldOptions);
	}

	/// ditto
	override Element addField(string label, string name, FormFieldOptions fieldOptions) {
		auto type = "text";
		auto t = this.querySelector("fieldset div");
		if(t is null)
			return super.addField(label, name, type, fieldOptions);
		else
			return t.addField(label, name, type, fieldOptions);
	}

	/// ditto
	override Element addField(string label, string name, string[string] options, FormFieldOptions fieldOptions = FormFieldOptions.none) {
		auto t = this.querySelector("fieldset div");
		if(t is null)
			return super.addField(label, name, options, fieldOptions);
		else
			return t.addField(label, name, options, fieldOptions);
	}

	/// ditto
	override void setValue(string field, string value) {
		setValue(field, value, true);
	}

	override void setValue(string name, string[] variable) {
		assert(0, "not implemented FIXME");
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
	/++
		Returns the form's contents in application/x-www-form-urlencoded format.

		Bugs:
			Doesn't handle repeated elements of the same name nor files.
	+/
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

			ret ~= encodeUriComponent(e.name) ~ "=" ~ encodeUriComponent(getValue(e.name));

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

/++
	Represents a HTML table. Has some convenience methods for working with tabular data.
+/
/// Group: implementations
class Table : Element {

	/// You can make this yourself but you'd generally get one of these object out of a html parse or [Element.make] call.
	this(Document _parentDocument) {
		super(_parentDocument);
		tagName = "table";
	}

	/++
		Creates an element with the given type and content. The argument can be an Element, Html, or other data which is converted to text with `to!string`

		The element is $(I not) appended to the table.
	+/
	Element th(T)(T t) {
		Element e;
		if(parentDocument !is null)
			e = parentDocument.createElement("th");
		else
			e = Element.make("th");
		static if(is(T == Html))
			e.innerHTML = t;
		else static if(is(T : Element))
			e.appendChild(t);
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
		else static if(is(T : Element))
			e.appendChild(t);
		else
			e.innerText = to!string(t);
		return e;
	}

	/++
		Passes each argument to the [th] method for `appendHeaderRow` or [td] method for the others, appends them all to the `<tbody>` element for `appendRow`, `<thead>` element for `appendHeaderRow`, or a `<tfoot>` element for `appendFooterRow`, and ensures it is appended it to the table.
	+/
	Element appendHeaderRow(T...)(T t) {
		return appendRowInternal("th", "thead", t);
	}

	/// ditto
	Element appendFooterRow(T...)(T t) {
		return appendRowInternal("td", "tfoot", t);
	}

	/// ditto
	Element appendRow(T...)(T t) {
		return appendRowInternal("td", "tbody", t);
	}

	/++
		Takes each argument as a class name and calls [Element.addClass] for each element in the column associated with that index.

		Please note this does not use the html `<col>` element.
	+/
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

	/// Returns the `<caption>` element of the table, creating one if it isn't there.
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

	/// Returns or sets the text inside the `<caption>` element, creating that element if it isnt' there.
	@property string caption() {
		return captionElement().innerText;
	}

	/// ditto
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
	do {
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

	/// Gets and sets the row/colspan attributes as integers
	@property int rowspan() const {
		int ret = 1;
		auto it = getAttribute("rowspan");
		if(it.length)
			ret = to!int(it);
		return ret;
	}

	/// ditto
	@property int colspan() const {
		int ret = 1;
		auto it = getAttribute("colspan");
		if(it.length)
			ret = to!int(it);
		return ret;
	}

	/// ditto
	@property int rowspan(int i) {
		setAttribute("rowspan", to!string(i));
		return i;
	}

	/// ditto
	@property int colspan(int i) {
		setAttribute("colspan", to!string(i));
		return i;
	}

}


/// This is thrown on parse errors.
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
	"area","base","br","col","hr","img","input","link","meta","param",

	// html 5
	"embed","source","track","wbr"
];

private immutable static string[] htmlRawSourceElements = [
	"script", "style"
];

private immutable static string[] htmlInlineElements = [
	"span", "strong", "em", "b", "i", "a"
];


static import std.conv;

/// helper function for decoding html entities
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
		else if (q >= 'A' && q <= 'F')
			v = q - 'A' + 10;
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
		    "~=", "*=", "|=", "^=", "$=", "!=",
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

	/// Parts of the CSS selector implementation
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

	/// ditto
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
		/// Returns true if the given element matches this part
		bool matchElement(Element e, Element scopeElementNow = null) {
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
			if(scopeElement) {
				if(e !is scopeElementNow)
					return false;
			}
			if(emptyElement) {
				if(e.isEmpty())
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
	/// ditto
	Element[] getElementsBySelectorParts(Element start, SelectorPart[] parts, Element scopeElementNow = null) {
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
					if(part.matchElement(e, scopeElementNow)) {
						ret ~= getElementsBySelectorParts(e, parts[1..$], scopeElementNow);
					}
				}
			break;
			case 1: // children
				foreach(e; start.childNodes) {
					if(part.matchElement(e, scopeElementNow)) {
						ret ~= getElementsBySelectorParts(e, parts[1..$], scopeElementNow);
					}
				}
			break;
			case 2: // next-sibling
				auto e = start.nextSibling("*");
				if(part.matchElement(e, scopeElementNow))
					ret ~= getElementsBySelectorParts(e, parts[1..$], scopeElementNow);
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
						if(part.matchElement(e, scopeElementNow))
							ret ~= getElementsBySelectorParts(e, parts[1..$], scopeElementNow);
					}
				}
			break;
			case 4: // immediate parent node, an extension of mine to walk back up the tree
				auto e = start.parentNode;
				if(part.matchElement(e, scopeElementNow)) {
					ret ~= getElementsBySelectorParts(e, parts[1..$], scopeElementNow);
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
		Element[] getMatchingElements(Element start, Element relativeTo = null) {
			Element[] ret;
			foreach(component; components)
				ret ~= getElementsBySelectorParts(start, component.parts, relativeTo);
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
		Element[] getElements(Element start, Element relativeTo = null) {
			return removeDuplicates(getElementsBySelectorParts(start, parts, relativeTo));
		}

		// USEFUL (but not implemented)
		/// If relativeTo == null, it assumes the root of the parent document.
		bool matchElement(Element e, Element relativeTo = null) {
			if(e is null) return false;
			Element where = e;
			int lastSeparation = -1;

			auto lparts = parts;

			if(parts.length && parts[0].separation > 0) {
				throw new Exception("invalid selector");
			/+
				// if it starts with a non-trivial separator, inject
				// a "*" matcher to act as a root. for cases like document.querySelector("> body")
				// which implies html

				// however, if it is a child-matching selector and there are no children,
				// bail out early as it obviously cannot match.
				bool hasNonTextChildren = false;
				foreach(c; e.children)
					if(c.nodeType != 3) {
						hasNonTextChildren = true;
						break;
					}
				if(!hasNonTextChildren)
					return false;

				// there is probably a MUCH better way to do this.
				auto dummy = SelectorPart.init;
				dummy.tagNameFilter = "*";
				dummy.separation = 0;
				lparts = dummy ~ lparts;
			+/
			}

			foreach(part; retro(lparts)) {

				 // writeln("matching ", where, " with ", part, " via ", lastSeparation);
				 // writeln(parts);

				if(lastSeparation == -1) {
					if(!part.matchElement(where, relativeTo))
						return false;
				} else if(lastSeparation == 0) { // generic parent
					// need to go up the whole chain
					where = where.parentNode;

					while(where !is null) {
						if(part.matchElement(where, relativeTo))
							break;

						if(where is relativeTo)
							return false;

						where = where.parentNode;
					}

					if(where is null)
						return false;
				} else if(lastSeparation == 1) { // the > operator
					where = where.parentNode;

					if(!part.matchElement(where, relativeTo))
						return false;
				} else if(lastSeparation == 2) { // the + operator
				//writeln("WHERE", where, " ", part);
					where = where.previousSibling("*");

					if(!part.matchElement(where, relativeTo))
						return false;
				} else if(lastSeparation == 3) { // the ~ operator
					where = where.previousSibling("*");
					while(where !is null) {
						if(part.matchElement(where, relativeTo))
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

				/*
					/+
					I commented this to magically make unittest pass and I think the reason it works
					when commented is that I inject a :scope iff there's a selector at top level now
					and if not, it follows the (frankly stupid) w3c standard behavior at arbitrary id
					asduiwh . but me injecting the :scope also acts as a terminating condition.

					tbh this prolly needs like a trillion more tests.
					+/
				if(where is relativeTo)
					return false; // at end of line, if we aren't done by now, the match fails
				*/
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
								import arsd.core;
								throw ArsdException!"CSS Selector Problem"(token, tokens, cast(int) state);
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
						case "lang":
							state = State.SkippingFunctionalSelector;
						continue;
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
						case "nth-last-child":
							// FIXME
							//current.nthLastOfType ~= ParsedNth(readFunctionalSelector());
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

/++
	This delegate is called if you call [Element.computedStyle] to attach an object to the element
	that holds stylesheet information. You can rebind it to something else to return a subclass
	if you want to hold more per-element extension data than the normal computed style object holds
	(e.g. layout info as well).

	The default is `return new CssStyle(null, element.style);`

	History:
		Added September 13, 2024 (dub v11.6)
+/
CssStyle function(Element e) computedStyleFactory = &defaultComputedStyleFactory;

/// ditto
CssStyle defaultComputedStyleFactory(Element e) {
	return new CssStyle(null, e.style); // gives at least something to work with
}


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
			s.important = 2;
		} else {
			// SO. WRONG.
			foreach(ch; rule) {
				if(ch == '.')
					s.classes++;
				if(ch == '#')
					s.ids++;
				if(ch == ' ')
					s.tags++;
				if(ch == ',')
					break;
			}
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
			return setValue(name, value, Specificity(0x02000000) /* inline specificity */);
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
					property.specificity = newSpecificity;
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
				// assert(0, value);
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

private AttributesHolder aadup(const AttributesHolder arr) {
	AttributesHolder ret;
	foreach(k, v; arr)
		ret[k] = v;
	return ret;
}















// These MUST be sorted. See generatedomcases.d for a program to generate it if you need to add more than a few (otherwise maybe you can work it in yourself but yikes)

immutable string[] availableEntities =
["AElig", "AElig", "AMP", "AMP", "Aacute", "Aacute", "Abreve", "Abreve", "Acirc", "Acirc", "Acy", "Acy", "Afr", "Afr", "Agrave", "Agrave", "Alpha", "Alpha", "Amacr", "Amacr", "And", "And", "Aogon", "Aogon", "Aopf", "Aopf", "ApplyFunction", "ApplyFunction", "Aring", "Aring", "Ascr", "Ascr", "Assign", "Assign", "Atilde",
"Atilde", "Auml", "Auml", "Backslash", "Backslash", "Barv", "Barv", "Barwed", "Barwed", "Bcy", "Bcy", "Because", "Because", "Bernoullis", "Bernoullis", "Beta", "Beta", "Bfr", "Bfr", "Bopf", "Bopf", "Breve", "Breve", "Bscr", "Bscr", "Bumpeq", "Bumpeq", "CHcy", "CHcy", "COPY", "COPY", "Cacute", "Cacute", "Cap", "Cap", "CapitalDifferentialD",
"CapitalDifferentialD", "Cayleys", "Cayleys", "Ccaron", "Ccaron", "Ccedil", "Ccedil", "Ccirc", "Ccirc", "Cconint", "Cconint", "Cdot", "Cdot", "Cedilla", "Cedilla", "CenterDot", "CenterDot", "Cfr", "Cfr", "Chi", "Chi", "CircleDot", "CircleDot", "CircleMinus", "CircleMinus", "CirclePlus", "CirclePlus", "CircleTimes", "CircleTimes",
"ClockwiseContourIntegral", "ClockwiseContourIntegral", "CloseCurlyDoubleQuote", "CloseCurlyDoubleQuote", "CloseCurlyQuote", "CloseCurlyQuote", "Colon", "Colon", "Colone", "Colone", "Congruent", "Congruent", "Conint", "Conint", "ContourIntegral", "ContourIntegral", "Copf", "Copf", "Coproduct", "Coproduct", "CounterClockwiseContourIntegral",
"CounterClockwiseContourIntegral", "Cross", "Cross", "Cscr", "Cscr", "Cup", "Cup", "CupCap", "CupCap", "DD", "DD", "DDotrahd", "DDotrahd", "DJcy", "DJcy", "DScy", "DScy", "DZcy", "DZcy", "Dagger", "Dagger", "Darr", "Darr", "Dashv", "Dashv", "Dcaron", "Dcaron", "Dcy", "Dcy", "Del", "Del", "Delta", "Delta", "Dfr", "Dfr",
"DiacriticalAcute", "DiacriticalAcute", "DiacriticalDot", "DiacriticalDot", "DiacriticalDoubleAcute", "DiacriticalDoubleAcute", "DiacriticalGrave", "DiacriticalGrave", "DiacriticalTilde", "DiacriticalTilde", "Diamond", "Diamond", "DifferentialD", "DifferentialD", "Dopf", "Dopf", "Dot", "Dot", "DotDot", "DotDot", "DotEqual",
"DotEqual", "DoubleContourIntegral", "DoubleContourIntegral", "DoubleDot", "DoubleDot", "DoubleDownArrow", "DoubleDownArrow", "DoubleLeftArrow", "DoubleLeftArrow", "DoubleLeftRightArrow", "DoubleLeftRightArrow", "DoubleLeftTee", "DoubleLeftTee", "DoubleLongLeftArrow", "DoubleLongLeftArrow", "DoubleLongLeftRightArrow",
"DoubleLongLeftRightArrow", "DoubleLongRightArrow", "DoubleLongRightArrow", "DoubleRightArrow", "DoubleRightArrow", "DoubleRightTee", "DoubleRightTee", "DoubleUpArrow", "DoubleUpArrow", "DoubleUpDownArrow", "DoubleUpDownArrow", "DoubleVerticalBar", "DoubleVerticalBar", "DownArrow", "DownArrow", "DownArrowBar", "DownArrowBar",
"DownArrowUpArrow", "DownArrowUpArrow", "DownBreve", "DownBreve", "DownLeftRightVector", "DownLeftRightVector", "DownLeftTeeVector", "DownLeftTeeVector", "DownLeftVector", "DownLeftVector", "DownLeftVectorBar", "DownLeftVectorBar", "DownRightTeeVector", "DownRightTeeVector", "DownRightVector", "DownRightVector", "DownRightVectorBar",
"DownRightVectorBar", "DownTee", "DownTee", "DownTeeArrow", "DownTeeArrow", "Downarrow", "Downarrow", "Dscr", "Dscr", "Dstrok", "Dstrok", "ENG", "ENG", "ETH", "ETH", "Eacute", "Eacute", "Ecaron", "Ecaron", "Ecirc", "Ecirc", "Ecy", "Ecy", "Edot", "Edot", "Efr", "Efr", "Egrave", "Egrave", "Element", "Element", "Emacr", "Emacr",
"EmptySmallSquare", "EmptySmallSquare", "EmptyVerySmallSquare", "EmptyVerySmallSquare", "Eogon", "Eogon", "Eopf", "Eopf", "Epsilon", "Epsilon", "Equal", "Equal", "EqualTilde", "EqualTilde", "Equilibrium", "Equilibrium", "Escr", "Escr", "Esim", "Esim", "Eta", "Eta", "Euml", "Euml", "Exists", "Exists", "ExponentialE", "ExponentialE",
"Fcy", "Fcy", "Ffr", "Ffr", "FilledSmallSquare", "FilledSmallSquare", "FilledVerySmallSquare", "FilledVerySmallSquare", "Fopf", "Fopf", "ForAll", "ForAll", "Fouriertrf", "Fouriertrf", "Fscr", "Fscr", "GJcy", "GJcy", "GT", "GT", "Gamma", "Gamma", "Gammad", "Gammad", "Gbreve", "Gbreve", "Gcedil", "Gcedil", "Gcirc", "Gcirc",
"Gcy", "Gcy", "Gdot", "Gdot", "Gfr", "Gfr", "Gg", "Gg", "Gopf", "Gopf", "GreaterEqual", "GreaterEqual", "GreaterEqualLess", "GreaterEqualLess", "GreaterFullEqual", "GreaterFullEqual", "GreaterGreater", "GreaterGreater", "GreaterLess", "GreaterLess", "GreaterSlantEqual", "GreaterSlantEqual", "GreaterTilde", "GreaterTilde",
"Gscr", "Gscr", "Gt", "Gt", "HARDcy", "HARDcy", "Hacek", "Hacek", "Hat", "Hat", "Hcirc", "Hcirc", "Hfr", "Hfr", "HilbertSpace", "HilbertSpace", "Hopf", "Hopf", "HorizontalLine", "HorizontalLine", "Hscr", "Hscr", "Hstrok", "Hstrok", "HumpDownHump", "HumpDownHump", "HumpEqual", "HumpEqual", "IEcy", "IEcy", "IJlig", "IJlig",
"IOcy", "IOcy", "Iacute", "Iacute", "Icirc", "Icirc", "Icy", "Icy", "Idot", "Idot", "Ifr", "Ifr", "Igrave", "Igrave", "Im", "Im", "Imacr", "Imacr", "ImaginaryI", "ImaginaryI", "Implies", "Implies", "Int", "Int", "Integral", "Integral", "Intersection", "Intersection", "InvisibleComma", "InvisibleComma", "InvisibleTimes",
"InvisibleTimes", "Iogon", "Iogon", "Iopf", "Iopf", "Iota", "Iota", "Iscr", "Iscr", "Itilde", "Itilde", "Iukcy", "Iukcy", "Iuml", "Iuml", "Jcirc", "Jcirc", "Jcy", "Jcy", "Jfr", "Jfr", "Jopf", "Jopf", "Jscr", "Jscr", "Jsercy", "Jsercy", "Jukcy", "Jukcy", "KHcy", "KHcy", "KJcy", "KJcy", "Kappa", "Kappa", "Kcedil", "Kcedil",
"Kcy", "Kcy", "Kfr", "Kfr", "Kopf", "Kopf", "Kscr", "Kscr", "LJcy", "LJcy", "LT", "LT", "Lacute", "Lacute", "Lambda", "Lambda", "Lang", "Lang", "Laplacetrf", "Laplacetrf", "Larr", "Larr", "Lcaron", "Lcaron", "Lcedil", "Lcedil", "Lcy", "Lcy", "LeftAngleBracket", "LeftAngleBracket", "LeftArrow", "LeftArrow", "LeftArrowBar",
"LeftArrowBar", "LeftArrowRightArrow", "LeftArrowRightArrow", "LeftCeiling", "LeftCeiling", "LeftDoubleBracket", "LeftDoubleBracket", "LeftDownTeeVector", "LeftDownTeeVector", "LeftDownVector", "LeftDownVector", "LeftDownVectorBar", "LeftDownVectorBar", "LeftFloor", "LeftFloor", "LeftRightArrow", "LeftRightArrow", "LeftRightVector",
"LeftRightVector", "LeftTee", "LeftTee", "LeftTeeArrow", "LeftTeeArrow", "LeftTeeVector", "LeftTeeVector", "LeftTriangle", "LeftTriangle", "LeftTriangleBar", "LeftTriangleBar", "LeftTriangleEqual", "LeftTriangleEqual", "LeftUpDownVector", "LeftUpDownVector", "LeftUpTeeVector", "LeftUpTeeVector", "LeftUpVector", "LeftUpVector",
"LeftUpVectorBar", "LeftUpVectorBar", "LeftVector", "LeftVector", "LeftVectorBar", "LeftVectorBar", "Leftarrow", "Leftarrow", "Leftrightarrow", "Leftrightarrow", "LessEqualGreater", "LessEqualGreater", "LessFullEqual", "LessFullEqual", "LessGreater", "LessGreater", "LessLess", "LessLess", "LessSlantEqual", "LessSlantEqual",
"LessTilde", "LessTilde", "Lfr", "Lfr", "Ll", "Ll", "Lleftarrow", "Lleftarrow", "Lmidot", "Lmidot", "LongLeftArrow", "LongLeftArrow", "LongLeftRightArrow", "LongLeftRightArrow", "LongRightArrow", "LongRightArrow", "Longleftarrow", "Longleftarrow", "Longleftrightarrow", "Longleftrightarrow", "Longrightarrow", "Longrightarrow",
"Lopf", "Lopf", "LowerLeftArrow", "LowerLeftArrow", "LowerRightArrow", "LowerRightArrow", "Lscr", "Lscr", "Lsh", "Lsh", "Lstrok", "Lstrok", "Lt", "Lt", "Map", "Map", "Mcy", "Mcy", "MediumSpace", "MediumSpace", "Mellintrf", "Mellintrf", "Mfr", "Mfr", "MinusPlus", "MinusPlus", "Mopf", "Mopf", "Mscr", "Mscr", "Mu", "Mu",
"NJcy", "NJcy", "Nacute", "Nacute", "Ncaron", "Ncaron", "Ncedil", "Ncedil", "Ncy", "Ncy", "NegativeMediumSpace", "NegativeMediumSpace", "NegativeThickSpace", "NegativeThickSpace", "NegativeThinSpace", "NegativeThinSpace", "NegativeVeryThinSpace", "NegativeVeryThinSpace", "NestedGreaterGreater", "NestedGreaterGreater",
"NestedLessLess", "NestedLessLess", "NewLine", "NewLine", "Nfr", "Nfr", "NoBreak", "NoBreak", "NonBreakingSpace", "NonBreakingSpace", "Nopf", "Nopf", "Not", "Not", "NotCongruent", "NotCongruent", "NotCupCap", "NotCupCap", "NotDoubleVerticalBar", "NotDoubleVerticalBar", "NotElement", "NotElement", "NotEqual", "NotEqual",
"NotExists", "NotExists", "NotGreater", "NotGreater", "NotGreaterEqual", "NotGreaterEqual", "NotGreaterLess", "NotGreaterLess", "NotGreaterTilde", "NotGreaterTilde", "NotLeftTriangle", "NotLeftTriangle", "NotLeftTriangleEqual", "NotLeftTriangleEqual", "NotLess", "NotLess", "NotLessEqual", "NotLessEqual", "NotLessGreater",
"NotLessGreater", "NotLessTilde", "NotLessTilde", "NotPrecedes", "NotPrecedes", "NotPrecedesSlantEqual", "NotPrecedesSlantEqual", "NotReverseElement", "NotReverseElement", "NotRightTriangle", "NotRightTriangle", "NotRightTriangleEqual", "NotRightTriangleEqual", "NotSquareSubsetEqual", "NotSquareSubsetEqual", "NotSquareSupersetEqual",
"NotSquareSupersetEqual", "NotSubsetEqual", "NotSubsetEqual", "NotSucceeds", "NotSucceeds", "NotSucceedsSlantEqual", "NotSucceedsSlantEqual", "NotSupersetEqual", "NotSupersetEqual", "NotTilde", "NotTilde", "NotTildeEqual", "NotTildeEqual", "NotTildeFullEqual", "NotTildeFullEqual", "NotTildeTilde", "NotTildeTilde", "NotVerticalBar",
"NotVerticalBar", "Nscr", "Nscr", "Ntilde", "Ntilde", "Nu", "Nu", "OElig", "OElig", "Oacute", "Oacute", "Ocirc", "Ocirc", "Ocy", "Ocy", "Odblac", "Odblac", "Ofr", "Ofr", "Ograve", "Ograve", "Omacr", "Omacr", "Omega", "Omega", "Omicron", "Omicron", "Oopf", "Oopf", "OpenCurlyDoubleQuote", "OpenCurlyDoubleQuote", "OpenCurlyQuote",
"OpenCurlyQuote", "Or", "Or", "Oscr", "Oscr", "Oslash", "Oslash", "Otilde", "Otilde", "Otimes", "Otimes", "Ouml", "Ouml", "OverBar", "OverBar", "OverBrace", "OverBrace", "OverBracket", "OverBracket", "OverParenthesis", "OverParenthesis", "PartialD", "PartialD", "Pcy", "Pcy", "Pfr", "Pfr", "Phi", "Phi", "Pi", "Pi", "PlusMinus",
"PlusMinus", "Poincareplane", "Poincareplane", "Popf", "Popf", "Pr", "Pr", "Precedes", "Precedes", "PrecedesEqual", "PrecedesEqual", "PrecedesSlantEqual", "PrecedesSlantEqual", "PrecedesTilde", "PrecedesTilde", "Prime", "Prime", "Product", "Product", "Proportion", "Proportion", "Proportional", "Proportional", "Pscr", "Pscr",
"Psi", "Psi", "QUOT", "QUOT", "Qfr", "Qfr", "Qopf", "Qopf", "Qscr", "Qscr", "RBarr", "RBarr", "REG", "REG", "Racute", "Racute", "Rang", "Rang", "Rarr", "Rarr", "Rarrtl", "Rarrtl", "Rcaron", "Rcaron", "Rcedil", "Rcedil", "Rcy", "Rcy", "Re", "Re", "ReverseElement", "ReverseElement", "ReverseEquilibrium", "ReverseEquilibrium",
"ReverseUpEquilibrium", "ReverseUpEquilibrium", "Rfr", "Rfr", "Rho", "Rho", "RightAngleBracket", "RightAngleBracket", "RightArrow", "RightArrow", "RightArrowBar", "RightArrowBar", "RightArrowLeftArrow", "RightArrowLeftArrow", "RightCeiling", "RightCeiling", "RightDoubleBracket", "RightDoubleBracket", "RightDownTeeVector",
"RightDownTeeVector", "RightDownVector", "RightDownVector", "RightDownVectorBar", "RightDownVectorBar", "RightFloor", "RightFloor", "RightTee", "RightTee", "RightTeeArrow", "RightTeeArrow", "RightTeeVector", "RightTeeVector", "RightTriangle", "RightTriangle", "RightTriangleBar", "RightTriangleBar", "RightTriangleEqual",
"RightTriangleEqual", "RightUpDownVector", "RightUpDownVector", "RightUpTeeVector", "RightUpTeeVector", "RightUpVector", "RightUpVector", "RightUpVectorBar", "RightUpVectorBar", "RightVector", "RightVector", "RightVectorBar", "RightVectorBar", "Rightarrow", "Rightarrow", "Ropf", "Ropf", "RoundImplies", "RoundImplies",
"Rrightarrow", "Rrightarrow", "Rscr", "Rscr", "Rsh", "Rsh", "RuleDelayed", "RuleDelayed", "SHCHcy", "SHCHcy", "SHcy", "SHcy", "SOFTcy", "SOFTcy", "Sacute", "Sacute", "Sc", "Sc", "Scaron", "Scaron", "Scedil", "Scedil", "Scirc", "Scirc", "Scy", "Scy", "Sfr", "Sfr", "ShortDownArrow", "ShortDownArrow", "ShortLeftArrow", "ShortLeftArrow",
"ShortRightArrow", "ShortRightArrow", "ShortUpArrow", "ShortUpArrow", "Sigma", "Sigma", "SmallCircle", "SmallCircle", "Sopf", "Sopf", "Sqrt", "Sqrt", "Square", "Square", "SquareIntersection", "SquareIntersection", "SquareSubset", "SquareSubset", "SquareSubsetEqual", "SquareSubsetEqual", "SquareSuperset", "SquareSuperset",
"SquareSupersetEqual", "SquareSupersetEqual", "SquareUnion", "SquareUnion", "Sscr", "Sscr", "Star", "Star", "Sub", "Sub", "Subset", "Subset", "SubsetEqual", "SubsetEqual", "Succeeds", "Succeeds", "SucceedsEqual", "SucceedsEqual", "SucceedsSlantEqual", "SucceedsSlantEqual", "SucceedsTilde", "SucceedsTilde", "SuchThat",
"SuchThat", "Sum", "Sum", "Sup", "Sup", "Superset", "Superset", "SupersetEqual", "SupersetEqual", "Supset", "Supset", "THORN", "THORN", "TRADE", "TRADE", "TSHcy", "TSHcy", "TScy", "TScy", "Tab", "Tab", "Tau", "Tau", "Tcaron", "Tcaron", "Tcedil", "Tcedil", "Tcy", "Tcy", "Tfr", "Tfr", "Therefore", "Therefore", "Theta", "Theta",
"ThinSpace", "ThinSpace", "Tilde", "Tilde", "TildeEqual", "TildeEqual", "TildeFullEqual", "TildeFullEqual", "TildeTilde", "TildeTilde", "Topf", "Topf", "TripleDot", "TripleDot", "Tscr", "Tscr", "Tstrok", "Tstrok", "Uacute", "Uacute", "Uarr", "Uarr", "Uarrocir", "Uarrocir", "Ubrcy", "Ubrcy", "Ubreve", "Ubreve", "Ucirc",
"Ucirc", "Ucy", "Ucy", "Udblac", "Udblac", "Ufr", "Ufr", "Ugrave", "Ugrave", "Umacr", "Umacr", "UnderBar", "UnderBar", "UnderBrace", "UnderBrace", "UnderBracket", "UnderBracket", "UnderParenthesis", "UnderParenthesis", "Union", "Union", "UnionPlus", "UnionPlus", "Uogon", "Uogon", "Uopf", "Uopf", "UpArrow", "UpArrow", "UpArrowBar",
"UpArrowBar", "UpArrowDownArrow", "UpArrowDownArrow", "UpDownArrow", "UpDownArrow", "UpEquilibrium", "UpEquilibrium", "UpTee", "UpTee", "UpTeeArrow", "UpTeeArrow", "Uparrow", "Uparrow", "Updownarrow", "Updownarrow", "UpperLeftArrow", "UpperLeftArrow", "UpperRightArrow", "UpperRightArrow", "Upsi", "Upsi", "Upsilon", "Upsilon",
"Uring", "Uring", "Uscr", "Uscr", "Utilde", "Utilde", "Uuml", "Uuml", "VDash", "VDash", "Vbar", "Vbar", "Vcy", "Vcy", "Vdash", "Vdash", "Vdashl", "Vdashl", "Vee", "Vee", "Verbar", "Verbar", "Vert", "Vert", "VerticalBar", "VerticalBar", "VerticalLine", "VerticalLine", "VerticalSeparator", "VerticalSeparator", "VerticalTilde",
"VerticalTilde", "VeryThinSpace", "VeryThinSpace", "Vfr", "Vfr", "Vopf", "Vopf", "Vscr", "Vscr", "Vvdash", "Vvdash", "Wcirc", "Wcirc", "Wedge", "Wedge", "Wfr", "Wfr", "Wopf", "Wopf", "Wscr", "Wscr", "Xfr", "Xfr", "Xi", "Xi", "Xopf", "Xopf", "Xscr", "Xscr", "YAcy", "YAcy", "YIcy", "YIcy", "YUcy", "YUcy", "Yacute", "Yacute",
"Ycirc", "Ycirc", "Ycy", "Ycy", "Yfr", "Yfr", "Yopf", "Yopf", "Yscr", "Yscr", "Yuml", "Yuml", "ZHcy", "ZHcy", "Zacute", "Zacute", "Zcaron", "Zcaron", "Zcy", "Zcy", "Zdot", "Zdot", "ZeroWidthSpace", "ZeroWidthSpace", "Zeta", "Zeta", "Zfr", "Zfr", "Zopf", "Zopf", "Zscr", "Zscr", "aacute", "aacute", "abreve", "abreve", "ac",
"ac", "acd", "acd", "acirc", "acirc", "acute", "acute", "acy", "acy", "aelig", "aelig", "af", "af", "afr", "afr", "agrave", "agrave", "alefsym", "alefsym", "aleph", "aleph", "alpha", "alpha", "amacr", "amacr", "amalg", "amalg", "and", "and", "andand", "andand", "andd", "andd", "andslope", "andslope", "andv", "andv", "ang",
"ang", "ange", "ange", "angle", "angle", "angmsd", "angmsd", "angmsdaa", "angmsdaa", "angmsdab", "angmsdab", "angmsdac", "angmsdac", "angmsdad", "angmsdad", "angmsdae", "angmsdae", "angmsdaf", "angmsdaf", "angmsdag", "angmsdag", "angmsdah", "angmsdah", "angrt", "angrt", "angrtvb", "angrtvb", "angrtvbd", "angrtvbd", "angsph",
"angsph", "angst", "angst", "angzarr", "angzarr", "aogon", "aogon", "aopf", "aopf", "ap", "ap", "apE", "apE", "apacir", "apacir", "ape", "ape", "apid", "apid", "approx", "approx", "approxeq", "approxeq", "aring", "aring", "ascr", "ascr", "ast", "ast", "asymp", "asymp", "asympeq", "asympeq", "atilde", "atilde", "auml",
"auml", "awconint", "awconint", "awint", "awint", "bNot", "bNot", "backcong", "backcong", "backepsilon", "backepsilon", "backprime", "backprime", "backsim", "backsim", "backsimeq", "backsimeq", "barvee", "barvee", "barwed", "barwed", "barwedge", "barwedge", "bbrk", "bbrk", "bbrktbrk", "bbrktbrk", "bcong", "bcong", "bcy",
"bcy", "bdquo", "bdquo", "becaus", "becaus", "because", "because", "bemptyv", "bemptyv", "bepsi", "bepsi", "bernou", "bernou", "beta", "beta", "beth", "beth", "between", "between", "bfr", "bfr", "bigcap", "bigcap", "bigcirc", "bigcirc", "bigcup", "bigcup", "bigodot", "bigodot", "bigoplus", "bigoplus", "bigotimes", "bigotimes",
"bigsqcup", "bigsqcup", "bigstar", "bigstar", "bigtriangledown", "bigtriangledown", "bigtriangleup", "bigtriangleup", "biguplus", "biguplus", "bigvee", "bigvee", "bigwedge", "bigwedge", "bkarow", "bkarow", "blacklozenge", "blacklozenge", "blacksquare", "blacksquare", "blacktriangle", "blacktriangle", "blacktriangledown",
"blacktriangledown", "blacktriangleleft", "blacktriangleleft", "blacktriangleright", "blacktriangleright", "blank", "blank", "blk12", "blk12", "blk14", "blk14", "blk34", "blk34", "block", "block", "bnot", "bnot", "bopf", "bopf", "bot", "bot", "bottom", "bottom", "bowtie", "bowtie", "boxDL", "boxDL", "boxDR", "boxDR", "boxDl",
"boxDl", "boxDr", "boxDr", "boxH", "boxH", "boxHD", "boxHD", "boxHU", "boxHU", "boxHd", "boxHd", "boxHu", "boxHu", "boxUL", "boxUL", "boxUR", "boxUR", "boxUl", "boxUl", "boxUr", "boxUr", "boxV", "boxV", "boxVH", "boxVH", "boxVL", "boxVL", "boxVR", "boxVR", "boxVh", "boxVh", "boxVl", "boxVl", "boxVr", "boxVr", "boxbox",
"boxbox", "boxdL", "boxdL", "boxdR", "boxdR", "boxdl", "boxdl", "boxdr", "boxdr", "boxh", "boxh", "boxhD", "boxhD", "boxhU", "boxhU", "boxhd", "boxhd", "boxhu", "boxhu", "boxminus", "boxminus", "boxplus", "boxplus", "boxtimes", "boxtimes", "boxuL", "boxuL", "boxuR", "boxuR", "boxul", "boxul", "boxur", "boxur", "boxv",
"boxv", "boxvH", "boxvH", "boxvL", "boxvL", "boxvR", "boxvR", "boxvh", "boxvh", "boxvl", "boxvl", "boxvr", "boxvr", "bprime", "bprime", "breve", "breve", "brvbar", "brvbar", "bscr", "bscr", "bsemi", "bsemi", "bsim", "bsim", "bsime", "bsime", "bsol", "bsol", "bsolb", "bsolb", "bsolhsub", "bsolhsub", "bull", "bull", "bullet",
"bullet", "bump", "bump", "bumpE", "bumpE", "bumpe", "bumpe", "bumpeq", "bumpeq", "cacute", "cacute", "cap", "cap", "capand", "capand", "capbrcup", "capbrcup", "capcap", "capcap", "capcup", "capcup", "capdot", "capdot", "caret", "caret", "caron", "caron", "ccaps", "ccaps", "ccaron", "ccaron", "ccedil", "ccedil", "ccirc",
"ccirc", "ccups", "ccups", "ccupssm", "ccupssm", "cdot", "cdot", "cedil", "cedil", "cemptyv", "cemptyv", "cent", "cent", "centerdot", "centerdot", "cfr", "cfr", "chcy", "chcy", "check", "check", "checkmark", "checkmark", "chi", "chi", "cir", "cir", "cirE", "cirE", "circ", "circ", "circeq", "circeq", "circlearrowleft",
"circlearrowleft", "circlearrowright", "circlearrowright", "circledR", "circledR", "circledS", "circledS", "circledast", "circledast", "circledcirc", "circledcirc", "circleddash", "circleddash", "cire", "cire", "cirfnint", "cirfnint", "cirmid", "cirmid", "cirscir", "cirscir", "clubs", "clubs", "clubsuit", "clubsuit", "colon",
"colon", "colone", "colone", "coloneq", "coloneq", "comma", "comma", "commat", "commat", "comp", "comp", "compfn", "compfn", "complement", "complement", "complexes", "complexes", "cong", "cong", "congdot", "congdot", "conint", "conint", "copf", "copf", "coprod", "coprod", "copy", "copy", "copysr", "copysr", "crarr", "crarr",
"cross", "cross", "cscr", "cscr", "csub", "csub", "csube", "csube", "csup", "csup", "csupe", "csupe", "ctdot", "ctdot", "cudarrl", "cudarrl", "cudarrr", "cudarrr", "cuepr", "cuepr", "cuesc", "cuesc", "cularr", "cularr", "cularrp", "cularrp", "cup", "cup", "cupbrcap", "cupbrcap", "cupcap", "cupcap", "cupcup", "cupcup",
"cupdot", "cupdot", "cupor", "cupor", "curarr", "curarr", "curarrm", "curarrm", "curlyeqprec", "curlyeqprec", "curlyeqsucc", "curlyeqsucc", "curlyvee", "curlyvee", "curlywedge", "curlywedge", "curren", "curren", "curvearrowleft", "curvearrowleft", "curvearrowright", "curvearrowright", "cuvee", "cuvee", "cuwed", "cuwed",
"cwconint", "cwconint", "cwint", "cwint", "cylcty", "cylcty", "dArr", "dArr", "dHar", "dHar", "dagger", "dagger", "daleth", "daleth", "darr", "darr", "dash", "dash", "dashv", "dashv", "dbkarow", "dbkarow", "dblac", "dblac", "dcaron", "dcaron", "dcy", "dcy", "dd", "dd", "ddagger", "ddagger", "ddarr", "ddarr", "ddotseq",
"ddotseq", "deg", "deg", "delta", "delta", "demptyv", "demptyv", "dfisht", "dfisht", "dfr", "dfr", "dharl", "dharl", "dharr", "dharr", "diam", "diam", "diamond", "diamond", "diamondsuit", "diamondsuit", "diams", "diams", "die", "die", "digamma", "digamma", "disin", "disin", "div", "div", "divide", "divide", "divideontimes",
"divideontimes", "divonx", "divonx", "djcy", "djcy", "dlcorn", "dlcorn", "dlcrop", "dlcrop", "dollar", "dollar", "dopf", "dopf", "dot", "dot", "doteq", "doteq", "doteqdot", "doteqdot", "dotminus", "dotminus", "dotplus", "dotplus", "dotsquare", "dotsquare", "doublebarwedge", "doublebarwedge", "downarrow", "downarrow", "downdownarrows",
"downdownarrows", "downharpoonleft", "downharpoonleft", "downharpoonright", "downharpoonright", "drbkarow", "drbkarow", "drcorn", "drcorn", "drcrop", "drcrop", "dscr", "dscr", "dscy", "dscy", "dsol", "dsol", "dstrok", "dstrok", "dtdot", "dtdot", "dtri", "dtri", "dtrif", "dtrif", "duarr", "duarr", "duhar", "duhar", "dwangle",
"dwangle", "dzcy", "dzcy", "dzigrarr", "dzigrarr", "eDDot", "eDDot", "eDot", "eDot", "eacute", "eacute", "easter", "easter", "ecaron", "ecaron", "ecir", "ecir", "ecirc", "ecirc", "ecolon", "ecolon", "ecy", "ecy", "edot", "edot", "ee", "ee", "efDot", "efDot", "efr", "efr", "eg", "eg", "egrave", "egrave", "egs", "egs", "egsdot",
"egsdot", "el", "el", "elinters", "elinters", "ell", "ell", "els", "els", "elsdot", "elsdot", "emacr", "emacr", "empty", "empty", "emptyset", "emptyset", "emptyv", "emptyv", "emsp", "emsp", "emsp13", "emsp13", "emsp14", "emsp14", "eng", "eng", "ensp", "ensp", "eogon", "eogon", "eopf", "eopf", "epar", "epar", "eparsl",
"eparsl", "eplus", "eplus", "epsi", "epsi", "epsilon", "epsilon", "epsiv", "epsiv", "eqcirc", "eqcirc", "eqcolon", "eqcolon", "eqsim", "eqsim", "eqslantgtr", "eqslantgtr", "eqslantless", "eqslantless", "equals", "equals", "equest", "equest", "equiv", "equiv", "equivDD", "equivDD", "eqvparsl", "eqvparsl", "erDot", "erDot",
"erarr", "erarr", "escr", "escr", "esdot", "esdot", "esim", "esim", "eta", "eta", "eth", "eth", "euml", "euml", "euro", "euro", "excl", "excl", "exist", "exist", "expectation", "expectation", "exponentiale", "exponentiale", "fallingdotseq", "fallingdotseq", "fcy", "fcy", "female", "female", "ffilig", "ffilig", "fflig",
"fflig", "ffllig", "ffllig", "ffr", "ffr", "filig", "filig", "flat", "flat", "fllig", "fllig", "fltns", "fltns", "fnof", "fnof", "fopf", "fopf", "forall", "forall", "fork", "fork", "forkv", "forkv", "fpartint", "fpartint", "frac12", "frac12", "frac13", "frac13", "frac14", "frac14", "frac15", "frac15", "frac16", "frac16",
"frac18", "frac18", "frac23", "frac23", "frac25", "frac25", "frac34", "frac34", "frac35", "frac35", "frac38", "frac38", "frac45", "frac45", "frac56", "frac56", "frac58", "frac58", "frac78", "frac78", "frasl", "frasl", "frown", "frown", "fscr", "fscr", "gE", "gE", "gEl", "gEl", "gacute", "gacute", "gamma", "gamma", "gammad",
"gammad", "gap", "gap", "gbreve", "gbreve", "gcirc", "gcirc", "gcy", "gcy", "gdot", "gdot", "ge", "ge", "gel", "gel", "geq", "geq", "geqq", "geqq", "geqslant", "geqslant", "ges", "ges", "gescc", "gescc", "gesdot", "gesdot", "gesdoto", "gesdoto", "gesdotol", "gesdotol", "gesles", "gesles", "gfr", "gfr", "gg", "gg", "ggg",
"ggg", "gimel", "gimel", "gjcy", "gjcy", "gl", "gl", "glE", "glE", "gla", "gla", "glj", "glj", "gnE", "gnE", "gnap", "gnap", "gnapprox", "gnapprox", "gne", "gne", "gneq", "gneq", "gneqq", "gneqq", "gnsim", "gnsim", "gopf", "gopf", "grave", "grave", "gscr", "gscr", "gsim", "gsim", "gsime", "gsime", "gsiml", "gsiml", "gtcc",
"gtcc", "gtcir", "gtcir", "gtdot", "gtdot", "gtlPar", "gtlPar", "gtquest", "gtquest", "gtrapprox", "gtrapprox", "gtrarr", "gtrarr", "gtrdot", "gtrdot", "gtreqless", "gtreqless", "gtreqqless", "gtreqqless", "gtrless", "gtrless", "gtrsim", "gtrsim", "hArr", "hArr", "hairsp", "hairsp", "half", "half", "hamilt", "hamilt",
"hardcy", "hardcy", "harr", "harr", "harrcir", "harrcir", "harrw", "harrw", "hbar", "hbar", "hcirc", "hcirc", "hearts", "hearts", "heartsuit", "heartsuit", "hellip", "hellip", "hercon", "hercon", "hfr", "hfr", "hksearow", "hksearow", "hkswarow", "hkswarow", "hoarr", "hoarr", "homtht", "homtht", "hookleftarrow", "hookleftarrow",
"hookrightarrow", "hookrightarrow", "hopf", "hopf", "horbar", "horbar", "hscr", "hscr", "hslash", "hslash", "hstrok", "hstrok", "hybull", "hybull", "hyphen", "hyphen", "iacute", "iacute", "ic", "ic", "icirc", "icirc", "icy", "icy", "iecy", "iecy", "iexcl", "iexcl", "iff", "iff", "ifr", "ifr", "igrave", "igrave", "ii",
"ii", "iiiint", "iiiint", "iiint", "iiint", "iinfin", "iinfin", "iiota", "iiota", "ijlig", "ijlig", "imacr", "imacr", "image", "image", "imagline", "imagline", "imagpart", "imagpart", "imath", "imath", "imof", "imof", "imped", "imped", "in", "in", "incare", "incare", "infin", "infin", "infintie", "infintie", "inodot",
"inodot", "int", "int", "intcal", "intcal", "integers", "integers", "intercal", "intercal", "intlarhk", "intlarhk", "intprod", "intprod", "iocy", "iocy", "iogon", "iogon", "iopf", "iopf", "iota", "iota", "iprod", "iprod", "iquest", "iquest", "iscr", "iscr", "isin", "isin", "isinE", "isinE", "isindot", "isindot", "isins",
"isins", "isinsv", "isinsv", "isinv", "isinv", "it", "it", "itilde", "itilde", "iukcy", "iukcy", "iuml", "iuml", "jcirc", "jcirc", "jcy", "jcy", "jfr", "jfr", "jmath", "jmath", "jopf", "jopf", "jscr", "jscr", "jsercy", "jsercy", "jukcy", "jukcy", "kappa", "kappa", "kappav", "kappav", "kcedil", "kcedil", "kcy", "kcy", "kfr",
"kfr", "kgreen", "kgreen", "khcy", "khcy", "kjcy", "kjcy", "kopf", "kopf", "kscr", "kscr", "lAarr", "lAarr", "lArr", "lArr", "lAtail", "lAtail", "lBarr", "lBarr", "lE", "lE", "lEg", "lEg", "lHar", "lHar", "lacute", "lacute", "laemptyv", "laemptyv", "lagran", "lagran", "lambda", "lambda", "lang", "lang", "langd", "langd",
"langle", "langle", "lap", "lap", "laquo", "laquo", "larr", "larr", "larrb", "larrb", "larrbfs", "larrbfs", "larrfs", "larrfs", "larrhk", "larrhk", "larrlp", "larrlp", "larrpl", "larrpl", "larrsim", "larrsim", "larrtl", "larrtl", "lat", "lat", "latail", "latail", "late", "late", "lbarr", "lbarr", "lbbrk", "lbbrk", "lbrace",
"lbrace", "lbrack", "lbrack", "lbrke", "lbrke", "lbrksld", "lbrksld", "lbrkslu", "lbrkslu", "lcaron", "lcaron", "lcedil", "lcedil", "lceil", "lceil", "lcub", "lcub", "lcy", "lcy", "ldca", "ldca", "ldquo", "ldquo", "ldquor", "ldquor", "ldrdhar", "ldrdhar", "ldrushar", "ldrushar", "ldsh", "ldsh", "le", "le", "leftarrow",
"leftarrow", "leftarrowtail", "leftarrowtail", "leftharpoondown", "leftharpoondown", "leftharpoonup", "leftharpoonup", "leftleftarrows", "leftleftarrows", "leftrightarrow", "leftrightarrow", "leftrightarrows", "leftrightarrows", "leftrightharpoons", "leftrightharpoons", "leftrightsquigarrow", "leftrightsquigarrow", "leftthreetimes",
"leftthreetimes", "leg", "leg", "leq", "leq", "leqq", "leqq", "leqslant", "leqslant", "les", "les", "lescc", "lescc", "lesdot", "lesdot", "lesdoto", "lesdoto", "lesdotor", "lesdotor", "lesges", "lesges", "lessapprox", "lessapprox", "lessdot", "lessdot", "lesseqgtr", "lesseqgtr", "lesseqqgtr", "lesseqqgtr", "lessgtr", "lessgtr",
"lesssim", "lesssim", "lfisht", "lfisht", "lfloor", "lfloor", "lfr", "lfr", "lg", "lg", "lgE", "lgE", "lhard", "lhard", "lharu", "lharu", "lharul", "lharul", "lhblk", "lhblk", "ljcy", "ljcy", "ll", "ll", "llarr", "llarr", "llcorner", "llcorner", "llhard", "llhard", "lltri", "lltri", "lmidot", "lmidot", "lmoust", "lmoust",
"lmoustache", "lmoustache", "lnE", "lnE", "lnap", "lnap", "lnapprox", "lnapprox", "lne", "lne", "lneq", "lneq", "lneqq", "lneqq", "lnsim", "lnsim", "loang", "loang", "loarr", "loarr", "lobrk", "lobrk", "longleftarrow", "longleftarrow", "longleftrightarrow", "longleftrightarrow", "longmapsto", "longmapsto", "longrightarrow",
"longrightarrow", "looparrowleft", "looparrowleft", "looparrowright", "looparrowright", "lopar", "lopar", "lopf", "lopf", "loplus", "loplus", "lotimes", "lotimes", "lowast", "lowast", "lowbar", "lowbar", "loz", "loz", "lozenge", "lozenge", "lozf", "lozf", "lpar", "lpar", "lparlt", "lparlt", "lrarr", "lrarr", "lrcorner",
"lrcorner", "lrhar", "lrhar", "lrhard", "lrhard", "lrm", "lrm", "lrtri", "lrtri", "lsaquo", "lsaquo", "lscr", "lscr", "lsh", "lsh", "lsim", "lsim", "lsime", "lsime", "lsimg", "lsimg", "lsqb", "lsqb", "lsquo", "lsquo", "lsquor", "lsquor", "lstrok", "lstrok", "ltcc", "ltcc", "ltcir", "ltcir", "ltdot", "ltdot", "lthree",
"lthree", "ltimes", "ltimes", "ltlarr", "ltlarr", "ltquest", "ltquest", "ltrPar", "ltrPar", "ltri", "ltri", "ltrie", "ltrie", "ltrif", "ltrif", "lurdshar", "lurdshar", "luruhar", "luruhar", "mDDot", "mDDot", "macr", "macr", "male", "male", "malt", "malt", "maltese", "maltese", "map", "map", "mapsto", "mapsto", "mapstodown",
"mapstodown", "mapstoleft", "mapstoleft", "mapstoup", "mapstoup", "marker", "marker", "mcomma", "mcomma", "mcy", "mcy", "mdash", "mdash", "measuredangle", "measuredangle", "mfr", "mfr", "mho", "mho", "micro", "micro", "mid", "mid", "midast", "midast", "midcir", "midcir", "middot", "middot", "minus", "minus", "minusb",
"minusb", "minusd", "minusd", "minusdu", "minusdu", "mlcp", "mlcp", "mldr", "mldr", "mnplus", "mnplus", "models", "models", "mopf", "mopf", "mp", "mp", "mscr", "mscr", "mstpos", "mstpos", "mu", "mu", "multimap", "multimap", "mumap", "mumap", "nLeftarrow", "nLeftarrow", "nLeftrightarrow", "nLeftrightarrow", "nRightarrow",
"nRightarrow", "nVDash", "nVDash", "nVdash", "nVdash", "nabla", "nabla", "nacute", "nacute", "nap", "nap", "napos", "napos", "napprox", "napprox", "natur", "natur", "natural", "natural", "naturals", "naturals", "nbsp", "nbsp", "ncap", "ncap", "ncaron", "ncaron", "ncedil", "ncedil", "ncong", "ncong", "ncup", "ncup", "ncy",
"ncy", "ndash", "ndash", "ne", "ne", "neArr", "neArr", "nearhk", "nearhk", "nearr", "nearr", "nearrow", "nearrow", "nequiv", "nequiv", "nesear", "nesear", "nexist", "nexist", "nexists", "nexists", "nfr", "nfr", "nge", "nge", "ngeq", "ngeq", "ngsim", "ngsim", "ngt", "ngt", "ngtr", "ngtr", "nhArr", "nhArr", "nharr", "nharr",
"nhpar", "nhpar", "ni", "ni", "nis", "nis", "nisd", "nisd", "niv", "niv", "njcy", "njcy", "nlArr", "nlArr", "nlarr", "nlarr", "nldr", "nldr", "nle", "nle", "nleftarrow", "nleftarrow", "nleftrightarrow", "nleftrightarrow", "nleq", "nleq", "nless", "nless", "nlsim", "nlsim", "nlt", "nlt", "nltri", "nltri", "nltrie", "nltrie",
"nmid", "nmid", "nopf", "nopf", "not", "not", "notin", "notin", "notinva", "notinva", "notinvb", "notinvb", "notinvc", "notinvc", "notni", "notni", "notniva", "notniva", "notnivb", "notnivb", "notnivc", "notnivc", "npar", "npar", "nparallel", "nparallel", "npolint", "npolint", "npr", "npr", "nprcue", "nprcue", "nprec",
"nprec", "nrArr", "nrArr", "nrarr", "nrarr", "nrightarrow", "nrightarrow", "nrtri", "nrtri", "nrtrie", "nrtrie", "nsc", "nsc", "nsccue", "nsccue", "nscr", "nscr", "nshortmid", "nshortmid", "nshortparallel", "nshortparallel", "nsim", "nsim", "nsime", "nsime", "nsimeq", "nsimeq", "nsmid", "nsmid", "nspar", "nspar", "nsqsube",
"nsqsube", "nsqsupe", "nsqsupe", "nsub", "nsub", "nsube", "nsube", "nsubseteq", "nsubseteq", "nsucc", "nsucc", "nsup", "nsup", "nsupe", "nsupe", "nsupseteq", "nsupseteq", "ntgl", "ntgl", "ntilde", "ntilde", "ntlg", "ntlg", "ntriangleleft", "ntriangleleft", "ntrianglelefteq", "ntrianglelefteq", "ntriangleright", "ntriangleright",
"ntrianglerighteq", "ntrianglerighteq", "nu", "nu", "num", "num", "numero", "numero", "numsp", "numsp", "nvDash", "nvDash", "nvHarr", "nvHarr", "nvdash", "nvdash", "nvinfin", "nvinfin", "nvlArr", "nvlArr", "nvrArr", "nvrArr", "nwArr", "nwArr", "nwarhk", "nwarhk", "nwarr", "nwarr", "nwarrow", "nwarrow", "nwnear", "nwnear",
"oS", "oS", "oacute", "oacute", "oast", "oast", "ocir", "ocir", "ocirc", "ocirc", "ocy", "ocy", "odash", "odash", "odblac", "odblac", "odiv", "odiv", "odot", "odot", "odsold", "odsold", "oelig", "oelig", "ofcir", "ofcir", "ofr", "ofr", "ogon", "ogon", "ograve", "ograve", "ogt", "ogt", "ohbar", "ohbar", "ohm", "ohm", "oint",
"oint", "olarr", "olarr", "olcir", "olcir", "olcross", "olcross", "oline", "oline", "olt", "olt", "omacr", "omacr", "omega", "omega", "omicron", "omicron", "omid", "omid", "ominus", "ominus", "oopf", "oopf", "opar", "opar", "operp", "operp", "oplus", "oplus", "or", "or", "orarr", "orarr", "ord", "ord", "order", "order",
"orderof", "orderof", "ordf", "ordf", "ordm", "ordm", "origof", "origof", "oror", "oror", "orslope", "orslope", "orv", "orv", "oscr", "oscr", "oslash", "oslash", "osol", "osol", "otilde", "otilde", "otimes", "otimes", "otimesas", "otimesas", "ouml", "ouml", "ovbar", "ovbar", "par", "par", "para", "para", "parallel", "parallel",
"parsim", "parsim", "parsl", "parsl", "part", "part", "pcy", "pcy", "percnt", "percnt", "period", "period", "permil", "permil", "perp", "perp", "pertenk", "pertenk", "pfr", "pfr", "phi", "phi", "phiv", "phiv", "phmmat", "phmmat", "phone", "phone", "pi", "pi", "pitchfork", "pitchfork", "piv", "piv", "planck", "planck",
"planckh", "planckh", "plankv", "plankv", "plus", "plus", "plusacir", "plusacir", "plusb", "plusb", "pluscir", "pluscir", "plusdo", "plusdo", "plusdu", "plusdu", "pluse", "pluse", "plusmn", "plusmn", "plussim", "plussim", "plustwo", "plustwo", "pm", "pm", "pointint", "pointint", "popf", "popf", "pound", "pound", "pr",
"pr", "prE", "prE", "prap", "prap", "prcue", "prcue", "pre", "pre", "prec", "prec", "precapprox", "precapprox", "preccurlyeq", "preccurlyeq", "preceq", "preceq", "precnapprox", "precnapprox", "precneqq", "precneqq", "precnsim", "precnsim", "precsim", "precsim", "prime", "prime", "primes", "primes", "prnE", "prnE", "prnap",
"prnap", "prnsim", "prnsim", "prod", "prod", "profalar", "profalar", "profline", "profline", "profsurf", "profsurf", "prop", "prop", "propto", "propto", "prsim", "prsim", "prurel", "prurel", "pscr", "pscr", "psi", "psi", "puncsp", "puncsp", "qfr", "qfr", "qint", "qint", "qopf", "qopf", "qprime", "qprime", "qscr", "qscr",
"quaternions", "quaternions", "quatint", "quatint", "quest", "quest", "questeq", "questeq", "rAarr", "rAarr", "rArr", "rArr", "rAtail", "rAtail", "rBarr", "rBarr", "rHar", "rHar", "racute", "racute", "radic", "radic", "raemptyv", "raemptyv", "rang", "rang", "rangd", "rangd", "range", "range", "rangle", "rangle", "raquo",
"raquo", "rarr", "rarr", "rarrap", "rarrap", "rarrb", "rarrb", "rarrbfs", "rarrbfs", "rarrc", "rarrc", "rarrfs", "rarrfs", "rarrhk", "rarrhk", "rarrlp", "rarrlp", "rarrpl", "rarrpl", "rarrsim", "rarrsim", "rarrtl", "rarrtl", "rarrw", "rarrw", "ratail", "ratail", "ratio", "ratio", "rationals", "rationals", "rbarr", "rbarr",
"rbbrk", "rbbrk", "rbrace", "rbrace", "rbrack", "rbrack", "rbrke", "rbrke", "rbrksld", "rbrksld", "rbrkslu", "rbrkslu", "rcaron", "rcaron", "rcedil", "rcedil", "rceil", "rceil", "rcub", "rcub", "rcy", "rcy", "rdca", "rdca", "rdldhar", "rdldhar", "rdquo", "rdquo", "rdquor", "rdquor", "rdsh", "rdsh", "real", "real", "realine",
"realine", "realpart", "realpart", "reals", "reals", "rect", "rect", "reg", "reg", "rfisht", "rfisht", "rfloor", "rfloor", "rfr", "rfr", "rhard", "rhard", "rharu", "rharu", "rharul", "rharul", "rho", "rho", "rhov", "rhov", "rightarrow", "rightarrow", "rightarrowtail", "rightarrowtail", "rightharpoondown", "rightharpoondown",
"rightharpoonup", "rightharpoonup", "rightleftarrows", "rightleftarrows", "rightleftharpoons", "rightleftharpoons", "rightrightarrows", "rightrightarrows", "rightsquigarrow", "rightsquigarrow", "rightthreetimes", "rightthreetimes", "ring", "ring", "risingdotseq", "risingdotseq", "rlarr", "rlarr", "rlhar", "rlhar", "rlm",
"rlm", "rmoust", "rmoust", "rmoustache", "rmoustache", "rnmid", "rnmid", "roang", "roang", "roarr", "roarr", "robrk", "robrk", "ropar", "ropar", "ropf", "ropf", "roplus", "roplus", "rotimes", "rotimes", "rpar", "rpar", "rpargt", "rpargt", "rppolint", "rppolint", "rrarr", "rrarr", "rsaquo", "rsaquo", "rscr", "rscr", "rsh",
"rsh", "rsqb", "rsqb", "rsquo", "rsquo", "rsquor", "rsquor", "rthree", "rthree", "rtimes", "rtimes", "rtri", "rtri", "rtrie", "rtrie", "rtrif", "rtrif", "rtriltri", "rtriltri", "ruluhar", "ruluhar", "rx", "rx", "sacute", "sacute", "sbquo", "sbquo", "sc", "sc", "scE", "scE", "scap", "scap", "scaron", "scaron", "sccue",
"sccue", "sce", "sce", "scedil", "scedil", "scirc", "scirc", "scnE", "scnE", "scnap", "scnap", "scnsim", "scnsim", "scpolint", "scpolint", "scsim", "scsim", "scy", "scy", "sdot", "sdot", "sdotb", "sdotb", "sdote", "sdote", "seArr", "seArr", "searhk", "searhk", "searr", "searr", "searrow", "searrow", "sect", "sect", "semi",
"semi", "seswar", "seswar", "setminus", "setminus", "setmn", "setmn", "sext", "sext", "sfr", "sfr", "sfrown", "sfrown", "sharp", "sharp", "shchcy", "shchcy", "shcy", "shcy", "shortmid", "shortmid", "shortparallel", "shortparallel", "shy", "shy", "sigma", "sigma", "sigmaf", "sigmaf", "sigmav", "sigmav", "sim", "sim", "simdot",
"simdot", "sime", "sime", "simeq", "simeq", "simg", "simg", "simgE", "simgE", "siml", "siml", "simlE", "simlE", "simne", "simne", "simplus", "simplus", "simrarr", "simrarr", "slarr", "slarr", "smallsetminus", "smallsetminus", "smashp", "smashp", "smeparsl", "smeparsl", "smid", "smid", "smile", "smile", "smt", "smt", "smte",
"smte", "softcy", "softcy", "sol", "sol", "solb", "solb", "solbar", "solbar", "sopf", "sopf", "spades", "spades", "spadesuit", "spadesuit", "spar", "spar", "sqcap", "sqcap", "sqcup", "sqcup", "sqsub", "sqsub", "sqsube", "sqsube", "sqsubset", "sqsubset", "sqsubseteq", "sqsubseteq", "sqsup", "sqsup", "sqsupe", "sqsupe",
"sqsupset", "sqsupset", "sqsupseteq", "sqsupseteq", "squ", "squ", "square", "square", "squarf", "squarf", "squf", "squf", "srarr", "srarr", "sscr", "sscr", "ssetmn", "ssetmn", "ssmile", "ssmile", "sstarf", "sstarf", "star", "star", "starf", "starf", "straightepsilon", "straightepsilon", "straightphi", "straightphi", "strns",
"strns", "sub", "sub", "subE", "subE", "subdot", "subdot", "sube", "sube", "subedot", "subedot", "submult", "submult", "subnE", "subnE", "subne", "subne", "subplus", "subplus", "subrarr", "subrarr", "subset", "subset", "subseteq", "subseteq", "subseteqq", "subseteqq", "subsetneq", "subsetneq", "subsetneqq", "subsetneqq",
"subsim", "subsim", "subsub", "subsub", "subsup", "subsup", "succ", "succ", "succapprox", "succapprox", "succcurlyeq", "succcurlyeq", "succeq", "succeq", "succnapprox", "succnapprox", "succneqq", "succneqq", "succnsim", "succnsim", "succsim", "succsim", "sum", "sum", "sung", "sung", "sup", "sup", "sup1", "sup1", "sup2",
"sup2", "sup3", "sup3", "supE", "supE", "supdot", "supdot", "supdsub", "supdsub", "supe", "supe", "supedot", "supedot", "suphsol", "suphsol", "suphsub", "suphsub", "suplarr", "suplarr", "supmult", "supmult", "supnE", "supnE", "supne", "supne", "supplus", "supplus", "supset", "supset", "supseteq", "supseteq", "supseteqq",
"supseteqq", "supsetneq", "supsetneq", "supsetneqq", "supsetneqq", "supsim", "supsim", "supsub", "supsub", "supsup", "supsup", "swArr", "swArr", "swarhk", "swarhk", "swarr", "swarr", "swarrow", "swarrow", "swnwar", "swnwar", "szlig", "szlig", "target", "target", "tau", "tau", "tbrk", "tbrk", "tcaron", "tcaron", "tcedil",
"tcedil", "tcy", "tcy", "tdot", "tdot", "telrec", "telrec", "tfr", "tfr", "there4", "there4", "therefore", "therefore", "theta", "theta", "thetasym", "thetasym", "thetav", "thetav", "thickapprox", "thickapprox", "thicksim", "thicksim", "thinsp", "thinsp", "thkap", "thkap", "thksim", "thksim", "thorn", "thorn", "tilde",
"tilde", "times", "times", "timesb", "timesb", "timesbar", "timesbar", "timesd", "timesd", "tint", "tint", "toea", "toea", "top", "top", "topbot", "topbot", "topcir", "topcir", "topf", "topf", "topfork", "topfork", "tosa", "tosa", "tprime", "tprime", "trade", "trade", "triangle", "triangle", "triangledown", "triangledown",
"triangleleft", "triangleleft", "trianglelefteq", "trianglelefteq", "triangleq", "triangleq", "triangleright", "triangleright", "trianglerighteq", "trianglerighteq", "tridot", "tridot", "trie", "trie", "triminus", "triminus", "triplus", "triplus", "trisb", "trisb", "tritime", "tritime", "trpezium", "trpezium", "tscr",
"tscr", "tscy", "tscy", "tshcy", "tshcy", "tstrok", "tstrok", "twixt", "twixt", "twoheadleftarrow", "twoheadleftarrow", "twoheadrightarrow", "twoheadrightarrow", "uArr", "uArr", "uHar", "uHar", "uacute", "uacute", "uarr", "uarr", "ubrcy", "ubrcy", "ubreve", "ubreve", "ucirc", "ucirc", "ucy", "ucy", "udarr", "udarr", "udblac",
"udblac", "udhar", "udhar", "ufisht", "ufisht", "ufr", "ufr", "ugrave", "ugrave", "uharl", "uharl", "uharr", "uharr", "uhblk", "uhblk", "ulcorn", "ulcorn", "ulcorner", "ulcorner", "ulcrop", "ulcrop", "ultri", "ultri", "umacr", "umacr", "uml", "uml", "uogon", "uogon", "uopf", "uopf", "uparrow", "uparrow", "updownarrow",
"updownarrow", "upharpoonleft", "upharpoonleft", "upharpoonright", "upharpoonright", "uplus", "uplus", "upsi", "upsi", "upsih", "upsih", "upsilon", "upsilon", "upuparrows", "upuparrows", "urcorn", "urcorn", "urcorner", "urcorner", "urcrop", "urcrop", "uring", "uring", "urtri", "urtri", "uscr", "uscr", "utdot", "utdot",
"utilde", "utilde", "utri", "utri", "utrif", "utrif", "uuarr", "uuarr", "uuml", "uuml", "uwangle", "uwangle", "vArr", "vArr", "vBar", "vBar", "vBarv", "vBarv", "vDash", "vDash", "vangrt", "vangrt", "varepsilon", "varepsilon", "varkappa", "varkappa", "varnothing", "varnothing", "varphi", "varphi", "varpi", "varpi", "varpropto",
"varpropto", "varr", "varr", "varrho", "varrho", "varsigma", "varsigma", "vartheta", "vartheta", "vartriangleleft", "vartriangleleft", "vartriangleright", "vartriangleright", "vcy", "vcy", "vdash", "vdash", "vee", "vee", "veebar", "veebar", "veeeq", "veeeq", "vellip", "vellip", "verbar", "verbar", "vert", "vert", "vfr",
"vfr", "vltri", "vltri", "vopf", "vopf", "vprop", "vprop", "vrtri", "vrtri", "vscr", "vscr", "vzigzag", "vzigzag", "wcirc", "wcirc", "wedbar", "wedbar", "wedge", "wedge", "wedgeq", "wedgeq", "weierp", "weierp", "wfr", "wfr", "wopf", "wopf", "wp", "wp", "wr", "wr", "wreath", "wreath", "wscr", "wscr", "xcap", "xcap", "xcirc",
"xcirc", "xcup", "xcup", "xdtri", "xdtri", "xfr", "xfr", "xhArr", "xhArr", "xharr", "xharr", "xi", "xi", "xlArr", "xlArr", "xlarr", "xlarr", "xmap", "xmap", "xnis", "xnis", "xodot", "xodot", "xopf", "xopf", "xoplus", "xoplus", "xotime", "xotime", "xrArr", "xrArr", "xrarr", "xrarr", "xscr", "xscr", "xsqcup", "xsqcup", "xuplus",
"xuplus", "xutri", "xutri", "xvee", "xvee", "xwedge", "xwedge", "yacute", "yacute", "yacy", "yacy", "ycirc", "ycirc", "ycy", "ycy", "yen", "yen", "yfr", "yfr", "yicy", "yicy", "yopf", "yopf", "yscr", "yscr", "yucy", "yucy", "yuml", "yuml", "zacute", "zacute", "zcaron", "zcaron", "zcy", "zcy", "zdot", "zdot", "zeetrf",
"zeetrf", "zeta", "zeta", "zfr", "zfr", "zhcy", "zhcy", "zigrarr", "zigrarr", "zopf", "zopf", "zscr", "zscr", "zwj", "zwj", "zwnj", "zwnj", ];

immutable dchar[] availableEntitiesValues =
['\u00c6', '\u00c6', '\u0026', '\u0026', '\u00c1', '\u00c1', '\u0102', '\u0102', '\u00c2', '\u00c2', '\u0410', '\u0410', '\U0001d504', '\U0001d504', '\u00c0', '\u00c0', '\u0391', '\u0391', '\u0100', '\u0100', '\u2a53', '\u2a53', '\u0104', '\u0104', '\U0001d538', '\U0001d538', '\u2061', '\u2061', '\u00c5', '\u00c5', '\U0001d49c', '\U0001d49c', '\u2254', '\u2254', '\u00c3',
'\u00c3', '\u00c4', '\u00c4', '\u2216', '\u2216', '\u2ae7', '\u2ae7', '\u2306', '\u2306', '\u0411', '\u0411', '\u2235', '\u2235', '\u212c', '\u212c', '\u0392', '\u0392', '\U0001d505', '\U0001d505', '\U0001d539', '\U0001d539', '\u02d8', '\u02d8', '\u212c', '\u212c', '\u224e', '\u224e', '\u0427', '\u0427', '\u00a9', '\u00a9', '\u0106', '\u0106', '\u22d2', '\u22d2', '\u2145',
'\u2145', '\u212d', '\u212d', '\u010c', '\u010c', '\u00c7', '\u00c7', '\u0108', '\u0108', '\u2230', '\u2230', '\u010a', '\u010a', '\u00b8', '\u00b8', '\u00b7', '\u00b7', '\u212d', '\u212d', '\u03a7', '\u03a7', '\u2299', '\u2299', '\u2296', '\u2296', '\u2295', '\u2295', '\u2297', '\u2297',
'\u2232', '\u2232', '\u201d', '\u201d', '\u2019', '\u2019', '\u2237', '\u2237', '\u2a74', '\u2a74', '\u2261', '\u2261', '\u222f', '\u222f', '\u222e', '\u222e', '\u2102', '\u2102', '\u2210', '\u2210', '\u2233',
'\u2233', '\u2a2f', '\u2a2f', '\U0001d49e', '\U0001d49e', '\u22d3', '\u22d3', '\u224d', '\u224d', '\u2145', '\u2145', '\u2911', '\u2911', '\u0402', '\u0402', '\u0405', '\u0405', '\u040f', '\u040f', '\u2021', '\u2021', '\u21a1', '\u21a1', '\u2ae4', '\u2ae4', '\u010e', '\u010e', '\u0414', '\u0414', '\u2207', '\u2207', '\u0394', '\u0394', '\U0001d507', '\U0001d507',
'\u00b4', '\u00b4', '\u02d9', '\u02d9', '\u02dd', '\u02dd', '\u0060', '\u0060', '\u02dc', '\u02dc', '\u22c4', '\u22c4', '\u2146', '\u2146', '\U0001d53b', '\U0001d53b', '\u00a8', '\u00a8', '\u20dc', '\u20dc', '\u2250',
'\u2250', '\u222f', '\u222f', '\u00a8', '\u00a8', '\u21d3', '\u21d3', '\u21d0', '\u21d0', '\u21d4', '\u21d4', '\u2ae4', '\u2ae4', '\u27f8', '\u27f8', '\u27fa',
'\u27fa', '\u27f9', '\u27f9', '\u21d2', '\u21d2', '\u22a8', '\u22a8', '\u21d1', '\u21d1', '\u21d5', '\u21d5', '\u2225', '\u2225', '\u2193', '\u2193', '\u2913', '\u2913',
'\u21f5', '\u21f5', '\u0311', '\u0311', '\u2950', '\u2950', '\u295e', '\u295e', '\u21bd', '\u21bd', '\u2956', '\u2956', '\u295f', '\u295f', '\u21c1', '\u21c1', '\u2957',
'\u2957', '\u22a4', '\u22a4', '\u21a7', '\u21a7', '\u21d3', '\u21d3', '\U0001d49f', '\U0001d49f', '\u0110', '\u0110', '\u014a', '\u014a', '\u00d0', '\u00d0', '\u00c9', '\u00c9', '\u011a', '\u011a', '\u00ca', '\u00ca', '\u042d', '\u042d', '\u0116', '\u0116', '\U0001d508', '\U0001d508', '\u00c8', '\u00c8', '\u2208', '\u2208', '\u0112', '\u0112',
'\u25fb', '\u25fb', '\u25ab', '\u25ab', '\u0118', '\u0118', '\U0001d53c', '\U0001d53c', '\u0395', '\u0395', '\u2a75', '\u2a75', '\u2242', '\u2242', '\u21cc', '\u21cc', '\u2130', '\u2130', '\u2a73', '\u2a73', '\u0397', '\u0397', '\u00cb', '\u00cb', '\u2203', '\u2203', '\u2147', '\u2147',
'\u0424', '\u0424', '\U0001d509', '\U0001d509', '\u25fc', '\u25fc', '\u25aa', '\u25aa', '\U0001d53d', '\U0001d53d', '\u2200', '\u2200', '\u2131', '\u2131', '\u2131', '\u2131', '\u0403', '\u0403', '\u003e', '\u003e', '\u0393', '\u0393', '\u03dc', '\u03dc', '\u011e', '\u011e', '\u0122', '\u0122', '\u011c', '\u011c',
'\u0413', '\u0413', '\u0120', '\u0120', '\U0001d50a', '\U0001d50a', '\u22d9', '\u22d9', '\U0001d53e', '\U0001d53e', '\u2265', '\u2265', '\u22db', '\u22db', '\u2267', '\u2267', '\u2aa2', '\u2aa2', '\u2277', '\u2277', '\u2a7e', '\u2a7e', '\u2273', '\u2273',
'\U0001d4a2', '\U0001d4a2', '\u226b', '\u226b', '\u042a', '\u042a', '\u02c7', '\u02c7', '\u005e', '\u005e', '\u0124', '\u0124', '\u210c', '\u210c', '\u210b', '\u210b', '\u210d', '\u210d', '\u2500', '\u2500', '\u210b', '\u210b', '\u0126', '\u0126', '\u224e', '\u224e', '\u224f', '\u224f', '\u0415', '\u0415', '\u0132', '\u0132',
'\u0401', '\u0401', '\u00cd', '\u00cd', '\u00ce', '\u00ce', '\u0418', '\u0418', '\u0130', '\u0130', '\u2111', '\u2111', '\u00cc', '\u00cc', '\u2111', '\u2111', '\u012a', '\u012a', '\u2148', '\u2148', '\u21d2', '\u21d2', '\u222c', '\u222c', '\u222b', '\u222b', '\u22c2', '\u22c2', '\u2063', '\u2063', '\u2062',
'\u2062', '\u012e', '\u012e', '\U0001d540', '\U0001d540', '\u0399', '\u0399', '\u2110', '\u2110', '\u0128', '\u0128', '\u0406', '\u0406', '\u00cf', '\u00cf', '\u0134', '\u0134', '\u0419', '\u0419', '\U0001d50d', '\U0001d50d', '\U0001d541', '\U0001d541', '\U0001d4a5', '\U0001d4a5', '\u0408', '\u0408', '\u0404', '\u0404', '\u0425', '\u0425', '\u040c', '\u040c', '\u039a', '\u039a', '\u0136', '\u0136',
'\u041a', '\u041a', '\U0001d50e', '\U0001d50e', '\U0001d542', '\U0001d542', '\U0001d4a6', '\U0001d4a6', '\u0409', '\u0409', '\u003c', '\u003c', '\u0139', '\u0139', '\u039b', '\u039b', '\u27ea', '\u27ea', '\u2112', '\u2112', '\u219e', '\u219e', '\u013d', '\u013d', '\u013b', '\u013b', '\u041b', '\u041b', '\u27e8', '\u27e8', '\u2190', '\u2190', '\u21e4',
'\u21e4', '\u21c6', '\u21c6', '\u2308', '\u2308', '\u27e6', '\u27e6', '\u2961', '\u2961', '\u21c3', '\u21c3', '\u2959', '\u2959', '\u230a', '\u230a', '\u2194', '\u2194', '\u294e',
'\u294e', '\u22a3', '\u22a3', '\u21a4', '\u21a4', '\u295a', '\u295a', '\u22b2', '\u22b2', '\u29cf', '\u29cf', '\u22b4', '\u22b4', '\u2951', '\u2951', '\u2960', '\u2960', '\u21bf', '\u21bf',
'\u2958', '\u2958', '\u21bc', '\u21bc', '\u2952', '\u2952', '\u21d0', '\u21d0', '\u21d4', '\u21d4', '\u22da', '\u22da', '\u2266', '\u2266', '\u2276', '\u2276', '\u2aa1', '\u2aa1', '\u2a7d', '\u2a7d',
'\u2272', '\u2272', '\U0001d50f', '\U0001d50f', '\u22d8', '\u22d8', '\u21da', '\u21da', '\u013f', '\u013f', '\u27f5', '\u27f5', '\u27f7', '\u27f7', '\u27f6', '\u27f6', '\u27f8', '\u27f8', '\u27fa', '\u27fa', '\u27f9', '\u27f9',
'\U0001d543', '\U0001d543', '\u2199', '\u2199', '\u2198', '\u2198', '\u2112', '\u2112', '\u21b0', '\u21b0', '\u0141', '\u0141', '\u226a', '\u226a', '\u2905', '\u2905', '\u041c', '\u041c', '\u205f', '\u205f', '\u2133', '\u2133', '\U0001d510', '\U0001d510', '\u2213', '\u2213', '\U0001d544', '\U0001d544', '\u2133', '\u2133', '\u039c', '\u039c',
'\u040a', '\u040a', '\u0143', '\u0143', '\u0147', '\u0147', '\u0145', '\u0145', '\u041d', '\u041d', '\u200b', '\u200b', '\u200b', '\u200b', '\u200b', '\u200b', '\u200b', '\u200b', '\u226b', '\u226b',
'\u226a', '\u226a', '\u000a', '\u000a', '\U0001d511', '\U0001d511', '\u2060', '\u2060', '\u00a0', '\u00a0', '\u2115', '\u2115', '\u2aec', '\u2aec', '\u2262', '\u2262', '\u226d', '\u226d', '\u2226', '\u2226', '\u2209', '\u2209', '\u2260', '\u2260',
'\u2204', '\u2204', '\u226f', '\u226f', '\u2271', '\u2271', '\u2279', '\u2279', '\u2275', '\u2275', '\u22ea', '\u22ea', '\u22ec', '\u22ec', '\u226e', '\u226e', '\u2270', '\u2270', '\u2278',
'\u2278', '\u2274', '\u2274', '\u2280', '\u2280', '\u22e0', '\u22e0', '\u220c', '\u220c', '\u22eb', '\u22eb', '\u22ed', '\u22ed', '\u22e2', '\u22e2', '\u22e3',
'\u22e3', '\u2288', '\u2288', '\u2281', '\u2281', '\u22e1', '\u22e1', '\u2289', '\u2289', '\u2241', '\u2241', '\u2244', '\u2244', '\u2247', '\u2247', '\u2249', '\u2249', '\u2224',
'\u2224', '\U0001d4a9', '\U0001d4a9', '\u00d1', '\u00d1', '\u039d', '\u039d', '\u0152', '\u0152', '\u00d3', '\u00d3', '\u00d4', '\u00d4', '\u041e', '\u041e', '\u0150', '\u0150', '\U0001d512', '\U0001d512', '\u00d2', '\u00d2', '\u014c', '\u014c', '\u03a9', '\u03a9', '\u039f', '\u039f', '\U0001d546', '\U0001d546', '\u201c', '\u201c', '\u2018',
'\u2018', '\u2a54', '\u2a54', '\U0001d4aa', '\U0001d4aa', '\u00d8', '\u00d8', '\u00d5', '\u00d5', '\u2a37', '\u2a37', '\u00d6', '\u00d6', '\u203e', '\u203e', '\u23de', '\u23de', '\u23b4', '\u23b4', '\u23dc', '\u23dc', '\u2202', '\u2202', '\u041f', '\u041f', '\U0001d513', '\U0001d513', '\u03a6', '\u03a6', '\u03a0', '\u03a0', '\u00b1',
'\u00b1', '\u210c', '\u210c', '\u2119', '\u2119', '\u2abb', '\u2abb', '\u227a', '\u227a', '\u2aaf', '\u2aaf', '\u227c', '\u227c', '\u227e', '\u227e', '\u2033', '\u2033', '\u220f', '\u220f', '\u2237', '\u2237', '\u221d', '\u221d', '\U0001d4ab', '\U0001d4ab',
'\u03a8', '\u03a8', '\u0022', '\u0022', '\U0001d514', '\U0001d514', '\u211a', '\u211a', '\U0001d4ac', '\U0001d4ac', '\u2910', '\u2910', '\u00ae', '\u00ae', '\u0154', '\u0154', '\u27eb', '\u27eb', '\u21a0', '\u21a0', '\u2916', '\u2916', '\u0158', '\u0158', '\u0156', '\u0156', '\u0420', '\u0420', '\u211c', '\u211c', '\u220b', '\u220b', '\u21cb', '\u21cb',
'\u296f', '\u296f', '\u211c', '\u211c', '\u03a1', '\u03a1', '\u27e9', '\u27e9', '\u2192', '\u2192', '\u21e5', '\u21e5', '\u21c4', '\u21c4', '\u2309', '\u2309', '\u27e7', '\u27e7', '\u295d',
'\u295d', '\u21c2', '\u21c2', '\u2955', '\u2955', '\u230b', '\u230b', '\u22a2', '\u22a2', '\u21a6', '\u21a6', '\u295b', '\u295b', '\u22b3', '\u22b3', '\u29d0', '\u29d0', '\u22b5',
'\u22b5', '\u294f', '\u294f', '\u295c', '\u295c', '\u21be', '\u21be', '\u2954', '\u2954', '\u21c0', '\u21c0', '\u2953', '\u2953', '\u21d2', '\u21d2', '\u211d', '\u211d', '\u2970', '\u2970',
'\u21db', '\u21db', '\u211b', '\u211b', '\u21b1', '\u21b1', '\u29f4', '\u29f4', '\u0429', '\u0429', '\u0428', '\u0428', '\u042c', '\u042c', '\u015a', '\u015a', '\u2abc', '\u2abc', '\u0160', '\u0160', '\u015e', '\u015e', '\u015c', '\u015c', '\u0421', '\u0421', '\U0001d516', '\U0001d516', '\u2193', '\u2193', '\u2190', '\u2190',
'\u2192', '\u2192', '\u2191', '\u2191', '\u03a3', '\u03a3', '\u2218', '\u2218', '\U0001d54a', '\U0001d54a', '\u221a', '\u221a', '\u25a1', '\u25a1', '\u2293', '\u2293', '\u228f', '\u228f', '\u2291', '\u2291', '\u2290', '\u2290',
'\u2292', '\u2292', '\u2294', '\u2294', '\U0001d4ae', '\U0001d4ae', '\u22c6', '\u22c6', '\u22d0', '\u22d0', '\u22d0', '\u22d0', '\u2286', '\u2286', '\u227b', '\u227b', '\u2ab0', '\u2ab0', '\u227d', '\u227d', '\u227f', '\u227f', '\u220b',
'\u220b', '\u2211', '\u2211', '\u22d1', '\u22d1', '\u2283', '\u2283', '\u2287', '\u2287', '\u22d1', '\u22d1', '\u00de', '\u00de', '\u2122', '\u2122', '\u040b', '\u040b', '\u0426', '\u0426', '\u0009', '\u0009', '\u03a4', '\u03a4', '\u0164', '\u0164', '\u0162', '\u0162', '\u0422', '\u0422', '\U0001d517', '\U0001d517', '\u2234', '\u2234', '\u0398', '\u0398',
'\u2009', '\u2009', '\u223c', '\u223c', '\u2243', '\u2243', '\u2245', '\u2245', '\u2248', '\u2248', '\U0001d54b', '\U0001d54b', '\u20db', '\u20db', '\U0001d4af', '\U0001d4af', '\u0166', '\u0166', '\u00da', '\u00da', '\u219f', '\u219f', '\u2949', '\u2949', '\u040e', '\u040e', '\u016c', '\u016c', '\u00db',
'\u00db', '\u0423', '\u0423', '\u0170', '\u0170', '\U0001d518', '\U0001d518', '\u00d9', '\u00d9', '\u016a', '\u016a', '\u005f', '\u005f', '\u23df', '\u23df', '\u23b5', '\u23b5', '\u23dd', '\u23dd', '\u22c3', '\u22c3', '\u228e', '\u228e', '\u0172', '\u0172', '\U0001d54c', '\U0001d54c', '\u2191', '\u2191', '\u2912',
'\u2912', '\u21c5', '\u21c5', '\u2195', '\u2195', '\u296e', '\u296e', '\u22a5', '\u22a5', '\u21a5', '\u21a5', '\u21d1', '\u21d1', '\u21d5', '\u21d5', '\u2196', '\u2196', '\u2197', '\u2197', '\u03d2', '\u03d2', '\u03a5', '\u03a5',
'\u016e', '\u016e', '\U0001d4b0', '\U0001d4b0', '\u0168', '\u0168', '\u00dc', '\u00dc', '\u22ab', '\u22ab', '\u2aeb', '\u2aeb', '\u0412', '\u0412', '\u22a9', '\u22a9', '\u2ae6', '\u2ae6', '\u22c1', '\u22c1', '\u2016', '\u2016', '\u2016', '\u2016', '\u2223', '\u2223', '\u007c', '\u007c', '\u2758', '\u2758', '\u2240',
'\u2240', '\u200a', '\u200a', '\U0001d519', '\U0001d519', '\U0001d54d', '\U0001d54d', '\U0001d4b1', '\U0001d4b1', '\u22aa', '\u22aa', '\u0174', '\u0174', '\u22c0', '\u22c0', '\U0001d51a', '\U0001d51a', '\U0001d54e', '\U0001d54e', '\U0001d4b2', '\U0001d4b2', '\U0001d51b', '\U0001d51b', '\u039e', '\u039e', '\U0001d54f', '\U0001d54f', '\U0001d4b3', '\U0001d4b3', '\u042f', '\u042f', '\u0407', '\u0407', '\u042e', '\u042e', '\u00dd', '\u00dd',
'\u0176', '\u0176', '\u042b', '\u042b', '\U0001d51c', '\U0001d51c', '\U0001d550', '\U0001d550', '\U0001d4b4', '\U0001d4b4', '\u0178', '\u0178', '\u0416', '\u0416', '\u0179', '\u0179', '\u017d', '\u017d', '\u0417', '\u0417', '\u017b', '\u017b', '\u200b', '\u200b', '\u0396', '\u0396', '\u2128', '\u2128', '\u2124', '\u2124', '\U0001d4b5', '\U0001d4b5', '\u00e1', '\u00e1', '\u0103', '\u0103', '\u223e',
'\u223e', '\u223f', '\u223f', '\u00e2', '\u00e2', '\u00b4', '\u00b4', '\u0430', '\u0430', '\u00e6', '\u00e6', '\u2061', '\u2061', '\U0001d51e', '\U0001d51e', '\u00e0', '\u00e0', '\u2135', '\u2135', '\u2135', '\u2135', '\u03b1', '\u03b1', '\u0101', '\u0101', '\u2a3f', '\u2a3f', '\u2227', '\u2227', '\u2a55', '\u2a55', '\u2a5c', '\u2a5c', '\u2a58', '\u2a58', '\u2a5a', '\u2a5a', '\u2220',
'\u2220', '\u29a4', '\u29a4', '\u2220', '\u2220', '\u2221', '\u2221', '\u29a8', '\u29a8', '\u29a9', '\u29a9', '\u29aa', '\u29aa', '\u29ab', '\u29ab', '\u29ac', '\u29ac', '\u29ad', '\u29ad', '\u29ae', '\u29ae', '\u29af', '\u29af', '\u221f', '\u221f', '\u22be', '\u22be', '\u299d', '\u299d', '\u2222',
'\u2222', '\u00c5', '\u00c5', '\u237c', '\u237c', '\u0105', '\u0105', '\U0001d552', '\U0001d552', '\u2248', '\u2248', '\u2a70', '\u2a70', '\u2a6f', '\u2a6f', '\u224a', '\u224a', '\u224b', '\u224b', '\u2248', '\u2248', '\u224a', '\u224a', '\u00e5', '\u00e5', '\U0001d4b6', '\U0001d4b6', '\u002a', '\u002a', '\u2248', '\u2248', '\u224d', '\u224d', '\u00e3', '\u00e3', '\u00e4',
'\u00e4', '\u2233', '\u2233', '\u2a11', '\u2a11', '\u2aed', '\u2aed', '\u224c', '\u224c', '\u03f6', '\u03f6', '\u2035', '\u2035', '\u223d', '\u223d', '\u22cd', '\u22cd', '\u22bd', '\u22bd', '\u2305', '\u2305', '\u2305', '\u2305', '\u23b5', '\u23b5', '\u23b6', '\u23b6', '\u224c', '\u224c', '\u0431',
'\u0431', '\u201e', '\u201e', '\u2235', '\u2235', '\u2235', '\u2235', '\u29b0', '\u29b0', '\u03f6', '\u03f6', '\u212c', '\u212c', '\u03b2', '\u03b2', '\u2136', '\u2136', '\u226c', '\u226c', '\U0001d51f', '\U0001d51f', '\u22c2', '\u22c2', '\u25ef', '\u25ef', '\u22c3', '\u22c3', '\u2a00', '\u2a00', '\u2a01', '\u2a01', '\u2a02', '\u2a02',
'\u2a06', '\u2a06', '\u2605', '\u2605', '\u25bd', '\u25bd', '\u25b3', '\u25b3', '\u2a04', '\u2a04', '\u22c1', '\u22c1', '\u22c0', '\u22c0', '\u290d', '\u290d', '\u29eb', '\u29eb', '\u25aa', '\u25aa', '\u25b4', '\u25b4', '\u25be',
'\u25be', '\u25c2', '\u25c2', '\u25b8', '\u25b8', '\u2423', '\u2423', '\u2592', '\u2592', '\u2591', '\u2591', '\u2593', '\u2593', '\u2588', '\u2588', '\u2310', '\u2310', '\U0001d553', '\U0001d553', '\u22a5', '\u22a5', '\u22a5', '\u22a5', '\u22c8', '\u22c8', '\u2557', '\u2557', '\u2554', '\u2554', '\u2556',
'\u2556', '\u2553', '\u2553', '\u2550', '\u2550', '\u2566', '\u2566', '\u2569', '\u2569', '\u2564', '\u2564', '\u2567', '\u2567', '\u255d', '\u255d', '\u255a', '\u255a', '\u255c', '\u255c', '\u2559', '\u2559', '\u2551', '\u2551', '\u256c', '\u256c', '\u2563', '\u2563', '\u2560', '\u2560', '\u256b', '\u256b', '\u2562', '\u2562', '\u255f', '\u255f', '\u29c9',
'\u29c9', '\u2555', '\u2555', '\u2552', '\u2552', '\u2510', '\u2510', '\u250c', '\u250c', '\u2500', '\u2500', '\u2565', '\u2565', '\u2568', '\u2568', '\u252c', '\u252c', '\u2534', '\u2534', '\u229f', '\u229f', '\u229e', '\u229e', '\u22a0', '\u22a0', '\u255b', '\u255b', '\u2558', '\u2558', '\u2518', '\u2518', '\u2514', '\u2514', '\u2502',
'\u2502', '\u256a', '\u256a', '\u2561', '\u2561', '\u255e', '\u255e', '\u253c', '\u253c', '\u2524', '\u2524', '\u251c', '\u251c', '\u2035', '\u2035', '\u02d8', '\u02d8', '\u00a6', '\u00a6', '\U0001d4b7', '\U0001d4b7', '\u204f', '\u204f', '\u223d', '\u223d', '\u22cd', '\u22cd', '\u005c', '\u005c', '\u29c5', '\u29c5', '\u27c8', '\u27c8', '\u2022', '\u2022', '\u2022',
'\u2022', '\u224e', '\u224e', '\u2aae', '\u2aae', '\u224f', '\u224f', '\u224f', '\u224f', '\u0107', '\u0107', '\u2229', '\u2229', '\u2a44', '\u2a44', '\u2a49', '\u2a49', '\u2a4b', '\u2a4b', '\u2a47', '\u2a47', '\u2a40', '\u2a40', '\u2041', '\u2041', '\u02c7', '\u02c7', '\u2a4d', '\u2a4d', '\u010d', '\u010d', '\u00e7', '\u00e7', '\u0109',
'\u0109', '\u2a4c', '\u2a4c', '\u2a50', '\u2a50', '\u010b', '\u010b', '\u00b8', '\u00b8', '\u29b2', '\u29b2', '\u00a2', '\u00a2', '\u00b7', '\u00b7', '\U0001d520', '\U0001d520', '\u0447', '\u0447', '\u2713', '\u2713', '\u2713', '\u2713', '\u03c7', '\u03c7', '\u25cb', '\u25cb', '\u29c3', '\u29c3', '\u02c6', '\u02c6', '\u2257', '\u2257', '\u21ba',
'\u21ba', '\u21bb', '\u21bb', '\u00ae', '\u00ae', '\u24c8', '\u24c8', '\u229b', '\u229b', '\u229a', '\u229a', '\u229d', '\u229d', '\u2257', '\u2257', '\u2a10', '\u2a10', '\u2aef', '\u2aef', '\u29c2', '\u29c2', '\u2663', '\u2663', '\u2663', '\u2663', '\u003a',
'\u003a', '\u2254', '\u2254', '\u2254', '\u2254', '\u002c', '\u002c', '\u0040', '\u0040', '\u2201', '\u2201', '\u2218', '\u2218', '\u2201', '\u2201', '\u2102', '\u2102', '\u2245', '\u2245', '\u2a6d', '\u2a6d', '\u222e', '\u222e', '\U0001d554', '\U0001d554', '\u2210', '\u2210', '\u00a9', '\u00a9', '\u2117', '\u2117', '\u21b5', '\u21b5',
'\u2717', '\u2717', '\U0001d4b8', '\U0001d4b8', '\u2acf', '\u2acf', '\u2ad1', '\u2ad1', '\u2ad0', '\u2ad0', '\u2ad2', '\u2ad2', '\u22ef', '\u22ef', '\u2938', '\u2938', '\u2935', '\u2935', '\u22de', '\u22de', '\u22df', '\u22df', '\u21b6', '\u21b6', '\u293d', '\u293d', '\u222a', '\u222a', '\u2a48', '\u2a48', '\u2a46', '\u2a46', '\u2a4a', '\u2a4a',
'\u228d', '\u228d', '\u2a45', '\u2a45', '\u21b7', '\u21b7', '\u293c', '\u293c', '\u22de', '\u22de', '\u22df', '\u22df', '\u22ce', '\u22ce', '\u22cf', '\u22cf', '\u00a4', '\u00a4', '\u21b6', '\u21b6', '\u21b7', '\u21b7', '\u22ce', '\u22ce', '\u22cf', '\u22cf',
'\u2232', '\u2232', '\u2231', '\u2231', '\u232d', '\u232d', '\u21d3', '\u21d3', '\u2965', '\u2965', '\u2020', '\u2020', '\u2138', '\u2138', '\u2193', '\u2193', '\u2010', '\u2010', '\u22a3', '\u22a3', '\u290f', '\u290f', '\u02dd', '\u02dd', '\u010f', '\u010f', '\u0434', '\u0434', '\u2146', '\u2146', '\u2021', '\u2021', '\u21ca', '\u21ca', '\u2a77',
'\u2a77', '\u00b0', '\u00b0', '\u03b4', '\u03b4', '\u29b1', '\u29b1', '\u297f', '\u297f', '\U0001d521', '\U0001d521', '\u21c3', '\u21c3', '\u21c2', '\u21c2', '\u22c4', '\u22c4', '\u22c4', '\u22c4', '\u2666', '\u2666', '\u2666', '\u2666', '\u00a8', '\u00a8', '\u03dd', '\u03dd', '\u22f2', '\u22f2', '\u00f7', '\u00f7', '\u00f7', '\u00f7', '\u22c7',
'\u22c7', '\u22c7', '\u22c7', '\u0452', '\u0452', '\u231e', '\u231e', '\u230d', '\u230d', '\u0024', '\u0024', '\U0001d555', '\U0001d555', '\u02d9', '\u02d9', '\u2250', '\u2250', '\u2251', '\u2251', '\u2238', '\u2238', '\u2214', '\u2214', '\u22a1', '\u22a1', '\u2306', '\u2306', '\u2193', '\u2193', '\u21ca',
'\u21ca', '\u21c3', '\u21c3', '\u21c2', '\u21c2', '\u2910', '\u2910', '\u231f', '\u231f', '\u230c', '\u230c', '\U0001d4b9', '\U0001d4b9', '\u0455', '\u0455', '\u29f6', '\u29f6', '\u0111', '\u0111', '\u22f1', '\u22f1', '\u25bf', '\u25bf', '\u25be', '\u25be', '\u21f5', '\u21f5', '\u296f', '\u296f', '\u29a6',
'\u29a6', '\u045f', '\u045f', '\u27ff', '\u27ff', '\u2a77', '\u2a77', '\u2251', '\u2251', '\u00e9', '\u00e9', '\u2a6e', '\u2a6e', '\u011b', '\u011b', '\u2256', '\u2256', '\u00ea', '\u00ea', '\u2255', '\u2255', '\u044d', '\u044d', '\u0117', '\u0117', '\u2147', '\u2147', '\u2252', '\u2252', '\U0001d522', '\U0001d522', '\u2a9a', '\u2a9a', '\u00e8', '\u00e8', '\u2a96', '\u2a96', '\u2a98',
'\u2a98', '\u2a99', '\u2a99', '\u23e7', '\u23e7', '\u2113', '\u2113', '\u2a95', '\u2a95', '\u2a97', '\u2a97', '\u0113', '\u0113', '\u2205', '\u2205', '\u2205', '\u2205', '\u2205', '\u2205', '\u2003', '\u2003', '\u2004', '\u2004', '\u2005', '\u2005', '\u014b', '\u014b', '\u2002', '\u2002', '\u0119', '\u0119', '\U0001d556', '\U0001d556', '\u22d5', '\u22d5', '\u29e3',
'\u29e3', '\u2a71', '\u2a71', '\u03b5', '\u03b5', '\u03b5', '\u03b5', '\u03f5', '\u03f5', '\u2256', '\u2256', '\u2255', '\u2255', '\u2242', '\u2242', '\u2a96', '\u2a96', '\u2a95', '\u2a95', '\u003d', '\u003d', '\u225f', '\u225f', '\u2261', '\u2261', '\u2a78', '\u2a78', '\u29e5', '\u29e5', '\u2253', '\u2253',
'\u2971', '\u2971', '\u212f', '\u212f', '\u2250', '\u2250', '\u2242', '\u2242', '\u03b7', '\u03b7', '\u00f0', '\u00f0', '\u00eb', '\u00eb', '\u20ac', '\u20ac', '\u0021', '\u0021', '\u2203', '\u2203', '\u2130', '\u2130', '\u2147', '\u2147', '\u2252', '\u2252', '\u0444', '\u0444', '\u2640', '\u2640', '\ufb03', '\ufb03', '\ufb00',
'\ufb00', '\ufb04', '\ufb04', '\U0001d523', '\U0001d523', '\ufb01', '\ufb01', '\u266d', '\u266d', '\ufb02', '\ufb02', '\u25b1', '\u25b1', '\u0192', '\u0192', '\U0001d557', '\U0001d557', '\u2200', '\u2200', '\u22d4', '\u22d4', '\u2ad9', '\u2ad9', '\u2a0d', '\u2a0d', '\u00bd', '\u00bd', '\u2153', '\u2153', '\u00bc', '\u00bc', '\u2155', '\u2155', '\u2159', '\u2159',
'\u215b', '\u215b', '\u2154', '\u2154', '\u2156', '\u2156', '\u00be', '\u00be', '\u2157', '\u2157', '\u215c', '\u215c', '\u2158', '\u2158', '\u215a', '\u215a', '\u215d', '\u215d', '\u215e', '\u215e', '\u2044', '\u2044', '\u2322', '\u2322', '\U0001d4bb', '\U0001d4bb', '\u2267', '\u2267', '\u2a8c', '\u2a8c', '\u01f5', '\u01f5', '\u03b3', '\u03b3', '\u03dd',
'\u03dd', '\u2a86', '\u2a86', '\u011f', '\u011f', '\u011d', '\u011d', '\u0433', '\u0433', '\u0121', '\u0121', '\u2265', '\u2265', '\u22db', '\u22db', '\u2265', '\u2265', '\u2267', '\u2267', '\u2a7e', '\u2a7e', '\u2a7e', '\u2a7e', '\u2aa9', '\u2aa9', '\u2a80', '\u2a80', '\u2a82', '\u2a82', '\u2a84', '\u2a84', '\u2a94', '\u2a94', '\U0001d524', '\U0001d524', '\u226b', '\u226b', '\u22d9',
'\u22d9', '\u2137', '\u2137', '\u0453', '\u0453', '\u2277', '\u2277', '\u2a92', '\u2a92', '\u2aa5', '\u2aa5', '\u2aa4', '\u2aa4', '\u2269', '\u2269', '\u2a8a', '\u2a8a', '\u2a8a', '\u2a8a', '\u2a88', '\u2a88', '\u2a88', '\u2a88', '\u2269', '\u2269', '\u22e7', '\u22e7', '\U0001d558', '\U0001d558', '\u0060', '\u0060', '\u210a', '\u210a', '\u2273', '\u2273', '\u2a8e', '\u2a8e', '\u2a90', '\u2a90', '\u2aa7',
'\u2aa7', '\u2a7a', '\u2a7a', '\u22d7', '\u22d7', '\u2995', '\u2995', '\u2a7c', '\u2a7c', '\u2a86', '\u2a86', '\u2978', '\u2978', '\u22d7', '\u22d7', '\u22db', '\u22db', '\u2a8c', '\u2a8c', '\u2277', '\u2277', '\u2273', '\u2273', '\u21d4', '\u21d4', '\u200a', '\u200a', '\u00bd', '\u00bd', '\u210b', '\u210b',
'\u044a', '\u044a', '\u2194', '\u2194', '\u2948', '\u2948', '\u21ad', '\u21ad', '\u210f', '\u210f', '\u0125', '\u0125', '\u2665', '\u2665', '\u2665', '\u2665', '\u2026', '\u2026', '\u22b9', '\u22b9', '\U0001d525', '\U0001d525', '\u2925', '\u2925', '\u2926', '\u2926', '\u21ff', '\u21ff', '\u223b', '\u223b', '\u21a9', '\u21a9',
'\u21aa', '\u21aa', '\U0001d559', '\U0001d559', '\u2015', '\u2015', '\U0001d4bd', '\U0001d4bd', '\u210f', '\u210f', '\u0127', '\u0127', '\u2043', '\u2043', '\u2010', '\u2010', '\u00ed', '\u00ed', '\u2063', '\u2063', '\u00ee', '\u00ee', '\u0438', '\u0438', '\u0435', '\u0435', '\u00a1', '\u00a1', '\u21d4', '\u21d4', '\U0001d526', '\U0001d526', '\u00ec', '\u00ec', '\u2148',
'\u2148', '\u2a0c', '\u2a0c', '\u222d', '\u222d', '\u29dc', '\u29dc', '\u2129', '\u2129', '\u0133', '\u0133', '\u012b', '\u012b', '\u2111', '\u2111', '\u2110', '\u2110', '\u2111', '\u2111', '\u0131', '\u0131', '\u22b7', '\u22b7', '\u01b5', '\u01b5', '\u2208', '\u2208', '\u2105', '\u2105', '\u221e', '\u221e', '\u29dd', '\u29dd', '\u0131',
'\u0131', '\u222b', '\u222b', '\u22ba', '\u22ba', '\u2124', '\u2124', '\u22ba', '\u22ba', '\u2a17', '\u2a17', '\u2a3c', '\u2a3c', '\u0451', '\u0451', '\u012f', '\u012f', '\U0001d55a', '\U0001d55a', '\u03b9', '\u03b9', '\u2a3c', '\u2a3c', '\u00bf', '\u00bf', '\U0001d4be', '\U0001d4be', '\u2208', '\u2208', '\u22f9', '\u22f9', '\u22f5', '\u22f5', '\u22f4',
'\u22f4', '\u22f3', '\u22f3', '\u2208', '\u2208', '\u2062', '\u2062', '\u0129', '\u0129', '\u0456', '\u0456', '\u00ef', '\u00ef', '\u0135', '\u0135', '\u0439', '\u0439', '\U0001d527', '\U0001d527', '\u0237', '\u0237', '\U0001d55b', '\U0001d55b', '\U0001d4bf', '\U0001d4bf', '\u0458', '\u0458', '\u0454', '\u0454', '\u03ba', '\u03ba', '\u03f0', '\u03f0', '\u0137', '\u0137', '\u043a', '\u043a', '\U0001d528',
'\U0001d528', '\u0138', '\u0138', '\u0445', '\u0445', '\u045c', '\u045c', '\U0001d55c', '\U0001d55c', '\U0001d4c0', '\U0001d4c0', '\u21da', '\u21da', '\u21d0', '\u21d0', '\u291b', '\u291b', '\u290e', '\u290e', '\u2266', '\u2266', '\u2a8b', '\u2a8b', '\u2962', '\u2962', '\u013a', '\u013a', '\u29b4', '\u29b4', '\u2112', '\u2112', '\u03bb', '\u03bb', '\u27e8', '\u27e8', '\u2991', '\u2991',
'\u27e8', '\u27e8', '\u2a85', '\u2a85', '\u00ab', '\u00ab', '\u2190', '\u2190', '\u21e4', '\u21e4', '\u291f', '\u291f', '\u291d', '\u291d', '\u21a9', '\u21a9', '\u21ab', '\u21ab', '\u2939', '\u2939', '\u2973', '\u2973', '\u21a2', '\u21a2', '\u2aab', '\u2aab', '\u2919', '\u2919', '\u2aad', '\u2aad', '\u290c', '\u290c', '\u2772', '\u2772', '\u007b',
'\u007b', '\u005b', '\u005b', '\u298b', '\u298b', '\u298f', '\u298f', '\u298d', '\u298d', '\u013e', '\u013e', '\u013c', '\u013c', '\u2308', '\u2308', '\u007b', '\u007b', '\u043b', '\u043b', '\u2936', '\u2936', '\u201c', '\u201c', '\u201e', '\u201e', '\u2967', '\u2967', '\u294b', '\u294b', '\u21b2', '\u21b2', '\u2264', '\u2264', '\u2190',
'\u2190', '\u21a2', '\u21a2', '\u21bd', '\u21bd', '\u21bc', '\u21bc', '\u21c7', '\u21c7', '\u2194', '\u2194', '\u21c6', '\u21c6', '\u21cb', '\u21cb', '\u21ad', '\u21ad', '\u22cb',
'\u22cb', '\u22da', '\u22da', '\u2264', '\u2264', '\u2266', '\u2266', '\u2a7d', '\u2a7d', '\u2a7d', '\u2a7d', '\u2aa8', '\u2aa8', '\u2a7f', '\u2a7f', '\u2a81', '\u2a81', '\u2a83', '\u2a83', '\u2a93', '\u2a93', '\u2a85', '\u2a85', '\u22d6', '\u22d6', '\u22da', '\u22da', '\u2a8b', '\u2a8b', '\u2276', '\u2276',
'\u2272', '\u2272', '\u297c', '\u297c', '\u230a', '\u230a', '\U0001d529', '\U0001d529', '\u2276', '\u2276', '\u2a91', '\u2a91', '\u21bd', '\u21bd', '\u21bc', '\u21bc', '\u296a', '\u296a', '\u2584', '\u2584', '\u0459', '\u0459', '\u226a', '\u226a', '\u21c7', '\u21c7', '\u231e', '\u231e', '\u296b', '\u296b', '\u25fa', '\u25fa', '\u0140', '\u0140', '\u23b0', '\u23b0',
'\u23b0', '\u23b0', '\u2268', '\u2268', '\u2a89', '\u2a89', '\u2a89', '\u2a89', '\u2a87', '\u2a87', '\u2a87', '\u2a87', '\u2268', '\u2268', '\u22e6', '\u22e6', '\u27ec', '\u27ec', '\u21fd', '\u21fd', '\u27e6', '\u27e6', '\u27f5', '\u27f5', '\u27f7', '\u27f7', '\u27fc', '\u27fc', '\u27f6',
'\u27f6', '\u21ab', '\u21ab', '\u21ac', '\u21ac', '\u2985', '\u2985', '\U0001d55d', '\U0001d55d', '\u2a2d', '\u2a2d', '\u2a34', '\u2a34', '\u2217', '\u2217', '\u005f', '\u005f', '\u25ca', '\u25ca', '\u25ca', '\u25ca', '\u29eb', '\u29eb', '\u0028', '\u0028', '\u2993', '\u2993', '\u21c6', '\u21c6', '\u231f',
'\u231f', '\u21cb', '\u21cb', '\u296d', '\u296d', '\u200e', '\u200e', '\u22bf', '\u22bf', '\u2039', '\u2039', '\U0001d4c1', '\U0001d4c1', '\u21b0', '\u21b0', '\u2272', '\u2272', '\u2a8d', '\u2a8d', '\u2a8f', '\u2a8f', '\u005b', '\u005b', '\u2018', '\u2018', '\u201a', '\u201a', '\u0142', '\u0142', '\u2aa6', '\u2aa6', '\u2a79', '\u2a79', '\u22d6', '\u22d6', '\u22cb',
'\u22cb', '\u22c9', '\u22c9', '\u2976', '\u2976', '\u2a7b', '\u2a7b', '\u2996', '\u2996', '\u25c3', '\u25c3', '\u22b4', '\u22b4', '\u25c2', '\u25c2', '\u294a', '\u294a', '\u2966', '\u2966', '\u223a', '\u223a', '\u00af', '\u00af', '\u2642', '\u2642', '\u2720', '\u2720', '\u2720', '\u2720', '\u21a6', '\u21a6', '\u21a6', '\u21a6', '\u21a7',
'\u21a7', '\u21a4', '\u21a4', '\u21a5', '\u21a5', '\u25ae', '\u25ae', '\u2a29', '\u2a29', '\u043c', '\u043c', '\u2014', '\u2014', '\u2221', '\u2221', '\U0001d52a', '\U0001d52a', '\u2127', '\u2127', '\u00b5', '\u00b5', '\u2223', '\u2223', '\u002a', '\u002a', '\u2af0', '\u2af0', '\u00b7', '\u00b7', '\u2212', '\u2212', '\u229f',
'\u229f', '\u2238', '\u2238', '\u2a2a', '\u2a2a', '\u2adb', '\u2adb', '\u2026', '\u2026', '\u2213', '\u2213', '\u22a7', '\u22a7', '\U0001d55e', '\U0001d55e', '\u2213', '\u2213', '\U0001d4c2', '\U0001d4c2', '\u223e', '\u223e', '\u03bc', '\u03bc', '\u22b8', '\u22b8', '\u22b8', '\u22b8', '\u21cd', '\u21cd', '\u21ce', '\u21ce', '\u21cf',
'\u21cf', '\u22af', '\u22af', '\u22ae', '\u22ae', '\u2207', '\u2207', '\u0144', '\u0144', '\u2249', '\u2249', '\u0149', '\u0149', '\u2249', '\u2249', '\u266e', '\u266e', '\u266e', '\u266e', '\u2115', '\u2115', '\u00a0', '\u00a0', '\u2a43', '\u2a43', '\u0148', '\u0148', '\u0146', '\u0146', '\u2247', '\u2247', '\u2a42', '\u2a42', '\u043d',
'\u043d', '\u2013', '\u2013', '\u2260', '\u2260', '\u21d7', '\u21d7', '\u2924', '\u2924', '\u2197', '\u2197', '\u2197', '\u2197', '\u2262', '\u2262', '\u2928', '\u2928', '\u2204', '\u2204', '\u2204', '\u2204', '\U0001d52b', '\U0001d52b', '\u2271', '\u2271', '\u2271', '\u2271', '\u2275', '\u2275', '\u226f', '\u226f', '\u226f', '\u226f', '\u21ce', '\u21ce', '\u21ae', '\u21ae',
'\u2af2', '\u2af2', '\u220b', '\u220b', '\u22fc', '\u22fc', '\u22fa', '\u22fa', '\u220b', '\u220b', '\u045a', '\u045a', '\u21cd', '\u21cd', '\u219a', '\u219a', '\u2025', '\u2025', '\u2270', '\u2270', '\u219a', '\u219a', '\u21ae', '\u21ae', '\u2270', '\u2270', '\u226e', '\u226e', '\u2274', '\u2274', '\u226e', '\u226e', '\u22ea', '\u22ea', '\u22ec', '\u22ec',
'\u2224', '\u2224', '\U0001d55f', '\U0001d55f', '\u00ac', '\u00ac', '\u2209', '\u2209', '\u2209', '\u2209', '\u22f7', '\u22f7', '\u22f6', '\u22f6', '\u220c', '\u220c', '\u220c', '\u220c', '\u22fe', '\u22fe', '\u22fd', '\u22fd', '\u2226', '\u2226', '\u2226', '\u2226', '\u2a14', '\u2a14', '\u2280', '\u2280', '\u22e0', '\u22e0', '\u2280',
'\u2280', '\u21cf', '\u21cf', '\u219b', '\u219b', '\u219b', '\u219b', '\u22eb', '\u22eb', '\u22ed', '\u22ed', '\u2281', '\u2281', '\u22e1', '\u22e1', '\U0001d4c3', '\U0001d4c3', '\u2224', '\u2224', '\u2226', '\u2226', '\u2241', '\u2241', '\u2244', '\u2244', '\u2244', '\u2244', '\u2224', '\u2224', '\u2226', '\u2226', '\u22e2',
'\u22e2', '\u22e3', '\u22e3', '\u2284', '\u2284', '\u2288', '\u2288', '\u2288', '\u2288', '\u2281', '\u2281', '\u2285', '\u2285', '\u2289', '\u2289', '\u2289', '\u2289', '\u2279', '\u2279', '\u00f1', '\u00f1', '\u2278', '\u2278', '\u22ea', '\u22ea', '\u22ec', '\u22ec', '\u22eb', '\u22eb',
'\u22ed', '\u22ed', '\u03bd', '\u03bd', '\u0023', '\u0023', '\u2116', '\u2116', '\u2007', '\u2007', '\u22ad', '\u22ad', '\u2904', '\u2904', '\u22ac', '\u22ac', '\u29de', '\u29de', '\u2902', '\u2902', '\u2903', '\u2903', '\u21d6', '\u21d6', '\u2923', '\u2923', '\u2196', '\u2196', '\u2196', '\u2196', '\u2927', '\u2927',
'\u24c8', '\u24c8', '\u00f3', '\u00f3', '\u229b', '\u229b', '\u229a', '\u229a', '\u00f4', '\u00f4', '\u043e', '\u043e', '\u229d', '\u229d', '\u0151', '\u0151', '\u2a38', '\u2a38', '\u2299', '\u2299', '\u29bc', '\u29bc', '\u0153', '\u0153', '\u29bf', '\u29bf', '\U0001d52c', '\U0001d52c', '\u02db', '\u02db', '\u00f2', '\u00f2', '\u29c1', '\u29c1', '\u29b5', '\u29b5', '\u03a9', '\u03a9', '\u222e',
'\u222e', '\u21ba', '\u21ba', '\u29be', '\u29be', '\u29bb', '\u29bb', '\u203e', '\u203e', '\u29c0', '\u29c0', '\u014d', '\u014d', '\u03c9', '\u03c9', '\u03bf', '\u03bf', '\u29b6', '\u29b6', '\u2296', '\u2296', '\U0001d560', '\U0001d560', '\u29b7', '\u29b7', '\u29b9', '\u29b9', '\u2295', '\u2295', '\u2228', '\u2228', '\u21bb', '\u21bb', '\u2a5d', '\u2a5d', '\u2134', '\u2134',
'\u2134', '\u2134', '\u00aa', '\u00aa', '\u00ba', '\u00ba', '\u22b6', '\u22b6', '\u2a56', '\u2a56', '\u2a57', '\u2a57', '\u2a5b', '\u2a5b', '\u2134', '\u2134', '\u00f8', '\u00f8', '\u2298', '\u2298', '\u00f5', '\u00f5', '\u2297', '\u2297', '\u2a36', '\u2a36', '\u00f6', '\u00f6', '\u233d', '\u233d', '\u2225', '\u2225', '\u00b6', '\u00b6', '\u2225', '\u2225',
'\u2af3', '\u2af3', '\u2afd', '\u2afd', '\u2202', '\u2202', '\u043f', '\u043f', '\u0025', '\u0025', '\u002e', '\u002e', '\u2030', '\u2030', '\u22a5', '\u22a5', '\u2031', '\u2031', '\U0001d52d', '\U0001d52d', '\u03c6', '\u03c6', '\u03d5', '\u03d5', '\u2133', '\u2133', '\u260e', '\u260e', '\u03c0', '\u03c0', '\u22d4', '\u22d4', '\u03d6', '\u03d6', '\u210f', '\u210f',
'\u210e', '\u210e', '\u210f', '\u210f', '\u002b', '\u002b', '\u2a23', '\u2a23', '\u229e', '\u229e', '\u2a22', '\u2a22', '\u2214', '\u2214', '\u2a25', '\u2a25', '\u2a72', '\u2a72', '\u00b1', '\u00b1', '\u2a26', '\u2a26', '\u2a27', '\u2a27', '\u00b1', '\u00b1', '\u2a15', '\u2a15', '\U0001d561', '\U0001d561', '\u00a3', '\u00a3', '\u227a',
'\u227a', '\u2ab3', '\u2ab3', '\u2ab7', '\u2ab7', '\u227c', '\u227c', '\u2aaf', '\u2aaf', '\u227a', '\u227a', '\u2ab7', '\u2ab7', '\u227c', '\u227c', '\u2aaf', '\u2aaf', '\u2ab9', '\u2ab9', '\u2ab5', '\u2ab5', '\u22e8', '\u22e8', '\u227e', '\u227e', '\u2032', '\u2032', '\u2119', '\u2119', '\u2ab5', '\u2ab5', '\u2ab9',
'\u2ab9', '\u22e8', '\u22e8', '\u220f', '\u220f', '\u232e', '\u232e', '\u2312', '\u2312', '\u2313', '\u2313', '\u221d', '\u221d', '\u221d', '\u221d', '\u227e', '\u227e', '\u22b0', '\u22b0', '\U0001d4c5', '\U0001d4c5', '\u03c8', '\u03c8', '\u2008', '\u2008', '\U0001d52e', '\U0001d52e', '\u2a0c', '\u2a0c', '\U0001d562', '\U0001d562', '\u2057', '\u2057', '\U0001d4c6', '\U0001d4c6',
'\u210d', '\u210d', '\u2a16', '\u2a16', '\u003f', '\u003f', '\u225f', '\u225f', '\u21db', '\u21db', '\u21d2', '\u21d2', '\u291c', '\u291c', '\u290f', '\u290f', '\u2964', '\u2964', '\u0155', '\u0155', '\u221a', '\u221a', '\u29b3', '\u29b3', '\u27e9', '\u27e9', '\u2992', '\u2992', '\u29a5', '\u29a5', '\u27e9', '\u27e9', '\u00bb',
'\u00bb', '\u2192', '\u2192', '\u2975', '\u2975', '\u21e5', '\u21e5', '\u2920', '\u2920', '\u2933', '\u2933', '\u291e', '\u291e', '\u21aa', '\u21aa', '\u21ac', '\u21ac', '\u2945', '\u2945', '\u2974', '\u2974', '\u21a3', '\u21a3', '\u219d', '\u219d', '\u291a', '\u291a', '\u2236', '\u2236', '\u211a', '\u211a', '\u290d', '\u290d',
'\u2773', '\u2773', '\u007d', '\u007d', '\u005d', '\u005d', '\u298c', '\u298c', '\u298e', '\u298e', '\u2990', '\u2990', '\u0159', '\u0159', '\u0157', '\u0157', '\u2309', '\u2309', '\u007d', '\u007d', '\u0440', '\u0440', '\u2937', '\u2937', '\u2969', '\u2969', '\u201d', '\u201d', '\u201d', '\u201d', '\u21b3', '\u21b3', '\u211c', '\u211c', '\u211b',
'\u211b', '\u211c', '\u211c', '\u211d', '\u211d', '\u25ad', '\u25ad', '\u00ae', '\u00ae', '\u297d', '\u297d', '\u230b', '\u230b', '\U0001d52f', '\U0001d52f', '\u21c1', '\u21c1', '\u21c0', '\u21c0', '\u296c', '\u296c', '\u03c1', '\u03c1', '\u03f1', '\u03f1', '\u2192', '\u2192', '\u21a3', '\u21a3', '\u21c1', '\u21c1',
'\u21c0', '\u21c0', '\u21c4', '\u21c4', '\u21cc', '\u21cc', '\u21c9', '\u21c9', '\u219d', '\u219d', '\u22cc', '\u22cc', '\u02da', '\u02da', '\u2253', '\u2253', '\u21c4', '\u21c4', '\u21cc', '\u21cc', '\u200f',
'\u200f', '\u23b1', '\u23b1', '\u23b1', '\u23b1', '\u2aee', '\u2aee', '\u27ed', '\u27ed', '\u21fe', '\u21fe', '\u27e7', '\u27e7', '\u2986', '\u2986', '\U0001d563', '\U0001d563', '\u2a2e', '\u2a2e', '\u2a35', '\u2a35', '\u0029', '\u0029', '\u2994', '\u2994', '\u2a12', '\u2a12', '\u21c9', '\u21c9', '\u203a', '\u203a', '\U0001d4c7', '\U0001d4c7', '\u21b1',
'\u21b1', '\u005d', '\u005d', '\u2019', '\u2019', '\u2019', '\u2019', '\u22cc', '\u22cc', '\u22ca', '\u22ca', '\u25b9', '\u25b9', '\u22b5', '\u22b5', '\u25b8', '\u25b8', '\u29ce', '\u29ce', '\u2968', '\u2968', '\u211e', '\u211e', '\u015b', '\u015b', '\u201a', '\u201a', '\u227b', '\u227b', '\u2ab4', '\u2ab4', '\u2ab8', '\u2ab8', '\u0161', '\u0161', '\u227d',
'\u227d', '\u2ab0', '\u2ab0', '\u015f', '\u015f', '\u015d', '\u015d', '\u2ab6', '\u2ab6', '\u2aba', '\u2aba', '\u22e9', '\u22e9', '\u2a13', '\u2a13', '\u227f', '\u227f', '\u0441', '\u0441', '\u22c5', '\u22c5', '\u22a1', '\u22a1', '\u2a66', '\u2a66', '\u21d8', '\u21d8', '\u2925', '\u2925', '\u2198', '\u2198', '\u2198', '\u2198', '\u00a7', '\u00a7', '\u003b',
'\u003b', '\u2929', '\u2929', '\u2216', '\u2216', '\u2216', '\u2216', '\u2736', '\u2736', '\U0001d530', '\U0001d530', '\u2322', '\u2322', '\u266f', '\u266f', '\u0449', '\u0449', '\u0448', '\u0448', '\u2223', '\u2223', '\u2225', '\u2225', '\u00ad', '\u00ad', '\u03c3', '\u03c3', '\u03c2', '\u03c2', '\u03c2', '\u03c2', '\u223c', '\u223c', '\u2a6a',
'\u2a6a', '\u2243', '\u2243', '\u2243', '\u2243', '\u2a9e', '\u2a9e', '\u2aa0', '\u2aa0', '\u2a9d', '\u2a9d', '\u2a9f', '\u2a9f', '\u2246', '\u2246', '\u2a24', '\u2a24', '\u2972', '\u2972', '\u2190', '\u2190', '\u2216', '\u2216', '\u2a33', '\u2a33', '\u29e4', '\u29e4', '\u2223', '\u2223', '\u2323', '\u2323', '\u2aaa', '\u2aaa', '\u2aac',
'\u2aac', '\u044c', '\u044c', '\u002f', '\u002f', '\u29c4', '\u29c4', '\u233f', '\u233f', '\U0001d564', '\U0001d564', '\u2660', '\u2660', '\u2660', '\u2660', '\u2225', '\u2225', '\u2293', '\u2293', '\u2294', '\u2294', '\u228f', '\u228f', '\u2291', '\u2291', '\u228f', '\u228f', '\u2291', '\u2291', '\u2290', '\u2290', '\u2292', '\u2292',
'\u2290', '\u2290', '\u2292', '\u2292', '\u25a1', '\u25a1', '\u25a1', '\u25a1', '\u25aa', '\u25aa', '\u25aa', '\u25aa', '\u2192', '\u2192', '\U0001d4c8', '\U0001d4c8', '\u2216', '\u2216', '\u2323', '\u2323', '\u22c6', '\u22c6', '\u2606', '\u2606', '\u2605', '\u2605', '\u03f5', '\u03f5', '\u03d5', '\u03d5', '\u00af',
'\u00af', '\u2282', '\u2282', '\u2ac5', '\u2ac5', '\u2abd', '\u2abd', '\u2286', '\u2286', '\u2ac3', '\u2ac3', '\u2ac1', '\u2ac1', '\u2acb', '\u2acb', '\u228a', '\u228a', '\u2abf', '\u2abf', '\u2979', '\u2979', '\u2282', '\u2282', '\u2286', '\u2286', '\u2ac5', '\u2ac5', '\u228a', '\u228a', '\u2acb', '\u2acb',
'\u2ac7', '\u2ac7', '\u2ad5', '\u2ad5', '\u2ad3', '\u2ad3', '\u227b', '\u227b', '\u2ab8', '\u2ab8', '\u227d', '\u227d', '\u2ab0', '\u2ab0', '\u2aba', '\u2aba', '\u2ab6', '\u2ab6', '\u22e9', '\u22e9', '\u227f', '\u227f', '\u2211', '\u2211', '\u266a', '\u266a', '\u2283', '\u2283', '\u00b9', '\u00b9', '\u00b2',
'\u00b2', '\u00b3', '\u00b3', '\u2ac6', '\u2ac6', '\u2abe', '\u2abe', '\u2ad8', '\u2ad8', '\u2287', '\u2287', '\u2ac4', '\u2ac4', '\u27c9', '\u27c9', '\u2ad7', '\u2ad7', '\u297b', '\u297b', '\u2ac2', '\u2ac2', '\u2acc', '\u2acc', '\u228b', '\u228b', '\u2ac0', '\u2ac0', '\u2283', '\u2283', '\u2287', '\u2287', '\u2ac6',
'\u2ac6', '\u228b', '\u228b', '\u2acc', '\u2acc', '\u2ac8', '\u2ac8', '\u2ad4', '\u2ad4', '\u2ad6', '\u2ad6', '\u21d9', '\u21d9', '\u2926', '\u2926', '\u2199', '\u2199', '\u2199', '\u2199', '\u292a', '\u292a', '\u00df', '\u00df', '\u2316', '\u2316', '\u03c4', '\u03c4', '\u23b4', '\u23b4', '\u0165', '\u0165', '\u0163',
'\u0163', '\u0442', '\u0442', '\u20db', '\u20db', '\u2315', '\u2315', '\U0001d531', '\U0001d531', '\u2234', '\u2234', '\u2234', '\u2234', '\u03b8', '\u03b8', '\u03d1', '\u03d1', '\u03d1', '\u03d1', '\u2248', '\u2248', '\u223c', '\u223c', '\u2009', '\u2009', '\u2248', '\u2248', '\u223c', '\u223c', '\u00fe', '\u00fe', '\u02dc',
'\u02dc', '\u00d7', '\u00d7', '\u22a0', '\u22a0', '\u2a31', '\u2a31', '\u2a30', '\u2a30', '\u222d', '\u222d', '\u2928', '\u2928', '\u22a4', '\u22a4', '\u2336', '\u2336', '\u2af1', '\u2af1', '\U0001d565', '\U0001d565', '\u2ada', '\u2ada', '\u2929', '\u2929', '\u2034', '\u2034', '\u2122', '\u2122', '\u25b5', '\u25b5', '\u25bf', '\u25bf',
'\u25c3', '\u25c3', '\u22b4', '\u22b4', '\u225c', '\u225c', '\u25b9', '\u25b9', '\u22b5', '\u22b5', '\u25ec', '\u25ec', '\u225c', '\u225c', '\u2a3a', '\u2a3a', '\u2a39', '\u2a39', '\u29cd', '\u29cd', '\u2a3b', '\u2a3b', '\u23e2', '\u23e2', '\U0001d4c9',
'\U0001d4c9', '\u0446', '\u0446', '\u045b', '\u045b', '\u0167', '\u0167', '\u226c', '\u226c', '\u219e', '\u219e', '\u21a0', '\u21a0', '\u21d1', '\u21d1', '\u2963', '\u2963', '\u00fa', '\u00fa', '\u2191', '\u2191', '\u045e', '\u045e', '\u016d', '\u016d', '\u00fb', '\u00fb', '\u0443', '\u0443', '\u21c5', '\u21c5', '\u0171',
'\u0171', '\u296e', '\u296e', '\u297e', '\u297e', '\U0001d532', '\U0001d532', '\u00f9', '\u00f9', '\u21bf', '\u21bf', '\u21be', '\u21be', '\u2580', '\u2580', '\u231c', '\u231c', '\u231c', '\u231c', '\u230f', '\u230f', '\u25f8', '\u25f8', '\u016b', '\u016b', '\u00a8', '\u00a8', '\u0173', '\u0173', '\U0001d566', '\U0001d566', '\u2191', '\u2191', '\u2195',
'\u2195', '\u21bf', '\u21bf', '\u21be', '\u21be', '\u228e', '\u228e', '\u03c5', '\u03c5', '\u03d2', '\u03d2', '\u03c5', '\u03c5', '\u21c8', '\u21c8', '\u231d', '\u231d', '\u231d', '\u231d', '\u230e', '\u230e', '\u016f', '\u016f', '\u25f9', '\u25f9', '\U0001d4ca', '\U0001d4ca', '\u22f0', '\u22f0',
'\u0169', '\u0169', '\u25b5', '\u25b5', '\u25b4', '\u25b4', '\u21c8', '\u21c8', '\u00fc', '\u00fc', '\u29a7', '\u29a7', '\u21d5', '\u21d5', '\u2ae8', '\u2ae8', '\u2ae9', '\u2ae9', '\u22a8', '\u22a8', '\u299c', '\u299c', '\u03f5', '\u03f5', '\u03f0', '\u03f0', '\u2205', '\u2205', '\u03d5', '\u03d5', '\u03d6', '\u03d6', '\u221d',
'\u221d', '\u2195', '\u2195', '\u03f1', '\u03f1', '\u03c2', '\u03c2', '\u03d1', '\u03d1', '\u22b2', '\u22b2', '\u22b3', '\u22b3', '\u0432', '\u0432', '\u22a2', '\u22a2', '\u2228', '\u2228', '\u22bb', '\u22bb', '\u225a', '\u225a', '\u22ee', '\u22ee', '\u007c', '\u007c', '\u007c', '\u007c', '\U0001d533',
'\U0001d533', '\u22b2', '\u22b2', '\U0001d567', '\U0001d567', '\u221d', '\u221d', '\u22b3', '\u22b3', '\U0001d4cb', '\U0001d4cb', '\u299a', '\u299a', '\u0175', '\u0175', '\u2a5f', '\u2a5f', '\u2227', '\u2227', '\u2259', '\u2259', '\u2118', '\u2118', '\U0001d534', '\U0001d534', '\U0001d568', '\U0001d568', '\u2118', '\u2118', '\u2240', '\u2240', '\u2240', '\u2240', '\U0001d4cc', '\U0001d4cc', '\u22c2', '\u22c2', '\u25ef',
'\u25ef', '\u22c3', '\u22c3', '\u25bd', '\u25bd', '\U0001d535', '\U0001d535', '\u27fa', '\u27fa', '\u27f7', '\u27f7', '\u03be', '\u03be', '\u27f8', '\u27f8', '\u27f5', '\u27f5', '\u27fc', '\u27fc', '\u22fb', '\u22fb', '\u2a00', '\u2a00', '\U0001d569', '\U0001d569', '\u2a01', '\u2a01', '\u2a02', '\u2a02', '\u27f9', '\u27f9', '\u27f6', '\u27f6', '\U0001d4cd', '\U0001d4cd', '\u2a06', '\u2a06', '\u2a04',
'\u2a04', '\u25b3', '\u25b3', '\u22c1', '\u22c1', '\u22c0', '\u22c0', '\u00fd', '\u00fd', '\u044f', '\u044f', '\u0177', '\u0177', '\u044b', '\u044b', '\u00a5', '\u00a5', '\U0001d536', '\U0001d536', '\u0457', '\u0457', '\U0001d56a', '\U0001d56a', '\U0001d4ce', '\U0001d4ce', '\u044e', '\u044e', '\u00ff', '\u00ff', '\u017a', '\u017a', '\u017e', '\u017e', '\u0437', '\u0437', '\u017c', '\u017c', '\u2128',
'\u2128', '\u03b6', '\u03b6', '\U0001d537', '\U0001d537', '\u0436', '\u0436', '\u21dd', '\u21dd', '\U0001d56b', '\U0001d56b', '\U0001d4cf', '\U0001d4cf', '\u200d', '\u200d', '\u200c', '\u200c', ];























// dom event support, if you want to use it

/// used for DOM events
version(dom_with_events)
alias EventHandler = void delegate(Element handlerAttachedTo, Event event);

/// This is a DOM event, like in javascript. Note that this library never fires events - it is only here for you to use if you want it.
version(dom_with_events)
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

			// stdout.flush();
		}

		enum contextToKeep = 100;

		void markDataDiscardable(size_t p) {

			if(p < contextToKeep)
				return;
			p -= contextToKeep;

			// pretends data[0 .. p] is gone and adjusts future things as if it was still there
			startingLineNumber = getLineNumber(p);
			assert(p >= virtualStartIndex);
			data = data[p - virtualStartIndex .. $];
			virtualStartIndex = p;
		}

		int getLineNumber(size_t p) {
			int line = startingLineNumber;
			assert(p >= virtualStartIndex);
			foreach(c; data[0 .. p - virtualStartIndex])
				if(c == '\n')
					line++;
			return line;
		}


		@property final size_t length() {
			// the parser checks length primarily directly before accessing the next character
			// so this is the place we'll hook to append more if possible and needed.
			if(lastIdx + 1 >= (data.length + virtualStartIndex) && hasMore()) {
				data ~= getMore();
			}
			return data.length + virtualStartIndex;
		}

		final char opIndex(size_t idx) {
			if(idx > lastIdx)
				lastIdx = idx;
			return data[idx - virtualStartIndex];
		}

		final string opSlice(size_t start, size_t end) {
			if(end > lastIdx)
				lastIdx = end;
			// writeln(virtualStartIndex, " " , start, " ", end);
			assert(start >= virtualStartIndex);
			assert(end >= virtualStartIndex);
			return data[start - virtualStartIndex .. end - virtualStartIndex];
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

		int startingLineNumber = 1;
		size_t virtualStartIndex = 0;


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

/++
	Normalizes the whitespace in the given text according to HTML rules.

	History:
		Added March 25, 2022 (dub v10.8)

		The `stripLeadingAndTrailing` argument was added September 13, 2024 (dub v11.6).
+/
string normalizeWhitespace(string text, bool stripLeadingAndTrailing = true) {
	string ret;
	ret.reserve(text.length);
	bool lastWasWhite = stripLeadingAndTrailing;
	foreach(char ch; text) {
		if(ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
			if(lastWasWhite)
				continue;
			lastWasWhite = true;
			ch = ' ';
		} else {
			lastWasWhite = false;
		}

		ret ~= ch;
	}

	if(stripLeadingAndTrailing)
		return ret.stripRight;
	else {
		/+
		if(lastWasWhite && (ret.length == 0 || ret[$-1] != ' '))
			ret ~= ' ';
		+/
		return ret;
	}
}

unittest {
	assert(normalizeWhitespace("    foo   ") == "foo");
	assert(normalizeWhitespace("    f\n \t oo   ") == "f oo");
	assert(normalizeWhitespace("    foo   ", false) == " foo ");
	assert(normalizeWhitespace(" foo ", false) == " foo ");
	assert(normalizeWhitespace("\nfoo", false) == " foo");
}

unittest {
	Document document;

	document = new Document("<test> foo \r </test>");
	assert(document.root.visibleText == "foo");

	document = new Document("<test> foo \r <br>hi</test>");
	assert(document.root.visibleText == "foo\nhi");

	document = new Document("<test> foo \r <br>hi<pre>hi\nthere\n    indent<br />line</pre></test>");
	assert(document.root.visibleText == "foo\nhihi\nthere\n    indent\nline", document.root.visibleText);
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

bool allAreInlineHtml(const(Element)[] children, const string[] inlineElements) {
	foreach(child; children) {
		if(child.nodeType == NodeType.Text && child.nodeValue.strip.length) {
			// cool
		} else if(child.tagName.isInArray(inlineElements) && allAreInlineHtml(child.children, inlineElements)) {
			// cool, this is an inline element and none of its children contradict that
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
		<div id=\"empty\"></div>
		<div id=\"empty-but-text\">test</div>
        </body>
</html>");

	auto doc = document;

	{
	auto empty = doc.requireElementById("empty");
	assert(empty.querySelector(" > *") is null, empty.querySelector(" > *").toString);
	}
	{
	auto empty = doc.requireElementById("empty-but-text");
	assert(empty.querySelector(" > *") is null, empty.querySelector(" > *").toString);
	}

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

unittest {
	// toPrettyString is not stable, but these are some best-effort attempts
	// despite these being in a test, I might change these anyway!
	assert(Element.make("a").toPrettyString == "<a></a>");
	assert(Element.make("a", "").toPrettyString(false, 0, " ") == "<a></a>");
	assert(Element.make("a", " ").toPrettyString(false, 0, " ") == "<a> </a>");//, Element.make("a", " ").toPrettyString(false, 0, " "));
	assert(Element.make("a", "b").toPrettyString == "<a>b</a>");
	assert(Element.make("a", "b").toPrettyString(false, 0, "") == "<a>b</a>");

	{
	auto document = new Document("<html><body><p>hello <a href=\"world\">world</a></p></body></html>");
	auto pretty = document.toPrettyString(false, 0, "  ");
	assert(pretty ==
`<!DOCTYPE html>
<html>
  <body>
    <p>hello <a href="world">world</a></p>
  </body>
</html>`, pretty);
	}

	{
	auto document = new XmlDocument("<html><body><p>hello <a href=\"world\">world</a></p></body></html>");
	assert(document.toPrettyString(false, 0, "  ") ==
`<?xml version="1.0" encoding="UTF-8"?>
<html>
  <body>
    <p>
      hello
      <a href="world">world</a>
    </p>
  </body>
</html>`);
	}

	foreach(test; [
		"<a att=\"http://ele\"><b><ele1>Hello</ele1>\n  <c>\n   <d>\n    <ele2>How are you?</ele2>\n   </d>\n   <e>\n    <ele3>Good &amp; you?</ele3>\n   </e>\n  </c>\n </b>\n</a>",
		"<a att=\"http://ele\"><b><ele1>Hello</ele1><c><d><ele2>How are you?</ele2></d><e><ele3>Good &amp; you?</ele3></e></c></b></a>",
	] )
	{
	auto document = new XmlDocument(test);
	assert(document.root.toPrettyString(false, 0, " ") == "<a att=\"http://ele\">\n <b>\n  <ele1>Hello</ele1>\n  <c>\n   <d>\n    <ele2>How are you?</ele2>\n   </d>\n   <e>\n    <ele3>Good &amp; you?</ele3>\n   </e>\n  </c>\n </b>\n</a>");
	assert(document.toPrettyString(false, 0, " ") == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<a att=\"http://ele\">\n <b>\n  <ele1>Hello</ele1>\n  <c>\n   <d>\n    <ele2>How are you?</ele2>\n   </d>\n   <e>\n    <ele3>Good &amp; you?</ele3>\n   </e>\n  </c>\n </b>\n</a>");
	auto omg = document.root;
	omg.parent_ = null;
	assert(omg.toPrettyString(false, 0, " ") == "<a att=\"http://ele\">\n <b>\n  <ele1>Hello</ele1>\n  <c>\n   <d>\n    <ele2>How are you?</ele2>\n   </d>\n   <e>\n    <ele3>Good &amp; you?</ele3>\n   </e>\n  </c>\n </b>\n</a>");
	}

	{
	auto document = new XmlDocument(`<a><b>toto</b><c></c></a>`);
	assert(document.root.toPrettyString(false, 0, null) == `<a><b>toto</b><c></c></a>`);
	assert(document.root.toPrettyString(false, 0, " ") == `<a>
 <b>toto</b>
 <c></c>
</a>`);
	}

	{
auto str = `<!DOCTYPE html>
<html>
	<head>
		<title>Test</title>
	</head>
	<body>
		<p>Hello there</p>
		<p>I like <a href="">Links</a></p>
		<div>
			this is indented since there's a block inside
			<p>this is the block</p>
			and this gets its own line
		</div>
	</body>
</html>`;
		auto doc = new Document(str, true, true);
		assert(doc.toPrettyString == str);
	}
}

unittest {
	auto document = new Document("<foo><items><item><title>test</title><desc>desc</desc></item></items></foo>");
	auto items = document.root.requireSelector("> items");
	auto item = items.requireSelector("> item");
	auto title = item.requireSelector("> title");

	// this not actually implemented at this point but i might want to later. it prolly should work as an extension of the standard behavior
	// assert(title.requireSelector("~ desc").innerText == "desc");

	assert(item.requireSelector("title ~ desc").innerText == "desc");

	assert(items.querySelector("item:has(title)") !is null);
	assert(items.querySelector("item:has(nothing)") is null);

	assert(title.innerText == "test");
}

unittest {
	auto document = new Document("broken"); // just ensuring it doesn't crash
}


/*
Copyright: Adam D. Ruppe, 2010 - 2023
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions by Nick Sabalausky, Trass3r, and ketmar among others
*/
