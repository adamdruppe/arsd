/// stb_truetype.h - v0.6c - public domain
/// authored from 2009-2012 by Sean Barrett / RAD Game Tools
//
// http://nothings.org/stb/stb_truetype.h
//
// port to D by adam d. ruppe. see the link above for more info about the lib and real author.

// here's some D convenience functions
module stb_truetype;

struct TtfFont {
	stbtt_fontinfo font;
	this(in ubyte[] data) {
		load(data);
	}

	void load(in ubyte[] data) {
   		if(stbtt_InitFont(&font, data.ptr, stbtt_GetFontOffsetForIndex(data.ptr, 0)) == 0)
			throw new Exception("load font problem");
	}

	ubyte[] renderCharacter(dchar c, int size, out int width, out int height, float shift_x = 0.0, float shift_y = 0.0) {
   		auto ptr = stbtt_GetCodepointBitmapSubpixel(&font, 0.0,stbtt_ScaleForPixelHeight(&font, size),
			shift_x, shift_y, c, &width, &height, null,null);
		return ptr[0 .. width * height];
	}

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


// test program
/+
int main(string[] args)
{
import std.conv;
import simpledisplay;
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




// STB_IMAGE FOLLOWS


   alias ubyte  stbtt_uint8;
   alias byte   stbtt_int8;
   alias ushort stbtt_uint16;
   alias short  stbtt_int16;
   alias uint   stbtt_uint32;
   alias int    stbtt_int32;

   alias char[(stbtt_int32.sizeof)==4 ? 1 : -1] stbtt__check_size32;
   alias char[(stbtt_int16.sizeof)==2 ? 1 : -1] stbtt__check_size16;

   static import core.stdc.stdlib;
   alias STBTT_sort = core.stdc.stdlib.qsort;

   static import std.math;
   int STBTT_ifloor(float x) { return cast(int) std.math.floor(x); }
   int STBTT_iceil(float x) { return cast(int) std.math.ceil(x); }

   void* STBTT_malloc(size_t x, in void* u) { import core.memory; return GC.malloc(x); /*return core.stdc.stdlib.malloc(x);*/ }
   void STBTT_free(void* x,in void* u) { /*return core.stdc.stdlib.free(x);*/ }

   static import core.stdc.string;
   alias STBTT_strlen = core.stdc.string.strlen;

   alias STBTT_memcpy = core.stdc.string.memcpy;
   alias STBTT_memset = core.stdc.string.memset;

//////////////////////////////////////////////////////////////////////////////
//
// TEXTURE BAKING API
//
// If you use this API, you only have to call two functions ever.
//

struct stbtt_bakedchar
{
   ushort x0,y0,x1,y1; // coordinates of bbox in bitmap
   float xoff,yoff,xadvance;   
}

// if return is positive, the first unused row of the bitmap
// if return is negative, returns the negative of the number of characters that fit
// if return is 0, no characters fit and no rows were used
// This uses a very crappy packing.

struct stbtt_aligned_quad
{
   float x0,y0,s0,t0; // top-left
   float x1,y1,s1,t1; // bottom-right
}

// Call GetBakedQuad with char_index = 'character - first_char', and it
// creates the quad you need to draw and advances the current position.
//
// The coordinate system used assumes y increases downwards.
//
// Characters will extend both above and below the current position;
// see discussion of "BASELINE" above.
//
// It's inefficient; you might want to c&p it and optimize it.


//////////////////////////////////////////////////////////////////////////////
//
// FONT LOADING
//
//

// Each .ttf/.ttc file may have more than one font. Each font has a sequential
// index number starting from 0. Call this function to get the font offset for
// a given index; it returns -1 if the index is out of range. A regular .ttf
// file will only define one font and it always be at offset 0, so it will
// return '0' for index 0, and -1 for all other indices. You can just skip
// this step if you know it's that kind of font.


// The following structure is defined publically so you can declare one on
// the stack or as a global or etc, but you should treat it as opaque.
struct stbtt_fontinfo
{
   void           * userdata;
   ubyte  * data;              // pointer to .ttf file
   int              fontstart;         // offset of start of font

   int numGlyphs;                     // number of glyphs, needed for range checking

   int loca,head,glyf,hhea,hmtx,kern; // table locations as offset from start of .ttf
   int index_map;                     // a cmap mapping for our chosen character encoding
   int indexToLocFormat;              // format needed to map from glyph index to glyph
}

// Given an offset into the file that defines a font, this function builds
// the necessary cached info for the rest of the system. You must allocate
// the stbtt_fontinfo yourself, and stbtt_InitFont will fill it out. You don't
// need to do anything special to free it, because the contents are pure
// value data with no additional data structures. Returns 0 on failure.


//////////////////////////////////////////////////////////////////////////////
//
// GLYPH SHAPES (you probably don't need these, but they have to go before
// the bitmaps for C declaration-order reasons)
//

   enum {
      STBTT_vmove=1,
      STBTT_vline,
      STBTT_vcurve
   }

   alias short stbtt_vertex_type;
   struct stbtt_vertex
   {
      stbtt_vertex_type x,y,cx,cy;
      ubyte type,padding;
   }

// @TODO: don't expose this structure
struct stbtt__bitmap
{
   int w,h,stride;
   ubyte *pixels;
}

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


enum STBTT_MACSTYLE_DONTCARE   = 0;
enum STBTT_MACSTYLE_BOLD       = 1;
enum STBTT_MACSTYLE_ITALIC     = 2;
enum STBTT_MACSTYLE_UNDERSCORE = 4;
enum STBTT_MACSTYLE_NONE       = 8;   // <= not same as 0, this makes us check the bitfield is 0

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
};

enum { // encodingID for STBTT_PLATFORM_ID_UNICODE
   STBTT_UNICODE_EID_UNICODE_1_0    =0,
   STBTT_UNICODE_EID_UNICODE_1_1    =1,
   STBTT_UNICODE_EID_ISO_10646      =2,
   STBTT_UNICODE_EID_UNICODE_2_0_BMP=3,
   STBTT_UNICODE_EID_UNICODE_2_0_FULL=4
};

enum { // encodingID for STBTT_PLATFORM_ID_MICROSOFT
   STBTT_MS_EID_SYMBOL        =0,
   STBTT_MS_EID_UNICODE_BMP   =1,
   STBTT_MS_EID_SHIFTJIS      =2,
   STBTT_MS_EID_UNICODE_FULL  =10
};

enum { // encodingID for STBTT_PLATFORM_ID_MAC; same as Script Manager codes
   STBTT_MAC_EID_ROMAN        =0,   STBTT_MAC_EID_ARABIC       =4,
   STBTT_MAC_EID_JAPANESE     =1,   STBTT_MAC_EID_HEBREW       =5,
   STBTT_MAC_EID_CHINESE_TRAD =2,   STBTT_MAC_EID_GREEK        =6,
   STBTT_MAC_EID_KOREAN       =3,   STBTT_MAC_EID_RUSSIAN      =7
};

enum { // languageID for STBTT_PLATFORM_ID_MICROSOFT; same as LCID...
       // problematic because there are e.g. 16 english LCIDs and 16 arabic LCIDs
   STBTT_MS_LANG_ENGLISH     =0x0409,   STBTT_MS_LANG_ITALIAN     =0x0410,
   STBTT_MS_LANG_CHINESE     =0x0804,   STBTT_MS_LANG_JAPANESE    =0x0411,
   STBTT_MS_LANG_DUTCH       =0x0413,   STBTT_MS_LANG_KOREAN      =0x0412,
   STBTT_MS_LANG_FRENCH      =0x040c,   STBTT_MS_LANG_RUSSIAN     =0x0419,
   STBTT_MS_LANG_GERMAN      =0x0407,   STBTT_MS_LANG_SPANISH     =0x0409,
   STBTT_MS_LANG_HEBREW      =0x040d,   STBTT_MS_LANG_SWEDISH     =0x041D
};

enum { // languageID for STBTT_PLATFORM_ID_MAC
   STBTT_MAC_LANG_ENGLISH      =0 ,   STBTT_MAC_LANG_JAPANESE     =11,
   STBTT_MAC_LANG_ARABIC       =12,   STBTT_MAC_LANG_KOREAN       =23,
   STBTT_MAC_LANG_DUTCH        =4 ,   STBTT_MAC_LANG_RUSSIAN      =32,
   STBTT_MAC_LANG_FRENCH       =1 ,   STBTT_MAC_LANG_SPANISH      =6 ,
   STBTT_MAC_LANG_GERMAN       =2 ,   STBTT_MAC_LANG_SWEDISH      =5 ,
   STBTT_MAC_LANG_HEBREW       =10,   STBTT_MAC_LANG_CHINESE_SIMPLIFIED =33,
   STBTT_MAC_LANG_ITALIAN      =3 ,   STBTT_MAC_LANG_CHINESE_TRAD =19
};

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
////
////   IMPLEMENTATION
////
////

//////////////////////////////////////////////////////////////////////////
//
// accessors to parse data from file
//

// on platforms that don't allow misaligned reads, if we want to allow
// truetype fonts that aren't padded to alignment, define ALLOW_UNALIGNED_TRUETYPE

stbtt_uint8 ttBYTE(in stbtt_uint8* p) { return * cast(stbtt_uint8 *) (p); }
stbtt_int8 ttCHAR(in stbtt_uint8* p)     { return * cast(stbtt_int8 *) (p); }
stbtt_int32 ttFixed(in stbtt_uint8* p) { return ttLONG(p); }

version(BigEndian) {
   stbtt_uint16 ttUSHORT(in stbtt_uint8* p)   { return * cast(stbtt_uint16 *) (p); }
   stbtt_int16 ttSHORT(in stbtt_uint8* p)    { return * cast(stbtt_int16 *) (p); }
   stbtt_uint32 ttULONG(in stbtt_uint8* p)    { return * cast(stbtt_uint32 *) (p); }
   stbtt_int32 ttLONG(in stbtt_uint8* p)     { return * cast(stbtt_int32 *) (p); }
} else {
   stbtt_uint16 ttUSHORT(const stbtt_uint8 *p) { return p[0]*256 + p[1]; }
   stbtt_int16 ttSHORT(const stbtt_uint8 *p)   { return cast(short)(p[0]*256 + p[1]); }
   stbtt_uint32 ttULONG(const stbtt_uint8 *p)  { return (p[0]<<24) + (p[1]<<16) + (p[2]<<8) + p[3]; }
   stbtt_int32 ttLONG(const stbtt_uint8 *p)    { return (p[0]<<24) + (p[1]<<16) + (p[2]<<8) + p[3]; }
}


bool stbtt_tag4(in stbtt_uint8* p,int c0, int c1, int c2, int c3) { return ((p)[0] == (c0) && (p)[1] == (c1) && (p)[2] == (c2) && (p)[3] == (c3)); }
bool stbtt_tag(in stbtt_uint8* p, in char* str) { return stbtt_tag4(p,str[0],str[1],str[2],str[3]); }

static int stbtt__isfont(const stbtt_uint8 *font)
{
   // check the version number
   if (stbtt_tag4(font, '1',0,0,0))  return 1; // TrueType 1
   if (stbtt_tag(font, "typ1".ptr))   return 1; // TrueType with type 1 font -- we don't support this!
   if (stbtt_tag(font, "OTTO".ptr))   return 1; // OpenType with CFF
   if (stbtt_tag4(font, 0,1,0,0)) return 1; // OpenType 1.0
   return 0;
}

// @OPTIMIZE: binary search
static stbtt_uint32 stbtt__find_table(const(stbtt_uint8) *data, stbtt_uint32 fontstart, const char *tag)
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

int stbtt_GetFontOffsetForIndex(const ubyte *font_collection, int index)
{
   // if it's just a font, there's only one valid index
   if (stbtt__isfont(font_collection))
      return index == 0 ? 0 : -1;

   // check if it's a TTC
   if (stbtt_tag(font_collection, "ttcf")) {
      // version 1?
      if (ttULONG(font_collection+4) == 0x00010000 || ttULONG(font_collection+4) == 0x00020000) {
         stbtt_int32 n = ttLONG(font_collection+8);
         if (index >= n)
            return -1;
         return ttULONG(font_collection+12+index*14);
      }
   }
   return -1;
}

int stbtt_InitFont(stbtt_fontinfo *info, const ubyte *data2, int fontstart)
{
   stbtt_uint8 *data = cast(stbtt_uint8 *) data2;
   stbtt_uint32 cmap, t;
   stbtt_int32 i,numTables;

   info.data = data;
   info.fontstart = fontstart;

   cmap = stbtt__find_table(data, fontstart, "cmap");       // required
   info.loca = stbtt__find_table(data, fontstart, "loca"); // required
   info.head = stbtt__find_table(data, fontstart, "head"); // required
   info.glyf = stbtt__find_table(data, fontstart, "glyf"); // required
   info.hhea = stbtt__find_table(data, fontstart, "hhea"); // required
   info.hmtx = stbtt__find_table(data, fontstart, "hmtx"); // required
   info.kern = stbtt__find_table(data, fontstart, "kern"); // not required
   if (!cmap || !info.loca || !info.head || !info.glyf || !info.hhea || !info.hmtx)
      return 0;

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
      	default: break;//assert(0);
         case STBTT_PLATFORM_ID_MICROSOFT:
            switch (ttUSHORT(data+encoding_record+2)) {
	       default: assert(0);
               case STBTT_MS_EID_UNICODE_BMP:
               case STBTT_MS_EID_UNICODE_FULL:
                  // MS/Unicode
                  info.index_map = cmap + ttULONG(data+encoding_record+4);
                  break;
            }
            break;
      }
   }
   if (info.index_map == 0)
      return 0;

   info.indexToLocFormat = ttUSHORT(data+info.head + 50);
   return 1;
}

int stbtt_FindGlyphIndex(const stbtt_fontinfo *info, int unicode_codepoint)
{
   const(stbtt_uint8) *data = info.data;
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
      //return 0;
   } else if (format == 4) { // standard mapping for windows fonts: binary search collection of ranges
      stbtt_uint16 segcount = ttUSHORT(data+index_map+6) >> 1;
      stbtt_uint16 searchRange = ttUSHORT(data+index_map+8) >> 1;
      stbtt_uint16 entrySelector = ttUSHORT(data+index_map+10);
      stbtt_uint16 rangeShift = ttUSHORT(data+index_map+12) >> 1;
      stbtt_uint16 item, offset, start, end;

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
         stbtt_uint16 start2, end2;
         searchRange >>= 1;
         start2 = ttUSHORT(data + search + 2 + segcount*2 + 2);
         end2 = ttUSHORT(data + search + 2);
         start2 = ttUSHORT(data + search + searchRange*2 + segcount*2 + 2);
         end2 = ttUSHORT(data + search + searchRange*2);
         if (unicode_codepoint > end2)
            search += searchRange*2;
         --entrySelector;
      }
      search += 2;

      item = cast(stbtt_uint16) ((search - endCount) >> 1);

      assert(unicode_codepoint <= ttUSHORT(data + endCount + 2*item));
      start = ttUSHORT(data + index_map + 14 + segcount*2 + 2 + 2*item);
      end = ttUSHORT(data + index_map + 14 + 2 + 2*item);
      if (unicode_codepoint < start)
         return 0;

      offset = ttUSHORT(data + index_map + 14 + segcount*6 + 2 + 2*item);
      if (offset == 0)
         return cast(stbtt_uint16) (unicode_codepoint + ttSHORT(data + index_map + 14 + segcount*4 + 2 + 2*item));

      return ttUSHORT(data + offset + (unicode_codepoint-start)*2 + index_map + 14 + segcount*6 + 2 + 2*item);
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
   // return 0;
}

int stbtt_GetCodepointShape(const stbtt_fontinfo *info, int unicode_codepoint, stbtt_vertex **vertices)
{
   return stbtt_GetGlyphShape(info, stbtt_FindGlyphIndex(info, unicode_codepoint), vertices);
}

static void stbtt_setvertex(stbtt_vertex *v, stbtt_uint8 type, stbtt_int32 x, stbtt_int32 y, stbtt_int32 cx, stbtt_int32 cy)
{
   v.type = type;
   v.x = cast(stbtt_int16) x;
   v.y = cast(stbtt_int16) y;
   v.cx = cast(stbtt_int16) cx;
   v.cy = cast(stbtt_int16) cy;
}

static int stbtt__GetGlyfOffset(const stbtt_fontinfo *info, int glyph_index)
{
   int g1,g2;

   if (glyph_index >= info.numGlyphs) return -1; // glyph index out of range
   if (info.indexToLocFormat >= 2)    return -1; // unknown index.glyph map format

   if (info.indexToLocFormat == 0) {
      g1 = info.glyf + ttUSHORT(info.data + info.loca + glyph_index * 2) * 2;
      g2 = info.glyf + ttUSHORT(info.data + info.loca + glyph_index * 2 + 2) * 2;
   } else {
      g1 = info.glyf + ttULONG (info.data + info.loca + glyph_index * 4);
      g2 = info.glyf + ttULONG (info.data + info.loca + glyph_index * 4 + 4);
   }

   return g1==g2 ? -1 : g1; // if length is 0, return -1
}

int stbtt_GetGlyphBox(const stbtt_fontinfo *info, int glyph_index, int *x0, int *y0, int *x1, int *y1)
{
   int g = stbtt__GetGlyfOffset(info, glyph_index);
   if (g < 0) return 0;

   if (x0) *x0 = ttSHORT(info.data + g + 2);
   if (y0) *y0 = ttSHORT(info.data + g + 4);
   if (x1) *x1 = ttSHORT(info.data + g + 6);
   if (y1) *y1 = ttSHORT(info.data + g + 8);
   return 1;
}

int stbtt_GetCodepointBox(const stbtt_fontinfo *info, int codepoint, int *x0, int *y0, int *x1, int *y1)
{
   return stbtt_GetGlyphBox(info, stbtt_FindGlyphIndex(info,codepoint), x0,y0,x1,y1);
}

int stbtt_IsGlyphEmpty(const stbtt_fontinfo *info, int glyph_index)
{
   stbtt_int16 numberOfContours;
   int g = stbtt__GetGlyfOffset(info, glyph_index);
   if (g < 0) return 1;
   numberOfContours = ttSHORT(info.data + g);
   return numberOfContours == 0;
}

static int stbtt__close_shape(stbtt_vertex *vertices, int num_vertices, int was_off, int start_off,
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

int stbtt_GetGlyphShape(const stbtt_fontinfo *info, int glyph_index, stbtt_vertex **pvertices)
{
   stbtt_int16 numberOfContours;
   const(stbtt_uint8) *endPtsOfContours;
   const(stbtt_uint8) *data = info.data;
   stbtt_vertex *vertices=null;
   int num_vertices=0;
   int g = stbtt__GetGlyfOffset(info, glyph_index);

   *pvertices = null;

   if (g < 0) return 0;

   numberOfContours = ttSHORT(data + g);

   if (numberOfContours > 0) {
      stbtt_uint8 flags=0,flagcount;
      stbtt_int32 ins, i,j=0,m,n, next_move, was_off=0, off, start_off=0;
      stbtt_int32 x,y,cx,cy,sx,sy, scx,scy;
      const(stbtt_uint8) *points;
      endPtsOfContours = (data + g + 10);
      ins = ttUSHORT(data + g + 10 + numberOfContours * 2);
      points = data + g + 10 + numberOfContours * 2 + 2 + ins;

      n = 1+ttUSHORT(endPtsOfContours + numberOfContours*2-2);

      m = n + 2*numberOfContours;  // a loose bound on how many vertices we might need
      vertices = cast(stbtt_vertex *) STBTT_malloc(m * vertices[0].sizeof, info.userdata);
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
            x += (flags & 16) ? dx : -dx; // ???
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
            y += (flags & 32) ? dy : -dy; // ???
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
      const(stbtt_uint8) *comp = data + g + 10;
      num_vertices = 0;
      vertices = null;
      while (more) {
         stbtt_uint16 flags, gidx;
         int comp_num_verts = 0, i;
         stbtt_vertex* comp_verts = null, tmp = null;
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
         m = cast(float) std.math.sqrt(mtx[0]*mtx[0] + mtx[1]*mtx[1]);
         n = cast(float) std.math.sqrt(mtx[2]*mtx[2] + mtx[3]*mtx[3]);

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
            tmp = cast(stbtt_vertex*)STBTT_malloc((num_vertices+comp_num_verts)*stbtt_vertex.sizeof, info.userdata);
            if (!tmp) {
               if (vertices) STBTT_free(vertices, info.userdata);
               if (comp_verts) STBTT_free(comp_verts, info.userdata);
               return 0;
            }
            if (num_vertices > 0) core.stdc.string.memcpy(tmp, vertices, num_vertices*stbtt_vertex.sizeof);
            core.stdc.string.memcpy(tmp+num_vertices, comp_verts, comp_num_verts*stbtt_vertex.sizeof);
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

void stbtt_GetGlyphHMetrics(const stbtt_fontinfo *info, int glyph_index, int *advanceWidth, int *leftSideBearing)
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

int  stbtt_GetGlyphKernAdvance(const stbtt_fontinfo *info, int glyph1, int glyph2)
{
   const(stbtt_uint8) *data = info.data + info.kern;
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

int  stbtt_GetCodepointKernAdvance(const stbtt_fontinfo *info, int ch1, int ch2)
{
   if (!info.kern) // if no kerning table, don't waste time looking up both codepoint.glyphs
      return 0;
   return stbtt_GetGlyphKernAdvance(info, stbtt_FindGlyphIndex(info,ch1), stbtt_FindGlyphIndex(info,ch2));
}

void stbtt_GetCodepointHMetrics(const stbtt_fontinfo *info, int codepoint, int *advanceWidth, int *leftSideBearing)
{
   stbtt_GetGlyphHMetrics(info, stbtt_FindGlyphIndex(info,codepoint), advanceWidth, leftSideBearing);
}

void stbtt_GetFontVMetrics(const stbtt_fontinfo *info, int *ascent, int *descent, int *lineGap)
{
   if (ascent ) *ascent  = ttSHORT(info.data+info.hhea + 4);
   if (descent) *descent = ttSHORT(info.data+info.hhea + 6);
   if (lineGap) *lineGap = ttSHORT(info.data+info.hhea + 8);
}

void stbtt_GetFontBoundingBox(const stbtt_fontinfo *info, int *x0, int *y0, int *x1, int *y1)
{
   *x0 = ttSHORT(info.data + info.head + 36);
   *y0 = ttSHORT(info.data + info.head + 38);
   *x1 = ttSHORT(info.data + info.head + 40);
   *y1 = ttSHORT(info.data + info.head + 42);
}

float stbtt_ScaleForPixelHeight(const stbtt_fontinfo *info, float height)
{
   int fheight = ttSHORT(info.data + info.hhea + 4) - ttSHORT(info.data + info.hhea + 6);
   return cast(float) height / fheight;
}

float stbtt_ScaleForMappingEmToPixels(const stbtt_fontinfo *info, float pixels)
{
   int unitsPerEm = ttUSHORT(info.data + info.head + 18);
   return pixels / unitsPerEm;
}

void stbtt_FreeShape(const stbtt_fontinfo *info, stbtt_vertex *v)
{
   STBTT_free(v, info.userdata);
}

//////////////////////////////////////////////////////////////////////////////
//
// antialiasing software rasterizer
//

void stbtt_GetGlyphBitmapBoxSubpixel(const stbtt_fontinfo *font, int glyph, float scale_x, float scale_y,float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   int x0,y0,x1,y1;
   if (!stbtt_GetGlyphBox(font, glyph, &x0,&y0,&x1,&y1))
      x0=y0=x1=y1=0; // e.g. space character
   // now move to integral bboxes (treating pixels as little squares, what pixels get touched)?
   if (ix0) *ix0 =  STBTT_ifloor(x0 * scale_x + shift_x);
   if (iy0) *iy0 = -STBTT_iceil (y1 * scale_y + shift_y);
   if (ix1) *ix1 =  STBTT_iceil (x1 * scale_x + shift_x);
   if (iy1) *iy1 = -STBTT_ifloor(y0 * scale_y + shift_y);
}
void stbtt_GetGlyphBitmapBox(const stbtt_fontinfo *font, int glyph, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   stbtt_GetGlyphBitmapBoxSubpixel(font, glyph, scale_x, scale_y,0.0f,0.0f, ix0, iy0, ix1, iy1);
}

void stbtt_GetCodepointBitmapBoxSubpixel(const stbtt_fontinfo *font, int codepoint, float scale_x, float scale_y, float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   stbtt_GetGlyphBitmapBoxSubpixel(font, stbtt_FindGlyphIndex(font,codepoint), scale_x, scale_y,shift_x,shift_y, ix0,iy0,ix1,iy1);
}

void stbtt_GetCodepointBitmapBox(const stbtt_fontinfo *font, int codepoint, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1)
{
   stbtt_GetCodepointBitmapBoxSubpixel(font, codepoint, scale_x, scale_y,0.0f,0.0f, ix0,iy0,ix1,iy1);
}

struct stbtt__edge {
   float x0,y0, x1,y1;
   int invert;
}

struct stbtt__active_edge
{
   int x,dx;
   float ey;
   stbtt__active_edge *next;
   int valid;
}

enum FIXSHIFT =  10;
enum FIX      =  (1 << FIXSHIFT);
enum FIXMASK  =  (FIX-1);

static stbtt__active_edge *new_active(stbtt__edge *e, int off_x, float start_point, in void *userdata)
{
   stbtt__active_edge *z = cast(stbtt__active_edge *) STBTT_malloc((stbtt__active_edge).sizeof, userdata); // @TODO: make a pool of these!!!
   float dxdy = (e.x1 - e.x0) / (e.y1 - e.y0);
   assert(e.y0 <= start_point);
   if (!z) return z;
   // round dx down to avoid going too far
   if (dxdy < 0)
      z.dx = -STBTT_ifloor(FIX * -dxdy);
   else
      z.dx = STBTT_ifloor(FIX * dxdy);
   z.x = STBTT_ifloor(FIX * (e.x0 + dxdy * (start_point - e.y0)));
   z.x -= off_x * FIX;
   z.ey = e.y1;
   z.next = null;
   z.valid = e.invert ? 1 : -1;
   return z;
}

// note: this routine clips fills that extend off the edges... ideally this
// wouldn't happen, but it could happen if the truetype glyph bounding boxes
// are wrong, or if the user supplies a too-small bitmap
static void stbtt__fill_active_edges(ubyte *scanline, int len, stbtt__active_edge *e, int max_weight)
{
   // non-zero winding fill
   int x0=0, w=0;

   while (e) {
      if (w == 0) {
         // if we're currently at zero, we need to record the edge start point
         x0 = e.x; w += e.valid;
      } else {
         int x1 = e.x; w += e.valid;
         // if we went to zero, we need to draw
         if (w == 0) {
            int i = x0 >> FIXSHIFT;
            int j = x1 >> FIXSHIFT;

            if (i < len && j >= 0) {
               if (i == j) {
                  // x0,x1 are the same pixel, so compute combined coverage
                  scanline[i] = cast(ubyte)(scanline[i] + cast(stbtt_uint8) ((x1 - x0) * max_weight >> FIXSHIFT));
               } else {
                  if (i >= 0) // add antialiasing for x0
                     scanline[i] = cast(ubyte)( scanline[i] + cast(stbtt_uint8) (((FIX - (x0 & FIXMASK)) * max_weight) >> FIXSHIFT));
                  else
                     i = -1; // clip

                  if (j < len) // add antialiasing for x1
                     scanline[j] =  cast(ubyte)(scanline[j] + cast(stbtt_uint8) (((x1 & FIXMASK) * max_weight) >> FIXSHIFT));
                  else
                     j = len; // clip

                  for (++i; i < j; ++i) // fill pixels between x0 and x1
                     scanline[i] =  cast(ubyte)(scanline[i] + cast(stbtt_uint8) max_weight);
               }
            }
         }
      }
      
      e = e.next;
   }
}

static void stbtt__rasterize_sorted_edges(stbtt__bitmap *result, stbtt__edge *e, int n, int vsubsample, int off_x, int off_y, in void *userdata)
{
   stbtt__active_edge *active = null;
   int y,j=0;
   int max_weight = (255 / vsubsample);  // weight per vertical scanline
   int s; // vertical subsample index
   ubyte[512] scanline_data;
   ubyte *scanline;

   if (result.w > 512)
      scanline = cast(ubyte *) STBTT_malloc(result.w, userdata);
   else
      scanline = scanline_data.ptr;

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
               assert(z.valid);
               z.valid = 0;
               STBTT_free(z, userdata);
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
               stbtt__active_edge *z = new_active(e, off_x, scan_y, userdata);
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
                  // at this point, p.next.x is NOT < z.x
                  z.next = p.next;
                  p.next = z;
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

   while (active) {
      stbtt__active_edge *z = active;
      active = active.next;
      STBTT_free(z, userdata);
   }

   if (scanline != scanline_data.ptr)
      STBTT_free(scanline, userdata);
}

extern(C) int stbtt__edge_compare(const void *p, const void *q)
{
   stbtt__edge *a = cast(stbtt__edge *) p;
   stbtt__edge *b = cast(stbtt__edge *) q;

   if (a.y0 < b.y0) return -1;
   if (a.y0 > b.y0) return  1;
   return 0;
}

struct stbtt__point
{
   float x,y;
}

static void stbtt__rasterize(stbtt__bitmap *result, stbtt__point *pts, int *wcount, int windings, float scale_x, float scale_y, float shift_x, float shift_y, int off_x, int off_y, int invert, in void *userdata)
{
   float y_scale_inv = invert ? -scale_y : scale_y;
   stbtt__edge *e;
   int n,i,j,k,m;
   int vsubsample = result.h < 8 ? 15 : 5;
   // vsubsample should divide 255 evenly; otherwise we won't reach full opacity

   // now we have to blow out the windings into explicit edge lists
   n = 0;
   for (i=0; i < windings; ++i)
      n += wcount[i];

   e = cast(stbtt__edge *) STBTT_malloc((*e).sizeof * (n+1), userdata); // add an extra one as a sentinel
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
            a=j;b=k;
         }
         e[n].x0 = p[a].x * scale_x + shift_x;
         e[n].y0 = p[a].y * y_scale_inv * vsubsample + shift_y;
         e[n].x1 = p[b].x * scale_x + shift_x;
         e[n].y1 = p[b].y * y_scale_inv * vsubsample + shift_y;
         ++n;
      }
   }

   // now sort the edges by their highest point (should snap to integer, and then by x)
   STBTT_sort(cast(void*) e, n, (e[0]).sizeof, &stbtt__edge_compare);

   // now, traverse the scanlines and find the intersections on each scanline, use xor winding rule
   stbtt__rasterize_sorted_edges(result, e, n, vsubsample, off_x, off_y, userdata);

   STBTT_free(e, userdata);
}

static void stbtt__add_point(stbtt__point *points, int n, float x, float y)
{
   if (!points) return; // during first pass, it's unallocated
   points[n].x = x;
   points[n].y = y;
}

// tesselate until threshhold p is happy... @TODO warped to compensate for non-linear stretching
static int stbtt__tesselate_curve(stbtt__point *points, int *num_points, float x0, float y0, float x1, float y1, float x2, float y2, float objspace_flatness_squared, int n)
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

// returns number of contours
stbtt__point *stbtt_FlattenCurves(stbtt_vertex *vertices, int num_verts, float objspace_flatness, int **contour_lengths, int *num_contours, in void *userdata)
{
   stbtt__point *points=null;
   int num_points=0;

   float objspace_flatness_squared = objspace_flatness * objspace_flatness;
   int i,n=0,start=0, pass;

   // count how many "moves" there are to get the contour count
   for (i=0; i < num_verts; ++i)
      if (vertices[i].type == STBTT_vmove)
         ++n;

   *num_contours = n;
   if (n == 0) return null;

   *contour_lengths = cast(int *) STBTT_malloc((**contour_lengths).sizeof * n, userdata);

   if (*contour_lengths is null) {
      *num_contours = 0;
      return null;
   }

   // make two passes through the points so we don't need to realloc
   for (pass=0; pass < 2; ++pass) {
      float x=0,y=0;
      if (pass == 1) {
         points = cast(stbtt__point *) STBTT_malloc(num_points * (points[0]).sizeof, userdata);
         if (points == null) goto error;
      }
      num_points = 0;
      n= -1;
      for (i=0; i < num_verts; ++i) {
         switch (vertices[i].type) {
	 default: assert(0);
            case STBTT_vmove:
               // start the next contour
               if (n >= 0)
                  (*contour_lengths)[n] = num_points - start;
               ++n;
               start = num_points;

               x = vertices[i].x; y = vertices[i].y;
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
               x = vertices[i].x; y = vertices[i].y;
               break;
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

void stbtt_Rasterize(stbtt__bitmap *result, float flatness_in_pixels, stbtt_vertex *vertices, int num_verts, float scale_x, float scale_y, float shift_x, float shift_y, int x_off, int y_off, int invert, in void *userdata)
{
   float scale = scale_x > scale_y ? scale_y : scale_x;
   int winding_count;
   int *winding_lengths;
   stbtt__point *windings = stbtt_FlattenCurves(vertices, num_verts, flatness_in_pixels / scale, &winding_lengths, &winding_count, userdata);
   if (windings) {
      stbtt__rasterize(result, windings, winding_lengths, winding_count, scale_x, scale_y, shift_x, shift_y, x_off, y_off, invert, userdata);
      STBTT_free(winding_lengths, userdata);
      STBTT_free(windings, userdata);
   }
}

void stbtt_FreeBitmap(ubyte *bitmap, void *userdata)
{
   STBTT_free(bitmap, userdata);
}

ubyte *stbtt_GetGlyphBitmapSubpixel(const stbtt_fontinfo *info, float scale_x, float scale_y, float shift_x, float shift_y, int glyph, int *width, int *height, int *xoff, int *yoff)
{
   int ix0,iy0,ix1,iy1;
   stbtt__bitmap gbm;
   stbtt_vertex *vertices;   
   int num_verts = stbtt_GetGlyphShape(info, glyph, &vertices);

   if (scale_x == 0) scale_x = scale_y;
   if (scale_y == 0) {
      if (scale_x == 0) return null;
      scale_y = scale_x;
   }

   stbtt_GetGlyphBitmapBox(info, glyph, scale_x, scale_y, &ix0,&iy0,&ix1,&iy1);

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

ubyte *stbtt_GetGlyphBitmap(const stbtt_fontinfo *info, float scale_x, float scale_y, int glyph, int *width, int *height, int *xoff, int *yoff)
{
   return stbtt_GetGlyphBitmapSubpixel(info, scale_x, scale_y, 0.0f, 0.0f, glyph, width, height, xoff, yoff);
}

void stbtt_MakeGlyphBitmapSubpixel(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int glyph)
{
   int ix0,iy0;
   stbtt_vertex *vertices;
   int num_verts = stbtt_GetGlyphShape(info, glyph, &vertices);
   stbtt__bitmap gbm;   

   stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale_x, scale_y, shift_x, shift_y, &ix0,&iy0,null,null);
   gbm.pixels = output;
   gbm.w = out_w;
   gbm.h = out_h;
   gbm.stride = out_stride;

   if (gbm.w && gbm.h)
      stbtt_Rasterize(&gbm, 0.35f, vertices, num_verts, scale_x, scale_y, shift_x, shift_y, ix0,iy0, 1, info.userdata);

   STBTT_free(vertices, info.userdata);
}

void stbtt_MakeGlyphBitmap(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int glyph)
{
   stbtt_MakeGlyphBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, 0.0f,0.0f, glyph);
}

ubyte *stbtt_GetCodepointBitmapSubpixel(const stbtt_fontinfo *info, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint, int *width, int *height, int *xoff, int *yoff)
{
   return stbtt_GetGlyphBitmapSubpixel(info, scale_x, scale_y,shift_x,shift_y, stbtt_FindGlyphIndex(info,codepoint), width,height,xoff,yoff);
}   

void stbtt_MakeCodepointBitmapSubpixel(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint)
{
   stbtt_MakeGlyphBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, shift_x, shift_y, stbtt_FindGlyphIndex(info,codepoint));
}

ubyte *stbtt_GetCodepointBitmap(const stbtt_fontinfo *info, float scale_x, float scale_y, int codepoint, int *width, int *height, int *xoff, int *yoff)
{
   return stbtt_GetCodepointBitmapSubpixel(info, scale_x, scale_y, 0.0f,0.0f, codepoint, width,height,xoff,yoff);
}   

void stbtt_MakeCodepointBitmap(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int codepoint)
{
   stbtt_MakeCodepointBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, 0.0f,0.0f, codepoint);
}

//////////////////////////////////////////////////////////////////////////////
//
// bitmap baking
//
// This is SUPER-CRAPPY packing to keep source code small

extern int stbtt_BakeFontBitmap(const ubyte *data, int offset,  // font location (use offset=0 for plain .ttf)
                                float pixel_height,                     // height of font in pixels
                                ubyte *pixels, int pw, int ph,  // bitmap to be filled in
                                int first_char, int num_chars,          // characters to bake
                                stbtt_bakedchar *chardata)
{
   float scale;
   int x,y,bottom_y, i;
   stbtt_fontinfo f;
   stbtt_InitFont(&f, data, offset);
   STBTT_memset(pixels, 0, pw*ph); // background of 0 around pixels
   x=y=1;
   bottom_y = 1;

   scale = stbtt_ScaleForPixelHeight(&f, pixel_height);

   for (i=0; i < num_chars; ++i) {
      int advance, lsb, x0,y0,x1,y1,gw,gh;
      int g = stbtt_FindGlyphIndex(&f, first_char + i);
      stbtt_GetGlyphHMetrics(&f, g, &advance, &lsb);
      stbtt_GetGlyphBitmapBox(&f, g, scale,scale, &x0,&y0,&x1,&y1);
      gw = x1-x0;
      gh = y1-y0;
      if (x + gw + 1 >= pw)
         { y = bottom_y; x = 1; } // advance to next row
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
      x = x + gw + 2;
      if (y+gh+2 > bottom_y)
         bottom_y = y+gh+2;
   }
   return bottom_y;
}

void stbtt_GetBakedQuad(stbtt_bakedchar *chardata, int pw, int ph, int char_index, float *xpos, float *ypos, stbtt_aligned_quad *q, int opengl_fillrule)
{
   float d3d_bias = opengl_fillrule ? 0 : -0.5f;
   float ipw = 1.0f / pw, iph = 1.0f / ph;
   stbtt_bakedchar *b = chardata + char_index;
   int round_x = STBTT_ifloor((*xpos + b.xoff) + 0.5);
   int round_y = STBTT_ifloor((*ypos + b.yoff) + 0.5);

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
// font name matching -- recommended not to use this
//

// check if a utf8 string contains a prefix which is the utf16 string; if so return length of matching utf8 string
static stbtt_int32 stbtt__CompareUTF8toUTF16_bigendian_prefix(const stbtt_uint8 *s1, stbtt_int32 len1, const(stbtt_uint8) *s2, stbtt_int32 len2) 
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

int stbtt_CompareUTF8toUTF16_bigendian(const char *s1, int len1, const char *s2, int len2) 
{
   return len1 == stbtt__CompareUTF8toUTF16_bigendian_prefix(cast(const stbtt_uint8*) s1, len1,cast (const stbtt_uint8*) s2, len2);
}

// returns results in whatever encoding you request... but note that 2-byte encodings
// will be BIG-ENDIAN... use stbtt_CompareUTF8toUTF16_bigendian() to compare
const(char) *stbtt_GetFontNameString(const stbtt_fontinfo *font, int *length, int platformID, int encodingID, int languageID, int nameID)
{
   stbtt_int32 i,count,stringOffset;
   const(stbtt_uint8) *fc = font.data;
   stbtt_uint32 offset = font.fontstart;
   stbtt_uint32 nm = stbtt__find_table(fc, offset, "name".ptr);
   if (!nm) return null;

   count = ttUSHORT(fc+nm+2);
   stringOffset = nm + ttUSHORT(fc+nm+4);
   for (i=0; i < count; ++i) {
      stbtt_uint32 loc = nm + 6 + 12 * i;
      if (platformID == ttUSHORT(fc+loc+0) && encodingID == ttUSHORT(fc+loc+2)
          && languageID == ttUSHORT(fc+loc+4) && nameID == ttUSHORT(fc+loc+6)) {
         *length = ttUSHORT(fc+loc+8);
         return cast(const(char) *) (fc+stringOffset+ttUSHORT(fc+loc+10));
      }
   }
   return null;
}

static int stbtt__matchpair(stbtt_uint8 *fc, stbtt_uint32 nm, stbtt_uint8 *name, stbtt_int32 nlen, stbtt_int32 target_id, stbtt_int32 next_id)
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
            stbtt_int32 slen = ttUSHORT(fc+loc+8), off = ttUSHORT(fc+loc+10);

            // check if there's a prefix match
            stbtt_int32 matchlen = stbtt__CompareUTF8toUTF16_bigendian_prefix(name, nlen, fc+stringOffset+off,slen);
            if (matchlen >= 0) {
               // check for target_id+1 immediately following, with same encoding & language
               if (i+1 < count && ttUSHORT(fc+loc+12+6) == next_id && ttUSHORT(fc+loc+12) == platform && ttUSHORT(fc+loc+12+2) == encoding && ttUSHORT(fc+loc+12+4) == language) {
                  stbtt_int32 slen2 = ttUSHORT(fc+loc+12+8), off2 = ttUSHORT(fc+loc+12+10);
                  if (slen2 == 0) {
                     if (matchlen == nlen)
                        return 1;
                  } else if (matchlen < nlen && name[matchlen] == ' ') {
                     ++matchlen;
                     if (stbtt_CompareUTF8toUTF16_bigendian(cast(char*) (name+matchlen), nlen-matchlen, cast(char*)(fc+stringOffset+off2),slen2))
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

static int stbtt__matches(stbtt_uint8 *fc, stbtt_uint32 offset, stbtt_uint8 *name, stbtt_int32 flags)
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

int stbtt_FindMatchingFont(const ubyte *font_collection, const char *name_utf8, stbtt_int32 flags)
{
   stbtt_int32 i;
   for (i=0;;++i) {
      stbtt_int32 off = stbtt_GetFontOffsetForIndex(font_collection, i);
      if (off < 0) return off;
      if (stbtt__matches(cast(stbtt_uint8 *) font_collection, off, cast(stbtt_uint8*) name_utf8, flags))
         return off;
   }
}
