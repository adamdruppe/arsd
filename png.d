/++
	PNG file read and write. Leverages [arsd.color|color.d]'s [MemoryImage] interfaces for interop.

	The main high-level functions you want are [readPng], [readPngFromBytes], [writePng], and maybe [writeImageToPngFile] or [writePngLazy] for some circumstances.

	The other functions are low-level implementations and helpers for dissecting the png file format.

	History:
		Originally written in 2009. This is why some of it is still written in a C-like style!

	See_Also:
	$(LIST
		* [arsd.image] has generic load interfaces that can handle multiple file formats, including png.
		* [arsd.apng] handles the animated png extensions.
	)
+/
module arsd.png;

import core.memory;

/++
	Easily reads a png file into a [MemoryImage]

	Returns:
		Please note this function doesn't return null right now, but you should still check for null anyway as that might change.

		The returned [MemoryImage] is either a [IndexedImage] or a [TrueColorImage], depending on the file's color mode. You can cast it to one or the other, or just call [MemoryImage.getAsTrueColorImage] which will cast and return or convert as needed automatically.

		Greyscale pngs and bit depths other than 8 are converted for the ease of the MemoryImage interface. If you need more detail, try [PNG] and [getDatastream] etc.
+/
MemoryImage readPng(string filename) {
	import std.file;
	return imageFromPng(readPng(cast(ubyte[]) read(filename)));
}

/++
	Easily reads a png from a data array into a MemoryImage.

	History:
		Added December 29, 2021 (dub v10.5)
+/
MemoryImage readPngFromBytes(const(ubyte)[] bytes) {
	return imageFromPng(readPng(bytes));
}

/++
	Saves a MemoryImage to a png file. See also: [writeImageToPngFile] which uses memory a little more efficiently

	See_Also:
		[writePngToArray]
+/
void writePng(string filename, MemoryImage mi) {
	// FIXME: it would be nice to write the file lazily so we don't have so many intermediate buffers here
	import std.file;
	std.file.write(filename, writePngToArray(mi));
}

/++
	Creates an in-memory png file from the given memory image, returning it.

	History:
		Added April 21, 2023 (dub v11.0)
	See_Also:
		[writePng]
+/
ubyte[] writePngToArray(MemoryImage mi) {
	PNG* png;
	if(auto p = cast(IndexedImage) mi)
		png = pngFromImage(p);
	else if(auto p = cast(TrueColorImage) mi)
		png = pngFromImage(p);
	else assert(0);
	return writePng(png);
}

/++
	Represents the different types of png files, with numbers matching what the spec gives for filevalues.
+/
enum PngType {
	greyscale = 0, /// The data must be `depth` bits per pixel
	truecolor = 2, /// The data will be RGB triples, so `depth * 3` bits per pixel. Depth must be 8 or 16.
	indexed = 3, /// The data must be `depth` bits per pixel, with a palette attached. Use [writePng] with [IndexedImage] for this mode. Depth must be <= 8.
	greyscale_with_alpha = 4, /// The data must be (grey, alpha) byte pairs for each pixel. Thus `depth * 2` bits per pixel. Depth must be 8 or 16.
	truecolor_with_alpha = 6 /// The data must be RGBA quads for each pixel. Thus, `depth * 4` bits per pixel. Depth must be 8 or 16.
}

/++
	Saves an image from an existing array of pixel data. Note that depth other than 8 may not be implemented yet. Also note depth of 16 must be stored big endian
+/
void writePng(string filename, const ubyte[] data, int width, int height, PngType type, ubyte depth = 8) {
	PngHeader h;
	h.width = width;
	h.height = height;
	h.type = cast(ubyte) type;
	h.depth = depth;

	auto png = blankPNG(h);
	addImageDatastreamToPng(data, png);

	import std.file;
	std.file.write(filename, writePng(png));
}


/*
//Here's a simple test program that shows how to write a quick image viewer with simpledisplay:

import arsd.png;
import arsd.simpledisplay;

import std.file;
void main(string[] args) {
	// older api, the individual functions give you more control if you need it
	//auto img = imageFromPng(readPng(cast(ubyte[]) read(args[1])));

	// newer api, simpler but less control
	auto img = readPng(args[1]);

	// displayImage is from simpledisplay and just pops up a window to show the image
	// simpledisplay's Images are a little different than MemoryImages that this loads,
	// but conversion is easy
	displayImage(Image.fromMemoryImage(img));
}
*/

// By Adam D. Ruppe, 2009-2010, released into the public domain
//import std.file;

//import std.zlib;

public import arsd.color;

/**
	The return value should be casted to indexed or truecolor depending on what the file is. You can
	also use getAsTrueColorImage to forcibly convert it if needed.

	To get an image from a png file, do something like this:

	auto i = cast(TrueColorImage) imageFromPng(readPng(cast(ubyte)[]) std.file.read("file.png")));
*/
MemoryImage imageFromPng(PNG* png) {
	PngHeader h = getHeader(png);

	/** Types from the PNG spec:
		0 - greyscale
		2 - truecolor
		3 - indexed color
		4 - grey with alpha
		6 - true with alpha

		1, 5, and 7 are invalid.

		There's a kind of bitmask going on here:
			If type&1, it has a palette.
			If type&2, it is in color.
			If type&4, it has an alpha channel in the datastream.
	*/

	MemoryImage i;
	ubyte[] idata;
	// FIXME: some duplication with the lazy reader below in the module

	switch(h.type) {
		case 0: // greyscale
		case 4: // greyscale with alpha
			// this might be a different class eventually...
			auto a = new TrueColorImage(h.width, h.height);
			idata = a.imageData.bytes;
			i = a;
		break;
		case 2: // truecolor
		case 6: // truecolor with alpha
			auto a = new TrueColorImage(h.width, h.height);
			idata = a.imageData.bytes;
			i = a;
		break;
		case 3: // indexed
			auto a = new IndexedImage(h.width, h.height);
			a.palette = fetchPalette(png);
			a.hasAlpha = true; // FIXME: don't be so conservative here
			idata = a.data;
			i = a;
		break;
		default:
			assert(0, "invalid png");
	}

	size_t idataIdx = 0;

	auto file = LazyPngFile!(Chunk[])(png.chunks);
	immutable(ubyte)[] previousLine;
	auto bpp = bytesPerPixel(h);
	foreach(line; file.rawDatastreamByChunk()) {
		auto filter = line[0];
		auto data = unfilter(filter, line[1 .. $], previousLine, bpp);
		previousLine = data;

		convertPngData(h.type, h.depth, data, h.width, idata, idataIdx);
	}
	assert(idataIdx == idata.length, "not all filled, wtf");

	assert(i !is null);

	return i;
}

/+
	This is used by the load MemoryImage functions to convert the png'd datastream into the format MemoryImage's implementations expect.

	idata needs to be already sized for the image! width * height if indexed, width*height*4 if not.
+/
void convertPngData(ubyte type, ubyte depth, const(ubyte)[] data, int width, ubyte[] idata, ref size_t idataIdx) {
	ubyte consumeOne() {
		ubyte ret = data[0];
		data = data[1 .. $];
		return ret;
	}
	import std.conv;

	loop: for(int pixel = 0; pixel < width; pixel++)
		switch(type) {
			case 0: // greyscale
			case 4: // greyscale with alpha
			case 3: // indexed

				void acceptPixel(ubyte p) {
					if(type == 3) {
						idata[idataIdx++] = p;
					} else {
						if(depth == 1) {
							p = p ? 0xff : 0;
						} else if (depth == 2) {
							p |= p << 2;
							p |= p << 4;
						}
						else if (depth == 4) {
							p |= p << 4;
						}
						idata[idataIdx++] = p;
						idata[idataIdx++] = p;
						idata[idataIdx++] = p;

						if(type == 0)
							idata[idataIdx++] = 255;
						else if(type == 4)
							idata[idataIdx++] = consumeOne();
					}
				}

				auto b = consumeOne();
				switch(depth) {
					case 1:
						acceptPixel((b >> 7) & 0x01);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 6) & 0x01);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 5) & 0x01);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 4) & 0x01);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 3) & 0x01);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 2) & 0x01);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 1) & 0x01);
						pixel++; if(pixel == width) break loop;
						acceptPixel(b & 0x01);
					break;
					case 2:
						acceptPixel((b >> 6) & 0x03);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 4) & 0x03);
						pixel++; if(pixel == width) break loop;
						acceptPixel((b >> 2) & 0x03);
						pixel++; if(pixel == width) break loop;
						acceptPixel(b & 0x03);
					break;
					case 4:
						acceptPixel((b >> 4) & 0x0f);
						pixel++; if(pixel == width) break loop;
						acceptPixel(b & 0x0f);
					break;
					case 8:
						acceptPixel(b);
					break;
					case 16:
						assert(type != 3); // 16 bit indexed isn't supported per png spec
						acceptPixel(b);
						consumeOne(); // discarding the least significant byte as we can't store it anyway
					break;
					default:
						assert(0, "bit depth not implemented");
				}
			break;
			case 2: // truecolor
			case 6: // true with alpha
				if(depth == 8) {
					idata[idataIdx++] = consumeOne();
					idata[idataIdx++] = consumeOne();
					idata[idataIdx++] = consumeOne();
					idata[idataIdx++] = (type == 6) ? consumeOne() : 255;
				} else if(depth == 16) {
					idata[idataIdx++] = consumeOne();
					consumeOne();
					idata[idataIdx++] = consumeOne();
					consumeOne();
					idata[idataIdx++] = consumeOne();
					consumeOne();
					idata[idataIdx++] = (type == 6) ? consumeOne() : 255;
					if(type == 6)
						consumeOne();

				} else assert(0, "unsupported truecolor bit depth " ~ to!string(depth));
			break;
			default: assert(0);
		}
	assert(data.length == 0, "not all consumed, wtf " ~ to!string(data));
}

/*
struct PngHeader {
	uint width;
	uint height;
	ubyte depth = 8;
	ubyte type = 6; // 0 - greyscale, 2 - truecolor, 3 - indexed color, 4 - grey with alpha, 6 - true with alpha
	ubyte compressionMethod = 0; // should be zero
	ubyte filterMethod = 0; // should be zero
	ubyte interlaceMethod = 0; // bool
}
*/


/++
	Creates the [PNG] data structure out of an [IndexedImage]. This structure will have the minimum number of colors
	needed to represent the image faithfully in the file and will be ready for writing to a file.

	This is called by [writePng].
+/
PNG* pngFromImage(IndexedImage i) {
	PngHeader h;
	h.width = i.width;
	h.height = i.height;
	h.type = 3;
	if(i.numColors() <= 2)
		h.depth = 1;
	else if(i.numColors() <= 4)
		h.depth = 2;
	else if(i.numColors() <= 16)
		h.depth = 4;
	else if(i.numColors() <= 256)
		h.depth = 8;
	else throw new Exception("can't save this as an indexed png");

	auto png = blankPNG(h);

	// do palette and alpha
	// FIXME: if there is only one transparent color, set it as the special chunk for that

	// FIXME: we'd get a smaller file size if the transparent pixels were arranged first
	Chunk palette;
	palette.type = ['P', 'L', 'T', 'E'];
	palette.size = cast(int) i.palette.length * 3;
	palette.payload.length = palette.size;

	Chunk alpha;
	if(i.hasAlpha) {
		alpha.type = ['t', 'R', 'N', 'S'];
		alpha.size = cast(uint) i.palette.length;
		alpha.payload.length = alpha.size;
	}

	for(int a = 0; a < i.palette.length; a++) {
		palette.payload[a*3+0] = i.palette[a].r;
		palette.payload[a*3+1] = i.palette[a].g;
		palette.payload[a*3+2] = i.palette[a].b;
		if(i.hasAlpha)
			alpha.payload[a] = i.palette[a].a;
	}

	palette.checksum = crc("PLTE", palette.payload);
	png.chunks ~= palette;
	if(i.hasAlpha) {
		alpha.checksum = crc("tRNS", alpha.payload);
		png.chunks ~= alpha;
	}

	// do the datastream
	if(h.depth == 8) {
		addImageDatastreamToPng(i.data, png);
	} else {
		// gotta convert it

		auto bitsPerLine = i.width * h.depth;
		if(bitsPerLine % 8 != 0)
			bitsPerLine = bitsPerLine / 8 + 1;
		else
			bitsPerLine = bitsPerLine / 8;

		ubyte[] datastream = new ubyte[bitsPerLine * i.height];
		int shift = 0;

		switch(h.depth) {
			default: assert(0);
			case 1: shift = 7; break;
			case 2: shift = 6; break;
			case 4: shift = 4; break;
			case 8: shift = 0; break;
		}
		size_t dsp = 0;
		size_t dpos = 0;
		bool justAdvanced;
		for(int y = 0; y < i.height; y++) {
		for(int x = 0; x < i.width; x++) {
			datastream[dsp] |= i.data[dpos++] << shift;

			switch(h.depth) {
				default: assert(0);
				case 1: shift-= 1; break;
				case 2: shift-= 2; break;
				case 4: shift-= 4; break;
				case 8: shift-= 8; break;
			}

			justAdvanced = shift < 0;
			if(shift < 0) {
				dsp++;
				switch(h.depth) {
					default: assert(0);
					case 1: shift = 7; break;
					case 2: shift = 6; break;
					case 4: shift = 4; break;
					case 8: shift = 0; break;
				}
			}
		}
			if(!justAdvanced)
				dsp++;
			switch(h.depth) {
				default: assert(0);
				case 1: shift = 7; break;
				case 2: shift = 6; break;
				case 4: shift = 4; break;
				case 8: shift = 0; break;
			}

		}

		addImageDatastreamToPng(datastream, png);
	}

	return png;
}

/++
	Creates the [PNG] data structure out of a [TrueColorImage]. This implementation currently always make
	the file a true color with alpha png type.

	This is called by [writePng].
+/

PNG* pngFromImage(TrueColorImage i) {
	PngHeader h;
	h.width = i.width;
	h.height = i.height;
	// FIXME: optimize it if it is greyscale or doesn't use alpha alpha

	auto png = blankPNG(h);
	addImageDatastreamToPng(i.imageData.bytes, png);

	return png;
}

/*
void main(string[] args) {
	auto a = readPng(cast(ubyte[]) read(args[1]));
	auto f = getDatastream(a);

	foreach(i; f) {
		writef("%d ", i);
	}

	writefln("\n\n%d", f.length);
}
*/

/++
	Represents the PNG file's data. This struct is intended to be passed around by pointer.
+/
struct PNG {
	/++
		The length of the file.
	+/
	uint length;
	/++
		The PNG file magic number header. Please note the image data header is a IHDR chunk, not this (see [getHeader] for that). This just a static identifier

		History:
			Prior to October 10, 2022, this was called `header`.
	+/
	ubyte[8] magic;// = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; // this is the only valid value but idk if it is worth changing here since the ctor sets it regardless.
	/// ditto
	deprecated("use `magic` instead") alias header = magic;

	/++
		The array of chunks that make up the file contents. See [getChunkNullable], [getChunk], [insertChunk], and [replaceChunk] for functions to access and manipulate this array.
	+/
	Chunk[] chunks;

	/++
		Gets the chunk with the given name, or throws if it cannot be found.

		Returns:
			A non-null pointer to the chunk in the [chunks] array.
		Throws:
			an exception if the chunk can not be found. The type of this exception is subject to change at this time.
		See_Also:
			[getChunkNullable], which returns a null pointer instead of throwing.
	+/
	pure @trusted /* see note on getChunkNullable */
	Chunk* getChunk(string what) {
		foreach(ref c; chunks) {
			if(c.stype == what)
				return &c;
		}
		throw new Exception("no such chunk " ~ what);
	}

	/++
		Gets the chunk with the given name, return `null` if it is not found.

		See_Also:
			[getChunk], which throws if the chunk cannot be found.
	+/
	nothrow @nogc pure @trusted /* trusted because &c i know is referring to the dynamic array, not actually a local. That has lifetime at least as much of the parent PNG object. */
	Chunk* getChunkNullable(string what) {
		foreach(ref c; chunks) {
			if(c.stype == what)
				return &c;
		}
		return null;
	}

	/++
		Insert chunk before IDAT. PNG specs allows to drop all chunks after IDAT,
		so we have to insert our custom chunks right before it.
		Use `Chunk.create()` to create new chunk, and then `insertChunk()` to add it.
		Return `true` if we did replacement.
	+/
	nothrow pure @trusted /* the chunks.ptr here fails safe, but it does that for performance and again I control that data so can be reasonably assured */
	bool insertChunk (Chunk* chk, bool replaceExisting=false) {
		if (chk is null) return false; // just in case
		// use reversed loop, as "IDAT" is usually present, and it is usually the last,
		// so we will somewhat amortize painter's algorithm here.
		foreach_reverse (immutable idx, ref cc; chunks) {
			if (replaceExisting && cc.type == chk.type) {
				// replace existing chunk, the easiest case
				chunks[idx] = *chk;
				return true;
			}
			if (cc.stype == "IDAT") {
				// ok, insert it; and don't use phobos
				chunks.length += 1;
				foreach_reverse (immutable c; idx+1..chunks.length) chunks.ptr[c] = chunks.ptr[c-1];
				chunks.ptr[idx] = *chk;
				return false;
			}
		}
		chunks ~= *chk;
		return false;
	}

	/++
		Convenient wrapper for `insertChunk()`.
	+/
	nothrow pure @safe
	bool replaceChunk (Chunk* chk) { return insertChunk(chk, true); }
}

/++
	this is just like writePng(filename, pngFromImage(image)), but it manages
	its own memory and writes straight to the file instead of using intermediate buffers that might not get gc'd right
+/
void writeImageToPngFile(in char[] filename, TrueColorImage image) {
	PNG* png;
	ubyte[] com;
{
	import std.zlib;
	PngHeader h;
	h.width = image.width;
	h.height = image.height;
	png = blankPNG(h);

	size_t bytesPerLine = cast(size_t)h.width * 4;
	if(h.type == 3)
		bytesPerLine = cast(size_t)h.width * 8 / h.depth;
	Chunk dat;
	dat.type = ['I', 'D', 'A', 'T'];
	size_t pos = 0;

	auto compressor = new Compress();

	import core.stdc.stdlib;
	auto lineBuffer = (cast(ubyte*)malloc(1 + bytesPerLine))[0 .. 1+bytesPerLine];
	scope(exit) free(lineBuffer.ptr);

	while(pos+bytesPerLine <= image.imageData.bytes.length) {
		lineBuffer[0] = 0;
		lineBuffer[1..1+bytesPerLine] = image.imageData.bytes[pos.. pos+bytesPerLine];
		com ~= cast(ubyte[]) compressor.compress(lineBuffer);
		pos += bytesPerLine;
	}

	com ~= cast(ubyte[]) compressor.flush();

	assert(com.length <= uint.max);
	dat.size = cast(uint) com.length;
	dat.payload = com;
	dat.checksum = crc("IDAT", dat.payload);

	png.chunks ~= dat;

	Chunk c;

	c.size = 0;
	c.type = ['I', 'E', 'N', 'D'];
	c.checksum = crc("IEND", c.payload);

	png.chunks ~= c;
}
	assert(png !is null);

	import core.stdc.stdio;
	import std.string;
	FILE* fp = fopen(toStringz(filename), "wb");
	if(fp is null)
		throw new Exception("Couldn't open png file for writing.");
	scope(exit) fclose(fp);

	fwrite(png.magic.ptr, 1, 8, fp);
	foreach(c; png.chunks) {
		fputc((c.size & 0xff000000) >> 24, fp);
		fputc((c.size & 0x00ff0000) >> 16, fp);
		fputc((c.size & 0x0000ff00) >> 8, fp);
		fputc((c.size & 0x000000ff) >> 0, fp);

		fwrite(c.type.ptr, 1, 4, fp);
		fwrite(c.payload.ptr, 1, c.size, fp);

		fputc((c.checksum & 0xff000000) >> 24, fp);
		fputc((c.checksum & 0x00ff0000) >> 16, fp);
		fputc((c.checksum & 0x0000ff00) >> 8, fp);
		fputc((c.checksum & 0x000000ff) >> 0, fp);
	}

	{ import core.memory : GC; GC.free(com.ptr); } // there is a reference to this in the PNG struct, but it is going out of scope here too, so who cares
	// just wanna make sure this crap doesn't stick around
}

/++
	Turns a [PNG] structure into an array of bytes, ready to be written to a file.
+/
ubyte[] writePng(PNG* p) {
	ubyte[] a;
	if(p.length)
		a.length = p.length;
	else {
		a.length = 8;
		foreach(c; p.chunks)
			a.length += c.size + 12;
	}
	size_t pos;

	a[0..8] = p.magic[0..8];
	pos = 8;
	foreach(c; p.chunks) {
		a[pos++] = (c.size & 0xff000000) >> 24;
		a[pos++] = (c.size & 0x00ff0000) >> 16;
		a[pos++] = (c.size & 0x0000ff00) >> 8;
		a[pos++] = (c.size & 0x000000ff) >> 0;

		a[pos..pos+4] = c.type[0..4];
		pos += 4;
		a[pos..pos+c.size] = c.payload[0..c.size];
		pos += c.size;

		a[pos++] = (c.checksum & 0xff000000) >> 24;
		a[pos++] = (c.checksum & 0x00ff0000) >> 16;
		a[pos++] = (c.checksum & 0x0000ff00) >> 8;
		a[pos++] = (c.checksum & 0x000000ff) >> 0;
	}

	return a;
}

/++
	Opens a file and pulls the [PngHeader] out, leaving the rest of the data alone.

	This might be useful when you're only interested in getting a file's image size or
	other basic metainfo without loading the whole thing.
+/
PngHeader getHeaderFromFile(string filename) {
	import std.stdio;
	auto file = File(filename, "rb");
	ubyte[12] initialBuffer; // file header + size of first chunk (should be IHDR)
	auto data = file.rawRead(initialBuffer[]);
	if(data.length != 12)
		throw new Exception("couldn't get png file header off " ~ filename);

	if(data[0..8] != [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
		throw new Exception("file " ~ filename ~ " is not a png");

	size_t pos = 8;
	size_t size;
	size |= data[pos++] << 24;
	size |= data[pos++] << 16;
	size |= data[pos++] << 8;
	size |= data[pos++] << 0;

	size += 4; // chunk type
	size += 4; // checksum

	ubyte[] more;
	more.length = size;

	auto chunk = file.rawRead(more);
	if(chunk.length != size)
		throw new Exception("couldn't get png image header off " ~ filename);


	more = data ~ chunk;

	auto png = readPng(more);
	return getHeader(png);
}

/++
	Given an in-memory array of bytes from a PNG file, returns the parsed out [PNG] object.

	You might want the other [readPng] overload instead, which returns an even more processed [MemoryImage] object.
+/
PNG* readPng(in ubyte[] data) {
	auto p = new PNG;

	p.length = cast(int) data.length;
	p.magic[0..8] = data[0..8];

	if(p.magic != [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
		throw new Exception("not a png, header wrong");

	size_t pos = 8;

	while(pos < data.length && data.length - pos >= 12) {
		Chunk n;
		n.size |= data[pos++] << 24;
		n.size |= data[pos++] << 16;
		n.size |= data[pos++] << 8;
		n.size |= data[pos++] << 0;
		n.type[0..4] = data[pos..pos+4];
		pos += 4;
		n.payload.length = n.size;
		if(pos + n.size > data.length)
			throw new Exception(format("malformed png, chunk '%s' %d @ %d longer than data %d", n.type, n.size, pos, data.length));
		if(pos + n.size < pos)
			throw new Exception("uint overflow: chunk too large");
		n.payload[0..n.size] = data[pos..pos+n.size];
		pos += n.size;

		n.checksum |= data[pos++] << 24;
		n.checksum |= data[pos++] << 16;
		n.checksum |= data[pos++] << 8;
		n.checksum |= data[pos++] << 0;

		p.chunks ~= n;

		if(n.type == "IEND")
			break;
	}

	return p;
}

/++
	Creates a new [PNG] object from the given header parameters, ready to receive data.
+/
PNG* blankPNG(PngHeader h) {
	auto p = new PNG;
	p.magic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

	Chunk c;

	c.size = 13;
	c.type = ['I', 'H', 'D', 'R'];

	c.payload.length = 13;
	size_t pos = 0;

	c.payload[pos++] = h.width >> 24;
	c.payload[pos++] = (h.width >> 16) & 0xff;
	c.payload[pos++] = (h.width >> 8) & 0xff;
	c.payload[pos++] = h.width & 0xff;

	c.payload[pos++] = h.height >> 24;
	c.payload[pos++] = (h.height >> 16) & 0xff;
	c.payload[pos++] = (h.height >> 8) & 0xff;
	c.payload[pos++] = h.height & 0xff;

	c.payload[pos++] = h.depth;
	c.payload[pos++] = h.type;
	c.payload[pos++] = h.compressionMethod;
	c.payload[pos++] = h.filterMethod;
	c.payload[pos++] = h.interlaceMethod;


	c.checksum = crc("IHDR", c.payload);

	p.chunks ~= c;

	return p;
}

/+
	Implementation helper for creating png files.

	Its API is subject to change; it would be private except it might be useful to you.
+/
// should NOT have any idata already.
// FIXME: doesn't handle palettes
void addImageDatastreamToPng(const(ubyte)[] data, PNG* png, bool addIend = true) {
	// we need to go through the lines and add the filter byte
	// then compress it into an IDAT chunk
	// then add the IEND chunk
	import std.zlib;

	PngHeader h = getHeader(png);

	if(h.depth == 0)
		throw new Exception("depth of zero makes no sense");
	if(h.width == 0)
		throw new Exception("width zero?!!?!?!");

	int multiplier;
	size_t bytesPerLine;
	switch(h.type) {
		case 0:
			multiplier = 1;
		break;
		case 2:
			multiplier = 3;
		break;
		case 3:
			multiplier = 1;
		break;
		case 4:
			multiplier = 2;
		break;
		case 6:
			multiplier = 4;
		break;
		default: assert(0);
	}

	bytesPerLine = h.width * multiplier * h.depth / 8;
	if((h.width * multiplier * h.depth) % 8 != 0)
		bytesPerLine += 1;

	assert(bytesPerLine >= 1);
	Chunk dat;
	dat.type = ['I', 'D', 'A', 'T'];
	size_t pos = 0;

	const(ubyte)[] output;
	while(pos+bytesPerLine <= data.length) {
		output ~= 0;
		output ~= data[pos..pos+bytesPerLine];
		pos += bytesPerLine;
	}

	auto com = cast(ubyte[]) compress(output);
	dat.size = cast(int) com.length;
	dat.payload = com;
	dat.checksum = crc("IDAT", dat.payload);

	png.chunks ~= dat;

	if(addIend) {
		Chunk c;

		c.size = 0;
		c.type = ['I', 'E', 'N', 'D'];
		c.checksum = crc("IEND", c.payload);

		png.chunks ~= c;
	}

}

deprecated alias PngHeader PNGHeader;

// bKGD - palette entry for background or the RGB (16 bits each) for that. or 16 bits of grey

/+
	Uncompresses the raw datastream out of the file chunks, but does not continue processing it, so the scanlines are still filtered, etc.
+/
ubyte[] getDatastream(PNG* p) {
	import std.zlib;
	ubyte[] compressed;

	foreach(c; p.chunks) {
		if(c.stype != "IDAT")
			continue;
		compressed ~= c.payload;
	}

	return cast(ubyte[]) uncompress(compressed);
}

/+
	Gets a raw datastream out of a 8 bpp png. See also [getANDMask]
+/
// FIXME: Assuming 8 bits per pixel
ubyte[] getUnfilteredDatastream(PNG* p) {
	PngHeader h = getHeader(p);
	assert(h.filterMethod == 0);

	assert(h.type == 3); // FIXME
	assert(h.depth == 8); // FIXME

	ubyte[] data = getDatastream(p);
	ubyte[] ufdata = new ubyte[data.length - h.height];

	int bytesPerLine = cast(int) ufdata.length / h.height;

	int pos = 0, pos2 = 0;
	for(int a = 0; a < h.height; a++) {
		assert(data[pos2] == 0);
		ufdata[pos..pos+bytesPerLine] = data[pos2+1..pos2+bytesPerLine+1];
		pos+= bytesPerLine;
		pos2+= bytesPerLine + 1;
	}

	return ufdata;
}

/+
	Gets the unfiltered raw datastream for conversion to Windows ico files. See also [getANDMask] and [fetchPaletteWin32].
+/
ubyte[] getFlippedUnfilteredDatastream(PNG* p) {
	PngHeader h = getHeader(p);
	assert(h.filterMethod == 0);

	assert(h.type == 3); // FIXME
	assert(h.depth == 8 || h.depth == 4); // FIXME

	ubyte[] data = getDatastream(p);
	ubyte[] ufdata = new ubyte[data.length - h.height];

	int bytesPerLine = cast(int) ufdata.length / h.height;


	int pos = cast(int) ufdata.length - bytesPerLine, pos2 = 0;
	for(int a = 0; a < h.height; a++) {
		assert(data[pos2] == 0);
		ufdata[pos..pos+bytesPerLine] = data[pos2+1..pos2+bytesPerLine+1];
		pos-= bytesPerLine;
		pos2+= bytesPerLine + 1;
	}

	return ufdata;
}

ubyte getHighNybble(ubyte a) {
	return cast(ubyte)(a >> 4); // FIXME
}

ubyte getLowNybble(ubyte a) {
	return a & 0x0f;
}

/++
	Takes the transparency info and returns an AND mask suitable for use in a Windows ico
+/
ubyte[] getANDMask(PNG* p) {
	PngHeader h = getHeader(p);
	assert(h.filterMethod == 0);

	assert(h.type == 3); // FIXME
	assert(h.depth == 8 || h.depth == 4); // FIXME

	assert(h.width % 8 == 0); // might actually be %2

	ubyte[] data = getDatastream(p);
	ubyte[] ufdata = new ubyte[h.height*((((h.width+7)/8)+3)&~3)]; // gotta pad to DWORDs...

	Color[] colors = fetchPalette(p);

	int pos = 0, pos2 = (h.width/((h.depth == 8) ? 1 : 2)+1)*(h.height-1);
	bool bits = false;
	for(int a = 0; a < h.height; a++) {
		assert(data[pos2++] == 0);
		for(int b = 0; b < h.width; b++) {
			if(h.depth == 4) {
				ufdata[pos/8] |= ((colors[bits? getLowNybble(data[pos2]) : getHighNybble(data[pos2])].a <= 30) << (7-(pos%8)));
			} else
				ufdata[pos/8] |= ((colors[data[pos2]].a == 0) << (7-(pos%8)));
			pos++;
			if(h.depth == 4) {
				if(bits) {
					pos2++;
				}
				bits = !bits;
			} else
				pos2++;
		}

		int pad = 0;
		for(; pad < ((pos/8) % 4); pad++) {
			ufdata[pos/8] = 0;
			pos+=8;
		}
		if(h.depth == 4)
			pos2 -= h.width + 2;
		else
			pos2-= 2*(h.width) +2;
	}

	return ufdata;
}

// Done with assumption

/++
	Gets the parsed [PngHeader] data out of the [PNG] object.
+/
@nogc @safe pure
PngHeader getHeader(PNG* p) {
	PngHeader h;
	ubyte[] data = p.getChunkNullable("IHDR").payload;

	int pos = 0;

	h.width |= data[pos++] << 24;
	h.width |= data[pos++] << 16;
	h.width |= data[pos++] << 8;
	h.width |= data[pos++] << 0;

	h.height |= data[pos++] << 24;
	h.height |= data[pos++] << 16;
	h.height |= data[pos++] << 8;
	h.height |= data[pos++] << 0;

	h.depth = data[pos++];
	h.type = data[pos++];
	h.compressionMethod = data[pos++];
	h.filterMethod = data[pos++];
	h.interlaceMethod = data[pos++];

	return h;
}

/*
struct Color {
	ubyte r;
	ubyte g;
	ubyte b;
	ubyte a;
}
*/

/+
class Image {
	Color[][] trueColorData;
	ubyte[] indexData;

	Color[] palette;

	uint width;
	uint height;

	this(uint w, uint h) {}
}

Image fromPNG(PNG* p) {

}

PNG* toPNG(Image i) {

}
+/		struct RGBQUAD {
			ubyte rgbBlue;
			ubyte rgbGreen;
			ubyte rgbRed;
			ubyte rgbReserved;
		}

/+
	Gets the palette out of the format Windows expects for bmp and ico files.

	See also getANDMask
+/
RGBQUAD[] fetchPaletteWin32(PNG* p) {
	RGBQUAD[] colors;

	auto palette = p.getChunk("PLTE");

	colors.length = (palette.size) / 3;

	for(int i = 0; i < colors.length; i++) {
		colors[i].rgbRed = palette.payload[i*3+0];
		colors[i].rgbGreen = palette.payload[i*3+1];
		colors[i].rgbBlue = palette.payload[i*3+2];
		colors[i].rgbReserved = 0;
	}

	return colors;

}

/++
	Extracts the palette chunk from a PNG object as an array of RGBA quads.

	See_Also:
		[replacePalette]
+/
Color[] fetchPalette(PNG* p) {
	Color[] colors;

	auto header = getHeader(p);
	if(header.type == 0) { // greyscale
		colors.length = 256;
		foreach(i; 0..256)
			colors[i] = Color(cast(ubyte) i, cast(ubyte) i, cast(ubyte) i);
		return colors;
	}

	// assuming this is indexed
	assert(header.type == 3);

	auto palette = p.getChunk("PLTE");

	Chunk* alpha = p.getChunkNullable("tRNS");

	colors.length = palette.size / 3;

	for(int i = 0; i < colors.length; i++) {
		colors[i].r = palette.payload[i*3+0];
		colors[i].g = palette.payload[i*3+1];
		colors[i].b = palette.payload[i*3+2];
		if(alpha !is null && i < alpha.size)
			colors[i].a = alpha.payload[i];
		else
			colors[i].a = 255;

		//writefln("%2d: %3d %3d %3d %3d", i, colors[i].r, colors[i].g, colors[i].b, colors[i].a);
	}

	return colors;
}

/++
	Replaces the palette data in a [PNG] object.

	See_Also:
		[fetchPalette]
+/
void replacePalette(PNG* p, Color[] colors) {
	auto palette = p.getChunk("PLTE");
	auto alpha = p.getChunkNullable("tRNS");

	//import std.string;
	//assert(0, format("%s %s", colors.length, alpha.size));
	//assert(colors.length == alpha.size);
	if(alpha) {
		alpha.size = cast(int) colors.length;
		alpha.payload.length = colors.length; // we make sure there's room for our simple method below
	}
	p.length = 0; // so write will recalculate

	for(int i = 0; i < colors.length; i++) {
		palette.payload[i*3+0] = colors[i].r;
		palette.payload[i*3+1] = colors[i].g;
		palette.payload[i*3+2] = colors[i].b;
		if(alpha)
			alpha.payload[i] = colors[i].a;
	}

	palette.checksum = crc("PLTE", palette.payload);
	if(alpha)
		alpha.checksum = crc("tRNS", alpha.payload);
}

@safe nothrow pure @nogc
uint update_crc(in uint crc, in ubyte[] buf){
	static const uint[256] crc_table = [0, 1996959894, 3993919788, 2567524794, 124634137, 1886057615, 3915621685, 2657392035, 249268274, 2044508324, 3772115230, 2547177864, 162941995, 2125561021, 3887607047, 2428444049, 498536548, 1789927666, 4089016648, 2227061214, 450548861, 1843258603, 4107580753, 2211677639, 325883990, 1684777152, 4251122042, 2321926636, 335633487, 1661365465, 4195302755, 2366115317, 997073096, 1281953886, 3579855332, 2724688242, 1006888145, 1258607687, 3524101629, 2768942443, 901097722, 1119000684, 3686517206, 2898065728, 853044451, 1172266101, 3705015759, 2882616665, 651767980, 1373503546, 3369554304, 3218104598, 565507253, 1454621731, 3485111705, 3099436303, 671266974, 1594198024, 3322730930, 2970347812, 795835527, 1483230225, 3244367275, 3060149565, 1994146192, 31158534, 2563907772, 4023717930, 1907459465, 112637215, 2680153253, 3904427059, 2013776290, 251722036, 2517215374, 3775830040, 2137656763, 141376813, 2439277719, 3865271297, 1802195444, 476864866, 2238001368, 4066508878, 1812370925, 453092731, 2181625025, 4111451223, 1706088902, 314042704, 2344532202, 4240017532, 1658658271, 366619977, 2362670323, 4224994405, 1303535960, 984961486, 2747007092, 3569037538, 1256170817, 1037604311, 2765210733, 3554079995, 1131014506, 879679996, 2909243462, 3663771856, 1141124467, 855842277, 2852801631, 3708648649, 1342533948, 654459306, 3188396048, 3373015174, 1466479909, 544179635, 3110523913, 3462522015, 1591671054, 702138776, 2966460450, 3352799412, 1504918807, 783551873, 3082640443, 3233442989, 3988292384, 2596254646, 62317068, 1957810842, 3939845945, 2647816111, 81470997, 1943803523, 3814918930, 2489596804, 225274430, 2053790376, 3826175755, 2466906013, 167816743, 2097651377, 4027552580, 2265490386, 503444072, 1762050814, 4150417245, 2154129355, 426522225, 1852507879, 4275313526, 2312317920, 282753626, 1742555852, 4189708143, 2394877945, 397917763, 1622183637, 3604390888, 2714866558, 953729732, 1340076626, 3518719985, 2797360999, 1068828381, 1219638859, 3624741850, 2936675148, 906185462, 1090812512, 3747672003, 2825379669, 829329135, 1181335161, 3412177804, 3160834842, 628085408, 1382605366, 3423369109, 3138078467, 570562233, 1426400815, 3317316542, 2998733608, 733239954, 1555261956, 3268935591, 3050360625, 752459403, 1541320221, 2607071920, 3965973030, 1969922972, 40735498, 2617837225, 3943577151, 1913087877, 83908371, 2512341634, 3803740692, 2075208622, 213261112, 2463272603, 3855990285, 2094854071, 198958881, 2262029012, 4057260610, 1759359992, 534414190, 2176718541, 4139329115, 1873836001, 414664567, 2282248934, 4279200368, 1711684554, 285281116, 2405801727, 4167216745, 1634467795, 376229701, 2685067896, 3608007406, 1308918612, 956543938, 2808555105, 3495958263, 1231636301, 1047427035, 2932959818, 3654703836, 1088359270, 936918000, 2847714899, 3736837829, 1202900863, 817233897, 3183342108, 3401237130, 1404277552, 615818150, 3134207493, 3453421203, 1423857449, 601450431, 3009837614, 3294710456, 1567103746, 711928724, 3020668471, 3272380065, 1510334235, 755167117];

	uint c = crc;

	foreach(b; buf)
		c = crc_table[(c ^ b) & 0xff] ^ (c >> 8);

	return c;
}

/+
	Figures out the crc for a chunk. Used internally.

	lol is just the chunk name
+/
uint crc(in string lol, in ubyte[] buf){
	uint c = update_crc(0xffffffffL, cast(ubyte[]) lol);
	return update_crc(c, buf) ^ 0xffffffffL;
}


/* former module arsd.lazypng follows */

// this is like png.d but all range based so more complicated...
// and I don't remember how to actually use it.

// some day I'll prolly merge it with png.d but for now just throwing it up there

//module arsd.lazypng;

//import arsd.color;

//import std.stdio;

import std.range;
import std.traits;
import std.exception;
import std.string;
//import std.conv;

/*
struct Color {
	ubyte r;
	ubyte g;
	ubyte b;
	ubyte a;

	string toString() {
		return format("#%2x%2x%2x %2x", r, g, b, a);
	}
}
*/

//import arsd.simpledisplay;

struct RgbaScanline {
	Color[] pixels;
}


// lazy range to convert some png scanlines into greyscale. part of an experiment i didn't do much with but still use sometimes.
auto convertToGreyscale(ImageLines)(ImageLines lines)
	if(isInputRange!ImageLines && is(ElementType!ImageLines == RgbaScanline))
{
	struct GreyscaleLines {
		ImageLines lines;
		bool isEmpty;
		this(ImageLines lines) {
			this.lines = lines;
			if(!empty())
				popFront(); // prime
		}

		int length() {
			return lines.length;
		}

		bool empty() {
			return isEmpty;
		}

		RgbaScanline current;
		RgbaScanline front() {
			return current;
		}

		void popFront() {
			if(lines.empty()) {
				isEmpty = true;
				return;
			}
			auto old = lines.front();
			current.pixels.length = old.pixels.length;
			foreach(i, c; old.pixels) {
				ubyte v = cast(ubyte) (
					cast(int) c.r * 0.30 +
					cast(int) c.g * 0.59 +
					cast(int) c.b * 0.11);
				current.pixels[i] = Color(v, v, v, c.a);
			}
			lines.popFront;
		}
	}

	return GreyscaleLines(lines);
}




/// Lazily breaks the buffered input range into
/// png chunks, as defined in the PNG spec
///
/// Note: bufferedInputRange is defined in this file too.
LazyPngChunks!(Range) readPngChunks(Range)(Range r)
	if(isBufferedInputRange!(Range) && is(ElementType!(Range) == ubyte[]))
{
	// First, we need to check the header
	// Then we'll lazily pull the chunks

	while(r.front.length < 8) {
		enforce(!r.empty(), "This isn't big enough to be a PNG file");
		r.appendToFront();
	}

	enforce(r.front[0..8] == PNG_MAGIC_NUMBER,
		"The file's magic number doesn't look like PNG");

	r.consumeFromFront(8);

	return LazyPngChunks!Range(r);
}

/// Same as above, but takes a regular input range instead of a buffered one.
/// Provided for easier compatibility with standard input ranges
/// (for example, std.stdio.File.byChunk)
auto readPngChunks(Range)(Range r)
	if(!isBufferedInputRange!(Range) && isInputRange!(Range))
{
	return readPngChunks(BufferedInputRange!Range(r));
}

/// Given an input range of bytes, return a lazy PNG file
auto pngFromBytes(Range)(Range r)
	if(isInputRange!(Range) && is(ElementType!Range == ubyte[]))
{
	auto chunks = readPngChunks(r);
	auto file = LazyPngFile!(typeof(chunks))(chunks);

	return file;
}

/// See: [readPngChunks]
struct LazyPngChunks(T)
	if(isBufferedInputRange!(T) && is(ElementType!T == ubyte[]))
{
	T bytes;
	Chunk current;

	this(T range) {
		bytes = range;
		popFront(); // priming it
	}

	Chunk front() {
		return current;
	}

	bool empty() {
		return (bytes.front.length == 0 && bytes.empty);
	}

	void popFront() {
		enforce(!empty());

		while(bytes.front().length < 4) {
			enforce(!bytes.empty,
				format("Malformed PNG file - chunk size too short (%s < 4)",
					bytes.front().length));
			bytes.appendToFront();
		}

		Chunk n;
		n.size |= bytes.front()[0] << 24;
		n.size |= bytes.front()[1] << 16;
		n.size |= bytes.front()[2] << 8;
		n.size |= bytes.front()[3] << 0;

		bytes.consumeFromFront(4);

		while(bytes.front().length < n.size + 8) {
			enforce(!bytes.empty,
				format("Malformed PNG file - chunk too short (%s < %s)",
					bytes.front.length, n.size));
			bytes.appendToFront();
		}
		n.type[0 .. 4] = bytes.front()[0 .. 4];
		bytes.consumeFromFront(4);

		n.payload.length = n.size;
		n.payload[0 .. n.size] = bytes.front()[0 .. n.size];
		bytes.consumeFromFront(n.size);

		n.checksum |= bytes.front()[0] << 24;
		n.checksum |= bytes.front()[1] << 16;
		n.checksum |= bytes.front()[2] << 8;
		n.checksum |= bytes.front()[3] << 0;

		bytes.consumeFromFront(4);

		enforce(n.checksum == crcPng(n.stype, n.payload), "Chunk checksum didn't match");

		current = n;
	}
}

/// Lazily reads out basic info from a png (header, palette, image data)
/// It will only allocate memory to read a palette, and only copies on
/// the header and the palette. It ignores everything else.
///
/// FIXME: it doesn't handle interlaced files.
struct LazyPngFile(LazyPngChunksProvider)
	if(isInputRange!(LazyPngChunksProvider) &&
		is(ElementType!(LazyPngChunksProvider) == Chunk))
{
	LazyPngChunksProvider chunks;

	this(LazyPngChunksProvider chunks) {
		enforce(!chunks.empty(), "There are no chunks in this png");

		header = PngHeader.fromChunk(chunks.front());
		chunks.popFront();

		// And now, find the datastream so we're primed for lazy
		// reading, saving the palette and transparency info, if
		// present

		chunkLoop:
		while(!chunks.empty()) {
			auto chunk = chunks.front();
			switch(chunks.front.stype) {
				case "PLTE":
					// if it is in color, palettes are
					// always stored as 8 bit per channel
					// RGB triplets Alpha is stored elsewhere.

					// FIXME: doesn't do greyscale palettes!

					enforce(chunk.size % 3 == 0);
					palette.length = chunk.size / 3;

					auto offset = 0;
					foreach(i; 0 .. palette.length) {
						palette[i] = Color(
							chunk.payload[offset+0],
							chunk.payload[offset+1],
							chunk.payload[offset+2],
							255);
						offset += 3;
					}
				break;
				case "tRNS":
					// 8 bit channel in same order as
					// palette

					if(chunk.size > palette.length)
						palette.length = chunk.size;

					foreach(i, a; chunk.payload)
						palette[i].a = a;
				break;
				case "IDAT":
					// leave the datastream for later
					break chunkLoop;
				default:
					// ignore chunks we don't care about
			}
			chunks.popFront();
		}

		this.chunks = chunks;
		enforce(!chunks.empty() && chunks.front().stype == "IDAT",
			"Malformed PNG file - no image data is present");
	}

	/// Lazily reads and decompresses the image datastream, returning chunkSize bytes of
	/// it per front. It does *not* change anything, so the filter byte is still there.
	///
	/// If chunkSize == 0, it automatically calculates chunk size to give you data by line.
	auto rawDatastreamByChunk(int chunkSize = 0) {
		assert(chunks.front().stype == "IDAT");

		if(chunkSize == 0)
			chunkSize = bytesPerLine();

		struct DatastreamByChunk(T) {
			private import etc.c.zlib;
			z_stream* zs; // we have to malloc this too, as dmd can move the struct, and zlib 1.2.10 is intolerant to that
			int chunkSize;
			int bufpos;
			int plpos; // bytes eaten in current chunk payload
			T chunks;
			bool eoz;

			this(int cs, T chunks) {
				import core.stdc.stdlib : malloc;
				import core.stdc.string : memset;
				this.chunkSize = cs;
				this.chunks = chunks;
				assert(chunkSize > 0);
				buffer = (cast(ubyte*)malloc(chunkSize))[0..chunkSize];
				pkbuf = (cast(ubyte*)malloc(32768))[0..32768]; // arbitrary number
				zs = cast(z_stream*)malloc(z_stream.sizeof);
				memset(zs, 0, z_stream.sizeof);
				zs.avail_in = 0;
				zs.avail_out = 0;
				auto res = inflateInit2(zs, 15);
				assert(res == Z_OK);
				popFront(); // priming
			}

			~this () {
				version(arsdpng_debug) { import core.stdc.stdio : printf; printf("destroying lazy PNG reader...\n"); }
				import core.stdc.stdlib : free;
				if (zs !is null) { inflateEnd(zs); free(zs); }
				if (pkbuf.ptr !is null) free(pkbuf.ptr);
				if (buffer.ptr !is null) free(buffer.ptr);
			}

			@disable this (this); // no copies!

			ubyte[] front () { return (bufpos > 0 ? buffer[0..bufpos] : null); }

			ubyte[] buffer;
			ubyte[] pkbuf; // we will keep some packed data here in case payload moves, lol

			void popFront () {
				bufpos = 0;
				while (plpos != plpos.max && bufpos < chunkSize) {
					// do we have some bytes in zstream?
					if (zs.avail_in > 0) {
						// just unpack
						zs.next_out = cast(typeof(zs.next_out))(buffer.ptr+bufpos);
						int rd = chunkSize-bufpos;
						zs.avail_out = rd;
						auto err = inflate(zs, Z_SYNC_FLUSH);
						if (err != Z_STREAM_END && err != Z_OK) throw new Exception("PNG unpack error");
						if (err == Z_STREAM_END) {
							if(zs.avail_in != 0) {
								// this thing is malformed..
								// libpng would warn here "libpng warning: IDAT: Extra compressed data"
								// i used to just throw with the assertion on the next line
								// but now just gonna discard the extra data to be a bit more permissive
								zs.avail_in = 0;
							}
							assert(zs.avail_in == 0);
							eoz = true;
						}
						bufpos += rd-zs.avail_out;
						continue;
					}
					// no more zstream bytes; do we have something in current chunk?
					if (plpos == plpos.max || plpos >= chunks.front.payload.length) {
						// current chunk is complete, do we have more chunks?
						if (chunks.front.stype != "IDAT") break; // this chunk is not IDAT, that means that... alas
						chunks.popFront(); // remove current IDAT
						plpos = 0;
						if (chunks.empty || chunks.front.stype != "IDAT") plpos = plpos.max; // special value
						continue;
					}
					if (plpos < chunks.front.payload.length) {
						// current chunk is not complete, get some more bytes from it
						int rd = cast(int)(chunks.front.payload.length-plpos <= pkbuf.length ? chunks.front.payload.length-plpos : pkbuf.length);
						assert(rd > 0);
						pkbuf[0..rd] = chunks.front.payload[plpos..plpos+rd];
						plpos += rd;
						if (eoz) {
							// we did hit end-of-stream, reinit zlib (well, well, i know that we can reset it... meh)
							inflateEnd(zs);
							zs.avail_in = 0;
							zs.avail_out = 0;
							auto res = inflateInit2(zs, 15);
							assert(res == Z_OK);
							eoz = false;
						}
						// setup read pointer
						zs.next_in = cast(typeof(zs.next_in))pkbuf.ptr;
						zs.avail_in = cast(uint)rd;
						continue;
					}
					assert(0, "wtf?! we should not be here!");
				}
			}

			bool empty () { return (bufpos == 0); }
		}

		return DatastreamByChunk!(typeof(chunks))(chunkSize, chunks);
	}

	// FIXME: no longer compiles
	version(none)
	auto byRgbaScanline() {
		static struct ByRgbaScanline {
			ReturnType!(rawDatastreamByChunk) datastream;
			RgbaScanline current;
			PngHeader header;
			int bpp;
			Color[] palette;

			bool isEmpty = false;

			bool empty() {
				return isEmpty;
			}

			@property int length() {
				return header.height;
			}

			// This is needed for the filter algorithms
			immutable(ubyte)[] previousLine;

			// FIXME: I think my range logic got screwed somewhere
			// in the stack... this is messed up.
			void popFront() {
				assert(!empty());
				if(datastream.empty()) {
					isEmpty = true;
					return;
				}
				current.pixels.length = header.width;

				// ensure it is primed
				if(datastream.front.length == 0)
					datastream.popFront;

				auto rawData = datastream.front();
				auto filter = rawData[0];
				auto data = unfilter(filter, rawData[1 .. $], previousLine, bpp);

				if(data.length == 0) {
					isEmpty = true;
					return;
				}

				assert(data.length);

				previousLine = data;

				// FIXME: if it's rgba, this could probably be faster
				assert(header.depth == 8,
					"Sorry, depths other than 8 aren't implemented yet.");

				auto offset = 0;
				foreach(i; 0 .. header.width) {
					switch(header.type) {
						case 0: // greyscale
						case 4: // grey with alpha
							auto value = data[offset++];
							current.pixels[i] = Color(
								value,
								value,
								value,
								(header.type == 4)
									? data[offset++] : 255
							);
						break;
						case 3: // indexed
							current.pixels[i] = palette[data[offset++]];
						break;
						case 2: // truecolor
						case 6: // true with alpha
							current.pixels[i] = Color(
								data[offset++],
								data[offset++],
								data[offset++],
								(header.type == 6)
									? data[offset++] : 255
							);
						break;
						default:
							throw new Exception("invalid png file");
					}
				}

				assert(offset == data.length);
				if(!datastream.empty())
					datastream.popFront();
			}

			RgbaScanline front() {
				return current;
			}
		}

		assert(chunks.front.stype == "IDAT");

		ByRgbaScanline range;
		range.header = header;
		range.bpp = bytesPerPixel;
		range.palette = palette;
		range.datastream = rawDatastreamByChunk(bytesPerLine());
		range.popFront();

		return range;
	}

	int bytesPerPixel() {
		return .bytesPerPixel(header);
	}

	int bytesPerLine() {
		return .bytesPerLineOfPng(header.depth, header.type, header.width);
	}

	PngHeader header;
	Color[] palette;
}

// FIXME: doesn't handle interlacing... I think
// note it returns the length including the filter byte!!
@nogc @safe pure nothrow
int bytesPerLineOfPng(ubyte depth, ubyte type, uint width) {
	immutable bitsPerChannel = depth;

	int bitsPerPixel = bitsPerChannel;
	if(type & 2 && !(type & 1)) // in color, but no palette
		bitsPerPixel *= 3;
	if(type & 4) // has alpha channel
		bitsPerPixel += bitsPerChannel;

	immutable int sizeInBits = width * bitsPerPixel;

	// need to round up to the nearest byte
	int sizeInBytes = (sizeInBits + 7) / 8;

	return sizeInBytes + 1; // the +1 is for the filter byte that precedes all lines
}

/**************************************************
 * Buffered input range - generic, non-image code
***************************************************/

/// Is the given range a buffered input range? That is, an input range
/// that also provides consumeFromFront(int) and appendToFront()
///
/// THIS IS BAD CODE. I wrote it before understanding how ranges are supposed to work.
template isBufferedInputRange(R) {
	enum bool isBufferedInputRange =
		isInputRange!(R) && is(typeof(
	{
		R r;
		r.consumeFromFront(0);
		r.appendToFront();
	}()));
}

/// Allows appending to front on a regular input range, if that range is
/// an array. It appends to the array rather than creating an array of
/// arrays; it's meant to make the illusion of one continuous front rather
/// than simply adding capability to walk backward to an existing input range.
///
/// I think something like this should be standard; I find File.byChunk
/// to be almost useless without this capability.

// FIXME: what if Range is actually an array itself? We should just use
// slices right into it... I guess maybe r.front() would be the whole
// thing in that case though, so we would indeed be slicing in right now.
// Gotta check it though.
struct BufferedInputRange(Range)
	if(isInputRange!(Range) && isArray!(ElementType!(Range)))
{
	private Range underlyingRange;
	private ElementType!(Range) buffer;

	/// Creates a buffer for the given range. You probably shouldn't
	/// keep using the underlying range directly.
	///
	/// It assumes the underlying range has already been primed.
	this(Range r) {
		underlyingRange = r;
		// Is this really correct? Want to make sure r.front
		// is valid but it doesn't necessarily need to have
		// more elements...
		enforce(!r.empty());

		buffer = r.front();
		usingUnderlyingBuffer = true;
	}

	/// Forwards to the underlying range's empty function
	bool empty() {
		return underlyingRange.empty();
	}

	/// Returns the current buffer
	ElementType!(Range) front() {
		return buffer;
	}

	// actually, not terribly useful IMO. appendToFront calls it
	// implicitly when necessary

	/// Discard the current buffer and get the next item off the
	/// underlying range. Be sure to call at least once to prime
	/// the range (after checking if it is empty, of course)
	void popFront() {
		enforce(!empty());
		underlyingRange.popFront();
		buffer = underlyingRange.front();
		usingUnderlyingBuffer = true;
	}

	bool usingUnderlyingBuffer = false;

	/// Remove the first count items from the buffer
	void consumeFromFront(int count) {
		buffer = buffer[count .. $];
	}

	/// Append the next item available on the underlying range to
	/// our buffer.
	void appendToFront() {
		if(buffer.length == 0) {
			// may let us reuse the underlying range's buffer,
			// hopefully avoiding an extra allocation
			popFront();
		} else {
			enforce(!underlyingRange.empty());

			// need to make sure underlyingRange.popFront doesn't overwrite any
			// of our buffer...
			if(usingUnderlyingBuffer) {
				buffer = buffer.dup;
				usingUnderlyingBuffer = false;
			}

			underlyingRange.popFront();

			buffer ~= underlyingRange.front();
		}
	}
}

/**************************************************
 * Lower level implementations of image formats.
 * and associated helper functions.
 *
 * Related to the module, but not particularly
 * interesting, so it's at the bottom.
***************************************************/


/* PNG file format implementation */

//import std.zlib;
import std.math;

/// All PNG files are supposed to open with these bytes according to the spec
static immutable(ubyte[]) PNG_MAGIC_NUMBER = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/// A PNG file consists of the magic number then a stream of chunks. This
/// struct represents those chunks.
struct Chunk {
	uint size;
	ubyte[4] type;
	ubyte[] payload;
	uint checksum;

	/// returns the type as a string for easier comparison with literals
	@nogc @safe nothrow pure
	const(char)[] stype() return const {
		return cast(const(char)[]) type;
	}

	@trusted nothrow pure /* trusted because of the cast of name to ubyte. It is copied into a new buffer anyway though so obviously harmless. */
	static Chunk* create(string type, ubyte[] payload)
		in {
			assert(type.length == 4);
		}
	do {
		Chunk* c = new Chunk;
		c.size = cast(int) payload.length;
		c.type[] = (cast(ubyte[]) type)[];
		c.payload = payload;

		c.checksum = crcPng(type, payload);

		return c;
	}

	/// Puts it into the format for outputting to a file
	@safe nothrow pure
	ubyte[] toArray() {
		ubyte[] a;
		a.length = size + 12;

		int pos = 0;

		a[pos++] = (size & 0xff000000) >> 24;
		a[pos++] = (size & 0x00ff0000) >> 16;
		a[pos++] = (size & 0x0000ff00) >> 8;
		a[pos++] = (size & 0x000000ff) >> 0;

		a[pos .. pos + 4] = type[0 .. 4];
		pos += 4;

		a[pos .. pos + size] = payload[0 .. size];

		pos += size;

		assert(checksum);

		a[pos++] = (checksum & 0xff000000) >> 24;
		a[pos++] = (checksum & 0x00ff0000) >> 16;
		a[pos++] = (checksum & 0x0000ff00) >> 8;
		a[pos++] = (checksum & 0x000000ff) >> 0;

		return a;
	}
}

/// The first chunk in a PNG file is a header that contains this info
struct PngHeader {
	/// Width of the image, in pixels.
	uint width;

	/// Height of the image, in pixels.
	uint height;

	/**
		This is bits per channel - per color for truecolor or grey
		and per pixel for palette.

		Indexed ones can have depth of 1,2,4, or 8,

		Greyscale can be 1,2,4,8,16

		Everything else must be 8 or 16.
	*/
	ubyte depth = 8;

	/** Types from the PNG spec:
		0 - greyscale
		2 - truecolor
		3 - indexed color
		4 - grey with alpha
		6 - true with alpha

		1, 5, and 7 are invalid.

		There's a kind of bitmask going on here:
			If type&1, it has a palette.
			If type&2, it is in color.
			If type&4, it has an alpha channel in the datastream.
	*/
	ubyte type = 6;

	ubyte compressionMethod = 0; /// should be zero
	ubyte filterMethod = 0; /// should be zero
	/// 0 is non interlaced, 1 if Adam7. No more are defined in the spec
	ubyte interlaceMethod = 0;

	pure @safe // @nogc with -dip1008 too......
	static PngHeader fromChunk(in Chunk c) {
		if(c.stype != "IHDR")
			throw new Exception("The chunk is not an image header");

		PngHeader h;
		auto data = c.payload;
		int pos = 0;

		if(data.length != 13)
			throw new Exception("Malformed PNG file - the IHDR is the wrong size");

		h.width |= data[pos++] << 24;
		h.width |= data[pos++] << 16;
		h.width |= data[pos++] << 8;
		h.width |= data[pos++] << 0;

		h.height |= data[pos++] << 24;
		h.height |= data[pos++] << 16;
		h.height |= data[pos++] << 8;
		h.height |= data[pos++] << 0;

		h.depth = data[pos++];
		h.type = data[pos++];
		h.compressionMethod = data[pos++];
		h.filterMethod = data[pos++];
		h.interlaceMethod = data[pos++];

		return h;
	}

	Chunk* toChunk() {
		ubyte[] data;
		data.length = 13;
		int pos = 0;

		data[pos++] = width >> 24;
		data[pos++] = (width >> 16) & 0xff;
		data[pos++] = (width >> 8) & 0xff;
		data[pos++] = width & 0xff;

		data[pos++] = height >> 24;
		data[pos++] = (height >> 16) & 0xff;
		data[pos++] = (height >> 8) & 0xff;
		data[pos++] = height & 0xff;

		data[pos++] = depth;
		data[pos++] = type;
		data[pos++] = compressionMethod;
		data[pos++] = filterMethod;
		data[pos++] = interlaceMethod;

		assert(pos == 13);

		return Chunk.create("IHDR", data);
	}
}

/// turns a range of png scanlines into a png file in the output range. really weird
void writePngLazy(OutputRange, InputRange)(ref OutputRange where, InputRange image)
	if(
		isOutputRange!(OutputRange, ubyte[]) &&
		isInputRange!(InputRange) &&
		is(ElementType!InputRange == RgbaScanline))
{
	import std.zlib;
	where.put(PNG_MAGIC_NUMBER);
	PngHeader header;

	assert(!image.empty());

	// using the default values for header here... FIXME not super clear

	header.width = image.front.pixels.length;
	header.height = image.length;

	enforce(header.width > 0, "Image width <= 0");
	enforce(header.height > 0, "Image height <= 0");

	where.put(header.toChunk().toArray());

	auto compressor = new std.zlib.Compress();
	const(void)[] compressedData;
	int cnt;
	foreach(line; image) {
		// YOU'VE GOT TO BE FUCKING KIDDING ME!
		// I have to /cast/ to void[]!??!?

		ubyte[] data;
		data.length = 1 + header.width * 4;
		data[0] = 0; // filter type
		int offset = 1;
		foreach(pixel; line.pixels) {
			data[offset++] = pixel.r;
			data[offset++] = pixel.g;
			data[offset++] = pixel.b;
			data[offset++] = pixel.a;
		}

		compressedData ~= compressor.compress(cast(void[])
			data);
		if(compressedData.length > 2_000) {
			where.put(Chunk.create("IDAT", cast(ubyte[])
				compressedData).toArray());
			compressedData = null;
		}

		cnt++;
	}

	assert(cnt == header.height, format("Got %d lines instead of %d", cnt, header.height));

	compressedData ~= compressor.flush();
	if(compressedData.length)
		where.put(Chunk.create("IDAT", cast(ubyte[])
			compressedData).toArray());

	where.put(Chunk.create("IEND", null).toArray());
}

// bKGD - palette entry for background or the RGB (16 bits each) for that. or 16 bits of grey

@trusted nothrow pure @nogc /* trusted because of the cast from char to ubyte */
uint crcPng(in char[] chunkName, in ubyte[] buf){
	uint c = update_crc(0xffffffffL, cast(ubyte[]) chunkName);
	return update_crc(c, buf) ^ 0xffffffffL;
}

/++
	Png files apply a filter to each line in the datastream, hoping to aid in compression. This undoes that as you load.
+/
immutable(ubyte)[] unfilter(ubyte filterType, in ubyte[] data, in ubyte[] previousLine, int bpp) {
	// Note: the overflow arithmetic on the ubytes in here is intentional
	switch(filterType) {
		case 0:
			return data.idup; // FIXME is copying really necessary?
		case 1:
			auto arr = data.dup;
			// first byte gets zero added to it so nothing special
			foreach(i; bpp .. arr.length) {
				arr[i] += arr[i - bpp];
			}

			return assumeUnique(arr);
		case 2:
			auto arr = data.dup;
			if(previousLine.length)
			foreach(i; 0 .. arr.length) {
				arr[i] += previousLine[i];
			}

			return assumeUnique(arr);
		case 3:
			auto arr = data.dup;
			foreach(i; 0 .. arr.length) {
				auto left = i < bpp ? 0 : arr[i - bpp];
				auto above = previousLine.length ? previousLine[i] : 0;

				arr[i] += cast(ubyte) ((left + above) / 2);
			}

			return assumeUnique(arr);
		case 4:
			auto arr = data.dup;
			foreach(i; 0 .. arr.length) {
				ubyte prev   = i < bpp ? 0 : arr[i - bpp];
				ubyte prevLL = i < bpp ? 0 : (i < previousLine.length ? previousLine[i - bpp] : 0);

				arr[i] += PaethPredictor(prev, (i < previousLine.length ? previousLine[i] : 0), prevLL);
			}

			return assumeUnique(arr);
		default:
			throw new Exception("invalid PNG file, bad filter type");
	}
}

ubyte PaethPredictor(ubyte a, ubyte b, ubyte c) {
	int p = cast(int) a + b - c;
	auto pa = abs(p - a);
	auto pb = abs(p - b);
	auto pc = abs(p - c);

	if(pa <= pb && pa <= pc)
		return a;
	if(pb <= pc)
		return b;
	return c;
}

///
int bytesPerPixel(PngHeader header) {
	immutable bitsPerChannel = header.depth;

	int bitsPerPixel = bitsPerChannel;
	if(header.type & 2 && !(header.type & 1)) // in color, but no palette
		bitsPerPixel *= 3;
	if(header.type & 4) // has alpha channel
		bitsPerPixel += bitsPerChannel;

	return (bitsPerPixel + 7) / 8;
}
