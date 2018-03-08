/++
	Cross platform window manager utilities for interacting with other unknown windows on the OS.

	Based on arsd.simpledisplay.
+/
module arsd.wmutil;

public import arsd.simpledisplay;

static assert(UsingSimpledisplayX11 || UsingSimpledisplayWindows, "wmutil only works on X11 or Windows");

static if (UsingSimpledisplayX11)
{
extern(C) nothrow @nogc {
Atom* XListProperties(Display *display, Window w, int *num_prop_return);
Status XGetTextProperty(Display *display, Window w, XTextProperty *text_prop_return, Atom property);
Status XQueryTree(Display *display, Window w, Window *root_return, Window *parent_return, Window **children_return, uint *nchildren_return);
}
}

struct WindowChildrenIterator {
	NativeWindowHandle parent;

	int opApply(int delegate(NativeWindowHandle) dg) const {
		version (Windows) {
			struct EnumParams {
				int result;
				int delegate(NativeWindowHandle) dg;
				Exception ex;
			}

			EnumParams params;

			EnumChildWindows(parent, function (window, lparam) nothrow {
				EnumParams* args = cast(EnumParams*)lparam;
				try {
					args.result = args.dg(window);
					if (args.result)
						return 0;
					else
						return 1;
				} catch (Exception e) {
					args.ex = e;
					return 0;
				}
			}, cast(LPARAM)&params);

			if (params.ex)
				throw params.ex;

			return params.result;
		} else static if (UsingSimpledisplayX11) {
			int result;
			Window unusedWindow;
			Window* children;
			uint numChildren;
			Status status = XQueryTree(XDisplayConnection.get(), parent, &unusedWindow, &unusedWindow, &children, &numChildren);
			if (status == 0 || children is null)
				return 0;
			scope (exit)
				XFree(children);

			foreach (window; children[0 .. numChildren]) {
				result = dg(window);
				if (result)
					break;
			}
			return result;
		} else
			throw new NotYetImplementedException();
		
	}
}

WindowChildrenIterator iterateWindows(NativeWindowHandle parent = NativeWindowHandle.init) {
	return WindowChildrenIterator(parent);
}

/++
	Searches for a window with the specified class name and returns the native window handle to it.

	Params:
		className = the class name to check the window for, case-insensitive.
+/
version (Windows)
NativeWindowHandle findWindowByClass(LPCTSTR className) {
	return FindWindow(className, null);
}

/// ditto
version (Windows)
NativeWindowHandle findWindowByClass(string className) {
	return findWindowByClass(className.toWStringz);
}

/// ditto
static if (UsingSimpledisplayX11)
NativeWindowHandle findWindowByClass(string className) {
	import std.algorithm : splitter;
	import std.uni : sicmp;

	auto classAtom = GetAtom!"WM_CLASS"(XDisplayConnection.get());
	Atom returnType;
	int returnFormat;
	arch_ulong numItems, bytesAfter;
	char* strs;
	foreach (window; iterateWindows) {
		if (0 == XGetWindowProperty(XDisplayConnection.get(), window, classAtom, 0, 64, false, AnyPropertyType, &returnType, &returnFormat, &numItems, &bytesAfter, cast(void**)&strs)) {
			scope (exit)
				XFree(strs);
			if (returnFormat == 8) {
				foreach (windowClassName; strs[0 .. numItems].splitter('\0')) {
					if (sicmp(windowClassName, className) == 0)
						return window;
				}
			}
		}
	}
	return NativeWindowHandle.init;
}

/++
	Params:
		window = The window to check who created it
	Returns: the PID of the owner who created this window. On windows this will always work and be accurate. On X11 this might return -1 if none is specified and might not actually be the actual owner.
+/
version (Windows)
int ownerPID(NativeWindowHandle window) @property {
	DWORD ret;
	GetWindowThreadProcessId(window, &ret);
	return cast(int)ret;
}

/// ditto
static if (UsingSimpledisplayX11)
int ownerPID(NativeWindowHandle window) @property {
	auto pidAtom = GetAtom!"_NET_WM_PID"(XDisplayConnection.get());
	Atom returnType;
	int returnFormat;
	arch_ulong numItems, bytesAfter;
	uint* ints;
	if (0 == XGetWindowProperty(XDisplayConnection.get(), window, pidAtom, 0, 1, false, AnyPropertyType, &returnType, &returnFormat, &numItems, &bytesAfter, cast(void**)&ints)) {
		scope (exit)
			XFree(ints);
		if (returnFormat < 64 && numItems > 0) {
			return *ints;
		}
	}
	return -1;
}

unittest {
	import std.stdio;
	auto window = findWindowByClass("x-terminal-emulator");
	writeln("Terminal: ", window.ownerPID);
}
