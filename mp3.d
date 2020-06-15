/*
 * MPEG Audio Layer III decoder
 * Copyright (c) 2001, 2002 Fabrice Bellard,
 *           (c) 2007 Martin J. Fiedler
 *
 * D conversion by Ketmar // Invisible Vector
 *
 * This file is a stripped-down version of the MPEG Audio decoder from
 * the FFmpeg libavcodec library.
 *
 * FFmpeg and minimp3 are free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg and minimp3 are distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */
/++
	Port of ffmpeg's minimp3 lib to D.

	Authors:
		Code originally by Fabrice Bellard and Martin J. Fiedler.

		Ported to D by ketmar.

		Hacked up by Adam.
	License:
		LGPL 2.1.
+/
module arsd.mp3;

/* code sample:
  auto fi = File(args[1]);

  auto reader = delegate (void[] buf) {
    auto rd = fi.rawRead(buf[]);
    return cast(int)rd.length;
  };

  auto mp3 = new MP3Decoder(reader);

  if (!mp3.valid) {
    writeln("invalid MP3 file!");
    return;
  }

  writeln("sample rate: ", mp3.sampleRate);
  writeln("channels   : ", mp3.channels);

  auto fo = File("z00.raw", "w");
  while (mp3.valid) {
    fo.rawWrite(mp3.frameSamples);
    mp3.decodeNextFrame(reader);
  }
  fo.close();
*/

/* determining mp3 duration with scanning:
  auto fi = File(args.length > 1 ? args[1] : FileName);

  auto info = mp3Scan((void[] buf) {
    auto rd = fi.rawRead(buf[]);
    return cast(uint)rd.length;
  });

  if (!info.valid) {
    writeln("invalid MP3 file!");
  } else {
    writeln("sample rate: ", info.sampleRate);
    writeln("channels   : ", info.channels);
    writeln("samples    : ", info.samples);
    auto seconds = info.samples/info.sampleRate;
    writefln("time: %2s:%02s", seconds/60, seconds%60);
  }
*/


// ////////////////////////////////////////////////////////////////////////// //
alias MP3Decoder = MP3DecoderImpl!true;
alias MP3DecoderNoGC = MP3DecoderImpl!false;


// ////////////////////////////////////////////////////////////////////////// //
// see iv.mp3scan
/+
struct MP3Info {
  uint sampleRate;
  ubyte channels;
  ulong samples;

  @property bool valid () const pure nothrow @safe @nogc { return (sampleRate != 0); }
}


MP3Info mp3Scan(RDG) (scope RDG rdg) if (is(typeof({
  ubyte[2] buf;
  int rd = rdg(buf[]);
}))) {
  MP3Info info;
  bool eofhit;
  ubyte[4096] inbuf;
  enum inbufsize = cast(uint)inbuf.length;
  uint inbufpos, inbufused;
  mp3_context_t* s = cast(mp3_context_t*)libc_calloc(mp3_context_t.sizeof, 1);
  if (s is null) return info;
  scope(exit) libc_free(s);
  bool skipTagCheck;
  int headersCount;

  void readMoreData () {
    if (inbufused-inbufpos < 1441) {
      import core.stdc.string : memmove;
      auto left = inbufused-inbufpos;
      if (inbufpos > 0) memmove(inbuf.ptr, inbuf.ptr+inbufpos, left);
      inbufpos = 0;
      inbufused = left;
      // read more bytes
      left = inbufsize-inbufused;
      int rd = rdg(inbuf[inbufused..inbufused+left]);
      if (rd <= 0) {
        eofhit = true;
      } else {
        inbufused += rd;
      }
    }
  }

  // now skip frames
  while (!eofhit) {
    readMoreData();
    if (eofhit && inbufused-inbufpos < 1024) break;
    auto left = inbufused-inbufpos;
    // check for tags
    if (!skipTagCheck) {
      skipTagCheck = true;
      if (left >= 10) {
        // check for ID3v2
        if (inbuf.ptr[0] == 'I' && inbuf.ptr[1] == 'D' && inbuf.ptr[2] == '3' && inbuf.ptr[3] != 0xff && inbuf.ptr[4] != 0xff &&
            ((inbuf.ptr[6]|inbuf.ptr[7]|inbuf.ptr[8]|inbuf.ptr[9])&0x80) == 0) { // see ID3v2 specs
          // get tag size
          uint sz = (inbuf.ptr[9]|(inbuf.ptr[8]<<7)|(inbuf.ptr[7]<<14)|(inbuf.ptr[6]<<21))+10;
          // skip `sz` bytes, it's a tag
          while (sz > 0 && !eofhit) {
            readMoreData();
            left = inbufused-inbufpos;
            if (left > sz) left = sz;
            inbufpos += left;
            sz -= left;
          }
          if (eofhit) break;
          continue;
        }
      }
    } else {
      if (inbuf.ptr[0] == 'T' && inbuf.ptr[1] == 'A' && inbuf.ptr[2] == 'G') {
        // this may be ID3v1, just skip 128 bytes
        uint sz = 128;
        while (sz > 0 && !eofhit) {
          readMoreData();
          left = inbufused-inbufpos;
          if (left > sz) left = sz;
          inbufpos += left;
          sz -= left;
        }
        if (eofhit) break;
        continue;
      }
    }
    int res = mp3_skip_frame(s, inbuf.ptr+inbufpos, left);
    if (res < 0) {
      // can't decode frame
      if (inbufused-inbufpos < 1024) inbufpos = inbufused; else inbufpos += 1024;
    } else {
      if (headersCount < 6) ++headersCount;
      if (!info.valid) {
        if (s.sample_rate < 1024 || s.sample_rate > 96000) break;
        if (s.nb_channels < 1 || s.nb_channels > 2) break;
        info.sampleRate = s.sample_rate;
        info.channels = cast(ubyte)s.nb_channels;
      }
      info.samples += s.sample_count;
      inbufpos += res;
    }
  }
  //{ import core.stdc.stdio : printf; printf("%d\n", headersCount); }
  if (headersCount < 6) info = info.init;
  return info;
}
+/


// ////////////////////////////////////////////////////////////////////////// //
final class MP3DecoderImpl(bool allowGC) {
public:
  enum MaxSamplesPerFrame = 1152*2;

  // read bytes into the buffer, return number of bytes read or 0 for EOF, -1 on error
  // will never be called with empty buffer, or buffer more than 128KB
  static if (allowGC) {
    alias ReadBufFn = int delegate (void[] buf);
  } else {
    alias ReadBufFn = int delegate (void[] buf) nothrow @nogc;
  }

public:
  static struct mp3_info_t {
    int sample_rate;
    int channels;
    int audio_bytes; // generated amount of audio per frame
  }

private:
  void* dec;
  //ReadBufFn readBuf;
  ubyte* inbuf;
  uint inbufsize; // will allocate enough bytes for one frame
  uint inbufpos, inbufused;
  bool eofhit;
  short[MaxSamplesPerFrame] samples;
  uint scanLeft = 256*1024+16; // how much bytes we should scan (max ID3 size is 256KB)

  static if (allowGC) mixin(ObjectCodeMixin); else mixin("nothrow @nogc: "~ObjectCodeMixin);
}

private enum ObjectCodeMixin = q{
private:
  uint ensureBytes (scope ReadBufFn readBuf, uint size) {
    import core.stdc.string : memmove;
    for (;;) {
      assert(inbufused >= inbufpos);
      uint left = inbufused-inbufpos;
      if (left >= size) return size;
      if (eofhit) return left;
      if (left > 0) {
        if (inbufpos > 0) memmove(inbuf, inbuf+inbufpos, left);
        inbufused = left;
      } else {
        inbufused = 0;
      }
      inbufpos = 0;
      //{ import std.conv : to; assert(size > inbufused, "size="~to!string(size)~"; inbufpos="~to!string(inbufpos)~"; inbufused="~to!string(inbufused)~"; inbufsize="~to!string(inbufsize)); }
      assert(size > inbufused);
      left = size-inbufused;
      assert(left > 0);
      if (inbufsize < inbufused+left) {
        auto np = libc_realloc(inbuf, inbufused+left);
        if (np is null) assert(0, "out of memory"); //FIXME
        inbufsize = inbufused+left;
        inbuf = cast(ubyte*)np;
      }
      auto rd = readBuf(inbuf[inbufused..inbufused+left]);
      if (rd > left) assert(0, "mp3 reader returned too many bytes");
      if (rd <= 0) eofhit = true; else inbufused += rd;
    }
  }

  void removeBytes (uint size) {
    if (size == 0) return;
    if (size > inbufused-inbufpos) {
      //assert(0, "the thing that should not be");
      // we will come here when we are scanning for MP3 frame and no more bytes left
      eofhit = true;
      inbufpos = inbufused;
    } else {
      inbufpos += size;
    }
  }

private:
  mp3_info_t info;
  bool curFrameIsOk;
  bool skipTagCheck;

private:
  bool decodeOneFrame (scope ReadBufFn readBuf, bool first=false) {
    for (;;) {
      if (!eofhit && inbufused-inbufpos < 1441) ensureBytes(readBuf, 64*1024);
      int res, size = -1;

      // check for tags
      if (!skipTagCheck) {
        skipTagCheck = false;
        if (inbufused-inbufpos >= 10) {
          // check for ID3v2
          if (inbuf[inbufpos+0] == 'I' && inbuf[inbufpos+1] == 'D' && inbuf[inbufpos+2] == '3' && inbuf[inbufpos+3] != 0xff && inbuf[inbufpos+4] != 0xff &&
              ((inbuf[inbufpos+6]|inbuf[inbufpos+7]|inbuf[inbufpos+8]|inbuf[inbufpos+9])&0x80) == 0) { // see ID3v2 specs
            // get tag size
            uint sz = (inbuf[inbufpos+9]|(inbuf[inbufpos+8]<<7)|(inbuf[inbufpos+7]<<14)|(inbuf[inbufpos+6]<<21))+10;
            // skip `sz` bytes, it's a tag
            while (sz > 0 && !eofhit) {
              ensureBytes(readBuf, 64*1024);
              auto left = inbufused-inbufpos;
              if (left > sz) left = sz;
              removeBytes(left);
              sz -= left;
            }
            if (eofhit) { curFrameIsOk = false; return false; }
            continue;
          }
        }
      } else {
        if (inbuf[inbufpos+0] == 'T' && inbuf[inbufpos+1] == 'A' && inbuf[inbufpos+2] == 'G') {
          // this may be ID3v1, just skip 128 bytes
          uint sz = 128;
          while (sz > 0 && !eofhit) {
            ensureBytes(readBuf, 64*1024);
            auto left = inbufused-inbufpos;
            if (left > sz) left = sz;
            removeBytes(left);
            sz -= left;
          }
          if (eofhit) { curFrameIsOk = false; return false; }
          continue;
        }
      }

      mp3_context_t* s = cast(mp3_context_t*)dec;
      res = mp3_decode_frame(s, /*cast(int16_t*)out_*/samples.ptr, &size, inbuf+inbufpos, /*bytes*/inbufused-inbufpos);
      if (res < 0) {
        // can't decode frame
        if (scanLeft >= 1024) {
          scanLeft -= 1024;
          removeBytes(1024);
          continue;
        }
        curFrameIsOk = false;
        return false;
      }
      info.audio_bytes = size;
      if (first) {
        info.sample_rate = s.sample_rate;
        info.channels = s.nb_channels;
        if ((info.sample_rate < 1024 || info.sample_rate > 96000) ||
            (info.channels < 1 || info.channels > 2) ||
            (info.audio_bytes < 2 || info.audio_bytes > MaxSamplesPerFrame*2 || info.audio_bytes%2 != 0))
        {
          curFrameIsOk = false;
          return false;
        }
        curFrameIsOk = true;
      } else {
        if ((s.sample_rate < 1024 || s.sample_rate > 96000) ||
            (s.nb_channels < 1 || s.nb_channels > 2) ||
            (size < 2 || size > MaxSamplesPerFrame*2 || size%2 != 0))
        {
          curFrameIsOk = false;
        } else {
          curFrameIsOk = true;
        }
      }
      if (curFrameIsOk) {
        scanLeft = 256*1024+16;
        removeBytes(s.frame_size);
        return /*s.frame_size*/true;
      }
      if (scanLeft >= 1024) {
        scanLeft -= 1024;
        removeBytes(1024);
        continue;
      }
      return false;
    }
  }

public:
  this (scope ReadBufFn reader) {
    static if (allowGC) {
      if (reader is null) throw new Exception("reader is null");
    } else {
      if (reader is null) assert(0, "reader is null");
    }
    //readBuf = reader;
    dec = libc_calloc(mp3_context_t.sizeof, 1);
    if (dec is null) assert(0, "out of memory"); // no, really! ;-)
    //mp3_decode_init(cast(mp3_context_t*)dec);
    if (!decodeOneFrame(reader, true)) close();
  }

  ~this () { close(); }

  void close () {
    if (dec !is null) { libc_free(dec); dec = null; }
    if (inbuf !is null) { libc_free(inbuf); inbuf = null; }
    info.audio_bytes = 0;
  }

  // restart decoding
  void restart (scope ReadBufFn reader) {
    inbufpos = inbufused = 0;
    eofhit = false;
    info.audio_bytes = 0;
    scanLeft = 256*1024+16;
    skipTagCheck = false;
    if (!decodeOneFrame(reader, true)) close();
  }

  // empty read buffers and decode next frame; should be used to sync after seeking in input stream
  void sync (scope ReadBufFn reader) {
    inbufpos = inbufused = 0;
    eofhit = false;
    info.audio_bytes = 0;
    scanLeft = 256*1024+16;
    skipTagCheck = false;
    if (!decodeOneFrame(reader)) close();
  }

  bool decodeNextFrame (scope ReadBufFn reader) {
    if (!valid) return false;
    static if (allowGC) scope(failure) close();
    if (reader is null) return false;
    if (!decodeOneFrame(reader)) {
      close();
      return false;
    }
    return true;
  }

  @property bool valid () const pure nothrow @safe @nogc { return (dec !is null && curFrameIsOk); }
  @property uint sampleRate () const pure nothrow @safe @nogc { return (valid ? info.sample_rate : 0); }
  @property ubyte channels () const pure nothrow @safe @nogc { return (valid ? cast(ubyte)info.channels : 0); }
  @property int samplesInFrame () const pure nothrow @safe @nogc { return (valid ? cast(ubyte)info.audio_bytes : 0); }

  @property short[] frameSamples () nothrow @nogc {
    if (!valid) return null;
    return samples[0..info.audio_bytes/2];
  }
};


// ////////////////////////////////////////////////////////////////////////// //
private:
nothrow @nogc:
import core.stdc.stdlib : libc_calloc = calloc, libc_malloc = malloc, libc_realloc = realloc, libc_free = free;
import core.stdc.string : libc_memcpy = memcpy, libc_memset = memset, libc_memmove = memmove;

import std.math : libc_pow = pow, libc_frexp = frexp, tan, M_PI = PI, sqrt, cos, sin;

/*
void* libc_calloc (usize nmemb, usize count) {
  import core.stdc.stdlib : calloc;
  import core.stdc.stdio : printf;
  printf("calloc(%zu, %zu)\n", nmemb, count);
  return calloc(nmemb, count);
}

void* libc_malloc (usize count) {
  import core.stdc.stdlib : malloc;
  import core.stdc.stdio : printf;
  printf("malloc(%zu)\n", count+1024*1024);
  return malloc(count);
}

void* libc_realloc (void* ptr, usize count) {
  import core.stdc.stdlib : realloc;
  import core.stdc.stdio : printf;
  printf("realloc(%p, %zu)\n", ptr, count);
  return realloc(ptr, count+1024*1024);
}

void libc_free (void* ptr) {
  import core.stdc.stdlib : free;
  import core.stdc.stdio : printf;
  printf("free(%p)\n", ptr);
  return free(ptr);
}
*/

enum MP3_FRAME_SIZE = 1152;
enum MP3_MAX_CODED_FRAME_SIZE = 1792;
enum MP3_MAX_CHANNELS = 2;
enum SBLIMIT = 32;

enum MP3_STEREO = 0;
enum MP3_JSTEREO = 1;
enum MP3_DUAL = 2;
enum MP3_MONO = 3;

enum SAME_HEADER_MASK = (0xffe00000 | (3 << 17) | (0xf << 12) | (3 << 10) | (3 << 19));

enum FRAC_BITS = 15;
enum WFRAC_BITS = 14;

enum OUT_MAX = (32767);
enum OUT_MIN = (-32768);
enum OUT_SHIFT = (WFRAC_BITS + FRAC_BITS - 15);

enum MODE_EXT_MS_STEREO = 2;
enum MODE_EXT_I_STEREO = 1;

enum FRAC_ONE = (1 << FRAC_BITS);
//enum FIX(a)   ((int)((a) * FRAC_ONE))
enum FIXR(double a) = (cast(int)((a) * FRAC_ONE + 0.5));
int FIXRx(double a) { static if (__VERSION__ > 2067) pragma(inline, true); return (cast(int)((a) * FRAC_ONE + 0.5)); }
//enum FRAC_RND(a) (((a) + (FRAC_ONE/2)) >> FRAC_BITS)
enum FIXHR(double a) = (cast(int)((a) * (1L<<32) + 0.5));
int FIXHRx() (double a) { static if (__VERSION__ > 2067) pragma(inline, true); return (cast(int)((a) * (1L<<32) + 0.5)); }

long MULL() (int a, int b) { static if (__VERSION__ > 2067) pragma(inline, true); return ((cast(long)(a) * cast(long)(b)) >> FRAC_BITS); }
long MULH() (int a, int b) { static if (__VERSION__ > 2067) pragma(inline, true); return ((cast(long)(a) * cast(long)(b)) >> 32); }
auto MULS(T) (T ra, T rb) { static if (__VERSION__ > 2067) pragma(inline, true); return ((ra) * (rb)); }

enum ISQRT2 = FIXR!(0.70710678118654752440);

enum HEADER_SIZE = 4;
enum BACKSTEP_SIZE = 512;
enum EXTRABYTES = 24;


// ////////////////////////////////////////////////////////////////////////// //
alias VLC_TYPE = short;
alias VT2 = VLC_TYPE[2];

alias int8_t = byte;
alias int16_t = short;
alias int32_t = int;
alias int64_t = long;

alias uint8_t = ubyte;
alias uint16_t = ushort;
alias uint32_t = uint;
alias uint64_t = ulong;

struct bitstream_t {
  const(ubyte)* buffer, buffer_end;
  int index;
  int size_in_bits;
}

struct vlc_t {
  int bits;
  //VLC_TYPE (*table)[2]; ///< code, bits
  VT2* table;
  int table_size, table_allocated;
}

struct mp3_context_t {
  uint8_t[2*BACKSTEP_SIZE+EXTRABYTES] last_buf;
  int last_buf_size;
  int frame_size;
  uint32_t free_format_next_header;
  int error_protection;
  int sample_rate;
  int sample_rate_index;
  int bit_rate;
  bitstream_t gb;
  bitstream_t in_gb;
  int nb_channels;
  int sample_count;
  int mode;
  int mode_ext;
  int lsf;
  int16_t[512*2][MP3_MAX_CHANNELS] synth_buf;
  int[MP3_MAX_CHANNELS] synth_buf_offset;
  int32_t[SBLIMIT][36][MP3_MAX_CHANNELS] sb_samples;
  int32_t[SBLIMIT*18][MP3_MAX_CHANNELS] mdct_buf;
  int dither_state;
  uint last_header; //&0xffff0c00u;
}

struct granule_t {
  uint8_t scfsi;
  int part2_3_length;
  int big_values;
  int global_gain;
  int scalefac_compress;
  uint8_t block_type;
  uint8_t switch_point;
  int[3] table_select;
  int[3] subblock_gain;
  uint8_t scalefac_scale;
  uint8_t count1table_select;
  int[3] region_size;
  int preflag;
  int short_start, long_end;
  uint8_t[40] scale_factors;
  int32_t[SBLIMIT * 18] sb_hybrid;
}

struct huff_table_t {
  int xsize;
  immutable(uint8_t)* bits;
  immutable(uint16_t)* codes;
}

__gshared vlc_t[16] huff_vlc;
__gshared vlc_t[2] huff_quad_vlc;
__gshared uint16_t[23][9] band_index_long;
enum TABLE_4_3_SIZE = (8191 + 16)*4;
__gshared int8_t* table_4_3_exp;
__gshared uint32_t* table_4_3_value;
__gshared uint32_t[512] exp_table;
__gshared uint32_t[16][512] expval_table;
__gshared int32_t[16][2] is_table;
__gshared int32_t[16][2][2] is_table_lsf;
__gshared int32_t[4][8] csa_table;
__gshared float[4][8] csa_table_float;
__gshared int32_t[36][8] mdct_win;
__gshared int16_t[512] window;


// ////////////////////////////////////////////////////////////////////////// //
static immutable uint16_t[15][2] mp3_bitrate_tab = [
  [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 ],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
];

static immutable uint16_t[3] mp3_freq_tab = [ 44100, 48000, 32000 ];

static immutable int32_t[257] mp3_enwindow = [
     0,    -1,    -1,    -1,    -1,    -1,    -1,    -2,
    -2,    -2,    -2,    -3,    -3,    -4,    -4,    -5,
    -5,    -6,    -7,    -7,    -8,    -9,   -10,   -11,
   -13,   -14,   -16,   -17,   -19,   -21,   -24,   -26,
   -29,   -31,   -35,   -38,   -41,   -45,   -49,   -53,
   -58,   -63,   -68,   -73,   -79,   -85,   -91,   -97,
  -104,  -111,  -117,  -125,  -132,  -139,  -147,  -154,
  -161,  -169,  -176,  -183,  -190,  -196,  -202,  -208,
   213,   218,   222,   225,   227,   228,   228,   227,
   224,   221,   215,   208,   200,   189,   177,   163,
   146,   127,   106,    83,    57,    29,    -2,   -36,
   -72,  -111,  -153,  -197,  -244,  -294,  -347,  -401,
  -459,  -519,  -581,  -645,  -711,  -779,  -848,  -919,
  -991, -1064, -1137, -1210, -1283, -1356, -1428, -1498,
 -1567, -1634, -1698, -1759, -1817, -1870, -1919, -1962,
 -2001, -2032, -2057, -2075, -2085, -2087, -2080, -2063,
  2037,  2000,  1952,  1893,  1822,  1739,  1644,  1535,
  1414,  1280,  1131,   970,   794,   605,   402,   185,
   -45,  -288,  -545,  -814, -1095, -1388, -1692, -2006,
 -2330, -2663, -3004, -3351, -3705, -4063, -4425, -4788,
 -5153, -5517, -5879, -6237, -6589, -6935, -7271, -7597,
 -7910, -8209, -8491, -8755, -8998, -9219, -9416, -9585,
 -9727, -9838, -9916, -9959, -9966, -9935, -9863, -9750,
 -9592, -9389, -9139, -8840, -8492, -8092, -7640, -7134,
  6574,  5959,  5288,  4561,  3776,  2935,  2037,  1082,
    70,  -998, -2122, -3300, -4533, -5818, -7154, -8540,
 -9975,-11455,-12980,-14548,-16155,-17799,-19478,-21189,
-22929,-24694,-26482,-28289,-30112,-31947,-33791,-35640,
-37489,-39336,-41176,-43006,-44821,-46617,-48390,-50137,
-51853,-53534,-55178,-56778,-58333,-59838,-61289,-62684,
-64019,-65290,-66494,-67629,-68692,-69679,-70590,-71420,
-72169,-72835,-73415,-73908,-74313,-74630,-74856,-74992,
 75038,
];

static immutable uint8_t[16][2] slen_table = [
  [ 0, 0, 0, 0, 3, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4 ],
  [ 0, 1, 2, 3, 0, 1, 2, 3, 1, 2, 3, 1, 2, 3, 2, 3 ],
];

static immutable uint8_t[4][3][6] lsf_nsf_table = [
  [ [  6,  5,  5, 5 ], [  9,  9,  9, 9 ], [  6,  9,  9, 9 ] ],
  [ [  6,  5,  7, 3 ], [  9,  9, 12, 6 ], [  6,  9, 12, 6 ] ],
  [ [ 11, 10,  0, 0 ], [ 18, 18,  0, 0 ], [ 15, 18,  0, 0 ] ],
  [ [  7,  7,  7, 0 ], [ 12, 12, 12, 0 ], [  6, 15, 12, 0 ] ],
  [ [  6,  6,  6, 3 ], [ 12,  9,  9, 6 ], [  6, 12,  9, 6 ] ],
  [ [  8,  8,  5, 0 ], [ 15, 12,  9, 0 ], [  6, 18,  9, 0 ] ],
];

static immutable uint16_t[4] mp3_huffcodes_1 = [ 0x0001, 0x0001, 0x0001, 0x0000, ];

static immutable uint8_t[4] mp3_huffbits_1 = [ 1,  3,  2,  3, ];

static immutable uint16_t[9] mp3_huffcodes_2 = [ 0x0001, 0x0002, 0x0001, 0x0003, 0x0001, 0x0001, 0x0003, 0x0002, 0x0000, ];

static immutable uint8_t[9] mp3_huffbits_2 = [ 1,  3,  6,  3,  3,  5,  5,  5,  6, ];

static immutable uint16_t[9] mp3_huffcodes_3 = [ 0x0003, 0x0002, 0x0001, 0x0001, 0x0001, 0x0001, 0x0003, 0x0002, 0x0000, ];

static immutable uint8_t[9] mp3_huffbits_3 = [ 2,  2,  6,  3,  2,  5,  5,  5,  6, ];

static immutable uint16_t[16] mp3_huffcodes_5 = [
 0x0001, 0x0002, 0x0006, 0x0005, 0x0003, 0x0001, 0x0004, 0x0004,
 0x0007, 0x0005, 0x0007, 0x0001, 0x0006, 0x0001, 0x0001, 0x0000,
];

static immutable uint8_t[16] mp3_huffbits_5 = [
  1,  3,  6,  7,  3,  3,  6,  7,
  6,  6,  7,  8,  7,  6,  7,  8,
];

static immutable uint16_t[16] mp3_huffcodes_6 = [
 0x0007, 0x0003, 0x0005, 0x0001, 0x0006, 0x0002, 0x0003, 0x0002,
 0x0005, 0x0004, 0x0004, 0x0001, 0x0003, 0x0003, 0x0002, 0x0000,
];

static immutable uint8_t[16] mp3_huffbits_6 = [
  3,  3,  5,  7,  3,  2,  4,  5,
  4,  4,  5,  6,  6,  5,  6,  7,
];

static immutable uint16_t[36] mp3_huffcodes_7 = [
 0x0001, 0x0002, 0x000a, 0x0013, 0x0010, 0x000a, 0x0003, 0x0003,
 0x0007, 0x000a, 0x0005, 0x0003, 0x000b, 0x0004, 0x000d, 0x0011,
 0x0008, 0x0004, 0x000c, 0x000b, 0x0012, 0x000f, 0x000b, 0x0002,
 0x0007, 0x0006, 0x0009, 0x000e, 0x0003, 0x0001, 0x0006, 0x0004,
 0x0005, 0x0003, 0x0002, 0x0000,
];

static immutable uint8_t[36] mp3_huffbits_7 = [
  1,  3,  6,  8,  8,  9,  3,  4,
  6,  7,  7,  8,  6,  5,  7,  8,
  8,  9,  7,  7,  8,  9,  9,  9,
  7,  7,  8,  9,  9, 10,  8,  8,
  9, 10, 10, 10,
];

static immutable uint16_t[36] mp3_huffcodes_8 = [
 0x0003, 0x0004, 0x0006, 0x0012, 0x000c, 0x0005, 0x0005, 0x0001,
 0x0002, 0x0010, 0x0009, 0x0003, 0x0007, 0x0003, 0x0005, 0x000e,
 0x0007, 0x0003, 0x0013, 0x0011, 0x000f, 0x000d, 0x000a, 0x0004,
 0x000d, 0x0005, 0x0008, 0x000b, 0x0005, 0x0001, 0x000c, 0x0004,
 0x0004, 0x0001, 0x0001, 0x0000,
];

static immutable uint8_t[36] mp3_huffbits_8 = [
  2,  3,  6,  8,  8,  9,  3,  2,
  4,  8,  8,  8,  6,  4,  6,  8,
  8,  9,  8,  8,  8,  9,  9, 10,
  8,  7,  8,  9, 10, 10,  9,  8,
  9,  9, 11, 11,
];

static immutable uint16_t[36] mp3_huffcodes_9 = [
 0x0007, 0x0005, 0x0009, 0x000e, 0x000f, 0x0007, 0x0006, 0x0004,
 0x0005, 0x0005, 0x0006, 0x0007, 0x0007, 0x0006, 0x0008, 0x0008,
 0x0008, 0x0005, 0x000f, 0x0006, 0x0009, 0x000a, 0x0005, 0x0001,
 0x000b, 0x0007, 0x0009, 0x0006, 0x0004, 0x0001, 0x000e, 0x0004,
 0x0006, 0x0002, 0x0006, 0x0000,
];

static immutable uint8_t[36] mp3_huffbits_9 = [
  3,  3,  5,  6,  8,  9,  3,  3,
  4,  5,  6,  8,  4,  4,  5,  6,
  7,  8,  6,  5,  6,  7,  7,  8,
  7,  6,  7,  7,  8,  9,  8,  7,
  8,  8,  9,  9,
];

static immutable uint16_t[64] mp3_huffcodes_10 = [
 0x0001, 0x0002, 0x000a, 0x0017, 0x0023, 0x001e, 0x000c, 0x0011,
 0x0003, 0x0003, 0x0008, 0x000c, 0x0012, 0x0015, 0x000c, 0x0007,
 0x000b, 0x0009, 0x000f, 0x0015, 0x0020, 0x0028, 0x0013, 0x0006,
 0x000e, 0x000d, 0x0016, 0x0022, 0x002e, 0x0017, 0x0012, 0x0007,
 0x0014, 0x0013, 0x0021, 0x002f, 0x001b, 0x0016, 0x0009, 0x0003,
 0x001f, 0x0016, 0x0029, 0x001a, 0x0015, 0x0014, 0x0005, 0x0003,
 0x000e, 0x000d, 0x000a, 0x000b, 0x0010, 0x0006, 0x0005, 0x0001,
 0x0009, 0x0008, 0x0007, 0x0008, 0x0004, 0x0004, 0x0002, 0x0000,
];

static immutable uint8_t[64] mp3_huffbits_10 = [
  1,  3,  6,  8,  9,  9,  9, 10,
  3,  4,  6,  7,  8,  9,  8,  8,
  6,  6,  7,  8,  9, 10,  9,  9,
  7,  7,  8,  9, 10, 10,  9, 10,
  8,  8,  9, 10, 10, 10, 10, 10,
  9,  9, 10, 10, 11, 11, 10, 11,
  8,  8,  9, 10, 10, 10, 11, 11,
  9,  8,  9, 10, 10, 11, 11, 11,
];

static immutable uint16_t[64] mp3_huffcodes_11 = [
 0x0003, 0x0004, 0x000a, 0x0018, 0x0022, 0x0021, 0x0015, 0x000f,
 0x0005, 0x0003, 0x0004, 0x000a, 0x0020, 0x0011, 0x000b, 0x000a,
 0x000b, 0x0007, 0x000d, 0x0012, 0x001e, 0x001f, 0x0014, 0x0005,
 0x0019, 0x000b, 0x0013, 0x003b, 0x001b, 0x0012, 0x000c, 0x0005,
 0x0023, 0x0021, 0x001f, 0x003a, 0x001e, 0x0010, 0x0007, 0x0005,
 0x001c, 0x001a, 0x0020, 0x0013, 0x0011, 0x000f, 0x0008, 0x000e,
 0x000e, 0x000c, 0x0009, 0x000d, 0x000e, 0x0009, 0x0004, 0x0001,
 0x000b, 0x0004, 0x0006, 0x0006, 0x0006, 0x0003, 0x0002, 0x0000,
];

static immutable uint8_t[64] mp3_huffbits_11 = [
  2,  3,  5,  7,  8,  9,  8,  9,
  3,  3,  4,  6,  8,  8,  7,  8,
  5,  5,  6,  7,  8,  9,  8,  8,
  7,  6,  7,  9,  8, 10,  8,  9,
  8,  8,  8,  9,  9, 10,  9, 10,
  8,  8,  9, 10, 10, 11, 10, 11,
  8,  7,  7,  8,  9, 10, 10, 10,
  8,  7,  8,  9, 10, 10, 10, 10,
];

static immutable uint16_t[64] mp3_huffcodes_12 = [
 0x0009, 0x0006, 0x0010, 0x0021, 0x0029, 0x0027, 0x0026, 0x001a,
 0x0007, 0x0005, 0x0006, 0x0009, 0x0017, 0x0010, 0x001a, 0x000b,
 0x0011, 0x0007, 0x000b, 0x000e, 0x0015, 0x001e, 0x000a, 0x0007,
 0x0011, 0x000a, 0x000f, 0x000c, 0x0012, 0x001c, 0x000e, 0x0005,
 0x0020, 0x000d, 0x0016, 0x0013, 0x0012, 0x0010, 0x0009, 0x0005,
 0x0028, 0x0011, 0x001f, 0x001d, 0x0011, 0x000d, 0x0004, 0x0002,
 0x001b, 0x000c, 0x000b, 0x000f, 0x000a, 0x0007, 0x0004, 0x0001,
 0x001b, 0x000c, 0x0008, 0x000c, 0x0006, 0x0003, 0x0001, 0x0000,
];

static immutable uint8_t[64] mp3_huffbits_12 = [
  4,  3,  5,  7,  8,  9,  9,  9,
  3,  3,  4,  5,  7,  7,  8,  8,
  5,  4,  5,  6,  7,  8,  7,  8,
  6,  5,  6,  6,  7,  8,  8,  8,
  7,  6,  7,  7,  8,  8,  8,  9,
  8,  7,  8,  8,  8,  9,  8,  9,
  8,  7,  7,  8,  8,  9,  9, 10,
  9,  8,  8,  9,  9,  9,  9, 10,
];

static immutable uint16_t[256] mp3_huffcodes_13 = [
 0x0001, 0x0005, 0x000e, 0x0015, 0x0022, 0x0033, 0x002e, 0x0047,
 0x002a, 0x0034, 0x0044, 0x0034, 0x0043, 0x002c, 0x002b, 0x0013,
 0x0003, 0x0004, 0x000c, 0x0013, 0x001f, 0x001a, 0x002c, 0x0021,
 0x001f, 0x0018, 0x0020, 0x0018, 0x001f, 0x0023, 0x0016, 0x000e,
 0x000f, 0x000d, 0x0017, 0x0024, 0x003b, 0x0031, 0x004d, 0x0041,
 0x001d, 0x0028, 0x001e, 0x0028, 0x001b, 0x0021, 0x002a, 0x0010,
 0x0016, 0x0014, 0x0025, 0x003d, 0x0038, 0x004f, 0x0049, 0x0040,
 0x002b, 0x004c, 0x0038, 0x0025, 0x001a, 0x001f, 0x0019, 0x000e,
 0x0023, 0x0010, 0x003c, 0x0039, 0x0061, 0x004b, 0x0072, 0x005b,
 0x0036, 0x0049, 0x0037, 0x0029, 0x0030, 0x0035, 0x0017, 0x0018,
 0x003a, 0x001b, 0x0032, 0x0060, 0x004c, 0x0046, 0x005d, 0x0054,
 0x004d, 0x003a, 0x004f, 0x001d, 0x004a, 0x0031, 0x0029, 0x0011,
 0x002f, 0x002d, 0x004e, 0x004a, 0x0073, 0x005e, 0x005a, 0x004f,
 0x0045, 0x0053, 0x0047, 0x0032, 0x003b, 0x0026, 0x0024, 0x000f,
 0x0048, 0x0022, 0x0038, 0x005f, 0x005c, 0x0055, 0x005b, 0x005a,
 0x0056, 0x0049, 0x004d, 0x0041, 0x0033, 0x002c, 0x002b, 0x002a,
 0x002b, 0x0014, 0x001e, 0x002c, 0x0037, 0x004e, 0x0048, 0x0057,
 0x004e, 0x003d, 0x002e, 0x0036, 0x0025, 0x001e, 0x0014, 0x0010,
 0x0035, 0x0019, 0x0029, 0x0025, 0x002c, 0x003b, 0x0036, 0x0051,
 0x0042, 0x004c, 0x0039, 0x0036, 0x0025, 0x0012, 0x0027, 0x000b,
 0x0023, 0x0021, 0x001f, 0x0039, 0x002a, 0x0052, 0x0048, 0x0050,
 0x002f, 0x003a, 0x0037, 0x0015, 0x0016, 0x001a, 0x0026, 0x0016,
 0x0035, 0x0019, 0x0017, 0x0026, 0x0046, 0x003c, 0x0033, 0x0024,
 0x0037, 0x001a, 0x0022, 0x0017, 0x001b, 0x000e, 0x0009, 0x0007,
 0x0022, 0x0020, 0x001c, 0x0027, 0x0031, 0x004b, 0x001e, 0x0034,
 0x0030, 0x0028, 0x0034, 0x001c, 0x0012, 0x0011, 0x0009, 0x0005,
 0x002d, 0x0015, 0x0022, 0x0040, 0x0038, 0x0032, 0x0031, 0x002d,
 0x001f, 0x0013, 0x000c, 0x000f, 0x000a, 0x0007, 0x0006, 0x0003,
 0x0030, 0x0017, 0x0014, 0x0027, 0x0024, 0x0023, 0x0035, 0x0015,
 0x0010, 0x0017, 0x000d, 0x000a, 0x0006, 0x0001, 0x0004, 0x0002,
 0x0010, 0x000f, 0x0011, 0x001b, 0x0019, 0x0014, 0x001d, 0x000b,
 0x0011, 0x000c, 0x0010, 0x0008, 0x0001, 0x0001, 0x0000, 0x0001,
];

static immutable uint8_t[256] mp3_huffbits_13 = [
  1,  4,  6,  7,  8,  9,  9, 10,
  9, 10, 11, 11, 12, 12, 13, 13,
  3,  4,  6,  7,  8,  8,  9,  9,
  9,  9, 10, 10, 11, 12, 12, 12,
  6,  6,  7,  8,  9,  9, 10, 10,
  9, 10, 10, 11, 11, 12, 13, 13,
  7,  7,  8,  9,  9, 10, 10, 10,
 10, 11, 11, 11, 11, 12, 13, 13,
  8,  7,  9,  9, 10, 10, 11, 11,
 10, 11, 11, 12, 12, 13, 13, 14,
  9,  8,  9, 10, 10, 10, 11, 11,
 11, 11, 12, 11, 13, 13, 14, 14,
  9,  9, 10, 10, 11, 11, 11, 11,
 11, 12, 12, 12, 13, 13, 14, 14,
 10,  9, 10, 11, 11, 11, 12, 12,
 12, 12, 13, 13, 13, 14, 16, 16,
  9,  8,  9, 10, 10, 11, 11, 12,
 12, 12, 12, 13, 13, 14, 15, 15,
 10,  9, 10, 10, 11, 11, 11, 13,
 12, 13, 13, 14, 14, 14, 16, 15,
 10, 10, 10, 11, 11, 12, 12, 13,
 12, 13, 14, 13, 14, 15, 16, 17,
 11, 10, 10, 11, 12, 12, 12, 12,
 13, 13, 13, 14, 15, 15, 15, 16,
 11, 11, 11, 12, 12, 13, 12, 13,
 14, 14, 15, 15, 15, 16, 16, 16,
 12, 11, 12, 13, 13, 13, 14, 14,
 14, 14, 14, 15, 16, 15, 16, 16,
 13, 12, 12, 13, 13, 13, 15, 14,
 14, 17, 15, 15, 15, 17, 16, 16,
 12, 12, 13, 14, 14, 14, 15, 14,
 15, 15, 16, 16, 19, 18, 19, 16,
];

static immutable uint16_t[256] mp3_huffcodes_15 = [
 0x0007, 0x000c, 0x0012, 0x0035, 0x002f, 0x004c, 0x007c, 0x006c,
 0x0059, 0x007b, 0x006c, 0x0077, 0x006b, 0x0051, 0x007a, 0x003f,
 0x000d, 0x0005, 0x0010, 0x001b, 0x002e, 0x0024, 0x003d, 0x0033,
 0x002a, 0x0046, 0x0034, 0x0053, 0x0041, 0x0029, 0x003b, 0x0024,
 0x0013, 0x0011, 0x000f, 0x0018, 0x0029, 0x0022, 0x003b, 0x0030,
 0x0028, 0x0040, 0x0032, 0x004e, 0x003e, 0x0050, 0x0038, 0x0021,
 0x001d, 0x001c, 0x0019, 0x002b, 0x0027, 0x003f, 0x0037, 0x005d,
 0x004c, 0x003b, 0x005d, 0x0048, 0x0036, 0x004b, 0x0032, 0x001d,
 0x0034, 0x0016, 0x002a, 0x0028, 0x0043, 0x0039, 0x005f, 0x004f,
 0x0048, 0x0039, 0x0059, 0x0045, 0x0031, 0x0042, 0x002e, 0x001b,
 0x004d, 0x0025, 0x0023, 0x0042, 0x003a, 0x0034, 0x005b, 0x004a,
 0x003e, 0x0030, 0x004f, 0x003f, 0x005a, 0x003e, 0x0028, 0x0026,
 0x007d, 0x0020, 0x003c, 0x0038, 0x0032, 0x005c, 0x004e, 0x0041,
 0x0037, 0x0057, 0x0047, 0x0033, 0x0049, 0x0033, 0x0046, 0x001e,
 0x006d, 0x0035, 0x0031, 0x005e, 0x0058, 0x004b, 0x0042, 0x007a,
 0x005b, 0x0049, 0x0038, 0x002a, 0x0040, 0x002c, 0x0015, 0x0019,
 0x005a, 0x002b, 0x0029, 0x004d, 0x0049, 0x003f, 0x0038, 0x005c,
 0x004d, 0x0042, 0x002f, 0x0043, 0x0030, 0x0035, 0x0024, 0x0014,
 0x0047, 0x0022, 0x0043, 0x003c, 0x003a, 0x0031, 0x0058, 0x004c,
 0x0043, 0x006a, 0x0047, 0x0036, 0x0026, 0x0027, 0x0017, 0x000f,
 0x006d, 0x0035, 0x0033, 0x002f, 0x005a, 0x0052, 0x003a, 0x0039,
 0x0030, 0x0048, 0x0039, 0x0029, 0x0017, 0x001b, 0x003e, 0x0009,
 0x0056, 0x002a, 0x0028, 0x0025, 0x0046, 0x0040, 0x0034, 0x002b,
 0x0046, 0x0037, 0x002a, 0x0019, 0x001d, 0x0012, 0x000b, 0x000b,
 0x0076, 0x0044, 0x001e, 0x0037, 0x0032, 0x002e, 0x004a, 0x0041,
 0x0031, 0x0027, 0x0018, 0x0010, 0x0016, 0x000d, 0x000e, 0x0007,
 0x005b, 0x002c, 0x0027, 0x0026, 0x0022, 0x003f, 0x0034, 0x002d,
 0x001f, 0x0034, 0x001c, 0x0013, 0x000e, 0x0008, 0x0009, 0x0003,
 0x007b, 0x003c, 0x003a, 0x0035, 0x002f, 0x002b, 0x0020, 0x0016,
 0x0025, 0x0018, 0x0011, 0x000c, 0x000f, 0x000a, 0x0002, 0x0001,
 0x0047, 0x0025, 0x0022, 0x001e, 0x001c, 0x0014, 0x0011, 0x001a,
 0x0015, 0x0010, 0x000a, 0x0006, 0x0008, 0x0006, 0x0002, 0x0000,
];

static immutable uint8_t[256] mp3_huffbits_15 = [
  3,  4,  5,  7,  7,  8,  9,  9,
  9, 10, 10, 11, 11, 11, 12, 13,
  4,  3,  5,  6,  7,  7,  8,  8,
  8,  9,  9, 10, 10, 10, 11, 11,
  5,  5,  5,  6,  7,  7,  8,  8,
  8,  9,  9, 10, 10, 11, 11, 11,
  6,  6,  6,  7,  7,  8,  8,  9,
  9,  9, 10, 10, 10, 11, 11, 11,
  7,  6,  7,  7,  8,  8,  9,  9,
  9,  9, 10, 10, 10, 11, 11, 11,
  8,  7,  7,  8,  8,  8,  9,  9,
  9,  9, 10, 10, 11, 11, 11, 12,
  9,  7,  8,  8,  8,  9,  9,  9,
  9, 10, 10, 10, 11, 11, 12, 12,
  9,  8,  8,  9,  9,  9,  9, 10,
 10, 10, 10, 10, 11, 11, 11, 12,
  9,  8,  8,  9,  9,  9,  9, 10,
 10, 10, 10, 11, 11, 12, 12, 12,
  9,  8,  9,  9,  9,  9, 10, 10,
 10, 11, 11, 11, 11, 12, 12, 12,
 10,  9,  9,  9, 10, 10, 10, 10,
 10, 11, 11, 11, 11, 12, 13, 12,
 10,  9,  9,  9, 10, 10, 10, 10,
 11, 11, 11, 11, 12, 12, 12, 13,
 11, 10,  9, 10, 10, 10, 11, 11,
 11, 11, 11, 11, 12, 12, 13, 13,
 11, 10, 10, 10, 10, 11, 11, 11,
 11, 12, 12, 12, 12, 12, 13, 13,
 12, 11, 11, 11, 11, 11, 11, 11,
 12, 12, 12, 12, 13, 13, 12, 13,
 12, 11, 11, 11, 11, 11, 11, 12,
 12, 12, 12, 12, 13, 13, 13, 13,
];

static immutable uint16_t[256] mp3_huffcodes_16 = [
 0x0001, 0x0005, 0x000e, 0x002c, 0x004a, 0x003f, 0x006e, 0x005d,
 0x00ac, 0x0095, 0x008a, 0x00f2, 0x00e1, 0x00c3, 0x0178, 0x0011,
 0x0003, 0x0004, 0x000c, 0x0014, 0x0023, 0x003e, 0x0035, 0x002f,
 0x0053, 0x004b, 0x0044, 0x0077, 0x00c9, 0x006b, 0x00cf, 0x0009,
 0x000f, 0x000d, 0x0017, 0x0026, 0x0043, 0x003a, 0x0067, 0x005a,
 0x00a1, 0x0048, 0x007f, 0x0075, 0x006e, 0x00d1, 0x00ce, 0x0010,
 0x002d, 0x0015, 0x0027, 0x0045, 0x0040, 0x0072, 0x0063, 0x0057,
 0x009e, 0x008c, 0x00fc, 0x00d4, 0x00c7, 0x0183, 0x016d, 0x001a,
 0x004b, 0x0024, 0x0044, 0x0041, 0x0073, 0x0065, 0x00b3, 0x00a4,
 0x009b, 0x0108, 0x00f6, 0x00e2, 0x018b, 0x017e, 0x016a, 0x0009,
 0x0042, 0x001e, 0x003b, 0x0038, 0x0066, 0x00b9, 0x00ad, 0x0109,
 0x008e, 0x00fd, 0x00e8, 0x0190, 0x0184, 0x017a, 0x01bd, 0x0010,
 0x006f, 0x0036, 0x0034, 0x0064, 0x00b8, 0x00b2, 0x00a0, 0x0085,
 0x0101, 0x00f4, 0x00e4, 0x00d9, 0x0181, 0x016e, 0x02cb, 0x000a,
 0x0062, 0x0030, 0x005b, 0x0058, 0x00a5, 0x009d, 0x0094, 0x0105,
 0x00f8, 0x0197, 0x018d, 0x0174, 0x017c, 0x0379, 0x0374, 0x0008,
 0x0055, 0x0054, 0x0051, 0x009f, 0x009c, 0x008f, 0x0104, 0x00f9,
 0x01ab, 0x0191, 0x0188, 0x017f, 0x02d7, 0x02c9, 0x02c4, 0x0007,
 0x009a, 0x004c, 0x0049, 0x008d, 0x0083, 0x0100, 0x00f5, 0x01aa,
 0x0196, 0x018a, 0x0180, 0x02df, 0x0167, 0x02c6, 0x0160, 0x000b,
 0x008b, 0x0081, 0x0043, 0x007d, 0x00f7, 0x00e9, 0x00e5, 0x00db,
 0x0189, 0x02e7, 0x02e1, 0x02d0, 0x0375, 0x0372, 0x01b7, 0x0004,
 0x00f3, 0x0078, 0x0076, 0x0073, 0x00e3, 0x00df, 0x018c, 0x02ea,
 0x02e6, 0x02e0, 0x02d1, 0x02c8, 0x02c2, 0x00df, 0x01b4, 0x0006,
 0x00ca, 0x00e0, 0x00de, 0x00da, 0x00d8, 0x0185, 0x0182, 0x017d,
 0x016c, 0x0378, 0x01bb, 0x02c3, 0x01b8, 0x01b5, 0x06c0, 0x0004,
 0x02eb, 0x00d3, 0x00d2, 0x00d0, 0x0172, 0x017b, 0x02de, 0x02d3,
 0x02ca, 0x06c7, 0x0373, 0x036d, 0x036c, 0x0d83, 0x0361, 0x0002,
 0x0179, 0x0171, 0x0066, 0x00bb, 0x02d6, 0x02d2, 0x0166, 0x02c7,
 0x02c5, 0x0362, 0x06c6, 0x0367, 0x0d82, 0x0366, 0x01b2, 0x0000,
 0x000c, 0x000a, 0x0007, 0x000b, 0x000a, 0x0011, 0x000b, 0x0009,
 0x000d, 0x000c, 0x000a, 0x0007, 0x0005, 0x0003, 0x0001, 0x0003,
];

static immutable uint8_t[256] mp3_huffbits_16 = [
  1,  4,  6,  8,  9,  9, 10, 10,
 11, 11, 11, 12, 12, 12, 13,  9,
  3,  4,  6,  7,  8,  9,  9,  9,
 10, 10, 10, 11, 12, 11, 12,  8,
  6,  6,  7,  8,  9,  9, 10, 10,
 11, 10, 11, 11, 11, 12, 12,  9,
  8,  7,  8,  9,  9, 10, 10, 10,
 11, 11, 12, 12, 12, 13, 13, 10,
  9,  8,  9,  9, 10, 10, 11, 11,
 11, 12, 12, 12, 13, 13, 13,  9,
  9,  8,  9,  9, 10, 11, 11, 12,
 11, 12, 12, 13, 13, 13, 14, 10,
 10,  9,  9, 10, 11, 11, 11, 11,
 12, 12, 12, 12, 13, 13, 14, 10,
 10,  9, 10, 10, 11, 11, 11, 12,
 12, 13, 13, 13, 13, 15, 15, 10,
 10, 10, 10, 11, 11, 11, 12, 12,
 13, 13, 13, 13, 14, 14, 14, 10,
 11, 10, 10, 11, 11, 12, 12, 13,
 13, 13, 13, 14, 13, 14, 13, 11,
 11, 11, 10, 11, 12, 12, 12, 12,
 13, 14, 14, 14, 15, 15, 14, 10,
 12, 11, 11, 11, 12, 12, 13, 14,
 14, 14, 14, 14, 14, 13, 14, 11,
 12, 12, 12, 12, 12, 13, 13, 13,
 13, 15, 14, 14, 14, 14, 16, 11,
 14, 12, 12, 12, 13, 13, 14, 14,
 14, 16, 15, 15, 15, 17, 15, 11,
 13, 13, 11, 12, 14, 14, 13, 14,
 14, 15, 16, 15, 17, 15, 14, 11,
  9,  8,  8,  9,  9, 10, 10, 10,
 11, 11, 11, 11, 11, 11, 11,  8,
];

static immutable uint16_t[256] mp3_huffcodes_24 = [
 0x000f, 0x000d, 0x002e, 0x0050, 0x0092, 0x0106, 0x00f8, 0x01b2,
 0x01aa, 0x029d, 0x028d, 0x0289, 0x026d, 0x0205, 0x0408, 0x0058,
 0x000e, 0x000c, 0x0015, 0x0026, 0x0047, 0x0082, 0x007a, 0x00d8,
 0x00d1, 0x00c6, 0x0147, 0x0159, 0x013f, 0x0129, 0x0117, 0x002a,
 0x002f, 0x0016, 0x0029, 0x004a, 0x0044, 0x0080, 0x0078, 0x00dd,
 0x00cf, 0x00c2, 0x00b6, 0x0154, 0x013b, 0x0127, 0x021d, 0x0012,
 0x0051, 0x0027, 0x004b, 0x0046, 0x0086, 0x007d, 0x0074, 0x00dc,
 0x00cc, 0x00be, 0x00b2, 0x0145, 0x0137, 0x0125, 0x010f, 0x0010,
 0x0093, 0x0048, 0x0045, 0x0087, 0x007f, 0x0076, 0x0070, 0x00d2,
 0x00c8, 0x00bc, 0x0160, 0x0143, 0x0132, 0x011d, 0x021c, 0x000e,
 0x0107, 0x0042, 0x0081, 0x007e, 0x0077, 0x0072, 0x00d6, 0x00ca,
 0x00c0, 0x00b4, 0x0155, 0x013d, 0x012d, 0x0119, 0x0106, 0x000c,
 0x00f9, 0x007b, 0x0079, 0x0075, 0x0071, 0x00d7, 0x00ce, 0x00c3,
 0x00b9, 0x015b, 0x014a, 0x0134, 0x0123, 0x0110, 0x0208, 0x000a,
 0x01b3, 0x0073, 0x006f, 0x006d, 0x00d3, 0x00cb, 0x00c4, 0x00bb,
 0x0161, 0x014c, 0x0139, 0x012a, 0x011b, 0x0213, 0x017d, 0x0011,
 0x01ab, 0x00d4, 0x00d0, 0x00cd, 0x00c9, 0x00c1, 0x00ba, 0x00b1,
 0x00a9, 0x0140, 0x012f, 0x011e, 0x010c, 0x0202, 0x0179, 0x0010,
 0x014f, 0x00c7, 0x00c5, 0x00bf, 0x00bd, 0x00b5, 0x00ae, 0x014d,
 0x0141, 0x0131, 0x0121, 0x0113, 0x0209, 0x017b, 0x0173, 0x000b,
 0x029c, 0x00b8, 0x00b7, 0x00b3, 0x00af, 0x0158, 0x014b, 0x013a,
 0x0130, 0x0122, 0x0115, 0x0212, 0x017f, 0x0175, 0x016e, 0x000a,
 0x028c, 0x015a, 0x00ab, 0x00a8, 0x00a4, 0x013e, 0x0135, 0x012b,
 0x011f, 0x0114, 0x0107, 0x0201, 0x0177, 0x0170, 0x016a, 0x0006,
 0x0288, 0x0142, 0x013c, 0x0138, 0x0133, 0x012e, 0x0124, 0x011c,
 0x010d, 0x0105, 0x0200, 0x0178, 0x0172, 0x016c, 0x0167, 0x0004,
 0x026c, 0x012c, 0x0128, 0x0126, 0x0120, 0x011a, 0x0111, 0x010a,
 0x0203, 0x017c, 0x0176, 0x0171, 0x016d, 0x0169, 0x0165, 0x0002,
 0x0409, 0x0118, 0x0116, 0x0112, 0x010b, 0x0108, 0x0103, 0x017e,
 0x017a, 0x0174, 0x016f, 0x016b, 0x0168, 0x0166, 0x0164, 0x0000,
 0x002b, 0x0014, 0x0013, 0x0011, 0x000f, 0x000d, 0x000b, 0x0009,
 0x0007, 0x0006, 0x0004, 0x0007, 0x0005, 0x0003, 0x0001, 0x0003,
];

static immutable uint8_t[256] mp3_huffbits_24 = [
  4,  4,  6,  7,  8,  9,  9, 10,
 10, 11, 11, 11, 11, 11, 12,  9,
  4,  4,  5,  6,  7,  8,  8,  9,
  9,  9, 10, 10, 10, 10, 10,  8,
  6,  5,  6,  7,  7,  8,  8,  9,
  9,  9,  9, 10, 10, 10, 11,  7,
  7,  6,  7,  7,  8,  8,  8,  9,
  9,  9,  9, 10, 10, 10, 10,  7,
  8,  7,  7,  8,  8,  8,  8,  9,
  9,  9, 10, 10, 10, 10, 11,  7,
  9,  7,  8,  8,  8,  8,  9,  9,
  9,  9, 10, 10, 10, 10, 10,  7,
  9,  8,  8,  8,  8,  9,  9,  9,
  9, 10, 10, 10, 10, 10, 11,  7,
 10,  8,  8,  8,  9,  9,  9,  9,
 10, 10, 10, 10, 10, 11, 11,  8,
 10,  9,  9,  9,  9,  9,  9,  9,
  9, 10, 10, 10, 10, 11, 11,  8,
 10,  9,  9,  9,  9,  9,  9, 10,
 10, 10, 10, 10, 11, 11, 11,  8,
 11,  9,  9,  9,  9, 10, 10, 10,
 10, 10, 10, 11, 11, 11, 11,  8,
 11, 10,  9,  9,  9, 10, 10, 10,
 10, 10, 10, 11, 11, 11, 11,  8,
 11, 10, 10, 10, 10, 10, 10, 10,
 10, 10, 11, 11, 11, 11, 11,  8,
 11, 10, 10, 10, 10, 10, 10, 10,
 11, 11, 11, 11, 11, 11, 11,  8,
 12, 10, 10, 10, 10, 10, 10, 11,
 11, 11, 11, 11, 11, 11, 11,  8,
  8,  7,  7,  7,  7,  7,  7,  7,
  7,  7,  7,  8,  8,  8,  8,  4,
];

static immutable huff_table_t[16] mp3_huff_tables = [
huff_table_t( 1, null, null ),
huff_table_t( 2, mp3_huffbits_1.ptr, mp3_huffcodes_1.ptr ),
huff_table_t( 3, mp3_huffbits_2.ptr, mp3_huffcodes_2.ptr ),
huff_table_t( 3, mp3_huffbits_3.ptr, mp3_huffcodes_3.ptr ),
huff_table_t( 4, mp3_huffbits_5.ptr, mp3_huffcodes_5.ptr ),
huff_table_t( 4, mp3_huffbits_6.ptr, mp3_huffcodes_6.ptr ),
huff_table_t( 6, mp3_huffbits_7.ptr, mp3_huffcodes_7.ptr ),
huff_table_t( 6, mp3_huffbits_8.ptr, mp3_huffcodes_8.ptr ),
huff_table_t( 6, mp3_huffbits_9.ptr, mp3_huffcodes_9.ptr ),
huff_table_t( 8, mp3_huffbits_10.ptr, mp3_huffcodes_10.ptr ),
huff_table_t( 8, mp3_huffbits_11.ptr, mp3_huffcodes_11.ptr ),
huff_table_t( 8, mp3_huffbits_12.ptr, mp3_huffcodes_12.ptr ),
huff_table_t( 16, mp3_huffbits_13.ptr, mp3_huffcodes_13.ptr ),
huff_table_t( 16, mp3_huffbits_15.ptr, mp3_huffcodes_15.ptr ),
huff_table_t( 16, mp3_huffbits_16.ptr, mp3_huffcodes_16.ptr ),
huff_table_t( 16, mp3_huffbits_24.ptr, mp3_huffcodes_24.ptr ),
];

static immutable uint8_t[2][32] mp3_huff_data = [
[ 0, 0 ],
[ 1, 0 ],
[ 2, 0 ],
[ 3, 0 ],
[ 0, 0 ],
[ 4, 0 ],
[ 5, 0 ],
[ 6, 0 ],
[ 7, 0 ],
[ 8, 0 ],
[ 9, 0 ],
[ 10, 0 ],
[ 11, 0 ],
[ 12, 0 ],
[ 0, 0 ],
[ 13, 0 ],
[ 14, 1 ],
[ 14, 2 ],
[ 14, 3 ],
[ 14, 4 ],
[ 14, 6 ],
[ 14, 8 ],
[ 14, 10 ],
[ 14, 13 ],
[ 15, 4 ],
[ 15, 5 ],
[ 15, 6 ],
[ 15, 7 ],
[ 15, 8 ],
[ 15, 9 ],
[ 15, 11 ],
[ 15, 13 ],
];

static immutable uint8_t[16][2] mp3_quad_codes = [
    [  1,  5,  4,  5,  6,  5,  4,  4, 7,  3,  6,  0,  7,  2,  3,  1, ],
    [ 15, 14, 13, 12, 11, 10,  9,  8, 7,  6,  5,  4,  3,  2,  1,  0, ],
];

static immutable uint8_t[16][2] mp3_quad_bits = [
    [ 1, 4, 4, 5, 4, 6, 5, 6, 4, 5, 5, 6, 5, 6, 6, 6, ],
    [ 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, ],
];

static immutable uint8_t[22][9] band_size_long = [
[ 4, 4, 4, 4, 4, 4, 6, 6, 8, 8, 10,
  12, 16, 20, 24, 28, 34, 42, 50, 54, 76, 158, ], /* 44100 */
[ 4, 4, 4, 4, 4, 4, 6, 6, 6, 8, 10,
  12, 16, 18, 22, 28, 34, 40, 46, 54, 54, 192, ], /* 48000 */
[ 4, 4, 4, 4, 4, 4, 6, 6, 8, 10, 12,
  16, 20, 24, 30, 38, 46, 56, 68, 84, 102, 26, ], /* 32000 */
[ 6, 6, 6, 6, 6, 6, 8, 10, 12, 14, 16,
  20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54, ], /* 22050 */
[ 6, 6, 6, 6, 6, 6, 8, 10, 12, 14, 16,
  18, 22, 26, 32, 38, 46, 52, 64, 70, 76, 36, ], /* 24000 */
[ 6, 6, 6, 6, 6, 6, 8, 10, 12, 14, 16,
  20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54, ], /* 16000 */
[ 6, 6, 6, 6, 6, 6, 8, 10, 12, 14, 16,
  20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54, ], /* 11025 */
[ 6, 6, 6, 6, 6, 6, 8, 10, 12, 14, 16,
  20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54, ], /* 12000 */
[ 12, 12, 12, 12, 12, 12, 16, 20, 24, 28, 32,
  40, 48, 56, 64, 76, 90, 2, 2, 2, 2, 2, ], /* 8000 */
];

static immutable uint8_t[13][9] band_size_short = [
[ 4, 4, 4, 4, 6, 8, 10, 12, 14, 18, 22, 30, 56, ], /* 44100 */
[ 4, 4, 4, 4, 6, 6, 10, 12, 14, 16, 20, 26, 66, ], /* 48000 */
[ 4, 4, 4, 4, 6, 8, 12, 16, 20, 26, 34, 42, 12, ], /* 32000 */
[ 4, 4, 4, 6, 6, 8, 10, 14, 18, 26, 32, 42, 18, ], /* 22050 */
[ 4, 4, 4, 6, 8, 10, 12, 14, 18, 24, 32, 44, 12, ], /* 24000 */
[ 4, 4, 4, 6, 8, 10, 12, 14, 18, 24, 30, 40, 18, ], /* 16000 */
[ 4, 4, 4, 6, 8, 10, 12, 14, 18, 24, 30, 40, 18, ], /* 11025 */
[ 4, 4, 4, 6, 8, 10, 12, 14, 18, 24, 30, 40, 18, ], /* 12000 */
[ 8, 8, 8, 12, 16, 20, 24, 28, 36, 2, 2, 2, 26, ], /* 8000 */
];

static immutable uint8_t[22][2] mp3_pretab = [
    [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ],
    [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 3, 2, 0 ],
];

static immutable float[8] ci_table = [
    -0.6f, -0.535f, -0.33f, -0.185f, -0.095f, -0.041f, -0.0142f, -0.0037f,
];

enum C1 = FIXHR!(0.98480775301220805936/2);
enum C2 = FIXHR!(0.93969262078590838405/2);
enum C3 = FIXHR!(0.86602540378443864676/2);
enum C4 = FIXHR!(0.76604444311897803520/2);
enum C5 = FIXHR!(0.64278760968653932632/2);
enum C6 = FIXHR!(0.5/2);
enum C7 = FIXHR!(0.34202014332566873304/2);
enum C8 = FIXHR!(0.17364817766693034885/2);

static immutable int[9] icos36 = [
    FIXR!(0.50190991877167369479),
    FIXR!(0.51763809020504152469), //0
    FIXR!(0.55168895948124587824),
    FIXR!(0.61038729438072803416),
    FIXR!(0.70710678118654752439), //1
    FIXR!(0.87172339781054900991),
    FIXR!(1.18310079157624925896),
    FIXR!(1.93185165257813657349), //2
    FIXR!(5.73685662283492756461),
];

static immutable int[9] icos36h = [
    FIXHR!(0.50190991877167369479/2),
    FIXHR!(0.51763809020504152469/2), //0
    FIXHR!(0.55168895948124587824/2),
    FIXHR!(0.61038729438072803416/2),
    FIXHR!(0.70710678118654752439/2), //1
    FIXHR!(0.87172339781054900991/2),
    FIXHR!(1.18310079157624925896/4),
    FIXHR!(1.93185165257813657349/4), //2
    //FIXHR!(5.73685662283492756461),
];

////////////////////////////////////////////////////////////////////////////////

int unaligned32_be (const(uint8_t)* p) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  return (((p[0]<<8) | p[1])<<16) | (p[2]<<8) | (p[3]);
}

enum MIN_CACHE_BITS = 25;

enum NEG_SSR32(string a, string s) = "((cast( int32_t)("~a~"))>>(32-("~s~")))";
enum NEG_USR32(string a, string s) = "((cast(uint32_t)("~a~"))>>(32-("~s~")))";

enum OPEN_READER(string name, string gb) =
  "int "~name~"_index = ("~gb~").index;\n"~
  "int "~name~"_cache = 0;\n";

enum CLOSE_READER(string name, string gb) = "("~gb~").index = "~name~"_index;";

enum UPDATE_CACHE(string name, string gb) = name~"_cache = unaligned32_be(&(("~gb~").buffer["~name~"_index>>3])) << ("~name~"_index&0x07);";

enum SKIP_CACHE(string name, string gb, string num) = name~"_cache <<= ("~num~");";

enum SKIP_COUNTER(string name, string gb, string num) = name~"_index += ("~num~");";

enum SKIP_BITS(string name, string gb, string num) = "{"~SKIP_CACHE!(name, gb, num)~SKIP_COUNTER!(name, gb, num)~"}";

enum LAST_SKIP_BITS(string name, string gb, string num) = SKIP_COUNTER!(name, gb, num);
enum LAST_SKIP_CACHE(string name, string gb, string num) = "{}";

enum SHOW_UBITS(string name, string gb, string num) = NEG_USR32!(name~"_cache", num);

enum SHOW_SBITS(string name, string gb, string num) = NEG_SSR32(name~"_cache", num);

enum GET_CACHE(string name, string gb) = "(cast(uint32_t)"~name~"_cache)";

int get_bits_count() (const(bitstream_t)* s) { static if (__VERSION__ > 2067) pragma(inline, true); return s.index; }

void skip_bits_long (bitstream_t* s, int n) { static if (__VERSION__ > 2067) pragma(inline, true); s.index += n; }
//#define skip_bits skip_bits_long
alias skip_bits = skip_bits_long;

void init_get_bits (bitstream_t* s, const(uint8_t)* buffer, int bit_size) {
  int buffer_size = (bit_size+7)>>3;
  if (buffer_size < 0 || bit_size < 0) {
    buffer_size = bit_size = 0;
    buffer = null;
  }
  s.buffer = buffer;
  s.size_in_bits = bit_size;
  s.buffer_end = buffer + buffer_size;
  s.index = 0;
}

uint get_bits (bitstream_t* s, int n){
  int tmp;
  mixin(OPEN_READER!("re", "s"));
  mixin(UPDATE_CACHE!("re", "s"));
  tmp = mixin(SHOW_UBITS!("re", "s", "n"));
  mixin(LAST_SKIP_BITS!("re", "s", "n"));
  mixin(CLOSE_READER!("re", "s"));
  return tmp;
}

int get_bitsz (bitstream_t* s, int n) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  return (n == 0 ? 0 : get_bits(s, n));
}

uint get_bits1 (bitstream_t* s) {
  int index = s.index;
  uint8_t result = s.buffer[index>>3];
  result <<= (index&0x07);
  result >>= 8 - 1;
  ++index;
  s.index = index;
  return result;
}

void align_get_bits (bitstream_t* s) {
  int n = (-get_bits_count(s)) & 7;
  if (n) skip_bits(s, n);
}

enum GET_DATA(string v, string table, string i, string wrap, string size) =
"{\n"~
"  const(uint8_t)* ptr = cast(const(uint8_t)*)"~table~"+"~i~"*"~wrap~";\n"~
"  switch ("~size~") {\n"~
"    case 1: "~v~" = *cast(const(uint8_t)*)ptr; break;\n"~
"    case 2: "~v~" = *cast(const(uint16_t)*)ptr; break;\n"~
"    default: "~v~" = *cast(const(uint32_t)*)ptr; break;\n"~
"  }\n"~
"}\n"~
"";

int alloc_table (vlc_t* vlc, int size) {
  int index;
  index = vlc.table_size;
  vlc.table_size += size;
  if (vlc.table_size > vlc.table_allocated) {
    vlc.table_allocated += (1 << vlc.bits);
    vlc.table = cast(VT2*)libc_realloc(vlc.table, VT2.sizeof * vlc.table_allocated);
    if (!vlc.table) return -1;
  }
  return index;
}


int build_table (
  vlc_t* vlc, int table_nb_bits,
  int nb_codes,
  const(void)* bits, int bits_wrap, int bits_size,
  const(void)* codes, int codes_wrap, int codes_size,
  uint32_t code_prefix, int n_prefix
) {
  int i, j, k, n, table_size, table_index, nb, n1, index, code_prefix2;
  uint32_t code;
  //VLC_TYPE (*table)[2];
  VT2* table;

  table_size = 1 << table_nb_bits;
  table_index = alloc_table(vlc, table_size);
  if (table_index < 0) return -1;
  table = &vlc.table[table_index];

  for (i = 0; i < table_size; i++) {
    table[i][1] = 0; //bits
    table[i][0] = -1; //codes
  }

  for (i = 0; i < nb_codes; i++) {
    mixin(GET_DATA!("n", "bits", "i", "bits_wrap", "bits_size"));
    mixin(GET_DATA!("code", "codes", "i", "codes_wrap", "codes_size"));
    if (n <= 0) continue;
    n -= n_prefix;
    code_prefix2 = code >> n;
    if (n > 0 && code_prefix2 == code_prefix) {
      if (n <= table_nb_bits) {
        j = (code << (table_nb_bits - n)) & (table_size - 1);
        nb = 1 << (table_nb_bits - n);
        for(k=0;k<nb;k++) {
          if (table[j][1] /*bits*/ != 0) {
              return -1;
          }
          table[j][1] = cast(short)n; //bits
          table[j][0] = cast(short)i; //code
          j++;
        }
      } else {
        n -= table_nb_bits;
        j = (code >> n) & ((1 << table_nb_bits) - 1);
        n1 = -cast(int)table[j][1]; //bits
        if (n > n1)
            n1 = n;
        table[j][1] = cast(short)(-n1); //bits
      }
    }
  }
  for(i=0;i<table_size;i++) {
      n = table[i][1]; //bits
      if (n < 0) {
          n = -n;
          if (n > table_nb_bits) {
              n = table_nb_bits;
              table[i][1] = cast(short)(-n); //bits
          }
          index = build_table(vlc, n, nb_codes,
                              bits, bits_wrap, bits_size,
                              codes, codes_wrap, codes_size,
                              (code_prefix << table_nb_bits) | i,
                              n_prefix + table_nb_bits);
          if (index < 0)
              return -1;
          table = &vlc.table[table_index];
          table[i][0] = cast(short)index; //code
      }
  }
  return table_index;
}

int init_vlc(
    vlc_t *vlc, int nb_bits, int nb_codes,
    const void *bits, int bits_wrap, int bits_size,
    const void *codes, int codes_wrap, int codes_size
) {
    vlc.bits = nb_bits;
    if (build_table(vlc, nb_bits, nb_codes,
                    bits, bits_wrap, bits_size,
                    codes, codes_wrap, codes_size,
                    0, 0) < 0) {
        libc_free(vlc.table);
        return -1;
    }
    return 0;
}

enum GET_VLC(string code, string name, string gb, string table, string bits, string max_depth) =
"{\n"~
"    int n, index, nb_bits;\n"~
"\n"~
"    index= "~SHOW_UBITS!(name, gb, bits)~";\n"~
"    "~code~" = "~table~"[index][0];\n"~
"    n    = "~table~"[index][1];\n"~
"\n"~
"    if ("~max_depth~" > 1 && n < 0){\n"~
"        "~LAST_SKIP_BITS!(name, gb, bits)~"\n"~
"        "~UPDATE_CACHE!(name, gb)~"\n"~
"\n"~
"        nb_bits = -n;\n"~
"\n"~
"        index= "~SHOW_UBITS!(name, gb, "nb_bits")~" + "~code~";\n"~
"        "~code~" = "~table~"[index][0];\n"~
"        n    = "~table~"[index][1];\n"~
"        if ("~max_depth~" > 2 && n < 0){\n"~
"            "~LAST_SKIP_BITS!(name, gb, "nb_bits")~"\n"~
"            "~UPDATE_CACHE!(name, gb)~"\n"~
"\n"~
"            nb_bits = -n;\n"~
"\n"~
"            index= "~SHOW_UBITS!(name, gb, "nb_bits")~" + "~code~";\n"~
"            "~code~" = "~table~"[index][0];\n"~
"            n    = "~table~"[index][1];\n"~
"        }\n"~
"    }\n"~
"    "~SKIP_BITS!(name, gb, "n")~"\n"~
"}\n"~
"";

int get_vlc2(bitstream_t *s, VT2* table, int bits, int max_depth) {
  int code;

  mixin(OPEN_READER!("re", "s"));
  mixin(UPDATE_CACHE!("re", "s"));

  mixin(GET_VLC!("code", "re", "s", "table", "bits", "max_depth"));

  mixin(CLOSE_READER!("re", "s"));
  return code;
}

void switch_buffer (mp3_context_t *s, int *pos, int *end_pos, int *end_pos2) {
    if(s.in_gb.buffer && *pos >= s.gb.size_in_bits){
        s.gb= s.in_gb;
        s.in_gb.buffer=null;
        skip_bits_long(&s.gb, *pos - *end_pos);
        *end_pos2=
        *end_pos= *end_pos2 + get_bits_count(&s.gb) - *pos;
        *pos= get_bits_count(&s.gb);
    }
}


// ////////////////////////////////////////////////////////////////////////// //
int mp3_check_header(uint32_t header){
  //pragma(inline, true);
  /* header */
  if ((header & 0xffe00000) != 0xffe00000) return -1;
  /* layer check */
  if ((header & (3<<17)) != (1 << 17)) return -1;
  /* bit rate */
  if ((header & (0xf<<12)) == 0xf<<12) return -1;
  /* frequency */
  if ((header & (3<<10)) == 3<<10) return -1;
  return 0;
}


void lsf_sf_expand (int *slen, int sf, int n1, int n2, int n3) {
    if (n3) {
        slen[3] = sf % n3;
        sf /= n3;
    } else {
        slen[3] = 0;
    }
    if (n2) {
        slen[2] = sf % n2;
        sf /= n2;
    } else {
        slen[2] = 0;
    }
    slen[1] = sf % n1;
    sf /= n1;
    slen[0] = sf;
}

int l3_unscale(int value, int exponent)
{
    uint m;
    int e;

    e = table_4_3_exp  [4*value + (exponent&3)];
    m = table_4_3_value[4*value + (exponent&3)];
    e -= (exponent >> 2);
    if (e > 31)
        return 0;
    m = (m + (1 << (e-1))) >> e;

    return m;
}

int round_sample(int *sum) {
    int sum1;
    sum1 = (*sum) >> OUT_SHIFT;
    *sum &= (1<<OUT_SHIFT)-1;
    if (sum1 < OUT_MIN)
        sum1 = OUT_MIN;
    else if (sum1 > OUT_MAX)
        sum1 = OUT_MAX;
    return sum1;
}

void exponents_from_scale_factors (mp3_context_t *s, granule_t *g, int16_t *exponents) {
    const(uint8_t)* bstab, pretab;
    int len, i, j, k, l, v0, shift, gain;
    int[3] gains;
    int16_t *exp_ptr;

    exp_ptr = exponents;
    gain = g.global_gain - 210;
    shift = g.scalefac_scale + 1;

    bstab = band_size_long[s.sample_rate_index].ptr;
    pretab = mp3_pretab[g.preflag].ptr;
    for(i=0;i<g.long_end;i++) {
        v0 = gain - ((g.scale_factors[i] + pretab[i]) << shift) + 400;
        len = bstab[i];
        for(j=len;j>0;j--)
            *exp_ptr++ = cast(short)v0;
    }

    if (g.short_start < 13) {
        bstab = band_size_short[s.sample_rate_index].ptr;
        gains[0] = gain - (g.subblock_gain[0] << 3);
        gains[1] = gain - (g.subblock_gain[1] << 3);
        gains[2] = gain - (g.subblock_gain[2] << 3);
        k = g.long_end;
        for(i=g.short_start;i<13;i++) {
            len = bstab[i];
            for(l=0;l<3;l++) {
                v0 = gains[l] - (g.scale_factors[k++] << shift) + 400;
                for(j=len;j>0;j--)
                *exp_ptr++ = cast(short)v0;
            }
        }
    }
}

void reorder_block(mp3_context_t *s, granule_t *g)
{
    int i, j, len;
    int32_t* ptr, dst, ptr1;
    int32_t[576] tmp;

    if (g.block_type != 2)
        return;

    if (g.switch_point) {
        if (s.sample_rate_index != 8) {
            ptr = g.sb_hybrid.ptr + 36;
        } else {
            ptr = g.sb_hybrid.ptr + 48;
        }
    } else {
        ptr = g.sb_hybrid.ptr;
    }

    for(i=g.short_start;i<13;i++) {
        len = band_size_short[s.sample_rate_index][i];
        ptr1 = ptr;
        dst = tmp.ptr;
        for(j=len;j>0;j--) {
            *dst++ = ptr[0*len];
            *dst++ = ptr[1*len];
            *dst++ = ptr[2*len];
            ptr++;
        }
        ptr+=2*len;
        libc_memcpy(ptr1, tmp.ptr, len * 3 * (*ptr1).sizeof);
    }
}

void compute_antialias(mp3_context_t *s, granule_t *g) {
  enum INT_AA(string j) =
    "tmp0 = ptr[-1-"~j~"];\n"~
    "tmp1 = ptr[   "~j~"];\n"~
    "tmp2= cast(int)MULH(tmp0 + tmp1, csa[0+4*"~j~"]);\n"~
    "ptr[-1-"~j~"] = cast(int)(4*(tmp2 - MULH(tmp1, csa[2+4*"~j~"])));\n"~
    "ptr[   "~j~"] = cast(int)(4*(tmp2 + MULH(tmp0, csa[3+4*"~j~"])));\n";

    int32_t* ptr, csa;
    int n, i;

    /* we antialias only "long" bands */
    if (g.block_type == 2) {
        if (!g.switch_point)
            return;
        /* XXX: check this for 8000Hz case */
        n = 1;
    } else {
        n = SBLIMIT - 1;
    }

    ptr = g.sb_hybrid.ptr + 18;
    for(i = n;i > 0;i--) {
        int tmp0, tmp1, tmp2;
        csa = &csa_table[0][0];

        mixin(INT_AA!("0"));
        mixin(INT_AA!("1"));
        mixin(INT_AA!("2"));
        mixin(INT_AA!("3"));
        mixin(INT_AA!("4"));
        mixin(INT_AA!("5"));
        mixin(INT_AA!("6"));
        mixin(INT_AA!("7"));

        ptr += 18;
    }
}

void compute_stereo (mp3_context_t *s, granule_t *g0, granule_t *g1) {
    int i, j, k, l;
    int32_t v1, v2;
    int sf_max, tmp0, tmp1, sf, len, non_zero_found;
    int32_t[16]* is_tab;
    int32_t* tab0, tab1;
    int[3] non_zero_found_short;

    if (s.mode_ext & MODE_EXT_I_STEREO) {
        if (!s.lsf) {
            is_tab = is_table.ptr;
            sf_max = 7;
        } else {
            is_tab = is_table_lsf[g1.scalefac_compress & 1].ptr;
            sf_max = 16;
        }

        tab0 = g0.sb_hybrid.ptr + 576;
        tab1 = g1.sb_hybrid.ptr + 576;

        non_zero_found_short[0] = 0;
        non_zero_found_short[1] = 0;
        non_zero_found_short[2] = 0;
        k = (13 - g1.short_start) * 3 + g1.long_end - 3;
        for(i = 12;i >= g1.short_start;i--) {
            /* for last band, use previous scale factor */
            if (i != 11)
                k -= 3;
            len = band_size_short[s.sample_rate_index][i];
            for(l=2;l>=0;l--) {
                tab0 -= len;
                tab1 -= len;
                if (!non_zero_found_short[l]) {
                    /* test if non zero band. if so, stop doing i-stereo */
                    for(j=0;j<len;j++) {
                        if (tab1[j] != 0) {
                            non_zero_found_short[l] = 1;
                            goto found1;
                        }
                    }
                    sf = g1.scale_factors[k + l];
                    if (sf >= sf_max)
                        goto found1;

                    v1 = is_tab[0][sf];
                    v2 = is_tab[1][sf];
                    for(j=0;j<len;j++) {
                        tmp0 = tab0[j];
                        tab0[j] = cast(int)MULL(tmp0, v1);
                        tab1[j] = cast(int)MULL(tmp0, v2);
                    }
                } else {
                found1:
                    if (s.mode_ext & MODE_EXT_MS_STEREO) {
                        /* lower part of the spectrum : do ms stereo
                           if enabled */
                        for(j=0;j<len;j++) {
                            tmp0 = tab0[j];
                            tmp1 = tab1[j];
                            tab0[j] = cast(int)MULL(tmp0 + tmp1, ISQRT2);
                            tab1[j] = cast(int)MULL(tmp0 - tmp1, ISQRT2);
                        }
                    }
                }
            }
        }

        non_zero_found = non_zero_found_short[0] |
            non_zero_found_short[1] |
            non_zero_found_short[2];

        for(i = g1.long_end - 1;i >= 0;i--) {
            len = band_size_long[s.sample_rate_index][i];
            tab0 -= len;
            tab1 -= len;
            /* test if non zero band. if so, stop doing i-stereo */
            if (!non_zero_found) {
                for(j=0;j<len;j++) {
                    if (tab1[j] != 0) {
                        non_zero_found = 1;
                        goto found2;
                    }
                }
                /* for last band, use previous scale factor */
                k = (i == 21) ? 20 : i;
                sf = g1.scale_factors[k];
                if (sf >= sf_max)
                    goto found2;
                v1 = is_tab[0][sf];
                v2 = is_tab[1][sf];
                for(j=0;j<len;j++) {
                    tmp0 = tab0[j];
                    tab0[j] = cast(int)MULL(tmp0, v1);
                    tab1[j] = cast(int)MULL(tmp0, v2);
                }
            } else {
            found2:
                if (s.mode_ext & MODE_EXT_MS_STEREO) {
                    /* lower part of the spectrum : do ms stereo
                       if enabled */
                    for(j=0;j<len;j++) {
                        tmp0 = tab0[j];
                        tmp1 = tab1[j];
                        tab0[j] = cast(int)MULL(tmp0 + tmp1, ISQRT2);
                        tab1[j] = cast(int)MULL(tmp0 - tmp1, ISQRT2);
                    }
                }
            }
        }
    } else if (s.mode_ext & MODE_EXT_MS_STEREO) {
        /* ms stereo ONLY */
        /* NOTE: the 1/sqrt(2) normalization factor is included in the
           global gain */
        tab0 = g0.sb_hybrid.ptr;
        tab1 = g1.sb_hybrid.ptr;
        for(i=0;i<576;i++) {
            tmp0 = tab0[i];
            tmp1 = tab1[i];
            tab0[i] = tmp0 + tmp1;
            tab1[i] = tmp0 - tmp1;
        }
    }
}

int huffman_decode (mp3_context_t *s, granule_t *g, int16_t *exponents, int end_pos2) {
    int s_index;
    int i;
    int last_pos, bits_left;
    vlc_t* vlc;
    int end_pos = s.gb.size_in_bits;
    if (end_pos2 < end_pos) end_pos = end_pos2;

    /* low frequencies (called big values) */
    s_index = 0;
    for(i=0;i<3;i++) {
        int j, k, l, linbits;
        j = g.region_size[i];
        if (j == 0)
            continue;
        /* select vlc table */
        k = g.table_select[i];
        l = mp3_huff_data[k][0];
        linbits = mp3_huff_data[k][1];
        vlc = &huff_vlc[l];

        if(!l){
            libc_memset(&g.sb_hybrid[s_index], 0, (g.sb_hybrid[0]).sizeof*2*j);
            s_index += 2*j;
            continue;
        }

        /* read huffcode and compute each couple */
        for(;j>0;j--) {
            int exponent, x, y, v;
            int pos= get_bits_count(&s.gb);

            if (pos >= end_pos){
                switch_buffer(s, &pos, &end_pos, &end_pos2);
                if(pos >= end_pos)
                    break;
            }
            y = get_vlc2(&s.gb, vlc.table, 7, 3);

            if(!y){
                g.sb_hybrid[s_index  ] =
                g.sb_hybrid[s_index+1] = 0;
                s_index += 2;
                continue;
            }

            exponent= exponents[s_index];

            if(y&16){
                x = y >> 5;
                y = y & 0x0f;
                if (x < 15){
                    v = expval_table[ exponent ][ x ];
                }else{
                    x += get_bitsz(&s.gb, linbits);
                    v = l3_unscale(x, exponent);
                }
                if (get_bits1(&s.gb))
                    v = -v;
                g.sb_hybrid[s_index] = v;
                if (y < 15){
                    v = expval_table[ exponent ][ y ];
                }else{
                    y += get_bitsz(&s.gb, linbits);
                    v = l3_unscale(y, exponent);
                }
                if (get_bits1(&s.gb))
                    v = -v;
                g.sb_hybrid[s_index+1] = v;
            }else{
                x = y >> 5;
                y = y & 0x0f;
                x += y;
                if (x < 15){
                    v = expval_table[ exponent ][ x ];
                }else{
                    x += get_bitsz(&s.gb, linbits);
                    v = l3_unscale(x, exponent);
                }
                if (get_bits1(&s.gb))
                    v = -v;
                g.sb_hybrid[s_index+!!y] = v;
                g.sb_hybrid[s_index+ !y] = 0;
            }
            s_index+=2;
        }
    }

    /* high frequencies */
    vlc = &huff_quad_vlc[g.count1table_select];
    last_pos=0;
    while (s_index <= 572) {
        int pos, code;
        pos = get_bits_count(&s.gb);
        if (pos >= end_pos) {
            if (pos > end_pos2 && last_pos){
                /* some encoders generate an incorrect size for this
                   part. We must go back into the data */
                s_index -= 4;
                skip_bits_long(&s.gb, last_pos - pos);
                break;
            }
            switch_buffer(s, &pos, &end_pos, &end_pos2);
            if(pos >= end_pos)
                break;
        }
        last_pos= pos;

        code = get_vlc2(&s.gb, vlc.table, vlc.bits, 1);
        g.sb_hybrid[s_index+0]=
        g.sb_hybrid[s_index+1]=
        g.sb_hybrid[s_index+2]=
        g.sb_hybrid[s_index+3]= 0;
        while(code){
            static immutable int[16] idxtab = [3,3,2,2,1,1,1,1,0,0,0,0,0,0,0,0];
            int v;
            int pos_= s_index+idxtab[code];
            code ^= 8>>idxtab[code];
            v = exp_table[ exponents[pos_] ];
            if(get_bits1(&s.gb))
                v = -v;
            g.sb_hybrid[pos_] = v;
        }
        s_index+=4;
    }
    /*
    if (s_index >= g.sb_hybrid.length) {
      import core.stdc.stdio : printf;
      printf("s_index=%u; len=%u; len=%u\n", cast(uint)s_index, cast(uint)g.sb_hybrid.length, cast(uint)((g.sb_hybrid[0]).sizeof*(576 - s_index)));
      assert(0);
    }
    */
    if ((g.sb_hybrid[0]).sizeof*(576 - s_index) > 0) {
      libc_memset(&g.sb_hybrid[s_index], 0, (g.sb_hybrid[0]).sizeof*(576 - s_index));
    }

    /* skip extension bits */
    bits_left = end_pos2 - get_bits_count(&s.gb);
    if (bits_left < 0) {
        return -1;
    }
    skip_bits_long(&s.gb, bits_left);

    i= get_bits_count(&s.gb);
    switch_buffer(s, &i, &end_pos, &end_pos2);

    return 0;
}


// ////////////////////////////////////////////////////////////////////////// //
void imdct12(int *out_, int *in_)
{
    int in0, in1, in2, in3, in4, in5, t1, t2;

    in0= in_[0*3];
    in1= in_[1*3] + in_[0*3];
    in2= in_[2*3] + in_[1*3];
    in3= in_[3*3] + in_[2*3];
    in4= in_[4*3] + in_[3*3];
    in5= in_[5*3] + in_[4*3];
    in5 += in3;
    in3 += in1;

    in2= cast(int)MULH(2*in2, C3);
    in3= cast(int)MULH(4*in3, C3);

    t1 = in0 - in4;
    t2 = cast(int)MULH(2*(in1 - in5), icos36h[4]);

    out_[ 7]=
    out_[10]= t1 + t2;
    out_[ 1]=
    out_[ 4]= t1 - t2;

    in0 += in4>>1;
    in4 = in0 + in2;
    in5 += 2*in1;
    in1 = cast(int)MULH(in5 + in3, icos36h[1]);
    out_[ 8]=
    out_[ 9]= in4 + in1;
    out_[ 2]=
    out_[ 3]= in4 - in1;

    in0 -= in2;
    in5 = cast(int)MULH(2*(in5 - in3), icos36h[7]);
    out_[ 0]=
    out_[ 5]= in0 - in5;
    out_[ 6]=
    out_[11]= in0 + in5;
}

void imdct36(int *out_, int *buf, int *in_, int *win)
{
    int i, j, t0, t1, t2, t3, s0, s1, s2, s3;
    int[18] tmp;
    int* tmp1, in1;

    for(i=17;i>=1;i--)
        in_[i] += in_[i-1];
    for(i=17;i>=3;i-=2)
        in_[i] += in_[i-2];

    for(j=0;j<2;j++) {
        tmp1 = tmp.ptr + j;
        in1 = in_ + j;
        t2 = in1[2*4] + in1[2*8] - in1[2*2];

        t3 = in1[2*0] + (in1[2*6]>>1);
        t1 = in1[2*0] - in1[2*6];
        tmp1[ 6] = t1 - (t2>>1);
        tmp1[16] = t1 + t2;

        t0 = cast(int)MULH(2*(in1[2*2] + in1[2*4]),    C2);
        t1 = cast(int)MULH(   in1[2*4] - in1[2*8] , -2*C8);
        t2 = cast(int)MULH(2*(in1[2*2] + in1[2*8]),   -C4);

        tmp1[10] = t3 - t0 - t2;
        tmp1[ 2] = t3 + t0 + t1;
        tmp1[14] = t3 + t2 - t1;

        tmp1[ 4] = cast(int)MULH(2*(in1[2*5] + in1[2*7] - in1[2*1]), -C3);
        t2 = cast(int)MULH(2*(in1[2*1] + in1[2*5]),    C1);
        t3 = cast(int)MULH(   in1[2*5] - in1[2*7] , -2*C7);
        t0 = cast(int)MULH(2*in1[2*3], C3);

        t1 = cast(int)MULH(2*(in1[2*1] + in1[2*7]),   -C5);

        tmp1[ 0] = t2 + t3 + t0;
        tmp1[12] = t2 + t1 - t0;
        tmp1[ 8] = t3 - t1 - t0;
    }

    i = 0;
    for(j=0;j<4;j++) {
        t0 = tmp[i];
        t1 = tmp[i + 2];
        s0 = t1 + t0;
        s2 = t1 - t0;

        t2 = tmp[i + 1];
        t3 = tmp[i + 3];
        s1 = cast(int)MULH(2*(t3 + t2), icos36h[j]);
        s3 = cast(int)MULL(t3 - t2, icos36[8 - j]);

        t0 = s0 + s1;
        t1 = s0 - s1;
        out_[(9 + j)*SBLIMIT] =  cast(int)MULH(t1, win[9 + j]) + buf[9 + j];
        out_[(8 - j)*SBLIMIT] =  cast(int)MULH(t1, win[8 - j]) + buf[8 - j];
        buf[9 + j] = cast(int)MULH(t0, win[18 + 9 + j]);
        buf[8 - j] = cast(int)MULH(t0, win[18 + 8 - j]);

        t0 = s2 + s3;
        t1 = s2 - s3;
        out_[(9 + 8 - j)*SBLIMIT] =  cast(int)MULH(t1, win[9 + 8 - j]) + buf[9 + 8 - j];
        out_[(        j)*SBLIMIT] =  cast(int)MULH(t1, win[        j]) + buf[        j];
        buf[9 + 8 - j] = cast(int)MULH(t0, win[18 + 9 + 8 - j]);
        buf[      + j] = cast(int)MULH(t0, win[18         + j]);
        i += 4;
    }

    s0 = tmp[16];
    s1 = cast(int)MULH(2*tmp[17], icos36h[4]);
    t0 = s0 + s1;
    t1 = s0 - s1;
    out_[(9 + 4)*SBLIMIT] =  cast(int)MULH(t1, win[9 + 4]) + buf[9 + 4];
    out_[(8 - 4)*SBLIMIT] =  cast(int)MULH(t1, win[8 - 4]) + buf[8 - 4];
    buf[9 + 4] = cast(int)MULH(t0, win[18 + 9 + 4]);
    buf[8 - 4] = cast(int)MULH(t0, win[18 + 8 - 4]);
}

void compute_imdct (mp3_context_t *s, granule_t *g, int32_t *sb_samples, int32_t *mdct_buf) {
    int32_t* ptr, win, win1, buf, out_ptr, ptr1;
    int32_t[12] out2;
    int i, j, mdct_long_end, v, sblimit;

    /* find last non zero block */
    ptr = g.sb_hybrid.ptr + 576;
    ptr1 = g.sb_hybrid.ptr + 2 * 18;
    while (ptr >= ptr1) {
        ptr -= 6;
        v = ptr[0] | ptr[1] | ptr[2] | ptr[3] | ptr[4] | ptr[5];
        if (v != 0)
            break;
    }
    sblimit = cast(int)((ptr - g.sb_hybrid.ptr) / 18) + 1;

    if (g.block_type == 2) {
        /* XXX: check for 8000 Hz */
        if (g.switch_point)
            mdct_long_end = 2;
        else
            mdct_long_end = 0;
    } else {
        mdct_long_end = sblimit;
    }

    buf = mdct_buf;
    ptr = g.sb_hybrid.ptr;
    for(j=0;j<mdct_long_end;j++) {
        /* apply window & overlap with previous buffer */
        out_ptr = sb_samples + j;
        /* select window */
        if (g.switch_point && j < 2)
            win1 = mdct_win[0].ptr;
        else
            win1 = mdct_win[g.block_type].ptr;
        /* select frequency inversion */
        win = win1 + ((4 * 36) & -(j & 1));
        imdct36(out_ptr, buf, ptr, win);
        out_ptr += 18*SBLIMIT;
        ptr += 18;
        buf += 18;
    }
    for(j=mdct_long_end;j<sblimit;j++) {
        /* select frequency inversion */
        win = mdct_win[2].ptr + ((4 * 36) & -(j & 1));
        out_ptr = sb_samples + j;

        for(i=0; i<6; i++){
            *out_ptr = buf[i];
            out_ptr += SBLIMIT;
        }
        imdct12(out2.ptr, ptr + 0);
        for(i=0;i<6;i++) {
            *out_ptr = cast(int)MULH(out2[i], win[i]) + buf[i + 6*1];
            buf[i + 6*2] = cast(int)MULH(out2[i + 6], win[i + 6]);
            out_ptr += SBLIMIT;
        }
        imdct12(out2.ptr, ptr + 1);
        for(i=0;i<6;i++) {
            *out_ptr = cast(int)MULH(out2[i], win[i]) + buf[i + 6*2];
            buf[i + 6*0] = cast(int)MULH(out2[i + 6], win[i + 6]);
            out_ptr += SBLIMIT;
        }
        imdct12(out2.ptr, ptr + 2);
        for(i=0;i<6;i++) {
            buf[i + 6*0] = cast(int)MULH(out2[i], win[i]) + buf[i + 6*0];
            buf[i + 6*1] = cast(int)MULH(out2[i + 6], win[i + 6]);
            buf[i + 6*2] = 0;
        }
        ptr += 18;
        buf += 18;
    }
    /* zero bands */
    for(j=sblimit;j<SBLIMIT;j++) {
        /* overlap */
        out_ptr = sb_samples + j;
        for(i=0;i<18;i++) {
            *out_ptr = buf[i];
            buf[i] = 0;
            out_ptr += SBLIMIT;
        }
        buf += 18;
    }
}

enum SUM8(string sum, string op, string w, string p) =
"{\n"~
"  "~sum~" "~op~" MULS(("~w~")[0 * 64], "~p~"[0 * 64]);\n"~
"  "~sum~" "~op~" MULS(("~w~")[1 * 64], "~p~"[1 * 64]);\n"~
"  "~sum~" "~op~" MULS(("~w~")[2 * 64], "~p~"[2 * 64]);\n"~
"  "~sum~" "~op~" MULS(("~w~")[3 * 64], "~p~"[3 * 64]);\n"~
"  "~sum~" "~op~" MULS(("~w~")[4 * 64], "~p~"[4 * 64]);\n"~
"  "~sum~" "~op~" MULS(("~w~")[5 * 64], "~p~"[5 * 64]);\n"~
"  "~sum~" "~op~" MULS(("~w~")[6 * 64], "~p~"[6 * 64]);\n"~
"  "~sum~" "~op~" MULS(("~w~")[7 * 64], "~p~"[7 * 64]);\n"~
"}\n";

enum SUM8P2(string sum1, string op1, string sum2, string op2, string w1, string w2, string p) =
"{\n"~
"  int tmp_;\n"~
"  tmp_ = "~p~"[0 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[0 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[0 * 64], tmp_);\n"~
"  tmp_ = "~p~"[1 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[1 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[1 * 64], tmp_);\n"~
"  tmp_ = "~p~"[2 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[2 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[2 * 64], tmp_);\n"~
"  tmp_ = "~p~"[3 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[3 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[3 * 64], tmp_);\n"~
"  tmp_ = "~p~"[4 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[4 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[4 * 64], tmp_);\n"~
"  tmp_ = "~p~"[5 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[5 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[5 * 64], tmp_);\n"~
"  tmp_ = "~p~"[6 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[6 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[6 * 64], tmp_);\n"~
"  tmp_ = "~p~"[7 * 64];\n"~
"  "~sum1~" "~op1~" MULS(("~w1~")[7 * 64], tmp_);\n"~
"  "~sum2~" "~op2~" MULS(("~w2~")[7 * 64], tmp_);\n"~
"}\n";

enum COS0_0 = FIXHR!(0.50060299823519630134/2);
enum COS0_1 = FIXHR!(0.50547095989754365998/2);
enum COS0_2 = FIXHR!(0.51544730992262454697/2);
enum COS0_3 = FIXHR!(0.53104259108978417447/2);
enum COS0_4 = FIXHR!(0.55310389603444452782/2);
enum COS0_5 = FIXHR!(0.58293496820613387367/2);
enum COS0_6 = FIXHR!(0.62250412303566481615/2);
enum COS0_7 = FIXHR!(0.67480834145500574602/2);
enum COS0_8 = FIXHR!(0.74453627100229844977/2);
enum COS0_9 = FIXHR!(0.83934964541552703873/2);
enum COS0_10 = FIXHR!(0.97256823786196069369/2);
enum COS0_11 = FIXHR!(1.16943993343288495515/4);
enum COS0_12 = FIXHR!(1.48416461631416627724/4);
enum COS0_13 = FIXHR!(2.05778100995341155085/8);
enum COS0_14 = FIXHR!(3.40760841846871878570/8);
enum COS0_15 = FIXHR!(10.19000812354805681150/32);

enum COS1_0 = FIXHR!(0.50241928618815570551/2);
enum COS1_1 = FIXHR!(0.52249861493968888062/2);
enum COS1_2 = FIXHR!(0.56694403481635770368/2);
enum COS1_3 = FIXHR!(0.64682178335999012954/2);
enum COS1_4 = FIXHR!(0.78815462345125022473/2);
enum COS1_5 = FIXHR!(1.06067768599034747134/4);
enum COS1_6 = FIXHR!(1.72244709823833392782/4);
enum COS1_7 = FIXHR!(5.10114861868916385802/16);

enum COS2_0 = FIXHR!(0.50979557910415916894/2);
enum COS2_1 = FIXHR!(0.60134488693504528054/2);
enum COS2_2 = FIXHR!(0.89997622313641570463/2);
enum COS2_3 = FIXHR!(2.56291544774150617881/8);

enum COS3_0 = FIXHR!(0.54119610014619698439/2);
enum COS3_1 = FIXHR!(1.30656296487637652785/4);

enum COS4_0 = FIXHR!(0.70710678118654752439/2);

enum BF(string a, string b, string c, string s) =
"{\n"~
"  tmp0 = tab["~a~"] + tab["~b~"];\n"~
"  tmp1 = tab["~a~"] - tab["~b~"];\n"~
"  tab["~a~"] = tmp0;\n"~
"  tab["~b~"] = cast(int)MULH(tmp1<<("~s~"), "~c~");\n"~
"}\n";

enum BF1(string a, string b, string c, string d) =
"{\n"~
"  "~BF!(a, b, "COS4_0", "1")~"\n"~
"  "~BF!(c, d,"-COS4_0", "1")~"\n"~
"  tab["~c~"] += tab["~d~"];\n"~
"}\n";

enum BF2(string a, string b, string c, string d) =
"{\n"~
"  "~BF!(a, b, "COS4_0", "1")~"\n"~
"  "~BF!(c, d,"-COS4_0", "1")~"\n"~
"  tab["~c~"] += tab["~d~"];\n"~
"  tab["~a~"] += tab["~c~"];\n"~
"  tab["~c~"] += tab["~b~"];\n"~
"  tab["~b~"] += tab["~d~"];\n"~
"}\n";

void dct32(int32_t *out_, int32_t *tab) {
    int tmp0, tmp1;

    /* pass 1 */
    mixin(BF!("0", "31", "COS0_0", "1"));
    mixin(BF!("15", "16", "COS0_15", "5"));
    /* pass 2 */
    mixin(BF!("0", "15", "COS1_0", "1"));
    mixin(BF!("16", "31", "-COS1_0", "1"));
    /* pass 1 */
    mixin(BF!("7", "24", "COS0_7", "1"));
    mixin(BF!("8", "23", "COS0_8", "1"));
    /* pass 2 */
    mixin(BF!("7", "8", "COS1_7", "4"));
    mixin(BF!("23", "24", "-COS1_7", "4"));
    /* pass 3 */
    mixin(BF!("0", "7", "COS2_0", "1"));
    mixin(BF!("8", "15", "-COS2_0", "1"));
    mixin(BF!("16", "23", "COS2_0", "1"));
    mixin(BF!("24", "31", "-COS2_0", "1"));
    /* pass 1 */
    mixin(BF!("3", "28", "COS0_3", "1"));
    mixin(BF!("12", "19", "COS0_12", "2"));
    /* pass 2 */
    mixin(BF!("3", "12", "COS1_3", "1"));
    mixin(BF!("19", "28", "-COS1_3", "1"));
    /* pass 1 */
    mixin(BF!("4", "27", "COS0_4", "1"));
    mixin(BF!("11", "20", "COS0_11", "2"));
    /* pass 2 */
    mixin(BF!("4", "11", "COS1_4", "1"));
    mixin(BF!("20", "27", "-COS1_4", "1"));
    /* pass 3 */
    mixin(BF!("3", "4", "COS2_3", "3"));
    mixin(BF!("11", "12", "-COS2_3", "3"));
    mixin(BF!("19", "20", "COS2_3", "3"));
    mixin(BF!("27", "28", "-COS2_3", "3"));
    /* pass 4 */
    mixin(BF!("0", "3", "COS3_0", "1"));
    mixin(BF!("4", "7", "-COS3_0", "1"));
    mixin(BF!("8", "11", "COS3_0", "1"));
    mixin(BF!("12", "15", "-COS3_0", "1"));
    mixin(BF!("16", "19", "COS3_0", "1"));
    mixin(BF!("20", "23", "-COS3_0", "1"));
    mixin(BF!("24", "27", "COS3_0", "1"));
    mixin(BF!("28", "31", "-COS3_0", "1"));



    /* pass 1 */
    mixin(BF!("1", "30", "COS0_1", "1"));
    mixin(BF!("14", "17", "COS0_14", "3"));
    /* pass 2 */
    mixin(BF!("1", "14", "COS1_1", "1"));
    mixin(BF!("17", "30", "-COS1_1", "1"));
    /* pass 1 */
    mixin(BF!("6", "25", "COS0_6", "1"));
    mixin(BF!("9", "22", "COS0_9", "1"));
    /* pass 2 */
    mixin(BF!("6", "9", "COS1_6", "2"));
    mixin(BF!("22", "25", "-COS1_6", "2"));
    /* pass 3 */
    mixin(BF!("1", "6", "COS2_1", "1"));
    mixin(BF!("9", "14", "-COS2_1", "1"));
    mixin(BF!("17", "22", "COS2_1", "1"));
    mixin(BF!("25", "30", "-COS2_1", "1"));

    /* pass 1 */
    mixin(BF!("2", "29", "COS0_2", "1"));
    mixin(BF!("13", "18", "COS0_13", "3"));
    /* pass 2 */
    mixin(BF!("2", "13", "COS1_2", "1"));
    mixin(BF!("18", "29", "-COS1_2", "1"));
    /* pass 1 */
    mixin(BF!("5", "26", "COS0_5", "1"));
    mixin(BF!("10", "21", "COS0_10", "1"));
    /* pass 2 */
    mixin(BF!("5", "10", "COS1_5", "2"));
    mixin(BF!("21", "26", "-COS1_5", "2"));
    /* pass 3 */
    mixin(BF!("2", "5", "COS2_2", "1"));
    mixin(BF!("10", "13", "-COS2_2", "1"));
    mixin(BF!("18", "21", "COS2_2", "1"));
    mixin(BF!("26", "29", "-COS2_2", "1"));
    /* pass 4 */
    mixin(BF!("1", "2", "COS3_1", "2"));
    mixin(BF!("5", "6", "-COS3_1", "2"));
    mixin(BF!("9", "10", "COS3_1", "2"));
    mixin(BF!("13", "14", "-COS3_1", "2"));
    mixin(BF!("17", "18", "COS3_1", "2"));
    mixin(BF!("21", "22", "-COS3_1", "2"));
    mixin(BF!("25", "26", "COS3_1", "2"));
    mixin(BF!("29", "30", "-COS3_1", "2"));

    /* pass 5 */
    mixin(BF1!("0", "1", "2", "3"));
    mixin(BF2!("4", "5", "6", "7"));
    mixin(BF1!("8", "9", "10", "11"));
    mixin(BF2!("12", "13", "14", "15"));
    mixin(BF1!("16", "17", "18", "19"));
    mixin(BF2!("20", "21", "22", "23"));
    mixin(BF1!("24", "25", "26", "27"));
    mixin(BF2!("28", "29", "30", "31"));

    /* pass 6 */

    tab[8] += tab[12];
    tab[12] += tab[10];
    tab[10] += tab[14];
    tab[14] += tab[9];
    tab[9] += tab[13];
    tab[13] += tab[11];
    tab[11] += tab[15];

    out_[ 0] = tab[0];
    out_[16] = tab[1];
    out_[ 8] = tab[2];
    out_[24] = tab[3];
    out_[ 4] = tab[4];
    out_[20] = tab[5];
    out_[12] = tab[6];
    out_[28] = tab[7];
    out_[ 2] = tab[8];
    out_[18] = tab[9];
    out_[10] = tab[10];
    out_[26] = tab[11];
    out_[ 6] = tab[12];
    out_[22] = tab[13];
    out_[14] = tab[14];
    out_[30] = tab[15];

    tab[24] += tab[28];
    tab[28] += tab[26];
    tab[26] += tab[30];
    tab[30] += tab[25];
    tab[25] += tab[29];
    tab[29] += tab[27];
    tab[27] += tab[31];

    out_[ 1] = tab[16] + tab[24];
    out_[17] = tab[17] + tab[25];
    out_[ 9] = tab[18] + tab[26];
    out_[25] = tab[19] + tab[27];
    out_[ 5] = tab[20] + tab[28];
    out_[21] = tab[21] + tab[29];
    out_[13] = tab[22] + tab[30];
    out_[29] = tab[23] + tab[31];
    out_[ 3] = tab[24] + tab[20];
    out_[19] = tab[25] + tab[21];
    out_[11] = tab[26] + tab[22];
    out_[27] = tab[27] + tab[23];
    out_[ 7] = tab[28] + tab[18];
    out_[23] = tab[29] + tab[19];
    out_[15] = tab[30] + tab[17];
    out_[31] = tab[31];
}

void mp3_synth_filter(
    int16_t *synth_buf_ptr, int *synth_buf_offset,
    int16_t *window, int *dither_state,
    int16_t *samples, int incr,
    int32_t* sb_samples/*[SBLIMIT]*/
) {
    int32_t[32] tmp;
    int16_t *synth_buf;
    const(int16_t)* w, w2, p;
    int j, offset, v;
    int16_t *samples2;
    int sum, sum2;

    dct32(tmp.ptr, sb_samples);

    offset = *synth_buf_offset;
    synth_buf = synth_buf_ptr + offset;

    for(j=0;j<32;j++) {
        v = tmp[j];
        /* NOTE: can cause a loss in precision if very high amplitude
           sound */
        if (v > 32767)
            v = 32767;
        else if (v < -32768)
            v = -32768;
        synth_buf[j] = cast(short)v;
    }
    /* copy to avoid wrap */
    libc_memcpy(synth_buf + 512, synth_buf, 32 * int16_t.sizeof);

    samples2 = samples + 31 * incr;
    w = window;
    w2 = window + 31;

    sum = *dither_state;
    p = synth_buf + 16;
    mixin(SUM8!("sum", "+=", "w", "p"));
    p = synth_buf + 48;
    mixin(SUM8!("sum", "-=", "w + 32", "p"));
    *samples = cast(short)round_sample(&sum);
    samples += incr;
    w++;

    /* we calculate two samples at the same time to avoid one memory
       access per two sample */
    for(j=1;j<16;j++) {
        sum2 = 0;
        p = synth_buf + 16 + j;
        mixin(SUM8P2!("sum", "+=", "sum2", "-=", "w", "w2", "p"));
        p = synth_buf + 48 - j;
        mixin(SUM8P2!("sum", "-=", "sum2", "-=", "w + 32", "w2 + 32", "p"));

        *samples = cast(short)round_sample(&sum);
        samples += incr;
        sum += sum2;
        *samples2 = cast(short)round_sample(&sum);
        samples2 -= incr;
        w++;
        w2--;
    }

    p = synth_buf + 32;
    mixin(SUM8!("sum", "-=", "w + 32", "p"));
    *samples = cast(short)round_sample(&sum);
    *dither_state= sum;

    offset = (offset - 32) & 511;
    *synth_buf_offset = offset;
}


// ////////////////////////////////////////////////////////////////////////// //
int decode_header(mp3_context_t *s, uint32_t header) {
    static immutable short[4][4] sampleCount = [
      [0, 576, 1152, 384], // v2.5
      [0, 0, 0, 0], // reserved
      [0, 576, 1152, 384], // v2
      [0, 1152, 1152, 384], // v1
    ];
    ubyte mpid = (header>>19)&0x03;
    ubyte layer = (header>>17)&0x03;

    s.sample_count = sampleCount.ptr[mpid].ptr[layer];

    int sample_rate, frame_size, mpeg25, padding;
    int sample_rate_index, bitrate_index;
    if (header & (1<<20)) {
        s.lsf = (header & (1<<19)) ? 0 : 1;
        mpeg25 = 0;
    } else {
        s.lsf = 1;
        mpeg25 = 1;
    }

    sample_rate_index = (header >> 10) & 3;
    sample_rate = mp3_freq_tab[sample_rate_index] >> (s.lsf + mpeg25);
    sample_rate_index += 3 * (s.lsf + mpeg25);
    s.sample_rate_index = sample_rate_index;
    s.error_protection = ((header >> 16) & 1) ^ 1;
    s.sample_rate = sample_rate;

    bitrate_index = (header >> 12) & 0xf;
    padding = (header >> 9) & 1;
    s.mode = (header >> 6) & 3;
    s.mode_ext = (header >> 4) & 3;
    s.nb_channels = (s.mode == MP3_MONO) ? 1 : 2;

    if (bitrate_index != 0) {
        frame_size = mp3_bitrate_tab[s.lsf][bitrate_index];
        s.bit_rate = frame_size * 1000;
        s.frame_size = (frame_size * 144000) / (sample_rate << s.lsf) + padding;
    } else {
        /* if no frame size computed, signal it */
        return 1;
    }
    return 0;
}

int mp_decode_layer3(mp3_context_t *s) {
    int nb_granules, main_data_begin, private_bits;
    int gr, ch, blocksplit_flag, i, j, k, n, bits_pos;
    granule_t *g;
    static granule_t[2][2] granules;
    static int16_t[576] exponents;
    const(uint8_t)* ptr;

    if (s.lsf) {
        main_data_begin = get_bits(&s.gb, 8);
        private_bits = get_bits(&s.gb, s.nb_channels);
        nb_granules = 1;
    } else {
        main_data_begin = get_bits(&s.gb, 9);
        if (s.nb_channels == 2)
            private_bits = get_bits(&s.gb, 3);
        else
            private_bits = get_bits(&s.gb, 5);
        nb_granules = 2;
        for(ch=0;ch<s.nb_channels;ch++) {
            granules[ch][0].scfsi = 0; /* all scale factors are transmitted */
            granules[ch][1].scfsi = cast(ubyte)get_bits(&s.gb, 4);
        }
    }

    for(gr=0;gr<nb_granules;gr++) {
        for(ch=0;ch<s.nb_channels;ch++) {
            g = &granules[ch][gr];
            g.part2_3_length = get_bits(&s.gb, 12);
            g.big_values = get_bits(&s.gb, 9);
            g.global_gain = get_bits(&s.gb, 8);
            /* if MS stereo only is selected, we precompute the
               1/sqrt(2) renormalization factor */
            if ((s.mode_ext & (MODE_EXT_MS_STEREO | MODE_EXT_I_STEREO)) ==
                MODE_EXT_MS_STEREO)
                g.global_gain -= 2;
            if (s.lsf)
                g.scalefac_compress = get_bits(&s.gb, 9);
            else
                g.scalefac_compress = get_bits(&s.gb, 4);
            blocksplit_flag = get_bits(&s.gb, 1);
            if (blocksplit_flag) {
                g.block_type = cast(ubyte)get_bits(&s.gb, 2);
                if (g.block_type == 0)
                    return -1;
                g.switch_point = cast(ubyte)get_bits(&s.gb, 1);
                for(i=0;i<2;i++)
                    g.table_select[i] = get_bits(&s.gb, 5);
                for(i=0;i<3;i++)
                    g.subblock_gain[i] = get_bits(&s.gb, 3);
                /* compute huffman coded region sizes */
                if (g.block_type == 2)
                    g.region_size[0] = (36 / 2);
                else {
                    if (s.sample_rate_index <= 2)
                        g.region_size[0] = (36 / 2);
                    else if (s.sample_rate_index != 8)
                        g.region_size[0] = (54 / 2);
                    else
                        g.region_size[0] = (108 / 2);
                }
                g.region_size[1] = (576 / 2);
            } else {
                int region_address1, region_address2, l;
                g.block_type = 0;
                g.switch_point = 0;
                for(i=0;i<3;i++)
                    g.table_select[i] = get_bits(&s.gb, 5);
                /* compute huffman coded region sizes */
                region_address1 = get_bits(&s.gb, 4);
                region_address2 = get_bits(&s.gb, 3);
                g.region_size[0] =
                    band_index_long[s.sample_rate_index][region_address1 + 1] >> 1;
                l = region_address1 + region_address2 + 2;
                /* should not overflow */
                if (l > 22)
                    l = 22;
                g.region_size[1] =
                    band_index_long[s.sample_rate_index][l] >> 1;
            }
            /* convert region offsets to region sizes and truncate
               size to big_values */
            g.region_size[2] = (576 / 2);
            j = 0;
            for(i=0;i<3;i++) {
                k = g.region_size[i];
                if (g.big_values < k) k = g.big_values;
                g.region_size[i] = k - j;
                j = k;
            }

            /* compute band indexes */
            if (g.block_type == 2) {
                if (g.switch_point) {
                    /* if switched mode, we handle the 36 first samples as
                       long blocks.  For 8000Hz, we handle the 48 first
                       exponents as long blocks (XXX: check this!) */
                    if (s.sample_rate_index <= 2)
                        g.long_end = 8;
                    else if (s.sample_rate_index != 8)
                        g.long_end = 6;
                    else
                        g.long_end = 4; /* 8000 Hz */

                    g.short_start = 2 + (s.sample_rate_index != 8);
                } else {
                    g.long_end = 0;
                    g.short_start = 0;
                }
            } else {
                g.short_start = 13;
                g.long_end = 22;
            }

            g.preflag = 0;
            if (!s.lsf)
                g.preflag = get_bits(&s.gb, 1);
            g.scalefac_scale = cast(ubyte)get_bits(&s.gb, 1);
            g.count1table_select = cast(ubyte)get_bits(&s.gb, 1);
        }
    }

    ptr = s.gb.buffer + (get_bits_count(&s.gb)>>3);
    /* now we get bits from the main_data_begin offset */
    if(main_data_begin > s.last_buf_size){
        s.last_buf_size= main_data_begin;
      }

    libc_memcpy(s.last_buf.ptr + s.last_buf_size, ptr, EXTRABYTES);
    s.in_gb= s.gb;
    init_get_bits(&s.gb, s.last_buf.ptr + s.last_buf_size - main_data_begin, main_data_begin*8);

    for(gr=0;gr<nb_granules;gr++) {
        for(ch=0;ch<s.nb_channels;ch++) {
            g = &granules[ch][gr];

            bits_pos = get_bits_count(&s.gb);

            if (!s.lsf) {
                uint8_t *sc;
                int slen, slen1, slen2;

                /* MPEG1 scale factors */
                slen1 = slen_table[0][g.scalefac_compress];
                slen2 = slen_table[1][g.scalefac_compress];
                if (g.block_type == 2) {
                    n = g.switch_point ? 17 : 18;
                    j = 0;
                    if(slen1){
                        for(i=0;i<n;i++)
                            g.scale_factors[j++] = cast(ubyte)get_bits(&s.gb, slen1);
                    }else{
                        libc_memset(cast(void*) &g.scale_factors[j], 0, n);
                        j += n;
//                        for(i=0;i<n;i++)
//                            g.scale_factors[j++] = 0;
                    }
                    if(slen2){
                        for(i=0;i<18;i++)
                            g.scale_factors[j++] = cast(ubyte)get_bits(&s.gb, slen2);
                        for(i=0;i<3;i++)
                            g.scale_factors[j++] = 0;
                    }else{
                        for(i=0;i<21;i++)
                            g.scale_factors[j++] = 0;
                    }
                } else {
                    sc = granules[ch][0].scale_factors.ptr;
                    j = 0;
                    for(k=0;k<4;k++) {
                        n = (k == 0 ? 6 : 5);
                        if ((g.scfsi & (0x8 >> k)) == 0) {
                            slen = (k < 2) ? slen1 : slen2;
                            if(slen){
                                for(i=0;i<n;i++)
                                    g.scale_factors[j++] = cast(ubyte)get_bits(&s.gb, slen);
                            }else{
                                libc_memset(cast(void*) &g.scale_factors[j], 0, n);
                                j += n;
//                                for(i=0;i<n;i++)
//                                    g.scale_factors[j++] = 0;
                            }
                        } else {
                            /* simply copy from last granule */
                            for(i=0;i<n;i++) {
                                g.scale_factors[j] = sc[j];
                                j++;
                            }
                        }
                    }
                    g.scale_factors[j++] = 0;
                }
            } else {
                int tindex, tindex2, sl, sf;
                int[4] slen;

                /* LSF scale factors */
                if (g.block_type == 2) {
                    tindex = g.switch_point ? 2 : 1;
                } else {
                    tindex = 0;
                }
                sf = g.scalefac_compress;
                if ((s.mode_ext & MODE_EXT_I_STEREO) && ch == 1) {
                    /* intensity stereo case */
                    sf >>= 1;
                    if (sf < 180) {
                        lsf_sf_expand(slen.ptr, sf, 6, 6, 0);
                        tindex2 = 3;
                    } else if (sf < 244) {
                        lsf_sf_expand(slen.ptr, sf - 180, 4, 4, 0);
                        tindex2 = 4;
                    } else {
                        lsf_sf_expand(slen.ptr, sf - 244, 3, 0, 0);
                        tindex2 = 5;
                    }
                } else {
                    /* normal case */
                    if (sf < 400) {
                        lsf_sf_expand(slen.ptr, sf, 5, 4, 4);
                        tindex2 = 0;
                    } else if (sf < 500) {
                        lsf_sf_expand(slen.ptr, sf - 400, 5, 4, 0);
                        tindex2 = 1;
                    } else {
                        lsf_sf_expand(slen.ptr, sf - 500, 3, 0, 0);
                        tindex2 = 2;
                        g.preflag = 1;
                    }
                }

                j = 0;
                for(k=0;k<4;k++) {
                    n = lsf_nsf_table[tindex2][tindex][k];
                    sl = slen[k];
                    if(sl){
                        for(i=0;i<n;i++)
                            g.scale_factors[j++] = cast(ubyte)get_bits(&s.gb, sl);
                    }else{
                        libc_memset(cast(void*) &g.scale_factors[j], 0, n);
                        j += n;
//                        for(i=0;i<n;i++)
//                            g.scale_factors[j++] = 0;
                    }
                }
                /* XXX: should compute exact size */
                libc_memset(cast(void*) &g.scale_factors[j], 0, 40 - j);
//                for(;j<40;j++)
//                    g.scale_factors[j] = 0;
            }

            exponents_from_scale_factors(s, g, exponents.ptr);

            /* read Huffman coded residue */
            if (huffman_decode(s, g, exponents.ptr,
                               bits_pos + g.part2_3_length) < 0)
                return -1;
        } /* ch */

        if (s.nb_channels == 2)
            compute_stereo(s, &granules[0][gr], &granules[1][gr]);

        for(ch=0;ch<s.nb_channels;ch++) {
            g = &granules[ch][gr];
            reorder_block(s, g);
            compute_antialias(s, g);
            compute_imdct(s, g, &s.sb_samples[ch][18 * gr][0], s.mdct_buf[ch].ptr);
        }
    } /* gr */
    return nb_granules * 18;
}

int mp3_decode_main(
    mp3_context_t *s,
    int16_t *samples, const uint8_t *buf, int buf_size
) {
    int i, nb_frames, ch;
    int16_t *samples_ptr;

    init_get_bits(&s.gb, buf + HEADER_SIZE, (buf_size - HEADER_SIZE)*8);

    if (s.error_protection)
        get_bits(&s.gb, 16);

        nb_frames = mp_decode_layer3(s);

        s.last_buf_size=0;
        if(s.in_gb.buffer){
            align_get_bits(&s.gb);
            i= (s.gb.size_in_bits - get_bits_count(&s.gb))>>3;
            if(i >= 0 && i <= BACKSTEP_SIZE){
                libc_memmove(s.last_buf.ptr, s.gb.buffer + (get_bits_count(&s.gb)>>3), i);
                s.last_buf_size=i;
            }
            s.gb= s.in_gb;
        }

        align_get_bits(&s.gb);
        i= (s.gb.size_in_bits - get_bits_count(&s.gb))>>3;

        if(i<0 || i > BACKSTEP_SIZE || nb_frames<0){
            i = buf_size - HEADER_SIZE;
            if (BACKSTEP_SIZE < i) i = BACKSTEP_SIZE;
        }
        libc_memcpy(s.last_buf.ptr + s.last_buf_size, s.gb.buffer + buf_size - HEADER_SIZE - i, i);
        s.last_buf_size += i;

    /* apply the synthesis filter */
    for(ch=0;ch<s.nb_channels;ch++) {
        samples_ptr = samples + ch;
        for(i=0;i<nb_frames;i++) {
            mp3_synth_filter(
                s.synth_buf[ch].ptr, &(s.synth_buf_offset[ch]),
                window.ptr, &s.dither_state,
                samples_ptr, s.nb_channels,
                s.sb_samples[ch][i].ptr
            );
            samples_ptr += 32 * s.nb_channels;
        }
    }
    return nb_frames * 32 * cast(int)uint16_t.sizeof * s.nb_channels;
}


// ////////////////////////////////////////////////////////////////////////// //
shared static this () {
  auto res = mp3_decode_init();
  if (res < 0) assert(0, "mp3 initialization failed");
}

int mp3_decode_init () {
    int i, j, k;

    if (true) {
        /* synth init */
        for(i=0;i<257;i++) {
            int v;
            v = mp3_enwindow[i];
            static if (WFRAC_BITS < 16) {
              v = (v + (1 << (16 - WFRAC_BITS - 1))) >> (16 - WFRAC_BITS);
            }
            window[i] = cast(short)v;
            if ((i & 63) != 0)
                v = -v;
            if (i != 0)
                window[512 - i] = cast(short)v;
        }

        /* huffman decode tables */
        for(i=1;i<16;i++) {
            const huff_table_t *h = &mp3_huff_tables[i];
            int xsize, x, y;
            uint n;
            uint8_t[512] tmp_bits;
            uint16_t[512] tmp_codes;

            libc_memset(tmp_bits.ptr, 0, tmp_bits.sizeof);
            libc_memset(tmp_codes.ptr, 0, tmp_codes.sizeof);

            xsize = h.xsize;
            n = xsize * xsize;

            j = 0;
            for(x=0;x<xsize;x++) {
                for(y=0;y<xsize;y++){
                    tmp_bits [(x << 5) | y | ((x&&y)<<4)]= h.bits [j  ];
                    tmp_codes[(x << 5) | y | ((x&&y)<<4)]= h.codes[j++];
                }
            }

            init_vlc(&huff_vlc[i], 7, 512,
                     tmp_bits.ptr, 1, 1, tmp_codes.ptr, 2, 2);
        }
        for(i=0;i<2;i++) {
            init_vlc(&huff_quad_vlc[i], (i == 0 ? 7 : 4), 16,
                     mp3_quad_bits[i].ptr, 1, 1, mp3_quad_codes[i].ptr, 1, 1);
        }

        for(i=0;i<9;i++) {
            k = 0;
            for(j=0;j<22;j++) {
                band_index_long[i][j] = cast(ushort)k;
                k += band_size_long[i][j];
            }
            band_index_long[i][22] = cast(ushort)k;
        }

        /* compute n ^ (4/3) and store it in mantissa/exp format */
        table_4_3_exp= cast(byte*)libc_malloc(TABLE_4_3_SIZE * (table_4_3_exp[0]).sizeof);
        if(!table_4_3_exp)
            return -1;
        table_4_3_value= cast(uint*)libc_malloc(TABLE_4_3_SIZE * (table_4_3_value[0]).sizeof);
        if(!table_4_3_value)
            return -1;

        for(i=1;i<TABLE_4_3_SIZE;i++) {
            double f, fm;
            int e, m;
            f = libc_pow(cast(double)(i/4), 4.0 / 3.0) * libc_pow(2, (i&3)*0.25);
            fm = libc_frexp(f, e);
            m = cast(uint32_t)(fm*(1L<<31) + 0.5);
            e+= FRAC_BITS - 31 + 5 - 100;
            table_4_3_value[i] = m;
            table_4_3_exp[i] = cast(byte)(-e);
        }
        for(i=0; i<512*16; i++){
            int exponent= (i>>4);
            double f= libc_pow(i&15, 4.0 / 3.0) * libc_pow(2, (exponent-400)*0.25 + FRAC_BITS + 5);
            expval_table[exponent][i&15]= cast(uint)f;
            if((i&15)==1)
                exp_table[exponent]= cast(uint)f;
        }

        for(i=0;i<7;i++) {
            float f;
            int v;
            if (i != 6) {
                f = tan(cast(double)i * M_PI / 12.0);
                v = FIXRx(f / (1.0 + f));
            } else {
                v = FIXR!(1.0);
            }
            is_table[0][i] = v;
            is_table[1][6 - i] = v;
        }
        for(i=7;i<16;i++)
            is_table[0][i] = is_table[1][i] = cast(int)0.0;

        for(i=0;i<16;i++) {
            double f;
            int e, k_;

            for(j=0;j<2;j++) {
                e = -(j + 1) * ((i + 1) >> 1);
                f = libc_pow(2.0, e / 4.0);
                k_ = i & 1;
                is_table_lsf[j][k_ ^ 1][i] = FIXRx(f);
                is_table_lsf[j][k_][i] = FIXR!(1.0);
            }
        }

        for(i=0;i<8;i++) {
            float ci, cs, ca;
            ci = ci_table[i];
            cs = 1.0 / sqrt(1.0 + ci * ci);
            ca = cs * ci;
            csa_table[i][0] = FIXHRx(cs/4);
            csa_table[i][1] = FIXHRx(ca/4);
            csa_table[i][2] = FIXHRx(ca/4) + FIXHRx(cs/4);
            csa_table[i][3] = FIXHRx(ca/4) - FIXHRx(cs/4);
            csa_table_float[i][0] = cs;
            csa_table_float[i][1] = ca;
            csa_table_float[i][2] = ca + cs;
            csa_table_float[i][3] = ca - cs;
        }

        /* compute mdct windows */
        for(i=0;i<36;i++) {
            for(j=0; j<4; j++){
                double d;

                if(j==2 && i%3 != 1)
                    continue;

                d= sin(M_PI * (i + 0.5) / 36.0);
                if(j==1){
                    if     (i>=30) d= 0;
                    else if(i>=24) d= sin(M_PI * (i - 18 + 0.5) / 12.0);
                    else if(i>=18) d= 1;
                }else if(j==3){
                    if     (i<  6) d= 0;
                    else if(i< 12) d= sin(M_PI * (i -  6 + 0.5) / 12.0);
                    else if(i< 18) d= 1;
                }
                d*= 0.5 / cos(M_PI*(2*i + 19)/72);
                if(j==2)
                    mdct_win[j][i/3] = FIXHRx((d / (1<<5)));
                else
                    mdct_win[j][i  ] = FIXHRx((d / (1<<5)));
            }
        }
        for(j=0;j<4;j++) {
            for(i=0;i<36;i+=2) {
                mdct_win[j + 4][i] = mdct_win[j][i];
                mdct_win[j + 4][i + 1] = -mdct_win[j][i + 1];
            }
        }
        //init = 1;
    }
    return 0;
}

int mp3_decode_frame (mp3_context_t *s, int16_t *out_samples, int *data_size, uint8_t *buf, int buf_size) {
  uint32_t header;
  int out_size;
  int extra_bytes = 0;

retry:
  if (buf_size < HEADER_SIZE) return -1;

  header = (buf[0]<<24)|(buf[1]<<16)|(buf[2]<<8)|buf[3];
  if (mp3_check_header(header) < 0){
    ++buf;
    --buf_size;
    ++extra_bytes;
    goto retry;
  }

  if (s.last_header && (header&0xffff0c00u) != s.last_header) {
    ++buf;
    --buf_size;
    ++extra_bytes;
    goto retry;
  }

  if (decode_header(s, header) == 1) {
    s.frame_size = -1;
    return -1;
  }

  if (s.frame_size<=0 || s.frame_size > buf_size) return -1; // incomplete frame
  if (s.frame_size < buf_size) buf_size = s.frame_size;

  out_size = mp3_decode_main(s, out_samples, buf, buf_size);
  if (out_size >= 0) {
    *data_size = out_size;
    s.last_header = header&0xffff0c00u;
  }
  // else: Error while decoding MPEG audio frame.
  s.frame_size += extra_bytes;
  return buf_size;
}


/+
int mp3_skip_frame (mp3_context_t *s, uint8_t *buf, int buf_size) {
  uint32_t header;
  int out_size;
  int extra_bytes = 0;

retry:
  if (buf_size < HEADER_SIZE) return -1;

  header = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
  if (mp3_check_header(header) < 0) {
    ++buf;
    --buf_size;
    ++extra_bytes;
    goto retry;
  }

  if (s.last_header && (header&0xffff0c00u) != s.last_header) {
    ++buf;
    --buf_size;
    ++extra_bytes;
    goto retry;
  }

  if (decode_header(s, header) == 1) {
    s.frame_size = -1;
    return -1;
  }

  if (s.frame_size <= 0 || s.frame_size > buf_size) return -1;  // incomplete frame
  if (s.frame_size < buf_size) buf_size = s.frame_size;
  s.last_header = header&0xffff0c00u;
  s.frame_size += extra_bytes;
  return buf_size;
}
+/
