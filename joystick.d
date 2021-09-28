/++

	Provides a polling-based API to use gamepads/joysticks on Linux and Windows.

	Pass `-version=ps1_style` or `-version=xbox_style` to pick your API style - the constants will use the names of the buttons on those controllers and attempt to emulate the other. ps1_style is compatible with more hardware and thus the default. XBox controllers work with either, though.

	The docs for this file are quite weak, I suggest you view source of [arsd.game] for an example of how it might be used.

	FIXME: on Linux, certain controller brands will not be recognized and you need to set the mappings yourself, e.g., `version(linux) joystickMapping[0] = &xbox360Mapping;`. I will formalize this into a proper api later.
+/

/*
	FIXME: a simple function to integrate with sdpy event loop. templated function

	HIGH LEVEL NOTES

	This will offer a pollable state of two styles of controller: a PS1 or an XBox 360.


	Actually, maybe I'll combine the two controller types. Make L2 and R2 just digital aliases
	for the triggers, which are analog aliases for it.

	Then have a virtual left stick which has the dpad aliases, while keeping the other two independent
	(physical dpad and physical left stick).

	Everything else should basically just work. We'll simply be left with naming and I can do them with
	aliases too.


	I do NOT bother with pressure sensitive other buttons, though Xbox original and PS2 had them, they
	have been removed from the newer models. It makes things simpler anyway since we can check "was just
	pressed" instead of all deltas.


	The PS1 controller style works for a lot of games:
		* The D-pad is an alias for the left stick. Analog input still works too.
		* L2 and R2 are given as buttons
		* The keyboard works as buttons
		* The mouse is an alias for the right stick
		* Buttons are given as labeled on a playstation controller

	The XBox controller style works if you need full, modern features:
		* The left stick and D-pad works independently of one another
			the d pad works as additional buttons.
		* The triggers work as independent analog inputs
			note that the WinMM driver doesn't support full independence
			since it is sent as a z-axis. Linux and modern Windows does though.
		* Buttons are labeled as they are on the XBox controller
		* The rumble motors are available, if the underlying driver supports it and noop if not.
		* Audio I/O is available, if the underlying driver supports it. NOT IMPLEMENTED.

	You chose which one you want at compile time with a -version=xbox_style or -version=ps1_style switch.
	The default is ps1_style which works with xbox controllers too, it just simplifies them.

	TODO:
		handling keyboard+mouse input as joystick aliases
		remapping support
		network transparent joysticks for at least the basic stuff.

	=================================

	LOW LEVEL NOTES

	On Linux, I'll just use /dev/input/js*. It is easy and works with everything I care about. It can fire
	events to arsd.eventloop and also maintains state internally for polling. You do have to let it get
	events though to handle that input - either doing your own select (etc.) on the js file descriptor,
	or running the event loop (which is what I recommend).

	On Windows, I'll support the mmsystem messages as far as I can, and XInput for more capabilities
	of the XBox 360 controller. (The mmsystem should support my old PS1 controller and xbox is the
	other one I have. I have PS3 controllers too which would be nice but since they require additional
	drivers, meh.)

	linux notes:
		all basic input is available, no audio (I think), no force feedback (I think)

	winmm notes:
		the xbox 360 controller basically works and sends events to the window for the buttons,
		left stick, and triggers. It doesn't send events for the right stick or dpad, but these
		are available through joyGetPosEx (the dpad is the POV hat and the right stick is
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



	Other fancy joysticks work low level on linux at least but the high level api reduces them to boredom but like
	hey the events are still there and it still basically works, you'd just have to give a custom mapping.
*/
module arsd.joystick;

// --------------------------------
// High level interface
// --------------------------------

version(xbox_style) {
	version(ps1_style)
		static assert(0, "Pass only one xbox_style OR ps1_style");
} else
	version=ps1_style; // default is PS1 style as it is a lower common denominator

version(xbox_style) {
	alias Axis = XBox360Axes;
	alias Button = XBox360Buttons;
} else version(ps1_style) {
	alias Axis = PS1AnalogAxes;
	alias Button = PS1Buttons;
}


version(Windows) {
	WindowsXInput wxi;
}

version(OSX) {
	struct JoystickState {}
}

JoystickState[4] joystickState;

version(linux) {
	int[4] joystickFds = -1;


	// On Linux, we have to track state ourselves since we only get events from the OS
	struct JoystickState {
		short[8] axes;
		ubyte[16] buttons;
	}

	const(JoystickMapping)*[4] joystickMapping;

	struct JoystickMapping {
		// maps virtual buttons to real buttons, etc.
		int[__traits(allMembers, Axis).length] axisOffsets = -1;
		int[__traits(allMembers, Button).length] buttonOffsets = -1;
	}

	/// If you have a real xbox 360 controller, use this mapping
	version(xbox_style) // xbox style maps directly to an xbox controller (of course)
	static immutable xbox360Mapping = JoystickMapping(
		[0,1,2,3,4,5,6,7],
		[0,1,2,3,4,5,6,7,8,9,10]
	);
	else version(ps1_style)
	static immutable xbox360Mapping = JoystickMapping(
		// PS1AnalogAxes index to XBox360Axes values
		[XBox360Axes.horizontalLeftStick,
		XBox360Axes.verticalLeftStick,
		XBox360Axes.verticalRightStick,
		XBox360Axes.horizontalRightStick,
		XBox360Axes.horizontalDpad,
		XBox360Axes.verticalDpad],
		// PS1Buttons index to XBox360Buttons values
		[XBox360Buttons.y, XBox360Buttons.b, XBox360Buttons.a, XBox360Buttons.x,
			cast(XBox360Buttons) -1, cast(XBox360Buttons) -1, // L2 and R2 don't map easily
			XBox360Buttons.lb, XBox360Buttons.rb,
			XBox360Buttons.back, XBox360Buttons.start,
			XBox360Buttons.leftStick, XBox360Buttons.rightStick]
	);


	/// For a real ps1 controller
	version(ps1_style)
	static immutable ps1Mapping = JoystickMapping(
		[0,1,2,3,4,5],
		[0,1,2,3,4,5,6,7,8,9,10,11]

	);
	else version(xbox_style)
	static immutable ps1Mapping = JoystickMapping(
		// FIXME... if we're going to support this at all
		// I think if I were to write a program using the xbox style,
		// I'd just use my xbox controller.
	);

	/// For Linux only, reads the latest joystick events into the change buffer, if available.
	/// It is non-blocking
	void readJoystickEvents(int fd) {
		js_event event;

		while(true) {
			auto r = read(fd, &event, event.sizeof);
			if(r == -1) {
				import core.stdc.errno;
				if(errno == EAGAIN || errno == EWOULDBLOCK)
					break;
				else assert(0); // , to!string(fd) ~ " " ~ to!string(errno));
			}
			assert(r == event.sizeof);

			ptrdiff_t player = -1;
			foreach(i, f; joystickFds)
				if(f == fd) {
					player = i;
					break;
				}

			assert(player >= 0 && player < joystickState.length);

			if(event.type & JS_EVENT_AXIS) {
				joystickState[player].axes[event.number] = event.value;

				if(event.type & JS_EVENT_INIT) {
					if(event.number == 5) {
						// After being initialized, if axes[6] == 32767, it seems to be my PS1 controller
						// If axes[5] is -32767, it might be an Xbox controller.

						if(event.value == -32767 && joystickMapping[player] is null) {
							joystickMapping[player] = &xbox360Mapping;
						}
					} else if(event.number == 6) {
						if((event.value == 32767 || event.value == -32767) && joystickMapping[player] is null) {
							joystickMapping[player] = &ps1Mapping;
						}
					}
				}
			}
			if(event.type & JS_EVENT_BUTTON) {
				joystickState[player].buttons[event.number] = event.value ? 255 : 0;
			}
		}
	}
}

version(Windows) {
	extern(Windows)
	DWORD function(DWORD, XINPUT_STATE*) getJoystickOSState;

	extern(Windows)
	DWORD winMMFallback(DWORD id, XINPUT_STATE* state) {
		JOYINFOEX info;
		auto result = joyGetPosEx(id, &info);
		if(result == 0) {
			// FIXME

		}
		return result;
	}

	alias JoystickState = XINPUT_STATE;
}

/// Returns the number of players actually connected
///
/// The controller ID
int enableJoystickInput(
	int player1ControllerId = 0,
	int player2ControllerId = 1,
	int player3ControllerId = 2,
	int player4ControllerId = 3)
{
	version(linux) {
		bool preparePlayer(int player, int id) {
			if(id < 0)
				return false;

			assert(player >= 0 && player < joystickFds.length);
			assert(id < 10);
			assert(id >= 0);
			char[] filename = "/dev/input/js0\0".dup;
			filename[$-2] = cast(char) (id + '0');

			int fd = open(filename.ptr, O_RDONLY);
			if(fd > 0) {
				joystickFds[player] = fd;

				version(with_eventloop) {
					import arsd.eventloop;
					makeNonBlocking(fd);
					addFileEventListeners(fd, &readJoystickEvents, null, null);
				} else {
					// for polling, we will set nonblocking mode anyway,
					// the readJoystickEvents function will handle this fine
					// so we can call it when needed even on like a game timer.
					auto flags = fcntl(fd, F_GETFL, 0);
					if(flags == -1)
						throw new Exception("fcntl get");
					flags |= O_NONBLOCK;
					auto s = fcntl(fd, F_SETFL, flags);
					if(s == -1)
						throw new Exception("fcntl set");
				}

				return true;
			}
			return false;
		}

		if(!preparePlayer(0, player1ControllerId) ? 1 : 0)
			return 0;
		if(!preparePlayer(1, player2ControllerId) ? 1 : 0)
			return 1;
		if(!preparePlayer(2, player3ControllerId) ? 1 : 0)
			return 2;
		if(!preparePlayer(3, player4ControllerId) ? 1 : 0)
			return 3;
		return 4; // all players successfully initialized
	} else version(Windows) {
		if(wxi.loadDll()) {
			getJoystickOSState = wxi.XInputGetState;
		} else {
			// WinMM fallback
			getJoystickOSState = &winMMFallback;
		}

		assert(getJoystickOSState !is null);

		if(getJoystickOSState(player1ControllerId, &(joystickState[0])))
			return 0;
		if(getJoystickOSState(player2ControllerId, &(joystickState[1])))
			return 1;
		if(getJoystickOSState(player3ControllerId, &(joystickState[2])))
			return 2;
		if(getJoystickOSState(player4ControllerId, &(joystickState[3])))
			return 3;

		return 4;
	} else static assert(0, "Unsupported OS");

	// return 0;
}

///
void closeJoysticks() {
	version(linux) {
		foreach(ref fd; joystickFds) {
			if(fd > 0) {
				version(with_eventloop) {
					import arsd.eventloop;
					removeFileEventListeners(fd);
				}
				close(fd);
			}
			fd = -1;
		}
	} else version(Windows) {
		getJoystickOSState = null;
		wxi.unloadDll();
	} else static assert(0);
}

///
struct JoystickUpdate {
	///
	int player;

	JoystickState old;
	JoystickState current;

	/// changes from last update
	bool buttonWasJustPressed(Button button) {
		return buttonIsPressed(button) && !oldButtonIsPressed(button);
	}

	/// ditto
	bool buttonWasJustReleased(Button button) {
		return !buttonIsPressed(button) && oldButtonIsPressed(button);
	}

	/// this is normalized down to a 16 step change
	/// and ignores a dead zone near the middle
	short axisChange(Axis axis) {
		return cast(short) (axisPosition(axis) - oldAxisPosition(axis));
	}

	/// current state
	bool buttonIsPressed(Button button) {
		return buttonIsPressedHelper(button, &current);
	}

	/// Note: UP is negative!
	/// Value will actually be -16 to 16 ish.
	short axisPosition(Axis axis, short digitalFallbackValue = short.max) {
		return axisPositionHelper(axis, &current, digitalFallbackValue);
	}

	/* private */

	// old state
	bool oldButtonIsPressed(Button button) {
		return buttonIsPressedHelper(button, &old);
	}

	short oldAxisPosition(Axis axis, short digitalFallbackValue = short.max) {
		return axisPositionHelper(axis, &old, digitalFallbackValue);
	}

	short axisPositionHelper(Axis axis, JoystickState* what, short digitalFallbackValue = short.max) {
		version(ps1_style) {
			// on PS1, the d-pad and left stick are synonyms for each other
			// the dpad takes precedence, if it is pressed

			if(axis == PS1AnalogAxes.horizontalDpad || axis == PS1AnalogAxes.horizontalLeftStick) {
				auto it = axisPositionHelperRaw(PS1AnalogAxes.horizontalDpad, what, digitalFallbackValue);
				if(!it)
					it = axisPositionHelperRaw(PS1AnalogAxes.horizontalLeftStick, what, digitalFallbackValue);
				return it;
			}

			if(axis == PS1AnalogAxes.verticalDpad || axis == PS1AnalogAxes.verticalLeftStick) {
				auto it = axisPositionHelperRaw(PS1AnalogAxes.verticalDpad, what, digitalFallbackValue);
				if(!it)
					it = axisPositionHelperRaw(PS1AnalogAxes.verticalLeftStick, what, digitalFallbackValue);
				return it;
			}
		}

		return axisPositionHelperRaw(axis, what, digitalFallbackValue);
	}

	static short normalizeAxis(short value) {
	/+
		auto v = normalizeAxisHack(value);
		import std.stdio;
		writeln(value, " :: ", v);
		return v;
	}
	static short normalizeAxisHack(short value) {
	+/
		if(value > -1600 && value < 1600)
			return 0; // the deadzone gives too much useless junk
		return cast(short) (value >>> 11);
	}

	bool buttonIsPressedHelper(Button button, JoystickState* what) {
		version(linux) {
			int mapping = -1;
			if(auto ptr = joystickMapping[player])
				mapping = ptr.buttonOffsets[button];
			if(mapping != -1)
				return what.buttons[mapping] ? true : false;
			// otherwise what do we do?
			// FIXME
			return false; // the button isn't mapped, figure it isn't there and thus can't be pushed
		} else version(Windows) {
			// on Windows, I'm always assuming it is an XBox 360 controller
			// because that's what I have and the OS supports it so well
			version(xbox_style)
			final switch(button) {
				case XBox360Buttons.a: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_A) ? true : false;
				case XBox360Buttons.b: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_B) ? true : false;
				case XBox360Buttons.x: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_X) ? true : false;
				case XBox360Buttons.y: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_Y) ? true : false;

				case XBox360Buttons.lb: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) ? true : false;
				case XBox360Buttons.rb: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) ? true : false;

				case XBox360Buttons.back: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_BACK) ? true : false;
				case XBox360Buttons.start: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_START) ? true : false;

				case XBox360Buttons.leftStick: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_THUMB) ? true : false;
				case XBox360Buttons.rightStick: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_THUMB) ? true : false;

				case XBox360Buttons.xboxLogo: return false;
			}
			else version(ps1_style)
			final switch(button) {
				case PS1Buttons.triangle: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_Y) ? true : false;
				case PS1Buttons.square: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_X) ? true : false;
				case PS1Buttons.cross: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_A) ? true : false;
				case PS1Buttons.circle: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_B) ? true : false;

				case PS1Buttons.select: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_BACK) ? true : false;
				case PS1Buttons.start: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_START) ? true : false;

				case PS1Buttons.l1: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) ? true : false;
				case PS1Buttons.r1: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) ? true : false;

				case PS1Buttons.l2: return (what.Gamepad.bLeftTrigger > 100);
				case PS1Buttons.r2: return (what.Gamepad.bRightTrigger > 100);

				case PS1Buttons.l3: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_THUMB) ? true : false;
				case PS1Buttons.r3: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_THUMB) ? true : false;
			}
		}
	}

	short axisPositionHelperRaw(Axis axis, JoystickState* what, short digitalFallbackValue = short.max) {
		version(linux) {
			int mapping = -1;
			if(auto ptr = joystickMapping[player])
				mapping = ptr.axisOffsets[axis];
			if(mapping != -1)
				return normalizeAxis(what.axes[mapping]);
			return 0; // no such axis apparently, let the cooked one do something if it can
		} else version(Windows) {
			// on Windows, assuming it is an XBox 360 controller
			version(xbox_style)
			final switch(axis) {
				case XBox360Axes.horizontalLeftStick:
					return normalizeAxis(what.Gamepad.sThumbLX);
				case XBox360Axes.verticalLeftStick:
					return normalizeAxis(what.Gamepad.sThumbLY);
				case XBox360Axes.horizontalRightStick:
					return normalizeAxis(what.Gamepad.sThumbRX);
				case XBox360Axes.verticalRightStick:
					return normalizeAxis(what.Gamepad.sThumbRY);
				case XBox360Axes.verticalDpad:
					return (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_UP) ? -digitalFallbackValue :
					       (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN) ? digitalFallbackValue :
					       0;
				case XBox360Axes.horizontalDpad:
					return (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT) ? -digitalFallbackValue :
					       (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) ? digitalFallbackValue :
					       0;
				case XBox360Axes.lt:
					return normalizeTrigger(what.Gamepad.bLeftTrigger);
				case XBox360Axes.rt:
					return normalizeTrigger(what.Gamepad.bRightTrigger);
			}
			else version(ps1_style)
			final switch(axis) {
				case PS1AnalogAxes.horizontalDpad:
				case PS1AnalogAxes.horizontalLeftStick:
					short got = (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT) ? cast(short)-cast(int)digitalFallbackValue :
					       (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) ? digitalFallbackValue :
					       0;
					if(got == 0)
						got = what.Gamepad.sThumbLX;

					return normalizeAxis(got);
				case PS1AnalogAxes.verticalDpad:
				case PS1AnalogAxes.verticalLeftStick:
					short got = (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_UP) ? digitalFallbackValue :
					       (what.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN) ? cast(short)-cast(int)digitalFallbackValue :
						what.Gamepad.sThumbLY;

					if(got == short.min)
						got++; // to avoid overflow on the axis inversion below

					return normalizeAxis(cast(short)-cast(int)got);
				case PS1AnalogAxes.horizontalRightStick:
					return normalizeAxis(what.Gamepad.sThumbRX);
				case PS1AnalogAxes.verticalRightStick:
					return normalizeAxis(what.Gamepad.sThumbRY);
			}
		}
	}

	version(Windows)
		short normalizeTrigger(BYTE b) {
			if(b < XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
				return 0;
			return cast(short)((b << 8)|0xff);
		}
}

///
JoystickUpdate getJoystickUpdate(int player) {
	static JoystickState[4] previous;

	version(Windows) {
		assert(getJoystickOSState !is null);
		if(getJoystickOSState(player, &(joystickState[player])))
			return JoystickUpdate();
			//throw new Exception("wtf");
	}

	auto it = JoystickUpdate(player, previous[player], joystickState[player]);

	previous[player] = joystickState[player];

	return it;
}

// --------------------------------
// Low level interface
// --------------------------------

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

	version(arsd_js_test)
	void main() {
		/*
		// winmm test
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

		// xinput test

		WindowsXInput x;
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
	enum XINPUT_GAMEPAD_LEFT_THUMB =	0x0040; // pushing on the stick
	enum XINPUT_GAMEPAD_RIGHT_THUMB =	0x0080;
	enum XINPUT_GAMEPAD_LEFT_SHOULDER =	0x0100;
	enum XINPUT_GAMEPAD_RIGHT_SHOULDER =	0x0200;
	enum XINPUT_GAMEPAD_A =	0x1000;
	enum XINPUT_GAMEPAD_B =	0x2000;
	enum XINPUT_GAMEPAD_X =	0x4000;
	enum XINPUT_GAMEPAD_Y =	0x8000;

	enum XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE =  7849;
	enum XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE = 8689;
	enum XINPUT_GAMEPAD_TRIGGER_THRESHOLD =   30;

	struct XINPUT_STATE {
		DWORD dwPacketNumber;
		XINPUT_GAMEPAD Gamepad;
	}

	struct XINPUT_VIBRATION {
		WORD wLeftMotorSpeed; // low frequency motor. use any value between 0-65535 here
		WORD wRightMotorSpeed; // high frequency motor. use any value between 0-65535 here
	}

	struct WindowsXInput {
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
			unloadDll();
		}

		void unloadDll() {
			if(dll !is null) {
				FreeLibrary(dll);
				dll = null;
			}
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
}

	// My hardware:
	// a Sony PS1 dual shock controller on a PSX to USB adapter from Radio Shack
	// and a wired XBox 360 controller from Microsoft.

	// FIXME: these are the values based on my linux box, but I also use them as the virtual codes
	// I want nicer virtual codes I think.

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
		horizontalLeftStick = 0,
		verticalLeftStick,
		verticalRightStick,
		horizontalRightStick,
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
		verticalRightStick,
		rt,
		horizontalDpad,
		verticalDpad
	}

version(linux) {

	version(arsd_js_test)
	void main(string[] args) {
		int fd = open(args.length > 1 ? (args[1]~'\0').ptr : "/dev/input/js0".ptr, O_RDONLY);
		assert(fd > 0);
		js_event event;

		short[8] axes;
		ubyte[16] buttons;

		printf("\n");

		while(true) {
			auto r = read(fd, &event, event.sizeof);
			assert(r == event.sizeof);

			// writef("\r%12s", event);
			if(event.type & JS_EVENT_AXIS) {
				axes[event.number] = event.value >> 12;
			}
			if(event.type & JS_EVENT_BUTTON) {
				buttons[event.number] = cast(ubyte) event.value;
			}
			writef("\r%6s %1s", axes[0..8], buttons[0 .. 16]);
			stdout.flush();
		}

		close(fd);
		printf("\n");
	}

	version(joystick_demo)
	version(linux)
	void amain(string[] args) {
		import arsd.simpleaudio;

		AudioOutput audio = AudioOutput(0);

		int fd = open(args.length > 1 ? (args[1]~'\0').ptr : "/dev/input/js1".ptr, O_RDONLY | O_NONBLOCK);
		assert(fd > 0);
		js_event event;

		short[512] buffer;

		short val = short.max / 4;
		int swap = 44100 / 600;
		int swapCount = swap / 2;

		short val2 = short.max / 4;
		int swap2 = 44100 / 600;
		int swapCount2 = swap / 2;

		short[8] axes;
		ubyte[16] buttons;

		while(true) {
			int r = read(fd, &event, event.sizeof);
			while(r >= 0) {
				import std.conv;
				assert(r == event.sizeof, to!string(r));

				// writef("\r%12s", event);
				if(event.type & JS_EVENT_AXIS) {
					axes[event.number] = event.value; //  >> 12;
				}
				if(event.type & JS_EVENT_BUTTON) {
					buttons[event.number] = cast(ubyte) event.value;
				}


				int freq = axes[XBox360Axes.horizontalLeftStick];
				freq += short.max;
				freq /= 100;
				freq += 400;

				swap = 44100 / freq;

				val = (cast(int) axes[XBox360Axes.lt] + short.max) / 8;


				int freq2 = axes[XBox360Axes.horizontalRightStick];
				freq2 += short.max;
				freq2 /= 1000;
				freq2 += 400;

				swap2 = 44100 / freq2;

				val2 = (cast(int) axes[XBox360Axes.rt] + short.max) / 8;


				// try to starve the read
				r = read(fd, &event, event.sizeof);
			}

			for(int i = 0; i < buffer.length / 2; i++) {
			import std.math;
				auto v = cast(ushort) (val * sin(cast(real) swapCount / (2*PI)));
				auto v2 = cast(ushort) (val2 * sin(cast(real) swapCount2 / (2*PI)));
				buffer[i*2] = cast(ushort)(v + v2);
				buffer[i*2+1] = cast(ushort)(v + v2);
				swapCount--;
				swapCount2--;
				if(swapCount == 0) {
					swapCount = swap / 2;
					// val = -val;
				}
				if(swapCount2 == 0) {
					swapCount2 = swap2 / 2;
					// val = -val;
				}
			}


			//audio.write(buffer[]);
		}

		close(fd);
	}
}



	version(joystick_demo)
	version(Windows)
	void amain() {
		import arsd.simpleaudio;
		auto midi = MidiOutput(0);
		ubyte[16] buffer = void;
		ubyte[] where = buffer[];
		midi.writeRawMessageData(where.midiProgramChange(1, 79));

		auto x = WindowsXInput();
		x.loadDll();

		XINPUT_STATE state;
		XINPUT_STATE oldstate;
		DWORD pn;
		while(true) {
			oldstate = state;
			x.XInputGetState(0, &state);
			byte note = 72;
			if(state.dwPacketNumber != oldstate.dwPacketNumber) {
				if((state.Gamepad.wButtons & XINPUT_GAMEPAD_A) && !(oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_A))
					midi.writeRawMessageData(where.midiNoteOn(1, note, 127));
				if(!(state.Gamepad.wButtons & XINPUT_GAMEPAD_A) && (oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_A))
					midi.writeRawMessageData(where.midiNoteOff(1, note, 127));

				note = 75;

				if((state.Gamepad.wButtons & XINPUT_GAMEPAD_B) && !(oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_B))
					midi.writeRawMessageData(where.midiNoteOn(1, note, 127));
				if(!(state.Gamepad.wButtons & XINPUT_GAMEPAD_B) && (oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_B))
					midi.writeRawMessageData(where.midiNoteOff(1, note, 127));

				note = 77;

				if((state.Gamepad.wButtons & XINPUT_GAMEPAD_X) && !(oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_X))
					midi.writeRawMessageData(where.midiNoteOn(1, note, 127));
				if(!(state.Gamepad.wButtons & XINPUT_GAMEPAD_X) && (oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_X))
					midi.writeRawMessageData(where.midiNoteOff(1, note, 127));

				note = 79;
				if((state.Gamepad.wButtons & XINPUT_GAMEPAD_Y) && !(oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_Y))
					midi.writeRawMessageData(where.midiNoteOn(1, note, 127));
				if(!(state.Gamepad.wButtons & XINPUT_GAMEPAD_Y) && (oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_Y))
					midi.writeRawMessageData(where.midiNoteOff(1, note, 127));

				note = 81;
				if((state.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) && !(oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER))
					midi.writeRawMessageData(where.midiNoteOn(1, note, 127));
				if(!(state.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) && (oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER))
					midi.writeRawMessageData(where.midiNoteOff(1, note, 127));

				note = 83;
				if((state.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) && !(oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER))
					midi.writeRawMessageData(where.midiNoteOn(1, note, 127));
				if(!(state.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) && (oldstate.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER))
					midi.writeRawMessageData(where.midiNoteOff(1, note, 127));
			}

			Sleep(1);

			where = buffer[];
		}
	}

