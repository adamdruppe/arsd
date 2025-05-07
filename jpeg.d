// jpgd.h - C++ class for JPEG decompression.
// Rich Geldreich <richgel99@gmail.com>
// Alex Evans: Linear memory allocator (taken from jpge.h).
// v1.04, May. 19, 2012: Code tweaks to fix VS2008 static code analysis warnings (all looked harmless)
// D translation by Ketmar // Invisible Vector
//
// This is free and unencumbered software released into the public domain.
//
// Anyone is free to copy, modify, publish, use, compile, sell, or
// distribute this software, either in source code form or as a compiled
// binary, for any purpose, commercial or non-commercial, and by any
// means.
//
// In jurisdictions that recognize copyright laws, the author or authors
// of this software dedicate any and all copyright interest in the
// software to the public domain. We make this dedication for the benefit
// of the public at large and to the detriment of our heirs and
// successors. We intend this dedication to be an overt act of
// relinquishment in perpetuity of all present and future rights to this
// software under copyright law.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
// OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//
// For more information, please refer to <http://unlicense.org/>
//
// Supports progressive and baseline sequential JPEG image files, and the most common chroma subsampling factors: Y, H1V1, H2V1, H1V2, and H2V2.
//
// Chroma upsampling quality: H2V2 is upsampled in the frequency domain, H2V1 and H1V2 are upsampled using point sampling.
// Chroma upsampling reference: "Fast Scheme for Image Size Change in the Compressed Domain"
// http://vision.ai.uiuc.edu/~dugad/research/dct/index.html
/**
 * Loads a JPEG image from a memory buffer or a file.
 *
 * req_comps can be 1 (grayscale), 3 (RGB), or 4 (RGBA).
 * On return, width/height will be set to the image's dimensions, and actual_comps will be set to the either 1 (grayscale) or 3 (RGB).
 * Requesting a 8 or 32bpp image is currently a little faster than 24bpp because the jpeg_decoder class itself currently always unpacks to either 8 or 32bpp.
 */
module arsd.jpeg;

@system:

// Set to 1 to enable freq. domain chroma upsampling on images using H2V2 subsampling (0=faster nearest neighbor sampling).
// This is slower, but results in higher quality on images with highly saturated colors.
version = JPGD_SUPPORT_FREQ_DOMAIN_UPSAMPLING;

/// Input stream interface.
/// This delegate is called when the internal input buffer is empty.
/// Parameters:
///   pBuf - input buffer
///   max_bytes_to_read - maximum bytes that can be written to pBuf
///   pEOF_flag - set this to true if at end of stream (no more bytes remaining)
///   Returns -1 on error, otherwise return the number of bytes actually written to the buffer (which may be 0).
///   Notes: This delegate will be called in a loop until you set *pEOF_flag to true or the internal buffer is full.
alias JpegStreamReadFunc = int delegate (void* pBuf, int max_bytes_to_read, bool* pEOF_flag);


// ////////////////////////////////////////////////////////////////////////// //
private:
void *jpgd_malloc (size_t nSize) { import core.stdc.stdlib : malloc; return malloc(nSize); }
void jpgd_free (void *p) { import core.stdc.stdlib : free; if (p !is null) free(p); }

// Success/failure error codes.
alias jpgd_status = int;
enum /*jpgd_status*/ {
  JPGD_SUCCESS = 0, JPGD_FAILED = -1, JPGD_DONE = 1,
  JPGD_BAD_DHT_COUNTS = -256, JPGD_BAD_DHT_INDEX, JPGD_BAD_DHT_MARKER, JPGD_BAD_DQT_MARKER, JPGD_BAD_DQT_TABLE,
  JPGD_BAD_PRECISION, JPGD_BAD_HEIGHT, JPGD_BAD_WIDTH, JPGD_TOO_MANY_COMPONENTS,
  JPGD_BAD_SOF_LENGTH, JPGD_BAD_VARIABLE_MARKER, JPGD_BAD_DRI_LENGTH, JPGD_BAD_SOS_LENGTH,
  JPGD_BAD_SOS_COMP_ID, JPGD_W_EXTRA_BYTES_BEFORE_MARKER, JPGD_NO_ARITHMITIC_SUPPORT, JPGD_UNEXPECTED_MARKER,
  JPGD_NOT_JPEG, JPGD_UNSUPPORTED_MARKER, JPGD_BAD_DQT_LENGTH, JPGD_TOO_MANY_BLOCKS,
  JPGD_UNDEFINED_QUANT_TABLE, JPGD_UNDEFINED_HUFF_TABLE, JPGD_NOT_SINGLE_SCAN, JPGD_UNSUPPORTED_COLORSPACE,
  JPGD_UNSUPPORTED_SAMP_FACTORS, JPGD_DECODE_ERROR, JPGD_BAD_RESTART_MARKER, JPGD_ASSERTION_ERROR,
  JPGD_BAD_SOS_SPECTRAL, JPGD_BAD_SOS_SUCCESSIVE, JPGD_STREAM_READ, JPGD_NOTENOUGHMEM,
}

enum {
  JPGD_IN_BUF_SIZE = 8192, JPGD_MAX_BLOCKS_PER_MCU = 10, JPGD_MAX_HUFF_TABLES = 8, JPGD_MAX_QUANT_TABLES = 4,
  JPGD_MAX_COMPONENTS = 4, JPGD_MAX_COMPS_IN_SCAN = 4, JPGD_MAX_BLOCKS_PER_ROW = 8192, JPGD_MAX_HEIGHT = 16384, JPGD_MAX_WIDTH = 16384,
}

// DCT coefficients are stored in this sequence.
static immutable int[64] g_ZAG = [  0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63 ];

alias JPEG_MARKER = int;
enum /*JPEG_MARKER*/ {
  M_SOF0  = 0xC0, M_SOF1  = 0xC1, M_SOF2  = 0xC2, M_SOF3  = 0xC3, M_SOF5  = 0xC5, M_SOF6  = 0xC6, M_SOF7  = 0xC7, M_JPG   = 0xC8,
  M_SOF9  = 0xC9, M_SOF10 = 0xCA, M_SOF11 = 0xCB, M_SOF13 = 0xCD, M_SOF14 = 0xCE, M_SOF15 = 0xCF, M_DHT   = 0xC4, M_DAC   = 0xCC,
  M_RST0  = 0xD0, M_RST1  = 0xD1, M_RST2  = 0xD2, M_RST3  = 0xD3, M_RST4  = 0xD4, M_RST5  = 0xD5, M_RST6  = 0xD6, M_RST7  = 0xD7,
  M_SOI   = 0xD8, M_EOI   = 0xD9, M_SOS   = 0xDA, M_DQT   = 0xDB, M_DNL   = 0xDC, M_DRI   = 0xDD, M_DHP   = 0xDE, M_EXP   = 0xDF,
  M_APP0  = 0xE0, M_APP15 = 0xEF, M_JPG0  = 0xF0, M_JPG13 = 0xFD, M_COM   = 0xFE, M_TEM   = 0x01, M_ERROR = 0x100, RST0   = 0xD0,
  M_APP1  = 0xE1,
}

alias JPEG_SUBSAMPLING = int;
enum /*JPEG_SUBSAMPLING*/ { JPGD_GRAYSCALE = 0, JPGD_YH1V1, JPGD_YH2V1, JPGD_YH1V2, JPGD_YH2V2 }

enum CONST_BITS = 13;
enum PASS1_BITS = 2;
enum SCALEDONE = cast(int)1;

enum FIX_0_298631336 = cast(int)2446;  /* FIX(0.298631336) */
enum FIX_0_390180644 = cast(int)3196;  /* FIX(0.390180644) */
enum FIX_0_541196100 = cast(int)4433;  /* FIX(0.541196100) */
enum FIX_0_765366865 = cast(int)6270;  /* FIX(0.765366865) */
enum FIX_0_899976223 = cast(int)7373;  /* FIX(0.899976223) */
enum FIX_1_175875602 = cast(int)9633;  /* FIX(1.175875602) */
enum FIX_1_501321110 = cast(int)12299; /* FIX(1.501321110) */
enum FIX_1_847759065 = cast(int)15137; /* FIX(1.847759065) */
enum FIX_1_961570560 = cast(int)16069; /* FIX(1.961570560) */
enum FIX_2_053119869 = cast(int)16819; /* FIX(2.053119869) */
enum FIX_2_562915447 = cast(int)20995; /* FIX(2.562915447) */
enum FIX_3_072711026 = cast(int)25172; /* FIX(3.072711026) */

int DESCALE() (int x, int n) { pragma(inline, true); return (((x) + (SCALEDONE << ((n)-1))) >> (n)); }
int DESCALE_ZEROSHIFT() (int x, int n) { pragma(inline, true); return (((x) + (128 << (n)) + (SCALEDONE << ((n)-1))) >> (n)); }
ubyte CLAMP() (int i) { pragma(inline, true); return cast(ubyte)(cast(uint)i > 255 ? (((~i) >> 31) & 0xFF) : i); }


// Compiler creates a fast path 1D IDCT for X non-zero columns
struct Row(int NONZERO_COLS) {
pure nothrow @trusted @nogc:
  static void idct(int* pTemp, const(jpeg_decoder.jpgd_block_t)* pSrc) {
    static if (NONZERO_COLS == 0) {
      // nothing
    } else static if (NONZERO_COLS == 1) {
      immutable int dcval = (pSrc[0] << PASS1_BITS);
      pTemp[0] = dcval;
      pTemp[1] = dcval;
      pTemp[2] = dcval;
      pTemp[3] = dcval;
      pTemp[4] = dcval;
      pTemp[5] = dcval;
      pTemp[6] = dcval;
      pTemp[7] = dcval;
    } else {
      // ACCESS_COL() will be optimized at compile time to either an array access, or 0.
      //#define ACCESS_COL(x) (((x) < NONZERO_COLS) ? (int)pSrc[x] : 0)
      template ACCESS_COL(int x) {
        static if (x < NONZERO_COLS) enum ACCESS_COL = "cast(int)pSrc["~x.stringof~"]"; else enum ACCESS_COL = "0";
      }

      immutable int z2 = mixin(ACCESS_COL!2), z3 = mixin(ACCESS_COL!6);

      immutable int z1 = (z2 + z3)*FIX_0_541196100;
      immutable int tmp2 = z1 + z3*(-FIX_1_847759065);
      immutable int tmp3 = z1 + z2*FIX_0_765366865;

      immutable int tmp0 = (mixin(ACCESS_COL!0) + mixin(ACCESS_COL!4)) << CONST_BITS;
      immutable int tmp1 = (mixin(ACCESS_COL!0) - mixin(ACCESS_COL!4)) << CONST_BITS;

      immutable int tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;

      immutable int atmp0 = mixin(ACCESS_COL!7), atmp1 = mixin(ACCESS_COL!5), atmp2 = mixin(ACCESS_COL!3), atmp3 = mixin(ACCESS_COL!1);

      immutable int bz1 = atmp0 + atmp3, bz2 = atmp1 + atmp2, bz3 = atmp0 + atmp2, bz4 = atmp1 + atmp3;
      immutable int bz5 = (bz3 + bz4)*FIX_1_175875602;

      immutable int az1 = bz1*(-FIX_0_899976223);
      immutable int az2 = bz2*(-FIX_2_562915447);
      immutable int az3 = bz3*(-FIX_1_961570560) + bz5;
      immutable int az4 = bz4*(-FIX_0_390180644) + bz5;

      immutable int btmp0 = atmp0*FIX_0_298631336 + az1 + az3;
      immutable int btmp1 = atmp1*FIX_2_053119869 + az2 + az4;
      immutable int btmp2 = atmp2*FIX_3_072711026 + az2 + az3;
      immutable int btmp3 = atmp3*FIX_1_501321110 + az1 + az4;

      pTemp[0] = DESCALE(tmp10 + btmp3, CONST_BITS-PASS1_BITS);
      pTemp[7] = DESCALE(tmp10 - btmp3, CONST_BITS-PASS1_BITS);
      pTemp[1] = DESCALE(tmp11 + btmp2, CONST_BITS-PASS1_BITS);
      pTemp[6] = DESCALE(tmp11 - btmp2, CONST_BITS-PASS1_BITS);
      pTemp[2] = DESCALE(tmp12 + btmp1, CONST_BITS-PASS1_BITS);
      pTemp[5] = DESCALE(tmp12 - btmp1, CONST_BITS-PASS1_BITS);
      pTemp[3] = DESCALE(tmp13 + btmp0, CONST_BITS-PASS1_BITS);
      pTemp[4] = DESCALE(tmp13 - btmp0, CONST_BITS-PASS1_BITS);
    }
  }
}


// Compiler creates a fast path 1D IDCT for X non-zero rows
struct Col (int NONZERO_ROWS) {
pure nothrow @trusted @nogc:
  static void idct(ubyte* pDst_ptr, const(int)* pTemp) {
    static assert(NONZERO_ROWS > 0);
    static if (NONZERO_ROWS == 1) {
      int dcval = DESCALE_ZEROSHIFT(pTemp[0], PASS1_BITS+3);
      immutable ubyte dcval_clamped = cast(ubyte)CLAMP(dcval);
      pDst_ptr[0*8] = dcval_clamped;
      pDst_ptr[1*8] = dcval_clamped;
      pDst_ptr[2*8] = dcval_clamped;
      pDst_ptr[3*8] = dcval_clamped;
      pDst_ptr[4*8] = dcval_clamped;
      pDst_ptr[5*8] = dcval_clamped;
      pDst_ptr[6*8] = dcval_clamped;
      pDst_ptr[7*8] = dcval_clamped;
    } else {
      // ACCESS_ROW() will be optimized at compile time to either an array access, or 0.
      //#define ACCESS_ROW(x) (((x) < NONZERO_ROWS) ? pTemp[x * 8] : 0)
      template ACCESS_ROW(int x) {
        static if (x < NONZERO_ROWS) enum ACCESS_ROW = "pTemp["~(x*8).stringof~"]"; else enum ACCESS_ROW = "0";
      }

      immutable int z2 = mixin(ACCESS_ROW!2);
      immutable int z3 = mixin(ACCESS_ROW!6);

      immutable int z1 = (z2 + z3)*FIX_0_541196100;
      immutable int tmp2 = z1 + z3*(-FIX_1_847759065);
      immutable int tmp3 = z1 + z2*FIX_0_765366865;

      immutable int tmp0 = (mixin(ACCESS_ROW!0) + mixin(ACCESS_ROW!4)) << CONST_BITS;
      immutable int tmp1 = (mixin(ACCESS_ROW!0) - mixin(ACCESS_ROW!4)) << CONST_BITS;

      immutable int tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;

      immutable int atmp0 = mixin(ACCESS_ROW!7), atmp1 = mixin(ACCESS_ROW!5), atmp2 = mixin(ACCESS_ROW!3), atmp3 = mixin(ACCESS_ROW!1);

      immutable int bz1 = atmp0 + atmp3, bz2 = atmp1 + atmp2, bz3 = atmp0 + atmp2, bz4 = atmp1 + atmp3;
      immutable int bz5 = (bz3 + bz4)*FIX_1_175875602;

      immutable int az1 = bz1*(-FIX_0_899976223);
      immutable int az2 = bz2*(-FIX_2_562915447);
      immutable int az3 = bz3*(-FIX_1_961570560) + bz5;
      immutable int az4 = bz4*(-FIX_0_390180644) + bz5;

      immutable int btmp0 = atmp0*FIX_0_298631336 + az1 + az3;
      immutable int btmp1 = atmp1*FIX_2_053119869 + az2 + az4;
      immutable int btmp2 = atmp2*FIX_3_072711026 + az2 + az3;
      immutable int btmp3 = atmp3*FIX_1_501321110 + az1 + az4;

      int i = DESCALE_ZEROSHIFT(tmp10 + btmp3, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*0] = cast(ubyte)CLAMP(i);

      i = DESCALE_ZEROSHIFT(tmp10 - btmp3, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*7] = cast(ubyte)CLAMP(i);

      i = DESCALE_ZEROSHIFT(tmp11 + btmp2, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*1] = cast(ubyte)CLAMP(i);

      i = DESCALE_ZEROSHIFT(tmp11 - btmp2, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*6] = cast(ubyte)CLAMP(i);

      i = DESCALE_ZEROSHIFT(tmp12 + btmp1, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*2] = cast(ubyte)CLAMP(i);

      i = DESCALE_ZEROSHIFT(tmp12 - btmp1, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*5] = cast(ubyte)CLAMP(i);

      i = DESCALE_ZEROSHIFT(tmp13 + btmp0, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*3] = cast(ubyte)CLAMP(i);

      i = DESCALE_ZEROSHIFT(tmp13 - btmp0, CONST_BITS+PASS1_BITS+3);
      pDst_ptr[8*4] = cast(ubyte)CLAMP(i);
    }
  }
}


static immutable ubyte[512] s_idct_row_table = [
  1,0,0,0,0,0,0,0, 2,0,0,0,0,0,0,0, 2,1,0,0,0,0,0,0, 2,1,1,0,0,0,0,0, 2,2,1,0,0,0,0,0, 3,2,1,0,0,0,0,0, 4,2,1,0,0,0,0,0, 4,3,1,0,0,0,0,0,
  4,3,2,0,0,0,0,0, 4,3,2,1,0,0,0,0, 4,3,2,1,1,0,0,0, 4,3,2,2,1,0,0,0, 4,3,3,2,1,0,0,0, 4,4,3,2,1,0,0,0, 5,4,3,2,1,0,0,0, 6,4,3,2,1,0,0,0,
  6,5,3,2,1,0,0,0, 6,5,4,2,1,0,0,0, 6,5,4,3,1,0,0,0, 6,5,4,3,2,0,0,0, 6,5,4,3,2,1,0,0, 6,5,4,3,2,1,1,0, 6,5,4,3,2,2,1,0, 6,5,4,3,3,2,1,0,
  6,5,4,4,3,2,1,0, 6,5,5,4,3,2,1,0, 6,6,5,4,3,2,1,0, 7,6,5,4,3,2,1,0, 8,6,5,4,3,2,1,0, 8,7,5,4,3,2,1,0, 8,7,6,4,3,2,1,0, 8,7,6,5,3,2,1,0,
  8,7,6,5,4,2,1,0, 8,7,6,5,4,3,1,0, 8,7,6,5,4,3,2,0, 8,7,6,5,4,3,2,1, 8,7,6,5,4,3,2,2, 8,7,6,5,4,3,3,2, 8,7,6,5,4,4,3,2, 8,7,6,5,5,4,3,2,
  8,7,6,6,5,4,3,2, 8,7,7,6,5,4,3,2, 8,8,7,6,5,4,3,2, 8,8,8,6,5,4,3,2, 8,8,8,7,5,4,3,2, 8,8,8,7,6,4,3,2, 8,8,8,7,6,5,3,2, 8,8,8,7,6,5,4,2,
  8,8,8,7,6,5,4,3, 8,8,8,7,6,5,4,4, 8,8,8,7,6,5,5,4, 8,8,8,7,6,6,5,4, 8,8,8,7,7,6,5,4, 8,8,8,8,7,6,5,4, 8,8,8,8,8,6,5,4, 8,8,8,8,8,7,5,4,
  8,8,8,8,8,7,6,4, 8,8,8,8,8,7,6,5, 8,8,8,8,8,7,6,6, 8,8,8,8,8,7,7,6, 8,8,8,8,8,8,7,6, 8,8,8,8,8,8,8,6, 8,8,8,8,8,8,8,7, 8,8,8,8,8,8,8,8,
];

static immutable ubyte[64] s_idct_col_table = [ 1, 1, 2, 3, 3, 3, 3, 3, 3, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8 ];

void idct() (const(jpeg_decoder.jpgd_block_t)* pSrc_ptr, ubyte* pDst_ptr, int block_max_zag) {
  assert(block_max_zag >= 1);
  assert(block_max_zag <= 64);

  if (block_max_zag <= 1)
  {
    int k = ((pSrc_ptr[0] + 4) >> 3) + 128;
    k = CLAMP(k);
    k = k | (k<<8);
    k = k | (k<<16);

    for (int i = 8; i > 0; i--)
    {
      *cast(int*)&pDst_ptr[0] = k;
      *cast(int*)&pDst_ptr[4] = k;
      pDst_ptr += 8;
    }
    return;
  }

  int[64] temp;

  const(jpeg_decoder.jpgd_block_t)* pSrc = pSrc_ptr;
  int* pTemp = temp.ptr;

  const(ubyte)* pRow_tab = &s_idct_row_table.ptr[(block_max_zag - 1) * 8];
  int i;
  for (i = 8; i > 0; i--, pRow_tab++)
  {
    switch (*pRow_tab)
    {
      case 0: Row!(0).idct(pTemp, pSrc); break;
      case 1: Row!(1).idct(pTemp, pSrc); break;
      case 2: Row!(2).idct(pTemp, pSrc); break;
      case 3: Row!(3).idct(pTemp, pSrc); break;
      case 4: Row!(4).idct(pTemp, pSrc); break;
      case 5: Row!(5).idct(pTemp, pSrc); break;
      case 6: Row!(6).idct(pTemp, pSrc); break;
      case 7: Row!(7).idct(pTemp, pSrc); break;
      case 8: Row!(8).idct(pTemp, pSrc); break;
      default: assert(0);
    }

    pSrc += 8;
    pTemp += 8;
  }

  pTemp = temp.ptr;

  immutable int nonzero_rows = s_idct_col_table.ptr[block_max_zag - 1];
  for (i = 8; i > 0; i--)
  {
    switch (nonzero_rows)
    {
      case 1: Col!(1).idct(pDst_ptr, pTemp); break;
      case 2: Col!(2).idct(pDst_ptr, pTemp); break;
      case 3: Col!(3).idct(pDst_ptr, pTemp); break;
      case 4: Col!(4).idct(pDst_ptr, pTemp); break;
      case 5: Col!(5).idct(pDst_ptr, pTemp); break;
      case 6: Col!(6).idct(pDst_ptr, pTemp); break;
      case 7: Col!(7).idct(pDst_ptr, pTemp); break;
      case 8: Col!(8).idct(pDst_ptr, pTemp); break;
      default: assert(0);
    }

    pTemp++;
    pDst_ptr++;
  }
}

void idct_4x4() (const(jpeg_decoder.jpgd_block_t)* pSrc_ptr, ubyte* pDst_ptr) {
  int[64] temp;
  int* pTemp = temp.ptr;
  const(jpeg_decoder.jpgd_block_t)* pSrc = pSrc_ptr;

  for (int i = 4; i > 0; i--)
  {
    Row!(4).idct(pTemp, pSrc);
    pSrc += 8;
    pTemp += 8;
  }

  pTemp = temp.ptr;
  for (int i = 8; i > 0; i--)
  {
    Col!(4).idct(pDst_ptr, pTemp);
    pTemp++;
    pDst_ptr++;
  }
}


// ////////////////////////////////////////////////////////////////////////// //
struct jpeg_decoder {
private import core.stdc.string : memcpy, memset;
private:
  static auto JPGD_MIN(T) (T a, T b) pure nothrow @safe @nogc { pragma(inline, true); return (a < b ? a : b); }
  static auto JPGD_MAX(T) (T a, T b) pure nothrow @safe @nogc { pragma(inline, true); return (a > b ? a : b); }

  alias jpgd_quant_t = short;
  alias jpgd_block_t = short;
  alias pDecode_block_func = void function (ref jpeg_decoder, int, int, int);

  static struct huff_tables {
    bool ac_table;
    uint[256] look_up;
    uint[256] look_up2;
    ubyte[256] code_size;
    uint[512] tree;
  }

  static struct coeff_buf {
    ubyte* pData;
    int block_num_x, block_num_y;
    int block_len_x, block_len_y;
    int block_size;
  }

  static struct mem_block {
    mem_block* m_pNext;
    size_t m_used_count;
    size_t m_size;
    char[1] m_data;
  }

  mem_block* m_pMem_blocks;
  int m_image_x_size;
  int m_image_y_size;
  JpegStreamReadFunc readfn;
  int m_progressive_flag;
  ubyte[JPGD_MAX_HUFF_TABLES] m_huff_ac;
  ubyte*[JPGD_MAX_HUFF_TABLES] m_huff_num;      // pointer to number of Huffman codes per bit size
  ubyte*[JPGD_MAX_HUFF_TABLES] m_huff_val;      // pointer to Huffman codes per bit size
  jpgd_quant_t*[JPGD_MAX_QUANT_TABLES] m_quant; // pointer to quantization tables
  int m_scan_type;                              // Gray, Yh1v1, Yh1v2, Yh2v1, Yh2v2 (CMYK111, CMYK4114 no longer supported)
  int m_comps_in_frame;                         // # of components in frame
  int[JPGD_MAX_COMPONENTS] m_comp_h_samp;       // component's horizontal sampling factor
  int[JPGD_MAX_COMPONENTS] m_comp_v_samp;       // component's vertical sampling factor
  int[JPGD_MAX_COMPONENTS] m_comp_quant;        // component's quantization table selector
  int[JPGD_MAX_COMPONENTS] m_comp_ident;        // component's ID
  int[JPGD_MAX_COMPONENTS] m_comp_h_blocks;
  int[JPGD_MAX_COMPONENTS] m_comp_v_blocks;
  int m_comps_in_scan;                          // # of components in scan
  int[JPGD_MAX_COMPS_IN_SCAN] m_comp_list;      // components in this scan
  int[JPGD_MAX_COMPONENTS] m_comp_dc_tab;       // component's DC Huffman coding table selector
  int[JPGD_MAX_COMPONENTS] m_comp_ac_tab;       // component's AC Huffman coding table selector
  int m_spectral_start;                         // spectral selection start
  int m_spectral_end;                           // spectral selection end
  int m_successive_low;                         // successive approximation low
  int m_successive_high;                        // successive approximation high
  int m_max_mcu_x_size;                         // MCU's max. X size in pixels
  int m_max_mcu_y_size;                         // MCU's max. Y size in pixels
  int m_blocks_per_mcu;
  int m_max_blocks_per_row;
  int m_mcus_per_row, m_mcus_per_col;
  int[JPGD_MAX_BLOCKS_PER_MCU] m_mcu_org;
  int m_total_lines_left;                       // total # lines left in image
  int m_mcu_lines_left;                         // total # lines left in this MCU
  int m_real_dest_bytes_per_scan_line;
  int m_dest_bytes_per_scan_line;               // rounded up
  int m_dest_bytes_per_pixel;                   // 4 (RGB) or 1 (Y)
  huff_tables*[JPGD_MAX_HUFF_TABLES] m_pHuff_tabs;
  coeff_buf*[JPGD_MAX_COMPONENTS] m_dc_coeffs;
  coeff_buf*[JPGD_MAX_COMPONENTS] m_ac_coeffs;
  int m_eob_run;
  int[JPGD_MAX_COMPONENTS] m_block_y_mcu;
  ubyte* m_pIn_buf_ofs;
  int m_in_buf_left;
  int m_tem_flag;
  bool m_eof_flag;
  ubyte[128] m_in_buf_pad_start;
  ubyte[JPGD_IN_BUF_SIZE+128] m_in_buf;
  ubyte[128] m_in_buf_pad_end;
  int m_bits_left;
  uint m_bit_buf;
  int m_restart_interval;
  int m_restarts_left;
  int m_next_restart_num;
  int m_max_mcus_per_row;
  int m_max_blocks_per_mcu;
  int m_expanded_blocks_per_mcu;
  int m_expanded_blocks_per_row;
  int m_expanded_blocks_per_component;
  bool m_freq_domain_chroma_upsample;
  int m_max_mcus_per_col;
  uint[JPGD_MAX_COMPONENTS] m_last_dc_val;
  jpgd_block_t* m_pMCU_coefficients;
  int[JPGD_MAX_BLOCKS_PER_MCU] m_mcu_block_max_zag;
  ubyte* m_pSample_buf;
  int[256] m_crr;
  int[256] m_cbb;
  int[256] m_crg;
  int[256] m_cbg;
  ubyte* m_pScan_line_0;
  ubyte* m_pScan_line_1;
  jpgd_status m_error_code;
  bool m_ready_flag;
  int m_total_bytes_read;

public:
  // Inspect `error_code` after constructing to determine if the stream is valid or not. You may look at the `width`, `height`, etc.
  // methods after the constructor is called. You may then either destruct the object, or begin decoding the image by calling begin_decoding(), then decode() on each scanline.
  this (JpegStreamReadFunc rfn) { decode_init(rfn); }

  ~this () { free_all_blocks(); }

  @disable this (this); // no copies

  // Call this method after constructing the object to begin decompression.
  // If JPGD_SUCCESS is returned you may then call decode() on each scanline.
  int begin_decoding () {
    if (m_ready_flag) return JPGD_SUCCESS;
    if (m_error_code) return JPGD_FAILED;
    try {
      decode_start();
      m_ready_flag = true;
      return JPGD_SUCCESS;
    } catch (Exception e) {
      //version(jpegd_test) {{ import core.stdc.stdio; stderr.fprintf("ERROR: %.*s...\n", cast(int)e.msg.length, e.msg.ptr); }}
      version(jpegd_test) {{ import std.stdio; stderr.writeln(e.toString); }}
    }
    return JPGD_FAILED;
  }

  // Returns the next scan line.
  // For grayscale images, pScan_line will point to a buffer containing 8-bit pixels (`bytes_per_pixel` will return 1).
  // Otherwise, it will always point to a buffer containing 32-bit RGBA pixels (A will always be 255, and `bytes_per_pixel` will return 4).
  // Returns JPGD_SUCCESS if a scan line has been returned.
  // Returns JPGD_DONE if all scan lines have been returned.
  // Returns JPGD_FAILED if an error occurred. Inspect `error_code` for a more info.
  int decode (/*const void** */void** pScan_line, uint* pScan_line_len) {
    if (m_error_code || !m_ready_flag) return JPGD_FAILED;
    if (m_total_lines_left == 0) return JPGD_DONE;
    try {
      if (m_mcu_lines_left == 0) {
        if (m_progressive_flag) load_next_row(); else decode_next_row();
        // Find the EOI marker if that was the last row.
        if (m_total_lines_left <= m_max_mcu_y_size) find_eoi();
        m_mcu_lines_left = m_max_mcu_y_size;
      }
      if (m_freq_domain_chroma_upsample) {
        expanded_convert();
        *pScan_line = m_pScan_line_0;
      } else {
        switch (m_scan_type) {
          case JPGD_YH2V2:
            if ((m_mcu_lines_left & 1) == 0) {
              H2V2Convert();
              *pScan_line = m_pScan_line_0;
            } else {
              *pScan_line = m_pScan_line_1;
            }
            break;
          case JPGD_YH2V1:
            H2V1Convert();
            *pScan_line = m_pScan_line_0;
            break;
          case JPGD_YH1V2:
            if ((m_mcu_lines_left & 1) == 0) {
              H1V2Convert();
              *pScan_line = m_pScan_line_0;
            } else {
              *pScan_line = m_pScan_line_1;
            }
            break;
          case JPGD_YH1V1:
            H1V1Convert();
            *pScan_line = m_pScan_line_0;
            break;
          case JPGD_GRAYSCALE:
            gray_convert();
            *pScan_line = m_pScan_line_0;
            break;
          default:
        }
      }
      *pScan_line_len = m_real_dest_bytes_per_scan_line;
      --m_mcu_lines_left;
      --m_total_lines_left;
      return JPGD_SUCCESS;
    } catch (Exception) {}
    return JPGD_FAILED;
  }

  @property const pure nothrow @trusted @nogc {
    jpgd_status error_code () { pragma(inline, true); return m_error_code; }

    int width () { pragma(inline, true); return m_image_x_size; }
    int height () { pragma(inline, true); return m_image_y_size; }

    int num_components () { pragma(inline, true); return m_comps_in_frame; }

    int bytes_per_pixel () { pragma(inline, true); return m_dest_bytes_per_pixel; }
    int bytes_per_scan_line () { pragma(inline, true); return m_image_x_size * bytes_per_pixel(); }

    // Returns the total number of bytes actually consumed by the decoder (which should equal the actual size of the JPEG file).
    int total_bytes_read () { pragma(inline, true); return m_total_bytes_read; }
  }

private:
  // Retrieve one character from the input stream.
  uint get_char () {
    // Any bytes remaining in buffer?
    if (!m_in_buf_left) {
      // Try to get more bytes.
      prep_in_buffer();
      // Still nothing to get?
      if (!m_in_buf_left) {
        // Pad the end of the stream with 0xFF 0xD9 (EOI marker)
        int t = m_tem_flag;
        m_tem_flag ^= 1;
        return (t ? 0xD9 : 0xFF);
      }
    }
    uint c = *m_pIn_buf_ofs++;
    --m_in_buf_left;
    return c;
  }

  // Same as previous method, except can indicate if the character is a pad character or not.
  uint get_char (bool* pPadding_flag) {
    if (!m_in_buf_left) {
      prep_in_buffer();
      if (!m_in_buf_left) {
        *pPadding_flag = true;
        int t = m_tem_flag;
        m_tem_flag ^= 1;
        return (t ? 0xD9 : 0xFF);
      }
    }
    *pPadding_flag = false;
    uint c = *m_pIn_buf_ofs++;
    --m_in_buf_left;
    return c;
  }

  // Inserts a previously retrieved character back into the input buffer.
  void stuff_char (ubyte q) {
    *(--m_pIn_buf_ofs) = q;
    m_in_buf_left++;
  }

  // Retrieves one character from the input stream, but does not read past markers. Will continue to return 0xFF when a marker is encountered.
  ubyte get_octet () {
    bool padding_flag;
    int c = get_char(&padding_flag);
    if (c == 0xFF) {
      if (padding_flag) return 0xFF;
      c = get_char(&padding_flag);
      if (padding_flag) { stuff_char(0xFF); return 0xFF; }
      if (c == 0x00) return 0xFF;
      stuff_char(cast(ubyte)(c));
      stuff_char(0xFF);
      return 0xFF;
    }
    return cast(ubyte)(c);
  }

  // Retrieves a variable number of bits from the input stream. Does not recognize markers.
  uint get_bits (int num_bits) {
    if (!num_bits) return 0;
    uint i = m_bit_buf >> (32 - num_bits);
    if ((m_bits_left -= num_bits) <= 0) {
      m_bit_buf <<= (num_bits += m_bits_left);
      uint c1 = get_char();
      uint c2 = get_char();
      m_bit_buf = (m_bit_buf & 0xFFFF0000) | (c1 << 8) | c2;
      m_bit_buf <<= -m_bits_left;
      m_bits_left += 16;
      assert(m_bits_left >= 0);
    } else {
      m_bit_buf <<= num_bits;
    }
    return i;
  }

  // Retrieves a variable number of bits from the input stream. Markers will not be read into the input bit buffer. Instead, an infinite number of all 1's will be returned when a marker is encountered.
  uint get_bits_no_markers (int num_bits) {
    if (!num_bits) return 0;
    uint i = m_bit_buf >> (32 - num_bits);
    if ((m_bits_left -= num_bits) <= 0) {
      m_bit_buf <<= (num_bits += m_bits_left);
      if (m_in_buf_left < 2 || m_pIn_buf_ofs[0] == 0xFF || m_pIn_buf_ofs[1] == 0xFF) {
        uint c1 = get_octet();
        uint c2 = get_octet();
        m_bit_buf |= (c1 << 8) | c2;
      } else {
        m_bit_buf |= (cast(uint)m_pIn_buf_ofs[0] << 8) | m_pIn_buf_ofs[1];
        m_in_buf_left -= 2;
        m_pIn_buf_ofs += 2;
      }
      m_bit_buf <<= -m_bits_left;
      m_bits_left += 16;
      assert(m_bits_left >= 0);
    } else {
      m_bit_buf <<= num_bits;
    }
    return i;
  }

  // Decodes a Huffman encoded symbol.
  int huff_decode (huff_tables *pH) {
    int symbol;
    // Check first 8-bits: do we have a complete symbol?
    if ((symbol = pH.look_up.ptr[m_bit_buf >> 24]) < 0) {
      // Decode more bits, use a tree traversal to find symbol.
      int ofs = 23;
      do {
        symbol = pH.tree.ptr[-cast(int)(symbol + ((m_bit_buf >> ofs) & 1))];
        --ofs;
      } while (symbol < 0);
      get_bits_no_markers(8 + (23 - ofs));
    } else {
      get_bits_no_markers(pH.code_size.ptr[symbol]);
    }
    return symbol;
  }

  // Decodes a Huffman encoded symbol.
  int huff_decode (huff_tables *pH, ref int extra_bits) {
    int symbol;
    // Check first 8-bits: do we have a complete symbol?
    if ((symbol = pH.look_up2.ptr[m_bit_buf >> 24]) < 0) {
      // Use a tree traversal to find symbol.
      int ofs = 23;
      do {
        symbol = pH.tree.ptr[-cast(int)(symbol + ((m_bit_buf >> ofs) & 1))];
        --ofs;
      } while (symbol < 0);
      get_bits_no_markers(8 + (23 - ofs));
      extra_bits = get_bits_no_markers(symbol & 0xF);
    } else {
      assert(((symbol >> 8) & 31) == pH.code_size.ptr[symbol & 255] + ((symbol & 0x8000) ? (symbol & 15) : 0));
      if (symbol & 0x8000) {
        get_bits_no_markers((symbol >> 8) & 31);
        extra_bits = symbol >> 16;
      } else {
        int code_size = (symbol >> 8) & 31;
        int num_extra_bits = symbol & 0xF;
        int bits = code_size + num_extra_bits;
        if (bits <= (m_bits_left + 16)) {
          extra_bits = get_bits_no_markers(bits) & ((1 << num_extra_bits) - 1);
        } else {
          get_bits_no_markers(code_size);
          extra_bits = get_bits_no_markers(num_extra_bits);
        }
      }
      symbol &= 0xFF;
    }
    return symbol;
  }

  // Tables and macro used to fully decode the DPCM differences.
  static immutable int[16] s_extend_test = [ 0, 0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0080, 0x0100, 0x0200, 0x0400, 0x0800, 0x1000, 0x2000, 0x4000 ];
  static immutable int[16] s_extend_offset = [ 0, ((-1)<<1) + 1, ((-1)<<2) + 1, ((-1)<<3) + 1, ((-1)<<4) + 1, ((-1)<<5) + 1, ((-1)<<6) + 1, ((-1)<<7) + 1, ((-1)<<8) + 1, ((-1)<<9) + 1, ((-1)<<10) + 1, ((-1)<<11) + 1, ((-1)<<12) + 1, ((-1)<<13) + 1, ((-1)<<14) + 1, ((-1)<<15) + 1 ];
  static immutable int[18] s_extend_mask = [ 0, (1<<0), (1<<1), (1<<2), (1<<3), (1<<4), (1<<5), (1<<6), (1<<7), (1<<8), (1<<9), (1<<10), (1<<11), (1<<12), (1<<13), (1<<14), (1<<15), (1<<16) ];
  // The logical AND's in this macro are to shut up static code analysis (aren't really necessary - couldn't find another way to do this)
  //#define JPGD_HUFF_EXTEND(x, s) (((x) < s_extend_test[s & 15]) ? ((x) + s_extend_offset[s & 15]) : (x))
  static JPGD_HUFF_EXTEND (int x, int s) nothrow @trusted @nogc { pragma(inline, true); return (((x) < s_extend_test.ptr[s & 15]) ? ((x) + s_extend_offset.ptr[s & 15]) : (x)); }

  // Clamps a value between 0-255.
  //static ubyte clamp (int i) { if (cast(uint)(i) > 255) i = (((~i) >> 31) & 0xFF); return cast(ubyte)(i); }
  alias clamp = CLAMP;

  static struct DCT_Upsample {
  static:
    static struct Matrix44 {
    pure nothrow @trusted @nogc:
      alias Element_Type = int;
      enum { NUM_ROWS = 4, NUM_COLS = 4 }

      Element_Type[NUM_COLS][NUM_ROWS] v;

      this() (const scope auto ref Matrix44 m) {
        foreach (immutable r; 0..NUM_ROWS) v[r][] = m.v[r][];
      }

      //@property int rows () const { pragma(inline, true); return NUM_ROWS; }
      //@property int cols () const { pragma(inline, true); return NUM_COLS; }

      ref inout(Element_Type) at (int r, int c) inout { pragma(inline, true); return v.ptr[r].ptr[c]; }

      ref Matrix44 opOpAssign(string op:"+") (const scope auto ref Matrix44 a) {
        foreach (int r; 0..NUM_ROWS) {
          at(r, 0) += a.at(r, 0);
          at(r, 1) += a.at(r, 1);
          at(r, 2) += a.at(r, 2);
          at(r, 3) += a.at(r, 3);
        }
        return this;
      }

      ref Matrix44 opOpAssign(string op:"-") (const scope auto ref Matrix44 a) {
        foreach (int r; 0..NUM_ROWS) {
          at(r, 0) -= a.at(r, 0);
          at(r, 1) -= a.at(r, 1);
          at(r, 2) -= a.at(r, 2);
          at(r, 3) -= a.at(r, 3);
        }
        return this;
      }

      Matrix44 opBinary(string op:"+") (const scope auto ref Matrix44 b) const {
        alias a = this;
        Matrix44 ret;
        foreach (int r; 0..NUM_ROWS) {
          ret.at(r, 0) = a.at(r, 0) + b.at(r, 0);
          ret.at(r, 1) = a.at(r, 1) + b.at(r, 1);
          ret.at(r, 2) = a.at(r, 2) + b.at(r, 2);
          ret.at(r, 3) = a.at(r, 3) + b.at(r, 3);
        }
        return ret;
      }

      Matrix44 opBinary(string op:"-") (const scope auto ref Matrix44 b) const {
        alias a = this;
        Matrix44 ret;
        foreach (int r; 0..NUM_ROWS) {
          ret.at(r, 0) = a.at(r, 0) - b.at(r, 0);
          ret.at(r, 1) = a.at(r, 1) - b.at(r, 1);
          ret.at(r, 2) = a.at(r, 2) - b.at(r, 2);
          ret.at(r, 3) = a.at(r, 3) - b.at(r, 3);
        }
        return ret;
      }

      static void add_and_store() (jpgd_block_t* pDst, const scope auto ref Matrix44 a, const scope auto ref Matrix44 b) {
        foreach (int r; 0..4) {
          pDst[0*8 + r] = cast(jpgd_block_t)(a.at(r, 0) + b.at(r, 0));
          pDst[1*8 + r] = cast(jpgd_block_t)(a.at(r, 1) + b.at(r, 1));
          pDst[2*8 + r] = cast(jpgd_block_t)(a.at(r, 2) + b.at(r, 2));
          pDst[3*8 + r] = cast(jpgd_block_t)(a.at(r, 3) + b.at(r, 3));
        }
      }

      static void sub_and_store() (jpgd_block_t* pDst, const scope auto ref Matrix44 a, const scope auto ref Matrix44 b) {
        foreach (int r; 0..4) {
          pDst[0*8 + r] = cast(jpgd_block_t)(a.at(r, 0) - b.at(r, 0));
          pDst[1*8 + r] = cast(jpgd_block_t)(a.at(r, 1) - b.at(r, 1));
          pDst[2*8 + r] = cast(jpgd_block_t)(a.at(r, 2) - b.at(r, 2));
          pDst[3*8 + r] = cast(jpgd_block_t)(a.at(r, 3) - b.at(r, 3));
        }
      }
    }

    enum FRACT_BITS = 10;
    enum SCALE = 1 << FRACT_BITS;

    alias Temp_Type = int;
    //TODO: convert defines to mixins
    //#define D(i) (((i) + (SCALE >> 1)) >> FRACT_BITS)
    //#define F(i) ((int)((i) * SCALE + .5f))
    // Any decent C++ compiler will optimize this at compile time to a 0, or an array access.
    //#define AT(c, r) ((((c)>=NUM_COLS)||((r)>=NUM_ROWS)) ? 0 : pSrc[(c)+(r)*8])

    static int D(T) (T i) { pragma(inline, true); return (((i) + (SCALE >> 1)) >> FRACT_BITS); }
    enum F(float i) = (cast(int)((i) * SCALE + 0.5f));

    // NUM_ROWS/NUM_COLS = # of non-zero rows/cols in input matrix
    static struct P_Q(int NUM_ROWS, int NUM_COLS) {
      static void calc (ref Matrix44 P, ref Matrix44 Q, const(jpgd_block_t)* pSrc) {
        //auto AT (int c, int r) nothrow @trusted @nogc { return (c >= NUM_COLS || r >= NUM_ROWS ? 0 : pSrc[c+r*8]); }
        template AT(int c, int r) {
          static if (c >= NUM_COLS || r >= NUM_ROWS) enum AT = "0"; else enum AT = "pSrc["~c.stringof~"+"~r.stringof~"*8]";
        }
        // 4x8 = 4x8 times 8x8, matrix 0 is constant
        immutable Temp_Type X000 = mixin(AT!(0, 0));
        immutable Temp_Type X001 = mixin(AT!(0, 1));
        immutable Temp_Type X002 = mixin(AT!(0, 2));
        immutable Temp_Type X003 = mixin(AT!(0, 3));
        immutable Temp_Type X004 = mixin(AT!(0, 4));
        immutable Temp_Type X005 = mixin(AT!(0, 5));
        immutable Temp_Type X006 = mixin(AT!(0, 6));
        immutable Temp_Type X007 = mixin(AT!(0, 7));
        immutable Temp_Type X010 = D(F!(0.415735f) * mixin(AT!(1, 0)) + F!(0.791065f) * mixin(AT!(3, 0)) + F!(-0.352443f) * mixin(AT!(5, 0)) + F!(0.277785f) * mixin(AT!(7, 0)));
        immutable Temp_Type X011 = D(F!(0.415735f) * mixin(AT!(1, 1)) + F!(0.791065f) * mixin(AT!(3, 1)) + F!(-0.352443f) * mixin(AT!(5, 1)) + F!(0.277785f) * mixin(AT!(7, 1)));
        immutable Temp_Type X012 = D(F!(0.415735f) * mixin(AT!(1, 2)) + F!(0.791065f) * mixin(AT!(3, 2)) + F!(-0.352443f) * mixin(AT!(5, 2)) + F!(0.277785f) * mixin(AT!(7, 2)));
        immutable Temp_Type X013 = D(F!(0.415735f) * mixin(AT!(1, 3)) + F!(0.791065f) * mixin(AT!(3, 3)) + F!(-0.352443f) * mixin(AT!(5, 3)) + F!(0.277785f) * mixin(AT!(7, 3)));
        immutable Temp_Type X014 = D(F!(0.415735f) * mixin(AT!(1, 4)) + F!(0.791065f) * mixin(AT!(3, 4)) + F!(-0.352443f) * mixin(AT!(5, 4)) + F!(0.277785f) * mixin(AT!(7, 4)));
        immutable Temp_Type X015 = D(F!(0.415735f) * mixin(AT!(1, 5)) + F!(0.791065f) * mixin(AT!(3, 5)) + F!(-0.352443f) * mixin(AT!(5, 5)) + F!(0.277785f) * mixin(AT!(7, 5)));
        immutable Temp_Type X016 = D(F!(0.415735f) * mixin(AT!(1, 6)) + F!(0.791065f) * mixin(AT!(3, 6)) + F!(-0.352443f) * mixin(AT!(5, 6)) + F!(0.277785f) * mixin(AT!(7, 6)));
        immutable Temp_Type X017 = D(F!(0.415735f) * mixin(AT!(1, 7)) + F!(0.791065f) * mixin(AT!(3, 7)) + F!(-0.352443f) * mixin(AT!(5, 7)) + F!(0.277785f) * mixin(AT!(7, 7)));
        immutable Temp_Type X020 = mixin(AT!(4, 0));
        immutable Temp_Type X021 = mixin(AT!(4, 1));
        immutable Temp_Type X022 = mixin(AT!(4, 2));
        immutable Temp_Type X023 = mixin(AT!(4, 3));
        immutable Temp_Type X024 = mixin(AT!(4, 4));
        immutable Temp_Type X025 = mixin(AT!(4, 5));
        immutable Temp_Type X026 = mixin(AT!(4, 6));
        immutable Temp_Type X027 = mixin(AT!(4, 7));
        immutable Temp_Type X030 = D(F!(0.022887f) * mixin(AT!(1, 0)) + F!(-0.097545f) * mixin(AT!(3, 0)) + F!(0.490393f) * mixin(AT!(5, 0)) + F!(0.865723f) * mixin(AT!(7, 0)));
        immutable Temp_Type X031 = D(F!(0.022887f) * mixin(AT!(1, 1)) + F!(-0.097545f) * mixin(AT!(3, 1)) + F!(0.490393f) * mixin(AT!(5, 1)) + F!(0.865723f) * mixin(AT!(7, 1)));
        immutable Temp_Type X032 = D(F!(0.022887f) * mixin(AT!(1, 2)) + F!(-0.097545f) * mixin(AT!(3, 2)) + F!(0.490393f) * mixin(AT!(5, 2)) + F!(0.865723f) * mixin(AT!(7, 2)));
        immutable Temp_Type X033 = D(F!(0.022887f) * mixin(AT!(1, 3)) + F!(-0.097545f) * mixin(AT!(3, 3)) + F!(0.490393f) * mixin(AT!(5, 3)) + F!(0.865723f) * mixin(AT!(7, 3)));
        immutable Temp_Type X034 = D(F!(0.022887f) * mixin(AT!(1, 4)) + F!(-0.097545f) * mixin(AT!(3, 4)) + F!(0.490393f) * mixin(AT!(5, 4)) + F!(0.865723f) * mixin(AT!(7, 4)));
        immutable Temp_Type X035 = D(F!(0.022887f) * mixin(AT!(1, 5)) + F!(-0.097545f) * mixin(AT!(3, 5)) + F!(0.490393f) * mixin(AT!(5, 5)) + F!(0.865723f) * mixin(AT!(7, 5)));
        immutable Temp_Type X036 = D(F!(0.022887f) * mixin(AT!(1, 6)) + F!(-0.097545f) * mixin(AT!(3, 6)) + F!(0.490393f) * mixin(AT!(5, 6)) + F!(0.865723f) * mixin(AT!(7, 6)));
        immutable Temp_Type X037 = D(F!(0.022887f) * mixin(AT!(1, 7)) + F!(-0.097545f) * mixin(AT!(3, 7)) + F!(0.490393f) * mixin(AT!(5, 7)) + F!(0.865723f) * mixin(AT!(7, 7)));

        // 4x4 = 4x8 times 8x4, matrix 1 is constant
        P.at(0, 0) = X000;
        P.at(0, 1) = D(X001 * F!(0.415735f) + X003 * F!(0.791065f) + X005 * F!(-0.352443f) + X007 * F!(0.277785f));
        P.at(0, 2) = X004;
        P.at(0, 3) = D(X001 * F!(0.022887f) + X003 * F!(-0.097545f) + X005 * F!(0.490393f) + X007 * F!(0.865723f));
        P.at(1, 0) = X010;
        P.at(1, 1) = D(X011 * F!(0.415735f) + X013 * F!(0.791065f) + X015 * F!(-0.352443f) + X017 * F!(0.277785f));
        P.at(1, 2) = X014;
        P.at(1, 3) = D(X011 * F!(0.022887f) + X013 * F!(-0.097545f) + X015 * F!(0.490393f) + X017 * F!(0.865723f));
        P.at(2, 0) = X020;
        P.at(2, 1) = D(X021 * F!(0.415735f) + X023 * F!(0.791065f) + X025 * F!(-0.352443f) + X027 * F!(0.277785f));
        P.at(2, 2) = X024;
        P.at(2, 3) = D(X021 * F!(0.022887f) + X023 * F!(-0.097545f) + X025 * F!(0.490393f) + X027 * F!(0.865723f));
        P.at(3, 0) = X030;
        P.at(3, 1) = D(X031 * F!(0.415735f) + X033 * F!(0.791065f) + X035 * F!(-0.352443f) + X037 * F!(0.277785f));
        P.at(3, 2) = X034;
        P.at(3, 3) = D(X031 * F!(0.022887f) + X033 * F!(-0.097545f) + X035 * F!(0.490393f) + X037 * F!(0.865723f));
        // 40 muls 24 adds

        // 4x4 = 4x8 times 8x4, matrix 1 is constant
        Q.at(0, 0) = D(X001 * F!(0.906127f) + X003 * F!(-0.318190f) + X005 * F!(0.212608f) + X007 * F!(-0.180240f));
        Q.at(0, 1) = X002;
        Q.at(0, 2) = D(X001 * F!(-0.074658f) + X003 * F!(0.513280f) + X005 * F!(0.768178f) + X007 * F!(-0.375330f));
        Q.at(0, 3) = X006;
        Q.at(1, 0) = D(X011 * F!(0.906127f) + X013 * F!(-0.318190f) + X015 * F!(0.212608f) + X017 * F!(-0.180240f));
        Q.at(1, 1) = X012;
        Q.at(1, 2) = D(X011 * F!(-0.074658f) + X013 * F!(0.513280f) + X015 * F!(0.768178f) + X017 * F!(-0.375330f));
        Q.at(1, 3) = X016;
        Q.at(2, 0) = D(X021 * F!(0.906127f) + X023 * F!(-0.318190f) + X025 * F!(0.212608f) + X027 * F!(-0.180240f));
        Q.at(2, 1) = X022;
        Q.at(2, 2) = D(X021 * F!(-0.074658f) + X023 * F!(0.513280f) + X025 * F!(0.768178f) + X027 * F!(-0.375330f));
        Q.at(2, 3) = X026;
        Q.at(3, 0) = D(X031 * F!(0.906127f) + X033 * F!(-0.318190f) + X035 * F!(0.212608f) + X037 * F!(-0.180240f));
        Q.at(3, 1) = X032;
        Q.at(3, 2) = D(X031 * F!(-0.074658f) + X033 * F!(0.513280f) + X035 * F!(0.768178f) + X037 * F!(-0.375330f));
        Q.at(3, 3) = X036;
        // 40 muls 24 adds
      }
    }

    static struct R_S(int NUM_ROWS, int NUM_COLS) {
      static void calc(ref Matrix44 R, ref Matrix44 S, const(jpgd_block_t)* pSrc) {
        //auto AT (int c, int r) nothrow @trusted @nogc { return (c >= NUM_COLS || r >= NUM_ROWS ? 0 : pSrc[c+r*8]); }
        template AT(int c, int r) {
          static if (c >= NUM_COLS || r >= NUM_ROWS) enum AT = "0"; else enum AT = "pSrc["~c.stringof~"+"~r.stringof~"*8]";
        }
        // 4x8 = 4x8 times 8x8, matrix 0 is constant
        immutable Temp_Type X100 = D(F!(0.906127f) * mixin(AT!(1, 0)) + F!(-0.318190f) * mixin(AT!(3, 0)) + F!(0.212608f) * mixin(AT!(5, 0)) + F!(-0.180240f) * mixin(AT!(7, 0)));
        immutable Temp_Type X101 = D(F!(0.906127f) * mixin(AT!(1, 1)) + F!(-0.318190f) * mixin(AT!(3, 1)) + F!(0.212608f) * mixin(AT!(5, 1)) + F!(-0.180240f) * mixin(AT!(7, 1)));
        immutable Temp_Type X102 = D(F!(0.906127f) * mixin(AT!(1, 2)) + F!(-0.318190f) * mixin(AT!(3, 2)) + F!(0.212608f) * mixin(AT!(5, 2)) + F!(-0.180240f) * mixin(AT!(7, 2)));
        immutable Temp_Type X103 = D(F!(0.906127f) * mixin(AT!(1, 3)) + F!(-0.318190f) * mixin(AT!(3, 3)) + F!(0.212608f) * mixin(AT!(5, 3)) + F!(-0.180240f) * mixin(AT!(7, 3)));
        immutable Temp_Type X104 = D(F!(0.906127f) * mixin(AT!(1, 4)) + F!(-0.318190f) * mixin(AT!(3, 4)) + F!(0.212608f) * mixin(AT!(5, 4)) + F!(-0.180240f) * mixin(AT!(7, 4)));
        immutable Temp_Type X105 = D(F!(0.906127f) * mixin(AT!(1, 5)) + F!(-0.318190f) * mixin(AT!(3, 5)) + F!(0.212608f) * mixin(AT!(5, 5)) + F!(-0.180240f) * mixin(AT!(7, 5)));
        immutable Temp_Type X106 = D(F!(0.906127f) * mixin(AT!(1, 6)) + F!(-0.318190f) * mixin(AT!(3, 6)) + F!(0.212608f) * mixin(AT!(5, 6)) + F!(-0.180240f) * mixin(AT!(7, 6)));
        immutable Temp_Type X107 = D(F!(0.906127f) * mixin(AT!(1, 7)) + F!(-0.318190f) * mixin(AT!(3, 7)) + F!(0.212608f) * mixin(AT!(5, 7)) + F!(-0.180240f) * mixin(AT!(7, 7)));
        immutable Temp_Type X110 = mixin(AT!(2, 0));
        immutable Temp_Type X111 = mixin(AT!(2, 1));
        immutable Temp_Type X112 = mixin(AT!(2, 2));
        immutable Temp_Type X113 = mixin(AT!(2, 3));
        immutable Temp_Type X114 = mixin(AT!(2, 4));
        immutable Temp_Type X115 = mixin(AT!(2, 5));
        immutable Temp_Type X116 = mixin(AT!(2, 6));
        immutable Temp_Type X117 = mixin(AT!(2, 7));
        immutable Temp_Type X120 = D(F!(-0.074658f) * mixin(AT!(1, 0)) + F!(0.513280f) * mixin(AT!(3, 0)) + F!(0.768178f) * mixin(AT!(5, 0)) + F!(-0.375330f) * mixin(AT!(7, 0)));
        immutable Temp_Type X121 = D(F!(-0.074658f) * mixin(AT!(1, 1)) + F!(0.513280f) * mixin(AT!(3, 1)) + F!(0.768178f) * mixin(AT!(5, 1)) + F!(-0.375330f) * mixin(AT!(7, 1)));
        immutable Temp_Type X122 = D(F!(-0.074658f) * mixin(AT!(1, 2)) + F!(0.513280f) * mixin(AT!(3, 2)) + F!(0.768178f) * mixin(AT!(5, 2)) + F!(-0.375330f) * mixin(AT!(7, 2)));
        immutable Temp_Type X123 = D(F!(-0.074658f) * mixin(AT!(1, 3)) + F!(0.513280f) * mixin(AT!(3, 3)) + F!(0.768178f) * mixin(AT!(5, 3)) + F!(-0.375330f) * mixin(AT!(7, 3)));
        immutable Temp_Type X124 = D(F!(-0.074658f) * mixin(AT!(1, 4)) + F!(0.513280f) * mixin(AT!(3, 4)) + F!(0.768178f) * mixin(AT!(5, 4)) + F!(-0.375330f) * mixin(AT!(7, 4)));
        immutable Temp_Type X125 = D(F!(-0.074658f) * mixin(AT!(1, 5)) + F!(0.513280f) * mixin(AT!(3, 5)) + F!(0.768178f) * mixin(AT!(5, 5)) + F!(-0.375330f) * mixin(AT!(7, 5)));
        immutable Temp_Type X126 = D(F!(-0.074658f) * mixin(AT!(1, 6)) + F!(0.513280f) * mixin(AT!(3, 6)) + F!(0.768178f) * mixin(AT!(5, 6)) + F!(-0.375330f) * mixin(AT!(7, 6)));
        immutable Temp_Type X127 = D(F!(-0.074658f) * mixin(AT!(1, 7)) + F!(0.513280f) * mixin(AT!(3, 7)) + F!(0.768178f) * mixin(AT!(5, 7)) + F!(-0.375330f) * mixin(AT!(7, 7)));
        immutable Temp_Type X130 = mixin(AT!(6, 0));
        immutable Temp_Type X131 = mixin(AT!(6, 1));
        immutable Temp_Type X132 = mixin(AT!(6, 2));
        immutable Temp_Type X133 = mixin(AT!(6, 3));
        immutable Temp_Type X134 = mixin(AT!(6, 4));
        immutable Temp_Type X135 = mixin(AT!(6, 5));
        immutable Temp_Type X136 = mixin(AT!(6, 6));
        immutable Temp_Type X137 = mixin(AT!(6, 7));
        // 80 muls 48 adds

        // 4x4 = 4x8 times 8x4, matrix 1 is constant
        R.at(0, 0) = X100;
        R.at(0, 1) = D(X101 * F!(0.415735f) + X103 * F!(0.791065f) + X105 * F!(-0.352443f) + X107 * F!(0.277785f));
        R.at(0, 2) = X104;
        R.at(0, 3) = D(X101 * F!(0.022887f) + X103 * F!(-0.097545f) + X105 * F!(0.490393f) + X107 * F!(0.865723f));
        R.at(1, 0) = X110;
        R.at(1, 1) = D(X111 * F!(0.415735f) + X113 * F!(0.791065f) + X115 * F!(-0.352443f) + X117 * F!(0.277785f));
        R.at(1, 2) = X114;
        R.at(1, 3) = D(X111 * F!(0.022887f) + X113 * F!(-0.097545f) + X115 * F!(0.490393f) + X117 * F!(0.865723f));
        R.at(2, 0) = X120;
        R.at(2, 1) = D(X121 * F!(0.415735f) + X123 * F!(0.791065f) + X125 * F!(-0.352443f) + X127 * F!(0.277785f));
        R.at(2, 2) = X124;
        R.at(2, 3) = D(X121 * F!(0.022887f) + X123 * F!(-0.097545f) + X125 * F!(0.490393f) + X127 * F!(0.865723f));
        R.at(3, 0) = X130;
        R.at(3, 1) = D(X131 * F!(0.415735f) + X133 * F!(0.791065f) + X135 * F!(-0.352443f) + X137 * F!(0.277785f));
        R.at(3, 2) = X134;
        R.at(3, 3) = D(X131 * F!(0.022887f) + X133 * F!(-0.097545f) + X135 * F!(0.490393f) + X137 * F!(0.865723f));
        // 40 muls 24 adds
        // 4x4 = 4x8 times 8x4, matrix 1 is constant
        S.at(0, 0) = D(X101 * F!(0.906127f) + X103 * F!(-0.318190f) + X105 * F!(0.212608f) + X107 * F!(-0.180240f));
        S.at(0, 1) = X102;
        S.at(0, 2) = D(X101 * F!(-0.074658f) + X103 * F!(0.513280f) + X105 * F!(0.768178f) + X107 * F!(-0.375330f));
        S.at(0, 3) = X106;
        S.at(1, 0) = D(X111 * F!(0.906127f) + X113 * F!(-0.318190f) + X115 * F!(0.212608f) + X117 * F!(-0.180240f));
        S.at(1, 1) = X112;
        S.at(1, 2) = D(X111 * F!(-0.074658f) + X113 * F!(0.513280f) + X115 * F!(0.768178f) + X117 * F!(-0.375330f));
        S.at(1, 3) = X116;
        S.at(2, 0) = D(X121 * F!(0.906127f) + X123 * F!(-0.318190f) + X125 * F!(0.212608f) + X127 * F!(-0.180240f));
        S.at(2, 1) = X122;
        S.at(2, 2) = D(X121 * F!(-0.074658f) + X123 * F!(0.513280f) + X125 * F!(0.768178f) + X127 * F!(-0.375330f));
        S.at(2, 3) = X126;
        S.at(3, 0) = D(X131 * F!(0.906127f) + X133 * F!(-0.318190f) + X135 * F!(0.212608f) + X137 * F!(-0.180240f));
        S.at(3, 1) = X132;
        S.at(3, 2) = D(X131 * F!(-0.074658f) + X133 * F!(0.513280f) + X135 * F!(0.768178f) + X137 * F!(-0.375330f));
        S.at(3, 3) = X136;
        // 40 muls 24 adds
      }
    }
  } // end namespace DCT_Upsample

  // Unconditionally frees all allocated m_blocks.
  void free_all_blocks () {
    //m_pStream = null;
    readfn = null;
    for (mem_block *b = m_pMem_blocks; b; ) {
      mem_block* n = b.m_pNext;
      jpgd_free(b);
      b = n;
    }
    m_pMem_blocks = null;
  }

  // This method handles all errors. It will never return.
  // It could easily be changed to use C++ exceptions.
  /*JPGD_NORETURN*/ void stop_decoding (jpgd_status status, size_t line=__LINE__) {
    m_error_code = status;
    free_all_blocks();
    //longjmp(m_jmp_state, status);
    throw new Exception("jpeg decoding error", __FILE__, line);
  }

  void* alloc (size_t nSize, bool zero=false) {
    nSize = (JPGD_MAX(nSize, 1) + 3) & ~3;
    char *rv = null;
    for (mem_block *b = m_pMem_blocks; b; b = b.m_pNext)
    {
      if ((b.m_used_count + nSize) <= b.m_size)
      {
        rv = b.m_data.ptr + b.m_used_count;
        b.m_used_count += nSize;
        break;
      }
    }
    if (!rv)
    {
      size_t capacity = JPGD_MAX(32768 - 256, (nSize + 2047) & ~2047);
      mem_block *b = cast(mem_block*)jpgd_malloc(mem_block.sizeof + capacity);
      if (!b) { stop_decoding(JPGD_NOTENOUGHMEM); }
      b.m_pNext = m_pMem_blocks; m_pMem_blocks = b;
      b.m_used_count = nSize;
      b.m_size = capacity;
      rv = b.m_data.ptr;
    }
    if (zero) memset(rv, 0, nSize);
    return rv;
  }

  void word_clear (void *p, ushort c, uint n) {
    ubyte *pD = cast(ubyte*)p;
    immutable ubyte l = c & 0xFF, h = (c >> 8) & 0xFF;
    while (n)
    {
      pD[0] = l; pD[1] = h; pD += 2;
      n--;
    }
  }

  // Refill the input buffer.
  // This method will sit in a loop until (A) the buffer is full or (B)
  // the stream's read() method reports and end of file condition.
  void prep_in_buffer () {
    m_in_buf_left = 0;
    m_pIn_buf_ofs = m_in_buf.ptr;

    if (m_eof_flag)
      return;

    do
    {
      int bytes_read = readfn(m_in_buf.ptr + m_in_buf_left, JPGD_IN_BUF_SIZE - m_in_buf_left, &m_eof_flag);
      if (bytes_read == -1)
        stop_decoding(JPGD_STREAM_READ);

      m_in_buf_left += bytes_read;
    } while ((m_in_buf_left < JPGD_IN_BUF_SIZE) && (!m_eof_flag));

    m_total_bytes_read += m_in_buf_left;

    // Pad the end of the block with M_EOI (prevents the decompressor from going off the rails if the stream is invalid).
    // (This dates way back to when this decompressor was written in C/asm, and the all-asm Huffman decoder did some fancy things to increase perf.)
    word_clear(m_pIn_buf_ofs + m_in_buf_left, 0xD9FF, 64);
  }

  // Read a Huffman code table.
  void read_dht_marker () {
    int i, index, count;
    ubyte[17] huff_num;
    ubyte[256] huff_val;

    uint num_left = get_bits(16);

    if (num_left < 2)
      stop_decoding(JPGD_BAD_DHT_MARKER);

    num_left -= 2;

    while (num_left)
    {
      index = get_bits(8);

      huff_num.ptr[0] = 0;

      count = 0;

      for (i = 1; i <= 16; i++)
      {
        huff_num.ptr[i] = cast(ubyte)(get_bits(8));
        count += huff_num.ptr[i];
      }

      if (count > 255)
        stop_decoding(JPGD_BAD_DHT_COUNTS);

      for (i = 0; i < count; i++)
        huff_val.ptr[i] = cast(ubyte)(get_bits(8));

      i = 1 + 16 + count;

      if (num_left < cast(uint)i)
        stop_decoding(JPGD_BAD_DHT_MARKER);

      num_left -= i;

      if ((index & 0x10) > 0x10)
        stop_decoding(JPGD_BAD_DHT_INDEX);

      index = (index & 0x0F) + ((index & 0x10) >> 4) * (JPGD_MAX_HUFF_TABLES >> 1);

      if (index >= JPGD_MAX_HUFF_TABLES)
        stop_decoding(JPGD_BAD_DHT_INDEX);

      if (!m_huff_num.ptr[index])
        m_huff_num.ptr[index] = cast(ubyte*)alloc(17);

      if (!m_huff_val.ptr[index])
        m_huff_val.ptr[index] = cast(ubyte*)alloc(256);

      m_huff_ac.ptr[index] = (index & 0x10) != 0;
      memcpy(m_huff_num.ptr[index], huff_num.ptr, 17);
      memcpy(m_huff_val.ptr[index], huff_val.ptr, 256);
    }
  }

  // Read a quantization table.
  void read_dqt_marker () {
    int n, i, prec;
    uint num_left;
    uint temp;

    num_left = get_bits(16);

    if (num_left < 2)
      stop_decoding(JPGD_BAD_DQT_MARKER);

    num_left -= 2;

    while (num_left)
    {
      n = get_bits(8);
      prec = n >> 4;
      n &= 0x0F;

      if (n >= JPGD_MAX_QUANT_TABLES)
        stop_decoding(JPGD_BAD_DQT_TABLE);

      if (!m_quant.ptr[n])
        m_quant.ptr[n] = cast(jpgd_quant_t*)alloc(64 * jpgd_quant_t.sizeof);

      // read quantization entries, in zag order
      for (i = 0; i < 64; i++)
      {
        temp = get_bits(8);

        if (prec)
          temp = (temp << 8) + get_bits(8);

        m_quant.ptr[n][i] = cast(jpgd_quant_t)(temp);
      }

      i = 64 + 1;

      if (prec)
        i += 64;

      if (num_left < cast(uint)i)
        stop_decoding(JPGD_BAD_DQT_LENGTH);

      num_left -= i;
    }
  }

  // Read the start of frame (SOF) marker.
  void read_sof_marker () {
    int i;
    uint num_left;

    num_left = get_bits(16);

    if (get_bits(8) != 8)   /* precision: sorry, only 8-bit precision is supported right now */
      stop_decoding(JPGD_BAD_PRECISION);

    m_image_y_size = get_bits(16);

    if ((m_image_y_size < 1) || (m_image_y_size > JPGD_MAX_HEIGHT))
      stop_decoding(JPGD_BAD_HEIGHT);

    m_image_x_size = get_bits(16);

    if ((m_image_x_size < 1) || (m_image_x_size > JPGD_MAX_WIDTH))
      stop_decoding(JPGD_BAD_WIDTH);

    m_comps_in_frame = get_bits(8);

    if (m_comps_in_frame > JPGD_MAX_COMPONENTS)
      stop_decoding(JPGD_TOO_MANY_COMPONENTS);

    if (num_left != cast(uint)(m_comps_in_frame * 3 + 8))
      stop_decoding(JPGD_BAD_SOF_LENGTH);

    for (i = 0; i < m_comps_in_frame; i++)
    {
      m_comp_ident.ptr[i]  = get_bits(8);
      m_comp_h_samp.ptr[i] = get_bits(4);
      m_comp_v_samp.ptr[i] = get_bits(4);
      m_comp_quant.ptr[i]  = get_bits(8);
    }
  }

  private void exif_enforce(bool what) {
	if(!what)
		throw new Exception("jpeg exif data format error");
  }

  void read_exif_marker() {
    uint num_left;

    num_left = get_bits(16);

    if (num_left < 2)
      stop_decoding(JPGD_BAD_VARIABLE_MARKER);

    num_left -= 2;

    ubyte[] data;
    data.length = num_left;
    int offset;

    while (num_left)
    {
      data[offset++] = cast(ubyte) get_bits(8);
      num_left--;
    }

    if(data.length > 4 && data[0 .. 4] == "Exif") {
	data = data[4 .. $];
	while(data.length && data[0] == 0)
		data = data[1 .. $];
	if(data.length < 8)
		return; // abandon the parse, no tiff header

	int offsetAdjustment = 0;

	bool bigEndian = data[0] == 'M';
	// should be MM or II
	exif_enforce(data[0] == data[1]);
	if(!bigEndian)
		exif_enforce(data[0] == 'I');
	data = data[2 .. $];
	offsetAdjustment += 2;

	uint read4() {
		exif_enforce(data.length >= 4);

		uint ret;
		if(bigEndian) {
			ret |= data[0] << 24;
			ret |= data[1] << 16;
			ret |= data[2] <<  8;
			ret |= data[3] <<  0;
		} else {
			ret |= data[3] << 24;
			ret |= data[2] << 16;
			ret |= data[1] <<  8;
			ret |= data[0] <<  0;
		}

		data = data[4 .. $];
		offsetAdjustment += 4;
		return ret;
	}

	ushort read2() {
		exif_enforce(data.length >= 2);

		ushort ret;
		if(bigEndian) {
			ret |= data[0] << 8;
			ret |= data[1] << 0;
		} else {
			ret |= data[1] << 8;
			ret |= data[0] << 0;
		}

		data = data[2 .. $];
		offsetAdjustment += 2;
		return ret;
	}

	ubyte read1() {
		exif_enforce(data.length >= 1);
		ubyte ret = data[0];
		data = data[1 .. $];
		offsetAdjustment += 1;
		return ret;
	}

	void jumpOffset(uint offset) {
		exif_enforce(offsetAdjustment <= offset);
		offset -= offsetAdjustment;
		data = data[offset .. $];
		offsetAdjustment += offset;
	}

	exif_enforce(read2() == 42);

	while(data.length) {
		auto nextIfdOffset = read4();
		if(nextIfdOffset == 0)
			return;
		jumpOffset(nextIfdOffset);

		// reading an ifd now
		auto numberOfIfdEntries = read2();
		foreach(item; 0 .. numberOfIfdEntries) {
			auto tagId = read2();
			auto fieldType = read2();
			auto countOfType = read4();
			auto valueOrOffset = read4();

			// https://exiftool.org/TagNames/EXIF.html

			// FIXME we could read a LOT more of this, but for now all i care about is orientation lol
			if(tagId == 0x0112 && fieldType == 3 && countOfType == 1) {
				/+
					valueOrOffset can be:

					1 = Horizontal (normal)
					2 = Mirror horizontal
					3 = Rotate 180
					4 = Mirror vertical
					5 = Mirror horizontal and rotate 270 CW
					6 = Rotate 90 CW
					7 = Mirror horizontal and rotate 90 CW
					8 = Rotate 270 CW
				+/

				// it stores the data inline but packed into the first bytes
				// so since this is a 16 bit thing packed to the left, we want to move it
				// down to right slot based on endinanness. woof but meh.
				if(bigEndian) {
					this.orientation = valueOrOffset >> 16;
				} else {
					this.orientation = valueOrOffset;
				}
			}

			// import std.stdio; writefln("%04x %d %d %d", tagId, fieldType, countOfType, valueOrOffset);
		}
	}
    }

    // format: Exif\0\0<tiff file bytes here>
    // are those two zero bytes just padding?
    /+
	tiff file:

	II or MM for byte order
	then 16 bit number 42 (0x2a 0x00)
	32 bit number containing byte offset of first IFD (should prolly be 8, saying it starts right after the header)

	IFD:
		16 bit number of fields
		12-byte entries
		4 byte offset of next ifd (0 if none)

	IFD entry:
		16 bit tag id
		16 bit field type
			1 = byte
			2 = ascii stringz
			3 = 16 bit ushort
			4 = 32 bit ulong
			5 = rational; numerator then denominator

			and others, see https://web.archive.org/web/20210108174645/https://www.adobe.io/content/dam/udp/en/open/standards/tiff/TIFF6.pdf
		32 bit number of values (count of the type)
		32 bit value or offset (must be even number, can point anywhere in file, but if the type is 4 bytes or less it is just packed in here, left-aligned)
    +/
  }

    /++
	The exif orientation value from the file, if present (0 if it was not present).

	You do not have to look at this if you leave [autoRotateBasedOnExifOrientation] as the default `true` value.

	History:
		Added May 6, 2025
    +/
    public int orientation = 0;

    /++
	If true (the default), the image will have the orientation automatically applied to the pixels before returning.

	Otherwise, you must see [orientation] to know the intended look.

	History:
		Added May 7, 2025
    +/
    public bool autoRotateBasedOnExifOrientation = true;

  // Used to skip unrecognized markers.
  void skip_variable_marker () {
    uint num_left;

    num_left = get_bits(16);

    if (num_left < 2)
      stop_decoding(JPGD_BAD_VARIABLE_MARKER);

    num_left -= 2;

    while (num_left)
    {
      get_bits(8);
      num_left--;
    }
  }

  // Read a define restart interval (DRI) marker.
  void read_dri_marker () {
    if (get_bits(16) != 4)
      stop_decoding(JPGD_BAD_DRI_LENGTH);

    m_restart_interval = get_bits(16);
  }

  // Read a start of scan (SOS) marker.
  void read_sos_marker () {
    uint num_left;
    int i, ci, n, c, cc;

    num_left = get_bits(16);

    n = get_bits(8);

    m_comps_in_scan = n;

    num_left -= 3;

    if ( (num_left != cast(uint)(n * 2 + 3)) || (n < 1) || (n > JPGD_MAX_COMPS_IN_SCAN) )
      stop_decoding(JPGD_BAD_SOS_LENGTH);

    for (i = 0; i < n; i++)
    {
      cc = get_bits(8);
      c = get_bits(8);
      num_left -= 2;

      for (ci = 0; ci < m_comps_in_frame; ci++)
        if (cc == m_comp_ident.ptr[ci])
          break;

      if (ci >= m_comps_in_frame)
        stop_decoding(JPGD_BAD_SOS_COMP_ID);

      m_comp_list.ptr[i]    = ci;
      m_comp_dc_tab.ptr[ci] = (c >> 4) & 15;
      m_comp_ac_tab.ptr[ci] = (c & 15) + (JPGD_MAX_HUFF_TABLES >> 1);
    }

    m_spectral_start  = get_bits(8);
    m_spectral_end    = get_bits(8);
    m_successive_high = get_bits(4);
    m_successive_low  = get_bits(4);

    if (!m_progressive_flag)
    {
      m_spectral_start = 0;
      m_spectral_end = 63;
    }

    num_left -= 3;

    /* read past whatever is num_left */
    while (num_left)
    {
      get_bits(8);
      num_left--;
    }
  }

  // Finds the next marker.
  int next_marker () {
    uint c, bytes;

    bytes = 0;

    do
    {
      do
      {
        bytes++;
        c = get_bits(8);
      } while (c != 0xFF);

      do
      {
        c = get_bits(8);
      } while (c == 0xFF);

    } while (c == 0);

    // If bytes > 0 here, there where extra bytes before the marker (not good).

    return c;
  }

  // Process markers. Returns when an SOFx, SOI, EOI, or SOS marker is
  // encountered.
  int process_markers (bool allow_restarts = false) {
    int c;

    for ( ; ; ) {
      c = next_marker();

      switch (c)
      {
        case M_SOF0:
        case M_SOF1:
        case M_SOF2:
        case M_SOF3:
        case M_SOF5:
        case M_SOF6:
        case M_SOF7:
        //case M_JPG:
        case M_SOF9:
        case M_SOF10:
        case M_SOF11:
        case M_SOF13:
        case M_SOF14:
        case M_SOF15:
        case M_SOI:
        case M_EOI:
        case M_SOS:
          return c;
        case M_DHT:
          read_dht_marker();
          break;
        // No arithmitic support - dumb patents!
        case M_DAC:
          stop_decoding(JPGD_NO_ARITHMITIC_SUPPORT);
          break;
        case M_DQT:
          read_dqt_marker();
          break;
        case M_DRI:
          read_dri_marker();
          break;
	case M_APP1: /* likely EXIF data */
          read_exif_marker();

	break;
        //case M_APP0:  /* no need to read the JFIF marker */

        case M_RST0:    /* no parameters */
        case M_RST1:
        case M_RST2:
        case M_RST3:
        case M_RST4:
        case M_RST5:
        case M_RST6:
        case M_RST7:
		if(allow_restarts)
			continue;
		else
			goto case;
        case M_JPG:
        case M_TEM:
          stop_decoding(JPGD_UNEXPECTED_MARKER);
          break;
        default:    /* must be DNL, DHP, EXP, APPn, JPGn, COM, or RESn or APP0 */
          skip_variable_marker();
          break;
      }
    }

    assert(0);
  }

  // Finds the start of image (SOI) marker.
  // This code is rather defensive: it only checks the first 512 bytes to avoid
  // false positives.
  void locate_soi_marker () {
    uint lastchar, thischar;
    uint bytesleft;

    lastchar = get_bits(8);

    thischar = get_bits(8);

    /* ok if it's a normal JPEG file without a special header */

    if ((lastchar == 0xFF) && (thischar == M_SOI))
      return;

    bytesleft = 4096; //512;

    for ( ; ; )
    {
      if (--bytesleft == 0)
        stop_decoding(JPGD_NOT_JPEG);

      lastchar = thischar;

      thischar = get_bits(8);

      if (lastchar == 0xFF)
      {
        if (thischar == M_SOI)
          break;
        else if (thischar == M_EOI) // get_bits will keep returning M_EOI if we read past the end
          stop_decoding(JPGD_NOT_JPEG);
      }
    }

    // Check the next character after marker: if it's not 0xFF, it can't be the start of the next marker, so the file is bad.
    thischar = (m_bit_buf >> 24) & 0xFF;

    if (thischar != 0xFF)
      stop_decoding(JPGD_NOT_JPEG);
  }

  // Find a start of frame (SOF) marker.
  void locate_sof_marker () {
    locate_soi_marker();

    int c = process_markers();

    switch (c)
    {
      case M_SOF2:
        m_progressive_flag = true;
        goto case;
      case M_SOF0:  /* baseline DCT */
      case M_SOF1:  /* extended sequential DCT */
        read_sof_marker();
        break;
      case M_SOF9:  /* Arithmitic coding */
        stop_decoding(JPGD_NO_ARITHMITIC_SUPPORT);
        break;
      default:
        stop_decoding(JPGD_UNSUPPORTED_MARKER);
        break;
    }
  }

  // Find a start of scan (SOS) marker.
  int locate_sos_marker () {
    int c;

    c = process_markers();

    if (c == M_EOI)
      return false;
    else if (c != M_SOS)
      stop_decoding(JPGD_UNEXPECTED_MARKER);

    read_sos_marker();

    return true;
  }

  // Reset everything to default/uninitialized state.
  void initit (JpegStreamReadFunc rfn) {
    m_pMem_blocks = null;
    m_error_code = JPGD_SUCCESS;
    m_ready_flag = false;
    m_image_x_size = m_image_y_size = 0;
    readfn = rfn;
    m_progressive_flag = false;

    memset(m_huff_ac.ptr, 0, m_huff_ac.sizeof);
    memset(m_huff_num.ptr, 0, m_huff_num.sizeof);
    memset(m_huff_val.ptr, 0, m_huff_val.sizeof);
    memset(m_quant.ptr, 0, m_quant.sizeof);

    m_scan_type = 0;
    m_comps_in_frame = 0;

    memset(m_comp_h_samp.ptr, 0, m_comp_h_samp.sizeof);
    memset(m_comp_v_samp.ptr, 0, m_comp_v_samp.sizeof);
    memset(m_comp_quant.ptr, 0, m_comp_quant.sizeof);
    memset(m_comp_ident.ptr, 0, m_comp_ident.sizeof);
    memset(m_comp_h_blocks.ptr, 0, m_comp_h_blocks.sizeof);
    memset(m_comp_v_blocks.ptr, 0, m_comp_v_blocks.sizeof);

    m_comps_in_scan = 0;
    memset(m_comp_list.ptr, 0, m_comp_list.sizeof);
    memset(m_comp_dc_tab.ptr, 0, m_comp_dc_tab.sizeof);
    memset(m_comp_ac_tab.ptr, 0, m_comp_ac_tab.sizeof);

    m_spectral_start = 0;
    m_spectral_end = 0;
    m_successive_low = 0;
    m_successive_high = 0;
    m_max_mcu_x_size = 0;
    m_max_mcu_y_size = 0;
    m_blocks_per_mcu = 0;
    m_max_blocks_per_row = 0;
    m_mcus_per_row = 0;
    m_mcus_per_col = 0;
    m_expanded_blocks_per_component = 0;
    m_expanded_blocks_per_mcu = 0;
    m_expanded_blocks_per_row = 0;
    m_freq_domain_chroma_upsample = false;

    memset(m_mcu_org.ptr, 0, m_mcu_org.sizeof);

    m_total_lines_left = 0;
    m_mcu_lines_left = 0;
    m_real_dest_bytes_per_scan_line = 0;
    m_dest_bytes_per_scan_line = 0;
    m_dest_bytes_per_pixel = 0;

    memset(m_pHuff_tabs.ptr, 0, m_pHuff_tabs.sizeof);

    memset(m_dc_coeffs.ptr, 0, m_dc_coeffs.sizeof);
    memset(m_ac_coeffs.ptr, 0, m_ac_coeffs.sizeof);
    memset(m_block_y_mcu.ptr, 0, m_block_y_mcu.sizeof);

    m_eob_run = 0;

    memset(m_block_y_mcu.ptr, 0, m_block_y_mcu.sizeof);

    m_pIn_buf_ofs = m_in_buf.ptr;
    m_in_buf_left = 0;
    m_eof_flag = false;
    m_tem_flag = 0;

    memset(m_in_buf_pad_start.ptr, 0, m_in_buf_pad_start.sizeof);
    memset(m_in_buf.ptr, 0, m_in_buf.sizeof);
    memset(m_in_buf_pad_end.ptr, 0, m_in_buf_pad_end.sizeof);

    m_restart_interval = 0;
    m_restarts_left    = 0;
    m_next_restart_num = 0;

    m_max_mcus_per_row = 0;
    m_max_blocks_per_mcu = 0;
    m_max_mcus_per_col = 0;

    memset(m_last_dc_val.ptr, 0, m_last_dc_val.sizeof);
    m_pMCU_coefficients = null;
    m_pSample_buf = null;

    m_total_bytes_read = 0;

    m_pScan_line_0 = null;
    m_pScan_line_1 = null;

    // Ready the input buffer.
    prep_in_buffer();

    // Prime the bit buffer.
    m_bits_left = 16;
    m_bit_buf = 0;

    get_bits(16);
    get_bits(16);

    for (int i = 0; i < JPGD_MAX_BLOCKS_PER_MCU; i++)
      m_mcu_block_max_zag.ptr[i] = 64;
  }

  enum SCALEBITS = 16;
  enum ONE_HALF = (cast(int) 1 << (SCALEBITS-1));
  enum FIX(float x) = (cast(int)((x) * (1L<<SCALEBITS) + 0.5f));

  // Create a few tables that allow us to quickly convert YCbCr to RGB.
  void create_look_ups () {
    for (int i = 0; i <= 255; i++)
    {
      int k = i - 128;
      m_crr.ptr[i] = ( FIX!(1.40200f)  * k + ONE_HALF) >> SCALEBITS;
      m_cbb.ptr[i] = ( FIX!(1.77200f)  * k + ONE_HALF) >> SCALEBITS;
      m_crg.ptr[i] = (-FIX!(0.71414f)) * k;
      m_cbg.ptr[i] = (-FIX!(0.34414f)) * k + ONE_HALF;
    }
  }

  // This method throws back into the stream any bytes that where read
  // into the bit buffer during initial marker scanning.
  void fix_in_buffer () {
    // In case any 0xFF's where pulled into the buffer during marker scanning.
    assert((m_bits_left & 7) == 0);

    if (m_bits_left == 16)
      stuff_char(cast(ubyte)(m_bit_buf & 0xFF));

    if (m_bits_left >= 8)
      stuff_char(cast(ubyte)((m_bit_buf >> 8) & 0xFF));

    stuff_char(cast(ubyte)((m_bit_buf >> 16) & 0xFF));
    stuff_char(cast(ubyte)((m_bit_buf >> 24) & 0xFF));

    m_bits_left = 16;
    get_bits_no_markers(16);
    get_bits_no_markers(16);
  }

  void transform_mcu (int mcu_row) {
    jpgd_block_t* pSrc_ptr = m_pMCU_coefficients;
    ubyte* pDst_ptr = m_pSample_buf + mcu_row * m_blocks_per_mcu * 64;

    for (int mcu_block = 0; mcu_block < m_blocks_per_mcu; mcu_block++)
    {
      idct(pSrc_ptr, pDst_ptr, m_mcu_block_max_zag.ptr[mcu_block]);
      pSrc_ptr += 64;
      pDst_ptr += 64;
    }
  }

  static immutable ubyte[64] s_max_rc = [
    17, 18, 34, 50, 50, 51, 52, 52, 52, 68, 84, 84, 84, 84, 85, 86, 86, 86, 86, 86,
    102, 118, 118, 118, 118, 118, 118, 119, 120, 120, 120, 120, 120, 120, 120, 136,
    136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136,
    136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136
  ];

  void transform_mcu_expand (int mcu_row) {
    jpgd_block_t* pSrc_ptr = m_pMCU_coefficients;
    ubyte* pDst_ptr = m_pSample_buf + mcu_row * m_expanded_blocks_per_mcu * 64;

    // Y IDCT
    int mcu_block;
    for (mcu_block = 0; mcu_block < m_expanded_blocks_per_component; mcu_block++)
    {
      idct(pSrc_ptr, pDst_ptr, m_mcu_block_max_zag.ptr[mcu_block]);
      pSrc_ptr += 64;
      pDst_ptr += 64;
    }

    // Chroma IDCT, with upsampling
    jpgd_block_t[64] temp_block;

    for (int i = 0; i < 2; i++)
    {
      DCT_Upsample.Matrix44 P, Q, R, S;

      assert(m_mcu_block_max_zag.ptr[mcu_block] >= 1);
      assert(m_mcu_block_max_zag.ptr[mcu_block] <= 64);

      int max_zag = m_mcu_block_max_zag.ptr[mcu_block++] - 1;
      if (max_zag <= 0) max_zag = 0; // should never happen, only here to shut up static analysis
      switch (s_max_rc.ptr[max_zag])
      {
      case 1*16+1:
        DCT_Upsample.P_Q!(1, 1).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(1, 1).calc(R, S, pSrc_ptr);
        break;
      case 1*16+2:
        DCT_Upsample.P_Q!(1, 2).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(1, 2).calc(R, S, pSrc_ptr);
        break;
      case 2*16+2:
        DCT_Upsample.P_Q!(2, 2).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(2, 2).calc(R, S, pSrc_ptr);
        break;
      case 3*16+2:
        DCT_Upsample.P_Q!(3, 2).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(3, 2).calc(R, S, pSrc_ptr);
        break;
      case 3*16+3:
        DCT_Upsample.P_Q!(3, 3).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(3, 3).calc(R, S, pSrc_ptr);
        break;
      case 3*16+4:
        DCT_Upsample.P_Q!(3, 4).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(3, 4).calc(R, S, pSrc_ptr);
        break;
      case 4*16+4:
        DCT_Upsample.P_Q!(4, 4).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(4, 4).calc(R, S, pSrc_ptr);
        break;
      case 5*16+4:
        DCT_Upsample.P_Q!(5, 4).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(5, 4).calc(R, S, pSrc_ptr);
        break;
      case 5*16+5:
        DCT_Upsample.P_Q!(5, 5).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(5, 5).calc(R, S, pSrc_ptr);
        break;
      case 5*16+6:
        DCT_Upsample.P_Q!(5, 6).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(5, 6).calc(R, S, pSrc_ptr);
        break;
      case 6*16+6:
        DCT_Upsample.P_Q!(6, 6).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(6, 6).calc(R, S, pSrc_ptr);
        break;
      case 7*16+6:
        DCT_Upsample.P_Q!(7, 6).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(7, 6).calc(R, S, pSrc_ptr);
        break;
      case 7*16+7:
        DCT_Upsample.P_Q!(7, 7).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(7, 7).calc(R, S, pSrc_ptr);
        break;
      case 7*16+8:
        DCT_Upsample.P_Q!(7, 8).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(7, 8).calc(R, S, pSrc_ptr);
        break;
      case 8*16+8:
        DCT_Upsample.P_Q!(8, 8).calc(P, Q, pSrc_ptr);
        DCT_Upsample.R_S!(8, 8).calc(R, S, pSrc_ptr);
        break;
      default:
        assert(false);
      }

      auto a = DCT_Upsample.Matrix44(P + Q);
      P -= Q;
      DCT_Upsample.Matrix44* b = &P;
      auto c = DCT_Upsample.Matrix44(R + S);
      R -= S;
      DCT_Upsample.Matrix44* d = &R;

      DCT_Upsample.Matrix44.add_and_store(temp_block.ptr, a, c);
      idct_4x4(temp_block.ptr, pDst_ptr);
      pDst_ptr += 64;

      DCT_Upsample.Matrix44.sub_and_store(temp_block.ptr, a, c);
      idct_4x4(temp_block.ptr, pDst_ptr);
      pDst_ptr += 64;

      DCT_Upsample.Matrix44.add_and_store(temp_block.ptr, *b, *d);
      idct_4x4(temp_block.ptr, pDst_ptr);
      pDst_ptr += 64;

      DCT_Upsample.Matrix44.sub_and_store(temp_block.ptr, *b, *d);
      idct_4x4(temp_block.ptr, pDst_ptr);
      pDst_ptr += 64;

      pSrc_ptr += 64;
    }
  }

  // Loads and dequantizes the next row of (already decoded) coefficients.
  // Progressive images only.
  void load_next_row () {
    int i;
    jpgd_block_t *p;
    jpgd_quant_t *q;
    int mcu_row, mcu_block, row_block = 0;
    int component_num, component_id;
    int[JPGD_MAX_COMPONENTS] block_x_mcu;

    memset(block_x_mcu.ptr, 0, JPGD_MAX_COMPONENTS * int.sizeof);

    for (mcu_row = 0; mcu_row < m_mcus_per_row; mcu_row++)
    {
      int block_x_mcu_ofs = 0, block_y_mcu_ofs = 0;

      for (mcu_block = 0; mcu_block < m_blocks_per_mcu; mcu_block++)
      {
        component_id = m_mcu_org.ptr[mcu_block];
        q = m_quant.ptr[m_comp_quant.ptr[component_id]];

        p = m_pMCU_coefficients + 64 * mcu_block;

        jpgd_block_t* pAC = coeff_buf_getp(m_ac_coeffs.ptr[component_id], block_x_mcu.ptr[component_id] + block_x_mcu_ofs, m_block_y_mcu.ptr[component_id] + block_y_mcu_ofs);
        jpgd_block_t* pDC = coeff_buf_getp(m_dc_coeffs.ptr[component_id], block_x_mcu.ptr[component_id] + block_x_mcu_ofs, m_block_y_mcu.ptr[component_id] + block_y_mcu_ofs);
        p[0] = pDC[0];
        memcpy(&p[1], &pAC[1], 63 * jpgd_block_t.sizeof);

        for (i = 63; i > 0; i--)
          if (p[g_ZAG[i]])
            break;

        m_mcu_block_max_zag.ptr[mcu_block] = i + 1;

        for ( ; i >= 0; i--)
          if (p[g_ZAG[i]])
            p[g_ZAG[i]] = cast(jpgd_block_t)(p[g_ZAG[i]] * q[i]);

        row_block++;

        if (m_comps_in_scan == 1)
          block_x_mcu.ptr[component_id]++;
        else
        {
          if (++block_x_mcu_ofs == m_comp_h_samp.ptr[component_id])
          {
            block_x_mcu_ofs = 0;

            if (++block_y_mcu_ofs == m_comp_v_samp.ptr[component_id])
            {
              block_y_mcu_ofs = 0;

              block_x_mcu.ptr[component_id] += m_comp_h_samp.ptr[component_id];
            }
          }
        }
      }

      if (m_freq_domain_chroma_upsample)
        transform_mcu_expand(mcu_row);
      else
        transform_mcu(mcu_row);
    }

    if (m_comps_in_scan == 1)
      m_block_y_mcu.ptr[m_comp_list.ptr[0]]++;
    else
    {
      for (component_num = 0; component_num < m_comps_in_scan; component_num++)
      {
        component_id = m_comp_list.ptr[component_num];

        m_block_y_mcu.ptr[component_id] += m_comp_v_samp.ptr[component_id];
      }
    }
  }

  // Restart interval processing.
  void process_restart () {
    int i;
    int c = 0;

    // Align to a byte boundry
    // FIXME: Is this really necessary? get_bits_no_markers() never reads in markers!
    //get_bits_no_markers(m_bits_left & 7);

    // Let's scan a little bit to find the marker, but not _too_ far.
    // 1536 is a "fudge factor" that determines how much to scan.
    for (i = 1536; i > 0; i--)
      if (get_char() == 0xFF)
        break;

    if (i == 0)
      stop_decoding(JPGD_BAD_RESTART_MARKER);

    for ( ; i > 0; i--)
      if ((c = get_char()) != 0xFF)
        break;

    if (i == 0)
      stop_decoding(JPGD_BAD_RESTART_MARKER);

    // Is it the expected marker? If not, something bad happened.
    if (c != (m_next_restart_num + M_RST0))
      stop_decoding(JPGD_BAD_RESTART_MARKER);

    // Reset each component's DC prediction values.
    memset(&m_last_dc_val, 0, m_comps_in_frame * uint.sizeof);

    m_eob_run = 0;

    m_restarts_left = m_restart_interval;

    m_next_restart_num = (m_next_restart_num + 1) & 7;

    // Get the bit buffer going again...

    m_bits_left = 16;
    get_bits_no_markers(16);
    get_bits_no_markers(16);
  }

  static int dequantize_ac (int c, int q) { pragma(inline, true); c *= q; return c; }

  // Decodes and dequantizes the next row of coefficients.
  void decode_next_row () {
    int row_block = 0;

    for (int mcu_row = 0; mcu_row < m_mcus_per_row; mcu_row++)
    {
      if ((m_restart_interval) && (m_restarts_left == 0))
        process_restart();

      jpgd_block_t* p = m_pMCU_coefficients;
      for (int mcu_block = 0; mcu_block < m_blocks_per_mcu; mcu_block++, p += 64)
      {
        int component_id = m_mcu_org.ptr[mcu_block];
        jpgd_quant_t* q = m_quant.ptr[m_comp_quant.ptr[component_id]];

        int r, s;
        s = huff_decode(m_pHuff_tabs.ptr[m_comp_dc_tab.ptr[component_id]], r);
        s = JPGD_HUFF_EXTEND(r, s);

        m_last_dc_val.ptr[component_id] = (s += m_last_dc_val.ptr[component_id]);

        p[0] = cast(jpgd_block_t)(s * q[0]);

        int prev_num_set = m_mcu_block_max_zag.ptr[mcu_block];

        huff_tables *pH = m_pHuff_tabs.ptr[m_comp_ac_tab.ptr[component_id]];

        int k;
        for (k = 1; k < 64; k++)
        {
          int extra_bits;
          s = huff_decode(pH, extra_bits);

          r = s >> 4;
          s &= 15;

          if (s)
          {
            if (r)
            {
              if ((k + r) > 63)
                stop_decoding(JPGD_DECODE_ERROR);

              if (k < prev_num_set)
              {
                int n = JPGD_MIN(r, prev_num_set - k);
                int kt = k;
                while (n--)
                  p[g_ZAG[kt++]] = 0;
              }

              k += r;
            }

            s = JPGD_HUFF_EXTEND(extra_bits, s);

            assert(k < 64);

            p[g_ZAG[k]] = cast(jpgd_block_t)(dequantize_ac(s, q[k])); //s * q[k];
          }
          else
          {
            if (r == 15)
            {
              if ((k + 16) > 64)
                stop_decoding(JPGD_DECODE_ERROR);

              if (k < prev_num_set)
              {
                int n = JPGD_MIN(16, prev_num_set - k);
                int kt = k;
                while (n--)
                {
                  assert(kt <= 63);
                  p[g_ZAG[kt++]] = 0;
                }
              }

              k += 16 - 1; // - 1 because the loop counter is k
              assert(p[g_ZAG[k]] == 0);
            }
            else
              break;
          }
        }

        if (k < prev_num_set)
        {
          int kt = k;
          while (kt < prev_num_set)
            p[g_ZAG[kt++]] = 0;
        }

        m_mcu_block_max_zag.ptr[mcu_block] = k;

        row_block++;
      }

      if (m_freq_domain_chroma_upsample)
        transform_mcu_expand(mcu_row);
      else
        transform_mcu(mcu_row);

      m_restarts_left--;
    }
  }

  // YCbCr H1V1 (1x1:1:1, 3 m_blocks per MCU) to RGB
  void H1V1Convert () {
    int row = m_max_mcu_y_size - m_mcu_lines_left;
    ubyte *d = m_pScan_line_0;
    ubyte *s = m_pSample_buf + row * 8;

    for (int i = m_max_mcus_per_row; i > 0; i--)
    {
      for (int j = 0; j < 8; j++)
      {
        int y = s[j];
        int cb = s[64+j];
        int cr = s[128+j];

        d[0] = clamp(y + m_crr.ptr[cr]);
        d[1] = clamp(y + ((m_crg.ptr[cr] + m_cbg.ptr[cb]) >> 16));
        d[2] = clamp(y + m_cbb.ptr[cb]);
        d[3] = 255;

        d += 4;
      }

      s += 64*3;
    }
  }

  // YCbCr H2V1 (2x1:1:1, 4 m_blocks per MCU) to RGB
  void H2V1Convert () {
    int row = m_max_mcu_y_size - m_mcu_lines_left;
    ubyte *d0 = m_pScan_line_0;
    ubyte *y = m_pSample_buf + row * 8;
    ubyte *c = m_pSample_buf + 2*64 + row * 8;

    for (int i = m_max_mcus_per_row; i > 0; i--)
    {
      for (int l = 0; l < 2; l++)
      {
        for (int j = 0; j < 4; j++)
        {
          int cb = c[0];
          int cr = c[64];

          int rc = m_crr.ptr[cr];
          int gc = ((m_crg.ptr[cr] + m_cbg.ptr[cb]) >> 16);
          int bc = m_cbb.ptr[cb];

          int yy = y[j<<1];
          d0[0] = clamp(yy+rc);
          d0[1] = clamp(yy+gc);
          d0[2] = clamp(yy+bc);
          d0[3] = 255;

          yy = y[(j<<1)+1];
          d0[4] = clamp(yy+rc);
          d0[5] = clamp(yy+gc);
          d0[6] = clamp(yy+bc);
          d0[7] = 255;

          d0 += 8;

          c++;
        }
        y += 64;
      }

      y += 64*4 - 64*2;
      c += 64*4 - 8;
    }
  }

  // YCbCr H2V1 (1x2:1:1, 4 m_blocks per MCU) to RGB
  void H1V2Convert () {
    int row = m_max_mcu_y_size - m_mcu_lines_left;
    ubyte *d0 = m_pScan_line_0;
    ubyte *d1 = m_pScan_line_1;
    ubyte *y;
    ubyte *c;

    if (row < 8)
      y = m_pSample_buf + row * 8;
    else
      y = m_pSample_buf + 64*1 + (row & 7) * 8;

    c = m_pSample_buf + 64*2 + (row >> 1) * 8;

    for (int i = m_max_mcus_per_row; i > 0; i--)
    {
      for (int j = 0; j < 8; j++)
      {
        int cb = c[0+j];
        int cr = c[64+j];

        int rc = m_crr.ptr[cr];
        int gc = ((m_crg.ptr[cr] + m_cbg.ptr[cb]) >> 16);
        int bc = m_cbb.ptr[cb];

        int yy = y[j];
        d0[0] = clamp(yy+rc);
        d0[1] = clamp(yy+gc);
        d0[2] = clamp(yy+bc);
        d0[3] = 255;

        yy = y[8+j];
        d1[0] = clamp(yy+rc);
        d1[1] = clamp(yy+gc);
        d1[2] = clamp(yy+bc);
        d1[3] = 255;

        d0 += 4;
        d1 += 4;
      }

      y += 64*4;
      c += 64*4;
    }
  }

  // YCbCr H2V2 (2x2:1:1, 6 m_blocks per MCU) to RGB
  void H2V2Convert () {
    int row = m_max_mcu_y_size - m_mcu_lines_left;
    ubyte *d0 = m_pScan_line_0;
    ubyte *d1 = m_pScan_line_1;
    ubyte *y;
    ubyte *c;

    if (row < 8)
      y = m_pSample_buf + row * 8;
    else
      y = m_pSample_buf + 64*2 + (row & 7) * 8;

    c = m_pSample_buf + 64*4 + (row >> 1) * 8;

    for (int i = m_max_mcus_per_row; i > 0; i--)
    {
      for (int l = 0; l < 2; l++)
      {
        for (int j = 0; j < 8; j += 2)
        {
          int cb = c[0];
          int cr = c[64];

          int rc = m_crr.ptr[cr];
          int gc = ((m_crg.ptr[cr] + m_cbg.ptr[cb]) >> 16);
          int bc = m_cbb.ptr[cb];

          int yy = y[j];
          d0[0] = clamp(yy+rc);
          d0[1] = clamp(yy+gc);
          d0[2] = clamp(yy+bc);
          d0[3] = 255;

          yy = y[j+1];
          d0[4] = clamp(yy+rc);
          d0[5] = clamp(yy+gc);
          d0[6] = clamp(yy+bc);
          d0[7] = 255;

          yy = y[j+8];
          d1[0] = clamp(yy+rc);
          d1[1] = clamp(yy+gc);
          d1[2] = clamp(yy+bc);
          d1[3] = 255;

          yy = y[j+8+1];
          d1[4] = clamp(yy+rc);
          d1[5] = clamp(yy+gc);
          d1[6] = clamp(yy+bc);
          d1[7] = 255;

          d0 += 8;
          d1 += 8;

          c++;
        }
        y += 64;
      }

      y += 64*6 - 64*2;
      c += 64*6 - 8;
    }
  }

  // Y (1 block per MCU) to 8-bit grayscale
  void gray_convert () {
    int row = m_max_mcu_y_size - m_mcu_lines_left;
    ubyte *d = m_pScan_line_0;
    ubyte *s = m_pSample_buf + row * 8;

    for (int i = m_max_mcus_per_row; i > 0; i--)
    {
      *cast(uint*)d = *cast(uint*)s;
      *cast(uint*)(&d[4]) = *cast(uint*)(&s[4]);

      s += 64;
      d += 8;
    }
  }

  void expanded_convert () {
    int row = m_max_mcu_y_size - m_mcu_lines_left;

    ubyte* Py = m_pSample_buf + (row / 8) * 64 * m_comp_h_samp.ptr[0] + (row & 7) * 8;

    ubyte* d = m_pScan_line_0;

    for (int i = m_max_mcus_per_row; i > 0; i--)
    {
      for (int k = 0; k < m_max_mcu_x_size; k += 8)
      {
        immutable int Y_ofs = k * 8;
        immutable int Cb_ofs = Y_ofs + 64 * m_expanded_blocks_per_component;
        immutable int Cr_ofs = Y_ofs + 64 * m_expanded_blocks_per_component * 2;
        for (int j = 0; j < 8; j++)
        {
          int y = Py[Y_ofs + j];
          int cb = Py[Cb_ofs + j];
          int cr = Py[Cr_ofs + j];

          d[0] = clamp(y + m_crr.ptr[cr]);
          d[1] = clamp(y + ((m_crg.ptr[cr] + m_cbg.ptr[cb]) >> 16));
          d[2] = clamp(y + m_cbb.ptr[cb]);
          d[3] = 255;

          d += 4;
        }
      }

      Py += 64 * m_expanded_blocks_per_mcu;
    }
  }

  // Find end of image (EOI) marker, so we can return to the user the exact size of the input stream.
  void find_eoi () {
    if (!m_progressive_flag)
    {
      // Attempt to read the EOI marker.
      //get_bits_no_markers(m_bits_left & 7);

      // Prime the bit buffer
      m_bits_left = 16;
      get_bits(16);
      get_bits(16);

      // The next marker _should_ be EOI
      process_markers(true); // but restarts are allowed as we can harmlessly skip them at the end of the stream
    }

    m_total_bytes_read -= m_in_buf_left;
  }

  // Creates the tables needed for efficient Huffman decoding.
  void make_huff_table (int index, huff_tables *pH) {
    int p, i, l, si;
    ubyte[257] huffsize;
    uint[257] huffcode;
    uint code;
    uint subtree;
    int code_size;
    int lastp;
    int nextfreeentry;
    int currententry;

    pH.ac_table = m_huff_ac.ptr[index] != 0;

    p = 0;

    for (l = 1; l <= 16; l++)
    {
      for (i = 1; i <= m_huff_num.ptr[index][l]; i++)
        huffsize.ptr[p++] = cast(ubyte)(l);
    }

    huffsize.ptr[p] = 0;

    lastp = p;

    code = 0;
    si = huffsize.ptr[0];
    p = 0;

    while (huffsize.ptr[p])
    {
      while (huffsize.ptr[p] == si)
      {
        huffcode.ptr[p++] = code;
        code++;
      }

      code <<= 1;
      si++;
    }

    memset(pH.look_up.ptr, 0, pH.look_up.sizeof);
    memset(pH.look_up2.ptr, 0, pH.look_up2.sizeof);
    memset(pH.tree.ptr, 0, pH.tree.sizeof);
    memset(pH.code_size.ptr, 0, pH.code_size.sizeof);

    nextfreeentry = -1;

    p = 0;

    while (p < lastp)
    {
      i = m_huff_val.ptr[index][p];
      code = huffcode.ptr[p];
      code_size = huffsize.ptr[p];

      pH.code_size.ptr[i] = cast(ubyte)(code_size);

      if (code_size <= 8)
      {
        code <<= (8 - code_size);

        for (l = 1 << (8 - code_size); l > 0; l--)
        {
          assert(i < 256);

          pH.look_up.ptr[code] = i;

          bool has_extrabits = false;
          int extra_bits = 0;
          int num_extra_bits = i & 15;

          int bits_to_fetch = code_size;
          if (num_extra_bits)
          {
            int total_codesize = code_size + num_extra_bits;
            if (total_codesize <= 8)
            {
              has_extrabits = true;
              extra_bits = ((1 << num_extra_bits) - 1) & (code >> (8 - total_codesize));
              assert(extra_bits <= 0x7FFF);
              bits_to_fetch += num_extra_bits;
            }
          }

          if (!has_extrabits)
            pH.look_up2.ptr[code] = i | (bits_to_fetch << 8);
          else
            pH.look_up2.ptr[code] = i | 0x8000 | (extra_bits << 16) | (bits_to_fetch << 8);

          code++;
        }
      }
      else
      {
        subtree = (code >> (code_size - 8)) & 0xFF;

        currententry = pH.look_up.ptr[subtree];

        if (currententry == 0)
        {
          pH.look_up.ptr[subtree] = currententry = nextfreeentry;
          pH.look_up2.ptr[subtree] = currententry = nextfreeentry;

          nextfreeentry -= 2;
        }

        code <<= (16 - (code_size - 8));

        for (l = code_size; l > 9; l--)
        {
          if ((code & 0x8000) == 0)
            currententry--;

          if (pH.tree.ptr[-currententry - 1] == 0)
          {
            pH.tree.ptr[-currententry - 1] = nextfreeentry;

            currententry = nextfreeentry;

            nextfreeentry -= 2;
          }
          else
            currententry = pH.tree.ptr[-currententry - 1];

          code <<= 1;
        }

        if ((code & 0x8000) == 0)
          currententry--;

        pH.tree.ptr[-currententry - 1] = i;
      }

      p++;
    }
  }

  // Verifies the quantization tables needed for this scan are available.
  void check_quant_tables () {
    for (int i = 0; i < m_comps_in_scan; i++)
      if (m_quant.ptr[m_comp_quant.ptr[m_comp_list.ptr[i]]] == null)
        stop_decoding(JPGD_UNDEFINED_QUANT_TABLE);
  }

  // Verifies that all the Huffman tables needed for this scan are available.
  void check_huff_tables () {
    for (int i = 0; i < m_comps_in_scan; i++)
    {
      if ((m_spectral_start == 0) && (m_huff_num.ptr[m_comp_dc_tab.ptr[m_comp_list.ptr[i]]] == null))
        stop_decoding(JPGD_UNDEFINED_HUFF_TABLE);

      if ((m_spectral_end > 0) && (m_huff_num.ptr[m_comp_ac_tab.ptr[m_comp_list.ptr[i]]] == null))
        stop_decoding(JPGD_UNDEFINED_HUFF_TABLE);
    }

    for (int i = 0; i < JPGD_MAX_HUFF_TABLES; i++)
      if (m_huff_num.ptr[i])
      {
        if (!m_pHuff_tabs.ptr[i])
          m_pHuff_tabs.ptr[i] = cast(huff_tables*)alloc(huff_tables.sizeof);

        make_huff_table(i, m_pHuff_tabs.ptr[i]);
      }
  }

  // Determines the component order inside each MCU.
  // Also calcs how many MCU's are on each row, etc.
  void calc_mcu_block_order () {
    int component_num, component_id;
    int max_h_samp = 0, max_v_samp = 0;

    for (component_id = 0; component_id < m_comps_in_frame; component_id++)
    {
      if (m_comp_h_samp.ptr[component_id] > max_h_samp)
        max_h_samp = m_comp_h_samp.ptr[component_id];

      if (m_comp_v_samp.ptr[component_id] > max_v_samp)
        max_v_samp = m_comp_v_samp.ptr[component_id];
    }

    for (component_id = 0; component_id < m_comps_in_frame; component_id++)
    {
      m_comp_h_blocks.ptr[component_id] = ((((m_image_x_size * m_comp_h_samp.ptr[component_id]) + (max_h_samp - 1)) / max_h_samp) + 7) / 8;
      m_comp_v_blocks.ptr[component_id] = ((((m_image_y_size * m_comp_v_samp.ptr[component_id]) + (max_v_samp - 1)) / max_v_samp) + 7) / 8;
    }

    if (m_comps_in_scan == 1)
    {
      m_mcus_per_row = m_comp_h_blocks.ptr[m_comp_list.ptr[0]];
      m_mcus_per_col = m_comp_v_blocks.ptr[m_comp_list.ptr[0]];
    }
    else
    {
      m_mcus_per_row = (((m_image_x_size + 7) / 8) + (max_h_samp - 1)) / max_h_samp;
      m_mcus_per_col = (((m_image_y_size + 7) / 8) + (max_v_samp - 1)) / max_v_samp;
    }

    if (m_comps_in_scan == 1)
    {
      m_mcu_org.ptr[0] = m_comp_list.ptr[0];

      m_blocks_per_mcu = 1;
    }
    else
    {
      m_blocks_per_mcu = 0;

      for (component_num = 0; component_num < m_comps_in_scan; component_num++)
      {
        int num_blocks;

        component_id = m_comp_list.ptr[component_num];

        num_blocks = m_comp_h_samp.ptr[component_id] * m_comp_v_samp.ptr[component_id];

        while (num_blocks--)
          m_mcu_org.ptr[m_blocks_per_mcu++] = component_id;
      }
    }
  }

  // Starts a new scan.
  int init_scan () {
    if (!locate_sos_marker())
      return false;

    calc_mcu_block_order();

    check_huff_tables();

    check_quant_tables();

    memset(m_last_dc_val.ptr, 0, m_comps_in_frame * uint.sizeof);

    m_eob_run = 0;

    if (m_restart_interval)
    {
      m_restarts_left = m_restart_interval;
      m_next_restart_num = 0;
    }

    fix_in_buffer();

    return true;
  }

  // Starts a frame. Determines if the number of components or sampling factors
  // are supported.
  void init_frame () {
    int i;

    if (m_comps_in_frame == 1)
    {
      version(jpegd_test) {{ import std.stdio; stderr.writeln("m_comp_h_samp=", m_comp_h_samp.ptr[0], "; m_comp_v_samp=", m_comp_v_samp.ptr[0]); }}

      //if ((m_comp_h_samp.ptr[0] != 1) || (m_comp_v_samp.ptr[0] != 1))
      //  stop_decoding(JPGD_UNSUPPORTED_SAMP_FACTORS);

      if ((m_comp_h_samp.ptr[0] == 1) && (m_comp_v_samp.ptr[0] == 1))
      {
        m_scan_type = JPGD_GRAYSCALE;
        m_max_blocks_per_mcu = 1;
        m_max_mcu_x_size = 8;
        m_max_mcu_y_size = 8;
      }
      else if ((m_comp_h_samp.ptr[0] == 2) && (m_comp_v_samp.ptr[0] == 2))
      {
        //k8: i added this, and i absolutely don't know what it means; but it decoded two sample images i found
        m_scan_type = JPGD_GRAYSCALE;
        m_max_blocks_per_mcu = 4;
        m_max_mcu_x_size = 8;
        m_max_mcu_y_size = 8;
      }
      else if ((m_comp_h_samp.ptr[0] == 2) && (m_comp_v_samp.ptr[0] == 1))
      {
      	// adr added this. idk if it is right seems wrong since it the same as above but..... meh ship it.
        m_scan_type = JPGD_GRAYSCALE;
        m_max_blocks_per_mcu = 4;
        m_max_mcu_x_size = 8;
        m_max_mcu_y_size = 8;
      }
      else {
      // code -231 brings us here
      //import std.conv;
      //assert(0, to!string(m_comp_h_samp) ~ to!string(m_comp_v_samp));
        stop_decoding(JPGD_UNSUPPORTED_SAMP_FACTORS);
      }
    }
    else if (m_comps_in_frame == 3)
    {
      if ( ((m_comp_h_samp.ptr[1] != 1) || (m_comp_v_samp.ptr[1] != 1)) ||
           ((m_comp_h_samp.ptr[2] != 1) || (m_comp_v_samp.ptr[2] != 1)) )
        stop_decoding(JPGD_UNSUPPORTED_SAMP_FACTORS);

      if ((m_comp_h_samp.ptr[0] == 1) && (m_comp_v_samp.ptr[0] == 1))
      {
        m_scan_type = JPGD_YH1V1;

        m_max_blocks_per_mcu = 3;
        m_max_mcu_x_size = 8;
        m_max_mcu_y_size = 8;
      }
      else if ((m_comp_h_samp.ptr[0] == 2) && (m_comp_v_samp.ptr[0] == 1))
      {
        m_scan_type = JPGD_YH2V1;
        m_max_blocks_per_mcu = 4;
        m_max_mcu_x_size = 16;
        m_max_mcu_y_size = 8;
      }
      else if ((m_comp_h_samp.ptr[0] == 1) && (m_comp_v_samp.ptr[0] == 2))
      {
        m_scan_type = JPGD_YH1V2;
        m_max_blocks_per_mcu = 4;
        m_max_mcu_x_size = 8;
        m_max_mcu_y_size = 16;
      }
      else if ((m_comp_h_samp.ptr[0] == 2) && (m_comp_v_samp.ptr[0] == 2))
      {
        m_scan_type = JPGD_YH2V2;
        m_max_blocks_per_mcu = 6;
        m_max_mcu_x_size = 16;
        m_max_mcu_y_size = 16;
      }
      else
        stop_decoding(JPGD_UNSUPPORTED_SAMP_FACTORS);
    }
    else
      stop_decoding(JPGD_UNSUPPORTED_COLORSPACE);

    m_max_mcus_per_row = (m_image_x_size + (m_max_mcu_x_size - 1)) / m_max_mcu_x_size;
    m_max_mcus_per_col = (m_image_y_size + (m_max_mcu_y_size - 1)) / m_max_mcu_y_size;

    // These values are for the *destination* pixels: after conversion.
    if (m_scan_type == JPGD_GRAYSCALE)
      m_dest_bytes_per_pixel = 1;
    else
      m_dest_bytes_per_pixel = 4;

    m_dest_bytes_per_scan_line = ((m_image_x_size + 15) & 0xFFF0) * m_dest_bytes_per_pixel;

    m_real_dest_bytes_per_scan_line = (m_image_x_size * m_dest_bytes_per_pixel);

    // Initialize two scan line buffers.
    m_pScan_line_0 = cast(ubyte*)alloc(m_dest_bytes_per_scan_line, true);
    if ((m_scan_type == JPGD_YH1V2) || (m_scan_type == JPGD_YH2V2))
      m_pScan_line_1 = cast(ubyte*)alloc(m_dest_bytes_per_scan_line, true);

    m_max_blocks_per_row = m_max_mcus_per_row * m_max_blocks_per_mcu;

    // Should never happen
    if (m_max_blocks_per_row > JPGD_MAX_BLOCKS_PER_ROW)
      stop_decoding(JPGD_ASSERTION_ERROR);

    // Allocate the coefficient buffer, enough for one MCU
    m_pMCU_coefficients = cast(jpgd_block_t*)alloc(m_max_blocks_per_mcu * 64 * jpgd_block_t.sizeof);

    for (i = 0; i < m_max_blocks_per_mcu; i++)
      m_mcu_block_max_zag.ptr[i] = 64;

    m_expanded_blocks_per_component = m_comp_h_samp.ptr[0] * m_comp_v_samp.ptr[0];
    m_expanded_blocks_per_mcu = m_expanded_blocks_per_component * m_comps_in_frame;
    m_expanded_blocks_per_row = m_max_mcus_per_row * m_expanded_blocks_per_mcu;
    // Freq. domain chroma upsampling is only supported for H2V2 subsampling factor (the most common one I've seen).
    m_freq_domain_chroma_upsample = false;
    version(JPGD_SUPPORT_FREQ_DOMAIN_UPSAMPLING) {
      m_freq_domain_chroma_upsample = (m_expanded_blocks_per_mcu == 4*3);
    }

    if (m_freq_domain_chroma_upsample)
      m_pSample_buf = cast(ubyte*)alloc(m_expanded_blocks_per_row * 64);
    else
      m_pSample_buf = cast(ubyte*)alloc(m_max_blocks_per_row * 64);

    m_total_lines_left = m_image_y_size;

    m_mcu_lines_left = 0;

    create_look_ups();
  }

  // The coeff_buf series of methods originally stored the coefficients
  // into a "virtual" file which was located in EMS, XMS, or a disk file. A cache
  // was used to make this process more efficient. Now, we can store the entire
  // thing in RAM.
  coeff_buf* coeff_buf_open(int block_num_x, int block_num_y, int block_len_x, int block_len_y) {
    coeff_buf* cb = cast(coeff_buf*)alloc(coeff_buf.sizeof);

    cb.block_num_x = block_num_x;
    cb.block_num_y = block_num_y;
    cb.block_len_x = block_len_x;
    cb.block_len_y = block_len_y;
    cb.block_size = cast(int)((block_len_x * block_len_y) * jpgd_block_t.sizeof);
    cb.pData = cast(ubyte*)alloc(cb.block_size * block_num_x * block_num_y, true);
    return cb;
  }

  jpgd_block_t* coeff_buf_getp (coeff_buf *cb, int block_x, int block_y) {
    assert((block_x < cb.block_num_x) && (block_y < cb.block_num_y));
    return cast(jpgd_block_t*)(cb.pData + block_x * cb.block_size + block_y * (cb.block_size * cb.block_num_x));
  }

  // The following methods decode the various types of m_blocks encountered
  // in progressively encoded images.
  static void decode_block_dc_first (ref jpeg_decoder pD, int component_id, int block_x, int block_y) {
    int s, r;
    jpgd_block_t *p = pD.coeff_buf_getp(pD.m_dc_coeffs.ptr[component_id], block_x, block_y);

    if ((s = pD.huff_decode(pD.m_pHuff_tabs.ptr[pD.m_comp_dc_tab.ptr[component_id]])) != 0)
    {
      r = pD.get_bits_no_markers(s);
      s = JPGD_HUFF_EXTEND(r, s);
    }

    pD.m_last_dc_val.ptr[component_id] = (s += pD.m_last_dc_val.ptr[component_id]);

    p[0] = cast(jpgd_block_t)(s << pD.m_successive_low);
  }

  static void decode_block_dc_refine (ref jpeg_decoder pD, int component_id, int block_x, int block_y) {
    if (pD.get_bits_no_markers(1))
    {
      jpgd_block_t *p = pD.coeff_buf_getp(pD.m_dc_coeffs.ptr[component_id], block_x, block_y);

      p[0] |= (1 << pD.m_successive_low);
    }
  }

  static void decode_block_ac_first (ref jpeg_decoder pD, int component_id, int block_x, int block_y) {
    int k, s, r;

    if (pD.m_eob_run)
    {
      pD.m_eob_run--;
      return;
    }

    jpgd_block_t *p = pD.coeff_buf_getp(pD.m_ac_coeffs.ptr[component_id], block_x, block_y);

    for (k = pD.m_spectral_start; k <= pD.m_spectral_end; k++)
    {
      s = pD.huff_decode(pD.m_pHuff_tabs.ptr[pD.m_comp_ac_tab.ptr[component_id]]);

      r = s >> 4;
      s &= 15;

      if (s)
      {
        if ((k += r) > 63)
          pD.stop_decoding(JPGD_DECODE_ERROR);

        r = pD.get_bits_no_markers(s);
        s = JPGD_HUFF_EXTEND(r, s);

        p[g_ZAG[k]] = cast(jpgd_block_t)(s << pD.m_successive_low);
      }
      else
      {
        if (r == 15)
        {
          if ((k += 15) > 63)
            pD.stop_decoding(JPGD_DECODE_ERROR);
        }
        else
        {
          pD.m_eob_run = 1 << r;

          if (r)
            pD.m_eob_run += pD.get_bits_no_markers(r);

          pD.m_eob_run--;

          break;
        }
      }
    }
  }

  static void decode_block_ac_refine (ref jpeg_decoder pD, int component_id, int block_x, int block_y) {
    int s, k, r;
    int p1 = 1 << pD.m_successive_low;
    int m1 = (-1) << pD.m_successive_low;
    jpgd_block_t *p = pD.coeff_buf_getp(pD.m_ac_coeffs.ptr[component_id], block_x, block_y);

    assert(pD.m_spectral_end <= 63);

    k = pD.m_spectral_start;

    if (pD.m_eob_run == 0)
    {
      for ( ; k <= pD.m_spectral_end; k++)
      {
        s = pD.huff_decode(pD.m_pHuff_tabs.ptr[pD.m_comp_ac_tab.ptr[component_id]]);

        r = s >> 4;
        s &= 15;

        if (s)
        {
          if (s != 1)
            pD.stop_decoding(JPGD_DECODE_ERROR);

          if (pD.get_bits_no_markers(1))
            s = p1;
          else
            s = m1;
        }
        else
        {
          if (r != 15)
          {
            pD.m_eob_run = 1 << r;

            if (r)
              pD.m_eob_run += pD.get_bits_no_markers(r);

            break;
          }
        }

        do
        {
          jpgd_block_t *this_coef = p + g_ZAG[k & 63];

          if (*this_coef != 0)
          {
            if (pD.get_bits_no_markers(1))
            {
              if ((*this_coef & p1) == 0)
              {
                if (*this_coef >= 0)
                  *this_coef = cast(jpgd_block_t)(*this_coef + p1);
                else
                  *this_coef = cast(jpgd_block_t)(*this_coef + m1);
              }
            }
          }
          else
          {
            if (--r < 0)
              break;
          }

          k++;

        } while (k <= pD.m_spectral_end);

        if ((s) && (k < 64))
        {
          p[g_ZAG[k]] = cast(jpgd_block_t)(s);
        }
      }
    }

    if (pD.m_eob_run > 0)
    {
      for ( ; k <= pD.m_spectral_end; k++)
      {
        jpgd_block_t *this_coef = p + g_ZAG[k & 63]; // logical AND to shut up static code analysis

        if (*this_coef != 0)
        {
          if (pD.get_bits_no_markers(1))
          {
            if ((*this_coef & p1) == 0)
            {
              if (*this_coef >= 0)
                *this_coef = cast(jpgd_block_t)(*this_coef + p1);
              else
                *this_coef = cast(jpgd_block_t)(*this_coef + m1);
            }
          }
        }
      }

      pD.m_eob_run--;
    }
  }

  // Decode a scan in a progressively encoded image.
  void decode_scan (pDecode_block_func decode_block_func) {
    int mcu_row, mcu_col, mcu_block;
    int[JPGD_MAX_COMPONENTS] block_x_mcu;
    int[JPGD_MAX_COMPONENTS] m_block_y_mcu;

    memset(m_block_y_mcu.ptr, 0, m_block_y_mcu.sizeof);

    for (mcu_col = 0; mcu_col < m_mcus_per_col; mcu_col++)
    {
      int component_num, component_id;

      memset(block_x_mcu.ptr, 0, block_x_mcu.sizeof);

      for (mcu_row = 0; mcu_row < m_mcus_per_row; mcu_row++)
      {
        int block_x_mcu_ofs = 0, block_y_mcu_ofs = 0;

        if ((m_restart_interval) && (m_restarts_left == 0))
          process_restart();

        for (mcu_block = 0; mcu_block < m_blocks_per_mcu; mcu_block++)
        {
          component_id = m_mcu_org.ptr[mcu_block];

          decode_block_func(this, component_id, block_x_mcu.ptr[component_id] + block_x_mcu_ofs, m_block_y_mcu.ptr[component_id] + block_y_mcu_ofs);

          if (m_comps_in_scan == 1)
            block_x_mcu.ptr[component_id]++;
          else
          {
            if (++block_x_mcu_ofs == m_comp_h_samp.ptr[component_id])
            {
              block_x_mcu_ofs = 0;

              if (++block_y_mcu_ofs == m_comp_v_samp.ptr[component_id])
              {
                block_y_mcu_ofs = 0;
                block_x_mcu.ptr[component_id] += m_comp_h_samp.ptr[component_id];
              }
            }
          }
        }

        m_restarts_left--;
      }

      if (m_comps_in_scan == 1)
        m_block_y_mcu.ptr[m_comp_list.ptr[0]]++;
      else
      {
        for (component_num = 0; component_num < m_comps_in_scan; component_num++)
        {
          component_id = m_comp_list.ptr[component_num];
          m_block_y_mcu.ptr[component_id] += m_comp_v_samp.ptr[component_id];
        }
      }
    }
  }

  // Decode a progressively encoded image.
  void init_progressive () {
    int i;

    if (m_comps_in_frame == 4)
      stop_decoding(JPGD_UNSUPPORTED_COLORSPACE);

    // Allocate the coefficient buffers.
    for (i = 0; i < m_comps_in_frame; i++)
    {
      m_dc_coeffs.ptr[i] = coeff_buf_open(m_max_mcus_per_row * m_comp_h_samp.ptr[i], m_max_mcus_per_col * m_comp_v_samp.ptr[i], 1, 1);
      m_ac_coeffs.ptr[i] = coeff_buf_open(m_max_mcus_per_row * m_comp_h_samp.ptr[i], m_max_mcus_per_col * m_comp_v_samp.ptr[i], 8, 8);
    }

    for ( ; ; )
    {
      int dc_only_scan, refinement_scan;
      pDecode_block_func decode_block_func;

      if (!init_scan())
        break;

      dc_only_scan = (m_spectral_start == 0);
      refinement_scan = (m_successive_high != 0);

      if ((m_spectral_start > m_spectral_end) || (m_spectral_end > 63))
        stop_decoding(JPGD_BAD_SOS_SPECTRAL);

      if (dc_only_scan)
      {
        if (m_spectral_end)
          stop_decoding(JPGD_BAD_SOS_SPECTRAL);
      }
      else if (m_comps_in_scan != 1)  /* AC scans can only contain one component */
        stop_decoding(JPGD_BAD_SOS_SPECTRAL);

      if ((refinement_scan) && (m_successive_low != m_successive_high - 1))
        stop_decoding(JPGD_BAD_SOS_SUCCESSIVE);

      if (dc_only_scan)
      {
        if (refinement_scan)
          decode_block_func = &decode_block_dc_refine;
        else
          decode_block_func = &decode_block_dc_first;
      }
      else
      {
        if (refinement_scan)
          decode_block_func = &decode_block_ac_refine;
        else
          decode_block_func = &decode_block_ac_first;
      }

      decode_scan(decode_block_func);

      m_bits_left = 16;
      get_bits(16);
      get_bits(16);
    }

    m_comps_in_scan = m_comps_in_frame;

    for (i = 0; i < m_comps_in_frame; i++)
      m_comp_list.ptr[i] = i;

    calc_mcu_block_order();
  }

  void init_sequential () {
    if (!init_scan())
      stop_decoding(JPGD_UNEXPECTED_MARKER);
  }

  void decode_start () {
    init_frame();

    if (m_progressive_flag)
      init_progressive();
    else
      init_sequential();
  }

  void decode_init (JpegStreamReadFunc rfn) {
    initit(rfn);
    locate_sof_marker();
  }
}


// ////////////////////////////////////////////////////////////////////////// //
/// read JPEG image header, determine dimensions and number of components.
/// return `false` if image is not JPEG (i hope).
public bool detect_jpeg_image_from_stream (scope JpegStreamReadFunc rfn, out int width, out int height, out int actual_comps) {
  if (rfn is null) return false;
  auto decoder = jpeg_decoder(rfn);
  version(jpegd_test) { import core.stdc.stdio : printf; printf("%u bytes read.\n", cast(uint)decoder.total_bytes_read); }
  if (decoder.error_code != JPGD_SUCCESS) return false;
  width = decoder.width;
  height = decoder.height;
  actual_comps = decoder.num_components;
  return true;
}


// ////////////////////////////////////////////////////////////////////////// //
/// read JPEG image header, determine dimensions and number of components.
/// return `false` if image is not JPEG (i hope).
public bool detect_jpeg_image_from_file (const(char)[] filename, out int width, out int height, out int actual_comps) {
  import core.stdc.stdio;

  FILE* m_pFile;
  bool m_eof_flag, m_error_flag;

  if (filename.length == 0) throw new Exception("cannot open unnamed file");
  if (filename.length < 512) {
    char[513] buffer;
    //import core.stdc.stdlib : alloca;
    auto tfn = buffer[0 .. filename.length + 1]; // (cast(char*)alloca(filename.length+1))[0..filename.length+1];
    tfn[0..filename.length] = filename[];
    tfn[filename.length] = 0;
    m_pFile = fopen(tfn.ptr, "rb");
  } else {
    import core.stdc.stdlib : malloc, free;
    auto tfn = (cast(char*)malloc(filename.length+1))[0..filename.length+1];
    if (tfn !is null) {
      scope(exit) free(tfn.ptr);
      m_pFile = fopen(tfn.ptr, "rb");
    }
  }
  if (m_pFile is null) throw new Exception("cannot open file '"~filename.idup~"'");
  scope(exit) if (m_pFile) fclose(m_pFile);

  return detect_jpeg_image_from_stream(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      if (m_pFile is null) return -1;
      if (m_eof_flag) {
        *pEOF_flag = true;
        return 0;
      }
      if (m_error_flag) return -1;
      int bytes_read = cast(int)(fread(pBuf, 1, max_bytes_to_read, m_pFile));
      if (bytes_read < max_bytes_to_read) {
        if (ferror(m_pFile)) {
          m_error_flag = true;
          return -1;
        }
        m_eof_flag = true;
        *pEOF_flag = true;
      }
      return bytes_read;
    },
    width, height, actual_comps);
}


// ////////////////////////////////////////////////////////////////////////// //
/// read JPEG image header, determine dimensions and number of components.
/// return `false` if image is not JPEG (i hope).
public bool detect_jpeg_image_from_memory (const(void)[] buf, out int width, out int height, out int actual_comps) {
  size_t bufpos;
  return detect_jpeg_image_from_stream(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      import core.stdc.string : memcpy;
      if (bufpos >= buf.length) {
        *pEOF_flag = true;
        return 0;
      }
      if (buf.length-bufpos < max_bytes_to_read) max_bytes_to_read = cast(int)(buf.length-bufpos);
      memcpy(pBuf, (cast(const(ubyte)*)buf.ptr)+bufpos, max_bytes_to_read);
      bufpos += max_bytes_to_read;
      return max_bytes_to_read;
    },
    width, height, actual_comps);
}


// ////////////////////////////////////////////////////////////////////////// //
/// decompress JPEG image, what else?
/// you can specify required color components in `req_comps` (3 for RGB or 4 for RGBA), or leave it as is to use image value.
public ubyte[] decompress_jpeg_image_from_stream(bool useMalloc=false) (scope JpegStreamReadFunc rfn, out int width, out int height, out int actual_comps, int req_comps=-1) {
  import core.stdc.string : memcpy;

  //actual_comps = 0;
  if (rfn is null) return null;
  if (req_comps != -1 && req_comps != 1 && req_comps != 3 && req_comps != 4) return null;

  auto decoder = jpeg_decoder(rfn);
  if (decoder.error_code != JPGD_SUCCESS) return null;
  version(jpegd_test) scope(exit) { import core.stdc.stdio : printf; printf("%u bytes read.\n", cast(uint)decoder.total_bytes_read); }

  immutable int image_width = decoder.width;
  immutable int image_height = decoder.height;
  width = image_width;
  height = image_height;
  actual_comps = decoder.num_components;
  if (req_comps < 0) req_comps = decoder.num_components;

  if (decoder.begin_decoding() != JPGD_SUCCESS) return null;

  immutable int dst_bpl = image_width*req_comps;

  static if (useMalloc) {
    ubyte* pImage_data = cast(ubyte*)jpgd_malloc(dst_bpl*image_height);
    if (pImage_data is null) return null;
    auto idata = pImage_data[0..dst_bpl*image_height];
  } else {
    auto idata = new ubyte[](dst_bpl*image_height);
    auto pImage_data = idata.ptr;
  }

  scope(failure) {
    static if (useMalloc) {
      jpgd_free(pImage_data);
    } else {
      import core.memory : GC;
      GC.free(idata.ptr);
      idata = null;
    }
  }

  for (int y = 0; y < image_height; ++y) {
    const(ubyte)* pScan_line;
    uint scan_line_len;
    if (decoder.decode(/*(const void**)*/cast(void**)&pScan_line, &scan_line_len) != JPGD_SUCCESS) {
      static if (useMalloc) {
        jpgd_free(pImage_data);
      } else {
        import core.memory : GC;
        GC.free(idata.ptr);
        idata = null;
      }
      return null;
    }

    ubyte* pDst = pImage_data+y*dst_bpl;

    if ((req_comps == 1 && decoder.num_components == 1) || (req_comps == 4 && decoder.num_components == 3)) {
      memcpy(pDst, pScan_line, dst_bpl);
    } else if (decoder.num_components == 1) {
      if (req_comps == 3) {
        for (int x = 0; x < image_width; ++x) {
          ubyte luma = pScan_line[x];
          pDst[0] = luma;
          pDst[1] = luma;
          pDst[2] = luma;
          pDst += 3;
        }
      } else {
        for (int x = 0; x < image_width; ++x) {
          ubyte luma = pScan_line[x];
          pDst[0] = luma;
          pDst[1] = luma;
          pDst[2] = luma;
          pDst[3] = 255;
          pDst += 4;
        }
      }
    } else if (decoder.num_components == 3) {
      if (req_comps == 1) {
        immutable int YR = 19595, YG = 38470, YB = 7471;
        for (int x = 0; x < image_width; ++x) {
          int r = pScan_line[x*4+0];
          int g = pScan_line[x*4+1];
          int b = pScan_line[x*4+2];
          *pDst++ = cast(ubyte)((r * YR + g * YG + b * YB + 32768) >> 16);
        }
      } else {
        for (int x = 0; x < image_width; ++x) {
          pDst[0] = pScan_line[x*4+0];
          pDst[1] = pScan_line[x*4+1];
          pDst[2] = pScan_line[x*4+2];
          pDst += 3;
        }
      }
    }
  }

  return idata;
}


// ////////////////////////////////////////////////////////////////////////// //
/// decompress JPEG image from disk file.
/// you can specify required color components in `req_comps` (3 for RGB or 4 for RGBA), or leave it as is to use image value.
public ubyte[] decompress_jpeg_image_from_file(bool useMalloc=false) (const(char)[] filename, out int width, out int height, out int actual_comps, int req_comps=-1) {
  import core.stdc.stdio;

  FILE* m_pFile;
  bool m_eof_flag, m_error_flag;

  if (filename.length == 0) throw new Exception("cannot open unnamed file");
  if (filename.length < 512) {
	char[513] buffer;
    //import core.stdc.stdlib : alloca;
    auto tfn = buffer[0 .. filename.length + 1]; // (cast(char*)alloca(filename.length+1))[0..filename.length+1];
    tfn[0..filename.length] = filename[];
    tfn[filename.length] = 0;
    m_pFile = fopen(tfn.ptr, "rb");
  } else {
    import core.stdc.stdlib : malloc, free;
    auto tfn = (cast(char*)malloc(filename.length+1))[0..filename.length+1];
    if (tfn !is null) {
      scope(exit) free(tfn.ptr);
      m_pFile = fopen(tfn.ptr, "rb");
    }
  }
  if (m_pFile is null) throw new Exception("cannot open file '"~filename.idup~"'");
  scope(exit) if (m_pFile) fclose(m_pFile);

  return decompress_jpeg_image_from_stream!useMalloc(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      if (m_pFile is null) return -1;
      if (m_eof_flag) {
        *pEOF_flag = true;
        return 0;
      }
      if (m_error_flag) return -1;
      int bytes_read = cast(int)(fread(pBuf, 1, max_bytes_to_read, m_pFile));
      if (bytes_read < max_bytes_to_read) {
        if (ferror(m_pFile)) {
          m_error_flag = true;
          return -1;
        }
        m_eof_flag = true;
        *pEOF_flag = true;
      }
      return bytes_read;
    },
    width, height, actual_comps, req_comps);
}


// ////////////////////////////////////////////////////////////////////////// //
/// decompress JPEG image from memory buffer.
/// you can specify required color components in `req_comps` (3 for RGB or 4 for RGBA), or leave it as is to use image value.
public ubyte[] decompress_jpeg_image_from_memory(bool useMalloc=false) (const(void)[] buf, out int width, out int height, out int actual_comps, int req_comps=-1) {
  size_t bufpos;
  return decompress_jpeg_image_from_stream!useMalloc(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      import core.stdc.string : memcpy;
      if (bufpos >= buf.length) {
        *pEOF_flag = true;
        return 0;
      }
      if (buf.length-bufpos < max_bytes_to_read) max_bytes_to_read = cast(int)(buf.length-bufpos);
      memcpy(pBuf, (cast(const(ubyte)*)buf.ptr)+bufpos, max_bytes_to_read);
      bufpos += max_bytes_to_read;
      return max_bytes_to_read;
    },
    width, height, actual_comps, req_comps);
}


// ////////////////////////////////////////////////////////////////////////// //
// if we have access "iv.vfs", add some handy API
static if (__traits(compiles, { import iv.vfs; })) enum JpegHasIVVFS = true; else enum JpegHasIVVFS = false;

static if (JpegHasIVVFS) {
import iv.vfs;

// ////////////////////////////////////////////////////////////////////////// //
/// decompress JPEG image from disk file.
/// you can specify required color components in `req_comps` (3 for RGB or 4 for RGBA), or leave it as is to use image value.
public ubyte[] decompress_jpeg_image_from_file(bool useMalloc=false) (VFile fl, out int width, out int height, out int actual_comps, int req_comps=-1) {
  return decompress_jpeg_image_from_stream!useMalloc(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      if (!fl.isOpen) return -1;
      if (fl.eof) {
        *pEOF_flag = true;
        return 0;
      }
      auto rd = fl.rawRead(pBuf[0..max_bytes_to_read]);
      if (fl.eof) *pEOF_flag = true;
      return cast(int)rd.length;
    },
    width, height, actual_comps, req_comps);
}
// vfs API
}


// ////////////////////////////////////////////////////////////////////////// //
// if we have access "arsd.color", add some handy API
static if (__traits(compiles, { import arsd.color; })) enum JpegHasArsd = true; else enum JpegHasArsd = false;



public struct LastJpegError {
	int stage;
	int code;
	int details;
}

public LastJpegError lastJpegError;


static if (JpegHasArsd) {
import arsd.color;
static import arsd.core;

// ////////////////////////////////////////////////////////////////////////// //
/// decompress JPEG image, what else?
public MemoryImage readJpegFromStream (scope JpegStreamReadFunc rfn) {
  import core.stdc.string : memcpy;
  enum req_comps = 4;

  if (rfn is null) return null;

  auto decoder = jpeg_decoder(rfn);
  if (decoder.error_code != JPGD_SUCCESS) { lastJpegError = LastJpegError(1, decoder.error_code); return null; }
  version(jpegd_test) scope(exit) { import core.stdc.stdio : printf; printf("%u bytes read.\n", cast(uint)decoder.total_bytes_read); }

  immutable int image_width = decoder.width;
  immutable int image_height = decoder.height;
  //width = image_width;
  //height = image_height;
  //actual_comps = decoder.num_components;

  version(jpegd_test) {{ import core.stdc.stdio; stderr.fprintf("starting (%dx%d)...\n", image_width, image_height); }}

  auto err = decoder.begin_decoding();
  if (err != JPGD_SUCCESS || image_width < 1 || image_height < 1) {
		lastJpegError = LastJpegError(2, err, decoder.m_error_code);
		return null;
  }

  immutable int dst_bpl = image_width*req_comps;
  auto img = new TrueColorImage(image_width, image_height);
  scope(failure) { img.clearInternal(); img = null; }
  ubyte* pImage_data = img.imageData.bytes.ptr;

  for (int y = 0; y < image_height; ++y) {
    //version(jpegd_test) {{ import core.stdc.stdio; stderr.fprintf("loading line %d...\n", y); }}

    const(ubyte)* pScan_line;
    uint scan_line_len;
    err = decoder.decode(/*(const void**)*/cast(void**)&pScan_line, &scan_line_len);
    if (err != JPGD_SUCCESS) {
      lastJpegError = LastJpegError(3, err);
      img.clearInternal();
      img = null;
      //jpgd_free(pImage_data);
      return null;
    }

    ubyte* pDst = pImage_data+y*dst_bpl;

    if ((req_comps == 1 && decoder.num_components == 1) || (req_comps == 4 && decoder.num_components == 3)) {
      memcpy(pDst, pScan_line, dst_bpl);
    } else if (decoder.num_components == 1) {
      if (req_comps == 3) {
        for (int x = 0; x < image_width; ++x) {
          ubyte luma = pScan_line[x];
          pDst[0] = luma;
          pDst[1] = luma;
          pDst[2] = luma;
          pDst += 3;
        }
      } else {
        for (int x = 0; x < image_width; ++x) {
          ubyte luma = pScan_line[x];
          pDst[0] = luma;
          pDst[1] = luma;
          pDst[2] = luma;
          pDst[3] = 255;
          pDst += 4;
        }
      }
    } else if (decoder.num_components == 3) {
      if (req_comps == 1) {
        immutable int YR = 19595, YG = 38470, YB = 7471;
        for (int x = 0; x < image_width; ++x) {
          int r = pScan_line[x*4+0];
          int g = pScan_line[x*4+1];
          int b = pScan_line[x*4+2];
          *pDst++ = cast(ubyte)((r * YR + g * YG + b * YB + 32768) >> 16);
        }
      } else {
        for (int x = 0; x < image_width; ++x) {
          pDst[0] = pScan_line[x*4+0];
          pDst[1] = pScan_line[x*4+1];
          pDst[2] = pScan_line[x*4+2];
          pDst += 3;
        }
      }
    }
  }

  static void rotate180(TrueColorImage img) {
	size_t cursor = img.imageData.colors.length - 1;

	foreach(i, px; img.imageData.colors) {
		img.imageData.colors[i] = img.imageData.colors[cursor];
		img.imageData.colors[cursor] = px;

		cursor -= 1;
		if(i == cursor)
			break;
	}
  }

  static void mirrorHorizontally(TrueColorImage img) {
  	if(img.width < 2)
		return;
  	foreach(row; 0 .. img.height) {
		auto off1 = row * img.width;
		auto off2 = off1 + img.width - 1;

		while(off1 < off2) {
			auto px = img.imageData.colors[off1];
			img.imageData.colors[off1] = img.imageData.colors[off2];
			img.imageData.colors[off2] = px;

			off1++;
			off2--;
		}
	}
  }

  static void mirrorVertically(TrueColorImage img) {
  	if(img.height < 2)
		return;
  	foreach(column; 0 .. img.width) {
		auto off1 = column;
		auto off2 = img.imageData.colors.length - img.width + off1;

		while(off1 < off2) {
			auto px = img.imageData.colors[off1];
			img.imageData.colors[off1] = img.imageData.colors[off2];
			img.imageData.colors[off2] = px;

			off1 += img.width;
			off2 -= img.width;
		}
	}
  }


  static TrueColorImage rotate90(const TrueColorImage img) {
	auto rotatedImage = new TrueColorImage(img.height, img.width); // swapped due to rotation
	const area = img.imageData.colors.length;
	const rowLength = img.height;
	ptrdiff_t cursor = -1;

	foreach(px; img.imageData.colors) {
		cursor += rowLength;
		if(cursor > area) {
			cursor -= (area + 1);
		}

		rotatedImage.imageData.colors[cursor] = px;
	}

	return rotatedImage;
  }

  if(decoder.autoRotateBasedOnExifOrientation && img.imageData.colors.length)
  switch(decoder.orientation) {
  	case 0:
  	case 1:
		// no work required
	break;
	case 2:
		// mirror horizontal
		mirrorHorizontally(img);
	break;
	case 3:
		// rotate 180
		rotate180(img);
	break;
	case 4:
		// mirror vertical
		mirrorVertically(img);
	break;
	case 5:
		// mirror horizontal and rotate 270 CW
		mirrorHorizontally(img);
		rotate180(img);
		img = rotate90(img);
	break;
	case 6:
		// rotate 90 CW
		img = rotate90(img);
	break;
	case 7:
		// mirror horizontal and rotate 90 CW
		mirrorHorizontally(img);
		img = rotate90(img);
	break;
	case 8:
		// rotate 270 CW aka 90 CCW
		rotate180(img);
		img = rotate90(img);
	break;

	default:
		// unknown, just leave it alone
  }

  return img;
}


// ////////////////////////////////////////////////////////////////////////// //
/// decompress JPEG image from disk file.
/// Returns null if loading failed for any reason.
public MemoryImage readJpeg (const(char)[] filename) {
  import core.stdc.stdio;

  FILE* m_pFile;
  bool m_eof_flag, m_error_flag;

  if (filename.length == 0) throw new Exception("cannot open unnamed file");
  if (filename.length < 512) {
	char[513] buffer;
    //import core.stdc.stdlib : alloca;
    auto tfn = buffer[0 .. filename.length + 1]; // (cast(char*)alloca(filename.length+1))[0..filename.length+1];
    tfn[0..filename.length] = filename[];
    tfn[filename.length] = 0;
    m_pFile = fopen(tfn.ptr, "rb");
  } else {
    import core.stdc.stdlib : malloc, free;
    auto tfn = (cast(char*)malloc(filename.length+1))[0..filename.length+1];
    if (tfn !is null) {
      scope(exit) free(tfn.ptr);
      m_pFile = fopen(tfn.ptr, "rb");
    }
  }
  if (m_pFile is null) throw new Exception("cannot open file '"~filename.idup~"'");
  scope(exit) if (m_pFile) fclose(m_pFile);

  return readJpegFromStream(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      if (m_pFile is null) return -1;
      if (m_eof_flag) {
        *pEOF_flag = true;
        return 0;
      }
      if (m_error_flag) return -1;
      int bytes_read = cast(int)(fread(pBuf, 1, max_bytes_to_read, m_pFile));
      if (bytes_read < max_bytes_to_read) {
        if (ferror(m_pFile)) {
          m_error_flag = true;
          return -1;
        }
        m_eof_flag = true;
        *pEOF_flag = true;
      }
      return bytes_read;
    }
  );
}

/++
	History:
		Added January 22, 2021 (release version 9.2)
+/
public void writeJpeg(const(char)[] filename, TrueColorImage img, JpegParams params = JpegParams.init) {
	if(!compress_image_to_jpeg_file(filename, img.width, img.height, 4, img.imageData.bytes, params))
		throw new Exception("jpeg write failed"); // FIXME: check errno?
}

/++
  	Encodes an image as jpeg in memory.

	History:
		Added January 22, 2021 (release version 9.2)
+/
public ubyte[] encodeJpeg(TrueColorImage img, JpegParams params = JpegParams.init) {
  	ubyte[] data;
	encodeJpeg((const scope ubyte[] i) {
		data ~= i;
		return true;
	}, img, params);

	return data;
}

/// ditto
public void encodeJpeg(scope bool delegate(const scope ubyte[]) dg, TrueColorImage img, JpegParams params = JpegParams.init) {
	if(!compress_image_to_jpeg_stream(
		dg,
		img.width, img.height, 4, img.imageData.bytes, params))
		throw new Exception("encode");
}


// ////////////////////////////////////////////////////////////////////////// //
/// decompress JPEG image from memory buffer.
public MemoryImage readJpegFromMemory (const(void)[] buf) {
  size_t bufpos;
  return readJpegFromStream(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      import core.stdc.string : memcpy;
      if (bufpos >= buf.length) {
        *pEOF_flag = true;
        return 0;
      }
      if (buf.length-bufpos < max_bytes_to_read) max_bytes_to_read = cast(int)(buf.length-bufpos);
      memcpy(pBuf, (cast(const(ubyte)*)buf.ptr)+bufpos, max_bytes_to_read);
      bufpos += max_bytes_to_read;
      return max_bytes_to_read;
    }
  );
}
// done with arsd API
}


static if (JpegHasIVVFS) {
public MemoryImage readJpeg (VFile fl) {
  return readJpegFromStream(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      if (!fl.isOpen) return -1;
      if (fl.eof) {
        *pEOF_flag = true;
        return 0;
      }
      auto rd = fl.rawRead(pBuf[0..max_bytes_to_read]);
      if (fl.eof) *pEOF_flag = true;
      return cast(int)rd.length;
    }
  );
}

public bool detectJpeg (VFile fl, out int width, out int height, out int actual_comps) {
  return detect_jpeg_image_from_stream(
    delegate int (void* pBuf, int max_bytes_to_read, bool *pEOF_flag) {
      if (!fl.isOpen) return -1;
      if (fl.eof) {
        *pEOF_flag = true;
        return 0;
      }
      auto rd = fl.rawRead(pBuf[0..max_bytes_to_read]);
      if (fl.eof) *pEOF_flag = true;
      return cast(int)rd.length;
    },
    width, height, actual_comps);
}
// vfs API
}


// ////////////////////////////////////////////////////////////////////////// //
version(jpegd_test) {
import arsd.color;
import arsd.png;

void main (string[] args) {
  import std.stdio;
  int width, height, comps;
  {
    assert(detect_jpeg_image_from_file((args.length > 1 ? args[1] : "image.jpg"), width, height, comps));
    writeln(width, "x", height, "x", comps);
    auto img = readJpeg((args.length > 1 ? args[1] : "image.jpg"));
    writeln(img.width, "x", img.height);
    writePng("z00.png", img);
  }
  {
    ubyte[] file;
    {
      auto fl = File(args.length > 1 ? args[1] : "image.jpg");
      file.length = cast(int)fl.size;
      fl.rawRead(file[]);
    }
    assert(detect_jpeg_image_from_memory(file[], width, height, comps));
    writeln(width, "x", height, "x", comps);
    auto img = readJpegFromMemory(file[]);
    writeln(img.width, "x", img.height);
    writePng("z01.png", img);
  }
}
}

// jpge.cpp - C++ class for JPEG compression.
// Public domain, Rich Geldreich <richgel99@gmail.com>
// Alex Evans: Added RGBA support, linear memory allocator.
// v1.01, Dec. 18, 2010 - Initial release
// v1.02, Apr. 6, 2011 - Removed 2x2 ordered dither in H2V1 chroma subsampling method load_block_16_8_8(). (The rounding factor was 2, when it should have been 1. Either way, it wasn't helping.)
// v1.03, Apr. 16, 2011 - Added support for optimized Huffman code tables, optimized dynamic memory allocation down to only 1 alloc.
//                        Also from Alex Evans: Added RGBA support, linear memory allocator (no longer needed in v1.03).
// v1.04, May. 19, 2012: Forgot to set m_pFile ptr to null in cfile_stream::close(). Thanks to Owen Kaluza for reporting this bug.
//                       Code tweaks to fix VS2008 static code analysis warnings (all looked harmless).
//                       Code review revealed method load_block_16_8_8() (used for the non-default H2V1 sampling mode to downsample chroma) somehow didn't get the rounding factor fix from v1.02.
// D translation by Ketmar // Invisible Vector
//
// This is free and unencumbered software released into the public domain.
//
// Anyone is free to copy, modify, publish, use, compile, sell, or
// distribute this software, either in source code form or as a compiled
// binary, for any purpose, commercial or non-commercial, and by any
// means.
//
// In jurisdictions that recognize copyright laws, the author or authors
// of this software dedicate any and all copyright interest in the
// software to the public domain. We make this dedication for the benefit
// of the public at large and to the detriment of our heirs and
// successors. We intend this dedication to be an overt act of
// relinquishment in perpetuity of all present and future rights to this
// software under copyright law.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
// OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//
// For more information, please refer to <http://unlicense.org/>
/**
 * Writes a JPEG image to a file or stream.
 * num_channels must be 1 (Y), 3 (RGB), 4 (RGBA), image pitch must be width*num_channels.
 * note that alpha will not be stored in jpeg file.
 */

public:
// ////////////////////////////////////////////////////////////////////////// //
// JPEG chroma subsampling factors. Y_ONLY (grayscale images) and H2V2 (color images) are the most common.
enum JpegSubsampling { Y_ONLY = 0, H1V1 = 1, H2V1 = 2, H2V2 = 3 }

/// JPEG compression parameters structure.
public struct JpegParams {
  /// Quality: 1-100, higher is better. Typical values are around 50-95.
  int quality = 85;

  /// subsampling:
  /// 0 = Y (grayscale) only
  /// 1 = YCbCr, no subsampling (H1V1, YCbCr 1x1x1, 3 blocks per MCU)
  /// 2 = YCbCr, H2V1 subsampling (YCbCr 2x1x1, 4 blocks per MCU)
  /// 3 = YCbCr, H2V2 subsampling (YCbCr 4x1x1, 6 blocks per MCU-- very common)
  JpegSubsampling subsampling = JpegSubsampling.H2V2;

  /// Disables CbCr discrimination - only intended for testing.
  /// If true, the Y quantization table is also used for the CbCr channels.
  bool noChromaDiscrimFlag = false;

  ///
  bool twoPass = true;

  ///
  bool check () const pure nothrow @trusted @nogc {
    if (quality < 1 || quality > 100) return false;
    if (cast(uint)subsampling > cast(uint)JpegSubsampling.H2V2) return false;
    return true;
  }
}


// ////////////////////////////////////////////////////////////////////////// //
/// Writes JPEG image to file.
/// num_channels must be 1 (Y), 3 (RGB), 4 (RGBA), image pitch must be width*num_channels.
/// note that alpha will not be stored in jpeg file.
bool compress_image_to_jpeg_stream (scope jpeg_encoder.WriteFunc wfn, int width, int height, int num_channels, const(ubyte)[] pImage_data) { return compress_image_to_jpeg_stream(wfn, width, height, num_channels, pImage_data, JpegParams()); }

/// Writes JPEG image to file.
/// num_channels must be 1 (Y), 3 (RGB), 4 (RGBA), image pitch must be width*num_channels.
/// note that alpha will not be stored in jpeg file.
bool compress_image_to_jpeg_stream (scope jpeg_encoder.WriteFunc wfn, int width, int height, int num_channels, const(ubyte)[] pImage_data, in JpegParams comp_params) {
  jpeg_encoder dst_image;
  if (!dst_image.setup(wfn, width, height, num_channels, comp_params)) return false;
  for (uint pass_index = 0; pass_index < dst_image.total_passes(); pass_index++) {
    for (int i = 0; i < height; i++) {
      const(ubyte)* pBuf = pImage_data.ptr+i*width*num_channels;
      if (!dst_image.process_scanline(pBuf)) return false;
    }
    if (!dst_image.process_scanline(null)) return false;
  }
  dst_image.deinit();
  //return dst_stream.close();
  return true;
}


/// Writes JPEG image to file.
/// num_channels must be 1 (Y), 3 (RGB), 4 (RGBA), image pitch must be width*num_channels.
/// note that alpha will not be stored in jpeg file.
bool compress_image_to_jpeg_file (const(char)[] fname, int width, int height, int num_channels, const(ubyte)[] pImage_data) { return compress_image_to_jpeg_file(fname, width, height, num_channels, pImage_data, JpegParams()); }

/// Writes JPEG image to file.
/// num_channels must be 1 (Y), 3 (RGB), 4 (RGBA), image pitch must be width*num_channels.
/// note that alpha will not be stored in jpeg file.
bool compress_image_to_jpeg_file() (const(char)[] fname, int width, int height, int num_channels, const(ubyte)[] pImage_data, const scope auto ref JpegParams comp_params) {
  import std.internal.cstring;
  import core.stdc.stdio : FILE, fopen, fclose, fwrite;
  FILE* fl = fopen(fname.tempCString, "wb");
  if (fl is null) return false;
  scope(exit) if (fl !is null) fclose(fl);
  auto res = compress_image_to_jpeg_stream(
    delegate bool (scope const(ubyte)[] buf) {
      if (fwrite(buf.ptr, 1, buf.length, fl) != buf.length) return false;
      return true;
    }, width, height, num_channels, pImage_data, comp_params);
  if (res) {
    if (fclose(fl) != 0) res = false;
    fl = null;
  }
  return res;
}


// ////////////////////////////////////////////////////////////////////////// //
private:
nothrow @trusted @nogc {
auto JPGE_MIN(T) (T a, T b) pure nothrow @safe @nogc { pragma(inline, true); return (a < b ? a : b); }
auto JPGE_MAX(T) (T a, T b) pure nothrow @safe @nogc { pragma(inline, true); return (a > b ? a : b); }

void *jpge_malloc (size_t nSize) { import core.stdc.stdlib : malloc; return malloc(nSize); }
void jpge_free (void *p) { import core.stdc.stdlib : free; if (p !is null) free(p); }


// Various JPEG enums and tables.
enum { DC_LUM_CODES = 12, AC_LUM_CODES = 256, DC_CHROMA_CODES = 12, AC_CHROMA_CODES = 256, MAX_HUFF_SYMBOLS = 257, MAX_HUFF_CODESIZE = 32 }

static immutable ubyte[64] s_zag = [ 0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63 ];
static immutable short[64] s_std_lum_quant = [ 16,11,12,14,12,10,16,14,13,14,18,17,16,19,24,40,26,24,22,22,24,49,35,37,29,40,58,51,61,60,57,51,56,55,64,72,92,78,64,68,87,69,55,56,80,109,81,87,95,98,103,104,103,62,77,113,121,112,100,120,92,101,103,99 ];
static immutable short[64] s_std_croma_quant = [ 17,18,18,24,21,24,47,26,26,47,99,66,56,66,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99 ];
static immutable ubyte[17] s_dc_lum_bits = [ 0,0,1,5,1,1,1,1,1,1,0,0,0,0,0,0,0 ];
static immutable ubyte[DC_LUM_CODES] s_dc_lum_val = [ 0,1,2,3,4,5,6,7,8,9,10,11 ];
static immutable ubyte[17] s_ac_lum_bits = [ 0,0,2,1,3,3,2,4,3,5,5,4,4,0,0,1,0x7d ];
static immutable ubyte[AC_LUM_CODES] s_ac_lum_val = [
  0x01,0x02,0x03,0x00,0x04,0x11,0x05,0x12,0x21,0x31,0x41,0x06,0x13,0x51,0x61,0x07,0x22,0x71,0x14,0x32,0x81,0x91,0xa1,0x08,0x23,0x42,0xb1,0xc1,0x15,0x52,0xd1,0xf0,
  0x24,0x33,0x62,0x72,0x82,0x09,0x0a,0x16,0x17,0x18,0x19,0x1a,0x25,0x26,0x27,0x28,0x29,0x2a,0x34,0x35,0x36,0x37,0x38,0x39,0x3a,0x43,0x44,0x45,0x46,0x47,0x48,0x49,
  0x4a,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6a,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7a,0x83,0x84,0x85,0x86,0x87,0x88,0x89,
  0x8a,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9a,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7,0xa8,0xa9,0xaa,0xb2,0xb3,0xb4,0xb5,0xb6,0xb7,0xb8,0xb9,0xba,0xc2,0xc3,0xc4,0xc5,
  0xc6,0xc7,0xc8,0xc9,0xca,0xd2,0xd3,0xd4,0xd5,0xd6,0xd7,0xd8,0xd9,0xda,0xe1,0xe2,0xe3,0xe4,0xe5,0xe6,0xe7,0xe8,0xe9,0xea,0xf1,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,
  0xf9,0xfa
];
static immutable ubyte[17] s_dc_chroma_bits = [ 0,0,3,1,1,1,1,1,1,1,1,1,0,0,0,0,0 ];
static immutable ubyte[DC_CHROMA_CODES] s_dc_chroma_val = [ 0,1,2,3,4,5,6,7,8,9,10,11 ];
static immutable ubyte[17] s_ac_chroma_bits = [ 0,0,2,1,2,4,4,3,4,7,5,4,4,0,1,2,0x77 ];
static immutable ubyte[AC_CHROMA_CODES] s_ac_chroma_val = [
  0x00,0x01,0x02,0x03,0x11,0x04,0x05,0x21,0x31,0x06,0x12,0x41,0x51,0x07,0x61,0x71,0x13,0x22,0x32,0x81,0x08,0x14,0x42,0x91,0xa1,0xb1,0xc1,0x09,0x23,0x33,0x52,0xf0,
  0x15,0x62,0x72,0xd1,0x0a,0x16,0x24,0x34,0xe1,0x25,0xf1,0x17,0x18,0x19,0x1a,0x26,0x27,0x28,0x29,0x2a,0x35,0x36,0x37,0x38,0x39,0x3a,0x43,0x44,0x45,0x46,0x47,0x48,
  0x49,0x4a,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6a,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7a,0x82,0x83,0x84,0x85,0x86,0x87,
  0x88,0x89,0x8a,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9a,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7,0xa8,0xa9,0xaa,0xb2,0xb3,0xb4,0xb5,0xb6,0xb7,0xb8,0xb9,0xba,0xc2,0xc3,
  0xc4,0xc5,0xc6,0xc7,0xc8,0xc9,0xca,0xd2,0xd3,0xd4,0xd5,0xd6,0xd7,0xd8,0xd9,0xda,0xe2,0xe3,0xe4,0xe5,0xe6,0xe7,0xe8,0xe9,0xea,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,
  0xf9,0xfa
];

// Low-level helper functions.
//template <class T> inline void clear_obj(T &obj) { memset(&obj, 0, sizeof(obj)); }

enum YR = 19595, YG = 38470, YB = 7471, CB_R = -11059, CB_G = -21709, CB_B = 32768, CR_R = 32768, CR_G = -27439, CR_B = -5329; // int
//ubyte clamp (int i) { if (cast(uint)(i) > 255U) { if (i < 0) i = 0; else if (i > 255) i = 255; } return cast(ubyte)(i); }
ubyte clamp() (int i) { pragma(inline, true); return cast(ubyte)(cast(uint)i > 255 ? (((~i)>>31)&0xFF) : i); }

void RGB_to_YCC (ubyte* pDst, const(ubyte)* pSrc, int num_pixels) {
  for (; num_pixels; pDst += 3, pSrc += 3, --num_pixels) {
    immutable int r = pSrc[0], g = pSrc[1], b = pSrc[2];
    pDst[0] = cast(ubyte)((r*YR+g*YG+b*YB+32768)>>16);
    pDst[1] = clamp(128+((r*CB_R+g*CB_G+b*CB_B+32768)>>16));
    pDst[2] = clamp(128+((r*CR_R+g*CR_G+b*CR_B+32768)>>16));
  }
}

void RGB_to_Y (ubyte* pDst, const(ubyte)* pSrc, int num_pixels) {
  for (; num_pixels; ++pDst, pSrc += 3, --num_pixels) {
    pDst[0] = cast(ubyte)((pSrc[0]*YR+pSrc[1]*YG+pSrc[2]*YB+32768)>>16);
  }
}

void RGBA_to_YCC (ubyte* pDst, const(ubyte)* pSrc, int num_pixels) {
  for (; num_pixels; pDst += 3, pSrc += 4, --num_pixels) {
    immutable int r = pSrc[0], g = pSrc[1], b = pSrc[2];
    pDst[0] = cast(ubyte)((r*YR+g*YG+b*YB+32768)>>16);
    pDst[1] = clamp(128+((r*CB_R+g*CB_G+b*CB_B+32768)>>16));
    pDst[2] = clamp(128+((r*CR_R+g*CR_G+b*CR_B+32768)>>16));
  }
}

void RGBA_to_Y (ubyte* pDst, const(ubyte)* pSrc, int num_pixels) {
  for (; num_pixels; ++pDst, pSrc += 4, --num_pixels) {
    pDst[0] = cast(ubyte)((pSrc[0]*YR+pSrc[1]*YG+pSrc[2]*YB+32768)>>16);
  }
}

void Y_to_YCC (ubyte* pDst, const(ubyte)* pSrc, int num_pixels) {
  for (; num_pixels; pDst += 3, ++pSrc, --num_pixels) { pDst[0] = pSrc[0]; pDst[1] = 128; pDst[2] = 128; }
}

// Forward DCT - DCT derived from jfdctint.
enum { ROW_BITS = 2 }
//#define DCT_DESCALE(x, n) (((x)+(((int)1)<<((n)-1)))>>(n))
int DCT_DESCALE() (int x, int n) { pragma(inline, true); return (((x)+((cast(int)1)<<((n)-1)))>>(n)); }
//#define DCT_MUL(var, c) (cast(short)(var)*cast(int)(c))

//#define DCT1D(s0, s1, s2, s3, s4, s5, s6, s7)
enum DCT1D = q{{
  int t0 = s0+s7, t7 = s0-s7, t1 = s1+s6, t6 = s1-s6, t2 = s2+s5, t5 = s2-s5, t3 = s3+s4, t4 = s3-s4;
  int t10 = t0+t3, t13 = t0-t3, t11 = t1+t2, t12 = t1-t2;
  int u1 = (cast(short)(t12+t13)*cast(int)(4433));
  s2 = u1+(cast(short)(t13)*cast(int)(6270));
  s6 = u1+(cast(short)(t12)*cast(int)(-15137));
  u1 = t4+t7;
  int u2 = t5+t6, u3 = t4+t6, u4 = t5+t7;
  int z5 = (cast(short)(u3+u4)*cast(int)(9633));
  t4 = (cast(short)(t4)*cast(int)(2446)); t5 = (cast(short)(t5)*cast(int)(16819));
  t6 = (cast(short)(t6)*cast(int)(25172)); t7 = (cast(short)(t7)*cast(int)(12299));
  u1 = (cast(short)(u1)*cast(int)(-7373)); u2 = (cast(short)(u2)*cast(int)(-20995));
  u3 = (cast(short)(u3)*cast(int)(-16069)); u4 = (cast(short)(u4)*cast(int)(-3196));
  u3 += z5; u4 += z5;
  s0 = t10+t11; s1 = t7+u1+u4; s3 = t6+u2+u3; s4 = t10-t11; s5 = t5+u2+u4; s7 = t4+u1+u3;
}};

void DCT2D (int* p) {
  int c;
  int* q = p;
  for (c = 7; c >= 0; --c, q += 8) {
    int s0 = q[0], s1 = q[1], s2 = q[2], s3 = q[3], s4 = q[4], s5 = q[5], s6 = q[6], s7 = q[7];
    //DCT1D(s0, s1, s2, s3, s4, s5, s6, s7);
    mixin(DCT1D);
    q[0] = s0<<ROW_BITS; q[1] = DCT_DESCALE(s1, CONST_BITS-ROW_BITS); q[2] = DCT_DESCALE(s2, CONST_BITS-ROW_BITS); q[3] = DCT_DESCALE(s3, CONST_BITS-ROW_BITS);
    q[4] = s4<<ROW_BITS; q[5] = DCT_DESCALE(s5, CONST_BITS-ROW_BITS); q[6] = DCT_DESCALE(s6, CONST_BITS-ROW_BITS); q[7] = DCT_DESCALE(s7, CONST_BITS-ROW_BITS);
  }
  for (q = p, c = 7; c >= 0; --c, ++q) {
    int s0 = q[0*8], s1 = q[1*8], s2 = q[2*8], s3 = q[3*8], s4 = q[4*8], s5 = q[5*8], s6 = q[6*8], s7 = q[7*8];
    //DCT1D(s0, s1, s2, s3, s4, s5, s6, s7);
    mixin(DCT1D);
    q[0*8] = DCT_DESCALE(s0, ROW_BITS+3); q[1*8] = DCT_DESCALE(s1, CONST_BITS+ROW_BITS+3); q[2*8] = DCT_DESCALE(s2, CONST_BITS+ROW_BITS+3); q[3*8] = DCT_DESCALE(s3, CONST_BITS+ROW_BITS+3);
    q[4*8] = DCT_DESCALE(s4, ROW_BITS+3); q[5*8] = DCT_DESCALE(s5, CONST_BITS+ROW_BITS+3); q[6*8] = DCT_DESCALE(s6, CONST_BITS+ROW_BITS+3); q[7*8] = DCT_DESCALE(s7, CONST_BITS+ROW_BITS+3);
  }
}

struct sym_freq { uint m_key, m_sym_index; }

// Radix sorts sym_freq[] array by 32-bit key m_key. Returns ptr to sorted values.
sym_freq* radix_sort_syms (uint num_syms, sym_freq* pSyms0, sym_freq* pSyms1) {
  const uint cMaxPasses = 4;
  uint[256*cMaxPasses] hist;
  //clear_obj(hist);
  for (uint i = 0; i < num_syms; i++) {
    uint freq = pSyms0[i].m_key;
    ++hist[freq&0xFF];
    ++hist[256+((freq>>8)&0xFF)];
    ++hist[256*2+((freq>>16)&0xFF)];
    ++hist[256*3+((freq>>24)&0xFF)];
  }
  sym_freq* pCur_syms = pSyms0;
  sym_freq* pNew_syms = pSyms1;
  uint total_passes = cMaxPasses; while (total_passes > 1 && num_syms == hist[(total_passes-1)*256]) --total_passes;
  uint[256] offsets;
  for (uint pass_shift = 0, pass = 0; pass < total_passes; ++pass, pass_shift += 8) {
    const(uint)* pHist = &hist[pass<<8];
    uint cur_ofs = 0;
    for (uint i = 0; i < 256; i++) { offsets[i] = cur_ofs; cur_ofs += pHist[i]; }
    for (uint i = 0; i < num_syms; i++) pNew_syms[offsets[(pCur_syms[i].m_key>>pass_shift)&0xFF]++] = pCur_syms[i];
    sym_freq* t = pCur_syms; pCur_syms = pNew_syms; pNew_syms = t;
  }
  return pCur_syms;
}

// calculate_minimum_redundancy() originally written by: Alistair Moffat, alistair@cs.mu.oz.au, Jyrki Katajainen, jyrki@diku.dk, November 1996.
void calculate_minimum_redundancy (sym_freq* A, int n) {
  int root, leaf, next, avbl, used, dpth;
  if (n == 0) return;
  if (n == 1) { A[0].m_key = 1; return; }
  A[0].m_key += A[1].m_key; root = 0; leaf = 2;
  for (next=1; next < n-1; next++)
  {
    if (leaf>=n || A[root].m_key<A[leaf].m_key) { A[next].m_key = A[root].m_key; A[root++].m_key = next; } else A[next].m_key = A[leaf++].m_key;
    if (leaf>=n || (root<next && A[root].m_key<A[leaf].m_key)) { A[next].m_key += A[root].m_key; A[root++].m_key = next; } else A[next].m_key += A[leaf++].m_key;
  }
  A[n-2].m_key = 0;
  for (next=n-3; next>=0; next--) A[next].m_key = A[A[next].m_key].m_key+1;
  avbl = 1; used = dpth = 0; root = n-2; next = n-1;
  while (avbl>0)
  {
    while (root >= 0 && cast(int)A[root].m_key == dpth) { used++; root--; }
    while (avbl>used) { A[next--].m_key = dpth; avbl--; }
    avbl = 2*used; dpth++; used = 0;
  }
}

// Limits canonical Huffman code table's max code size to max_code_size.
void huffman_enforce_max_code_size (int* pNum_codes, int code_list_len, int max_code_size) {
  if (code_list_len <= 1) return;
  for (int i = max_code_size+1; i <= MAX_HUFF_CODESIZE; i++) pNum_codes[max_code_size] += pNum_codes[i];
  uint total = 0;
  for (int i = max_code_size; i > 0; i--) total += ((cast(uint)pNum_codes[i])<<(max_code_size-i));
  while (total != (1UL<<max_code_size)) {
    pNum_codes[max_code_size]--;
    for (int i = max_code_size-1; i > 0; i--) {
      if (pNum_codes[i]) { pNum_codes[i]--; pNum_codes[i+1] += 2; break; }
    }
    total--;
  }
}
}


// ////////////////////////////////////////////////////////////////////////// //
// Lower level jpeg_encoder class - useful if more control is needed than the above helper functions.
struct jpeg_encoder {
public:
  alias WriteFunc = bool delegate (scope const(ubyte)[] buf);

nothrow /*@trusted @nogc*/:
private:
  alias sample_array_t = int;

  WriteFunc m_pStream;
  JpegParams m_params;
  ubyte m_num_components;
  ubyte[3] m_comp_h_samp;
  ubyte[3] m_comp_v_samp;
  int m_image_x, m_image_y, m_image_bpp, m_image_bpl;
  int m_image_x_mcu, m_image_y_mcu;
  int m_image_bpl_xlt, m_image_bpl_mcu;
  int m_mcus_per_row;
  int m_mcu_x, m_mcu_y;
  ubyte*[16] m_mcu_lines;
  ubyte m_mcu_y_ofs;
  sample_array_t[64] m_sample_array;
  short[64] m_coefficient_array;
  int[64][2] m_quantization_tables;
  uint[256][4] m_huff_codes;
  ubyte[256][4] m_huff_code_sizes;
  ubyte[17][4] m_huff_bits;
  ubyte[256][4] m_huff_val;
  uint[256][4] m_huff_count;
  int[3] m_last_dc_val;
  enum JPGE_OUT_BUF_SIZE = 2048;
  ubyte[JPGE_OUT_BUF_SIZE] m_out_buf;
  ubyte* m_pOut_buf;
  uint m_out_buf_left;
  uint m_bit_buffer;
  uint m_bits_in;
  ubyte m_pass_num;
  bool m_all_stream_writes_succeeded = true;

private:
  // Generates an optimized offman table.
  void optimize_huffman_table (int table_num, int table_len) {
    sym_freq[MAX_HUFF_SYMBOLS] syms0;
    sym_freq[MAX_HUFF_SYMBOLS] syms1;
    syms0[0].m_key = 1; syms0[0].m_sym_index = 0;  // dummy symbol, assures that no valid code contains all 1's
    int num_used_syms = 1;
    const uint *pSym_count = &m_huff_count[table_num][0];
    for (int i = 0; i < table_len; i++) {
      if (pSym_count[i]) { syms0[num_used_syms].m_key = pSym_count[i]; syms0[num_used_syms++].m_sym_index = i+1; }
    }
    sym_freq* pSyms = radix_sort_syms(num_used_syms, syms0.ptr, syms1.ptr);
    calculate_minimum_redundancy(pSyms, num_used_syms);

    // Count the # of symbols of each code size.
    int[1+MAX_HUFF_CODESIZE] num_codes;
    //clear_obj(num_codes);
    for (int i = 0; i < num_used_syms; i++) num_codes[pSyms[i].m_key]++;

    enum JPGE_CODE_SIZE_LIMIT = 16u; // the maximum possible size of a JPEG Huffman code (valid range is [9,16] - 9 vs. 8 because of the dummy symbol)
    huffman_enforce_max_code_size(num_codes.ptr, num_used_syms, JPGE_CODE_SIZE_LIMIT);

    // Compute m_huff_bits array, which contains the # of symbols per code size.
    //clear_obj(m_huff_bits[table_num]);
    m_huff_bits[table_num][] = 0;
    for (int i = 1; i <= cast(int)JPGE_CODE_SIZE_LIMIT; i++) m_huff_bits[table_num][i] = cast(ubyte)(num_codes[i]);

    // Remove the dummy symbol added above, which must be in largest bucket.
    for (int i = JPGE_CODE_SIZE_LIMIT; i >= 1; i--) {
      if (m_huff_bits[table_num][i]) { m_huff_bits[table_num][i]--; break; }
    }

    // Compute the m_huff_val array, which contains the symbol indices sorted by code size (smallest to largest).
    for (int i = num_used_syms-1; i >= 1; i--) m_huff_val[table_num][num_used_syms-1-i] = cast(ubyte)(pSyms[i].m_sym_index-1);
  }

  bool put_obj(T) (T v) {
    try {
      return (m_pStream !is null && m_pStream((&v)[0..1]));
    } catch (Exception) {}
    return false;
  }

  bool put_buf() (const(void)* v, uint len) {
    try {
      return (m_pStream !is null && m_pStream((cast(ubyte*)v)[0..len]));
    } catch (Exception) {}
    return false;
  }

  // JPEG marker generation.
  void emit_byte (ubyte i) {
    m_all_stream_writes_succeeded = m_all_stream_writes_succeeded && put_obj(i);
  }

  void emit_word(uint i) {
    emit_byte(cast(ubyte)(i>>8));
    emit_byte(cast(ubyte)(i&0xFF));
  }

  void emit_marker (int marker) {
    emit_byte(cast(ubyte)(0xFF));
    emit_byte(cast(ubyte)(marker));
  }

  // Emit JFIF marker
  void emit_jfif_app0 () {
    emit_marker(M_APP0);
    emit_word(2+4+1+2+1+2+2+1+1);
    emit_byte(0x4A); emit_byte(0x46); emit_byte(0x49); emit_byte(0x46); /* Identifier: ASCII "JFIF" */
    emit_byte(0);
    emit_byte(1); /* Major version */
    emit_byte(1); /* Minor version */
    emit_byte(0); /* Density unit */
    emit_word(1);
    emit_word(1);
    emit_byte(0); /* No thumbnail image */
    emit_byte(0);
  }

  // Emit quantization tables
  void emit_dqt () {
    for (int i = 0; i < (m_num_components == 3 ? 2 : 1); i++) {
      emit_marker(M_DQT);
      emit_word(64+1+2);
      emit_byte(cast(ubyte)(i));
      for (int j = 0; j < 64; j++) emit_byte(cast(ubyte)(m_quantization_tables[i][j]));
    }
  }

  // Emit start of frame marker
  void emit_sof () {
    emit_marker(M_SOF0); /* baseline */
    emit_word(3*m_num_components+2+5+1);
    emit_byte(8); /* precision */
    emit_word(m_image_y);
    emit_word(m_image_x);
    emit_byte(m_num_components);
    for (int i = 0; i < m_num_components; i++) {
      emit_byte(cast(ubyte)(i+1)); /* component ID */
      emit_byte(cast(ubyte)((m_comp_h_samp[i]<<4)+m_comp_v_samp[i])); /* h and v sampling */
      emit_byte(i > 0); /* quant. table num */
    }
  }

  // Emit Huffman table.
  void emit_dht (ubyte* bits, ubyte* val, int index, bool ac_flag) {
    emit_marker(M_DHT);
    int length = 0;
    for (int i = 1; i <= 16; i++) length += bits[i];
    emit_word(length+2+1+16);
    emit_byte(cast(ubyte)(index+(ac_flag<<4)));
    for (int i = 1; i <= 16; i++) emit_byte(bits[i]);
    for (int i = 0; i < length; i++) emit_byte(val[i]);
  }

  // Emit all Huffman tables.
  void emit_dhts () {
    emit_dht(m_huff_bits[0+0].ptr, m_huff_val[0+0].ptr, 0, false);
    emit_dht(m_huff_bits[2+0].ptr, m_huff_val[2+0].ptr, 0, true);
    if (m_num_components == 3) {
      emit_dht(m_huff_bits[0+1].ptr, m_huff_val[0+1].ptr, 1, false);
      emit_dht(m_huff_bits[2+1].ptr, m_huff_val[2+1].ptr, 1, true);
    }
  }

  // emit start of scan
  void emit_sos () {
    emit_marker(M_SOS);
    emit_word(2*m_num_components+2+1+3);
    emit_byte(m_num_components);
    for (int i = 0; i < m_num_components; i++) {
      emit_byte(cast(ubyte)(i+1));
      if (i == 0)
        emit_byte((0<<4)+0);
      else
        emit_byte((1<<4)+1);
    }
    emit_byte(0); /* spectral selection */
    emit_byte(63);
    emit_byte(0);
  }

  // Emit all markers at beginning of image file.
  void emit_markers () {
    emit_marker(M_SOI);
    emit_jfif_app0();
    emit_dqt();
    emit_sof();
    emit_dhts();
    emit_sos();
  }

  // Compute the actual canonical Huffman codes/code sizes given the JPEG huff bits and val arrays.
  void compute_huffman_table (uint* codes, ubyte* code_sizes, ubyte* bits, ubyte* val) {
    import core.stdc.string : memset;

    int i, l, last_p, si;
    ubyte[257] huff_size;
    uint[257] huff_code;
    uint code;

    int p = 0;
    for (l = 1; l <= 16; l++)
      for (i = 1; i <= bits[l]; i++)
        huff_size[p++] = cast(ubyte)l;

    huff_size[p] = 0; last_p = p; // write sentinel

    code = 0; si = huff_size[0]; p = 0;

    while (huff_size[p])
    {
      while (huff_size[p] == si)
        huff_code[p++] = code++;
      code <<= 1;
      si++;
    }

    memset(codes, 0, codes[0].sizeof*256);
    memset(code_sizes, 0, code_sizes[0].sizeof*256);
    for (p = 0; p < last_p; p++)
    {
      codes[val[p]]      = huff_code[p];
      code_sizes[val[p]] = huff_size[p];
    }
  }

  // Quantization table generation.
  void compute_quant_table (int* pDst, const(short)* pSrc) {
    int q;
    if (m_params.quality < 50)
      q = 5000/m_params.quality;
    else
      q = 200-m_params.quality*2;
    for (int i = 0; i < 64; i++) {
      int j = *pSrc++; j = (j*q+50L)/100L;
      *pDst++ = JPGE_MIN(JPGE_MAX(j, 1), 255);
    }
  }

  // Higher-level methods.
  void first_pass_init () {
    import core.stdc.string : memset;
    m_bit_buffer = 0; m_bits_in = 0;
    memset(m_last_dc_val.ptr, 0, 3*m_last_dc_val[0].sizeof);
    m_mcu_y_ofs = 0;
    m_pass_num = 1;
  }

  bool second_pass_init () {
    compute_huffman_table(&m_huff_codes[0+0][0], &m_huff_code_sizes[0+0][0], m_huff_bits[0+0].ptr, m_huff_val[0+0].ptr);
    compute_huffman_table(&m_huff_codes[2+0][0], &m_huff_code_sizes[2+0][0], m_huff_bits[2+0].ptr, m_huff_val[2+0].ptr);
    if (m_num_components > 1)
    {
      compute_huffman_table(&m_huff_codes[0+1][0], &m_huff_code_sizes[0+1][0], m_huff_bits[0+1].ptr, m_huff_val[0+1].ptr);
      compute_huffman_table(&m_huff_codes[2+1][0], &m_huff_code_sizes[2+1][0], m_huff_bits[2+1].ptr, m_huff_val[2+1].ptr);
    }
    first_pass_init();
    emit_markers();
    m_pass_num = 2;
    return true;
  }

  bool jpg_open (int p_x_res, int p_y_res, int src_channels) {
    m_num_components = 3;
    switch (m_params.subsampling) {
      case JpegSubsampling.Y_ONLY:
        m_num_components = 1;
        m_comp_h_samp[0] = 1; m_comp_v_samp[0] = 1;
        m_mcu_x          = 8; m_mcu_y          = 8;
        break;
      case JpegSubsampling.H1V1:
        m_comp_h_samp[0] = 1; m_comp_v_samp[0] = 1;
        m_comp_h_samp[1] = 1; m_comp_v_samp[1] = 1;
        m_comp_h_samp[2] = 1; m_comp_v_samp[2] = 1;
        m_mcu_x          = 8; m_mcu_y          = 8;
        break;
      case JpegSubsampling.H2V1:
        m_comp_h_samp[0] = 2; m_comp_v_samp[0] = 1;
        m_comp_h_samp[1] = 1; m_comp_v_samp[1] = 1;
        m_comp_h_samp[2] = 1; m_comp_v_samp[2] = 1;
        m_mcu_x          = 16; m_mcu_y         = 8;
        break;
      case JpegSubsampling.H2V2:
        m_comp_h_samp[0] = 2; m_comp_v_samp[0] = 2;
        m_comp_h_samp[1] = 1; m_comp_v_samp[1] = 1;
        m_comp_h_samp[2] = 1; m_comp_v_samp[2] = 1;
        m_mcu_x          = 16; m_mcu_y         = 16;
        break;
      default: assert(0);
    }

    m_image_x        = p_x_res; m_image_y = p_y_res;
    m_image_bpp      = src_channels;
    m_image_bpl      = m_image_x*src_channels;
    m_image_x_mcu    = (m_image_x+m_mcu_x-1)&(~(m_mcu_x-1));
    m_image_y_mcu    = (m_image_y+m_mcu_y-1)&(~(m_mcu_y-1));
    m_image_bpl_xlt  = m_image_x*m_num_components;
    m_image_bpl_mcu  = m_image_x_mcu*m_num_components;
    m_mcus_per_row   = m_image_x_mcu/m_mcu_x;

    if ((m_mcu_lines[0] = cast(ubyte*)(jpge_malloc(m_image_bpl_mcu*m_mcu_y))) is null) return false;
    for (int i = 1; i < m_mcu_y; i++)
      m_mcu_lines[i] = m_mcu_lines[i-1]+m_image_bpl_mcu;

    compute_quant_table(m_quantization_tables[0].ptr, s_std_lum_quant.ptr);
    compute_quant_table(m_quantization_tables[1].ptr, (m_params.noChromaDiscrimFlag ? s_std_lum_quant.ptr : s_std_croma_quant.ptr));

    m_out_buf_left = JPGE_OUT_BUF_SIZE;
    m_pOut_buf = m_out_buf.ptr;

    if (m_params.twoPass)
    {
      //clear_obj(m_huff_count);
      import core.stdc.string : memset;
      memset(m_huff_count.ptr, 0, m_huff_count.sizeof);
      first_pass_init();
    }
    else
    {
      import core.stdc.string : memcpy;
      memcpy(m_huff_bits[0+0].ptr, s_dc_lum_bits.ptr, 17);    memcpy(m_huff_val[0+0].ptr, s_dc_lum_val.ptr, DC_LUM_CODES);
      memcpy(m_huff_bits[2+0].ptr, s_ac_lum_bits.ptr, 17);    memcpy(m_huff_val[2+0].ptr, s_ac_lum_val.ptr, AC_LUM_CODES);
      memcpy(m_huff_bits[0+1].ptr, s_dc_chroma_bits.ptr, 17); memcpy(m_huff_val[0+1].ptr, s_dc_chroma_val.ptr, DC_CHROMA_CODES);
      memcpy(m_huff_bits[2+1].ptr, s_ac_chroma_bits.ptr, 17); memcpy(m_huff_val[2+1].ptr, s_ac_chroma_val.ptr, AC_CHROMA_CODES);
      if (!second_pass_init()) return false;   // in effect, skip over the first pass
    }
    return m_all_stream_writes_succeeded;
  }

  void load_block_8_8_grey (int x) {
    ubyte *pSrc;
    sample_array_t *pDst = m_sample_array.ptr;
    x <<= 3;
    for (int i = 0; i < 8; i++, pDst += 8)
    {
      pSrc = m_mcu_lines[i]+x;
      pDst[0] = pSrc[0]-128; pDst[1] = pSrc[1]-128; pDst[2] = pSrc[2]-128; pDst[3] = pSrc[3]-128;
      pDst[4] = pSrc[4]-128; pDst[5] = pSrc[5]-128; pDst[6] = pSrc[6]-128; pDst[7] = pSrc[7]-128;
    }
  }

  void load_block_8_8 (int x, int y, int c) {
    ubyte *pSrc;
    sample_array_t *pDst = m_sample_array.ptr;
    x = (x*(8*3))+c;
    y <<= 3;
    for (int i = 0; i < 8; i++, pDst += 8)
    {
      pSrc = m_mcu_lines[y+i]+x;
      pDst[0] = pSrc[0*3]-128; pDst[1] = pSrc[1*3]-128; pDst[2] = pSrc[2*3]-128; pDst[3] = pSrc[3*3]-128;
      pDst[4] = pSrc[4*3]-128; pDst[5] = pSrc[5*3]-128; pDst[6] = pSrc[6*3]-128; pDst[7] = pSrc[7*3]-128;
    }
  }

  void load_block_16_8 (int x, int c) {
    ubyte* pSrc1;
    ubyte* pSrc2;
    sample_array_t *pDst = m_sample_array.ptr;
    x = (x*(16*3))+c;
    int a = 0, b = 2;
    for (int i = 0; i < 16; i += 2, pDst += 8)
    {
      pSrc1 = m_mcu_lines[i+0]+x;
      pSrc2 = m_mcu_lines[i+1]+x;
      pDst[0] = ((pSrc1[ 0*3]+pSrc1[ 1*3]+pSrc2[ 0*3]+pSrc2[ 1*3]+a)>>2)-128; pDst[1] = ((pSrc1[ 2*3]+pSrc1[ 3*3]+pSrc2[ 2*3]+pSrc2[ 3*3]+b)>>2)-128;
      pDst[2] = ((pSrc1[ 4*3]+pSrc1[ 5*3]+pSrc2[ 4*3]+pSrc2[ 5*3]+a)>>2)-128; pDst[3] = ((pSrc1[ 6*3]+pSrc1[ 7*3]+pSrc2[ 6*3]+pSrc2[ 7*3]+b)>>2)-128;
      pDst[4] = ((pSrc1[ 8*3]+pSrc1[ 9*3]+pSrc2[ 8*3]+pSrc2[ 9*3]+a)>>2)-128; pDst[5] = ((pSrc1[10*3]+pSrc1[11*3]+pSrc2[10*3]+pSrc2[11*3]+b)>>2)-128;
      pDst[6] = ((pSrc1[12*3]+pSrc1[13*3]+pSrc2[12*3]+pSrc2[13*3]+a)>>2)-128; pDst[7] = ((pSrc1[14*3]+pSrc1[15*3]+pSrc2[14*3]+pSrc2[15*3]+b)>>2)-128;
      int temp = a; a = b; b = temp;
    }
  }

  void load_block_16_8_8 (int x, int c) {
    ubyte *pSrc1;
    sample_array_t *pDst = m_sample_array.ptr;
    x = (x*(16*3))+c;
    for (int i = 0; i < 8; i++, pDst += 8) {
      pSrc1 = m_mcu_lines[i+0]+x;
      pDst[0] = ((pSrc1[ 0*3]+pSrc1[ 1*3])>>1)-128; pDst[1] = ((pSrc1[ 2*3]+pSrc1[ 3*3])>>1)-128;
      pDst[2] = ((pSrc1[ 4*3]+pSrc1[ 5*3])>>1)-128; pDst[3] = ((pSrc1[ 6*3]+pSrc1[ 7*3])>>1)-128;
      pDst[4] = ((pSrc1[ 8*3]+pSrc1[ 9*3])>>1)-128; pDst[5] = ((pSrc1[10*3]+pSrc1[11*3])>>1)-128;
      pDst[6] = ((pSrc1[12*3]+pSrc1[13*3])>>1)-128; pDst[7] = ((pSrc1[14*3]+pSrc1[15*3])>>1)-128;
    }
  }

  void load_quantized_coefficients (int component_num) {
    int *q = m_quantization_tables[component_num > 0].ptr;
    short *pDst = m_coefficient_array.ptr;
    for (int i = 0; i < 64; i++)
    {
      sample_array_t j = m_sample_array[s_zag[i]];
      if (j < 0)
      {
        if ((j = -j+(*q>>1)) < *q)
          *pDst++ = 0;
        else
          *pDst++ = cast(short)(-(j/ *q));
      }
      else
      {
        if ((j = j+(*q>>1)) < *q)
          *pDst++ = 0;
        else
          *pDst++ = cast(short)((j/ *q));
      }
      q++;
    }
  }

  void flush_output_buffer () {
    if (m_out_buf_left != JPGE_OUT_BUF_SIZE) m_all_stream_writes_succeeded = m_all_stream_writes_succeeded && put_buf(m_out_buf.ptr, JPGE_OUT_BUF_SIZE-m_out_buf_left);
    m_pOut_buf = m_out_buf.ptr;
    m_out_buf_left = JPGE_OUT_BUF_SIZE;
  }

  void put_bits (uint bits, uint len) {
    m_bit_buffer |= (cast(uint)bits<<(24-(m_bits_in += len)));
    while (m_bits_in >= 8) {
      ubyte c;
      //#define JPGE_PUT_BYTE(c) { *m_pOut_buf++ = (c); if (--m_out_buf_left == 0) flush_output_buffer(); }
      //JPGE_PUT_BYTE(c = (ubyte)((m_bit_buffer>>16)&0xFF));
      //if (c == 0xFF) JPGE_PUT_BYTE(0);
      c = cast(ubyte)((m_bit_buffer>>16)&0xFF);
      *m_pOut_buf++ = c;
      if (--m_out_buf_left == 0) flush_output_buffer();
      if (c == 0xFF) {
        *m_pOut_buf++ = 0;
        if (--m_out_buf_left == 0) flush_output_buffer();
      }
      m_bit_buffer <<= 8;
      m_bits_in -= 8;
    }
  }

  void code_coefficients_pass_one (int component_num) {
    if (component_num >= 3) return; // just to shut up static analysis
    int i, run_len, nbits, temp1;
    short *src = m_coefficient_array.ptr;
    uint *dc_count = (component_num ? m_huff_count[0+1].ptr : m_huff_count[0+0].ptr);
    uint *ac_count = (component_num ? m_huff_count[2+1].ptr : m_huff_count[2+0].ptr);

    temp1 = src[0]-m_last_dc_val[component_num];
    m_last_dc_val[component_num] = src[0];
    if (temp1 < 0) temp1 = -temp1;

    nbits = 0;
    while (temp1)
    {
      nbits++; temp1 >>= 1;
    }

    dc_count[nbits]++;
    for (run_len = 0, i = 1; i < 64; i++)
    {
      if ((temp1 = m_coefficient_array[i]) == 0)
        run_len++;
      else
      {
        while (run_len >= 16)
        {
          ac_count[0xF0]++;
          run_len -= 16;
        }
        if (temp1 < 0) temp1 = -temp1;
        nbits = 1;
        while (temp1 >>= 1) nbits++;
        ac_count[(run_len<<4)+nbits]++;
        run_len = 0;
      }
    }
    if (run_len) ac_count[0]++;
  }

  void code_coefficients_pass_two (int component_num) {
    int i, j, run_len, nbits, temp1, temp2;
    short *pSrc = m_coefficient_array.ptr;
    uint*[2] codes;
    ubyte*[2] code_sizes;

    if (component_num == 0)
    {
      codes[0] = m_huff_codes[0+0].ptr; codes[1] = m_huff_codes[2+0].ptr;
      code_sizes[0] = m_huff_code_sizes[0+0].ptr; code_sizes[1] = m_huff_code_sizes[2+0].ptr;
    }
    else
    {
      codes[0] = m_huff_codes[0+1].ptr; codes[1] = m_huff_codes[2+1].ptr;
      code_sizes[0] = m_huff_code_sizes[0+1].ptr; code_sizes[1] = m_huff_code_sizes[2+1].ptr;
    }

    temp1 = temp2 = pSrc[0]-m_last_dc_val[component_num];
    m_last_dc_val[component_num] = pSrc[0];

    if (temp1 < 0)
    {
      temp1 = -temp1; temp2--;
    }

    nbits = 0;
    while (temp1)
    {
      nbits++; temp1 >>= 1;
    }

    put_bits(codes[0][nbits], code_sizes[0][nbits]);
    if (nbits) put_bits(temp2&((1<<nbits)-1), nbits);

    for (run_len = 0, i = 1; i < 64; i++)
    {
      if ((temp1 = m_coefficient_array[i]) == 0)
        run_len++;
      else
      {
        while (run_len >= 16)
        {
          put_bits(codes[1][0xF0], code_sizes[1][0xF0]);
          run_len -= 16;
        }
        if ((temp2 = temp1) < 0)
        {
          temp1 = -temp1;
          temp2--;
        }
        nbits = 1;
        while (temp1 >>= 1)
          nbits++;
        j = (run_len<<4)+nbits;
        put_bits(codes[1][j], code_sizes[1][j]);
        put_bits(temp2&((1<<nbits)-1), nbits);
        run_len = 0;
      }
    }
    if (run_len)
      put_bits(codes[1][0], code_sizes[1][0]);
  }

  void code_block (int component_num) {
    DCT2D(m_sample_array.ptr);
    load_quantized_coefficients(component_num);
    if (m_pass_num == 1)
      code_coefficients_pass_one(component_num);
    else
      code_coefficients_pass_two(component_num);
  }

  void process_mcu_row () {
    if (m_num_components == 1)
    {
      for (int i = 0; i < m_mcus_per_row; i++)
      {
        load_block_8_8_grey(i); code_block(0);
      }
    }
    else if ((m_comp_h_samp[0] == 1) && (m_comp_v_samp[0] == 1))
    {
      for (int i = 0; i < m_mcus_per_row; i++)
      {
        load_block_8_8(i, 0, 0); code_block(0); load_block_8_8(i, 0, 1); code_block(1); load_block_8_8(i, 0, 2); code_block(2);
      }
    }
    else if ((m_comp_h_samp[0] == 2) && (m_comp_v_samp[0] == 1))
    {
      for (int i = 0; i < m_mcus_per_row; i++)
      {
        load_block_8_8(i*2+0, 0, 0); code_block(0); load_block_8_8(i*2+1, 0, 0); code_block(0);
        load_block_16_8_8(i, 1); code_block(1); load_block_16_8_8(i, 2); code_block(2);
      }
    }
    else if ((m_comp_h_samp[0] == 2) && (m_comp_v_samp[0] == 2))
    {
      for (int i = 0; i < m_mcus_per_row; i++)
      {
        load_block_8_8(i*2+0, 0, 0); code_block(0); load_block_8_8(i*2+1, 0, 0); code_block(0);
        load_block_8_8(i*2+0, 1, 0); code_block(0); load_block_8_8(i*2+1, 1, 0); code_block(0);
        load_block_16_8(i, 1); code_block(1); load_block_16_8(i, 2); code_block(2);
      }
    }
  }

  bool terminate_pass_one () {
    optimize_huffman_table(0+0, DC_LUM_CODES); optimize_huffman_table(2+0, AC_LUM_CODES);
    if (m_num_components > 1)
    {
      optimize_huffman_table(0+1, DC_CHROMA_CODES); optimize_huffman_table(2+1, AC_CHROMA_CODES);
    }
    return second_pass_init();
  }

  bool terminate_pass_two () {
    put_bits(0x7F, 7);
    flush_output_buffer();
    emit_marker(M_EOI);
    m_pass_num++; // purposely bump up m_pass_num, for debugging
    return true;
  }

  bool process_end_of_image () {
    if (m_mcu_y_ofs)
    {
      if (m_mcu_y_ofs < 16) // check here just to shut up static analysis
      {
        for (int i = m_mcu_y_ofs; i < m_mcu_y; i++) {
          import core.stdc.string : memcpy;
          memcpy(m_mcu_lines[i], m_mcu_lines[m_mcu_y_ofs-1], m_image_bpl_mcu);
        }
      }
      process_mcu_row();
    }

    if (m_pass_num == 1)
      return terminate_pass_one();
    else
      return terminate_pass_two();
  }

  void load_mcu (const(void)* pSrc) {
    import core.stdc.string : memcpy;
    const(ubyte)* Psrc = cast(const(ubyte)*)(pSrc);

    ubyte* pDst = m_mcu_lines[m_mcu_y_ofs]; // OK to write up to m_image_bpl_xlt bytes to pDst

    if (m_num_components == 1)
    {
      if (m_image_bpp == 4)
        RGBA_to_Y(pDst, Psrc, m_image_x);
      else if (m_image_bpp == 3)
        RGB_to_Y(pDst, Psrc, m_image_x);
      else
        memcpy(pDst, Psrc, m_image_x);
    }
    else
    {
      if (m_image_bpp == 4)
        RGBA_to_YCC(pDst, Psrc, m_image_x);
      else if (m_image_bpp == 3)
        RGB_to_YCC(pDst, Psrc, m_image_x);
      else
        Y_to_YCC(pDst, Psrc, m_image_x);
    }

    // Possibly duplicate pixels at end of scanline if not a multiple of 8 or 16
    if (m_num_components == 1) {
      import core.stdc.string : memset;
      memset(m_mcu_lines[m_mcu_y_ofs]+m_image_bpl_xlt, pDst[m_image_bpl_xlt-1], m_image_x_mcu-m_image_x);
    } else
    {
      const ubyte y = pDst[m_image_bpl_xlt-3+0], cb = pDst[m_image_bpl_xlt-3+1], cr = pDst[m_image_bpl_xlt-3+2];
      ubyte *q = m_mcu_lines[m_mcu_y_ofs]+m_image_bpl_xlt;
      for (int i = m_image_x; i < m_image_x_mcu; i++)
      {
        *q++ = y; *q++ = cb; *q++ = cr;
      }
    }

    if (++m_mcu_y_ofs == m_mcu_y)
    {
      process_mcu_row();
      m_mcu_y_ofs = 0;
    }
  }

  void clear() {
    m_mcu_lines[0] = null;
    m_pass_num = 0;
    m_all_stream_writes_succeeded = true;
  }


public:
  //this () { clear(); }
  ~this () { deinit(); }

  @disable this (this); // no copies

  // Initializes the compressor.
  // pStream: The stream object to use for writing compressed data.
  // comp_params - Compression parameters structure, defined above.
  // width, height  - Image dimensions.
  // channels - May be 1, or 3. 1 indicates grayscale, 3 indicates RGB source data.
  // Returns false on out of memory or if a stream write fails.
  bool setup() (WriteFunc pStream, int width, int height, int src_channels, const scope auto ref JpegParams comp_params) {
    deinit();
    if ((pStream is null || width < 1 || height < 1) || (src_channels != 1 && src_channels != 3 && src_channels != 4) || !comp_params.check()) return false;
    m_pStream = pStream;
    m_params = comp_params;
    return jpg_open(width, height, src_channels);
  }

  bool setup() (WriteFunc pStream, int width, int height, int src_channels) { return setup(pStream, width, height, src_channels, JpegParams()); }

  @property ref inout(JpegParams) params () return inout pure nothrow @trusted @nogc { pragma(inline, true); return m_params; }

  // Deinitializes the compressor, freeing any allocated memory. May be called at any time.
  void deinit () {
    jpge_free(m_mcu_lines[0]);
    clear();
  }

  @property uint total_passes () const pure nothrow @trusted @nogc { pragma(inline, true); return (m_params.twoPass ? 2 : 1); }
  @property uint cur_pass () const pure nothrow @trusted @nogc { pragma(inline, true); return m_pass_num; }

  // Call this method with each source scanline.
  // width*src_channels bytes per scanline is expected (RGB or Y format).
  // You must call with null after all scanlines are processed to finish compression.
  // Returns false on out of memory or if a stream write fails.
  bool process_scanline (const(void)* pScanline) {
    if (m_pass_num < 1 || m_pass_num > 2) return false;
    if (m_all_stream_writes_succeeded) {
      if (pScanline is null) {
        if (!process_end_of_image()) return false;
      } else {
        load_mcu(pScanline);
      }
    }
    return m_all_stream_writes_succeeded;
  }
}
