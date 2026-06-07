/++
	Creates a UNIX terminal emulator, nested in a minigui widget.

	Depends on my terminalemulator.d core in the arsd repo.
+/
module arsd.minigui_addons.terminal_emulator_widget;
///
version(tew_main)
unittest {
	import arsd.minigui;
	import arsd.minigui_addons.terminal_emulator_widget;

	// version(linux) {} else static assert(0, "Terminal emulation kinda works on other platforms (it runs on Windows, but has no compatible shell program to run there!), but it is actually useful on Linux.")

	void main() {
		auto window = new MainWindow("Minigui Terminal Emulation");
		version(Posix)
			auto tew = new TerminalEmulatorWidget(["/bin/bash"], window);
		else version(Windows)
			auto tew = new TerminalEmulatorWidget([`c:\windows\system32\cmd.exe`], window);
		window.loop();
	}

	main();
}

import arsd.minigui;

import arsd.terminalemulator;

class TerminalEmulatorWidget : Widget {
	this(Widget parent) {
		terminalEmulator = new TerminalEmulatorInsideWidget(this);
		super(parent);
	}

	mixin Observable!(MemoryImage, "icon"); // please note it can be changed to null!
	mixin Observable!(string, "title");

	this(string[] args, Widget parent) {
		version(Windows) {
			import core.sys.windows.windows : HANDLE;
			void startup(HANDLE inwritePipe, HANDLE outreadPipe) {
				terminalEmulator = new TerminalEmulatorInsideWidget(inwritePipe, outreadPipe, this);
			}

			import std.string;
			startChild!startup(args[0], args.join(" "));
		}
		else version(Posix) {
			void startup(int master) {
				int fd = master;
				import fcntl = core.sys.posix.fcntl;
				auto flags = fcntl.fcntl(fd, fcntl.F_GETFL, 0);
				if(flags == -1)
					throw new Exception("fcntl get");
				flags |= fcntl.O_NONBLOCK;
				auto s = fcntl.fcntl(fd, fcntl.F_SETFL, flags);
				if(s == -1)
					throw new Exception("fcntl set");

				terminalEmulator = new TerminalEmulatorInsideWidget(master, this);
			}

			import std.process;
			auto cmd = environment.get("SHELL", "/bin/bash");
			startChild!startup(args[0], args);
		}

		super(parent);
	}

	TerminalEmulatorInsideWidget terminalEmulator;

	override void registerMovement() {
		super.registerMovement();
		terminalEmulator.resized(width, height);
	}

	override void focus() {
		super.focus();
		terminalEmulator.attentionReceived();
	}

	class Style : Widget.Style {
		override MouseCursor cursor() { return GenericCursor.Text; }
	}
	mixin OverrideStyle!Style;

	override void paint(WidgetPainter painter) {
		terminalEmulator.redrawPainter(painter, true);
	}
}


class TerminalEmulatorInsideWidget : TerminalEmulator {

	void resized(int w, int h) {
		this.resizeTerminal(w / fontWidth, h / fontHeight);
		clearScreenRequested = true;
		redraw();
	}


	protected override void changeCursorStyle(CursorStyle s) { }

	protected override void changeWindowTitle(string t) {
		widget.title = t;
	}

	// FIXME: minigui TabWidget ought to be able to accept icons too.
	protected override void changeWindowIcon(IndexedImage t) {
		widget.icon = t;
	}

	// FIXME: should we be able to delegate this up the chain too?
	protected override void soundBell() {
		static if(UsingSimpledisplayX11)
			XBell(XDisplayConnection.get(), 50);
	}

	protected override void demandAttention() {
		// to trigger:  echo -e '\033]5001;1\007'

		widget.emitCommand!"requestAttention";

		// to acknowledge:
		// attentionReceived();
	}

	override void requestExit() {
	sdpyPrintDebugString("exit");
		widget.emitCommand!"requestExit";
		// FIXME
	}


	protected override void changeIconTitle(string) {}
	protected override void changeTextAttributes(TextAttributes) {}

	protected override void copyToClipboard(string text) {
		setClipboardText(widget.parentWindow.win, text);
	}

	protected override void pasteFromClipboard(void delegate(in char[]) dg) {
		static if(UsingSimpledisplayX11)
			getPrimarySelection(widget.parentWindow.win, dg);
		else
			getClipboardText(widget.parentWindow.win, (in char[] dataIn) {
				char[] data;
				// change Windows \r\n to plain \n
				foreach(char ch; dataIn)
					if(ch != 13)
						data ~= ch;
				dg(data);
			});
	}

	protected override void copyToPrimary(string text) {
		static if(UsingSimpledisplayX11)
			setPrimarySelection(widget.parentWindow.win, text);
		else
			{}
	}
	protected override void pasteFromPrimary(void delegate(in char[]) dg) {
		static if(UsingSimpledisplayX11)
			getPrimarySelection(widget.parentWindow.win, dg);
	}



	void resizeImage() { }
	mixin PtySupport!(resizeImage);

	version(Posix)
		this(int masterfd, TerminalEmulatorWidget widget) {
			master = masterfd;
			this(widget);
		}
	else version(Windows) {
		import core.sys.windows.windows;
		this(HANDLE stdin, HANDLE stdout, TerminalEmulatorWidget widget) {
			this.stdin = stdin;
			this.stdout = stdout;
			this(widget);
		}
	}

	bool focused;

	TerminalEmulatorWidget widget;

	mixin SdpyDraw;

	private this(TerminalEmulatorWidget widget) {

		this.widget = widget;

		fontSize = 14;
		loadDefaultFont();

		auto desiredWidth = 80;
		auto desiredHeight = 24;

		super(desiredWidth, desiredHeight);

		bool skipNextChar = false;

		widget.addEventListener((MouseDownEvent ev) {
			int termX = (ev.clientX - paddingLeft) / fontWidth;
			int termY = (ev.clientY - paddingTop) / fontHeight;

			if(sendMouseInputToApplication(termX, termY,
				arsd.terminalemulator.MouseEventType.buttonPressed,
				cast(arsd.terminalemulator.MouseButton) ev.button,
				(ev.state & ModifierState.shift) ? true : false,
				(ev.state & ModifierState.ctrl) ? true : false,
				(ev.state & ModifierState.alt) ? true : false
			))
				redraw();
		});

		widget.addEventListener((MouseUpEvent ev) {
			int termX = (ev.clientX - paddingLeft) / fontWidth;
			int termY = (ev.clientY - paddingTop) / fontHeight;

			if(sendMouseInputToApplication(termX, termY,
				arsd.terminalemulator.MouseEventType.buttonReleased,
				cast(arsd.terminalemulator.MouseButton) ev.button,
				(ev.state & ModifierState.shift) ? true : false,
				(ev.state & ModifierState.ctrl) ? true : false,
				(ev.state & ModifierState.alt) ? true : false
			))
				redraw();
		});

		widget.addEventListener((MouseMoveEvent ev) {
			int termX = (ev.clientX - paddingLeft) / fontWidth;
			int termY = (ev.clientY - paddingTop) / fontHeight;

			if(sendMouseInputToApplication(termX, termY,
				arsd.terminalemulator.MouseEventType.motion,
				cast(arsd.terminalemulator.MouseButton) ev.button,
				(ev.state & ModifierState.shift) ? true : false,
				(ev.state & ModifierState.ctrl) ? true : false,
				(ev.state & ModifierState.alt) ? true : false
			))
				redraw();
		});

		widget.addEventListener((KeyDownEvent ev) {
			if(ev.key == Key.ScrollLock) {
				toggleScrollbackWrap();
			}

			string magic() {
				string code;
				foreach(member; __traits(allMembers, TerminalKey))
					if(member != "Escape")
						code ~= "case Key." ~ member ~ ": if(sendKeyToApplication(TerminalKey." ~ member ~ "
							, (ev.state & ModifierState.shift)?true:false
							, (ev.state & ModifierState.alt)?true:false
							, (ev.state & ModifierState.ctrl)?true:false
							, (ev.state & ModifierState.windows)?true:false
						)) redraw(); break;";
				return code;
			}


			switch(ev.key) {
				//// I want the escape key to send twice to differentiate it from
				//// other escape sequences easily.
				//case Key.Escape: sendToApplication("\033"); break;

				mixin(magic());

				default:
					// keep going, not special
			}

			// remapping of alt+key is possible too, at least on linux.
			/+
			static if(UsingSimpledisplayX11)
			if(ev.state & ModifierState.alt) {
				if(ev.character in altMappings) {
					sendToApplication(altMappings[ev.character]);
					skipNextChar = true;
				}
			}
			+/

			return; // the character event handler will do others
		});

		widget.addEventListener((CharEvent ev) {
			dchar c = ev.character;
			if(skipNextChar) {
				skipNextChar = false;
				return;
			}

			endScrollback();
			char[4] str;
			import std.utf;
			if(c == '\n') c = '\r'; // terminal seem to expect enter to send 13 instead of 10
			auto data = str[0 .. encode(str, c)];

			// on X11, the delete key can send a 127 character too, but that shouldn't be sent to the terminal since xterm shoots \033[3~ instead, which we handle in the KeyEvent handler.
			if(c != 127)
				sendToApplication(data);
		});

		version(Posix) {
			auto cls = new PosixFdReader(&readyToRead, master);
		} else
		version(Windows) {
			overlapped = new OVERLAPPED();
			overlapped.hEvent = cast(void*) this;

			//window.handleNativeEvent = &windowsRead;
			readyToReadWindows(0, 0, overlapped);
			redraw();
		}
	}

	static int fontSize = 14;

	bool clearScreenRequested = true;
	void redraw(bool forceRedraw = false) {
		if(widget.parentWindow is null || widget.parentWindow.win is null)
			return;
		auto painter = widget.draw();
		if(clearScreenRequested) {
			auto clearColor = defaultBackground;
			painter.outlineColor = clearColor;
			painter.fillColor = clearColor;
			painter.drawRectangle(Point(0, 0), widget.width, widget.height);
			clearScreenRequested = false;
			forceRedraw = true;
		}

		redrawPainter(painter, forceRedraw);
	}

	bool debugMode = false;
}
