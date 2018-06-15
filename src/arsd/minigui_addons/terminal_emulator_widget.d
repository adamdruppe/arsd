/++
	Creates a UNIX terminal emulator, nested in a minigui widget.

	Depends on my terminalemulator.d core. Get it here:
	https://github.com/adamdruppe/terminal-emulator/blob/master/terminalemulator.d
+/
module arsd.minigui_addons.terminal_emulator_widget;
///
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
}

import arsd.minigui;

import arsd.terminalemulator;

class TerminalEmulatorWidget : Widget {
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

	override MouseCursor cursor() { return GenericCursor.Text; }

	override void paint(ScreenPainter painter) {
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
		//if(window && t.length)
			//window.title = t;
	}
	protected override void changeWindowIcon(IndexedImage t) {
		//if(window && t)
			//window.icon = t;
	}
	protected override void changeIconTitle(string) {}
	protected override void changeTextAttributes(TextAttributes) {}
	protected override void soundBell() {
		static if(UsingSimpledisplayX11)
			XBell(XDisplayConnection.get(), 50);
	}

	protected override void demandAttention() {
		//window.requestAttention();
	}

	protected override void copyToClipboard(string text) {
		static if(UsingSimpledisplayX11)
			setPrimarySelection(widget.parentWindow.win, text);
		else
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
	OperatingSystemFont font;

	private this(TerminalEmulatorWidget widget) {

		this.widget = widget;

		static if(UsingSimpledisplayX11) {
			// FIXME: survive reconnects?
			fontSize = 14;
			font = new OperatingSystemFont("fixed", fontSize, FontWeight.medium);
			if(font.isNull) {
				// didn't work, it is using a
				// fallback, prolly fixed-13
				import std.stdio; writeln("font failed");
				fontWidth = 6;
				fontHeight = 13;
			} else {
				fontWidth = fontSize / 2;
				fontHeight = fontSize;
			}
		} else version(Windows) {
			font = new OperatingSystemFont("Courier New", fontSize, FontWeight.medium);
			fontHeight = fontSize;
			fontWidth = fontSize / 2;
		}

		auto desiredWidth = 80;
		auto desiredHeight = 24;

		super(desiredWidth, desiredHeight);

		bool skipNextChar = false;

		widget.addEventListener("mousedown", (Event ev) {
			int termX = (ev.clientX - paddingLeft) / fontWidth;
			int termY = (ev.clientY - paddingTop) / fontHeight;

			if(sendMouseInputToApplication(termX, termY,
				arsd.terminalemulator.MouseEventType.buttonPressed,
				cast(arsd.terminalemulator.MouseButton) ev.button,
				(ev.state & ModifierState.shift) ? true : false,
				(ev.state & ModifierState.ctrl) ? true : false
			))
				redraw();
		});

		widget.addEventListener("mouseup", (Event ev) {
			int termX = (ev.clientX - paddingLeft) / fontWidth;
			int termY = (ev.clientY - paddingTop) / fontHeight;

			if(sendMouseInputToApplication(termX, termY,
				arsd.terminalemulator.MouseEventType.buttonReleased,
				cast(arsd.terminalemulator.MouseButton) ev.button,
				(ev.state & ModifierState.shift) ? true : false,
				(ev.state & ModifierState.ctrl) ? true : false
			))
				redraw();
		});

		widget.addEventListener("mousemove", (Event ev) {
			int termX = (ev.clientX - paddingLeft) / fontWidth;
			int termY = (ev.clientY - paddingTop) / fontHeight;

			if(sendMouseInputToApplication(termX, termY,
				arsd.terminalemulator.MouseEventType.motion,
				cast(arsd.terminalemulator.MouseButton) ev.button,
				(ev.state & ModifierState.shift) ? true : false,
				(ev.state & ModifierState.ctrl) ? true : false
			))
				redraw();
		});

		widget.addEventListener("keydown", (Event ev) {
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

		widget.addEventListener("char", (Event ev) {
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

	int fontWidth;
	int fontHeight;

	static int fontSize = 14;

	enum paddingLeft = 2;
	enum paddingTop = 1;

	bool clearScreenRequested = true;
	void redraw(bool forceRedraw = false) {
		if(widget.parentWindow is null || widget.parentWindow.win is null)
			return;
		auto painter = widget.draw();
		if(clearScreenRequested) {
			auto clearColor = defaultTextAttributes.background;
			painter.outlineColor = clearColor;
			painter.fillColor = clearColor;
			painter.drawRectangle(Point(0, 0), widget.width, widget.height);
			clearScreenRequested = false;
			forceRedraw = true;
		}

		redrawPainter(painter, forceRedraw);
	}

	bool lastDrawAlternativeScreen;
	final arsd.color.Rectangle redrawPainter(T)(T painter, bool forceRedraw) {
		arsd.color.Rectangle invalidated;

		// FIXME: could prolly use optimizations

		painter.setFont(font);

		int posx = paddingLeft;
		int posy = paddingTop;


		char[512] bufferText;
		bool hasBufferedInfo;
		int bufferTextLength;
		Color bufferForeground;
		Color bufferBackground;
		int bufferX = -1;
		int bufferY = -1;
		bool bufferReverse;
		void flushBuffer() {
			if(!hasBufferedInfo) {
				return;
			}

			assert(posx - bufferX - 1 > 0);

			painter.fillColor = bufferReverse ? bufferForeground : bufferBackground;
			painter.outlineColor = bufferReverse ? bufferForeground : bufferBackground;

			painter.drawRectangle(Point(bufferX, bufferY), posx - bufferX, fontHeight);
			painter.fillColor = Color.transparent;
			// Hack for contrast!
			if(bufferBackground == Color.black && !bufferReverse) {
				// brighter than normal in some cases so i can read it easily
				painter.outlineColor = contrastify(bufferForeground);
			} else if(bufferBackground == Color.white && !bufferReverse) {
				// darker than normal so i can read it
				painter.outlineColor = antiContrastify(bufferForeground);
			} else if(bufferForeground == bufferBackground) {
				// color on itself, I want it visible too
				auto hsl = toHsl(bufferForeground, true);
				if(hsl[2] < 0.5)
					hsl[2] += 0.5;
				else
					hsl[2] -= 0.5;
				painter.outlineColor = fromHsl(hsl[0], hsl[1], hsl[2]);

			} else {
				// normal
				painter.outlineColor = bufferReverse ? bufferBackground : bufferForeground;
			}

			// FIXME: make sure this clips correctly
			painter.drawText(Point(bufferX, bufferY), cast(immutable) bufferText[0 .. bufferTextLength]);

			hasBufferedInfo = false;

			bufferReverse = false;
			bufferTextLength = 0;
			bufferX = -1;
			bufferY = -1;
		}



		int x;
		foreach(idx, ref cell; alternateScreenActive ? alternateScreen : normalScreen) {
			if(!forceRedraw && !cell.invalidated && lastDrawAlternativeScreen == alternateScreenActive) {
				flushBuffer();
				goto skipDrawing;
			}
			cell.invalidated = false;
			version(none) if(bufferX == -1) { // why was this ever here?
				bufferX = posx;
				bufferY = posy;
			}

			{

				invalidated.left = posx < invalidated.left ? posx : invalidated.left;
				invalidated.top = posy < invalidated.top ? posy : invalidated.top;
				int xmax = posx + fontWidth;
				int ymax = posy + fontHeight;
				invalidated.right = xmax > invalidated.right ? xmax : invalidated.right;
				invalidated.bottom = ymax > invalidated.bottom ? ymax : invalidated.bottom;

				// FIXME: this could be more efficient, simpledisplay could get better graphics context handling
				{

					bool reverse = (cell.attributes.inverse != reverseVideo);
					if(cell.selected)
						reverse = !reverse;

					auto fgc = cell.attributes.foreground;
					auto bgc = cell.attributes.background;

					if(!(cell.attributes.foregroundIndex & 0xff00)) {
						// this refers to a specific palette entry, which may change, so we should use that
						fgc = palette[cell.attributes.foregroundIndex];
					}
					if(!(cell.attributes.backgroundIndex & 0xff00)) {
						// this refers to a specific palette entry, which may change, so we should use that
						bgc = palette[cell.attributes.backgroundIndex];
					}

					if(fgc != bufferForeground || bgc != bufferBackground || reverse != bufferReverse)
						flushBuffer();
					bufferReverse = reverse;
					bufferBackground = bgc;
					bufferForeground = fgc;
				}
			}

				if(cell.ch != dchar.init) {
					char[4] str;
					import std.utf;
					// now that it is buffered, we do want to draw it this way...
					//if(cell.ch != ' ') { // no point wasting time drawing spaces, which are nothing; the bg rectangle already did the important thing
						try {
							auto stride = encode(str, cell.ch);
							if(bufferTextLength + stride > bufferText.length)
								flushBuffer();
							bufferText[bufferTextLength .. bufferTextLength + stride] = str[0 .. stride];
							bufferTextLength += stride;

							if(bufferX == -1) {
								bufferX = posx;
								bufferY = posy;
							}
							hasBufferedInfo = true;
						} catch(Exception e) {
							import std.stdio;
							writeln(cast(uint) cell.ch, " :: ", e.msg);
						}
					//}
				} else if(cell.nonCharacterData !is null) {
				}

				if(cell.attributes.underlined) {
					// the posx adjustment is because the buffer assumes it is going
					// to be flushed after advancing, but here, we're doing it mid-character
					// FIXME: we should just underline the whole thing consecutively, with the buffer
					posx += fontWidth;
					flushBuffer();
					posx -= fontWidth;
					painter.drawLine(Point(posx, posy + fontHeight - 1), Point(posx + fontWidth, posy + fontHeight - 1));
				}
			skipDrawing:

				posx += fontWidth;
			x++;
			if(x == screenWidth) {
				flushBuffer();
				x = 0;
				posy += fontHeight;
				posx = paddingLeft;
			}
		}

		if(cursorShowing) {
			painter.fillColor = cursorColor;
			painter.outlineColor = cursorColor;
			painter.rasterOp = RasterOp.xor;

			posx = cursorPosition.x * fontWidth + paddingLeft;
			posy = cursorPosition.y * fontHeight + paddingTop;

			int cursorWidth = fontWidth;
			int cursorHeight = fontHeight;

			final switch(cursorStyle) {
				case CursorStyle.block:
					painter.drawRectangle(Point(posx, posy), cursorWidth, cursorHeight);
				break;
				case CursorStyle.underline:
					painter.drawRectangle(Point(posx, posy + cursorHeight - 2), cursorWidth, 2);
				break;
				case CursorStyle.bar:
					painter.drawRectangle(Point(posx, posy), 2, cursorHeight);
				break;
			}
			painter.rasterOp = RasterOp.normal;

			// since the cursor draws over the cell, we need to make sure it is redrawn each time too
			auto buffer = alternateScreenActive ? (&alternateScreen) : (&normalScreen);
			if(cursorX >= 0 && cursorY >= 0 && cursorY < screenHeight && cursorX < screenWidth) {
				(*buffer)[cursorY * screenWidth + cursorX].invalidated = true;
			}

			invalidated.left = posx < invalidated.left ? posx : invalidated.left;
			invalidated.top = posy < invalidated.top ? posy : invalidated.top;
			int xmax = posx + fontWidth;
			int ymax = xmax + fontHeight;
			invalidated.right = xmax > invalidated.right ? xmax : invalidated.right;
			invalidated.bottom = ymax > invalidated.bottom ? ymax : invalidated.bottom;
		}

		lastDrawAlternativeScreen = alternateScreenActive;

		return invalidated;
	}


	// black bg, make the colors more visible
	Color contrastify(Color c) {
		if(c == Color(0xcd, 0, 0))
			return Color.fromHsl(0, 1.0, 0.75);
		else if(c == Color(0, 0, 0xcd))
			return Color.fromHsl(240, 1.0, 0.75);
		else if(c == Color(229, 229, 229))
			return Color(0x99, 0x99, 0x99);
		else return c;
	}

	// white bg, make them more visible
	Color antiContrastify(Color c) {
		if(c == Color(0xcd, 0xcd, 0))
			return Color.fromHsl(60, 1.0, 0.25);
		else if(c == Color(0, 0xcd, 0xcd))
			return Color.fromHsl(180, 1.0, 0.25);
		else if(c == Color(229, 229, 229))
			return Color(0x99, 0x99, 0x99);
		else return c;
	}

	bool debugMode = false;
}
