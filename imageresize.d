/++
	Image resizing support for [arsd.color.MemoryImage]. Handles up and down scaling.
	See [imageResize] for the main function, all others are lower level if you need
	more control.


	Authors:
		Originally written in C by Rich Geldreich, ported to D by ketmar.
	License:
		Public Domain / Unlicense - http://unlicense.org/
+/
module arsd.imageresize;

import arsd.color;

// ////////////////////////////////////////////////////////////////////////// //
// Separable filtering image rescaler v2.21, Rich Geldreich - richgel99@gmail.com
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
// Feb. 1996: Creation, losely based on a heavily bugfixed version of Schumacher's resampler in Graphics Gems 3.
// Oct. 2000: Ported to C++, tweaks.
// May 2001: Continous to discrete mapping, box filter tweaks.
// March 9, 2002: Kaiser filter grabbed from Jonathan Blow's GD magazine mipmap sample code.
// Sept. 8, 2002: Comments cleaned up a bit.
// Dec. 31, 2008: v2.2: Bit more cleanup, released as public domain.
// June 4, 2012: v2.21: Switched to unlicense.org, integrated GCC fixes supplied by Peter Nagy <petern@crytek.com>, Anteru at anteru.net, and clay@coge.net,
// added Codeblocks project (for testing with MinGW and GCC), VS2008 static code analysis pass.
// float or double
private:

//version = iresample_debug;


// ////////////////////////////////////////////////////////////////////////// //
public enum ImageResizeDefaultFilter = "lanczos4"; /// Default filter for image resampler.
public enum ImageResizeMaxDimension = 65536; /// Maximum image width/height for image resampler.


// ////////////////////////////////////////////////////////////////////////// //
/// Number of known image resizer filters.
public @property int imageResizeFilterCount () { pragma(inline, true); return NumFilters; }

/// Get filter name. Will return `null` for invalid index.
public string imageResizeFilterName (long idx) { pragma(inline, true); return (idx >= 0 && idx < NumFilters ? gFilters.ptr[cast(uint)idx].name : null); }

/// Find filter index by name. Will use default filter for invalid names.
public int imageResizeFindFilter (const(char)[] name, const(char)[] defaultFilter=ImageResizeDefaultFilter) {
  int res = resamplerFindFilterInternal(name);
  if (res >= 0) return res;
  res = resamplerFindFilterInternal(defaultFilter);
  if (res >= 0) return res;
  res = resamplerFindFilterInternal("lanczos4");
  assert(res >= 0);
  return res;
}


// ////////////////////////////////////////////////////////////////////////// //
/// Resize image.
public TrueColorImage imageResize(int Components=4) (MemoryImage msrcimg, int dstwdt, int dsthgt, const(char)[] filter=null, float gamma=1.0f, float filterScale=1.0f) {
  static assert(Components == 1 || Components == 3 || Components == 4, "invalid number of components in color");
  return imageResize!Components(msrcimg, dstwdt, dsthgt, imageResizeFindFilter(filter), gamma, filterScale);
}

/// ditto
public TrueColorImage imageResize(int Components=4) (MemoryImage msrcimg, int dstwdt, int dsthgt, int filter, float gamma=1.0f, float filterScale=1.0f) {
  static assert(Components == 1 || Components == 3 || Components == 4, "invalid number of components in color");
  if (msrcimg is null || msrcimg.width < 1 || msrcimg.height < 1 || msrcimg.width > ImageResizeMaxDimension || msrcimg.height > ImageResizeMaxDimension) {
    throw new Exception("invalid source image");
  }
  if (dstwdt < 1 || dsthgt < 1 || dstwdt > ImageResizeMaxDimension || dsthgt > ImageResizeMaxDimension) throw new Exception("invalid destination image size");
  auto resimg = new TrueColorImage(dstwdt, dsthgt);
  scope(failure) .destroy(resimg);
  if (auto tc = cast(TrueColorImage)msrcimg) {
    imageResize!Components(
      delegate (Color[] destrow, int y) { destrow[] = tc.imageData.colors[y*tc.width..(y+1)*tc.width]; },
      delegate (int y, const(Color)[] row) { resimg.imageData.colors[y*resimg.width..(y+1)*resimg.width] = row[]; },
      msrcimg.width, msrcimg.height, dstwdt, dsthgt, filter, gamma, filterScale
    );
  } else {
    imageResize!Components(
      delegate (Color[] destrow, int y) { foreach (immutable x, ref c; destrow) c = msrcimg.getPixel(cast(int)x, y); },
      delegate (int y, const(Color)[] row) { resimg.imageData.colors[y*resimg.width..(y+1)*resimg.width] = row[]; },
      msrcimg.width, msrcimg.height, dstwdt, dsthgt, filter, gamma, filterScale
    );
  }
  return resimg;
}


private {
  enum Linear2srgbTableSize = 4096;
  enum InvLinear2srgbTableSize = cast(float)(1.0f/Linear2srgbTableSize);
  float[256] srgb2linear = void;
  ubyte[Linear2srgbTableSize] linear2srgb = void;
  float lastGamma = float.nan;
}

/// Resize image.
/// Partial gamma correction looks better on mips; set to 1.0 to disable gamma correction.
/// Filter scale: values < 1.0 cause aliasing, but create sharper looking mips (0.75f, for example).
public void imageResize(int Components=4) (
  scope void delegate (Color[] destrow, int y) srcGetRow,
  scope void delegate (int y, const(Color)[] row) dstPutRow,
  int srcwdt, int srchgt, int dstwdt, int dsthgt,
  int filter=-1, float gamma=1.0f, float filterScale=1.0f
) {
  static assert(Components == 1 || Components == 3 || Components == 4, "invalid number of components in color");
  assert(srcGetRow !is null);
  assert(dstPutRow !is null);

  if (srcwdt < 1 || srchgt < 1 || dstwdt < 1 || dsthgt < 1 ||
      srcwdt > ImageResizeMaxDimension || srchgt > ImageResizeMaxDimension ||
      dstwdt > ImageResizeMaxDimension || dsthgt > ImageResizeMaxDimension) throw new Exception("invalid image size");

  if (filter < 0 || filter >= NumFilters) {
    filter = resamplerFindFilterInternal(ImageResizeDefaultFilter);
    if (filter < 0) {
      filter = resamplerFindFilterInternal("lanczos4");
    }
  }
  assert(filter >= 0 && filter < NumFilters);


  if (lastGamma != gamma) {
    version(iresample_debug) { import core.stdc.stdio; stderr.fprintf("creating translation tables for gamma %f (previous gamma is %f)\n", gamma, lastGamma); }
    foreach (immutable i, ref v; srgb2linear[]) {
      import std.math : pow;
      v = cast(float)pow(cast(int)i*1.0f/255.0f, gamma);
    }
    immutable float invSourceGamma = 1.0f/gamma;
    foreach (immutable i, ref v; linear2srgb[]) {
      import std.math : pow;
      int k = cast(int)(255.0f*pow(cast(int)i*InvLinear2srgbTableSize, invSourceGamma)+0.5f);
      if (k < 0) k = 0; else if (k > 255) k = 255;
      v = cast(ubyte)k;
    }
    lastGamma = gamma;
  }
  version(iresample_debug) { import core.stdc.stdio; stderr.fprintf("filter is %d\n", filter); }

  ImageResampleWorker[Components] resamplers;
  float[][Components] samples;
  Color[] srcrow, dstrow;
  scope(exit) {
    foreach (ref rsm; resamplers[]) .destroy(rsm);
    foreach (ref smr; samples[]) .destroy(smr);
  }

  // now create a ImageResampleWorker instance for each component to process
  // the first instance will create new contributor tables, which are shared by the resamplers
  // used for the other components (a memory and slight cache efficiency optimization).
  resamplers[0] = new ImageResampleWorker(srcwdt, srchgt, dstwdt, dsthgt, ImageResampleWorker.BoundaryClamp, 0.0f, 1.0f, filter, null, null, filterScale, filterScale);
  samples[0].length = srcwdt;
  srcrow.length = srcwdt;
  dstrow.length = dstwdt;
  foreach (immutable i; 1..Components) {
    resamplers[i] = new ImageResampleWorker(srcwdt, srchgt, dstwdt, dsthgt, ImageResampleWorker.BoundaryClamp, 0.0f, 1.0f, filter, resamplers[0].getClistX(), resamplers[0].getClistY(), filterScale, filterScale);
    samples[i].length = srcwdt;
  }

  int dsty = 0;
  foreach (immutable int srcy; 0..srchgt) {
    // get row components
    srcGetRow(srcrow, srcy);
    {
      auto scp = srcrow.ptr;
      foreach (immutable x; 0..srcwdt) {
        auto sc = *scp++;
        samples.ptr[0].ptr[x] = srgb2linear.ptr[sc.r]; // first component
        static if (Components > 1) samples.ptr[1].ptr[x] = srgb2linear.ptr[sc.g]; // second component
        static if (Components > 2) samples.ptr[2].ptr[x] = srgb2linear.ptr[sc.b]; // thirs component
        static if (Components == 4) samples.ptr[3].ptr[x] = sc.a*(1.0f/255.0f); // fourth component is alpha, and it is already linear
      }
    }

    foreach (immutable c; 0..Components) if (!resamplers.ptr[c].putLine(samples.ptr[c].ptr)) assert(0, "out of memory");

    for (;;) {
      int compIdx = 0;
      for (; compIdx < Components; ++compIdx) {
        const(float)* outsmp = resamplers.ptr[compIdx].getLine();
        if (outsmp is null) break;
        auto dsc = dstrow.ptr;
        // alpha?
        static if (Components == 4) {
          if (compIdx == 3) {
            foreach (immutable x; 0..dstwdt) {
              dsc.a = Color.clampToByte(cast(int)(255.0f*(*outsmp++)+0.5f));
              ++dsc;
            }
            continue;
          }
        }
        // color
        auto dsb = (cast(ubyte*)dsc)+compIdx;
        foreach (immutable x; 0..dstwdt) {
          int j = cast(int)(Linear2srgbTableSize*(*outsmp++)+0.5f);
          if (j < 0) j = 0; else if (j >= Linear2srgbTableSize) j = Linear2srgbTableSize-1;
          *dsb = linear2srgb.ptr[j];
          dsb += 4;
        }
      }
      if (compIdx < Components) break;
      // fill destination line
      assert(dsty < dsthgt);
      static if (Components != 4) {
        auto dsc = dstrow.ptr;
        foreach (immutable x; 0..dstwdt) {
          static if (Components == 1) dsc.g = dsc.b = dsc.r;
          dsc.a = 255;
          ++dsc;
        }
      }
      //version(iresample_debug) { import core.stdc.stdio; stderr.fprintf("writing dest row %d with %u components\n", dsty, Components); }
      dstPutRow(dsty, dstrow);
      ++dsty;
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
public final class ImageResampleWorker {
nothrow @trusted @nogc:
public:
  alias ResampleReal = float;
  alias Sample = ResampleReal;

  static struct Contrib {
    ResampleReal weight;
    ushort pixel;
  }

  static struct ContribList {
    ushort n;
    Contrib* p;
  }

  alias BoundaryOp = int;
  enum /*Boundary_Op*/ {
    BoundaryWrap = 0,
    BoundaryReflect = 1,
    BoundaryClamp = 2,
  }

  alias Status = int;
  enum /*Status*/ {
    StatusOkay = 0,
    StatusOutOfMemory = 1,
    StatusBadFilterName = 2,
    StatusScanBufferFull = 3,
  }

private:
  alias FilterFunc = ResampleReal function (ResampleReal) nothrow @trusted @nogc;

  int mIntermediateX;

  int mResampleSrcX;
  int mResampleSrcY;
  int mResampleDstX;
  int mResampleDstY;

  BoundaryOp mBoundaryOp;

  Sample* mPdstBuf;
  Sample* mPtmpBuf;

  ContribList* mPclistX;
  ContribList* mPclistY;

  bool mClistXForced;
  bool mClistYForced;

  bool mDelayXResample;

  int* mPsrcYCount;
  ubyte* mPsrcYFlag;

  // The maximum number of scanlines that can be buffered at one time.
  enum MaxScanBufSize = ImageResizeMaxDimension;

  static struct ScanBuf {
    int[MaxScanBufSize] scanBufY;
    Sample*[MaxScanBufSize] scanBufL;
  }

  ScanBuf* mPscanBuf;

  int mCurSrcY;
  int mCurDstY;

  Status mStatus;

  // The make_clist() method generates, for all destination samples,
  // the list of all source samples with non-zero weighted contributions.
  ContribList* makeClist(
    int srcX, int dstX, BoundaryOp boundaryOp,
    FilterFunc Pfilter,
    ResampleReal filterSupport,
    ResampleReal filterScale,
    ResampleReal srcOfs)
  {
    import core.stdc.stdlib : calloc, free;
    import std.math : floor, ceil;

    static struct ContribBounds {
      // The center of the range in DISCRETE coordinates (pixel center = 0.0f).
      ResampleReal center;
      int left, right;
    }

    ContribList* Pcontrib, PcontribRes;
    Contrib* Pcpool;
    Contrib* PcpoolNext;
    ContribBounds* PcontribBounds;

    if ((Pcontrib = cast(ContribList*)calloc(dstX, ContribList.sizeof)) is null) return null;
    scope(exit) if (Pcontrib !is null) free(Pcontrib);

    PcontribBounds = cast(ContribBounds*)calloc(dstX, ContribBounds.sizeof);
    if (PcontribBounds is null) return null;
    scope(exit) free(PcontribBounds);

    enum ResampleReal NUDGE = 0.5f;
    immutable ResampleReal ooFilterScale = 1.0f/filterScale;
    immutable ResampleReal xscale = dstX/cast(ResampleReal)srcX;

    if (xscale < 1.0f) {
      int total = 0;
      // Handle case when there are fewer destination samples than source samples (downsampling/minification).
      // stretched half width of filter
      immutable ResampleReal halfWidth = (filterSupport/xscale)*filterScale;
      // Find the range of source sample(s) that will contribute to each destination sample.
      foreach (immutable i; 0..dstX) {
        // Convert from discrete to continuous coordinates, scale, then convert back to discrete.
        ResampleReal center = (cast(ResampleReal)i+NUDGE)/xscale;
        center -= NUDGE;
        center += srcOfs;
        immutable int left = castToInt(cast(ResampleReal)floor(center-halfWidth));
        immutable int right = castToInt(cast(ResampleReal)ceil(center+halfWidth));
        PcontribBounds[i].center = center;
        PcontribBounds[i].left = left;
        PcontribBounds[i].right = right;
        total += (right-left+1);
      }

      // Allocate memory for contributors.
      if (total == 0 || ((Pcpool = cast(Contrib*)calloc(total, Contrib.sizeof)) is null)) return null;
      //scope(failure) free(Pcpool);
      //immutable int total = n;

      PcpoolNext = Pcpool;

      // Create the list of source samples which contribute to each destination sample.
      foreach (immutable i; 0..dstX) {
        int maxK = -1;
        ResampleReal maxW = -1e+20f;

        ResampleReal center = PcontribBounds[i].center;
        immutable int left = PcontribBounds[i].left;
        immutable int right = PcontribBounds[i].right;

        Pcontrib[i].n = 0;
        Pcontrib[i].p = PcpoolNext;
        PcpoolNext += (right-left+1);
        assert(PcpoolNext-Pcpool <= total);

        ResampleReal totalWeight0 = 0;
        foreach (immutable j; left..right+1) totalWeight0 += Pfilter((center-cast(ResampleReal)j)*xscale*ooFilterScale);
        immutable ResampleReal norm = cast(ResampleReal)(1.0f/totalWeight0);

        ResampleReal totalWeight1 = 0;
        foreach (immutable j; left..right+1) {
          immutable ResampleReal weight = Pfilter((center-cast(ResampleReal)j)*xscale*ooFilterScale)*norm;
          if (weight == 0.0f) continue;
          immutable int n = reflect(j, srcX, boundaryOp);
          // Increment the number of source samples which contribute to the current destination sample.
          immutable int k = Pcontrib[i].n++;
          Pcontrib[i].p[k].pixel = cast(ushort)(n); // store src sample number
          Pcontrib[i].p[k].weight = weight; // store src sample weight
          totalWeight1 += weight; // total weight of all contributors
          if (weight > maxW) {
            maxW = weight;
            maxK = k;
          }
        }
        //assert(Pcontrib[i].n);
        //assert(max_k != -1);
        if (maxK == -1 || Pcontrib[i].n == 0) return null;
        if (totalWeight1 != 1.0f) Pcontrib[i].p[maxK].weight += 1.0f-totalWeight1;
      }
    } else {
      int total = 0;
      // Handle case when there are more destination samples than source samples (upsampling).
      immutable ResampleReal halfWidth = filterSupport*filterScale;
      // Find the source sample(s) that contribute to each destination sample.
      foreach (immutable i; 0..dstX) {
        // Convert from discrete to continuous coordinates, scale, then convert back to discrete.
        ResampleReal center = (cast(ResampleReal)i+NUDGE)/xscale;
        center -= NUDGE;
        center += srcOfs;
        immutable int left = castToInt(cast(ResampleReal)floor(center-halfWidth));
        immutable int right = castToInt(cast(ResampleReal)ceil(center+halfWidth));
        PcontribBounds[i].center = center;
        PcontribBounds[i].left = left;
        PcontribBounds[i].right = right;
        total += (right-left+1);
      }

      // Allocate memory for contributors.
      if (total == 0 || ((Pcpool = cast(Contrib*)calloc(total, Contrib.sizeof)) is null)) return null;
      //scope(failure) free(Pcpool);

      PcpoolNext = Pcpool;

      // Create the list of source samples which contribute to each destination sample.
      foreach (immutable i; 0..dstX) {
        int maxK = -1;
        ResampleReal maxW = -1e+20f;

        ResampleReal center = PcontribBounds[i].center;
        immutable int left = PcontribBounds[i].left;
        immutable int right = PcontribBounds[i].right;

        Pcontrib[i].n = 0;
        Pcontrib[i].p = PcpoolNext;
        PcpoolNext += (right-left+1);
        assert(PcpoolNext-Pcpool <= total);

        ResampleReal totalWeight0 = 0;
        foreach (immutable j; left..right+1) totalWeight0 += Pfilter((center-cast(ResampleReal)j)*ooFilterScale);
        immutable ResampleReal norm = cast(ResampleReal)(1.0f/totalWeight0);

        ResampleReal totalWeight1 = 0;
        foreach (immutable j; left..right+1) {
          immutable ResampleReal weight = Pfilter((center-cast(ResampleReal)j)*ooFilterScale)*norm;
          if (weight == 0.0f) continue;
          immutable int n = reflect(j, srcX, boundaryOp);
          // Increment the number of source samples which contribute to the current destination sample.
          immutable int k = Pcontrib[i].n++;
          Pcontrib[i].p[k].pixel = cast(ushort)(n); // store src sample number
          Pcontrib[i].p[k].weight = weight; // store src sample weight
          totalWeight1 += weight; // total weight of all contributors
          if (weight > maxW) {
            maxW = weight;
            maxK = k;
          }
        }
        //assert(Pcontrib[i].n);
        //assert(max_k != -1);
        if (maxK == -1 || Pcontrib[i].n == 0) return null;
        if (totalWeight1 != 1.0f) Pcontrib[i].p[maxK].weight += 1.0f-totalWeight1;
      }
    }
    // don't free return value
    PcontribRes = Pcontrib;
    Pcontrib = null;
    return PcontribRes;
  }

  static int countOps (const(ContribList)* Pclist, int k) {
    int t = 0;
    foreach (immutable i; 0..k) t += Pclist[i].n;
    return t;
  }

  private ResampleReal mLo;
  private ResampleReal mHi;

  ResampleReal clampSample (ResampleReal f) const {
    pragma(inline, true);
    if (f < mLo) f = mLo; else if (f > mHi) f = mHi;
    return f;
  }

public:
  // src_x/src_y - Input dimensions
  // dst_x/dst_y - Output dimensions
  // boundary_op - How to sample pixels near the image boundaries
  // sample_low/sample_high - Clamp output samples to specified range, or disable clamping if sample_low >= sample_high
  // Pclist_x/Pclist_y - Optional pointers to contributor lists from another instance of a ImageResampleWorker
  // src_x_ofs/src_y_ofs - Offset input image by specified amount (fractional values okay)
  this(
    int srcX, int srcY,
    int dstX, int dstY,
    BoundaryOp boundaryOp=BoundaryClamp,
    ResampleReal sampleLow=0.0f, ResampleReal sampleHigh=0.0f,
    int PfilterIndex=-1,
    ContribList* PclistX=null,
    ContribList* PclistY=null,
    ResampleReal filterXScale=1.0f,
    ResampleReal filterYScale=1.0f,
    ResampleReal srcXOfs=0.0f,
    ResampleReal srcYOfs=0.0f)
  {
    import core.stdc.stdlib : calloc, malloc;

    int i, j;
    ResampleReal support;
    FilterFunc func;

    assert(srcX > 0);
    assert(srcY > 0);
    assert(dstX > 0);
    assert(dstY > 0);

    mLo = sampleLow;
    mHi = sampleHigh;

    mDelayXResample = false;
    mIntermediateX = 0;
    mPdstBuf = null;
    mPtmpBuf = null;
    mClistXForced = false;
    mPclistX = null;
    mClistYForced = false;
    mPclistY = null;
    mPsrcYCount = null;
    mPsrcYFlag = null;
    mPscanBuf = null;
    mStatus = StatusOkay;

    mResampleSrcX = srcX;
    mResampleSrcY = srcY;
    mResampleDstX = dstX;
    mResampleDstY = dstY;

    mBoundaryOp = boundaryOp;

    if ((mPdstBuf = cast(Sample*)malloc(mResampleDstX*Sample.sizeof)) is null) {
      mStatus = StatusOutOfMemory;
      return;
    }

    if (PfilterIndex < 0 || PfilterIndex >= NumFilters) {
      PfilterIndex = resamplerFindFilterInternal(ImageResizeDefaultFilter);
      if (PfilterIndex < 0 || PfilterIndex >= NumFilters) {
        mStatus = StatusBadFilterName;
        return;
      }
    }

    func = gFilters[PfilterIndex].func;
    support = gFilters[PfilterIndex].support;

    // Create contributor lists, unless the user supplied custom lists.
    if (PclistX is null) {
      mPclistX = makeClist(mResampleSrcX, mResampleDstX, mBoundaryOp, func, support, filterXScale, srcXOfs);
      if (mPclistX is null) {
        mStatus = StatusOutOfMemory;
        return;
      }
    } else {
      mPclistX = PclistX;
      mClistXForced = true;
    }

    if (PclistY is null) {
      mPclistY = makeClist(mResampleSrcY, mResampleDstY, mBoundaryOp, func, support, filterYScale, srcYOfs);
      if (mPclistY is null) {
        mStatus = StatusOutOfMemory;
        return;
      }
    } else {
      mPclistY = PclistY;
      mClistYForced = true;
    }

    if ((mPsrcYCount = cast(int*)calloc(mResampleSrcY, int.sizeof)) is null) {
      mStatus = StatusOutOfMemory;
      return;
    }

    if ((mPsrcYFlag = cast(ubyte*)calloc(mResampleSrcY, ubyte.sizeof)) is null) {
      mStatus = StatusOutOfMemory;
      return;
    }

    // Count how many times each source line contributes to a destination line.
    for (i = 0; i < mResampleDstY; ++i) {
      for (j = 0; j < mPclistY[i].n; ++j) {
        ++mPsrcYCount[resamplerRangeCheck(mPclistY[i].p[j].pixel, mResampleSrcY)];
      }
    }

    if ((mPscanBuf = cast(ScanBuf*)malloc(ScanBuf.sizeof)) is null) {
      mStatus = StatusOutOfMemory;
      return;
    }

    for (i = 0; i < MaxScanBufSize; ++i) {
      mPscanBuf.scanBufY.ptr[i] = -1;
      mPscanBuf.scanBufL.ptr[i] = null;
    }

    mCurSrcY = mCurDstY = 0;
    {
      // Determine which axis to resample first by comparing the number of multiplies required
      // for each possibility.
      int xOps = countOps(mPclistX, mResampleDstX);
      int yOps = countOps(mPclistY, mResampleDstY);

      // Hack 10/2000: Weight Y axis ops a little more than X axis ops.
      // (Y axis ops use more cache resources.)
      int xyOps = xOps*mResampleSrcY+(4*yOps*mResampleDstX)/3;
      int yxOps = (4*yOps*mResampleSrcX)/3+xOps*mResampleDstY;

      // Now check which resample order is better. In case of a tie, choose the order
      // which buffers the least amount of data.
      if (xyOps > yxOps || (xyOps == yxOps && mResampleSrcX < mResampleDstX)) {
        mDelayXResample = true;
        mIntermediateX = mResampleSrcX;
      } else {
        mDelayXResample = false;
        mIntermediateX = mResampleDstX;
      }
    }

    if (mDelayXResample) {
      if ((mPtmpBuf = cast(Sample*)malloc(mIntermediateX*Sample.sizeof)) is null) {
        mStatus = StatusOutOfMemory;
        return;
      }
    }
  }

  ~this () {
     import core.stdc.stdlib : free;

     if (mPdstBuf !is null) {
       free(mPdstBuf);
       mPdstBuf = null;
     }

     if (mPtmpBuf !is null) {
       free(mPtmpBuf);
       mPtmpBuf = null;
     }

     // Don't deallocate a contibutor list if the user passed us one of their own.
     if (mPclistX !is null && !mClistXForced) {
       free(mPclistX.p);
       free(mPclistX);
       mPclistX = null;
     }
     if (mPclistY !is null && !mClistYForced) {
       free(mPclistY.p);
       free(mPclistY);
       mPclistY = null;
     }

     if (mPsrcYCount !is null) {
       free(mPsrcYCount);
       mPsrcYCount = null;
     }

     if (mPsrcYFlag !is null) {
       free(mPsrcYFlag);
       mPsrcYFlag = null;
     }

     if (mPscanBuf !is null) {
       foreach (immutable i; 0..MaxScanBufSize) if (mPscanBuf.scanBufL.ptr[i] !is null) free(mPscanBuf.scanBufL.ptr[i]);
       free(mPscanBuf);
       mPscanBuf = null;
     }
  }

  // Reinits resampler so it can handle another frame.
  void restart () {
    import core.stdc.stdlib : free;
    if (StatusOkay != mStatus) return;
    mCurSrcY = mCurDstY = 0;
    foreach (immutable i; 0..mResampleSrcY) {
      mPsrcYCount[i] = 0;
      mPsrcYFlag[i] = false;
    }
    foreach (immutable i; 0..mResampleDstY) {
      foreach (immutable j; 0..mPclistY[i].n) {
        ++mPsrcYCount[resamplerRangeCheck(mPclistY[i].p[j].pixel, mResampleSrcY)];
      }
    }
    foreach (immutable i; 0..MaxScanBufSize) {
      mPscanBuf.scanBufY.ptr[i] = -1;
      free(mPscanBuf.scanBufL.ptr[i]);
      mPscanBuf.scanBufL.ptr[i] = null;
    }
  }

  // false on out of memory.
  bool putLine (const(Sample)* Psrc) {
    int i;

    if (mCurSrcY >= mResampleSrcY) return false;

    // Does this source line contribute to any destination line? if not, exit now.
    if (!mPsrcYCount[resamplerRangeCheck(mCurSrcY, mResampleSrcY)]) {
      ++mCurSrcY;
      return true;
    }

    // Find an empty slot in the scanline buffer. (FIXME: Perf. is terrible here with extreme scaling ratios.)
    for (i = 0; i < MaxScanBufSize; ++i) if (mPscanBuf.scanBufY.ptr[i] == -1) break;

    // If the buffer is full, exit with an error.
    if (i == MaxScanBufSize) {
      mStatus = StatusScanBufferFull;
      return false;
    }

    mPsrcYFlag[resamplerRangeCheck(mCurSrcY, mResampleSrcY)] = true;
    mPscanBuf.scanBufY.ptr[i] = mCurSrcY;

    // Does this slot have any memory allocated to it?
    if (!mPscanBuf.scanBufL.ptr[i]) {
      import core.stdc.stdlib : malloc;
      if ((mPscanBuf.scanBufL.ptr[i] = cast(Sample*)malloc(mIntermediateX*Sample.sizeof)) is null) {
        mStatus = StatusOutOfMemory;
        return false;
      }
    }

    // Resampling on the X axis first?
    if (mDelayXResample) {
      import core.stdc.string : memcpy;
      assert(mIntermediateX == mResampleSrcX);
      // Y-X resampling order
      memcpy(mPscanBuf.scanBufL.ptr[i], Psrc, mIntermediateX*Sample.sizeof);
    } else {
      assert(mIntermediateX == mResampleDstX);
      // X-Y resampling order
      resampleX(mPscanBuf.scanBufL.ptr[i], Psrc);
    }

    ++mCurSrcY;

    return true;
  }

  // null if no scanlines are currently available (give the resampler more scanlines!)
  const(Sample)* getLine () {
    // if all the destination lines have been generated, then always return null
    if (mCurDstY == mResampleDstY) return null;
    // check to see if all the required contributors are present, if not, return null
    foreach (immutable i; 0..mPclistY[mCurDstY].n) {
      if (!mPsrcYFlag[resamplerRangeCheck(mPclistY[mCurDstY].p[i].pixel, mResampleSrcY)]) return null;
    }
    resampleY(mPdstBuf);
    ++mCurDstY;
    return mPdstBuf;
  }

  @property Status status () const { pragma(inline, true); return mStatus; }

  // returned contributor lists can be shared with another ImageResampleWorker
  void getClists (ContribList** ptrClistX, ContribList** ptrClistY) {
    if (ptrClistX !is null) *ptrClistX = mPclistX;
    if (ptrClistY !is null) *ptrClistY = mPclistY;
  }

  @property ContribList* getClistX () { pragma(inline, true); return mPclistX; }
  @property ContribList* getClistY () { pragma(inline, true); return mPclistY; }

  // filter accessors
  static @property auto filters () {
    static struct FilterRange {
    pure nothrow @trusted @nogc:
      int idx;
      @property bool empty () const { pragma(inline, true); return (idx >= NumFilters); }
      @property string front () const { pragma(inline, true); return (idx < NumFilters ? gFilters[idx].name : null); }
      void popFront () { if (idx < NumFilters) ++idx; }
      int length () const { return cast(int)NumFilters; }
      alias opDollar = length;
    }
    return FilterRange();
  }

private:
  /* Ensure that the contributing source sample is
  * within bounds. If not, reflect, clamp, or wrap.
  */
  int reflect (in int j, in int srcX, in BoundaryOp boundaryOp) {
    int n;
    if (j < 0) {
      if (boundaryOp == BoundaryReflect) {
        n = -j;
        if (n >= srcX) n = srcX-1;
      } else if (boundaryOp == BoundaryWrap) {
        n = posmod(j, srcX);
      } else {
        n = 0;
      }
    } else if (j >= srcX) {
      if (boundaryOp == BoundaryReflect) {
        n = (srcX-j)+(srcX-1);
        if (n < 0) n = 0;
      } else if (boundaryOp == BoundaryWrap) {
        n = posmod(j, srcX);
      } else {
        n = srcX-1;
      }
    } else {
      n = j;
    }
    return n;
  }

  void resampleX (Sample* Pdst, const(Sample)* Psrc) {
    assert(Pdst);
    assert(Psrc);

    Sample total;
    ContribList *Pclist = mPclistX;
    Contrib *p;

    for (int i = mResampleDstX; i > 0; --i, ++Pclist) {
      int j = void;
      for (j = Pclist.n, p = Pclist.p, total = 0; j > 0; --j, ++p) total += Psrc[p.pixel]*p.weight;
      *Pdst++ = total;
    }
  }

  void scaleYMov (Sample* Ptmp, const(Sample)* Psrc, ResampleReal weight, int dstX) {
    // Not += because temp buf wasn't cleared.
    for (int i = dstX; i > 0; --i) *Ptmp++ = *Psrc++*weight;
  }

  void scaleYAdd (Sample* Ptmp, const(Sample)* Psrc, ResampleReal weight, int dstX) {
    for (int i = dstX; i > 0; --i) (*Ptmp++) += *Psrc++*weight;
  }

  void clamp (Sample* Pdst, int n) {
    while (n > 0) {
      *Pdst = clampSample(*Pdst);
      ++Pdst;
      --n;
    }
  }

  void resampleY (Sample* Pdst) {
    Sample* Psrc;
    ContribList* Pclist = &mPclistY[mCurDstY];

    Sample* Ptmp = mDelayXResample ? mPtmpBuf : Pdst;
    assert(Ptmp);

    // process each contributor
    foreach (immutable i; 0..Pclist.n) {
      // locate the contributor's location in the scan buffer -- the contributor must always be found!
      int j = void;
      for (j = 0; j < MaxScanBufSize; ++j) if (mPscanBuf.scanBufY.ptr[j] == Pclist.p[i].pixel) break;
      assert(j < MaxScanBufSize);
      Psrc = mPscanBuf.scanBufL.ptr[j];
      if (!i) {
        scaleYMov(Ptmp, Psrc, Pclist.p[i].weight, mIntermediateX);
      } else {
        scaleYAdd(Ptmp, Psrc, Pclist.p[i].weight, mIntermediateX);
      }

      /* If this source line doesn't contribute to any
       * more destination lines then mark the scanline buffer slot
       * which holds this source line as free.
       * (The max. number of slots used depends on the Y
       * axis sampling factor and the scaled filter width.)
       */

      if (--mPsrcYCount[resamplerRangeCheck(Pclist.p[i].pixel, mResampleSrcY)] == 0) {
        mPsrcYFlag[resamplerRangeCheck(Pclist.p[i].pixel, mResampleSrcY)] = false;
        mPscanBuf.scanBufY.ptr[j] = -1;
      }
    }

    // now generate the destination line
    if (mDelayXResample) {
      // X was resampling delayed until after Y resampling
      assert(Pdst != Ptmp);
      resampleX(Pdst, Ptmp);
    } else {
      assert(Pdst == Ptmp);
    }

    if (mLo < mHi) clamp(Pdst, mResampleDstX);
  }
}


// ////////////////////////////////////////////////////////////////////////// //
private nothrow @trusted @nogc:
int resamplerRangeCheck (int v, int h) {
  version(assert) {
    //import std.conv : to;
    //assert(v >= 0 && v < h, "invalid v ("~to!string(v)~"), should be in [0.."~to!string(h)~")");
    assert(v >= 0 && v < h); // alas, @nogc
    return v;
  } else {
    pragma(inline, true);
    return v;
  }
}

enum M_PI = 3.14159265358979323846;

// Float to int cast with truncation.
int castToInt (ImageResampleWorker.ResampleReal i) { pragma(inline, true); return cast(int)i; }

// (x mod y) with special handling for negative x values.
int posmod (int x, int y) {
  pragma(inline, true);
  if (x >= 0) {
    return (x%y);
  } else {
    int m = (-x)%y;
    if (m != 0) m = y-m;
    return m;
  }
}

// To add your own filter, insert the new function below and update the filter table.
// There is no need to make the filter function particularly fast, because it's
// only called during initializing to create the X and Y axis contributor tables.

/* pulse/Fourier window */
enum BoxFilterSupport = 0.5f;
ImageResampleWorker.ResampleReal boxFilter (ImageResampleWorker.ResampleReal t) {
  // make_clist() calls the filter function with t inverted (pos = left, neg = right)
  if (t >= -0.5f && t < 0.5f) return 1.0f; else return 0.0f;
}

/* box (*) box, bilinear/triangle */
enum TentFilterSupport = 1.0f;
ImageResampleWorker.ResampleReal tentFilter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 1.0f) return 1.0f-t; else return 0.0f;
}

/* box (*) box (*) box */
enum BellSupport = 1.5f;
ImageResampleWorker.ResampleReal bellFilter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 0.5f) return (0.75f-(t*t));
  if (t < 1.5f) { t = (t-1.5f); return (0.5f*(t*t)); }
  return (0.0f);
}

/* box (*) box (*) box (*) box */
enum BSplineSupport = 2.0f;
ImageResampleWorker.ResampleReal BSplineFilter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 1.0f) { immutable ImageResampleWorker.ResampleReal tt = t*t; return ((0.5f*tt*t)-tt+(2.0f/3.0f)); }
  if (t < 2.0f) { t = 2.0f-t; return ((1.0f/6.0f)*(t*t*t)); }
  return 0.0f;
}

// Dodgson, N., "Quadratic Interpolation for Image Resampling"
enum QuadraticSupport = 1.5f;
ImageResampleWorker.ResampleReal quadratic (ImageResampleWorker.ResampleReal t, in ImageResampleWorker.ResampleReal R) {
  pragma(inline, true);
  if (t < 0.0f) t = -t;
  if (t < QuadraticSupport) {
    immutable ImageResampleWorker.ResampleReal tt = t*t;
    if (t <= 0.5f) return (-2.0f*R)*tt+0.5f*(R+1.0f);
    return (R*tt)+(-2.0f*R-0.5f)*t+(3.0f/4.0f)*(R+1.0f);
  }
  return 0.0f;
}

ImageResampleWorker.ResampleReal quadraticInterpFilter (ImageResampleWorker.ResampleReal t) {
  return quadratic(t, 1.0f);
}

ImageResampleWorker.ResampleReal quadraticApproxFilter (ImageResampleWorker.ResampleReal t) {
  return quadratic(t, 0.5f);
}

ImageResampleWorker.ResampleReal quadraticMixFilter (ImageResampleWorker.ResampleReal t) {
  return quadratic(t, 0.8f);
}

// Mitchell, D. and A. Netravali, "Reconstruction Filters in Computer Graphics."
// Computer Graphics, Vol. 22, No. 4, pp. 221-228.
// (B, C)
// (1/3, 1/3)  - Defaults recommended by Mitchell and Netravali
// (1, 0)    - Equivalent to the Cubic B-Spline
// (0, 0.5)   - Equivalent to the Catmull-Rom Spline
// (0, C)   - The family of Cardinal Cubic Splines
// (B, 0)   - Duff's tensioned B-Splines.
ImageResampleWorker.ResampleReal mitchell (ImageResampleWorker.ResampleReal t, in ImageResampleWorker.ResampleReal B, in ImageResampleWorker.ResampleReal C) {
  ImageResampleWorker.ResampleReal tt = t*t;
  if (t < 0.0f) t = -t;
  if (t < 1.0f) {
    t = (((12.0f-9.0f*B-6.0f*C)*(t*tt))+
         ((-18.0f+12.0f*B+6.0f*C)*tt)+
         (6.0f-2.0f*B));
    return (t/6.0f);
  }
  if (t < 2.0f) {
    t = (((-1.0f*B-6.0f*C)*(t*tt))+
         ((6.0f*B+30.0f*C)*tt)+
         ((-12.0f*B-48.0f*C)*t)+
         (8.0f*B+24.0f*C));
    return (t/6.0f);
  }
  return 0.0f;
}

enum MitchellSupport = 2.0f;
ImageResampleWorker.ResampleReal mitchellFilter (ImageResampleWorker.ResampleReal t) {
  return mitchell(t, 1.0f/3.0f, 1.0f/3.0f);
}

enum CatmullRomSupport = 2.0f;
ImageResampleWorker.ResampleReal catmullRomFilter (ImageResampleWorker.ResampleReal t) {
  return mitchell(t, 0.0f, 0.5f);
}

double sinc (double x) {
  pragma(inline, true);
  import std.math : sin;
  x *= M_PI;
  if (x < 0.01f && x > -0.01f) return 1.0f+x*x*(-1.0f/6.0f+x*x*1.0f/120.0f);
  return sin(x)/x;
}

ImageResampleWorker.ResampleReal clean (double t) {
  pragma(inline, true);
  import std.math : abs;
  enum EPSILON = cast(ImageResampleWorker.ResampleReal)0.0000125f;
  if (abs(t) < EPSILON) return 0.0f;
  return cast(ImageResampleWorker.ResampleReal)t;
}

//static double blackman_window(double x)
//{
//  return 0.42f+0.50f*cos(M_PI*x)+0.08f*cos(2.0f*M_PI*x);
//}

double blackmanExactWindow (double x) {
  pragma(inline, true);
  import std.math : cos;
  return 0.42659071f+0.49656062f*cos(M_PI*x)+0.07684867f*cos(2.0f*M_PI*x);
}

enum BlackmanSupport = 3.0f;
ImageResampleWorker.ResampleReal blackmanFilter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 3.0f) {
    //return clean(sinc(t)*blackman_window(t/3.0f));
    return clean(sinc(t)*blackmanExactWindow(t/3.0f));
  }
  return (0.0f);
}

// with blackman window
enum GaussianSupport = 1.25f;
ImageResampleWorker.ResampleReal gaussianFilter (ImageResampleWorker.ResampleReal t) {
  import std.math : exp, sqrt;
  if (t < 0) t = -t;
  if (t < GaussianSupport) return clean(exp(-2.0f*t*t)*sqrt(2.0f/M_PI)*blackmanExactWindow(t/GaussianSupport));
  return 0.0f;
}

// Windowed sinc -- see "Jimm Blinn's Corner: Dirty Pixels" pg. 26.
enum Lanczos3Support = 3.0f;
ImageResampleWorker.ResampleReal lanczos3Filter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 3.0f) return clean(sinc(t)*sinc(t/3.0f));
  return (0.0f);
}

enum Lanczos4Support = 4.0f;
ImageResampleWorker.ResampleReal lanczos4Filter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 4.0f) return clean(sinc(t)*sinc(t/4.0f));
  return (0.0f);
}

enum Lanczos6Support = 6.0f;
ImageResampleWorker.ResampleReal lanczos6Filter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 6.0f) return clean(sinc(t)*sinc(t/6.0f));
  return (0.0f);
}

enum Lanczos12Support = 12.0f;
ImageResampleWorker.ResampleReal lanczos12Filter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < 12.0f) return clean(sinc(t)*sinc(t/12.0f));
  return (0.0f);
}

double bessel0 (double x) {
  enum EpsilonRatio = cast(double)1E-16;
  double xh = 0.5*x;
  double sum = 1.0;
  double pow = 1.0;
  int k = 0;
  double ds = 1.0;
  // FIXME: Shouldn't this stop after X iterations for max. safety?
  while (ds > sum*EpsilonRatio) {
    ++k;
    pow = pow*(xh/k);
    ds = pow*pow;
    sum = sum+ds;
  }
  return sum;
}

enum KaiserAlpha = cast(ImageResampleWorker.ResampleReal)4.0;
double kaiser (double alpha, double halfWidth, double x) {
  pragma(inline, true);
  import std.math : sqrt;
  immutable double ratio = (x/halfWidth);
  return bessel0(alpha*sqrt(1-ratio*ratio))/bessel0(alpha);
}

enum KaiserSupport = 3;
static ImageResampleWorker.ResampleReal kaiserFilter (ImageResampleWorker.ResampleReal t) {
  if (t < 0.0f) t = -t;
  if (t < KaiserSupport) {
    import std.math : exp, log;
    // db atten
    immutable ImageResampleWorker.ResampleReal att = 40.0f;
    immutable ImageResampleWorker.ResampleReal alpha = cast(ImageResampleWorker.ResampleReal)(exp(log(cast(double)0.58417*(att-20.96))*0.4)+0.07886*(att-20.96));
    //const ImageResampleWorker.Resample_Real alpha = KAISER_ALPHA;
    return cast(ImageResampleWorker.ResampleReal)clean(sinc(t)*kaiser(alpha, KaiserSupport, t));
  }
  return 0.0f;
}

// filters[] is a list of all the available filter functions.
struct FilterInfo {
  string name;
  ImageResampleWorker.FilterFunc func;
  ImageResampleWorker.ResampleReal support;
}

static immutable FilterInfo[16] gFilters = [
   FilterInfo("box",              &boxFilter,             BoxFilterSupport),
   FilterInfo("tent",             &tentFilter,            TentFilterSupport),
   FilterInfo("bell",             &bellFilter,            BellSupport),
   FilterInfo("bspline",          &BSplineFilter,         BSplineSupport),
   FilterInfo("mitchell",         &mitchellFilter,        MitchellSupport),
   FilterInfo("lanczos3",         &lanczos3Filter,        Lanczos3Support),
   FilterInfo("blackman",         &blackmanFilter,        BlackmanSupport),
   FilterInfo("lanczos4",         &lanczos4Filter,        Lanczos4Support),
   FilterInfo("lanczos6",         &lanczos6Filter,        Lanczos6Support),
   FilterInfo("lanczos12",        &lanczos12Filter,       Lanczos12Support),
   FilterInfo("kaiser",           &kaiserFilter,          KaiserSupport),
   FilterInfo("gaussian",         &gaussianFilter,        GaussianSupport),
   FilterInfo("catmullrom",       &catmullRomFilter,      CatmullRomSupport),
   FilterInfo("quadratic_interp", &quadraticInterpFilter, QuadraticSupport),
   FilterInfo("quadratic_approx", &quadraticApproxFilter, QuadraticSupport),
   FilterInfo("quadratic_mix",    &quadraticMixFilter,    QuadraticSupport),
];

enum NumFilters = cast(int)gFilters.length;


bool rsmStringEqu (const(char)[] s0, const(char)[] s1) {
  for (;;) {
    if (s0.length && (s0.ptr[0] <= ' ' || s0.ptr[0] == '_')) { s0 = s0[1..$]; continue; }
    if (s1.length && (s1.ptr[0] <= ' ' || s1.ptr[0] == '_')) { s1 = s1[1..$]; continue; }
    if (s0.length == 0) {
      while (s1.length && (s1.ptr[0] <= ' ' || s1.ptr[0] == '_')) s1 = s1[1..$];
      return (s1.length == 0);
    }
    if (s1.length == 0) {
      while (s0.length && (s0.ptr[0] <= ' ' || s0.ptr[0] == '_')) s0 = s0[1..$];
      return (s0.length == 0);
    }
    assert(s0.length && s1.length);
    char c0 = s0.ptr[0];
    char c1 = s1.ptr[0];
    if (c0 >= 'A' && c0 <= 'Z') c0 += 32; // poor man's tolower
    if (c1 >= 'A' && c1 <= 'Z') c1 += 32; // poor man's tolower
    if (c0 != c1) return false;
    s0 = s0[1..$];
    s1 = s1[1..$];
  }
}


int resamplerFindFilterInternal (const(char)[] name) {
  if (name.length) {
    foreach (immutable idx, const ref fi; gFilters[]) if (rsmStringEqu(name, fi.name)) return cast(int)idx;
  }
  return -1;
}
