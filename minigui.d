// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775498%28v=vs.85%29.aspx

/*
	TODO:

	scrolling
	event cleanup
	ScreenPainter dtor stuff. clipping api.
	Windows radio button sizing and theme text selection
	tooltips.
	api improvements

	margins are kinda broken, they don't collapse like they should. at least.
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
+/
module arsd.minigui;

public import arsd.simpledisplay;

version(Windows)
	import core.sys.windows.windows;

// this is a hack to call the original window procedure on native win32 widgets if our event listener thing prevents default.
private bool lastDefaultPrevented;

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
			parentWindow = parent.parentWindow;
			createWin32Window(this, "ComboBox", null, style);
		}
	else version(custom_widgets)
		this(Widget parent = null) {
			super(parent);

			addEventListener("keydown", (Event event) {
				if(event.key == Key.Up) {
					if(selection > -1) { // -1 means select blank
						selection--;
						auto t = new Event(EventType.change, this);
						t.dispatch();
					}
					event.preventDefault();
				}
				if(event.key == Key.Down) {
					if(selection + 1 < options.length) {
						selection++;
						auto t = new Event(EventType.change, this);
						t.dispatch();
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
		SendMessageA(hwnd, 323 /*CB_ADDSTRING*/, 0, cast(LPARAM) toStringzInternal(s));
	}

	void setSelection(int idx) {
		selection = idx;
		version(win32_widgets)
		SendMessageA(hwnd, 334 /*CB_SETCURSEL*/, idx, 0);

		auto t = new Event(EventType.change, this);
		t.dispatch();
	}

	version(win32_widgets)
	override void handleWmCommand(ushort cmd, ushort id) {
		selection = SendMessageA(hwnd, 327 /* CB_GETCURSEL */, 0, 0);
		auto event = new Event(EventType.change, this);
		event.dispatch();
	}

	override int minHeight() { return Window.lineHeight * 4 / 3; }
	override int maxHeight() { return Window.lineHeight * 4 / 3; }

	version(custom_widgets) {
		SimpleWindow dropDown;
		void popup() {
			auto w = width;
			auto h = this.options.length * Window.lineHeight + 8;

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

							auto t = new Event(EventType.change, this);
							t.dispatch();
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
			paint = delegate(ScreenPainter painter) {
				draw3dFrame(this, painter, FrameStyle.risen);
				painter.outlineColor = Color.black;
				painter.drawText(Point(4, 4), selection == -1 ? "" : options[selection]);

				painter.outlineColor = Color.black;
				painter.fillColor = Color.black;
				Point[3] triangle;
				enum padding = 6;
				enum paddingV = 8;
				enum triangleWidth = 10;
				triangle[0] = Point(width - padding - triangleWidth, paddingV);
				triangle[1] = Point(width - padding - triangleWidth / 2, height - paddingV);
				triangle[2] = Point(width - padding - 0, paddingV);
				painter.drawPolygon(triangle[]);

				if(isFocused()) {
					painter.fillColor = Color.transparent;
					painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
					painter.drawRectangle(Point(2, 2), width - 4, height - 4);
					painter.pen = Pen(Color.black, 1, Pen.Style.Solid);

				}

			};

			addEventListener("focus", &this.redraw);
			addEventListener("blur", &this.redraw);
			addEventListener(EventType.change, &this.redraw);
			addEventListener("mousedown", () { this.focus(); this.popup(); });
			addEventListener("keydown", (Event event) {
				if(event.key == Key.Space)
					popup();
			});
		} else static assert(false);
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
			addEventListener(EventType.change, {
				lineEdit.content = (selection == -1 ? "" : options[selection]);
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
	override int heightStretchiness() { return 2; }

	version(custom_widgets) {
		LineEdit lineEdit;
		ListWidget listWidget;

		override void addOption(string s) {
			listWidget.options ~= ListWidget.Option(s);
			ComboboxBase.addOption(s);
		}
	}
}

/++

+/
version(custom_widgets)
class ListWidget : Widget {

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

	this(Widget parent = null) {
		super(parent);

		defaultEventHandlers["click"] = delegate(Widget _this, Event event) {
			this.focus();
			auto y = (event.clientY - 4) / Window.lineHeight;
			if(y >= 0 && y < options.length) {
				setSelection(y);
			}
		};

		paint = delegate(ScreenPainter painter) {
			draw3dFrame(this, painter, FrameStyle.sunk, Color.white);

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
					painter.fillColor = Color(255, 255, 0);
					painter.drawRectangle(pos, width - 8, Window.lineHeight);
					painter.rasterOp = RasterOp.normal;
				}
				pos.y += Window.lineHeight;
			}
		};
	}

	Option[] options;
	bool multiSelect;
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
		createWin32Window(this, "msctls_updown32", null, 4/*UDS_ALIGNRIGHT*/| 2 /* UDS_SETBUDDYINT */ | 16 /* UDS_AUTOBUDDY */ | 32 /* UDS_ARROWKEYS */);
	}

	override int minHeight() { return Window.lineHeight; }
	override int maxHeight() { return Window.lineHeight * 3/2; }

	override int minWidth() { return Window.lineHeight * 3/2; }
	override int maxWidth() { return Window.lineHeight * 3/2; }
}
+/

class DataView : Widget {
	// this is the omnibus data viewer
	// the internal data layout is something like:
	// string[string][] but also each node can have parents
}


// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775491(v=vs.85).aspx#PROGRESS_CLASS

// http://svn.dsource.org/projects/bindings/trunk/win32/commctrl.d

// FIXME: menus should prolly capture the mouse. ugh i kno.
/*
	TextEdit needs:

	* carat manipulation
	* selection control
	* convenience functions for appendText, insertText, insertTextAtCarat, etc.

	For example:

	connect(paste, &textEdit.insertTextAtCarat);

	would be nice.



	I kinda want an omnibus dataview that combines list, tree,
	and table - it can be switched dynamically between them.

	Flattening policy: only show top level, show recursive, show grouped
	List styles: plain list (e.g. <ul>), tiles (some details next to it), icons (like Windows explorer)

	Single select, multi select, organization, drag+drop
*/

//static if(UsingSimpledisplayX11)
version(win32_widgets) {}
else version(custom_widgets)
	enum windowBackgroundColor = Color(192, 192, 192);
else static assert(false);

private const(char)* toStringzInternal(string s) { return (s ~ '\0').ptr; }
private const(wchar)* toWstringzInternal(in char[] s) {
	wchar[] str;
	str.reserve(s.length + 1);
	foreach(dchar ch; s)
		str ~= ch;
	str ~= '\0';
	return str.ptr;
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

	painter.outlineColor = (style == FrameStyle.sunk) ? Color(128, 128, 128) : Color(223, 223, 223);
	painter.drawLine(Point(x + 0, y + 0), Point(x + width, y + 0));
	painter.drawLine(Point(x + 0, y + 0), Point(x + 0, y + height - 1));

	// inner layer
	//right, bottom
	painter.outlineColor = (style == FrameStyle.sunk) ? Color(223, 223, 223) : Color(128, 128, 128);
	painter.drawLine(Point(x + width - 2, y + 2), Point(x + width - 2, y + height - 2));
	painter.drawLine(Point(x + 2, y + height - 2), Point(x + width - 2, y + height - 2));
	// left, top
	painter.outlineColor = (style == FrameStyle.sunk) ? Color.black : Color.white;
	painter.drawLine(Point(x + 1, y + 1), Point(x + width - 2, y + 1));
	painter.drawLine(Point(x + 1, y + 1), Point(x + 1, y + height - 2));
}

///
class Action {
	version(win32_widgets) {
		int id;
		static int lastId = 9000;
		static Action[int] mapping;
	}

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

	string label;
	ushort iconId;
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
	window.menu = bar;

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
	int widthStretchiness() { return 1; }
	int heightStretchiness() { return 1; }

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
		stretchinessSum += mixin("child." ~ relevantMeasure ~ "Stretchiness()");
	}

	// stretch to fill space
	while(spaceRemaining > 0 && stretchinessSum) {
		//import std.stdio; writeln("str ", stretchinessSum);
		auto spacePerChild = spaceRemaining / stretchinessSum;
		if(spacePerChild <= 0)
			break;
		int previousSpaceRemaining = spaceRemaining;
		stretchinessSum = 0;
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
			auto spaceAdjustment = spacePerChild * mixin("child." ~ relevantMeasure ~ "Stretchiness()");
			mixin("child." ~ relevantMeasure) += spaceAdjustment;
			spaceRemaining -= spaceAdjustment;
			if(mixin("child." ~ relevantMeasure) > maximum) {
				auto diff = mixin("child." ~ relevantMeasure) - maximum;
				mixin("child." ~ relevantMeasure) -= diff;
				spaceRemaining += diff;
			} else if(mixin("child." ~ relevantMeasure) < maximum) {
				stretchinessSum += mixin("child." ~ relevantMeasure ~ "Stretchiness()");
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

/+
mixin template StyleInfo(string windowType) {
	version(win32_theming)
		HTHEME theme;
	/* ok we need to:
		open theme
		close theme (when it is all done)
		draw background
		get font
		respond to theme changed messages
	*/
}
+/

// OK so we need to make getting at the native window stuff possible in simpledisplay.d
// and here, it must be integrable with the layout, the event system, and not be painted over.
version(win32_widgets) {
	extern(Windows)
	int HookedWndProc(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) nothrow {
		//import std.stdio; try { writeln(iMessage); } catch(Exception e) {};
		if(auto te = hWnd in Widget.nativeMapping) {
			try {
				if(iMessage == WM_SETFOCUS) {
					auto lol = *te;
					while(lol !is null && lol.implicitlyCreated)
						lol = lol.parent;
					lol.focus();
					//(*te).parentWindow.focusedWidget = lol;
				}



				if(iMessage == WM_CTLCOLORBTN || iMessage == WM_CTLCOLORSTATIC) {
					SetBkMode(cast(HDC) wParam, TRANSPARENT);
					return cast(typeof(return)) 
						//GetStockObject(NULL_BRUSH);
						// this is the window background color...
						GetSysColorBrush(COLOR_3DFACE);
				}


				auto pos = getChildPositionRelativeToParentOrigin(*te);
				lastDefaultPrevented = false;
				// try {import std.stdio; writeln(typeid(*te)); } catch(Exception e) {}
				if(SimpleWindow.triggerEvents(hWnd, iMessage, wParam, lParam, pos[0], pos[1], (*te).parentWindow.win) || !lastDefaultPrevented)
					return CallWindowProcW((*te).originalWindowProcedure, hWnd, iMessage, wParam, lParam);
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

	void createWin32Window(Widget p, string className, string windowText, DWORD style, DWORD extStyle = 0) {
		assert(p.parentWindow !is null);
		assert(p.parentWindow.win.impl.hwnd !is null);

		HWND phwnd;
		if(p.parent !is null && p.parent.hwnd !is null)
			phwnd = p.parent.hwnd;
		else
			phwnd = p.parentWindow.win.impl.hwnd;

		assert(phwnd !is null);

		style |= WS_VISIBLE | WS_CHILD;
		p.hwnd = CreateWindowExA(extStyle, toStringzInternal(className), toStringzInternal(windowText), style,
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
	}
}

version(win32_widgets)
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
	from simpledisplay, OR Terminal from terminal to provide some
	simple controls and such.

	Non-native controls suck, but nevertheless, I'm going to do it that
	way to avoid dependencies on stuff like gtk on X... and since I'll
	be writing the widgets there, I might as well just use them on Windows
	too.

	So, by extension, this sucks. But gtkd is just too big for me.


	The goal is to look kinda like Windows 95, perhaps with customizability.
	Nothing too fancy, just the basics that work.
*/
class Widget {
	mixin EventStuff!();
	mixin LayoutInfo!();

	bool hidden_;
	bool hidden() { return hidden_; }
	void hidden(bool h) {
		auto o = hidden_;
		hidden_ = h;
		if(h && !o) {
			if(parent) {
				parent.recomputeChildLayout();
				parent.redraw();
			}
		}
	}

	static if(UsingSimpledisplayX11) {
		// see: http://tronche.com/gui/x/xlib/appendix/b/
		protected Cursor cursor;

		// maybe I can do something similar cross platform
	}

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

	string statusTip;
	// string toolTip;
	// string helpText;

	bool tabStop = true;
	int tabOrder;

	version(win32_widgets) {
		static Widget[HWND] nativeMapping;
		HWND hwnd;
		WNDPROC originalWindowProcedure;
	}
	bool implicitlyCreated;

	int x; // relative to the parent's origin
	int y; // relative to the parent's origin
	int width;
	int height;
	Widget[] children;
	Widget parent;

	void registerMovement() {
		version(win32_widgets) {
			if(hwnd) {
				auto pos = getChildPositionRelativeToParentHwnd(this);
				MoveWindow(hwnd, pos[0], pos[1], width, height, true);
			}
		}
	}

	Window parentWindow;

	this(Widget parent = null) {
		if(parent !is null)
			parent.addChild(this);
	}

	bool isFocused() {
		return parentWindow && parentWindow.focusedWidget is this;
	}

	bool showing = true;
	void show() { showing = true; redraw(); }
	void hide() { showing = false; }

	void delegate(MouseEvent) handleMouseEvent;
	void delegate(dchar) handleCharEvent;
	void delegate(KeyEvent) handleKeyEvent;

	bool dispatchMouseEvent(MouseEvent e) {
		return eventBase!(MouseEvent, "handleMouseEvent")(e);
	}
	bool dispatchKeyEvent(KeyEvent e) {
		return eventBase!(KeyEvent, "handleKeyEvent")(e);
	}
	bool dispatchCharEvent(dchar e) {
		return eventBase!(dchar, "handleCharEvent")(e);
	}

	private bool eventBase(EventType, string handler)(EventType e) {

		static if(is(EventType == MouseEvent)) {
		/*
			assert(e.x >= 0);
			assert(e.y >= 0);
			assert(e.x < width);
			assert(e.y < height);
		*/

			auto child = getChildAtPosition(e.x, e.y);
			if(child !is null) {
				e.x -= child.x;
				e.y -= child.y;
				if(mixin("child." ~ handler) !is null)
					mixin("child." ~ handler)(e);
				return true;
			}
		}

		if(mixin(handler) !is null) {
			mixin(handler)(e);
			return true;
		}

		return false;
	}


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

		if(parentWindow !is null) {
			w.attachedToWindow(parentWindow);
			parentWindow.recomputeChildLayout();
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

	void delegate(ScreenPainter painter) paint;

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

	protected void privatePaint(ScreenPainter painter, int lox, int loy) {
		if(hidden)
			return;

		painter.originX = lox + x;
		painter.originY = loy + y;

		painter.setClipRectangle(Point(0, 0), width, height);

		if(paint !is null)
			paint(painter);
		foreach(child; children)
			child.privatePaint(painter, painter.originX, painter.originY);
	}

	void redraw() {
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

/// For [ScrollableWidget], determines when to show the scroll bar to the user.
enum ScrollBarShowPolicy {
	automatic, /// automatically show the scroll bar if it is necessary
	never, /// never show the scroll bar (scrolling must be done programmatically)
	always /// always show the scroll bar, even if it is disabled
}

/++
+/
version(win32_widgets)
class ScrollableWidget : Widget { this(Widget parent = null) { super(parent); } } // TEMPORARY
else
class ScrollableWidget : Widget {
	this(Widget parent = null) {
		horizontalScrollbarHolder = new FixedPosition(this);
		verticalScrollbarHolder = new FixedPosition(this);
		horizontalScrollBar = new HorizontalScrollbar(horizontalScrollbarHolder);
		verticalScrollBar = new VerticalScrollbar(verticalScrollbarHolder);

		horizontalScrollbarHolder.hidden_ = true;
		verticalScrollbarHolder.hidden_ = true;

		super(parent);
	}

	FixedPosition horizontalScrollbarHolder;
	FixedPosition verticalScrollbarHolder;

	VerticalScrollbar verticalScrollBar;
	HorizontalScrollbar horizontalScrollBar;

	override void recomputeChildLayout() {
		bool both = showingVerticalScroll && showingHorizontalScroll;
		if(horizontalScrollbarHolder && verticalScrollbarHolder) {
			horizontalScrollbarHolder.width = this.width - (both ? 16 : 0);
			horizontalScrollbarHolder.height = 16;
			horizontalScrollbarHolder.x = 0;
			horizontalScrollbarHolder.y = this.height - 16;

			verticalScrollbarHolder.width = 16;
			verticalScrollbarHolder.height = this.height - (both ? 16 : 0);
			verticalScrollbarHolder.x = this.width - 16;
			verticalScrollbarHolder.y = 0;

			{
				int viewableScrollArea = viewportHeight;
				int totalScrollArea = contentHeight;
				int totalScrollBarArea = verticalScrollBar.thumb.height;
				int thumbSize;
				if(totalScrollArea)
					thumbSize = viewableScrollArea * totalScrollBarArea / totalScrollArea;
				else
					thumbSize = 0;
				if(thumbSize < 6)
					thumbSize = 6;

				verticalScrollBar.thumb.thumbHeight = thumbSize;
			}

			{
				int viewableScrollArea = viewportWidth;
				int totalScrollArea = contentWidth;
				int totalScrollBarArea = horizontalScrollBar.thumb.width;
				int thumbSize;
				if(totalScrollArea)
					thumbSize = viewableScrollArea * totalScrollBarArea / totalScrollArea;
				else
					thumbSize = 0;
				if(thumbSize < 6)
					thumbSize = 6;

				horizontalScrollBar.thumb.thumbWidth = thumbSize;
			}
		}


		super.recomputeChildLayout();
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

	@property int viewportWidth() {
		return width - (showingVerticalScroll ? 16 : 0);
	}
	@property int viewportHeight() {
		return height - (showingHorizontalScroll ? 16 : 0);
	}

	// FIXME property
	Point scrollOrigin;

	// the user sets these two
	private int contentWidth = 0;
	private int contentHeight = 0;

	void setContentSize(int width, int height) {
		contentWidth = width;
		contentHeight = height;

		if(showingVerticalScroll || showingHorizontalScroll) {
			recomputeChildLayout();
		}


		if(showingHorizontalScroll())
			horizontalScrollbarHolder.hidden = false;
		else
			horizontalScrollbarHolder.hidden = true;
		if(showingVerticalScroll())
			verticalScrollbarHolder.hidden = false;
		else
			verticalScrollbarHolder.hidden = true;

		if(showingVerticalScroll())
			verticalScrollBar.redraw();
		if(showingHorizontalScroll())
			horizontalScrollBar.redraw();

	}

	void verticalScroll(int delta) {
		verticalScrollTo(scrollOrigin.y + delta);
	}
	void verticalScrollTo(int pos) {
		scrollOrigin.y = pos;
		if(scrollOrigin.y + viewportHeight > contentHeight)
			scrollOrigin.y = contentHeight - viewportHeight;

		if(scrollOrigin.y < 0)
			scrollOrigin.y = 0;


		int viewableScrollArea = viewportHeight;
		int totalScrollArea = contentHeight;
		int totalScrollBarArea = verticalScrollBar.thumb.height;
		int thumbPosition = scrollOrigin.y * totalScrollBarArea / totalScrollArea;
		int thumbSize = viewableScrollArea * totalScrollBarArea / totalScrollArea;
		verticalScrollBar.thumb.positionY = thumbPosition;

		redraw();
	}

	void horizontalScroll(int delta) {
		horizontalScrollTo(scrollOrigin.x + delta);
	}
	void horizontalScrollTo(int pos) {
		scrollOrigin.x = pos;
		if(scrollOrigin.x + viewportWidth > contentWidth)
			scrollOrigin.x = contentWidth - viewportWidth;

		if(scrollOrigin.x < 0)
			scrollOrigin.x = 0;


		int viewableScrollArea = viewportWidth;
		int totalScrollArea = contentWidth;
		int totalScrollBarArea = horizontalScrollBar.thumb.width;
		int thumbPosition = scrollOrigin.x * totalScrollBarArea / totalScrollArea;
		int thumbSize = viewableScrollArea * totalScrollBarArea / totalScrollArea;
		horizontalScrollBar.thumb.positionX = thumbPosition;

		redraw();
	}
	void scrollTo(Point p) {
		verticalScrollTo(p.y);
		horizontalScrollTo(p.x);
	}

	bool showingHorizontalScroll() {
		return contentWidth > width;
	}
	bool showingVerticalScroll() {
		return contentHeight > height;
	}

	/// This is called before the ordinary paint delegate,
	/// giving you a chance to draw the window frame, etc,
	/// before the scroll clip takes effect
	void paintFrameAndBackground(ScreenPainter painter) {}

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

		painter.originX -= scrollOrigin.x;
		painter.originY -= scrollOrigin.y;
		painter.setClipRectangle(scrollOrigin, viewportWidth(), viewportHeight());

		return painter;
	}

	override protected void privatePaint(ScreenPainter painter, int lox, int loy) {
		if(hidden)
			return;
		painter.originX = lox + x;
		painter.originY = loy + y;

		painter.setClipRectangle(Point(0, 0), width, height);
		paintFrameAndBackground(painter);

		painter.originX -= scrollOrigin.x;
		painter.originY -= scrollOrigin.y;
		painter.setClipRectangle(scrollOrigin, viewportWidth(), viewportHeight());

		if(paint !is null)
			paint(painter);
		foreach(child; children) {
			if(cast(FixedPosition) child)
				child.privatePaint(painter, painter.originX + scrollOrigin.x, painter.originY + scrollOrigin.y);
			else
				child.privatePaint(painter, painter.originX, painter.originY);
		}
	}

}

///
abstract class ScrollbarBase : Widget {
	this(Widget parent = null) {
		super(parent);
		tabStop = false;
	}

	int viewableArea;
	int totalScrollableArea;
}

///
version(custom_widgets)
class HorizontalScrollbar : ScrollbarBase {

	MouseTrackingWidget thumb;

	this(Widget parent = null) {
		super(parent);
		// FIXME win32_widgets

		auto vl = new HorizontalLayout(this);
		auto leftButton = new ArrowButton(ArrowDirection.left, vl);
		thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.horizontal, vl);
		auto rightButton = new ArrowButton(ArrowDirection.right, vl);

		ScrollableWidget scrollableParent;
		Widget p = parent;
		while(p !is null) {
			if(auto sw = cast(ScrollableWidget) p) {
				scrollableParent = sw;
				break;
			}
			p = p.parent;
		}

		leftButton.addEventListener(EventType.triggered, () {
			if(scrollableParent)
				scrollableParent.horizontalScroll(-16);
		});
		rightButton.addEventListener(EventType.triggered, () {
			if(scrollableParent)
				scrollableParent.horizontalScroll(16);
		});

		thumb.thumbWidth = this.minWidth;
		thumb.thumbHeight = 16;

		thumb.addEventListener(EventType.change, () {
			int viewableScrollArea = scrollableParent.viewportWidth;
			int totalScrollArea = scrollableParent.contentWidth;
			int totalScrollBarArea = thumb.width;

			auto sx = thumb.positionX * totalScrollArea / totalScrollBarArea;

			scrollableParent.horizontalScrollTo(sx);
		});

	}

	override int minHeight() { return 16; }
	override int maxHeight() { return 16; }
	override int minWidth() { return 48; }
}

///show
version(custom_widgets)
class VerticalScrollbar : ScrollbarBase {

	MouseTrackingWidget thumb;

	this(Widget parent = null) {
		super(parent);
		// FIXME win32_widgets

		auto vl = new VerticalLayout(this);
		auto upButton = new ArrowButton(ArrowDirection.up, vl);
		thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.vertical, vl);
		auto downButton = new ArrowButton(ArrowDirection.down, vl);

		ScrollableWidget scrollableParent;
		Widget p = parent;
		while(p !is null) {
			if(auto sw = cast(ScrollableWidget) p) {
				scrollableParent = sw;
				break;
			}
			p = p.parent;
		}

		upButton.addEventListener(EventType.triggered, () {
			if(scrollableParent)
				scrollableParent.verticalScroll(-16);
		});
		downButton.addEventListener(EventType.triggered, () {
			if(scrollableParent)
				scrollableParent.verticalScroll(16);
		});

		thumb.thumbWidth = this.minWidth;
		thumb.thumbHeight = 16;

		thumb.addEventListener(EventType.change, () {
			int viewableScrollArea = scrollableParent.viewportHeight;
			int totalScrollArea = scrollableParent.contentHeight;
			int totalScrollBarArea = thumb.height;

			auto sy = thumb.positionY * totalScrollArea / totalScrollBarArea;

			scrollableParent.verticalScrollTo(sy);
		});

	}

	override int minWidth() { return 16; }
	override int maxWidth() { return 16; }
	override int minHeight() { return 48; }
}

/++
	A mouse tracking widget is one that follows the mouse when dragged inside it.

	Concrete subclasses may include a scrollbar thumb and a volume control.
+/
version(custom_widgets)
class MouseTrackingWidget : Widget {
	int mouseTrackerPosition;

	int positionX;
	int positionY;

	///
	enum Orientation {
		horizontal, ///
		vertical, ///
		twoDimensional, ///
	}

	int thumbWidth;
	int thumbHeight;

	this(Orientation orientation, Widget parent = null) {
		super(parent);

		//assert(parentWindow !is null);

		bool dragging;
		bool hovering;

		int startMouseX, startMouseY;

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

		this.paint = (ScreenPainter painter) {
			auto c = lighten(windowBackgroundColor, 0.2);
			painter.outlineColor = c;
			painter.fillColor = c;
			painter.drawRectangle(Point(0, 0), this.width, this.height);

			auto color = hovering ? Color(215, 215, 215) : windowBackgroundColor;
			draw3dFrame(positionX, positionY, thumbWidth, thumbHeight, painter, FrameStyle.risen, color);

		};
	}
}

///
abstract class Layout : Widget {
	this(Widget parent = null) {
		tabStop = false;
		super(parent);
		if(parent)
			this.parentWindow = parent.parentWindow;
	}
}

/++
	Makes all children minimum width and height, placing them down
	left to right, top to bottom.

	Useful if you want to make a list of buttons that automatically
	wrap to a new line when necessary.
+/
class InlineBlockLayout : Layout {
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

/// Stacks the widgets vertically, taking all the available width for each child.
class VerticalLayout : Layout {
	// intentionally blank - widget's default is vertical layout right now
	this(Widget parent = null) { super(parent); }
}

/// Stacks the widgets horizontally, taking all the available height for each child.
class HorizontalLayout : Layout {
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
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

}

/++
	Bypasses automatic layout for its children, using manual positioning and sizing only.
	While you need to manually position them, you must ensure they are inside the StaticLayout's
	bounding box to avoid undefined behavior.

	You should almost never use this.
+/
class StaticLayout : Layout {
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
	this(Widget parent = null) { super(parent); }
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

	static int lineHeight;

	Widget focusedWidget;

	SimpleWindow win;

	this(Widget p) {
		tabStop = false;
		super(p);
	}

	this(SimpleWindow win) {
		tabStop = false;
		super(null);
		this.win = win;

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

		bool skipNextChar = false;

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


		defaultEventHandlers["keydown"] = delegate void(Widget ignored, Event event) {
			Widget _this = event.target;

			if(event.key == Key.Tab) {
				/* Window tab ordering is a recursive thingy with each group */

				// FIXME inefficient
				Widget[] helper(Widget p) {
					if(p.hidden)
						return null;
					Widget[] childOrdering = p.children.dup;

					import std.algorithm;
					sort!((a, b) => a.tabOrder < b.tabOrder)(childOrdering);

					Widget[] ret;
					foreach(child; childOrdering) {
						if(child.tabStop && !child.hidden)
							ret ~= child;
						ret ~= helper(child);
					}

					return ret;
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
		};


		if(lineHeight == 0) {
			auto painter = win.draw();
			lineHeight = painter.fontHeight() * 5 / 4;
		}

		version(win32_widgets) {
			this.paint = (ScreenPainter painter) {
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
			};
		}
		else version(custom_widgets)
			this.paint = (ScreenPainter painter) {
				painter.fillColor = windowBackgroundColor;
				painter.outlineColor = windowBackgroundColor;
				painter.drawRectangle(Point(0, 0), this.width, this.height);
			};
		else static assert(false);
	}

	this(int width = 500, int height = 500, string title = null) {
		win = new SimpleWindow(width, height, title, OpenGlOptions.no, Resizability.allowResizing, WindowTypes.normal, WindowFlags.dontAutoShow);
		this(win);
	}

	void close() {
		win.close();
	}

	override bool dispatchKeyEvent(KeyEvent ev) {
		if(focusedWidget) {
			auto event = new Event(ev.pressed ? "keydown" : "keyup", focusedWidget);
			event.character = ev.character;
			event.key = ev.key;
			event.state = ev.modifierState;
			event.shiftKey = (ev.modifierState & ModifierState.shift) ? true : false;
			event.dispatch();
		}
		return super.dispatchKeyEvent(ev);
	}

	override bool dispatchCharEvent(dchar ch) {
		if(focusedWidget) {
			auto event = new Event("char", focusedWidget);
			event.character = ch;
			event.dispatch();
		}
		return super.dispatchCharEvent(ch);
	}

	Widget mouseLastOver;
	Widget mouseLastDownOn;
	override bool dispatchMouseEvent(MouseEvent ev) {
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
			event.state = ev.modifierState;
			event.clientX = eleR.x;
			event.clientY = eleR.y;
			event.dispatch();
		} else if(ev.type == 2) {
			auto event = new Event("mouseup", ele);
			event.button = ev.button;
			event.clientX = eleR.x;
			event.clientY = eleR.y;
			event.state = ev.modifierState;
			event.dispatch();
			if(mouseLastDownOn is ele) {
				event = new Event("click", ele);
				event.clientX = eleR.x;
				event.clientY = eleR.y;
				event.button = ev.button;
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

						static if(UsingSimpledisplayX11)
							XDefineCursor(XDisplayConnection.get(), ele.parentWindow.win.impl.window, ele.cursor);
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

		return super.dispatchMouseEvent(ev);
	}

	void loop() {
		recomputeChildLayout();
		focusedWidget = getFirstFocusable(this); // FIXME: autofocus?
		win.show();
		redraw();
		win.eventLoop(0);
	}

	override void show() {
		win.show();
		super.show();
	}
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

	string content() {
		return lineEdit.content;
	}
	void content(string c) {
		return lineEdit.content(c);
	}
}

///
class MainWindow : Window {
	this(string title = null) {
		super(500, 500, title);

		defaultEventHandlers["mouseover"] = delegate void(Widget _this, Event event) {
			if(this.statusBar !is null && event.target.statusTip.length)
				this.statusBar.parts[0].content = event.target.statusTip;
			else if(this.statusBar !is null && _this.statusTip.length)
				this.statusBar.parts[0].content = _this.statusTip; // ~ " " ~ event.target.toString();
		};

		_clientArea = new ClientAreaWidget();
		_clientArea.x = 0;
		_clientArea.y = 0;
		_clientArea.width = this.width;
		_clientArea.height = this.height;
		_clientArea.tabStop = false;

		super.addChild(_clientArea);

		statusBar = new StatusBar(this);
	}

	override void addChild(Widget c, int position = int.max) {
		clientArea.addChild(c, position);
	}

	MenuBar _menu;
	MenuBar menu() { return _menu; }
	MenuBar menu(MenuBar m) {
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
	@property Widget clientArea() { return _clientArea; }
	@property void clientArea(Widget wid) {
		_clientArea = wid;
	}

	private StatusBar _statusBar;
	@property StatusBar statusBar() { return _statusBar; }
	@property void statusBar(StatusBar bar) {
		_statusBar = bar;
		super.addChild(_statusBar);
	}

	@property string title() { return parentWindow.win.title; }
	@property void title(string title) { parentWindow.win.title = title; }
}

class ClientAreaWidget : Widget {
	this(Widget parent = null) {
		super(parent);
	}

	override int paddingLeft() { return 2; }
	override int paddingRight() { return 2; }
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
		override int minHeight() { return 32; }// Window.lineHeight * 3/2; }
		override int maxHeight() { return 32; } //Window.lineHeight * 3/2; }
	} else static assert(false);
	override int heightStretchiness() { return 0; }

	version(win32_widgets) 
		HIMAGELIST imageList;

	this(Action[] actions, Widget parent = null) {
		super(parent);

		tabStop = false;

		version(win32_widgets) {
			parentWindow = parent.parentWindow;
			createWin32Window(this, "ToolbarWindow32", "", 0);

			imageList = ImageList_Create(
				// width, height
				16, 16,
				ILC_COLOR16 | ILC_MASK,
				16 /*numberOfButtons*/, 0);

			SendMessageA(hwnd, TB_SETIMAGELIST, cast(WPARAM) 0, cast(LPARAM) imageList);
			SendMessageA(hwnd, TB_LOADIMAGES, cast(WPARAM) IDB_STD_SMALL_COLOR, cast(LPARAM) HINST_COMMCTRL);

			TBBUTTON[] buttons;

			// FIXME: I_IMAGENONE is if here is no icon
			foreach(action; actions)
				buttons ~= TBBUTTON(MAKELONG(cast(ushort)(action.iconId ? (action.iconId - 1) : -2 /* I_IMAGENONE */), 0), action.id, TBSTATE_ENABLED, 0, 0, 0, cast(int) toStringzInternal(action.label));

			SendMessageA(hwnd, TB_BUTTONSTRUCTSIZE, cast(WPARAM)TBBUTTON.sizeof, 0);
			SendMessageA(hwnd, TB_ADDBUTTONSA,       cast(WPARAM) buttons.length,      cast(LPARAM)buttons.ptr);

			/* this seems to make it a vertical toolbar on windows xp... don't actually want that
			SIZE size;
			SendMessageA(hwnd, TB_GETIDEALSIZE, true, cast(LPARAM) &size);
			idealHeight = size.cy;
			*/

			RECT rect;
			GetWindowRect(hwnd, &rect);
			idealHeight = rect.bottom - rect.top + 10; // the +10 is a hack since the size right now doesn't look right on a real Windows XP box

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

///
class ToolButton : Button {
	this(string label, Widget parent = null) {
		super(label, parent);
		tabStop = false;
	}
	this(Action action, Widget parent = null) {
		super(action.label, parent);
		tabStop = false;
		this.action = action;

		version(win32_widgets) {}
		else version(custom_widgets) {
			defaultEventHandlers["click"] = (Widget _this, Event event) {
				foreach(handler; action.triggered)
					handler();
			};

			paint = (ScreenPainter painter) {
				this.draw3dFrame(painter, isDepressed ? FrameStyle.sunk : FrameStyle.risen, currentButtonColor);

				painter.outlineColor = Color.black;

				enum iconSize = 32;
				enum multiplier = iconSize / 16;
				switch(action.iconId) {
					case GenericIcons.New:
						painter.fillColor = Color.white;
						painter.drawPolygon(
							Point(3, 2) * multiplier, Point(3, 13) * multiplier, Point(12, 13) * multiplier, Point(12, 6) * multiplier,
							Point(8, 2) * multiplier, Point(8, 6) * multiplier, Point(12, 6) * multiplier, Point(8, 2) * multiplier
						);
					break;
					case GenericIcons.Save:
						painter.fillColor = Color.black;
						painter.drawRectangle(Point(2, 2) * multiplier, Point(13, 13) * multiplier);

						painter.fillColor = Color.white;
						painter.outlineColor = Color.white;
						// the slider
						painter.drawRectangle(Point(5, 2) * multiplier, Point(10, 5) * multiplier);
						// the label
						painter.drawRectangle(Point(4, 8) * multiplier, Point(11, 12) * multiplier);

						painter.fillColor = Color.black;
						painter.outlineColor = Color.black;
						// the disc window
						painter.drawRectangle(Point(8, 3) * multiplier, Point(9, 4) * multiplier);
					break;
					case GenericIcons.Open:
						painter.fillColor = Color.white;
						painter.drawPolygon(
							Point(2, 4) * multiplier, Point(2, 12) * multiplier, Point(13, 12) * multiplier, Point(13, 3) * multiplier,
							Point(9, 3) * multiplier, Point(9, 4) * multiplier, Point(2, 4) * multiplier);
						painter.drawLine(Point(2, 6) * multiplier, Point(13, 7) * multiplier);
						//painter.drawLine(Point(9, 6) * multiplier, Point(13, 7) * multiplier);
					break;
					case GenericIcons.Copy:
						painter.fillColor = Color.white;
						painter.drawRectangle(Point(3, 2) * multiplier, Point(9, 10) * multiplier);
						painter.drawRectangle(Point(6, 5) * multiplier, Point(12, 13) * multiplier);
					break;
					case GenericIcons.Cut:
						painter.fillColor = Color.transparent;
						painter.drawLine(Point(3, 2) * multiplier, Point(10, 9) * multiplier);
						painter.drawLine(Point(4, 9) * multiplier, Point(11, 2) * multiplier);
						painter.drawRectangle(Point(3, 9) * multiplier, Point(5, 13) * multiplier);
						painter.drawRectangle(Point(9, 9) * multiplier, Point(11, 12) * multiplier);
					break;
					case GenericIcons.Paste:
						painter.fillColor = Color.white;
						painter.drawRectangle(Point(2, 3) * multiplier, Point(11, 11) * multiplier);
						painter.drawRectangle(Point(6, 8) * multiplier, Point(13, 13) * multiplier);
						painter.drawLine(Point(6, 2) * multiplier, Point(4, 5) * multiplier);
						painter.drawLine(Point(6, 2) * multiplier, Point(9, 5) * multiplier);
						painter.fillColor = Color.black;
						painter.drawRectangle(Point(4, 5) * multiplier, Point(9, 6) * multiplier);
					break;
					case GenericIcons.Help:
						painter.drawText(Point(0, 0), "?", Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);
					break;
					default:
						painter.drawText(Point(0, 0), action.label, Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);
				}
			};
		}
		else static assert(false);
	}

	Action action;

	override int maxWidth() { return 32; }
	override int minWidth() { return 32; }
	override int maxHeight() { return 32; }
	override int minHeight() { return 32; }
}


///
class MenuBar : Widget {
	MenuItem[] items;

	version(win32_widgets) {
		HMENU handle;
		this(Widget parent = null) {
			super(parent);

			handle = CreateMenu();
			tabStop = false;
		}
	} else version(custom_widgets) {
		this(Widget parent = null) {
			tabStop = false; // these are selected some other way
			super(parent);
			this.paint = (ScreenPainter painter) {
				draw3dFrame(this, painter, FrameStyle.risen);
			};
		}
	} else static assert(false);

	MenuItem addItem(MenuItem item) {
		this.addChild(item);
		items ~= item;
		version(win32_widgets) {
			AppendMenuA(handle, MF_STRING, item.action is null ? 9000 : item.action.id, toStringzInternal(item.label)); // XXX
		}
		return item;
	}

	Menu addItem(Menu item) {
		auto mbItem = new MenuItem(item.label, this.parentWindow);

		addChild(mbItem);
		items ~= mbItem;

		version(win32_widgets) {
			AppendMenuA(handle, MF_STRING | MF_POPUP, cast(UINT) item.handle, toStringzInternal(item.label)); // XXX
		} else version(custom_widgets) {
			mbItem.defaultEventHandlers["click"] = (Widget e, Event ev) {
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
	struct Parts {
		@disable this();
		this(StatusBar owner) { this.owner = owner; }
		//@disable this(this);
		@property int length() { return cast(int) owner.partsArray.length; }
		private StatusBar owner;
		private this(StatusBar owner, Part[] parts) {
			this.owner.partsArray = parts;
			this.owner = owner;
		}
		Part opIndex(int p) {
			if(owner.partsArray.length == 0)
				this ~= new StatusBar.Part(300);
			return owner.partsArray[p];
		}

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
				SendMessageA(owner.hwnd, WM_USER + 4 /*SB_SETPARTS*/, owner.partsArray.length, cast(int) pos.ptr);
			} else version(custom_widgets) {
				owner.redraw();
			} else static assert(false);

			return p;
		}
	}

	private Parts _parts;
	@property Parts parts() {
		return _parts;
	}

	static class Part {
		int width;
		StatusBar owner;

		this(int w = 100) { width = w; }

		private int idx;
		private string _content;
		@property string content() { return _content; }
		@property void content(string s) {
			version(win32_widgets) {
				_content = s;
				SendMessageA(owner.hwnd, SB_SETTEXT, idx, cast(LPARAM) toStringzInternal(s));
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


	this(Widget parent = null) {
		super(null); // FIXME
		_parts = Parts(this);
		tabStop = false;
		version(win32_widgets) {
			parentWindow = parent.parentWindow;
			createWin32Window(this, "msctls_statusbar32", "", 0);

			RECT rect;
			GetWindowRect(hwnd, &rect);
			idealHeight = rect.bottom - rect.top;
			assert(idealHeight);
		} else version(custom_widgets) {
			this.paint = (ScreenPainter painter) {
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
			};
		} else static assert(false);
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
		parentWindow = parent.parentWindow;
		createWin32Window(this, "msctls_progress32", "", 8 /* PBS_MARQUEE */);
		tabStop = false;
	}
	override int minHeight() { return 10; }
}

/// A progress bar with a known endpoint and completion amount
class ProgressBar : Widget {
	version(win32_widgets)
	this(Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "msctls_progress32", "", 0);
		tabStop = false;
	}
	else version(custom_widgets) {
		this(Widget parent = null) {
			super(parent);
			max = 100;
			step = 10;
			tabStop = false;
			paint = (ScreenPainter painter) {
				this.draw3dFrame(painter, FrameStyle.sunk);
				painter.fillColor = Color.blue;
				painter.drawRectangle(Point(0, 0), width * current / max, height);
			};
		}

		int current;
		int max;
		int step;
	}
	else static assert(false);

	void advanceOneStep() {
		version(win32_widgets)
			SendMessageA(hwnd, PBM_STEPIT, 0, 0);
		else version(custom_widgets)
			addToPosition(step);
		else static assert(false);
	}

	void setStepIncrement(int increment) {
		version(win32_widgets)
			SendMessageA(hwnd, PBM_SETSTEP, increment, 0);
		else version(custom_widgets)
			step = increment;
		else static assert(false);
	}

	void addToPosition(int amount) {
		version(win32_widgets)
			SendMessageA(hwnd, PBM_DELTAPOS, amount, 0);
		else version(custom_widgets)
			setPosition(current + amount);
		else static assert(false);
	}

	void setPosition(int pos) {
		version(win32_widgets)
			SendMessageA(hwnd, PBM_SETPOS, pos, 0);
		else version(custom_widgets) {
			current = pos;
			if(current > max)
				current = max;
			redraw();
		}
		else static assert(false);
	}

	void setRange(ushort min, ushort max) {
		version(win32_widgets)
			SendMessageA(hwnd, PBM_SETRANGE, 0, MAKELONG(min, max));
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

	version(win32_widgets)
	this(string legend, Widget parent = null) {
		super(parent);
		this.legend = legend;
		parentWindow = parent.parentWindow;
		createWin32Window(this, "button", legend, BS_GROUPBOX);
		tabStop = false;
	}
	else version(custom_widgets)
	this(string legend, Widget parent = null) {
		super(parent);
		tabStop = false;
		this.legend = legend;
		parentWindow = parent.parentWindow;
		this.paint = (ScreenPainter painter) {
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
		};
	}
	else static assert(false);

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
		return super.minHeight() + Window.lineHeight + 4;
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

		parentWindow.removeEventListener("mousedown", &remove);
		parentWindow.releaseMouseCapture();
	}

	version(win32_widgets) {}
	else version(custom_widgets) {
		SimpleWindow dropDown;
		Widget menuParent;
		void popup(Widget parent) {
			this.menuParent = parent;

			auto w = 150;
			auto h = this.children.length ? cast(int) this.children.length * this.children[0].maxHeight() : 20;

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
					auto painter = dropDown.draw();
					dropDown.grabInput();
				}
			};

			dropDown.show();
		}
	}
	else static assert(false);

	version(custom_widgets)
	void unpopup() {
		dropDown.releaseInputGrab();
		dropDown.hide();
		if(!menuParent.parentWindow.win.closed)
			menuParent.parentWindow.win.focus();
	}

	MenuItem[] items;

	MenuItem addItem(MenuItem item) {
		addChild(item);
		items ~= item;
		version(win32_widgets) {
			AppendMenuA(handle, MF_STRING, item.action is null ? 9000 : item.action.id, toStringzInternal(item.label)); // XXX
		}
		return item;
	}

	string label;

	version(win32_widgets) {
		HMENU handle;
		this(string label, Widget parent = null) {
			super(parent);
			this.label = label;
			handle = CreatePopupMenu();
		}
	} else version(custom_widgets) {
		this(string label, Widget parent = null) {

			if(dropDown) {
				dropDown.close();
			}
			dropDown = new SimpleWindow(
				150, 4,
				null, OpenGlOptions.no, Resizability.fixedSize, WindowTypes.dropdownMenu, WindowFlags.dontAutoShow/*, window*/);

			this.label = label;

			defaultEventHandlers["click"] = delegate(Widget this_, Event ev) {
				unpopup();
			};

			super(dropDown);

			this.paint = delegate (ScreenPainter painter) {
				this.draw3dFrame(painter, FrameStyle.risen);
			};
		}
	} else static assert(false);

	override int maxHeight() { return Window.lineHeight; }
	override int minHeight() { return Window.lineHeight; }
}

///
class MenuItem : MouseActivatedWidget {
	Menu submenu;

	Action action;
	string label;

	override int paddingLeft() { return 4; }

	override int maxHeight() { return Window.lineHeight + 4; }
	override int minWidth() { return Window.lineHeight * cast(int) label.length + 8; }
	override int maxWidth() {
		if(cast(MenuBar) parent)
			return Window.lineHeight / 2 * cast(int) label.length + 8;
		return int.max;
	}
	this(string lbl, Widget parent = null) {
		super(parent);
		//label = lbl; // FIXME
		foreach(char ch; lbl) // FIXME
			if(ch != '&') // FIXME
				label ~= ch; // FIXME
		version(win32_widgets) {}
		else version(custom_widgets)
			this.paint = (ScreenPainter painter) {
				if(isHovering)
					painter.outlineColor = Color.blue;
				else
					painter.outlineColor = Color.black;
				painter.fillColor = Color.transparent;
				painter.drawText(Point(cast(MenuBar) this.parent ? 4 : 20, 2), label, Point(width, height), TextAlignment.Left);
			};
		else static assert(false);
		tabStop = false; // these are selected some other way
	}

	this(Action action, Widget parent = null) {
		assert(action !is null);
		this(action.label);
		this.action = action;
		defaultEventHandlers["triggered"] = (Widget w, Event ev) {
			//auto event = new Event("triggered", this);
			//event.dispatch();
			foreach(handler; action.triggered)
				handler();

			if(auto pmenu = cast(Menu) this.parent)
				pmenu.remove();
		};
		tabStop = false; // these are selected some other way
	}
}

version(win32_widgets)
class MouseActivatedWidget : Widget {
	bool isChecked() {
		assert(hwnd);
		return SendMessageA(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED;

	}
	void isChecked(bool state) {
		assert(hwnd);
		SendMessageA(hwnd, BM_SETCHECK, state ? BST_CHECKED : BST_UNCHECKED, 0);

	}

	this(Widget parent = null) {
		super(parent);
	}
}
else version(custom_widgets)
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

		defaultEventHandlers["focus"] = delegate (Widget _this, Event ev) {
			_this.redraw();
		};
		defaultEventHandlers["blur"] = delegate (Widget _this, Event ev) {
			isDepressed = false;
			isHovering = false;
			_this.redraw();
		};
		defaultEventHandlers["keydown"] = delegate (Widget _this, Event ev) {
			if(ev.key == Key.Space || ev.key == Key.Enter || ev.key == Key.PadEnter) {
				isDepressed = true;
				_this.redraw();
			}
		};
		defaultEventHandlers["keyup"] = delegate (Widget _this, Event ev) {
			if(!isDepressed)
				return;
			isDepressed = false;
			_this.redraw();

			auto event = new Event("triggered", this);
			event.sendDirectly();
		};


		defaultEventHandlers["click"] = (Widget w, Event ev) {
			if(this.tabStop)
				this.focus();
			auto event = new Event("triggered", this);
			event.sendDirectly();
		};
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

	version(win32_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "button", label, BS_AUTOCHECKBOX);
	}
	else version(custom_widgets)
	this(string label, Widget parent = null) {
		super(parent);

		this.paint = (ScreenPainter painter) {

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
		};

		defaultEventHandlers["triggered"] = delegate (Widget _this, Event ev) {
			isChecked = !isChecked;

			auto event = new Event(EventType.change, this);
			event.dispatch();

			redraw();
		};
	}
	else static assert(false);
}

///
class VerticalSpacer : Widget {
	override int maxHeight() { return 20; }
	override int minHeight() { return 20; }
	this(Widget parent = null) {
		super(parent);
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

	version(win32_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "button", label, BS_AUTORADIOBUTTON);
	}
	else version(custom_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		height = 16;
		width = height + 4 + cast(int) label.length * 16;

		this.paint = (ScreenPainter painter) {
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
		};

		defaultEventHandlers["triggered"] = delegate (Widget _this, Event ev) {
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
		};
	}
	else static assert(false);
}


///
class Button : MouseActivatedWidget {
	Color normalBgColor;
	Color hoverBgColor;
	Color depressedBgColor;

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

	version(win32_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "button", label, BS_PUSHBUTTON);

		// FIXME: use ideal button size instead
		width = 50;
		height = 30;
	}
	else version(custom_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		normalBgColor = Color(192, 192, 192);
		hoverBgColor = Color(215, 215, 215);
		depressedBgColor = Color(160, 160, 160);

		width = 50;
		height = 30;

		this.paint = (ScreenPainter painter) {
			this.draw3dFrame(painter, isDepressed ? FrameStyle.sunk : FrameStyle.risen, currentButtonColor);


			painter.outlineColor = Color.black;
			painter.drawText(Point(0, 0), label, Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);

			if(isFocused()) {
				painter.fillColor = Color.transparent;
				painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
				painter.drawRectangle(Point(2, 2), width - 4, height - 4);
				painter.pen = Pen(Color.black, 1, Pen.Style.Solid);

			}
		};
	}
	else static assert(false);

	override int minHeight() { return Window.lineHeight; }
}

enum ArrowDirection {
	left, right, up, down
}

///
version(custom_widgets)
class ArrowButton : Button {
	this(ArrowDirection direction, Widget parent = null) {
		super("", parent);

		auto superPainter = this.paint;
		assert(superPainter !is null);
		this.paint = (ScreenPainter painter) {
			superPainter(painter);

			painter.outlineColor = Color.black;
			painter.fillColor = Color.black;

			auto offset = Point((this.width - 16) / 2, (this.height - 16) / 2);

			final switch(direction) {
				case ArrowDirection.up:
					painter.drawPolygon(
						Point(4, 12) + offset,
						Point(8, 6) + offset,
						Point(12, 12) + offset
					);
				break;
				case ArrowDirection.down:
					painter.drawPolygon(
						Point(4, 6) + offset,
						Point(8, 12) + offset,
						Point(12, 6) + offset
					);
				break;
				case ArrowDirection.left:
					painter.drawPolygon(
						Point(12, 4) + offset,
						Point(6, 8) + offset,
						Point(12, 12) + offset
					);
				break;
				case ArrowDirection.right:
					painter.drawPolygon(
						Point(6, 4) + offset,
						Point(12, 8) + offset,
						Point(6, 12) + offset
					);
				break;
			}

		};
	}

	override int minHeight() { return 16; }
	override int maxHeight() { return 16; }
	override int minWidth() { return 16; }
	override int maxWidth() { return 16; }
}

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
class TextLabel : Widget {
	override int maxHeight() { return Window.lineHeight; }
	override int minHeight() { return Window.lineHeight; }
	override int minWidth() { return 32; }

	string label;
	this(string label, Widget parent = null) {
		this.label = label;
		this.tabStop = false;
		super(parent);
		parentWindow = parent.parentWindow;
		paint = (ScreenPainter painter) {
			painter.outlineColor = Color.black;
			painter.drawText(Point(0, 0), this.label, Point(width,height), TextAlignment.Right);
		};
	}

}

version(custom_widgets)
	mixin ExperimentalTextComponent;

/// Contains the implementation of text editing
abstract class EditableTextWidget : ScrollableWidget {
	this(Widget parent = null) {
		super(parent);
	}

	override int minWidth() { return 16; }
	override int minHeight() { return Window.lineHeight + 0; } // the +0 is to leave room for the padding
	override int widthStretchiness() { return 3; }

	@property string content() {
		version(win32_widgets) {
			char[4096] buffer;
			// FIXME: GetWindowTextW
			// FIXME: GetWindowTextLength
			auto l = GetWindowTextA(hwnd, buffer.ptr, buffer.length - 1);
			if(l >= 0)
				return buffer[0 .. l].idup;
			else
				return null;
		} else version(custom_widgets) {
			return textLayout.getPlainText();
		} else static assert(false);
	}
	@property void content(string s) {
		version(win32_widgets)
			SetWindowTextA(hwnd, toStringzInternal(s));
		else version(custom_widgets) {
			textLayout.clear();
			textLayout.addText(s);
			/*
			textLayout.addText(ForegroundColor.red, s);
			textLayout.addText(ForegroundColor.blue, TextFormat.underline, "http://dpldocs.info/");
			textLayout.addText(" is the best!");
			*/
			redraw();
		}
		else static assert(false);
	}

	version(custom_widgets)
	override void paintFrameAndBackground(ScreenPainter painter) {
		this.draw3dFrame(painter, FrameStyle.sunk, Color.white);
	}

	version(win32_widgets) { /* will do it with Windows calls in the classes */ }
	else version(custom_widgets) {
		// FIXME

		Timer caratTimer;
		TextLayout textLayout;

		void setupCustomTextEditing() {
			textLayout = new TextLayout(Rectangle(0, 0, width, height));

			this.paint = (ScreenPainter painter) {
				if(parentWindow.win.closed) return;

				textLayout.boundingBox = Rectangle(4, 2, width - 8, height - 4);

				painter.outlineColor = Color.black;
				// painter.drawText(Point(4, 4), content, Point(width - 4, height - 4));

				textLayout.caratShowingOnScreen = false;

				textLayout.drawInto(painter, !parentWindow.win.closed && isFocused());
			};

			defaultEventHandlers["click"] = delegate (Widget _this, Event ev) {
				if(parentWindow.win.closed) return;
				textLayout.moveCaratToPixelCoordinates(ev.clientX, ev.clientY);
				this.focus();
			};

			defaultEventHandlers["focus"] = delegate (Widget _this, Event ev) {
				if(parentWindow.win.closed) return;
				auto painter = this.draw();
				textLayout.drawCarat(painter);

				if(caratTimer) {
					caratTimer.destroy();
					caratTimer = null;
				}

				caratTimer = new Timer(500, {
					if(parentWindow.win.closed) {
						caratTimer.destroy();
						return;
					}
					if(isFocused()) {
						auto painter = this.draw();
						textLayout.drawCarat(painter);
					} else if(textLayout.caratShowingOnScreen) {
						auto painter = this.draw();
						textLayout.eraseCarat(painter);
					}
				});

			};
			defaultEventHandlers["blur"] = delegate (Widget _this, Event ev) {
				if(parentWindow.win.closed) return;
				auto painter = this.draw();
				textLayout.eraseCarat(painter);
				if(caratTimer) {
					caratTimer.destroy();
					caratTimer = null;
				}

				auto evt = new Event(EventType.change, this);
				evt.dispatch();
			};

			defaultEventHandlers["char"] = delegate (Widget _this, Event ev) {
				textLayout.insert(ev.character);
				redraw();

				// FIXME: too inefficient
				auto cbb = textLayout.contentBoundingBox();
				setContentSize(cbb.width, cbb.height);
			};
			addEventListener("keydown", delegate (Widget _this, Event ev) {
				switch(ev.key) {
					case Key.Delete:
						textLayout.delete_();
						redraw();
					break;
					case Key.Left:
						textLayout.moveLeft(textLayout.carat);
						redraw();
					break;
					case Key.Right:
						textLayout.moveRight(textLayout.carat);
						redraw();
					break;
					case Key.Up:
						textLayout.moveUp(textLayout.carat);
						redraw();
					break;
					case Key.Down:
						textLayout.moveDown(textLayout.carat);
						redraw();
					break;
					case Key.Home:
						textLayout.moveHome(textLayout.carat);
						redraw();
					break;
					case Key.End:
						textLayout.moveEnd(textLayout.carat);
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
			});

			static if(UsingSimpledisplayX11)
				cursor = XCreateFontCursor(XDisplayConnection.get(), 152 /* XC_xterm, a text input thingy */);
		}
	}
	else static assert(false);
}

///
class LineEdit : EditableTextWidget {
	this(Widget parent = null) {
		super(parent);
		version(win32_widgets) {
			parentWindow = parent.parentWindow;
			createWin32Window(this, "edit", "", 
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
}

///
class TextEdit : EditableTextWidget {
	this(Widget parent = null) {
		super(parent);
		version(win32_widgets) {
			parentWindow = parent.parentWindow;
			createWin32Window(this, "edit", "", 
				0|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_WANTRETURN|ES_AUTOHSCROLL|ES_AUTOVSCROLL, WS_EX_CLIENTEDGE);
		} else version(custom_widgets) {
			setupCustomTextEditing();
		} else static assert(false);
	}
	override int maxHeight() { return int.max; }
	override int heightStretchiness() { return 4; }
}



///
class MessageBox : Window {
	this(string message) {
		super(300, 100);

		auto superPaint = this.paint;
		this.paint = (ScreenPainter painter) {
			if(superPaint)
				superPaint(painter);
			painter.outlineColor = Color.black;
			painter.drawText(Point(0, 0), message, Point(width, height / 2), TextAlignment.Center | TextAlignment.VerticalCenter);
		};

		auto button = new Button("OK", this);
		button. x = this.width / 2 - button.width / 2;
		button.y = height - (button.height + 10);
		button.addEventListener(EventType.triggered, () {
			win.close();
		});

		button.registerMovement();
		button.focus();

		win.show();
		redraw();
	}

	// this one is all fixed position
	override void recomputeChildLayout() {}
}







/* FIXME: this is mostly copy/pasta'd from dom.d. Would be nice to kill the duplication */

mixin template EventStuff() {
	EventHandler[][string] bubblingEventHandlers;
	EventHandler[][string] capturingEventHandlers;
	EventHandler[string] defaultEventHandlers;

	void addDirectEventListener(string event, void delegate() handler, bool useCapture = false) {
		addEventListener(event, (Widget, Event e) {
			if(e.srcElement is this)
				handler();
		}, useCapture);
	}

	void addEventListener(string event, void delegate() handler, bool useCapture = false) {
		addEventListener(event, (Widget, Event) { handler(); }, useCapture);
	}

	void addEventListener(string event, void delegate(Event) handler, bool useCapture = false) {
		addEventListener(event, (Widget, Event e) { handler(e); }, useCapture);
	}

	void addEventListener(string event, EventHandler handler, bool useCapture = false) {
		if(event.length > 2 && event[0..2] == "on")
			event = event[2 .. $];

		if(useCapture)
			capturingEventHandlers[event] ~= handler;
		else
			bubblingEventHandlers[event] ~= handler;
	}

	void removeEventListener(string event, void delegate() handler, bool useCapture = false) {
		removeEventListener(event, (Widget, Event) { handler(); }, useCapture);
	}

	void removeEventListener(string event, void delegate(Event) handler, bool useCapture = false) {
		removeEventListener(event, (Widget, Event e) { handler(e); }, useCapture);
	}

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
}

alias void delegate(Widget handlerAttachedTo, Event event) EventHandler;

enum EventType : string {
	click = "click",

	mouseenter = "mouseenter",
	mouseleave = "mouseleave",
	mousein = "mousein",
	mouseout = "mouseout",
	mouseup = "mouseup",
	mousedown = "mousedown",
	mousemove = "mousemove",

	keydown = "keydown",
	keyup = "keyup",
	// char = "char",

	focus = "focus",
	blur = "blur",

	triggered = "triggered",

	change = "change",
}

///
class Event {
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

	Widget srcElement;
	alias srcElement target;

	Widget relatedTarget;

	int clientX;
	int clientY;

	int viewportX;
	int viewportY;

	int button;
	Key key;
	dchar character;

	int state;

	bool shiftKey;

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

bool isAParentOf(Widget a, Widget b) {
	if(a is null || b is null)
		return false;

	while(b !is null) {
		if(a is b)
			return true;
		b = b.parent;
	}

	return false;
}

struct WidgetAtPointResponse {
	Widget widget;
	int x;
	int y;
}

WidgetAtPointResponse widgetAtPoint(Widget starting, int x, int y) {
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

version(win32_theming) {
	import std.c.windows.windows;

	alias HANDLE HTHEME;

	// Since dmd doesn't offer uxtheme.lib, I'll load the dll at runtime instead
	HMODULE uxtheme;
	static this() {
		uxtheme = LoadLibraryA("uxtheme.dll");
		if(uxtheme) {
			DrawThemeBackground = cast(typeof(DrawThemeBackground)) GetProcAddress(uxtheme, "DrawThemeBackground");
			OpenThemeData = cast(typeof(OpenThemeData)) GetProcAddress(uxtheme, "OpenThemeData");
			CloseThemeData = cast(typeof(CloseThemeData)) GetProcAddress(uxtheme, "CloseThemeData");
			GetThemeSysColorBrush = cast(typeof(GetThemeSysColorBrush)) GetProcAddress(uxtheme, "CloseThemeData");
		}
	}

	// everything from here is just win32 headers copy pasta
private:
extern(Windows):

	HRESULT function(HTHEME, HDC, int, int, in RECT*, in RECT*) DrawThemeBackground;
	HTHEME function(HWND, LPCWSTR) OpenThemeData;
	HRESULT function(HTHEME) CloseThemeData;
	HBRUSH function(HTHEME, int) GetThemeSysColorBrush;

	HMODULE LoadLibraryA(LPCSTR);
	BOOL FreeLibrary(HMODULE);
	FARPROC GetProcAddress(HMODULE, LPCSTR);
	// pragma(lib, "uxtheme");

	BOOL GetClassInfoA(HINSTANCE, LPCSTR, WNDCLASS*);
}

version(win32_widgets) {
	import core.sys.windows.windows;
	import gdi = core.sys.windows.wingdi;
	// import win32.commctrl;
	// import win32.winuser;

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
	enum SB_SETTEXT = WM_USER + 1; // SET TEXT A. It is +11 for W
}



enum GenericIcons : ushort {
	None,
	// these happen to match the win32 std icons numerically if you just subtract one from the value
	Cut,
	Copy,
	Paste,
	Undo,
	Redo,
	Delete,
	New,
	Open,
	Save,
	PrintPreview,
	Properties,
	Help,
	Find,
	Replace,
	Print,
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
