/+
	== pixelpresenter ==
	Copyright Elias Batek (0xEAB) 2023.
	Distributed under the Boost Software License, Version 1.0.
 +/
/++
	$(B Pixel Presenter) is a high-level display library for one specific scenario:
	Blitting fully-rendered frames to the screen.

	This is useful for software-rendered applications.
	Think of old-skool games, emulators etc.

	This library builds upon [arsd.simpledisplay] and [arsd.color].
	It wraps a [arsd.simpledisplay.SimpleWindow|SimpleWindow]) and displays the provided frame data.
	Each frame is automatically centered on, and optionally scaled to, the carrier window.
	This processing is done with hardware acceleration (OpenGL).
	Later versions might add a software-mode.

	Several $(B scaling) modes are supported.
	Most notably `keepAspectRatio` that scales frames to the while preserving the original aspect ratio.
	See [Scaling] for details.

	$(PITFALL
		This module is $(B work in progress).
		API is subject to changes until further notice.
	)
 +/
module arsd.pixelpresenter;

import arsd.color;
import arsd.simpledisplay;

/*
	## TODO

	- Complete documentation
	- Usage example(s)
	- Additional renderer implementations:
		- a `ScreenPainter`-based renderer
		- a legacy OpenGL renderer (maybe)
	- Is there something in arsd that serves a similar purpose to `PixelBuffer`?
	- Minimum window size
		- or something similar
		- to ensure `Scaling.integer` doesn’t break “unexpectedly”
	- Hybrid scaling mode: integer up, FP down
	- Fix timing
 */

///
alias Pixel = Color;

///
alias ColorF = arsd.color.ColorF;

///
alias Size = arsd.color.Size;

///
alias Point = arsd.color.Point;

// verify assumption(s)
static assert(Pixel.sizeof == uint.sizeof);

/// casts value `v` to type `T`
auto ref T typeCast(T, S)(auto ref S v) {
	return cast(T) v;
}

@safe pure nothrow @nogc {
	///
	Pixel rgba(ubyte r, ubyte g, ubyte b, ubyte a = 0xFF) {
		return Pixel(r, g, b, a);
	}

	///
	Pixel rgb(ubyte r, ubyte g, ubyte b) {
		return rgba(r, g, b, 0xFF);
	}
}

/++
	Pixel data container
 +/
struct PixelBuffer {

	/// Pixel data
	Pixel[] data;

	/// Pixel per row
	int width;

@safe pure nothrow:

	this(Size size) {
		this.size = size;
	}

	// undocumented: really shouldn’t be used.
	// carries the risks of `length` and `width` getting out of sync accidentally.
	deprecated("Use `size` instead.")
	void length(int value) {
		data.length = value;
	}

	/++
		Changes the size of the buffer

		Reallocates the underlying pixel array.
	 +/
	void size(Size value) {
		data.length = value.area;
		width = value.width;
	}

	/// ditto
	void size(int totalPixels, int width)
	in (length % width == 0) {
		data.length = totalPixels;
		this.width = width;
	}

@safe pure nothrow @nogc:

	/// Height of the buffer, i.e. the number of lines
	int height() inout {
		if (data.length == 0)
			return 0;
		return (cast(int) data.length / width);
	}

	/// Rectangular size of the buffer
	Size size() inout {
		return Size(width, height);
	}

	/// Length of the buffer, i.e. the number of pixels
	int length() inout {
		return cast(int) data.length;
	}

	/++
		Number of bytes per line

		Returns:
			width × Pixel.sizeof
	 +/
	int pitch() inout {
		return (width * int(Pixel.sizeof));
	}

	/// Clears the buffers contents (by setting each pixel to the same color)
	void clear(Pixel value) {
		data[] = value;
	}
}

@safe pure nothrow @nogc {

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
		return (cast(Point) delta) >> 1;
	}
}

/++
	Scaling/Fit Modes

	Each scaling modes has unique behavior for different window-size to frame-size ratios.

	Unfortunately, there are no universally applicable naming conventions for these modes.
	In fact, different implementations tend to contradict each other.

	$(SMALL_TABLE
		Mode feature matrix
		Mode        | Aspect Ratio | Pixel Ratio | Cropping | Border | Comment(s)
		`none`      | preserved    | preserved   | yes      | 4      |
		`stretch`	| no           | no          | no       | none   |
		`contain`   | preserved    | no          | no       | 4      | letterboxing/pillarboxing
		`integer`   | preserved    | preserved   | no       | 2      | works only if `window.size >= frame.size`
		`cover`     | preserved    | no          | yes      | none   |
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
	cover, ///

	// aliases
	center = none, ///
	keepAspectRatio = contain, ///

	// CSS `object-fit` style aliases
	cssNone = none, ///
	cssContain = contain, ///
	cssFill = stretch, ///
	cssCover = cover, ///
}

///
enum ScalingFilter {
	nearest, /// nearest neighbor → blocky/pixel’ish
	linear, /// (bi-)linear interpolation → smooth/blurry
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
			Filter
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
		string title = "ARSD Pixel Presenter";
		Size size;
	}
}

// undocumented
struct PresenterObjects {
	PixelBuffer framebuffer;
	SimpleWindow window;
	PresenterConfig config;
}

///
struct WantsOpenGl {
	bool wanted; /// Is OpenGL wanted?
	ubyte vMaj; /// major version
	ubyte vMin; /// minor version
}

///
interface PixelRenderer {
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

		Params:
			pro = Pointer to the [PresenterObjects] of the presenter. To be stored for later use.
	 +/
	public void setup(PresenterObjects* pro);

	/++
		Reconfigure renderer

		Called upon configuration changes.
		The new config can be found in the [PresenterObjects] received during `setup()`.
	 +/
	public void reconfigure();
}

///
final class OpenGL3PixelRenderer : PixelRenderer {

	private {
		PresenterObjects* _pro;

		bool _clear = true;

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
		return WantsOpenGl(true, 3, 0);
	}

	// TODO: make this ctor?
	public void setup(PresenterObjects* pro) {
		_pro = pro;
		_pro.window.visibleForTheFirstTime = &this.visibleForTheFirstTime;
		_pro.window.redrawOpenGlScene = &this.redrawOpenGlScene;
	}

	private {
		void visibleForTheFirstTime() {
			_pro.window.setAsCurrentOpenGlContext();
			gl3.loadDynamicLibrary();

			this.compileLinkShader();
			this.setupVertexObjects();

			this.reconfigure();
		}

		void redrawOpenGlScene() {
			if (_clear) {
				glClearColor(
					_pro.config.renderer.background.r,
					_pro.config.renderer.background.g,
					_pro.config.renderer.background.b,
					_pro.config.renderer.background.a
				);
				glClear(GL_COLOR_BUFFER_BIT);
				_clear = false;
			}

			glActiveTexture(GL_TEXTURE0);
			glBindTexture(GL_TEXTURE_2D, _texture);
			glTexSubImage2D(
				GL_TEXTURE_2D,
				0,
				0, 0,
				_pro.config.renderer.resolution.width, _pro.config.renderer.resolution.height,
				GL_RGBA, GL_UNSIGNED_BYTE,
				cast(void*) _pro.framebuffer.data.ptr
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

			glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * GLfloat.sizeof, cast(void*)(2 * GLfloat.sizeof));
			glEnableVertexAttribArray(1);
		}

		void setupTexture() {
			if (_texture == 0) {
				glGenTextures(1, &_texture);
			}

			glBindTexture(GL_TEXTURE_2D, _texture);

			final switch (_pro.config.renderer.filter) with (ScalingFilter) {
			case nearest:
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
				break;
			case linear:
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
				_pro.config.renderer.resolution.width, _pro.config.renderer.resolution.height,
				0,
				GL_RGBA, GL_UNSIGNED_BYTE,
				null
			);

			glBindTexture(GL_TEXTURE_2D, 0);
		}
	}

	public void reconfigure() {
		Size viewport;

		final switch (_pro.config.renderer.scaling) {

		case Scaling.none:
			viewport = _pro.config.renderer.resolution;
			break;

		case Scaling.stretch:
			viewport = _pro.config.window.size;
			break;

		case Scaling.contain:
			const float scaleF = karContainScalingFactorF(_pro.config.renderer.resolution, _pro.config.window.size);
			viewport = Size(
				typeCast!int(scaleF * _pro.config.renderer.resolution.width),
				typeCast!int(scaleF * _pro.config.renderer.resolution.height),
			);
			break;

		case Scaling.integer:
			const int scaleI = karContainScalingFactorInt(_pro.config.renderer.resolution, _pro.config.window.size);
			viewport = (_pro.config.renderer.resolution * scaleI);
			break;

		case Scaling.cover:
			const float fillF = karCoverScalingFactorF(_pro.config.renderer.resolution, _pro.config.window.size);
			viewport = Size(
				typeCast!int(fillF * _pro.config.renderer.resolution.width),
				typeCast!int(fillF * _pro.config.renderer.resolution.height),
			);
			break;
		}

		const Point viewportPos = offsetCenter(viewport, _pro.config.window.size);
		glViewport(viewportPos.x, viewportPos.y, viewport.width, viewport.height);
		this.setupTexture();
		_clear = true;
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
 +/
final class PixelPresenter {

	private {
		PresenterObjects* _pro;
		PixelRenderer _renderer;
	}

	// ctors
	public {

		///
		this(const PresenterConfig config, bool useOpenGl = true) {
			if (useOpenGl) {
				this(config, new OpenGL3PixelRenderer());
			} else {
				assert(false, "Not implemented");
			}
		}

		///
		this(const PresenterConfig config, PixelRenderer renderer) {
			_renderer = renderer;

			// create software framebuffer
			auto framebuffer = PixelBuffer(config.renderer.resolution);

			// OpenGL?
			auto openGlOptions = OpenGlOptions.no;
			const openGl = _renderer.wantsOpenGl;
			if (openGl.wanted) {
				setOpenGLContextVersion(openGl.vMaj, openGl.vMin);
				openGLContextCompatible = false;

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

			// alloc objects
			_pro = new PresenterObjects(
				framebuffer,
				window,
				config,
			);

			_renderer.setup(_pro);
		}
	}

	// additional convience ctors
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

		///
		int eventLoop(T...)(T eventHandlers) if (T.length == 0 || is(T[0] == delegate)) {
			return _pro.window.eventLoop(
				16, // ~60 FPS
				delegate() { eventHandlers[0](); _pro.window.redrawOpenGlSceneSoon(); },
				eventHandlers[1 .. $],
			);
		}

		///
		PixelBuffer framebuffer() @safe pure nothrow @nogc {
			return _pro.framebuffer;
		}

		///
		void reconfigure(const PresenterConfig config) {
			assert(false, "Not implemented");
			//_framebuffer.size = config.internalResolution;
			//_renderer.reconfigure(config);
		}

		///
		bool isFullscreen() {
			return _pro.window.fullscreen;
		}

		/// ditto
		void isFullscreen(bool enabled) {
			return _pro.window.fullscreen = enabled;
		}

		/++
			Returns the underlying `SimpleWindow`

			$(WARNING
				This is unsupported; use at your own risk.

				Tinkering with the window directly can break all sort of things
				that a presenter or renderer could possibly have set up.
			)
		 +/
		SimpleWindow tinker() @safe pure nothrow @nogc {
			return _pro.window;
		}
	}

	// event handlers
	private {
		void windowResized(int width, int height) {
			_pro.config.window.size = Size(width, height);
			_renderer.reconfigure();
		}
	}
}
