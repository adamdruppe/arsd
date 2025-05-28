// for optional dependency
// for VT on Windows P s = 1 8 → Report the size of the text area in characters as CSI 8 ; height ; width t
// could be used to have the TE volunteer the size

// FIXME: have some flags or formal api to set color to vtsequences even on pipe etc on demand.


// FIXME: the resume signal needs to be handled to set the terminal back in proper mode.

/++
	Module for interacting with the user's terminal, including color output, cursor manipulation, and full-featured real-time mouse and keyboard input. Also includes high-level convenience methods, like [Terminal.getline], which gives the user a line editor with history, completion, etc. See the [#examples].


	The main interface for this module is the Terminal struct, which
	encapsulates the output functions and line-buffered input of the terminal, and
	RealTimeConsoleInput, which gives real time input.

	Creating an instance of these structs will perform console initialization. When the struct
	goes out of scope, any changes in console settings will be automatically reverted and pending
	output is flushed. Do not create a global Terminal, as this will skip the destructor. Also do
	not create an instance inside a class or array, as again the destructor will be nondeterministic.
	You should create the object as a local inside main (or wherever else will encapsulate its whole
	usage lifetime), then pass borrowed pointers to it if needed somewhere else. This ensures the
	construction and destruction is run in a timely manner.

	$(PITFALL
		Output is NOT flushed on \n! Output is buffered until:

		$(LIST
			* Terminal's destructor is run
			* You request input from the terminal object
			* You call `terminal.flush()`
		)

		If you want to see output immediately, always call `terminal.flush()`
		after writing.
	)

	Note: on Posix, it traps SIGINT and translates it into an input event. You should
	keep your event loop moving and keep an eye open for this to exit cleanly; simply break
	your event loop upon receiving a UserInterruptionEvent. (Without
	the signal handler, ctrl+c can leave your terminal in a bizarre state.)

	As a user, if you have to forcibly kill your program and the event doesn't work, there's still ctrl+\

	On old Mac Terminal btw, a lot of hacks are needed and mouse support doesn't work on older versions.
	Most functions work now with newer Mac OS versions though.

	Future_Roadmap:
	$(LIST
		* The CharacterEvent and NonCharacterKeyEvent types will be removed. Instead, use KeyboardEvent
		  on new programs.

		* The ScrollbackBuffer will be expanded to be easier to use to partition your screen. It might even
		  handle input events of some sort. Its API may change.

		* getline I want to be really easy to use both for code and end users. It will need multi-line support
		  eventually.

		* I might add an expandable event loop and base level widget classes. This may be Linux-specific in places and may overlap with similar functionality in simpledisplay.d. If I can pull it off without a third module, I want them to be compatible with each other too so the two modules can be combined easily. (Currently, they are both compatible with my eventloop.d and can be easily combined through it, but that is a third module.)

		* More advanced terminal features as functions, where available, like cursor changing and full-color functions.

		* More documentation.
	)

	WHAT I WON'T DO:
	$(LIST
		* support everything under the sun. If it isn't default-installed on an OS I or significant number of other people
		  might actually use, and isn't written by me, I don't really care about it. This means the only supported terminals are:
		  $(LIST

		  * xterm (and decently xterm compatible emulators like Konsole)
		  * Windows console
		  * rxvt (to a lesser extent)
		  * Linux console
		  * My terminal emulator family of applications https://github.com/adamdruppe/terminal-emulator
		  )

		  Anything else is cool if it does work, but I don't want to go out of my way for it.

		* Use other libraries, unless strictly optional. terminal.d is a stand-alone module by default and
		  always will be.

		* Do a full TUI widget set. I might do some basics and lay a little groundwork, but a full TUI
		  is outside the scope of this module (unless I can do it really small.)
	)

	History:
		On December 29, 2020 the structs and their destructors got more protection against in-GC finalization errors and duplicate executions.

		This should not affect your code.
+/
module arsd.terminal;

// FIXME: needs to support VT output on Windows too in certain situations
// detect VT on windows by trying to set the flag. if this succeeds, ask it for caps. if this replies with my code we good to do extended output.

/++
	$(H3 Get Line)

	This example will demonstrate the high-level [Terminal.getline] interface.

	The user will be able to type a line and navigate around it with cursor keys and even the mouse on some systems, as well as perform editing as they expect (e.g. the backspace and delete keys work normally) until they press enter.  Then, the final line will be returned to your program, which the example will simply print back to the user.
+/
unittest {
	import arsd.terminal;

	void main() {
		auto terminal = Terminal(ConsoleOutputType.linear);
		string line = terminal.getline();
		terminal.writeln("You wrote: ", line);

		// new on October 11, 2021: you can change the echo char
		// for password masking now. Also pass `0` there to get unix-style
		// total silence.
		string pwd = terminal.getline("Password: ", '*');
		terminal.writeln("Your password is: ", pwd);
	}

	version(demos) main; // exclude from docs
}

/++
	$(H3 Color)

	This example demonstrates color output, using [Terminal.color]
	and the output functions like [Terminal.writeln].
+/
unittest {
	import arsd.terminal;

	void main() {
		auto terminal = Terminal(ConsoleOutputType.linear);
		terminal.color(Color.green, Color.black);
		terminal.writeln("Hello world, in green on black!");
		terminal.color(Color.DEFAULT, Color.DEFAULT);
		terminal.writeln("And back to normal.");
	}

	version(demos) main; // exclude from docs
}

/++
	$(H3 Single Key)

	This shows how to get one single character press using
	the [RealTimeConsoleInput] structure. The return value
	is normally a character, but can also be a member of
	[KeyboardEvent.Key] for certain keys on the keyboard such
	as arrow keys.

	For more advanced cases, you might consider looping on
	[RealTimeConsoleInput.nextEvent] which gives you full events
	including paste events, mouse activity, resizes, and more.

	See_Also: [KeyboardEvent], [KeyboardEvent.Key], [kbhit]
+/
unittest {
	import arsd.terminal;

	void main() {
		auto terminal = Terminal(ConsoleOutputType.linear);
		auto input = RealTimeConsoleInput(&terminal, ConsoleInputFlags.raw);

		terminal.writeln("Press any key to continue...");
		auto ch = input.getch();
		terminal.writeln("You pressed ", ch);
	}

	version(demos) main; // exclude from docs
}

/// ditto
unittest {
	import arsd.terminal;

	void main() {
		auto terminal = Terminal(ConsoleOutputType.linear);
		auto rtti = RealTimeConsoleInput(&terminal, ConsoleInputFlags.raw);
		loop: while(true) {
			switch(rtti.getch()) {
				case 'q': // other characters work as chars in the switch
					break loop;
				case KeyboardEvent.Key.F1: // also f-keys via that enum
					terminal.writeln("You pressed F1!");
				break;
				case KeyboardEvent.Key.LeftArrow: // arrow keys, etc.
					terminal.writeln("left");
				break;
				case KeyboardEvent.Key.RightArrow:
					terminal.writeln("right");
				break;
				default: {}
			}
		}
	}

	version(demos) main; // exclude from docs
}

/++
	$(H3 Full screen)

	This shows how to use the cellular (full screen) mode and pass terminal to functions.
+/
unittest {
	import arsd.terminal;

	// passing terminals must be done by ref or by pointer
	void helper(Terminal* terminal) {
		terminal.moveTo(0, 1);
		terminal.getline("Press enter to exit...");
	}

	void main() {
		// ask for cellular mode, it will go full screen
		auto terminal = Terminal(ConsoleOutputType.cellular);

		// it is automatically cleared upon entry
		terminal.write("Hello upper left corner");

		// pass it by pointer to other functions
		helper(&terminal);

		// since at the end of main, Terminal's destructor
		// resets the terminal to how it was before for the
		// user
	}
}

/*
	Widgets:
		tab widget
		scrollback buffer
		partitioned canvas
*/

// FIXME: ctrl+d eof on stdin

// FIXME: http://msdn.microsoft.com/en-us/library/windows/desktop/ms686016%28v=vs.85%29.aspx


/++
	A function the sigint handler will call (if overridden - which is the
	case when [RealTimeConsoleInput] is active on Posix or if you compile with
	`TerminalDirectToEmulator` version on any platform at this time) in addition
	to the library's default handling, which is to set a flag for the event loop
	to inform you.

	Remember, this is called from a signal handler and/or from a separate thread,
	so you are not allowed to do much with it and need care when setting TLS variables.

	I suggest you only set a `__gshared bool` flag as many other operations will risk
	undefined behavior.

	$(WARNING
		This function is never called on the default Windows console
		configuration in the current implementation. You can use
		`-version=TerminalDirectToEmulator` to guarantee it is called there
		too by causing the library to pop up a gui window for your application.
	)

	History:
		Added March 30, 2020. Included in release v7.1.0.

+/
__gshared void delegate() nothrow @nogc sigIntExtension;

static import arsd.core;

import core.stdc.stdio;

version(TerminalDirectToEmulator) {
	version=WithEncapsulatedSignals;
	private __gshared bool windowGone = false;
	private bool forceTerminationTried = false;
	private void forceTermination() {
		if(forceTerminationTried) {
			// why are we still here?! someone must be catching the exception and calling back.
			// there's no recovery so time to kill this program.
			import core.stdc.stdlib;
			abort();
		} else {
			// give them a chance to cleanly exit...
			forceTerminationTried = true;
			throw new HangupException();
		}
	}
}

version(Posix) {
	enum SIGWINCH = 28;
	__gshared bool windowSizeChanged = false;
	__gshared bool interrupted = false; /// you might periodically check this in a long operation and abort if it is set. Remember it is volatile. It is also sent through the input event loop via RealTimeConsoleInput
	__gshared bool hangedUp = false; /// similar to interrupted.
	__gshared bool continuedFromSuspend = false; /// SIGCONT was just received, the terminal state may have changed. Added Feb 18, 2021.
	version=WithSignals;

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

		if(sigIntExtension)
			sigIntExtension();
	}
	extern(C)
	void hangupSignalHandler(int sigNumber) nothrow {
		hangedUp = true;
		version(with_eventloop) {
			import arsd.eventloop;
			try
				send(SignalFired());
			catch(Exception) {}
		}
	}
	extern(C)
	void continueSignalHandler(int sigNumber) nothrow {
		continuedFromSuspend = true;
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

version(TerminalDirectToEmulator) {
	version=VtEscapeCodes;
	version(Windows)
		version=Win32Console;
} else version(Windows) {
	version(VtEscapeCodes) {} // cool
	version=Win32Console;
}

version(Windows)
{
	import core.sys.windows.wincon;
	import core.sys.windows.winnt;
	import core.sys.windows.winbase;
	import core.sys.windows.winuser;
}

version(Win32Console) {
	__gshared bool UseWin32Console = true;

	pragma(lib, "user32");
}

version(Posix) {

	version=VtEscapeCodes;

	import core.sys.posix.termios;
	import core.sys.posix.unistd;
	import unix = core.sys.posix.unistd;
	import core.sys.posix.sys.types;
	import core.sys.posix.sys.time;
	import core.stdc.stdio;

	import core.sys.posix.sys.ioctl;
}
version(CRuntime_Musl) {
	// Druntime currently doesn't have bindings for termios on Musl.
	// We define our own bindings whenever the import fails.
	// When druntime catches up, this block can slowly be removed,
	// although for backward compatibility we might want to keep it.
	static if (!__traits(compiles, { import core.sys.posix.termios : tcgetattr; })) {
		extern (C) {
			int tcgetattr (int, termios *);
			int tcsetattr (int, int, const termios *);
		}
	}
}

version(VtEscapeCodes) {

	__gshared bool UseVtSequences = true;

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
vs|xterm|tmux|tmux-256color|xterm-kitty|screen|screen.xterm|screen-256color|screen.xterm-256color|xterm-color|xterm-256color|vs100|xterm terminal emulator (X Window System):\
	:am:bs:mi@:km:co#80:li#55:\
	:im@:ei@:\
	:cl=\E[H\E[J:\
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
rxvt|rxvt-unicode|rxvt-unicode-256color:\
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
        :ac=aaffggiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~:

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
} else {
	enum UseVtSequences = false;
}

/// A modifier for [Color]
enum Bright = 0x08;

/// Defines the list of standard colors understood by Terminal.
/// See also: [Bright]
enum Color : ushort {
	black = 0, /// .
	red = 1, /// .
	green = 2, /// .
	yellow = red | green, /// .
	blue = 4, /// .
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
/// The rationale for that is to ensure the Terminal destructor has a chance to run, since the terminal is a shared resource and should be put back before the program terminates.
enum ConsoleInputFlags {
	raw = 0, /// raw input returns keystrokes immediately, without line buffering
	echo = 1, /// do you want to automatically echo input back to the user?
	mouse = 2, /// capture mouse events
	paste = 4, /// capture paste events (note: without this, paste can come through as keystrokes)
	size = 8, /// window resize events

	releasedKeys = 64, /// key release events. Not reliable on Posix.

	allInputEvents = 8|4|2, /// subscribe to all input events. Note: in previous versions, this also returned release events. It no longer does, use allInputEventsWithRelease if you want them.
	allInputEventsWithRelease = allInputEvents|releasedKeys, /// subscribe to all input events, including (unreliable on Posix) key release events.

	noEolWrap = 128,
	selectiveMouse = 256, /// Uses arsd terminal emulator's proprietary extension to select mouse input only for special cases, intended to enhance getline while keeping default terminal mouse behavior in other places. If it is set, it overrides [mouse] event flag. If not using the arsd terminal emulator, this will disable application mouse input.
}

/// Defines how terminal output should be handled.
enum ConsoleOutputType {
	linear = 0, /// do you want output to work one line at a time?
	cellular = 1, /// or do you want access to the terminal screen as a grid of characters?
	//truncatedCellular = 3, /// cellular, but instead of wrapping output to the next line automatically, it will truncate at the edges

	minimalProcessing = 255, /// do the least possible work, skips most construction and destruction tasks, does not query terminal in any way in favor of making assumptions about it. Only use if you know what you're doing here
}

alias ConsoleOutputMode = ConsoleOutputType;

/// Some methods will try not to send unnecessary commands to the screen. You can override their judgement using a ForceOption parameter, if present
enum ForceOption {
	automatic = 0, /// automatically decide what to do (best, unless you know for sure it isn't right)
	neverSend = -1, /// never send the data. This will only update Terminal's internal state. Use with caution.
	alwaysSend = 1, /// always send the data, even if it doesn't seem necessary
}

///
enum TerminalCursor {
	DEFAULT = 0, ///
	insert = 1, ///
	block = 2 ///
}

// we could do it with termcap too, getenv("TERMCAP") then split on : and replace \E with \033 and get the pieces

/// Encapsulates the I/O capabilities of a terminal.
///
/// Warning: do not write out escape sequences to the terminal. This won't work
/// on Windows and will confuse Terminal's internal state on Posix.
struct Terminal {
	///
	@disable this();
	@disable this(this);
	private ConsoleOutputType type;

	version(TerminalDirectToEmulator) {
		private bool windowSizeChanged = false;
		private bool interrupted = false; /// you might periodically check this in a long operation and abort if it is set. Remember it is volatile. It is also sent through the input event loop via RealTimeConsoleInput
		private bool hangedUp = false; /// similar to interrupted.
	}

	private TerminalCursor currentCursor_;
	version(Windows) private CONSOLE_CURSOR_INFO originalCursorInfo;

	/++
		Changes the current cursor.
	+/
	void cursor(TerminalCursor what, ForceOption force = ForceOption.automatic) {
		if(force == ForceOption.neverSend) {
			currentCursor_ = what;
			return;
		} else {
			if(what != currentCursor_ || force == ForceOption.alwaysSend) {
				currentCursor_ = what;
				if(UseVtSequences) {
					final switch(what) {
						case TerminalCursor.DEFAULT:
							if(terminalInFamily("linux"))
								writeStringRaw("\033[?0c");
							else
								writeStringRaw("\033[2 q"); // assuming non-blinking block are the desired default
						break;
						case TerminalCursor.insert:
							if(terminalInFamily("linux"))
								writeStringRaw("\033[?2c");
							else if(terminalInFamily("xterm"))
								writeStringRaw("\033[6 q");
							else
								writeStringRaw("\033[4 q");
						break;
						case TerminalCursor.block:
							if(terminalInFamily("linux"))
								writeStringRaw("\033[?6c");
							else
								writeStringRaw("\033[2 q");
						break;
					}
				} else version(Win32Console) if(UseWin32Console) {
					final switch(what) {
						case TerminalCursor.DEFAULT:
							SetConsoleCursorInfo(hConsole, &originalCursorInfo);
						break;
						case TerminalCursor.insert:
						case TerminalCursor.block:
							CONSOLE_CURSOR_INFO info;
							GetConsoleCursorInfo(hConsole, &info);
							info.dwSize = what == TerminalCursor.insert ? 1 : 100;
							SetConsoleCursorInfo(hConsole, &info);
						break;
					}
				}
			}
		}
	}

	/++
		Terminal is only valid to use on an actual console device or terminal
		handle. You should not attempt to construct a Terminal instance if this
		returns false. Real time input is similarly impossible if `!stdinIsTerminal`.
	+/
	static bool stdoutIsTerminal() {
		version(TerminalDirectToEmulator) {
			version(Windows) {
				// if it is null, it was a gui subsystem exe. But otherwise, it
				// might be explicitly redirected and we should respect that for
				// compatibility with normal console expectations (even though like
				// we COULD pop up a gui and do both, really that isn't the normal
				// use of this library so don't wanna go too nuts)
				auto hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
				return hConsole is null || GetFileType(hConsole) == FILE_TYPE_CHAR;
			} else version(Posix) {
				// same as normal here since thee is no gui subsystem really
				import core.sys.posix.unistd;
				return cast(bool) isatty(1);
			} else static assert(0);
		} else version(Posix) {
			import core.sys.posix.unistd;
			return cast(bool) isatty(1);
		} else version(Win32Console) {
			auto hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
			return GetFileType(hConsole) == FILE_TYPE_CHAR;
			/+
			auto hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
			CONSOLE_SCREEN_BUFFER_INFO originalSbi;
			if(GetConsoleScreenBufferInfo(hConsole, &originalSbi) == 0)
				return false;
			else
				return true;
			+/
		} else static assert(0);
	}

	///
	static bool stdinIsTerminal() {
		version(TerminalDirectToEmulator) {
			version(Windows) {
				auto hConsole = GetStdHandle(STD_INPUT_HANDLE);
				return hConsole is null || GetFileType(hConsole) == FILE_TYPE_CHAR;
			} else version(Posix) {
				// same as normal here since thee is no gui subsystem really
				import core.sys.posix.unistd;
				return cast(bool) isatty(0);
			} else static assert(0);
		} else version(Posix) {
			import core.sys.posix.unistd;
			return cast(bool) isatty(0);
		} else version(Win32Console) {
			auto hConsole = GetStdHandle(STD_INPUT_HANDLE);
			return GetFileType(hConsole) == FILE_TYPE_CHAR;
		} else static assert(0);
	}

	version(Posix) {
		private int fdOut;
		private int fdIn;
		void delegate(in void[]) _writeDelegate; // used to override the unix write() system call, set it magically
	}
	private int[] delegate() getSizeOverride;

	bool terminalInFamily(string[] terms...) {
		version(Win32Console) if(UseWin32Console)
			return false;

		// we're not writing to a terminal at all!
		if(!usingDirectEmulator && type != ConsoleOutputType.minimalProcessing)
		if(!stdoutIsTerminal || !stdinIsTerminal)
			return false;

		import std.process;
		import std.string;
		version(TerminalDirectToEmulator)
			auto term = "xterm";
		else
			auto term = type == ConsoleOutputType.minimalProcessing ? "xterm" : environment.get("TERM");

		foreach(t; terms)
			if(indexOf(term, t) != -1)
				return true;

		return false;
	}

	version(Posix) {
		// This is a filthy hack because Terminal.app and OS X are garbage who don't
		// work the way they're advertised. I just have to best-guess hack and hope it
		// doesn't break anything else. (If you know a better way, let me know!)
		bool isMacTerminal() {
			// it gives 1,2 in getTerminalCapabilities and sets term...
			import std.process;
			import std.string;
			auto term = environment.get("TERM");
			return term == "xterm-256color" && tcaps == TerminalCapabilities.vt100;
		}
	} else
		bool isMacTerminal() { return false; }

	static string[string] termcapDatabase;
	static void readTermcapFile(bool useBuiltinTermcap = false) {
		import std.file;
		import std.stdio;
		import std.string;

		//if(!exists("/etc/termcap"))
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
			version(VtEscapeCodes)
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
	void readTermcap(string t = null) {
		version(TerminalDirectToEmulator)
		if(usingDirectEmulator)
			t = "xterm";
		import std.process;
		import std.string;
		import std.array;

		string termcapData = environment.get("TERMCAP");
		if(termcapData.length == 0) {
			if(t is null) {
				t = environment.get("TERM");
			}

			// loosen the check so any xterm variety gets
			// the same termcap. odds are this is right
			// almost always
			if(t.indexOf("xterm") != -1)
				t = "xterm";
			else if(t.indexOf("putty") != -1)
				t = "xterm";
			else if(t.indexOf("tmux") != -1)
				t = "tmux";
			else if(t.indexOf("screen") != -1)
				t = "screen";

			termcapData = getTermcapDatabase(t);
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
		if(!usingDirectEmulator && type != ConsoleOutputType.minimalProcessing && !stdoutIsTerminal)
			return false;

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

	private uint _tcaps;
	private bool tcapsRequested;

	uint tcaps() const {
		if(type != ConsoleOutputType.minimalProcessing)
		if(!tcapsRequested) {
			Terminal* mutable = cast(Terminal*) &this;
			version(Posix)
				mutable._tcaps = getTerminalCapabilities(fdIn, fdOut);
			else
				{} // FIXME do something for windows too...
			mutable.tcapsRequested = true;
		}

		return _tcaps;

	}

	bool inlineImagesSupported() const {
		return (tcaps & TerminalCapabilities.arsdImage) ? true : false;
	}
	bool clipboardSupported() const {
		version(Win32Console) return true;
		else return (tcaps & TerminalCapabilities.arsdClipboard) ? true : false;
	}

	version (Win32Console)
		// Mimic sc & rc termcaps on Windows
		COORD[] cursorPositionStack;

	/++
		Saves/restores cursor position to a stack.

		History:
			Added August 6, 2022 (dub v10.9)
	+/
	bool saveCursorPosition()
	{
		if(UseVtSequences)
			return doTermcap("sc");
		else version (Win32Console) if(UseWin32Console)
		{
			flush();
			CONSOLE_SCREEN_BUFFER_INFO info;
			if (GetConsoleScreenBufferInfo(hConsole, &info))
			{
				cursorPositionStack ~= info.dwCursorPosition; // push
				return true;
			}
			else
			{
				return false;
			}
		}
		assert(0);
	}

	/// ditto
	bool restoreCursorPosition()
	{
		if(UseVtSequences)
			// FIXME: needs to update cursorX and cursorY
			return doTermcap("rc");
		else version (Win32Console) if(UseWin32Console)
		{
			if (cursorPositionStack.length > 0)
			{
				auto p = cursorPositionStack[$ - 1];
				moveTo(p.X, p.Y);
				cursorPositionStack = cursorPositionStack[0 .. $ - 1]; // pop
				return true;
			}
			else
				return false;
		}
		assert(0);
	}

	// only supported on my custom terminal emulator. guarded behind if(inlineImagesSupported)
	// though that isn't even 100% accurate but meh
	void changeWindowIcon()(string filename) {
		if(inlineImagesSupported()) {
		        import arsd.png;
			auto image = readPng(filename);
			auto ii = cast(IndexedImage) image;
			assert(ii !is null);

			// copy/pasted from my terminalemulator.d
			string encodeSmallTextImage(IndexedImage ii) {
				char encodeNumeric(int c) {
					if(c < 10)
						return cast(char)(c + '0');
					if(c < 10 + 26)
						return cast(char)(c - 10 + 'a');
					assert(0);
				}

				string s;
				s ~= encodeNumeric(ii.width);
				s ~= encodeNumeric(ii.height);

				foreach(entry; ii.palette)
					s ~= entry.toRgbaHexString();
				s ~= "Z";

				ubyte rleByte;
				int rleCount;

				void rleCommit() {
					if(rleByte >= 26)
						assert(0); // too many colors for us to handle
					if(rleCount == 0)
						goto finish;
					if(rleCount == 1) {
						s ~= rleByte + 'a';
						goto finish;
					}

					import std.conv;
					s ~= to!string(rleCount);
					s ~= rleByte + 'a';

					finish:
						rleByte = 0;
						rleCount = 0;
				}

				foreach(b; ii.data) {
					if(b == rleByte)
						rleCount++;
					else {
						rleCommit();
						rleByte = b;
						rleCount = 1;
					}
				}

				rleCommit();

				return s;
			}

			this.writeStringRaw("\033]5000;"~encodeSmallTextImage(ii)~"\007");
		}
	}

	// dependent on tcaps...
	void displayInlineImage()(in ubyte[] imageData) {
		if(inlineImagesSupported) {
			import std.base64;

			// I might change this protocol later!
			enum extensionMagicIdentifier = "ARSD Terminal Emulator binary extension data follows:";

			this.writeStringRaw("\000");
			this.writeStringRaw(extensionMagicIdentifier);
			this.writeStringRaw(Base64.encode(imageData));
			this.writeStringRaw("\000");
		}
	}

	void demandUserAttention() {
		if(UseVtSequences) {
			if(!terminalInFamily("linux"))
				writeStringRaw("\033]5001;1\007");
		}
	}

	void requestCopyToClipboard(in char[] text) {
		if(clipboardSupported) {
			import std.base64;
			writeStringRaw("\033]52;c;"~Base64.encode(cast(ubyte[])text)~"\007");
		}
	}

	void requestCopyToPrimary(in char[] text) {
		if(clipboardSupported) {
			import std.base64;
			writeStringRaw("\033]52;p;"~Base64.encode(cast(ubyte[])text)~"\007");
		}
	}

	// it sets the internal selection, you are still responsible for showing to users if need be
	// may not work though, check `clipboardSupported` or have some alternate way for the user to use the selection
	void requestSetTerminalSelection(string text) {
		if(clipboardSupported) {
			import std.base64;
			writeStringRaw("\033]52;s;"~Base64.encode(cast(ubyte[])text)~"\007");
		}
	}


	bool hasDefaultDarkBackground() {
		version(Win32Console) {
			return !(defaultBackgroundColor & 0xf);
		} else {
			version(TerminalDirectToEmulator)
			if(usingDirectEmulator)
				return integratedTerminalEmulatorConfiguration.defaultBackground.g < 100;
			// FIXME: there is probably a better way to do this
			// but like idk how reliable it is.
			if(terminalInFamily("linux"))
				return true;
			else
				return false;
		}
	}

	version(TerminalDirectToEmulator) {
		TerminalEmulatorWidget tew;
		private __gshared Window mainWindow;
		import core.thread;
		version(Posix)
			ThreadID threadId;
		else version(Windows)
			HANDLE threadId;
		private __gshared Thread guiThread;

		private static class NewTerminalEvent {
			Terminal* t;
			this(Terminal* t) {
				this.t = t;
			}
		}

	}
	bool usingDirectEmulator;

	version(TerminalDirectToEmulator)
	/++
		When using the embedded terminal emulator build, closing the terminal signals that the main thread should exit
		by sending it a hang up event. If the main thread responds, no problem. But if it doesn't, it can keep a thing
		running in the background with no visible window. This timeout gives it a chance to exit cleanly, but if it
		doesn't by the end of the time, the program will be forcibly closed automatically.

		History:
			Added March 14, 2023 (dub v10.10)
	+/
	static __gshared int terminateTimeoutMsecs = 3500;

	version(TerminalDirectToEmulator)
	/++
	+/
	this(ConsoleOutputType type) {
		_initialized = true;
		this.type = type;

		if(type == ConsoleOutputType.minimalProcessing) {
			readTermcap("xterm");
			_suppressDestruction = true;
			return;
		}

		import arsd.simpledisplay;
		static if(UsingSimpledisplayX11) {
			if(!integratedTerminalEmulatorConfiguration.preferDegradedTerminal)
			try {
				if(arsd.simpledisplay.librariesSuccessfullyLoaded) {
					XDisplayConnection.get();
					this.usingDirectEmulator = true;
				} else if(!integratedTerminalEmulatorConfiguration.fallbackToDegradedTerminal) {
					throw new Exception("Unable to load X libraries to create custom terminal.");
				}
			} catch(Exception e) {
				if(!integratedTerminalEmulatorConfiguration.fallbackToDegradedTerminal)
					throw e;
			}
		} else {
			usingDirectEmulator = true;
		}

		if(integratedTerminalEmulatorConfiguration.preferDegradedTerminal)
			this.usingDirectEmulator = false;

		// FIXME is this really correct logic?
		if(!stdinIsTerminal || !stdoutIsTerminal)
			this.usingDirectEmulator = false;

		if(usingDirectEmulator) {
			version(Win32Console)
				UseWin32Console = false;
			UseVtSequences = true;
		} else {
			version(Posix) {
				posixInitialize(type, 0, 1, null);
				return;
			} else version(Win32Console) {
				UseVtSequences = false;
				UseWin32Console = true; // this might be set back to false by windowsInitialize but that's ok
				windowsInitialize(type);
				return;
			}
			assert(0);
		}

		_tcaps = uint.max; // all capabilities
		tcapsRequested = true;
		import core.thread;

		version(Posix)
			threadId = Thread.getThis.id;
		else version(Windows)
			threadId = GetCurrentThread();

		if(guiThread is null) {
			guiThread = new Thread( {
				try {
					auto window = new TerminalEmulatorWindow(&this, null);
					mainWindow = window;
					mainWindow.win.addEventListener((NewTerminalEvent t) {
						auto nw = new TerminalEmulatorWindow(t.t, null);
						t.t.tew = nw.tew;
						t.t = null;
						nw.show();
					});
					tew = window.tew;
					window.loop();

					// if the other thread doesn't terminate in a reasonable amount of time
					// after the window closes, we're gonna terminate it by force to avoid
					// leaving behind a background process with no obvious ui
					if(Terminal.terminateTimeoutMsecs >= 0) {
						auto murderThread = new Thread(() {
							Thread.sleep(terminateTimeoutMsecs.msecs);
							terminateTerminalProcess(threadId);
						});
						murderThread.isDaemon = true;
						murderThread.start();
					}
				} catch(Throwable t) {
					guiAbortProcess(t.toString());
				}
			});
			guiThread.start();
			guiThread.priority = Thread.PRIORITY_MAX; // gui thread needs responsiveness
		} else {
			// FIXME: 64 bit builds on linux segfault with multiple terminals
			// so that isn't really supported as of yet.
			while(cast(shared) mainWindow is null) {
				import core.thread;
				Thread.sleep(5.msecs);
			}
			mainWindow.win.postEvent(new NewTerminalEvent(&this));
		}

		// need to wait until it is properly initialized
		while(cast(shared) tew is null) {
			import core.thread;
			Thread.sleep(5.msecs);
		}

		initializeVt();

	}
	else

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
		_initialized = true;
		posixInitialize(type, fdIn, fdOut, getSizeOverride);
	} else version(Win32Console)
	this(ConsoleOutputType type) {
		windowsInitialize(type);
	}

	version(Win32Console)
	void windowsInitialize(ConsoleOutputType type) {
		_initialized = true;
		if(UseVtSequences) {
			hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
			initializeVt();
		} else {
			if(type == ConsoleOutputType.cellular) {
				goCellular();
			} else {
				hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
			}

			if(GetConsoleScreenBufferInfo(hConsole, &originalSbi) != 0) {
				defaultForegroundColor = win32ConsoleColorToArsdTerminalColor(originalSbi.wAttributes & 0x0f);
				defaultBackgroundColor = win32ConsoleColorToArsdTerminalColor((originalSbi.wAttributes >> 4) & 0x0f);
			} else {
				// throw new Exception("not a user-interactive terminal");
				UseWin32Console = false;
			}

			// this is unnecessary since I use the W versions of other functions
			// and can cause weird font bugs, so I'm commenting unless some other
			// need comes up.
			/*
			oldCp = GetConsoleOutputCP();
			SetConsoleOutputCP(65001); // UTF-8

			oldCpIn = GetConsoleCP();
			SetConsoleCP(65001); // UTF-8
			*/
		}
	}


	version(Posix)
	private void posixInitialize(ConsoleOutputType type, int fdIn = 0, int fdOut = 1, int[] delegate() getSizeOverride = null) {
		this.fdIn = fdIn;
		this.fdOut = fdOut;
		this.getSizeOverride = getSizeOverride;
		this.type = type;

		if(type == ConsoleOutputType.minimalProcessing) {
			readTermcap("xterm");
			_suppressDestruction = true;
			return;
		}

		initializeVt();
	}

	void initializeVt() {
		readTermcap();

		if(type == ConsoleOutputType.cellular) {
			goCellular();
		}

		if(type != ConsoleOutputType.minimalProcessing)
		if(terminalInFamily("xterm", "rxvt", "screen", "tmux")) {
			writeStringRaw("\033[22;0t"); // save window title on a stack (support seems spotty, but it doesn't hurt to have it)
		}

	}

	private void goCellular() {
		if(!usingDirectEmulator && !Terminal.stdoutIsTerminal && type != ConsoleOutputType.minimalProcessing)
			throw new Exception("Cannot go to cellular mode with redirected output");

		if(UseVtSequences) {
			doTermcap("ti");
			clear();
			moveTo(0, 0, ForceOption.alwaysSend); // we need to know where the cursor is for some features to work, and moving it is easier than querying it
		} else version(Win32Console) if(UseWin32Console) {
			hConsole = CreateConsoleScreenBuffer(GENERIC_READ | GENERIC_WRITE, 0, null, CONSOLE_TEXTMODE_BUFFER, null);
			if(hConsole == INVALID_HANDLE_VALUE) {
				import std.conv;
				throw new Exception(to!string(GetLastError()));
			}

			SetConsoleActiveScreenBuffer(hConsole);
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
			//size.X = 80;
			//size.Y = 24;
			//SetConsoleScreenBufferSize(hConsole, size);

			GetConsoleCursorInfo(hConsole, &originalCursorInfo);

			clear();
		}
	}

	private void goLinear() {
		if(UseVtSequences) {
			doTermcap("te");
		} else version(Win32Console) if(UseWin32Console) {
			auto stdo = GetStdHandle(STD_OUTPUT_HANDLE);
			SetConsoleActiveScreenBuffer(stdo);
			if(hConsole !is stdo)
				CloseHandle(hConsole);

			hConsole = stdo;
		}
	}

	private ConsoleOutputType originalType;
	private bool typeChanged;

	// EXPERIMENTAL do not use yet
	/++
		It is not valid to call this if you constructed with minimalProcessing.
	+/
	void enableAlternateScreen(bool active) {
		assert(type != ConsoleOutputType.minimalProcessing);

		if(active) {
			if(type == ConsoleOutputType.cellular)
				return; // already set

			flush();
			goCellular();
			type = ConsoleOutputType.cellular;
		} else {
			if(type == ConsoleOutputType.linear)
				return; // already set

			flush();
			goLinear();
			type = ConsoleOutputType.linear;
		}
	}

	version(Windows) {
		HANDLE hConsole;
		CONSOLE_SCREEN_BUFFER_INFO originalSbi;
	}

	version(Win32Console) {
		private Color defaultBackgroundColor = Color.black;
		private Color defaultForegroundColor = Color.white;
		// UINT oldCp;
		// UINT oldCpIn;
	}

	// only use this if you are sure you know what you want, since the terminal is a shared resource you generally really want to reset it to normal when you leave...
	bool _suppressDestruction = false;

	bool _initialized = false; // set to true for Terminal.init purposes, but ctors will set it to false initially, then might reset to true if needed

	~this() {
		if(!_initialized)
			return;

		import core.memory;
		static if(is(typeof(GC.inFinalizer)))
			if(GC.inFinalizer)
				return;

		if(_suppressDestruction) {
			flush();
			return;
		}

		if(UseVtSequences) {
			if(type == ConsoleOutputType.cellular) {
				goLinear();
			}
			version(TerminalDirectToEmulator) {
				if(usingDirectEmulator) {

					if(integratedTerminalEmulatorConfiguration.closeOnExit) {
						tew.parentWindow.close();
					} else {
						writeln("\n\n<exited>");
						setTitle(tew.terminalEmulator.currentTitle ~ " <exited>");
					}

					tew.term = null;
				} else {
					if(terminalInFamily("xterm", "rxvt", "screen", "tmux")) {
						writeStringRaw("\033[23;0t"); // restore window title from the stack
					}
				}
			} else
			if(terminalInFamily("xterm", "rxvt", "screen", "tmux")) {
				writeStringRaw("\033[23;0t"); // restore window title from the stack
			}
			cursor = TerminalCursor.DEFAULT;
			showCursor();
			reset();
			flush();

			if(lineGetter !is null)
				lineGetter.dispose();
		} else version(Win32Console) if(UseWin32Console) {
			flush(); // make sure user data is all flushed before resetting
			reset();
			showCursor();

			if(lineGetter !is null)
				lineGetter.dispose();


			/+
			SetConsoleOutputCP(oldCp);
			SetConsoleCP(oldCpIn);
			+/

			goLinear();
		}

		flush();

		version(TerminalDirectToEmulator)
		if(usingDirectEmulator && guiThread !is null) {
			guiThread.join();
			guiThread = null;
		}
	}

	// lazily initialized and preserved between calls to getline for a bit of efficiency (only a bit)
	// and some history storage.
	/++
		The cached object used by [getline]. You can set it yourself if you like.

		History:
			Documented `public` on December 25, 2020.
	+/
	public LineGetter lineGetter;

	int _currentForeground = Color.DEFAULT;
	int _currentBackground = Color.DEFAULT;
	RGB _currentForegroundRGB;
	RGB _currentBackgroundRGB;
	bool reverseVideo = false;

	/++
		Attempts to set color according to a 24 bit value (r, g, b, each >= 0 and < 256).


		This is not supported on all terminals. It will attempt to fall back to a 256-color
		or 8-color palette in those cases automatically.

		Returns: true if it believes it was successful (note that it cannot be completely sure),
		false if it had to use a fallback.
	+/
	bool setTrueColor(RGB foreground, RGB background, ForceOption force = ForceOption.automatic) {
		if(force == ForceOption.neverSend) {
			_currentForeground = -1;
			_currentBackground = -1;
			_currentForegroundRGB = foreground;
			_currentBackgroundRGB = background;
			return true;
		}

		if(force == ForceOption.automatic && _currentForeground == -1 && _currentBackground == -1 && (_currentForegroundRGB == foreground && _currentBackgroundRGB == background))
			return true;

		_currentForeground = -1;
		_currentBackground = -1;
		_currentForegroundRGB = foreground;
		_currentBackgroundRGB = background;

		if(UseVtSequences) {
			// FIXME: if the terminal reliably does support 24 bit color, use it
			// instead of the round off. But idk how to detect that yet...

			// fallback to 16 color for term that i know don't take it well
			import std.process;
			import std.string;
			version(TerminalDirectToEmulator)
			if(usingDirectEmulator)
				goto skip_approximation;

			if(environment.get("TERM") == "rxvt" || environment.get("TERM") == "linux") {
				// not likely supported, use 16 color fallback
				auto setTof = approximate16Color(foreground);
				auto setTob = approximate16Color(background);

				writeStringRaw(format("\033[%dm\033[3%dm\033[4%dm",
					(setTof & Bright) ? 1 : 0,
					cast(int) (setTof & ~Bright),
					cast(int) (setTob & ~Bright)
				));

				return false;
			}

			skip_approximation:

			// otherwise, assume it is probably supported and give it a try
			writeStringRaw(format("\033[38;5;%dm\033[48;5;%dm",
				colorToXTermPaletteIndex(foreground),
				colorToXTermPaletteIndex(background)
			));

			/+ // this is the full 24 bit color sequence
			writeStringRaw(format("\033[38;2;%d;%d;%dm", foreground.r, foreground.g, foreground.b));
			writeStringRaw(format("\033[48;2;%d;%d;%dm", background.r, background.g, background.b));
			+/

			return true;
		} version(Win32Console) if(UseWin32Console) {
			flush();
			ushort setTob = arsdTerminalColorToWin32ConsoleColor(approximate16Color(background));
			ushort setTof = arsdTerminalColorToWin32ConsoleColor(approximate16Color(foreground));
			SetConsoleTextAttribute(
				hConsole,
				cast(ushort)((setTob << 4) | setTof));
			return false;
		}
		return false;
	}

	/// Changes the current color. See enum [Color] for the values and note colors can be [arsd.docs.general_concepts#bitmasks|bitwise-or] combined with [Bright].
	void color(int foreground, int background, ForceOption force = ForceOption.automatic, bool reverseVideo = false) {
		if(!usingDirectEmulator && !stdoutIsTerminal && type != ConsoleOutputType.minimalProcessing)
			return;
		if(force != ForceOption.neverSend) {
			if(UseVtSequences) {
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
			} else version(Win32Console) if(UseWin32Console) {
				// assuming a dark background on windows, so LowContrast == dark which means the bit is NOT set on hardware
				/*
				foreground ^= LowContrast;
				background ^= LowContrast;
				*/

				ushort setTof = cast(ushort) foreground;
				ushort setTob = cast(ushort) background;

				// this isn't necessarily right but meh
				if(background == Color.DEFAULT)
					setTob = defaultBackgroundColor;
				if(foreground == Color.DEFAULT)
					setTof = defaultForegroundColor;

				if(force == ForceOption.alwaysSend || reverseVideo != this.reverseVideo || foreground != _currentForeground || background != _currentBackground) {
					flush(); // if we don't do this now, the buffering can screw up the colors...
					if(reverseVideo) {
						if(background == Color.DEFAULT)
							setTof = defaultBackgroundColor;
						else
							setTof = cast(ushort) background | (foreground & Bright);

						if(background == Color.DEFAULT)
							setTob = defaultForegroundColor;
						else
							setTob = cast(ushort) (foreground & ~Bright);
					}
					SetConsoleTextAttribute(
						hConsole,
						cast(ushort)((arsdTerminalColorToWin32ConsoleColor(cast(Color) setTob) << 4) | arsdTerminalColorToWin32ConsoleColor(cast(Color) setTof)));
				}
			}
		}

		_currentForeground = foreground;
		_currentBackground = background;
		this.reverseVideo = reverseVideo;
	}

	private bool _underlined = false;
	private bool _bolded = false;
	private bool _italics = false;

	/++
		Outputs a hyperlink to my custom terminal (v0.0.7 or later) or to version
		`TerminalDirectToEmulator`.  The way it works is a bit strange...


		If using a terminal that supports it, it outputs the given text with the
		given identifier attached (one bit of identifier per grapheme of text!). When
		the user clicks on it, it will send a [LinkEvent] with the text and the identifier
		for you to respond, if in real-time input mode, or a simple paste event with the
		text if not (you will not be able to distinguish this from a user pasting the
		same text).

		If the user's terminal does not support my feature, it writes plain text instead.

		It is important that you make sure your program still works even if the hyperlinks
		never work - ideally, make them out of text the user can type manually or copy/paste
		into your command line somehow too.

		Hyperlinks may not work correctly after your program exits or if you are capturing
		mouse input (the user will have to hold shift in that case). It is really designed
		for linear mode with direct to emulator mode. If you are using cellular mode with
		full input capturing, you should manage the clicks yourself.

		Similarly, if it horizontally scrolls off the screen, it can be corrupted since it
		packs your text and identifier into free bits in the screen buffer itself. I may be
		able to fix that later.

		Params:
			text = text displayed in the terminal

			identifier = an additional number attached to the text and returned to you in a [LinkEvent].
			Possible uses of this are to have a small number of "link classes" that are handled based on
			the text. For example, maybe identifier == 0 means paste text into the line. identifier == 1
			could mean open a browser. identifier == 2 might open details for it. Just be sure to encode
			the bulk of the information into the text so the user can copy/paste it out too.

			You may also create a mapping of (identifier,text) back to some other activity, but if you do
			that, be sure to check [hyperlinkSupported] and fallback in your own code so it still makes
			sense to users on other terminals.

			autoStyle = set to `false` to suppress the automatic color and underlining of the text.

		Bugs:
			there's no keyboard interaction with it at all right now. i might make the terminal
			emulator offer the ids or something through a hold ctrl or something interface. idk.
			or tap ctrl twice to turn that on.

		History:
			Added March 18, 2020
	+/
	void hyperlink(string text, ushort identifier = 0, bool autoStyle = true) {
		if((tcaps & TerminalCapabilities.arsdHyperlinks)) {
			bool previouslyUnderlined = _underlined;
			int fg = _currentForeground, bg = _currentBackground;
			if(autoStyle) {
				color(Color.blue, Color.white);
				underline = true;
			}

			import std.conv;
			writeStringRaw("\033[?" ~ to!string(65536 + identifier) ~ "h");
			write(text);
			writeStringRaw("\033[?65536l");

			if(autoStyle) {
				underline = previouslyUnderlined;
				color(fg, bg);
			}
		} else {
			write(text); // graceful degrade
		}
	}

	/++
		Returns true if the terminal advertised compatibility with the [hyperlink] function's
		implementation.

		History:
			Added April 2, 2021
	+/
	bool hyperlinkSupported() {
		if((tcaps & TerminalCapabilities.arsdHyperlinks)) {
			return true;
		} else {
			return false;
		}
	}

	/++
		Sets or resets the terminal's text rendering options.

		Note: the Windows console does not support these and many Unix terminals don't either.
		Many will treat italic as blink and bold as brighter color. There is no way to know
		what will happen. So I don't recommend you use these in general. They don't even work
		with `-version=TerminalDirectToEmulator`.

		History:
			underline was added in March 2020. italic and bold were added November 1, 2022

			since they are unreliable, i didnt want to add these but did for some special requests.
	+/
	void underline(bool set, ForceOption force = ForceOption.automatic) {
		if(set == _underlined && force != ForceOption.alwaysSend)
			return;
		if(UseVtSequences) {
			if(set)
				writeStringRaw("\033[4m");
			else
				writeStringRaw("\033[24m");
		}
		_underlined = set;
	}
	/// ditto
	void italic(bool set, ForceOption force = ForceOption.automatic) {
		if(set == _italics && force != ForceOption.alwaysSend)
			return;
		if(UseVtSequences) {
			if(set)
				writeStringRaw("\033[3m");
			else
				writeStringRaw("\033[23m");
		}
		_italics = set;
	}
	/// ditto
	void bold(bool set, ForceOption force = ForceOption.automatic) {
		if(set == _bolded && force != ForceOption.alwaysSend)
			return;
		if(UseVtSequences) {
			if(set)
				writeStringRaw("\033[1m");
			else
				writeStringRaw("\033[22m");
		}
		_bolded = set;
	}

	// FIXME: implement this in arsd terminalemulator too
	// and make my vim use it. these are extensions in the iterm, etc
	/+
	void setUnderlineColor(Color colorIndex) {} // 58;5;n
	void setUnderlineColor(int r, int g, int b) {} // 58;2;r;g;b
	void setDefaultUnderlineColor() {} // 59
	+/





	/// Returns the terminal to normal output colors
	void reset() {
		if(!usingDirectEmulator && stdoutIsTerminal && type != ConsoleOutputType.minimalProcessing) {
			if(UseVtSequences)
				writeStringRaw("\033[0m");
			else version(Win32Console) if(UseWin32Console) {
				SetConsoleTextAttribute(
					hConsole,
					originalSbi.wAttributes);
			}
		}

		_underlined = false;
		_italics = false;
		_bolded = false;
		_currentForeground = Color.DEFAULT;
		_currentBackground = Color.DEFAULT;
		reverseVideo = false;
	}

	// FIXME: add moveRelative

	/++
		The current cached x and y positions of the output cursor. 0 == leftmost column for x and topmost row for y.

		Please note that the cached position is not necessarily accurate. You may consider calling [updateCursorPosition]
		first to ask the terminal for its authoritative answer.
	+/
	@property int cursorX() {
		if(cursorPositionDirty)
			updateCursorPosition();
		return _cursorX;
	}

	/// ditto
	@property int cursorY() {
		if(cursorPositionDirty)
			updateCursorPosition();
		return _cursorY;
	}

	private bool cursorPositionDirty = true;

	private int _cursorX;
	private int _cursorY;

	/// Moves the output cursor to the given position. (0, 0) is the upper left corner of the screen. The force parameter can be used to force an update, even if Terminal doesn't think it is necessary
	void moveTo(int x, int y, ForceOption force = ForceOption.automatic) {
		if(force != ForceOption.neverSend && (force == ForceOption.alwaysSend || x != _cursorX || y != _cursorY)) {
			executeAutoHideCursor();
			if(UseVtSequences) {
				doTermcap("cm", y, x);
			} else version(Win32Console) if(UseWin32Console) {
				flush(); // if we don't do this now, the buffering can screw up the position
				COORD coord = {cast(short) x, cast(short) y};
				SetConsoleCursorPosition(hConsole, coord);
			}
		}

		_cursorX = x;
		_cursorY = y;
	}

	/// shows the cursor
	void showCursor() {
		if(UseVtSequences)
			doTermcap("ve");
		else version(Win32Console) if(UseWin32Console) {
			CONSOLE_CURSOR_INFO info;
			GetConsoleCursorInfo(hConsole, &info);
			info.bVisible = true;
			SetConsoleCursorInfo(hConsole, &info);
		}
	}

	/// hides the cursor
	void hideCursor() {
		if(UseVtSequences) {
			doTermcap("vi");
		} else version(Win32Console) if(UseWin32Console) {
			CONSOLE_CURSOR_INFO info;
			GetConsoleCursorInfo(hConsole, &info);
			info.bVisible = false;
			SetConsoleCursorInfo(hConsole, &info);
		}

	}

	private bool autoHidingCursor;
	private bool autoHiddenCursor;
	// explicitly not publicly documented
	// Sets the cursor to automatically insert a hide command at the front of the output buffer iff it is moved.
	// Call autoShowCursor when you are done with the batch update.
	void autoHideCursor() {
		autoHidingCursor = true;
	}

	private void executeAutoHideCursor() {
		if(autoHidingCursor) {
			if(UseVtSequences) {
				// prepend the hide cursor command so it is the first thing flushed
				writeBuffer = "\033[?25l" ~ writeBuffer;
			} else version(Win32Console) if(UseWin32Console)
				hideCursor();

			autoHiddenCursor = true;
			autoHidingCursor = false; // already been done, don't insert the command again
		}
	}

	// explicitly not publicly documented
	// Shows the cursor if it was automatically hidden by autoHideCursor and resets the internal auto hide state.
	void autoShowCursor() {
		if(autoHiddenCursor)
			showCursor();

		autoHidingCursor = false;
		autoHiddenCursor = false;
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
		import std.string;
		if(terminalInFamily("xterm", "rxvt", "screen", "tmux"))
			writeStringRaw(format("\033]0;%s\007", t));
		else version(Win32Console) if(UseWin32Console) {
			wchar[256] buffer;
			size_t bufferLength;
			foreach(wchar ch; t)
				if(bufferLength < buffer.length)
					buffer[bufferLength++] = ch;
			if(bufferLength < buffer.length)
				buffer[bufferLength++] = 0;
			else
				buffer[$-1] = 0;
			SetConsoleTitleW(buffer.ptr);
		}
	}

	/// Flushes your updates to the terminal.
	/// It is important to call this when you are finished writing for now if you are using the version=with_eventloop
	void flush() {
		version(TerminalDirectToEmulator)
			if(windowGone)
				return;
		version(TerminalDirectToEmulator)
			if(usingDirectEmulator && pipeThroughStdOut) {
				fflush(stdout);
				fflush(stderr);
				return;
			}

		if(writeBuffer.length == 0)
			return;

		version(TerminalDirectToEmulator) {
			if(usingDirectEmulator) {
				tew.sendRawInput(cast(ubyte[]) writeBuffer);
				writeBuffer = null;
			} else {
				interiorFlush();
			}
		} else {
			interiorFlush();
		}
	}

	private void interiorFlush() {
		version(Posix) {
			if(_writeDelegate !is null) {
				_writeDelegate(writeBuffer);
				writeBuffer = null;
			} else {
				ssize_t written;

				while(writeBuffer.length) {
					written = unix.write(this.fdOut, writeBuffer.ptr, writeBuffer.length);
					if(written < 0) {
						import core.stdc.errno;
						auto err = errno();
						if(err == EAGAIN || err == EWOULDBLOCK) {
							import core.thread;
							Thread.sleep(1.msecs);
							continue;
						}
						throw new Exception("write failed for some reason");
					}
					writeBuffer = writeBuffer[written .. $];
				}
			}
		} else version(Win32Console) {
			// if(_writeDelegate !is null)
				// _writeDelegate(writeBuffer);

			if(UseWin32Console) {
				import std.conv;
				// FIXME: I'm not sure I'm actually happy with this allocation but
				// it probably isn't a big deal. At least it has unicode support now.
				wstring writeBufferw = to!wstring(writeBuffer);
				while(writeBufferw.length) {
					DWORD written;
					WriteConsoleW(hConsole, writeBufferw.ptr, cast(DWORD)writeBufferw.length, &written, null);
					writeBufferw = writeBufferw[written .. $];
				}
			} else {
				import std.stdio;
				stdout.rawWrite(writeBuffer); // FIXME
			}

			writeBuffer = null;
		}
	}

	int[] getSize() {
		version(TerminalDirectToEmulator) {
			if(usingDirectEmulator)
				return [tew.terminalEmulator.width, tew.terminalEmulator.height];
			else
				return getSizeInternal();
		} else {
			return getSizeInternal();
		}
	}

	private int[] getSizeInternal() {
		if(getSizeOverride)
			return getSizeOverride();

		if(!usingDirectEmulator && !stdoutIsTerminal && type != ConsoleOutputType.minimalProcessing)
			throw new Exception("unable to get size of non-terminal");
		version(Windows) {
			CONSOLE_SCREEN_BUFFER_INFO info;
			GetConsoleScreenBufferInfo( hConsole, &info );

			int cols, rows;

			cols = (info.srWindow.Right - info.srWindow.Left + 1);
			rows = (info.srWindow.Bottom - info.srWindow.Top + 1);

			return [cols, rows];
		} else {
			winsize w;
			ioctl(1, TIOCGWINSZ, &w);
			return [w.ws_col, w.ws_row];
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
        import std.uni;
        int[Grapheme] graphemeWidth;
        bool willInsertFollowingLine = false;
        bool uncertainIfAtEndOfLine = false;
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
        void writePrintableString(const(char)[] s, ForceOption force = ForceOption.automatic) {
		writePrintableString_(s, force);
		cursorPositionDirty = true;
        }

	void writePrintableString_(const(char)[] s, ForceOption force = ForceOption.automatic) {
		// an escape character is going to mess things up. Actually any non-printable character could, but meh
		// assert(s.indexOf("\033") == -1);

		if(s.length == 0)
			return;

		if(type == ConsoleOutputType.minimalProcessing) {
			// need to still try to track a little, even if we can't
			// talk to the terminal in minimal processing mode
			auto height = this.height;
			foreach(dchar ch; s) {
				switch(ch) {
					case '\n':
						_cursorX = 0;
						_cursorY++;
					break;
					case '\t':
						int diff = 8 - (_cursorX % 8);
						if(diff == 0)
							diff = 8;
						_cursorX += diff;
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
			}
		}

		version(TerminalDirectToEmulator) {
			// this breaks up extremely long output a little as an aid to the
			// gui thread; by breaking it up, it helps to avoid monopolizing the
			// event loop. Easier to do here than in the thread itself because
			// this one doesn't have escape sequences to break up so it avoids work.
			while(s.length) {
				auto len = s.length;
				if(len > 1024 * 32) {
					len = 1024 * 32;
					// get to the start of a utf-8 sequence. kidna sorta.
					while(len && (s[len] & 0x1000_0000))
						len--;
				}
				auto next = s[0 .. len];
				s = s[len .. $];
				writeStringRaw(next);
			}
		} else {
			writeStringRaw(s);
		}
	}

	/* private */ bool _wrapAround = true;

	deprecated alias writePrintableString writeString; /// use write() or writePrintableString instead

	private string writeBuffer;
	/++
		Set this before you create any `Terminal`s if you want it to merge the C
		stdout and stderr streams into the GUI terminal window. It will always
		redirect stdout if this is set (you may want to check for existing redirections
		first before setting this, see [Terminal.stdoutIsTerminal]), and will redirect
		stderr as well if it is invalid or points to the parent terminal.

		You must opt into this since it is globally invasive (changing the C handle
		can affect things across the program) and possibly buggy. It also will likely
		hurt the efficiency of embedded terminal output.

		Please note that this is currently only available in with `TerminalDirectToEmulator`
		version enabled.

		History:
		Added October 2, 2020.
	+/
	version(TerminalDirectToEmulator)
	static shared(bool) pipeThroughStdOut = false;

	/++
		Options for [stderrBehavior]. Only applied if [pipeThroughStdOut] is set to `true` and its redirection actually is performed.
	+/
	version(TerminalDirectToEmulator)
	enum StderrBehavior {
		sendToWindowIfNotAlreadyRedirected, /// If stderr does not exist or is pointing at a parent terminal, change it to point at the window alongside stdout (if stdout is changed by [pipeThroughStdOut]).
		neverSendToWindow, /// Tell this library to never redirect stderr. It will leave it alone.
		alwaysSendToWindow /// Always redirect stderr to the window through stdout if [pipeThroughStdOut] is set, even if it has already been redirected by the shell or code previously in your program.
	}

	/++
		If [pipeThroughStdOut] is set, this decides what happens to stderr.
		See: [StderrBehavior].

		History:
		Added October 3, 2020.
	+/
	version(TerminalDirectToEmulator)
	static shared(StderrBehavior) stderrBehavior = StderrBehavior.sendToWindowIfNotAlreadyRedirected;

	// you really, really shouldn't use this unless you know what you are doing
	/*private*/ void writeStringRaw(in char[] s) {
		version(TerminalDirectToEmulator)
		if(pipeThroughStdOut && usingDirectEmulator) {
			fwrite(s.ptr, 1, s.length, stdout);
			return;
		}

		writeBuffer ~= s; // buffer it to do everything at once in flush() calls
		if(writeBuffer.length >  1024 * 32)
			flush();
	}


	/// Clears the screen.
	void clear() {
		if(UseVtSequences) {
			doTermcap("cl");
		} else version(Win32Console) if(UseWin32Console) {
			// http://support.microsoft.com/kb/99261
			flush();

			DWORD c;
			CONSOLE_SCREEN_BUFFER_INFO csbi;
			DWORD conSize;
			GetConsoleScreenBufferInfo(hConsole, &csbi);
			conSize = csbi.dwSize.X * csbi.dwSize.Y;
			COORD coordScreen;
			FillConsoleOutputCharacterA(hConsole, ' ', conSize, coordScreen, &c);
			FillConsoleOutputAttribute(hConsole, csbi.wAttributes, conSize, coordScreen, &c);
			moveTo(0, 0, ForceOption.alwaysSend);
		}

		_cursorX = 0;
		_cursorY = 0;
	}

        /++
		Clears the current line from the cursor onwards.

		History:
			Added January 25, 2023 (dub v11.0)
	+/
        void clearToEndOfLine() {
                if(UseVtSequences) {
                        writeStringRaw("\033[0K");
                }
                else version(Win32Console) if(UseWin32Console) {
                        updateCursorPosition();
                        auto x = _cursorX;
                        auto y = _cursorY;
                        DWORD c;
                        CONSOLE_SCREEN_BUFFER_INFO csbi;
                        DWORD conSize = width-x;
                        GetConsoleScreenBufferInfo(hConsole, &csbi);
                        auto coordScreen = COORD(cast(short) x, cast(short) y);
                        FillConsoleOutputCharacterA(hConsole, ' ', conSize, coordScreen, &c);
                        FillConsoleOutputAttribute(hConsole, csbi.wAttributes, conSize, coordScreen, &c);
                        moveTo(x, y, ForceOption.alwaysSend);
                }
        }
	/++
		Gets a line, including user editing. Convenience method around the [LineGetter] class and [RealTimeConsoleInput] facilities - use them if you need more control.


		$(TIP
			You can set the [lineGetter] member directly if you want things like stored history.

			---
			Terminal terminal = Terminal(ConsoleOutputType.linear);
			terminal.lineGetter = new LineGetter(&terminal, "my_history");

			auto line = terminal.getline("$ ");
			terminal.writeln(line);
			---
		)
		You really shouldn't call this if stdin isn't actually a user-interactive terminal! However, if it isn't, it will simply read one line from the pipe without writing the prompt. See [stdinIsTerminal].

		Params:
			prompt = the prompt to give the user. For example, `"Your name: "`.
			echoChar = the character to show back to the user as they type. The default value of `dchar.init` shows the user their own input back normally. Passing `0` here will disable echo entirely, like a Unix password prompt. Or you might also try `'*'` to do a password prompt that shows the number of characters input to the user.
			prefilledData = the initial data to populate the edit buffer

		History:
			The `echoChar` parameter was added on October 11, 2021 (dub v10.4).

			The `prompt` would not take effect if it was `null` prior to November 12, 2021. Before then, a `null` prompt would just leave the previous prompt string in place on the object. After that, the prompt is always set to the argument, including turning it off if you pass `null` (which is the default).

			Always pass a string if you want it to display a string.

			The `prefilledData` (and overload with it as second param) was added on January 1, 2023 (dub v10.10 / v11.0).

			On November 7, 2023 (dub v11.3), this function started returning stdin.readln in the event that the instance is not connected to a terminal.
	+/
	string getline(string prompt = null, dchar echoChar = dchar.init, string prefilledData = null) {
		if(!usingDirectEmulator && type != ConsoleOutputType.minimalProcessing)
		if(!stdoutIsTerminal || !stdinIsTerminal) {
			import std.stdio;
			import std.string;
			return readln().chomp;
		}

		if(lineGetter is null)
			lineGetter = new LineGetter(&this);
		// since the struct might move (it shouldn't, this should be unmovable!) but since
		// it technically might, I'm updating the pointer before using it just in case.
		lineGetter.terminal = &this;

		auto ec = lineGetter.echoChar;
		auto p = lineGetter.prompt;
		scope(exit) {
			lineGetter.echoChar = ec;
			lineGetter.prompt = p;
		}
		lineGetter.echoChar = echoChar;


		lineGetter.prompt = prompt;
		if(prefilledData) {
			lineGetter.addString(prefilledData);
			lineGetter.maintainBuffer = true;
		}

		auto input = RealTimeConsoleInput(&this, ConsoleInputFlags.raw | ConsoleInputFlags.selectiveMouse | ConsoleInputFlags.paste | ConsoleInputFlags.size | ConsoleInputFlags.noEolWrap);
		auto line = lineGetter.getline(&input);

		// lineGetter leaves us exactly where it was when the user hit enter, giving best
		// flexibility to real-time input and cellular programs. The convenience function,
		// however, wants to do what is right in most the simple cases, which is to actually
		// print the line (echo would be enabled without RealTimeConsoleInput anyway and they
		// did hit enter), so we'll do that here too.
		writePrintableString("\n");

		return line;
	}

	/// ditto
	string getline(string prompt, string prefilledData, dchar echoChar = dchar.init) {
		return getline(prompt, echoChar, prefilledData);
	}


	/++
		Forces [cursorX] and [cursorY] to resync from the terminal.

		History:
			Added January 8, 2023
	+/
	void updateCursorPosition() {
		if(type == ConsoleOutputType.minimalProcessing)
			return;
		auto terminal = &this;

		terminal.flush();
		cursorPositionDirty = false;

		// then get the current cursor position to start fresh
		version(TerminalDirectToEmulator) {
			if(!terminal.usingDirectEmulator)
				return updateCursorPosition_impl();

			if(terminal.pipeThroughStdOut) {
				terminal.tew.terminalEmulator.waitingForInboundSync = true;
				terminal.writeStringRaw("\xff");
				terminal.flush();
				if(windowGone) forceTermination();
				terminal.tew.terminalEmulator.syncSignal.wait();
			}

			terminal._cursorX = terminal.tew.terminalEmulator.cursorX;
			terminal._cursorY = terminal.tew.terminalEmulator.cursorY;
		} else
			updateCursorPosition_impl();
               if(_cursorX == width) {
                       willInsertFollowingLine = true;
                       _cursorX--;
               }
	}
	private void updateCursorPosition_impl() {
		if(!usingDirectEmulator && type != ConsoleOutputType.minimalProcessing)
		if(!stdinIsTerminal || !stdoutIsTerminal)
			throw new Exception("cannot update cursor position on non-terminal");
		auto terminal = &this;
		version(Win32Console) {
			if(UseWin32Console) {
				CONSOLE_SCREEN_BUFFER_INFO info;
				GetConsoleScreenBufferInfo(terminal.hConsole, &info);
				_cursorX = info.dwCursorPosition.X;
				_cursorY = info.dwCursorPosition.Y;
			}
		} else version(Posix) {
			// request current cursor position

			// we have to turn off cooked mode to get this answer, otherwise it will all
			// be messed up. (I hate unix terminals, the Windows way is so much easer.)

			// We also can't use RealTimeConsoleInput here because it also does event loop stuff
			// which would be broken by the child destructor :( (maybe that should be a FIXME)

			/+
			if(rtci !is null) {
				while(rtci.timedCheckForInput_bypassingBuffer(1000))
					rtci.inputQueue ~= rtci.readNextEvents();
			}
			+/

			ubyte[128] hack2;
			termios old;
			ubyte[128] hack;
			tcgetattr(terminal.fdIn, &old);
			auto n = old;
			n.c_lflag &= ~(ICANON | ECHO);
			tcsetattr(terminal.fdIn, TCSANOW, &n);
			scope(exit)
				tcsetattr(terminal.fdIn, TCSANOW, &old);


			terminal.writeStringRaw("\033[6n");
			terminal.flush();

			import std.conv;
			import core.stdc.errno;

			import core.sys.posix.unistd;

			ubyte readOne() {
				ubyte[1] buffer;
				int tries = 0;
				try_again:
				if(tries > 30)
					throw new Exception("terminal reply timed out");
				auto len = read(terminal.fdIn, buffer.ptr, buffer.length);
				if(len == -1) {
					if(errno == EINTR)
						goto try_again;
					if(errno == EAGAIN || errno == EWOULDBLOCK) {
						import core.thread;
						Thread.sleep(10.msecs);
						tries++;
						goto try_again;
					}
				} else if(len == 0) {
					throw new Exception("Couldn't get cursor position to initialize get line " ~ to!string(len) ~ " " ~ to!string(errno));
				}

				return buffer[0];
			}

			nextEscape:
			while(readOne() != '\033') {}
			if(readOne() != '[')
				goto nextEscape;

			int x, y;

			// now we should have some numbers being like yyy;xxxR
			// but there may be a ? in there too; DEC private mode format
			// of the very same data.

			x = 0;
			y = 0;

			auto b = readOne();

			if(b == '?')
				b = readOne(); // no big deal, just ignore and continue

			nextNumberY:
			if(b >= '0' && b <= '9') {
				y *= 10;
				y += b - '0';
			} else goto nextEscape;

			b = readOne();
			if(b != ';')
				goto nextNumberY;

			b = readOne();
			nextNumberX:
			if(b >= '0' && b <= '9') {
				x *= 10;
				x += b - '0';
			} else goto nextEscape;

			b = readOne();
			// another digit
			if(b >= '0' && b <= '9')
				goto nextNumberX;

			if(b != 'R')
				goto nextEscape; // it wasn't the right thing it after all

			_cursorX = x - 1;
			_cursorY = y - 1;
		}
	}
}

/++
	Removes terminal color, bold, etc. sequences from a string,
	making it plain text suitable for output to a normal .txt
	file.
+/
inout(char)[] removeTerminalGraphicsSequences(inout(char)[] s) {
	import std.string;

	// on old compilers, inout index of fails, but const works, so i'll just
	// cast it, this is ok since inout and const work the same regardless
	auto at = (cast(const(char)[])s).indexOf("\033[");
	if(at == -1)
		return s;

	inout(char)[] ret;

	do {
		ret ~= s[0 .. at];
		s = s[at + 2 .. $];
		while(s.length && !((s[0] >= 'a' && s[0] <= 'z') || s[0] >= 'A' && s[0] <= 'Z')) {
			s = s[1 .. $];
		}
		if(s.length)
			s = s[1 .. $]; // skip the terminator
		at = (cast(const(char)[])s).indexOf("\033[");
	} while(at != -1);

	ret ~= s;

	return ret;
}

unittest {
	assert("foo".removeTerminalGraphicsSequences == "foo");
	assert("\033[34mfoo".removeTerminalGraphicsSequences == "foo");
	assert("\033[34mfoo\033[39m".removeTerminalGraphicsSequences == "foo");
	assert("\033[34m\033[45mfoo\033[39mbar\033[49m".removeTerminalGraphicsSequences == "foobar");
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

	/++
		Requests the system to send paste data as a [PasteEvent] to this stream, if possible.

		See_Also:
			[Terminal.requestCopyToPrimary]
			[Terminal.requestCopyToClipboard]
			[Terminal.clipboardSupported]

		History:
			Added February 17, 2020.

			It was in Terminal briefly during an undocumented period, but it had to be moved here to have the context needed to send the real time paste event.
	+/
	void requestPasteFromClipboard() @system {
		version(Win32Console) {
			HWND hwndOwner = null;
			if(OpenClipboard(hwndOwner) == 0)
				throw new Exception("OpenClipboard");
			scope(exit)
				CloseClipboard();
			if(auto dataHandle = GetClipboardData(CF_UNICODETEXT)) {

				if(auto data = cast(wchar*) GlobalLock(dataHandle)) {
					scope(exit)
						GlobalUnlock(dataHandle);

					int len = 0;
					auto d = data;
					while(*d) {
						d++;
						len++;
					}
					string s;
					s.reserve(len);
					foreach(idx, dchar ch; data[0 .. len]) {
						// CR/LF -> LF
						if(ch == '\r' && idx + 1 < len && data[idx + 1] == '\n')
							continue;
						s ~= ch;
					}

					injectEvent(InputEvent(PasteEvent(s), terminal), InjectionPosition.tail);
				}
			}
		} else
		if(terminal.clipboardSupported) {
			if(UseVtSequences)
				terminal.writeStringRaw("\033]52;c;?\007");
		}
	}

	/// ditto
	void requestPasteFromPrimary() {
		if(terminal.clipboardSupported) {
			if(UseVtSequences)
				terminal.writeStringRaw("\033]52;p;?\007");
		}
	}

	private bool utf8MouseMode;

	version(Posix) {
		private int fdOut;
		private int fdIn;
		private sigaction_t oldSigWinch;
		private sigaction_t oldSigIntr;
		private sigaction_t oldHupIntr;
		private sigaction_t oldContIntr;
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
	private void function(RealTimeConsoleInput*)[] destructor;

	version(Posix)
	private bool reinitializeAfterSuspend() {
		version(TerminalDirectToEmulator) {
			if(terminal.usingDirectEmulator)
				return false;
		}

		// copy/paste from posixInit but with private old
		if(fdIn != -1) {
			termios old;
			ubyte[128] hack;

			tcgetattr(fdIn, &old);
			auto n = old;

			auto f = ICANON;
			if(!(flags & ConsoleInputFlags.echo))
				f |= ECHO;

			n.c_lflag &= ~f;
			tcsetattr(fdIn, TCSANOW, &n);

			// ensure these are still appropriately blocking after the resumption
			import core.sys.posix.fcntl;
			if(fdIn != -1) {
				auto ctl = fcntl(fdIn, F_GETFL);
				ctl &= ~O_NONBLOCK;
				if(arsd.core.inSchedulableTask)
					ctl |= O_NONBLOCK;
				fcntl(fdIn, F_SETFL, ctl);
			}
			if(fdOut != -1) {
				auto ctl = fcntl(fdOut, F_GETFL);
				ctl &= ~O_NONBLOCK;
				if(arsd.core.inSchedulableTask)
					ctl |= O_NONBLOCK;
				fcntl(fdOut, F_SETFL, ctl);
			}
		}

		// copy paste from constructor, but not setting the destructor teardown since that's already done
		if(flags & ConsoleInputFlags.selectiveMouse) {
			terminal.writeStringRaw("\033[?1014h");
		} else if(flags & ConsoleInputFlags.mouse) {
			terminal.writeStringRaw("\033[?1000h");
			import std.process : environment;

			if(terminal.terminalInFamily("xterm") && environment.get("MOUSE_HACK") != "1002") {
				terminal.writeStringRaw("\033[?1003h\033[?1005h"); // full mouse tracking (1003) with utf-8 mode (1005) for exceedingly large terminals
				utf8MouseMode = true;
			} else if(terminal.terminalInFamily("rxvt", "screen", "tmux") || environment.get("MOUSE_HACK") == "1002") {
				terminal.writeStringRaw("\033[?1002h"); // this is vt200 mouse with press/release and motion notification iff buttons are pressed
			}
		}
		if(flags & ConsoleInputFlags.paste) {
			if(terminal.terminalInFamily("xterm", "rxvt", "screen", "tmux")) {
				terminal.writeStringRaw("\033[?2004h"); // bracketed paste mode
			}
		}

		if(terminal.tcaps & TerminalCapabilities.arsdHyperlinks) {
			terminal.writeStringRaw("\033[?3004h"); // bracketed link mode
		}

		// try to ensure the terminal is in UTF-8 mode
		if(terminal.terminalInFamily("xterm", "screen", "linux", "tmux") && !terminal.isMacTerminal()) {
			terminal.writeStringRaw("\033%G");
		}

		terminal.flush();

		// returning true will send a resize event as well, which does the rest of the catch up and redraw as necessary
		return true;
	}

	/// To capture input, you need to provide a terminal and some flags.
	public this(Terminal* terminal, ConsoleInputFlags flags) {
		createLock();
		_initialized = true;
		this.flags = flags;
		this.terminal = terminal;

		version(Windows) {
			inputHandle = GetStdHandle(STD_INPUT_HANDLE);

		}

		version(Win32Console) {

			GetConsoleMode(inputHandle, &oldInput);

			DWORD mode = 0;
			//mode |= ENABLE_PROCESSED_INPUT /* 0x01 */; // this gives Ctrl+C and automatic paste... which we probably want to be similar to linux
			//if(flags & ConsoleInputFlags.size)
			mode |= ENABLE_WINDOW_INPUT /* 0208 */; // gives size etc
			if(flags & ConsoleInputFlags.echo)
				mode |= ENABLE_ECHO_INPUT; // 0x4
			if(flags & ConsoleInputFlags.mouse)
				mode |= ENABLE_MOUSE_INPUT; // 0x10
			// if(flags & ConsoleInputFlags.raw) // FIXME: maybe that should be a separate flag for ENABLE_LINE_INPUT

			SetConsoleMode(inputHandle, mode);
			destructor ~= (this_) { SetConsoleMode(this_.inputHandle, this_.oldInput); };


			GetConsoleMode(terminal.hConsole, &oldOutput);
			mode = 0;
			// we want this to match linux too
			mode |= ENABLE_PROCESSED_OUTPUT; /* 0x01 */
			if(!(flags & ConsoleInputFlags.noEolWrap))
				mode |= ENABLE_WRAP_AT_EOL_OUTPUT; /* 0x02 */
			SetConsoleMode(terminal.hConsole, mode);
			destructor ~= (this_) { SetConsoleMode(this_.terminal.hConsole, this_.oldOutput); };
		}

		version(TerminalDirectToEmulator) {
			if(terminal.usingDirectEmulator)
				terminal.tew.terminalEmulator.echo = (flags & ConsoleInputFlags.echo) ? true : false;
			else version(Posix)
				posixInit();
		} else version(Posix) {
			posixInit();
		}

		if(UseVtSequences) {


			if(flags & ConsoleInputFlags.selectiveMouse) {
				// arsd terminal extension, but harmless on most other terminals
				terminal.writeStringRaw("\033[?1014h");
				destructor ~= (this_) { this_.terminal.writeStringRaw("\033[?1014l"); };
			} else if(flags & ConsoleInputFlags.mouse) {
				// basic button press+release notification

				// FIXME: try to get maximum capabilities from all terminals
				// right now this works well on xterm but rxvt isn't sending movements...

				terminal.writeStringRaw("\033[?1000h");
				destructor ~= (this_) { this_.terminal.writeStringRaw("\033[?1000l"); };
				// the MOUSE_HACK env var is for the case where I run screen
				// but set TERM=xterm (which I do from putty). The 1003 mouse mode
				// doesn't work there, breaking mouse support entirely. So by setting
				// MOUSE_HACK=1002 it tells us to use the other mode for a fallback.
				import std.process : environment;

				if(terminal.terminalInFamily("xterm") && environment.get("MOUSE_HACK") != "1002") {
					// this is vt200 mouse with full motion tracking, supported by xterm
					terminal.writeStringRaw("\033[?1003h\033[?1005h");
					utf8MouseMode = true;
					destructor ~= (this_) { this_.terminal.writeStringRaw("\033[?1005l\033[?1003l"); };
				} else if(terminal.terminalInFamily("rxvt", "screen", "tmux") || environment.get("MOUSE_HACK") == "1002") {
					terminal.writeStringRaw("\033[?1002h"); // this is vt200 mouse with press/release and motion notification iff buttons are pressed
					destructor ~= (this_) { this_.terminal.writeStringRaw("\033[?1002l"); };
				}
			}
			if(flags & ConsoleInputFlags.paste) {
				if(terminal.terminalInFamily("xterm", "rxvt", "screen", "tmux")) {
					terminal.writeStringRaw("\033[?2004h"); // bracketed paste mode
					destructor ~= (this_) { this_.terminal.writeStringRaw("\033[?2004l"); };
				}
			}

			if(terminal.tcaps & TerminalCapabilities.arsdHyperlinks) {
				terminal.writeStringRaw("\033[?3004h"); // bracketed link mode
				destructor ~= (this_) { this_.terminal.writeStringRaw("\033[?3004l"); };
			}

			// try to ensure the terminal is in UTF-8 mode
			if(terminal.terminalInFamily("xterm", "screen", "linux", "tmux") && !terminal.isMacTerminal()) {
				terminal.writeStringRaw("\033%G");
			}

			terminal.flush();
		}


		version(with_eventloop) {
			import arsd.eventloop;
			version(Win32Console) {
				static HANDLE listenTo;
				listenTo = inputHandle;
			} else version(Posix) {
				// total hack but meh i only ever use this myself
				static int listenTo;
				listenTo = this.fdIn;
			} else static assert(0, "idk about this OS");

			version(Posix)
			addListener(&signalFired);

			if(listenTo != -1) {
				addFileEventListeners(listenTo, &eventListener, null, null);
				destructor ~= (this_) { removeFileEventListeners(listenTo); };
			}
			addOnIdle(&terminal.flush);
			destructor ~= (this_) { removeOnIdle(&this_.terminal.flush); };
		}
	}

	version(Posix)
	private void posixInit() {
		this.fdIn = terminal.fdIn;
		this.fdOut = terminal.fdOut;

		// if a naughty program changes the mode on these to nonblocking
		// and doesn't change them back, it can cause trouble to us here.
		// so i explicitly set the blocking flag since EAGAIN is not as nice
		// for my purposes (it isn't consistently handled well in here)
		import core.sys.posix.fcntl;
		{
			auto ctl = fcntl(fdIn, F_GETFL);
			ctl &= ~O_NONBLOCK;
			if(arsd.core.inSchedulableTask)
				ctl |= O_NONBLOCK;
			fcntl(fdIn, F_SETFL, ctl);
		}
		{
			auto ctl = fcntl(fdOut, F_GETFL);
			ctl &= ~O_NONBLOCK;
			if(arsd.core.inSchedulableTask)
				ctl |= O_NONBLOCK;
			fcntl(fdOut, F_SETFL, ctl);
		}

		if(fdIn != -1) {
			tcgetattr(fdIn, &old);
			auto n = old;

			auto f = ICANON;
			if(!(flags & ConsoleInputFlags.echo))
				f |= ECHO;

			// \033Z or \033[c

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

		{
			import core.sys.posix.signal;
			sigaction_t n;
			n.sa_handler = &hangupSignalHandler;
			n.sa_mask = cast(sigset_t) 0;
			n.sa_flags = 0;
			sigaction(SIGHUP, &n, &oldHupIntr);
		}

		{
			import core.sys.posix.signal;
			sigaction_t n;
			n.sa_handler = &continueSignalHandler;
			n.sa_mask = cast(sigset_t) 0;
			n.sa_flags = 0;
			sigaction(SIGCONT, &n, &oldContIntr);
		}

	}

	void fdReadyReader() {
		auto queue = readNextEvents();
		foreach(event; queue)
			userEventHandler(event);
	}

	void delegate(InputEvent) userEventHandler;

	/++
		If you are using [arsd.simpledisplay] and want terminal interop too, you can call
		this function to add it to the sdpy event loop and get the callback called on new
		input.

		Note that you will probably need to call `terminal.flush()` when you are doing doing
		output, as the sdpy event loop doesn't know to do that (yet). I will probably change
		that in a future version, but it doesn't hurt to call it twice anyway, so I recommend
		calling flush yourself in any code you write using this.
	+/
	auto integrateWithSimpleDisplayEventLoop()(void delegate(InputEvent) userEventHandler) {
		this.userEventHandler = userEventHandler;
		import arsd.simpledisplay;
		version(Win32Console)
			auto listener = new WindowsHandleReader(&fdReadyReader, terminal.hConsole);
		else version(linux)
			auto listener = new PosixFdReader(&fdReadyReader, fdIn);
		else static assert(0, "sdpy event loop integration not implemented on this platform");

		return listener;
	}

	version(with_eventloop) {
		version(Posix)
		void signalFired(SignalFired) {
			if(interrupted) {
				interrupted = false;
				send(InputEvent(UserInterruptionEvent(), terminal));
			}
			if(windowSizeChanged)
				send(checkWindowSizeChanged());
			if(hangedUp) {
				hangedUp = false;
				send(InputEvent(HangupEvent(), terminal));
			}
		}

		import arsd.eventloop;
		void eventListener(OsFileHandle fd) {
			auto queue = readNextEvents();
			foreach(event; queue)
				send(event);
		}
	}

	bool _suppressDestruction;
	bool _initialized = false;

	~this() {
		if(!_initialized)
			return;
		import core.memory;
		static if(is(typeof(GC.inFinalizer)))
			if(GC.inFinalizer)
				return;

		if(_suppressDestruction)
			return;

		// the delegate thing doesn't actually work for this... for some reason

		version(TerminalDirectToEmulator) {
			if(terminal && terminal.usingDirectEmulator)
				goto skip_extra;
		}

		version(Posix) {
			if(fdIn != -1)
				tcsetattr(fdIn, TCSANOW, &old);

			if(flags & ConsoleInputFlags.size) {
				// restoration
				sigaction(SIGWINCH, &oldSigWinch, null);
			}
			sigaction(SIGINT, &oldSigIntr, null);
			sigaction(SIGHUP, &oldHupIntr, null);
			sigaction(SIGCONT, &oldContIntr, null);
		}

		skip_extra:

		// we're just undoing everything the constructor did, in reverse order, same criteria
		foreach_reverse(d; destructor)
			d(&this);
	}

	/**
		Returns true if there iff getch() would not block.

		WARNING: kbhit might consume input that would be ignored by getch. This
		function is really only meant to be used in conjunction with getch. Typically,
		you should use a full-fledged event loop if you want all kinds of input. kbhit+getch
		are just for simple keyboard driven applications.

		See_Also: [KeyboardEvent], [KeyboardEvent.Key], [kbhit]
	*/
	bool kbhit() {
		auto got = getch(true);

		if(got == dchar.init)
			return false;

		getchBuffer = got;
		return true;
	}

	/// Check for input, waiting no longer than the number of milliseconds. Note that this doesn't necessarily mean [getch] will not block, use this AND [kbhit] for that case.
	bool timedCheckForInput(int milliseconds) {
		if(inputQueue.length || timedCheckForInput_bypassingBuffer(milliseconds))
			return true;
		version(WithEncapsulatedSignals)
			if(terminal.interrupted || terminal.windowSizeChanged || terminal.hangedUp)
				return true;
		version(WithSignals)
			if(interrupted || windowSizeChanged || hangedUp)
				return true;
		return false;
	}

	/* private */ bool anyInput_internal(int timeout = 0) {
		return timedCheckForInput(timeout);
	}

	bool timedCheckForInput_bypassingBuffer(int milliseconds) {
		version(TerminalDirectToEmulator) {
			if(!terminal.usingDirectEmulator)
				return timedCheckForInput_bypassingBuffer_impl(milliseconds);

			import core.time;
			if(terminal.tew.terminalEmulator.pendingForApplication.length)
				return true;
			if(windowGone) forceTermination();
			if(terminal.tew.terminalEmulator.outgoingSignal.wait(milliseconds.msecs))
				// it was notified, but it could be left over from stuff we
				// already processed... so gonna check the blocking conditions here too
				// (FIXME: this sucks and is surely a race condition of pain)
				return terminal.tew.terminalEmulator.pendingForApplication.length || terminal.interrupted || terminal.windowSizeChanged || terminal.hangedUp;
			else
				return false;
		} else
			return timedCheckForInput_bypassingBuffer_impl(milliseconds);
	}

	private bool timedCheckForInput_bypassingBuffer_impl(int milliseconds) {
		version(Windows) {
			auto response = WaitForSingleObject(inputHandle, milliseconds);
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
			int tries = 0;
			try_again:
			auto ret = select(fdIn + 1, &fs, null, null, &tv);
			if(ret == -1) {
				import core.stdc.errno;
				if(errno == EINTR) {
					tries++;
					if(tries < 3)
						goto try_again;
				}
				return false;
			}
			if(ret == 0)
				return false;

			return FD_ISSET(fdIn, &fs);
		}
	}

	private dchar getchBuffer;

	/// Get one key press from the terminal, discarding other
	/// events in the process. Returns dchar.init upon receiving end-of-file.
	///
	/// Be aware that this may return non-character key events, like F1, F2, arrow keys, etc., as private use Unicode characters. Check them against KeyboardEvent.Key if you like.
	dchar getch(bool nonblocking = false) {
		if(getchBuffer != dchar.init) {
			auto a = getchBuffer;
			getchBuffer = dchar.init;
			return a;
		}

		if(nonblocking && !anyInput_internal())
			return dchar.init;

		auto event = nextEvent();
		while(event.type != InputEvent.Type.KeyboardEvent || event.keyboardEvent.pressed == false) {
			if(event.type == InputEvent.Type.UserInterruptionEvent)
				throw new UserInterruptionException();
			if(event.type == InputEvent.Type.HangupEvent)
				throw new HangupException();
			if(event.type == InputEvent.Type.EndOfFileEvent)
				return dchar.init;

			if(nonblocking && !anyInput_internal())
				return dchar.init;

			event = nextEvent();
		}
		return event.keyboardEvent.which;
	}

	//char[128] inputBuffer;
	//int inputBufferPosition;
	int nextRaw(bool interruptable = false) {
		version(TerminalDirectToEmulator) {
			if(!terminal.usingDirectEmulator)
				return nextRaw_impl(interruptable);
			moar:
			//if(interruptable && inputQueue.length)
				//return -1;
			if(terminal.tew.terminalEmulator.pendingForApplication.length == 0) {
				if(windowGone) forceTermination();
				terminal.tew.terminalEmulator.outgoingSignal.wait();
			}
			synchronized(terminal.tew.terminalEmulator) {
				if(terminal.tew.terminalEmulator.pendingForApplication.length == 0) {
					if(interruptable)
						return -1;
					else
						goto moar;
				}
				auto a = terminal.tew.terminalEmulator.pendingForApplication[0];
				terminal.tew.terminalEmulator.pendingForApplication = terminal.tew.terminalEmulator.pendingForApplication[1 .. $];
				return a;
			}
		} else {
			auto got = nextRaw_impl(interruptable);
			if(got == int.min && !interruptable)
				throw new Exception("eof found in non-interruptable context");
			// import std.stdio; writeln(cast(int) got);
			return got;
		}
	}
	private int nextRaw_impl(bool interruptable = false) {
		version(Posix) {
			if(fdIn == -1)
				return 0;

			char[1] buf;
			try_again:
			auto ret = read(fdIn, buf.ptr, buf.length);
			if(ret == 0)
				return int.min; // input closed
			if(ret == -1) {
				import core.stdc.errno;
				if(errno == EINTR) {
					// interrupted by signal call, quite possibly resize or ctrl+c which we want to check for in the event loop
					if(interruptable)
						return -1;
					else
						goto try_again;
				} else if(errno == EAGAIN || errno == EWOULDBLOCK) {
					// I turn off O_NONBLOCK explicitly in setup unless in a schedulable task, but
					// still just in case, let's keep this working too

					if(auto controls = arsd.core.inSchedulableTask) {
						controls.yieldUntilReadable(fdIn);
						goto try_again;
					} else {
						import core.thread;
						Thread.sleep(1.msecs);
						goto try_again;
					}
				} else {
					import std.conv;
					throw new Exception("read failed " ~ to!string(errno));
				}
			}

			//terminal.writef("RAW READ: %d\n", buf[0]);

			if(ret == 1)
				return inputPrefilter ? inputPrefilter(buf[0]) : buf[0];
			else
				assert(0); // read too much, should be impossible
		} else version(Windows) {
			char[1] buf;
			DWORD d;
			import std.conv;
			if(!ReadFile(inputHandle, buf.ptr, cast(int) buf.length, &d, null))
				throw new Exception("ReadFile " ~ to!string(GetLastError()));
			if(d == 0)
				return int.min;
			return buf[0];
		}
	}

	version(Posix)
		int delegate(char) inputPrefilter;

	// for VT
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
		version(WithSignals)
			windowSizeChanged = false;
		version(WithEncapsulatedSignals)
			terminal.windowSizeChanged = false;
		return InputEvent(SizeChangedEvent(oldWidth, oldHeight, terminal.width, terminal.height), terminal);
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

		wait_for_more:
		version(WithSignals) {
			if(interrupted) {
				interrupted = false;
				return InputEvent(UserInterruptionEvent(), terminal);
			}

			if(hangedUp) {
				hangedUp = false;
				return InputEvent(HangupEvent(), terminal);
			}

			if(windowSizeChanged) {
				return checkWindowSizeChanged();
			}

			if(continuedFromSuspend) {
				continuedFromSuspend = false;
				if(reinitializeAfterSuspend())
					return checkWindowSizeChanged(); // while it was suspended it is possible the window got resized, so we'll check that, and sending this event also triggers a redraw on most programs too which is also convenient for getting them caught back up to the screen
				else
					goto wait_for_more;
			}
		}

		version(WithEncapsulatedSignals) {
			if(terminal.interrupted) {
				terminal.interrupted = false;
				return InputEvent(UserInterruptionEvent(), terminal);
			}

			if(terminal.hangedUp) {
				terminal.hangedUp = false;
				return InputEvent(HangupEvent(), terminal);
			}

			if(terminal.windowSizeChanged) {
				return checkWindowSizeChanged();
			}
		}

		mutex.lock();
		if(inputQueue.length) {
			auto e = inputQueue[0];
			inputQueue = inputQueue[1 .. $];
			mutex.unlock();
			return e;
		}
		mutex.unlock();

		auto more = readNextEvents();
		if(!more.length)
			goto wait_for_more; // i used to do a loop (readNextEvents can read something, but it might be discarded by the input filter) but now it goto's above because readNextEvents might be interrupted by a SIGWINCH aka size event so we want to check that at least

		assert(more.length);

		auto e = more[0];
		mutex.lock(); scope(exit) mutex.unlock();
		inputQueue = more[1 .. $];
		return e;
	}

	InputEvent* peekNextEvent() {
		mutex.lock(); scope(exit) mutex.unlock();
		if(inputQueue.length)
			return &(inputQueue[0]);
		return null;
	}


	import core.sync.mutex;
	private shared(Mutex) mutex;

	private void createLock() {
		if(mutex is null)
			mutex = new shared Mutex;
	}
	enum InjectionPosition { head, tail }

	/++
		Injects a custom event into the terminal input queue.

		History:
			`shared` overload added November 24, 2021 (dub v10.4)
		Bugs:
			Unless using `TerminalDirectToEmulator`, this will not wake up the
			event loop if it is already blocking until normal terminal input
			arrives anyway, then the event will be processed before the new event.

			I might change this later.
	+/
	void injectEvent(CustomEvent ce) shared {
		(cast() this).injectEvent(InputEvent(ce, cast(Terminal*) terminal), InjectionPosition.tail);

		version(TerminalDirectToEmulator) {
			if(terminal.usingDirectEmulator) {
				(cast(Terminal*) terminal).tew.terminalEmulator.outgoingSignal.notify();
				return;
			}
		}
		// FIXME: for the others, i might need to wake up the WaitForSingleObject or select calls.
	}

	void injectEvent(InputEvent ev, InjectionPosition where) {
		mutex.lock(); scope(exit) mutex.unlock();
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

	InputEvent[] readNextEvents() {
		if(UseVtSequences)
			return readNextEventsVt();
		else version(Win32Console)
			return readNextEventsWin32();
		else
			assert(0);
	}

	version(Win32Console)
	InputEvent[] readNextEventsWin32() {
		terminal.flush(); // make sure all output is sent out before waiting for anything

		INPUT_RECORD[32] buffer;
		DWORD actuallyRead;

		if(auto controls = arsd.core.inSchedulableTask) {
			if(PeekConsoleInputW(inputHandle, buffer.ptr, 1, &actuallyRead) == 0)
				throw new Exception("PeekConsoleInputW");

			if(actuallyRead == 0) {
				// the next call would block, we need to wait on the handle
				controls.yieldUntilSignaled(inputHandle);
			}
		}

		if(ReadConsoleInputW(inputHandle, buffer.ptr, buffer.length, &actuallyRead) == 0) {
		//import std.stdio; writeln(buffer[0 .. actuallyRead][0].KeyEvent, cast(int) buffer[0].KeyEvent.UnicodeChar);
			throw new Exception("ReadConsoleInput");
		}

		InputEvent[] newEvents;
		input_loop: foreach(record; buffer[0 .. actuallyRead]) {
			switch(record.EventType) {
				case KEY_EVENT:
					auto ev = record.KeyEvent;
					KeyboardEvent ke;
					CharacterEvent e;
					NonCharacterKeyEvent ne;

					ke.pressed = ev.bKeyDown ? true : false;

					// only send released events when specifically requested
					// terminal.writefln("got %s %s", ev.UnicodeChar, ev.bKeyDown);
					if(ev.UnicodeChar && ev.wVirtualKeyCode == VK_MENU && ev.bKeyDown == 0) {
						// this indicates Windows is actually sending us
						// an alt+xxx key sequence, may also be a unicode paste.
						// either way, it cool.
						ke.pressed = true;
					} else {
						if(!(flags & ConsoleInputFlags.releasedKeys) && !ev.bKeyDown)
							break;
					}

					if(ev.UnicodeChar == 0 && ev.wVirtualKeyCode == VK_SPACE && ev.bKeyDown == 1) {
						ke.which = 0;
						ke.modifierState = ev.dwControlKeyState;
						newEvents ~= InputEvent(ke, terminal);
						continue;
					}

					e.eventType = ke.pressed ? CharacterEvent.Type.Pressed : CharacterEvent.Type.Released;
					ne.eventType = ke.pressed ? NonCharacterKeyEvent.Type.Pressed : NonCharacterKeyEvent.Type.Released;

					e.modifierState = ev.dwControlKeyState;
					ne.modifierState = ev.dwControlKeyState;
					ke.modifierState = ev.dwControlKeyState;

					if(ev.UnicodeChar) {
						// new style event goes first

						if(ev.UnicodeChar == 3) {
							// handling this internally for linux compat too
							newEvents ~= InputEvent(UserInterruptionEvent(), terminal);
						} else if(ev.UnicodeChar == '\r') {
							// translating \r to \n for same result as linux...
							ke.which = cast(dchar) cast(wchar) '\n';
							newEvents ~= InputEvent(ke, terminal);

							// old style event then follows as the fallback
							e.character = cast(dchar) cast(wchar) '\n';
							newEvents ~= InputEvent(e, terminal);
						} else if(ev.wVirtualKeyCode == 0x1b) {
							ke.which = cast(KeyboardEvent.Key) (ev.wVirtualKeyCode + 0xF0000);
							newEvents ~= InputEvent(ke, terminal);

							ne.key = cast(NonCharacterKeyEvent.Key) ev.wVirtualKeyCode;
							newEvents ~= InputEvent(ne, terminal);
						} else {
							ke.which = cast(dchar) cast(wchar) ev.UnicodeChar;
							newEvents ~= InputEvent(ke, terminal);

							// old style event then follows as the fallback
							e.character = cast(dchar) cast(wchar) ev.UnicodeChar;
							newEvents ~= InputEvent(e, terminal);
						}
					} else {
						// old style event
						ne.key = cast(NonCharacterKeyEvent.Key) ev.wVirtualKeyCode;

						// new style event. See comment on KeyboardEvent.Key
						ke.which = cast(KeyboardEvent.Key) (ev.wVirtualKeyCode + 0xF0000);

						// FIXME: make this better. the goal is to make sure the key code is a valid enum member
						// Windows sends more keys than Unix and we're doing lowest common denominator here
						foreach(member; __traits(allMembers, NonCharacterKeyEvent.Key))
							if(__traits(getMember, NonCharacterKeyEvent.Key, member) == ne.key) {
								newEvents ~= InputEvent(ke, terminal);
								newEvents ~= InputEvent(ne, terminal);
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

					newEvents ~= InputEvent(e, terminal);
				break;
				case WINDOW_BUFFER_SIZE_EVENT:
					auto ev = record.WindowBufferSizeEvent;
					auto oldWidth = terminal.width;
					auto oldHeight = terminal.height;
					terminal._width = ev.dwSize.X;
					terminal._height = ev.dwSize.Y;
					newEvents ~= InputEvent(SizeChangedEvent(oldWidth, oldHeight, terminal.width, terminal.height), terminal);
				break;
				// FIXME: can we catch ctrl+c here too?
				default:
					// ignore
			}
		}

		return newEvents;
	}

	// for UseVtSequences....
	InputEvent[] readNextEventsVt() {
		terminal.flush(); // make sure all output is sent out before we try to get input

		// we want to starve the read, especially if we're called from an edge-triggered
		// epoll (which might happen in version=with_eventloop.. impl detail there subject
		// to change).
		auto initial = readNextEventsHelper();

		// lol this calls select() inside a function prolly called from epoll but meh,
		// it is the simplest thing that can possibly work. The alternative would be
		// doing non-blocking reads and buffering in the nextRaw function (not a bad idea
		// btw, just a bit more of a hassle).
		while(timedCheckForInput_bypassingBuffer(0)) {
			auto ne = readNextEventsHelper();
			initial ~= ne;
			foreach(n; ne)
				if(n.type == InputEvent.Type.EndOfFileEvent || n.type == InputEvent.Type.HangupEvent)
					return initial; // hit end of file, get out of here lest we infinite loop
					// (select still returns info available even after we read end of file)
		}
		return initial;
	}

	// The helper reads just one actual event from the pipe...
	// for UseVtSequences....
	InputEvent[] readNextEventsHelper(int remainingFromLastTime = int.max) {
		bool maybeTranslateCtrl(ref dchar c) {
			import std.algorithm : canFind;
			// map anything in the range of [1, 31] to C-lowercase character
			// except backspace (^h), tab (^i), linefeed (^j), carriage return (^m), and esc (^[)
			// \a, \v (lol), and \f are also 'special', but not worthwhile to special-case here
			if(1 <= c && c <= 31
			   && !"\b\t\n\r\x1b"d.canFind(c))
			{
				// I'm versioning this out because it is a breaking change. Maybe can come back to it later.
				version(terminal_translate_ctl) {
					c += 'a' - 1;
				}
				return true;
			}
			return false;
		}
		InputEvent[] charPressAndRelease(dchar character, uint modifiers = 0) {
			if(maybeTranslateCtrl(character))
				modifiers |= ModifierState.control;
			if((flags & ConsoleInputFlags.releasedKeys))
				return [
					// new style event
					InputEvent(KeyboardEvent(true, character, modifiers), terminal),
					InputEvent(KeyboardEvent(false, character, modifiers), terminal),
					// old style event
					InputEvent(CharacterEvent(CharacterEvent.Type.Pressed, character, modifiers), terminal),
					InputEvent(CharacterEvent(CharacterEvent.Type.Released, character, modifiers), terminal),
				];
			else return [
				// new style event
				InputEvent(KeyboardEvent(true, character, modifiers), terminal),
				// old style event
				InputEvent(CharacterEvent(CharacterEvent.Type.Pressed, character, modifiers), terminal)
			];
		}
		InputEvent[] keyPressAndRelease(NonCharacterKeyEvent.Key key, uint modifiers = 0) {
			if((flags & ConsoleInputFlags.releasedKeys))
				return [
					// new style event FIXME: when the old events are removed, kill the +0xF0000 from here!
					InputEvent(KeyboardEvent(true, cast(dchar)(key) + 0xF0000, modifiers), terminal),
					InputEvent(KeyboardEvent(false, cast(dchar)(key) + 0xF0000, modifiers), terminal),
					// old style event
					InputEvent(NonCharacterKeyEvent(NonCharacterKeyEvent.Type.Pressed, key, modifiers), terminal),
					InputEvent(NonCharacterKeyEvent(NonCharacterKeyEvent.Type.Released, key, modifiers), terminal),
				];
			else return [
				// new style event FIXME: when the old events are removed, kill the +0xF0000 from here!
				InputEvent(KeyboardEvent(true, cast(dchar)(key) + 0xF0000, modifiers), terminal),
				// old style event
				InputEvent(NonCharacterKeyEvent(NonCharacterKeyEvent.Type.Pressed, key, modifiers), terminal)
			];
		}

		InputEvent[] keyPressAndRelease2(dchar c, uint modifiers = 0) {
			if((flags & ConsoleInputFlags.releasedKeys))
				return [
					InputEvent(KeyboardEvent(true, c, modifiers), terminal),
					InputEvent(KeyboardEvent(false, c, modifiers), terminal),
					// old style event
					InputEvent(CharacterEvent(CharacterEvent.Type.Pressed, c, modifiers), terminal),
					InputEvent(CharacterEvent(CharacterEvent.Type.Released, c, modifiers), terminal),
				];
			else return [
				InputEvent(KeyboardEvent(true, c, modifiers), terminal),
				// old style event
				InputEvent(CharacterEvent(CharacterEvent.Type.Pressed, c, modifiers), terminal)
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

				case "ho": // this might not be a key but my thing sometimes returns it... weird...
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
					//terminal.writeln(cap);
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
					return [InputEvent(PasteEvent(data), terminal)];
				case "\033[220~":
					// bracketed hyperlink begin (arsd extension)

					string data;
					for(;;) {
						auto n = nextRaw();
						if(n == '\033') {
							n = nextRaw();
							if(n == '[') {
								auto esc = readEscapeSequence(sequenceBuffer);
								if(esc == "\033[221~") {
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

					import std.string, std.conv;
					auto idx = data.indexOf(";");
					auto id = data[0 .. idx].to!ushort;
					data = data[idx + 1 .. $];
					idx = data.indexOf(";");
					auto cmd = data[0 .. idx].to!ushort;
					data = data[idx + 1 .. $];

					return [InputEvent(LinkEvent(data, id, cmd), terminal)];
				case "\033[M":
					// mouse event
					auto buttonCode = nextRaw() - 32;
						// nextChar is commented because i'm not using UTF-8 mouse mode
						// cuz i don't think it is as widely supported
					int x;
					int y;

					if(utf8MouseMode) {
						x = cast(int) nextChar(nextRaw()) - 33; /* they encode value + 32, but make upper left 1,1. I want it to be 0,0 */
						y = cast(int) nextChar(nextRaw()) - 33; /* ditto */
					} else {
						x = cast(int) (/*nextChar*/(nextRaw())) - 33; /* they encode value + 32, but make upper left 1,1. I want it to be 0,0 */
						y = cast(int) (/*nextChar*/(nextRaw())) - 33; /* ditto */
					}


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

					return [InputEvent(m, terminal)];
				default:
					// screen doesn't actually do the modifiers, but
					// it uses the same format so this branch still works fine.
					if(terminal.terminalInFamily("xterm", "screen", "tmux")) {
						import std.conv, std.string;
						auto terminator = sequence[$ - 1];
						auto parts = sequence[2 .. $ - 1].split(";");
						// parts[0] and terminator tells us the key
						// parts[1] tells us the modifierState

						uint modifierState;

						int keyGot;

						int modGot;
						if(parts.length > 1)
							modGot = to!int(parts[1]);
						if(parts.length > 2)
							keyGot = to!int(parts[2]);
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
									case "1": return keyPressAndRelease(NonCharacterKeyEvent.Key.Home, modifierState);
									case "4": return keyPressAndRelease(NonCharacterKeyEvent.Key.End, modifierState);
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

									// xterm extension for arbitrary keys with arbitrary modifiers
									case "27": return keyPressAndRelease2(keyGot == '\x1b' ? KeyboardEvent.Key.escape : keyGot, modifierState);

									// starting at 70  im free to do my own but i rolled all but ScrollLock into 27 as of Dec 3, 2020
									case "70": return keyPressAndRelease(NonCharacterKeyEvent.Key.ScrollLock, modifierState);
									default:
								}
							break;

							default:
						}
					} else if(terminal.terminalInFamily("rxvt")) {
						// look it up in the termcap key database
						string cap = terminal.findSequenceInTermcap(sequence);
						if(cap !is null) {
						//terminal.writeln("found in termcap " ~ cap);
							return translateTermcapName(cap);
						}
						// FIXME: figure these out. rxvt seems to just change the terminator while keeping the rest the same
						// though it isn't consistent. ugh.
					} else {
						// maybe we could do more terminals, but linux doesn't even send it and screen just seems to pass through, so i don't think so; xterm prolly covers most them anyway
						// so this space is semi-intentionally left blank
						//terminal.writeln("wtf ", sequence[1..$]);

						// look it up in the termcap key database
						string cap = terminal.findSequenceInTermcap(sequence);
						if(cap !is null) {
						//terminal.writeln("found in termcap " ~ cap);
							return translateTermcapName(cap);
						}
					}
			}

			return null;
		}

		auto c = remainingFromLastTime == int.max ? nextRaw(true) : remainingFromLastTime;
		if(c == -1)
			return null; // interrupted; give back nothing so the other level can recheck signal flags
		// 0 conflicted with ctrl+space, so I have to use int.min to indicate eof
		if(c == int.min)
			return [InputEvent(EndOfFileEvent(), terminal)];
		if(c == '\033') {
			if(!timedCheckForInput_bypassingBuffer(50)) {
				// user hit escape (or super slow escape sequence, but meh)
				return keyPressAndRelease(NonCharacterKeyEvent.Key.escape);
			}
			// escape sequence
			c = nextRaw();
			if(c == '[' || c == 'O') { // CSI, ends on anything >= 'A'
				return doEscapeSequence(readEscapeSequence(sequenceBuffer));
			} else if(c == '\033') {
				// could be escape followed by an escape sequence!
				return keyPressAndRelease(NonCharacterKeyEvent.Key.escape) ~ readNextEventsHelper(c);
			} else {
				// exceedingly quick esc followed by char is also what many terminals do for alt
				return charPressAndRelease(nextChar(c), cast(uint)ModifierState.alt);
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

/++
	The new style of keyboard event

	Worth noting some special cases terminals tend to do:

	$(LIST
		* Ctrl+space bar sends char 0.
		* Ctrl+ascii characters send char 1 - 26 as chars on all systems. Ctrl+shift+ascii is generally not recognizable on Linux, but works on Windows and with my terminal emulator on all systems. Alt+ctrl+ascii, for example Alt+Ctrl+F, is sometimes sent as modifierState = alt|ctrl, key = 'f'. Sometimes modifierState = alt|ctrl, key = 'F'. Sometimes modifierState = ctrl|alt, key = 6. Which one you get depends on the system/terminal and the user's caps lock state. You're probably best off checking all three and being aware it might not work at all.
		* Some combinations like ctrl+i are indistinguishable from other keys like tab.
		* Other modifier+key combinations may send random other things or not be detected as it is configuration-specific with no way to detect. It is reasonably reliable for the non-character keys (arrows, F1-F12, Home/End, etc.) but not perfectly so. Some systems just don't send them. If they do though, terminal will try to set `modifierState`.
		* Alt+key combinations do not generally work on Windows since the operating system uses that combination for something else. The events may come to you, but it may also go to the window menu or some other operation too. In fact, it might do both!
		* Shift is sometimes applied to the character, sometimes set in modifierState, sometimes both, sometimes neither.
		* On some systems, the return key sends \r and some sends \n.
	)
+/
struct KeyboardEvent {
	bool pressed; ///
	dchar which; ///
	alias key = which; /// I often use this when porting old to new so i took it
	alias character = which; /// I often use this when porting old to new so i took it
	uint modifierState; ///

	// filter irrelevant modifiers...
	uint modifierStateFiltered() const {
		uint ms = modifierState;
		if(which < 32 && which != 9 && which != 8 && which != '\n')
			ms &= ~ModifierState.control;
		return ms;
	}

	/++
		Returns true if the event was a normal typed character.

		You may also want to check modifiers if you want to process things differently when alt, ctrl, or shift is pressed.
		[modifierStateFiltered] returns only modifiers that are special in some way for the typed character. You can bitwise
		and that against [ModifierState]'s members to test.

		[isUnmodifiedCharacter] does such a check for you.

		$(NOTE
			Please note that enter, tab, and backspace count as characters.
		)
	+/
	bool isCharacter() {
		return !isNonCharacterKey() && !isProprietary();
	}

	/++
		Returns true if this keyboard event represents a normal character keystroke, with no extraordinary modifier keys depressed.

		Shift is considered an ordinary modifier except in the cases of tab, backspace, enter, and the space bar, since it is a normal
		part of entering many other characters.

		History:
			Added December 4, 2020.
	+/
	bool isUnmodifiedCharacter() {
		uint modsInclude = ModifierState.control | ModifierState.alt | ModifierState.meta;
		if(which == '\b' || which == '\t' || which == '\n' || which == '\r' || which == ' ' || which == 0)
			modsInclude |= ModifierState.shift;
		return isCharacter() && (modifierStateFiltered() & modsInclude) == 0;
	}

	/++
		Returns true if the key represents one of the range named entries in the [Key] enum.
		This does not necessarily mean it IS one of the named entries, just that it is in the
		range. Checking more precisely would require a loop in here and you are better off doing
		that in your own `switch` statement, with a do-nothing `default`.

		Remember that users can create synthetic input of any character value.

		History:
			While this function was present before, it was undocumented until December 4, 2020.
	+/
	bool isNonCharacterKey() {
		return which >= Key.min && which <= Key.max;
	}

	///
	bool isProprietary() {
		return which >= ProprietaryPseudoKeys.min && which <= ProprietaryPseudoKeys.max;
	}

	// these match Windows virtual key codes numerically for simplicity of translation there
	// but are plus a unicode private use area offset so i can cram them in the dchar
	// http://msdn.microsoft.com/en-us/library/windows/desktop/dd375731%28v=vs.85%29.aspx
	/++
		Represents non-character keys.
	+/
	enum Key : dchar {
		escape = 0x1b + 0xF0000, /// .
		F1 = 0x70 + 0xF0000, /// .
		F2 = 0x71 + 0xF0000, /// .
		F3 = 0x72 + 0xF0000, /// .
		F4 = 0x73 + 0xF0000, /// .
		F5 = 0x74 + 0xF0000, /// .
		F6 = 0x75 + 0xF0000, /// .
		F7 = 0x76 + 0xF0000, /// .
		F8 = 0x77 + 0xF0000, /// .
		F9 = 0x78 + 0xF0000, /// .
		F10 = 0x79 + 0xF0000, /// .
		F11 = 0x7A + 0xF0000, /// .
		F12 = 0x7B + 0xF0000, /// .
		LeftArrow = 0x25 + 0xF0000, /// .
		RightArrow = 0x27 + 0xF0000, /// .
		UpArrow = 0x26 + 0xF0000, /// .
		DownArrow = 0x28 + 0xF0000, /// .
		Insert = 0x2d + 0xF0000, /// .
		Delete = 0x2e + 0xF0000, /// .
		Home = 0x24 + 0xF0000, /// .
		End = 0x23 + 0xF0000, /// .
		PageUp = 0x21 + 0xF0000, /// .
		PageDown = 0x22 + 0xF0000, /// .
		ScrollLock = 0x91 + 0xF0000, /// unlikely to work outside my custom terminal emulator

		/*
		Enter = '\n',
		Backspace = '\b',
		Tab = '\t',
		*/
	}

	/++
		These are extensions added for better interop with the embedded emulator.
		As characters inside the unicode private-use area, you shouldn't encounter
		them unless you opt in by using some other proprietary feature.

		History:
			Added December 4, 2020.
	+/
	enum ProprietaryPseudoKeys : dchar {
		/++
			If you use [Terminal.requestSetTerminalSelection], you should also process
			this pseudo-key to clear the selection when the terminal tells you do to keep
			you UI in sync.

			History:
				Added December 4, 2020.
		+/
		SelectNone = 0x0 + 0xF1000, // 987136
	}
}

/// Deprecated: use KeyboardEvent instead in new programs
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

/// Deprecated: use KeyboardEvent instead in new programs
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
		ScrollLock = 0x91, /// unlikely to work outside my terminal emulator
		}
	Key key; /// .

	uint modifierState; /// A mask of ModifierState. Always use by checking modifierState & ModifierState.something, the actual value differs across platforms

}

/// .
struct PasteEvent {
	string pastedText; /// .
}

/++
	Indicates a hyperlink was clicked in my custom terminal emulator
	or with version `TerminalDirectToEmulator`.

	You can simply ignore this event in a `final switch` if you aren't
	using the feature.

	History:
		Added March 18, 2020
+/
struct LinkEvent {
	string text; /// the text visible to the user that they clicked on
	ushort identifier; /// the identifier set when you output the link. This is small because it is packed into extra bits on the text, one bit per character.
	ushort command; /// set by the terminal to indicate how it was clicked. values tbd, currently always 0
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

/// When you get this, check terminal.width and terminal.height to see the new size and react accordingly.
struct SizeChangedEvent {
	int oldWidth;
	int oldHeight;
	int newWidth;
	int newHeight;
}

/// the user hitting ctrl+c will send this
/// You should drop what you're doing and perhaps exit when this happens.
struct UserInterruptionEvent {}

/// If the user hangs up (for example, closes the terminal emulator without exiting the app), this is sent.
/// If you receive it, you should generally cleanly exit.
struct HangupEvent {}

/// Sent upon receiving end-of-file from stdin.
struct EndOfFileEvent {}

interface CustomEvent {}

class RunnableCustomEvent : CustomEvent {
	this(void delegate() dg) {
		this.dg = dg;
	}

	void run() {
		if(dg)
			dg();
	}

	private void delegate() dg;
}

version(Win32Console)
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

version(DDoc)
///
enum ModifierState : uint {
	///
	shift = 4,
	///
	alt = 2,
	///
	control = 16,

}

/++
	[RealTimeConsoleInput.nextEvent] returns one of these. Check the type, then use the [InputEvent.get|get] method to get the more detailed information about the event.
++/
struct InputEvent {
	/// .
	enum Type {
		KeyboardEvent, /// Keyboard key pressed (or released, where supported)
		CharacterEvent, /// Do not use this in new programs, use KeyboardEvent instead
		NonCharacterKeyEvent, /// Do not use this in new programs, use KeyboardEvent instead
		PasteEvent, /// The user pasted some text. Not always available, the pasted text might come as a series of character events instead.
		LinkEvent, /// User clicked a hyperlink you created. Simply ignore if you are not using that feature.
		MouseEvent, /// only sent if you subscribed to mouse events
		SizeChangedEvent, /// only sent if you subscribed to size events
		UserInterruptionEvent, /// the user hit ctrl+c
		EndOfFileEvent, /// stdin has received an end of file
		HangupEvent, /// the terminal hanged up - for example, if the user closed a terminal emulator
		CustomEvent /// .
	}

	/// If this event is deprecated, you should filter it out in new programs
	bool isDeprecated() {
		return type == Type.CharacterEvent || type == Type.NonCharacterKeyEvent;
	}

	/// .
	@property Type type() { return t; }

	/// Returns a pointer to the terminal associated with this event.
	/// (You can usually just ignore this as there's only one terminal typically.)
	///
	/// It may be null in the case of program-generated events;
	@property Terminal* terminal() { return term; }

	/++
		Gets the specific event instance. First, check the type (such as in a `switch` statement), then extract the correct one from here. Note that the template argument is a $(B value type of the enum above), not a type argument. So to use it, do $(D event.get!(InputEvent.Type.KeyboardEvent)), for example.

		See_Also:

		The event types:
			[KeyboardEvent], [MouseEvent], [SizeChangedEvent],
			[PasteEvent], [UserInterruptionEvent],
			[EndOfFileEvent], [HangupEvent], [CustomEvent]

		And associated functions:
			[RealTimeConsoleInput], [ConsoleInputFlags]
	++/
	@property auto get(Type T)() {
		if(type != T)
			throw new Exception("Wrong event type");
		static if(T == Type.CharacterEvent)
			return characterEvent;
		else static if(T == Type.KeyboardEvent)
			return keyboardEvent;
		else static if(T == Type.NonCharacterKeyEvent)
			return nonCharacterKeyEvent;
		else static if(T == Type.PasteEvent)
			return pasteEvent;
		else static if(T == Type.LinkEvent)
			return linkEvent;
		else static if(T == Type.MouseEvent)
			return mouseEvent;
		else static if(T == Type.SizeChangedEvent)
			return sizeChangedEvent;
		else static if(T == Type.UserInterruptionEvent)
			return userInterruptionEvent;
		else static if(T == Type.EndOfFileEvent)
			return endOfFileEvent;
		else static if(T == Type.HangupEvent)
			return hangupEvent;
		else static if(T == Type.CustomEvent)
			return customEvent;
		else static assert(0, "Type " ~ T.stringof ~ " not added to the get function");
	}

	/// custom event is public because otherwise there's no point at all
	this(CustomEvent c, Terminal* p = null) {
		t = Type.CustomEvent;
		customEvent = c;
	}

	private {
		this(CharacterEvent c, Terminal* p) {
			t = Type.CharacterEvent;
			characterEvent = c;
		}
		this(KeyboardEvent c, Terminal* p) {
			t = Type.KeyboardEvent;
			keyboardEvent = c;
		}
		this(NonCharacterKeyEvent c, Terminal* p) {
			t = Type.NonCharacterKeyEvent;
			nonCharacterKeyEvent = c;
		}
		this(PasteEvent c, Terminal* p) {
			t = Type.PasteEvent;
			pasteEvent = c;
		}
		this(LinkEvent c, Terminal* p) {
			t = Type.LinkEvent;
			linkEvent = c;
		}
		this(MouseEvent c, Terminal* p) {
			t = Type.MouseEvent;
			mouseEvent = c;
		}
		this(SizeChangedEvent c, Terminal* p) {
			t = Type.SizeChangedEvent;
			sizeChangedEvent = c;
		}
		this(UserInterruptionEvent c, Terminal* p) {
			t = Type.UserInterruptionEvent;
			userInterruptionEvent = c;
		}
		this(HangupEvent c, Terminal* p) {
			t = Type.HangupEvent;
			hangupEvent = c;
		}
		this(EndOfFileEvent c, Terminal* p) {
			t = Type.EndOfFileEvent;
			endOfFileEvent = c;
		}

		Type t;
		Terminal* term;

		union {
			KeyboardEvent keyboardEvent;
			CharacterEvent characterEvent;
			NonCharacterKeyEvent nonCharacterKeyEvent;
			PasteEvent pasteEvent;
			MouseEvent mouseEvent;
			SizeChangedEvent sizeChangedEvent;
			UserInterruptionEvent userInterruptionEvent;
			HangupEvent hangupEvent;
			EndOfFileEvent endOfFileEvent;
			LinkEvent linkEvent;
			CustomEvent customEvent;
		}
	}
}

version(Demo)
/// View the source of this!
void main() {
	auto terminal = Terminal(ConsoleOutputType.cellular);

	//terminal.color(Color.DEFAULT, Color.DEFAULT);

	terminal.writeln(terminal.tcaps);

	//
	///*
	auto getter = new FileLineGetter(&terminal, "test");
	getter.prompt = "> ";
	//getter.history = ["abcdefghijklmnopqrstuvwzyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"];
	terminal.writeln("\n" ~ getter.getline());
	terminal.writeln("\n" ~ getter.getline());
	terminal.writeln("\n" ~ getter.getline());
	getter.dispose();
	//*/

	terminal.writeln(terminal.getline());
	terminal.writeln(terminal.getline());
	terminal.writeln(terminal.getline());

	//input.getch();

	// return;
	//

	terminal.setTitle("Basic I/O");
	auto input = RealTimeConsoleInput(&terminal, ConsoleInputFlags.raw | ConsoleInputFlags.allInputEventsWithRelease);
	terminal.color(Color.green | Bright, Color.black);

	terminal.write("test some long string to see if it wraps or what because i dont really know what it is going to do so i just want to test i think it will wrap but gotta be sure lolololololololol");
	terminal.writefln("%d %d", terminal.cursorX, terminal.cursorY);

	terminal.color(Color.DEFAULT, Color.DEFAULT);

	int centerX = terminal.width / 2;
	int centerY = terminal.height / 2;

	bool timeToBreak = false;

	terminal.hyperlink("test", 4);
	terminal.hyperlink("another", 7);

	void handleEvent(InputEvent event) {
		//terminal.writef("%s\n", event.type);
		final switch(event.type) {
			case InputEvent.Type.LinkEvent:
				auto ev = event.get!(InputEvent.Type.LinkEvent);
				terminal.writeln(ev);
			break;
			case InputEvent.Type.UserInterruptionEvent:
			case InputEvent.Type.HangupEvent:
			case InputEvent.Type.EndOfFileEvent:
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
			case InputEvent.Type.KeyboardEvent:
				auto ev = event.get!(InputEvent.Type.KeyboardEvent);
				if(!ev.pressed) break;
					terminal.writef("\t%s", ev);
				terminal.writef(" (%s)", cast(KeyboardEvent.Key) ev.which);
				terminal.writeln();
				if(ev.which == 'Q') {
					timeToBreak = true;
					version(with_eventloop) {
						import arsd.eventloop;
						exit();
					}
				}

				if(ev.which == 'C')
					terminal.clear();
			break;
			case InputEvent.Type.CharacterEvent: // obsolete
				auto ev = event.get!(InputEvent.Type.CharacterEvent);
				//terminal.writef("\t%s\n", ev);
			break;
			case InputEvent.Type.NonCharacterKeyEvent: // obsolete
				//terminal.writef("\t%s\n", event.get!(InputEvent.Type.NonCharacterKeyEvent));
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

		//terminal.writefln("%d %d", terminal.cursorX, terminal.cursorY);

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

enum TerminalCapabilities : uint {
	// the low byte is just a linear progression
	minimal = 0,
	vt100 = 1, // caps == 1, 2
	vt220 = 6, // initial 6 in caps. aka the linux console
	xterm = 64,

	// the rest of them are bitmasks

	// my special terminal emulator extensions
	arsdClipboard = 1 << 15, // 90 in caps
	arsdImage = 1 << 16, // 91 in caps
	arsdHyperlinks = 1 << 17, // 92 in caps
}

version(Posix)
private uint /* TerminalCapabilities bitmask */ getTerminalCapabilities(int fdIn, int fdOut) {
	if(fdIn == -1 || fdOut == -1)
		return TerminalCapabilities.minimal;
	if(!isatty(fdIn) || !isatty(fdOut))
		return TerminalCapabilities.minimal;

	import std.conv;
	import core.stdc.errno;
	import core.sys.posix.unistd;

	ubyte[128] hack2;
	termios old;
	ubyte[128] hack;
	tcgetattr(fdIn, &old);
	auto n = old;
	n.c_lflag &= ~(ICANON | ECHO);
	tcsetattr(fdIn, TCSANOW, &n);
	scope(exit)
		tcsetattr(fdIn, TCSANOW, &old);

	// drain the buffer? meh

	string cmd = "\033[c";
	auto err = write(fdOut, cmd.ptr, cmd.length);
	if(err != cmd.length) {
		throw new Exception("couldn't ask terminal for ID");
	}

	// reading directly to bypass any buffering
	int retries = 16;
	int len;
	ubyte[96] buffer;
	try_again:


	timeval tv;
	tv.tv_sec = 0;
	tv.tv_usec = 250 * 1000; // 250 ms

	fd_set fs;
	FD_ZERO(&fs);

	FD_SET(fdIn, &fs);
	if(select(fdIn + 1, &fs, null, null, &tv) == -1) {
		goto try_again;
	}

	if(FD_ISSET(fdIn, &fs)) {
		auto len2 = read(fdIn, &buffer[len], buffer.length - len);
		if(len2 <= 0) {
			retries--;
			if(retries > 0)
				goto try_again;
			throw new Exception("can't get terminal id");
		} else {
			len += len2;
		}
	} else {
		// no data... assume terminal doesn't support giving an answer
		return TerminalCapabilities.minimal;
	}

	ubyte[] answer;
	bool hasAnswer(ubyte[] data) {
		if(data.length < 4)
			return false;
		answer = null;
		size_t start;
		int position = 0;
		foreach(idx, ch; data) {
			switch(position) {
				case 0:
					if(ch == '\033') {
						start = idx;
						position++;
					}
				break;
				case 1:
					if(ch == '[')
						position++;
					else
						position = 0;
				break;
				case 2:
					if(ch == '?')
						position++;
					else
						position = 0;
				break;
				case 3:
					// body
					if(ch == 'c') {
						answer = data[start .. idx + 1];
						return true;
					} else if(ch == ';' || (ch >= '0' && ch <= '9')) {
						// good, keep going
					} else {
						// invalid, drop it
						position = 0;
					}
				break;
				default: assert(0);
			}
		}
		return false;
	}

	auto got = buffer[0 .. len];
	if(!hasAnswer(got)) {
		if(retries > 0)
			goto try_again;
		else
			return TerminalCapabilities.minimal;
	}
	auto gots = cast(char[]) answer[3 .. $-1];

	import std.string;

	// import std.stdio; File("tcaps.txt", "wt").writeln(gots);

	if(gots == "1;2") {
		return TerminalCapabilities.vt100;
	} else if(gots == "6") {
		return TerminalCapabilities.vt220;
	} else {
		auto pieces = split(gots, ";");
		uint ret = TerminalCapabilities.xterm;
		foreach(p; pieces) {
			switch(p) {
				case "90":
					ret |= TerminalCapabilities.arsdClipboard;
				break;
				case "91":
					ret |= TerminalCapabilities.arsdImage;
				break;
				case "92":
					ret |= TerminalCapabilities.arsdHyperlinks;
				break;
				default:
			}
		}
		return ret;
	}
}

private extern(C) int mkstemp(char *templ);

/*
	FIXME: support lines that wrap
	FIXME: better controls maybe

	FIXME: support multi-line "lines" and some form of line continuation, both
	       from the user (if permitted) and from the application, so like the user
	       hits "class foo { \n" and the app says "that line needs continuation" automatically.

	FIXME: fix lengths on prompt and suggestion
*/
/**
	A user-interactive line editor class, used by [Terminal.getline]. It is similar to
	GNU readline, offering comparable features like tab completion, history, and graceful
	degradation to adapt to the user's terminal.


	A note on history:

	$(WARNING
		To save history, you must call LineGetter.dispose() when you're done with it.
		History will not be automatically saved without that call!
	)

	The history saving and loading as a trivially encountered race condition: if you
	open two programs that use the same one at the same time, the one that closes second
	will overwrite any history changes the first closer saved.

	GNU Getline does this too... and it actually kinda drives me nuts. But I don't know
	what a good fix is except for doing a transactional commit straight to the file every
	time and that seems like hitting the disk way too often.

	We could also do like a history server like a database daemon that keeps the order
	correct but I don't actually like that either because I kinda like different bashes
	to have different history, I just don't like it all to get lost.

	Regardless though, this isn't even used in bash anyway, so I don't think I care enough
	to put that much effort into it. Just using separate files for separate tasks is good
	enough I think.
*/
class LineGetter {
	/* A note on the assumeSafeAppends in here: since these buffers are private, we can be
	   pretty sure that stomping isn't an issue, so I'm using this liberally to keep the
	   append/realloc code simple and hopefully reasonably fast. */

	// saved to file
	string[] history;

	// not saved
	Terminal* terminal;
	string historyFilename;

	/// Make sure that the parent terminal struct remains in scope for the duration
	/// of LineGetter's lifetime, as it does hold on to and use the passed pointer
	/// throughout.
	///
	/// historyFilename will load and save an input history log to a particular folder.
	/// Leaving it null will mean no file will be used and history will not be saved across sessions.
	this(Terminal* tty, string historyFilename = null) {
		this.terminal = tty;
		this.historyFilename = historyFilename;

		line.reserve(128);

		if(historyFilename.length)
			loadSettingsAndHistoryFromFile();

		regularForeground = cast(Color) terminal._currentForeground;
		background = cast(Color) terminal._currentBackground;
		suggestionForeground = Color.blue;
	}

	/// Call this before letting LineGetter die so it can do any necessary
	/// cleanup and save the updated history to a file.
	void dispose() {
		if(historyFilename.length && historyCommitMode == HistoryCommitMode.atTermination)
			saveSettingsAndHistoryToFile();
	}

	/// Override this to change the directory where history files are stored
	///
	/// Default is $HOME/.arsd-getline on linux and %APPDATA%/arsd-getline/ on Windows.
	/* virtual */ string historyFileDirectory() {
		version(Windows) {
			char[1024] path;
			// FIXME: this doesn't link because the crappy dmd lib doesn't have it
			if(0) { // SHGetFolderPathA(null, CSIDL_APPDATA, null, 0, path.ptr) >= 0) {
				import core.stdc.string;
				return cast(string) path[0 .. strlen(path.ptr)] ~ "\\arsd-getline";
			} else {
				import std.process;
				return environment["APPDATA"] ~ "\\arsd-getline";
			}
		} else version(Posix) {
			import std.process;
			return environment["HOME"] ~ "/.arsd-getline";
		}
	}

	/// You can customize the colors here. You should set these after construction, but before
	/// calling startGettingLine or getline.
	Color suggestionForeground = Color.blue;
	Color regularForeground = Color.DEFAULT; /// ditto
	Color background = Color.DEFAULT; /// ditto
	Color promptColor = Color.DEFAULT; /// ditto
	Color specialCharBackground = Color.green; /// ditto
	//bool reverseVideo;

	/// Set this if you want a prompt to be drawn with the line. It does NOT support color in string.
	@property void prompt(string p) {
		this.prompt_ = p;

		promptLength = 0;
		foreach(dchar c; p)
			promptLength++;
	}

	/// ditto
	@property string prompt() {
		return this.prompt_;
	}

	private string prompt_;
	private int promptLength;

	/++
		Turn on auto suggest if you want a greyed thing of what tab
		would be able to fill in as you type.

		You might want to turn it off if generating a completion list is slow.

		Or if you know you want it, be sure to turn it on explicitly in your
		code because I reserve the right to change the default without advance notice.

		History:
			On March 4, 2020, I changed the default to `false` because it
			is kinda slow and not useful in all cases.
	+/
	bool autoSuggest = false;

	/++
		Returns true if there was any input in the buffer. Can be
		checked in the case of a [UserInterruptionException].
	+/
	bool hadInput() {
		return line.length > 0;
	}

	/++
		Override this if you don't want all lines added to the history.
		You can return null to not add it at all, or you can transform it.

		History:
			Prior to October 12, 2021, it always committed all candidates.
			After that, it no longer commits in F9/ctrl+enter "run and maintain buffer"
			operations. This is tested with the [lastLineWasRetained] method.

			The idea is those are temporary experiments and need not clog history until
			it is complete.
	+/
	/* virtual */ string historyFilter(string candidate) {
		if(lastLineWasRetained())
			return null;
		return candidate;
	}

	/++
		History is normally only committed to the file when the program is
		terminating, but if you are losing data due to crashes, you might want
		to change this to `historyCommitMode = HistoryCommitMode.afterEachLine;`.

		History:
			Added January 26, 2021 (version 9.2)
	+/
	public enum HistoryCommitMode {
		/// The history file is written to disk only at disposal time by calling [saveSettingsAndHistoryToFile]
		atTermination,
		/// The history file is written to disk after each line of input by calling [appendHistoryToFile]
		afterEachLine
	}

	/// ditto
	public HistoryCommitMode historyCommitMode;

	/++
		You may override this to do nothing. If so, you should
		also override [appendHistoryToFile] if you ever change
		[historyCommitMode].

		You should call [historyPath] to get the proper filename.
	+/
	/* virtual */ void saveSettingsAndHistoryToFile() {
		import std.file;
		if(!exists(historyFileDirectory))
			mkdirRecurse(historyFileDirectory);

		auto fn = historyPath();

		import std.stdio;
		auto file = File(fn, "wb");
		file.write("// getline history file\r\n");
		foreach(item; history)
			file.writeln(item, "\r");
	}

	/++
		If [historyCommitMode] is [HistoryCommitMode.afterEachLine],
		this line is called after each line to append to the file instead
		of [saveSettingsAndHistoryToFile].

		Use [historyPath] to get the proper full path.

		History:
			Added January 26, 2021 (version 9.2)
	+/
	/* virtual */ void appendHistoryToFile(string item) {
		import std.file;

		if(!exists(historyFileDirectory))
			mkdirRecurse(historyFileDirectory);
		// this isn't exactly atomic but meh tbh i don't care.
		auto fn = historyPath();
		if(exists(fn)) {
			append(fn, item ~ "\r\n");
		} else {
			std.file.write(fn, "// getline history file\r\n" ~ item ~ "\r\n");
		}
	}

	/// You may override this to do nothing
	/* virtual */ void loadSettingsAndHistoryFromFile() {
		import std.file;
		history = null;
		auto fn = historyPath();
		if(exists(fn)) {
			import std.stdio, std.algorithm, std.string;
			string cur;

			auto file = File(fn, "rb");
			auto first = file.readln();
			if(first.startsWith("// getline history file")) {
				foreach(chunk; file.byChunk(1024)) {
					auto idx = (cast(char[]) chunk).indexOf(cast(char) '\r');
					while(idx != -1) {
						cur ~= cast(char[]) chunk[0 .. idx];
						history ~= cur;
						cur = null;
						if(idx + 2 <= chunk.length)
							chunk = chunk[idx + 2 .. $]; // skipping \r\n
						else
							chunk = chunk[$ .. $];
						idx = (cast(char[]) chunk).indexOf(cast(char) '\r');
					}
					cur ~= cast(char[]) chunk;
				}
				if(cur.length)
					history ~= cur;
			} else {
				// old-style plain file
				history ~= first;
				foreach(line; file.byLine())
					history ~= line.idup;
			}
		}
	}

	/++
		History:
			Introduced on January 31, 2020
	+/
	/* virtual */ string historyFileExtension() {
		return ".history";
	}

	/// semi-private, do not rely upon yet
	final string historyPath() {
		import std.path;
		auto filename = historyFileDirectory() ~ dirSeparator ~ historyFilename ~ historyFileExtension();
		return filename;
	}

	/++
		Override this to provide tab completion. You may use the candidate
		argument to filter the list, but you don't have to (LineGetter will
		do it for you on the values you return). This means you can ignore
		the arguments if you like.

		Ideally, you wouldn't return more than about ten items since the list
		gets difficult to use if it is too long.

		Tab complete cannot modify text before or after the cursor at this time.
		I *might* change that later to allow tab complete to fuzzy search and spell
		check fix before. But right now it ONLY inserts.

		Default is to provide recent command history as autocomplete.

		$(WARNING Both `candidate` and `afterCursor` may have private data packed into the dchar bits
		if you enabled [enableAutoCloseBrackets]. Use `ch & ~PRIVATE_BITS_MASK` to get standard dchars.)

		Returns:
			This function should return the full string to replace
			`candidate[tabCompleteStartPoint(args) .. $]`.
			For example, if your user wrote `wri<tab>` and you want to complete
			it to `write` or `writeln`, you should return `["write", "writeln"]`.

			If you offer different tab complete in different places, you still
			need to return the whole string. For example, a file completion of
			a second argument, when the user writes `terminal.d term<tab>` and you
			want it to complete to an additional `terminal.d`, you should return
			`["terminal.d terminal.d"]`; in other words, `candidate ~ completion`
			for each completion.

			It does this so you can simply return an array of words without having
			to rebuild that array for each combination.

			To choose the word separator, override [tabCompleteStartPoint].

		Params:
			candidate = the text of the line up to the text cursor, after
			which the completed text would be inserted

			afterCursor = the remaining text after the cursor. You can inspect
			this, but cannot change it - this will be appended to the line
			after completion, keeping the cursor in the same relative location.

		History:
			Prior to January 30, 2020, this method took only one argument,
			`candidate`. It now takes `afterCursor` as well, to allow you to
			make more intelligent completions with full context.
	+/
	/* virtual */ protected string[] tabComplete(in dchar[] candidate, in dchar[] afterCursor) {
		return history.length > 20 ? history[0 .. 20] : history;
	}

	/++
		Override this to provide a different tab competition starting point. The default
		is `0`, always completing the complete line, but you may return the index of another
		character of `candidate` to provide a new split.

		$(WARNING Both `candidate` and `afterCursor` may have private data packed into the dchar bits
		if you enabled [enableAutoCloseBrackets]. Use `ch & ~PRIVATE_BITS_MASK` to get standard dchars.)

		Returns:
			The index of `candidate` where we should start the slice to keep in [tabComplete].
			It must be `>= 0 && <= candidate.length`.

		History:
			Added on February 1, 2020. Initial default is to return 0 to maintain
			old behavior.
	+/
	/* virtual */ protected size_t tabCompleteStartPoint(in dchar[] candidate, in dchar[] afterCursor) {
		return 0;
	}

	/++
		This gives extra information for an item when displaying tab competition details.

		History:
			Added January 31, 2020.

	+/
	/* virtual */ protected string tabCompleteHelp(string candidate) {
		return null;
	}

	private string[] filterTabCompleteList(string[] list, size_t start) {
		if(list.length == 0)
			return list;

		string[] f;
		f.reserve(list.length);

		foreach(item; list) {
			import std.algorithm;
			if(startsWith(item, line[start .. cursorPosition].map!(x => x & ~PRIVATE_BITS_MASK)))
				f ~= item;
		}

		/+
		// if it is excessively long, let's trim it down by trying to
		// group common sub-sequences together.
		if(f.length > terminal.height * 3 / 4) {
			import std.algorithm;
			f.sort();

			// see how many can be saved by just keeping going until there is
			// no more common prefix. then commit that and keep on down the list.
			// since it is sorted, if there is a commonality, it should appear quickly
			string[] n;
			string commonality = f[0];
			size_t idx = 1;
			while(idx < f.length) {
				auto c = commonPrefix(commonality, f[idx]);
				if(c.length > cursorPosition - start) {
					commonality = c;
				} else {
					n ~= commonality;
					commonality = f[idx];
				}
				idx++;
			}
			if(commonality.length)
				n ~= commonality;

			if(n.length)
				f = n;
		}
		+/

		return f;
	}

	/++
		Override this to provide a custom display of the tab completion list.

		History:
			Prior to January 31, 2020, it only displayed the list. After
			that, it would call [tabCompleteHelp] for each candidate and display
			that string (if present) as well.
	+/
	protected void showTabCompleteList(string[] list) {
		if(list.length) {
			// FIXME: allow mouse clicking of an item, that would be cool

			auto start = tabCompleteStartPoint(line[0 .. cursorPosition], line[cursorPosition .. $]);

			// FIXME: scroll
			//if(terminal.type == ConsoleOutputType.linear) {
				terminal.writeln();
				foreach(item; list) {
					terminal.color(suggestionForeground, background);
					import std.utf;
					auto idx = codeLength!char(line[start .. cursorPosition]);
					terminal.write("  ", item[0 .. idx]);
					terminal.color(regularForeground, background);
					terminal.write(item[idx .. $]);
					auto help = tabCompleteHelp(item);
					if(help !is null) {
						import std.string;
						help = help.replace("\t", " ").replace("\n", " ").replace("\r", " ");
						terminal.write("\t\t");
						int remaining;
						if(terminal.cursorX + 2 < terminal.width) {
							remaining = terminal.width - terminal.cursorX - 2;
						}
						if(remaining > 8) {
							string msg = help;
							foreach(idxh, dchar c; msg) {
								remaining--;
								if(remaining <= 0) {
									msg = msg[0 .. idxh];
									break;
								}
							}

							/+
							size_t use = help.length < remaining ? help.length : remaining;

							if(use < help.length) {
								if((help[use] & 0xc0) != 0x80) {
									import std.utf;
									use += stride(help[use .. $]);
								} else {
									// just get to the end of this code point
									while(use < help.length && (help[use] & 0xc0) == 0x80)
										use++;
								}
							}
							auto msg = help[0 .. use];
							+/
							if(msg.length)
								terminal.write(msg);
						}
					}
					terminal.writeln();

				}
				updateCursorPosition();
				redraw();
			//}
		}
	}

	/++
		Called by the default event loop when the user presses F1. Override
		`showHelp` to change the UI, override [helpMessage] if you just want
		to change the message.

		History:
			Introduced on January 30, 2020
	+/
	protected void showHelp() {
		terminal.writeln();
		terminal.writeln(helpMessage);
		updateCursorPosition();
		redraw();
	}

	/++
		History:
			Introduced on January 30, 2020
	+/
	protected string helpMessage() {
		return "Press F2 to edit current line in your external editor. F3 searches history. F9 runs current line while maintaining current edit state.";
	}

	/++
		$(WARNING `line` may have private data packed into the dchar bits
		if you enabled [enableAutoCloseBrackets]. Use `ch & ~PRIVATE_BITS_MASK` to get standard dchars.)

		History:
			Introduced on January 30, 2020
	+/
	protected dchar[] editLineInEditor(in dchar[] line, in size_t cursorPosition) {
		import std.conv;
		import std.process;
		import std.file;

		char[] tmpName;

		version(Windows) {
			import core.stdc.string;
			char[280] path;
			auto l = GetTempPathA(cast(DWORD) path.length, path.ptr);
			if(l == 0) throw new Exception("GetTempPathA");
			path[l] = 0;
			char[280] name;
			auto r = GetTempFileNameA(path.ptr, "adr", 0, name.ptr);
			if(r == 0) throw new Exception("GetTempFileNameA");
			tmpName = name[0 .. strlen(name.ptr)];
			scope(exit)
				std.file.remove(tmpName);
			std.file.write(tmpName, to!string(line));

			string editor = environment.get("EDITOR", "notepad.exe");
		} else {
			import core.stdc.stdlib;
			import core.sys.posix.unistd;
			char[120] name;
			string p = "/tmp/adrXXXXXX";
			name[0 .. p.length] = p[];
			name[p.length] = 0;
			auto fd = mkstemp(name.ptr);
			tmpName = name[0 .. p.length];
			if(fd == -1) throw new Exception("mkstemp");
			scope(exit)
				close(fd);
			scope(exit)
				std.file.remove(tmpName);

			string s = to!string(line);
			while(s.length) {
				auto x = write(fd, s.ptr, s.length);
				if(x == -1) throw new Exception("write");
				s = s[x .. $];
			}
			string editor = environment.get("EDITOR", "vi");
		}

		// FIXME the spawned process changes even more terminal state than set up here!

		try {
			version(none)
			if(UseVtSequences) {
				if(terminal.type == ConsoleOutputType.cellular) {
					terminal.doTermcap("te");
				}
			}
			version(Posix) {
				import std.stdio;
				// need to go to the parent terminal jic we're in an embedded terminal with redirection
				terminal.write(" !! Editor may be in parent terminal !!");
				terminal.flush();
				spawnProcess([editor, tmpName], File("/dev/tty", "rb"), File("/dev/tty", "wb")).wait;
			} else {
				spawnProcess([editor, tmpName]).wait;
			}
			if(UseVtSequences) {
				if(terminal.type == ConsoleOutputType.cellular)
					terminal.doTermcap("ti");
			}
			import std.string;
			return to!(dchar[])(cast(char[]) std.file.read(tmpName)).chomp;
		} catch(Exception e) {
			// edit failed, we should prolly tell them but idk how....
			return null;
		}
	}

	//private RealTimeConsoleInput* rtci;

	/// One-call shop for the main workhorse
	/// If you already have a RealTimeConsoleInput ready to go, you
	/// should pass a pointer to yours here. Otherwise, LineGetter will
	/// make its own.
	public string getline(RealTimeConsoleInput* input = null) {
		startGettingLine();
		if(input is null) {
			auto i = RealTimeConsoleInput(terminal, ConsoleInputFlags.raw | ConsoleInputFlags.allInputEvents | ConsoleInputFlags.selectiveMouse | ConsoleInputFlags.noEolWrap);
			//rtci = &i;
			//scope(exit) rtci = null;
			while(workOnLine(i.nextEvent(), &i)) {}
		} else {
			//rtci = input;
			//scope(exit) rtci = null;
			while(workOnLine(input.nextEvent(), input)) {}
		}
		return finishGettingLine();
	}

	/++
		Set in [historyRecallFilterMethod].

		History:
			Added November 27, 2020.
	+/
	enum HistoryRecallFilterMethod {
		/++
			Goes through history in simple chronological order.
			Your existing command entry is not considered as a filter.
		+/
		chronological,
		/++
			Goes through history filtered with only those that begin with your current command entry.

			So, if you entered "animal", "and", "bad", "cat" previously, then enter
			"a" and pressed up, it would jump to "and", then up again would go to "animal".
		+/
		prefixed,
		/++
			Goes through history filtered with only those that $(B contain) your current command entry.

			So, if you entered "animal", "and", "bad", "cat" previously, then enter
			"n" and pressed up, it would jump to "and", then up again would go to "animal".
		+/
		containing,
		/++
			Goes through history to fill in your command at the cursor. It filters to only entries
			that start with the text before your cursor and ends with text after your cursor.

			So, if you entered "animal", "and", "bad", "cat" previously, then enter
			"ad" and pressed left to position the cursor between the a and d, then pressed up
			it would jump straight to "and".
		+/
		sandwiched,
	}
	/++
		Controls what happens when the user presses the up key, etc., to recall history entries. See [HistoryRecallMethod] for the options.

		This has no effect on the history search user control (default key: F3 or ctrl+r), which always searches through a "containing" method.

		History:
			Added November 27, 2020.
	+/
	HistoryRecallFilterMethod historyRecallFilterMethod = HistoryRecallFilterMethod.chronological;

	/++
		Enables automatic closing of brackets like (, {, and [ when the user types.
		Specifically, you subclass and return a string of the completions you want to
		do, so for that set, return `"()[]{}"`


		$(WARNING
			If you subclass this and return anything other than `null`, your subclass must also
			realize that the `line` member and everything that slices it ([tabComplete] and more)
			need to mask away the extra bits to get the original content. See [PRIVATE_BITS_MASK].
			`line[] &= cast(dchar) ~PRIVATE_BITS_MASK;`
		)

		Returns:
			A string with pairs of characters. When the user types the character in an even-numbered
			position, it automatically inserts the following character after the cursor (without moving
			the cursor). The inserted character will be automatically overstriken if the user types it
			again.

			The default is `return null`, which disables the feature.

		History:
			Added January 25, 2021 (version 9.2)
	+/
	protected string enableAutoCloseBrackets() {
		return null;
	}

	/++
		If [enableAutoCloseBrackets] does not return null, you should ignore these bits in the line.
	+/
	protected enum PRIVATE_BITS_MASK = 0x80_00_00_00;
	// note: several instances in the code of PRIVATE_BITS_MASK are kinda conservative; masking it away is destructive
	// but less so than crashing cuz of invalid unicode character popping up later. Besides the main intention is when
	// you are kinda immediately typing so it forgetting is probably fine.

	/++
		Subclasses that implement this function can enable syntax highlighting in the line as you edit it.


		The library will call this when it prepares to draw the line, giving you the full line as well as the
		current position in that array it is about to draw. You return a [SyntaxHighlightMatch]
		object with its `charsMatched` member set to how many characters the given colors should apply to.
		If it is set to zero, default behavior is retained for the next character, and [syntaxHighlightMatch]
		will be called again immediately. If it is set to -1 syntax highlighting is disabled for the rest of
		the line. If set to int.max, it will apply to the remainder of the line.

		If it is set to another positive value, the given colors are applied for that number of characters and
		[syntaxHighlightMatch] will NOT be called again until those characters are consumed.

		Note that the first call may have `currentDrawPosition` be greater than zero due to horizontal scrolling.
		After that though, it will be called based on your `charsMatched` in the return value.

		`currentCursorPosition` is passed in case you want to do things like highlight a matching parenthesis over
		the cursor or similar. You can also simply ignore it.

		$(WARNING `line` may have private data packed into the dchar bits
		if you enabled [enableAutoCloseBrackets]. Use `ch & ~PRIVATE_BITS_MASK` to get standard dchars.)

		History:
			Added January 25, 2021 (version 9.2)
	+/
	protected SyntaxHighlightMatch syntaxHighlightMatch(in dchar[] line, in size_t currentDrawPosition, in size_t currentCursorPosition) {
		return SyntaxHighlightMatch(-1); // -1 just means syntax highlighting is disabled and it shouldn't try again
	}

	/// ditto
	static struct SyntaxHighlightMatch {
		int charsMatched = 0;
		Color foreground = Color.DEFAULT;
		Color background = Color.DEFAULT;
	}


	private int currentHistoryViewPosition = 0;
	private dchar[] uncommittedHistoryCandidate;
	private int uncommitedHistoryCursorPosition;
	void loadFromHistory(int howFarBack) {
		if(howFarBack < 0)
			howFarBack = 0;
		if(howFarBack > history.length) // lol signed/unsigned comparison here means if i did this first, before howFarBack < 0, it would totally cycle around.
			howFarBack = cast(int) history.length;
		if(howFarBack == currentHistoryViewPosition)
			return;
		if(currentHistoryViewPosition == 0) {
			// save the current line so we can down arrow back to it later
			if(uncommittedHistoryCandidate.length < line.length) {
				uncommittedHistoryCandidate.length = line.length;
			}

			uncommittedHistoryCandidate[0 .. line.length] = line[];
			uncommittedHistoryCandidate = uncommittedHistoryCandidate[0 .. line.length];
			uncommittedHistoryCandidate.assumeSafeAppend();
			uncommitedHistoryCursorPosition = cursorPosition;
		}

		if(howFarBack == 0) {
		zero:
			line.length = uncommittedHistoryCandidate.length;
			line.assumeSafeAppend();
			line[] = uncommittedHistoryCandidate[];
		} else {
			line = line[0 .. 0];
			line.assumeSafeAppend();

			string selection;

			final switch(historyRecallFilterMethod) with(HistoryRecallFilterMethod) {
				case chronological:
					selection = history[$ - howFarBack];
				break;
				case prefixed:
				case containing:
					import std.algorithm;
					int count;
					foreach_reverse(item; history) {
						if(
							(historyRecallFilterMethod == prefixed && item.startsWith(uncommittedHistoryCandidate))
							||
							(historyRecallFilterMethod == containing && item.canFind(uncommittedHistoryCandidate))
						)
						{
							selection = item;
							count++;
							if(count == howFarBack)
								break;
						}
					}
					howFarBack = count;
				break;
				case sandwiched:
					import std.algorithm;
					int count;
					foreach_reverse(item; history) {
						if(
							(item.startsWith(uncommittedHistoryCandidate[0 .. uncommitedHistoryCursorPosition]))
							&&
							(item.endsWith(uncommittedHistoryCandidate[uncommitedHistoryCursorPosition .. $]))
						)
						{
							selection = item;
							count++;
							if(count == howFarBack)
								break;
						}
					}
					howFarBack = count;

				break;
			}

			if(howFarBack == 0)
				goto zero;

			int i;
			line.length = selection.length;
			foreach(dchar ch; selection)
				line[i++] = ch;
			line = line[0 .. i];
			line.assumeSafeAppend();
		}

		currentHistoryViewPosition = howFarBack;
		cursorPosition = cast(int) line.length;
		scrollToEnd();
	}

	bool insertMode = true;

	private ConsoleOutputType original = cast(ConsoleOutputType) -1;
	private bool multiLineModeOn = false;
	private int startOfLineXOriginal;
	private int startOfLineYOriginal;
	void multiLineMode(bool on) {
		if(original == -1) {
			original = terminal.type;
			startOfLineXOriginal = startOfLineX;
			startOfLineYOriginal = startOfLineY;
		}

		if(on) {
			terminal.enableAlternateScreen = true;
			startOfLineX = 0;
			startOfLineY = 0;
		}
		else if(original == ConsoleOutputType.linear) {
			terminal.enableAlternateScreen = false;
		}

		if(!on) {
			startOfLineX = startOfLineXOriginal;
			startOfLineY = startOfLineYOriginal;
		}

		multiLineModeOn = on;
	}
	bool multiLineMode() { return multiLineModeOn; }

	void toggleMultiLineMode() {
		multiLineMode = !multiLineModeOn;
		redraw();
	}

	private dchar[] line;
	private int cursorPosition = 0;
	private int horizontalScrollPosition = 0;
	private int verticalScrollPosition = 0;

	private void scrollToEnd() {
		if(multiLineMode) {
			// FIXME
		} else {
			horizontalScrollPosition = (cast(int) line.length);
			horizontalScrollPosition -= availableLineLength();
			if(horizontalScrollPosition < 0)
				horizontalScrollPosition = 0;
		}
	}

	// used for redrawing the line in the right place
	// and detecting mouse events on our line.
	private int startOfLineX;
	private int startOfLineY;

	// private string[] cachedCompletionList;

	// FIXME
	// /// Note that this assumes the tab complete list won't change between actual
	// /// presses of tab by the user. If you pass it a list, it will use it, but
	// /// otherwise it will keep track of the last one to avoid calls to tabComplete.
	private string suggestion(string[] list = null) {
		import std.algorithm, std.utf;
		auto relevantLineSection = line[0 .. cursorPosition];
		auto start = tabCompleteStartPoint(relevantLineSection, line[cursorPosition .. $]);
		relevantLineSection = relevantLineSection[start .. $];
		// FIXME: see about caching the list if we easily can
		if(list is null)
			list = filterTabCompleteList(tabComplete(relevantLineSection, line[cursorPosition .. $]), start);

		if(list.length) {
			string commonality = list[0];
			foreach(item; list[1 .. $]) {
				commonality = commonPrefix(commonality, item);
			}

			if(commonality.length) {
				return commonality[codeLength!char(relevantLineSection) .. $];
			}
		}

		return null;
	}

	/// Adds a character at the current position in the line. You can call this too if you hook events for hotkeys or something.
	/// You'll probably want to call redraw() after adding chars.
	void addChar(dchar ch) {
		assert(cursorPosition >= 0 && cursorPosition <= line.length);
		if(cursorPosition == line.length)
			line ~= ch;
		else {
			assert(line.length);
			if(insertMode) {
				line ~= ' ';
				for(int i = cast(int) line.length - 2; i >= cursorPosition; i --)
					line[i + 1] = line[i];
			}
			line[cursorPosition] = ch;
		}
		cursorPosition++;

		if(multiLineMode) {
			// FIXME
		} else {
			if(cursorPosition > horizontalScrollPosition + availableLineLength())
				horizontalScrollPosition++;
		}

		lineChanged = true;
	}

	/// .
	void addString(string s) {
		// FIXME: this could be more efficient
		// but does it matter? these lines aren't super long anyway. But then again a paste could be excessively long (prolly accidental, but still)

		import std.utf;
		foreach(dchar ch; s.byDchar) // using this for the replacement dchar, normal foreach would throw on invalid utf 8
			addChar(ch);
	}

	/// Deletes the character at the current position in the line.
	/// You'll probably want to call redraw() after deleting chars.
	void deleteChar() {
		if(cursorPosition == line.length)
			return;
		for(int i = cursorPosition; i < line.length - 1; i++)
			line[i] = line[i + 1];
		line = line[0 .. $-1];
		line.assumeSafeAppend();
		lineChanged = true;
	}

	protected bool lineChanged;

	private void killText(dchar[] text) {
		if(!text.length)
			return;

		if(justKilled)
			killBuffer = text ~ killBuffer;
		else
			killBuffer = text;
	}

	///
	void deleteToEndOfLine() {
		killText(line[cursorPosition .. $]);
		line = line[0 .. cursorPosition];
		line.assumeSafeAppend();
		//while(cursorPosition < line.length)
			//deleteChar();
	}

	/++
		Used by the word movement keys (e.g. alt+backspace) to find a word break.

		History:
			Added April 21, 2021 (dub v9.5)

			Prior to that, [LineGetter] only used [std.uni.isWhite]. Now it uses this which
			uses if not alphanum and not underscore.

			You can subclass this to customize its behavior.
	+/
	bool isWordSeparatorCharacter(dchar d) {
		import std.uni : isAlphaNum;

		return !(isAlphaNum(d) || d == '_');
	}

	private int wordForwardIdx() {
		int cursorPosition = this.cursorPosition;
		if(cursorPosition == line.length)
			return cursorPosition;
		while(cursorPosition + 1 < line.length && isWordSeparatorCharacter(line[cursorPosition]))
			cursorPosition++;
		while(cursorPosition + 1 < line.length && !isWordSeparatorCharacter(line[cursorPosition + 1]))
			cursorPosition++;
		cursorPosition += 2;
		if(cursorPosition > line.length)
			cursorPosition = cast(int) line.length;

		return cursorPosition;
	}
	void wordForward() {
		cursorPosition = wordForwardIdx();
		aligned(cursorPosition, 1);
		maybePositionCursor();
	}
	void killWordForward() {
		int to = wordForwardIdx(), from = cursorPosition;
		killText(line[from .. to]);
		line = line[0 .. from] ~ line[to .. $];
		cursorPosition = cast(int)from;
		maybePositionCursor();
	}
	private int wordBackIdx() {
		if(!line.length || !cursorPosition)
			return cursorPosition;
		int ret = cursorPosition - 1;
		while(ret && isWordSeparatorCharacter(line[ret]))
			ret--;
		while(ret && !isWordSeparatorCharacter(line[ret - 1]))
			ret--;
		return ret;
	}
	void wordBack() {
		cursorPosition = wordBackIdx();
		aligned(cursorPosition, -1);
		maybePositionCursor();
	}
	void killWord() {
		int from = wordBackIdx(), to = cursorPosition;
		killText(line[from .. to]);
		line = line[0 .. from] ~ line[to .. $];
		cursorPosition = cast(int)from;
		maybePositionCursor();
	}

	private void maybePositionCursor() {
		if(multiLineMode) {
			// omg this is so bad
			// and it more accurately sets scroll position
			int x, y;
			foreach(idx, ch; line) {
				if(idx == cursorPosition)
					break;
				if(ch == '\n') {
					x = 0;
					y++;
				} else {
					x++;
				}
			}

			while(x - horizontalScrollPosition < 0) {
				horizontalScrollPosition -= terminal.width / 2;
				if(horizontalScrollPosition < 0)
					horizontalScrollPosition = 0;
			}
			while(y - verticalScrollPosition < 0) {
				verticalScrollPosition --;
				if(verticalScrollPosition < 0)
					verticalScrollPosition = 0;
			}

			while((x - horizontalScrollPosition) >= terminal.width) {
				horizontalScrollPosition += terminal.width / 2;
			}
			while((y - verticalScrollPosition) + 2 >= terminal.height) {
				verticalScrollPosition ++;
			}

		} else {
			if(cursorPosition < horizontalScrollPosition || cursorPosition > horizontalScrollPosition + availableLineLength()) {
				positionCursor();
			}
		}
	}

	private void charBack() {
		if(!cursorPosition)
			return;
		cursorPosition--;
		aligned(cursorPosition, -1);
		maybePositionCursor();
	}
	private void charForward() {
		if(cursorPosition >= line.length)
			return;
		cursorPosition++;
		aligned(cursorPosition, 1);
		maybePositionCursor();
	}

	int availableLineLength() {
		return maximumDrawWidth - promptLength - 1;
	}

	/++
		Controls the input echo setting.

		Possible values are:

			`dchar.init` = normal; user can see their input.

			`'\0'` = nothing; the cursor does not visually move as they edit. Similar to Unix style password prompts.

			`'*'` (or anything else really) = will replace all input characters with stars when displaying, obscure the specific characters, but still showing the number of characters and position of the cursor to the user.

		History:
			Added October 11, 2021 (dub v10.4)
	+/
	dchar echoChar = dchar.init;

	protected static struct Drawer {
		LineGetter lg;

		this(LineGetter lg) {
			this.lg = lg;
			linesRemaining = lg.terminal.height - 1;
		}

		int written;
		int lineLength;

		int linesRemaining;


		Color currentFg_ = Color.DEFAULT;
		Color currentBg_ = Color.DEFAULT;
		int colorChars = 0;

		Color currentFg() {
			if(colorChars <= 0 || currentFg_ == Color.DEFAULT)
				return lg.regularForeground;
			return currentFg_;
		}

		Color currentBg() {
			if(colorChars <= 0 || currentBg_ == Color.DEFAULT)
				return lg.background;
			return currentBg_;
		}

		void specialChar(char c) {
			// maybe i should check echoChar here too but meh

			lg.terminal.color(lg.regularForeground, lg.specialCharBackground);
			lg.terminal.write(c);
			lg.terminal.color(currentFg, currentBg);

			written++;
			lineLength--;
		}

		void regularChar(dchar ch) {
			import std.utf;
			char[4] buffer;

			if(lg.echoChar == '\0')
				return;
			else if(lg.echoChar !is dchar.init)
				ch = lg.echoChar;

			auto l = encode(buffer, ch);
			// note the Terminal buffers it so meh
			lg.terminal.write(buffer[0 .. l]);

			written++;
			lineLength--;

			if(lg.multiLineMode) {
				if(ch == '\n') {
					lineLength = lg.terminal.width;
					linesRemaining--;
				}
			}
		}

		void drawContent(T)(T towrite, int highlightBegin = 0, int highlightEnd = 0, bool inverted = false, int lineidx = -1) {
			// FIXME: if there is a color at the end of the line it messes up as you scroll
			// FIXME: need a way to go to multi-line editing

			bool highlightOn = false;
			void highlightOff() {
				lg.terminal.color(currentFg, currentBg, ForceOption.automatic, inverted);
				highlightOn = false;
			}

			foreach(idx, dchar ch; towrite) {
				if(linesRemaining <= 0)
					break;
				if(lineLength <= 0) {
					if(lg.multiLineMode) {
						if(ch == '\n') {
							lineLength = lg.terminal.width;
						}
						continue;
					} else
						break;
				}

				static if(is(T == dchar[])) {
					if(lineidx != -1 && colorChars == 0) {
						auto shm = lg.syntaxHighlightMatch(lg.line, lineidx + idx, lg.cursorPosition);
						if(shm.charsMatched > 0) {
							colorChars = shm.charsMatched;
							currentFg_ = shm.foreground;
							currentBg_ = shm.background;
							lg.terminal.color(currentFg, currentBg);
						}
					}
				}

				switch(ch) {
					case '\n': lg.multiLineMode ? regularChar('\n') : specialChar('n'); break;
					case '\r': specialChar('r'); break;
					case '\a': specialChar('a'); break;
					case '\t': specialChar('t'); break;
					case '\b': specialChar('b'); break;
					case '\033': specialChar('e'); break;
					case '\&nbsp;': specialChar(' '); break;
					default:
						if(highlightEnd) {
							if(idx == highlightBegin) {
								lg.terminal.color(lg.regularForeground, Color.yellow, ForceOption.automatic, inverted);
								highlightOn = true;
							}
							if(idx == highlightEnd) {
								highlightOff();
							}
						}

						regularChar(ch & ~PRIVATE_BITS_MASK);
				}

				if(colorChars > 0) {
					colorChars--;
					if(colorChars == 0)
						lg.terminal.color(currentFg, currentBg);
				}
			}
			if(highlightOn)
				highlightOff();
		}

	}

	/++
		If you are implementing a subclass, use this instead of `terminal.width` to see how far you can draw. Use care to remember this is a width, not a right coordinate.

		History:
			Added May 24, 2021
	+/
	final public @property int maximumDrawWidth() {
		auto tw = terminal.width - startOfLineX;
		if(_drawWidthMax && _drawWidthMax <= tw)
			return _drawWidthMax;
		return tw;
	}

	/++
		Sets the maximum width the line getter will use. Set to 0 to disable, in which case it will use the entire width of the terminal.

		History:
			Added May 24, 2021
	+/
	final public @property void maximumDrawWidth(int newMax) {
		_drawWidthMax = newMax;
	}

	/++
		Returns the maximum vertical space available to draw.

		Currently, this is always 1.

		History:
			Added May 24, 2021
	+/
	@property int maximumDrawHeight() {
		return 1;
	}

	private int _drawWidthMax = 0;

	private int lastDrawLength = 0;
	void redraw() {
		finalizeRedraw(coreRedraw());
	}

	void finalizeRedraw(CoreRedrawInfo cdi) {
		if(!cdi.populated)
			return;

		if(!multiLineMode) {
			terminal.clearToEndOfLine();
			/*
			if(UseVtSequences && !_drawWidthMax) {
				terminal.writeStringRaw("\033[K");
			} else {
				// FIXME: graphemes
				if(cdi.written + promptLength < lastDrawLength)
				foreach(i; cdi.written + promptLength .. lastDrawLength)
					terminal.write(" ");
				lastDrawLength = cdi.written;
			}
			*/
			// if echoChar is null then we don't want to reflect the position at all
			terminal.moveTo(startOfLineX + ((echoChar == 0) ? 0 : cdi.cursorPositionToDrawX) + promptLength, startOfLineY + cdi.cursorPositionToDrawY);
		} else {
			if(echoChar != 0)
				terminal.moveTo(cdi.cursorPositionToDrawX, cdi.cursorPositionToDrawY);
		}
		endRedraw(); // make sure the cursor is turned back on
	}

	static struct CoreRedrawInfo {
		bool populated;
		int written;
		int cursorPositionToDrawX;
		int cursorPositionToDrawY;
	}

	private void endRedraw() {
		version(Win32Console) {
			// on Windows, we want to make sure all
			// is displayed before the cursor jumps around
			terminal.flush();
			terminal.showCursor();
		} else {
			// but elsewhere, the showCursor is itself buffered,
			// so we can do it all at once for a slight speed boost
			terminal.showCursor();
			//import std.string; import std.stdio; writeln(terminal.writeBuffer.replace("\033", "\\e"));
			terminal.flush();
		}
	}

	final CoreRedrawInfo coreRedraw() {
		if(supplementalGetter)
			return CoreRedrawInfo.init; // the supplementalGetter will be drawing instead...
		terminal.hideCursor();
		scope(failure) {
			// don't want to leave the cursor hidden on the event of an exception
			// can't just scope(success) it here since the cursor will be seen bouncing when finalizeRedraw is run
			endRedraw();
		}
		terminal.moveTo(startOfLineX, startOfLineY);

		if(multiLineMode)
			terminal.clear();

		Drawer drawer = Drawer(this);

		drawer.lineLength = availableLineLength();
		if(drawer.lineLength < 0)
			throw new Exception("too narrow terminal to draw");

		if(!multiLineMode) {
			terminal.color(promptColor, background);
			terminal.write(prompt);
			terminal.color(regularForeground, background);
		}

		dchar[] towrite;

		if(multiLineMode) {
			towrite = line[];
			if(verticalScrollPosition) {
				int remaining = verticalScrollPosition;
				while(towrite.length) {
					if(towrite[0] == '\n') {
						towrite = towrite[1 .. $];
						remaining--;
						if(remaining == 0)
							break;
						continue;
					}
					towrite = towrite[1 .. $];
				}
			}
			horizontalScrollPosition = 0; // FIXME
		} else {
			towrite = line[horizontalScrollPosition .. $];
		}
		auto cursorPositionToDrawX = cursorPosition - horizontalScrollPosition;
		auto cursorPositionToDrawY = 0;

		if(selectionStart != selectionEnd) {
			dchar[] beforeSelection, selection, afterSelection;

			beforeSelection = line[0 .. selectionStart];
			selection = line[selectionStart .. selectionEnd];
			afterSelection = line[selectionEnd .. $];

			drawer.drawContent(beforeSelection);
			terminal.color(regularForeground, background, ForceOption.automatic, true);
			drawer.drawContent(selection, 0, 0, true);
			terminal.color(regularForeground, background);
			drawer.drawContent(afterSelection);
		} else {
			drawer.drawContent(towrite, 0, 0, false, horizontalScrollPosition);
		}

		string suggestion;

		if(drawer.lineLength >= 0) {
			suggestion = ((cursorPosition == towrite.length) && autoSuggest) ? this.suggestion() : null;
			if(suggestion.length) {
				terminal.color(suggestionForeground, background);
				foreach(dchar ch; suggestion) {
					if(drawer.lineLength == 0)
						break;
					drawer.regularChar(ch);
				}
				terminal.color(regularForeground, background);
			}
		}

		CoreRedrawInfo cri;
		cri.populated = true;
		cri.written = drawer.written;
		if(multiLineMode) {
			cursorPositionToDrawX = 0;
			cursorPositionToDrawY = 0;
			// would be better if it did this in the same drawing pass...
			foreach(idx, dchar ch; line) {
				if(idx == cursorPosition)
					break;
				if(ch == '\n') {
					cursorPositionToDrawX = 0;
					cursorPositionToDrawY++;
				} else {
					cursorPositionToDrawX++;
				}
			}

			cri.cursorPositionToDrawX = cursorPositionToDrawX - horizontalScrollPosition;
			cri.cursorPositionToDrawY = cursorPositionToDrawY - verticalScrollPosition;
		} else {
			cri.cursorPositionToDrawX = cursorPositionToDrawX;
			cri.cursorPositionToDrawY = cursorPositionToDrawY;
		}

		return cri;
	}

	/// Starts getting a new line. Call workOnLine and finishGettingLine afterward.
	///
	/// Make sure that you've flushed your input and output before calling this
	/// function or else you might lose events or get exceptions from this.
	void startGettingLine() {
		// reset from any previous call first
		if(!maintainBuffer) {
			cursorPosition = 0;
			horizontalScrollPosition = 0;
			verticalScrollPosition = 0;
			justHitTab = false;
			currentHistoryViewPosition = 0;
			if(line.length) {
				line = line[0 .. 0];
				line.assumeSafeAppend();
			}
		}

		maintainBuffer = false;

		initializeWithSize(true);

		terminal.cursor = TerminalCursor.insert;
		terminal.showCursor();
	}

	private void positionCursor() {
		if(cursorPosition == 0) {
			horizontalScrollPosition = 0;
			verticalScrollPosition = 0;
		} else if(cursorPosition == line.length) {
			scrollToEnd();
		} else {
			if(multiLineMode) {
				// FIXME
				maybePositionCursor();
			} else {
				// otherwise just try to center it in the screen
				horizontalScrollPosition = cursorPosition;
				horizontalScrollPosition -= maximumDrawWidth / 2;
				// align on a code point boundary
				aligned(horizontalScrollPosition, -1);
				if(horizontalScrollPosition < 0)
					horizontalScrollPosition = 0;
			}
		}
	}

	private void aligned(ref int what, int direction) {
		// whereas line is right now dchar[] no need for this
		// at least until we go by grapheme...
		/*
		while(what > 0 && what < line.length && ((line[what] & 0b1100_0000) == 0b1000_0000))
			what += direction;
		*/
	}

	protected void initializeWithSize(bool firstEver = false) {
		auto x = startOfLineX;

		updateCursorPosition();

		if(!firstEver) {
			startOfLineX = x;
			positionCursor();
		}

		lastDrawLength = maximumDrawWidth;
		version(Win32Console)
			lastDrawLength -= 1; // I don't like this but Windows resizing is different anyway and it is liable to scroll if i go over..

		redraw();
	}

	protected void updateCursorPosition() {
		terminal.updateCursorPosition();

		startOfLineX = terminal.cursorX;
		startOfLineY = terminal.cursorY;
	}

	// Text killed with C-w/C-u/C-k/C-backspace, to be restored by C-y
	private dchar[] killBuffer;

	// Given 'a b c d|', C-w C-w C-y should kill c and d, and then restore both
	// But given 'a b c d|', C-w M-b C-w C-y should kill d, kill b, and then restore only b
	// So we need this extra bit of state to decide whether to append to or replace the kill buffer
	// when the user kills some text
	private bool justKilled;

	private bool justHitTab;
	private bool eof;

	///
	string delegate(string s) pastePreprocessor;

	string defaultPastePreprocessor(string s) {
		return s;
	}

	void showIndividualHelp(string help) {
		terminal.writeln();
		terminal.writeln(help);
	}

	private bool maintainBuffer;

	/++
		Returns true if the last line was retained by the user via the F9 or ctrl+enter key
		which runs it but keeps it in the edit buffer.

		This is only valid inside [finishGettingLine] or immediately after [finishGettingLine]
		returns, but before [startGettingLine] is called again.

		History:
			Added October 12, 2021
	+/
	final public bool lastLineWasRetained() const {
		return maintainBuffer;
	}

	private LineGetter supplementalGetter;

	/* selection helpers */
	protected {
		// make sure you set the anchor first
		void extendSelectionToCursor() {
			if(cursorPosition < selectionStart)
				selectionStart = cursorPosition;
			else if(cursorPosition > selectionEnd)
				selectionEnd = cursorPosition;

			terminal.requestSetTerminalSelection(getSelection());
		}
		void setSelectionAnchorToCursor() {
			if(selectionStart == -1)
				selectionStart = selectionEnd = cursorPosition;
		}
		void sanitizeSelection() {
			if(selectionStart == selectionEnd)
				return;

			if(selectionStart < 0 || selectionEnd < 0 || selectionStart > line.length || selectionEnd > line.length)
				selectNone();
		}
	}
	public {
		// redraw after calling this
		void selectAll() {
			selectionStart = 0;
			selectionEnd = cast(int) line.length;
		}

		// redraw after calling this
		void selectNone() {
			selectionStart = selectionEnd = -1;
		}

		string getSelection() {
			sanitizeSelection();
			if(selectionStart == selectionEnd)
				return null;
			import std.conv;
			line[] &= cast(dchar) ~PRIVATE_BITS_MASK;
			return to!string(line[selectionStart .. selectionEnd]);
		}
	}
	private {
		int selectionStart = -1;
		int selectionEnd = -1;
	}

	void backwardToNewline() {
		while(cursorPosition && line[cursorPosition - 1] != '\n')
			cursorPosition--;
		phantomCursorX = 0;
	}

	void forwardToNewLine() {
		while(cursorPosition < line.length && line[cursorPosition] != '\n')
			cursorPosition++;
	}

	private int phantomCursorX;

	void lineBackward() {
		int count;
		while(cursorPosition && line[cursorPosition - 1] != '\n') {
			cursorPosition--;
			count++;
		}
		if(count > phantomCursorX)
			phantomCursorX = count;

		if(cursorPosition == 0)
			return;
		cursorPosition--;

		while(cursorPosition && line[cursorPosition - 1] != '\n') {
			cursorPosition--;
		}

		count = phantomCursorX;
		while(count) {
			if(cursorPosition == line.length)
				break;
			if(line[cursorPosition] == '\n')
				break;
			cursorPosition++;
			count--;
		}
	}

	void lineForward() {
		int count;

		// see where we are in the current line
		auto beginPos = cursorPosition;
		while(beginPos && line[beginPos - 1] != '\n') {
			beginPos--;
			count++;
		}

		if(count > phantomCursorX)
			phantomCursorX = count;

		// get to the next line
		while(cursorPosition < line.length && line[cursorPosition] != '\n') {
			cursorPosition++;
		}
		if(cursorPosition == line.length)
			return;
		cursorPosition++;

		// get to the same spot in this same line
		count = phantomCursorX;
		while(count) {
			if(cursorPosition == line.length)
				break;
			if(line[cursorPosition] == '\n')
				break;
			cursorPosition++;
			count--;
		}
	}

	void pageBackward() {
		foreach(count; 0 .. terminal.height)
			lineBackward();
		maybePositionCursor();
	}

	void pageForward() {
		foreach(count; 0 .. terminal.height)
			lineForward();
		maybePositionCursor();
	}

	bool isSearchingHistory() {
		return supplementalGetter !is null;
	}

	/++
		Cancels an in-progress history search immediately, discarding the result, returning
		to the normal prompt.

		If the user is not currently searching history (see [isSearchingHistory]), this
		function does nothing.
	+/
	void cancelHistorySearch() {
		if(isSearchingHistory()) {
			lastDrawLength = maximumDrawWidth - 1;
			supplementalGetter = null;
			redraw();
		}
	}

	/++
		for integrating into another event loop
		you can pass individual events to this and
		the line getter will work on it

		returns false when there's nothing more to do

		History:
			On February 17, 2020, it was changed to take
			a new argument which should be the input source
			where the event came from.
	+/
	bool workOnLine(InputEvent e, RealTimeConsoleInput* rtti = null) {
		if(supplementalGetter) {
			if(!supplementalGetter.workOnLine(e, rtti)) {
				auto got = supplementalGetter.finishGettingLine();
				// the supplementalGetter will poke our own state directly
				// so i can ignore the return value here...

				// but i do need to ensure we clear any
				// stuff left on the screen from it.
				lastDrawLength = maximumDrawWidth - 1;
				supplementalGetter = null;
				redraw();
			}
			return true;
		}

		switch(e.type) {
			case InputEvent.Type.EndOfFileEvent:
				justHitTab = false;
				eof = true;
				// FIXME: this should be distinct from an empty line when hit at the beginning
				return false;
			//break;
			case InputEvent.Type.KeyboardEvent:
				auto ev = e.keyboardEvent;
				if(ev.pressed == false)
					return true;
				/* Insert the character (unless it is backspace, tab, or some other control char) */
				auto ch = ev.which;
				switch(ch) {
					case KeyboardEvent.ProprietaryPseudoKeys.SelectNone:
						selectNone();
						redraw();
					break;
					version(Windows) case 'z', 26: { // and this is really for Windows
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						goto case;
					}
					case 'd', 4: // ctrl+d will also send a newline-equivalent
						if(ev.modifierState & ModifierState.alt) {
							// gnu alias for kill word (also on ctrl+backspace)
							justHitTab = false;
							lineChanged = true;
							killWordForward();
							justKilled = true;
							redraw();
							break;
						}
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						if(line.length == 0)
							eof = true;
						justHitTab = justKilled = false;
						return false; // indicate end of line so it doesn't maintain the buffer thinking it was ctrl+enter
					case '\r':
					case '\n':
						justHitTab = justKilled = false;
						if(ev.modifierState & ModifierState.control) {
							goto case KeyboardEvent.Key.F9;
						}
						if(ev.modifierState & ModifierState.shift) {
							addChar('\n');
							redraw();
							break;
						}
						return false;
					case '\t':
						justKilled = false;

						if(ev.modifierState & ModifierState.shift) {
							justHitTab = false;
							addChar('\t');
							redraw();
							break;
						}

						// I want to hide the private bits from the other functions, but retain them across completions,
						// which is why it does it on a copy here. Could probably be more efficient, but meh.
						auto line = this.line.dup;
						line[] &= cast(dchar) ~PRIVATE_BITS_MASK;

						auto relevantLineSection = line[0 .. cursorPosition];
						auto start = tabCompleteStartPoint(relevantLineSection, line[cursorPosition .. $]);
						relevantLineSection = relevantLineSection[start .. $];
						auto possibilities = filterTabCompleteList(tabComplete(relevantLineSection, line[cursorPosition .. $]), start);
						import std.utf;

						if(possibilities.length == 1) {
							auto toFill = possibilities[0][codeLength!char(relevantLineSection) .. $];
							if(toFill.length) {
								addString(toFill);
								redraw();
							} else {
								auto help = this.tabCompleteHelp(possibilities[0]);
								if(help.length) {
									showIndividualHelp(help);
									updateCursorPosition();
									redraw();
								}
							}
							justHitTab = false;
						} else {
							if(justHitTab) {
								justHitTab = false;
								showTabCompleteList(possibilities);
							} else {
								justHitTab = true;
								/* fill it in with as much commonality as there is amongst all the suggestions */
								auto suggestion = this.suggestion(possibilities);
								if(suggestion.length) {
									addString(suggestion);
									redraw();
								}
							}
						}
					break;
					case '\b':
						justHitTab = false;
						// i use control for delete word, but gnu uses alt. so this allows both
						if(ev.modifierState & (ModifierState.control | ModifierState.alt)) {
							lineChanged = true;
							killWord();
							justKilled = true;
							redraw();
						} else if(cursorPosition) {
							lineChanged = true;
							justKilled = false;
							cursorPosition--;
							for(int i = cursorPosition; i < line.length - 1; i++)
								line[i] = line[i + 1];
							line = line[0 .. $ - 1];
							line.assumeSafeAppend();

							if(multiLineMode) {
								// FIXME
							} else {
								if(horizontalScrollPosition > cursorPosition - 1)
									horizontalScrollPosition = cursorPosition - 1 - availableLineLength();
								if(horizontalScrollPosition < 0)
									horizontalScrollPosition = 0;
							}

							redraw();
						}
						phantomCursorX = 0;
					break;
					case KeyboardEvent.Key.escape:
						justHitTab = justKilled = false;
						if(multiLineMode)
							multiLineMode = false;
						else {
							cursorPosition = 0;
							horizontalScrollPosition = 0;
							line = line[0 .. 0];
							line.assumeSafeAppend();
						}
						redraw();
					break;
					case KeyboardEvent.Key.F1:
						justHitTab = justKilled = false;
						showHelp();
					break;
					case KeyboardEvent.Key.F2:
						justHitTab = justKilled = false;

						if(ev.modifierState & ModifierState.control) {
							toggleMultiLineMode();
							break;
						}

						line[] &= cast(dchar) ~PRIVATE_BITS_MASK;
						auto got = editLineInEditor(line, cursorPosition);
						if(got !is null) {
							line = got;
							if(cursorPosition > line.length)
								cursorPosition = cast(int) line.length;
							if(horizontalScrollPosition > line.length)
								horizontalScrollPosition = cast(int) line.length;
							positionCursor();
							redraw();
						}
					break;
					case '(':
						if(!(ev.modifierState & ModifierState.alt))
							goto default;
						justHitTab = justKilled = false;
						addChar('(');
						addChar(cast(dchar) (')' | PRIVATE_BITS_MASK));
						charBack();
						redraw();
					break;
					case 'l', 12:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						goto case;
					case KeyboardEvent.Key.F5:
						// FIXME: I might not want to do this on full screen programs,
						// but arguably the application should just hook the event then.
						terminal.clear();
						updateCursorPosition();
						redraw();
					break;
					case 'r', 18:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						goto case;
					case KeyboardEvent.Key.F3:
						justHitTab = justKilled = false;
						// search in history
						// FIXME: what about search in completion too?
						line[] &= cast(dchar) ~PRIVATE_BITS_MASK;
						supplementalGetter = new HistorySearchLineGetter(this);
						supplementalGetter.startGettingLine();
						supplementalGetter.redraw();
					break;
					case 'u', 21:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						goto case;
					case KeyboardEvent.Key.F4:
						killText(line);
						line = [];
						cursorPosition = 0;
						justHitTab = false;
						justKilled = true;
						redraw();
					break;
					// btw alt+enter could be alias for F9?
					case KeyboardEvent.Key.F9:
						justHitTab = justKilled = false;
						// compile and run analog; return the current string
						// but keep the buffer the same

						maintainBuffer = true;
						return false;
					case '5', 0x1d: // ctrl+5, because of vim % shortcut
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						justHitTab = justKilled = false;
						// FIXME: would be cool if this worked with quotes and such too
						// FIXME: in insert mode prolly makes sense to look at the position before the cursor tbh
						if(cursorPosition >= 0 && cursorPosition < line.length) {
							dchar at = line[cursorPosition] & ~PRIVATE_BITS_MASK;
							int direction;
							dchar lookFor;
							switch(at) {
								case '(': direction = 1; lookFor = ')'; break;
								case '[': direction = 1; lookFor = ']'; break;
								case '{': direction = 1; lookFor = '}'; break;
								case ')': direction = -1; lookFor = '('; break;
								case ']': direction = -1; lookFor = '['; break;
								case '}': direction = -1; lookFor = '{'; break;
								default:
							}
							if(direction) {
								int pos = cursorPosition;
								int count;
								while(pos >= 0 && pos < line.length) {
									auto lp = line[pos] & ~PRIVATE_BITS_MASK;
									if(lp == at)
										count++;
									if(lp == lookFor)
										count--;
									if(count == 0) {
										cursorPosition = pos;
										redraw();
										break;
									}
									pos += direction;
								}
							}
						}
					break;

					// FIXME: should be able to update the selection with shift+arrows as well as mouse
					// if terminal emulator supports this, it can formally select it to the buffer for copy
					// and sending to primary on X11 (do NOT do it on Windows though!!!)
					case 'b', 2:
						if(ev.modifierState & ModifierState.alt)
							wordBack();
						else if(ev.modifierState & ModifierState.control)
							charBack();
						else
							goto default;
						justHitTab = justKilled = false;
						redraw();
					break;
					case 'f', 6:
						if(ev.modifierState & ModifierState.alt)
							wordForward();
						else if(ev.modifierState & ModifierState.control)
							charForward();
						else
							goto default;
						justHitTab = justKilled = false;
						redraw();
					break;
					case KeyboardEvent.Key.LeftArrow:
						justHitTab = justKilled = false;
						phantomCursorX = 0;

						/*
						if(ev.modifierState & ModifierState.shift)
							setSelectionAnchorToCursor();
						*/

						if(ev.modifierState & ModifierState.control)
							wordBack();
						else if(cursorPosition)
							charBack();

						/*
						if(ev.modifierState & ModifierState.shift)
							extendSelectionToCursor();
						*/

						redraw();
					break;
					case KeyboardEvent.Key.RightArrow:
						justHitTab = justKilled = false;
						if(ev.modifierState & ModifierState.control)
							wordForward();
						else
							charForward();
						redraw();
					break;
					case 'p', 16:
						if(ev.modifierState & ModifierState.control)
							goto case;
						goto default;
					case KeyboardEvent.Key.UpArrow:
						justHitTab = justKilled = false;
						if(multiLineMode) {
							lineBackward();
							maybePositionCursor();
						} else
							loadFromHistory(currentHistoryViewPosition + 1);
						redraw();
					break;
					case 'n', 14:
						if(ev.modifierState & ModifierState.control)
							goto case;
						goto default;
					case KeyboardEvent.Key.DownArrow:
						justHitTab = justKilled = false;
						if(multiLineMode) {
							lineForward();
							maybePositionCursor();
						} else
							loadFromHistory(currentHistoryViewPosition - 1);
						redraw();
					break;
					case KeyboardEvent.Key.PageUp:
						justHitTab = justKilled = false;
						if(multiLineMode)
							pageBackward();
						else
							loadFromHistory(cast(int) history.length);
						redraw();
					break;
					case KeyboardEvent.Key.PageDown:
						justHitTab = justKilled = false;
						if(multiLineMode)
							pageForward();
						else
							loadFromHistory(0);
						redraw();
					break;
					case 'a', 1: // this one conflicts with Windows-style select all...
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						if(ev.modifierState & ModifierState.shift) {
							// ctrl+shift+a will select all...
							// for now I will have it just copy to clipboard but later once I get the time to implement full selection handling, I'll change it
							terminal.requestCopyToClipboard(lineAsString());
							break;
						}
						goto case;
					case KeyboardEvent.Key.Home:
						justHitTab = justKilled = false;
						if(multiLineMode) {
							backwardToNewline();
						} else {
							cursorPosition = 0;
						}
						horizontalScrollPosition = 0;
						redraw();
					break;
					case 'e', 5:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						goto case;
					case KeyboardEvent.Key.End:
						justHitTab = justKilled = false;
						if(multiLineMode) {
							forwardToNewLine();
						} else {
							cursorPosition = cast(int) line.length;
							scrollToEnd();
						}
						redraw();
					break;
					case 'v', 22:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						justKilled = false;
						if(rtti)
							rtti.requestPasteFromClipboard();
					break;
					case KeyboardEvent.Key.Insert:
						justHitTab = justKilled = false;
						if(ev.modifierState & ModifierState.shift) {
							// paste

							// shift+insert = request paste
							// ctrl+insert = request copy. but that needs a selection

							// those work on Windows!!!! and many linux TEs too.
							// but if it does make it here, we'll attempt it at this level
							if(rtti)
								rtti.requestPasteFromClipboard();
						} else if(ev.modifierState & ModifierState.control) {
							// copy
							// FIXME we could try requesting it though this control unlikely to even come
						} else {
							insertMode = !insertMode;

							if(insertMode)
								terminal.cursor = TerminalCursor.insert;
							else
								terminal.cursor = TerminalCursor.block;
						}
					break;
					case KeyboardEvent.Key.Delete:
						justHitTab = false;
						if(ev.modifierState & ModifierState.control) {
							deleteToEndOfLine();
							justKilled = true;
						} else {
							deleteChar();
							justKilled = false;
						}
						redraw();
					break;
					case 'k', 11:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						deleteToEndOfLine();
						justHitTab = false;
						justKilled = true;
						redraw();
					break;
					case 'w', 23:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						killWord();
						justHitTab = false;
						justKilled = true;
						redraw();
					break;
					case 'y', 25:
						if(!(ev.modifierState & ModifierState.control))
							goto default;
						justHitTab = justKilled = false;
						foreach(c; killBuffer)
							addChar(c);
						redraw();
					break;
					default:
						justHitTab = justKilled = false;
						if(e.keyboardEvent.isCharacter) {

							// overstrike an auto-inserted thing if that's right there
							if(cursorPosition < line.length)
							if(line[cursorPosition] & PRIVATE_BITS_MASK) {
								if((line[cursorPosition] & ~PRIVATE_BITS_MASK) == ch) {
									line[cursorPosition] = ch;
									cursorPosition++;
									redraw();
									break;
								}
							}



							// the ordinary add, of course
							addChar(ch);


							// and auto-insert a closing pair if appropriate
							auto autoChars = enableAutoCloseBrackets();
							bool found = false;
							foreach(idx, dchar ac; autoChars) {
								if(found) {
									addChar(ac | PRIVATE_BITS_MASK);
									charBack();
									break;
								}
								if((idx&1) == 0 && ac == ch)
									found = true;
							}
						}
						redraw();
				}
			break;
			case InputEvent.Type.PasteEvent:
				justHitTab = false;
				if(pastePreprocessor)
					addString(pastePreprocessor(e.pasteEvent.pastedText));
				else
					addString(defaultPastePreprocessor(e.pasteEvent.pastedText));
				redraw();
			break;
			case InputEvent.Type.MouseEvent:
				/* Clicking with the mouse to move the cursor is so much easier than arrowing
				   or even emacs/vi style movements much of the time, so I'ma support it. */

				auto me = e.mouseEvent;
				if(me.eventType == MouseEvent.Type.Pressed) {
					if(me.buttons & MouseEvent.Button.Left) {
						if(multiLineMode) {
							// FIXME
						} else if(me.y == startOfLineY) { // single line only processes on itself
							int p = me.x - startOfLineX - promptLength + horizontalScrollPosition;
							if(p >= 0 && p < line.length) {
								justHitTab = false;
								cursorPosition = p;
								redraw();
							}
						}
					}
					if(me.buttons & MouseEvent.Button.Middle) {
						if(rtti)
							rtti.requestPasteFromPrimary();
					}
				}
			break;
			case InputEvent.Type.LinkEvent:
				if(handleLinkEvent !is null)
					handleLinkEvent(e.linkEvent, this);
			break;
			case InputEvent.Type.SizeChangedEvent:
				/* We'll adjust the bounding box. If you don't like this, handle SizeChangedEvent
				   yourself and then don't pass it to this function. */
				// FIXME
				initializeWithSize();
			break;
			case InputEvent.Type.CustomEvent:
				if(auto rce = cast(RunnableCustomEvent) e.customEvent)
					rce.run();
			break;
			case InputEvent.Type.UserInterruptionEvent:
				/* I'll take this as canceling the line. */
				throw new UserInterruptionException();
			//break;
			case InputEvent.Type.HangupEvent:
				/* I'll take this as canceling the line. */
				throw new HangupException();
			//break;
			default:
				/* ignore. ideally it wouldn't be passed to us anyway! */
		}

		return true;
	}

	/++
		Gives a convenience hook for subclasses to handle my terminal's hyperlink extension.


		You can also handle these by filtering events before you pass them to [workOnLine].
		That's still how I recommend handling any overrides or custom events, but making this
		a delegate is an easy way to inject handlers into an otherwise linear i/o application.

		Does nothing if null.

		It passes the event as well as the current line getter to the delegate. You may simply
		`lg.addString(ev.text); lg.redraw();` in some cases.

		History:
			Added April 2, 2021.

		See_Also:
			[Terminal.hyperlink]

			[TerminalCapabilities.arsdHyperlinks]
	+/
	void delegate(LinkEvent ev, LineGetter lg) handleLinkEvent;

	/++
		Replaces the line currently being edited with the given line and positions the cursor inside it.

		History:
			Added November 27, 2020.
	+/
	void replaceLine(const scope dchar[] line) {
		if(this.line.length < line.length)
			this.line.length = line.length;
		else
			this.line = this.line[0 .. line.length];
		this.line.assumeSafeAppend();
		this.line[] = line[];
		if(cursorPosition > line.length)
			cursorPosition = cast(int) line.length;
		if(multiLineMode) {
			// FIXME?
			horizontalScrollPosition = 0;
			verticalScrollPosition = 0;
		} else {
			if(horizontalScrollPosition > line.length)
				horizontalScrollPosition = cast(int) line.length;
		}
		positionCursor();
	}

	/// ditto
	void replaceLine(const scope char[] line) {
		if(line.length >= 255) {
			import std.conv;
			replaceLine(to!dstring(line));
			return;
		}
		dchar[255] tmp;
		size_t idx;
		foreach(dchar c; line) {
			tmp[idx++] = c;
		}

		replaceLine(tmp[0 .. idx]);
	}

	/++
		Gets the current line buffer as a duplicated string.

		History:
			Added January 25, 2021
	+/
	string lineAsString() {
		import std.conv;

		// FIXME: I should prolly not do this on the internal copy but it isn't a huge deal
		line[] &= cast(dchar) ~PRIVATE_BITS_MASK;

		return to!string(line);
	}

	///
	string finishGettingLine() {
		import std.conv;


		if(multiLineMode)
			multiLineMode = false;

		line[] &= cast(dchar) ~PRIVATE_BITS_MASK;

		auto f = to!string(line);
		auto history = historyFilter(f);
		if(history !is null) {
			this.history ~= history;
			if(this.historyCommitMode == HistoryCommitMode.afterEachLine)
				appendHistoryToFile(history);
		}

		// FIXME: we should hide the cursor if it was hidden in the call to startGettingLine

		// also need to reset the color going forward
		terminal.color(Color.DEFAULT, Color.DEFAULT);

		return eof ? null : f.length ? f : "";
	}
}

class HistorySearchLineGetter : LineGetter {
	LineGetter basedOn;
	string sideDisplay;
	this(LineGetter basedOn) {
		this.basedOn = basedOn;
		super(basedOn.terminal);
	}

	override void updateCursorPosition() {
		super.updateCursorPosition();
		startOfLineX = basedOn.startOfLineX;
		startOfLineY = basedOn.startOfLineY;
	}

	override void initializeWithSize(bool firstEver = false) {
		if(maximumDrawWidth > 60)
			this.prompt = "(history search): \"";
		else
			this.prompt = "(hs): \"";
		super.initializeWithSize(firstEver);
	}

	override int availableLineLength() {
		return maximumDrawWidth / 2 - promptLength - 1;
	}

	override void loadFromHistory(int howFarBack) {
		currentHistoryViewPosition = howFarBack;
		reloadSideDisplay();
	}

	int highlightBegin;
	int highlightEnd;

	void reloadSideDisplay() {
		import std.string;
		import std.range;
		int counter = currentHistoryViewPosition;

		string lastHit;
		int hb, he;
		if(line.length)
		foreach_reverse(item; basedOn.history) {
			auto idx = item.indexOf(line);
			if(idx != -1) {
				hb = cast(int) idx;
				he = cast(int) (idx + line.walkLength);
				lastHit = item;
				if(counter)
					counter--;
				else
					break;
			}
		}
		sideDisplay = lastHit;
		highlightBegin = hb;
		highlightEnd = he;
		redraw();
	}


	bool redrawQueued = false;
	override void redraw() {
		redrawQueued = true;
	}

	void actualRedraw() {
		auto cri = coreRedraw();
		terminal.write("\" ");

		int available = maximumDrawWidth / 2 - 1;
		auto used = prompt.length + cri.written + 3 /* the write above plus a space */;
		if(used < available)
			available += available - used;

		//terminal.moveTo(maximumDrawWidth / 2, startOfLineY);
		Drawer drawer = Drawer(this);
		drawer.lineLength = available;
		drawer.drawContent(sideDisplay, highlightBegin, highlightEnd);

		cri.written += drawer.written;

		finalizeRedraw(cri);
	}

	override bool workOnLine(InputEvent e, RealTimeConsoleInput* rtti = null) {
		scope(exit) {
			if(redrawQueued) {
				actualRedraw();
				redrawQueued = false;
			}
		}
		if(e.type == InputEvent.Type.KeyboardEvent) {
			auto ev = e.keyboardEvent;
			if(ev.pressed == false)
				return true;
			/* Insert the character (unless it is backspace, tab, or some other control char) */
			auto ch = ev.which;
			switch(ch) {
				// modification being the search through history commands
				// should just keep searching, not endlessly nest.
				case 'r', 18:
					if(!(ev.modifierState & ModifierState.control))
						goto default;
					goto case;
				case KeyboardEvent.Key.F3:
					e.keyboardEvent.which = KeyboardEvent.Key.UpArrow;
				break;
				case KeyboardEvent.Key.escape:
					sideDisplay = null;
					return false; // cancel
				default:
			}
		}
		if(super.workOnLine(e, rtti)) {
			if(lineChanged) {
				currentHistoryViewPosition = 0;
				reloadSideDisplay();
				lineChanged = false;
			}
			return true;
		}
		return false;
	}

	override void startGettingLine() {
		super.startGettingLine();
		this.line = basedOn.line.dup;
		cursorPosition = cast(int) this.line.length;
		startOfLineX = basedOn.startOfLineX;
		startOfLineY = basedOn.startOfLineY;
		positionCursor();
		reloadSideDisplay();
	}

	override string finishGettingLine() {
		auto got = super.finishGettingLine();

		if(sideDisplay.length)
			basedOn.replaceLine(sideDisplay);

		return got;
	}
}

/// Adds default constructors that just forward to the superclass
mixin template LineGetterConstructors() {
	this(Terminal* tty, string historyFilename = null) {
		super(tty, historyFilename);
	}
}

/// This is a line getter that customizes the tab completion to
/// fill in file names separated by spaces, like a command line thing.
class FileLineGetter : LineGetter {
	mixin LineGetterConstructors;

	/// You can set this property to tell it where to search for the files
	/// to complete.
	string searchDirectory = ".";

	override size_t tabCompleteStartPoint(in dchar[] candidate, in dchar[] afterCursor) {
		import std.string;
		return candidate.lastIndexOf(" ") + 1;
	}

	override protected string[] tabComplete(in dchar[] candidate, in dchar[] afterCursor) {
		import std.file, std.conv, std.algorithm, std.string;

		string[] list;
		foreach(string name; dirEntries(searchDirectory, SpanMode.breadth)) {
			// both with and without the (searchDirectory ~ "/")
			list ~= name[searchDirectory.length + 1 .. $];
			list ~= name[0 .. $];
		}

		return list;
	}
}

/+
class FullscreenEditor {

}
+/


version(Windows) {
	// to get the directory for saving history in the line things
	enum CSIDL_APPDATA = 26;
	extern(Windows) HRESULT SHGetFolderPathA(HWND, int, HANDLE, DWORD, LPSTR);
}





/* Like getting a line, printing a lot of lines is kinda important too, so I'm including
   that widget here too. */


/++
	The ScrollbackBuffer is a writable in-memory terminal that can be drawn to a real [Terminal]
	and maintain some internal position state by handling events. It is your responsibility to
	draw it (using the [drawInto] method) and dispatch events to its [handleEvent] method (if you
	want to, you can also just call the methods yourself).


	I originally wrote this to support my irc client and some of the features are geared toward
	helping with that (for example, [name] and [demandsAttention]), but the main thrust is to
	support either tabs or sub-sections of the terminal having their own output that can be displayed
	and scrolled back independently while integrating with some larger application.

	History:
		Committed to git on August 4, 2015.

		Cleaned up and documented on May 25, 2021.
+/
struct ScrollbackBuffer {
	/++
		A string you can set and process on your own. The library only sets it from the
		constructor, then leaves it alone.

		In my irc client, I use this as the title of a tab I draw to indicate separate
		conversations.
	+/
	public string name;
	/++
		A flag you can set and process on your own. All the library does with it is
		set it to false when it handles an event, otherwise you can do whatever you
		want with it.

		In my irc client, I use this to add a * to the tab to indicate new messages.
	+/
	public bool demandsAttention;

	/++
		The coordinates of the last [drawInto]
	+/
	int x, y, width, height;

	private CircularBuffer!Line lines;
	private bool eol; // if the last line had an eol, next append needs a new line. doing this means we won't have a spurious blank line at the end of the draw-in

	/++
		Property to control the current scrollback position. 0 = latest message
		at bottom of screen.

		See_Also: [scrollToBottom], [scrollToTop], [scrollUp], [scrollDown], [scrollTopPosition]
	+/
	@property int scrollbackPosition() const pure @nogc nothrow @safe {
		return scrollbackPosition_;
	}

	/// ditto
	private @property void scrollbackPosition(int p) pure @nogc nothrow @safe {
		scrollbackPosition_ = p;
	}

	private int scrollbackPosition_;

	/++
		This is the color it uses to clear the screen.

		History:
			Added May 26, 2021
	+/
	public Color defaultForeground = Color.DEFAULT;
	/// ditto
	public Color defaultBackground = Color.DEFAULT;

	private int foreground_ = Color.DEFAULT, background_ = Color.DEFAULT;

	/++
		The name is for your own use only. I use the name as a tab title but you could ignore it and just pass `null` too.
	+/
	this(string name) {
		this.name = name;
	}

	/++
		Writing into the scrollback buffer can be done with the same normal functions.

		Note that you will have to call [redraw] yourself to make this actually appear on screen.
	+/
	void write(T...)(T t) {
		import std.conv : text;
		addComponent(text(t), foreground_, background_, null);
	}

	/// ditto
	void writeln(T...)(T t) {
		write(t, "\n");
	}

	/// ditto
	void writef(T...)(string fmt, T t) {
		import std.format: format;
		write(format(fmt, t));
	}

	/// ditto
	void writefln(T...)(string fmt, T t) {
		writef(fmt, t, "\n");
	}

	/// ditto
	void color(int foreground, int background) {
		this.foreground_ = foreground;
		this.background_ = background;
	}

	/++
		Clears the scrollback buffer.
	+/
	void clear() {
		lines.clear();
		clickRegions = null;
		scrollbackPosition_ = 0;
	}

	/++

	+/
	void addComponent(string text, int foreground, int background, bool delegate() onclick) {
		addComponent(LineComponent(text, foreground, background, onclick));
	}

	/++

	+/
	void addComponent(LineComponent component) {
		if(lines.length == 0 || eol) {
			addLine();
			eol = false;
		}
		bool first = true;
		import std.algorithm;

		if(component.text.length && component.text[$-1] == '\n') {
			eol = true;
			component.text = component.text[0 .. $ - 1];
		}

		foreach(t; splitter(component.text, "\n")) {
			if(!first) addLine();
			first = false;
			auto c = component;
			c.text = t;
			lines[$-1].components ~= c;
		}
	}

	/++
		Adds an empty line.
	+/
	void addLine() {
		lines ~= Line();
		if(scrollbackPosition_) // if the user is scrolling back, we want to keep them basically centered where they are
			scrollbackPosition_++;
	}

	/++
		This is what [writeln] actually calls.

		Using this exclusively though can give you more control, especially over the trailing \n.
	+/
	void addLine(string line) {
		lines ~= Line([LineComponent(line)]);
		if(scrollbackPosition_) // if the user is scrolling back, we want to keep them basically centered where they are
			scrollbackPosition_++;
	}

	/++
		Adds a line by components without affecting scrollback.

		History:
			Added May 17, 2022
	+/
	void addLine(LineComponent[] components...) {
		lines ~= Line(components.dup);
	}

	/++
		Scrolling controls.

		Notice that `scrollToTop`  needs width and height to know how to word wrap it to determine the number of lines present to scroll back.
	+/
	void scrollUp(int lines = 1) {
		scrollbackPosition_ += lines;
		//if(scrollbackPosition >= this.lines.length)
		//	scrollbackPosition = cast(int) this.lines.length - 1;
	}

	/// ditto
	void scrollDown(int lines = 1) {
		scrollbackPosition_ -= lines;
		if(scrollbackPosition_ < 0)
			scrollbackPosition_ = 0;
	}

	/// ditto
	void scrollToBottom() {
		scrollbackPosition_ = 0;
	}

	/// ditto
	void scrollToTop(int width, int height) {
		scrollbackPosition_ = scrollTopPosition(width, height);
	}


	/++
		You can construct these to get more control over specifics including
		setting RGB colors.

		But generally just using [write] and friends is easier.
	+/
	struct LineComponent {
		private string text;
		private bool isRgb;
		private union {
			int color;
			RGB colorRgb;
		}
		private union {
			int background;
			RGB backgroundRgb;
		}
		private bool delegate() onclick; // return true if you need to redraw

		// 16 color ctor
		this(string text, int color = Color.DEFAULT, int background = Color.DEFAULT, bool delegate() onclick = null) {
			this.text = text;
			this.color = color;
			this.background = background;
			this.onclick = onclick;
			this.isRgb = false;
		}

		// true color ctor
		this(string text, RGB colorRgb, RGB backgroundRgb = RGB(0, 0, 0), bool delegate() onclick = null) {
			this.text = text;
			this.colorRgb = colorRgb;
			this.backgroundRgb = backgroundRgb;
			this.onclick = onclick;
			this.isRgb = true;
		}
	}

	private struct Line {
		LineComponent[] components;
		int length() {
			int l = 0;
			foreach(c; components)
				l += c.text.length;
			return l;
		}
	}

	/++
		This is an internal helper for its scrollback buffer.

		It is fairly generic and I might move it somewhere else some day.

		It has a compile-time specified limit of 8192 entries.
	+/
	static struct CircularBuffer(T) {
		T[] backing;

		enum maxScrollback = 8192; // as a power of 2, i hope the compiler optimizes the % below to a simple bit mask...

		int start;
		int length_;

		void clear() {
			backing = null;
			start = 0;
			length_ = 0;
		}

		size_t length() {
			return length_;
		}

		void opOpAssign(string op : "~")(T line) {
			if(length_ < maxScrollback) {
				backing.assumeSafeAppend();
				backing ~= line;
				length_++;
			} else {
				backing[start] = line;
				start++;
				if(start == maxScrollback)
					start = 0;
			}
		}

		ref T opIndex(int idx) {
			return backing[(start + idx) % maxScrollback];
		}
		ref T opIndex(Dollar idx) {
			return backing[(start + (length + idx.offsetFromEnd)) % maxScrollback];
		}

		CircularBufferRange opSlice(int startOfIteration, Dollar end) {
			return CircularBufferRange(&this, startOfIteration, cast(int) length - startOfIteration + end.offsetFromEnd);
		}
		CircularBufferRange opSlice(int startOfIteration, int end) {
			return CircularBufferRange(&this, startOfIteration, end - startOfIteration);
		}
		CircularBufferRange opSlice() {
			return CircularBufferRange(&this, 0, cast(int) length);
		}

		static struct CircularBufferRange {
			CircularBuffer* item;
			int position;
			int remaining;
			this(CircularBuffer* item, int startOfIteration, int count) {
				this.item = item;
				position = startOfIteration;
				remaining = count;
			}

			ref T front() { return (*item)[position]; }
			bool empty() { return remaining <= 0; }
			void popFront() {
				position++;
				remaining--;
			}

			ref T back() { return (*item)[remaining - 1 - position]; }
			void popBack() {
				remaining--;
			}
		}

		static struct Dollar {
			int offsetFromEnd;
			Dollar opBinary(string op : "-")(int rhs) {
				return Dollar(offsetFromEnd - rhs);
			}
		}
		Dollar opDollar() { return Dollar(0); }
	}

	/++
		Given a size, how far would you have to scroll back to get to the top?

		Please note that this is O(n) with the length of the scrollback buffer.
	+/
	int scrollTopPosition(int width, int height) {
		int lineCount;

		foreach_reverse(line; lines) {
			int written = 0;
			comp_loop: foreach(cidx, component; line.components) {
				auto towrite = component.text;
				foreach(idx, dchar ch; towrite) {
					if(written >= width) {
						lineCount++;
						written = 0;
					}

					if(ch == '\t')
						written += 8; // FIXME
					else
						written++;
				}
			}
			lineCount++;
		}

		//if(lineCount > height)
			return lineCount - height;
		//return 0;
	}

	/++
		Draws the current state into the given terminal inside the given bounding box.

		Also updates its internal position and click region data which it uses for event filtering in [handleEvent].
	+/
	void drawInto(Terminal* terminal, in int x = 0, in int y = 0, int width = 0, int height = 0) {
		if(lines.length == 0)
			return;

		if(width == 0)
			width = terminal.width;
		if(height == 0)
			height = terminal.height;

		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;

		/* We need to figure out how much is going to fit
		   in a first pass, so we can figure out where to
		   start drawing */

		int remaining = height + scrollbackPosition;
		int start = cast(int) lines.length;
		int howMany = 0;

		bool firstPartial = false;

		static struct Idx {
			size_t cidx;
			size_t idx;
		}

		Idx firstPartialStartIndex;

		// this is private so I know we can safe append
		clickRegions.length = 0;
		clickRegions.assumeSafeAppend();

		// FIXME: should prolly handle \n and \r in here too.

		// we'll work backwards to figure out how much will fit...
		// this will give accurate per-line things even with changing width and wrapping
		// while being generally efficient - we usually want to show the end of the list
		// anyway; actually using the scrollback is a bit of an exceptional case.

		// It could probably do this instead of on each redraw, on each resize or insertion.
		// or at least cache between redraws until one of those invalidates it.
		foreach_reverse(line; lines) {
			int written = 0;
			int brokenLineCount;
			Idx[16] lineBreaksBuffer;
			Idx[] lineBreaks = lineBreaksBuffer[];
			comp_loop: foreach(cidx, component; line.components) {
				auto towrite = component.text;
				foreach(idx, dchar ch; towrite) {
					if(written >= width) {
						if(brokenLineCount == lineBreaks.length)
							lineBreaks ~= Idx(cidx, idx);
						else
							lineBreaks[brokenLineCount] = Idx(cidx, idx);

						brokenLineCount++;

						written = 0;
					}

					if(ch == '\t')
						written += 8; // FIXME
					else
						written++;
				}
			}

			lineBreaks = lineBreaks[0 .. brokenLineCount];

			foreach_reverse(lineBreak; lineBreaks) {
				if(remaining == 1) {
					firstPartial = true;
					firstPartialStartIndex = lineBreak;
					break;
				} else {
					remaining--;
				}
				if(remaining <= 0)
					break;
			}

			remaining--;

			start--;
			howMany++;
			if(remaining <= 0)
				break;
		}

		// second pass: actually draw it
		int linePos = remaining;

		foreach(line; lines[start .. start + howMany]) {
			int written = 0;

			if(linePos < 0) {
				linePos++;
				continue;
			}

			terminal.moveTo(x, y + ((linePos >= 0) ? linePos : 0));

			auto todo = line.components;

			if(firstPartial) {
				todo = todo[firstPartialStartIndex.cidx .. $];
			}

			foreach(ref component; todo) {
				if(component.isRgb)
					terminal.setTrueColor(component.colorRgb, component.backgroundRgb);
				else
					terminal.color(
						component.color == Color.DEFAULT ? defaultForeground : component.color,
						component.background == Color.DEFAULT ? defaultBackground : component.background,
					);
				auto towrite = component.text;

				again:

				if(linePos >= height)
					break;

				if(firstPartial) {
					towrite = towrite[firstPartialStartIndex.idx .. $];
					firstPartial = false;
				}

				foreach(idx, dchar ch; towrite) {
					if(written >= width) {
						clickRegions ~= ClickRegion(&component, terminal.cursorX, terminal.cursorY, written);
						terminal.write(towrite[0 .. idx]);
						towrite = towrite[idx .. $];
						linePos++;
						written = 0;
						terminal.moveTo(x, y + linePos);
						goto again;
					}

					if(ch == '\t')
						written += 8; // FIXME
					else
						written++;
				}

				if(towrite.length) {
					clickRegions ~= ClickRegion(&component, terminal.cursorX, terminal.cursorY, written);
					terminal.write(towrite);
				}
			}

			if(written < width) {
				terminal.color(defaultForeground, defaultBackground);
				foreach(i; written .. width)
					terminal.write(" ");
			}

			linePos++;

			if(linePos >= height)
				break;
		}

		if(linePos < height) {
			terminal.color(defaultForeground, defaultBackground);
			foreach(i; linePos .. height) {
				if(i >= 0 && i < height) {
					terminal.moveTo(x, y + i);
					foreach(w; 0 .. width)
						terminal.write(" ");
				}
			}
		}
	}

	private struct ClickRegion {
		LineComponent* component;
		int xStart;
		int yStart;
		int length;
	}
	private ClickRegion[] clickRegions;

	/++
		Default event handling for this widget. Call this only after drawing it into a rectangle
		and only if the event ought to be dispatched to it (which you determine however you want;
		you could dispatch all events to it, or perhaps filter some out too)

		Returns: true if it should be redrawn
	+/
	bool handleEvent(InputEvent e) {
		final switch(e.type) {
			case InputEvent.Type.LinkEvent:
				// meh
			break;
			case InputEvent.Type.KeyboardEvent:
				auto ev = e.keyboardEvent;

				demandsAttention = false;

				switch(ev.which) {
					case KeyboardEvent.Key.UpArrow:
						scrollUp();
						return true;
					case KeyboardEvent.Key.DownArrow:
						scrollDown();
						return true;
					case KeyboardEvent.Key.PageUp:
						if(ev.modifierState & ModifierState.control)
							scrollToTop(width, height);
						else
							scrollUp(height);
						return true;
					case KeyboardEvent.Key.PageDown:
						if(ev.modifierState & ModifierState.control)
							scrollToBottom();
						else
							scrollDown(height);
						return true;
					default:
						// ignore
				}
			break;
			case InputEvent.Type.MouseEvent:
				auto ev = e.mouseEvent;
				if(ev.x >= x && ev.x < x + width && ev.y >= y && ev.y < y + height) {
					demandsAttention = false;
					// it is inside our box, so do something with it
					auto mx = ev.x - x;
					auto my = ev.y - y;

					if(ev.eventType == MouseEvent.Type.Pressed) {
						if(ev.buttons & MouseEvent.Button.Left) {
							foreach(region; clickRegions)
								if(ev.x >= region.xStart && ev.x < region.xStart + region.length && ev.y == region.yStart)
									if(region.component.onclick !is null)
										return region.component.onclick();
						}
						if(ev.buttons & MouseEvent.Button.ScrollUp) {
							scrollUp();
							return true;
						}
						if(ev.buttons & MouseEvent.Button.ScrollDown) {
							scrollDown();
							return true;
						}
					}
				} else {
					// outside our area, free to ignore
				}
			break;
			case InputEvent.Type.SizeChangedEvent:
				// (size changed might be but it needs to be handled at a higher level really anyway)
				// though it will return true because it probably needs redrawing anyway.
				return true;
			case InputEvent.Type.UserInterruptionEvent:
				throw new UserInterruptionException();
			case InputEvent.Type.HangupEvent:
				throw new HangupException();
			case InputEvent.Type.EndOfFileEvent:
				// ignore, not relevant to this
			break;
			case InputEvent.Type.CharacterEvent:
			case InputEvent.Type.NonCharacterKeyEvent:
				// obsolete, ignore them until they are removed
			break;
			case InputEvent.Type.CustomEvent:
			case InputEvent.Type.PasteEvent:
				// ignored, not relevant to us
			break;
		}

		return false;
	}
}


/++
	Thrown by [LineGetter] if the user pressed ctrl+c while it is processing events.
+/
class UserInterruptionException : Exception {
	this() { super("Ctrl+C"); }
}
/++
	Thrown by [LineGetter] if the terminal closes while it is processing input.
+/
class HangupException : Exception {
	this() { super("Terminal disconnected"); }
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

version(Demo_kbhit)
void main() {
	auto terminal = Terminal(ConsoleOutputType.linear);
	auto input = RealTimeConsoleInput(&terminal, ConsoleInputFlags.raw);

	int a;
	char ch = '.';
	while(a < 1000) {
		a++;
		if(a % terminal.width == 0) {
			terminal.write("\r");
			if(ch == '.')
				ch = ' ';
			else
				ch = '.';
		}

		if(input.kbhit())
			terminal.write(input.getch());
		else
			terminal.write(ch);

		terminal.flush();

		import core.thread;
		Thread.sleep(50.msecs);
	}
}

/*
	The Xterm palette progression is:
	[0, 95, 135, 175, 215, 255]

	So if I take the color and subtract 55, then div 40, I get
	it into one of these areas. If I add 20, I get a reasonable
	rounding.
*/

ubyte colorToXTermPaletteIndex(RGB color) {
	/*
		Here, I will round off to the color ramp or the
		greyscale. I will NOT use the bottom 16 colors because
		there's duplicates (or very close enough) to them in here
	*/

	if(color.r == color.g && color.g == color.b) {
		// grey - find one of them:
		if(color.r == 0) return 0;
		// meh don't need those two, let's simplify branche
		//if(color.r == 0xc0) return 7;
		//if(color.r == 0x80) return 8;
		// it isn't == 255 because it wants to catch anything
		// that would wrap the simple algorithm below back to 0.
		if(color.r >= 248) return 15;

		// there's greys in the color ramp too, but these
		// are all close enough as-is, no need to complicate
		// algorithm for approximation anyway

		return cast(ubyte) (232 + ((color.r - 8) / 10));
	}

	// if it isn't grey, it is color

	// the ramp goes blue, green, red, with 6 of each,
	// so just multiplying will give something good enough

	// will give something between 0 and 5, with some rounding
	auto r = (cast(int) color.r - 35) / 40;
	auto g = (cast(int) color.g - 35) / 40;
	auto b = (cast(int) color.b - 35) / 40;

	return cast(ubyte) (16 + b + g*6 + r*36);
}

/++
	Represents a 24-bit color.


	$(TIP You can convert these to and from [arsd.color.Color] using
	      `.tupleof`:

		---
	      	RGB rgb;
		Color c = Color(rgb.tupleof);
		---
	)
+/
struct RGB {
	ubyte r; ///
	ubyte g; ///
	ubyte b; ///
	// terminal can't actually use this but I want the value
	// there for assignment to an arsd.color.Color
	private ubyte a = 255;
}

// This is an approximation too for a few entries, but a very close one.
RGB xtermPaletteIndexToColor(int paletteIdx) {
	RGB color;

	if(paletteIdx < 16) {
		if(paletteIdx == 7)
			return RGB(0xc0, 0xc0, 0xc0);
		else if(paletteIdx == 8)
			return RGB(0x80, 0x80, 0x80);

		color.r = (paletteIdx & 0b001) ? ((paletteIdx & 0b1000) ? 0xff : 0x80) : 0x00;
		color.g = (paletteIdx & 0b010) ? ((paletteIdx & 0b1000) ? 0xff : 0x80) : 0x00;
		color.b = (paletteIdx & 0b100) ? ((paletteIdx & 0b1000) ? 0xff : 0x80) : 0x00;

	} else if(paletteIdx < 232) {
		// color ramp, 6x6x6 cube
		color.r = cast(ubyte) ((paletteIdx - 16) / 36 * 40 + 55);
		color.g = cast(ubyte) (((paletteIdx - 16) % 36) / 6 * 40 + 55);
		color.b = cast(ubyte) ((paletteIdx - 16) % 6 * 40 + 55);

		if(color.r == 55) color.r = 0;
		if(color.g == 55) color.g = 0;
		if(color.b == 55) color.b = 0;
	} else {
		// greyscale ramp, from 0x8 to 0xee
		color.r = cast(ubyte) (8 + (paletteIdx - 232) * 10);
		color.g = color.r;
		color.b = color.g;
	}

	return color;
}

Color approximate16Color(RGB color) {
	int c;
	c |= color.r > 64 ? 1 : 0;
	c |= color.g > 64 ? 2 : 0;
	c |= color.b > 64 ? 4 : 0;

	c |= (((color.r + color.g + color.b) / 3) > 80) ? Bright : 0;

	return cast(Color) c;
}

Color win32ConsoleColorToArsdTerminalColor(ushort c) {
	ushort v = cast(ushort) c;
	auto b1 = v & 1;
	auto b2 = v & 2;
	auto b3 = v & 4;
	auto b4 = v & 8;

	return cast(Color) ((b1 << 2) | b2 | (b3 >> 2) | b4);
}

ushort arsdTerminalColorToWin32ConsoleColor(Color c) {
	assert(c != Color.DEFAULT);

	ushort v = cast(ushort) c;
	auto b1 = v & 1;
	auto b2 = v & 2;
	auto b3 = v & 4;
	auto b4 = v & 8;

	return cast(ushort) ((b1 << 2) | b2 | (b3 >> 2) | b4);
}

version(TerminalDirectToEmulator) {

	void terminateTerminalProcess(T)(T threadId) {
		version(Posix) {
			pthread_kill(threadId, SIGQUIT); // or SIGKILL even?

			assert(0);
			//import core.sys.posix.pthread;
			//pthread_cancel(widget.term.threadId);
			//widget.term = null;
		} else version(Windows) {
			import core.sys.windows.winbase;
			import core.sys.windows.winnt;

			auto hnd = OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE, TRUE, GetCurrentProcessId());
			TerminateProcess(hnd, -1);
			assert(0);
		}
	}



	/++
		Indicates the TerminalDirectToEmulator features
		are present. You can check this with `static if`.

		$(WARNING
			This will cause the [Terminal] constructor to spawn a GUI thread with [arsd.minigui]/[arsd.simpledisplay].

			This means you can NOT use those libraries in your
			own thing without using the [arsd.simpledisplay.runInGuiThread] helper since otherwise the main thread is inaccessible, since having two different threads creating event loops or windows is undefined behavior with those libraries.
		)
	+/
	enum IntegratedEmulator = true;

	version(Windows) {
	private enum defaultFont = "Consolas";
	private enum defaultSize = 14;
	} else {
	private enum defaultFont = "monospace";
	private enum defaultSize = 12; // it is measured differently with fontconfig than core x and windows...
	}

	/++
		Allows customization of the integrated emulator window.
		You may change the default colors, font, and other aspects
		of GUI integration.

		Test for its presence before using with `static if(arsd.terminal.IntegratedEmulator)`.

		All settings here must be set BEFORE you construct any [Terminal] instances.

		History:
			Added March 7, 2020.
	+/
	struct IntegratedTerminalEmulatorConfiguration {
		/// Note that all Colors in here are 24 bit colors.
		alias Color = arsd.color.Color;

		/// Default foreground color of the terminal.
		Color defaultForeground = Color.black;
		/// Default background color of the terminal.
		Color defaultBackground = Color.white;

		/++
			Font to use in the window. It should be a monospace font,
			and your selection may not actually be used if not available on
			the user's system, in which case it will fallback to one.

			History:
				Implemented March 26, 2020

				On January 16, 2021, I changed the default to be a fancier
				font than the underlying terminalemulator.d uses ("monospace"
				on Linux and "Consolas" on Windows, though I will note
				that I do *not* guarantee this won't change.) On January 18,
				I changed the default size.

				If you want specific values for these things, you should set
				them in your own application.

				On January 12, 2022, I changed the font size to be auto-scaled
				with detected dpi by default. You can undo this by setting
				`scaleFontSizeWithDpi` to false. On March 22, 2022, I tweaked
				this slightly to only scale if the font point size is not already
				scaled (e.g. by Xft.dpi settings) to avoid double scaling.
		+/
		string fontName = defaultFont;
		/// ditto
		int fontSize = defaultSize;
		/// ditto
		bool scaleFontSizeWithDpi = true;

		/++
			Requested initial terminal size in character cells. You may not actually get exactly this.
		+/
		int initialWidth = 80;
		/// ditto
		int initialHeight = 30;

		/++
			If `true`, the window will close automatically when the main thread exits.
			Otherwise, the window will remain open so the user can work with output before
			it disappears.

			History:
				Added April 10, 2020 (v7.2.0)
		+/
		bool closeOnExit = false;

		/++
			Gives you a chance to modify the window as it is constructed. Intended
			to let you add custom menu options.

			---
			import arsd.terminal;
			integratedTerminalEmulatorConfiguration.menuExtensionsConstructor = (TerminalEmulatorWindow window) {
				import arsd.minigui; // for the menu related UDAs
				class Commands {
					@menu("Help") {
						void Topics() {
							auto window = new Window(); // make a help window of some sort
							window.show();
						}

						@separator

						void About() {
							messageBox("My Application v 1.0");
						}
					}
				}
				window.setMenuAndToolbarFromAnnotatedCode(new Commands());
			};
			---

			History:
				Added March 29, 2020. Included in release v7.1.0.
		+/
		void delegate(TerminalEmulatorWindow) menuExtensionsConstructor;

		/++
			Set this to true if you want [Terminal] to fallback to the user's
			existing native terminal in the event that creating the custom terminal
			is impossible for whatever reason.

			If your application must have all advanced features, set this to `false`.
			Otherwise, be sure you handle the absence of advanced features in your
			application by checking methods like [Terminal.inlineImagesSupported],
			etc., and only use things you can gracefully degrade without.

			If this is set to false, `Terminal`'s constructor will throw if the gui fails
			instead of carrying on with the stdout terminal (if possible).

			History:
				Added June 28, 2020. Included in release v8.1.0.

		+/
		bool fallbackToDegradedTerminal = true;

		/++
			The default key control is ctrl+c sends an interrupt character and ctrl+shift+c
			does copy to clipboard. If you set this to `true`, it swaps those two bindings.

			History:
				Added June 15, 2021. Included in release v10.1.0.
		+/
		bool ctrlCCopies = false; // FIXME: i could make this context-sensitive too, so if text selected, copy, otherwise, cancel. prolly show in statu s bar

		/++
			When using the integrated terminal emulator, the default is to assume you want it.
			But some users may wish to force the in-terminal fallback anyway at start up time.

			Seeing this to `true` will skip attempting to create the gui window where a fallback
			is available. It is ignored on systems where there is no fallback. Make sure that
			[fallbackToDegradedTerminal] is set to `true` if you use this.

			History:
				Added October 4, 2022 (dub v10.10)
		+/
		bool preferDegradedTerminal = false;
	}

	/+
		status bar should probably tell
		if scroll lock is on...
	+/

	/// You can set this in a static module constructor. (`shared static this() {}`)
	__gshared IntegratedTerminalEmulatorConfiguration integratedTerminalEmulatorConfiguration;

	import arsd.terminalemulator;
	import arsd.minigui;

	version(Posix)
		private extern(C) int openpty(int* master, int* slave, char*, const void*, const void*);

	/++
		Represents the window that the library pops up for you.
	+/
	final class TerminalEmulatorWindow : MainWindow {
		/++
			Returns the size of an individual character cell, in pixels.

			History:
				Added April 2, 2021
		+/
		Size characterCellSize() {
			if(tew && tew.terminalEmulator)
				return Size(tew.terminalEmulator.fontWidth, tew.terminalEmulator.fontHeight);
			else
				return Size(1, 1);
		}

		/++
			Gives access to the underlying terminal emulation object.
		+/
		TerminalEmulator terminalEmulator() {
			return tew.terminalEmulator;
		}

		private TerminalEmulatorWindow parent;
		private TerminalEmulatorWindow[] children;
		private void childClosing(TerminalEmulatorWindow t) {
			foreach(idx, c; children)
				if(c is t)
					children = children[0 .. idx] ~ children[idx + 1 .. $];
		}
		private void registerChild(TerminalEmulatorWindow t) {
			children ~= t;
		}

		private this(Terminal* term, TerminalEmulatorWindow parent) {

			this.parent = parent;
			scope(success) if(parent) parent.registerChild(this);

			super("Terminal Application");
			//, integratedTerminalEmulatorConfiguration.initialWidth * integratedTerminalEmulatorConfiguration.fontSize / 2, integratedTerminalEmulatorConfiguration.initialHeight * integratedTerminalEmulatorConfiguration.fontSize);

			smw = new ScrollMessageWidget(this);
			tew = new TerminalEmulatorWidget(term, smw);

			if(integratedTerminalEmulatorConfiguration.initialWidth == 0 || integratedTerminalEmulatorConfiguration.initialHeight == 0) {
				win.show(); // if must be mapped before maximized... it does cause a flash but meh.
				win.maximize();
			} else {
				win.resize(integratedTerminalEmulatorConfiguration.initialWidth * tew.terminalEmulator.fontWidth, integratedTerminalEmulatorConfiguration.initialHeight * tew.terminalEmulator.fontHeight);
			}

			smw.addEventListener("scroll", () {
				tew.terminalEmulator.scrollbackTo(smw.position.x, smw.position.y + tew.terminalEmulator.height);
				redraw();
			});

			smw.setTotalArea(1, 1);

			setMenuAndToolbarFromAnnotatedCode(this);
			if(integratedTerminalEmulatorConfiguration.menuExtensionsConstructor)
				integratedTerminalEmulatorConfiguration.menuExtensionsConstructor(this);



			if(term.pipeThroughStdOut && parent is null) { // if we have a parent, it already did this and stealing it is going to b0rk the output entirely
				version(Posix) {
					import unix = core.sys.posix.unistd;
					import core.stdc.stdio;

					auto fp = stdout;

					//  FIXME: openpty? child processes can get a lil borked.

					int[2] fds;
					auto ret = pipe(fds);

					auto fd = fileno(fp);

					dup2(fds[1], fd);
					unix.close(fds[1]);
					if(isatty(2))
						dup2(1, 2);
					auto listener = new PosixFdReader(() {
						ubyte[1024] buffer;
						auto ret = read(fds[0], buffer.ptr, buffer.length);
						if(ret <= 0) return;
						tew.terminalEmulator.sendRawInput(buffer[0 .. ret]);
						tew.terminalEmulator.redraw();
					}, fds[0]);

					readFd = fds[0];
				} else version(CRuntime_Microsoft) {

					CHAR[MAX_PATH] PipeNameBuffer;

					static shared(int) PipeSerialNumber = 0;

					import core.atomic;

					import core.stdc.string;

					// we need a unique name in the universal filesystem
					// so it can be freopen'd. When the process terminates,
					// this is auto-closed too, so the pid is good enough, just
					// with the shared number
					sprintf(PipeNameBuffer.ptr,
						`\\.\pipe\arsd.terminal.pipe.%08x.%08x`.ptr,
						GetCurrentProcessId(),
						atomicOp!"+="(PipeSerialNumber, 1)
				       );

					readPipe = CreateNamedPipeA(
						PipeNameBuffer.ptr,
						1/*PIPE_ACCESS_INBOUND*/ | FILE_FLAG_OVERLAPPED,
						0 /*PIPE_TYPE_BYTE*/ | 0/*PIPE_WAIT*/,
						1,         // Number of pipes
						1024,         // Out buffer size
						1024,         // In buffer size
						0,//120 * 1000,    // Timeout in ms
						null
					);
					if (!readPipe) {
						throw new Exception("CreateNamedPipeA");
					}

					this.overlapped = new OVERLAPPED();
					this.overlapped.hEvent = cast(void*) this;
					this.overlappedBuffer = new ubyte[](4096);

					import std.conv;
					import core.stdc.errno;
					if(freopen(PipeNameBuffer.ptr, "wb", stdout) is null)
						//MessageBoxA(null, ("excep " ~ to!string(errno) ~ "\0").ptr, "asda", 0);
						throw new Exception("freopen");

					setvbuf(stdout, null, _IOLBF, 128); // I'd prefer to line buffer it, but that doesn't seem to work for some reason.

					ConnectNamedPipe(readPipe, this.overlapped);

					// also send stderr to stdout if it isn't already redirected somewhere else
					if(_fileno(stderr) < 0) {
						freopen("nul", "wb", stderr);

						_dup2(_fileno(stdout), _fileno(stderr));
						setvbuf(stderr, null, _IOLBF, 128); // if I don't unbuffer this it can really confuse things
					}

					WindowsRead(0, 0, this.overlapped);
				} else throw new Exception("pipeThroughStdOut not supported on this system currently. Use -m32mscoff instead.");
			}
		}

		version(Windows) {
			HANDLE readPipe;
			private ubyte[] overlappedBuffer;
			private OVERLAPPED* overlapped;
			static final private extern(Windows) void WindowsRead(DWORD errorCode, DWORD numberOfBytes, OVERLAPPED* overlapped) {
				TerminalEmulatorWindow w = cast(TerminalEmulatorWindow) overlapped.hEvent;
				if(numberOfBytes) {
					w.tew.terminalEmulator.sendRawInput(w.overlappedBuffer[0 .. numberOfBytes]);
					w.tew.terminalEmulator.redraw();
				}
				import std.conv;
				if(!ReadFileEx(w.readPipe, w.overlappedBuffer.ptr, cast(DWORD) w.overlappedBuffer.length, overlapped, &WindowsRead))
					if(GetLastError() == 997) {}
					//else throw new Exception("ReadFileEx " ~ to!string(GetLastError()));
			}
		}

		version(Posix) {
			int readFd = -1;
		}

		TerminalEmulator.TerminalCell[] delegate(TerminalEmulator.TerminalCell[] i) parentFilter;

		private void addScrollbackLineFromParent(TerminalEmulator.TerminalCell[] lineIn) {
			if(parentFilter is null)
				return;

			auto line = parentFilter(lineIn);
			if(line is null) return;

			if(tew && tew.terminalEmulator) {
				bool atBottom = smw.verticalScrollBar.atEnd && smw.horizontalScrollBar.atStart;
				tew.terminalEmulator.addScrollbackLine(line);
				tew.terminalEmulator.notifyScrollbackAdded();
				if(atBottom) {
					tew.terminalEmulator.notifyScrollbarPosition(0, int.max);
					tew.terminalEmulator.scrollbackTo(0, int.max);
					tew.terminalEmulator.drawScrollback();
					tew.redraw();
				}
			}
		}

		private TerminalEmulatorWidget tew;
		private ScrollMessageWidget smw;

		@menu("&History") {
			@tip("Saves the currently visible content to a file")
			void Save() {
				getSaveFileName((string name) {
					if(name.length) {
						try
							tew.terminalEmulator.writeScrollbackToFile(name);
						catch(Exception e)
							messageBox("Save failed: " ~ e.msg);
					}
				});
			}

			// FIXME
			version(FIXME)
			void Save_HTML() {

			}

			@separator
			/*
			void Find() {
				// FIXME
				// jump to the previous instance in the scrollback

			}
			*/

			void Filter() {
				// open a new window that just shows items that pass the filter

				static struct FilterParams {
					string searchTerm;
					bool caseSensitive;
				}

				dialog((FilterParams p) {
					auto nw = new TerminalEmulatorWindow(null, this);

					nw.parentWindow.win.handleCharEvent = null; // kinda a hack... i just don't want it ever turning off scroll lock...

					nw.parentFilter = (TerminalEmulator.TerminalCell[] line) {
						import std.algorithm;
						import std.uni;
						// omg autodecoding being kinda useful for once LOL
						if(line.map!(c => c.hasNonCharacterData ? dchar(0) : (p.caseSensitive ? c.ch : c.ch.toLower)).
							canFind(p.searchTerm))
						{
							// I might highlight the match too, but meh for now
							return line;
						}
						return null;
					};

					foreach(line; tew.terminalEmulator.sbb[0 .. $]) {
						if(auto l = nw.parentFilter(line)) {
							nw.tew.terminalEmulator.addScrollbackLine(l);
						}
					}
					nw.tew.terminalEmulator.scrollLockLock();
					nw.tew.terminalEmulator.drawScrollback();
					nw.title = "Filter Display";
					nw.show();
				});

			}

			@separator
			void Clear() {
				tew.terminalEmulator.clearScrollbackHistory();
				tew.terminalEmulator.cls();
				tew.terminalEmulator.moveCursor(0, 0);
				if(tew.term) {
					tew.term.windowSizeChanged = true;
					tew.terminalEmulator.outgoingSignal.notify();
				}
				tew.redraw();
			}

			@separator
			void Exit() @accelerator("Alt+F4") @hotkey('x') {
				this.close();
			}
		}

		@menu("&Edit") {
			void Copy() {
				tew.terminalEmulator.copyToClipboard(tew.terminalEmulator.getSelectedText());
			}

			void Paste() {
				tew.terminalEmulator.pasteFromClipboard(&tew.terminalEmulator.sendPasteData);
			}
		}
	}

	private class InputEventInternal {
		const(ubyte)[] data;
		this(in ubyte[] data) {
			this.data = data;
		}
	}

	private class TerminalEmulatorWidget : Widget {

		Menu ctx;

		override Menu contextMenu(int x, int y) {
			if(ctx is null) {
				ctx = new Menu("", this);
				ctx.addItem(new MenuItem(new Action("Copy", 0, {
					terminalEmulator.copyToClipboard(terminalEmulator.getSelectedText());
				})));
				 ctx.addItem(new MenuItem(new Action("Paste", 0, {
					terminalEmulator.pasteFromClipboard(&terminalEmulator.sendPasteData);
				})));
				 ctx.addItem(new MenuItem(new Action("Toggle Scroll Lock", 0, {
				 	terminalEmulator.toggleScrollLock();
				})));
			}
			return ctx;
		}

		this(Terminal* term, ScrollMessageWidget parent) {
			this.smw = parent;
			this.term = term;
			super(parent);
			terminalEmulator = new TerminalEmulatorInsideWidget(this);
			this.parentWindow.addEventListener("closed", {
				if(term) {
					term.hangedUp = true;
					// should I just send an official SIGHUP?!
				}

				if(auto wi = cast(TerminalEmulatorWindow) this.parentWindow) {
					if(wi.parent)
						wi.parent.childClosing(wi);

					// if I don't close the redirected pipe, the other thread
					// will get stuck indefinitely as it tries to flush its stderr
					version(Windows) {
						CloseHandle(wi.readPipe);
						wi.readPipe = null;
					} version(Posix) {
						import unix = core.sys.posix.unistd;
						import unix2 = core.sys.posix.fcntl;
						unix.close(wi.readFd);

						version(none)
						if(term && term.pipeThroughStdOut) {
							auto fd = unix2.open("/dev/null", unix2.O_RDWR);
							unix.close(0);
							unix.close(1);
							unix.close(2);

							dup2(fd, 0);
							dup2(fd, 1);
							dup2(fd, 2);
						}
					}
				}

				// try to get it to terminate slightly more forcibly too, if possible
				if(sigIntExtension)
					sigIntExtension();

				terminalEmulator.outgoingSignal.notify();
				terminalEmulator.incomingSignal.notify();
				terminalEmulator.syncSignal.notify();

				windowGone = true;
			});

			this.parentWindow.win.addEventListener((InputEventInternal ie) {
				terminalEmulator.sendRawInput(ie.data);
				this.redraw();
				terminalEmulator.incomingSignal.notify();
			});
		}

		ScrollMessageWidget smw;
		Terminal* term;

		void sendRawInput(const(ubyte)[] data) {
			if(this.parentWindow) {
				this.parentWindow.win.postEvent(new InputEventInternal(data));
				if(windowGone) forceTermination();
				terminalEmulator.incomingSignal.wait(); // blocking write basically, wait until the TE confirms the receipt of it
			}
		}

		override void dpiChanged() {
			if(terminalEmulator) {
				terminalEmulator.loadFont();
				terminalEmulator.resized(width, height);
			}
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

		static class Style : Widget.Style {
			override MouseCursor cursor() {
				return GenericCursor.Text;
			}
		}
		mixin OverrideStyle!Style;

		override void erase(WidgetPainter painter) { /* intentionally blank, paint does it better */ }

		override void paint(WidgetPainter painter) {
			bool forceRedraw = false;
			if(terminalEmulator.invalidateAll || terminalEmulator.clearScreenRequested) {
				auto clearColor = terminalEmulator.defaultBackground;
				painter.outlineColor = clearColor;
				painter.fillColor = clearColor;
				painter.drawRectangle(Point(0, 0), this.width, this.height);
				terminalEmulator.clearScreenRequested = false;
				forceRedraw = true;
			}

			terminalEmulator.redrawPainter(painter, forceRedraw);
		}
	}

	private class TerminalEmulatorInsideWidget : TerminalEmulator {

		private ScrollbackBuffer sbb() { return scrollbackBuffer; }

		void resized(int w, int h) {
			this.resizeTerminal(w / fontWidth, h / fontHeight);
			if(widget && widget.smw) {
				widget.smw.setViewableArea(this.width, this.height);
				widget.smw.setPageSize(this.width / 2, this.height / 2);
			}
			notifyScrollbarPosition(0, int.max);
			clearScreenRequested = true;
			if(widget && widget.term)
				widget.term.windowSizeChanged = true;
			outgoingSignal.notify();
			redraw();
		}

		override void addScrollbackLine(TerminalCell[] line) {
			super.addScrollbackLine(line);
			if(widget)
			if(auto p = cast(TerminalEmulatorWindow) widget.parentWindow) {
				foreach(child; p.children)
					child.addScrollbackLineFromParent(line);
			}
		}

		override void notifyScrollbackAdded() {
			widget.smw.setTotalArea(this.scrollbackWidth > this.width ? this.scrollbackWidth : this.width, this.scrollbackLength > this.height ? this.scrollbackLength : this.height);
		}

		override void notifyScrollbarPosition(int x, int y) {
			widget.smw.setPosition(x, y);
			widget.redraw();
		}

		override void notifyScrollbarRelevant(bool isRelevantHorizontally, bool isRelevantVertically) {
			if(isRelevantVertically)
				notifyScrollbackAdded();
			else
				widget.smw.setTotalArea(width, height);
		}

		override @property public int cursorX() { return super.cursorX; }
		override @property public int cursorY() { return super.cursorY; }

		protected override void changeCursorStyle(CursorStyle s) { }

		string currentTitle;
		protected override void changeWindowTitle(string t) {
			if(widget && widget.parentWindow && t.length) {
				widget.parentWindow.win.title = t;
				currentTitle = t;
			}
		}
		protected override void changeWindowIcon(IndexedImage t) {
			if(widget && widget.parentWindow && t)
				widget.parentWindow.win.icon = t;
		}

		protected override void changeIconTitle(string) {}
		protected override void changeTextAttributes(TextAttributes) {}
		protected override void soundBell() {
			static if(UsingSimpledisplayX11)
				XBell(XDisplayConnection.get(), 50);
		}

		protected override void demandAttention() {
			if(widget && widget.parentWindow)
				widget.parentWindow.win.requestAttention();
		}

		protected override void copyToClipboard(string text) {
			setClipboardText(widget.parentWindow.win, text);
		}

		override int maxScrollbackLength() const {
			return int.max; // no scrollback limit for custom programs
		}

		protected override void pasteFromClipboard(void delegate(in char[]) dg) {
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

		override void requestExit() {
			widget.parentWindow.close();
		}

		bool echo = false;

		override void sendRawInput(in ubyte[] data) {
			void send(in ubyte[] data) {
				if(data.length == 0)
					return;
				super.sendRawInput(data);
				if(echo)
				sendToApplication(data);
			}

			// need to echo, translate 10 to 13/10 cr-lf
			size_t last = 0;
			const ubyte[2] crlf = [13, 10];
			foreach(idx, ch; data) {
				if(waitingForInboundSync && ch == 255) {
					send(data[last .. idx]);
					last = idx + 1;
					waitingForInboundSync = false;
					syncSignal.notify();
					continue;
				}
				if(ch == 10) {
					send(data[last .. idx]);
					send(crlf[]);
					last = idx + 1;
				}
			}

			if(last < data.length)
				send(data[last .. $]);
		}

		bool focused;

		TerminalEmulatorWidget widget;

		import arsd.simpledisplay;
		import arsd.color;
		import core.sync.semaphore;
		alias ModifierState = arsd.simpledisplay.ModifierState;
		alias Color = arsd.color.Color;
		alias fromHsl = arsd.color.fromHsl;

		const(ubyte)[] pendingForApplication;
		Semaphore syncSignal;
		Semaphore outgoingSignal;
		Semaphore incomingSignal;

		private shared(bool) waitingForInboundSync;

		override void sendToApplication(scope const(void)[] what) {
			synchronized(this) {
				pendingForApplication ~= cast(const(ubyte)[]) what;
			}
			outgoingSignal.notify();
		}

		@property int width() { return screenWidth; }
		@property int height() { return screenHeight; }

		@property bool invalidateAll() { return super.invalidateAll; }

		void loadFont() {
			if(this.font) {
				this.font.unload();
				this.font = null;
			}
			auto fontSize = integratedTerminalEmulatorConfiguration.fontSize;
			if(integratedTerminalEmulatorConfiguration.scaleFontSizeWithDpi) {
				static if(UsingSimpledisplayX11) {
					// if it is an xft font and xft is already scaled, we should NOT double scale.
					import std.algorithm;
					if(integratedTerminalEmulatorConfiguration.fontName.startsWith("core:")) {
						// core font doesn't use xft anyway
						fontSize = widget.scaleWithDpi(fontSize);
					} else {
						auto xft = getXftDpi();
						if(xft is float.init)
							xft = 96;
						// the xft passed as assumed means it will figure that's what the size
						// is based on (which it is, inside xft) preventing the double scale problem
						fontSize = widget.scaleWithDpi(fontSize, cast(int) xft);

					}
				} else {
					fontSize = widget.scaleWithDpi(fontSize);
				}
			}

			if(integratedTerminalEmulatorConfiguration.fontName.length) {
				this.font = new OperatingSystemFont(integratedTerminalEmulatorConfiguration.fontName, fontSize, FontWeight.medium);
				if(this.font.isNull) {
					// carry on, it will try a default later
				} else if(this.font.isMonospace) {
					this.fontWidth = font.averageWidth;
					this.fontHeight = font.height;
				} else {
					this.font.unload(); // can't really use a non-monospace font, so just going to unload it so the default font loads again
				}
			}

			if(this.font is null || this.font.isNull)
				loadDefaultFont(fontSize);
		}

		private this(TerminalEmulatorWidget widget) {

			this.syncSignal = new Semaphore();
			this.outgoingSignal = new Semaphore();
			this.incomingSignal = new Semaphore();

			this.widget = widget;

			loadFont();

			super(integratedTerminalEmulatorConfiguration.initialWidth ? integratedTerminalEmulatorConfiguration.initialWidth : 80,
				integratedTerminalEmulatorConfiguration.initialHeight ? integratedTerminalEmulatorConfiguration.initialHeight : 30);

			defaultForeground = integratedTerminalEmulatorConfiguration.defaultForeground;
			defaultBackground = integratedTerminalEmulatorConfiguration.defaultBackground;

			bool skipNextChar = false;

			widget.addEventListener((MouseDownEvent ev) {
				int termX = (ev.clientX - paddingLeft) / fontWidth;
				int termY = (ev.clientY - paddingTop) / fontHeight;

				if((!mouseButtonTracking || selectiveMouseTracking || (ev.state & ModifierState.shift)) && ev.button == MouseButton.right)
					widget.showContextMenu(ev.clientX, ev.clientY);
				else
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
					(ev.state & ModifierState.leftButtonDown) ? arsd.terminalemulator.MouseButton.left
					: (ev.state & ModifierState.rightButtonDown) ? arsd.terminalemulator.MouseButton.right
					: (ev.state & ModifierState.middleButtonDown) ? arsd.terminalemulator.MouseButton.middle
					: cast(arsd.terminalemulator.MouseButton) 0,
					(ev.state & ModifierState.shift) ? true : false,
					(ev.state & ModifierState.ctrl) ? true : false,
					(ev.state & ModifierState.alt) ? true : false
				))
					redraw();
			});

			widget.addEventListener((KeyDownEvent ev) {
				if(ev.key == Key.C && !(ev.state & ModifierState.shift) && (ev.state & ModifierState.ctrl)) {
					if(integratedTerminalEmulatorConfiguration.ctrlCCopies) {
						goto copy;
					}
				}
				if(ev.key == Key.C && (ev.state & ModifierState.shift) && (ev.state & ModifierState.ctrl)) {
					if(integratedTerminalEmulatorConfiguration.ctrlCCopies) {
						sendSigInt();
						skipNextChar = true;
						return;
					}
					// ctrl+c is cancel so ctrl+shift+c ends up doing copy.
					copy:
					copyToClipboard(getSelectedText());
					skipNextChar = true;
					return;
				}
				if(ev.key == Key.Insert && (ev.state & ModifierState.ctrl)) {
					copyToClipboard(getSelectedText());
					return;
				}

				auto keyToSend = ev.key;

				static if(UsingSimpledisplayX11) {
					if((ev.state & ModifierState.alt) && ev.originalKeyEvent.charsPossible.length) {
						keyToSend = cast(Key) ev.originalKeyEvent.charsPossible[0];
					}
				}

				defaultKeyHandler!(typeof(ev.key))(
					keyToSend
					, (ev.state & ModifierState.shift)?true:false
					, (ev.state & ModifierState.alt)?true:false
					, (ev.state & ModifierState.ctrl)?true:false
					, (ev.state & ModifierState.windows)?true:false
				);

				return; // the character event handler will do others
			});

			widget.addEventListener((CharEvent ev) {
				if(skipNextChar) {
					skipNextChar = false;
					return;
				}
				dchar c = ev.character;

				if(c == 0x1c) /* ctrl+\, force quit */ {
					version(Posix) {
						import core.sys.posix.signal;
						if(widget is null || widget.term is null) {
							// the other thread must already be dead, so we can just close
							widget.parentWindow.close(); // I'm gonna let it segfault if this is null cuz like that isn't supposed to happen
							return;
						}
					}

					terminateTerminalProcess(widget.term.threadId);
				} else if(c == 3) {// && !ev.shiftKey) /* ctrl+c, interrupt. But NOT ctrl+shift+c as that's a user-defined keystroke and/or "copy", but ctrl+shift+c never gets sent here.... thanks to the skipNextChar above */ {
					sendSigInt();
				} else {
					defaultCharHandler(c);
				}
			});
		}

		void sendSigInt() {
			if(sigIntExtension)
				sigIntExtension();

			if(widget && widget.term) {
				widget.term.interrupted = true;
				outgoingSignal.notify();
			}
		}

		bool clearScreenRequested = true;
		void redraw() {
			if(widget.parentWindow is null || widget.parentWindow.win is null || widget.parentWindow.win.closed)
				return;

			widget.redraw();
		}

		mixin SdpyDraw;
	}
} else {
	///
	enum IntegratedEmulator = false;
}

/*
void main() {
	auto terminal = Terminal(ConsoleOutputType.linear);
	terminal.setTrueColor(RGB(255, 0, 255), RGB(255, 255, 255));
	terminal.writeln("Hello, world!");
}
*/

private version(Windows) {
	pragma(lib, "user32");
	import core.sys.windows.winbase;
	import core.sys.windows.winnt;

	extern(Windows)
	HANDLE CreateNamedPipeA(
		const(char)* lpName,
		DWORD dwOpenMode,
		DWORD dwPipeMode,
		DWORD nMaxInstances,
		DWORD nOutBufferSize,
		DWORD nInBufferSize,
		DWORD nDefaultTimeOut,
		LPSECURITY_ATTRIBUTES lpSecurityAttributes
	);

	version(CRuntime_Microsoft) {
		extern(C) int _dup2(int, int);
		extern(C) int _fileno(FILE*);
	}
}

/++
	Convenience object to forward terminal keys to a [arsd.simpledisplay.SimpleWindow]. Meant for cases when you have a gui window as the primary mode of interaction, but also want keys to the parent terminal to be usable too by the window.

	Please note that not all keys may be accurately forwarded. It is not meant to be 100% comprehensive; that's for the window.

	History:
		Added December 29, 2020.
+/
static if(__traits(compiles, mixin(`{ static foreach(i; 0 .. 1) {} }`)))
mixin(q{
auto SdpyIntegratedKeys(SimpleWindow)(SimpleWindow window) {
	struct impl {
		static import sdpy = arsd.simpledisplay;
		Terminal* terminal;
		RealTimeConsoleInput* rtti;

		// FIXME hack to work around bug in opend compiler (i think)
		version(D_OpenD)
			alias mutableRefInit = imported!"core.attribute".mutableRefInit;
		else
			enum mutableRefInit;

		@mutableRefInit
		typeof(RealTimeConsoleInput.init.integrateWithSimpleDisplayEventLoop(null)) listener;
		this(sdpy.SimpleWindow window) {
			terminal = new Terminal(ConsoleOutputType.linear);
			rtti = new RealTimeConsoleInput(terminal, ConsoleInputFlags.releasedKeys);
			listener = rtti.integrateWithSimpleDisplayEventLoop(delegate(InputEvent ie) {
				if(ie.type == InputEvent.Type.HangupEvent || ie.type == InputEvent.Type.EndOfFileEvent)
					disconnect();

				if(ie.type != InputEvent.Type.KeyboardEvent)
					return;
				auto kbd = ie.get!(InputEvent.Type.KeyboardEvent);
				if(window.handleKeyEvent !is null) {
					sdpy.KeyEvent ke;
					ke.pressed = kbd.pressed;
					if(kbd.modifierState & ModifierState.control)
						ke.modifierState |= sdpy.ModifierState.ctrl;
					if(kbd.modifierState & ModifierState.alt)
						ke.modifierState |= sdpy.ModifierState.alt;
					if(kbd.modifierState & ModifierState.shift)
						ke.modifierState |= sdpy.ModifierState.shift;

					sw: switch(kbd.which) {
						case KeyboardEvent.Key.escape: ke.key = sdpy.Key.Escape; break;
						case KeyboardEvent.Key.F1: ke.key = sdpy.Key.F1; break;
						case KeyboardEvent.Key.F2: ke.key = sdpy.Key.F2; break;
						case KeyboardEvent.Key.F3: ke.key = sdpy.Key.F3; break;
						case KeyboardEvent.Key.F4: ke.key = sdpy.Key.F4; break;
						case KeyboardEvent.Key.F5: ke.key = sdpy.Key.F5; break;
						case KeyboardEvent.Key.F6: ke.key = sdpy.Key.F6; break;
						case KeyboardEvent.Key.F7: ke.key = sdpy.Key.F7; break;
						case KeyboardEvent.Key.F8: ke.key = sdpy.Key.F8; break;
						case KeyboardEvent.Key.F9: ke.key = sdpy.Key.F9; break;
						case KeyboardEvent.Key.F10: ke.key = sdpy.Key.F10; break;
						case KeyboardEvent.Key.F11: ke.key = sdpy.Key.F11; break;
						case KeyboardEvent.Key.F12: ke.key = sdpy.Key.F12; break;
						case KeyboardEvent.Key.LeftArrow: ke.key = sdpy.Key.Left; break;
						case KeyboardEvent.Key.RightArrow: ke.key = sdpy.Key.Right; break;
						case KeyboardEvent.Key.UpArrow: ke.key = sdpy.Key.Up; break;
						case KeyboardEvent.Key.DownArrow: ke.key = sdpy.Key.Down; break;
						case KeyboardEvent.Key.Insert: ke.key = sdpy.Key.Insert; break;
						case KeyboardEvent.Key.Delete: ke.key = sdpy.Key.Delete; break;
						case KeyboardEvent.Key.Home: ke.key = sdpy.Key.Home; break;
						case KeyboardEvent.Key.End: ke.key = sdpy.Key.End; break;
						case KeyboardEvent.Key.PageUp: ke.key = sdpy.Key.PageUp; break;
						case KeyboardEvent.Key.PageDown: ke.key = sdpy.Key.PageDown; break;
						case KeyboardEvent.Key.ScrollLock: ke.key = sdpy.Key.ScrollLock; break;

						case '\r', '\n': ke.key = sdpy.Key.Enter; break;
						case '\t': ke.key = sdpy.Key.Tab; break;
						case ' ': ke.key = sdpy.Key.Space; break;
						case '\b': ke.key = sdpy.Key.Backspace; break;

						case '`': ke.key = sdpy.Key.Grave; break;
						case '-': ke.key = sdpy.Key.Dash; break;
						case '=': ke.key = sdpy.Key.Equals; break;
						case '[': ke.key = sdpy.Key.LeftBracket; break;
						case ']': ke.key = sdpy.Key.RightBracket; break;
						case '\\': ke.key = sdpy.Key.Backslash; break;
						case ';': ke.key = sdpy.Key.Semicolon; break;
						case '\'': ke.key = sdpy.Key.Apostrophe; break;
						case ',': ke.key = sdpy.Key.Comma; break;
						case '.': ke.key = sdpy.Key.Period; break;
						case '/': ke.key = sdpy.Key.Slash; break;

						static foreach(ch; 'A' .. ('Z' + 1)) {
							case ch, ch + 32:
								version(Windows)
									ke.key = cast(sdpy.Key) ch;
								else
									ke.key = cast(sdpy.Key) (ch + 32);
							break sw;
						}
						static foreach(ch; '0' .. ('9' + 1)) {
							case ch:
								ke.key = cast(sdpy.Key) ch;
							break sw;
						}

						default:
					}

					// I'm tempted to leave the window null since it didn't originate from here
					// or maybe set a ModifierState....
					//ke.window = window;

					window.handleKeyEvent(ke);
				}
				if(window.handleCharEvent !is null) {
					if(kbd.isCharacter)
						window.handleCharEvent(kbd.which);
				}
			});
		}

		void disconnect() {
			if(listener is null)
				return;
			listener.dispose();
			listener = null;
			try {
				.destroy(*rtti);
				.destroy(*terminal);
			} catch(Exception e) {

			}
			rtti = null;
			terminal = null;
		}

		~this() {
			disconnect();
		}
	}
	return impl(window);
}
});


/*
	ONLY SUPPORTED ON MY TERMINAL EMULATOR IN GENERAL

	bracketed section can collapse and scroll independently in the TE. may also pop out into a window (possibly with a comparison window)

	hyperlink can either just indicate something to the TE to handle externally
	OR
	indicate a certain input sequence be triggered when it is clicked (prolly wrapped up as a paste event). this MAY also be a custom event.

	internally it can set two bits: one indicates it is a hyperlink, the other just flips each use to separate consecutive sequences.

	it might require the content of the paste event to be the visible word but it would bne kinda cool if it could be some secret thing elsewhere.


	I could spread a unique id number across bits, one bit per char so the memory isn't too bad.
	so it would set a number and a word. this is sent back to the application to handle internally.

	1) turn on special input
	2) turn off special input
	3) special input sends a paste event with a number and the text
	4) to make a link, you write out the begin sequence, the text, and the end sequence. including the magic number somewhere.
		magic number is allowed to have one bit per char. the terminal discards anything else. terminal.d api will enforce.

	if magic number is zero, it is not sent in the paste event. maybe.

	or if it is like 255, it is handled as a url and opened externally
		tho tbh a url could just be detected by regex pattern


	NOTE: if your program requests mouse input, the TE does not process it! Thus the user will have to shift+click for it.

	mode 3004 for bracketed hyperlink

	hyperlink sequence: \033[?220hnum;text\033[?220l~

*/
