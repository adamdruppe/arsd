// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775498%28v=vs.85%29.aspx

// minigui needs to have a stdout redirection for gui mode on windows writeln

// I kinda wanna do state reacting. sort of. idk tho

// need a viewer widget that works like a web page - arrows scroll down consistently

// FIXME: the menus should be a bit more discoverable, at least a single click to open the others instead of two.
// and help info about menu items.
// and search in menus?

// FIXME: a scroll area event signaling when a thing comes into view might be good
// FIXME: arrow key navigation and accelerators in dialog boxes will be a must

// FIXME: unify Windows style line endings

/*
	TODO:

	pie menu

	class Form with submit behavior -- see AutomaticDialog

	disabled widgets and menu items

	TrackBar controls

	event cleanup
	tooltips.
	api improvements

	margins are kinda broken, they don't collapse like they should. at least.

	a table form btw would be a horizontal layout of vertical layouts holding each column
	that would give the same width things
*/

/*

1(15:19:48) NotSpooky: Menus, text entry, label, notebook, box, frame, file dialogs and layout (this one is very useful because I can draw lines between its child widgets
*/

/++
	minigui is a smallish GUI widget library, aiming to be on par with at least
	HTML4 forms and a few other expected gui components. It uses native controls
	on Windows and does its own thing on Linux (Mac is not currently supported but
	may be later, and should use native controls) to keep size down. The Linux
	appearance is similar to Windows 95 and avoids using images to maintain network
	efficiency on remote X connections.
	
	minigui's only required dependencies are [arsd.simpledisplay] and [arsd.color].

	Its #1 goal is to be useful without being large and complicated like GTK and Qt.
	It isn't hugely concerned with appearance - on Windows, it just uses the native
	controls and native theme, and on Linux, it keeps it simple and I may change that
	at any time.

	I love Qt, if you want something full featured, use it! But if you want something
	you can just drop into a small project and expect the basics to work without outside
	dependencies, hopefully minigui will work for you.

	The event model is similar to what you use in the browser with Javascript and the
	layout engine tries to automatically fit things in, similar to a css flexbox.


	FOR BEST RESULTS: be sure to link with the appropriate subsystem command
	`-L/SUBSYSTEM:WINDOWS:5.0`, for example, because otherwise you'll get a
	console and other visual bugs.

	HTML_To_Classes:
		`<input type="text">` = [LineEdit]
		`<textarea>` = [TextEdit]
		`<select>` = [DropDownSelection]
		`<input type="checkbox">` = [Checkbox]
		`<input type="radio">` = [Radiobox]
		`<button>` = [Button]


	Stretchiness:
		The default is 4. You can use larger numbers for things that should
		consume a lot of space, and lower numbers for ones that are better at
		smaller sizes.

	Overlapped_input:
		COMING SOON:
		minigui will include a little bit of I/O functionality that just works
		with the event loop. If you want to get fancy, I suggest spinning up
		another thread and posting events back and forth.

	$(H2 Add ons)

	$(H2 XML definitions)
		If you use [arsd.minigui_xml], you can create widget trees from XML at runtime.

	$(H3 Scriptability)
		minigui is compatible with [arsd.script]. If you see `@scriptable` on a method
		in this documentation, it means you can call it from the script language.

		Tip: to allow easy creation of widget trees from script, import [arsd.minigui_xml]
		and make [arsd.minigui_xml.makeWidgetFromString] available to your script:

		---
		import arsd.minigui_xml;
		import arsd.script;

		var globals = var.emptyObject;
		globals.makeWidgetFromString = &makeWidgetFromString;

		// this now works
		interpret(`var window = makeWidgetFromString("<MainWindow />");`, globals);
		---

		More to come.
+/
module arsd.minigui;

public import arsd.simpledisplay;
private alias Rectangle = arsd.color.Rectangle; // I specifically want this in here, not the win32 GDI Rectangle()

version(Windows) {
	import core.sys.windows.winnls;
	import core.sys.windows.windef;
	import core.sys.windows.basetyps;
	import core.sys.windows.winbase;
	import core.sys.windows.winuser;
	import core.sys.windows.wingdi;
	static import gdi = core.sys.windows.wingdi;
}

// this is a hack to call the original window procedure on native win32 widgets if our event listener thing prevents default.
private bool lastDefaultPrevented;

/// Methods marked with this are available from scripts if added to the [arsd.script] engine.
alias scriptable = arsd_jsvar_compatible;

version(Windows) {
	// use native widgets when available unless specifically asked otherwise
	version(custom_widgets) {
		enum bool UsingCustomWidgets = true;
		enum bool UsingWin32Widgets = false;
	} else {
		version = win32_widgets;
		enum bool UsingCustomWidgets = false;
		enum bool UsingWin32Widgets = true;
	}
	// and native theming when needed
	//version = win32_theming;
} else {
	enum bool UsingCustomWidgets = true;
	enum bool UsingWin32Widgets = false;
	version=custom_widgets;
}



/*

	The main goals of minigui.d are to:
		1) Provide basic widgets that just work in a lightweight lib.
		   I basically want things comparable to a plain HTML form,
		   plus the easy and obvious things you expect from Windows
		   apps like a menu.
		2) Use native things when possible for best functionality with
		   least library weight.
		3) Give building blocks to provide easy extension for your
		   custom widgets, or hooking into additional native widgets
		   I didn't wrap.
		4) Provide interfaces for easy interaction between third
		   party minigui extensions. (event model, perhaps
		   signals/slots, drop-in ease of use bits.)
		5) Zero non-system dependencies, including Phobos as much as
		   I reasonably can. It must only import arsd.color and
		   my simpledisplay.d. If you need more, it will have to be
		   an extension module.
		6) An easy layout system that generally works.

	A stretch goal is to make it easy to make gui forms with code,
	some kind of resource file (xml?) and even a wysiwyg designer.

	Another stretch goal is to make it easy to hook data into the gui,
	including from reflection. So like auto-generate a form from a
	function signature or struct definition, or show a list from an
	array that automatically updates as the array is changed. Then,
	your program focuses on the data more than the gui interaction.



	STILL NEEDED:
		* combo box. (this is diff than select because you can free-form edit too. more like a lineedit with autoselect)
		* slider
		* listbox
		* spinner
		* label?
		* rich text
*/

alias HWND=void*;

///
abstract class ComboboxBase : Widget {
	// if the user can enter arbitrary data, we want to use  2 == CBS_DROPDOWN
	// or to always show the list, we want CBS_SIMPLE == 1
	version(win32_widgets)
		this(uint style, Widget parent = null) {
			super(parent);
			createWin32Window(this, "ComboBox"w, null, style);
		}
	else version(custom_widgets)
		this(Widget parent = null) {
			super(parent);

			addEventListener("keydown", (Event event) {
				if(event.key == Key.Up) {
					if(selection > -1) { // -1 means select blank
						selection--;
						fireChangeEvent();
					}
					event.preventDefault();
				}
				if(event.key == Key.Down) {
					if(selection + 1 < options.length) {
						selection++;
						fireChangeEvent();
					}
					event.preventDefault();
				}

			});

		}
	else static assert(false);

	private string[] options;
	private int selection = -1;

	void addOption(string s) {
		options ~= s;
		version(win32_widgets)
		SendMessageW(hwnd, 323 /*CB_ADDSTRING*/, 0, cast(LPARAM) toWstringzInternal(s));
	}

	void setSelection(int idx) {
		selection = idx;
		version(win32_widgets)
		SendMessageW(hwnd, 334 /*CB_SETCURSEL*/, idx, 0);

		auto t = new Event(EventType.change, this);
		t.intValue = selection;
		t.stringValue = selection == -1 ? null : options[selection];
		t.dispatch();
	}

	version(win32_widgets)
	override void handleWmCommand(ushort cmd, ushort id) {
		selection = cast(int) SendMessageW(hwnd, 327 /* CB_GETCURSEL */, 0, 0);
		fireChangeEvent();
	}

	private void fireChangeEvent() {
		if(selection >= options.length)
			selection = -1;
		auto event = new Event(EventType.change, this);
		event.intValue = selection;
		event.stringValue = selection == -1 ? null : options[selection];
		event.dispatch();
	}

	override int minHeight() { return Window.lineHeight + 4; }
	override int maxHeight() { return Window.lineHeight + 4; }

	version(custom_widgets) {
		SimpleWindow dropDown;
		void popup() {
			auto w = width;
			auto h = cast(int) this.options.length * Window.lineHeight + 8;

			auto coord = this.globalCoordinates();
			auto dropDown = new SimpleWindow(
				w, h,
				null, OpenGlOptions.no, Resizability.fixedSize, WindowTypes.dropdownMenu, WindowFlags.dontAutoShow/*, window*/);

			dropDown.move(coord.x, coord.y + this.height);

			{
				auto painter = dropDown.draw();
				draw3dFrame(0, 0, w, h, painter, FrameStyle.risen);
				auto p = Point(4, 4);
				painter.outlineColor = Color.black;
				foreach(option; options) {
					painter.drawText(p, option);
					p.y += Window.lineHeight;
				}
			}

			dropDown.setEventHandlers(
				(MouseEvent event) {
					if(event.type == MouseEventType.buttonReleased) {
						auto element = (event.y - 4) / Window.lineHeight;
						if(element >= 0 && element <= options.length) {
							selection = element;

							fireChangeEvent();
						}
						dropDown.close();
					}
				}
			);

			dropDown.show();
			dropDown.grabInput();
		}

	}
}

/++
	A drop-down list where the user must select one of the
	given options. Like `<select>` in HTML.
+/
class DropDownSelection : ComboboxBase {
	this(Widget parent = null) {
		version(win32_widgets)
			super(3 /* CBS_DROPDOWNLIST */, parent);
		else version(custom_widgets) {
			super(parent);

			addEventListener("focus", () { this.redraw; });
			addEventListener("blur", () { this.redraw; });
			addEventListener(EventType.change, () { this.redraw; });
			addEventListener("mousedown", () { this.focus(); this.popup(); });
			addEventListener("keydown", (Event event) {
				if(event.key == Key.Space)
					popup();
			});
		} else static assert(false);
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		draw3dFrame(this, painter, FrameStyle.risen);
		painter.outlineColor = Color.black;
		painter.drawText(Point(4, 4), selection == -1 ? "" : options[selection]);

		painter.outlineColor = Color.black;
		painter.fillColor = Color.black;
		Point[4] triangle;
		enum padding = 6;
		enum paddingV = 7;
		enum triangleWidth = 10;
		triangle[0] = Point(width - padding - triangleWidth, paddingV);
		triangle[1] = Point(width - padding - triangleWidth / 2, height - paddingV);
		triangle[2] = Point(width - padding - 0, paddingV);
		triangle[3] = triangle[0];
		painter.drawPolygon(triangle[]);

		if(isFocused()) {
			painter.fillColor = Color.transparent;
			painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
			painter.drawRectangle(Point(2, 2), width - 4, height - 4);
			painter.pen = Pen(Color.black, 1, Pen.Style.Solid);

		}

	}

}

/++
	A text box with a drop down arrow listing selections.
	The user can choose from the list, or type their own.
+/
class FreeEntrySelection : ComboboxBase {
	this(Widget parent = null) {
		version(win32_widgets)
			super(2 /* CBS_DROPDOWN */, parent);
		else version(custom_widgets) {
			super(parent);
			auto hl = new HorizontalLayout(this);
			lineEdit = new LineEdit(hl);

			tabStop = false;

			lineEdit.addEventListener("focus", &lineEdit.selectAll);

			auto btn = new class ArrowButton {
				this() {
					super(ArrowDirection.down, hl);
				}
				override int maxHeight() {
					return int.max;
				}
			};
			//btn.addDirectEventListener("focus", &lineEdit.focus);
			btn.addEventListener("triggered", &this.popup);
			addEventListener(EventType.change, (Event event) {
				lineEdit.content = event.stringValue;
				lineEdit.focus();
				redraw();
			});
		}
		else static assert(false);
	}

	version(custom_widgets) {
		LineEdit lineEdit;
	}
}

/++
	A combination of free entry with a list below it.
+/
class ComboBox : ComboboxBase {
	this(Widget parent = null) {
		version(win32_widgets)
			super(1 /* CBS_SIMPLE */, parent);
		else version(custom_widgets) {
			super(parent);
			lineEdit = new LineEdit(this);
			listWidget = new ListWidget(this);
			listWidget.multiSelect = false;
			listWidget.addEventListener(EventType.change, delegate(Widget, Event) {
				string c = null;
				foreach(option; listWidget.options)
					if(option.selected) {
						c = option.label;
						break;
					}
				lineEdit.content = c;
			});

			listWidget.tabStop = false;
			this.tabStop = false;
			listWidget.addEventListener("focus", &lineEdit.focus);
			this.addEventListener("focus", &lineEdit.focus);

			addDirectEventListener(EventType.change, {
				listWidget.setSelection(selection);
				if(selection != -1)
					lineEdit.content = options[selection];
				lineEdit.focus();
				redraw();
			});

			lineEdit.addEventListener("focus", &lineEdit.selectAll);

			listWidget.addDirectEventListener(EventType.change, {
				int set = -1;
				foreach(idx, opt; listWidget.options)
					if(opt.selected) {
						set = cast(int) idx;
						break;
					}
				if(set != selection)
					this.setSelection(set);
			});
		} else static assert(false);
	}

	override int minHeight() { return Window.lineHeight * 3; }
	override int maxHeight() { return int.max; }
	override int heightStretchiness() { return 5; }

	version(custom_widgets) {
		LineEdit lineEdit;
		ListWidget listWidget;

		override void addOption(string s) {
			listWidget.options ~= ListWidget.Option(s);
			ComboboxBase.addOption(s);
		}
	}
}

/+
class Spinner : Widget {
	version(win32_widgets)
	this(Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		auto hlayout = new HorizontalLayout(this);
		lineEdit = new LineEdit(hlayout);
		upDownControl = new UpDownControl(hlayout);
	}

	LineEdit lineEdit;
	UpDownControl upDownControl;
}

class UpDownControl : Widget {
	version(win32_widgets)
	this(Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "msctls_updown32"w, null, 4/*UDS_ALIGNRIGHT*/| 2 /* UDS_SETBUDDYINT */ | 16 /* UDS_AUTOBUDDY */ | 32 /* UDS_ARROWKEYS */);
	}

	override int minHeight() { return Window.lineHeight; }
	override int maxHeight() { return Window.lineHeight * 3/2; }

	override int minWidth() { return Window.lineHeight * 3/2; }
	override int maxWidth() { return Window.lineHeight * 3/2; }
}
+/

/+
class DataView : Widget {
	// this is the omnibus data viewer
	// the internal data layout is something like:
	// string[string][] but also each node can have parents
}
+/


// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775491(v=vs.85).aspx#PROGRESS_CLASS

// http://svn.dsource.org/projects/bindings/trunk/win32/commctrl.d

// FIXME: menus should prolly capture the mouse. ugh i kno.
/*
	TextEdit needs:

	* caret manipulation
	* selection control
	* convenience functions for appendText, insertText, insertTextAtCaret, etc.

	For example:

	connect(paste, &textEdit.insertTextAtCaret);

	would be nice.



	I kinda want an omnibus dataview that combines list, tree,
	and table - it can be switched dynamically between them.

	Flattening policy: only show top level, show recursive, show grouped
	List styles: plain list (e.g. <ul>), tiles (some details next to it), icons (like Windows explorer)

	Single select, multi select, organization, drag+drop
*/

//static if(UsingSimpledisplayX11)
version(win32_widgets) {}
else version(custom_widgets) {
	enum windowBackgroundColor = Color(212, 212, 212); // used to be 192
	enum activeTabColor = lightAccentColor;
	enum hoveringColor = Color(228, 228, 228);
	enum buttonColor = windowBackgroundColor;
	enum depressedButtonColor = darkAccentColor;
	enum activeListXorColor = Color(255, 255, 127);
	enum progressBarColor = Color(0, 0, 128);
	enum activeMenuItemColor = Color(0, 0, 128);

	enum scrollClickRepeatInterval = 50;
}
else static assert(false);
	// these are used by horizontal rule so not just custom_widgets. for now at least.
	enum darkAccentColor = Color(172, 172, 172);
	enum lightAccentColor = Color(223, 223, 223); // used to be 223

private const(wchar)* toWstringzInternal(in char[] s) {
	wchar[] str;
	str.reserve(s.length + 1);
	foreach(dchar ch; s)
		str ~= ch;
	str ~= '\0';
	return str.ptr;
}

void setClickRepeat(Widget w, int interval, int delay = 250) {
	Timer timer;
	int delayRemaining = delay / interval;
	if(delayRemaining <= 1)
		delayRemaining = 2;

	immutable originalDelayRemaining = delayRemaining;

	w.addDirectEventListener("mousedown", (Event ev) {
		if(ev.srcElement !is w)
			return;
		if(timer !is null) {
			timer.destroy();
			timer = null;
		}
		delayRemaining = originalDelayRemaining;
		timer = new Timer(interval, () {
			if(delayRemaining > 0)
				delayRemaining--;
			else {
				auto ev = new Event("click", w);
				ev.sendDirectly();
			}
		});
	});

	w.addDirectEventListener("mouseup", (Event ev) {
		if(ev.srcElement !is w)
			return;
		if(timer !is null) {
			timer.destroy();
			timer = null;
		}
	});

	w.addDirectEventListener("mouseleave", (Event ev) {
		if(ev.srcElement !is w)
			return;
		if(timer !is null) {
			timer.destroy();
			timer = null;
		}
	});

}

enum FrameStyle {
	risen,
	sunk
}

version(custom_widgets)
void draw3dFrame(Widget widget, ScreenPainter painter, FrameStyle style, Color background = windowBackgroundColor) {
	draw3dFrame(0, 0, widget.width, widget.height, painter, style, background);
}

version(custom_widgets)
void draw3dFrame(int x, int y, int width, int height, ScreenPainter painter, FrameStyle style, Color background = windowBackgroundColor) {
	// outer layer
	painter.outlineColor = style == FrameStyle.sunk ? Color.white : Color.black;
	painter.fillColor = background;
	painter.drawRectangle(Point(x + 0, y + 0), width, height);

	painter.outlineColor = (style == FrameStyle.sunk) ? darkAccentColor : lightAccentColor;
	painter.drawLine(Point(x + 0, y + 0), Point(x + width, y + 0));
	painter.drawLine(Point(x + 0, y + 0), Point(x + 0, y + height - 1));

	// inner layer
	//right, bottom
	painter.outlineColor = (style == FrameStyle.sunk) ? lightAccentColor : darkAccentColor;
	painter.drawLine(Point(x + width - 2, y + 2), Point(x + width - 2, y + height - 2));
	painter.drawLine(Point(x + 2, y + height - 2), Point(x + width - 2, y + height - 2));
	// left, top
	painter.outlineColor = (style == FrameStyle.sunk) ? Color.black : Color.white;
	painter.drawLine(Point(x + 1, y + 1), Point(x + width, y + 1));
	painter.drawLine(Point(x + 1, y + 1), Point(x + 1, y + height - 2));
}

///
class Action {
	version(win32_widgets) {
		private int id;
		private static int lastId = 9000;
		private static Action[int] mapping;
	}

	KeyEvent accelerator;

	///
	this(string label, ushort icon = 0, void delegate() triggered = null) {
		this.label = label;
		this.iconId = icon;
		if(triggered !is null)
			this.triggered ~= triggered;
		version(win32_widgets) {
			id = ++lastId;
			mapping[id] = this;
		}
	}

	private string label;
	private ushort iconId;
	// icon

	// when it is triggered, the triggered event is fired on the window
	void delegate()[] triggered;
}

/*
	plan:
		keyboard accelerators

		* menus (and popups and tooltips)
		* status bar
		* toolbars and buttons

		sortable table view

		maybe notification area icons
		basic clipboard

		* radio box
		splitter
		toggle buttons (optionally mutually exclusive, like in Paint)
		label, rich text display, multi line plain text (selectable)
		* fieldset
		* nestable grid layout
		single line text input
		* multi line text input
		slider
		spinner
		list box
		drop down
		combo box
		auto complete box
		* progress bar

		terminal window/widget (on unix it might even be a pty but really idk)

		ok button
		cancel button

		keyboard hotkeys

		scroll widget

		event redirections and network transparency
		script integration
*/


/*
	MENUS

	auto bar = new MenuBar(window);
	window.menuBar = bar;

	auto fileMenu = bar.addItem(new Menu("&File"));
	fileMenu.addItem(new MenuItem("&Exit"));


	EVENTS

	For controls, you should usually use "triggered" rather than "click", etc., because
	triggered handles both keyboard (focus and press as well as hotkeys) and mouse activation.
	This is the case on menus and pushbuttons.

	"click", on the other hand, currently only fires when it is literally clicked by the mouse.
*/


/*
enum LinePreference {
	AlwaysOnOwnLine, // always on its own line
	PreferOwnLine, // it will always start a new line, and if max width <= line width, it will expand all the way
	PreferToShareLine, // does not force new line, and if the next child likes to share too, they will div it up evenly. otherwise, it will expand as much as it can
}
*/

mixin template Padding(string code) {
	override int paddingLeft() { return mixin(code);}
	override int paddingRight() { return mixin(code);}
	override int paddingTop() { return mixin(code);}
	override int paddingBottom() { return mixin(code);}
}

mixin template Margin(string code) {
	override int marginLeft() { return mixin(code);}
	override int marginRight() { return mixin(code);}
	override int marginTop() { return mixin(code);}
	override int marginBottom() { return mixin(code);}
}


mixin template LayoutInfo() {
	int minWidth() { return 0; }
	int minHeight() {
		// default widgets have a vertical layout, therefore the minimum height is the sum of the contents
		int sum = 0;
		foreach(child; children) {
			sum += child.minHeight();
			sum += child.marginTop();
			sum += child.marginBottom();
		}

		return sum;
	}
	int maxWidth() { return int.max; }
	int maxHeight() { return int.max; }
	int widthStretchiness() { return 4; }
	int heightStretchiness() { return 4; }

	int marginLeft() { return 0; }
	int marginRight() { return 0; }
	int marginTop() { return 0; }
	int marginBottom() { return 0; }
	int paddingLeft() { return 0; }
	int paddingRight() { return 0; }
	int paddingTop() { return 0; }
	int paddingBottom() { return 0; }
	//LinePreference linePreference() { return LinePreference.PreferOwnLine; }

	void recomputeChildLayout() {
		.recomputeChildLayout!"height"(this);
	}
}

private
void recomputeChildLayout(string relevantMeasure)(Widget parent) {
	enum calcingV = relevantMeasure == "height";

	parent.registerMovement();

	if(parent.children.length == 0)
		return;

	enum firstThingy = relevantMeasure == "height" ? "Top" : "Left";
	enum secondThingy = relevantMeasure == "height" ? "Bottom" : "Right";

	enum otherFirstThingy = relevantMeasure == "height" ? "Left" : "Top";
	enum otherSecondThingy = relevantMeasure == "height" ? "Right" : "Bottom";

	// my own width and height should already be set by the caller of this function...
	int spaceRemaining = mixin("parent." ~ relevantMeasure) -
		mixin("parent.padding"~firstThingy~"()") -
		mixin("parent.padding"~secondThingy~"()");

	int stretchinessSum;
	int stretchyChildSum;
	int lastMargin = 0;

	// set initial size
	foreach(child; parent.children) {
		if(cast(StaticPosition) child)
			continue;
		if(child.hidden)
			continue;

		static if(calcingV) {
			child.width = parent.width -
				mixin("child.margin"~otherFirstThingy~"()") -
				mixin("child.margin"~otherSecondThingy~"()") -
				mixin("parent.padding"~otherFirstThingy~"()") -
				mixin("parent.padding"~otherSecondThingy~"()");

			if(child.width < 0)
				child.width = 0;
			if(child.width > child.maxWidth())
				child.width = child.maxWidth();
			child.height = child.minHeight();
		} else {
			child.height = parent.height -
				mixin("child.margin"~firstThingy~"()") -
				mixin("child.margin"~secondThingy~"()") -
				mixin("parent.padding"~firstThingy~"()") -
				mixin("parent.padding"~secondThingy~"()");
			if(child.height < 0)
				child.height = 0;
			if(child.height > child.maxHeight())
				child.height = child.maxHeight();
			child.width = child.minWidth();
		}

		spaceRemaining -= mixin("child." ~ relevantMeasure);

		int thisMargin = mymax(lastMargin, mixin("child.margin"~firstThingy~"()"));
		auto margin = mixin("child.margin" ~ secondThingy ~ "()");
		lastMargin = margin;
		spaceRemaining -= thisMargin + margin;
		auto s = mixin("child." ~ relevantMeasure ~ "Stretchiness()");
		stretchinessSum += s;
		if(s > 0)
			stretchyChildSum++;
	}

	// stretch to fill space
	while(spaceRemaining > 0 && stretchinessSum && stretchyChildSum) {
		//import std.stdio; writeln("str ", stretchinessSum);
		auto spacePerChild = spaceRemaining / stretchinessSum;
		bool spreadEvenly;
		bool giveToBiggest;
		if(spacePerChild <= 0) {
			spacePerChild = spaceRemaining / stretchyChildSum;
			spreadEvenly = true;
		}
		if(spacePerChild <= 0) {
			giveToBiggest = true;
		}
		int previousSpaceRemaining = spaceRemaining;
		stretchinessSum = 0;
		Widget mostStretchy;
		int mostStretchyS;
		foreach(child; parent.children) {
			if(cast(StaticPosition) child)
				continue;
			if(child.hidden)
				continue;
			static if(calcingV)
				auto maximum = child.maxHeight();
			else
				auto maximum = child.maxWidth();

			if(mixin("child." ~ relevantMeasure) >= maximum) {
				auto adj = mixin("child." ~ relevantMeasure) - maximum;
				mixin("child." ~ relevantMeasure) -= adj;
				spaceRemaining += adj;
				continue;
			}
			auto s = mixin("child." ~ relevantMeasure ~ "Stretchiness()");
			if(s <= 0)
				continue;
			auto spaceAdjustment = spacePerChild * (spreadEvenly ? 1 : s);
			mixin("child." ~ relevantMeasure) += spaceAdjustment;
			spaceRemaining -= spaceAdjustment;
			if(mixin("child." ~ relevantMeasure) > maximum) {
				auto diff = mixin("child." ~ relevantMeasure) - maximum;
				mixin("child." ~ relevantMeasure) -= diff;
				spaceRemaining += diff;
			} else if(mixin("child." ~ relevantMeasure) < maximum) {
				stretchinessSum += mixin("child." ~ relevantMeasure ~ "Stretchiness()");
				if(mostStretchy is null || s >= mostStretchyS) {
					mostStretchy = child;
					mostStretchyS = s;
				}
			}
		}

		if(giveToBiggest && mostStretchy !is null) {
			auto child = mostStretchy;
			int spaceAdjustment = spaceRemaining;

			static if(calcingV)
				auto maximum = child.maxHeight();
			else
				auto maximum = child.maxWidth();

			mixin("child." ~ relevantMeasure) += spaceAdjustment;
			spaceRemaining -= spaceAdjustment;
			if(mixin("child." ~ relevantMeasure) > maximum) {
				auto diff = mixin("child." ~ relevantMeasure) - maximum;
				mixin("child." ~ relevantMeasure) -= diff;
				spaceRemaining += diff;
			}
		}

		if(spaceRemaining == previousSpaceRemaining)
			break; // apparently nothing more we can do
	}

	// position
	lastMargin = 0;
	int currentPos = mixin("parent.padding"~firstThingy~"()");
	foreach(child; parent.children) {
		if(cast(StaticPosition) child) {
			child.recomputeChildLayout();
			continue;
		}
		if(child.hidden)
			continue;
		auto margin = mixin("child.margin" ~ secondThingy ~ "()");
		int thisMargin = mymax(lastMargin, mixin("child.margin"~firstThingy~"()"));
		currentPos += thisMargin;
		static if(calcingV) {
			child.x = parent.paddingLeft() + child.marginLeft();
			child.y = currentPos;
		} else {
			child.x = currentPos;
			child.y = parent.paddingTop() + child.marginTop();

		}
		currentPos += mixin("child." ~ relevantMeasure);
		currentPos += margin;
		lastMargin = margin;

		child.recomputeChildLayout();
	}
}

int mymax(int a, int b) { return a > b ? a : b; }

// OK so we need to make getting at the native window stuff possible in simpledisplay.d
// and here, it must be integrable with the layout, the event system, and not be painted over.
version(win32_widgets) {
	extern(Windows)
	private
	int HookedWndProc(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) nothrow {
		//import std.stdio; try { writeln(iMessage); } catch(Exception e) {};
		if(auto te = hWnd in Widget.nativeMapping) {
			try {

				te.hookedWndProc(iMessage, wParam, lParam);

				if(iMessage == WM_SETFOCUS) {
					auto lol = *te;
					while(lol !is null && lol.implicitlyCreated)
						lol = lol.parent;
					lol.focus();
					//(*te).parentWindow.focusedWidget = lol;
				}



				if(iMessage == WM_CTLCOLORBTN || iMessage == WM_CTLCOLORSTATIC) {
					SetBkMode(cast(HDC) wParam, TRANSPARENT);
					return cast(typeof(return)) GetSysColorBrush(COLOR_3DFACE); // this is the window background color...
						//GetStockObject(NULL_BRUSH);
				}


				auto pos = getChildPositionRelativeToParentOrigin(*te);
				lastDefaultPrevented = false;
				// try {import std.stdio; writeln(typeid(*te)); } catch(Exception e) {}
				if(SimpleWindow.triggerEvents(hWnd, iMessage, wParam, lParam, pos[0], pos[1], (*te).parentWindow.win) || !lastDefaultPrevented)
					return cast(int) CallWindowProcW((*te).originalWindowProcedure, hWnd, iMessage, wParam, lParam);
				else {
					// it was something we recognized, should only call the window procedure if the default was not prevented
				}
			} catch(Exception e) {
				assert(0, e.toString());
			}
			return 0;
		}
		assert(0, "shouldn't be receiving messages for this window....");
		//import std.conv;
		//assert(0, to!string(hWnd) ~ " :: " ~ to!string(TextEdit.nativeMapping)); // not supposed to happen
	}

	// className MUST be a string literal
	void createWin32Window(Widget p, const(wchar)[] className, string windowText, DWORD style, DWORD extStyle = 0) {
		assert(p.parentWindow !is null);
		assert(p.parentWindow.win.impl.hwnd !is null);

		HWND phwnd;
		if(p.parent !is null && p.parent.hwnd !is null)
			phwnd = p.parent.hwnd;
		else
			phwnd = p.parentWindow.win.impl.hwnd;

		assert(phwnd !is null);

		WCharzBuffer wt = WCharzBuffer(windowText);

		style |= WS_VISIBLE | WS_CHILD;
		p.hwnd = CreateWindowExW(extStyle, className.ptr, wt.ptr, style,
				CW_USEDEFAULT, CW_USEDEFAULT, 100, 100,
				phwnd, null, cast(HINSTANCE) GetModuleHandle(null), null);

		assert(p.hwnd !is null);


		static HFONT font;
		if(font is null) {
			NONCLIENTMETRICS params;
			params.cbSize = params.sizeof;
			if(SystemParametersInfo(SPI_GETNONCLIENTMETRICS, params.sizeof, &params, 0)) {
				font = CreateFontIndirect(&params.lfMessageFont);
			}
		}

		if(font)
			SendMessage(p.hwnd, WM_SETFONT, cast(uint) font, true);

		Widget.nativeMapping[p.hwnd] = p;

		p.originalWindowProcedure = cast(WNDPROC) SetWindowLong(p.hwnd, GWL_WNDPROC, cast(LONG) &HookedWndProc);

		EnumChildWindows(p.hwnd, &childHandler, cast(LPARAM) cast(void*) p);

		p.registerMovement();
	}
}

version(win32_widgets)
private
extern(Windows) BOOL childHandler(HWND hwnd, LPARAM lparam) {
	if(hwnd is null || hwnd in Widget.nativeMapping)
		return true;
	auto parent = cast(Widget) cast(void*) lparam;
	Widget p = new Widget();
	p.parent = parent;
	p.parentWindow = parent.parentWindow;
	p.hwnd = hwnd;
	p.implicitlyCreated = true;
	Widget.nativeMapping[p.hwnd] = p;
	p.originalWindowProcedure = cast(WNDPROC) SetWindowLong(p.hwnd, GWL_WNDPROC, cast(LONG) &HookedWndProc);
	return true;
}

/**
	The way this module works is it builds on top of a SimpleWindow
	from simpledisplay to provide simple controls and such.

	Non-native controls suck, but nevertheless, I'm going to do it that
	way to avoid dependencies on stuff like gtk on X... and since I'll
	be writing the widgets there, I might as well just use them on Windows
	too if you like, using `-version=custom_widgets`.

	So, by extension, this sucks. But gtkd is just too big for me.


	The goal is to look kinda like Windows 95, perhaps with customizability.
	Nothing too fancy, just the basics that work.
*/
class Widget {
	mixin LayoutInfo!();

	///
	@scriptable
	void removeWidget() {
		auto p = this.parent;
		if(p) {
			int item;
			for(item = 0; item < p.children.length; item++)
				if(p.children[item] is this)
					break;
			for(; item < p.children.length - 1; item++)
				p.children[item] = p.children[item + 1];
			p.children = p.children[0 .. $-1];
		}
	}

	@scriptable
	Widget getChildByName(string name) {
		return getByName(name);
	}
	///
	final WidgetClass getByName(WidgetClass = Widget)(string name) {
		if(this.name == name)
			if(auto c = cast(WidgetClass) this)
				return c;
		foreach(child; children) {
			auto w = child.getByName(name);
			if(auto c = cast(WidgetClass) w)
				return c;
		}
		return null;
	}

	@scriptable
	string name; ///

	private EventHandler[][string] bubblingEventHandlers;
	private EventHandler[][string] capturingEventHandlers;

	/++
		Default event handlers. These are called on the appropriate
		event unless [Event.preventDefault] is called on the event at
		some point through the bubbling process.


		If you are implementing your own widget and want to add custom
		events, you should follow the same pattern here: create a virtual
		function named `defaultEventHandler_eventname` with the implementation,
		then, override [setupDefaultEventHandlers] and add a wrapped caller to
		`defaultEventHandlers["eventname"]`. It should be wrapped like so:
		`defaultEventHandlers["eventname"] = (Widget t, Event event) { t.defaultEventHandler_name(event); };`.
		This ensures virtual dispatch based on the correct subclass.

		Also, don't forget to call `super.setupDefaultEventHandlers();` too in your
		overridden version.

		You only need to do that on parent classes adding NEW event types. If you
		just want to change the default behavior of an existing event type in a subclass,
		you override the function (and optionally call `super.method_name`) like normal.

	+/
	protected EventHandler[string] defaultEventHandlers;

	/// ditto
	void setupDefaultEventHandlers() {
		defaultEventHandlers["click"] = (Widget t, Event event) { t.defaultEventHandler_click(event); };
		defaultEventHandlers["keydown"] = (Widget t, Event event) { t.defaultEventHandler_keydown(event); };
		defaultEventHandlers["keyup"] = (Widget t, Event event) { t.defaultEventHandler_keyup(event); };
		defaultEventHandlers["mouseover"] = (Widget t, Event event) { t.defaultEventHandler_mouseover(event); };
		defaultEventHandlers["mouseout"] = (Widget t, Event event) { t.defaultEventHandler_mouseout(event); };
		defaultEventHandlers["mousedown"] = (Widget t, Event event) { t.defaultEventHandler_mousedown(event); };
		defaultEventHandlers["mouseup"] = (Widget t, Event event) { t.defaultEventHandler_mouseup(event); };
		defaultEventHandlers["mouseenter"] = (Widget t, Event event) { t.defaultEventHandler_mouseenter(event); };
		defaultEventHandlers["mouseleave"] = (Widget t, Event event) { t.defaultEventHandler_mouseleave(event); };
		defaultEventHandlers["mousemove"] = (Widget t, Event event) { t.defaultEventHandler_mousemove(event); };
		defaultEventHandlers["char"] = (Widget t, Event event) { t.defaultEventHandler_char(event); };
		defaultEventHandlers["triggered"] = (Widget t, Event event) { t.defaultEventHandler_triggered(event); };
		defaultEventHandlers["change"] = (Widget t, Event event) { t.defaultEventHandler_change(event); };
		defaultEventHandlers["focus"] = (Widget t, Event event) { t.defaultEventHandler_focus(event); };
		defaultEventHandlers["blur"] = (Widget t, Event event) { t.defaultEventHandler_blur(event); };
	}

	/// ditto
	void defaultEventHandler_click(Event event) {}
	/// ditto
	void defaultEventHandler_keydown(Event event) {}
	/// ditto
	void defaultEventHandler_keyup(Event event) {}
	/// ditto
	void defaultEventHandler_mousedown(Event event) {}
	/// ditto
	void defaultEventHandler_mouseover(Event event) {}
	/// ditto
	void defaultEventHandler_mouseout(Event event) {}
	/// ditto
	void defaultEventHandler_mouseup(Event event) {}
	/// ditto
	void defaultEventHandler_mousemove(Event event) {}
	/// ditto
	void defaultEventHandler_mouseenter(Event event) {}
	/// ditto
	void defaultEventHandler_mouseleave(Event event) {}
	/// ditto
	void defaultEventHandler_char(Event event) {}
	/// ditto
	void defaultEventHandler_triggered(Event event) {}
	/// ditto
	void defaultEventHandler_change(Event event) {}
	/// ditto
	void defaultEventHandler_focus(Event event) {}
	/// ditto
	void defaultEventHandler_blur(Event event) {}

	/++
		Events use a Javascript-esque scheme.

		[addEventListener] returns an opaque handle that you can later pass to [removeEventListener].
	+/
	EventListener addDirectEventListener(string event, void delegate() handler, bool useCapture = false) {
		return addEventListener(event, (Widget, Event e) {
			if(e.srcElement is this)
				handler();
		}, useCapture);
	}

	///
	EventListener addDirectEventListener(string event, void delegate(Event) handler, bool useCapture = false) {
		return addEventListener(event, (Widget, Event e) {
			if(e.srcElement is this)
				handler(e);
		}, useCapture);
	}


	///
	@scriptable
	EventListener addEventListener(string event, void delegate() handler, bool useCapture = false) {
		return addEventListener(event, (Widget, Event) { handler(); }, useCapture);
	}

	///
	EventListener addEventListener(string event, void delegate(Event) handler, bool useCapture = false) {
		return addEventListener(event, (Widget, Event e) { handler(e); }, useCapture);
	}

	///
	EventListener addEventListener(string event, EventHandler handler, bool useCapture = false) {
		if(event.length > 2 && event[0..2] == "on")
			event = event[2 .. $];

		if(useCapture)
			capturingEventHandlers[event] ~= handler;
		else
			bubblingEventHandlers[event] ~= handler;

		return EventListener(this, event, handler, useCapture);
	}

	///
	void removeEventListener(string event, EventHandler handler, bool useCapture = false) {
		if(event.length > 2 && event[0..2] == "on")
			event = event[2 .. $];

		if(useCapture) {
			if(event in capturingEventHandlers)
			foreach(ref evt; capturingEventHandlers[event])
				if(evt is handler) evt = null;
		} else {
			if(event in bubblingEventHandlers)
			foreach(ref evt; bubblingEventHandlers[event])
				if(evt is handler) evt = null;
		}
	}

	///
	void removeEventListener(EventListener listener) {
		removeEventListener(listener.event, listener.handler, listener.useCapture);
	}

	MouseCursor cursor() {
		return GenericCursor.Default;
	}

	static if(UsingSimpledisplayX11) {
		void discardXConnectionState() {
			foreach(child; children)
				child.discardXConnectionState();
		}

		void recreateXConnectionState() {
			foreach(child; children)
				child.recreateXConnectionState();
			redraw();
		}
	}

	///
	Point globalCoordinates() {
		int x = this.x;
		int y = this.y;
		auto p = this.parent;
		while(p) {
			x += p.x;
			y += p.y;
			p = p.parent;
		}

		static if(UsingSimpledisplayX11) {
			auto dpy = XDisplayConnection.get;
			arsd.simpledisplay.Window dummyw;
			XTranslateCoordinates(dpy, this.parentWindow.win.impl.window, RootWindow(dpy, DefaultScreen(dpy)), x, y, &x, &y, &dummyw);
		} else {
			POINT pt;
			pt.x = x;
			pt.y = y;
			MapWindowPoints(this.parentWindow.win.impl.hwnd, null, &pt, 1);
			x = pt.x;
			y = pt.y;
		}

		return Point(x, y);
	}

	version(win32_widgets)
	void handleWmCommand(ushort cmd, ushort id) {}

	version(win32_widgets)
	int handleWmNotify(NMHDR* hdr, int code) { return 0; }

	@scriptable
	string statusTip;
	// string toolTip;
	// string helpText;

	bool tabStop = true;
	int tabOrder;

	version(win32_widgets) {
		static Widget[HWND] nativeMapping;
		HWND hwnd;
		WNDPROC originalWindowProcedure;

		int hookedWndProc(UINT iMessage, WPARAM wParam, LPARAM lParam) {
			return 0;
		}
	}
	bool implicitlyCreated;

	int x; // relative to the parent's origin
	int y; // relative to the parent's origin
	int width;
	int height;
	Widget[] children;
	Widget parent;

	protected
	void registerMovement() {
		version(win32_widgets) {
			if(hwnd) {
				auto pos = getChildPositionRelativeToParentHwnd(this);
				MoveWindow(hwnd, pos[0], pos[1], width, height, true);
			}
		}
	}

	Window parentWindow;

	///
	this(Widget parent = null) {
		if(parent !is null)
			parent.addChild(this);
		setupDefaultEventHandlers();
	}

	///
	@scriptable
	bool isFocused() {
		return parentWindow && parentWindow.focusedWidget is this;
	}

	private bool showing_ = true;
	bool showing() { return showing_; }
	bool hidden() { return !showing_; }
	void showing(bool s, bool recalculate = true) {
		auto so = showing_;
		showing_ = s;
		if(s != so) {

			version(win32_widgets)
			if(hwnd)
				ShowWindow(hwnd, s ? SW_SHOW : SW_HIDE);

			if(parent && recalculate) {
				parent.recomputeChildLayout();
				parent.redraw();
			}

			foreach(child; children)
				child.showing(s, false);
		}
	}
	///
	@scriptable
	void show() {
		showing = true;
	}
	///
	@scriptable
	void hide() {
		showing = false;
	}

	///
	@scriptable
	void focus() {
		assert(parentWindow !is null);
		if(isFocused())
			return;

		if(parentWindow.focusedWidget) {
			// FIXME: more details here? like from and to
			auto evt = new Event("blur", parentWindow.focusedWidget);
			parentWindow.focusedWidget = null;
			evt.sendDirectly();
		}


		version(win32_widgets) {
			if(this.hwnd !is null)
				SetFocus(this.hwnd);
		}

		parentWindow.focusedWidget = this;
		auto evt = new Event("focus", this);
		evt.dispatch();
	}


	void attachedToWindow(Window w) {}
	void addedTo(Widget w) {}

	private void newWindow(Window parent) {
		parentWindow = parent;
		foreach(child; children)
			child.newWindow(parent);
	}

	protected void addChild(Widget w, int position = int.max) {
		w.parent = this;
		if(position == int.max || position == children.length)
			children ~= w;
		else {
			assert(position < children.length);
			children.length = children.length + 1;
			for(int i = cast(int) children.length - 1; i > position; i--)
				children[i] = children[i - 1];
			children[position] = w;
		}

		w.newWindow(this.parentWindow);

		w.addedTo(this);

		if(this.hidden)
			w.showing = false;

		if(parentWindow !is null) {
			w.attachedToWindow(parentWindow);
			parentWindow.recomputeChildLayout();
			parentWindow.redraw();
		}
	}

	Widget getChildAtPosition(int x, int y) {
		// it goes backward so the last one to show gets picked first
		// might use z-index later
		foreach_reverse(child; children) {
			if(child.hidden)
				continue;
			if(child.x <= x && child.y <= y
				&& ((x - child.x) < child.width)
				&& ((y - child.y) < child.height))
			{
				return child;
			}
		}

		return null;
	}

	///
	void paint(ScreenPainter painter) {}

	/// I don't actually like the name of this
	/// this draws a background on it
	void erase(ScreenPainter painter) {
		version(win32_widgets)
			if(hwnd) return; // Windows will do it. I think.

		auto c = backgroundColor;
		painter.fillColor = c;
		painter.outlineColor = c;

		version(win32_widgets) {
			HANDLE b, p;
			if(c.a == 0) {
				b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
				p = SelectObject(painter.impl.hdc, GetStockObject(NULL_PEN));
			}
		}
		painter.drawRectangle(Point(0, 0), width, height);
		version(win32_widgets) {
			if(c.a == 0) {
				SelectObject(painter.impl.hdc, p);
				SelectObject(painter.impl.hdc, b);
			}
		}
	}

	///
	Color backgroundColor() {
		// the default is a "transparent" background, which means
		// it goes as far up as it can to get the color
		if (backgroundColor_ != Color.transparent)
			return backgroundColor_;
		if (parent)
			return parent.backgroundColor();
		return backgroundColor_;
	}

	private Color backgroundColor_ = Color.transparent;
	
	///
	void backgroundColor(Color c){
		this.backgroundColor_ = c;
	}

	///
	ScreenPainter draw() {
		int x = this.x, y = this.y;
		auto parent = this.parent;
		while(parent) {
			x += parent.x;
			y += parent.y;
			parent = parent.parent;
		}

		auto painter = parentWindow.win.draw();
		painter.originX = x;
		painter.originY = y;
		painter.setClipRectangle(Point(0, 0), width, height);
		return painter;
	}

	protected void privatePaint(ScreenPainter painter, int lox, int loy, bool force = false) {
		if(hidden)
			return;

		painter.originX = lox + x;
		painter.originY = loy + y;

		bool actuallyPainted = false;

		if(redrawRequested || force) {
			painter.setClipRectangle(Point(0, 0), width, height);

			erase(painter);
			paint(painter);

			redrawRequested = false;
			actuallyPainted = true;
		}

		foreach(child; children)
			child.privatePaint(painter, painter.originX, painter.originY, actuallyPainted);
	}

	static class RedrawEvent {}
	__gshared re = new RedrawEvent();

	private bool redrawRequested;
	///
	final void redraw(string file = __FILE__, size_t line = __LINE__) {
		redrawRequested = true;

		if(this.parentWindow) {
			auto sw = this.parentWindow.win;
			assert(sw !is null);
			if(!sw.eventQueued!RedrawEvent) {
				sw.postEvent(re);
				//import std.stdio; writeln("redraw requested from ", file,":",line," ", this.parentWindow.win.impl.window);
			}
		}
	}

	void actualRedraw() {
		if(!showing) return;

		assert(parentWindow !is null);

		auto w = drawableWindow;
		if(w is null)
			w = parentWindow.win;

		if(w.closed())
			return;

		auto ugh = this.parent;
		int lox, loy;
		while(ugh) {
			lox += ugh.x;
			loy += ugh.y;
			ugh = ugh.parent;
		}
		auto painter = w.draw();
		privatePaint(painter, lox, loy);
	}

	SimpleWindow drawableWindow;
}

/++
	Nests an opengl capable window inside this window as a widget.

	You may also just want to create an additional [SimpleWindow] with
	[OpenGlOptions.yes] yourself.

	An OpenGL widget cannot have child widgets. It will throw if you try.
+/
static if(OpenGlEnabled)
class OpenGlWidget : Widget {
	SimpleWindow win;

	///
	this(Widget parent) {
		this.parentWindow = parent.parentWindow;
		win = new SimpleWindow(640, 480, null, OpenGlOptions.yes, Resizability.automaticallyScaleIfPossible, WindowTypes.nestedChild, WindowFlags.normal, this.parentWindow.win);
		super(parent);

		version(win32_widgets) {
			Widget.nativeMapping[win.hwnd] = this;
			this.originalWindowProcedure = cast(WNDPROC) SetWindowLong(win.hwnd, GWL_WNDPROC, cast(LONG) &HookedWndProc);
		} else {
			win.setEventHandlers(
				(MouseEvent e) {
					Widget p = this;
					while(p ! is parentWindow) {
						e.x += p.x;
						e.y += p.y;
						p = p.parent;
					}
					parentWindow.dispatchMouseEvent(e);
				},
				(KeyEvent e) {
					//import std.stdio;
					//writefln("%x   %s", cast(uint) e.key, e.key);
					parentWindow.dispatchKeyEvent(e);
				},
				(dchar e) {
					parentWindow.dispatchCharEvent(e);
				},
			);
		}
	}

	override void paint(ScreenPainter painter) {
		win.redrawOpenGlSceneNow();
	}

	void redrawOpenGlScene(void delegate() dg) {
		win.redrawOpenGlScene = dg;
	}

	override void showing(bool s, bool recalc) {
		auto cur = hidden;
		win.hidden = !s;
		if(cur != s && s)
			redraw();
	}

	/// OpenGL widgets cannot have child widgets. Do not call this.
	/* @disable */ final override void addChild(Widget, int) {
		throw new Error("cannot add children to OpenGL widgets");
	}

	/// When an opengl widget is laid out, it will adjust the glViewport for you automatically.
	/// Keep in mind that events like mouse coordinates are still relative to your size.
	override void registerMovement() {
		//import std.stdio; writefln("%d %d %d %d", x,y,width,height);
		version(win32_widgets)
			auto pos = getChildPositionRelativeToParentHwnd(this);
		else
			auto pos = getChildPositionRelativeToParentOrigin(this);
		win.moveResize(pos[0], pos[1], width, height);
	}

	//void delegate() drawFrame;
}

/++

+/
version(custom_widgets)
class ListWidget : ScrollableWidget {

	static struct Option {
		string label;
		bool selected;
	}

	void setSelection(int y) {
		if(!multiSelect)
			foreach(ref opt; options)
				opt.selected = false;
		if(y >= 0 && y < options.length)
			options[y].selected = !options[y].selected;

		auto evt = new Event(EventType.change, this);
		evt.dispatch();

		redraw();

	}

	override void defaultEventHandler_click(Event event) {
		this.focus();
		auto y = (event.clientY - 4) / Window.lineHeight;
		if(y >= 0 && y < options.length) {
			setSelection(y);
		}
		super.defaultEventHandler_click(event);
	}

	this(Widget parent = null) {
		tabStop = false;
		super(parent);
	}

	override void paintFrameAndBackground(ScreenPainter painter) {
		draw3dFrame(this, painter, FrameStyle.sunk, Color.white);
	}

	override void paint(ScreenPainter painter) {
		auto pos = Point(4, 4);
		foreach(idx, option; options) {
			painter.fillColor = Color.white;
			painter.outlineColor = Color.white;
			painter.drawRectangle(pos, width - 8, Window.lineHeight);
			painter.outlineColor = Color.black;
			painter.drawText(pos, option.label);
			if(option.selected) {
				painter.rasterOp = RasterOp.xor;
				painter.outlineColor = Color.white;
				painter.fillColor = activeListXorColor;
				painter.drawRectangle(pos, width - 8, Window.lineHeight);
				painter.rasterOp = RasterOp.normal;
			}
			pos.y += Window.lineHeight;
		}
	}


	void addOption(string text) {
		options ~= Option(text);
		setContentSize(width, cast(int) (options.length * Window.lineHeight));
		redraw();
	}

	void clear() {
		options = null;
		redraw();
	}

	Option[] options;
	bool multiSelect;

	override int heightStretchiness() { return 6; }
}



/// For [ScrollableWidget], determines when to show the scroll bar to the user.
enum ScrollBarShowPolicy {
	automatic, /// automatically show the scroll bar if it is necessary
	never, /// never show the scroll bar (scrolling must be done programmatically)
	always /// always show the scroll bar, even if it is disabled
}

/++
FIXME ScrollBarShowPolicy
+/
class ScrollableWidget : Widget {
	// FIXME: make line size configurable
	// FIXME: add keyboard controls
	version(win32_widgets) {
		override int hookedWndProc(UINT msg, WPARAM wParam, LPARAM lParam) {
			if(msg == WM_VSCROLL || msg == WM_HSCROLL) {
				auto pos = HIWORD(wParam);
				auto m = LOWORD(wParam);

				// FIXME: I can reintroduce the
				// scroll bars now by using this
				// in the top-level window handler
				// to forward comamnds
				auto scrollbarHwnd = lParam;
				switch(m) {
					case SB_BOTTOM:
						if(msg == WM_HSCROLL)
							horizontalScrollTo(contentWidth_);
						else
							verticalScrollTo(contentHeight_);
					break;
					case SB_TOP:
						if(msg == WM_HSCROLL)
							horizontalScrollTo(0);
						else
							verticalScrollTo(0);
					break;
					case SB_ENDSCROLL:
						// idk
					break;
					case SB_LINEDOWN:
						if(msg == WM_HSCROLL)
							horizontalScroll(16);
						else
							verticalScroll(16);
					break;
					case SB_LINEUP:
						if(msg == WM_HSCROLL)
							horizontalScroll(-16);
						else
							verticalScroll(-16);
					break;
					case SB_PAGEDOWN:
						if(msg == WM_HSCROLL)
							horizontalScroll(100);
						else
							verticalScroll(100);
					break;
					case SB_PAGEUP:
						if(msg == WM_HSCROLL)
							horizontalScroll(-100);
						else
							verticalScroll(-100);
					break;
					case SB_THUMBPOSITION:
					case SB_THUMBTRACK:
						if(msg == WM_HSCROLL)
							horizontalScrollTo(pos);
						else
							verticalScrollTo(pos);

						if(m == SB_THUMBTRACK) {
							// the event loop doesn't seem to carry on with a requested redraw..
							// so we request it to get our dirty bit set...
							redraw();
							// then we need to immediately actually redraw it too for instant feedback to user
							actualRedraw();
						}
					break;
					default:
				}
			}
			return 0;
		}
	}
	///
	this(Widget parent) {
		this.parentWindow = parent.parentWindow;

		version(win32_widgets) {
			static bool classRegistered = false;
			if(!classRegistered) {
				HINSTANCE hInstance = cast(HINSTANCE) GetModuleHandle(null);
				WNDCLASSEX wc;
				wc.cbSize = wc.sizeof;
				wc.hInstance = hInstance;
				wc.lpfnWndProc = &DefWindowProc;
				wc.lpszClassName = "arsd_minigui_ScrollableWidget"w.ptr;
				if(!RegisterClassExW(&wc))
					throw new Exception("RegisterClass ");// ~ to!string(GetLastError()));
				classRegistered = true;
			}

			createWin32Window(this, "arsd_minigui_ScrollableWidget"w, "", 
				0|WS_CHILD|WS_VISIBLE|WS_HSCROLL|WS_VSCROLL, 0);
			super(parent);
		} else version(custom_widgets) {
			outerContainer = new ScrollableContainerWidget(this, parent);
			super(outerContainer);
		} else static assert(0);
	}

	version(custom_widgets)
		ScrollableContainerWidget outerContainer;

	override void defaultEventHandler_click(Event event) {
		if(event.button == MouseButton.wheelUp)
			verticalScroll(-16);
		if(event.button == MouseButton.wheelDown)
			verticalScroll(16);
		super.defaultEventHandler_click(event);
	}

	override void defaultEventHandler_keydown(Event event) {
		switch(event.key) {
			case Key.Left:
				horizontalScroll(-16);
			break;
			case Key.Right:
				horizontalScroll(16);
			break;
			case Key.Up:
				verticalScroll(-16);
			break;
			case Key.Down:
				verticalScroll(16);
			break;
			case Key.Home:
				verticalScrollTo(0);
			break;
			case Key.End:
				verticalScrollTo(contentHeight);
			break;
			case Key.PageUp:
				verticalScroll(-160);
			break;
			case Key.PageDown:
				verticalScroll(160);
			break;
			default:
		}
		super.defaultEventHandler_keydown(event);
	}


	version(win32_widgets)
	override void recomputeChildLayout() {
		super.recomputeChildLayout();
		SCROLLINFO info;
		info.cbSize = info.sizeof;
		info.nPage = viewportHeight;
		info.fMask = SIF_PAGE | SIF_RANGE;
		info.nMin = 0;
		info.nMax = contentHeight_;
		SetScrollInfo(hwnd, SB_VERT, &info, true);

		info.cbSize = info.sizeof;
		info.nPage = viewportWidth;
		info.fMask = SIF_PAGE | SIF_RANGE;
		info.nMin = 0;
		info.nMax = contentWidth_;
		SetScrollInfo(hwnd, SB_HORZ, &info, true);
	}



	/*
		Scrolling
		------------

		You are assigned a width and a height by the layout engine, which
		is your viewport box. However, you may draw more than that by setting
		a contentWidth and contentHeight.

		If these can be contained by the viewport, no scrollbar is displayed.
		If they cannot fit though, it will automatically show scroll as necessary.

		If contentWidth == 0, no horizontal scrolling is performed. If contentHeight
		is zero, no vertical scrolling is performed.

		If scrolling is necessary, the lib will automatically work with the bars.
		When you redraw, the origin and clipping info in the painter is set so if
		you just draw everything, it will work, but you can be more efficient by checking
		the viewportWidth, viewportHeight, and scrollOrigin members.
	*/

	///
	final @property int viewportWidth() {
		return width - (showingVerticalScroll ? 16 : 0);
	}
	///
	final @property int viewportHeight() {
		return height - (showingHorizontalScroll ? 16 : 0);
	}

	// FIXME property
	Point scrollOrigin_;

	///
	final const(Point) scrollOrigin() {
		return scrollOrigin_;
	}

	// the user sets these two
	private int contentWidth_ = 0;
	private int contentHeight_ = 0;

	///
	int contentWidth() { return contentWidth_; }
	///
	int contentHeight() { return contentHeight_; }

	///
	void setContentSize(int width, int height) {
		contentWidth_ = width;
		contentHeight_ = height;

		version(custom_widgets) {
			if(showingVerticalScroll || showingHorizontalScroll) {
				outerContainer.recomputeChildLayout();
			}

			if(showingVerticalScroll())
				outerContainer.verticalScrollBar.redraw();
			if(showingHorizontalScroll())
				outerContainer.horizontalScrollBar.redraw();
		} else version(win32_widgets) {
			recomputeChildLayout();
		} else static assert(0);

	}

	///
	void verticalScroll(int delta) {
		verticalScrollTo(scrollOrigin.y + delta);
	}
	///
	void verticalScrollTo(int pos) {
		scrollOrigin_.y = pos;
		if(scrollOrigin_.y + viewportHeight > contentHeight)
			scrollOrigin_.y = contentHeight - viewportHeight;

		if(scrollOrigin_.y < 0)
			scrollOrigin_.y = 0;

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = scrollOrigin_.y;
			SetScrollInfo(hwnd, SB_VERT, &info, true);
		} else version(custom_widgets) {
			outerContainer.verticalScrollBar.setPosition(scrollOrigin_.y);
		} else static assert(0);

		redraw();
	}

	///
	void horizontalScroll(int delta) {
		horizontalScrollTo(scrollOrigin.x + delta);
	}
	///
	void horizontalScrollTo(int pos) {
		scrollOrigin_.x = pos;
		if(scrollOrigin_.x + viewportWidth > contentWidth)
			scrollOrigin_.x = contentWidth - viewportWidth;

		if(scrollOrigin_.x < 0)
			scrollOrigin_.x = 0;

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = scrollOrigin_.x;
			SetScrollInfo(hwnd, SB_HORZ, &info, true);
		} else version(custom_widgets) {
			outerContainer.horizontalScrollBar.setPosition(scrollOrigin_.x);
		} else static assert(0);

		redraw();
	}
	///
	void scrollTo(Point p) {
		verticalScrollTo(p.y);
		horizontalScrollTo(p.x);
	}

	///
	void ensureVisibleInScroll(Point p) {
		auto rect = viewportRectangle();
		if(rect.contains(p))
			return;
		if(p.x < rect.left)
			horizontalScroll(p.x - rect.left);
		else if(p.x > rect.right)
			horizontalScroll(p.x - rect.right);

		if(p.y < rect.top)
			verticalScroll(p.y - rect.top);
		else if(p.y > rect.bottom)
			verticalScroll(p.y - rect.bottom);
	}

	///
	void ensureVisibleInScroll(Rectangle rect) {
		ensureVisibleInScroll(rect.upperLeft);
		ensureVisibleInScroll(rect.lowerRight);
	}

	///
	Rectangle viewportRectangle() {
		return Rectangle(scrollOrigin, Size(viewportWidth, viewportHeight));
	}

	///
	bool showingHorizontalScroll() {
		return contentWidth > width;
	}
	///
	bool showingVerticalScroll() {
		return contentHeight > height;
	}

	/// This is called before the ordinary paint delegate,
	/// giving you a chance to draw the window frame, etc,
	/// before the scroll clip takes effect
	void paintFrameAndBackground(ScreenPainter painter) {
		version(win32_widgets) {
			auto b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
			auto p = SelectObject(painter.impl.hdc, GetStockObject(NULL_PEN));
			// since the pen is null, to fill the whole space, we need the +1 on both.
			gdi.Rectangle(painter.impl.hdc, 0, 0, this.width + 1, this.height + 1);
			SelectObject(painter.impl.hdc, p);
			SelectObject(painter.impl.hdc, b);
		}

	}

	// make space for the scroll bar, and that's it.
	final override int paddingRight() { return 16; }
	final override int paddingBottom() { return 16; }

	/*
		END SCROLLING
	*/

	override ScreenPainter draw() {
		int x = this.x, y = this.y;
		auto parent = this.parent;
		while(parent) {
			x += parent.x;
			y += parent.y;
			parent = parent.parent;
		}

		auto painter = parentWindow.win.draw();
		painter.originX = x;
		painter.originY = y;

		painter.originX = painter.originX - scrollOrigin.x;
		painter.originY = painter.originY - scrollOrigin.y;
		painter.setClipRectangle(scrollOrigin, viewportWidth(), viewportHeight());

		return painter;
	}

	override protected void privatePaint(ScreenPainter painter, int lox, int loy, bool force = false) {
		if(hidden)
			return;
		painter.originX = lox + x;
		painter.originY = loy + y;

		bool actuallyPainted = false;

		if(force || redrawRequested) {
			painter.setClipRectangle(Point(0, 0), width, height);
			paintFrameAndBackground(painter);
		}

		painter.originX = painter.originX - scrollOrigin.x;
		painter.originY = painter.originY - scrollOrigin.y;
		if(force || redrawRequested) {
			painter.setClipRectangle(scrollOrigin + Point(2, 2) /* border */, width - 4, height - 4);

			//erase(painter); // we paintFrameAndBackground above so no need
			paint(painter);

			actuallyPainted = true;
			redrawRequested = false;
		}
		foreach(child; children) {
			if(cast(FixedPosition) child)
				child.privatePaint(painter, painter.originX + scrollOrigin.x, painter.originY + scrollOrigin.y, actuallyPainted);
			else
				child.privatePaint(painter, painter.originX, painter.originY, actuallyPainted);
		}
	}
}

version(custom_widgets)
private class ScrollableContainerWidget : Widget {

	ScrollableWidget sw;

	VerticalScrollbar verticalScrollBar;
	HorizontalScrollbar horizontalScrollBar;

	this(ScrollableWidget sw, Widget parent) {
		this.sw = sw;

		this.tabStop = false;

		horizontalScrollBar = new HorizontalScrollbar(this);
		verticalScrollBar = new VerticalScrollbar(this);

		horizontalScrollBar.showing_ = false;
		verticalScrollBar.showing_ = false;

		horizontalScrollBar.addEventListener(EventType.change, () {
			sw.horizontalScrollTo(horizontalScrollBar.position);
		});
		verticalScrollBar.addEventListener(EventType.change, () {
			sw.verticalScrollTo(verticalScrollBar.position);
		});


		super(parent);
	}

	// this is supposed to be basically invisible...
	override int minWidth() { return sw.minWidth; }
	override int minHeight() { return sw.minHeight; }
	override int maxWidth() { return sw.maxWidth; }
	override int maxHeight() { return sw.maxHeight; }
	override int widthStretchiness() { return sw.widthStretchiness; }
	override int heightStretchiness() { return sw.heightStretchiness; }
	override int marginLeft() { return sw.marginLeft; }
	override int marginRight() { return sw.marginRight; }
	override int marginTop() { return sw.marginTop; }
	override int marginBottom() { return sw.marginBottom; }
	override int paddingLeft() { return sw.paddingLeft; }
	override int paddingRight() { return sw.paddingRight; }
	override int paddingTop() { return sw.paddingTop; }
	override int paddingBottom() { return sw.paddingBottom; }
	override void focus() { sw.focus(); }


	override void recomputeChildLayout() {
		if(sw is null) return;

		bool both = sw.showingVerticalScroll && sw.showingHorizontalScroll;
		if(horizontalScrollBar && verticalScrollBar) {
			horizontalScrollBar.width = this.width - (both ? verticalScrollBar.minWidth() : 0);
			horizontalScrollBar.height = horizontalScrollBar.minHeight();
			horizontalScrollBar.x = 0;
			horizontalScrollBar.y = this.height - horizontalScrollBar.minHeight();

			verticalScrollBar.width = verticalScrollBar.minWidth();
			verticalScrollBar.height = this.height - (both ? horizontalScrollBar.minHeight() : 0) - 2 - 2;
			verticalScrollBar.x = this.width - verticalScrollBar.minWidth();
			verticalScrollBar.y = 0 + 2;

			sw.x = 0;
			sw.y = 0;
			sw.width = this.width - (verticalScrollBar.showing ? verticalScrollBar.width : 0);
			sw.height = this.height - (horizontalScrollBar.showing ? horizontalScrollBar.height : 0);

			if(sw.contentWidth_ <= this.width)
				sw.scrollOrigin_.x = 0;
			if(sw.contentHeight_ <= this.height)
				sw.scrollOrigin_.y = 0;

			horizontalScrollBar.recomputeChildLayout();
			verticalScrollBar.recomputeChildLayout();
			sw.recomputeChildLayout();
		}

		if(sw.contentWidth_ <= this.width)
			sw.scrollOrigin_.x = 0;
		if(sw.contentHeight_ <= this.height)
			sw.scrollOrigin_.y = 0;

		if(sw.showingHorizontalScroll())
			horizontalScrollBar.showing = true;
		else
			horizontalScrollBar.showing = false;
		if(sw.showingVerticalScroll())
			verticalScrollBar.showing = true;
		else
			verticalScrollBar.showing = false;


		verticalScrollBar.setViewableArea(sw.viewportHeight());
		verticalScrollBar.setMax(sw.contentHeight);
		verticalScrollBar.setPosition(sw.scrollOrigin.y);

		horizontalScrollBar.setViewableArea(sw.viewportWidth());
		horizontalScrollBar.setMax(sw.contentWidth);
		horizontalScrollBar.setPosition(sw.scrollOrigin.x);
	}
}

/*
class ScrollableClientWidget : Widget {
	this(Widget parent) {
		super(parent);
	}
	override void paint(ScreenPainter p) {
		parent.paint(p);
	}
}
*/

///
abstract class ScrollbarBase : Widget {
	///
	this(Widget parent) {
		super(parent);
		tabStop = false;
	}

	private int viewableArea_;
	private int max_;
	private int step_ = 16;
	private int position_;

	///
	void setViewableArea(int a) {
		viewableArea_ = a;
	}
	///
	void setMax(int a) {
		max_ = a;
	}
	///
	int max() {
		return max_;
	}
	///
	void setPosition(int a) {
		position_ = max ? a : 0;
	}
	///
	int position() {
		return position_;
	}
	///
	void setStep(int a) {
		step_ = a;
	}
	///
	int step() {
		return step_;
	}

	protected void informProgramThatUserChangedPosition(int n) {
		position_ = n;
		auto evt = new Event(EventType.change, this);
		evt.intValue = n;
		evt.dispatch();
	}

	version(custom_widgets) {
		abstract protected int getBarDim();
		int thumbSize() {
			if(viewableArea_ >= max_)
				return getBarDim();

			int res;
			if(max_) {
				res = getBarDim() * viewableArea_ / max_;
			}
			if(res < 6)
				res = 6;

			return res;
		}

		int thumbPosition() {
			/*
				viewableArea_ is the viewport height/width
				position_ is where we are
			*/
			if(max_) {
				if(position_ + viewableArea_ >= max_)
					return getBarDim - thumbSize;
				return getBarDim * position_ / max_;
			}
			return 0;
		}
	}
}

//public import mgt;

/++
	A mouse tracking widget is one that follows the mouse when dragged inside it.

	Concrete subclasses may include a scrollbar thumb and a volume control.
+/
//version(custom_widgets)
class MouseTrackingWidget : Widget {

	///
	int positionX() { return positionX_; }
	///
	int positionY() { return positionY_; }

	///
	void positionX(int p) { positionX_ = p; }
	///
	void positionY(int p) { positionY_ = p; }

	private int positionX_;
	private int positionY_;

	///
	enum Orientation {
		horizontal, ///
		vertical, ///
		twoDimensional, ///
	}

	private int thumbWidth_;
	private int thumbHeight_;

	///
	int thumbWidth() { return thumbWidth_; }
	///
	int thumbHeight() { return thumbHeight_; }
	///
	int thumbWidth(int a) { return thumbWidth_ = a; }
	///
	int thumbHeight(int a) { return thumbHeight_ = a; }

	private bool dragging;
	private bool hovering;
	private int startMouseX, startMouseY;

	///
	this(Orientation orientation, Widget parent = null) {
		super(parent);

		//assert(parentWindow !is null);

		addEventListener(EventType.mousedown, (Event event) {
			if(event.clientX >= positionX && event.clientX < positionX + thumbWidth && event.clientY >= positionY && event.clientY < positionY + thumbHeight) {
				dragging = true;
				startMouseX = event.clientX - positionX;
				startMouseY = event.clientY - positionY;
				parentWindow.captureMouse(this);
			} else {
				if(orientation == Orientation.horizontal || orientation == Orientation.twoDimensional)
					positionX = event.clientX - thumbWidth / 2;
				if(orientation == Orientation.vertical || orientation == Orientation.twoDimensional)
					positionY = event.clientY - thumbHeight / 2;

				if(positionX + thumbWidth > this.width)
					positionX = this.width - thumbWidth;
				if(positionY + thumbHeight > this.height)
					positionY = this.height - thumbHeight;

				if(positionX < 0)
					positionX = 0;
				if(positionY < 0)
					positionY = 0;


				auto evt = new Event(EventType.change, this);
				evt.sendDirectly();

				redraw();

			}
		});

		addEventListener(EventType.mouseup, (Event event) {
			dragging = false;
			parentWindow.releaseMouseCapture();
		});

		addEventListener(EventType.mouseout, (Event event) {
			if(!hovering)
				return;
			hovering = false;
			redraw();
		});

		addEventListener(EventType.mousemove, (Event event) {
			auto oh = hovering;
			if(event.clientX >= positionX && event.clientX < positionX + thumbWidth && event.clientY >= positionY && event.clientY < positionY + thumbHeight) {
				hovering = true;
			} else {
				hovering = false;
			}
			if(!dragging) {
				if(hovering != oh)
					redraw();
				return;
			}

			if(orientation == Orientation.horizontal || orientation == Orientation.twoDimensional)
				positionX = event.clientX - startMouseX; // FIXME: click could be in the middle of it
			if(orientation == Orientation.vertical || orientation == Orientation.twoDimensional)
				positionY = event.clientY - startMouseY;

			if(positionX + thumbWidth > this.width)
				positionX = this.width - thumbWidth;
			if(positionY + thumbHeight > this.height)
				positionY = this.height - thumbHeight;

			if(positionX < 0)
				positionX = 0;
			if(positionY < 0)
				positionY = 0;

			auto evt = new Event(EventType.change, this);
			evt.sendDirectly();

			redraw();
		});
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		auto c = darken(windowBackgroundColor, 0.2);
		painter.outlineColor = c;
		painter.fillColor = c;
		painter.drawRectangle(Point(0, 0), this.width, this.height);

		auto color = hovering ? hoveringColor : windowBackgroundColor;
		draw3dFrame(positionX, positionY, thumbWidth, thumbHeight, painter, FrameStyle.risen, color);
	}
}

version(custom_widgets)
private
class HorizontalScrollbar : ScrollbarBase {

	version(custom_widgets) {
		private MouseTrackingWidget thumb;

		override int getBarDim() {
			return thumb.width;
		}
	}

	override void setViewableArea(int a) {
		super.setViewableArea(a);

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nPage = a;
			info.fMask = SIF_PAGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			// intentionally blank
		} else static assert(0);

	}

	override void setMax(int a) {
		super.setMax(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nMin = 0;
			info.nMax = max;
			info.fMask = SIF_RANGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		}
	}

	override void setPosition(int a) {
		super.setPosition(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = position;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionX = thumbPosition();
			thumb.thumbWidth = thumbSize;
			thumb.redraw();
		} else static assert(0);
	}

	this(Widget parent) {
		super(parent);

		version(win32_widgets) {
			createWin32Window(this, "Scrollbar"w, "", 
				0|WS_CHILD|WS_VISIBLE|SBS_HORZ|SBS_BOTTOMALIGN, 0);
		} else version(custom_widgets) {
			auto vl = new HorizontalLayout(this);
			auto leftButton = new ArrowButton(ArrowDirection.left, vl);
			leftButton.setClickRepeat(scrollClickRepeatInterval);
			thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.horizontal, vl);
			auto rightButton = new ArrowButton(ArrowDirection.right, vl);
			rightButton.setClickRepeat(scrollClickRepeatInterval);

			leftButton.addEventListener(EventType.triggered, () {
				informProgramThatUserChangedPosition(position - step());
			});
			rightButton.addEventListener(EventType.triggered, () {
				informProgramThatUserChangedPosition(position + step());
			});

			thumb.thumbWidth = this.minWidth;
			thumb.thumbHeight = 16;

			thumb.addEventListener(EventType.change, () {
				auto sx = thumb.positionX * max() / thumb.width;
				informProgramThatUserChangedPosition(sx);
			});
		}
	}

	override int minHeight() { return 16; }
	override int maxHeight() { return 16; }
	override int minWidth() { return 48; }
}

version(custom_widgets)
private
class VerticalScrollbar : ScrollbarBase {

	version(custom_widgets) {
		override int getBarDim() {
			return thumb.height;
		}

		private MouseTrackingWidget thumb;
	}

	override void setViewableArea(int a) {
		super.setViewableArea(a);

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nPage = a;
			info.fMask = SIF_PAGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			// intentionally blank
		} else static assert(0);

	}

	override void setMax(int a) {
		super.setMax(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nMin = 0;
			info.nMax = max;
			info.fMask = SIF_RANGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		}
	}

	override void setPosition(int a) {
		super.setPosition(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = position;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionY = thumbPosition;
			thumb.thumbHeight = thumbSize;
			thumb.redraw();
		} else static assert(0);
	}

	this(Widget parent) {
		super(parent);

		version(win32_widgets) {
			createWin32Window(this, "Scrollbar"w, "", 
				0|WS_CHILD|WS_VISIBLE|SBS_VERT|SBS_RIGHTALIGN, 0);
		} else version(custom_widgets) {
			auto vl = new VerticalLayout(this);
			auto upButton = new ArrowButton(ArrowDirection.up, vl);
			upButton.setClickRepeat(scrollClickRepeatInterval);
			thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.vertical, vl);
			auto downButton = new ArrowButton(ArrowDirection.down, vl);
			downButton.setClickRepeat(scrollClickRepeatInterval);

			upButton.addEventListener(EventType.triggered, () {
				informProgramThatUserChangedPosition(position - step());
			});
			downButton.addEventListener(EventType.triggered, () {
				informProgramThatUserChangedPosition(position + step());
			});

			thumb.thumbWidth = this.minWidth;
			thumb.thumbHeight = 16;

			thumb.addEventListener(EventType.change, () {
				auto sy = thumb.positionY * max() / thumb.height;

				informProgramThatUserChangedPosition(sy);
			});
		}
	}

	override int minWidth() { return 16; }
	override int maxWidth() { return 16; }
	override int minHeight() { return 48; }
}



///
abstract class Layout : Widget {
	this(Widget parent = null) {
		tabStop = false;
		super(parent);
	}
}

/++
	Makes all children minimum width and height, placing them down
	left to right, top to bottom.

	Useful if you want to make a list of buttons that automatically
	wrap to a new line when necessary.
+/
class InlineBlockLayout : Layout {
	///
	this(Widget parent = null) { super(parent); }

	override void recomputeChildLayout() {
		registerMovement();

		int x = this.paddingLeft, y = this.paddingTop;

		int lineHeight;
		int previousMargin = 0;
		int previousMarginBottom = 0;

		foreach(child; children) {
			if(child.hidden)
				continue;
			if(cast(FixedPosition) child) {
				child.recomputeChildLayout();
				continue;
			}
			child.width = child.minWidth();
			if(child.width == 0)
				child.width = 32;
			child.height = child.minHeight();
			if(child.height == 0)
				child.height = 32;

			if(x + child.width + paddingRight > this.width) {
				x = this.paddingLeft;
				y += lineHeight;
				lineHeight = 0;
				previousMargin = 0;
				previousMarginBottom = 0;
			}

			auto margin = child.marginLeft;
			if(previousMargin > margin)
				margin = previousMargin;

			x += margin;

			child.x = x;
			child.y = y;

			int marginTopApplied;
			if(child.marginTop > previousMarginBottom) {
				child.y += child.marginTop;
				marginTopApplied = child.marginTop;
			}

			x += child.width;
			previousMargin = child.marginRight;

			if(child.marginBottom > previousMarginBottom)
				previousMarginBottom = child.marginBottom;

			auto h = child.height + previousMarginBottom + marginTopApplied;
			if(h > lineHeight)
				lineHeight = h;

			child.recomputeChildLayout();
		}

	}

	override int minWidth() {
		int min;
		foreach(child; children) {
			auto cm = child.minWidth;
			if(cm > min)
				min = cm;
		}
		return min + paddingLeft + paddingRight;
	}

	override int minHeight() {
		int min;
		foreach(child; children) {
			auto cm = child.minHeight;
			if(cm > min)
				min = cm;
		}
		return min + paddingTop + paddingBottom;
	}
}

/++
	A tab widget is a set of clickable tab buttons followed by a content area.


	Tabs can change existing content or can be new pages.

	When the user picks a different tab, a `change` message is generated.
+/
class TabWidget : Widget {
	this(Widget parent) {
		super(parent);

		version(win32_widgets) {
			createWin32Window(this, WC_TABCONTROL, "", 0);
		} else version(custom_widgets) {
			tabBarHeight = Window.lineHeight;

			addDirectEventListener(EventType.click, (Event event) {
				if(event.clientY < tabBarHeight) {
					auto t = (event.clientX / tabWidth);
					if(t >= 0 && t < children.length)
						setCurrentTab(t);
				}
			});
		} else static assert(0);
	}

	override int marginTop() { return 4; }
	override int marginBottom() { return 4; }

	override int minHeight() {
		int max = 0;
		foreach(child; children)
			max = mymax(child.minHeight, max);


		version(win32_widgets) {
			RECT rect;
			rect.right = this.width;
			rect.bottom = max;
			TabCtrl_AdjustRect(hwnd, true, &rect);

			max = rect.bottom;
		} else {
			max += Window.lineHeight + 4;
		}


		return max;
	}

	version(win32_widgets)
	override int handleWmNotify(NMHDR* hdr, int code) {
		switch(code) {
			case TCN_SELCHANGE:
				auto sel = TabCtrl_GetCurSel(hwnd);
				showOnly(sel);
			break;
			default:
		}
		return 0;
	}

	override void addChild(Widget child, int pos = int.max) {
		if(auto twp = cast(TabWidgetPage) child) {
			super.addChild(child, pos);
			if(pos == int.max)
				pos = cast(int) this.children.length - 1;

			version(win32_widgets) {
				TCITEM item;
				item.mask = TCIF_TEXT;
				WCharzBuffer buf = WCharzBuffer(twp.title);
				item.pszText = buf.ptr;
				SendMessage(hwnd, TCM_INSERTITEM, pos, cast(LPARAM) &item);
			} else version(custom_widgets) {
			}

			if(pos != getCurrentTab) {
				child.showing = false;
			}
		} else {
			assert(0, "Don't add children directly to a tab widget, instead add them to a page (see addPage)");
		}
	}

	override void recomputeChildLayout() {
		this.registerMovement();
		version(win32_widgets) {

			// Windows doesn't actually parent widgets to the
			// tab control, so we will temporarily pretend this isn't
			// a native widget as we do the changes. A bit of a filthy
			// hack, but a functional one.
			auto hwnd = this.hwnd;
			this.hwnd = null;
			scope(exit) this.hwnd = hwnd;

			RECT rect;
			GetWindowRect(hwnd, &rect);

			auto left = rect.left;
			auto top = rect.top;

			TabCtrl_AdjustRect(hwnd, false, &rect);
			foreach(child; children) {
				child.x = rect.left - left;
				child.y = rect.top - top;
				child.width = rect.right - rect.left;
				child.height = rect.bottom - rect.top;
				child.recomputeChildLayout();
			}
		} else version(custom_widgets) {
			foreach(child; children) {
				child.x = 2;
				child.y = tabBarHeight + 2; // for the border
				child.width = width - 4; // for the border
				child.height = height - tabBarHeight - 2 - 2; // for the border
				child.recomputeChildLayout();
			}
		} else static assert(0);
	}

	version(custom_widgets) {
		private int currentTab_;
		int tabBarHeight;
		int tabWidth = 80;
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {

		draw3dFrame(0, tabBarHeight - 2, width, height - tabBarHeight + 2, painter, FrameStyle.risen);

		int posX = 0;
		foreach(idx, child; children) {
			if(auto twp = cast(TabWidgetPage) child) {
				auto isCurrent = idx == getCurrentTab();
				draw3dFrame(posX, 0, tabWidth, tabBarHeight, painter, isCurrent ? FrameStyle.risen : FrameStyle.sunk, isCurrent ? windowBackgroundColor : darken(windowBackgroundColor, 0.1));
				painter.outlineColor = Color.black;
				painter.drawText(Point(posX + 4, 2), twp.title);

				if(isCurrent) {
					painter.outlineColor = windowBackgroundColor;
					painter.fillColor = Color.transparent;
					painter.drawLine(Point(posX + 2, tabBarHeight - 1), Point(posX + tabWidth, tabBarHeight - 1));
					painter.drawLine(Point(posX + 2, tabBarHeight - 2), Point(posX + tabWidth, tabBarHeight - 2));

					painter.outlineColor = Color.white;
					painter.drawPixel(Point(posX + 1, tabBarHeight - 1));
					painter.drawPixel(Point(posX + 1, tabBarHeight - 2));
					painter.outlineColor = activeTabColor;
					painter.drawPixel(Point(posX, tabBarHeight - 1));
				}

				posX += tabWidth - 2;
			}
		}
	}

	///
	@scriptable
	void setCurrentTab(int item) {
		version(win32_widgets)
			TabCtrl_SetCurSel(hwnd, item);
		else version(custom_widgets)
			currentTab_ = item;
		else static assert(0);

		showOnly(item);
	}

	///
	@scriptable
	int getCurrentTab() {
		version(win32_widgets)
			return TabCtrl_GetCurSel(hwnd);
		else version(custom_widgets)
			return currentTab_; // FIXME
		else static assert(0);
	}

	///
	@scriptable
	void removeTab(int item) {
		if(item && item == getCurrentTab())
			setCurrentTab(item - 1);

		version(win32_widgets) {
			TabCtrl_DeleteItem(hwnd, item);
		}

		for(int a = item; a < children.length - 1; a++)
			this.children[a] = this.children[a + 1];
		this.children = this.children[0 .. $-1];
	}

	///
	@scriptable
	TabWidgetPage addPage(string title) {
		return new TabWidgetPage(title, this);
	}

	private void showOnly(int item) {
		foreach(idx, child; children)
			if(idx == item) {
				child.show();
				recomputeChildLayout();
			} else {
				child.hide();
			}
	}
}

/++
	A page widget is basically a tab widget with hidden tabs.

	You add [TabWidgetPage]s to it.
+/
class PageWidget : Widget {
	this(Widget parent) {
		super(parent);
	}

	override int minHeight() {
		int max = 0;
		foreach(child; children)
			max = mymax(child.minHeight, max);

		return max;
	}


	override void addChild(Widget child, int pos = int.max) {
		if(auto twp = cast(TabWidgetPage) child) {
			super.addChild(child, pos);
			if(pos == int.max)
				pos = cast(int) this.children.length - 1;

			if(pos != getCurrentTab) {
				child.showing = false;
			}
		} else {
			assert(0, "Don't add children directly to a page widget, instead add them to a page (see addPage)");
		}
	}

	override void recomputeChildLayout() {
		this.registerMovement();
		foreach(child; children) {
			child.x = 0;
			child.y = 0;
			child.width = width;
			child.height = height;
			child.recomputeChildLayout();
		}
	}

	private int currentTab_;

	///
	@scriptable
	void setCurrentTab(int item) {
		currentTab_ = item;

		showOnly(item);
	}

	///
	@scriptable
	int getCurrentTab() {
		return currentTab_;
	}

	///
	@scriptable
	void removeTab(int item) {
		if(item && item == getCurrentTab())
			setCurrentTab(item - 1);

		for(int a = item; a < children.length - 1; a++)
			this.children[a] = this.children[a + 1];
		this.children = this.children[0 .. $-1];
	}

	///
	@scriptable
	TabWidgetPage addPage(string title) {
		return new TabWidgetPage(title, this);
	}

	private void showOnly(int item) {
		foreach(idx, child; children)
			if(idx == item) {
				child.show();
				child.recomputeChildLayout();
			} else {
				child.hide();
			}
	}

}

/++

+/
class TabWidgetPage : Widget {
	string title;
	this(string title, Widget parent) {
		this.title = title;
		super(parent);
	}

	override int minHeight() {
		int sum = 0;
		foreach(child; children)
			sum += child.minHeight();
		return sum;
	}
}

version(none)
class CollapsableSidebar : Widget {

}

/// Stacks the widgets vertically, taking all the available width for each child.
class VerticalLayout : Layout {
	// intentionally blank - widget's default is vertical layout right now
	///
	this(Widget parent) { super(parent); }
}

/// Stacks the widgets horizontally, taking all the available height for each child.
class HorizontalLayout : Layout {
	///
	this(Widget parent = null) { super(parent); }
	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}

	override int minHeight() {
		int largest = 0;
		int margins = 0;
		int lastMargin = 0;
		foreach(child; children) {
			auto mh = child.minHeight();
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

	override int maxHeight() {
		int largest = 0;
		int margins = 0;
		int lastMargin = 0;
		foreach(child; children) {
			auto mh = child.maxHeight();
			if(mh == int.max)
				return int.max;
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

	override int heightStretchiness() {
		int max;
		foreach(child; children) {
			auto c = child.heightStretchiness;
			if(c > max)
				max = c;
		}
		return max;
	}

}

/++
	Bypasses automatic layout for its children, using manual positioning and sizing only.
	While you need to manually position them, you must ensure they are inside the StaticLayout's
	bounding box to avoid undefined behavior.

	You should almost never use this.
+/
class StaticLayout : Layout {
	///
	this(Widget parent = null) { super(parent); }
	override void recomputeChildLayout() {
		registerMovement();
		foreach(child; children)
			child.recomputeChildLayout();
	}
}

/++
	Bypasses automatic positioning when being laid out. It is your responsibility to make
	room for this widget in the parent layout.

	Its children are laid out normally, unless there is exactly one, in which case it takes
	on the full size of the `StaticPosition` object (if you plan to put stuff on the edge, you
	can do that with `padding`).
+/
class StaticPosition : Layout {
	///
	this(Widget parent = null) { super(parent); }

	override void recomputeChildLayout() {
		registerMovement();
		if(this.children.length == 1) {
			auto child = children[0];
			child.x = 0;
			child.y = 0;
			child.width = this.width;
			child.height = this.height;
			child.recomputeChildLayout();
		} else
		foreach(child; children)
			child.recomputeChildLayout();
	}

}

/++
	FixedPosition is like [StaticPosition], but its coordinates
	are always relative to the viewport, meaning they do not scroll with
	the parent content.
+/
class FixedPosition : StaticPosition {
	///
	this(Widget parent) { super(parent); }
}


///
class Window : Widget {
	int mouseCaptureCount = 0;
	Widget mouseCapturedBy;
	void captureMouse(Widget byWhom) {
		assert(mouseCapturedBy is null || byWhom is mouseCapturedBy);
		mouseCaptureCount++;
		mouseCapturedBy = byWhom;
		win.grabInput();
	}
	void releaseMouseCapture() {
		mouseCaptureCount--;
		mouseCapturedBy = null;
		win.releaseInputGrab();
	}

	///
	@scriptable
	@property bool focused() {
		return win.focused;
	}

	override Color backgroundColor() {
		version(custom_widgets)
			return windowBackgroundColor;
		else version(win32_widgets)
			return Color.transparent;
		else static assert(0);
	}

	///
	static int lineHeight;

	Widget focusedWidget;

	SimpleWindow win;

	///
	this(Widget p) {
		tabStop = false;
		super(p);
	}

	private bool skipNextChar = false;

	///
	this(SimpleWindow win) {

		static if(UsingSimpledisplayX11) {
			win.discardAdditionalConnectionState = &discardXConnectionState;
			win.recreateAdditionalConnectionState = &recreateXConnectionState;
		}

		tabStop = false;
		super(null);
		this.win = win;

		win.addEventListener((Widget.RedrawEvent) {
			//import std.stdio; writeln("redrawing");
			this.actualRedraw();
		});

		this.width = win.width;
		this.height = win.height;
		this.parentWindow = this;

		win.windowResized = (int w, int h) {
			this.width = w;
			this.height = h;
			recomputeChildLayout();
			redraw();
		};

		win.onFocusChange = (bool getting) {
			if(this.focusedWidget) {
				auto evt = new Event(getting ? "focus" : "blur", this.focusedWidget);
				evt.dispatch();
			}
			auto evt = new Event(getting ? "focus" : "blur", this);
			evt.dispatch();
		};

		win.setEventHandlers(
			(MouseEvent e) {
				dispatchMouseEvent(e);
			},
			(KeyEvent e) {
				//import std.stdio;
				//writefln("%x   %s", cast(uint) e.key, e.key);
				dispatchKeyEvent(e);
			},
			(dchar e) {
				if(e == 13) e = 10; // hack?
				if(e == 127) return; // linux sends this, windows doesn't. we don't want it.
				dispatchCharEvent(e);
			},
		);

		addEventListener("char", (Widget, Event ev) {
			if(skipNextChar) {
				ev.preventDefault();
				skipNextChar = false;
			}
		});

		version(win32_widgets)
		win.handleNativeEvent = delegate int(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {

			if(hwnd !is this.win.impl.hwnd)
				return 1; // we don't care...
			switch(msg) {
				case WM_NOTIFY:
					auto hdr = cast(NMHDR*) lParam;
					auto hwndFrom = hdr.hwndFrom;
					auto code = hdr.code;

					if(auto widgetp = hwndFrom in Widget.nativeMapping) {
						return (*widgetp).handleWmNotify(hdr, code);
					}
				break;
				case WM_COMMAND:
					switch(HIWORD(wParam)) {
						case 0:
						// case BN_CLICKED: aka 0
						case 1:
							auto idm = LOWORD(wParam);
							if(auto item = idm in Action.mapping) {
								foreach(handler; (*item).triggered)
									handler();
							/*
								auto event = new Event("triggered", *item);
								event.button = idm;
								event.dispatch();
							*/
							} else {
								auto handle = cast(HWND) lParam;
								if(auto widgetp = handle in Widget.nativeMapping) {
									(*widgetp).handleWmCommand(HIWORD(wParam), LOWORD(wParam));
								}
							}
						break;
						default:
							return 1;
					}
				break;
				default: return 1; // not handled, pass it on
			}
			return 0;
		};



		if(lineHeight == 0) {
			auto painter = win.draw();
			lineHeight = painter.fontHeight() * 5 / 4;
		}
	}

	version(win32_widgets)
	override void paint(ScreenPainter painter) {
		/*
		RECT rect;
		rect.right = this.width;
		rect.bottom = this.height;
		DrawThemeBackground(theme, painter.impl.hdc, 4, 1, &rect, null);
		*/
		// 3dface is used as window backgrounds by Windows too, so that's why I'm using it here
		auto b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
		auto p = SelectObject(painter.impl.hdc, GetStockObject(NULL_PEN));
		// since the pen is null, to fill the whole space, we need the +1 on both.
		gdi.Rectangle(painter.impl.hdc, 0, 0, this.width + 1, this.height + 1);
		SelectObject(painter.impl.hdc, p);
		SelectObject(painter.impl.hdc, b);
	}
	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		painter.fillColor = windowBackgroundColor;
		painter.outlineColor = windowBackgroundColor;
		painter.drawRectangle(Point(0, 0), this.width, this.height);
	}


	override void defaultEventHandler_keydown(Event event) {
		Widget _this = event.target;

		if(event.key == Key.Tab) {
			/* Window tab ordering is a recursive thingy with each group */

			// FIXME inefficient
			Widget[] helper(Widget p) {
				if(p.hidden)
					return null;
				Widget[] childOrdering;

				auto children = p.children.dup;

				while(true) {
					// UIs should be generally small, so gonna brute force it a little
					// note that it must be a stable sort here; if all are index 0, it should be in order of declaration

					Widget smallestTab;
					foreach(ref c; children) {
						if(c is null) continue;
						if(smallestTab is null || c.tabOrder < smallestTab.tabOrder) {
							smallestTab = c;
							c = null;
						}
					}
					if(smallestTab !is null) {
						if(smallestTab.tabStop && !smallestTab.hidden)
							childOrdering ~= smallestTab;
						if(!smallestTab.hidden)
							childOrdering ~= helper(smallestTab);
					} else
						break;

				}

				return childOrdering;
			}

			Widget[] tabOrdering = helper(this);

			Widget recipient;

			if(tabOrdering.length) {
				bool seenThis = false;
				Widget previous;
				foreach(idx, child; tabOrdering) {
					if(child is focusedWidget) {

						if(event.shiftKey) {
							if(idx == 0)
								recipient = tabOrdering[$-1];
							else
								recipient = tabOrdering[idx - 1];
							break;
						}

						seenThis = true;
						if(idx + 1 == tabOrdering.length) {
							// we're at the end, either move to the next group
							// or start back over
							recipient = tabOrdering[0];
						}
						continue;
					}
					if(seenThis) {
						recipient = child;
						break;
					}
					previous = child;
				}
			}

			if(recipient !is null) {
				// import std.stdio; writeln(typeid(recipient));
				recipient.focus();
				/*
				version(win32_widgets) {
					if(recipient.hwnd !is null)
						SetFocus(recipient.hwnd);
				} else version(custom_widgets) {
					focusedWidget = recipient;
				} else static assert(false);
				*/

				skipNextChar = true;
			}
		}

		debug if(event.key == Key.F12) {
			if(devTools) {
				devTools.close();
				devTools = null;
			} else {
				devTools = new DevToolWindow(this);
				devTools.show();
			}
		}
	}

	debug DevToolWindow devTools;


	///
	this(int width = 500, int height = 500, string title = null) {
		win = new SimpleWindow(width, height, title, OpenGlOptions.no, Resizability.allowResizing, WindowTypes.normal, WindowFlags.dontAutoShow);
		this(win);
	}

	///
	this(string title) {
		this(500, 500, title);
	}

	///
	@scriptable
	void close() {
		win.close();
	}

	bool dispatchKeyEvent(KeyEvent ev) {
		auto wid = focusedWidget;
		if(wid is null)
			wid = this;
		auto event = new Event(ev.pressed ? "keydown" : "keyup", wid);
		event.originalKeyEvent = ev;
		event.character = ev.character;
		event.key = ev.key;
		event.state = ev.modifierState;
		event.shiftKey = (ev.modifierState & ModifierState.shift) ? true : false;
		event.dispatch();

		return true;
	}

	bool dispatchCharEvent(dchar ch) {
		if(focusedWidget) {
			auto event = new Event("char", focusedWidget);
			event.character = ch;
			event.dispatch();
		}
		return true;
	}

	Widget mouseLastOver;
	Widget mouseLastDownOn;
	bool dispatchMouseEvent(MouseEvent ev) {
		auto eleR = widgetAtPoint(this, ev.x, ev.y);
		auto ele = eleR.widget;

		if(mouseCapturedBy !is null) {
			if(ele !is mouseCapturedBy && !mouseCapturedBy.isAParentOf(ele))
				ele = mouseCapturedBy;
		}

		// a hack to get it relative to the widget.
		eleR.x = ev.x;
		eleR.y = ev.y;
		auto pain = ele;
		while(pain) {
			eleR.x -= pain.x;
			eleR.y -= pain.y;
			pain = pain.parent;
		}

		if(ev.type == 1) {
			mouseLastDownOn = ele;
			auto event = new Event("mousedown", ele);
			event.button = ev.button;
			event.buttonLinear = ev.buttonLinear;
			event.state = ev.modifierState;
			event.clientX = eleR.x;
			event.clientY = eleR.y;
			event.dispatch();
		} else if(ev.type == 2) {
			auto event = new Event("mouseup", ele);
			event.button = ev.button;
			event.buttonLinear = ev.buttonLinear;
			event.clientX = eleR.x;
			event.clientY = eleR.y;
			event.state = ev.modifierState;
			event.dispatch();
			if(mouseLastDownOn is ele) {
				event = new Event("click", ele);
				event.clientX = eleR.x;
				event.clientY = eleR.y;
				event.button = ev.button;
				event.buttonLinear = ev.buttonLinear;
				event.dispatch();
			}
		} else if(ev.type == 0) {
			// motion
			Event event = new Event("mousemove", ele);
			event.state = ev.modifierState;
			event.clientX = eleR.x;
			event.clientY = eleR.y;
			event.dispatch();

			if(mouseLastOver !is ele) {
				if(ele !is null) {
					if(!isAParentOf(ele, mouseLastOver)) {
						event = new Event("mouseenter", ele);
						event.relatedTarget = mouseLastOver;
						event.sendDirectly();

						ele.parentWindow.win.cursor = ele.cursor;
					}
				}

				if(mouseLastOver !is null) {
					if(!isAParentOf(mouseLastOver, ele)) {
						event = new Event("mouseleave", mouseLastOver);
						event.relatedTarget = ele;
						event.sendDirectly();
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
		}

		return true;
	}

	/// Shows the window and runs the application event loop.
	@scriptable
	void loop() {
		show();
		win.eventLoop(0);
	}

	private bool firstShow = true;

	@scriptable
	override void show() {
		bool rd = false;
		if(firstShow) {
			firstShow = false;
			recomputeChildLayout();
			focusedWidget = getFirstFocusable(this); // FIXME: autofocus?
			redraw();
		}
		win.show();
		super.show();
	}
	@scriptable
	override void hide() {
		win.hide();
		super.hide();
	}

	static Widget getFirstFocusable(Widget start) {
		if(start.tabStop && !start.hidden)
			return start;

		if(!start.hidden)
		foreach(child; start.children) {
			auto f = getFirstFocusable(child);
			if(f !is null)
				return f;
		}
		return null;
	}
}

debug private class DevToolWindow : Window {
	Window p;

	TextEdit parentList;
	TextEdit logWindow;
	TextLabel clickX, clickY;

	this(Window p) {
		this.p = p;
		super(400, 300, "Developer Toolbox");

		logWindow = new TextEdit(this);
		parentList = new TextEdit(this);

		auto hl = new HorizontalLayout(this);
		clickX = new TextLabel("", hl);
		clickY = new TextLabel("", hl);

		parentListeners ~= p.addEventListener(EventType.click, (Event ev) {
			auto s = ev.srcElement;
			string list = s.toString();
			s = s.parent;
			while(s) {
				list ~= "\n";
				list ~= s.toString();
				s = s.parent;
			}
			parentList.content = list;

			import std.conv;
			clickX.label = to!string(ev.clientX);
			clickY.label = to!string(ev.clientY);
		});
	}

	EventListener[] parentListeners;

	override void close() {
		assert(p !is null);
		foreach(p; parentListeners)
			p.disconnect();
		parentListeners = null;
		p.devTools = null;
		p = null;
		super.close();
	}

	override void defaultEventHandler_keydown(Event ev) {
		if(ev.key == Key.F12) {
			this.close();
			p.devTools = null;
		} else {
			super.defaultEventHandler_keydown(ev);
		}
	}

	void log(T...)(T t) {
		string str;
		import std.conv;
		foreach(i; t)
			str ~= to!string(i);
		str ~= "\n";
		logWindow.addText(str);

		logWindow.ensureVisibleInScroll(logWindow.textLayout.caretBoundingBox());
	}
}

/++
	A dialog is a transient window that intends to get information from
	the user before being dismissed.
+/
abstract class Dialog : Window {
	///
	this(int width, int height, string title = null) {
		super(width, height, title);
	}

	///
	abstract void OK();

	///
	void Cancel() {
		this.close();
	}
}

///
class LabeledLineEdit : Widget {
	///
	this(string label, Widget parent = null) {
		super(parent);
		tabStop = false;
		auto hl = new HorizontalLayout(this);
		this.label = new TextLabel(label, hl);
		this.lineEdit = new LineEdit(hl);
	}
	TextLabel label; ///
	LineEdit lineEdit; ///

	override int minHeight() { return Window.lineHeight + 4; }
	override int maxHeight() { return Window.lineHeight + 4; }

	///
	string content() {
		return lineEdit.content;
	}
	///
	void content(string c) {
		return lineEdit.content(c);
	}

	///
	void selectAll() {
		lineEdit.selectAll();
	}

	override void focus() {
		lineEdit.focus();
	}
}

///
class MainWindow : Window {
	///
	this(string title = null, int initialWidth = 500, int initialHeight = 500) {
		super(initialWidth, initialHeight, title);

		_clientArea = new ClientAreaWidget();
		_clientArea.x = 0;
		_clientArea.y = 0;
		_clientArea.width = this.width;
		_clientArea.height = this.height;
		_clientArea.tabStop = false;

		super.addChild(_clientArea);

		statusBar = new StatusBar(this);
	}

	/++
		Adds a menu and toolbar from annotated functions.

	---
        struct Commands {
                @menu("File") {
                        void New() {}
                        void Open() {}
                        void Save() {}
                        @separator
                        void Exit() @accelerator("Alt+F4") {
                                window.close();
                        }
                }

                @menu("Edit") {
                        void Undo() {
                                undo();
                        }
                        @separator
                        void Cut() {}
                        void Copy() {}
                        void Paste() {}
                }

                @menu("Help") {
                        void About() {}
                }
        }

        Commands commands;

        window.setMenuAndToolbarFromAnnotatedCode(commands);
	---

	+/
	void setMenuAndToolbarFromAnnotatedCode(T)(ref T t) if(!is(T == class) && !is(T == interface)) {
		setMenuAndToolbarFromAnnotatedCode_internal(t);
	}
	void setMenuAndToolbarFromAnnotatedCode(T)(T t) if(is(T == class) || is(T == interface)) {
		setMenuAndToolbarFromAnnotatedCode_internal(t);
	}
	void setMenuAndToolbarFromAnnotatedCode_internal(T)(ref T t) {
		Action[] toolbarActions;
		auto menuBar = new MenuBar();
		Menu[string] mcs;

		void delegate() triggering;

		foreach(memberName; __traits(derivedMembers, T)) {
			static if(__traits(compiles, triggering = &__traits(getMember, t, memberName))) {
				.menu menu;
				.toolbar toolbar;
				bool separator;
				.accelerator accelerator;
				.icon icon;
				string label;
				foreach(attr; __traits(getAttributes, __traits(getMember, T, memberName))) {
					static if(is(typeof(attr) == .menu))
						menu = attr;
					else static if(is(typeof(attr) == .toolbar))
						toolbar = attr;
					else static if(is(attr == .separator))
						separator = true;
					else static if(is(typeof(attr) == .accelerator))
						accelerator = attr;
					else static if(is(typeof(attr) == .icon))
						icon = attr;
					else static if(is(typeof(attr) == .label))
						label = attr.label;
				}

				if(menu !is .menu.init || toolbar !is .toolbar.init) {
					ushort correctIcon = icon.id; // FIXME
					if(label.length == 0)
						label = memberName;
					auto action = new Action(label, correctIcon, &__traits(getMember, t, memberName));

					if(accelerator.keyString.length) {
						auto ke = KeyEvent.parse(accelerator.keyString);
						action.accelerator = ke;
						accelerators[ke.toStr] = &__traits(getMember, t, memberName);
					}

					if(toolbar !is .toolbar.init)
						toolbarActions ~= action;
					if(menu !is .menu.init) {
						Menu mc;
						if(menu.name in mcs) {
							mc = mcs[menu.name];
						} else {
							mc = new Menu(menu.name);
							menuBar.addItem(mc);
							mcs[menu.name] = mc;
						}

						if(separator)
							mc.addSeparator();
						mc.addItem(new MenuItem(action));
					}
				}
			}
		}

		this.menuBar = menuBar;

		if(toolbarActions.length) {
			auto tb = new ToolBar(toolbarActions, this);
		}
	}

	void delegate()[string] accelerators;

	override void defaultEventHandler_keydown(Event event) {
		auto str = event.originalKeyEvent.toStr;
		if(auto acl = str in accelerators)
			(*acl)();
		super.defaultEventHandler_keydown(event);
	}

	override void defaultEventHandler_mouseover(Event event) {
		super.defaultEventHandler_mouseover(event);
		if(this.statusBar !is null && event.target.statusTip.length)
			this.statusBar.parts[0].content = event.target.statusTip;
		else if(this.statusBar !is null && this.statusTip.length)
			this.statusBar.parts[0].content = this.statusTip; // ~ " " ~ event.target.toString();
	}

	override void addChild(Widget c, int position = int.max) {
		if(auto tb = cast(ToolBar) c)
			version(win32_widgets)
				super.addChild(c, 0);
			else version(custom_widgets)
				super.addChild(c, menuBar ? 1 : 0);
			else static assert(0);
		else
			clientArea.addChild(c, position);
	}

	ToolBar _toolBar;
	///
	ToolBar toolBar() { return _toolBar; }
	///
	ToolBar toolBar(ToolBar t) {
		_toolBar = t;
		foreach(child; this.children)
			if(child is t)
				return t;
		version(win32_widgets)
			super.addChild(t, 0);
		else version(custom_widgets)
			super.addChild(t, menuBar ? 1 : 0);
		else static assert(0);
		return t;
	}

	MenuBar _menu;
	///
	MenuBar menuBar() { return _menu; }
	///
	MenuBar menuBar(MenuBar m) {
		if(_menu !is null) {
			// make sure it is sanely removed
			// FIXME
		}

		_menu = m;

		version(win32_widgets) {
			SetMenu(parentWindow.win.impl.hwnd, m.handle);
		} else version(custom_widgets) {
			super.addChild(m, 0);

		//	clientArea.y = menu.height;
		//	clientArea.height = this.height - menu.height;

			recomputeChildLayout();
		} else static assert(false);

		return _menu;
	}
	private Widget _clientArea;
	///
	@property Widget clientArea() { return _clientArea; }
	protected @property void clientArea(Widget wid) {
		_clientArea = wid;
	}

	private StatusBar _statusBar;
	///
	@property StatusBar statusBar() { return _statusBar; }
	///
	@property void statusBar(StatusBar bar) {
		_statusBar = bar;
		super.addChild(_statusBar);
	}

	///
	@property string title() { return parentWindow.win.title; }
	///
	@property void title(string title) { parentWindow.win.title = title; }
}

class ClientAreaWidget : Widget {
	this(Widget parent = null) {
		super(parent);
		//sa = new ScrollableWidget(this);
	}
	/*
	ScrollableWidget sa;
	override void addChild(Widget w, int position) {
		if(sa is null)
			super.addChild(w, position);
		else {
			sa.addChild(w, position);
			sa.setContentSize(this.minWidth + 1, this.minHeight);
			import std.stdio; writeln(sa.contentWidth, "x", sa.contentHeight);
		}
	}
	*/
}

/**
	Toolbars are lists of buttons (typically icons) that appear under the menu.
	Each button ought to correspond to a menu item.
*/
class ToolBar : Widget {
	version(win32_widgets) {
		private const int idealHeight;
		override int minHeight() { return idealHeight; }
		override int maxHeight() { return idealHeight; }
	} else version(custom_widgets) {
		override int minHeight() { return toolbarIconSize; }// Window.lineHeight * 3/2; }
		override int maxHeight() { return toolbarIconSize; } //Window.lineHeight * 3/2; }
	} else static assert(false);
	override int heightStretchiness() { return 0; }

	version(win32_widgets) 
		HIMAGELIST imageList;

	this(Widget parent) {
		this(null, parent);
	}

	///
	this(Action[] actions, Widget parent = null) {
		super(parent);

		tabStop = false;

		version(win32_widgets) {
			// so i like how the flat thing looks on windows, but not on wine
			// and eh, with windows visual styles enabled it looks cool anyway soooo gonna
			// leave it commented
			createWin32Window(this, "ToolbarWindow32"w, "", TBSTYLE_LIST|/*TBSTYLE_FLAT|*/TBSTYLE_TOOLTIPS);
			
			SendMessageW(hwnd, TB_SETEXTENDEDSTYLE, 0, 8/*TBSTYLE_EX_MIXEDBUTTONS*/);

			imageList = ImageList_Create(
				// width, height
				16, 16,
				ILC_COLOR16 | ILC_MASK,
				16 /*numberOfButtons*/, 0);

			SendMessageW(hwnd, TB_SETIMAGELIST, cast(WPARAM) 0, cast(LPARAM) imageList);
			SendMessageW(hwnd, TB_LOADIMAGES, cast(WPARAM) IDB_STD_SMALL_COLOR, cast(LPARAM) HINST_COMMCTRL);
			SendMessageW(hwnd, TB_SETMAXTEXTROWS, 0, 0);
			SendMessageW(hwnd, TB_AUTOSIZE, 0, 0);

			TBBUTTON[] buttons;

			// FIXME: I_IMAGENONE is if here is no icon
			foreach(action; actions)
				buttons ~= TBBUTTON(MAKELONG(cast(ushort)(action.iconId ? (action.iconId - 1) : -2 /* I_IMAGENONE */), 0), action.id, TBSTATE_ENABLED, 0, 0, 0, cast(int) toWstringzInternal(action.label));

			SendMessageW(hwnd, TB_BUTTONSTRUCTSIZE, cast(WPARAM)TBBUTTON.sizeof, 0);
			SendMessageW(hwnd, TB_ADDBUTTONSW, cast(WPARAM) buttons.length, cast(LPARAM)buttons.ptr);

			SIZE size;
			import core.sys.windows.commctrl;
			SendMessageW(hwnd, TB_GETMAXSIZE, 0, cast(LPARAM) &size);
			idealHeight = size.cy + 4; // the plus 4 is a hack

			/*
			RECT rect;
			GetWindowRect(hwnd, &rect);
			idealHeight = rect.bottom - rect.top + 10; // the +10 is a hack since the size right now doesn't look right on a real Windows XP box
			*/

			assert(idealHeight);
		} else version(custom_widgets) {
			foreach(action; actions)
				addChild(new ToolButton(action));
		} else static assert(false);
	}

	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}
}

enum toolbarIconSize = 24;

///
class ToolButton : Button {
	///
	this(string label, Widget parent = null) {
		super(label, parent);
		tabStop = false;
	}
	///
	this(Action action, Widget parent = null) {
		super(action.label, parent);
		tabStop = false;
		this.action = action;
	}

	version(custom_widgets)
	override void defaultEventHandler_click(Event event) {
		foreach(handler; action.triggered)
			handler();
	}

	Action action;

	override int maxWidth() { return toolbarIconSize; }
	override int minWidth() { return toolbarIconSize; }
	override int maxHeight() { return toolbarIconSize; }
	override int minHeight() { return toolbarIconSize; }

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		this.draw3dFrame(painter, isDepressed ? FrameStyle.sunk : FrameStyle.risen, currentButtonColor);

		painter.outlineColor = Color.black;

		// I want to get from 16 to 24. that's * 3 / 2
		static assert(toolbarIconSize >= 16);
		enum multiplier = toolbarIconSize / 8;
		enum divisor = 2 + ((toolbarIconSize % 8) ? 1 : 0);
		switch(action.iconId) {
			case GenericIcons.New:
				painter.fillColor = Color.white;
				painter.drawPolygon(
					Point(3, 2) * multiplier / divisor, Point(3, 13) * multiplier / divisor, Point(12, 13) * multiplier / divisor, Point(12, 6) * multiplier / divisor,
					Point(8, 2) * multiplier / divisor, Point(8, 6) * multiplier / divisor, Point(12, 6) * multiplier / divisor, Point(8, 2) * multiplier / divisor,
					Point(3, 2) * multiplier / divisor, Point(3, 13) * multiplier / divisor
				);
			break;
			case GenericIcons.Save:
				painter.fillColor = Color.white;
				painter.outlineColor = Color.black;
				painter.drawRectangle(Point(2, 2) * multiplier / divisor, Point(13, 13) * multiplier / divisor);

				// the label
				painter.drawRectangle(Point(4, 8) * multiplier / divisor, Point(11, 13) * multiplier / divisor);

				// the slider
				painter.fillColor = Color.black;
				painter.outlineColor = Color.black;
				painter.drawRectangle(Point(4, 3) * multiplier / divisor, Point(10, 6) * multiplier / divisor);

				painter.fillColor = Color.white;
				painter.outlineColor = Color.white;
				// the disc window
				painter.drawRectangle(Point(5, 3) * multiplier / divisor, Point(6, 5) * multiplier / divisor);
			break;
			case GenericIcons.Open:
				painter.fillColor = Color.white;
				painter.drawPolygon(
					Point(4, 4) * multiplier / divisor, Point(4, 12) * multiplier / divisor, Point(13, 12) * multiplier / divisor, Point(13, 3) * multiplier / divisor,
					Point(9, 3) * multiplier / divisor, Point(9, 4) * multiplier / divisor, Point(4, 4) * multiplier / divisor);
				painter.drawPolygon(
					Point(2, 6) * multiplier / divisor, Point(11, 6) * multiplier / divisor,
					Point(12, 12) * multiplier / divisor, Point(4, 12) * multiplier / divisor,
					Point(2, 6) * multiplier / divisor);
				//painter.drawLine(Point(9, 6) * multiplier / divisor, Point(13, 7) * multiplier / divisor);
			break;
			case GenericIcons.Copy:
				painter.fillColor = Color.white;
				painter.drawRectangle(Point(3, 2) * multiplier / divisor, Point(9, 10) * multiplier / divisor);
				painter.drawRectangle(Point(6, 5) * multiplier / divisor, Point(12, 13) * multiplier / divisor);
			break;
			case GenericIcons.Cut:
				painter.fillColor = Color.transparent;
				painter.drawLine(Point(3, 2) * multiplier / divisor, Point(10, 9) * multiplier / divisor);
				painter.drawLine(Point(4, 9) * multiplier / divisor, Point(11, 2) * multiplier / divisor);
				painter.drawRectangle(Point(3, 9) * multiplier / divisor, Point(5, 13) * multiplier / divisor);
				painter.drawRectangle(Point(9, 9) * multiplier / divisor, Point(11, 12) * multiplier / divisor);
			break;
			case GenericIcons.Paste:
				painter.fillColor = Color.white;
				painter.drawRectangle(Point(2, 3) * multiplier / divisor, Point(11, 11) * multiplier / divisor);
				painter.drawRectangle(Point(6, 8) * multiplier / divisor, Point(13, 13) * multiplier / divisor);
				painter.drawLine(Point(6, 2) * multiplier / divisor, Point(4, 5) * multiplier / divisor);
				painter.drawLine(Point(6, 2) * multiplier / divisor, Point(9, 5) * multiplier / divisor);
				painter.fillColor = Color.black;
				painter.drawRectangle(Point(4, 5) * multiplier / divisor, Point(9, 6) * multiplier / divisor);
			break;
			case GenericIcons.Help:
				painter.drawText(Point(0, 0), "?", Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);
			break;
			case GenericIcons.Undo:
				painter.fillColor = Color.transparent;
				painter.drawArc(Point(3, 4) * multiplier / divisor, 9 * multiplier / divisor, 9 * multiplier / divisor, 0, 360 * 64);
				painter.outlineColor = Color.black;
				painter.fillColor = Color.black;
				painter.drawPolygon(
					Point(4, 4) * multiplier / divisor,
					Point(8, 2) * multiplier / divisor,
					Point(8, 6) * multiplier / divisor,
					Point(4, 4) * multiplier / divisor,
				);
			break;
			case GenericIcons.Redo:
				painter.fillColor = Color.transparent;
				painter.drawArc(Point(3, 4) * multiplier / divisor, 9 * multiplier / divisor, 9 * multiplier / divisor, 0, 360 * 64);
				painter.outlineColor = Color.black;
				painter.fillColor = Color.black;
				painter.drawPolygon(
					Point(10, 4) * multiplier / divisor,
					Point(6, 2) * multiplier / divisor,
					Point(6, 6) * multiplier / divisor,
					Point(10, 4) * multiplier / divisor,
				);
			break;
			default:
				painter.drawText(Point(0, 0), action.label, Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);
		}
	}

}


///
class MenuBar : Widget {
	MenuItem[] items;

	version(win32_widgets) {
		HMENU handle;
		///
		this(Widget parent = null) {
			super(parent);

			handle = CreateMenu();
			tabStop = false;
		}
	} else version(custom_widgets) {
		///
		this(Widget parent = null) {
			tabStop = false; // these are selected some other way
			super(parent);
		}

		mixin Padding!q{2};
	} else static assert(false);

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		draw3dFrame(this, painter, FrameStyle.risen);
	}

	///
	MenuItem addItem(MenuItem item) {
		this.addChild(item);
		items ~= item;
		version(win32_widgets) {
			AppendMenuW(handle, MF_STRING, item.action is null ? 9000 : item.action.id, toWstringzInternal(item.label));
		}
		return item;
	}


	///
	Menu addItem(Menu item) {
		auto mbItem = new MenuItem(item.label, this.parentWindow);

		addChild(mbItem);
		items ~= mbItem;

		version(win32_widgets) {
			AppendMenuW(handle, MF_STRING | MF_POPUP, cast(UINT) item.handle, toWstringzInternal(item.label));
		} else version(custom_widgets) {
			mbItem.defaultEventHandlers["mousedown"] = (Widget e, Event ev) {
				item.popup(mbItem);
			};
		} else static assert(false);

		return item;
	}

	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}

	override int maxHeight() { return Window.lineHeight + 4; }
	override int minHeight() { return Window.lineHeight + 4; }
}


/**
	Status bars appear at the bottom of a MainWindow.
	They are made out of Parts, with a width and content.

	They can have multiple parts or be in simple mode. FIXME: implement


	sb.parts[0].content = "Status bar text!";
*/
class StatusBar : Widget {
	private Part[] partsArray;
	///
	struct Parts {
		@disable this();
		this(StatusBar owner) { this.owner = owner; }
		//@disable this(this);
		///
		@property int length() { return cast(int) owner.partsArray.length; }
		private StatusBar owner;
		private this(StatusBar owner, Part[] parts) {
			this.owner.partsArray = parts;
			this.owner = owner;
		}
		///
		Part opIndex(int p) {
			if(owner.partsArray.length == 0)
				this ~= new StatusBar.Part(300);
			return owner.partsArray[p];
		}

		///
		Part opOpAssign(string op : "~" )(Part p) {
			assert(owner.partsArray.length < 255);
			p.owner = this.owner;
			p.idx = cast(int) owner.partsArray.length;
			owner.partsArray ~= p;
			version(win32_widgets) {
				int[256] pos;
				int cpos = 0;
				foreach(idx, part; owner.partsArray) {
					if(part.width)
						cpos += part.width;
					else
						cpos += 100;

					if(idx + 1 == owner.partsArray.length)
						pos[idx] = -1;
					else
						pos[idx] = cpos;
				}
				SendMessageW(owner.hwnd, WM_USER + 4 /*SB_SETPARTS*/, owner.partsArray.length, cast(int) pos.ptr);
			} else version(custom_widgets) {
				owner.redraw();
			} else static assert(false);

			return p;
		}
	}

	private Parts _parts;
	///
	@property Parts parts() {
		return _parts;
	}

	///
	static class Part {
		int width;
		StatusBar owner;

		///
		this(int w = 100) { width = w; }

		private int idx;
		private string _content;
		///
		@property string content() { return _content; }
		///
		@property void content(string s) {
			version(win32_widgets) {
				_content = s;
				WCharzBuffer bfr = WCharzBuffer(s);
				SendMessageW(owner.hwnd, SB_SETTEXT, idx, cast(LPARAM) bfr.ptr);
			} else version(custom_widgets) {
				if(_content != s) {
					_content = s;
					owner.redraw();
				}
			} else static assert(false);
		}
	}
	string simpleModeContent;
	bool inSimpleMode;


	///
	this(Widget parent = null) {
		super(null); // FIXME
		_parts = Parts(this);
		tabStop = false;
		version(win32_widgets) {
			parentWindow = parent.parentWindow;
			createWin32Window(this, "msctls_statusbar32"w, "", 0);

			RECT rect;
			GetWindowRect(hwnd, &rect);
			idealHeight = rect.bottom - rect.top;
			assert(idealHeight);
		} else version(custom_widgets) {
		} else static assert(false);
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		this.draw3dFrame(painter, FrameStyle.sunk);
		int cpos = 0;
		int remainingLength = this.width;
		foreach(idx, part; this.partsArray) {
			auto partWidth = part.width ? part.width : ((idx + 1 == this.partsArray.length) ? remainingLength : 100);
			painter.setClipRectangle(Point(cpos, 0), partWidth, height);
			draw3dFrame(cpos, 0, partWidth, height, painter, FrameStyle.sunk);
			painter.setClipRectangle(Point(cpos + 2, 2), partWidth - 4, height - 4);
			painter.drawText(Point(cpos + 4, 0), part.content, Point(width, height), TextAlignment.VerticalCenter);
			cpos += partWidth;
			remainingLength -= partWidth;
		}
	}


	version(win32_widgets) {
		private const int idealHeight;
		override int maxHeight() { return idealHeight; }
		override int minHeight() { return idealHeight; }
	} else version(custom_widgets) {
		override int maxHeight() { return Window.lineHeight + 4; }
		override int minHeight() { return Window.lineHeight + 4; }
	} else static assert(false);
}

/// Displays an in-progress indicator without known values
version(none)
class IndefiniteProgressBar : Widget {
	version(win32_widgets)
	this(Widget parent = null) {
		super(parent);
		createWin32Window(this, "msctls_progress32"w, "", 8 /* PBS_MARQUEE */);
		tabStop = false;
	}
	override int minHeight() { return 10; }
}

/// A progress bar with a known endpoint and completion amount
class ProgressBar : Widget {
	this(Widget parent = null) {
		version(win32_widgets) {
			super(parent);
			createWin32Window(this, "msctls_progress32"w, "", 0);
			tabStop = false;
		} else version(custom_widgets) {
			super(parent);
			max = 100;
			step = 10;
			tabStop = false;
		} else static assert(0);
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		this.draw3dFrame(painter, FrameStyle.sunk);
		painter.fillColor = progressBarColor;
		painter.drawRectangle(Point(0, 0), width * current / max, height);
	}


	version(custom_widgets) {
		int current;
		int max;
		int step;
	}

	///
	void advanceOneStep() {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_STEPIT, 0, 0);
		else version(custom_widgets)
			addToPosition(step);
		else static assert(false);
	}

	///
	void setStepIncrement(int increment) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_SETSTEP, increment, 0);
		else version(custom_widgets)
			step = increment;
		else static assert(false);
	}

	///
	void addToPosition(int amount) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_DELTAPOS, amount, 0);
		else version(custom_widgets)
			setPosition(current + amount);
		else static assert(false);
	}

	///
	void setPosition(int pos) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_SETPOS, pos, 0);
		else version(custom_widgets) {
			current = pos;
			if(current > max)
				current = max;
			redraw();
		}
		else static assert(false);
	}

	///
	void setRange(ushort min, ushort max) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_SETRANGE, 0, MAKELONG(min, max));
		else version(custom_widgets) {
			this.max = max;
		}
		else static assert(false);
	}

	override int minHeight() { return 10; }
}

///
class Fieldset : Widget {
	// FIXME: on Windows,it doesn't draw the background on the label
	// on X, it doesn't fix the clipping rectangle for it
	version(win32_widgets)
		override int paddingTop() { return Window.lineHeight; }
	else version(custom_widgets)
		override int paddingTop() { return Window.lineHeight + 2; }
	else static assert(false);
	override int paddingBottom() { return 6; }
	override int paddingLeft() { return 6; }
	override int paddingRight() { return 6; }

	override int marginLeft() { return 6; }
	override int marginRight() { return 6; }
	override int marginTop() { return 2; }
	override int marginBottom() { return 2; }

	string legend;

	///
	this(string legend, Widget parent) {
		version(win32_widgets) {
			super(parent);
			this.legend = legend;
			createWin32Window(this, "button"w, legend, BS_GROUPBOX);
			tabStop = false;
		} else version(custom_widgets) {
			super(parent);
			tabStop = false;
			this.legend = legend;
		} else static assert(0);
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		painter.fillColor = Color.transparent;
		painter.pen = Pen(Color.black, 1);
		painter.drawRectangle(Point(0, Window.lineHeight / 2), width, height - Window.lineHeight / 2);

		auto tx = painter.textSize(legend);
		painter.outlineColor = Color.transparent;

		static if(UsingSimpledisplayX11) {
			painter.fillColor = windowBackgroundColor;
			painter.drawRectangle(Point(8, 0), tx.width, tx.height);
		} else version(Windows) {
			auto b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
			painter.drawRectangle(Point(8, -tx.height/2), tx.width, tx.height);
			SelectObject(painter.impl.hdc, b);
		} else static assert(0);
		painter.outlineColor = Color.black;
		painter.drawText(Point(8, 0), legend);
	}


	override int maxHeight() {
		auto m = paddingTop() + paddingBottom();
		foreach(child; children) {
			m += child.maxHeight();
			m += child.marginBottom();
			m += child.marginTop();
		}
		return m + 6;
	}

	override int minHeight() {
		auto m = paddingTop() + paddingBottom();
		foreach(child; children) {
			m += child.minHeight();
			m += child.marginBottom();
			m += child.marginTop();
		}
		return m + 6;
	}
}

/// Draws a line
class HorizontalRule : Widget {
	mixin Margin!q{ 2 };
	override int minHeight() { return 2; }
	override int maxHeight() { return 2; }

	///
	this(Widget parent = null) {
		super(parent);
	}

	override void paint(ScreenPainter painter) {
		painter.outlineColor = darkAccentColor;
		painter.drawLine(Point(0, 0), Point(width, 0));
		painter.outlineColor = lightAccentColor;
		painter.drawLine(Point(0, 1), Point(width, 1));
	}
}

/// ditto
class VerticalRule : Widget {
	mixin Margin!q{ 2 };
	override int minWidth() { return 2; }
	override int maxWidth() { return 2; }

	///
	this(Widget parent = null) {
		super(parent);
	}

	override void paint(ScreenPainter painter) {
		painter.outlineColor = darkAccentColor;
		painter.drawLine(Point(0, 0), Point(0, height));
		painter.outlineColor = lightAccentColor;
		painter.drawLine(Point(1, 0), Point(1, height));
	}
}


///
class Menu : Window {
	void remove() {
		foreach(i, child; parentWindow.children)
			if(child is this) {
				parentWindow.children = parentWindow.children[0 .. i] ~ parentWindow.children[i + 1 .. $];
				break;
			}
		parentWindow.redraw();

		parentWindow.releaseMouseCapture();
	}

	///
	void addSeparator() {
		version(win32_widgets)
			AppendMenu(handle, MF_SEPARATOR, 0, null);
		else version(custom_widgets)
			auto hr = new HorizontalRule(this);
		else static assert(0);
	}

	override int paddingTop() { return 4; }
	override int paddingBottom() { return 4; }
	override int paddingLeft() { return 2; }
	override int paddingRight() { return 2; }

	version(win32_widgets) {}
	else version(custom_widgets) {
		SimpleWindow dropDown;
		Widget menuParent;
		void popup(Widget parent) {
			this.menuParent = parent;

			auto w = 150;
			auto h = paddingTop + paddingBottom;
			Widget previousChild;
			foreach(child; this.children) {
				h += child.minHeight();
				h += mymax(child.marginTop(), previousChild ? previousChild.marginBottom() : 0);
				previousChild = child;
			}

			if(previousChild)
			h += previousChild.marginBottom();

			auto coord = parent.globalCoordinates();
			dropDown.moveResize(coord.x, coord.y + parent.parentWindow.lineHeight, w, h);
			this.x = 0;
			this.y = 0;
			this.width = dropDown.width;
			this.height = dropDown.height;
			this.drawableWindow = dropDown;
			this.recomputeChildLayout();

			static if(UsingSimpledisplayX11)
				XSync(XDisplayConnection.get, 0);

			dropDown.visibilityChanged = (bool visible) {
				if(visible) {
					this.redraw();
					dropDown.grabInput();
				} else {
					dropDown.releaseInputGrab();
				}
			};

			dropDown.show();

			bool firstClick = true;

			clickListener = this.addEventListener(EventType.click, (Event ev) {
				if(firstClick) {
					firstClick = false;
					//return;
				}
				//if(ev.clientX < 0 || ev.clientY < 0 || ev.clientX > width || ev.clientY > height)
					unpopup();
			});
		}

		EventListener clickListener;
	}
	else static assert(false);

	version(custom_widgets)
	void unpopup() {
		mouseLastOver = mouseLastDownOn = null;
		dropDown.hide();
		if(!menuParent.parentWindow.win.closed) {
			if(auto maw = cast(MouseActivatedWidget) menuParent) {
				maw.isDepressed = false;
				maw.isHovering = false;
				maw.redraw();
			}
			menuParent.parentWindow.win.focus();
		}
		clickListener.disconnect();
	}

	MenuItem[] items;

	///
	MenuItem addItem(MenuItem item) {
		addChild(item);
		items ~= item;
		version(win32_widgets) {
			AppendMenuW(handle, MF_STRING, item.action is null ? 9000 : item.action.id, toWstringzInternal(item.label));
		}
		return item;
	}

	string label;

	version(win32_widgets) {
		HMENU handle;
		///
		this(string label, Widget parent = null) {
			super(parent);
			this.label = label;
			handle = CreatePopupMenu();
		}
	} else version(custom_widgets) {
		///
		this(string label, Widget parent = null) {

			if(dropDown) {
				dropDown.close();
			}
			dropDown = new SimpleWindow(
				150, 4,
				null, OpenGlOptions.no, Resizability.fixedSize, WindowTypes.dropdownMenu, WindowFlags.dontAutoShow/*, window*/);

			this.label = label;

			super(dropDown);
		}
	} else static assert(false);

	override int maxHeight() { return Window.lineHeight; }
	override int minHeight() { return Window.lineHeight; }

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		this.draw3dFrame(painter, FrameStyle.risen);
	}
}

///
class MenuItem : MouseActivatedWidget {
	Menu submenu;

	Action action;
	string label;

	override int paddingLeft() { return 4; }

	override int maxHeight() { return Window.lineHeight + 4; }
	override int minHeight() { return Window.lineHeight + 4; }
	override int minWidth() { return Window.lineHeight * cast(int) label.length + 8; }
	override int maxWidth() {
		if(cast(MenuBar) parent)
			return Window.lineHeight / 2 * cast(int) label.length + 8;
		return int.max;
	}
	///
	this(string lbl, Widget parent = null) {
		super(parent);
		//label = lbl; // FIXME
		foreach(char ch; lbl) // FIXME
			if(ch != '&') // FIXME
				label ~= ch; // FIXME
		tabStop = false; // these are selected some other way
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		if(isDepressed)
			this.draw3dFrame(painter, FrameStyle.sunk);
		if(isHovering)
			painter.outlineColor = activeMenuItemColor;
		else
			painter.outlineColor = Color.black;
		painter.fillColor = Color.transparent;
		painter.drawText(Point(cast(MenuBar) this.parent ? 4 : 20, 2), label, Point(width, height), TextAlignment.Left);
		if(action && action.accelerator !is KeyEvent.init) {
			painter.drawText(Point(cast(MenuBar) this.parent ? 4 : 20, 2), action.accelerator.toStr(), Point(width - 4, height), TextAlignment.Right);

		}
	}


	///
	this(Action action, Widget parent = null) {
		assert(action !is null);
		this(action.label);
		this.action = action;
		tabStop = false; // these are selected some other way
	}

	override void defaultEventHandler_triggered(Event event) {
		if(action)
		foreach(handler; action.triggered)
			handler();

		if(auto pmenu = cast(Menu) this.parent)
			pmenu.remove();

		super.defaultEventHandler_triggered(event);
	}
}

version(win32_widgets)
///
class MouseActivatedWidget : Widget {
	bool isChecked() {
		assert(hwnd);
		return SendMessageW(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED;

	}
	void isChecked(bool state) {
		assert(hwnd);
		SendMessageW(hwnd, BM_SETCHECK, state ? BST_CHECKED : BST_UNCHECKED, 0);

	}

	this(Widget parent = null) {
		super(parent);
	}
}
else version(custom_widgets)
///
class MouseActivatedWidget : Widget {
	bool isDepressed = false;
	bool isHovering = false;
	bool isChecked = false;

	override void attachedToWindow(Window w) {
		w.addEventListener("mouseup", delegate (Widget _this, Event ev) {
			isDepressed = false;
		});
	}

	this(Widget parent = null) {
		super(parent);
		addEventListener("mouseenter", delegate (Widget _this, Event ev) {
			isHovering = true;
			redraw();
		});

		addEventListener("mouseleave", delegate (Widget _this, Event ev) {
			isHovering = false;
			isDepressed = false;
			redraw();
		});

		addEventListener("mousedown", delegate (Widget _this, Event ev) {
			isDepressed = true;
			redraw();
		});

		addEventListener("mouseup", delegate (Widget _this, Event ev) {
			isDepressed = false;
			redraw();
		});
	}

	override void defaultEventHandler_focus(Event ev) {
		super.defaultEventHandler_focus(ev);
		this.redraw();
	}
	override void defaultEventHandler_blur(Event ev) {
		super.defaultEventHandler_blur(ev);
		isDepressed = false;
		isHovering = false;
		this.redraw();
	}
	override void defaultEventHandler_keydown(Event ev) {
		super.defaultEventHandler_keydown(ev);
		if(ev.key == Key.Space || ev.key == Key.Enter || ev.key == Key.PadEnter) {
			isDepressed = true;
			this.redraw();
		}
	}
	override void defaultEventHandler_keyup(Event ev) {
		super.defaultEventHandler_keyup(ev);
		if(!isDepressed)
			return;
		isDepressed = false;
		this.redraw();

		auto event = new Event("triggered", this);
		event.sendDirectly();
	}
	override void defaultEventHandler_click(Event ev) {
		super.defaultEventHandler_click(ev);
		if(this.tabStop)
			this.focus();
		auto event = new Event("triggered", this);
		event.sendDirectly();
	}

}
else static assert(false);


///
class Checkbox : MouseActivatedWidget {

	version(win32_widgets) {
		override int maxHeight() { return 16; }
		override int minHeight() { return 16; }
	} else version(custom_widgets) {
		override int maxHeight() { return Window.lineHeight; }
		override int minHeight() { return Window.lineHeight; }
	} else static assert(0);

	override int marginLeft() { return 4; }

	private string label;

	///
	this(string label, Widget parent = null) {
		super(parent);
		this.label = label;
		version(win32_widgets) {
			createWin32Window(this, "button"w, label, BS_AUTOCHECKBOX);
		} else version(custom_widgets) {

		} else static assert(0);
	}

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		if(isFocused()) {
			painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
			painter.fillColor = windowBackgroundColor;
			painter.drawRectangle(Point(0, 0), width, height);
			painter.pen = Pen(Color.black, 1, Pen.Style.Solid);
		} else {
			painter.pen = Pen(windowBackgroundColor, 1, Pen.Style.Solid);
			painter.fillColor = windowBackgroundColor;
			painter.drawRectangle(Point(0, 0), width, height);
		}


		enum buttonSize = 16;

		painter.outlineColor = Color.black;
		painter.fillColor = Color.white;
		painter.drawRectangle(Point(2, 2), buttonSize - 2, buttonSize - 2);

		if(isChecked) {
			painter.pen = Pen(Color.black, 2);
			// I'm using height so the checkbox is square
			enum padding = 5;
			painter.drawLine(Point(padding, padding), Point(buttonSize - (padding-2), buttonSize - (padding-2)));
			painter.drawLine(Point(buttonSize-(padding-2), padding), Point(padding, buttonSize - (padding-2)));

			painter.pen = Pen(Color.black, 1);
		}

		painter.drawText(Point(buttonSize + 4, 0), label, Point(width, height), TextAlignment.Left | TextAlignment.VerticalCenter);
	}

	override void defaultEventHandler_triggered(Event ev) {
		isChecked = !isChecked;

		auto event = new Event(EventType.change, this);
		event.dispatch();

		redraw();
	};

}

/// Adds empty space to a layout.
class VerticalSpacer : Widget {
	///
	this(Widget parent = null) {
		super(parent);
	}
}

/// ditto
class HorizontalSpacer : Widget {
	///
	this(Widget parent = null) {
		super(parent);
		this.tabStop = false;
	}
}


///
class Radiobox : MouseActivatedWidget {

	version(win32_widgets) {
		override int maxHeight() { return 16; }
		override int minHeight() { return 16; }
	} else version(custom_widgets) {
		override int maxHeight() { return Window.lineHeight; }
		override int minHeight() { return Window.lineHeight; }
	} else static assert(0);

	override int marginLeft() { return 4; }

	private string label;

	version(win32_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		this.label = label;
		createWin32Window(this, "button"w, label, BS_AUTORADIOBUTTON);
	}
	else version(custom_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		this.label = label;
		height = 16;
		width = height + 4 + cast(int) label.length * 16;
	}
	else static assert(false);

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		if(isFocused) {
			painter.fillColor = windowBackgroundColor;
			painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
		} else {
			painter.fillColor = windowBackgroundColor;
			painter.outlineColor = windowBackgroundColor;
		}
		painter.drawRectangle(Point(0, 0), width, height);

		painter.pen = Pen(Color.black, 1, Pen.Style.Solid);

		enum buttonSize = 16;

		painter.outlineColor = Color.black;
		painter.fillColor = Color.white;
		painter.drawEllipse(Point(2, 2), Point(buttonSize - 2, buttonSize - 2));
		if(isChecked) {
			painter.outlineColor = Color.black;
			painter.fillColor = Color.black;
			// I'm using height so the checkbox is square
			painter.drawEllipse(Point(5, 5), Point(buttonSize - 5, buttonSize - 5));
		}

		painter.drawText(Point(buttonSize + 4, 0), label, Point(width, height), TextAlignment.Left | TextAlignment.VerticalCenter);
	}


	override void defaultEventHandler_triggered(Event ev) {
		isChecked = true;

		if(this.parent) {
			foreach(child; this.parent.children) {
				if(child is this) continue;
				if(auto rb = cast(Radiobox) child) {
					rb.isChecked = false;
					auto event = new Event(EventType.change, rb);
					event.dispatch();
					rb.redraw();
				}
			}
		}

		auto event = new Event(EventType.change, this);
		event.dispatch();

		redraw();
	}

}


///
class Button : MouseActivatedWidget {
	Color normalBgColor;
	Color hoverBgColor;
	Color depressedBgColor;

	override int heightStretchiness() { return 3; }
	override int widthStretchiness() { return 3; }

	version(win32_widgets)
	override void handleWmCommand(ushort cmd, ushort id) {
		auto event = new Event("triggered", this);
		event.dispatch();
	}

	version(win32_widgets) {}
	else version(custom_widgets)
	Color currentButtonColor() {
		if(isHovering) {
			return isDepressed ? depressedBgColor : hoverBgColor;
		}

		return normalBgColor;
	}
	else static assert(false);

	private string label_;

	string label() { return label_; }
	void label(string l) {
		label_ = l;
		version(win32_widgets) {
			WCharzBuffer bfr = WCharzBuffer(l);
			SetWindowTextW(hwnd, bfr.ptr);
		} else version(custom_widgets) {
			redraw();
		}
	}

	version(win32_widgets)
	this(string label, Widget parent = null) {
		// FIXME: use ideal button size instead
		width = 50;
		height = 30;
		super(parent);
		createWin32Window(this, "button"w, label, BS_PUSHBUTTON);

		this.label = label;
	}
	else version(custom_widgets)
	this(string label, Widget parent = null) {
		width = 50;
		height = 30;
		super(parent);
		normalBgColor = buttonColor;
		hoverBgColor = hoveringColor;
		depressedBgColor = depressedButtonColor;

		this.label = label;
	}
	else static assert(false);

	override int minHeight() { return Window.lineHeight + 4; }

	version(custom_widgets)
	override void paint(ScreenPainter painter) {
		this.draw3dFrame(painter, isDepressed ? FrameStyle.sunk : FrameStyle.risen, currentButtonColor);


		painter.outlineColor = Color.black;
		painter.drawText(Point(0, 0), label, Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);

		if(isFocused()) {
			painter.fillColor = Color.transparent;
			painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
			painter.drawRectangle(Point(2, 2), width - 4, height - 4);
			painter.pen = Pen(Color.black, 1, Pen.Style.Solid);

		}
	}

}

/++
	A button with a consistent size, suitable for user commands like OK and Cancel.
+/
class CommandButton : Button {
	this(string label, Widget parent = null) {
		super(label, parent);
	}

	override int maxHeight() {
		return Window.lineHeight + 4;
	}

	override int maxWidth() {
		return Window.lineHeight * 4;
	}

	override int marginLeft() { return 12; }
	override int marginRight() { return 12; }
	override int marginTop() { return 12; }
	override int marginBottom() { return 12; }
}

///
enum ArrowDirection {
	left, ///
	right, ///
	up, ///
	down ///
}

///
version(custom_widgets)
class ArrowButton : Button {
	///
	this(ArrowDirection direction, Widget parent = null) {
		super("", parent);
		this.direction = direction;
	}

	private ArrowDirection direction;

	override int minHeight() { return 16; }
	override int maxHeight() { return 16; }
	override int minWidth() { return 16; }
	override int maxWidth() { return 16; }

	override void paint(ScreenPainter painter) {
		super.paint(painter);

		painter.outlineColor = Color.black;
		painter.fillColor = Color.black;

		auto offset = Point((this.width - 16) / 2, (this.height - 16) / 2);

		final switch(direction) {
			case ArrowDirection.up:
				painter.drawPolygon(
					Point(2, 10) + offset,
					Point(7, 5) + offset,
					Point(12, 10) + offset,
					Point(2, 10) + offset
				);
			break;
			case ArrowDirection.down:
				painter.drawPolygon(
					Point(2, 6) + offset,
					Point(7, 11) + offset,
					Point(12, 6) + offset,
					Point(2, 6) + offset
				);
			break;
			case ArrowDirection.left:
				painter.drawPolygon(
					Point(10, 2) + offset,
					Point(5, 7) + offset,
					Point(10, 12) + offset,
					Point(10, 2) + offset
				);
			break;
			case ArrowDirection.right:
				painter.drawPolygon(
					Point(6, 2) + offset,
					Point(11, 7) + offset,
					Point(6, 12) + offset,
					Point(6, 2) + offset
				);
			break;
		}
	}
}

private
int[2] getChildPositionRelativeToParentOrigin(Widget c) nothrow {
	int x, y;
	Widget par = c;
	while(par) {
		x += par.x;
		y += par.y;
		par = par.parent;
	}
	return [x, y];
}

version(win32_widgets)
private
int[2] getChildPositionRelativeToParentHwnd(Widget c) nothrow {
	int x, y;
	Widget par = c;
	while(par) {
		x += par.x;
		y += par.y;
		par = par.parent;
		if(par !is null && par.hwnd !is null)
			break;
	}
	return [x, y];
}

///
class ImageBox : Widget {
	private MemoryImage image_;

	///
	public void setImage(MemoryImage image){
		this.image_ = image;
		if(this.parentWindow && this.parentWindow.win)
			sprite = new Sprite(this.parentWindow.win, Image.fromMemoryImage(image_));
		redraw();
	}

	/// How to fit the image in the box if they aren't an exact match in size?
	enum HowToFit {
		center, /// centers the image, cropping around all the edges as needed
		crop, /// always draws the image in the upper left, cropping the lower right if needed
		// stretch, /// not implemented
	}

	private Sprite sprite;
	private HowToFit howToFit_;

	private Color backgroundColor_;

	///
	this(MemoryImage image, HowToFit howToFit, Color backgroundColor = Color.transparent, Widget parent = null) {
		this.image_ = image;
		this.tabStop = false;
		this.howToFit_ = howToFit;
		this.backgroundColor_ = backgroundColor;
		super(parent);
		updateSprite();
	}

	private void updateSprite() {
		if(sprite is null && this.parentWindow && this.parentWindow.win)
			sprite = new Sprite(this.parentWindow.win, Image.fromMemoryImage(image_));
	}

	override void paint(ScreenPainter painter) {
		updateSprite();
		if(backgroundColor_.a) {
			painter.fillColor = backgroundColor_;
			painter.drawRectangle(Point(0, 0), width, height);
		}
		if(howToFit_ == HowToFit.crop)
			sprite.drawAt(painter, Point(0, 0));
		else if(howToFit_ == HowToFit.center) {
			sprite.drawAt(painter, Point((width - image_.width) / 2, (height - image_.height) / 2));
		}
	}
}

///
class TextLabel : Widget {
	override int maxHeight() { return Window.lineHeight; }
	override int minHeight() { return Window.lineHeight; }
	override int minWidth() { return 32; }

	string label_;

	///
	@scriptable
	string label() { return label_; }

	///
	@scriptable
	void label(string l) {
		label_ = l;
		redraw();
	}

	///
	this(string label, Widget parent = null) {
		this.label_ = label;
		this.alignment = TextAlignment.Right;
		this.tabStop = false;
		super(parent);
	}

	///
	this(string label, TextAlignment alignment, Widget parent = null) {
		this.label_ = label;
		this.alignment = alignment;
		this.tabStop = false;
		super(parent);
	}

	TextAlignment alignment;

	override void paint(ScreenPainter painter) {
		painter.outlineColor = Color.black;
		painter.drawText(Point(0, 0), this.label, Point(width,height), alignment);
	}

}

version(custom_widgets)
	private mixin ExperimentalTextComponent;

version(win32_widgets)
	alias EditableTextWidgetParent = Widget; ///
else version(custom_widgets)
	alias EditableTextWidgetParent = ScrollableWidget; ///
else static assert(0);

/// Contains the implementation of text editing
abstract class EditableTextWidget : EditableTextWidgetParent {
	this(Widget parent = null) {
		super(parent);
	}

	override int minWidth() { return 16; }
	override int minHeight() { return Window.lineHeight + 0; } // the +0 is to leave room for the padding
	override int widthStretchiness() { return 7; }

	void selectAll() {
		version(win32_widgets)
			SendMessage(hwnd, EM_SETSEL, 0, -1);
		else version(custom_widgets) {
			textLayout.selectAll();
			redraw();
		}
	}

	@property string content() {
		version(win32_widgets) {
			wchar[4096] bufferstack;
			wchar[] buffer;
			auto len = GetWindowTextLength(hwnd);
			if(len < bufferstack.length)
				buffer = bufferstack[0 .. len + 1];
			else
				buffer = new wchar[](len + 1);

			auto l = GetWindowTextW(hwnd, buffer.ptr, cast(int) buffer.length);
			if(l >= 0)
				return makeUtf8StringFromWindowsString(buffer[0 .. l]);
			else
				return null;
		} else version(custom_widgets) {
			return textLayout.getPlainText();
		} else static assert(false);
	}
	@property void content(string s) {
		version(win32_widgets) {
			WCharzBuffer bfr = WCharzBuffer(s, WindowsStringConversionFlags.convertNewLines);
			SetWindowTextW(hwnd, bfr.ptr);
		} else version(custom_widgets) {
			textLayout.clear();
			textLayout.addText(s);

			{
			// FIXME: it should be able to get this info easier
			auto painter = draw();
			textLayout.redoLayout(painter);
			}
			auto cbb = textLayout.contentBoundingBox();
			setContentSize(cbb.width, cbb.height);
			/*
			textLayout.addText(ForegroundColor.red, s);
			textLayout.addText(ForegroundColor.blue, TextFormat.underline, "http://dpldocs.info/");
			textLayout.addText(" is the best!");
			*/
			redraw();
		}
		else static assert(false);
	}

	void addText(string txt) {
		version(custom_widgets) {
			textLayout.addText(txt);

			{
			// FIXME: it should be able to get this info easier
			auto painter = draw();
			textLayout.redoLayout(painter);
			}
			auto cbb = textLayout.contentBoundingBox();
			setContentSize(cbb.width, cbb.height);

		} else
			content = content ~ txt;
	}

	version(custom_widgets)
	override void paintFrameAndBackground(ScreenPainter painter) {
		this.draw3dFrame(painter, FrameStyle.sunk, Color.white);
	}

	version(win32_widgets) { /* will do it with Windows calls in the classes */ }
	else version(custom_widgets) {
		// FIXME

		Timer caretTimer;
		TextLayout textLayout;

		void setupCustomTextEditing() {
			textLayout = new TextLayout(Rectangle(4, 2, width - 8, height - 4));
		}

		override void paint(ScreenPainter painter) {
			if(parentWindow.win.closed) return;

			textLayout.boundingBox = Rectangle(4, 2, width - 8, height - 4);

			/*
			painter.outlineColor = Color.white;
			painter.fillColor = Color.white;
			painter.drawRectangle(Point(4, 4), contentWidth, contentHeight);
			*/

			painter.outlineColor = Color.black;
			// painter.drawText(Point(4, 4), content, Point(width - 4, height - 4));

			textLayout.caretShowingOnScreen = false;

			textLayout.drawInto(painter, !parentWindow.win.closed && isFocused());
		}


		override MouseCursor cursor() {
			return GenericCursor.Text;
		}
	}
	else static assert(false);



	version(custom_widgets)
	override void defaultEventHandler_mousedown(Event ev) {
		super.defaultEventHandler_mousedown(ev);
		if(parentWindow.win.closed) return;
		if(ev.button == MouseButton.left) {
			if(textLayout.selectNone())
				redraw();
			textLayout.moveCaretToPixelCoordinates(ev.clientX, ev.clientY);
			this.focus();
			//this.parentWindow.win.grabInput();
		} else if(ev.button == MouseButton.middle) {
			static if(UsingSimpledisplayX11) {
				getPrimarySelection(parentWindow.win, (txt) {
					textLayout.insert(txt);
					redraw();

					auto cbb = textLayout.contentBoundingBox();
					setContentSize(cbb.width, cbb.height);
				});
			}
		}
	}

	version(custom_widgets)
	override void defaultEventHandler_mouseup(Event ev) {
		//this.parentWindow.win.releaseInputGrab();
		super.defaultEventHandler_mouseup(ev);
	}

	version(custom_widgets)
	override void defaultEventHandler_mousemove(Event ev) {
		super.defaultEventHandler_mousemove(ev);
		if(ev.state & ModifierState.leftButtonDown) {
			textLayout.selectToPixelCoordinates(ev.clientX, ev.clientY);
			redraw();
		}
	}

	version(custom_widgets)
	override void defaultEventHandler_focus(Event ev) {
		super.defaultEventHandler_focus(ev);
		if(parentWindow.win.closed) return;
		auto painter = this.draw();
		textLayout.drawCaret(painter);

		if(caretTimer) {
			caretTimer.destroy();
			caretTimer = null;
		}

		bool blinkingCaret = true;
		static if(UsingSimpledisplayX11)
			if(!Image.impl.xshmAvailable)
				blinkingCaret = false; // if on a remote connection, don't waste bandwidth on an expendable blink

		if(blinkingCaret)
		caretTimer = new Timer(500, {
			if(parentWindow.win.closed) {
				caretTimer.destroy();
				return;
			}
			if(isFocused()) {
				auto painter = this.draw();
				textLayout.drawCaret(painter);
			} else if(textLayout.caretShowingOnScreen) {
				auto painter = this.draw();
				textLayout.eraseCaret(painter);
			}
		});
	}

	override void defaultEventHandler_blur(Event ev) {
		super.defaultEventHandler_blur(ev);
		if(parentWindow.win.closed) return;
		version(custom_widgets) {
			auto painter = this.draw();
			textLayout.eraseCaret(painter);
			if(caretTimer) {
				caretTimer.destroy();
				caretTimer = null;
			}
		}

		auto evt = new Event(EventType.change, this);
		evt.stringValue = this.content;
		evt.dispatch();
	}

	version(custom_widgets)
	override void defaultEventHandler_char(Event ev) {
		super.defaultEventHandler_char(ev);
		textLayout.insert(ev.character);
		redraw();

		// FIXME: too inefficient
		auto cbb = textLayout.contentBoundingBox();
		setContentSize(cbb.width, cbb.height);
	}
	version(custom_widgets)
	override void defaultEventHandler_keydown(Event ev) {
		//super.defaultEventHandler_keydown(ev);
		switch(ev.key) {
			case Key.Delete:
				textLayout.delete_();
				redraw();
			break;
			case Key.Left:
				textLayout.moveLeft();
				redraw();
			break;
			case Key.Right:
				textLayout.moveRight();
				redraw();
			break;
			case Key.Up:
				textLayout.moveUp();
				redraw();
			break;
			case Key.Down:
				textLayout.moveDown();
				redraw();
			break;
			case Key.Home:
				textLayout.moveHome();
				redraw();
			break;
			case Key.End:
				textLayout.moveEnd();
				redraw();
			break;
			case Key.PageUp:
				foreach(i; 0 .. 32)
				textLayout.moveUp();
				redraw();
			break;
			case Key.PageDown:
				foreach(i; 0 .. 32)
				textLayout.moveDown();
				redraw();
			break;

			default:
				 {} // intentionally blank, let "char" handle it
		}
		/*
		if(ev.key == Key.Backspace) {
			textLayout.backspace();
			redraw();
		}
		*/
		ensureVisibleInScroll(textLayout.caretBoundingBox());
	}


}

///
class LineEdit : EditableTextWidget {
	// FIXME: hack
	version(custom_widgets) {
	override bool showingVerticalScroll() { return false; }
	override bool showingHorizontalScroll() { return false; }
	}

	///
	this(Widget parent = null) {
		super(parent);
		version(win32_widgets) {
			createWin32Window(this, "edit"w, "", 
				0, WS_EX_CLIENTEDGE);//|WS_HSCROLL|ES_AUTOHSCROLL);
		} else version(custom_widgets) {
			setupCustomTextEditing();
			addEventListener("char", delegate(Widget _this, Event ev) {
				if(ev.character == '\n')
					ev.preventDefault();
			});
		} else static assert(false);
	}
	override int maxHeight() { return Window.lineHeight + 4; }
	override int minHeight() { return Window.lineHeight + 4; }
}

///
class TextEdit : EditableTextWidget {
	///
	this(Widget parent = null) {
		super(parent);
		version(win32_widgets) {
			createWin32Window(this, "edit"w, "", 
				0|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_WANTRETURN|ES_AUTOHSCROLL|ES_AUTOVSCROLL, WS_EX_CLIENTEDGE);
		} else version(custom_widgets) {
			setupCustomTextEditing();
		} else static assert(false);
	}
	override int maxHeight() { return int.max; }
	override int heightStretchiness() { return 7; }
}


/++

+/
version(none)
class RichTextDisplay : Widget {
	@property void content(string c) {}
	void appendContent(string c) {}
}

///
class MessageBox : Window {
	private string message;
	MessageBoxButton buttonPressed = MessageBoxButton.None;
	///
	this(string message, string[] buttons = ["OK"], MessageBoxButton[] buttonIds = [MessageBoxButton.OK]) {
		super(300, 100);

		assert(buttons.length);
		assert(buttons.length ==  buttonIds.length);

		this.message = message;

		int buttonsWidth = cast(int) buttons.length * 50 + (cast(int) buttons.length - 1) * 16;

		int x = this.width / 2 - buttonsWidth / 2;

		foreach(idx, buttonText; buttons) {
			auto button = new Button(buttonText, this);
			button.x = x;
			button.y = height - (button.height + 10);
			button.addEventListener(EventType.triggered, ((size_t idx) { return () {
				this.buttonPressed = buttonIds[idx];
				win.close();
			}; })(idx));

			button.registerMovement();
			x += button.width;
			x += 16;
			if(idx == 0)
				button.focus();
		}

		win.show();
		redraw();
	}

	override void paint(ScreenPainter painter) {
		super.paint(painter);
		painter.outlineColor = Color.black;
		painter.drawText(Point(0, 0), message, Point(width, height / 2), TextAlignment.Center | TextAlignment.VerticalCenter);
	}

	// this one is all fixed position
	override void recomputeChildLayout() {}
}

///
enum MessageBoxStyle {
	OK, ///
	OKCancel, ///
	RetryCancel, ///
	YesNo, ///
	YesNoCancel, ///
	RetryCancelContinue /// In a multi-part process, if one part fails, ask the user if you should retry that failed step, cancel the entire process, or just continue with the next step, accepting failure on this step.
}

///
enum MessageBoxIcon {
	None, ///
	Info, ///
	Warning, ///
	Error ///
}

/// Identifies the button the user pressed on a message box.
enum MessageBoxButton {
	None, /// The user closed the message box without clicking any of the buttons.
	OK, ///
	Cancel, ///
	Retry, ///
	Yes, ///
	No, ///
	Continue ///
}


/++
	Displays a modal message box, blocking until the user dismisses it.

	Returns: the button pressed.
+/
MessageBoxButton messageBox(string title, string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
	version(win32_widgets) {
		WCharzBuffer t = WCharzBuffer(title);
		WCharzBuffer m = WCharzBuffer(message);
		UINT type;
		with(MessageBoxStyle)
		final switch(style) {
			case OK: type |= MB_OK; break;
			case OKCancel: type |= MB_OKCANCEL; break;
			case RetryCancel: type |= MB_RETRYCANCEL; break;
			case YesNo: type |= MB_YESNO; break;
			case YesNoCancel: type |= MB_YESNOCANCEL; break;
			case RetryCancelContinue: type |= MB_CANCELTRYCONTINUE; break;
		}
		with(MessageBoxIcon)
		final switch(icon) {
			case None: break;
			case Info: type |= MB_ICONINFORMATION; break;
			case Warning: type |= MB_ICONWARNING; break;
			case Error: type |= MB_ICONERROR; break;
		}
		switch(MessageBoxW(null, m.ptr, t.ptr, type)) {
			case IDOK: return MessageBoxButton.OK;
			case IDCANCEL: return MessageBoxButton.Cancel;
			case IDTRYAGAIN, IDRETRY: return MessageBoxButton.Retry;
			case IDYES: return MessageBoxButton.Yes;
			case IDNO: return MessageBoxButton.No;
			case IDCONTINUE: return MessageBoxButton.Continue;
			default: return MessageBoxButton.None;
		}
	} else {
		string[] buttons;
		MessageBoxButton[] buttonIds;
		with(MessageBoxStyle)
		final switch(style) {
			case OK:
				buttons = ["OK"];
				buttonIds = [MessageBoxButton.OK];
			break;
			case OKCancel:
				buttons = ["OK", "Cancel"];
				buttonIds = [MessageBoxButton.OK, MessageBoxButton.Cancel];
			break;
			case RetryCancel:
				buttons = ["Retry", "Cancel"];
				buttonIds = [MessageBoxButton.Retry, MessageBoxButton.Cancel];
			break;
			case YesNo:
				buttons = ["Yes", "No"];
				buttonIds = [MessageBoxButton.Yes, MessageBoxButton.No];
			break;
			case YesNoCancel:
				buttons = ["Yes", "No", "Cancel"];
				buttonIds = [MessageBoxButton.Yes, MessageBoxButton.No, MessageBoxButton.Cancel];
			break;
			case RetryCancelContinue:
				buttons = ["Try Again", "Cancel", "Continue"];
				buttonIds = [MessageBoxButton.Retry, MessageBoxButton.Cancel, MessageBoxButton.Continue];
			break;
		}
		auto mb = new MessageBox(message, buttons, buttonIds);
		EventLoop el = EventLoop.get;
		el.run(() { return !mb.win.closed; });
		return mb.buttonPressed;
	}
}

/// ditto
int messageBox(string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
	return messageBox(null, message, style, icon);
}



///
alias void delegate(Widget handlerAttachedTo, Event event) EventHandler;

///
struct EventListener {
	Widget widget;
	string event;
	EventHandler handler;
	bool useCapture;

	///
	void disconnect() {
		widget.removeEventListener(this);
	}
}

///
enum EventType : string {
	click = "click", ///

	mouseenter = "mouseenter", ///
	mouseleave = "mouseleave", ///
	mousein = "mousein", ///
	mouseout = "mouseout", ///
	mouseup = "mouseup", ///
	mousedown = "mousedown", ///
	mousemove = "mousemove", ///

	keydown = "keydown", ///
	keyup = "keyup", ///
	char_ = "char", ///

	focus = "focus", ///
	blur = "blur", ///

	triggered = "triggered", ///

	change = "change", ///
}

///
class Event {
	/// Creates an event without populating any members and without sending it. See [dispatch]
	this(string eventName, Widget target) {
		this.eventName = eventName;
		this.srcElement = target;
	}

	/// Prevents the default event handler (if there is one) from being called
	void preventDefault() {
		lastDefaultPrevented = true;
		defaultPrevented = true;
	}

	/// Stops the event propagation immediately.
	void stopPropagation() {
		propagationStopped = true;
	}

	private bool defaultPrevented;
	private bool propagationStopped;
	private string eventName;

	Widget srcElement; ///
	alias srcElement target; ///

	Widget relatedTarget; ///

	// for mouse events
	int clientX; /// The mouse event location relative to the target widget
	int clientY; /// ditto

	int viewportX; /// The mouse event location relative to the window origin
	int viewportY; /// ditto

	int button; /// [MouseEvent.button]
	int buttonLinear; /// [MouseEvent.buttonLinear]

	// for key events
	Key key; ///

	KeyEvent originalKeyEvent;

	// char character events
	dchar character; ///

	// for several event types
	int state; ///

	// for change events
	int intValue; ///
	string stringValue; ///

	bool shiftKey; ///

	private bool isBubbling;

	private void adjustScrolling() {
	version(custom_widgets) { // TEMP
		viewportX = clientX;
		viewportY = clientY;
		if(auto se = cast(ScrollableWidget) srcElement) {
			clientX += se.scrollOrigin.x;
			clientY += se.scrollOrigin.y;
		}
	}
	}

	/// this sends it only to the target. If you want propagation, use dispatch() instead.
	void sendDirectly() {
		if(srcElement is null)
			return;

		//debug if(eventName != "mousemove" && target !is null && target.parentWindow && target.parentWindow.devTools)
			//target.parentWindow.devTools.log("Event ", eventName, " dispatched directly to ", srcElement);

		adjustScrolling();

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

		//debug if(eventName != "mousemove" && target !is null && target.parentWindow && target.parentWindow.devTools)
			//target.parentWindow.devTools.log("Event ", eventName, " dispatched to ", srcElement);

		adjustScrolling();
		// first capture, then bubble

		Widget[] chain;
		Widget curr = srcElement;
		while(curr) {
			auto l = curr;
			chain ~= l;
			curr = curr.parent;
		}

		isBubbling = false;

		foreach_reverse(e; chain) {
			if(eventName in e.capturingEventHandlers)
			foreach(handler; e.capturingEventHandlers[eventName])
				if(handler !is null)
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
				if(handler !is null)
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

private bool isAParentOf(Widget a, Widget b) {
	if(a is null || b is null)
		return false;

	while(b !is null) {
		if(a is b)
			return true;
		b = b.parent;
	}

	return false;
}

private struct WidgetAtPointResponse {
	Widget widget;
	int x;
	int y;
}

private WidgetAtPointResponse widgetAtPoint(Widget starting, int x, int y) {
	assert(starting !is null);
	auto child = starting.getChildAtPosition(x, y);
	while(child) {
		if(child.hidden)
			continue;
		starting = child;
		x -= child.x;
		y -= child.y;
		auto r = starting.widgetAtPoint(x, y);//starting.getChildAtPosition(x, y);
		child = r.widget;
		if(child is starting)
			break;
	}
	return WidgetAtPointResponse(starting, x, y);
}

version(win32_widgets) {
	import core.sys.windows.commctrl;

	pragma(lib, "comctl32");
	shared static this() {
		// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775507(v=vs.85).aspx
		INITCOMMONCONTROLSEX ic;
		ic.dwSize = cast(DWORD) ic.sizeof;
		ic.dwICC = ICC_UPDOWN_CLASS | ICC_WIN95_CLASSES | ICC_BAR_CLASSES | ICC_PROGRESS_CLASS | ICC_COOL_CLASSES | ICC_STANDARD_CLASSES | ICC_USEREX_CLASSES;
		if(!InitCommonControlsEx(&ic)) {
			//import std.stdio; writeln("ICC failed");
		}
	}


	// everything from here is just win32 headers copy pasta
private:
extern(Windows):

	alias HANDLE HMENU;
	HMENU CreateMenu();
	bool SetMenu(HWND, HMENU);
	HMENU CreatePopupMenu();
	enum MF_POPUP = 0x10;
	enum MF_STRING = 0;


	BOOL InitCommonControlsEx(const INITCOMMONCONTROLSEX*);
	struct INITCOMMONCONTROLSEX {
		DWORD dwSize;
		DWORD dwICC;
	}
	enum HINST_COMMCTRL = cast(HINSTANCE) (-1);
enum {
        IDB_STD_SMALL_COLOR,
        IDB_STD_LARGE_COLOR,
        IDB_VIEW_SMALL_COLOR = 4,
        IDB_VIEW_LARGE_COLOR = 5
}
enum {
        STD_CUT,
        STD_COPY,
        STD_PASTE,
        STD_UNDO,
        STD_REDOW,
        STD_DELETE,
        STD_FILENEW,
        STD_FILEOPEN,
        STD_FILESAVE,
        STD_PRINTPRE,
        STD_PROPERTIES,
        STD_HELP,
        STD_FIND,
        STD_REPLACE,
        STD_PRINT // = 14
}

alias HANDLE HIMAGELIST;
	HIMAGELIST ImageList_Create(int, int, UINT, int, int);
	int ImageList_Add(HIMAGELIST, HBITMAP, HBITMAP);
        BOOL ImageList_Destroy(HIMAGELIST);

uint MAKELONG(ushort a, ushort b) {
        return cast(uint) ((b << 16) | a);
}


struct TBBUTTON {
	int   iBitmap;
	int   idCommand;
	BYTE  fsState;
	BYTE  fsStyle;
	BYTE[2]  bReserved; // FIXME: isn't that different on 64 bit?
	DWORD dwData;
	int   iString;
}

	enum {
		TB_ADDBUTTONSA   = WM_USER + 20,
		TB_INSERTBUTTONA = WM_USER + 21,
		TB_GETIDEALSIZE = WM_USER + 99,
	}

struct SIZE {
	LONG cx;
	LONG cy;
}


enum {
	TBSTATE_CHECKED       = 1,
	TBSTATE_PRESSED       = 2,
	TBSTATE_ENABLED       = 4,
	TBSTATE_HIDDEN        = 8,
	TBSTATE_INDETERMINATE = 16,
	TBSTATE_WRAP          = 32
}



enum {
	ILC_COLOR    = 0,
	ILC_COLOR4   = 4,
	ILC_COLOR8   = 8,
	ILC_COLOR16  = 16,
	ILC_COLOR24  = 24,
	ILC_COLOR32  = 32,
	ILC_COLORDDB = 254,
	ILC_MASK     = 1,
	ILC_PALETTE  = 2048
}


alias TBBUTTON*       PTBBUTTON, LPTBBUTTON;


enum {
	TB_ENABLEBUTTON          = WM_USER + 1,
	TB_CHECKBUTTON,
	TB_PRESSBUTTON,
	TB_HIDEBUTTON,
	TB_INDETERMINATE, //     = WM_USER + 5,
	TB_ISBUTTONENABLED       = WM_USER + 9,
	TB_ISBUTTONCHECKED,
	TB_ISBUTTONPRESSED,
	TB_ISBUTTONHIDDEN,
	TB_ISBUTTONINDETERMINATE, // = WM_USER + 13,
	TB_SETSTATE              = WM_USER + 17,
	TB_GETSTATE              = WM_USER + 18,
	TB_ADDBITMAP             = WM_USER + 19,
	TB_DELETEBUTTON          = WM_USER + 22,
	TB_GETBUTTON,
	TB_BUTTONCOUNT,
	TB_COMMANDTOINDEX,
	TB_SAVERESTOREA,
	TB_CUSTOMIZE,
	TB_ADDSTRINGA,
	TB_GETITEMRECT,
	TB_BUTTONSTRUCTSIZE,
	TB_SETBUTTONSIZE,
	TB_SETBITMAPSIZE,
	TB_AUTOSIZE, //          = WM_USER + 33,
	TB_GETTOOLTIPS           = WM_USER + 35,
	TB_SETTOOLTIPS           = WM_USER + 36,
	TB_SETPARENT             = WM_USER + 37,
	TB_SETROWS               = WM_USER + 39,
	TB_GETROWS,
	TB_GETBITMAPFLAGS,
	TB_SETCMDID,
	TB_CHANGEBITMAP,
	TB_GETBITMAP,
	TB_GETBUTTONTEXTA,
	TB_REPLACEBITMAP, //     = WM_USER + 46,
	TB_GETBUTTONSIZE         = WM_USER + 58,
	TB_SETBUTTONWIDTH        = WM_USER + 59,
	TB_GETBUTTONTEXTW        = WM_USER + 75,
	TB_SAVERESTOREW          = WM_USER + 76,
	TB_ADDSTRINGW            = WM_USER + 77,
}

extern(Windows)
BOOL EnumChildWindows(HWND, WNDENUMPROC, LPARAM);

alias extern(Windows) BOOL function (HWND, LPARAM) WNDENUMPROC;


	enum {
		TB_SETINDENT = WM_USER + 47,
		TB_SETIMAGELIST,
		TB_GETIMAGELIST,
		TB_LOADIMAGES,
		TB_GETRECT,
		TB_SETHOTIMAGELIST,
		TB_GETHOTIMAGELIST,
		TB_SETDISABLEDIMAGELIST,
		TB_GETDISABLEDIMAGELIST,
		TB_SETSTYLE,
		TB_GETSTYLE,
		//TB_GETBUTTONSIZE,
		//TB_SETBUTTONWIDTH,
		TB_SETMAXTEXTROWS,
		TB_GETTEXTROWS // = WM_USER + 61
	}

enum {
	CCM_FIRST            = 0x2000,
	CCM_LAST             = CCM_FIRST + 0x200,
	CCM_SETBKCOLOR       = 8193,
	CCM_SETCOLORSCHEME   = 8194,
	CCM_GETCOLORSCHEME   = 8195,
	CCM_GETDROPTARGET    = 8196,
	CCM_SETUNICODEFORMAT = 8197,
	CCM_GETUNICODEFORMAT = 8198,
	CCM_SETVERSION       = 0x2007,
	CCM_GETVERSION       = 0x2008,
	CCM_SETNOTIFYWINDOW  = 0x2009
}


enum {
	PBM_SETRANGE     = WM_USER + 1,
	PBM_SETPOS,
	PBM_DELTAPOS,
	PBM_SETSTEP,
	PBM_STEPIT,   // = WM_USER + 5
	PBM_SETRANGE32   = 1030,
	PBM_GETRANGE,
	PBM_GETPOS,
	PBM_SETBARCOLOR, // = 1033
	PBM_SETBKCOLOR   = CCM_SETBKCOLOR
}

enum {
	PBS_SMOOTH   = 1,
	PBS_VERTICAL = 4
}

enum {
        ICC_LISTVIEW_CLASSES = 1,
        ICC_TREEVIEW_CLASSES = 2,
        ICC_BAR_CLASSES      = 4,
        ICC_TAB_CLASSES      = 8,
        ICC_UPDOWN_CLASS     = 16,
        ICC_PROGRESS_CLASS   = 32,
        ICC_HOTKEY_CLASS     = 64,
        ICC_ANIMATE_CLASS    = 128,
        ICC_WIN95_CLASSES    = 255,
        ICC_DATE_CLASSES     = 256,
        ICC_USEREX_CLASSES   = 512,
        ICC_COOL_CLASSES     = 1024,
	ICC_STANDARD_CLASSES = 0x00004000,
}

	enum WM_USER = 1024;
}

version(win32_widgets)
	pragma(lib, "comdlg32");


///
enum GenericIcons : ushort {
	None, ///
	// these happen to match the win32 std icons numerically if you just subtract one from the value
	Cut, ///
	Copy, ///
	Paste, ///
	Undo, ///
	Redo, ///
	Delete, ///
	New, ///
	Open, ///
	Save, ///
	PrintPreview, ///
	Properties, ///
	Help, ///
	Find, ///
	Replace, ///
	Print, ///
}

///
void getOpenFileName(
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null
)
{
	return getFileName(true, onOK, prefilledName, filters);
}

///
void getSaveFileName(
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null
)
{
	return getFileName(false, onOK, prefilledName, filters);
}

void getFileName(
	bool openOrSave,
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null,
)
{

	version(win32_widgets) {
		import core.sys.windows.commdlg;
	/*
	Ofn.lStructSize = sizeof(OPENFILENAME); 
	Ofn.hwndOwner = hWnd; 
	Ofn.lpstrFilter = szFilter; 
	Ofn.lpstrFile= szFile; 
	Ofn.nMaxFile = sizeof(szFile)/ sizeof(*szFile); 
	Ofn.lpstrFileTitle = szFileTitle; 
	Ofn.nMaxFileTitle = sizeof(szFileTitle); 
	Ofn.lpstrInitialDir = (LPSTR)NULL; 
	Ofn.Flags = OFN_SHOWHELP | OFN_OVERWRITEPROMPT; 
	Ofn.lpstrTitle = szTitle; 
	 */


		wchar[1024] file = 0;
		makeWindowsString(prefilledName, file[]);
		OPENFILENAME ofn;
		ofn.lStructSize = ofn.sizeof;
		ofn.lpstrFile = file.ptr;
		ofn.nMaxFile = file.length;
		if(openOrSave ? GetOpenFileName(&ofn) : GetSaveFileName(&ofn)) {
			onOK(makeUtf8StringFromWindowsString(ofn.lpstrFile));
		}
	} else version(custom_widgets) {
		auto picker = new FilePicker(prefilledName);
		picker.onOK = onOK;
		picker.show();
	}
}

version(custom_widgets)
private
class FilePicker : Dialog {
	void delegate(string) onOK;
	LineEdit lineEdit;
	this(string prefilledName, Window owner = null) {
		super(300, 200, "Choose File..."); // owner);

		auto listWidget = new ListWidget(this);

		lineEdit = new LineEdit(this);
		lineEdit.focus();
		lineEdit.addEventListener("char", (Event event) {
			if(event.character == '\t' || event.character == '\n')
				event.preventDefault();
		});

		listWidget.addEventListener(EventType.change, () {
			foreach(o; listWidget.options)
				if(o.selected)
					lineEdit.content = o.label;
		});

		//version(none)
		lineEdit.addEventListener(EventType.keydown, (Event event) {
			if(event.key == Key.Tab) {
				listWidget.clear();

				string commonPrefix;
				auto cnt = lineEdit.content;
				if(cnt.length >= 2 && cnt[0 ..2] == "./")
					cnt = cnt[2 .. $];

				version(Windows) {
					WIN32_FIND_DATA data;
					WCharzBuffer search = WCharzBuffer("./" ~ cnt ~ "*");
					auto handle = FindFirstFileW(search.ptr, &data);
					scope(exit) if(handle !is INVALID_HANDLE_VALUE) FindClose(handle);
					if(handle is INVALID_HANDLE_VALUE) {
						if(GetLastError() == ERROR_FILE_NOT_FOUND)
							goto file_not_found;
						throw new WindowsApiException("FindFirstFileW");
					}
				} else version(Posix) {
					import core.sys.posix.dirent;
					auto dir = opendir(".");
					scope(exit)
						if(dir) closedir(dir);
					if(dir is null)
						throw new ErrnoApiException("opendir");

					auto dirent = readdir(dir);
					if(dirent is null)
						goto file_not_found;
					// filter those that don't start with it, since posix doesn't
					// do the * thing itself
					while(dirent.d_name[0 .. cnt.length] != cnt[]) {
						dirent = readdir(dir);
						if(dirent is null)
							goto file_not_found;
					}
				} else static assert(0);

				while(true) {
				//foreach(string name; dirEntries(".", cnt ~ "*", SpanMode.shallow)) {
					version(Windows) {
						string name = makeUtf8StringFromWindowsString(data.cFileName[0 .. findIndexOfZero(data.cFileName[])]);
					} else version(Posix) {
						string name = dirent.d_name[0 .. findIndexOfZero(dirent.d_name[])].idup;
					} else static assert(0);


					listWidget.addOption(name);
					if(commonPrefix is null)
						commonPrefix = name;
					else {
						foreach(idx, char i; name) {
							if(idx >= commonPrefix.length || i != commonPrefix[idx]) {
								commonPrefix = commonPrefix[0 .. idx];
								break;
							}
						}
					}

					version(Windows) {
						auto ret = FindNextFileW(handle, &data);
						if(ret == 0) {
							if(GetLastError() == ERROR_NO_MORE_FILES)
								break;
							throw new WindowsApiException("FindNextFileW");
						}
					} else version(Posix) {
						dirent = readdir(dir);
						if(dirent is null)
							break;

						while(dirent.d_name[0 .. cnt.length] != cnt[]) {
							dirent = readdir(dir);
							if(dirent is null)
								break;
						}

						if(dirent is null)
							break;
					} else static assert(0);
				}
				if(commonPrefix.length)
					lineEdit.content = commonPrefix;

				file_not_found:
				event.preventDefault();
			}
		});

		lineEdit.content = prefilledName;

		auto hl = new HorizontalLayout(this);
		auto cancelButton = new Button("Cancel", hl);
		auto okButton = new Button("OK", hl);

		recomputeChildLayout(); // FIXME hack

		cancelButton.addEventListener(EventType.triggered, &Cancel);
		okButton.addEventListener(EventType.triggered, &OK);

		this.addEventListener("keydown", (Event event) {
			if(event.key == Key.Enter || event.key == Key.PadEnter) {
				event.preventDefault();
				OK();
			}
			if(event.key == Key.Escape)
				Cancel();
		});

	}

	override void OK() {
		if(onOK)
			onOK(lineEdit.content);
		close();
	}
}

/*
http://msdn.microsoft.com/en-us/library/windows/desktop/bb775947%28v=vs.85%29.aspx#check_boxes
http://msdn.microsoft.com/en-us/library/windows/desktop/ms633574%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb775943%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb775951%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms632680%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms644996%28v=vs.85%29.aspx#message_box
http://www.sbin.org/doc/Xlib/chapt_03.html

http://msdn.microsoft.com/en-us/library/windows/desktop/bb760433%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb760446%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb760443%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb760476%28v=vs.85%29.aspx
*/


// These are all for setMenuAndToolbarFromAnnotatedCode
/// This item in the menu will be preceded by a separator line
/// Group: generating_from_code
struct separator {}
deprecated("It was misspelled, use separator instead") alias seperator = separator;
/// Program-wide keyboard shortcut to trigger the action
/// Group: generating_from_code
struct accelerator { string keyString; }
/// tells which menu the action will be on
/// Group: generating_from_code
struct menu { string name; }
/// Describes which toolbar section the action appears on
/// Group: generating_from_code
struct toolbar { string groupName; }
///
/// Group: generating_from_code
struct icon { ushort id; }
///
/// Group: generating_from_code
struct label { string label; }


/++
	Observes and allows inspection of an object via automatic gui
+/
/// Group: generating_from_code
ObjectInspectionWindow objectInspectionWindow(T)(T t) if(is(T == class)) {
	return new ObjectInspectionWindowImpl!(T)(t);
}

class ObjectInspectionWindow : Window {
	this(int a, int b, string c) {
		super(a, b, c);
	}

	abstract void readUpdatesFromObject();
}

class ObjectInspectionWindowImpl(T) : ObjectInspectionWindow {
	T t;
	this(T t) {
		this.t = t;

		super(300, 400, "ObjectInspectionWindow - " ~ T.stringof);

		static foreach(memberName; __traits(derivedMembers, T)) {{
			alias member = I!(__traits(getMember, t, memberName))[0];
			alias type = typeof(member);
			static if(is(type == int)) {
				auto le = new LabeledLineEdit(memberName ~ ": ", this);
				le.addEventListener("char", (Event ev) {
					if((ev.character < '0' || ev.character > '9') && ev.character != '-')
						ev.preventDefault();
				});
				le.addEventListener(EventType.change, (Event ev) {
					__traits(getMember, t, memberName) = cast(type) stringToLong(ev.stringValue);
				});

				updateMemberDelegates[memberName] = () {
					le.content = toInternal!string(__traits(getMember, t, memberName));
				};
			}
		}}
	}

	void delegate()[string] updateMemberDelegates;

	override void readUpdatesFromObject() {
		foreach(k, v; updateMemberDelegates)
			v();
	}
};

/++
	Creates a dialog based on a data structure.

	---
	dialog((YourStructure value) {
		// the user filled in the struct and clicked OK,
		// you can check the members now
	});
	---
+/
/// Group: generating_from_code
void dialog(T)(void delegate(T) onOK, void delegate() onCancel = null) {
	auto dg = new AutomaticDialog!T(onOK, onCancel);
	dg.show();
}

private static template I(T...) { alias I = T; }

class AutomaticDialog(T) : Dialog {
	T t;

	void delegate(T) onOK;
	void delegate() onCancel;

	override int paddingTop() { return Window.lineHeight; }
	override int paddingBottom() { return Window.lineHeight; }
	override int paddingRight() { return Window.lineHeight; }
	override int paddingLeft() { return Window.lineHeight; }

	this(void delegate(T) onOK, void delegate() onCancel) {
		static if(is(T == class))
			t = new T();
		this.onOK = onOK;
		this.onCancel = onCancel;
		super(400, cast(int)(__traits(allMembers, T).length + 5) * Window.lineHeight, T.stringof);

		foreach(memberName; __traits(allMembers, T)) {
			alias member = I!(__traits(getMember, t, memberName))[0];
			alias type = typeof(member);
			static if(is(type == string)) {
				auto show = memberName;
				// cheap capitalize lol
				if(show[0] >= 'a' && show[0] <= 'z')
					show = "" ~ cast(char)(show[0] - 32) ~ show[1 .. $];
				auto le = new LabeledLineEdit(show ~ ": ", this);
				le.addEventListener(EventType.change, (Event ev) {
					__traits(getMember, t, memberName) = ev.stringValue;
				});
			} else static if(is(type : long)) {
				auto le = new LabeledLineEdit(memberName ~ ": ", this);
				le.addEventListener("char", (Event ev) {
					if((ev.character < '0' || ev.character > '9') && ev.character != '-')
						ev.preventDefault();
				});
				le.addEventListener(EventType.change, (Event ev) {
					__traits(getMember, t, memberName) = cast(type) stringToLong(ev.stringValue);
				});
			}
		}

		auto hl = new HorizontalLayout(this);
		auto stretch = new HorizontalSpacer(hl); // to right align
		auto ok = new CommandButton("OK", hl);
		auto cancel = new CommandButton("Cancel", hl);
		ok.addEventListener(EventType.triggered, &OK);
		cancel.addEventListener(EventType.triggered, &Cancel);

		this.addEventListener(EventType.keydown, (Event ev) {
			if(ev.key == Key.Enter || ev.key == Key.PadEnter) {
				ok.focus();
				OK();
				ev.preventDefault();
			}
			if(ev.key == Key.Escape) {
				Cancel();
				ev.preventDefault();
			}
		});

		this.children[0].focus();
	}

	override void OK() {
		onOK(t);
		close();
	}

	override void Cancel() {
		if(onCancel)
			onCancel();
		close();
	}
}

private long stringToLong(string s) {
	long ret;
	if(s.length == 0)
		return ret;
	bool negative = s[0] == '-';
	if(negative)
		s = s[1 .. $];
	foreach(ch; s) {
		if(ch >= '0' && ch <= '9') {
			ret *= 10;
			ret += ch - '0';
		}
	}
	if(negative)
		ret = -ret;
	return ret;
}
