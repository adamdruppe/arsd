/*
	On Linux, I'll just use /dev/input/js*. It is easy and works with everything I care about.

	On Windows, I'll support the mmsystem messages as far as I can, and XInput for more capabilities
	of the XBox 360 controller. (The mmsystem should support my old PS1 controller and xbox is the
	other one I have. I have PS3 controllers too which would be nice but since they require additional
	drivers, meh.)

	linux notes:
		all basic input is available, no audio (I think), no force feedback (I think)

	winmm notes:
		the xbox 360 controller basically works and sends events to the window for the buttons,
		left stick, and triggers. It doesn't send events for the right stick or dpad, but these
		are available through joyGetPositionEx (the dpad is the POV hat and the right stick is
		the other axes).

		The triggers are considered a z-axis with the left one going negative and right going positive.

	windows xinput notes:
		all xbox 360 controller features are available via a polling api.

		it doesn't seem to support events. That's OK for games generally though, because we just
		want to check state on each loop.

		For non-games however, using the traditional message loop is probably easier.

		XInput is only supported on newer operating systems (Vista I think),
		so I'm going to dynamically load it all and fallback on the old one if
		it fails.
*/

version(Windows) {

	import core.sys.windows.windows;

	alias MMRESULT = UINT;

	struct JOYINFOEX {
		DWORD dwSize;
		DWORD dwFlags;
		DWORD dwXpos;
		DWORD dwYpos;
		DWORD dwZpos;
		DWORD dwRpos;
		DWORD dwUpos;
		DWORD dwVpos;
		DWORD dwButtons;
		DWORD dwButtonNumber;
		DWORD dwPOV;
		DWORD dwReserved1;
		DWORD dwReserved2;
	}

	enum  : DWORD {
		JOY_POVCENTERED = -1,
		JOY_POVFORWARD  = 0,
		JOY_POVBACKWARD = 18000,
		JOY_POVLEFT     = 27000,
		JOY_POVRIGHT    = 9000
	}

	extern(Windows)
	MMRESULT joySetCapture(HWND window, UINT stickId, UINT period, BOOL changed);

	extern(Windows)
	MMRESULT joyGetPosEx(UINT stickId, JOYINFOEX* pji);

	extern(Windows)
	MMRESULT joyReleaseCapture(UINT stickId);

	// SEE ALSO:
	// http://msdn.microsoft.com/en-us/library/windows/desktop/dd757105%28v=vs.85%29.aspx

	// Windows also provides joyGetThreshold, joySetThreshold

	// there's also JOY2 messages
	enum MM_JOY1MOVE = 0; // FIXME
	enum MM_JOY1BUTTONDOWN = 0; // FIXME
	enum MM_JOY1BUTTONUP = 0; // FIXME

	pragma(lib, "winmm");

	void main() {
		/*
		auto window = new SimpleWindow(500, 500);

		joySetCapture(window.impl.hwnd, 0, 0, false);

		window.handleNativeEvent = (HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
			import std.stdio;
			writeln(msg, " ", wparam, " ", lparam);
			return 1;
		};

		window.eventLoop(0);

		joyReleaseCapture(0);
		*/

		import std.stdio;

		WindowXInput x;
		if(!x.loadDll()) {
			writeln("Load DLL failed");
			return;
		}

		writeln("success");

		assert(x.XInputSetState !is null);
		assert(x.XInputGetState !is null);

		XINPUT_STATE state;

		XINPUT_VIBRATION vibration;

		if(!x.XInputGetState(0, &state)) {
			writeln("Player 1 detected");
		} else return;
		if(!x.XInputGetState(1, &state)) {
			writeln("Player 2 detected");
		} else writeln("Player 2 not found");

		DWORD pn;
		foreach(i; 0 .. 60) {
			x.XInputGetState(0, &state);
			if(pn != state.dwPacketNumber) {
				writeln("c: ", state);
				pn = state.dwPacketNumber;
			}
			Sleep(50);
			if(i == 20) {
				vibration.wLeftMotorSpeed = WORD.max;
				vibration.wRightMotorSpeed = WORD.max;
				x.XInputSetState(0, &vibration);
				vibration = XINPUT_VIBRATION.init;
			}

			if(i == 40)
				x.XInputSetState(0, &vibration);
		}
	}

	struct XINPUT_GAMEPAD {
		WORD  wButtons;
		BYTE  bLeftTrigger;
		BYTE  bRightTrigger;
		SHORT sThumbLX;
		SHORT sThumbLY;
		SHORT sThumbRX;
		SHORT sThumbRY;
	}

	// enum XInputGamepadButtons {
	// It is a bitmask of these
	enum XINPUT_GAMEPAD_DPAD_UP =	0x0001;
	enum XINPUT_GAMEPAD_DPAD_DOWN =	0x0002;
	enum XINPUT_GAMEPAD_DPAD_LEFT =	0x0004;
	enum XINPUT_GAMEPAD_DPAD_RIGHT =	0x0008;
	enum XINPUT_GAMEPAD_START =	0x0010;
	enum XINPUT_GAMEPAD_BACK =	0x0020;
	enum XINPUT_GAMEPAD_LEFT_THUMB =	0x0040;
	enum XINPUT_GAMEPAD_RIGHT_THUMB =	0x0080;
	enum XINPUT_GAMEPAD_LEFT_SHOULDER =	0x0100;
	enum XINPUT_GAMEPAD_RIGHT_SHOULDER =	0x0200;
	enum XINPUT_GAMEPAD_A =	0x1000;
	enum XINPUT_GAMEPAD_B =	0x2000;
	enum XINPUT_GAMEPAD_X =	0x4000;
	enum XINPUT_GAMEPAD_Y =	0x8000;

	struct XINPUT_STATE {
		DWORD dwPacketNumber;
		XINPUT_GAMEPAD Gamepad;
	}

	struct XINPUT_VIBRATION {
		WORD wLeftMotorSpeed; // low frequency motor
		WORD wRightMotorSpeed; // high frequency motor
	}

	struct WindowXInput {
		HANDLE dll;
		bool loadDll() {
			// try Windows 8 first
			dll = LoadLibraryA("Xinput1_4.dll");
			if(dll is null) // then try Windows Vista
				dll = LoadLibraryA("Xinput9_1_0.dll");

			if(dll is null)
				return false; // couldn't load it, tell user

			XInputGetState = cast(typeof(XInputGetState)) GetProcAddress(dll, "XInputGetState");
			XInputSetState = cast(typeof(XInputSetState)) GetProcAddress(dll, "XInputSetState");

			return true;
		}

		~this() {
			if(dll !is null)
				FreeLibrary(dll);
		}

		// These are all dynamically loaded from the DLL
		extern(Windows) {
			DWORD function(DWORD, XINPUT_STATE*) XInputGetState;
			DWORD function(DWORD, XINPUT_VIBRATION*) XInputSetState;
		}

		// there's other functions but I don't use them; my controllers
		// are corded, for example, and I don't have a headset that works
		// with them. But if I get ones, I'll add them too.
		//
		// There's also some Windows 8 and up functions I didn't use, I just
		// wanted the basics.
	}
}

version(linux) {

	// https://www.kernel.org/doc/Documentation/input/joystick-api.txt
	struct js_event {
		uint time;
		short value;
		ubyte type;
		ubyte number;
	}

	enum JS_EVENT_BUTTON = 0x01;
	enum JS_EVENT_AXIS   = 0x02;
	enum JS_EVENT_INIT   = 0x80;

	import core.sys.posix.unistd;
	import core.sys.posix.fcntl;

	import std.stdio;

	struct RawControllerEvent {
		int controller;
		int type;
		int number;
		int value;
	}

	// These values are determined experimentally on my Linux box
	// and won't necessarily match what you have. I really don't know.
	// TODO: see if these line up on Windows

	// My hardware:
	// a Sony PS1 dual shock controller on a PSX to USB adapter from Radio Shack
	// and a wired XBox 360 controller from Microsoft.

	enum PS1Buttons {
		triangle = 0,
		circle,
		cross,
		square,
		l2,
		r2,
		l1,
		r1,
		select,
		start,
		l3,
		r3
	}

	// Use if analog is turned off
	// Tip: if you just check this OR the analog one it will work in both cases easily enough
	enum PS1Axes {
		horizontalDpad = 0,
		verticalDpad = 1,
	}

	// Use if analog is turned on
	enum PS1AnalogAxes {
		horiziontalLeftStick = 0,
		verticalLeftStick,
		verticalRightStick,
		horiziontalRightStick,
		horizontalDpad,
		verticalDpad,
	}


	enum XBox360Buttons {
		a = 0,
		b,
		x,
		y,
		lb,
		rb,
		back,
		start,
		xboxLogo,
		leftStick,
		rightStick
	}

	enum XBox360Axes {
		horizontalLeftStick = 0,
		verticalLeftStick,
		lt,
		horizontalRightStick,
		verticalLeftStick,
		rt,
		horizontalDpad,
		verticalDpad
	}

	void main(string[] args) {
		int fd = open(args.length > 1 ? (args[1]~'\0').ptr : "/dev/input/js0".ptr, O_RDONLY);
		assert(fd > 0);
		js_event event;

		short[8] axes;
		ubyte[16] buttons;

		printf("\n");

		while(true) {
			int r = read(fd, &event, event.sizeof);
			assert(r == event.sizeof);

			// writef("\r%12s", event);
			if(event.type & JS_EVENT_AXIS) {
				axes[event.number] = event.value >> 12;
			}
			if(event.type & JS_EVENT_BUTTON) {
				buttons[event.number] = event.value;
			}
			writef("\r%6s %1s", axes[0..8], buttons[0 .. 16]);
			stdout.flush();
		}

		close(fd);
		printf("\n");
	}
}
