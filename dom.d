module arsd.dom;

import std.string;
// import std.ascii;
import std.exception;

import std.uri;
import std.array;

import std.stdio;

// Biggest (known) fixme left for "tag soup": <p> .... <p> in loose mode should close it on the second opening.
// Biggest FIXME for real documents: character set encoding detection

// Should I support Element.dataset? it does dash to camelcase for attribute "data-xxx-xxx"

/*
	To pwn haml, it might be interesting to add a

	getElementBySelectorAndMakeIfNotThere

	It first does querySelector. If null, find the path that was closest to matching using
	the weight rules or the left to right reading, whatever gets close.

	Then make the elements so it works and return the first matching element.


	virtual Element setMainPart() {} // usually does innertext but can be overridden by certain elements


	The haml converter produces a mixin string that does getElementBySelectorAndMakeIfNotThere and calls
	setMainPart on it. boom.
*/

///.
T[] insertAfter(T)(T[] arr, int position, T[] what) {
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

///.
bool isInArray(T)(T item, T[] arr) {
	foreach(i; arr)
		if(item == i)
			return true;
	return false;
}

///.
class Stack(T) {

	///.
	void push(T t) {
		arr ~= t;
	}

	///.
	T pop() {
		assert(arr.length);
		T tmp = arr[$-1];
		arr.length = arr.length - 1;
		return tmp;
	}

	///.
	T peek() {
		return arr[$-1];
	}

	///.
	bool empty() {
		return arr.length ? false : true;
	}

	///.
	T[] arr;
}

///.
class ElementStream {

	///.
	Element front() {
		return current.element;
	}

	///.
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

	///.
	void currentKilled() {
		if(stack.empty) // should never happen
			isEmpty = true;
		else {
			current = stack.pop();
			current.childPosition--; // when it is killed, the parent is brought back a lil so when we popFront, this is then right
		}
	}

	///.
	bool empty() {
		return isEmpty;
	}

	///.
	struct Current {
		Element element;
		int childPosition;
	}

	///.
	Current current;

	///.
	Stack!(Current) stack;

	///.
	bool isEmpty;
}

///.
string[string] dup(in string[string] arr) {
	string[string] ret;
	foreach(k, v; arr)
		ret[k] = v;
	return ret;
}

/*
	swapNode
	cloneNode
*/
///.
class Element {

	///.
	Element[] children;

	///.
	string tagName;

	///.
	string[string] attributes;

	///.
	bool selfClosed;

	///.
	Document parentDocument;

	///.
	this(Document _parentDocument, string _tagName, string[string] _attributes = null, bool _selfClosed = false) {
		parentDocument = _parentDocument;
		tagName = _tagName;
		if(_attributes !is null)
			attributes = _attributes;
		selfClosed = _selfClosed;
	}

	///.
	@property Element previousSibling(string tagName = null) {
		if(this.parentNode is null)
			return null;
		Element ps = null;
		foreach(e; this.parentNode.childNodes) {
			if(e is this)
				break;
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
			if(mightBe)
				if(tagName is null || e.tagName == tagName) {
					ns = e;
					break;
				}
		}

		return ns;
	}


	// if you change something here, it won't apply... FIXME const? but changing it would be nice if it applies to the style attribute too though you should use style there.
	///.
	@property CssStyle computedStyle() {
		if(_computedStyle is null) {
			auto style = this.getAttribute("style");
		/* we'll treat shitty old html attributes as css here */
			if(this.hasAttribute("width"))
				style ~= "; width: " ~ this.width;
			if(this.hasAttribute("height"))
				style ~= "; width: " ~ this.height;
			if(this.hasAttribute("bgcolor"))
				style ~= "; background-color: " ~ this.bgcolor;
			if(this.tagName == "body" && this.hasAttribute("text"))
				style ~= "; color: " ~ this.text;
			if(this.hasAttribute("color"))
				style ~= "; color: " ~ this.color;
		/* done */


			_computedStyle = new CssStyle(null, style); // gives at least something to work with
		}
		return _computedStyle;
	}

	private CssStyle _computedStyle;

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

	///.
	@property Element cloned() {
		auto e = new Element(parentDocument, tagName, attributes.dup, selfClosed);
		foreach(child; children) {
			e.appendChild(child.cloned);
		}

		return e;
	}

	/// Returns the first child of this element. If it has no children, returns null.
	@property Element firstChild() {
		return children.length ? children[0] : null;
	}

	@property Element lastChild() {
		return children.length ? children[$ - 1] : null;
	}

	/// Convenience constructor when you don't care about the parentDocument. Note this might break things on the document.
	/// Note also that without a parent document, elements are always in strict, case-sensitive mode.
	this(string _tagName, string[string] _attributes = null) {
		tagName = _tagName;
		if(_attributes !is null)
			attributes = _attributes;
		selfClosed = tagName.isInArray(selfClosedElements);
	}

	/*
	private this() {

	}
	*/

	private this(Document _parentDocument) {
		parentDocument = _parentDocument;
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

    public:
    	/// Appends the given element to this one. The given element must not have a parent already.
	Element appendChild(Element e)
		in {
			assert(e !is null);
			assert(e.parentNode is null);
		}
		out (ret) {
			assert(e.parentNode is this);
			assert(e is ret);
		}
	body {
		selfClosed = false;
		e.parentNode = this;
		e.parentDocument = this.parentDocument;
		children ~= e;
		return e;
	}

	/// Inserts the second element to this node, right before the first param
	Element insertBefore(Element where, Element what)
		in {
			assert(where !is null);
			assert(where.parentNode is this);
			assert(what !is null);
			assert(what.parentNode is null);
		}
		out (ret) {
			assert(where.parentNode is this);
			assert(what.parentNode is this);
			assert(ret is what);
		}
	body {
		foreach(i, e; children) {
			if(e is where) {
				children = children[0..i] ~ what ~ children[i..$];
				what.parentNode = this;
				return what;
			}
		}

		return what;

		assert(0);
	}

	///.
	Element insertAfter(Element where, Element what)
		in {
			assert(where !is null);
			assert(where.parentNode is this);
			assert(what !is null);
			assert(what.parentNode is null);
		}
		out (ret) {
			assert(where.parentNode is this);
			assert(what.parentNode is this);
			assert(ret is what);
		}
	body {
		foreach(i, e; children) {
			if(e is where) {
				children = children[0 .. i + 1] ~ what ~ children[i + 1 .. $];
				what.parentNode = this;
				return what;
			}
		}

		return what;

		assert(0);
	}


	/// convenience function to quickly add a tag with some text or
	/// other relevant info (for example, it's a src for an <img> element
	/// instead of inner text)
	Element addChild(string tagName, string childInfo = null, string childInfo2 = null) {
		auto e = parentDocument.createElement(tagName);
		if(childInfo !is null)
			switch(tagName) {
				case "img":
					e.src = childInfo;
					if(childInfo2 !is null)
						e.alt = childInfo2;
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
				default:
					e.innerText = childInfo;
			}
		return appendChild(e);
	}

	///.
	Element addChild(string tagName, Element firstChild)
	in {
		assert(parentDocument !is null);
		assert(firstChild !is null);
	}
	out(ret) {
		assert(ret !is null);
		assert(ret.parentNode is this);
		assert(firstChild.parentNode is ret);
	}
	body {
		auto e = parentDocument.createElement(tagName);
		e.appendChild(firstChild);
		this.appendChild(e);
		return e;
	}

	Element addChild(string tagName, Html innerHtml)
	in {
		assert(parentDocument !is null);
	}
	out(ret) {
		assert(ret !is null);
		assert(ret.parentNode is this);
	}
	body {
		auto e = parentDocument.createElement(tagName);
		this.appendChild(e);
		e.innerHTML = innerHtml.source;
		return e;
	}

	///.
	T getParent(T)(string tagName = null) if(is(T : Element)) {
		if(tagName is null) {
			static if(is(T == Form))
				tagName = "form";
			else static if(is(T == Table))
				tagName = "table";
			else static if(is(T == Table))
				tagName == "a";
		}

		auto par = this.parentNode;
		while(par !is null) {
			if(tagName is null || par.tagName == tagName)
				break;
			par = par.parentNode;
		}

		auto t = cast(T) par;
		if(t is null)
			throw new ElementNotFoundException("", tagName ~ " parent not found");

		return t;
	}

	/// swaps one child for a new thing. Returns the old child which is now parentless.
	Element swapNode(Element child, Element replacement) {
		foreach(ref c; this.children)
			if(c is child) {
				c.parentNode = null;
				c = replacement;
				c.parentNode = this;
				return child;
			}
		assert(0);
	}


	///.
	Element getElementById(string id) {
		foreach(e; tree)
			if(e.id == id)
				return e;
		return null;
	}

	///.
	final SomeElementType requireElementById(SomeElementType = Element)(string id)
	if(
		is(SomeElementType : Element)
	)
	out(ret) {
		assert(ret !is null);
	}
	body {
		auto e = cast(SomeElementType) getElementById(id);
		if(e is null)
			throw new ElementNotFoundException(SomeElementType.stringof, "id=" ~ id);
		return e;
	}

	///.
	final SomeElementType requireSelector(SomeElementType = Element)(string selector)
	if(
		is(SomeElementType : Element)
	)
	out(ret) {
		assert(ret !is null);
	}
	body {
		auto e = cast(SomeElementType) querySelector(selector);
		if(e is null)
			throw new ElementNotFoundException(SomeElementType.stringof, selector);
		return e;
	}

	///.
	Element querySelector(string selector) {
		// FIXME: inefficient
		auto list = getElementsBySelector(selector);
		if(list.length == 0)
			return null;
		return list[0];
	}

	/// a more standards-compliant alias for getElementsBySelector
	Element[] querySelectorAll(string selector) {
		return getElementsBySelector(selector);
	}

	///.
	Element[] getElementsBySelector(string selector) {
		if(parentDocument && parentDocument.loose)
			selector = selector.toLower;

		Element[] ret;
		foreach(sel; parseSelectorString(selector))
			ret ~= sel.getElements(this);
		return ret;
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

	///.
	Element appendText(string text) {
		Element e = new TextNode(parentDocument, text);
		return appendChild(e);
	}

	///.
	@property Element[] childElements() {
		Element[] ret;
		foreach(c; children)
			if(c.nodeType == 1)
				ret ~= c;
		return ret;
	}

	/*
		Does a CSS selector

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

	/// Appends the given html to the element, returning the elements appended
	Element[] appendHtml(string html) {
		Document d = new Document("<root>" ~ html ~ "</root>");
		return stealChildren(d.root);
	}

	///.
	Element addClass(string c) {
		string cn = getAttribute("class");
		if(cn is null) {
			setAttribute("class", c);
			return this;
		} else {
			setAttribute("class", cn ~ " " ~ c);
		}

		return this;
	}

	///.
	Element removeClass(string c) {
		auto cn = className;

		className = cn.replace(c, "").strip;

		return this;
	}

	///.
	bool hasClass(string c) {
		auto cn = className;

		int idx = cn.indexOf(c);
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

	///.
	void reparent(Element newParent)
		in {
			assert(newParent !is null);
			assert(parentNode !is null);
		}
		out {
			assert(this.parentNode == newParent);
			assert(isInArray(this, newParent.children));
		}
	body {
		parentNode.removeChild(this);
		newParent.appendChild(this);
	}

	///.
	void insertChildAfter(Element child, Element where)
		in {
			assert(child !is null);
			assert(where !is null);
			assert(where.parentNode is this);
			assert(!selfClosed);
			assert(isInArray(where, children));
		}
		out {
			assert(child.parentNode is this);
			assert(where.parentNode is this);
			assert(isInArray(where, children));
			assert(isInArray(child, children));
		}
	body {
		foreach(i, c; children) {
			if(c is where) {
				i++;
				children = children[0..i] ~ child ~ children[i..$];
				child.parentNode = this;
				break;
			}
		}
	}

	///.
	Element[] stealChildren(Element e, Element position = null)
		in {
			assert(!selfClosed);
			assert(e !is null);
			if(position !is null)
				assert(isInArray(position, children));
		}
		out {
			assert(e.children.length == 0);
		}
	body {
		foreach(c; e.children)
			c.parentNode = this;
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

		auto ret = e.children.dup;
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
			assert(children[0] is e);
		}
	body {
		e.parentNode = this;
		children = e ~ children;
		return e;
	}


	/**
		Provides easy access to attributes, like in javascript
	*/
		// name != "popFront" is so duck typing doesn't think it's a range
	string opDispatch(string name)(string v = null) if(name != "popFront") {
		if(v !is null)
			setAttribute(name, v);
		return getAttribute(name);
	}

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


	// should return int
	///.
	@property int nodeType() const {
		return 1;
	}

	/**
		Returns a string containing all child elements, formatted such that it could be pasted into
		an XML file.
	*/
	@property string innerHTML() const {
		string s = "";
		if(children is null) {
			assert(s !is null);
			return s;
		}
		foreach(child; children) {
			assert(child !is null);
			auto ts = child.toString();
			assert(ts !is null);
			s ~= ts;
		}

		assert(s !is null);

		return s;
	}

	/**
		Takes some html and replaces the element's children with the tree made from the string.
	*/
	@property void innerHTML(string html) {
		if(html.length)
			selfClosed = false;

		auto doc = new Document();
		doc.parse("<innerhtml>" ~ html ~ "</innerhtml>"); // FIXME: this should preserve the strictness of the parent document

		children = doc.root.children;
		foreach(c; children) {
			c.parentNode = this;
		}

		auto newpd = this.parentDocument;
		foreach(c; this.tree) {
			c.parentDocument = newpd;
		}

		doc.root.children = null;
	}

	/// ditto
	@property void innerHTML(Html html) {
		this.innerHTML = html.source;
	}

	/**
		Replaces this node with the given html string, which is parsed

		Note: this invalidates the this reference, since it is removed
		from the tree.

		Returns the new children that replace this.
	*/
	@property Element[] outerHTML(string html) {
		auto doc = new Document();
		doc.parse("<innerhtml>" ~ html ~ "</innerhtml>"); // FIXME: needs to preserve the strictness

		children = doc.root.children;
		foreach(c; children) {
			c.parentNode = this;
		}


		stripOut();

		return doc.root.children;
	}

	///.
	@property string outerHTML() {
		return this.toString();
	}

	///.
	@property void innerRawSource(string rawSource) {
		children.length = 0;
		auto rs = new RawSource(parentDocument, rawSource);
		rs.parentNode = this;

		children ~= rs;
	}

	/**
		Gets the given attribute value, or null if the
		attribute is not set.

		Note that the returned string is decoded, so it no longer contains any xml entities.
	*/
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
	Element setAttribute(string name, string value) {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();

		// I never use this shit legitimately and neither should you
		if(name.toLower == "href" || name.toLower == "src") {
			if(value.strip.toLower.startsWith("vbscript:"))
				value = value[9..$];
			if(value.strip.toLower.startsWith("javascript:"))
				value = value[11..$];
		}

		attributes[name] = value;

		return this;
	}

	/**
		Extension
	*/
	bool hasAttribute(string name) {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();

		if(name in attributes)
			return true;
		else
			return false;
	}

	/**
		Extension
	*/
	void removeAttribute(string name) {
		if(parentDocument && parentDocument.loose)
			name = name.toLower();
		if(name in attributes)
			attributes.remove(name);
	}

	/**
		Gets the class attribute's contents. Returns
		an empty string if it has no class.
	*/
	string className() const {
		auto c = getAttribute("class");
		if(c is null)
			return "";
		return c;
	}

	///.
	Element className(string c) {
		setAttribute("class", c);
		return this;
	}

	///.
	string nodeValue() const {
		return "";
	}

	///.
	Element replaceChild(Element find, Element replace) 
		in {
			assert(find !is null);
			assert(replace !is null);
			assert(replace.parentNode is null);
		}
		out {
			assert(replace.parentNode is this);
			assert(find.parentNode is null);
		}
	body {
		for(int i = 0; i < children.length; i++) {
			if(children[i] is find) {
				replace.parentNode = this;
				children[i].parentNode = null;
				children[i] = replace;
				return replace;
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
			foreach(child; children)
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

	///.
	Element[] removeChildren()
		out (ret) {
			assert(children.length == 0);
			foreach(r; ret)
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
		EXTENSION

		Replaces the given element with a whole group.
	*/
	void replaceChild(Element find, Element[] replace)
		in {
			assert(find !is null);
			assert(replace !is null);
			assert(find.parentNode is this);
			foreach(r; replace)
				assert(r.parentNode is null);
		}
		out {
			assert(find.parentNode is null);
			assert(children.length >= replace.length);
			foreach(child; children)
				assert(child !is find);
			foreach(r; replace)
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
				children = .insertAfter(children, i, replace[1..$]);
				foreach(e; replace)
					e.parentNode = this;
				return;
			}
		}

		throw new Exception("no such child");
	}

	///.
	Element parentNode;

	/**
		Strips this tag out of the document, putting its inner html
		as children of the parent.
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

	Element replaceWith(Element e) {
		if(e.parentNode !is null)
			e.parentNode.removeChild(e);
		this.parentNode.replaceChild(this, e);
		return e;
	}

	/**
		INCOMPATIBLE -- extension

		Splits the className into an array of each class given
	*/
	string[] classNames() const {
		return className().split(" ");
	}

	/**
		Fetches the first consecutive text nodes, concatenated together
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
		Fetch the inside text, with all tags stripped out
	*/
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

	/**
		Sets the inside text, replacing all children
	*/
	@property void innerText(string text) {
		assert(!selfClosed);
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
		Same result as innerText; the tag with all tags stripped out
	*/
	@property string outerText() const {
		return innerText();
	}


	invariant () {
		if(children !is null)
		foreach(child; children) {
		//	assert(parentNode !is null);
			assert(child !is null);
			assert(child.parentNode is this, format("%s is not a parent of %s (it thought it was %s)", tagName, child.tagName, child.parentNode is null ? "null" : child.parentNode.tagName));
			assert(child !is this);
			assert(child !is parentNode);
		}

		//assert(parentDocument !is null); // no more; if it is present, we use it, but it is not required
		// reason is so you can create these without needing a reference to the document
	}

	/**
		Turns the whole element, including tag, attributes, and children, into a string which could be pasted into
		an XML file.
	*/
	override string toString() const {
		assert(tagName !is null);
		string s = "<" ~ tagName;

		foreach(n, v ; attributes) {
			assert(n !is null);
			//assert(v !is null);
			s ~= " " ~ n ~ "=\"" ~ htmlEntitiesEncode(v) ~ "\"";
		}

		if(selfClosed){
			s ~= " />";
			return s;
		}

		s ~= ">";

		s ~= innerHTML();

		s ~= "</" ~ tagName ~ ">";

		assert(s !is null);

		return s;
	}

	/**
		Returns a lazy range of all its children, recursively.
	*/
	ElementStream tree() {
		return new ElementStream(this);
	}
}

///.
class DocumentFragment : Element {
	///.
	this(Document _parentDocument) {
		tagName = "#fragment";
		super(_parentDocument);
	}

	///.
	override string toString() const {
		return this.innerHTML;
	}
}

///.
string htmlEntitiesEncode(string data) {
	char[] output = "".dup;
	foreach(dchar d; data) {
		if(d == '&')
			output ~= "&amp;";
		else if (d == '<')
			output ~= "&lt;";
		else if (d == '>')
			output ~= "&gt;";
		else if (d == '\"')
			output ~= "&quot;";
		else if (d < 128 && d > 0)
			output ~= d;
		else
			output ~= "&#" ~ std.conv.to!string(cast(int) d) ~ ";";
	}

	//assert(output !is null); // this fails on empty attributes.....
	return assumeUnique(output);

//	data = data.replace("\u00a0", "&nbsp;");
}

///.
string xmlEntitiesEncode(string data) {
	return htmlEntitiesEncode(data);
}

///.
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
		// the next are html rather than xml
		/*
		case "cent":
		case "pound":
		case "sect":
		case "deg":
		case "micro"
		*/
		case "laquo":
			return '\u00ab';
		case "raquo":
			return '\u00bb';
		case "lsquo":
			return '\u2018';
		case "rsquo":
			return '\u2019';
		case "ldquo":
			return '\u201c';
		case "rdquo":
			return '\u201d';
		case "reg":
			return '\u00ae';
		case "trade":
			return '\u2122';
		case "nbsp":
			return '\u00a0';
		case "amp":
			return '&';
		case "copy":
			return '\u00a9';
		case "eacute":
			return '\u00e9';
		case "mdash":
			return '\u2014';
		// and handling numeric entities
		default:
			if(entity[1] == '#') {
				if(entity[2] == 'x' /*|| (!strict && entity[2] == 'X')*/) {
					auto hex = entity[3..$-1];

					auto p = intFromHex(to!string(hex).toLower());
					return cast(dchar) p;
				} else {
					auto decimal = entity[2..$-1];

					auto p = std.conv.to!int(decimal);
					return cast(dchar) p;
				}
			} else
				return '?';
	}

	assert(0);
}

import std.utf;

///.
string htmlEntitiesDecode(string data, bool strict = false) {
	dchar[] a;

	bool tryingEntity = false;
	dchar[] entityBeingTried;
	int entityAttemptIndex = 0;

	foreach(dchar ch; data) {
		if(tryingEntity) {
			entityAttemptIndex++;
			entityBeingTried ~= ch;

			if(ch == ';') {
				tryingEntity = false;
				a ~= parseEntity(entityBeingTried);
			} else {
				if(entityAttemptIndex >= 7) {
					if(strict)
						throw new Exception("unterminated entity at " ~ to!string(entityBeingTried));
					else {
						tryingEntity = false;
						a ~= entityBeingTried;
					}
				}
			}
		} else {
			if(ch == '&') {
				tryingEntity = true;
				entityBeingTried = null;
				entityBeingTried ~= ch;
				entityAttemptIndex = 0;
			} else {
				a ~= ch;
			}
		}
	}

	return std.conv.to!string(a);
}

///.
class RawSource : Element {

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
	override int nodeType() const {
		return 100;
	}

	///.
	override string toString() const {
		return source;
	}

	///.
	override Element appendChild(Element e) {
		assert(0, "Cannot append to a text node");
	}


	///.
	string source;
}

///.
enum NodeType { Text = 3}

///.
class TextNode : Element {
  public:
	///.
	this(Document _parentDocument, string e) {
		super(_parentDocument);
		contents = e;
		tagName = "#text";
	}

	///.
	static TextNode fromUndecodedString(Document _parentDocument, string html) {
		auto e = new TextNode(_parentDocument, "");
		e.contents = htmlEntitiesDecode(html, _parentDocument is null ? false : !_parentDocument.loose);
		return e;
	}

	///.
	override @property Element cloned() {
		return new TextNode(parentDocument, contents);
	}

	///.
	override string nodeValue() const {
		return this.contents; //toString();
	}

	///.
	override int nodeType() const {
		return NodeType.Text;
	}

	///.
	override string toString() const {
		string s;
		if(contents.length)
			s = htmlEntitiesEncode(contents);
		else
			s = "";

		assert(s !is null);
		return s;
	}

	///.
	override Element appendChild(Element e) {
		assert(0, "Cannot append to a text node");
	}

	///.
	string contents;
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

		int ques = href.indexOf("?");
		string str = "";
		if(ques != -1) {
			str = href[ques+1..$];

			int fragment = str.indexOf("#");
			if(fragment != -1)
				str = str[0..fragment];
		}

		string[] variables = str.split("&");

		string[string] hash;

		foreach(var; variables) {
			int index = var.indexOf("=");
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

		int question = href.indexOf("?");
		if(question != -1)
			href = href[0..question];

		string frag = "";
		int fragment = href.indexOf("#");
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
	void setValue(string name, string variable) {
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

	// FIXME: doesn't handle arrays; multiple fields can have the same name

	/// Set's the form field's value. For input boxes, this sets the value attribute. For
	/// textareas, it sets the innerText. For radio boxes and select boxes, it removes
	/// the checked/selected attribute from all, and adds it to the one matching the value.
	/// For checkboxes, if the value is non-null and not empty, it checks the box.

	/// If you set a value that doesn't exist, it throws an exception if makeNew is false.
	/// Otherwise, it makes a new input with type=hidden to keep the value.
	void setValue(string field, string value, bool makeNew = true) {
		auto eles = getField(field);
		if(eles.length == 0) {
			if(makeNew) {
				addField(field, value);
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
							if(value.length)
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
						addChild("option", value)
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
	Element addField(string name, string value, string type = "hidden") {
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

	///.
	Element th(T)(T t) {
		assert(parentDocument !is null);
		Element e = parentDocument.createElement("th");
		static if(is(T == Html))
			e.innerHTML = t;
		else
			e.innerText = to!string(t);
		return e;
	}

	///.
	Element td(T)(T t) {
		assert(parentDocument !is null);
		Element e = parentDocument.createElement("td");
		static if(is(T == Html))
			e.innerHTML = t;
		else
			e.innerText = to!string(t);
		return e;
	}

	///.
	Element appendRow(T...)(T t) {
		assert(parentDocument !is null);

		Element row = parentDocument.createElement("tr");

		foreach(e; t) {
			static if(is(typeof(e) : Element)) {
				if(e.tagName == "td" || e.tagName == "th")
					row.appendChild(e);
				else {
					Element a = parentDocument.createElement("td");

					a.appendChild(e);

					row.appendChild(a);
				}
			} else static if(is(typeof(e) == Html)) {
				Element a = parentDocument.createElement("td");
				a.innerHTML = e.source;
				row.appendChild(a);
			} else {
				Element a = parentDocument.createElement("td");
				a.innerText = to!string(e);
				row.appendChild(a);
			}
		}

		foreach(e; children) {
			if(e.tagName == "tbody") {
				e.appendChild(row);
				goto done;
			}
		}

		appendChild(row);

	    done:
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
			cap = parentDocument.createElement("caption");
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
}


///.
class MarkupError : Exception {

	///.
	this(string message) {
		super(message);
	}
}

///.
class ElementNotFoundException : Exception {

	///.
	this(string type, string search) {
		super("Element of type '"~type~"' matching {"~search~"} not found.");
	}
}

/// The html struct is used to differentiate between regular text nodes and html in certain functions
struct Html {
	///.
	string source;
}

///.
class Document {
	///.
	this(string data, bool caseSensitive = false, bool strict = false) {
		parse(data, caseSensitive, strict);
	}

	/**
		Creates an empty document. It has *nothing* in it at all.
	*/
	this() {

	}

	/// Concatenates any consecutive text nodes
	/*
	void normalize() {
		
	}
	*/

	/**
		Take XMLish* data and try to make the DOM tree out of it.

		The goal isn't to be perfect, but to just be good enough to
		approximate Javascript's behavior.

		If strict, it throws on something that doesn't make sense.
		(Examples: mismatched tags. It doesn't validate!)
		If not strict, it tries to recover anyway, and only throws
		when something is REALLY unworkable.

		If strict is false, it uses a magic list of tags that needn't
		be closed. If you are writing a document specifically for this,
		try to avoid such - use self closed tags at least. Easier to parse.

		* The xml version at the top really shouldn't be there...
	*/
	void parse(/*in */string data, bool caseSensitive = false, bool strict = false) {
		// go through character by character.
		// if you see a <, consider it a tag.
		// name goes until the first non tagname character
		// then see if it self closes or has an attribute

		// if not in a tag, anything not a tag is a big text
		// node child. It ends as soon as it sees a <

		// Whitespace in text or attributes is preserved, but not between attributes

		// &amp; and friends are converted when I know them, left the same otherwise

		try {
			validate(data); // it *must* be UTF-8 for this to work correctly
		} catch (Throwable t) {
			if(strict)
			throw new MarkupError("This document is not UTF-8.");
			else {
				string newData;
				foreach(char c; data)
					if(c < 128)
						newData ~= cast(char) c;
				data = newData;
			}
		}

		int pos = 0;

		clear();

		loose = !caseSensitive;

		bool sawImproperNesting = false;

		int getLineNumber(int p) {
			int line = 1;
			foreach(c; data[0..p])
				if(c == '\n')
					line++;
			return line;
		}

		void parseError(string message) {
			throw new MarkupError(format("char %d (line %d): %s", pos, getLineNumber(pos), message));
		}

		void eatWhitespace() {
			while(pos < data.length && (data[pos] == ' ' || data[pos] == '\n' || data[pos] == '\t'))
				pos++;
		}

		string readTagName() {
			// remember to include : for namespaces
			// basically just keep going until >, /, or whitespace
			int start = pos;
			while(  data[pos] != '>' && data[pos] != '/' &&
				data[pos] != ' ' && data[pos] != '\n' && data[pos] != '\t')
				pos++;

			if(!caseSensitive)
				return toLower(data[start..pos]);
			else
				return data[start..pos];
		}

		string readAttributeName() {
			// remember to include : for namespaces
			// basically just keep going until >, /, or whitespace
			int start = pos;
			while(  data[pos] != '>' && data[pos] != '/'  && data[pos] != '=' &&
				data[pos] != ' ' && data[pos] != '\n' && data[pos] != '\t')
				pos++;

			if(!caseSensitive)
				return toLower(data[start..pos]);
			else
				return data[start..pos];
		}

		string readAttributeValue() {
			switch(data[pos]) {
				case '\'':
				case '"':
					char end = data[pos];
					pos++;
					int start = pos;
					while(data[pos] != end)
						pos++;
					string v = htmlEntitiesDecode(data[start..pos], strict);
					pos++; // skip over the end
				return v;
				default:
					if(strict)
						parseError("Attributes must be quoted");
					// read until whitespace or terminator (/ or >)
					int start = pos;
					while(data[pos] != '>' && data[pos] != '/' &&
					      data[pos] != ' ' && data[pos] != '\n' && data[pos] != '\t')
					      	pos++;

					string v = htmlEntitiesDecode(data[start..pos], strict);
					// don't skip the end - we'll need it later
					return v;
			}
		}

		TextNode readTextNode() {
			int start = pos;
			while(pos < data.length && data[pos] != '<') {
				pos++;
			}

			return TextNode.fromUndecodedString(this, data[start..pos]);
		}

		RawSource readCDataNode() {
			int start = pos;
			while(pos < data.length && data[pos] != '<') {
				pos++;
			}

			return new RawSource(this, data[start..pos]);
		}

		char readEntity() {
			return ' ';
		}

		string readComment() {
			return "";
		}

		string readScript() {
			return "";
		}


		struct Ele {
			int type; // element or closing tag or nothing
			Element element; // for type == 0
			string payload; // for type == 1
		}
		// recursively read a tag
		Ele readElement(string[] parentChain = null) {
			if(!strict && parentChain is null)
				parentChain = [];

			if(pos >= data.length)
				if(strict) {
					throw new MarkupError("Gone over the input (is there no root element?), chain: " ~ to!string(parentChain));
				} else {
					if(parentChain.length)
						return Ele(1, null, parentChain[0]); // in loose mode, we just assume the document has ended
					else
						return Ele(4); // signal emptiness upstream
				}

			if(data[pos] != '<') {
				return Ele(0, readTextNode(), null);
			}

			enforce(data[pos] == '<');
			pos++;
			switch(data[pos]) {
				// I don't care about these, so I just want to skip them
				case '!': // might be a comment, a doctype, or a special instruction
					pos++;
					if(data[pos] == '-' && data[pos+1] == '-') {
						// comment
						pos += 2;
						while(data[pos..pos+3] != "-->")
							pos++;
						assert(data[pos] == '-');
						pos++;
						assert(data[pos] == '-');
						pos++;
						assert(data[pos] == '>');
					} else if(data[pos..pos + 7] == "[CDATA[") {
						pos += 7;
						// FIXME: major malfunction possible here
						auto cdataStart = pos;
						auto cdataEnd = pos + data[pos .. $].indexOf("]]>");

						pos = cdataEnd + 3;
						return Ele(0, new TextNode(this, data[cdataStart .. cdataEnd]), null);
					} else
						while(data[pos] != '>')
							pos++;
					pos++; // skip the >
				break;
				case '?':
					char end = data[pos];

				    more:
					pos++; // skip the start
					while(data[pos] != end)
						pos++;
					pos++; // skip the end
					if(data[pos] == '>')
						pos++;
					else
						goto more;
				break;
				case '/': // closing an element
					pos++; // skip the start
					int p = pos;
					while(data[pos] != '>')
						pos++;
					//writefln("</%s>", data[p..pos]);
					pos++; // skip the '>'

					string tname = data[p..pos-1];
					if(!caseSensitive)
						tname = tname.toLower;

				return Ele(1, null, tname); // closing tag reports itself here
				case ' ': // assume it isn't a real element...
					if(strict)
						parseError("bad markup - improperly placed <");
					else
						return Ele(0, TextNode.fromUndecodedString(this, "<"), null);
				break;
				default:
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
						enforce(data[pos] == '>');//, format("got %s when expecting >\nContext:\n%s", data[pos], data[pos - 100 .. pos + 100]));
						else {
							// if we got here, it's probably because a slash was in an
							// unquoted attribute - don't trust the selfClosed value
							if(!selfClosed)
								selfClosed = tagName.isInArray(selfClosedElements);

							while(data[pos] != '>')
								pos++;
						}

						int whereThisTagStarted = pos; // for better error messages

						pos++;

						auto e = createElement(tagName);
						e.attributes = attributes;
						e.selfClosed = selfClosed;
						e.parseAttributes();


						// HACK to handle script as a CDATA section 
						if(tagName == "script" || tagName == "style") {
							string closer = "</" ~ tagName ~ ">";
							int ending = indexOf(data[pos..$], closer);
							if(loose && ending == -1)
								ending = indexOf(data[pos..$], closer.toUpper);
							if(ending == -1)
								throw new Exception("tag " ~ tagName ~ " never closed");
							ending += pos;
							e.innerRawSource = data[pos..ending];
							pos = ending + closer.length;
							return Ele(0, e, null);
						}

						bool closed = selfClosed;

						//writef("<%s>", tagName);
						while(!closed) {
							Ele n;
							if(strict)
								n = readElement();
							else
								n = readElement(parentChain ~ tagName);

							if(n.type == 4) return n; // the document is empty


							if(n.type == 0) {
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
											e.appendChild(n.element);
											n.element = null;
										}

										// is the element open somewhere up the chain?
										foreach(parent; parentChain)
											if(parent == n.payload) {
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

										if(!found) // if not found in the tree though, it's probably just text
										e.appendChild(TextNode.fromUndecodedString(this, "</"~n.payload~">"));
									}
								} else {
									if(n.element)
										e.appendChild(n.element);
								}

								if(n.payload == tagName) // in strict mode, this is always true
									closed = true;
							} else { /*throw new Exception("wtf " ~ tagName);*/ }
						}
						//writef("</%s>\n", tagName);
						return Ele(0, e, null);
					}

					switch(data[pos]) {
						default: assert(0);
						case '/': // self closing tag
							return addTag(true);
						case '>':
							return addTag(false);
						case ' ':
						case '\t':
						case '\n':
							// there might be attributes...
							moreAttributes:
							eatWhitespace();

							switch(data[pos]) {
								case '/': // self closing tag
									return addTag(true);
								case '>': // closed tag; open -- we now read the contents
									return addTag(false);
								default: // it is an attribute
									string attrName = readAttributeName();
									string attrValue = attrName;
									if(data[pos] == '=') {
										pos++;
										attrValue = readAttributeValue();
									}

									attributes[attrName] = attrValue;

									goto moreAttributes;
							}
					}
			}

			return Ele(2, null, null); // this is a <! or <? thing prolly.
			//assert(0);
		}

		eatWhitespace();
		Ele r;
		do {
			r = readElement; // there SHOULD only be one element...
			if(r.type == 4)
				break; // the document is completely empty...
		} while (r.type != 0 || r.element.nodeType != 1); // we look past the xml prologue and doctype

		root = r.element;

		if(root is null)
			if(strict)
				assert(0, "empty document should be impossible in strict mode");
			else
				parse(`<html><head></head><body></body></html>`); // fill in a dummy document in loose mode since that's what browsers do

		if(0&&sawImproperNesting) {
			// in loose mode, we can see some bad nesting. It's hard to fix above though
			// because my code sucks. So, we'll fix it here.

			fixing_p_again:
			foreach(ele; root.getElementsBySelector("p > p")) {
				auto holder = ele.parentNode.parentNode;
				auto h2 = ele.parentNode;

				if(holder is null || h2 is null)
					continue;

				ele = ele.parentNode.removeChild(ele);

				holder.insertAfter(h2, ele);

				goto fixing_p_again;
			}

		}
	}

	/* end massive parse function */

	///.
	@property string title() {
		bool doesItMatch(Element e) {
			return (e.tagName == "title");
		}

		auto e = findFirst(&doesItMatch);
		if(e)
			return e.innerText();
		return "";
	}

	///.
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
	///.
	Element getElementById(string id) {
		return root.getElementById(id);
	}

	///.
	final SomeElementType requireElementById(SomeElementType = Element)(string id)
		if( is(SomeElementType : Element))
		out(ret) { assert(ret !is null); }
	body {
		return root.requireElementById!(SomeElementType)(id);
	}

	///.
	final SomeElementType requireSelector(SomeElementType = Element)(string selector)
		if( is(SomeElementType : Element))
		out(ret) { assert(ret !is null); }
	body {
		return root.requireSelector!(SomeElementType)(selector);
	}


	///.
	Element querySelector(string selector) {
		return root.querySelector(selector);
	}

	///.
	Element[] querySelectorAll(string selector) {
		return root.querySelectorAll(selector);
	}

	///.
	Element[] getElementsBySelector(string selector) {
		return root.getElementsBySelector(selector);
	}

	///.
	Element[] getElementsByTagName(string tag) {
		return root.getElementsByTagName(tag);
	}

	/** Extension: FIXME: btw, this could just be a lazy range...... */
	Element getFirstElementByTagName(string tag) {
		if(loose)
			tag = tag.toLower();
		bool doesItMatch(Element e) {
			return e.tagName == tag;
		}
		return findFirst(&doesItMatch);
	}

	///.
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
	
	///.
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

		bool selfClosed = name.isInArray(selfClosedElements);

		Element e;
		switch(name) {
			case "table":
				e = new Table(this);
			break;
			case "a":
				e = new Link(this);
			break;
			case "form":
				e = new Form(this);
			break;
			default:
				return new Element(this, name, null, selfClosed);
		}

		// make sure all the stuff is constructed properly FIXME: should probably be in all the right constructors too
		e.tagName = name;
		e.selfClosed = selfClosed;
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


	// ******** Begin extensions ******** //

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
		prolog = d;
	}

	///.
	string prolog = "<!DOCTYPE html>\n";

	///.
	override string toString() const {
		return prolog ~ root.toString();
	}

	///.
	Element root;

	///.
	bool loose;

}

	private static string[] selfClosedElements = [ "img", "hr", "input", "br", "col", "link", "meta" ];

static import std.conv;

///.
int intFromHex(string hex) {
	int place = 1;
	int value = 0;
	for(int a = hex.length - 1; a >= 0; a--) {
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

		///.
		static immutable string[] selectorTokens = [
			// It is important that the 2 character possibilities go first here for accurate lexing
		    "~=", "*=", "|=", "^=", "$=", "!=", // "::" should be there too for full standard
		    "<<", // my any-parent extension (reciprocal of whitespace)
		    " - ", // previous-sibling extension (whitespace required to disambiguate tag-names)
		    ".", ">", "+", "*", ":", "[", "]", "=", "\"", "#", ",", " ", "~", "<"
		]; // other is white space or a name.

		///.
		int idToken(string str, int position) {
			int tid = -1;
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
	string[] lexSelector(string selector) {

		// FIXME: it doesn't support quoted attributes
		// FIXME: it doesn't support backslash escaped characters
		// FIXME: it should ignore /* comments */
		string[] tokens;
		int start = -1;
		bool skip = false;
		// get rid of useless, non-syntax whitespace

		selector = selector.strip;
		selector = selector.replace("\n", " "); // FIXME hack

		selector = selector.replace(" >", ">");
		selector = selector.replace("> ", ">");
		selector = selector.replace(" +", "+");
		selector = selector.replace("+ ", "+");
		selector = selector.replace(" ~", "~");
		selector = selector.replace("~ ", "~");
		selector = selector.replace(" <", "<");
		selector = selector.replace("< ", "<");
			// FIXME: this is ugly ^^^^^. It should just ignore that whitespace somewhere else.

		foreach(i, c; selector) { // kill useless leading/trailing whitespace too
			if(skip) {
				skip = false;
				continue;
			}

			int tid = idToken(selector, i);

			if(tid == -1) {
				if(start == -1)
					start = i;
			} else {
				if(start != -1) {
					tokens ~= selector[start..i];
					start = -1;
				}
				tokens ~= selectorTokens[tid];
			}

			if (tid != -1 && selectorTokens[tid].length == 2)
				skip = true;
		}
		if(start != -1)
			tokens ~= selector[start..$];

		return tokens;
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

		bool firstChild; ///.
		bool lastChild; ///.

		bool emptyElement; ///.
		bool oddChild; ///.
		bool evenChild; ///.

		bool rootElement; ///.

		int separation = -1; /// -1 == only itself; the null selector, 0 == tree, 1 == childNodes, 2 == childAfter, 3 == youngerSibling, 4 == parentOf

		///.
		string toString() {
			string ret;
			switch(separation) {
				default: assert(0);
				case -1: break;
				case 0: ret ~= " "; break;
				case 1: ret ~= ">"; break;
				case 2: ret ~= "+"; break;
				case 3: ret ~= "~"; break;
				case 4: ret ~= "<"; break;
			}
			ret ~= tagNameFilter;
			foreach(a; attributesPresent) ret ~= "[" ~ a ~ "]";
			foreach(a; attributesEqual) ret ~= "[" ~ a[0] ~ "=" ~ a[1] ~ "]";
			foreach(a; attributesEndsWith) ret ~= "[" ~ a[0] ~ "$=" ~ a[1] ~ "]";
			foreach(a; attributesStartsWith) ret ~= "[" ~ a[0] ~ "^=" ~ a[1] ~ "]";
			foreach(a; attributesNotEqual) ret ~= "[" ~ a[0] ~ "!=" ~ a[1] ~ "]";
			foreach(a; attributesInclude) ret ~= "[" ~ a[0] ~ "*=" ~ a[1] ~ "]";
			foreach(a; attributesIncludesSeparatedByDashes) ret ~= "[" ~ a[0] ~ "|=" ~ a[1] ~ "]";
			foreach(a; attributesIncludesSeparatedBySpaces) ret ~= "[" ~ a[0] ~ "~=" ~ a[1] ~ "]";

			if(firstChild) ret ~= ":first-child";
			if(lastChild) ret ~= ":last-child";
			if(emptyElement) ret ~= ":empty";
			if(oddChild) ret ~= ":odd-child";
			if(evenChild) ret ~= ":even-child";
			if(rootElement) ret ~= ":root";

			return ret;
		}

		// USEFUL
		///.
		bool matchElement(Element e) {
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
			if(emptyElement) {
				if(e.children.length)
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
				if(a[0] !in e.attributes || e.attributes[a[0]] == a[1])
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

			return true;
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
				auto tmp = start.parentNode;
				if(tmp !is null) {
					int pos = -1;
					auto children = tmp.childElements;
					foreach(i, child; children) {
						if(child is start) {
							pos = i;
							break;
						}
					}
					assert(pos != -1);
					if(pos + 1 < children.length) {
						auto e = children[pos+1];
						if(part.matchElement(e))
							ret ~= getElementsBySelectorParts(e, parts[1..$]);
					}
				}
			break;
			case 3: // younger sibling
				auto tmp = start.parentNode;
				if(tmp !is null) {
					int pos = -1;
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

	///.
	struct Selector {
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
			// FIXME
			/+
			Element where = e;
			foreach(part; retro(parts)) {
				if(where is relativeTo)
					return false; // at end of line, if we aren't done by now, the match fails
				if(!part.matchElement(where))
					return false; // didn't match

				if(part.selection == 1) // the > operator
					where = where.parentNode;
				else if(part.selection == 0) { // generic parent
					// need to go up the whole chain
				}
			}
			+/
			return true; // if we got here, it is a success
		}

		// the string should NOT have commas. Use parseSelectorString for that instead
		///.
		static Selector fromString(string selector) {
			return parseSelector(lexSelector(selector));
		}
	}

	///.
	Selector[] parseSelectorString(string selector) {
		Selector[] ret;
		foreach(s; selector.split(",")) {
			ret ~= parseSelector(lexSelector(s));
		}

		return ret;
	}

	///.
	Selector parseSelector(string[] tokens) {
		Selector s;

		SelectorPart current;
		void commit() {
			// might as well skip null items
			if(current != current.init) {
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
			ReadingAttributeValue
		}
		State state = State.Starting;
		string attributeName, attributeValue, attributeComparison;
		foreach(token; tokens) {
			int tid = -1;
			foreach(i, item; selectorTokens)
				if(token == item) {
					tid = i;
					break;
				}
			final switch(state) {
				case State.Starting: // fresh, might be reading an operator or a tagname
					if(tid == -1) {
						current.tagNameFilter = token;
					} else {
						// Selector operators
						switch(token) {
							case "*":
								current.tagNameFilter = "*";
							break;
							case " ":
								commit();
								current.separation = 0; // tree
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
						case "link":
							current.attributesPresent ~= "href";
						break;
						case "root":
							current.rootElement = true;
						break;
						// My extensions
						case "odd-child":
							current.oddChild = true;
						break;
						case "even-child":
							current.evenChild = true;
						break;

						case "visited", "active", "hover", "target", "focus", "checked", "selected":
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
						default:
							//if(token.indexOf("lang") == -1)
							//assert(0, token);
						break;
					}
					state = State.Starting;
				break;
				case State.ReadingAttributeSelector:
					attributeName = token;
					attributeComparison = null;
					attributeValue = null;
					state = State.ReadingAttributeComparison;
				break;
				case State.ReadingAttributeComparison:
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

		commit;

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


///.
string unCamelCase(string a) {
	string ret;
	foreach(c; a)
		if((c >= 'A' && c <= 'Z'))
			ret ~= "-" ~ toLower("" ~ c)[0];
		else
			ret ~= c;
	return ret;
}

///.
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

///.
class CssStyle {
	///.
	this(string rule, string content) {
		rule = rule.strip;
		content = content.strip;

		if(content.length == 0)
			return;

		originatingRule = rule;
		originatingSpecificity = getSpecificityOfRule(rule); // FIXME: if there's commas, this won't actually work!

		foreach(part; content.split(";")) {
			part = part.strip;
			if(part.length == 0)
				continue;
			auto idx = part.indexOf(":");
			if(idx == -1)
				continue;
				//throw new Exception("Bad css rule (no colon): " ~ part);

			Property p;

			p.name = part[0 .. idx].strip;
			p.value = part[idx + 1 .. $].replace("! important", "!important").replace("!important", "").strip; // FIXME don't drop important
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
			value = value.replace("!important", "").strip;
		}

		foreach(ref property; properties)
			if(property.name == name) {
				if(newSpecificity.score >= property.specificity.score) {
					property.givenExplicitly = explicit;
					expandShortForm(property, newSpecificity);
					return (property.value = value);
				} else {
					if(name == "display")
					writeln("Not setting ", name, " to ", value, " because ", newSpecificity.score, " < ", property.specificity.score);
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

			default: ;
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

///.
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


/*
Copyright: Adam D. Ruppe, 2010 - 2011
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions by Nick Sabalausky

        Copyright Adam D. Ruppe 2010-2011.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
        http://www.boost.org/LICENSE_1_0.txt)
*/
