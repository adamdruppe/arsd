/*
 * Copyright (c) 2013-14 Mikko Mononen memon@inside.org
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 * claim that you wrote the original software. If you use this software
 * in a product, an acknowledgment in the product documentation would be
 * appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 * misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 *
 * The SVG parser is based on Anti-Grain Geometry 2.4 SVG example
 * Copyright (C) 2002-2004 Maxim Shemanarev (McSeem) (http://www.antigrain.com/)
 *
 * Arc calculation code based on canvg (https://code.google.com/p/canvg/)
 *
 * Bounding box calculation based on http://blog.hackers-cafe.net/2009/06/how-to-calculate-bezier-curves-bounding.html
 *
 * Fork developement, feature integration and new bugs:
 * Ketmar // Invisible Vector <ketmar@ketmar.no-ip.org>
 * Contains code from various contributors.
 */
/**
  NanoVega.SVG is a simple stupid SVG parser. The output of the parser is a list of drawing commands.

  The library suits well for anything from rendering scalable icons in your editor application to prototyping a game.

  NanoVega.SVG supports a wide range of SVG features, but several are be missing. Among the most notable
  known missing features: `<use>`, `<text>`, `<def>` for shapes (it does work for gradients), `<script>` and animations. Note that `<clipPath>` is new and may be buggy (but anything in here may be buggy!) and the css support is fairly rudimentary.


  The shapes in the SVG images are transformed by the viewBox and converted to specified units.
  That is, you should get the same looking data as your designed in your favorite app.

  NanoVega.SVG can return the paths in few different units. For example if you want to render an image, you may choose
  to get the paths in pixels, or if you are feeding the data into a CNC-cutter, you may want to use millimeters.

  The units passed to NanoVega.SVG should be one of: 'px', 'pt', 'pc', 'mm', 'cm', 'in'.
  DPI (dots-per-inch) controls how the unit conversion is done.

  If you don't know or care about the units stuff, "px" and 96 should get you going.

  Example Usage:

  The easiest way to use it is to rasterize a SVG to a [arsd.color.TrueColorImage], and from there you can work with it
  same as any other memory image. For example, to turn a SVG into a png:

  ---
	import arsd.svg;
	import arsd.png;

	void main() {
	    // Load
	    NSVG* image = nsvgParseFromFile("test.svg", "px", 96);

	    int w = 200;
	    int h = 200;

	    NSVGrasterizer rast = nsvgCreateRasterizer();
	    // Allocate memory for image
	    auto img = new TrueColorImage(w, h);
	    // Rasterize
	    rasterize(rast, image, 0, 0, 1, img.imageData.bytes.ptr, w, h, w*4);

	    // Delete
	    image.kill();

	    writePng("test.png", img);


	}
  ---

  You can also dig into the individual commands of the svg without rasterizing it.
  Note that this is fairly complicated - svgs have a lot of settings, and even this
  example only does the basics.


  ---
import core.stdc.stdio;
import core.stdc.stdlib;
import arsd.svg;
import arsd.nanovega;

void main() {

    // we'll create a NanoVega window to display the image
    int w = 800;
    int h = 600;
    auto window = new NVGWindow(w, h, "SVG Test");

    // Load the file and can look at its info
    NSVG* image = nsvgParseFromFile("/home/me/svgs/arsd.svg", "px", 96);
    printf("size: %f x %f\n", image.width, image.height);

    // and then use the data when the window asks us to redraw
    // note that is is far from complete; svgs can have shapes, clips, caps, joins...
    // we're only doing the bare minimum here.
    window.redrawNVGScene = delegate(nvg) {

        // clear the screen with white so we can see the images on top of it
        nvg.beginPath();
        nvg.fillColor = NVGColor.white;
        nvg.rect(0, 0, window.width, window.height);
        nvg.fill();
        nvg.closePath();

        image.forEachShape((in ref NSVG.Shape shape) {
            if (!shape.visible) return;

            nvg.beginPath();

            // load the stroke
            nvg.strokeWidth = shape.strokeWidth;
            debug import std.stdio;

            final switch(shape.stroke.type) {
                case NSVG.PaintType.None:
                    // no stroke
                break;
                case NSVG.PaintType.Color:
                    with(shape.stroke)
                        nvg.strokeColor = NVGColor(r, g, b, a);
                    debug writefln("%08x", shape.fill.color);
                    break;
                case NSVG.PaintType.LinearGradient:
                case NSVG.PaintType.RadialGradient:
                    // FIXME: set the nvg stroke paint to shape.stroke.gradient
            }

            // load the fill
            final switch(shape.fill.type) {
                case NSVG.PaintType.None:
                    // no fill set
                break;
                case NSVG.PaintType.Color:
                    with(shape.fill)
                        nvg.fillColor = NVGColor(r, g, b, a);
                    break;
                case NSVG.PaintType.LinearGradient:
                case NSVG.PaintType.RadialGradient:
                    // FIXME: set the nvg fill paint to shape.stroke.gradient
            }

            shape.forEachPath((in ref NSVG.Path path) {
                // this will issue final `LineTo` for closed pathes
                path.forEachCommand!true(delegate (NSVG.Command cmd, const(float)[] args) nothrow @trusted @nogc {
                    debug writeln(cmd, args);
                    final switch (cmd) {
                        case NSVG.Command.MoveTo: nvg.moveTo(args); break;
                        case NSVG.Command.LineTo: nvg.lineTo(args); break;
                        case NSVG.Command.QuadTo: nvg.quadTo(args); break;
                        case NSVG.Command.BezierTo: nvg.bezierTo(args); break;
                    }
                });
            });

            nvg.fill();
            nvg.stroke();

            nvg.closePath();
        });
    };

    window.eventLoop(0);

    // Delete the image
    image.kill();
}
  ---

  TODO: maybe merge https://github.com/memononen/nanosvg/pull/94 too
 */
module arsd.svg;

alias NSVGclipPathIndex = ubyte;

private import core.stdc.math : fabs, fabsf, atan2f, acosf, cosf, sinf, tanf, sqrt, sqrtf, floorf, ceilf, fmodf;
//private import iv.vfs;

version(nanosvg_disable_vfs) {
  enum NanoSVGHasIVVFS = false;
} else {
  static if (is(typeof((){import iv.vfs;}))) {
    enum NanoSVGHasIVVFS = true;
    import iv.vfs;
  } else {
    enum NanoSVGHasIVVFS = false;
  }
}

version(aliced) {} else {
  private alias usize = size_t;
}

version = nanosvg_crappy_stylesheet_parser;
//version = nanosvg_debug_styles;
//version(rdmd) import iv.strex;

//version = nanosvg_use_beziers; // convert everything to beziers
//version = nanosvg_only_cubic_beziers; // convert everything to cubic beziers

///
public enum NSVGDefaults {
  CanvasWidth = 800,
  CanvasHeight = 600,
}


// ////////////////////////////////////////////////////////////////////////// //
public alias NSVGrasterizer = NSVGrasterizerS*; ///
public alias NSVGRasterizer = NSVGrasterizer; ///

///
struct NSVG {
  @disable this (this);

  ///
  enum Command : int {
    MoveTo, ///
    LineTo, ///
    QuadTo, ///
    BezierTo, /// cubic bezier
  }

  ///
  enum PaintType : ubyte {
    None, ///
    Color, ///
    LinearGradient, ///
    RadialGradient, ///
  }

  ///
  enum SpreadType : ubyte {
    Pad, ///
    Reflect, ///
    Repeat, ///
  }

  ///
  enum LineJoin : ubyte {
    Miter, ///
    Round, ///
    Bevel, ///
  }

  ///
  enum LineCap : ubyte {
    Butt, ///
    Round, ///
    Square, ///
  }

  ///
  enum FillRule : ubyte {
    NonZero, ///
    EvenOdd, ///
  }

  alias Flags = ubyte; ///
  enum : ubyte {
    Visible = 0x01, ///
  }

  ///
  static struct GradientStop {
    uint color; ///
    float offset; ///
  }

  ///
  static struct Gradient {
    float[6] xform; ///
    SpreadType spread; ///
    float fx, fy; ///
    int nstops; ///
    GradientStop[0] stops; ///
  }

  ///
  static struct Paint {
  pure nothrow @safe @nogc:
    @disable this (this);
    PaintType type; ///
    union {
      uint color; ///
      Gradient* gradient; ///
    }
    static uint rgb (ubyte r, ubyte g, ubyte b) { pragma(inline, true); return (r|(g<<8)|(b<<16)); } ///
    @property const {
      bool isNone () { pragma(inline, true); return (type == PaintType.None); } ///
      bool isColor () { pragma(inline, true); return (type == PaintType.Color); } ///
      // gradient types
      bool isLinear () { pragma(inline, true); return (type == PaintType.LinearGradient); } ///
      bool isRadial () { pragma(inline, true); return (type == PaintType.RadialGradient); } ///
      // color
      ubyte r () { pragma(inline, true); return color&0xff; } ///
      ubyte g () { pragma(inline, true); return (color>>8)&0xff; } ///
      ubyte b () { pragma(inline, true); return (color>>16)&0xff; } ///
      ubyte a () { pragma(inline, true); return (color>>24)&0xff; } ///
    }
  }

  ///
  static struct Path {
    @disable this (this);
    float* stream;   /// Command, args...; Cubic bezier points: x0,y0, [cpx1,cpx1,cpx2,cpy2,x1,y1], ...
    int nsflts;      /// Total number of floats in stream.
    bool closed;     /// Flag indicating if shapes should be treated as closed.
    float[4] bounds; /// Tight bounding box of the shape [minx,miny,maxx,maxy].
    NSVG.Path* next; /// Pointer to next path, or null if last element.

    ///
    @property bool empty () const pure nothrow @safe @nogc { pragma(inline, true); return (nsflts == 0); }

    ///
    float startX () const nothrow @trusted @nogc {
      pragma(inline, true);
      return (nsflts >= 3 && cast(Command)stream[0] == Command.MoveTo ? stream[1] : float.nan);
    }

    ///
    float startY () const nothrow @trusted @nogc {
      pragma(inline, true);
      return (nsflts >= 3 && cast(Command)stream[0] == Command.MoveTo ? stream[2] : float.nan);
    }

    ///
    bool startPoint (float* dx, float* dy) const nothrow @trusted @nogc {
      if (nsflts >= 3 && cast(Command)stream[0] == Command.MoveTo) {
        if (dx !is null) *dx = stream[1];
        if (dy !is null) *dy = stream[2];
        return true;
      } else {
        if (dx !is null) *dx = 0;
        if (dy !is null) *dy = 0;
        return false;
      }
    }

    ///
    int countCubics () const nothrow @trusted @nogc {
      if (nsflts < 3) return 0;
      int res = 0, argc;
      for (int pidx = 0; pidx+3 <= nsflts; ) {
        final switch (cast(Command)stream[pidx++]) {
          case Command.MoveTo: argc = 2; break;
          case Command.LineTo: argc = 2; ++res; break;
          case Command.QuadTo: argc = 4; ++res; break;
          case Command.BezierTo: argc = 6; ++res; break;
        }
        if (pidx+argc > nsflts) break; // just in case
        pidx += argc;
      }
      return res;
    }

    ///
    int countCommands(bool synthesizeCloseCommand=true) () const nothrow @trusted @nogc {
      if (nsflts < 3) return 0;
      int res = 0, argc;
      for (int pidx = 0; pidx+3 <= nsflts; ) {
        ++res;
        final switch (cast(Command)stream[pidx++]) {
          case Command.MoveTo: argc = 2; break;
          case Command.LineTo: argc = 2; break;
          case Command.QuadTo: argc = 4; break;
          case Command.BezierTo: argc = 6; break;
        }
        if (pidx+argc > nsflts) break; // just in case
        pidx += argc;
      }
      static if (synthesizeCloseCommand) { if (closed) ++res; }
      return res;
    }

    /// emits cubic beziers.
    /// if `withMoveTo` is `false`, issue 8-arg commands for cubic beziers (i.e. include starting point).
    /// if `withMoveTo` is `true`, issue 2-arg command for `moveTo`, and 6-arg command for cubic beziers.
    void asCubics(bool withMoveTo=false, DG) (scope DG dg) inout if (__traits(compiles, (){ DG xdg; float[] f; xdg(f); })) {
      if (dg is null) return;
      if (nsflts < 3) return;
      enum HasRes = __traits(compiles, (){ DG xdg; float[] f; bool res = xdg(f); });
      float cx = 0, cy = 0;
      float[8] cubic = void;

      void synthLine (in float cx, in float cy, in float x, in float y) nothrow @trusted @nogc {
        immutable float dx = x-cx;
        immutable float dy = y-cy;
        cubic.ptr[0] = cx;
        cubic.ptr[1] = cy;
        cubic.ptr[2] = cx+dx/3.0f;
        cubic.ptr[3] = cy+dy/3.0f;
        cubic.ptr[4] = x-dx/3.0f;
        cubic.ptr[5] = y-dy/3.0f;
        cubic.ptr[6] = x;
        cubic.ptr[7] = y;
      }

      void synthQuad (in float cx, in float cy, in float x1, in float y1, in float x2, in float y2) nothrow @trusted @nogc {
        immutable float cx1 = x1+2.0f/3.0f*(cx-x1);
        immutable float cy1 = y1+2.0f/3.0f*(cy-y1);
        immutable float cx2 = x2+2.0f/3.0f*(cx-x2);
        immutable float cy2 = y2+2.0f/3.0f*(cy-y2);
        cubic.ptr[0] = cx;
        cubic.ptr[1] = cy;
        cubic.ptr[2] = cx1;
        cubic.ptr[3] = cy2;
        cubic.ptr[4] = cx2;
        cubic.ptr[5] = cy2;
        cubic.ptr[6] = x2;
        cubic.ptr[7] = y2;
      }

      for (int pidx = 0; pidx+3 <= nsflts; ) {
        final switch (cast(Command)stream[pidx++]) {
          case Command.MoveTo:
            static if (withMoveTo) {
              static if (HasRes) { if (dg(stream[pidx+0..pidx+2])) return; } else { dg(stream[pidx+0..pidx+2]); }
            }
            cx = stream[pidx++];
            cy = stream[pidx++];
            continue;
          case Command.LineTo:
            synthLine(cx, cy, stream[pidx+0], stream[pidx+1]);
            pidx += 2;
            break;
          case Command.QuadTo:
            synthQuad(cx, cy, stream[pidx+0], stream[pidx+1], stream[pidx+2], stream[pidx+3]);
            pidx += 4;
            break;
          case Command.BezierTo:
            cubic.ptr[0] = cx;
            cubic.ptr[1] = cy;
            cubic.ptr[2..8] = stream[pidx..pidx+6];
            pidx += 6;
            break;
        }
        cx = cubic.ptr[6];
        cy = cubic.ptr[7];
        static if (withMoveTo) {
          static if (HasRes) { if (dg(cubic[2..8])) return; } else { dg(cubic[2..8]); }
        } else {
          static if (HasRes) { if (dg(cubic[])) return; } else { dg(cubic[]); }
        }
      }
    }

    /// if `synthesizeCloseCommand` is true, and the path is closed, this emits line to the first point.
    void forEachCommand(bool synthesizeCloseCommand=true, DG) (scope DG dg) inout
    if (__traits(compiles, (){ DG xdg; Command c; const(float)[] f; xdg(c, f); }))
    {
      if (dg is null) return;
      if (nsflts < 3) return;
      enum HasRes = __traits(compiles, (){ DG xdg; Command c; const(float)[] f; bool res = xdg(c, f); });
      int argc;
      Command cmd;
      for (int pidx = 0; pidx+3 <= nsflts; ) {
        cmd = cast(Command)stream[pidx++];
        final switch (cmd) {
          case Command.MoveTo: argc = 2; break;
          case Command.LineTo: argc = 2; break;
          case Command.QuadTo: argc = 4; break;
          case Command.BezierTo: argc = 6; break;
        }
        if (pidx+argc > nsflts) break; // just in case
        static if (HasRes) { if (dg(cmd, stream[pidx..pidx+argc])) return; } else { dg(cmd, stream[pidx..pidx+argc]); }
        pidx += argc;
      }
      static if (synthesizeCloseCommand) {
        if (closed && cast(Command)stream[0] == Command.MoveTo) {
          static if (HasRes) { if (dg(Command.LineTo, stream[1..3])) return; } else { dg(Command.LineTo, stream[1..3]); }
        }
      }
    }
  }

  static struct Clip {
    NSVGclipPathIndex* index;	// Array of clip path indices (of related NSVGimage).
    NSVGclipPathIndex count;	// Number of clip paths in this set.
  }

  ///
  static struct Shape {
    @disable this (this);
    char[64] id = 0;          /// Optional 'id' attr of the shape or its group
    NSVG.Paint fill;          /// Fill paint
    NSVG.Paint stroke;        /// Stroke paint
    float opacity;            /// Opacity of the shape.
    float strokeWidth;        /// Stroke width (scaled).
    float strokeDashOffset;   /// Stroke dash offset (scaled).
    float[8] strokeDashArray; /// Stroke dash array (scaled).
    byte strokeDashCount;     /// Number of dash values in dash array.
    LineJoin strokeLineJoin;  /// Stroke join type.
    LineCap strokeLineCap;    /// Stroke cap type.
    float miterLimit;         /// Miter limit
    FillRule fillRule;        /// Fill rule, see FillRule.
    /*Flags*/ubyte flags;     /// Logical or of NSVG_FLAGS_* flags
    float[4] bounds;          /// Tight bounding box of the shape [minx,miny,maxx,maxy].
    NSVG.Path* paths;         /// Linked list of paths in the image.
    NSVG.Clip clip;
    NSVG.Shape* next;         /// Pointer to next shape, or null if last element.

    @property bool visible () const pure nothrow @safe @nogc { pragma(inline, true); return ((flags&Visible) != 0); } ///

    /// delegate can accept:
    ///   NSVG.Path*
    ///   const(NSVG.Path)*
    ///   ref NSVG.Path
    ///   in ref NSVG.Path
    /// delegate can return:
    ///   void
    ///   bool (true means `stop`)
    void forEachPath(DG) (scope DG dg) inout
    if (__traits(compiles, (){ DG xdg; NSVG.Path s; xdg(&s); }) ||
        __traits(compiles, (){ DG xdg; NSVG.Path s; xdg(s); }))
    {
      if (dg is null) return;
      enum WantPtr = __traits(compiles, (){ DG xdg; NSVG.Path s; xdg(&s); });
      static if (WantPtr) {
        enum HasRes = __traits(compiles, (){ DG xdg; NSVG.Path s; bool res = xdg(&s); });
      } else {
        enum HasRes = __traits(compiles, (){ DG xdg; NSVG.Path s; bool res = xdg(s); });
      }
      static if (__traits(compiles, (){ NSVG.Path* s = this.paths; })) {
        alias TP = NSVG.Path*;
      } else {
        alias TP = const(NSVG.Path)*;
      }
      for (TP path = paths; path !is null; path = path.next) {
        static if (HasRes) {
          static if (WantPtr) {
            if (dg(path)) return;
          } else {
            if (dg(*path)) return;
          }
        } else {
          static if (WantPtr) dg(path); else dg(*path);
        }
      }
    }
  }

  static struct ClipPath {
    char[64] id; // Unique id of this clip path (from SVG).
    NSVGclipPathIndex index; // Unique internal index of this clip path.
    NSVG.Shape* shapes; // Linked list of shapes in this clip path.
    NSVG.ClipPath* next; // Pointer to next clip path or NULL.
  }

  float width;        /// Width of the image.
  float height;       /// Height of the image.
  NSVG.Shape* shapes; /// Linked list of shapes in the image.
  NSVG.ClipPath* clipPaths;	/// Linked list of clip paths in the image.

  /// delegate can accept:
  ///   NSVG.Shape*
  ///   const(NSVG.Shape)*
  ///   ref NSVG.Shape
  ///   in ref NSVG.Shape
  /// delegate can return:
  ///   void
  ///   bool (true means `stop`)
  void forEachShape(DG) (scope DG dg) inout
  if (__traits(compiles, (){ DG xdg; NSVG.Shape s; xdg(&s); }) ||
      __traits(compiles, (){ DG xdg; NSVG.Shape s; xdg(s); }))
  {
    if (dg is null) return;
    enum WantPtr = __traits(compiles, (){ DG xdg; NSVG.Shape s; xdg(&s); });
    static if (WantPtr) {
      enum HasRes = __traits(compiles, (){ DG xdg; NSVG.Shape s; bool res = xdg(&s); });
    } else {
      enum HasRes = __traits(compiles, (){ DG xdg; NSVG.Shape s; bool res = xdg(s); });
    }
    static if (__traits(compiles, (){ NSVG.Shape* s = this.shapes; })) {
      alias TP = NSVG.Shape*;
    } else {
      alias TP = const(NSVG.Shape)*;
    }
    for (TP shape = shapes; shape !is null; shape = shape.next) {
      static if (HasRes) {
        static if (WantPtr) {
          if (dg(shape)) return;
        } else {
          if (dg(*shape)) return;
        }
      } else {
        static if (WantPtr) dg(shape); else dg(*shape);
      }
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
private:
nothrow @trusted @nogc {

// ////////////////////////////////////////////////////////////////////////// //
// sscanf replacement: just enough to replace all our cases
int xsscanf(A...) (const(char)[] str, const(char)[] fmt, ref A args) {
  int spos;
  while (spos < str.length && str.ptr[spos] <= ' ') ++spos;

  static int hexdigit() (char c) {
    pragma(inline, true);
    return
      (c >= '0' && c <= '9' ? c-'0' :
       c >= 'A' && c <= 'F' ? c-'A'+10 :
       c >= 'a' && c <= 'f' ? c-'a'+10 :
       -1);
  }

  bool parseInt(T : ulong) (ref T res) {
    res = 0;
    debug(xsscanf_int) { import std.stdio; writeln("parseInt00: str=", str[spos..$].quote); }
    bool neg = false;
         if (spos < str.length && str.ptr[spos] == '+') ++spos;
    else if (spos < str.length && str.ptr[spos] == '-') { neg = true; ++spos; }
    if (spos >= str.length || str.ptr[spos] < '0' || str.ptr[spos] > '9') return false;
    while (spos < str.length && str.ptr[spos] >= '0' && str.ptr[spos] <= '9') res = res*10+str.ptr[spos++]-'0';
    debug(xsscanf_int) { import std.stdio; writeln("parseInt10: str=", str[spos..$].quote); }
    if (neg) res = -res;
    return true;
  }

  bool parseHex(T : ulong) (ref T res) {
    res = 0;
    debug(xsscanf_int) { import std.stdio; writeln("parseHex00: str=", str[spos..$].quote); }
    if (spos >= str.length || hexdigit(str.ptr[spos]) < 0) return false;
    while (spos < str.length) {
      auto d = hexdigit(str.ptr[spos]);
      if (d < 0) break;
      res = res*16+d;
      ++spos;
    }
    debug(xsscanf_int) { import std.stdio; writeln("parseHex10: str=", str[spos..$].quote); }
    return true;
  }

  bool parseFloat(T : real) (ref T res) {
    res = 0.0;
    debug(xsscanf_float) { import std.stdio; writeln("parseFloat00: str=", str[spos..$].quote); }
    bool neg = false;
         if (spos < str.length && str.ptr[spos] == '+') ++spos;
    else if (spos < str.length && str.ptr[spos] == '-') { neg = true; ++spos; }
    bool wasChar = false;
    // integer part
    debug(xsscanf_float) { import std.stdio; writeln("parseFloat01: str=", str[spos..$].quote); }
    if (spos < str.length && str.ptr[spos] >= '0' && str.ptr[spos] <= '9') wasChar = true;
    while (spos < str.length && str.ptr[spos] >= '0' && str.ptr[spos] <= '9') res = res*10+str.ptr[spos++]-'0';
    // fractional part
    if (spos < str.length && str.ptr[spos] == '.') {
      debug(xsscanf_float) { import std.stdio; writeln("parseFloat02: str=", str[spos..$].quote); }
      T div = 1.0/10;
      ++spos;
      if (spos < str.length && str.ptr[spos] >= '0' && str.ptr[spos] <= '9') wasChar = true;
      debug(xsscanf_float) { import std.stdio; writeln("parseFloat03: str=", str[spos..$].quote); }
      while (spos < str.length && str.ptr[spos] >= '0' && str.ptr[spos] <= '9') {
        res += div*(str.ptr[spos++]-'0');
        div /= 10.0;
      }
      debug(xsscanf_float) { import std.stdio; writeln("parseFloat04: str=", str[spos..$].quote); }
      debug(xsscanf_float) { import std.stdio; writeln("div=", div, "; res=", res, "; str=", str[spos..$].quote); }
    }
    // '[Ee][+-]num' part
    if (wasChar && spos < str.length && (str.ptr[spos] == 'E' || str.ptr[spos] == 'e')) {
      debug(xsscanf_float) { import std.stdio; writeln("parseFloat05: str=", str[spos..$].quote); }
      ++spos;
      bool xneg = false;
           if (spos < str.length && str.ptr[spos] == '+') ++spos;
      else if (spos < str.length && str.ptr[spos] == '-') { xneg = true; ++spos; }
      int n = 0;
      if (spos >= str.length || str.ptr[spos] < '0' || str.ptr[spos] > '9') return false; // number expected
      debug(xsscanf_float) { import std.stdio; writeln("parseFloat06: str=", str[spos..$].quote); }
      while (spos < str.length && str.ptr[spos] >= '0' && str.ptr[spos] <= '9') n = n*10+str.ptr[spos++]-'0';
      if (xneg) {
        while (n-- > 0) res /= 10;
      } else {
        while (n-- > 0) res *= 10;
      }
      debug(xsscanf_float) { import std.stdio; writeln("parseFloat07: str=", str[spos..$].quote); }
    }
    if (!wasChar) return false;
    debug(xsscanf_float) { import std.stdio; writeln("parseFloat10: str=", str[spos..$].quote); }
    if (neg) res = -res;
    return true;
  }

  int fpos;

  void skipXSpaces () {
    if (fpos < fmt.length && fmt.ptr[fpos] <= ' ') {
      while (fpos < fmt.length && fmt.ptr[fpos] <= ' ') ++fpos;
      while (spos < str.length && str.ptr[spos] <= ' ') ++spos;
    }
  }

  bool parseImpl(T/*, usize dummy*/) (ref T res) {
    while (fpos < fmt.length) {
      //{ import std.stdio; writeln("spos=", spos, "; fpos=", fpos, "\nfmt=", fmt[fpos..$].quote, "\nstr=", str[spos..$].quote); }
      if (fmt.ptr[fpos] <= ' ') {
        skipXSpaces();
        continue;
      }
      if (fmt.ptr[fpos] != '%') {
        if (spos >= str.length || str.ptr[spos] != fmt.ptr[spos]) return false;
        ++spos;
        ++fpos;
        continue;
      }
      if (fmt.length-fpos < 2) return false; // stray percent
      fpos += 2;
      bool skipAss = false;
      if (fmt.ptr[fpos-1] == '*') {
        ++fpos;
        if (fpos >= fmt.length) return false; // stray star
        skipAss = true;
      }
      switch (fmt.ptr[fpos-1]) {
        case '%':
          if (spos >= str.length || str.ptr[spos] != '%') return false;
          ++spos;
          break;
        case 'd':
          static if (is(T : ulong)) {
            if (skipAss) {
              long v;
              if (!parseInt!long(v)) return false;
            } else {
              return parseInt!T(res);
            }
          } else {
            if (!skipAss) assert(0, "invalid type");
            long v;
            if (!parseInt!long(v)) return false;
          }
          break;
        case 'x':
          static if (is(T : ulong)) {
            if (skipAss) {
              long v;
              if (!parseHex!long(v)) return false;
            } else {
              return parseHex!T(res);
            }
          } else {
            if (!skipAss) assert(0, "invalid type");
            ulong v;
            if (!parseHex!ulong(v)) return false;
          }
          break;
        case 'f':
          static if (is(T == float) || is(T == double) || is(T == real)) {
            if (skipAss) {
              double v;
              if (!parseFloat!double(v)) return false;
            } else {
              return parseFloat!T(res);
            }
          } else {
            if (!skipAss) assert(0, "invalid type");
            double v;
            if (!parseFloat!double(v)) return false;
          }
          break;
        case '[':
          if (fmt.length-fpos < 1) return false;
          auto stp = spos;
          while (spos < str.length) {
            bool ok = false;
            foreach (immutable cidx, char c; fmt[fpos..$]) {
              if (cidx != 0) {
                if (c == '-') assert(0, "not yet");
                if (c == ']') break;
              }
              if (c == ' ') {
                if (str.ptr[spos] <= ' ') { ok = true; break; }
              } else {
                if (str.ptr[spos] == c) { ok = true; break; }
              }
            }
            //{ import std.stdio; writeln("** spos=", spos, "; fpos=", fpos, "\nfmt=", fmt[fpos..$].quote, "\nstr=", str[spos..$].quote, "\nok: ", ok); }
            if (!ok) break; // not a match
            ++spos; // skip match
          }
          ++fpos;
          while (fpos < fmt.length && fmt[fpos] != ']') ++fpos;
          if (fpos < fmt.length) ++fpos;
          static if (is(T == const(char)[])) {
            if (!skipAss) {
              res = str[stp..spos];
              return true;
            }
          } else {
            if (!skipAss) assert(0, "invalid type");
          }
          break;
        case 's':
          auto stp = spos;
          while (spos < str.length && str.ptr[spos] > ' ') ++spos;
          static if (is(T == const(char)[])) {
            if (!skipAss) {
              res = str[stp..spos];
              return true;
            }
          } else {
            // skip non-spaces
            if (!skipAss) assert(0, "invalid type");
          }
          break;
        default: assert(0, "unknown format specifier");
      }
    }
    return false;
  }

  foreach (usize aidx, immutable T; A) {
    //pragma(msg, "aidx=", aidx, "; T=", T);
    if (!parseImpl!(T)(args[aidx])) return -(spos+1);
    //{ import std.stdio; writeln("@@@ aidx=", aidx+3, "; spos=", spos, "; fpos=", fpos, "\nfmt=", fmt[fpos..$].quote, "\nstr=", str[spos..$].quote); }
  }
  skipXSpaces();
  return (fpos < fmt.length ? -(spos+1) : spos);
}


// ////////////////////////////////////////////////////////////////////////// //
T* xalloc(T) (usize addmem=0) if (!is(T == class)) {
  import core.stdc.stdlib : malloc;
  if (T.sizeof == 0 && addmem == 0) addmem = 1;
  auto res = cast(ubyte*)malloc(T.sizeof+addmem+256);
  if (res is null) assert(0, "NanoVega.SVG: out of memory");
  res[0..T.sizeof+addmem] = 0;
  return cast(T*)res;
}

T* xcalloc(T) (usize count) if (!is(T == class) && !is(T == struct)) {
  import core.stdc.stdlib : malloc;
  usize sz = T.sizeof*count;
  if (sz == 0) sz = 1;
  auto res = cast(ubyte*)malloc(sz+256);
  if (res is null) assert(0, "NanoVega.SVG: out of memory");
  res[0..sz] = 0;
  return cast(T*)res;
}

void xfree(T) (ref T* p) {
  if (p !is null) {
    import core.stdc.stdlib : free;
    free(p);
    p = null;
  }
}


alias AttrList = const(const(char)[])[];

public enum NSVG_PI = 3.14159265358979323846264338327f; ///
enum NSVG_KAPPA90 = 0.5522847493f; // Lenght proportional to radius of a cubic bezier handle for 90deg arcs.

enum NSVG_ALIGN_MIN = 0;
enum NSVG_ALIGN_MID = 1;
enum NSVG_ALIGN_MAX = 2;
enum NSVG_ALIGN_NONE = 0;
enum NSVG_ALIGN_MEET = 1;
enum NSVG_ALIGN_SLICE = 2;


int nsvg__isspace() (char c) { pragma(inline, true); return (c && c <= ' '); } // because
int nsvg__isdigit() (char c) { pragma(inline, true); return (c >= '0' && c <= '9'); }
int nsvg__isnum() (char c) { pragma(inline, true); return ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.' || c == 'e' || c == 'E'); }

int nsvg__hexdigit() (char c) {
  pragma(inline, true);
  return
    (c >= '0' && c <= '9' ? c-'0' :
     c >= 'A' && c <= 'F' ? c-'A'+10 :
     c >= 'a' && c <= 'f' ? c-'a'+10 :
     -1);
}

float nsvg__minf() (float a, float b) { pragma(inline, true); return (a < b ? a : b); }
float nsvg__maxf() (float a, float b) { pragma(inline, true); return (a > b ? a : b); }


// Simple XML parser
enum NSVG_XML_TAG = 1;
enum NSVG_XML_CONTENT = 2;
enum NSVG_XML_MAX_ATTRIBS = 256;

void nsvg__parseContent (const(char)[] s, scope void function (void* ud, const(char)[] s) nothrow @nogc contentCb, void* ud) {
  // Trim start white spaces
  while (s.length && nsvg__isspace(s[0])) s = s[1..$];
  if (s.length == 0) return;
  //{ import std.stdio; writeln("s=", s.quote); }
  if (contentCb !is null) contentCb(ud, s);
}

static void nsvg__parseElement (const(char)[] s,
                 scope void function (void* ud, const(char)[] el, AttrList attr) nothrow @nogc startelCb,
                 scope void function (void* ud, const(char)[] el) nothrow @nogc endelCb,
                 void* ud)
{
  const(char)[][NSVG_XML_MAX_ATTRIBS] attr;
  int nattr = 0;
  const(char)[] name;
  int start = 0;
  int end = 0;
  char quote;

  // Skip white space after the '<'
  while (s.length && nsvg__isspace(s[0])) s = s[1..$];

  // Check if the tag is end tag
  if (s.length && s[0] == '/') {
    s = s[1..$];
    end = 1;
  } else {
    start = 1;
  }

  // Skip comments, data and preprocessor stuff.
  if (s.length == 0 || s[0] == '?' || s[0] == '!') return;

  // Get tag name
  //{ import std.stdio; writeln("bs=", s.quote); }
  {
    usize pos = 0;
    while (pos < s.length && !nsvg__isspace(s[pos])) ++pos;
    name = s[0..pos];
    s = s[pos..$];
  }
  //{ import std.stdio; writeln("name=", name.quote); }
  //{ import std.stdio; writeln("as=", s.quote); }

  // Get attribs
  while (!end && s.length && attr.length-nattr >= 2) {
    // skip white space before the attrib name
    while (s.length && nsvg__isspace(s[0])) s = s[1..$];
    if (s.length == 0) break;
    if (s[0] == '/') { end = 1; break; }
    // find end of the attrib name
    {
      usize pos = 0;
      while (pos < s.length && !nsvg__isspace(s[pos]) && s[pos] != '=') ++pos;
      attr[nattr++] = s[0..pos];
      s = s[pos..$];
    }
    // skip until the beginning of the value
    while (s.length && s[0] != '\"' && s[0] != '\'') s = s[1..$];
    if (s.length == 0) break;
    // store value and find the end of it
    quote = s[0];
    s = s[1..$];
    {
      usize pos = 0;
      while (pos < s.length && s[pos] != quote) ++pos;
      attr[nattr++] = s[0..pos];
      s = s[pos+(pos < s.length ? 1 : 0)..$];
    }
    //{ import std.stdio; writeln("n=", attr[nattr-2].quote, "\nv=", attr[nattr-1].quote, "\n"); }
  }

  debug(nanosvg) {
    import std.stdio;
    writeln("===========================");
    foreach (immutable idx, const(char)[] v; attr[0..nattr]) writeln("  #", idx, ": ", v.quote);
  }

  // Call callbacks.
  if (start && startelCb !is null) startelCb(ud, name, attr[0..nattr]);
  if (end && endelCb !is null) endelCb(ud, name);
}

void nsvg__parseXML (const(char)[] input,
                     scope void function (void* ud, const(char)[] el, AttrList attr) nothrow @nogc startelCb,
                     scope void function (void* ud, const(char)[] el) nothrow @nogc endelCb,
                     scope void function (void* ud, const(char)[] s) nothrow @nogc contentCb,
                     void* ud)
{
  usize cpos = 0;
  int state = NSVG_XML_CONTENT;
  while (cpos < input.length) {
    if (state == NSVG_XML_CONTENT && input[cpos] == '<') {
      if (input.length-cpos >= 9 && input[cpos..cpos+9] == "<![CDATA[") {
        cpos += 9;
        while (cpos < input.length) {
          if (input.length-cpos > 1 && input.ptr[cpos] == ']' && input.ptr[cpos+1] == ']') {
            cpos += 2;
            while (cpos < input.length && input.ptr[cpos] <= ' ') ++cpos;
            if (cpos < input.length && input.ptr[cpos] == '>') { ++cpos; break; }
          } else {
            ++cpos;
          }
        }
        continue;
      }
      // start of a tag
      //{ import std.stdio; writeln("ctx: ", input[0..cpos].quote); }
      ////version(nanosvg_debug_styles) { import std.stdio; writeln("ctx: ", input[0..cpos].quote); }
      nsvg__parseContent(input[0..cpos], contentCb, ud);
      input = input[cpos+1..$];
      if (input.length > 2 && input.ptr[0] == '!' && input.ptr[1] == '-' && input.ptr[2] == '-') {
        //{ import std.stdio; writeln("ctx0: ", input.quote); }
        // skip comments
        cpos = 3;
        while (cpos < input.length) {
          if (input.length-cpos > 2 && input.ptr[cpos] == '-' && input.ptr[cpos+1] == '-' && input.ptr[cpos+2] == '>') {
            cpos += 3;
            break;
          }
          ++cpos;
        }
        input = input[cpos..$];
        //{ import std.stdio; writeln("ctx1: ", input.quote); }
      } else {
        state = NSVG_XML_TAG;
      }
      cpos = 0;
    } else if (state == NSVG_XML_TAG && input[cpos] == '>') {
      // start of a content or new tag
      //{ import std.stdio; writeln("tag: ", input[0..cpos].quote); }
      nsvg__parseElement(input[0..cpos], startelCb, endelCb, ud);
      input = input[cpos+1..$];
      cpos = 0;
      state = NSVG_XML_CONTENT;
    } else {
      ++cpos;
    }
  }
}


/* Simple SVG parser. */

enum NSVG_MAX_ATTR = 128;

enum GradientUnits : ubyte {
  User,
  Object,
}

enum NSVG_MAX_DASHES = 8;

enum Units : ubyte {
  user,
  px,
  pt,
  pc,
  mm,
  cm,
  in_,
  percent,
  em,
  ex,
}

struct Coordinate {
  float value;
  Units units;
}

struct LinearData {
  Coordinate x1, y1, x2, y2;
}

struct RadialData {
  Coordinate cx, cy, r, fx, fy;
}

struct GradientData {
  char[64] id = 0;
  char[64] ref_ = 0;
  NSVG.PaintType type;
  union {
    LinearData linear;
    RadialData radial;
  }
  NSVG.SpreadType spread;
  GradientUnits units;
  float[6] xform;
  int nstops;
  NSVG.GradientStop* stops;
  GradientData* next;
}

struct Attrib {
  char[64] id = 0;
  float[6] xform;
  uint fillColor;
  uint strokeColor;
  float opacity;
  float fillOpacity;
  float strokeOpacity;
  char[64] fillGradient = 0;
  char[64] strokeGradient = 0;
  float strokeWidth;
  float strokeDashOffset;
  float[NSVG_MAX_DASHES] strokeDashArray;
  int strokeDashCount;
  NSVG.LineJoin strokeLineJoin;
  NSVG.LineCap strokeLineCap;
  float miterLimit;
  NSVG.FillRule fillRule;
  float fontSize;
  uint stopColor;
  float stopOpacity;
  float stopOffset;
  ubyte hasFill;
  ubyte hasStroke;
  ubyte visible;
  NSVGclipPathIndex clipPathCount;
}

version(nanosvg_crappy_stylesheet_parser) {
struct Style {
  const(char)[] name;
  const(char)[] value;
}
}

struct Parser {
  Attrib[NSVG_MAX_ATTR] attr;
  int attrHead;
  float* stream;
  int nsflts;
  int csflts;
  NSVG.Path* plist;
  NSVG* image;
  GradientData* gradients;
  NSVG.Shape* shapesTail;
  float viewMinx, viewMiny, viewWidth, viewHeight;
  int alignX, alignY, alignType;
  float dpi;
  bool pathFlag;
  bool defsFlag;

  NSVG.ClipPath* clipPath;
  NSVGclipPathIndex[255] clipPathStack; // note the  type of clipPathIndex = ubyte

  int canvaswdt = -1;
  int canvashgt = -1;
  version(nanosvg_crappy_stylesheet_parser) {
    Style* styles;
    uint styleCount;
    bool inStyle;
  }
}

const(char)[] fromAsciiz (const(char)[] s) {
  //foreach (immutable idx, char ch; s) if (!ch) return s[0..idx];
  //return s;
  if (s.length) {
    import core.stdc.string : memchr;
    if (auto zp = cast(const(char)*)memchr(s.ptr, 0, s.length)) return s[0..cast(usize)(zp-s.ptr)];
  }
  return s;
}

// ////////////////////////////////////////////////////////////////////////// //
// matrix operations made public for the sake of... something.

///
public void nsvg__xformIdentity (float* t) {
  t[0] = 1.0f; t[1] = 0.0f;
  t[2] = 0.0f; t[3] = 1.0f;
  t[4] = 0.0f; t[5] = 0.0f;
}

///
public void nsvg__xformSetTranslation (float* t, in float tx, in float ty) {
  t[0] = 1.0f; t[1] = 0.0f;
  t[2] = 0.0f; t[3] = 1.0f;
  t[4] = tx; t[5] = ty;
}

///
public void nsvg__xformSetScale (float* t, in float sx, in float sy) {
  t[0] = sx; t[1] = 0.0f;
  t[2] = 0.0f; t[3] = sy;
  t[4] = 0.0f; t[5] = 0.0f;
}

///
public void nsvg__xformSetSkewX (float* t, in float a) {
  t[0] = 1.0f; t[1] = 0.0f;
  t[2] = tanf(a); t[3] = 1.0f;
  t[4] = 0.0f; t[5] = 0.0f;
}

///
public void nsvg__xformSetSkewY (float* t, in float a) {
  t[0] = 1.0f; t[1] = tanf(a);
  t[2] = 0.0f; t[3] = 1.0f;
  t[4] = 0.0f; t[5] = 0.0f;
}

///
public void nsvg__xformSetRotation (float* t, in float a) {
  immutable cs = cosf(a), sn = sinf(a);
  t[0] = cs; t[1] = sn;
  t[2] = -sn; t[3] = cs;
  t[4] = 0.0f; t[5] = 0.0f;
}

///
public void nsvg__xformMultiply (float* t, const(float)* s) {
  immutable t0 = t[0]*s[0]+t[1]*s[2];
  immutable t2 = t[2]*s[0]+t[3]*s[2];
  immutable t4 = t[4]*s[0]+t[5]*s[2]+s[4];
  t[1] = t[0]*s[1]+t[1]*s[3];
  t[3] = t[2]*s[1]+t[3]*s[3];
  t[5] = t[4]*s[1]+t[5]*s[3]+s[5];
  t[0] = t0;
  t[2] = t2;
  t[4] = t4;
}

///
public void nsvg__xformInverse (float* inv, const(float)* t) {
  immutable double det = cast(double)t[0]*t[3]-cast(double)t[2]*t[1];
  if (det > -1e-6 && det < 1e-6) {
    nsvg__xformIdentity(inv);
    return;
  }
  immutable double invdet = 1.0/det;
  inv[0] = cast(float)(t[3]*invdet);
  inv[2] = cast(float)(-t[2]*invdet);
  inv[4] = cast(float)((cast(double)t[2]*t[5]-cast(double)t[3]*t[4])*invdet);
  inv[1] = cast(float)(-t[1]*invdet);
  inv[3] = cast(float)(t[0]*invdet);
  inv[5] = cast(float)((cast(double)t[1]*t[4]-cast(double)t[0]*t[5])*invdet);
}

///
public void nsvg__xformPremultiply (float* t, const(float)* s) {
  float[6] s2 = s[0..6];
  //memcpy(s2.ptr, s, float.sizeof*6);
  nsvg__xformMultiply(s2.ptr, t);
  //memcpy(t, s2.ptr, float.sizeof*6);
  t[0..6] = s2[];
}

///
public void nsvg__xformPoint (float* dx, float* dy, in float x, in float y, const(float)* t) {
  if (dx !is null) *dx = x*t[0]+y*t[2]+t[4];
  if (dy !is null) *dy = x*t[1]+y*t[3]+t[5];
}

///
public void nsvg__xformVec (float* dx, float* dy, in float x, in float y, const(float)* t) {
  if (dx !is null) *dx = x*t[0]+y*t[2];
  if (dy !is null) *dy = x*t[1]+y*t[3];
}

///
public enum NSVG_EPSILON = (1e-12);

///
public int nsvg__ptInBounds (const(float)* pt, const(float)* bounds) {
  pragma(inline, true);
  return pt[0] >= bounds[0] && pt[0] <= bounds[2] && pt[1] >= bounds[1] && pt[1] <= bounds[3];
}

///
public double nsvg__evalBezier (double t, double p0, double p1, double p2, double p3) {
  pragma(inline, true);
  double it = 1.0-t;
  return it*it*it*p0+3.0*it*it*t*p1+3.0*it*t*t*p2+t*t*t*p3;
}

///
public void nsvg__curveBounds (float* bounds, const(float)* curve) {
  const float* v0 = &curve[0];
  const float* v1 = &curve[2];
  const float* v2 = &curve[4];
  const float* v3 = &curve[6];

  // Start the bounding box by end points
  bounds[0] = nsvg__minf(v0[0], v3[0]);
  bounds[1] = nsvg__minf(v0[1], v3[1]);
  bounds[2] = nsvg__maxf(v0[0], v3[0]);
  bounds[3] = nsvg__maxf(v0[1], v3[1]);

  // Bezier curve fits inside the convex hull of it's control points.
  // If control points are inside the bounds, we're done.
  if (nsvg__ptInBounds(v1, bounds) && nsvg__ptInBounds(v2, bounds)) return;

  // Add bezier curve inflection points in X and Y.
  double[2] roots = void;
  foreach (int i; 0..2) {
    immutable double a = -3.0*v0[i]+9.0*v1[i]-9.0*v2[i]+3.0*v3[i];
    immutable double b = 6.0*v0[i]-12.0*v1[i]+6.0*v2[i];
    immutable double c = 3.0*v1[i]-3.0*v0[i];
    int count = 0;
    if (fabs(a) < NSVG_EPSILON) {
      if (fabs(b) > NSVG_EPSILON) {
        immutable double t = -c/b;
        if (t > NSVG_EPSILON && t < 1.0-NSVG_EPSILON) roots.ptr[count++] = t;
      }
    } else {
      immutable double b2ac = b*b-4.0*c*a;
      if (b2ac > NSVG_EPSILON) {
        double t = (-b+sqrt(b2ac))/(2.0*a);
        if (t > NSVG_EPSILON && t < 1.0-NSVG_EPSILON) roots.ptr[count++] = t;
        t = (-b-sqrt(b2ac))/(2.0*a);
        if (t > NSVG_EPSILON && t < 1.0-NSVG_EPSILON) roots.ptr[count++] = t;
      }
    }
    foreach (int j; 0..count) {
      immutable double v = nsvg__evalBezier(roots.ptr[j], v0[i], v1[i], v2[i], v3[i]);
      bounds[0+i] = nsvg__minf(bounds[0+i], cast(float)v);
      bounds[2+i] = nsvg__maxf(bounds[2+i], cast(float)v);
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
Parser* nsvg__createParser () {
  Parser* p = xalloc!Parser;
  if (p is null) goto error;

  p.image = xalloc!NSVG;
  if (p.image is null) goto error;

  // Init style
  nsvg__xformIdentity(p.attr[0].xform.ptr);
  p.attr[0].id[] = 0;
  p.attr[0].fillColor = NSVG.Paint.rgb(0, 0, 0);
  p.attr[0].strokeColor = NSVG.Paint.rgb(0, 0, 0);
  p.attr[0].opacity = 1;
  p.attr[0].fillOpacity = 1;
  p.attr[0].strokeOpacity = 1;
  p.attr[0].stopOpacity = 1;
  p.attr[0].strokeWidth = 1;
  p.attr[0].strokeLineJoin = NSVG.LineJoin.Miter;
  p.attr[0].strokeLineCap = NSVG.LineCap.Butt;
  p.attr[0].miterLimit = 4;
  p.attr[0].fillRule = NSVG.FillRule.EvenOdd;
  p.attr[0].hasFill = 1;
  p.attr[0].visible = 1;

  return p;

error:
  if (p !is null) {
    xfree(p.image);
    xfree(p);
  }
  return null;
}

void nsvg__deletePaths (NSVG.Path* path) {
  while (path !is null) {
    NSVG.Path* next = path.next;
    xfree(path.stream);
    xfree(path);
    path = next;
  }
}

void nsvg__deletePaint (NSVG.Paint* paint) {
  if (paint.type == NSVG.PaintType.LinearGradient || paint.type == NSVG.PaintType.RadialGradient) xfree(paint.gradient);
}

void nsvg__deleteGradientData (GradientData* grad) {
  GradientData* next;
  while (grad !is null) {
    next = grad.next;
    xfree(grad.stops);
    xfree(grad);
    grad = next;
  }
}

void nsvg__deleteParser (Parser* p) {
  if (p !is null) {
    nsvg__deletePaths(p.plist);
    nsvg__deleteGradientData(p.gradients);
    kill(p.image);
    xfree(p.stream);
    version(nanosvg_crappy_stylesheet_parser) xfree(p.styles);
    xfree(p);
  }
}

void nsvg__resetPath (Parser* p) {
  p.nsflts = 0;
}

void nsvg__addToStream (Parser* p, in float v) {
  if (p.nsflts+1 > p.csflts) {
    import core.stdc.stdlib : realloc;
    p.csflts = (p.csflts == 0 ? 32 : p.csflts < 16384 ? p.csflts*2 : p.csflts+4096); //k8: arbitrary
    p.stream = cast(float*)realloc(p.stream, p.csflts*float.sizeof);
    if (p.stream is null) assert(0, "nanosvg: out of memory");
  }
  p.stream[p.nsflts++] = v;
}

void nsvg__addCommand (Parser* p, NSVG.Command c) {
  nsvg__addToStream(p, cast(float)c);
}

void nsvg__addPoint (Parser* p, in float x, in float y) {
  nsvg__addToStream(p, x);
  nsvg__addToStream(p, y);
}

void nsvg__moveTo (Parser* p, in float x, in float y) {
  // this is always called right after `nsvg__resetPath()`
  if (p.nsflts != 0) assert(0, "internal error in NanoVega.SVG");
  nsvg__addCommand(p, NSVG.Command.MoveTo);
  nsvg__addPoint(p, x, y);
  /*
  if (p.npts > 0) {
    p.pts[(p.npts-1)*2+0] = x;
    p.pts[(p.npts-1)*2+1] = y;
  } else {
    nsvg__addPoint(p, x, y);
  }
  */
}

void nsvg__lineTo (Parser* p, in float x, in float y) {
  if (p.nsflts > 0) {
    version(nanosvg_use_beziers) {
      immutable float px = p.pts[(p.npts-1)*2+0];
      immutable float py = p.pts[(p.npts-1)*2+1];
      immutable float dx = x-px;
      immutable float dy = y-py;
      nsvg__addCommand(NSVG.Command.BezierTo);
      nsvg__addPoint(p, px+dx/3.0f, py+dy/3.0f);
      nsvg__addPoint(p, x-dx/3.0f, y-dy/3.0f);
      nsvg__addPoint(p, x, y);
    } else {
      nsvg__addCommand(p, NSVG.Command.LineTo);
      nsvg__addPoint(p, x, y);
    }
  }
}

void nsvg__cubicBezTo (Parser* p, in float cpx1, in float cpy1, in float cpx2, in float cpy2, in float x, in float y) {
  nsvg__addCommand(p, NSVG.Command.BezierTo);
  nsvg__addPoint(p, cpx1, cpy1);
  nsvg__addPoint(p, cpx2, cpy2);
  nsvg__addPoint(p, x, y);
}

void nsvg__quadBezTo (Parser* p, in float cpx1, in float cpy1, in float x, in float y) {
  nsvg__addCommand(p, NSVG.Command.QuadTo);
  nsvg__addPoint(p, cpx1, cpy1);
  nsvg__addPoint(p, x, y);
}

Attrib* nsvg__getAttr (Parser* p) {
  return p.attr.ptr+p.attrHead;
}

void nsvg__pushAttr (Parser* p) {
  if (p.attrHead < NSVG_MAX_ATTR-1) {
    import core.stdc.string : memmove;
    ++p.attrHead;
    memmove(p.attr.ptr+p.attrHead, p.attr.ptr+(p.attrHead-1), Attrib.sizeof);
  }
}

void nsvg__popAttr (Parser* p) {
  if (p.attrHead > 0) --p.attrHead;
}

float nsvg__actualOrigX (Parser* p) { pragma(inline, true); return p.viewMinx; }
float nsvg__actualOrigY (Parser* p) { pragma(inline, true); return p.viewMiny; }
float nsvg__actualWidth (Parser* p) { pragma(inline, true); return p.viewWidth; }
float nsvg__actualHeight (Parser* p) { pragma(inline, true); return p.viewHeight; }

float nsvg__actualLength (Parser* p) {
  immutable float w = nsvg__actualWidth(p);
  immutable float h = nsvg__actualHeight(p);
  return sqrtf(w*w+h*h)/sqrtf(2.0f);
}

float nsvg__convertToPixels (Parser* p, Coordinate c, float orig, float length) {
  Attrib* attr = nsvg__getAttr(p);
  switch (c.units) {
    case Units.user: return c.value;
    case Units.px: return c.value;
    case Units.pt: return c.value/72.0f*p.dpi;
    case Units.pc: return c.value/6.0f*p.dpi;
    case Units.mm: return c.value/25.4f*p.dpi;
    case Units.cm: return c.value/2.54f*p.dpi;
    case Units.in_: return c.value*p.dpi;
    case Units.em: return c.value*attr.fontSize;
    case Units.ex: return c.value*attr.fontSize*0.52f; // x-height of Helvetica.
    case Units.percent: return orig+c.value/100.0f*length;
    default: return c.value;
  }
  assert(0);
  //return c.value;
}

GradientData* nsvg__findGradientData (Parser* p, const(char)[] id) {
  GradientData* grad = p.gradients;
  id = id.fromAsciiz;
  while (grad !is null) {
    if (grad.id.fromAsciiz == id) return grad;
    grad = grad.next;
  }
  return null;
}

NSVG.Gradient* nsvg__createGradient (Parser* p, const(char)[] id, const(float)* localBounds, NSVG.PaintType* paintType) {
  Attrib* attr = nsvg__getAttr(p);
  GradientData* data = null;
  GradientData* ref_ = null;
  NSVG.GradientStop* stops = null;
  NSVG.Gradient* grad;
  float ox = void, oy = void, sw = void, sh = void;
  int nstops = 0;

  id = id.fromAsciiz;
  data = nsvg__findGradientData(p, id);
  if (data is null) return null;

  // TODO: use ref_ to fill in all unset values too.
  ref_ = data;
  while (ref_ !is null) {
    if (stops is null && ref_.stops !is null) {
      stops = ref_.stops;
      nstops = ref_.nstops;
      break;
    }
    ref_ = nsvg__findGradientData(p, ref_.ref_[]);
  }
  if (stops is null) return null;

  grad = xalloc!(NSVG.Gradient)(NSVG.GradientStop.sizeof*nstops);
  if (grad is null) return null;

  // The shape width and height.
  if (data.units == GradientUnits.Object) {
    ox = localBounds[0];
    oy = localBounds[1];
    sw = localBounds[2]-localBounds[0];
    sh = localBounds[3]-localBounds[1];
  } else {
    ox = nsvg__actualOrigX(p);
    oy = nsvg__actualOrigY(p);
    sw = nsvg__actualWidth(p);
    sh = nsvg__actualHeight(p);
  }
  immutable float sl = sqrtf(sw*sw+sh*sh)/sqrtf(2.0f);

  if (data.type == NSVG.PaintType.LinearGradient) {
    immutable float x1 = nsvg__convertToPixels(p, data.linear.x1, ox, sw);
    immutable float y1 = nsvg__convertToPixels(p, data.linear.y1, oy, sh);
    immutable float x2 = nsvg__convertToPixels(p, data.linear.x2, ox, sw);
    immutable float y2 = nsvg__convertToPixels(p, data.linear.y2, oy, sh);
    // Calculate transform aligned to the line
    immutable float dx = x2-x1;
    immutable float dy = y2-y1;
    grad.xform[0] = dy; grad.xform[1] = -dx;
    grad.xform[2] = dx; grad.xform[3] = dy;
    grad.xform[4] = x1; grad.xform[5] = y1;
  } else {
    immutable float cx = nsvg__convertToPixels(p, data.radial.cx, ox, sw);
    immutable float cy = nsvg__convertToPixels(p, data.radial.cy, oy, sh);
    immutable float fx = nsvg__convertToPixels(p, data.radial.fx, ox, sw);
    immutable float fy = nsvg__convertToPixels(p, data.radial.fy, oy, sh);
    immutable float r = nsvg__convertToPixels(p, data.radial.r, 0, sl);
    // Calculate transform aligned to the circle
    grad.xform[0] = r; grad.xform[1] = 0;
    grad.xform[2] = 0; grad.xform[3] = r;
    grad.xform[4] = cx; grad.xform[5] = cy;
    // fix from https://github.com/memononen/nanosvg/issues/26#issuecomment-278713651
    grad.fx = (fx-cx)/r; // was fx/r;
    grad.fy = (fy-cy)/r; // was fy/r;
  }

  nsvg__xformMultiply(grad.xform.ptr, data.xform.ptr);
  nsvg__xformMultiply(grad.xform.ptr, attr.xform.ptr);

  grad.spread = data.spread;
  //memcpy(grad.stops.ptr, stops, nstops*NSVG.GradientStop.sizeof);
  grad.stops.ptr[0..nstops] = stops[0..nstops];
  grad.nstops = nstops;

  *paintType = data.type;

  return grad;
}

float nsvg__getAverageScale (float* t) {
  float sx = sqrtf(t[0]*t[0]+t[2]*t[2]);
  float sy = sqrtf(t[1]*t[1]+t[3]*t[3]);
  return (sx+sy)*0.5f;
}

void nsvg__quadBounds (float* bounds, const(float)* curve) nothrow @trusted @nogc {
  // cheat: convert quadratic bezier to cubic bezier
  immutable float cx = curve[0];
  immutable float cy = curve[1];
  immutable float x1 = curve[2];
  immutable float y1 = curve[3];
  immutable float x2 = curve[4];
  immutable float y2 = curve[5];
  immutable float cx1 = x1+2.0f/3.0f*(cx-x1);
  immutable float cy1 = y1+2.0f/3.0f*(cy-y1);
  immutable float cx2 = x2+2.0f/3.0f*(cx-x2);
  immutable float cy2 = y2+2.0f/3.0f*(cy-y2);
  float[8] cubic = void;
  cubic.ptr[0] = cx;
  cubic.ptr[1] = cy;
  cubic.ptr[2] = cx1;
  cubic.ptr[3] = cy1;
  cubic.ptr[4] = cx2;
  cubic.ptr[5] = cy2;
  cubic.ptr[6] = x2;
  cubic.ptr[7] = y2;
  nsvg__curveBounds(bounds, cubic.ptr);
}

void nsvg__getLocalBounds (float* bounds, NSVG.Shape* shape, const(float)* xform) {
  bool first = true;

  void addPoint (in float x, in float y) nothrow @trusted @nogc {
    if (!first) {
      bounds[0] = nsvg__minf(bounds[0], x);
      bounds[1] = nsvg__minf(bounds[1], y);
      bounds[2] = nsvg__maxf(bounds[2], x);
      bounds[3] = nsvg__maxf(bounds[3], y);
    } else {
      bounds[0] = bounds[2] = x;
      bounds[1] = bounds[3] = y;
      first = false;
    }
  }

  void addRect (in float x0, in float y0, in float x1, in float y1) nothrow @trusted @nogc {
    addPoint(x0, y0);
    addPoint(x1, y0);
    addPoint(x1, y1);
    addPoint(x0, y1);
  }

  float cx = 0, cy = 0;
  for (NSVG.Path* path = shape.paths; path !is null; path = path.next) {
    path.forEachCommand!false(delegate (NSVG.Command cmd, const(float)[] args) nothrow @trusted @nogc {
      import core.stdc.string : memmove;
      assert(args.length <= 6);
      float[8] xpt = void;
      // transform points
      foreach (immutable n; 0..args.length/2) {
        nsvg__xformPoint(&xpt.ptr[n*2+0], &xpt.ptr[n*2+1], args.ptr[n*2+0], args.ptr[n*2+1], xform);
      }
      // add to bounds
      final switch (cmd) {
        case NSVG.Command.MoveTo:
          cx = xpt.ptr[0];
          cy = xpt.ptr[1];
          break;
        case NSVG.Command.LineTo:
          addPoint(cx, cy);
          addPoint(xpt.ptr[0], xpt.ptr[1]);
          cx = xpt.ptr[0];
          cy = xpt.ptr[1];
          break;
        case NSVG.Command.QuadTo:
          memmove(xpt.ptr+2, xpt.ptr, 4); // make room for starting point
          xpt.ptr[0] = cx;
          xpt.ptr[1] = cy;
          float[4] curveBounds = void;
          nsvg__quadBounds(curveBounds.ptr, xpt.ptr);
          addRect(curveBounds.ptr[0], curveBounds.ptr[1], curveBounds.ptr[2], curveBounds.ptr[3]);
          cx = xpt.ptr[4];
          cy = xpt.ptr[5];
          break;
        case NSVG.Command.BezierTo:
          memmove(xpt.ptr+2, xpt.ptr, 6); // make room for starting point
          xpt.ptr[0] = cx;
          xpt.ptr[1] = cy;
          float[4] curveBounds = void;
          nsvg__curveBounds(curveBounds.ptr, xpt.ptr);
          addRect(curveBounds.ptr[0], curveBounds.ptr[1], curveBounds.ptr[2], curveBounds.ptr[3]);
          cx = xpt.ptr[6];
          cy = xpt.ptr[7];
          break;
      }
    });
    /*
    nsvg__xformPoint(&curve.ptr[0], &curve.ptr[1], path.pts[0], path.pts[1], xform);
    for (int i = 0; i < path.npts-1; i += 3) {
      nsvg__xformPoint(&curve.ptr[2], &curve.ptr[3], path.pts[(i+1)*2], path.pts[(i+1)*2+1], xform);
      nsvg__xformPoint(&curve.ptr[4], &curve.ptr[5], path.pts[(i+2)*2], path.pts[(i+2)*2+1], xform);
      nsvg__xformPoint(&curve.ptr[6], &curve.ptr[7], path.pts[(i+3)*2], path.pts[(i+3)*2+1], xform);
      nsvg__curveBounds(curveBounds.ptr, curve.ptr);
      if (first) {
        bounds[0] = curveBounds.ptr[0];
        bounds[1] = curveBounds.ptr[1];
        bounds[2] = curveBounds.ptr[2];
        bounds[3] = curveBounds.ptr[3];
        first = false;
      } else {
        bounds[0] = nsvg__minf(bounds[0], curveBounds.ptr[0]);
        bounds[1] = nsvg__minf(bounds[1], curveBounds.ptr[1]);
        bounds[2] = nsvg__maxf(bounds[2], curveBounds.ptr[2]);
        bounds[3] = nsvg__maxf(bounds[3], curveBounds.ptr[3]);
      }
      curve.ptr[0] = curve.ptr[6];
      curve.ptr[1] = curve.ptr[7];
    }
    */
  }
}

void nsvg__addShape (Parser* p) {
  Attrib* attr = nsvg__getAttr(p);
  float scale = 1.0f;
  NSVG.Shape* shape;
  NSVG.Path* path;
  int i;

  if (p.plist is null) return;

  shape = xalloc!(NSVG.Shape);
  if (shape is null) goto error;
  //memset(shape, 0, NSVG.Shape.sizeof);

  shape.id[] = attr.id[];
  scale = nsvg__getAverageScale(attr.xform.ptr);
  shape.strokeWidth = attr.strokeWidth*scale;
  shape.strokeDashOffset = attr.strokeDashOffset*scale;
  shape.strokeDashCount = cast(char)attr.strokeDashCount;
  for (i = 0; i < attr.strokeDashCount; i++) shape.strokeDashArray[i] = attr.strokeDashArray[i]*scale;
  shape.strokeLineJoin = attr.strokeLineJoin;
  shape.strokeLineCap = attr.strokeLineCap;
  shape.miterLimit = attr.miterLimit;
  shape.fillRule = attr.fillRule;
  shape.opacity = attr.opacity;

  shape.paths = p.plist;
  p.plist = null;


  shape.clip.count = attr.clipPathCount;
  if (shape.clip.count > 0) {
      import core.stdc.stdlib : malloc;
      import core.stdc.string : memcpy;
      shape.clip.index = xcalloc!NSVGclipPathIndex(attr.clipPathCount);

      if (shape.clip.index is null) goto error;

      memcpy(shape.clip.index, p.clipPathStack.ptr,
             attr.clipPathCount * NSVGclipPathIndex.sizeof);
  }

  // Calculate shape bounds
  shape.bounds.ptr[0] = shape.paths.bounds.ptr[0];
  shape.bounds.ptr[1] = shape.paths.bounds.ptr[1];
  shape.bounds.ptr[2] = shape.paths.bounds.ptr[2];
  shape.bounds.ptr[3] = shape.paths.bounds.ptr[3];
  for (path = shape.paths.next; path !is null; path = path.next) {
    shape.bounds.ptr[0] = nsvg__minf(shape.bounds.ptr[0], path.bounds[0]);
    shape.bounds.ptr[1] = nsvg__minf(shape.bounds.ptr[1], path.bounds[1]);
    shape.bounds.ptr[2] = nsvg__maxf(shape.bounds.ptr[2], path.bounds[2]);
    shape.bounds.ptr[3] = nsvg__maxf(shape.bounds.ptr[3], path.bounds[3]);
  }

  // Set fill
  if (attr.hasFill == 0) {
    shape.fill.type = NSVG.PaintType.None;
  } else if (attr.hasFill == 1) {
    shape.fill.type = NSVG.PaintType.Color;
    shape.fill.color = attr.fillColor;
    shape.fill.color |= cast(uint)(attr.fillOpacity*255)<<24;
  } else if (attr.hasFill == 2) {
    float[6] inv;
    float[4] localBounds;
    nsvg__xformInverse(inv.ptr, attr.xform.ptr);
    nsvg__getLocalBounds(localBounds.ptr, shape, inv.ptr);
    shape.fill.gradient = nsvg__createGradient(p, attr.fillGradient[], localBounds.ptr, &shape.fill.type);
    if (shape.fill.gradient is null) shape.fill.type = NSVG.PaintType.None;
  }

  // Set stroke
  if (attr.hasStroke == 0) {
    shape.stroke.type = NSVG.PaintType.None;
  } else if (attr.hasStroke == 1) {
    shape.stroke.type = NSVG.PaintType.Color;
    shape.stroke.color = attr.strokeColor;
    shape.stroke.color |= cast(uint)(attr.strokeOpacity*255)<<24;
  } else if (attr.hasStroke == 2) {
    float[6] inv;
    float[4] localBounds;
    nsvg__xformInverse(inv.ptr, attr.xform.ptr);
    nsvg__getLocalBounds(localBounds.ptr, shape, inv.ptr);
    shape.stroke.gradient = nsvg__createGradient(p, attr.strokeGradient[], localBounds.ptr, &shape.stroke.type);
    if (shape.stroke.gradient is null) shape.stroke.type = NSVG.PaintType.None;
  }

  // Set flags
  shape.flags = (attr.visible ? NSVG.Visible : 0x00);

  if (p.clipPath !is null) {
        shape.next = p.clipPath.shapes;
        p.clipPath.shapes = shape;
  } else {
      // Add to tail
      if (p.image.shapes is null)
        p.image.shapes = shape;
      else
        p.shapesTail.next = shape;

      p.shapesTail = shape;
  }

  return;

error:
  if (shape) {
    if(shape.clip.index) {
        import core.stdc.stdlib;
        free(shape.clip.index);
    }
    xfree(shape);
  }
}

void nsvg__addPath (Parser* p, bool closed) {
  Attrib* attr = nsvg__getAttr(p);

  if (p.nsflts < 4) return;

  if (closed) {
    auto cmd = cast(NSVG.Command)p.stream[0];
    if (cmd != NSVG.Command.MoveTo) assert(0, "NanoVega.SVG: invalid path");
    nsvg__lineTo(p, p.stream[1], p.stream[2]);
  }

  float cx = 0, cy = 0;
  float[4] bounds = void;
  bool first = true;

  NSVG.Path* path = xalloc!(NSVG.Path);
  if (path is null) goto error;
  //memset(path, 0, NSVG.Path.sizeof);

  path.stream = xcalloc!float(p.nsflts);
  if (path.stream is null) goto error;
  path.closed = closed;
  path.nsflts = p.nsflts;

  // transform path and calculate bounds
  void addPoint (in float x, in float y) nothrow @trusted @nogc {
    if (!first) {
      bounds[0] = nsvg__minf(bounds[0], x);
      bounds[1] = nsvg__minf(bounds[1], y);
      bounds[2] = nsvg__maxf(bounds[2], x);
      bounds[3] = nsvg__maxf(bounds[3], y);
    } else {
      bounds[0] = bounds[2] = x;
      bounds[1] = bounds[3] = y;
      first = false;
    }
  }

  void addRect (in float x0, in float y0, in float x1, in float y1) nothrow @trusted @nogc {
    addPoint(x0, y0);
    addPoint(x1, y0);
    addPoint(x1, y1);
    addPoint(x0, y1);
  }

  version(none) {
    foreach (immutable idx, float f; p.stream[0..p.nsflts]) {
      import core.stdc.stdio;
      printf("idx=%u; f=%g\n", cast(uint)idx, cast(double)f);
    }
  }

  for (int i = 0; i+3 <= p.nsflts; ) {
    int argc = 0; // pair of coords
    NSVG.Command cmd = cast(NSVG.Command)p.stream[i];
    final switch (cmd) {
      case NSVG.Command.MoveTo: argc = 1; break;
      case NSVG.Command.LineTo: argc = 1; break;
      case NSVG.Command.QuadTo: argc = 2; break;
      case NSVG.Command.BezierTo: argc = 3; break;
    }
    // copy command
    path.stream[i] = p.stream[i];
    ++i;
    auto starti = i;
    // transform points
    while (argc-- > 0) {
      nsvg__xformPoint(&path.stream[i+0], &path.stream[i+1], p.stream[i+0], p.stream[i+1], attr.xform.ptr);
      i += 2;
    }
    // do bounds
    final switch (cmd) {
      case NSVG.Command.MoveTo:
        cx = path.stream[starti+0];
        cy = path.stream[starti+1];
        break;
      case NSVG.Command.LineTo:
        addPoint(cx, cy);
        cx = path.stream[starti+0];
        cy = path.stream[starti+1];
        addPoint(cx, cy);
        break;
      case NSVG.Command.QuadTo:
        float[6] curve = void;
        curve.ptr[0] = cx;
        curve.ptr[1] = cy;
        curve.ptr[2..6] = path.stream[starti+0..starti+4];
        cx = path.stream[starti+2];
        cy = path.stream[starti+3];
        float[4] curveBounds = void;
        nsvg__quadBounds(curveBounds.ptr, curve.ptr);
        addRect(curveBounds.ptr[0], curveBounds.ptr[1], curveBounds.ptr[2], curveBounds.ptr[3]);
        break;
      case NSVG.Command.BezierTo:
        float[8] curve = void;
        curve.ptr[0] = cx;
        curve.ptr[1] = cy;
        curve.ptr[2..8] = path.stream[starti+0..starti+6];
        cx = path.stream[starti+4];
        cy = path.stream[starti+5];
        float[4] curveBounds = void;
        nsvg__curveBounds(curveBounds.ptr, curve.ptr);
        addRect(curveBounds.ptr[0], curveBounds.ptr[1], curveBounds.ptr[2], curveBounds.ptr[3]);
        break;
    }
  }
  path.bounds[0..4] = bounds[0..4];

  path.next = p.plist;
  p.plist = path;

  return;

error:
  if (path !is null) {
    if (path.stream !is null) xfree(path.stream);
    xfree(path);
  }
}

static NSVG.ClipPath* nsvg__createClipPath(const char* name, NSVGclipPathIndex index)
{
	NSVG.ClipPath* clipPath = xalloc!(NSVG.ClipPath);
	if (clipPath is null) return null;
	// memset(clipPath, 0, sizeof(NSVGclipPath));
        import core.stdc.string;
	strncpy(clipPath.id.ptr, name, 63);
	clipPath.id[63] = '\0';
	clipPath.index = index;
	return clipPath;
}

static NSVG.ClipPath* nsvg__findClipPath(Parser* p, const char* name)
{
	NSVGclipPathIndex i = 0;
	NSVG.ClipPath** link;

        import core.stdc.string;

	link = &p.image.clipPaths;
	while (*link !is null) {
		if (strcmp((*link).id.ptr, name) == 0) {
			break;
		}
		link = &(*link).next;
		i++;
	}
	if (*link is null) {
		*link = nsvg__createClipPath(name, i);
	}
	return *link;
}


// We roll our own string to float because the std library one uses locale and messes things up.
// special hack: stop at '\0' (actually, it stops on any non-digit, so no special code is required)
float nsvg__atof (const(char)[] s) nothrow @trusted @nogc {
  if (s.length == 0) return 0; // oops

  const(char)* cur = s.ptr;
  auto left = s.length;
  double res = 0.0, sign = 1.0;
  bool hasIntPart = false, hasFracPart = false;

  char peekChar () nothrow @trusted @nogc { pragma(inline, true); return (left > 0 ? *cur : '\x00'); }
  char getChar () nothrow @trusted @nogc { if (left > 0) { --left; return *cur++; } else return '\x00'; }

  // Parse optional sign
  switch (peekChar) {
    case '-': sign = -1; goto case;
    case '+': getChar(); break;
    default: break;
  }

  // Parse integer part
  if (nsvg__isdigit(peekChar)) {
    // Parse digit sequence
    hasIntPart = true;
    while (nsvg__isdigit(peekChar)) res = res*10.0+(getChar()-'0');
  }

  // Parse fractional part.
  if (peekChar == '.') {
    getChar(); // Skip '.'
    if (nsvg__isdigit(peekChar)) {
      // Parse digit sequence
      hasFracPart = true;
      int divisor = 1;
      long num = 0;
      while (nsvg__isdigit(peekChar)) {
        divisor *= 10;
        num = num*10+(getChar()-'0');
      }
      res += cast(double)num/divisor;
    }
  }

  // A valid number should have integer or fractional part.
  if (!hasIntPart && !hasFracPart) return 0;

  // Parse optional exponent
  if (peekChar == 'e' || peekChar == 'E') {
    getChar(); // skip 'E'
    // parse optional sign
    bool epositive = true;
    switch (peekChar) {
      case '-': epositive = false; goto case;
      case '+': getChar(); break;
      default: break;
    }
    int expPart = 0;
    while (nsvg__isdigit(peekChar)) expPart = expPart*10+(getChar()-'0');
    if (epositive) {
      foreach (immutable _; 0..expPart) res *= 10.0;
    } else {
      foreach (immutable _; 0..expPart) res /= 10.0;
    }
  }

  return cast(float)(res*sign);
}

// `it` should be big enough
// returns number of chars eaten
int nsvg__parseNumber (const(char)[] s, char[] it) {
  int i = 0;
  it[] = 0;

  const(char)[] os = s;

  // sign
  if (s.length && (s[0] == '-' || s[0] == '+')) {
    if (it.length-i > 1) it[i++] = s[0];
    s = s[1..$];
  }
  // integer part
  while (s.length && nsvg__isdigit(s[0])) {
    if (it.length-i > 1) it[i++] = s[0];
    s = s[1..$];
  }
  if (s.length && s[0] == '.') {
    // decimal point
    if (it.length-i > 1) it[i++] = s[0];
    s = s[1..$];
    // fraction part
    while (s.length && nsvg__isdigit(s[0])) {
      if (it.length-i > 1) it[i++] = s[0];
      s = s[1..$];
    }
  }
  // exponent
  if (s.length && (s[0] == 'e' || s[0] == 'E')) {
    if (it.length-i > 1) it[i++] = s[0];
    s = s[1..$];
    if (s.length && (s[0] == '-' || s[0] == '+')) {
      if (it.length-i > 1) it[i++] = s[0];
      s = s[1..$];
    }
    while (s.length && nsvg__isdigit(s[0])) {
      if (it.length-i > 1) it[i++] = s[0];
      s = s[1..$];
    }
  }

  return cast(int)(s.ptr-os.ptr);
}

// `it` should be big enough
int nsvg__getNextPathItem (const(char)[] s, char[] it) {
  int res = 0;
  it[] = '\0';
  // skip white spaces and commas
  while (res < s.length && (nsvg__isspace(s[res]) || s[res] == ',')) ++res;
  if (res >= s.length) return cast(int)s.length;
  if (s[res] == '-' || s[res] == '+' || s[res] == '.' || nsvg__isdigit(s[res])) {
    res += nsvg__parseNumber(s[res..$], it);
  } else if (s.length) {
    // Parse command
    it[0] = s[res++];
  }
  return res;
}

uint nsvg__parseColorHex (const(char)[] str) {
  char[12] tmp = 0;
  uint c = 0;
  ubyte r = 0, g = 0, b = 0;
  int n = 0;
  if (str.length) str = str[1..$]; // skip #
  // calculate number of characters
  while (n < str.length && !nsvg__isspace(str[n])) ++n;
  if (n == 3 || n == 6) {
    foreach (char ch; str[0..n]) {
      auto d0 = nsvg__hexdigit(ch);
      if (d0 < 0) break;
      c = c*16+d0;
    }
    if (n == 3) {
      c = (c&0xf)|((c&0xf0)<<4)|((c&0xf00)<<8);
      c |= c<<4;
    }
  }
  r = (c>>16)&0xff;
  g = (c>>8)&0xff;
  b = c&0xff;
  return NSVG.Paint.rgb(r, g, b);
}

uint nsvg__parseColorRGB (const(char)[] str) {
  int r = -1, g = -1, b = -1;
  const(char)[] s1, s2;
  assert(str.length > 4);
  xsscanf(str[4..$], "%d%[%%, \t]%d%[%%, \t]%d", r, s1, g, s2, b);
  if (s1[].xindexOf('%') >= 0) {
    return NSVG.Paint.rgb(cast(ubyte)((r*255)/100), cast(ubyte)((g*255)/100), cast(ubyte)((b*255)/100));
  } else {
    return NSVG.Paint.rgb(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b);
  }
}

struct NSVGNamedColor {
  string name;
  uint color;
}

static immutable NSVGNamedColor[147] nsvg__colors = [
  NSVGNamedColor("aliceblue", NSVG.Paint.rgb(240, 248, 255)),
  NSVGNamedColor("antiquewhite", NSVG.Paint.rgb(250, 235, 215)),
  NSVGNamedColor("aqua", NSVG.Paint.rgb( 0, 255, 255)),
  NSVGNamedColor("aquamarine", NSVG.Paint.rgb(127, 255, 212)),
  NSVGNamedColor("azure", NSVG.Paint.rgb(240, 255, 255)),
  NSVGNamedColor("beige", NSVG.Paint.rgb(245, 245, 220)),
  NSVGNamedColor("bisque", NSVG.Paint.rgb(255, 228, 196)),
  NSVGNamedColor("black", NSVG.Paint.rgb( 0, 0, 0)), // basic color
  NSVGNamedColor("blanchedalmond", NSVG.Paint.rgb(255, 235, 205)),
  NSVGNamedColor("blue", NSVG.Paint.rgb( 0, 0, 255)), // basic color
  NSVGNamedColor("blueviolet", NSVG.Paint.rgb(138, 43, 226)),
  NSVGNamedColor("brown", NSVG.Paint.rgb(165, 42, 42)),
  NSVGNamedColor("burlywood", NSVG.Paint.rgb(222, 184, 135)),
  NSVGNamedColor("cadetblue", NSVG.Paint.rgb( 95, 158, 160)),
  NSVGNamedColor("chartreuse", NSVG.Paint.rgb(127, 255, 0)),
  NSVGNamedColor("chocolate", NSVG.Paint.rgb(210, 105, 30)),
  NSVGNamedColor("coral", NSVG.Paint.rgb(255, 127, 80)),
  NSVGNamedColor("cornflowerblue", NSVG.Paint.rgb(100, 149, 237)),
  NSVGNamedColor("cornsilk", NSVG.Paint.rgb(255, 248, 220)),
  NSVGNamedColor("crimson", NSVG.Paint.rgb(220, 20, 60)),
  NSVGNamedColor("cyan", NSVG.Paint.rgb( 0, 255, 255)), // basic color
  NSVGNamedColor("darkblue", NSVG.Paint.rgb( 0, 0, 139)),
  NSVGNamedColor("darkcyan", NSVG.Paint.rgb( 0, 139, 139)),
  NSVGNamedColor("darkgoldenrod", NSVG.Paint.rgb(184, 134, 11)),
  NSVGNamedColor("darkgray", NSVG.Paint.rgb(169, 169, 169)),
  NSVGNamedColor("darkgreen", NSVG.Paint.rgb( 0, 100, 0)),
  NSVGNamedColor("darkgrey", NSVG.Paint.rgb(169, 169, 169)),
  NSVGNamedColor("darkkhaki", NSVG.Paint.rgb(189, 183, 107)),
  NSVGNamedColor("darkmagenta", NSVG.Paint.rgb(139, 0, 139)),
  NSVGNamedColor("darkolivegreen", NSVG.Paint.rgb( 85, 107, 47)),
  NSVGNamedColor("darkorange", NSVG.Paint.rgb(255, 140, 0)),
  NSVGNamedColor("darkorchid", NSVG.Paint.rgb(153, 50, 204)),
  NSVGNamedColor("darkred", NSVG.Paint.rgb(139, 0, 0)),
  NSVGNamedColor("darksalmon", NSVG.Paint.rgb(233, 150, 122)),
  NSVGNamedColor("darkseagreen", NSVG.Paint.rgb(143, 188, 143)),
  NSVGNamedColor("darkslateblue", NSVG.Paint.rgb( 72, 61, 139)),
  NSVGNamedColor("darkslategray", NSVG.Paint.rgb( 47, 79, 79)),
  NSVGNamedColor("darkslategrey", NSVG.Paint.rgb( 47, 79, 79)),
  NSVGNamedColor("darkturquoise", NSVG.Paint.rgb( 0, 206, 209)),
  NSVGNamedColor("darkviolet", NSVG.Paint.rgb(148, 0, 211)),
  NSVGNamedColor("deeppink", NSVG.Paint.rgb(255, 20, 147)),
  NSVGNamedColor("deepskyblue", NSVG.Paint.rgb( 0, 191, 255)),
  NSVGNamedColor("dimgray", NSVG.Paint.rgb(105, 105, 105)),
  NSVGNamedColor("dimgrey", NSVG.Paint.rgb(105, 105, 105)),
  NSVGNamedColor("dodgerblue", NSVG.Paint.rgb( 30, 144, 255)),
  NSVGNamedColor("firebrick", NSVG.Paint.rgb(178, 34, 34)),
  NSVGNamedColor("floralwhite", NSVG.Paint.rgb(255, 250, 240)),
  NSVGNamedColor("forestgreen", NSVG.Paint.rgb( 34, 139, 34)),
  NSVGNamedColor("fuchsia", NSVG.Paint.rgb(255, 0, 255)),
  NSVGNamedColor("gainsboro", NSVG.Paint.rgb(220, 220, 220)),
  NSVGNamedColor("ghostwhite", NSVG.Paint.rgb(248, 248, 255)),
  NSVGNamedColor("gold", NSVG.Paint.rgb(255, 215, 0)),
  NSVGNamedColor("goldenrod", NSVG.Paint.rgb(218, 165, 32)),
  NSVGNamedColor("gray", NSVG.Paint.rgb(128, 128, 128)), // basic color
  NSVGNamedColor("green", NSVG.Paint.rgb( 0, 128, 0)), // basic color
  NSVGNamedColor("greenyellow", NSVG.Paint.rgb(173, 255, 47)),
  NSVGNamedColor("grey", NSVG.Paint.rgb(128, 128, 128)), // basic color
  NSVGNamedColor("honeydew", NSVG.Paint.rgb(240, 255, 240)),
  NSVGNamedColor("hotpink", NSVG.Paint.rgb(255, 105, 180)),
  NSVGNamedColor("indianred", NSVG.Paint.rgb(205, 92, 92)),
  NSVGNamedColor("indigo", NSVG.Paint.rgb( 75, 0, 130)),
  NSVGNamedColor("ivory", NSVG.Paint.rgb(255, 255, 240)),
  NSVGNamedColor("khaki", NSVG.Paint.rgb(240, 230, 140)),
  NSVGNamedColor("lavender", NSVG.Paint.rgb(230, 230, 250)),
  NSVGNamedColor("lavenderblush", NSVG.Paint.rgb(255, 240, 245)),
  NSVGNamedColor("lawngreen", NSVG.Paint.rgb(124, 252, 0)),
  NSVGNamedColor("lemonchiffon", NSVG.Paint.rgb(255, 250, 205)),
  NSVGNamedColor("lightblue", NSVG.Paint.rgb(173, 216, 230)),
  NSVGNamedColor("lightcoral", NSVG.Paint.rgb(240, 128, 128)),
  NSVGNamedColor("lightcyan", NSVG.Paint.rgb(224, 255, 255)),
  NSVGNamedColor("lightgoldenrodyellow", NSVG.Paint.rgb(250, 250, 210)),
  NSVGNamedColor("lightgray", NSVG.Paint.rgb(211, 211, 211)),
  NSVGNamedColor("lightgreen", NSVG.Paint.rgb(144, 238, 144)),
  NSVGNamedColor("lightgrey", NSVG.Paint.rgb(211, 211, 211)),
  NSVGNamedColor("lightpink", NSVG.Paint.rgb(255, 182, 193)),
  NSVGNamedColor("lightsalmon", NSVG.Paint.rgb(255, 160, 122)),
  NSVGNamedColor("lightseagreen", NSVG.Paint.rgb( 32, 178, 170)),
  NSVGNamedColor("lightskyblue", NSVG.Paint.rgb(135, 206, 250)),
  NSVGNamedColor("lightslategray", NSVG.Paint.rgb(119, 136, 153)),
  NSVGNamedColor("lightslategrey", NSVG.Paint.rgb(119, 136, 153)),
  NSVGNamedColor("lightsteelblue", NSVG.Paint.rgb(176, 196, 222)),
  NSVGNamedColor("lightyellow", NSVG.Paint.rgb(255, 255, 224)),
  NSVGNamedColor("lime", NSVG.Paint.rgb( 0, 255, 0)),
  NSVGNamedColor("limegreen", NSVG.Paint.rgb( 50, 205, 50)),
  NSVGNamedColor("linen", NSVG.Paint.rgb(250, 240, 230)),
  NSVGNamedColor("magenta", NSVG.Paint.rgb(255, 0, 255)), // basic color
  NSVGNamedColor("maroon", NSVG.Paint.rgb(128, 0, 0)),
  NSVGNamedColor("mediumaquamarine", NSVG.Paint.rgb(102, 205, 170)),
  NSVGNamedColor("mediumblue", NSVG.Paint.rgb( 0, 0, 205)),
  NSVGNamedColor("mediumorchid", NSVG.Paint.rgb(186, 85, 211)),
  NSVGNamedColor("mediumpurple", NSVG.Paint.rgb(147, 112, 219)),
  NSVGNamedColor("mediumseagreen", NSVG.Paint.rgb( 60, 179, 113)),
  NSVGNamedColor("mediumslateblue", NSVG.Paint.rgb(123, 104, 238)),
  NSVGNamedColor("mediumspringgreen", NSVG.Paint.rgb( 0, 250, 154)),
  NSVGNamedColor("mediumturquoise", NSVG.Paint.rgb( 72, 209, 204)),
  NSVGNamedColor("mediumvioletred", NSVG.Paint.rgb(199, 21, 133)),
  NSVGNamedColor("midnightblue", NSVG.Paint.rgb( 25, 25, 112)),
  NSVGNamedColor("mintcream", NSVG.Paint.rgb(245, 255, 250)),
  NSVGNamedColor("mistyrose", NSVG.Paint.rgb(255, 228, 225)),
  NSVGNamedColor("moccasin", NSVG.Paint.rgb(255, 228, 181)),
  NSVGNamedColor("navajowhite", NSVG.Paint.rgb(255, 222, 173)),
  NSVGNamedColor("navy", NSVG.Paint.rgb( 0, 0, 128)),
  NSVGNamedColor("oldlace", NSVG.Paint.rgb(253, 245, 230)),
  NSVGNamedColor("olive", NSVG.Paint.rgb(128, 128, 0)),
  NSVGNamedColor("olivedrab", NSVG.Paint.rgb(107, 142, 35)),
  NSVGNamedColor("orange", NSVG.Paint.rgb(255, 165, 0)),
  NSVGNamedColor("orangered", NSVG.Paint.rgb(255, 69, 0)),
  NSVGNamedColor("orchid", NSVG.Paint.rgb(218, 112, 214)),
  NSVGNamedColor("palegoldenrod", NSVG.Paint.rgb(238, 232, 170)),
  NSVGNamedColor("palegreen", NSVG.Paint.rgb(152, 251, 152)),
  NSVGNamedColor("paleturquoise", NSVG.Paint.rgb(175, 238, 238)),
  NSVGNamedColor("palevioletred", NSVG.Paint.rgb(219, 112, 147)),
  NSVGNamedColor("papayawhip", NSVG.Paint.rgb(255, 239, 213)),
  NSVGNamedColor("peachpuff", NSVG.Paint.rgb(255, 218, 185)),
  NSVGNamedColor("peru", NSVG.Paint.rgb(205, 133, 63)),
  NSVGNamedColor("pink", NSVG.Paint.rgb(255, 192, 203)),
  NSVGNamedColor("plum", NSVG.Paint.rgb(221, 160, 221)),
  NSVGNamedColor("powderblue", NSVG.Paint.rgb(176, 224, 230)),
  NSVGNamedColor("purple", NSVG.Paint.rgb(128, 0, 128)),
  NSVGNamedColor("red", NSVG.Paint.rgb(255, 0, 0)), // basic color
  NSVGNamedColor("rosybrown", NSVG.Paint.rgb(188, 143, 143)),
  NSVGNamedColor("royalblue", NSVG.Paint.rgb( 65, 105, 225)),
  NSVGNamedColor("saddlebrown", NSVG.Paint.rgb(139, 69, 19)),
  NSVGNamedColor("salmon", NSVG.Paint.rgb(250, 128, 114)),
  NSVGNamedColor("sandybrown", NSVG.Paint.rgb(244, 164, 96)),
  NSVGNamedColor("seagreen", NSVG.Paint.rgb( 46, 139, 87)),
  NSVGNamedColor("seashell", NSVG.Paint.rgb(255, 245, 238)),
  NSVGNamedColor("sienna", NSVG.Paint.rgb(160, 82, 45)),
  NSVGNamedColor("silver", NSVG.Paint.rgb(192, 192, 192)),
  NSVGNamedColor("skyblue", NSVG.Paint.rgb(135, 206, 235)),
  NSVGNamedColor("slateblue", NSVG.Paint.rgb(106, 90, 205)),
  NSVGNamedColor("slategray", NSVG.Paint.rgb(112, 128, 144)),
  NSVGNamedColor("slategrey", NSVG.Paint.rgb(112, 128, 144)),
  NSVGNamedColor("snow", NSVG.Paint.rgb(255, 250, 250)),
  NSVGNamedColor("springgreen", NSVG.Paint.rgb( 0, 255, 127)),
  NSVGNamedColor("steelblue", NSVG.Paint.rgb( 70, 130, 180)),
  NSVGNamedColor("tan", NSVG.Paint.rgb(210, 180, 140)),
  NSVGNamedColor("teal", NSVG.Paint.rgb( 0, 128, 128)),
  NSVGNamedColor("thistle", NSVG.Paint.rgb(216, 191, 216)),
  NSVGNamedColor("tomato", NSVG.Paint.rgb(255, 99, 71)),
  NSVGNamedColor("turquoise", NSVG.Paint.rgb( 64, 224, 208)),
  NSVGNamedColor("violet", NSVG.Paint.rgb(238, 130, 238)),
  NSVGNamedColor("wheat", NSVG.Paint.rgb(245, 222, 179)),
  NSVGNamedColor("white", NSVG.Paint.rgb(255, 255, 255)), // basic color
  NSVGNamedColor("whitesmoke", NSVG.Paint.rgb(245, 245, 245)),
  NSVGNamedColor("yellow", NSVG.Paint.rgb(255, 255, 0)), // basic color
  NSVGNamedColor("yellowgreen", NSVG.Paint.rgb(154, 205, 50)),
];

enum nsvg__color_name_maxlen = () {
  int res = 0;
  foreach (const ref known; nsvg__colors) if (res < known.name.length) res = cast(int)known.name.length;
  return res;
}();


// `s0` and `s1` are never empty here
// `s0` is always lowercased
int xstrcmp (const(char)[] s0, const(char)[] s1) {
  /*
  const(char)* sp0 = s0.ptr;
  const(char)* sp1 = s1.ptr;
  foreach (; 0..(s0.length < s1.length ? s0.length : s1.length)) {
    int c1 = cast(int)(*sp1++);
    if (c1 >= 'A' && c1 <= 'Z') c1 += 32; // poor man's tolower
    if (auto diff = cast(int)(*sp0++)-c1) return diff;
  }
  // equals so far
  if (s0.length < s1.length) return -1;
  if (s0.length > s1.length) return 1;
  return 0;
  */
  import core.stdc.string : memcmp;
  if (auto diff = memcmp(s0.ptr, s1.ptr, (s0.length < s1.length ? s0.length : s1.length))) return diff;
  // equals so far
  if (s0.length < s1.length) return -1;
  if (s0.length > s1.length) return 1;
  return 0;
}


uint nsvg__parseColorName (const(char)[] str) {
  if (str.length == 0 || str.length > nsvg__color_name_maxlen) return NSVG.Paint.rgb(128, 128, 128);
  // check if `str` contains only letters, and convert it to lowercase
  char[nsvg__color_name_maxlen] slow = void;
  foreach (immutable cidx, char ch; str) {
    if (ch >= 'A' && ch <= 'Z') ch += 32; // poor man's tolower
    if (ch < 'a' || ch > 'z') return NSVG.Paint.rgb(128, 128, 128); // alas
    slow.ptr[cidx] = ch;
  }
  int low = 0;
  int high = cast(int)nsvg__colors.length-1;
  while (low <= high) {
    int med = (low+high)/2;
    assert(med >= 0 && med < nsvg__colors.length);
    int res = xstrcmp(nsvg__colors.ptr[med].name, str);
         if (res < 0) low = med+1;
    else if (res > 0) high = med-1;
    else return nsvg__colors.ptr[med].color;
  }
  return NSVG.Paint.rgb(128, 128, 128);
}

uint nsvg__parseColor (const(char)[] str) {
  while (str.length && str[0] <= ' ') str = str[1..$];
  if (str.length >= 1 && str[0] == '#') return nsvg__parseColorHex(str);
  if (str.length >= 4 && str[0] == 'r' && str[1] == 'g' && str[2] == 'b' && str[3] == '(') return nsvg__parseColorRGB(str);
  return nsvg__parseColorName(str);
}

float nsvg__parseOpacity (const(char)[] str) {
  float val = 0;
  xsscanf(str, "%f", val);
  if (val < 0.0f) val = 0.0f;
  if (val > 1.0f) val = 1.0f;
  return val;
}

float nsvg__parseMiterLimit (const(char)[] str) {
  float val = 0;
  xsscanf(str, "%f", val);
  if (val < 0.0f) val = 0.0f;
  return val;
}

Units nsvg__parseUnits (const(char)[] units) {
  if (units.length && units.ptr[0] == '%') return Units.percent;
  if (units.length == 2) {
    if (units.ptr[0] == 'p' && units.ptr[1] == 'x') return Units.px;
    if (units.ptr[0] == 'p' && units.ptr[1] == 't') return Units.pt;
    if (units.ptr[0] == 'p' && units.ptr[1] == 'c') return Units.pc;
    if (units.ptr[0] == 'm' && units.ptr[1] == 'm') return Units.mm;
    if (units.ptr[0] == 'c' && units.ptr[1] == 'm') return Units.cm;
    if (units.ptr[0] == 'i' && units.ptr[1] == 'n') return Units.in_;
    if (units.ptr[0] == 'e' && units.ptr[1] == 'm') return Units.em;
    if (units.ptr[0] == 'e' && units.ptr[1] == 'x') return Units.ex;
  }
  return Units.user;
}

Coordinate nsvg__parseCoordinateRaw (const(char)[] str) {
  Coordinate coord = Coordinate(0, Units.user);
  const(char)[] units;
  xsscanf(str, "%f%s", coord.value, units);
  coord.units = nsvg__parseUnits(units);
  return coord;
}

Coordinate nsvg__coord (float v, Units units) {
  Coordinate coord = Coordinate(v, units);
  return coord;
}

float nsvg__parseCoordinate (Parser* p, const(char)[] str, float orig, float length) {
  Coordinate coord = nsvg__parseCoordinateRaw(str);
  return nsvg__convertToPixels(p, coord, orig, length);
}

int nsvg__parseTransformArgs (const(char)[] str, float* args, int maxNa, int* na) {
  usize end, ptr;
  char[65] it = void;

  assert(str.length);
  *na = 0;

  ptr = 0;
  while (ptr < str.length && str[ptr] != '(') ++ptr;
  if (ptr >= str.length) return 1;

  end = ptr;
  while (end < str.length && str[end] != ')') ++end;
  if (end >= str.length) return 1;

  while (ptr < end) {
    if (str[ptr] == '-' || str[ptr] == '+' || str[ptr] == '.' || nsvg__isdigit(str[ptr])) {
      if (*na >= maxNa) return 0;
      ptr += nsvg__parseNumber(str[ptr..end], it[]);
      args[(*na)++] = nsvg__atof(it[]); // `it` is guaranteed to be asciiz, and `nsvg__atof()` will stop
    } else {
      ++ptr;
    }
  }
  return cast(int)end; // fuck off, 64bit
}


int nsvg__parseMatrix (float* xform, const(char)[] str) {
  float[6] t = void;
  int na = 0;
  int len = nsvg__parseTransformArgs(str, t.ptr, 6, &na);
  if (na != 6) return len;
  xform[0..6] = t[];
  return len;
}

int nsvg__parseTranslate (float* xform, const(char)[] str) {
  float[2] args = void;
  float[6] t = void;
  int na = 0;
  int len = nsvg__parseTransformArgs(str, args.ptr, 2, &na);
  if (na == 1) args[1] = 0.0;
  nsvg__xformSetTranslation(t.ptr, args.ptr[0], args.ptr[1]);
  xform[0..6] = t[];
  return len;
}

int nsvg__parseScale (float* xform, const(char)[] str) {
  float[2] args = void;
  int na = 0;
  float[6] t = void;
  int len = nsvg__parseTransformArgs(str, args.ptr, 2, &na);
  if (na == 1) args.ptr[1] = args.ptr[0];
  nsvg__xformSetScale(t.ptr, args.ptr[0], args.ptr[1]);
  xform[0..6] = t[];
  return len;
}

int nsvg__parseSkewX (float* xform, const(char)[] str) {
  float[1] args = void;
  int na = 0;
  float[6] t = void;
  int len = nsvg__parseTransformArgs(str, args.ptr, 1, &na);
  nsvg__xformSetSkewX(t.ptr, args.ptr[0]/180.0f*NSVG_PI);
  xform[0..6] = t[];
  return len;
}

int nsvg__parseSkewY (float* xform, const(char)[] str) {
  float[1] args = void;
  int na = 0;
  float[6] t = void;
  int len = nsvg__parseTransformArgs(str, args.ptr, 1, &na);
  nsvg__xformSetSkewY(t.ptr, args.ptr[0]/180.0f*NSVG_PI);
  xform[0..6] = t[];
  return len;
}

int nsvg__parseRotate (float* xform, const(char)[] str) {
  float[3] args = void;
  int na = 0;
  float[6] m = void;
  float[6] t = void;
  int len = nsvg__parseTransformArgs(str, args.ptr, 3, &na);
  if (na == 1) args.ptr[1] = args.ptr[2] = 0.0f;
  nsvg__xformIdentity(m.ptr);

  if (na > 1) {
    nsvg__xformSetTranslation(t.ptr, -args.ptr[1], -args.ptr[2]);
    nsvg__xformMultiply(m.ptr, t.ptr);
  }

  nsvg__xformSetRotation(t.ptr, args.ptr[0]/180.0f*NSVG_PI);
  nsvg__xformMultiply(m.ptr, t.ptr);

  if (na > 1) {
    nsvg__xformSetTranslation(t.ptr, args.ptr[1], args.ptr[2]);
    nsvg__xformMultiply(m.ptr, t.ptr);
  }

  xform[0..6] = m[];

  return len;
}

bool startsWith (const(char)[] str, const(char)[] sw) {
  pragma(inline, true);
  return (sw.length <= str.length && str[0..sw.length] == sw[]);
}

void nsvg__parseTransform (float* xform, const(char)[] str) {
  float[6] t = void;
  nsvg__xformIdentity(xform);
  while (str.length) {
    int len;
         if (startsWith(str, "matrix")) len = nsvg__parseMatrix(t.ptr, str);
    else if (startsWith(str, "translate")) len = nsvg__parseTranslate(t.ptr, str);
    else if (startsWith(str, "scale")) len = nsvg__parseScale(t.ptr, str);
    else if (startsWith(str, "rotate")) len = nsvg__parseRotate(t.ptr, str);
    else if (startsWith(str, "skewX")) len = nsvg__parseSkewX(t.ptr, str);
    else if (startsWith(str, "skewY")) len = nsvg__parseSkewY(t.ptr, str);
    else { str = str[1..$]; continue; }
    str = str[len..$];
    nsvg__xformPremultiply(xform, t.ptr);
  }
}

// `id` should be prealloced
void nsvg__parseUrl (char[] id, const(char)[] str) {
  int i = 0;
  if (str.length >= 4) {
    str = str[4..$]; // "url(";
    if (str.length && str[0] == '#') str = str[1..$];
    while (str.length && str[0] != ')') {
      if (id.length-i > 1) id[i++] = str[0];
      str = str[1..$];
    }
  }
  if (id.length-i > 0) id[i] = '\0';
}

NSVG.LineCap nsvg__parseLineCap (const(char)[] str) {
  if (str == "butt") return NSVG.LineCap.Butt;
  if (str == "round") return NSVG.LineCap.Round;
  if (str == "square") return NSVG.LineCap.Square;
  // TODO: handle inherit.
  return NSVG.LineCap.Butt;
}

NSVG.LineJoin nsvg__parseLineJoin (const(char)[] str) {
  if (str == "miter") return NSVG.LineJoin.Miter;
  if (str == "round") return NSVG.LineJoin.Round;
  if (str == "bevel") return NSVG.LineJoin.Bevel;
  // TODO: handle inherit.
  return NSVG.LineJoin.Miter;
}

NSVG.FillRule nsvg__parseFillRule (const(char)[] str) {
  if (str == "nonzero") return NSVG.FillRule.NonZero;
  if (str == "evenodd") return NSVG.FillRule.EvenOdd;
  // TODO: handle inherit.
  return NSVG.FillRule.EvenOdd;
}


int nsvg__parseStrokeDashArray (Parser* p, const(char)[] str, float* strokeDashArray) {
  char[65] item = 0;
  int count = 0;
  float sum = 0.0f;

  int nsvg__getNextDashItem () {
    int n = 0;
    item[] = '\0';
    // skip white spaces and commas
    while (str.length && (nsvg__isspace(str[0]) || str[0] == ',')) str = str[1..$];
    // advance until whitespace, comma or end
    while (str.length && (!nsvg__isspace(str[0]) && str[0] != ',')) {
      if (item.length-n > 1) item[n++] = str[0];
      str = str[1..$];
    }
    return n;
  }

  // Handle "none"
  if (!str.length || str[0] == 'n') return 0;

  // Parse dashes
  while (str.length) {
    auto len = nsvg__getNextDashItem();
    if (len < 1) break;
    if (count < NSVG_MAX_DASHES) strokeDashArray[count++] = fabsf(nsvg__parseCoordinate(p, item[0..len], 0.0f, nsvg__actualLength(p)));
  }

  foreach (int i; 0..count) sum += strokeDashArray[i];
  if (sum <= 1e-6f) count = 0;

  return count;
}

const(char)[] trimLeft (const(char)[] s, char ech=0) {
  usize pos = 0;
  while (pos < s.length) {
    if (s.ptr[pos] <= ' ') { ++pos; continue; }
    if (ech && s.ptr[pos] == ech) { ++pos; continue; }
    if (s.ptr[pos] == '/' && s.length-pos > 1 && s.ptr[pos+1] == '*') {
      pos += 2;
      while (s.length-pos > 1 && !(s.ptr[pos] == '*' && s.ptr[pos+1] == '/')) ++pos;
      if ((pos += 2) > s.length) pos = s.length;
      continue;
    }
    break;
  }
  return s[pos..$];
}

static const(char)[] trimRight (const(char)[] s, char ech=0) {
  usize pos = 0;
  while (pos < s.length) {
    if (s.ptr[pos] <= ' ' || (ech && s.ptr[pos] == ech)) {
      if (s[pos..$].trimLeft(ech).length == 0) return s[0..pos];
    } else if (s.ptr[pos] == '/' && s.length-pos > 1 && s.ptr[pos+1] == '*') {
      if (s[pos..$].trimLeft(ech).length == 0) return s[0..pos];
    }
    ++pos;
  }
  return s;
}

version(nanosvg_crappy_stylesheet_parser) {
Style* findStyle (Parser* p, char fch, const(char)[] name) {
  if (name.length == 0) return null;
  foreach (ref st; p.styles[0..p.styleCount]) {
    if (st.name.length < 2 || st.name.ptr[0] != fch) continue;
    if (st.name[1..$] == name) return &st;
  }
  return null;
}

void nsvg__parseClassOrId (Parser* p, char lch, const(char)[] str) {
  while (str.length) {
    while (str.length && str.ptr[0] <= ' ') str = str[1..$];
    if (str.length == 0) break;
    usize pos = 1;
    while (pos < str.length && str.ptr[pos] > ' ') ++pos;
    version(nanosvg_debug_styles) { import std.stdio; writeln("class to find: ", lch, str[0..pos].quote); }
    if (auto st = p.findStyle(lch, str[0..pos])) {
      version(nanosvg_debug_styles) { import std.stdio; writeln("class: [", str[0..pos], "]; value: ", st.value.quote); }
      nsvg__parseStyle(p, st.value);
    }
    str = str[pos..$];
  }
}
}

bool nsvg__parseAttr (Parser* p, const(char)[] name, const(char)[] value) {
  float[6] xform = void;
  Attrib* attr = nsvg__getAttr(p);
  if (attr is null) return false; //???

  if (name == "style") {
    nsvg__parseStyle(p, value);
  } else if (name == "display") {
    if (value == "none") attr.visible = 0;
    // Don't reset .visible on display:inline, one display:none hides the whole subtree
  } else if (name == "fill") {
    if (value == "none") {
      attr.hasFill = 0;
    } else if (startsWith(value, "url(")) {
      attr.hasFill = 2;
      nsvg__parseUrl(attr.fillGradient[], value);
    } else {
      attr.hasFill = 1;
      attr.fillColor = nsvg__parseColor(value);
    }
  } else if (name == "opacity") {
    attr.opacity = nsvg__parseOpacity(value);
  } else if (name == "fill-opacity") {
    attr.fillOpacity = nsvg__parseOpacity(value);
  } else if (name == "stroke") {
    if (value == "none") {
      attr.hasStroke = 0;
    } else if (startsWith(value, "url(")) {
      attr.hasStroke = 2;
      nsvg__parseUrl(attr.strokeGradient[], value);
    } else {
      attr.hasStroke = 1;
      attr.strokeColor = nsvg__parseColor(value);
    }
  } else if (name == "stroke-width") {
    attr.strokeWidth = nsvg__parseCoordinate(p, value, 0.0f, nsvg__actualLength(p));
  } else if (name == "stroke-dasharray") {
    attr.strokeDashCount = nsvg__parseStrokeDashArray(p, value, attr.strokeDashArray.ptr);
  } else if (name == "stroke-dashoffset") {
    attr.strokeDashOffset = nsvg__parseCoordinate(p, value, 0.0f, nsvg__actualLength(p));
  } else if (name == "stroke-opacity") {
    attr.strokeOpacity = nsvg__parseOpacity(value);
  } else if (name == "stroke-linecap") {
    attr.strokeLineCap = nsvg__parseLineCap(value);
  } else if (name == "stroke-linejoin") {
    attr.strokeLineJoin = nsvg__parseLineJoin(value);
  } else if (name == "stroke-miterlimit") {
    attr.miterLimit = nsvg__parseMiterLimit(value);
  } else if (name == "fill-rule") {
    attr.fillRule = nsvg__parseFillRule(value);
  } else if (name == "font-size") {
    attr.fontSize = nsvg__parseCoordinate(p, value, 0.0f, nsvg__actualLength(p));
  } else if (name == "transform") {
    nsvg__parseTransform(xform.ptr, value);
    nsvg__xformPremultiply(attr.xform.ptr, xform.ptr);
  } else if (name == "clip-path") {
    if(value.length > 4 && value[0 .. 4] == "url(" && attr.clipPathCount < 255) {
        char[64] clipName;
        nsvg__parseUrl(clipName[], value);
        NSVG.ClipPath* clipPath= nsvg__findClipPath(p, clipName.ptr);
        p.clipPathStack[attr.clipPathCount++] = clipPath.index;
    }
  } else if (name == "stop-color") {
    attr.stopColor = nsvg__parseColor(value);
  } else if (name == "stop-opacity") {
    attr.stopOpacity = nsvg__parseOpacity(value);
  } else if (name == "offset") {
    attr.stopOffset = nsvg__parseCoordinate(p, value, 0.0f, 1.0f);
  } else if (name == "class") {
    version(nanosvg_crappy_stylesheet_parser) nsvg__parseClassOrId(p, '.', value);
  } else if (name == "id") {
    // apply classes here too
    version(nanosvg_crappy_stylesheet_parser) nsvg__parseClassOrId(p, '#', value);
    attr.id[] = 0;
    if (value.length > attr.id.length-1) value = value[0..attr.id.length-1];
    attr.id[0..value.length] = value[];
  } else {
    return false;
  }
  return true;
}

bool nsvg__parseNameValue (Parser* p, const(char)[] str) {
  const(char)[] name;

  str = str.trimLeft;
  usize pos = 0;
  while (pos < str.length && str.ptr[pos] != ':') {
    if (str.length-pos > 1 && str.ptr[pos] == '/' && str.ptr[pos+1] == '*') {
      pos += 2;
      while (str.length-pos > 1 && !(str.ptr[pos] == '*' && str.ptr[pos+1] == '/')) ++pos;
      if ((pos += 2) > str.length) pos = str.length;
    } else {
      ++pos;
    }
  }

  name = str[0..pos].trimLeft.trimRight;
  if (name.length == 0) return false;

  str = str[pos+(pos < str.length ? 1 : 0)..$].trimLeft.trimRight(';');

  version(nanosvg_debug_styles) { import std.stdio; writeln("** name=", name.quote, "; value=", str.quote); }

  return nsvg__parseAttr(p, name, str);
}

void nsvg__parseStyle (Parser* p, const(char)[] str) {
  while (str.length) {
    str = str.trimLeft;
    usize pos = 0;
    while (pos < str.length && str[pos] != ';') {
      if (str.length-pos > 1 && str.ptr[pos] == '/' && str.ptr[pos+1] == '*') {
        pos += 2;
        while (str.length-pos > 1 && !(str.ptr[pos] == '*' && str.ptr[pos+1] == '/')) ++pos;
        if ((pos += 2) > str.length) pos = str.length;
      } else {
        ++pos;
      }
    }
    const(char)[] val = trimRight(str[0..pos]);
    version(nanosvg_debug_styles) { import std.stdio; writeln("style: ", val.quote); }
    str = str[pos+(pos < str.length ? 1 : 0)..$];
    if (val.length > 0) nsvg__parseNameValue(p, val);
  }
}

void nsvg__parseAttribs (Parser* p, AttrList attr) {
  for (usize i = 0; attr.length-i >= 2; i += 2) {
         if (attr[i] == "style") nsvg__parseStyle(p, attr[i+1]);
    else if (attr[i] == "class") { version(nanosvg_crappy_stylesheet_parser) nsvg__parseClassOrId(p, '.', attr[i+1]); }
    else nsvg__parseAttr(p, attr[i], attr[i+1]);
  }
}

int nsvg__getArgsPerElement (char cmd) {
  switch (cmd) {
    case 'v': case 'V':
    case 'h': case 'H':
      return 1;
    case 'm': case 'M':
    case 'l': case 'L':
    case 't': case 'T':
      return 2;
    case 'q': case 'Q':
    case 's': case 'S':
      return 4;
    case 'c': case 'C':
      return 6;
    case 'a': case 'A':
      return 7;
    default:
  }
  return 0;
}

void nsvg__pathMoveTo (Parser* p, float* cpx, float* cpy, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathMoveTo: args=", args[0..2]); }
  if (rel) { *cpx += args[0]; *cpy += args[1]; } else { *cpx = args[0]; *cpy = args[1]; }
  nsvg__moveTo(p, *cpx, *cpy);
}

void nsvg__pathLineTo (Parser* p, float* cpx, float* cpy, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathLineTo: args=", args[0..2]); }
  if (rel) { *cpx += args[0]; *cpy += args[1]; } else { *cpx = args[0]; *cpy = args[1]; }
  nsvg__lineTo(p, *cpx, *cpy);
}

void nsvg__pathHLineTo (Parser* p, float* cpx, float* cpy, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathHLineTo: args=", args[0..1]); }
  if (rel) *cpx += args[0]; else *cpx = args[0];
  nsvg__lineTo(p, *cpx, *cpy);
}

void nsvg__pathVLineTo (Parser* p, float* cpx, float* cpy, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathVLineTo: args=", args[0..1]); }
  if (rel) *cpy += args[0]; else *cpy = args[0];
  nsvg__lineTo(p, *cpx, *cpy);
}

void nsvg__pathCubicBezTo (Parser* p, float* cpx, float* cpy, float* cpx2, float* cpy2, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathCubicBezTo: args=", args[0..6]); }
  float cx1 = args[0];
  float cy1 = args[1];
  float cx2 = args[2];
  float cy2 = args[3];
  float x2 = args[4];
  float y2 = args[5];

  if (rel) {
    cx1 += *cpx;
    cy1 += *cpy;
    cx2 += *cpx;
    cy2 += *cpy;
    x2 += *cpx;
    y2 += *cpy;
  }

  nsvg__cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);

  *cpx2 = cx2;
  *cpy2 = cy2;
  *cpx = x2;
  *cpy = y2;
}

void nsvg__pathCubicBezShortTo (Parser* p, float* cpx, float* cpy, float* cpx2, float* cpy2, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathCubicBezShortTo: args=", args[0..4]); }

  float cx2 = args[0];
  float cy2 = args[1];
  float x2 = args[2];
  float y2 = args[3];
  immutable float x1 = *cpx;
  immutable float y1 = *cpy;

  if (rel) {
    cx2 += *cpx;
    cy2 += *cpy;
    x2 += *cpx;
    y2 += *cpy;
  }

  immutable float cx1 = 2*x1-*cpx2;
  immutable float cy1 = 2*y1-*cpy2;

  nsvg__cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);

  *cpx2 = cx2;
  *cpy2 = cy2;
  *cpx = x2;
  *cpy = y2;
}

void nsvg__pathQuadBezTo (Parser* p, float* cpx, float* cpy, float* cpx2, float* cpy2, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathQuadBezTo: args=", args[0..4]); }

  float cx = args[0];
  float cy = args[1];
  float x2 = args[2];
  float y2 = args[3];
  immutable float x1 = *cpx;
  immutable float y1 = *cpy;

  if (rel) {
    cx += *cpx;
    cy += *cpy;
    x2 += *cpx;
    y2 += *cpy;
  }

  version(nanosvg_only_cubic_beziers) {
    // convert to cubic bezier
    immutable float cx1 = x1+2.0f/3.0f*(cx-x1);
    immutable float cy1 = y1+2.0f/3.0f*(cy-y1);
    immutable float cx2 = x2+2.0f/3.0f*(cx-x2);
    immutable float cy2 = y2+2.0f/3.0f*(cy-y2);
    nsvg__cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
  } else {
    nsvg__quadBezTo(p, cx, cy, x2, y2);
  }

  *cpx2 = cx;
  *cpy2 = cy;
  *cpx = x2;
  *cpy = y2;
}

void nsvg__pathQuadBezShortTo (Parser* p, float* cpx, float* cpy, float* cpx2, float* cpy2, const(float)* args, bool rel) {
  debug(nanosvg) { import std.stdio; writeln("nsvg__pathQuadBezShortTo: args=", args[0..2]); }

  float x2 = args[0];
  float y2 = args[1];
  immutable float x1 = *cpx;
  immutable float y1 = *cpy;

  if (rel) {
    x2 += *cpx;
    y2 += *cpy;
  }

  immutable float cx = 2*x1-*cpx2;
  immutable float cy = 2*y1-*cpy2;

  version(nanosvg_only_cubic_beziers) {
    // convert to cubic bezier
    immutable float cx1 = x1+2.0f/3.0f*(cx-x1);
    immutable float cy1 = y1+2.0f/3.0f*(cy-y1);
    immutable float cx2 = x2+2.0f/3.0f*(cx-x2);
    immutable float cy2 = y2+2.0f/3.0f*(cy-y2);
    nsvg__cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
  } else {
    nsvg__quadBezTo(p, cx, cy, x2, y2);
  }

  *cpx2 = cx;
  *cpy2 = cy;
  *cpx = x2;
  *cpy = y2;
}

float nsvg__sqr (in float x) pure nothrow @safe @nogc { pragma(inline, true); return x*x; }
float nsvg__vmag (in float x, float y) nothrow @safe @nogc { pragma(inline, true); return sqrtf(x*x+y*y); }

float nsvg__vecrat (float ux, float uy, float vx, float vy) nothrow @safe @nogc {
  pragma(inline, true);
  return (ux*vx+uy*vy)/(nsvg__vmag(ux, uy)*nsvg__vmag(vx, vy));
}

float nsvg__vecang (float ux, float uy, float vx, float vy) nothrow @safe @nogc {
  float r = nsvg__vecrat(ux, uy, vx, vy);
  if (r < -1.0f) r = -1.0f;
  if (r > 1.0f) r = 1.0f;
  return (ux*vy < uy*vx ? -1.0f : 1.0f)*acosf(r);
}

void nsvg__pathArcTo (Parser* p, float* cpx, float* cpy, const(float)* args, bool rel) {
  // ported from canvg (https://code.google.com/p/canvg/)
  float rx = fabsf(args[0]); // y radius
  float ry = fabsf(args[1]); // x radius
  immutable float rotx = args[2]/180.0f*NSVG_PI; // x rotation engle
  immutable float fa = (fabsf(args[3]) > 1e-6 ? 1 : 0); // large arc
  immutable float fs = (fabsf(args[4]) > 1e-6 ? 1 : 0); // sweep direction
  immutable float x1 = *cpx; // start point
  immutable float y1 = *cpy;

  // end point
  float x2 = args[5];
  float y2 = args[6];

  if (rel) { x2 += *cpx; y2 += *cpy; }

  float dx = x1-x2;
  float dy = y1-y2;
  immutable float d0 = sqrtf(dx*dx+dy*dy);
  if (d0 < 1e-6f || rx < 1e-6f || ry < 1e-6f) {
    // the arc degenerates to a line
    nsvg__lineTo(p, x2, y2);
    *cpx = x2;
    *cpy = y2;
    return;
  }

  immutable float sinrx = sinf(rotx);
  immutable float cosrx = cosf(rotx);

  // convert to center point parameterization
  // http://www.w3.org/TR/SVG11/implnote.html#ArcImplementationNotes
  // 1) Compute x1', y1'
  immutable float x1p = cosrx*dx/2.0f+sinrx*dy/2.0f;
  immutable float y1p = -sinrx*dx/2.0f+cosrx*dy/2.0f;
  immutable float d1 = nsvg__sqr(x1p)/nsvg__sqr(rx)+nsvg__sqr(y1p)/nsvg__sqr(ry);
  if (d1 > 1) {
    immutable float d2 = sqrtf(d1);
    rx *= d2;
    ry *= d2;
  }
  // 2) Compute cx', cy'
  float s = 0.0f;
  float sa = nsvg__sqr(rx)*nsvg__sqr(ry)-nsvg__sqr(rx)*nsvg__sqr(y1p)-nsvg__sqr(ry)*nsvg__sqr(x1p);
  immutable float sb = nsvg__sqr(rx)*nsvg__sqr(y1p)+nsvg__sqr(ry)*nsvg__sqr(x1p);
  if (sa < 0.0f) sa = 0.0f;
  if (sb > 0.0f) s = sqrtf(sa/sb);
  if (fa == fs) s = -s;
  immutable float cxp = s*rx*y1p/ry;
  immutable float cyp = s*-ry*x1p/rx;

  // 3) Compute cx,cy from cx',cy'
  immutable float cx = (x1+x2)/2.0f+cosrx*cxp-sinrx*cyp;
  immutable float cy = (y1+y2)/2.0f+sinrx*cxp+cosrx*cyp;

  // 4) Calculate theta1, and delta theta.
  immutable float ux = (x1p-cxp)/rx;
  immutable float uy = (y1p-cyp)/ry;
  immutable float vx = (-x1p-cxp)/rx;
  immutable float vy = (-y1p-cyp)/ry;
  immutable float a1 = nsvg__vecang(1.0f, 0.0f, ux, uy); // Initial angle
  float da = nsvg__vecang(ux, uy, vx, vy); // Delta angle

       if (fs == 0 && da > 0) da -= 2*NSVG_PI;
  else if (fs == 1 && da < 0) da += 2*NSVG_PI;

  float[6] t = void;
  // approximate the arc using cubic spline segments
  t.ptr[0] = cosrx; t.ptr[1] = sinrx;
  t.ptr[2] = -sinrx; t.ptr[3] = cosrx;
  t.ptr[4] = cx; t.ptr[5] = cy;

  // split arc into max 90 degree segments
  // the loop assumes an iteration per end point (including start and end), this +1
  immutable ndivs = cast(int)(fabsf(da)/(NSVG_PI*0.5f)+1.0f);
  immutable float hda = (da/cast(float)ndivs)/2.0f;
  float kappa = fabsf(4.0f/3.0f*(1.0f-cosf(hda))/sinf(hda));
  if (da < 0.0f) kappa = -kappa;

  immutable float ndivsf = cast(float)ndivs;
  float px = 0, py = 0, ptanx = 0, ptany = 0;
  foreach (int i; 0..ndivs+1) {
    float x = void, y = void, tanx = void, tany = void;
    immutable float a = a1+da*(i/ndivsf);
    immutable float loopdx = cosf(a);
    immutable float loopdy = sinf(a);
    nsvg__xformPoint(&x, &y, loopdx*rx, loopdy*ry, t.ptr); // position
    nsvg__xformVec(&tanx, &tany, -loopdy*rx*kappa, loopdx*ry*kappa, t.ptr); // tangent
    if (i > 0) nsvg__cubicBezTo(p, px+ptanx, py+ptany, x-tanx, y-tany, x, y);
    px = x;
    py = y;
    ptanx = tanx;
    ptany = tany;
  }

  *cpx = x2;
  *cpy = y2;
}

void nsvg__parsePath (Parser* p, AttrList attr) {
  const(char)[] s = null;
  char cmd = '\0';
  float[10] args = void;
  int nargs;
  int rargs = 0;
  float cpx = void, cpy = void, cpx2 = void, cpy2 = void;
  bool closedFlag = false;
  char[65] item = void;

  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (attr[i] == "d") {
      s = attr[i+1];
    } else {
      const(char)[][2] tmp;
      tmp[0] = attr[i];
      tmp[1] = attr[i+1];
      nsvg__parseAttribs(p, tmp[]);
    }
  }

  if (s.length) {
    nsvg__resetPath(p);
    cpx = 0;
    cpy = 0;
    cpx2 = 0;
    cpy2 = 0;
    closedFlag = false;
    nargs = 0;

    while (s.length) {
      auto skl = nsvg__getNextPathItem(s, item[]);
      if (skl < s.length) s = s[skl..$]; else s = s[$..$];
      debug(nanosvg) { import std.stdio; writeln(":: ", item.fromAsciiz.quote, " : ", s.quote); }
      if (!item[0]) break;
      if (nsvg__isnum(item[0])) {
        if (nargs < 10) {
          args[nargs++] = nsvg__atof(item[]);
        }
        if (nargs >= rargs) {
          switch (cmd) {
            case 'm': case 'M': // move to
              nsvg__pathMoveTo(p, &cpx, &cpy, args.ptr, (cmd == 'm' ? 1 : 0));
              // Moveto can be followed by multiple coordinate pairs,
              // which should be treated as linetos.
              cmd = (cmd == 'm' ? 'l' : 'L');
              rargs = nsvg__getArgsPerElement(cmd);
              cpx2 = cpx; cpy2 = cpy;
              break;
            case 'l': case 'L': // line to
              nsvg__pathLineTo(p, &cpx, &cpy, args.ptr, (cmd == 'l' ? 1 : 0));
              cpx2 = cpx; cpy2 = cpy;
              break;
            case 'H': case 'h': // horizontal line to
              nsvg__pathHLineTo(p, &cpx, &cpy, args.ptr, (cmd == 'h' ? 1 : 0));
              cpx2 = cpx; cpy2 = cpy;
              break;
            case 'V': case 'v': // vertical line to
              nsvg__pathVLineTo(p, &cpx, &cpy, args.ptr, (cmd == 'v' ? 1 : 0));
              cpx2 = cpx; cpy2 = cpy;
              break;
            case 'C': case 'c': // cubic bezier
              nsvg__pathCubicBezTo(p, &cpx, &cpy, &cpx2, &cpy2, args.ptr, (cmd == 'c' ? 1 : 0));
              break;
            case 'S': case 's': // "short" cubic bezier
              nsvg__pathCubicBezShortTo(p, &cpx, &cpy, &cpx2, &cpy2, args.ptr, (cmd == 's' ? 1 : 0));
              break;
            case 'Q': case 'q': // quadratic bezier
              nsvg__pathQuadBezTo(p, &cpx, &cpy, &cpx2, &cpy2, args.ptr, (cmd == 'q' ? 1 : 0));
              break;
            case 'T': case 't': // "short" quadratic bezier
              nsvg__pathQuadBezShortTo(p, &cpx, &cpy, &cpx2, &cpy2, args.ptr, cmd == 't' ? 1 : 0);
              break;
            case 'A': case 'a': // arc
              nsvg__pathArcTo(p, &cpx, &cpy, args.ptr, cmd == 'a' ? 1 : 0);
              cpx2 = cpx; cpy2 = cpy;
              break;
            default:
              if (nargs >= 2) {
                cpx = args[nargs-2];
                cpy = args[nargs-1];
                cpx2 = cpx;
                cpy2 = cpy;
              }
              break;
          }
          nargs = 0;
        }
      } else {
        cmd = item[0];
        rargs = nsvg__getArgsPerElement(cmd);
        if (cmd == 'M' || cmd == 'm') {
          // commit path
          if (p.nsflts > 0) nsvg__addPath(p, closedFlag);
          // start new subpath
          nsvg__resetPath(p);
          closedFlag = false;
          nargs = 0;
        } else if (cmd == 'Z' || cmd == 'z') {
          closedFlag = true;
          // commit path
          if (p.nsflts > 0) {
            // move current point to first point
            if ((cast(NSVG.Command)p.stream[0]) != NSVG.Command.MoveTo) assert(0, "NanoVega.SVG: invalid path");
            cpx = p.stream[1];
            cpy = p.stream[2];
            cpx2 = cpx;
            cpy2 = cpy;
            nsvg__addPath(p, closedFlag);
          }
          // start new subpath
          nsvg__resetPath(p);
          nsvg__moveTo(p, cpx, cpy);
          closedFlag = false;
          nargs = 0;
        }
      }
    }
    // commit path
    if (p.nsflts) nsvg__addPath(p, closedFlag);
  }

  nsvg__addShape(p);
}

void nsvg__parseRect (Parser* p, AttrList attr) {
  float x = 0.0f;
  float y = 0.0f;
  float w = 0.0f;
  float h = 0.0f;
  float rx = -1.0f; // marks not set
  float ry = -1.0f;

  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (!nsvg__parseAttr(p, attr[i], attr[i+1])) {
           if (attr[i] == "x") x = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigX(p), nsvg__actualWidth(p));
      else if (attr[i] == "y") y = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigY(p), nsvg__actualHeight(p));
      else if (attr[i] == "width") w = nsvg__parseCoordinate(p, attr[i+1], 0.0f, nsvg__actualWidth(p));
      else if (attr[i] == "height") h = nsvg__parseCoordinate(p, attr[i+1], 0.0f, nsvg__actualHeight(p));
      else if (attr[i] == "rx") rx = fabsf(nsvg__parseCoordinate(p, attr[i+1], 0.0f, nsvg__actualWidth(p)));
      else if (attr[i] == "ry") ry = fabsf(nsvg__parseCoordinate(p, attr[i+1], 0.0f, nsvg__actualHeight(p)));
    }
  }

  if (rx < 0.0f && ry > 0.0f) rx = ry;
  if (ry < 0.0f && rx > 0.0f) ry = rx;
  if (rx < 0.0f) rx = 0.0f;
  if (ry < 0.0f) ry = 0.0f;
  if (rx > w/2.0f) rx = w/2.0f;
  if (ry > h/2.0f) ry = h/2.0f;

  if (w != 0.0f && h != 0.0f) {
    nsvg__resetPath(p);

    if (rx < 0.00001f || ry < 0.0001f) {
      nsvg__moveTo(p, x, y);
      nsvg__lineTo(p, x+w, y);
      nsvg__lineTo(p, x+w, y+h);
      nsvg__lineTo(p, x, y+h);
    } else {
      // Rounded rectangle
      nsvg__moveTo(p, x+rx, y);
      nsvg__lineTo(p, x+w-rx, y);
      nsvg__cubicBezTo(p, x+w-rx*(1-NSVG_KAPPA90), y, x+w, y+ry*(1-NSVG_KAPPA90), x+w, y+ry);
      nsvg__lineTo(p, x+w, y+h-ry);
      nsvg__cubicBezTo(p, x+w, y+h-ry*(1-NSVG_KAPPA90), x+w-rx*(1-NSVG_KAPPA90), y+h, x+w-rx, y+h);
      nsvg__lineTo(p, x+rx, y+h);
      nsvg__cubicBezTo(p, x+rx*(1-NSVG_KAPPA90), y+h, x, y+h-ry*(1-NSVG_KAPPA90), x, y+h-ry);
      nsvg__lineTo(p, x, y+ry);
      nsvg__cubicBezTo(p, x, y+ry*(1-NSVG_KAPPA90), x+rx*(1-NSVG_KAPPA90), y, x+rx, y);
    }

    nsvg__addPath(p, 1);

    nsvg__addShape(p);
  }
}

void nsvg__parseCircle (Parser* p, AttrList attr) {
  float cx = 0.0f;
  float cy = 0.0f;
  float r = 0.0f;

  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (!nsvg__parseAttr(p, attr[i], attr[i+1])) {
           if (attr[i] == "cx") cx = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigX(p), nsvg__actualWidth(p));
      else if (attr[i] == "cy") cy = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigY(p), nsvg__actualHeight(p));
      else if (attr[i] == "r") r = fabsf(nsvg__parseCoordinate(p, attr[i+1], 0.0f, nsvg__actualLength(p)));
    }
  }

  if (r > 0.0f) {
    nsvg__resetPath(p);

    nsvg__moveTo(p, cx+r, cy);
    nsvg__cubicBezTo(p, cx+r, cy+r*NSVG_KAPPA90, cx+r*NSVG_KAPPA90, cy+r, cx, cy+r);
    nsvg__cubicBezTo(p, cx-r*NSVG_KAPPA90, cy+r, cx-r, cy+r*NSVG_KAPPA90, cx-r, cy);
    nsvg__cubicBezTo(p, cx-r, cy-r*NSVG_KAPPA90, cx-r*NSVG_KAPPA90, cy-r, cx, cy-r);
    nsvg__cubicBezTo(p, cx+r*NSVG_KAPPA90, cy-r, cx+r, cy-r*NSVG_KAPPA90, cx+r, cy);

    nsvg__addPath(p, 1);

    nsvg__addShape(p);
  }
}

void nsvg__parseEllipse (Parser* p, AttrList attr) {
  float cx = 0.0f;
  float cy = 0.0f;
  float rx = 0.0f;
  float ry = 0.0f;

  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (!nsvg__parseAttr(p, attr[i], attr[i+1])) {
           if (attr[i] == "cx") cx = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigX(p), nsvg__actualWidth(p));
      else if (attr[i] == "cy") cy = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigY(p), nsvg__actualHeight(p));
      else if (attr[i] == "rx") rx = fabsf(nsvg__parseCoordinate(p, attr[i+1], 0.0f, nsvg__actualWidth(p)));
      else if (attr[i] == "ry") ry = fabsf(nsvg__parseCoordinate(p, attr[i+1], 0.0f, nsvg__actualHeight(p)));
    }
  }

  if (rx > 0.0f && ry > 0.0f) {
    nsvg__resetPath(p);

    nsvg__moveTo(p, cx+rx, cy);
    nsvg__cubicBezTo(p, cx+rx, cy+ry*NSVG_KAPPA90, cx+rx*NSVG_KAPPA90, cy+ry, cx, cy+ry);
    nsvg__cubicBezTo(p, cx-rx*NSVG_KAPPA90, cy+ry, cx-rx, cy+ry*NSVG_KAPPA90, cx-rx, cy);
    nsvg__cubicBezTo(p, cx-rx, cy-ry*NSVG_KAPPA90, cx-rx*NSVG_KAPPA90, cy-ry, cx, cy-ry);
    nsvg__cubicBezTo(p, cx+rx*NSVG_KAPPA90, cy-ry, cx+rx, cy-ry*NSVG_KAPPA90, cx+rx, cy);

    nsvg__addPath(p, 1);

    nsvg__addShape(p);
  }
}

void nsvg__parseLine (Parser* p, AttrList attr) {
  float x1 = 0.0;
  float y1 = 0.0;
  float x2 = 0.0;
  float y2 = 0.0;

  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (!nsvg__parseAttr(p, attr[i], attr[i+1])) {
           if (attr[i] == "x1") x1 = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigX(p), nsvg__actualWidth(p));
      else if (attr[i] == "y1") y1 = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigY(p), nsvg__actualHeight(p));
      else if (attr[i] == "x2") x2 = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigX(p), nsvg__actualWidth(p));
      else if (attr[i] == "y2") y2 = nsvg__parseCoordinate(p, attr[i+1], nsvg__actualOrigY(p), nsvg__actualHeight(p));
    }
  }

  nsvg__resetPath(p);

  nsvg__moveTo(p, x1, y1);
  nsvg__lineTo(p, x2, y2);

  nsvg__addPath(p, 0);

  nsvg__addShape(p);
}

void nsvg__parsePoly (Parser* p, AttrList attr, bool closeFlag) {
  float[2] args = void;
  int nargs, npts = 0;
  char[65] item = 0;

  nsvg__resetPath(p);

  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (!nsvg__parseAttr(p, attr[i], attr[i+1])) {
      if (attr[i] == "points") {
        const(char)[]s = attr[i+1];
        nargs = 0;
        while (s.length) {
          auto skl = nsvg__getNextPathItem(s, item[]);
          if (skl < s.length) s = s[skl..$]; else s = s[$..$];
          args[nargs++] = nsvg__atof(item[]);
          if (nargs >= 2) {
            if (npts == 0) nsvg__moveTo(p, args[0], args[1]); else nsvg__lineTo(p, args[0], args[1]);
            nargs = 0;
            ++npts;
          }
        }
      }
    }
  }

  nsvg__addPath(p, closeFlag);

  nsvg__addShape(p);
}

void nsvg__parseSVG (Parser* p, AttrList attr) {
  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (!nsvg__parseAttr(p, attr[i], attr[i+1])) {
      if (attr[i] == "width") {
        p.image.width = nsvg__parseCoordinate(p, attr[i+1], 0.0f, p.canvaswdt);
        //{ import core.stdc.stdio; printf("(%d) w=%d [%.*s]\n", p.canvaswdt, cast(int)p.image.width, cast(uint)attr[i+1].length, attr[i+1].ptr); }
      } else if (attr[i] == "height") {
        p.image.height = nsvg__parseCoordinate(p, attr[i+1], 0.0f, p.canvashgt);
      } else if (attr[i] == "viewBox") {
        xsscanf(attr[i+1], "%f%*[%%, \t]%f%*[%%, \t]%f%*[%%, \t]%f", p.viewMinx, p.viewMiny, p.viewWidth, p.viewHeight);
      } else if (attr[i] == "preserveAspectRatio") {
        if (attr[i+1].xindexOf("none") >= 0) {
          // No uniform scaling
          p.alignType = NSVG_ALIGN_NONE;
        } else {
          // Parse X align
               if (attr[i+1].xindexOf("xMin") >= 0) p.alignX = NSVG_ALIGN_MIN;
          else if (attr[i+1].xindexOf("xMid") >= 0) p.alignX = NSVG_ALIGN_MID;
          else if (attr[i+1].xindexOf("xMax") >= 0) p.alignX = NSVG_ALIGN_MAX;
          // Parse X align
               if (attr[i+1].xindexOf("yMin") >= 0) p.alignY = NSVG_ALIGN_MIN;
          else if (attr[i+1].xindexOf("yMid") >= 0) p.alignY = NSVG_ALIGN_MID;
          else if (attr[i+1].xindexOf("yMax") >= 0) p.alignY = NSVG_ALIGN_MAX;
          // Parse meet/slice
          p.alignType = NSVG_ALIGN_MEET;
          if (attr[i+1].xindexOf("slice") >= 0) p.alignType = NSVG_ALIGN_SLICE;
        }
      }
    }
  }
}

void nsvg__parseGradient (Parser* p, AttrList attr, NSVG.PaintType type) {
  GradientData* grad = xalloc!GradientData;
  if (grad is null) return;
  //memset(grad, 0, GradientData.sizeof);
  grad.units = GradientUnits.Object;
  grad.type = type;
  if (grad.type == NSVG.PaintType.LinearGradient) {
    grad.linear.x1 = nsvg__coord(0.0f, Units.percent);
    grad.linear.y1 = nsvg__coord(0.0f, Units.percent);
    grad.linear.x2 = nsvg__coord(100.0f, Units.percent);
    grad.linear.y2 = nsvg__coord(0.0f, Units.percent);
  } else if (grad.type == NSVG.PaintType.RadialGradient) {
    grad.radial.cx = nsvg__coord(50.0f, Units.percent);
    grad.radial.cy = nsvg__coord(50.0f, Units.percent);
    grad.radial.r = nsvg__coord(50.0f, Units.percent);
  }

  nsvg__xformIdentity(grad.xform.ptr);

  for (usize i = 0; attr.length-i >= 2; i += 2) {
    if (attr[i] == "id") {
      grad.id[] = 0;
      const(char)[] s = attr[i+1];
      if (s.length > grad.id.length-1) s = s[0..grad.id.length-1];
      grad.id[0..s.length] = s[];
    } else if (!nsvg__parseAttr(p, attr[i], attr[i+1])) {
           if (attr[i] == "gradientUnits") { if (attr[i+1] == "objectBoundingBox") grad.units = GradientUnits.Object; else grad.units = GradientUnits.User; }
      else if (attr[i] == "gradientTransform") { nsvg__parseTransform(grad.xform.ptr, attr[i+1]); }
      else if (attr[i] == "cx") { grad.radial.cx = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "cy") { grad.radial.cy = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "r") { grad.radial.r = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "fx") { grad.radial.fx = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "fy") { grad.radial.fy = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "x1") { grad.linear.x1 = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "y1") { grad.linear.y1 = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "x2") { grad.linear.x2 = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "y2") { grad.linear.y2 = nsvg__parseCoordinateRaw(attr[i+1]); }
      else if (attr[i] == "spreadMethod") {
             if (attr[i+1] == "pad") grad.spread = NSVG.SpreadType.Pad;
        else if (attr[i+1] == "reflect") grad.spread = NSVG.SpreadType.Reflect;
        else if (attr[i+1] == "repeat") grad.spread = NSVG.SpreadType.Repeat;
      } else if (attr[i] == "xlink:href") {
        grad.ref_[] = 0;
        const(char)[] s = attr[i+1];
        if (s.length > 0 && s.ptr[0] == '#') s = s[1..$]; // remove '#'
        if (s.length > grad.ref_.length-1) s = s[0..grad.ref_.length-1];
        grad.ref_[0..s.length] = s[];
      }
    }
  }

  grad.next = p.gradients;
  p.gradients = grad;
}

void nsvg__parseGradientStop (Parser* p, AttrList attr) {
  import core.stdc.stdlib : realloc;

  Attrib* curAttr = nsvg__getAttr(p);
  GradientData* grad;
  NSVG.GradientStop* stop;
  int idx;

  curAttr.stopOffset = 0;
  curAttr.stopColor = 0;
  curAttr.stopOpacity = 1.0f;

  for (usize i = 0; attr.length-i >= 2; i += 2) nsvg__parseAttr(p, attr[i], attr[i+1]);

  // Add stop to the last gradient.
  grad = p.gradients;
  if (grad is null) return;

  ++grad.nstops;
  grad.stops = cast(NSVG.GradientStop*)realloc(grad.stops, NSVG.GradientStop.sizeof*grad.nstops+256);
  if (grad.stops is null) assert(0, "nanosvg: out of memory");

  // Insert
  idx = grad.nstops-1;
  foreach (int i; 0..grad.nstops-1) {
    if (curAttr.stopOffset < grad.stops[i].offset) {
      idx = i;
      break;
    }
  }
  if (idx != grad.nstops-1) {
    for (int i = grad.nstops-1; i > idx; --i) grad.stops[i] = grad.stops[i-1];
  }

  stop = grad.stops+idx;
  stop.color = curAttr.stopColor;
  stop.color |= cast(uint)(curAttr.stopOpacity*255)<<24;
  stop.offset = curAttr.stopOffset;
}

void nsvg__startElement (void* ud, const(char)[] el, AttrList attr) {
  Parser* p = cast(Parser*)ud;

  version(nanosvg_debug_styles) { import std.stdio; writeln("tagB: ", el.quote); }
  version(nanosvg_crappy_stylesheet_parser) { p.inStyle = (el == "style"); }

  if (p.defsFlag) {
    // Skip everything but gradients in defs
    if (el == "linearGradient") {
      nsvg__parseGradient(p, attr, NSVG.PaintType.LinearGradient);
    } else if (el == "radialGradient") {
      nsvg__parseGradient(p, attr, NSVG.PaintType.RadialGradient);
    } else if (el == "stop") {
      nsvg__parseGradientStop(p, attr);
    }
    return;
  }

  if (el == "g") {
    nsvg__pushAttr(p);
    nsvg__parseAttribs(p, attr);
  } else if (el == "path") {
    if (p.pathFlag) return; // do not allow nested paths
    p.pathFlag = true;
    nsvg__pushAttr(p);
    nsvg__parsePath(p, attr);
    nsvg__popAttr(p);
  } else if (el == "rect") {
    nsvg__pushAttr(p);
    nsvg__parseRect(p, attr);
    nsvg__popAttr(p);
  } else if (el == "circle") {
    nsvg__pushAttr(p);
    nsvg__parseCircle(p, attr);
    nsvg__popAttr(p);
  } else if (el == "ellipse") {
    nsvg__pushAttr(p);
    nsvg__parseEllipse(p, attr);
    nsvg__popAttr(p);
  } else if (el == "line")  {
    nsvg__pushAttr(p);
    nsvg__parseLine(p, attr);
    nsvg__popAttr(p);
  } else if (el == "polyline")  {
    nsvg__pushAttr(p);
    nsvg__parsePoly(p, attr, 0);
    nsvg__popAttr(p);
  } else if (el == "polygon")  {
    nsvg__pushAttr(p);
    nsvg__parsePoly(p, attr, 1);
    nsvg__popAttr(p);
  } else  if (el == "linearGradient") {
    nsvg__parseGradient(p, attr, NSVG.PaintType.LinearGradient);
  } else if (el == "radialGradient") {
    nsvg__parseGradient(p, attr, NSVG.PaintType.RadialGradient);
  } else if (el == "stop") {
    nsvg__parseGradientStop(p, attr);
  } else if (el == "defs") {
    p.defsFlag = true;
  } else if (el == "svg") {
    nsvg__parseSVG(p, attr);
  } else if (el == "clipPath") {
    nsvg__pushAttr(p);
    foreach(a; attr) {
        if(a == "id") {
            p.clipPath = nsvg__findClipPath(p, a.ptr);
            break;
        }
    }
  }
}

void nsvg__endElement (void* ud, const(char)[] el) {
  version(nanosvg_debug_styles) { import std.stdio; writeln("tagE: ", el.quote); }
  Parser* p = cast(Parser*)ud;
       if (el == "g") nsvg__popAttr(p);
  else if (el == "path") p.pathFlag = false;
  else if (el == "defs") p.defsFlag = false;
  else if (el == "clipPath") {
    if(p.clipPath !is null) {
        NSVG.Shape* shape = p.clipPath.shapes;
        while(shape !is null) {
            shape.fill.type = NSVG.PaintType.Color;
            shape.stroke.type = NSVG.PaintType.None;
            shape = shape.next;
        }
        p.clipPath = null;
    }
    nsvg__popAttr(p);
  }
  else if (el == "style") { version(nanosvg_crappy_stylesheet_parser) p.inStyle = false; }
}

void nsvg__content (void* ud, const(char)[] s) {
  version(nanosvg_crappy_stylesheet_parser) {
    Parser* p = cast(Parser*)ud;
    if (!p.inStyle) {
      return;
    }
    // cheap hack
    for (;;) {
      while (s.length && s.ptr[0] <= ' ') s = s[1..$];
      if (!s.startsWith("<![CDATA[")) break;
      s = s[9..$];
    }
    for (;;) {
      while (s.length && (s[$-1] <= ' ' || s[$-1] == '>')) s = s[0..$-1];
      if (s.length > 1 && s[$-2..$] == "]]") s = s[0..$-2]; else break;
    }
    version(nanosvg_debug_styles) { import std.stdio; writeln("ctx: ", s.quote); }
    uint tokensAdded = 0;
    while (s.length) {
      if (s.length > 1 && s.ptr[0] == '/' && s.ptr[1] == '*') {
        // comment
        s = s[2..$];
        while (s.length > 1 && !(s.ptr[0] == '*' && s.ptr[1] == '/')) s = s[1..$];
        if (s.length <= 2) break;
        s = s[2..$];
        continue;
      } else if (s.ptr[0] <= ' ') {
        while (s.length && s.ptr[0] <= ' ') s = s[1..$];
        continue;
      }
      //version(nanosvg_debug_styles) { import std.stdio; writeln("::: ", s.quote); }
      if (s.ptr[0] == '{') {
        usize pos = 1;
        while (pos < s.length && s.ptr[pos] != '}') {
          if (s.length-pos > 1 && s.ptr[pos] == '/' && s.ptr[pos+1] == '*') {
            // skip comment
            pos += 2;
            while (s.length-pos > 1 && !(s.ptr[pos] == '*' && s.ptr[pos+1] == '/')) ++pos;
            if (s.length-pos <= 2) { pos = cast(uint)s.length; break; }
            pos += 2;
          } else {
            ++pos;
          }
        }
        version(nanosvg_debug_styles) { import std.stdio; writeln("*** style: ", s[1..pos].quote); }
        if (tokensAdded > 0) {
          foreach (immutable idx; p.styleCount-tokensAdded..p.styleCount) p.styles[idx].value = s[1..pos];
        }
        tokensAdded = 0;
        if (s.length-pos < 1) break;
        s = s[pos+1..$];
      } else {
        usize pos = 0;
        while (pos < s.length && s.ptr[pos] > ' ' && s.ptr[pos] != '{' && s.ptr[pos] != '/') ++pos;
        const(char)[] tk = s[0..pos];
        version(nanosvg_debug_styles) { import std.stdio; writeln("token: ", tk.quote); }
        s = s[pos..$];
        {
          import core.stdc.stdlib : realloc;
          import core.stdc.string : memset;
          p.styles = cast(typeof(p.styles))realloc(p.styles, p.styles[0].sizeof*(p.styleCount+1));
          memset(p.styles+p.styleCount, 0, p.styles[0].sizeof);
          ++p.styleCount;
        }
        p.styles[p.styleCount-1].name = tk;
        ++tokensAdded;
      }
    }
    version(nanosvg_debug_styles) foreach (const ref st; p.styles[0..p.styleCount]) { import std.stdio; writeln("name: ", st.name.quote, "; value: ", st.value.quote); }
  }
}

void nsvg__imageBounds (Parser* p, float* bounds) {
  NSVG.Shape* shape;
  shape = p.image.shapes;
  if (shape is null) {
    bounds[0..4] = 0.0;
    return;
  }
  bounds[0] = shape.bounds.ptr[0];
  bounds[1] = shape.bounds.ptr[1];
  bounds[2] = shape.bounds.ptr[2];
  bounds[3] = shape.bounds.ptr[3];
  for (shape = shape.next; shape !is null; shape = shape.next) {
    bounds[0] = nsvg__minf(bounds[0], shape.bounds.ptr[0]);
    bounds[1] = nsvg__minf(bounds[1], shape.bounds.ptr[1]);
    bounds[2] = nsvg__maxf(bounds[2], shape.bounds.ptr[2]);
    bounds[3] = nsvg__maxf(bounds[3], shape.bounds.ptr[3]);
  }
}

float nsvg__viewAlign (float content, float container, int type) {
  if (type == NSVG_ALIGN_MIN) return 0;
  if (type == NSVG_ALIGN_MAX) return container-content;
  // mid
  return (container-content)*0.5f;
}

void nsvg__scaleGradient (NSVG.Gradient* grad, float tx, float ty, float sx, float sy) {
  float[6] t = void;
  nsvg__xformSetTranslation(t.ptr, tx, ty);
  nsvg__xformMultiply(grad.xform.ptr, t.ptr);

  nsvg__xformSetScale(t.ptr, sx, sy);
  nsvg__xformMultiply(grad.xform.ptr, t.ptr);
}

void nsvg__scaleToViewbox (Parser* p, const(char)[] units) {
  NSVG.ClipPath* clipPath;
  float tx = void, ty = void, sx = void, sy = void, us = void;

  float[4] bounds = void;

  // Guess image size if not set completely.
  nsvg__imageBounds(p, bounds.ptr);

  if (p.viewWidth == 0) {
    if (p.image.width > 0) {
      p.viewWidth = p.image.width;
    } else {
      p.viewMinx = bounds[0];
      p.viewWidth = bounds[2]-bounds[0];
    }
  }
  if (p.viewHeight == 0) {
    if (p.image.height > 0) {
      p.viewHeight = p.image.height;
    } else {
      p.viewMiny = bounds[1];
      p.viewHeight = bounds[3]-bounds[1];
    }
  }
  if (p.image.width == 0)
    p.image.width = p.viewWidth;
  if (p.image.height == 0)
    p.image.height = p.viewHeight;

  tx = -p.viewMinx;
  ty = -p.viewMiny;
  sx = p.viewWidth > 0 ? p.image.width/p.viewWidth : 0;
  sy = p.viewHeight > 0 ? p.image.height/p.viewHeight : 0;
  // Unit scaling
  us = 1.0f/nsvg__convertToPixels(p, nsvg__coord(1.0f, nsvg__parseUnits(units)), 0.0f, 1.0f);

  // Fix aspect ratio
  if (p.alignType == NSVG_ALIGN_MEET) {
    // fit whole image into viewbox
    sx = sy = nsvg__minf(sx, sy);
    tx += nsvg__viewAlign(p.viewWidth*sx, p.image.width, p.alignX)/sx;
    ty += nsvg__viewAlign(p.viewHeight*sy, p.image.height, p.alignY)/sy;
  } else if (p.alignType == NSVG_ALIGN_SLICE) {
    // fill whole viewbox with image
    sx = sy = nsvg__maxf(sx, sy);
    tx += nsvg__viewAlign(p.viewWidth*sx, p.image.width, p.alignX)/sx;
    ty += nsvg__viewAlign(p.viewHeight*sy, p.image.height, p.alignY)/sy;
  }

  // Transform
  sx *= us;
  sy *= us;

  nsvg__transformShapes(p.image.shapes, tx, ty, sx, sy);

  clipPath = p.image.clipPaths;
  while(clipPath !is null) {
        nsvg__transformShapes(clipPath.shapes, tx, ty, sx, sy);
        clipPath = clipPath.next;
  }
}

void nsvg__transformShapes(NSVG.Shape* shapes, float tx, float ty, float sx, float sy) {

  float avgs;
  NSVG.Shape* shape;
  NSVG.Path* path;

  float[4] bounds = void;
  float[6] t = void;
  float* pt;


  avgs = (sx+sy)/2.0f;
  for (shape = shapes; shape !is null; shape = shape.next) {
    shape.bounds.ptr[0] = (shape.bounds.ptr[0]+tx)*sx;
    shape.bounds.ptr[1] = (shape.bounds.ptr[1]+ty)*sy;
    shape.bounds.ptr[2] = (shape.bounds.ptr[2]+tx)*sx;
    shape.bounds.ptr[3] = (shape.bounds.ptr[3]+ty)*sy;
    for (path = shape.paths; path !is null; path = path.next) {
      path.bounds[0] = (path.bounds[0]+tx)*sx;
      path.bounds[1] = (path.bounds[1]+ty)*sy;
      path.bounds[2] = (path.bounds[2]+tx)*sx;
      path.bounds[3] = (path.bounds[3]+ty)*sy;
      for (int i = 0; i+3 <= path.nsflts; ) {
        int argc = 0; // pair of coords
        NSVG.Command cmd = cast(NSVG.Command)path.stream[i++];
        final switch (cmd) {
          case NSVG.Command.MoveTo: argc = 1; break;
          case NSVG.Command.LineTo: argc = 1; break;
          case NSVG.Command.QuadTo: argc = 2; break;
          case NSVG.Command.BezierTo: argc = 3; break;
        }
        // scale points
        while (argc-- > 0) {
          path.stream[i+0] = (path.stream[i+0]+tx)*sx;
          path.stream[i+1] = (path.stream[i+1]+ty)*sy;
          i += 2;
        }
      }
    }

    if (shape.fill.type == NSVG.PaintType.LinearGradient || shape.fill.type == NSVG.PaintType.RadialGradient) {
      nsvg__scaleGradient(shape.fill.gradient, tx, ty, sx, sy);
      //memcpy(t.ptr, shape.fill.gradient.xform.ptr, float.sizeof*6);
      t.ptr[0..6] = shape.fill.gradient.xform[0..6];
      nsvg__xformInverse(shape.fill.gradient.xform.ptr, t.ptr);
    }
    if (shape.stroke.type == NSVG.PaintType.LinearGradient || shape.stroke.type == NSVG.PaintType.RadialGradient) {
      nsvg__scaleGradient(shape.stroke.gradient, tx, ty, sx, sy);
      //memcpy(t.ptr, shape.stroke.gradient.xform.ptr, float.sizeof*6);
      t.ptr[0..6] = shape.stroke.gradient.xform[0..6];
      nsvg__xformInverse(shape.stroke.gradient.xform.ptr, t.ptr);
    }

    shape.strokeWidth *= avgs;
    shape.strokeDashOffset *= avgs;
    foreach (immutable int i; 0..shape.strokeDashCount) shape.strokeDashArray[i] *= avgs;
  }
}

///
public NSVG* nsvgParse (const(char)[] input, const(char)[] units="px", float dpi=96, int canvaswdt=-1, int canvashgt=-1) {
  Parser* p;
  NSVG* ret = null;

  /*
  static if (NanoSVGHasVFS) {
    if (input.length > 4 && input[0..5] == "NSVG\x00" && units == "px" && dpi == 96) {
      return nsvgUnserialize(wrapStream(MemoryStreamRO(input)));
    }
  }
  */

  p = nsvg__createParser();
  if (p is null) return null;
  p.dpi = dpi;
  p.canvaswdt = (canvaswdt < 1 ? NSVGDefaults.CanvasWidth : canvaswdt);
  p.canvashgt = (canvashgt < 1 ? NSVGDefaults.CanvasHeight : canvashgt);

  nsvg__parseXML(input, &nsvg__startElement, &nsvg__endElement, &nsvg__content, p);

  // Scale to viewBox
  nsvg__scaleToViewbox(p, units);

  ret = p.image;
  p.image = null;

  nsvg__deleteParser(p);

  return ret;
}

private void deleteShapes(NSVG.Shape* shape) {
  NSVG.Shape* snext;
  while (shape !is null) {
    snext = shape.next;
    nsvg__deletePaths(shape.paths);
    nsvg__deletePaint(&shape.fill);
    nsvg__deletePaint(&shape.stroke);

    if(shape.clip.index)
        xfree(shape.clip.index);

    xfree(shape);
    shape = snext;
  }
}

private void deleteClipPaths(NSVG.ClipPath* path) {
    NSVG.ClipPath* pnext;
    while(path !is null) {
        pnext = path.next;
        deleteShapes(path.shapes);
        xfree(path);
        path = pnext;
    }
}

///
public void kill (NSVG* image) {
  import core.stdc.string : memset;

  if (image is null) return;

    deleteShapes(image.shapes);
    deleteClipPaths(image.clipPaths);

  memset(image, 0, (*image).sizeof);
  xfree(image);
}

} // nothrow @trusted @nogc


///
public NSVG* nsvgParseFromFile (const(char)[] filename, const(char)[] units="px", float dpi=96, int canvaswdt=-1, int canvashgt=-1) nothrow @system {
  import core.stdc.stdlib : malloc, free;
  enum AddedBytes = 8;

  char* data = null;
  scope(exit) if (data !is null) free(data);

  if (filename.length == 0) return null;

  try {
    static if (NanoSVGHasIVVFS) {
      auto fl = VFile(filename);
      auto size = fl.size;
      if (size > int.max/8 || size < 1) return null;
      data = cast(char*)malloc(cast(uint)size+AddedBytes);
      if (data is null) return null;
      data[0..cast(uint)size+AddedBytes] = 0;
      fl.rawReadExact(data[0..cast(uint)size]);
      fl.close();
    } else {
      import core.stdc.stdio : FILE, fopen, fclose, fread, ftell, fseek;
      import std.internal.cstring : tempCString;
      auto fl = fopen(filename.tempCString, "rb");
      if (fl is null) return null;
      scope(exit) fclose(fl);
      if (fseek(fl, 0, 2/*SEEK_END*/) != 0) return null;
      auto size = ftell(fl);
      if (fseek(fl, 0, 0/*SEEK_SET*/) != 0) return null;
      if (size < 16 || size > int.max/32) return null;
      data = cast(char*)malloc(cast(uint)size+AddedBytes);
      if (data is null) assert(0, "out of memory in NanoVega fontstash");
      data[0..cast(uint)size+AddedBytes] = 0;
      char* dptr = data;
      auto left = cast(uint)size;
      while (left > 0) {
        auto rd = fread(dptr, 1, left, fl);
        if (rd == 0) return null; // unexpected EOF or reading error, it doesn't matter
        dptr += rd;
        left -= rd;
      }
    }
    return nsvgParse(data[0..cast(uint)size], units, dpi, canvaswdt, canvashgt);
  } catch (Exception e) {
    return null;
  }
}


static if (NanoSVGHasIVVFS) {
///
public NSVG* nsvgParseFromFile(ST) (auto ref ST fi, const(char)[] units="px", float dpi=96, int canvaswdt=-1, int canvashgt=-1) nothrow
if (isReadableStream!ST && isSeekableStream!ST && streamHasSize!ST)
{
  import core.stdc.stdlib : malloc, free;

  enum AddedBytes = 8;
  usize size;
  char* data = null;
  scope(exit) if (data is null) free(data);

  try {
    auto sz = fi.size;
    auto pp = fi.tell;
    if (pp >= sz) return null;
    sz -= pp;
    if (sz > 0x3ff_ffff) return null;
    size = cast(usize)sz;
    data = cast(char*)malloc(size+AddedBytes);
    if (data is null) return null;
    scope(exit) free(data);
    data[0..size+AddedBytes] = 0;
    fi.rawReadExact(data[0..size]);
    return nsvgParse(data[0..size], units, dpi, canvaswdt, canvashgt);
  } catch (Exception e) {
    return null;
  }
}
}


// ////////////////////////////////////////////////////////////////////////// //
// rasterizer
private:
nothrow @trusted @nogc {

enum NSVG__SUBSAMPLES = 5;
enum NSVG__FIXSHIFT = 10;
enum NSVG__FIX = 1<<NSVG__FIXSHIFT;
enum NSVG__FIXMASK = NSVG__FIX-1;
enum NSVG__MEMPAGE_SIZE = 1024;

struct NSVGedge {
  float x0 = 0, y0 = 0, x1 = 0, y1 = 0;
  int dir = 0;
  NSVGedge* next;
}

struct NSVGpoint {
  float x = 0, y = 0;
  float dx = 0, dy = 0;
  float len = 0;
  float dmx = 0, dmy = 0;
  ubyte flags = 0;
}

struct NSVGactiveEdge {
  int x = 0, dx = 0;
  float ey = 0;
  int dir = 0;
  NSVGactiveEdge *next;
}

struct NSVGmemPage {
  ubyte[NSVG__MEMPAGE_SIZE] mem;
  int size;
  NSVGmemPage* next;
}

struct NSVGcachedPaint {
  char type;
  char spread;
  float[6] xform = 0;
  uint[256] colors;
}

struct NSVGrasterizerS {
  float px = 0, py = 0;

  float tessTol = 0;
  float distTol = 0;

  NSVGedge* edges;
  int nedges;
  int cedges;

  NSVGpoint* points;
  int npoints;
  int cpoints;

  NSVGpoint* points2;
  int npoints2;
  int cpoints2;

  NSVGactiveEdge* freelist;
  NSVGmemPage* pages;
  NSVGmemPage* curpage;

  ubyte* scanline;
  int cscanline;

  NSVGscanlineFunction fscanline;

  ubyte* stencil;
  int stencilSize;
  int stencilStride;

  ubyte* bitmap;
  int width, height, stride;
}

alias NSVGscanlineFunction = void function(
    ubyte* dst, int count, ubyte* cover, int x, int y,
    float tx, float ty, float scale, const(NSVGcachedPaint)* cache);


///
public NSVGrasterizer nsvgCreateRasterizer () {
  NSVGrasterizer r = xalloc!NSVGrasterizerS;
  if (r is null) goto error;

  r.tessTol = 0.25f;
  r.distTol = 0.01f;

  return r;

error:
  r.kill();
  return null;
}

///
public void kill (NSVGrasterizer r) {
  NSVGmemPage* p;

  if (r is null) return;

  p = r.pages;
  while (p !is null) {
    NSVGmemPage* next = p.next;
    xfree(p);
    p = next;
  }

  if (r.edges) xfree(r.edges);
  if (r.points) xfree(r.points);
  if (r.points2) xfree(r.points2);
  if (r.scanline) xfree(r.scanline);
  if (r.stencil) xfree(r.stencil);

  xfree(r);
}

NSVGmemPage* nsvg__nextPage (NSVGrasterizer r, NSVGmemPage* cur) {
  NSVGmemPage *newp;

  // If using existing chain, return the next page in chain
  if (cur !is null && cur.next !is null) return cur.next;

  // Alloc new page
  newp = xalloc!NSVGmemPage;
  if (newp is null) return null;

  // Add to linked list
  if (cur !is null)
    cur.next = newp;
  else
    r.pages = newp;

  return newp;
}

void nsvg__resetPool (NSVGrasterizer r) {
  NSVGmemPage* p = r.pages;
  while (p !is null) {
    p.size = 0;
    p = p.next;
  }
  r.curpage = r.pages;
}

ubyte* nsvg__alloc (NSVGrasterizer r, int size) {
  ubyte* buf;
  if (size > NSVG__MEMPAGE_SIZE) return null;
  if (r.curpage is null || r.curpage.size+size > NSVG__MEMPAGE_SIZE) {
    r.curpage = nsvg__nextPage(r, r.curpage);
  }
  buf = &r.curpage.mem[r.curpage.size];
  r.curpage.size += size;
  return buf;
}

int nsvg__ptEquals (float x1, float y1, float x2, float y2, float tol) {
  immutable float dx = x2-x1;
  immutable float dy = y2-y1;
  return dx*dx+dy*dy < tol*tol;
}

void nsvg__addPathPoint (NSVGrasterizer r, float x, float y, int flags) {
  import core.stdc.stdlib : realloc;

  NSVGpoint* pt;

  if (r.npoints > 0) {
    pt = r.points+(r.npoints-1);
    if (nsvg__ptEquals(pt.x, pt.y, x, y, r.distTol)) {
      pt.flags |= flags;
      return;
    }
  }

  if (r.npoints+1 > r.cpoints) {
    r.cpoints = (r.cpoints > 0 ? r.cpoints*2 : 64);
    r.points = cast(NSVGpoint*)realloc(r.points, NSVGpoint.sizeof*r.cpoints+256);
    if (r.points is null) assert(0, "nanosvg: out of memory");
  }

  pt = r.points+r.npoints;
  pt.x = x;
  pt.y = y;
  pt.flags = cast(ubyte)flags;
  ++r.npoints;
}

void nsvg__appendPathPoint (NSVGrasterizer r, NSVGpoint pt) {
  import core.stdc.stdlib : realloc;
  if (r.npoints+1 > r.cpoints) {
    r.cpoints = (r.cpoints > 0 ? r.cpoints*2 : 64);
    r.points = cast(NSVGpoint*)realloc(r.points, NSVGpoint.sizeof*r.cpoints+256);
    if (r.points is null) assert(0, "nanosvg: out of memory");
  }
  r.points[r.npoints] = pt;
  ++r.npoints;
}

void nsvg__duplicatePoints (NSVGrasterizer r) {
  import core.stdc.stdlib : realloc;
  import core.stdc.string : memmove;
  if (r.npoints > r.cpoints2) {
    r.cpoints2 = r.npoints;
    r.points2 = cast(NSVGpoint*)realloc(r.points2, NSVGpoint.sizeof*r.cpoints2+256);
    if (r.points2 is null) assert(0, "nanosvg: out of memory");
  }
  memmove(r.points2, r.points, NSVGpoint.sizeof*r.npoints);
  r.npoints2 = r.npoints;
}

void nsvg__addEdge (NSVGrasterizer r, float x0, float y0, float x1, float y1) {
  NSVGedge* e;

  // Skip horizontal edges
  if (y0 == y1) return;

  if (r.nedges+1 > r.cedges) {
    import core.stdc.stdlib : realloc;
    r.cedges = (r.cedges > 0 ? r.cedges*2 : 64);
    r.edges = cast(NSVGedge*)realloc(r.edges, NSVGedge.sizeof*r.cedges+256);
    if (r.edges is null) assert(0, "nanosvg: out of memory");
  }

  e = &r.edges[r.nedges];
  ++r.nedges;

  if (y0 < y1) {
    e.x0 = x0;
    e.y0 = y0;
    e.x1 = x1;
    e.y1 = y1;
    e.dir = 1;
  } else {
    e.x0 = x1;
    e.y0 = y1;
    e.x1 = x0;
    e.y1 = y0;
    e.dir = -1;
  }
}

float nsvg__normalize (float *x, float* y) {
  immutable float d = sqrtf((*x)*(*x)+(*y)*(*y));
  if (d > 1e-6f) {
    float id = 1.0f/d;
    *x *= id;
    *y *= id;
  }
  return d;
}

void nsvg__flattenCubicBez (NSVGrasterizer r, in float x1, in float y1, in float x2, in float y2, in float x3, in float y3, in float x4, in float y4, in int level, in int type) {
  if (level > 10) return;

  // check for collinear points, and use AFD tesselator on such curves (it is WAY faster for this case)
  version(none) {
    if (level == 0) {
      static bool collinear (in float v0x, in float v0y, in float v1x, in float v1y, in float v2x, in float v2y) nothrow @trusted @nogc {
        immutable float cz = (v1x-v0x)*(v2y-v0y)-(v2x-v0x)*(v1y-v0y);
        return (fabsf(cz*cz) <= 0.01f);
      }
      if (collinear(x1, y1, x2, y2, x3, y3) && collinear(x2, y2, x3, y3, x3, y4)) {
        //{ import core.stdc.stdio; printf("AFD fallback!\n"); }
        nsvg__flattenCubicBezAFD(r, x1, y1, x2, y2, x3, y3, x4, y4, type);
        return;
      }
    }
  }

  immutable x12 = (x1+x2)*0.5f;
  immutable y12 = (y1+y2)*0.5f;
  immutable x23 = (x2+x3)*0.5f;
  immutable y23 = (y2+y3)*0.5f;
  immutable x34 = (x3+x4)*0.5f;
  immutable y34 = (y3+y4)*0.5f;
  immutable x123 = (x12+x23)*0.5f;
  immutable y123 = (y12+y23)*0.5f;

  immutable dx = x4-x1;
  immutable dy = y4-y1;
  immutable d2 = fabsf(((x2-x4)*dy-(y2-y4)*dx));
  immutable d3 = fabsf(((x3-x4)*dy-(y3-y4)*dx));

  if ((d2+d3)*(d2+d3) < r.tessTol*(dx*dx+dy*dy)) {
    nsvg__addPathPoint(r, x4, y4, type);
    return;
  }

  immutable x234 = (x23+x34)*0.5f;
  immutable y234 = (y23+y34)*0.5f;
  immutable x1234 = (x123+x234)*0.5f;
  immutable y1234 = (y123+y234)*0.5f;

  // "taxicab" / "manhattan" check for flat curves
  if (fabsf(x1+x3-x2-x2)+fabsf(y1+y3-y2-y2)+fabsf(x2+x4-x3-x3)+fabsf(y2+y4-y3-y3) < r.tessTol/4) {
    nsvg__addPathPoint(r, x1234, y1234, type);
    return;
  }

  nsvg__flattenCubicBez(r, x1, y1, x12, y12, x123, y123, x1234, y1234, level+1, 0);
  nsvg__flattenCubicBez(r, x1234, y1234, x234, y234, x34, y34, x4, y4, level+1, type);
}

// Adaptive forward differencing for bezier tesselation.
// See Lien, Sheue-Ling, Michael Shantz, and Vaughan Pratt.
// "Adaptive forward differencing for rendering curves and surfaces."
// ACM SIGGRAPH Computer Graphics. Vol. 21. No. 4. ACM, 1987.
// original code by Taylor Holliday <taylor@audulus.com>
void nsvg__flattenCubicBezAFD (NSVGrasterizer r, in float x1, in float y1, in float x2, in float y2, in float x3, in float y3, in float x4, in float y4, in int type) nothrow @trusted @nogc {
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

  immutable float tol = r.tessTol*4;

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
    nsvg__addPathPoint(r, px, py, (t > 0 ? type : 0));

    // Advance along the curve.
    t += dt;

    // Ensure we don't overshoot.
    assert(t <= AFD_ONE);
  }
}

void nsvg__flattenShape (NSVGrasterizer r, const(NSVG.Shape)* shape, float scale) {
  for (const(NSVG.Path)* path = shape.paths; path !is null; path = path.next) {
    r.npoints = 0;
    if (path.empty) continue;
    // first point
    float x0, y0;
    path.startPoint(&x0, &y0);
    nsvg__addPathPoint(r, x0*scale, y0*scale, 0);
    // cubic beziers
    path.asCubics(delegate (const(float)[] cubic) {
      assert(cubic.length >= 8);
      nsvg__flattenCubicBez(r,
        cubic.ptr[0]*scale, cubic.ptr[1]*scale,
        cubic.ptr[2]*scale, cubic.ptr[3]*scale,
        cubic.ptr[4]*scale, cubic.ptr[5]*scale,
        cubic.ptr[6]*scale, cubic.ptr[7]*scale,
        0, 0);
    });
    // close path
    nsvg__addPathPoint(r, x0*scale, y0*scale, 0);
    // Flatten path
    /+
    nsvg__addPathPoint(r, path.pts[0]*scale, path.pts[1]*scale, 0);
    for (int i = 0; i < path.npts-1; i += 3) {
      const(float)* p = path.pts+(i*2);
      nsvg__flattenCubicBez(r, p[0]*scale, p[1]*scale, p[2]*scale, p[3]*scale, p[4]*scale, p[5]*scale, p[6]*scale, p[7]*scale, 0, 0);
    }
    // Close path
    nsvg__addPathPoint(r, path.pts[0]*scale, path.pts[1]*scale, 0);
    +/
    // Build edges
    for (int i = 0, j = r.npoints-1; i < r.npoints; j = i++) {
      nsvg__addEdge(r, r.points[j].x, r.points[j].y, r.points[i].x, r.points[i].y);
    }
  }
}

alias PtFlags = ubyte;
enum : ubyte {
  PtFlagsCorner = 0x01,
  PtFlagsBevel = 0x02,
  PtFlagsLeft = 0x04,
}

void nsvg__initClosed (NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p0, const(NSVGpoint)* p1, float lineWidth) {
  immutable float w = lineWidth*0.5f;
  float dx = p1.x-p0.x;
  float dy = p1.y-p0.y;
  immutable float len = nsvg__normalize(&dx, &dy);
  immutable float px = p0.x+dx*len*0.5f, py = p0.y+dy*len*0.5f;
  immutable float dlx = dy, dly = -dx;
  immutable float lx = px-dlx*w, ly = py-dly*w;
  immutable float rx = px+dlx*w, ry = py+dly*w;
  left.x = lx; left.y = ly;
  right.x = rx; right.y = ry;
}

void nsvg__buttCap (NSVGrasterizer r, NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p, float dx, float dy, float lineWidth, int connect) {
  immutable float w = lineWidth*0.5f;
  immutable float px = p.x, py = p.y;
  immutable float dlx = dy, dly = -dx;
  immutable float lx = px-dlx*w, ly = py-dly*w;
  immutable float rx = px+dlx*w, ry = py+dly*w;

  nsvg__addEdge(r, lx, ly, rx, ry);

  if (connect) {
    nsvg__addEdge(r, left.x, left.y, lx, ly);
    nsvg__addEdge(r, rx, ry, right.x, right.y);
  }
  left.x = lx; left.y = ly;
  right.x = rx; right.y = ry;
}

void nsvg__squareCap (NSVGrasterizer r, NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p, float dx, float dy, float lineWidth, int connect) {
  immutable float w = lineWidth*0.5f;
  immutable float px = p.x-dx*w, py = p.y-dy*w;
  immutable float dlx = dy, dly = -dx;
  immutable float lx = px-dlx*w, ly = py-dly*w;
  immutable float rx = px+dlx*w, ry = py+dly*w;

  nsvg__addEdge(r, lx, ly, rx, ry);

  if (connect) {
    nsvg__addEdge(r, left.x, left.y, lx, ly);
    nsvg__addEdge(r, rx, ry, right.x, right.y);
  }
  left.x = lx; left.y = ly;
  right.x = rx; right.y = ry;
}

void nsvg__roundCap (NSVGrasterizer r, NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p, float dx, float dy, float lineWidth, int ncap, int connect) {
  immutable float w = lineWidth*0.5f;
  immutable float px = p.x, py = p.y;
  immutable float dlx = dy, dly = -dx;
  float lx = 0, ly = 0, rx = 0, ry = 0, prevx = 0, prevy = 0;

  foreach (int i; 0..ncap) {
    immutable float a = i/cast(float)(ncap-1)*NSVG_PI;
    immutable float ax = cosf(a)*w, ay = sinf(a)*w;
    immutable float x = px-dlx*ax-dx*ay;
    immutable float y = py-dly*ax-dy*ay;

    if (i > 0) nsvg__addEdge(r, prevx, prevy, x, y);

    prevx = x;
    prevy = y;

    if (i == 0) {
      lx = x;
      ly = y;
    } else if (i == ncap-1) {
      rx = x;
      ry = y;
    }
  }

  if (connect) {
    nsvg__addEdge(r, left.x, left.y, lx, ly);
    nsvg__addEdge(r, rx, ry, right.x, right.y);
  }

  left.x = lx; left.y = ly;
  right.x = rx; right.y = ry;
}

void nsvg__bevelJoin (NSVGrasterizer r, NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p0, const(NSVGpoint)* p1, float lineWidth) {
  immutable float w = lineWidth*0.5f;
  immutable float dlx0 = p0.dy, dly0 = -p0.dx;
  immutable float dlx1 = p1.dy, dly1 = -p1.dx;
  immutable float lx0 = p1.x-(dlx0*w), ly0 = p1.y-(dly0*w);
  immutable float rx0 = p1.x+(dlx0*w), ry0 = p1.y+(dly0*w);
  immutable float lx1 = p1.x-(dlx1*w), ly1 = p1.y-(dly1*w);
  immutable float rx1 = p1.x+(dlx1*w), ry1 = p1.y+(dly1*w);

  nsvg__addEdge(r, lx0, ly0, left.x, left.y);
  nsvg__addEdge(r, lx1, ly1, lx0, ly0);

  nsvg__addEdge(r, right.x, right.y, rx0, ry0);
  nsvg__addEdge(r, rx0, ry0, rx1, ry1);

  left.x = lx1; left.y = ly1;
  right.x = rx1; right.y = ry1;
}

void nsvg__miterJoin (NSVGrasterizer r, NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p0, const(NSVGpoint)* p1, float lineWidth) {
  immutable float w = lineWidth*0.5f;
  immutable float dlx0 = p0.dy, dly0 = -p0.dx;
  immutable float dlx1 = p1.dy, dly1 = -p1.dx;
  float lx0 = void, rx0 = void, lx1 = void, rx1 = void;
  float ly0 = void, ry0 = void, ly1 = void, ry1 = void;

  if (p1.flags&PtFlagsLeft) {
    lx0 = lx1 = p1.x-p1.dmx*w;
    ly0 = ly1 = p1.y-p1.dmy*w;
    nsvg__addEdge(r, lx1, ly1, left.x, left.y);

    rx0 = p1.x+(dlx0*w);
    ry0 = p1.y+(dly0*w);
    rx1 = p1.x+(dlx1*w);
    ry1 = p1.y+(dly1*w);
    nsvg__addEdge(r, right.x, right.y, rx0, ry0);
    nsvg__addEdge(r, rx0, ry0, rx1, ry1);
  } else {
    lx0 = p1.x-(dlx0*w);
    ly0 = p1.y-(dly0*w);
    lx1 = p1.x-(dlx1*w);
    ly1 = p1.y-(dly1*w);
    nsvg__addEdge(r, lx0, ly0, left.x, left.y);
    nsvg__addEdge(r, lx1, ly1, lx0, ly0);

    rx0 = rx1 = p1.x+p1.dmx*w;
    ry0 = ry1 = p1.y+p1.dmy*w;
    nsvg__addEdge(r, right.x, right.y, rx1, ry1);
  }

  left.x = lx1; left.y = ly1;
  right.x = rx1; right.y = ry1;
}

void nsvg__roundJoin (NSVGrasterizer r, NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p0, const(NSVGpoint)* p1, float lineWidth, int ncap) {
  int i, n;
  float w = lineWidth*0.5f;
  float dlx0 = p0.dy, dly0 = -p0.dx;
  float dlx1 = p1.dy, dly1 = -p1.dx;
  float a0 = atan2f(dly0, dlx0);
  float a1 = atan2f(dly1, dlx1);
  float da = a1-a0;
  float lx, ly, rx, ry;

  if (da < NSVG_PI) da += NSVG_PI*2;
  if (da > NSVG_PI) da -= NSVG_PI*2;

  n = cast(int)ceilf((fabsf(da)/NSVG_PI)*ncap);
  if (n < 2) n = 2;
  if (n > ncap) n = ncap;

  lx = left.x;
  ly = left.y;
  rx = right.x;
  ry = right.y;

  for (i = 0; i < n; i++) {
    float u = i/cast(float)(n-1);
    float a = a0+u*da;
    float ax = cosf(a)*w, ay = sinf(a)*w;
    float lx1 = p1.x-ax, ly1 = p1.y-ay;
    float rx1 = p1.x+ax, ry1 = p1.y+ay;

    nsvg__addEdge(r, lx1, ly1, lx, ly);
    nsvg__addEdge(r, rx, ry, rx1, ry1);

    lx = lx1; ly = ly1;
    rx = rx1; ry = ry1;
  }

  left.x = lx; left.y = ly;
  right.x = rx; right.y = ry;
}

void nsvg__straightJoin (NSVGrasterizer r, NSVGpoint* left, NSVGpoint* right, const(NSVGpoint)* p1, float lineWidth) {
  float w = lineWidth*0.5f;
  float lx = p1.x-(p1.dmx*w), ly = p1.y-(p1.dmy*w);
  float rx = p1.x+(p1.dmx*w), ry = p1.y+(p1.dmy*w);

  nsvg__addEdge(r, lx, ly, left.x, left.y);
  nsvg__addEdge(r, right.x, right.y, rx, ry);

  left.x = lx; left.y = ly;
  right.x = rx; right.y = ry;
}

int nsvg__curveDivs (float r, float arc, float tol) {
  float da = acosf(r/(r+tol))*2.0f;
  int divs = cast(int)ceilf(arc/da);
  if (divs < 2) divs = 2;
  return divs;
}

void nsvg__expandStroke (NSVGrasterizer r, const(NSVGpoint)* points, int npoints, int closed, int lineJoin, int lineCap, float lineWidth) {
  int ncap = nsvg__curveDivs(lineWidth*0.5f, NSVG_PI, r.tessTol);  // Calculate divisions per half circle.
  //NSVGpoint left = {0, 0, 0, 0, 0, 0, 0, 0}, right = {0, 0, 0, 0, 0, 0, 0, 0}, firstLeft = {0, 0, 0, 0, 0, 0, 0, 0}, firstRight = {0, 0, 0, 0, 0, 0, 0, 0};
  NSVGpoint left, right, firstLeft, firstRight;
  const(NSVGpoint)* p0, p1;
  int j, s, e;

  // Build stroke edges
  if (closed) {
    // Looping
    p0 = &points[npoints-1];
    p1 = &points[0];
    s = 0;
    e = npoints;
  } else {
    // Add cap
    p0 = &points[0];
    p1 = &points[1];
    s = 1;
    e = npoints-1;
  }

  if (closed) {
    nsvg__initClosed(&left, &right, p0, p1, lineWidth);
    firstLeft = left;
    firstRight = right;
  } else {
    // Add cap
    float dx = p1.x-p0.x;
    float dy = p1.y-p0.y;
    nsvg__normalize(&dx, &dy);
    if (lineCap == NSVG.LineCap.Butt)
      nsvg__buttCap(r, &left, &right, p0, dx, dy, lineWidth, 0);
    else if (lineCap == NSVG.LineCap.Square)
      nsvg__squareCap(r, &left, &right, p0, dx, dy, lineWidth, 0);
    else if (lineCap == NSVG.LineCap.Round)
      nsvg__roundCap(r, &left, &right, p0, dx, dy, lineWidth, ncap, 0);
  }

  for (j = s; j < e; ++j) {
    if (p1.flags&PtFlagsCorner) {
      if (lineJoin == NSVG.LineJoin.Round)
        nsvg__roundJoin(r, &left, &right, p0, p1, lineWidth, ncap);
      else if (lineJoin == NSVG.LineJoin.Bevel || (p1.flags&PtFlagsBevel))
        nsvg__bevelJoin(r, &left, &right, p0, p1, lineWidth);
      else
        nsvg__miterJoin(r, &left, &right, p0, p1, lineWidth);
    } else {
      nsvg__straightJoin(r, &left, &right, p1, lineWidth);
    }
    p0 = p1++;
  }

  if (closed) {
    // Loop it
    nsvg__addEdge(r, firstLeft.x, firstLeft.y, left.x, left.y);
    nsvg__addEdge(r, right.x, right.y, firstRight.x, firstRight.y);
  } else {
    // Add cap
    float dx = p1.x-p0.x;
    float dy = p1.y-p0.y;
    nsvg__normalize(&dx, &dy);
    if (lineCap == NSVG.LineCap.Butt)
      nsvg__buttCap(r, &right, &left, p1, -dx, -dy, lineWidth, 1);
    else if (lineCap == NSVG.LineCap.Square)
      nsvg__squareCap(r, &right, &left, p1, -dx, -dy, lineWidth, 1);
    else if (lineCap == NSVG.LineCap.Round)
      nsvg__roundCap(r, &right, &left, p1, -dx, -dy, lineWidth, ncap, 1);
  }
}

void nsvg__prepareStroke (NSVGrasterizer r, float miterLimit, int lineJoin) {
  int i, j;
  NSVGpoint* p0, p1;

  p0 = r.points+(r.npoints-1);
  p1 = r.points;
  for (i = 0; i < r.npoints; i++) {
    // Calculate segment direction and length
    p0.dx = p1.x-p0.x;
    p0.dy = p1.y-p0.y;
    p0.len = nsvg__normalize(&p0.dx, &p0.dy);
    // Advance
    p0 = p1++;
  }

  // calculate joins
  p0 = r.points+(r.npoints-1);
  p1 = r.points;
  for (j = 0; j < r.npoints; j++) {
    float dlx0, dly0, dlx1, dly1, dmr2, cross;
    dlx0 = p0.dy;
    dly0 = -p0.dx;
    dlx1 = p1.dy;
    dly1 = -p1.dx;
    // Calculate extrusions
    p1.dmx = (dlx0+dlx1)*0.5f;
    p1.dmy = (dly0+dly1)*0.5f;
    dmr2 = p1.dmx*p1.dmx+p1.dmy*p1.dmy;
    if (dmr2 > 0.000001f) {
      float s2 = 1.0f/dmr2;
      if (s2 > 600.0f) {
        s2 = 600.0f;
      }
      p1.dmx *= s2;
      p1.dmy *= s2;
    }

    // Clear flags, but keep the corner.
    p1.flags = (p1.flags&PtFlagsCorner) ? PtFlagsCorner : 0;

    // Keep track of left turns.
    cross = p1.dx*p0.dy-p0.dx*p1.dy;
    if (cross > 0.0f)
      p1.flags |= PtFlagsLeft;

    // Check to see if the corner needs to be beveled.
    if (p1.flags&PtFlagsCorner) {
      if ((dmr2*miterLimit*miterLimit) < 1.0f || lineJoin == NSVG.LineJoin.Bevel || lineJoin == NSVG.LineJoin.Round) {
        p1.flags |= PtFlagsBevel;
      }
    }

    p0 = p1++;
  }
}

void nsvg__flattenShapeStroke (NSVGrasterizer r, const(NSVG.Shape)* shape, float scale) {
  int i, j, closed;
  const(NSVG.Path)* path;
  const(NSVGpoint)* p0, p1;
  float miterLimit = shape.miterLimit;
  int lineJoin = shape.strokeLineJoin;
  int lineCap = shape.strokeLineCap;
  float lineWidth = shape.strokeWidth*scale;

  for (path = shape.paths; path !is null; path = path.next) {
    // Flatten path
    r.npoints = 0;
    if (!path.empty) {
      // first point
      {
        float x0, y0;
        path.startPoint(&x0, &y0);
        nsvg__addPathPoint(r, x0*scale, y0*scale, PtFlagsCorner);
      }
      // cubic beziers
      path.asCubics(delegate (const(float)[] cubic) {
        assert(cubic.length >= 8);
        nsvg__flattenCubicBez(r,
          cubic.ptr[0]*scale, cubic.ptr[1]*scale,
          cubic.ptr[2]*scale, cubic.ptr[3]*scale,
          cubic.ptr[4]*scale, cubic.ptr[5]*scale,
          cubic.ptr[6]*scale, cubic.ptr[7]*scale,
          0, PtFlagsCorner);
      });
    }
    /+
    nsvg__addPathPoint(r, path.pts[0]*scale, path.pts[1]*scale, PtFlagsCorner);
    for (i = 0; i < path.npts-1; i += 3) {
      const(float)* p = &path.pts[i*2];
      nsvg__flattenCubicBez(r, p[0]*scale, p[1]*scale, p[2]*scale, p[3]*scale, p[4]*scale, p[5]*scale, p[6]*scale, p[7]*scale, 0, PtFlagsCorner);
    }
    +/
    if (r.npoints < 2) continue;

    closed = path.closed;

    // If the first and last points are the same, remove the last, mark as closed path.
    p0 = &r.points[r.npoints-1];
    p1 = &r.points[0];
    if (nsvg__ptEquals(p0.x, p0.y, p1.x, p1.y, r.distTol)) {
      r.npoints--;
      p0 = &r.points[r.npoints-1];
      closed = 1;
    }

    if (shape.strokeDashCount > 0) {
      int idash = 0, dashState = 1;
      float totalDist = 0, dashLen, allDashLen, dashOffset;
      NSVGpoint cur;

      if (closed) nsvg__appendPathPoint(r, r.points[0]);

      // Duplicate points . points2.
      nsvg__duplicatePoints(r);

      r.npoints = 0;
      cur = r.points2[0];
      nsvg__appendPathPoint(r, cur);

      // Figure out dash offset.
      allDashLen = 0;
      for (j = 0; j < shape.strokeDashCount; j++) allDashLen += shape.strokeDashArray[j];
      if (shape.strokeDashCount&1) allDashLen *= 2.0f;
      // Find location inside pattern
      dashOffset = fmodf(shape.strokeDashOffset, allDashLen);
      if (dashOffset < 0.0f) dashOffset += allDashLen;

      while (dashOffset > shape.strokeDashArray[idash]) {
        dashOffset -= shape.strokeDashArray[idash];
        idash = (idash+1)%shape.strokeDashCount;
      }
      dashLen = (shape.strokeDashArray[idash]-dashOffset)*scale;

      for (j = 1; j < r.npoints2; ) {
        float dx = r.points2[j].x-cur.x;
        float dy = r.points2[j].y-cur.y;
        float dist = sqrtf(dx*dx+dy*dy);

        if (totalDist+dist > dashLen) {
          // Calculate intermediate point
          float d = (dashLen-totalDist)/dist;
          float x = cur.x+dx*d;
          float y = cur.y+dy*d;
          nsvg__addPathPoint(r, x, y, PtFlagsCorner);

          // Stroke
          if (r.npoints > 1 && dashState) {
            nsvg__prepareStroke(r, miterLimit, lineJoin);
            nsvg__expandStroke(r, r.points, r.npoints, 0, lineJoin, lineCap, lineWidth);
          }
          // Advance dash pattern
          dashState = !dashState;
          idash = (idash+1)%shape.strokeDashCount;
          dashLen = shape.strokeDashArray[idash]*scale;
          // Restart
          cur.x = x;
          cur.y = y;
          cur.flags = PtFlagsCorner;
          totalDist = 0.0f;
          r.npoints = 0;
          nsvg__appendPathPoint(r, cur);
        } else {
          totalDist += dist;
          cur = r.points2[j];
          nsvg__appendPathPoint(r, cur);
          j++;
        }
      }
      // Stroke any leftover path
      if (r.npoints > 1 && dashState) nsvg__expandStroke(r, r.points, r.npoints, 0, lineJoin, lineCap, lineWidth);
    } else {
      nsvg__prepareStroke(r, miterLimit, lineJoin);
      nsvg__expandStroke(r, r.points, r.npoints, closed, lineJoin, lineCap, lineWidth);
    }
  }
}

extern(C) int nsvg__cmpEdge (scope const void *p, scope const void *q) nothrow @trusted @nogc {
  NSVGedge* a = cast(NSVGedge*)p;
  NSVGedge* b = cast(NSVGedge*)q;
  if (a.y0 < b.y0) return -1;
  if (a.y0 > b.y0) return  1;
  return 0;
}


static NSVGactiveEdge* nsvg__addActive (NSVGrasterizer r, const(NSVGedge)* e, float startPoint) {
  NSVGactiveEdge* z;

  if (r.freelist !is null) {
    // Restore from freelist.
    z = r.freelist;
    r.freelist = z.next;
  } else {
    // Alloc new edge.
    z = cast(NSVGactiveEdge*)nsvg__alloc(r, NSVGactiveEdge.sizeof);
    if (z is null) return null;
  }

  immutable float dxdy = (e.x1-e.x0)/(e.y1-e.y0);
  //STBTT_assert(e.y0 <= start_point);
  // round dx down to avoid going too far
  if (dxdy < 0)
    z.dx = cast(int)(-floorf(NSVG__FIX*-dxdy));
  else
    z.dx = cast(int)floorf(NSVG__FIX*dxdy);
  z.x = cast(int)floorf(NSVG__FIX*(e.x0+dxdy*(startPoint-e.y0)));
  //z.x -= off_x*FIX;
  z.ey = e.y1;
  z.next = null;
  z.dir = e.dir;

  return z;
}

void nsvg__freeActive (NSVGrasterizer r, NSVGactiveEdge* z) {
  z.next = r.freelist;
  r.freelist = z;
}

void nsvg__fillScanline (ubyte* scanline, int len, int x0, int x1, int maxWeight, int* xmin, int* xmax) {
  int i = x0>>NSVG__FIXSHIFT;
  int j = x1>>NSVG__FIXSHIFT;
  if (i < *xmin) *xmin = i;
  if (j > *xmax) *xmax = j;
  if (i < len && j >= 0) {
    if (i == j) {
      // x0, x1 are the same pixel, so compute combined coverage
      scanline[i] += cast(ubyte)((x1-x0)*maxWeight>>NSVG__FIXSHIFT);
    } else {
      if (i >= 0) // add antialiasing for x0
        scanline[i] += cast(ubyte)(((NSVG__FIX-(x0&NSVG__FIXMASK))*maxWeight)>>NSVG__FIXSHIFT);
      else
        i = -1; // clip

      if (j < len) // add antialiasing for x1
        scanline[j] += cast(ubyte)(((x1&NSVG__FIXMASK)*maxWeight)>>NSVG__FIXSHIFT);
      else
        j = len; // clip

      for (++i; i < j; ++i) // fill pixels between x0 and x1
        scanline[i] += cast(ubyte)maxWeight;
    }
  }
}

// note: this routine clips fills that extend off the edges... ideally this
// wouldn't happen, but it could happen if the truetype glyph bounding boxes
// are wrong, or if the user supplies a too-small bitmap
void nsvg__fillActiveEdges (ubyte* scanline, int len, const(NSVGactiveEdge)* e, int maxWeight, int* xmin, int* xmax, char fillRule) {
  // non-zero winding fill
  int x0 = 0, w = 0;
  if (fillRule == NSVG.FillRule.NonZero) {
    // Non-zero
    while (e !is null) {
      if (w == 0) {
        // if we're currently at zero, we need to record the edge start point
        x0 = e.x; w += e.dir;
      } else {
        int x1 = e.x; w += e.dir;
        // if we went to zero, we need to draw
        if (w == 0) nsvg__fillScanline(scanline, len, x0, x1, maxWeight, xmin, xmax);
      }
      e = e.next;
    }
  } else if (fillRule == NSVG.FillRule.EvenOdd) {
    // Even-odd
    while (e !is null) {
      if (w == 0) {
        // if we're currently at zero, we need to record the edge start point
        x0 = e.x; w = 1;
      } else {
        int x1 = e.x; w = 0;
        nsvg__fillScanline(scanline, len, x0, x1, maxWeight, xmin, xmax);
      }
      e = e.next;
    }
  }
}

float nsvg__clampf() (float a, float mn, float mx) { pragma(inline, true); return (a < mn ? mn : (a > mx ? mx : a)); }

uint nsvg__RGBA() (ubyte r, ubyte g, ubyte b, ubyte a) { pragma(inline, true); return (r)|(g<<8)|(b<<16)|(a<<24); }

uint nsvg__lerpRGBA (uint c0, uint c1, float u) {
  int iu = cast(int)(nsvg__clampf(u, 0.0f, 1.0f)*256.0f);
  int r = (((c0)&0xff)*(256-iu)+(((c1)&0xff)*iu))>>8;
  int g = (((c0>>8)&0xff)*(256-iu)+(((c1>>8)&0xff)*iu))>>8;
  int b = (((c0>>16)&0xff)*(256-iu)+(((c1>>16)&0xff)*iu))>>8;
  int a = (((c0>>24)&0xff)*(256-iu)+(((c1>>24)&0xff)*iu))>>8;
  return nsvg__RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, cast(ubyte)a);
}

uint nsvg__applyOpacity (uint c, float u) {
  int iu = cast(int)(nsvg__clampf(u, 0.0f, 1.0f)*256.0f);
  int r = (c)&0xff;
  int g = (c>>8)&0xff;
  int b = (c>>16)&0xff;
  int a = (((c>>24)&0xff)*iu)>>8;
  return nsvg__RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, cast(ubyte)a);
}

int nsvg__div255() (int x) { pragma(inline, true); return ((x+1)*257)>>16; }

void nsvg__scanlineBit(
    ubyte* row, int count, ubyte* cover, int x, int y,
    float tx, float ty, float scale, const(NSVGcachedPaint)* cache)
{
    int x1 = x + count;
    for(; x < x1; x++) {
        row[x/8] |= 1 << (x % 8);
    }
}

void nsvg__scanlineSolid (ubyte* row, int count, ubyte* cover, int x, int y, float tx, float ty, float scale, const(NSVGcachedPaint)* cache) {

  ubyte* dst = row + x*4;

  if (cache.type == NSVG.PaintType.Color) {
    int cr = cache.colors[0]&0xff;
    int cg = (cache.colors[0]>>8)&0xff;
    int cb = (cache.colors[0]>>16)&0xff;
    int ca = (cache.colors[0]>>24)&0xff;

    foreach (int i; 0..count) {
      int r, g, b;
      int a = nsvg__div255(cast(int)cover[0]*ca);
      int ia = 255-a;
      // Premultiply
      r = nsvg__div255(cr*a);
      g = nsvg__div255(cg*a);
      b = nsvg__div255(cb*a);

      // Blend over
      r += nsvg__div255(ia*cast(int)dst[0]);
      g += nsvg__div255(ia*cast(int)dst[1]);
      b += nsvg__div255(ia*cast(int)dst[2]);
      a += nsvg__div255(ia*cast(int)dst[3]);

      dst[0] = cast(ubyte)r;
      dst[1] = cast(ubyte)g;
      dst[2] = cast(ubyte)b;
      dst[3] = cast(ubyte)a;

      ++cover;
      dst += 4;
    }
  } else if (cache.type == NSVG.PaintType.LinearGradient) {
    // TODO: spread modes.
    // TODO: plenty of opportunities to optimize.
    const(float)* t = cache.xform.ptr;
    //int i, cr, cg, cb, ca;
    //uint c;

    float fx = (x-tx)/scale;
    float fy = (y-ty)/scale;
    float dx = 1.0f/scale;

    foreach (int i; 0..count) {
      //int r, g, b, a, ia;
      float gy = fx*t[1]+fy*t[3]+t[5];
      uint c = cache.colors[cast(int)nsvg__clampf(gy*255.0f, 0, 255.0f)];
      int cr = (c)&0xff;
      int cg = (c>>8)&0xff;
      int cb = (c>>16)&0xff;
      int ca = (c>>24)&0xff;

      int a = nsvg__div255(cast(int)cover[0]*ca);
      int ia = 255-a;

      // Premultiply
      int r = nsvg__div255(cr*a);
      int g = nsvg__div255(cg*a);
      int b = nsvg__div255(cb*a);

      // Blend over
      r += nsvg__div255(ia*cast(int)dst[0]);
      g += nsvg__div255(ia*cast(int)dst[1]);
      b += nsvg__div255(ia*cast(int)dst[2]);
      a += nsvg__div255(ia*cast(int)dst[3]);

      dst[0] = cast(ubyte)r;
      dst[1] = cast(ubyte)g;
      dst[2] = cast(ubyte)b;
      dst[3] = cast(ubyte)a;

      ++cover;
      dst += 4;
      fx += dx;
    }
  } else if (cache.type == NSVG.PaintType.RadialGradient) {
    // TODO: spread modes.
    // TODO: plenty of opportunities to optimize.
    // TODO: focus (fx, fy)
    //float fx, fy, dx, gx, gy, gd;
    const(float)* t = cache.xform.ptr;
    //int i, cr, cg, cb, ca;
    //uint c;

    float fx = (x-tx)/scale;
    float fy = (y-ty)/scale;
    float dx = 1.0f/scale;

    foreach (int i; 0..count) {
      //int r, g, b, a, ia;
      float gx = fx*t[0]+fy*t[2]+t[4];
      float gy = fx*t[1]+fy*t[3]+t[5];
      float gd = sqrtf(gx*gx+gy*gy);
      uint c = cache.colors[cast(int)nsvg__clampf(gd*255.0f, 0, 255.0f)];
      int cr = (c)&0xff;
      int cg = (c>>8)&0xff;
      int cb = (c>>16)&0xff;
      int ca = (c>>24)&0xff;

      int a = nsvg__div255(cast(int)cover[0]*ca);
      int ia = 255-a;

      // Premultiply
      int r = nsvg__div255(cr*a);
      int g = nsvg__div255(cg*a);
      int b = nsvg__div255(cb*a);

      // Blend over
      r += nsvg__div255(ia*cast(int)dst[0]);
      g += nsvg__div255(ia*cast(int)dst[1]);
      b += nsvg__div255(ia*cast(int)dst[2]);
      a += nsvg__div255(ia*cast(int)dst[3]);

      dst[0] = cast(ubyte)r;
      dst[1] = cast(ubyte)g;
      dst[2] = cast(ubyte)b;
      dst[3] = cast(ubyte)a;

      ++cover;
      dst += 4;
      fx += dx;
    }
  }
}

void nsvg__rasterizeSortedEdges (NSVGrasterizer r, float tx, float ty, float scale, const(NSVGcachedPaint)* cache, char fillRule, const(NSVG.Clip)* clip) {
  NSVGactiveEdge* active = null;
  int s;
  int e = 0;
  int maxWeight = (255/NSVG__SUBSAMPLES);  // weight per vertical scanline
  int xmin, xmax;

  foreach (int y; 0..r.height) {
    import core.stdc.string : memset;
    memset(r.scanline, 0, r.width);
    xmin = r.width;
    xmax = 0;
    for (s = 0; s < NSVG__SUBSAMPLES; ++s) {
      // find center of pixel for this scanline
      float scany = y*NSVG__SUBSAMPLES+s+0.5f;
      NSVGactiveEdge** step = &active;

      // update all active edges;
      // remove all active edges that terminate before the center of this scanline
      while (*step) {
        NSVGactiveEdge* z = *step;
        if (z.ey <= scany) {
          *step = z.next; // delete from list
          //NSVG__assert(z.valid);
          nsvg__freeActive(r, z);
        } else {
          z.x += z.dx; // advance to position for current scanline
          step = &((*step).next); // advance through list
        }
      }

      // resort the list if needed
      for (;;) {
        int changed = 0;
        step = &active;
        while (*step && (*step).next) {
          if ((*step).x > (*step).next.x) {
            NSVGactiveEdge* t = *step;
            NSVGactiveEdge* q = t.next;
            t.next = q.next;
            q.next = t;
            *step = q;
            changed = 1;
          }
          step = &(*step).next;
        }
        if (!changed) break;
      }

      // insert all edges that start before the center of this scanline -- omit ones that also end on this scanline
      while (e < r.nedges && r.edges[e].y0 <= scany) {
        if (r.edges[e].y1 > scany) {
          NSVGactiveEdge* z = nsvg__addActive(r, &r.edges[e], scany);
          if (z is null) break;
          // find insertion point
          if (active is null) {
            active = z;
          } else if (z.x < active.x) {
            // insert at front
            z.next = active;
            active = z;
          } else {
            // find thing to insert AFTER
            NSVGactiveEdge* p = active;
            while (p.next && p.next.x < z.x)
              p = p.next;
            // at this point, p.next.x is NOT < z.x
            z.next = p.next;
            p.next = z;
          }
        }
        e++;
      }

      // now process all active edges in non-zero fashion
      if (active !is null)
        nsvg__fillActiveEdges(r.scanline, r.width, active, maxWeight, &xmin, &xmax, fillRule);
    }
    // Blit
    if (xmin < 0) xmin = 0;
    if (xmax > r.width-1) xmax = r.width-1;
    if (xmin <= xmax) {
      //nsvg__scanlineSolid(&r.bitmap[y*r.stride]+xmin*4, xmax-xmin+1, &r.scanline[xmin], xmin, y, tx, ty, scale, cache);
      int i, j;
      for(i = 0; i < clip.count; i++) {
        ubyte* stencil = &r.stencil[r.stencilSize * clip.index[i] + y * r.stencilStride];
        for(j = xmin; j <= xmax; j++) {
            if(((stencil[j/8]>> (j % 8)) & 1) == 0) {
                r.scanline[j] = 0;
            }
        }
      }

      r.fscanline(&r.bitmap[y * r.stride], xmax-xmin+1, &r.scanline[xmin], xmin, y, tx, ty, scale, cache);
    }
  }

}

void nsvg__unpremultiplyAlpha (ubyte* image, int w, int h, int stride) {
  // Unpremultiply
  foreach (int y; 0..h) {
    ubyte *row = &image[y*stride];
    foreach (int x; 0..w) {
      int r = row[0], g = row[1], b = row[2], a = row[3];
      if (a != 0) {
        row[0] = cast(ubyte)(r*255/a);
        row[1] = cast(ubyte)(g*255/a);
        row[2] = cast(ubyte)(b*255/a);
      }
      row += 4;
    }
  }

  // Defringe
  foreach (int y; 0..h) {
    ubyte *row = &image[y*stride];
    foreach (int x; 0..w) {
      int r = 0, g = 0, b = 0, a = row[3], n = 0;
      if (a == 0) {
        if (x-1 > 0 && row[-1] != 0) {
          r += row[-4];
          g += row[-3];
          b += row[-2];
          n++;
        }
        if (x+1 < w && row[7] != 0) {
          r += row[4];
          g += row[5];
          b += row[6];
          n++;
        }
        if (y-1 > 0 && row[-stride+3] != 0) {
          r += row[-stride];
          g += row[-stride+1];
          b += row[-stride+2];
          n++;
        }
        if (y+1 < h && row[stride+3] != 0) {
          r += row[stride];
          g += row[stride+1];
          b += row[stride+2];
          n++;
        }
        if (n > 0) {
          row[0] = cast(ubyte)(r/n);
          row[1] = cast(ubyte)(g/n);
          row[2] = cast(ubyte)(b/n);
        }
      }
      row += 4;
    }
  }
}


void nsvg__initPaint (NSVGcachedPaint* cache, const(NSVG.Paint)* paint, float opacity) {
  const(NSVG.Gradient)* grad;

  cache.type = paint.type;

  if (paint.type == NSVG.PaintType.Color) {
    cache.colors[0] = nsvg__applyOpacity(paint.color, opacity);
    return;
  }

  grad = paint.gradient;

  cache.spread = grad.spread;
  //memcpy(cache.xform.ptr, grad.xform.ptr, float.sizeof*6);
  cache.xform[0..6] = grad.xform[0..6];

  if (grad.nstops == 0) {
    //for (i = 0; i < 256; i++) cache.colors[i] = 0;
    cache.colors[0..256] = 0;
  } if (grad.nstops == 1) {
    foreach (int i; 0..256) cache.colors[i] = nsvg__applyOpacity(grad.stops.ptr[i].color, opacity);
  } else {
    uint cb = 0;
    //float ua, ub, du, u;
    int ia, ib, count;

    uint ca = nsvg__applyOpacity(grad.stops.ptr[0].color, opacity);
    float ua = nsvg__clampf(grad.stops.ptr[0].offset, 0, 1);
    float ub = nsvg__clampf(grad.stops.ptr[grad.nstops-1].offset, ua, 1);
    ia = cast(int)(ua*255.0f);
    ib = cast(int)(ub*255.0f);
    //for (i = 0; i < ia; i++) cache.colors[i] = ca;
    cache.colors[0..ia] = ca;

    foreach (int i; 0..grad.nstops-1) {
      ca = nsvg__applyOpacity(grad.stops.ptr[i].color, opacity);
      cb = nsvg__applyOpacity(grad.stops.ptr[i+1].color, opacity);
      ua = nsvg__clampf(grad.stops.ptr[i].offset, 0, 1);
      ub = nsvg__clampf(grad.stops.ptr[i+1].offset, 0, 1);
      ia = cast(int)(ua*255.0f);
      ib = cast(int)(ub*255.0f);
      count = ib-ia;
      if (count <= 0) continue;
      float u = 0;
      immutable float du = 1.0f/cast(float)count;
      foreach (int j; 0..count) {
        cache.colors[ia+j] = nsvg__lerpRGBA(ca, cb, u);
        u += du;
      }
    }

    //for (i = ib; i < 256; i++) cache.colors[i] = cb;
    cache.colors[ib..256] = cb;
  }

}

extern(C) {
  private alias _compare_fp_t = int function (const void*, const void*) nothrow @nogc;
  private extern(C) void qsort (scope void* base, size_t nmemb, size_t size, _compare_fp_t compar) nothrow @nogc;
}

/**
 * Rasterizes SVG image, returns RGBA image (non-premultiplied alpha).
 *
 * Params:
 *   r = pointer to rasterizer context
 *   image = pointer to SVG image to rasterize
 *   tx, ty = image offset (applied after scaling)
 *   scale = image scale
 *   dst = pointer to destination image data, 4 bytes per pixel (RGBA)
 *   w = width of the image to render
 *   h = height of the image to render
 *   stride = number of bytes per scaleline in the destination buffer
 */
public void rasterize (NSVGrasterizer r, const(NSVG)* image, float tx, float ty, float scale, ubyte* dst, int w, int h, int stride=-1) {
  for (int i = 0; i < h; i++) {
    import core.stdc.string : memset;
    memset(&dst[i*stride], 0, w*4);
  }

  rasterizeClipPaths(r, image, w, h, tx, ty, scale);
  rasterizeShapes(r, image.shapes, tx, ty, scale, dst,w, h, stride, &nsvg__scanlineSolid);

  nsvg__unpremultiplyAlpha(dst, w, h, stride);
}

private void rasterizeClipPaths(NSVGrasterizer r, const(NSVG)* image, int w, int h, float tx, float ty, float scale) {
    const(NSVG.ClipPath)* clipPath = image.clipPaths;
    int clipPathCount = 0;

    if(clipPath is null) {
        r.stencil = null;
        return;
    }

    while(clipPath !is null) {
        clipPathCount++;
        clipPath = clipPath.next;
    }

    r.stencilStride = w / 8 + (w % 8 != 0 ? 1 : 0);
    r.stencilSize = h * r.stencilStride;
    import core.stdc.stdlib;
    r.stencil = cast(ubyte*) realloc(r.stencil, r.stencilSize * clipPathCount);
    if(r.stencil is null) return;
    r.stencil[0 .. r.stencilSize * clipPathCount] = 0;

    clipPath = image.clipPaths;
    while(clipPath !is null) {
        rasterizeShapes(r, clipPath.shapes, tx, ty, scale, &r.stencil[r.stencilSize * clipPath.index], w, h, r.stencilStride, &nsvg__scanlineBit);
        clipPath = clipPath.next;
    }
}

private void rasterizeShapes (NSVGrasterizer r, const(NSVG.Shape)* shapes, float tx, float ty, float scale, ubyte* dst, int w, int h, int stride, NSVGscanlineFunction fscanline) {
  const(NSVG.Shape)* shape = null;
  NSVGedge* e = null;
  NSVGcachedPaint cache;
  int i;

  if (stride <= 0) stride = w*4;
  r.bitmap = dst;
  r.width = w;
  r.height = h;
  r.stride = stride;
  r.fscanline = fscanline;

  if (w > r.cscanline) {
    import core.stdc.stdlib : realloc;
    r.cscanline = w;
    r.scanline = cast(ubyte*)realloc(r.scanline, w+256);
    if (r.scanline is null) assert(0, "nanosvg: out of memory");
  }

  /+

  for (shape = image.shapes; shape !is null; shape = shape.next) {
  +/
  for (shape = shapes; shape !is null; shape = shape.next) {
    if (!(shape.flags&NSVG.Visible)) continue;

    if (shape.fill.type != NSVG.PaintType.None) {
      //import core.stdc.stdlib : qsort; // not @nogc

      nsvg__resetPool(r);
      r.freelist = null;
      r.nedges = 0;

      nsvg__flattenShape(r, shape, scale);

      // Scale and translate edges
      for (i = 0; i < r.nedges; i++) {
        e = &r.edges[i];
        e.x0 = tx+e.x0;
        e.y0 = (ty+e.y0)*NSVG__SUBSAMPLES;
        e.x1 = tx+e.x1;
        e.y1 = (ty+e.y1)*NSVG__SUBSAMPLES;
      }

      // Rasterize edges
      if(r.nedges != 0)
        qsort(r.edges, r.nedges, NSVGedge.sizeof, &nsvg__cmpEdge);

      // now, traverse the scanlines and find the intersections on each scanline, use non-zero rule
      nsvg__initPaint(&cache, &shape.fill, shape.opacity);

      nsvg__rasterizeSortedEdges(r, tx, ty, scale, &cache, shape.fillRule, &shape.clip);
    }
    if (shape.stroke.type != NSVG.PaintType.None && (shape.strokeWidth*scale) > 0.01f) {
      //import core.stdc.stdlib : qsort; // not @nogc

      nsvg__resetPool(r);
      r.freelist = null;
      r.nedges = 0;

      nsvg__flattenShapeStroke(r, shape, scale);

      //dumpEdges(r, "edge.svg");

      // Scale and translate edges
      for (i = 0; i < r.nedges; i++) {
        e = &r.edges[i];
        e.x0 = tx+e.x0;
        e.y0 = (ty+e.y0)*NSVG__SUBSAMPLES;
        e.x1 = tx+e.x1;
        e.y1 = (ty+e.y1)*NSVG__SUBSAMPLES;
      }

      // Rasterize edges
      if(r.nedges != 0)
        qsort(r.edges, r.nedges, NSVGedge.sizeof, &nsvg__cmpEdge);

      // now, traverse the scanlines and find the intersections on each scanline, use non-zero rule
      nsvg__initPaint(&cache, &shape.stroke, shape.opacity);

      nsvg__rasterizeSortedEdges(r, tx, ty, scale, &cache, NSVG.FillRule.NonZero, &shape.clip);
    }
  }

  r.bitmap = null;
  r.width = 0;
  r.height = 0;
  r.stride = 0;
  r.fscanline = null;
}

} // nothrow @trusted @nogc


// ////////////////////////////////////////////////////////////////////////// //
ptrdiff_t xindexOf (const(void)[] hay, const(void)[] need, usize stIdx=0) pure @trusted nothrow @nogc {
  if (hay.length <= stIdx || need.length == 0 || need.length > hay.length-stIdx) {
    return -1;
  } else {
    //import iv.strex : memmem;
    auto res = memmem(hay.ptr+stIdx, hay.length-stIdx, need.ptr, need.length);
    return (res !is null ? cast(ptrdiff_t)(res-hay.ptr) : -1);
  }
}

ptrdiff_t xindexOf (const(void)[] hay, ubyte ch, usize stIdx=0) pure @trusted nothrow @nogc {
  return xindexOf(hay, (&ch)[0..1], stIdx);
}

pure nothrow @trusted @nogc:
version(linux) {
  extern(C) inout(void)* memmem (inout(void)* haystack, usize haystacklen, inout(void)* needle, usize needlelen);
} else {
  inout(void)* memmem (inout(void)* haystack, usize haystacklen, inout(void)* needle, usize needlelen) {
    auto h = cast(const(ubyte)*)haystack;
    auto n = cast(const(ubyte)*)needle;
    // usize is unsigned
    if (needlelen > haystacklen) return null;
    foreach (immutable i; 0..haystacklen-needlelen+1) {
      import core.stdc.string : memcmp;
      if (memcmp(h+i, n, needlelen) == 0) return cast(void*)(h+i);
    }
    return null;
  }
}
