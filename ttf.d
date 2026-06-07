/++
	TrueType Font rendering. Meant to be used with [arsd.simpledisplay], but it doesn't actually require that. Port of stb_truetype plus D wrappers for convenience.


	Credits: Started as a copy of stb_truetype by Sean Barrett and ketmar helped
	with expansions.
+/
module arsd.ttf;

// stb_truetype.h - v1.19 - public domain
// authored from 2009-2016 by Sean Barrett / RAD Game Tools
//
// http://nothings.org/stb/stb_truetype.h
//
// port to D by adam d. ruppe (v.6) and massively updated ketmar. see the link above for more info about the lib and real author.

// here's some D convenience functions

// need to do some print glyphs t it....


///
struct TtfFont {
	stbtt_fontinfo font;
	///
	this(in ubyte[] data) {
		load(data);
	}

	///
	void load(in ubyte[] data) {
		if(stbtt_InitFont(&font, data.ptr, stbtt_GetFontOffsetForIndex(data.ptr, 0)) == 0)
			throw new Exception("load font problem");
	}

	/// Note that you must stbtt_FreeBitmap(returnValue.ptr, null); this thing or it will leak!!!!
	ubyte[] renderCharacter(dchar c, int size, out int width, out int height, float shift_x = 0.0, float shift_y = 0.0) {
 		auto ptr = stbtt_GetCodepointBitmapSubpixel(&font, 0.0,stbtt_ScaleForPixelHeight(&font, size),
			shift_x, shift_y, c, &width, &height, null,null);
		return ptr[0 .. width * height];
	}

	///
	void getStringSize(in char[] s, int size, out int width, out int height) {
		float xpos=0;

		auto scale = stbtt_ScaleForPixelHeight(&font, size);
		int ascent, descent, line_gap;
		stbtt_GetFontVMetrics(&font, &ascent,&descent,&line_gap);
		auto baseline = cast(int) (ascent*scale);

		import std.math;

		int maxWidth;

		foreach(i, dchar ch; s) {
			int advance,lsb;
			auto x_shift = xpos - floor(xpos);
			stbtt_GetCodepointHMetrics(&font, ch, &advance, &lsb);

			int x0, y0, x1, y1;
			stbtt_GetCodepointBitmapBoxSubpixel(&font, ch, scale,scale,x_shift,0, &x0,&y0,&x1,&y1);

			maxWidth = cast(int)(xpos + x1);

			xpos += (advance * scale);
			if (i + 1 < s.length)
				xpos += scale*stbtt_GetCodepointKernAdvance(&font, ch,s[i+1]);
		}

		width = maxWidth;
		height = size;
	}

	///
	ubyte[] renderString(in char[] s, int size, out int width, out int height) {
		float xpos=0;

		auto scale = stbtt_ScaleForPixelHeight(&font, size);
		int ascent, descent, line_gap;
		stbtt_GetFontVMetrics(&font, &ascent,&descent,&line_gap);
		auto baseline = cast(int) (ascent*scale);

		import std.math;

		int swidth;
		int sheight;
		getStringSize(s, size, swidth, sheight);
		auto screen = new ubyte[](swidth * sheight);

		foreach(i, dchar ch; s) {
			int advance,lsb;
			auto x_shift = xpos - floor(xpos);
			stbtt_GetCodepointHMetrics(&font, ch, &advance, &lsb);
			int cw, cheight;
			auto c = renderCharacter(ch, size, cw, cheight, x_shift, 0.0);
			scope(exit) stbtt_FreeBitmap(c.ptr, null);

			int x0, y0, x1, y1;
			stbtt_GetCodepointBitmapBoxSubpixel(&font, ch, scale,scale,x_shift,0, &x0,&y0,&x1,&y1);

			int x = cast(int) xpos + x0;
			int y = baseline + y0;
			int cx = 0;
			foreach(index, pixel; c) {
				if(cx == cw) {
					cx = 0;
					y++;
					x = cast(int) xpos + x0;
				}
				auto offset = swidth * y + x;
				if(offset >= screen.length)
					break;
				int val = (cast(int) pixel * (255 - screen[offset]) / 255);
				if(val > 255)
					val = 255;
				screen[offset] += cast(ubyte)(val);
				x++;
				cx++;
			}

			//stbtt_MakeCodepointBitmapSubpixel(&font, &screen[(baseline + y0) * swidth + cast(int) xpos + x0], x1-x0,y1-y0, 79, scale,scale,      x_shift,0, ch);
			// note that this stomps the old data, so where character boxes overlap (e.g. 'lj') it's wrong
			// because this API is really for baking character bitmaps into textures. if you want to render
			// a sequence of characters, you really need to render each bitmap to a temp buffer, then
			// "alpha blend" that into the working buffer
			xpos += (advance * scale);
			if (i + 1 < s.length)
				xpos += scale*stbtt_GetCodepointKernAdvance(&font, ch,s[i+1]);
		}

		width = swidth;
		height = sheight;

		return screen;
	}

	// ~this() {}
}

/// Version of OpenGL you want it to use. Currently only two options.
enum OpenGlFontGLVersion {
	old, /// old style glBegin/glEnd stuff
	shader, /// newer style shader stuff
}

/+
	This is mostly there if you want to draw different pieces together in
	different colors or across different boxes (see what text didn't fit, etc.).

	Used only with [OpenGlLimitedFont] right now.
+/
struct DrawingTextContext {
	const(char)[] text; /// remaining text
	float x; /// current position of the baseline
	float y; /// ditto

	const int left; /// bounding box, if applicable
	const int top; /// ditto
	const int right; /// ditto
	const int bottom; /// ditto
}

abstract class OpenGlLimitedFontBase() {
	void createShaders() {}
	abstract uint glFormat();
	abstract void startDrawing(Color color);
	abstract void addQuad(
		float s0, float t0, float x0, float y0,
		float s1, float t1, float x1, float y1
	);
	abstract void finishDrawing();


// FIXME: does this kern?
// FIXME: it would be cool if it did per-letter transforms too like word art. make it tangent to some baseline

	import arsd.simpledisplay;

	static private int nextPowerOfTwo(int v) {
		v--;
		v |= v >> 1;
		v |= v >> 2;
		v |= v >> 4;
		v |= v >> 8;
		v |= v >> 16;
		v++;
		return v;
	}

	uint _tex;
	stbtt_bakedchar[] charInfo;

	import arsd.color;

	/++

		Tip: if color == Color.transparent, it will not actually attempt to draw to OpenGL. You can use this
		to help plan pagination inside the bounding box.

	+/
	public final DrawingTextContext drawString(int x, int y, in char[] text, Color color = Color.white, Rectangle boundingBox = Rectangle.init) {
		if(boundingBox == Rectangle.init) {
			// if you hit a newline, at least keep it aligned here if something wasn't
			// explicitly given.
			boundingBox.left = x;
			boundingBox.top = y;
			boundingBox.right = int.max;
			boundingBox.bottom = int.max;
		}
		DrawingTextContext dtc = DrawingTextContext(text, x, y, boundingBox.tupleof);
		drawString(dtc, color);
		return dtc;
	}

	/++
		It won't attempt to draw partial characters if it butts up against the bounding box, unless
		word wrap was impossible. Use clipping if you need to cover that up and guarantee it never goes
		outside the bounding box ever.

	+/
	public final void drawString(ref DrawingTextContext context, Color color = Color.white) {
		bool actuallyDraw = color != Color.transparent;

		if(actuallyDraw) {
			startDrawing(color);
		}

		bool newWord = true;
		bool atStartOfLine = true;
		float currentWordLength;
		int currentWordCharsRemaining;

		void calculateWordInfo() {
			const(char)[] copy = context.text;
			currentWordLength = 0.0;
			currentWordCharsRemaining = 0;

			while(copy.length) {
				auto ch = copy[0];
				copy = copy[1 .. $];

				currentWordCharsRemaining++;

				if(ch <= 32)
					break; // not in a word anymore

				if(ch < firstChar || ch > lastChar)
					continue;

				const b = charInfo[cast(int) ch - cast(int) firstChar];

				currentWordLength += b.xadvance;
			}
		}

		bool newline() {
			context.x = context.left;
			context.y += lineHeight;
			atStartOfLine = true;

			if(context.y + descent > context.bottom)
				return false;

			return true;
		}

		while(context.text.length) {
			if(newWord) {
				calculateWordInfo();
				newWord = false;

				if(context.x + currentWordLength > context.right) {
					if(!newline())
						break; // ran out of space
				}
			}

			// FIXME i should prolly UTF-8 decode....
			dchar ch = context.text[0];
			context.text = context.text[1 .. $];

			if(currentWordCharsRemaining) {
				currentWordCharsRemaining--;

				if(currentWordCharsRemaining == 0)
					newWord = true;
			}

			if(ch == '\t') {
				context.x += 20;
				continue;
			}
			if(ch == '\n') {
				if(newline())
					continue;
				else
					break;
			}

			if(ch < firstChar || ch > lastChar) {
				if(ch == ' ')
					context.x += lineHeight / 4; // fake space if not available in formal font (I recommend you do include it though)
				continue;
			}

			const b = charInfo[cast(int) ch - cast(int) firstChar];

			int round_x = STBTT_ifloor((context.x + b.xoff) + 0.5f);
			int round_y = STBTT_ifloor((context.y + b.yoff) + 0.5f);

			// box to draw on the screen
			auto x0 = round_x;
			auto y0 = round_y;
			auto x1 = round_x + b.x1 - b.x0;
			auto y1 = round_y + b.y1 - b.y0;

			// is that outside the bounding box we should draw in?
			// if so on x, wordwrap to the next line. if so on y,
			// return prematurely and let the user context handle it if needed.

			// box to fetch off the surface
			auto s0 = b.x0 * ipw;
			auto t0 = b.y0 * iph;
			auto s1 = b.x1 * ipw;
			auto t1 = b.y1 * iph;

			if(actuallyDraw) {
				addQuad(s0, t0, x0, y0, s1, t1, x1, y1);
			}

			context.x += b.xadvance;
		}

		if(actuallyDraw)
			finishDrawing();
	}

	private {
		const dchar firstChar;
		const dchar lastChar;
		const int pw;
		const int ph;
		const float ipw;
		const float iph;
	}

	public const int lineHeight; /// metrics

	public const int ascent; /// ditto
	public const int descent; /// ditto
	public const int line_gap; /// ditto;

	/++

	+/
	public this(const ubyte[] ttfData, float fontPixelHeight, dchar firstChar = 32, dchar lastChar = 127) {

		assert(lastChar > firstChar);
		assert(fontPixelHeight > 0);

		this.firstChar = firstChar;
		this.lastChar = lastChar;

		int numChars = 1 + cast(int) lastChar - cast(int) firstChar;

		lineHeight = cast(int) (fontPixelHeight + 0.5);

		import std.math;
		// will most likely be 512x512ish; about 256k likely
		int height = cast(int) (fontPixelHeight + 1) * cast(int) (sqrt(cast(float) numChars) + 1);
		height = nextPowerOfTwo(height);
		int width = height;

		this.pw = width;
		this.ph = height;

		ipw = 1.0f / pw;
		iph = 1.0f / ph;

		int len = width * height;

		//import std.stdio; writeln(len);

		import core.stdc.stdlib;
		ubyte[] buffer = (cast(ubyte*) malloc(len))[0 .. len];
		if(buffer is null) assert(0);
		scope(exit) free(buffer.ptr);

		charInfo.length = numChars;

		int ascent, descent, line_gap;

		if(stbtt_BakeFontBitmap(
			ttfData.ptr, 0,
			fontPixelHeight,
			buffer.ptr, width, height,
			cast(int) firstChar, numChars,
			charInfo.ptr,
			&ascent, &descent, &line_gap
		) == 0)
			throw new Exception("bake font didn't work");

		this.ascent = ascent;
		this.descent = descent;
		this.line_gap = line_gap;

		assert(openGLCurrentContext() !is null);

		glGenTextures(1, &_tex);
		glBindTexture(GL_TEXTURE_2D, _tex);
		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

		glTexImage2D(
			GL_TEXTURE_2D,
			0,
			glFormat,
			width,
			height,
			0,
			glFormat,
			GL_UNSIGNED_BYTE,
			buffer.ptr);

		checkGlError();

		glBindTexture(GL_TEXTURE_2D, 0);

		createShaders();
	}


}

/++
	Note that the constructor calls OpenGL functions and thus this must be called AFTER
	the context creation, e.g. on simpledisplay's window first visible delegate.

	Any text with characters outside the range you bake in the constructor are simply
	ignored - that's why it is called "limited" font. The [TtfFont] struct can generate
	any string on-demand which is more flexible, and even faster for strings repeated
	frequently, but slower for frequently-changing or one-off strings. That's what this
	class is made for.

	History:
		Added April 24, 2020
+/
final class OpenGlLimitedFont(OpenGlFontGLVersion ver = OpenGlFontGLVersion.old) : OpenGlLimitedFontBase!() {
	import arsd.simpledisplay;
	static if(OpenGlEnabled):
		import arsd.color;

	public this(const ubyte[] ttfData, float fontPixelHeight, dchar firstChar = 32, dchar lastChar = 127) {
		super(ttfData, fontPixelHeight, firstChar, lastChar);
	}


	override uint glFormat() {
		// on new-style opengl this is the required value
		static if(ver == OpenGlFontGLVersion.shader)
			return GL_RED;
		else
			return GL_ALPHA;

	}

	static if(ver == OpenGlFontGLVersion.shader) {
		private OpenGlShader shader;
		private static struct Vertex {
			this(float a, float b, float c, float d, float e = 0.0) {
				t[0] = a;
				t[1] = b;
				xyz[0] = c;
				xyz[1] = d;
				xyz[2] = e;
			}
			float[2] t;
			float[3] xyz;
		}
		private GlObject!Vertex glo;
		// GL_DYNAMIC_DRAW FIXME
		private Vertex[] vertixes;
		private uint[] indexes;

		public BasicMatrix!(4, 4) mymatrix;
		public BasicMatrix!(4, 4) projection;

		override void createShaders() {
			mymatrix.loadIdentity();
			projection.loadIdentity();

			shader = new OpenGlShader(
				OpenGlShader.Source(GL_VERTEX_SHADER, `
					#version 330 core

					`~glo.generateShaderDefinitions()~`

					out vec2 texCoord;

					uniform mat4 mymatrix;
					uniform mat4 projection;

					void main() {
						gl_Position = projection * mymatrix * vec4(xyz, 1.0);
						texCoord = t;
					}
				`),
				OpenGlShader.Source(GL_FRAGMENT_SHADER, `
					#version 330 core

					in vec2 texCoord;

					out vec4 FragColor;

					uniform vec4 color;
					uniform sampler2D tex;

					void main() {
						FragColor = color * vec4(1, 1, 1, texture(tex, texCoord).r);
					}
				`),
			);
		}
	}

	override void startDrawing(Color color) {
		glBindTexture(GL_TEXTURE_2D, _tex);

		static if(ver == OpenGlFontGLVersion.shader) {
			shader.use();
			shader.uniforms.color() = OGL.vec4f(cast(float)color.r/255.0, cast(float)color.g/255.0, cast(float)color.b/255.0, cast(float)color.a / 255.0);

			shader.uniforms.mymatrix() = OGL.mat4x4f(mymatrix.data);
			shader.uniforms.projection() = OGL.mat4x4f(projection.data);
		} else {
			glColor4f(cast(float)color.r/255.0, cast(float)color.g/255.0, cast(float)color.b/255.0, cast(float)color.a / 255.0);
		}
	}
	override void addQuad(
		float s0, float t0, float x0, float y0,
		float s1, float t1, float x1, float y1
	) {
		static if(ver == OpenGlFontGLVersion.shader) {
			auto idx = cast(int) vertixes.length;
			vertixes ~= [
				Vertex(s0, t0, x0, y0),
				Vertex(s1, t0, x1, y0),
				Vertex(s1, t1, x1, y1),
				Vertex(s0, t1, x0, y1),
			];

			indexes ~= [
				idx + 0,
				idx + 1,
				idx + 3,
				idx + 1,
				idx + 2,
				idx + 3,
			];
		} else {
			glBegin(GL_QUADS);
				glTexCoord2f(s0, t0); 		glVertex2f(x0, y0);
				glTexCoord2f(s1, t0); 		glVertex2f(x1, y0);
				glTexCoord2f(s1, t1); 		glVertex2f(x1, y1);
				glTexCoord2f(s0, t1); 		glVertex2f(x0, y1);
			glEnd();
		}
	}
	override void finishDrawing() {
		static if(ver == OpenGlFontGLVersion.shader) {
			glo = new typeof(glo)(vertixes, indexes);
			glo.draw();
			vertixes = vertixes[0..0];
			vertixes.assumeSafeAppend();
			indexes = indexes[0..0];
			indexes.assumeSafeAppend();
		}
		glBindTexture(GL_TEXTURE_2D, 0); // unbind the texture
	}

}


// test program
/+
int main(string[] args)
{
import std.conv;
import arsd.simpledisplay;
   int c = (args.length > 1 ? to!int(args[1]) : 'a'), s = (args.length > 2 ? to!int(args[2]) : 20);
import std.file;

   auto font = TtfFont(cast(ubyte[]) /*import("sans-serif.ttf"));//*/std.file.read(args.length > 3 ? args[3] : "sans-serif.ttf"));

   int w, h;
   auto bitmap = font.renderString("Hejlqo, world!qMpj", s, w, h);
	auto img = new Image(w, h);

   for (int j=0; j < h; ++j) {
      for (int i=0; i < w; ++i)
         img.putPixel(i, j, Color(0, (bitmap[j*w+i] > 128) ? 255 : 0, 0));
   }
   img.displayImage();
   return 0;
}
+/




// STB_TTF FOLLOWS


nothrow @trusted @nogc:

version = STB_RECT_PACK_VERSION;

// ////////////////////////////////////////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////////
// //
// //  SAMPLE PROGRAMS
// //
//
//  Incomplete text-in-3d-api example, which draws quads properly aligned to be lossless
//
/+
#if 0
#define STB_TRUETYPE_IMPLEMENTATION  // force following include to generate implementation
#include "stb_truetype.h"

unsigned char ttf_buffer[1<<20];
unsigned char temp_bitmap[512*512];

stbtt_bakedchar cdata[96]; // ASCII 32..126 is 95 glyphs
GLuint ftex;

void my_stbtt_initfont(void)
{
   fread(ttf_buffer, 1, 1<<20, fopen("c:/windows/fonts/times.ttf", "rb"));
   stbtt_BakeFontBitmap(ttf_buffer,0, 32.0, temp_bitmap,512,512, 32,96, cdata); // no guarantee this fits!
   // can free ttf_buffer at this point
   glGenTextures(1, &ftex);
   glBindTexture(GL_TEXTURE_2D, ftex);
   glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, 512,512, 0, GL_ALPHA, GL_UNSIGNED_BYTE, temp_bitmap);
   // can free temp_bitmap at this point
   glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
}

void my_stbtt_print(float x, float y, char *text)
{
   // assume orthographic projection with units = screen pixels, origin at top left
   glEnable(GL_TEXTURE_2D);
   glBindTexture(GL_TEXTURE_2D, ftex);
   glBegin(GL_QUADS);
   while (*text) {
      if (*text >= 32 && *text < 128) {
         stbtt_aligned_quad q;
         stbtt_GetBakedQuad(cdata, 512,512, *text-32, &x,&y,&q,1);//1=opengl & d3d10+,0=d3d9
         glTexCoord2f(q.s0,q.t1); glVertex2f(q.x0,q.y0);
         glTexCoord2f(q.s1,q.t1); glVertex2f(q.x1,q.y0);
         glTexCoord2f(q.s1,q.t0); glVertex2f(q.x1,q.y1);
         glTexCoord2f(q.s0,q.t0); glVertex2f(q.x0,q.y1);
      }
      ++text;
   }
   glEnd();
}
#endif
//
//
// ////////////////////////////////////////////////////////////////////////////
//
// Complete program (this compiles): get a single bitmap, print as ASCII art
//
#if 0
#include <stdio.h>
#define STB_TRUETYPE_IMPLEMENTATION  // force following include to generate implementation
#include "stb_truetype.h"

char ttf_buffer[1<<25];

int main(int argc, char **argv)
{
   stbtt_fontinfo font;
   unsigned char *bitmap;
   int w,h,i,j,c = (argc > 1 ? atoi(argv[1]) : 'a'), s = (argc > 2 ? atoi(argv[2]) : 20);

   fread(ttf_buffer, 1, 1<<25, fopen(argc > 3 ? argv[3] : "c:/windows/fonts/arialbd.ttf", "rb"));

   stbtt_InitFont(&font, ttf_buffer, stbtt_GetFontOffsetForIndex(ttf_buffer,0));
   bitmap = stbtt_GetCodepointBitmap(&font, 0,stbtt_ScaleForPixelHeight(&font, s), c, &w, &h, 0,0);

   for (j=0; j < h; ++j) {
      for (i=0; i < w; ++i)
         putchar(" .:ioVM@"[bitmap[j*w+i]>>5]);
      putchar('\n');
   }
   return 0;
}
#endif
//
// Output:
//
//     .ii.
//    @@@@@@.
//   V@Mio@@o
//   :i.  V@V
//     :oM@@M
//   :@@@MM@M
//   @@o  o@M
//  :@@.  M@M
//   @@@o@@@@
//   :M@@V:@@.
//
//////////////////////////////////////////////////////////////////////////////
//
// Complete program: print "Hello World!" banner, with bugs
//
#if 0
char buffer[24<<20];
unsigned char screen[20][79];

int main(int arg, char **argv)
{
   stbtt_fontinfo font;
   int i,j,ascent,baseline,ch=0;
   float scale, xpos=2; // leave a little padding in case the character extends left
   char *text = "Heljo World!"; // intentionally misspelled to show 'lj' brokenness

   fread(buffer, 1, 1000000, fopen("c:/windows/fonts/arialbd.ttf", "rb"));
   stbtt_InitFont(&font, buffer, 0);

   scale = stbtt_ScaleForPixelHeight(&font, 15);
   stbtt_GetFontVMetrics(&font, &ascent,0,0);
   baseline = (int) (ascent*scale);

   while (text[ch]) {
      int advance,lsb,x0,y0,x1,y1;
      float x_shift = xpos - (float) floor(xpos);
      stbtt_GetCodepointHMetrics(&font, text[ch], &advance, &lsb);
      stbtt_GetCodepointBitmapBoxSubpixel(&font, text[ch], scale,scale,x_shift,0, &x0,&y0,&x1,&y1);
      stbtt_MakeCodepointBitmapSubpixel(&font, &screen[baseline + y0][(int) xpos + x0], x1-x0,y1-y0, 79, scale,scale,x_shift,0, text[ch]);
      // note that this stomps the old data, so where character boxes overlap (e.g. 'lj') it's wrong
      // because this API is really for baking character bitmaps into textures. if you want to render
      // a sequence of characters, you really need to render each bitmap to a temp buffer, then
      // "alpha blend" that into the working buffer
      xpos += (advance * scale);
      if (text[ch+1])
         xpos += scale*stbtt_GetCodepointKernAdvance(&font, text[ch],text[ch+1]);
      ++ch;
   }

   for (j=0; j < 20; ++j) {
      for (i=0; i < 78; ++i)
         putchar(" .:ioVM@"[screen[j][i]>>5]);
      putchar('\n');
   }

   return 0;
}
#endif
+/

// ////////////////////////////////////////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////////
// //
// //   INTEGRATION WITH YOUR CODEBASE
// //
// //   The following sections allow you to supply alternate definitions
// //   of C library functions used by stb_truetype, e.g. if you don't
// //   link with the C runtime library.

// #define your own (u)stbtt_int8/16/32 before including to override this
alias stbtt_uint8 = ubyte;
alias stbtt_int8 = byte;
alias stbtt_uint16 = ushort;
alias stbtt_int16 = short;
alias stbtt_uint32 = uint;
alias stbtt_int32 = int;

//typedef char stbtt__check_size32[sizeof(stbtt_int32)==4 ? 1 : -1];
//typedef char stbtt__check_size16[sizeof(stbtt_int16)==2 ? 1 : -1];

int STBTT_ifloor(T) (in T x) pure { pragma(inline, true); import std.math : floor; return cast(int)floor(x); }
int STBTT_iceil(T) (in T x) pure { pragma(inline, true); import std.math : ceil; return cast(int)ceil(x); }

T STBTT_sqrt(T) (in T x) pure { pragma(inline, true); import std.math : sqrt; return sqrt(x); }
T STBTT_pow(T) (in T x, in T y) pure { pragma(inline, true); import std.math : pow; return pow(x, y); }

T STBTT_fmod(T) (in T x, in T y) { pragma(inline, true); import std.math : fmod; return fmod(x, y); }

T STBTT_cos(T) (in T x) pure { pragma(inline, true); import std.math : cos; return cos(x); }
T STBTT_acos(T) (in T x) pure { pragma(inline, true); import std.math : acos; return acos(x); }

T STBTT_fabs(T) (in T x) pure { pragma(inline, true); import std.math : abs; return abs(x); }

// #define your own functions "STBTT_malloc" / "STBTT_free" to avoid malloc.h
void* STBTT_malloc (uint size, const(void)* uptr) { pragma(inline, true); import core.stdc.stdlib : malloc; return malloc(size); }
void STBTT_free (void *ptr, const(void)* uptr) { pragma(inline, true); import core.stdc.stdlib : free; free(ptr); }
/*
#ifndef STBTT_malloc
#include <stdlib.h>
#define STBTT_malloc(x,u)  ((void)(u),malloc(x))
#define STBTT_free(x,u)    ((void)(u),free(x))
#endif
*/

//alias STBTT_assert = assert;

uint STBTT_strlen (const(void)* p) { pragma(inline, true); import core.stdc.string : strlen; return (p !is null ? cast(uint)strlen(cast(const(char)*)p) : 0); }
void STBTT_memcpy (void* d, const(void)* s, uint count) { pragma(inline, true); import core.stdc.string : memcpy; if (count > 0) memcpy(d, s, count); }
void STBTT_memset (void* d, uint v, uint count) { pragma(inline, true); import core.stdc.string : memset; if (count > 0) memset(d, v, count); }


// /////////////////////////////////////////////////////////////////////////////
// /////////////////////////////////////////////////////////////////////////////
// //
// //   INTERFACE
// //
// //

// private structure
struct stbtt__buf {
   ubyte *data;
   int cursor;
   int size;
}

//////////////////////////////////////////////////////////////////////////////
//
// TEXTURE BAKING API
//
// If you use this API, you only have to call two functions ever.
//

struct stbtt_bakedchar {
   ushort x0,y0,x1,y1; // coordinates of bbox in bitmap
   float xoff,yoff,xadvance;
}

/+
STBTT_DEF int stbtt_BakeFontBitmap(const(ubyte)* data, int offset,  // font location (use offset=0 for plain .ttf)
                                float pixel_height,                     // height of font in pixels
                                ubyte *pixels, int pw, int ph,  // bitmap to be filled in
                                int first_char, int num_chars,          // characters to bake
                                stbtt_bakedchar *chardata,           // you allocate this, it's num_chars long
				int* ascent, int * descent, int* line_gap); // metrics for use later too
+/
// if return is positive, the first unused row of the bitmap
// if return is negative, returns the negative of the number of characters that fit
// if return is 0, no characters fit and no rows were used
// This uses a very crappy packing.

struct stbtt_aligned_quad {
   float x0,y0,s0,t0; // top-left
   float x1,y1,s1,t1; // bottom-right
}

/+
STBTT_DEF void stbtt_GetBakedQuad(const(stbtt_bakedchar)* chardata, int pw, int ph,  // same data as above
                               int char_index,             // character to display
                               float *xpos, float *ypos,   // pointers to current position in screen pixel space
                               stbtt_aligned_quad *q,      // output: quad to draw
                               int opengl_fillrule);       // true if opengl fill rule; false if DX9 or earlier
+/
// Call GetBakedQuad with char_index = 'character - first_char', and it
// creates the quad you need to draw and advances the current position.
//
// The coordinate system used assumes y increases downwards.
//
// Characters will extend both above and below the current position;
// see discussion of "BASELINE" above.
//
// It's inefficient; you might want to c&p it and optimize it.



// ////////////////////////////////////////////////////////////////////////////
//
// NEW TEXTURE BAKING API
//
// This provides options for packing multiple fonts into one atlas, not
// perfectly but better than nothing.

struct stbtt_packedchar {
   ushort x0,y0,x1,y1; // coordinates of bbox in bitmap
   float xoff,yoff,xadvance;
   float xoff2,yoff2;
}

//typedef struct stbtt_pack_context stbtt_pack_context;
//typedef struct stbtt_fontinfo stbtt_fontinfo;
//#ifndef STB_RECT_PACK_VERSION
//typedef struct stbrp_rect stbrp_rect;
//#endif

//STBTT_DEF int  stbtt_PackBegin(stbtt_pack_context *spc, ubyte *pixels, int width, int height, int stride_in_bytes, int padding, void *alloc_context);
// Initializes a packing context stored in the passed-in stbtt_pack_context.
// Future calls using this context will pack characters into the bitmap passed
// in here: a 1-channel bitmap that is width * height. stride_in_bytes is
// the distance from one row to the next (or 0 to mean they are packed tightly
// together). "padding" is the amount of padding to leave between each
// character (normally you want '1' for bitmaps you'll use as textures with
// bilinear filtering).
//
// Returns 0 on failure, 1 on success.

//STBTT_DEF void stbtt_PackEnd  (stbtt_pack_context *spc);
// Cleans up the packing context and frees all memory.

//#define STBTT_POINT_SIZE(x)   (-(x))

/+
STBTT_DEF int  stbtt_PackFontRange(stbtt_pack_context *spc, const(ubyte)* fontdata, int font_index, float font_size,
                                int first_unicode_char_in_range, int num_chars_in_range, stbtt_packedchar *chardata_for_range);
+/
// Creates character bitmaps from the font_index'th font found in fontdata (use
// font_index=0 if you don't know what that is). It creates num_chars_in_range
// bitmaps for characters with unicode values starting at first_unicode_char_in_range
// and increasing. Data for how to render them is stored in chardata_for_range;
// pass these to stbtt_GetPackedQuad to get back renderable quads.
//
// font_size is the full height of the character from ascender to descender,
// as computed by stbtt_ScaleForPixelHeight. To use a point size as computed
// by stbtt_ScaleForMappingEmToPixels, wrap the point size in STBTT_POINT_SIZE()
// and pass that result as 'font_size':
//       ...,                  20 , ... // font max minus min y is 20 pixels tall
//       ..., STBTT_POINT_SIZE(20), ... // 'M' is 20 pixels tall

struct stbtt_pack_range {
   float font_size;
   int first_unicode_codepoint_in_range;  // if non-zero, then the chars are continuous, and this is the first codepoint
   int *array_of_unicode_codepoints;       // if non-zero, then this is an array of unicode codepoints
   int num_chars;
   stbtt_packedchar *chardata_for_range; // output
   ubyte h_oversample, v_oversample; // don't set these, they're used internally
}

//STBTT_DEF int  stbtt_PackFontRanges(stbtt_pack_context *spc, const(ubyte)* fontdata, int font_index, stbtt_pack_range *ranges, int num_ranges);
// Creates character bitmaps from multiple ranges of characters stored in
// ranges. This will usually create a better-packed bitmap than multiple
// calls to stbtt_PackFontRange. Note that you can call this multiple
// times within a single PackBegin/PackEnd.

//STBTT_DEF void stbtt_PackSetOversampling(stbtt_pack_context *spc, unsigned int h_oversample, unsigned int v_oversample);
// Oversampling a font increases the quality by allowing higher-quality subpixel
// positioning, and is especially valuable at smaller text sizes.
//
// This function sets the amount of oversampling for all following calls to
// stbtt_PackFontRange(s) or stbtt_PackFontRangesGatherRects for a given
// pack context. The default (no oversampling) is achieved by h_oversample=1
// and v_oversample=1. The total number of pixels required is
// h_oversample*v_oversample larger than the default; for example, 2x2
// oversampling requires 4x the storage of 1x1. For best results, render
// oversampled textures with bilinear filtering. Look at the readme in
// stb/tests/oversample for information about oversampled fonts
//
// To use with PackFontRangesGather etc., you must set it before calls
// call to PackFontRangesGatherRects.

/+
STBTT_DEF void stbtt_GetPackedQuad(const(stbtt_packedchar)* chardata, int pw, int ph,  // same data as above
                               int char_index,             // character to display
                               float *xpos, float *ypos,   // pointers to current position in screen pixel space
                               stbtt_aligned_quad *q,      // output: quad to draw
                               int align_to_integer);

STBTT_DEF int  stbtt_PackFontRangesGatherRects(stbtt_pack_context *spc, const(stbtt_fontinfo)* info, stbtt_pack_range *ranges, int num_ranges, stbrp_rect *rects);
STBTT_DEF void stbtt_PackFontRangesPackRects(stbtt_pack_context *spc, stbrp_rect *rects, int num_rects);
STBTT_DEF int  stbtt_PackFontRangesRenderIntoRects(stbtt_pack_context *spc, const(stbtt_fontinfo)* info, stbtt_pack_range *ranges, int num_ranges, stbrp_rect *rects);
+/
// Calling these functions in sequence is roughly equivalent to calling
// stbtt_PackFontRanges(). If you more control over the packing of multiple
// fonts, or if you want to pack custom data into a font texture, take a look
// at the source to of stbtt_PackFontRanges() and create a custom version
// using these functions, e.g. call GatherRects multiple times,
// building up a single array of rects, then call PackRects once,
// then call RenderIntoRects repeatedly. This may result in a
// better packing than calling PackFontRanges multiple times
// (or it may not).

// this is an opaque structure that you shouldn't mess with which holds
// all the context needed from PackBegin to PackEnd.
struct stbtt_pack_context {
   void *user_allocator_context;
   void *pack_info;
   int   width;
   int   height;
   int   stride_in_bytes;
   int   padding;
   uint   h_oversample, v_oversample;
   ubyte *pixels;
   void  *nodes;
}

// ////////////////////////////////////////////////////////////////////////////
//
// FONT LOADING
//
//

//STBTT_DEF int stbtt_GetNumberOfFonts(const(ubyte)* data);
// This function will determine the number of fonts in a font file.  TrueType
// collection (.ttc) files may contain multiple fonts, while TrueType font
// (.ttf) files only contain one font. The number of fonts can be used for
// indexing with the previous function where the index is between zero and one
// less than the total fonts. If an error occurs, -1 is returned.

//STBTT_DEF int stbtt_GetFontOffsetForIndex(const(ubyte)* data, int index);
// Each .ttf/.ttc file may have more than one font. Each font has a sequential
// index number starting from 0. Call this function to get the font offset for
// a given index; it returns -1 if the index is out of range. A regular .ttf
// file will only define one font and it always be at offset 0, so it will
// return '0' for index 0, and -1 for all other indices.

// The following structure is defined publically so you can declare one on
// the stack or as a global or etc, but you should treat it as opaque.
struct stbtt_fontinfo {
   void           * userdata;
   ubyte  * data;              // pointer to .ttf file
   int              fontstart;         // offset of start of font

   int numGlyphs;                     // number of glyphs, needed for range checking

   int loca,head,glyf,hhea,hmtx,kern,gpos; // table locations as offset from start of .ttf
   int index_map;                     // a cmap mapping for our chosen character encoding
   int indexToLocFormat;              // format needed to map from glyph index to glyph

   stbtt__buf cff;                    // cff font data
   stbtt__buf charstrings;            // the charstring index
   stbtt__buf gsubrs;                 // global charstring subroutines index
   stbtt__buf subrs;                  // private charstring subroutines index
   stbtt__buf fontdicts;              // array of font dicts
   stbtt__buf fdselect;               // map from glyph to fontdict
}

//STBTT_DEF int stbtt_InitFont(stbtt_fontinfo *info, const(ubyte)* data, int offset);
// Given an offset into the file that defines a font, this function builds
// the necessary cached info for the rest of the system. You must allocate
// the stbtt_fontinfo yourself, and stbtt_InitFont will fill it out. You don't
// need to do anything special to free it, because the contents are pure
// value data with no additional data structures. Returns 0 on failure.


// ////////////////////////////////////////////////////////////////////////////
//
// CHARACTER TO GLYPH-INDEX CONVERSIOn

//STBTT_DEF int stbtt_FindGlyphIndex(const(stbtt_fontinfo)* info, int unicode_codepoint);
// If you're going to perform multiple operations on the same character
// and you want a speed-up, call this function with the character you're
// going to process, then use glyph-based functions instead of the
// codepoint-based functions.


// ////////////////////////////////////////////////////////////////////////////
//
// CHARACTER PROPERTIES
//

//STBTT_DEF float stbtt_ScaleForPixelHeight(const(stbtt_fontinfo)* info, float pixels);
// computes a scale factor to produce a font whose "height" is 'pixels' tall.
// Height is measured as the distance from the highest ascender to the lowest
// descender; in other words, it's equivalent to calling stbtt_GetFontVMetrics
// and computing:
//       scale = pixels / (ascent - descent)
// so if you prefer to measure height by the ascent only, use a similar calculation.

//STBTT_DEF float stbtt_ScaleForMappingEmToPixels(const(stbtt_fontinfo)* info, float pixels);
// computes a scale factor to produce a font whose EM size is mapped to
// 'pixels' tall. This is probably what traditional APIs compute, but
// I'm not positive.

//STBTT_DEF void stbtt_GetFontVMetrics(const(stbtt_fontinfo)* info, int *ascent, int *descent, int *lineGap);
// ascent is the coordinate above the baseline the font extends; descent
// is the coordinate below the baseline the font extends (i.e. it is typically negative)
// lineGap is the spacing between one row's descent and the next row's ascent...
// so you should advance the vertical position by "*ascent - *descent + *lineGap"
//   these are expressed in unscaled coordinates, so you must multiply by
//   the scale factor for a given size

//STBTT_DEF int  stbtt_GetFontVMetricsOS2(const(stbtt_fontinfo)* info, int *typoAscent, int *typoDescent, int *typoLineGap);
// analogous to GetFontVMetrics, but returns the "typographic" values from the OS/2
// table (specific to MS/Windows TTF files).
//
// Returns 1 on success (table present), 0 on failure.

//STBTT_DEF void stbtt_GetFontBoundingBox(const(stbtt_fontinfo)* info, int *x0, int *y0, int *x1, int *y1);
// the bounding box around all possible characters

//STBTT_DEF void stbtt_GetCodepointHMetrics(const(stbtt_fontinfo)* info, int codepoint, int *advanceWidth, int *leftSideBearing);
// leftSideBearing is the offset from the current horizontal position to the left edge of the character
// advanceWidth is the offset from the current horizontal position to the next horizontal position
//   these are expressed in unscaled coordinates

//STBTT_DEF int  stbtt_GetCodepointKernAdvance(const(stbtt_fontinfo)* info, int ch1, int ch2);
// an additional amount to add to the 'advance' value between ch1 and ch2

//STBTT_DEF int stbtt_GetCodepointBox(const(stbtt_fontinfo)* info, int codepoint, int *x0, int *y0, int *x1, int *y1);
// Gets the bounding box of the visible part of the glyph, in unscaled coordinates

//STBTT_DEF void stbtt_GetGlyphHMetrics(const(stbtt_fontinfo)* info, int glyph_index, int *advanceWidth, int *leftSideBearing);
//STBTT_DEF int  stbtt_GetGlyphKernAdvance(const(stbtt_fontinfo)* info, int glyph1, int glyph2);
//STBTT_DEF int  stbtt_GetGlyphBox(const(stbtt_fontinfo)* info, int glyph_index, int *x0, int *y0, int *x1, int *y1);
// as above, but takes one or more glyph indices for greater efficiency


//////////////////////////////////////////////////////////////////////////////
//
// GLYPH SHAPES (you probably don't need these, but they have to go before
// the bitmaps for C declaration-order reasons)
//

//#ifndef STBTT_vmove // you can predefine these to use different values (but why?)
enum {
  STBTT_vmove=1,
  STBTT_vline,
  STBTT_vcurve,
  STBTT_vcubic
}

//#ifndef stbtt_vertex // you can predefine this to use different values (we share this with other code at RAD)
alias stbtt_vertex_type = short; // can't use stbtt_int16 because that's not visible in the header file
struct stbtt_vertex {
  stbtt_vertex_type x,y,cx,cy,cx1,cy1;
  ubyte type,padding;
}
//#endif

//STBTT_DEF int stbtt_IsGlyphEmpty(const(stbtt_fontinfo)* info, int glyph_index);
// returns non-zero if nothing is drawn for this glyph

//STBTT_DEF int stbtt_GetCodepointShape(const(stbtt_fontinfo)* info, int unicode_codepoint, stbtt_vertex **vertices);
//STBTT_DEF int stbtt_GetGlyphShape(const(stbtt_fontinfo)* info, int glyph_index, stbtt_vertex **vertices);
// returns # of vertices and fills *vertices with the pointer to them
//   these are expressed in "unscaled" coordinates
//
// The shape is a series of countours. Each one starts with
// a STBTT_moveto, then consists of a series of mixed
// STBTT_lineto and STBTT_curveto segments. A lineto
// draws a line from previous endpoint to its x,y; a curveto
// draws a quadratic bezier from previous endpoint to
// its x,y, using cx,cy as the bezier control point.

//STBTT_DEF void stbtt_FreeShape(const(stbtt_fontinfo)* info, stbtt_vertex *vertices);
// frees the data allocated above

// ////////////////////////////////////////////////////////////////////////////
//
// BITMAP RENDERING
//

//STBTT_DEF void stbtt_FreeBitmap(ubyte *bitmap, void *userdata);
// frees the bitmap allocated below

//STBTT_DEF ubyte *stbtt_GetCodepointBitmap(const(stbtt_fontinfo)* info, float scale_x, float scale_y, int codepoint, int *width, int *height, int *xoff, int *yoff);
// allocates a large-enough single-channel 8bpp bitmap and renders the
// specified character/glyph at the specified scale into it, with
// antialiasing. 0 is no coverage (transparent), 255 is fully covered (opaque).
// *width & *height are filled out with the width & height of the bitmap,
// which is stored left-to-right, top-to-bottom.
//
// xoff/yoff are the offset it pixel space from the glyph origin to the top-left of the bitmap

//STBTT_DEF ubyte *stbtt_GetCodepointBitmapSubpixel(const(stbtt_fontinfo)* info, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint, int *width, int *height, int *xoff, int *yoff);
// the same as stbtt_GetCodepoitnBitmap, but you can specify a subpixel
// shift for the character

//STBTT_DEF void stbtt_MakeCodepointBitmap(const(stbtt_fontinfo)* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int codepoint);
// the same as stbtt_GetCodepointBitmap, but you pass in storage for the bitmap
// in the form of 'output', with row spacing of 'out_stride' bytes. the bitmap
// is clipped to out_w/out_h bytes. Call stbtt_GetCodepointBitmapBox to get the
// width and height and positioning info for it first.

//STBTT_DEF void stbtt_MakeCodepointBitmapSubpixel(const(stbtt_fontinfo)* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint);
// same as stbtt_MakeCodepointBitmap, but you can specify a subpixel
// shift for the character

//STBTT_DEF void stbtt_MakeCodepointBitmapSubpixelPrefilter(const(stbtt_fontinfo)* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int oversample_x, int oversample_y, float *sub_x, float *sub_y, int codepoint);
// same as stbtt_MakeCodepointBitmapSubpixel, but prefiltering
// is performed (see stbtt_PackSetOversampling)

//STBTT_DEF void stbtt_GetCodepointBitmapBox(const(stbtt_fontinfo)* font, int codepoint, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1);
// get the bbox of the bitmap centered around the glyph origin; so the
// bitmap width is ix1-ix0, height is iy1-iy0, and location to place
// the bitmap top left is (leftSideBearing*scale,iy0).
// (Note that the bitmap uses y-increases-down, but the shape uses
// y-increases-up, so CodepointBitmapBox and CodepointBox are inverted.)

//STBTT_DEF void stbtt_GetCodepointBitmapBoxSubpixel(const(stbtt_fontinfo)* font, int codepoint, float scale_x, float scale_y, float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1);
// same as stbtt_GetCodepointBitmapBox, but you can specify a subpixel
// shift for the character

// the following functions are equivalent to the above functions, but operate
// on glyph indices instead of Unicode codepoints (for efficiency)
//STBTT_DEF ubyte *stbtt_GetGlyphBitmap(const(stbtt_fontinfo)* info, float scale_x, float scale_y, int glyph, int *width, int *height, int *xoff, int *yoff);
//STBTT_DEF ubyte *stbtt_GetGlyphBitmapSubpixel(const(stbtt_fontinfo)* info, float scale_x, float scale_y, float shift_x, float shift_y, int glyph, int *width, int *height, int *xoff, int *yoff);
//STBTT_DEF void stbtt_MakeGlyphBitmap(const(stbtt_fontinfo)* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int glyph);
//STBTT_DEF void stbtt_MakeGlyphBitmapSubpixel(const(stbtt_fontinfo)* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int glyph);
//STBTT_DEF void stbtt_MakeGlyphBitmapSubpixelPrefilter(const(stbtt_fontinfo)* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int oversample_x, int oversample_y, float *sub_x, float *sub_y, int glyph);
//STBTT_DEF void stbtt_GetGlyphBitmapBox(const(stbtt_fontinfo)* font, int glyph, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1);
//STBTT_DEF void stbtt_GetGlyphBitmapBoxSubpixel(const(stbtt_fontinfo)* font, int glyph, float scale_x, float scale_y,float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1);


// @TODO: don't expose this structure
struct stbtt__bitmap {
   int w,h,stride;
   ubyte *pixels;
}

// rasterize a shape with quadratic beziers into a bitmap
/+
STBTT_DEF void stbtt_Rasterize(stbtt__bitmap *result,        // 1-channel bitmap to draw into
                               float flatness_in_pixels,     // allowable error of curve in pixels
                               stbtt_vertex *vertices,       // array of vertices defining shape
                               int num_verts,                // number of vertices in above array
                               float scale_x, float scale_y, // scale applied to input vertices
                               float shift_x, float shift_y, // translation applied to input vertices
                               int x_off, int y_off,         // another translation applied to input
                               int invert,                   // if non-zero, vertically flip shape
                               void *userdata);              // context for to STBTT_MALLOC
+/

// ////////////////////////////////////////////////////////////////////////////
//
// Signed Distance Function (or Field) rendering

//STBTT_DEF void stbtt_FreeSDF(ubyte *bitmap, void *userdata);
// frees the SDF bitmap allocated below

//STBTT_DEF ubyte * stbtt_GetGlyphSDF(const(stbtt_fontinfo)* info, float scale, int glyph, int padding, ubyte onedge_value, float pixel_dist_scale, int *width, int *height, int *xoff, int *yoff);
//STBTT_DEF ubyte * stbtt_GetCodepointSDF(const(stbtt_fontinfo)* info, float scale, int codepoint, int padding, ubyte onedge_value, float pixel_dist_scale, int *width, int *height, int *xoff, int *yoff);
// These functions compute a discretized SDF field for a single character, suitable for storing
// in a single-channel texture, sampling with bilinear filtering, and testing against
// larger than some threshhold to produce scalable fonts.
//        info              --  the font
//        scale             --  controls the size of the resulting SDF bitmap, same as it would be creating a regular bitmap
//        glyph/codepoint   --  the character to generate the SDF for
//        padding           --  extra "pixels" around the character which are filled with the distance to the character (not 0),
//                                 which allows effects like bit outlines
//        onedge_value      --  value 0-255 to test the SDF against to reconstruct the character (i.e. the isocontour of the character)
//        pixel_dist_scale  --  what value the SDF should increase by when moving one SDF "pixel" away from the edge (on the 0..255 scale)
//                                 if positive, > onedge_value is inside; if negative, < onedge_value is inside
//        width,height      --  output height & width of the SDF bitmap (including padding)
//        xoff,yoff         --  output origin of the character
//        return value      --  a 2D array of bytes 0..255, width*height in size
//
// pixel_dist_scale & onedge_value are a scale & bias that allows you to make
// optimal use of the limited 0..255 for your application, trading off precision
// and special effects. SDF values outside the range 0..255 are clamped to 0..255.
//
// Example:
//      scale = stbtt_ScaleForPixelHeight(22)
//      padding = 5
//      onedge_value = 180
//      pixel_dist_scale = 180/5.0 = 36.0
//
//      This will create an SDF bitmap in which the character is about 22 pixels
//      high but the whole bitmap is about 22+5+5=32 pixels high. To produce a filled
//      shape, sample the SDF at each pixel and fill the pixel if the SDF value
//      is greater than or equal to 180/255. (You'll actually want to antialias,
//      which is beyond the scope of this example.) Additionally, you can compute
//      offset outlines (e.g. to stroke the character border inside & outside,
//      or only outside). For example, to fill outside the character up to 3 SDF
//      pixels, you would compare against (180-36.0*3)/255 = 72/255. The above
//      choice of variables maps a range from 5 pixels outside the shape to
//      2 pixels inside the shape to 0..255; this is intended primarily for apply
//      outside effects only (the interior range is needed to allow proper
//      antialiasing of the font at *smaller* sizes)
//
// The function computes the SDF analytically at each SDF pixel, not by e.g.
// building a higher-res bitmap and approximating it. In theory the quality
// should be as high as possible for an SDF of this size & representation, but
// unclear if this is true in practice (perhaps building a higher-res bitmap
// and computing from that can allow drop-out prevention).
//
// The algorithm has not been optimized at all, so expect it to be slow
// if computing lots of characters or very large sizes.



//////////////////////////////////////////////////////////////////////////////
//
// Finding the right font...
//
// You should really just solve this offline, keep your own tables
// of what font is what, and don't try to get it out of the .ttf file.
// That's because getting it out of the .ttf file is really hard, because
// the names in the file can appear in many possible encodings, in many
// possible languages, and e.g. if you need a case-insensitive comparison,
// the details of that depend on the encoding & language in a complex way
// (actually underspecified in truetype, but also gigantic).
//
// But you can use the provided functions in two possible ways:
//     stbtt_FindMatchingFont() will use *case-sensitive* comparisons on
//             unicode-encoded names to try to find the font you want;
//             you can run this before calling stbtt_InitFont()
//
//     stbtt_GetFontNameString() lets you get any of the various strings
//             from the file yourself and do your own comparisons on them.
//             You have to have called stbtt_InitFont() first.


//STBTT_DEF int stbtt_FindMatchingFont(const(ubyte)* fontdata, const(char)* name, int flags);
// returns the offset (not index) of the font that matches, or -1 if none
//   if you use STBTT_MACSTYLE_DONTCARE, use a font name like "Arial Bold".
//   if you use any other flag, use a font name like "Arial"; this checks
//     the 'macStyle' header field; i don't know if fonts set this consistently
enum {
  STBTT_MACSTYLE_DONTCARE   = 0,
  STBTT_MACSTYLE_BOLD       = 1,
  STBTT_MACSTYLE_ITALIC     = 2,
  STBTT_MACSTYLE_UNDERSCORE = 4,
  STBTT_MACSTYLE_NONE       = 8,   // <= not same as 0, this makes us check the bitfield is 0
}

//STBTT_DEF int stbtt_CompareUTF8toUTF16_bigendian(const(char)* s1, int len1, const(char)* s2, int len2);
// returns 1/0 whether the first string interpreted as utf8 is identical to
// the second string interpreted as big-endian utf16... useful for strings from next func

//STBTT_DEF const(char)* stbtt_GetFontNameString(const(stbtt_fontinfo)* font, int *length, int platformID, int encodingID, int languageID, int nameID);
// returns the string (which may be big-endian double byte, e.g. for unicode)
// and puts the length in bytes in *length.
//
// some of the values for the IDs are below; for more see the truetype spec:
//     http://developer.apple.com/textfonts/TTRefMan/RM06/Chap6name.html
//     http://www.microsoft.com/typography/otspec/name.htm

enum { // platformID
   STBTT_PLATFORM_ID_UNICODE   =0,
   STBTT_PLATFORM_ID_MAC       =1,
   STBTT_PLATFORM_ID_ISO       =2,
   STBTT_PLATFORM_ID_MICROSOFT =3
}

enum { // encodingID for STBTT_PLATFORM_ID_UNICODE
   STBTT_UNICODE_EID_UNICODE_1_0    =0,
   STBTT_UNICODE_EID_UNICODE_1_1    =1,
   STBTT_UNICODE_EID_ISO_10646      =2,
   STBTT_UNICODE_EID_UNICODE_2_0_BMP=3,
   STBTT_UNICODE_EID_UNICODE_2_0_FULL=4
}

enum { // encodingID for STBTT_PLATFORM_ID_MICROSOFT
   STBTT_MS_EID_SYMBOL        =0,
   STBTT_MS_EID_UNICODE_BMP   =1,
   STBTT_MS_EID_SHIFTJIS      =2,
   STBTT_MS_EID_UNICODE_FULL  =10
}

enum { // encodingID for STBTT_PLATFORM_ID_MAC; same as Script Manager codes
   STBTT_MAC_EID_ROMAN        =0,   STBTT_MAC_EID_ARABIC       =4,
   STBTT_MAC_EID_JAPANESE     =1,   STBTT_MAC_EID_HEBREW       =5,
   STBTT_MAC_EID_CHINESE_TRAD =2,   STBTT_MAC_EID_GREEK        =6,
   STBTT_MAC_EID_KOREAN       =3,   STBTT_MAC_EID_RUSSIAN      =7
}

enum { // languageID for STBTT_PLATFORM_ID_MICROSOFT; same as LCID...
       // problematic because there are e.g. 16 english LCIDs and 16 arabic LCIDs
   STBTT_MS_LANG_ENGLISH     =0x0409,   STBTT_MS_LANG_ITALIAN     =0x0410,
   STBTT_MS_LANG_CHINESE     =0x0804,   STBTT_MS_LANG_JAPANESE    =0x0411,
   STBTT_MS_LANG_DUTCH       =0x0413,   STBTT_MS_LANG_KOREAN      =0x0412,
   STBTT_MS_LANG_FRENCH      =0x040c,   STBTT_MS_LANG_RUSSIAN     =0x0419,
   STBTT_MS_LANG_GERMAN      =0x0407,   STBTT_MS_LANG_SPANISH     =0x0409,
   STBTT_MS_LANG_HEBREW      =0x040d,   STBTT_MS_LANG_SWEDISH     =0x041D
}

enum { // languageID for STBTT_PLATFORM_ID_MAC
   STBTT_MAC_LANG_ENGLISH      =0 ,   STBTT_MAC_LANG_JAPANESE     =11,
   STBTT_MAC_LANG_ARABIC       =12,   STBTT_MAC_LANG_KOREAN       =23,
   STBTT_MAC_LANG_DUTCH        =4 ,   STBTT_MAC_LANG_RUSSIAN      =32,
   STBTT_MAC_LANG_FRENCH       =1 ,   STBTT_MAC_LANG_SPANISH      =6 ,
   STBTT_MAC_LANG_GERMAN       =2 ,   STBTT_MAC_LANG_SWEDISH      =5 ,
   STBTT_MAC_LANG_HEBREW       =10,   STBTT_MAC_LANG_CHINESE_SIMPLIFIED =33,
   STBTT_MAC_LANG_ITALIAN      =3 ,   STBTT_MAC_LANG_CHINESE_TRAD =19
}


// /////////////////////////////////////////////////////////////////////////////
// /////////////////////////////////////////////////////////////////////////////
// //
// //   IMPLEMENTATION
// //
// //
private:

enum STBTT_MAX_OVERSAMPLE = 8; // it also must be POT
static assert(STBTT_MAX_OVERSAMPLE > 0 && STBTT_MAX_OVERSAMPLE <= 255, "STBTT_MAX_OVERSAMPLE cannot be > 255");

//typedef int stbtt__test_oversample_pow2[(STBTT_MAX_OVERSAMPLE & (STBTT_MAX_OVERSAMPLE-1)) == 0 ? 1 : -1];

enum STBTT_RASTERIZER_VERSION = 2;

/*
#ifdef _MSC_VER
#define STBTT__NOTUSED(v)  (void)(v)
#else
#define STBTT__NOTUSED(v)  (void)sizeof(v)
#endif
*/

// ////////////////////////////////////////////////////////////////////////
//
// stbtt__buf helpers to parse data from file
//

private stbtt_uint8 stbtt__buf_get8(stbtt__buf *b)
{
   if (b.cursor >= b.size)
      return 0;
   return b.data[b.cursor++];
}

private stbtt_uint8 stbtt__buf_peek8(stbtt__buf *b)
{
   if (b.cursor >= b.size)
      return 0;
   return b.data[b.cursor];
}

private void stbtt__buf_seek(stbtt__buf *b, int o)
{
   assert(!(o > b.size || o < 0));
   b.cursor = (o > b.size || o < 0) ? b.size : o;
}

private void stbtt__buf_skip(stbtt__buf *b, int o)
{
   stbtt__buf_seek(b, b.cursor + o);
}

private stbtt_uint32 stbtt__buf_get(stbtt__buf *b, int n)
{
   stbtt_uint32 v = 0;
   int i;
   assert(n >= 1 && n <= 4);
   for (i = 0; i < n; i++)
      v = (v << 8) | stbtt__buf_get8(b);
   return v;
}

private stbtt__buf stbtt__new_buf(const(void)* p, size_t size)
{
   stbtt__buf r;
   assert(size < 0x40000000);
   r.data = cast(stbtt_uint8*) p;
   r.size = cast(int) size;
   r.cursor = 0;
   return r;
}

//#define stbtt__buf_get16(b)  stbtt__buf_get((b), 2)
//#define stbtt__buf_get32(b)  stbtt__buf_get((b), 4)
ushort stbtt__buf_get16 (stbtt__buf *b) { pragma(inline, true); return cast(ushort)stbtt__buf_get(b, 2); }
uint stbtt__buf_get32 (stbtt__buf *b) { pragma(inline, true); return cast(uint)stbtt__buf_get(b, 4); }

private stbtt__buf stbtt__buf_range(const(stbtt__buf)* b, int o, int s)
{
   stbtt__buf r = stbtt__new_buf(null, 0);
   if (o < 0 || s < 0 || o > b.size || s > b.size - o) return r;
   r.data = cast(ubyte*)b.data + o;
   r.size = s;
   return r;
}

private stbtt__buf stbtt__cff_get_index(stbtt__buf *b)
{
   int count, start, offsize;
   start = b.cursor;
   count = stbtt__buf_get16(b);
   if (count) {
      offsize = stbtt__buf_get8(b);
      assert(offsize >= 1 && offsize <= 4);
      stbtt__buf_skip(b, offsize * count);
      stbtt__buf_skip(b, stbtt__buf_get(b, offsize) - 1);
   }
   return stbtt__buf_range(b, start, b.cursor - start);
}

private stbtt_uint32 stbtt__cff_int(stbtt__buf *b)
{
   int b0 = stbtt__buf_get8(b);
   if (b0 >= 32 && b0 <= 246)       return b0 - 139;
   else if (b0 >= 247 && b0 <= 250) return (b0 - 247)*256 + stbtt__buf_get8(b) + 108;
   else if (b0 >= 251 && b0 <= 254) return -(b0 - 251)*256 - stbtt__buf_get8(b) - 108;
   else if (b0 == 28)               return stbtt__buf_get16(b);
   else if (b0 == 29)               return stbtt__buf_get32(b);
   assert(0);
}

private void stbtt__cff_skip_operand(stbtt__buf *b) {
   int v, b0 = stbtt__buf_peek8(b);
   assert(b0 >= 28);
   if (b0 == 30) {
      stbtt__buf_skip(b, 1);
      while (b.cursor < b.size) {
         v = stbtt__buf_get8(b);
         if ((v & 0xF) == 0xF || (v >> 4) == 0xF)
            break;
      }
   } else {
      stbtt__cff_int(b);
   }
}

private stbtt__buf stbtt__dict_get(stbtt__buf *b, int key)
{
   stbtt__buf_seek(b, 0);
   while (b.cursor < b.size) {
      int start = b.cursor, end, op;
      while (stbtt__buf_peek8(b) >= 28)
         stbtt__cff_skip_operand(b);
      end = b.cursor;
      op = stbtt__buf_get8(b);
      if (op == 12)  op = stbtt__buf_get8(b) | 0x100;
      if (op == key) return stbtt__buf_range(b, start, end-start);
   }
   return stbtt__buf_range(b, 0, 0);
}

private void stbtt__dict_get_ints(stbtt__buf *b, int key, int outcount, stbtt_uint32 *outstb)
{
   int i;
   stbtt__buf operands = stbtt__dict_get(b, key);
   for (i = 0; i < outcount && operands.cursor < operands.size; i++)
      outstb[i] = stbtt__cff_int(&operands);
}

private int stbtt__cff_index_count(stbtt__buf *b)
{
   stbtt__buf_seek(b, 0);
   return stbtt__buf_get16(b);
}

private stbtt__buf stbtt__cff_index_get(stbtt__buf b, int i)
{
   int count, offsize, start, end;
   stbtt__buf_seek(&b, 0);
   count = stbtt__buf_get16(&b);
   offsize = stbtt__buf_get8(&b);
   assert(i >= 0 && i < count);
   assert(offsize >= 1 && offsize <= 4);
   stbtt__buf_skip(&b, i*offsize);
   start = stbtt__buf_get(&b, offsize);
   end = stbtt__buf_get(&b, offsize);
   return stbtt__buf_range(&b, 2+(count+1)*offsize+start, end - start);
}

//////////////////////////////////////////////////////////////////////////
//
// accessors to parse data from file
//

// on platforms that don't allow misaligned reads, if we want to allow
// truetype fonts that aren't padded to alignment, define ALLOW_UNALIGNED_TRUETYPE

//#define ttBYTE(p)     (* (stbtt_uint8 *) (p))
//#define ttCHAR(p)     (* (stbtt_int8 *) (p))
//#define ttFixed(p)    ttLONG(p)
stbtt_uint8 ttBYTE (const(void)* p) pure { pragma(inline, true); return *cast(const(stbtt_uint8)*)p; }
stbtt_int8 ttCHAR (const(void)* p) pure { pragma(inline, true); return *cast(const(stbtt_int8)*)p; }

private stbtt_uint16 ttUSHORT(const(stbtt_uint8)* p) { return p[0]*256 + p[1]; }
private stbtt_int16 ttSHORT(const(stbtt_uint8)* p)   { return cast(stbtt_int16)(p[0]*256 + p[1]); }
private stbtt_uint32 ttULONG(const(stbtt_uint8)* p)  { return (p[0]<<24) + (p[1]<<16) + (p[2]<<8) + p[3]; }
private stbtt_int32 ttLONG(const(stbtt_uint8)* p)    { return (p[0]<<24) + (p[1]<<16) + (p[2]<<8) + p[3]; }

//#define stbtt_tag4(p,c0,c1,c2,c3) ((p)[0] == (c0) && (p)[1] == (c1) && (p)[2] == (c2) && (p)[3] == (c3))
//#define stbtt_tag(p,str)           stbtt_tag4(p,str[0],str[1],str[2],str[3])

bool stbtt_tag4 (const(void)* p, ubyte c0, ubyte c1, ubyte c2, ubyte c3) pure {
  return
    (cast(const(ubyte)*)p)[0] == c0 &&
    (cast(const(ubyte)*)p)[1] == c1 &&
    (cast(const(ubyte)*)p)[2] == c2 &&
    (cast(const(ubyte)*)p)[3] == c3;
}

bool stbtt_tag (const(void)* p, const(void)* str) {
  //stbtt_tag4(p,str[0],str[1],str[2],str[3])
  import core.stdc.string : memcmp;
  return (memcmp(p, str, 4) == 0);
}

private int stbtt__isfont(stbtt_uint8 *font)
{
   // check the version number
   if (stbtt_tag4(font, '1',0,0,0))  return 1; // TrueType 1
   if (stbtt_tag(font, "typ1".ptr))   return 1; // TrueType with type 1 font -- we don't support this!
   if (stbtt_tag(font, "OTTO".ptr))   return 1; // OpenType with CFF
   if (stbtt_tag4(font, 0,1,0,0)) return 1; // OpenType 1.0
   if (stbtt_tag(font, "true".ptr))   return 1; // Apple specification for TrueType fonts
   return 0;
}

// @OPTIMIZE: binary search
private stbtt_uint32 stbtt__find_table(stbtt_uint8 *data, stbtt_uint32 fontstart, const(char)* tag)
{
   stbtt_int32 num_tables = ttUSHORT(data+fontstart+4);
   stbtt_uint32 tabledir = fontstart + 12;
   stbtt_int32 i;
   for (i=0; i < num_tables; ++i) {
      stbtt_uint32 loc = tabledir + 16*i;
      if (stbtt_tag(data+loc+0, tag))
         return ttULONG(data+loc+8);
   }
   return 0;
}

private int stbtt_GetFontOffsetForIndex_internal(ubyte *font_collection, int index)
{
   // if it's just a font, there's only one valid index
   if (stbtt__isfont(font_collection))
      return index == 0 ? 0 : -1;

   // check if it's a TTC
   if (stbtt_tag(font_collection, "ttcf".ptr)) {
      // version 1?
      if (ttULONG(font_collection+4) == 0x00010000 || ttULONG(font_collection+4) == 0x00020000) {
         stbtt_int32 n = ttLONG(font_collection+8);
         if (index >= n)
            return -1;
         return ttULONG(font_collection+12+index*4);
      }
   }
   return -1;
}

private int stbtt_GetNumberOfFonts_internal(ubyte *font_collection)
{
   // if it's just a font, there's only one valid font
   if (stbtt__isfont(font_collection))
      return 1;

   // check if it's a TTC
   if (stbtt_tag(font_collection, "ttcf".ptr)) {
      // version 1?
      if (ttULONG(font_collection+4) == 0x00010000 || ttULONG(font_collection+4) == 0x00020000) {
         return ttLONG(font_collection+8);
      }
   }
   return 0;
}

private stbtt__buf stbtt__get_subrs(stbtt__buf cff, stbtt__buf fontdict)
{
   stbtt_uint32 subrsoff = 0;
   stbtt_uint32[2] private_loc = 0;
   stbtt__buf pdict;
   stbtt__dict_get_ints(&fontdict, 18, 2, private_loc.ptr);
   if (!private_loc[1] || !private_loc[0]) return stbtt__new_buf(null, 0);
   pdict = stbtt__buf_range(&cff, private_loc[1], private_loc[0]);
   stbtt__dict_get_ints(&pdict, 19, 1, &subrsoff);
   if (!subrsoff) return stbtt__new_buf(null, 0);
   stbtt__buf_seek(&cff, private_loc[1]+subrsoff);
   return stbtt__cff_get_index(&cff);
}

private int stbtt_InitFont_internal(stbtt_fontinfo *info, ubyte *data, int fontstart)
{
   stbtt_uint32 cmap, t;
   stbtt_int32 i,numTables;

   info.data = data;
   info.fontstart = fontstart;
   info.cff = stbtt__new_buf(null, 0);

   cmap = stbtt__find_table(data, fontstart, "cmap");       // required
   info.loca = stbtt__find_table(data, fontstart, "loca"); // required
   info.head = stbtt__find_table(data, fontstart, "head"); // required
   info.glyf = stbtt__find_table(data, fontstart, "glyf"); // required
   info.hhea = stbtt__find_table(data, fontstart, "hhea"); // required
   info.hmtx = stbtt__find_table(data, fontstart, "hmtx"); // required
   info.kern = stbtt__find_table(data, fontstart, "kern"); // not required
   info.gpos = stbtt__find_table(data, fontstart, "GPOS"); // not required

   if (!cmap || !info.head || !info.hhea || !info.hmtx)
      return 0;
   if (info.glyf) {
      // required for truetype
      if (!info.loca) return 0;
   } else {
      // initialization for CFF / Type2 fonts (OTF)
      stbtt__buf b, topdict, topdictidx;
      stbtt_uint32 cstype = 2, charstrings = 0, fdarrayoff = 0, fdselectoff = 0;
      stbtt_uint32 cff;

      cff = stbtt__find_table(data, fontstart, "CFF ");
      if (!cff) return 0;

      info.fontdicts = stbtt__new_buf(null, 0);
      info.fdselect = stbtt__new_buf(null, 0);

      // @TODO this should use size from table (not 512MB)
      info.cff = stbtt__new_buf(data+cff, 512*1024*1024);
      b = info.cff;

      // read the header
      stbtt__buf_skip(&b, 2);
      stbtt__buf_seek(&b, stbtt__buf_get8(&b)); // hdrsize

      // @TODO the name INDEX could list multiple fonts,
      // but we just use the first one.
      stbtt__cff_get_index(&b);  // name INDEX
      topdictidx = stbtt__cff_get_index(&b);
      topdict = stbtt__cff_index_get(topdictidx, 0);
      stbtt__cff_get_index(&b);  // string INDEX
      info.gsubrs = stbtt__cff_get_index(&b);

      stbtt__dict_get_ints(&topdict, 17, 1, &charstrings);
      stbtt__dict_get_ints(&topdict, 0x100 | 6, 1, &cstype);
      stbtt__dict_get_ints(&topdict, 0x100 | 36, 1, &fdarrayoff);
      stbtt__dict_get_ints(&topdict, 0x100 | 37, 1, &fdselectoff);
      info.subrs = stbtt__get_subrs(b, topdict);

      // we only support Type 2 charstrings
      if (cstype != 2) return 0;
      if (charstrings == 0) return 0;

      if (fdarrayoff) {
         // looks like a CID font
         if (!fdselectoff) return 0;
         stbtt__buf_seek(&b, fdarrayoff);
         info.fontdicts = stbtt__cff_get_index(&b);
         info.fdselect = stbtt__buf_range(&b, fdselectoff, b.size-fdselectoff);
      }

      stbtt__buf_seek(&b, charstrings);
      info.charstrings = stbtt__cff_get_index(&b);
   }

   t = stbtt__find_table(data, fontstart, "maxp");
   if (t)
      info.numGlyphs = ttUSHORT(data+t+4);
   else
      info.numGlyphs = 0xffff;

   // find a cmap encoding table we understand *now* to avoid searching
   // later. (todo: could make this installable)
   // the same regardless of glyph.
   numTables = ttUSHORT(data + cmap + 2);
   info.index_map = 0;
   for (i=0; i < numTables; ++i) {
      stbtt_uint32 encoding_record = cmap + 4 + 8 * i;
      // find an encoding we understand:
      switch(ttUSHORT(data+encoding_record)) {
         case STBTT_PLATFORM_ID_MICROSOFT:
            switch (ttUSHORT(data+encoding_record+2)) {
               case STBTT_MS_EID_UNICODE_BMP:
               case STBTT_MS_EID_UNICODE_FULL:
                  // MS/Unicode
                  info.index_map = cmap + ttULONG(data+encoding_record+4);
                  break;
               default:
            }
            break;
        case STBTT_PLATFORM_ID_UNICODE:
            // Mac/iOS has these
            // all the encodingIDs are unicode, so we don't bother to check it
            info.index_map = cmap + ttULONG(data+encoding_record+4);
            break;
        default:
      }
   }
   if (info.index_map == 0)
      return 0;

   info.indexToLocFormat = ttUSHORT(data+info.head + 50);
   return 1;
}

public int stbtt_FindGlyphIndex(const(stbtt_fontinfo)* info, int unicode_codepoint)
{
   stbtt_uint8 *data = cast(stbtt_uint8*)info.data;
   stbtt_uint32 index_map = info.index_map;

   stbtt_uint16 format = ttUSHORT(data + index_map + 0);
   if (format == 0) { // apple byte encoding
      stbtt_int32 bytes = ttUSHORT(data + index_map + 2);
      if (unicode_codepoint < bytes-6)
         return ttBYTE(data + index_map + 6 + unicode_codepoint);
      return 0;
   } else if (format == 6) {
      stbtt_uint32 first = ttUSHORT(data + index_map + 6);
      stbtt_uint32 count = ttUSHORT(data + index_map + 8);
      if (cast(stbtt_uint32) unicode_codepoint >= first && cast(stbtt_uint32) unicode_codepoint < first+count)
         return ttUSHORT(data + index_map + 10 + (unicode_codepoint - first)*2);
      return 0;
   } else if (format == 2) {
      assert(0); // @TODO: high-byte mapping for japanese/chinese/korean
   } else if (format == 4) { // standard mapping for windows fonts: binary search collection of ranges
      stbtt_uint16 segcount = ttUSHORT(data+index_map+6) >> 1;
      stbtt_uint16 searchRange = ttUSHORT(data+index_map+8) >> 1;
      stbtt_uint16 entrySelector = ttUSHORT(data+index_map+10);
      stbtt_uint16 rangeShift = ttUSHORT(data+index_map+12) >> 1;

      // do a binary search of the segments
      stbtt_uint32 endCount = index_map + 14;
      stbtt_uint32 search = endCount;

      if (unicode_codepoint > 0xffff)
         return 0;

      // they lie from endCount .. endCount + segCount
      // but searchRange is the nearest power of two, so...
      if (unicode_codepoint >= ttUSHORT(data + search + rangeShift*2))
         search += rangeShift*2;

      // now decrement to bias correctly to find smallest
      search -= 2;
      while (entrySelector) {
         stbtt_uint16 end;
         searchRange >>= 1;
         end = ttUSHORT(data + search + searchRange*2);
         if (unicode_codepoint > end)
            search += searchRange*2;
         --entrySelector;
      }
      search += 2;

      {
         stbtt_uint16 offset, start;
         stbtt_uint16 item = cast(stbtt_uint16) ((search - endCount) >> 1);

         assert(unicode_codepoint <= ttUSHORT(data + endCount + 2*item));
         start = ttUSHORT(data + index_map + 14 + segcount*2 + 2 + 2*item);
         if (unicode_codepoint < start)
            return 0;

         offset = ttUSHORT(data + index_map + 14 + segcount*6 + 2 + 2*item);
         if (offset == 0)
            return cast(stbtt_uint16) (unicode_codepoint + ttSHORT(data + index_map + 14 + segcount*4 + 2 + 2*item));

         return ttUSHORT(data + offset + (unicode_codepoint-start)*2 + index_map + 14 + segcount*6 + 2 + 2*item);
      }
   } else if (format == 12 || format == 13) {
      stbtt_uint32 ngroups = ttULONG(data+index_map+12);
      stbtt_int32 low,high;
      low = 0; high = cast(stbtt_int32)ngroups;
      // Binary search the right group.
      while (low < high) {
         stbtt_int32 mid = low + ((high-low) >> 1); // rounds down, so low <= mid < high
         stbtt_uint32 start_char = ttULONG(data+index_map+16+mid*12);
         stbtt_uint32 end_char = ttULONG(data+index_map+16+mid*12+4);
         if (cast(stbtt_uint32) unicode_codepoint < start_char)
            high = mid;
         else if (cast(stbtt_uint32) unicode_codepoint > end_char)
            low = mid+1;
         else {
            stbtt_uint32 start_glyph = ttULONG(data+index_map+16+mid*12+8);
            if (format == 12)
               return start_glyph + unicode_codepoint-start_char;
            else // format == 13
               return start_glyph;
         }
      }
      return 0; // not found
   }
   // @TODO
   assert(0);
}

public int stbtt_GetCodepointShape(stbtt_fontinfo* info, int unicode_codepoint, stbtt_vertex **vertices)
{
   return stbtt_GetGlyphShape(info, stbtt_FindGlyphIndex(info, unicode_codepoint), vertices);
}

private void stbtt_setvertex(stbtt_vertex *v, stbtt_uint8 type, stbtt_int32 x, stbtt_int32 y, stbtt_int32 cx, stbtt_int32 cy)
{
   v.type = type;
   v.x = cast(stbtt_int16) x;
   v.y = cast(stbtt_int16) y;
   v.cx = cast(stbtt_int16) cx;
   v.cy = cast(stbtt_int16) cy;
}

private int stbtt__GetGlyfOffset(const(stbtt_fontinfo)* info, int glyph_index)
{
   int g1,g2;

   assert(!info.cff.size);

   if (glyph_index >= info.numGlyphs) return -1; // glyph index out of range
   if (info.indexToLocFormat >= 2)    return -1; // unknown index->glyph map format

   if (info.indexToLocFormat == 0) {
      g1 = info.glyf + ttUSHORT(info.data + info.loca + glyph_index * 2) * 2;
      g2 = info.glyf + ttUSHORT(info.data + info.loca + glyph_index * 2 + 2) * 2;
   } else {
      g1 = info.glyf + ttULONG (info.data + info.loca + glyph_index * 4);
      g2 = info.glyf + ttULONG (info.data + info.loca + glyph_index * 4 + 4);
   }

   return g1==g2 ? -1 : g1; // if length is 0, return -1
}

//private int stbtt__GetGlyphInfoT2(const(stbtt_fontinfo)* info, int glyph_index, int *x0, int *y0, int *x1, int *y1);

public int stbtt_GetGlyphBox(stbtt_fontinfo* info, int glyph_index, int *x0, int *y0, int *x1, int *y1)
{
   if (info.cff.size) {
      stbtt__GetGlyphInfoT2(info, glyph_index, x0, y0, x1, y1);
   } else {
      int g = stbtt__GetGlyfOffset(info, glyph_index);
      if (g < 0) return 0;

      if (x0) *x0 = ttSHORT(info.data + g + 2);
      if (y0) *y0 = ttSHORT(info.data + g + 4);
      if (x1) *x1 = ttSHORT(info.data + g + 6);
      if (y1) *y1 = ttSHORT(info.data + g + 8);
   }
   return 1;
}

public int stbtt_GetCodepointBox(stbtt_fontinfo* info, int codepoint, int *x0, int *y0, int *x1, int *y1)
{
   return stbtt_GetGlyphBox(info, stbtt_FindGlyphIndex(info,codepoint), x0,y0,x1,y1);
}

public int stbtt_IsGlyphEmpty(stbtt_fontinfo* info, int glyph_index)
{
   stbtt_int16 numberOfContours;
   int g;
   if (info.cff.size)
      return stbtt__GetGlyphInfoT2(info, glyph_index, null, null, null, null) == 0;
   g = stbtt__GetGlyfOffset(info, glyph_index);
   if (g < 0) return 1;
   numberOfContours = ttSHORT(info.data + g);
   return numberOfContours == 0;
}

private int stbtt__close_shape(stbtt_vertex *vertices, int num_vertices, int was_off, int start_off,
    stbtt_int32 sx, stbtt_int32 sy, stbtt_int32 scx, stbtt_int32 scy, stbtt_int32 cx, stbtt_int32 cy)
{
   if (start_off) {
      if (was_off)
         stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, (cx+scx)>>1, (cy+scy)>>1, cx,cy);
      stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, sx,sy,scx,scy);
   } else {
      if (was_off)
         stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve,sx,sy,cx,cy);
      else
         stbtt_setvertex(&vertices[num_vertices++], STBTT_vline,sx,sy,0,0);
   }
   return num_vertices;
}

private int stbtt__GetGlyphShapeTT(stbtt_fontinfo* info, int glyph_index, stbtt_vertex **pvertices)
{
   stbtt_int16 numberOfContours;
   stbtt_uint8 *endPtsOfContours;
   stbtt_uint8 *data = cast(stbtt_uint8*)info.data;
   stbtt_vertex *vertices = null;
   int num_vertices=0;
   int g = stbtt__GetGlyfOffset(info, glyph_index);

   *pvertices = null;

   if (g < 0) return 0;

   numberOfContours = ttSHORT(data + g);

   if (numberOfContours > 0) {
      stbtt_uint8 flags=0,flagcount;
      stbtt_int32 ins, i,j=0,m,n, next_move, was_off=0, off, start_off=0;
      stbtt_int32 x,y,cx,cy,sx,sy, scx,scy;
      stbtt_uint8 *points;
      endPtsOfContours = (data + g + 10);
      ins = ttUSHORT(data + g + 10 + numberOfContours * 2);
      points = data + g + 10 + numberOfContours * 2 + 2 + ins;

      n = 1+ttUSHORT(endPtsOfContours + numberOfContours*2-2);

      m = n + 2*numberOfContours;  // a loose bound on how many vertices we might need
      vertices = cast(stbtt_vertex *) STBTT_malloc(m * cast(uint)vertices[0].sizeof, info.userdata);
      if (vertices is null)
         return 0;

      next_move = 0;
      flagcount=0;

      // in first pass, we load uninterpreted data into the allocated array
      // above, shifted to the end of the array so we won't overwrite it when
      // we create our final data starting from the front

      off = m - n; // starting offset for uninterpreted data, regardless of how m ends up being calculated

      // first load flags

      for (i=0; i < n; ++i) {
         if (flagcount == 0) {
            flags = *points++;
            if (flags & 8)
               flagcount = *points++;
         } else
            --flagcount;
         vertices[off+i].type = flags;
      }

      // now load x coordinates
      x=0;
      for (i=0; i < n; ++i) {
         flags = vertices[off+i].type;
         if (flags & 2) {
            stbtt_int16 dx = *points++;
            x += (flags & 16) ? cast(int)dx : -cast(int)dx; // ???
         } else {
            if (!(flags & 16)) {
               x = x + cast(stbtt_int16) (points[0]*256 + points[1]);
               points += 2;
            }
         }
         vertices[off+i].x = cast(stbtt_int16) x;
      }

      // now load y coordinates
      y=0;
      for (i=0; i < n; ++i) {
         flags = vertices[off+i].type;
         if (flags & 4) {
            stbtt_int16 dy = *points++;
            y += (flags & 32) ? cast(int)dy : -cast(int)dy; // ???
         } else {
            if (!(flags & 32)) {
               y = y + cast(stbtt_int16) (points[0]*256 + points[1]);
               points += 2;
            }
         }
         vertices[off+i].y = cast(stbtt_int16) y;
      }

      // now convert them to our format
      num_vertices=0;
      sx = sy = cx = cy = scx = scy = 0;
      for (i=0; i < n; ++i) {
         flags = vertices[off+i].type;
         x     = cast(stbtt_int16) vertices[off+i].x;
         y     = cast(stbtt_int16) vertices[off+i].y;

         if (next_move == i) {
            if (i != 0)
               num_vertices = stbtt__close_shape(vertices, num_vertices, was_off, start_off, sx,sy,scx,scy,cx,cy);

            // now start the new one
            start_off = !(flags & 1);
            if (start_off) {
               // if we start off with an off-curve point, then when we need to find a point on the curve
               // where we can start, and we need to save some state for when we wraparound.
               scx = x;
               scy = y;
               if (!(vertices[off+i+1].type & 1)) {
                  // next point is also a curve point, so interpolate an on-point curve
                  sx = (x + cast(stbtt_int32) vertices[off+i+1].x) >> 1;
                  sy = (y + cast(stbtt_int32) vertices[off+i+1].y) >> 1;
               } else {
                  // otherwise just use the next point as our start point
                  sx = cast(stbtt_int32) vertices[off+i+1].x;
                  sy = cast(stbtt_int32) vertices[off+i+1].y;
                  ++i; // we're using point i+1 as the starting point, so skip it
               }
            } else {
               sx = x;
               sy = y;
            }
            stbtt_setvertex(&vertices[num_vertices++], STBTT_vmove,sx,sy,0,0);
            was_off = 0;
            next_move = 1 + ttUSHORT(endPtsOfContours+j*2);
            ++j;
         } else {
            if (!(flags & 1)) { // if it's a curve
               if (was_off) // two off-curve control points in a row means interpolate an on-curve midpoint
                  stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, (cx+x)>>1, (cy+y)>>1, cx, cy);
               cx = x;
               cy = y;
               was_off = 1;
            } else {
               if (was_off)
                  stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, x,y, cx, cy);
               else
                  stbtt_setvertex(&vertices[num_vertices++], STBTT_vline, x,y,0,0);
               was_off = 0;
            }
         }
      }
      num_vertices = stbtt__close_shape(vertices, num_vertices, was_off, start_off, sx,sy,scx,scy,cx,cy);
   } else if (numberOfContours == -1) {
      // Compound shapes.
      int more = 1;
      stbtt_uint8 *comp = data + g + 10;
      num_vertices = 0;
      vertices = null;
      while (more) {
         stbtt_uint16 flags, gidx;
         int comp_num_verts = 0, i;
         stbtt_vertex *comp_verts = null, tmp = null;
         float[6] mtx = [1,0,0,1,0,0];
         float m, n;

         flags = ttSHORT(comp); comp+=2;
         gidx = ttSHORT(comp); comp+=2;

         if (flags & 2) { // XY values
            if (flags & 1) { // shorts
               mtx[4] = ttSHORT(comp); comp+=2;
               mtx[5] = ttSHORT(comp); comp+=2;
            } else {
               mtx[4] = ttCHAR(comp); comp+=1;
               mtx[5] = ttCHAR(comp); comp+=1;
            }
         }
         else {
            // @TODO handle matching point
            assert(0);
         }
         if (flags & (1<<3)) { // WE_HAVE_A_SCALE
            mtx[0] = mtx[3] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[1] = mtx[2] = 0;
         } else if (flags & (1<<6)) { // WE_HAVE_AN_X_AND_YSCALE
            mtx[0] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[1] = mtx[2] = 0;
            mtx[3] = ttSHORT(comp)/16384.0f; comp+=2;
         } else if (flags & (1<<7)) { // WE_HAVE_A_TWO_BY_TWO
            mtx[0] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[1] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[2] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[3] = ttSHORT(comp)/16384.0f; comp+=2;
         }

         // Find transformation scales.
         m = cast(float) STBTT_sqrt(mtx[0]*mtx[0] + mtx[1]*mtx[1]);
         n = cast(float) STBTT_sqrt(mtx[2]*mtx[2] + mtx[3]*mtx[3]);

         // Get indexed glyph.
         comp_num_verts = stbtt_GetGlyphShape(info, gidx, &comp_verts);
         if (comp_num_verts > 0) {
            // Transform vertices.
            for (i = 0; i < comp_num_verts; ++i) {
               stbtt_vertex* v = &comp_verts[i];
               stbtt_vertex_type x,y;
               x=v.x; y=v.y;
               v.x = cast(stbtt_vertex_type)(m * (mtx[0]*x + mtx[2]*y + mtx[4]));
               v.y = cast(stbtt_vertex_type)(n * (mtx[1]*x + mtx[3]*y + mtx[5]));
               x=v.cx; y=v.cy;
               v.cx = cast(stbtt_vertex_type)(m * (mtx[0]*x + mtx[2]*y + mtx[4]));
               v.cy = cast(stbtt_vertex_type)(n * (mtx[1]*x + mtx[3]*y + mtx[5]));
            }
            // Append vertices.
            tmp = cast(stbtt_vertex*)STBTT_malloc((num_vertices+comp_num_verts)*cast(uint)stbtt_vertex.sizeof, info.userdata);
            if (!tmp) {
               if (vertices) STBTT_free(vertices, info.userdata);
               if (comp_verts) STBTT_free(comp_verts, info.userdata);
               return 0;
            }
            if (num_vertices > 0) STBTT_memcpy(tmp, vertices, num_vertices*cast(uint)stbtt_vertex.sizeof);
            STBTT_memcpy(tmp+num_vertices, comp_verts, comp_num_verts*cast(uint)stbtt_vertex.sizeof);
            if (vertices) STBTT_free(vertices, info.userdata);
            vertices = tmp;
            STBTT_free(comp_verts, info.userdata);
            num_vertices += comp_num_verts;
         }
         // More components ?
         more = flags & (1<<5);
      }
   } else if (numberOfContours < 0) {
      // @TODO other compound variations?
      assert(0);
   } else {
      // numberOfCounters == 0, do nothing
   }

   *pvertices = vertices;
   return num_vertices;
}

struct stbtt__csctx {
   int bounds;
   int started;
   float first_x, first_y;
   float x, y;
   stbtt_int32 min_x, max_x, min_y, max_y;

   stbtt_vertex *pvertices;
   int num_vertices;
}

//#define STBTT__CSCTX_INIT(bounds) {bounds,0, 0,0, 0,0, 0,0,0,0, null, 0}

private void stbtt__track_vertex(stbtt__csctx *c, stbtt_int32 x, stbtt_int32 y)
{
   if (x > c.max_x || !c.started) c.max_x = x;
   if (y > c.max_y || !c.started) c.max_y = y;
   if (x < c.min_x || !c.started) c.min_x = x;
   if (y < c.min_y || !c.started) c.min_y = y;
   c.started = 1;
}

private void stbtt__csctx_v(stbtt__csctx *c, stbtt_uint8 type, stbtt_int32 x, stbtt_int32 y, stbtt_int32 cx, stbtt_int32 cy, stbtt_int32 cx1, stbtt_int32 cy1)
{
   if (c.bounds) {
      stbtt__track_vertex(c, x, y);
      if (type == STBTT_vcubic) {
         stbtt__track_vertex(c, cx, cy);
         stbtt__track_vertex(c, cx1, cy1);
      }
   } else {
      stbtt_setvertex(&c.pvertices[c.num_vertices], type, x, y, cx, cy);
      c.pvertices[c.num_vertices].cx1 = cast(stbtt_int16) cx1;
      c.pvertices[c.num_vertices].cy1 = cast(stbtt_int16) cy1;
   }
   c.num_vertices++;
}

private void stbtt__csctx_close_shape(stbtt__csctx *ctx)
{
   if (ctx.first_x != ctx.x || ctx.first_y != ctx.y)
      stbtt__csctx_v(ctx, STBTT_vline, cast(int)ctx.first_x, cast(int)ctx.first_y, 0, 0, 0, 0);
}

private void stbtt__csctx_rmove_to(stbtt__csctx *ctx, float dx, float dy)
{
   stbtt__csctx_close_shape(ctx);
   ctx.first_x = ctx.x = ctx.x + dx;
   ctx.first_y = ctx.y = ctx.y + dy;
   stbtt__csctx_v(ctx, STBTT_vmove, cast(int)ctx.x, cast(int)ctx.y, 0, 0, 0, 0);
}

private void stbtt__csctx_rline_to(stbtt__csctx *ctx, float dx, float dy)
{
   ctx.x += dx;
   ctx.y += dy;
   stbtt__csctx_v(ctx, STBTT_vline, cast(int)ctx.x, cast(int)ctx.y, 0, 0, 0, 0);
}

private void stbtt__csctx_rccurve_to(stbtt__csctx *ctx, float dx1, float dy1, float dx2, float dy2, float dx3, float dy3)
{
   float cx1 = ctx.x + dx1;
   float cy1 = ctx.y + dy1;
   float cx2 = cx1 + dx2;
   float cy2 = cy1 + dy2;
   ctx.x = cx2 + dx3;
   ctx.y = cy2 + dy3;
   stbtt__csctx_v(ctx, STBTT_vcubic, cast(int)ctx.x, cast(int)ctx.y, cast(int)cx1, cast(int)cy1, cast(int)cx2, cast(int)cy2);
}

private stbtt__buf stbtt__get_subr(stbtt__buf idx, int n)
{
   int count = stbtt__cff_index_count(&idx);
   int bias = 107;
   if (count >= 33900)
      bias = 32768;
   else if (count >= 1240)
      bias = 1131;
   n += bias;
   if (n < 0 || n >= count)
      return stbtt__new_buf(null, 0);
   return stbtt__cff_index_get(idx, n);
}

private stbtt__buf stbtt__cid_get_glyph_subrs(stbtt_fontinfo* info, int glyph_index)
{
   stbtt__buf fdselect = info.fdselect;
   int nranges, start, end, v, fmt, fdselector = -1, i;

   stbtt__buf_seek(&fdselect, 0);
   fmt = stbtt__buf_get8(&fdselect);
   if (fmt == 0) {
      // untested
      stbtt__buf_skip(&fdselect, glyph_index);
      fdselector = stbtt__buf_get8(&fdselect);
   } else if (fmt == 3) {
      nranges = stbtt__buf_get16(&fdselect);
      start = stbtt__buf_get16(&fdselect);
      for (i = 0; i < nranges; i++) {
         v = stbtt__buf_get8(&fdselect);
         end = stbtt__buf_get16(&fdselect);
         if (glyph_index >= start && glyph_index < end) {
            fdselector = v;
            break;
         }
         start = end;
      }
   }
   if (fdselector == -1) stbtt__new_buf(null, 0);
   return stbtt__get_subrs(info.cff, stbtt__cff_index_get(info.fontdicts, fdselector));
}

private int stbtt__run_charstring(stbtt_fontinfo* info, int glyph_index, stbtt__csctx *c)
{
   int in_header = 1, maskbits = 0, subr_stack_height = 0, sp = 0, v, i, b0;
   int has_subrs = 0, clear_stack;
   float[48] s = void;
   stbtt__buf[10] subr_stack = void;
   stbtt__buf subrs = info.subrs, b;
   float f;

   static int STBTT__CSERR(string s) { pragma(inline, true); return 0; }

   // this currently ignores the initial width value, which isn't needed if we have hmtx
   b = stbtt__cff_index_get(info.charstrings, glyph_index);
   while (b.cursor < b.size) {
      i = 0;
      clear_stack = 1;
      b0 = stbtt__buf_get8(&b);
      switch (b0) {
      // @TODO implement hinting
      case 0x13: // hintmask
      case 0x14: // cntrmask
         if (in_header)
            maskbits += (sp / 2); // implicit "vstem"
         in_header = 0;
         stbtt__buf_skip(&b, (maskbits + 7) / 8);
         break;

      case 0x01: // hstem
      case 0x03: // vstem
      case 0x12: // hstemhm
      case 0x17: // vstemhm
         maskbits += (sp / 2);
         break;

      case 0x15: // rmoveto
         in_header = 0;
         if (sp < 2) return STBTT__CSERR("rmoveto stack");
         stbtt__csctx_rmove_to(c, s[sp-2], s[sp-1]);
         break;
      case 0x04: // vmoveto
         in_header = 0;
         if (sp < 1) return STBTT__CSERR("vmoveto stack");
         stbtt__csctx_rmove_to(c, 0, s[sp-1]);
         break;
      case 0x16: // hmoveto
         in_header = 0;
         if (sp < 1) return STBTT__CSERR("hmoveto stack");
         stbtt__csctx_rmove_to(c, s[sp-1], 0);
         break;

      case 0x05: // rlineto
         if (sp < 2) return STBTT__CSERR("rlineto stack");
         for (; i + 1 < sp; i += 2)
            stbtt__csctx_rline_to(c, s[i], s[i+1]);
         break;

      // hlineto/vlineto and vhcurveto/hvcurveto alternate horizontal and vertical
      // starting from a different place.

      case 0x07: // vlineto
         if (sp < 1) return STBTT__CSERR("vlineto stack");
         goto vlineto;
      case 0x06: // hlineto
         if (sp < 1) return STBTT__CSERR("hlineto stack");
         for (;;) {
            if (i >= sp) break;
            stbtt__csctx_rline_to(c, s[i], 0);
            i++;
      vlineto:
            if (i >= sp) break;
            stbtt__csctx_rline_to(c, 0, s[i]);
            i++;
         }
         break;

      case 0x1F: // hvcurveto
         if (sp < 4) return STBTT__CSERR("hvcurveto stack");
         goto hvcurveto;
      case 0x1E: // vhcurveto
         if (sp < 4) return STBTT__CSERR("vhcurveto stack");
         for (;;) {
            if (i + 3 >= sp) break;
            stbtt__csctx_rccurve_to(c, 0, s[i], s[i+1], s[i+2], s[i+3], (sp - i == 5) ? s[i + 4] : 0.0f);
            i += 4;
      hvcurveto:
            if (i + 3 >= sp) break;
            stbtt__csctx_rccurve_to(c, s[i], 0, s[i+1], s[i+2], (sp - i == 5) ? s[i+4] : 0.0f, s[i+3]);
            i += 4;
         }
         break;

      case 0x08: // rrcurveto
         if (sp < 6) return STBTT__CSERR("rcurveline stack");
         for (; i + 5 < sp; i += 6)
            stbtt__csctx_rccurve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5]);
         break;

      case 0x18: // rcurveline
         if (sp < 8) return STBTT__CSERR("rcurveline stack");
         for (; i + 5 < sp - 2; i += 6)
            stbtt__csctx_rccurve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5]);
         if (i + 1 >= sp) return STBTT__CSERR("rcurveline stack");
         stbtt__csctx_rline_to(c, s[i], s[i+1]);
         break;

      case 0x19: // rlinecurve
         if (sp < 8) return STBTT__CSERR("rlinecurve stack");
         for (; i + 1 < sp - 6; i += 2)
            stbtt__csctx_rline_to(c, s[i], s[i+1]);
         if (i + 5 >= sp) return STBTT__CSERR("rlinecurve stack");
         stbtt__csctx_rccurve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5]);
         break;

      case 0x1A: // vvcurveto
      case 0x1B: // hhcurveto
         if (sp < 4) return STBTT__CSERR("(vv|hh)curveto stack");
         f = 0.0;
         if (sp & 1) { f = s[i]; i++; }
         for (; i + 3 < sp; i += 4) {
            if (b0 == 0x1B)
               stbtt__csctx_rccurve_to(c, s[i], f, s[i+1], s[i+2], s[i+3], 0.0);
            else
               stbtt__csctx_rccurve_to(c, f, s[i], s[i+1], s[i+2], 0.0, s[i+3]);
            f = 0.0;
         }
         break;

      case 0x0A: // callsubr
         if (!has_subrs) {
            if (info.fdselect.size)
               subrs = stbtt__cid_get_glyph_subrs(info, glyph_index);
            has_subrs = 1;
         }
         // fallthrough
         goto case;
      case 0x1D: // callgsubr
         if (sp < 1) return STBTT__CSERR("call(g|)subr stack");
         v = cast(int) s[--sp];
         if (subr_stack_height >= 10) return STBTT__CSERR("recursion limit");
         subr_stack[subr_stack_height++] = b;
         b = stbtt__get_subr(b0 == 0x0A ? subrs : info.gsubrs, v);
         if (b.size == 0) return STBTT__CSERR("subr not found");
         b.cursor = 0;
         clear_stack = 0;
         break;

      case 0x0B: // return
         if (subr_stack_height <= 0) return STBTT__CSERR("return outside subr");
         b = subr_stack[--subr_stack_height];
         clear_stack = 0;
         break;

      case 0x0E: // endchar
         stbtt__csctx_close_shape(c);
         return 1;

      case 0x0C: { // two-byte escape
         float dx1, dx2, dx3, dx4, dx5, dx6, dy1, dy2, dy3, dy4, dy5, dy6;
         float dx, dy;
         int b1 = stbtt__buf_get8(&b);
         switch (b1) {
         // @TODO These "flex" implementations ignore the flex-depth and resolution,
         // and always draw beziers.
         case 0x22: // hflex
            if (sp < 7) return STBTT__CSERR("hflex stack");
            dx1 = s[0];
            dx2 = s[1];
            dy2 = s[2];
            dx3 = s[3];
            dx4 = s[4];
            dx5 = s[5];
            dx6 = s[6];
            stbtt__csctx_rccurve_to(c, dx1, 0, dx2, dy2, dx3, 0);
            stbtt__csctx_rccurve_to(c, dx4, 0, dx5, -dy2, dx6, 0);
            break;

         case 0x23: // flex
            if (sp < 13) return STBTT__CSERR("flex stack");
            dx1 = s[0];
            dy1 = s[1];
            dx2 = s[2];
            dy2 = s[3];
            dx3 = s[4];
            dy3 = s[5];
            dx4 = s[6];
            dy4 = s[7];
            dx5 = s[8];
            dy5 = s[9];
            dx6 = s[10];
            dy6 = s[11];
            //fd is s[12]
            stbtt__csctx_rccurve_to(c, dx1, dy1, dx2, dy2, dx3, dy3);
            stbtt__csctx_rccurve_to(c, dx4, dy4, dx5, dy5, dx6, dy6);
            break;

         case 0x24: // hflex1
            if (sp < 9) return STBTT__CSERR("hflex1 stack");
            dx1 = s[0];
            dy1 = s[1];
            dx2 = s[2];
            dy2 = s[3];
            dx3 = s[4];
            dx4 = s[5];
            dx5 = s[6];
            dy5 = s[7];
            dx6 = s[8];
            stbtt__csctx_rccurve_to(c, dx1, dy1, dx2, dy2, dx3, 0);
            stbtt__csctx_rccurve_to(c, dx4, 0, dx5, dy5, dx6, -(dy1+dy2+dy5));
            break;

         case 0x25: // flex1
            if (sp < 11) return STBTT__CSERR("flex1 stack");
            dx1 = s[0];
            dy1 = s[1];
            dx2 = s[2];
            dy2 = s[3];
            dx3 = s[4];
            dy3 = s[5];
            dx4 = s[6];
            dy4 = s[7];
            dx5 = s[8];
            dy5 = s[9];
            dx6 = dy6 = s[10];
            dx = dx1+dx2+dx3+dx4+dx5;
            dy = dy1+dy2+dy3+dy4+dy5;
            if (STBTT_fabs(dx) > STBTT_fabs(dy))
               dy6 = -dy;
            else
               dx6 = -dx;
            stbtt__csctx_rccurve_to(c, dx1, dy1, dx2, dy2, dx3, dy3);
            stbtt__csctx_rccurve_to(c, dx4, dy4, dx5, dy5, dx6, dy6);
            break;

         default:
            return STBTT__CSERR("unimplemented");
         }
      } break;

      default:
         if (b0 != 255 && b0 != 28 && (b0 < 32 || b0 > 254))
            return STBTT__CSERR("reserved operator");

         // push immediate
         if (b0 == 255) {
            f = cast(float)cast(stbtt_int32)stbtt__buf_get32(&b) / 0x10000;
         } else {
            stbtt__buf_skip(&b, -1);
            f = cast(float)cast(stbtt_int16)stbtt__cff_int(&b);
         }
         if (sp >= 48) return STBTT__CSERR("push stack overflow");
         s[sp++] = f;
         clear_stack = 0;
         break;
      }
      if (clear_stack) sp = 0;
   }
   return STBTT__CSERR("no endchar");
}

private int stbtt__GetGlyphShapeT2(stbtt_fontinfo* info, int glyph_index, stbtt_vertex **pvertices)
{
   // runs the charstring twice, once to count and once to output (to avoid realloc)
   stbtt__csctx count_ctx = stbtt__csctx(1,0, 0,0, 0,0, 0,0,0,0, null, 0); //STBTT__CSCTX_INIT(1);
   stbtt__csctx output_ctx = stbtt__csctx(0,0, 0,0, 0,0, 0,0,0,0, null, 0); //STBTT__CSCTX_INIT(0);
   if (stbtt__run_charstring(info, glyph_index, &count_ctx)) {
      *pvertices = cast(stbtt_vertex*)STBTT_malloc(count_ctx.num_vertices*cast(uint)stbtt_vertex.sizeof, info.userdata);
      output_ctx.pvertices = *pvertices;
      if (stbtt__run_charstring(info, glyph_index, &output_ctx)) {
         assert(output_ctx.num_vertices == count_ctx.num_vertices);
         return output_ctx.num_vertices;
      }
   }
   *pvertices = null;
   return 0;
}

public int stbtt__GetGlyphInfoT2(stbtt_fontinfo* info, int glyph_index, int *x0, int *y0, int *x1, int *y1)
{
   stbtt__csctx c = stbtt__csctx(1,0, 0,0, 0,0, 0,0,0,0, null, 0); //STBTT__CSCTX_INIT(1);
   int r = stbtt__run_charstring(info, glyph_index, &c); //k8: sorry
   if (x0)  *x0 = r ? c.min_x : 0;
   if (y0)  *y0 = r ? c.min_y : 0;
   if (x1)  *x1 = r ? c.max_x : 0;
   if (y1)  *y1 = r ? c.max_y : 0;
   return r ? c.num_vertices : 0;
}

public int stbtt_GetGlyphShape(stbtt_fontinfo* info, int glyph_index, stbtt_vertex **pvertices)
{
   if (!info.cff.size)
      return stbtt__GetGlyphShapeTT(info, glyph_index, pvertices);
   else
      return stbtt__GetGlyphShapeT2(info, glyph_index, pvertices);
}

public void stbtt_GetGlyphHMetrics(const(stbtt_fontinfo)* info, int glyph_index, int *advanceWidth, int *leftSideBearing)
{
   stbtt_uint16 numOfLongHorMetrics = ttUSHORT(info.data+info.hhea + 34);
   if (glyph_index < numOfLongHorMetrics) {
      if (advanceWidth)     *advanceWidth    = ttSHORT(info.data + info.hmtx + 4*glyph_index);
      if (leftSideBearing)  *leftSideBearing = ttSHORT(info.data + info.hmtx + 4*glyph_index + 2);
   } else {
      if (advanceWidth)     *advanceWidth    = ttSHORT(info.data + info.hmtx + 4*(numOfLongHorMetrics-1));
      if (leftSideBearing)  *leftSideBearing = ttSHORT(info.data + info.hmtx + 4*numOfLongHorMetrics + 2*(glyph_index - numOfLongHorMetrics));
   }
}

private int  stbtt__GetGlyphKernInfoAdvance(stbtt_fontinfo* info, int glyph1, int glyph2)
{
   stbtt_uint8 *data = info.data + info.kern;
   stbtt_uint32 needle, straw;
   int l, r, m;

   // we only look at the first table. it must be 'horizontal' and format 0.
   if (!info.kern)
      return 0;
   if (ttUSHORT(data+2) < 1) // number of tables, need at least 1
      return 0;
   if (ttUSHORT(data+8) != 1) // horizontal flag must be set in format
      return 0;

   l = 0;
   r = ttUSHORT(data+10) - 1;
   needle = glyph1 << 16 | glyph2;
   while (l <= r) {
      m = (l + r) >> 1;
      straw = ttULONG(data+18+(m*6)); // note: unaligned read
      if (needle < straw)
         r = m - 1;
      else if (needle > straw)
         l = m + 1;
      else
         return ttSHORT(data+22+(m*6));
   }
   return 0;
}

private stbtt_int32  stbtt__GetCoverageIndex(stbtt_uint8 *coverageTable, int glyph)
{
    stbtt_uint16 coverageFormat = ttUSHORT(coverageTable);
    switch(coverageFormat) {
        case 1: {
            stbtt_uint16 glyphCount = ttUSHORT(coverageTable + 2);

            // Binary search.
            stbtt_int32 l=0, r=glyphCount-1, m;
            int straw, needle=glyph;
            while (l <= r) {
                stbtt_uint8 *glyphArray = coverageTable + 4;
                stbtt_uint16 glyphID;
                m = (l + r) >> 1;
                glyphID = ttUSHORT(glyphArray + 2 * m);
                straw = glyphID;
                if (needle < straw)
                    r = m - 1;
                else if (needle > straw)
                    l = m + 1;
                else {
                     return m;
                }
            }
        } break;

        case 2: {
            stbtt_uint16 rangeCount = ttUSHORT(coverageTable + 2);
            stbtt_uint8 *rangeArray = coverageTable + 4;

            // Binary search.
            stbtt_int32 l=0, r=rangeCount-1, m;
            int strawStart, strawEnd, needle=glyph;
            while (l <= r) {
                stbtt_uint8 *rangeRecord;
                m = (l + r) >> 1;
                rangeRecord = rangeArray + 6 * m;
                strawStart = ttUSHORT(rangeRecord);
                strawEnd = ttUSHORT(rangeRecord + 2);
                if (needle < strawStart)
                    r = m - 1;
                else if (needle > strawEnd)
                    l = m + 1;
                else {
                    stbtt_uint16 startCoverageIndex = ttUSHORT(rangeRecord + 4);
                    return startCoverageIndex + glyph - strawStart;
                }
            }
        } break;

        default: {
            // There are no other cases.
            assert(0);
        }
    }

    return -1;
}

private stbtt_int32  stbtt__GetGlyphClass(stbtt_uint8 *classDefTable, int glyph)
{
    stbtt_uint16 classDefFormat = ttUSHORT(classDefTable);
    switch(classDefFormat)
    {
        case 1: {
            stbtt_uint16 startGlyphID = ttUSHORT(classDefTable + 2);
            stbtt_uint16 glyphCount = ttUSHORT(classDefTable + 4);
            stbtt_uint8 *classDef1ValueArray = classDefTable + 6;

            if (glyph >= startGlyphID && glyph < startGlyphID + glyphCount)
                return cast(stbtt_int32)ttUSHORT(classDef1ValueArray + 2 * (glyph - startGlyphID));

            classDefTable = classDef1ValueArray + 2 * glyphCount;
        } break;

        case 2: {
            stbtt_uint16 classRangeCount = ttUSHORT(classDefTable + 2);
            stbtt_uint8 *classRangeRecords = classDefTable + 4;

            // Binary search.
            stbtt_int32 l=0, r=classRangeCount-1, m;
            int strawStart, strawEnd, needle=glyph;
            while (l <= r) {
                stbtt_uint8 *classRangeRecord;
                m = (l + r) >> 1;
                classRangeRecord = classRangeRecords + 6 * m;
                strawStart = ttUSHORT(classRangeRecord);
                strawEnd = ttUSHORT(classRangeRecord + 2);
                if (needle < strawStart)
                    r = m - 1;
                else if (needle > strawEnd)
                    l = m + 1;
                else
                    return cast(stbtt_int32)ttUSHORT(classRangeRecord + 4);
            }

            classDefTable = classRangeRecords + 6 * classRangeCount;
        } break;

        default: {
            // There are no other cases.
            assert(0);
        }
    }

    return -1;
}

// Define to STBTT_assert(x) if you want to break on unimplemented formats.
//#define STBTT_GPOS_TODO_assert(x)

private stbtt_int32  stbtt__GetGlyphGPOSInfoAdvance(stbtt_fontinfo* info, int glyph1, int glyph2)
{
    stbtt_uint16 lookupListOffset;
    stbtt_uint8 *lookupList;
    stbtt_uint16 lookupCount;
    stbtt_uint8 *data;
    stbtt_int32 i;

    if (!info.gpos) return 0;

    data = info.data + info.gpos;

    if (ttUSHORT(data+0) != 1) return 0; // Major version 1
    if (ttUSHORT(data+2) != 0) return 0; // Minor version 0

    lookupListOffset = ttUSHORT(data+8);
    lookupList = data + lookupListOffset;
    lookupCount = ttUSHORT(lookupList);

    for (i=0; i<lookupCount; ++i) {
        stbtt_uint16 lookupOffset = ttUSHORT(lookupList + 2 + 2 * i);
        stbtt_uint8 *lookupTable = lookupList + lookupOffset;

        stbtt_uint16 lookupType = ttUSHORT(lookupTable);
        stbtt_uint16 subTableCount = ttUSHORT(lookupTable + 4);
        stbtt_uint8 *subTableOffsets = lookupTable + 6;
        switch(lookupType) {
            case 2: { // Pair Adjustment Positioning Subtable
                stbtt_int32 sti;
                for (sti=0; sti<subTableCount; sti++) {
                    stbtt_uint16 subtableOffset = ttUSHORT(subTableOffsets + 2 * sti);
                    stbtt_uint8 *table = lookupTable + subtableOffset;
                    stbtt_uint16 posFormat = ttUSHORT(table);
                    stbtt_uint16 coverageOffset = ttUSHORT(table + 2);
                    stbtt_int32 coverageIndex = stbtt__GetCoverageIndex(table + coverageOffset, glyph1);
                    if (coverageIndex == -1) continue;

                    switch (posFormat) {
                        case 1: {
                            stbtt_int32 l, r, m;
                            int straw, needle;
                            stbtt_uint16 valueFormat1 = ttUSHORT(table + 4);
                            stbtt_uint16 valueFormat2 = ttUSHORT(table + 6);
                            stbtt_int32 valueRecordPairSizeInBytes = 2;
                            stbtt_uint16 pairSetCount = ttUSHORT(table + 8);
                            stbtt_uint16 pairPosOffset = ttUSHORT(table + 10 + 2 * coverageIndex);
                            stbtt_uint8 *pairValueTable = table + pairPosOffset;
                            stbtt_uint16 pairValueCount = ttUSHORT(pairValueTable);
                            stbtt_uint8 *pairValueArray = pairValueTable + 2;
                            // TODO: Support more formats.
                            //!STBTT_GPOS_TODO_assert(valueFormat1 == 4);
                            if (valueFormat1 != 4) return 0;
                            //!STBTT_GPOS_TODO_assert(valueFormat2 == 0);
                            if (valueFormat2 != 0) return 0;

                            assert(coverageIndex < pairSetCount);

                            needle=glyph2;
                            r=pairValueCount-1;
                            l=0;

                            // Binary search.
                            while (l <= r) {
                                stbtt_uint16 secondGlyph;
                                stbtt_uint8 *pairValue;
                                m = (l + r) >> 1;
                                pairValue = pairValueArray + (2 + valueRecordPairSizeInBytes) * m;
                                secondGlyph = ttUSHORT(pairValue);
                                straw = secondGlyph;
                                if (needle < straw)
                                    r = m - 1;
                                else if (needle > straw)
                                    l = m + 1;
                                else {
                                    stbtt_int16 xAdvance = ttSHORT(pairValue + 2);
                                    return xAdvance;
                                }
                            }
                        } break;

                        case 2: {
                            stbtt_uint16 valueFormat1 = ttUSHORT(table + 4);
                            stbtt_uint16 valueFormat2 = ttUSHORT(table + 6);

                            stbtt_uint16 classDef1Offset = ttUSHORT(table + 8);
                            stbtt_uint16 classDef2Offset = ttUSHORT(table + 10);
                            int glyph1class = stbtt__GetGlyphClass(table + classDef1Offset, glyph1);
                            int glyph2class = stbtt__GetGlyphClass(table + classDef2Offset, glyph2);

                            stbtt_uint16 class1Count = ttUSHORT(table + 12);
                            stbtt_uint16 class2Count = ttUSHORT(table + 14);
                            assert(glyph1class < class1Count);
                            assert(glyph2class < class2Count);

                            // TODO: Support more formats.
                            //!STBTT_GPOS_TODO_assert(valueFormat1 == 4);
                            if (valueFormat1 != 4) return 0;
                            //!STBTT_GPOS_TODO_assert(valueFormat2 == 0);
                            if (valueFormat2 != 0) return 0;

                            if (glyph1class >= 0 && glyph1class < class1Count && glyph2class >= 0 && glyph2class < class2Count) {
                                stbtt_uint8 *class1Records = table + 16;
                                stbtt_uint8 *class2Records = class1Records + 2 * (glyph1class * class2Count);
                                stbtt_int16 xAdvance = ttSHORT(class2Records + 2 * glyph2class);
                                return xAdvance;
                            }
                        } break;

                        default: {
                            // There are no other cases.
                            assert(0);
                        }
                    }
                }
                break;
            }

            default:
                // TODO: Implement other stuff.
                break;
        }
    }

    return 0;
}

public int  stbtt_GetGlyphKernAdvance(stbtt_fontinfo* info, int g1, int g2)
{
   int xAdvance = 0;

   if (info.gpos)
      xAdvance += stbtt__GetGlyphGPOSInfoAdvance(info, g1, g2);

   if (info.kern)
      xAdvance += stbtt__GetGlyphKernInfoAdvance(info, g1, g2);

   return xAdvance;
}

public int  stbtt_GetCodepointKernAdvance(stbtt_fontinfo* info, int ch1, int ch2)
{
   if (!info.kern && !info.gpos) // if no kerning table, don't waste time looking up both codepoint->glyphs
      return 0;
   return stbtt_GetGlyphKernAdvance(info, stbtt_FindGlyphIndex(info,ch1), stbtt_FindGlyphIndex(info,ch2));
}

public void stbtt_GetCodepointHMetrics(const(stbtt_fontinfo)* info, int codepoint, int *advanceWidth, int *leftSideBearing)
{
   stbtt_GetGlyphHMetrics(info, stbtt_FindGlyphIndex(info,codepoint), advanceWidth, leftSideBearing);
}

public void stbtt_GetFontVMetrics(const(stbtt_fontinfo)* info, int *ascent, int *descent, int *lineGap)
{
   if (ascent ) *ascent  = ttSHORT(info.data+info.hhea + 4);
   if (descent) *descent = ttSHORT(info.data+info.hhea + 6);
   if (lineGap) *lineGap = ttSHORT(info.data+info.hhea + 8);
}

public int  stbtt_GetFontVMetricsOS2(stbtt_fontinfo* info, int *typoAscent, int *typoDescent, int *typoLineGap)
{
   int tab = stbtt__find_table(info.data, info.fontstart, "OS/2");
   if (!tab)
      return 0;
   if (typoAscent ) *typoAscent  = ttSHORT(info.data+tab + 68);
   if (typoDescent) *typoDescent = ttSHORT(info.data+tab + 70);
   if (typoLineGap) *typoLineGap = ttSHORT(info.data+tab + 72);
   return 1;
}

public int  stbtt_GetFontXHeight(stbtt_fontinfo* info, int *xHeight)
{
   int tab = stbtt__find_table(info.data, info.fontstart, "OS/2");
   if (!tab)
      return 0;
   if (xHeight) {
      auto height = ttSHORT(info.data+tab + 86);
      if (height == 0) height = ttSHORT(info.data+tab + 2);
      *xHeight = height;
   }
   return 1;
}

public void stbtt_GetFontBoundingBox(const(stbtt_fontinfo)* info, int *x0, int *y0, int *x1, int *y1)
{
   *x0 = ttSHORT(info.data + info.head + 36);
   *y0 = ttSHORT(info.data + info.head + 38);
   *x1 = ttSHORT(info.data + info.head + 40);
   *y1 = ttSHORT(info.data + info.head + 42);
}

public float stbtt_ScaleForPixelHeight(const(stbtt_fontinfo)* info, float height)
{
   int fheight = ttSHORT(info.data + info.hhea + 4) - ttSHORT(info.data + info.hhea + 6);
   return cast(float) height / fheight;
}

public float stbtt_ScaleForMappingEmToPixels(const(stbtt_fontinfo)* info, float pixels)
{
   int unitsPerEm = ttUSHORT(info.data + info.head + 18);
   return pixels / unitsPerEm;
}

public void stbtt_FreeShape(const(stbtt_fontinfo)* info, stbtt_vertex *v)
{
   STBTT_free(v, info.userdata);
}

//////////////////////////////////////////////////////////////////////////////
//
// antialiasing software rasterizer
//

public void stbtt_GetGlyphBitmapBoxSubpixel(stbtt_fontinfo* font, int glyph, float scale_x, float scale_y,float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   int x0=0,y0=0,x1,y1; // =0 suppresses compiler warning
   if (!stbtt_GetGlyphBox(font, glyph, &x0,&y0,&x1,&y1)) {
      // e.g. space character
      if (ix0) *ix0 = 0;
      if (iy0) *iy0 = 0;
      if (ix1) *ix1 = 0;
      if (iy1) *iy1 = 0;
   } else {
      // move to integral bboxes (treating pixels as little squares, what pixels get touched)?
      if (ix0) *ix0 = STBTT_ifloor( x0 * scale_x + shift_x);
      if (iy0) *iy0 = STBTT_ifloor(-y1 * scale_y + shift_y);
      if (ix1) *ix1 = STBTT_iceil ( x1 * scale_x + shift_x);
      if (iy1) *iy1 = STBTT_iceil (-y0 * scale_y + shift_y);
   }
}

public void stbtt_GetGlyphBitmapBox(stbtt_fontinfo* font, int glyph, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   stbtt_GetGlyphBitmapBoxSubpixel(font, glyph, scale_x, scale_y,0.0f,0.0f, ix0, iy0, ix1, iy1);
}

public void stbtt_GetCodepointBitmapBoxSubpixel(stbtt_fontinfo* font, int codepoint, float scale_x, float scale_y, float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   stbtt_GetGlyphBitmapBoxSubpixel(font, stbtt_FindGlyphIndex(font,codepoint), scale_x, scale_y,shift_x,shift_y, ix0,iy0,ix1,iy1);
}

public void stbtt_GetCodepointBitmapBox(stbtt_fontinfo* font, int codepoint, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   stbtt_GetCodepointBitmapBoxSubpixel(font, codepoint, scale_x, scale_y,0.0f,0.0f, ix0,iy0,ix1,iy1);
}

//////////////////////////////////////////////////////////////////////////////
//
//  Rasterizer

struct stbtt__hheap_chunk {
   stbtt__hheap_chunk *next;
}

struct stbtt__hheap {
   stbtt__hheap_chunk *head;
   void   *first_free;
   int    num_remaining_in_head_chunk;
}

private void *stbtt__hheap_alloc(stbtt__hheap *hh, size_t size, void *userdata)
{
   if (hh.first_free) {
      void *p = hh.first_free;
      hh.first_free = * cast(void **) p;
      return p;
   } else {
      if (hh.num_remaining_in_head_chunk == 0) {
         int count = (size < 32 ? 2000 : size < 128 ? 800 : 100);
         stbtt__hheap_chunk *c = cast(stbtt__hheap_chunk *) STBTT_malloc(cast(uint)(stbtt__hheap_chunk.sizeof + size * count), userdata);
         if (c == null)
            return null;
         c.next = hh.head;
         hh.head = c;
         hh.num_remaining_in_head_chunk = count;
      }
      --hh.num_remaining_in_head_chunk;
      return cast(char *) (hh.head) + cast(uint)stbtt__hheap_chunk.sizeof + size * hh.num_remaining_in_head_chunk;
   }
}

private void stbtt__hheap_free(stbtt__hheap *hh, void *p)
{
   *cast(void **) p = hh.first_free;
   hh.first_free = p;
}

private void stbtt__hheap_cleanup(stbtt__hheap *hh, void *userdata)
{
   stbtt__hheap_chunk *c = hh.head;
   while (c) {
      stbtt__hheap_chunk *n = c.next;
      STBTT_free(c, userdata);
      c = n;
   }
}

struct stbtt__edge {
   float x0,y0, x1,y1;
   int invert;
}


struct stbtt__active_edge {
   stbtt__active_edge *next;
   static if (STBTT_RASTERIZER_VERSION == 1) {
     int x,dx;
     float ey;
     int direction;
   } else static if (STBTT_RASTERIZER_VERSION == 2) {
     float fx,fdx,fdy;
     float direction;
     float sy;
     float ey;
   } else {
     static assert(0, "Unrecognized value of STBTT_RASTERIZER_VERSION");
   }
}

static if (STBTT_RASTERIZER_VERSION == 1) {
enum STBTT_FIXSHIFT   = 10;
enum STBTT_FIX        = (1 << STBTT_FIXSHIFT);
enum STBTT_FIXMASK    = (STBTT_FIX-1);

private stbtt__active_edge *stbtt__new_active(stbtt__hheap *hh, stbtt__edge *e, int off_x, float start_point, void *userdata)
{
   stbtt__active_edge *z = void;
   z = cast(stbtt__active_edge *) stbtt__hheap_alloc(hh, cast(uint)(*z).sizeof, userdata);
   float dxdy = (e.x1 - e.x0) / (e.y1 - e.y0);
   assert(z != null);
   if (!z) return z;

   // round dx down to avoid overshooting
   if (dxdy < 0)
      z.dx = -STBTT_ifloor(STBTT_FIX * -dxdy);
   else
      z.dx = STBTT_ifloor(STBTT_FIX * dxdy);

   z.x = STBTT_ifloor(STBTT_FIX * e.x0 + z.dx * (start_point - e.y0)); // use z->dx so when we offset later it's by the same amount
   z.x -= off_x * STBTT_FIX;

   z.ey = e.y1;
   z.next = 0;
   z.direction = e.invert ? 1 : -1;
   return z;
}
} else static if (STBTT_RASTERIZER_VERSION == 2) {
private stbtt__active_edge *stbtt__new_active(stbtt__hheap *hh, stbtt__edge *e, int off_x, float start_point, void *userdata)
{
   stbtt__active_edge *z = void;
   z = cast(stbtt__active_edge *) stbtt__hheap_alloc(hh, cast(uint)(*z).sizeof, userdata);
   float dxdy = (e.x1 - e.x0) / (e.y1 - e.y0);
   assert(z != null);
   //STBTT_assert(e->y0 <= start_point);
   if (!z) return z;
   z.fdx = dxdy;
   z.fdy = dxdy != 0.0f ? (1.0f/dxdy) : 0.0f;
   z.fx = e.x0 + dxdy * (start_point - e.y0);
   z.fx -= off_x;
   z.direction = e.invert ? 1.0f : -1.0f;
   z.sy = e.y0;
   z.ey = e.y1;
   z.next = null;
   return z;
}
} else {
  static assert(0, "Unrecognized value of STBTT_RASTERIZER_VERSION");
}

static if (STBTT_RASTERIZER_VERSION == 1) {
// note: this routine clips fills that extend off the edges... ideally this
// wouldn't happen, but it could happen if the truetype glyph bounding boxes
// are wrong, or if the user supplies a too-small bitmap
private void stbtt__fill_active_edges(ubyte *scanline, int len, stbtt__active_edge *e, int max_weight)
{
   // non-zero winding fill
   int x0=0, w=0;

   while (e) {
      if (w == 0) {
         // if we're currently at zero, we need to record the edge start point
         x0 = e.x; w += e.direction;
      } else {
         int x1 = e.x; w += e.direction;
         // if we went to zero, we need to draw
         if (w == 0) {
            int i = x0 >> STBTT_FIXSHIFT;
            int j = x1 >> STBTT_FIXSHIFT;

            if (i < len && j >= 0) {
               if (i == j) {
                  // x0,x1 are the same pixel, so compute combined coverage
                  scanline[i] = scanline[i] + cast(stbtt_uint8) ((x1 - x0) * max_weight >> STBTT_FIXSHIFT);
               } else {
                  if (i >= 0) // add antialiasing for x0
                     scanline[i] = scanline[i] + cast(stbtt_uint8) (((STBTT_FIX - (x0 & STBTT_FIXMASK)) * max_weight) >> STBTT_FIXSHIFT);
                  else
                     i = -1; // clip

                  if (j < len) // add antialiasing for x1
                     scanline[j] = scanline[j] + cast(stbtt_uint8) (((x1 & STBTT_FIXMASK) * max_weight) >> STBTT_FIXSHIFT);
                  else
                     j = len; // clip

                  for (++i; i < j; ++i) // fill pixels between x0 and x1
                     scanline[i] = scanline[i] + cast(stbtt_uint8) max_weight;
               }
            }
         }
      }

      e = e.next;
   }
}

private void stbtt__rasterize_sorted_edges(stbtt__bitmap *result, stbtt__edge *e, int n, int vsubsample, int off_x, int off_y, void *userdata)
{
   stbtt__hheap hh = { 0, 0, 0 };
   stbtt__active_edge *active = null;
   int y,j=0;
   int max_weight = (255 / vsubsample);  // weight per vertical scanline
   int s; // vertical subsample index
   ubyte[512] scanline_data = void;
   ubyte *scanline;

   if (result.w > 512)
      scanline = cast(ubyte *) STBTT_malloc(result.w, userdata);
   else
      scanline = scanline_data;

   y = off_y * vsubsample;
   e[n].y0 = (off_y + result.h) * cast(float) vsubsample + 1;

   while (j < result.h) {
      STBTT_memset(scanline, 0, result.w);
      for (s=0; s < vsubsample; ++s) {
         // find center of pixel for this scanline
         float scan_y = y + 0.5f;
         stbtt__active_edge **step = &active;

         // update all active edges;
         // remove all active edges that terminate before the center of this scanline
         while (*step) {
            stbtt__active_edge * z = *step;
            if (z.ey <= scan_y) {
               *step = z.next; // delete from list
               assert(z.direction);
               z.direction = 0;
               stbtt__hheap_free(&hh, z);
            } else {
               z.x += z.dx; // advance to position for current scanline
               step = &((*step).next); // advance through list
            }
         }

         // resort the list if needed
         for(;;) {
            int changed=0;
            step = &active;
            while (*step && (*step).next) {
               if ((*step).x > (*step).next.x) {
                  stbtt__active_edge *t = *step;
                  stbtt__active_edge *q = t.next;

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
         while (e.y0 <= scan_y) {
            if (e.y1 > scan_y) {
               stbtt__active_edge *z = stbtt__new_active(&hh, e, off_x, scan_y, userdata);
               if (z != null) {
                  // find insertion point
                  if (active == null)
                     active = z;
                  else if (z.x < active.x) {
                     // insert at front
                     z.next = active;
                     active = z;
                  } else {
                     // find thing to insert AFTER
                     stbtt__active_edge *p = active;
                     while (p.next && p.next.x < z.x)
                        p = p.next;
                     // at this point, p->next->x is NOT < z->x
                     z.next = p.next;
                     p.next = z;
                  }
               }
            }
            ++e;
         }

         // now process all active edges in XOR fashion
         if (active)
            stbtt__fill_active_edges(scanline, result.w, active, max_weight);

         ++y;
      }
      STBTT_memcpy(result.pixels + j * result.stride, scanline, result.w);
      ++j;
   }

   stbtt__hheap_cleanup(&hh, userdata);

   if (scanline != scanline_data)
      STBTT_free(scanline, userdata);
}

} else static if (STBTT_RASTERIZER_VERSION == 2) {

// the edge passed in here does not cross the vertical line at x or the vertical line at x+1
// (i.e. it has already been clipped to those)
private void stbtt__handle_clipped_edge(float *scanline, int x, stbtt__active_edge *e, float x0, float y0, float x1, float y1)
{
   if (y0 == y1) return;
   assert(y0 < y1);
   assert(e.sy <= e.ey);
   if (y0 > e.ey) return;
   if (y1 < e.sy) return;
   if (y0 < e.sy) {
      x0 += (x1-x0) * (e.sy - y0) / (y1-y0);
      y0 = e.sy;
   }
   if (y1 > e.ey) {
      x1 += (x1-x0) * (e.ey - y1) / (y1-y0);
      y1 = e.ey;
   }

   if (x0 == x)
      assert(x1 <= x+1);
   else if (x0 == x+1)
      assert(x1 >= x);
   else if (x0 <= x)
      assert(x1 <= x);
   else if (x0 >= x+1)
      assert(x1 >= x+1);
   else
      assert(x1 >= x && x1 <= x+1);

   if (x0 <= x && x1 <= x)
      scanline[x] += e.direction * (y1-y0);
   else if (x0 >= x+1 && x1 >= x+1)
      {}
   else {
      assert(x0 >= x && x0 <= x+1 && x1 >= x && x1 <= x+1);
      scanline[x] += e.direction * (y1-y0) * (1-((x0-x)+(x1-x))/2); // coverage = 1 - average x position
   }
}

private void stbtt__fill_active_edges_new(float *scanline, float *scanline_fill, int len, stbtt__active_edge *e, float y_top)
{
   float y_bottom = y_top+1;

   while (e) {
      // brute force every pixel

      // compute intersection points with top & bottom
      assert(e.ey >= y_top);

      if (e.fdx == 0) {
         float x0 = e.fx;
         if (x0 < len) {
            if (x0 >= 0) {
               stbtt__handle_clipped_edge(scanline,cast(int) x0,e, x0,y_top, x0,y_bottom);
               stbtt__handle_clipped_edge(scanline_fill-1,cast(int) x0+1,e, x0,y_top, x0,y_bottom);
            } else {
               stbtt__handle_clipped_edge(scanline_fill-1,0,e, x0,y_top, x0,y_bottom);
            }
         }
      } else {
         float x0 = e.fx;
         float dx = e.fdx;
         float xb = x0 + dx;
         float x_top, x_bottom;
         float sy0,sy1;
         float dy = e.fdy;
         assert(e.sy <= y_bottom && e.ey >= y_top);

         // compute endpoints of line segment clipped to this scanline (if the
         // line segment starts on this scanline. x0 is the intersection of the
         // line with y_top, but that may be off the line segment.
         if (e.sy > y_top) {
            x_top = x0 + dx * (e.sy - y_top);
            sy0 = e.sy;
         } else {
            x_top = x0;
            sy0 = y_top;
         }
         if (e.ey < y_bottom) {
            x_bottom = x0 + dx * (e.ey - y_top);
            sy1 = e.ey;
         } else {
            x_bottom = xb;
            sy1 = y_bottom;
         }

         if (x_top >= 0 && x_bottom >= 0 && x_top < len && x_bottom < len) {
            // from here on, we don't have to range check x values

            if (cast(int) x_top == cast(int) x_bottom) {
               float height;
               // simple case, only spans one pixel
               int x = cast(int) x_top;
               height = sy1 - sy0;
               assert(x >= 0 && x < len);
               scanline[x] += e.direction * (1-((x_top - x) + (x_bottom-x))/2)  * height;
               scanline_fill[x] += e.direction * height; // everything right of this pixel is filled
            } else {
               int x,x1,x2;
               float y_crossing, step, sign, area;
               // covers 2+ pixels
               if (x_top > x_bottom) {
                  // flip scanline vertically; signed area is the same
                  float t;
                  sy0 = y_bottom - (sy0 - y_top);
                  sy1 = y_bottom - (sy1 - y_top);
                  t = sy0, sy0 = sy1, sy1 = t;
                  t = x_bottom, x_bottom = x_top, x_top = t;
                  dx = -dx;
                  dy = -dy;
                  t = x0, x0 = xb, xb = t;
               }

               x1 = cast(int) x_top;
               x2 = cast(int) x_bottom;
               // compute intersection with y axis at x1+1
               y_crossing = (x1+1 - x0) * dy + y_top;

               sign = e.direction;
               // area of the rectangle covered from y0..y_crossing
               area = sign * (y_crossing-sy0);
               // area of the triangle (x_top,y0), (x+1,y0), (x+1,y_crossing)
               scanline[x1] += area * (1-((x_top - x1)+(x1+1-x1))/2);

               step = sign * dy;
               for (x = x1+1; x < x2; ++x) {
                  scanline[x] += area + step/2;
                  area += step;
               }
               y_crossing += dy * (x2 - (x1+1));

               assert(STBTT_fabs(area) <= 1.01f);

               scanline[x2] += area + sign * (1-((x2-x2)+(x_bottom-x2))/2) * (sy1-y_crossing);

               scanline_fill[x2] += sign * (sy1-sy0);
            }
         } else {
            // if edge goes outside of box we're drawing, we require
            // clipping logic. since this does not match the intended use
            // of this library, we use a different, very slow brute
            // force implementation
            int x;
            for (x=0; x < len; ++x) {
               // cases:
               //
               // there can be up to two intersections with the pixel. any intersection
               // with left or right edges can be handled by splitting into two (or three)
               // regions. intersections with top & bottom do not necessitate case-wise logic.
               //
               // the old way of doing this found the intersections with the left & right edges,
               // then used some simple logic to produce up to three segments in sorted order
               // from top-to-bottom. however, this had a problem: if an x edge was epsilon
               // across the x border, then the corresponding y position might not be distinct
               // from the other y segment, and it might ignored as an empty segment. to avoid
               // that, we need to explicitly produce segments based on x positions.

               // rename variables to clearly-defined pairs
               float y0 = y_top;
               float x1 = cast(float) (x);
               float x2 = cast(float) (x+1);
               float x3 = xb;
               float y3 = y_bottom;

               // x = e->x + e->dx * (y-y_top)
               // (y-y_top) = (x - e->x) / e->dx
               // y = (x - e->x) / e->dx + y_top
               float y1 = (x - x0) / dx + y_top;
               float y2 = (x+1 - x0) / dx + y_top;

               if (x0 < x1 && x3 > x2) {         // three segments descending down-right
                  stbtt__handle_clipped_edge(scanline,x,e, x0,y0, x1,y1);
                  stbtt__handle_clipped_edge(scanline,x,e, x1,y1, x2,y2);
                  stbtt__handle_clipped_edge(scanline,x,e, x2,y2, x3,y3);
               } else if (x3 < x1 && x0 > x2) {  // three segments descending down-left
                  stbtt__handle_clipped_edge(scanline,x,e, x0,y0, x2,y2);
                  stbtt__handle_clipped_edge(scanline,x,e, x2,y2, x1,y1);
                  stbtt__handle_clipped_edge(scanline,x,e, x1,y1, x3,y3);
               } else if (x0 < x1 && x3 > x1) {  // two segments across x, down-right
                  stbtt__handle_clipped_edge(scanline,x,e, x0,y0, x1,y1);
                  stbtt__handle_clipped_edge(scanline,x,e, x1,y1, x3,y3);
               } else if (x3 < x1 && x0 > x1) {  // two segments across x, down-left
                  stbtt__handle_clipped_edge(scanline,x,e, x0,y0, x1,y1);
                  stbtt__handle_clipped_edge(scanline,x,e, x1,y1, x3,y3);
               } else if (x0 < x2 && x3 > x2) {  // two segments across x+1, down-right
                  stbtt__handle_clipped_edge(scanline,x,e, x0,y0, x2,y2);
                  stbtt__handle_clipped_edge(scanline,x,e, x2,y2, x3,y3);
               } else if (x3 < x2 && x0 > x2) {  // two segments across x+1, down-left
                  stbtt__handle_clipped_edge(scanline,x,e, x0,y0, x2,y2);
                  stbtt__handle_clipped_edge(scanline,x,e, x2,y2, x3,y3);
               } else {  // one segment
                  stbtt__handle_clipped_edge(scanline,x,e, x0,y0, x3,y3);
               }
            }
         }
      }
      e = e.next;
   }
}

// directly AA rasterize edges w/o supersampling
private void stbtt__rasterize_sorted_edges(stbtt__bitmap *result, stbtt__edge *e, int n, int vsubsample, int off_x, int off_y, void *userdata)
{
   stbtt__hheap hh = stbtt__hheap( null, null, 0 );
   stbtt__active_edge *active = null;
   int y,j=0, i;
   float[129] scanline_data = void;
   float *scanline, scanline2;

   //STBTT__NOTUSED(vsubsample);

   if (result.w > 64)
      scanline = cast(float *) STBTT_malloc((result.w*2+1) * cast(uint)float.sizeof, userdata);
   else
      scanline = scanline_data.ptr;

   scanline2 = scanline + result.w;

   y = off_y;
   e[n].y0 = cast(float) (off_y + result.h) + 1;

   while (j < result.h) {
      // find center of pixel for this scanline
      float scan_y_top    = y + 0.0f;
      float scan_y_bottom = y + 1.0f;
      stbtt__active_edge **step = &active;

      STBTT_memset(scanline , 0, result.w*cast(uint)scanline[0].sizeof);
      STBTT_memset(scanline2, 0, (result.w+1)*cast(uint)scanline[0].sizeof);

      // update all active edges;
      // remove all active edges that terminate before the top of this scanline
      while (*step) {
         stbtt__active_edge * z = *step;
         if (z.ey <= scan_y_top) {
            *step = z.next; // delete from list
            assert(z.direction);
            z.direction = 0;
            stbtt__hheap_free(&hh, z);
         } else {
            step = &((*step).next); // advance through list
         }
      }

      // insert all edges that start before the bottom of this scanline
      while (e.y0 <= scan_y_bottom) {
         if (e.y0 != e.y1) {
            stbtt__active_edge *z = stbtt__new_active(&hh, e, off_x, scan_y_top, userdata);
            if (z != null) {
               assert(z.ey >= scan_y_top);
               // insert at front
               z.next = active;
               active = z;
            }
         }
         ++e;
      }

      // now process all active edges
      if (active)
         stbtt__fill_active_edges_new(scanline, scanline2+1, result.w, active, scan_y_top);

      {
         float sum = 0;
         for (i=0; i < result.w; ++i) {
            float k;
            int m;
            sum += scanline2[i];
            k = scanline[i] + sum;
            k = cast(float) STBTT_fabs(k)*255 + 0.5f;
            m = cast(int) k;
            if (m > 255) m = 255;
            result.pixels[j*result.stride + i] = cast(ubyte) m;
         }
      }
      // advance all the edges
      step = &active;
      while (*step) {
         stbtt__active_edge *z = *step;
         z.fx += z.fdx; // advance to position for current scanline
         step = &((*step).next); // advance through list
      }

      ++y;
      ++j;
   }

   stbtt__hheap_cleanup(&hh, userdata);

   if (scanline !is scanline_data.ptr)
      STBTT_free(scanline, userdata);
}
} else {
  static assert(0, "Unrecognized value of STBTT_RASTERIZER_VERSION");
}

//#define STBTT__COMPARE(a,b)  ((a).y0 < (b).y0)
bool STBTT__COMPARE (stbtt__edge *a, stbtt__edge *b) pure { pragma(inline, true); return (a.y0 < b.y0); }

private void stbtt__sort_edges_ins_sort(stbtt__edge *p, int n)
{
   int i,j;
   for (i=1; i < n; ++i) {
      stbtt__edge t = p[i];
      stbtt__edge *a = &t;
      j = i;
      while (j > 0) {
         stbtt__edge *b = &p[j-1];
         int c = STBTT__COMPARE(a,b);
         if (!c) break;
         p[j] = p[j-1];
         --j;
      }
      if (i != j)
         p[j] = t;
   }
}

private void stbtt__sort_edges_quicksort(stbtt__edge *p, int n)
{
   /* threshhold for transitioning to insertion sort */
   while (n > 12) {
      stbtt__edge t;
      int c01,c12,c,m,i,j;

      /* compute median of three */
      m = n >> 1;
      c01 = STBTT__COMPARE(&p[0],&p[m]);
      c12 = STBTT__COMPARE(&p[m],&p[n-1]);
      /* if 0 >= mid >= end, or 0 < mid < end, then use mid */
      if (c01 != c12) {
         /* otherwise, we'll need to swap something else to middle */
         int z;
         c = STBTT__COMPARE(&p[0],&p[n-1]);
         /* 0>mid && mid<n:  0>n => n; 0<n => 0 */
         /* 0<mid && mid>n:  0>n => 0; 0<n => n */
         z = (c == c12) ? 0 : n-1;
         t = p[z];
         p[z] = p[m];
         p[m] = t;
      }
      /* now p[m] is the median-of-three */
      /* swap it to the beginning so it won't move around */
      t = p[0];
      p[0] = p[m];
      p[m] = t;

      /* partition loop */
      i=1;
      j=n-1;
      for(;;) {
         /* handling of equality is crucial here */
         /* for sentinels & efficiency with duplicates */
         for (;;++i) {
            if (!STBTT__COMPARE(&p[i], &p[0])) break;
         }
         for (;;--j) {
            if (!STBTT__COMPARE(&p[0], &p[j])) break;
         }
         /* make sure we haven't crossed */
         if (i >= j) break;
         t = p[i];
         p[i] = p[j];
         p[j] = t;

         ++i;
         --j;
      }
      /* recurse on smaller side, iterate on larger */
      if (j < (n-i)) {
         stbtt__sort_edges_quicksort(p,j);
         p = p+i;
         n = n-i;
      } else {
         stbtt__sort_edges_quicksort(p+i, n-i);
         n = j;
      }
   }
}

private void stbtt__sort_edges(stbtt__edge *p, int n)
{
   stbtt__sort_edges_quicksort(p, n);
   stbtt__sort_edges_ins_sort(p, n);
}

struct stbtt__point {
   float x,y;
}

private void stbtt__rasterize(stbtt__bitmap *result, stbtt__point *pts, int *wcount, int windings, float scale_x, float scale_y, float shift_x, float shift_y, int off_x, int off_y, int invert, void *userdata)
{
   float y_scale_inv = invert ? -scale_y : scale_y;
   stbtt__edge *e;
   int n,i,j,k,m;
static if (STBTT_RASTERIZER_VERSION == 1) {
   int vsubsample = result.h < 8 ? 15 : 5;
} else static if (STBTT_RASTERIZER_VERSION == 2) {
   int vsubsample = 1;
} else {
  static assert(0, "Unrecognized value of STBTT_RASTERIZER_VERSION");
}
   // vsubsample should divide 255 evenly; otherwise we won't reach full opacity

   // now we have to blow out the windings into explicit edge lists
   n = 0;
   for (i=0; i < windings; ++i)
      n += wcount[i];

   e = cast(stbtt__edge *) STBTT_malloc(cast(uint)(*e).sizeof * (n+1), userdata); // add an extra one as a sentinel
   if (e is null) return;
   n = 0;

   m=0;
   for (i=0; i < windings; ++i) {
      stbtt__point *p = pts + m;
      m += wcount[i];
      j = wcount[i]-1;
      for (k=0; k < wcount[i]; j=k++) {
         int a=k,b=j;
         // skip the edge if horizontal
         if (p[j].y == p[k].y)
            continue;
         // add edge from j to k to the list
         e[n].invert = 0;
         if (invert ? p[j].y > p[k].y : p[j].y < p[k].y) {
            e[n].invert = 1;
            a=j,b=k;
         }
         e[n].x0 = p[a].x * scale_x + shift_x;
         e[n].y0 = (p[a].y * y_scale_inv + shift_y) * vsubsample;
         e[n].x1 = p[b].x * scale_x + shift_x;
         e[n].y1 = (p[b].y * y_scale_inv + shift_y) * vsubsample;
         ++n;
      }
   }

   // now sort the edges by their highest point (should snap to integer, and then by x)
   //STBTT_sort(e, n, e[0].sizeof, stbtt__edge_compare);
   stbtt__sort_edges(e, n);

   // now, traverse the scanlines and find the intersections on each scanline, use xor winding rule
   stbtt__rasterize_sorted_edges(result, e, n, vsubsample, off_x, off_y, userdata);

   STBTT_free(e, userdata);
}

private void stbtt__add_point(stbtt__point *points, int n, float x, float y)
{
   if (!points) return; // during first pass, it's unallocated
   points[n].x = x;
   points[n].y = y;
}

// tesselate until threshhold p is happy... @TODO warped to compensate for non-linear stretching
private int stbtt__tesselate_curve(stbtt__point *points, int *num_points, float x0, float y0, float x1, float y1, float x2, float y2, float objspace_flatness_squared, int n)
{
   // midpoint
   float mx = (x0 + 2*x1 + x2)/4;
   float my = (y0 + 2*y1 + y2)/4;
   // versus directly drawn line
   float dx = (x0+x2)/2 - mx;
   float dy = (y0+y2)/2 - my;
   if (n > 16) // 65536 segments on one curve better be enough!
      return 1;
   if (dx*dx+dy*dy > objspace_flatness_squared) { // half-pixel error allowed... need to be smaller if AA
      stbtt__tesselate_curve(points, num_points, x0,y0, (x0+x1)/2.0f,(y0+y1)/2.0f, mx,my, objspace_flatness_squared,n+1);
      stbtt__tesselate_curve(points, num_points, mx,my, (x1+x2)/2.0f,(y1+y2)/2.0f, x2,y2, objspace_flatness_squared,n+1);
   } else {
      stbtt__add_point(points, *num_points,x2,y2);
      *num_points = *num_points+1;
   }
   return 1;
}

private void stbtt__tesselate_cubic(stbtt__point *points, int *num_points, float x0, float y0, float x1, float y1, float x2, float y2, float x3, float y3, float objspace_flatness_squared, int n)
{
   // @TODO this "flatness" calculation is just made-up nonsense that seems to work well enough
   float dx0 = x1-x0;
   float dy0 = y1-y0;
   float dx1 = x2-x1;
   float dy1 = y2-y1;
   float dx2 = x3-x2;
   float dy2 = y3-y2;
   float dx = x3-x0;
   float dy = y3-y0;
   float longlen = cast(float) (STBTT_sqrt(dx0*dx0+dy0*dy0)+STBTT_sqrt(dx1*dx1+dy1*dy1)+STBTT_sqrt(dx2*dx2+dy2*dy2));
   float shortlen = cast(float) STBTT_sqrt(dx*dx+dy*dy);
   float flatness_squared = longlen*longlen-shortlen*shortlen;

   if (n > 16) // 65536 segments on one curve better be enough!
      return;

   if (flatness_squared > objspace_flatness_squared) {
      float x01 = (x0+x1)/2;
      float y01 = (y0+y1)/2;
      float x12 = (x1+x2)/2;
      float y12 = (y1+y2)/2;
      float x23 = (x2+x3)/2;
      float y23 = (y2+y3)/2;

      float xa = (x01+x12)/2;
      float ya = (y01+y12)/2;
      float xb = (x12+x23)/2;
      float yb = (y12+y23)/2;

      float mx = (xa+xb)/2;
      float my = (ya+yb)/2;

      stbtt__tesselate_cubic(points, num_points, x0,y0, x01,y01, xa,ya, mx,my, objspace_flatness_squared,n+1);
      stbtt__tesselate_cubic(points, num_points, mx,my, xb,yb, x23,y23, x3,y3, objspace_flatness_squared,n+1);
   } else {
      stbtt__add_point(points, *num_points,x3,y3);
      *num_points = *num_points+1;
   }
}

// returns number of contours
private stbtt__point *stbtt_FlattenCurves(stbtt_vertex *vertices, int num_verts, float objspace_flatness, int **contour_lengths, int *num_contours, void *userdata)
{
   stbtt__point *points = null;
   int num_points=0;

   float objspace_flatness_squared = objspace_flatness * objspace_flatness;
   int i,n=0,start=0, pass;

   // count how many "moves" there are to get the contour count
   for (i=0; i < num_verts; ++i)
      if (vertices[i].type == STBTT_vmove)
         ++n;

   *num_contours = n;
   if (n == 0) return null;

   *contour_lengths = cast(int *) STBTT_malloc(cast(uint)(**contour_lengths).sizeof * n, userdata);

   if (*contour_lengths is null) {
      *num_contours = 0;
      return null;
   }

   // make two passes through the points so we don't need to realloc
   for (pass=0; pass < 2; ++pass) {
      float x=0,y=0;
      if (pass == 1) {
         points = cast(stbtt__point *) STBTT_malloc(num_points * cast(uint)points[0].sizeof, userdata);
         if (points == null) goto error;
      }
      num_points = 0;
      n= -1;
      for (i=0; i < num_verts; ++i) {
         switch (vertices[i].type) {
            case STBTT_vmove:
               // start the next contour
               if (n >= 0)
                  (*contour_lengths)[n] = num_points - start;
               ++n;
               start = num_points;

               x = vertices[i].x, y = vertices[i].y;
               stbtt__add_point(points, num_points++, x,y);
               break;
            case STBTT_vline:
               x = vertices[i].x, y = vertices[i].y;
               stbtt__add_point(points, num_points++, x, y);
               break;
            case STBTT_vcurve:
               stbtt__tesselate_curve(points, &num_points, x,y,
                                        vertices[i].cx, vertices[i].cy,
                                        vertices[i].x,  vertices[i].y,
                                        objspace_flatness_squared, 0);
               x = vertices[i].x, y = vertices[i].y;
               break;
            case STBTT_vcubic:
               stbtt__tesselate_cubic(points, &num_points, x,y,
                                        vertices[i].cx, vertices[i].cy,
                                        vertices[i].cx1, vertices[i].cy1,
                                        vertices[i].x,  vertices[i].y,
                                        objspace_flatness_squared, 0);
               x = vertices[i].x, y = vertices[i].y;
               break;
           default:
         }
      }
      (*contour_lengths)[n] = num_points - start;
   }

   return points;
error:
   STBTT_free(points, userdata);
   STBTT_free(*contour_lengths, userdata);
   *contour_lengths = null;
   *num_contours = 0;
   return null;
}

public void stbtt_Rasterize(stbtt__bitmap *result, float flatness_in_pixels, stbtt_vertex *vertices, int num_verts, float scale_x, float scale_y, float shift_x, float shift_y, int x_off, int y_off, int invert, void *userdata)
{
   float scale            = scale_x > scale_y ? scale_y : scale_x;
   int winding_count      = 0;
   int *winding_lengths   = null;
   stbtt__point *windings = stbtt_FlattenCurves(vertices, num_verts, flatness_in_pixels / scale, &winding_lengths, &winding_count, userdata);
   if (windings) {
      stbtt__rasterize(result, windings, winding_lengths, winding_count, scale_x, scale_y, shift_x, shift_y, x_off, y_off, invert, userdata);
      STBTT_free(winding_lengths, userdata);
      STBTT_free(windings, userdata);
   }
}

public void stbtt_FreeBitmap(ubyte *bitmap, void *userdata)
{
   STBTT_free(bitmap, userdata);
}

public ubyte *stbtt_GetGlyphBitmapSubpixel(stbtt_fontinfo* info, float scale_x, float scale_y, float shift_x, float shift_y, int glyph, int *width, int *height, int *xoff, int *yoff)
{
   int ix0,iy0,ix1,iy1;
   stbtt__bitmap gbm;
   stbtt_vertex *vertices;
   int num_verts = stbtt_GetGlyphShape(info, glyph, &vertices);

   if (scale_x == 0) scale_x = scale_y;
   if (scale_y == 0) {
      if (scale_x == 0) {
         STBTT_free(vertices, info.userdata);
         return null;
      }
      scale_y = scale_x;
   }

   stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale_x, scale_y, shift_x, shift_y, &ix0,&iy0,&ix1,&iy1);

   // now we get the size
   gbm.w = (ix1 - ix0);
   gbm.h = (iy1 - iy0);
   gbm.pixels = null; // in case we error

   if (width ) *width  = gbm.w;
   if (height) *height = gbm.h;
   if (xoff  ) *xoff   = ix0;
   if (yoff  ) *yoff   = iy0;

   if (gbm.w && gbm.h) {
      gbm.pixels = cast(ubyte *) STBTT_malloc(gbm.w * gbm.h, info.userdata);
      if (gbm.pixels) {
         gbm.stride = gbm.w;

         stbtt_Rasterize(&gbm, 0.35f, vertices, num_verts, scale_x, scale_y, shift_x, shift_y, ix0, iy0, 1, info.userdata);
      }
   }
   STBTT_free(vertices, info.userdata);
   return gbm.pixels;
}

public ubyte *stbtt_GetGlyphBitmap(stbtt_fontinfo* info, float scale_x, float scale_y, int glyph, int *width, int *height, int *xoff, int *yoff)
{
   return stbtt_GetGlyphBitmapSubpixel(info, scale_x, scale_y, 0.0f, 0.0f, glyph, width, height, xoff, yoff);
}

public void stbtt_MakeGlyphBitmapSubpixel(stbtt_fontinfo* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int glyph)
{
   int ix0,iy0;
   stbtt_vertex *vertices;
   int num_verts = stbtt_GetGlyphShape(info, glyph, &vertices);
   stbtt__bitmap gbm;

   stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale_x, scale_y, shift_x, shift_y, &ix0,&iy0, null, null);
   gbm.pixels = output;
   gbm.w = out_w;
   gbm.h = out_h;
   gbm.stride = out_stride;

   if (gbm.w && gbm.h)
      stbtt_Rasterize(&gbm, 0.35f, vertices, num_verts, scale_x, scale_y, shift_x, shift_y, ix0,iy0, 1, info.userdata);

   STBTT_free(vertices, info.userdata);
}

public void stbtt_MakeGlyphBitmap(stbtt_fontinfo* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int glyph)
{
   stbtt_MakeGlyphBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, 0.0f,0.0f, glyph);
}

public ubyte *stbtt_GetCodepointBitmapSubpixel(stbtt_fontinfo* info, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint, int *width, int *height, int *xoff, int *yoff)
{
   return stbtt_GetGlyphBitmapSubpixel(info, scale_x, scale_y,shift_x,shift_y, stbtt_FindGlyphIndex(info,codepoint), width,height,xoff,yoff);
}

public void stbtt_MakeCodepointBitmapSubpixelPrefilter(stbtt_fontinfo* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int oversample_x, int oversample_y, float *sub_x, float *sub_y, int codepoint)
{
   stbtt_MakeGlyphBitmapSubpixelPrefilter(info, output, out_w, out_h, out_stride, scale_x, scale_y, shift_x, shift_y, oversample_x, oversample_y, sub_x, sub_y, stbtt_FindGlyphIndex(info,codepoint));
}

public void stbtt_MakeCodepointBitmapSubpixel(stbtt_fontinfo* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint)
{
   stbtt_MakeGlyphBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, shift_x, shift_y, stbtt_FindGlyphIndex(info,codepoint));
}

public ubyte *stbtt_GetCodepointBitmap(stbtt_fontinfo* info, float scale_x, float scale_y, int codepoint, int *width, int *height, int *xoff, int *yoff)
{
   return stbtt_GetCodepointBitmapSubpixel(info, scale_x, scale_y, 0.0f,0.0f, codepoint, width,height,xoff,yoff);
}

public void stbtt_MakeCodepointBitmap(stbtt_fontinfo* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int codepoint)
{
   stbtt_MakeCodepointBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, 0.0f,0.0f, codepoint);
}

//////////////////////////////////////////////////////////////////////////////
//
// bitmap baking
//
// This is SUPER-CRAPPY packing to keep source code small

private int stbtt_BakeFontBitmap_internal(ubyte *data, int offset,  // font location (use offset=0 for plain .ttf)
                                float pixel_height,                     // height of font in pixels
                                ubyte *pixels, int pw, int ph,  // bitmap to be filled in
                                int first_char, int num_chars,          // characters to bake
                                stbtt_bakedchar *chardata,
				int* ascent, int* descent, int* line_gap
				)
{
   float scale;
   int x,y,bottom_y, i;
   stbtt_fontinfo f;
   f.userdata = null;
   if (!stbtt_InitFont(&f, data, offset))
      return -1;
   STBTT_memset(pixels, 0, pw*ph); // background of 0 around pixels
   x=y=1;
   bottom_y = 1;

   scale = stbtt_ScaleForPixelHeight(&f, pixel_height);

   stbtt_GetFontVMetrics(&f, ascent, descent, line_gap);

   if(ascent) *ascent = cast(int) (*ascent * scale);
   if(descent) *descent = cast(int) (*descent * scale);
   if(line_gap) *line_gap = cast(int) (*line_gap * scale);

   for (i=0; i < num_chars; ++i) {
      int advance, lsb, x0,y0,x1,y1,gw,gh;
      int g = stbtt_FindGlyphIndex(&f, first_char + i);
      stbtt_GetGlyphHMetrics(&f, g, &advance, &lsb);
      stbtt_GetGlyphBitmapBox(&f, g, scale,scale, &x0,&y0,&x1,&y1);
      gw = x1-x0;
      gh = y1-y0;
      if (x + gw + 1 >= pw)
         y = bottom_y, x = 1; // advance to next row
      if (y + gh + 1 >= ph) // check if it fits vertically AFTER potentially moving to next row
         return -i;
      assert(x+gw < pw);
      assert(y+gh < ph);
      stbtt_MakeGlyphBitmap(&f, pixels+x+y*pw, gw,gh,pw, scale,scale, g);
      chardata[i].x0 = cast(stbtt_int16) x;
      chardata[i].y0 = cast(stbtt_int16) y;
      chardata[i].x1 = cast(stbtt_int16) (x + gw);
      chardata[i].y1 = cast(stbtt_int16) (y + gh);
      chardata[i].xadvance = scale * advance;
      chardata[i].xoff     = cast(float) x0;
      chardata[i].yoff     = cast(float) y0;
      x = x + gw + 1;
      if (y+gh+1 > bottom_y)
         bottom_y = y+gh+1;
   }
   return bottom_y;
}

public void stbtt_GetBakedQuad(const(stbtt_bakedchar)* chardata, int pw, int ph, int char_index, float *xpos, float *ypos, stbtt_aligned_quad *q, int opengl_fillrule)
{
   float d3d_bias = opengl_fillrule ? 0 : -0.5f;
   float ipw = 1.0f / pw, iph = 1.0f / ph;
   const(stbtt_bakedchar)* b = chardata + char_index;
   int round_x = STBTT_ifloor((*xpos + b.xoff) + 0.5f);
   int round_y = STBTT_ifloor((*ypos + b.yoff) + 0.5f);

   q.x0 = round_x + d3d_bias;
   q.y0 = round_y + d3d_bias;
   q.x1 = round_x + b.x1 - b.x0 + d3d_bias;
   q.y1 = round_y + b.y1 - b.y0 + d3d_bias;

   q.s0 = b.x0 * ipw;
   q.t0 = b.y0 * iph;
   q.s1 = b.x1 * ipw;
   q.t1 = b.y1 * iph;

   *xpos += b.xadvance;
}

//////////////////////////////////////////////////////////////////////////////
//
// rectangle packing replacement routines if you don't have stb_rect_pack.h
//

version(STB_RECT_PACK_VERSION) {

alias stbrp_coord = int;

// //////////////////////////////////////////////////////////////////////////////////
//                                                                                //
//                                                                                //
// COMPILER WARNING ?!?!?                                                         //
//                                                                                //
//                                                                                //
// if you get a compile warning due to these symbols being defined more than      //
// once, move #include "stb_rect_pack.h" before #include "stb_truetype.h"         //
//                                                                                //
// //////////////////////////////////////////////////////////////////////////////////

struct stbrp_context {
   int width,height;
   int x,y,bottom_y;
}

struct stbrp_node {
   ubyte x;
}

struct stbrp_rect {
   stbrp_coord x,y;
   int id,w,h,was_packed;
}

private void stbrp_init_target(stbrp_context *con, int pw, int ph, stbrp_node *nodes, int num_nodes)
{
   con.width  = pw;
   con.height = ph;
   con.x = 0;
   con.y = 0;
   con.bottom_y = 0;
   //STBTT__NOTUSED(nodes);
   //STBTT__NOTUSED(num_nodes);
}

private void stbrp_pack_rects(stbrp_context *con, stbrp_rect *rects, int num_rects)
{
   int i;
   for (i=0; i < num_rects; ++i) {
      if (con.x + rects[i].w > con.width) {
         con.x = 0;
         con.y = con.bottom_y;
      }
      if (con.y + rects[i].h > con.height)
         break;
      rects[i].x = con.x;
      rects[i].y = con.y;
      rects[i].was_packed = 1;
      con.x += rects[i].w;
      if (con.y + rects[i].h > con.bottom_y)
         con.bottom_y = con.y + rects[i].h;
   }
   for (   ; i < num_rects; ++i)
      rects[i].was_packed = 0;
}
}


// ////////////////////////////////////////////////////////////////////////////
//
// bitmap baking
//
// This is SUPER-AWESOME (tm Ryan Gordon) packing using stb_rect_pack.h. If
// stb_rect_pack.h isn't available, it uses the BakeFontBitmap strategy.

public int stbtt_PackBegin(stbtt_pack_context *spc, ubyte *pixels, int pw, int ph, int stride_in_bytes, int padding, void *alloc_context)
{
   stbrp_context *context = void;
   context = cast(stbrp_context *) STBTT_malloc(cast(uint)(*context).sizeof            ,alloc_context);
   int            num_nodes = pw - padding;
   stbrp_node    *nodes   = void;
   nodes = cast(stbrp_node    *) STBTT_malloc(cast(uint)(*nodes  ).sizeof * num_nodes,alloc_context);

   if (context == null || nodes == null) {
      if (context != null) STBTT_free(context, alloc_context);
      if (nodes   != null) STBTT_free(nodes  , alloc_context);
      return 0;
   }

   spc.user_allocator_context = alloc_context;
   spc.width = pw;
   spc.height = ph;
   spc.pixels = pixels;
   spc.pack_info = context;
   spc.nodes = nodes;
   spc.padding = padding;
   spc.stride_in_bytes = stride_in_bytes != 0 ? stride_in_bytes : pw;
   spc.h_oversample = 1;
   spc.v_oversample = 1;

   stbrp_init_target(context, pw-padding, ph-padding, nodes, num_nodes);

   if (pixels)
      STBTT_memset(pixels, 0, pw*ph); // background of 0 around pixels

   return 1;
}

public void stbtt_PackEnd  (stbtt_pack_context *spc)
{
   STBTT_free(spc.nodes    , spc.user_allocator_context);
   STBTT_free(spc.pack_info, spc.user_allocator_context);
}

public void stbtt_PackSetOversampling(stbtt_pack_context *spc, uint h_oversample, uint v_oversample)
{
   assert(h_oversample <= STBTT_MAX_OVERSAMPLE);
   assert(v_oversample <= STBTT_MAX_OVERSAMPLE);
   if (h_oversample <= STBTT_MAX_OVERSAMPLE)
      spc.h_oversample = h_oversample;
   if (v_oversample <= STBTT_MAX_OVERSAMPLE)
      spc.v_oversample = v_oversample;
}

enum STBTT__OVER_MASK = (STBTT_MAX_OVERSAMPLE-1);

private void stbtt__h_prefilter(ubyte *pixels, int w, int h, int stride_in_bytes, uint kernel_width)
{
   ubyte[STBTT_MAX_OVERSAMPLE] buffer = void;
   int safe_w = w - kernel_width;
   int j;
   STBTT_memset(buffer.ptr, 0, STBTT_MAX_OVERSAMPLE); // suppress bogus warning from VS2013 -analyze
   for (j=0; j < h; ++j) {
      int i;
      uint total;
      STBTT_memset(buffer.ptr, 0, kernel_width);

      total = 0;

      // make kernel_width a constant in common cases so compiler can optimize out the divide
      switch (kernel_width) {
         case 2:
            for (i=0; i <= safe_w; ++i) {
               total += pixels[i] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i];
               pixels[i] = cast(ubyte) (total / 2);
            }
            break;
         case 3:
            for (i=0; i <= safe_w; ++i) {
               total += pixels[i] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i];
               pixels[i] = cast(ubyte) (total / 3);
            }
            break;
         case 4:
            for (i=0; i <= safe_w; ++i) {
               total += pixels[i] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i];
               pixels[i] = cast(ubyte) (total / 4);
            }
            break;
         case 5:
            for (i=0; i <= safe_w; ++i) {
               total += pixels[i] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i];
               pixels[i] = cast(ubyte) (total / 5);
            }
            break;
         default:
            for (i=0; i <= safe_w; ++i) {
               total += pixels[i] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i];
               pixels[i] = cast(ubyte) (total / kernel_width);
            }
            break;
      }

      for (; i < w; ++i) {
         assert(pixels[i] == 0);
         total -= buffer[i & STBTT__OVER_MASK];
         pixels[i] = cast(ubyte) (total / kernel_width);
      }

      pixels += stride_in_bytes;
   }
}

private void stbtt__v_prefilter(ubyte *pixels, int w, int h, int stride_in_bytes, uint kernel_width)
{
   ubyte[STBTT_MAX_OVERSAMPLE] buffer = void;
   int safe_h = h - kernel_width;
   int j;
   STBTT_memset(buffer.ptr, 0, STBTT_MAX_OVERSAMPLE); // suppress bogus warning from VS2013 -analyze
   for (j=0; j < w; ++j) {
      int i;
      uint total;
      STBTT_memset(buffer.ptr, 0, kernel_width);

      total = 0;

      // make kernel_width a constant in common cases so compiler can optimize out the divide
      switch (kernel_width) {
         case 2:
            for (i=0; i <= safe_h; ++i) {
               total += pixels[i*stride_in_bytes] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i*stride_in_bytes];
               pixels[i*stride_in_bytes] = cast(ubyte) (total / 2);
            }
            break;
         case 3:
            for (i=0; i <= safe_h; ++i) {
               total += pixels[i*stride_in_bytes] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i*stride_in_bytes];
               pixels[i*stride_in_bytes] = cast(ubyte) (total / 3);
            }
            break;
         case 4:
            for (i=0; i <= safe_h; ++i) {
               total += pixels[i*stride_in_bytes] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i*stride_in_bytes];
               pixels[i*stride_in_bytes] = cast(ubyte) (total / 4);
            }
            break;
         case 5:
            for (i=0; i <= safe_h; ++i) {
               total += pixels[i*stride_in_bytes] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i*stride_in_bytes];
               pixels[i*stride_in_bytes] = cast(ubyte) (total / 5);
            }
            break;
         default:
            for (i=0; i <= safe_h; ++i) {
               total += pixels[i*stride_in_bytes] - buffer[i & STBTT__OVER_MASK];
               buffer[(i+kernel_width) & STBTT__OVER_MASK] = pixels[i*stride_in_bytes];
               pixels[i*stride_in_bytes] = cast(ubyte) (total / kernel_width);
            }
            break;
      }

      for (; i < h; ++i) {
         assert(pixels[i*stride_in_bytes] == 0);
         total -= buffer[i & STBTT__OVER_MASK];
         pixels[i*stride_in_bytes] = cast(ubyte) (total / kernel_width);
      }

      pixels += 1;
   }
}

private float stbtt__oversample_shift(int oversample)
{
   if (!oversample)
      return 0.0f;

   // The prefilter is a box filter of width "oversample",
   // which shifts phase by (oversample - 1)/2 pixels in
   // oversampled space. We want to shift in the opposite
   // direction to counter this.
   return cast(float)-(oversample - 1) / (2.0f * cast(float)oversample);
}

// rects array must be big enough to accommodate all characters in the given ranges
public int stbtt_PackFontRangesGatherRects(stbtt_pack_context *spc, stbtt_fontinfo* info, stbtt_pack_range *ranges, int num_ranges, stbrp_rect *rects)
{
   int i,j,k;

   k=0;
   for (i=0; i < num_ranges; ++i) {
      float fh = ranges[i].font_size;
      float scale = fh > 0 ? stbtt_ScaleForPixelHeight(info, fh) : stbtt_ScaleForMappingEmToPixels(info, -fh);
      ranges[i].h_oversample = cast(ubyte) spc.h_oversample;
      ranges[i].v_oversample = cast(ubyte) spc.v_oversample;
      for (j=0; j < ranges[i].num_chars; ++j) {
         int x0,y0,x1,y1;
         int codepoint = ranges[i].array_of_unicode_codepoints == null ? ranges[i].first_unicode_codepoint_in_range + j : ranges[i].array_of_unicode_codepoints[j];
         int glyph = stbtt_FindGlyphIndex(info, codepoint);
         stbtt_GetGlyphBitmapBoxSubpixel(info,glyph,
                                         scale * spc.h_oversample,
                                         scale * spc.v_oversample,
                                         0,0,
                                         &x0,&y0,&x1,&y1);
         rects[k].w = cast(stbrp_coord) (x1-x0 + spc.padding + spc.h_oversample-1);
         rects[k].h = cast(stbrp_coord) (y1-y0 + spc.padding + spc.v_oversample-1);
         ++k;
      }
   }

   return k;
}

public void stbtt_MakeGlyphBitmapSubpixelPrefilter(stbtt_fontinfo* info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int prefilter_x, int prefilter_y, float *sub_x, float *sub_y, int glyph)
{
   stbtt_MakeGlyphBitmapSubpixel(info,
                                 output,
                                 out_w - (prefilter_x - 1),
                                 out_h - (prefilter_y - 1),
                                 out_stride,
                                 scale_x,
                                 scale_y,
                                 shift_x,
                                 shift_y,
                                 glyph);

   if (prefilter_x > 1)
      stbtt__h_prefilter(output, out_w, out_h, out_stride, prefilter_x);

   if (prefilter_y > 1)
      stbtt__v_prefilter(output, out_w, out_h, out_stride, prefilter_y);

   *sub_x = stbtt__oversample_shift(prefilter_x);
   *sub_y = stbtt__oversample_shift(prefilter_y);
}

// rects array must be big enough to accommodate all characters in the given ranges
public int stbtt_PackFontRangesRenderIntoRects(stbtt_pack_context *spc, stbtt_fontinfo* info, stbtt_pack_range *ranges, int num_ranges, stbrp_rect *rects)
{
   int i,j,k, return_value = 1;

   // save current values
   int old_h_over = spc.h_oversample;
   int old_v_over = spc.v_oversample;

   k = 0;
   for (i=0; i < num_ranges; ++i) {
      float fh = ranges[i].font_size;
      float scale = fh > 0 ? stbtt_ScaleForPixelHeight(info, fh) : stbtt_ScaleForMappingEmToPixels(info, -fh);
      float recip_h,recip_v,sub_x,sub_y;
      spc.h_oversample = ranges[i].h_oversample;
      spc.v_oversample = ranges[i].v_oversample;
      recip_h = 1.0f / spc.h_oversample;
      recip_v = 1.0f / spc.v_oversample;
      sub_x = stbtt__oversample_shift(spc.h_oversample);
      sub_y = stbtt__oversample_shift(spc.v_oversample);
      for (j=0; j < ranges[i].num_chars; ++j) {
         stbrp_rect *r = &rects[k];
         if (r.was_packed) {
            stbtt_packedchar *bc = &ranges[i].chardata_for_range[j];
            int advance, lsb, x0,y0,x1,y1;
            int codepoint = ranges[i].array_of_unicode_codepoints == null ? ranges[i].first_unicode_codepoint_in_range + j : ranges[i].array_of_unicode_codepoints[j];
            int glyph = stbtt_FindGlyphIndex(info, codepoint);
            stbrp_coord pad = cast(stbrp_coord) spc.padding;

            // pad on left and top
            r.x += pad;
            r.y += pad;
            r.w -= pad;
            r.h -= pad;
            stbtt_GetGlyphHMetrics(info, glyph, &advance, &lsb);
            stbtt_GetGlyphBitmapBox(info, glyph,
                                    scale * spc.h_oversample,
                                    scale * spc.v_oversample,
                                    &x0,&y0,&x1,&y1);
            stbtt_MakeGlyphBitmapSubpixel(info,
                                          spc.pixels + r.x + r.y*spc.stride_in_bytes,
                                          r.w - spc.h_oversample+1,
                                          r.h - spc.v_oversample+1,
                                          spc.stride_in_bytes,
                                          scale * spc.h_oversample,
                                          scale * spc.v_oversample,
                                          0,0,
                                          glyph);

            if (spc.h_oversample > 1)
               stbtt__h_prefilter(spc.pixels + r.x + r.y*spc.stride_in_bytes,
                                  r.w, r.h, spc.stride_in_bytes,
                                  spc.h_oversample);

            if (spc.v_oversample > 1)
               stbtt__v_prefilter(spc.pixels + r.x + r.y*spc.stride_in_bytes,
                                  r.w, r.h, spc.stride_in_bytes,
                                  spc.v_oversample);

            bc.x0       = cast(stbtt_int16)  r.x;
            bc.y0       = cast(stbtt_int16)  r.y;
            bc.x1       = cast(stbtt_int16) (r.x + r.w);
            bc.y1       = cast(stbtt_int16) (r.y + r.h);
            bc.xadvance =                scale * advance;
            bc.xoff     =       cast(float)  x0 * recip_h + sub_x;
            bc.yoff     =       cast(float)  y0 * recip_v + sub_y;
            bc.xoff2    =                (x0 + r.w) * recip_h + sub_x;
            bc.yoff2    =                (y0 + r.h) * recip_v + sub_y;
         } else {
            return_value = 0; // if any fail, report failure
         }

         ++k;
      }
   }

   // restore original values
   spc.h_oversample = old_h_over;
   spc.v_oversample = old_v_over;

   return return_value;
}

public void stbtt_PackFontRangesPackRects(stbtt_pack_context *spc, stbrp_rect *rects, int num_rects)
{
   stbrp_pack_rects(cast(stbrp_context *) spc.pack_info, rects, num_rects);
}

public int stbtt_PackFontRanges(stbtt_pack_context *spc, const(ubyte)* fontdata, int font_index, stbtt_pack_range *ranges, int num_ranges)
{
   stbtt_fontinfo info;
   int i,j,n, return_value = 1;
   //stbrp_context *context = (stbrp_context *) spc->pack_info;
   stbrp_rect    *rects;

   // flag all characters as NOT packed
   for (i=0; i < num_ranges; ++i)
      for (j=0; j < ranges[i].num_chars; ++j)
         ranges[i].chardata_for_range[j].x0 =
         ranges[i].chardata_for_range[j].y0 =
         ranges[i].chardata_for_range[j].x1 =
         ranges[i].chardata_for_range[j].y1 = 0;

   n = 0;
   for (i=0; i < num_ranges; ++i)
      n += ranges[i].num_chars;

   rects = cast(stbrp_rect *) STBTT_malloc(cast(uint)(*rects).sizeof * n, spc.user_allocator_context);
   if (rects == null)
      return 0;

   info.userdata = spc.user_allocator_context;
   stbtt_InitFont(&info, fontdata, stbtt_GetFontOffsetForIndex(fontdata,font_index));

   n = stbtt_PackFontRangesGatherRects(spc, &info, ranges, num_ranges, rects);

   stbtt_PackFontRangesPackRects(spc, rects, n);

   return_value = stbtt_PackFontRangesRenderIntoRects(spc, &info, ranges, num_ranges, rects);

   STBTT_free(rects, spc.user_allocator_context);
   return return_value;
}

public int stbtt_PackFontRange(stbtt_pack_context *spc, const(ubyte)* fontdata, int font_index, float font_size,
            int first_unicode_codepoint_in_range, int num_chars_in_range, stbtt_packedchar *chardata_for_range)
{
   stbtt_pack_range range;
   range.first_unicode_codepoint_in_range = first_unicode_codepoint_in_range;
   range.array_of_unicode_codepoints = null;
   range.num_chars                   = num_chars_in_range;
   range.chardata_for_range          = chardata_for_range;
   range.font_size                   = font_size;
   return stbtt_PackFontRanges(spc, fontdata, font_index, &range, 1);
}

public void stbtt_GetPackedQuad(const(stbtt_packedchar)* chardata, int pw, int ph, int char_index, float *xpos, float *ypos, stbtt_aligned_quad *q, int align_to_integer)
{
   float ipw = 1.0f / pw, iph = 1.0f / ph;
   const(stbtt_packedchar)* b = chardata + char_index;

   if (align_to_integer) {
      float x = cast(float) STBTT_ifloor((*xpos + b.xoff) + 0.5f);
      float y = cast(float) STBTT_ifloor((*ypos + b.yoff) + 0.5f);
      q.x0 = x;
      q.y0 = y;
      q.x1 = x + b.xoff2 - b.xoff;
      q.y1 = y + b.yoff2 - b.yoff;
   } else {
      q.x0 = *xpos + b.xoff;
      q.y0 = *ypos + b.yoff;
      q.x1 = *xpos + b.xoff2;
      q.y1 = *ypos + b.yoff2;
   }

   q.s0 = b.x0 * ipw;
   q.t0 = b.y0 * iph;
   q.s1 = b.x1 * ipw;
   q.t1 = b.y1 * iph;

   *xpos += b.xadvance;
}

//////////////////////////////////////////////////////////////////////////////
//
// sdf computation
//

//#define STBTT_min(a,b)  ((a) < (b) ? (a) : (b))
//#define STBTT_max(a,b)  ((a) < (b) ? (b) : (a))
T STBTT_min(T) (in T a, in T b) pure { pragma(inline, true); return (a < b ? a : b); }
T STBTT_max(T) (in T a, in T b) pure { pragma(inline, true); return (a < b ? b : a); }

private int stbtt__ray_intersect_bezier(const scope ref float[2] orig, const scope ref float[2] ray, const scope ref float[2] q0, const scope ref float[2] q1, const scope ref float[2] q2, ref float[2][2] hits)
{
   float q0perp = q0[1]*ray[0] - q0[0]*ray[1];
   float q1perp = q1[1]*ray[0] - q1[0]*ray[1];
   float q2perp = q2[1]*ray[0] - q2[0]*ray[1];
   float roperp = orig[1]*ray[0] - orig[0]*ray[1];

   float a = q0perp - 2*q1perp + q2perp;
   float b = q1perp - q0perp;
   float c = q0perp - roperp;

   float s0 = 0., s1 = 0.;
   int num_s = 0;

   if (a != 0.0) {
      float discr = b*b - a*c;
      if (discr > 0.0) {
         float rcpna = -1 / a;
         float d = cast(float) STBTT_sqrt(discr);
         s0 = (b+d) * rcpna;
         s1 = (b-d) * rcpna;
         if (s0 >= 0.0 && s0 <= 1.0)
            num_s = 1;
         if (d > 0.0 && s1 >= 0.0 && s1 <= 1.0) {
            if (num_s == 0) s0 = s1;
            ++num_s;
         }
      }
   } else {
      // 2*b*s + c = 0
      // s = -c / (2*b)
      s0 = c / (-2 * b);
      if (s0 >= 0.0 && s0 <= 1.0)
         num_s = 1;
   }

   if (num_s == 0)
      return 0;
   else {
      float rcp_len2 = 1 / (ray[0]*ray[0] + ray[1]*ray[1]);
      float rayn_x = ray[0] * rcp_len2, rayn_y = ray[1] * rcp_len2;

      float q0d =   q0[0]*rayn_x +   q0[1]*rayn_y;
      float q1d =   q1[0]*rayn_x +   q1[1]*rayn_y;
      float q2d =   q2[0]*rayn_x +   q2[1]*rayn_y;
      float rod = orig[0]*rayn_x + orig[1]*rayn_y;

      float q10d = q1d - q0d;
      float q20d = q2d - q0d;
      float q0rd = q0d - rod;

      hits[0][0] = q0rd + s0*(2.0f - 2.0f*s0)*q10d + s0*s0*q20d;
      hits[0][1] = a*s0+b;

      if (num_s > 1) {
         hits[1][0] = q0rd + s1*(2.0f - 2.0f*s1)*q10d + s1*s1*q20d;
         hits[1][1] = a*s1+b;
         return 2;
      } else {
         return 1;
      }
   }
}

private int equal(float *a, float *b)
{
   return (a[0] == b[0] && a[1] == b[1]);
}

private int stbtt__compute_crossings_x(float x, float y, int nverts, stbtt_vertex *verts)
{
   int i;
   float[2] orig = void;
   float[2] ray = [ 1, 0 ];
   float y_frac;
   int winding = 0;

   orig[0] = x;
   orig[1] = y;

   // make sure y never passes through a vertex of the shape
   y_frac = cast(float) STBTT_fmod(y, 1.0f);
   if (y_frac < 0.01f)
      y += 0.01f;
   else if (y_frac > 0.99f)
      y -= 0.01f;
   orig[1] = y;

   // test a ray from (-infinity,y) to (x,y)
   for (i=0; i < nverts; ++i) {
      if (verts[i].type == STBTT_vline) {
         int x0 = cast(int) verts[i-1].x, y0 = cast(int) verts[i-1].y;
         int x1 = cast(int) verts[i  ].x, y1 = cast(int) verts[i  ].y;
         if (y > STBTT_min(y0,y1) && y < STBTT_max(y0,y1) && x > STBTT_min(x0,x1)) {
            float x_inter = (y - y0) / (y1 - y0) * (x1-x0) + x0;
            if (x_inter < x)
               winding += (y0 < y1) ? 1 : -1;
         }
      }
      if (verts[i].type == STBTT_vcurve) {
         int x0 = cast(int) verts[i-1].x , y0 = cast(int) verts[i-1].y ;
         int x1 = cast(int) verts[i  ].cx, y1 = cast(int) verts[i  ].cy;
         int x2 = cast(int) verts[i  ].x , y2 = cast(int) verts[i  ].y ;
         int ax = STBTT_min(x0,STBTT_min(x1,x2)), ay = STBTT_min(y0,STBTT_min(y1,y2));
         int by = STBTT_max(y0,STBTT_max(y1,y2));
         if (y > ay && y < by && x > ax) {
            float[2] q0, q1, q2;
            float[2][2] hits;
            q0[0] = cast(float)x0;
            q0[1] = cast(float)y0;
            q1[0] = cast(float)x1;
            q1[1] = cast(float)y1;
            q2[0] = cast(float)x2;
            q2[1] = cast(float)y2;
            if (equal(q0.ptr,q1.ptr) || equal(q1.ptr,q2.ptr)) {
               x0 = cast(int)verts[i-1].x;
               y0 = cast(int)verts[i-1].y;
               x1 = cast(int)verts[i  ].x;
               y1 = cast(int)verts[i  ].y;
               if (y > STBTT_min(y0,y1) && y < STBTT_max(y0,y1) && x > STBTT_min(x0,x1)) {
                  float x_inter = (y - y0) / (y1 - y0) * (x1-x0) + x0;
                  if (x_inter < x)
                     winding += (y0 < y1) ? 1 : -1;
               }
            } else {
               int num_hits = stbtt__ray_intersect_bezier(orig, ray, q0, q1, q2, hits);
               if (num_hits >= 1)
                  if (hits[0][0] < 0)
                     winding += (hits[0][1] < 0 ? -1 : 1);
               if (num_hits >= 2)
                  if (hits[1][0] < 0)
                     winding += (hits[1][1] < 0 ? -1 : 1);
            }
         }
      }
   }
   return winding;
}

private float stbtt__cuberoot( float x )
{
   if (x<0)
      return -cast(float) STBTT_pow(-x,1.0f/3.0f);
   else
      return  cast(float) STBTT_pow( x,1.0f/3.0f);
}

// x^3 + c*x^2 + b*x + a = 0
private int stbtt__solve_cubic(float a, float b, float c, float* r)
{
  float s = -a / 3;
  float p = b - a*a / 3;
  float q = a * (2*a*a - 9*b) / 27 + c;
  float p3 = p*p*p;
  float d = q*q + 4*p3 / 27;
  if (d >= 0) {
    float z = cast(float) STBTT_sqrt(d);
    float u = (-q + z) / 2;
    float v = (-q - z) / 2;
    u = stbtt__cuberoot(u);
    v = stbtt__cuberoot(v);
    r[0] = s + u + v;
    return 1;
  } else {
     float u = cast(float) STBTT_sqrt(-p/3);
     float v = cast(float) STBTT_acos(-STBTT_sqrt(-27/p3) * q / 2) / 3; // p3 must be negative, since d is negative
     float m = cast(float) STBTT_cos(v);
      float n = cast(float) STBTT_cos(v-3.141592/2)*1.732050808f;
     r[0] = s + u * 2 * m;
     r[1] = s - u * (m + n);
     r[2] = s - u * (m - n);

      //STBTT_assert( STBTT_fabs(((r[0]+a)*r[0]+b)*r[0]+c) < 0.05f);  // these asserts may not be safe at all scales, though they're in bezier t parameter units so maybe?
      //STBTT_assert( STBTT_fabs(((r[1]+a)*r[1]+b)*r[1]+c) < 0.05f);
      //STBTT_assert( STBTT_fabs(((r[2]+a)*r[2]+b)*r[2]+c) < 0.05f);
    return 3;
   }
}

public ubyte * stbtt_GetGlyphSDF(stbtt_fontinfo* info, float scale, int glyph, int padding, ubyte onedge_value, float pixel_dist_scale, int *width, int *height, int *xoff, int *yoff)
{
   float scale_x = scale, scale_y = scale;
   int ix0,iy0,ix1,iy1;
   int w,h;
   ubyte *data;

   // if one scale is 0, use same scale for both
   if (scale_x == 0) scale_x = scale_y;
   if (scale_y == 0) {
      if (scale_x == 0) return null;  // if both scales are 0, return NULL
      scale_y = scale_x;
   }

   stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale, scale, 0.0f,0.0f, &ix0,&iy0,&ix1,&iy1);

   // if empty, return NULL
   if (ix0 == ix1 || iy0 == iy1)
      return null;

   ix0 -= padding;
   iy0 -= padding;
   ix1 += padding;
   iy1 += padding;

   w = (ix1 - ix0);
   h = (iy1 - iy0);

   if (width ) *width  = w;
   if (height) *height = h;
   if (xoff  ) *xoff   = ix0;
   if (yoff  ) *yoff   = iy0;

   // invert for y-downwards bitmaps
   scale_y = -scale_y;

   {
      int x,y,i,j;
      float *precompute;
      stbtt_vertex *verts;
      int num_verts = stbtt_GetGlyphShape(info, glyph, &verts);
      data = cast(ubyte *) STBTT_malloc(w * h, info.userdata);
      precompute = cast(float *) STBTT_malloc(num_verts * cast(uint)float.sizeof, info.userdata);

      for (i=0,j=num_verts-1; i < num_verts; j=i++) {
         if (verts[i].type == STBTT_vline) {
            float x0 = verts[i].x*scale_x, y0 = verts[i].y*scale_y;
            float x1 = verts[j].x*scale_x, y1 = verts[j].y*scale_y;
            float dist = cast(float) STBTT_sqrt((x1-x0)*(x1-x0) + (y1-y0)*(y1-y0));
            precompute[i] = (dist == 0) ? 0.0f : 1.0f / dist;
         } else if (verts[i].type == STBTT_vcurve) {
            float x2 = verts[j].x *scale_x, y2 = verts[j].y *scale_y;
            float x1 = verts[i].cx*scale_x, y1 = verts[i].cy*scale_y;
            float x0 = verts[i].x *scale_x, y0 = verts[i].y *scale_y;
            float bx = x0 - 2*x1 + x2, by = y0 - 2*y1 + y2;
            float len2 = bx*bx + by*by;
            if (len2 != 0.0f)
               precompute[i] = 1.0f / (bx*bx + by*by);
            else
               precompute[i] = 0.0f;
         } else
            precompute[i] = 0.0f;
      }

      for (y=iy0; y < iy1; ++y) {
         for (x=ix0; x < ix1; ++x) {
            float val;
            float min_dist = 999999.0f;
            float sx = cast(float) x + 0.5f;
            float sy = cast(float) y + 0.5f;
            float x_gspace = (sx / scale_x);
            float y_gspace = (sy / scale_y);

            int winding = stbtt__compute_crossings_x(x_gspace, y_gspace, num_verts, verts); // @OPTIMIZE: this could just be a rasterization, but needs to be line vs. non-tesselated curves so a new path

            for (i=0; i < num_verts; ++i) {
               float x0 = verts[i].x*scale_x, y0 = verts[i].y*scale_y;

               // check against every point here rather than inside line/curve primitives -- @TODO: wrong if multiple 'moves' in a row produce a garbage point, and given culling, probably more efficient to do within line/curve
               float dist2 = (x0-sx)*(x0-sx) + (y0-sy)*(y0-sy);
               if (dist2 < min_dist*min_dist)
                  min_dist = cast(float) STBTT_sqrt(dist2);

               if (verts[i].type == STBTT_vline) {
                  float x1 = verts[i-1].x*scale_x, y1 = verts[i-1].y*scale_y;

                  // coarse culling against bbox
                  //if (sx > STBTT_min(x0,x1)-min_dist && sx < STBTT_max(x0,x1)+min_dist &&
                  //    sy > STBTT_min(y0,y1)-min_dist && sy < STBTT_max(y0,y1)+min_dist)
                  float dist = cast(float) STBTT_fabs((x1-x0)*(y0-sy) - (y1-y0)*(x0-sx)) * precompute[i];
                  assert(i != 0);
                  if (dist < min_dist) {
                     // check position along line
                     // x' = x0 + t*(x1-x0), y' = y0 + t*(y1-y0)
                     // minimize (x'-sx)*(x'-sx)+(y'-sy)*(y'-sy)
                     float dx = x1-x0, dy = y1-y0;
                     float px = x0-sx, py = y0-sy;
                     // minimize (px+t*dx)^2 + (py+t*dy)^2 = px*px + 2*px*dx*t + t^2*dx*dx + py*py + 2*py*dy*t + t^2*dy*dy
                     // derivative: 2*px*dx + 2*py*dy + (2*dx*dx+2*dy*dy)*t, set to 0 and solve
                     float t = -(px*dx + py*dy) / (dx*dx + dy*dy);
                     if (t >= 0.0f && t <= 1.0f)
                        min_dist = dist;
                  }
               } else if (verts[i].type == STBTT_vcurve) {
                  float x2 = verts[i-1].x *scale_x, y2 = verts[i-1].y *scale_y;
                  float x1 = verts[i  ].cx*scale_x, y1 = verts[i  ].cy*scale_y;
                  float box_x0 = STBTT_min(STBTT_min(x0,x1),x2);
                  float box_y0 = STBTT_min(STBTT_min(y0,y1),y2);
                  float box_x1 = STBTT_max(STBTT_max(x0,x1),x2);
                  float box_y1 = STBTT_max(STBTT_max(y0,y1),y2);
                  // coarse culling against bbox to avoid computing cubic unnecessarily
                  if (sx > box_x0-min_dist && sx < box_x1+min_dist && sy > box_y0-min_dist && sy < box_y1+min_dist) {
                     int num=0;
                     float ax = x1-x0, ay = y1-y0;
                     float bx = x0 - 2*x1 + x2, by = y0 - 2*y1 + y2;
                     float mx = x0 - sx, my = y0 - sy;
                     float[3] res;
                     float px,py,t,it;
                     float a_inv = precompute[i];
                     if (a_inv == 0.0) { // if a_inv is 0, it's 2nd degree so use quadratic formula
                        float a = 3*(ax*bx + ay*by);
                        float b = 2*(ax*ax + ay*ay) + (mx*bx+my*by);
                        float c = mx*ax+my*ay;
                        if (a == 0.0) { // if a is 0, it's linear
                           if (b != 0.0) {
                              res[num++] = -c/b;
                           }
                        } else {
                           float discriminant = b*b - 4*a*c;
                           if (discriminant < 0)
                              num = 0;
                           else {
                              float root = cast(float) STBTT_sqrt(discriminant);
                              res[0] = (-b - root)/(2*a);
                              res[1] = (-b + root)/(2*a);
                              num = 2; // don't bother distinguishing 1-solution case, as code below will still work
                           }
                        }
                     } else {
                        float b = 3*(ax*bx + ay*by) * a_inv; // could precompute this as it doesn't depend on sample point
                        float c = (2*(ax*ax + ay*ay) + (mx*bx+my*by)) * a_inv;
                        float d = (mx*ax+my*ay) * a_inv;
                        num = stbtt__solve_cubic(b, c, d, res.ptr);
                     }
                     if (num >= 1 && res[0] >= 0.0f && res[0] <= 1.0f) {
                        t = res[0], it = 1.0f - t;
                        px = it*it*x0 + 2*t*it*x1 + t*t*x2;
                        py = it*it*y0 + 2*t*it*y1 + t*t*y2;
                        dist2 = (px-sx)*(px-sx) + (py-sy)*(py-sy);
                        if (dist2 < min_dist * min_dist)
                           min_dist = cast(float) STBTT_sqrt(dist2);
                     }
                     if (num >= 2 && res[1] >= 0.0f && res[1] <= 1.0f) {
                        t = res[1], it = 1.0f - t;
                        px = it*it*x0 + 2*t*it*x1 + t*t*x2;
                        py = it*it*y0 + 2*t*it*y1 + t*t*y2;
                        dist2 = (px-sx)*(px-sx) + (py-sy)*(py-sy);
                        if (dist2 < min_dist * min_dist)
                           min_dist = cast(float) STBTT_sqrt(dist2);
                     }
                     if (num >= 3 && res[2] >= 0.0f && res[2] <= 1.0f) {
                        t = res[2], it = 1.0f - t;
                        px = it*it*x0 + 2*t*it*x1 + t*t*x2;
                        py = it*it*y0 + 2*t*it*y1 + t*t*y2;
                        dist2 = (px-sx)*(px-sx) + (py-sy)*(py-sy);
                        if (dist2 < min_dist * min_dist)
                           min_dist = cast(float) STBTT_sqrt(dist2);
                     }
                  }
               }
            }
            if (winding == 0)
               min_dist = -min_dist;  // if outside the shape, value is negative
            val = onedge_value + pixel_dist_scale * min_dist;
            if (val < 0)
               val = 0;
            else if (val > 255)
               val = 255;
            data[(y-iy0)*w+(x-ix0)] = cast(ubyte) val;
         }
      }
      STBTT_free(precompute, info.userdata);
      STBTT_free(verts, info.userdata);
   }
   return data;
}

public ubyte * stbtt_GetCodepointSDF(stbtt_fontinfo* info, float scale, int codepoint, int padding, ubyte onedge_value, float pixel_dist_scale, int *width, int *height, int *xoff, int *yoff)
{
   return stbtt_GetGlyphSDF(info, scale, stbtt_FindGlyphIndex(info, codepoint), padding, onedge_value, pixel_dist_scale, width, height, xoff, yoff);
}

public void stbtt_FreeSDF(ubyte *bitmap, void *userdata)
{
   STBTT_free(bitmap, userdata);
}

//////////////////////////////////////////////////////////////////////////////
//
// font name matching -- recommended not to use this
//

// check if a utf8 string contains a prefix which is the utf16 string; if so return length of matching utf8 string
private stbtt_int32 stbtt__CompareUTF8toUTF16_bigendian_prefix(stbtt_uint8 *s1, stbtt_int32 len1, stbtt_uint8 *s2, stbtt_int32 len2)
{
   stbtt_int32 i=0;

   // convert utf16 to utf8 and compare the results while converting
   while (len2) {
      stbtt_uint16 ch = s2[0]*256 + s2[1];
      if (ch < 0x80) {
         if (i >= len1) return -1;
         if (s1[i++] != ch) return -1;
      } else if (ch < 0x800) {
         if (i+1 >= len1) return -1;
         if (s1[i++] != 0xc0 + (ch >> 6)) return -1;
         if (s1[i++] != 0x80 + (ch & 0x3f)) return -1;
      } else if (ch >= 0xd800 && ch < 0xdc00) {
         stbtt_uint32 c;
         stbtt_uint16 ch2 = s2[2]*256 + s2[3];
         if (i+3 >= len1) return -1;
         c = ((ch - 0xd800) << 10) + (ch2 - 0xdc00) + 0x10000;
         if (s1[i++] != 0xf0 + (c >> 18)) return -1;
         if (s1[i++] != 0x80 + ((c >> 12) & 0x3f)) return -1;
         if (s1[i++] != 0x80 + ((c >>  6) & 0x3f)) return -1;
         if (s1[i++] != 0x80 + ((c      ) & 0x3f)) return -1;
         s2 += 2; // plus another 2 below
         len2 -= 2;
      } else if (ch >= 0xdc00 && ch < 0xe000) {
         return -1;
      } else {
         if (i+2 >= len1) return -1;
         if (s1[i++] != 0xe0 + (ch >> 12)) return -1;
         if (s1[i++] != 0x80 + ((ch >> 6) & 0x3f)) return -1;
         if (s1[i++] != 0x80 + ((ch     ) & 0x3f)) return -1;
      }
      s2 += 2;
      len2 -= 2;
   }
   return i;
}

private int stbtt_CompareUTF8toUTF16_bigendian_internal(char *s1, int len1, char *s2, int len2)
{
   return len1 == stbtt__CompareUTF8toUTF16_bigendian_prefix(cast(stbtt_uint8*) s1, len1, cast(stbtt_uint8*) s2, len2);
}

// returns results in whatever encoding you request... but note that 2-byte encodings
// will be BIG-ENDIAN... use stbtt_CompareUTF8toUTF16_bigendian() to compare
public const(char)* stbtt_GetFontNameString(stbtt_fontinfo* font, int *length, int platformID, int encodingID, int languageID, int nameID)
{
   stbtt_int32 i,count,stringOffset;
   stbtt_uint8 *fc = font.data;
   stbtt_uint32 offset = font.fontstart;
   stbtt_uint32 nm = stbtt__find_table(fc, offset, "name");
   if (!nm) return null;

   count = ttUSHORT(fc+nm+2);
   stringOffset = nm + ttUSHORT(fc+nm+4);
   for (i=0; i < count; ++i) {
      stbtt_uint32 loc = nm + 6 + 12 * i;
      if (platformID == ttUSHORT(fc+loc+0) && encodingID == ttUSHORT(fc+loc+2)
          && languageID == ttUSHORT(fc+loc+4) && nameID == ttUSHORT(fc+loc+6)) {
         *length = ttUSHORT(fc+loc+8);
         return cast(const(char)* ) (fc+stringOffset+ttUSHORT(fc+loc+10));
      }
   }
   return null;
}

private int stbtt__matchpair(stbtt_uint8 *fc, stbtt_uint32 nm, stbtt_uint8 *name, stbtt_int32 nlen, stbtt_int32 target_id, stbtt_int32 next_id)
{
   stbtt_int32 i;
   stbtt_int32 count = ttUSHORT(fc+nm+2);
   stbtt_int32 stringOffset = nm + ttUSHORT(fc+nm+4);

   for (i=0; i < count; ++i) {
      stbtt_uint32 loc = nm + 6 + 12 * i;
      stbtt_int32 id = ttUSHORT(fc+loc+6);
      if (id == target_id) {
         // find the encoding
         stbtt_int32 platform = ttUSHORT(fc+loc+0), encoding = ttUSHORT(fc+loc+2), language = ttUSHORT(fc+loc+4);

         // is this a Unicode encoding?
         if (platform == 0 || (platform == 3 && encoding == 1) || (platform == 3 && encoding == 10)) {
            stbtt_int32 slen = ttUSHORT(fc+loc+8);
            stbtt_int32 off = ttUSHORT(fc+loc+10);

            // check if there's a prefix match
            stbtt_int32 matchlen = stbtt__CompareUTF8toUTF16_bigendian_prefix(name, nlen, fc+stringOffset+off,slen);
            if (matchlen >= 0) {
               // check for target_id+1 immediately following, with same encoding & language
               if (i+1 < count && ttUSHORT(fc+loc+12+6) == next_id && ttUSHORT(fc+loc+12) == platform && ttUSHORT(fc+loc+12+2) == encoding && ttUSHORT(fc+loc+12+4) == language) {
                  slen = ttUSHORT(fc+loc+12+8);
                  off = ttUSHORT(fc+loc+12+10);
                  if (slen == 0) {
                     if (matchlen == nlen)
                        return 1;
                  } else if (matchlen < nlen && name[matchlen] == ' ') {
                     ++matchlen;
                     if (stbtt_CompareUTF8toUTF16_bigendian_internal(cast(char*) (name+matchlen), nlen-matchlen, cast(char*)(fc+stringOffset+off),slen))
                        return 1;
                  }
               } else {
                  // if nothing immediately following
                  if (matchlen == nlen)
                     return 1;
               }
            }
         }

         // @TODO handle other encodings
      }
   }
   return 0;
}

private int stbtt__matches(stbtt_uint8 *fc, stbtt_uint32 offset, stbtt_uint8 *name, stbtt_int32 flags)
{
   stbtt_int32 nlen = cast(stbtt_int32) STBTT_strlen(cast(char *) name);
   stbtt_uint32 nm,hd;
   if (!stbtt__isfont(fc+offset)) return 0;

   // check italics/bold/underline flags in macStyle...
   if (flags) {
      hd = stbtt__find_table(fc, offset, "head");
      if ((ttUSHORT(fc+hd+44) & 7) != (flags & 7)) return 0;
   }

   nm = stbtt__find_table(fc, offset, "name");
   if (!nm) return 0;

   if (flags) {
      // if we checked the macStyle flags, then just check the family and ignore the subfamily
      if (stbtt__matchpair(fc, nm, name, nlen, 16, -1))  return 1;
      if (stbtt__matchpair(fc, nm, name, nlen,  1, -1))  return 1;
      if (stbtt__matchpair(fc, nm, name, nlen,  3, -1))  return 1;
   } else {
      if (stbtt__matchpair(fc, nm, name, nlen, 16, 17))  return 1;
      if (stbtt__matchpair(fc, nm, name, nlen,  1,  2))  return 1;
      if (stbtt__matchpair(fc, nm, name, nlen,  3, -1))  return 1;
   }

   return 0;
}

private int stbtt_FindMatchingFont_internal(ubyte *font_collection, char *name_utf8, stbtt_int32 flags)
{
   stbtt_int32 i;
   for (i=0;;++i) {
      stbtt_int32 off = stbtt_GetFontOffsetForIndex(font_collection, i);
      if (off < 0) return off;
      if (stbtt__matches(cast(stbtt_uint8 *) font_collection, off, cast(stbtt_uint8*) name_utf8, flags))
         return off;
   }
}

public int stbtt_BakeFontBitmap(const(ubyte)* data, int offset,
                                float pixel_height, ubyte *pixels, int pw, int ph,
                                int first_char, int num_chars, stbtt_bakedchar *chardata,
				int* ascent = null, int* descent = null, int* line_gap = null
				)
{
   return stbtt_BakeFontBitmap_internal(cast(ubyte *) data, offset, pixel_height, pixels, pw, ph, first_char, num_chars, chardata, ascent, descent, line_gap);
}

public int stbtt_GetFontOffsetForIndex(const(ubyte)* data, int index)
{
   return stbtt_GetFontOffsetForIndex_internal(cast(ubyte *) data, index);
}

public int stbtt_GetNumberOfFonts(const(ubyte)* data)
{
   return stbtt_GetNumberOfFonts_internal(cast(ubyte *) data);
}

public int stbtt_InitFont(stbtt_fontinfo *info, const(ubyte)* data, int offset)
{
   return stbtt_InitFont_internal(info, cast(ubyte *) data, offset);
}

public int stbtt_FindMatchingFont(const(ubyte)* fontdata, const(char)* name, int flags)
{
   return stbtt_FindMatchingFont_internal(cast(ubyte *) fontdata, cast(char *) name, flags);
}

public int stbtt_CompareUTF8toUTF16_bigendian(const(char)* s1, int len1, const(char)* s2, int len2)
{
   return stbtt_CompareUTF8toUTF16_bigendian_internal(cast(char *) s1, len1, cast(char *) s2, len2);
}


// FULL VERSION HISTORY
//
//   1.19 (2018-02-11) OpenType GPOS kerning (horizontal only), STBTT_fmod
//   1.18 (2018-01-29) add missing function
//   1.17 (2017-07-23) make more arguments const; doc fix
//   1.16 (2017-07-12) SDF support
//   1.15 (2017-03-03) make more arguments const
//   1.14 (2017-01-16) num-fonts-in-TTC function
//   1.13 (2017-01-02) support OpenType fonts, certain Apple fonts
//   1.12 (2016-10-25) suppress warnings about casting away const with -Wcast-qual
//   1.11 (2016-04-02) fix unused-variable warning
//   1.10 (2016-04-02) allow user-defined fabs() replacement
//                     fix memory leak if fontsize=0.0
//                     fix warning from duplicate typedef
//   1.09 (2016-01-16) warning fix; avoid crash on outofmem; use alloc userdata for PackFontRanges
//   1.08 (2015-09-13) document stbtt_Rasterize(); fixes for vertical & horizontal edges
//   1.07 (2015-08-01) allow PackFontRanges to accept arrays of sparse codepoints;
//                     allow PackFontRanges to pack and render in separate phases;
//                     fix stbtt_GetFontOFfsetForIndex (never worked for non-0 input?);
//                     fixed an assert() bug in the new rasterizer
//                     replace assert() with STBTT_assert() in new rasterizer
//   1.06 (2015-07-14) performance improvements (~35% faster on x86 and x64 on test machine)
//                     also more precise AA rasterizer, except if shapes overlap
//                     remove need for STBTT_sort
//   1.05 (2015-04-15) fix misplaced definitions for STBTT_STATIC
//   1.04 (2015-04-15) typo in example
//   1.03 (2015-04-12) STBTT_STATIC, fix memory leak in new packing, various fixes
//   1.02 (2014-12-10) fix various warnings & compile issues w/ stb_rect_pack, C++
//   1.01 (2014-12-08) fix subpixel position when oversampling to exactly match
//                        non-oversampled; STBTT_POINT_SIZE for packed case only
//   1.00 (2014-12-06) add new PackBegin etc. API, w/ support for oversampling
//   0.99 (2014-09-18) fix multiple bugs with subpixel rendering (ryg)
//   0.9  (2014-08-07) support certain mac/iOS fonts without an MS platformID
//   0.8b (2014-07-07) fix a warning
//   0.8  (2014-05-25) fix a few more warnings
//   0.7  (2013-09-25) bugfix: subpixel glyph bug fixed in 0.5 had come back
//   0.6c (2012-07-24) improve documentation
//   0.6b (2012-07-20) fix a few more warnings
//   0.6  (2012-07-17) fix warnings; added stbtt_ScaleForMappingEmToPixels,
//                        stbtt_GetFontBoundingBox, stbtt_IsGlyphEmpty
//   0.5  (2011-12-09) bugfixes:
//                        subpixel glyph renderer computed wrong bounding box
//                        first vertex of shape can be off-curve (FreeSans)
//   0.4b (2011-12-03) fixed an error in the font baking example
//   0.4  (2011-12-01) kerning, subpixel rendering (tor)
//                    bugfixes for:
//                        codepoint-to-glyph conversion using table fmt=12
//                        codepoint-to-glyph conversion using table fmt=4
//                        stbtt_GetBakedQuad with non-square texture (Zer)
//                    updated Hello World! sample to use kerning and subpixel
//                    fixed some warnings
//   0.3  (2009-06-24) cmap fmt=12, compound shapes (MM)
//                    userdata, malloc-from-userdata, non-zero fill (stb)
//   0.2  (2009-03-11) Fix unsigned/signed char warnings
//   0.1  (2009-03-09) First public release
//

/*
------------------------------------------------------------------------------
This software is available under 2 licenses -- choose whichever you prefer.
------------------------------------------------------------------------------
ALTERNATIVE A - MIT License
Copyright (c) 2017 Sean Barrett
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
------------------------------------------------------------------------------
ALTERNATIVE B - Public Domain (www.unlicense.org)
This is free and unencumbered software released into the public domain.
Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.
In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
------------------------------------------------------------------------------
*/
