// FIXME: the audio thread needs to trigger an event in the event of its death too

// i could add a "time" uniform for the shaders automatically. unity does a float4 i think with ticks in it
// register cheat code? or even a fighting game combo..
/++
	An add-on for simpledisplay.d, joystick.d, and simpleaudio.d
	that includes helper functions for writing simple games (and perhaps
	other multimedia programs). Whereas simpledisplay works with
	an event-driven framework, arsd.game always uses a consistent
	timer for updates.

	$(PITFALL
		I AM NO LONGER HAPPY WITH THIS INTERFACE AND IT WILL CHANGE.

		While arsd 11 included an overhaul (so you might want to fork
		an older version if you relied on it, but the transition is worth
		it and wasn't too hard for my game), there's still more stuff changing.

		This is considered unstable as of arsd 11.0 and will not re-stabilize
		until some 11.x release to be determined in the future (and then it might
		break again in 12.0, but i'll commit to long term stabilization after that
		at the latest).
	)


	The general idea is you provide a game class which implements a minimum of
	three functions: `update`, `drawFrame`, and `getWindow`. Your main function
	calls `runGame!YourClass();`.

	`getWindow` is called first. It is responsible for creating the window and
	initializing your setup. Then the game loop is started, which will call `update`,
	to update your game state, and `drawFrame`, which draws the current state.

	`update` is called on a consistent timer. It should always do exactly one delta-time
	step of your game work and the library will ensure it is called often enough to keep
	game time where it should be with real time. `drawFrame` will be called when an opportunity
	arises, possibly more or less often than `update` is called. `drawFrame` gets an argument
	telling you how close it is to the next `update` that you can use for interpolation.

	How, exactly, you decide to draw and update is up to you, but I strongly recommend that you
	keep your game state inside the game class, or at least accessible from it. In other words,
	avoid using global and static variables.

	It might be easier to understand by example. Behold:

	---
	import arsd.game;

	final class MyGame : GameHelperBase {
		/// Called when it is time to redraw the frame. The interpolate member
		/// tells you the fraction of an update has passed since the last update
		/// call; you can use this to make smoother animations if you like.
		override void drawFrame(float interpolate) {
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
		override bool update() {
			x += 1;
			y += 1;
			return true;
		}

		override SimpleWindow getWindow() {
			// if you want to use OpenGL 3 or nanovega or whatever, you can set it up in here too.
			auto window = create2dWindow("My game");
			// load textures and such here
			return window;
		}
	}

	void main() {
		runGame!MyGame(20 /*targetUpdateRate - shoot for 20 updates per second of game state*/);
		// please note that it can draw faster than this; updates should be less than drawn frames per second.
	}
	---

	Of course, this isn't much of a game, since there's no input. The [GameHelperBase] provides a few ways for your
	`update` function to check for user input: you can check the current state of and transition since last update
	of a SNES-style [VirtualController] through [GameHelperBase.snes], or the computer keyboard and mouse through
	[GameHelperBase.keyboardState] and (FIXME: expose mouse). Touch events are not implemented at this time and I have
	no timetable for when they will be, but I do want to add them at some point.

	The SNES controller is great if your game can work with it because it will automatically map to various gamepads
	as well as to the standard computer keyboard. This gives the user a lot of flexibility in how they control the game.
	If it doesn't though, you can try the other models. However, I don't recommend you try to mix them in the same game mode,
	since you wouldn't want a user to accidentally trigger the controller while trying to type their name, for example.

	If you just do the basics here, you'll have a working basic game. You can also get additional
	features by implementing more functions, like `override bool wantAudio() { return true; } ` will
	enable audio, for example. You can then trigger sounds and music to play in your `update` function.

	Let's expand the example to show this:

	// FIXME: paste in game2.d contents here

	A game usually isn't just one thing, and it might help to separate these out. I call these [GameScreen]s.
	The name might not be perfect, but the idea is that even a basic game might still have, for example, a
	title screen and a gameplay screen. These are likely to have different controls, different drawing, and some
	different state.


	The MyGame handler is actually a template, so you don't have virtual
	function indirection and not all functions are required. The interfaces
	are just to help you get the signatures right, they don't force virtual
	dispatch at runtime.

	$(H2 Input)

	In the overview, I mentioned that there's input available through a few means. Among the functions are:

	Checking capabilities:
		keyboardIsPresent, mouseIsPresent, gamepadIsPresent, joystickIsPresent, touchIsPresent - return true if there's a physical device for this (tho all can be emulated from just keyboard/mouse)

	Gamepads, mouse buttons, and keyboards:
		wasPressed - returns true if the button was not pressed but became pressed over the update period.
		wasReleased - returns true if the button was pressed, but was released over the update period
		wasClicked - returns true if the button was released but became pressed and released again since you last asked without much other movement in between
		isHeld - returns true if the button is currently held down
	Gamepad specific (remember the keyboard emulates a basic gamepad):
		startRecordingButtons - starts recording buttons
		getRecordedButtons - gets the sequence of button presses with associated times
		stopRecordingButtons - stops recording buttons

		You might use this to check for things like cheat codes and fighting game style special moves.
	Keyboard-specific:
		startRecordingCharacters - starts recording keyboard character input
		getRecordedCharacters - returns the characters typed since you started recording characters
		stopRecordingCharacters - stops recording characters and clears the recording

		You might use this for taking input for chat or character name selection.

		FIXME: add an on-screen keyboard thing you can use with gamepads too
	Mouse and joystick:
		startRecordingPath - starts recording paths, each point coming off the operating system is noted with a timestamp relative to when the recording started
		getRecordedPath - gets the current recorded path
		stopRecordingPath - stops recording the path and clears the recording.

		You might use this for things like finding circles in Mario Party.
	Mouse-specific:
		// actually instead of capture/release i might make it a property of the screen. we'll see.
		captureCursor - captures the cursor inside the window
		releaseCursor - releases any existing capture
		currentPosition - returns the current position over the window, in pixels, with (0,0) being the upper left.
		changeInPosition - returns the change in position since last time you asked
		wheelMotion - change in wheel ticks since last time you asked
	Joystick-specific (be aware that the mouse will act as an emulated joystick):
		currentPosition - returns the current position of the stick, 0,0 being centered and -1, 1 being the upper left corner and 1,-1 being the lower right position. Note that there is a dead zone in the middle of joysticks that does not count so minute wiggles are filtered out.
		changeInPosition - returns the change in position since last time you asked

		There may also be raw input data available, since this uses arsd.joystick.
	Touch-specific:

	$(H2 Window control)

	FIXME: no public functions for this yet.

	You can check for resizes and if the user wants to close to give you a chance to save the game before closing. You can also call `window.close();`. The library normally takes care of this for you.

	Minimized windows will put the game on hold automatically. Maximize and full screen is handled automatically. You can request full screen when creating the window, or use the simpledisplay functions in runInGuiThreadAsync (but don't if you don't need to).

	Showing and hiding cursor can be done in sdpy too.

	Text drawing prolly shouldn't bitmap scale when the window is blown up, e.g. hidpi. Other things can just auto scale tho. The library should take care of this automatically.

	You can set window title and icon when creating it too.

	$(H2 Drawing)

	I try not to force any one drawing model upon you. I offer four options out of the box and any opengl library has a good chance of working with appropriate setup.

	The out-of-the-box choices are:

	$(LIST
		* Old-style OpenGL, 2d or 3d, with glBegin, glEnd, glRotate, etc. For text, you can use [arsd.ttf.OpenGlLimitedFont]

		* New-style OpenGL, 2d or 3d, with shaders and your own math libraries. For text, you can use [arsd.ttf.OpenGlLimitedFont] with new style flag enabled.

		* [Nanovega|arsd.nanovega] 2d vector graphics. Nanovega supports its own text drawing functions.

		* The `BasicDrawing` functions provided by `arsd.game`. To some extent, you'll be able to mix and match these with other drawing models. It is just bare minimum functionality you might find useful made in a more concise form than even old-style opengl or for porting something that uses a ScreenPainter. (not implemented)
	)

	Please note that the simpledisplay ScreenPainter will NOT work in a game `drawFrame` function.

	You can switch between 2d and 3d modes when drawing either with opengl functions or with my helper functions like go2d (FIXME: not in the right module yet).

	$(H3 Images)

	use arsd.image and the OpenGlTexture object.

	$(H3 Text)

	use [OpenGlLimitedFont] and maybe [OperatingSystemFont]

	$(H3 3d models)

	FIXME add something

	$(H2 Audio)

	done through arsd.simpleaudio

	$(H2 Collision detection)

	Nanovega actually offers this but generally you're on your own. arsd's Rectangle functions offer some too.

	$(H2 Labeling variables)

	You can label and categorize variables in your game to help get and set them automatically. For example, marking them as `@Saved` and `@ResetOnNewDungeon` which you use to do batch updates. FIXME: implement this.

	$(H2 Random numbers)

	std.random works but might want another thing so the seed is saved with the game. An old school trick is to seed it based on some user input, even just time it took then to go past the title screen.

	$(H2 Screenshots)

	simpledisplay has a function for it. FIXME give a one-stop function here.

	$(H2 Stuff missing from raylib that might be useful)

	the screen space functions. the 3d model stuff.

	$(H2 Online play)

	FIXME: not implemented

	If you make your games input strictly use the virtual controller functions, it supports multiple players. Locally, they can be multiple gamepads plugged in to the computer. Over the network, you can have multiple players connect to someone acting as a server and it sends input from each player's computers to everyone else which is exposed to the game as other virtual controllers.

	The way this works is before your game actually starts running, if the game was run with the network flag (which can come from command line or through the `runGame` parameter), one player will act as the server and others will connect to them

	There is also a chat function built in.

		getUserChat(recipients, prompt) - tells the input system that you want to accept a user chat message.
		drawUserChat(Point, Color, Font) - returns null if not getting user chat, otherwise returns the current string (what about the carat?)
		cancelGetChat - cancels a getUserChat.

		sendBotChat(recipients, sender, message) - sends a chat from your program to the other users (will be marked as a bot message)

		getChatHistory
		getLatestChat - returns the latest chat not yet returned, or null if none have come in recently

		Chat messages take an argument defining the recipients, which you might want to limit if there are teams.

	In your Game object, there is a `filterUserChat` method you can optionally implement. This is given the message they typed. If you return the message, it will send it to other players. Or you can return null to cancel sending it on the network. You might then use the chat function to implement cheat codes like the old Warcraft and Starcraft games. If the player is not connected on the network, nothing happens even if you do return a message, since there is nobody to send it to.

	You can also implement a `chatHistoryLength` which tells how many messages to keep in memory.

	Finally, you can send custom network messages with `sendNetworkUpdate` and `getNetworkUpdate`, which work with your own arbitrary structs that represent data packets. Each one can be sent to recipients like chat messages but this is strictly for the program to read  These take an argument to decide if it should be the tcp or udp connections.

	$(H2 Split screen)

	When playing locally, you might want to split your window for multiple players to see. The library might offer functions to help you in future versions. Your code should realize when it is split screen and adjust the ui accordingly regardless.

	$(H2 Library internals)

	To better understand why things work the way they do, here's an overview of the internal architecture of the library. Much of the information here may be changed in future versions of the library, so try to think more about the concepts than the specifics as you read.

	$(H3 The game clock)

	$(H3 Thread layout)

	It runs four threads: a UI thread, a graphics thread, an audio thread, and a game thread.

	The UI thread runs your `getWindow` function, but otherwise is managed by the library. It handles input messages, window resizes, and other things. Being built on [arsd.simpledisplay], it is possible for you to do work in it with the `runInGuiThread` and `runInGuiThreadAsync` functions, which might be useful if, for example, you wanted to open other windows. But you should generally avoid it.

	The graphics thread runs your `load` and `drawFrame` functions. It gets the OpenGL context bound to it after the window is created, and expects to always have it. Since OpenGL contexts cannot be simultaneously shared across two threads, this means your other functions shouldn't try to access any of these objects. (It is possible to release the context from one thread, then attach it in another - indeed, the library does this between `getWindow` and `load` - but doing this in your user code is not supported and you'd try it at your own risk.)

	The audio thread is created if `wantAudio` is true and is communicated to via the `audio` object in your game class. The library manages it for you and the methods in the `audio` object tell it what to do. You are permitted to call these from your `update` function, or to load sound assets from your `load` function.

	Finally, the game thread is responsible for running your `update` function at a regular interval. The library coordinates sharing your game state between it and the graphics thread with a mutex. You can get more fine-grained control over this by overriding `updateWithManualLock`. The default is for `drawFrame` and `update` to never run simultaneously to keep data sharing to a minimum, but if you know what you're doing, you can make the lock time very very small by limiting the amount of writable data is actually shared. The default is what it is to keep things simple for you and should work most the time, though.

	Most computer programs are written either as batch processors or as event-driven applications. Batch processors do their work when requested, then exit. Event-driven applications, including many video games, wait for something to happen, like the user pressing a key or clicking the mouse, respond to it, then go back to waiting. These might do some animations, but this is the exception to its run time, not the rule. You are assumed to be waiting for events, but can `requestAnimationFrame` for the special occasions.

	But this is the rule for the third category of programs: time-driven programs, and many video games fall into this category. This is what `arsd.game` tries to make easy. It assumes you want a timed `update` and a steady stream of animation frames, and if you want to make an exception, you can pause updates until an event comes in. FIXME: `pauseUntilNextInput`. `designFps` = 0, `requestAnimationFrame`, `requestAnimation(duration)`

	$(H3 Webassembly implementation)

	See_Also:
		[arsd.ttf.OpenGlLimitedFont]

	History:
		The [GameHelperBase], indeed most the module, was completely redesigned in November 2022. If you
		have code that depended on the old way, you're probably better off keeping a copy of the old module
		and not updating it again.

		However, if you want to update it, you can approximate the old behavior by making a single `GameScreen`
		and moving most your code into it, especially the `drawFrame` and `update` methods, and returning that
		as the `firstScreen`.
+/
module arsd.game;

/+
	Platformer demo:
		dance of sugar plum fairy as you are the fairy jumping around
	Board game demo:
		good old chess
	3d first person demo:
		orbit simulator. your instruments show the spacecraft orientation relative to direction of motion (0 = prograde, 180 = retrograde yaw then the pitch angle relative to the orbit plane with up just being a thing) and your orbit params (apogee, perigee, phase, etc. also show velocity and potential energy relative to planet). and your angular velocity in three dimensions

		you just kinda fly around. goal is to try to actually transfer to another station successfully.

		play blue danube song lol

+/


// i will want to keep a copy of these that the events update, then the pre-frame update call just copies it in
// just gotta remember potential cross-thread issues; the write should prolly be protected by a mutex so it all happens
// together when the frame begins
struct VirtualJoystick {
	// the mouse sets one thing and the right stick sets another
	// both will update it, so hopefully people won't move mouse and joystick at the same time.
	private float[2] currentPosition_ = 0.0;
	private float[2] positionLastAsked_ = 0.0;

	float[2] currentPosition() {
		return currentPosition_;
	}

	float[2] changeInPosition() {
		auto tmp = positionLastAsked_;
		positionLastAsked_ = currentPosition_;
		return [currentPosition_[0] - tmp[0], currentPosition_[1] - tmp[1]];
	}

}

struct MouseAccess {
	// the mouse buttons can be L and R on the virtual gamepad
	int[2] currentPosition_;
}

struct KeyboardAccess {
	// state based access

	int lastChange; // in terms of the game clock's frame counter

	void startRecordingCharacters() {

	}

	string getRecordedCharacters() {
		return "";
	}

	void stopRecordingCharacters() {

	}
}

struct MousePath {
	static struct Waypoint {
		// Duration timestamp
		// x, y
		// button flags
	}

	Waypoint[] path;

}

struct JoystickPath {
	static struct Waypoint {
		// Duration timestamp
		// x, y
		// button flags
	}

	Waypoint[] path;
}

/++
	See [GameScreen] for the thing you are supposed to use. This is just for internal use by the arsd.game library.
+/
class GameScreenBase {
	abstract inout(GameHelperBase) game() inout;
	abstract void update();
	abstract void drawFrame(float interpolate);
	abstract void load();

	private bool loaded;
	final void ensureLoaded(GameHelperBase game) {
		if(!this.loaded) {
			// FIXME: unpause the update thread when it is done
			synchronized(game) {
				if(!this.loaded) {
					this.load();
					this.loaded = true;
				}
			}
		}
	}
}

/+
	you ask for things to be done - foo();
	and other code asks you to do things - foo() { }


	Recommended drawing methods:
		old opengl
		new opengl
		nanovega

	FIXME:
		for nanovega, load might want a withNvg()
		both load and drawFrame might want a nvgFrame()

		game.nvgFrame((nvg) {

		});
+/

/++
	Tip: if your screen is a generic component reused across many games, you might pass `GameHelperBase` as the `Game` parameter.
+/
class GameScreen(Game) : GameScreenBase {
	private Game game_;

	// convenience accessors
	final AudioOutputThread audio() {
		if(this is null || game is null) return AudioOutputThread.init;
		return game.audio;
	}

	final VirtualController snes() {
		if(this is null || game is null) return VirtualController.init;
		return game.snes;
	}

	/+
		manual draw mode turns off the automatic timer to render and only
		draws when you specifically trigger it. might not be worth tho.
	+/


	// You are not supposed to call this.
	final void setGame(Game game) {
		// assert(game_ is null);
		assert(game !is null);
		this.game_ = game;
	}

	/++
		Gives access to your game object for use through the screen.
	+/
	public override inout(Game) game() inout {
		if(game_ is null)
			throw new Exception("The game screen isn't showing!");
		return game_;
	}

	/++
		`update`'s responsibility is to:

		$(LIST
			* Process player input
			* Update game state - object positions, do collision detection, etc.
			* Run any character AI
			* Kick off any audio associated with changes in this update
			* Transition to other screens if appropriate
		)

		It is NOT supposed to:

		$(LIST
			* draw - that's the job of [drawFrame]
			* load files, bind textures, or similar - that's the job of [load]
			* set uniforms or other OpenGL objects - do one-time things in [load] and per-frame things in [drawFrame]
		)
	+/
	override abstract void update();

	/++
		`drawFrame`'s responsibility is to draw a single frame. It can use the `interpolate` method to smooth animations between updates.

		It should NOT change any variables in the game state or attempt to do things like collision detection - that's [update]'s job. When interpolating, just assume the objects are going to keep doing what they're doing.

		It should also NOT load any files, create textures, or any other setup task - [load] is supposed to have already done that.
	+/
	override abstract void drawFrame(float interpolate);

	/++
		Load your graphics and other assets in this function. You are allowed to draw to the screen while loading, but note you'll have to manage things like buffer swapping yourself if you do. [drawFrame] and [update] will be paused until loading is complete. This function will be called exactly once per screen object, right as it is first shown.
	+/
	override void load() {}
}

/// ditto
//alias GenericGameScreen = GameScreen!GameHelperBase;

///
unittest {
	// The TitleScreen has a simple job: show the title until the user presses start. After that, it will progress to the GameplayScreen.

	static // exclude from docs
	class DemoGame : GameHelperBase {
		// I put this inside DemoGame for this demo, but you could define them in separate files if you wanted to
		static class TitleScreen : GameScreen!DemoGame {
			override void update() {
				// you can always access your main Game object through the screen objects
				if(game.snes[VirtualController.Button.Start]) {
					//game.showScreen(new GameplayScreen());
				}
			}

			override void drawFrame(float interpolate) {

			}
		}

		// and the minimum boilerplate the game itself must provide for the library
		// is the window it wants to use and the first screen to load into it.
		override TitleScreen firstScreen() {
			return new TitleScreen();
		}

		override SimpleWindow getWindow() {
			auto window = create2dWindow("Demo game");
			return window;
		}
	}

	void main() {
		runGame!DemoGame();
	}

	main(); // exclude from docs
}

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

import arsd.core;

import arsd.simpledisplay : Timer;

public import arsd.joystick;

/++
	Creates a simple 2d (old-style) opengl simpledisplay window. It sets the matrix for pixel coordinates and enables alpha blending and textures.
+/
SimpleWindow create2dWindow(string title, int width = 512, int height = 512) {
	auto window = new SimpleWindow(width, height, title, OpenGlOptions.yes);

	//window.visibleForTheFirstTime = () {
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
	//};

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

		window.setAsCurrentOpenGlContext();
		glViewport(x, y, w, h);
		window.redrawOpenGlSceneSoon();
	};

	return window;
}

/++
	This is the base class for your game. Create a class based on this, then pass it to [runGame].
+/
abstract class GameHelperBase : SynchronizableObject {
	/++
		Implement this to draw.

		The `interpolateToNextFrame` argument tells you how close you are to the next frame. You should
		take your current state and add the estimated next frame things multiplied by this to get smoother
		animation. interpolateToNextFrame will always be >= 0 and < 1.0.

		History:
			Previous to August 27, 2022, this took no arguments. It could thus not interpolate frames!
	+/
	deprecated("Move to void drawFrame(float) in a GameScreen instead") void drawFrame(float interpolateToNextFrame) {
		drawFrameInternal(interpolateToNextFrame);
	}

	final void drawFrameInternal(float interpolateToNextFrame) {
		if(currentScreen is null)
			return;

		currentScreen.ensureLoaded(this);
		currentScreen.drawFrame(interpolateToNextFrame);
	}

	// in frames
	ushort snesRepeatRate() { return ushort.max; }
	ushort snesRepeatDelay() { return snesRepeatRate(); }

	/++
		Implement this to update your game state by a single fixed timestep. You should
		check for user input state here.

		Return true if something visibly changed to queue a frame redraw asap.

		History:
			Previous to August 27, 2022, this took an argument. This was a design flaw.
	+/
	deprecated("Move to void update in a GameScreen instead") bool update() { return false; }

	/+
		override this to have more control over synchronization

		its main job is to lock on `this` and update what [update] changes
		and call `bookkeeping` while inside the lock

		but if you have some work that can be done outside the lock - things
		that are read-only on the game state - you might split it up here and
		batch your update. as long as nothing that the [drawFrame] needs is mutated
		outside the lock you'll be ok.

		History:
			Added November 12, 2022
	+/
	bool updateWithManualLock(scope void delegate() bookkeeping) shared {
		if(currentScreen is null)
			return false;
		synchronized(this) {
			if(currentScreen.loaded)
				(cast() this).currentScreen.update();
			bookkeeping();
			return false;
		}
	}
	//abstract void fillAudioBuffer(short[] buffer);

	/++
		Returns the main game window. This function will only be
		called once if you use runGame. You should return a window
		here like one created with `create2dWindow`.
	+/
	abstract SimpleWindow getWindow();

	/++
		Override this and return true to initialize the audio system. If you return `true`
		here, the [audio] member can be used.
	+/
	bool wantAudio() { return false; }

	/++
		Override this and return true if you are compatible with separate render and update threads.
	+/
	bool multithreadCompatible() { return true; }

	/// You must override [wantAudio] and return true for this to be valid;
	AudioOutputThread audio;

	this() {
		audio = AudioOutputThread(wantAudio());
	}

	protected bool redrawForced;

	private GameScreenBase currentScreen;

	/+
	// it will also need a configuration in time and such
	enum ScreenTransition {
		none,
		crossFade
	}
	+/

	/++
		Shows the given screen, making it actively responsible for drawing and updating,
		optionally through the given transition effect.
	+/
	void showScreen(this This, Screen)(Screen cs, GameScreenBase transition = null) {
		cs.setGame(cast(This) this);
		currentScreen = cs;
		// FIXME: pause the update thread here, and fast forward the game clock when it is unpaused
		// (this actually SHOULD be called from the update thread, except for the initial load... and even that maybe it will then)
		// but i have to be careful waiting here because it can deadlock with teh mutex still locked.
	}

	/++
		Returns the first screen of your game.
	+/
	abstract GameScreenBase firstScreen();

	/++
		Returns the number of game updates per second your game is designed for.

		This isn't necessarily the number of frames drawn per second, which may be more
		or less due to frame skipping and interpolation, but it is the number of times
		your screen's update methods will be called each second.

		You actually want to make this as small as possible without breaking your game's
		physics and feeling of responsiveness to the controls. Remember, the display FPS
		is different - you can interpolate frames for smooth animation. What you want to
		ensure here is that the design fps is big enough that you don't have problems like
		clipping through walls or sluggishness in player control, but not so big that the
		computer is busy doing collision detection, etc., all the time and has no time
		left over to actually draw the game.

		I personally find 20 actually works pretty well, though the default set here is 60
		due to how common that number is. You are encouraged to override this and use what
		works for you.
	+/
	int designFps() { return 60; }

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

	Additionally, the mouse is mapped to the virtual joystick, and mouse buttons left and right are mapped to shoulder buttons L and R.


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

	/+
	+/

	VirtualJoystick stick;

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

struct ButtonCheck {
	bool wasPressed() {
		return false;
	}
	bool wasReleased() {
		return false;
	}
	bool wasClicked() {
		return false;
	}
	bool isHeld() {
		return false;
	}

	bool opCast(T : bool)() {
		return isHeld();
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
void runGame()(GameHelperBase game, int targetUpdateRate = 20, int maxRedrawRate = 0) { assert(0, "this overload is deprecated, use runGame!YourClass instead"); }

/++
	Runs your game. It will construct the given class and destroy it at end of scope.
	Your class must have a default constructor and must implement [GameHelperBase].
	Your class should also probably be `final` for a small, but easy performance boost.

	$(TIP
		If you need to pass parameters to your game class, you can define
		it as a nested class in your `main` function and access the local
		variables that way instead of passing them explicitly through the
		constructor.
	)

	Params:
	targetUpdateRate = The number of game state updates you get per second. You want this to be quick enough that players don't feel input lag, but conservative enough that any supported computer can keep up with it easily.
	maxRedrawRate = The maximum draw frame rate. 0 means it will only redraw after a state update changes things. It will be automatically capped at the user's monitor refresh rate. Frames in between updates can be interpolated or skipped.
+/
void runGame(T : GameHelperBase)(int targetUpdateRate = 0, int maxRedrawRate = 0) {

	auto game = new T();
	scope(exit) .destroy(game);

	if(targetUpdateRate == 0)
		targetUpdateRate = game.designFps();

	// this is a template btw because then it can statically dispatch
	// the members instead of going through the virtual interface.

	auto window = game.getWindow();
	game.showScreen(game.firstScreen());

	auto lastUpdate = MonoTime.currTime;
	bool isImmediateUpdate;

	int joystickPlayers;

	window.redrawOpenGlScene = null;

	/*
		The game clock should always be one update ahead of the real world clock.

		If it is behind the real world clock, it needs to run update faster, so it will
		double up on its timer to try to update and skip some render frames to make cpu time available.
		Generally speaking the render should never be more than one full frame ahead of the game clock,
		and since the game clock should always be a bit ahead of the real world clock, if the game clock
		is behind the real world clock, time to skip.

		If there's a huge jump in the real world clock - more than a couple seconds between
		updates - this probably indicates the computer went to sleep or something. We can't
		catch up, so this will just resync the clock to real world and not try to catch up.
	*/
	MonoTime gameClock;
	// FIXME: render thread should be lower priority than the ui thread

	int rframeCounter = 0;
	auto drawer = delegate bool() {
		if(gameClock is MonoTime.init)
			return false; // can't draw uninitialized info
		/* // i think this is the same as if delta < 0 below...
		auto time = MonoTime.currTime;
		if(gameClock + (1000.msecs / targetUpdateRate) < time) {
			writeln("frame skip ", gameClock, " vs ", time);
			return false; // we're behind on updates, skip this frame
		}
		*/

		if(false && isImmediateUpdate) {
			game.drawFrameInternal(0.0);
			isImmediateUpdate = false;
		} else {
			auto now = MonoTime.currTime - lastUpdate;
			Duration nextFrame = msecs(1000 / targetUpdateRate);
			auto delta = cast(float) ((nextFrame - now).total!"usecs") / cast(float) nextFrame.total!"usecs";

			if(delta < 0) {
				//writeln("behind ", cast(int)(delta * 100));
				return false; // the render is too far ahead of the updater! time to skip frames to let it catch up
			}

			game.drawFrameInternal(1.0 - delta);
		}

		rframeCounter++;
		/+
		if(rframeCounter % 60 == 0) {
			writeln("frame");
		}
		+/

		return true;
	};

	import core.thread;
	import core.volatile;
	Thread renderThread; // FIXME: low priority
	Thread updateThread; // FIXME: slightly high priority

	// shared things to communicate with threads
	ubyte exit;
	ulong newWindowSize;
	ubyte loadRequired; // if the screen changed and you need to call load again in the render thread

	ubyte workersPaused;
	// Event unpauseRender; // maybe a manual reset so you set it then reset after unpausing
	// Event unpauseUpdate;

	// the input buffers should prolly be double buffered generally speaking

	// FIXME: i might just want an asset cache thing
	// FIXME: ffor audio, i want to be able to play a sound to completion without necessarily letting it play twice simultaneously and then replay it later. this would be a sound effect thing. but you might also play it twice anyway if there's like two shots so meh. and then i'll need BGM controlling in the game and/or screen.

	Timer renderTimer;
	Timer updateTimer;

	auto updater = delegate() {
		if(gameClock is MonoTime.init) {
			gameClock = MonoTime.currTime;
		}

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

		int runs;

		again:

		auto now = MonoTime.currTime;
		bool changed;
		changed = (cast(shared)game).updateWithManualLock({ lastUpdate = now; });
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

		if(game.redrawForced) {
			changed = true;
			game.redrawForced = false;
		}

		gameClock += 1.seconds / targetUpdateRate;

		if(++runs < 3 && gameClock < MonoTime.currTime)
			goto again;

		// FIXME: rate limiting
		// FIXME: triple buffer it.
		if(changed && renderThread is null) {
			isImmediateUpdate = true;
			window.redrawOpenGlSceneSoon();
		}
	};

	//window.vsync = false;

	const maxRedrawTime = maxRedrawRate > 0 ? (1000.msecs / maxRedrawRate) : 4.msecs;

	if(game.multithreadCompatible()) {
		window.redrawOpenGlScene = null;
		renderThread = new Thread({
			// FIXME: catch exception and inform the parent
			int frames = 0;
			int skipped = 0;

			Duration renderTime;
			Duration flipTime;
			Duration renderThrottleTime;

			MonoTime initial = MonoTime.currTime;

			while(!volatileLoad(&exit)) {
				MonoTime start = MonoTime.currTime;
				{
					window.mtLock();
					scope(exit)
						window.mtUnlock();
					window.setAsCurrentOpenGlContext();
				}

				bool actuallyDrew;

				synchronized(game)
					actuallyDrew = drawer();

				MonoTime end = MonoTime.currTime;

				if(actuallyDrew) {
					window.mtLock();
					scope(exit)
						window.mtUnlock();
					window.swapOpenGlBuffers();
				}
				// want to ensure the vsync wait occurs here, outside the window and locks
				// some impls will do it on glFinish, some on the next touch of the
				// front buffer, hence the clear being done here.
				if(actuallyDrew) {
					glFinish();
					clearOpenGlScreen(window);
				}

				// this is just to wake up the UI thread to check X events again
				// (any custom event will force a check of XPending) just cuz apparently
				// the readiness of the file descriptor can be reset by one of the vsync functions
				static if(UsingSimpledisplayX11) {
					__gshared thing = new Object;
					window.postEvent(thing);
				}

				MonoTime flip = MonoTime.currTime;

				renderTime += end - start;
				flipTime += flip - end;

				if(flip - start < maxRedrawTime) {
					renderThrottleTime += maxRedrawTime - (flip - start);
					Thread.sleep(maxRedrawTime - (flip - start));
				}

				if(actuallyDrew)
					frames++;
				else
					skipped++;
				// if(frames % 60 == 0) writeln("frame");
			}

			MonoTime finalt = MonoTime.currTime;

			writeln("Average render time: ", renderTime / frames);
			writeln("Average flip time: ", flipTime / frames);
			writeln("Average throttle time: ", renderThrottleTime / frames);
			writeln("Frames: ", frames, ", skipped: ", skipped, " over ", finalt - initial);
		});

		updateThread = new Thread({
			// FIXME: catch exception and inform the parent
			int frames;

			joystickPlayers = enableJoystickInput();
			scope(exit) closeJoysticks();

			Duration updateTime;
			Duration waitTime;

			while(!volatileLoad(&exit)) {
				MonoTime start = MonoTime.currTime;
				updater();
				MonoTime end = MonoTime.currTime;

				updateTime += end - start;

				frames++;
				// if(frames % game.designFps == 0) writeln("update");

				const now = MonoTime.currTime - lastUpdate;
				Duration nextFrame = msecs(1000) / targetUpdateRate;
				const sleepTime = nextFrame - now;
				if(sleepTime.total!"msecs" <= 0) {
					// falling behind on update...
				} else {
					waitTime += sleepTime;
					// writeln(sleepTime);
					Thread.sleep(sleepTime);
				}
			}

			writeln("Average update time: " , updateTime / frames);
			writeln("Average wait time: " , waitTime / frames);
		});
	} else {
		// single threaded, vsync a bit dangeresque here since it
		// puts the ui thread to sleep!
		window.vsync = false;
	}

	// FIXME: when single threaded, set the joystick here
	// actually just always do the joystick in the event thread regardless

	int frameCounter;

	auto first = window.visibleForTheFirstTime;
	window.visibleForTheFirstTime = () {
		if(first)
			first();

		if(updateThread) {
			updateThread.start();
		} else {
			updateTimer = new Timer(1000 / targetUpdateRate, {
				frameCounter++;
				updater();
			});
		}

		if(renderThread) {
			window.suppressAutoOpenglViewport = true; // we don't want the context being pulled back by the other thread now, we'll check it over here.
			// FIXME: set viewport prior to render if width/height changed
			window.releaseCurrentOpenGlContext(); // need to let the render thread take it
			renderThread.start();
			renderThread.priority = Thread.PRIORITY_MIN;
		} else {
			window.redrawOpenGlScene = { synchronized(game) drawer(); };
			renderTimer = new Timer(1000 / 60, { window.redrawOpenGlSceneSoon(); });
		}
	};

	window.onClosing = () {
		volatileStore(&exit, 1);

		if(updateTimer) {
			updateTimer.dispose();
			updateTimer = null;
		}
		if(renderTimer) {
			renderTimer.dispose();
			renderTimer = null;
		}

		if(renderThread) {
			renderThread.join();
			renderThread = null;
		}
		if(updateThread) {
			updateThread.join();
			updateThread = null;
		}
	};

	Thread.getThis.priority = Thread.PRIORITY_MAX;

	window.eventLoop(0,
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
+/
// Doesn't do mipmapping btw.
final class OpenGlTexture {
	private uint _tex;
	private int _width;
	private int _height;
	private float _texCoordWidth;
	private float _texCoordHeight;

	/// Calls glBindTexture
	void bind() {
		doLazyLoad();
		glBindTexture(GL_TEXTURE_2D, _tex);
	}

	/// For easy 2d drawing of it
	void draw(Point where, int width = 0, int height = 0, float rotation = 0.0, Color bg = Color.white) {
		draw(where.x, where.y, width, height, rotation, bg);
	}

	///
	void draw(float x, float y, int width = 0, int height = 0, float rotation = 0.0, Color bg = Color.white) {
		doLazyLoad();
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
	uint tex() { doLazyLoad(); return _tex; }

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

	private TrueColorImage pendingImage;

	private final void doLazyLoad() {
		if(pendingImage !is null) {
			auto tmp = pendingImage;
			pendingImage = null;
			bindFrom(tmp);
		}
	}

	/++
		After you delete it with dispose, you may rebind it to something else with this.

		If the current thread doesn't own an opengl context, it will save the image to try to lazy load it later.
	+/
	void bindFrom(TrueColorImage from) {
		assert(from !is null);
		assert(from.width > 0 && from.height > 0);

		import core.stdc.stdlib;

		_width = from.width;
		_height = from.height;

		this.from = from;

		if(openGLCurrentContext() is null) {
			pendingImage = from;
			return;
		}

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


/++
	NOT fully compatible with simpledisplay's screenpainter, but emulates some of its api.

	I want it to be runtime swappable between the fancy opengl and a backup one for my remote X purposes.
+/
class ScreenPainterImpl : BasicDrawing {
	Color outlineColor;
	Color fillColor;

	import arsd.ttf;

	SimpleWindow window;
	OpenGlLimitedFontBase!() font;

	this(SimpleWindow window, OpenGlLimitedFontBase!() font) {
		this.window = window;
		this.font = font;
	}

	void clear(Color c) {
		fillRectangle(Rectangle(Point(0, 0), Size(window.width, window.height)), c);
	}

	void drawRectangle(Rectangle r) {
		fillRectangle(r, fillColor);
		Point[4] vertexes = [
			r.upperLeft,
			r.upperRight,
			r.lowerRight,
			r.lowerLeft
		];
		outlinePolygon(vertexes[], outlineColor);
	}
	void drawRectangle(Point ul, Size sz) {
		drawRectangle(Rectangle(ul, sz));
	}
	void drawText(Point upperLeft, scope const char[] text) {
		drawText(Rectangle(upperLeft, Size(4096, 4096)), text, outlineColor);
	}


	void fillRectangle(Rectangle r, Color c) {
		glBegin(GL_QUADS);
		glColor4f(c.r / 255.0, c.g / 255.0, c.b / 255.0, c.a / 255.0);

		with(r) {
			glVertex2i(upperLeft.x, upperLeft.y);
			glVertex2i(upperRight.x, upperRight.y);
			glVertex2i(lowerRight.x, lowerRight.y);
			glVertex2i(lowerLeft.x, lowerLeft.y);
		}

		glEnd();
	}
	void outlinePolygon(Point[] vertexes, Color c) {
		glBegin(GL_LINE_LOOP);
		glColor4f(c.r / 255.0, c.g / 255.0, c.b / 255.0, c.a / 255.0);

		foreach(vertex; vertexes) {
			glVertex2i(vertex.x, vertex.y);
		}

		glEnd();
	}
	void drawText(Rectangle boundingBox, scope const char[] text, Color color) {
		font.drawString(boundingBox.upperLeft.tupleof, text, color);
	}

	protected int refcount;

	void flush() {

	}
}

struct ScreenPainter {
	ScreenPainterImpl impl;

	this(ScreenPainterImpl impl) {
		this.impl = impl;
		impl.refcount++;
	}

	this(this) {
		if(impl)
			impl.refcount++;
	}

	~this() {
		if(impl)
			if(--impl.refcount == 0)
				impl.flush();
	}

	alias impl this;
}
