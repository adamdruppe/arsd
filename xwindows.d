/// This module is a bunch of helper functions for dealing with X11
/// windows on top of simpledisplay.d
///
/// It is mostly about the atoms that communicate stuff to things like
/// window managers and taskbars.
///
/// The eventual goal is for this to be useful for writing those and for
/// writing plain applications.
module arsd.xwindows;

import simpledisplay;

enum _NET_WM_STATE_ADD = 1;
enum _NET_WM_STATE_REMOVE = 0;
enum _NET_WM_STATE_TOGGLE = 2;

void demandAttention(SimpleWindow window, bool needs = true) {
	auto display = XDisplayConnection.get();
	auto atom = GetAtom!"_NET_WM_STATE_DEMANDS_ATTENTION"(display);
	//auto atom2 = GetAtom!"_NET_WM_STATE_SHADED"(display);

	XClientMessageEvent xclient;

	xclient.type = EventType.ClientMessage;
	xclient.window = window.impl.window;
	xclient.message_type = GetAtom!"_NET_WM_STATE"(display);
	xclient.format = 32;
	xclient.data.l[0] = needs ? _NET_WM_STATE_ADD : _NET_WM_STATE_REMOVE;
	xclient.data.l[1] = atom;
	//xclient.data.l[2] = atom2;
	// [2] == a second property
	// [3] == source. 0 == unknown, 1 == app, 2 == else

	XSendEvent(
		display,
		RootWindow(display, DefaultScreen(display)),
		false,
		EventMask.SubstructureRedirectMask | EventMask.SubstructureNotifyMask,
		cast(XEvent*) &xclient
	);

	/+
	XChangeProperty(
		display,
		window.impl.window,
		GetAtom!"_NET_WM_STATE"(display),
		XA_ATOM,
		32 /* bits */,
		PropModeAppend,
		&atom,
		1);
	+/
}

TrueColorImage getWindowNetWmIcon(Window window) {
	auto display = XDisplayConnection.get;

	auto data =  cast(arch_ulong[]) getX11PropertyData (window, GetAtom!"_NET_WM_ICON"(display), XA_CARDINAL);

	if (data.length > 2) {
		// these are an array of rgba images that we have to convert into pixmaps ourself

		int width = data[0];
		int height = data[1];
		data = data[2 .. 2 + width * height];

		auto bytes = cast(ubyte[]) data;

		// this returns ARGB. Remember it is little-endian so
		//                                         we have BGRA
		// our thing uses RGBA, which in little endian, is ABGR
		for(int idx = 0; idx < bytes.length; idx += 4) {
			auto r = bytes[idx + 2];
			auto g = bytes[idx + 1];
			auto b = bytes[idx + 0];
			auto a = bytes[idx + 3];

			bytes[idx + 0] = r;
			bytes[idx + 1] = g;
			bytes[idx + 2] = b;
			bytes[idx + 3] = a;
		}

		return new TrueColorImage(width, height, bytes);
	}

	return null;
}
