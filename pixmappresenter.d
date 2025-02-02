/+
	== pixmappresenter ==
	Copyright Elias Batek (0xEAB) 2023 - 2024.
	Distributed under the Boost Software License, Version 1.0.
 +/
/++
	$(B Pixmap Presenter) is a high-level display library for one specific scenario:
	Blitting fully-rendered frames to the screen.

	This is useful for software-rendered applications.
	Think of old-skool games, emulators etc.

	This library builds upon [arsd.simpledisplay] and [arsd.color].
	It wraps a [arsd.simpledisplay.SimpleWindow|SimpleWindow] and displays the provided frame data.
	Each frame is automatically centered on, and optionally scaled to, the carrier window.
	This processing is done with hardware acceleration (OpenGL).
	Later versions might add a software-mode.

	Several $(B scaling) modes are supported.
	Most notably [pixmappresenter.Scaling.contain|contain] that scales pixmaps to the window’s current size
	while preserving the original aspect ratio.
	See [Scaling] for details.

	$(PITFALL
		This module is $(B work in progress).
		API is subject to changes until further notice.
	)

	## Usage examples

	### Basic usage

	This example displays a blue frame that increases in color intensity,
	then jumps back to black and the process repeats.

	---
	void main() {
		// Internal resolution of the images (“frames”) we will render.
		// From the PixmapPresenter’s perspective,
		// these are the “fully-rendered frames” that it will blit to screen.
		// They may be up- & down-scaled to the window’s actual size
		// (according to the chosen scaling mode) by the presenter.
		const resolution = Size(240, 120);

		// Let’s create a new presenter.
		// (For more fine-grained control there’s also a constructor overload that
		// accepts a [PresenterConfig] instance).
		auto presenter = new PixmapPresenter(
			"Demo",         // window title
			resolution,     // internal resolution
			Size(960, 480), // initial window size (optional; default: =resolution)
		);

		// This variable will be “shared” across events (and frames).
		int blueChannel = 0;

		// Run the eventloop.
		// The callback delegate will get executed every ~16ms (≙ ~60FPS) and schedule a redraw.
		presenter.eventLoop(16, delegate() {
			// Update the pixmap (“framebuffer”) here…

			// Construct an RGB color value.
			auto color = Pixel(0x00, 0x00, blueChannel);
			// For demo purposes, apply it to the whole pixmap.
			presenter.framebuffer.clear(color);

			// Increment the amount of blue to be used by the next frame.
			++blueChannel;
			// reset if greater than 0xFF (=ubyte.max)
			if (blueChannel > 0xFF)
				blueChannel = 0;
		});
	}
	---

	### Minimal example

	---
	void main() {
		auto pmp = new PixmapPresenter("My Pixmap App", Size(640, 480));
		pmp.framebuffer.clear(rgb(0xFF, 0x00, 0x99));
		pmp.eventLoop();
	}
	---

	### Advanced example

	---
	import arsd.pixmappresenter;

	int main() {
		// Internal resolution of the images (“frames”) we will render.
		// For further details, check out the “Basic usage” example.
		const resolution = Size(240, 120);

		// Configure our presenter in advance.
		auto cfg = PresenterConfig();
		cfg.window.title = "Demo II";
		cfg.window.size = Size(960, 480);
		cfg.renderer.resolution = resolution;
		cfg.renderer.scaling = Scaling.integer; // integer scaling
		                                        // → The frame on-screen will
		                                        // always have a size that is a
		                                        // multiple of the internal
		                                        // resolution.
		                                        // → Also check out the
		                                        // `intHybrid` scaling mode.
		// The gentle reader might have noticed that integer scaling will result
		// in a padding/border area around the image for most window sizes.
		// How about changing its color?
		cfg.renderer.background = ColorF(Pixel.white);

		// Let’s instantiate a new presenter with the previously created config.
		auto presenter = new PixmapPresenter(cfg);

		// Start with a green frame, so we can easily observe what’s going on.
		presenter.framebuffer.clear(rgb(0x00, 0xDD, 0x00));

		int line = 0;
		ubyte color = 0;
		byte colorDelta = 2;

		// Run the eventloop.
		// Note how the callback delegate returns a [LoopCtrl] instance.
		return presenter.eventLoop(delegate() {
			// Determine the start and end index of the current line in the
			// framebuffer.
			immutable x0 = line * resolution.width;
			immutable x1 = x0 + resolution.width;

			// Change the color of the current line
			presenter.framebuffer.data[x0 .. x1] = rgb(color, color, 0xFF);

			// Determine the color to use for the next line
			// (to be applied on the next update).
			color += colorDelta;
			if (color == 0x00)
				colorDelta = 2;
			else if (color >= 0xFE)
				colorDelta = -2;

			// Increment the line counter; reset to 0 once we’ve reached the
			// end of the framebuffer (=the final/last line).
			++line;
			if (line == resolution.height)
				line = 0;

			// Schedule a redraw in ~16ms.
			return LoopCtrl.redrawIn(16);
		}, delegate(MouseEvent ev) {
			// toggle fullscreen mode on double-click
			if (ev.doubleClick) {
				presenter.toggleFullscreen();
			}
		});
	}
	---
 +/
module arsd.pixmappresenter;

import arsd.core;

/++
	While publicly importing `arsd.simpledisplay` is not actually necessary,
	most real-world code would eventually import said module as well anyway.

	More importantly, this public import prevents users from facing certain
	symbol clashes in their code that would occur in modules importing both
	`pixmappresenter` and `simpledisplay`.
	For instance both of these modules happen to define different types
	as `Pixmap`.
 +/
public import arsd.simpledisplay;

///
public import arsd.pixmappaint;

/*
	## TODO

	- More comprehensive documentation
	- Additional renderer implementations:
		- a `ScreenPainter`-based renderer
	- Minimum window size
		- to ensure `Scaling.integer` doesn’t break “unexpectedly”
	- More control over timing
		- that’s a simpledisplay thing, though
 */

///
alias Pixmap = arsd.pixmappaint.Pixmap;

///
alias WindowResizedCallback = void delegate(Size);

// is the Timer class available on this platform?
private enum hasTimer = is(arsd.simpledisplay.Timer == class);

// resolve symbol clash on “Timer” (arsd.core vs arsd.simpledisplay)
static if (hasTimer) {
	private alias Timer = arsd.simpledisplay.Timer;
}

// viewport math
private @safe pure nothrow @nogc {

	// keep aspect ratio (contain)
	bool karContainNeedsDownscaling(const Size drawing, const Size canvas) {
		return (drawing.width > canvas.width)
			|| (drawing.height > canvas.height);
	}

	// keep aspect ratio (contain)
	int karContainScalingFactorInt(const Size drawing, const Size canvas) {
		const int w = canvas.width / drawing.width;
		const int h = canvas.height / drawing.height;

		return (w < h) ? w : h;
	}

	// keep aspect ratio (contain; FP variant)
	float karContainScalingFactorF(const Size drawing, const Size canvas) {
		const w = float(canvas.width) / float(drawing.width);
		const h = float(canvas.height) / float(drawing.height);

		return (w < h) ? w : h;
	}

	// keep aspect ratio (cover)
	float karCoverScalingFactorF(const Size drawing, const Size canvas) {
		const w = float(canvas.width) / float(drawing.width);
		const h = float(canvas.height) / float(drawing.height);

		return (w > h) ? w : h;
	}

	Size deltaPerimeter(const Size a, const Size b) {
		return Size(
			a.width - b.width,
			a.height - b.height,
		);
	}

	Point offsetCenter(const Size drawing, const Size canvas) {
		auto delta = canvas.deltaPerimeter(drawing);
		return (castTo!Point(delta) >> 1);
	}
}

///
struct Viewport {
	Size size; ///
	Point offset; ///
}

/++
	Calls `glViewport` with the data from the provided [Viewport].
 +/
void glViewportPMP(const ref Viewport vp) {
	glViewport(vp.offset.x, vp.offset.y, vp.size.width, vp.size.height);
}

/++
	Calculates the dimensions and position of the viewport for the provided config.

	$(TIP
		Primary use case for this is [PixmapRenderer] implementations.
	)
 +/
Viewport calculateViewport(const ref PresenterConfig config) @safe pure nothrow @nogc {
	Size size;

	final switch (config.renderer.scaling) {

	case Scaling.none:
		size = config.renderer.resolution;
		break;

	case Scaling.stretch:
		size = config.window.size;
		break;

	case Scaling.contain:
		const float scaleF = karContainScalingFactorF(config.renderer.resolution, config.window.size);
		size = Size(
			castTo!int(scaleF * config.renderer.resolution.width),
			castTo!int(scaleF * config.renderer.resolution.height),
		);
		break;

	case Scaling.integer:
		const int scaleI = karContainScalingFactorInt(config.renderer.resolution, config.window.size);
		size = (config.renderer.resolution * scaleI);
		break;

	case Scaling.intHybrid:
		if (karContainNeedsDownscaling(config.renderer.resolution, config.window.size)) {
			goto case Scaling.contain;
		}
		goto case Scaling.integer;

	case Scaling.cover:
		const float fillF = karCoverScalingFactorF(config.renderer.resolution, config.window.size);
		size = Size(
			castTo!int(fillF * config.renderer.resolution.width),
			castTo!int(fillF * config.renderer.resolution.height),
		);
		break;
	}

	const Point offset = offsetCenter(size, config.window.size);

	return Viewport(size, offset);
}

/++
	Scaling/Fit Modes

	Each scaling modes has unique behavior for different window-size to pixmap-size ratios.

	$(NOTE
		Unfortunately, there are no universally applicable naming conventions for these modes.
		In fact, different implementations tend to contradict each other.
	)

	$(SMALL_TABLE
		Mode feature matrix
		Mode        | Aspect Ratio | Pixel Ratio | Cropping | Border | Comment(s)
		`none`      | preserved    | preserved   | yes      | 4      | Crops if the `window.size < pixmap.size`.
		`stretch`   | no           | no          | no       | none   |
		`contain`   | preserved    | no          | no       | 2      | Letterboxing/Pillarboxing
		`integer`   | preserved    | preserved   | no       | 4      | Works only if `window.size >= pixmap.size`.
		`intHybrid` | preserved    | when up     | no       | 4 or 2 | Hybrid: int upscaling, decimal downscaling
		`cover`     | preserved    | no          | yes      | none   |
	)

	$(NOTE
		Integer scaling – Note that the resulting integer ratio of a window smaller than a pixmap is `0`.

		Use `intHybrid` to prevent the pixmap from disappearing on disproportionately small window sizes.
		It uses $(I integer)-mode for upscaling and the regular $(I contain)-mode for downscaling.
	)

	$(SMALL_TABLE
		Feature      | Definition
		Aspect Ratio | Whether the original aspect ratio (width ÷ height) of the input frame is preserved
		Pixel Ratio  | Whether the orignal pixel ratio (= square) is preserved
		Cropping     | Whether the outer areas of the input frame might get cut off
		Border       | The number of padding-areas/borders that can potentially appear around the frame
	)

	For your convience, aliases matching the [`object-fit`](https://developer.mozilla.org/en-US/docs/Web/CSS/object-fit)
	CSS property are provided, too. These are prefixed with `css`.
	Currently there is no equivalent for `scale-down` as it does not appear to be particularly useful here.
 +/
enum Scaling {
	none = 0, ///
	stretch, ///
	contain, ///
	integer, ///
	intHybrid, ///
	cover, ///

	// aliases
	center = none, ///
	keepAspectRatio = contain, ///

	// CSS `object-fit` style aliases
	cssNone = none, /// equivalent CSS: `object-fit: none;`
	cssContain = contain, /// equivalent CSS: `object-fit: contain;`
	cssFill = stretch, /// equivalent CSS: `object-fit: fill;`
	cssCover = cover, /// equivalent CSS: `object-fit: cover;`
}

///
struct PresenterConfig {
	Window window; ///
	Renderer renderer; ///

	///
	static struct Renderer {
		/++
			Internal resolution
		 +/
		Size resolution;

		/++
			Scaling method
			to apply when `window.size` != `resolution`
		 +/
		Scaling scaling = Scaling.keepAspectRatio;

		/++
			Scaling filter
		 +/
		ScalingFilter filter = ScalingFilter.nearest;

		/++
			Background color
		 +/
		ColorF background = ColorF(0.0f, 0.0f, 0.0f, 1.0f);

		///
		void setPixelPerfect() {
			scaling = Scaling.integer;
			filter = ScalingFilter.nearest;
		}
	}

	///
	static struct Window {
		///
		string title = "ARSD Pixmap Presenter";

		///
		Size size;

		/++
			Window corner style

			$(NOTE
				At the time of writing, this is only implemented on Windows.
				It has no effect elsewhere for now but does no harm either.

				Windows: Requires Windows 11 or later.
			)

			History:
				Added September 10, 2024.
		 +/
		CornerStyle corners = CornerStyle.rectangular;
	}
}

// undocumented
struct PresenterObjectsContainer {
	Pixmap framebuffer;
	SimpleWindow window;
	PresenterConfig config;
}

///
struct WantsOpenGl {
	ubyte vMaj; /// Major version
	ubyte vMin; /// Minor version
	bool compat; /// Compatibility profile? → true = Compatibility Profile; false = Core Profile

@safe pure nothrow @nogc:

	/// Is OpenGL wanted?
	bool wanted() const {
		return vMaj > 0;
	}
}

/++
	Renderer abstraction

	A renderer scales, centers and blits pixmaps to screen.
 +/
interface PixmapRenderer {
	/++
		Does this renderer use OpenGL?

		Returns:
			Whether the renderer requires an OpenGL-enabled window
			and which version is expected.
	 +/
	public WantsOpenGl wantsOpenGl() @safe pure nothrow @nogc;

	/++
		Setup function

		Called once during setup.
		Perform initialization tasks in here.

		$(NOTE
			The final thing a setup function does
			is usually to call `reconfigure()` on the renderer.
		)

		Params:
			container = Pointer to the [PresenterObjectsContainer] of the presenter. To be stored for later use.
	 +/
	public void setup(PresenterObjectsContainer* container);

	/++
		Reconfigures the renderer

		Called upon configuration changes.
		The new config can be found in the [PresenterObjectsContainer] received during `setup()`.
	 +/
	public void reconfigure();

	/++
		Schedules a redraw
	 +/
	public void redrawSchedule();

	/++
		Triggers a redraw
	 +/
	public void redrawNow();
}

/++
	OpenGL 3.0 implementation of a [PixmapRenderer]
 +/
final class OpenGl3PixmapRenderer : PixmapRenderer {

	private {
		PresenterObjectsContainer* _poc;

		GLfloat[16] _vertices;
		OpenGlShader _shader;
		GLuint _vao;
		GLuint _vbo;
		GLuint _ebo;
		GLuint _texture = 0;
	}

	///
	public this() {
	}

	public WantsOpenGl wantsOpenGl() @safe pure nothrow @nogc {
		return WantsOpenGl(3, 0, false);
	}

	public void setup(PresenterObjectsContainer* pro) {
		_poc = pro;
		_poc.window.suppressAutoOpenglViewport = true;
		_poc.window.visibleForTheFirstTime = &this.visibleForTheFirstTime;
		_poc.window.redrawOpenGlScene = &this.redrawOpenGlScene;
	}

	private {
		void visibleForTheFirstTime() {
			_poc.window.setAsCurrentOpenGlContext();
			gl3.loadDynamicLibrary();

			this.compileLinkShader();
			this.setupVertexObjects();

			this.reconfigure();
		}

		void redrawOpenGlScene() {
			glClearColor(
				_poc.config.renderer.background.r,
				_poc.config.renderer.background.g,
				_poc.config.renderer.background.b,
				_poc.config.renderer.background.a
			);
			glClear(GL_COLOR_BUFFER_BIT);

			glActiveTexture(GL_TEXTURE0);
			glBindTexture(GL_TEXTURE_2D, _texture);
			glTexSubImage2D(
				GL_TEXTURE_2D,
				0,
				0, 0,
				_poc.config.renderer.resolution.width, _poc.config.renderer.resolution.height,
				GL_RGBA, GL_UNSIGNED_BYTE,
				castTo!(void*)(_poc.framebuffer.data.ptr)
			);

			glUseProgram(_shader.shaderProgram);
			glBindVertexArray(_vao);
			glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, null);
		}
	}

	private {
		void compileLinkShader() {
			_shader = new OpenGlShader(
				OpenGlShader.Source(GL_VERTEX_SHADER, `
					#version 330 core
					layout (location = 0) in vec2 aPos;
					layout (location = 1) in vec2 aTexCoord;

					out vec2 TexCoord;

					void main() {
						gl_Position = vec4(aPos.x, aPos.y, 0.0, 1.0);
						TexCoord = aTexCoord;
					}
				`),
				OpenGlShader.Source(GL_FRAGMENT_SHADER, `
					#version 330 core
					out vec4 FragColor;

					in vec2 TexCoord;

					uniform sampler2D sampler;

					void main() {
						FragColor = texture(sampler, TexCoord);
					}
				`),
			);
		}

		void setupVertexObjects() {
			glGenVertexArrays(1, &_vao);
			glBindVertexArray(_vao);

			glGenBuffers(1, &_vbo);
			glGenBuffers(1, &_ebo);

			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _ebo);
			glBufferDataSlice(GL_ELEMENT_ARRAY_BUFFER, indices, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, _vbo);
			glBufferDataSlice(GL_ARRAY_BUFFER, vertices, GL_STATIC_DRAW);

			glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * GLfloat.sizeof, null);
			glEnableVertexAttribArray(0);

			glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * GLfloat.sizeof, castTo!(void*)(2 * GLfloat.sizeof));
			glEnableVertexAttribArray(1);
		}

		void setupTexture() {
			if (_texture == 0) {
				glGenTextures(1, &_texture);
			}

			glBindTexture(GL_TEXTURE_2D, _texture);

			final switch (_poc.config.renderer.filter) with (ScalingFilter) {
			case nearest:
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
				break;
			case bilinear:
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
				break;
			}

			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
			glTexImage2D(
				GL_TEXTURE_2D,
				0,
				GL_RGBA8,
				_poc.config.renderer.resolution.width, _poc.config.renderer.resolution.height,
				0,
				GL_RGBA, GL_UNSIGNED_BYTE,
				null
			);

			glBindTexture(GL_TEXTURE_2D, 0);
		}
	}

	public void reconfigure() {
		const Viewport viewport = calculateViewport(_poc.config);
		glViewportPMP(viewport);

		this.setupTexture();
	}

	void redrawSchedule() {
		_poc.window.redrawOpenGlSceneSoon();
	}

	void redrawNow() {
		_poc.window.redrawOpenGlSceneNow();
	}

	private {
		static immutable GLfloat[] vertices = [
			//dfmt off
			// positions     // texture coordinates
			 1.0f,  1.0f,    1.0f, 0.0f,
			 1.0f, -1.0f,    1.0f, 1.0f,
			-1.0f, -1.0f,    0.0f, 1.0f,
			-1.0f,  1.0f,    0.0f, 0.0f,
			//dfmt on
		];

		static immutable GLuint[] indices = [
			//dfmt off
			0, 1, 3,
			1, 2, 3,
			//dfmt on
		];
	}
}

/++
	Legacy OpenGL (1.x) renderer implementation

	Uses what is often called the $(I Fixed Function Pipeline).
 +/
final class OpenGl1PixmapRenderer : PixmapRenderer {

	private {
		PresenterObjectsContainer* _poc;
		GLuint _texture = 0;
	}

	public @safe pure nothrow @nogc {
		///
		this() {
		}

		WantsOpenGl wantsOpenGl() pure nothrow @nogc @safe {
			return WantsOpenGl(1, 1, true);
		}

	}

	public void setup(PresenterObjectsContainer* poc) {
		_poc = poc;
		_poc.window.suppressAutoOpenglViewport = true;
		_poc.window.visibleForTheFirstTime = &this.visibleForTheFirstTime;
		_poc.window.redrawOpenGlScene = &this.redrawOpenGlScene;
	}

	private {

		void visibleForTheFirstTime() {
			//_poc.window.setAsCurrentOpenGlContext();
			// ↑-- reconfigure() does this, too.
			// |-- Uncomment if this functions does something else in the future.

			this.reconfigure();
		}

		void setupTexture() {
			if (_texture == 0) {
				glGenTextures(1, &_texture);
			}

			glBindTexture(GL_TEXTURE_2D, _texture);

			final switch (_poc.config.renderer.filter) with (ScalingFilter) {
			case nearest:
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
				break;
			case bilinear:
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
				break;
			}

			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
			glTexImage2D(
				GL_TEXTURE_2D,
				0,
				GL_RGBA8,
				_poc.config.renderer.resolution.width,
				_poc.config.renderer.resolution.height,
				0,
				GL_RGBA, GL_UNSIGNED_BYTE,
				null
			);

			glBindTexture(GL_TEXTURE_2D, 0);
		}

		void setupMatrix() {
			glMatrixMode(GL_PROJECTION);
			glLoadIdentity();
			glOrtho(
				0, _poc.config.renderer.resolution.width,
				_poc.config.renderer.resolution.height, 0,
				-1, 1
			);
			//glMatrixMode(GL_MODELVIEW);
		}

		void redrawOpenGlScene() {
			glClearColor(
				_poc.config.renderer.background.r,
				_poc.config.renderer.background.g,
				_poc.config.renderer.background.b,
				_poc.config.renderer.background.a,
			);
			glClear(GL_COLOR_BUFFER_BIT);

			glBindTexture(GL_TEXTURE_2D, _texture);
			glEnable(GL_TEXTURE_2D);
			{
				glTexSubImage2D(
					GL_TEXTURE_2D,
					0,
					0, 0,
					_poc.config.renderer.resolution.width, _poc.config.renderer.resolution.height,
					GL_RGBA, GL_UNSIGNED_BYTE,
					castTo!(void*)(_poc.framebuffer.data.ptr)
				);

				glBegin(GL_QUADS);
				{
					glTexCoord2f(0, 0);
					glVertex2i(0, 0);

					glTexCoord2f(0, 1);
					glVertex2i(0, _poc.config.renderer.resolution.height);

					glTexCoord2f(1, 1);
					glVertex2i(_poc.config.renderer.resolution.width, _poc.config.renderer.resolution.height);

					glTexCoord2f(1, 0);
					glVertex2i(_poc.config.renderer.resolution.width, 0);
				}
				glEnd();
			}
			glDisable(GL_TEXTURE_2D);
			glBindTexture(GL_TEXTURE_2D, 0);
		}
	}

	public void reconfigure() {
		_poc.window.setAsCurrentOpenGlContext();

		const Viewport viewport = calculateViewport(_poc.config);
		glViewportPMP(viewport);

		this.setupTexture();
		this.setupMatrix();
	}

	public void redrawSchedule() {
		_poc.window.redrawOpenGlSceneSoon();
	}

	public void redrawNow() {
		_poc.window.redrawOpenGlSceneNow();
	}
}

/+
/++
	Purely software renderer
 +/
final class SoftwarePixmapRenderer : PixmapRenderer {

	private {
		PresenterObjectsContainer* _poc;
	}

	public WantsOpenGl wantsOpenGl() @safe pure nothrow @nogc {
		return WantsOpenGl(0);
	}

	public void setup(PresenterObjectsContainer* container) {
	}

	public void reconfigure() {
	}

	/++
		Schedules a redraw
	 +/
	public void redrawSchedule() {
	}

	/++
		Triggers a redraw
	 +/
	public void redrawNow() {
	}
}
+/

///
struct LoopCtrl {
	int interval; /// in milliseconds
	bool redraw; ///

	///
	@disable this();

@safe pure nothrow @nogc:

	private this(int interval, bool redraw) {
		this.interval = interval;
		this.redraw = redraw;
	}

	///
	static LoopCtrl waitFor(int intervalMS) {
		return LoopCtrl(intervalMS, false);
	}

	///
	static LoopCtrl redrawIn(int intervalMS) {
		return LoopCtrl(intervalMS, true);
	}
}

/++
	Pixmap Presenter window

	A high-level window class that displays fully-rendered frames in the form of [Pixmap|Pixmaps].
	The pixmap will be centered and (optionally) scaled.
 +/
final class PixmapPresenter {

	private {
		PresenterObjectsContainer* _poc;
		PixmapRenderer _renderer;

		static if (hasTimer) {
			Timer _timer;
		}

		WindowResizedCallback _onWindowResize;
	}

	// ctors
	public {

		///
		this(const PresenterConfig config, bool useOpenGl = true) {
			if (useOpenGl) {
				this(config, new OpenGl3PixmapRenderer());
			} else {
				assert(false, "Not implemented");
			}
		}

		///
		this(const PresenterConfig config, PixmapRenderer renderer) {
			_renderer = renderer;

			// create software framebuffer
			auto framebuffer = Pixmap.makeNew(config.renderer.resolution);

			// OpenGL?
			auto openGlOptions = OpenGlOptions.no;
			const openGl = _renderer.wantsOpenGl;
			if (openGl.wanted) {
				setOpenGLContextVersion(openGl.vMaj, openGl.vMin);
				openGLContextCompatible = openGl.compat;

				openGlOptions = OpenGlOptions.yes;
			}

			// spawn window
			auto window = new SimpleWindow(
				config.window.size,
				config.window.title,
				openGlOptions,
				Resizability.allowResizing,
			);

			window.windowResized = &this.windowResized;
			window.cornerStyle = config.window.corners;

			// alloc objects
			_poc = new PresenterObjectsContainer(
				framebuffer,
				window,
				config,
			);

			_renderer.setup(_poc);
		}
	}

	// additional convenience ctors
	public {

		///
		this(
			string title,
			const Size resolution,
			const Size initialWindowSize,
			Scaling scaling = Scaling.contain,
			ScalingFilter filter = ScalingFilter.nearest,
		) {
			auto cfg = PresenterConfig();

			cfg.window.title = title;
			cfg.renderer.resolution = resolution;
			cfg.window.size = initialWindowSize;
			cfg.renderer.scaling = scaling;
			cfg.renderer.filter = filter;

			this(cfg);
		}

		///
		this(
			string title,
			const Size resolution,
			Scaling scaling = Scaling.contain,
			ScalingFilter filter = ScalingFilter.nearest,
		) {
			this(title, resolution, resolution, scaling, filter,);
		}
	}

	// public functions
	public {

		/++
			Runs the event loop (with a pulse timer)

			A redraw will be scheduled automatically each pulse.
		 +/
		int eventLoop(T...)(long pulseTimeout, void delegate() onPulse, T eventHandlers) {
			// run event-loop with pulse timer
			return _poc.window.eventLoop(
				pulseTimeout,
				delegate() { onPulse(); this.scheduleRedraw(); },
				eventHandlers,
			);
		}

		//dfmt off
		/++
			Runs the event loop

			Redraws have to manually scheduled through [scheduleRedraw] when using this overload.
		 +/
		int eventLoop(T...)(T eventHandlers) if (
			(T.length == 0) || (is(T[0] == delegate) && !is(typeof(() { return T[0](); }()) == LoopCtrl))
		) {
			return _poc.window.eventLoop(eventHandlers);
		}
		//dfmt on

		static if (hasTimer) {
			/++
				Runs the event loop
				with [LoopCtrl] timing mechanism
			 +/
			int eventLoop(T...)(LoopCtrl delegate() callback, T eventHandlers) {
				if (callback !is null) {
					LoopCtrl prev = LoopCtrl(1, true);

					_timer = new Timer(prev.interval, delegate() {
						// redraw if requested by previous ctrl message
						if (prev.redraw) {
							_renderer.redrawNow();
							prev.redraw = false; // done
						}

						// execute callback
						const LoopCtrl ctrl = callback();

						// different than previous ctrl message?
						if (ctrl.interval != prev.interval) {
							// update timer
							_timer.changeTime(ctrl.interval);
						}

						// save ctrl message
						prev = ctrl;
					});
				}

				// run event-loop
				return _poc.window.eventLoop(0, eventHandlers);
			}
		}

		/++
			The [Pixmap] to be presented.

			Use this to “draw” on screen.
		 +/
		Pixmap pixmap() @safe pure nothrow @nogc {
			return _poc.framebuffer;
		}

		/// ditto
		alias framebuffer = pixmap;

		/++
			Updates the configuration of the presenter.

			Params:
				resizeWindow = if false, `config.window.size` will be ignored.
		 +/
		void reconfigure(PresenterConfig config, const bool resizeWindow = false) {
			// override requested window-size to current size if no resize requested
			if (!resizeWindow) {
				config.window.size = _poc.config.window.size;
			}

			this.reconfigureImpl(config);
		}

		private void reconfigureImpl(const ref PresenterConfig config) {
			_poc.window.title = config.window.title;

			if (config.renderer.resolution != _poc.config.renderer.resolution) {
				_poc.framebuffer.size = config.renderer.resolution;
			}

			immutable resize = (config.window.size != _poc.config.window.size);

			// update stored configuration
			_poc.config = config;

			if (resize) {
				_poc.window.resize(config.window.size.width, config.window.size.height);
				// resize-handler will call `_renderer.reconfigure()`
			} else {
				_renderer.reconfigure();
			}
		}

		/++
			Schedules a redraw
		 +/
		void scheduleRedraw() {
			_renderer.redrawSchedule();
		}

		/++
			Fullscreen mode
		 +/
		bool isFullscreen() {
			return _poc.window.fullscreen;
		}

		/// ditto
		void isFullscreen(bool enabled) {
			_poc.window.fullscreen = enabled;
		}

		/++
			Toggles the fullscreen state of the window.

			Turns a non-fullscreen window into fullscreen mode.
			Exits fullscreen mode for fullscreen-windows.
		 +/
		void toggleFullscreen() {
			this.isFullscreen = !this.isFullscreen;
		}

		/++
			Returns the underlying [arsd.simpledisplay.SimpleWindow|SimpleWindow]

			$(WARNING
				This is unsupported; use at your own risk.

				Tinkering with the window directly can break all sort of things
				that a presenter or renderer could possibly have set up.
			)
		 +/
		SimpleWindow tinkerWindow() @safe pure nothrow @nogc {
			return _poc.window;
		}

		/++
			Returns the underlying [PixmapRenderer]

			$(TIP
				Type-cast the returned reference to the actual implementation type for further use.
			)

			$(WARNING
				This is quasi unsupported; use at your own risk.

				Using the result of this function is pratictically no different than
				using a reference to the renderer further on after passing it the presenter’s constructor.
				It can’t be prohibited but it resembles a footgun.
			)
		 +/
		PixmapRenderer tinkerRenderer() @safe pure nothrow @nogc {
			return _renderer;
		}
	}

	// event (handler) properties
	public @safe pure nothrow @nogc {

		/++
			Event handler: window resize
		 +/
		void onWindowResize(WindowResizedCallback value) {
			_onWindowResize = value;
		}
	}

	// event handlers
	private {
		void windowResized(int width, int height) {
			const newSize = Size(width, height);

			_poc.config.window.size = newSize;
			_renderer.reconfigure();
			// ↑ In case this call gets removed, update `reconfigure()`.
			//   Current implementation takes advantage of the `_renderer.reconfigure()` call here.

			if (_onWindowResize !is null) {
				_onWindowResize(newSize);
			}
		}
	}
}
