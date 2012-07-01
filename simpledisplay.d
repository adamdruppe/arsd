module simpledisplay;
/*
	Stuff to add:

	Pens and brushes?
	Maybe a global event loop?

	Mouse deltas
	Key items
*/

version(linux)
	version = X11;
version(OSX)
	version = X11;
version(FreeBSD)
	version = X11;
version(Solaris)
	version = X11;

import std.exception;
import core.thread;
import std.string; // FIXME: move to drawText X11 on next dmd

import std.stdio;

import arsd.color; // no longer stand alone... :-( but i need a common type for this to work with images easily.

struct Point {
	int x;
	int y;
}

struct Size {
	int width;
	int height;
}


struct KeyEvent {

}

struct MouseEvent {
	int type; // movement, press, release, double click

	int x;
	int y;

	int button;
	int buttonFlags;
}

struct MouseClickEvent {

}

struct MouseMoveEvent {

}


struct Pen {
	Color color;
	int width;
	Style style;
/+
// From X.h

#define LineSolid		0
#define LineOnOffDash		1
#define LineDoubleDash		2
       LineDou-        The full path of the line is drawn, but the
       bleDash         even dashes are filled differently from the
                       odd dashes (see fill-style) with CapButt
                       style used where even and odd dashes meet.



/* capStyle */

#define CapNotLast		0
#define CapButt			1
#define CapRound		2
#define CapProjecting		3

/* joinStyle */

#define JoinMiter		0
#define JoinRound		1
#define JoinBevel		2

/* fillStyle */

#define FillSolid		0
#define FillTiled		1
#define FillStippled		2
#define FillOpaqueStippled	3


+/
	enum Style {
		Solid,
		Dashed
	}
}


class Image {
	this(int width, int height) {
		this.width = width;
		this.height = height;

		impl.createImage(width, height);
	}

	this(Size size) {
		this(size.width, size.height);
	}

	~this() {
		impl.dispose();
	}

	void putPixel(int x, int y, Color c) {
		if(x < 0 || x >= width)
			return;
		if(y < 0 || y >= height)
			return;

		impl.setPixel(x, y, c);
	}

	void opIndexAssign(Color c, int x, int y) {
		putPixel(x, y, c);
	}

	immutable int width;
	immutable int height;
    private:
	mixin NativeImageImplementation!() impl;
}

void displayImage(Image image, SimpleWindow win = null) {
	if(win is null) {
		win = new SimpleWindow(image);
		{
			auto p = win.draw;
			p.drawImage(Point(0, 0), image);
		}
		win.eventLoop(0,
			(int) {
				win.close();
			} );
	} else {
		win.image = image;
	}
}

/// Most functions use the outlineColor instead of taking a color themselves.
struct ScreenPainter {
	SimpleWindow window;
	this(SimpleWindow window, NativeWindowHandle handle) {
		this.window = window;
		if(window.activeScreenPainter !is null) {
			impl = window.activeScreenPainter;
			impl.referenceCount++;
		//	writeln("refcount ++ ", impl.referenceCount);
		} else {
			impl = new ScreenPainterImplementation;
			impl.window = window;
			impl.create(handle);
			impl.referenceCount = 1;
			window.activeScreenPainter = impl;
		//	writeln("constructed");
		}
	}

	~this() {
		impl.referenceCount--;
		//writeln("refcount -- ", impl.referenceCount);
		if(impl.referenceCount == 0) {
			//writeln("destructed");
			impl.dispose();
			window.activeScreenPainter = null;
		}
	}

	// @disable this(this) { } // compiler bug? the linker is bitching about it beind defined twice

	this(this) {
		impl.referenceCount++;
		//writeln("refcount ++ ", impl.referenceCount);
	}

	@property void outlineColor(Color c) {
		impl.outlineColor(c);
	}

	@property void fillColor(Color c) {
		impl.fillColor(c);
	}

	void updateDisplay() {
		// FIXME
	}

	void clear() {
		fillColor = Color(255, 255, 255);
		drawRectangle(Point(0, 0), window.width, window.height);
	}

	void drawImage(Point upperLeft, Image i) {
		impl.drawImage(upperLeft.x, upperLeft.y, i);
	}

	void drawText(Point upperLeft, string text) {
		// bounding rect other sizes are ignored for now
		impl.drawText(upperLeft.x, upperLeft.y, 0, 0, text);
	}

	void drawPixel(Point where) {
		impl.drawPixel(where.x, where.y);
	}


	void drawLine(Point starting, Point ending) {
		impl.drawLine(starting.x, starting.y, ending.x, ending.y);
	}

	void drawRectangle(Point upperLeft, int width, int height) {
		impl.drawRectangle(upperLeft.x, upperLeft.y, width, height);
	}

	/// Arguments are the points of the bounding rectangle
	void drawEllipse(Point upperLeft, Point lowerRight) {
		impl.drawEllipse(upperLeft.x, upperLeft.y, lowerRight.x, lowerRight.y);
	}

	void drawArc(Point upperLeft, int width, int height, int start, int finish) {
		impl.drawArc(upperLeft.x, upperLeft.y, width, height, start, finish);
	}

	void drawPolygon(Point[] vertexes) {
		impl.drawPolygon(vertexes);
	}


	// and do a draw/fill in a single call maybe. Windows can do it... but X can't, though it could do two calls.

	//mixin NativeScreenPainterImplementation!() impl;


	// HACK: if I mixin the impl directly, it won't let me override the copy
	// constructor! The linker complains about there being multiple definitions.
	// I'll make the best of it and reference count it though.
	ScreenPainterImplementation* impl;
}

	// HACK: I need a pointer to the implementation so it's separate
	struct ScreenPainterImplementation {
		SimpleWindow window;
		int referenceCount;
		mixin NativeScreenPainterImplementation!();
	}

class SimpleWindow {
	int width;
	int height;

	// HACK: making the best of some copy constructor woes with refcounting
	private ScreenPainterImplementation* activeScreenPainter;

	/// Creates a window based on the given image. It's client area
	/// width and height is equal to the image. (A window's client area
	/// is the drawable space inside; it excludes the title bar, etc.)
	this(Image image, string title = null) {
		this.backingImage = image;
		this(image.width, image.height, title);
	}

	this(Size size, string title = null) {
		this(size.width, size.height, title);
	}

	this(int width, int height, string title = null) {
		this.width = width;
		this.height = height;
		impl.createWindow(width, height, title is null ? "D Application" : title);
	}

	Image backingImage;

	~this() {
		impl.dispose();
	}

	/// Closes the window and terminates it's event loop.
	void close() {
		impl.closeWindow();
	}

	/// The event loop automatically returns when the window is closed
	/// pulseTimeout is given in milliseconds.
	final int eventLoop(T...)(
		long pulseTimeout,    /// set to zero if you don't want a pulse. Note: don't set it too big, or user input may not be processed in a timely manner. I suggest something < 150.
		T eventHandlers) /// delegate list like std.concurrency.receive
	{

		// FIXME: add more events
		foreach(handler; eventHandlers) {
			static if(__traits(compiles, handleKeyEvent = handler)) {
				handleKeyEvent = handler;
			} else static if(__traits(compiles, handleCharEvent = handler)) {
				handleCharEvent = handler;
			} else static if(__traits(compiles, handlePulse = handler)) {
				handlePulse = handler;
			} else static if(__traits(compiles, handleMouseEvent = handler)) {
				handleMouseEvent = handler;
			} else static assert(0, "I can't use this event handler " ~ typeof(handler).stringof);
		}


		return impl.eventLoop(pulseTimeout);
	}

	ScreenPainter draw() {
		return impl.getPainter();
	}

	@property void image(Image i) {
		backingImage = i;
		version(Windows) {
			RECT r;
			r.right = i.width;
			r.bottom = i.height;

			InvalidateRect(hwnd, &r, false);
		}
		version(X11) {
			if(!destroyed)
			XPutImage(display, cast(Drawable) window, gc, backingImage.handle, 0, 0, 0, 0, backingImage.width, backingImage.height);
		}
	}

	/// What follows are the event handlers. These are set automatically
	/// by the eventLoop function, but are still public so you can change
	/// them later.

	/// Handles a low-level keyboard event
	void delegate(int key) handleKeyEvent;

	/// Handles a higher level keyboard event - c is the character just pressed.
	void delegate(dchar c) handleCharEvent;

	void delegate() handlePulse;

	void delegate(MouseEvent) handleMouseEvent;

	/** Platform specific - handle any native messages this window gets.
	  *
	  * Note: this is called *in addition to* other event handlers.

	  * On Windows, it takes the form of void delegate(UINT, WPARAM, LPARAM).

	  * On X11, it takes the form of void delegate(XEvent).
	**/
	NativeEventHandler handleNativeEvent;

  private:
	mixin NativeSimpleWindowImplementation!() impl;
}

/* Additional utilities */


import std.conv;
import std.math;

Color fromHsl(real h, real s, real l) {
	h = h % 360;

	real C = (1 - abs(2 * l - 1)) * s;

	real hPrime = h / 60;

	real X = C * (1 - abs(hPrime % 2 - 1));

	real r, g, b;

	if(std.math.isNaN(h))
		r = g = b = 0;
	else if (hPrime >= 0 && hPrime < 1) {
		r = C;
		g = X;
		b = 0;
	} else if (hPrime >= 1 && hPrime < 2) {
		r = X;
		g = C;
		b = 0;
	} else if (hPrime >= 2 && hPrime < 3) {
		r = 0;
		g = C;
		b = X;
	} else if (hPrime >= 3 && hPrime < 4) {
		r = 0;
		g = X;
		b = C;
	} else if (hPrime >= 4 && hPrime < 5) {
		r = X;
		g = 0;
		b = C;
	} else if (hPrime >= 5 && hPrime < 6) {
		r = C;
		g = 0;
		b = X;
	}

	real m = l - C / 2;

	r += m;
	g += m;
	b += m;

	return Color(
		cast(ubyte)(r * 255),
		cast(ubyte)(g * 255),
		cast(ubyte)(b * 255),
		255);
}



/* ********** What follows is the system-specific implementations *********/
version(Windows) {
	import std.string;

	SimpleWindow[HWND] windowObjects;

	alias void delegate(UINT, WPARAM, LPARAM) NativeEventHandler;
	alias HWND NativeWindowHandle;

	extern(Windows)
	int WndProc(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) {
		if(hWnd in windowObjects) {
			auto window = windowObjects[hWnd];
			return window.windowProcedure(hWnd, iMessage, wParam, lParam);
		} else {
			return DefWindowProc(hWnd, iMessage, wParam, lParam);
		}
	}

	mixin template NativeScreenPainterImplementation() {
		HDC hdc;
		HWND hwnd;
		HDC windowHdc;
		HBITMAP oldBmp;

		void create(NativeWindowHandle window) {
			auto buffer = this.window.impl.buffer;
			hwnd = window;
			windowHdc = GetDC(hwnd);

			hdc = CreateCompatibleDC(windowHdc);
			oldBmp = SelectObject(hdc, buffer);

			// X doesn't draw a text background, so neither should we
			SetBkMode(hdc, TRANSPARENT);
		}

		// just because we can on Windows...
		//void create(Image image);

		void dispose() {
			// FIXME: this.window.width/height is probably wrong
			BitBlt(windowHdc, 0, 0, this.window.width, this.window.height, hdc, 0, 0, SRCCOPY);

			ReleaseDC(hwnd, windowHdc);

			if(originalPen !is null)
				SelectObject(hdc, originalPen);
			if(currentPen !is null)
				DeleteObject(currentPen);
			if(originalBrush !is null)
				SelectObject(hdc, originalBrush);
			if(currentBrush !is null)
				DeleteObject(currentBrush);

			SelectObject(hdc, oldBmp);

			DeleteDC(hdc);
		}

		HPEN originalPen;
		HPEN currentPen;

		Color _foreground;
		@property void outlineColor(Color c) {
			_foreground = c;
			HPEN pen;
			if(c.a == 0) {
				pen = GetStockObject(NULL_PEN);
			} else {
				pen = CreatePen(PS_SOLID, 1, RGB(c.r, c.g, c.b));
			}
			auto orig = SelectObject(hdc, pen);
			if(originalPen is null)
				originalPen = orig;

			if(currentPen !is null)
				DeleteObject(currentPen);

			currentPen = pen;

			// the outline is like a foreground since it's done that way on X
			SetTextColor(hdc, RGB(c.r, c.g, c.b));
		}

		HBRUSH originalBrush;
		HBRUSH currentBrush;
		@property void fillColor(Color c) {
			HBRUSH brush;
			if(c.a == 0) {
				brush = GetStockObject(HOLLOW_BRUSH);
			} else {
				brush = CreateSolidBrush(RGB(c.r, c.g, c.b));
			}
			auto orig = SelectObject(hdc, brush);
			if(originalBrush is null)
				originalBrush = orig;

			if(currentBrush !is null)
				DeleteObject(currentBrush);

			currentBrush = brush;

			// background color is NOT set because X doesn't draw text backgrounds
			//   SetBkColor(hdc, RGB(255, 255, 255));
		}

		void drawImage(int x, int y, Image i) {
			BITMAP bm;

			HDC hdcMem = CreateCompatibleDC(hdc);
			HBITMAP hbmOld = SelectObject(hdcMem, i.handle);

			GetObject(i.handle, bm.sizeof, &bm);

			BitBlt(hdc, x, y, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, SRCCOPY);

			SelectObject(hdcMem, hbmOld);
			DeleteDC(hdcMem);
		}

		void drawText(int x, int y, int x2, int y2, string text) {
			/*
			RECT rect;
			rect.left = x;
			rect.top = y;
			rect.right = x2;
			rect.bottom = y2;

			DrawText(hdc, text.ptr, text.length, &rect, DT_LEFT);
			*/

			TextOut(hdc, x, y, text.ptr, text.length);
		}

		void drawPixel(int x, int y) {
			SetPixel(hdc, x, y, RGB(_foreground.r, _foreground.g, _foreground.b));
		}

		// The basic shapes, outlined

		void drawLine(int x1, int y1, int x2, int y2) {
			MoveToEx(hdc, x1, y1, null);
			LineTo(hdc, x2, y2);
		}

		void drawRectangle(int x, int y, int width, int height) {
			Rectangle(hdc, x, y, x + width, y + height);
		}

		/// Arguments are the points of the bounding rectangle
		void drawEllipse(int x1, int y1, int x2, int y2) {
			Ellipse(hdc, x1, y1, x2, y2);
		}

		void drawArc(int x1, int y1, int width, int height, int start, int finish) {
			// FIXME: start X, start Y, end X, end Y
			Arc(hdc, x1, y1, x1 + width, y1 + height, 0, 0, 0, 0);
		}

		void drawPolygon(Point[] vertexes) {
			POINT[] points;
			points.length = vertexes.length;

			foreach(i, p; vertexes) {
				points[i].x = p.x;
				points[i].y = p.y;
			}

			Polygon(hdc, points.ptr, points.length);
		}
	}


	// Mix this into the SimpleWindow class
	mixin template NativeSimpleWindowImplementation() {
		ScreenPainter getPainter() {
			return ScreenPainter(this, hwnd);
		}

		HBITMAP buffer;

		void createWindow(int width, int height, string title) {
			const char* cn = "DSimpleWindow";

			HINSTANCE hInstance = cast(HINSTANCE) GetModuleHandle(null);

			WNDCLASS wc;

			wc.cbClsExtra = 0;
			wc.cbWndExtra = 0;
			wc.hbrBackground = cast(HBRUSH) GetStockObject(WHITE_BRUSH);
			wc.hCursor = LoadCursor(null, IDC_ARROW);
			wc.hIcon = LoadIcon(hInstance, null);
			wc.hInstance = hInstance;
			wc.lpfnWndProc = &WndProc;
			wc.lpszClassName = cn;
			wc.style = CS_HREDRAW | CS_VREDRAW;
			if(!RegisterClass(&wc))
				throw new Exception("RegisterClass");

			hwnd = CreateWindow(cn, toStringz(title), WS_OVERLAPPEDWINDOW,
				CW_USEDEFAULT, CW_USEDEFAULT, width, height,
				null, null, hInstance, null);

			windowObjects[hwnd] = this;

			HDC hdc = GetDC(hwnd);
			buffer = CreateCompatibleBitmap(hdc, width, height);

			auto hdcBmp = CreateCompatibleDC(hdc);
			// make sure it's filled with a blank slate
			auto oldBmp = SelectObject(hdcBmp, buffer);
			auto oldBrush = SelectObject(hdcBmp, GetStockObject(WHITE_BRUSH));
			Rectangle(hdcBmp, 0, 0, width, height);
			SelectObject(hdcBmp, oldBmp);
			SelectObject(hdcBmp, oldBrush);
			DeleteDC(hdcBmp);

			ReleaseDC(hwnd, hdc);

			// We want the window's client area to match the image size
			RECT rcClient, rcWindow;
			POINT ptDiff;
			GetClientRect(hwnd, &rcClient);
			GetWindowRect(hwnd, &rcWindow);
			ptDiff.x = (rcWindow.right - rcWindow.left) - rcClient.right;
			ptDiff.y = (rcWindow.bottom - rcWindow.top) - rcClient.bottom;
			MoveWindow(hwnd,rcWindow.left, rcWindow.top, width + ptDiff.x, height + ptDiff.y, true);

			ShowWindow(hwnd, SW_SHOWNORMAL);
		}


		void dispose() {
			DeleteObject(buffer);
		}

		void closeWindow() {
			DestroyWindow(hwnd);
		}

		HWND hwnd;

		// the extern(Windows) wndproc should just forward to this
		int windowProcedure(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam) {
			assert(hwnd is this.hwnd);

			MouseEvent mouse;
			switch(msg) {
				case WM_CHAR:
					wchar c = cast(wchar) wParam;
					if(handleCharEvent)
						handleCharEvent(cast(dchar) c);
				break;
				case WM_MOUSEMOVE:

				case WM_LBUTTONDOWN:
				case WM_LBUTTONUP:
				case WM_LBUTTONDBLCLK:

				case WM_RBUTTONDOWN:
				case WM_RBUTTONUP:
				case WM_RBUTTONDBLCLK:

				case WM_MBUTTONDOWN:
				case WM_MBUTTONUP:
				case WM_MBUTTONDBLCLK:
					mouse.type = 0;
					mouse.x = LOWORD(lParam);
					mouse.y = HIWORD(lParam);
					mouse.buttonFlags = wParam;

					if(handleMouseEvent)
						handleMouseEvent(mouse);
				break;
				case WM_KEYDOWN:
					if(handleKeyEvent)
						handleKeyEvent(wParam);
				break;
				case WM_CLOSE:
				case WM_DESTROY:
					PostQuitMessage(0);
				break;
				case WM_PAINT: {
					BITMAP bm;
					PAINTSTRUCT ps;

					HDC hdc = BeginPaint(hwnd, &ps);

/*
					if(backingImage !is null) {
						HDC hdcMem = CreateCompatibleDC(hdc);
						HBITMAP hbmOld = SelectObject(hdcMem, backingImage.handle);

						GetObject(backingImage.handle, bm.sizeof, &bm);

						BitBlt(hdc, 0, 0, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, SRCCOPY);

						SelectObject(hdcMem, hbmOld);
						DeleteDC(hdcMem);
					}
*/
					HDC hdcMem = CreateCompatibleDC(hdc);
					HBITMAP hbmOld = SelectObject(hdcMem, buffer);

					GetObject(buffer, bm.sizeof, &bm);

					BitBlt(hdc, 0, 0, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, SRCCOPY);

					SelectObject(hdcMem, hbmOld);
					DeleteDC(hdcMem);


					EndPaint(hwnd, &ps);
				} break;
				  default:
					return DefWindowProc(hwnd, msg, wParam, lParam);
			}
			 return 0;

		}

		int eventLoop(long pulseTimeout) {
			MSG message;
			int ret;

			if(pulseTimeout) {
				bool done = false;
				while(!done) {
					while(!done && PeekMessage(&message, hwnd, 0, 0, PM_NOREMOVE)) {
						ret = GetMessage(&message, hwnd, 0, 0);
						if(ret == 0)
							done = true;

						TranslateMessage(&message);
						DispatchMessage(&message);
					}

					if(!done && handlePulse !is null)
						handlePulse();
					Thread.sleep(pulseTimeout * 10000);
				}
			} else {
				while((ret = GetMessage(&message, hwnd, 0, 0)) != 0) {
					if(ret == -1)
						throw new Exception("GetMessage failed");
					TranslateMessage(&message);
					DispatchMessage(&message);
				}
			}

			return message.wParam;
		}
	}

	mixin template NativeImageImplementation() {
		HBITMAP handle;
		byte* rawData;

		void setPixel(int x, int y, Color c) {
			auto itemsPerLine = ((cast(int) width * 3 + 3) / 4) * 4;
			// remember, bmps are upside down
			auto offset = itemsPerLine * (height - y - 1) + x * 3;

			rawData[offset + 0] = c.b;
			rawData[offset + 1] = c.g;
			rawData[offset + 2] = c.r;
		}

		void createImage(int width, int height) {
			BITMAPINFO infoheader;
			infoheader.bmiHeader.biSize = infoheader.bmiHeader.sizeof;
			infoheader.bmiHeader.biWidth = width;
			infoheader.bmiHeader.biHeight = height;
			infoheader.bmiHeader.biPlanes = 1;
			infoheader.bmiHeader.biBitCount = 24;
			infoheader.bmiHeader.biCompression = BI_RGB;

			handle = enforce(CreateDIBSection(
				null,
				&infoheader,
				DIB_RGB_COLORS,
				cast(void**) &rawData,
				null,
				0));

		}

		void dispose() {
			DeleteObject(handle);
		}
	}

	enum KEY_ESCAPE = 27;
}
version(X11) {

	alias void delegate(XEvent) NativeEventHandler;
	alias Window NativeWindowHandle;

	enum KEY_ESCAPE = 9;
	import core.stdc.stdlib;

	mixin template NativeScreenPainterImplementation() {
		Display* display;
		Drawable d;
		Drawable destiny;
		GC gc;

		void create(NativeWindowHandle window) {
			this.display = XDisplayConnection.get();

    			auto buffer = this.window.impl.buffer;

			this.d = cast(Drawable) buffer;
			this.destiny = cast(Drawable) window;

			auto dgc = DefaultGC(display, DefaultScreen(display));

			this.gc = XCreateGC(display, d, 0, null);

			XCopyGC(display, dgc, 0xffffffff, this.gc);

		}

		void dispose() {
    			auto buffer = this.window.impl.buffer;

			// FIXME: this.window.width/height is probably wrong

			// src x,y     then dest x, y
			XCopyArea(display, d, destiny, gc, 0, 0, this.window.width, this.window.height, 0, 0);

			XFreeGC(display, gc);
		}

		bool backgroundIsNotTransparent = true;
		bool foregroundIsNotTransparent = true;

		Color _outlineColor;
		Color _fillColor;

		@property void outlineColor(Color c) {
			_outlineColor = c;
			if(c.a == 0) {
				foregroundIsNotTransparent = false;
				return;
			}

			foregroundIsNotTransparent = true;

			XSetForeground(display, gc,
				cast(uint) c.r << 16 |
				cast(uint) c.g << 8 |
				cast(uint) c.b);
		}

		@property void fillColor(Color c) {
			_fillColor = c;
			if(c.a == 0) {
				backgroundIsNotTransparent = false;
				return;
			}

			backgroundIsNotTransparent = true;

			XSetBackground(display, gc,
				cast(uint) c.r << 16 |
				cast(uint) c.g << 8 |
				cast(uint) c.b);

		}

		void swapColors() {
			auto tmp = _fillColor;
			fillColor = _outlineColor;
			outlineColor = tmp;
		}

		void drawImage(int x, int y, Image i) {
			// source x, source y
			XPutImage(display, d, gc, i.handle, 0, 0, x, y, i.width, i.height);
		}

		void drawText(int x, int y, int x2, int y2, string text) {
			foreach(line; text.split("\n")) {
				XDrawString(display, d, gc, x, y + 12, line.ptr, cast(int) line.length);
				y += 16;
			}
		}

		void drawPixel(int x, int y) {
			XDrawPoint(display, d, gc, x, y);
		}

		// The basic shapes, outlined

		void drawLine(int x1, int y1, int x2, int y2) {
			if(foregroundIsNotTransparent)
				XDrawLine(display, d, gc, x1, y1, x2, y2);
		}

		void drawRectangle(int x, int y, int width, int height) {
			if(backgroundIsNotTransparent) {
				swapColors();
				XFillRectangle(display, d, gc, x, y, width, height);
				swapColors();
			}
			if(foregroundIsNotTransparent)
				XDrawRectangle(display, d, gc, x, y, width, height);
		}

		/// Arguments are the points of the bounding rectangle
		void drawEllipse(int x1, int y1, int x2, int y2) {
			drawArc(x1, y1, x2 - x1, y2 - y1, 0, 360 * 64);
		}

		// NOTE: start and finish are in units of degrees * 64
		void drawArc(int x1, int y1, int width, int height, int start, int finish) {
			if(backgroundIsNotTransparent) {
				swapColors();
				XFillArc(display, d, gc, x1, y1, width, height, start, finish);
				swapColors();
			}
			if(foregroundIsNotTransparent)
				XDrawArc(display, d, gc, x1, y1, width, height, start, finish);
		}

		void drawPolygon(Point[] vertexes) {
			XPoint[] points;
			points.length = vertexes.length;

			foreach(i, p; vertexes) {
				points[i].x = cast(short) p.x;
				points[i].y = cast(short) p.y;
			}

			if(backgroundIsNotTransparent) {
				swapColors();
				XFillPolygon(display, d, gc, points.ptr, cast(int) points.length, PolygonShape.Complex, CoordMode.CoordModeOrigin);
				swapColors();
			}
			if(foregroundIsNotTransparent) {
				XDrawLines(display, d, gc, points.ptr, cast(int) points.length, CoordMode.CoordModeOrigin);
			}
		}
	}


	class XDisplayConnection {
		private static Display* display;

		static Display* get() {
			if(display is null)
				display = enforce(XOpenDisplay(null));

			return display;
		}

		static void close() {
			XCloseDisplay(display);
			display = null;
		}
	}

	mixin template NativeImageImplementation() {
		XImage* handle;
		byte* rawData;

		void createImage(int width, int height) {
			auto display = XDisplayConnection.get();
			auto screen = DefaultScreen(display);

			// This actually needs to be malloc to avoid a double free error when XDestroyImage is called
			rawData = cast(byte*) malloc(width * height * 4);

			handle = XCreateImage(
				display,
				DefaultVisual(display, screen),
				24, // bpp
				ImageFormat.ZPixmap,
				0, // offset
				rawData,
				width, height,
				8 /* FIXME */, 4 * width); // padding, bytes per line
		}

		void dispose() {
			XDestroyImage(handle);
		}

		/*
		Color getPixel(int x, int y) {

		}
		*/

		void setPixel(int x, int y, Color c) {
			auto offset = (y * width + x) * 4;
			rawData[offset + 0] = c.b;
			rawData[offset + 1] = c.g;
			rawData[offset + 2] = c.r;
		}
	}

	mixin template NativeSimpleWindowImplementation() {
		GC gc;
		Window window;
		Display* display;

		Pixmap buffer;

		ScreenPainter getPainter() {
			return ScreenPainter(this, window);
		}

		void createWindow(int width, int height, string title) {
			display = XDisplayConnection.get();
			auto screen = DefaultScreen(display);

			window = XCreateSimpleWindow(
				display,
				RootWindow(display, screen),
				0, 0, // x, y
				width, height,
				1, // border width
				BlackPixel(display, screen), // border
				WhitePixel(display, screen)); // background

			XTextProperty windowName;
			windowName.value = title.ptr;
			windowName.encoding = XA_STRING;
			windowName.format = 8;
			windowName.nitems = cast(uint) title.length;

			XSetWMName(display, window, &windowName);

			buffer = XCreatePixmap(display, cast(Drawable) window, width, height, 24);

			gc = DefaultGC(display, screen);

			// clear out the buffer to get us started...
			XSetForeground(display, gc, WhitePixel(display, screen));
			XFillRectangle(display, cast(Drawable) buffer, gc, 0, 0, width, height);
			XSetForeground(display, gc, BlackPixel(display, screen));

			// This gives our window a close button
			Atom atom = XInternAtom(display, "WM_DELETE_WINDOW".ptr, true); // FIXME: does this need to be freed?
			XSetWMProtocols(display, window, &atom, 1);

			XMapWindow(display, window);

			XSelectInput(display, window,
				EventMask.ExposureMask |
				EventMask.KeyPressMask |
				EventMask.StructureNotifyMask
				| EventMask.PointerMotionMask // FIXME: not efficient
				| EventMask.ButtonPressMask
				| EventMask.ButtonReleaseMask
			);
		}

		void closeWindow() {
			XFreePixmap(display, buffer);
			XDestroyWindow(display, window);
		}

		void dispose() {
		}

		bool destroyed = false;

		int eventLoop(long pulseTimeout) {
			XEvent e;
			bool done = false;

			while (!done) {
			while(!done &&
				(pulseTimeout == 0 || (XPending(display) > 0)))
			{
				XNextEvent(display, &e);

				switch(e.type) {
				  case EventType.Expose:
				  	//if(backingImage !is null)
					//	XPutImage(display, cast(Drawable) window, gc, backingImage.handle, 0, 0, 0, 0, backingImage.width, backingImage.height);
					XCopyArea(display, cast(Drawable) buffer, cast(Drawable) window, gc, 0, 0, width, height, 0, 0);
				  break;
				  case EventType.ClientMessage: // User clicked the close button
				  case EventType.DestroyNotify:
					done = true;
					destroyed = true;
				  break;

				  case EventType.MotionNotify:
				  	MouseEvent mouse;
					auto event = e.xmotion;

					mouse.type = 0;
					mouse.x = event.x;
					mouse.y = event.y;
					mouse.buttonFlags = event.state;

					if(handleMouseEvent)
						handleMouseEvent(mouse);
				  break;
				  case EventType.ButtonPress:
				  case EventType.ButtonRelease:
				  	MouseEvent mouse;
					auto event = e.xbutton;

					mouse.type = e.type == EventType.ButtonPress ? 1 : 2;
					mouse.x = event.x;
					mouse.y = event.y;
					mouse.button = event.button;
					//mouse.buttonFlags = event.detail;

					if(handleMouseEvent)
						handleMouseEvent(mouse);
				  break;

				  case EventType.KeyPress:
					if(handleCharEvent)
						handleCharEvent(
							XKeycodeToKeysym(
								XDisplayConnection.get(),
								e.xkey.keycode,
								0)); // FIXME: we should check shift, etc. too, so it matches Windows' behavior better
				  	if(handleKeyEvent)
						handleKeyEvent(e.xkey.keycode);
				  break;
				  default:
				}
			}
				if(!done && pulseTimeout !=0) {
					if(handlePulse !is null)
						handlePulse();
					Thread.sleep(pulseTimeout * 10000);
				}
			}

			return 0;
		}
	}
}

/* *************************************** */
/*      Done with simpledisplay stuff      */
/* *************************************** */

// Necessary C library bindings follow

version(Windows) {
	import core.sys.windows.windows;

	pragma(lib, "gdi32");

	extern(Windows) {
		// The included D headers are incomplete, finish them here
		// enough that this module works.
		alias GetObjectA GetObject;
		alias GetMessageA GetMessage;
		alias PeekMessageA PeekMessage;
		alias TextOutA TextOut;
		alias DispatchMessageA DispatchMessage;
		alias GetModuleHandleA GetModuleHandle;
		alias LoadCursorA LoadCursor;
		alias LoadIconA LoadIcon;
		alias RegisterClassA RegisterClass;
		alias CreateWindowA CreateWindow;
		alias DefWindowProcA DefWindowProc;
		alias DrawTextA DrawText;

		bool MoveWindow(HWND hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
		HBITMAP CreateDIBSection(HDC, const BITMAPINFO*, uint, void**, HANDLE hSection, DWORD);
		bool BitBlt(HDC hdcDest, int nXDest, int nYDest, int nWidth, int nHeight, HDC hdcSrc, int nXSrc, int nYSrc, DWORD dwRop);
		bool DestroyWindow(HWND);
		int DrawTextA(HDC hDC, LPCTSTR lpchText, int nCount, LPRECT lpRect, UINT uFormat);
		bool Rectangle(HDC, int, int, int, int);
		bool Ellipse(HDC, int, int, int, int);
		bool Arc(HDC, int, int, int, int, int, int, int, int);
		bool Polygon(HDC, POINT*, int);
		HBRUSH CreateSolidBrush(COLORREF);

		HBITMAP CreateCompatibleBitmap(HDC, int, int);

		uint SetTimer(HWND, uint, uint, void*);
		bool KillTimer(HWND, uint);


		enum BI_RGB = 0;
		enum DIB_RGB_COLORS = 0;
		enum DT_LEFT = 0;
		enum TRANSPARENT = 1;

	}

}

else version(X11) {

// X11 bindings needed here
/*
	A little of this is from the bindings project on
	D Source and some of it is copy/paste from the C
	header.

	The DSource listing consistently used D's long
	where C used long. That's wrong - C long is 32 bit, so
	it should be int in D. I changed that here.

	Note:
	This isn't complete, just took what I needed for myself.
*/

pragma(lib, "X11");

extern(C):


KeySym XKeycodeToKeysym(
    Display*		/* display */,
    KeyCode		/* keycode */,
    int			/* index */
);

Display* XOpenDisplay(const char*);
int XCloseDisplay(Display*);


enum MappingType:int {
	MappingModifier		=0,
	MappingKeyboard		=1,
	MappingPointer		=2
}

/* ImageFormat -- PutImage, GetImage */
enum ImageFormat:int {
	XYBitmap	=0,	/* depth 1, XYFormat */
	XYPixmap	=1,	/* depth == drawable depth */
	ZPixmap	=2	/* depth == drawable depth */
}

enum ModifierName:int {
	ShiftMapIndex	=0,
	LockMapIndex	=1,
	ControlMapIndex	=2,
	Mod1MapIndex	=3,
	Mod2MapIndex	=4,
	Mod3MapIndex	=5,
	Mod4MapIndex	=6,
	Mod5MapIndex	=7
}

enum ButtonMask:int {
	Button1Mask	=1<<8,
	Button2Mask	=1<<9,
	Button3Mask	=1<<10,
	Button4Mask	=1<<11,
	Button5Mask	=1<<12,
	AnyModifier	=1<<15/* used in GrabButton, GrabKey */
}

enum KeyOrButtonMask:uint {
	ShiftMask	=1<<0,
	LockMask	=1<<1,
	ControlMask	=1<<2,
	Mod1Mask	=1<<3,
	Mod2Mask	=1<<4,
	Mod3Mask	=1<<5,
	Mod4Mask	=1<<6,
	Mod5Mask	=1<<7,
	Button1Mask	=1<<8,
	Button2Mask	=1<<9,
	Button3Mask	=1<<10,
	Button4Mask	=1<<11,
	Button5Mask	=1<<12,
	AnyModifier	=1<<15/* used in GrabButton, GrabKey */
}

enum ButtonName:int {
	Button1	=1,
	Button2	=2,
	Button3	=3,
	Button4	=4,
	Button5	=5
}

/* Notify modes */
enum NotifyModes:int
{
	NotifyNormal		=0,
	NotifyGrab			=1,
	NotifyUngrab		=2,
	NotifyWhileGrabbed	=3
}
const int NotifyHint	=1;	/* for MotionNotify events */

/* Notify detail */
enum NotifyDetail:int
{
	NotifyAncestor			=0,
	NotifyVirtual			=1,
	NotifyInferior			=2,
	NotifyNonlinear			=3,
	NotifyNonlinearVirtual	=4,
	NotifyPointer			=5,
	NotifyPointerRoot		=6,
	NotifyDetailNone		=7
}

/* Visibility notify */

enum VisibilityNotify:int
{
VisibilityUnobscured		=0,
VisibilityPartiallyObscured	=1,
VisibilityFullyObscured		=2
}


enum WindowStackingMethod:int
{
	Above		=0,
	Below		=1,
	TopIf		=2,
	BottomIf	=3,
	Opposite	=4
}

/* Circulation request */
enum CirculationRequest:int
{
	PlaceOnTop		=0,
	PlaceOnBottom	=1
}

enum PropertyNotification:int
{
	PropertyNewValue	=0,
	PropertyDelete		=1
}

enum ColorMapNotification:int
{
	ColormapUninstalled	=0,
	ColormapInstalled		=1
}


	struct _XPrivate {}
	struct _XrmHashBucketRec {}

	alias void* XPointer;
	alias void* XExtData;

	alias uint XID;

	alias XID Window;
	alias XID Drawable;
	alias XID Pixmap;

	alias uint Atom;
	alias bool Bool;
	alias Display XDisplay;

	alias int ByteOrder;
	alias uint Time;
	alias void ScreenFormat;

	struct XImage {
	    int width, height;			/* size of image */
	    int xoffset;				/* number of pixels offset in X direction */
	    ImageFormat format;		/* XYBitmap, XYPixmap, ZPixmap */
	    void *data;					/* pointer to image data */
	    ByteOrder byte_order;		/* data byte order, LSBFirst, MSBFirst */
	    int bitmap_unit;			/* quant. of scanline 8, 16, 32 */
	    int bitmap_bit_order;		/* LSBFirst, MSBFirst */
	    int bitmap_pad;			/* 8, 16, 32 either XY or ZPixmap */
	    int depth;					/* depth of image */
	    int bytes_per_line;			/* accelarator to next line */
	    int bits_per_pixel;			/* bits per pixel (ZPixmap) */
	    uint red_mask;	/* bits in z arrangment */
	    uint green_mask;
	    uint blue_mask;
	    XPointer obdata;			/* hook for the object routines to hang on */
	    struct f {				/* image manipulation routines */
			XImage* function(
				XDisplay* 			/* display */,
				Visual*				/* visual */,
				uint				/* depth */,
				int					/* format */,
				int					/* offset */,
				byte*				/* data */,
				uint				/* width */,
				uint				/* height */,
				int					/* bitmap_pad */,
				int					/* bytes_per_line */) create_image;
			int  function(XImage *)destroy_image;
			uint function(XImage *, int, int)get_pixel;
			int  function(XImage *, int, int, uint)put_pixel;
			XImage function(XImage *, int, int, uint, uint)sub_image;
			int function(XImage *, int)add_pixel;
		}
	}



/*
 * Definitions of specific events.
 */
struct XKeyEvent
{
	int type;			/* of event */
	uint serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window it is reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	KeyOrButtonMask state;	/* key or button mask */
	uint keycode;	/* detail */
	Bool same_screen;	/* same screen flag */
}
alias XKeyEvent XKeyPressedEvent;
alias XKeyEvent XKeyReleasedEvent;

struct XButtonEvent
{
	int type;		/* of event */
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window it is reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	KeyOrButtonMask state;	/* key or button mask */
	uint button;	/* detail */
	Bool same_screen;	/* same screen flag */
}
alias XButtonEvent XButtonPressedEvent;
alias XButtonEvent XButtonReleasedEvent;

struct XMotionEvent{
	int type;		/* of event */
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	KeyOrButtonMask state;	/* key or button mask */
	byte is_hint;		/* detail */
	Bool same_screen;	/* same screen flag */
}
alias XMotionEvent XPointerMovedEvent;

struct XCrossingEvent{
	int type;		/* of event */
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	NotifyModes mode;		/* NotifyNormal, NotifyGrab, NotifyUngrab */
	NotifyDetail detail;
	/*
	 * NotifyAncestor, NotifyVirtual, NotifyInferior,
	 * NotifyNonlinear,NotifyNonlinearVirtual
	 */
	Bool same_screen;	/* same screen flag */
	Bool focus;		/* Boolean focus */
	KeyOrButtonMask state;	/* key or button mask */
}
alias XCrossingEvent XEnterWindowEvent;
alias XCrossingEvent XLeaveWindowEvent;

struct XFocusChangeEvent{
	int type;		/* FocusIn or FocusOut */
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;		/* window of event */
	NotifyModes mode;		/* NotifyNormal, NotifyWhileGrabbed,
				   NotifyGrab, NotifyUngrab */
	NotifyDetail detail;
	/*
	 * NotifyAncestor, NotifyVirtual, NotifyInferior,
	 * NotifyNonlinear,NotifyNonlinearVirtual, NotifyPointer,
	 * NotifyPointerRoot, NotifyDetailNone
	 */
}
alias XFocusChangeEvent XFocusInEvent;
alias XFocusChangeEvent XFocusOutEvent;
Window XCreateSimpleWindow(
    Display*	/* display */,
    Window		/* parent */,
    int			/* x */,
    int			/* y */,
    uint		/* width */,
    uint		/* height */,
    uint		/* border_width */,
    uint		/* border */,
    uint		/* background */
);

XImage *XCreateImage(
    Display*		/* display */,
    Visual*		/* visual */,
    uint	/* depth */,
    int			/* format */,
    int			/* offset */,
    byte*		/* data */,
    uint	/* width */,
    uint	/* height */,
    int			/* bitmap_pad */,
    int			/* bytes_per_line */
);

Atom XInternAtom(
    Display*		/* display */,
    const char*	/* atom_name */,
    Bool		/* only_if_exists */
);

alias int Status;


enum EventMask:int
{
	NoEventMask				=0,
	KeyPressMask			=1<<0,
	KeyReleaseMask			=1<<1,
	ButtonPressMask			=1<<2,
	ButtonReleaseMask		=1<<3,
	EnterWindowMask			=1<<4,
	LeaveWindowMask			=1<<5,
	PointerMotionMask		=1<<6,
	PointerMotionHintMask	=1<<7,
	Button1MotionMask		=1<<8,
	Button2MotionMask		=1<<9,
	Button3MotionMask		=1<<10,
	Button4MotionMask		=1<<11,
	Button5MotionMask		=1<<12,
	ButtonMotionMask		=1<<13,
	KeymapStateMask		=1<<14,
	ExposureMask			=1<<15,
	VisibilityChangeMask	=1<<16,
	StructureNotifyMask		=1<<17,
	ResizeRedirectMask		=1<<18,
	SubstructureNotifyMask	=1<<19,
	SubstructureRedirectMask=1<<20,
	FocusChangeMask			=1<<21,
	PropertyChangeMask		=1<<22,
	ColormapChangeMask		=1<<23,
	OwnerGrabButtonMask		=1<<24
}

int XPutImage(
    Display*	/* display */,
    Drawable	/* d */,
    GC			/* gc */,
    XImage*	/* image */,
    int			/* src_x */,
    int			/* src_y */,
    int			/* dest_x */,
    int			/* dest_y */,
    uint		/* width */,
    uint		/* height */
);

int XDestroyWindow(
    Display*	/* display */,
    Window		/* w */
);

int XDestroyImage(
	XImage*);

int XSelectInput(
    Display*	/* display */,
    Window		/* w */,
    EventMask	/* event_mask */
);

int XMapWindow(
    Display*	/* display */,
    Window		/* w */
);

int XNextEvent(
    Display*	/* display */,
    XEvent*		/* event_return */
);

Status XSetWMProtocols(
    Display*	/* display */,
    Window		/* w */,
    Atom*		/* protocols */,
    int			/* count */
);

enum EventType:int
{
	KeyPress			=2,
	KeyRelease			=3,
	ButtonPress			=4,
	ButtonRelease		=5,
	MotionNotify		=6,
	EnterNotify			=7,
	LeaveNotify			=8,
	FocusIn				=9,
	FocusOut			=10,
	KeymapNotify		=11,
	Expose				=12,
	GraphicsExpose		=13,
	NoExpose			=14,
	VisibilityNotify	=15,
	CreateNotify		=16,
	DestroyNotify		=17,
	UnmapNotify		=18,
	MapNotify			=19,
	MapRequest			=20,
	ReparentNotify		=21,
	ConfigureNotify		=22,
	ConfigureRequest	=23,
	GravityNotify		=24,
	ResizeRequest		=25,
	CirculateNotify		=26,
	CirculateRequest	=27,
	PropertyNotify		=28,
	SelectionClear		=29,
	SelectionRequest	=30,
	SelectionNotify		=31,
	ColormapNotify		=32,
	ClientMessage		=33,
	MappingNotify		=34,
	LASTEvent			=35	/* must be bigger than any event # */
}
/* generated on EnterWindow and FocusIn  when KeyMapState selected */
struct XKeymapEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	byte key_vector[32];
}

struct XExposeEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	int x, y;
	int width, height;
	int count;		/* if non-zero, at least this many more */
}

struct XGraphicsExposeEvent{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Drawable drawable;
	int x, y;
	int width, height;
	int count;		/* if non-zero, at least this many more */
	int major_code;		/* core is CopyArea or CopyPlane */
	int minor_code;		/* not defined in the core */
}

struct XNoExposeEvent{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Drawable drawable;
	int major_code;		/* core is CopyArea or CopyPlane */
	int minor_code;		/* not defined in the core */
}

struct XVisibilityEvent{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	VisibilityNotify state;		/* Visibility state */
}

struct XCreateWindowEvent{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;		/* parent of the window */
	Window window;		/* window id of window created */
	int x, y;		/* window location */
	int width, height;	/* size of window */
	int border_width;	/* border width */
	Bool override_redirect;	/* creation should be overridden */
}

struct XDestroyWindowEvent
{
	int type;
	uint serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
}

struct XUnmapEvent
{
	int type;
	uint serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	Bool from_configure;
}

struct XMapEvent
{
	int type;
	uint serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	Bool override_redirect;	/* Boolean, is override set... */
}

struct XMapRequestEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;
	Window window;
}

struct XReparentEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	Window parent;
	int x, y;
	Bool override_redirect;
}

struct XConfigureEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	int x, y;
	int width, height;
	int border_width;
	Window above;
	Bool override_redirect;
}

struct XGravityEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	int x, y;
}

struct XResizeRequestEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	int width, height;
}

struct  XConfigureRequestEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;
	Window window;
	int x, y;
	int width, height;
	int border_width;
	Window above;
	WindowStackingMethod detail;		/* Above, Below, TopIf, BottomIf, Opposite */
	uint value_mask;
}

struct XCirculateEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	CirculationRequest place;		/* PlaceOnTop, PlaceOnBottom */
}

struct XCirculateRequestEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;
	Window window;
	CirculationRequest place;		/* PlaceOnTop, PlaceOnBottom */
}

struct XPropertyEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Atom atom;
	Time time;
	PropertyNotification state;		/* NewValue, Deleted */
}

struct XSelectionClearEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Atom selection;
	Time time;
}

struct XSelectionRequestEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window owner;
	Window requestor;
	Atom selection;
	Atom target;
	Atom property;
	Time time;
}

struct XSelectionEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window requestor;
	Atom selection;
	Atom target;
	Atom property;		/* ATOM or None */
	Time time;
}

struct XColormapEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Colormap colormap;	/* COLORMAP or None */
	Bool new_;		/* C++ */
	ColorMapNotification state;		/* ColormapInstalled, ColormapUninstalled */
}

struct XClientMessageEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Atom message_type;
	int format;
	union data{
		byte b[20];
		short s[10];
		int l[5];
		}
}

struct XMappingEvent
{
	int type;
	uint serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;		/* unused */
	MappingType request;		/* one of MappingModifier, MappingKeyboard,
				   MappingPointer */
	int first_keycode;	/* first keycode */
	int count;		/* defines range of change w. first_keycode*/
}

struct XErrorEvent
{
	int type;
	Display *display;	/* Display the event was read from */
	XID resourceid;		/* resource id */
	uint serial;	/* serial number of failed request */
	uint error_code;	/* error code of failed request */
	ubyte request_code;	/* Major op-code of failed request */
	ubyte minor_code;	/* Minor op-code of failed request */
}

struct XAnyEvent
{
	int type;
	ubyte serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;/* Display the event was read from */
	Window window;	/* window on which event was requested in event mask */
}

union XEvent{
    int type;		/* must not be changed; first element */
	XAnyEvent xany;
	XKeyEvent xkey;
	XButtonEvent xbutton;
	XMotionEvent xmotion;
	XCrossingEvent xcrossing;
	XFocusChangeEvent xfocus;
	XExposeEvent xexpose;
	XGraphicsExposeEvent xgraphicsexpose;
	XNoExposeEvent xnoexpose;
	XVisibilityEvent xvisibility;
	XCreateWindowEvent xcreatewindow;
	XDestroyWindowEvent xdestroywindow;
	XUnmapEvent xunmap;
	XMapEvent xmap;
	XMapRequestEvent xmaprequest;
	XReparentEvent xreparent;
	XConfigureEvent xconfigure;
	XGravityEvent xgravity;
	XResizeRequestEvent xresizerequest;
	XConfigureRequestEvent xconfigurerequest;
	XCirculateEvent xcirculate;
	XCirculateRequestEvent xcirculaterequest;
	XPropertyEvent xproperty;
	XSelectionClearEvent xselectionclear;
	XSelectionRequestEvent xselectionrequest;
	XSelectionEvent xselection;
	XColormapEvent xcolormap;
	XClientMessageEvent xclient;
	XMappingEvent xmapping;
	XErrorEvent xerror;
	XKeymapEvent xkeymap;
	int pad[24];
}


	struct Display {
		XExtData *ext_data;	/* hook for extension to hang data */
		_XPrivate *private1;
		int fd;			/* Network socket. */
		int private2;
		int proto_major_version;/* major version of server's X protocol */
		int proto_minor_version;/* minor version of servers X protocol */
		char *vendor;		/* vendor of the server hardware */
	    	XID private3;
		XID private4;
		XID private5;
		int private6;
		XID function(Display*)resource_alloc;/* allocator function */
		ByteOrder byte_order;		/* screen byte order, LSBFirst, MSBFirst */
		int bitmap_unit;	/* padding and data requirements */
		int bitmap_pad;		/* padding requirements on bitmaps */
		ByteOrder bitmap_bit_order;	/* LeastSignificant or MostSignificant */
		int nformats;		/* number of pixmap formats in list */
		ScreenFormat *pixmap_format;	/* pixmap format list */
		int private8;
		int release;		/* release of the server */
		_XPrivate *private9;
		_XPrivate *private10;
		int qlen;		/* Length of input event queue */
		uint last_request_read; /* seq number of last event read */
		uint request;	/* sequence number of last request. */
		XPointer private11;
		XPointer private12;
		XPointer private13;
		XPointer private14;
		uint max_request_size; /* maximum number 32 bit words in request*/
		_XrmHashBucketRec *db;
		int function  (Display*)private15;
		char *display_name;	/* "host:display" string used on this connect*/
		int default_screen;	/* default screen for operations */
		int nscreens;		/* number of screens on this server*/
		Screen *screens;	/* pointer to list of screens */
		uint motion_buffer;	/* size of motion buffer */
		uint private16;
		int min_keycode;	/* minimum defined keycode */
		int max_keycode;	/* maximum defined keycode */
		XPointer private17;
		XPointer private18;
		int private19;
		byte *xdefaults;	/* contents of defaults from server */
		/* there is more to this structure, but it is private to Xlib */
	}

struct Depth
{
	int depth;		/* this depth (Z) of the depth */
	int nvisuals;		/* number of Visual types at this depth */
	Visual *visuals;	/* list of visuals possible at this depth */
}

alias void* GC;
alias int VisualID;
alias XID Colormap;
alias XID KeySym;
alias uint KeyCode;

struct Screen{
	XExtData *ext_data;		/* hook for extension to hang data */
	Display *display;		/* back pointer to display structure */
	Window root;			/* Root window id. */
	int width, height;		/* width and height of screen */
	int mwidth, mheight;	/* width and height of  in millimeters */
	int ndepths;			/* number of depths possible */
	Depth *depths;			/* list of allowable depths on the screen */
	int root_depth;			/* bits per pixel */
	Visual *root_visual;	/* root visual */
	GC default_gc;			/* GC for the root root visual */
	Colormap cmap;			/* default color map */
	uint white_pixel;
	uint black_pixel;		/* White and Black pixel values */
	int max_maps, min_maps;	/* max and min color maps */
	int backing_store;		/* Never, WhenMapped, Always */
	bool save_unders;
	int root_input_mask;	/* initial root input mask */
}

struct Visual
{
	XExtData *ext_data;	/* hook for extension to hang data */
	VisualID visualid;	/* visual id of this visual */
	int class_;			/* class of screen (monochrome, etc.) */
	uint red_mask, green_mask, blue_mask;	/* mask values */
	int bits_per_rgb;	/* log base 2 of distinct color values */
	int map_entries;	/* color map entries */
}

	alias Display* _XPrivDisplay;

	Screen* ScreenOfDisplay(Display* dpy, int scr) {
		return (&(cast(_XPrivDisplay)dpy).screens[scr]);
	}

	Window	RootWindow(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).root;
	}

	int DefaultScreen(Display *dpy) {
		return dpy.default_screen;
	}

	Visual* DefaultVisual(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).root_visual;
	}

	GC DefaultGC(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).default_gc;
	}

	uint BlackPixel(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).black_pixel;
	}

	uint WhitePixel(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).white_pixel;
	}

	int XDrawString(Display*, Drawable, GC, int, int, in char*, int);
	int XDrawLine(Display*, Drawable, GC, int, int, int, int);
	int XDrawRectangle(Display*, Drawable, GC, int, int, uint, uint);
	int XDrawArc(Display*, Drawable, GC, int, int, uint, uint, int, int);
	int XFillRectangle(Display*, Drawable, GC, int, int, uint, uint);
	int XFillArc(Display*, Drawable, GC, int, int, uint, uint, int, int);
	int XDrawPoint(Display*, Drawable, GC, int, int);
	int XSetForeground(Display*, GC, uint);
	int XSetBackground(Display*, GC, uint);

	GC XCreateGC(Display*, Drawable, uint, void*);
	int XCopyGC(Display*, GC, uint, GC);
	int XFreeGC(Display*, GC);

	bool XCheckWindowEvent(Display*, Window, int, XEvent*);
	bool XCheckMaskEvent(Display*, int, XEvent*);

	int XPending(Display*);

	Pixmap XCreatePixmap(Display*, Drawable, uint, uint, uint);
	int XFreePixmap(Display*, Pixmap);
	int XCopyArea(Display*, Drawable, Drawable, GC, int, int, uint, uint, int, int);
	int XFlush(Display*);

	struct XPoint {
		short x;
		short y;
	}

	int XDrawLines(Display*, Drawable, GC, XPoint*, int, CoordMode);
	int XFillPolygon(Display*, Drawable, GC, XPoint*, int, PolygonShape, CoordMode);

	enum CoordMode:int {
		CoordModeOrigin = 0,
		CoordModePrevious = 1
	}

	enum PolygonShape:int {
		Complex = 0,
		Nonconvex = 1,
		Convex = 2
	}

	struct XTextProperty {
		const(char)* value;		/* same as Property routines */
		Atom encoding;			/* prop type */
		int format;				/* prop data format: 8, 16, or 32 */
		uint nitems;		/* number of data items in value */
	}

	void XSetWMName(Display*, Window, XTextProperty*);

	enum Atom XA_STRING = 31;

} else static assert(0, "Unsupported operating system");
