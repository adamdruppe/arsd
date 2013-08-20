module arsd.minigui;

import simpledisplay;

version(Windows) {
	// use native widgets when available
	version = win32_widgets;
	// and native theming when needed
	version = win32_theming;
}

enum windowBackgroundColor = Color(190, 190, 190);

private const(char)* toStringz(string s) { return (s ~ '\0').ptr; }

/*
class Action {
	string label;
	// icon

	// when it is triggered, the triggered event is fired on the window
	void delegate()[] triggered;
}
*/

/*
	plan:
		keyboard accelerators

		menus (and popups and tooltips)
		status bar
		toolbars and buttons

		sortable table view

		maybe notification area icons

		radio box
		toggle buttons (optionally mutually exclusive, like in Paint)
		label, rich text display, multi line plain text (selectable)
		fieldset
		nestable grid layout
		single line text input
		multi line text input
		slider
		spinner
		list box
		drop down
		combo box
		auto complete box
		progress bar

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

mixin template LayoutInfo() {
	int minWidth() { return 0; }
	int minHeight() { return 0; }
	int maxWidth() { return int.max; }
	int maxHeight() { return int.max; }
	int widthStretchiness() { return 1; }
	int heightStretchiness() { return 1; }
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
	// my own width and height should already be set by the caller of this function...
	int spaceRemaining = mixin("parent." ~ relevantMeasure);
	int stretchinessSum;
	foreach(child; parent.children) {
		static if(calcingV) {
			child.width = parent.width; // block element style
			if(child.width > child.maxWidth())
				child.width = child.maxWidth();
			child.height = child.minHeight();
		} else {
			child.height = parent.height; // block element style
			if(child.height > child.maxHeight())
				child.height = child.maxHeight();
			child.width = child.minWidth();
		}

		spaceRemaining -= mixin("child." ~ relevantMeasure);
		stretchinessSum += mixin("child." ~ relevantMeasure ~ "Stretchiness()");
	}

	while(stretchinessSum) {
		auto spacePerChild = spaceRemaining / stretchinessSum;
		if(spacePerChild == 0)
			break;
		stretchinessSum = 0;
		foreach(child; parent.children) {
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
				auto diff = maximum - mixin("child." ~ relevantMeasure);
				mixin("child." ~ relevantMeasure) -= diff;
				spaceRemaining += diff;
			} else if(mixin("child." ~ relevantMeasure) < maximum) {
				stretchinessSum += mixin("child." ~ relevantMeasure ~ "Stretchiness()");
			}
		}
	}

	int currentPos = 0;
	foreach(child; parent.children) {
		static if(calcingV) {
			child.x = 0;
			child.y = currentPos;
		} else {
			child.x = currentPos;
			child.y = 0;

		}
		currentPos += mixin("child." ~ relevantMeasure);

		child.recomputeChildLayout();
	}
}

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
// and here, it must be integratable with the layout, the event system, and not be painted over.
version(win32_widgets) {
	import std.c.windows.windows;
	extern(Windows)
	int HookedWndProc(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) nothrow {
		if(auto te = hWnd in Widget.nativeMapping) {
			auto pos = getChildPositionRelativeToParentOrigin(*te);
			if(SimpleWindow.triggerEvents(hWnd, iMessage, wParam, lParam, pos[0], pos[1], (*te).parentWindow.win))
				{}
			return CallWindowProcW((*te).originalWindowProcedure, hWnd, iMessage, wParam, lParam);
		}
		assert(0, "shouldn't be receiving messages for this window....");
		//import std.conv;
		//assert(0, to!string(hWnd) ~ " :: " ~ to!string(TextEdit.nativeMapping)); // not supposed to happen
	}

	void createWin32Window(Widget p, string className, string windowText, DWORD style) {
		assert(p.parentWindow !is null);
		assert(p.parentWindow.win.impl.hwnd !is null);

		style |= WS_VISIBLE | WS_CHILD;
		p.hwnd = CreateWindow(toStringz(className), toStringz(windowText), style,
				CW_USEDEFAULT, CW_USEDEFAULT, 100, 100,
				p.parentWindow.win.impl.hwnd, null, cast(HINSTANCE) GetModuleHandle(null), null);

		assert(p.hwnd !is null);

		Widget.nativeMapping[p.hwnd] = p;

		p.originalWindowProcedure = cast(WNDPROC) SetWindowLong(p.hwnd, GWL_WNDPROC, cast(LONG) &HookedWndProc);
	}
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

	string statusTip;
	// string toolTip;
	// string helpText;

	version(win32_widgets) {
		static Widget[HWND] nativeMapping;
		HWND hwnd;
		WNDPROC originalWindowProcedure;
	}

	int x; // relative to the parent's origin
	int y; // relative to the parent's origin
	int width;
	int height;
	Widget[] children;
	Widget parent;

	void registerMovement() {
		version(win32_widgets) {
			if(hwnd) {
				auto pos = getChildPositionRelativeToParentOrigin(this);
				MoveWindow(hwnd, pos[0], pos[1], width, height, true);
			}
		}
	}

	Window parentWindow;

	this(Widget parent = null) {
		if(parent !is null)
			parent.addChild(this);
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

	void attachedToWindow(Window w) {}
	void addedTo(Widget w) {}

	private void newWindow(Window parent) {
		parentWindow = parent;
		foreach(child; children)
			child.newWindow(parent);
	}

	void addChild(Widget w, int position = int.max) {
		w.parent = this;
		if(position == int.max || position == children.length)
			children ~= w;
		else {
			assert(position < children.length);
			children.length = children.length + 1;
			for(int i = children.length - 1; i > position; i--)
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
		auto painter = parentWindow.win.draw();
		painter.originX = x;
		painter.originY = y;
		return painter;
	}

	protected void privatePaint(ScreenPainter painter, int lox, int loy) {
		painter.originX = lox + x;
		painter.originY = loy + y;
		if(paint !is null)
			paint(painter);
		foreach(child; children)
			child.privatePaint(painter, painter.originX, painter.originY);
	}

	void redraw() {
		if(!showing) return;

		assert(parentWindow !is null);
		auto ugh = this.parent;
		int lox, loy;
		while(ugh) {
			lox += ugh.x;
			loy += ugh.y;
			ugh = ugh.parent;
		}
		auto painter = parentWindow.win.draw();
		privatePaint(painter, lox, loy);
	}
}

class VerticalLayout : Widget {
	// intentionally blank - widget's default is vertical layout right now
}
class HorizontalLayout : Widget {
	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}
}



class Window : Widget {
	static int lineHeight;

	Widget focusedWidget;

	SimpleWindow win;
	this(int width = 500, int height = 500) {
		super(null);

		win = new SimpleWindow(width, height);
		this.width = win.width;
		this.height = win.height;
		this.parentWindow = this;
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
				dispatchCharEvent(e);
			},
		);

		if(lineHeight == 0) {
			auto painter = win.draw();
			lineHeight = painter.fontHeight() * 5 / 4;
		}

		this.paint = (ScreenPainter painter) {
			painter.fillColor = windowBackgroundColor;
			painter.drawRectangle(Point(0, 0), this.width, this.height);
		};
	}

	void close() {
		win.close();
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
		auto ele = widgetAtPoint(this, ev.x, ev.y);

		if(ev.type == 1) {
			mouseLastDownOn = ele;
			auto event = new Event("mousedown", ele);
			event.button = ev.button;
			event.dispatch();
		} else if(ev.type == 2) {
			auto event = new Event("mouseup", ele);
			event.button = ev.button;
			event.dispatch();
			if(mouseLastDownOn is ele) {
				event = new Event("click", ele);
				event.clientX = ev.x;
				event.clientY = ev.y;
				event.dispatch();
			}
		} else if(ev.type == 0 && mouseLastOver !is ele) {
			// motion
			Event event;

			if(ele !is null) {
				if(!isAParentOf(ele, mouseLastOver)) {
					event = new Event("mouseenter", ele);
					event.relatedTarget = mouseLastOver;
					event.sendDirectly();
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

		return super.dispatchMouseEvent(ev);
	}

	void loop() {
		recomputeChildLayout();
		redraw();
		win.eventLoop(0);
	}
}

class MainWindow : Window {
	this() {
		super(500, 500);

		win.windowResized = (int w, int h) {
			this.width = w;
			this.height = h;
			recomputeChildLayout();
			redraw();
		};

		defaultEventHandlers["mouseover"] = delegate void(Widget _this, Event event) {
			if(this.statusBar !is null && event.target.statusTip.length)
				this.statusBar.content = event.target.statusTip;
			else if(this.statusBar !is null && _this.statusTip.length)
				this.statusBar.content = _this.statusTip;
		};

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
							if(auto item = idm in menuCommandMapping) {
								auto event = new Event("triggered", *item);
								event.button = idm;
								event.dispatch();
							} else {
								auto buttonHandle = cast(HWND) lParam;
								if(auto widget = buttonHandle in Widget.nativeMapping) {
									auto event = new Event("triggered", *widget);
									event.dispatch();
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

		_clientArea = new Widget();
		_clientArea.x = 0;
		_clientArea.y = 0;
		_clientArea.width = this.width;
		_clientArea.height = this.height;

		super.addChild(_clientArea);

		statusBar = new StatusBar("", this);
	}

	override void addChild(Widget c, int position = int.max) {
		clientArea.addChild(c, position);
	}

	version(win32_widgets)
	static MenuItem[int] menuCommandMapping;
	static int lastId = 9000;

	MenuBar _menu;
	MenuBar menu() { return _menu; }
	void menu(MenuBar m) {
		if(_menu !is null) {
			// make sure it is sanely removed
			// FIXME
		}

		version(win32_widgets) {
			SetMenu(parentWindow.win.impl.hwnd, m.handle);
		} else {
			_menu = m;
			super.addChild(m, 0);

		//	clientArea.y = menu.height;
		//	clientArea.height = this.height - menu.height;

			recomputeChildLayout();
		}
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
}

/**
	Toolbars are lists of buttons (typically icons) that appear under the menu.
	Each button ought to correspond to a menu item.
*/
class ToolBar : Widget {
	override int maxHeight() { return 40; }

	version(win32_widgets) {
	HIMAGELIST imageList;
	this(Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "ToolbarWindow32", "", 0);

		auto numberOfButtons = 3;

		imageList = ImageList_Create(
			// width, height
			16, 16,
			ILC_COLOR16 | ILC_MASK,
			numberOfButtons, 0);

		SendMessageA(hwnd, TB_SETIMAGELIST, cast(WPARAM) 0, cast(LPARAM) imageList);
		SendMessageA(hwnd, TB_LOADIMAGES, cast(WPARAM) IDB_STD_SMALL_COLOR, cast(LPARAM) HINST_COMMCTRL);

		TBBUTTON[] buttons;
		buttons ~= TBBUTTON(MAKELONG(STD_FILENEW, 0), 9435, TBSTATE_ENABLED, 0, 0, 0, cast(int) "New".ptr);
		buttons ~= TBBUTTON(MAKELONG(STD_FILEOPEN, 0), 9435, TBSTATE_ENABLED, 0, 0, 0, cast(int) "Open".ptr);
		buttons ~= TBBUTTON(MAKELONG(STD_FILESAVE, 0), 9435, TBSTATE_ENABLED, 0, 0, 0, cast(int) "Save".ptr);

		SendMessageA(hwnd, TB_BUTTONSTRUCTSIZE, cast(WPARAM)TBBUTTON.sizeof, 0);
		SendMessageA(hwnd, TB_ADDBUTTONSA,       cast(WPARAM)numberOfButtons,      cast(LPARAM)buttons.ptr);

	}
	} else {
		this(Widget parent = null) {
			super(parent);
			addChild(new ToolButton("New"));
			addChild(new ToolButton("Open"));
			addChild(new ToolButton("Save"));
		}
	}

	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}
}

class ToolButton : Button {
	this(string label, Widget parent = null) {
		super(label, parent);
	}

	override int maxWidth() { return 40; }
	override int minWidth() { return 40; }
}


class MenuBar : Widget {
	MenuItem[] items;

	version(win32_widgets) {
		HMENU handle;
		this(Widget parent = null) {
			super(parent);

			handle = CreateMenu();
		}
	} else {
		this(Widget parent = null) {
			super(parent);
			this.paint = (ScreenPainter painter) {
				painter.outlineColor = Color.black;
				painter.fillColor = Color.transparent;
				painter.drawRectangle(Point(0, 0), width, height);
			};
		}
	}

	MenuItem addItem(MenuItem item) {
		this.addChild(item);
		items ~= item;
		version(win32_widgets) {
			MainWindow.menuCommandMapping[MainWindow.lastId + 1] = item;
			AppendMenu(handle, MF_STRING, ++MainWindow.lastId, toStringz(item.label));
		}
		return item;
	}

	Menu addItem(Menu item) {
		auto mbItem = new MenuItem(item.label, this.parentWindow);

		addChild(mbItem);
		items ~= mbItem;

		version(win32_widgets) {
			AppendMenu(handle, MF_STRING | MF_POPUP, cast(UINT) item.handle, toStringz(item.label));
		} else {
			mbItem.defaultEventHandlers["click"] = (Widget e, Event ev) {
				item.parentWindow = e.parentWindow;
				item.popup(mbItem);
			};
		}

		return item;
	}

	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}

	override int maxHeight() { return Window.lineHeight; }
	override int minHeight() { return Window.lineHeight; }

}


/**
	Status bars appear at the bottom of a MainWindow.

	auto window = new MainWindow(100, 100);
	window.statusBar = new StatusBar("Test", window);

	// two parts, spaced automatically
	or new StatusBar(["test", "23"], window);

	// three parts, evenly spaced, no identifier
	or new StatusBar(3, window);

	// part spacing
	or new StatusBar([32, 0], window)
	or new StatusBar([StatusBarPart(32, "foo"), StatusBarPart("test")]);


	They can have multiple parts or be in simple mode. FIXME: implement
*/
class StatusBar : Widget {
	private string _content;
	@property string content() { return _content; }
	@property void content(string s) {
		version(win32_widgets) {
			WPARAM wParam;
			auto idx = 0; // see also SB_SIMPLEID
			wParam = idx;
			SendMessageA(hwnd, SB_SETTEXT, wParam, cast(LPARAM) toStringz(s));
		} else {
			_content = s;
			redraw();
		}
	}

	version(win32_widgets)
	this(string c, Widget parent = null) {
		super(null); // FIXME
		parentWindow = parent.parentWindow;
		createWin32Window(this, "msctls_statusbar32", "D rox", 0);
	}
	else
	this(string c, Widget parent = null) {
		super(null); // is this right?
		_content = c;
		this.paint = (ScreenPainter painter) {
			painter.outlineColor = Color.black;
			painter.fillColor = windowBackgroundColor;
			painter.drawRectangle(Point(0, 0), width, height);
			painter.drawText(Point(4, 0), content, Point(width, height));
		};
	}

	override int maxHeight() { return Window.lineHeight; }
	override int minHeight() { return Window.lineHeight; }

}

class Menu : Widget {
	void remove() {
		foreach(i, child; parentWindow.children)
			if(child is this) {
				parentWindow.children = parentWindow.children[0 .. i] ~ parentWindow.children[i + 1 .. $];
				break;
			}
		parentWindow.redraw();

		parentWindow.removeEventListener("mousedown", &remove);
	}

	void popup(Widget parent) {
		assert(parentWindow !is null);
		auto pos = getChildPositionRelativeToParentOrigin(parent);
		this.x = pos[0];
		this.y = pos[1] + parent.height;
		this.width = parent.width;
		if(this.children.length)
			this.height = this.children.length * this.children[0].maxHeight();
		else
			this.height = 4;
		this.recomputeChildLayout();

		this.paint = (ScreenPainter painter) {
			painter.outlineColor = Color.black;
			painter.fillColor = Color(190, 190, 190);
			painter.drawRectangle(Point(0, 0), width, height);
		};

		parentWindow.children ~= this;

		parentWindow.addEventListener("mousedown", &remove);

		defaultEventHandlers["mousedown"] = (Widget _this, Event ev) {
			ev.stopPropagation();
		};

		foreach(child; children)
			child.parentWindow = this.parentWindow;

		this.show();
	}

	MenuItem[] items;

	MenuItem addItem(MenuItem item) {
		addChild(item);
		items ~= item;
		version(win32_widgets) {
			MainWindow.menuCommandMapping[MainWindow.lastId + 1] = item;
			AppendMenu(handle, MF_STRING, ++MainWindow.lastId, toStringz(item.label));
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
	} else {
		this(string label, Widget parent = null) {
			super(parent);
			this.label = label;
			this.paint = (ScreenPainter painter) {
				painter.outlineColor = Color.black;
				painter.fillColor = Color.transparent;
				painter.drawRectangle(Point(0, 0), width, height);
			};
		}
	}

	override int maxHeight() { return Window.lineHeight; }
	override int minHeight() { return Window.lineHeight; }
}

class MenuItem : MouseActivatedWidget {
	Menu submenu;

	string label;

	override int maxHeight() { return Window.lineHeight; }
	override int minWidth() { return Window.lineHeight * label.length; }
	override int maxWidth() { return Window.lineHeight / 2 * label.length; }
	this(string lbl, Window parent = null) {
		super(parent);
		label = lbl;
		version(win32_widgets) {} else
		this.paint = (ScreenPainter painter) {
			if(isHovering)
				painter.outlineColor = Color.blue;
			else
				painter.outlineColor = Color.black;
			painter.drawText(Point(0, 0), label, Point(width, height), TextAlignment.Center);
		};

		defaultEventHandlers["click"] = (Widget w, Event ev) {
			auto event = new Event("triggered", this);
			event.dispatch();
		};
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
else
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

		defaultEventHandlers["click"] = (Widget w, Event ev) {
			auto event = new Event("triggered", this);
			event.dispatch();
		};
	}
}


class Checkbox : MouseActivatedWidget {

	override int maxHeight() { return 16; }
	override int minHeight() { return 16; }

	version(win32_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "button", label, BS_AUTOCHECKBOX);
	}
	else
	this(string label, Widget parent = null) {
		super(parent);

		this.paint = (ScreenPainter painter) {
			painter.outlineColor = Color.black;
			painter.fillColor = Color.white;
			painter.drawRectangle(Point(2, 2), height - 2, height - 2);

			if(isChecked) {
				painter.pen = Pen(Color.black, 2);
				// I'm using height so the checkbox is square
				painter.drawLine(Point(6, 6), Point(height - 4, height - 4));
				painter.drawLine(Point(height-4, 6), Point(6, height - 4));

				painter.pen = Pen(Color.black, 1);
			}

			painter.drawText(Point(height + 4, 0), label, Point(width, height), TextAlignment.Left | TextAlignment.VerticalCenter);
		};

		defaultEventHandlers["click"] = delegate (Widget _this, Event ev) {
			isChecked = !isChecked;

			auto event = new Event("change", this);
			event.dispatch();

			redraw();
		};
	}
}

class MutuallyExclusiveGroup {
	MouseActivatedWidget[] members;

	Radiobox addMember(Radiobox w) {
		members ~= w;
		w.group = this;
		return w;
	}

	void uncheckOthers(Widget checked) {
		foreach(member; members)
			if(member !is checked) {
				member.isChecked = false;
				member.redraw();
			}
	}
}

class Radiobox : MouseActivatedWidget {
	MutuallyExclusiveGroup group;

	override int maxHeight() { return 16; }
	override int minHeight() { return 16; }

	version(win32_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "button", label, BS_AUTORADIOBUTTON);
	}
	else
	this(string label, Widget parent = null) {
		super(parent);
		height = 16;
		width = height + 4 + label.length * 16;

		this.paint = (ScreenPainter painter) {
			painter.outlineColor = Color.black;
			painter.fillColor = Color.white;
			painter.drawEllipse(Point(2, 2), Point(height - 2, height - 2));

			if(isChecked) {
				painter.outlineColor = Color.black;
				painter.fillColor = Color.black;
				// I'm using height so the checkbox is square
				painter.drawEllipse(Point(5, 5), Point(height - 5, height - 5));
			}

			painter.drawText(Point(height + 4, 0), label, Point(width, height), TextAlignment.Left | TextAlignment.VerticalCenter);
		};

		defaultEventHandlers["click"] = delegate (Widget _this, Event ev) {
			isChecked = true;

			if(group !is null)
				group.uncheckOthers(this);

			auto event = new Event("change", this);
			event.dispatch();

			redraw();
		};
	}
}


class Button : MouseActivatedWidget {
	Color normalBgColor;
	Color hoverBgColor;
	Color depressedBgColor;

	version(win32_widgets) {} else
	Color currentButtonColor() {
		if(isHovering) {
			return isDepressed ? depressedBgColor : hoverBgColor;
		}

		return normalBgColor;
	}

	version(win32_widgets)
	this(string label, Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "button", label, BS_PUSHBUTTON);

		// FIXME: use ideal button size instead
		width = 50;
		height = 30;
	}
	else

	this(string label, Widget parent = null) {
		super(parent);
		normalBgColor = Color(192, 192, 192);
		hoverBgColor = Color(215, 215, 215);
		depressedBgColor = Color(160, 160, 160);

		width = 50;
		height = 30;

		this.paint = (ScreenPainter painter) {
			painter.outlineColor = Color.black;
			painter.fillColor = currentButtonColor;
			painter.drawRectangle(Point(0, 0), width, height);


			painter.outlineColor = (isHovering && isDepressed) ? Color(128, 128, 128) : Color.white;
			painter.drawLine(Point(0, 0), Point(width, 0));
			painter.drawLine(Point(0, 0), Point(0, height - 1));

			painter.outlineColor = (isHovering && isDepressed) ? Color.white : Color(128, 128, 128);
			painter.drawLine(Point(width - 1, 1), Point(width - 1, height - 1));
			painter.drawLine(Point(1, height - 1), Point(width - 1, height - 1));


			painter.outlineColor = Color.black;
			painter.drawText(Point(0, 0), label, Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);
		};
	}
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


class TextEdit : Widget {
	override int heightStretchiness() { return 3; }
	override int widthStretchiness() { return 3; }

	version(win32_widgets)
	this(Widget parent = null) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "edit", "", 
			WS_BORDER|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_WANTRETURN|ES_AUTOHSCROLL|ES_AUTOVSCROLL);
	}
	else
	this(Widget parent = null) {
		super(parent);

		this.paint = (ScreenPainter painter) {
			painter.fillColor = Color.white;
			painter.drawRectangle(Point(0, 0), width, height);

			painter.outlineColor = Color.black;
			painter.drawText(Point(4, 4), content, Point(width - 4, height - 4));
		};

		defaultEventHandlers["click"] = delegate (Widget _this, Event ev) {
			this.focus();
		};

		defaultEventHandlers["char"] = delegate (Widget _this, Event ev) {
			content = content() ~ cast(char) ev.character;
			redraw();
		};

		//super();
	}

	string _content;
	@property string content() { return _content; }
	@property void content(string s) {
		_content = s;
		version(win32_widgets)
			SetWindowTextA(hwnd, toStringz(s));
		else
			redraw();
	}

	void focus() {
		assert(parentWindow !is null);
		parentWindow.focusedWidget = this;
	}
}



class MessageBox : Window {
	this(string message) {
		super(300, 100);

		this.paint = (ScreenPainter painter) {
			painter.fillColor = Color(192, 192, 192);
			painter.drawRectangle(Point(0, 0), this.width, this.height);

			painter.outlineColor = Color.black;
			painter.drawText(Point(0, 0), message, Point(width, height / 2), TextAlignment.Center | TextAlignment.VerticalCenter);
		};

		auto button = new Button("OK", this);
		button. x = this.width / 2 - button.width / 2;
		button.y = height - (button.height + 10);
		button.addEventListener(EventType.click, () {
			close();
		});

		button.registerMovement();

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
			foreach(ref evt; capturingEventHandlers[event])
				if(evt is handler) evt = null;
		} else {
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

	keydown = "keydown",
	keyup = "keyup",
	// char = "char",

	focus = "focus",
	blur = "blur",

	triggered = "triggered",
}

class Event {
	this(string eventName, Widget target) {
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

	private bool defaultPrevented;
	private bool propagationStopped;
	private string eventName;

	Widget srcElement;
	alias srcElement target;

	Widget relatedTarget;

	int clientX;
	int clientY;

	int button;
	dchar character;

	private bool isBubbling;

	/// this sends it only to the target. If you want propagation, use dispatch() instead.
	void sendDirectly() {
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

			if(!defaultPrevented)
				if(eventName in e.defaultEventHandlers)
					e.defaultEventHandlers[eventName](e, this);

			if(propagationStopped)
				break;
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

Widget widgetAtPoint(Widget starting, int x, int y) {
	assert(starting !is null);
	auto child = starting.getChildAtPosition(x, y);
	while(child) {
		starting = child;
		x -= child.x;
		y -= child.y;
		child = starting.widgetAtPoint(x, y);//starting.getChildAtPosition(x, y);
		if(child is starting)
			break;
	}
	return starting;
}


version(Windows) {
	pragma(lib, "comctl32");

	static this() {
		INITCOMMONCONTROLSEX ic;
		ic.dwSize = cast(DWORD) ic.sizeof;
		ic.dwICC = ICC_WIN95_CLASSES | ICC_BAR_CLASSES | ICC_PROGRESS_CLASS | ICC_COOL_CLASSES;
		InitCommonControlsEx(&ic);
	}


	// everything from here is just win32 headers copy pasta
private:
extern(Windows):

	alias HANDLE HMENU;
	HMENU CreateMenu();
	bool SetMenu(HWND, HMENU);
	HMENU CreatePopupMenu();
	BOOL AppendMenuA(HMENU, uint, UINT_PTR, LPCTSTR);
	alias AppendMenuA AppendMenu;
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
	BYTE  bReserved[2]; // FIXME: isn't that different on 64 bit?
	DWORD dwData;
	int   iString;
}

	enum {
		TB_ADDBUTTONSA   = WM_USER + 20,
		TB_INSERTBUTTONA = WM_USER + 21
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
        ICC_COOL_CLASSES     = 1024
}

	enum WM_USER = 1024;
	enum SB_SETTEXT = WM_USER + 1; // SET TEXT A. It is +11 for W
}
