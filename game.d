// register cheat code? or even a fighting game combo..
/++
	An add-on for simpledisplay.d, joystick.d, and simpleaudio.d
	that includes helper functions for writing simple games (and perhaps
	other multimedia programs). Whereas simpledisplay works with
	an event-driven framework, arsd.game always uses a consistent
	timer for updates.

	Usage example:

	---
	final class MyGame : GameHelperBase {
		/// Called when it is time to redraw the frame
		/// it will try for a particular FPS
		override void drawFrame() {
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_ACCUM_BUFFER_BIT);

			glLoadIdentity();

			glColor3f(1.0, 1.0, 1.0);
			glTranslatef(x, y, 0);
			glBegin(GL_QUADS);

			glVertex2i(0, 0);
			glVertex2i(16, 0);
			glVertex2i(16, 16);
			glVertex2i(0, 16);

			glEnd();
		}

		int x, y;
		override bool update(Duration deltaTime) {
			x += 1;
			y += 1;
			return true;
		}

		override SimpleWindow getWindow() {
			auto window = create2dWindow("My game");
			// load textures and such here
			return window;
		}

		final void fillAudioBuffer(short[] buffer) {

		}
	}

	void main() {
		auto game = new MyGame();

		runGame(game, maxRedrawRate, maxUpdateRate);
	}
	---

	It provides an audio thread, input scaffold, and helper functions.


	The MyGame handler is actually a template, so you don't have virtual
	function indirection and not all functions are required. The interfaces
	are just to help you get the signatures right, they don't force virtual
	dispatch at runtime.

	See_Also:
		[arsd.ttf.OpenGlLimitedFont]
+/
module arsd.game;

/+
	Networking helper: just send/receive messages and manage some connections

	It might offer a controller queue you can put local and network events in to get fair lag and transparent ultiplayer

	split screen?!?!

+/

/+
	ADD ME:
	Animation helper like audio style. Your game object
	has a particular image attached as primary.

	You can be like `animate once` or `animate indefinitely`
	and it takes care of it, then set new things and it does that too.
+/

public import arsd.gamehelpers;
public import arsd.color;
public import arsd.simpledisplay;
public import arsd.simpleaudio;

import std.math;
public import core.time;

public import arsd.joystick;

/++
	Creates a simple 2d opengl simpledisplay window. It sets the matrix for pixel coordinates and enables alpha blending and textures.
+/
SimpleWindow create2dWindow(string title, int width = 512, int height = 512) {
	auto window = new SimpleWindow(width, height, title, OpenGlOptions.yes);

	window.setAsCurrentOpenGlContext();

	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glClearColor(0,0,0,0);
	glDepthFunc(GL_LEQUAL);

	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0, width, height, 0, 0, 1);

	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	glDisable(GL_DEPTH_TEST);
	glEnable(GL_TEXTURE_2D);

	window.windowResized = (newWidth, newHeight) {
		int x, y, w, h;

		// FIXME: this works for only square original sizes
		if(newWidth < newHeight) {
			w = newWidth;
			h = newWidth * height / width;
			x = 0;
			y = (newHeight - h) / 2;
		} else {
			w = newHeight * width / height;
			h = newHeight;
			x = (newWidth - w) / 2;
			y = 0;
		}

		glViewport(x, y, w, h);
		window.redrawOpenGlSceneNow();
	};

	return window;
}

/++
	This is the base class for your game.

	You should destroy this explicitly. Easiest
	way is to do this in your `main` function:

	---
		auto game = new MyGameSubclass();
		scope(exit) .destroy(game);

		runGame(game);
	---
+/
abstract class GameHelperBase {
	/// Implement this to draw.
	abstract void drawFrame();

	ushort snesRepeatRate() { return ushort.max; }
	ushort snesRepeatDelay() { return snesRepeatRate(); }

	/// Implement this to update. The deltaTime tells how much real time has passed since the last update.
	/// Returns true if anything changed, which will queue up a redraw
	abstract bool update(Duration deltaTime);
	//abstract void fillAudioBuffer(short[] buffer);

	/// Returns the main game window. This function will only be
	/// called once if you use runGame. You should return a window
	/// here like one created with `create2dWindow`.
	abstract SimpleWindow getWindow();

	/// Override this and return true to initialize the audio system.
	/// Note that trying to use the [audio] member without this will segfault!
	bool wantAudio() { return false; }

	/// You must override [wantAudio] and return true for this to be valid;
	AudioOutputThread audio;

	this() {
		audio = AudioOutputThread(wantAudio());
	}

	protected bool redrawForced;

	/// Forces a redraw even if update returns false
	final public void forceRedraw() {
		redrawForced = true;
	}

	/// These functions help you handle user input. It offers polling functions for
	/// keyboard, mouse, joystick, and virtual controller input.
	///
	/// The virtual digital controllers are best to use if that model fits you because it
	/// works with several kinds of controllers as well as keyboards.

	JoystickUpdate[4] joysticks;
	ref JoystickUpdate joystick1() { return joysticks[0]; }

	bool[256] keyboardState;

	// FIXME: add a mouse position and delta thing too.

	/++

	+/
	VirtualController snes;
}

/++
	The virtual controller is based on the SNES. If you need more detail, try using
	the joystick or keyboard and mouse members directly.

	```
	 l          r

	 U          X
	L R  s  S  Y A
	 D          B
	```

	For Playstation and XBox controllers plugged into the computer,
	it picks those buttons based on similar layout on the physical device.

	For keyboard control, arrows and WASD are mapped to the d-pad (ULRD in the diagram),
	Q and E are mapped to the shoulder buttons (l and r in the diagram).So are U and P.

	Z, X, C, V (for when right hand is on arrows) and K,L,I,O (for left hand on WASD) are mapped to B,A,Y,X buttons.

	G is mapped to select (s), and H is mapped to start (S).

	The space bar and enter keys are also set to button A, with shift mapped to button B.


	Only player 1 is mapped to the keyboard.
+/
struct VirtualController {
	ushort previousState;
	ushort state;

	// for key repeat
	ushort truePreviousState;
	ushort lastStateChange;
	bool repeating;

	///
	enum Button {
		Up, Left, Right, Down,
		X, A, B, Y,
		Select, Start, L, R
	}

	@nogc pure nothrow @safe:

	/++
		History: Added April 30, 2020
	+/
	bool justPressed(Button idx) const {
		auto before = (previousState & (1 << (cast(int) idx))) ? true : false;
		auto after = (state & (1 << (cast(int) idx))) ? true : false;
		return !before && after;
	}
	/++
		History: Added April 30, 2020
	+/
	bool justReleased(Button idx) const {
		auto before = (previousState & (1 << (cast(int) idx))) ? true : false;
		auto after = (state & (1 << (cast(int) idx))) ? true : false;
		return before && !after;
	}

	///
	bool opIndex(Button idx) const {
		return (state & (1 << (cast(int) idx))) ? true : false;
	}
	private void opIndexAssign(bool value, Button idx) {
		if(value)
			state |= (1 << (cast(int) idx));
		else
			state &= ~(1 << (cast(int) idx));
	}
}

/++
	Deprecated, use the other overload instead.

	History:
		Deprecated on May 9, 2020. Instead of calling
		`runGame(your_instance);` run `runGame!YourClass();`
		instead. If you needed to change something in the game
		ctor, make a default constructor in your class to do that
		instead.
+/
deprecated("Use runGame!YourGameType(updateRate, redrawRate); instead now.")
void runGame()(GameHelperBase game, int maxUpdateRate = 20, int maxRedrawRate = 0) { assert(0, "this overload is deprecated, use runGame!YourClass instead"); }

/++
	Runs your game. It will construct the given class and destroy it at end of scope.
	Your class must have a default constructor and must implement [GameHelperBase].
	Your class should also probably be `final` for performance reasons.

	$(TIP
		If you need to pass parameters to your game class, you can define
		it as a nested class in your `main` function and access the local
		variables that way instead of passing them explicitly through the
		constructor.
	)

	Params:
	maxUpdateRate = The max rates are given in executions per second
	maxRedrawRate = Redraw will never be called unless there has been at least one update
+/
void runGame(T : GameHelperBase)(int maxUpdateRate = 20, int maxRedrawRate = 0) {


	auto game = new T();
	scope(exit) .destroy(game);

	// this is a template btw because then it can statically dispatch
	// the members instead of going through the virtual interface.

	int joystickPlayers = enableJoystickInput();
	scope(exit) closeJoysticks();

	auto window = game.getWindow();

	window.redrawOpenGlScene = &game.drawFrame;

	auto lastUpdate = MonoTime.currTime;

	window.eventLoop(1000 / maxUpdateRate,
		delegate() {
			foreach(p; 0 .. joystickPlayers) {
				version(linux)
					readJoystickEvents(joystickFds[p]);
				auto update = getJoystickUpdate(p);

				if(p == 0) {
					static if(__traits(isSame, Button, PS1Buttons)) {
						// PS1 style joystick mapping compiled in
						with(Button) with(VirtualController.Button) {
							// so I did the "wasJustPressed thing because it interplays
							// better with the keyboard as well which works on events...
							if(update.buttonWasJustPressed(square)) game.snes[Y] = true;
							if(update.buttonWasJustPressed(triangle)) game.snes[X] = true;
							if(update.buttonWasJustPressed(cross)) game.snes[B] = true;
							if(update.buttonWasJustPressed(circle)) game.snes[A] = true;
							if(update.buttonWasJustPressed(select)) game.snes[Select] = true;
							if(update.buttonWasJustPressed(start)) game.snes[Start] = true;
							if(update.buttonWasJustPressed(l1)) game.snes[L] = true;
							if(update.buttonWasJustPressed(r1)) game.snes[R] = true;
							// note: no need to check analog stick here cuz joystick.d already does it for us (per old playstation tradition)
							if(update.axisChange(Axis.horizontalDpad) < 0 && update.axisPosition(Axis.horizontalDpad) < -8) game.snes[Left] = true;
							if(update.axisChange(Axis.horizontalDpad) > 0 && update.axisPosition(Axis.horizontalDpad) > 8) game.snes[Right] = true;
							if(update.axisChange(Axis.verticalDpad) < 0 && update.axisPosition(Axis.verticalDpad) < -8) game.snes[Up] = true;
							if(update.axisChange(Axis.verticalDpad) > 0 && update.axisPosition(Axis.verticalDpad) > 8) game.snes[Down] = true;

							if(update.buttonWasJustReleased(square)) game.snes[Y] = false;
							if(update.buttonWasJustReleased(triangle)) game.snes[X] = false;
							if(update.buttonWasJustReleased(cross)) game.snes[B] = false;
							if(update.buttonWasJustReleased(circle)) game.snes[A] = false;
							if(update.buttonWasJustReleased(select)) game.snes[Select] = false;
							if(update.buttonWasJustReleased(start)) game.snes[Start] = false;
							if(update.buttonWasJustReleased(l1)) game.snes[L] = false;
							if(update.buttonWasJustReleased(r1)) game.snes[R] = false;
							if(update.axisChange(Axis.horizontalDpad) > 0 && update.axisPosition(Axis.horizontalDpad) > -8) game.snes[Left] = false;
							if(update.axisChange(Axis.horizontalDpad) < 0 && update.axisPosition(Axis.horizontalDpad) < 8) game.snes[Right] = false;
							if(update.axisChange(Axis.verticalDpad) > 0 && update.axisPosition(Axis.verticalDpad) > -8) game.snes[Up] = false;
							if(update.axisChange(Axis.verticalDpad) < 0 && update.axisPosition(Axis.verticalDpad) < 8) game.snes[Down] = false;
						}

					} else static if(__traits(isSame, Button, XBox360Buttons)) {
					static assert(0);
						// XBox style mapping
						// the reason this exists is if the programmer wants to use the xbox details, but
						// might also want the basic controller in here. joystick.d already does translations
						// so an xbox controller with the default build actually uses the PS1 branch above.
						/+
						case XBox360Buttons.a: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_A) ? true : false;
						case XBox360Buttons.b: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_B) ? true : false;
						case XBox360Buttons.x: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_X) ? true : false;
						case XBox360Buttons.y: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_Y) ? true : false;

						case XBox360Buttons.lb: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) ? true : false;
						case XBox360Buttons.rb: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) ? true : false;

						case XBox360Buttons.back: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_BACK) ? true : false;
						case XBox360Buttons.start: return (what.Gamepad.wButtons & XINPUT_GAMEPAD_START) ? true : false;
						+/
					}
				}

				game.joysticks[p] = update;
			}

			auto now = MonoTime.currTime;
			bool changed = game.update(now - lastUpdate);
			auto stateChange = game.snes.truePreviousState ^ game.snes.state;
			game.snes.previousState = game.snes.state;
			game.snes.truePreviousState = game.snes.state;

			if(stateChange == 0) {
				game.snes.lastStateChange++;
				auto r = game.snesRepeatRate();
				if(r != typeof(r).max && !game.snes.repeating && game.snes.lastStateChange == game.snesRepeatDelay()) {
					game.snes.lastStateChange = 0;
					game.snes.repeating = true;
				} else if(r != typeof(r).max && game.snes.repeating && game.snes.lastStateChange == r) {
					game.snes.lastStateChange = 0;
					game.snes.previousState = 0;
				}
			} else {
				game.snes.repeating = false;
			}
			lastUpdate = now;

			if(game.redrawForced) {
				changed = true;
				game.redrawForced = false;
			}

			// FIXME: rate limiting
			if(changed)
				window.redrawOpenGlSceneNow();
		},

		delegate (KeyEvent ke) {
			game.keyboardState[ke.hardwareCode] = ke.pressed;

			with(VirtualController.Button)
			switch(ke.key) {
				case Key.Up, Key.W: game.snes[Up] = ke.pressed; break;
				case Key.Down, Key.S: game.snes[Down] = ke.pressed; break;
				case Key.Left, Key.A: game.snes[Left] = ke.pressed; break;
				case Key.Right, Key.D: game.snes[Right] = ke.pressed; break;
				case Key.Q, Key.U: game.snes[L] = ke.pressed; break;
				case Key.E, Key.P: game.snes[R] = ke.pressed; break;
				case Key.Z, Key.K: game.snes[B] = ke.pressed; break;
				case Key.Space, Key.Enter, Key.X, Key.L: game.snes[A] = ke.pressed; break;
				case Key.C, Key.I: game.snes[Y] = ke.pressed; break;
				case Key.V, Key.O: game.snes[X] = ke.pressed; break;
				case Key.G: game.snes[Select] = ke.pressed; break;
				case Key.H: game.snes[Start] = ke.pressed; break;
				case Key.Shift, Key.Shift_r: game.snes[B] = ke.pressed; break;
				default:
			}
		}
	);
}

/++
	Simple class for putting a TrueColorImage in as an OpenGL texture.

	Doesn't do mipmapping btw.
+/
final class OpenGlTexture {
	private uint _tex;
	private int _width;
	private int _height;
	private float _texCoordWidth;
	private float _texCoordHeight;

	/// Calls glBindTexture
	void bind() {
		glBindTexture(GL_TEXTURE_2D, _tex);
	}

	/// For easy 2d drawing of it
	void draw(Point where, int width = 0, int height = 0, float rotation = 0.0, Color bg = Color.white) {
		draw(where.x, where.y, width, height, rotation, bg);
	}

	///
	void draw(float x, float y, int width = 0, int height = 0, float rotation = 0.0, Color bg = Color.white) {
		glPushMatrix();
		glTranslatef(x, y, 0);

		if(width == 0)
			width = this.originalImageWidth;
		if(height == 0)
			height = this.originalImageHeight;

		glTranslatef(cast(float) width / 2, cast(float) height / 2, 0);
		glRotatef(rotation, 0, 0, 1);
		glTranslatef(cast(float) -width / 2, cast(float) -height / 2, 0);

		glColor4f(cast(float)bg.r/255.0, cast(float)bg.g/255.0, cast(float)bg.b/255.0, cast(float)bg.a / 255.0);
		glBindTexture(GL_TEXTURE_2D, _tex);
		glBegin(GL_QUADS); 
			glTexCoord2f(0, 0); 				glVertex2i(0, 0);
			glTexCoord2f(texCoordWidth, 0); 		glVertex2i(width, 0); 
			glTexCoord2f(texCoordWidth, texCoordHeight); 	glVertex2i(width, height); 
			glTexCoord2f(0, texCoordHeight); 		glVertex2i(0, height); 
		glEnd();

		glBindTexture(GL_TEXTURE_2D, 0); // unbind the texture

		glPopMatrix();
	}

	/// Use for glTexCoord2f
	float texCoordWidth() { return _texCoordWidth; }
	float texCoordHeight() { return _texCoordHeight; } /// ditto

	/// Returns the texture ID
	uint tex() { return _tex; }

	/// Returns the size of the image
	int originalImageWidth() { return _width; }
	int originalImageHeight() { return _height; } /// ditto

	// explicitly undocumented, i might remove this
	TrueColorImage from;

	/// Make a texture from an image.
	this(TrueColorImage from) {
		bindFrom(from);
	}

	/// Generates from text. Requires ttf.d
	/// pass a pointer to the TtfFont as the first arg (it is template cuz of lazy importing, not because it actually works with different types)
	this(T, FONT)(FONT* font, int size, in T[] text) if(is(T == char)) {
		bindFrom(font, size, text);
	}

	/// Creates an empty texture class for you to use with [bindFrom] later
	/// Using it when not bound is undefined behavior.
	this() {}



	/// After you delete it with dispose, you may rebind it to something else with this.
	void bindFrom(TrueColorImage from) {
		assert(from !is null);
		assert(from.width > 0 && from.height > 0);

		import core.stdc.stdlib;

		_width = from.width;
		_height = from.height;

		this.from = from;

		auto _texWidth = _width;
		auto _texHeight = _height;

		const(ubyte)* data = from.imageData.bytes.ptr;
		bool freeRequired = false;

		// gotta round them to the nearest power of two which means padding the image
		if((_texWidth & (_texWidth - 1)) || (_texHeight & (_texHeight - 1))) {
			_texWidth = nextPowerOfTwo(_texWidth);
			_texHeight = nextPowerOfTwo(_texHeight);

			auto n = cast(ubyte*) malloc(_texWidth * _texHeight * 4);
			if(n is null) assert(0);
			scope(failure) free(n);

			auto size = from.width * 4;
			auto advance = _texWidth * 4;
			int at = 0;
			int at2 = 0;
			foreach(y; 0 .. from.height) {
				n[at .. at + size] = from.imageData.bytes[at2 .. at2+ size];
				at += advance;
				at2 += size;
			}

			data = n;
			freeRequired = true;

			// the rest of data will be initialized to zeros automatically which is fine.
		}

		glGenTextures(1, &_tex);
		glBindTexture(GL_TEXTURE_2D, tex);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		
		glTexImage2D(
			GL_TEXTURE_2D,
			0,
			GL_RGBA,
			_texWidth, // needs to be power of 2
			_texHeight,
			0,
			GL_RGBA,
			GL_UNSIGNED_BYTE,
			data);

		assert(!glGetError());

		_texCoordWidth = cast(float) _width / _texWidth;
		_texCoordHeight = cast(float) _height / _texHeight;

		if(freeRequired)
			free(cast(void*) data);
		glBindTexture(GL_TEXTURE_2D, 0);
	}

	/// ditto
	void bindFrom(T, FONT)(FONT* font, int size, in T[] text) if(is(T == char)) {
		assert(font !is null);
		int width, height;
		auto data = font.renderString(text, size, width, height);
		auto image = new TrueColorImage(width, height);
		int pos = 0;
		foreach(y; 0 .. height)
		foreach(x; 0 .. width) {
			image.imageData.bytes[pos++] = 255;
			image.imageData.bytes[pos++] = 255;
			image.imageData.bytes[pos++] = 255;
			image.imageData.bytes[pos++] = data[0];
			data = data[1 .. $];
		}
		assert(data.length == 0);

		bindFrom(image);
	}

	/// Deletes the texture. Using it after calling this is undefined behavior
	void dispose() {
		glDeleteTextures(1, &_tex);
		_tex = 0;
	}

	~this() {
		if(_tex > 0)
			dispose();
	}
}

/+
	FIXME: i want to do stbtt_GetBakedQuad for ASCII and use that
	for simple cases especially numbers. for other stuff you can
	create the texture for the text above.
+/

///
void clearOpenGlScreen(SimpleWindow window) {
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_ACCUM_BUFFER_BIT);
}


