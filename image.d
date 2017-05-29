/// this file imports all available image decoders, and provides convenient functions to load image regardless of it's format.
module arsd.image;

public import arsd.color;
public import arsd.png;
public import arsd.jpeg;
public import arsd.bmp;
public import arsd.targa;

static if (__traits(compiles, { import iv.vfs; })) enum ArsdImageHasIVVFS = true; else enum ArsdImageHasIVVFS = false;


private bool strEquCI (const(char)[] s0, const(char)[] s1) pure nothrow @trusted @nogc {
  if (s0.length != s1.length) return false;
  foreach (immutable idx, char ch; s0) {
    if (ch >= 'A' && ch <= 'Z') ch += 32; // poor man's tolower()
    char c1 = s1.ptr[idx];
    if (c1 >= 'A' && c1 <= 'Z') c1 += 32; // poor man's tolower()
    if (ch != c1) return false;
  }
  return true;
}


/// Image formats `arsd.image` can load (except `Unknown`, of course).
enum ImageFileFormat {
  Unknown, ///
  Png, ///
  Bmp, ///
  Jpeg, ///
  Tga, ///
  Gif, /// we can't load it yet, but we can at least detect it
}


/// Try to guess image format from file extension.
public ImageFileFormat guessImageFormatFromExtension (const(char)[] filename) {
  if (filename.length < 2) return ImageFileFormat.Unknown;
  size_t extpos = filename.length;
  version(Windows) {
    while (extpos > 0 && filename.ptr[extpos-1] != '.' && filename.ptr[extpos-1] != '/' && filename.ptr[extpos-1] != '\\' && filename.ptr[extpos-1] != ':') --extpos;
  } else {
    while (extpos > 0 && filename.ptr[extpos-1] != '.' && filename.ptr[extpos-1] != '/') --extpos;
  }
  if (extpos == 0 || filename.ptr[extpos-1] != '.') return ImageFileFormat.Unknown;
  auto ext = filename[extpos..$];
  if (strEquCI(ext, "png")) return ImageFileFormat.Png;
  if (strEquCI(ext, "bmp")) return ImageFileFormat.Bmp;
  if (strEquCI(ext, "jpg") || strEquCI(ext, "jpeg")) return ImageFileFormat.Jpeg;
  if (strEquCI(ext, "gif")) return ImageFileFormat.Gif;
  if (strEquCI(ext, "tga")) return ImageFileFormat.Tga;
  return ImageFileFormat.Unknown;
}


/// Try to guess image format by first data bytes.
public ImageFileFormat guessImageFormatFromMemory (const(void)[] membuf) {
  enum TargaSign = "TRUEVISION-XFILE.\x00";
  auto buf = cast(const(ubyte)[])membuf;
  if (buf.length == 0) return ImageFileFormat.Unknown;
  // detect file format
  // png
  if (buf.length > 7 && buf.ptr[0] == 0x89 && buf.ptr[1] == 0x50 && buf.ptr[2] == 0x4E &&
      buf.ptr[3] == 0x47 && buf.ptr[4] == 0x0D && buf.ptr[5] == 0x0A && buf.ptr[6] == 0x1A)
  {
    return ImageFileFormat.Png;
  }
  // bmp
  if (buf.length > 6 && buf.ptr[0] == 'B' && buf.ptr[1] == 'M') {
    uint datasize = buf.ptr[2]|(buf.ptr[3]<<8)|(buf.ptr[4]<<16)|(buf.ptr[5]<<24);
    if (datasize > 6 && datasize <= buf.length) return ImageFileFormat.Bmp;
  }
  // gif
  if (buf.length > 5 && buf.ptr[0] == 'G' && buf.ptr[1] == 'I' && buf.ptr[2] == 'F' &&
      buf.ptr[3] == '8' && (buf.ptr[4] == '7' || buf.ptr[4] == '9'))
  {
    return ImageFileFormat.Gif;
  }
  // jpg
  try {
    int width, height, components;
    if (detect_jpeg_image_from_memory(buf, width, height, components)) return ImageFileFormat.Jpeg;
  } catch (Exception e) {} // sorry
  // tga (sorry, targas without footer, i don't love you)
  if (buf.length > TargaSign.length+4*2 && cast(const(char)[])(buf[$-TargaSign.length..$]) == TargaSign) {
    // more guesswork
    switch (buf.ptr[2]) {
      case 1: case 2: case 3: case 9: case 10: case 11: return ImageFileFormat.Tga;
      default:
    }
  }
  // ok, try to guess targa by validating some header fields
  bool guessTarga () nothrow @trusted @nogc {
    if (buf.length < 45) return false; // minimal 1x1 tga
    immutable ubyte idlength = buf.ptr[0];
    immutable ubyte bColorMapType = buf.ptr[1];
    immutable ubyte type = buf.ptr[2];
    immutable ushort wColorMapFirstEntryIndex = cast(ushort)(buf.ptr[3]|(buf.ptr[4]<<8));
    immutable ushort wColorMapLength = cast(ushort)(buf.ptr[5]|(buf.ptr[6]<<8));
    immutable ubyte bColorMapEntrySize = buf.ptr[7];
    immutable ushort wOriginX = cast(ushort)(buf.ptr[8]|(buf.ptr[9]<<8));
    immutable ushort wOriginY = cast(ushort)(buf.ptr[10]|(buf.ptr[11]<<8));
    immutable ushort wImageWidth = cast(ushort)(buf.ptr[12]|(buf.ptr[13]<<8));
    immutable ushort wImageHeight = cast(ushort)(buf.ptr[14]|(buf.ptr[15]<<8));
    immutable ubyte bPixelDepth = buf.ptr[16];
    immutable ubyte bImageDescriptor = buf.ptr[17];
    if (wImageWidth < 1 || wImageHeight < 1 || wImageWidth > 32000 || wImageHeight > 32000) return false; // arbitrary limit
    immutable uint pixelsize = (bPixelDepth>>3);
    switch (type) {
      case 2: // truecolor, raw
      case 10: // truecolor, rle
        switch (pixelsize) {
          case 2: case 3: case 4: break;
          default: return false;
        }
        break;
      case 1: // paletted, raw
      case 9: // paletted, rle
        if (pixelsize != 1) return false;
        break;
      case 3: // b/w, raw
      case 11: // b/w, rle
        if (pixelsize != 1 && pixelsize != 2) return false;
        break;
      default: // invalid type
        return false;
    }
    // check for valid colormap
    switch (bColorMapType) {
      case 0:
        if (wColorMapFirstEntryIndex != 0 || wColorMapLength != 0) return 0;
        break;
      case 1:
        if (bColorMapEntrySize != 15 && bColorMapEntrySize != 16 && bColorMapEntrySize != 24 && bColorMapEntrySize != 32) return false;
        if (wColorMapLength == 0) return false;
        break;
      default: // invalid colormap type
        return false;
    }
    if (((bImageDescriptor>>6)&3) != 0) return false;
    // this *looks* like a tga
    return true;
  }
  if (guessTarga()) return ImageFileFormat.Tga;
  // dunno
  return ImageFileFormat.Unknown;
}


/// Try to guess image format from file name and load that image.
public MemoryImage loadImageFromFile(T:const(char)[]) (T filename) {
  static if (is(T == typeof(null))) {
    throw new Exception("cannot load image from unnamed file");
  } else {
    final switch (guessImageFormatFromExtension(filename)) {
      case ImageFileFormat.Unknown:
        //throw new Exception("cannot determine file format from extension");
        static if (ArsdImageHasIVVFS) auto fl = VFile(filename); else { import std.stdio; auto fl = File(filename); }
        auto fsz = fl.size-fl.tell;
        if (fsz < 4) throw new Exception("cannot determine file format");
        if (fsz > int.max/8) throw new Exception("image data too big");
        auto data = new ubyte[](cast(uint)fsz);
        scope(exit) delete data; // this should be safe, as image will copy data to it's internal storage
        fl.rawReadExact(data);
        return loadImageFromMemory(data);
      case ImageFileFormat.Png: static if (is(T == string)) return readPng(filename); else return readPng(filename.idup);
      case ImageFileFormat.Bmp: static if (is(T == string)) return readBmp(filename); else return readBmp(filename.idup);
      case ImageFileFormat.Jpeg: return readJpeg(filename);
      case ImageFileFormat.Gif: throw new Exception("arsd has no GIF loader yet");
      case ImageFileFormat.Tga: return loadTga(filename);
    }
  }
}


/// Try to guess image format from data and load that image.
public MemoryImage loadImageFromMemory (const(void)[] membuf) {
  final switch (guessImageFormatFromMemory(membuf)) {
    case ImageFileFormat.Unknown: throw new Exception("cannot determine file format");
    case ImageFileFormat.Png: return imageFromPng(readPng(cast(const(ubyte)[])membuf));
    case ImageFileFormat.Bmp: return readBmp(cast(const(ubyte)[])membuf);
    case ImageFileFormat.Jpeg: return readJpegFromMemory(cast(const(ubyte)[])membuf);
    case ImageFileFormat.Gif: throw new Exception("arsd has no GIF loader yet");
    case ImageFileFormat.Tga: return loadTgaMem(membuf);
  }
}


static if (ArsdImageHasIVVFS) {
import iv.vfs;
public MemoryImage loadImageFromFile (VFile fl) {
  auto fsz = fl.size-fl.tell;
  if (fsz < 4) throw new Exception("cannot determine file format");
  if (fsz > int.max/8) throw new Exception("image data too big");
  auto data = new ubyte[](cast(uint)fsz);
  scope(exit) delete data; // this should be safe, as image will copy data to it's internal storage
  fl.rawReadExact(data);
  return loadImageFromMemory(data);
}
}
