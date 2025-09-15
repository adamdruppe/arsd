/++
	Basic .bmp file format implementation for [arsd.color.MemoryImage].
	Compare with [arsd.png] basic functionality.
+/
module arsd.bmp;

import arsd.color;

//version = arsd_debug_bitmap_loader;


/// Reads a .bmp file from the given `filename`
MemoryImage readBmp(string filename) {
	import core.stdc.stdio;

	FILE* fp = fopen((filename ~ "\0").ptr, "rb".ptr);
	if(fp is null)
		throw new Exception("can't open save file");
	scope(exit) fclose(fp);

	void specialFread(void* tgt, size_t size) {
		version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("ofs: 0x%08x\n", cast(uint)ftell(fp)); }
		fread(tgt, size, 1, fp);
	}

	return readBmpIndirect(&specialFread);
}

/++
	Reads a bitmap out of an in-memory array of data. For example, from the data returned from [std.file.read].

	It forwards the arguments to [readBmpIndirect], so see that for more details.

	If you are given a raw pointer to some data, you might just slice it: bytes 2-6 of the file header (if present)
	are a little-endian uint giving the file size. You might slice only to that, or you could slice right to `int.max`
	and trust the library to bounds check for you based on data integrity checks.
+/
MemoryImage readBmp(in ubyte[] data, bool lookForFileHeader = true, bool hackAround64BitLongs = false, bool hasAndMask = false) {
	int position;
	const(ubyte)[] current = data;
	void specialFread(void* tgt, size_t size) {
		while(size) {
			if (current.length == 0) throw new Exception("out of bmp data"); // it's not *that* fatal, so don't throw RangeError
			//import std.stdio; writefln("%04x", position);
			*cast(ubyte*)(tgt) = current[0];
			current = current[1 .. $];
			position++;
			tgt++;
			size--;
		}
	}

	return readBmpIndirect(&specialFread, lookForFileHeader, hackAround64BitLongs, hasAndMask);
}

/++
	Reads using a delegate to read instead of assuming a direct file. View the source of `readBmp`'s overloads for fairly simple examples of how you can use it

	History:
		The `lookForFileHeader` param was added in July 2020.

		The `hackAround64BitLongs` param was added December 21, 2020. You should probably never use this unless you know for sure you have a file corrupted in this specific way. View the source to see a comment inside the file to describe it a bit more.

		The `hasAndMask` param was added July 21, 2022. This is set to true if it is a bitmap from a .ico file or similar, where the top half of the file (by height) is the xor mask, then the bottom half is the and mask.
+/
MemoryImage readBmpIndirect(scope void delegate(void*, size_t) fread, bool lookForFileHeader = true, bool hackAround64BitLongs = false, bool hasAndMask = false) {
	uint read4()  { uint what; fread(&what, 4); return what; }
	uint readLONG()  {
		auto le = read4();
		/++
			A user on discord encountered a file in the wild that wouldn't load
			by any other bmp viewer. After looking at the raw bytes, it appeared it
			wrote out the LONG fields on the bitmap info header as 64 bit values when
			they are supposed to always be 32 bit values. This hack gives a chance to work
			around that and load the file anyway.
		+/
		if(hackAround64BitLongs)
			if(read4() != 0)
				throw new Exception("hackAround64BitLongs is true, but the file doesn't appear to use 64 bit longs");
		return le;
	}
	ushort read2(){ ushort what; fread(&what, 2); return what; }

	bool headerRead = false;
	int hackCounter;

	ubyte read1() {
		if(hackAround64BitLongs && headerRead && hackCounter < 16) {
			hackCounter++;
			return 0;
		}
		ubyte what;
		fread(&what, 1);
		return what;
	}

	void require1(ubyte t, size_t line = __LINE__) {
		if(read1() != t)
			throw new Exception("didn't get expected byte value", __FILE__, line);
	}
	void require2(ushort t) {
		auto got = read2();
		if(got != t) {
			version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("expected: %d, got %d\n", cast(int) t, cast(int) got); }
			throw new Exception("didn't get expected short value");
		}
	}
	void require4(uint t, size_t line = __LINE__) {
		auto got = read4();
		//import std.conv;
		if(got != t)
			throw new Exception("didn't get expected int value " /*~ to!string(got)*/, __FILE__, line);
	}

	uint offsetToBits;
	int offsetToBitsAfterHeader;

	if(lookForFileHeader) {
		require1('B');
		require1('M');

		auto fileSize = read4(); // size of file in bytes
		require2(0); // reserved
		require2(0); 	// reserved

		offsetToBits = read4();
		version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("pixel data offset: 0x%08x\n", cast(uint)offsetToBits); }
	}

	auto sizeOfBitmapInfoHeader = read4();
	if (sizeOfBitmapInfoHeader < 12) throw new Exception("invalid bitmap header size");

	version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("size of bitmap info header: %d\n", cast(uint)sizeOfBitmapInfoHeader); }

	if(offsetToBits > sizeOfBitmapInfoHeader + 14 /* 14 is the size size of file header */)
		offsetToBitsAfterHeader = offsetToBits - sizeOfBitmapInfoHeader - 14;

	int width, height, rdheight;

	if (sizeOfBitmapInfoHeader == 12) {
		width = read2();
		rdheight = cast(short)read2();
	} else {
		if (sizeOfBitmapInfoHeader < 16) throw new Exception("invalid bitmap header size");
		sizeOfBitmapInfoHeader -= 4; // hack!
		width = readLONG();
		rdheight = cast(int)readLONG();
	}

	height = (rdheight < 0 ? -rdheight : rdheight);

	if(hasAndMask) {
		version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("has and mask so height slashed %d\n", height / 2); }
		height = height / 2;
	}

	rdheight = (rdheight < 0 ? 1 : -1); // so we can use it as delta (note the inverted sign)

	version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("size: %dx%d\n", cast(int)width, cast(int) height); }
	if (width < 1 || height < 1) throw new Exception("invalid bitmap dimensions");

	require2(1); // planes

	auto bitsPerPixel = read2();
	switch (bitsPerPixel) {
		case 1: case 2: case 4: case 8: case 16: case 24: case 32: break;
		default: throw new Exception("invalid bitmap depth");
	}

	/*
		0 = BI_RGB
		1 = BI_RLE8   RLE 8-bit/pixel   Can be used only with 8-bit/pixel bitmaps
		2 = BI_RLE4   RLE 4-bit/pixel   Can be used only with 4-bit/pixel bitmaps
		3 = BI_BITFIELDS
	*/
	uint compression = 0;
	uint sizeOfUncompressedData = 0;
	uint xPixelsPerMeter = 0;
	uint yPixelsPerMeter = 0;
	uint colorsUsed = 0;
	uint colorsImportant = 0;

	sizeOfBitmapInfoHeader -= 12;
	if (sizeOfBitmapInfoHeader > 0) {
		if (sizeOfBitmapInfoHeader < 6*4) throw new Exception("invalid bitmap header size");
		sizeOfBitmapInfoHeader -= 6*4;
		compression = read4();
		sizeOfUncompressedData = read4();
		xPixelsPerMeter = readLONG();
		yPixelsPerMeter = readLONG();
		colorsUsed = read4();
		colorsImportant = read4();
	}

	if (compression > 3) throw new Exception("invalid bitmap compression");
	if (compression == 1 && bitsPerPixel != 8) throw new Exception("invalid bitmap compression");
	if (compression == 2 && bitsPerPixel != 4) throw new Exception("invalid bitmap compression");

	version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("compression: %u; bpp: %u\n", compression, cast(uint)bitsPerPixel); }

	uint redMask;
	uint greenMask;
	uint blueMask;
	uint alphaMask;
	if (compression == 3) {
		if (sizeOfBitmapInfoHeader < 4*4) throw new Exception("invalid bitmap compression");
		sizeOfBitmapInfoHeader -= 4*4;
		redMask = read4();
		greenMask = read4();
		blueMask = read4();
		alphaMask = read4();
	}
	// FIXME: we could probably handle RLE4 as well

	// I don't know about the rest of the header, so I'm just skipping it.
	version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("header bytes left: %u\n", cast(uint)sizeOfBitmapInfoHeader); }
	foreach (skip; 0..sizeOfBitmapInfoHeader) read1();

	headerRead = true;



	// the dg returns the change in offset
	void processAndMask(scope int delegate(int x, int y, bool transparent) apply) {
		try {
			// the and mask is always 1bpp and i want to translate it into transparent pixels

			for(int y = (height - 1); y >= 0; y--) {
				//version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf(" reading and mask %d\n", y); }
				int read;
				for(int x = 0; x < width; x++) {
					const b = read1();
					//import std.stdio; writefln("%02x", b);
					read++;
					foreach_reverse(lol; 0 .. 8) {
						bool transparent = !!((b & (1 << lol)));
						version(arsd_debug_bitmap_loader) { import std.stdio; write(transparent ? "o":"x"); }
						apply(x, y, transparent);

						x++;
						if(x >= width)
							break;
					}
					x--; // we do this once too many times in the loop
				}
				while(read % 4) {
					read1();
					read++;
				}
				version(arsd_debug_bitmap_loader) {import std.stdio; writeln(""); }
			}

			/+
			this the algorithm btw
			keep.imageData.bytes[] &= tci.imageData.bytes[andOffset .. $];
			keep.imageData.bytes[] ^= tci.imageData.bytes[0 .. andOffset];
			+/
		} catch(Exception e) {
			// discard; the and mask is optional in practice since using all 0's
			// gives a result and some files in the wild deliberately truncate the
			// file (though they aren't supposed to....) expecting readers to do this.
			version(arsd_debug_bitmap_loader) { import std.stdio; writeln(e); }
		}
	}



	if(bitsPerPixel <= 8) {
		// indexed image
		version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("colorsUsed=%u; colorsImportant=%u\n", colorsUsed, colorsImportant); }
		if (colorsUsed == 0 || colorsUsed > (1 << bitsPerPixel)) colorsUsed = (1 << bitsPerPixel);
		auto img = new IndexedImage(width, height);
		img.palette.reserve(1 << bitsPerPixel);

		foreach(idx; 0 .. /*(1 << bitsPerPixel)*/colorsUsed) {
			auto b = read1();
			auto g = read1();
			auto r = read1();
			auto reserved = read1();

			img.palette ~= Color(r, g, b);
		}
		while (img.palette.length < (1 << bitsPerPixel)) img.palette ~= Color.transparent;

		// and the data
		int bytesPerPixel = 1;
		auto offsetStart = (rdheight > 0 ? 0 : width * height * bytesPerPixel);
		int bytesRead = 0;

		if (compression == 1) {
			// this is complicated
			assert(bitsPerPixel == 8); // always
			int x = 0, y = (rdheight > 0 ? 0 : height-1);
			void setpix (int v) {
				if (x >= 0 && y >= 0 && x < width && y < height) img.data.ptr[y*width+x] = v&0xff;
				++x;
			}
			version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("width=%d; height=%d; rdheight=%d\n", width, height, rdheight); }
			for (;;) {
				ubyte codelen = read1();
				ubyte codecode = read1();
				version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("x=%d; y=%d; len=%u; code=%u\n", x, y, cast(uint)codelen, cast(uint)codecode); }
				bytesRead += 2;
				if (codelen == 0) {
					// special code
					if (codecode == 0) {
						// end of line
						version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("  EOL\n"); }
						while (x < width) setpix(1);
						x = 0;
						y += rdheight;
						if (y < 0 || y >= height) break; // ooops
					} else if (codecode == 1) {
						version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("  EOB\n"); }
						// end of bitmap
						break;
					} else if (codecode == 2) {
						// delta
						int xofs = read1();
						int yofs = read1();
						version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("  deltax=%d; deltay=%d\n", xofs, yofs); }
						bytesRead += 2;
						x += xofs;
						y += yofs*rdheight;
						if (y < 0 || y >= height) break; // ooops
					} else {
						version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("  LITERAL: %u\n", cast(uint)codecode); }
						// literal copy
						while (codecode-- > 0) {
							setpix(read1());
							++bytesRead;
						}
						version(arsd_debug_bitmap_loader) if (bytesRead%2) { import core.stdc.stdio; printf("  LITERAL SKIP\n"); }
						if (bytesRead%2) { read1(); ++bytesRead; }
						assert(bytesRead%2 == 0);
					}
				} else {
					while (codelen-- > 0) setpix(codecode);
				}
			}
		} else if (compression == 2) {
			throw new Exception("4RLE for bitmaps aren't supported yet");
		} else {
			for(int y = height; y > 0; y--) {
				if (rdheight < 0) offsetStart -= width * bytesPerPixel;
				int offset = offsetStart;
				while (bytesRead%4 != 0) {
					read1();
					++bytesRead;
				}
				bytesRead = 0;

				for(int x = 0; x < width; x++) {
					auto b = read1();
					++bytesRead;
					if(bitsPerPixel == 8) {
						img.data[offset++] = b;
					} else if(bitsPerPixel == 4) {
						img.data[offset++] = (b&0xf0) >> 4;
						x++;
						if(offset == img.data.length)
							break;
						img.data[offset++] = (b&0x0f);
					} else if(bitsPerPixel == 2) {
						img.data[offset++] = (b & 0b11000000) >> 6;
						x++;
						if(offset == img.data.length)
							break;
						img.data[offset++] = (b & 0b00110000) >> 4;
						x++;
						if(offset == img.data.length)
							break;
						img.data[offset++] = (b & 0b00001100) >> 2;
						x++;
						if(offset == img.data.length)
							break;
						img.data[offset++] = (b & 0b00000011) >> 0;
					} else if(bitsPerPixel == 1) {
						foreach_reverse(lol; 0 .. 8) {
							bool value = !!((b & (1 << lol)));
							img.data[offset++] = value ? 1 : 0;
							x++;
							if(offset == img.data.length)
								break;
						}
						x--; // we do this once too many times in the loop
					} else assert(0);
					// I don't think these happen in the wild but I could be wrong, my bmp knowledge is somewhat outdated
				}
				if (rdheight > 0) offsetStart += width * bytesPerPixel;
			}
		}

		if(hasAndMask) {
			auto tp = img.palette.length;
			if(tp < 256) {
				// easy, there's room, just add an entry.
				img.palette ~= Color.transparent;
				img.hasAlpha = true;
			} else {
				// not enough room, gotta try to find something unused to overwrite...
				// FIXME: could prolly use more caution here
				auto selection = 39;

				img.palette[selection] = Color.transparent;
				img.hasAlpha = true;
				tp = selection;
			}

			if(tp < 256) {
				processAndMask(delegate int(int x, int y, bool transparent) {
					auto existing = img.data[y * img.width + x];

					if(img.palette[existing] == Color.black && transparent) {
						// import std.stdio; write("O");
						img.data[y * img.width + x] = cast(ubyte) tp;
					} else {
						// import std.stdio; write("X");
					}

					return 1;
				});
			} else {
				//import std.stdio; writeln("no room in palette for transparency alas");
			}
		}

		return img;
	} else {
		if (compression != 0 && compression != 3) throw new Exception("unsupported bitmap compression");
		// true color image
		auto img = new TrueColorImage(width, height);

		foreach(counter; 0 .. offsetToBitsAfterHeader) {
			// so tbh I don't know what this actually is, but we can know to skip it at least
			read1();
		}

		// no palette, so straight into the data
		int offsetStart = width * height * 4;
		int bytesPerPixel = 4;
		for(int y = height; y > 0; y--) {
			version(arsd_debug_bitmap_loader) { import core.stdc.stdio; printf("  true color image: %d\n", y); }
			offsetStart -= width * bytesPerPixel;
			int offset = offsetStart;
			int b = 0;
			foreach(x; 0 .. width) {
				if(compression == 3) {
					ubyte[8] buffer;
					assert(bitsPerPixel / 8 < 8);
					foreach(lol; 0 .. bitsPerPixel / 8) {
						if(lol >= buffer.length)
							throw new Exception("wtf");
						buffer[lol] = read1();
						b++;
					}

					ulong data = *(cast(ulong*) buffer.ptr);

					auto blue = data & blueMask;
					auto green = data & greenMask;
					auto red = data & redMask;
					auto alpha = data & alphaMask;

					if(blueMask)
						blue = blue * 255 / blueMask;
					if(greenMask)
						green = green * 255 / greenMask;
					if(redMask)
						red = red * 255 / redMask;
					if(alphaMask)
						alpha = alpha * 255 / alphaMask;
					else
						alpha = 255;

					img.imageData.bytes[offset + 2] = cast(ubyte) blue;
					img.imageData.bytes[offset + 1] = cast(ubyte) green;
					img.imageData.bytes[offset + 0] = cast(ubyte) red;
					img.imageData.bytes[offset + 3] = cast(ubyte) alpha;
				} else {
					assert(compression == 0);

					if(bitsPerPixel == 24 || bitsPerPixel == 32) {
						img.imageData.bytes[offset + 2] = read1(); // b
						img.imageData.bytes[offset + 1] = read1(); // g
						img.imageData.bytes[offset + 0] = read1(); // r
						if(bitsPerPixel == 32) {
							img.imageData.bytes[offset + 3] = read1(); // a
							b++;
						} else {
							img.imageData.bytes[offset + 3] = 255; // a
						}
						b += 3;
					} else {
						assert(bitsPerPixel == 16);
						// these are stored xrrrrrgggggbbbbb
						ushort d = read1();
						d |= cast(ushort)read1() << 8;
							// we expect 8 bit numbers but these only give 5 bits of info,
							// therefore we shift left 3 to get the right stuff.
						img.imageData.bytes[offset + 0] = (d & 0b0111110000000000) >> (10-3);
						img.imageData.bytes[offset + 1] = (d & 0b0000001111100000) >> (5-3);
						img.imageData.bytes[offset + 2] = (d & 0b0000000000011111) << 3;
						img.imageData.bytes[offset + 3] = 255; // r
						b += 2;
					}
				}

				offset += bytesPerPixel;
			}

			int w = b%4;
			if(w)
			for(int a = 0; a < 4-w; a++)
				read1(); // pad until divisible by four
		}

		if(hasAndMask) {
			processAndMask(delegate int(int x, int y, bool transparent) {
				int offset = (y * img.width + x) * 4;
				auto existing = img.imageData.bytes[offset + 3];
				// only use the and mask if the alpha channel appears unused
				if(transparent && existing == 255)
					img.imageData.bytes[offset + 3] = 0;
				//import std.stdio; write(transparent ? "o":"x");

				return 4;
			});
		}


		return img;
	}

	assert(0);
}

/// Writes the `img` out to `filename`, in .bmp format. Writes [TrueColorImage] out
/// as a 24 bmp and [IndexedImage] out as an 8 bit bmp. Drops transparency information.
void writeBmp(MemoryImage img, string filename) {
	import core.stdc.stdio;
	FILE* fp = fopen((filename ~ "\0").ptr, "wb".ptr);
	if(fp is null)
		throw new Exception("can't open save file");
	scope(exit) fclose(fp);

	int written;
	void my_fwrite(ubyte b) {
		written++;
		fputc(b, fp);
	}

	writeBmpIndirect(img, &my_fwrite, true);
}

/+
void main() {
	import arsd.simpledisplay;
	//import std.file;
	//auto img = readBmp(cast(ubyte[]) std.file.read("/home/me/test2.bmp"));
	auto img = readBmp("/home/me/test2.bmp");
	import std.stdio;
	writeln((cast(Object)img).toString());
	displayImage(Image.fromMemoryImage(img));
	//img.writeBmp("/home/me/test2.bmp");
}
+/

/++
	Writes a bitmap file to a delegate, byte by byte, with data from the given image.

	If `prependFileHeader` is `true`, it will add the bitmap file header too.
+/
void writeBmpIndirect(MemoryImage img, scope void delegate(ubyte) fwrite, bool prependFileHeader) {

	void write4(uint what){
		fwrite(what & 0xff);
		fwrite((what >> 8) & 0xff);
		fwrite((what >> 16) & 0xff);
		fwrite((what >> 24) & 0xff);
	}
	void write2(ushort what){
		fwrite(what & 0xff);
		fwrite(what >> 8);
	}
	void write1(ubyte what) { fwrite(what); }

	int width = img.width;
	int height = img.height;
	ushort bitsPerPixel;

	ubyte[] data;
	Color[] palette;

	// FIXME we should be able to write RGBA bitmaps too, though it seems like not many
	// programs correctly read them!

	if(auto tci = cast(TrueColorImage) img) {
		bitsPerPixel = 24;
		data = tci.imageData.bytes;
		// we could also realistically do 16 but meh
	} else if(auto pi = cast(IndexedImage) img) {
		// FIXME: implement other bpps for more efficiency
		/*
		if(pi.palette.length == 2)
			bitsPerPixel = 1;
		else if(pi.palette.length <= 16)
			bitsPerPixel = 4;
		else
		*/
			bitsPerPixel = 8;
		data = pi.data;
		palette = pi.palette;
	} else throw new Exception("I can't save this image type " ~ img.classinfo.name);

	ushort offsetToBits;
	if(bitsPerPixel == 8)
		offsetToBits = 1078;
	else if (bitsPerPixel == 24 || bitsPerPixel == 16)
		offsetToBits = 54;
	else
		offsetToBits = cast(ushort)(54 * (1 << bitsPerPixel)); // room for the palette...

	uint fileSize = offsetToBits;
	if(bitsPerPixel == 8) {
		fileSize += height * (width + width%4);
	} else if(bitsPerPixel == 24)
		fileSize += height * ((width * 3) + (!((width*3)%4) ? 0 : 4-((width*3)%4)));
	else assert(0, "not implemented"); // FIXME

	if(prependFileHeader) {
		write1('B');
		write1('M');

		write4(fileSize); // size of file in bytes
		write2(0); 	// reserved
		write2(0); 	// reserved
		write4(offsetToBits); // offset to the bitmap data
	}

	write4(40); // size of BITMAPINFOHEADER

	write4(width); // width
	write4(height); // height

	write2(1); // planes
	write2(bitsPerPixel); // bpp
	write4(0); // compression
	write4(0); // size of uncompressed
	write4(0); // x pels per meter
	write4(0); // y pels per meter
	write4(0); // colors used
	write4(0); // colors important

	// And here we write the palette
	if(bitsPerPixel <= 8)
		foreach(c; palette[0..(1 << bitsPerPixel)]){
			write1(c.b);
			write1(c.g);
			write1(c.r);
			write1(0);
		}

	// And finally the data

	int bytesPerPixel;
	if(bitsPerPixel == 8)
		bytesPerPixel = 1;
	else if(bitsPerPixel == 24)
		bytesPerPixel = 4;
	else assert(0, "not implemented"); // FIXME

	int offsetStart = cast(int) data.length;
	for(int y = height; y > 0; y--) {
		offsetStart -= width * bytesPerPixel;
		int offset = offsetStart;
		int b = 0;
		foreach(x; 0 .. width) {
			if(bitsPerPixel == 8) {
				write1(data[offset]);
				b++;
			} else if(bitsPerPixel == 24) {
				write1(data[offset + 2]); // blue
				write1(data[offset + 1]); // green
				write1(data[offset + 0]); // red
				b += 3;
			} else assert(0); // FIXME
			offset += bytesPerPixel;
		}

		int w = b%4;
		if(w)
		for(int a = 0; a < 4-w; a++)
			write1(0); // pad until divisible by four
	}
}
