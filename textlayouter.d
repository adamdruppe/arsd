/++
	A homemade text layout and editing engine, designed for the needs of minigui's custom widgets to be good enough for me to use. May or may not work for you.


	You use it by creating a [TextLayouter] and populating it with some data. Then you connect it to a user interface which calls [TextLayouter.getDrawableText] to know what and where to display the content and manipulates the content through the [Selection] object. Your text has styles applied to it through a [TextStyle] interface, which is deliberately minimal for the layouter - you are expected to cast it back to your implementation as-needed to get your other data out.

	See the docs on each of those objects for more details.

	Bugs:
		BiDi and right-to-left text in general is not yet implemented. I'm pretty sure I can do it, but I need unicode tables that aren't available to arsd yet.

		Doesn't do text kerning since the other implementations I've looked at on-screen don't do it either so it seems unnecessary. I might revisit this.

		Also doesn't handle shaped text, which breaks click point detection on Windows for certain script families.

		The edit implementation is a simple string. It performs surprisingly well, but I'll probably go back to it and change to a gap buffer later.

		Relaying out and saving state is only partially incremental at this time.

		The main interfaces are written with eventually fixing these in mind, but I might have to extend the [MeasurableFont] and [TextStyle] interfaces, and it might need some helper objects injected too. So possible they will be small breaking changes to support these, but I'm pretty sure it won't require any major rewrites of the code nor of user code when these are added, just adding methods to interfaces.

	History:
		Written in December 2022. Released in arsd 11.0.
+/
module arsd.textlayouter;

// see: https://harfbuzz.github.io/a-simple-shaping-example.html


// FIXME: unicode private use area could be delegated out but it might also be used by something else.
// just really want an encoding scheme for replaced elements that punt it outside..

import arsd.simpledisplay;

/+
	FIXME: caret style might need to be separate from anything drawn.
	FIXME: when adding things, inform new sizes for scrollbar updates in real time
	FIXME: scroll when selecting and dragging oob. generally capture on mouse down and release on mouse up.
	FIXME: page up, page down.

	FIXME: there is a spot right between some glyphs when changing fonts where it selected none.


	Need to know style at insertion point (which is the one before the caret codepoint unless it is at start of line, in which case it is the one at it)


	The style interface might actually want like toHtml and toRtf. at least on the minigui side, not strictly necessary here.
+/


/+
	subclass w/ style
	lazy layout queuing

	style info could possibly be a linked list but it prolly don't have to be anything too special

	track changes
+/

/+
	Word wrap needs to maintain indentation in some cases

	The left and right margins of exclusion area

	Exclusion are in the center?

	line-spacing

	if you click on the gap above a bounding box of a segment it doesn't find that segement despite being in the same line. need to check not just by segment bounding box but by line bounding box.

	FIXME: in sdpy, font is not reset upon returning from a child painter
	FIXME: in minigui the scrollbars can steal focus from the thing the are controlling
	FIXME: scw needs a per-button-click scroll amount since 1 may not be sufficient every time (tho 1 should be a possibility somehow)
+/

/+
	REPLACED CONTENT

		magic char followed by a dchar
		the dchar represents the replaced content array index
		replaced content needs to tell the layouter: ascent, descent, width.
		all replaced content gets its own special segment.
		replaced content must be registered and const? or at the very least not modify things the layouter cares about. but better if nothing changes for undo sake.

		it has a style but it only cares about the alignment from it.
+/

/+
	HTML
		generally take all the text nodes and make them have unique text style instances
		the text style can then refer back to the dom for click handling, css forwarding etc.

		but html has blocks...

	BLOCK ELEMENTS

		margin+padding behavior
		bounding box of nested things for background images and borders

		an inline-block gets this stuff but does not go on its own line.

	INLINE TABLES
+/

// FIXME: add center, left, right, justify and valign top, bottom, middle, baseline
// valign top = ascent = 0 of line. bottom = descent = bottom of line. middle = ascent+descent/2 = middle of line. baseline = matched baselines

// draw underline and strike through line segments - the offets may be in the font and underline might not want to slice the bottom fo p etc
// drawble textm ight give the offsets into the slice after all, and/or give non-trabable character things


// You can do the caret by any time it gets drawn, you set the flag that it is on, then you can xor it to turn it off and keep track of that at top level.


/++
	Represents the style of a span of text.

	You should never mutate one of these, instead construct a new one.

	Please note that methods may be added to this interface without being a full breaking change.
+/
interface TextStyle {
	/++
		Must never return `null`.
	+/
	MeasurableFont font();

	// FIXME: I might also want a duplicate function for saving state.

	// verticalAlign?

	// i should keep a refcount here, then i can do a COW if i wanted to.

	// you might use different style things to represent different  html elements or something too for click responses.

	/++
		You can mix this in to your implementation class to get default implementations of new methods I add.

		You will almost certainly want to override the things anyway, but this can help you keep things compiling.

		Please note that there is no default for font.
	+/
	static mixin template Defaults() {
		/++
			The default returns a [TerminalFontRepresentation]. This is almost certainly NOT what you want,
			so implement your own `font()` member anyway.
		+/
		MeasurableFont font() {
			return TerminalFontRepresentation.instance;
		}

	}
}

/++
	This is a demo implementation of [MeasurableFont]. The expectation is more often that you'd use a [arsd.simpledisplay.OperatingSystemFont], which also implements this interface, but if you wanted to do your own thing this basic demo might help.
+/
class TerminalFontRepresentation : MeasurableFont {
	static TerminalFontRepresentation instance() {
		static TerminalFontRepresentation i;
		if(i is null)
			i = new TerminalFontRepresentation();
		return i;
	}

	bool isMonospace() { return true; }
	int averageWidth() { return 1; }
	int height() { return 1; }
	/// since it is a grid this is a bit bizarre to translate.
	int ascent() { return 1; }
	int descent() { return 0; }

	int stringWidth(scope const(char)[] s, SimpleWindow window = null) {
		int count;
		foreach(dchar ch; s)
			count++;
		return count;
	}
}

/++
	A selection has four pieces:

	1) A position
	2) An anchor
	3) A focus
	4) A user coordinate

	The user coordinate should only ever be changed in direct response to actual user action and indicates
	where they ideally want the focus to be.

	If they move in the horizontal direction, the x user coordinate should change. The y should not, even if the actual focus moved around (e.g. moving to a previous line while left arrowing).

	If they move in a vertical direction, the y user coordinate should change. The x should not even if the actual focus moved around (e.g. going to the end of a shorter line while up arrowing).

	The position, anchor, and focus are stored in opaque units. The user coordinate is EITHER grid coordinates (line, glyph) or screen coordinates (pixels).

	Most methods on the selection move the position. This is not visible to the user, it is just an internal marker.

	setAnchor() sets the anchor to the current position.
	setFocus() sets the focus to the current position.

	The anchor is the part of the selection that doesn't move as you drag. The focus is the part of the selection that holds the caret and would move as you dragged around. (Open a program like Notepad and click and drag around. Your first click set the anchor, then as you drag, the focus moves around. The selection is everything between the anchor and the focus.)

	The selection, while being fairly opaque, lets you do a great many things. Consider, for example, vim's 5dd command - delete five lines from the current position. You can do this by taking a selection, going to the beginning of the current line. Then dropping anchor. Then go down five lines and go to end of line. Then extend through the EOL character. Now delete the selection. Finally, restore the anchor and focus from the user coordinate, so their cursor on screen remains in the same approximate position.

	The code can look something like this:

	---
	selection
		.moveHome
		.setAnchor
		.moveDown(5)
		.moveEnd
		.moveForward(&isEol)
		.setFocus
		.deleteContent
		.moveToUserCoordinate
		.setAnchor;
	---

	If you can think about how you'd do it on the standard keyboard, you can do it with this api. Everything between a setAnchor and setFocus would be like holding shift while doing the other things.

	void selectBetween(Selection other);

	Please note that this is just a handle to another object. Treat it as a reference type.
+/
public struct Selection {
	/++
		You cannot construct these yourself. Instead, use [TextLayouter.selection] to get it.
	+/
	@disable this();
	private this(TextLayouter layouter, int selectionId) {
		this.layouter = layouter;
		this.selectionId = selectionId;
	}
	private TextLayouter layouter;
	private int selectionId;

	private ref SelectionImpl impl() {
		return layouter._selections[selectionId];
	}

	/+ Inspection +/

	/++
		Returns `true` if the selection is currently empty. An empty selection still has a position - where the cursor is drawn - but has no text inside it.

		See_Also:
			[getContent], [getContentString]
	+/
	bool isEmpty() {
		return impl.focus == impl.anchor;
	}

	/++
		Function to get the content of the selection. It is fed to you as a series of zero or more chunks of text and style information.

		Please note that some text blocks may be empty, indicating only style has changed.

		See_Also:
			[getContentString], [isEmpty]
	+/
	void getContent(scope void delegate(scope const(char)[] text, TextStyle style) dg) {
		dg(layouter.text[impl.start .. impl.end], null); // FIXME: style
	}

	/++
		Convenience function to get the content of the selection as a simple string.

		See_Also:
			[getContent], [isEmpty]
	+/
	string getContentString() {
		string s;
		getContent((txt, style) {
			s ~= txt;
		});
		return s;
	}

	// need this so you can scroll found text into view and similar
	Rectangle focusBoundingBox() {
		return layouter.boundingBoxOfGlyph(layouter.findContainingSegment(impl.focus), impl.focus);
	}

	/+ Setting the explicit positions to the current internal position +/

	/++
		These functions set the actual selection from the current internal position.

		A selection has two major pieces, the anchor and the focus, and a third bookkeeping coordinate, called the user coordinate.

		It is best to think about these by thinking about the user interface. When you click and drag in a text document, the point where
		you clicked is the anchor position. As you drag, it moves the focus position. The selection is all the text between the anchor and
		focus. The cursor (also known as the caret) is drawn at the focus point.

		Meanwhile, the user coordinate is the point where the user last explicitly moved the focus. Try clicking near the end of a long line,
		then moving up past a short line, to another long line. Your cursor should remain near the column of the original click, even though
		the focus moved left while passing through the short line. The user coordinate is how this is achieved - explicit user action on the
		horizontal axis (like pressing the left or right arrows) sets the X coordinate with [setUserXCoordinate], and explicit user action on the vertical axis sets the Y coordinate (like the up or down arrows) with [setUserYCoordinate], leaving X alone even if the focus moved horizontally due to a shorter or longer line. They're only moved together if the user action worked on both axes together (like a mouse click) with the [setUserCoordinate] function. Note that `setUserCoordinate` remembers the column even if there is no glyph there, making it ideal for mouse interaction, whereas the `setUserXCoordinate` and `setUserYCoordinate` set it to the position of the glyph on the focus, making them more suitable for keyboard interaction.

		Before you set one of these values, you move the internal position with the `move` family of functions ([moveTo], [moveLeft], etc.).

		Setting the anchor also always sets the focus.

		For example, to select the whole document:

		---
		with(selection) {
			moveToStartOfDocument(); // changes internal position without affecting the actual selection
			setAnchor(); // set the anchor, actually changing the selection.
			// Note that setting the anchor also always sets the focus, so the selection is empty at this time.
			moveToEndOfDocument(); // move the internal position to the end
			setFocus(); // and now set the focus, which extends the selection from the anchor, meaning the whole document is selected now
		}
		---

		I didn't set the user coordinate there since the user's action didn't specify a row or column.
	+/
	Selection setAnchor() {
		impl.anchor = impl.position;
		impl.focus = impl.position;
		// layouter.notifySelectionChanged();
		return this;
	}

	/// ditto
	Selection setFocus() {
		impl.focus = impl.position;
		// layouter.notifySelectionChanged();
		return this;
	}

	/// ditto
	Selection setUserCoordinate(Point p) {
		impl.virtualFocusPosition = p;
		return this;
	}

	/// ditto
	Selection setUserXCoordinate() {
		impl.virtualFocusPosition.x = layouter.boundingBoxOfGlyph(layouter.findContainingSegment(impl.position), impl.position).left;
		return this;
	}

	/// ditto
	Selection setUserYCoordinate() {
		impl.virtualFocusPosition.y = layouter.boundingBoxOfGlyph(layouter.findContainingSegment(impl.position), impl.position).top;
		return this;
	}

	/++
		Gets the current user coordinate, the point where they explicitly want the caret to be near.

		History:
			Added January 24, 2025
	+/
	Point getUserCoordinate() {
		return impl.virtualFocusPosition;
	}

	/+ Moving the internal position +/

	/++

	+/
	Selection moveTo(Point p, bool setUserCoordinate = true) {
		impl.position = layouter.offsetOfClick(p);
		if(setUserCoordinate)
			impl.virtualFocusPosition = p;
		return this;
	}

	/++

	+/
	Selection moveToStartOfDocument() {
		impl.position = 0;
		return this;
	}

	/// ditto
	Selection moveToEndOfDocument() {
		impl.position = cast(int) layouter.text.length - 1; // never include the 0 terminator
		return this;
	}

	/++

	+/
	Selection moveToStartOfLine(bool byRender = true, bool includeLeadingWhitespace = true) {
		// FIXME: chekc for word wrap by checking segment.displayLineNumber
		// FIXME: includeLeadingWhitespace
		while(impl.position > 0 && layouter.text[impl.position - 1] != '\n')
			impl.position--;

		return this;
	}

	/// ditto
	Selection moveToEndOfLine(bool byRender = true) {
		// FIXME: chekc for word wrap by checking segment.displayLineNumber
		while(impl.position + 1 < layouter.text.length && layouter.text[impl.position] != '\n') // never include the 0 terminator
			impl.position++;
		return this;
	}

	/++
		If the position is abutting an end of line marker, it moves past it, to include it.
		If not, it does nothing.

		The intention is so you can delete a whole line by doing:

		---
		with(selection) {
			moveToStartOfLine();
			setAnchor();
			// this moves to the end of the visible line, but if you stopped here, you'd be left with an empty line
			moveToEndOfLine();
			// this moves past the line marker, meaning you don't just delete the line's content, it deletes the entire line
			moveToIncludeAdjacentEndOfLineMarker();
			setFocus();
			replaceContent("");
		}
		---
	+/
	Selection moveToIncludeAdjacentEndOfLineMarker() {
		// FIXME: i need to decide what i want to do about \r too. Prolly should remove it at the boundaries.
		if(impl.position + 1 < layouter.text.length && layouter.text[impl.position] == '\n') { // never include the 0 terminator
			impl.position++;
		}
		return this;
	}

	// note there's move up / down / left / right
	// in addition to move forward / backward glyph/line
	// the directions always match what's on screen.
	// the others always match the logical order in the string.
	/++

	+/
	Selection moveUp(int count = 1, bool byRender = true) {
		verticalMoveImpl(-1, count, byRender);
		return this;
	}

	/// ditto
	Selection moveDown(int count = 1, bool byRender = true) {
		verticalMoveImpl(1, count, byRender);
		return this;
	}

	/// ditto
	Selection moveLeft(int count = 1, bool byRender = true) {
		horizontalMoveImpl(-1, count, byRender);
		return this;
	}

	/// ditto
	Selection moveRight(int count = 1, bool byRender = true) {
		horizontalMoveImpl(1, count, byRender);
		return this;
	}

	/+
	enum PlacementOfFind {
		beginningOfHit,
		endOfHit
	}

	enum IfNotFound {
		changeNothing,
		moveToEnd,
		callDelegate
	}

	enum CaseSensitive {
		yes,
		no
	}

	void find(scope const(char)[] text, PlacementOfFind placeAt = PlacementOfFind.beginningOfHit, IfNotFound ifNotFound = IfNotFound.changeNothing) {
	}
	+/

	/++
		Does a custom search through the text.

		Params:
			predicate = a search filter. It passes you back a slice of your buffer filled with text at the current search position. You pass the slice of this buffer that matched your search, or `null` if there was no match here. You MUST return either null or a slice of the buffer that was passed to you. If you return an empty slice of of the buffer (buffer[0..0] for example), it cancels the search.

			The window buffer will try to move one code unit at a time. It may straddle code point boundaries - you need to account for this in your predicate.

			windowBuffer = a buffer to temporarily hold text for comparison. You should size this for the text you're trying to find

			searchBackward = determines the direction of the search. If true, it searches from the start of current selection backward to the beginning of the document. If false, it searches from the end of current selection forward to the end of the document.
		Returns:
			an object representing the search results and letting you manipulate the selection based upon it

	+/
	FindResult find(
		scope const(char)[] delegate(scope return const(char)[] buffer) predicate,
		int windowBufferSize,
		bool searchBackward,
	) {
		assert(windowBufferSize != 0, "you must pass a buffer of some size");

		char[] windowBuffer = new char[](windowBufferSize); // FIXME i don't need to actually copy in the current impl

		int currentSpot = impl.position;

		const finalSpot = searchBackward ? currentSpot : cast(int) layouter.text.length;

		if(searchBackward) {
			currentSpot -= windowBuffer.length;
			if(currentSpot < 0)
				currentSpot = 0;
		}

		auto endingSpot = currentSpot + windowBuffer.length;
		if(endingSpot > finalSpot)
			endingSpot = finalSpot;

		keep_searching:
		windowBuffer[0 .. endingSpot - currentSpot] = layouter.text[currentSpot .. endingSpot];
		auto result = predicate(windowBuffer[0 .. endingSpot - currentSpot]);
		if(result !is null) {
			// we're done, it was found
			auto offsetStart = result is null ? currentSpot : cast(int) (result.ptr - windowBuffer.ptr);
			assert(offsetStart >= 0 && offsetStart < windowBuffer.length);
			return FindResult(this, currentSpot + offsetStart, result !is null, currentSpot + cast(int) (offsetStart + result.length));
		} else if((searchBackward && currentSpot > 0) || (!searchBackward && endingSpot < finalSpot)) {
			// not found, keep searching
			if(searchBackward) {
				currentSpot--;
				endingSpot--;
			} else {
				currentSpot++;
				endingSpot++;
			}
			goto keep_searching;
		} else {
			// not found, at end of search
			return FindResult(this, currentSpot, false, currentSpot /* zero length result */);
		}

		assert(0);
	}

	/// ditto
	static struct FindResult {
		private Selection selection;
		private int position;
		private bool found;
		private int endPosition;

		///
		bool wasFound() {
			return found;
		}

		///
		Selection moveTo() {
			selection.impl.position = position;
			return selection;
		}

		///
		Selection moveToEnd() {
			selection.impl.position = endPosition;
			return selection;
		}

		///
		void selectHit() {
			selection.impl.position = position;
			selection.setAnchor();
			selection.impl.position = endPosition;
			selection.setFocus();
		}
	}



	/+
	/+ +
		Searches by regex.

		This is a template because the regex engine can be a heavy dependency, so it is only
		included if you need it. The RegEx object is expected to match the Phobos std.regex.RegEx
		api, so while you could, in theory, replace it, it is probably easier to just use the Phobos one.
	+/
	void find(RegEx)(RegEx re) {

	}
	+/

	/+ Manipulating the data in the selection +/

	/++
		Replaces the content of the selection. If you replace it with an empty `newText`, it will delete the content.

		If newText == "\b", it will delete the selection if it is non-empty, and otherwise delete the thing before the cursor.

		If you want to do normal editor backspace key, you might want to check `if(!selection.isEmpty()) selection.moveLeft();`
		before calling `selection.deleteContent()`. Similarly, for the delete key, you might use `moveRight` instead, since this
		function will do nothing for an empty selection by itself.

		FIXME: what if i want to replace it with some multiply styled text? Could probably call it in sequence actually.
	+/
	Selection replaceContent(scope const(char)[] newText, TextLayouter.StyleHandle style = TextLayouter.StyleHandle.init) {
		layouter.wasMutated_ = true;

		if(style == TextLayouter.StyleHandle.init)
			style = layouter.getInsertionStyleAt(impl.focus);

		int removeBegin, removeEnd;
		if(this.isEmpty()) {
			if(newText.length == 1 && newText[0] == '\b') {
				auto place = impl.focus;
				if(place > 0) {
					int amount = 1;
					while((layouter.text[place - amount] & 0b11000000) == 0b10000000) // all non-start bytes of a utf-8 sequence have this convenient property
						amount++; // assumes this will never go over the edge cuz of it being valid utf 8 internally

					removeBegin = place - amount;
					removeEnd = place;

					if(removeBegin < 0)
						removeBegin = 0;
					if(removeEnd < 0)
						removeEnd = 0;
				}

				newText = null;
			} else {
				removeBegin = impl.terminus;
				removeEnd = impl.terminus;
			}
		} else {
			removeBegin = impl.start;
			removeEnd = impl.end;
			if(newText.length == 1 && newText[0] == '\b') {
				newText = null;
			}
		}

		auto place = impl.terminus;

		auto changeInLength = cast(int) newText.length - (removeEnd - removeBegin);

		// FIXME: the horror
		auto trash = layouter.text[0 .. removeBegin];
		trash ~= newText;
		trash ~= layouter.text[removeEnd .. $];
		layouter.text = trash;

		impl.position = removeBegin + cast(int) newText.length;
		this.setAnchor();

		/+
			For styles:
				if one part resides in the deleted zone, it should be truncated to the edge of the deleted zone
				if they are entirely in the deleted zone - their new length is zero - they should simply be deleted
				if they are entirely before the deleted zone, it can stay the same
				if they are entirely after the deleted zone, they should get += changeInLength

				FIXME: if the deleted zone lies entirely inside one of the styles, that style's length should be extended to include the new text if it has no style, or otherwise split into a few style blocks

				However, the algorithm for default style in the new zone is a bit different: if at index 0 or right after a \n, it uses the next style. otherwise it uses the previous one.
		+/

		//writeln(removeBegin, " ", removeEnd);
		//foreach(st; layouter.styles) writeln("B: ", st.offset, "..", st.offset + st.length, " ", st.styleInformationIndex);

		// first I'm going to update all of them so it is in a consistent state
		foreach(ref st; layouter.styles) {
			auto begin = st.offset;
			auto end = st.offset + st.length;

			void adjust(ref int what) {
				if(what < removeBegin) {
					// no change needed
				} else if(what >= removeBegin && what < removeEnd) {
					what = removeBegin;
				} else if(what) {
					what += changeInLength;
				}
			}

			adjust(begin);
			adjust(end);

			assert(end >= begin); // empty styles are not permitted by the implementation
			st.offset = begin;
			st.length = end - begin;
		}

		// then go back and inject the new style, if needed
		if(changeInLength > 0) {
			changeStyle(removeBegin, removeBegin + cast(int) newText.length, style);
		}

		removeEmptyStyles();

		// or do i want to use init to just keep using the same style as is already there?
		// FIXME
		//if(style !is StyleHandle.init) {
			// styles ~= StyleBlock(cast(int) before.length, cast(int) changeInLength, style.index);
		//}


		auto endInvalidate = removeBegin + newText.length;
		if(removeEnd > endInvalidate)
			endInvalidate = removeEnd;
		layouter.invalidateLayout(removeBegin, endInvalidate, changeInLength);

		// there's a new style from removeBegin to removeBegin + newText.length

		// FIXME other selections in the zone need to be adjusted too
		// if they are in the deleted zone, it should be moved to the end of the new zone (removeBegin + newText.length)
		// if they are before the deleted zone, they can stay the same
		// if they are after the deleted zone, they should be adjusted by changeInLength
		foreach(idx, ref selection; layouter._selections[0 .. layouter.selectionsInUse]) {

			// don't adjust ourselves here, we already did it above
			// and besides don't want mutation in here
			if(idx == selectionId)
				continue;

			void adjust(ref int what) {
				if(what < removeBegin) {
					// no change needed
				} else if(what >= removeBegin && what < removeEnd) {
					what = removeBegin;
				} else if(what) {
					what += changeInLength;
				}
			}

			adjust(selection.anchor);
			adjust(selection.terminus);
		}
			// you might need to set the user coordinate after this!

		return this;
	}

	private void removeEmptyStyles() {
		/+ the code doesn't like empty style blocks, so gonna go back and remove those +/
		for(int i = 0; i < cast(int) layouter.styles.length; i++) {
			if(layouter.styles[i].length == 0) {
				for(auto i2 = i; i2 + 1 < layouter.styles.length; i2++)
					layouter.styles[i2] = layouter.styles[i2 + 1];
				layouter.styles = layouter.styles[0 .. $-1];
				layouter.styles.assumeSafeAppend();
				i--;
			}
		}
	}

	/++
		Changes the style of the given selection. Gives existing styles in the selection to your delegate
		and you return a new style to assign to that block.
	+/
	public void changeStyle(TextLayouter.StyleHandle delegate(TextStyle existing) newStyle) {
		// FIXME there might be different sub-styles so we should actually look them up and send each one
		auto ns = newStyle(null);
		changeStyle(impl.start, impl.end, ns);
		removeEmptyStyles();

		layouter.invalidateLayout(impl.start, impl.end, 0);
	}

	/+ Impl helpers +/

	private void changeStyle(int newStyleBegin, int newStyleEnd, TextLayouter.StyleHandle style) {
		// FIXME: binary search
		for(size_t i = 0; i < layouter.styles.length; i++) {
			auto s = &layouter.styles[i];
			const oldStyleBegin = s.offset;
			const oldStyleEnd = s.offset + s.length;

			if(newStyleBegin >= oldStyleBegin && newStyleBegin < oldStyleEnd) {
				// the cases:

				// it is an exact match in size, we can simply overwrite it
				if(newStyleBegin == oldStyleBegin && newStyleEnd == oldStyleEnd) {
					s.styleInformationIndex = style.index;
					break; // all done
				}
				// we're the same as the existing style, so it is just a matter of extending it to include us
				else if(s.styleInformationIndex == style.index) {
					if(newStyleEnd > oldStyleEnd) {
						s.length = newStyleEnd - oldStyleBegin;

						// then need to fix up all the subsequent blocks, adding the offset, reducing the length
						int remainingFixes = newStyleEnd - oldStyleEnd;
						foreach(st; layouter.styles[i + 1 .. $]) {
							auto thisFixup = remainingFixes;
							if(st.length < thisFixup)
								thisFixup = st.length;
							// this can result in 0 length, the loop after this will delete that.
							st.offset += thisFixup;
							st.length -= thisFixup;

							remainingFixes -= thisFixup;

							assert(remainingFixes >= 0);

							if(remainingFixes == 0)
								break;
						}
					}
					// otherwise it is all already there and nothing need be done at all
					break;
				}
				// for the rest of the cases, the style does not match and is not a size match,
				// so a new block is going to have to be inserted
				// ///////////
				// we're entirely contained inside, so keep the left, insert ourselves, and re-create right.
				else if(newStyleEnd > oldStyleBegin && newStyleEnd < oldStyleEnd) {
					// keep the old style on the left...
					s.length = newStyleBegin - oldStyleBegin;

					auto toInsert1 = TextLayouter.StyleBlock(newStyleBegin, newStyleEnd - newStyleBegin, style.index);
					auto toInsert2 = TextLayouter.StyleBlock(newStyleEnd, oldStyleEnd - newStyleEnd, s.styleInformationIndex);

					layouter.styles = layouter.styles[0 .. i + 1] ~ toInsert1 ~ toInsert2 ~ layouter.styles[i + 1 .. $];

					// writeln(*s); writeln(toInsert1); writeln(toInsert2);

					break; // no need to continue processing as the other offsets are unaffected
				}
				// we need to keep the left end of the original thing, but then insert ourselves on afterward
				else if(newStyleBegin >= oldStyleBegin) {
					// want to just shorten the original thing, then adjust the values
					// so next time through the loop can work on that existing block

					s.length = newStyleBegin - oldStyleBegin;

					// extend the following style to start here, so there's no gap in the next loop iteration
					if(i + i < layouter.styles.length) {
						auto originalOffset = layouter.styles[i+1].offset;
						assert(originalOffset >= newStyleBegin);
						layouter.styles[i+1].offset = newStyleBegin;
						layouter.styles[i+1].length += originalOffset - newStyleBegin;

						// i will NOT change the style info index yet, since the next iteration will do that
						continue;
					} else {
						// at the end of the loop we can just append the new thing and break out of here
						layouter.styles ~= TextLayouter.StyleBlock(newStyleBegin, newStyleEnd - newStyleBegin, style.index);
						break;
					}
				}
				else {
					// this should be impossible as i think i covered all the cases above
					// as we iterate through
					// writeln(oldStyleBegin, "..", oldStyleEnd, " -- ", newStyleBegin, "..", newStyleEnd);
					assert(0);
				}
			}
		}

		// foreach(st; layouter.styles) writeln("A: ", st.offset, "..", st.offset + st.length, " ", st.styleInformationIndex);
	}

	// returns the edge of the new cursor position
	private void horizontalMoveImpl(int direction, int count, bool byRender) {
		assert(direction != 0);

		auto place = impl.focus + direction;

		foreach(c; 0 .. count) {
			while(place >= 0 && place < layouter.text.length && (layouter.text[place] & 0b11000000) == 0b10000000) // all non-start bytes of a utf-8 sequence have this convenient property
				place += direction;
		}

		// FIXME if(byRender), if we're on a rtl line, swap the things. but if it is mixed it won't even do anything and stay in logical order

		if(place < 0)
			place = 0;
		if(place >= layouter.text.length)
			place = cast(int) layouter.text.length - 1;

		impl.position = place;

	}

	// returns the baseline of the new cursor
	private void verticalMoveImpl(int direction, int count, bool byRender) {
		assert(direction != 0);
		// this needs to find the closest glyph on the virtual x on the previous (rendered) line

		int segmentIndex = layouter.findContainingSegment(impl.terminus);

		// we know this is going to lead to a different segment since
		// the layout breaks up that way, so we can just go straight backward

		auto segment = layouter.segments[segmentIndex];

		auto idealX = impl.virtualFocusPosition.x;

		auto targetLineNumber = segment.displayLineNumber + (direction * count);
		if(targetLineNumber < 0)
			targetLineNumber = 0;

		// FIXME if(!byRender)


		// FIXME: when you are going down, a line that begins with tab doesn't highlight the right char.

		int bestHit = -1;
		int bestHitDistance = int.max;

		// writeln(targetLineNumber, " ", segmentIndex, " ", layouter.segments.length);

		segmentLoop: while(segmentIndex >= 0 && segmentIndex < layouter.segments.length) {
			segment = layouter.segments[segmentIndex];
			if(segment.displayLineNumber == targetLineNumber) {
				// we're in the right line... but not necessarily the right segment
				// writeln("line found");
				if(idealX >= segment.boundingBox.left && idealX < segment.boundingBox.right) {
					// need to find the exact thing in here

					auto hit = segment.textBeginOffset;
					auto ul = segment.upperLeft;

					bool found;
					auto txt = layouter.text[segment.textBeginOffset .. segment.textEndOffset];
					auto codepoint = 0;
					foreach(idx, dchar d; txt) {
						auto width = layouter.segmentsWidths[segmentIndex][codepoint];

						hit = segment.textBeginOffset + cast(int) idx;

						auto distanceToLeft = ul.x - idealX;
						if(distanceToLeft < 0) distanceToLeft = -distanceToLeft;
						if(distanceToLeft < bestHitDistance) {
							bestHit = hit;
							bestHitDistance = distanceToLeft;
						} else {
							// getting further away = no help
							break;
						}

						/*
						// FIXME: I probably want something slightly different
						if(ul.x >= idealX) {
							found = true;
							break;
						}
						*/

						ul.x += width;
						codepoint++;
					}

					/*
					if(!found)
						hit = segment.textEndOffset - 1;

					impl.position = hit;
					bestHit = -1;
					*/

					impl.position = bestHit;
					bestHit = -1;

					// selections[selectionId].virtualFocusPosition = Point(selections[selectionId].virtualFocusPosition.x, segment.boundingBox.bottom);

					break segmentLoop;
				} else {
					// FIXME: assuming ltr here
					auto distance = idealX - segment.boundingBox.right;
					if(distance < 0)
						distance = -distance;
					if(bestHit == -1 || distance < bestHitDistance) {
						bestHit = segment.textEndOffset - 1;
						bestHitDistance = distance;
					}
				}
			} else if(bestHit != -1) {
				impl.position = bestHit;
				bestHit = -1;
				break segmentLoop;
			}

			segmentIndex += direction;
		}

		if(bestHit != -1)
			impl.position = bestHit;

		if(impl.position == layouter.text.length)
			impl.position -- ; // never select the eof marker
	}
}

unittest {
	auto l = new TextLayouter(new class TextStyle {
		mixin Defaults;
	});

	l.appendText("this is a test string again");
	auto s = l.selection();
	auto result = s.find(b => (b == "a") ? b : null, 1, false);
	assert(result.wasFound);
	assert(result.position == 8);
	assert(result.endPosition == 9);
	result.selectHit();
	assert(s.getContentString() == "a");
	result.moveToEnd();
	result = s.find(b => (b == "a") ? b : null, 1, false); // should find next
	assert(result.wasFound);
	assert(result.position == 22);
	assert(result.endPosition == 23);
}

private struct SelectionImpl {
	// you want multiple selections at most points
	int id;
	int anchor;
	int terminus;

	int position;

	alias focus = terminus;

	/+
		As you move through lines of different lengths, your actual x will change,
		but the user will want to stay in the same relative spot, consider passing:

		long thing
		short
		long thing

		from the 'i'. When you go down, you'd be back by the t, but go down again, you should
		go back to the i. This variable helps achieve this.
	+/
	Point virtualFocusPosition;

	int start() {
		return anchor <= terminus ? anchor : terminus;
	}
	int end() {
		return anchor <= terminus ? terminus : anchor;
	}
	bool empty() {
		return anchor == terminus;
	}
	bool containsOffset(int textOffset) {
		return textOffset >= start && textOffset < end;
	}
	bool isIncludedInRange(int textStart, int textEnd) {
		// if either end are in there, we're obviously in the range
		if((start >= textStart && start < textEnd) || (end >= textStart && end < textEnd))
			return true;
		// or if the selection is entirely inside the given range...
		if(start >= textStart && end < textEnd)
			return true;
		// or if the given range is at all inside the selection
		if((textStart >= start && textStart < end) || (textEnd >= start && textEnd < end))
			return true;
		return false;
	}
}

/++
	Bugs:
		Only tested on Latin scripts at this time. Other things should be possible but might need work. Let me know if you need it and I'll see what I can do.
+/
class TextLayouter {


	// actually running this invariant gives quadratic performance in the layouter (cuz of isWordwrapPoint lol)
	// so gonna only version it in for special occasions
	version(none)
	invariant() {
		// There is one and exactly one segment for every char in the string.
		// The segments are stored in sequence from index 0 to the end of the string.
		// styleInformationIndex is always in bounds of the styles array.
		// There is one and exactly one style block for every char in the string.
		// Style blocks are stored in sequence from index 0 to the end of the string.

		assert(text.length > 0 && text[$-1] == 0);
		assert(styles.length >= 1);
		int last = 0;
		foreach(style; styles) {
			assert(style.offset == last); // all styles must be in order and contiguous
			assert(style.length > 0); // and non-empty
			assert(style.styleInformationIndex != -1); // and not default constructed (this should be resolved before adding)
			assert(style.styleInformationIndex >= 0 && style.styleInformationIndex < stylePalette.length); // all must be in-bounds
			last = style.offset + style.length;
		}
		assert(last == text.length); // and all chars in the array must be covered by a style block
	}

	/+
	private void notifySelectionChanged() {
		if(onSelectionChanged !is null)
			onSelectionChanged(this);
	}

	/++
		A delegate called when the current selection is changed through api or user action.

		History:
			Added July 10, 2024
	+/
	void delegate(TextLayouter l) onSelectionChanged;
	+/

	/++
		Gets the object representing the given selection.

		Normally, id = 0 is the user's selection, then id's 60, 61, 62, and 63 are private to the application.
	+/
	Selection selection(int id = 0) {
		assert(id >= 0 && id < _selections.length);
		return Selection(this, id);
	}

	/++
		The rendered size of the text.
	+/
	public int width() {
		relayoutIfNecessary();
		return _width;
	}

	/// ditto
	public int height() {
		relayoutIfNecessary();
		return _height;
	}

	static struct State {
		// for the delta compression, the text is the main field to worry about
		// and what it really needs to know is just based on what, then what is added and what is removed.
		// i think everything else i'd just copy in (or reference the same array) anyway since they're so
		// much smaller anyway.
		//
		// and if the text is small might as well just copy/reference it too tbh.
		private {
			char[] text;
			TextStyle[] stylePalette;
			StyleBlock[] styles;
			SelectionImpl[] selections;
		}
	}

	// for manual undo stuff
	// and all state should be able to do do it incrementally too; each modification to those should be compared.
	/++
		The editor's internal state can be saved and restored as an opaque blob. You might use this to make undo checkpoints and similar.

		Its implementation may use delta compression from a previous saved state, it will try to do this transparently for you to save memory.
	+/
	const(State)* saveState() {
		return new State(text.dup, stylePalette.dup, styles.dup, _selections.dup);
	}
	/// ditto
	void restoreState(const(State)* state) {
		auto changeInLength = cast(int) this.text.length - cast(int) state.text.length;
		this.text = state.text.dup;
		// FIXME: bad cast
		this.stylePalette = (cast(TextStyle[]) state.stylePalette).dup;
		this.styles = state.styles.dup;
		this._selections = state.selections.dup;

		invalidateLayout(0, text.length, changeInLength);
	}

	// FIXME: I might want to make the original line number exposed somewhere too like in the segment draw information

	// FIXME: all the actual content - styles, text, and selection stuff - needs to be able to communicate its changes
	// incrementally for the network use case. the segments tho not that important.

	// FIXME: for the password thing all the glyph positions need to be known to this system, so it can't just draw it
	// that way (unless it knows it is using a monospace font... but we can trick it by giving it a fake font that gives all those metrics)
	// so actually that is the magic lol

	private static struct StyleBlock {
		int offset;
		int length;

		int styleInformationIndex;
	}

	/+
	void resetSelection(int selectionId) {

	}

	// FIXME: is it moving teh anchor or the focus?
	void extendSelection(int selectionId, bool fromBeginning, bool direction, int delegate(scope const char[] c) handler) {
		// iterates through the selection, giving you the chars, until you return 0
		// can use this to do things like delete words in front of cursor
	}

	void duplicateSelection(int receivingSelectionId, int sourceSelectionId) {

	}
	+/

	private int findContainingSegment(int textOffset) {

		relayoutIfNecessary();

		// FIXME: binary search

		// FIXME: when the index is here, use it
		foreach(idx, segment; segments) {
			// this assumes the segments are in order of text offset
			if(textOffset >= segment.textBeginOffset && textOffset < segment.textEndOffset)
				return cast(int) idx;
		}
		assert(0);
	}

	// need page up+down, home, edit, arrows, etc.

	/++
		Finds the given text, setting the given selection to it, if found.

		Starts from the given selection and moves in the direction to find next.

		Returns true if found.

		NOT IMPLEMENTED use a selection instead
	+/
	FindResult find(int selectionId, in const(char)[] text, bool direction, bool wraparound) {
		return FindResult.NotFound;
	}
	/// ditto
	enum FindResult : int {
		NotFound = 0,
		Found = 1,
		WrappedAround = 2
	}

	private bool wasMutated_ = false;
	/++
		The layouter maintains a flag to tell if the content has been changed.
	+/
	public bool wasMutated() {
		return wasMutated_;
	}

	/// ditto
	public void clearWasMutatedFlag() {
		wasMutated_ = false;
	}

	/++
		Represents a possible registered style for a segment of text.
	+/
	public static struct StyleHandle {
		private this(int idx) { this.index = idx; }
		private int index = -1;
	}

	/++
		Registers a text style you can use in text segments.
	+/
	// FIXME: i might have to construct it internally myself so i can return it const.
	public StyleHandle registerStyle(TextStyle style) {
		stylePalette ~= style;
		return StyleHandle(cast(int) stylePalette.length - 1);
	}


	/++
		Appends text at the end, without disturbing user selection.
	+/
	public void appendText(scope const(char)[] text, StyleHandle style = StyleHandle.init) {
		wasMutated_ = true;
		auto before = this.text;
		this.text.length += text.length;
		this.text[before.length-1 .. before.length-1 + text.length] = text[];
		this.text[$-1] = 0; // gotta maintain the zero terminator i use
		// or do i want to use init to just keep using the same style as is already there?
		if(style is StyleHandle.init) {
			// default is to extend the existing style
			styles[$-1].length += text.length;
		} else {
			// otherwise, insert a new block for it
			styles[$-1].length -= 1; // it no longer covers the zero terminator

			// but this does, hence the +1
			styles ~= StyleBlock(cast(int) before.length - 1, cast(int) text.length + 1, style.index);
		}

		invalidateLayout(cast(int) before.length - 1 /* zero terminator */, this.text.length, cast(int) text.length);
	}

	/++
		Calls your delegate for each segment of the text, guaranteeing you will be called exactly once for each non-nil char in the string and each slice will have exactly one style. A segment may be as small as a single char.

		FIXME: have a getTextInSelection

		FIXME: have some kind of index stuff so you can select some text found in here (think regex search)

		This function might be cut in a future version in favor of [getDrawableText]
	+/
	void getText(scope void delegate(scope const(char)[] segment, TextStyle style) handler) {
		handler(text[0 .. $-1], null); // cut off the null terminator
	}

	/++
		Gets the current text value as a plain-text string.
	+/
	string getTextString() {
		string s;
		getText((segment, style) {
			s ~= segment;
		});
		return s;
	}

	alias getContentString = getTextString;

	public static struct DrawingInformation {
		Rectangle boundingBox;
		Point initialBaseline;
		ulong selections; // 0 if not selected. bitmask of selection ids otherwise

		int direction; // you start at initialBaseline then draw ltr or rtl or up or down.
		// might also store glyph id, which could be encoded texture # + position, stuff like that. if each segment were
		// a glyph at least which is sometimes needed but prolly not gonna stress abut that in my use cases, i'd rather batch.
	}

	public static struct CaretInformation {
		int id;
		Rectangle boundingBox;
	}

	// assumes the idx is indeed in the segment
	private Rectangle boundingBoxOfGlyph(size_t segmentIndex, int idx) {
		// I can't relayoutIfNecessary here because that might invalidate the segmentIndex!!
		// relayoutIfNecessary();
		auto segment = segments[segmentIndex];

		int codepointCounter = 0;
		auto bb = segment.boundingBox;
		foreach(thing, dchar cp; text[segment.textBeginOffset .. segment.textEndOffset]) {
			auto w = segmentsWidths[segmentIndex][codepointCounter];

			if(thing + segment.textBeginOffset == idx) {
				bb.right = bb.left + w;
				return bb;
			}

			bb.left += w;

			codepointCounter++;
		}

		bb.right = bb.left + 1;

		return bb;
	}

	/+
	void getTextAtPosition(Point p) {
		relayoutIfNecessary();
		// return the text in that segment, the style info attached, and if that specific point is part of a selection (can be used to tell if it should be a drag operation)
		// then might want dropTextAt(Point p)
	}
	+/

	/++
		Gets the text that you need to draw, guaranteeing each call to your delegate will:

		* Have a contiguous slice into text
		* Have exactly one style (which may be null, meaning use all your default values. Be sure you draw with the same font you passed as the default font to TextLayouter.)
		* Be a linear block of text that fits in a single rectangular segment
		* A segment will be as large a block of text as the implementation can do, but it may be as short as a single char.
		* The segment may be a special escape sequence. FIXME explain how to check this.

		Return `false` from your delegate to stop iterating through the text.

		Please note that the `caretPosition` can be `Rectangle.init`, indicating it is not present in this segment. If it is not that, it will be the bounding box of the glyph.

		You can use the `startFrom` parameter to skip ahead. The intended use case for this is to start from a scrolling position in the box; the first segment given will include this point. FIXME: maybe it should just go ahead and do a bounding box. Note that the segments may extend outside the point; it is just meant that it will include that and try to trim the rest.

		The segment may include all forms of whitespace, including newlines, tab characters, etc. Generally, a tab character will be in its own segment and \n will appear at the end of a segment. You will probably want to `stripRight` each segment depending on your drawing functions.
	+/
	public void getDrawableText(scope bool delegate(scope const(char)[] segment, TextStyle style, DrawingInformation information, CaretInformation[] carets...) dg, Rectangle box = Rectangle.init) {
		relayoutIfNecessary();
		getInternalSegments(delegate bool(size_t segmentIndex, scope ref Segment segment) {
			if(segment.textBeginOffset == -1)
				return true;

			TextStyle style;
			assert(segment.styleInformationIndex < stylePalette.length);

			style = stylePalette[segment.styleInformationIndex];

			ubyte[64] possibleSelections;
			int possibleSelectionsCount;

			CaretInformation[64] caretInformation;
			int cic;

			// bounding box reduction
			foreach(si, selection; _selections[0 .. selectionsInUse]) {
				if(selection.isIncludedInRange(segment.textBeginOffset, segment.textEndOffset)) {
					if(!selection.empty()) {
						possibleSelections[possibleSelectionsCount++] = cast(ubyte) si;
					}
					if(selection.focus >= segment.textBeginOffset && selection.focus < segment.textEndOffset) {

						// make sure the caret box represents that it would be if we actually
						// did the insertion, so adjust the bounding box to account for a possibly
						// different font

						auto insertionStyle = stylePalette[getInsertionStyleAt(selection.focus).index];
						auto glyphStyle = style;

						auto bb = boundingBoxOfGlyph(segmentIndex, selection.focus);

						bb.top += glyphStyle.font.ascent;
						bb.bottom -= glyphStyle.font.descent;

						bb.top -= insertionStyle.font.ascent;
						bb.bottom += insertionStyle.font.descent;

						caretInformation[cic++] = CaretInformation(cast(int) si, bb);
					}
				}
			}

			// the rest of this might need splitting based on selections

			DrawingInformation di;
			di.boundingBox = Rectangle(segment.upperLeft, Size(segment.width, segment.height));
			di.selections = 0;

			// di.initialBaseline = Point(x, y); // FIXME
			// FIXME if the selection focus is in this box, we should set the caretPosition to the bounding box of the associated glyph
			// di.caretPosition = Rectangle(x, y, w, h); // FIXME

			auto end = segment.textEndOffset;
			if(end == text.length)
				end--; // don't send the terminating 0 to the user as that's an internal detail

			auto txt = text[segment.textBeginOffset .. end];

			if(possibleSelectionsCount == 0) {
				// no selections present, no need to iterate
				// FIXME: but i might have to take some gap chars and such out anyway.
				return dg(txt, style, di, caretInformation[0 .. cic]);
			} else {
				ulong lastSel = 0;
				size_t lastSelPos = 0;
				size_t lastSelCodepoint = 0;
				bool exit = false;

				void sendSegment(size_t start, size_t end, size_t codepointStart, size_t codepointEnd) {
					di.selections = lastSel;

					Rectangle bbOriginal = di.boundingBox;

					int segmentWidth;

					foreach(width; segmentsWidths[segmentIndex][codepointStart .. codepointEnd]) {
						segmentWidth += width;
					}

					auto diFragment = di;
					diFragment.boundingBox.right = diFragment.boundingBox.left + segmentWidth;

					// FIXME: adjust the rest of di for this
					// FIXME: the caretInformation arguably should be truncated for those not in this particular sub-segment
					exit = !dg(txt[start .. end], style, diFragment, caretInformation[0 .. cic]);

					di.initialBaseline.x += segmentWidth;
					di.boundingBox.left += segmentWidth;

					lastSelPos = end;
					lastSelCodepoint = codepointEnd;
				}

				size_t codepoint = 0;

				foreach(ci, dchar ch; txt) {
					auto sel = selectionsAt(cast(int) ci + segment.textBeginOffset);
					if(sel != lastSel) {
						// send this segment

						sendSegment(lastSelPos, ci, lastSelCodepoint, codepoint);
						lastSel = sel;
						if(exit) return false;
					}

					codepoint++;
				}

				sendSegment(lastSelPos, txt.length, lastSelCodepoint, codepoint);
				if(exit) return false;
			}

			return true;
		}, box);
	}

	// returns any segments that may lie inside the bounding box. if the box's size is 0, it is unbounded and goes through all segments
	// may return more than is necessary; it uses the box as a hint to speed the search, not as the strict bounds it returns.
	protected void getInternalSegments(scope bool delegate(size_t idx, scope ref Segment segment) dg, Rectangle box = Rectangle.init) {
		relayoutIfNecessary();

		if(box.right == box.left)
			box.right = int.max;
		if(box.bottom == box.top)
			box.bottom = int.max;

		if(segments.length < 64 || box.top < 64) {
			foreach(idx, ref segment; segments) {
				if(dg(idx, segment) == false)
					break;
			}
		} else {
			int maximum = cast(int) segments.length;
			int searchPoint = maximum / 2;

			keepSearching:
			//writeln(searchPoint);
			if(segments[searchPoint].upperLeft.y > box.top) {
				// we're too far ahead to find the box
				maximum = searchPoint;
				auto newSearchPoint = maximum / 2;
				if(newSearchPoint == searchPoint) {
					searchPoint = newSearchPoint;
					goto useIt;
				}
				searchPoint = newSearchPoint;
				goto keepSearching;
			} else if(segments[searchPoint].boundingBox.bottom < box.top) {
				// the box is a way down from here still
				auto newSearchPoint = (maximum - searchPoint) / 2 + searchPoint;
				if(newSearchPoint == searchPoint) {
					searchPoint = newSearchPoint;
					goto useIt;
				}
				searchPoint = newSearchPoint;
				goto keepSearching;
			}

			useIt:

			auto line = segments[searchPoint].displayLineNumber;
			if(line) {
				// go to the line right before this to ensure we have everything in here
				while(searchPoint != 0 && segments[searchPoint].displayLineNumber == line)
					searchPoint--;
			}

			foreach(idx, ref segment; segments[searchPoint .. $]) {
				if(dg(idx + searchPoint, segment) == false)
					break;
			}
		}
	}

	private {
		// user code can add new styles to the palette
		TextStyle[] stylePalette;

		// if editable by user, these will change
		char[] text;
		StyleBlock[] styles;

		// the layout function calculates these
		Segment[] segments;
		short[][] segmentsWidths;
	}

	/++

	+/
	this(TextStyle defaultStyle) {
		this.stylePalette ~= defaultStyle;
		this.text = [0]; // i never want to let the editor go over, so this pseudochar makes that a bit easier
		this.styles ~= StyleBlock(0, 1, 0); // default style should never be deleted too at the end of the file
		this.invalidateLayout(0, 1, 0);
	}

	// maybe unstable
	TextStyle defaultStyle() {
		auto ts = this.stylePalette[0];
		invalidateLayout(0, text.length, 0); // assume they are going to mutate it
		return ts;
	}

	// most of these are unimplemented...
	bool editable;
	int wordWrapLength = 0;
	int delegate(int x) tabStop = null;
	int delegate(Rectangle line) leftOffset = null;
	int delegate(Rectangle line) rightOffset = null;
	int lineSpacing = 0;

	/+
		the function it could call is drawStringSegment with a certain slice of it, an offset (guaranteed to be rectangular) and then you do the styles. it does need to know the font tho.

		it takes a flag: UpperLeft or Baseline. this tells its coordinates for the string segment when you draw.

		The style can just be a void* or something, not really the problem of the layouter; it only cares about font metrics

		The layout thing needs to know:
			1) is it word wrapped
			2) a delegate for offset left for the given line height
			2) a delegate for offset right for the given line height

		GetSelection() returns the segments that are currently selected
		Caret position, if there is one

		Each TextLayouter can represent a block element in HTML terms. Centering and such done outside.
		Selections going across blocks is an exercise for the outside code (it'd select start to all of one, all of middle, all to end of last).


		EDITING:
			just like addText which it does replacing the selection if there is one or inserting/overstriking at the caret

			everything has an optional void* style which it does as offset-based overlays

			user responsibility to getSelection if they want to add something to the style
	+/

	private static struct Segment {
		// 32 bytes rn, i can reasonably save 6 with shorts
		// do i even need the segmentsWidths cache or can i reasonably recalculate it lazily?

		int textBeginOffset;
		int textEndOffset; // can make a short length i think

		int styleInformationIndex;

		// calculated values after iterating through the segment
		int width; // short
		int height; // short

		Point upperLeft;

		int displayLineNumber; // I might change this to be a fractional thing, like 24 bits line number, 8 bits fractional number (from word wrap) tho realistically i suspect an index of original lines would be easier to maintain (could only have one value per like 100 real lines cuz it just narrows down the linear search

		/*
		Point baseline() {

		}
		*/

		Rectangle boundingBox() {
			return Rectangle(upperLeft, Size(width, height));
		}
	}

	private int _width;
	private int _height;

	private SelectionImpl[64] _selections;
	private int selectionsInUse = 1;

	/++
		Selections have two parts: an anchor (typically set to where the user clicked the mouse down)
		and a focus (typically where the user released the mouse button). As you click and drag, you
		want to change the focus while keeping the anchor the same.

		The caret is drawn at the focus. If the anchor and focus are the same point, the selection
		is empty.

		Please note that the selection focus is different than a keyboard focus. (I'd personally prefer
		to call it a terminus, but I'm trying to use the same terminology as the web standards, even if
		I don't like it.)

		After calling this, you don't need to call relayout(), but you might want to redraw to show the
		user the result of this action.
	+/

	/+
		Returns the nearest offset in the text for the given point.

		it should return if it was inside the segment bounding box tho

		might make this private

		FIXME: the public one might be like segmentOfClick so you can get the style info out (which might hold hyperlink data)
	+/
	int offsetOfClick(Point p) {
		int idx = cast(int) text.length - 1;

		relayoutIfNecessary();

		if(p.y > _height)
			return idx;

		getInternalSegments(delegate bool(size_t segmentIndex, scope ref Segment segment) {
			idx = segment.textBeginOffset;
			// FIXME: this all assumes ltr

			auto boundingBox = Rectangle(segment.upperLeft, Size(segment.width, segment.height));
			if(boundingBox.contains(p)) {
				int x = segment.upperLeft.x;
				int codePointIndex = 0;

				int bestHit = int.max;
				int bestHitDistance = int.max;
				if(bestHitDistance < 0) bestHitDistance = -bestHitDistance;
				foreach(i, dchar ch; text[segment.textBeginOffset .. segment.textEndOffset]) {
					const width = segmentsWidths[segmentIndex][codePointIndex];
					idx = segment.textBeginOffset + cast(int) i; // can't just idx++ since it needs utf-8 stride

					auto distanceToLeft = p.x - x;
					if(distanceToLeft < 0) distanceToLeft = -distanceToLeft;

					//auto distanceToRight = p.x - (x + width);
					//if(distanceToRight < 0) distanceToRight = -distanceToRight;

					//bool improved = false;

					if(distanceToLeft < bestHitDistance) {
						bestHit = idx;
						bestHitDistance = distanceToLeft;
						// improved = true;
					}
					/*
					if(distanceToRight < bestHitDistance) {
						bestHit = idx + 1;
						bestHitDistance = distanceToRight;
						improved = true;
					}
					*/

					//if(!improved) {
						// we're moving further away, no point continuing
						// (please note that RTL transitions = different segment)
						//break;
					//}

					x += width;
					codePointIndex++;
				}

				if(bestHit != int.max)
					idx = bestHit;

				return false;
			} else if(p.x < boundingBox.left && p.y >= boundingBox.top && p.y < boundingBox.bottom) {
				// to the left of a line
				// assumes ltr
				idx = segment.textBeginOffset;
				return false;
			/+
			} else if(p.x >= boundingBox.right && p.y >= boundingBox.top && p.y < boundingBox.bottom) {
				// to the right of a line
				idx = segment.textEndOffset;
				return false;
			+/
			} else if(p.y < segment.upperLeft.y) {
				// should go to the end of the previous line
				auto thisLine = segment.displayLineNumber;
				idx = 0;
				while(segmentIndex > 0) {
					segmentIndex--;

					if(segments[segmentIndex].displayLineNumber < thisLine) {
						idx = segments[segmentIndex].textEndOffset - 1;
						break;
					}
				}
				return false;
			} else {
				// for single line if nothing else matched we'd best put it at the end; will be reset for the next iteration
				// if there is one. and if not, this is where we want it - at the end of the text
				idx = cast(int) text.length - 1;
			}

			return true;
		}, Rectangle(p, Size(0, 0)));
		return idx;
	}

	/++

		History:
			Added September 13, 2024
	+/
	const(TextStyle) styleAtPoint(Point p) {
		TextStyle s;
		getInternalSegments(delegate bool(size_t segmentIndex, scope ref Segment segment) {
			if(segment.boundingBox.contains(p)) {
				s = stylePalette[segment.styleInformationIndex];
				return false;
			}

			return true;
		}, Rectangle(p, Size(1, 1)));

		return s;
	}

	private StyleHandle getInsertionStyleAt(int offset) {
		assert(offset >= 0 && offset < text.length);
		/+
			If we are at the first part of a logical line, use the next local style (the one in bounds at the offset).

			Otherwise, use the previous one (the one in bounds).
		+/

		if(offset == 0 || text[offset - 1] == '\n') {
			// no adjust needed, we use the style here
		} else {
			offset--; // use the previous one
		}

		return getStyleAt(offset);
	}

	private StyleHandle getStyleAt(int offset) {
		// FIXME: binary search
		foreach(style; styles) {
			if(offset >= style.offset && offset < (style.offset + style.length))
				return StyleHandle(style.styleInformationIndex);
		}
		assert(0);
	}

	/++
		Returns a bitmask of the selections active at any given offset.

		May not be stable.
	+/
	ulong selectionsAt(int offset) {
		ulong result;
		ulong bit = 1;
		foreach(selection; _selections[0 .. selectionsInUse]) {
			if(selection.containsOffset(offset))
				result |= bit;
			bit <<= 1;
		}
		return result;
	}

	private int wordWrapWidth_;

	/++
		Set to 0 to disable word wrapping.
	+/
	public void wordWrapWidth(int width) {
		if(width != wordWrapWidth_) {
			wordWrapWidth_ = width;
			invalidateLayout(0, text.length, 0);
		}
	}

	private int justificationWidth_;

	/++
		Not implemented.
	+/
	public void justificationWidth(int width) {
		if(width != justificationWidth_) {
			justificationWidth_ = width;
			invalidateLayout(0, text.length, 0);
		}
	}

	/++
		Can override this to define if a char is a word splitter for word wrapping.
	+/
	protected bool isWordwrapPoint(dchar c) {
		if(c == ' ')
			return true;
		return false;
	}

	private bool invalidateLayout_;
	private int invalidStart = int.max;
	private int invalidEnd = 0;
	private int invalidatedChangeInTextLength = 0;
	/++
		This should be called (internally, end users don't need to see it) any time the text or style has changed.
	+/
	protected void invalidateLayout(size_t start, size_t end, int changeInTextLength) {
		invalidateLayout_ = true;

		if(start < invalidStart)
			invalidStart = cast(int) start;
		if(end > invalidEnd)
			invalidEnd = cast(int) end;

		invalidatedChangeInTextLength += changeInTextLength;
	}

	/++
		This should be called (internally, end users don't need to see it) any time you're going to return something to the user that is dependent on the layout.
	+/
	protected void relayoutIfNecessary() {
		if(invalidateLayout_) {
			relayoutImplementation();
			invalidateLayout_ = false;
			invalidStart = int.max;
			invalidEnd = 0;
			invalidatedChangeInTextLength = 0;
		}
	}

	/++
		Params:
			wordWrapLength = the length, in display pixels, of the layout's bounding box as far as word wrap is concerned. If 0, word wrapping is disabled.

			FIXME: wordWrapChars and if you word wrap, should it indent it too? more realistically i pass the string to the helper and it has to findWordBoundary and then it can prolly return the left offset too, based on the previous line offset perhaps.

			substituteGlyph?  actually that can prolly be a fake password font.


			int maximumHeight. if non-zero, the leftover text is returned so you can pass it to another layout instance (e.g. for columns or pagination)
	+/
	protected void relayoutImplementation() {


		// an optimization here is to avoid redoing stuff outside the invalidated zone.
		// basically it would keep going until a segment after the invalidated end area was in the state before and after.

		debug(text_layouter_bench) {
			// writeln("relayouting");
			import core.time;
			auto start = MonoTime.currTime;
			scope(exit) {
				writeln(MonoTime.currTime - start);
			}
		}

		auto originalSegments = segments;
		auto originalWidth = _width;
		auto originalHeight = _height;
		auto originalSegmentsWidths = segmentsWidths;

		_width = 0;
		_height = 0;

		assert(invalidStart != int.max);
		assert(invalidStart >= 0);
		assert(invalidStart < text.length);

		if(invalidEnd > text.length)
			invalidEnd = cast(int) text.length;

		int firstInvalidSegment = 0;

		Point currentCorner = Point(0, 0);
		int displayLineNumber = 0;
		int lineSegmentIndexStart = 0;

		if(invalidStart != 0) {
			// while i could binary search for the invalid thing,
			// i also need to rebuild _width and _height anyway so
			// just gonna loop through and hope for the best.
			bool found = false;

			// I can't just use the segment bounding box per se since that isn't the whole line
			// and the finishLine adjustment for mixed fonts/sizes will throw things off. so we
			// want to start at the very corner of the line
			int lastLineY;
			int thisLineY;
			foreach(idx, segment; segments) {
				// FIXME: i might actually need to go back to the logical line
				if(displayLineNumber != segment.displayLineNumber) {
					lastLineY = thisLineY;
					displayLineNumber = segment.displayLineNumber;
					lineSegmentIndexStart = cast(int) idx;
				}
				auto b = segment.boundingBox.bottom;
				if(b > thisLineY)
					thisLineY = b;

				if(invalidStart >= segment.textBeginOffset  && invalidStart < segment.textEndOffset) {
					// we'll redo the whole line with the invalidated region since it might have other coordinate things

					segment = segments[lineSegmentIndexStart];

					firstInvalidSegment = lineSegmentIndexStart;// cast(int) idx;
					invalidStart = segment.textBeginOffset;
					displayLineNumber = segment.displayLineNumber;
					currentCorner = segment.upperLeft;
					currentCorner.y = lastLineY;

					found = true;
					break;
				}

				// FIXME: since we rewind to the line segment start above this might not be correct anymore.
				auto bb = segment.boundingBox;
				if(bb.right > _width)
					_width = bb.right;
				if(bb.bottom > _height)
					_height = bb.bottom;
			}
			assert(found);
		}

		// writeln(invalidStart, " starts segment ", firstInvalidSegment, " and line ", displayLineNumber, " seg ", lineSegmentIndexStart);

		segments = segments[0 .. firstInvalidSegment];
		segments.assumeSafeAppend();

		segmentsWidths = segmentsWidths[0 .. firstInvalidSegment];
		segmentsWidths.assumeSafeAppend();

		version(try_kerning_hack) {
			size_t previousIndex = 0;
			int lastWidth;
			int lastWidthDistance;
		}

		Segment segment;

		Segment previousOldSavedSegment;
		short[] previousOldSavedWidths;
		TextStyle currentStyle = null;
		int currentStyleIndex = 0;
		MeasurableFont font;
		ubyte[128] glyphWidths;
		void loadNewFont(MeasurableFont what) {
			font = what;

			// caching the ascii widths locally can give a boost to ~ 20% of the speed of this function
			foreach(char c; 32 .. 128) {
				auto w = font.stringWidth((&c)[0 .. 1]);
				glyphWidths[c] = cast(ubyte) w; // FIXME: what if it doesn't fit?
			}
		}

		auto styles = this.styles;

		foreach(style; this.styles) {
			if(invalidStart >= style.offset && invalidStart < (style.offset + style.length)) {
				currentStyle = stylePalette[style.styleInformationIndex];
				if(currentStyle !is null)
					loadNewFont(currentStyle.font);
				currentStyleIndex = style.styleInformationIndex;

				styles = styles[1 .. $];
				break;
			} else if(style.offset > invalidStart) {
				break;
			}
			styles = styles[1 .. $];
		}

		int offsetToNextStyle = int.max;
		if(styles.length) {
			offsetToNextStyle = styles[0].offset;
		}


		assert(offsetToNextStyle >= 0);

		short[] widths;

		size_t segmentBegan = invalidStart;
		void finishSegment(size_t idx) {
			if(idx == segmentBegan)
				return;
			segmentBegan = idx;
			segment.textEndOffset = cast(int) idx;
			segment.displayLineNumber = displayLineNumber;

			if(segments.length < originalSegments.length) {
				previousOldSavedSegment = originalSegments[segments.length];
				previousOldSavedWidths = originalSegmentsWidths[segmentsWidths.length];
			} else {
				previousOldSavedSegment = Segment.init;
				previousOldSavedWidths = null;
			}

			segments ~= segment;
			segmentsWidths ~= widths;

			segment = Segment.init;
			segment.upperLeft = currentCorner;
			segment.styleInformationIndex = currentStyleIndex;
			segment.textBeginOffset = cast(int) idx;
			widths = null;
		}

		// FIXME: when we start in an invalidated thing this is not necessarily right, it should be calculated above
		int biggestDescent = font.descent;
		int lineHeight = font.height;

		bool finishLine(size_t idx, MeasurableFont outerFont) {
			if(segment.textBeginOffset == idx)
				return false; // no need to keep nothing.

			if(currentCorner.x > this._width)
				this._width = currentCorner.x;

			auto thisLineY = currentCorner.y;

			auto thisLineHeight = lineHeight;
			currentCorner.y += lineHeight;
			currentCorner.x = 0;

			finishSegment(idx); // i use currentCorner in there! so this must be after that
			displayLineNumber++;

			lineHeight = outerFont.height;
			biggestDescent = outerFont.descent;

			// go back and adjust all the segments on this line to have the right height and do vertical alignment with the baseline
			foreach(ref seg; segments[lineSegmentIndexStart .. $]) {
				MeasurableFont font;
				if(seg.styleInformationIndex < stylePalette.length) {
					auto si = stylePalette[seg.styleInformationIndex];
					if(si)
						font = si.font;
				}

				auto baseline = thisLineHeight - biggestDescent;

				seg.upperLeft.y += baseline - font.ascent;
				seg.height = thisLineHeight - (baseline - font.ascent);
			}

			// now need to check if we can finish relayout early

			// if we're beyond the invalidated section and have original data to compare against...
			previousOldSavedSegment.textBeginOffset += invalidatedChangeInTextLength;
			previousOldSavedSegment.textEndOffset += invalidatedChangeInTextLength;

			/+
			// FIXME: would be nice to make this work somehow - when you input a new line it needs to just adjust the y stuff
			// part of the problem is that it needs to inject a new segment for the newline and then the whole old array is
			// broken.
			int deltaY;
			int deltaLineNumber;

			if(idx >= invalidEnd && segments[$-1] != previousOldSavedSegment) {
				deltaY = thisLineHeight;
				deltaLineNumber = 1;
				previousOldSavedSegment.upperLeft.y += deltaY;
				previousOldSavedSegment.displayLineNumber += deltaLineNumber;
				writeln("trying deltaY = ", deltaY);
				writeln(previousOldSavedSegment);
				writeln(segments[$-1]);
			}
			+/

			// FIXME: if the only thing that's changed is a y coordinate, adjust that too
			// finishEarly();
			if(idx >= invalidEnd && segments[$-1] == previousOldSavedSegment) {
				if(segmentsWidths[$-1] == previousOldSavedWidths) {
					// we've hit a point where nothing has changed, it is time to stop processing

					foreach(ref seg; originalSegments[segments.length .. $]) {
						seg.textBeginOffset += invalidatedChangeInTextLength;
						seg.textEndOffset += invalidatedChangeInTextLength;

						/+
						seg.upperLeft.y += deltaY;
						seg.displayLineNumber += deltaLineNumber;
						+/

						auto bb = seg.boundingBox;
						if(bb.right > _width)
							_width = bb.right;
						if(bb.bottom > _height)
							_height = bb.bottom;
					}

					// these refer to the same array or should anyway so hopefully this doesn't do anything.
					// FIXME: confirm this isn't sucky
					segments ~= originalSegments[segments.length .. $];
					segmentsWidths ~= originalSegmentsWidths[segmentsWidths.length .. $];

					return true;
				} else {
					// writeln("not matched");
					// writeln(previousOldSavedWidths != segmentsWidths[$-1]);
				}
			}

			lineSegmentIndexStart = cast(int) segments.length;

			return false;
		}

		void finishEarly() {
			// lol i did all the work before triggering this
		}

		segment.upperLeft = currentCorner;
		segment.styleInformationIndex = currentStyleIndex;
		segment.textBeginOffset = invalidStart;

		bool endSegment;
		bool endLine;

		bool tryWordWrapOnNext;

		// writeln("Prior to loop: ", MonoTime.currTime - start, " ", invalidStart);

		// FIXME: i should prolly go by grapheme
		foreach(idxRaw, dchar ch; text[invalidStart .. $]) {
			auto idx = idxRaw + invalidStart;

			version(try_kerning_hack)
				lastWidthDistance++;
			auto oldFont = font;
			if(offsetToNextStyle == idx) {
				auto oldStyle = currentStyle;
				if(styles.length) {
					StyleBlock currentStyleBlock = styles[0];
					offsetToNextStyle += currentStyleBlock.length;
					styles = styles[1 .. $];

					currentStyle = stylePalette[currentStyleBlock.styleInformationIndex];
					currentStyleIndex = currentStyleBlock.styleInformationIndex;
				} else {
					currentStyle = null;
					offsetToNextStyle = int.max;
				}
				if(oldStyle !is currentStyle) {
					if(!endLine)
						endSegment = true;

					loadNewFont(currentStyle.font);
				}
			}

			if(tryWordWrapOnNext) {
				int nextWordwrapPoint = cast(int) idx;
				while(nextWordwrapPoint < text.length && !isWordwrapPoint(text[nextWordwrapPoint])) {
					if(text[nextWordwrapPoint] == '\n')
						break;
					nextWordwrapPoint++;
				}

				if(currentCorner.x + font.stringWidth(text[idx .. nextWordwrapPoint]) >= wordWrapWidth_)
					endLine = true;

				tryWordWrapOnNext = false;
			}

			if(endSegment && !endLine) {
				finishSegment(idx);
				endSegment = false;
			}

			bool justChangedLine;
			if(endLine) {
				auto flr = finishLine(idx, oldFont);
				if(flr)
					return finishEarly();
				endLine = false;
				endSegment = false;
				justChangedLine = true;
			}

			if(font !is oldFont) {
				// FIXME: adjust height
				if(justChangedLine || font.height > lineHeight)
					lineHeight = font.height;
				if(justChangedLine || font.descent > biggestDescent)
					biggestDescent = font.descent;
			}



			int thisWidth = 0;

			switch(ch) {
				case 0:
					goto advance;
				case '\r':
					goto advance;
				case '\n':
					/+
					finishSegment(idx);
					segment.textBeginOffset = cast(int) idx;

					thisWidth = 0;
					+/

					endLine = true;
					goto advance;

					// FIXME: a tab at the end of a line causes the next line to indent
				case '\t':
					finishSegment(idx);

					// a tab should be its own segment with no text
					// per se

					thisWidth = 48;

					segment.width += thisWidth;
					currentCorner.x += thisWidth;

					endSegment = true;
					goto advance;

					//goto advance;
				default:
					// FIXME: i don't think the draw thing uses kerning but if it does this is wrong.

					// figure out this length (it uses previous idx to get some kerning info used)
					version(try_kerning_hack) {
						if(lastWidthDistance == 1) {
							auto width = font.stringWidth(text[previousIndex .. idx + stride(text[idx])]);
							thisWidth = width - lastWidth;
							// writeln(text[previousIndex .. idx + stride(text[idx])], " ", width, "-", lastWidth);
						} else {
							auto width = font.stringWidth(text[idx .. idx + stride(text[idx])]);
							thisWidth = width;
						}
					} else {
						if(text[idx] < 128)
							thisWidth = glyphWidths[text[idx]];
						else
							thisWidth = font.stringWidth(text[idx .. idx + stride(text[idx])]);
					}

					segment.width += thisWidth;
					currentCorner.x += thisWidth;

					version(try_kerning_hack) {
						lastWidth = thisWidth;
						previousIndex = idx;
						lastWidthDistance = 0;
					}
			}

			if(wordWrapWidth_ > 0 && isWordwrapPoint(ch))
				tryWordWrapOnNext = true;

			// if im iterating and hit something that would change the line height, will have to go back and change everything perhaps. or at least work with offsets from the baseline throughout...

			// might also just want a special string sequence that can inject things in the middle of text like inline images. it'd have to tell the height and advance.

			// this would be to test if the kerning adjustments do anything. seems like the fonts
			// don't care tbh but still.
			// thisWidth = font.stringWidth(text[idx .. idx + stride(text[idx])]);

			advance:
			if(segment.textBeginOffset != -1) {
				widths ~= cast(short) thisWidth;
			}
		}

		auto finished = finishLine(text.length, font);
		/+
		if(!finished)
			currentCorner.y += lineHeight;
		import arsd.core; writeln(finished);
		+/

		_height = currentCorner.y;

		// import arsd.core;writeln(_height);

		assert(segments.length);

		//return widths;

		// writefln("%(%s\n%)", segments[0 .. 10]);
	}

	private {
		int stride(char c) {
			if(c < 0x80) {
				return 1;
			} else if(c == 0xff) {
				return 1;
			} else {
				import core.bitop : bsr;
				return 7 - bsr((~uint(c)) & 0xFF);
			}
		}
	}
}

class StyledTextLayouter(StyleClass) : TextLayouter {

}
