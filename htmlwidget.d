/**
	My old toy html widget build out of my libraries. Not great, you probably don't want to use it.


	This module has a lot of dependencies

	dmd yourapp.d arsd/htmlwidget.d arsd/simpledisplay.d arsd/curl.d arsd/color.d arsd/dom.d arsd/characterencodings.d arsd/imagedraft.d -J. -version=browser

	-version=browser is important so dom.d has the extensibility hook this module uses.



	The idea here is to be a quick html window, displayed using the simpledisplay.d
	module.

	Nothing fancy, the html+css support is spotty and it has some text layout bugs...
	but it can work for a simple thing.

	It has no javascript support, but you can (and must, for even links to work) add
	event listeners in your D code.
*/
module arsd.htmlwidget;

public import arsd.simpledisplay;
import arsd.image;

public import arsd.dom;

import std.range;
import std.conv;
import std.stdio;
import std.string;
import std.algorithm : max, min;

alias void delegate(Element, Event) EventHandler;

struct CssSize {
	string definition;

	int getPixels(int oneEm, int oneHundredPercent)
//		out (ret) { assert(ret >= 0, to!string(ret) ~ " " ~ definition); }
	do {
		if(definition.length == 0 || definition == "none")
			return 0;

		if(definition == "auto")
			return 0;

		if(isNumeric(definition))
			return to!int(definition);

		if(definition[$-1] == '%') {
			if(oneHundredPercent < 0)
				return 0;
			return cast(int) (to!real(definition[0 .. $-1]) * oneHundredPercent);
		}
		if(definition[$-2 .. $] == "px")
			return to!int(definition[0 .. $ - 2]);
		if(definition[$-2 .. $] == "em")
			return cast(int) (to!real(definition[0 .. $-2]) * oneEm);

		// FIXME: other units of measure...

		return 0;
	}
}


Color readColor(string v) {
	v = v.toLower;
	switch(v) {
		case "transparent":
			return Color(0, 0, 0, 0);
		case "red":
			return Color(255, 0, 0);
		case "green":
			return Color(0, 255, 0);
		case "blue":
			return Color(0, 0, 255);
		case "yellow":
			return Color(255, 255, 0);
		case "white":
			return Color(255, 255, 255);
		case "black":
			return Color(0, 0, 0);
		default:
			if(v[0] == '#') {
				return Color.fromString(v);
			} else {
				goto case "transparent";
			}
	}
}

enum TableDisplay : int {
	table = 1,
	row = 2,
	cell = 3,
	caption = 4
}

class LayoutData {
	Element element;
	this(Element parent) {
		element = parent;
		element.expansionHook = cast(void*) this;

		parseStyle;
	}

	void parseStyle() {
		// reset to defaults
		renderInline = true;
		outsideNormalFlow = false;
		renderValueAsText = false;
		doNotDraw = false;

		if(element.nodeType != 1) {
			return; // only tags get style
		}

		// legitimate attributes FIXME: do these belong here?

		if(element.hasAttribute("colspan"))
			tableColspan = to!int(element.attrs.colspan);
		else
			tableColspan = 1;
		if(element.hasAttribute("rowspan"))
			tableRowspan = to!int(element.attrs.rowspan);
		else
			tableRowspan = 1;


		if(element.tagName == "img") {
			try {
				auto bytes = cast(ubyte[]) curl(absolutizeUrl(element.src, _contextHack.currentUrl));
				auto i = loadImageFromMemory(bytes);
				image = Image.fromMemoryImage(i);

				width = CssSize(to!string(image.width) ~ "px");
				height = CssSize(to!string(image.height) ~ "px");

			} catch (Throwable t) {
				writeln(t.toString);
				image = null;
			}
		}

		CssSize readSize(string v) {
			return CssSize(v);
			/*
			if(v.indexOf("px") == -1)
				return 0;

			return to!int(v[0 .. $-2]);
			*/
		}

		auto style = element.computedStyle;

		//if(element.tagName == "a")
			//assert(0, style.toString);

		foreach(item; style.properties) {
			string value = item.value;

			Element curr = element;
			while(value == "inherit" && curr.parentNode !is null) {
				curr = curr.parentNode;
				value = curr.computedStyle.getValue(item.name);
			}

			if(value == "inherit")
				assert(0, item.name ~ " came in as inherit all the way up the chain");

			switch(item.name) {
				case "attribute-as-text":
					renderValueAsText = true;
				break;
				case "margin-bottom":
					marginBottom = readSize(value);
				break;
				case "margin-top":
					marginTop = readSize(value);
				break;
				case "margin-left":
					marginLeft = readSize(value);
				break;
				case "margin-right":
					marginRight = readSize(value);
				break;
				case "padding-bottom":
					paddingBottom = readSize(value);
				break;
				case "padding-top":
					paddingTop = readSize(value);
				break;
				case "padding-left":
					paddingLeft = readSize(value);
				break;
				case "padding-right":
					paddingRight = readSize(value);
				break;
				case "visibility":
					if(value == "hidden")
						doNotDraw = true;
					else
						doNotDraw = false;
				break;
				case "width":
					if(value == "auto")
						width = CssSize();
					else
						width = readSize(value);
				break;
				case "height":
					if(value == "auto")
						height = CssSize();
					else
						height = readSize(value);
				break;
				case "display":
					tableDisplay = 0;
					switch(value) {
						case "block":
							renderInline = false;
						break;
						case "inline":
							renderInline = true;
						break;
						case "none":
							doNotRender = true;
						break;
						case "list-item":
							renderInline = false;
							// FIXME - show the list marker too
						break;
						case "inline-block":
							renderInline = false; // FIXME
						break;
						case "table":
							renderInline = false;
						goto case;
						case "inline-table":
							tableDisplay = TableDisplay.table;
						break;
						case "table-row":
							tableDisplay = TableDisplay.row;
						break;
						case "table-cell":
							tableDisplay = TableDisplay.cell;
						break;
						case "table-caption":
							tableDisplay = TableDisplay.caption;
						break;
						case "run-in":

						/* do these even matter? */
						case "table-header-group":
						case "table-footer-group":
						case "table-row-group":
						case "table-column":
						case "table-column-group":
						default:
							// FIXME
					}

					if(value == "table-row")
						renderInline = false;
				break;
				case "position":
					position = value;
					if(position == "absolute" || position == "fixed")
						outsideNormalFlow = true;
				break;
				case "top":
					top = CssSize(value);
				break;
				case "bottom":
					bottom = CssSize(value);
				break;
				case "right":
					right = CssSize(value);
				break;
				case "left":
					left = CssSize(value);
				break;
				case "color":
					foregroundColor = readColor(value);
				break;
				case "background-color":
					backgroundColor = readColor(value);
				break;
				case "float":
					switch(value) {
						case "none": cssFloat = 0; outsideNormalFlow = false; break;
						case "left": cssFloat = 1; outsideNormalFlow = true; break;
						case "right": cssFloat = 2; outsideNormalFlow = true; break;
						default: assert(0);
					}
				break;
				case "clear":
					switch(value) {
						case "none": floatClear = 0; break;
						case "left": floatClear = 1; break;
						case "right": floatClear = 2; break;
						case "both": floatClear = 1; break; // FIXME
						default: assert(0);
					}
				break;
				case "border":
					borderWidth = CssSize("1px");
				break;
				default:
			}
		}

		// FIXME
		if(tableDisplay == TableDisplay.row) {
			renderInline = false;
		} else if(tableDisplay == TableDisplay.cell)
			renderInline = true;
	}

	static LayoutData get(Element e) {
		if(e.expansionHook is null)
			return new LayoutData(e);
		return cast(LayoutData) e.expansionHook;
	}

	EventHandler[][string] bubblingEventHandlers;
	EventHandler[][string] capturingEventHandlers;
	EventHandler[string] defaultEventHandlers;

	int absoluteLeft() {
		int a = offsetLeft;
		// FIXME: dead wrong
		/*
		auto p = offsetParent;
		while(p) {
			auto l = LayoutData.get(p);
			a += l.offsetLeft;
			p = l.offsetParent;
		}*/

		return a;
	}

	int absoluteTop() {
		int a = offsetTop;
		/*
		auto p = offsetParent;
		while(p) {
			auto l = LayoutData.get(p);
			a += l.offsetTop;
			p = l.offsetParent;
		}*/

		return a;
	}

	int offsetWidth;
	int offsetHeight;
	int offsetLeft;
	int offsetTop;
	Element offsetParent;

	CssSize borderWidth;

	CssSize paddingLeft;
	CssSize paddingRight;
	CssSize paddingTop;
	CssSize paddingBottom;

	CssSize marginLeft;
	CssSize marginRight;
	CssSize marginTop;
	CssSize marginBottom;

	CssSize width;
	CssSize height;

	string position;

	CssSize left;
	CssSize top;
	CssSize right;
	CssSize bottom;

	Color borderColor;
	Color backgroundColor;
	Color foregroundColor;

	int zIndex;


	/* pseudo classes */
	bool hover;
	bool active;
	bool focus;
	bool link;
	bool visited;
	bool selected;
	bool checked;
	/* done */

	/* CSS styles */
	bool doNotRender;
	bool doNotDraw;
	bool renderInline;
	bool renderValueAsText;

	int tableDisplay; // 1= table, 2 = table-row, 3 = table-cell, 4 = table-caption
	int tableColspan;
	int tableRowspan;
	int cssFloat;
	int floatClear;

	string textToRender;

	bool outsideNormalFlow;

	/* Efficiency flags */

	static bool someRepaintRequired;
	bool repaintRequired;

	void invalidate() {
		repaintRequired = true;
		someRepaintRequired = true;
	}

	void paintCompleted() {
		repaintRequired = false;
		someRepaintRequired = false; // FIXME
	}

	Image image;
}

Element elementFromPoint(Document document, int x, int y) {
	int winningZIndex = int.min;
	Element winner;
	foreach(element; document.mainBody.tree) {
		if(element.nodeType == 3) // do I want this?
			continue;
		auto e = LayoutData.get(element);
		if(e.doNotRender)
			continue;
		if(
			e.zIndex >= winningZIndex
			&&
			x >= e.absoluteLeft() && x < e.absoluteLeft() + e.offsetWidth
			&&
			y >= e.absoluteTop() && y < e.absoluteTop() + e.offsetHeight
		) {
			winner = e.element;
			winningZIndex = e.zIndex;
		}
	}

	return winner;
}

int longestLine(string a) {
	int longest = 0;
	foreach(l; a.split("\n"))
		if(l.length > longest)
			longest = cast(int) l.length;
	return longest;
}

int getTableCells(Element row) {
	int count;
	foreach(c; row.childNodes) {
		auto l = LayoutData.get(c);
		if(l.tableDisplay == TableDisplay.cell)
			count += l.tableColspan;
	}

	return count;
}

// returns: dom structure changed
bool layout(Element element, int containerWidth, int containerHeight, int cx, int cy, bool canWrap, int parentContainerWidth = 0) {
	auto oneEm = 16;

	if(element.tagName == "head")
		return false;

	auto l = LayoutData.get(element);

	if(l.doNotRender)
		return false;

	if(element.nodeType == 3 && element.nodeValue.strip.length == 0) {
		l.doNotRender = true;
		return false;
	}

	if(!l.renderInline) {
		cx += l.marginLeft.getPixels(oneEm, containerWidth); // FIXME: does this belong here?
		//cy += l.marginTop.getPixels(oneEm, containerHeight);
		containerWidth -= l.marginLeft.getPixels(oneEm, containerWidth) + l.marginRight.getPixels(oneEm, containerWidth);
		//containerHeight -= l.marginTop.getPixels(oneEm, containerHeight) + l.marginBottom.getPixels(oneEm, containerHeight);
	}

	l.offsetLeft = cx;
	l.offsetTop = cy;

	//if(!l.renderInline) {
		cx += l.paddingLeft.getPixels(oneEm, containerWidth);
		cy += l.paddingTop.getPixels(oneEm, containerHeight);
		containerWidth -= l.paddingLeft.getPixels(oneEm, containerWidth) + l.paddingRight.getPixels(oneEm, containerWidth);
		containerHeight -= l.paddingTop.getPixels(oneEm, containerHeight) + l.paddingBottom.getPixels(oneEm, containerHeight);
	//}

	auto initialX = cx;
	auto initialY = cy;
	auto availableWidth = containerWidth;
	auto availableHeight = containerHeight;

	int fx; // current position for floats
	int fy;


	int boundingWidth;
	int boundingHeight;

	int biggestWidth;
	int biggestHeight;

	int lastMarginBottom;
	int lastMarginApplied;

	bool hasContentLeft;


	int cssWidth = l.width.getPixels(oneEm, containerWidth);
	int cssHeight = l.height.getPixels(oneEm, containerHeight);

	bool widthSet = false;

	if(l.tableDisplay == TableDisplay.cell && !widthSet) {
		l.offsetWidth = l.tableColspan * parentContainerWidth / getTableCells(l.element.parentNode);
		widthSet = true;
		containerWidth = l.offsetWidth;
		availableWidth = containerWidth;
	}


	int skip;
	startAgain:
	// now, we layout the children to collect all that info together
	foreach(i, child; element.childNodes) {
		if(skip) {
			skip--;
			continue;
		}

		auto childLayout = LayoutData.get(child);

		if(!childLayout.outsideNormalFlow && !childLayout.renderInline && hasContentLeft) {
			cx = initialX;
			cy += biggestHeight;
			availableWidth = containerWidth;
			availableHeight -= biggestHeight;
			hasContentLeft = false;

			biggestHeight = 0;
		}

		if(childLayout.floatClear) {
			cx = initialX;

			if(max(fy, cy) != cy)
				availableHeight -= fy - cy;

			cy = max(fy, cy);
			hasContentLeft = false;
			biggestHeight = 0;
		}

		auto currentMargin = childLayout.marginTop.getPixels(oneEm, containerHeight);
		currentMargin = max(currentMargin, lastMarginBottom) - lastMarginBottom;
		if(currentMargin < 0)
			currentMargin = 0;
		if(!lastMarginApplied && max(currentMargin, lastMarginBottom) > 0)
			currentMargin = max(currentMargin, lastMarginBottom);

		lastMarginApplied = currentMargin;

		cy += currentMargin;
		containerHeight -= currentMargin;

		bool changed = layout(child, availableWidth, availableHeight, cx, cy, !l.renderInline, containerWidth);

		if(childLayout.cssFloat) {
			childLayout.offsetTop += fy;
			foreach(bele; child.tree) {
				auto lolol = LayoutData.get(bele);
				lolol.offsetTop += fy;
			}

			fx += childLayout.offsetWidth;
			fy += childLayout.offsetHeight;
		}

		if(childLayout.doNotRender || childLayout.outsideNormalFlow)
			continue;

		//if(childLayout.offsetHeight < 0)
			//childLayout.offsetHeight = 0;
		//if(childLayout.offsetWidth < 0)
			//childLayout.offsetWidth = 0;

		assert(childLayout.offsetHeight >= 0);
		assert(childLayout.offsetWidth >= 0);

		// inline elements can't have blocks inside
		//if(!childLayout.renderInline)
			//l.renderInline = false;

		lastMarginBottom = childLayout.marginBottom.getPixels(oneEm, containerHeight);

		if(childLayout.offsetWidth > biggestWidth)
			biggestWidth = childLayout.offsetWidth;
		if(childLayout.offsetHeight > biggestHeight)
			biggestHeight = childLayout.offsetHeight;

		availableWidth -= childLayout.offsetWidth;


		if(cx + childLayout.offsetWidth > boundingWidth)
			boundingWidth = cx + childLayout.offsetWidth;

		// if the dom was changed, it was to wrap...
		if(changed || availableWidth <= 0) {
			// gotta move to a new line
			availableWidth = containerWidth;
			cx = initialX;
			cy += biggestHeight;
			biggestHeight = 0;
			availableHeight -= childLayout.offsetHeight;
			hasContentLeft = false;
			//writeln("new line now at ", cy);
		} else {
			// can still use this one
			cx += childLayout.offsetWidth;
			hasContentLeft = true;
		}

		if(changed) {
			skip = cast(int) i;
			writeln("dom changed");
			goto startAgain;
		}
	}

	if(hasContentLeft)
		cy += biggestHeight; // line-height

	boundingHeight = cy - initialY + l.paddingTop.getPixels(oneEm, containerHeight) + l.paddingBottom.getPixels(oneEm, containerHeight);

	// And finally, layout this element itself
	if(element.nodeType == 3) {
		bool wrapIt;
		if(element.computedStyle.getValue("white-space") == "pre") {
			l.textToRender = element.nodeValue;
		} else {
			l.textToRender = replace(element.nodeValue,"\n", " ").replace("\t", " ").replace("\r", " ");//.squeeze(" "); // FIXME
			wrapIt = true;
		}
		if(l.textToRender.length == 0) {
			l.doNotRender = true;
			return false;
		}

		if(wrapIt) {
			auto lineWidth = containerWidth / 6;

			bool startedWithSpace = l.textToRender[0] == ' ';

			if(l.textToRender.length > lineWidth)
				l.textToRender = wrap(l.textToRender, lineWidth);

			if(l.textToRender[$-1] == '\n')
				l.textToRender = l.textToRender[0 .. $-1];

			if(startedWithSpace && l.textToRender[0] != ' ')
				l.textToRender = " " ~ l.textToRender;
		}

		bool contentChanged = false;
		// we can wrap so let's do it
		/*
		auto lineIdx = l.textToRender.indexOf("\n");
		if(canWrap && lineIdx != -1) {
			writeln("changing ***", l.textToRender, "***");
			auto remaining = l.textToRender[lineIdx + 1 .. $];
			l.textToRender = l.textToRender[0 .. lineIdx];

			Element[] txt;
			txt ~= new TextNode(element.parentDocument, l.textToRender);
			txt ~= new TextNode(element.parentDocument, "\n");
			txt ~= new TextNode(element.parentDocument, remaining);

			element.parentNode.replaceChild(element, txt);
			contentChanged = true;
		}
		*/

		if(l.textToRender.length != 0) {
			l.offsetHeight = cast(int) count(l.textToRender, "\n") * 16 + 16; // lines * line-height
			l.offsetWidth = l.textToRender.longestLine * 6; // inline
		} else {
			l.offsetWidth = 0;
			l.offsetHeight = 0;
		}

		l.renderInline = true;

		//writefln("Text %s at (%s, %s) with size %sx%s", element.tagName, l.offsetLeft, l.offsetTop, l.offsetWidth, l.offsetHeight);

		return contentChanged;
	}

	// images get special treatment too
	if(l.image !is null) {
		if(!widthSet)
			l.offsetWidth = l.image.width;
		l.offsetHeight = l.image.height;
		//writefln("Image %s at (%s, %s) with size %sx%s", element.tagName, l.offsetLeft, l.offsetTop, l.offsetWidth, l.offsetHeight);

		return false;
	}

	/*
	// tables constrain floats...
	if(l.tableDisplay == TableDisplay.cell) {
		l.offsetHeight += fy;
	}
	*/

	// layout an inline element...
	if(l.renderInline) {
		//if(l.tableDisplay == TableDisplay.cell) {
			//auto ow = widthSet ? l.offsetWidth : 0;
			//l.offsetWidth = min(ow, boundingWidth - initialX);
			//if(l.offsetWidth < 0)
				//l.offsetWidth = 0;
		//} else
		if(!widthSet) {
			l.offsetWidth = boundingWidth - initialX; // FIXME: padding?
			if(l.offsetWidth < 0)
				l.offsetWidth = 0;
		}

		l.offsetHeight = max(boundingHeight, biggestHeight);
		//writefln("Inline element %s at (%s, %s) with size %sx%s", element.tagName, l.offsetLeft, l.offsetTop, l.offsetWidth, l.offsetHeight);
	// and layout a block element
	} else {
		l.offsetWidth = containerWidth;
		l.offsetHeight = boundingHeight;

		//writefln("Block element %s at (%s, %s) with size %sx%s", element.tagName, l.offsetLeft, l.offsetTop, l.offsetWidth, l.offsetHeight);
	}

	if(l.position == "absolute") {
		l.offsetTop = l.top.getPixels(oneEm, containerHeight);
		l.offsetLeft = l.left.getPixels(oneEm, containerWidth);
	//	l.offsetRight = l.right.getPixels(oneEm, containerWidth);
	//	l.offsetBottom = l.bottom.getPixels(oneEm, containerHeight);
	} else if(l.position == "relative") {
		l.offsetTop = l.top.getPixels(oneEm, containerHeight);
		l.offsetLeft = l.left.getPixels(oneEm, containerWidth);
	//	l.offsetRight = l.right.getPixels(oneEm, containerWidth);
	//	l.offsetBottom = l.bottom.getPixels(oneEm, containerHeight);
	}

	// table cells need special treatment
	if(!l.tableDisplay) {
		if(cssWidth) {
			l.offsetWidth = cssWidth;
			containerWidth = min(containerWidth, cssWidth);
			// not setting widthSet since this is just a hint
		}
		if(cssHeight) {
			l.offsetHeight = cssHeight;
			containerHeight = min(containerHeight, cssHeight);
		}
	}



	/*
	// table cell
	if(l.tableDisplay == 2) {
		l.offsetWidth = containerWidth;
	}
	*/

	// a table row, and all it's cell children, have the same height
	if(l.tableDisplay == TableDisplay.row) {
		int maxHeight = 0;
		foreach(e; element.childNodes) {
			auto el = LayoutData.get(e);
			if(el.tableDisplay == TableDisplay.cell) {
				if(el.offsetHeight > maxHeight)
					maxHeight = el.offsetHeight;
			}
		}

		foreach(e; element.childNodes) {
			auto el = LayoutData.get(e);
			if(el.tableDisplay == TableDisplay.cell) {
				el.offsetHeight = maxHeight;
			}
		}
		l.offsetHeight = maxHeight;
	}

	// every column in a table has equal width

	// assert(l.offsetHeight == 0 || l.offsetHeight > 10, format("%s on %s %s", l.offsetHeight, element.tagName, element.id ~ "." ~ element.className));

	return false;

}

	int scrollTop = 0;

void drawElement(ScreenPainter p, Element ele, int startingX, int startingY) {
	auto oneEm = 1;

	// margin is handled in the layout phase, but border, padding, and obviously, content are handled here

	auto l = LayoutData.get(ele);

	if(l.doNotDraw)
		return;

	if(l.doNotRender)
		return;
	startingX = 0; // FIXME
	startingY = 0; // FIXME why does this fix things?
	int cx = l.offsetLeft + startingX, cy = l.offsetTop + startingY, cw = l.offsetWidth, ch = l.offsetHeight;

	if(l.image !is null) {
		p.drawImage(Point(cx, cy - scrollTop), l.image);
	}

	//if(cw <= 0 || ch <= 0)
	//	return;

	if(l.borderWidth.getPixels(oneEm, 1) > 0) {
		p.fillColor = Color(0, 0, 0, 0);
		p.outlineColor = l.borderColor;
		// FIXME: handle actual widths by selecting a pen
		p.drawRectangle(Point(cx, cy - scrollTop), cw, ch); // draws the border
	}

	int sx = cx, sy = cy;

	cx += l.borderWidth.getPixels(oneEm, 1);
	cy += l.borderWidth.getPixels(oneEm, 1);
	cw -= l.borderWidth.getPixels(oneEm, 1) * 2;
	ch -= l.borderWidth.getPixels(oneEm, 1) * 2;

	p.fillColor = l.backgroundColor;
	p.outlineColor = Color(0, 0, 0, 0);

	if(ele.tagName == "body") { // HACK to make the body bg apply to the whole window
		cx = 0;
		cy = 0;
		cw = p.window.width;
		ch = p.window.height;
		p.drawRectangle(Point(0, 0), p.window.width, p.window.height); // draw the padding box
	} else

	p.drawRectangle(Point(cx, cy - scrollTop), cw, ch); // draw the padding box

	if(l.renderValueAsText && ele.value.length) {
		p.outlineColor = l.foregroundColor;
		p.drawText(Point(
			cx + l.paddingLeft.getPixels(oneEm, 1),
			cy + l.paddingTop.getPixels(oneEm, 1) - scrollTop),
			ele.value);
	}

	//p.fillColor = Color(255, 255, 255);
	//p.drawRectangle(Point(cx, cy), cw, ch); // draw the content box


	foreach(e; ele.childNodes) {
		if(e.nodeType == 3) {
			auto thisL = LayoutData.get(e);
			p.outlineColor = LayoutData.get(e.parentNode).foregroundColor;
			p.drawText(Point(thisL.offsetLeft, thisL.offsetTop - scrollTop), toAscii(LayoutData.get(e).textToRender));
		} else
			drawElement(p, e, sx, sy);
	}

	l.repaintRequired = false;
}


string toAscii(string s) {
	string ret;
	foreach(dchar c; s) {
		if(c < 128 && c > 0)
			ret ~= cast(char) c;
		else switch(c) {
			case '\u00a0': // nbsp
				ret ~= ' ';
			break;
			case '\u2018':
			case '\u2019':
				ret ~= "'";
			break;
			case '\u201c':
			case '\u201d':
				ret ~= "\"";
			break;
			default:
				// skip non-ascii
		}
	}

	return ret;
}


class Event {
	this(string eventName, Element target) {
		this.eventName = eventName;
		this.srcElement = target;
	}

	void preventDefault() {
		defaultPrevented = true;
	}

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

	void send() {
		if(srcElement is null)
			return;

		auto e = LayoutData.get(srcElement);

		if(eventName in e.bubblingEventHandlers)
		foreach(handler; e.bubblingEventHandlers[eventName])
			handler(e.element, this);

		if(!defaultPrevented)
			if(eventName in e.defaultEventHandlers)
				e.defaultEventHandlers[eventName](e.element, this);
	}

	void dispatch() {
		if(srcElement is null)
			return;

		// first capture, then bubble

		LayoutData[] chain;
		Element curr = srcElement;
		while(curr) {
			auto l = LayoutData.get(curr);
			chain ~= l;
			curr = curr.parentNode;

		}

		isBubbling = false;
		foreach(e; chain.retro) {
			if(eventName in e.capturingEventHandlers)
			foreach(handler; e.capturingEventHandlers[eventName])
				handler(e.element, this);

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
				handler(e.element, this);

			if(!defaultPrevented)
				if(eventName in e.defaultEventHandlers)
					e.defaultEventHandlers[eventName](e.element, this);

			if(propagationStopped)
				break;
		}

	}
}

void addEventListener(string event, Element what, EventHandler handler, bool bubble = true) {
	if(event.length > 2 && event[0..2] == "on")
		event = event[2 .. $];

	auto l = LayoutData.get(what);
	if(bubble)
		l.bubblingEventHandlers[event] ~= handler;
	else
		l.capturingEventHandlers[event] ~= handler;
}

void addEventListener(string event, Element[] what, EventHandler handler, bool bubble = true) {
	foreach(w; what)
		addEventListener(event, w, handler, bubble);
}

bool isAParentOf(Element a, Element b) {
	if(a is null || b is null)
		return false;

	while(b !is null) {
		if(a is b)
			return true;
		b = b.parentNode;
	}

	return false;
}

void runHtmlWidget(SimpleWindow win, BrowsingContext context) {
	Element mouseLastOver;

	win.eventLoop(0,
	(MouseEvent e) {
		auto ele = elementFromPoint(context.document, e.x, e.y + scrollTop);

		if(mouseLastOver !is ele) {
			Event event;

			if(ele !is null) {
				if(!isAParentOf(ele, mouseLastOver)) {
					//writeln("mouseenter on ", ele.tagName);

					event = new Event("mouseenter", ele);
					event.relatedTarget = mouseLastOver;
					event.send();
				}
			}

			if(mouseLastOver !is null) {
				if(!isAParentOf(mouseLastOver, ele)) {
					event = new Event("mouseleave", mouseLastOver);
					event.relatedTarget = ele;
					event.send();
				}
			}

			if(ele !is null) {
				event = new Event("mouseover", ele);
				event.relatedTarget = mouseLastOver;
				event.dispatch();
			}

			if(mouseLastOver !is null) {
				event = new Event("mouseout", mouseLastOver);
				event.relatedTarget = ele;
				event.dispatch();
			}

			mouseLastOver = ele;
		}

		if(ele !is null) {
			auto l = LayoutData.get(ele);
			auto event = new Event(
				  e.type == 0 ? "mousemove"
				: e.type == 1 ? "mousedown"
				: e.type == 2 ? "mouseup"
				: impossible
			, ele);
			event.clientX = e.x;
			event.clientY = e.y;
			event.button = e.button;

			event.dispatch();

			if(l.someRepaintRequired) {
				auto p = win.draw();
				p.clear();
				drawElement(p, context.document.mainBody, 0, 0);
				l.paintCompleted();
			}
		}
	},
	(dchar key) {
		auto s = scrollTop;
		if(key == 'j')
			scrollTop += 16;
		else if(key == 'k')
			scrollTop -= 16;
		if(key == 'n')
			scrollTop += 160;
		else if(key == 'm')
			scrollTop -= 160;

		if(context.focusedElement !is null) {
			context.focusedElement.value = context.focusedElement.value ~ cast(char) key;
			auto p = win.draw();
			drawElement(p, context.focusedElement, 0, 0);
		}

		if(s != scrollTop) {
			auto p = win.draw();
			p.clear();
			drawElement(p, context.document.mainBody, 0, 0);
		}

		if(key == 'q')
			win.close();
	});
}

class BrowsingContext {
	string currentUrl;
	Document document;
	Element focusedElement;
}

string absolutizeUrl(string url, string currentUrl) {
	if(url.length == 0)
		return null;

	auto current = currentUrl;
	auto idx = current.lastIndexOf("/");
	if(idx != -1 && idx > 7)
		current = current[0 .. idx + 1];

	if(url[0] == '/') {
		auto i = current[8 .. $].indexOf("/");
		if(i != -1)
			current = current[0 .. i + 8];
	}

	if(url.length < 7 || url[0 .. 7] != "http://")
		url = current ~ url;

	return url;
}

BrowsingContext _contextHack; // FIXME: the images aren't done sanely

import arsd.curl;
Document gotoSite(SimpleWindow win, BrowsingContext context, string url, string post = null) {
	_contextHack = context;

	auto p = win.draw;
	p.fillColor = Color(255, 255, 255);
	p.outlineColor = Color(0, 0, 0);
	p.drawRectangle(Point(0, 0), 800, 800);

	auto document = new Document(curl(url.absolutizeUrl(context.currentUrl), post));
	context.document = document;

	context.currentUrl = url.absolutizeUrl(context.currentUrl);

	string styleSheetText = import("default.css");

	foreach(ele; document.querySelectorAll("head link[rel=stylesheet]")) {
		if(!ele.hasAttribute("media") || ele.attrs.media().indexOf("screen") != -1)
			styleSheetText ~= curl(ele.href.absolutizeUrl(context.currentUrl));
	}

	foreach(ele; document.getElementsByTagName("style"))
		styleSheetText ~= ele.innerHTML;

	styleSheetText = styleSheetText.replace(`@import "/style_common.css";`, curl("http://arsdnet.net/style_common.css"));

	auto styleSheet = new StyleSheet(styleSheetText);
	styleSheet.apply(document);

	foreach(e; document.root.tree)
		LayoutData.get(e); // initializing the css here

	return document;
}


string impossible() {
	assert(0);
	//return null;
}

