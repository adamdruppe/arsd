/++
	Load (and, in the future, save) support for Windows .ico icon files.

	History:
		Written July 21, 2022 (dub v10.9)

	Examples:

	---
	void main() {
		auto thing = loadIco("test.ico");
		import std.stdio;
		writeln(thing.length); // tell how many things it found

		/+ // just to display one
		import arsd.simpledisplay;
		auto img = new SimpleWindow(thing[0].width, thing[0].height);
		{
		auto paint = img.draw();
		paint.drawImage(Point(0, 0), Image.fromMemoryImage(thing[0]));
		}

		img.eventLoop(0);
		+/

		// and this converts all its versions
		import arsd.png;
		import std.format;
		foreach(idx, t; thing)
			writePng(format("test-converted-%d-%dx%d.png", idx, t.width, t.height), t);
	}
	---
+/
module arsd.ico;

import arsd.png;
import arsd.bmp;

struct IcoHeader {
	ushort reserved;
	ushort imageType; // 1 = icon, 2 = cursor
	ushort numberOfImages;
}

struct ICONDIRENTRY {
	ubyte width; // 0 == 256
	ubyte height; // 0 == 256
	ubyte numColors; // 0 == no palette
	ubyte reserved;
	ushort planesOrHotspotX;
	ushort bppOrHotspotY;
	uint imageDataSize;
	uint imageDataOffset; // from beginning of file
}

// the file goes header, then array of dir entries, then images
/*
Recall that if an image is stored in BMP format, it must exclude the opening BITMAPFILEHEADER structure, whereas if it is stored in PNG format, it must be stored in its entirety.

Note that the height of the BMP image must be twice the height declared in the image directory. The second half of the bitmap should be an AND mask for the existing screen pixels, with the output pixels given by the formula Output = (Existing AND Mask) XOR Image. Set the mask to be zero everywhere for a clean overwrite. 

from wikipedia
*/

/++
	Loads a ico file off the given file or from the given memory block.

	Returns:
		Array of individual images found in the icon file. These are typically different size representations of the same icon.
+/
MemoryImage[] loadIco(string filename) {
	import std.file;
	return loadIcoFromMemory(cast(const(ubyte)[]) std.file.read(filename));
}

/// ditto
MemoryImage[] loadIcoFromMemory(const(ubyte)[] data) {
	IcoHeader header;
	if(data.length < 6)
		throw new Exception("Not an icon file - too short to have a header");
	header.reserved |= data[0];
	header.reserved |= data[1] << 8;

	header.imageType |= data[2];
	header.imageType |= data[3] << 8;

	header.numberOfImages |= data[4];
	header.numberOfImages |= data[5] << 8;

	if(header.reserved != 0)
		throw new Exception("Not an icon file - first bytes incorrect");
	if(header.imageType > 1)
		throw new Exception("Not an icon file - invalid image type header");

	auto originalData = data;
	data = data[6 .. $];

	ubyte nextByte() {
		if(data.length == 0)
			throw new Exception("Invalid icon file, it too short");
		ubyte b = data[0];
		data = data[1 .. $];
		return b;
	}

	ICONDIRENTRY readDirEntry() {
		ICONDIRENTRY ide;
		ide.width = nextByte();
		ide.height = nextByte();
		ide.numColors = nextByte();
		ide.reserved = nextByte();

		ide.planesOrHotspotX |= nextByte();
		ide.planesOrHotspotX |= nextByte() << 8;

		ide.bppOrHotspotY |= nextByte();
		ide.bppOrHotspotY |= nextByte() << 8;

		ide.imageDataSize |= nextByte() << 0;
		ide.imageDataSize |= nextByte() << 8;
		ide.imageDataSize |= nextByte() << 16;
		ide.imageDataSize |= nextByte() << 24;

		ide.imageDataOffset |= nextByte() << 0;
		ide.imageDataOffset |= nextByte() << 8;
		ide.imageDataOffset |= nextByte() << 16;
		ide.imageDataOffset |= nextByte() << 24;

		return ide;
	}

	ICONDIRENTRY[] ides;
	foreach(i; 0 .. header.numberOfImages)
		ides ~= readDirEntry();

	MemoryImage[] images;
	foreach(image; ides) {
		if(image.imageDataOffset >= originalData.length)
			throw new Exception("Invalid icon file - image data offset beyond file size");
		if(image.imageDataOffset + image.imageDataSize > originalData.length)
			throw new Exception("Invalid icon file - image data extends beyond file size");

		auto idata = originalData[image.imageDataOffset .. image.imageDataOffset + image.imageDataSize];

		if(idata.length < 4)
			throw new Exception("Invalid image, not long enough to identify");

		if(idata[0 .. 4] == "\x89PNG") {
			images ~= readPngFromBytes(idata);
		} else {
			images ~= readBmp(idata, false, false, true);
		}
	}

	return images;
}

