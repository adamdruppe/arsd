/+

	What does work:
		* Windows and Linux guis. No Mac (well, outside of XQuartz, that should work) because the font class isn't finished in simpledisplay Cocoa version... after that though it SHOULD at least display...
		* basic text stuff
		* basic css stuff like font-size, color, etc.
		* clicking links


	Still nothing rn but wanted:
		* images
		* tables
		* forms? embedding a minigui widget would be kinda cool
		* inline-block
		* float

	UI wishlist:
		* selecting text
		* right click menus
		* put the load+parse either async or in a helper thread. then the stop button can actually do something too.
		* keybaord focus is janky

	Simple bugs:
		* text sizes all wrong on Windows, need to multiply them up at least
		* file:/// urls print without the extra //. I think that's correct according to URI RFC but need to check.

	Bigger bugs:
		* most css units are broken

	Would be nice:
		* css @supports at least being properly ignored
		* css calc() not throwing exceptions
		* css dynamic styles like :hover, :focus, etc., since it applies css statically. might be able to fix at some point, load it into a special object at least for simple cases
		* cursor changes on links
		* at least bare minimum flexbox...
		* margin: 0px auto, max-width, borders, padding.

	Amusing side trips:
		* <script language="adrscript">


	TODO
floats
position absolute
images
tables
list markers
ignore unsupported css
make my css % thing at least work (it rn hardcodes it!)
bare minimum flexbox to make my personal blog work
maybe basic forms
anchors

+/
module arsd.minigui_addons.html_viewer;

// FIXME: add a "throw on unsupported feature" to help authors making stuff for pure internal use

/+
	Flow elements:
		goes from top to bottom, each one affecting the ones below it
		these might have position: relative which offsets it but does not affect the flow

		Note: negative margin collapses by taking the positive margin minus the negative margin and that's the new margin (could be negative). This moves the whole flow along with it.

		No horizontal margins collapse.
	Float elements:
		affected by flow above it, but does not affect ones below it
	Absolute position elements:
		completely out of the flow


	Each element here is going to be a rectangle, based on the DOM tree, and each rectangle is broken up into flow blocks which are TextLayouters.

	Each element has stuff nested inside itself.
+/

import arsd.dom;
import arsd.minigui;
import arsd.textlayouter;
import arsd.http2;

// import arsd.image;
// import arsd.script; // let's have some fun lol

/+
	CSS features wanted:
		calc()
		var()
		attr()
		inherit
		MAYBE: initial
+/
struct CssContext {
	int emSize;
	int remSize;
	int vw;
	int vh;
	int parentWidth;
	int parentHeight;
	int lh; // line height
	int rlh;
	int dpi;

	// units:
	/+
		https://developer.mozilla.org/en-US/docs/Learn/CSS/Building_blocks/Values_and_units

		Might want to add a ddpx for device-dependent pixels since
		note that px is assumed to be based on 96 and scaled with dpi
	+/
}

private string substituteCssVars(string c, Element e) {
	// FIXME: what if it is recursive?
	import std.string;
	again:
	auto idx = c.indexOf("var(");
	if(idx == -1)
		return c;
	auto before = c[0..idx];
	auto end = c[idx + 4 .. $].indexOf(")");
	if(end == -1)
		throw new Exception("bad var");
	auto after = c[idx + 4 + end + 1 .. $];
	auto v = c[idx + 4 .. end + idx + 4];
	//import arsd.core; writeln("v:::::::::::", v);
	auto comma = v.indexOf(",");
	string def;
	if(comma != -1) {
		def = v[comma + 1 .. $].strip;
		v = v[0 .. comma].strip;
	}

	//import arsd.core; writeln("::::var ", v, " DEFAULT ", def);

	auto varValue = e.computedStyle.getValue(v);
	if(varValue.length == 0)
		varValue = def;

	c = before ~ varValue ~ after;
	goto again;
}

private Color cssColor(string c, Element e) {
	// import arsd.core; writeln(c);

	c = substituteCssVars(c, e);

	// import arsd.core; writeln(c);

	if(c == "inherit") {
		if(e.parentNode !is null)
			return cssColor(e.parentNode.computedStyle.color, e.parentNode);
		else
			throw new Exception("uh oh");
	}

	import std.string;
	if(c.strip.length == 0) {
		return Color.black;
	}

	// what my color object calls "green", css calls "lime" lol
	if(c == "green")
		return Color(0, 127, 0);
	if(c == "lime")
		return Color.green;
	// Color.fromString handles rgba, hsl, and #xxx stuff as well as some names, so it incomplete but often good enough
	return Color.fromString(c);
}

private int cssSizeToPixels(string cssSize, int emSize = 16, int hundredPercent = 1600) {
	int unitsIdx;
	foreach(idx, char ch; cssSize) {
		if(!(ch >= '0' && ch <= '9') && ch != '.') {
			unitsIdx = cast(int) idx;
			break;
		}
	}

	if(unitsIdx == 0)
		return 0; // i don't wanna mess with it, prolly calc() or --var or something lol

	import std.conv;
	float v = to!float(cssSize[0 .. unitsIdx]);
	switch(cssSize[unitsIdx .. $]) {
		case "px":
		case "":
			return cast(int) v;
		case "ch":
			return cast(int) (v * emSize * 3/2);
		case "em":
		case "rem":
			return cast(int) (v * emSize);
		case "pt":
			return cast(int) (v * 1.2);
		case "%":
			return cast(int) (v * hundredPercent / 100);
		// in, cm, ch, vw, vh, golly so many css units!!!

		default:
			return cast(int) v;
	}
}

private FontWeight cssWeightToSdpy(string weight) {
	switch(weight) {
		// lighter and bolder are supposed to be considered from inheritance...
		case "lighter", "100": return FontWeight.thin;

		case "regular", "400": return FontWeight.regular;

		case "bold", "700": return FontWeight.bold;

		case "bolder", "900": return FontWeight.heavy;

		case "normal":
		default:
			return FontWeight.dontcare;
	}
}

/+
	dom.d provides a css style thing that applies a sheet,
	but it doesn't actually do the cascade nor does it give
	a space for other useful info. we're going to extend it to
	do those things.
+/
class ExtendedCssStyle : CssStyle {
	Element e;
	this(Element e) {
		this.e = e;
		super(null /* rule */, e.style);
	}

	override string getValue(string name) {
		auto got = super.getValue(name);
		if(isInheritableCss(name) && got is null && e.parentNode !is null)
			// make those styles cascade! note the recursion here will go all the way up to the root element.
			return e.parentNode.computedStyle.getValue(name);
		return got;
	}
}

CssStyle ourComputedStyleFactory(Element e) {
	return new ExtendedCssStyle(e);
}


private bool isInheritableCss(string name) {
	if(name.length > 2 && name[0..2] == "--")
		return true;
	switch(name) {
		case "font-size", "font-weight", "font-style", "font-family":
		case "color":
			return true;
		default: return false;
	}
}

class HtmlViewerWidget : Widget {
	mixin Observable!(Uri, "uri");
	mixin Observable!(string, "status");

	// FIXME: history should also keep scroll position
	Uri[] history;
	size_t currentHistoryIndex;
	Document document;
	string source;

	string defaultStyleSheet() {
		import std.file;
		return readText("default.css");
	}

	void goBack() {
		if(currentHistoryIndex) {
			loadUri(history[--currentHistoryIndex], false);
		}
	}

	void goForward() {
		if(currentHistoryIndex + 1 < history.length) {
			loadUri(history[++currentHistoryIndex], false);
		}
	}

	bool cssEnabled = true;

	void loadUri(Uri uri, bool commitHistory = true) {
		document = new Document;
		if(uri.scheme == "file") {
			import std.file;
			if(std.file.exists(uri.path))
				source = readText(uri.path);
			else
				source = "<body>File not found</body>";
		} else {
			auto req = get(uri);
			// i should prolly do this async but meh
			auto res = req.waitForCompletion();
			uri = Uri(req.finalUrl).basedOn(uri);
			source = res.contentText;
		}

		if(commitHistory) {
			if(this.history.length) {
				this.history = this.history[0 .. this.currentHistoryIndex + 1];
				this.history.assumeSafeAppend();
			}
			this.history ~= uri;
			this.currentHistoryIndex = this.history.length - 1;
		}
		this.uri = uri;

		document.parseGarbage("<html><body>" ~ source ~ "</body></html>"); // if the document has a proper html tag, this adds another one but that's fairly harmless. if it doesn't, this ensures there is a single root for the parser
		if(auto extra = document.querySelector("body body")) {
			document.mainBody.stripOut;
		}

		string css;
		if(cssEnabled) {
			foreach(cssLink; document.querySelectorAll(`link[rel=stylesheet]`)) {
				auto linkUri = Uri(cssLink.href).basedOn(uri);
				auto req = get(linkUri);
				auto res = req.waitForCompletion();
				css ~= res.contentText;
			}
			foreach(cssInline; document.querySelectorAll("style")) {
				css ~= cssInline.innerHTML;
			}
		}

		auto oldcsf = computedStyleFactory;
		computedStyleFactory = &ourComputedStyleFactory;
		scope(exit)
			computedStyleFactory = oldcsf;

		StyleSheet ss;
		try {
			ss = new StyleSheet(defaultStyleSheet() ~ css);
		} catch(Exception) {
			// any kind of parse error might as well at least still
			// display the page somehow...
			ss = new StyleSheet(defaultStyleSheet());
		}

		ss.apply(document);

		/+
		if(auto wtf = document.querySelector("[style]")) {
			import arsd.core;
			foreach(prop; wtf.computedStyle.properties)
				writeln(prop.name, " ", prop.value, " ", prop.specificity.score);
		}
		+/

		hid.layoutDocument();
		this.smw.setPosition(0, 0);
		hid.redraw();
	}

	this(Widget parent) {
		super(parent);
		smw = new ScrollMessageWidget(this);
		smw.addEventListener("scroll", () {
			hid.redraw();
		});
		hid = new HtmlInnerDisplay(this, smw);
	}

	ScrollMessageWidget smw;
	HtmlInnerDisplay hid;
}

// i could potentially make this a Widget tbh
private abstract class BlockFlowElement {
	Element element;

	this(Element element) {
		this.element = element;
		assert(element !is null);

		backgroundColor = cssColor(element.computedStyle.backgroundColor, element);
	}

	int marginTop;
	int marginBottom;
	int marginLeft;
	int marginRight;
	bool centerLeft;
	bool centerRight;

	int paddingTop;
	int paddingBottom;
	int paddingLeft;
	int paddingRight;
	// borders
	// padding

	int maxWidth;

	Color backgroundColor;

	// these mutable when recomputing layout
	Point origin;
	int width;
	int height;

	abstract Element elementAtMousePosition(int x, int y);

	/+
		Returns the layout height used (content box w/o overflow) without its own margin.
	+/
	abstract int recomputeChildLayout(Point origin, Size availableArea, ref int previousMargin);

	void paint(ref WidgetPainter painter, Point scrollPosition) {
		if(backgroundColor != Color.transparent) {
			painter.outlineColor = backgroundColor;
			painter.fillColor = backgroundColor;
			painter.drawRectangle(Rectangle(origin - scrollPosition, Size(width, height)));
		}
	}

	string toString(int indent) {
		return Object.toString();
	}
}

private class TextFlowElement : BlockFlowElement {
	TextLayouter layouter;

	this(TextLayouter layouter, Element element) {
		assert(layouter !is null);
		this.layouter = layouter;
		super(element);
	}

	override string toString(int indent) {
		string ret;
		foreach(i; 0 .. indent)
			ret ~= "  ";
		auto s = layouter.getTextString();
		if(s.length > 60)
			s = s[0..60];
		ret ~= "<#text>" ~ s ~ "</#text>";
		return ret;
	}

	override Element elementAtMousePosition(int x, int y) {
		auto s = cast(HtmlInnerDisplay.HtmlTextStyle) layouter.styleAtPoint(Point(x, y) - origin);
		if(s !is null && s.domElement !is null) {
			return s.domElement;
		}
		return null;
	}

	override int recomputeChildLayout(Point origin, Size availableArea, ref int previousMargin) {
		this.origin = origin;
		layouter.wordWrapWidth = availableArea.width;
		this.width = availableArea.width;
		this.height = layouter.height();
		/+
		import std.string;
		if(layouter.getTextString.strip.length == 0) {
			// import arsd.core; writeln(this.height);
			this.height = 0;
		}
		+/
		return this.height;
	}

	override void paint(ref WidgetPainter painter, Point scrollPosition) {
		super.paint(painter, scrollPosition);

		// note that the text layouter coordinates are relative to the origin
		layouter.getDrawableText(delegate bool(txt, styleIn, info, carets...) {
			if(styleIn is null)
				return true;
			auto style = cast(HtmlInnerDisplay.HtmlTextStyle) styleIn;
			assert(style !is null);

			painter.setFont(style.font);

			if(info.selections && info.boundingBox.width > 0) {
				auto color = Color(128,128,128);// this.isFocused ? Color(0, 0, 128) : Color(128, 128, 128); // FIXME don't hardcode
				painter.fillColor = color;
				painter.outlineColor = color;
				painter.drawRectangle(Rectangle(info.boundingBox.upperLeft + origin - scrollPosition, info.boundingBox.size));
				painter.outlineColor = Color.white;
			} else {
				painter.outlineColor = style.foregroundColor;
			}


			import std.string;
			if(txt.strip.length) {
				painter.drawText(info.boundingBox.upperLeft + origin - scrollPosition, txt.stripRight);
				// import arsd.core; writeln((info.boundingBox.upperLeft + origin).y); writeln(painter.originY);
			}

			if(info.boundingBox.upperLeft.y > this.height) {
				return false;
			} else {
				return true;
			}
		});
	}
}

private class NestingFlowElement : BlockFlowElement {
	BlockFlowElement[] mainFlow;
	// FIXME floats
	// FIXME absolute positions

	// FIXME: empty text layout things still have size like the whitespace between <body> and <h1>

	// remember there is a z-index too

	override string toString(int indent) {
		string s;

		foreach(i; 0 .. indent)
			s ~= "  ";
		s ~= "<"~element.tagName~">";
		foreach(item; mainFlow) {
			s ~= "\n";
			s ~= item.toString(indent + 1);
		}

		s ~= "\n";
		foreach(i; 0 .. indent)
			s ~= "  ";
		s ~= "</" ~ element.tagName ~ ">";
		return s;
	}

	this(Element element) {
		super(element);

		marginTop = cssSizeToPixels(element.computedStyle.marginTop);
		marginBottom = cssSizeToPixels(element.computedStyle.marginBottom);
		marginLeft = cssSizeToPixels(element.computedStyle.marginLeft);
		marginRight = cssSizeToPixels(element.computedStyle.marginRight);

		paddingTop = cssSizeToPixels(element.computedStyle.paddingTop);
		paddingBottom = cssSizeToPixels(element.computedStyle.paddingBottom);
		paddingLeft = cssSizeToPixels(element.computedStyle.paddingLeft);
		paddingRight = cssSizeToPixels(element.computedStyle.paddingRight);

		if(element.computedStyle.marginLeft == "auto")
			centerLeft = true;
		if(element.computedStyle.marginRight == "auto")
			centerRight = true;

		maxWidth = cssSizeToPixels(element.computedStyle.maxWidth);

		layoutBlockRecursively(element);
	}

	override Element elementAtMousePosition(int x, int y) {
		foreach_reverse(block; mainFlow) {
			if(block.origin.y < y) {
				return block.elementAtMousePosition(x, y);
			}
		}

		return null;
	}

	void layoutBlockRecursively(Element currentBlock) {
		Element currentStyleParent;
		TextLayouter.StyleHandle currentStyle;
		TextLayouter l;
		bool lastWasLineBreak = true;
		bool isPre;

		// return true if it had a surprise block in it
		bool layoutChildNode(Element parent) {
			bool hadBlock;
			foreach(element; parent.childNodes) {
				if(element.nodeType == 3 || element.tagName == "br") {
					bool needsNewStyle;

					if(currentStyleParent !is element.parentNode) {
						currentStyleParent = element.parentNode;
						auto ws = currentStyleParent.computedStyle.whiteSpace;
						isPre = ws == "pre" || ws == "pre-line" || ws == "pre-wrap";
						needsNewStyle = true;
					}

					if(element.nodeType == 3 && !isPre) {
						import std.string;
						if(element.nodeValue.strip.length == 0)
							continue;
					}
					if(l is null) {
						l = new TextLayouter(new HtmlInnerDisplay.HtmlTextStyle(null));
						mainFlow ~= new TextFlowElement(l, currentBlock);
						needsNewStyle = true;
					}
					if(needsNewStyle)
						currentStyle = l.registerStyle(new HtmlInnerDisplay.HtmlTextStyle(currentStyleParent));
					assert(currentStyleParent !is null);

					if(element.nodeType == 3) {
						auto txt = isPre ? element.nodeValue : normalizeWhitespace(element.nodeValue, false);
						if(lastWasLineBreak) {
							import std.string;
							txt = txt.stripLeft();
						}
						l.appendText(txt, currentStyle);
						lastWasLineBreak = false;
					} else {
						l.appendText("\n", currentStyle); // br element
						lastWasLineBreak = true;
					}
				} else {
					auto display = element.computedStyle.display;
					if(display == "none")
						continue;

					if(display == "block") {
						mainFlow ~= new NestingFlowElement(element);

						// we're back to this block, but treat it like a new one again
						currentStyleParent = null;
						l = null;
						hadBlock = true;
					} else {
						if(layoutChildNode(element)) {
							// surprise block in there
							currentStyleParent = null;
							l = null;
							hadBlock = true;
						}
					}
				}
			}
			return hadBlock;
		}

		layoutChildNode(currentBlock);
	}

	override int recomputeChildLayout(Point origin, const Size availableArea, ref int previousMargin) {
		int widthToUse = availableArea.width - this.marginRight - this.marginLeft;
		if(this.maxWidth > 0 && widthToUse > this.maxWidth)
			widthToUse = this.maxWidth;

		int offsetX;
		if(this.centerLeft && this.centerRight) {
			origin.x += (availableArea.width - widthToUse) / 2;
		}

		this.origin = origin;

		origin.x += this.paddingLeft;
		origin.y += this.paddingTop;

		// FIXME: negative margin
		foreach(idx, ref block; mainFlow) {
			// FIXME: this doesn't collapse correctly across all the empty things
			auto marginToUse = (block.marginTop > previousMargin) ? block.marginTop : previousMargin;
			// if(idx == 0) marginToUse = 0;

			origin.y += block.recomputeChildLayout(origin + Point(marginLeft, marginToUse), Size(widthToUse - paddingLeft - paddingRight - block.marginRight, availableArea.height), previousMargin);
			origin.y += marginToUse;

			previousMargin = block.marginBottom;
		}

		// FIXME: what about margin bottom at the end of a thing?

		this.width = widthToUse;
		this.height = origin.y - this.origin.y + this.paddingBottom;

		return this.height;
	}

	override void paint(ref WidgetPainter painter, Point scrollPosition) {
		super.paint(painter, scrollPosition);

		foreach(block; mainFlow) {
			block.paint(painter, scrollPosition);
		}
	}
}

// grid, flexbox, and tables prolly also subclasses of this.

class HtmlInnerDisplay : Widget {

	HtmlViewerWidget hmv;
	ScrollMessageWidget smw;

	NestingFlowElement bodyFlow;

	Element elementAtMousePosition(int x, int y) {
		x += smw.position().x;
		y += smw.position().y;

		return bodyFlow.elementAtMousePosition(x, y);
	}

	/+
	BlockFlowElement blockAtMousePosition(int x, int y) {
		x += smw.position().x;
		y += smw.position().y;

		foreach_reverse(block; blocks) {
			if(block.origin.y < y) {
				return block;
			}
		}

		return BlockFlowElement.init;
	}
	+/

	override void defaultEventHandler_mousemove(MouseMoveEvent event) {
		auto ele = elementAtMousePosition(event.clientX, event.clientY);
		if(ele is null) {
			hmv.status = null;
			return;
		}
		if(ele.tagName == "a")
			hmv.status = ele.attrs.href;
	}

	override void defaultEventHandler_click(ClickEvent event) {
		/+
		if(event.button == MouseButton.right) {
			auto block = blockAtMousePosition(event.clientX, event.clientY);
			if(block && block.element)
				messageBox(block.element.toString);
		}
		+/
		auto ele = elementAtMousePosition(event.clientX, event.clientY);
		if(ele is null)
			return;

		if(ele.tagName == "a" && ele.attrs.href.length) {
			if(event.button == MouseButton.left)
				hmv.loadUri(Uri(ele.attrs.href).basedOn(hmv.uri));
		}
	}

	this(HtmlViewerWidget hmv, ScrollMessageWidget parent) {
		this.hmv = hmv;
		this.smw = parent;

		smw.addDefaultWheelListeners(32, 32, 8);
		smw.movementPerButtonClick(16, 16);
		smw.addDefaultKeyboardListeners(16, 16);

		super(parent);
	}

	static class HtmlTextStyle : TextStyle {
		static {
			OperatingSystemFont defaultFontCached;
			OperatingSystemFont defaultFont() {
				if(defaultFontCached is null) {
					defaultFontCached = new OperatingSystemFont();
					defaultFontCached.loadDefault();
				}
				return defaultFontCached;
			}

			OperatingSystemFont[string] fontCache;
			OperatingSystemFont getFont(string family, string size, string weight, string style) {
				auto key = family ~ size ~ weight ~ style;
				if(auto f = key in fontCache)
					return *f;

				int fontScale(int s) {
					version(Windows)
						return s * 2; // windows font sizes just seem off and idk what exactly the diff is so just hacking it for now.
					else
						return s;
				}

				auto f = new OperatingSystemFont(family, fontScale(cssSizeToPixels(size, 16, 16)), cssWeightToSdpy(weight), style == "italic");
				if(f.isNull)
					f.loadDefault();
				fontCache[key] = f;
				return f;

			}
		}

		Element domElement;
		OperatingSystemFont font_;
		Color foregroundColor = Color.black;

		this(Element domElement) {
			this.domElement = domElement;

			if(domElement !is null) {
				auto cs = domElement.computedStyle;
				font_ = getFont(cs.fontFamily, cs.fontSize, cs.fontWeight, cs.fontStyle);
				try {
					foregroundColor = cssColor(cs.color, domElement);
				} catch(Exception e) {
					// FIXME can default to something better than plain black, inherit it maybe
				}
			}

			if(font_ is null) {
				font_ = defaultFont;
			}

		}

		override OperatingSystemFont font() {
			return font_;
		}
	}

	void layoutDocument() {
		if(hmv.document is null || hmv.document.mainBody is null)
			return;

		/+
			General plan:

			* Each block element gets its own TextLayouter instance
			* RIP floats, inline-blocks, and inline images as layouter doesn't (yet) do replaced elements :(
		+/

		bodyFlow = new NestingFlowElement(hmv.document.mainBody);

		recomputeChildLayout();
	}

	enum padding = 4;
	override void recomputeChildLayout() {
		int previousMargin = 0;
		int totalArea = 0;

		if(bodyFlow) {
			totalArea = bodyFlow.recomputeChildLayout(Point(padding, padding), Size(this.width - padding* 2, this.height - padding* 2), previousMargin);
		}

		this.smw.setTotalArea(this.width, totalArea);
		this.smw.setViewableArea(this.width, this.height);
	}

	override void paint(WidgetPainter painter) {
		// clear the screen
		painter.outlineColor = Color.white;
		painter.fillColor = Color.white;
		painter.drawRectangle(Rectangle(Point(0, 0), Size(width, height)));

		// transform to remove the scroll aspect here then everything else works in the widget coordinate space

		if(bodyFlow)
			bodyFlow.paint(painter, smw.position);
	}
}

class AddressBarWidget : Widget {

	private static class AddressBarButton : Button {
		this(string label, Widget parent) {
			super(label, parent);
		}

		override int maxWidth() {
			return scaleWithDpi(24);
		}
	}



	Button back;
	Button forward;
	Button stop;
	Button reload;
	LineEdit url;
	Button go;
	this(BrowserWidget parent) {
		super(parent);

		auto hl = new HorizontalLayout(this);
		back = new AddressBarButton("<", hl);
		back.addWhenTriggered(() { parent.Back(); });
		forward = new AddressBarButton(">", hl);
		forward.addWhenTriggered(() { parent.Forward(); });
		stop = new AddressBarButton("X", hl);
		reload = new AddressBarButton("R", hl);
		reload.addWhenTriggered(() { parent.Reload(); });
		url = new LineEdit(hl);
		go = new AddressBarButton("Go", hl);
		go.addWhenTriggered(() { parent.Open(url.content); });

		url.addEventListener((DoubleClickEvent ev) {
			url.selectAll();
			ev.preventDefault();
		});

		url.addEventListener((CharEvent ke) {
			if(ke.character == '\n') {
				auto event = new Event("triggered", go);
				event.dispatch();
				ke.preventDefault();
			}
		});

		this.tabStop = false;
	}

	override int maxHeight() {
		return scaleWithDpi(24);
	}
}


class BrowserWidget : Widget {
	AddressBarWidget ab;
	HtmlViewerWidget hvw;

	this(Widget parent) {
		super(parent);
		ab = new AddressBarWidget(this);
		hvw = new HtmlViewerWidget(this);
		hvw.uri_changed = u => ab.url.content = u;
		this.tabStop = false;
	}

	@menu("&File") {
		void Open(string url) {
			if(url.length == 0)
				return;
			if(url[0] == '/')
				url = "file://" ~ url;
			else if(url.length < 7 && url[0 .. 4] != "http")
				url = "http://" ~ url;

			hvw.loadUri(Uri(url));
		}

		@accelerator("Alt+Left")
		void Back() {
			hvw.goBack();
		}

		@accelerator("Alt+Right")
		void Forward() {
			hvw.goForward();
		}

		@accelerator("F5")
		void Reload() {
			hvw.loadUri(hvw.uri, false);
		}

		@accelerator("Ctrl+W")
		void Quit() {
			this.parentWindow.close();
		}
	}

	@menu("&Edit") {

	}

	@menu("Fea&tures") {
		void Css(bool enabled) {
			hvw.cssEnabled = enabled;
		}
	}

	@menu("&View") {
		@accelerator("Ctrl+U")
		void ViewSource() {
			auto window = new Window();
			auto td = new TextDisplay(hvw.source, window);
			window.show();
		}

		void ViewDomTree() {
			if(hvw.document is null) {
				messageBox("No document is currently loaded.");
			} else {
				auto window = new Window();
				auto td = new TextDisplay(hvw.document.toPrettyString(), window);
				window.show();
			}
		}

		void ViewLayoutTree() {
			if(hvw.hid.bodyFlow) {
				auto window = new Window();
				auto td = new TextDisplay(hvw.hid.bodyFlow.toString(0), window);
				window.show();
			}

		}
	}
	@menu("&Help") {
		void About() {
			messageBox("lol made for a browser jam");
		}
	}
}

MainWindow createBrowserWindow(string title, string initialUrl) {
	auto window = new MainWindow(title);
	auto bw = new BrowserWidget(window);

	bw.hvw.status_changed = u => window.statusBar.parts[0].content = u;

	window.setMenuAndToolbarFromAnnotatedCode(bw);

	if(initialUrl.length)
		bw.Open(initialUrl);

	return window;
}
