// DDS decoders
// Based on code from Nvidia's DDS example:
// http://www.nvidia.com/object/dxtc_decompression_code.html
//
// Copyright (c) 2003 Randy Reddig
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this list
// of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice, this
// list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// Neither the names of the copyright holders nor the names of its contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// D port and further changes by Ketmar // Invisible Vector
module arsd.dds;

import arsd.color : Color, TrueColorImage;


// ////////////////////////////////////////////////////////////////////////// //
public bool ddsDetect (const(void)[] buf, int* width=null, int* height=null) nothrow @trusted @nogc {
  if (buf.length < 128) return false;
  auto data = cast(const(ubyte)[])buf;

  uint getUInt (uint ofs) nothrow @trusted @nogc {
    if (ofs >= data.length) return uint.max;
    if (data.length-ofs < 4) return uint.max;
    return data.ptr[ofs]|(data.ptr[ofs+1]<<8)|(data.ptr[ofs+2]<<16)|(data.ptr[ofs+3]<<24);
  }

  // signature
  if (data.ptr[0] != 'D' || data.ptr[1] != 'D' || data.ptr[2] != 'S' || data.ptr[3] != ' ') return false;
  // header size check
  if (getUInt(4) != 124) return false;

  int w = getUInt(4*4);
  int h = getUInt(3*4);
  // arbitrary limits
  if (w < 1 || h < 1 || w > 65500 || h > 65500) return false;
  if (width !is null) *width = w;
  if (height !is null) *height = h;

  // check pixel format
  if (getUInt(76) < 8) return false; // size
  immutable flags = getUInt(80);
  if (flags&DDS_FOURCC) {
    // DXTn
    if (data.ptr[84+0] != 'D' || data.ptr[84+1] != 'X' || data.ptr[84+2] != 'T') return false;
    if (data.ptr[84+3] < '1' || data.ptr[84+3] > '5') return false;
  } else if (flags == DDS_RGB || flags == DDS_RGBA) {
    immutable bitcount = getUInt(88);
    if (bitcount != 24 && bitcount != 32) return false;
    // ARGB8888
    //if (data.ptr[84+0] == 0 || data.ptr[84+1] == 0 || data.ptr[84+2] == 0 || data.ptr[84+3] == 0) return true;
  }
  return true;
}


// ////////////////////////////////////////////////////////////////////////// //
public TrueColorImage ddsLoadFromMemory (const(void)[] buf) {
  int w, h;
  if (!ddsDetect(buf, &w, &h)) throw new Exception("not a DDS image");

  //FIXME: check for OOB access in decoders
  const(ddsBuffer_t)* dds = cast(const(ddsBuffer_t)*)buf.ptr;

  auto tc = new TrueColorImage(w, h);
  scope(failure) .destroy(tc);

  if (!DDSDecompress(dds, tc.imageData.colors)) throw new Exception("invalid dds image");

  return tc;
}


static import std.stdio;
public TrueColorImage ddsLoadFromFile() (std.stdio.File fl) {
  import core.stdc.stdlib : malloc, free;
  auto fsize = fl.size-fl.tell;
  if (fsize < 128 || fsize > int.max/8) throw new Exception("invalid dds size");
  ddsBuffer_t* dds = cast(ddsBuffer_t*)malloc(cast(uint)fsize);
  if (dds is null) throw new Exception("out of memory");
  scope(exit) free(dds);
  ubyte[] lb = (cast(ubyte*)dds)[0..cast(uint)fsize];
  while (lb.length > 0) {
    auto rd = fl.rawRead(lb[]);
    if (rd.length < 1) throw new Exception("read error");
    lb = lb[rd.length..$];
  }
  return ddsLoadFromMemory((cast(ubyte*)dds)[0..cast(uint)fsize]);
}


static if (__traits(compiles, { import iv.vfs; })) {
  import iv.vfs;
  public TrueColorImage ddsLoadFromFile() (VFile fl) {
    import core.stdc.stdlib : malloc, free;
    auto fsize = fl.size-fl.tell;
    if (fsize < 128 || fsize > int.max/8) throw new Exception("invalid dds size");
    ddsBuffer_t* dds = cast(ddsBuffer_t*)malloc(cast(uint)fsize);
    if (dds is null) throw new Exception("out of memory");
    scope(exit) free(dds);
    ubyte[] lb = (cast(ubyte*)dds)[0..cast(uint)fsize];
    fl.rawReadExact(lb);
    return ddsLoadFromMemory(lb);
  }
}



// ////////////////////////////////////////////////////////////////////////// //
private nothrow @trusted @nogc:

// dds definition
enum DDSPixelFormat {
  Unknown,
  RGB888,
  ARGB8888,
  DXT1,
  DXT2,
  DXT3,
  DXT4,
  DXT5,
}


// 16bpp stuff
enum DDS_LOW_5 = 0x001F;
enum DDS_MID_6 = 0x07E0;
enum DDS_HIGH_5 = 0xF800;
enum DDS_MID_555 = 0x03E0;
enum DDS_HI_555 = 0x7C00;

enum DDS_FOURCC = 0x00000004U;
enum DDS_RGB = 0x00000040U;
enum DDS_RGBA = 0x00000041U;
enum DDS_DEPTH = 0x00800000U;

enum DDS_COMPLEX = 0x00000008U;
enum DDS_CUBEMAP = 0x00000200U;
enum DDS_VOLUME = 0x00200000U;


// structures
align(1) struct ddsColorKey_t {
align(1):
  uint colorSpaceLowValue;
  uint colorSpaceHighValue;
}


align(1) struct ddsCaps_t {
align(1):
  uint caps1;
  uint caps2;
  uint caps3;
  uint caps4;
}


align(1) struct ddsMultiSampleCaps_t {
align(1):
  ushort flipMSTypes;
  ushort bltMSTypes;
}


align(1) struct ddsPixelFormat_t {
align(1):
  uint size;
  uint flags;
  char[4] fourCC;
  union {
    uint rgbBitCount;
    uint yuvBitCount;
    uint zBufferBitDepth;
    uint alphaBitDepth;
    uint luminanceBitCount;
    uint bumpBitCount;
    uint privateFormatBitCount;
  }
  union {
    uint rBitMask;
    uint yBitMask;
    uint stencilBitDepth;
    uint luminanceBitMask;
    uint bumpDuBitMask;
    uint operations;
  }
  union {
    uint gBitMask;
    uint uBitMask;
    uint zBitMask;
    uint bumpDvBitMask;
    ddsMultiSampleCaps_t multiSampleCaps;
  }
  union {
    uint bBitMask;
    uint vBitMask;
    uint stencilBitMask;
    uint bumpLuminanceBitMask;
  }
  union {
    uint rgbAlphaBitMask;
    uint yuvAlphaBitMask;
    uint luminanceAlphaBitMask;
    uint rgbZBitMask;
    uint yuvZBitMask;
  }
}
//pragma(msg, ddsPixelFormat_t.sizeof);


align(1) struct ddsBuffer_t {
align(1):
  // magic: 'dds '
  char[4] magic;

  // directdraw surface
  uint size;
  uint flags;
  uint height;
  uint width;
  union {
    int pitch;
    uint linearSize;
  }
  uint backBufferCount;
  union {
    uint mipMapCount;
    uint refreshRate;
    uint srcVBHandle;
  }
  uint alphaBitDepth;
  uint reserved;
  uint /+void*+/ surface;
  union {
    ddsColorKey_t ckDestOverlay;
    uint emptyFaceColor;
  }
  ddsColorKey_t ckDestBlt;
  ddsColorKey_t ckSrcOverlay;
  ddsColorKey_t ckSrcBlt;
  union {
    ddsPixelFormat_t pixelFormat;
    uint fvf;
  }
  ddsCaps_t ddsCaps;
  uint textureStage;

  // data (Varying size)
  ubyte[0] data;
}
//pragma(msg, ddsBuffer_t.sizeof);
//pragma(msg, ddsBuffer_t.pixelFormat.offsetof+4*2);


align(1) struct ddsColorBlock_t {
align(1):
  ushort[2] colors;
  ubyte[4] row;
}
static assert(ddsColorBlock_t.sizeof == 8);


align(1) struct ddsAlphaBlockExplicit_t {
align(1):
  ushort[4] row;
}
static assert(ddsAlphaBlockExplicit_t.sizeof == 8);


align(1) struct ddsAlphaBlock3BitLinear_t {
align(1):
  ubyte alpha0;
  ubyte alpha1;
  ubyte[6] stuff;
}
static assert(ddsAlphaBlock3BitLinear_t.sizeof == 8);


// ////////////////////////////////////////////////////////////////////////// //
//public int DDSGetInfo( ddsBuffer_t *dds, int *width, int *height, DDSPixelFormat *pf );
//public int DDSDecompress( ddsBuffer_t *dds, ubyte *pixels );

// extracts relevant info from a dds texture, returns `true` on success
/*public*/ bool DDSGetInfo (const(ddsBuffer_t)* dds, int* width, int* height, DDSPixelFormat* pf) {
  // dummy test
  if (dds is null) return false;

  // test dds header
  if (dds.magic != "DDS ") return false;
  if (DDSLittleLong(dds.size) != 124) return false;
  // arbitrary limits
  if (DDSLittleLong(dds.width) < 1 || DDSLittleLong(dds.width) > 65535) return false;
  if (DDSLittleLong(dds.height) < 1 || DDSLittleLong(dds.height) > 65535) return false;

  // extract width and height
  if (width !is null) *width = DDSLittleLong(dds.width);
  if (height !is null) *height = DDSLittleLong(dds.height);

  // get pixel format
  DDSDecodePixelFormat(dds, pf);

  // return ok
  return true;
}


// decompresses a dds texture into an rgba image buffer, returns 0 on success
/*public*/ bool DDSDecompress (const(ddsBuffer_t)* dds, Color[] pixels) {
  int width, height;
  DDSPixelFormat pf;

  // get dds info
  if (!DDSGetInfo(dds, &width, &height, &pf)) return false;
  // arbitrary limits
  if (DDSLittleLong(dds.width) < 1 || DDSLittleLong(dds.width) > 65535) return false;
  if (DDSLittleLong(dds.height) < 1 || DDSLittleLong(dds.height) > 65535) return false;
  if (pixels.length < width*height) return false;

  // decompress
  final switch (pf) {
    // FIXME: support other [a]rgb formats
    case DDSPixelFormat.RGB888: return DDSDecompressRGB888(dds, width, height, pixels.ptr);
    case DDSPixelFormat.ARGB8888: return DDSDecompressARGB8888(dds, width, height, pixels.ptr);
    case DDSPixelFormat.DXT1: return DDSDecompressDXT1(dds, width, height, pixels.ptr);
    case DDSPixelFormat.DXT2: return DDSDecompressDXT2(dds, width, height, pixels.ptr);
    case DDSPixelFormat.DXT3: return DDSDecompressDXT3(dds, width, height, pixels.ptr);
    case DDSPixelFormat.DXT4: return DDSDecompressDXT4(dds, width, height, pixels.ptr);
    case DDSPixelFormat.DXT5: return DDSDecompressDXT5(dds, width, height, pixels.ptr);
    case DDSPixelFormat.Unknown: break;
  }

  return false;
}


// ////////////////////////////////////////////////////////////////////////// //
private:

version(BigEndian) {
  int DDSLittleLong (int src) pure nothrow @safe @nogc {
    pragma(inline, true);
    return
      ((src&0xFF000000)>>24)|
      ((src&0x00FF0000)>>8)|
      ((src&0x0000FF00)<<8)|
      ((src&0x000000FF)<<24);
  }
  short DDSLittleShort (short src) pure nothrow @safe @nogc {
    pragma(inline, true);
    return cast(short)(((src&0xFF00)>>8)|((src&0x00FF)<<8));
  }
} else {
  // little endian
  int DDSLittleLong (int src) pure nothrow @safe @nogc { pragma(inline, true); return src; }
  short DDSLittleShort (short src) pure nothrow @safe @nogc { pragma(inline, true); return src; }
}


// determines which pixel format the dds texture is in
private void DDSDecodePixelFormat (const(ddsBuffer_t)* dds, DDSPixelFormat* pf) {
  // dummy check
  if (dds is null || pf is null) return;
  *pf = DDSPixelFormat.Unknown;

  if (dds.pixelFormat.size < 8) return;

  if (dds.pixelFormat.flags&DDS_FOURCC) {
    // DXTn
         if (dds.pixelFormat.fourCC == "DXT1") *pf = DDSPixelFormat.DXT1;
    else if (dds.pixelFormat.fourCC == "DXT2") *pf = DDSPixelFormat.DXT2;
    else if (dds.pixelFormat.fourCC == "DXT3") *pf = DDSPixelFormat.DXT3;
    else if (dds.pixelFormat.fourCC == "DXT4") *pf = DDSPixelFormat.DXT4;
    else if (dds.pixelFormat.fourCC == "DXT5") *pf = DDSPixelFormat.DXT5;
    else return;
  } else if (dds.pixelFormat.flags == DDS_RGB || dds.pixelFormat.flags == DDS_RGBA) {
    //immutable bitcount = getUInt(88);
         if (dds.pixelFormat.rgbBitCount == 24) *pf = DDSPixelFormat.RGB888;
    else if (dds.pixelFormat.rgbBitCount == 32) *pf = DDSPixelFormat.ARGB8888;
    else return;
  }
}


// extracts colors from a dds color block
private void DDSGetColorBlockColors (const(ddsColorBlock_t)* block, Color* colors) {
  ushort word;

  // color 0
  word = DDSLittleShort(block.colors.ptr[0]);
  colors[0].a = 0xff;

  // extract rgb bits
  colors[0].b = cast(ubyte)word;
  colors[0].b <<= 3;
  colors[0].b |= (colors[0].b>>5);
  word >>= 5;
  colors[0].g = cast(ubyte)word;
  colors[0].g <<= 2;
  colors[0].g |= (colors[0].g>>5);
  word >>= 6;
  colors[0].r = cast(ubyte)word;
  colors[0].r <<= 3;
  colors[0].r |= (colors[0].r>>5);

  // same for color 1
  word = DDSLittleShort(block.colors.ptr[1]);
  colors[1].a = 0xff;

  // extract rgb bits
  colors[1].b = cast(ubyte)word;
  colors[1].b <<= 3;
  colors[1].b |= (colors[1].b>>5);
  word >>= 5;
  colors[1].g = cast(ubyte)word;
  colors[1].g <<= 2;
  colors[1].g |= (colors[1].g>>5);
  word >>= 6;
  colors[1].r = cast(ubyte)word;
  colors[1].r <<= 3;
  colors[1].r |= (colors[1].r>>5);

  // use this for all but the super-freak math method
  if (block.colors.ptr[0] > block.colors.ptr[1]) {
    /* four-color block: derive the other two colors.
       00 = color 0, 01 = color 1, 10 = color 2, 11 = color 3
       these two bit codes correspond to the 2-bit fields
       stored in the 64-bit block. */
    word = (cast(ushort)colors[0].r*2+cast(ushort)colors[1].r)/3;
                      // no +1 for rounding
                      // as bits have been shifted to 888
    colors[2].r = cast(ubyte) word;
    word = (cast(ushort)colors[0].g*2+cast(ushort)colors[1].g)/3;
    colors[2].g = cast(ubyte) word;
    word = (cast(ushort)colors[0].b*2+cast(ushort)colors[1].b)/3;
    colors[2].b = cast(ubyte)word;
    colors[2].a = 0xff;

    word = (cast(ushort)colors[0].r+cast(ushort)colors[1].r*2)/3;
    colors[3].r = cast(ubyte)word;
    word = (cast(ushort)colors[0].g+cast(ushort)colors[1].g*2)/3;
    colors[3].g = cast(ubyte)word;
    word = (cast(ushort)colors[0].b+cast(ushort)colors[1].b*2)/3;
    colors[3].b = cast(ubyte)word;
    colors[3].a = 0xff;
  } else {
    /* three-color block: derive the other color.
       00 = color 0, 01 = color 1, 10 = color 2,
       11 = transparent.
       These two bit codes correspond to the 2-bit fields
       stored in the 64-bit block */
    word = (cast(ushort)colors[0].r+cast(ushort)colors[1].r)/2;
    colors[2].r = cast(ubyte)word;
    word = (cast(ushort)colors[0].g+cast(ushort)colors[1].g)/2;
    colors[2].g = cast(ubyte)word;
    word = (cast(ushort)colors[0].b+cast(ushort)colors[1].b)/2;
    colors[2].b = cast(ubyte)word;
    colors[2].a = 0xff;

    // random color to indicate alpha
    colors[3].r = 0x00;
    colors[3].g = 0xff;
    colors[3].b = 0xff;
    colors[3].a = 0x00;
  }
}


//decodes a dds color block
//FIXME: make endian-safe
private void DDSDecodeColorBlock (uint* pixel, const(ddsColorBlock_t)* block, int width, const(Color)* colors) {
  int r, n;
  uint bits;
  static immutable uint[4] masks = [ 3, 12, 3<<4, 3<<6 ];  // bit masks = 00000011, 00001100, 00110000, 11000000
  static immutable ubyte[4] shift = [ 0, 2, 4, 6 ];
  // r steps through lines in y
  // no width * 4 as unsigned int ptr inc will * 4
  for (r = 0; r < 4; ++r, pixel += width-4) {
    // width * 4 bytes per pixel per line, each j dxtc row is 4 lines of pixels
    // n steps through pixels
    for (n = 0; n < 4; ++n) {
      bits = block.row.ptr[r]&masks.ptr[n];
      bits >>= shift.ptr[n];
      switch (bits) {
        case 0: *pixel++ = colors[0].asUint; break;
        case 1: *pixel++ = colors[1].asUint; break;
        case 2: *pixel++ = colors[2].asUint; break;
        case 3: *pixel++ = colors[3].asUint; break;
        default: ++pixel; break; // invalid
      }
    }
  }
}


// decodes a dds explicit alpha block
//FIXME: endianness
private void DDSDecodeAlphaExplicit (uint* pixel, const(ddsAlphaBlockExplicit_t)* alphaBlock, int width, uint alphaZero) {
  int row, pix;
  ushort word;
  Color color;

  // clear color
  color.r = 0;
  color.g = 0;
  color.b = 0;

  // walk rows
  for (row = 0; row < 4; ++row, pixel += width-4) {
    word = DDSLittleShort(alphaBlock.row.ptr[row]);
    // walk pixels
    for (pix = 0; pix < 4; ++pix) {
      // zero the alpha bits of image pixel
      *pixel &= alphaZero;
      color.a = word&0x000F;
      color.a = cast(ubyte)(color.a|(color.a<<4));
      *pixel |= *(cast(const(uint)*)&color);
      word >>= 4; // move next bits to lowest 4
      ++pixel; // move to next pixel in the row
    }
  }
}


// decodes interpolated alpha block
private void DDSDecodeAlpha3BitLinear (uint* pixel, const(ddsAlphaBlock3BitLinear_t)* alphaBlock, int width, uint alphaZero) {
  int row, pix;
  uint stuff;
  ubyte[4][4] bits;
  ushort[8] alphas;
  Color[4][4] aColors;

  // get initial alphas
  alphas.ptr[0] = alphaBlock.alpha0;
  alphas.ptr[1] = alphaBlock.alpha1;

  if (alphas.ptr[0] > alphas.ptr[1]) {
    // 8-alpha block
    // 000 = alpha_0, 001 = alpha_1, others are interpolated
    alphas.ptr[2] = (6*alphas.ptr[0]+alphas.ptr[1])/7; // bit code 010
    alphas.ptr[3] = (5*alphas.ptr[0]+2*alphas.ptr[1])/7; // bit code 011
    alphas.ptr[4] = (4*alphas.ptr[0]+3*alphas.ptr[1])/7; // bit code 100
    alphas.ptr[5] = (3*alphas.ptr[0]+4*alphas.ptr[1])/7; // bit code 101
    alphas.ptr[6] = (2*alphas.ptr[0]+5*alphas.ptr[1])/7; // bit code 110
    alphas.ptr[7] = (alphas.ptr[0]+6*alphas.ptr[1])/7; // bit code 111
  } else {
    // 6-alpha block
    // 000 = alpha_0, 001 = alpha_1, others are interpolated
    alphas.ptr[2] = (4*alphas.ptr[0]+alphas.ptr[1])/5; // bit code 010
    alphas.ptr[3] = (3*alphas.ptr[0]+2*alphas.ptr[1])/5; // bit code 011
    alphas.ptr[4] = (2*alphas.ptr[0]+3*alphas.ptr[1])/5; // bit code 100
    alphas.ptr[5] = (alphas.ptr[0]+4*alphas.ptr[1])/5; // bit code 101
    alphas.ptr[6] = 0; // bit code 110
    alphas.ptr[7] = 255; // bit code 111
  }

  // decode 3-bit fields into array of 16 bytes with same value

  // first two rows of 4 pixels each
  stuff = *(cast(const(uint)*)&(alphaBlock.stuff.ptr[0]));

  bits.ptr[0].ptr[0] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[0].ptr[1] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[0].ptr[2] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[0].ptr[3] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[1].ptr[0] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[1].ptr[1] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[1].ptr[2] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[1].ptr[3] = cast(ubyte)(stuff&0x00000007);

  // last two rows
  stuff = *(cast(const(uint)*)&(alphaBlock.stuff.ptr[3])); // last 3 bytes

  bits.ptr[2].ptr[0] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[2].ptr[1] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[2].ptr[2] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[2].ptr[3] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[3].ptr[0] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[3].ptr[1] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[3].ptr[2] = cast(ubyte)(stuff&0x00000007);
  stuff >>= 3;
  bits.ptr[3].ptr[3] = cast(ubyte)(stuff&0x00000007);

  // decode the codes into alpha values
  for (row = 0; row < 4; ++row) {
    for (pix = 0; pix < 4; ++pix) {
      aColors.ptr[row].ptr[pix].r = 0;
      aColors.ptr[row].ptr[pix].g = 0;
      aColors.ptr[row].ptr[pix].b = 0;
      aColors.ptr[row].ptr[pix].a = cast(ubyte)alphas.ptr[bits.ptr[row].ptr[pix]];
    }
  }

  // write out alpha values to the image bits
  for (row = 0; row < 4; ++row, pixel += width-4) {
    for (pix = 0; pix < 4; ++pix) {
      // zero the alpha bits of image pixel
      *pixel &= alphaZero;
      // or the bits into the prev. nulled alpha
      *pixel |= *(cast(const(uint)*)&(aColors.ptr[row].ptr[pix]));
      ++pixel;
    }
  }
}


// decompresses a dxt1 format texture
private bool DDSDecompressDXT1 (const(ddsBuffer_t)* dds, int width, int height, Color* pixels) {
  Color[4] colors;
  immutable int xBlocks = width/4;
  immutable int yBlocks = height/4;
  // 8 bytes per block
  auto block = cast(const(ddsColorBlock_t)*)dds.data.ptr;
  foreach (immutable y; 0..yBlocks) {
    foreach (immutable x; 0..xBlocks) {
      DDSGetColorBlockColors(block, colors.ptr);
      auto pixel = cast(uint*)(pixels+x*4+(y*4)*width);
      DDSDecodeColorBlock(pixel, block, width, colors.ptr);
      ++block;
    }
  }
  // return ok
  return true;
}


// decompresses a dxt3 format texture
private bool DDSDecompressDXT3 (const(ddsBuffer_t)* dds, int width, int height, Color* pixels) {
  Color[4] colors;

  // setup
  immutable int xBlocks = width/4;
  immutable int yBlocks = height/4;

  // create zero alpha
  colors.ptr[0].a = 0;
  colors.ptr[0].r = 0xFF;
  colors.ptr[0].g = 0xFF;
  colors.ptr[0].b = 0xFF;
  immutable uint alphaZero = colors.ptr[0].asUint;

  // 8 bytes per block, 1 block for alpha, 1 block for color
  auto block = cast(const(ddsColorBlock_t)*)dds.data.ptr;
  foreach (immutable y; 0..yBlocks) {
    foreach (immutable x; 0..xBlocks) {
      // get alpha block
      auto alphaBlock = cast(const(ddsAlphaBlockExplicit_t)*)block++;
      // get color block
      DDSGetColorBlockColors(block, colors.ptr);
      // decode color block
      auto pixel = cast(uint*)(pixels+x*4+(y*4)*width);
      DDSDecodeColorBlock(pixel, block, width, colors.ptr);
      // overwrite alpha bits with alpha block
      DDSDecodeAlphaExplicit(pixel, alphaBlock, width, alphaZero);
      ++block;
    }
  }

  // return ok
  return true;
}


// decompresses a dxt5 format texture
private bool DDSDecompressDXT5 (const(ddsBuffer_t)* dds, int width, int height, Color* pixels) {
  Color[4] colors;

  // setup
  immutable int xBlocks = width/4;
  immutable int yBlocks = height/4;

  // create zero alpha
  colors.ptr[0].a = 0;
  colors.ptr[0].r = 0xFF;
  colors.ptr[0].g = 0xFF;
  colors.ptr[0].b = 0xFF;
  immutable uint alphaZero = colors.ptr[0].asUint;

  // 8 bytes per block, 1 block for alpha, 1 block for color
  auto block = cast(const(ddsColorBlock_t)*)dds.data.ptr;
  foreach (immutable y; 0..yBlocks) {
    //block = cast(ddsColorBlock_t*)(dds.data.ptr+y*xBlocks*16);
    foreach (immutable x; 0..xBlocks) {
      // get alpha block
      auto alphaBlock = cast(const(ddsAlphaBlock3BitLinear_t)*)block++;
      // get color block
      DDSGetColorBlockColors(block, colors.ptr);
      // decode color block
      auto pixel = cast(uint*)(pixels+x*4+(y*4)*width);
      DDSDecodeColorBlock(pixel, block, width, colors.ptr);
      // overwrite alpha bits with alpha block
      DDSDecodeAlpha3BitLinear(pixel, alphaBlock, width, alphaZero);
      ++block;
    }
  }

  // return ok
  return true;
}


private void unmultiply (Color[] pixels) {
  // premultiplied alpha
  foreach (ref Color clr; pixels) {
    if (clr.a != 0) {
      clr.r = Color.clampToByte(clr.r*255/clr.a);
      clr.g = Color.clampToByte(clr.g*255/clr.a);
      clr.b = Color.clampToByte(clr.b*255/clr.a);
    }
  }
}


// decompresses a dxt2 format texture (FIXME: un-premultiply alpha)
private bool DDSDecompressDXT2 (const(ddsBuffer_t)* dds, int width, int height, Color* pixels) {
  // decompress dxt3 first
  if (!DDSDecompressDXT3(dds, width, height, pixels)) return false;
  //FIXME: is un-premultiply correct?
  unmultiply(pixels[0..width*height]);
  return true;
}


// decompresses a dxt4 format texture (FIXME: un-premultiply alpha)
private bool DDSDecompressDXT4 (const(ddsBuffer_t)* dds, int width, int height, Color* pixels) {
  // decompress dxt5 first
  if (!DDSDecompressDXT5(dds, width, height, pixels)) return false;
  //FIXME: is un-premultiply correct?
  unmultiply(pixels[0..width*height]);
  return true;
}


// decompresses an argb 8888 format texture
private bool DDSDecompressARGB8888 (const(ddsBuffer_t)* dds, int width, int height, Color* pixels) {
  auto zin = cast(const(Color)*)dds.data.ptr;
  //pixels[0..width*height] = zin[0..width*height];
  foreach (immutable idx; 0..width*height) {
    pixels.r = zin.b;
    pixels.g = zin.g;
    pixels.b = zin.r;
    pixels.a = zin.a;
    ++pixels;
    ++zin;
  }
  return true;
}


// decompresses an rgb 888 format texture
private bool DDSDecompressRGB888 (const(ddsBuffer_t)* dds, int width, int height, Color* pixels) {
  auto zin = cast(const(ubyte)*)dds.data.ptr;
  //pixels[0..width*height] = zin[0..width*height];
  foreach (immutable idx; 0..width*height) {
    pixels.b = *zin++;
    pixels.g = *zin++;
    pixels.r = *zin++;
    pixels.a = 255;
    ++pixels;
  }
  return true;
}
