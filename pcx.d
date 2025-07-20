//ketmar: Adam didn't wrote this, don't blame him!
//TODO: other bpp formats besides 8 and 24
module arsd.pcx;

import arsd.color;
import std.stdio : File; // sorry

static if (__traits(compiles, { import iv.vfs; })) enum ArsdPcxHasIVVFS = true; else enum ArsdPcxHasIVVFS = false;
static if (ArsdPcxHasIVVFS) import iv.vfs;


// ////////////////////////////////////////////////////////////////////////// //
public MemoryImage loadPcxMem (const(void)[] buf, const(char)[] filename=null) {
  static struct MemRO {
    const(ubyte)[] data;
    long pos;

    this (const(void)[] abuf) { data = cast(const(ubyte)[])abuf; }

    @property long tell () { return pos; }
    @property long size () { return data.length; }

    void seek (long offset, int whence=Seek.Set) {
      switch (whence) {
        case Seek.Set:
          if (offset < 0 || offset > data.length) throw new Exception("invalid offset");
          pos = offset;
          break;
        case Seek.Cur:
          if (offset < -pos || offset > data.length-pos) throw new Exception("invalid offset");
          pos += offset;
          break;
        case Seek.End:
          pos = data.length+offset;
          if (pos < 0 || pos > data.length) throw new Exception("invalid offset");
          break;
        default:
          throw new Exception("invalid offset origin");
      }
    }

    ptrdiff_t read (void* buf, size_t count) @system {
      if (pos >= data.length) return 0;
      if (count > 0) {
        import core.stdc.string : memcpy;
        long rlen = data.length-pos;
        if (rlen >= count) rlen = count;
        assert(rlen != 0);
        memcpy(buf, data.ptr+pos, cast(size_t)rlen);
        pos += rlen;
        return cast(ptrdiff_t)rlen;
      } else {
        return 0;
      }
    }
  }

  auto rd = MemRO(buf);
  return loadPcx(rd, filename);
}

static if (ArsdPcxHasIVVFS) public MemoryImage loadPcx (VFile fl) { return loadPcxImpl(fl, fl.name); }
public MemoryImage loadPcx (File fl) { return loadPcxImpl(fl, fl.name); }
public MemoryImage loadPcx(T:const(char)[]) (T fname) {
  static if (is(T == typeof(null))) {
    throw new Exception("cannot load nameless tga");
  } else {
    static if (ArsdPcxHasIVVFS) {
      return loadPcx(VFile(fname));
    } else static if (is(T == string)) {
      return loadPcx(File(fname), fname);
    } else {
      return loadPcx(File(fname.idup), fname);
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
// pass filename to ease detection
// hack around "has scoped destruction, cannot build closure"
public MemoryImage loadPcx(ST) (auto ref ST fl, const(char)[] filename=null) if (isReadableStream!ST && isSeekableStream!ST) { return loadPcxImpl(fl, filename); }

private MemoryImage loadPcxImpl(ST) (auto ref ST fl, const(char)[] filename) {
  import core.stdc.stdlib : malloc, free;

  // PCX file header
  static struct PCXHeader {
    ubyte manufacturer; // 0x0a --signifies a PCX file
    ubyte ver; // version 5 is what we look for
    ubyte encoding; // when 1, it's RLE encoding (only type as of yet)
    ubyte bitsperpixel; // how many bits to represent 1 pixel
    ushort xmin, ymin, xmax, ymax; // dimensions of window (really insigned?)
    ushort hdpi, vdpi; // device resolution (horizontal, vertical)
    ubyte[16*3] colormap; // 16-color palette
    ubyte reserved;
    ubyte colorplanes; // number of color planes
    ushort bytesperline; // number of bytes per line (per color plane)
    ushort palettetype; // 1 = color,2 = grayscale (unused in v.5+)
    ubyte[58] filler; // used to fill-out 128 byte header (useless)
  }

  bool isGoodExtension (const(char)[] filename) {
    if (filename.length >= 4) {
      auto ext = filename[$-4..$];
      if (ext[0] == '.' && (ext[1] == 'P' || ext[1] == 'p') && (ext[2] == 'C' || ext[2] == 'c') && (ext[3] == 'X' || ext[3] == 'x')) return true;
    }
    return false;
  }

  // check file extension, if any
  if (filename.length && !isGoodExtension(filename)) return null;

  // we should have at least header
  if (fl.size < 129) throw new Exception("invalid pcx file size");

  fl.seek(0);
  PCXHeader hdr;
  fl.readStruct(hdr);

  // check some header fields
  if (hdr.manufacturer != 0x0a) throw new Exception("invalid pcx manufacturer");
  if (/*header.ver != 0 && header.ver != 2 && header.ver != 3 &&*/ hdr.ver != 5) throw new Exception("invalid pcx version");
  if (hdr.encoding != 0 && hdr.encoding != 1) throw new Exception("invalid pcx compresstion");

  int wdt = hdr.xmax-hdr.xmin+1;
  int hgt = hdr.ymax-hdr.ymin+1;

  // arbitrary size limits
  if (wdt < 1 || wdt > 32000) throw new Exception("invalid pcx width");
  if (hgt < 1 || hgt > 32000) throw new Exception("invalid pcx height");

  if (hdr.bytesperline < wdt) throw new Exception("invalid pcx hdr");

  // if it's not a 256-color PCX file, and not 24-bit PCX file, gtfo
  bool bpp24 = false;
  bool hasAlpha = false;
  if (hdr.colorplanes == 1) {
    if (hdr.bitsperpixel != 8 && hdr.bitsperpixel != 24 && hdr.bitsperpixel != 32) throw new Exception("invalid pcx bpp");
    bpp24 = (hdr.bitsperpixel == 24);
    hasAlpha = (hdr.bitsperpixel == 32);
  } else if (hdr.colorplanes == 3 || hdr.colorplanes == 4) {
    if (hdr.bitsperpixel != 8) throw new Exception("invalid pcx bpp");
    bpp24 = true;
    hasAlpha = (hdr.colorplanes == 4);
  }

  version(arsd_debug_pcx) { import core.stdc.stdio; printf("colorplanes=%u; bitsperpixel=%u; bytesperline=%u\n", cast(uint)hdr.colorplanes, cast(uint)hdr.bitsperpixel, cast(uint)hdr.bytesperline); }

  // additional checks
  if (hdr.reserved != 0) throw new Exception("invalid pcx hdr");

  // 8bpp files MUST have palette
  if (!bpp24 && fl.size < 129+769) throw new Exception("invalid pcx file size");

  void readLine (ubyte* line) {
    foreach (immutable p; 0..hdr.colorplanes) {
      int count = 0;
      ubyte b;
      foreach (immutable n; 0..hdr.bytesperline) {
        if (count == 0) {
          // read next byte, do RLE decompression by the way
          fl.rawReadExact((&b)[0..1]);
          if (hdr.encoding) {
            if ((b&0xc0) == 0xc0) {
              count = b&0x3f;
              if (count == 0) throw new Exception("invalid pcx RLE data");
              fl.rawReadExact((&b)[0..1]);
            } else {
              count = 1;
            }
          } else {
            count = 1;
          }
        }
        assert(count > 0);
        line[n] = b;
        --count;
      }
      // allow excessive counts, why not?
      line += hdr.bytesperline;
    }
  }

  int lsize = hdr.bytesperline*hdr.colorplanes;
  if (!bpp24 && lsize < 768) lsize = 768; // so we can use it as palette buffer
  auto line = cast(ubyte*)malloc(lsize);
  if (line is null) throw new Exception("out of memory");
  scope(exit) free(line);

  IndexedImage iimg;
  TrueColorImage timg;
  scope(failure) { .destroy(timg); .destroy(iimg); }

  if (!bpp24) {
    iimg = new IndexedImage(wdt, hgt);
  } else {
    timg = new TrueColorImage(wdt, hgt);
  }

  foreach (immutable y; 0..hgt) {
    readLine(line);
    if (!bpp24) {
      import core.stdc.string : memcpy;
      // 8bpp, with palette
      memcpy(iimg.data.ptr+wdt*y, line, wdt);
    } else {
      // 24bpp
      auto src = line;
      auto dest = timg.imageData.bytes.ptr+(wdt*4)*y; //RGBA
      if (hdr.colorplanes != 1) {
        // planar
        foreach (immutable x; 0..wdt) {
          *dest++ = src[0]; // red
          *dest++ = src[hdr.bytesperline]; // green
          *dest++ = src[hdr.bytesperline*2]; // blue
          if (hasAlpha) {
            *dest++ = src[hdr.bytesperline*3]; // blue
          } else {
            *dest++ = 255; // alpha (opaque)
          }
          ++src;
        }
      } else {
        // flat
        foreach (immutable x; 0..wdt) {
          *dest++ = *src++; // red
          *dest++ = *src++; // green
          *dest++ = *src++; // blue
          if (hasAlpha) {
            *dest++ = *src++; // alpha
          } else {
            *dest++ = 255; // alpha (opaque)
          }
        }
      }
    }
  }

  // read palette
  if (!bpp24) {
    fl.seek(-769, Seek.End);
    if (fl.readNum!ubyte != 12) throw new Exception("invalid pcx palette");
    // it is guaranteed to have at least 768 bytes in `line`
    fl.rawReadExact(line[0..768]);
    if (iimg.palette.length < 256) iimg.palette.length = 256;
    foreach (immutable cidx; 0..256) {
      /* nope, it is not in VGA format
      // transform [0..63] palette to [0..255]
      int r = line[cidx*3+0]*255/63;
      int g = line[cidx*3+1]*255/63;
      int b = line[cidx*3+2]*255/63;
      iimg.palette[cidx] = Color(r, g, b, 255);
      */
      iimg.palette[cidx] = Color(line[cidx*3+0], line[cidx*3+1], line[cidx*3+2], 255);
    }
    return iimg;
  } else {
    return timg;
  }
}


// ////////////////////////////////////////////////////////////////////////// //
private:
static if (!ArsdPcxHasIVVFS) {
import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;

enum Seek : int {
  Set = SEEK_SET,
  Cur = SEEK_CUR,
  End = SEEK_END,
}


// ////////////////////////////////////////////////////////////////////////// //
// augmentation checks
// is this "low-level" stream that can be read?
enum isLowLevelStreamR(T) = is(typeof((inout int=0) {
  auto t = T.init;
  ubyte[1] b;
  ptrdiff_t r = t.read(b.ptr, 1);
}));

// is this "low-level" stream that can be written?
enum isLowLevelStreamW(T) = is(typeof((inout int=0) {
  auto t = T.init;
  ubyte[1] b;
  ptrdiff_t w = t.write(b.ptr, 1);
}));


// is this "low-level" stream that can be seeked?
enum isLowLevelStreamS(T) = is(typeof((inout int=0) {
  auto t = T.init;
  long p = t.lseek(0, 0);
}));


// ////////////////////////////////////////////////////////////////////////// //
// augment low-level streams with `rawRead`
T[] rawRead(ST, T) (auto ref ST st, T[] buf) if (isLowLevelStreamR!ST && !is(T == const) && !is(T == immutable)) {
  if (buf.length > 0) {
    auto res = st.read(buf.ptr, buf.length*T.sizeof);
    if (res == -1 || res%T.sizeof != 0) throw new Exception("read error");
    return buf[0..res/T.sizeof];
  } else {
    return buf[0..0];
  }
}

// augment low-level streams with `rawWrite`
void rawWrite(ST, T) (auto ref ST st, in T[] buf) if (isLowLevelStreamW!ST) {
  if (buf.length > 0) {
    auto res = st.write(buf.ptr, buf.length*T.sizeof);
    if (res == -1 || res%T.sizeof != 0) throw new Exception("write error");
  }
}

// read exact size or throw error
T[] rawReadExact(ST, T) (auto ref ST st, T[] buf) if (isReadableStream!ST && !is(T == const) && !is(T == immutable)) {
  if (buf.length == 0) return buf;
  auto left = buf.length*T.sizeof;
  auto dp = cast(ubyte*)buf.ptr;
  while (left > 0) {
    auto res = st.rawRead(cast(void[])(dp[0..left]));
    if (res.length == 0) throw new Exception("read error");
    dp += res.length;
    left -= res.length;
  }
  return buf;
}

// write exact size or throw error (just for convenience)
void rawWriteExact(ST, T) (auto ref ST st, in T[] buf) if (isWriteableStream!ST) { st.rawWrite(buf); }

// if stream doesn't have `.size`, but can be seeked, emulate it
long size(ST) (auto ref ST st) if (isSeekableStream!ST && !streamHasSize!ST) {
  auto opos = st.tell;
  st.seek(0, Seek.End);
  auto res = st.tell;
  st.seek(opos);
  return res;
}


// ////////////////////////////////////////////////////////////////////////// //
// check if a given stream supports `eof`
enum streamHasEof(T) = is(typeof((inout int=0) {
  auto t = T.init;
  bool n = t.eof;
}));

// check if a given stream supports `seek`
enum streamHasSeek(T) = is(typeof((inout int=0) {
  import core.stdc.stdio : SEEK_END;
  auto t = T.init;
  t.seek(0);
  t.seek(0, SEEK_END);
}));

// check if a given stream supports `tell`
enum streamHasTell(T) = is(typeof((inout int=0) {
  auto t = T.init;
  long pos = t.tell;
}));

// check if a given stream supports `size`
enum streamHasSize(T) = is(typeof((inout int=0) {
  auto t = T.init;
  long pos = t.size;
}));

// check if a given stream supports `rawRead()`.
// it's enough to support `void[] rawRead (void[] buf)`
enum isReadableStream(T) = is(typeof((inout int=0) {
  auto t = T.init;
  ubyte[1] b;
  auto v = cast(void[])b;
  t.rawRead(v);
}));

// check if a given stream supports `rawWrite()`.
// it's enough to support `inout(void)[] rawWrite (inout(void)[] buf)`
enum isWriteableStream(T) = is(typeof((inout int=0) {
  auto t = T.init;
  ubyte[1] b;
  t.rawWrite(cast(void[])b);
}));

// check if a given stream supports `.seek(ofs, [whence])`, and `.tell`
enum isSeekableStream(T) = (streamHasSeek!T && streamHasTell!T);

// check if we can get size of a given stream.
// this can be done either with `.size`, or with `.seek` and `.tell`
enum isSizedStream(T) = (streamHasSize!T || isSeekableStream!T);

// ////////////////////////////////////////////////////////////////////////// //
private enum isGoodEndianness(string s) = (s == "LE" || s == "le" || s == "BE" || s == "be");

private template isLittleEndianness(string s) if (isGoodEndianness!s) {
  enum isLittleEndianness = (s == "LE" || s == "le");
}

private template isBigEndianness(string s) if (isGoodEndianness!s) {
  enum isLittleEndianness = (s == "BE" || s == "be");
}

private template isSystemEndianness(string s) if (isGoodEndianness!s) {
  version(LittleEndian) {
    enum isSystemEndianness = isLittleEndianness!s;
  } else {
    enum isSystemEndianness = isBigEndianness!s;
  }
}


// ////////////////////////////////////////////////////////////////////////// //
// write integer value of the given type, with the given endianness (default: little-endian)
// usage: st.writeNum!ubyte(10)
void writeNum(T, string es="LE", ST) (auto ref ST st, T n) if (isGoodEndianness!es && isWriteableStream!ST && __traits(isIntegral, T)) {
  static assert(T.sizeof <= 8); // just in case
  static if (isSystemEndianness!es) {
    st.rawWriteExact((&n)[0..1]);
  } else {
    ubyte[T.sizeof] b = void;
    version(LittleEndian) {
      // convert to big-endian
      foreach_reverse (ref x; b) { x = n&0xff; n >>= 8; }
    } else {
      // convert to little-endian
      foreach (ref x; b) { x = n&0xff; n >>= 8; }
    }
    st.rawWriteExact(b[]);
  }
}


// read integer value of the given type, with the given endianness (default: little-endian)
// usage: auto v = st.readNum!ubyte
T readNum(T, string es="LE", ST) (auto ref ST st) if (isGoodEndianness!es && isReadableStream!ST && __traits(isIntegral, T)) {
  static assert(T.sizeof <= 8); // just in case
  static if (isSystemEndianness!es) {
    T v = void;
    st.rawReadExact((&v)[0..1]);
    return v;
  } else {
    ubyte[T.sizeof] b = void;
    st.rawReadExact(b[]);
    T v = 0;
    version(LittleEndian) {
      // convert from big-endian
      foreach (ubyte x; b) { v <<= 8; v |= x; }
    } else {
      // conver from little-endian
      foreach_reverse (ubyte x; b) { v <<= 8; v |= x; }
    }
    return v;
  }
}


private enum reverseBytesMixin = "
  foreach (idx; 0..b.length/2) {
    ubyte t = b[idx];
    b[idx] = b[$-idx-1];
    b[$-idx-1] = t;
  }
";


// write floating value of the given type, with the given endianness (default: little-endian)
// usage: st.writeNum!float(10)
void writeNum(T, string es="LE", ST) (auto ref ST st, T n) if (isGoodEndianness!es && isWriteableStream!ST && __traits(isFloating, T)) {
  static assert(T.sizeof <= 8);
  static if (isSystemEndianness!es) {
    st.rawWriteExact((&n)[0..1]);
  } else {
    import core.stdc.string : memcpy;
    ubyte[T.sizeof] b = void;
    memcpy(b.ptr, &n, T.sizeof);
    mixin(reverseBytesMixin);
    st.rawWriteExact(b[]);
  }
}


// read floating value of the given type, with the given endianness (default: little-endian)
// usage: auto v = st.readNum!float
T readNum(T, string es="LE", ST) (auto ref ST st) if (isGoodEndianness!es && isReadableStream!ST && __traits(isFloating, T)) {
  static assert(T.sizeof <= 8);
  T v = void;
  static if (isSystemEndianness!es) {
    st.rawReadExact((&v)[0..1]);
  } else {
    import core.stdc.string : memcpy;
    ubyte[T.sizeof] b = void;
    st.rawReadExact(b[]);
    mixin(reverseBytesMixin);
    memcpy(&v, b.ptr, T.sizeof);
  }
  return v;
}


// ////////////////////////////////////////////////////////////////////////// //
void readStruct(string es="LE", SS, ST) (auto ref ST fl, ref SS st)
if (is(SS == struct) && isGoodEndianness!es && isReadableStream!ST)
{
  void unserData(T) (ref T v) {
    import std.traits : Unqual;
    alias UT = Unqual!T;
    static if (is(T : V[], V)) {
      // array
      static if (__traits(isStaticArray, T)) {
        foreach (ref it; v) unserData(it);
      } else static if (is(UT == char)) {
        // special case: dynamic `char[]` array will be loaded as asciiz string
        char c;
        for (;;) {
          if (fl.rawRead((&c)[0..1]).length == 0) break; // don't require trailing zero on eof
          if (c == 0) break;
          v ~= c;
        }
      } else {
        assert(0, "cannot load dynamic arrays yet");
      }
    } else static if (is(T : V[K], K, V)) {
      assert(0, "cannot load associative arrays yet");
    } else static if (__traits(isIntegral, UT) || __traits(isFloating, UT)) {
      // this takes care of `*char` and `bool` too
      v = cast(UT)fl.readNum!(UT, es);
    } else static if (is(T == struct)) {
      // struct
      import std.traits : FieldNameTuple, hasUDA;
      foreach (string fldname; FieldNameTuple!T) {
        unserData(__traits(getMember, v, fldname));
      }
    }
  }

  unserData(st);
}
}
