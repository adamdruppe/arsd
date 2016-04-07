// WORK IN PROGRESS

/++
	An add-on for simpledisplay.d, joystick.d, and simpleaudio.d
	that includes helper functions for writing games (and perhaps
	other multimedia programs).

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
		override void update(Duration deltaTime) {
			x += 1;
			y += 1;
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
+/
module arsd.gamehelpers;

public import arsd.color;
public import arsd.simpledisplay;

import std.math;
public import core.time;

public import arsd.joystick;

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

	return window;
}

/// This is the base class for your game.
class GameHelperBase {
	/// Implement this to draw.
	abstract void drawFrame();

	/// Implement this to update. The deltaTime tells how much real time has passed since the last update.
	abstract void update(Duration deltaTime);
	//abstract void fillAudioBuffer(short[] buffer);

	/// Returns the main game window. This function will only be
	/// called once if you use runGame. You should return a window
	/// here like one created with `create2dWindow`.
	abstract SimpleWindow getWindow();


	/// These functions help you handle user input. It offers polling functions for
	/// keyboard, mouse, joystick, and virtual controller input.
	///
	/// The virtual digital controllers are best to use if that model fits you because it
	/// works with several kinds of controllers as well as keyboards.

	JoystickUpdate joystick1;
}

/// The max rates are given in executions per second
/// Redraw will never be called unless there has been at least one update
void runGame(T : GameHelperBase)(T game, int maxUpdateRate = 20, int maxRedrawRate = 0) {
	// this is a template btw because then it can statically dispatch
	// the members instead of going through the virtual interface.

	int joystickPlayers = enableJoystickInput();
	scope(exit) closeJoysticks();

	auto window = game.getWindow();

	window.redrawOpenGlScene = &game.drawFrame;

	auto lastUpdate = MonoTime.currTime;

	window.eventLoop(1000 / maxUpdateRate,
		delegate() {
			if(joystickPlayers) {
				version(linux)
					readJoystickEvents(joystickFds[0]);
				auto update = getJoystickUpdate(0);
				game.joystick1 = update;
			} else assert(0);

			auto now = MonoTime.currTime;
			game.update(now - lastUpdate);
			lastUpdate = now;

			// FIXME: rate limiting
			window.redrawOpenGlSceneNow();
		},

		delegate (KeyEvent ke) {
			// FIXME
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
		assert(from.width > 0 && from.height > 0);

		_width = from.width;
		_height = from.height;

		this.from = from;

		auto _texWidth = _width;
		auto _texHeight = _height;

		const(ubyte)[] data = from.imageData.bytes;

		// gotta round them to the nearest power of two which means padding the image
		if((_texWidth & (_texWidth - 1)) || (_texHeight & (_texHeight - 1))) {
			_texWidth = nextPowerOfTwo(_texWidth);
			_texHeight = nextPowerOfTwo(_texHeight);

			auto n = new ubyte[](_texWidth * _texHeight * 4);
			auto size = from.width * 4;
			auto advance = _texWidth * 4;
			int at = 0;
			int at2 = 0;
			foreach(y; 0 .. from.height) {
				n[at .. at + size] = from.imageData.bytes[at2 .. at2+ size];
				at += advance;
				at2 += size;
			}

			data = n[];

			// the rest of data will be initialized to zeros automatically which is fine.
		}

		glGenTextures(1, &_tex);
		glBindTexture(GL_TEXTURE_2D, tex);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

		glTexImage2D(
			GL_TEXTURE_2D,
			0,
			GL_RGBA,
			_texWidth, // needs to be power of 2
			_texHeight,
			0,
			GL_RGBA,
			GL_UNSIGNED_BYTE,
			data.ptr);

		assert(!glGetError());

		_texCoordWidth = cast(float) _width / _texWidth;
		_texCoordHeight = cast(float) _height / _texHeight;
	}

	/// Generates from text. Requires stb_truetype.d
	/// pass a pointer to the TtfFont as the first arg (it is template cuz of lazy importing, not because it actually works with different types)
	this(T, FONT)(FONT* font, int size, in T[] text) if(is(T == char)) {
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

		this(image);
	}

	~this() {
		glDeleteTextures(1, &_tex);
	}
}


// Some math helpers

int nextPowerOfTwo(int v) {
	v--;
	v |= v >> 1;
	v |= v >> 2;
	v |= v >> 4;
	v |= v >> 8;
	v |= v >> 16;
	v++;
	return v;
}

void crossProduct(
	float u1, float u2, float u3,
	float v1, float v2, float v3,
	out float s1, out float s2, out float s3)
{
	s1 = u2 * v3 - u3 * v2;
	s2 = u3 * v1 - u1 * v3;
	s3 = u1 * v2 - u2 * v1;
}

void rotateAboutAxis(
	float theta, // in RADIANS
	float x, float y, float z,
	float u, float v, float w,
	out float xp, out float yp, out float zp)
{
	xp = u * (u*x + v*y + w*z) * (1 - cos(theta)) + x * cos(theta) + (-w*y + v*z) * sin(theta);
	yp = v * (u*x + v*y + w*z) * (1 - cos(theta)) + y * cos(theta) + (w*x - u*z) * sin(theta);
	zp = w * (u*x + v*y + w*z) * (1 - cos(theta)) + z * cos(theta) + (-v*x + u*y) * sin(theta);
}

void rotateAboutPoint(
	float theta, // in RADIANS
	float originX, float originY,
	float rotatingX, float rotatingY,
	out float xp, out float yp)
{
	if(theta == 0) {
		xp = rotatingX;
		yp = rotatingY;
		return;
	}

	rotatingX -= originX;
	rotatingY -= originY;

	float s = sin(theta);
	float c = cos(theta);

	float x = rotatingX * c - rotatingY * s;
	float y = rotatingX * s + rotatingY * c;

	xp = x + originX;
	yp = y + originY;
}
