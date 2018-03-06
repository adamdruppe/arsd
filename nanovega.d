//
// Copyright (c) 2013 Mikko Mononen memon@inside.org
//
// This software is provided 'as-is', without any express or implied
// warranty.  In no event will the authors be held liable for any damages
// arising from the use of this software.
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would be
//    appreciated but is not required.
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
// 3. This notice may not be removed or altered from any source distribution.
//
// Fork developement, feature integration and new bugs:
// Ketmar // Invisible Vector <ketmar@ketmar.no-ip.org>
// Contains code from various contributors.
/**
The NanoVega API is modeled loosely on HTML5 canvas API.
If you know canvas, you're up to speed with NanoVega in no time.

$(SIDE_BY_SIDE

	$(COLUMN

		D code with nanovega:

		---
		import arsd.simpledisplay;

		import arsd.nanovega;

		void main () {
		  NVGContext nvg; // our NanoVega context

		  // we need at least OpenGL3 with GLSL to use NanoVega,
		  // so let's tell simpledisplay about that
		  setOpenGLContextVersion(3, 0);

		  // now create OpenGL window
		  auto sdmain = new SimpleWindow(800, 600, "NanoVega Simple Sample", OpenGlOptions.yes, Resizability.allowResizing);

		  // we need to destroy NanoVega context on window close
		  // stricly speaking, it is not necessary, as nothing fatal
		  // will happen if you'll forget it, but let's be polite.
		  // note that we cannot do that *after* our window was closed,
		  // as we need alive OpenGL context to do proper cleanup.
		  sdmain.onClosing = delegate () {
		    nvg.kill();
		  };

		  // this is called just before our window will be shown for the first time.
		  // we must create NanoVega context here, as it needs to initialize
		  // internal OpenGL subsystem with valid OpenGL context.
		  sdmain.visibleForTheFirstTime = delegate () {
		    // yes, that's all
		    nvg = nvgCreateContext();
		    if (nvg is null) assert(0, "cannot initialize NanoVega");
		  };

		  // this callback will be called when we will need to repaint our window
		  sdmain.redrawOpenGlScene = delegate () {
		    // fix viewport (we can do this in resize event, or here, it doesn't matter)
		    glViewport(0, 0, sdmain.width, sdmain.height);

		    // clear window
		    glClearColor(0, 0, 0, 0);
		    glClear(glNVGClearFlags); // use NanoVega API to get flags for OpenGL call

		    {
		      nvg.beginFrame(sdmain.width, sdmain.height); // begin rendering
		      scope(exit) nvg.endFrame(); // and flush render queue on exit

		      nvg.beginPath(); // start new path
		      nvg.roundedRect(20.5, 30.5, sdmain.width-40, sdmain.height-60, 8); // .5 to draw at pixel center (see NanoVega documentation)
		      // now set filling mode for our rectangle
		      // you can create colors using HTML syntax, or with convenient constants
		      nvg.fillPaint = nvg.linearGradient(20.5, 30.5, sdmain.width-40, sdmain.height-60, NVGColor("#f70"), NVGColor.green);
		      // now fill our rect
		      nvg.fill();
		      // and draw a nice outline
		      nvg.strokeColor = NVGColor.white;
		      nvg.strokeWidth = 2;
		      nvg.stroke();
		      // that's all, folks!
		    }
		  };

		  sdmain.eventLoop(0, // no pulse timer required
		    delegate (KeyEvent event) {
		      if (event == "*-Q" || event == "Escape") { sdmain.close(); return; } // quit on Q, Ctrl+Q, and so on
		    },
		  );

		  flushGui(); // let OS do it's cleanup
		}
		---
	)

	$(COLUMN
		Javascript code with HTML5 Canvas

		```html
		<!DOCTYPE html>
		<html>
		<head>
			<title>NanoVega Simple Sample (HTML5 Translation)</title>
			<style>
				body { background-color: black; }
			</style>
		</head>
		<body>
			<canvas id="my-canvas" width="800" height="600"></canvas>
		<script>
			var canvas = document.getElementById("my-canvas");
			var context = canvas.getContext("2d");

			context.beginPath();

			context.rect(20.5, 30.5, canvas.width - 40, canvas.height - 60);

			var gradient = context.createLinearGradient(20.5, 30.5, canvas.width - 40, canvas.height - 60);
			gradient.addColorStop(0, "#f70");
			gradient.addColorStop(1, "green");

			context.fillStyle = gradient;
			context.fill();
			context.closePath();
			context.strokeStyle = "white";
			context.lineWidth = 2;
			context.stroke();
		</script>
		</body>
		</html>
		```
	)
)


Creating drawing context
========================

The drawing context is created using platform specific constructor function.

  ---
  NVGContext vg = nvgCreateContext();
  ---


Drawing shapes with NanoVega
============================

Drawing a simple shape using NanoVega consists of four steps:
$(LIST
  * begin a new shape,
  * define the path to draw,
  * set fill or stroke,
  * and finally fill or stroke the path.
)

  ---
  vg.beginPath();
  vg.rect(100, 100, 120, 30);
  vg.fillColor(nvgRGBA(255, 192, 0, 255));
  vg.fill();
  ---

Calling [beginPath] will clear any existing paths and start drawing from blank slate.
There are number of number of functions to define the path to draw, such as rectangle,
rounded rectangle and ellipse, or you can use the common moveTo, lineTo, bezierTo and
arcTo API to compose the paths step by step.


Understanding Composite Paths
=============================

Because of the way the rendering backend is built in NanoVega, drawing a composite path,
that is path consisting from multiple paths defining holes and fills, is a bit more
involved. NanoVega uses non-zero filling rule and by default, and paths are wound in counter
clockwise order. Keep that in mind when drawing using the low level draw API. In order to
wind one of the predefined shapes as a hole, you should call `pathWinding(NVGSolidity.Hole)`,
or `pathWinding(NVGSolidity.Solid)` $(B after) defining the path.

  ---
  vg.beginPath();
  vg.rect(100, 100, 120, 30);
  vg.circle(120, 120, 5);
  vg.pathWinding(NVGSolidity.Hole); // mark circle as a hole
  vg.fillColor(nvgRGBA(255, 192, 0, 255));
  vg.fill();
  ---


Rendering is wrong, what to do?
===============================

$(LIST
  * make sure you have created NanoVega context using [nvgCreateContext] call
  * make sure you have initialised OpenGL with $(B stencil buffer)
  * make sure you have cleared stencil buffer
  * make sure all rendering calls happen between [beginFrame] and [endFrame]
  * to enable more checks for OpenGL errors, add `NVGContextFlag.Debug` flag to [nvgCreateContext]
)


OpenGL state touched by the backend
===================================

The OpenGL back-end touches following states:

When textures are uploaded or updated, the following pixel store is set to defaults:
`GL_UNPACK_ALIGNMENT`, `GL_UNPACK_ROW_LENGTH`, `GL_UNPACK_SKIP_PIXELS`, `GL_UNPACK_SKIP_ROWS`.
Texture binding is also affected. Texture updates can happen when the user loads images,
or when new font glyphs are added. Glyphs are added as needed between calls to [beginFrame]
and [endFrame].

The data for the whole frame is buffered and flushed in [endFrame].
The following code illustrates the OpenGL state touched by the rendering code:

  ---
  glUseProgram(prog);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_CULL_FACE);
  glCullFace(GL_BACK);
  glFrontFace(GL_CCW);
  glEnable(GL_BLEND);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_COLOR_LOGIC_OP);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glStencilMask(0xffffffff);
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
  glStencilFunc(GL_ALWAYS, 0, 0xffffffff);
  glActiveTexture(GL_TEXTURE1);
  glActiveTexture(GL_TEXTURE0);
  glBindBuffer(GL_UNIFORM_BUFFER, buf);
  glBindVertexArray(arr);
  glBindBuffer(GL_ARRAY_BUFFER, buf);
  glBindTexture(GL_TEXTURE_2D, tex);
  glUniformBlockBinding(... , GLNVG_FRAG_BINDING);
  ---

  Symbol_groups:

  context_management =
    ## Context Management

    Functions to create and destory NanoVega context.

  frame_management =
    ## Frame Management

    To start drawing with NanoVega context, you have to "begin frame", and then
    "end frame" to flush your rendering commands to GPU.

  composite_operation =
    ## Composite Operation

    The composite operations in NanoVega are modeled after HTML Canvas API, and
    the blend func is based on OpenGL (see corresponding manuals for more info).
    The colors in the blending state have premultiplied alpha.

  color_utils =
    ## Color Utils

    Colors in NanoVega are stored as ARGB. Zero alpha means "transparent color".

  matrices =
    ## Matrices and Transformations

    The paths, gradients, patterns and scissor region are transformed by an transformation
    matrix at the time when they are passed to the API.
    The current transformation matrix is an affine matrix:

    ----------------------
      [sx kx tx]
      [ky sy ty]
      [ 0  0  1]
    ----------------------

    Where: (sx, sy) define scaling, (kx, ky) skewing, and (tx, ty) translation.
    The last row is assumed to be (0, 0, 1) and is not stored.

    Apart from [resetTransform], each transformation function first creates
    specific transformation matrix and pre-multiplies the current transformation by it.

    Current coordinate system (transformation) can be saved and restored using [save] and [restore].

    The following functions can be used to make calculations on 2x3 transformation matrices.
    A 2x3 matrix is represented as float[6].

  state_handling =
    ## State Handling

    NanoVega contains state which represents how paths will be rendered.
    The state contains transform, fill and stroke styles, text and font styles,
    and scissor clipping.

  render_styles =
    ## Render Styles

    Fill and stroke render style can be either a solid color or a paint which is a gradient or a pattern.
    Solid color is simply defined as a color value, different kinds of paints can be created
    using [linearGradient], [boxGradient], [radialGradient] and [imagePattern].

    Current render style can be saved and restored using [save] and [restore].

    Note that if you want "almost perfect" pixel rendering, you should set aspect ratio to 1,
    and use `integerCoord+0.5f` as pixel coordinates.

  render_transformations =
    ## Render Transformations

    Transformation matrix management for the current rendering style. Transformations are applied in
    backwards order. I.e. if you first translate, and then rotate, your path will be rotated around
    it's origin, and then translated to the destination point.

  scissoring =
    ## Scissoring

    Scissoring allows you to clip the rendering into a rectangle. This is useful for various
    user interface cases like rendering a text edit or a timeline.

  images =
    ## Images

    NanoVega allows you to load image files in various formats (if arsd loaders are in place) to be used for rendering.
    In addition you can upload your own image.
    The parameter imageFlagsList is a list of flags defined in [NVGImageFlag].

    If you will use your image as fill pattern, it will be scaled by default. To make it repeat, pass
    [NVGImageFlag.RepeatX] and [NVGImageFlag.RepeatY] flags to image creation function respectively.

  paints =
    ## Paints

    NanoVega supports four types of paints: linear gradient, box gradient, radial gradient and image pattern.
    These can be used as paints for strokes and fills.

  gpu_affine =
    ## Render-Time Affine Transformations

    It is possible to set affine transformation matrix for GPU. That matrix will
    be applied by the shader code. This can be used to quickly translate and rotate
    saved paths. Call this $(B only) between [beginFrame] and [endFrame].

    Note that [beginFrame] resets this matrix to identity one.

    $(WARNING Don't use this for scaling or skewing, or your image will be heavily distorted!)

  paths =
    ## Paths

    Drawing a new shape starts with [beginPath], it clears all the currently defined paths.
    Then you define one or more paths and sub-paths which describe the shape. The are functions
    to draw common shapes like rectangles and circles, and lower level step-by-step functions,
    which allow to define a path curve by curve.

    NanoVega uses even-odd fill rule to draw the shapes. Solid shapes should have counter clockwise
    winding and holes should have counter clockwise order. To specify winding of a path you can
    call [pathWinding]. This is useful especially for the common shapes, which are drawn CCW.

    Finally you can fill the path using current fill style by calling [fill], and stroke it
    with current stroke style by calling [stroke].

    The curve segments and sub-paths are transformed by the current transform.

  picking_api =
    ## Picking API

    This is picking API that works directly on paths, without rasterizing them first.

    [beginFrame] resets picking state. Then you can create paths as usual, but
    there is a possibility to perform hit checks $(B before) rasterizing a path.
    Call either id assigning functions ([currFillHitId]/[currStrokeHitId]), or
    immediate hit test functions ([hitTestCurrFill]/[hitTestCurrStroke])
    before rasterizing (i.e. calling [fill] or [stroke]) to perform hover
    effects, for example.

    Also note that picking API is ignoring GPU affine transformation matrix.
    You can "untransform" picking coordinates before checking with [gpuUntransformPoint].

    $(WARNING Picking API completely ignores clipping. If you want to check for
              clip regions, you have to manuall register them as fill/stroke paths,
              and perform the necessary logic. See [hitTestForId] function.)

  clipping =
    ## Cliping with paths

    If scissoring is not enough for you, you can clip rendering with arbitrary path,
    or with combination of paths. Clip region is saved by [save] and restored by
    [restore] NanoVega functions. You can combine clip paths with various logic
    operations, see [NVGClipMode].

    Note that both [clip] and [clipStroke] are ignoring scissoring (i.e. clip mask
    is created as if there was no scissor set). Actual rendering is affected by
    scissors, though.

  text_api =
    ## Text

    NanoVega allows you to load .ttf files and use the font to render text.
    You have to load some font, and set proper font size before doing anything
    with text, as there is no "default" font provided by NanoVega. Also, don't
    forget to check return value of `createFont()`, 'cause NanoVega won't fail
    if it cannot load font, it will silently try to render nothing.

    The appearance of the text can be defined by setting the current text style
    and by specifying the fill color. Common text and font settings such as
    font size, letter spacing and text align are supported. Font blur allows you
    to create simple text effects such as drop shadows.

    At render time the font face can be set based on the font handles or name.

    Font measure functions return values in local space, the calculations are
    carried in the same resolution as the final rendering. This is done because
    the text glyph positions are snapped to the nearest pixels sharp rendering.

    The local space means that values are not rotated or scale as per the current
    transformation. For example if you set font size to 12, which would mean that
    line height is 16, then regardless of the current scaling and rotation, the
    returned line height is always 16. Some measures may vary because of the scaling
    since aforementioned pixel snapping.

    While this may sound a little odd, the setup allows you to always render the
    same way regardless of scaling. I.e. following works regardless of scaling:

    ----------------------
       string txt = "Text me up.";
       vg.textBounds(x, y, txt, bounds);
       vg.beginPath();
       vg.roundedRect(bounds[0], bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1], 6);
       vg.fill();
    ----------------------

    Note: currently only solid color fill is supported for text.

  path_recording =
    ## Recording and Replaying Pathes

    $(WARNING This API is hightly experimental, and is subject to change.
              While I will try to keep it compatible in future NanoVega
              versions, no promises are made. Also note that NanoVega
              rendering is quite fast, so you prolly don't need this
              functionality. If you really want to render-once-and-copy,
              consider rendering to FBO, and use imaging API to blit
              FBO texture instead. Note that NanoVega supports alot of
              blit/copy modes.)

    It is posible to record render commands and replay them later. This will allow
    you to skip possible time-consuming tesselation stage. Potential uses of this
    feature is, for example, rendering alot of similar complex paths, like game
    tiles, or enemy sprites.

    Path replaying has some limitations, though: you cannot change stroke width,
    fringe size, tesselation tolerance, or rescale path. But you can change fill
    color/pattern, stroke color, translate and/or rotate saved paths.

    Note that text rendering commands are not saved, as technically text rendering
    is not a path.

    To translate or rotate a record, use [affineGPU] API call.

    To record render commands, you must create new path set with [newPathSet]
    function, then start recording with [startRecording]. You can cancel current
    recording with [cancelRecording], or commit (save) recording with [stopRecording].

    You can resume recording with [startRecording] after [stopRecording] call.
    Calling [cancelRecording] will cancel only current recording session (i.e. it
    will forget everything from the very latest [startRecording], not the whole
    record).

    Finishing frame with [endFrame] will automatically commit current recording, and
    calling [cancelFrame] will cancel recording by calling [cancelRecording].

    Note that commit recording will clear current picking scene (but cancelling won't).

    Calling [startRecording] without commiting or cancelling recoriding will commit.

    $(WARNING Text output is not recorded now. Neither is scissor, so if you are using
              scissoring or text in your paths (UI, for example), things will not
              work as you may expect.)
 */
module arsd.nanovega;
private:

version(aliced) {
  import iv.meta;
  import iv.vfs;
} else {
  private alias usize = size_t;
  // i fear phobos!
  private template Unqual(T) {
         static if (is(T U ==          immutable U)) alias Unqual = U;
    else static if (is(T U == shared inout const U)) alias Unqual = U;
    else static if (is(T U == shared inout       U)) alias Unqual = U;
    else static if (is(T U == shared       const U)) alias Unqual = U;
    else static if (is(T U == shared             U)) alias Unqual = U;
    else static if (is(T U ==        inout const U)) alias Unqual = U;
    else static if (is(T U ==        inout       U)) alias Unqual = U;
    else static if (is(T U ==              const U)) alias Unqual = U;
    else alias Unqual = T;
  }
  private template isAnyCharType(T, bool unqual=false) {
    static if (unqual) private alias UT = Unqual!T; else private alias UT = T;
    enum isAnyCharType = is(UT == char) || is(UT == wchar) || is(UT == dchar);
  }
  private template isWideCharType(T, bool unqual=false) {
    static if (unqual) private alias UT = Unqual!T; else private alias UT = T;
    enum isWideCharType = is(UT == wchar) || is(UT == dchar);
  }
}
version(nanovg_disable_vfs) {
  enum NanoVegaHasIVVFS = false;
} else {
  static if (is(typeof((){import iv.vfs;}))) {
    enum NanoVegaHasIVVFS = true;
    import iv.vfs;
  } else {
    enum NanoVegaHasIVVFS = false;
  }
}

// ////////////////////////////////////////////////////////////////////////// //
// engine
// ////////////////////////////////////////////////////////////////////////// //
import core.stdc.stdlib : malloc, realloc, free;
import core.stdc.string : memset, memcpy, strlen;
import std.math : PI;

version(Posix) {
  version = nanovg_use_freetype;
} else {
  version = nanovg_disable_fontconfig;
}
version(aliced) {
  version = nanovg_default_no_font_aa;
  version = nanovg_builtin_fontconfig_bindings;
  version = nanovg_builtin_freetype_bindings;
  version = nanovg_builtin_opengl_bindings; // use `arsd.simpledisplay` to get basic bindings
} else {
  version = nanovg_builtin_fontconfig_bindings;
  version = nanovg_builtin_freetype_bindings;
  version = nanovg_builtin_opengl_bindings; // use `arsd.simpledisplay` to get basic bindings
}

version(nanovg_disable_fontconfig) {
  public enum NanoVegaHasFontConfig = false;
} else {
  public enum NanoVegaHasFontConfig = true;
  version(nanovg_builtin_fontconfig_bindings) {} else import iv.fontconfig;
}

//version = nanovg_bench_flatten;

public:
alias NVG_PI = PI;

enum NanoVegaHasArsdColor = (is(typeof((){ import arsd.color; })));
enum NanoVegaHasArsdImage = (is(typeof((){ import arsd.color; import arsd.image; })));

static if (NanoVegaHasArsdColor) private import arsd.color;
static if (NanoVegaHasArsdImage) {
  private import arsd.image;
} else {
  void stbi_set_unpremultiply_on_load (int flag_true_if_should_unpremultiply) {}
  void stbi_convert_iphone_png_to_rgb (int flag_true_if_should_convert) {}
  ubyte* stbi_load (const(char)* filename, int* x, int* y, int* comp, int req_comp) { return null; }
  ubyte* stbi_load_from_memory (const(void)* buffer, int len, int* x, int* y, int* comp, int req_comp) { return null; }
  void stbi_image_free (void* retval_from_stbi_load) {}
}

version(nanovg_default_no_font_aa) {
  __gshared bool NVG_INVERT_FONT_AA = false;
} else {
  __gshared bool NVG_INVERT_FONT_AA = true;
}


/// this is branchless for ints on x86, and even for longs on x86_64
public ubyte nvgClampToByte(T) (T n) pure nothrow @safe @nogc if (__traits(isIntegral, T)) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  static if (T.sizeof == 2 || T.sizeof == 4) {
    static if (__traits(isUnsigned, T)) {
      return cast(ubyte)(n&0xff|(255-((-cast(int)(n < 256))>>24)));
    } else {
      n &= -cast(int)(n >= 0);
      return cast(ubyte)(n|((255-cast(int)n)>>31));
    }
  } else static if (T.sizeof == 1) {
    static assert(__traits(isUnsigned, T), "clampToByte: signed byte? no, really?");
    return cast(ubyte)n;
  } else static if (T.sizeof == 8) {
    static if (__traits(isUnsigned, T)) {
      return cast(ubyte)(n&0xff|(255-((-cast(long)(n < 256))>>56)));
    } else {
      n &= -cast(long)(n >= 0);
      return cast(ubyte)(n|((255-cast(long)n)>>63));
    }
  } else {
    static assert(false, "clampToByte: integer too big");
  }
}


/// NanoVega RGBA color
/// Group: color_utils
public align(1) struct NVGColor {
align(1):
public:
  float[4] rgba = 0; /// default color is transparent (a=1 is opaque)

public:
  @property string toString () const @safe { import std.string : format; return "NVGColor(%s,%s,%s,%s)".format(r, g, b, a); }

public:
  enum transparent = NVGColor(0.0f, 0.0f, 0.0f, 0.0f);
  enum k8orange = NVGColor(1.0f, 0.5f, 0.0f, 1.0f);

  enum aliceblue = NVGColor(240, 248, 255);
  enum antiquewhite = NVGColor(250, 235, 215);
  enum aqua = NVGColor(0, 255, 255);
  enum aquamarine = NVGColor(127, 255, 212);
  enum azure = NVGColor(240, 255, 255);
  enum beige = NVGColor(245, 245, 220);
  enum bisque = NVGColor(255, 228, 196);
  enum black = NVGColor(0, 0, 0); // basic color
  enum blanchedalmond = NVGColor(255, 235, 205);
  enum blue = NVGColor(0, 0, 255); // basic color
  enum blueviolet = NVGColor(138, 43, 226);
  enum brown = NVGColor(165, 42, 42);
  enum burlywood = NVGColor(222, 184, 135);
  enum cadetblue = NVGColor(95, 158, 160);
  enum chartreuse = NVGColor(127, 255, 0);
  enum chocolate = NVGColor(210, 105, 30);
  enum coral = NVGColor(255, 127, 80);
  enum cornflowerblue = NVGColor(100, 149, 237);
  enum cornsilk = NVGColor(255, 248, 220);
  enum crimson = NVGColor(220, 20, 60);
  enum cyan = NVGColor(0, 255, 255); // basic color
  enum darkblue = NVGColor(0, 0, 139);
  enum darkcyan = NVGColor(0, 139, 139);
  enum darkgoldenrod = NVGColor(184, 134, 11);
  enum darkgray = NVGColor(169, 169, 169);
  enum darkgreen = NVGColor(0, 100, 0);
  enum darkgrey = NVGColor(169, 169, 169);
  enum darkkhaki = NVGColor(189, 183, 107);
  enum darkmagenta = NVGColor(139, 0, 139);
  enum darkolivegreen = NVGColor(85, 107, 47);
  enum darkorange = NVGColor(255, 140, 0);
  enum darkorchid = NVGColor(153, 50, 204);
  enum darkred = NVGColor(139, 0, 0);
  enum darksalmon = NVGColor(233, 150, 122);
  enum darkseagreen = NVGColor(143, 188, 143);
  enum darkslateblue = NVGColor(72, 61, 139);
  enum darkslategray = NVGColor(47, 79, 79);
  enum darkslategrey = NVGColor(47, 79, 79);
  enum darkturquoise = NVGColor(0, 206, 209);
  enum darkviolet = NVGColor(148, 0, 211);
  enum deeppink = NVGColor(255, 20, 147);
  enum deepskyblue = NVGColor(0, 191, 255);
  enum dimgray = NVGColor(105, 105, 105);
  enum dimgrey = NVGColor(105, 105, 105);
  enum dodgerblue = NVGColor(30, 144, 255);
  enum firebrick = NVGColor(178, 34, 34);
  enum floralwhite = NVGColor(255, 250, 240);
  enum forestgreen = NVGColor(34, 139, 34);
  enum fuchsia = NVGColor(255, 0, 255);
  enum gainsboro = NVGColor(220, 220, 220);
  enum ghostwhite = NVGColor(248, 248, 255);
  enum gold = NVGColor(255, 215, 0);
  enum goldenrod = NVGColor(218, 165, 32);
  enum gray = NVGColor(128, 128, 128); // basic color
  enum green = NVGColor(0, 128, 0); // basic color
  enum greenyellow = NVGColor(173, 255, 47);
  enum grey = NVGColor(128, 128, 128); // basic color
  enum honeydew = NVGColor(240, 255, 240);
  enum hotpink = NVGColor(255, 105, 180);
  enum indianred = NVGColor(205, 92, 92);
  enum indigo = NVGColor(75, 0, 130);
  enum ivory = NVGColor(255, 255, 240);
  enum khaki = NVGColor(240, 230, 140);
  enum lavender = NVGColor(230, 230, 250);
  enum lavenderblush = NVGColor(255, 240, 245);
  enum lawngreen = NVGColor(124, 252, 0);
  enum lemonchiffon = NVGColor(255, 250, 205);
  enum lightblue = NVGColor(173, 216, 230);
  enum lightcoral = NVGColor(240, 128, 128);
  enum lightcyan = NVGColor(224, 255, 255);
  enum lightgoldenrodyellow = NVGColor(250, 250, 210);
  enum lightgray = NVGColor(211, 211, 211);
  enum lightgreen = NVGColor(144, 238, 144);
  enum lightgrey = NVGColor(211, 211, 211);
  enum lightpink = NVGColor(255, 182, 193);
  enum lightsalmon = NVGColor(255, 160, 122);
  enum lightseagreen = NVGColor(32, 178, 170);
  enum lightskyblue = NVGColor(135, 206, 250);
  enum lightslategray = NVGColor(119, 136, 153);
  enum lightslategrey = NVGColor(119, 136, 153);
  enum lightsteelblue = NVGColor(176, 196, 222);
  enum lightyellow = NVGColor(255, 255, 224);
  enum lime = NVGColor(0, 255, 0);
  enum limegreen = NVGColor(50, 205, 50);
  enum linen = NVGColor(250, 240, 230);
  enum magenta = NVGColor(255, 0, 255); // basic color
  enum maroon = NVGColor(128, 0, 0);
  enum mediumaquamarine = NVGColor(102, 205, 170);
  enum mediumblue = NVGColor(0, 0, 205);
  enum mediumorchid = NVGColor(186, 85, 211);
  enum mediumpurple = NVGColor(147, 112, 219);
  enum mediumseagreen = NVGColor(60, 179, 113);
  enum mediumslateblue = NVGColor(123, 104, 238);
  enum mediumspringgreen = NVGColor(0, 250, 154);
  enum mediumturquoise = NVGColor(72, 209, 204);
  enum mediumvioletred = NVGColor(199, 21, 133);
  enum midnightblue = NVGColor(25, 25, 112);
  enum mintcream = NVGColor(245, 255, 250);
  enum mistyrose = NVGColor(255, 228, 225);
  enum moccasin = NVGColor(255, 228, 181);
  enum navajowhite = NVGColor(255, 222, 173);
  enum navy = NVGColor(0, 0, 128);
  enum oldlace = NVGColor(253, 245, 230);
  enum olive = NVGColor(128, 128, 0);
  enum olivedrab = NVGColor(107, 142, 35);
  enum orange = NVGColor(255, 165, 0);
  enum orangered = NVGColor(255, 69, 0);
  enum orchid = NVGColor(218, 112, 214);
  enum palegoldenrod = NVGColor(238, 232, 170);
  enum palegreen = NVGColor(152, 251, 152);
  enum paleturquoise = NVGColor(175, 238, 238);
  enum palevioletred = NVGColor(219, 112, 147);
  enum papayawhip = NVGColor(255, 239, 213);
  enum peachpuff = NVGColor(255, 218, 185);
  enum peru = NVGColor(205, 133, 63);
  enum pink = NVGColor(255, 192, 203);
  enum plum = NVGColor(221, 160, 221);
  enum powderblue = NVGColor(176, 224, 230);
  enum purple = NVGColor(128, 0, 128);
  enum red = NVGColor(255, 0, 0); // basic color
  enum rosybrown = NVGColor(188, 143, 143);
  enum royalblue = NVGColor(65, 105, 225);
  enum saddlebrown = NVGColor(139, 69, 19);
  enum salmon = NVGColor(250, 128, 114);
  enum sandybrown = NVGColor(244, 164, 96);
  enum seagreen = NVGColor(46, 139, 87);
  enum seashell = NVGColor(255, 245, 238);
  enum sienna = NVGColor(160, 82, 45);
  enum silver = NVGColor(192, 192, 192);
  enum skyblue = NVGColor(135, 206, 235);
  enum slateblue = NVGColor(106, 90, 205);
  enum slategray = NVGColor(112, 128, 144);
  enum slategrey = NVGColor(112, 128, 144);
  enum snow = NVGColor(255, 250, 250);
  enum springgreen = NVGColor(0, 255, 127);
  enum steelblue = NVGColor(70, 130, 180);
  enum tan = NVGColor(210, 180, 140);
  enum teal = NVGColor(0, 128, 128);
  enum thistle = NVGColor(216, 191, 216);
  enum tomato = NVGColor(255, 99, 71);
  enum turquoise = NVGColor(64, 224, 208);
  enum violet = NVGColor(238, 130, 238);
  enum wheat = NVGColor(245, 222, 179);
  enum white = NVGColor(255, 255, 255); // basic color
  enum whitesmoke = NVGColor(245, 245, 245);
  enum yellow = NVGColor(255, 255, 0); // basic color
  enum yellowgreen = NVGColor(154, 205, 50);

nothrow @safe @nogc:
public:
  ///
  this (ubyte ar, ubyte ag, ubyte ab, ubyte aa=255) pure {
    pragma(inline, true);
    r = ar/255.0f;
    g = ag/255.0f;
    b = ab/255.0f;
    a = aa/255.0f;
  }

  ///
  this (float ar, float ag, float ab, float aa=1.0f) pure {
    pragma(inline, true);
    r = ar;
    g = ag;
    b = ab;
    a = aa;
  }

  /// AABBGGRR (same format as little-endian RGBA image, coincidentally, the same as arsd.color)
  this (uint c) pure {
    pragma(inline, true);
    r = (c&0xff)/255.0f;
    g = ((c>>8)&0xff)/255.0f;
    b = ((c>>16)&0xff)/255.0f;
    a = ((c>>24)&0xff)/255.0f;
  }

  /// Supports: "#rgb", "#rrggbb", "#argb", "#aarrggbb"
  this (const(char)[] srgb) {
    static int c2d (char ch) pure nothrow @safe @nogc {
      pragma(inline, true);
      return
        ch >= '0' && ch <= '9' ? ch-'0' :
        ch >= 'A' && ch <= 'F' ? ch-'A'+10 :
        ch >= 'a' && ch <= 'f' ? ch-'a'+10 :
        -1;
    }
    int[8] digs;
    int dc = -1;
    foreach (immutable char ch; srgb) {
      if (ch <= ' ') continue;
      if (ch == '#') {
        if (dc != -1) { dc = -1; break; }
        dc = 0;
      } else {
        if (dc >= digs.length) { dc = -1; break; }
        if ((digs[dc++] = c2d(ch)) < 0) { dc = -1; break; }
      }
    }
    switch (dc) {
      case 3: // rgb
        a = 1.0f;
        r = digs[0]/15.0f;
        g = digs[1]/15.0f;
        b = digs[2]/15.0f;
        break;
      case 4: // argb
        a = digs[0]/15.0f;
        r = digs[1]/15.0f;
        g = digs[2]/15.0f;
        b = digs[3]/15.0f;
        break;
      case 6: // rrggbb
        a = 1.0f;
        r = (digs[0]*16+digs[1])/255.0f;
        g = (digs[2]*16+digs[3])/255.0f;
        b = (digs[4]*16+digs[5])/255.0f;
        break;
      case 8: // aarrggbb
        a = (digs[0]*16+digs[1])/255.0f;
        r = (digs[2]*16+digs[3])/255.0f;
        g = (digs[4]*16+digs[5])/255.0f;
        b = (digs[6]*16+digs[7])/255.0f;
        break;
      default:
        break;
    }
  }

  /// Is this color completely opaque?
  @property bool isOpaque () const pure nothrow @trusted @nogc { pragma(inline, true); return (rgba.ptr[3] >= 1.0f); }
  /// Is this color completely transparent?
  @property bool isTransparent () const pure nothrow @trusted @nogc { pragma(inline, true); return (rgba.ptr[3] <= 0.0f); }

  /// AABBGGRR (same format as little-endian RGBA image, coincidentally, the same as arsd.color)
  @property uint asUint () const pure {
    pragma(inline, true);
    return
      cast(uint)(r*255)|
      (cast(uint)(g*255)<<8)|
      (cast(uint)(b*255)<<16)|
      (cast(uint)(a*255)<<24);
  }

  alias asUintABGR = asUint; /// Ditto.

  /// AABBGGRR (same format as little-endian RGBA image, coincidentally, the same as arsd.color)
  static NVGColor fromUint (uint c) pure { pragma(inline, true); return NVGColor(c); }

  alias fromUintABGR = fromUint; /// Ditto.

  /// AARRGGBB
  @property uint asUintARGB () const pure {
    pragma(inline, true);
    return
      cast(uint)(b*255)|
      (cast(uint)(g*255)<<8)|
      (cast(uint)(r*255)<<16)|
      (cast(uint)(a*255)<<24);
  }

  /// AARRGGBB
  static NVGColor fromUintARGB (uint c) pure { pragma(inline, true); return NVGColor((c>>16)&0xff, (c>>8)&0xff, c&0xff, (c>>24)&0xff); }

  @property ref inout(float) r () inout pure @trusted { pragma(inline, true); return rgba.ptr[0]; } ///
  @property ref inout(float) g () inout pure @trusted { pragma(inline, true); return rgba.ptr[1]; } ///
  @property ref inout(float) b () inout pure @trusted { pragma(inline, true); return rgba.ptr[2]; } ///
  @property ref inout(float) a () inout pure @trusted { pragma(inline, true); return rgba.ptr[3]; } ///

  ref NVGColor applyTint() (in auto ref NVGColor tint) nothrow @trusted @nogc {
    if (tint.a == 0) return this;
    foreach (immutable idx, ref float v; rgba[0..4]) {
      v = nvg__clamp(v*tint.rgba.ptr[idx], 0.0f, 1.0f);
    }
    return this;
  }

  NVGHSL asHSL() (bool useWeightedLightness=false) const { pragma(inline, true); return NVGHSL.fromColor(this, useWeightedLightness); } ///
  static fromHSL() (in auto ref NVGHSL hsl) { pragma(inline, true); return hsl.asColor; } ///

  static if (NanoVegaHasArsdColor) {
    Color toArsd () const { pragma(inline, true); return Color(cast(int)(r*255), cast(int)(g*255), cast(int)(b*255), cast(int)(a*255)); } ///
    static NVGColor fromArsd (in Color c) { pragma(inline, true); return NVGColor(c.r, c.g, c.b, c.a); } ///
    ///
    this (in Color c) {
      version(aliced) pragma(inline, true);
      r = c.r/255.0f;
      g = c.g/255.0f;
      b = c.b/255.0f;
      a = c.a/255.0f;
    }
  }
}


/// NanoVega A-HSL color
/// Group: color_utils
public align(1) struct NVGHSL {
align(1):
  float h=0, s=0, l=1, a=1; ///

  string toString () const { import std.format : format; return (a != 1 ? "HSL(%s,%s,%s,%d)".format(h, s, l, a) : "HSL(%s,%s,%s)".format(h, s, l)); }

nothrow @safe @nogc:
public:
  ///
  this (float ah, float as, float al, float aa=1) pure { pragma(inline, true); h = ah; s = as; l = al; a = aa; }

  NVGColor asColor () const { pragma(inline, true); return nvgHSLA(h, s, l, a); } ///

  // taken from Adam's arsd.color
  /** Converts an RGB color into an HSL triplet.
   * [useWeightedLightness] will try to get a better value for luminosity for the human eye,
   * which is more sensitive to green than red and more to red than blue.
   * If it is false, it just does average of the rgb. */
  static NVGHSL fromColor() (in auto ref NVGColor c, bool useWeightedLightness=false) pure {
    NVGHSL res;
    res.a = c.a;
    float r1 = c.r;
    float g1 = c.g;
    float b1 = c.b;

    float maxColor = r1;
    if (g1 > maxColor) maxColor = g1;
    if (b1 > maxColor) maxColor = b1;
    float minColor = r1;
    if (g1 < minColor) minColor = g1;
    if (b1 < minColor) minColor = b1;

    res.l = (maxColor+minColor)/2;
    if (useWeightedLightness) {
      // the colors don't affect the eye equally
      // this is a little more accurate than plain HSL numbers
      res.l = 0.2126*r1+0.7152*g1+0.0722*b1;
    }
    if (maxColor != minColor) {
      if (res.l < 0.5) {
        res.s = (maxColor-minColor)/(maxColor+minColor);
      } else {
        res.s = (maxColor-minColor)/(2.0-maxColor-minColor);
      }
      if (r1 == maxColor) {
        res.h = (g1-b1)/(maxColor-minColor);
      } else if(g1 == maxColor) {
        res.h = 2.0+(b1-r1)/(maxColor-minColor);
      } else {
        res.h = 4.0+(r1-g1)/(maxColor-minColor);
      }
    }

    res.h = res.h*60;
    if (res.h < 0) res.h += 360;
    res.h /= 360;

    return res;
  }
}


//version = nanovega_debug_image_manager;
//version = nanovega_debug_image_manager_rc;

/** NanoVega image handle.
 *
 * This is refcounted struct, so you don't need to do anything special to free it once it is allocated.
 *
 * Group: images
 */
struct NVGImage {
private:
  NVGContext ctx;
  int id; // backend image id

public:
  ///
  this() (in auto ref NVGImage src) nothrow @trusted @nogc {
    version(nanovega_debug_image_manager_rc) { import core.stdc.stdio; printf("NVGImage %p created from %p (imgid=%d)\n", &this, src, src.id); }
    ctx = cast(NVGContext)src.ctx;
    id = src.id;
    if (ctx !is null) ctx.nvg__imageIncRef(id);
  }

  ///
  ~this () nothrow @trusted @nogc { version(aliced) pragma(inline, true); clear(); }

  ///
  this (this) nothrow @trusted @nogc {
    if (ctx !is null) {
      version(nanovega_debug_image_manager_rc) { import core.stdc.stdio; printf("NVGImage %p postblit (imgid=%d)\n", &this, id); }
      ctx.nvg__imageIncRef(id);
    }
  }

  ///
  void opAssign() (in auto ref NVGImage src) nothrow @trusted @nogc {
    version(nanovega_debug_image_manager_rc) { import core.stdc.stdio; printf("NVGImage %p (imgid=%d) assigned from %p (imgid=%d)\n", &this, id, &src, src.id); }
    if (src.ctx !is null) (cast(NVGContext)src.ctx).nvg__imageIncRef(src.id);
    if (ctx !is null) ctx.nvg__imageDecRef(id);
    ctx = cast(NVGContext)src.ctx;
    id = src.id;
  }

  /// Is this image valid?
  @property bool valid () const pure nothrow @safe @nogc { pragma(inline, true); return (id > 0 && ctx.valid); }

  /// Is this image valid?
  @property bool isSameContext (const(NVGContext) actx) const pure nothrow @safe @nogc { pragma(inline, true); return (actx !is null && ctx is actx); }

  /// Returns image width, or zero for invalid image.
  int width () const nothrow @trusted @nogc {
    int w = 0;
    if (valid) {
      int h = void;
      ctx.params.renderGetTextureSize(cast(void*)ctx.params.userPtr, id, &w, &h);
    }
    return w;
  }

  /// Returns image height, or zero for invalid image.
  int height () const nothrow @trusted @nogc {
    int h = 0;
    if (valid) {
      int w = void;
      ctx.params.renderGetTextureSize(cast(void*)ctx.params.userPtr, id, &w, &h);
    }
    return h;
  }

  /// Free this image.
  void clear () nothrow @trusted @nogc {
    if (ctx !is null) {
      version(nanovega_debug_image_manager_rc) { import core.stdc.stdio; printf("NVGImage %p cleared (imgid=%d)\n", &this, id); }
      ctx.nvg__imageDecRef(id);
      ctx = null;
      id = 0;
    }
  }
}


/// Paint parameters for various fills. Don't change anything here!
/// Group: render_styles
public struct NVGPaint {
  NVGMatrix xform;
  float[2] extent = 0.0f;
  float radius = 0.0f;
  float feather = 0.0f;
  NVGColor innerColor; /// this can be used to modulate images (fill/font)
  NVGColor middleColor;
  NVGColor outerColor;
  float midp = -1; // middle stop for 3-color gradient
  NVGImage image;
  bool simpleColor; /// if `true`, only innerColor is used, and this is solid-color paint

  this() (in auto ref NVGPaint p) nothrow @trusted @nogc {
    xform = p.xform;
    extent[] = p.extent[];
    radius = p.radius;
    feather = p.feather;
    innerColor = p.innerColor;
    middleColor = p.middleColor;
    midp = p.midp;
    outerColor = p.outerColor;
    image = p.image;
    simpleColor = p.simpleColor;
  }

  void opAssign() (in auto ref NVGPaint p) nothrow @trusted @nogc {
    xform = p.xform;
    extent[] = p.extent[];
    radius = p.radius;
    feather = p.feather;
    innerColor = p.innerColor;
    middleColor = p.middleColor;
    midp = p.midp;
    outerColor = p.outerColor;
    image = p.image;
    simpleColor = p.simpleColor;
  }

  void clear () nothrow @trusted @nogc {
    version(aliced) pragma(inline, true);
    import core.stdc.string : memset;
    image.clear();
    memset(&this, 0, this.sizeof);
    simpleColor = true;
  }
}

/// Path winding.
/// Group: paths
public enum NVGWinding {
  CCW = 1, /// Winding for solid shapes
  CW = 2,  /// Winding for holes
}

/// Path solidity.
/// Group: paths
public enum NVGSolidity {
  Solid = 1, /// Solid shape (CCW winding).
  Hole = 2, /// Hole (CW winding).
}

/// Line cap style.
/// Group: render_styles
public enum NVGLineCap {
  Butt, ///
  Round, ///
  Square, ///
  Bevel, ///
  Miter, ///
}

/// Text align.
/// Group: text_api
public align(1) struct NVGTextAlign {
align(1):
  /// Horizontal align.
  enum H : ubyte {
    Left   = 0, /// Default, align text horizontally to left.
    Center = 1, /// Align text horizontally to center.
    Right  = 2, /// Align text horizontally to right.
  }

  /// Vertical align.
  enum V : ubyte {
    Baseline = 0, /// Default, align text vertically to baseline.
    Top      = 1, /// Align text vertically to top.
    Middle   = 2, /// Align text vertically to middle.
    Bottom   = 3, /// Align text vertically to bottom.
  }

pure nothrow @safe @nogc:
public:
  this (H h) { pragma(inline, true); value = h; } ///
  this (V v) { pragma(inline, true); value = cast(ubyte)(v<<4); } ///
  this (H h, V v) { pragma(inline, true); value = cast(ubyte)(h|(v<<4)); } ///
  this (V v, H h) { pragma(inline, true); value = cast(ubyte)(h|(v<<4)); } ///
  void reset () { pragma(inline, true); value = 0; } ///
  void reset (H h, V v) { pragma(inline, true); value = cast(ubyte)(h|(v<<4)); } ///
  void reset (V v, H h) { pragma(inline, true); value = cast(ubyte)(h|(v<<4)); } ///
@property:
  bool left () const { pragma(inline, true); return ((value&0x0f) == H.Left); } ///
  void left (bool v) { pragma(inline, true); value = cast(ubyte)((value&0xf0)|(v ? H.Left : 0)); } ///
  bool center () const { pragma(inline, true); return ((value&0x0f) == H.Center); } ///
  void center (bool v) { pragma(inline, true); value = cast(ubyte)((value&0xf0)|(v ? H.Center : 0)); } ///
  bool right () const { pragma(inline, true); return ((value&0x0f) == H.Right); } ///
  void right (bool v) { pragma(inline, true); value = cast(ubyte)((value&0xf0)|(v ? H.Right : 0)); } ///
  //
  bool baseline () const { pragma(inline, true); return (((value>>4)&0x0f) == V.Baseline); } ///
  void baseline (bool v) { pragma(inline, true); value = cast(ubyte)((value&0x0f)|(v ? V.Baseline<<4 : 0)); } ///
  bool top () const { pragma(inline, true); return (((value>>4)&0x0f) == V.Top); } ///
  void top (bool v) { pragma(inline, true); value = cast(ubyte)((value&0x0f)|(v ? V.Top<<4 : 0)); } ///
  bool middle () const { pragma(inline, true); return (((value>>4)&0x0f) == V.Middle); } ///
  void middle (bool v) { pragma(inline, true); value = cast(ubyte)((value&0x0f)|(v ? V.Middle<<4 : 0)); } ///
  bool bottom () const { pragma(inline, true); return (((value>>4)&0x0f) == V.Bottom); } ///
  void bottom (bool v) { pragma(inline, true); value = cast(ubyte)((value&0x0f)|(v ? V.Bottom<<4 : 0)); } ///
  //
  H horizontal () const { pragma(inline, true); return cast(H)(value&0x0f); } ///
  void horizontal (H v) { pragma(inline, true); value = (value&0xf0)|v; } ///
  //
  V vertical () const { pragma(inline, true); return cast(V)((value>>4)&0x0f); } ///
  void vertical (V v) { pragma(inline, true); value = (value&0x0f)|cast(ubyte)(v<<4); } ///
  //
private:
  ubyte value = 0; // low nibble: horizontal; high nibble: vertical
}

/// Blending type.
/// Group: composite_operation
public enum NVGBlendFactor {
  Zero = 1<<0, ///
  One = 1<<1, ///
  SrcColor = 1<<2, ///
  OneMinusSrcColor = 1<<3, ///
  DstColor = 1<<4, ///
  OneMinusDstColor = 1<<5, ///
  SrcAlpha = 1<<6, ///
  OneMinusSrcAlpha = 1<<7, ///
  DstAlpha = 1<<8, ///
  OneMinusDstAlpha = 1<<9, ///
  SrcAlphaSaturate = 1<<10, ///
}

/// Composite operation (HTML5-alike).
/// Group: composite_operation
public enum NVGCompositeOperation {
  SourceOver, ///
  SourceIn, ///
  SourceOut, ///
  SourceAtop, ///
  DestinationOver, ///
  DestinationIn, ///
  DestinationOut, ///
  DestinationAtop, ///
  Lighter, ///
  Copy, ///
  Xor, ///
}

/// Composite operation state.
/// Group: composite_operation
public struct NVGCompositeOperationState {
  bool simple; /// `true`: use `glBlendFunc()` instead of `glBlendFuncSeparate()`
  NVGBlendFactor srcRGB; ///
  NVGBlendFactor dstRGB; ///
  NVGBlendFactor srcAlpha; ///
  NVGBlendFactor dstAlpha; ///
}

/// Mask combining more
/// Group: clipping
public enum NVGClipMode {
  None, /// normal rendering (i.e. render path instead of modifying clip region)
  Union, /// old mask will be masked with the current one; this is the default mode for [clip]
  Or, /// new mask will be added to the current one (logical `OR` operation);
  Xor, /// new mask will be logically `XOR`ed with the current one
  Sub, /// "subtract" current path from mask
  Replace, /// replace current mask
  Add = Or, /// Synonym
}

/// Glyph position info.
/// Group: text_api
public struct NVGGlyphPosition {
  usize strpos;     /// Position of the glyph in the input string.
  float x;          /// The x-coordinate of the logical glyph position.
  float minx, maxx; /// The bounds of the glyph shape.
}

/// Text row storage.
/// Group: text_api
public struct NVGTextRow(CT) if (isAnyCharType!CT) {
  alias CharType = CT;
  const(CT)[] s;
  int start;        /// Index in the input text where the row starts.
  int end;          /// Index in the input text where the row ends (one past the last character).
  float width;      /// Logical width of the row.
  float minx, maxx; /// Actual bounds of the row. Logical with and bounds can differ because of kerning and some parts over extending.
  /// Get rest of the string.
  @property const(CT)[] rest () const pure nothrow @trusted @nogc { pragma(inline, true); return (end <= s.length ? s[end..$] : null); }
  /// Get current row.
  @property const(CT)[] row () const pure nothrow @trusted @nogc { pragma(inline, true); return s[start..end]; }
  @property const(CT)[] string () const pure nothrow @trusted @nogc { pragma(inline, true); return s; }
  @property void string(CT) (const(CT)[] v) pure nothrow @trusted @nogc { pragma(inline, true); s = v; }
}

/// Image creation flags.
/// Group: images
public enum NVGImageFlag : uint {
  None            =    0, /// Nothing special.
  GenerateMipmaps = 1<<0, /// Generate mipmaps during creation of the image.
  RepeatX         = 1<<1, /// Repeat image in X direction.
  RepeatY         = 1<<2, /// Repeat image in Y direction.
  FlipY           = 1<<3, /// Flips (inverses) image in Y direction when rendered.
  Premultiplied   = 1<<4, /// Image data has premultiplied alpha.
  NoFiltering     = 1<<8, /// use GL_NEAREST instead of GL_LINEAR
  Nearest = NoFiltering,  /// compatibility with original NanoVG
}

alias NVGImageFlags = NVGImageFlag; /// Backwards compatibility for [NVGImageFlag].


// ////////////////////////////////////////////////////////////////////////// //
private:

static T* xdup(T) (const(T)* ptr, int count) nothrow @trusted @nogc {
  import core.stdc.stdlib : malloc;
  import core.stdc.string : memcpy;
  if (count == 0) return null;
  T* res = cast(T*)malloc(T.sizeof*count);
  if (res is null) assert(0, "NanoVega: out of memory");
  memcpy(res, ptr, T.sizeof*count);
  return res;
}

// Internal Render API
enum NVGtexture {
  Alpha = 0x01,
  RGBA  = 0x02,
}

struct NVGscissor {
  NVGMatrix xform;
  float[2] extent = -1.0f;
}

struct NVGvertex {
  float x, y, u, v;
}

struct NVGpath {
  int first;
  int count;
  bool closed;
  int nbevel;
  NVGvertex* fill;
  int nfill;
  NVGvertex* stroke;
  int nstroke;
  NVGWinding winding;
  int convex;
  bool cloned;

  @disable this (this); // no copies

  void clear () nothrow @trusted @nogc {
    import core.stdc.stdlib : free;
    if (cloned) {
      if (stroke !is null && stroke !is fill) free(stroke);
      if (fill !is null) free(fill);
    }
    this = this.init;
  }

  // won't clear current path
  void copyFrom (const NVGpath* src) nothrow @trusted @nogc {
    import core.stdc.string : memcpy;
    assert(src !is null);
    memcpy(&this, src, NVGpath.sizeof);
    this.fill = xdup(src.fill, src.nfill);
    if (src.stroke is src.fill) {
      this.stroke = this.fill;
    } else {
      this.stroke = xdup(src.stroke, src.nstroke);
    }
    this.cloned = true;
  }
}


struct NVGparams {
  void* userPtr;
  bool edgeAntiAlias;
  bool fontAA;
  bool function (void* uptr) nothrow @trusted @nogc renderCreate;
  int function (void* uptr, NVGtexture type, int w, int h, int imageFlags, const(ubyte)* data) nothrow @trusted @nogc renderCreateTexture;
  bool function (void* uptr, int image) nothrow @trusted @nogc renderTextureIncRef;
  bool function (void* uptr, int image) nothrow @trusted @nogc renderDeleteTexture;
  bool function (void* uptr, int image, int x, int y, int w, int h, const(ubyte)* data) nothrow @trusted @nogc renderUpdateTexture;
  bool function (void* uptr, int image, int* w, int* h) nothrow @trusted @nogc renderGetTextureSize;
  void function (void* uptr, int width, int height) nothrow @trusted @nogc renderViewport; // called in [beginFrame]
  void function (void* uptr) nothrow @trusted @nogc renderCancel;
  void function (void* uptr) nothrow @trusted @nogc renderFlush;
  void function (void* uptr) nothrow @trusted @nogc renderPushClip; // backend should support stack of at least [NVG_MAX_STATES] elements
  void function (void* uptr) nothrow @trusted @nogc renderPopClip; // backend should support stack of at least [NVG_MAX_STATES] elements
  void function (void* uptr) nothrow @trusted @nogc renderResetClip; // reset current clip region to `non-clipped`
  void function (void* uptr, NVGCompositeOperationState compositeOperation, NVGClipMode clipmode, NVGPaint* paint, NVGscissor* scissor, float fringe, const(float)* bounds, const(NVGpath)* paths, int npaths, bool evenOdd) nothrow @trusted @nogc renderFill;
  void function (void* uptr, NVGCompositeOperationState compositeOperation, NVGClipMode clipmode, NVGPaint* paint, NVGscissor* scissor, float fringe, float strokeWidth, const(NVGpath)* paths, int npaths) nothrow @trusted @nogc renderStroke;
  void function (void* uptr, NVGCompositeOperationState compositeOperation, NVGClipMode clipmode, NVGPaint* paint, NVGscissor* scissor, const(NVGvertex)* verts, int nverts) nothrow @trusted @nogc renderTriangles;
  void function (void* uptr, in ref NVGMatrix mat) nothrow @trusted @nogc renderSetAffine;
  void function (void* uptr) nothrow @trusted @nogc renderDelete;
}

// ////////////////////////////////////////////////////////////////////////// //
private:

enum NVG_INIT_FONTIMAGE_SIZE = 512;
enum NVG_MAX_FONTIMAGE_SIZE  = 2048;
enum NVG_MAX_FONTIMAGES      = 4;

enum NVG_INIT_COMMANDS_SIZE = 256;
enum NVG_INIT_POINTS_SIZE   = 128;
enum NVG_INIT_PATHS_SIZE    = 16;
enum NVG_INIT_VERTS_SIZE    = 256;
enum NVG_MAX_STATES         = 32;

enum NVG_KAPPA90 = 0.5522847493f; // Length proportional to radius of a cubic bezier handle for 90deg arcs.
enum NVG_MIN_FEATHER = 0.001f; // it should be greater than zero, 'cause it is used in shader for divisions

enum Command {
  MoveTo = 0,
  LineTo = 1,
  BezierTo = 2,
  Close = 3,
  Winding = 4,
}

enum PointFlag : int {
  Corner = 0x01,
  Left = 0x02,
  Bevel = 0x04,
  InnerBevelPR = 0x08,
}

struct NVGstate {
  NVGCompositeOperationState compositeOperation;
  bool shapeAntiAlias = true;
  NVGPaint fill;
  NVGPaint stroke;
  float strokeWidth = 1.0f;
  float miterLimit = 10.0f;
  NVGLineCap lineJoin = NVGLineCap.Miter;
  NVGLineCap lineCap = NVGLineCap.Butt;
  float alpha = 1.0f;
  NVGMatrix xform;
  NVGscissor scissor;
  float fontSize = 16.0f;
  float letterSpacing = 0.0f;
  float lineHeight = 1.0f;
  float fontBlur = 0.0f;
  NVGTextAlign textAlign;
  int fontId = 0;
  bool evenOddMode = false; // use even-odd filling rule (required for some svgs); otherwise use non-zero fill

  void clearPaint () nothrow @trusted @nogc {
    fill.clear();
    stroke.clear();
  }
}

struct NVGpoint {
  float x, y;
  float dx, dy;
  float len;
  float dmx, dmy;
  ubyte flags;
}

struct NVGpathCache {
  NVGpoint* points;
  int npoints;
  int cpoints;
  NVGpath* paths;
  int npaths;
  int cpaths;
  NVGvertex* verts;
  int nverts;
  int cverts;
  float[4] bounds;
  // this is required for saved paths
  bool strokeReady;
  bool fillReady;
  float strokeAlphaMul;
  float strokeWidth;
  float fringeWidth;
  bool evenOddMode;
  NVGClipMode clipmode;
  // non-saved path will not have this
  float* commands;
  int ncommands;

  @disable this (this); // no copies

  // won't clear current path
  void copyFrom (const NVGpathCache* src) nothrow @trusted @nogc {
    import core.stdc.stdlib : malloc;
    import core.stdc.string : memcpy, memset;
    assert(src !is null);
    memcpy(&this, src, NVGpathCache.sizeof);
    this.points = xdup(src.points, src.npoints);
    this.cpoints = src.npoints;
    this.verts = xdup(src.verts, src.nverts);
    this.cverts = src.nverts;
    this.commands = xdup(src.commands, src.ncommands);
    if (src.npaths > 0) {
      this.paths = cast(NVGpath*)malloc(src.npaths*NVGpath.sizeof);
      memset(this.paths, 0, npaths*NVGpath.sizeof);
      foreach (immutable pidx; 0..npaths) this.paths[pidx].copyFrom(&src.paths[pidx]);
    } else {
      this.npaths = this.cpaths = 0;
    }
  }

  void clear () nothrow @trusted @nogc {
    import core.stdc.stdlib : free;
    if (paths !is null) {
      foreach (ref p; paths[0..npaths]) p.clear();
      free(paths);
    }
    if (points !is null) free(points);
    if (verts !is null) free(verts);
    if (commands !is null) free(commands);
    this = this.init;
  }
}

/// Pointer to opaque NanoVega context structure.
/// Group: context_management
public alias NVGContext = NVGcontextinternal*;

// Returns FontStash context of the given NanoVega context.
public FONScontext* fonsContext (NVGContext ctx) { return (ctx !is null ? ctx.fs : null); }

/** Bezier curve rasterizer.
 *
 * De Casteljau Bezier rasterizer is faster, but currently rasterizing curves with cusps sligtly wrong.
 * It doesn't really matter in practice.
 *
 * AFD tesselator is somewhat slower, but does cusps better.
 *
 * McSeem rasterizer should have the best quality, bit it is the slowest method. Basically, you will
 * never notice any visial difference (and this code is not really debugged), so you probably should
 * not use it. It is there for further experiments.
 */
public enum NVGTesselation {
  DeCasteljau, /// default: standard well-known tesselation algorithm
  AFD, /// adaptive forward differencing
  DeCasteljauMcSeem, /// standard well-known tesselation algorithm, with improvements from Maxim Shemanarev; slowest one, but should give best results
}

/// Default tesselator for Bezier curves.
public __gshared NVGTesselation NVG_DEFAULT_TESSELATOR = NVGTesselation.DeCasteljau;


// some public info

/// valid only inside [beginFrame]/[endFrame]
/// Group: context_management
public int width (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx !is null ? ctx.mWidth : 0); }

/// valid only inside [beginFrame]/[endFrame]
/// Group: context_management
public int height (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx !is null ? ctx.mHeight : 0); }

/// valid only inside [beginFrame]/[endFrame]
/// Group: context_management
public float devicePixelRatio (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx !is null ? ctx.mDeviceRatio : float.nan); }

// path autoregistration

/// [pickid] to stop autoregistration.
/// Group: context_management
public enum NVGNoPick = -1;

/// >=0: this pickid will be assigned to all filled/stroked paths
/// Group: context_management
public int pickid (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx !is null ? ctx.pathPickId : NVGNoPick); }

/// >=0: this pickid will be assigned to all filled/stroked paths
/// Group: context_management
public void pickid (NVGContext ctx, int v) nothrow @trusted @nogc { pragma(inline, true); if (ctx !is null) ctx.pathPickId = v; }

/// pick autoregistration mode; see [NVGPickKind]
/// Group: context_management
public uint pickmode (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx !is null ? ctx.pathPickRegistered&NVGPickKind.All : 0); }

/// pick autoregistration mode; see [NVGPickKind]
/// Group: context_management
public void pickmode (NVGContext ctx, uint v) nothrow @trusted @nogc { pragma(inline, true); if (ctx !is null) ctx.pathPickRegistered = (ctx.pathPickRegistered&0xffff_0000u)|(v&NVGPickKind.All); }

// tesselator options

///
/// Group: context_management
public NVGTesselation tesselation (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx !is null ? ctx.tesselatortype : NVGTesselation.DeCasteljau); }

///
/// Group: context_management
public void tesselation (NVGContext ctx, NVGTesselation v) nothrow @trusted @nogc { pragma(inline, true); if (ctx !is null) ctx.tesselatortype = v; }


private struct NVGcontextinternal {
private:
  NVGparams params;
  float* commands;
  int ccommands;
  int ncommands;
  float commandx, commandy;
  NVGstate[NVG_MAX_STATES] states;
  int nstates;
  NVGpathCache* cache;
  public float tessTol;
  public float angleTol; // 0.0f -- angle tolerance for McSeem Bezier rasterizer
  public float cuspLimit; // 0 -- cusp limit for McSeem Bezier rasterizer (0: real cusps)
  float distTol;
  public float fringeWidth;
  float devicePxRatio;
  FONScontext* fs;
  NVGImage[NVG_MAX_FONTIMAGES] fontImages;
  int fontImageIdx;
  int drawCallCount;
  int fillTriCount;
  int strokeTriCount;
  int textTriCount;
  NVGTesselation tesselatortype;
  // picking API
  NVGpickScene* pickScene;
  int pathPickId; // >=0: register all paths for picking using this id
  uint pathPickRegistered; // if [pathPickId] >= 0, this is used to avoid double-registration (see [NVGPickKind]); hi 16 bit is check flags, lo 16 bit is mode
  // path recording
  NVGPathSet recset;
  int recstart; // used to cancel recording
  bool recblockdraw;
  // internals
  NVGMatrix gpuAffine;
  int mWidth, mHeight;
  float mDeviceRatio;
  // image manager
  int imageCount; // number of alive images in this context
  bool contextAlive; // context can be dead, but still contain some images

  @disable this (this); // no copies
}

void nvg__imageIncRef (NVGContext ctx, int imgid) nothrow @trusted @nogc {
  if (ctx !is null && imgid > 0) {
    ++ctx.imageCount;
    version(nanovega_debug_image_manager_rc) { import core.stdc.stdio; printf("image[++]ref: context %p: %d image refs (%d)\n", ctx, ctx.imageCount, imgid); }
    if (ctx.contextAlive) ctx.params.renderTextureIncRef(ctx.params.userPtr, imgid);
  }
}

void nvg__imageDecRef (NVGContext ctx, int imgid) nothrow @trusted @nogc {
  if (ctx !is null && imgid > 0) {
    assert(ctx.imageCount > 0);
    --ctx.imageCount;
    version(nanovega_debug_image_manager_rc) { import core.stdc.stdio; printf("image[--]ref: context %p: %d image refs (%d)\n", ctx, ctx.imageCount, imgid); }
    if (ctx.contextAlive) ctx.params.renderDeleteTexture(ctx.params.userPtr, imgid);
    version(nanovega_debug_image_manager) if (!ctx.contextAlive) { import core.stdc.stdio; printf("image[--]ref: zombie context %p: %d image refs (%d)\n", ctx, ctx.imageCount, imgid); }
    if (!ctx.contextAlive && ctx.imageCount == 0) {
      // it is finally safe to free context memory
      import core.stdc.stdlib : free;
      version(nanovega_debug_image_manager) { import core.stdc.stdio; printf("killed zombie context %p\n", ctx); }
      free(ctx);
    }
  }
}


public import core.stdc.math :
  nvg__sqrtf = sqrtf,
  nvg__modf = fmodf,
  nvg__sinf = sinf,
  nvg__cosf = cosf,
  nvg__tanf = tanf,
  nvg__atan2f = atan2f,
  nvg__acosf = acosf,
  nvg__ceilf = ceilf;

version(Windows) {
  public int nvg__lrintf (float f) nothrow @trusted @nogc { pragma(inline, true); return cast(int)(f+0.5); }
} else {
  public import core.stdc.math : nvg__lrintf = lrintf;
}

public auto nvg__min(T) (T a, T b) { pragma(inline, true); return (a < b ? a : b); }
public auto nvg__max(T) (T a, T b) { pragma(inline, true); return (a > b ? a : b); }
public auto nvg__clamp(T) (T a, T mn, T mx) { pragma(inline, true); return (a < mn ? mn : (a > mx ? mx : a)); }
//float nvg__absf() (float a) { pragma(inline, true); return (a >= 0.0f ? a : -a); }
public auto nvg__sign(T) (T a) { pragma(inline, true); return (a >= cast(T)0 ? cast(T)1 : cast(T)(-1)); }
public float nvg__cross() (float dx0, float dy0, float dx1, float dy1) { pragma(inline, true); return (dx1*dy0-dx0*dy1); }

public import core.stdc.math : nvg__absf = fabsf;


float nvg__normalize (float* x, float* y) nothrow @safe @nogc {
  float d = nvg__sqrtf((*x)*(*x)+(*y)*(*y));
  if (d > 1e-6f) {
    immutable float id = 1.0f/d;
    *x *= id;
    *y *= id;
  }
  return d;
}

void nvg__deletePathCache (ref NVGpathCache* c) nothrow @trusted @nogc {
  if (c !is null) {
    c.clear();
    free(c);
  }
}

NVGpathCache* nvg__allocPathCache () nothrow @trusted @nogc {
  NVGpathCache* c = cast(NVGpathCache*)malloc(NVGpathCache.sizeof);
  if (c is null) goto error;
  memset(c, 0, NVGpathCache.sizeof);

  c.points = cast(NVGpoint*)malloc(NVGpoint.sizeof*NVG_INIT_POINTS_SIZE);
  if (c.points is null) goto error;
  assert(c.npoints == 0);
  c.cpoints = NVG_INIT_POINTS_SIZE;

  c.paths = cast(NVGpath*)malloc(NVGpath.sizeof*NVG_INIT_PATHS_SIZE);
  if (c.paths is null) goto error;
  assert(c.npaths == 0);
  c.cpaths = NVG_INIT_PATHS_SIZE;

  c.verts = cast(NVGvertex*)malloc(NVGvertex.sizeof*NVG_INIT_VERTS_SIZE);
  if (c.verts is null) goto error;
  assert(c.nverts == 0);
  c.cverts = NVG_INIT_VERTS_SIZE;

  return c;

error:
  nvg__deletePathCache(c);
  return null;
}

void nvg__setDevicePixelRatio (NVGContext ctx, float ratio) pure nothrow @safe @nogc {
  ctx.tessTol = 0.25f/ratio;
  ctx.distTol = 0.01f/ratio;
  ctx.fringeWidth = 1.0f/ratio;
  ctx.devicePxRatio = ratio;
}

NVGCompositeOperationState nvg__compositeOperationState (NVGCompositeOperation op) pure nothrow @safe @nogc {
  NVGCompositeOperationState state;
  NVGBlendFactor sfactor, dfactor;

       if (op == NVGCompositeOperation.SourceOver) { sfactor = NVGBlendFactor.One; dfactor = NVGBlendFactor.OneMinusSrcAlpha;}
  else if (op == NVGCompositeOperation.SourceIn) { sfactor = NVGBlendFactor.DstAlpha; dfactor = NVGBlendFactor.Zero; }
  else if (op == NVGCompositeOperation.SourceOut) { sfactor = NVGBlendFactor.OneMinusDstAlpha; dfactor = NVGBlendFactor.Zero; }
  else if (op == NVGCompositeOperation.SourceAtop) { sfactor = NVGBlendFactor.DstAlpha; dfactor = NVGBlendFactor.OneMinusSrcAlpha; }
  else if (op == NVGCompositeOperation.DestinationOver) { sfactor = NVGBlendFactor.OneMinusDstAlpha; dfactor = NVGBlendFactor.One; }
  else if (op == NVGCompositeOperation.DestinationIn) { sfactor = NVGBlendFactor.Zero; dfactor = NVGBlendFactor.SrcAlpha; }
  else if (op == NVGCompositeOperation.DestinationOut) { sfactor = NVGBlendFactor.Zero; dfactor = NVGBlendFactor.OneMinusSrcAlpha; }
  else if (op == NVGCompositeOperation.DestinationAtop) { sfactor = NVGBlendFactor.OneMinusDstAlpha; dfactor = NVGBlendFactor.SrcAlpha; }
  else if (op == NVGCompositeOperation.Lighter) { sfactor = NVGBlendFactor.One; dfactor = NVGBlendFactor.One; }
  else if (op == NVGCompositeOperation.Copy) { sfactor = NVGBlendFactor.One; dfactor = NVGBlendFactor.Zero;  }
  else if (op == NVGCompositeOperation.Xor) {
    state.simple = false;
    state.srcRGB = NVGBlendFactor.OneMinusDstColor;
    state.srcAlpha = NVGBlendFactor.OneMinusDstAlpha;
    state.dstRGB = NVGBlendFactor.OneMinusSrcColor;
    state.dstAlpha = NVGBlendFactor.OneMinusSrcAlpha;
    return state;
  }
  else { sfactor = NVGBlendFactor.One; dfactor = NVGBlendFactor.OneMinusSrcAlpha; } // default value for invalid op: SourceOver

  state.simple = true;
  state.srcAlpha = sfactor;
  state.dstAlpha = dfactor;
  return state;
}

NVGstate* nvg__getState (NVGContext ctx) pure nothrow @trusted @nogc {
  pragma(inline, true);
  return &ctx.states.ptr[ctx.nstates-1];
}

// Constructor called by the render back-end.
NVGContext createInternal (NVGparams* params) nothrow @trusted @nogc {
  FONSparams fontParams = void;
  NVGContext ctx = cast(NVGContext)malloc(NVGcontextinternal.sizeof);
  if (ctx is null) goto error;
  memset(ctx, 0, NVGcontextinternal.sizeof);

  ctx.angleTol = 0; // angle tolerance for McSeem Bezier rasterizer
  ctx.cuspLimit = 0; // cusp limit for McSeem Bezier rasterizer (0: real cusps)

  ctx.contextAlive = true;

  ctx.params = *params;
  //ctx.fontImages[0..NVG_MAX_FONTIMAGES] = 0;

  ctx.commands = cast(float*)malloc(float.sizeof*NVG_INIT_COMMANDS_SIZE);
  if (ctx.commands is null) goto error;
  ctx.ncommands = 0;
  ctx.ccommands = NVG_INIT_COMMANDS_SIZE;

  ctx.cache = nvg__allocPathCache();
  if (ctx.cache is null) goto error;

  ctx.save();
  ctx.reset();

  nvg__setDevicePixelRatio(ctx, 1.0f);

  if (!ctx.params.renderCreate(ctx.params.userPtr)) goto error;

  // init font rendering
  memset(&fontParams, 0, fontParams.sizeof);
  fontParams.width = NVG_INIT_FONTIMAGE_SIZE;
  fontParams.height = NVG_INIT_FONTIMAGE_SIZE;
  fontParams.flags = FONS_ZERO_TOPLEFT;
  fontParams.renderCreate = null;
  fontParams.renderUpdate = null;
  debug(nanovega) fontParams.renderDraw = null;
  fontParams.renderDelete = null;
  fontParams.userPtr = null;
  ctx.fs = fonsCreateInternal(&fontParams);
  if (ctx.fs is null) goto error;

  // create font texture
  ctx.fontImages[0].id = ctx.params.renderCreateTexture(ctx.params.userPtr, NVGtexture.Alpha, fontParams.width, fontParams.height, (ctx.params.fontAA ? 0 : NVGImageFlag.NoFiltering), null);
  if (ctx.fontImages[0].id == 0) goto error;
  ctx.fontImages[0].ctx = ctx;
  ctx.nvg__imageIncRef(ctx.fontImages[0].id);
  ctx.fontImageIdx = 0;

  ctx.pathPickId = -1;
  ctx.tesselatortype = NVG_DEFAULT_TESSELATOR;

  return ctx;

error:
  ctx.deleteInternal();
  return null;
}

// Called by render backend.
NVGparams* internalParams (NVGContext ctx) nothrow @trusted @nogc {
  return &ctx.params;
}

// Destructor called by the render back-end.
void deleteInternal (ref NVGContext ctx) nothrow @trusted @nogc {
  if (ctx is null) return;
  if (ctx.contextAlive) {
    if (ctx.commands !is null) free(ctx.commands);
    nvg__deletePathCache(ctx.cache);

    if (ctx.fs) fonsDeleteInternal(ctx.fs);

    foreach (uint i; 0..NVG_MAX_FONTIMAGES) ctx.fontImages[i].clear();

    if (ctx.params.renderDelete !is null) ctx.params.renderDelete(ctx.params.userPtr);

    if (ctx.pickScene !is null) nvg__deletePickScene(ctx.pickScene);

    ctx.contextAlive = false;

    if (ctx.imageCount == 0) {
      version(nanovega_debug_image_manager) { import core.stdc.stdio; printf("destroyed context %p\n", ctx); }
      free(ctx);
    } else {
      version(nanovega_debug_image_manager) { import core.stdc.stdio; printf("context %p is zombie now (%d image refs)\n", ctx, ctx.imageCount); }
    }
  }
}

/// Delete NanoVega context.
/// Group: context_management
public void kill (ref NVGContext ctx) nothrow @trusted @nogc {
  if (ctx !is null) {
    ctx.deleteInternal();
    ctx = null;
  }
}

/// Returns `true` if the given context is not `null` and can be used for painting.
/// Group: context_management
public bool valid (in NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx !is null && ctx.contextAlive); }


// ////////////////////////////////////////////////////////////////////////// //
// Frame Management

/** Begin drawing a new frame.
 *
 * Calls to NanoVega drawing API should be wrapped in [beginFrame] and [endFrame]
 *
 * [beginFrame] defines the size of the window to render to in relation currently
 * set viewport (i.e. glViewport on GL backends). Device pixel ration allows to
 * control the rendering on Hi-DPI devices.
 *
 * For example, GLFW returns two dimension for an opened window: window size and
 * frame buffer size. In that case you would set windowWidth/windowHeight to the window size,
 * devicePixelRatio to: `windowWidth/windowHeight`.
 *
 * Default ratio is `1`.
 *
 * Note that fractional ratio can (and will) distort your fonts and images.
 *
 * This call also resets pick marks (see picking API for non-rasterized paths),
 * path recording, and GPU affine transformatin matrix.
 *
 * see also [glNVGClearFlags], which returns necessary flags for [glClear].
 *
 * Group: frame_management
 */
public void beginFrame (NVGContext ctx, int windowWidth, int windowHeight, float devicePixelRatio=1.0f) nothrow @trusted @nogc {
  import std.math : isNaN;
  /*
  printf("Tris: draws:%d  fill:%d  stroke:%d  text:%d  TOT:%d\n",
         ctx.drawCallCount, ctx.fillTriCount, ctx.strokeTriCount, ctx.textTriCount,
         ctx.fillTriCount+ctx.strokeTriCount+ctx.textTriCount);
  */

  if (windowWidth < 1) windowWidth = 1;
  if (windowHeight < 1) windowHeight = 1;

  if (isNaN(devicePixelRatio)) devicePixelRatio = (windowHeight > 0 ? cast(float)windowWidth/cast(float)windowHeight : 1024.0/768.0);

  foreach (ref NVGstate st; ctx.states[0..ctx.nstates]) st.clearPaint();
  ctx.nstates = 0;
  ctx.save();
  ctx.reset();

  nvg__setDevicePixelRatio(ctx, devicePixelRatio);

  ctx.params.renderViewport(ctx.params.userPtr, windowWidth, windowHeight);
  ctx.mWidth = windowWidth;
  ctx.mHeight = windowHeight;
  ctx.mDeviceRatio = devicePixelRatio;

  ctx.recset = null;
  ctx.recstart = -1;

  ctx.pathPickId = NVGNoPick;
  ctx.pathPickRegistered = 0;

  ctx.drawCallCount = 0;
  ctx.fillTriCount = 0;
  ctx.strokeTriCount = 0;
  ctx.textTriCount = 0;

  ctx.gpuAffine = NVGMatrix.Identity;

  nvg__pickBeginFrame(ctx, windowWidth, windowHeight);
}

/// Cancels drawing the current frame. Cancels path recording.
/// Group: frame_management
public void cancelFrame (NVGContext ctx) nothrow @trusted @nogc {
  ctx.cancelRecording();
  ctx.mWidth = 0;
  ctx.mHeight = 0;
  ctx.mDeviceRatio = 0;
  // cancel render queue
  ctx.params.renderCancel(ctx.params.userPtr);
}

/// Ends drawing the current frame (flushing remaining render state). Commits recorded paths.
/// Group: frame_management
public void endFrame (NVGContext ctx) nothrow @trusted @nogc {
  if (ctx.recset !is null) ctx.recset.takeCurrentPickScene(ctx);
  ctx.stopRecording();
  ctx.mWidth = 0;
  ctx.mHeight = 0;
  ctx.mDeviceRatio = 0;
  // flush render queue
  NVGstate* state = nvg__getState(ctx);
  ctx.params.renderFlush(ctx.params.userPtr);
  if (ctx.fontImageIdx != 0) {
    auto fontImage = ctx.fontImages[ctx.fontImageIdx];
    int j = 0, iw, ih;
    // delete images that smaller than current one
    if (!fontImage.valid) return;
    ctx.imageSize(fontImage, iw, ih);
    foreach (int i; 0..ctx.fontImageIdx) {
      if (ctx.fontImages[i].valid) {
        int nw, nh;
        ctx.imageSize(ctx.fontImages[i], nw, nh);
        if (nw < iw || nh < ih) {
          ctx.deleteImage(ctx.fontImages[i]);
        } else {
          ctx.fontImages[j++] = ctx.fontImages[i];
        }
      }
    }
    // make current font image to first
    ctx.fontImages[j++] = ctx.fontImages[0];
    ctx.fontImages[0] = fontImage;
    ctx.fontImageIdx = 0;
    // clear all images after j
    ctx.fontImages[j..NVG_MAX_FONTIMAGES] = NVGImage.init;
  }
}


// ////////////////////////////////////////////////////////////////////////// //
// Recording and Replaying Pathes

/// Saved path set.
/// Group: path_recording
public alias NVGPathSet = NVGPathSetS*;


//TODO: save scissor info?
struct NVGPathSetS {
private:
  // either path cache, or text item
  static struct Node {
    NVGPaint paint;
    NVGpathCache* path;
  }

private:
  Node* nodes;
  int nnodes, cnodes;
  NVGpickScene* pickscene;
  //int npickscenes, cpickscenes;
  NVGContext svctx; // used to do some sanity checks, and to free resources

private:
  Node* allocNode () nothrow @trusted @nogc {
    import core.stdc.string : memset;
    // grow buffer if necessary
    if (nnodes+1 > cnodes) {
      import core.stdc.stdlib : realloc;
      int newsz = (cnodes == 0 ? 8 : cnodes <= 1024 ? cnodes*2 : cnodes+1024);
      nodes = cast(Node*)realloc(nodes, newsz*Node.sizeof);
      if (nodes is null) assert(0, "NanoVega: out of memory");
      //memset(svp.caches+svp.ccaches, 0, (newsz-svp.ccaches)*NVGpathCache.sizeof);
      cnodes = newsz;
    }
    assert(nnodes < cnodes);
    memset(nodes+nnodes, 0, Node.sizeof);
    return &nodes[nnodes++];
  }

  Node* allocPathNode () nothrow @trusted @nogc {
    import core.stdc.stdlib : malloc;
    import core.stdc.string : memset;
    auto node = allocNode();
    // allocate path cache
    auto pc = cast(NVGpathCache*)malloc(NVGpathCache.sizeof);
    if (pc is null) assert(0, "NanoVega: out of memory");
    node.path = pc;
    return node;
  }

  void clearNode (int idx) nothrow @trusted @nogc {
    if (idx < 0 || idx >= nnodes) return;
    Node* node = &nodes[idx];
    if (svctx !is null && node.paint.image.valid) node.paint.image.clear();
    if (node.path !is null) node.path.clear();
  }

private:
  void takeCurrentPickScene (NVGContext ctx) nothrow @trusted @nogc {
    NVGpickScene* ps = ctx.pickScene;
    if (ps is null) return; // nothing to do
    if (ps.npaths == 0) return; // pick scene is empty
    ctx.pickScene = null;
    pickscene = ps;
  }

  void replay (NVGContext ctx, in ref NVGColor fillTint, in ref NVGColor strokeTint) nothrow @trusted @nogc {
    NVGstate* state = nvg__getState(ctx);
    foreach (ref node; nodes[0..nnodes]) {
      if (auto cc = node.path) {
        if (cc.npaths <= 0) continue;

        if (cc.fillReady) {
          NVGPaint fillPaint = node.paint;

          // apply global alpha
          fillPaint.innerColor.a *= state.alpha;
          fillPaint.middleColor.a *= state.alpha;
          fillPaint.outerColor.a *= state.alpha;

          fillPaint.innerColor.applyTint(fillTint);
          fillPaint.middleColor.applyTint(fillTint);
          fillPaint.outerColor.applyTint(fillTint);

          ctx.params.renderFill(ctx.params.userPtr, state.compositeOperation, cc.clipmode, &fillPaint, &state.scissor, cc.fringeWidth, cc.bounds.ptr, cc.paths, cc.npaths, cc.evenOddMode);

          // count triangles
          foreach (int i; 0..cc.npaths) {
            NVGpath* path = &cc.paths[i];
            ctx.fillTriCount += path.nfill-2;
            ctx.fillTriCount += path.nstroke-2;
            ctx.drawCallCount += 2;
          }
        }

        if (cc.strokeReady) {
          NVGPaint strokePaint = node.paint;

          strokePaint.innerColor.a *= cc.strokeAlphaMul;
          strokePaint.middleColor.a *= cc.strokeAlphaMul;
          strokePaint.outerColor.a *= cc.strokeAlphaMul;

          // apply global alpha
          strokePaint.innerColor.a *= state.alpha;
          strokePaint.middleColor.a *= state.alpha;
          strokePaint.outerColor.a *= state.alpha;

          strokePaint.innerColor.applyTint(strokeTint);
          strokePaint.middleColor.applyTint(strokeTint);
          strokePaint.outerColor.applyTint(strokeTint);

          ctx.params.renderStroke(ctx.params.userPtr, state.compositeOperation, cc.clipmode, &strokePaint, &state.scissor, cc.fringeWidth, cc.strokeWidth, cc.paths, cc.npaths);

          // count triangles
          foreach (int i; 0..cc.npaths) {
            NVGpath* path = &cc.paths[i];
            ctx.strokeTriCount += path.nstroke-2;
            ++ctx.drawCallCount;
          }
        }
      }
    }
  }

public:
  @disable this (this); // no copies

  // pick test
  // Call delegate [dg] for each path under the specified position (in no particular order).
  // Returns the id of the path for which delegate [dg] returned true or -1.
  // dg is: `bool delegate (int id, int order)` -- [order] is path ordering (ascending).
  int hitTestDG(bool bestOrder=false, DG) (in float x, in float y, NVGPickKind kind, scope DG dg) if (IsGoodHitTestDG!DG || IsGoodHitTestInternalDG!DG) {
    if (pickscene is null) return -1;

    NVGpickScene* ps = pickscene;
    int levelwidth = 1<<(ps.nlevels-1);
    int cellx = nvg__clamp(cast(int)(x/ps.xdim), 0, levelwidth);
    int celly = nvg__clamp(cast(int)(y/ps.ydim), 0, levelwidth);
    int npicked = 0;

    for (int lvl = ps.nlevels-1; lvl >= 0; --lvl) {
      NVGpickPath* pp = ps.levels[lvl][celly*levelwidth+cellx];
      while (pp !is null) {
        if (nvg__pickPathTestBounds(svctx, ps, pp, x, y)) {
          int hit = 0;
          if ((kind&NVGPickKind.Stroke) && (pp.flags&NVGPathFlags.Stroke)) hit = nvg__pickPathStroke(ps, pp, x, y);
          if (!hit && (kind&NVGPickKind.Fill) && (pp.flags&NVGPathFlags.Fill)) hit = nvg__pickPath(ps, pp, x, y);
          if (hit) {
            static if (IsGoodHitTestDG!DG) {
              static if (__traits(compiles, (){ DG dg; bool res = dg(cast(int)42, cast(int)666); })) {
                if (dg(pp.id, cast(int)pp.order)) return pp.id;
              } else {
                dg(pp.id, cast(int)pp.order);
              }
            } else {
              static if (__traits(compiles, (){ DG dg; NVGpickPath* pp; bool res = dg(pp); })) {
                if (dg(pp)) return pp.id;
              } else {
                dg(pp);
              }
            }
          }
        }
        pp = pp.next;
      }
      cellx >>= 1;
      celly >>= 1;
      levelwidth >>= 1;
    }

    return -1;
  }

  // Fills ids with a list of the top most hit ids under the specified position.
  // Returns the slice of [ids].
  int[] hitTestAll (in float x, in float y, NVGPickKind kind, int[] ids) nothrow @trusted @nogc {
    if (pickscene is null || ids.length == 0) return ids[0..0];

    int npicked = 0;
    NVGpickScene* ps = pickscene;

    hitTestDG!false(x, y, kind, delegate (NVGpickPath* pp) nothrow @trusted @nogc {
      if (npicked == ps.cpicked) {
        int cpicked = ps.cpicked+ps.cpicked;
        NVGpickPath** picked = cast(NVGpickPath**)realloc(ps.picked, (NVGpickPath*).sizeof*ps.cpicked);
        if (picked is null) return true; // abort
        ps.cpicked = cpicked;
        ps.picked = picked;
      }
      ps.picked[npicked] = pp;
      ++npicked;
      return false; // go on
    });

    qsort(ps.picked, npicked, (NVGpickPath*).sizeof, &nvg__comparePaths);

    assert(npicked >= 0);
    if (npicked > ids.length) npicked = cast(int)ids.length;
    foreach (immutable nidx, ref int did; ids[0..npicked]) did = ps.picked[nidx].id;

    return ids[0..npicked];
  }

  // Returns the id of the pickable shape containing x,y or -1 if no shape was found.
  int hitTest (in float x, in float y, NVGPickKind kind) nothrow @trusted @nogc {
    if (pickscene is null) return -1;

    int bestOrder = -1;
    int bestID = -1;

    hitTestDG!true(x, y, kind, delegate (NVGpickPath* pp) nothrow @trusted @nogc {
      if (pp.order > bestOrder) {
        bestOrder = pp.order;
        bestID = pp.id;
      }
    });

    return bestID;
  }
}

// Append current path to existing path set. Is is safe to call this with `null` [svp].
void appendCurrentPathToCache (NVGContext ctx, NVGPathSet svp, in ref NVGPaint paint) nothrow @trusted @nogc {
  if (ctx is null || svp is null) return;
  if (ctx !is svp.svctx) assert(0, "NanoVega: cannot save paths from different contexts");
  if (ctx.ncommands == 0) {
    assert(ctx.cache.npaths == 0);
    return;
  }
  if (!ctx.cache.fillReady && !ctx.cache.strokeReady) return;

  // tesselate current path
  //if (!ctx.cache.fillReady) nvg__prepareFill(ctx);
  //if (!ctx.cache.strokeReady) nvg__prepareStroke(ctx);

  auto node = svp.allocPathNode();
  NVGpathCache* cc = node.path;
  cc.copyFrom(ctx.cache);
  node.paint = paint;
  // copy path commands (we may need 'em for picking)
  version(all) {
    cc.ncommands = ctx.ncommands;
    if (cc.ncommands) {
      import core.stdc.stdlib : malloc;
      import core.stdc.string : memcpy;
      cc.commands = cast(float*)malloc(ctx.ncommands*float.sizeof);
      if (cc.commands is null) assert(0, "NanoVega: out of memory");
      memcpy(cc.commands, ctx.commands, ctx.ncommands*float.sizeof);
    } else {
      cc.commands = null;
    }
  }
}

/// Create new empty path set.
/// Group: path_recording
public NVGPathSet newPathSet (NVGContext ctx) nothrow @trusted @nogc {
  import core.stdc.stdlib : malloc;
  import core.stdc.string : memset;
  if (ctx is null) return null;
  NVGPathSet res = cast(NVGPathSet)malloc(NVGPathSetS.sizeof);
  if (res is null) assert(0, "NanoVega: out of memory");
  memset(res, 0, NVGPathSetS.sizeof);
  res.svctx = ctx;
  return res;
}

/// Is the given path set empty? Empty path set can be `null`.
/// Group: path_recording
public bool empty (NVGPathSet svp) pure nothrow @safe @nogc { pragma(inline, true); return (svp is null || svp.nnodes == 0); }

/// Clear path set contents. Will release $(B some) allocated memory (this function is meant to clear something that will be reused).
/// Group: path_recording
public void clear (NVGPathSet svp) nothrow @trusted @nogc {
  if (svp !is null) {
    import core.stdc.stdlib : free;
    foreach (immutable idx; 0.. svp.nnodes) svp.clearNode(idx);
    svp.nnodes = 0;
  }
}

/// Destroy path set (frees all allocated memory).
/// Group: path_recording
public void kill (ref NVGPathSet svp) nothrow @trusted @nogc {
  if (svp !is null) {
    import core.stdc.stdlib : free;
    svp.clear();
    if (svp.nodes !is null) free(svp.nodes);
    free(svp);
    if (svp.pickscene !is null) nvg__deletePickScene(svp.pickscene);
    svp = null;
  }
}

/// Start path recording. [svp] should be alive until recording is cancelled or stopped.
/// Group: path_recording
public void startRecording (NVGContext ctx, NVGPathSet svp) nothrow @trusted @nogc {
  if (svp !is null && svp.svctx !is ctx) assert(0, "NanoVega: cannot share path set between contexts");
  ctx.stopRecording();
  ctx.recset = svp;
  ctx.recstart = (svp !is null ? svp.nnodes : -1);
  ctx.recblockdraw = false;
}

/** Start path recording. [svp] should be alive until recording is cancelled or stopped.
 *
 * This will block all rendering, so you can call your rendering functions to record paths without actual drawing.
 * Commiting or cancelling will re-enable rendering.
 * You can call this with `null` svp to block rendering without recording any paths.
 *
 * Group: path_recording
 */
public void startBlockingRecording (NVGContext ctx, NVGPathSet svp) nothrow @trusted @nogc {
  if (svp !is null && svp.svctx !is ctx) assert(0, "NanoVega: cannot share path set between contexts");
  ctx.stopRecording();
  ctx.recset = svp;
  ctx.recstart = (svp !is null ? svp.nnodes : -1);
  ctx.recblockdraw = true;
}

/// Commit recorded paths. It is safe to call this when recording is not started.
/// Group: path_recording
public void stopRecording (NVGContext ctx) nothrow @trusted @nogc {
  if (ctx.recset !is null && ctx.recset.svctx !is ctx) assert(0, "NanoVega: cannot share path set between contexts");
  if (ctx.recset !is null) ctx.recset.takeCurrentPickScene(ctx);
  ctx.recset = null;
  ctx.recstart = -1;
  ctx.recblockdraw = false;
}

/// Cancel path recording.
/// Group: path_recording
public void cancelRecording (NVGContext ctx) nothrow @trusted @nogc {
  if (ctx.recset !is null) {
    if (ctx.recset.svctx !is ctx) assert(0, "NanoVega: cannot share path set between contexts");
    assert(ctx.recstart >= 0 && ctx.recstart <= ctx.recset.nnodes);
    foreach (immutable idx; ctx.recstart..ctx.recset.nnodes) ctx.recset.clearNode(idx);
    ctx.recset.nnodes = ctx.recstart;
    ctx.recset = null;
    ctx.recstart = -1;
  }
  ctx.recblockdraw = false;
}

/** Replay saved path set.
 *
 * Replaying record while you're recording another one is undefined behavior.
 *
 * Group: path_recording
 */
public void replayRecording() (NVGContext ctx, NVGPathSet svp, in auto ref NVGColor fillTint, in auto ref NVGColor strokeTint) nothrow @trusted @nogc {
  if (svp !is null && svp.svctx !is ctx) assert(0, "NanoVega: cannot share path set between contexts");
  svp.replay(ctx, fillTint, strokeTint);
}

/// Ditto.
public void replayRecording() (NVGContext ctx, NVGPathSet svp, in auto ref NVGColor fillTint) nothrow @trusted @nogc { ctx.replayRecording(svp, fillTint, NVGColor.transparent); }

/// Ditto.
public void replayRecording (NVGContext ctx, NVGPathSet svp) nothrow @trusted @nogc { ctx.replayRecording(svp, NVGColor.transparent, NVGColor.transparent); }


// ////////////////////////////////////////////////////////////////////////// //
// Composite operation

/// Sets the composite operation.
/// Group: composite_operation
public void globalCompositeOperation (NVGContext ctx, NVGCompositeOperation op) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.compositeOperation = nvg__compositeOperationState(op);
}

/// Sets the composite operation with custom pixel arithmetic.
/// Group: composite_operation
public void globalCompositeBlendFunc (NVGContext ctx, NVGBlendFactor sfactor, NVGBlendFactor dfactor) nothrow @trusted @nogc {
  ctx.globalCompositeBlendFuncSeparate(sfactor, dfactor, sfactor, dfactor);
}

/// Sets the composite operation with custom pixel arithmetic for RGB and alpha components separately.
/// Group: composite_operation
public void globalCompositeBlendFuncSeparate (NVGContext ctx, NVGBlendFactor srcRGB, NVGBlendFactor dstRGB, NVGBlendFactor srcAlpha, NVGBlendFactor dstAlpha) nothrow @trusted @nogc {
  NVGCompositeOperationState op;
  op.simple = false;
  op.srcRGB = srcRGB;
  op.dstRGB = dstRGB;
  op.srcAlpha = srcAlpha;
  op.dstAlpha = dstAlpha;
  NVGstate* state = nvg__getState(ctx);
  state.compositeOperation = op;
}


// ////////////////////////////////////////////////////////////////////////// //
// Color utils

/// Returns a color value from string form.
/// Supports: "#rgb", "#rrggbb", "#argb", "#aarrggbb"
/// Group: color_utils
public NVGColor nvgRGB (const(char)[] srgb) nothrow @trusted @nogc { pragma(inline, true); return NVGColor(srgb); }

/// Ditto.
public NVGColor nvgRGBA (const(char)[] srgb) nothrow @trusted @nogc { pragma(inline, true); return NVGColor(srgb); }

/// Returns a color value from red, green, blue values. Alpha will be set to 255 (1.0f).
/// Group: color_utils
public NVGColor nvgRGB (int r, int g, int b) nothrow @trusted @nogc { pragma(inline, true); return NVGColor(nvgClampToByte(r), nvgClampToByte(g), nvgClampToByte(b), 255); }

/// Returns a color value from red, green, blue values. Alpha will be set to 1.0f.
/// Group: color_utils
public NVGColor nvgRGBf (float r, float g, float b) nothrow @trusted @nogc { pragma(inline, true); return NVGColor(r, g, b, 1.0f); }

/// Returns a color value from red, green, blue and alpha values.
/// Group: color_utils
public NVGColor nvgRGBA (int r, int g, int b, int a=255) nothrow @trusted @nogc { pragma(inline, true); return NVGColor(nvgClampToByte(r), nvgClampToByte(g), nvgClampToByte(b), nvgClampToByte(a)); }

/// Returns a color value from red, green, blue and alpha values.
/// Group: color_utils
public NVGColor nvgRGBAf (float r, float g, float b, float a=1.0f) nothrow @trusted @nogc { pragma(inline, true); return NVGColor(r, g, b, a); }

/// Returns new color with transparency (alpha) set to [a].
/// Group: color_utils
public NVGColor nvgTransRGBA (NVGColor c, ubyte a) nothrow @trusted @nogc {
  pragma(inline, true);
  c.a = a/255.0f;
  return c;
}

/// Ditto.
public NVGColor nvgTransRGBAf (NVGColor c, float a) nothrow @trusted @nogc {
  pragma(inline, true);
  c.a = a;
  return c;
}

/// Linearly interpolates from color c0 to c1, and returns resulting color value.
/// Group: color_utils
public NVGColor nvgLerpRGBA() (in auto ref NVGColor c0, in auto ref NVGColor c1, float u) nothrow @trusted @nogc {
  NVGColor cint = void;
  u = nvg__clamp(u, 0.0f, 1.0f);
  float oneminu = 1.0f-u;
  foreach (uint i; 0..4) cint.rgba.ptr[i] = c0.rgba.ptr[i]*oneminu+c1.rgba.ptr[i]*u;
  return cint;
}

/* see below
public NVGColor nvgHSL() (float h, float s, float l) {
  //pragma(inline, true); // alas
  return nvgHSLA(h, s, l, 255);
}
*/

float nvg__hue (float h, float m1, float m2) pure nothrow @safe @nogc {
  if (h < 0) h += 1;
  if (h > 1) h -= 1;
  if (h < 1.0f/6.0f) return m1+(m2-m1)*h*6.0f;
  if (h < 3.0f/6.0f) return m2;
  if (h < 4.0f/6.0f) return m1+(m2-m1)*(2.0f/3.0f-h)*6.0f;
  return m1;
}

/// Returns color value specified by hue, saturation and lightness.
/// HSL values are all in range [0..1], alpha will be set to 255.
/// Group: color_utils
public alias nvgHSL = nvgHSLA; // trick to allow inlining

/// Returns color value specified by hue, saturation and lightness and alpha.
/// HSL values are all in range [0..1], alpha in range [0..255].
/// Group: color_utils
public NVGColor nvgHSLA (float h, float s, float l, ubyte a=255) nothrow @trusted @nogc {
  pragma(inline, true);
  NVGColor col = void;
  h = nvg__modf(h, 1.0f);
  if (h < 0.0f) h += 1.0f;
  s = nvg__clamp(s, 0.0f, 1.0f);
  l = nvg__clamp(l, 0.0f, 1.0f);
  immutable float m2 = (l <= 0.5f ? l*(1+s) : l+s-l*s);
  immutable float m1 = 2*l-m2;
  col.r = nvg__clamp(nvg__hue(h+1.0f/3.0f, m1, m2), 0.0f, 1.0f);
  col.g = nvg__clamp(nvg__hue(h, m1, m2), 0.0f, 1.0f);
  col.b = nvg__clamp(nvg__hue(h-1.0f/3.0f, m1, m2), 0.0f, 1.0f);
  col.a = a/255.0f;
  return col;
}

/// Returns color value specified by hue, saturation and lightness and alpha.
/// HSL values and alpha are all in range [0..1].
/// Group: color_utils
public NVGColor nvgHSLA (float h, float s, float l, float a) nothrow @trusted @nogc {
  // sorry for copypasta, it is for inliner
  static if (__VERSION__ >= 2072) pragma(inline, true);
  NVGColor col = void;
  h = nvg__modf(h, 1.0f);
  if (h < 0.0f) h += 1.0f;
  s = nvg__clamp(s, 0.0f, 1.0f);
  l = nvg__clamp(l, 0.0f, 1.0f);
  immutable m2 = (l <= 0.5f ? l*(1+s) : l+s-l*s);
  immutable m1 = 2*l-m2;
  col.r = nvg__clamp(nvg__hue(h+1.0f/3.0f, m1, m2), 0.0f, 1.0f);
  col.g = nvg__clamp(nvg__hue(h, m1, m2), 0.0f, 1.0f);
  col.b = nvg__clamp(nvg__hue(h-1.0f/3.0f, m1, m2), 0.0f, 1.0f);
  col.a = a;
  return col;
}


// ////////////////////////////////////////////////////////////////////////// //
// Matrices and Transformations

/** Matrix class.
 *
 * Group: matrices
 */
public align(1) struct NVGMatrix {
align(1):
private:
  static immutable float[6] IdentityMat = [
    1.0f, 0.0f,
    0.0f, 1.0f,
    0.0f, 0.0f,
  ];

public:
  /// Matrix values. Initial value is identity matrix.
  float[6] mat = [
    1.0f, 0.0f,
    0.0f, 1.0f,
    0.0f, 0.0f,
  ];

public nothrow @trusted @nogc:
  /// Create Matrix with the given values.
  this (const(float)[] amat...) {
    pragma(inline, true);
    if (amat.length >= 6) {
      mat.ptr[0..6] = amat.ptr[0..6];
    } else {
      mat.ptr[0..6] = 0;
      mat.ptr[0..amat.length] = amat[];
    }
  }

  /// Can be used to check validity of [inverted] result
  @property bool valid () const { import core.stdc.math : isfinite; return (isfinite(mat.ptr[0]) != 0); }

  /// Returns `true` if this matrix is identity matrix.
  @property bool isIdentity () const { version(aliced) pragma(inline, true); return (mat[] == IdentityMat[]); }

  /// Returns new inverse matrix.
  /// If inverted matrix cannot be calculated, `res.valid` fill be `false`.
  NVGMatrix inverted () const {
    NVGMatrix res = this;
    res.invert;
    return res;
  }

  /// Inverts this matrix.
  /// If inverted matrix cannot be calculated, `this.valid` fill be `false`.
  ref NVGMatrix invert () {
    float[6] inv = void;
    immutable double det = cast(double)mat.ptr[0]*mat.ptr[3]-cast(double)mat.ptr[2]*mat.ptr[1];
    if (det > -1e-6 && det < 1e-6) {
      inv[] = float.nan;
    } else {
      immutable double invdet = 1.0/det;
      inv.ptr[0] = cast(float)(mat.ptr[3]*invdet);
      inv.ptr[2] = cast(float)(-mat.ptr[2]*invdet);
      inv.ptr[4] = cast(float)((cast(double)mat.ptr[2]*mat.ptr[5]-cast(double)mat.ptr[3]*mat.ptr[4])*invdet);
      inv.ptr[1] = cast(float)(-mat.ptr[1]*invdet);
      inv.ptr[3] = cast(float)(mat.ptr[0]*invdet);
      inv.ptr[5] = cast(float)((cast(double)mat.ptr[1]*mat.ptr[4]-cast(double)mat.ptr[0]*mat.ptr[5])*invdet);
    }
    mat.ptr[0..6] = inv.ptr[0..6];
    return this;
  }

  /// Sets this matrix to identity matrix.
  ref NVGMatrix identity () { version(aliced) pragma(inline, true); mat[] = IdentityMat[]; return this; }

  /// Translate this matrix.
  ref NVGMatrix translate (in float tx, in float ty) {
    version(aliced) pragma(inline, true);
    return this.mul(Translated(tx, ty));
  }

  /// Scale this matrix.
  ref NVGMatrix scale (in float sx, in float sy) {
    version(aliced) pragma(inline, true);
    return this.mul(Scaled(sx, sy));
  }

  /// Rotate this matrix.
  ref NVGMatrix rotate (in float a) {
    version(aliced) pragma(inline, true);
    return this.mul(Rotated(a));
  }

  /// Skew this matrix by X axis.
  ref NVGMatrix skewX (in float a) {
    version(aliced) pragma(inline, true);
    return this.mul(SkewedX(a));
  }

  /// Skew this matrix by Y axis.
  ref NVGMatrix skewY (in float a) {
    version(aliced) pragma(inline, true);
    return this.mul(SkewedY(a));
  }

  /// Skew this matrix by both axes.
  ref NVGMatrix skewY (in float ax, in float ay) {
    version(aliced) pragma(inline, true);
    return this.mul(SkewedXY(ax, ay));
  }

  /// Transform point with this matrix. `null` destinations are allowed.
  /// [sx] and [sy] is the source point. [dx] and [dy] may point to the same variables.
  void point (float* dx, float* dy, float sx, float sy) nothrow @trusted @nogc {
    version(aliced) pragma(inline, true);
    if (dx !is null) *dx = sx*mat.ptr[0]+sy*mat.ptr[2]+mat.ptr[4];
    if (dy !is null) *dy = sx*mat.ptr[1]+sy*mat.ptr[3]+mat.ptr[5];
  }

  /// Transform point with this matrix.
  void point (ref float x, ref float y) nothrow @trusted @nogc {
    version(aliced) pragma(inline, true);
    immutable float nx = x*mat.ptr[0]+y*mat.ptr[2]+mat.ptr[4];
    immutable float ny = x*mat.ptr[1]+y*mat.ptr[3]+mat.ptr[5];
    x = nx;
    y = ny;
  }

  /// Sets this matrix to the result of multiplication of `this` and [s] (this * S).
  ref NVGMatrix mul() (in auto ref NVGMatrix s) {
    immutable float t0 = mat.ptr[0]*s.mat.ptr[0]+mat.ptr[1]*s.mat.ptr[2];
    immutable float t2 = mat.ptr[2]*s.mat.ptr[0]+mat.ptr[3]*s.mat.ptr[2];
    immutable float t4 = mat.ptr[4]*s.mat.ptr[0]+mat.ptr[5]*s.mat.ptr[2]+s.mat.ptr[4];
    mat.ptr[1] = mat.ptr[0]*s.mat.ptr[1]+mat.ptr[1]*s.mat.ptr[3];
    mat.ptr[3] = mat.ptr[2]*s.mat.ptr[1]+mat.ptr[3]*s.mat.ptr[3];
    mat.ptr[5] = mat.ptr[4]*s.mat.ptr[1]+mat.ptr[5]*s.mat.ptr[3]+s.mat.ptr[5];
    mat.ptr[0] = t0;
    mat.ptr[2] = t2;
    mat.ptr[4] = t4;
    return this;
  }

  /// Sets this matrix to the result of multiplication of [s] and `this` (S * this).
  /// Sets the transform to the result of multiplication of two transforms, of A = B*A.
  /// Group: matrices
  ref NVGMatrix premul() (in auto ref NVGMatrix s) {
    NVGMatrix s2 = s;
    s2.mul(this);
    mat[] = s2.mat[];
    return this;
  }

  /// Multiply this matrix by [s], return result as new matrix.
  /// Performs operations in this left-to-right order.
  NVGMatrix opBinary(string op="*") (in auto ref NVGMatrix s) const {
    version(aliced) pragma(inline, true);
    NVGMatrix res = this;
    res.mul(s);
    return res;
  }

  /// Multiply this matrix by [s].
  /// Performs operations in this left-to-right order.
  ref NVGMatrix opOpAssign(string op="*") (in auto ref NVGMatrix s) {
    version(aliced) pragma(inline, true);
    return this.mul(s);
  }

  float scaleX () const { pragma(inline, true); return nvg__sqrtf(mat.ptr[0]*mat.ptr[0]+mat.ptr[2]*mat.ptr[2]); } /// Returns x scaling of this matrix.
  float scaleY () const { pragma(inline, true); return nvg__sqrtf(mat.ptr[1]*mat.ptr[1]+mat.ptr[3]*mat.ptr[3]); } /// Returns y scaling of this matrix.
  float rotation () const { pragma(inline, true); return nvg__atan2f(mat.ptr[1], mat.ptr[0]); } /// Returns rotation of this matrix.
  float tx () const { pragma(inline, true); return mat.ptr[4]; } /// Returns x translation of this matrix.
  float ty () const { pragma(inline, true); return mat.ptr[5]; } /// Returns y translation of this matrix.

  ref NVGMatrix scaleX (in float v) { pragma(inline, true); return scaleRotateTransform(v, scaleY, rotation, tx, ty); } /// Sets x scaling of this matrix.
  ref NVGMatrix scaleY (in float v) { pragma(inline, true); return scaleRotateTransform(scaleX, v, rotation, tx, ty); } /// Sets y scaling of this matrix.
  ref NVGMatrix rotation (in float v) { pragma(inline, true); return scaleRotateTransform(scaleX, scaleY, v, tx, ty); } /// Sets rotation of this matrix.
  ref NVGMatrix tx (in float v) { pragma(inline, true); mat.ptr[4] = v; return this; } /// Sets x translation of this matrix.
  ref NVGMatrix ty (in float v) { pragma(inline, true); mat.ptr[5] = v; return this; } /// Sets y translation of this matrix.

  /// Utility function to be used in `setXXX()`.
  /// This is the same as doing: `mat.identity.rotate(a).scale(xs, ys).translate(tx, ty)`, only faster
  ref NVGMatrix scaleRotateTransform (in float xscale, in float yscale, in float a, in float tx, in float ty) {
    immutable float cs = nvg__cosf(a), sn = nvg__sinf(a);
    mat.ptr[0] = xscale*cs; mat.ptr[1] = yscale*sn;
    mat.ptr[2] = xscale*-sn; mat.ptr[3] = yscale*cs;
    mat.ptr[4] = tx; mat.ptr[5] = ty;
    return this;
  }

  /// This is the same as doing: `mat.identity.rotate(a).translate(tx, ty)`, only faster
  ref NVGMatrix rotateTransform (in float a, in float tx, in float ty) {
    immutable float cs = nvg__cosf(a), sn = nvg__sinf(a);
    mat.ptr[0] = cs; mat.ptr[1] = sn;
    mat.ptr[2] = -sn; mat.ptr[3] = cs;
    mat.ptr[4] = tx; mat.ptr[5] = ty;
    return this;
  }

  /// Returns new identity matrix.
  static NVGMatrix Identity () { pragma(inline, true); return NVGMatrix.init; }

  /// Returns new translation matrix.
  static NVGMatrix Translated (in float tx, in float ty) {
    version(aliced) pragma(inline, true);
    NVGMatrix res = void;
    res.mat.ptr[0] = 1.0f; res.mat.ptr[1] = 0.0f;
    res.mat.ptr[2] = 0.0f; res.mat.ptr[3] = 1.0f;
    res.mat.ptr[4] = tx; res.mat.ptr[5] = ty;
    return res;
  }

  /// Returns new scaling matrix.
  static NVGMatrix Scaled (in float sx, in float sy) {
    version(aliced) pragma(inline, true);
    NVGMatrix res = void;
    res.mat.ptr[0] = sx; res.mat.ptr[1] = 0.0f;
    res.mat.ptr[2] = 0.0f; res.mat.ptr[3] = sy;
    res.mat.ptr[4] = 0.0f; res.mat.ptr[5] = 0.0f;
    return res;
  }

  /// Returns new rotation matrix. Angle is specified in radians.
  static NVGMatrix Rotated (in float a) {
    version(aliced) pragma(inline, true);
    immutable float cs = nvg__cosf(a), sn = nvg__sinf(a);
    NVGMatrix res = void;
    res.mat.ptr[0] = cs; res.mat.ptr[1] = sn;
    res.mat.ptr[2] = -sn; res.mat.ptr[3] = cs;
    res.mat.ptr[4] = 0.0f; res.mat.ptr[5] = 0.0f;
    return res;
  }

  /// Returns new x-skewing matrix. Angle is specified in radians.
  static NVGMatrix SkewedX (in float a) {
    version(aliced) pragma(inline, true);
    NVGMatrix res = void;
    res.mat.ptr[0] = 1.0f; res.mat.ptr[1] = 0.0f;
    res.mat.ptr[2] = nvg__tanf(a); res.mat.ptr[3] = 1.0f;
    res.mat.ptr[4] = 0.0f; res.mat.ptr[5] = 0.0f;
    return res;
  }

  /// Returns new y-skewing matrix. Angle is specified in radians.
  static NVGMatrix SkewedY (in float a) {
    version(aliced) pragma(inline, true);
    NVGMatrix res = void;
    res.mat.ptr[0] = 1.0f; res.mat.ptr[1] = nvg__tanf(a);
    res.mat.ptr[2] = 0.0f; res.mat.ptr[3] = 1.0f;
    res.mat.ptr[4] = 0.0f; res.mat.ptr[5] = 0.0f;
    return res;
  }

  /// Returns new xy-skewing matrix. Angles are specified in radians.
  static NVGMatrix SkewedXY (in float ax, in float ay) {
    version(aliced) pragma(inline, true);
    NVGMatrix res = void;
    res.mat.ptr[0] = 1.0f; res.mat.ptr[1] = nvg__tanf(ay);
    res.mat.ptr[2] = nvg__tanf(ax); res.mat.ptr[3] = 1.0f;
    res.mat.ptr[4] = 0.0f; res.mat.ptr[5] = 0.0f;
    return res;
  }

  /// Utility function to be used in `setXXX()`.
  /// This is the same as doing: `NVGMatrix.Identity.rotate(a).scale(xs, ys).translate(tx, ty)`, only faster
  static NVGMatrix ScaledRotatedTransformed (in float xscale, in float yscale, in float a, in float tx, in float ty) {
    NVGMatrix res = void;
    res.scaleRotateTransform(xscale, yscale, a, tx, ty);
    return res;
  }

  /// This is the same as doing: `NVGMatrix.Identity.rotate(a).translate(tx, ty)`, only faster
  static NVGMatrix RotatedTransformed (in float a, in float tx, in float ty) {
    NVGMatrix res = void;
    res.rotateTransform(a, tx, ty);
    return res;
  }
}


/// Converts degrees to radians.
/// Group: matrices
public float nvgDegToRad() (in float deg) pure nothrow @safe @nogc { pragma(inline, true); return deg/180.0f*NVG_PI; }

/// Converts radians to degrees.
/// Group: matrices
public float nvgRadToDeg() (in float rad) pure nothrow @safe @nogc { pragma(inline, true); return rad/NVG_PI*180.0f; }

public alias nvgDegrees = nvgDegToRad; /// Use this like `42.nvgDegrees`
public float nvgRadians() (in float rad) pure nothrow @safe @nogc { pragma(inline, true); return rad; } /// Use this like `0.1.nvgRadians`


// ////////////////////////////////////////////////////////////////////////// //
void nvg__setPaintColor() (ref NVGPaint p, in auto ref NVGColor color) nothrow @trusted @nogc {
  p.clear();
  p.xform.identity;
  p.radius = 0.0f;
  p.feather = 1.0f;
  p.innerColor = p.middleColor = p.outerColor = color;
  p.midp = -1;
  p.simpleColor = true;
}


// ////////////////////////////////////////////////////////////////////////// //
// State handling

version(nanovega_debug_clipping) {
  public void nvgClipDumpOn (NVGContext ctx) { glnvg__clipDebugDump(ctx.params.userPtr, true); }
  public void nvgClipDumpOff (NVGContext ctx) { glnvg__clipDebugDump(ctx.params.userPtr, false); }
}

/** Pushes and saves the current render state into a state stack.
 * A matching [restore] must be used to restore the state.
 * Returns `false` if state stack overflowed.
 *
 * Group: state_handling
 */
public bool save (NVGContext ctx) nothrow @trusted @nogc {
  if (ctx.nstates >= NVG_MAX_STATES) return false;
  if (ctx.nstates > 0) {
    //memcpy(&ctx.states[ctx.nstates], &ctx.states[ctx.nstates-1], NVGstate.sizeof);
    ctx.states[ctx.nstates] = ctx.states[ctx.nstates-1];
    ctx.params.renderPushClip(ctx.params.userPtr);
  }
  ++ctx.nstates;
  return true;
}

/// Pops and restores current render state.
/// Group: state_handling
public bool restore (NVGContext ctx) nothrow @trusted @nogc {
  if (ctx.nstates <= 1) return false;
  ctx.states[ctx.nstates-1].clearPaint();
  ctx.params.renderPopClip(ctx.params.userPtr);
  --ctx.nstates;
  return true;
}

/// Resets current render state to default values. Does not affect the render state stack.
/// Group: state_handling
public void reset (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.clearPaint();

  nvg__setPaintColor(state.fill, nvgRGBA(255, 255, 255, 255));
  nvg__setPaintColor(state.stroke, nvgRGBA(0, 0, 0, 255));
  state.compositeOperation = nvg__compositeOperationState(NVGCompositeOperation.SourceOver);
  state.shapeAntiAlias = true;
  state.strokeWidth = 1.0f;
  state.miterLimit = 10.0f;
  state.lineCap = NVGLineCap.Butt;
  state.lineJoin = NVGLineCap.Miter;
  state.alpha = 1.0f;
  state.xform.identity;

  state.scissor.extent[] = -1.0f;

  state.fontSize = 16.0f;
  state.letterSpacing = 0.0f;
  state.lineHeight = 1.0f;
  state.fontBlur = 0.0f;
  state.textAlign.reset;
  state.fontId = 0;
  state.evenOddMode = false;

  ctx.params.renderResetClip(ctx.params.userPtr);
}

/** Returns `true` if we have any room in state stack.
 * It is guaranteed to have at least 32 stack slots.
 *
 * Group: state_handling
 */
public bool canSave (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx.nstates < NVG_MAX_STATES); }

/** Returns `true` if we have any saved state.
 *
 * Group: state_handling
 */
public bool canRestore (NVGContext ctx) pure nothrow @trusted @nogc { pragma(inline, true); return (ctx.nstates > 1); }


// ////////////////////////////////////////////////////////////////////////// //
// Render styles

/// Sets filling mode to "even-odd".
/// Group: render_styles
public void evenOddFill (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.evenOddMode = true;
}

/// Sets filling mode to "non-zero" (this is default mode).
/// Group: render_styles
public void nonZeroFill (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.evenOddMode = false;
}

/// Sets whether to draw antialias for [stroke] and [fill]. It's enabled by default.
/// Group: render_styles
public void shapeAntiAlias (NVGContext ctx, bool enabled) {
  NVGstate* state = nvg__getState(ctx);
  state.shapeAntiAlias = enabled;
}

/// Sets the stroke width of the stroke style.
/// Group: render_styles
public void strokeWidth (NVGContext ctx, float width) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.strokeWidth = width;
}

/// Sets the miter limit of the stroke style. Miter limit controls when a sharp corner is beveled.
/// Group: render_styles
public void miterLimit (NVGContext ctx, float limit) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.miterLimit = limit;
}

/// Sets how the end of the line (cap) is drawn,
/// Can be one of: NVGLineCap.Butt (default), NVGLineCap.Round, NVGLineCap.Square.
/// Group: render_styles
public void lineCap (NVGContext ctx, NVGLineCap cap) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.lineCap = cap;
}

/// Sets how sharp path corners are drawn.
/// Can be one of NVGLineCap.Miter (default), NVGLineCap.Round, NVGLineCap.Bevel.
/// Group: render_styles
public void lineJoin (NVGContext ctx, NVGLineCap join) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.lineJoin = join;
}

/// Sets the transparency applied to all rendered shapes.
/// Already transparent paths will get proportionally more transparent as well.
/// Group: render_styles
public void globalAlpha (NVGContext ctx, float alpha) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.alpha = alpha;
}

static if (NanoVegaHasArsdColor) {
/// Sets current stroke style to a solid color.
/// Group: render_styles
public void strokeColor (NVGContext ctx, Color color) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  nvg__setPaintColor(state.stroke, NVGColor(color));
}
}

/// Sets current stroke style to a solid color.
/// Group: render_styles
public void strokeColor() (NVGContext ctx, in auto ref NVGColor color) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  nvg__setPaintColor(state.stroke, color);
}

/// Sets current stroke style to a paint, which can be a one of the gradients or a pattern.
/// Group: render_styles
public void strokePaint() (NVGContext ctx, in auto ref NVGPaint paint) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.stroke = paint;
  //nvgTransformMultiply(state.stroke.xform[], state.xform[]);
  state.stroke.xform.mul(state.xform);
}

static if (NanoVegaHasArsdColor) {
/// Sets current fill style to a solid color.
/// Group: render_styles
public void fillColor (NVGContext ctx, Color color) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  nvg__setPaintColor(state.fill, NVGColor(color));
}
}

/// Sets current fill style to a solid color.
/// Group: render_styles
public void fillColor() (NVGContext ctx, in auto ref NVGColor color) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  nvg__setPaintColor(state.fill, color);
}

/// Sets current fill style to a paint, which can be a one of the gradients or a pattern.
/// Group: render_styles
public void fillPaint() (NVGContext ctx, in auto ref NVGPaint paint) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.fill = paint;
  //nvgTransformMultiply(state.fill.xform[], state.xform[]);
  state.fill.xform.mul(state.xform);
}

/// Sets current fill style to a multistop linear gradient.
/// Group: render_styles
public void fillPaint() (NVGContext ctx, in auto ref NVGLGS lgs) nothrow @trusted @nogc {
  if (!lgs.valid) {
    NVGPaint p = void;
    memset(&p, 0, p.sizeof);
    nvg__setPaintColor(p, NVGColor.red);
    ctx.fillPaint = p;
  } else if (lgs.midp >= -1) {
    //{ import core.stdc.stdio; printf("SIMPLE! midp=%f\n", cast(double)lgs.midp); }
    ctx.fillPaint = ctx.linearGradient(lgs.cx, lgs.cy, lgs.dimx, lgs.dimy, lgs.ic, lgs.midp, lgs.mc, lgs.oc);
  } else {
    ctx.fillPaint = ctx.imagePattern(lgs.cx, lgs.cy, lgs.dimx, lgs.dimy, lgs.angle, lgs.imgid);
  }
}

/// Returns current transformation matrix.
/// Group: render_transformations
public NVGMatrix currTransform (NVGContext ctx) pure nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  return state.xform;
}

/// Sets current transformation matrix.
/// Group: render_transformations
public void currTransform() (NVGContext ctx, in auto ref NVGMatrix m) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.xform = m;
}

/// Resets current transform to an identity matrix.
/// Group: render_transformations
public void resetTransform (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.xform.identity;
}

/// Premultiplies current coordinate system by specified matrix.
/// Group: render_transformations
public void transform() (NVGContext ctx, in auto ref NVGMatrix mt) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  //nvgTransformPremultiply(state.xform[], t[]);
  state.xform *= mt;
}

/// Translates current coordinate system.
/// Group: render_transformations
public void translate (NVGContext ctx, in float x, in float y) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  //NVGMatrix t = void;
  //nvgTransformTranslate(t[], x, y);
  //nvgTransformPremultiply(state.xform[], t[]);
  state.xform.premul(NVGMatrix.Translated(x, y));
}

/// Rotates current coordinate system. Angle is specified in radians.
/// Group: render_transformations
public void rotate (NVGContext ctx, in float angle) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  //NVGMatrix t = void;
  //nvgTransformRotate(t[], angle);
  //nvgTransformPremultiply(state.xform[], t[]);
  state.xform.premul(NVGMatrix.Rotated(angle));
}

/// Skews the current coordinate system along X axis. Angle is specified in radians.
/// Group: render_transformations
public void skewX (NVGContext ctx, in float angle) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  //NVGMatrix t = void;
  //nvgTransformSkewX(t[], angle);
  //nvgTransformPremultiply(state.xform[], t[]);
  state.xform.premul(NVGMatrix.SkewedX(angle));
}

/// Skews the current coordinate system along Y axis. Angle is specified in radians.
/// Group: render_transformations
public void skewY (NVGContext ctx, in float angle) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  //NVGMatrix t = void;
  //nvgTransformSkewY(t[], angle);
  //nvgTransformPremultiply(state.xform[], t[]);
  state.xform.premul(NVGMatrix.SkewedY(angle));
}

/// Scales the current coordinate system.
/// Group: render_transformations
public void scale (NVGContext ctx, in float x, in float y) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  //NVGMatrix t = void;
  //nvgTransformScale(t[], x, y);
  //nvgTransformPremultiply(state.xform[], t[]);
  state.xform.premul(NVGMatrix.Scaled(x, y));
}


// ////////////////////////////////////////////////////////////////////////// //
// Images

/// Creates image by loading it from the disk from specified file name.
/// Returns handle to the image or 0 on error.
/// Group: images
public NVGImage createImage() (NVGContext ctx, const(char)[] filename, const(NVGImageFlag)[] imageFlagsList...) {
  static if (NanoVegaHasArsdImage) {
    import arsd.image;
    // do we have new arsd API to load images?
    static if (!is(typeof(MemoryImage.fromImageFile)) || !is(typeof(MemoryImage.clearInternal))) {
      static assert(0, "Sorry, your ARSD is too old. Please, update it.");
    }
    try {
      auto oimg = MemoryImage.fromImageFile(filename);
      if (auto img = cast(TrueColorImage)oimg) {
        scope(exit) oimg.clearInternal();
        return ctx.createImageRGBA(img.width, img.height, img.imageData.bytes[], imageFlagsList);
      } else {
        TrueColorImage img = oimg.getAsTrueColorImage;
        scope(exit) img.clearInternal();
        oimg.clearInternal(); // drop original image, as `getAsTrueColorImage()` MUST create a new one here
        oimg = null;
        return ctx.createImageRGBA(img.width, img.height, img.imageData.bytes[], imageFlagsList);
      }
    } catch (Exception) {}
    return NVGImage.init;
  } else {
    import std.internal.cstring;
    ubyte* img;
    int w, h, n;
    stbi_set_unpremultiply_on_load(1);
    stbi_convert_iphone_png_to_rgb(1);
    img = stbi_load(filename.tempCString, &w, &h, &n, 4);
    if (img is null) {
      //printf("Failed to load %s - %s\n", filename, stbi_failure_reason());
      return NVGImage.init;
    }
    auto image = ctx.createImageRGBA(w, h, img[0..w*h*4], imageFlagsList);
    stbi_image_free(img);
    return image;
  }
}

static if (NanoVegaHasArsdImage) {
  /// Creates image by loading it from the specified memory image.
  /// Returns handle to the image or 0 on error.
  /// Group: images
  public NVGImage createImageFromMemoryImage() (NVGContext ctx, MemoryImage img, const(NVGImageFlag)[] imageFlagsList...) {
    if (img is null) return NVGImage.init;
    if (auto tc = cast(TrueColorImage)img) {
      return ctx.createImageRGBA(tc.width, tc.height, tc.imageData.bytes[], imageFlagsList);
    } else {
      auto tc = img.getAsTrueColorImage;
      scope(exit) tc.clearInternal(); // here, it is guaranteed that `tc` is newly allocated image, so it is safe to kill it
      return ctx.createImageRGBA(tc.width, tc.height, tc.imageData.bytes[], imageFlagsList);
    }
  }
} else {
  /// Creates image by loading it from the specified chunk of memory.
  /// Returns handle to the image or 0 on error.
  /// Group: images
  public NVGImage createImageMem() (NVGContext ctx, const(ubyte)* data, int ndata, const(NVGImageFlag)[] imageFlagsList...) {
    int w, h, n, image;
    ubyte* img = stbi_load_from_memory(data, ndata, &w, &h, &n, 4);
    if (img is null) {
      //printf("Failed to load %s - %s\n", filename, stbi_failure_reason());
      return NVGImage.init;
    }
    image = ctx.createImageRGBA(w, h, img[0..w*h*4], imageFlagsList);
    stbi_image_free(img);
    return image;
  }
}

/// Creates image from specified image data.
/// Returns handle to the image or 0 on error.
/// Group: images
public NVGImage createImageRGBA (NVGContext ctx, int w, int h, const(void)[] data, const(NVGImageFlag)[] imageFlagsList...) nothrow @trusted @nogc {
  if (w < 1 || h < 1 || data.length < w*h*4) return NVGImage.init;
  uint imageFlags = 0;
  foreach (immutable uint flag; imageFlagsList) imageFlags |= flag;
  NVGImage res;
  res.id = ctx.params.renderCreateTexture(ctx.params.userPtr, NVGtexture.RGBA, w, h, imageFlags, cast(const(ubyte)*)data.ptr);
  if (res.id > 0) {
    res.ctx = ctx;
    ctx.nvg__imageIncRef(res.id);
  }
  return res;
}

/// Updates image data specified by image handle.
/// Group: images
public void updateImage() (NVGContext ctx, auto ref NVGImage image, const(void)[] data) nothrow @trusted @nogc {
  if (image.valid) {
    int w, h;
    if (image.ctx !is ctx) assert(0, "NanoVega: you cannot use image from one context in another context");
    ctx.params.renderGetTextureSize(ctx.params.userPtr, image.id, &w, &h);
    ctx.params.renderUpdateTexture(ctx.params.userPtr, image.id, 0, 0, w, h, cast(const(ubyte)*)data.ptr);
  }
}

/// Returns the dimensions of a created image.
/// Group: images
public void imageSize() (NVGContext ctx, in auto ref NVGImage image, out int w, out int h) nothrow @trusted @nogc {
  if (image.valid) {
    if (image.ctx !is ctx) assert(0, "NanoVega: you cannot use image from one context in another context");
    ctx.params.renderGetTextureSize(cast(void*)ctx.params.userPtr, image.id, &w, &h);
  }
}

/// Deletes created image.
/// Group: images
public void deleteImage() (NVGContext ctx, ref NVGImage image) nothrow @trusted @nogc {
  if (ctx is null || !image.valid) return;
  if (image.ctx !is ctx) assert(0, "NanoVega: you cannot use image from one context in another context");
  image.clear();
}


// ////////////////////////////////////////////////////////////////////////// //
// Paints

static if (NanoVegaHasArsdColor) {
/** Creates and returns a linear gradient. Parameters `(sx, sy) (ex, ey)` specify the start and end coordinates
 * of the linear gradient, icol specifies the start color and ocol the end color.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint linearGradient (NVGContext ctx, in float sx, in float sy, in float ex, in float ey, in Color icol, in Color ocol) nothrow @trusted @nogc {
  return ctx.linearGradient(sx, sy, ex, ey, NVGColor(icol), NVGColor(ocol));
}
/** Creates and returns a linear gradient with middle stop. Parameters `(sx, sy) (ex, ey)` specify the start
 * and end coordinates of the linear gradient, icol specifies the start color, midp specifies stop point in
 * range `(0..1)`, and ocol the end color.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint linearGradient (NVGContext ctx, in float sx, in float sy, in float ex, in float ey, in Color icol, in float midp, in Color mcol, in Color ocol) nothrow @trusted @nogc {
  return ctx.linearGradient(sx, sy, ex, ey, NVGColor(icol), midp, NVGColor(mcol), NVGColor(ocol));
}
}

/** Creates and returns a linear gradient. Parameters `(sx, sy) (ex, ey)` specify the start and end coordinates
 * of the linear gradient, icol specifies the start color and ocol the end color.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint linearGradient() (NVGContext ctx, float sx, float sy, float ex, float ey, in auto ref NVGColor icol, in auto ref NVGColor ocol) nothrow @trusted @nogc {
  enum large = 1e5f;

  NVGPaint p = void;
  memset(&p, 0, p.sizeof);
  p.simpleColor = false;

  // Calculate transform aligned to the line
  float dx = ex-sx;
  float dy = ey-sy;
  immutable float d = nvg__sqrtf(dx*dx+dy*dy);
  if (d > 0.0001f) {
    dx /= d;
    dy /= d;
  } else {
    dx = 0;
    dy = 1;
  }

  p.xform.mat.ptr[0] = dy; p.xform.mat.ptr[1] = -dx;
  p.xform.mat.ptr[2] = dx; p.xform.mat.ptr[3] = dy;
  p.xform.mat.ptr[4] = sx-dx*large; p.xform.mat.ptr[5] = sy-dy*large;

  p.extent.ptr[0] = large;
  p.extent.ptr[1] = large+d*0.5f;

  p.radius = 0.0f;

  p.feather = nvg__max(NVG_MIN_FEATHER, d);

  p.innerColor = p.middleColor = icol;
  p.outerColor = ocol;
  p.midp = -1;

  return p;
}

/** Creates and returns a linear gradient with middle stop. Parameters `(sx, sy) (ex, ey)` specify the start
 * and end coordinates of the linear gradient, icol specifies the start color, midp specifies stop point in
 * range `(0..1)`, and ocol the end color.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint linearGradient() (NVGContext ctx, float sx, float sy, float ex, float ey, in auto ref NVGColor icol, in float midp, in auto ref NVGColor mcol, in auto ref NVGColor ocol) nothrow @trusted @nogc {
  enum large = 1e5f;

  NVGPaint p = void;
  memset(&p, 0, p.sizeof);
  p.simpleColor = false;

  // Calculate transform aligned to the line
  float dx = ex-sx;
  float dy = ey-sy;
  immutable float d = nvg__sqrtf(dx*dx+dy*dy);
  if (d > 0.0001f) {
    dx /= d;
    dy /= d;
  } else {
    dx = 0;
    dy = 1;
  }

  p.xform.mat.ptr[0] = dy; p.xform.mat.ptr[1] = -dx;
  p.xform.mat.ptr[2] = dx; p.xform.mat.ptr[3] = dy;
  p.xform.mat.ptr[4] = sx-dx*large; p.xform.mat.ptr[5] = sy-dy*large;

  p.extent.ptr[0] = large;
  p.extent.ptr[1] = large+d*0.5f;

  p.radius = 0.0f;

  p.feather = nvg__max(NVG_MIN_FEATHER, d);

  if (midp <= 0) {
    p.innerColor = p.middleColor = mcol;
    p.midp = -1;
  } else if (midp > 1) {
    p.innerColor = p.middleColor = icol;
    p.midp = -1;
  } else {
    p.innerColor = icol;
    p.middleColor = mcol;
    p.midp = midp;
  }
  p.outerColor = ocol;

  return p;
}

static if (NanoVegaHasArsdColor) {
/** Creates and returns a radial gradient. Parameters (cx, cy) specify the center, inr and outr specify
 * the inner and outer radius of the gradient, icol specifies the start color and ocol the end color.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint radialGradient (NVGContext ctx, in float cx, in float cy, in float inr, in float outr, in Color icol, in Color ocol) nothrow @trusted @nogc {
  return ctx.radialGradient(cx, cy, inr, outr, NVGColor(icol), NVGColor(ocol));
}
}

/** Creates and returns a radial gradient. Parameters (cx, cy) specify the center, inr and outr specify
 * the inner and outer radius of the gradient, icol specifies the start color and ocol the end color.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint radialGradient() (NVGContext ctx, float cx, float cy, float inr, float outr, in auto ref NVGColor icol, in auto ref NVGColor ocol) nothrow @trusted @nogc {
  immutable float r = (inr+outr)*0.5f;
  immutable float f = (outr-inr);

  NVGPaint p = void;
  memset(&p, 0, p.sizeof);
  p.simpleColor = false;

  p.xform.identity;
  p.xform.mat.ptr[4] = cx;
  p.xform.mat.ptr[5] = cy;

  p.extent.ptr[0] = r;
  p.extent.ptr[1] = r;

  p.radius = r;

  p.feather = nvg__max(NVG_MIN_FEATHER, f);

  p.innerColor = p.middleColor = icol;
  p.outerColor = ocol;
  p.midp = -1;

  return p;
}

static if (NanoVegaHasArsdColor) {
/** Creates and returns a box gradient. Box gradient is a feathered rounded rectangle, it is useful for rendering
 * drop shadows or highlights for boxes. Parameters (x, y) define the top-left corner of the rectangle,
 * (w, h) define the size of the rectangle, r defines the corner radius, and f feather. Feather defines how blurry
 * the border of the rectangle is. Parameter icol specifies the inner color and ocol the outer color of the gradient.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint boxGradient (NVGContext ctx, in float x, in float y, in float w, in float h, in float r, in float f, in Color icol, in Color ocol) nothrow @trusted @nogc {
  return ctx.boxGradient(x, y, w, h, r, f, NVGColor(icol), NVGColor(ocol));
}
}

/** Creates and returns a box gradient. Box gradient is a feathered rounded rectangle, it is useful for rendering
 * drop shadows or highlights for boxes. Parameters (x, y) define the top-left corner of the rectangle,
 * (w, h) define the size of the rectangle, r defines the corner radius, and f feather. Feather defines how blurry
 * the border of the rectangle is. Parameter icol specifies the inner color and ocol the outer color of the gradient.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint boxGradient() (NVGContext ctx, float x, float y, float w, float h, float r, float f, in auto ref NVGColor icol, in auto ref NVGColor ocol) nothrow @trusted @nogc {
  NVGPaint p = void;
  memset(&p, 0, p.sizeof);
  p.simpleColor = false;

  p.xform.identity;
  p.xform.mat.ptr[4] = x+w*0.5f;
  p.xform.mat.ptr[5] = y+h*0.5f;

  p.extent.ptr[0] = w*0.5f;
  p.extent.ptr[1] = h*0.5f;

  p.radius = r;

  p.feather = nvg__max(NVG_MIN_FEATHER, f);

  p.innerColor = p.middleColor = icol;
  p.outerColor = ocol;
  p.midp = -1;

  return p;
}

/** Creates and returns an image pattern. Parameters `(cx, cy)` specify the left-top location of the image pattern,
 * `(w, h)` the size of one image, [angle] rotation around the top-left corner, [image] is handle to the image to render.
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * Group: paints
 */
public NVGPaint imagePattern() (NVGContext ctx, float cx, float cy, float w, float h, float angle, in auto ref NVGImage image, float alpha=1) nothrow @trusted @nogc {
  NVGPaint p = void;
  memset(&p, 0, p.sizeof);
  p.simpleColor = false;

  p.xform.identity.rotate(angle);
  p.xform.mat.ptr[4] = cx;
  p.xform.mat.ptr[5] = cy;

  p.extent.ptr[0] = w;
  p.extent.ptr[1] = h;

  p.image = image;

  p.innerColor = p.middleColor = p.outerColor = nvgRGBAf(1, 1, 1, alpha);
  p.midp = -1;

  return p;
}

/// Linear gradient with multiple stops.
/// $(WARNING THIS IS EXPERIMENTAL API AND MAY BE CHANGED/BROKEN IN NEXT RELEASES!)
/// Group: paints
public struct NVGLGS {
private:
  NVGColor ic, mc, oc; // inner, middle, out
  float midp;
  NVGImage imgid;
  // [imagePattern] arguments
  float cx, cy, dimx, dimy; // dimx and dimy are ex and ey for simple gradients
  public float angle; ///

public:
  @disable this (this); // no copies
  @property bool valid () const pure nothrow @safe @nogc { pragma(inline, true); return (imgid.valid || midp >= -1); } ///
  void clear ()  nothrow @safe @nogc { pragma(inline, true); imgid.clear(); midp = float.nan; } ///
}

/** Returns [NVGPaint] for linear gradient with stops, created with [createLinearGradientWithStops].
 * The gradient is transformed by the current transform when it is passed to [fillPaint] or [strokePaint].
 *
 * $(WARNING THIS IS EXPERIMENTAL API AND MAY BE CHANGED/BROKEN IN NEXT RELEASES!)
 * Group: paints
 */
public NVGPaint asPaint() (NVGContext ctx, in auto ref NVGLGS lgs) nothrow @trusted @nogc {
  if (!lgs.valid) {
    NVGPaint p = void;
    memset(&p, 0, p.sizeof);
    nvg__setPaintColor(p, NVGColor.red);
    return p;
  } else if (lgs.midp >= -1) {
    return ctx.linearGradient(lgs.cx, lgs.cy, lgs.dimx, lgs.dimy, lgs.ic, lgs.midp, lgs.mc, lgs.oc);
  } else {
    return ctx.imagePattern(lgs.cx, lgs.cy, lgs.dimx, lgs.dimy, lgs.angle, lgs.imgid);
  }
}

/// Gradient Stop Point.
/// $(WARNING THIS IS EXPERIMENTAL API AND MAY BE CHANGED/BROKEN IN NEXT RELEASES!)
/// Group: paints
public struct NVGGradientStop {
  float offset = 0; /// [0..1]
  NVGColor color; ///

  this() (in float aofs, in auto ref NVGColor aclr) nothrow @trusted @nogc { pragma(inline, true); offset = aofs; color = aclr; } ///
  static if (NanoVegaHasArsdColor) {
    this() (in float aofs, in Color aclr) nothrow @trusted @nogc { pragma(inline, true); offset = aofs; color = NVGColor(aclr); } ///
  }
}

/// Create linear gradient data suitable to use with `linearGradient(res)`.
/// Don't forget to destroy the result when you don't need it anymore with `ctx.kill(res);`.
/// $(WARNING THIS IS EXPERIMENTAL API AND MAY BE CHANGED/BROKEN IN NEXT RELEASES!)
/// Group: paints
public NVGLGS createLinearGradientWithStops (NVGContext ctx, in float sx, in float sy, in float ex, in float ey, const(NVGGradientStop)[] stops...) nothrow @trusted @nogc {
  // based on the code by Jorge Acereda <jacereda@gmail.com>
  enum NVG_GRADIENT_SAMPLES = 1024;
  static void gradientSpan (uint* dst, const(NVGGradientStop)* s0, const(NVGGradientStop)* s1) nothrow @trusted @nogc {
    immutable float s0o = nvg__clamp(s0.offset, 0.0f, 1.0f);
    immutable float s1o = nvg__clamp(s1.offset, 0.0f, 1.0f);
    uint s = cast(uint)(s0o*NVG_GRADIENT_SAMPLES);
    uint e = cast(uint)(s1o*NVG_GRADIENT_SAMPLES);
    uint sc = 0xffffffffU;
    uint sh = 24;
    uint r = cast(uint)(s0.color.rgba[0]*sc);
    uint g = cast(uint)(s0.color.rgba[1]*sc);
    uint b = cast(uint)(s0.color.rgba[2]*sc);
    uint a = cast(uint)(s0.color.rgba[3]*sc);
    uint dr = cast(uint)((s1.color.rgba[0]*sc-r)/(e-s));
    uint dg = cast(uint)((s1.color.rgba[1]*sc-g)/(e-s));
    uint db = cast(uint)((s1.color.rgba[2]*sc-b)/(e-s));
    uint da = cast(uint)((s1.color.rgba[3]*sc-a)/(e-s));
    dst += s;
    foreach (immutable _; s..e) {
      version(BigEndian) {
        *dst++ = ((r>>sh)<<24)+((g>>sh)<<16)+((b>>sh)<<8)+((a>>sh)<<0);
      } else {
        *dst++ = ((a>>sh)<<24)+((b>>sh)<<16)+((g>>sh)<<8)+((r>>sh)<<0);
      }
      r += dr;
      g += dg;
      b += db;
      a += da;
    }
  }

  NVGLGS res;
  res.cx = sx;
  res.cy = sy;

  if (stops.length == 2 && stops.ptr[0].offset <= 0 && stops.ptr[1].offset >= 1) {
    // create simple linear gradient
    res.ic = res.mc = stops.ptr[0].color;
    res.oc = stops.ptr[1].color;
    res.midp = -1;
    res.dimx = ex;
    res.dimy = ey;
  } else if (stops.length == 3 && stops.ptr[0].offset <= 0 && stops.ptr[2].offset >= 1) {
    // create simple linear gradient with middle stop
    res.ic = stops.ptr[0].color;
    res.mc = stops.ptr[1].color;
    res.oc = stops.ptr[2].color;
    res.midp = stops.ptr[1].offset;
    res.dimx = ex;
    res.dimy = ey;
  } else {
    // create image gradient
    uint[NVG_GRADIENT_SAMPLES] data = void;
    immutable float w = ex-sx;
    immutable float h = ey-sy;
    res.dimx = nvg__sqrtf(w*w+h*h);
    res.dimy = 1; //???

    res.angle =
      (/*nvg__absf(h) < 0.0001 ? 0 :
       nvg__absf(w) < 0.0001 ? 90.nvgDegrees :*/
       nvg__atan2f(h/*ey-sy*/, w/*ex-sx*/));

    if (stops.length > 0) {
      auto s0 = NVGGradientStop(0, nvgRGBAf(0, 0, 0, 1));
      auto s1 = NVGGradientStop(1, nvgRGBAf(1, 1, 1, 1));
      if (stops.length > 64) stops = stops[0..64];
      if (stops.length) {
        s0.color = stops[0].color;
        s1.color = stops[$-1].color;
      }
      gradientSpan(data.ptr, &s0, (stops.length ? stops.ptr : &s1));
      foreach (immutable i; 0..stops.length-1) gradientSpan(data.ptr, stops.ptr+i, stops.ptr+i+1);
      gradientSpan(data.ptr, (stops.length ? stops.ptr+stops.length-1 : &s0), &s1);
      res.imgid = ctx.createImageRGBA(NVG_GRADIENT_SAMPLES, 1, data[]/*, NVGImageFlag.RepeatX, NVGImageFlag.RepeatY*/);
    }
  }
  return res;
}


// ////////////////////////////////////////////////////////////////////////// //
// Scissoring

/// Sets the current scissor rectangle. The scissor rectangle is transformed by the current transform.
/// Group: scissoring
public void scissor (NVGContext ctx, in float x, in float y, float w, float h) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);

  w = nvg__max(0.0f, w);
  h = nvg__max(0.0f, h);

  state.scissor.xform.identity;
  state.scissor.xform.mat.ptr[4] = x+w*0.5f;
  state.scissor.xform.mat.ptr[5] = y+h*0.5f;
  //nvgTransformMultiply(state.scissor.xform[], state.xform[]);
  state.scissor.xform.mul(state.xform);

  state.scissor.extent.ptr[0] = w*0.5f;
  state.scissor.extent.ptr[1] = h*0.5f;
}

/// Sets the current scissor rectangle. The scissor rectangle is transformed by the current transform.
/// Arguments: [x, y, w, h]*
/// Group: scissoring
public void scissor (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 4;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [scissor] call");
  if (args.length < ArgC) return;
  NVGstate* state = nvg__getState(ctx);
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable x = *aptr++;
    immutable y = *aptr++;
    immutable w = nvg__max(0.0f, *aptr++);
    immutable h = nvg__max(0.0f, *aptr++);

    state.scissor.xform.identity;
    state.scissor.xform.mat.ptr[4] = x+w*0.5f;
    state.scissor.xform.mat.ptr[5] = y+h*0.5f;
    //nvgTransformMultiply(state.scissor.xform[], state.xform[]);
    state.scissor.xform.mul(state.xform);

    state.scissor.extent.ptr[0] = w*0.5f;
    state.scissor.extent.ptr[1] = h*0.5f;
  }
}

void nvg__isectRects (float* dst, float ax, float ay, float aw, float ah, float bx, float by, float bw, float bh) nothrow @trusted @nogc {
  immutable float minx = nvg__max(ax, bx);
  immutable float miny = nvg__max(ay, by);
  immutable float maxx = nvg__min(ax+aw, bx+bw);
  immutable float maxy = nvg__min(ay+ah, by+bh);
  dst[0] = minx;
  dst[1] = miny;
  dst[2] = nvg__max(0.0f, maxx-minx);
  dst[3] = nvg__max(0.0f, maxy-miny);
}

/** Intersects current scissor rectangle with the specified rectangle.
 * The scissor rectangle is transformed by the current transform.
 * Note: in case the rotation of previous scissor rect differs from
 * the current one, the intersection will be done between the specified
 * rectangle and the previous scissor rectangle transformed in the current
 * transform space. The resulting shape is always rectangle.
 *
 * Group: scissoring
 */
public void intersectScissor (NVGContext ctx, in float x, in float y, in float w, in float h) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);

  // If no previous scissor has been set, set the scissor as current scissor.
  if (state.scissor.extent.ptr[0] < 0) {
    ctx.scissor(x, y, w, h);
    return;
  }

  NVGMatrix pxform = void;
  NVGMatrix invxorm = void;
  float[4] rect = void;

  // Transform the current scissor rect into current transform space.
  // If there is difference in rotation, this will be approximation.
  //memcpy(pxform.mat.ptr, state.scissor.xform.ptr, float.sizeof*6);
  pxform = state.scissor.xform;
  immutable float ex = state.scissor.extent.ptr[0];
  immutable float ey = state.scissor.extent.ptr[1];
  //nvgTransformInverse(invxorm[], state.xform[]);
  invxorm = state.xform.inverted;
  //nvgTransformMultiply(pxform[], invxorm[]);
  pxform.mul(invxorm);
  immutable float tex = ex*nvg__absf(pxform.mat.ptr[0])+ey*nvg__absf(pxform.mat.ptr[2]);
  immutable float tey = ex*nvg__absf(pxform.mat.ptr[1])+ey*nvg__absf(pxform.mat.ptr[3]);

  // Intersect rects.
  nvg__isectRects(rect.ptr, pxform.mat.ptr[4]-tex, pxform.mat.ptr[5]-tey, tex*2, tey*2, x, y, w, h);

  //ctx.scissor(rect.ptr[0], rect.ptr[1], rect.ptr[2], rect.ptr[3]);
  ctx.scissor(rect.ptr[0..4]);
}

/** Intersects current scissor rectangle with the specified rectangle.
 * The scissor rectangle is transformed by the current transform.
 * Note: in case the rotation of previous scissor rect differs from
 * the current one, the intersection will be done between the specified
 * rectangle and the previous scissor rectangle transformed in the current
 * transform space. The resulting shape is always rectangle.
 *
 * Arguments: [x, y, w, h]*
 *
 * Group: scissoring
 */
public void intersectScissor (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 4;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [intersectScissor] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable x = *aptr++;
    immutable y = *aptr++;
    immutable w = *aptr++;
    immutable h = *aptr++;
    ctx.intersectScissor(x, y, w, h);
  }
}

/// Reset and disables scissoring.
/// Group: scissoring
public void resetScissor (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  state.scissor.xform.mat[] = 0.0f;
  state.scissor.extent[] = -1.0f;
}


// ////////////////////////////////////////////////////////////////////////// //
// Render-Time Affine Transformations

/// Sets GPU affine transformatin matrix. Don't do scaling or skewing here.
/// This matrix won't be saved/restored with context state save/restore operations, as it is not a part of that state.
/// Group: gpu_affine
public void affineGPU() (NVGContext ctx, in auto ref NVGMatrix mat) nothrow @trusted @nogc {
  ctx.gpuAffine = mat;
  ctx.params.renderSetAffine(ctx.params.userPtr, ctx.gpuAffine);
}

/// Get current GPU affine transformatin matrix.
/// Group: gpu_affine
public NVGMatrix affineGPU (NVGContext ctx) nothrow @safe @nogc {
  pragma(inline, true);
  return ctx.gpuAffine;
}

/// "Untransform" point using current GPU affine matrix.
/// Group: gpu_affine
public void gpuUntransformPoint (NVGContext ctx, float *dx, float *dy, in float x, in float y) nothrow @safe @nogc {
  if (ctx.gpuAffine.isIdentity) {
    if (dx !is null) *dx = x;
    if (dy !is null) *dy = y;
  } else {
    // inverse GPU transformation
    NVGMatrix igpu = ctx.gpuAffine.inverted;
    igpu.point(dx, dy, x, y);
  }
}


// ////////////////////////////////////////////////////////////////////////// //
// rasterization (tesselation) code

int nvg__ptEquals (float x1, float y1, float x2, float y2, float tol) pure nothrow @safe @nogc {
  //pragma(inline, true);
  immutable float dx = x2-x1;
  immutable float dy = y2-y1;
  return dx*dx+dy*dy < tol*tol;
}

float nvg__distPtSeg (float x, float y, float px, float py, float qx, float qy) pure nothrow @safe @nogc {
  immutable float pqx = qx-px;
  immutable float pqy = qy-py;
  float dx = x-px;
  float dy = y-py;
  immutable float d = pqx*pqx+pqy*pqy;
  float t = pqx*dx+pqy*dy;
  if (d > 0) t /= d;
  if (t < 0) t = 0; else if (t > 1) t = 1;
  dx = px+t*pqx-x;
  dy = py+t*pqy-y;
  return dx*dx+dy*dy;
}

void nvg__appendCommands(bool useCommand=true) (NVGContext ctx, Command acmd, const(float)[] vals...) nothrow @trusted @nogc {
  int nvals = cast(int)vals.length;
  static if (useCommand) {
    enum addon = 1;
  } else {
    enum addon = 0;
    if (nvals == 0) return; // nothing to do
  }

  NVGstate* state = nvg__getState(ctx);

  if (ctx.ncommands+nvals+addon > ctx.ccommands) {
    //int ccommands = ctx.ncommands+nvals+ctx.ccommands/2;
    int ccommands = ((ctx.ncommands+(nvals+addon))|0xfff)+1;
    float* commands = cast(float*)realloc(ctx.commands, float.sizeof*ccommands);
    if (commands is null) assert(0, "NanoVega: out of memory");
    ctx.commands = commands;
    ctx.ccommands = ccommands;
    assert(ctx.ncommands+(nvals+addon) <= ctx.ccommands);
  }

  static if (!useCommand) acmd = cast(Command)vals.ptr[0];

  if (acmd != Command.Close && acmd != Command.Winding) {
    //assert(nvals+addon >= 3);
    ctx.commandx = vals.ptr[nvals-2];
    ctx.commandy = vals.ptr[nvals-1];
  }

  // copy commands
  float* vp = ctx.commands+ctx.ncommands;
  static if (useCommand) {
    vp[0] = cast(float)acmd;
    if (nvals > 0) memcpy(vp+1, vals.ptr, nvals*float.sizeof);
  } else {
    memcpy(vp, vals.ptr, nvals*float.sizeof);
  }
  ctx.ncommands += nvals+addon;

  // transform commands
  int i = nvals+addon;
  while (i > 0) {
    int nlen = 1;
    final switch (cast(Command)(*vp)) {
      case Command.MoveTo:
      case Command.LineTo:
        assert(i >= 3);
        state.xform.point(vp+1, vp+2, vp[1], vp[2]);
        nlen = 3;
        break;
      case Command.BezierTo:
        assert(i >= 7);
        state.xform.point(vp+1, vp+2, vp[1], vp[2]);
        state.xform.point(vp+3, vp+4, vp[3], vp[4]);
        state.xform.point(vp+5, vp+6, vp[5], vp[6]);
        nlen = 7;
        break;
      case Command.Close:
        nlen = 1;
        break;
      case Command.Winding:
        nlen = 2;
        break;
    }
    assert(nlen > 0 && nlen <= i);
    i -= nlen;
    vp += nlen;
  }
}

void nvg__clearPathCache (NVGContext ctx) nothrow @trusted @nogc {
  // no need to clear paths, as data is not copied there
  //foreach (ref p; ctx.cache.paths[0..ctx.cache.npaths]) p.clear();
  ctx.cache.npoints = 0;
  ctx.cache.npaths = 0;
  ctx.cache.fillReady = ctx.cache.strokeReady = false;
  ctx.cache.clipmode = NVGClipMode.None;
}

NVGpath* nvg__lastPath (NVGContext ctx) nothrow @trusted @nogc {
  return (ctx.cache.npaths > 0 ? &ctx.cache.paths[ctx.cache.npaths-1] : null);
}

void nvg__addPath (NVGContext ctx) nothrow @trusted @nogc {
  import core.stdc.stdlib : realloc;
  import core.stdc.string : memset;

  if (ctx.cache.npaths+1 > ctx.cache.cpaths) {
    int cpaths = ctx.cache.npaths+1+ctx.cache.cpaths/2;
    NVGpath* paths = cast(NVGpath*)realloc(ctx.cache.paths, NVGpath.sizeof*cpaths);
    if (paths is null) assert(0, "NanoVega: out of memory");
    ctx.cache.paths = paths;
    ctx.cache.cpaths = cpaths;
  }

  NVGpath* path = &ctx.cache.paths[ctx.cache.npaths++];
  memset(path, 0, NVGpath.sizeof);
  path.first = ctx.cache.npoints;
  path.winding = NVGWinding.CCW;
}

NVGpoint* nvg__lastPoint (NVGContext ctx) nothrow @trusted @nogc {
  return (ctx.cache.npoints > 0 ? &ctx.cache.points[ctx.cache.npoints-1] : null);
}

void nvg__addPoint (NVGContext ctx, float x, float y, int flags) nothrow @trusted @nogc {
  NVGpath* path = nvg__lastPath(ctx);
  if (path is null) return;

  if (path.count > 0 && ctx.cache.npoints > 0) {
    NVGpoint* pt = nvg__lastPoint(ctx);
    if (nvg__ptEquals(pt.x, pt.y, x, y, ctx.distTol)) {
      pt.flags |= flags;
      return;
    }
  }

  if (ctx.cache.npoints+1 > ctx.cache.cpoints) {
    int cpoints = ctx.cache.npoints+1+ctx.cache.cpoints/2;
    NVGpoint* points = cast(NVGpoint*)realloc(ctx.cache.points, NVGpoint.sizeof*cpoints);
    if (points is null) return;
    ctx.cache.points = points;
    ctx.cache.cpoints = cpoints;
  }

  NVGpoint* pt = &ctx.cache.points[ctx.cache.npoints];
  memset(pt, 0, (*pt).sizeof);
  pt.x = x;
  pt.y = y;
  pt.flags = cast(ubyte)flags;

  ++ctx.cache.npoints;
  ++path.count;
}

void nvg__closePath (NVGContext ctx) nothrow @trusted @nogc {
  NVGpath* path = nvg__lastPath(ctx);
  if (path is null) return;
  path.closed = true;
}

void nvg__pathWinding (NVGContext ctx, NVGWinding winding) nothrow @trusted @nogc {
  NVGpath* path = nvg__lastPath(ctx);
  if (path is null) return;
  path.winding = winding;
}

float nvg__getAverageScale() (in auto ref NVGMatrix t) nothrow @trusted @nogc {
  immutable float sx = nvg__sqrtf(t.mat.ptr[0]*t.mat.ptr[0]+t.mat.ptr[2]*t.mat.ptr[2]);
  immutable float sy = nvg__sqrtf(t.mat.ptr[1]*t.mat.ptr[1]+t.mat.ptr[3]*t.mat.ptr[3]);
  return (sx+sy)*0.5f;
}

NVGvertex* nvg__allocTempVerts (NVGContext ctx, int nverts) nothrow @trusted @nogc {
  if (nverts > ctx.cache.cverts) {
    int cverts = (nverts+0xff)&~0xff; // Round up to prevent allocations when things change just slightly.
    NVGvertex* verts = cast(NVGvertex*)realloc(ctx.cache.verts, NVGvertex.sizeof*cverts);
    if (verts is null) return null;
    ctx.cache.verts = verts;
    ctx.cache.cverts = cverts;
  }

  return ctx.cache.verts;
}

float nvg__triarea2 (float ax, float ay, float bx, float by, float cx, float cy) pure nothrow @safe @nogc {
  immutable float abx = bx-ax;
  immutable float aby = by-ay;
  immutable float acx = cx-ax;
  immutable float acy = cy-ay;
  return acx*aby-abx*acy;
}

float nvg__polyArea (NVGpoint* pts, int npts) nothrow @trusted @nogc {
  float area = 0;
  foreach (int i; 2..npts) {
    NVGpoint* a = &pts[0];
    NVGpoint* b = &pts[i-1];
    NVGpoint* c = &pts[i];
    area += nvg__triarea2(a.x, a.y, b.x, b.y, c.x, c.y);
  }
  return area*0.5f;
}

void nvg__polyReverse (NVGpoint* pts, int npts) nothrow @trusted @nogc {
  NVGpoint tmp = void;
  int i = 0, j = npts-1;
  while (i < j) {
    tmp = pts[i];
    pts[i] = pts[j];
    pts[j] = tmp;
    ++i;
    --j;
  }
}

void nvg__vset (NVGvertex* vtx, float x, float y, float u, float v) nothrow @trusted @nogc {
  vtx.x = x;
  vtx.y = y;
  vtx.u = u;
  vtx.v = v;
}

void nvg__tesselateBezier (NVGContext ctx, in float x1, in float y1, in float x2, in float y2, in float x3, in float y3, in float x4, in float y4, in int level, in int type) nothrow @trusted @nogc {
  if (level > 10) return;

  // check for collinear points, and use AFD tesselator on such curves (it is WAY faster for this case)
  /*
  if (level == 0 && ctx.tesselatortype == NVGTesselation.Combined) {
    static bool collinear (in float v0x, in float v0y, in float v1x, in float v1y, in float v2x, in float v2y) nothrow @trusted @nogc {
      immutable float cz = (v1x-v0x)*(v2y-v0y)-(v2x-v0x)*(v1y-v0y);
      return (nvg__absf(cz*cz) <= 0.01f); // arbitrary number, seems to work ok with NanoSVG output
    }
    if (collinear(x1, y1, x2, y2, x3, y3) && collinear(x2, y2, x3, y3, x3, y4)) {
      //{ import core.stdc.stdio; printf("AFD fallback!\n"); }
      ctx.nvg__tesselateBezierAFD(x1, y1, x2, y2, x3, y3, x4, y4, type);
      return;
    }
  }
  */

  immutable float x12 = (x1+x2)*0.5f;
  immutable float y12 = (y1+y2)*0.5f;
  immutable float x23 = (x2+x3)*0.5f;
  immutable float y23 = (y2+y3)*0.5f;
  immutable float x34 = (x3+x4)*0.5f;
  immutable float y34 = (y3+y4)*0.5f;
  immutable float x123 = (x12+x23)*0.5f;
  immutable float y123 = (y12+y23)*0.5f;

  immutable float dx = x4-x1;
  immutable float dy = y4-y1;
  immutable float d2 = nvg__absf(((x2-x4)*dy-(y2-y4)*dx));
  immutable float d3 = nvg__absf(((x3-x4)*dy-(y3-y4)*dx));

  if ((d2+d3)*(d2+d3) < ctx.tessTol*(dx*dx+dy*dy)) {
    nvg__addPoint(ctx, x4, y4, type);
    return;
  }

  immutable float x234 = (x23+x34)*0.5f;
  immutable float y234 = (y23+y34)*0.5f;
  immutable float x1234 = (x123+x234)*0.5f;
  immutable float y1234 = (y123+y234)*0.5f;


  // "taxicab" / "manhattan" check for flat curves
  if (nvg__absf(x1+x3-x2-x2)+nvg__absf(y1+y3-y2-y2)+nvg__absf(x2+x4-x3-x3)+nvg__absf(y2+y4-y3-y3) < ctx.tessTol/4) {
    nvg__addPoint(ctx, x1234, y1234, type);
    return;
  }

  nvg__tesselateBezier(ctx, x1, y1, x12, y12, x123, y123, x1234, y1234, level+1, 0);
  nvg__tesselateBezier(ctx, x1234, y1234, x234, y234, x34, y34, x4, y4, level+1, type);
}

// based on the ideas and code of Maxim Shemanarev. Rest in Peace, bro!
// see http://www.antigrain.com/research/adaptive_bezier/index.html
void nvg__tesselateBezierMcSeem (NVGContext ctx, in float x1, in float y1, in float x2, in float y2, in float x3, in float y3, in float x4, in float y4, in int level, in int type) nothrow @trusted @nogc {
  enum CollinearEPS = 0.00000001f; // 0.00001f;
  enum AngleTolEPS = 0.01f;

  static float distSquared (in float x1, in float y1, in float x2, in float y2) pure nothrow @safe @nogc {
    pragma(inline, true);
    immutable float dx = x2-x1;
    immutable float dy = y2-y1;
    return dx*dx+dy*dy;
  }

  if (level == 0) {
    nvg__addPoint(ctx, x1, y1, 0);
    nvg__tesselateBezierMcSeem(ctx, x1, y1, x2, y2, x3, y3, x4, y4, 1, type);
    nvg__addPoint(ctx, x4, y4, type);
    return;
  }

  if (level >= 32) return; // recurse limit; practically, it should be never reached, but...

  // calculate all the mid-points of the line segments
  immutable float x12 = (x1+x2)*0.5f;
  immutable float y12 = (y1+y2)*0.5f;
  immutable float x23 = (x2+x3)*0.5f;
  immutable float y23 = (y2+y3)*0.5f;
  immutable float x34 = (x3+x4)*0.5f;
  immutable float y34 = (y3+y4)*0.5f;
  immutable float x123 = (x12+x23)*0.5f;
  immutable float y123 = (y12+y23)*0.5f;
  immutable float x234 = (x23+x34)*0.5f;
  immutable float y234 = (y23+y34)*0.5f;
  immutable float x1234 = (x123+x234)*0.5f;
  immutable float y1234 = (y123+y234)*0.5f;

  // try to approximate the full cubic curve by a single straight line
  immutable float dx = x4-x1;
  immutable float dy = y4-y1;

  float d2 = nvg__absf(((x2-x4)*dy-(y2-y4)*dx));
  float d3 = nvg__absf(((x3-x4)*dy-(y3-y4)*dx));
  //immutable float da1, da2, k;

  final switch ((cast(int)(d2 > CollinearEPS)<<1)+cast(int)(d3 > CollinearEPS)) {
    case 0:
      // all collinear or p1 == p4
      float k = dx*dx+dy*dy;
      if (k == 0) {
        d2 = distSquared(x1, y1, x2, y2);
        d3 = distSquared(x4, y4, x3, y3);
      } else {
        k = 1.0f/k;
        float da1 = x2-x1;
        float da2 = y2-y1;
        d2 = k*(da1*dx+da2*dy);
        da1 = x3-x1;
        da2 = y3-y1;
        d3 = k*(da1*dx+da2*dy);
        if (d2 > 0 && d2 < 1 && d3 > 0 && d3 < 1) {
          // Simple collinear case, 1---2---3---4
          // We can leave just two endpoints
          return;
        }
             if (d2 <= 0) d2 = distSquared(x2, y2, x1, y1);
        else if (d2 >= 1) d2 = distSquared(x2, y2, x4, y4);
        else d2 = distSquared(x2, y2, x1+d2*dx, y1+d2*dy);

             if (d3 <= 0) d3 = distSquared(x3, y3, x1, y1);
        else if (d3 >= 1) d3 = distSquared(x3, y3, x4, y4);
        else d3 = distSquared(x3, y3, x1+d3*dx, y1+d3*dy);
      }
      if (d2 > d3) {
        if (d2 < ctx.tessTol) {
          nvg__addPoint(ctx, x2, y2, type);
          return;
        }
      } if (d3 < ctx.tessTol) {
        nvg__addPoint(ctx, x3, y3, type);
        return;
      }
      break;
    case 1:
      // p1,p2,p4 are collinear, p3 is significant
      if (d3*d3 <= ctx.tessTol*(dx*dx+dy*dy)) {
        if (ctx.angleTol < AngleTolEPS) {
          nvg__addPoint(ctx, x23, y23, type);
          return;
        } else {
          // angle condition
          float da1 = nvg__absf(nvg__atan2f(y4-y3, x4-x3)-nvg__atan2f(y3-y2, x3-x2));
          if (da1 >= NVG_PI) da1 = 2*NVG_PI-da1;
          if (da1 < ctx.angleTol) {
            nvg__addPoint(ctx, x2, y2, type);
            nvg__addPoint(ctx, x3, y3, type);
            return;
          }
          if (ctx.cuspLimit != 0.0) {
            if (da1 > ctx.cuspLimit) {
              nvg__addPoint(ctx, x3, y3, type);
              return;
            }
          }
        }
      }
      break;
    case 2:
      // p1,p3,p4 are collinear, p2 is significant
      if (d2*d2 <= ctx.tessTol*(dx*dx+dy*dy)) {
        if (ctx.angleTol < AngleTolEPS) {
          nvg__addPoint(ctx, x23, y23, type);
          return;
        } else {
          // angle condition
          float da1 = nvg__absf(nvg__atan2f(y3-y2, x3-x2)-nvg__atan2f(y2-y1, x2-x1));
          if (da1 >= NVG_PI) da1 = 2*NVG_PI-da1;
          if (da1 < ctx.angleTol) {
            nvg__addPoint(ctx, x2, y2, type);
            nvg__addPoint(ctx, x3, y3, type);
            return;
          }
          if (ctx.cuspLimit != 0.0) {
            if (da1 > ctx.cuspLimit) {
              nvg__addPoint(ctx, x2, y2, type);
              return;
            }
          }
        }
      }
      break;
    case 3:
      // regular case
      if ((d2+d3)*(d2+d3) <= ctx.tessTol*(dx*dx+dy*dy)) {
        // if the curvature doesn't exceed the distance tolerance value, we tend to finish subdivisions
        if (ctx.angleTol < AngleTolEPS) {
          nvg__addPoint(ctx, x23, y23, type);
          return;
        } else {
          // angle and cusp condition
          immutable float k = nvg__atan2f(y3-y2, x3-x2);
          float da1 = nvg__absf(k-nvg__atan2f(y2-y1, x2-x1));
          float da2 = nvg__absf(nvg__atan2f(y4-y3, x4-x3)-k);
          if (da1 >= NVG_PI) da1 = 2*NVG_PI-da1;
          if (da2 >= NVG_PI) da2 = 2*NVG_PI-da2;
          if (da1+da2 < ctx.angleTol) {
            // finally we can stop the recursion
            nvg__addPoint(ctx, x23, y23, type);
            return;
          }
          if (ctx.cuspLimit != 0.0) {
            if (da1 > ctx.cuspLimit) {
              nvg__addPoint(ctx, x2, y2, type);
              return;
            }
            if (da2 > ctx.cuspLimit) {
              nvg__addPoint(ctx, x3, y3, type);
              return;
            }
          }
        }
      }
      break;
  }

  // continue subdivision
  nvg__tesselateBezierMcSeem(ctx, x1, y1, x12, y12, x123, y123, x1234, y1234, level+1, 0);
  nvg__tesselateBezierMcSeem(ctx, x1234, y1234, x234, y234, x34, y34, x4, y4, level+1, type);
}


// Adaptive forward differencing for bezier tesselation.
// See Lien, Sheue-Ling, Michael Shantz, and Vaughan Pratt.
// "Adaptive forward differencing for rendering curves and surfaces."
// ACM SIGGRAPH Computer Graphics. Vol. 21. No. 4. ACM, 1987.
// original code by Taylor Holliday <taylor@audulus.com>
void nvg__tesselateBezierAFD (NVGContext ctx, in float x1, in float y1, in float x2, in float y2, in float x3, in float y3, in float x4, in float y4, in int type) nothrow @trusted @nogc {
  enum AFD_ONE = (1<<10);

  // power basis
  immutable float ax = -x1+3*x2-3*x3+x4;
  immutable float ay = -y1+3*y2-3*y3+y4;
  immutable float bx = 3*x1-6*x2+3*x3;
  immutable float by = 3*y1-6*y2+3*y3;
  immutable float cx = -3*x1+3*x2;
  immutable float cy = -3*y1+3*y2;

  // Transform to forward difference basis (stepsize 1)
  float px = x1;
  float py = y1;
  float dx = ax+bx+cx;
  float dy = ay+by+cy;
  float ddx = 6*ax+2*bx;
  float ddy = 6*ay+2*by;
  float dddx = 6*ax;
  float dddy = 6*ay;

  //printf("dx: %f, dy: %f\n", dx, dy);
  //printf("ddx: %f, ddy: %f\n", ddx, ddy);
  //printf("dddx: %f, dddy: %f\n", dddx, dddy);

  int t = 0;
  int dt = AFD_ONE;

  immutable float tol = ctx.tessTol*4;

  while (t < AFD_ONE) {
    // Flatness measure.
    float d = ddx*ddx+ddy*ddy+dddx*dddx+dddy*dddy;

    // printf("d: %f, th: %f\n", d, th);

    // Go to higher resolution if we're moving a lot or overshooting the end.
    while ((d > tol && dt > 1) || (t+dt > AFD_ONE)) {
      // printf("up\n");

      // Apply L to the curve. Increase curve resolution.
      dx = 0.5f*dx-(1.0f/8.0f)*ddx+(1.0f/16.0f)*dddx;
      dy = 0.5f*dy-(1.0f/8.0f)*ddy+(1.0f/16.0f)*dddy;
      ddx = (1.0f/4.0f)*ddx-(1.0f/8.0f)*dddx;
      ddy = (1.0f/4.0f)*ddy-(1.0f/8.0f)*dddy;
      dddx = (1.0f/8.0f)*dddx;
      dddy = (1.0f/8.0f)*dddy;

      // Half the stepsize.
      dt >>= 1;

      // Recompute d
      d = ddx*ddx+ddy*ddy+dddx*dddx+dddy*dddy;
    }

    // Go to lower resolution if we're really flat
    // and we aren't going to overshoot the end.
    // XXX: tol/32 is just a guess for when we are too flat.
    while ((d > 0 && d < tol/32.0f && dt < AFD_ONE) && (t+2*dt <= AFD_ONE)) {
      // printf("down\n");

      // Apply L^(-1) to the curve. Decrease curve resolution.
      dx = 2*dx+ddx;
      dy = 2*dy+ddy;
      ddx = 4*ddx+4*dddx;
      ddy = 4*ddy+4*dddy;
      dddx = 8*dddx;
      dddy = 8*dddy;

      // Double the stepsize.
      dt <<= 1;

      // Recompute d
      d = ddx*ddx+ddy*ddy+dddx*dddx+dddy*dddy;
    }

    // Forward differencing.
    px += dx;
    py += dy;
    dx += ddx;
    dy += ddy;
    ddx += dddx;
    ddy += dddy;

    // Output a point.
    nvg__addPoint(ctx, px, py, (t > 0 ? type : 0));

    // Advance along the curve.
    t += dt;

    // Ensure we don't overshoot.
    assert(t <= AFD_ONE);
  }
}

version(nanovg_bench_flatten) import iv.timer : Timer;

void nvg__flattenPaths (NVGContext ctx) nothrow @trusted @nogc {
  version(nanovg_bench_flatten) {
    Timer timer;
    char[128] tmbuf;
    int bzcount;
  }
  NVGpathCache* cache = ctx.cache;

  if (cache.npaths > 0) return;

  // flatten
  version(nanovg_bench_flatten) timer.restart();
  int i = 0;
  while (i < ctx.ncommands) {
    final switch (cast(Command)ctx.commands[i]) {
      case Command.MoveTo:
        //assert(i+3 <= ctx.ncommands);
        nvg__addPath(ctx);
        const p = &ctx.commands[i+1];
        nvg__addPoint(ctx, p[0], p[1], PointFlag.Corner);
        i += 3;
        break;
      case Command.LineTo:
        //assert(i+3 <= ctx.ncommands);
        const p = &ctx.commands[i+1];
        nvg__addPoint(ctx, p[0], p[1], PointFlag.Corner);
        i += 3;
        break;
      case Command.BezierTo:
        //assert(i+7 <= ctx.ncommands);
        const last = nvg__lastPoint(ctx);
        if (last !is null) {
          const cp1 = &ctx.commands[i+1];
          const cp2 = &ctx.commands[i+3];
          const p = &ctx.commands[i+5];
          if (ctx.tesselatortype == NVGTesselation.DeCasteljau) {
            nvg__tesselateBezier(ctx, last.x, last.y, cp1[0], cp1[1], cp2[0], cp2[1], p[0], p[1], 0, PointFlag.Corner);
          } else if (ctx.tesselatortype == NVGTesselation.DeCasteljauMcSeem) {
            nvg__tesselateBezierMcSeem(ctx, last.x, last.y, cp1[0], cp1[1], cp2[0], cp2[1], p[0], p[1], 0, PointFlag.Corner);
          } else {
            nvg__tesselateBezierAFD(ctx, last.x, last.y, cp1[0], cp1[1], cp2[0], cp2[1], p[0], p[1], PointFlag.Corner);
          }
          version(nanovg_bench_flatten) ++bzcount;
        }
        i += 7;
        break;
      case Command.Close:
        //assert(i+1 <= ctx.ncommands);
        nvg__closePath(ctx);
        i += 1;
        break;
      case Command.Winding:
        //assert(i+2 <= ctx.ncommands);
        nvg__pathWinding(ctx, cast(NVGWinding)ctx.commands[i+1]);
        i += 2;
        break;
    }
  }
  version(nanovg_bench_flatten) {{
    timer.stop();
    auto xb = timer.toBuffer(tmbuf[]);
    import core.stdc.stdio : printf;
    printf("flattening time: [%.*s] (%d beziers)\n", cast(uint)xb.length, xb.ptr, bzcount);
  }}

  cache.bounds.ptr[0] = cache.bounds.ptr[1] = 1e6f;
  cache.bounds.ptr[2] = cache.bounds.ptr[3] = -1e6f;

  // calculate the direction and length of line segments
  version(nanovg_bench_flatten) timer.restart();
  foreach (int j; 0..cache.npaths) {
    NVGpath* path = &cache.paths[j];
    NVGpoint* pts = &cache.points[path.first];

    // if the first and last points are the same, remove the last, mark as closed path
    NVGpoint* p0 = &pts[path.count-1];
    NVGpoint* p1 = &pts[0];
    if (nvg__ptEquals(p0.x, p0.y, p1.x, p1.y, ctx.distTol)) {
      --path.count;
      p0 = &pts[path.count-1];
      path.closed = true;
    }

    // enforce winding
    if (path.count > 2) {
      immutable float area = nvg__polyArea(pts, path.count);
      if (path.winding == NVGWinding.CCW && area < 0.0f) nvg__polyReverse(pts, path.count);
      if (path.winding == NVGWinding.CW && area > 0.0f) nvg__polyReverse(pts, path.count);
    }

    foreach (immutable _; 0..path.count) {
      // calculate segment direction and length
      p0.dx = p1.x-p0.x;
      p0.dy = p1.y-p0.y;
      p0.len = nvg__normalize(&p0.dx, &p0.dy);
      // update bounds
      cache.bounds.ptr[0] = nvg__min(cache.bounds.ptr[0], p0.x);
      cache.bounds.ptr[1] = nvg__min(cache.bounds.ptr[1], p0.y);
      cache.bounds.ptr[2] = nvg__max(cache.bounds.ptr[2], p0.x);
      cache.bounds.ptr[3] = nvg__max(cache.bounds.ptr[3], p0.y);
      // advance
      p0 = p1++;
    }
  }
  version(nanovg_bench_flatten) {{
    timer.stop();
    auto xb = timer.toBuffer(tmbuf[]);
    import core.stdc.stdio : printf;
    printf("segment calculation time: [%.*s]\n", cast(uint)xb.length, xb.ptr);
  }}
}

int nvg__curveDivs (float r, float arc, float tol) nothrow @trusted @nogc {
  immutable float da = nvg__acosf(r/(r+tol))*2.0f;
  return nvg__max(2, cast(int)nvg__ceilf(arc/da));
}

void nvg__chooseBevel (int bevel, NVGpoint* p0, NVGpoint* p1, float w, float* x0, float* y0, float* x1, float* y1) nothrow @trusted @nogc {
  if (bevel) {
    *x0 = p1.x+p0.dy*w;
    *y0 = p1.y-p0.dx*w;
    *x1 = p1.x+p1.dy*w;
    *y1 = p1.y-p1.dx*w;
  } else {
    *x0 = p1.x+p1.dmx*w;
    *y0 = p1.y+p1.dmy*w;
    *x1 = p1.x+p1.dmx*w;
    *y1 = p1.y+p1.dmy*w;
  }
}

NVGvertex* nvg__roundJoin (NVGvertex* dst, NVGpoint* p0, NVGpoint* p1, float lw, float rw, float lu, float ru, int ncap, float fringe) nothrow @trusted @nogc {
  float dlx0 = p0.dy;
  float dly0 = -p0.dx;
  float dlx1 = p1.dy;
  float dly1 = -p1.dx;
  //NVG_NOTUSED(fringe);

  if (p1.flags&PointFlag.Left) {
    float lx0 = void, ly0 = void, lx1 = void, ly1 = void;
    nvg__chooseBevel(p1.flags&PointFlag.InnerBevelPR, p0, p1, lw, &lx0, &ly0, &lx1, &ly1);
    immutable float a0 = nvg__atan2f(-dly0, -dlx0);
    float a1 = nvg__atan2f(-dly1, -dlx1);
    if (a1 > a0) a1 -= NVG_PI*2;

    nvg__vset(dst, lx0, ly0, lu, 1); ++dst;
    nvg__vset(dst, p1.x-dlx0*rw, p1.y-dly0*rw, ru, 1); ++dst;

    int n = nvg__clamp(cast(int)nvg__ceilf(((a0-a1)/NVG_PI)*ncap), 2, ncap);
    for (int i = 0; i < n; ++i) {
      float u = i/cast(float)(n-1);
      float a = a0+u*(a1-a0);
      float rx = p1.x+nvg__cosf(a)*rw;
      float ry = p1.y+nvg__sinf(a)*rw;
      nvg__vset(dst, p1.x, p1.y, 0.5f, 1); ++dst;
      nvg__vset(dst, rx, ry, ru, 1); ++dst;
    }

    nvg__vset(dst, lx1, ly1, lu, 1); ++dst;
    nvg__vset(dst, p1.x-dlx1*rw, p1.y-dly1*rw, ru, 1); ++dst;

  } else {
    float rx0 = void, ry0 = void, rx1 = void, ry1 = void;
    nvg__chooseBevel(p1.flags&PointFlag.InnerBevelPR, p0, p1, -rw, &rx0, &ry0, &rx1, &ry1);
    immutable float a0 = nvg__atan2f(dly0, dlx0);
    float a1 = nvg__atan2f(dly1, dlx1);
    if (a1 < a0) a1 += NVG_PI*2;

    nvg__vset(dst, p1.x+dlx0*rw, p1.y+dly0*rw, lu, 1); ++dst;
    nvg__vset(dst, rx0, ry0, ru, 1); ++dst;

    int n = nvg__clamp(cast(int)nvg__ceilf(((a1-a0)/NVG_PI)*ncap), 2, ncap);
    for (int i = 0; i < n; i++) {
      float u = i/cast(float)(n-1);
      float a = a0+u*(a1-a0);
      float lx = p1.x+nvg__cosf(a)*lw;
      float ly = p1.y+nvg__sinf(a)*lw;
      nvg__vset(dst, lx, ly, lu, 1); ++dst;
      nvg__vset(dst, p1.x, p1.y, 0.5f, 1); ++dst;
    }

    nvg__vset(dst, p1.x+dlx1*rw, p1.y+dly1*rw, lu, 1); ++dst;
    nvg__vset(dst, rx1, ry1, ru, 1); ++dst;

  }
  return dst;
}

NVGvertex* nvg__bevelJoin (NVGvertex* dst, NVGpoint* p0, NVGpoint* p1, float lw, float rw, float lu, float ru, float fringe) nothrow @trusted @nogc {
  float rx0, ry0, rx1, ry1;
  float lx0, ly0, lx1, ly1;
  float dlx0 = p0.dy;
  float dly0 = -p0.dx;
  float dlx1 = p1.dy;
  float dly1 = -p1.dx;
  //NVG_NOTUSED(fringe);

  if (p1.flags&PointFlag.Left) {
    nvg__chooseBevel(p1.flags&PointFlag.InnerBevelPR, p0, p1, lw, &lx0, &ly0, &lx1, &ly1);

    nvg__vset(dst, lx0, ly0, lu, 1); ++dst;
    nvg__vset(dst, p1.x-dlx0*rw, p1.y-dly0*rw, ru, 1); ++dst;

    if (p1.flags&PointFlag.Bevel) {
      nvg__vset(dst, lx0, ly0, lu, 1); ++dst;
      nvg__vset(dst, p1.x-dlx0*rw, p1.y-dly0*rw, ru, 1); ++dst;

      nvg__vset(dst, lx1, ly1, lu, 1); ++dst;
      nvg__vset(dst, p1.x-dlx1*rw, p1.y-dly1*rw, ru, 1); ++dst;
    } else {
      rx0 = p1.x-p1.dmx*rw;
      ry0 = p1.y-p1.dmy*rw;

      nvg__vset(dst, p1.x, p1.y, 0.5f, 1); ++dst;
      nvg__vset(dst, p1.x-dlx0*rw, p1.y-dly0*rw, ru, 1); ++dst;

      nvg__vset(dst, rx0, ry0, ru, 1); ++dst;
      nvg__vset(dst, rx0, ry0, ru, 1); ++dst;

      nvg__vset(dst, p1.x, p1.y, 0.5f, 1); ++dst;
      nvg__vset(dst, p1.x-dlx1*rw, p1.y-dly1*rw, ru, 1); ++dst;
    }

    nvg__vset(dst, lx1, ly1, lu, 1); ++dst;
    nvg__vset(dst, p1.x-dlx1*rw, p1.y-dly1*rw, ru, 1); ++dst;

  } else {
    nvg__chooseBevel(p1.flags&PointFlag.InnerBevelPR, p0, p1, -rw, &rx0, &ry0, &rx1, &ry1);

    nvg__vset(dst, p1.x+dlx0*lw, p1.y+dly0*lw, lu, 1); ++dst;
    nvg__vset(dst, rx0, ry0, ru, 1); ++dst;

    if (p1.flags&PointFlag.Bevel) {
      nvg__vset(dst, p1.x+dlx0*lw, p1.y+dly0*lw, lu, 1); ++dst;
      nvg__vset(dst, rx0, ry0, ru, 1); ++dst;

      nvg__vset(dst, p1.x+dlx1*lw, p1.y+dly1*lw, lu, 1); ++dst;
      nvg__vset(dst, rx1, ry1, ru, 1); ++dst;
    } else {
      lx0 = p1.x+p1.dmx*lw;
      ly0 = p1.y+p1.dmy*lw;

      nvg__vset(dst, p1.x+dlx0*lw, p1.y+dly0*lw, lu, 1); ++dst;
      nvg__vset(dst, p1.x, p1.y, 0.5f, 1); ++dst;

      nvg__vset(dst, lx0, ly0, lu, 1); ++dst;
      nvg__vset(dst, lx0, ly0, lu, 1); ++dst;

      nvg__vset(dst, p1.x+dlx1*lw, p1.y+dly1*lw, lu, 1); ++dst;
      nvg__vset(dst, p1.x, p1.y, 0.5f, 1); ++dst;
    }

    nvg__vset(dst, p1.x+dlx1*lw, p1.y+dly1*lw, lu, 1); ++dst;
    nvg__vset(dst, rx1, ry1, ru, 1); ++dst;
  }

  return dst;
}

NVGvertex* nvg__buttCapStart (NVGvertex* dst, NVGpoint* p, float dx, float dy, float w, float d, float aa) nothrow @trusted @nogc {
  immutable float px = p.x-dx*d;
  immutable float py = p.y-dy*d;
  immutable float dlx = dy;
  immutable float dly = -dx;
  nvg__vset(dst, px+dlx*w-dx*aa, py+dly*w-dy*aa, 0, 0); ++dst;
  nvg__vset(dst, px-dlx*w-dx*aa, py-dly*w-dy*aa, 1, 0); ++dst;
  nvg__vset(dst, px+dlx*w, py+dly*w, 0, 1); ++dst;
  nvg__vset(dst, px-dlx*w, py-dly*w, 1, 1); ++dst;
  return dst;
}

NVGvertex* nvg__buttCapEnd (NVGvertex* dst, NVGpoint* p, float dx, float dy, float w, float d, float aa) nothrow @trusted @nogc {
  immutable float px = p.x+dx*d;
  immutable float py = p.y+dy*d;
  immutable float dlx = dy;
  immutable float dly = -dx;
  nvg__vset(dst, px+dlx*w, py+dly*w, 0, 1); ++dst;
  nvg__vset(dst, px-dlx*w, py-dly*w, 1, 1); ++dst;
  nvg__vset(dst, px+dlx*w+dx*aa, py+dly*w+dy*aa, 0, 0); ++dst;
  nvg__vset(dst, px-dlx*w+dx*aa, py-dly*w+dy*aa, 1, 0); ++dst;
  return dst;
}

NVGvertex* nvg__roundCapStart (NVGvertex* dst, NVGpoint* p, float dx, float dy, float w, int ncap, float aa) nothrow @trusted @nogc {
  immutable float px = p.x;
  immutable float py = p.y;
  immutable float dlx = dy;
  immutable float dly = -dx;
  //NVG_NOTUSED(aa);
  immutable float ncpf = cast(float)(ncap-1);
  foreach (int i; 0..ncap) {
    float a = i/*/cast(float)(ncap-1)*//ncpf*NVG_PI;
    float ax = nvg__cosf(a)*w, ay = nvg__sinf(a)*w;
    nvg__vset(dst, px-dlx*ax-dx*ay, py-dly*ax-dy*ay, 0, 1); ++dst;
    nvg__vset(dst, px, py, 0.5f, 1); ++dst;
  }
  nvg__vset(dst, px+dlx*w, py+dly*w, 0, 1); ++dst;
  nvg__vset(dst, px-dlx*w, py-dly*w, 1, 1); ++dst;
  return dst;
}

NVGvertex* nvg__roundCapEnd (NVGvertex* dst, NVGpoint* p, float dx, float dy, float w, int ncap, float aa) nothrow @trusted @nogc {
  immutable float px = p.x;
  immutable float py = p.y;
  immutable float dlx = dy;
  immutable float dly = -dx;
  //NVG_NOTUSED(aa);
  nvg__vset(dst, px+dlx*w, py+dly*w, 0, 1); ++dst;
  nvg__vset(dst, px-dlx*w, py-dly*w, 1, 1); ++dst;
  immutable float ncpf = cast(float)(ncap-1);
  foreach (int i; 0..ncap) {
    float a = i/*cast(float)(ncap-1)*//ncpf*NVG_PI;
    float ax = nvg__cosf(a)*w, ay = nvg__sinf(a)*w;
    nvg__vset(dst, px, py, 0.5f, 1); ++dst;
    nvg__vset(dst, px-dlx*ax+dx*ay, py-dly*ax+dy*ay, 0, 1); ++dst;
  }
  return dst;
}

void nvg__calculateJoins (NVGContext ctx, float w, int lineJoin, float miterLimit) nothrow @trusted @nogc {
  NVGpathCache* cache = ctx.cache;
  float iw = 0.0f;

  if (w > 0.0f) iw = 1.0f/w;

  // Calculate which joins needs extra vertices to append, and gather vertex count.
  foreach (int i; 0..cache.npaths) {
    NVGpath* path = &cache.paths[i];
    NVGpoint* pts = &cache.points[path.first];
    NVGpoint* p0 = &pts[path.count-1];
    NVGpoint* p1 = &pts[0];
    int nleft = 0;

    path.nbevel = 0;

    foreach (int j; 0..path.count) {
      //float dlx0, dly0, dlx1, dly1, dmr2, cross, limit;
      immutable float dlx0 = p0.dy;
      immutable float dly0 = -p0.dx;
      immutable float dlx1 = p1.dy;
      immutable float dly1 = -p1.dx;
      // Calculate extrusions
      p1.dmx = (dlx0+dlx1)*0.5f;
      p1.dmy = (dly0+dly1)*0.5f;
      immutable float dmr2 = p1.dmx*p1.dmx+p1.dmy*p1.dmy;
      if (dmr2 > 0.000001f) {
        float scale = 1.0f/dmr2;
        if (scale > 600.0f) scale = 600.0f;
        p1.dmx *= scale;
        p1.dmy *= scale;
      }

      // Clear flags, but keep the corner.
      p1.flags = (p1.flags&PointFlag.Corner) ? PointFlag.Corner : 0;

      // Keep track of left turns.
      immutable float cross = p1.dx*p0.dy-p0.dx*p1.dy;
      if (cross > 0.0f) {
        nleft++;
        p1.flags |= PointFlag.Left;
      }

      // Calculate if we should use bevel or miter for inner join.
      immutable float limit = nvg__max(1.01f, nvg__min(p0.len, p1.len)*iw);
      if ((dmr2*limit*limit) < 1.0f) p1.flags |= PointFlag.InnerBevelPR;

      // Check to see if the corner needs to be beveled.
      if (p1.flags&PointFlag.Corner) {
        if ((dmr2*miterLimit*miterLimit) < 1.0f || lineJoin == NVGLineCap.Bevel || lineJoin == NVGLineCap.Round) {
          p1.flags |= PointFlag.Bevel;
        }
      }

      if ((p1.flags&(PointFlag.Bevel|PointFlag.InnerBevelPR)) != 0) path.nbevel++;

      p0 = p1++;
    }

    path.convex = (nleft == path.count) ? 1 : 0;
  }
}

void nvg__expandStroke (NVGContext ctx, float w, int lineCap, int lineJoin, float miterLimit) nothrow @trusted @nogc {
  NVGpathCache* cache = ctx.cache;
  immutable float aa = ctx.fringeWidth;
  int ncap = nvg__curveDivs(w, NVG_PI, ctx.tessTol); // Calculate divisions per half circle.

  nvg__calculateJoins(ctx, w, lineJoin, miterLimit);

  // Calculate max vertex usage.
  int cverts = 0;
  foreach (int i; 0..cache.npaths) {
    NVGpath* path = &cache.paths[i];
    immutable bool loop = path.closed;
    if (lineJoin == NVGLineCap.Round) {
      cverts += (path.count+path.nbevel*(ncap+2)+1)*2; // plus one for loop
    } else {
      cverts += (path.count+path.nbevel*5+1)*2; // plus one for loop
    }
    if (!loop) {
      // space for caps
      if (lineCap == NVGLineCap.Round) {
        cverts += (ncap*2+2)*2;
      } else {
        cverts += (3+3)*2;
      }
    }
  }

  NVGvertex* verts = nvg__allocTempVerts(ctx, cverts);
  if (verts is null) return;

  foreach (int i; 0..cache.npaths) {
    NVGpath* path = &cache.paths[i];
    NVGpoint* pts = &cache.points[path.first];
    NVGpoint* p0;
    NVGpoint* p1;
    int s, e;

    path.fill = null;
    path.nfill = 0;

    // Calculate fringe or stroke
    immutable bool loop = path.closed;
    NVGvertex* dst = verts;
    path.stroke = dst;

    if (loop) {
      // Looping
      p0 = &pts[path.count-1];
      p1 = &pts[0];
      s = 0;
      e = path.count;
    } else {
      // Add cap
      p0 = &pts[0];
      p1 = &pts[1];
      s = 1;
      e = path.count-1;
    }

    if (!loop) {
      // Add cap
      float dx = p1.x-p0.x;
      float dy = p1.y-p0.y;
      nvg__normalize(&dx, &dy);
           if (lineCap == NVGLineCap.Butt) dst = nvg__buttCapStart(dst, p0, dx, dy, w, -aa*0.5f, aa);
      else if (lineCap == NVGLineCap.Butt || lineCap == NVGLineCap.Square) dst = nvg__buttCapStart(dst, p0, dx, dy, w, w-aa, aa);
      else if (lineCap == NVGLineCap.Round) dst = nvg__roundCapStart(dst, p0, dx, dy, w, ncap, aa);
    }

    foreach (int j; s..e) {
      if ((p1.flags&(PointFlag.Bevel|PointFlag.InnerBevelPR)) != 0) {
        if (lineJoin == NVGLineCap.Round) {
          dst = nvg__roundJoin(dst, p0, p1, w, w, 0, 1, ncap, aa);
        } else {
          dst = nvg__bevelJoin(dst, p0, p1, w, w, 0, 1, aa);
        }
      } else {
        nvg__vset(dst, p1.x+(p1.dmx*w), p1.y+(p1.dmy*w), 0, 1); ++dst;
        nvg__vset(dst, p1.x-(p1.dmx*w), p1.y-(p1.dmy*w), 1, 1); ++dst;
      }
      p0 = p1++;
    }

    if (loop) {
      // Loop it
      nvg__vset(dst, verts[0].x, verts[0].y, 0, 1); ++dst;
      nvg__vset(dst, verts[1].x, verts[1].y, 1, 1); ++dst;
    } else {
      // Add cap
      float dx = p1.x-p0.x;
      float dy = p1.y-p0.y;
      nvg__normalize(&dx, &dy);
           if (lineCap == NVGLineCap.Butt) dst = nvg__buttCapEnd(dst, p1, dx, dy, w, -aa*0.5f, aa);
      else if (lineCap == NVGLineCap.Butt || lineCap == NVGLineCap.Square) dst = nvg__buttCapEnd(dst, p1, dx, dy, w, w-aa, aa);
      else if (lineCap == NVGLineCap.Round) dst = nvg__roundCapEnd(dst, p1, dx, dy, w, ncap, aa);
    }

    path.nstroke = cast(int)(dst-verts);

    verts = dst;
  }
}

void nvg__expandFill (NVGContext ctx, float w, int lineJoin, float miterLimit) nothrow @trusted @nogc {
  NVGpathCache* cache = ctx.cache;
  immutable float aa = ctx.fringeWidth;
  bool fringe = (w > 0.0f);

  nvg__calculateJoins(ctx, w, lineJoin, miterLimit);

  // Calculate max vertex usage.
  int cverts = 0;
  foreach (int i; 0..cache.npaths) {
    NVGpath* path = &cache.paths[i];
    cverts += path.count+path.nbevel+1;
    if (fringe) cverts += (path.count+path.nbevel*5+1)*2; // plus one for loop
  }

  NVGvertex* verts = nvg__allocTempVerts(ctx, cverts);
  if (verts is null) return;

  bool convex = (cache.npaths == 1 && cache.paths[0].convex);

  foreach (int i; 0..cache.npaths) {
    NVGpath* path = &cache.paths[i];
    NVGpoint* pts = &cache.points[path.first];

    // Calculate shape vertices.
    immutable float woff = 0.5f*aa;
    NVGvertex* dst = verts;
    path.fill = dst;

    if (fringe) {
      // Looping
      NVGpoint* p0 = &pts[path.count-1];
      NVGpoint* p1 = &pts[0];
      foreach (int j; 0..path.count) {
        if (p1.flags&PointFlag.Bevel) {
          immutable float dlx0 = p0.dy;
          immutable float dly0 = -p0.dx;
          immutable float dlx1 = p1.dy;
          immutable float dly1 = -p1.dx;
          if (p1.flags&PointFlag.Left) {
            immutable float lx = p1.x+p1.dmx*woff;
            immutable float ly = p1.y+p1.dmy*woff;
            nvg__vset(dst, lx, ly, 0.5f, 1); ++dst;
          } else {
            immutable float lx0 = p1.x+dlx0*woff;
            immutable float ly0 = p1.y+dly0*woff;
            immutable float lx1 = p1.x+dlx1*woff;
            immutable float ly1 = p1.y+dly1*woff;
            nvg__vset(dst, lx0, ly0, 0.5f, 1); ++dst;
            nvg__vset(dst, lx1, ly1, 0.5f, 1); ++dst;
          }
        } else {
          nvg__vset(dst, p1.x+(p1.dmx*woff), p1.y+(p1.dmy*woff), 0.5f, 1); ++dst;
        }
        p0 = p1++;
      }
    } else {
      foreach (int j; 0..path.count) {
        nvg__vset(dst, pts[j].x, pts[j].y, 0.5f, 1);
        ++dst;
      }
    }

    path.nfill = cast(int)(dst-verts);
    verts = dst;

    // Calculate fringe
    if (fringe) {
      float lw = w+woff;
      immutable float rw = w-woff;
      float lu = 0;
      immutable float ru = 1;
      dst = verts;
      path.stroke = dst;

      // Create only half a fringe for convex shapes so that
      // the shape can be rendered without stenciling.
      if (convex) {
        lw = woff; // This should generate the same vertex as fill inset above.
        lu = 0.5f; // Set outline fade at middle.
      }

      // Looping
      NVGpoint* p0 = &pts[path.count-1];
      NVGpoint* p1 = &pts[0];

      foreach (int j; 0..path.count) {
        if ((p1.flags&(PointFlag.Bevel|PointFlag.InnerBevelPR)) != 0) {
          dst = nvg__bevelJoin(dst, p0, p1, lw, rw, lu, ru, ctx.fringeWidth);
        } else {
          nvg__vset(dst, p1.x+(p1.dmx*lw), p1.y+(p1.dmy*lw), lu, 1); ++dst;
          nvg__vset(dst, p1.x-(p1.dmx*rw), p1.y-(p1.dmy*rw), ru, 1); ++dst;
        }
        p0 = p1++;
      }

      // Loop it
      nvg__vset(dst, verts[0].x, verts[0].y, lu, 1); ++dst;
      nvg__vset(dst, verts[1].x, verts[1].y, ru, 1); ++dst;

      path.nstroke = cast(int)(dst-verts);
      verts = dst;
    } else {
      path.stroke = null;
      path.nstroke = 0;
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
// Paths

/// Clears the current path and sub-paths.
/// Group: paths
public void beginPath (NVGContext ctx) nothrow @trusted @nogc {
  ctx.ncommands = 0;
  ctx.pathPickRegistered &= NVGPickKind.All; // reset "registered" flags
  nvg__clearPathCache(ctx);
}

public alias newPath = beginPath; /// Ditto.

/// Starts new sub-path with specified point as first point.
/// Group: paths
public void moveTo (NVGContext ctx, in float x, in float y) nothrow @trusted @nogc {
  nvg__appendCommands(ctx, Command.MoveTo, x, y);
}

/// Starts new sub-path with specified point as first point.
/// Arguments: [x, y]*
/// Group: paths
public void moveTo (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 2;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [moveTo] call");
  if (args.length < ArgC) return;
  nvg__appendCommands(ctx, Command.MoveTo, args[$-2..$]);
}

/// Adds line segment from the last point in the path to the specified point.
/// Group: paths
public void lineTo (NVGContext ctx, in float x, in float y) nothrow @trusted @nogc {
  nvg__appendCommands(ctx, Command.LineTo, x, y);
}

/// Adds line segment from the last point in the path to the specified point.
/// Arguments: [x, y]*
/// Group: paths
public void lineTo (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 2;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [lineTo] call");
  if (args.length < ArgC) return;
  foreach (immutable idx; 0..args.length/ArgC) {
    nvg__appendCommands(ctx, Command.LineTo, args.ptr[idx*ArgC..idx*ArgC+ArgC]);
  }
}

/// Adds cubic bezier segment from last point in the path via two control points to the specified point.
/// Group: paths
public void bezierTo (NVGContext ctx, in float c1x, in float c1y, in float c2x, in float c2y, in float x, in float y) nothrow @trusted @nogc {
  nvg__appendCommands(ctx, Command.BezierTo, c1x, c1y, c2x, c2y, x, y);
}

/// Adds cubic bezier segment from last point in the path via two control points to the specified point.
/// Arguments: [c1x, c1y, c2x, c2y, x, y]*
/// Group: paths
public void bezierTo (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 6;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [bezierTo] call");
  if (args.length < ArgC) return;
  foreach (immutable idx; 0..args.length/ArgC) {
    nvg__appendCommands(ctx, Command.BezierTo, args.ptr[idx*ArgC..idx*ArgC+ArgC]);
  }
}

/// Adds quadratic bezier segment from last point in the path via a control point to the specified point.
/// Group: paths
public void quadTo (NVGContext ctx, in float cx, in float cy, in float x, in float y) nothrow @trusted @nogc {
  immutable float x0 = ctx.commandx;
  immutable float y0 = ctx.commandy;
  nvg__appendCommands(ctx,
    Command.BezierTo,
    x0+2.0f/3.0f*(cx-x0), y0+2.0f/3.0f*(cy-y0),
    x+2.0f/3.0f*(cx-x), y+2.0f/3.0f*(cy-y),
    x, y,
  );
}

/// Adds quadratic bezier segment from last point in the path via a control point to the specified point.
/// Arguments: [cx, cy, x, y]*
/// Group: paths
public void quadTo (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 4;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [quadTo] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable float x0 = ctx.commandx;
    immutable float y0 = ctx.commandy;
    immutable float cx = *aptr++;
    immutable float cy = *aptr++;
    immutable float x = *aptr++;
    immutable float y = *aptr++;
    nvg__appendCommands(ctx,
      Command.BezierTo,
      x0+2.0f/3.0f*(cx-x0), y0+2.0f/3.0f*(cy-y0),
      x+2.0f/3.0f*(cx-x), y+2.0f/3.0f*(cy-y),
      x, y,
    );
  }
}

/// Adds an arc segment at the corner defined by the last path point, and two specified points.
/// Group: paths
public void arcTo (NVGContext ctx, in float x1, in float y1, in float x2, in float y2, in float radius) nothrow @trusted @nogc {
  if (ctx.ncommands == 0) return;

  immutable float x0 = ctx.commandx;
  immutable float y0 = ctx.commandy;

  // handle degenerate cases
  if (nvg__ptEquals(x0, y0, x1, y1, ctx.distTol) ||
      nvg__ptEquals(x1, y1, x2, y2, ctx.distTol) ||
      nvg__distPtSeg(x1, y1, x0, y0, x2, y2) < ctx.distTol*ctx.distTol ||
      radius < ctx.distTol)
  {
    ctx.lineTo(x1, y1);
    return;
  }

  // calculate tangential circle to lines (x0, y0)-(x1, y1) and (x1, y1)-(x2, y2)
  float dx0 = x0-x1;
  float dy0 = y0-y1;
  float dx1 = x2-x1;
  float dy1 = y2-y1;
  nvg__normalize(&dx0, &dy0);
  nvg__normalize(&dx1, &dy1);
  immutable float a = nvg__acosf(dx0*dx1+dy0*dy1);
  immutable float d = radius/nvg__tanf(a/2.0f);

  //printf("a=%f° d=%f\n", a/NVG_PI*180.0f, d);

  if (d > 10000.0f) {
    ctx.lineTo(x1, y1);
    return;
  }

  float cx = void, cy = void, a0 = void, a1 = void;
  NVGWinding dir;
  if (nvg__cross(dx0, dy0, dx1, dy1) > 0.0f) {
    cx = x1+dx0*d+dy0*radius;
    cy = y1+dy0*d+-dx0*radius;
    a0 = nvg__atan2f(dx0, -dy0);
    a1 = nvg__atan2f(-dx1, dy1);
    dir = NVGWinding.CW;
    //printf("CW c=(%f, %f) a0=%f° a1=%f°\n", cx, cy, a0/NVG_PI*180.0f, a1/NVG_PI*180.0f);
  } else {
    cx = x1+dx0*d+-dy0*radius;
    cy = y1+dy0*d+dx0*radius;
    a0 = nvg__atan2f(-dx0, dy0);
    a1 = nvg__atan2f(dx1, -dy1);
    dir = NVGWinding.CCW;
    //printf("CCW c=(%f, %f) a0=%f° a1=%f°\n", cx, cy, a0/NVG_PI*180.0f, a1/NVG_PI*180.0f);
  }

  ctx.arc(dir, cx, cy, radius, a0, a1); // first is line
}


/// Adds an arc segment at the corner defined by the last path point, and two specified points.
/// Arguments: [x1, y1, x2, y2, radius]*
/// Group: paths
public void arcTo (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 5;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [arcTo] call");
  if (args.length < ArgC) return;
  if (ctx.ncommands == 0) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable float x0 = ctx.commandx;
    immutable float y0 = ctx.commandy;
    immutable float x1 = *aptr++;
    immutable float y1 = *aptr++;
    immutable float x2 = *aptr++;
    immutable float y2 = *aptr++;
    immutable float radius = *aptr++;
    ctx.arcTo(x1, y1, x2, y2, radius);
  }
}

/// Closes current sub-path with a line segment.
/// Group: paths
public void closePath (NVGContext ctx) nothrow @trusted @nogc {
  nvg__appendCommands(ctx, Command.Close);
}

/// Sets the current sub-path winding, see NVGWinding and NVGSolidity.
/// Group: paths
public void pathWinding (NVGContext ctx, NVGWinding dir) nothrow @trusted @nogc {
  nvg__appendCommands(ctx, Command.Winding, cast(float)dir);
}

/// Ditto.
public void pathWinding (NVGContext ctx, NVGSolidity dir) nothrow @trusted @nogc {
  nvg__appendCommands(ctx, Command.Winding, cast(float)dir);
}

/** Creates new circle arc shaped sub-path. The arc center is at (cx, cy), the arc radius is r,
 * and the arc is drawn from angle a0 to a1, and swept in direction dir (NVGWinding.CCW, or NVGWinding.CW).
 * Angles are specified in radians.
 *
 * [mode] is: "original", "move", "line" -- first command will be like original NanoVega, MoveTo, or LineTo
 *
 * Group: paths
 */
public void arc(string mode="original") (NVGContext ctx, NVGWinding dir, in float cx, in float cy, in float r, in float a0, in float a1) nothrow @trusted @nogc {
  static assert(mode == "original" || mode == "move" || mode == "line");

  float[3+5*7+100] vals = void;
  //int move = (ctx.ncommands > 0 ? Command.LineTo : Command.MoveTo);
  static if (mode == "original") {
    immutable int move = (ctx.ncommands > 0 ? Command.LineTo : Command.MoveTo);
  } else static if (mode == "move") {
    enum move = Command.MoveTo;
  } else static if (mode == "line") {
    enum move = Command.LineTo;
  } else {
    static assert(0, "wtf?!");
  }

  // Clamp angles
  float da = a1-a0;
  if (dir == NVGWinding.CW) {
    if (nvg__absf(da) >= NVG_PI*2) {
      da = NVG_PI*2;
    } else {
      while (da < 0.0f) da += NVG_PI*2;
    }
  } else {
    if (nvg__absf(da) >= NVG_PI*2) {
      da = -NVG_PI*2;
    } else {
      while (da > 0.0f) da -= NVG_PI*2;
    }
  }

  // Split arc into max 90 degree segments.
  immutable int ndivs = nvg__max(1, nvg__min(cast(int)(nvg__absf(da)/(NVG_PI*0.5f)+0.5f), 5));
  immutable float hda = (da/cast(float)ndivs)/2.0f;
  float kappa = nvg__absf(4.0f/3.0f*(1.0f-nvg__cosf(hda))/nvg__sinf(hda));

  if (dir == NVGWinding.CCW) kappa = -kappa;

  int nvals = 0;
  float px = 0, py = 0, ptanx = 0, ptany = 0;
  foreach (int i; 0..ndivs+1) {
    immutable float a = a0+da*(i/cast(float)ndivs);
    immutable float dx = nvg__cosf(a);
    immutable float dy = nvg__sinf(a);
    immutable float x = cx+dx*r;
    immutable float y = cy+dy*r;
    immutable float tanx = -dy*r*kappa;
    immutable float tany = dx*r*kappa;

    if (i == 0) {
      if (vals.length-nvals < 3) {
        // flush
        nvg__appendCommands!false(ctx, Command.MoveTo, vals.ptr[0..nvals]); // ignore command
        nvals = 0;
      }
      vals.ptr[nvals++] = cast(float)move;
      vals.ptr[nvals++] = x;
      vals.ptr[nvals++] = y;
    } else {
      if (vals.length-nvals < 7) {
        // flush
        nvg__appendCommands!false(ctx, Command.MoveTo, vals.ptr[0..nvals]); // ignore command
        nvals = 0;
      }
      vals.ptr[nvals++] = Command.BezierTo;
      vals.ptr[nvals++] = px+ptanx;
      vals.ptr[nvals++] = py+ptany;
      vals.ptr[nvals++] = x-tanx;
      vals.ptr[nvals++] = y-tany;
      vals.ptr[nvals++] = x;
      vals.ptr[nvals++] = y;
    }
    px = x;
    py = y;
    ptanx = tanx;
    ptany = tany;
  }

  nvg__appendCommands!false(ctx, Command.MoveTo, vals.ptr[0..nvals]); // ignore command
}


/** Creates new circle arc shaped sub-path. The arc center is at (cx, cy), the arc radius is r,
 * and the arc is drawn from angle a0 to a1, and swept in direction dir (NVGWinding.CCW, or NVGWinding.CW).
 * Angles are specified in radians.
 *
 * Arguments: [cx, cy, r, a0, a1]*
 *
 * [mode] is: "original", "move", "line" -- first command will be like original NanoVega, MoveTo, or LineTo
 *
 * Group: paths
 */
public void arc(string mode="original") (NVGContext ctx, NVGWinding dir, in float[] args) nothrow @trusted @nogc {
  static assert(mode == "original" || mode == "move" || mode == "line");
  enum ArgC = 5;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [arc] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable cx = *aptr++;
    immutable cy = *aptr++;
    immutable r = *aptr++;
    immutable a0 = *aptr++;
    immutable a1 = *aptr++;
    ctx.arc!mode(dir, cx, cy, r, a0, a1);
  }
}

/// Creates new rectangle shaped sub-path.
/// Group: paths
public void rect (NVGContext ctx, in float x, in float y, in float w, in float h) nothrow @trusted @nogc {
  nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
    Command.MoveTo, x, y,
    Command.LineTo, x, y+h,
    Command.LineTo, x+w, y+h,
    Command.LineTo, x+w, y,
    Command.Close,
  );
}

/// Creates new rectangle shaped sub-path.
/// Arguments: [x, y, w, h]*
/// Group: paths
public void rect (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 4;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [rect] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable x = *aptr++;
    immutable y = *aptr++;
    immutable w = *aptr++;
    immutable h = *aptr++;
    nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
      Command.MoveTo, x, y,
      Command.LineTo, x, y+h,
      Command.LineTo, x+w, y+h,
      Command.LineTo, x+w, y,
      Command.Close,
    );
  }
}

/// Creates new rounded rectangle shaped sub-path.
/// Group: paths
public void roundedRect (NVGContext ctx, in float x, in float y, in float w, in float h, in float radius) nothrow @trusted @nogc {
  ctx.roundedRectVarying(x, y, w, h, radius, radius, radius, radius);
}

/// Creates new rounded rectangle shaped sub-path.
/// Arguments: [x, y, w, h, radius]*
/// Group: paths
public void roundedRect (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 5;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [roundedRect] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable x = *aptr++;
    immutable y = *aptr++;
    immutable w = *aptr++;
    immutable h = *aptr++;
    immutable r = *aptr++;
    ctx.roundedRectVarying(x, y, w, h, r, r, r, r);
  }
}

/// Creates new rounded rectangle shaped sub-path. Specify ellipse width and height to round corners according to it.
/// Group: paths
public void roundedRectEllipse (NVGContext ctx, in float x, in float y, in float w, in float h, in float rw, in float rh) nothrow @trusted @nogc {
  if (rw < 0.1f || rh < 0.1f) {
    rect(ctx, x, y, w, h);
  } else {
    nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
      Command.MoveTo, x+rw, y,
      Command.LineTo, x+w-rw, y,
      Command.BezierTo, x+w-rw*(1-NVG_KAPPA90), y, x+w, y+rh*(1-NVG_KAPPA90), x+w, y+rh,
      Command.LineTo, x+w, y+h-rh,
      Command.BezierTo, x+w, y+h-rh*(1-NVG_KAPPA90), x+w-rw*(1-NVG_KAPPA90), y+h, x+w-rw, y+h,
      Command.LineTo, x+rw, y+h,
      Command.BezierTo, x+rw*(1-NVG_KAPPA90), y+h, x, y+h-rh*(1-NVG_KAPPA90), x, y+h-rh,
      Command.LineTo, x, y+rh,
      Command.BezierTo, x, y+rh*(1-NVG_KAPPA90), x+rw*(1-NVG_KAPPA90), y, x+rw, y,
      Command.Close,
    );
  }
}

/// Creates new rounded rectangle shaped sub-path. Specify ellipse width and height to round corners according to it.
/// Arguments: [x, y, w, h, rw, rh]*
/// Group: paths
public void roundedRectEllipse (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 6;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [roundedRectEllipse] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable x = *aptr++;
    immutable y = *aptr++;
    immutable w = *aptr++;
    immutable h = *aptr++;
    immutable rw = *aptr++;
    immutable rh = *aptr++;
    if (rw < 0.1f || rh < 0.1f) {
      rect(ctx, x, y, w, h);
    } else {
      nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
        Command.MoveTo, x+rw, y,
        Command.LineTo, x+w-rw, y,
        Command.BezierTo, x+w-rw*(1-NVG_KAPPA90), y, x+w, y+rh*(1-NVG_KAPPA90), x+w, y+rh,
        Command.LineTo, x+w, y+h-rh,
        Command.BezierTo, x+w, y+h-rh*(1-NVG_KAPPA90), x+w-rw*(1-NVG_KAPPA90), y+h, x+w-rw, y+h,
        Command.LineTo, x+rw, y+h,
        Command.BezierTo, x+rw*(1-NVG_KAPPA90), y+h, x, y+h-rh*(1-NVG_KAPPA90), x, y+h-rh,
        Command.LineTo, x, y+rh,
        Command.BezierTo, x, y+rh*(1-NVG_KAPPA90), x+rw*(1-NVG_KAPPA90), y, x+rw, y,
        Command.Close,
      );
    }
  }
}

/// Creates new rounded rectangle shaped sub-path. This one allows you to specify different rounding radii for each corner.
/// Group: paths
public void roundedRectVarying (NVGContext ctx, in float x, in float y, in float w, in float h, in float radTopLeft, in float radTopRight, in float radBottomRight, in float radBottomLeft) nothrow @trusted @nogc {
  if (radTopLeft < 0.1f && radTopRight < 0.1f && radBottomRight < 0.1f && radBottomLeft < 0.1f) {
    ctx.rect(x, y, w, h);
  } else {
    immutable float halfw = nvg__absf(w)*0.5f;
    immutable float halfh = nvg__absf(h)*0.5f;
    immutable float rxBL = nvg__min(radBottomLeft, halfw)*nvg__sign(w), ryBL = nvg__min(radBottomLeft, halfh)*nvg__sign(h);
    immutable float rxBR = nvg__min(radBottomRight, halfw)*nvg__sign(w), ryBR = nvg__min(radBottomRight, halfh)*nvg__sign(h);
    immutable float rxTR = nvg__min(radTopRight, halfw)*nvg__sign(w), ryTR = nvg__min(radTopRight, halfh)*nvg__sign(h);
    immutable float rxTL = nvg__min(radTopLeft, halfw)*nvg__sign(w), ryTL = nvg__min(radTopLeft, halfh)*nvg__sign(h);
    nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
      Command.MoveTo, x, y+ryTL,
      Command.LineTo, x, y+h-ryBL,
      Command.BezierTo, x, y+h-ryBL*(1-NVG_KAPPA90), x+rxBL*(1-NVG_KAPPA90), y+h, x+rxBL, y+h,
      Command.LineTo, x+w-rxBR, y+h,
      Command.BezierTo, x+w-rxBR*(1-NVG_KAPPA90), y+h, x+w, y+h-ryBR*(1-NVG_KAPPA90), x+w, y+h-ryBR,
      Command.LineTo, x+w, y+ryTR,
      Command.BezierTo, x+w, y+ryTR*(1-NVG_KAPPA90), x+w-rxTR*(1-NVG_KAPPA90), y, x+w-rxTR, y,
      Command.LineTo, x+rxTL, y,
      Command.BezierTo, x+rxTL*(1-NVG_KAPPA90), y, x, y+ryTL*(1-NVG_KAPPA90), x, y+ryTL,
      Command.Close,
    );
  }
}

/// Creates new rounded rectangle shaped sub-path. This one allows you to specify different rounding radii for each corner.
/// Arguments: [x, y, w, h, radTopLeft, radTopRight, radBottomRight, radBottomLeft]*
/// Group: paths
public void roundedRectVarying (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 8;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [roundedRectVarying] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable x = *aptr++;
    immutable y = *aptr++;
    immutable w = *aptr++;
    immutable h = *aptr++;
    immutable radTopLeft = *aptr++;
    immutable radTopRight = *aptr++;
    immutable radBottomRight = *aptr++;
    immutable radBottomLeft = *aptr++;
    if (radTopLeft < 0.1f && radTopRight < 0.1f && radBottomRight < 0.1f && radBottomLeft < 0.1f) {
      ctx.rect(x, y, w, h);
    } else {
      immutable float halfw = nvg__absf(w)*0.5f;
      immutable float halfh = nvg__absf(h)*0.5f;
      immutable float rxBL = nvg__min(radBottomLeft, halfw)*nvg__sign(w), ryBL = nvg__min(radBottomLeft, halfh)*nvg__sign(h);
      immutable float rxBR = nvg__min(radBottomRight, halfw)*nvg__sign(w), ryBR = nvg__min(radBottomRight, halfh)*nvg__sign(h);
      immutable float rxTR = nvg__min(radTopRight, halfw)*nvg__sign(w), ryTR = nvg__min(radTopRight, halfh)*nvg__sign(h);
      immutable float rxTL = nvg__min(radTopLeft, halfw)*nvg__sign(w), ryTL = nvg__min(radTopLeft, halfh)*nvg__sign(h);
      nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
        Command.MoveTo, x, y+ryTL,
        Command.LineTo, x, y+h-ryBL,
        Command.BezierTo, x, y+h-ryBL*(1-NVG_KAPPA90), x+rxBL*(1-NVG_KAPPA90), y+h, x+rxBL, y+h,
        Command.LineTo, x+w-rxBR, y+h,
        Command.BezierTo, x+w-rxBR*(1-NVG_KAPPA90), y+h, x+w, y+h-ryBR*(1-NVG_KAPPA90), x+w, y+h-ryBR,
        Command.LineTo, x+w, y+ryTR,
        Command.BezierTo, x+w, y+ryTR*(1-NVG_KAPPA90), x+w-rxTR*(1-NVG_KAPPA90), y, x+w-rxTR, y,
        Command.LineTo, x+rxTL, y,
        Command.BezierTo, x+rxTL*(1-NVG_KAPPA90), y, x, y+ryTL*(1-NVG_KAPPA90), x, y+ryTL,
        Command.Close,
      );
    }
  }
}

/// Creates new ellipse shaped sub-path.
/// Group: paths
public void ellipse (NVGContext ctx, in float cx, in float cy, in float rx, in float ry) nothrow @trusted @nogc {
  nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
    Command.MoveTo, cx-rx, cy,
    Command.BezierTo, cx-rx, cy+ry*NVG_KAPPA90, cx-rx*NVG_KAPPA90, cy+ry, cx, cy+ry,
    Command.BezierTo, cx+rx*NVG_KAPPA90, cy+ry, cx+rx, cy+ry*NVG_KAPPA90, cx+rx, cy,
    Command.BezierTo, cx+rx, cy-ry*NVG_KAPPA90, cx+rx*NVG_KAPPA90, cy-ry, cx, cy-ry,
    Command.BezierTo, cx-rx*NVG_KAPPA90, cy-ry, cx-rx, cy-ry*NVG_KAPPA90, cx-rx, cy,
    Command.Close,
  );
}

/// Creates new ellipse shaped sub-path.
/// Arguments: [cx, cy, rx, ry]*
/// Group: paths
public void ellipse (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 4;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [ellipse] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable cx = *aptr++;
    immutable cy = *aptr++;
    immutable rx = *aptr++;
    immutable ry = *aptr++;
    nvg__appendCommands!false(ctx, Command.MoveTo, // ignore command
      Command.MoveTo, cx-rx, cy,
      Command.BezierTo, cx-rx, cy+ry*NVG_KAPPA90, cx-rx*NVG_KAPPA90, cy+ry, cx, cy+ry,
      Command.BezierTo, cx+rx*NVG_KAPPA90, cy+ry, cx+rx, cy+ry*NVG_KAPPA90, cx+rx, cy,
      Command.BezierTo, cx+rx, cy-ry*NVG_KAPPA90, cx+rx*NVG_KAPPA90, cy-ry, cx, cy-ry,
      Command.BezierTo, cx-rx*NVG_KAPPA90, cy-ry, cx-rx, cy-ry*NVG_KAPPA90, cx-rx, cy,
      Command.Close,
    );
  }
}

/// Creates new circle shaped sub-path.
/// Group: paths
public void circle (NVGContext ctx, in float cx, in float cy, in float r) nothrow @trusted @nogc {
  ctx.ellipse(cx, cy, r, r);
}

/// Creates new circle shaped sub-path.
/// Arguments: [cx, cy, r]*
/// Group: paths
public void circle (NVGContext ctx, in float[] args) nothrow @trusted @nogc {
  enum ArgC = 3;
  if (args.length%ArgC != 0) assert(0, "NanoVega: invalid [circle] call");
  if (args.length < ArgC) return;
  const(float)* aptr = args.ptr;
  foreach (immutable idx; 0..args.length/ArgC) {
    immutable cx = *aptr++;
    immutable cy = *aptr++;
    immutable r = *aptr++;
    ctx.ellipse(cx, cy, r, r);
  }
}

// Debug function to dump cached path data.
debug public void debugDumpPathCache (NVGContext ctx) nothrow @trusted @nogc {
  import core.stdc.stdio : printf;
  const(NVGpath)* path;
  printf("Dumping %d cached paths\n", ctx.cache.npaths);
  for (int i = 0; i < ctx.cache.npaths; ++i) {
    path = &ctx.cache.paths[i];
    printf("-Path %d\n", i);
    if (path.nfill) {
      printf("-fill: %d\n", path.nfill);
      for (int j = 0; j < path.nfill; ++j) printf("%f\t%f\n", path.fill[j].x, path.fill[j].y);
    }
    if (path.nstroke) {
      printf("-stroke: %d\n", path.nstroke);
      for (int j = 0; j < path.nstroke; ++j) printf("%f\t%f\n", path.stroke[j].x, path.stroke[j].y);
    }
  }
}

// Flatten path, prepare it for fill operation.
void nvg__prepareFill (NVGContext ctx) nothrow @trusted @nogc {
  NVGpathCache* cache = ctx.cache;
  NVGstate* state = nvg__getState(ctx);

  nvg__flattenPaths(ctx);

  if (ctx.params.edgeAntiAlias && state.shapeAntiAlias) {
    nvg__expandFill(ctx, ctx.fringeWidth, NVGLineCap.Miter, 2.4f);
  } else {
    nvg__expandFill(ctx, 0.0f, NVGLineCap.Miter, 2.4f);
  }

  cache.evenOddMode = state.evenOddMode;
  cache.fringeWidth = ctx.fringeWidth;
  cache.fillReady = true;
  cache.strokeReady = false;
  cache.clipmode = NVGClipMode.None;
}

// Flatten path, prepare it for stroke operation.
void nvg__prepareStroke (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  NVGpathCache* cache = ctx.cache;

  nvg__flattenPaths(ctx);

  immutable float scale = nvg__getAverageScale(state.xform);
  float strokeWidth = nvg__clamp(state.strokeWidth*scale, 0.0f, 200.0f);

  if (strokeWidth < ctx.fringeWidth) {
    // If the stroke width is less than pixel size, use alpha to emulate coverage.
    // Since coverage is area, scale by alpha*alpha.
    immutable float alpha = nvg__clamp(strokeWidth/ctx.fringeWidth, 0.0f, 1.0f);
    cache.strokeAlphaMul = alpha*alpha;
    strokeWidth = ctx.fringeWidth;
  } else {
    cache.strokeAlphaMul = 1.0f;
  }
  cache.strokeWidth = strokeWidth;

  if (ctx.params.edgeAntiAlias && state.shapeAntiAlias) {
    nvg__expandStroke(ctx, strokeWidth*0.5f+ctx.fringeWidth*0.5f, state.lineCap, state.lineJoin, state.miterLimit);
  } else {
    nvg__expandStroke(ctx, strokeWidth*0.5f, state.lineCap, state.lineJoin, state.miterLimit);
  }

  cache.fringeWidth = ctx.fringeWidth;
  cache.fillReady = false;
  cache.strokeReady = true;
  cache.clipmode = NVGClipMode.None;
}

/// Fills the current path with current fill style.
/// Group: paths
public void fill (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);

  if (ctx.pathPickId >= 0 && (ctx.pathPickRegistered&(NVGPickKind.Fill|(NVGPickKind.Fill<<16))) == NVGPickKind.Fill) {
    ctx.pathPickRegistered |= NVGPickKind.Fill<<16;
    ctx.currFillHitId = ctx.pathPickId;
  }

  nvg__prepareFill(ctx);

  // apply global alpha
  NVGPaint fillPaint = state.fill;
  fillPaint.innerColor.a *= state.alpha;
  fillPaint.middleColor.a *= state.alpha;
  fillPaint.outerColor.a *= state.alpha;

  ctx.appendCurrentPathToCache(ctx.recset, state.fill);

  if (ctx.recblockdraw) return;

  ctx.params.renderFill(ctx.params.userPtr, state.compositeOperation, NVGClipMode.None, &fillPaint, &state.scissor, ctx.fringeWidth, ctx.cache.bounds.ptr, ctx.cache.paths, ctx.cache.npaths, state.evenOddMode);

  // count triangles
  foreach (int i; 0..ctx.cache.npaths) {
    NVGpath* path = &ctx.cache.paths[i];
    ctx.fillTriCount += path.nfill-2;
    ctx.fillTriCount += path.nstroke-2;
    ctx.drawCallCount += 2;
  }
}

/// Fills the current path with current stroke style.
/// Group: paths
public void stroke (NVGContext ctx) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);

  if (ctx.pathPickId >= 0 && (ctx.pathPickRegistered&(NVGPickKind.Stroke|(NVGPickKind.Stroke<<16))) == NVGPickKind.Stroke) {
    ctx.pathPickRegistered |= NVGPickKind.Stroke<<16;
    ctx.currStrokeHitId = ctx.pathPickId;
  }

  nvg__prepareStroke(ctx);

  NVGpathCache* cache = ctx.cache;

  NVGPaint strokePaint = state.stroke;
  strokePaint.innerColor.a *= cache.strokeAlphaMul;
  strokePaint.middleColor.a *= cache.strokeAlphaMul;
  strokePaint.outerColor.a *= cache.strokeAlphaMul;

  // apply global alpha
  strokePaint.innerColor.a *= state.alpha;
  strokePaint.middleColor.a *= state.alpha;
  strokePaint.outerColor.a *= state.alpha;

  ctx.appendCurrentPathToCache(ctx.recset, state.stroke);

  if (ctx.recblockdraw) return;

  ctx.params.renderStroke(ctx.params.userPtr, state.compositeOperation, NVGClipMode.None, &strokePaint, &state.scissor, ctx.fringeWidth, cache.strokeWidth, ctx.cache.paths, ctx.cache.npaths);

  // count triangles
  foreach (int i; 0..ctx.cache.npaths) {
    NVGpath* path = &ctx.cache.paths[i];
    ctx.strokeTriCount += path.nstroke-2;
    ++ctx.drawCallCount;
  }
}

/// Sets current path as clipping region.
/// Group: clipping
public void clip (NVGContext ctx, NVGClipMode aclipmode=NVGClipMode.Union) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);

  if (aclipmode == NVGClipMode.None) return;
  if (ctx.recblockdraw) return; //???

  if (aclipmode == NVGClipMode.Replace) ctx.params.renderResetClip(ctx.params.userPtr);

  /*
  if (ctx.pathPickId >= 0 && (ctx.pathPickRegistered&(NVGPickKind.Fill|(NVGPickKind.Fill<<16))) == NVGPickKind.Fill) {
    ctx.pathPickRegistered |= NVGPickKind.Fill<<16;
    ctx.currFillHitId = ctx.pathPickId;
  }
  */

  nvg__prepareFill(ctx);

  // apply global alpha
  NVGPaint fillPaint = state.fill;
  fillPaint.innerColor.a *= state.alpha;
  fillPaint.middleColor.a *= state.alpha;
  fillPaint.outerColor.a *= state.alpha;

  //ctx.appendCurrentPathToCache(ctx.recset, state.fill);

  ctx.params.renderFill(ctx.params.userPtr, state.compositeOperation, aclipmode, &fillPaint, &state.scissor, ctx.fringeWidth, ctx.cache.bounds.ptr, ctx.cache.paths, ctx.cache.npaths, state.evenOddMode);

  // count triangles
  foreach (int i; 0..ctx.cache.npaths) {
    NVGpath* path = &ctx.cache.paths[i];
    ctx.fillTriCount += path.nfill-2;
    ctx.fillTriCount += path.nstroke-2;
    ctx.drawCallCount += 2;
  }
}

/// Sets current path as clipping region.
/// Group: clipping
public alias clipFill = clip;

/// Sets current path' stroke as clipping region.
/// Group: clipping
public void clipStroke (NVGContext ctx, NVGClipMode aclipmode=NVGClipMode.Union) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);

  if (aclipmode == NVGClipMode.None) return;
  if (ctx.recblockdraw) return; //???

  if (aclipmode == NVGClipMode.Replace) ctx.params.renderResetClip(ctx.params.userPtr);

  /*
  if (ctx.pathPickId >= 0 && (ctx.pathPickRegistered&(NVGPickKind.Stroke|(NVGPickKind.Stroke<<16))) == NVGPickKind.Stroke) {
    ctx.pathPickRegistered |= NVGPickKind.Stroke<<16;
    ctx.currStrokeHitId = ctx.pathPickId;
  }
  */

  nvg__prepareStroke(ctx);

  NVGpathCache* cache = ctx.cache;

  NVGPaint strokePaint = state.stroke;
  strokePaint.innerColor.a *= cache.strokeAlphaMul;
  strokePaint.middleColor.a *= cache.strokeAlphaMul;
  strokePaint.outerColor.a *= cache.strokeAlphaMul;

  // apply global alpha
  strokePaint.innerColor.a *= state.alpha;
  strokePaint.middleColor.a *= state.alpha;
  strokePaint.outerColor.a *= state.alpha;

  //ctx.appendCurrentPathToCache(ctx.recset, state.stroke);

  ctx.params.renderStroke(ctx.params.userPtr, state.compositeOperation, aclipmode, &strokePaint, &state.scissor, ctx.fringeWidth, cache.strokeWidth, ctx.cache.paths, ctx.cache.npaths);

  // count triangles
  foreach (int i; 0..ctx.cache.npaths) {
    NVGpath* path = &ctx.cache.paths[i];
    ctx.strokeTriCount += path.nstroke-2;
    ++ctx.drawCallCount;
  }
}


// ////////////////////////////////////////////////////////////////////////// //
// Picking API

// most of the code is by Michael Wynne <mike@mikesspace.net>
// https://github.com/memononen/nanovg/pull/230
// https://github.com/MikeWW/nanovg

/// Pick type query. Used in [hitTest] and [hitTestAll].
/// Group: picking_api
public enum NVGPickKind : ubyte {
  Fill = 0x01, ///
  Stroke = 0x02, ///
  All = 0x03, ///
}

/// Marks the fill of the current path as pickable with the specified id.
/// Note that you can create and mark path without rasterizing it.
/// Group: picking_api
public void currFillHitId (NVGContext ctx, int id) nothrow @trusted @nogc {
  NVGpickScene* ps = nvg__pickSceneGet(ctx);
  NVGpickPath* pp = nvg__pickPathCreate(ctx, ctx.commands[0..ctx.ncommands], id, /*forStroke:*/false);
  nvg__pickSceneInsert(ps, pp);
}

public alias currFillPickId = currFillHitId; /// Ditto.

/// Marks the stroke of the current path as pickable with the specified id.
/// Note that you can create and mark path without rasterizing it.
/// Group: picking_api
public void currStrokeHitId (NVGContext ctx, int id) nothrow @trusted @nogc {
  NVGpickScene* ps = nvg__pickSceneGet(ctx);
  NVGpickPath* pp = nvg__pickPathCreate(ctx, ctx.commands[0..ctx.ncommands], id, /*forStroke:*/true);
  nvg__pickSceneInsert(ps, pp);
}

public alias currStrokePickId = currStrokeHitId; /// Ditto.

// Marks the saved path set (fill) as pickable with the specified id.
// $(WARNING this doesn't work right yet (it is using current context transformation and other settings instead of record settings)!)
// Group: picking_api
/+
public void pathSetFillHitId (NVGContext ctx, NVGPathSet svp, int id) nothrow @trusted @nogc {
  if (svp is null) return;
  if (svp.svctx !is ctx) assert(0, "NanoVega: cannot register path set from different context");
  foreach (ref cp; svp.caches[0..svp.ncaches]) {
    NVGpickScene* ps = nvg__pickSceneGet(ctx);
    NVGpickPath* pp = nvg__pickPathCreate(ctx, cp.commands[0..cp.ncommands], id, /*forStroke:*/false);
    nvg__pickSceneInsert(ps, pp);
  }
}
+/

// Marks the saved path set (stroke) as pickable with the specified id.
// $(WARNING this doesn't work right yet (it is using current context transformation and other settings instead of record settings)!)
// Group: picking_api
/+
public void pathSetStrokeHitId (NVGContext ctx, NVGPathSet svp, int id) nothrow @trusted @nogc {
  if (svp is null) return;
  if (svp.svctx !is ctx) assert(0, "NanoVega: cannot register path set from different context");
  foreach (ref cp; svp.caches[0..svp.ncaches]) {
    NVGpickScene* ps = nvg__pickSceneGet(ctx);
    NVGpickPath* pp = nvg__pickPathCreate(ctx, cp.commands[0..cp.ncommands], id, /*forStroke:*/true);
    nvg__pickSceneInsert(ps, pp);
  }
}
+/

private template IsGoodHitTestDG(DG) {
  enum IsGoodHitTestDG =
    __traits(compiles, (){ DG dg; bool res = dg(cast(int)42, cast(int)666); }) ||
    __traits(compiles, (){ DG dg; dg(cast(int)42, cast(int)666); });
}

private template IsGoodHitTestInternalDG(DG) {
  enum IsGoodHitTestInternalDG =
    __traits(compiles, (){ DG dg; NVGpickPath* pp; bool res = dg(pp); }) ||
    __traits(compiles, (){ DG dg; NVGpickPath* pp; dg(pp); });
}

/// Call delegate [dg] for each path under the specified position (in no particular order).
/// Returns the id of the path for which delegate [dg] returned true or [NVGNoPick].
/// dg is: `bool delegate (int id, int order)` -- [order] is path ordering (ascending).
/// Group: picking_api
public int hitTestDG(bool bestOrder=false, DG) (NVGContext ctx, in float x, in float y, NVGPickKind kind, scope DG dg) if (IsGoodHitTestDG!DG || IsGoodHitTestInternalDG!DG) {
  if (ctx.pickScene is null || ctx.pickScene.npaths == 0 || (kind&NVGPickKind.All) == 0) return -1;

  NVGpickScene* ps = ctx.pickScene;
  int levelwidth = 1<<(ps.nlevels-1);
  int cellx = nvg__clamp(cast(int)(x/ps.xdim), 0, levelwidth);
  int celly = nvg__clamp(cast(int)(y/ps.ydim), 0, levelwidth);
  int npicked = 0;

  // if we are interested only in most-toplevel path, there is no reason to check paths with worser order.
  // but we cannot just get out on the first path found, 'cause we are using quad tree to speed up bounds
  // checking, so path walking order is not guaranteed.
  static if (bestOrder) {
    int lastBestOrder = int.min;
  }

  //{ import core.stdc.stdio; printf("npaths=%d\n", ps.npaths); }
  for (int lvl = ps.nlevels-1; lvl >= 0; --lvl) {
    for (NVGpickPath* pp = ps.levels[lvl][celly*levelwidth+cellx]; pp !is null; pp = pp.next) {
      //{ import core.stdc.stdio; printf("... pos=(%g,%g); bounds=(%g,%g)-(%g,%g); flags=0x%02x; kind=0x%02x; kpx=0x%02x\n", x, y, pp.bounds[0], pp.bounds[1], pp.bounds[2], pp.bounds[3], pp.flags, kind, kind&pp.flags&3); }
      static if (bestOrder) {
        // reject earlier paths
        if (pp.order <= lastBestOrder) continue; // not interesting
      }
      immutable uint kpx = kind&pp.flags&3;
      if (kpx == 0) continue; // not interesting
      if (!nvg__pickPathTestBounds(ctx, ps, pp, x, y)) continue; // not interesting
      //{ import core.stdc.stdio; printf("in bounds!\n"); }
      int hit = 0;
      if (kpx&NVGPickKind.Stroke) hit = nvg__pickPathStroke(ps, pp, x, y);
      if (!hit && (kpx&NVGPickKind.Fill)) hit = nvg__pickPath(ps, pp, x, y);
      if (!hit) continue;
      //{ import core.stdc.stdio; printf("  HIT!\n"); }
      static if (bestOrder) lastBestOrder = pp.order;
      static if (IsGoodHitTestDG!DG) {
        static if (__traits(compiles, (){ DG dg; bool res = dg(cast(int)42, cast(int)666); })) {
          if (dg(pp.id, cast(int)pp.order)) return pp.id;
        } else {
          dg(pp.id, cast(int)pp.order);
        }
      } else {
        static if (__traits(compiles, (){ DG dg; NVGpickPath* pp; bool res = dg(pp); })) {
          if (dg(pp)) return pp.id;
        } else {
          dg(pp);
        }
      }
    }
    cellx >>= 1;
    celly >>= 1;
    levelwidth >>= 1;
  }

  return -1;
}

/// Fills ids with a list of the top most hit ids (from bottom to top) under the specified position.
/// Returns the slice of [ids].
/// Group: picking_api
public int[] hitTestAll (NVGContext ctx, in float x, in float y, NVGPickKind kind, int[] ids) nothrow @trusted @nogc {
  if (ctx.pickScene is null || ids.length == 0) return ids[0..0];

  int npicked = 0;
  NVGpickScene* ps = ctx.pickScene;

  ctx.hitTestDG!false(x, y, kind, delegate (NVGpickPath* pp) nothrow @trusted @nogc {
    if (npicked == ps.cpicked) {
      int cpicked = ps.cpicked+ps.cpicked;
      NVGpickPath** picked = cast(NVGpickPath**)realloc(ps.picked, (NVGpickPath*).sizeof*ps.cpicked);
      if (picked is null) return true; // abort
      ps.cpicked = cpicked;
      ps.picked = picked;
    }
    ps.picked[npicked] = pp;
    ++npicked;
    return false; // go on
  });

  qsort(ps.picked, npicked, (NVGpickPath*).sizeof, &nvg__comparePaths);

  assert(npicked >= 0);
  if (npicked > ids.length) npicked = cast(int)ids.length;
  foreach (immutable nidx, ref int did; ids[0..npicked]) did = ps.picked[nidx].id;

  return ids[0..npicked];
}

/// Returns the id of the pickable shape containing x,y or [NVGNoPick] if no shape was found.
/// Group: picking_api
public int hitTest (NVGContext ctx, in float x, in float y, NVGPickKind kind=NVGPickKind.All) nothrow @trusted @nogc {
  if (ctx.pickScene is null) return -1;

  int bestOrder = int.min;
  int bestID = -1;

  ctx.hitTestDG!true(x, y, kind, delegate (NVGpickPath* pp) {
    if (pp.order > bestOrder) {
      bestOrder = pp.order;
      bestID = pp.id;
    }
  });

  return bestID;
}

/// Returns `true` if the path with the given id contains x,y.
/// Group: picking_api
public bool hitTestForId (NVGContext ctx, in int id, in float x, in float y, NVGPickKind kind=NVGPickKind.All) nothrow @trusted @nogc {
  if (ctx.pickScene is null || id == NVGNoPick) return false;

  bool res = false;

  ctx.hitTestDG!false(x, y, kind, delegate (NVGpickPath* pp) {
    if (pp.id == id) {
      res = true;
      return true; // stop
    }
    return false; // continue
  });

  return res;
}

/// Returns `true` if the given point is within the fill of the currently defined path.
/// This operation can be done before rasterizing the current path.
/// Group: picking_api
public bool hitTestCurrFill (NVGContext ctx, in float x, in float y) nothrow @trusted @nogc {
  NVGpickScene* ps = nvg__pickSceneGet(ctx);
  int oldnpoints = ps.npoints;
  int oldnsegments = ps.nsegments;
  NVGpickPath* pp = nvg__pickPathCreate(ctx, ctx.commands[0..ctx.ncommands], 1, /*forStroke:*/false);
  if (pp is null) return false; // oops
  scope(exit) {
    nvg__freePickPath(ps, pp);
    ps.npoints = oldnpoints;
    ps.nsegments = oldnsegments;
  }
  return (nvg__pointInBounds(x, y, pp.bounds) ? nvg__pickPath(ps, pp, x, y) : false);
}

alias isPointInPath = hitTestCurrFill; /// Ditto.

/// Returns `true` if the given point is within the stroke of the currently defined path.
/// This operation can be done before rasterizing the current path.
/// Group: picking_api
public bool hitTestCurrStroke (NVGContext ctx, in float x, in float y) nothrow @trusted @nogc {
  NVGpickScene* ps = nvg__pickSceneGet(ctx);
  int oldnpoints = ps.npoints;
  int oldnsegments = ps.nsegments;
  NVGpickPath* pp = nvg__pickPathCreate(ctx, ctx.commands[0..ctx.ncommands], 1, /*forStroke:*/true);
  if (pp is null) return false; // oops
  scope(exit) {
    nvg__freePickPath(ps, pp);
    ps.npoints = oldnpoints;
    ps.nsegments = oldnsegments;
  }
  return (nvg__pointInBounds(x, y, pp.bounds) ? nvg__pickPathStroke(ps, pp, x, y) : false);
}


nothrow @trusted @nogc {
extern(C) {
  private alias _compare_fp_t = int function (const void*, const void*) nothrow @nogc;
  private extern(C) void qsort (scope void* base, size_t nmemb, size_t size, _compare_fp_t compar) nothrow @nogc;

  extern(C) int nvg__comparePaths (const void* a, const void* b) {
    return (*cast(const(NVGpickPath)**)b).order-(*cast(const(NVGpickPath)**)a).order;
  }
}

enum NVGPickEPS = 0.0001f;

// Segment flags
enum NVGSegmentFlags {
  Corner = 1,
  Bevel = 2,
  InnerBevel = 4,
  Cap = 8,
  Endcap = 16,
}

// Path flags
enum NVGPathFlags : ushort {
  Fill = NVGPickKind.Fill,
  Stroke = NVGPickKind.Stroke,
  Scissor = 0x80,
}

struct NVGsegment {
  int firstPoint; // Index into NVGpickScene.points
  short type; // NVG_LINETO or NVG_BEZIERTO
  short flags; // Flags relate to the corner between the prev segment and this one.
  float[4] bounds;
  float[2] startDir; // Direction at t == 0
  float[2] endDir; // Direction at t == 1
  float[2] miterDir; // Direction of miter of corner between the prev segment and this one.
}

struct NVGpickSubPath {
  short winding; // TODO: Merge to flag field
  bool closed; // TODO: Merge to flag field

  int firstSegment; // Index into NVGpickScene.segments
  int nsegments;

  float[4] bounds;

  NVGpickSubPath* next;
}

struct NVGpickPath {
  int id;
  short flags;
  short order;
  float strokeWidth;
  float miterLimit;
  short lineCap;
  short lineJoin;
  bool evenOddMode;

  float[4] bounds;
  int scissor; // Indexes into ps->points and defines scissor rect as XVec, YVec and Center

  NVGpickSubPath* subPaths;
  NVGpickPath* next;
  NVGpickPath* cellnext;
}

struct NVGpickScene {
  int npaths;

  NVGpickPath* paths; // Linked list of paths
  NVGpickPath* lastPath; // The last path in the paths linked list (the first path added)
  NVGpickPath* freePaths; // Linked list of free paths

  NVGpickSubPath* freeSubPaths; // Linked list of free sub paths

  int width;
  int height;

  // Points for all path sub paths.
  float* points;
  int npoints;
  int cpoints;

  // Segments for all path sub paths
  NVGsegment* segments;
  int nsegments;
  int csegments;

  // Implicit quadtree
  float xdim; // Width / (1 << nlevels)
  float ydim; // Height / (1 << nlevels)
  int ncells; // Total number of cells in all levels
  int nlevels;
  NVGpickPath*** levels; // Index: [Level][LevelY * LevelW + LevelX] Value: Linked list of paths

  // Temp storage for picking
  int cpicked;
  NVGpickPath** picked;
}


// bounds utilities
void nvg__initBounds (ref float[4] bounds) {
  bounds.ptr[0] = bounds.ptr[1] = 1e6f;
  bounds.ptr[2] = bounds.ptr[3] = -1e6f;
}

void nvg__expandBounds (ref float[4] bounds, const(float)* points, int npoints) {
  npoints *= 2;
  for (int i = 0; i < npoints; i += 2) {
    bounds.ptr[0] = nvg__min(bounds.ptr[0], points[i]);
    bounds.ptr[1] = nvg__min(bounds.ptr[1], points[i+1]);
    bounds.ptr[2] = nvg__max(bounds.ptr[2], points[i]);
    bounds.ptr[3] = nvg__max(bounds.ptr[3], points[i+1]);
  }
}

void nvg__unionBounds (ref float[4] bounds, in ref float[4] boundsB) {
  bounds.ptr[0] = nvg__min(bounds.ptr[0], boundsB.ptr[0]);
  bounds.ptr[1] = nvg__min(bounds.ptr[1], boundsB.ptr[1]);
  bounds.ptr[2] = nvg__max(bounds.ptr[2], boundsB.ptr[2]);
  bounds.ptr[3] = nvg__max(bounds.ptr[3], boundsB.ptr[3]);
}

void nvg__intersectBounds (ref float[4] bounds, in ref float[4] boundsB) {
  bounds.ptr[0] = nvg__max(boundsB.ptr[0], bounds.ptr[0]);
  bounds.ptr[1] = nvg__max(boundsB.ptr[1], bounds.ptr[1]);
  bounds.ptr[2] = nvg__min(boundsB.ptr[2], bounds.ptr[2]);
  bounds.ptr[3] = nvg__min(boundsB.ptr[3], bounds.ptr[3]);

  bounds.ptr[2] = nvg__max(bounds.ptr[0], bounds.ptr[2]);
  bounds.ptr[3] = nvg__max(bounds.ptr[1], bounds.ptr[3]);
}

bool nvg__pointInBounds (in float x, in float y, in ref float[4] bounds) {
  pragma(inline, true);
  return (x >= bounds.ptr[0] && x <= bounds.ptr[2] && y >= bounds.ptr[1] && y <= bounds.ptr[3]);
}

// building paths & sub paths
int nvg__pickSceneAddPoints (NVGpickScene* ps, const(float)* xy, int n) {
  import core.stdc.string : memcpy;
  if (ps.npoints+n > ps.cpoints) {
    import core.stdc.stdlib : realloc;
    int cpoints = ps.npoints+n+(ps.cpoints<<1);
    float* points = cast(float*)realloc(ps.points, float.sizeof*2*cpoints);
    if (points is null) assert(0, "NanoVega: out of memory");
    ps.points = points;
    ps.cpoints = cpoints;
  }
  int i = ps.npoints;
  if (xy !is null) memcpy(&ps.points[i*2], xy, float.sizeof*2*n);
  ps.npoints += n;
  return i;
}

void nvg__pickSubPathAddSegment (NVGpickScene* ps, NVGpickSubPath* psp, int firstPoint, int type, short flags) {
  NVGsegment* seg = null;
  if (ps.nsegments == ps.csegments) {
    int csegments = 1+ps.csegments+(ps.csegments<<1);
    NVGsegment* segments = cast(NVGsegment*)realloc(ps.segments, NVGsegment.sizeof*csegments);
    if (segments is null) assert(0, "NanoVega: out of memory");
    ps.segments = segments;
    ps.csegments = csegments;
  }

  if (psp.firstSegment == -1) psp.firstSegment = ps.nsegments;

  seg = &ps.segments[ps.nsegments];
  ++ps.nsegments;
  seg.firstPoint = firstPoint;
  seg.type = cast(short)type;
  seg.flags = flags;
  ++psp.nsegments;

  nvg__segmentDir(ps, psp, seg, 0, seg.startDir);
  nvg__segmentDir(ps, psp, seg, 1, seg.endDir);
}

void nvg__segmentDir (NVGpickScene* ps, NVGpickSubPath* psp, NVGsegment* seg, float t, ref float[2] d) {
  const(float)* points = &ps.points[seg.firstPoint*2];
  immutable float x0 = points[0*2+0], x1 = points[1*2+0];
  immutable float y0 = points[0*2+1], y1 = points[1*2+1];
  switch (seg.type) {
    case Command.LineTo:
      d.ptr[0] = x1-x0;
      d.ptr[1] = y1-y0;
      nvg__normalize(&d.ptr[0], &d.ptr[1]);
      break;
    case Command.BezierTo:
      immutable float x2 = points[2*2+0];
      immutable float y2 = points[2*2+1];
      immutable float x3 = points[3*2+0];
      immutable float y3 = points[3*2+1];

      immutable float omt = 1.0f-t;
      immutable float omt2 = omt*omt;
      immutable float t2 = t*t;

      d.ptr[0] =
        3.0f*omt2*(x1-x0)+
        6.0f*omt*t*(x2-x1)+
        3.0f*t2*(x3-x2);

      d.ptr[1] =
        3.0f*omt2*(y1-y0)+
        6.0f*omt*t*(y2-y1)+
        3.0f*t2*(y3-y2);

      nvg__normalize(&d.ptr[0], &d.ptr[1]);
      break;
    default:
      break;
  }
}

void nvg__pickSubPathAddFillSupports (NVGpickScene* ps, NVGpickSubPath* psp) {
  if (psp.firstSegment == -1) return;
  NVGsegment* segments = &ps.segments[psp.firstSegment];
  for (int s = 0; s < psp.nsegments; ++s) {
    NVGsegment* seg = &segments[s];
    const(float)* points = &ps.points[seg.firstPoint*2];
    if (seg.type == Command.LineTo) {
      nvg__initBounds(seg.bounds);
      nvg__expandBounds(seg.bounds, points, 2);
    } else {
      nvg__bezierBounds(points, seg.bounds);
    }
  }
}

void nvg__pickSubPathAddStrokeSupports (NVGpickScene* ps, NVGpickSubPath* psp, float strokeWidth, int lineCap, int lineJoin, float miterLimit) {
  if (psp.firstSegment == -1) return;
  immutable bool closed = psp.closed;
  const(float)* points = ps.points;
  NVGsegment* seg = null;
  NVGsegment* segments = &ps.segments[psp.firstSegment];
  int nsegments = psp.nsegments;
  NVGsegment* prevseg = (closed ? &segments[psp.nsegments-1] : null);

  int ns = 0; // nsupports
  float[32] supportingPoints;
  int firstPoint, lastPoint;

  if (!closed) {
    segments[0].flags |= NVGSegmentFlags.Cap;
    segments[nsegments-1].flags |= NVGSegmentFlags.Endcap;
  }

  for (int s = 0; s < nsegments; ++s) {
    seg = &segments[s];
    nvg__initBounds(seg.bounds);

    firstPoint = seg.firstPoint*2;
    lastPoint = firstPoint+(seg.type == Command.LineTo ? 2 : 6);

    ns = 0;

    // First two supporting points are either side of the start point
    supportingPoints.ptr[ns++] = points[firstPoint]-seg.startDir.ptr[1]*strokeWidth;
    supportingPoints.ptr[ns++] = points[firstPoint+1]+seg.startDir.ptr[0]*strokeWidth;

    supportingPoints.ptr[ns++] = points[firstPoint]+seg.startDir.ptr[1]*strokeWidth;
    supportingPoints.ptr[ns++] = points[firstPoint+1]-seg.startDir.ptr[0]*strokeWidth;

    // Second two supporting points are either side of the end point
    supportingPoints.ptr[ns++] = points[lastPoint]-seg.endDir.ptr[1]*strokeWidth;
    supportingPoints.ptr[ns++] = points[lastPoint+1]+seg.endDir.ptr[0]*strokeWidth;

    supportingPoints.ptr[ns++] = points[lastPoint]+seg.endDir.ptr[1]*strokeWidth;
    supportingPoints.ptr[ns++] = points[lastPoint+1]-seg.endDir.ptr[0]*strokeWidth;

    if ((seg.flags&NVGSegmentFlags.Corner) && prevseg !is null) {
      seg.miterDir.ptr[0] = 0.5f*(-prevseg.endDir.ptr[1]-seg.startDir.ptr[1]);
      seg.miterDir.ptr[1] = 0.5f*(prevseg.endDir.ptr[0]+seg.startDir.ptr[0]);

      immutable float M2 = seg.miterDir.ptr[0]*seg.miterDir.ptr[0]+seg.miterDir.ptr[1]*seg.miterDir.ptr[1];

      if (M2 > 0.000001f) {
        float scale = 1.0f/M2;
        if (scale > 600.0f) scale = 600.0f;
        seg.miterDir.ptr[0] *= scale;
        seg.miterDir.ptr[1] *= scale;
      }

      //NVG_PICK_DEBUG_VECTOR_SCALE(&points[firstPoint], seg.miterDir, 10);

      // Add an additional support at the corner on the other line
      supportingPoints.ptr[ns++] = points[firstPoint]-prevseg.endDir.ptr[1]*strokeWidth;
      supportingPoints.ptr[ns++] = points[firstPoint+1]+prevseg.endDir.ptr[0]*strokeWidth;

      if (lineJoin == NVGLineCap.Miter || lineJoin == NVGLineCap.Bevel) {
        // Set a corner as beveled if the join type is bevel or mitered and
        // miterLimit is hit.
        if (lineJoin == NVGLineCap.Bevel || (M2*miterLimit*miterLimit) < 1.0f) {
          seg.flags |= NVGSegmentFlags.Bevel;
        } else {
          // Corner is mitered - add miter point as a support
          supportingPoints.ptr[ns++] = points[firstPoint]+seg.miterDir.ptr[0]*strokeWidth;
          supportingPoints.ptr[ns++] = points[firstPoint+1]+seg.miterDir.ptr[1]*strokeWidth;
        }
      } else if (lineJoin == NVGLineCap.Round) {
        // ... and at the midpoint of the corner arc
        float[2] vertexN = [ -seg.startDir.ptr[0]+prevseg.endDir.ptr[0], -seg.startDir.ptr[1]+prevseg.endDir.ptr[1] ];
        nvg__normalize(&vertexN[0], &vertexN[1]);

        supportingPoints.ptr[ns++] = points[firstPoint]+vertexN[0]*strokeWidth;
        supportingPoints.ptr[ns++] = points[firstPoint+1]+vertexN[1]*strokeWidth;
      }
    }

    if (seg.flags&NVGSegmentFlags.Cap) {
      switch (lineCap) {
        case NVGLineCap.Butt:
          // supports for butt already added
          break;
        case NVGLineCap.Square:
          // square cap supports are just the original two supports moved out along the direction
          supportingPoints.ptr[ns++] = supportingPoints.ptr[0]-seg.startDir.ptr[0]*strokeWidth;
          supportingPoints.ptr[ns++] = supportingPoints.ptr[1]-seg.startDir.ptr[1]*strokeWidth;
          supportingPoints.ptr[ns++] = supportingPoints.ptr[2]-seg.startDir.ptr[0]*strokeWidth;
          supportingPoints.ptr[ns++] = supportingPoints.ptr[3]-seg.startDir.ptr[1]*strokeWidth;
          break;
        case NVGLineCap.Round:
          // add one additional support for the round cap along the dir
          supportingPoints.ptr[ns++] = points[firstPoint]-seg.startDir.ptr[0]*strokeWidth;
          supportingPoints.ptr[ns++] = points[firstPoint+1]-seg.startDir.ptr[1]*strokeWidth;
          break;
        default:
          break;
      }
    }

    if (seg.flags&NVGSegmentFlags.Endcap) {
      // end supporting points, either side of line
      int end = 4;
      switch(lineCap) {
        case NVGLineCap.Butt:
          // supports for butt already added
          break;
        case NVGLineCap.Square:
          // square cap supports are just the original two supports moved out along the direction
          supportingPoints.ptr[ns++] = supportingPoints.ptr[end+0]+seg.endDir.ptr[0]*strokeWidth;
          supportingPoints.ptr[ns++] = supportingPoints.ptr[end+1]+seg.endDir.ptr[1]*strokeWidth;
          supportingPoints.ptr[ns++] = supportingPoints.ptr[end+2]+seg.endDir.ptr[0]*strokeWidth;
          supportingPoints.ptr[ns++] = supportingPoints.ptr[end+3]+seg.endDir.ptr[1]*strokeWidth;
          break;
        case NVGLineCap.Round:
          // add one additional support for the round cap along the dir
          supportingPoints.ptr[ns++] = points[lastPoint]+seg.endDir.ptr[0]*strokeWidth;
          supportingPoints.ptr[ns++] = points[lastPoint+1]+seg.endDir.ptr[1]*strokeWidth;
          break;
        default:
          break;
      }
    }

    nvg__expandBounds(seg.bounds, supportingPoints.ptr, ns/2);

    prevseg = seg;
  }
}

NVGpickPath* nvg__pickPathCreate (NVGContext context, const(float)[] acommands, int id, bool forStroke) {
  NVGpickScene* ps = nvg__pickSceneGet(context);
  if (ps is null) return null;

  int i = 0;

  int ncommands = cast(int)acommands.length;
  const(float)* commands = acommands.ptr;

  NVGpickPath* pp = null;
  NVGpickSubPath* psp = null;
  float[2] start = void;
  int firstPoint;

  //bool hasHoles = false;
  NVGpickSubPath* prev = null;

  float[8] points = void;
  float[2] inflections = void;
  int ninflections = 0;

  NVGstate* state = nvg__getState(context);
  float[4] totalBounds = void;
  NVGsegment* segments = null;
  const(NVGsegment)* seg = null;
  NVGpickSubPath *curpsp;

  pp = nvg__allocPickPath(ps);
  if (pp is null) return null;

  pp.id = id;

  bool hasPoints = false;

  void closeIt () {
    if (psp is null || !hasPoints) return;
    if (ps.points[(ps.npoints-1)*2] != start.ptr[0] || ps.points[(ps.npoints-1)*2+1] != start.ptr[1]) {
      firstPoint = nvg__pickSceneAddPoints(ps, start.ptr, 1);
      nvg__pickSubPathAddSegment(ps, psp, firstPoint-1, Command.LineTo, NVGSegmentFlags.Corner);
    }
    psp.closed = true;
  }

  while (i < ncommands) {
    int cmd = cast(int)commands[i++];
    switch (cmd) {
      case Command.MoveTo: // one coordinate pair
        const(float)* tfxy = commands+i;
        i += 2;

        // new starting point
        start.ptr[0..2] = tfxy[0..2];

        // start a new path for each sub path to handle sub paths that intersect other sub paths
        prev = psp;
        psp = nvg__allocPickSubPath(ps);
        if (psp is null) { psp = prev; break; }
        psp.firstSegment = -1;
        psp.winding = NVGSolidity.Solid;
        psp.next = prev;

        nvg__pickSceneAddPoints(ps, tfxy, 1);
        hasPoints = true;
        break;
      case Command.LineTo: // one coordinate pair
        const(float)* tfxy = commands+i;
        i += 2;
        firstPoint = nvg__pickSceneAddPoints(ps, tfxy, 1);
        nvg__pickSubPathAddSegment(ps, psp, firstPoint-1, cmd, NVGSegmentFlags.Corner);
        hasPoints = true;
        break;
      case Command.BezierTo: // three coordinate pairs
        const(float)* tfxy = commands+i;
        i += 3*2;

        // Split the curve at it's dx==0 or dy==0 inflection points.
        // Thus:
        //    A horizontal line only ever interects the curves once.
        //  and
        //    Finding the closest point on any curve converges more reliably.

        // NOTE: We could just split on dy==0 here.

        memcpy(&points.ptr[0], &ps.points[(ps.npoints-1)*2], float.sizeof*2);
        memcpy(&points.ptr[2], tfxy, float.sizeof*2*3);

        ninflections = 0;
        nvg__bezierInflections(points.ptr, 1, &ninflections, inflections.ptr);
        nvg__bezierInflections(points.ptr, 0, &ninflections, inflections.ptr);

        if (ninflections) {
          float previnfl = 0;
          float[8] pointsA = void, pointsB = void;

          nvg__smallsort(inflections.ptr, ninflections);

          for (int infl = 0; infl < ninflections; ++infl) {
            if (nvg__absf(inflections.ptr[infl]-previnfl) < NVGPickEPS) continue;

            immutable float t = (inflections.ptr[infl]-previnfl)*(1.0f/(1.0f-previnfl));

            previnfl = inflections.ptr[infl];

            nvg__splitBezier(points.ptr, t, pointsA.ptr, pointsB.ptr);

            firstPoint = nvg__pickSceneAddPoints(ps, &pointsA.ptr[2], 3);
            nvg__pickSubPathAddSegment(ps, psp, firstPoint-1, cmd, (infl == 0) ? NVGSegmentFlags.Corner : 0);

            memcpy(points.ptr, pointsB.ptr, float.sizeof*8);
          }

          firstPoint = nvg__pickSceneAddPoints(ps, &pointsB.ptr[2], 3);
          nvg__pickSubPathAddSegment(ps, psp, firstPoint-1, cmd, 0);
        } else {
          firstPoint = nvg__pickSceneAddPoints(ps, tfxy, 3);
          nvg__pickSubPathAddSegment(ps, psp, firstPoint-1, cmd, NVGSegmentFlags.Corner);
        }
        hasPoints = true;
        break;
      case Command.Close:
        closeIt();
        break;
      case Command.Winding:
        psp.winding = cast(short)cast(int)commands[i];
        //if (psp.winding == NVGSolidity.Hole) hasHoles = true;
        i += 1;
        break;
      default:
        break;
    }
  }

  // force-close filled paths
  if (psp !is null && !forStroke && hasPoints && !psp.closed) closeIt();

  pp.flags = (forStroke ? NVGPathFlags.Stroke : NVGPathFlags.Fill);
  pp.subPaths = psp;
  pp.strokeWidth = state.strokeWidth*0.5f;
  pp.miterLimit = state.miterLimit;
  pp.lineCap = cast(short)state.lineCap;
  pp.lineJoin = cast(short)state.lineJoin;
  pp.evenOddMode = nvg__getState(context).evenOddMode;

  nvg__initBounds(totalBounds);

  for (curpsp = psp; curpsp; curpsp = curpsp.next) {
    if (forStroke) {
      nvg__pickSubPathAddStrokeSupports(ps, curpsp, pp.strokeWidth, pp.lineCap, pp.lineJoin, pp.miterLimit);
    } else {
      nvg__pickSubPathAddFillSupports(ps, curpsp);
    }

    if (curpsp.firstSegment == -1) continue;
    segments = &ps.segments[curpsp.firstSegment];
    nvg__initBounds(curpsp.bounds);
    for (int s = 0; s < curpsp.nsegments; ++s) {
      seg = &segments[s];
      //NVG_PICK_DEBUG_BOUNDS(seg.bounds);
      nvg__unionBounds(curpsp.bounds, seg.bounds);
    }

    nvg__unionBounds(totalBounds, curpsp.bounds);
  }

  // Store the scissor rect if present.
  if (state.scissor.extent.ptr[0] != -1.0f) {
    // Use points storage to store the scissor data
    pp.scissor = nvg__pickSceneAddPoints(ps, null, 4);
    float* scissor = &ps.points[pp.scissor*2];

    //memcpy(scissor, state.scissor.xform.ptr, 6*float.sizeof);
    scissor[0..6] = state.scissor.xform.mat[];
    memcpy(scissor+6, state.scissor.extent.ptr, 2*float.sizeof);

    pp.flags |= NVGPathFlags.Scissor;
  }

  memcpy(pp.bounds.ptr, totalBounds.ptr, float.sizeof*4);

  return pp;
}


// Struct management
NVGpickPath* nvg__allocPickPath (NVGpickScene* ps) {
  NVGpickPath* pp = ps.freePaths;
  if (pp !is null) {
    ps.freePaths = pp.next;
  } else {
    pp = cast(NVGpickPath*)malloc(NVGpickPath.sizeof);
  }
  memset(pp, 0, NVGpickPath.sizeof);
  return pp;
}

// Put a pick path and any sub paths (back) to the free lists.
void nvg__freePickPath (NVGpickScene* ps, NVGpickPath* pp) {
  // Add all sub paths to the sub path free list.
  // Finds the end of the path sub paths, links that to the current
  // sub path free list head and replaces the head ptr with the
  // head path sub path entry.
  NVGpickSubPath* psp = null;
  for (psp = pp.subPaths; psp !is null && psp.next !is null; psp = psp.next) {}

  if (psp) {
    psp.next = ps.freeSubPaths;
    ps.freeSubPaths = pp.subPaths;
  }
  pp.subPaths = null;

  // Add the path to the path freelist
  pp.next = ps.freePaths;
  ps.freePaths = pp;
  if (pp.next is null) ps.lastPath = pp;
}

NVGpickSubPath* nvg__allocPickSubPath (NVGpickScene* ps) {
  NVGpickSubPath* psp = ps.freeSubPaths;
  if (psp !is null) {
    ps.freeSubPaths = psp.next;
  } else {
    psp = cast(NVGpickSubPath*)malloc(NVGpickSubPath.sizeof);
    if (psp is null) return null;
  }
  memset(psp, 0, NVGpickSubPath.sizeof);
  return psp;
}

void nvg__returnPickSubPath (NVGpickScene* ps, NVGpickSubPath* psp) {
  psp.next = ps.freeSubPaths;
  ps.freeSubPaths = psp;
}

NVGpickScene* nvg__allocPickScene () {
  NVGpickScene* ps = cast(NVGpickScene*)malloc(NVGpickScene.sizeof);
  if (ps is null) return null;
  memset(ps, 0, NVGpickScene.sizeof);
  ps.nlevels = 5;
  return ps;
}

void nvg__deletePickScene (NVGpickScene* ps) {
  NVGpickPath* pp;
  NVGpickSubPath* psp;

  // Add all paths (and thus sub paths) to the free list(s).
  while (ps.paths !is null) {
    pp = ps.paths.next;
    nvg__freePickPath(ps, ps.paths);
    ps.paths = pp;
  }

  // Delete all paths
  while (ps.freePaths !is null) {
    pp = ps.freePaths;
    ps.freePaths = pp.next;
    while (pp.subPaths !is null) {
      psp = pp.subPaths;
      pp.subPaths = psp.next;
      free(psp);
    }
    free(pp);
  }

  // Delete all sub paths
  while (ps.freeSubPaths !is null) {
    psp = ps.freeSubPaths.next;
    free(ps.freeSubPaths);
    ps.freeSubPaths = psp;
  }

  ps.npoints = 0;
  ps.nsegments = 0;

  if (ps.levels !is null) {
    free(ps.levels[0]);
    free(ps.levels);
  }

  if (ps.picked !is null) free(ps.picked);
  if (ps.points !is null) free(ps.points);
  if (ps.segments !is null) free(ps.segments);

  free(ps);
}

NVGpickScene* nvg__pickSceneGet (NVGContext ctx) {
  if (ctx.pickScene is null) ctx.pickScene = nvg__allocPickScene();
  return ctx.pickScene;
}


// Applies Casteljau's algorithm to a cubic bezier for a given parameter t
// points is 4 points (8 floats)
// lvl1 is 3 points (6 floats)
// lvl2 is 2 points (4 floats)
// lvl3 is 1 point (2 floats)
void nvg__casteljau (const(float)* points, float t, float* lvl1, float* lvl2, float* lvl3) {
  enum x0 = 0*2+0; enum x1 = 1*2+0; enum x2 = 2*2+0; enum x3 = 3*2+0;
  enum y0 = 0*2+1; enum y1 = 1*2+1; enum y2 = 2*2+1; enum y3 = 3*2+1;

  // Level 1
  lvl1[x0] = (points[x1]-points[x0])*t+points[x0];
  lvl1[y0] = (points[y1]-points[y0])*t+points[y0];

  lvl1[x1] = (points[x2]-points[x1])*t+points[x1];
  lvl1[y1] = (points[y2]-points[y1])*t+points[y1];

  lvl1[x2] = (points[x3]-points[x2])*t+points[x2];
  lvl1[y2] = (points[y3]-points[y2])*t+points[y2];

  // Level 2
  lvl2[x0] = (lvl1[x1]-lvl1[x0])*t+lvl1[x0];
  lvl2[y0] = (lvl1[y1]-lvl1[y0])*t+lvl1[y0];

  lvl2[x1] = (lvl1[x2]-lvl1[x1])*t+lvl1[x1];
  lvl2[y1] = (lvl1[y2]-lvl1[y1])*t+lvl1[y1];

  // Level 3
  lvl3[x0] = (lvl2[x1]-lvl2[x0])*t+lvl2[x0];
  lvl3[y0] = (lvl2[y1]-lvl2[y0])*t+lvl2[y0];
}

// Calculates a point on a bezier at point t.
void nvg__bezierEval (const(float)* points, float t, ref float[2] tpoint) {
  immutable float omt = 1-t;
  immutable float omt3 = omt*omt*omt;
  immutable float omt2 = omt*omt;
  immutable float t3 = t*t*t;
  immutable float t2 = t*t;

  tpoint.ptr[0] =
    points[0]*omt3+
    points[2]*3.0f*omt2*t+
    points[4]*3.0f*omt*t2+
    points[6]*t3;

  tpoint.ptr[1] =
    points[1]*omt3+
    points[3]*3.0f*omt2*t+
    points[5]*3.0f*omt*t2+
    points[7]*t3;
}

// Splits a cubic bezier curve into two parts at point t.
void nvg__splitBezier (const(float)* points, float t, float* pointsA, float* pointsB) {
  enum x0 = 0*2+0; enum x1 = 1*2+0; enum x2 = 2*2+0; enum x3 = 3*2+0;
  enum y0 = 0*2+1; enum y1 = 1*2+1; enum y2 = 2*2+1; enum y3 = 3*2+1;

  float[6] lvl1 = void;
  float[4] lvl2 = void;
  float[2] lvl3 = void;

  nvg__casteljau(points, t, lvl1.ptr, lvl2.ptr, lvl3.ptr);

  // First half
  pointsA[x0] = points[x0];
  pointsA[y0] = points[y0];

  pointsA[x1] = lvl1.ptr[x0];
  pointsA[y1] = lvl1.ptr[y0];

  pointsA[x2] = lvl2.ptr[x0];
  pointsA[y2] = lvl2.ptr[y0];

  pointsA[x3] = lvl3.ptr[x0];
  pointsA[y3] = lvl3.ptr[y0];

  // Second half
  pointsB[x0] = lvl3.ptr[x0];
  pointsB[y0] = lvl3.ptr[y0];

  pointsB[x1] = lvl2.ptr[x1];
  pointsB[y1] = lvl2.ptr[y1];

  pointsB[x2] = lvl1.ptr[x2];
  pointsB[y2] = lvl1.ptr[y2];

  pointsB[x3] = points[x3];
  pointsB[y3] = points[y3];
}

// Calculates the inflection points in coordinate coord (X = 0, Y = 1) of a cubic bezier.
// Appends any found inflection points to the array inflections and increments *ninflections.
// So finds the parameters where dx/dt or dy/dt is 0
void nvg__bezierInflections (const(float)* points, int coord, int* ninflections, float* inflections) {
  immutable float v0 = points[0*2+coord], v1 = points[1*2+coord], v2 = points[2*2+coord], v3 = points[3*2+coord];
  float[2] t = void;
  int nvalid = *ninflections;

  immutable float a = 3.0f*( -v0+3.0f*v1-3.0f*v2+v3 );
  immutable float b = 6.0f*( v0-2.0f*v1+v2 );
  immutable float c = 3.0f*( v1-v0 );

  float d = b*b-4.0f*a*c;
  if (nvg__absf(d-0.0f) < NVGPickEPS) {
    // Zero or one root
    t.ptr[0] = -b/2.0f*a;
    if (t.ptr[0] > NVGPickEPS && t.ptr[0] < (1.0f-NVGPickEPS)) {
      inflections[nvalid] = t.ptr[0];
      ++nvalid;
    }
  } else if (d > NVGPickEPS) {
    // zero, one or two roots
    d = nvg__sqrtf(d);

    t.ptr[0] = (-b+d)/(2.0f*a);
    t.ptr[1] = (-b-d)/(2.0f*a);

    for (int i = 0; i < 2; ++i) {
      if (t.ptr[i] > NVGPickEPS && t.ptr[i] < (1.0f-NVGPickEPS)) {
        inflections[nvalid] = t.ptr[i];
        ++nvalid;
      }
    }
  } else {
    // zero roots
  }

  *ninflections = nvalid;
}

// Sort a small number of floats in ascending order (0 < n < 6)
void nvg__smallsort (float* values, int n) {
  bool bSwapped = true;
  for (int j = 0; j < n-1 && bSwapped; ++j) {
    bSwapped = false;
    for (int i = 0; i < n-1; ++i) {
      if (values[i] > values[i+1]) {
        auto tmp = values[i];
        values[i] = values[i+1];
        values[i+1] = tmp;
      }
    }
  }
}

// Calculates the bounding rect of a given cubic bezier curve.
void nvg__bezierBounds (const(float)* points, ref float[4] bounds) {
  float[4] inflections = void;
  int ninflections = 0;
  float[2] tpoint = void;

  nvg__initBounds(bounds);

  // Include start and end points in bounds
  nvg__expandBounds(bounds, &points[0], 1);
  nvg__expandBounds(bounds, &points[6], 1);

  // Calculate dx==0 and dy==0 inflection points and add then to the bounds

  nvg__bezierInflections(points, 0, &ninflections, inflections.ptr);
  nvg__bezierInflections(points, 1, &ninflections, inflections.ptr);

  for (int i = 0; i < ninflections; ++i) {
    nvg__bezierEval(points, inflections[i], tpoint);
    nvg__expandBounds(bounds, tpoint.ptr, 1);
  }
}

// Checks to see if a line originating from x,y along the +ve x axis
// intersects the given line (points[0],points[1]) -> (points[2], points[3]).
// Returns `true` on intersection.
// Horizontal lines are never hit.
bool nvg__intersectLine (const(float)* points, float x, float y) {
  immutable float x1 = points[0];
  immutable float y1 = points[1];
  immutable float x2 = points[2];
  immutable float y2 = points[3];
  immutable float d = y2-y1;
  if (d > NVGPickEPS || d < -NVGPickEPS) {
    immutable float s = (x2-x1)/d;
    immutable float lineX = x1+(y-y1)*s;
    return (lineX > x);
  } else {
    return false;
  }
}

// Checks to see if a line originating from x,y along the +ve x axis intersects the given bezier.
// It is assumed that the line originates from within the bounding box of
// the bezier and that the curve has no dy=0 inflection points.
// Returns the number of intersections found (which is either 1 or 0).
int nvg__intersectBezier (const(float)* points, float x, float y) {
  immutable float x0 = points[0*2+0], x1 = points[1*2+0], x2 = points[2*2+0], x3 = points[3*2+0];
  immutable float y0 = points[0*2+1], y1 = points[1*2+1], y2 = points[2*2+1], y3 = points[3*2+1];

  if (y0 == y1 && y1 == y2 && y2 == y3) return 0;

  // Initial t guess
  float t = void;
       if (y3 != y0) t = (y-y0)/(y3-y0);
  else if (x3 != x0) t = (x-x0)/(x3-x0);
  else t = 0.5f;

  // A few Newton iterations
  for (int iter = 0; iter < 6; ++iter) {
    immutable float omt = 1-t;
    immutable float omt2 = omt*omt;
    immutable float t2 = t*t;
    immutable float omt3 = omt2*omt;
    immutable float t3 = t2*t;

    immutable float ty = y0*omt3 +
      y1*3.0f*omt2*t +
      y2*3.0f*omt*t2 +
      y3*t3;

    // Newton iteration
    immutable float dty = 3.0f*omt2*(y1-y0) +
      6.0f*omt*t*(y2-y1) +
      3.0f*t2*(y3-y2);

    // dty will never == 0 since:
    //  Either omt, omt2 are zero OR t2 is zero
    //  y0 != y1 != y2 != y3 (checked above)
    t = t-(ty-y)/dty;
  }

  {
    immutable float omt = 1-t;
    immutable float omt2 = omt*omt;
    immutable float t2 = t*t;
    immutable float omt3 = omt2*omt;
    immutable float t3 = t2*t;

    immutable float tx =
      x0*omt3+
      x1*3.0f*omt2*t+
      x2*3.0f*omt*t2+
      x3*t3;

    return (tx > x ? 1 : 0);
  }
}

// Finds the closest point on a line to a given point
void nvg__closestLine (const(float)* points, float x, float y, float* closest, float* ot) {
  immutable float x1 = points[0];
  immutable float y1 = points[1];
  immutable float x2 = points[2];
  immutable float y2 = points[3];
  immutable float pqx = x2-x1;
  immutable float pqz = y2-y1;
  immutable float dx = x-x1;
  immutable float dz = y-y1;
  immutable float d = pqx*pqx+pqz*pqz;
  float t = pqx*dx+pqz*dz;
  if (d > 0) t /= d;
  if (t < 0) t = 0; else if (t > 1) t = 1;
  closest[0] = x1+t*pqx;
  closest[1] = y1+t*pqz;
  *ot = t;
}

// Finds the closest point on a curve for a given point (x,y).
// Assumes that the curve has no dx==0 or dy==0 inflection points.
void nvg__closestBezier (const(float)* points, float x, float y, float* closest, float *ot) {
  immutable float x0 = points[0*2+0], x1 = points[1*2+0], x2 = points[2*2+0], x3 = points[3*2+0];
  immutable float y0 = points[0*2+1], y1 = points[1*2+1], y2 = points[2*2+1], y3 = points[3*2+1];

  // This assumes that the curve has no dy=0 inflection points.

  // Initial t guess
  float t = 0.5f;

  // A few Newton iterations
  for (int iter = 0; iter < 6; ++iter) {
    immutable float omt = 1-t;
    immutable float omt2 = omt*omt;
    immutable float t2 = t*t;
    immutable float omt3 = omt2*omt;
    immutable float t3 = t2*t;

    immutable float ty =
      y0*omt3+
      y1*3.0f*omt2*t+
      y2*3.0f*omt*t2+
      y3*t3;

    immutable float tx =
      x0*omt3+
      x1*3.0f*omt2*t+
      x2*3.0f*omt*t2+
      x3*t3;

    // Newton iteration
    immutable float dty =
      3.0f*omt2*(y1-y0)+
      6.0f*omt*t*(y2-y1)+
      3.0f*t2*(y3-y2);

    immutable float ddty =
      6.0f*omt*(y2-2.0f*y1+y0)+
      6.0f*t*(y3-2.0f*y2+y1);

    immutable float dtx =
      3.0f*omt2*(x1-x0)+
      6.0f*omt*t*(x2-x1)+
      3.0f*t2*(x3-x2);

    immutable float ddtx =
      6.0f*omt*(x2-2.0f*x1+x0)+
      6.0f*t*(x3-2.0f*x2+x1);

    immutable float errorx = tx-x;
    immutable float errory = ty-y;

    immutable float n = errorx*dtx+errory*dty;
    if (n == 0) break;

    immutable float d = dtx*dtx+dty*dty+errorx*ddtx+errory*ddty;
    if (d != 0) t = t-n/d; else break;
  }

  t = nvg__max(0, nvg__min(1.0, t));
  *ot = t;
  {
    immutable float omt = 1-t;
    immutable float omt2 = omt*omt;
    immutable float t2 = t*t;
    immutable float omt3 = omt2*omt;
    immutable float t3 = t2*t;

    immutable float ty =
      y0*omt3+
      y1*3.0f*omt2*t+
      y2*3.0f*omt*t2+
      y3*t3;

    immutable float tx =
      x0*omt3+
      x1*3.0f*omt2*t+
      x2*3.0f*omt*t2+
      x3*t3;

    closest[0] = tx;
    closest[1] = ty;
  }
}

// Returns:
//  1  If (x,y) is contained by the stroke of the path
//  0  If (x,y) is not contained by the path.
int nvg__pickSubPathStroke (const NVGpickScene* ps, const NVGpickSubPath* psp, float x, float y, float strokeWidth, int lineCap, int lineJoin) {
  if (!nvg__pointInBounds(x, y, psp.bounds)) return 0;
  if (psp.firstSegment == -1) return 0;

  float[2] closest = void;
  float[2] d = void;
  float t = void;

  // trace a line from x,y out along the positive x axis and count the number of intersections
  int nsegments = psp.nsegments;
  const(NVGsegment)* seg = ps.segments+psp.firstSegment;
  const(NVGsegment)* prevseg = (psp.closed ? &ps.segments[psp.firstSegment+nsegments-1] : null);
  immutable float strokeWidthSqd = strokeWidth*strokeWidth;

  for (int s = 0; s < nsegments; ++s, prevseg = seg, ++seg) {
    if (nvg__pointInBounds(x, y, seg.bounds)) {
      // Line potentially hits stroke.
      switch (seg.type) {
        case Command.LineTo:
          nvg__closestLine(&ps.points[seg.firstPoint*2], x, y, closest.ptr, &t);
          break;
        case Command.BezierTo:
          nvg__closestBezier(&ps.points[seg.firstPoint*2], x, y, closest.ptr, &t);
          break;
        default:
          continue;
      }

      d.ptr[0] = x-closest.ptr[0];
      d.ptr[1] = y-closest.ptr[1];

      if ((t >= NVGPickEPS && t <= 1.0f-NVGPickEPS) ||
          (seg.flags&(NVGSegmentFlags.Corner|NVGSegmentFlags.Cap|NVGSegmentFlags.Endcap)) == 0 ||
          (lineJoin == NVGLineCap.Round))
      {
        // Closest point is in the middle of the line/curve, at a rounded join/cap
        // or at a smooth join
        immutable float distSqd = d.ptr[0]*d.ptr[0]+d.ptr[1]*d.ptr[1];
        if (distSqd < strokeWidthSqd) return 1;
      } else if ((t > 1.0f-NVGPickEPS && (seg.flags&NVGSegmentFlags.Endcap)) ||
                 (t < NVGPickEPS && (seg.flags&NVGSegmentFlags.Cap))) {
        switch (lineCap) {
          case NVGLineCap.Butt:
            immutable float distSqd = d.ptr[0]*d.ptr[0]+d.ptr[1]*d.ptr[1];
            immutable float dirD = (t < NVGPickEPS ?
              -(d.ptr[0]*seg.startDir.ptr[0]+d.ptr[1]*seg.startDir.ptr[1]) :
                d.ptr[0]*seg.endDir.ptr[0]+d.ptr[1]*seg.endDir.ptr[1]);
            if (dirD < -NVGPickEPS && distSqd < strokeWidthSqd) return 1;
            break;
          case NVGLineCap.Square:
            if (nvg__absf(d.ptr[0]) < strokeWidth && nvg__absf(d.ptr[1]) < strokeWidth) return 1;
            break;
          case NVGLineCap.Round:
            immutable float distSqd = d.ptr[0]*d.ptr[0]+d.ptr[1]*d.ptr[1];
            if (distSqd < strokeWidthSqd) return 1;
            break;
          default:
            break;
        }
      } else if (seg.flags&NVGSegmentFlags.Corner) {
        // Closest point is at a corner
        const(NVGsegment)* seg0, seg1;

        if (t < NVGPickEPS) {
          seg0 = prevseg;
          seg1 = seg;
        } else {
          seg0 = seg;
          seg1 = (s == nsegments-1 ? &ps.segments[psp.firstSegment] : seg+1);
        }

        if (!(seg1.flags&NVGSegmentFlags.Bevel)) {
          immutable float prevNDist = -seg0.endDir.ptr[1]*d.ptr[0]+seg0.endDir.ptr[0]*d.ptr[1];
          immutable float curNDist = seg1.startDir.ptr[1]*d.ptr[0]-seg1.startDir.ptr[0]*d.ptr[1];
          if (nvg__absf(prevNDist) < strokeWidth && nvg__absf(curNDist) < strokeWidth) return 1;
        } else {
          d.ptr[0] -= -seg1.startDir.ptr[1]*strokeWidth;
          d.ptr[1] -= +seg1.startDir.ptr[0]*strokeWidth;
          if (seg1.miterDir.ptr[0]*d.ptr[0]+seg1.miterDir.ptr[1]*d.ptr[1] < 0) return 1;
        }
      }
    }
  }

  return 0;
}

// Returns:
//   1  If (x,y) is contained by the path and the path is solid.
//  -1  If (x,y) is contained by the path and the path is a hole.
//   0  If (x,y) is not contained by the path.
int nvg__pickSubPath (const NVGpickScene* ps, const NVGpickSubPath* psp, float x, float y, bool evenOddMode) {
  if (!nvg__pointInBounds(x, y, psp.bounds)) return 0;
  if (psp.firstSegment == -1) return 0;

  const(NVGsegment)* seg = &ps.segments[psp.firstSegment];
  int nsegments = psp.nsegments;
  int nintersections = 0;

  // trace a line from x,y out along the positive x axis and count the number of intersections
  for (int s = 0; s < nsegments; ++s, ++seg) {
    if ((seg.bounds.ptr[1]-NVGPickEPS) < y &&
        (seg.bounds.ptr[3]-NVGPickEPS) > y &&
        seg.bounds.ptr[2] > x)
    {
      // Line hits the box.
      switch (seg.type) {
        case Command.LineTo:
          if (seg.bounds.ptr[0] > x) {
            // line originates outside the box
            ++nintersections;
          } else {
            // line originates inside the box
            nintersections += nvg__intersectLine(&ps.points[seg.firstPoint*2], x, y);
          }
          break;
        case Command.BezierTo:
          if (seg.bounds.ptr[0] > x) {
            // line originates outside the box
            ++nintersections;
          } else {
            // line originates inside the box
            nintersections += nvg__intersectBezier(&ps.points[seg.firstPoint*2], x, y);
          }
          break;
        default:
          break;
      }
    }
  }

  if (evenOddMode) {
    return nintersections;
  } else {
    return (nintersections&1 ? (psp.winding == NVGSolidity.Solid ? 1 : -1) : 0);
  }
}

bool nvg__pickPath (const(NVGpickScene)* ps, const(NVGpickPath)* pp, float x, float y) {
  int pickCount = 0;
  const(NVGpickSubPath)* psp = pp.subPaths;
  while (psp !is null) {
    pickCount += nvg__pickSubPath(ps, psp, x, y, pp.evenOddMode);
    psp = psp.next;
  }
  return ((pp.evenOddMode ? pickCount&1 : pickCount) != 0);
}

bool nvg__pickPathStroke (const(NVGpickScene)* ps, const(NVGpickPath)* pp, float x, float y) {
  const(NVGpickSubPath)* psp = pp.subPaths;
  while (psp !is null) {
    if (nvg__pickSubPathStroke(ps, psp, x, y, pp.strokeWidth, pp.lineCap, pp.lineJoin)) return true;
    psp = psp.next;
  }
  return false;
}

bool nvg__pickPathTestBounds (NVGContext ctx, const NVGpickScene* ps, const NVGpickPath* pp, float x, float y) {
  if (nvg__pointInBounds(x, y, pp.bounds)) {
    //{ import core.stdc.stdio; printf("  (0): in bounds!\n"); }
    if (pp.flags&NVGPathFlags.Scissor) {
      const(float)* scissor = &ps.points[pp.scissor*2];
      // untransform scissor translation
      float stx = void, sty = void;
      ctx.gpuUntransformPoint(&stx, &sty, scissor[4], scissor[5]);
      immutable float rx = x-stx;
      immutable float ry = y-sty;
      //{ import core.stdc.stdio; printf("  (1): rxy=(%g,%g); scissor=[%g,%g,%g,%g,%g] [%g,%g]!\n", rx, ry, scissor[0], scissor[1], scissor[2], scissor[3], scissor[4], scissor[5], scissor[6], scissor[7]); }
      if (nvg__absf((scissor[0]*rx)+(scissor[1]*ry)) > scissor[6] ||
          nvg__absf((scissor[2]*rx)+(scissor[3]*ry)) > scissor[7])
      {
        //{ import core.stdc.stdio; printf("    (1): scissor reject!\n"); }
        return false;
      }
    }
    return true;
  }
  return false;
}

int nvg__countBitsUsed (uint v) pure {
  pragma(inline, true);
  import core.bitop : bsr;
  return (v != 0 ? bsr(v)+1 : 0);
}

void nvg__pickSceneInsert (NVGpickScene* ps, NVGpickPath* pp) {
  if (ps is null || pp is null) return;

  int[4] cellbounds;
  int base = ps.nlevels-1;
  int level;
  int levelwidth;
  int levelshift;
  int levelx;
  int levely;
  NVGpickPath** cell = null;

  // Bit tricks for inserting into an implicit quadtree.

  // Calc bounds of path in cells at the lowest level
  cellbounds.ptr[0] = cast(int)(pp.bounds.ptr[0]/ps.xdim);
  cellbounds.ptr[1] = cast(int)(pp.bounds.ptr[1]/ps.ydim);
  cellbounds.ptr[2] = cast(int)(pp.bounds.ptr[2]/ps.xdim);
  cellbounds.ptr[3] = cast(int)(pp.bounds.ptr[3]/ps.ydim);

  // Find which bits differ between the min/max x/y coords
  cellbounds.ptr[0] ^= cellbounds.ptr[2];
  cellbounds.ptr[1] ^= cellbounds.ptr[3];

  // Use the number of bits used (countBitsUsed(x) == sizeof(int) * 8 - clz(x);
  // to calculate the level to insert at (the level at which the bounds fit in a single cell)
  level = nvg__min(base-nvg__countBitsUsed(cellbounds.ptr[0]), base-nvg__countBitsUsed(cellbounds.ptr[1]));
  if (level < 0) level = 0;
  //{ import core.stdc.stdio; printf("LEVEL: %d; bounds=(%g,%g)-(%g,%g)\n", level, pp.bounds[0], pp.bounds[1], pp.bounds[2], pp.bounds[3]); }
  //level = 0;

  // Find the correct cell in the chosen level, clamping to the edges.
  levelwidth = 1<<level;
  levelshift = (ps.nlevels-level)-1;
  levelx = nvg__clamp(cellbounds.ptr[2]>>levelshift, 0, levelwidth-1);
  levely = nvg__clamp(cellbounds.ptr[3]>>levelshift, 0, levelwidth-1);

  // Insert the path into the linked list at that cell.
  cell = &ps.levels[level][levely*levelwidth+levelx];

  pp.cellnext = *cell;
  *cell = pp;

  if (ps.paths is null) ps.lastPath = pp;
  pp.next = ps.paths;
  ps.paths = pp;

  // Store the order (depth) of the path for picking ops.
  pp.order = cast(short)ps.npaths;
  ++ps.npaths;
}

void nvg__pickBeginFrame (NVGContext ctx, int width, int height) {
  NVGpickScene* ps = nvg__pickSceneGet(ctx);

  //NVG_PICK_DEBUG_NEWFRAME();

  // Return all paths & sub paths from last frame to the free list
  while (ps.paths !is null) {
    NVGpickPath* pp = ps.paths.next;
    nvg__freePickPath(ps, ps.paths);
    ps.paths = pp;
  }

  ps.paths = null;
  ps.npaths = 0;

  // Store the screen metrics for the quadtree
  ps.width = width;
  ps.height = height;

  immutable float lowestSubDiv = cast(float)(1<<(ps.nlevels-1));
  ps.xdim = cast(float)width/lowestSubDiv;
  ps.ydim = cast(float)height/lowestSubDiv;

  // Allocate the quadtree if required.
  if (ps.levels is null) {
    int ncells = 1;

    ps.levels = cast(NVGpickPath***)malloc((NVGpickPath**).sizeof*ps.nlevels);
    for (int l = 0; l < ps.nlevels; ++l) {
      int leveldim = 1<<l;
      ncells += leveldim*leveldim;
    }

    ps.levels[0] = cast(NVGpickPath**)malloc((NVGpickPath*).sizeof*ncells);

    int cell = 1;
    for (int l = 1; l < ps.nlevels; ++l) {
      ps.levels[l] = &ps.levels[0][cell];
      int leveldim = 1<<l;
      cell += leveldim*leveldim;
    }

    ps.ncells = ncells;
  }
  memset(ps.levels[0], 0, ps.ncells*(NVGpickPath*).sizeof);

  // Allocate temporary storage for nvgHitTestAll results if required.
  if (ps.picked is null) {
    ps.cpicked = 16;
    ps.picked = cast(NVGpickPath**)malloc((NVGpickPath*).sizeof*ps.cpicked);
  }

  ps.npoints = 0;
  ps.nsegments = 0;
}
} // nothrow @trusted @nogc


// ////////////////////////////////////////////////////////////////////////// //
// Text

/** Creates font by loading it from the disk from specified file name.
 * Returns handle to the font or FONS_INVALID (aka -1) on error.
 * Use "fontname:noaa" as [name] to turn off antialiasing (if font driver supports that).
 *
 * On POSIX systems it is possible to use fontconfig font names too.
 * `:noaa` in font path is still allowed, but it must be the last option.
 *
 * Group: text_api
 */
public int createFont (NVGContext ctx, const(char)[] name, const(char)[] path) nothrow @trusted {
  return fonsAddFont(ctx.fs, name, path, ctx.params.fontAA);
}

/** Creates font by loading it from the specified memory chunk.
 * Returns handle to the font or FONS_INVALID (aka -1) on error.
 * Won't free data on error.
 *
 * Group: text_api
 */
public int createFontMem (NVGContext ctx, const(char)[] name, ubyte* data, int ndata, bool freeData) nothrow @trusted @nogc {
  return fonsAddFontMem(ctx.fs, name, data, ndata, freeData, ctx.params.fontAA);
}

/// Add fonts from another context.
/// This is more effective than reloading fonts, 'cause font data will be shared.
/// Group: text_api
public void addFontsFrom (NVGContext ctx, NVGContext source) nothrow @trusted @nogc {
  if (ctx is null || source is null) return;
  ctx.fs.fonsAddStashFonts(source.fs);
}

/// Finds a loaded font of specified name, and returns handle to it, or FONS_INVALID (aka -1) if the font is not found.
/// Group: text_api
public int findFont (NVGContext ctx, const(char)[] name) nothrow @trusted @nogc {
  pragma(inline, true);
  return (name.length == 0 ? FONS_INVALID : fonsGetFontByName(ctx.fs, name));
}

/// Sets the font size of current text style.
/// Group: text_api
public void fontSize (NVGContext ctx, float size) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).fontSize = size;
}

/// Gets the font size of current text style.
/// Group: text_api
public float fontSize (NVGContext ctx) nothrow @trusted @nogc {
  pragma(inline, true);
  return nvg__getState(ctx).fontSize;
}

/// Sets the blur of current text style.
/// Group: text_api
public void fontBlur (NVGContext ctx, float blur) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).fontBlur = blur;
}

/// Gets the blur of current text style.
/// Group: text_api
public float fontBlur (NVGContext ctx) nothrow @trusted @nogc {
  pragma(inline, true);
  return nvg__getState(ctx).fontBlur;
}

/// Sets the letter spacing of current text style.
/// Group: text_api
public void textLetterSpacing (NVGContext ctx, float spacing) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).letterSpacing = spacing;
}

/// Gets the letter spacing of current text style.
/// Group: text_api
public float textLetterSpacing (NVGContext ctx) nothrow @trusted @nogc {
  pragma(inline, true);
  return nvg__getState(ctx).letterSpacing;
}

/// Sets the proportional line height of current text style. The line height is specified as multiple of font size.
/// Group: text_api
public void textLineHeight (NVGContext ctx, float lineHeight) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).lineHeight = lineHeight;
}

/// Gets the proportional line height of current text style. The line height is specified as multiple of font size.
/// Group: text_api
public float textLineHeight (NVGContext ctx) nothrow @trusted @nogc {
  pragma(inline, true);
  return nvg__getState(ctx).lineHeight;
}

/// Sets the text align of current text style, see [NVGTextAlign] for options.
/// Group: text_api
public void textAlign (NVGContext ctx, NVGTextAlign talign) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).textAlign = talign;
}

/// Ditto.
public void textAlign (NVGContext ctx, NVGTextAlign.H h) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).textAlign.horizontal = h;
}

/// Ditto.
public void textAlign (NVGContext ctx, NVGTextAlign.V v) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).textAlign.vertical = v;
}

/// Ditto.
public void textAlign (NVGContext ctx, NVGTextAlign.H h, NVGTextAlign.V v) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).textAlign.reset(h, v);
}

/// Ditto.
public void textAlign (NVGContext ctx, NVGTextAlign.V v, NVGTextAlign.H h) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).textAlign.reset(h, v);
}

/// Gets the text align of current text style, see [NVGTextAlign] for options.
/// Group: text_api
public NVGTextAlign textAlign (NVGContext ctx) nothrow @trusted @nogc {
  pragma(inline, true);
  return nvg__getState(ctx).textAlign;
}

/// Sets the font face based on specified id of current text style.
/// Group: text_api
public void fontFaceId (NVGContext ctx, int font) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).fontId = font;
}

/// Gets the font face based on specified id of current text style.
/// Group: text_api
public int fontFaceId (NVGContext ctx) nothrow @trusted @nogc {
  pragma(inline, true);
  return nvg__getState(ctx).fontId;
}

/** Sets the font face based on specified name of current text style.
 *
 * The underlying implementation is using O(1) data structure to lookup
 * font names, so you probably should use this function instead of [fontFaceId]
 * to make your code more robust and less error-prone.
 *
 * Group: text_api
 */
public void fontFace (NVGContext ctx, const(char)[] font) nothrow @trusted @nogc {
  pragma(inline, true);
  nvg__getState(ctx).fontId = fonsGetFontByName(ctx.fs, font);
}

static if (is(typeof(&fons__nvg__toPath))) {
  public enum NanoVegaHasCharToPath = true; ///
} else {
  public enum NanoVegaHasCharToPath = false; ///
}

/// Adds glyph outlines to the current path. Vertical 0 is baseline.
/// The glyph is not scaled in any way, so you have to use NanoVega transformations instead.
/// Returns `false` if there is no such glyph, or current font is not scalable.
/// Group: text_api
public bool charToPath (NVGContext ctx, dchar dch, float[] bounds=null) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  fonsSetFont(ctx.fs, state.fontId);
  return fonsToPath(ctx.fs, ctx, dch, bounds);
}

static if (is(typeof(&fons__nvg__bounds))) {
  public enum NanoVegaHasCharPathBounds = true; ///
} else {
  public enum NanoVegaHasCharPathBounds = false; ///
}

/// Returns bounds of the glyph outlines. Vertical 0 is baseline.
/// The glyph is not scaled in any way.
/// Returns `false` if there is no such glyph, or current font is not scalable.
/// Group: text_api
public bool charPathBounds (NVGContext ctx, dchar dch, float[] bounds) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  fonsSetFont(ctx.fs, state.fontId);
  return fonsPathBounds(ctx.fs, dch, bounds);
}

/** [charOutline] will return malloced [NVGGlyphOutline].

 some usage samples:

 ---
    float[4] bounds = void;

    nvg.scale(0.5, 0.5);
    nvg.translate(500, 800);
    nvg.evenOddFill;

    nvg.newPath();
    nvg.charToPath('&', bounds[]);
    conwriteln(bounds[]);
    nvg.fillPaint(nvg.linearGradient(0, 0, 600, 600, NVGColor("#f70"), NVGColor("#ff0")));
    nvg.strokeColor(NVGColor("#0f0"));
    nvg.strokeWidth = 3;
    nvg.fill();
    nvg.stroke();
    // glyph bounds
    nvg.newPath();
    nvg.rect(bounds[0], bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]);
    nvg.strokeColor(NVGColor("#00f"));
    nvg.stroke();

    nvg.newPath();
    nvg.charToPath('g', bounds[]);
    conwriteln(bounds[]);
    nvg.fill();
    nvg.strokeColor(NVGColor("#0f0"));
    nvg.stroke();
    // glyph bounds
    nvg.newPath();
    nvg.rect(bounds[0], bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]);
    nvg.strokeColor(NVGColor("#00f"));
    nvg.stroke();

    nvg.newPath();
    nvg.moveTo(0, 0);
    nvg.lineTo(600, 0);
    nvg.strokeColor(NVGColor("#0ff"));
    nvg.stroke();

    if (auto ol = nvg.charOutline('Q')) {
      scope(exit) ol.kill();
      nvg.newPath();
      conwriteln("==== length: ", ol.length, " ====");
      foreach (const ref cmd; ol.commands) {
        //conwriteln("  ", cmd.code, ": ", cmd.args[]);
        assert(cmd.valid);
        final switch (cmd.code) {
          case cmd.Kind.MoveTo: nvg.moveTo(cmd.args[0], cmd.args[1]); break;
          case cmd.Kind.LineTo: nvg.lineTo(cmd.args[0], cmd.args[1]); break;
          case cmd.Kind.QuadTo: nvg.quadTo(cmd.args[0], cmd.args[1], cmd.args[2], cmd.args[3]); break;
          case cmd.Kind.BezierTo: nvg.bezierTo(cmd.args[0], cmd.args[1], cmd.args[2], cmd.args[3], cmd.args[4], cmd.args[5]); break;
        }
      }
      nvg.strokeColor(NVGColor("#f00"));
      nvg.stroke();
    }
 ---

 Group: text_api
 */
public struct NVGGlyphOutline {
public:
  /// commands
  static struct Command {
    enum Kind : ubyte {
      MoveTo, ///
      LineTo, ///
      QuadTo, ///
      BezierTo, ///
    }
    Kind code; ///
    const(float)[] args; ///
    @property bool valid () const pure nothrow @safe @nogc { pragma(inline, true); return (code >= 0 && code <= 3 && args.length >= 2); } ///

    /// perform NanoVega command with stored data.
    void perform (NVGContext ctx) const nothrow @trusted @nogc {
      if (ctx is null) return;
      switch (code) {
        case Kind.MoveTo: if (args.length > 1) ctx.moveTo(args.ptr[0..2]); break;
        case Kind.LineTo: if (args.length > 1) ctx.lineTo(args.ptr[0..2]); break;
        case Kind.QuadTo: if (args.length > 3) ctx.quadTo(args.ptr[0..4]); break;
        case Kind.BezierTo: if (args.length > 5) ctx.bezierTo(args.ptr[0..6]); break;
        default: break;
      }
    }

    /// perform NanoVega command with stored data, transforming points with [xform] transformation matrix.
    void perform() (NVGContext ctx, in auto ref NVGMatrix xform) const nothrow @trusted @nogc {
      if (ctx is null || !valid) return;
      float[6] pts = void;
      pts[0..args.length] = args[];
      foreach (immutable pidx; 0..args.length/2) xform.point(pts.ptr[pidx*2+0], pts.ptr[pidx*2+1]);
      switch (code) {
        case Kind.MoveTo: if (args.length > 1) ctx.moveTo(pts.ptr[0..2]); break;
        case Kind.LineTo: if (args.length > 1) ctx.lineTo(pts.ptr[0..2]); break;
        case Kind.QuadTo: if (args.length > 3) ctx.quadTo(pts.ptr[0..4]); break;
        case Kind.BezierTo: if (args.length > 5) ctx.bezierTo(pts.ptr[0..6]); break;
        default: break;
      }
    }
  }

  @disable this (this); // no copies

private:
  ubyte* data;
  uint used;
  uint size;
  uint ccount; // number of commands

private:
  void clear () nothrow @trusted @nogc {
    import core.stdc.stdlib : free;
    if (data !is null) { free(data); data = null; }
    used = size = ccount = 0;
    bounds[] = 0;
  }

public:
  float[4] bounds = 0;

  @property int length () const pure { pragma(inline, true); return ccount; }

public:
  /// Returns forward range with all glyph commands.
  /// $(WARNING returned rande should not outlive parent struct!)
  auto commands () nothrow @trusted @nogc {
    static struct Range {
    private nothrow @trusted @nogc:
      const(ubyte)* data;
      uint cleft; // number of commands left
    public:
      @property bool empty () const pure { pragma(inline, true); return (cleft == 0); }
      @property int length () const pure { pragma(inline, true); return cleft; }
      @property Range save () const pure { pragma(inline, true); Range res = this; return res; }
      @property Command front () const {
        Command res = void;
        if (cleft > 0) {
          res.code = cast(Command.Kind)data[0];
          switch (res.code) {
            case Command.Kind.MoveTo:
            case Command.Kind.LineTo:
              res.args = (cast(const(float*))(data+1))[0..1*2];
              break;
            case Command.Kind.QuadTo:
              res.args = (cast(const(float*))(data+1))[0..2*2];
              break;
            case Command.Kind.BezierTo:
              res.args = (cast(const(float*))(data+1))[0..3*2];
              break;
            default:
              res.code = cast(Command.Kind)255;
              res.args = null;
              break;
          }
        } else {
          res.code = cast(Command.Kind)255;
          res.args = null;
        }
        return res;
      }
      void popFront () {
        if (cleft == 0) return;
        if (--cleft == 0) return; // don't waste time skipping last command
        switch (data[0]) {
          case Command.Kind.MoveTo:
          case Command.Kind.LineTo:
            data += 1+1*2*cast(uint)float.sizeof;
            break;
          case Command.Kind.QuadTo:
            data += 1+2*2*cast(uint)float.sizeof;
            break;
          case Command.Kind.BezierTo:
            data += 1+3*2*cast(uint)float.sizeof;
            break;
          default:
            cleft = 0;
            break;
        }
      }
    }
    return Range(data, ccount);
  }
}

/// Destroy glyph outiline and free allocated memory.
/// Group: text_api
public void kill (ref NVGGlyphOutline* ol) nothrow @trusted @nogc {
  if (ol !is null) {
    import core.stdc.stdlib : free;
    ol.clear();
    free(ol);
    ol = null;
  }
}

static if (is(typeof(&fons__nvg__toOutline))) {
  public enum NanoVegaHasCharOutline = true; ///
} else {
  public enum NanoVegaHasCharOutline = false; ///
}

/// Returns glyph outlines as array of commands. Vertical 0 is baseline.
/// The glyph is not scaled in any way, so you have to use NanoVega transformations instead.
/// Returns `null` if there is no such glyph, or current font is not scalable.
/// Group: text_api
public NVGGlyphOutline* charOutline (NVGContext ctx, dchar dch) nothrow @trusted @nogc {
  import core.stdc.stdlib : malloc;
  import core.stdc.string : memcpy;
  NVGstate* state = nvg__getState(ctx);
  fonsSetFont(ctx.fs, state.fontId);
  NVGGlyphOutline oline;
  if (!fonsToOutline(ctx.fs, dch, &oline)) { oline.clear(); return null; }
  auto res = cast(NVGGlyphOutline*)malloc(NVGGlyphOutline.sizeof);
  if (res is null) { oline.clear(); return null; }
  memcpy(res, &oline, oline.sizeof);
  return res;
}


float nvg__quantize (float a, float d) pure nothrow @safe @nogc {
  pragma(inline, true);
  return (cast(int)(a/d+0.5f))*d;
}

float nvg__getFontScale (NVGstate* state) nothrow @safe @nogc {
  pragma(inline, true);
  return nvg__min(nvg__quantize(nvg__getAverageScale(state.xform), 0.01f), 4.0f);
}

void nvg__flushTextTexture (NVGContext ctx) nothrow @trusted @nogc {
  int[4] dirty = void;
  if (fonsValidateTexture(ctx.fs, dirty.ptr)) {
    auto fontImage = &ctx.fontImages[ctx.fontImageIdx];
    // Update texture
    if (fontImage.valid) {
      int iw, ih;
      const(ubyte)* data = fonsGetTextureData(ctx.fs, &iw, &ih);
      int x = dirty[0];
      int y = dirty[1];
      int w = dirty[2]-dirty[0];
      int h = dirty[3]-dirty[1];
      ctx.params.renderUpdateTexture(ctx.params.userPtr, fontImage.id, x, y, w, h, data);
    }
  }
}

bool nvg__allocTextAtlas (NVGContext ctx) nothrow @trusted @nogc {
  int iw, ih;
  nvg__flushTextTexture(ctx);
  if (ctx.fontImageIdx >= NVG_MAX_FONTIMAGES-1) return false;
  // if next fontImage already have a texture
  if (ctx.fontImages[ctx.fontImageIdx+1].valid) {
    ctx.imageSize(ctx.fontImages[ctx.fontImageIdx+1], iw, ih);
  } else {
    // calculate the new font image size and create it
    ctx.imageSize(ctx.fontImages[ctx.fontImageIdx], iw, ih);
    if (iw > ih) ih *= 2; else iw *= 2;
    if (iw > NVG_MAX_FONTIMAGE_SIZE || ih > NVG_MAX_FONTIMAGE_SIZE) iw = ih = NVG_MAX_FONTIMAGE_SIZE;
    ctx.fontImages[ctx.fontImageIdx+1].id = ctx.params.renderCreateTexture(ctx.params.userPtr, NVGtexture.Alpha, iw, ih, (ctx.params.fontAA ? 0 : NVGImageFlag.NoFiltering), null);
    if (ctx.fontImages[ctx.fontImageIdx+1].id > 0) {
      ctx.fontImages[ctx.fontImageIdx+1].ctx = ctx;
      ctx.nvg__imageIncRef(ctx.fontImages[ctx.fontImageIdx+1].id);
    }
  }
  ++ctx.fontImageIdx;
  fonsResetAtlas(ctx.fs, iw, ih);
  return true;
}

void nvg__renderText (NVGContext ctx, NVGvertex* verts, int nverts) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);
  NVGPaint paint = state.fill;

  // Render triangles.
  paint.image = ctx.fontImages[ctx.fontImageIdx];

  // Apply global alpha
  paint.innerColor.a *= state.alpha;
  paint.middleColor.a *= state.alpha;
  paint.outerColor.a *= state.alpha;

  ctx.params.renderTriangles(ctx.params.userPtr, state.compositeOperation, NVGClipMode.None, &paint, &state.scissor, verts, nverts);

  ++ctx.drawCallCount;
  ctx.textTriCount += nverts/3;
}

/// Draws text string at specified location. Returns next x position.
/// Group: text_api
public float text(T) (NVGContext ctx, float x, float y, const(T)[] str) nothrow @trusted @nogc if (isAnyCharType!T) {
  NVGstate* state = nvg__getState(ctx);
  FONStextIter!T iter, prevIter;
  FONSquad q;
  NVGvertex* verts;
  float scale = nvg__getFontScale(state)*ctx.devicePxRatio;
  float invscale = 1.0f/scale;
  int cverts = 0;
  int nverts = 0;

  if (state.fontId == FONS_INVALID) return x;
  if (str.length == 0) return x;

  fonsSetSize(ctx.fs, state.fontSize*scale);
  fonsSetSpacing(ctx.fs, state.letterSpacing*scale);
  fonsSetBlur(ctx.fs, state.fontBlur*scale);
  fonsSetAlign(ctx.fs, state.textAlign);
  fonsSetFont(ctx.fs, state.fontId);

  cverts = nvg__max(2, cast(int)(str.length))*6; // conservative estimate
  verts = nvg__allocTempVerts(ctx, cverts);
  if (verts is null) return x;

  fonsTextIterInit(ctx.fs, &iter, x*scale, y*scale, str, FONS_GLYPH_BITMAP_REQUIRED);
  prevIter = iter;
  while (fonsTextIterNext(ctx.fs, &iter, &q)) {
    float[4*2] c = void;
    if (iter.prevGlyphIndex < 0) { // can not retrieve glyph?
      if (nverts != 0) {
        // TODO: add back-end bit to do this just once per frame
        nvg__flushTextTexture(ctx);
        nvg__renderText(ctx, verts, nverts);
        nverts = 0;
      }
      if (!nvg__allocTextAtlas(ctx)) break; // no memory :(
      iter = prevIter;
      fonsTextIterNext(ctx.fs, &iter, &q); // try again
      if (iter.prevGlyphIndex < 0) {
        // still can not find glyph, try replacement
        iter = prevIter;
        if (!fonsTextIterGetDummyChar(ctx.fs, &iter, &q)) break;
      }
    }
    prevIter = iter;
    // Transform corners.
    state.xform.point(&c[0], &c[1], q.x0*invscale, q.y0*invscale);
    state.xform.point(&c[2], &c[3], q.x1*invscale, q.y0*invscale);
    state.xform.point(&c[4], &c[5], q.x1*invscale, q.y1*invscale);
    state.xform.point(&c[6], &c[7], q.x0*invscale, q.y1*invscale);
    // Create triangles
    if (nverts+6 <= cverts) {
      nvg__vset(&verts[nverts], c[0], c[1], q.s0, q.t0); ++nverts;
      nvg__vset(&verts[nverts], c[4], c[5], q.s1, q.t1); ++nverts;
      nvg__vset(&verts[nverts], c[2], c[3], q.s1, q.t0); ++nverts;
      nvg__vset(&verts[nverts], c[0], c[1], q.s0, q.t0); ++nverts;
      nvg__vset(&verts[nverts], c[6], c[7], q.s0, q.t1); ++nverts;
      nvg__vset(&verts[nverts], c[4], c[5], q.s1, q.t1); ++nverts;
    }
  }

  // TODO: add back-end bit to do this just once per frame
  if (nverts > 0) {
    nvg__flushTextTexture(ctx);
    nvg__renderText(ctx, verts, nverts);
  }

  return iter.nextx/scale;
}

/** Draws multi-line text string at specified location wrapped at the specified width.
 * White space is stripped at the beginning of the rows, the text is split at word boundaries or when new-line characters are encountered.
 * Words longer than the max width are slit at nearest character (i.e. no hyphenation).
 *
 * Group: text_api
 */
public void textBox(T) (NVGContext ctx, float x, float y, float breakRowWidth, const(T)[] str) nothrow @trusted @nogc if (isAnyCharType!T) {
  NVGstate* state = nvg__getState(ctx);
  if (state.fontId == FONS_INVALID) return;

  NVGTextRow!T[2] rows;
  auto oldAlign = state.textAlign;
  scope(exit) state.textAlign = oldAlign;
  auto halign = state.textAlign.horizontal;
  float lineh = 0;

  ctx.textMetrics(null, null, &lineh);
  state.textAlign.horizontal = NVGTextAlign.H.Left;
  for (;;) {
    auto rres = ctx.textBreakLines(str, breakRowWidth, rows[]);
    //{ import core.stdc.stdio : printf; printf("slen=%u; rlen=%u; bw=%f\n", cast(uint)str.length, cast(uint)rres.length, cast(double)breakRowWidth); }
    if (rres.length == 0) break;
    foreach (ref row; rres) {
      final switch (halign) {
        case NVGTextAlign.H.Left: ctx.text(x, y, row.row); break;
        case NVGTextAlign.H.Center: ctx.text(x+breakRowWidth*0.5f-row.width*0.5f, y, row.row); break;
        case NVGTextAlign.H.Right: ctx.text(x+breakRowWidth-row.width, y, row.row); break;
      }
      y += lineh*state.lineHeight;
    }
    str = rres[$-1].rest;
  }
}

private template isGoodPositionDelegate(DG) {
  private DG dg;
  static if (is(typeof({ NVGGlyphPosition pos; bool res = dg(pos); })) ||
             is(typeof({ NVGGlyphPosition pos; dg(pos); })))
    enum isGoodPositionDelegate = true;
  else
    enum isGoodPositionDelegate = false;
}

/** Calculates the glyph x positions of the specified text.
 * Measured values are returned in local coordinate space.
 *
 * Group: text_api
 */
public NVGGlyphPosition[] textGlyphPositions(T) (NVGContext ctx, float x, float y, const(T)[] str, NVGGlyphPosition[] positions) nothrow @trusted @nogc
if (isAnyCharType!T)
{
  if (str.length == 0 || positions.length == 0) return positions[0..0];
  usize posnum;
  auto len = ctx.textGlyphPositions(x, y, str, (in ref NVGGlyphPosition pos) {
    positions.ptr[posnum++] = pos;
    return (posnum < positions.length);
  });
  return positions[0..len];
}

/// Ditto.
public int textGlyphPositions(T, DG) (NVGContext ctx, float x, float y, const(T)[] str, scope DG dg)
if (isAnyCharType!T && isGoodPositionDelegate!DG)
{
  import std.traits : ReturnType;
  static if (is(ReturnType!dg == void)) enum RetBool = false; else enum RetBool = true;

  NVGstate* state = nvg__getState(ctx);
  float scale = nvg__getFontScale(state)*ctx.devicePxRatio;
  float invscale = 1.0f/scale;
  FONStextIter!T iter, prevIter;
  FONSquad q;
  int npos = 0;

  if (str.length == 0) return 0;

  fonsSetSize(ctx.fs, state.fontSize*scale);
  fonsSetSpacing(ctx.fs, state.letterSpacing*scale);
  fonsSetBlur(ctx.fs, state.fontBlur*scale);
  fonsSetAlign(ctx.fs, state.textAlign);
  fonsSetFont(ctx.fs, state.fontId);

  fonsTextIterInit(ctx.fs, &iter, x*scale, y*scale, str, FONS_GLYPH_BITMAP_OPTIONAL);
  prevIter = iter;
  while (fonsTextIterNext(ctx.fs, &iter, &q)) {
    if (iter.prevGlyphIndex < 0) { // can not retrieve glyph?
      if (!nvg__allocTextAtlas(ctx)) break; // no memory
      iter = prevIter;
      fonsTextIterNext(ctx.fs, &iter, &q); // try again
      if (iter.prevGlyphIndex < 0) {
        // still can not find glyph, try replacement
        iter = prevIter;
        if (!fonsTextIterGetDummyChar(ctx.fs, &iter, &q)) break;
      }
    }
    prevIter = iter;
    NVGGlyphPosition position = void; //WARNING!
    position.strpos = cast(usize)(iter.string-str.ptr);
    position.x = iter.x*invscale;
    position.minx = nvg__min(iter.x, q.x0)*invscale;
    position.maxx = nvg__max(iter.nextx, q.x1)*invscale;
    ++npos;
    static if (RetBool) { if (!dg(position)) return npos; } else dg(position);
  }

  return npos;
}

private template isGoodRowDelegate(CT, DG) {
  private DG dg;
  static if (is(typeof({ NVGTextRow!CT row; bool res = dg(row); })) ||
             is(typeof({ NVGTextRow!CT row; dg(row); })))
    enum isGoodRowDelegate = true;
  else
    enum isGoodRowDelegate = false;
}

/** Breaks the specified text into lines.
 * White space is stripped at the beginning of the rows, the text is split at word boundaries or when new-line characters are encountered.
 * Words longer than the max width are slit at nearest character (i.e. no hyphenation).
 *
 * Group: text_api
 */
public NVGTextRow!T[] textBreakLines(T) (NVGContext ctx, const(T)[] str, float breakRowWidth, NVGTextRow!T[] rows) nothrow @trusted @nogc
if (isAnyCharType!T)
{
  if (rows.length == 0) return rows;
  if (rows.length > int.max-1) rows = rows[0..int.max-1];
  int nrow = 0;
  auto count = ctx.textBreakLines(str, breakRowWidth, (in ref NVGTextRow!T row) {
    rows[nrow++] = row;
    return (nrow < rows.length);
  });
  return rows[0..count];
}

/// Ditto.
public int textBreakLines(T, DG) (NVGContext ctx, const(T)[] str, float breakRowWidth, scope DG dg)
if (isAnyCharType!T && isGoodRowDelegate!(T, DG))
{
  import std.traits : ReturnType;
  static if (is(ReturnType!dg == void)) enum RetBool = false; else enum RetBool = true;

  enum NVGcodepointType : int {
    Space,
    NewLine,
    Char,
  }

  NVGstate* state = nvg__getState(ctx);
  float scale = nvg__getFontScale(state)*ctx.devicePxRatio;
  float invscale = 1.0f/scale;
  FONStextIter!T iter, prevIter;
  FONSquad q;
  int nrows = 0;
  float rowStartX = 0;
  float rowWidth = 0;
  float rowMinX = 0;
  float rowMaxX = 0;
  int rowStart = 0;
  int rowEnd = 0;
  int wordStart = 0;
  float wordStartX = 0;
  float wordMinX = 0;
  int breakEnd = 0;
  float breakWidth = 0;
  float breakMaxX = 0;
  int type = NVGcodepointType.Space, ptype = NVGcodepointType.Space;
  uint pcodepoint = 0;

  if (state.fontId == FONS_INVALID) return 0;
  if (str.length == 0 || dg is null) return 0;

  fonsSetSize(ctx.fs, state.fontSize*scale);
  fonsSetSpacing(ctx.fs, state.letterSpacing*scale);
  fonsSetBlur(ctx.fs, state.fontBlur*scale);
  fonsSetAlign(ctx.fs, state.textAlign);
  fonsSetFont(ctx.fs, state.fontId);

  breakRowWidth *= scale;

  enum Phase {
    Normal, // searching for breaking point
    SkipBlanks, // skip leading blanks
  }
  Phase phase = Phase.SkipBlanks; // don't skip blanks on first line

  fonsTextIterInit(ctx.fs, &iter, 0, 0, str, FONS_GLYPH_BITMAP_OPTIONAL);
  prevIter = iter;
  while (fonsTextIterNext(ctx.fs, &iter, &q)) {
    if (iter.prevGlyphIndex < 0) { // can not retrieve glyph?
      if (!nvg__allocTextAtlas(ctx)) break; // no memory
      iter = prevIter;
      fonsTextIterNext(ctx.fs, &iter, &q); // try again
      if (iter.prevGlyphIndex < 0) {
        // still can not find glyph, try replacement
        iter = prevIter;
        if (!fonsTextIterGetDummyChar(ctx.fs, &iter, &q)) break;
      }
    }
    prevIter = iter;
    switch (iter.codepoint) {
      case 9: // \t
      case 11: // \v
      case 12: // \f
      case 32: // space
      case 0x00a0: // NBSP
        type = NVGcodepointType.Space;
        break;
      case 10: // \n
        type = (pcodepoint == 13 ? NVGcodepointType.Space : NVGcodepointType.NewLine);
        break;
      case 13: // \r
        type = (pcodepoint == 10 ? NVGcodepointType.Space : NVGcodepointType.NewLine);
        break;
      case 0x0085: // NEL
      case 0x2028: // Line Separator
      case 0x2029: // Paragraph Separator
        type = NVGcodepointType.NewLine;
        break;
      default:
        type = NVGcodepointType.Char;
        break;
    }
    if (phase == Phase.SkipBlanks) {
      // fix row start
      rowStart = cast(int)(iter.string-str.ptr);
      rowEnd = rowStart;
      rowStartX = iter.x;
      rowWidth = iter.nextx-rowStartX; // q.x1-rowStartX;
      rowMinX = q.x0-rowStartX;
      rowMaxX = q.x1-rowStartX;
      wordStart = rowStart;
      wordStartX = iter.x;
      wordMinX = q.x0-rowStartX;
      breakEnd = rowStart;
      breakWidth = 0.0;
      breakMaxX = 0.0;
      if (type == NVGcodepointType.Space) continue;
      phase = Phase.Normal;
    }

    if (type == NVGcodepointType.NewLine) {
      // always handle new lines
      NVGTextRow!T row;
      row.string = str;
      row.start = rowStart;
      row.end = rowEnd;
      row.width = rowWidth*invscale;
      row.minx = rowMinX*invscale;
      row.maxx = rowMaxX*invscale;
      ++nrows;
      static if (RetBool) { if (!dg(row)) return nrows; } else dg(row);
      phase = Phase.SkipBlanks;
    } else {
      float nextWidth = iter.nextx-rowStartX;
      // track last non-white space character
      if (type == NVGcodepointType.Char) {
        rowEnd = cast(int)(iter.nextp-str.ptr);
        rowWidth = iter.nextx-rowStartX;
        rowMaxX = q.x1-rowStartX;
      }
      // track last end of a word
      if (ptype == NVGcodepointType.Char && type == NVGcodepointType.Space) {
        breakEnd = cast(int)(iter.string-str.ptr);
        breakWidth = rowWidth;
        breakMaxX = rowMaxX;
      }
      // track last beginning of a word
      if (ptype == NVGcodepointType.Space && type == NVGcodepointType.Char) {
        wordStart = cast(int)(iter.string-str.ptr);
        wordStartX = iter.x;
        wordMinX = q.x0-rowStartX;
      }
      // break to new line when a character is beyond break width
      if (type == NVGcodepointType.Char && nextWidth > breakRowWidth) {
        // the run length is too long, need to break to new line
        NVGTextRow!T row;
        row.string = str;
        if (breakEnd == rowStart) {
          // the current word is longer than the row length, just break it from here
          row.start = rowStart;
          row.end = cast(int)(iter.string-str.ptr);
          row.width = rowWidth*invscale;
          row.minx = rowMinX*invscale;
          row.maxx = rowMaxX*invscale;
          ++nrows;
          static if (RetBool) { if (!dg(row)) return nrows; } else dg(row);
          rowStartX = iter.x;
          rowStart = cast(int)(iter.string-str.ptr);
          rowEnd = cast(int)(iter.nextp-str.ptr);
          rowWidth = iter.nextx-rowStartX;
          rowMinX = q.x0-rowStartX;
          rowMaxX = q.x1-rowStartX;
          wordStart = rowStart;
          wordStartX = iter.x;
          wordMinX = q.x0-rowStartX;
        } else {
          // break the line from the end of the last word, and start new line from the beginning of the new
          //{ import core.stdc.stdio : printf; printf("rowStart=%u; rowEnd=%u; breakEnd=%u; len=%u\n", rowStart, rowEnd, breakEnd, cast(uint)str.length); }
          row.start = rowStart;
          row.end = breakEnd;
          row.width = breakWidth*invscale;
          row.minx = rowMinX*invscale;
          row.maxx = breakMaxX*invscale;
          ++nrows;
          static if (RetBool) { if (!dg(row)) return nrows; } else dg(row);
          rowStartX = wordStartX;
          rowStart = wordStart;
          rowEnd = cast(int)(iter.nextp-str.ptr);
          rowWidth = iter.nextx-rowStartX;
          rowMinX = wordMinX;
          rowMaxX = q.x1-rowStartX;
          // no change to the word start
        }
        // set null break point
        breakEnd = rowStart;
        breakWidth = 0.0;
        breakMaxX = 0.0;
      }
    }

    pcodepoint = iter.codepoint;
    ptype = type;
  }

  // break the line from the end of the last word, and start new line from the beginning of the new
  if (phase != Phase.SkipBlanks && rowStart < str.length) {
    //{ import core.stdc.stdio : printf; printf("  rowStart=%u; len=%u\n", rowStart, cast(uint)str.length); }
    NVGTextRow!T row;
    row.string = str;
    row.start = rowStart;
    row.end = cast(int)str.length;
    row.width = rowWidth*invscale;
    row.minx = rowMinX*invscale;
    row.maxx = rowMaxX*invscale;
    ++nrows;
    static if (RetBool) { if (!dg(row)) return nrows; } else dg(row);
  }

  return nrows;
}

/** Returns iterator which you can use to calculate text bounds and advancement.
 * This is usable when you need to do some text layouting with wrapping, to avoid
 * guesswork ("will advancement for this space stay the same?"), and Schlemiel's
 * algorithm. Note that you can copy the returned struct to save iterator state.
 *
 * You can check if iterator is valid with [valid] property, put new chars with
 * [put] method, get current advance with [advance] property, and current
 * bounds with `getBounds(ref float[4] bounds)` method.
 *
 * $(WARNING Don't change font parameters while iterating! Or use [restoreFont] method.)
 *
 * Group: text_api
 */
public struct TextBoundsIterator {
private:
  NVGContext ctx;
  FonsTextBoundsIterator fsiter; // fontstash iterator
  float scale, invscale, xscaled, yscaled;
  // font settings
  float fsSize, fsSpacing, fsBlur;
  int fsFontId;
  NVGTextAlign fsAlign;

public:
  this (NVGContext actx, float ax, float ay) nothrow @trusted @nogc { reset(actx, ax, ay); }

  void reset (NVGContext actx, float ax, float ay) nothrow @trusted @nogc {
    fsiter = fsiter.init;
    this = this.init;
    if (actx is null) return;
    NVGstate* state = nvg__getState(actx);
    if (state is null) return;
    if (state.fontId == FONS_INVALID) { ctx = null; return; }

    ctx = actx;
    scale = nvg__getFontScale(state)*ctx.devicePxRatio;
    invscale = 1.0f/scale;

    fsSize = state.fontSize*scale;
    fsSpacing = state.letterSpacing*scale;
    fsBlur = state.fontBlur*scale;
    fsAlign = state.textAlign;
    fsFontId = state.fontId;
    restoreFont();

    xscaled = ax*scale;
    yscaled = ay*scale;
    fsiter.reset(ctx.fs, xscaled, yscaled);
  }

  /// Restart iteration. Will not restore font.
  void restart () nothrow @trusted @nogc {
    if (ctx !is null) fsiter.reset(ctx.fs, xscaled, yscaled);
  }

  /// Restore font settings for the context.
  void restoreFont () nothrow @trusted @nogc {
    if (ctx !is null) {
      fonsSetSize(ctx.fs, fsSize);
      fonsSetSpacing(ctx.fs, fsSpacing);
      fonsSetBlur(ctx.fs, fsBlur);
      fonsSetAlign(ctx.fs, fsAlign);
      fonsSetFont(ctx.fs, fsFontId);
    }
  }

  /// Is this iterator valid?
  @property bool valid () const pure nothrow @safe @nogc { pragma(inline, true); return (ctx !is null); }

  /// Add chars.
  void put(T) (const(T)[] str...) nothrow @trusted @nogc if (isAnyCharType!T) { pragma(inline, true); if (ctx !is null) fsiter.put(str[]); }

  /// Returns current advance
  @property float advance () const pure nothrow @safe @nogc { pragma(inline, true); return (ctx !is null ? fsiter.advance*invscale : 0); }

  /// Returns current text bounds.
  void getBounds (ref float[4] bounds) nothrow @trusted @nogc {
    if (ctx !is null) {
      fsiter.getBounds(bounds);
      fonsLineBounds(ctx.fs, yscaled, &bounds[1], &bounds[3]);
      bounds[0] *= invscale;
      bounds[1] *= invscale;
      bounds[2] *= invscale;
      bounds[3] *= invscale;
    } else {
      bounds[] = 0;
    }
  }

  /// Returns current horizontal text bounds.
  void getHBounds (out float xmin, out float xmax) nothrow @trusted @nogc {
    if (ctx !is null) {
      fsiter.getHBounds(xmin, xmax);
      xmin *= invscale;
      xmax *= invscale;
    }
  }

  /// Returns current vertical text bounds.
  void getVBounds (out float ymin, out float ymax) nothrow @trusted @nogc {
    if (ctx !is null) {
      //fsiter.getVBounds(ymin, ymax);
      fonsLineBounds(ctx.fs, yscaled, &ymin, &ymax);
      ymin *= invscale;
      ymax *= invscale;
    }
  }
}

/// Returns font line height (without line spacing), measured in local coordinate space.
/// Group: text_api
public float textFontHeight (NVGContext ctx) nothrow @trusted @nogc {
  float res = void;
  ctx.textMetrics(null, null, &res);
  return res;
}

/// Returns font ascender (positive), measured in local coordinate space.
/// Group: text_api
public float textFontAscender (NVGContext ctx) nothrow @trusted @nogc {
  float res = void;
  ctx.textMetrics(&res, null, null);
  return res;
}

/// Returns font descender (negative), measured in local coordinate space.
/// Group: text_api
public float textFontDescender (NVGContext ctx) nothrow @trusted @nogc {
  float res = void;
  ctx.textMetrics(null, &res, null);
  return res;
}

/** Measures the specified text string. Returns horizontal and vertical sizes of the measured text.
 * Measured values are returned in local coordinate space.
 *
 * Group: text_api
 */
public void textExtents(T) (NVGContext ctx, const(T)[] str, float *w, float *h) nothrow @trusted @nogc if (isAnyCharType!T) {
  float[4] bnd = void;
  ctx.textBounds(0, 0, str, bnd[]);
  if (!fonsGetFontAA(ctx.fs, nvg__getState(ctx).fontId)) {
    if (w !is null) *w = nvg__lrintf(bnd.ptr[2]-bnd.ptr[0]);
    if (h !is null) *h = nvg__lrintf(bnd.ptr[3]-bnd.ptr[1]);
  } else {
    if (w !is null) *w = bnd.ptr[2]-bnd.ptr[0];
    if (h !is null) *h = bnd.ptr[3]-bnd.ptr[1];
  }
}

/** Measures the specified text string. Returns horizontal size of the measured text.
 * Measured values are returned in local coordinate space.
 *
 * Group: text_api
 */
public float textWidth(T) (NVGContext ctx, const(T)[] str) nothrow @trusted @nogc if (isAnyCharType!T) {
  float w = void;
  ctx.textExtents(str, &w, null);
  return w;
}

/** Measures the specified text string. Parameter bounds should be a float[4],
 * if the bounding box of the text should be returned. The bounds value are [xmin, ymin, xmax, ymax]
 * Returns the horizontal advance of the measured text (i.e. where the next character should drawn).
 * Measured values are returned in local coordinate space.
 *
 * Group: text_api
 */
public float textBounds(T) (NVGContext ctx, float x, float y, const(T)[] str, float[] bounds) nothrow @trusted @nogc
if (isAnyCharType!T)
{
  NVGstate* state = nvg__getState(ctx);
  float scale = nvg__getFontScale(state)*ctx.devicePxRatio;
  float invscale = 1.0f/scale;
  float width;

  if (state.fontId == FONS_INVALID) {
    bounds[] = 0;
    return 0;
  }

  fonsSetSize(ctx.fs, state.fontSize*scale);
  fonsSetSpacing(ctx.fs, state.letterSpacing*scale);
  fonsSetBlur(ctx.fs, state.fontBlur*scale);
  fonsSetAlign(ctx.fs, state.textAlign);
  fonsSetFont(ctx.fs, state.fontId);

  float[4] b = void;
  width = fonsTextBounds(ctx.fs, x*scale, y*scale, str, b[]);
  if (bounds.length) {
    // use line bounds for height
    fonsLineBounds(ctx.fs, y*scale, b.ptr+1, b.ptr+3);
    if (bounds.length > 0) bounds.ptr[0] = b.ptr[0]*invscale;
    if (bounds.length > 1) bounds.ptr[1] = b.ptr[1]*invscale;
    if (bounds.length > 2) bounds.ptr[2] = b.ptr[2]*invscale;
    if (bounds.length > 3) bounds.ptr[3] = b.ptr[3]*invscale;
  }
  return width*invscale;
}

/// Ditto.
public void textBoxBounds(T) (NVGContext ctx, float x, float y, float breakRowWidth, const(T)[] str, float[] bounds) if (isAnyCharType!T) {
  NVGstate* state = nvg__getState(ctx);
  NVGTextRow!T[2] rows;
  float scale = nvg__getFontScale(state)*ctx.devicePxRatio;
  float invscale = 1.0f/scale;
  float lineh = 0, rminy = 0, rmaxy = 0;
  float minx, miny, maxx, maxy;

  if (state.fontId == FONS_INVALID) {
    bounds[] = 0;
    return;
  }

  auto oldAlign = state.textAlign;
  scope(exit) state.textAlign = oldAlign;
  auto halign = state.textAlign.horizontal;

  ctx.textMetrics(null, null, &lineh);
  state.textAlign.horizontal = NVGTextAlign.H.Left;

  minx = maxx = x;
  miny = maxy = y;

  fonsSetSize(ctx.fs, state.fontSize*scale);
  fonsSetSpacing(ctx.fs, state.letterSpacing*scale);
  fonsSetBlur(ctx.fs, state.fontBlur*scale);
  fonsSetAlign(ctx.fs, state.textAlign);
  fonsSetFont(ctx.fs, state.fontId);
  fonsLineBounds(ctx.fs, 0, &rminy, &rmaxy);
  rminy *= invscale;
  rmaxy *= invscale;

  for (;;) {
    auto rres = ctx.textBreakLines(str, breakRowWidth, rows[]);
    if (rres.length == 0) break;
    foreach (ref row; rres) {
      float rminx, rmaxx, dx = 0;
      // horizontal bounds
      final switch (halign) {
        case NVGTextAlign.H.Left: dx = 0; break;
        case NVGTextAlign.H.Center: dx = breakRowWidth*0.5f-row.width*0.5f; break;
        case NVGTextAlign.H.Right: dx = breakRowWidth-row.width; break;
      }
      rminx = x+row.minx+dx;
      rmaxx = x+row.maxx+dx;
      minx = nvg__min(minx, rminx);
      maxx = nvg__max(maxx, rmaxx);
      // vertical bounds
      miny = nvg__min(miny, y+rminy);
      maxy = nvg__max(maxy, y+rmaxy);
      y += lineh*state.lineHeight;
    }
    str = rres[$-1].rest;
  }

  if (bounds.length) {
    if (bounds.length > 0) bounds.ptr[0] = minx;
    if (bounds.length > 1) bounds.ptr[1] = miny;
    if (bounds.length > 2) bounds.ptr[2] = maxx;
    if (bounds.length > 3) bounds.ptr[3] = maxy;
  }
}

/// Returns the vertical metrics based on the current text style. Measured values are returned in local coordinate space.
/// Group: text_api
public void textMetrics (NVGContext ctx, float* ascender, float* descender, float* lineh) nothrow @trusted @nogc {
  NVGstate* state = nvg__getState(ctx);

  if (state.fontId == FONS_INVALID) {
    if (ascender !is null) *ascender *= 0;
    if (descender !is null) *descender *= 0;
    if (lineh !is null) *lineh *= 0;
    return;
  }

  immutable float scale = nvg__getFontScale(state)*ctx.devicePxRatio;
  immutable float invscale = 1.0f/scale;

  fonsSetSize(ctx.fs, state.fontSize*scale);
  fonsSetSpacing(ctx.fs, state.letterSpacing*scale);
  fonsSetBlur(ctx.fs, state.fontBlur*scale);
  fonsSetAlign(ctx.fs, state.textAlign);
  fonsSetFont(ctx.fs, state.fontId);

  fonsVertMetrics(ctx.fs, ascender, descender, lineh);
  if (ascender !is null) *ascender *= invscale;
  if (descender !is null) *descender *= invscale;
  if (lineh !is null) *lineh *= invscale;
}


// ////////////////////////////////////////////////////////////////////////// //
// fontstash
// ////////////////////////////////////////////////////////////////////////// //
import core.stdc.stdlib : malloc, realloc, free;
import core.stdc.string : memset, memcpy, strncpy, strcmp, strlen;
import core.stdc.stdio : FILE, fopen, fclose, fseek, ftell, fread, SEEK_END, SEEK_SET;

public:
// welcome to version hell!
version(nanovg_force_detect) {} else version(nanovg_use_freetype) { version = nanovg_use_freetype_ii; }
version(nanovg_ignore_iv_stb_ttf) enum nanovg_ignore_iv_stb_ttf = true; else enum nanovg_ignore_iv_stb_ttf = false;
//version(nanovg_ignore_mono);

version (nanovg_builtin_freetype_bindings) {
  version(Posix) {
    private enum NanoVegaForceFreeType = true;
  } else {
    private enum NanoVegaForceFreeType = false;
  }
} else {
  version(Posix) {
    private enum NanoVegaForceFreeType = true;
  } else {
    private enum NanoVegaForceFreeType = false;
  }
}

version(nanovg_use_freetype_ii) {
  enum NanoVegaIsUsingSTBTTF = false;
  //pragma(msg, "iv.freetype: forced");
} else {
  static if (NanoVegaForceFreeType) {
    enum NanoVegaIsUsingSTBTTF = false;
  } else {
    static if (!nanovg_ignore_iv_stb_ttf && __traits(compiles, { import iv.stb.ttf; })) {
      import iv.stb.ttf;
      enum NanoVegaIsUsingSTBTTF = true;
      //pragma(msg, "iv.stb.ttf");
    } else static if (__traits(compiles, { import arsd.ttf; })) {
      import arsd.ttf;
      enum NanoVegaIsUsingSTBTTF = true;
      //pragma(msg, "arsd.ttf");
    } else static if (__traits(compiles, { import stb_truetype; })) {
      import stb_truetype;
      enum NanoVegaIsUsingSTBTTF = true;
      //pragma(msg, "stb_truetype");
    } else static if (__traits(compiles, { import iv.freetype; })) {
      version (nanovg_builtin_freetype_bindings) {
        enum NanoVegaIsUsingSTBTTF = false;
        version = nanovg_builtin_freetype_bindings;
      } else {
        import iv.freetype;
        enum NanoVegaIsUsingSTBTTF = false;
      }
      //pragma(msg, "iv.freetype");
    } else {
      static assert(0, "no stb_ttf/iv.freetype found!");
    }
  }
}

//version = nanovg_kill_font_blur;


// ////////////////////////////////////////////////////////////////////////// //
//version = nanovg_ft_mono;

enum FONS_INVALID = -1;

alias FONSflags = int;
enum /*FONSflags*/ {
  FONS_ZERO_TOPLEFT    = 1<<0,
  FONS_ZERO_BOTTOMLEFT = 1<<1,
}

/+
alias FONSalign = int;
enum /*FONSalign*/ {
  // Horizontal align
  FONS_ALIGN_LEFT   = 1<<0, // Default
  FONS_ALIGN_CENTER   = 1<<1,
  FONS_ALIGN_RIGHT  = 1<<2,
  // Vertical align
  FONS_ALIGN_TOP    = 1<<3,
  FONS_ALIGN_MIDDLE = 1<<4,
  FONS_ALIGN_BOTTOM = 1<<5,
  FONS_ALIGN_BASELINE = 1<<6, // Default
}
+/

alias FONSglyphBitmap = int;
enum /*FONSglyphBitmap*/ {
  FONS_GLYPH_BITMAP_OPTIONAL = 1,
  FONS_GLYPH_BITMAP_REQUIRED = 2,
}

alias FONSerrorCode = int;
enum /*FONSerrorCode*/ {
  // Font atlas is full.
  FONS_ATLAS_FULL = 1,
  // Scratch memory used to render glyphs is full, requested size reported in 'val', you may need to bump up FONS_SCRATCH_BUF_SIZE.
  FONS_SCRATCH_FULL = 2,
  // Calls to fonsPushState has created too large stack, if you need deep state stack bump up FONS_MAX_STATES.
  FONS_STATES_OVERFLOW = 3,
  // Trying to pop too many states fonsPopState().
  FONS_STATES_UNDERFLOW = 4,
}

struct FONSparams {
  int width, height;
  ubyte flags;
  void* userPtr;
  bool function (void* uptr, int width, int height) nothrow @trusted @nogc renderCreate;
  int function (void* uptr, int width, int height) nothrow @trusted @nogc renderResize;
  void function (void* uptr, int* rect, const(ubyte)* data) nothrow @trusted @nogc renderUpdate;
  debug(nanovega) {
    void function (void* uptr, const(float)* verts, const(float)* tcoords, const(uint)* colors, int nverts) nothrow @trusted @nogc renderDraw;
  }
  void function (void* uptr) nothrow @trusted @nogc renderDelete;
}

struct FONSquad {
  float x0=0, y0=0, s0=0, t0=0;
  float x1=0, y1=0, s1=0, t1=0;
}

struct FONStextIter(CT) if (isAnyCharType!CT) {
  alias CharType = CT;
  float x=0, y=0, nextx=0, nexty=0, scale=0, spacing=0;
  uint codepoint;
  short isize, iblur;
  FONSfont* font;
  int prevGlyphIndex;
  const(CT)* s; // string
  const(CT)* n; // next
  const(CT)* e; // end
  FONSglyphBitmap bitmapOption;
  static if (is(CT == char)) {
    uint utf8state;
  }
  ~this () nothrow @trusted @nogc { pragma(inline, true); static if (is(CT == char)) utf8state = 0; s = n = e = null; }
  @property const(CT)* string () const pure nothrow @nogc { pragma(inline, true); return s; }
  @property const(CT)* nextp () const pure nothrow @nogc { pragma(inline, true); return n; }
  @property const(CT)* endp () const pure nothrow @nogc { pragma(inline, true); return e; }
}


// ////////////////////////////////////////////////////////////////////////// //
//static if (!HasAST) version = nanovg_use_freetype_ii_x;

/*version(nanovg_use_freetype_ii_x)*/ static if (!NanoVegaIsUsingSTBTTF) {
version(nanovg_builtin_freetype_bindings) {
pragma(lib, "freetype");
private extern(C) nothrow @trusted @nogc {
private import core.stdc.config : c_long, c_ulong;
alias FT_Pos = c_long;
// config/ftconfig.h
alias FT_Int16 = short;
alias FT_UInt16 = ushort;
alias FT_Int32 = int;
alias FT_UInt32 = uint;
alias FT_Fast = int;
alias FT_UFast = uint;
alias FT_Int64 = long;
alias FT_Uint64 = ulong;
// fttypes.h
alias FT_Bool = ubyte;
alias FT_FWord = short;
alias FT_UFWord = ushort;
alias FT_Char = char;
alias FT_Byte = ubyte;
alias FT_Bytes = FT_Byte*;
alias FT_Tag = FT_UInt32;
alias FT_String = char;
alias FT_Short = short;
alias FT_UShort = ushort;
alias FT_Int = int;
alias FT_UInt = uint;
alias FT_Long = c_long;
alias FT_ULong = c_ulong;
alias FT_F2Dot14 = short;
alias FT_F26Dot6 = c_long;
alias FT_Fixed = c_long;
alias FT_Error = int;
alias FT_Pointer = void*;
alias FT_Offset = usize;
alias FT_PtrDist = ptrdiff_t;

struct FT_UnitVector {
  FT_F2Dot14 x;
  FT_F2Dot14 y;
}

struct FT_Matrix {
  FT_Fixed xx, xy;
  FT_Fixed yx, yy;
}

struct FT_Data {
  const(FT_Byte)* pointer;
  FT_Int length;
}
alias FT_Face = FT_FaceRec*;
struct FT_FaceRec {
  FT_Long num_faces;
  FT_Long face_index;
  FT_Long face_flags;
  FT_Long style_flags;
  FT_Long num_glyphs;
  FT_String* family_name;
  FT_String* style_name;
  FT_Int num_fixed_sizes;
  FT_Bitmap_Size* available_sizes;
  FT_Int num_charmaps;
  FT_CharMap* charmaps;
  FT_Generic generic;
  FT_BBox bbox;
  FT_UShort units_per_EM;
  FT_Short ascender;
  FT_Short descender;
  FT_Short height;
  FT_Short max_advance_width;
  FT_Short max_advance_height;
  FT_Short underline_position;
  FT_Short underline_thickness;
  FT_GlyphSlot glyph;
  FT_Size size;
  FT_CharMap charmap;
  FT_Driver driver;
  FT_Memory memory;
  FT_Stream stream;
  FT_ListRec sizes_list;
  FT_Generic autohint;
  void* extensions;
  FT_Face_Internal internal;
}
struct FT_Bitmap_Size {
  FT_Short height;
  FT_Short width;
  FT_Pos size;
  FT_Pos x_ppem;
  FT_Pos y_ppem;
}
alias FT_CharMap = FT_CharMapRec*;
struct FT_CharMapRec {
  FT_Face face;
  FT_Encoding encoding;
  FT_UShort platform_id;
  FT_UShort encoding_id;
}
extern(C) nothrow @nogc { alias FT_Generic_Finalizer = void function (void* object); }
struct FT_Generic {
  void* data;
  FT_Generic_Finalizer finalizer;
}
struct FT_Vector {
  FT_Pos x;
  FT_Pos y;
}
struct FT_BBox {
  FT_Pos xMin, yMin;
  FT_Pos xMax, yMax;
}
alias FT_Pixel_Mode = int;
enum {
  FT_PIXEL_MODE_NONE = 0,
  FT_PIXEL_MODE_MONO,
  FT_PIXEL_MODE_GRAY,
  FT_PIXEL_MODE_GRAY2,
  FT_PIXEL_MODE_GRAY4,
  FT_PIXEL_MODE_LCD,
  FT_PIXEL_MODE_LCD_V,
  FT_PIXEL_MODE_MAX
}
struct FT_Bitmap {
  uint rows;
  uint width;
  int pitch;
  ubyte* buffer;
  ushort num_grays;
  ubyte pixel_mode;
  ubyte palette_mode;
  void* palette;
}
struct FT_Outline {
  short n_contours;
  short n_points;
  FT_Vector* points;
  byte* tags;
  short* contours;
  int flags;
}
alias FT_GlyphSlot = FT_GlyphSlotRec*;
struct FT_GlyphSlotRec {
  FT_Library library;
  FT_Face face;
  FT_GlyphSlot next;
  FT_UInt reserved;
  FT_Generic generic;
  FT_Glyph_Metrics metrics;
  FT_Fixed linearHoriAdvance;
  FT_Fixed linearVertAdvance;
  FT_Vector advance;
  FT_Glyph_Format format;
  FT_Bitmap bitmap;
  FT_Int bitmap_left;
  FT_Int bitmap_top;
  FT_Outline outline;
  FT_UInt num_subglyphs;
  FT_SubGlyph subglyphs;
  void* control_data;
  c_long control_len;
  FT_Pos lsb_delta;
  FT_Pos rsb_delta;
  void* other;
  FT_Slot_Internal internal;
}
alias FT_Size = FT_SizeRec*;
struct FT_SizeRec {
  FT_Face face;
  FT_Generic generic;
  FT_Size_Metrics metrics;
  FT_Size_Internal internal;
}
alias FT_Encoding = FT_Tag;
alias FT_Face_Internal = void*;
alias FT_Driver = void*;
alias FT_Memory = void*;
alias FT_Stream = void*;
alias FT_Library = void*;
alias FT_SubGlyph = void*;
alias FT_Slot_Internal = void*;
alias FT_Size_Internal = void*;
alias FT_ListNode = FT_ListNodeRec*;
alias FT_List = FT_ListRec*;
struct FT_ListNodeRec {
  FT_ListNode prev;
  FT_ListNode next;
  void* data;
}
struct FT_ListRec {
  FT_ListNode head;
  FT_ListNode tail;
}
struct FT_Glyph_Metrics {
  FT_Pos width;
  FT_Pos height;
  FT_Pos horiBearingX;
  FT_Pos horiBearingY;
  FT_Pos horiAdvance;
  FT_Pos vertBearingX;
  FT_Pos vertBearingY;
  FT_Pos vertAdvance;
}
alias FT_Glyph_Format = FT_Tag;
FT_Tag FT_MAKE_TAG (char x1, char x2, char x3, char x4) pure nothrow @safe @nogc {
  pragma(inline, true);
  return cast(FT_UInt32)((x1<<24)|(x2<<16)|(x3<<8)|x4);
}
enum : FT_Tag {
  FT_GLYPH_FORMAT_NONE = 0,
  FT_GLYPH_FORMAT_COMPOSITE = FT_MAKE_TAG('c','o','m','p'),
  FT_GLYPH_FORMAT_BITMAP = FT_MAKE_TAG('b','i','t','s'),
  FT_GLYPH_FORMAT_OUTLINE = FT_MAKE_TAG('o','u','t','l'),
  FT_GLYPH_FORMAT_PLOTTER = FT_MAKE_TAG('p','l','o','t'),
}
struct FT_Size_Metrics {
  FT_UShort x_ppem;
  FT_UShort y_ppem;

  FT_Fixed x_scale;
  FT_Fixed y_scale;

  FT_Pos ascender;
  FT_Pos descender;
  FT_Pos height;
  FT_Pos max_advance;
}
enum FT_LOAD_DEFAULT = 0x0U;
enum FT_LOAD_NO_SCALE = 1U<<0;
enum FT_LOAD_NO_HINTING = 1U<<1;
enum FT_LOAD_RENDER = 1U<<2;
enum FT_LOAD_NO_BITMAP = 1U<<3;
enum FT_LOAD_VERTICAL_LAYOUT = 1U<<4;
enum FT_LOAD_FORCE_AUTOHINT = 1U<<5;
enum FT_LOAD_CROP_BITMAP = 1U<<6;
enum FT_LOAD_PEDANTIC = 1U<<7;
enum FT_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH = 1U<<9;
enum FT_LOAD_NO_RECURSE = 1U<<10;
enum FT_LOAD_IGNORE_TRANSFORM = 1U<<11;
enum FT_LOAD_MONOCHROME = 1U<<12;
enum FT_LOAD_LINEAR_DESIGN = 1U<<13;
enum FT_LOAD_NO_AUTOHINT = 1U<<15;
enum FT_LOAD_COLOR = 1U<<20;
enum FT_LOAD_COMPUTE_METRICS = 1U<<21;
enum FT_FACE_FLAG_KERNING = 1U<<6;
alias FT_Kerning_Mode = int;
enum /*FT_Kerning_Mode*/ {
  FT_KERNING_DEFAULT = 0,
  FT_KERNING_UNFITTED,
  FT_KERNING_UNSCALED
}
extern(C) nothrow @nogc {
  alias FT_Outline_MoveToFunc = int function (const(FT_Vector)*, void*);
  alias FT_Outline_LineToFunc = int function (const(FT_Vector)*, void*);
  alias FT_Outline_ConicToFunc = int function (const(FT_Vector)*, const(FT_Vector)*, void*);
  alias FT_Outline_CubicToFunc = int function (const(FT_Vector)*, const(FT_Vector)*, const(FT_Vector)*, void*);
}
struct FT_Outline_Funcs {
  FT_Outline_MoveToFunc move_to;
  FT_Outline_LineToFunc line_to;
  FT_Outline_ConicToFunc conic_to;
  FT_Outline_CubicToFunc cubic_to;
  int shift;
  FT_Pos delta;
}

FT_Error FT_Init_FreeType (FT_Library*);
FT_Error FT_New_Memory_Face (FT_Library, const(FT_Byte)*, FT_Long, FT_Long, FT_Face*);
FT_UInt FT_Get_Char_Index (FT_Face, FT_ULong);
FT_Error FT_Set_Pixel_Sizes (FT_Face, FT_UInt, FT_UInt);
FT_Error FT_Load_Glyph (FT_Face, FT_UInt, FT_Int32);
FT_Error FT_Get_Advance (FT_Face, FT_UInt, FT_Int32, FT_Fixed*);
FT_Error FT_Get_Kerning (FT_Face, FT_UInt, FT_UInt, FT_UInt, FT_Vector*);
void FT_Outline_Get_CBox (const(FT_Outline)*, FT_BBox*);
FT_Error FT_Outline_Decompose (FT_Outline*, const(FT_Outline_Funcs)*, void*);
}
} else {
import iv.freetype;
}

struct FONSttFontImpl {
  FT_Face font;
  bool mono; // no aa?
}

__gshared FT_Library ftLibrary;

int fons__tt_init (FONScontext* context) nothrow @trusted @nogc {
  FT_Error ftError;
  //FONS_NOTUSED(context);
  ftError = FT_Init_FreeType(&ftLibrary);
  return (ftError == 0);
}

void fons__tt_setMono (FONScontext* context, FONSttFontImpl* font, bool v) nothrow @trusted @nogc {
  font.mono = v;
}

bool fons__tt_getMono (FONScontext* context, FONSttFontImpl* font) nothrow @trusted @nogc {
  return font.mono;
}

int fons__tt_loadFont (FONScontext* context, FONSttFontImpl* font, ubyte* data, int dataSize) nothrow @trusted @nogc {
  FT_Error ftError;
  //font.font.userdata = stash;
  ftError = FT_New_Memory_Face(ftLibrary, cast(const(FT_Byte)*)data, dataSize, 0, &font.font);
  return ftError == 0;
}

void fons__tt_getFontVMetrics (FONSttFontImpl* font, int* ascent, int* descent, int* lineGap) nothrow @trusted @nogc {
  *ascent = font.font.ascender;
  *descent = font.font.descender;
  *lineGap = font.font.height-(*ascent - *descent);
}

float fons__tt_getPixelHeightScale (FONSttFontImpl* font, float size) nothrow @trusted @nogc {
  return size/(font.font.ascender-font.font.descender);
}

int fons__tt_getGlyphIndex (FONSttFontImpl* font, int codepoint) nothrow @trusted @nogc {
  return FT_Get_Char_Index(font.font, codepoint);
}

int fons__tt_buildGlyphBitmap (FONSttFontImpl* font, int glyph, float size, float scale, int* advance, int* lsb, int* x0, int* y0, int* x1, int* y1) nothrow @trusted @nogc {
  FT_Error ftError;
  FT_GlyphSlot ftGlyph;
  //version(nanovg_ignore_mono) enum exflags = 0;
  //else version(nanovg_ft_mono) enum exflags = FT_LOAD_MONOCHROME; else enum exflags = 0;
  uint exflags = (font.mono ? FT_LOAD_MONOCHROME : 0);
  ftError = FT_Set_Pixel_Sizes(font.font, 0, cast(FT_UInt)(size*cast(float)font.font.units_per_EM/cast(float)(font.font.ascender-font.font.descender)));
  if (ftError) return 0;
  ftError = FT_Load_Glyph(font.font, glyph, FT_LOAD_RENDER|/*FT_LOAD_NO_AUTOHINT|*/exflags);
  if (ftError) return 0;
  ftError = FT_Get_Advance(font.font, glyph, FT_LOAD_NO_SCALE|/*FT_LOAD_NO_AUTOHINT|*/exflags, cast(FT_Fixed*)advance);
  if (ftError) return 0;
  ftGlyph = font.font.glyph;
  *lsb = cast(int)ftGlyph.metrics.horiBearingX;
  *x0 = ftGlyph.bitmap_left;
  *x1 = *x0+ftGlyph.bitmap.width;
  *y0 = -ftGlyph.bitmap_top;
  *y1 = *y0+ftGlyph.bitmap.rows;
  return 1;
}

void fons__tt_renderGlyphBitmap (FONSttFontImpl* font, ubyte* output, int outWidth, int outHeight, int outStride, float scaleX, float scaleY, int glyph) nothrow @trusted @nogc {
  FT_GlyphSlot ftGlyph = font.font.glyph;
  //FONS_NOTUSED(glyph); // glyph has already been loaded by fons__tt_buildGlyphBitmap
  //version(nanovg_ignore_mono) enum RenderAA = true;
  //else version(nanovg_ft_mono) enum RenderAA = false;
  //else enum RenderAA = true;
  if (font.mono) {
    auto src = ftGlyph.bitmap.buffer;
    auto dst = output;
    auto spt = ftGlyph.bitmap.pitch;
    if (spt < 0) spt = -spt;
    foreach (int y; 0..ftGlyph.bitmap.rows) {
      ubyte count = 0, b = 0;
      auto s = src;
      auto d = dst;
      foreach (int x; 0..ftGlyph.bitmap.width) {
        if (count-- == 0) { count = 7; b = *s++; } else b <<= 1;
        *d++ = (b&0x80 ? 255 : 0);
      }
      src += spt;
      dst += outStride;
    }
  } else {
    auto src = ftGlyph.bitmap.buffer;
    auto dst = output;
    auto spt = ftGlyph.bitmap.pitch;
    if (spt < 0) spt = -spt;
    foreach (int y; 0..ftGlyph.bitmap.rows) {
      import core.stdc.string : memcpy;
      //dst[0..ftGlyph.bitmap.width] = src[0..ftGlyph.bitmap.width];
      memcpy(dst, src, ftGlyph.bitmap.width);
      src += spt;
      dst += outStride;
    }
  }
}

float fons__tt_getGlyphKernAdvance (FONSttFontImpl* font, float size, int glyph1, int glyph2) nothrow @trusted @nogc {
  FT_Vector ftKerning;
  version(none) {
    // fitted kerning
    FT_Get_Kerning(font.font, glyph1, glyph2, FT_KERNING_DEFAULT, &ftKerning);
    //{ import core.stdc.stdio : printf; printf("kern for %u:%u: %d %d\n", glyph1, glyph2, ftKerning.x, ftKerning.y); }
    return cast(int)ftKerning.x; // round up and convert to integer
  } else {
    // unfitted kerning
    //FT_Get_Kerning(font.font, glyph1, glyph2, FT_KERNING_UNFITTED, &ftKerning);
    if (glyph1 <= 0 || glyph2 <= 0 || (font.font.face_flags&FT_FACE_FLAG_KERNING) == 0) return 0;
    if (FT_Set_Pixel_Sizes(font.font, 0, cast(FT_UInt)(size*cast(float)font.font.units_per_EM/cast(float)(font.font.ascender-font.font.descender)))) return 0;
    if (FT_Get_Kerning(font.font, glyph1, glyph2, FT_KERNING_DEFAULT, &ftKerning)) return 0;
    version(none) {
      if (ftKerning.x) {
        //{ import core.stdc.stdio : printf; printf("has kerning: %u\n", cast(uint)(font.font.face_flags&FT_FACE_FLAG_KERNING)); }
        { import core.stdc.stdio : printf; printf("kern for %u:%u: %d %d (size=%g)\n", glyph1, glyph2, ftKerning.x, ftKerning.y, cast(double)size); }
      }
    }
    version(none) {
      FT_Vector kk;
      if (FT_Get_Kerning(font.font, glyph1, glyph2, FT_KERNING_UNSCALED, &kk)) assert(0, "wtf?!");
      auto kadvfrac = FT_MulFix(kk.x, font.font.size.metrics.x_scale); // 1/64 of pixel
      //return cast(int)((kadvfrac/*+(kadvfrac < 0 ? -32 : 32)*/)>>6);
      //assert(ftKerning.x == kadvfrac);
      if (ftKerning.x || kadvfrac) {
        { import core.stdc.stdio : printf; printf("kern for %u:%u: %d %d (%d) (size=%g)\n", glyph1, glyph2, ftKerning.x, cast(int)kadvfrac, cast(int)(kadvfrac+(kadvfrac < 0 ? -31 : 32)>>6), cast(double)size); }
      }
      //return cast(int)(kadvfrac+(kadvfrac < 0 ? -31 : 32)>>6); // round up and convert to integer
      return kadvfrac/64.0f;
    }
    //return cast(int)(ftKerning.x+(ftKerning.x < 0 ? -31 : 32)>>6); // round up and convert to integer
    return ftKerning.x/64.0f;
  }
}

extern(C) nothrow @trusted @nogc {
  static struct OutlinerData {
    @disable this (this);
    NVGContext vg;
    NVGGlyphOutline* ol;
    FT_BBox outlineBBox;
  nothrow @trusted @nogc:
    T transx(T) (T v) const pure { pragma(inline, true); return v; }
    T transy(T) (T v) const pure { pragma(inline, true); return -v; }
    void putBytes (const(void)[] b) {
      assert(b.length <= 512);
      if (b.length == 0) return;
      if (ol.used+cast(uint)b.length > ol.size) {
        import core.stdc.stdlib : realloc;
        uint newsz = (ol.size == 0 ? 2048 : ol.size < 32768 ? ol.size*2 : ol.size+8192);
        assert(ol.used+cast(uint)b.length <= newsz);
        auto nd = cast(ubyte*)realloc(ol.data, newsz);
        if (nd is null) assert(0, "FONS: out of memory");
        ol.size = newsz;
        ol.data = nd;
      }
      import core.stdc.string : memcpy;
      memcpy(ol.data+ol.used, b.ptr, b.length);
      ol.used += cast(uint)b.length;
    }
    void newCommand (ubyte cmd) { pragma(inline, true); ++ol.ccount; putBytes((&cmd)[0..1]); }
    void putArg (float f) { putBytes((&f)[0..1]); }
  }

  int fons__nvg__moveto_cb (const(FT_Vector)* to, void* user) {
    auto odata = cast(OutlinerData*)user;
    if (odata.vg !is null) odata.vg.moveTo(odata.transx(to.x), odata.transy(to.y));
    if (odata.ol !is null) {
      odata.newCommand(odata.ol.Command.Kind.MoveTo);
      odata.putArg(odata.transx(to.x));
      odata.putArg(odata.transy(to.y));
    }
    return 0;
  }

  int fons__nvg__lineto_cb (const(FT_Vector)* to, void* user) {
    auto odata = cast(OutlinerData*)user;
    if (odata.vg !is null) odata.vg.lineTo(odata.transx(to.x), odata.transy(to.y));
    if (odata.ol !is null) {
      odata.newCommand(odata.ol.Command.Kind.LineTo);
      odata.putArg(odata.transx(to.x));
      odata.putArg(odata.transy(to.y));
    }
    return 0;
  }

  int fons__nvg__quadto_cb (const(FT_Vector)* c1, const(FT_Vector)* to, void* user) {
    auto odata = cast(OutlinerData*)user;
    if (odata.vg !is null) odata.vg.quadTo(odata.transx(c1.x), odata.transy(c1.y), odata.transx(to.x), odata.transy(to.y));
    if (odata.ol !is null) {
      odata.newCommand(odata.ol.Command.Kind.QuadTo);
      odata.putArg(odata.transx(c1.x));
      odata.putArg(odata.transy(c1.y));
      odata.putArg(odata.transx(to.x));
      odata.putArg(odata.transy(to.y));
    }
    return 0;
  }

  int fons__nvg__cubicto_cb (const(FT_Vector)* c1, const(FT_Vector)* c2, const(FT_Vector)* to, void* user) {
    auto odata = cast(OutlinerData*)user;
    if (odata.vg !is null) odata.vg.bezierTo(odata.transx(c1.x), odata.transy(c1.y), odata.transx(c2.x), odata.transy(c2.y), odata.transx(to.x), odata.transy(to.y));
    if (odata.ol !is null) {
      odata.newCommand(odata.ol.Command.Kind.BezierTo);
      odata.putArg(odata.transx(c1.x));
      odata.putArg(odata.transy(c1.y));
      odata.putArg(odata.transx(c2.x));
      odata.putArg(odata.transy(c2.y));
      odata.putArg(odata.transx(to.x));
      odata.putArg(odata.transy(to.y));
    }
    return 0;
  }
}

bool fons__nvg__toPath (NVGContext vg, FONSttFontImpl* font, uint glyphidx, float[] bounds=null) nothrow @trusted @nogc {
  if (bounds.length > 4) bounds = bounds.ptr[0..4];

  FT_Outline_Funcs funcs;
  funcs.move_to = &fons__nvg__moveto_cb;
  funcs.line_to = &fons__nvg__lineto_cb;
  funcs.conic_to = &fons__nvg__quadto_cb;
  funcs.cubic_to = &fons__nvg__cubicto_cb;

  auto err = FT_Load_Glyph(font.font, glyphidx, FT_LOAD_NO_BITMAP|FT_LOAD_NO_SCALE);
  if (err) { bounds[] = 0; return false; }
  if (font.font.glyph.format != FT_GLYPH_FORMAT_OUTLINE) { bounds[] = 0; return false; }

  FT_Outline outline = font.font.glyph.outline;

  OutlinerData odata;
  odata.vg = vg;
  FT_Outline_Get_CBox(&outline, &odata.outlineBBox);

  err = FT_Outline_Decompose(&outline, &funcs, &odata);
  if (err) { bounds[] = 0; return false; }
  if (bounds.length > 0) bounds.ptr[0] = odata.outlineBBox.xMin;
  if (bounds.length > 1) bounds.ptr[1] = -odata.outlineBBox.yMax;
  if (bounds.length > 2) bounds.ptr[2] = odata.outlineBBox.xMax;
  if (bounds.length > 3) bounds.ptr[3] = -odata.outlineBBox.yMin;
  return true;
}

bool fons__nvg__toOutline (FONSttFontImpl* font, uint glyphidx, NVGGlyphOutline* ol) nothrow @trusted @nogc {
  FT_Outline_Funcs funcs;
  funcs.move_to = &fons__nvg__moveto_cb;
  funcs.line_to = &fons__nvg__lineto_cb;
  funcs.conic_to = &fons__nvg__quadto_cb;
  funcs.cubic_to = &fons__nvg__cubicto_cb;

  auto err = FT_Load_Glyph(font.font, glyphidx, FT_LOAD_NO_BITMAP|FT_LOAD_NO_SCALE);
  if (err) return false;
  if (font.font.glyph.format != FT_GLYPH_FORMAT_OUTLINE) return false;

  FT_Outline outline = font.font.glyph.outline;

  OutlinerData odata;
  odata.ol = ol;
  FT_Outline_Get_CBox(&outline, &odata.outlineBBox);

  err = FT_Outline_Decompose(&outline, &funcs, &odata);
  if (err) return false;
  ol.bounds.ptr[0] = odata.outlineBBox.xMin;
  ol.bounds.ptr[1] = -odata.outlineBBox.yMax;
  ol.bounds.ptr[2] = odata.outlineBBox.xMax;
  ol.bounds.ptr[3] = -odata.outlineBBox.yMin;
  return true;
}

bool fons__nvg__bounds (FONSttFontImpl* font, uint glyphidx, float[] bounds) nothrow @trusted @nogc {
  if (bounds.length > 4) bounds = bounds.ptr[0..4];

  auto err = FT_Load_Glyph(font.font, glyphidx, FT_LOAD_NO_BITMAP|FT_LOAD_NO_SCALE);
  if (err) return false;
  if (font.font.glyph.format != FT_GLYPH_FORMAT_OUTLINE) { bounds[] = 0; return false; }

  FT_Outline outline = font.font.glyph.outline;
  FT_BBox outlineBBox;
  FT_Outline_Get_CBox(&outline, &outlineBBox);
  if (bounds.length > 0) bounds.ptr[0] = outlineBBox.xMin;
  if (bounds.length > 1) bounds.ptr[1] = -outlineBBox.yMax;
  if (bounds.length > 2) bounds.ptr[2] = outlineBBox.xMax;
  if (bounds.length > 3) bounds.ptr[3] = -outlineBBox.yMin;
  return true;
}


} else {
// ////////////////////////////////////////////////////////////////////////// //
// sorry
import std.traits : isFunctionPointer, isDelegate;
private auto assumeNoThrowNoGC(T) (scope T t) if (isFunctionPointer!T || isDelegate!T) {
  import std.traits;
  enum attrs = functionAttributes!T|FunctionAttribute.nogc|FunctionAttribute.nothrow_;
  return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

private auto forceNoThrowNoGC(T) (scope T t) if (isFunctionPointer!T || isDelegate!T) {
  try {
    return assumeNoThrowNoGC(t)();
  } catch (Exception e) {
    assert(0, "OOPS!");
  }
}

struct FONSttFontImpl {
  stbtt_fontinfo font;
  bool mono; // no aa?
}

int fons__tt_init (FONScontext* context) nothrow @trusted @nogc {
  return 1;
}

void fons__tt_setMono (FONScontext* context, FONSttFontImpl* font, bool v) nothrow @trusted @nogc {
  font.mono = v;
}

bool fons__tt_getMono (FONScontext* context, FONSttFontImpl* font) nothrow @trusted @nogc {
  return font.mono;
}

int fons__tt_loadFont (FONScontext* context, FONSttFontImpl* font, ubyte* data, int dataSize) nothrow @trusted @nogc {
  int stbError;
  font.font.userdata = context;
  forceNoThrowNoGC({ stbError = stbtt_InitFont(&font.font, data, 0); });
  return stbError;
}

void fons__tt_getFontVMetrics (FONSttFontImpl* font, int* ascent, int* descent, int* lineGap) nothrow @trusted @nogc {
  forceNoThrowNoGC({ stbtt_GetFontVMetrics(&font.font, ascent, descent, lineGap); });
}

float fons__tt_getPixelHeightScale (FONSttFontImpl* font, float size) nothrow @trusted @nogc {
  float res = void;
  forceNoThrowNoGC({ res = stbtt_ScaleForPixelHeight(&font.font, size); });
  return res;
}

int fons__tt_getGlyphIndex (FONSttFontImpl* font, int codepoint) nothrow @trusted @nogc {
  int res;
  forceNoThrowNoGC({ res = stbtt_FindGlyphIndex(&font.font, codepoint); });
  return res;
}

int fons__tt_buildGlyphBitmap (FONSttFontImpl* font, int glyph, float size, float scale, int* advance, int* lsb, int* x0, int* y0, int* x1, int* y1) nothrow @trusted @nogc {
  forceNoThrowNoGC({ stbtt_GetGlyphHMetrics(&font.font, glyph, advance, lsb); });
  forceNoThrowNoGC({ stbtt_GetGlyphBitmapBox(&font.font, glyph, scale, scale, x0, y0, x1, y1); });
  return 1;
}

void fons__tt_renderGlyphBitmap (FONSttFontImpl* font, ubyte* output, int outWidth, int outHeight, int outStride, float scaleX, float scaleY, int glyph) nothrow @trusted @nogc {
  forceNoThrowNoGC({ stbtt_MakeGlyphBitmap(&font.font, output, outWidth, outHeight, outStride, scaleX, scaleY, glyph); });
}

float fons__tt_getGlyphKernAdvance (FONSttFontImpl* font, float size, int glyph1, int glyph2) nothrow @trusted @nogc {
  float res = void;
  forceNoThrowNoGC({ res = stbtt_GetGlyphKernAdvance(&font.font, glyph1, glyph2); });
  return res;
}

} // version


// ////////////////////////////////////////////////////////////////////////// //
private:
enum FONS_SCRATCH_BUF_SIZE = 64000;
enum FONS_HASH_LUT_SIZE = 256;
enum FONS_INIT_FONTS = 4;
enum FONS_INIT_GLYPHS = 256;
enum FONS_INIT_ATLAS_NODES = 256;
enum FONS_VERTEX_COUNT = 1024;
enum FONS_MAX_STATES = 20;
enum FONS_MAX_FALLBACKS = 20;

uint fons__hashint() (uint a) pure nothrow @safe @nogc {
  pragma(inline, true);
  a += ~(a<<15);
  a ^=  (a>>10);
  a +=  (a<<3);
  a ^=  (a>>6);
  a += ~(a<<11);
  a ^=  (a>>16);
  return a;
}

uint fons__djbhash (const(void)[] s) pure nothrow @safe @nogc {
  uint hash = 5381;
  foreach (ubyte b; cast(const(ubyte)[])s) {
    if (b >= 'A' && b <= 'Z') b += 32; // poor man's tolower
    hash = ((hash<<5)+hash)+b;
  }
  return hash;
}

private bool fons_strequci (const(char)[] s0, const(char)[] s1) nothrow @trusted @nogc {
  if (s0.length != s1.length) return false;
  const(char)* sp0 = s0.ptr;
  const(char)* sp1 = s1.ptr;
  foreach (immutable _; 0..s0.length) {
    char c0 = *sp0++;
    char c1 = *sp1++;
    if (c0 != c1) {
      if (c0 >= 'A' && c0 <= 'Z') c0 += 32; // poor man tolower
      if (c1 >= 'A' && c1 <= 'Z') c1 += 32; // poor man tolower
      if (c0 != c1) return false;
    }
  }
  return true;
}


struct FONSglyph {
  uint codepoint;
  int index;
  int next;
  short size, blur;
  short x0, y0, x1, y1;
  short xadv, xoff, yoff;
}

// refcounted
struct FONSfontData {
  ubyte* data;
  int dataSize;
  bool freeData;
  int rc;

  @disable this (this); // no copies
}

// won't set rc to 1
FONSfontData* fons__createFontData (ubyte* adata, int asize, bool afree) nothrow @trusted @nogc {
  import core.stdc.stdlib : malloc;
  assert(adata !is null);
  assert(asize > 0);
  auto res = cast(FONSfontData*)malloc(FONSfontData.sizeof);
  if (res is null) assert(0, "FONS: out of memory");
  res.data = adata;
  res.dataSize = asize;
  res.freeData = afree;
  res.rc = 0;
  return res;
}

void incref (FONSfontData* fd) pure nothrow @trusted @nogc {
  pragma(inline, true);
  if (fd !is null) ++fd.rc;
}

void decref (ref FONSfontData* fd) nothrow @trusted @nogc {
  if (fd !is null) {
    if (--fd.rc == 0) {
      import core.stdc.stdlib : free;
      if (fd.freeData && fd.data !is null) {
        free(fd.data);
        fd.data = null;
      }
      free(fd);
      fd = null;
    }
  }
}

// as creating and destroying fonts is a rare operation, malloc some data
struct FONSfont {
  FONSttFontImpl font;
  char* name; // malloced, strz, always lowercase
  uint namelen;
  uint namehash;
  char* path; // malloced, strz
  FONSfontData* fdata;
  float ascender;
  float descender;
  float lineh;
  FONSglyph* glyphs;
  int cglyphs;
  int nglyphs;
  int[FONS_HASH_LUT_SIZE] lut;
  int[FONS_MAX_FALLBACKS] fallbacks;
  int nfallbacks;

  // except glyphs
  void freeMemory () nothrow @trusted @nogc {
    import core.stdc.stdlib : free;
    if (name !is null) { free(name); name = null; }
    namelen = namehash = 0;
    if (path !is null) { free(path); path = null; }
    fdata.decref();
  }

  // this also calcs name hash
  void setName (const(char)[] aname) nothrow @trusted @nogc {
    //{ import core.stdc.stdio; printf("setname: [%.*s]\n", cast(uint)aname.length, aname.ptr); }
    import core.stdc.stdlib : realloc;
    if (aname.length > int.max/32) assert(0, "FONS: invalid font name");
    namelen = cast(uint)aname.length;
    name = cast(char*)realloc(name, namelen+1);
    if (name is null) assert(0, "FONS: out of memory");
    if (aname.length) name[0..aname.length] = aname[];
    name[namelen] = 0;
    // lowercase it
    foreach (ref char ch; name[0..namelen]) if (ch >= 'A' && ch <= 'Z') ch += 32; // poor man's tolower
    namehash = fons__djbhash(name[0..namelen]);
    //{ import core.stdc.stdio; printf("  [%s] [%.*s] [0x%08x]\n", name, namelen, name, namehash); }
  }

  void setPath (const(char)[] apath) nothrow @trusted @nogc {
    import core.stdc.stdlib : realloc;
    if (apath.length > int.max/32) assert(0, "FONS: invalid font path");
    path = cast(char*)realloc(path, apath.length+1);
    if (path is null) assert(0, "FONS: out of memory");
    if (apath.length) path[0..apath.length] = apath[];
    path[apath.length] = 0;
  }

  // this won't check hash
  bool nameEqu (const(char)[] aname) nothrow @trusted @nogc {
    //{ import core.stdc.stdio; printf("nameEqu: aname=[%.*s]; namelen=%u; aslen=%u\n", cast(uint)aname.length, aname.ptr, namelen, cast(uint)aname.length); }
    if (namelen != aname.length) return false;
    const(char)* ns = name;
    // name part
    foreach (char ch; aname) {
      if (ch >= 'A' && ch <= 'Z') ch += 32; // poor man's tolower
      if (ch != *ns++) return false;
    }
    // done (length was checked earlier)
    return true;
  }
}

struct FONSstate {
  int font;
  NVGTextAlign talign;
  float size;
  uint color;
  float blur;
  float spacing;
}

struct FONSatlasNode {
  short x, y, width;
}

struct FONSatlas {
  int width, height;
  FONSatlasNode* nodes;
  int nnodes;
  int cnodes;
}

public struct FONScontext {
  FONSparams params;
  float itw, ith;
  ubyte* texData;
  int[4] dirtyRect;
  FONSfont** fonts; // actually, a simple hash table; can't grow yet
  int cfonts; // allocated
  int nfonts; // used (so we can track hash table stats)
  int* hashidx; // [hsize] items; holds indicies in [fonts] array
  int hused, hsize;// used items and total items in [hashidx]
  FONSatlas* atlas;
  debug(nanovega) {
    float[FONS_VERTEX_COUNT*2] verts;
    float[FONS_VERTEX_COUNT*2] tcoords;
    uint[FONS_VERTEX_COUNT] colors;
    int nverts;
  }
  ubyte* scratch;
  int nscratch;
  FONSstate[FONS_MAX_STATES] states;
  int nstates;
  void function (void* uptr, int error, int val) nothrow @trusted @nogc handleError;
  void* errorUptr;

  // simple linear probing; returns [FONS_INVALID] if not found
  int findNameInHash (const(char)[] name) nothrow @trusted @nogc {
    if (nfonts == 0) return FONS_INVALID;
    auto nhash = fons__djbhash(name);
    //{ import core.stdc.stdio; printf("findinhash: name=[%.*s]; nhash=0x%08x\n", cast(uint)name.length, name.ptr, nhash); }
    auto res = nhash%hsize;
    // hash will never be 100% full, so this loop is safe
    for (;;) {
      int idx = hashidx[res];
      if (idx == -1) break;
      auto font = fonts[idx];
      if (font is null) assert(0, "FONS internal error");
      if (font.namehash == nhash && font.nameEqu(name)) return idx;
      //{ import core.stdc.stdio; printf("findinhash chained: name=[%.*s]; nhash=0x%08x\n", cast(uint)name.length, name.ptr, nhash); }
      res = (res+1)%hsize;
    }
    return FONS_INVALID;
  }

  // should be called $(B before) freeing `fonts[fidx]`
  private void removeIndexFromHash (int fidx) nothrow @trusted @nogc {
    if (fidx < 0 || fidx >= nfonts) assert(0, "FONS internal error");
    if (fonts[fidx] is null) assert(0, "FONS internal error");
    if (hused != nfonts) assert(0, "FONS internal error");
    auto nhash = fonts[fidx].namehash;
    auto res = nhash%hsize;
    // hash will never be 100% full, so this loop is safe
    for (;;) {
      int idx = hashidx[res];
      if (idx == -1) assert(0, "FONS INTERNAL ERROR");
      if (idx == fidx) {
        // i found her! copy rest here
        int nidx = (res+1)%hsize;
        for (;;) {
          if ((hashidx[res] = hashidx[nidx]) == -1) break; // so it will copy `-1` too
          res = nidx;
          nidx = (nidx+1)%hsize;
        }
        return;
      }
      res = (res+1)%hsize;
    }
  }

  // add font with the given index to hash
  // prerequisite: font should not exists in hash
  private void addIndexToHash (int idx) nothrow @trusted @nogc {
    if (idx < 0 || idx >= nfonts) assert(0, "FONS internal error");
    if (fonts[idx] is null) assert(0, "FONS internal error");
    import core.stdc.stdlib : realloc;
    auto nhash = fonts[idx].namehash;
    //{ import core.stdc.stdio; printf("addtohash: name=[%.*s]; nhash=0x%08x\n", cast(uint)name.length, name.ptr, nhash); }
    // allocate new hash table if there was none
    if (hsize == 0) {
      enum InitSize = 256;
      auto newlist = cast(int*)realloc(null, InitSize*hashidx[0].sizeof);
      if (newlist is null) assert(0, "FONS: out of memory");
      newlist[0..InitSize] = -1;
      hsize = InitSize;
      hused = 0;
      hashidx = newlist;
    }
    int res = cast(int)(nhash%hsize);
    // need to rehash? we want our hash table 50% full at max
    if (hashidx[res] != -1 && hused >= hsize/2) {
      uint nsz = hsize*2;
      if (nsz > 1024*1024) assert(0, "FONS: out of memory for fonts");
      auto newlist = cast(int*)realloc(fonts, nsz*hashidx[0].sizeof);
      if (newlist is null) assert(0, "FONS: out of memory");
      newlist[0..nsz] = -1;
      hused = 0;
      // rehash
      foreach (immutable fidx, FONSfont* ff; fonts[0..nfonts]) {
        if (ff is null) continue;
        // find slot for this font (guaranteed to have one)
        uint newslot = ff.namehash%nsz;
        while (newlist[newslot] != -1) newslot = (newslot+1)%nsz;
        newlist[newslot] = cast(int)fidx;
        ++hused;
      }
      hsize = nsz;
      hashidx = newlist;
      // we added everything, including [idx], so nothing more to do here
    } else {
      // find slot (guaranteed to have one)
      while (hashidx[res] != -1) res = (res+1)%hsize;
      // i found her!
      hashidx[res] = idx;
      ++hused;
    }
  }
}

void* fons__tmpalloc (usize size, void* up) nothrow @trusted @nogc {
  ubyte* ptr;
  FONScontext* stash = cast(FONScontext*)up;
  // 16-byte align the returned pointer
  size = (size+0xf)&~0xf;
  if (stash.nscratch+cast(int)size > FONS_SCRATCH_BUF_SIZE) {
    if (stash.handleError) stash.handleError(stash.errorUptr, FONS_SCRATCH_FULL, stash.nscratch+cast(int)size);
    return null;
  }
  ptr = stash.scratch+stash.nscratch;
  stash.nscratch += cast(int)size;
  return ptr;
}

void fons__tmpfree (void* ptr, void* up) nothrow @trusted @nogc {
  // empty
}

// Copyright (c) 2008-2010 Bjoern Hoehrmann <bjoern@hoehrmann.de>
// See http://bjoern.hoehrmann.de/utf-8/decoder/dfa/ for details.

enum FONS_UTF8_ACCEPT = 0;
enum FONS_UTF8_REJECT = 12;

static immutable ubyte[364] utf8d = [
  // The first part of the table maps bytes to character classes that
  // to reduce the size of the transition table and create bitmasks.
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
  7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,  7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
  8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  10, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 3, 3, 11, 6, 6, 6, 5, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,

  // The second part is a transition table that maps a combination
  // of a state of the automaton and a character class to a state.
  0, 12, 24, 36, 60, 96, 84, 12, 12, 12, 48, 72, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
  12, 0, 12, 12, 12, 12, 12, 0, 12, 0, 12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 24, 12, 12,
  12, 12, 12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 12, 12, 24, 12, 12,
  12, 12, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12, 12, 36, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12,
  12, 36, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
];

private enum DecUtfMixin(string state, string codep, string byte_) =
`{
  uint type_ = utf8d.ptr[`~byte_~`];
  `~codep~` = (`~state~` != FONS_UTF8_ACCEPT ? (`~byte_~`&0x3fu)|(`~codep~`<<6) : (0xff>>type_)&`~byte_~`);
  if ((`~state~` = utf8d.ptr[256+`~state~`+type_]) == FONS_UTF8_REJECT) {
    `~state~` = FONS_UTF8_ACCEPT;
    `~codep~` = 0xFFFD;
  }
 }`;

/*
uint fons__decutf8 (uint* state, uint* codep, uint byte_) {
  pragma(inline, true);
  uint type = utf8d.ptr[byte_];
  *codep = (*state != FONS_UTF8_ACCEPT ? (byte_&0x3fu)|(*codep<<6) : (0xff>>type)&byte_);
  *state = utf8d.ptr[256 + *state+type];
  return *state;
}
*/

// Atlas based on Skyline Bin Packer by Jukka Jylänki
void fons__deleteAtlas (FONSatlas* atlas) nothrow @trusted @nogc {
  if (atlas is null) return;
  if (atlas.nodes !is null) free(atlas.nodes);
  free(atlas);
}

FONSatlas* fons__allocAtlas (int w, int h, int nnodes) nothrow @trusted @nogc {
  FONSatlas* atlas = null;

  // Allocate memory for the font stash.
  atlas = cast(FONSatlas*)malloc(FONSatlas.sizeof);
  if (atlas is null) goto error;
  memset(atlas, 0, FONSatlas.sizeof);

  atlas.width = w;
  atlas.height = h;

  // Allocate space for skyline nodes
  atlas.nodes = cast(FONSatlasNode*)malloc(FONSatlasNode.sizeof*nnodes);
  if (atlas.nodes is null) goto error;
  memset(atlas.nodes, 0, FONSatlasNode.sizeof*nnodes);
  atlas.nnodes = 0;
  atlas.cnodes = nnodes;

  // Init root node.
  atlas.nodes[0].x = 0;
  atlas.nodes[0].y = 0;
  atlas.nodes[0].width = cast(short)w;
  ++atlas.nnodes;

  return atlas;

error:
  if (atlas !is null) fons__deleteAtlas(atlas);
  return null;
}

bool fons__atlasInsertNode (FONSatlas* atlas, int idx, int x, int y, int w) nothrow @trusted @nogc {
  // Insert node
  if (atlas.nnodes+1 > atlas.cnodes) {
    atlas.cnodes = (atlas.cnodes == 0 ? 8 : atlas.cnodes*2);
    atlas.nodes = cast(FONSatlasNode*)realloc(atlas.nodes, FONSatlasNode.sizeof*atlas.cnodes);
    if (atlas.nodes is null) return false;
  }
  for (int i = atlas.nnodes; i > idx; --i) atlas.nodes[i] = atlas.nodes[i-1];
  atlas.nodes[idx].x = cast(short)x;
  atlas.nodes[idx].y = cast(short)y;
  atlas.nodes[idx].width = cast(short)w;
  ++atlas.nnodes;
  return 1;
}

void fons__atlasRemoveNode (FONSatlas* atlas, int idx) nothrow @trusted @nogc {
  if (atlas.nnodes == 0) return;
  for (int i = idx; i < atlas.nnodes-1; ++i) atlas.nodes[i] = atlas.nodes[i+1];
  --atlas.nnodes;
}

void fons__atlasExpand (FONSatlas* atlas, int w, int h) nothrow @trusted @nogc {
  // Insert node for empty space
  if (w > atlas.width) fons__atlasInsertNode(atlas, atlas.nnodes, atlas.width, 0, w-atlas.width);
  atlas.width = w;
  atlas.height = h;
}

void fons__atlasReset (FONSatlas* atlas, int w, int h) nothrow @trusted @nogc {
  atlas.width = w;
  atlas.height = h;
  atlas.nnodes = 0;
  // Init root node.
  atlas.nodes[0].x = 0;
  atlas.nodes[0].y = 0;
  atlas.nodes[0].width = cast(short)w;
  ++atlas.nnodes;
}

bool fons__atlasAddSkylineLevel (FONSatlas* atlas, int idx, int x, int y, int w, int h) nothrow @trusted @nogc {
  // Insert new node
  if (!fons__atlasInsertNode(atlas, idx, x, y+h, w)) return false;

  // Delete skyline segments that fall under the shadow of the new segment
  for (int i = idx+1; i < atlas.nnodes; ++i) {
    if (atlas.nodes[i].x < atlas.nodes[i-1].x+atlas.nodes[i-1].width) {
      int shrink = atlas.nodes[i-1].x+atlas.nodes[i-1].width-atlas.nodes[i].x;
      atlas.nodes[i].x += cast(short)shrink;
      atlas.nodes[i].width -= cast(short)shrink;
      if (atlas.nodes[i].width <= 0) {
        fons__atlasRemoveNode(atlas, i);
        --i;
      } else {
        break;
      }
    } else {
      break;
    }
  }

  // Merge same height skyline segments that are next to each other
  for (int i = 0; i < atlas.nnodes-1; ++i) {
    if (atlas.nodes[i].y == atlas.nodes[i+1].y) {
      atlas.nodes[i].width += atlas.nodes[i+1].width;
      fons__atlasRemoveNode(atlas, i+1);
      --i;
    }
  }

  return true;
}

int fons__atlasRectFits (FONSatlas* atlas, int i, int w, int h) nothrow @trusted @nogc {
  // Checks if there is enough space at the location of skyline span 'i',
  // and return the max height of all skyline spans under that at that location,
  // (think tetris block being dropped at that position). Or -1 if no space found.
  int x = atlas.nodes[i].x;
  int y = atlas.nodes[i].y;
  int spaceLeft;
  if (x+w > atlas.width) return -1;
  spaceLeft = w;
  while (spaceLeft > 0) {
    if (i == atlas.nnodes) return -1;
    y = nvg__max(y, atlas.nodes[i].y);
    if (y+h > atlas.height) return -1;
    spaceLeft -= atlas.nodes[i].width;
    ++i;
  }
  return y;
}

bool fons__atlasAddRect (FONSatlas* atlas, int rw, int rh, int* rx, int* ry) nothrow @trusted @nogc {
  int besth = atlas.height, bestw = atlas.width, besti = -1;
  int bestx = -1, besty = -1;

  // Bottom left fit heuristic.
  for (int i = 0; i < atlas.nnodes; ++i) {
    int y = fons__atlasRectFits(atlas, i, rw, rh);
    if (y != -1) {
      if (y+rh < besth || (y+rh == besth && atlas.nodes[i].width < bestw)) {
        besti = i;
        bestw = atlas.nodes[i].width;
        besth = y+rh;
        bestx = atlas.nodes[i].x;
        besty = y;
      }
    }
  }

  if (besti == -1) return false;

  // Perform the actual packing.
  if (!fons__atlasAddSkylineLevel(atlas, besti, bestx, besty, rw, rh)) return false;

  *rx = bestx;
  *ry = besty;

  return true;
}

void fons__addWhiteRect (FONScontext* stash, int w, int h) nothrow @trusted @nogc {
  int gx, gy;
  ubyte* dst;

  if (!fons__atlasAddRect(stash.atlas, w, h, &gx, &gy)) return;

  // Rasterize
  dst = &stash.texData[gx+gy*stash.params.width];
  foreach (int y; 0..h) {
    foreach (int x; 0..w) {
      dst[x] = 0xff;
    }
    dst += stash.params.width;
  }

  stash.dirtyRect.ptr[0] = nvg__min(stash.dirtyRect.ptr[0], gx);
  stash.dirtyRect.ptr[1] = nvg__min(stash.dirtyRect.ptr[1], gy);
  stash.dirtyRect.ptr[2] = nvg__max(stash.dirtyRect.ptr[2], gx+w);
  stash.dirtyRect.ptr[3] = nvg__max(stash.dirtyRect.ptr[3], gy+h);
}

public FONScontext* fonsCreateInternal (FONSparams* params) nothrow @trusted @nogc {
  FONScontext* stash = null;

  // Allocate memory for the font stash.
  stash = cast(FONScontext*)malloc(FONScontext.sizeof);
  if (stash is null) goto error;
  memset(stash, 0, FONScontext.sizeof);

  stash.params = *params;

  // Allocate scratch buffer.
  stash.scratch = cast(ubyte*)malloc(FONS_SCRATCH_BUF_SIZE);
  if (stash.scratch is null) goto error;

  // Initialize implementation library
  if (!fons__tt_init(stash)) goto error;

  if (stash.params.renderCreate !is null) {
    if (!stash.params.renderCreate(stash.params.userPtr, stash.params.width, stash.params.height)) goto error;
  }

  stash.atlas = fons__allocAtlas(stash.params.width, stash.params.height, FONS_INIT_ATLAS_NODES);
  if (stash.atlas is null) goto error;

  // Don't allocate space for fonts: hash manager will do that for us later.
  //stash.cfonts = 0;
  //stash.nfonts = 0;

  // Create texture for the cache.
  stash.itw = 1.0f/stash.params.width;
  stash.ith = 1.0f/stash.params.height;
  stash.texData = cast(ubyte*)malloc(stash.params.width*stash.params.height);
  if (stash.texData is null) goto error;
  memset(stash.texData, 0, stash.params.width*stash.params.height);

  stash.dirtyRect.ptr[0] = stash.params.width;
  stash.dirtyRect.ptr[1] = stash.params.height;
  stash.dirtyRect.ptr[2] = 0;
  stash.dirtyRect.ptr[3] = 0;

  // Add white rect at 0, 0 for debug drawing.
  fons__addWhiteRect(stash, 2, 2);

  fonsPushState(stash);
  fonsClearState(stash);

  return stash;

error:
  fonsDeleteInternal(stash);
  return null;
}

FONSstate* fons__getState (FONScontext* stash) nothrow @trusted @nogc {
  pragma(inline, true);
  return &stash.states[stash.nstates-1];
}

bool fonsAddFallbackFont (FONScontext* stash, int base, int fallback) nothrow @trusted @nogc {
  FONSfont* baseFont = stash.fonts[base];
  if (baseFont !is null && baseFont.nfallbacks < FONS_MAX_FALLBACKS) {
    baseFont.fallbacks.ptr[baseFont.nfallbacks++] = fallback;
    return true;
  }
  return false;
}

public void fonsSetSize (FONScontext* stash, float size) nothrow @trusted @nogc {
  pragma(inline, true);
  fons__getState(stash).size = size;
}

public void fonsSetColor (FONScontext* stash, uint color) nothrow @trusted @nogc {
  pragma(inline, true);
  fons__getState(stash).color = color;
}

public void fonsSetSpacing (FONScontext* stash, float spacing) nothrow @trusted @nogc {
  pragma(inline, true);
  fons__getState(stash).spacing = spacing;
}

public void fonsSetBlur (FONScontext* stash, float blur) nothrow @trusted @nogc {
  pragma(inline, true);
  version(nanovg_kill_font_blur) blur = 0;
  fons__getState(stash).blur = blur;
}

public void fonsSetAlign (FONScontext* stash, NVGTextAlign talign) nothrow @trusted @nogc {
  pragma(inline, true);
  fons__getState(stash).talign = talign;
}

public void fonsSetFont (FONScontext* stash, int font) nothrow @trusted @nogc {
  pragma(inline, true);
  fons__getState(stash).font = font;
}

// get AA for current font or for the specified font
public bool fonsGetFontAA (FONScontext* stash, int font=-1) nothrow @trusted @nogc {
  FONSstate* state = fons__getState(stash);
  if (font < 0) font = state.font;
  if (font < 0 || font >= stash.nfonts) return false;
  FONSfont* f = stash.fonts[font];
  return (f !is null ? !f.font.mono : false);
}

public void fonsPushState (FONScontext* stash) nothrow @trusted @nogc {
  if (stash.nstates >= FONS_MAX_STATES) {
    if (stash.handleError) stash.handleError(stash.errorUptr, FONS_STATES_OVERFLOW, 0);
    return;
  }
  if (stash.nstates > 0) memcpy(&stash.states[stash.nstates], &stash.states[stash.nstates-1], FONSstate.sizeof);
  ++stash.nstates;
}

public void fonsPopState (FONScontext* stash) nothrow @trusted @nogc {
  if (stash.nstates <= 1) {
    if (stash.handleError) stash.handleError(stash.errorUptr, FONS_STATES_UNDERFLOW, 0);
    return;
  }
  --stash.nstates;
}

public void fonsClearState (FONScontext* stash) nothrow @trusted @nogc {
  FONSstate* state = fons__getState(stash);
  state.size = 12.0f;
  state.color = 0xffffffff;
  state.font = 0;
  state.blur = 0;
  state.spacing = 0;
  state.talign.reset; //FONS_ALIGN_LEFT|FONS_ALIGN_BASELINE;
}

void fons__freeFont (FONSfont* font) nothrow @trusted @nogc {
  if (font is null) return;
  if (font.glyphs) free(font.glyphs);
  font.freeMemory();
  free(font);
}

// returns fid, not hash slot
int fons__allocFontAt (FONScontext* stash, int atidx) nothrow @trusted @nogc {
  if (atidx >= 0 && atidx >= stash.nfonts) assert(0, "internal NanoVega fontstash error");

  if (atidx < 0) {
    if (stash.nfonts >= stash.cfonts) {
      import core.stdc.stdlib : realloc;
      import core.stdc.string : memset;
      assert(stash.nfonts == stash.cfonts);
      int newsz = stash.cfonts+64;
      if (newsz > 65535) assert(0, "FONS: too many fonts");
      auto newlist = cast(FONSfont**)realloc(stash.fonts, newsz*(FONSfont*).sizeof);
      if (newlist is null) assert(0, "FONS: out of memory");
      memset(newlist+stash.cfonts, 0, (newsz-stash.cfonts)*(FONSfont*).sizeof);
      stash.fonts = newlist;
      stash.cfonts = newsz;
    }
    assert(stash.nfonts < stash.cfonts);
  }

  FONSfont* font = cast(FONSfont*)malloc(FONSfont.sizeof);
  if (font is null) assert(0, "FONS: out of memory");
  memset(font, 0, FONSfont.sizeof);

  font.glyphs = cast(FONSglyph*)malloc(FONSglyph.sizeof*FONS_INIT_GLYPHS);
  if (font.glyphs is null) assert(0, "FONS: out of memory");
  font.cglyphs = FONS_INIT_GLYPHS;
  font.nglyphs = 0;

  if (atidx < 0) {
    stash.fonts[stash.nfonts] = font;
    return stash.nfonts++;
  } else {
    stash.fonts[atidx] = font;
    return atidx;
  }
}

private enum NoAlias = ":noaa";

// defAA: antialias flag for fonts without ":noaa"
public int fonsAddFont (FONScontext* stash, const(char)[] name, const(char)[] path, bool defAA) nothrow @trusted {
  if (path.length == 0 || name.length == 0 || fons_strequci(name, NoAlias)) return FONS_INVALID;
  if (path.length > 32768) return FONS_INVALID; // arbitrary limit

  // if font path ends with ":noaa", turn off antialiasing
  if (path.length >= NoAlias.length && fons_strequci(path[$-NoAlias.length..$], NoAlias)) {
    path = path[0..$-NoAlias.length];
    if (path.length == 0) return FONS_INVALID;
    defAA = false;
  }

  // if font name ends with ":noaa", turn off antialiasing
  if (name.length > NoAlias.length && fons_strequci(name[$-NoAlias.length..$], NoAlias)) {
    name = name[0..$-NoAlias.length];
    defAA = false;
  }

  // find a font with the given name
  int fidx = stash.findNameInHash(name);
  //{ import core.stdc.stdio; printf("loading font '%.*s' [%s] (fidx=%d)...\n", cast(uint)path.length, path.ptr, fontnamebuf.ptr, fidx); }

  int loadFontFile (const(char)[] path) {
    // check if existing font (if any) has the same path
    if (fidx >= 0) {
      import core.stdc.string : strlen;
      auto plen = (stash.fonts[fidx].path !is null ? strlen(stash.fonts[fidx].path) : 0);
      version(Posix) {
        //{ import core.stdc.stdio; printf("+++ font [%.*s] was loaded from [%.*s]\n", cast(uint)blen, fontnamebuf.ptr, cast(uint)stash.fonts[fidx].path.length, stash.fonts[fidx].path.ptr); }
        if (plen == path.length && stash.fonts[fidx].path[0..plen] == path) {
          //{ import core.stdc.stdio; printf("*** font [%.*s] already loaded from [%.*s]\n", cast(uint)blen, fontnamebuf.ptr, cast(uint)plen, path.ptr); }
          // i found her!
          return fidx;
        }
      } else {
        if (plen == path.length && fons_strequci(stash.fonts[fidx].path[0..plen], path)) {
          // i found her!
          return fidx;
        }
      }
    }
    version(Windows) {
      // special shitdows check: this will reject fontconfig font names (but still allow things like "c:myfont")
      foreach (immutable char ch; path[(path.length >= 2 && path[1] == ':' ? 2 : 0)..$]) if (ch == ':') return FONS_INVALID;
    }
    // either no such font, or different path
    //{ import core.stdc.stdio; printf("trying font [%.*s] from file [%.*s]\n", cast(uint)blen, fontnamebuf.ptr, cast(uint)path.length, path.ptr); }
    int xres = FONS_INVALID;
    try {
      import core.stdc.stdlib : free, malloc;
      static if (NanoVegaHasIVVFS) {
        auto fl = VFile(path);
        auto dataSize = fl.size;
        if (dataSize < 16 || dataSize > int.max/32) return FONS_INVALID;
        ubyte* data = cast(ubyte*)malloc(cast(uint)dataSize);
        if (data is null) assert(0, "out of memory in NanoVega fontstash");
        scope(failure) free(data); // oops
        fl.rawReadExact(data[0..cast(uint)dataSize]);
        fl.close();
      } else {
        import core.stdc.stdio : FILE, fopen, fclose, fread, ftell, fseek;
        import std.internal.cstring : tempCString;
        auto fl = fopen(path.tempCString, "rb");
        if (fl is null) return FONS_INVALID;
        scope(exit) fclose(fl);
        if (fseek(fl, 0, 2/*SEEK_END*/) != 0) return FONS_INVALID;
        auto dataSize = ftell(fl);
        if (fseek(fl, 0, 0/*SEEK_SET*/) != 0) return FONS_INVALID;
        if (dataSize < 16 || dataSize > int.max/32) return FONS_INVALID;
        ubyte* data = cast(ubyte*)malloc(cast(uint)dataSize);
        if (data is null) assert(0, "out of memory in NanoVega fontstash");
        scope(failure) free(data); // oops
        ubyte* dptr = data;
        auto left = cast(uint)dataSize;
        while (left > 0) {
          auto rd = fread(dptr, 1, left, fl);
          if (rd == 0) { free(data); return FONS_INVALID; } // unexpected EOF or reading error, it doesn't matter
          dptr += rd;
          left -= rd;
        }
      }
      scope(failure) free(data); // oops
      // create font data
      FONSfontData* fdata = fons__createFontData(data, cast(int)dataSize, true); // free data
      fdata.incref();
      xres = fonsAddFontWithData(stash, name, fdata, defAA);
      if (xres == FONS_INVALID) {
        fdata.decref(); // this will free [data] and [fdata]
      } else {
        // remember path
        stash.fonts[xres].setPath(path);
      }
    } catch (Exception e) {
      // oops; sorry
    }
    return xres;
  }

  // first try direct path
  auto res = loadFontFile(path);
  // if loading failed, try fontconfig (if fontconfig is available)
  static if (NanoVegaHasFontConfig) {
    if (res == FONS_INVALID && fontconfigAvailable) {
      import std.internal.cstring : tempCString;
      FcPattern* pat = FcNameParse(path.tempCString);
      if (pat !is null) {
        scope(exit) FcPatternDestroy(pat);
        if (FcConfigSubstitute(null, pat, FcMatchPattern)) {
          FcDefaultSubstitute(pat);
          // find the font
          FcResult result;
          FcPattern* font = FcFontMatch(null, pat, &result);
          if (font !is null) {
            scope(exit) FcPatternDestroy(font);
            char* file = null;
            if (FcPatternGetString(font, FC_FILE, 0, &file) == FcResultMatch) {
              if (file !is null && file[0]) {
                import core.stdc.string : strlen;
                res = loadFontFile(file[0..strlen(file)]);
              }
            }
          }
        }
      }
    }
  }
  return res;
}

// This will not free data on error!
public int fonsAddFontMem (FONScontext* stash, const(char)[] name, ubyte* data, int dataSize, bool freeData, bool defAA) nothrow @trusted @nogc {
  FONSfontData* fdata = fons__createFontData(data, dataSize, freeData);
  fdata.incref();
  auto res = fonsAddFontWithData(stash, name, fdata, defAA);
  if (res == FONS_INVALID) {
    // we promised to not free data on error
    fdata.freeData = false;
    fdata.decref(); // this will free [fdata]
  }
  return res;
}

// Add fonts from another font stash
// This is more effective than reloading fonts, 'cause font data will be shared.
public void fonsAddStashFonts (FONScontext* stash, FONScontext* source) nothrow @trusted @nogc {
  if (stash is null || source is null) return;
  foreach (FONSfont* font; source.fonts[0..source.nfonts]) {
    if (font !is null) {
      auto newidx = fonsAddCookedFont(stash, font);
      FONSfont* newfont = stash.fonts[newidx];
      assert(newfont !is null);
      assert(newfont.path is null);
      // copy path
      if (font.path !is null && font.path[0]) {
        import core.stdc.stdlib : malloc;
        import core.stdc.string : strcpy, strlen;
        newfont.path = cast(char*)malloc(strlen(font.path)+1);
        if (newfont.path is null) assert(0, "FONS: out of memory");
        strcpy(newfont.path, font.path);
      }
    }
  }
}

// used to add font from another fontstash
int fonsAddCookedFont (FONScontext* stash, FONSfont* font) nothrow @trusted @nogc {
  if (font is null || font.fdata is null) return FONS_INVALID;
  font.fdata.incref();
  auto res = fonsAddFontWithData(stash, font.name[0..font.namelen], font.fdata, !font.font.mono);
  if (res == FONS_INVALID) font.fdata.decref(); // oops
  return res;
}

// fdata refcount must be already increased; it won't be changed
int fonsAddFontWithData (FONScontext* stash, const(char)[] name, FONSfontData* fdata, bool defAA) nothrow @trusted @nogc {
  int i, ascent, descent, fh, lineGap;

  if (name.length == 0 || fons_strequci(name, NoAlias)) return FONS_INVALID;
  if (name.length > 32767) return FONS_INVALID;
  if (fdata is null) return FONS_INVALID;

  // find a font with the given name
  int newidx;
  FONSfont* oldfont = null;
  int oldidx = stash.findNameInHash(name);
  if (oldidx != FONS_INVALID) {
    // replacement font
    oldfont = stash.fonts[oldidx];
    newidx = oldidx;
  } else {
    // new font, allocate new bucket
    newidx = -1;
  }

  newidx = fons__allocFontAt(stash, newidx);
  FONSfont* font = stash.fonts[newidx];
  font.setName(name);
  font.lut.ptr[0..FONS_HASH_LUT_SIZE] = -1; // init hash lookup
  font.fdata = fdata; // set the font data (don't change reference count)
  fons__tt_setMono(stash, &font.font, !defAA);

  // init font
  stash.nscratch = 0;
  if (!fons__tt_loadFont(stash, &font.font, fdata.data, fdata.dataSize)) {
    // we promised to not free data on error, so just clear the data store (it will be freed by the caller)
    font.fdata = null;
    fons__freeFont(font);
    if (oldidx != FONS_INVALID) {
      assert(oldidx == newidx);
      stash.fonts[oldidx] = oldfont;
    } else {
      assert(newidx == stash.nfonts-1);
      stash.fonts[newidx] = null;
      --stash.nfonts;
    }
    return FONS_INVALID;
  } else {
    // free old font data, if any
    if (oldfont) fons__freeFont(oldfont);
  }

  // add font to name hash
  if (oldidx == FONS_INVALID) stash.addIndexToHash(newidx);

  // store normalized line height
  // the real line height is got by multiplying the lineh by font size
  fons__tt_getFontVMetrics(&font.font, &ascent, &descent, &lineGap);
  fh = ascent-descent;
  font.ascender = cast(float)ascent/cast(float)fh;
  font.descender = cast(float)descent/cast(float)fh;
  font.lineh = cast(float)(fh+lineGap)/cast(float)fh;

  //{ import core.stdc.stdio; printf("created font [%.*s] (idx=%d)...\n", cast(uint)name.length, name.ptr, idx); }
  return newidx;
}

// returns `null` on invalid index
// $(WARNING copy name, as name buffer can be invalidated by next fontstash API call!)
public const(char)[] fonsGetNameByIndex (FONScontext* stash, int idx) nothrow @trusted @nogc {
  if (idx < 0 || idx >= stash.nfonts || stash.fonts[idx] is null) return null;
  return stash.fonts[idx].name[0..stash.fonts[idx].namelen];
}

// allowSubstitutes: check AA variants if exact name wasn't found?
// return [FONS_INVALID] if no font was found
public int fonsGetFontByName (FONScontext* stash, const(char)[] name) nothrow @trusted @nogc {
  //{ import core.stdc.stdio; printf("fonsGetFontByName: [%.*s]\n", cast(uint)name.length, name.ptr); }
  // remove ":noaa" suffix
  if (name.length >= NoAlias.length && fons_strequci(name[$-NoAlias.length..$], NoAlias)) {
    name = name[0..$-NoAlias.length];
  }
  if (name.length == 0) return FONS_INVALID;
  return stash.findNameInHash(name);
}

FONSglyph* fons__allocGlyph (FONSfont* font) nothrow @trusted @nogc {
  if (font.nglyphs+1 > font.cglyphs) {
    font.cglyphs = (font.cglyphs == 0 ? 8 : font.cglyphs*2);
    font.glyphs = cast(FONSglyph*)realloc(font.glyphs, FONSglyph.sizeof*font.cglyphs);
    if (font.glyphs is null) return null;
  }
  ++font.nglyphs;
  return &font.glyphs[font.nglyphs-1];
}

// 0: ooops
int fons__findGlyphForCP (FONScontext* stash, FONSfont *font, dchar dch, FONSfont** renderfont) nothrow @trusted @nogc {
  if (renderfont !is null) *renderfont = font;
  if (stash is null) return 0;
  if (font is null || font.fdata is null) return 0;
  auto g = fons__tt_getGlyphIndex(&font.font, cast(uint)dch);
  // try to find the glyph in fallback fonts
  if (g == 0) {
    foreach (immutable i; 0..font.nfallbacks) {
      FONSfont* fallbackFont = stash.fonts[font.fallbacks.ptr[i]];
      if (fallbackFont !is null) {
        int fallbackIndex = fons__tt_getGlyphIndex(&fallbackFont.font, cast(uint)dch);
        if (fallbackIndex != 0) {
          if (renderfont !is null) *renderfont = fallbackFont;
          return g;
        }
      }
    }
    // no char, try to find replacement one
    if (dch != 0xFFFD) {
      g = fons__tt_getGlyphIndex(&font.font, 0xFFFD);
      if (g == 0) {
        foreach (immutable i; 0..font.nfallbacks) {
          FONSfont* fallbackFont = stash.fonts[font.fallbacks.ptr[i]];
          if (fallbackFont !is null) {
            int fallbackIndex = fons__tt_getGlyphIndex(&fallbackFont.font, 0xFFFD);
            if (fallbackIndex != 0) {
              if (renderfont !is null) *renderfont = fallbackFont;
              return g;
            }
          }
        }
      }
    }
  }
  return g;
}

public bool fonsPathBounds (FONScontext* stash, dchar dch, float[] bounds) nothrow @trusted @nogc {
  if (bounds.length > 4) bounds = bounds.ptr[0..4];
  static if (is(typeof(&fons__nvg__bounds))) {
    if (stash is null) { bounds[] = 0; return false; }
    FONSstate* state = fons__getState(stash);
    if (state.font < 0 || state.font >= stash.nfonts) { bounds[] = 0; return false; }
    FONSfont* font;
    auto g = fons__findGlyphForCP(stash, stash.fonts[state.font], dch, &font);
    if (g == 0) { bounds[] = 0; return false; }
    assert(font !is null);
    return fons__nvg__bounds(&font.font, g, bounds);
  } else {
    bounds[] = 0;
    return false;
  }
}

public bool fonsToPath (FONScontext* stash, NVGContext vg, dchar dch, float[] bounds=null) nothrow @trusted @nogc {
  if (bounds.length > 4) bounds = bounds.ptr[0..4];
  static if (is(typeof(&fons__nvg__toPath))) {
    if (vg is null || stash is null) { bounds[] = 0; return false; }
    FONSstate* state = fons__getState(stash);
    if (state.font < 0 || state.font >= stash.nfonts) { bounds[] = 0; return false; }
    FONSfont* font;
    auto g = fons__findGlyphForCP(stash, stash.fonts[state.font], dch, &font);
    if (g == 0) { bounds[] = 0; return false; }
    assert(font !is null);
    return fons__nvg__toPath(vg, &font.font, g, bounds);
  } else {
    bounds[] = 0;
    return false;
  }
}

public bool fonsToOutline (FONScontext* stash, dchar dch, NVGGlyphOutline* ol) nothrow @trusted @nogc {
  if (stash is null || ol is null) return false;
  static if (is(typeof(&fons__nvg__toOutline))) {
    FONSstate* state = fons__getState(stash);
    if (state.font < 0 || state.font >= stash.nfonts) return false;
    FONSfont* font;
    auto g = fons__findGlyphForCP(stash, stash.fonts[state.font], dch, &font);
    if (g == 0) return false;
    assert(font !is null);
    return fons__nvg__toOutline(&font.font, g, ol);
  } else {
    return false;
  }
}


// Based on Exponential blur, Jani Huhtanen, 2006

enum APREC = 16;
enum ZPREC = 7;

void fons__blurCols (ubyte* dst, int w, int h, int dstStride, int alpha) nothrow @trusted @nogc {
  foreach (int y; 0..h) {
    int z = 0; // force zero border
    foreach (int x; 1..w) {
      z += (alpha*((cast(int)(dst[x])<<ZPREC)-z))>>APREC;
      dst[x] = cast(ubyte)(z>>ZPREC);
    }
    dst[w-1] = 0; // force zero border
    z = 0;
    for (int x = w-2; x >= 0; --x) {
      z += (alpha*((cast(int)(dst[x])<<ZPREC)-z))>>APREC;
      dst[x] = cast(ubyte)(z>>ZPREC);
    }
    dst[0] = 0; // force zero border
    dst += dstStride;
  }
}

void fons__blurRows (ubyte* dst, int w, int h, int dstStride, int alpha) nothrow @trusted @nogc {
  foreach (int x; 0..w) {
    int z = 0; // force zero border
    for (int y = dstStride; y < h*dstStride; y += dstStride) {
      z += (alpha*((cast(int)(dst[y])<<ZPREC)-z))>>APREC;
      dst[y] = cast(ubyte)(z>>ZPREC);
    }
    dst[(h-1)*dstStride] = 0; // force zero border
    z = 0;
    for (int y = (h-2)*dstStride; y >= 0; y -= dstStride) {
      z += (alpha*((cast(int)(dst[y])<<ZPREC)-z))>>APREC;
      dst[y] = cast(ubyte)(z>>ZPREC);
    }
    dst[0] = 0; // force zero border
    ++dst;
  }
}


void fons__blur (FONScontext* stash, ubyte* dst, int w, int h, int dstStride, int blur) nothrow @trusted @nogc {
  import std.math : expf = exp;
  int alpha;
  float sigma;
  if (blur < 1) return;
  // Calculate the alpha such that 90% of the kernel is within the radius. (Kernel extends to infinity)
  sigma = cast(float)blur*0.57735f; // 1/sqrt(3)
  alpha = cast(int)((1<<APREC)*(1.0f-expf(-2.3f/(sigma+1.0f))));
  fons__blurRows(dst, w, h, dstStride, alpha);
  fons__blurCols(dst, w, h, dstStride, alpha);
  fons__blurRows(dst, w, h, dstStride, alpha);
  fons__blurCols(dst, w, h, dstStride, alpha);
  //fons__blurrows(dst, w, h, dstStride, alpha);
  //fons__blurcols(dst, w, h, dstStride, alpha);
}

FONSglyph* fons__getGlyph (FONScontext* stash, FONSfont* font, uint codepoint, short isize, short iblur, FONSglyphBitmap bitmapOption) nothrow @trusted @nogc {
  int i, g, advance, lsb, x0, y0, x1, y1, gw, gh, gx, gy, x, y;
  float scale;
  FONSglyph* glyph = null;
  uint h;
  float size = isize/10.0f;
  int pad, added;
  ubyte* bdst;
  ubyte* dst;
  FONSfont* renderFont = font;

  version(nanovg_kill_font_blur) iblur = 0;

  if (isize < 2) return null;
  if (iblur > 20) iblur = 20;
  pad = iblur+2;

  // Reset allocator.
  stash.nscratch = 0;

  // Find code point and size.
  h = fons__hashint(codepoint)&(FONS_HASH_LUT_SIZE-1);
  i = font.lut.ptr[h];
  while (i != -1) {
    //if (font.glyphs[i].codepoint == codepoint && font.glyphs[i].size == isize && font.glyphs[i].blur == iblur) return &font.glyphs[i];
    if (font.glyphs[i].codepoint == codepoint && font.glyphs[i].size == isize && font.glyphs[i].blur == iblur) {
      glyph = &font.glyphs[i];
      // Negative coordinate indicates there is no bitmap data created.
      if (bitmapOption == FONS_GLYPH_BITMAP_OPTIONAL || (glyph.x0 >= 0 && glyph.y0 >= 0)) return glyph;
      // At this point, glyph exists but the bitmap data is not yet created.
      break;
    }
    i = font.glyphs[i].next;
  }

  // Create a new glyph or rasterize bitmap data for a cached glyph.
  //scale = fons__tt_getPixelHeightScale(&font.font, size);
  g = fons__findGlyphForCP(stash, font, cast(dchar)codepoint, &renderFont);
  // It is possible that we did not find a fallback glyph.
  // In that case the glyph index 'g' is 0, and we'll proceed below and cache empty glyph.

  scale = fons__tt_getPixelHeightScale(&renderFont.font, size);
  fons__tt_buildGlyphBitmap(&renderFont.font, g, size, scale, &advance, &lsb, &x0, &y0, &x1, &y1);
  gw = x1-x0+pad*2;
  gh = y1-y0+pad*2;

  // Determines the spot to draw glyph in the atlas.
  if (bitmapOption == FONS_GLYPH_BITMAP_REQUIRED) {
    // Find free spot for the rect in the atlas.
    added = fons__atlasAddRect(stash.atlas, gw, gh, &gx, &gy);
    if (added == 0 && stash.handleError !is null) {
      // Atlas is full, let the user to resize the atlas (or not), and try again.
      stash.handleError(stash.errorUptr, FONS_ATLAS_FULL, 0);
      added = fons__atlasAddRect(stash.atlas, gw, gh, &gx, &gy);
    }
    if (added == 0) return null;
  } else {
    // Negative coordinate indicates there is no bitmap data created.
    gx = -1;
    gy = -1;
  }

  // Init glyph.
  if (glyph is null) {
    glyph = fons__allocGlyph(font);
    glyph.codepoint = codepoint;
    glyph.size = isize;
    glyph.blur = iblur;
    glyph.next = 0;

    // Insert char to hash lookup.
    glyph.next = font.lut.ptr[h];
    font.lut.ptr[h] = font.nglyphs-1;
  }
  glyph.index = g;
  glyph.x0 = cast(short)gx;
  glyph.y0 = cast(short)gy;
  glyph.x1 = cast(short)(glyph.x0+gw);
  glyph.y1 = cast(short)(glyph.y0+gh);
  glyph.xadv = cast(short)(scale*advance*10.0f);
  glyph.xoff = cast(short)(x0-pad);
  glyph.yoff = cast(short)(y0-pad);

  if (bitmapOption == FONS_GLYPH_BITMAP_OPTIONAL) return glyph;

  // Rasterize
  dst = &stash.texData[(glyph.x0+pad)+(glyph.y0+pad)*stash.params.width];
  fons__tt_renderGlyphBitmap(&font.font, dst, gw-pad*2, gh-pad*2, stash.params.width, scale, scale, g);

  // Make sure there is one pixel empty border.
  dst = &stash.texData[glyph.x0+glyph.y0*stash.params.width];
  for (y = 0; y < gh; y++) {
    dst[y*stash.params.width] = 0;
    dst[gw-1+y*stash.params.width] = 0;
  }
  for (x = 0; x < gw; x++) {
    dst[x] = 0;
    dst[x+(gh-1)*stash.params.width] = 0;
  }

  // Debug code to color the glyph background
  version(none) {
    foreach (immutable yy; 0..gh) {
      foreach (immutable xx; 0..gw) {
        int a = cast(int)dst[xx+yy*stash.params.width]+42;
        if (a > 255) a = 255;
        dst[xx+yy*stash.params.width] = cast(ubyte)a;
      }
    }
  }

  // Blur
  if (iblur > 0) {
    stash.nscratch = 0;
    bdst = &stash.texData[glyph.x0+glyph.y0*stash.params.width];
    fons__blur(stash, bdst, gw, gh, stash.params.width, iblur);
  }

  stash.dirtyRect.ptr[0] = nvg__min(stash.dirtyRect.ptr[0], glyph.x0);
  stash.dirtyRect.ptr[1] = nvg__min(stash.dirtyRect.ptr[1], glyph.y0);
  stash.dirtyRect.ptr[2] = nvg__max(stash.dirtyRect.ptr[2], glyph.x1);
  stash.dirtyRect.ptr[3] = nvg__max(stash.dirtyRect.ptr[3], glyph.y1);

  return glyph;
}

void fons__getQuad (FONScontext* stash, FONSfont* font, int prevGlyphIndex, FONSglyph* glyph, float size, float scale, float spacing, float* x, float* y, FONSquad* q) nothrow @trusted @nogc {
  if (prevGlyphIndex >= 0) {
    immutable float adv = fons__tt_getGlyphKernAdvance(&font.font, size, prevGlyphIndex, glyph.index)/**scale*/; //k8: do we really need scale here?
    //if (adv != 0) { import core.stdc.stdio; printf("adv=%g (scale=%g; spacing=%g)\n", cast(double)adv, cast(double)scale, cast(double)spacing); }
    *x += cast(int)(adv+spacing /*+0.5f*/); //k8: for me, it looks better this way (with non-aa fonts)
  }

  // Each glyph has 2px border to allow good interpolation,
  // one pixel to prevent leaking, and one to allow good interpolation for rendering.
  // Inset the texture region by one pixel for correct interpolation.
  immutable float xoff = cast(short)(glyph.xoff+1);
  immutable float yoff = cast(short)(glyph.yoff+1);
  immutable float x0 = cast(float)(glyph.x0+1);
  immutable float y0 = cast(float)(glyph.y0+1);
  immutable float x1 = cast(float)(glyph.x1-1);
  immutable float y1 = cast(float)(glyph.y1-1);

  if (stash.params.flags&FONS_ZERO_TOPLEFT) {
    immutable float rx = cast(float)cast(int)(*x+xoff);
    immutable float ry = cast(float)cast(int)(*y+yoff);

    q.x0 = rx;
    q.y0 = ry;
    q.x1 = rx+x1-x0;
    q.y1 = ry+y1-y0;

    q.s0 = x0*stash.itw;
    q.t0 = y0*stash.ith;
    q.s1 = x1*stash.itw;
    q.t1 = y1*stash.ith;
  } else {
    immutable float rx = cast(float)cast(int)(*x+xoff);
    immutable float ry = cast(float)cast(int)(*y-yoff);

    q.x0 = rx;
    q.y0 = ry;
    q.x1 = rx+x1-x0;
    q.y1 = ry-y1+y0;

    q.s0 = x0*stash.itw;
    q.t0 = y0*stash.ith;
    q.s1 = x1*stash.itw;
    q.t1 = y1*stash.ith;
  }

  *x += cast(int)(glyph.xadv/10.0f+0.5f);
}

void fons__flush (FONScontext* stash) nothrow @trusted @nogc {
  // Flush texture
  if (stash.dirtyRect.ptr[0] < stash.dirtyRect.ptr[2] && stash.dirtyRect.ptr[1] < stash.dirtyRect.ptr[3]) {
    if (stash.params.renderUpdate !is null) stash.params.renderUpdate(stash.params.userPtr, stash.dirtyRect.ptr, stash.texData);
    // Reset dirty rect
    stash.dirtyRect.ptr[0] = stash.params.width;
    stash.dirtyRect.ptr[1] = stash.params.height;
    stash.dirtyRect.ptr[2] = 0;
    stash.dirtyRect.ptr[3] = 0;
  }

  debug(nanovega) {
    // Flush triangles
    if (stash.nverts > 0) {
      if (stash.params.renderDraw !is null) stash.params.renderDraw(stash.params.userPtr, stash.verts.ptr, stash.tcoords.ptr, stash.colors.ptr, stash.nverts);
      stash.nverts = 0;
    }
  }
}

debug(nanovega) void fons__vertex (FONScontext* stash, float x, float y, float s, float t, uint c) nothrow @trusted @nogc {
  stash.verts.ptr[stash.nverts*2+0] = x;
  stash.verts.ptr[stash.nverts*2+1] = y;
  stash.tcoords.ptr[stash.nverts*2+0] = s;
  stash.tcoords.ptr[stash.nverts*2+1] = t;
  stash.colors.ptr[stash.nverts] = c;
  ++stash.nverts;
}

float fons__getVertAlign (FONScontext* stash, FONSfont* font, NVGTextAlign talign, short isize) nothrow @trusted @nogc {
  if (stash.params.flags&FONS_ZERO_TOPLEFT) {
    final switch (talign.vertical) {
      case NVGTextAlign.V.Top: return font.ascender*cast(float)isize/10.0f;
      case NVGTextAlign.V.Middle: return (font.ascender+font.descender)/2.0f*cast(float)isize/10.0f;
      case NVGTextAlign.V.Baseline: return 0.0f;
      case NVGTextAlign.V.Bottom: return font.descender*cast(float)isize/10.0f;
    }
  } else {
    final switch (talign.vertical) {
      case NVGTextAlign.V.Top: return -font.ascender*cast(float)isize/10.0f;
      case NVGTextAlign.V.Middle: return -(font.ascender+font.descender)/2.0f*cast(float)isize/10.0f;
      case NVGTextAlign.V.Baseline: return 0.0f;
      case NVGTextAlign.V.Bottom: return -font.descender*cast(float)isize/10.0f;
    }
  }
  assert(0);
}

public bool fonsTextIterInit(T) (FONScontext* stash, FONStextIter!T* iter, float x, float y, const(T)[] str, FONSglyphBitmap bitmapOption) if (isAnyCharType!T) {
  if (stash is null || iter is null) return false;

  FONSstate* state = fons__getState(stash);
  float width;

  memset(iter, 0, (*iter).sizeof);

  if (stash is null) return false;
  if (state.font < 0 || state.font >= stash.nfonts) return false;
  iter.font = stash.fonts[state.font];
  if (iter.font is null || iter.font.fdata is null) return false;

  iter.isize = cast(short)(state.size*10.0f);
  iter.iblur = cast(short)state.blur;
  iter.scale = fons__tt_getPixelHeightScale(&iter.font.font, cast(float)iter.isize/10.0f);

  // Align horizontally
  if (state.talign.left) {
    // empty
  } else if (state.talign.right) {
    width = fonsTextBounds(stash, x, y, str, null);
    x -= width;
  } else if (state.talign.center) {
    width = fonsTextBounds(stash, x, y, str, null);
    x -= width*0.5f;
  }
  // Align vertically.
  y += fons__getVertAlign(stash, iter.font, state.talign, iter.isize);

  iter.x = iter.nextx = x;
  iter.y = iter.nexty = y;
  iter.spacing = state.spacing;
  if (str.ptr is null) {
         static if (is(T == char)) str = "";
    else static if (is(T == wchar)) str = ""w;
    else static if (is(T == dchar)) str = ""d;
    else static assert(0, "wtf?!");
  }
  iter.s = str.ptr;
  iter.n = str.ptr;
  iter.e = str.ptr+str.length;
  iter.codepoint = 0;
  iter.prevGlyphIndex = -1;
  iter.bitmapOption = bitmapOption;

  return true;
}

public bool fonsTextIterGetDummyChar(FT) (FONScontext* stash, FT* iter, FONSquad* quad) nothrow @trusted @nogc if (is(FT : FONStextIter!CT, CT)) {
  if (stash is null || iter is null) return false;
  // Get glyph and quad
  iter.x = iter.nextx;
  iter.y = iter.nexty;
  FONSglyph* glyph = fons__getGlyph(stash, iter.font, 0xFFFD, iter.isize, iter.iblur, iter.bitmapOption);
  if (glyph !is null) {
    fons__getQuad(stash, iter.font, iter.prevGlyphIndex, glyph, iter.isize/10.0f, iter.scale, iter.spacing, &iter.nextx, &iter.nexty, quad);
    iter.prevGlyphIndex = glyph.index;
    return true;
  } else {
    iter.prevGlyphIndex = -1;
    return false;
  }
}

public bool fonsTextIterNext(FT) (FONScontext* stash, FT* iter, FONSquad* quad) nothrow @trusted @nogc if (is(FT : FONStextIter!CT, CT)) {
  if (stash is null || iter is null) return false;
  FONSglyph* glyph = null;
  static if (is(FT.CharType == char)) {
    const(char)* str = iter.n;
    iter.s = iter.n;
    if (str is iter.e) return false;
    const(char)* e = iter.e;
    for (; str !is e; ++str) {
      /*if (fons__decutf8(&iter.utf8state, &iter.codepoint, *cast(const(ubyte)*)str)) continue;*/
      mixin(DecUtfMixin!("iter.utf8state", "iter.codepoint", "*cast(const(ubyte)*)str"));
      if (iter.utf8state) continue;
      ++str; // 'cause we'll break anyway
      // get glyph and quad
      iter.x = iter.nextx;
      iter.y = iter.nexty;
      glyph = fons__getGlyph(stash, iter.font, iter.codepoint, iter.isize, iter.iblur, iter.bitmapOption);
      if (glyph !is null) {
        fons__getQuad(stash, iter.font, iter.prevGlyphIndex, glyph, iter.isize/10.0f, iter.scale, iter.spacing, &iter.nextx, &iter.nexty, quad);
        iter.prevGlyphIndex = glyph.index;
      } else {
        iter.prevGlyphIndex = -1;
      }
      break;
    }
    iter.n = str;
  } else {
    const(FT.CharType)* str = iter.n;
    iter.s = iter.n;
    if (str is iter.e) return false;
    iter.codepoint = cast(uint)(*str++);
    if (iter.codepoint > dchar.max) iter.codepoint = 0xFFFD;
    // Get glyph and quad
    iter.x = iter.nextx;
    iter.y = iter.nexty;
    glyph = fons__getGlyph(stash, iter.font, iter.codepoint, iter.isize, iter.iblur, iter.bitmapOption);
    if (glyph !is null) {
      fons__getQuad(stash, iter.font, iter.prevGlyphIndex, glyph, iter.isize/10.0f, iter.scale, iter.spacing, &iter.nextx, &iter.nexty, quad);
      iter.prevGlyphIndex = glyph.index;
    } else {
      iter.prevGlyphIndex = -1;
    }
    iter.n = str;
  }
  return true;
}

debug(nanovega) public void fonsDrawDebug (FONScontext* stash, float x, float y) nothrow @trusted @nogc {
  int i;
  int w = stash.params.width;
  int h = stash.params.height;
  float u = (w == 0 ? 0 : 1.0f/w);
  float v = (h == 0 ? 0 : 1.0f/h);

  if (stash.nverts+6+6 > FONS_VERTEX_COUNT) fons__flush(stash);

  // Draw background
  fons__vertex(stash, x+0, y+0, u, v, 0x0fffffff);
  fons__vertex(stash, x+w, y+h, u, v, 0x0fffffff);
  fons__vertex(stash, x+w, y+0, u, v, 0x0fffffff);

  fons__vertex(stash, x+0, y+0, u, v, 0x0fffffff);
  fons__vertex(stash, x+0, y+h, u, v, 0x0fffffff);
  fons__vertex(stash, x+w, y+h, u, v, 0x0fffffff);

  // Draw texture
  fons__vertex(stash, x+0, y+0, 0, 0, 0xffffffff);
  fons__vertex(stash, x+w, y+h, 1, 1, 0xffffffff);
  fons__vertex(stash, x+w, y+0, 1, 0, 0xffffffff);

  fons__vertex(stash, x+0, y+0, 0, 0, 0xffffffff);
  fons__vertex(stash, x+0, y+h, 0, 1, 0xffffffff);
  fons__vertex(stash, x+w, y+h, 1, 1, 0xffffffff);

  // Drawbug draw atlas
  for (i = 0; i < stash.atlas.nnodes; i++) {
    FONSatlasNode* n = &stash.atlas.nodes[i];

    if (stash.nverts+6 > FONS_VERTEX_COUNT)
      fons__flush(stash);

    fons__vertex(stash, x+n.x+0, y+n.y+0, u, v, 0xc00000ff);
    fons__vertex(stash, x+n.x+n.width, y+n.y+1, u, v, 0xc00000ff);
    fons__vertex(stash, x+n.x+n.width, y+n.y+0, u, v, 0xc00000ff);

    fons__vertex(stash, x+n.x+0, y+n.y+0, u, v, 0xc00000ff);
    fons__vertex(stash, x+n.x+0, y+n.y+1, u, v, 0xc00000ff);
    fons__vertex(stash, x+n.x+n.width, y+n.y+1, u, v, 0xc00000ff);
  }

  fons__flush(stash);
}

public struct FonsTextBoundsIterator {
private:
  FONScontext* stash;
  FONSstate* state;
  uint codepoint;
  uint utf8state = 0;
  FONSquad q;
  FONSglyph* glyph = null;
  int prevGlyphIndex = -1;
  short isize, iblur;
  float scale;
  FONSfont* font;
  float startx, x, y;
  float minx, miny, maxx, maxy;

public:
  this (FONScontext* astash, float ax, float ay) nothrow @trusted @nogc { reset(astash, ax, ay); }

  void reset (FONScontext* astash, float ax, float ay) nothrow @trusted @nogc {
    this = this.init;
    if (astash is null) return;
    stash = astash;
    state = fons__getState(stash);
    if (state is null) { stash = null; return; } // alas

    x = ax;
    y = ay;

    isize = cast(short)(state.size*10.0f);
    iblur = cast(short)state.blur;

    if (state.font < 0 || state.font >= stash.nfonts) { stash = null; return; }
    font = stash.fonts[state.font];
    if (font is null || font.fdata is null) { stash = null; return; }

    scale = fons__tt_getPixelHeightScale(&font.font, cast(float)isize/10.0f);

    // align vertically
    y += fons__getVertAlign(stash, font, state.talign, isize);

    minx = maxx = x;
    miny = maxy = y;
    startx = x;
    //assert(prevGlyphIndex == -1);
  }

public:
  @property bool valid () const pure nothrow @safe @nogc { pragma(inline, true); return (state !is null); }

  void put(T) (const(T)[] str...) nothrow @trusted @nogc if (isAnyCharType!T) {
    enum DoCodePointMixin = q{
      glyph = fons__getGlyph(stash, font, codepoint, isize, iblur, FONS_GLYPH_BITMAP_OPTIONAL);
      if (glyph !is null) {
        fons__getQuad(stash, font, prevGlyphIndex, glyph, isize/10.0f, scale, state.spacing, &x, &y, &q);
        if (q.x0 < minx) minx = q.x0;
        if (q.x1 > maxx) maxx = q.x1;
        if (stash.params.flags&FONS_ZERO_TOPLEFT) {
          if (q.y0 < miny) miny = q.y0;
          if (q.y1 > maxy) maxy = q.y1;
        } else {
          if (q.y1 < miny) miny = q.y1;
          if (q.y0 > maxy) maxy = q.y0;
        }
        prevGlyphIndex = glyph.index;
      } else {
        prevGlyphIndex = -1;
      }
    };

    if (state is null) return; // alas
    static if (is(T == char)) {
      foreach (char ch; str) {
        mixin(DecUtfMixin!("utf8state", "codepoint", "cast(ubyte)ch"));
        if (utf8state) continue; // full char is not collected yet
        mixin(DoCodePointMixin);
      }
    } else {
      if (str.length == 0) return;
      if (utf8state) {
        utf8state = 0;
        codepoint = 0xFFFD;
        mixin(DoCodePointMixin);
      }
      foreach (T dch; str) {
        static if (is(T == dchar)) {
          if (dch > dchar.max) dch = 0xFFFD;
        }
        codepoint = cast(uint)dch;
        mixin(DoCodePointMixin);
      }
    }
  }

  // return current advance
  @property float advance () const pure nothrow @safe @nogc { pragma(inline, true); return (state !is null ? x-startx : 0); }

  void getBounds (ref float[4] bounds) const pure nothrow @safe @nogc {
    if (state is null) { bounds[] = 0; return; }
    float lminx = minx, lmaxx = maxx;
    // align horizontally
    if (state.talign.left) {
      // empty
    } else if (state.talign.right) {
      float ca = advance;
      lminx -= ca;
      lmaxx -= ca;
    } else if (state.talign.center) {
      float ca = advance*0.5f;
      lminx -= ca;
      lmaxx -= ca;
    }
    bounds[0] = lminx;
    bounds[1] = miny;
    bounds[2] = lmaxx;
    bounds[3] = maxy;
  }

  // Returns current horizontal text bounds.
  void getHBounds (out float xmin, out float xmax) nothrow @trusted @nogc {
    if (state !is null) {
      float lminx = minx, lmaxx = maxx;
      // align horizontally
      if (state.talign.left) {
        // empty
      } else if (state.talign.right) {
        float ca = advance;
        lminx -= ca;
        lmaxx -= ca;
      } else if (state.talign.center) {
        float ca = advance*0.5f;
        lminx -= ca;
        lmaxx -= ca;
      }
      xmin = lminx;
      xmax = lmaxx;
    }
  }

  // Returns current vertical text bounds.
  void getVBounds (out float ymin, out float ymax) nothrow @trusted @nogc {
    if (state !is null) {
      ymin = miny;
      ymax = maxy;
    }
  }
}

public float fonsTextBounds(T) (FONScontext* stash, float x, float y, const(T)[] str, float[] bounds) nothrow @trusted @nogc
if (isAnyCharType!T)
{
  FONSstate* state = fons__getState(stash);
  uint codepoint;
  uint utf8state = 0;
  FONSquad q;
  FONSglyph* glyph = null;
  int prevGlyphIndex = -1;
  short isize = cast(short)(state.size*10.0f);
  short iblur = cast(short)state.blur;
  float scale;
  FONSfont* font;
  float startx, advance;
  float minx, miny, maxx, maxy;

  if (stash is null) return 0;
  if (state.font < 0 || state.font >= stash.nfonts) return 0;
  font = stash.fonts[state.font];
  if (font is null || font.fdata is null) return 0;

  scale = fons__tt_getPixelHeightScale(&font.font, cast(float)isize/10.0f);

  // Align vertically.
  y += fons__getVertAlign(stash, font, state.talign, isize);

  minx = maxx = x;
  miny = maxy = y;
  startx = x;

  static if (is(T == char)) {
    foreach (char ch; str) {
      //if (fons__decutf8(&utf8state, &codepoint, *cast(const(ubyte)*)str)) continue;
      mixin(DecUtfMixin!("utf8state", "codepoint", "(cast(ubyte)ch)"));
      if (utf8state) continue;
      glyph = fons__getGlyph(stash, font, codepoint, isize, iblur, FONS_GLYPH_BITMAP_OPTIONAL);
      if (glyph !is null) {
        fons__getQuad(stash, font, prevGlyphIndex, glyph, isize/10.0f, scale, state.spacing, &x, &y, &q);
        if (q.x0 < minx) minx = q.x0;
        if (q.x1 > maxx) maxx = q.x1;
        if (stash.params.flags&FONS_ZERO_TOPLEFT) {
          if (q.y0 < miny) miny = q.y0;
          if (q.y1 > maxy) maxy = q.y1;
        } else {
          if (q.y1 < miny) miny = q.y1;
          if (q.y0 > maxy) maxy = q.y0;
        }
        prevGlyphIndex = glyph.index;
      } else {
        prevGlyphIndex = -1;
      }
    }
  } else {
    foreach (T ch; str) {
      static if (is(T == dchar)) {
        if (ch > dchar.max) ch = 0xFFFD;
      }
      codepoint = cast(uint)ch;
      glyph = fons__getGlyph(stash, font, codepoint, isize, iblur, FONS_GLYPH_BITMAP_OPTIONAL);
      if (glyph !is null) {
        fons__getQuad(stash, font, prevGlyphIndex, glyph, isize/10.0f, scale, state.spacing, &x, &y, &q);
        if (q.x0 < minx) minx = q.x0;
        if (q.x1 > maxx) maxx = q.x1;
        if (stash.params.flags&FONS_ZERO_TOPLEFT) {
          if (q.y0 < miny) miny = q.y0;
          if (q.y1 > maxy) maxy = q.y1;
        } else {
          if (q.y1 < miny) miny = q.y1;
          if (q.y0 > maxy) maxy = q.y0;
        }
        prevGlyphIndex = glyph.index;
      } else {
        prevGlyphIndex = -1;
      }
    }
  }

  advance = x-startx;

  // Align horizontally
  if (state.talign.left) {
    // empty
  } else if (state.talign.right) {
    minx -= advance;
    maxx -= advance;
  } else if (state.talign.center) {
    minx -= advance*0.5f;
    maxx -= advance*0.5f;
  }

  if (bounds.length) {
    if (bounds.length > 0) bounds.ptr[0] = minx;
    if (bounds.length > 1) bounds.ptr[1] = miny;
    if (bounds.length > 2) bounds.ptr[2] = maxx;
    if (bounds.length > 3) bounds.ptr[3] = maxy;
  }

  return advance;
}

public void fonsVertMetrics (FONScontext* stash, float* ascender, float* descender, float* lineh) nothrow @trusted @nogc {
  FONSfont* font;
  FONSstate* state = fons__getState(stash);
  short isize;

  if (stash is null) return;
  if (state.font < 0 || state.font >= stash.nfonts) return;
  font = stash.fonts[state.font];
  isize = cast(short)(state.size*10.0f);
  if (font is null || font.fdata is null) return;

  if (ascender) *ascender = font.ascender*isize/10.0f;
  if (descender) *descender = font.descender*isize/10.0f;
  if (lineh) *lineh = font.lineh*isize/10.0f;
}

public void fonsLineBounds (FONScontext* stash, float y, float* minyp, float* maxyp) nothrow @trusted @nogc {
  FONSfont* font;
  FONSstate* state = fons__getState(stash);
  short isize;

  if (minyp !is null) *minyp = 0;
  if (maxyp !is null) *maxyp = 0;

  if (stash is null) return;
  if (state.font < 0 || state.font >= stash.nfonts) return;
  font = stash.fonts[state.font];
  isize = cast(short)(state.size*10.0f);
  if (font is null || font.fdata is null) return;

  y += fons__getVertAlign(stash, font, state.talign, isize);

  if (stash.params.flags&FONS_ZERO_TOPLEFT) {
    immutable float miny = y-font.ascender*cast(float)isize/10.0f;
    immutable float maxy = miny+font.lineh*isize/10.0f;
    if (minyp !is null) *minyp = miny;
    if (maxyp !is null) *maxyp = maxy;
  } else {
    immutable float maxy = y+font.descender*cast(float)isize/10.0f;
    immutable float miny = maxy-font.lineh*isize/10.0f;
    if (minyp !is null) *minyp = miny;
    if (maxyp !is null) *maxyp = maxy;
  }
}

public const(ubyte)* fonsGetTextureData (FONScontext* stash, int* width, int* height) nothrow @trusted @nogc {
  if (width !is null) *width = stash.params.width;
  if (height !is null) *height = stash.params.height;
  return stash.texData;
}

public int fonsValidateTexture (FONScontext* stash, int* dirty) nothrow @trusted @nogc {
  if (stash.dirtyRect.ptr[0] < stash.dirtyRect.ptr[2] && stash.dirtyRect.ptr[1] < stash.dirtyRect.ptr[3]) {
    dirty[0] = stash.dirtyRect.ptr[0];
    dirty[1] = stash.dirtyRect.ptr[1];
    dirty[2] = stash.dirtyRect.ptr[2];
    dirty[3] = stash.dirtyRect.ptr[3];
    // Reset dirty rect
    stash.dirtyRect.ptr[0] = stash.params.width;
    stash.dirtyRect.ptr[1] = stash.params.height;
    stash.dirtyRect.ptr[2] = 0;
    stash.dirtyRect.ptr[3] = 0;
    return 1;
  }
  return 0;
}

public void fonsDeleteInternal (FONScontext* stash) nothrow @trusted @nogc {
  if (stash is null) return;

  if (stash.params.renderDelete !is null) stash.params.renderDelete(stash.params.userPtr);

  foreach (int i; 0..stash.nfonts) fons__freeFont(stash.fonts[i]);

  if (stash.atlas) fons__deleteAtlas(stash.atlas);
  if (stash.fonts) free(stash.fonts);
  if (stash.texData) free(stash.texData);
  if (stash.scratch) free(stash.scratch);
  if (stash.hashidx) free(stash.hashidx);
  free(stash);
}

public void fonsSetErrorCallback (FONScontext* stash, void function (void* uptr, int error, int val) nothrow @trusted @nogc callback, void* uptr) nothrow @trusted @nogc {
  if (stash is null) return;
  stash.handleError = callback;
  stash.errorUptr = uptr;
}

public void fonsGetAtlasSize (FONScontext* stash, int* width, int* height) nothrow @trusted @nogc {
  if (stash is null) return;
  *width = stash.params.width;
  *height = stash.params.height;
}

public int fonsExpandAtlas (FONScontext* stash, int width, int height) nothrow @trusted @nogc {
  int i, maxy = 0;
  ubyte* data = null;
  if (stash is null) return 0;

  width = nvg__max(width, stash.params.width);
  height = nvg__max(height, stash.params.height);

  if (width == stash.params.width && height == stash.params.height) return 1;

  // Flush pending glyphs.
  fons__flush(stash);

  // Create new texture
  if (stash.params.renderResize !is null) {
    if (stash.params.renderResize(stash.params.userPtr, width, height) == 0) return 0;
  }
  // Copy old texture data over.
  data = cast(ubyte*)malloc(width*height);
  if (data is null) return 0;
  for (i = 0; i < stash.params.height; i++) {
    ubyte* dst = &data[i*width];
    ubyte* src = &stash.texData[i*stash.params.width];
    memcpy(dst, src, stash.params.width);
    if (width > stash.params.width)
      memset(dst+stash.params.width, 0, width-stash.params.width);
  }
  if (height > stash.params.height) memset(&data[stash.params.height*width], 0, (height-stash.params.height)*width);

  free(stash.texData);
  stash.texData = data;

  // Increase atlas size
  fons__atlasExpand(stash.atlas, width, height);

  // Add existing data as dirty.
  for (i = 0; i < stash.atlas.nnodes; i++) maxy = nvg__max(maxy, stash.atlas.nodes[i].y);
  stash.dirtyRect.ptr[0] = 0;
  stash.dirtyRect.ptr[1] = 0;
  stash.dirtyRect.ptr[2] = stash.params.width;
  stash.dirtyRect.ptr[3] = maxy;

  stash.params.width = width;
  stash.params.height = height;
  stash.itw = 1.0f/stash.params.width;
  stash.ith = 1.0f/stash.params.height;

  return 1;
}

public bool fonsResetAtlas (FONScontext* stash, int width, int height) nothrow @trusted @nogc {
  if (stash is null) return false;

  // Flush pending glyphs.
  fons__flush(stash);

  // Create new texture
  if (stash.params.renderResize !is null) {
    if (stash.params.renderResize(stash.params.userPtr, width, height) == 0) return false;
  }

  // Reset atlas
  fons__atlasReset(stash.atlas, width, height);

  // Clear texture data.
  stash.texData = cast(ubyte*)realloc(stash.texData, width*height);
  if (stash.texData is null) return 0;
  memset(stash.texData, 0, width*height);

  // Reset dirty rect
  stash.dirtyRect.ptr[0] = width;
  stash.dirtyRect.ptr[1] = height;
  stash.dirtyRect.ptr[2] = 0;
  stash.dirtyRect.ptr[3] = 0;

  // Reset cached glyphs
  foreach (FONSfont* font; stash.fonts[0..stash.nfonts]) {
    if (font !is null) {
      font.nglyphs = 0;
      font.lut.ptr[0..FONS_HASH_LUT_SIZE] = -1;
    }
  }

  stash.params.width = width;
  stash.params.height = height;
  stash.itw = 1.0f/stash.params.width;
  stash.ith = 1.0f/stash.params.height;

  // Add white rect at 0, 0 for debug drawing.
  fons__addWhiteRect(stash, 2, 2);

  return true;
}


// ////////////////////////////////////////////////////////////////////////// //
// backgl
// ////////////////////////////////////////////////////////////////////////// //
import core.stdc.stdlib : malloc, realloc, free;
import core.stdc.string : memcpy, memset;

//import arsd.simpledisplay;
version(nanovg_builtin_opengl_bindings) { import arsd.simpledisplay; } else { import iv.glbinds; }

private:
// sdpy is missing that yet
static if (!is(typeof(GL_STENCIL_BUFFER_BIT))) enum uint GL_STENCIL_BUFFER_BIT = 0x00000400;


// OpenGL API missing from simpledisplay
private extern(System) nothrow @nogc {
  alias GLvoid = void;
  alias GLboolean = ubyte;
  alias GLuint = uint;
  alias GLenum = uint;
  alias GLchar = char;
  alias GLsizei = int;
  alias GLfloat = float;
  alias GLsizeiptr = ptrdiff_t;

  enum uint GL_STENCIL_BUFFER_BIT = 0x00000400;

  enum uint GL_INVALID_ENUM = 0x0500;

  enum uint GL_ZERO = 0;
  enum uint GL_ONE = 1;

  enum uint GL_FLOAT = 0x1406;

  enum uint GL_STREAM_DRAW = 0x88E0;

  enum uint GL_CCW = 0x0901;

  enum uint GL_STENCIL_TEST = 0x0B90;
  enum uint GL_SCISSOR_TEST = 0x0C11;

  enum uint GL_EQUAL = 0x0202;
  enum uint GL_NOTEQUAL = 0x0205;

  enum uint GL_ALWAYS = 0x0207;
  enum uint GL_KEEP = 0x1E00;

  enum uint GL_INCR = 0x1E02;

  enum uint GL_INCR_WRAP = 0x8507;
  enum uint GL_DECR_WRAP = 0x8508;

  enum uint GL_CULL_FACE = 0x0B44;
  enum uint GL_BACK = 0x0405;

  enum uint GL_FRAGMENT_SHADER = 0x8B30;
  enum uint GL_VERTEX_SHADER = 0x8B31;

  enum uint GL_COMPILE_STATUS = 0x8B81;
  enum uint GL_LINK_STATUS = 0x8B82;

  enum uint GL_UNPACK_ALIGNMENT = 0x0CF5;
  enum uint GL_UNPACK_ROW_LENGTH = 0x0CF2;
  enum uint GL_UNPACK_SKIP_PIXELS = 0x0CF4;
  enum uint GL_UNPACK_SKIP_ROWS = 0x0CF3;

  enum uint GL_GENERATE_MIPMAP = 0x8191;
  enum uint GL_LINEAR_MIPMAP_LINEAR = 0x2703;

  enum uint GL_RED = 0x1903;

  enum uint GL_TEXTURE0 = 0x84C0U;
  enum uint GL_TEXTURE1 = 0x84C1U;

  enum uint GL_ARRAY_BUFFER = 0x8892;

  enum uint GL_SRC_COLOR = 0x0300;
  enum uint GL_ONE_MINUS_SRC_COLOR = 0x0301;
  enum uint GL_SRC_ALPHA = 0x0302;
  enum uint GL_ONE_MINUS_SRC_ALPHA = 0x0303;
  enum uint GL_DST_ALPHA = 0x0304;
  enum uint GL_ONE_MINUS_DST_ALPHA = 0x0305;
  enum uint GL_DST_COLOR = 0x0306;
  enum uint GL_ONE_MINUS_DST_COLOR = 0x0307;
  enum uint GL_SRC_ALPHA_SATURATE = 0x0308;

  enum uint GL_INVERT = 0x150AU;

  enum uint GL_DEPTH_STENCIL = 0x84F9U;
  enum uint GL_UNSIGNED_INT_24_8 = 0x84FAU;

  enum uint GL_FRAMEBUFFER = 0x8D40U;
  enum uint GL_COLOR_ATTACHMENT0 = 0x8CE0U;
  enum uint GL_DEPTH_STENCIL_ATTACHMENT = 0x821AU;

  enum uint GL_FRAMEBUFFER_COMPLETE = 0x8CD5U;
  enum uint GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT = 0x8CD6U;
  enum uint GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT = 0x8CD7U;
  enum uint GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS = 0x8CD9U;
  enum uint GL_FRAMEBUFFER_UNSUPPORTED = 0x8CDDU;

  enum uint GL_COLOR_LOGIC_OP = 0x0BF2U;
  enum uint GL_CLEAR = 0x1500U;
  enum uint GL_COPY = 0x1503U;
  enum uint GL_XOR = 0x1506U;

  /*
  version(Windows) {
    private void* kglLoad (const(char)* name) {
      void* res = glGetProcAddress(name);
      if (res is null) {
        import core.sys.windows.windef, core.sys.windows.winbase;
        static HINSTANCE dll = null;
        if (dll is null) {
          dll = LoadLibraryA("opengl32.dll");
          if (dll is null) return null; // <32, but idc
          return GetProcAddress(dll, name);
        }
      }
    }
  } else {
    alias kglLoad = glGetProcAddress;
  }
  */

  alias glbfn_glStencilMask = void function(GLuint);
  __gshared glbfn_glStencilMask glStencilMask_NVGLZ; alias glStencilMask = glStencilMask_NVGLZ;
  alias glbfn_glStencilFunc = void function(GLenum, GLint, GLuint);
  __gshared glbfn_glStencilFunc glStencilFunc_NVGLZ; alias glStencilFunc = glStencilFunc_NVGLZ;
  alias glbfn_glGetShaderInfoLog = void function(GLuint, GLsizei, GLsizei*, GLchar*);
  __gshared glbfn_glGetShaderInfoLog glGetShaderInfoLog_NVGLZ; alias glGetShaderInfoLog = glGetShaderInfoLog_NVGLZ;
  alias glbfn_glGetProgramInfoLog = void function(GLuint, GLsizei, GLsizei*, GLchar*);
  __gshared glbfn_glGetProgramInfoLog glGetProgramInfoLog_NVGLZ; alias glGetProgramInfoLog = glGetProgramInfoLog_NVGLZ;
  alias glbfn_glCreateProgram = GLuint function();
  __gshared glbfn_glCreateProgram glCreateProgram_NVGLZ; alias glCreateProgram = glCreateProgram_NVGLZ;
  alias glbfn_glCreateShader = GLuint function(GLenum);
  __gshared glbfn_glCreateShader glCreateShader_NVGLZ; alias glCreateShader = glCreateShader_NVGLZ;
  alias glbfn_glShaderSource = void function(GLuint, GLsizei, const(GLchar*)*, const(GLint)*);
  __gshared glbfn_glShaderSource glShaderSource_NVGLZ; alias glShaderSource = glShaderSource_NVGLZ;
  alias glbfn_glCompileShader = void function(GLuint);
  __gshared glbfn_glCompileShader glCompileShader_NVGLZ; alias glCompileShader = glCompileShader_NVGLZ;
  alias glbfn_glGetShaderiv = void function(GLuint, GLenum, GLint*);
  __gshared glbfn_glGetShaderiv glGetShaderiv_NVGLZ; alias glGetShaderiv = glGetShaderiv_NVGLZ;
  alias glbfn_glAttachShader = void function(GLuint, GLuint);
  __gshared glbfn_glAttachShader glAttachShader_NVGLZ; alias glAttachShader = glAttachShader_NVGLZ;
  alias glbfn_glBindAttribLocation = void function(GLuint, GLuint, const(GLchar)*);
  __gshared glbfn_glBindAttribLocation glBindAttribLocation_NVGLZ; alias glBindAttribLocation = glBindAttribLocation_NVGLZ;
  alias glbfn_glLinkProgram = void function(GLuint);
  __gshared glbfn_glLinkProgram glLinkProgram_NVGLZ; alias glLinkProgram = glLinkProgram_NVGLZ;
  alias glbfn_glGetProgramiv = void function(GLuint, GLenum, GLint*);
  __gshared glbfn_glGetProgramiv glGetProgramiv_NVGLZ; alias glGetProgramiv = glGetProgramiv_NVGLZ;
  alias glbfn_glDeleteProgram = void function(GLuint);
  __gshared glbfn_glDeleteProgram glDeleteProgram_NVGLZ; alias glDeleteProgram = glDeleteProgram_NVGLZ;
  alias glbfn_glDeleteShader = void function(GLuint);
  __gshared glbfn_glDeleteShader glDeleteShader_NVGLZ; alias glDeleteShader = glDeleteShader_NVGLZ;
  alias glbfn_glGetUniformLocation = GLint function(GLuint, const(GLchar)*);
  __gshared glbfn_glGetUniformLocation glGetUniformLocation_NVGLZ; alias glGetUniformLocation = glGetUniformLocation_NVGLZ;
  alias glbfn_glGenBuffers = void function(GLsizei, GLuint*);
  __gshared glbfn_glGenBuffers glGenBuffers_NVGLZ; alias glGenBuffers = glGenBuffers_NVGLZ;
  alias glbfn_glPixelStorei = void function(GLenum, GLint);
  __gshared glbfn_glPixelStorei glPixelStorei_NVGLZ; alias glPixelStorei = glPixelStorei_NVGLZ;
  alias glbfn_glUniform4fv = void function(GLint, GLsizei, const(GLfloat)*);
  __gshared glbfn_glUniform4fv glUniform4fv_NVGLZ; alias glUniform4fv = glUniform4fv_NVGLZ;
  alias glbfn_glColorMask = void function(GLboolean, GLboolean, GLboolean, GLboolean);
  __gshared glbfn_glColorMask glColorMask_NVGLZ; alias glColorMask = glColorMask_NVGLZ;
  alias glbfn_glStencilOpSeparate = void function(GLenum, GLenum, GLenum, GLenum);
  __gshared glbfn_glStencilOpSeparate glStencilOpSeparate_NVGLZ; alias glStencilOpSeparate = glStencilOpSeparate_NVGLZ;
  alias glbfn_glDrawArrays = void function(GLenum, GLint, GLsizei);
  __gshared glbfn_glDrawArrays glDrawArrays_NVGLZ; alias glDrawArrays = glDrawArrays_NVGLZ;
  alias glbfn_glStencilOp = void function(GLenum, GLenum, GLenum);
  __gshared glbfn_glStencilOp glStencilOp_NVGLZ; alias glStencilOp = glStencilOp_NVGLZ;
  alias glbfn_glUseProgram = void function(GLuint);
  __gshared glbfn_glUseProgram glUseProgram_NVGLZ; alias glUseProgram = glUseProgram_NVGLZ;
  alias glbfn_glCullFace = void function(GLenum);
  __gshared glbfn_glCullFace glCullFace_NVGLZ; alias glCullFace = glCullFace_NVGLZ;
  alias glbfn_glFrontFace = void function(GLenum);
  __gshared glbfn_glFrontFace glFrontFace_NVGLZ; alias glFrontFace = glFrontFace_NVGLZ;
  alias glbfn_glActiveTexture = void function(GLenum);
  __gshared glbfn_glActiveTexture glActiveTexture_NVGLZ; alias glActiveTexture = glActiveTexture_NVGLZ;
  alias glbfn_glBindBuffer = void function(GLenum, GLuint);
  __gshared glbfn_glBindBuffer glBindBuffer_NVGLZ; alias glBindBuffer = glBindBuffer_NVGLZ;
  alias glbfn_glBufferData = void function(GLenum, GLsizeiptr, const(void)*, GLenum);
  __gshared glbfn_glBufferData glBufferData_NVGLZ; alias glBufferData = glBufferData_NVGLZ;
  alias glbfn_glEnableVertexAttribArray = void function(GLuint);
  __gshared glbfn_glEnableVertexAttribArray glEnableVertexAttribArray_NVGLZ; alias glEnableVertexAttribArray = glEnableVertexAttribArray_NVGLZ;
  alias glbfn_glVertexAttribPointer = void function(GLuint, GLint, GLenum, GLboolean, GLsizei, const(void)*);
  __gshared glbfn_glVertexAttribPointer glVertexAttribPointer_NVGLZ; alias glVertexAttribPointer = glVertexAttribPointer_NVGLZ;
  alias glbfn_glUniform1i = void function(GLint, GLint);
  __gshared glbfn_glUniform1i glUniform1i_NVGLZ; alias glUniform1i = glUniform1i_NVGLZ;
  alias glbfn_glUniform2fv = void function(GLint, GLsizei, const(GLfloat)*);
  __gshared glbfn_glUniform2fv glUniform2fv_NVGLZ; alias glUniform2fv = glUniform2fv_NVGLZ;
  alias glbfn_glDisableVertexAttribArray = void function(GLuint);
  __gshared glbfn_glDisableVertexAttribArray glDisableVertexAttribArray_NVGLZ; alias glDisableVertexAttribArray = glDisableVertexAttribArray_NVGLZ;
  alias glbfn_glDeleteBuffers = void function(GLsizei, const(GLuint)*);
  __gshared glbfn_glDeleteBuffers glDeleteBuffers_NVGLZ; alias glDeleteBuffers = glDeleteBuffers_NVGLZ;
  alias glbfn_glBlendFuncSeparate = void function(GLenum, GLenum, GLenum, GLenum);
  __gshared glbfn_glBlendFuncSeparate glBlendFuncSeparate_NVGLZ; alias glBlendFuncSeparate = glBlendFuncSeparate_NVGLZ;

  alias glbfn_glLogicOp = void function (GLenum opcode);
  __gshared glbfn_glLogicOp glLogicOp_NVGLZ; alias glLogicOp = glLogicOp_NVGLZ;
  alias glbfn_glFramebufferTexture2D = void function (GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
  __gshared glbfn_glFramebufferTexture2D glFramebufferTexture2D_NVGLZ; alias glFramebufferTexture2D = glFramebufferTexture2D_NVGLZ;
  alias glbfn_glDeleteFramebuffers = void function (GLsizei n, const(GLuint)* framebuffers);
  __gshared glbfn_glDeleteFramebuffers glDeleteFramebuffers_NVGLZ; alias glDeleteFramebuffers = glDeleteFramebuffers_NVGLZ;
  alias glbfn_glGenFramebuffers = void function (GLsizei n, GLuint* framebuffers);
  __gshared glbfn_glGenFramebuffers glGenFramebuffers_NVGLZ; alias glGenFramebuffers = glGenFramebuffers_NVGLZ;
  alias glbfn_glCheckFramebufferStatus = GLenum function (GLenum target);
  __gshared glbfn_glCheckFramebufferStatus glCheckFramebufferStatus_NVGLZ; alias glCheckFramebufferStatus = glCheckFramebufferStatus_NVGLZ;
  alias glbfn_glBindFramebuffer = void function (GLenum target, GLuint framebuffer);
  __gshared glbfn_glBindFramebuffer glBindFramebuffer_NVGLZ; alias glBindFramebuffer = glBindFramebuffer_NVGLZ;

  private void nanovgInitOpenGL () {
    __gshared bool initialized = false;
    if (initialized) return;
    glStencilMask_NVGLZ = cast(glbfn_glStencilMask)glbindGetProcAddress(`glStencilMask`);
    if (glStencilMask_NVGLZ is null) assert(0, `OpenGL function 'glStencilMask' not found!`);
    glStencilFunc_NVGLZ = cast(glbfn_glStencilFunc)glbindGetProcAddress(`glStencilFunc`);
    if (glStencilFunc_NVGLZ is null) assert(0, `OpenGL function 'glStencilFunc' not found!`);
    glGetShaderInfoLog_NVGLZ = cast(glbfn_glGetShaderInfoLog)glbindGetProcAddress(`glGetShaderInfoLog`);
    if (glGetShaderInfoLog_NVGLZ is null) assert(0, `OpenGL function 'glGetShaderInfoLog' not found!`);
    glGetProgramInfoLog_NVGLZ = cast(glbfn_glGetProgramInfoLog)glbindGetProcAddress(`glGetProgramInfoLog`);
    if (glGetProgramInfoLog_NVGLZ is null) assert(0, `OpenGL function 'glGetProgramInfoLog' not found!`);
    glCreateProgram_NVGLZ = cast(glbfn_glCreateProgram)glbindGetProcAddress(`glCreateProgram`);
    if (glCreateProgram_NVGLZ is null) assert(0, `OpenGL function 'glCreateProgram' not found!`);
    glCreateShader_NVGLZ = cast(glbfn_glCreateShader)glbindGetProcAddress(`glCreateShader`);
    if (glCreateShader_NVGLZ is null) assert(0, `OpenGL function 'glCreateShader' not found!`);
    glShaderSource_NVGLZ = cast(glbfn_glShaderSource)glbindGetProcAddress(`glShaderSource`);
    if (glShaderSource_NVGLZ is null) assert(0, `OpenGL function 'glShaderSource' not found!`);
    glCompileShader_NVGLZ = cast(glbfn_glCompileShader)glbindGetProcAddress(`glCompileShader`);
    if (glCompileShader_NVGLZ is null) assert(0, `OpenGL function 'glCompileShader' not found!`);
    glGetShaderiv_NVGLZ = cast(glbfn_glGetShaderiv)glbindGetProcAddress(`glGetShaderiv`);
    if (glGetShaderiv_NVGLZ is null) assert(0, `OpenGL function 'glGetShaderiv' not found!`);
    glAttachShader_NVGLZ = cast(glbfn_glAttachShader)glbindGetProcAddress(`glAttachShader`);
    if (glAttachShader_NVGLZ is null) assert(0, `OpenGL function 'glAttachShader' not found!`);
    glBindAttribLocation_NVGLZ = cast(glbfn_glBindAttribLocation)glbindGetProcAddress(`glBindAttribLocation`);
    if (glBindAttribLocation_NVGLZ is null) assert(0, `OpenGL function 'glBindAttribLocation' not found!`);
    glLinkProgram_NVGLZ = cast(glbfn_glLinkProgram)glbindGetProcAddress(`glLinkProgram`);
    if (glLinkProgram_NVGLZ is null) assert(0, `OpenGL function 'glLinkProgram' not found!`);
    glGetProgramiv_NVGLZ = cast(glbfn_glGetProgramiv)glbindGetProcAddress(`glGetProgramiv`);
    if (glGetProgramiv_NVGLZ is null) assert(0, `OpenGL function 'glGetProgramiv' not found!`);
    glDeleteProgram_NVGLZ = cast(glbfn_glDeleteProgram)glbindGetProcAddress(`glDeleteProgram`);
    if (glDeleteProgram_NVGLZ is null) assert(0, `OpenGL function 'glDeleteProgram' not found!`);
    glDeleteShader_NVGLZ = cast(glbfn_glDeleteShader)glbindGetProcAddress(`glDeleteShader`);
    if (glDeleteShader_NVGLZ is null) assert(0, `OpenGL function 'glDeleteShader' not found!`);
    glGetUniformLocation_NVGLZ = cast(glbfn_glGetUniformLocation)glbindGetProcAddress(`glGetUniformLocation`);
    if (glGetUniformLocation_NVGLZ is null) assert(0, `OpenGL function 'glGetUniformLocation' not found!`);
    glGenBuffers_NVGLZ = cast(glbfn_glGenBuffers)glbindGetProcAddress(`glGenBuffers`);
    if (glGenBuffers_NVGLZ is null) assert(0, `OpenGL function 'glGenBuffers' not found!`);
    glPixelStorei_NVGLZ = cast(glbfn_glPixelStorei)glbindGetProcAddress(`glPixelStorei`);
    if (glPixelStorei_NVGLZ is null) assert(0, `OpenGL function 'glPixelStorei' not found!`);
    glUniform4fv_NVGLZ = cast(glbfn_glUniform4fv)glbindGetProcAddress(`glUniform4fv`);
    if (glUniform4fv_NVGLZ is null) assert(0, `OpenGL function 'glUniform4fv' not found!`);
    glColorMask_NVGLZ = cast(glbfn_glColorMask)glbindGetProcAddress(`glColorMask`);
    if (glColorMask_NVGLZ is null) assert(0, `OpenGL function 'glColorMask' not found!`);
    glStencilOpSeparate_NVGLZ = cast(glbfn_glStencilOpSeparate)glbindGetProcAddress(`glStencilOpSeparate`);
    if (glStencilOpSeparate_NVGLZ is null) assert(0, `OpenGL function 'glStencilOpSeparate' not found!`);
    glDrawArrays_NVGLZ = cast(glbfn_glDrawArrays)glbindGetProcAddress(`glDrawArrays`);
    if (glDrawArrays_NVGLZ is null) assert(0, `OpenGL function 'glDrawArrays' not found!`);
    glStencilOp_NVGLZ = cast(glbfn_glStencilOp)glbindGetProcAddress(`glStencilOp`);
    if (glStencilOp_NVGLZ is null) assert(0, `OpenGL function 'glStencilOp' not found!`);
    glUseProgram_NVGLZ = cast(glbfn_glUseProgram)glbindGetProcAddress(`glUseProgram`);
    if (glUseProgram_NVGLZ is null) assert(0, `OpenGL function 'glUseProgram' not found!`);
    glCullFace_NVGLZ = cast(glbfn_glCullFace)glbindGetProcAddress(`glCullFace`);
    if (glCullFace_NVGLZ is null) assert(0, `OpenGL function 'glCullFace' not found!`);
    glFrontFace_NVGLZ = cast(glbfn_glFrontFace)glbindGetProcAddress(`glFrontFace`);
    if (glFrontFace_NVGLZ is null) assert(0, `OpenGL function 'glFrontFace' not found!`);
    glActiveTexture_NVGLZ = cast(glbfn_glActiveTexture)glbindGetProcAddress(`glActiveTexture`);
    if (glActiveTexture_NVGLZ is null) assert(0, `OpenGL function 'glActiveTexture' not found!`);
    glBindBuffer_NVGLZ = cast(glbfn_glBindBuffer)glbindGetProcAddress(`glBindBuffer`);
    if (glBindBuffer_NVGLZ is null) assert(0, `OpenGL function 'glBindBuffer' not found!`);
    glBufferData_NVGLZ = cast(glbfn_glBufferData)glbindGetProcAddress(`glBufferData`);
    if (glBufferData_NVGLZ is null) assert(0, `OpenGL function 'glBufferData' not found!`);
    glEnableVertexAttribArray_NVGLZ = cast(glbfn_glEnableVertexAttribArray)glbindGetProcAddress(`glEnableVertexAttribArray`);
    if (glEnableVertexAttribArray_NVGLZ is null) assert(0, `OpenGL function 'glEnableVertexAttribArray' not found!`);
    glVertexAttribPointer_NVGLZ = cast(glbfn_glVertexAttribPointer)glbindGetProcAddress(`glVertexAttribPointer`);
    if (glVertexAttribPointer_NVGLZ is null) assert(0, `OpenGL function 'glVertexAttribPointer' not found!`);
    glUniform1i_NVGLZ = cast(glbfn_glUniform1i)glbindGetProcAddress(`glUniform1i`);
    if (glUniform1i_NVGLZ is null) assert(0, `OpenGL function 'glUniform1i' not found!`);
    glUniform2fv_NVGLZ = cast(glbfn_glUniform2fv)glbindGetProcAddress(`glUniform2fv`);
    if (glUniform2fv_NVGLZ is null) assert(0, `OpenGL function 'glUniform2fv' not found!`);
    glDisableVertexAttribArray_NVGLZ = cast(glbfn_glDisableVertexAttribArray)glbindGetProcAddress(`glDisableVertexAttribArray`);
    if (glDisableVertexAttribArray_NVGLZ is null) assert(0, `OpenGL function 'glDisableVertexAttribArray' not found!`);
    glDeleteBuffers_NVGLZ = cast(glbfn_glDeleteBuffers)glbindGetProcAddress(`glDeleteBuffers`);
    if (glDeleteBuffers_NVGLZ is null) assert(0, `OpenGL function 'glDeleteBuffers' not found!`);
    glBlendFuncSeparate_NVGLZ = cast(glbfn_glBlendFuncSeparate)glbindGetProcAddress(`glBlendFuncSeparate`);
    if (glBlendFuncSeparate_NVGLZ is null) assert(0, `OpenGL function 'glBlendFuncSeparate' not found!`);

    glLogicOp_NVGLZ = cast(glbfn_glLogicOp)glbindGetProcAddress(`glLogicOp`);
    if (glLogicOp_NVGLZ is null) assert(0, `OpenGL function 'glLogicOp' not found!`);
    glFramebufferTexture2D_NVGLZ = cast(glbfn_glFramebufferTexture2D)glbindGetProcAddress(`glFramebufferTexture2D`);
    if (glFramebufferTexture2D_NVGLZ is null) assert(0, `OpenGL function 'glFramebufferTexture2D' not found!`);
    glDeleteFramebuffers_NVGLZ = cast(glbfn_glDeleteFramebuffers)glbindGetProcAddress(`glDeleteFramebuffers`);
    if (glDeleteFramebuffers_NVGLZ is null) assert(0, `OpenGL function 'glDeleteFramebuffers' not found!`);
    glGenFramebuffers_NVGLZ = cast(glbfn_glGenFramebuffers)glbindGetProcAddress(`glGenFramebuffers`);
    if (glGenFramebuffers_NVGLZ is null) assert(0, `OpenGL function 'glGenFramebuffers' not found!`);
    glCheckFramebufferStatus_NVGLZ = cast(glbfn_glCheckFramebufferStatus)glbindGetProcAddress(`glCheckFramebufferStatus`);
    if (glCheckFramebufferStatus_NVGLZ is null) assert(0, `OpenGL function 'glCheckFramebufferStatus' not found!`);
    glBindFramebuffer_NVGLZ = cast(glbfn_glBindFramebuffer)glbindGetProcAddress(`glBindFramebuffer`);
    if (glBindFramebuffer_NVGLZ is null) assert(0, `OpenGL function 'glBindFramebuffer' not found!`);

    initialized = true;
  }
}


/// Context creation flags.
/// Group: context_management
public enum NVGContextFlag : int {
  /// Nothing special, i.e. empty flag.
  None = 0,
  /// Flag indicating if geometry based anti-aliasing is used (may not be needed when using MSAA).
  Antialias = 1U<<0,
  /** Flag indicating if strokes should be drawn using stencil buffer. The rendering will be a little
    * slower, but path overlaps (i.e. self-intersecting or sharp turns) will be drawn just once. */
  StencilStrokes = 1U<<1,
  /// Flag indicating that additional debug checks are done.
  Debug = 1U<<2,
  /// Filter (antialias) fonts
  FontAA = 1U<<7,
  /// Don't filter (antialias) fonts
  FontNoAA = 1U<<8,
  /// You can use this as a substitute for default flags, for cases like this: `nvgCreateContext(NVGContextFlag.Default, NVGContextFlag.Debug);`.
  Default = 1U<<31,
}

public enum NANOVG_GL_USE_STATE_FILTER = true;

/// These are additional flags on top of [NVGImageFlag].
/// Group: images
public enum NVGImageFlagsGL : int {
  NoDelete = 1<<16,  // Do not delete GL texture handle.
}


/// Returns flags for glClear().
/// Group: context_management
public uint glNVGClearFlags () pure nothrow @safe @nogc {
  pragma(inline, true);
  return (GL_COLOR_BUFFER_BIT|/*GL_DEPTH_BUFFER_BIT|*/GL_STENCIL_BUFFER_BIT);
}


// ////////////////////////////////////////////////////////////////////////// //
private:

version = nanovega_shared_stencil;
//version = nanovega_debug_clipping;

enum GLNVGuniformLoc {
  ViewSize,
  Tex,
  Frag,
  TMat,
  TTr,
  ClipTex,
}

alias GLNVGshaderType = int;
enum /*GLNVGshaderType*/ {
  NSVG_SHADER_FILLCOLOR,
  NSVG_SHADER_FILLGRAD,
  NSVG_SHADER_FILLIMG,
  NSVG_SHADER_SIMPLE, // also used for clipfill
  NSVG_SHADER_IMG,
}

struct GLNVGshader {
  GLuint prog;
  GLuint frag;
  GLuint vert;
  GLint[GLNVGuniformLoc.max+1] loc;
}

struct GLNVGtexture {
  int id;
  GLuint tex;
  int width, height;
  NVGtexture type;
  int flags;
  int rc;
  int nextfree;
}

struct GLNVGblend {
  bool simple;
  GLenum srcRGB;
  GLenum dstRGB;
  GLenum srcAlpha;
  GLenum dstAlpha;
}

alias GLNVGcallType = int;
enum /*GLNVGcallType*/ {
  GLNVG_NONE = 0,
  GLNVG_FILL,
  GLNVG_CONVEXFILL,
  GLNVG_STROKE,
  GLNVG_TRIANGLES,
  GLNVG_AFFINE, // change affine transformation matrix
  GLNVG_PUSHCLIP,
  GLNVG_POPCLIP,
  GLNVG_RESETCLIP,
  GLNVG_CLIP_DDUMP_ON,
  GLNVG_CLIP_DDUMP_OFF,
}

struct GLNVGcall {
  int type;
  int evenOdd; // for fill
  int image;
  int pathOffset;
  int pathCount;
  int triangleOffset;
  int triangleCount;
  int uniformOffset;
  NVGMatrix affine;
  GLNVGblend blendFunc;
  NVGClipMode clipmode;
}

struct GLNVGpath {
  int fillOffset;
  int fillCount;
  int strokeOffset;
  int strokeCount;
}

align(1) struct GLNVGfragUniforms {
align(1):
  enum UNIFORM_ARRAY_SIZE = 13;
  // note: after modifying layout or size of uniform array,
  // don't forget to also update the fragment shader source!
  align(1) union {
  align(1):
    align(1) struct {
    align(1):
      float[12] scissorMat; // matrices are actually 3 vec4s
      float[12] paintMat;
      NVGColor innerCol;
      NVGColor middleCol;
      NVGColor outerCol;
      float[2] scissorExt;
      float[2] scissorScale;
      float[2] extent;
      float radius;
      float feather;
      float strokeMult;
      float strokeThr;
      float texType;
      float type;
      float doclip;
      float midp; // for gradients
      float unused2, unused3;
    }
    float[4][UNIFORM_ARRAY_SIZE] uniformArray;
  }
}

enum GLMaskState {
  DontMask = -1,
  Uninitialized = 0,
  Initialized = 1,
  JustCleared = 2,
}

struct GLNVGcontext {
  GLNVGshader shader;
  GLNVGtexture* textures;
  float[2] view;
  int freetexid; // -1: none
  int ntextures;
  int ctextures;
  GLuint vertBuf;
  int fragSize;
  int flags;
  // FBOs for masks
  GLuint[NVG_MAX_STATES] fbo;
  GLuint[2][NVG_MAX_STATES] fboTex; // FBO textures: [0] is color, [1] is stencil
  int fboWidth, fboHeight;
  GLMaskState[NVG_MAX_STATES] maskStack;
  int msp; // mask stack pointer; starts from `0`; points to next free item; see below for logic description
  int lastClipFBO; // -666: cache invalidated; -1: don't mask
  int lastClipUniOfs;
  bool doClipUnion; // specal mode
  GLNVGshader shaderFillFBO;
  GLNVGshader shaderCopyFBO;

  // Per frame buffers
  GLNVGcall* calls;
  int ccalls;
  int ncalls;
  GLNVGpath* paths;
  int cpaths;
  int npaths;
  NVGvertex* verts;
  int cverts;
  int nverts;
  ubyte* uniforms;
  int cuniforms;
  int nuniforms;
  NVGMatrix lastAffine;

  // cached state
  static if (NANOVG_GL_USE_STATE_FILTER) {
    GLuint boundTexture;
    GLuint stencilMask;
    GLenum stencilFunc;
    GLint stencilFuncRef;
    GLuint stencilFuncMask;
    GLNVGblend blendFunc;
  }
}

int glnvg__maxi() (int a, int b) { pragma(inline, true); return (a > b ? a : b); }

void glnvg__bindTexture (GLNVGcontext* gl, GLuint tex) nothrow @trusted @nogc {
  static if (NANOVG_GL_USE_STATE_FILTER) {
    if (gl.boundTexture != tex) {
      gl.boundTexture = tex;
      glBindTexture(GL_TEXTURE_2D, tex);
    }
  } else {
    glBindTexture(GL_TEXTURE_2D, tex);
  }
}

void glnvg__stencilMask (GLNVGcontext* gl, GLuint mask) nothrow @trusted @nogc {
  static if (NANOVG_GL_USE_STATE_FILTER) {
    if (gl.stencilMask != mask) {
      gl.stencilMask = mask;
      glStencilMask(mask);
    }
  } else {
    glStencilMask(mask);
  }
}

void glnvg__stencilFunc (GLNVGcontext* gl, GLenum func, GLint ref_, GLuint mask) nothrow @trusted @nogc {
  static if (NANOVG_GL_USE_STATE_FILTER) {
    if (gl.stencilFunc != func || gl.stencilFuncRef != ref_ || gl.stencilFuncMask != mask) {
      gl.stencilFunc = func;
      gl.stencilFuncRef = ref_;
      gl.stencilFuncMask = mask;
      glStencilFunc(func, ref_, mask);
    }
  } else {
    glStencilFunc(func, ref_, mask);
  }
}

// texture id is never zero
GLNVGtexture* glnvg__allocTexture (GLNVGcontext* gl) nothrow @trusted @nogc {
  GLNVGtexture* tex = null;

  int tid = gl.freetexid;
  if (tid == -1) {
    if (gl.ntextures >= gl.ctextures) {
      assert(gl.ntextures == gl.ctextures);
      int ctextures = (gl.ctextures == 0 ? 16 : glnvg__maxi(tid+1, 4)+gl.ctextures/2); // 1.5x overallocate
      GLNVGtexture* textures = cast(GLNVGtexture*)realloc(gl.textures, GLNVGtexture.sizeof*ctextures);
      if (textures is null) return null;
      memset(&textures[gl.ctextures], 0, (ctextures-gl.ctextures)*GLNVGtexture.sizeof);
      version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("allocated more textures (n=%d; c=%d; nc=%d)\n", gl.ntextures, gl.ctextures, ctextures); }}
      gl.textures = textures;
      gl.ctextures = ctextures;
    }
    tid = gl.ntextures++;
    version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("  got next free texture id %d, ntextures=%d\n", tid+1, gl.ntextures); }}
  } else {
    gl.freetexid = gl.textures[tid].nextfree;
  }
  assert(tid <= gl.ntextures);

  assert(gl.textures[tid].id == 0);
  tex = &gl.textures[tid];
  memset(tex, 0, (*tex).sizeof);
  tex.id = tid+1;
  tex.rc = 1;
  tex.nextfree = -1;

  version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("allocated texture with id %d (%d)\n", tex.id, tid+1); }}

  return tex;
}

GLNVGtexture* glnvg__findTexture (GLNVGcontext* gl, int id) nothrow @trusted @nogc {
  if (id <= 0 || id > gl.ntextures) return null;
  if (gl.textures[id-1].id == 0) return null; // free one
  assert(gl.textures[id-1].id == id);
  return &gl.textures[id-1];
}

bool glnvg__deleteTexture (GLNVGcontext* gl, ref int id) nothrow @trusted @nogc {
  if (id <= 0 || id > gl.ntextures) return false;
  auto tx = &gl.textures[id-1];
  if (tx.id == 0) { id = 0; return false; } // free one
  assert(tx.id == id);
  assert(tx.tex != 0);
  version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("decrefing texture with id %d (%d)\n", tx.id, id); }}
  if (--tx.rc == 0) {
    if ((tx.flags&NVGImageFlagsGL.NoDelete) == 0) glDeleteTextures(1, &tx.tex);
    version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("deleted texture with id %d (%d); glid=%u\n", tx.id, id, tx.tex); }}
    memset(tx, 0, (*tx).sizeof);
    //{ import core.stdc.stdio; printf("deleting texture with id %d\n", id); }
    tx.nextfree = gl.freetexid;
    gl.freetexid = id-1;
  }
  id = 0;
  return true;
}

void glnvg__dumpShaderError (GLuint shader, const(char)* name, const(char)* type) nothrow @trusted @nogc {
  import core.stdc.stdio : fprintf, stderr;
  GLchar[512+1] str = 0;
  GLsizei len = 0;
  glGetShaderInfoLog(shader, 512, &len, str.ptr);
  if (len > 512) len = 512;
  str[len] = '\0';
  fprintf(stderr, "Shader %s/%s error:\n%s\n", name, type, str.ptr);
}

void glnvg__dumpProgramError (GLuint prog, const(char)* name) nothrow @trusted @nogc {
  import core.stdc.stdio : fprintf, stderr;
  GLchar[512+1] str = 0;
  GLsizei len = 0;
  glGetProgramInfoLog(prog, 512, &len, str.ptr);
  if (len > 512) len = 512;
  str[len] = '\0';
  fprintf(stderr, "Program %s error:\n%s\n", name, str.ptr);
}

void glnvg__resetError(bool force=false) (GLNVGcontext* gl) nothrow @trusted @nogc {
  static if (!force) {
    if ((gl.flags&NVGContextFlag.Debug) == 0) return;
  }
  glGetError();
}

void glnvg__checkError(bool force=false) (GLNVGcontext* gl, const(char)* str) nothrow @trusted @nogc {
  GLenum err;
  static if (!force) {
    if ((gl.flags&NVGContextFlag.Debug) == 0) return;
  }
  err = glGetError();
  if (err != GL_NO_ERROR) {
    import core.stdc.stdio : fprintf, stderr;
    fprintf(stderr, "Error %08x after %s\n", err, str);
    return;
  }
}

bool glnvg__createShader (GLNVGshader* shader, const(char)* name, const(char)* header, const(char)* opts, const(char)* vshader, const(char)* fshader) nothrow @trusted @nogc {
  GLint status;
  GLuint prog, vert, frag;
  const(char)*[3] str;

  memset(shader, 0, (*shader).sizeof);

  prog = glCreateProgram();
  vert = glCreateShader(GL_VERTEX_SHADER);
  frag = glCreateShader(GL_FRAGMENT_SHADER);
  str[0] = header;
  str[1] = (opts !is null ? opts : "");
  str[2] = vshader;
  glShaderSource(vert, 3, cast(const(char)**)str.ptr, null);

  glCompileShader(vert);
  glGetShaderiv(vert, GL_COMPILE_STATUS, &status);
  if (status != GL_TRUE) {
    glnvg__dumpShaderError(vert, name, "vert");
    return false;
  }

  str[0] = header;
  str[1] = (opts !is null ? opts : "");
  str[2] = fshader;
  glShaderSource(frag, 3, cast(const(char)**)str.ptr, null);

  glCompileShader(frag);
  glGetShaderiv(frag, GL_COMPILE_STATUS, &status);
  if (status != GL_TRUE) {
    glnvg__dumpShaderError(frag, name, "frag");
    return false;
  }

  glAttachShader(prog, vert);
  glAttachShader(prog, frag);

  glBindAttribLocation(prog, 0, "vertex");
  glBindAttribLocation(prog, 1, "tcoord");

  glLinkProgram(prog);
  glGetProgramiv(prog, GL_LINK_STATUS, &status);
  if (status != GL_TRUE) {
    glnvg__dumpProgramError(prog, name);
    return false;
  }

  shader.prog = prog;
  shader.vert = vert;
  shader.frag = frag;

  return true;
}

void glnvg__deleteShader (GLNVGshader* shader) nothrow @trusted @nogc {
  if (shader.prog != 0) glDeleteProgram(shader.prog);
  if (shader.vert != 0) glDeleteShader(shader.vert);
  if (shader.frag != 0) glDeleteShader(shader.frag);
}

void glnvg__getUniforms (GLNVGshader* shader) nothrow @trusted @nogc {
  shader.loc[GLNVGuniformLoc.ViewSize] = glGetUniformLocation(shader.prog, "viewSize");
  shader.loc[GLNVGuniformLoc.Tex] = glGetUniformLocation(shader.prog, "tex");
  shader.loc[GLNVGuniformLoc.Frag] = glGetUniformLocation(shader.prog, "frag");
  shader.loc[GLNVGuniformLoc.TMat] = glGetUniformLocation(shader.prog, "tmat");
  shader.loc[GLNVGuniformLoc.TTr] = glGetUniformLocation(shader.prog, "ttr");
  shader.loc[GLNVGuniformLoc.ClipTex] = glGetUniformLocation(shader.prog, "clipTex");
}

void glnvg__killFBOs (GLNVGcontext* gl) nothrow @trusted @nogc {
  foreach (immutable fidx, ref GLuint fbo; gl.fbo[]) {
    if (fbo != 0) {
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, 0, 0);
      foreach (ref GLuint tid; gl.fboTex.ptr[fidx][]) if (tid != 0) { glDeleteTextures(1, &tid); tid = 0; }
      glDeleteFramebuffers(1, &fbo);
      fbo = 0;
    }
  }
  gl.fboWidth = gl.fboHeight = 0;
}

// returns `true` is new FBO was created
// will not unbind buffer, if it was created
bool glnvg__allocFBO (GLNVGcontext* gl, int fidx, bool doclear=true) nothrow @trusted @nogc {
  assert(fidx >= 0 && fidx < gl.fbo.length);
  assert(gl.fboWidth > 0);
  assert(gl.fboHeight > 0);

  if (gl.fbo.ptr[fidx] != 0) return false; // nothing to do, this FBO is already initialized

  glnvg__resetError(gl);

  // allocate FBO object
  GLuint fbo = 0;
  glGenFramebuffers(1, &fbo);
  if (fbo == 0) assert(0, "NanoVega: cannot create FBO");
  glnvg__checkError(gl, "glnvg__allocFBO: glGenFramebuffers");
  glBindFramebuffer(GL_FRAMEBUFFER, fbo);
  //scope(exit) glBindFramebuffer(GL_FRAMEBUFFER, 0);

  // attach 2D texture to this FBO
  GLuint tidColor = 0;
  glGenTextures(1, &tidColor);
  if (tidColor == 0) assert(0, "NanoVega: cannot create RGBA texture for FBO");
  glBindTexture(GL_TEXTURE_2D, tidColor);
  //scope(exit) glBindTexture(GL_TEXTURE_2D, 0);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glnvg__checkError(gl, "glnvg__allocFBO: glTexParameterf: GL_TEXTURE_WRAP_S");
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glnvg__checkError(gl, "glnvg__allocFBO: glTexParameterf: GL_TEXTURE_WRAP_T");
  //FIXME: linear or nearest?
  //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glnvg__checkError(gl, "glnvg__allocFBO: glTexParameterf: GL_TEXTURE_MIN_FILTER");
  //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glnvg__checkError(gl, "glnvg__allocFBO: glTexParameterf: GL_TEXTURE_MAG_FILTER");
  // empty texture
  //glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, gl.fboWidth, gl.fboHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
  // create texture with only one color channel
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, gl.fboWidth, gl.fboHeight, 0, GL_RED, GL_UNSIGNED_BYTE, null);
  //glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, gl.fboWidth, gl.fboHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
  glnvg__checkError(gl, "glnvg__allocFBO: glTexImage2D (color)");
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tidColor, 0);
  glnvg__checkError(gl, "glnvg__allocFBO: glFramebufferTexture2D (color)");

  // attach stencil texture to this FBO
  GLuint tidStencil = 0;
  version(nanovega_shared_stencil) {
    if (gl.fboTex.ptr[0].ptr[0] == 0) {
      glGenTextures(1, &tidStencil);
      if (tidStencil == 0) assert(0, "NanoVega: cannot create stencil texture for FBO");
      gl.fboTex.ptr[0].ptr[0] = tidStencil;
    } else {
      tidStencil = gl.fboTex.ptr[0].ptr[0];
    }
    if (fidx != 0) gl.fboTex.ptr[fidx].ptr[1] = 0; // stencil texture is shared among FBOs
  } else {
    glGenTextures(1, &tidStencil);
    if (tidStencil == 0) assert(0, "NanoVega: cannot create stencil texture for FBO");
    gl.fboTex.ptr[0].ptr[0] = tidStencil;
  }
  glBindTexture(GL_TEXTURE_2D, tidStencil);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_STENCIL, gl.fboWidth, gl.fboHeight, 0, GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, null);
  glnvg__checkError(gl, "glnvg__allocFBO: glTexImage2D (stencil)");
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, tidStencil, 0);
  glnvg__checkError(gl, "glnvg__allocFBO: glFramebufferTexture2D (stencil)");

  {
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
      version(all) {
        import core.stdc.stdio;
        if (status == GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT) printf("fucked attachement\n");
        if (status == GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS) printf("fucked dimensions\n");
        if (status == GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT) printf("missing attachement\n");
        if (status == GL_FRAMEBUFFER_UNSUPPORTED) printf("unsupported\n");
      }
      assert(0, "NanoVega: framebuffer creation failed");
    }
  }

  // clear 'em all
  if (doclear) {
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
  }

  // save texture ids
  gl.fbo.ptr[fidx] = fbo;
  gl.fboTex.ptr[fidx].ptr[0] = tidColor;
  version(nanovega_shared_stencil) {} else {
    gl.fboTex.ptr[fidx].ptr[1] = tidStencil;
  }

  static if (NANOVG_GL_USE_STATE_FILTER) glBindTexture(GL_TEXTURE_2D, gl.boundTexture);

  version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): created with index %d\n", gl.msp-1, fidx); }

  return true;
}

// will not unbind buffer
void glnvg__clearFBO (GLNVGcontext* gl, int fidx) nothrow @trusted @nogc {
  assert(fidx >= 0 && fidx < gl.fbo.length);
  assert(gl.fboWidth > 0);
  assert(gl.fboHeight > 0);
  assert(gl.fbo.ptr[fidx] != 0);
  glBindFramebuffer(GL_FRAMEBUFFER, gl.fbo.ptr[fidx]);
  glClearColor(0, 0, 0, 0);
  glClear(GL_COLOR_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
  version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): cleared with index %d\n", gl.msp-1, fidx); }
}

// will not unbind buffer
void glnvg__copyFBOToFrom (GLNVGcontext* gl, int didx, int sidx) nothrow @trusted @nogc {
  import core.stdc.string : memset;
  assert(didx >= 0 && didx < gl.fbo.length);
  assert(sidx >= 0 && sidx < gl.fbo.length);
  assert(gl.fboWidth > 0);
  assert(gl.fboHeight > 0);
  assert(gl.fbo.ptr[didx] != 0);
  assert(gl.fbo.ptr[sidx] != 0);
  if (didx == sidx) return;

  /*
  glBindFramebuffer(GL_FRAMEBUFFER, gl.fbo.ptr[didx]);
  glClearColor(0, 0, 0, 0);
  glClear(GL_COLOR_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
  return;
  */

  version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): copy FBO: %d -> %d\n", gl.msp-1, sidx, didx); }

  glUseProgram(gl.shaderCopyFBO.prog);

  glBindFramebuffer(GL_FRAMEBUFFER, gl.fbo.ptr[didx]);
  glDisable(GL_CULL_FACE);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
  glBindTexture(GL_TEXTURE_2D, gl.fboTex.ptr[sidx].ptr[0]);
  // copy texture by drawing full quad
  enum x = 0;
  enum y = 0;
  immutable int w = gl.fboWidth;
  immutable int h = gl.fboHeight;
  glBegin(GL_QUADS);
    glVertex2i(x, y); // top-left
    glVertex2i(w, y); // top-right
    glVertex2i(w, h); // bottom-right
    glVertex2i(x, h); // bottom-left
  glEnd();

  // restore state (but don't unbind FBO)
  static if (NANOVG_GL_USE_STATE_FILTER) glBindTexture(GL_TEXTURE_2D, gl.boundTexture);
  glEnable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glUseProgram(gl.shader.prog);
}

void glnvg__resetFBOClipTextureCache (GLNVGcontext* gl) nothrow @trusted @nogc {
  version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): texture cache invalidated (%d)\n", gl.msp-1, gl.lastClipFBO); }
  /*
  if (gl.lastClipFBO >= 0) {
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);
  }
  */
  gl.lastClipFBO = -666;
}

void glnvg__setFBOClipTexture (GLNVGcontext* gl, GLNVGfragUniforms* frag) nothrow @trusted @nogc {
  //assert(gl.msp > 0 && gl.msp <= gl.maskStack.length);
  if (gl.lastClipFBO != -666) {
    // cached
    version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): cached (%d)\n", gl.msp-1, gl.lastClipFBO); }
    frag.doclip = (gl.lastClipFBO >= 0 ? 1 : 0);
    return;
  }

  // no cache
  int fboidx = -1;
  mainloop: foreach_reverse (immutable sp, GLMaskState mst; gl.maskStack.ptr[0..gl.msp]/*; reverse*/) {
    final switch (mst) {
      case GLMaskState.DontMask: fboidx = -1; break mainloop;
      case GLMaskState.Uninitialized: break;
      case GLMaskState.Initialized: fboidx = cast(int)sp; break mainloop;
      case GLMaskState.JustCleared: assert(0, "NanoVega: `glnvg__setFBOClipTexture()` internal error");
    }
  }

  if (fboidx < 0) {
    // don't mask
    gl.lastClipFBO = -1;
    frag.doclip = 0;
  } else {
    // do masking
    assert(gl.fbo.ptr[fboidx] != 0);
    gl.lastClipFBO = fboidx;
    frag.doclip = 1;
  }

  version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): new cache (new:%d)\n", gl.msp-1, gl.lastClipFBO); }

  if (gl.lastClipFBO >= 0) {
    assert(gl.fboTex.ptr[gl.lastClipFBO].ptr[0]);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, gl.fboTex.ptr[gl.lastClipFBO].ptr[0]);
    glActiveTexture(GL_TEXTURE0);
  }
}

// returns index in `gl.fbo`, or -1 for "don't mask"
int glnvg__generateFBOClipTexture (GLNVGcontext* gl) nothrow @trusted @nogc {
  assert(gl.msp > 0 && gl.msp <= gl.maskStack.length);
  // reset cache
  //glnvg__resetFBOClipTextureCache(gl);
  // we need initialized FBO, even for "don't mask" case
  // for this, look back in stack, and either copy initialized FBO,
  // or stop at first uninitialized one, and clear it
  if (gl.maskStack.ptr[gl.msp-1] == GLMaskState.Initialized) {
    // shortcut
    version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): generation of new texture is skipped (already initialized)\n", gl.msp-1); }
    glBindFramebuffer(GL_FRAMEBUFFER, gl.fbo.ptr[gl.msp-1]);
    return gl.msp-1;
  }
  foreach_reverse (immutable sp; 0..gl.msp/*; reverse*/) {
    final switch (gl.maskStack.ptr[sp]) {
      case GLMaskState.DontMask:
        // clear it
        version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): generating new clean texture\n", gl.msp-1); }
        if (!glnvg__allocFBO(gl, gl.msp-1)) glnvg__clearFBO(gl, gl.msp-1);
        gl.maskStack.ptr[gl.msp-1] = GLMaskState.JustCleared;
        return gl.msp-1;
      case GLMaskState.Uninitialized: break; // do nothing
      case GLMaskState.Initialized:
        // i found her! copy to TOS
        version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): copying texture from %d\n", gl.msp-1, cast(int)sp); }
        glnvg__allocFBO(gl, gl.msp-1, false);
        glnvg__copyFBOToFrom(gl, gl.msp-1, sp);
        gl.maskStack.ptr[gl.msp-1] = GLMaskState.Initialized;
        return gl.msp-1;
      case GLMaskState.JustCleared: assert(0, "NanoVega: `glnvg__generateFBOClipTexture()` internal error");
    }
  }
  // nothing was initialized, lol
  version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): generating new clean texture (first one)\n", gl.msp-1); }
  if (!glnvg__allocFBO(gl, gl.msp-1)) glnvg__clearFBO(gl, gl.msp-1);
  gl.maskStack.ptr[gl.msp-1] = GLMaskState.JustCleared;
  return gl.msp-1;
}

void glnvg__renderPushClip (void* uptr) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGcall* call = glnvg__allocCall(gl);
  if (call is null) return;
  call.type = GLNVG_PUSHCLIP;
}

void glnvg__renderPopClip (void* uptr) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGcall* call = glnvg__allocCall(gl);
  if (call is null) return;
  call.type = GLNVG_POPCLIP;
}

void glnvg__renderResetClip (void* uptr) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGcall* call = glnvg__allocCall(gl);
  if (call is null) return;
  call.type = GLNVG_RESETCLIP;
}

void glnvg__clipDebugDump (void* uptr, bool doit) nothrow @trusted @nogc {
  version(nanovega_debug_clipping) {
    GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
    GLNVGcall* call = glnvg__allocCall(gl);
    call.type = (doit ? GLNVG_CLIP_DDUMP_ON : GLNVG_CLIP_DDUMP_OFF);
  }
}

bool glnvg__renderCreate (void* uptr) nothrow @trusted @nogc {
  import core.stdc.stdio : snprintf;

  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  enum align_ = 4;

  char[64] shaderHeader = void;
  //enum shaderHeader = "#define UNIFORM_ARRAY_SIZE 12\n";
  snprintf(shaderHeader.ptr, shaderHeader.length, "#define UNIFORM_ARRAY_SIZE %u\n", cast(uint)GLNVGfragUniforms.UNIFORM_ARRAY_SIZE);

  enum fillVertShader = q{
    uniform vec2 viewSize;
    attribute vec2 vertex;
    attribute vec2 tcoord;
    varying vec2 ftcoord;
    varying vec2 fpos;
    uniform vec4 tmat; /* abcd of affine matrix: xyzw */
    uniform vec2 ttr; /* tx and ty of affine matrix */
    void main (void) {
      /* affine transformation */
      float nx = vertex.x*tmat.x+vertex.y*tmat.z+ttr.x;
      float ny = vertex.x*tmat.y+vertex.y*tmat.w+ttr.y;
      ftcoord = tcoord;
      fpos = vec2(nx, ny);
      gl_Position = vec4(2.0*nx/viewSize.x-1.0, 1.0-2.0*ny/viewSize.y, 0, 1);
    }
  };

  enum fillFragShader = q{
    uniform vec4 frag[UNIFORM_ARRAY_SIZE];
    uniform sampler2D tex;
    uniform sampler2D clipTex;
    uniform vec2 viewSize;
    varying vec2 ftcoord;
    varying vec2 fpos;
    #define scissorMat mat3(frag[0].xyz, frag[1].xyz, frag[2].xyz)
    #define paintMat mat3(frag[3].xyz, frag[4].xyz, frag[5].xyz)
    #define innerCol frag[6]
    #define middleCol frag[7]
    #define outerCol frag[7+1]
    #define scissorExt frag[8+1].xy
    #define scissorScale frag[8+1].zw
    #define extent frag[9+1].xy
    #define radius frag[9+1].z
    #define feather frag[9+1].w
    #define strokeMult frag[10+1].x
    #define strokeThr frag[10+1].y
    #define texType int(frag[10+1].z)
    #define type int(frag[10+1].w)
    #define doclip int(frag[11+1].x)
    #define midp frag[11+1].y

    float sdroundrect (in vec2 pt, in vec2 ext, in float rad) {
      vec2 ext2 = ext-vec2(rad, rad);
      vec2 d = abs(pt)-ext2;
      return min(max(d.x, d.y), 0.0)+length(max(d, 0.0))-rad;
    }

    // Scissoring
    float scissorMask (in vec2 p) {
      vec2 sc = (abs((scissorMat*vec3(p, 1.0)).xy)-scissorExt);
      sc = vec2(0.5, 0.5)-sc*scissorScale;
      return clamp(sc.x, 0.0, 1.0)*clamp(sc.y, 0.0, 1.0);
    }

    #ifdef EDGE_AA
    // Stroke - from [0..1] to clipped pyramid, where the slope is 1px.
    float strokeMask () {
      return min(1.0, (1.0-abs(ftcoord.x*2.0-1.0))*strokeMult)*min(1.0, ftcoord.y);
    }
    #endif

    void main (void) {
      // clipping
      if (doclip != 0) {
        /*vec4 clr = texelFetch(clipTex, ivec2(int(gl_FragCoord.x), int(gl_FragCoord.y)), 0);*/
        vec4 clr = texture2D(clipTex, vec2(gl_FragCoord.x/viewSize.x, gl_FragCoord.y/viewSize.y));
        if (clr.r == 0.0) discard;
      }
      float scissor = scissorMask(fpos);
      if (scissor <= 0.0) discard; //k8: is it really faster?
      #ifdef EDGE_AA
      float strokeAlpha = strokeMask();
      if (strokeAlpha < strokeThr) discard;
      #else
      float strokeAlpha = 1.0;
      #endif
      // rendering
      vec4 color;
      if (type == 0) { /* NSVG_SHADER_FILLCOLOR */
        color = innerCol;
        // Combine alpha
        color *= strokeAlpha*scissor;
      } else if (type == 1) { /* NSVG_SHADER_FILLGRAD */
        // Gradient
        // Calculate gradient color using box gradient
        vec2 pt = (paintMat*vec3(fpos, 1.0)).xy;
        float d = clamp((sdroundrect(pt, extent, radius)+feather*0.5)/feather, 0.0, 1.0);
        if (midp <= 0) {
          color = mix(innerCol, outerCol, d);
        } else {
          midp = min(midp, 1.0);
          if (d < midp) {
            color = mix(innerCol, middleCol, d/midp);
          } else {
            color = mix(middleCol, outerCol, (d-midp)/midp);
          }
        }
        // Combine alpha
        color *= strokeAlpha*scissor;
      } else if (type == 2) { /* NSVG_SHADER_FILLIMG */
        // Image
        // Calculate color from texture
        vec2 pt = (paintMat*vec3(fpos, 1.0)).xy/extent;
        color = texture2D(tex, pt);
        if (texType == 1) color = vec4(color.xyz*color.w, color.w);
        if (texType == 2) color = vec4(color.x);
        // Apply color tint and alpha
        color *= innerCol;
        // Combine alpha
        color *= strokeAlpha*scissor;
      } else if (type == 3) { /* NSVG_SHADER_SIMPLE */
        // Stencil fill
        color = vec4(1, 1, 1, 1);
      } else if (type == 4) { /* NSVG_SHADER_IMG */
        // Textured tris
        color = texture2D(tex, ftcoord);
        if (texType == 1) color = vec4(color.xyz*color.w, color.w);
        if (texType == 2) color = vec4(color.x);
        color *= scissor;
        color *= innerCol; // Apply color tint
      }
      gl_FragColor = color;
    }
  };

  enum clipVertShaderFill = q{
    uniform vec2 viewSize;
    attribute vec2 vertex;
    uniform vec4 tmat; /* abcd of affine matrix: xyzw */
    uniform vec2 ttr; /* tx and ty of affine matrix */
    void main (void) {
      /* affine transformation */
      float nx = vertex.x*tmat.x+vertex.y*tmat.z+ttr.x;
      float ny = vertex.x*tmat.y+vertex.y*tmat.w+ttr.y;
      gl_Position = vec4(2.0*nx/viewSize.x-1.0, 1.0-2.0*ny/viewSize.y, 0, 1);
    }
  };

  enum clipFragShaderFill = q{
    uniform vec2 viewSize;
    void main (void) {
      gl_FragColor = vec4(1, 1, 1, 1);
    }
  };

  enum clipVertShaderCopy = q{
    uniform vec2 viewSize;
    attribute vec2 vertex;
    void main (void) {
      gl_Position = vec4(2.0*vertex.x/viewSize.x-1.0, 1.0-2.0*vertex.y/viewSize.y, 0, 1);
    }
  };

  enum clipFragShaderCopy = q{
    uniform sampler2D tex;
    uniform vec2 viewSize;
    void main (void) {
      //gl_FragColor = texelFetch(tex, ivec2(int(gl_FragCoord.x), int(gl_FragCoord.y)), 0);
      gl_FragColor = texture2D(tex, vec2(gl_FragCoord.x/viewSize.x, gl_FragCoord.y/viewSize.y));
    }
  };

  glnvg__checkError(gl, "init");

  string defines = (gl.flags&NVGContextFlag.Antialias ? "#define EDGE_AA 1\n" : null);
  if (!glnvg__createShader(&gl.shader, "shader", shaderHeader.ptr, defines.ptr, fillVertShader, fillFragShader)) return false;
  if (!glnvg__createShader(&gl.shaderFillFBO, "shaderFillFBO", shaderHeader.ptr, defines.ptr, clipVertShaderFill, clipFragShaderFill)) return false;
  if (!glnvg__createShader(&gl.shaderCopyFBO, "shaderCopyFBO", shaderHeader.ptr, defines.ptr, clipVertShaderCopy, clipFragShaderCopy)) return false;

  glnvg__checkError(gl, "uniform locations");
  glnvg__getUniforms(&gl.shader);
  glnvg__getUniforms(&gl.shaderFillFBO);
  glnvg__getUniforms(&gl.shaderCopyFBO);

  // Create dynamic vertex array
  glGenBuffers(1, &gl.vertBuf);

  gl.fragSize = GLNVGfragUniforms.sizeof+align_-GLNVGfragUniforms.sizeof%align_;

  glnvg__checkError(gl, "create done");

  glFinish();

  return true;
}

int glnvg__renderCreateTexture (void* uptr, NVGtexture type, int w, int h, int imageFlags, const(ubyte)* data) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGtexture* tex = glnvg__allocTexture(gl);

  if (tex is null) return 0;

  glGenTextures(1, &tex.tex);
  tex.width = w;
  tex.height = h;
  tex.type = type;
  tex.flags = imageFlags;
  glnvg__bindTexture(gl, tex.tex);

  version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("created texture with id %d; glid=%u\n", tex.id, tex.tex); }}

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, tex.width);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);

  // GL 1.4 and later has support for generating mipmaps using a tex parameter.
  if ((imageFlags&(NVGImageFlag.GenerateMipmaps|NVGImageFlag.NoFiltering)) == NVGImageFlag.GenerateMipmaps) glTexParameteri(GL_TEXTURE_2D, GL_GENERATE_MIPMAP, GL_TRUE);

  immutable ttype = (type == NVGtexture.RGBA ? GL_RGBA : GL_RED);
  glTexImage2D(GL_TEXTURE_2D, 0, ttype, w, h, 0, ttype, GL_UNSIGNED_BYTE, data);

  immutable tfmin =
    (imageFlags&NVGImageFlag.NoFiltering ? GL_NEAREST :
     imageFlags&NVGImageFlag.GenerateMipmaps ? GL_LINEAR_MIPMAP_LINEAR :
     GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, tfmin);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, (imageFlags&NVGImageFlag.NoFiltering ? GL_NEAREST : GL_LINEAR));

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (imageFlags&NVGImageFlag.RepeatX ? GL_REPEAT : GL_CLAMP_TO_EDGE));
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (imageFlags&NVGImageFlag.RepeatY ? GL_REPEAT : GL_CLAMP_TO_EDGE));

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);

  glnvg__checkError(gl, "create tex");
  glnvg__bindTexture(gl, 0);

  return tex.id;
}

bool glnvg__renderDeleteTexture (void* uptr, int image) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  return glnvg__deleteTexture(gl, image);
}

bool glnvg__renderTextureIncRef (void* uptr, int image) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGtexture* tex = glnvg__findTexture(gl, image);
  if (tex is null) {
    version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("CANNOT incref texture with id %d\n", image); }}
    return false;
  }
  ++tex.rc;
  version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("texture #%d: incref; newref=%d\n", image, tex.rc); }}
  return true;
}

bool glnvg__renderUpdateTexture (void* uptr, int image, int x, int y, int w, int h, const(ubyte)* data) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGtexture* tex = glnvg__findTexture(gl, image);

  if (tex is null) {
    version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("CANNOT update texture with id %d\n", image); }}
    return false;
  }

  version(nanovega_debug_textures) {{ import core.stdc.stdio; printf("updated texture with id %d; glid=%u\n", tex.id, image, tex.tex); }}

  glnvg__bindTexture(gl, tex.tex);

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, tex.width);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, x);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, y);

  immutable ttype = (tex.type == NVGtexture.RGBA ? GL_RGBA : GL_RED);
  glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, ttype, GL_UNSIGNED_BYTE, data);

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);

  glnvg__bindTexture(gl, 0);

  return true;
}

bool glnvg__renderGetTextureSize (void* uptr, int image, int* w, int* h) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGtexture* tex = glnvg__findTexture(gl, image);
  if (tex is null) {
    if (w !is null) *w = 0;
    if (h !is null) *h = 0;
    return false;
  } else {
    if (w !is null) *w = tex.width;
    if (h !is null) *h = tex.height;
    return true;
  }
}

void glnvg__xformToMat3x4 (float[] m3, const(float)[] t) nothrow @trusted @nogc {
  assert(t.length >= 6);
  assert(m3.length >= 12);
  m3.ptr[0] = t.ptr[0];
  m3.ptr[1] = t.ptr[1];
  m3.ptr[2] = 0.0f;
  m3.ptr[3] = 0.0f;
  m3.ptr[4] = t.ptr[2];
  m3.ptr[5] = t.ptr[3];
  m3.ptr[6] = 0.0f;
  m3.ptr[7] = 0.0f;
  m3.ptr[8] = t.ptr[4];
  m3.ptr[9] = t.ptr[5];
  m3.ptr[10] = 1.0f;
  m3.ptr[11] = 0.0f;
}

NVGColor glnvg__premulColor() (in auto ref NVGColor c) nothrow @trusted @nogc {
  //pragma(inline, true);
  NVGColor res = void;
  res.r = c.r*c.a;
  res.g = c.g*c.a;
  res.b = c.b*c.a;
  res.a = c.a;
  return res;
}

bool glnvg__convertPaint (GLNVGcontext* gl, GLNVGfragUniforms* frag, NVGPaint* paint, NVGscissor* scissor, float width, float fringe, float strokeThr) nothrow @trusted @nogc {
  import core.stdc.math : sqrtf;
  GLNVGtexture* tex = null;
  NVGMatrix invxform = void;

  memset(frag, 0, (*frag).sizeof);

  frag.innerCol = glnvg__premulColor(paint.innerColor);
  frag.middleCol = glnvg__premulColor(paint.middleColor);
  frag.outerCol = glnvg__premulColor(paint.outerColor);
  frag.midp = paint.midp;

  if (scissor.extent.ptr[0] < -0.5f || scissor.extent.ptr[1] < -0.5f) {
    memset(frag.scissorMat.ptr, 0, frag.scissorMat.sizeof);
    frag.scissorExt.ptr[0] = 1.0f;
    frag.scissorExt.ptr[1] = 1.0f;
    frag.scissorScale.ptr[0] = 1.0f;
    frag.scissorScale.ptr[1] = 1.0f;
  } else {
    //nvgTransformInverse(invxform[], scissor.xform[]);
    invxform = scissor.xform.inverted;
    glnvg__xformToMat3x4(frag.scissorMat[], invxform.mat[]);
    frag.scissorExt.ptr[0] = scissor.extent.ptr[0];
    frag.scissorExt.ptr[1] = scissor.extent.ptr[1];
    frag.scissorScale.ptr[0] = sqrtf(scissor.xform.mat.ptr[0]*scissor.xform.mat.ptr[0]+scissor.xform.mat.ptr[2]*scissor.xform.mat.ptr[2])/fringe;
    frag.scissorScale.ptr[1] = sqrtf(scissor.xform.mat.ptr[1]*scissor.xform.mat.ptr[1]+scissor.xform.mat.ptr[3]*scissor.xform.mat.ptr[3])/fringe;
  }

  memcpy(frag.extent.ptr, paint.extent.ptr, frag.extent.sizeof);
  frag.strokeMult = (width*0.5f+fringe*0.5f)/fringe;
  frag.strokeThr = strokeThr;

  if (paint.image.valid) {
    tex = glnvg__findTexture(gl, paint.image.id);
    if (tex is null) return false;
    if ((tex.flags&NVGImageFlag.FlipY) != 0) {
      /*
      NVGMatrix flipped;
      nvgTransformScale(flipped[], 1.0f, -1.0f);
      nvgTransformMultiply(flipped[], paint.xform[]);
      nvgTransformInverse(invxform[], flipped[]);
      */
      /*
      NVGMatrix m1 = void, m2 = void;
      nvgTransformTranslate(m1[], 0.0f, frag.extent.ptr[1]*0.5f);
      nvgTransformMultiply(m1[], paint.xform[]);
      nvgTransformScale(m2[], 1.0f, -1.0f);
      nvgTransformMultiply(m2[], m1[]);
      nvgTransformTranslate(m1[], 0.0f, -frag.extent.ptr[1]*0.5f);
      nvgTransformMultiply(m1[], m2[]);
      nvgTransformInverse(invxform[], m1[]);
      */
      NVGMatrix m1 = NVGMatrix.Translated(0.0f, frag.extent.ptr[1]*0.5f);
      m1.mul(paint.xform);
      NVGMatrix m2 = NVGMatrix.Scaled(1.0f, -1.0f);
      m2.mul(m1);
      m1 = NVGMatrix.Translated(0.0f, -frag.extent.ptr[1]*0.5f);
      m1.mul(m2);
      invxform = m1.inverted;
    } else {
      //nvgTransformInverse(invxform[], paint.xform[]);
      invxform = paint.xform.inverted;
    }
    frag.type = NSVG_SHADER_FILLIMG;

    if (tex.type == NVGtexture.RGBA) {
      frag.texType = (tex.flags&NVGImageFlag.Premultiplied ? 0 : 1);
    } else {
      frag.texType = 2;
    }
    //printf("frag.texType = %d\n", frag.texType);
  } else {
    frag.type = (paint.simpleColor ? NSVG_SHADER_FILLCOLOR : NSVG_SHADER_FILLGRAD);
    frag.radius = paint.radius;
    frag.feather = paint.feather;
    //nvgTransformInverse(invxform[], paint.xform[]);
    invxform = paint.xform.inverted;
  }

  glnvg__xformToMat3x4(frag.paintMat[], invxform.mat[]);

  return true;
}

void glnvg__setUniforms (GLNVGcontext* gl, int uniformOffset, int image) nothrow @trusted @nogc {
  GLNVGfragUniforms* frag = nvg__fragUniformPtr(gl, uniformOffset);
  glnvg__setFBOClipTexture(gl, frag);
  glUniform4fv(gl.shader.loc[GLNVGuniformLoc.Frag], frag.UNIFORM_ARRAY_SIZE, &(frag.uniformArray.ptr[0].ptr[0]));
  glnvg__checkError(gl, "glnvg__setUniforms");
  if (image != 0) {
    GLNVGtexture* tex = glnvg__findTexture(gl, image);
    glnvg__bindTexture(gl, (tex !is null ? tex.tex : 0));
    glnvg__checkError(gl, "tex paint tex");
  } else {
    glnvg__bindTexture(gl, 0);
  }
}

void glnvg__finishClip (GLNVGcontext* gl, NVGClipMode clipmode) nothrow @trusted @nogc {
  assert(clipmode != NVGClipMode.None);

  // fill FBO, clear stencil buffer
  //TODO: optimize with bounds?
  version(all) {
    //glnvg__resetAffine(gl);
    //glUseProgram(gl.shaderFillFBO.prog);
    glDisable(GL_CULL_FACE);
    glDisable(GL_BLEND);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glEnable(GL_STENCIL_TEST);
    if (gl.doClipUnion) {
      // for "and" we should clear everything that is NOT stencil-masked
      glnvg__stencilFunc(gl, GL_EQUAL, 0x00, 0xff);
      glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
    } else {
      glnvg__stencilFunc(gl, GL_NOTEQUAL, 0x00, 0xff);
      glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
    }
    glBegin(GL_QUADS);
      glVertex2i(0, 0);
      glVertex2i(0, gl.fboHeight);
      glVertex2i(gl.fboWidth, gl.fboHeight);
      glVertex2i(gl.fboWidth, 0);
    glEnd();
    //glnvg__restoreAffine(gl);
  }

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glDisable(GL_COLOR_LOGIC_OP);
  //glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE); // done above
  glEnable(GL_BLEND);
  glDisable(GL_STENCIL_TEST);
  glEnable(GL_CULL_FACE);
  glUseProgram(gl.shader.prog);

  // set current FBO as used one
  assert(gl.msp > 0 && gl.fbo.ptr[gl.msp-1] > 0 && gl.fboTex.ptr[gl.msp-1].ptr[0] > 0);
  if (gl.lastClipFBO != gl.msp-1) {
    version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): new cache from changed mask (old:%d; new:%d)\n", gl.msp-1, gl.lastClipFBO, gl.msp-1); }
    gl.lastClipFBO = gl.msp-1;
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, gl.fboTex.ptr[gl.lastClipFBO].ptr[0]);
    glActiveTexture(GL_TEXTURE0);
  }
}

void glnvg__setClipUniforms (GLNVGcontext* gl, int uniformOffset, NVGClipMode clipmode) nothrow @trusted @nogc {
  assert(clipmode != NVGClipMode.None);
  GLNVGfragUniforms* frag = nvg__fragUniformPtr(gl, uniformOffset);
  // save uniform offset for `glnvg__finishClip()`
  gl.lastClipUniOfs = uniformOffset;
  // get FBO index, bind this FBO
  immutable int clipTexId = glnvg__generateFBOClipTexture(gl);
  assert(clipTexId >= 0);
  glUseProgram(gl.shaderFillFBO.prog);
  glnvg__checkError(gl, "use");
  glBindFramebuffer(GL_FRAMEBUFFER, gl.fbo.ptr[clipTexId]);
  // set logic op for clip
  gl.doClipUnion = false;
  if (gl.maskStack.ptr[gl.msp-1] == GLMaskState.JustCleared) {
    // it is cleared to zero, we can just draw a path
    glDisable(GL_COLOR_LOGIC_OP);
    gl.maskStack.ptr[gl.msp-1] = GLMaskState.Initialized;
  } else {
    glEnable(GL_COLOR_LOGIC_OP);
    final switch (clipmode) {
      case NVGClipMode.None: assert(0, "wtf?!");
      case NVGClipMode.Union: glLogicOp(GL_CLEAR); gl.doClipUnion = true; break; // use `GL_CLEAR` to avoid adding another shader mode
      case NVGClipMode.Or: glLogicOp(GL_COPY); break; // GL_OR
      case NVGClipMode.Xor: glLogicOp(GL_XOR); break;
      case NVGClipMode.Sub: glLogicOp(GL_CLEAR); break;
      case NVGClipMode.Replace: glLogicOp(GL_COPY); break;
    }
  }
  // set affine matrix
  glUniform4fv(gl.shaderFillFBO.loc[GLNVGuniformLoc.TMat], 1, gl.lastAffine.mat.ptr);
  glnvg__checkError(gl, "affine 0");
  glUniform2fv(gl.shaderFillFBO.loc[GLNVGuniformLoc.TTr], 1, gl.lastAffine.mat.ptr+4);
  glnvg__checkError(gl, "affine 1");
  // setup common OpenGL parameters
  glDisable(GL_BLEND);
  glDisable(GL_CULL_FACE);
  glEnable(GL_STENCIL_TEST);
  glnvg__stencilMask(gl, 0xff);
  glnvg__stencilFunc(gl, GL_EQUAL, 0x00, 0xff);
  glStencilOp(GL_KEEP, GL_KEEP, GL_INCR);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
}

void glnvg__renderViewport (void* uptr, int width, int height) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  gl.view.ptr[0] = cast(float)width;
  gl.view.ptr[1] = cast(float)height;
  // kill FBOs if we need to create new ones (flushing will recreate 'em if necessary)
  if (width != gl.fboWidth || height != gl.fboHeight) {
    glnvg__killFBOs(gl);
    gl.fboWidth = width;
    gl.fboHeight = height;
  }
  gl.msp = 1;
  gl.maskStack.ptr[0] = GLMaskState.DontMask;
}

void glnvg__fill (GLNVGcontext* gl, GLNVGcall* call) nothrow @trusted @nogc {
  GLNVGpath* paths = &gl.paths[call.pathOffset];
  int npaths = call.pathCount;

  if (call.clipmode == NVGClipMode.None) {
    // Draw shapes
    glEnable(GL_STENCIL_TEST);
    glnvg__stencilMask(gl, 0xffU);
    glnvg__stencilFunc(gl, GL_ALWAYS, 0, 0xffU);

    glnvg__setUniforms(gl, call.uniformOffset, 0);
    glnvg__checkError(gl, "fill simple");

    glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
    if (call.evenOdd) {
      //glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INVERT);
      //glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_INVERT);
      glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
    } else {
      glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INCR_WRAP);
      glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_DECR_WRAP);
    }
    glDisable(GL_CULL_FACE);
    foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_FAN, paths[i].fillOffset, paths[i].fillCount);
    glEnable(GL_CULL_FACE);

    // Draw anti-aliased pixels
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glnvg__setUniforms(gl, call.uniformOffset+gl.fragSize, call.image);
    glnvg__checkError(gl, "fill fill");

    if (gl.flags&NVGContextFlag.Antialias) {
      glnvg__stencilFunc(gl, GL_EQUAL, 0x00, 0xffU);
      glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
      // Draw fringes
      foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);
    }

    // Draw fill
    glnvg__stencilFunc(gl, GL_NOTEQUAL, 0x0, 0xffU);
    glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
    if (call.evenOdd) {
      glDisable(GL_CULL_FACE);
      glDrawArrays(GL_TRIANGLE_STRIP, call.triangleOffset, call.triangleCount);
      //foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_FAN, paths[i].fillOffset, paths[i].fillCount);
      glEnable(GL_CULL_FACE);
    } else {
      glDrawArrays(GL_TRIANGLE_STRIP, call.triangleOffset, call.triangleCount);
    }

    glDisable(GL_STENCIL_TEST);
  } else {
    glnvg__setClipUniforms(gl, call.uniformOffset/*+gl.fragSize*/, call.clipmode); // this activates our FBO
    glnvg__checkError(gl, "fillclip simple");
    glnvg__stencilFunc(gl, GL_ALWAYS, 0x00, 0xffU);
    if (call.evenOdd) {
      //glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INVERT);
      //glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_INVERT);
      glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
    } else {
      glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INCR_WRAP);
      glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_DECR_WRAP);
    }
    foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_FAN, paths[i].fillOffset, paths[i].fillCount);
    glnvg__finishClip(gl, call.clipmode); // deactivate FBO, restore rendering state
  }
}

void glnvg__convexFill (GLNVGcontext* gl, GLNVGcall* call) nothrow @trusted @nogc {
  GLNVGpath* paths = &gl.paths[call.pathOffset];
  int npaths = call.pathCount;

  if (call.clipmode == NVGClipMode.None) {
    glnvg__setUniforms(gl, call.uniformOffset, call.image);
    glnvg__checkError(gl, "convex fill");
    if (call.evenOdd) glDisable(GL_CULL_FACE);
    foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_FAN, paths[i].fillOffset, paths[i].fillCount);
    if (gl.flags&NVGContextFlag.Antialias) {
      // Draw fringes
      foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);
    }
    if (call.evenOdd) glEnable(GL_CULL_FACE);
  } else {
    glnvg__setClipUniforms(gl, call.uniformOffset, call.clipmode); // this activates our FBO
    glnvg__checkError(gl, "clip convex fill");
    foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_FAN, paths[i].fillOffset, paths[i].fillCount);
    if (gl.flags&NVGContextFlag.Antialias) {
      // Draw fringes
      foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);
    }
    glnvg__finishClip(gl, call.clipmode); // deactivate FBO, restore rendering state
  }
}

void glnvg__stroke (GLNVGcontext* gl, GLNVGcall* call) nothrow @trusted @nogc {
  GLNVGpath* paths = &gl.paths[call.pathOffset];
  int npaths = call.pathCount;

  if (call.clipmode == NVGClipMode.None) {
    if (gl.flags&NVGContextFlag.StencilStrokes) {
      glEnable(GL_STENCIL_TEST);
      glnvg__stencilMask(gl, 0xff);

      // Fill the stroke base without overlap
      glnvg__stencilFunc(gl, GL_EQUAL, 0x0, 0xff);
      glStencilOp(GL_KEEP, GL_KEEP, GL_INCR);
      glnvg__setUniforms(gl, call.uniformOffset+gl.fragSize, call.image);
      glnvg__checkError(gl, "stroke fill 0");
      foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);

      // Draw anti-aliased pixels.
      glnvg__setUniforms(gl, call.uniformOffset, call.image);
      glnvg__stencilFunc(gl, GL_EQUAL, 0x00, 0xff);
      glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
      foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);

      // Clear stencil buffer.
      glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
      glnvg__stencilFunc(gl, GL_ALWAYS, 0x0, 0xff);
      glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
      glnvg__checkError(gl, "stroke fill 1");
      foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);
      glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

      glDisable(GL_STENCIL_TEST);

      //glnvg__convertPaint(gl, nvg__fragUniformPtr(gl, call.uniformOffset+gl.fragSize), paint, scissor, strokeWidth, fringe, 1.0f-0.5f/255.0f);
    } else {
      glnvg__setUniforms(gl, call.uniformOffset, call.image);
      glnvg__checkError(gl, "stroke fill");
      // Draw Strokes
      foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);
    }
  } else {
    glnvg__setClipUniforms(gl, call.uniformOffset/*+gl.fragSize*/, call.clipmode);
    glnvg__checkError(gl, "stroke fill 0");
    foreach (int i; 0..npaths) glDrawArrays(GL_TRIANGLE_STRIP, paths[i].strokeOffset, paths[i].strokeCount);
    glnvg__finishClip(gl, call.clipmode); // deactivate FBO, restore rendering state
  }
}

void glnvg__triangles (GLNVGcontext* gl, GLNVGcall* call) nothrow @trusted @nogc {
  if (call.clipmode == NVGClipMode.None) {
    glnvg__setUniforms(gl, call.uniformOffset, call.image);
    glnvg__checkError(gl, "triangles fill");
    glDrawArrays(GL_TRIANGLES, call.triangleOffset, call.triangleCount);
  } else {
    //TODO(?): use texture as mask?
  }
}

void glnvg__affine (GLNVGcontext* gl, GLNVGcall* call) nothrow @trusted @nogc {
  glUniform4fv(gl.shader.loc[GLNVGuniformLoc.TMat], 1, call.affine.mat.ptr);
  glnvg__checkError(gl, "affine");
  glUniform2fv(gl.shader.loc[GLNVGuniformLoc.TTr], 1, call.affine.mat.ptr+4);
  glnvg__checkError(gl, "affine");
  //glnvg__setUniforms(gl, call.uniformOffset, call.image);
}

void glnvg__renderCancelInternal (GLNVGcontext* gl, bool clearTextures) nothrow @trusted @nogc {
  if (clearTextures) {
    foreach (ref GLNVGcall c; gl.calls[0..gl.ncalls]) if (c.image > 0) glnvg__deleteTexture(gl, c.image);
  }
  gl.nverts = 0;
  gl.npaths = 0;
  gl.ncalls = 0;
  gl.nuniforms = 0;
  gl.msp = 1;
  gl.maskStack.ptr[0] = GLMaskState.DontMask;
}

void glnvg__renderCancel (void* uptr) nothrow @trusted @nogc {
  glnvg__renderCancelInternal(cast(GLNVGcontext*)uptr, true);
}

GLenum glnvg_convertBlendFuncFactor (NVGBlendFactor factor) pure nothrow @trusted @nogc {
  if (factor == NVGBlendFactor.Zero) return GL_ZERO;
  if (factor == NVGBlendFactor.One) return GL_ONE;
  if (factor == NVGBlendFactor.SrcColor) return GL_SRC_COLOR;
  if (factor == NVGBlendFactor.OneMinusSrcColor) return GL_ONE_MINUS_SRC_COLOR;
  if (factor == NVGBlendFactor.DstColor) return GL_DST_COLOR;
  if (factor == NVGBlendFactor.OneMinusDstColor) return GL_ONE_MINUS_DST_COLOR;
  if (factor == NVGBlendFactor.SrcAlpha) return GL_SRC_ALPHA;
  if (factor == NVGBlendFactor.OneMinusSrcAlpha) return GL_ONE_MINUS_SRC_ALPHA;
  if (factor == NVGBlendFactor.DstAlpha) return GL_DST_ALPHA;
  if (factor == NVGBlendFactor.OneMinusDstAlpha) return GL_ONE_MINUS_DST_ALPHA;
  if (factor == NVGBlendFactor.SrcAlphaSaturate) return GL_SRC_ALPHA_SATURATE;
  return GL_INVALID_ENUM;
}

GLNVGblend glnvg__buildBlendFunc (NVGCompositeOperationState op) pure nothrow @trusted @nogc {
  GLNVGblend res;
  res.simple = op.simple;
  res.srcRGB = glnvg_convertBlendFuncFactor(op.srcRGB);
  res.dstRGB = glnvg_convertBlendFuncFactor(op.dstRGB);
  res.srcAlpha = glnvg_convertBlendFuncFactor(op.srcAlpha);
  res.dstAlpha = glnvg_convertBlendFuncFactor(op.dstAlpha);
  if (res.simple) {
    if (res.srcAlpha == GL_INVALID_ENUM || res.dstAlpha == GL_INVALID_ENUM) {
      res.srcRGB = res.srcAlpha = res.dstRGB = res.dstAlpha = GL_INVALID_ENUM;
    }
  } else {
    if (res.srcRGB == GL_INVALID_ENUM || res.dstRGB == GL_INVALID_ENUM || res.srcAlpha == GL_INVALID_ENUM || res.dstAlpha == GL_INVALID_ENUM) {
      res.simple = true;
      res.srcRGB = res.srcAlpha = res.dstRGB = res.dstAlpha = GL_INVALID_ENUM;
    }
  }
  return res;
}

void glnvg__blendCompositeOperation() (GLNVGcontext* gl, in auto ref GLNVGblend op) nothrow @trusted @nogc {
  //glBlendFuncSeparate(glnvg_convertBlendFuncFactor(op.srcRGB), glnvg_convertBlendFuncFactor(op.dstRGB), glnvg_convertBlendFuncFactor(op.srcAlpha), glnvg_convertBlendFuncFactor(op.dstAlpha));
  static if (NANOVG_GL_USE_STATE_FILTER) {
    if (gl.blendFunc.simple == op.simple) {
      if (op.simple) {
        if (gl.blendFunc.srcAlpha == op.srcAlpha && gl.blendFunc.dstAlpha == op.dstAlpha) return;
      } else {
        if (gl.blendFunc.srcRGB == op.srcRGB && gl.blendFunc.dstRGB == op.dstRGB && gl.blendFunc.srcAlpha == op.srcAlpha && gl.blendFunc.dstAlpha == op.dstAlpha) return;
      }
    }
    gl.blendFunc = op;
  }
  if (op.simple) {
    if (op.srcAlpha == GL_INVALID_ENUM || op.dstAlpha == GL_INVALID_ENUM) {
      glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    } else {
      glBlendFunc(op.srcAlpha, op.dstAlpha);
    }
  } else {
    if (op.srcRGB == GL_INVALID_ENUM || op.dstRGB == GL_INVALID_ENUM || op.srcAlpha == GL_INVALID_ENUM || op.dstAlpha == GL_INVALID_ENUM) {
      glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    } else {
      glBlendFuncSeparate(op.srcRGB, op.dstRGB, op.srcAlpha, op.dstAlpha);
    }
  }
}

void glnvg__renderSetAffine (void* uptr, in ref NVGMatrix mat) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGcall* call;
  // if last operation was GLNVG_AFFINE, simply replace the matrix
  if (gl.ncalls > 0 && gl.calls[gl.ncalls-1].type == GLNVG_AFFINE) {
    call = &gl.calls[gl.ncalls-1];
  } else {
    call = glnvg__allocCall(gl);
    if (call is null) return;
    call.type = GLNVG_AFFINE;
  }
  call.affine.mat.ptr[0..6] = mat.mat.ptr[0..6];
}

version(nanovega_debug_clipping) public __gshared bool nanovegaClipDebugDump = false;

void glnvg__renderFlush (void* uptr) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  enum ShaderType { None, Fill, Clip }
  auto lastShader = ShaderType.None;
  if (gl.ncalls > 0) {
    gl.msp = 1;
    gl.maskStack.ptr[0] = GLMaskState.DontMask;

    // Setup require GL state.
    glUseProgram(gl.shader.prog);

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);
    glnvg__resetFBOClipTextureCache(gl);

    //glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    static if (NANOVG_GL_USE_STATE_FILTER) {
      gl.blendFunc.simple = true;
      gl.blendFunc.srcRGB = gl.blendFunc.dstRGB = gl.blendFunc.srcAlpha = gl.blendFunc.dstAlpha = GL_INVALID_ENUM;
    }
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA); // just in case
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);
    glEnable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glStencilMask(0xffffffff);
    glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
    glStencilFunc(GL_ALWAYS, 0, 0xffffffff);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, 0);
    static if (NANOVG_GL_USE_STATE_FILTER) {
      gl.boundTexture = 0;
      gl.stencilMask = 0xffffffff;
      gl.stencilFunc = GL_ALWAYS;
      gl.stencilFuncRef = 0;
      gl.stencilFuncMask = 0xffffffff;
    }
    glnvg__checkError(gl, "OpenGL setup");

    // Upload vertex data
    glBindBuffer(GL_ARRAY_BUFFER, gl.vertBuf);
    glBufferData(GL_ARRAY_BUFFER, gl.nverts*NVGvertex.sizeof, gl.verts, GL_STREAM_DRAW);
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, NVGvertex.sizeof, cast(const(GLvoid)*)cast(usize)0);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, NVGvertex.sizeof, cast(const(GLvoid)*)(0+2*float.sizeof));
    glnvg__checkError(gl, "vertex data uploading");

    // Set view and texture just once per frame.
    glUniform1i(gl.shader.loc[GLNVGuniformLoc.Tex], 0);
    if (gl.shader.loc[GLNVGuniformLoc.ClipTex] != -1) {
      //{ import core.stdc.stdio; printf("%d\n", gl.shader.loc[GLNVGuniformLoc.ClipTex]); }
      glUniform1i(gl.shader.loc[GLNVGuniformLoc.ClipTex], 1);
    }
    if (gl.shader.loc[GLNVGuniformLoc.ViewSize] != -1) glUniform2fv(gl.shader.loc[GLNVGuniformLoc.ViewSize], 1, gl.view.ptr);
    glnvg__checkError(gl, "render shader setup");

    // Reset affine transformations.
    glUniform4fv(gl.shader.loc[GLNVGuniformLoc.TMat], 1, NVGMatrix.IdentityMat.ptr);
    glUniform2fv(gl.shader.loc[GLNVGuniformLoc.TTr], 1, NVGMatrix.IdentityMat.ptr+4);
    glnvg__checkError(gl, "affine setup");

    // set clip shaders params
    // fill
    glUseProgram(gl.shaderFillFBO.prog);
    glnvg__checkError(gl, "clip shaders setup (fill 0)");
    if (gl.shaderFillFBO.loc[GLNVGuniformLoc.ViewSize] != -1) glUniform2fv(gl.shaderFillFBO.loc[GLNVGuniformLoc.ViewSize], 1, gl.view.ptr);
    glnvg__checkError(gl, "clip shaders setup (fill 1)");
    // copy
    glUseProgram(gl.shaderCopyFBO.prog);
    glnvg__checkError(gl, "clip shaders setup (copy 0)");
    if (gl.shaderCopyFBO.loc[GLNVGuniformLoc.ViewSize] != -1) glUniform2fv(gl.shaderCopyFBO.loc[GLNVGuniformLoc.ViewSize], 1, gl.view.ptr);
    glnvg__checkError(gl, "clip shaders setup (copy 1)");
    //glUniform1i(gl.shaderFillFBO.loc[GLNVGuniformLoc.Tex], 0);
    glUniform1i(gl.shaderCopyFBO.loc[GLNVGuniformLoc.Tex], 0);
    glnvg__checkError(gl, "clip shaders setup (copy 2)");
    // restore render shader
    glUseProgram(gl.shader.prog);

    //{ import core.stdc.stdio; printf("ViewSize=%u %u %u\n", gl.shader.loc[GLNVGuniformLoc.ViewSize], gl.shaderFillFBO.loc[GLNVGuniformLoc.ViewSize], gl.shaderCopyFBO.loc[GLNVGuniformLoc.ViewSize]); }

    gl.lastAffine.identity;

    foreach (int i; 0..gl.ncalls) {
      GLNVGcall* call = &gl.calls[i];
      switch (call.type) {
        case GLNVG_FILL: glnvg__blendCompositeOperation(gl, call.blendFunc); glnvg__fill(gl, call); break;
        case GLNVG_CONVEXFILL: glnvg__blendCompositeOperation(gl, call.blendFunc); glnvg__convexFill(gl, call); break;
        case GLNVG_STROKE: glnvg__blendCompositeOperation(gl, call.blendFunc); glnvg__stroke(gl, call); break;
        case GLNVG_TRIANGLES: glnvg__blendCompositeOperation(gl, call.blendFunc); glnvg__triangles(gl, call); break;
        case GLNVG_AFFINE: gl.lastAffine = call.affine; glnvg__affine(gl, call); break;
        // clip region management
        case GLNVG_PUSHCLIP:
          version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): push clip (cache:%d); current state is %d\n", gl.msp-1, gl.lastClipFBO, gl.maskStack.ptr[gl.msp-1]); }
          if (gl.msp >= gl.maskStack.length) assert(0, "NanoVega: mask stack overflow in OpenGL backend");
          if (gl.maskStack.ptr[gl.msp-1] == GLMaskState.DontMask) {
            gl.maskStack.ptr[gl.msp++] = GLMaskState.DontMask;
          } else {
            gl.maskStack.ptr[gl.msp++] = GLMaskState.Uninitialized;
          }
          // no need to reset FBO cache here, as nothing was changed
          break;
        case GLNVG_POPCLIP:
          if (gl.msp <= 1) assert(0, "NanoVega: mask stack underflow in OpenGL backend");
          version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): pop clip (cache:%d); current state is %d; previous state is %d\n", gl.msp-1, gl.lastClipFBO, gl.maskStack.ptr[gl.msp-1], gl.maskStack.ptr[gl.msp-2]); }
          --gl.msp;
          assert(gl.msp > 0);
          //{ import core.stdc.stdio; printf("popped; new msp is %d; state is %d\n", gl.msp, gl.maskStack.ptr[gl.msp]); }
          // check popped item
          final switch (gl.maskStack.ptr[gl.msp]) {
            case GLMaskState.DontMask:
              // if last FBO was "don't mask", reset cache if current is not "don't mask"
              if (gl.maskStack.ptr[gl.msp-1] != GLMaskState.DontMask) {
                version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("  +++ need to reset FBO cache\n"); }
                glnvg__resetFBOClipTextureCache(gl);
              }
              break;
            case GLMaskState.Uninitialized:
              // if last FBO texture was uninitialized, it means that nothing was changed,
              // so we can keep using cached FBO
              break;
            case GLMaskState.Initialized:
              // if last FBO was initialized, it means that something was definitely changed
              version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("  +++ need to reset FBO cache\n"); }
              glnvg__resetFBOClipTextureCache(gl);
              break;
            case GLMaskState.JustCleared: assert(0, "NanoVega: internal FBO stack error");
          }
          break;
        case GLNVG_RESETCLIP:
          // mark current mask as "don't mask"
          version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("FBO(%d): reset clip (cache:%d); current state is %d\n", gl.msp-1, gl.lastClipFBO, gl.maskStack.ptr[gl.msp-1]); }
          if (gl.msp > 0) {
            if (gl.maskStack.ptr[gl.msp-1] != GLMaskState.DontMask) {
              gl.maskStack.ptr[gl.msp-1] = GLMaskState.DontMask;
              version(nanovega_debug_clipping) if (nanovegaClipDebugDump) { import core.stdc.stdio; printf("  +++ need to reset FBO cache\n"); }
              glnvg__resetFBOClipTextureCache(gl);
            }
          }
          break;
        case GLNVG_CLIP_DDUMP_ON:
          version(nanovega_debug_clipping) nanovegaClipDebugDump = true;
          break;
        case GLNVG_CLIP_DDUMP_OFF:
          version(nanovega_debug_clipping) nanovegaClipDebugDump = false;
          break;
        case GLNVG_NONE: break;
        default:
          {
            import core.stdc.stdio; stderr.fprintf("NanoVega FATAL: invalid command in OpenGL backend: %d\n", call.type);
          }
          assert(0, "NanoVega: invalid command in OpenGL backend (fatal internal error)");
      }
      // and free texture, why not
      glnvg__deleteTexture(gl, call.image);
    }

    glDisableVertexAttribArray(0);
    glDisableVertexAttribArray(1);
    glDisable(GL_CULL_FACE);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glUseProgram(0);
    glnvg__bindTexture(gl, 0);
  }

  // this will do all necessary cleanup
  glnvg__renderCancelInternal(gl, false); // no need to clear textures
}

int glnvg__maxVertCount (const(NVGpath)* paths, int npaths) nothrow @trusted @nogc {
  int count = 0;
  foreach (int i; 0..npaths) {
    count += paths[i].nfill;
    count += paths[i].nstroke;
  }
  return count;
}

GLNVGcall* glnvg__allocCall (GLNVGcontext* gl) nothrow @trusted @nogc {
  GLNVGcall* ret = null;
  if (gl.ncalls+1 > gl.ccalls) {
    GLNVGcall* calls;
    int ccalls = glnvg__maxi(gl.ncalls+1, 128)+gl.ccalls/2; // 1.5x Overallocate
    calls = cast(GLNVGcall*)realloc(gl.calls, GLNVGcall.sizeof*ccalls);
    if (calls is null) return null;
    gl.calls = calls;
    gl.ccalls = ccalls;
  }
  ret = &gl.calls[gl.ncalls++];
  memset(ret, 0, GLNVGcall.sizeof);
  return ret;
}

int glnvg__allocPaths (GLNVGcontext* gl, int n) nothrow @trusted @nogc {
  int ret = 0;
  if (gl.npaths+n > gl.cpaths) {
    GLNVGpath* paths;
    int cpaths = glnvg__maxi(gl.npaths+n, 128)+gl.cpaths/2; // 1.5x Overallocate
    paths = cast(GLNVGpath*)realloc(gl.paths, GLNVGpath.sizeof*cpaths);
    if (paths is null) return -1;
    gl.paths = paths;
    gl.cpaths = cpaths;
  }
  ret = gl.npaths;
  gl.npaths += n;
  return ret;
}

int glnvg__allocVerts (GLNVGcontext* gl, int n) nothrow @trusted @nogc {
  int ret = 0;
  if (gl.nverts+n > gl.cverts) {
    NVGvertex* verts;
    int cverts = glnvg__maxi(gl.nverts+n, 4096)+gl.cverts/2; // 1.5x Overallocate
    verts = cast(NVGvertex*)realloc(gl.verts, NVGvertex.sizeof*cverts);
    if (verts is null) return -1;
    gl.verts = verts;
    gl.cverts = cverts;
  }
  ret = gl.nverts;
  gl.nverts += n;
  return ret;
}

int glnvg__allocFragUniforms (GLNVGcontext* gl, int n) nothrow @trusted @nogc {
  int ret = 0, structSize = gl.fragSize;
  if (gl.nuniforms+n > gl.cuniforms) {
    ubyte* uniforms;
    int cuniforms = glnvg__maxi(gl.nuniforms+n, 128)+gl.cuniforms/2; // 1.5x Overallocate
    uniforms = cast(ubyte*)realloc(gl.uniforms, structSize*cuniforms);
    if (uniforms is null) return -1;
    gl.uniforms = uniforms;
    gl.cuniforms = cuniforms;
  }
  ret = gl.nuniforms*structSize;
  gl.nuniforms += n;
  return ret;
}

GLNVGfragUniforms* nvg__fragUniformPtr (GLNVGcontext* gl, int i) nothrow @trusted @nogc {
  return cast(GLNVGfragUniforms*)&gl.uniforms[i];
}

void glnvg__vset (NVGvertex* vtx, float x, float y, float u, float v) nothrow @trusted @nogc {
  vtx.x = x;
  vtx.y = y;
  vtx.u = u;
  vtx.v = v;
}

void glnvg__renderFill (void* uptr, NVGCompositeOperationState compositeOperation, NVGClipMode clipmode, NVGPaint* paint, NVGscissor* scissor, float fringe, const(float)* bounds, const(NVGpath)* paths, int npaths, bool evenOdd) nothrow @trusted @nogc {
  if (npaths < 1) return;

  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGcall* call = glnvg__allocCall(gl);
  NVGvertex* quad;
  GLNVGfragUniforms* frag;
  int maxverts, offset;

  if (call is null) return;

  call.type = GLNVG_FILL;
  call.evenOdd = evenOdd;
  call.clipmode = clipmode;
  //if (clipmode != NVGClipMode.None) { import core.stdc.stdio; printf("CLIP!\n"); }
  call.blendFunc = glnvg__buildBlendFunc(compositeOperation);
  call.triangleCount = 4;
  call.pathOffset = glnvg__allocPaths(gl, npaths);
  if (call.pathOffset == -1) goto error;
  call.pathCount = npaths;
  call.image = paint.image.id;
  if (call.image > 0) glnvg__renderTextureIncRef(uptr, call.image);

  if (npaths == 1 && paths[0].convex) {
    call.type = GLNVG_CONVEXFILL;
    call.triangleCount = 0; // Bounding box fill quad not needed for convex fill
  }

  // Allocate vertices for all the paths.
  maxverts = glnvg__maxVertCount(paths, npaths)+call.triangleCount;
  offset = glnvg__allocVerts(gl, maxverts);
  if (offset == -1) goto error;

  foreach (int i; 0..npaths) {
    GLNVGpath* copy = &gl.paths[call.pathOffset+i];
    const(NVGpath)* path = &paths[i];
    memset(copy, 0, GLNVGpath.sizeof);
    if (path.nfill > 0) {
      copy.fillOffset = offset;
      copy.fillCount = path.nfill;
      memcpy(&gl.verts[offset], path.fill, NVGvertex.sizeof*path.nfill);
      offset += path.nfill;
    }
    if (path.nstroke > 0) {
      copy.strokeOffset = offset;
      copy.strokeCount = path.nstroke;
      memcpy(&gl.verts[offset], path.stroke, NVGvertex.sizeof*path.nstroke);
      offset += path.nstroke;
    }
  }

  // Setup uniforms for draw calls
  if (call.type == GLNVG_FILL) {
    import core.stdc.string : memcpy;
    // Quad
    call.triangleOffset = offset;
    quad = &gl.verts[call.triangleOffset];
    glnvg__vset(&quad[0], bounds[2], bounds[3], 0.5f, 1.0f);
    glnvg__vset(&quad[1], bounds[2], bounds[1], 0.5f, 1.0f);
    glnvg__vset(&quad[2], bounds[0], bounds[3], 0.5f, 1.0f);
    glnvg__vset(&quad[3], bounds[0], bounds[1], 0.5f, 1.0f);
    // Get uniform
    call.uniformOffset = glnvg__allocFragUniforms(gl, 2);
    if (call.uniformOffset == -1) goto error;
    // Simple shader for stencil
    frag = nvg__fragUniformPtr(gl, call.uniformOffset);
    memset(frag, 0, (*frag).sizeof);
    glnvg__convertPaint(gl, nvg__fragUniformPtr(gl, call.uniformOffset), paint, scissor, fringe, fringe, -1.0f);
    memcpy(nvg__fragUniformPtr(gl, call.uniformOffset+gl.fragSize), frag, (*frag).sizeof);
    frag.strokeThr = -1.0f;
    frag.type = NSVG_SHADER_SIMPLE;
    // Fill shader
    //glnvg__convertPaint(gl, nvg__fragUniformPtr(gl, call.uniformOffset+gl.fragSize), paint, scissor, fringe, fringe, -1.0f);
  } else {
    call.uniformOffset = glnvg__allocFragUniforms(gl, 1);
    if (call.uniformOffset == -1) goto error;
    // Fill shader
    glnvg__convertPaint(gl, nvg__fragUniformPtr(gl, call.uniformOffset), paint, scissor, fringe, fringe, -1.0f);
  }

  return;

error:
  // We get here if call alloc was ok, but something else is not.
  // Roll back the last call to prevent drawing it.
  if (gl.ncalls > 0) --gl.ncalls;
}

void glnvg__renderStroke (void* uptr, NVGCompositeOperationState compositeOperation, NVGClipMode clipmode, NVGPaint* paint, NVGscissor* scissor, float fringe, float strokeWidth, const(NVGpath)* paths, int npaths) nothrow @trusted @nogc {
  if (npaths < 1) return;

  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGcall* call = glnvg__allocCall(gl);
  int maxverts, offset;

  if (call is null) return;

  call.type = GLNVG_STROKE;
  call.clipmode = clipmode;
  call.blendFunc = glnvg__buildBlendFunc(compositeOperation);
  call.pathOffset = glnvg__allocPaths(gl, npaths);
  if (call.pathOffset == -1) goto error;
  call.pathCount = npaths;
  call.image = paint.image.id;
  if (call.image > 0) glnvg__renderTextureIncRef(uptr, call.image);

  // Allocate vertices for all the paths.
  maxverts = glnvg__maxVertCount(paths, npaths);
  offset = glnvg__allocVerts(gl, maxverts);
  if (offset == -1) goto error;

  foreach (int i; 0..npaths) {
    GLNVGpath* copy = &gl.paths[call.pathOffset+i];
    const(NVGpath)* path = &paths[i];
    memset(copy, 0, GLNVGpath.sizeof);
    if (path.nstroke) {
      copy.strokeOffset = offset;
      copy.strokeCount = path.nstroke;
      memcpy(&gl.verts[offset], path.stroke, NVGvertex.sizeof*path.nstroke);
      offset += path.nstroke;
    }
  }

  if (gl.flags&NVGContextFlag.StencilStrokes) {
    // Fill shader
    call.uniformOffset = glnvg__allocFragUniforms(gl, 2);
    if (call.uniformOffset == -1) goto error;
    glnvg__convertPaint(gl, nvg__fragUniformPtr(gl, call.uniformOffset), paint, scissor, strokeWidth, fringe, -1.0f);
    glnvg__convertPaint(gl, nvg__fragUniformPtr(gl, call.uniformOffset+gl.fragSize), paint, scissor, strokeWidth, fringe, 1.0f-0.5f/255.0f);
  } else {
    // Fill shader
    call.uniformOffset = glnvg__allocFragUniforms(gl, 1);
    if (call.uniformOffset == -1) goto error;
    glnvg__convertPaint(gl, nvg__fragUniformPtr(gl, call.uniformOffset), paint, scissor, strokeWidth, fringe, -1.0f);
  }

  return;

error:
  // We get here if call alloc was ok, but something else is not.
  // Roll back the last call to prevent drawing it.
  if (gl.ncalls > 0) --gl.ncalls;
}

void glnvg__renderTriangles (void* uptr, NVGCompositeOperationState compositeOperation, NVGClipMode clipmode, NVGPaint* paint, NVGscissor* scissor, const(NVGvertex)* verts, int nverts) nothrow @trusted @nogc {
  if (nverts < 1) return;

  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  GLNVGcall* call = glnvg__allocCall(gl);
  GLNVGfragUniforms* frag;

  if (call is null) return;

  call.type = GLNVG_TRIANGLES;
  call.clipmode = clipmode;
  call.blendFunc = glnvg__buildBlendFunc(compositeOperation);
  call.image = paint.image.id;
  if (call.image > 0) glnvg__renderTextureIncRef(uptr, call.image);

  // Allocate vertices for all the paths.
  call.triangleOffset = glnvg__allocVerts(gl, nverts);
  if (call.triangleOffset == -1) goto error;
  call.triangleCount = nverts;

  memcpy(&gl.verts[call.triangleOffset], verts, NVGvertex.sizeof*nverts);

  // Fill shader
  call.uniformOffset = glnvg__allocFragUniforms(gl, 1);
  if (call.uniformOffset == -1) goto error;
  frag = nvg__fragUniformPtr(gl, call.uniformOffset);
  glnvg__convertPaint(gl, frag, paint, scissor, 1.0f, 1.0f, -1.0f);
  frag.type = NSVG_SHADER_IMG;

  return;

error:
  // We get here if call alloc was ok, but something else is not.
  // Roll back the last call to prevent drawing it.
  if (gl.ncalls > 0) --gl.ncalls;
}

void glnvg__renderDelete (void* uptr) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)uptr;
  if (gl is null) return;

  glnvg__killFBOs(gl);
  glnvg__deleteShader(&gl.shader);
  glnvg__deleteShader(&gl.shaderFillFBO);
  glnvg__deleteShader(&gl.shaderCopyFBO);

  if (gl.vertBuf != 0) glDeleteBuffers(1, &gl.vertBuf);

  foreach (ref GLNVGtexture tex; gl.textures[0..gl.ntextures]) {
    if (tex.id != 0 && (tex.flags&NVGImageFlagsGL.NoDelete) == 0) {
      assert(tex.tex != 0);
      glDeleteTextures(1, &tex.tex);
    }
  }
  free(gl.textures);

  free(gl.paths);
  free(gl.verts);
  free(gl.uniforms);
  free(gl.calls);

  free(gl);
}


/** Creates NanoVega contexts for OpenGL2+.
 *
 * Specify creation flags as additional arguments, like this:
 * `nvgCreateContext(NVGContextFlag.Antialias, NVGContextFlag.StencilStrokes);`
 *
 * If you won't specify any flags, defaults will be used:
 * `[NVGContextFlag.Antialias, NVGContextFlag.StencilStrokes]`.
 *
 * Group: context_management
 */
public NVGContext nvgCreateContext (const(NVGContextFlag)[] flagList...) nothrow @trusted @nogc {
  version(aliced) {
    enum DefaultFlags = NVGContextFlag.Antialias|NVGContextFlag.StencilStrokes|NVGContextFlag.FontNoAA;
  } else {
    enum DefaultFlags = NVGContextFlag.Antialias|NVGContextFlag.StencilStrokes;
  }
  uint flags = 0;
  if (flagList.length != 0) {
    foreach (immutable flg; flagList) flags |= (flg != NVGContextFlag.Default ? flg : DefaultFlags);
  } else {
    flags = DefaultFlags;
  }
  NVGparams params = void;
  NVGContext ctx = null;
  version(nanovg_builtin_opengl_bindings) nanovgInitOpenGL(); // why not?
  GLNVGcontext* gl = cast(GLNVGcontext*)malloc(GLNVGcontext.sizeof);
  if (gl is null) goto error;
  memset(gl, 0, GLNVGcontext.sizeof);

  memset(&params, 0, params.sizeof);
  params.renderCreate = &glnvg__renderCreate;
  params.renderCreateTexture = &glnvg__renderCreateTexture;
  params.renderTextureIncRef = &glnvg__renderTextureIncRef;
  params.renderDeleteTexture = &glnvg__renderDeleteTexture;
  params.renderUpdateTexture = &glnvg__renderUpdateTexture;
  params.renderGetTextureSize = &glnvg__renderGetTextureSize;
  params.renderViewport = &glnvg__renderViewport;
  params.renderCancel = &glnvg__renderCancel;
  params.renderFlush = &glnvg__renderFlush;
  params.renderPushClip = &glnvg__renderPushClip;
  params.renderPopClip = &glnvg__renderPopClip;
  params.renderResetClip = &glnvg__renderResetClip;
  params.renderFill = &glnvg__renderFill;
  params.renderStroke = &glnvg__renderStroke;
  params.renderTriangles = &glnvg__renderTriangles;
  params.renderSetAffine = &glnvg__renderSetAffine;
  params.renderDelete = &glnvg__renderDelete;
  params.userPtr = gl;
  params.edgeAntiAlias = (flags&NVGContextFlag.Antialias ? true : false);
  if (flags&(NVGContextFlag.FontAA|NVGContextFlag.FontNoAA)) {
    params.fontAA = (flags&NVGContextFlag.FontNoAA ? NVG_INVERT_FONT_AA : !NVG_INVERT_FONT_AA);
  } else {
    params.fontAA = NVG_INVERT_FONT_AA;
  }

  gl.flags = flags;
  gl.freetexid = -1;

  ctx = createInternal(&params);
  if (ctx is null) goto error;

  return ctx;

error:
  // 'gl' is freed by nvgDeleteInternal.
  if (ctx !is null) ctx.deleteInternal();
  return null;
}

/// Create NanoVega OpenGL image from texture id.
/// Group: images
public int glCreateImageFromHandleGL2 (NVGContext ctx, GLuint textureId, int w, int h, int imageFlags) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)ctx.internalParams().userPtr;
  GLNVGtexture* tex = glnvg__allocTexture(gl);

  if (tex is null) return 0;

  tex.type = NVGtexture.RGBA;
  tex.tex = textureId;
  tex.flags = imageFlags;
  tex.width = w;
  tex.height = h;

  return tex.id;
}

/// Returns OpenGL texture id for NanoVega image.
/// Group: images
public GLuint glImageHandleGL2 (NVGContext ctx, int image) nothrow @trusted @nogc {
  GLNVGcontext* gl = cast(GLNVGcontext*)ctx.internalParams().userPtr;
  GLNVGtexture* tex = glnvg__findTexture(gl, image);
  return tex.tex;
}


// ////////////////////////////////////////////////////////////////////////// //
private:

static if (NanoVegaHasFontConfig) {
  version(nanovg_builtin_fontconfig_bindings) {
    pragma(lib, "fontconfig");

    private extern(C) nothrow @trusted @nogc {
      enum FC_FILE = "file"; /* String */
      alias FcBool = int;
      alias FcChar8 = char;
      struct FcConfig;
      struct FcPattern;
      alias FcMatchKind = int;
      enum : FcMatchKind {
        FcMatchPattern,
        FcMatchFont,
        FcMatchScan
      }
      alias FcResult = int;
      enum : FcResult {
        FcResultMatch,
        FcResultNoMatch,
        FcResultTypeMismatch,
        FcResultNoId,
        FcResultOutOfMemory
      }
      FcBool FcInit ();
      FcBool FcConfigSubstituteWithPat (FcConfig* config, FcPattern* p, FcPattern* p_pat, FcMatchKind kind);
      void FcDefaultSubstitute (FcPattern* pattern);
      FcBool FcConfigSubstitute (FcConfig* config, FcPattern* p, FcMatchKind kind);
      FcPattern* FcFontMatch (FcConfig* config, FcPattern* p, FcResult* result);
      FcPattern* FcNameParse (const(FcChar8)* name);
      void FcPatternDestroy (FcPattern* p);
      FcResult FcPatternGetString (const(FcPattern)* p, const(char)* object, int n, FcChar8** s);
    }
  }

  __gshared bool fontconfigAvailable = false;
  // initialize fontconfig
  shared static this () {
    if (FcInit()) {
      fontconfigAvailable = true;
    } else {
      import core.stdc.stdio : stderr, fprintf;
      stderr.fprintf("***NanoVega WARNING: cannot init fontconfig!\n");
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
public enum BaphometDims = 512.0f; // baphomet icon is 512x512 ([0..511])

private static immutable ubyte[7641] baphometPath = [
  0x01,0x04,0x06,0x30,0x89,0x7f,0x43,0x00,0x80,0xff,0x43,0x08,0xa0,0x1d,0xc6,0x43,0x00,0x80,0xff,0x43,
  0x00,0x80,0xff,0x43,0xa2,0x1d,0xc6,0x43,0x00,0x80,0xff,0x43,0x30,0x89,0x7f,0x43,0x08,0x00,0x80,0xff,
  0x43,0x7a,0x89,0xe5,0x42,0xa0,0x1d,0xc6,0x43,0x00,0x00,0x00,0x00,0x30,0x89,0x7f,0x43,0x00,0x00,0x00,
  0x00,0x08,0x7a,0x89,0xe5,0x42,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x7a,0x89,0xe5,0x42,0x00,0x00,
  0x00,0x00,0x30,0x89,0x7f,0x43,0x08,0x00,0x00,0x00,0x00,0xa2,0x1d,0xc6,0x43,0x7a,0x89,0xe5,0x42,0x00,
  0x80,0xff,0x43,0x30,0x89,0x7f,0x43,0x00,0x80,0xff,0x43,0x09,0x06,0x30,0x89,0x7f,0x43,0x72,0x87,0xdd,
  0x43,0x08,0x16,0x68,0xb3,0x43,0x72,0x87,0xdd,0x43,0x71,0x87,0xdd,0x43,0x17,0x68,0xb3,0x43,0x71,0x87,
  0xdd,0x43,0x30,0x89,0x7f,0x43,0x08,0x71,0x87,0xdd,0x43,0xd2,0x2f,0x18,0x43,0x16,0x68,0xb3,0x43,0x35,
  0xe2,0x87,0x42,0x30,0x89,0x7f,0x43,0x35,0xe2,0x87,0x42,0x08,0xd1,0x2f,0x18,0x43,0x35,0xe2,0x87,0x42,
  0x35,0xe2,0x87,0x42,0xd2,0x2f,0x18,0x43,0x35,0xe2,0x87,0x42,0x30,0x89,0x7f,0x43,0x08,0x35,0xe2,0x87,
  0x42,0x17,0x68,0xb3,0x43,0xd1,0x2f,0x18,0x43,0x72,0x87,0xdd,0x43,0x30,0x89,0x7f,0x43,0x72,0x87,0xdd,
  0x43,0x09,0x06,0x79,0xcb,0x11,0x43,0x62,0xbf,0xd7,0x42,0x07,0xa4,0x3f,0x7f,0x43,0x0b,0x86,0xdc,0x43,
  0x07,0x6c,0xb9,0xb2,0x43,0xe8,0xd1,0xca,0x42,0x07,0x6e,0x4d,0xa0,0x42,0xa9,0x10,0x9c,0x43,0x07,0xb7,
  0x40,0xd7,0x43,0xa9,0x10,0x9c,0x43,0x07,0x79,0xcb,0x11,0x43,0x62,0xbf,0xd7,0x42,0x09,0x06,0x98,0x42,
  0x74,0x43,0xb1,0x8d,0x68,0x43,0x08,0xd7,0x24,0x79,0x43,0xba,0x83,0x6e,0x43,0xa9,0x16,0x7c,0x43,0x56,
  0xa1,0x76,0x43,0x74,0x2a,0x7d,0x43,0x44,0x73,0x80,0x43,0x08,0x55,0xd1,0x7e,0x43,0xe3,0xea,0x76,0x43,
  0xbc,0x18,0x81,0x43,0x7f,0xa8,0x6e,0x43,0x8f,0x0a,0x84,0x43,0x02,0xfc,0x68,0x43,0x09,0x06,0x92,0x29,
  0x8d,0x43,0x73,0xc3,0x67,0x43,0x08,0xa4,0xd9,0x8e,0x43,0xf2,0xa6,0x7a,0x43,0x8f,0x22,0x88,0x43,0x75,
  0x2a,0x7d,0x43,0x42,0x7f,0x82,0x43,0x08,0xc8,0x88,0x43,0x09,0x06,0xc1,0x79,0x74,0x43,0x50,0x64,0x89,
  0x43,0x08,0x68,0x2d,0x72,0x43,0xee,0x21,0x81,0x43,0xcd,0x97,0x55,0x43,0xe6,0xf1,0x7b,0x43,0x91,0xec,
  0x5d,0x43,0xa8,0xc7,0x6a,0x43,0x09,0x06,0xfa,0xa5,0x52,0x43,0x60,0x97,0x7c,0x43,0x08,0x19,0xff,0x50,
  0x43,0xe9,0x6e,0x8a,0x43,0xb0,0xbd,0x70,0x43,0x4c,0x51,0x82,0x43,0x04,0xeb,0x69,0x43,0x66,0x0f,0x8e,
  0x43,0x09,0x06,0x17,0xbf,0x71,0x43,0x2c,0x58,0x94,0x43,0x08,0x1c,0x96,0x6e,0x43,0x61,0x68,0x99,0x43,
  0x2d,0x3a,0x6e,0x43,0xc8,0x81,0x9e,0x43,0xb7,0x9b,0x72,0x43,0x61,0xa4,0xa3,0x43,0x09,0x06,0x30,0xdb,
  0x82,0x43,0xdb,0xe9,0x93,0x43,0x08,0x11,0x82,0x84,0x43,0x61,0x68,0x99,0x43,0xe8,0x4a,0x84,0x43,0x8e,
  0xa6,0x9e,0x43,0x42,0x7f,0x82,0x43,0x61,0xa4,0xa3,0x43,0x09,0x06,0xc4,0x02,0x85,0x43,0xd1,0x0b,0x92,
  0x43,0x08,0xd6,0xb2,0x86,0x43,0x34,0x1e,0x92,0x43,0x4f,0x58,0x87,0x43,0xa4,0xf1,0x92,0x43,0x03,0xd9,
  0x87,0x43,0x7b,0xc6,0x94,0x43,0x09,0x06,0x87,0x3e,0x64,0x43,0x31,0x3b,0x93,0x43,0x08,0x3b,0xbf,0x64,
  0x43,0x6f,0xf9,0x91,0x43,0x96,0x0b,0x67,0x43,0xc5,0x4a,0x91,0x43,0xcf,0xfe,0x6a,0x43,0x31,0x2f,0x91,
  0x43,0x09,0x06,0x16,0x74,0xb5,0x43,0x08,0xec,0x8e,0x43,0x08,0x1b,0x4b,0xb2,0x43,0xee,0x5d,0x8b,0x43,
  0x48,0x4d,0xad,0x43,0x12,0xa6,0x8a,0x43,0xf3,0xd7,0xa7,0x43,0x74,0xb8,0x8a,0x43,0x08,0x8c,0xb2,0xa0,
  0x43,0xcd,0xf8,0x8a,0x43,0x68,0x46,0x9b,0x43,0x79,0x8f,0x87,0x43,0x49,0xc9,0x96,0x43,0xe9,0x3e,0x82,
  0x43,0x08,0x60,0x5c,0x97,0x43,0xa1,0xde,0x8b,0x43,0x4e,0xa0,0x93,0x43,0x31,0x3b,0x93,0x43,0x9f,0xea,
  0x8d,0x43,0x27,0x8d,0x99,0x43,0x08,0x07,0xe0,0x8c,0x43,0x06,0x34,0x9b,0x43,0x38,0xe9,0x8c,0x43,0x46,
  0x0a,0x9e,0x43,0x3d,0xcc,0x8b,0x43,0xb2,0x06,0xa2,0x43,0x08,0xf1,0x40,0x8a,0x43,0xb0,0x12,0xa4,0x43,
  0x39,0xd1,0x88,0x43,0x76,0x43,0xa6,0x43,0xfa,0x06,0x88,0x43,0xa4,0x75,0xa9,0x43,0x08,0x19,0x6c,0x88,
  0x43,0x9f,0x9e,0xac,0x43,0x66,0xeb,0x87,0x43,0x44,0x76,0xb0,0x43,0x6b,0xce,0x86,0x43,0x3b,0xbc,0xb4,
  0x43,0x08,0xa9,0x8c,0x85,0x43,0x06,0xd0,0xb5,0x43,0xfa,0xee,0x83,0x43,0x74,0xa3,0xb6,0x43,0x3d,0x90,
  0x81,0x43,0x31,0xf6,0xb6,0x43,0x08,0x9d,0x61,0x7d,0x43,0xee,0x48,0xb7,0x43,0x3b,0x1f,0x75,0x43,0xcf,
  0xe3,0xb6,0x43,0xee,0x6f,0x6d,0x43,0x68,0xe2,0xb5,0x43,0x08,0xd4,0xed,0x6b,0x43,0x87,0x2f,0xb2,0x43,
  0x0e,0xc9,0x6b,0x43,0xa7,0x7c,0xae,0x43,0x98,0xfa,0x67,0x43,0xab,0x53,0xab,0x43,0x08,0x25,0x2c,0x64,
  0x43,0x33,0xa2,0xa8,0x43,0x40,0x96,0x61,0x43,0xc3,0xc2,0xa5,0x43,0x64,0xde,0x60,0x43,0xfa,0xa2,0xa2,
  0x43,0x08,0xb0,0x5d,0x60,0x43,0x06,0x4c,0x9f,0x43,0x9a,0xca,0x5f,0x43,0x38,0x3d,0x9b,0x43,0x3b,0x8f,
  0x5c,0x43,0x85,0xb0,0x98,0x43,0x08,0x42,0x36,0x51,0x43,0x3d,0xf0,0x91,0x43,0xcd,0x4f,0x49,0x43,0xdb,
  0xb9,0x8b,0x43,0xe0,0xdb,0x44,0x43,0x42,0x8b,0x84,0x43,0x08,0x7e,0xc9,0x44,0x43,0x8a,0x57,0x8d,0x43,
  0xbc,0x6c,0x0f,0x43,0x23,0x62,0x8e,0x43,0xf5,0x17,0x07,0x43,0xc5,0x3e,0x8f,0x43,0x09,0x06,0xe0,0xea,
  0x76,0x43,0xab,0xef,0xc5,0x43,0x08,0x12,0x00,0x79,0x43,0xab,0xcb,0xbf,0x43,0x79,0xb9,0x6d,0x43,0x7e,
  0x8d,0xba,0x43,0xee,0x6f,0x6d,0x43,0x98,0xeb,0xb5,0x43,0x08,0xe0,0x02,0x7b,0x43,0x5f,0x1c,0xb8,0x43,
  0x85,0x2c,0x82,0x43,0xe9,0x65,0xb8,0x43,0xd6,0xb2,0x86,0x43,0xc6,0x05,0xb5,0x43,0x08,0x03,0xcd,0x85,
  0x43,0x5a,0x39,0xb9,0x43,0xe4,0x4f,0x81,0x43,0xdb,0xd4,0xbf,0x43,0xdf,0x6c,0x82,0x43,0xbc,0x93,0xc5,
  0x43,0x09,0x06,0xf0,0xd0,0x22,0x43,0x5d,0x19,0x08,0x43,0x08,0xbc,0xab,0x49,0x43,0x4a,0x35,0x29,0x43,
  0xcb,0xf7,0x65,0x43,0xce,0x37,0x45,0x43,0x0e,0x99,0x63,0x43,0x67,0xc6,0x5c,0x43,0x09,0x06,0x05,0x94,
  0xab,0x43,0xc2,0x13,0x04,0x43,0x08,0x9f,0x26,0x98,0x43,0x11,0x42,0x25,0x43,0x97,0x00,0x8a,0x43,0x32,
  0x32,0x41,0x43,0xf5,0x2f,0x8b,0x43,0xc7,0xc0,0x58,0x43,0x09,0x06,0x8f,0x85,0x48,0x43,0xe0,0xa8,0x8c,
  0x43,0x08,0x55,0xaa,0x48,0x43,0xe0,0xa8,0x8c,0x43,0x6b,0x3d,0x49,0x43,0xc1,0x43,0x8c,0x43,0x31,0x62,
  0x49,0x43,0xc1,0x43,0x8c,0x43,0x08,0x2f,0xe3,0x2f,0x43,0xad,0xe7,0x98,0x43,0xff,0x0d,0x0d,0x43,0xad,
  0xf3,0x9a,0x43,0xf0,0xaf,0xcc,0x42,0x74,0x00,0x97,0x43,0x08,0xbb,0xa2,0xf7,0x42,0x93,0x4d,0x93,0x43,
  0x5e,0x19,0x08,0x43,0x5a,0x2a,0x87,0x43,0x23,0x6e,0x10,0x43,0x42,0x97,0x86,0x43,0x08,0xca,0xe8,0x33,
  0x43,0x1b,0x3c,0x80,0x43,0x80,0xe8,0x4d,0x43,0xda,0xf4,0x70,0x43,0xae,0x0e,0x4f,0x43,0x2b,0x1b,0x65,
  0x43,0x08,0x66,0x96,0x54,0x43,0xa3,0xe1,0x3b,0x43,0x4e,0xc4,0x19,0x43,0xa0,0x1a,0x16,0x43,0x10,0xe2,
  0x14,0x43,0x26,0x14,0xe0,0x42,0x08,0x5c,0x91,0x1c,0x43,0xcb,0x27,0xee,0x42,0xa9,0x40,0x24,0x43,0x71,
  0x3b,0xfc,0x42,0xf3,0xef,0x2b,0x43,0x8b,0x27,0x05,0x43,0x08,0xe2,0x4b,0x2c,0x43,0x48,0x86,0x07,0x43,
  0x79,0x62,0x2f,0x43,0x05,0xe5,0x09,0x43,0x55,0x32,0x34,0x43,0xa0,0xd2,0x09,0x43,0x08,0x74,0xa3,0x36,
  0x43,0x3a,0xd1,0x08,0x43,0x7e,0x81,0x38,0x43,0x09,0xd4,0x0a,0x43,0x0d,0xba,0x39,0x43,0xa0,0xea,0x0d,
  0x43,0x08,0x6f,0xe4,0x3d,0x43,0x43,0xc7,0x0e,0x43,0xd6,0xe5,0x3e,0x43,0xc4,0x4a,0x11,0x43,0x55,0x7a,
  0x40,0x43,0x59,0x72,0x13,0x43,0x08,0x55,0x92,0x44,0x43,0xbf,0x73,0x14,0x43,0x23,0x95,0x46,0x43,0xa5,
  0x09,0x17,0x43,0xe0,0xf3,0x48,0x43,0xfe,0x55,0x19,0x43,0x08,0xcd,0x4f,0x49,0x43,0xaa,0x10,0x1c,0x43,
  0x61,0x77,0x4b,0x43,0xfe,0x6d,0x1d,0x43,0x80,0xe8,0x4d,0x43,0x2b,0x94,0x1e,0x43,0x08,0x58,0xc9,0x51,
  0x43,0x41,0x27,0x1f,0x43,0x9b,0x82,0x53,0x43,0x35,0x72,0x20,0x43,0x53,0xf2,0x54,0x43,0x88,0xcf,0x21,
  0x43,0x08,0x7b,0x29,0x55,0x43,0xe8,0x0a,0x25,0x43,0xb2,0x2d,0x58,0x43,0xef,0xe8,0x26,0x43,0x9b,0xb2,
  0x5b,0x43,0xd0,0x8f,0x28,0x43,0x08,0x5f,0xef,0x5f,0x43,0xeb,0x11,0x2a,0x43,0xfd,0xdc,0x5f,0x43,0x6e,
  0x95,0x2c,0x43,0x3b,0xa7,0x60,0x43,0x2b,0xf4,0x2e,0x43,0x08,0x06,0xbb,0x61,0x43,0xfd,0xe5,0x31,0x43,
  0xe7,0x61,0x63,0x43,0xef,0x30,0x33,0x43,0x53,0x52,0x65,0x43,0xa3,0xb1,0x33,0x43,0x08,0x12,0xa0,0x68,
  0x43,0x7f,0x69,0x34,0x43,0x40,0xc6,0x69,0x43,0x64,0xff,0x36,0x43,0x7e,0x90,0x6a,0x43,0x71,0xcc,0x39,
  0x43,0x08,0xbc,0x5a,0x6b,0x43,0x51,0x73,0x3b,0x43,0xc1,0x49,0x6c,0x43,0xa5,0xd0,0x3c,0x43,0xe0,0xba,
  0x6e,0x43,0xb8,0x74,0x3c,0x43,0x08,0x6b,0x1c,0x73,0x43,0x13,0xc1,0x3e,0x43,0x40,0xf6,0x71,0x43,0xce,
  0x1f,0x41,0x43,0x55,0x89,0x72,0x43,0x8d,0x7e,0x43,0x43,0x08,0x68,0x2d,0x72,0x43,0x89,0xae,0x4b,0x43,
  0xc1,0x79,0x74,0x43,0xcb,0x78,0x4c,0x43,0x55,0xa1,0x76,0x43,0x5b,0xb1,0x4d,0x43,0x08,0xa2,0x38,0x7a,
  0x43,0xd1,0x56,0x4e,0x43,0x85,0xb6,0x78,0x43,0xb1,0x15,0x54,0x43,0x83,0xc7,0x77,0x43,0x89,0x0e,0x5c,
  0x43,0x08,0xcf,0x46,0x77,0x43,0x0f,0x81,0x5f,0x43,0x1a,0xde,0x7a,0x43,0xce,0xc7,0x5d,0x43,0x42,0x73,
  0x80,0x43,0x99,0xc3,0x5a,0x43,0x08,0x85,0x2c,0x82,0x43,0xf6,0xe6,0x59,0x43,0x81,0x3d,0x81,0x43,0x16,
  0x10,0x50,0x43,0xd6,0x8e,0x80,0x43,0x5b,0x99,0x49,0x43,0x08,0xc4,0xea,0x80,0x43,0x22,0x95,0x46,0x43,
  0xfa,0xe2,0x81,0x43,0xda,0xec,0x43,0x43,0x78,0x77,0x83,0x43,0xe4,0xb2,0x41,0x43,0x08,0x8a,0x27,0x85,
  0x43,0x86,0x77,0x3e,0x43,0x0c,0x9f,0x85,0x43,0x07,0xf4,0x3b,0x43,0x8f,0x16,0x86,0x43,0xe6,0x82,0x39,
  0x43,0x08,0x85,0x44,0x86,0x43,0x37,0xd9,0x35,0x43,0x1e,0x4f,0x87,0x43,0xe1,0x7b,0x34,0x43,0xdf,0x90,
  0x88,0x43,0xb6,0x55,0x33,0x43,0x08,0xae,0x93,0x8a,0x43,0xfd,0xe5,0x31,0x43,0xfa,0x12,0x8a,0x43,0xbf,
  0x03,0x2d,0x43,0x19,0x78,0x8a,0x43,0x45,0x5e,0x2c,0x43,0x08,0x03,0xf1,0x8b,0x43,0xac,0x47,0x29,0x43,
  0x2f,0x17,0x8d,0x43,0x45,0x46,0x28,0x43,0xc8,0x21,0x8e,0x43,0x30,0xb3,0x27,0x43,0x08,0xa9,0xc8,0x8f,
  0x43,0xef,0xe8,0x26,0x43,0xbf,0x5b,0x90,0x43,0x5b,0xc1,0x24,0x43,0x10,0xca,0x90,0x43,0xa0,0x62,0x22,
  0x43,0x08,0x26,0x5d,0x91,0x43,0xbb,0xcc,0x1f,0x43,0xf0,0x70,0x92,0x43,0x78,0x13,0x1e,0x43,0x77,0xd7,
  0x93,0x43,0x73,0x24,0x1d,0x43,0x08,0x65,0x3f,0x96,0x43,0xce,0x58,0x1b,0x43,0xbe,0x7f,0x96,0x43,0xbf,
  0x8b,0x18,0x43,0x60,0x5c,0x97,0x43,0xb6,0xad,0x16,0x43,0x08,0xba,0xa8,0x99,0x43,0x78,0xcb,0x11,0x43,
  0x49,0xe1,0x9a,0x43,0x78,0xcb,0x11,0x43,0x01,0x51,0x9c,0x43,0x73,0xdc,0x10,0x43,0x08,0x72,0x24,0x9d,
  0x43,0xd2,0xff,0x0f,0x43,0x1c,0xd3,0x9d,0x43,0x07,0xec,0x0e,0x43,0xeb,0xc9,0x9d,0x43,0xe8,0x7a,0x0c,
  0x43,0x08,0x60,0x80,0x9d,0x43,0xd7,0xbe,0x08,0x43,0x4d,0xe8,0x9f,0x43,0x86,0x50,0x08,0x43,0x25,0xbd,
  0xa1,0x43,0x5b,0x2a,0x07,0x43,0x08,0x99,0x7f,0xa3,0x43,0xc9,0xf1,0x05,0x43,0x48,0x1d,0xa5,0x43,0x86,
  0x38,0x04,0x43,0x6c,0x71,0xa6,0x43,0x18,0x59,0x01,0x43,0x08,0x32,0x96,0xa6,0x43,0x6e,0x64,0xff,0x42,
  0x48,0x29,0xa7,0x43,0xed,0xcf,0xfd,0x42,0x5f,0xbc,0xa7,0x43,0x71,0x3b,0xfc,0x42,0x08,0xf3,0xe3,0xa9,
  0x43,0xf7,0x7d,0xf7,0x42,0xd8,0x6d,0xaa,0x43,0x45,0xe5,0xf2,0x42,0x48,0x41,0xab,0x43,0xcb,0x27,0xee,
  0x42,0x08,0x24,0xf9,0xab,0x43,0x52,0x6a,0xe9,0x42,0xee,0x0c,0xad,0x43,0x4c,0x8c,0xe7,0x42,0x1b,0x33,
  0xae,0x43,0xcc,0xf7,0xe5,0x42,0x08,0xaa,0x6b,0xaf,0x43,0xe8,0x61,0xe3,0x42,0x90,0xf5,0xaf,0x43,0xc9,
  0xf0,0xe0,0x42,0xe0,0x63,0xb0,0x43,0xe5,0x5a,0xde,0x42,0x08,0xaa,0x83,0xb3,0x43,0x29,0x2d,0x09,0x43,
  0x6a,0xfe,0x8e,0x43,0xb8,0x74,0x3c,0x43,0xd5,0x06,0x95,0x43,0xe6,0x79,0x67,0x43,0x08,0x2f,0x53,0x97,
  0x43,0xe9,0xb0,0x74,0x43,0xa8,0x28,0xa0,0x43,0x43,0xfd,0x76,0x43,0x83,0x28,0xad,0x43,0x17,0x59,0x81,
  0x43,0x08,0x3d,0xe7,0xbf,0x43,0x4b,0x8d,0x8c,0x43,0xae,0x96,0xba,0x43,0x66,0x27,0x92,0x43,0x15,0xe0,
  0xc7,0x43,0x6f,0x11,0x96,0x43,0x08,0x7e,0x5d,0xb2,0x43,0xdb,0x01,0x98,0x43,0x9e,0x56,0xa0,0x43,0x80,
  0xc1,0x97,0x43,0x69,0x2e,0x97,0x43,0x31,0x17,0x8d,0x43,0x09,0x06,0xab,0xa7,0x39,0x43,0x67,0x0f,0x0e,
  0x43,0x08,0xdb,0xbc,0x3b,0x43,0xe8,0x92,0x10,0x43,0xb5,0x85,0x3b,0x43,0x97,0x3c,0x14,0x43,0xab,0xa7,
  0x39,0x43,0x0c,0x0b,0x18,0x43,0x09,0x06,0xca,0x30,0x40,0x43,0x30,0x3b,0x13,0x43,0x08,0x17,0xc8,0x43,
  0x43,0xa5,0x09,0x17,0x43,0x7e,0xc9,0x44,0x43,0x1a,0xd8,0x1a,0x43,0x9d,0x22,0x43,0x43,0x8d,0xa6,0x1e,
  0x43,0x09,0x06,0xc8,0x78,0x4c,0x43,0xed,0xc9,0x1d,0x43,0x08,0x0b,0x32,0x4e,0x43,0x22,0xce,0x20,0x43,
  0x23,0xc5,0x4e,0x43,0x58,0xd2,0x23,0x43,0x0b,0x32,0x4e,0x43,0x2b,0xc4,0x26,0x43,0x09,0x06,0xec,0x08,
  0x58,0x43,0xc7,0xb1,0x26,0x43,0x08,0x02,0x9c,0x58,0x43,0xef,0x00,0x2b,0x43,0xd9,0x64,0x58,0x43,0x02,
  0xbd,0x2e,0x43,0x10,0x51,0x57,0x43,0x37,0xc1,0x31,0x43,0x09,0x06,0xcb,0xdf,0x61,0x43,0x4a,0x65,0x31,
  0x43,0x08,0xbe,0x2a,0x63,0x43,0xbd,0x33,0x35,0x43,0x32,0xe1,0x62,0x43,0x56,0x4a,0x38,0x43,0xde,0x83,
  0x61,0x43,0x3c,0xe0,0x3a,0x43,0x09,0x06,0x1c,0x7e,0x6a,0x43,0x5b,0x39,0x39,0x43,0x08,0x31,0x11,0x6b,
  0x43,0x0c,0xd2,0x3d,0x43,0x1c,0x7e,0x6a,0x43,0x13,0xd9,0x42,0x43,0xd9,0xc4,0x68,0x43,0xcb,0x60,0x48,
  0x43,0x09,0x06,0xe5,0xc1,0x73,0x43,0x16,0xf8,0x4b,0x43,0x08,0xa6,0xf7,0x72,0x43,0xb1,0xfd,0x4f,0x43,
  0x3b,0x07,0x71,0x43,0x4a,0x14,0x53,0x43,0xa2,0xf0,0x6d,0x43,0x7c,0x29,0x55,0x43,0x09,0x06,0x00,0x8d,
  0xa6,0x43,0xef,0x21,0x01,0x43,0x08,0x52,0xfb,0xa6,0x43,0xce,0xc8,0x02,0x43,0xe6,0x16,0xa7,0x43,0x51,
  0x4c,0x05,0x43,0x3b,0x68,0xa6,0x43,0x4c,0x75,0x08,0x43,0x09,0x06,0xde,0x20,0xa1,0x43,0x86,0x50,0x08,
  0x43,0x08,0xd4,0x4e,0xa1,0x43,0xd3,0xe7,0x0b,0x43,0xb5,0xe9,0xa0,0x43,0x59,0x5a,0x0f,0x43,0xba,0xcc,
  0x9f,0x43,0x54,0x83,0x12,0x43,0x09,0x06,0x77,0xfb,0x99,0x43,0x6c,0x16,0x13,0x43,0x08,0xde,0xfc,0x9a,
  0x43,0x4a,0xbd,0x14,0x43,0x06,0x34,0x9b,0x43,0xfe,0x55,0x19,0x43,0x13,0xe9,0x99,0x43,0x41,0x27,0x1f,
  0x43,0x09,0x06,0x46,0xce,0x93,0x43,0x26,0xa5,0x1d,0x43,0x08,0xe7,0xaa,0x94,0x43,0xbb,0xcc,0x1f,0x43,
  0x18,0xb4,0x94,0x43,0xa8,0x40,0x24,0x43,0xe2,0xbb,0x93,0x43,0x21,0xfe,0x28,0x43,0x09,0x06,0xb1,0x8e,
  0x8d,0x43,0xa8,0x58,0x28,0x43,0x08,0x19,0x90,0x8e,0x43,0x54,0x13,0x2b,0x43,0xa4,0xd9,0x8e,0x43,0x84,
  0x40,0x31,0x43,0x46,0xaa,0x8d,0x43,0x29,0x24,0x37,0x43,0x09,0x06,0xd6,0xbe,0x88,0x43,0xef,0x30,0x33,
  0x43,0x08,0x0c,0xb7,0x89,0x43,0x0e,0xa2,0x35,0x43,0xc0,0x37,0x8a,0x43,0x7a,0xaa,0x3b,0x43,0xbb,0x48,
  0x89,0x43,0xbb,0x7b,0x41,0x43,0x09,0x06,0x3a,0xad,0x82,0x43,0xc4,0x59,0x43,0x43,0x08,0xd2,0xb7,0x83,
  0x43,0x2b,0x5b,0x44,0x43,0x35,0xd6,0x85,0x43,0x48,0xf5,0x49,0x43,0x42,0x97,0x86,0x43,0xc4,0xa1,0x4f,
  0x43,0x09,0x06,0x9c,0xb3,0x80,0x43,0x48,0x55,0x5a,0x43,0x08,0xff,0xc5,0x80,0x43,0x09,0x73,0x55,0x43,
  0x93,0xe1,0x80,0x43,0x0f,0x39,0x53,0x43,0xf1,0xbe,0x7e,0x43,0x18,0xe7,0x4c,0x43,0x09,0x06,0xe0,0x02,
  0x7b,0x43,0x92,0xec,0x5d,0x43,0x08,0x09,0x3a,0x7b,0x43,0xf0,0xf7,0x58,0x43,0x09,0x3a,0x7b,0x43,0xe6,
  0x31,0x5b,0x43,0xe0,0x02,0x7b,0x43,0xa8,0x4f,0x56,0x43,0x09,0x06,0x39,0x4f,0x7d,0x43,0x3e,0x8f,0x5c,
  0x43,0x08,0xe9,0xe0,0x7c,0x43,0x03,0x9c,0x58,0x43,0x1e,0x2b,0x81,0x43,0x7f,0x30,0x5a,0x43,0xff,0x73,
  0x7d,0x43,0xf6,0xb6,0x51,0x43,0x09,0x06,0x5c,0xb8,0x52,0x43,0x28,0x21,0x87,0x43,0x08,0xae,0x3e,0x57,
  0x43,0x12,0x9a,0x88,0x43,0x23,0xf5,0x56,0x43,0x04,0xf1,0x8b,0x43,0x25,0xfc,0x5b,0x43,0x85,0x74,0x8e,
  0x43,0x08,0x2f,0xf2,0x61,0x43,0x8e,0x52,0x90,0x43,0xd9,0xdc,0x6c,0x43,0x85,0x74,0x8e,0x43,0xc6,0x20,
  0x69,0x43,0x3d,0xd8,0x8d,0x43,0x08,0x6d,0x8c,0x5a,0x43,0xf5,0x3b,0x8d,0x43,0x3d,0x77,0x58,0x43,0xa1,
  0xc6,0x87,0x43,0xf8,0xed,0x5e,0x43,0x5e,0x0d,0x86,0x43,0x09,0x06,0xde,0xcc,0x92,0x43,0xf7,0x17,0x87,
  0x43,0x08,0xb6,0x89,0x90,0x43,0xae,0x87,0x88,0x43,0x4a,0xa5,0x90,0x43,0xa1,0xde,0x8b,0x43,0xf9,0x2a,
  0x8e,0x43,0x23,0x62,0x8e,0x43,0x08,0xf5,0x2f,0x8b,0x43,0x5c,0x49,0x90,0x43,0x35,0xd6,0x85,0x43,0x8e,
  0x46,0x8e,0x43,0x3d,0xb4,0x87,0x43,0x47,0xaa,0x8d,0x43,0x08,0x6a,0xfe,0x8e,0x43,0xff,0x0d,0x8d,0x43,
  0xbb,0x6c,0x8f,0x43,0xf7,0x17,0x87,0x43,0x5c,0x31,0x8c,0x43,0xb2,0x5e,0x85,0x43,0x09,0x06,0x60,0x38,
  0x91,0x43,0x69,0x5d,0x7a,0x43,0x08,0x34,0x1e,0x92,0x43,0x1e,0x5b,0x89,0x43,0x04,0x63,0x7e,0x43,0x5e,
  0x01,0x84,0x43,0x59,0x2a,0x87,0x43,0x0d,0xcf,0x8d,0x43,0x09,0x03,0x04,0x06,0x5a,0x18,0x63,0x43,0x82,
  0x79,0x8b,0x43,0x08,0x25,0x2c,0x64,0x43,0x82,0x79,0x8b,0x43,0x2a,0x1b,0x65,0x43,0x9d,0xef,0x8a,0x43,
  0x2a,0x1b,0x65,0x43,0xc1,0x37,0x8a,0x43,0x08,0x2a,0x1b,0x65,0x43,0x17,0x89,0x89,0x43,0x25,0x2c,0x64,
  0x43,0x31,0xff,0x88,0x43,0x5a,0x18,0x63,0x43,0x31,0xff,0x88,0x43,0x08,0xf3,0x16,0x62,0x43,0x31,0xff,
  0x88,0x43,0xee,0x27,0x61,0x43,0x17,0x89,0x89,0x43,0xee,0x27,0x61,0x43,0xc1,0x37,0x8a,0x43,0x08,0xee,
  0x27,0x61,0x43,0x9d,0xef,0x8a,0x43,0xf3,0x16,0x62,0x43,0x82,0x79,0x8b,0x43,0x5a,0x18,0x63,0x43,0x82,
  0x79,0x8b,0x43,0x09,0x06,0x4f,0x64,0x89,0x43,0x82,0x79,0x8b,0x43,0x08,0x34,0xee,0x89,0x43,0x82,0x79,
  0x8b,0x43,0x85,0x5c,0x8a,0x43,0x9d,0xef,0x8a,0x43,0x85,0x5c,0x8a,0x43,0xc1,0x37,0x8a,0x43,0x08,0x85,
  0x5c,0x8a,0x43,0x17,0x89,0x89,0x43,0x34,0xee,0x89,0x43,0x31,0xff,0x88,0x43,0x4f,0x64,0x89,0x43,0x31,
  0xff,0x88,0x43,0x08,0x9c,0xe3,0x88,0x43,0x31,0xff,0x88,0x43,0x19,0x6c,0x88,0x43,0x17,0x89,0x89,0x43,
  0x19,0x6c,0x88,0x43,0xc1,0x37,0x8a,0x43,0x08,0x19,0x6c,0x88,0x43,0x9d,0xef,0x8a,0x43,0x9c,0xe3,0x88,
  0x43,0x82,0x79,0x8b,0x43,0x4f,0x64,0x89,0x43,0x82,0x79,0x8b,0x43,0x09,0x02,0x04,0x06,0x19,0x60,0x86,
  0x43,0xec,0xed,0xa3,0x43,0x08,0x35,0xd6,0x85,0x43,0x76,0x43,0xa6,0x43,0x93,0xe1,0x80,0x43,0x57,0x02,
  0xac,0x43,0x61,0xd8,0x80,0x43,0x87,0x17,0xae,0x43,0x08,0xa5,0x85,0x80,0x43,0xc3,0xfe,0xaf,0x43,0xce,
  0xbc,0x80,0x43,0x83,0x40,0xb1,0x43,0xa5,0x91,0x82,0x43,0x79,0x6e,0xb1,0x43,0x08,0x23,0x26,0x84,0x43,
  0x40,0x93,0xb1,0x43,0x30,0xe7,0x84,0x43,0xbe,0x1b,0xb1,0x43,0x11,0x82,0x84,0x43,0xab,0x6b,0xaf,0x43,
  0x08,0xb7,0x41,0x84,0x43,0x3b,0x98,0xae,0x43,0xb7,0x41,0x84,0x43,0xc3,0xf2,0xad,0x43,0xa1,0xae,0x83,
  0x43,0x83,0x28,0xad,0x43,0x08,0xb2,0x52,0x83,0x43,0x80,0x39,0xac,0x43,0x81,0x49,0x83,0x43,0xf0,0x00,
  0xab,0x43,0xe4,0x67,0x85,0x43,0x76,0x4f,0xa8,0x43,0x08,0x9c,0xd7,0x86,0x43,0xd1,0x83,0xa6,0x43,0xec,
  0x45,0x87,0x43,0x01,0x75,0xa2,0x43,0x19,0x60,0x86,0x43,0xec,0xed,0xa3,0x43,0x09,0x06,0xd9,0xdc,0x6c,
  0x43,0x14,0x25,0xa4,0x43,0x08,0xa2,0xf0,0x6d,0x43,0x9f,0x7a,0xa6,0x43,0x47,0xec,0x77,0x43,0x80,0x39,
  0xac,0x43,0xa9,0xfe,0x77,0x43,0xb0,0x4e,0xae,0x43,0x08,0x23,0xa4,0x78,0x43,0xea,0x35,0xb0,0x43,0xd2,
  0x35,0x78,0x43,0xab,0x77,0xb1,0x43,0xc1,0x79,0x74,0x43,0xa2,0xa5,0xb1,0x43,0x08,0xc6,0x50,0x71,0x43,
  0x68,0xca,0xb1,0x43,0xab,0xce,0x6f,0x43,0xe7,0x52,0xb1,0x43,0xea,0x98,0x70,0x43,0xd4,0xa2,0xaf,0x43,
  0x08,0x9d,0x19,0x71,0x43,0x96,0xd8,0xae,0x43,0x9d,0x19,0x71,0x43,0xec,0x29,0xae,0x43,0xca,0x3f,0x72,
  0x43,0xab,0x5f,0xad,0x43,0x08,0xa6,0xf7,0x72,0x43,0xa7,0x70,0xac,0x43,0x09,0x0a,0x73,0x43,0x17,0x38,
  0xab,0x43,0x44,0xcd,0x6e,0x43,0x9f,0x86,0xa8,0x43,0x08,0xd4,0xed,0x6b,0x43,0xf8,0xba,0xa6,0x43,0x31,
  0x11,0x6b,0x43,0x2a,0xac,0xa2,0x43,0xd9,0xdc,0x6c,0x43,0x14,0x25,0xa4,0x43,0x09,0x01,0x05,0x06,0x66,
  0x5d,0x7a,0x43,0x74,0xeb,0xc2,0x43,0x08,0x09,0x22,0x77,0x43,0x50,0xbb,0xc7,0x43,0xe9,0xe0,0x7c,0x43,
  0xf5,0x86,0xc9,0x43,0x8f,0x94,0x7a,0x43,0xc5,0x95,0xcd,0x43,0x09,0x06,0x08,0x98,0x80,0x43,0x6b,0x19,
  0xc3,0x43,0x08,0xb7,0x35,0x82,0x43,0x79,0xf2,0xc7,0x43,0xf1,0xbe,0x7e,0x43,0x1e,0xbe,0xc9,0x43,0x73,
  0x7c,0x80,0x43,0xec,0xcc,0xcd,0x43,0x09,0x06,0x28,0xab,0x7d,0x43,0xae,0xde,0xc6,0x43,0x08,0x1e,0xcd,
  0x7b,0x43,0x8a,0xa2,0xc9,0x43,0x30,0x89,0x7f,0x43,0x5c,0x94,0xcc,0x43,0x28,0xab,0x7d,0x43,0x42,0x2a,
  0xcf,0x43,0x09,0x01,0x05,0x06,0x24,0x14,0xe0,0x42,0xf5,0x77,0x97,0x43,0x08,0xf7,0x1d,0xe7,0x42,0x74,
  0x00,0x97,0x43,0x4d,0x93,0xec,0x42,0xdb,0xf5,0x95,0x43,0x29,0x4b,0xed,0x42,0xcd,0x34,0x95,0x43,0x09,
  0x06,0x29,0x7b,0xf5,0x42,0x6f,0x1d,0x98,0x43,0x08,0xe4,0xf1,0xfb,0x42,0x61,0x5c,0x97,0x43,0xdb,0x7d,
  0x01,0x43,0xb2,0xbe,0x95,0x43,0x55,0x23,0x02,0x43,0xe7,0xaa,0x94,0x43,0x09,0x06,0x98,0xdc,0x03,0x43,
  0xbe,0x8b,0x98,0x43,0x08,0x66,0xdf,0x05,0x43,0x47,0xe6,0x97,0x43,0xae,0x87,0x08,0x43,0x98,0x48,0x96,
  0x43,0x61,0x08,0x09,0x43,0xd6,0x06,0x95,0x43,0x09,0x06,0x31,0x0b,0x0b,0x43,0x8e,0x82,0x98,0x43,0x08,
  0xdb,0xc5,0x0d,0x43,0x80,0xc1,0x97,0x43,0xd6,0xee,0x10,0x43,0xa9,0xec,0x95,0x43,0x79,0xcb,0x11,0x43,
  0x55,0x8f,0x94,0x43,0x09,0x06,0xd1,0x2f,0x18,0x43,0xdb,0x01,0x98,0x43,0x08,0xad,0xe7,0x18,0x43,0x38,
  0x25,0x97,0x43,0x8a,0x9f,0x19,0x43,0x80,0xb5,0x95,0x43,0xd6,0x1e,0x19,0x43,0xe0,0xd8,0x94,0x43,0x09,
  0x06,0x9a,0x5b,0x1d,0x43,0x58,0x8a,0x97,0x43,0x08,0x01,0x5d,0x1e,0x43,0xf1,0x88,0x96,0x43,0x2f,0x83,
  0x1f,0x43,0x19,0xb4,0x94,0x43,0x19,0xf0,0x1e,0x43,0x6f,0x05,0x94,0x43,0x09,0x06,0x0b,0x53,0x24,0x43,
  0xae,0xdb,0x96,0x43,0x08,0x25,0xd5,0x25,0x43,0x50,0xac,0x95,0x43,0x53,0xfb,0x26,0x43,0x8a,0x7b,0x93,
  0x43,0x76,0x43,0x26,0x43,0xb7,0x95,0x92,0x43,0x09,0x06,0x76,0x5b,0x2a,0x43,0x47,0xda,0x95,0x43,0x08,
  0xf3,0xef,0x2b,0x43,0x10,0xe2,0x94,0x43,0x6d,0x95,0x2c,0x43,0xae,0xc3,0x92,0x43,0x68,0xa6,0x2b,0x43,
  0x47,0xc2,0x91,0x43,0x09,0x06,0x36,0xc1,0x31,0x43,0x2c,0x58,0x94,0x43,0x08,0x8c,0x1e,0x33,0x43,0x31,
  0x3b,0x93,0x43,0x79,0x7a,0x33,0x43,0xff,0x25,0x91,0x43,0xd9,0x9d,0x32,0x43,0xc1,0x5b,0x90,0x43,0x09,
  0x06,0x25,0x35,0x36,0x43,0x31,0x3b,0x93,0x43,0x08,0x3f,0xb7,0x37,0x43,0xc1,0x67,0x92,0x43,0xe0,0x93,
  0x38,0x43,0xae,0xb7,0x90,0x43,0x7e,0x81,0x38,0x43,0x0d,0xdb,0x8f,0x43,0x09,0x06,0xb5,0x85,0x3b,0x43,
  0xe4,0xaf,0x91,0x43,0x08,0xcf,0x07,0x3d,0x43,0x9d,0x13,0x91,0x43,0xbc,0x63,0x3d,0x43,0x47,0xb6,0x8f,
  0x43,0xe5,0x9a,0x3d,0x43,0x74,0xd0,0x8e,0x43,0x09,0x06,0xae,0xc6,0x42,0x43,0xa4,0xd9,0x8e,0x43,0x08,
  0xca,0x48,0x44,0x43,0xfa,0x2a,0x8e,0x43,0xa2,0x11,0x44,0x43,0x9d,0xfb,0x8c,0x43,0x55,0x92,0x44,0x43,
  0x0d,0xc3,0x8b,0x43,0x09,0x06,0x39,0x10,0xc3,0x43,0x34,0x36,0x96,0x43,0x08,0x92,0x44,0xc1,0x43,0xe4,
  0xc7,0x95,0x43,0x6f,0xf0,0xbf,0x43,0x4b,0xbd,0x94,0x43,0x47,0xb9,0xbf,0x43,0x0b,0xf3,0x93,0x43,0x09,
  0x06,0x8f,0x49,0xbe,0x43,0xb7,0xad,0x96,0x43,0x08,0x11,0xb5,0xbc,0x43,0x77,0xe3,0x95,0x43,0x9c,0xf2,
  0xba,0x43,0xfa,0x4e,0x94,0x43,0xae,0x96,0xba,0x43,0x31,0x3b,0x93,0x43,0x09,0x06,0xdb,0xb0,0xb9,0x43,
  0x10,0xee,0x96,0x43,0x08,0x42,0xa6,0xb8,0x43,0xc8,0x51,0x96,0x43,0x50,0x5b,0xb7,0x43,0x19,0xb4,0x94,
  0x43,0xf7,0x1a,0xb7,0x43,0x58,0x72,0x93,0x43,0x09,0x06,0xf2,0x2b,0xb6,0x43,0x10,0xee,0x96,0x43,0x08,
  0x9d,0xce,0xb4,0x43,0x04,0x2d,0x96,0x43,0xed,0x30,0xb3,0x43,0x2c,0x58,0x94,0x43,0xce,0xcb,0xb2,0x43,
  0xd6,0xfa,0x92,0x43,0x09,0x06,0x5a,0x09,0xb1,0x43,0x19,0xc0,0x96,0x43,0x08,0x6c,0xad,0xb0,0x43,0x77,
  0xe3,0x95,0x43,0x7e,0x51,0xb0,0x43,0xc0,0x73,0x94,0x43,0xd8,0x91,0xb0,0x43,0x1e,0x97,0x93,0x43,0x09,
  0x06,0x48,0x4d,0xad,0x43,0xbe,0x7f,0x96,0x43,0x08,0x95,0xcc,0xac,0x43,0x58,0x7e,0x95,0x43,0x4d,0x30,
  0xac,0x43,0x80,0xa9,0x93,0x43,0xd8,0x79,0xac,0x43,0xd6,0xfa,0x92,0x43,0x09,0x06,0x90,0xd1,0xa9,0x43,
  0x14,0xd1,0x95,0x43,0x08,0x83,0x10,0xa9,0x43,0xb7,0xa1,0x94,0x43,0x3b,0x74,0xa8,0x43,0xf1,0x70,0x92,
  0x43,0x29,0xd0,0xa8,0x43,0x1e,0x8b,0x91,0x43,0x09,0x06,0x5a,0xcd,0xa6,0x43,0x8a,0x87,0x95,0x43,0x08,
  0x1c,0x03,0xa6,0x43,0x23,0x86,0x94,0x43,0x5f,0xb0,0xa5,0x43,0xc1,0x67,0x92,0x43,0xe1,0x27,0xa6,0x43,
  0x8a,0x6f,0x91,0x43,0x09,0x06,0xd4,0x5a,0xa3,0x43,0x2c,0x58,0x94,0x43,0x08,0x29,0xac,0xa2,0x43,0x31,
  0x3b,0x93,0x43,0x32,0x7e,0xa2,0x43,0xff,0x25,0x91,0x43,0x83,0xec,0xa2,0x43,0x8e,0x52,0x90,0x43,0x09,
  0x06,0xf8,0x96,0xa0,0x43,0x1e,0x97,0x93,0x43,0x08,0xeb,0xd5,0x9f,0x43,0x7b,0xba,0x92,0x43,0x99,0x67,
  0x9f,0x43,0x9d,0x13,0x91,0x43,0x99,0x67,0x9f,0x43,0xfa,0x36,0x90,0x43,0x09,0x06,0xeb,0xc9,0x9d,0x43,
  0xc8,0x39,0x92,0x43,0x08,0xde,0x08,0x9d,0x43,0xb2,0xa6,0x91,0x43,0xe6,0xda,0x9c,0x43,0x2c,0x40,0x90,
  0x43,0x52,0xbf,0x9c,0x43,0x5a,0x5a,0x8f,0x43,0x09,0x06,0x37,0x3d,0x9b,0x43,0x85,0x80,0x90,0x43,0x08,
  0x2a,0x7c,0x9a,0x43,0xdb,0xd1,0x8f,0x43,0xf0,0xa0,0x9a,0x43,0x7d,0xa2,0x8e,0x43,0x65,0x57,0x9a,0x43,
  0xee,0x69,0x8d,0x43,0x09,0x02,0x04,0x06,0x2a,0xf4,0x2e,0x42,0x04,0x21,0x94,0x43,0x08,0x0d,0x8a,0x31,
  0x42,0x9f,0x0e,0x94,0x43,0xf3,0x1f,0x34,0x42,0x3d,0xfc,0x93,0x43,0x63,0xff,0x36,0x42,0xa9,0xe0,0x93,
  0x43,0x08,0xb5,0x34,0x5d,0x42,0x0b,0xf3,0x93,0x43,0x6d,0xa4,0x5e,0x42,0x03,0x39,0x98,0x43,0xe7,0x31,
  0x5b,0x42,0x93,0x89,0x9d,0x43,0x08,0x02,0x9c,0x58,0x42,0xd4,0x5a,0xa3,0x43,0x38,0x70,0x53,0x42,0x14,
  0x49,0xaa,0x43,0xf8,0xed,0x5e,0x42,0x83,0x28,0xad,0x43,0x08,0xea,0x68,0x68,0x42,0x20,0x22,0xaf,0x43,
  0x12,0xb8,0x6c,0x42,0xb5,0x49,0xb1,0x43,0x2a,0x4b,0x6d,0x42,0x0d,0x96,0xb3,0x43,0x07,0x2a,0x4b,0x6d,
  0x42,0xc6,0x05,0xb5,0x43,0x08,0x87,0x6e,0x6c,0x42,0x68,0xee,0xb7,0x43,0x1c,0x66,0x66,0x42,0x31,0x0e,
  0xbb,0x43,0x57,0x11,0x5e,0x42,0x8f,0x49,0xbe,0x43,0x08,0x66,0x96,0x54,0x42,0xb9,0x5c,0xb8,0x43,0x2c,
  0x2b,0x3c,0x42,0x68,0xd6,0xb3,0x43,0x2a,0xf4,0x2e,0x42,0x6d,0xad,0xb0,0x43,0x07,0x2a,0xf4,0x2e,0x42,
  0x61,0xa4,0xa3,0x43,0x08,0x55,0x1a,0x30,0x42,0xf0,0xd0,0xa2,0x43,0xf8,0xf6,0x30,0x42,0xb2,0x06,0xa2,
  0x43,0x98,0xd3,0x31,0x42,0xd6,0x4e,0xa1,0x43,0x08,0x1c,0x6f,0x38,0x42,0x2a,0x94,0x9e,0x43,0xc1,0x22,
  0x36,0x42,0xf5,0x9b,0x9d,0x43,0x2a,0xf4,0x2e,0x42,0x6a,0x52,0x9d,0x43,0x07,0x2a,0xf4,0x2e,0x42,0x57,
  0xa2,0x9b,0x43,0x08,0xab,0x8f,0x35,0x42,0x8a,0xab,0x9b,0x43,0xe9,0x71,0x3a,0x42,0xb2,0xe2,0x9b,0x43,
  0xb7,0x74,0x3c,0x42,0x34,0x5a,0x9c,0x43,0x08,0x23,0x7d,0x42,0x42,0x0b,0x2f,0x9e,0x43,0xe5,0x9a,0x3d,
  0x42,0x38,0x6d,0xa3,0x43,0x36,0xd9,0x35,0x42,0xf3,0xd7,0xa7,0x43,0x08,0x12,0x61,0x2e,0x42,0xb0,0x42,
  0xac,0x43,0x63,0xff,0x36,0x42,0xdd,0x74,0xaf,0x43,0x1e,0xa6,0x45,0x42,0x44,0x82,0xb2,0x43,0x08,0x74,
  0x1b,0x4b,0x42,0x79,0x7a,0xb3,0x43,0x10,0x21,0x4f,0x42,0x2a,0x18,0xb5,0x43,0xdb,0x4c,0x54,0x42,0x91,
  0x19,0xb6,0x43,0x08,0xee,0x3f,0x65,0x42,0x5f,0x28,0xba,0x43,0xa7,0xaf,0x66,0x42,0xb9,0x50,0xb6,0x43,
  0x14,0x58,0x5c,0x42,0xca,0xdc,0xb1,0x43,0x08,0x2c,0x8b,0x4c,0x42,0x4e,0x30,0xac,0x43,0x19,0xcf,0x48,
  0x42,0x2a,0xd0,0xa8,0x43,0xbc,0xab,0x49,0x42,0xa9,0x4c,0xa6,0x43,0x08,0x61,0x5f,0x47,0x42,0xfa,0xa2,
  0xa2,0x43,0xa7,0xaf,0x66,0x42,0x85,0x98,0x94,0x43,0x2a,0xf4,0x2e,0x42,0xc3,0x62,0x95,0x43,0x07,0x2a,
  0xf4,0x2e,0x42,0x04,0x21,0x94,0x43,0x09,0x06,0xd0,0xfe,0xea,0x41,0x9f,0x0e,0x94,0x43,0x08,0xdc,0xe3,
  0xf1,0x41,0xe9,0x9e,0x92,0x43,0xd2,0xe7,0x0b,0x42,0xd6,0x06,0x95,0x43,0x2a,0xf4,0x2e,0x42,0x04,0x21,
  0x94,0x43,0x07,0x2a,0xf4,0x2e,0x42,0xc3,0x62,0x95,0x43,0x08,0x87,0x17,0x2e,0x42,0xc3,0x62,0x95,0x43,
  0xe7,0x3a,0x2d,0x42,0xf5,0x6b,0x95,0x43,0x44,0x5e,0x2c,0x42,0xf5,0x6b,0x95,0x43,0x08,0xd1,0x47,0x1c,
  0x42,0x19,0xc0,0x96,0x43,0x66,0xdf,0x05,0x42,0x38,0x19,0x95,0x43,0x12,0x6a,0x00,0x42,0xb2,0xbe,0x95,
  0x43,0x08,0xbb,0x6b,0xea,0x41,0xd6,0x12,0x97,0x43,0x2d,0x82,0xfa,0x41,0x61,0x74,0x9b,0x43,0x7e,0x72,
  0x06,0x42,0x8a,0xab,0x9b,0x43,0x08,0xc8,0x39,0x12,0x42,0x4e,0xd0,0x9b,0x43,0x53,0xe3,0x22,0x42,0xc3,
  0x86,0x9b,0x43,0x2a,0xf4,0x2e,0x42,0x57,0xa2,0x9b,0x43,0x07,0x2a,0xf4,0x2e,0x42,0x6a,0x52,0x9d,0x43,
  0x08,0x01,0xa5,0x2a,0x42,0xa4,0x2d,0x9d,0x43,0x96,0x9c,0x24,0x42,0x06,0x40,0x9d,0x43,0x8a,0xb7,0x1d,
  0x42,0x9a,0x5b,0x9d,0x43,0x08,0x6b,0x16,0x13,0x42,0xcd,0x64,0x9d,0x43,0x42,0xc7,0x0e,0x42,0x9a,0x5b,
  0x9d,0x43,0x23,0x26,0x04,0x42,0xcd,0x64,0x9d,0x43,0x08,0xe6,0x91,0xeb,0x41,0x38,0x49,0x9d,0x43,0x73,
  0x7b,0xdb,0x41,0xf5,0x83,0x99,0x43,0x7f,0x60,0xe2,0x41,0x0b,0x0b,0x98,0x43,0x08,0x7f,0x60,0xe2,0x41,
  0xec,0x99,0x95,0x43,0xe3,0x5a,0xde,0x41,0xbe,0x7f,0x96,0x43,0xd0,0xfe,0xea,0x41,0x9f,0x0e,0x94,0x43,
  0x07,0xd0,0xfe,0xea,0x41,0x9f,0x0e,0x94,0x43,0x09,0x06,0x2a,0xf4,0x2e,0x42,0x6d,0xad,0xb0,0x43,0x08,
  0xd4,0x7e,0x29,0x42,0xab,0x6b,0xaf,0x43,0x4e,0x0c,0x26,0x42,0x44,0x6a,0xae,0x43,0x38,0x79,0x25,0x42,
  0xd4,0x96,0xad,0x43,0x08,0x25,0xbd,0x21,0x42,0xe2,0x4b,0xac,0x43,0x49,0x35,0x29,0x42,0x9a,0x97,0xa7,
  0x43,0x2a,0xf4,0x2e,0x42,0x61,0xa4,0xa3,0x43,0x07,0x2a,0xf4,0x2e,0x42,0x6d,0xad,0xb0,0x43,0x09,0x06,
  0x1d,0xe5,0x7f,0x43,0x87,0x4a,0xe6,0x43,0x08,0x86,0x20,0x80,0x43,0x57,0x41,0xe6,0x43,0x7d,0x4e,0x80,
  0x43,0x25,0x38,0xe6,0x43,0xa5,0x85,0x80,0x43,0xf3,0x2e,0xe6,0x43,0x08,0x35,0xca,0x83,0x43,0xd4,0xc9,
  0xe5,0x43,0x9c,0xd7,0x86,0x43,0x44,0x91,0xe4,0x43,0xd5,0xca,0x8a,0x43,0x91,0x1c,0xe6,0x43,0x08,0x53,
  0x5f,0x8c,0x43,0xf8,0x1d,0xe7,0x43,0x2f,0x17,0x8d,0x43,0x4e,0x7b,0xe8,0x43,0x92,0x29,0x8d,0x43,0x2f,
  0x22,0xea,0x43,0x07,0x92,0x29,0x8d,0x43,0x44,0xb5,0xea,0x43,0x08,0xfe,0x0d,0x8d,0x43,0x2a,0x4b,0xed,
  0x43,0xe3,0x8b,0x8b,0x43,0x55,0x7d,0xf0,0x43,0xec,0x51,0x89,0x43,0x72,0x0b,0xf4,0x43,0x08,0xcd,0xd4,
  0x84,0x43,0x9d,0x55,0xfb,0x43,0xc9,0xe5,0x83,0x43,0x74,0x1e,0xfb,0x43,0x73,0x94,0x84,0x43,0x5a,0x90,
  0xf7,0x43,0x08,0xe8,0x62,0x88,0x43,0xfd,0x30,0xee,0x43,0x39,0xc5,0x86,0x43,0xdd,0xbf,0xeb,0x43,0x35,
  0xbe,0x81,0x43,0x40,0xde,0xed,0x43,0x08,0x4f,0x34,0x81,0x43,0x36,0x0c,0xee,0x43,0x08,0x98,0x80,0x43,
  0xfd,0x30,0xee,0x43,0x1d,0xe5,0x7f,0x43,0x91,0x4c,0xee,0x43,0x07,0x1d,0xe5,0x7f,0x43,0x91,0x40,0xec,
  0x43,0x08,0x35,0xbe,0x81,0x43,0x06,0xf7,0xeb,0x43,0x15,0x65,0x83,0x43,0x49,0xa4,0xeb,0x43,0x1e,0x43,
  0x85,0x43,0xbe,0x5a,0xeb,0x43,0x08,0xae,0x93,0x8a,0x43,0xfd,0x18,0xea,0x43,0x42,0x97,0x86,0x43,0x5f,
  0x67,0xf4,0x43,0xa9,0x98,0x87,0x43,0xd4,0x1d,0xf4,0x43,0x08,0x5c,0x25,0x8a,0x43,0xcf,0x16,0xef,0x43,
  0x46,0xaa,0x8d,0x43,0x5a,0x3c,0xe9,0x43,0x19,0x6c,0x88,0x43,0x53,0x5e,0xe7,0x43,0x08,0xc4,0x02,0x85,
  0x43,0x96,0x0b,0xe7,0x43,0x85,0x2c,0x82,0x43,0x83,0x67,0xe7,0x43,0x1d,0xe5,0x7f,0x43,0x72,0xc3,0xe7,
  0x43,0x07,0x1d,0xe5,0x7f,0x43,0x87,0x4a,0xe6,0x43,0x09,0x06,0xfd,0x24,0x6c,0x43,0xd9,0x94,0xe0,0x43,
  0x08,0xfa,0x6c,0x78,0x43,0xd1,0xc2,0xe0,0x43,0x25,0x5c,0x6c,0x43,0x25,0x44,0xe8,0x43,0x1d,0xe5,0x7f,
  0x43,0x87,0x4a,0xe6,0x43,0x07,0x1d,0xe5,0x7f,0x43,0x72,0xc3,0xe7,0x43,0x08,0xa6,0x27,0x7b,0x43,0x91,
  0x28,0xe8,0x43,0xbc,0xa2,0x77,0x43,0xb0,0x8d,0xe8,0x43,0xc6,0x68,0x75,0x43,0x57,0x4d,0xe8,0x43,0x08,
  0xe0,0xd2,0x72,0x43,0xab,0x9e,0xe7,0x43,0x50,0x9a,0x71,0x43,0x2a,0x27,0xe7,0x43,0xea,0x98,0x70,0x43,
  0x57,0x35,0xe4,0x43,0x08,0x94,0x3b,0x6f,0x43,0x14,0x7c,0xe2,0x43,0xff,0x13,0x6d,0x43,0x06,0xbb,0xe1,
  0x43,0xcf,0xfe,0x6a,0x43,0x06,0xbb,0xe1,0x43,0x08,0x44,0x9d,0x66,0x43,0x77,0x8e,0xe2,0x43,0x3b,0xef,
  0x6c,0x43,0x91,0x10,0xe4,0x43,0xfd,0x24,0x6c,0x43,0xb0,0x81,0xe6,0x43,0x08,0x96,0x23,0x6b,0x43,0xee,
  0x57,0xe9,0x43,0xca,0x0f,0x6a,0x43,0x5f,0x37,0xec,0x43,0x55,0x71,0x6e,0x43,0x9f,0x01,0xed,0x43,0x08,
  0xdb,0xfb,0x75,0x43,0x3b,0xef,0xec,0x43,0x09,0x3a,0x7b,0x43,0xb0,0xa5,0xec,0x43,0x1d,0xe5,0x7f,0x43,
  0x91,0x40,0xec,0x43,0x07,0x1d,0xe5,0x7f,0x43,0x91,0x4c,0xee,0x43,0x08,0xa9,0x16,0x7c,0x43,0xb0,0xb1,
  0xee,0x43,0x47,0xec,0x77,0x43,0xd9,0xe8,0xee,0x43,0x1e,0x9d,0x73,0x43,0xcf,0x16,0xef,0x43,0x08,0x0e,
  0xc9,0x6b,0x43,0xee,0x7b,0xef,0x43,0x7e,0x90,0x6a,0x43,0xfd,0x30,0xee,0x43,0x01,0xfc,0x68,0x43,0x4e,
  0x93,0xec,0x43,0x08,0x31,0xf9,0x66,0x43,0x4e,0x87,0xea,0x43,0x31,0x11,0x6b,0x43,0xd4,0xd5,0xe7,0x43,
  0xd9,0xc4,0x68,0x43,0xd4,0xc9,0xe5,0x43,0x08,0xe5,0x79,0x67,0x43,0x77,0x9a,0xe4,0x43,0x44,0x9d,0x66,
  0x43,0xab,0x86,0xe3,0x43,0x7e,0x78,0x66,0x43,0x0b,0xaa,0xe2,0x43,0x07,0x7e,0x78,0x66,0x43,0x57,0x29,
  0xe2,0x43,0x08,0xa7,0xaf,0x66,0x43,0xbe,0x1e,0xe1,0x43,0x87,0x56,0x68,0x43,0x77,0x82,0xe0,0x43,0xfd,
  0x24,0x6c,0x43,0xd9,0x94,0xe0,0x43,0x09,0x06,0xc4,0x41,0xbf,0x43,0x85,0xc0,0x72,0x42,0x08,0x73,0xdf,
  0xc0,0x43,0xf4,0x76,0x72,0x42,0x97,0x33,0xc2,0x43,0x85,0xc0,0x72,0x42,0xb2,0xb5,0xc3,0x43,0x64,0x56,
  0x75,0x42,0x08,0x03,0x24,0xc4,0x43,0x5e,0x7f,0x78,0x42,0xfa,0x51,0xc4,0x43,0x01,0x85,0x7c,0x42,0x5c,
  0x64,0xc4,0x43,0xa0,0xb3,0x80,0x42,0x07,0x5c,0x64,0xc4,0x43,0x10,0x93,0x83,0x42,0x08,0xc8,0x48,0xc4,
  0x43,0x1c,0x78,0x8a,0x42,0x27,0x6c,0xc3,0x43,0xaf,0xcf,0x94,0x42,0x23,0x7d,0xc2,0x43,0x99,0x9c,0xa4,
  0x42,0x08,0x3d,0xe7,0xbf,0x43,0xfb,0xfd,0xb5,0x42,0xb3,0x9d,0xbf,0x43,0x88,0x17,0xae,0x42,0xc4,0x41,
  0xbf,0x43,0x69,0x76,0xa3,0x42,0x07,0xc4,0x41,0xbf,0x43,0xac,0xc8,0x8f,0x42,0x08,0x4f,0x8b,0xbf,0x43,
  0xed,0x81,0x91,0x42,0xe4,0xa6,0xbf,0x43,0x5d,0x61,0x94,0x42,0xfa,0x39,0xc0,0x43,0x3b,0x49,0x9d,0x42,
  0x08,0x2b,0x43,0xc0,0x43,0x28,0xed,0xa9,0x42,0x61,0x3b,0xc1,0x43,0x00,0x9e,0xa5,0x42,0xe4,0xb2,0xc1,
  0x43,0x5d,0x91,0x9c,0x42,0x08,0x78,0xce,0xc1,0x43,0xfd,0x36,0x90,0x42,0x22,0x89,0xc4,0x43,0x81,0x72,
  0x86,0x42,0xae,0xc6,0xc2,0x43,0xa0,0xb3,0x80,0x42,0x08,0x54,0x86,0xc2,0x43,0x58,0xd1,0x7e,0x42,0x30,
  0x32,0xc1,0x43,0xce,0x5e,0x7b,0x42,0xc4,0x41,0xbf,0x43,0xe8,0xf1,0x7b,0x42,0x07,0xc4,0x41,0xbf,0x43,
  0x85,0xc0,0x72,0x42,0x09,0x06,0xf6,0x32,0xbb,0x43,0x40,0xa7,0x60,0x42,0x08,0x35,0xfd,0xbb,0x43,0xa4,
  0xa1,0x5c,0x42,0x5e,0x34,0xbc,0x43,0x9d,0x2a,0x70,0x42,0x5e,0x40,0xbe,0x43,0x0e,0x0a,0x73,0x42,0x08,
  0x4c,0x9c,0xbe,0x43,0x0e,0x0a,0x73,0x42,0x08,0xef,0xbe,0x43,0x0e,0x0a,0x73,0x42,0xc4,0x41,0xbf,0x43,
  0x85,0xc0,0x72,0x42,0x07,0xc4,0x41,0xbf,0x43,0xe8,0xf1,0x7b,0x42,0x08,0xcd,0x13,0xbf,0x43,0xe8,0xf1,
  0x7b,0x42,0xd6,0xe5,0xbe,0x43,0x71,0x3b,0x7c,0x42,0xdf,0xb7,0xbe,0x43,0x71,0x3b,0x7c,0x42,0x08,0x08,
  0xe3,0xbc,0x43,0xa4,0x61,0x7d,0x42,0x28,0x3c,0xbb,0x43,0x91,0x45,0x69,0x42,0x28,0x3c,0xbb,0x43,0x58,
  0x71,0x6e,0x42,0x08,0xce,0xfb,0xba,0x43,0xd5,0x35,0x78,0x42,0x59,0x45,0xbb,0x43,0x58,0x23,0x82,0x42,
  0xa1,0xe1,0xbb,0x43,0xd7,0xbe,0x88,0x42,0x08,0xc9,0x18,0xbc,0x43,0xaf,0x9f,0x8c,0x42,0x1e,0x76,0xbd,
  0x43,0x51,0x7c,0x8d,0x42,0xd6,0xe5,0xbe,0x43,0xf4,0x58,0x8e,0x42,0x08,0x9c,0x0a,0xbf,0x43,0x45,0xc7,
  0x8e,0x42,0x30,0x26,0xbf,0x43,0x96,0x35,0x8f,0x42,0xc4,0x41,0xbf,0x43,0xac,0xc8,0x8f,0x42,0x07,0xc4,
  0x41,0xbf,0x43,0x69,0x76,0xa3,0x42,0x08,0x08,0xef,0xbe,0x43,0xb1,0xd6,0x99,0x42,0xe8,0x89,0xbe,0x43,
  0xde,0xc5,0x8d,0x42,0xc0,0x46,0xbc,0x43,0xc2,0x5b,0x90,0x42,0x08,0x9c,0xf2,0xba,0x43,0x86,0x80,0x90,
  0x42,0xf2,0x43,0xba,0x43,0xe8,0x73,0x87,0x42,0x8f,0x31,0xba,0x43,0xb6,0xf4,0x7d,0x42,0x07,0x8f,0x31,
  0xba,0x43,0x21,0xc6,0x76,0x42,0x08,0xc0,0x3a,0xba,0x43,0x5f,0x48,0x6b,0x42,0xae,0x96,0xba,0x43,0xe3,
  0x83,0x61,0x42,0xf6,0x32,0xbb,0x43,0x40,0xa7,0x60,0x42,0x09,0x06,0xea,0x74,0xea,0x43,0x61,0x44,0x93,
  0x43,0x08,0x24,0x5c,0xec,0x43,0x31,0x3b,0x93,0x43,0xfb,0x30,0xee,0x43,0x93,0x4d,0x93,0x43,0x0d,0xe1,
  0xef,0x43,0x80,0xa9,0x93,0x43,0x08,0x8f,0x58,0xf0,0x43,0xd1,0x17,0x94,0x43,0xb7,0x8f,0xf0,0x43,0x10,
  0xe2,0x94,0x43,0xea,0x98,0xf0,0x43,0xa9,0xec,0x95,0x43,0x07,0xea,0x98,0xf0,0x43,0x38,0x25,0x97,0x43,
  0x08,0x23,0x74,0xf0,0x43,0x9f,0x32,0x9a,0x43,0x5a,0x60,0xef,0x43,0x53,0xcb,0x9e,0x43,0x2d,0x3a,0xee,
  0x43,0xfd,0x91,0xa3,0x43,0x08,0xa2,0xf0,0xed,0x43,0xdd,0x38,0xa5,0x43,0x17,0xa7,0xed,0x43,0xbe,0xdf,
  0xa6,0x43,0x5a,0x54,0xed,0x43,0x9f,0x86,0xa8,0x43,0x08,0xfc,0x24,0xec,0x43,0xca,0xc4,0xad,0x43,0x48,
  0xa4,0xeb,0x43,0x40,0x6f,0xab,0x43,0x28,0x3f,0xeb,0x43,0x1c,0x0f,0xa8,0x43,0x08,0x1f,0x6d,0xeb,0x43,
  0x72,0x48,0xa3,0x43,0x67,0x09,0xec,0x43,0xd1,0x53,0x9e,0x43,0xea,0x74,0xea,0x43,0x1e,0xc7,0x9b,0x43,
  0x07,0xea,0x74,0xea,0x43,0x8a,0x9f,0x99,0x43,0x08,0x7e,0x90,0xea,0x43,0x8a,0x9f,0x99,0x43,0x12,0xac,
  0xea,0x43,0xbc,0xa8,0x99,0x43,0xa7,0xc7,0xea,0x43,0xbc,0xa8,0x99,0x43,0x08,0x51,0x76,0xeb,0x43,0x9f,
  0x32,0x9a,0x43,0x5e,0x37,0xec,0x43,0x49,0xed,0x9c,0x43,0xb0,0xa5,0xec,0x43,0x2a,0xa0,0xa0,0x43,0x08,
  0x09,0xe6,0xec,0x43,0xd1,0x77,0xa4,0x43,0x28,0x4b,0xed,0x43,0x61,0xa4,0xa3,0x43,0xab,0xc2,0xed,0x43,
  0x8e,0xb2,0xa0,0x43,0x08,0x70,0xe7,0xed,0x43,0xde,0x08,0x9d,0x43,0x87,0x86,0xf0,0x43,0x2f,0x53,0x97,
  0x43,0x87,0x7a,0xee,0x43,0xec,0x99,0x95,0x43,0x08,0xca,0x27,0xee,0x43,0xff,0x3d,0x95,0x43,0x74,0xca,
  0xec,0x43,0x55,0x8f,0x94,0x43,0xea,0x74,0xea,0x43,0xe7,0xaa,0x94,0x43,0x07,0xea,0x74,0xea,0x43,0x61,
  0x44,0x93,0x43,0x09,0x06,0x05,0xd3,0xe5,0x43,0x19,0x9c,0x90,0x43,0x08,0x09,0xc2,0xe6,0x43,0xd1,0xff,
  0x8f,0x43,0x4d,0x6f,0xe6,0x43,0x74,0xe8,0x92,0x43,0x3b,0xd7,0xe8,0x43,0xc3,0x56,0x93,0x43,0x08,0x1f,
  0x61,0xe9,0x43,0x93,0x4d,0x93,0x43,0x05,0xeb,0xe9,0x43,0x93,0x4d,0x93,0x43,0xea,0x74,0xea,0x43,0x61,
  0x44,0x93,0x43,0x07,0xea,0x74,0xea,0x43,0xe7,0xaa,0x94,0x43,0x08,0x24,0x50,0xea,0x43,0xe7,0xaa,0x94,
  0x43,0x2d,0x22,0xea,0x43,0xe7,0xaa,0x94,0x43,0x36,0xf4,0xe9,0x43,0xe7,0xaa,0x94,0x43,0x08,0xa2,0xcc,
  0xe7,0x43,0xe0,0xd8,0x94,0x43,0xd4,0xc9,0xe5,0x43,0x19,0xa8,0x92,0x43,0xd4,0xc9,0xe5,0x43,0x27,0x69,
  0x93,0x43,0x08,0x17,0x77,0xe5,0x43,0xe0,0xd8,0x94,0x43,0x67,0xe5,0xe5,0x43,0x47,0xda,0x95,0x43,0x43,
  0x9d,0xe6,0x43,0xe2,0xd3,0x97,0x43,0x08,0x9d,0xdd,0xe6,0x43,0xad,0xe7,0x98,0x43,0x09,0xce,0xe8,0x43,
  0xff,0x55,0x99,0x43,0xea,0x74,0xea,0x43,0x8a,0x9f,0x99,0x43,0x07,0xea,0x74,0xea,0x43,0x1e,0xc7,0x9b,
  0x43,0x08,0x71,0xcf,0xe9,0x43,0x53,0xb3,0x9a,0x43,0xa7,0xbb,0xe8,0x43,0xdb,0x0d,0x9a,0x43,0xc6,0x14,
  0xe7,0x43,0xdb,0x0d,0x9a,0x43,0x08,0x48,0x80,0xe5,0x43,0xdb,0x0d,0x9a,0x43,0x0a,0xb6,0xe4,0x43,0xc3,
  0x6e,0x97,0x43,0x76,0x9a,0xe4,0x43,0x74,0xf4,0x94,0x43,0x07,0x76,0x9a,0xe4,0x43,0x79,0xd7,0x93,0x43,
  0x08,0xd8,0xac,0xe4,0x43,0x66,0x27,0x92,0x43,0x29,0x1b,0xe5,0x43,0xe0,0xc0,0x90,0x43,0x05,0xd3,0xe5,
  0x43,0x19,0x9c,0x90,0x43,0x09,0x06,0x1b,0x66,0xe6,0x42,0xe3,0xa3,0x8f,0x42,0x08,0x71,0x0b,0xf4,0x42,
  0x00,0x0e,0x8d,0x42,0x8c,0x0f,0x01,0x43,0x3e,0xc0,0x89,0x42,0xf3,0x28,0x06,0x43,0x48,0x9e,0x8b,0x42,
  0x08,0x15,0x89,0x09,0x43,0x00,0x0e,0x8d,0x42,0xe0,0x9c,0x0a,0x43,0xc1,0x8b,0x98,0x42,0xa6,0xc1,0x0a,
  0x43,0x02,0xa5,0xaa,0x42,0x07,0xa6,0xc1,0x0a,0x43,0xf9,0xf6,0xb0,0x42,0x08,0xa6,0xc1,0x0a,0x43,0x47,
  0x8e,0xb4,0x42,0x42,0xaf,0x0a,0x43,0x1f,0x6f,0xb8,0x42,0xe0,0x9c,0x0a,0x43,0xba,0x74,0xbc,0x42,0x08,
  0xa1,0xd2,0x09,0x43,0x40,0x47,0xd0,0x42,0x0d,0xab,0x07,0x43,0x91,0xb5,0xd0,0x42,0x3b,0xb9,0x04,0x43,
  0xec,0x71,0xba,0x42,0x08,0xe5,0x5b,0x03,0x43,0xe3,0x33,0xa8,0x42,0x63,0xd8,0x00,0x43,0xce,0x70,0x9f,
  0x42,0x1b,0x66,0xe6,0x42,0xae,0x2f,0xa5,0x42,0x07,0x1b,0x66,0xe6,0x42,0xa2,0x4a,0x9e,0x42,0x08,0xed,
  0x6f,0xed,0x42,0x73,0x24,0x9d,0x42,0xd8,0x0c,0xf5,0x42,0x99,0x6c,0x9c,0x42,0x27,0xab,0xfd,0x42,0xea,
  0xda,0x9c,0x42,0x08,0x36,0xca,0x03,0x43,0x2b,0x94,0x9e,0x42,0x68,0xc7,0x01,0x43,0x8f,0xbe,0xa2,0x42,
  0xfa,0x06,0x08,0x43,0x73,0xb4,0xb5,0x42,0x08,0x8e,0x2e,0x0a,0x43,0x1f,0x6f,0xb8,0x42,0x9d,0xe3,0x08,
  0x43,0xd7,0x1e,0x99,0x42,0x28,0x15,0x05,0x43,0x32,0x3b,0x93,0x42,0x08,0x63,0xf0,0x04,0x43,0x70,0xed,
  0x8f,0x42,0x71,0x0b,0xf4,0x42,0x32,0x3b,0x93,0x42,0x1b,0x66,0xe6,0x42,0x73,0xf4,0x94,0x42,0x07,0x1b,
  0x66,0xe6,0x42,0xe3,0xa3,0x8f,0x42,0x09,0x06,0x5e,0x28,0xba,0x42,0x35,0xe2,0x87,0x42,0x08,0x8e,0x55,
  0xc0,0x42,0xb8,0x4d,0x86,0x42,0x60,0xbf,0xd7,0x42,0x3e,0xf0,0x91,0x42,0x63,0xf6,0xe4,0x42,0x70,0xed,
  0x8f,0x42,0x08,0x7a,0x89,0xe5,0x42,0xac,0xc8,0x8f,0x42,0xcc,0xf7,0xe5,0x42,0xac,0xc8,0x8f,0x42,0x1b,
  0x66,0xe6,0x42,0xe3,0xa3,0x8f,0x42,0x07,0x1b,0x66,0xe6,0x42,0x73,0xf4,0x94,0x42,0x08,0x63,0xf6,0xe4,
  0x42,0x3b,0x19,0x95,0x42,0xe6,0x61,0xe3,0x42,0x00,0x3e,0x95,0x42,0xf4,0x16,0xe2,0x42,0xc4,0x62,0x95,
  0x42,0x08,0x6e,0x74,0xd6,0x42,0x15,0xd1,0x95,0x42,0x97,0x63,0xca,0x42,0xaf,0xcf,0x94,0x42,0xfb,0x2d,
  0xbe,0x42,0x86,0x80,0x90,0x42,0x08,0x97,0x03,0xba,0x42,0xce,0x10,0x8f,0x42,0x5e,0x28,0xba,0x42,0x3e,
  0xf0,0x91,0x42,0xf2,0x4f,0xbc,0x42,0x45,0xf7,0x96,0x42,0x08,0x27,0x54,0xbf,0x42,0x73,0x24,0x9d,0x42,
  0xa5,0xe8,0xc0,0x42,0x86,0xe0,0xa0,0x42,0xe4,0xca,0xc5,0x42,0xed,0x11,0xaa,0x42,0x08,0x54,0xaa,0xc8,
  0x42,0x86,0x40,0xb1,0x42,0x59,0x81,0xc5,0x42,0xa1,0x11,0xc4,0x42,0x3e,0xe7,0xbf,0x42,0xfb,0x8d,0xce,
  0x42,0x08,0xb4,0x6d,0xb7,0x42,0x30,0xc2,0xd9,0x42,0x46,0xf5,0xc9,0x42,0xdf,0x53,0xd9,0x42,0x38,0x40,
  0xcb,0x42,0x62,0x8f,0xcf,0x42,0x08,0x7d,0xf9,0xcc,0x42,0xec,0xa1,0xc2,0x42,0x07,0x43,0xcd,0x42,0x6c,
  0xdd,0xb8,0x42,0x2b,0x8b,0xcc,0x42,0x92,0xf5,0xaf,0x42,0x08,0xf9,0x8d,0xce,0x42,0x41,0x57,0xa7,0x42,
  0x5b,0xb8,0xd2,0x42,0xae,0x2f,0xa5,0x42,0x18,0x2f,0xd9,0x42,0x13,0x2a,0xa1,0x42,0x08,0x41,0x7e,0xdd,
  0x42,0xe3,0x03,0xa0,0x42,0x2e,0xf2,0xe1,0x42,0x7c,0x02,0x9f,0x42,0x1b,0x66,0xe6,0x42,0xa2,0x4a,0x9e,
  0x42,0x07,0x1b,0x66,0xe6,0x42,0xae,0x2f,0xa5,0x42,0x08,0x4d,0x63,0xe4,0x42,0x00,0x9e,0xa5,0x42,0xf4,
  0x16,0xe2,0x42,0x15,0x31,0xa6,0x42,0x99,0xca,0xdf,0x42,0x2b,0xc4,0xa6,0x42,0x08,0xc0,0x82,0xc6,0x42,
  0xc4,0xc2,0xa5,0x42,0x57,0xe1,0xd5,0x42,0x91,0xb5,0xd0,0x42,0x54,0xda,0xd0,0x42,0x97,0x93,0xd2,0x42,
  0x08,0x9c,0x3a,0xc7,0x42,0x17,0x58,0xdc,0x42,0x9c,0x0a,0xbf,0x42,0x6e,0xa4,0xde,0x42,0x90,0x25,0xb8,
  0x42,0xdf,0x53,0xd9,0x42,0x08,0x59,0x21,0xb5,0x42,0xf2,0xdf,0xd4,0x42,0x51,0x43,0xb3,0x42,0x91,0xb5,
  0xd0,0x42,0xc5,0x29,0xbb,0x42,0x0e,0x1a,0xca,0x42,0x08,0x65,0x36,0xc4,0x42,0xd0,0x07,0xbd,0x42,0x3e,
  0xe7,0xbf,0x42,0x37,0x09,0xbe,0x42,0x0c,0xea,0xc1,0x42,0xcd,0xd0,0xaf,0x42,0x08,0x2b,0x5b,0xc4,0x42,
  0x18,0x08,0xa3,0x42,0x67,0xa6,0xab,0x42,0x99,0x3c,0x94,0x42,0x5e,0x28,0xba,0x42,0x35,0xe2,0x87,0x42,
  0x09,];

private struct ThePath {
public:
  enum Command {
    Bounds, // always first, has 4 args (x0, y0, x1, y1)
    StrokeMode,
    FillMode,
    StrokeFillMode,
    NormalStroke,
    ThinStroke,
    MoveTo,
    LineTo,
    CubicTo, // cubic bezier
    EndPath,
  }

public:
  const(ubyte)[] path;
  uint ppos;

public:
  this (const(void)[] apath) pure nothrow @trusted @nogc {
    path = cast(const(ubyte)[])apath;
  }

  @property bool empty () const pure nothrow @safe @nogc { pragma(inline, true); return (ppos >= path.length); }

  Command getCommand () nothrow @trusted @nogc {
    pragma(inline, true);
    if (ppos >= cast(uint)path.length) assert(0, "invalid path");
    return cast(Command)(path.ptr[ppos++]);
  }

  // number of (x,y) pairs for this command
  static int argCount (in Command cmd) nothrow @safe @nogc {
    version(aliced) pragma(inline, true);
         if (cmd == Command.Bounds) return 2;
    else if (cmd == Command.MoveTo || cmd == Command.LineTo) return 1;
    else if (cmd == Command.CubicTo) return 3;
    else return 0;
  }

  void skipArgs (int argc) nothrow @trusted @nogc {
    pragma(inline, true);
    ppos += cast(uint)(float.sizeof*2*argc);
  }

  float getFloat () nothrow @trusted @nogc {
    pragma(inline, true);
    if (ppos >= cast(uint)path.length || cast(uint)path.length-ppos < float.sizeof) assert(0, "invalid path");
    version(LittleEndian) {
      float res = *cast(const(float)*)(&path.ptr[ppos]);
      ppos += cast(uint)float.sizeof;
      return res;
    } else {
      static assert(float.sizeof == 4);
      uint xp = path.ptr[ppos]|(path.ptr[ppos+1]<<8)|(path.ptr[ppos+2]<<16)|(path.ptr[ppos+3]<<24);
      ppos += cast(uint)float.sizeof;
      return *cast(const(float)*)(&xp);
    }
  }
}

// this will add baphomet's background path to the current NanoVega path, so you can fill it.
public void addBaphometBack (NVGContext nvg, float ofsx=0, float ofsy=0, float scalex=1, float scaley=1) nothrow @trusted @nogc {
  if (nvg is null) return;

  auto path = ThePath(baphometPath);

  float getScaledX () nothrow @trusted @nogc { pragma(inline, true); return (ofsx+path.getFloat()*scalex); }
  float getScaledY () nothrow @trusted @nogc { pragma(inline, true); return (ofsy+path.getFloat()*scaley); }

  bool inPath = false;
  while (!path.empty) {
    auto cmd = path.getCommand();
    switch (cmd) {
      case ThePath.Command.MoveTo:
        inPath = true;
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.moveTo(ex, ey);
        break;
      case ThePath.Command.LineTo:
        inPath = true;
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.lineTo(ex, ey);
        break;
      case ThePath.Command.CubicTo: // cubic bezier
        inPath = true;
        immutable float x1 = getScaledX();
        immutable float y1 = getScaledY();
        immutable float x2 = getScaledX();
        immutable float y2 = getScaledY();
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.bezierTo(x1, y1, x2, y2, ex, ey);
        break;
      case ThePath.Command.EndPath:
        if (inPath) return;
        break;
      default:
        path.skipArgs(path.argCount(cmd));
        break;
    }
  }
}

// this will add baphomet's pupil paths to the current NanoVega path, so you can fill it.
public void addBaphometPupils(bool left=true, bool right=true) (NVGContext nvg, float ofsx=0, float ofsy=0, float scalex=1, float scaley=1) nothrow @trusted @nogc {
  // pupils starts with "fill-and-stroke" mode
  if (nvg is null) return;

  auto path = ThePath(baphometPath);

  float getScaledX () nothrow @trusted @nogc { pragma(inline, true); return (ofsx+path.getFloat()*scalex); }
  float getScaledY () nothrow @trusted @nogc { pragma(inline, true); return (ofsy+path.getFloat()*scaley); }

  bool inPath = false;
  bool pupLeft = true;
  while (!path.empty) {
    auto cmd = path.getCommand();
    switch (cmd) {
      case ThePath.Command.StrokeFillMode: inPath = true; break;
      case ThePath.Command.MoveTo:
        if (!inPath) goto default;
        static if (!left) { if (pupLeft) goto default; }
        static if (!right) { if (!pupLeft) goto default; }
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.moveTo(ex, ey);
        break;
      case ThePath.Command.LineTo:
        if (!inPath) goto default;
        static if (!left) { if (pupLeft) goto default; }
        static if (!right) { if (!pupLeft) goto default; }
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.lineTo(ex, ey);
        break;
      case ThePath.Command.CubicTo: // cubic bezier
        if (!inPath) goto default;
        static if (!left) { if (pupLeft) goto default; }
        static if (!right) { if (!pupLeft) goto default; }
        immutable float x1 = getScaledX();
        immutable float y1 = getScaledY();
        immutable float x2 = getScaledX();
        immutable float y2 = getScaledY();
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.bezierTo(x1, y1, x2, y2, ex, ey);
        break;
      case ThePath.Command.EndPath:
        if (inPath) {
          if (pupLeft) pupLeft = false; else return;
        }
        break;
      default:
        path.skipArgs(path.argCount(cmd));
        break;
    }
  }
}

// mode: 'f' to allow fills; 's' to allow strokes; 'w' to allow stroke widths; 'c' to replace fills with strokes
public void renderBaphomet(string mode="fs") (NVGContext nvg, float ofsx=0, float ofsy=0, float scalex=1, float scaley=1) nothrow @trusted @nogc {
  template hasChar(char ch, string s) {
         static if (s.length == 0) enum hasChar = false;
    else static if (s[0] == ch) enum hasChar = true;
    else enum hasChar = hasChar!(ch, s[1..$]);
  }
  enum AllowStroke = hasChar!('s', mode);
  enum AllowFill = hasChar!('f', mode);
  enum AllowWidth = hasChar!('w', mode);
  enum Contour = hasChar!('c', mode);
  //static assert(AllowWidth || AllowFill);

  if (nvg is null) return;

  auto path = ThePath(baphometPath);

  float getScaledX () nothrow @trusted @nogc { pragma(inline, true); return (ofsx+path.getFloat()*scalex); }
  float getScaledY () nothrow @trusted @nogc { pragma(inline, true); return (ofsy+path.getFloat()*scaley); }

  int mode = 0;
  int sw = ThePath.Command.NormalStroke;
  nvg.beginPath();
  while (!path.empty) {
    auto cmd = path.getCommand();
    switch (cmd) {
      case ThePath.Command.StrokeMode: mode = ThePath.Command.StrokeMode; break;
      case ThePath.Command.FillMode: mode = ThePath.Command.FillMode; break;
      case ThePath.Command.StrokeFillMode: mode = ThePath.Command.StrokeFillMode; break;
      case ThePath.Command.NormalStroke: sw = ThePath.Command.NormalStroke; break;
      case ThePath.Command.ThinStroke: sw = ThePath.Command.ThinStroke; break;
      case ThePath.Command.MoveTo:
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.moveTo(ex, ey);
        break;
      case ThePath.Command.LineTo:
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.lineTo(ex, ey);
        break;
      case ThePath.Command.CubicTo: // cubic bezier
        immutable float x1 = getScaledX();
        immutable float y1 = getScaledY();
        immutable float x2 = getScaledX();
        immutable float y2 = getScaledY();
        immutable float ex = getScaledX();
        immutable float ey = getScaledY();
        nvg.bezierTo(x1, y1, x2, y2, ex, ey);
        break;
      case ThePath.Command.EndPath:
        if (mode == ThePath.Command.FillMode || mode == ThePath.Command.StrokeFillMode) {
          static if (AllowFill || Contour) {
            static if (Contour) {
              if (mode == ThePath.Command.FillMode) { nvg.strokeWidth = 1; nvg.stroke(); }
            } else {
              nvg.fill();
            }
          }
        }
        if (mode == ThePath.Command.StrokeMode || mode == ThePath.Command.StrokeFillMode) {
          static if (AllowStroke || Contour) {
            static if (AllowWidth) {
                   if (sw == ThePath.Command.NormalStroke) nvg.strokeWidth = 1;
              else if (sw == ThePath.Command.ThinStroke) nvg.strokeWidth = 0.5;
              else assert(0, "wtf?!");
            }
            nvg.stroke();
          }
        }
        nvg.newPath();
        break;
      default:
        path.skipArgs(path.argCount(cmd));
        break;
    }
  }
  nvg.newPath();
}
