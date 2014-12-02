/**
 * Module for supporting cursor and color manipulation on the console.
 *
 * The main interface for this module is the Terminal struct, which
 * encapsulates the functions of the terminal. Creating an instance of
 * this struct will perform console initialization; when the struct
 * goes out of scope, any changes in console settings will be automatically
 * reverted.
 *
 * Note: on Posix, it traps SIGINT and translates it into an input event. You should
 * keep your event loop moving and keep an eye open for this to exit cleanly; simply break
 * your event loop upon receiving a UserInterruptionEvent. (Without
 * the signal handler, ctrl+c can leave your terminal in a bizarre state.)
 *
 * As a user, if you have to forcibly kill your program and the event doesn't work, there's still ctrl+\
 */
module terminal;

// FIXME: http://msdn.microsoft.com/en-us/library/windows/desktop/ms686016%28v=vs.85%29.aspx

version(linux)
	enum SIGWINCH = 28; // FIXME: confirm this is correct on other posix

version(Posix) {
	__gshared bool windowSizeChanged = false;
	__gshared bool interrupted = false;

	version(with_eventloop)
		struct SignalFired {}

	extern(C)
	void sizeSignalHandler(int sigNumber) nothrow {
		windowSizeChanged = true;
		version(with_eventloop) {
			import arsd.eventloop;
			try
				send(SignalFired());
			catch(Exception) {}
		}
	}
	extern(C)
	void interruptSignalHandler(int sigNumber) nothrow {
		interrupted = true;
		version(with_eventloop) {
			import arsd.eventloop;
			try
				send(SignalFired());
			catch(Exception) {}
		}
	}
}

// parts of this were taken from Robik's ConsoleD
// https://github.com/robik/ConsoleD/blob/master/consoled.d

// Uncomment this line to get a main() to demonstrate this module's
// capabilities.
//version = Demo

version(Windows) {
	import core.sys.windows.windows;
	import std.string : toStringz;
	private {
		enum RED_BIT = 4;
		enum GREEN_BIT = 2;
		enum BLUE_BIT = 1;
	}
}

version(Posix) {
	import core.sys.posix.termios;
	import core.sys.posix.unistd;
	import unix = core.sys.posix.unistd;
	import core.sys.posix.sys.types;
	import core.sys.posix.sys.time;
	import core.stdc.stdio;
	private {
		enum RED_BIT = 1;
		enum GREEN_BIT = 2;
		enum BLUE_BIT = 4;
	}

	extern(C) int ioctl(int, int, ...);
	enum int TIOCGWINSZ = 0x5413;
	struct winsize {
		ushort ws_row;
		ushort ws_col;
		ushort ws_xpixel;
		ushort ws_ypixel;
	}

	// I'm taking this from the minimal termcap from my Slackware box (which I use as my /etc/termcap) and just taking the most commonly used ones (for me anyway).

	// this way we'll have some definitions for 99% of typical PC cases even without any help from the local operating system

	enum string builtinTermcap = `
# Generic VT entry.
vg|vt-generic|Generic VT entries:\
	:bs:mi:ms:pt:xn:xo:it#8:\
	:RA=\E[?7l:SA=\E?7h:\
	:bl=^G:cr=^M:ta=^I:\
	:cm=\E[%i%d;%dH:\
	:le=^H:up=\E[A:do=\E[B:nd=\E[C:\
	:LE=\E[%dD:RI=\E[%dC:UP=\E[%dA:DO=\E[%dB:\
	:ho=\E[H:cl=\E[H\E[2J:ce=\E[K:cb=\E[1K:cd=\E[J:sf=\ED:sr=\EM:\
	:ct=\E[3g:st=\EH:\
	:cs=\E[%i%d;%dr:sc=\E7:rc=\E8:\
	:ei=\E[4l:ic=\E[@:IC=\E[%d@:al=\E[L:AL=\E[%dL:\
	:dc=\E[P:DC=\E[%dP:dl=\E[M:DL=\E[%dM:\
	:so=\E[7m:se=\E[m:us=\E[4m:ue=\E[m:\
	:mb=\E[5m:mh=\E[2m:md=\E[1m:mr=\E[7m:me=\E[m:\
	:sc=\E7:rc=\E8:kb=\177:\
	:ku=\E[A:kd=\E[B:kr=\E[C:kl=\E[D:


# Slackware 3.1 linux termcap entry (Sat Apr 27 23:03:58 CDT 1996):
lx|linux|console|con80x25|LINUX System Console:\
        :do=^J:co#80:li#25:cl=\E[H\E[J:sf=\ED:sb=\EM:\
        :le=^H:bs:am:cm=\E[%i%d;%dH:nd=\E[C:up=\E[A:\
        :ce=\E[K:cd=\E[J:so=\E[7m:se=\E[27m:us=\E[36m:ue=\E[m:\
        :md=\E[1m:mr=\E[7m:mb=\E[5m:me=\E[m:is=\E[1;25r\E[25;1H:\
        :ll=\E[1;25r\E[25;1H:al=\E[L:dc=\E[P:dl=\E[M:\
        :it#8:ku=\E[A:kd=\E[B:kr=\E[C:kl=\E[D:kb=^H:ti=\E[r\E[H:\
        :ho=\E[H:kP=\E[5~:kN=\E[6~:kH=\E[4~:kh=\E[1~:kD=\E[3~:kI=\E[2~:\
        :k1=\E[[A:k2=\E[[B:k3=\E[[C:k4=\E[[D:k5=\E[[E:k6=\E[17~:\
	:F1=\E[23~:F2=\E[24~:\
        :k7=\E[18~:k8=\E[19~:k9=\E[20~:k0=\E[21~:K1=\E[1~:K2=\E[5~:\
        :K4=\E[4~:K5=\E[6~:\
        :pt:sr=\EM:vt#3:xn:km:bl=^G:vi=\E[?25l:ve=\E[?25h:vs=\E[?25h:\
        :sc=\E7:rc=\E8:cs=\E[%i%d;%dr:\
        :r1=\Ec:r2=\Ec:r3=\Ec:

# Some other, commonly used linux console entries.
lx|con80x28:co#80:li#28:tc=linux:
lx|con80x43:co#80:li#43:tc=linux:
lx|con80x50:co#80:li#50:tc=linux:
lx|con100x37:co#100:li#37:tc=linux:
lx|con100x40:co#100:li#40:tc=linux:
lx|con132x43:co#132:li#43:tc=linux:

# vt102 - vt100 + insert line etc. VT102 does not have insert character.
v2|vt102|DEC vt102 compatible:\
	:co#80:li#24:\
	:ic@:IC@:\
	:is=\E[m\E[?1l\E>:\
	:rs=\E[m\E[?1l\E>:\
	:eA=\E)0:as=^N:ae=^O:ac=aaffggjjkkllmmnnooqqssttuuvvwwxx:\
	:ks=:ke=:\
	:k1=\EOP:k2=\EOQ:k3=\EOR:k4=\EOS:\
	:tc=vt-generic:

# vt100 - really vt102 without insert line, insert char etc.
vt|vt100|DEC vt100 compatible:\
	:im@:mi@:al@:dl@:ic@:dc@:AL@:DL@:IC@:DC@:\
	:tc=vt102:


# Entry for an xterm. Insert mode has been disabled.
vs|xterm|xterm-color|vs100|xterm terminal emulator (X Window System):\
	:am:bs:mi@:km:co#80:li#55:\
	:im@:ei@:\
	:ct=\E[3k:ue=\E[m:\
	:is=\E[m\E[?1l\E>:\
	:rs=\E[m\E[?1l\E>:\
	:vi=\E[?25l:ve=\E[?25h:\
	:eA=\E)0:as=^N:ae=^O:ac=aaffggjjkkllmmnnooqqssttuuvvwwxx:\
	:kI=\E[2~:kD=\E[3~:kP=\E[5~:kN=\E[6~:\
	:k1=\EOP:k2=\EOQ:k3=\EOR:k4=\EOS:k5=\E[15~:\
	:k6=\E[17~:k7=\E[18~:k8=\E[19~:k9=\E[20~:k0=\E[21~:\
	:F1=\E[23~:F2=\E[24~:\
	:kh=\E[H:kH=\E[F:\
	:ks=:ke=:\
	:te=\E[2J\E[?47l\E8:ti=\E7\E[?47h:\
	:tc=vt-generic:


#rxvt, added by me
rxvt|rxvt-unicode:\
	:am:bs:mi@:km:co#80:li#55:\
	:im@:ei@:\
	:ct=\E[3k:ue=\E[m:\
	:is=\E[m\E[?1l\E>:\
	:rs=\E[m\E[?1l\E>:\
	:vi=\E[?25l:\
	:ve=\E[?25h:\
	:eA=\E)0:as=^N:ae=^O:ac=aaffggjjkkllmmnnooqqssttuuvvwwxx:\
	:kI=\E[2~:kD=\E[3~:kP=\E[5~:kN=\E[6~:\
	:k1=\E[11~:k2=\E[12~:k3=\E[13~:k4=\E[14~:k5=\E[15~:\
	:k6=\E[17~:k7=\E[18~:k8=\E[19~:k9=\E[20~:k0=\E[21~:\
	:F1=\E[23~:F2=\E[24~:\
	:kh=\E[7~:kH=\E[8~:\
	:ks=:ke=:\
	:te=\E[2J\E[?47l\E8:ti=\E7\E[?47h:\
	:tc=vt-generic:


# Some other entries for the same xterm.
v2|xterms|vs100s|xterm small window:\
	:co#80:li#24:tc=xterm:
vb|xterm-bold|xterm with bold instead of underline:\
	:us=\E[1m:tc=xterm:
vi|xterm-ins|xterm with insert mode:\
	:mi:im=\E[4h:ei=\E[4l:tc=xterm:

Eterm|Eterm Terminal Emulator (X11 Window System):\
        :am:bw:eo:km:mi:ms:xn:xo:\
        :co#80:it#8:li#24:lm#0:pa#64:Co#8:AF=\E[3%dm:AB=\E[4%dm:op=\E[39m\E[49m:\
        :AL=\E[%dL:DC=\E[%dP:DL=\E[%dM:DO=\E[%dB:IC=\E[%d@:\
        :K1=\E[7~:K2=\EOu:K3=\E[5~:K4=\E[8~:K5=\E[6~:LE=\E[%dD:\
        :RI=\E[%dC:UP=\E[%dA:ae=^O:al=\E[L:as=^N:bl=^G:cd=\E[J:\
        :ce=\E[K:cl=\E[H\E[2J:cm=\E[%i%d;%dH:cr=^M:\
        :cs=\E[%i%d;%dr:ct=\E[3g:dc=\E[P:dl=\E[M:do=\E[B:\
        :ec=\E[%dX:ei=\E[4l:ho=\E[H:i1=\E[?47l\E>\E[?1l:ic=\E[@:\
        :im=\E[4h:is=\E[r\E[m\E[2J\E[H\E[?7h\E[?1;3;4;6l\E[4l:\
        :k1=\E[11~:k2=\E[12~:k3=\E[13~:k4=\E[14~:k5=\E[15~:\
        :k6=\E[17~:k7=\E[18~:k8=\E[19~:k9=\E[20~:kD=\E[3~:\
        :kI=\E[2~:kN=\E[6~:kP=\E[5~:kb=^H:kd=\E[B:ke=:kh=\E[7~:\
        :kl=\E[D:kr=\E[C:ks=:ku=\E[A:le=^H:mb=\E[5m:md=\E[1m:\
        :me=\E[m\017:mr=\E[7m:nd=\E[C:rc=\E8:\
        :sc=\E7:se=\E[27m:sf=^J:so=\E[7m:sr=\EM:st=\EH:ta=^I:\
        :te=\E[2J\E[?47l\E8:ti=\E7\E[?47h:ue=\E[24m:up=\E[A:\
        :us=\E[4m:vb=\E[?5h\E[?5l:ve=\E[?25h:vi=\E[?25l:\
        :ac=``aaffggiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~:

# DOS terminal emulator such as Telix or TeleMate.
# This probably also works for the SCO console, though it's incomplete.
an|ansi|ansi-bbs|ANSI terminals (emulators):\
	:co#80:li#24:am:\
	:is=:rs=\Ec:kb=^H:\
	:as=\E[m:ae=:eA=:\
	:ac=0\333+\257,\256.\031-\030a\261f\370g\361j\331k\277l\332m\300n\305q\304t\264u\303v\301w\302x\263~\025:\
	:kD=\177:kH=\E[Y:kN=\E[U:kP=\E[V:kh=\E[H:\
	:k1=\EOP:k2=\EOQ:k3=\EOR:k4=\EOS:k5=\EOT:\
	:k6=\EOU:k7=\EOV:k8=\EOW:k9=\EOX:k0=\EOY:\
	:tc=vt-generic:

	`;
}

enum Bright = 0x08;

/// Defines the list of standard colors understood by Terminal.
enum Color : ushort {
	black = 0, /// .
	red = RED_BIT, /// .
	green = GREEN_BIT, /// .
	yellow = red | green, /// .
	blue = BLUE_BIT, /// .
	magenta = red | blue, /// .
	cyan = blue | green, /// .
	white = red | green | blue, /// .
	DEFAULT = 256,
}

/// When capturing input, what events are you interested in?
///
/// Note: these flags can be OR'd together to select more than one option at a time.
///
/// Ctrl+C and other keyboard input is always captured, though it may be line buffered if you don't use raw.
enum ConsoleInputFlags {
	raw = 0, /// raw input returns keystrokes immediately, without line buffering
	echo = 1, /// do you want to automatically echo input back to the user?
	mouse = 2, /// capture mouse events
	paste = 4, /// capture paste events (note: without this, paste can come through as keystrokes)
	size = 8, /// window resize events

	allInputEvents = 8|4|2, /// subscribe to all input events.
}

/// Defines how terminal output should be handled.
enum ConsoleOutputType {
	linear = 0, /// do you want output to work one line at a time?
	cellular = 1, /// or do you want access to the terminal screen as a grid of characters?
	//truncatedCellular = 3, /// cellular, but instead of wrapping output to the next line automatically, it will truncate at the edges

	minimalProcessing = 255, /// do the least possible work, skips most construction and desturction tasks. Only use if you know what you're doing here
}

/// Some methods will try not to send unnecessary commands to the screen. You can override their judgement using a ForceOption parameter, if present
enum ForceOption {
	automatic = 0, /// automatically decide what to do (best, unless you know for sure it isn't right)
	neverSend = -1, /// never send the data. This will only update Terminal's internal state. Use with caution because this can
	alwaysSend = 1, /// always send the data, even if it doesn't seem necessary
}

// we could do it with termcap too, getenv("TERMCAP") then split on : and replace \E with \033 and get the pieces

/// Encapsulates the I/O capabilities of a terminal.
///
/// Warning: do not write out escape sequences to the terminal. This won't work
/// on Windows and will confuse Terminal's internal state on Posix.
struct Terminal {
	@disable this();
	@disable this(this);
	private ConsoleOutputType type;

	version(Posix) {
		private int fdOut;
		private int fdIn;
		private int[] delegate() getSizeOverride;
	}

	version(Posix) {
		bool terminalInFamily(string[] terms...) {
			import std.process;
			import std.string;
			auto term = environment.get("TERM");
			foreach(t; terms)
				if(indexOf(term, t) != -1)
					return true;

			return false;
		}

		static string[string] termcapDatabase;
		static void readTermcapFile(bool useBuiltinTermcap = false) {
			import std.file;
			import std.stdio;
			import std.string;

			if(!exists("/etc/termcap"))
				useBuiltinTermcap = true;

			string current;

			void commitCurrentEntry() {
				if(current is null)
					return;

				string names = current;
				auto idx = indexOf(names, ":");
				if(idx != -1)
					names = names[0 .. idx];

				foreach(name; split(names, "|"))
					termcapDatabase[name] = current;

				current = null;
			}

			void handleTermcapLine(in char[] line) {
				if(line.length == 0) { // blank
					commitCurrentEntry();
					return; // continue
				}
				if(line[0] == '#') // comment
					return; // continue
				size_t termination = line.length;
				if(line[$-1] == '\\')
					termination--; // cut off the \\
				current ~= strip(line[0 .. termination]);
				// termcap entries must be on one logical line, so if it isn't continued, we know we're done
				if(line[$-1] != '\\')
					commitCurrentEntry();
			}

			if(useBuiltinTermcap) {
				foreach(line; splitLines(builtinTermcap)) {
					handleTermcapLine(line);
				}
			} else {
				foreach(line; File("/etc/termcap").byLine()) {
					handleTermcapLine(line);
				}
			}
		}

		static string getTermcapDatabase(string terminal) {
			import std.string;

			if(termcapDatabase is null)
				readTermcapFile();

			auto data = terminal in termcapDatabase;
			if(data is null)
				return null;

			auto tc = *data;
			auto more = indexOf(tc, ":tc=");
			if(more != -1) {
				auto tcKey = tc[more + ":tc=".length .. $];
				auto end = indexOf(tcKey, ":");
				if(end != -1)
					tcKey = tcKey[0 .. end];
				tc = getTermcapDatabase(tcKey) ~ tc;
			}

			return tc;
		}

		string[string] termcap;
		void readTermcap() {
			import std.process;
			import std.string;
			import std.array;

			string termcapData = environment.get("TERMCAP");
			if(termcapData.length == 0) {
				termcapData = getTermcapDatabase(environment.get("TERM"));
			}

			auto e = replace(termcapData, "\\\n", "\n");
			termcap = null;

			foreach(part; split(e, ":")) {
				// FIXME: handle numeric things too

				auto things = split(part, "=");
				if(things.length)
					termcap[things[0]] =
						things.length > 1 ? things[1] : null;
			}
		}

		string findSequenceInTermcap(in char[] sequenceIn) {
			char[10] sequenceBuffer;
			char[] sequence;
			if(sequenceIn.length > 0 && sequenceIn[0] == '\033') {
				if(!(sequenceIn.length < sequenceBuffer.length - 1))
					return null;
				sequenceBuffer[1 .. sequenceIn.length + 1] = sequenceIn[];
				sequenceBuffer[0] = '\\';
				sequenceBuffer[1] = 'E';
				sequence = sequenceBuffer[0 .. sequenceIn.length + 1];
			} else {
				sequence = sequenceBuffer[1 .. sequenceIn.length + 1];
			}

			import std.array;
			foreach(k, v; termcap)
				if(v == sequence)
					return k;
			return null;
		}

		string getTermcap(string key) {
			auto k = key in termcap;
			if(k !is null) return *k;
			return null;
		}

		// Looks up a termcap item and tries to execute it. Returns false on failure
		bool doTermcap(T...)(string key, T t) {
			import std.conv;
			auto fs = getTermcap(key);
			if(fs is null)
				return false;

			int swapNextTwo = 0;

			R getArg(R)(int idx) {
				if(swapNextTwo == 2) {
					idx ++;
					swapNextTwo--;
				} else if(swapNextTwo == 1) {
					idx --;
					swapNextTwo--;
				}

				foreach(i, arg; t) {
					if(i == idx)
						return to!R(arg);
				}
				assert(0, to!string(idx) ~ " is out of bounds working " ~ fs);
			}

			char[256] buffer;
			int bufferPos = 0;

			void addChar(char c) {
				import std.exception;
				enforce(bufferPos < buffer.length);
				buffer[bufferPos++] = c;
			}

			void addString(in char[] c) {
				import std.exception;
				enforce(bufferPos + c.length < buffer.length);
				buffer[bufferPos .. bufferPos + c.length] = c[];
				bufferPos += c.length;
			}

			void addInt(int c, int minSize) {
				import std.string;
				auto str = format("%0"~(minSize ? to!string(minSize) : "")~"d", c);
				addString(str);
			}

			bool inPercent;
			int argPosition = 0;
			int incrementParams = 0;
			bool skipNext;
			bool nextIsChar;
			bool inBackslash;

			foreach(char c; fs) {
				if(inBackslash) {
					if(c == 'E')
						addChar('\033');
					else
						addChar(c);
					inBackslash = false;
				} else if(nextIsChar) {
					if(skipNext)
						skipNext = false;
					else
						addChar(cast(char) (c + getArg!int(argPosition) + (incrementParams ? 1 : 0)));
					if(incrementParams) incrementParams--;
					argPosition++;
					inPercent = false;
				} else if(inPercent) {
					switch(c) {
						case '%':
							addChar('%');
							inPercent = false;
						break;
						case '2':
						case '3':
						case 'd':
							if(skipNext)
								skipNext = false;
							else
								addInt(getArg!int(argPosition) + (incrementParams ? 1 : 0),
									c == 'd' ? 0 : (c - '0')
								);
							if(incrementParams) incrementParams--;
							argPosition++;
							inPercent = false;
						break;
						case '.':
							if(skipNext)
								skipNext = false;
							else
								addChar(cast(char) (getArg!int(argPosition) + (incrementParams ? 1 : 0)));
							if(incrementParams) incrementParams--;
							argPosition++;
						break;
						case '+':
							nextIsChar = true;
							inPercent = false;
						break;
						case 'i':
							incrementParams = 2;
							inPercent = false;
						break;
						case 's':
							skipNext = true;
							inPercent = false;
						break;
						case 'b':
							argPosition--;
							inPercent = false;
						break;
						case 'r':
							swapNextTwo = 2;
							inPercent = false;
						break;
						// FIXME: there's more
						// http://www.gnu.org/software/termutils/manual/termcap-1.3/html_mono/termcap.html

						default:
							assert(0, "not supported " ~ c);
					}
				} else {
					if(c == '%')
						inPercent = true;
					else if(c == '\\')
						inBackslash = true;
					else
						addChar(c);
				}
			}

			writeStringRaw(buffer[0 .. bufferPos]);
			return true;
		}
	}

	version(Posix)
	/**
	 * Constructs an instance of Terminal representing the capabilities of
	 * the current terminal.
	 *
	 * While it is possible to override the stdin+stdout file descriptors, remember
	 * that is not portable across platforms and be sure you know what you're doing.
	 *
	 * ditto on getSizeOverride. That's there so you can do something instead of ioctl.
	 */
	this(ConsoleOutputType type, int fdIn = 0, int fdOut = 1, int[] delegate() getSizeOverride = null) {
		this.fdIn = fdIn;
		this.fdOut = fdOut;
		this.getSizeOverride = getSizeOverride;
		this.type = type;

		readTermcap();

		if(type == ConsoleOutputType.minimalProcessing) {
			_suppressDestruction = true;
			return;
		}

		if(type == ConsoleOutputType.cellular) {
			doTermcap("ti");
			moveTo(0, 0, ForceOption.alwaysSend); // we need to know where the cursor is for some features to work, and moving it is easier than querying it
		}

		if(terminalInFamily("xterm", "rxvt", "screen")) {
			writeStringRaw("\033[22;0t"); // save window title on a stack (support seems spotty, but it doesn't hurt to have it)
		}
	}

	version(Windows)
		HANDLE hConsole;

	version(Windows)
	/// ditto
	this(ConsoleOutputType type) {
		hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
		if(type == ConsoleOutputType.cellular) {
			/*
http://msdn.microsoft.com/en-us/library/windows/desktop/ms686125%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms683193%28v=vs.85%29.aspx
			*/
			COORD size;
			/*
			CONSOLE_SCREEN_BUFFER_INFO sbi;
			GetConsoleScreenBufferInfo(hConsole, &sbi);
			size.X = cast(short) GetSystemMetrics(SM_CXMIN);
			size.Y = cast(short) GetSystemMetrics(SM_CYMIN);
			*/

			// FIXME: this sucks, maybe i should just revert it. but there shouldn't be scrollbars in cellular mode
			size.X = 80;
			size.Y = 24;
			SetConsoleScreenBufferSize(hConsole, size);
			moveTo(0, 0, ForceOption.alwaysSend); // we need to know where the cursor is for some features to work, and moving it is easier than querying it
		}
	}

	// only use this if you are sure you know what you want, since the terminal is a shared resource you generally really want to reset it to normal when you leave...
	bool _suppressDestruction;

	version(Posix)
	~this() {
		if(_suppressDestruction) {
			flush();
			return;
		}
		if(type == ConsoleOutputType.cellular) {
			doTermcap("te");
		}
		if(terminalInFamily("xterm", "rxvt", "screen")) {
			writeStringRaw("\033[23;0t"); // restore window title from the stack
		}
		showCursor();
		reset();
		flush();
	}

	version(Windows)
	~this() {
		reset();
		flush();
		showCursor();
	}

	int _currentForeground = Color.DEFAULT;
	int _currentBackground = Color.DEFAULT;
	bool reverseVideo = false;

	/// Changes the current color. See enum Color for the values.
	void color(int foreground, int background, ForceOption force = ForceOption.automatic, bool reverseVideo = false) {
		if(force != ForceOption.neverSend) {
			version(Windows) {
				// assuming a dark background on windows, so LowContrast == dark which means the bit is NOT set on hardware
				/*
				foreground ^= LowContrast;
				background ^= LowContrast;
				*/

				ushort setTof = cast(ushort) foreground;
				ushort setTob = cast(ushort) background;

				// this isn't necessarily right but meh
				if(background == Color.DEFAULT)
					setTob = Color.black;
				if(foreground == Color.DEFAULT)
					setTof = Color.white;

				if(force == ForceOption.alwaysSend || reverseVideo != this.reverseVideo || foreground != _currentForeground || background != _currentBackground) {
					flush(); // if we don't do this now, the buffering can screw up the colors...
					if(reverseVideo) {
						if(background == Color.DEFAULT)
							setTof = Color.black;
						else
							setTof = cast(ushort) background | (foreground & Bright);

						if(background == Color.DEFAULT)
							setTob = Color.white;
						else
							setTob = cast(ushort) (foreground & ~Bright);
					}
					SetConsoleTextAttribute(
						GetStdHandle(STD_OUTPUT_HANDLE),
						cast(ushort)((setTob << 4) | setTof));
				}
			} else {
				import std.process;
				// I started using this envvar for my text editor, but now use it elsewhere too
				// if we aren't set to dark, assume light
				/*
				if(getenv("ELVISBG") == "dark") {
					// LowContrast on dark bg menas
				} else {
					foreground ^= LowContrast;
					background ^= LowContrast;
				}
				*/

				ushort setTof = cast(ushort) foreground & ~Bright;
				ushort setTob = cast(ushort) background & ~Bright;

				if(foreground & Color.DEFAULT)
					setTof = 9; // ansi sequence for reset
				if(background == Color.DEFAULT)
					setTob = 9;

				import std.string;

				if(force == ForceOption.alwaysSend || reverseVideo != this.reverseVideo || foreground != _currentForeground || background != _currentBackground) {
					writeStringRaw(format("\033[%dm\033[3%dm\033[4%dm\033[%dm",
						(foreground != Color.DEFAULT && (foreground & Bright)) ? 1 : 0,
						cast(int) setTof,
						cast(int) setTob,
						reverseVideo ? 7 : 27
					));
				}
			}
		}

		_currentForeground = foreground;
		_currentBackground = background;
		this.reverseVideo = reverseVideo;
	}

	/// Returns the terminal to normal output colors
	void reset() {
		version(Windows)
			SetConsoleTextAttribute(
				GetStdHandle(STD_OUTPUT_HANDLE),
				cast(ushort)((Color.black << 4) | Color.white));
		else
			writeStringRaw("\033[0m");
	}

	// FIXME: add moveRelative

	/// The current x position of the output cursor. 0 == leftmost column
	@property int cursorX() {
		return _cursorX;
	}

	/// The current y position of the output cursor. 0 == topmost row
	@property int cursorY() {
		return _cursorY;
	}

	private int _cursorX;
	private int _cursorY;

	/// Moves the output cursor to the given position. (0, 0) is the upper left corner of the screen. The force parameter can be used to force an update, even if Terminal doesn't think it is necessary
	void moveTo(int x, int y, ForceOption force = ForceOption.automatic) {
		if(force != ForceOption.neverSend && (force == ForceOption.alwaysSend || x != _cursorX || y != _cursorY)) {
			version(Posix)
				doTermcap("cm", y, x);
			else version(Windows) {

				flush(); // if we don't do this now, the buffering can screw up the position
				COORD coord = {cast(short) x, cast(short) y};
				SetConsoleCursorPosition(hConsole, coord);
			} else static assert(0);
		}

		_cursorX = x;
		_cursorY = y;
	}

	/// shows the cursor
	void showCursor() {
		version(Posix)
			doTermcap("ve");
		else {
			CONSOLE_CURSOR_INFO info;
			GetConsoleCursorInfo(hConsole, &info);
			info.bVisible = true;
			SetConsoleCursorInfo(hConsole, &info);
		}
	}

	/// hides the cursor
	void hideCursor() {
		version(Posix) {
			doTermcap("vi");
		} else {
			CONSOLE_CURSOR_INFO info;
			GetConsoleCursorInfo(hConsole, &info);
			info.bVisible = false;
			SetConsoleCursorInfo(hConsole, &info);
		}

	}

	/*
	// alas this doesn't work due to a bunch of delegate context pointer and postblit problems
	// instead of using: auto input = terminal.captureInput(flags)
	// use: auto input = RealTimeConsoleInput(&terminal, flags);
	/// Gets real time input, disabling line buffering
	RealTimeConsoleInput captureInput(ConsoleInputFlags flags) {
		return RealTimeConsoleInput(&this, flags);
	}
	*/

	/// Changes the terminal's title
	void setTitle(string t) {
		version(Windows) {
			SetConsoleTitleA(toStringz(t));
		} else {
			import std.string;
			if(terminalInFamily("xterm", "rxvt", "screen"))
				writeStringRaw(format("\033]0;%s\007", t));
		}
	}

	/// Flushes your updates to the terminal.
	/// It is important to call this when you are finished writing for now if you are using the version=with_eventloop
	void flush() {
		version(Posix) {
			ssize_t written;

			while(writeBuffer.length) {
				written = unix.write(this.fdOut, writeBuffer.ptr, writeBuffer.length);
				if(written < 0)
					throw new Exception("write failed for some reason");
				writeBuffer = writeBuffer[written .. $];
			}
		} else version(Windows) {
			while(writeBuffer.length) {
				DWORD written;
				/* FIXME: WriteConsoleW */
				WriteConsoleA(hConsole, writeBuffer.ptr, writeBuffer.length, &written, null);
				writeBuffer = writeBuffer[written .. $];
			}
		}
		// not buffering right now on Windows, since it probably isn't on ssh anyway
	}

	int[] getSize() {
		version(Windows) {
			CONSOLE_SCREEN_BUFFER_INFO info;
			GetConsoleScreenBufferInfo( hConsole, &info );
        
			int cols, rows;
        
			cols = (info.srWindow.Right - info.srWindow.Left + 1);
			rows = (info.srWindow.Bottom - info.srWindow.Top + 1);

			return [cols, rows];
		} else {
			if(getSizeOverride is null) {
				winsize w;
				ioctl(0, TIOCGWINSZ, &w);
				return [w.ws_col, w.ws_row];
			} else return getSizeOverride();
		}
	}

	void updateSize() {
		auto size = getSize();
		_width = size[0];
		_height = size[1];
	}

	private int _width;
	private int _height;

	/// The current width of the terminal (the number of columns)
	@property int width() {
		if(_width == 0 || _height == 0)
			updateSize();
		return _width;
	}

	/// The current height of the terminal (the number of rows)
	@property int height() {
		if(_width == 0 || _height == 0)
			updateSize();
		return _height;
	}

	/*
	void write(T...)(T t) {
		foreach(arg; t) {
			writeStringRaw(to!string(arg));
		}
	}
	*/

	/// Writes to the terminal at the current cursor position.
	void writef(T...)(string f, T t) {
		import std.string;
		writePrintableString(format(f, t));
	}

	/// ditto
	void writefln(T...)(string f, T t) {
		writef(f ~ "\n", t);
	}

	/// ditto
	void write(T...)(T t) {
		import std.conv;
		string data;
		foreach(arg; t) {
			data ~= to!string(arg);
		}

		writePrintableString(data);
	}

	/// ditto
	void writeln(T...)(T t) {
		write(t, "\n");
	}

	/+
	/// A combined moveTo and writef that puts the cursor back where it was before when it finishes the write.
	/// Only works in cellular mode. 
	/// Might give better performance than moveTo/writef because if the data to write matches the internal buffer, it skips sending anything (to override the buffer check, you can use moveTo and writePrintableString with ForceOption.alwaysSend)
	void writefAt(T...)(int x, int y, string f, T t) {
		import std.string;
		auto toWrite = format(f, t);

		auto oldX = _cursorX;
		auto oldY = _cursorY;

		writeAtWithoutReturn(x, y, toWrite);

		moveTo(oldX, oldY);
	}

	void writeAtWithoutReturn(int x, int y, in char[] data) {
		moveTo(x, y);
		writeStringRaw(toWrite, ForceOption.alwaysSend);
	}
	+/

	void writePrintableString(in char[] s, ForceOption force = ForceOption.automatic) {
		// an escape character is going to mess things up. Actually any non-printable character could, but meh
		// assert(s.indexOf("\033") == -1);

		// tracking cursor position
		foreach(ch; s) {
			switch(ch) {
				case '\n':
					_cursorX = 0;
					_cursorY++;
				break;
				case '\t':
					_cursorX ++;
					_cursorX += _cursorX % 8; // FIXME: get the actual tabstop, if possible
				break;
				default:
					_cursorX++;
			}

			if(_wrapAround && _cursorX > width) {
				_cursorX = 0;
				_cursorY++;
			}

			if(_cursorY == height)
				_cursorY--;

			/+
			auto index = getIndex(_cursorX, _cursorY);
			if(data[index] != ch) {
				data[index] = ch;
			}
			+/
		}

		writeStringRaw(s);
	}

	/* private */ bool _wrapAround = true;

	deprecated alias writePrintableString writeString; /// use write() or writePrintableString instead

	private string writeBuffer;

	// you really, really shouldn't use this unless you know what you are doing
	/*private*/ void writeStringRaw(in char[] s) {
		// FIXME: make sure all the data is sent, check for errors
		version(Posix) {
			writeBuffer ~= s; // buffer it to do everything at once in flush() calls
		} else version(Windows) {
			writeBuffer ~= s;
		} else static assert(0);
	}

	/// Clears the screen.
	void clear() {
		version(Posix) {
			doTermcap("cl");
		} else version(Windows) {
			// TBD: copy the code from here and test it:
			// http://support.microsoft.com/kb/99261
			assert(0, "clear not yet implemented");
		}

		_cursorX = 0;
		_cursorY = 0;
	}
}

/+
struct ConsoleBuffer {
	int cursorX;
	int cursorY;
	int width;
	int height;
	dchar[] data;

	void actualize(Terminal* t) {
		auto writer = t.getBufferedWriter();

		this.copyTo(&(t.onScreen));
	}

	void copyTo(ConsoleBuffer* buffer) {
		buffer.cursorX = this.cursorX;
		buffer.cursorY = this.cursorY;
		buffer.width = this.width;
		buffer.height = this.height;
		buffer.data[] = this.data[];
	}
}
+/

/**
 * Encapsulates the stream of input events received from the terminal input.
 */
struct RealTimeConsoleInput {
	@disable this();
	@disable this(this);

	version(Posix) {
		private int fdOut;
		private int fdIn;
		private sigaction_t oldSigWinch;
		private sigaction_t oldSigIntr;
		private termios old;
		ubyte[128] hack;
		// apparently termios isn't the size druntime thinks it is (at least on 32 bit, sometimes)....
		// tcgetattr smashed other variables in here too that could create random problems
		// so this hack is just to give some room for that to happen without destroying the rest of the world
	}

	version(Windows) {
		private DWORD oldInput;
		private DWORD oldOutput;
		HANDLE inputHandle;
	}

	private ConsoleInputFlags flags;
	private Terminal* terminal;
	private void delegate()[] destructor;

	/// To capture input, you need to provide a terminal and some flags.
	public this(Terminal* terminal, ConsoleInputFlags flags) {
		this.flags = flags;
		this.terminal = terminal;

		version(Windows) {
			inputHandle = GetStdHandle(STD_INPUT_HANDLE);

			GetConsoleMode(inputHandle, &oldInput);

			DWORD mode = 0;
			mode |= ENABLE_PROCESSED_INPUT /* 0x01 */; // this gives Ctrl+C which we probably want to be similar to linux
			//if(flags & ConsoleInputFlags.size)
			mode |= ENABLE_WINDOW_INPUT /* 0208 */; // gives size etc
			if(flags & ConsoleInputFlags.echo)
				mode |= ENABLE_ECHO_INPUT; // 0x4
			if(flags & ConsoleInputFlags.mouse)
				mode |= ENABLE_MOUSE_INPUT; // 0x10
			// if(flags & ConsoleInputFlags.raw) // FIXME: maybe that should be a separate flag for ENABLE_LINE_INPUT

			SetConsoleMode(inputHandle, mode);
			destructor ~= { SetConsoleMode(inputHandle, oldInput); };


			GetConsoleMode(terminal.hConsole, &oldOutput);
			mode = 0;
			// we want this to match linux too
			mode |= ENABLE_PROCESSED_OUTPUT; /* 0x01 */
			mode |= ENABLE_WRAP_AT_EOL_OUTPUT; /* 0x02 */
			SetConsoleMode(terminal.hConsole, mode);
			destructor ~= { SetConsoleMode(terminal.hConsole, oldOutput); };

			// FIXME: change to UTF8 as well
		}

		version(Posix) {
			this.fdIn = terminal.fdIn;
			this.fdOut = terminal.fdOut;

			if(fdIn != -1) {
				tcgetattr(fdIn, &old);
				auto n = old;

				auto f = ICANON;
				if(!(flags & ConsoleInputFlags.echo))
					f |= ECHO;

				n.c_lflag &= ~f;
				tcsetattr(fdIn, TCSANOW, &n);
			}

			// some weird bug breaks this, https://github.com/robik/ConsoleD/issues/3
			//destructor ~= { tcsetattr(fdIn, TCSANOW, &old); };

			if(flags & ConsoleInputFlags.size) {
				import core.sys.posix.signal;
				sigaction_t n;
				n.sa_handler = &sizeSignalHandler;
				n.sa_mask = cast(sigset_t) 0;
				n.sa_flags = 0;
				sigaction(SIGWINCH, &n, &oldSigWinch);
			}

			{
				import core.sys.posix.signal;
				sigaction_t n;
				n.sa_handler = &interruptSignalHandler;
				n.sa_mask = cast(sigset_t) 0;
				n.sa_flags = 0;
				sigaction(SIGINT, &n, &oldSigIntr);
			}


			if(flags & ConsoleInputFlags.mouse) {
				// basic button press+release notification

				// FIXME: try to get maximum capabilities from all terminals
				// right now this works well on xterm but rxvt isn't sending movements...

				terminal.writeStringRaw("\033[?1000h");
				destructor ~= { terminal.writeStringRaw("\033[?1000l"); };
				if(terminal.terminalInFamily("xterm")) {
					// this is vt200 mouse with full motion tracking, supported by xterm
					terminal.writeStringRaw("\033[?1003h");
					destructor ~= { terminal.writeStringRaw("\033[?1003l"); };
				} else if(terminal.terminalInFamily("rxvt", "screen")) {
					terminal.writeStringRaw("\033[?1002h"); // this is vt200 mouse with press/release and motion notification iff buttons are pressed
					destructor ~= { terminal.writeStringRaw("\033[?1002l"); };
				}
			}
			if(flags & ConsoleInputFlags.paste) {
				if(terminal.terminalInFamily("xterm", "rxvt", "screen")) {
					terminal.writeStringRaw("\033[?2004h"); // bracketed paste mode
					destructor ~= { terminal.writeStringRaw("\033[?2004l"); };
				}
			}

			// try to ensure the terminal is in UTF-8 mode
			if(terminal.terminalInFamily("xterm", "screen", "linux")) {
				terminal.writeStringRaw("\033%G");
			}

			terminal.flush();
		}


		version(with_eventloop) {
			import arsd.eventloop;
			version(Windows)
				auto listenTo = inputHandle;
			else version(Posix)
				auto listenTo = this.fdIn;
			else static assert(0, "idk about this OS");

			version(Posix)
			addListener(&signalFired);

			if(listenTo != -1) {
				addFileEventListeners(listenTo, &eventListener, null, null);
				destructor ~= { removeFileEventListeners(listenTo); };
			}
			addOnIdle(&terminal.flush);
			destructor ~= { removeOnIdle(&terminal.flush); };
		}
	}

	version(with_eventloop) {
		version(Posix)
		void signalFired(SignalFired) {
			if(interrupted) {
				interrupted = false;
				send(InputEvent(UserInterruptionEvent()));
			}
			if(windowSizeChanged)
				send(checkWindowSizeChanged());
		}

		import arsd.eventloop;
		void eventListener(OsFileHandle fd) {
			auto queue = readNextEvents();
			foreach(event; queue)
				send(event);
		}
	}

	~this() {
		// the delegate thing doesn't actually work for this... for some reason
		version(Posix)
			if(fdIn != -1)
				tcsetattr(fdIn, TCSANOW, &old);

		version(Posix) {
			if(flags & ConsoleInputFlags.size) {
				// restoration
				sigaction(SIGWINCH, &oldSigWinch, null);
			}
			sigaction(SIGINT, &oldSigIntr, null);
		}

		// we're just undoing everything the constructor did, in reverse order, same criteria
		foreach_reverse(d; destructor)
			d();
	}

	/// Returns true if there is input available now
	bool kbhit() {
		return timedCheckForInput(0);
	}

	/// Check for input, waiting no longer than the number of milliseconds
	bool timedCheckForInput(int milliseconds) {
		version(Windows) {
			auto response = WaitForSingleObject(terminal.hConsole, milliseconds);
			if(response  == 0)
				return true; // the object is ready
			return false;
		} else version(Posix) {
			if(fdIn == -1)
				return false;

			timeval tv;
			tv.tv_sec = 0;
			tv.tv_usec = milliseconds * 1000;

			fd_set fs;
			FD_ZERO(&fs);

			FD_SET(fdIn, &fs);
			select(fdIn + 1, &fs, null, null, &tv);

			return FD_ISSET(fdIn, &fs);
		}
	}

	/// Get one character from the terminal, discarding other
	/// events in the process.
	dchar getch() {
		auto event = nextEvent();
		while(event.type != InputEvent.Type.CharacterEvent) {
			if(event.type == InputEvent.Type.UserInterruptionEvent)
				throw new Exception("Ctrl+c");
			event = nextEvent();
		}
		return event.characterEvent.character;
	}

	//char[128] inputBuffer;
	//int inputBufferPosition;
	version(Posix)
	int nextRaw(bool interruptable = false) {
		if(fdIn == -1)
			return 0;

		char[1] buf;
		try_again:
		auto ret = read(fdIn, buf.ptr, buf.length);
		if(ret == 0)
			return 0; // input closed
		if(ret == -1) {
			import core.stdc.errno;
			if(errno == EINTR)
				// interrupted by signal call, quite possibly resize or ctrl+c which we want to check for in the event loop
				if(interruptable)
					return -1;
				else
					goto try_again;
			else
				throw new Exception("read failed");
		}

		//terminal.writef("RAW READ: %d\n", buf[0]);

		if(ret == 1)
			return inputPrefilter ? inputPrefilter(buf[0]) : buf[0];
		else
			assert(0); // read too much, should be impossible
	}

	version(Posix)
		int delegate(char) inputPrefilter;

	version(Posix)
	dchar nextChar(int starting) {
		if(starting <= 127)
			return cast(dchar) starting;
		char[6] buffer;
		int pos = 0;
		buffer[pos++] = cast(char) starting;

		// see the utf-8 encoding for details
		int remaining = 0;
		ubyte magic = starting & 0xff;
		while(magic & 0b1000_000) {
			remaining++;
			magic <<= 1;
		}

		while(remaining && pos < buffer.length) {
			buffer[pos++] = cast(char) nextRaw();
			remaining--;
		}

		import std.utf;
		size_t throwAway; // it insists on the index but we don't care
		return decode(buffer[], throwAway);
	}

	InputEvent checkWindowSizeChanged() {
		auto oldWidth = terminal.width;
		auto oldHeight = terminal.height;
		terminal.updateSize();
		version(Posix)
		windowSizeChanged = false;
		return InputEvent(SizeChangedEvent(oldWidth, oldHeight, terminal.width, terminal.height));
	}


	// character event
	// non-character key event
	// paste event
	// mouse event
	// size event maybe, and if appropriate focus events

	/// Returns the next event.
	///
	/// Experimental: It is also possible to integrate this into
	/// a generic event loop, currently under -version=with_eventloop and it will
	/// require the module arsd.eventloop (Linux only at this point)
	InputEvent nextEvent() {
		terminal.flush();
		if(inputQueue.length) {
			auto e = inputQueue[0];
			inputQueue = inputQueue[1 .. $];
			return e;
		}

		wait_for_more:
		version(Posix)
		if(interrupted) {
			interrupted = false;
			return InputEvent(UserInterruptionEvent());
		}

		version(Posix)
		if(windowSizeChanged) {
			return checkWindowSizeChanged();
		}

		auto more = readNextEvents();
		if(!more.length)
			goto wait_for_more; // i used to do a loop (readNextEvents can read something, but it might be discarded by the input filter) but now it goto's above because readNextEvents might be interrupted by a SIGWINCH aka size event so we want to check that at least

		assert(more.length);

		auto e = more[0];
		inputQueue = more[1 .. $];
		return e;
	}

	InputEvent* peekNextEvent() {
		if(inputQueue.length)
			return &(inputQueue[0]);
		return null;
	}

	enum InjectionPosition { head, tail }
	void injectEvent(InputEvent ev, InjectionPosition where) {
		final switch(where) {
			case InjectionPosition.head:
				inputQueue = ev ~ inputQueue;
			break;
			case InjectionPosition.tail:
				inputQueue ~= ev;
			break;
		}
	}

	InputEvent[] inputQueue;

	version(Windows)
	InputEvent[] readNextEvents() {
		terminal.flush(); // make sure all output is sent out before waiting for anything

		INPUT_RECORD[32] buffer;
		DWORD actuallyRead;
			// FIXME: ReadConsoleInputW
		auto success = ReadConsoleInputA(inputHandle, buffer.ptr, buffer.length, &actuallyRead);
		if(success == 0)
			throw new Exception("ReadConsoleInput");

		InputEvent[] newEvents;
		input_loop: foreach(record; buffer[0 .. actuallyRead]) {
			switch(record.EventType) {
				case KEY_EVENT:
					auto ev = record.KeyEvent;
					CharacterEvent e;
					NonCharacterKeyEvent ne;

					e.eventType = ev.bKeyDown ? CharacterEvent.Type.Pressed : CharacterEvent.Type.Released;
					ne.eventType = ev.bKeyDown ? NonCharacterKeyEvent.Type.Pressed : NonCharacterKeyEvent.Type.Released;

					e.modifierState = ev.dwControlKeyState;
					ne.modifierState = ev.dwControlKeyState;

					if(ev.UnicodeChar) {
						e.character = cast(dchar) cast(wchar) ev.UnicodeChar;
						newEvents ~= InputEvent(e);
					} else {
						ne.key = cast(NonCharacterKeyEvent.Key) ev.wVirtualKeyCode;

						// FIXME: make this better. the goal is to make sure the key code is a valid enum member
						// Windows sends more keys than Unix and we're doing lowest common denominator here
						foreach(member; __traits(allMembers, NonCharacterKeyEvent.Key))
							if(__traits(getMember, NonCharacterKeyEvent.Key, member) == ne.key) {
								newEvents ~= InputEvent(ne);
								break;
							}
					}
				break;
				case MOUSE_EVENT:
					auto ev = record.MouseEvent;
					MouseEvent e;

					e.modifierState = ev.dwControlKeyState;
					e.x = ev.dwMousePosition.X;
					e.y = ev.dwMousePosition.Y;

					switch(ev.dwEventFlags) {
						case 0:
							//press or release
							e.eventType = MouseEvent.Type.Pressed;
							static DWORD lastButtonState;
							auto lastButtonState2 = lastButtonState;
							e.buttons = ev.dwButtonState;
							lastButtonState = e.buttons;

							// this is sent on state change. if fewer buttons are pressed, it must mean released
							if(cast(DWORD) e.buttons < lastButtonState2) {
								e.eventType = MouseEvent.Type.Released;
								// if last was 101 and now it is 100, then button far right was released
								// so we flip the bits, ~100 == 011, then and them: 101 & 011 == 001, the
								// button that was released
								e.buttons = lastButtonState2 & ~e.buttons;
							}
						break;
						case MOUSE_MOVED:
							e.eventType = MouseEvent.Type.Moved;
							e.buttons = ev.dwButtonState;
						break;
						case 0x0004/*MOUSE_WHEELED*/:
							e.eventType = MouseEvent.Type.Pressed;
							if(ev.dwButtonState > 0)
								e.buttons = MouseEvent.Button.ScrollDown;
							else
								e.buttons = MouseEvent.Button.ScrollUp;
						break;
						default:
							continue input_loop;
					}

					newEvents ~= InputEvent(e);
				break;
				case WINDOW_BUFFER_SIZE_EVENT:
					auto ev = record.WindowBufferSizeEvent;
					auto oldWidth = terminal.width;
					auto oldHeight = terminal.height;
					terminal._width = ev.dwSize.X;
					terminal._height = ev.dwSize.Y;
					newEvents ~= InputEvent(SizeChangedEvent(oldWidth, oldHeight, terminal.width, terminal.height));
				break;
				// FIXME: can we catch ctrl+c here too?
				default:
					// ignore
			}
		}

		return newEvents;
	}

	version(Posix)
	InputEvent[] readNextEvents() {
		terminal.flush(); // make sure all output is sent out before we try to get input

		InputEvent[] charPressAndRelease(dchar character) {
			return [
				InputEvent(CharacterEvent(CharacterEvent.Type.Pressed, character, 0)),
				InputEvent(CharacterEvent(CharacterEvent.Type.Released, character, 0)),
			];
		}
		InputEvent[] keyPressAndRelease(NonCharacterKeyEvent.Key key, uint modifiers = 0) {
			return [
				InputEvent(NonCharacterKeyEvent(NonCharacterKeyEvent.Type.Pressed, key, modifiers)),
				InputEvent(NonCharacterKeyEvent(NonCharacterKeyEvent.Type.Released, key, modifiers)),
			];
		}

		char[30] sequenceBuffer;

		// this assumes you just read "\033["
		char[] readEscapeSequence(char[] sequence) {
			int sequenceLength = 2;
			sequence[0] = '\033';
			sequence[1] = '[';

			while(sequenceLength < sequence.length) {
				auto n = nextRaw();
				sequence[sequenceLength++] = cast(char) n;
				// I think a [ is supposed to termiate a CSI sequence
				// but the Linux console sends CSI[A for F1, so I'm
				// hacking it to accept that too
				if(n >= 0x40 && !(sequenceLength == 3 && n == '['))
					break;
			}

			return sequence[0 .. sequenceLength];
		}

		InputEvent[] translateTermcapName(string cap) {
			switch(cap) {
				//case "k0":
					//return keyPressAndRelease(NonCharacterKeyEvent.Key.F1);
				case "k1":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F1);
				case "k2":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F2);
				case "k3":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F3);
				case "k4":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F4);
				case "k5":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F5);
				case "k6":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F6);
				case "k7":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F7);
				case "k8":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F8);
				case "k9":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F9);
				case "k;":
				case "k0":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F10);
				case "F1":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F11);
				case "F2":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.F12);


				case "kb":
					return charPressAndRelease('\b');
				case "kD":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.Delete);

				case "kd":
				case "do":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.DownArrow);
				case "ku":
				case "up":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.UpArrow);
				case "kl":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.LeftArrow);
				case "kr":
				case "nd":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.RightArrow);

				case "kN":
				case "K5":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.PageDown);
				case "kP":
				case "K2":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.PageUp);

				case "kh":
				case "K1":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.Home);
				case "kH":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.End);
				case "kI":
					return keyPressAndRelease(NonCharacterKeyEvent.Key.Insert);
				default:
					// don't know it, just ignore
					//import std.stdio;
					//writeln(cap);
			}

			return null;
		}


		InputEvent[] doEscapeSequence(in char[] sequence) {
			switch(sequence) {
				case "\033[200~":
					// bracketed paste begin
					// we want to keep reading until
					// "\033[201~":
					// and build a paste event out of it


					string data;
					for(;;) {
						auto n = nextRaw();
						if(n == '\033') {
							n = nextRaw();
							if(n == '[') {
								auto esc = readEscapeSequence(sequenceBuffer);
								if(esc == "\033[201~") {
									// complete!
									break;
								} else {
									// was something else apparently, but it is pasted, so keep it
									data ~= esc;
								}
							} else {
								data ~= '\033';
								data ~= cast(char) n;
							}
						} else {
							data ~= cast(char) n;
						}
					}
					return [InputEvent(PasteEvent(data))];
				case "\033[M":
					// mouse event
					auto buttonCode = nextRaw() - 32;
						// nextChar is commented because i'm not using UTF-8 mouse mode
						// cuz i don't think it is as widely supported
					auto x = cast(int) (/*nextChar*/(nextRaw())) - 33; /* they encode value + 32, but make upper left 1,1. I want it to be 0,0 */
					auto y = cast(int) (/*nextChar*/(nextRaw())) - 33; /* ditto */


					bool isRelease = (buttonCode & 0b11) == 3;
					int buttonNumber;
					if(!isRelease) {
						buttonNumber = (buttonCode & 0b11);
						if(buttonCode & 64)
							buttonNumber += 3; // button 4 and 5 are sent as like button 1 and 2, but code | 64
							// so button 1 == button 4 here

						// note: buttonNumber == 0 means button 1 at this point
						buttonNumber++; // hence this


						// apparently this considers middle to be button 2. but i want middle to be button 3.
						if(buttonNumber == 2)
							buttonNumber = 3;
						else if(buttonNumber == 3)
							buttonNumber = 2;
					}

					auto modifiers = buttonCode & (0b0001_1100);
						// 4 == shift
						// 8 == meta
						// 16 == control

					MouseEvent m;

					if(buttonCode & 32)
						m.eventType = MouseEvent.Type.Moved;
					else
						m.eventType = isRelease ? MouseEvent.Type.Released : MouseEvent.Type.Pressed;

					// ugh, if no buttons are pressed, released and moved are indistinguishable...
					// so we'll count the buttons down, and if we get a release
					static int buttonsDown = 0;
					if(!isRelease && buttonNumber <= 3) // exclude wheel "presses"...
						buttonsDown++;

					if(isRelease && m.eventType != MouseEvent.Type.Moved) {
						if(buttonsDown)
							buttonsDown--;
						else // no buttons down, so this should be a motion instead..
							m.eventType = MouseEvent.Type.Moved;
					}


					if(buttonNumber == 0)
						m.buttons = 0; // we don't actually know :(
					else
						m.buttons = 1 << (buttonNumber - 1); // I prefer flags so that's how we do it
					m.x = x;
					m.y = y;
					m.modifierState = modifiers;

					return [InputEvent(m)];
				default:
					// look it up in the termcap key database
					auto cap = terminal.findSequenceInTermcap(sequence);
					if(cap !is null) {
						return translateTermcapName(cap);
					} else {
						if(terminal.terminalInFamily("xterm")) {
							import std.conv, std.string;
							auto terminator = sequence[$ - 1];
							auto parts = sequence[2 .. $ - 1].split(";");
							// parts[0] and terminator tells us the key
							// parts[1] tells us the modifierState

							uint modifierState;

							int modGot;
							if(parts.length > 1)
								modGot = to!int(parts[1]);
							mod_switch: switch(modGot) {
								case 2: modifierState |= ModifierState.shift; break;
								case 3: modifierState |= ModifierState.alt; break;
								case 4: modifierState |= ModifierState.shift | ModifierState.alt; break;
								case 5: modifierState |= ModifierState.control; break;
								case 6: modifierState |= ModifierState.shift | ModifierState.control; break;
								case 7: modifierState |= ModifierState.alt | ModifierState.control; break;
								case 8: modifierState |= ModifierState.shift | ModifierState.alt | ModifierState.control; break;
								case 9:
								..
								case 16:
									modifierState |= ModifierState.meta;
									if(modGot != 9) {
										modGot -= 8;
										goto mod_switch;
									}
								break;

								// this is an extension in my own terminal emulator
								case 20:
								..
								case 36:
									modifierState |= ModifierState.windows;
									modGot -= 20;
									goto mod_switch;
								default:
							}

							switch(terminator) {
								case 'A': return keyPressAndRelease(NonCharacterKeyEvent.Key.UpArrow, modifierState);
								case 'B': return keyPressAndRelease(NonCharacterKeyEvent.Key.DownArrow, modifierState);
								case 'C': return keyPressAndRelease(NonCharacterKeyEvent.Key.RightArrow, modifierState);
								case 'D': return keyPressAndRelease(NonCharacterKeyEvent.Key.LeftArrow, modifierState);

								case 'H': return keyPressAndRelease(NonCharacterKeyEvent.Key.Home, modifierState);
								case 'F': return keyPressAndRelease(NonCharacterKeyEvent.Key.End, modifierState);

								case 'P': return keyPressAndRelease(NonCharacterKeyEvent.Key.F1, modifierState);
								case 'Q': return keyPressAndRelease(NonCharacterKeyEvent.Key.F2, modifierState);
								case 'R': return keyPressAndRelease(NonCharacterKeyEvent.Key.F3, modifierState);
								case 'S': return keyPressAndRelease(NonCharacterKeyEvent.Key.F4, modifierState);

								case '~': // others
									switch(parts[0]) {
										case "5": return keyPressAndRelease(NonCharacterKeyEvent.Key.PageUp, modifierState);
										case "6": return keyPressAndRelease(NonCharacterKeyEvent.Key.PageDown, modifierState);
										case "2": return keyPressAndRelease(NonCharacterKeyEvent.Key.Insert, modifierState);
										case "3": return keyPressAndRelease(NonCharacterKeyEvent.Key.Delete, modifierState);

										case "15": return keyPressAndRelease(NonCharacterKeyEvent.Key.F5, modifierState);
										case "17": return keyPressAndRelease(NonCharacterKeyEvent.Key.F6, modifierState);
										case "18": return keyPressAndRelease(NonCharacterKeyEvent.Key.F7, modifierState);
										case "19": return keyPressAndRelease(NonCharacterKeyEvent.Key.F8, modifierState);
										case "20": return keyPressAndRelease(NonCharacterKeyEvent.Key.F9, modifierState);
										case "21": return keyPressAndRelease(NonCharacterKeyEvent.Key.F10, modifierState);
										case "23": return keyPressAndRelease(NonCharacterKeyEvent.Key.F11, modifierState);
										case "24": return keyPressAndRelease(NonCharacterKeyEvent.Key.F12, modifierState);
										default:
									}
								break;

								default:
							}
						} else if(terminal.terminalInFamily("rxvt")) {
							// FIXME: figure these out. rxvt seems to just change the terminator while keeping the rest the same
							// though it isn't consistent. ugh.
						} else {
							// maybe we could do more terminals, but linux doesn't even send it and screen just seems to pass through, so i don't think so; xterm prolly covers most them anyway
							// so this space is semi-intentionally left blank
						}
					}
			}

			return null;
		}

		auto c = nextRaw(true);
		if(c == -1)
			return null; // interrupted; give back nothing so the other level can recheck signal flags
		if(c == 0)
			throw new Exception("stdin has reached end of file");
		if(c == '\033') {
			if(timedCheckForInput(50)) {
				// escape sequence
				c = nextRaw();
				if(c == '[') { // CSI, ends on anything >= 'A'
					return doEscapeSequence(readEscapeSequence(sequenceBuffer));
				} else if(c == 'O') {
					// could be xterm function key
					auto n = nextRaw();

					char[3] thing;
					thing[0] = '\033';
					thing[1] = 'O';
					thing[2] = cast(char) n;

					auto cap = terminal.findSequenceInTermcap(thing);
					if(cap is null) {
						return charPressAndRelease('\033') ~
							charPressAndRelease('O') ~
							charPressAndRelease(thing[2]);
					} else {
						return translateTermcapName(cap);
					}
				} else {
					// I don't know, probably unsupported terminal or just quick user input or something
					return charPressAndRelease('\033') ~ charPressAndRelease(nextChar(c));
				}
			} else {
				// user hit escape (or super slow escape sequence, but meh)
				return keyPressAndRelease(NonCharacterKeyEvent.Key.escape);
			}
		} else {
			// FIXME: what if it is neither? we should check the termcap
			auto next = nextChar(c);
			if(next == 127) // some terminals send 127 on the backspace. Let's normalize that.
				next = '\b';
			return charPressAndRelease(next);
		}
	}
}

/// Input event for characters
struct CharacterEvent {
	/// .
	enum Type {
		Released, /// .
		Pressed /// .
	}

	Type eventType; /// .
	dchar character; /// .
	uint modifierState; /// Don't depend on this to be available for character events
}

struct NonCharacterKeyEvent {
	/// .
	enum Type {
		Released, /// .
		Pressed /// .
	}
	Type eventType; /// .

	// these match Windows virtual key codes numerically for simplicity of translation there
	//http://msdn.microsoft.com/en-us/library/windows/desktop/dd375731%28v=vs.85%29.aspx
	/// .
	enum Key : int {
		escape = 0x1b, /// .
		F1 = 0x70, /// .
		F2 = 0x71, /// .
		F3 = 0x72, /// .
		F4 = 0x73, /// .
		F5 = 0x74, /// .
		F6 = 0x75, /// .
		F7 = 0x76, /// .
		F8 = 0x77, /// .
		F9 = 0x78, /// .
		F10 = 0x79, /// .
		F11 = 0x7A, /// .
		F12 = 0x7B, /// .
		LeftArrow = 0x25, /// .
		RightArrow = 0x27, /// .
		UpArrow = 0x26, /// .
		DownArrow = 0x28, /// .
		Insert = 0x2d, /// .
		Delete = 0x2e, /// .
		Home = 0x24, /// .
		End = 0x23, /// .
		PageUp = 0x21, /// .
		PageDown = 0x22, /// .
		}
	Key key; /// .

	uint modifierState; /// A mask of ModifierState. Always use by checking modifierState & ModifierState.something, the actual value differs across platforms

}

/// .
struct PasteEvent {
	string pastedText; /// .
}

/// .
struct MouseEvent {
	// these match simpledisplay.d numerically as well
	/// .
	enum Type {
		Moved = 0, /// .
		Pressed = 1, /// .
		Released = 2, /// .
		Clicked, /// .
	}

	Type eventType; /// .

	// note: these should numerically match simpledisplay.d for maximum beauty in my other code
	/// .
	enum Button : uint {
		None = 0, /// .
		Left = 1, /// .
		Middle = 4, /// .
		Right = 2, /// .
		ScrollUp = 8, /// .
		ScrollDown = 16 /// .
	}
	uint buttons; /// A mask of Button
	int x; /// 0 == left side
	int y; /// 0 == top
	uint modifierState; /// shift, ctrl, alt, meta, altgr. Not always available. Always check by using modifierState & ModifierState.something
}

/// .
struct SizeChangedEvent {
	int oldWidth;
	int oldHeight;
	int newWidth;
	int newHeight;
}

/// the user hitting ctrl+c will send this
struct UserInterruptionEvent {}

interface CustomEvent {}

version(Windows)
enum ModifierState : uint {
	shift = 0x10,
	control = 0x8 | 0x4, // 8 == left ctrl, 4 == right ctrl

	// i'm not sure if the next two are available
	alt = 2 | 1, //2 ==left alt, 1 == right alt

	// FIXME: I don't think these are actually available
	windows = 512,
	meta = 4096, // FIXME sanity

	// I don't think this is available on Linux....
	scrollLock = 0x40,
}
else
enum ModifierState : uint {
	shift = 4,
	alt = 2,
	control = 16,
	meta = 8,

	windows = 512 // only available if you are using my terminal emulator; it isn't actually offered on standard linux ones
}

/// GetNextEvent returns this. Check the type, then use get to get the more detailed input
struct InputEvent {
	/// .
	enum Type {
		CharacterEvent, ///.
		NonCharacterKeyEvent, /// .
		PasteEvent, /// .
		MouseEvent, /// only sent if you subscribed to mouse events
		SizeChangedEvent, /// only sent if you subscribed to size events
		UserInterruptionEvent, /// the user hit ctrl+c
		CustomEvent /// .
	}

	/// .
	@property Type type() { return t; }

	/// .
	@property auto get(Type T)() {
		if(type != T)
			throw new Exception("Wrong event type");
		static if(T == Type.CharacterEvent)
			return characterEvent;
		else static if(T == Type.NonCharacterKeyEvent)
			return nonCharacterKeyEvent;
		else static if(T == Type.PasteEvent)
			return pasteEvent;
		else static if(T == Type.MouseEvent)
			return mouseEvent;
		else static if(T == Type.SizeChangedEvent)
			return sizeChangedEvent;
		else static if(T == Type.UserInterruptionEvent)
			return userInterruptionEvent;
		else static if(T == Type.CustomEvent)
			return customEvent;
		else static assert(0, "Type " ~ T.stringof ~ " not added to the get function");
	}

	private {
		this(CharacterEvent c) {
			t = Type.CharacterEvent;
			characterEvent = c;
		}
		this(NonCharacterKeyEvent c) {
			t = Type.NonCharacterKeyEvent;
			nonCharacterKeyEvent = c;
		}
		this(PasteEvent c) {
			t = Type.PasteEvent;
			pasteEvent = c;
		}
		this(MouseEvent c) {
			t = Type.MouseEvent;
			mouseEvent = c;
		}
		this(SizeChangedEvent c) {
			t = Type.SizeChangedEvent;
			sizeChangedEvent = c;
		}
		this(UserInterruptionEvent c) {
			t = Type.UserInterruptionEvent;
			userInterruptionEvent = c;
		}
		this(CustomEvent c) {
			t = Type.CustomEvent;
			customEvent = c;
		}

		Type t;

		union {
			CharacterEvent characterEvent;
			NonCharacterKeyEvent nonCharacterKeyEvent;
			PasteEvent pasteEvent;
			MouseEvent mouseEvent;
			SizeChangedEvent sizeChangedEvent;
			UserInterruptionEvent userInterruptionEvent;
			CustomEvent customEvent;
		}
	}
}

version(Demo)
void main() {
	auto terminal = Terminal(ConsoleOutputType.linear);

	terminal.setTitle("Basic I/O");
	auto input = RealTimeConsoleInput(&terminal, ConsoleInputFlags.raw | ConsoleInputFlags.allInputEvents);

	terminal.color(Color.green | Bright, Color.black);
	//terminal.color(Color.DEFAULT, Color.DEFAULT);

	terminal.write("test some long string to see if it wraps or what because i dont really know what it is going to do so i just want to test i think it will wrap but gotta be sure lolololololololol");
	terminal.writefln("%d %d", terminal.cursorX, terminal.cursorY);

	int centerX = terminal.width / 2;
	int centerY = terminal.height / 2;

	bool timeToBreak = false;

	void handleEvent(InputEvent event) {
		terminal.writef("%s\n", event.type);
		final switch(event.type) {
			case InputEvent.Type.UserInterruptionEvent:
				timeToBreak = true;
				version(with_eventloop) {
					import arsd.eventloop;
					exit();
				}
			break;
			case InputEvent.Type.SizeChangedEvent:
				auto ev = event.get!(InputEvent.Type.SizeChangedEvent);
				terminal.writeln(ev);
			break;
			case InputEvent.Type.CharacterEvent:
				auto ev = event.get!(InputEvent.Type.CharacterEvent);
				terminal.writef("\t%s\n", ev);
				if(ev.character == 'Q') {
					timeToBreak = true;
					version(with_eventloop) {
						import arsd.eventloop;
						exit();
					}
				}

				if(ev.character == 'C')
					terminal.clear();
			break;
			case InputEvent.Type.NonCharacterKeyEvent:
				terminal.writef("\t%s\n", event.get!(InputEvent.Type.NonCharacterKeyEvent));
			break;
			case InputEvent.Type.PasteEvent:
				terminal.writef("\t%s\n", event.get!(InputEvent.Type.PasteEvent));
			break;
			case InputEvent.Type.MouseEvent:
				terminal.writef("\t%s\n", event.get!(InputEvent.Type.MouseEvent));
			break;
			case InputEvent.Type.CustomEvent:
			break;
		}

		terminal.writefln("%d %d", terminal.cursorX, terminal.cursorY);

		/*
		if(input.kbhit()) {
			auto c = input.getch();
			if(c == 'q' || c == 'Q')
				break;
			terminal.moveTo(centerX, centerY);
			terminal.writef("%c", c);
			terminal.flush();
		}
		usleep(10000);
		*/
	}

	version(with_eventloop) {
		import arsd.eventloop;
		addListener(&handleEvent);
		loop();
	} else {
		loop: while(true) {
			auto event = input.nextEvent();
			handleEvent(event);
			if(timeToBreak)
				break loop;
		}
	}
}


/*

	// more efficient scrolling
	http://msdn.microsoft.com/en-us/library/windows/desktop/ms685113%28v=vs.85%29.aspx
	// and the unix sequences


	rxvt documentation:
	use this to finish the input magic for that


       For the keypad, use Shift to temporarily override Application-Keypad
       setting use Num_Lock to toggle Application-Keypad setting if Num_Lock
       is off, toggle Application-Keypad setting. Also note that values of
       Home, End, Delete may have been compiled differently on your system.

                         Normal       Shift         Control      Ctrl+Shift
       Tab               ^I           ESC [ Z       ^I           ESC [ Z
       BackSpace         ^H           ^?            ^?           ^?
       Find              ESC [ 1 ~    ESC [ 1 $     ESC [ 1 ^    ESC [ 1 @
       Insert            ESC [ 2 ~    paste         ESC [ 2 ^    ESC [ 2 @
       Execute           ESC [ 3 ~    ESC [ 3 $     ESC [ 3 ^    ESC [ 3 @
       Select            ESC [ 4 ~    ESC [ 4 $     ESC [ 4 ^    ESC [ 4 @
       Prior             ESC [ 5 ~    scroll-up     ESC [ 5 ^    ESC [ 5 @
       Next              ESC [ 6 ~    scroll-down   ESC [ 6 ^    ESC [ 6 @
       Home              ESC [ 7 ~    ESC [ 7 $     ESC [ 7 ^    ESC [ 7 @
       End               ESC [ 8 ~    ESC [ 8 $     ESC [ 8 ^    ESC [ 8 @
       Delete            ESC [ 3 ~    ESC [ 3 $     ESC [ 3 ^    ESC [ 3 @
       F1                ESC [ 11 ~   ESC [ 23 ~    ESC [ 11 ^   ESC [ 23 ^
       F2                ESC [ 12 ~   ESC [ 24 ~    ESC [ 12 ^   ESC [ 24 ^
       F3                ESC [ 13 ~   ESC [ 25 ~    ESC [ 13 ^   ESC [ 25 ^
       F4                ESC [ 14 ~   ESC [ 26 ~    ESC [ 14 ^   ESC [ 26 ^
       F5                ESC [ 15 ~   ESC [ 28 ~    ESC [ 15 ^   ESC [ 28 ^
       F6                ESC [ 17 ~   ESC [ 29 ~    ESC [ 17 ^   ESC [ 29 ^
       F7                ESC [ 18 ~   ESC [ 31 ~    ESC [ 18 ^   ESC [ 31 ^
       F8                ESC [ 19 ~   ESC [ 32 ~    ESC [ 19 ^   ESC [ 32 ^
       F9                ESC [ 20 ~   ESC [ 33 ~    ESC [ 20 ^   ESC [ 33 ^
       F10               ESC [ 21 ~   ESC [ 34 ~    ESC [ 21 ^   ESC [ 34 ^
       F11               ESC [ 23 ~   ESC [ 23 $    ESC [ 23 ^   ESC [ 23 @
       F12               ESC [ 24 ~   ESC [ 24 $    ESC [ 24 ^   ESC [ 24 @
       F13               ESC [ 25 ~   ESC [ 25 $    ESC [ 25 ^   ESC [ 25 @
       F14               ESC [ 26 ~   ESC [ 26 $    ESC [ 26 ^   ESC [ 26 @
       F15 (Help)        ESC [ 28 ~   ESC [ 28 $    ESC [ 28 ^   ESC [ 28 @
       F16 (Menu)        ESC [ 29 ~   ESC [ 29 $    ESC [ 29 ^   ESC [ 29 @

       F17               ESC [ 31 ~   ESC [ 31 $    ESC [ 31 ^   ESC [ 31 @
       F18               ESC [ 32 ~   ESC [ 32 $    ESC [ 32 ^   ESC [ 32 @
       F19               ESC [ 33 ~   ESC [ 33 $    ESC [ 33 ^   ESC [ 33 @
       F20               ESC [ 34 ~   ESC [ 34 $    ESC [ 34 ^   ESC [ 34 @
                                                                 Application
       Up                ESC [ A      ESC [ a       ESC O a      ESC O A
       Down              ESC [ B      ESC [ b       ESC O b      ESC O B
       Right             ESC [ C      ESC [ c       ESC O c      ESC O C
       Left              ESC [ D      ESC [ d       ESC O d      ESC O D
       KP_Enter          ^M                                      ESC O M
       KP_F1             ESC O P                                 ESC O P
       KP_F2             ESC O Q                                 ESC O Q
       KP_F3             ESC O R                                 ESC O R
       KP_F4             ESC O S                                 ESC O S
       XK_KP_Multiply    *                                       ESC O j
       XK_KP_Add         +                                       ESC O k
       XK_KP_Separator   ,                                       ESC O l
       XK_KP_Subtract    -                                       ESC O m
       XK_KP_Decimal     .                                       ESC O n
       XK_KP_Divide      /                                       ESC O o
       XK_KP_0           0                                       ESC O p
       XK_KP_1           1                                       ESC O q
       XK_KP_2           2                                       ESC O r
       XK_KP_3           3                                       ESC O s
       XK_KP_4           4                                       ESC O t
       XK_KP_5           5                                       ESC O u
       XK_KP_6           6                                       ESC O v
       XK_KP_7           7                                       ESC O w
       XK_KP_8           8                                       ESC O x
       XK_KP_9           9                                       ESC O y
*/
