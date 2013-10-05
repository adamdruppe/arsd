module arsd.bmp;

import arsd.color;

MemoryImage readBmp(string filename) {
	import core.stdc.stdio;

	FILE* fp = fopen((filename ~ "\0").ptr, "rb".ptr);
	if(fp is null)
		throw new Exception("can't open save file");
	scope(exit) fclose(fp);

	void specialFread(void* tgt, size_t size) {
		fread(tgt, size, 1, fp);
	}

	return readBmpIndirect(&specialFread);
}

MemoryImage readBmp(in ubyte[] data) {
	const(ubyte)[] current = data;
	void specialFread(void* tgt, size_t size) {
		while(size) {
			*cast(ubyte*)(tgt) = current[0];
			current = current[1 .. $];
			tgt++;
			size--;
		}
	}

	return readBmpIndirect(&specialFread);
}

MemoryImage readBmpIndirect(void delegate(void*, size_t) fread) {
	uint read4()  { uint what; fread(&what, 4); return what; }
	ushort read2(){ ushort what; fread(&what, 2); return what; }
	ubyte read1(){ ubyte what; fread(&what, 1); return what; }

	void require1(ubyte t, size_t line = __LINE__) {
		if(read1() != t)
			throw new Exception("didn't get expected byte value", __FILE__, line);
	}
	void require2(ushort t) {
		if(read2() != t)
			throw new Exception("didn't get expected short value");
	}
	void require4(uint t, size_t line = __LINE__) {
		auto got = read4();
		//import std.conv;
		if(got != t)
			throw new Exception("didn't get expected int value " /*~ to!string(got)*/, __FILE__, line);
	}

	require1('B');
	require1('M');

	auto fileSize = read4(); // size of file in bytes
	require2(0); // reserved
	require2(0); 	// reserved

	auto offsetToBits = read4();

	auto sizeOfBitmapInfoHeader = read4();

	auto width = read4();
	auto height = read4();

	require2(1); // planes

	auto bitsPerPixel = read2();

	/*
		0 = BI_RGB
		3 = BI_BITFIELDS
	*/
	auto compression = read4();
	auto sizeOfUncompressedData = read4();

	auto xPixelsPerMeter = read4();
	auto yPixelsPerMeter = read4();
	auto colorsUsed = read4();
	auto colorsImportant = read4();

	int additionalRead = 0;
	uint redMask;
	uint greenMask;
	uint blueMask;
	uint alphaMask;
	if(compression == 3) {
		redMask = read4();
		greenMask = read4();
		blueMask = read4();
		alphaMask = read4();
		additionalRead += 4 * 4;
	}
	// FIXME: we could probably handle RLE as well

	// I don't know about the rest of the header, so I'm just skipping it.
	// 40 is the size of the basic info header that I did read.
	foreach(skip; 0 .. sizeOfBitmapInfoHeader - 40 - additionalRead)
		read1();

	if(bitsPerPixel <= 8) {
		// indexed image
		auto img = new IndexedImage(width, height);
		foreach(idx; 0 .. (1 << bitsPerPixel)) {
			auto b = read1();
			auto g = read1();
			auto r = read1();
			auto reserved = read1();

			img.palette ~= Color(r, g, b);
		}

		// and the data
		int bytesPerPixel = 1;
		auto offsetStart = width * height * bytesPerPixel;

		for(int y = height; y > 0; y--) {
			offsetStart -= width * bytesPerPixel;
			int offset = offsetStart;
			int bytesRead = 0;
			for(int x = 0; x < width; x++) {
				auto b = read1();
				bytesRead++;

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
					foreach(lol; 0 .. 8) {
						img.data[offset++] = (b & (1 << lol)) >> (7 - lol);
						x++;
						if(offset == img.data.length)
							break;
					}
					x--; // we do this once too many times in the loop

				} else assert(0);
				// I don't think these happen in the wild but I could be wrong, my bmp knowledge is somewhat outdated
			}

			int w = bytesRead%4;
			if(w)
			for(int a = 0; a < 4-w; a++)
				require1(0); // pad until divisible by four
		}



		return img;
	} else {
		// true color image
		auto img = new TrueColorImage(width, height);

		// no palette, so straight into the data
		int offsetStart = width * height * 4;
		int bytesPerPixel = 4;
		for(int y = height; y > 0; y--) {
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
				require1(0); // pad until divisible by four
		}


		return img;
	}

	assert(0);
}

void writeBmp(MemoryImage img, string filename) {
	import core.stdc.stdio;
	FILE* fp = fopen((filename ~ "\0").ptr, "wb".ptr);
	if(fp is null)
		throw new Exception("can't open save file");
	scope(exit) fclose(fp);

	void write4(uint what)  { fwrite(&what, 4, 1, fp); }
	void write2(ushort what){ fwrite(&what, 2, 1, fp); }
	void write1(ubyte what) { fputc(what, fp); }

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
	if (bitsPerPixel == 24 || bitsPerPixel == 16)
		offsetToBits = 54;
	else
		offsetToBits = cast(ushort)(54 + 4 * 1 << bitsPerPixel); // room for the palette...

	uint fileSize = offsetToBits;
	if(bitsPerPixel == 8)
		fileSize += height * (width + width%4);
	else if(bitsPerPixel == 24)
		fileSize += height * ((width * 3) + (!((width*3)%4) ? 0 : 4-((width*3)%4)));
	else assert(0, "not implemented"); // FIXME

	write1('B');
	write1('M');

	write4(fileSize); // size of file in bytes
	write2(0); 	// reserved
	write2(0); 	// reserved
	write4(offsetToBits); // offset to the bitmap data

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

	int offsetStart = data.length;
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

/+
void main() {
	import simpledisplay;
	//import std.file;
	//auto img = readBmp(cast(ubyte[]) std.file.read("/home/me/test2.bmp"));
	auto img = readBmp("/home/me/test2.bmp");
	import std.stdio;
	writeln((cast(Object)img).toString());
	displayImage(Image.fromMemoryImage(img));
	//img.writeBmp("/home/me/test2.bmp");
}
+/
