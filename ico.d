/++
	Load and save support for Windows .ico icon files. It also supports .cur files, but I've not actually tested them yet.

	History:
		Written July 21, 2022 (dub v10.9)

		Save support added April 21, 2023 (dub v11.0)

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

/++
	A representation of a cursor image as found in a .cur file.

	History:
		Added April 21, 2023 (dub v11.0)
+/
struct IcoCursor {
	MemoryImage image;
	int hotspotX;
	int hotspotY;
}

/++
	The header of a .ico or .cur file. Note the alignment is $(I not) correct for slurping the file.
+/
struct IcoHeader {
	ushort reserved;
	ushort imageType; // 1 = icon, 2 = cursor
	ushort numberOfImages;
}

/++
	The icon directory entry of a .ico or .cur file. Note the alignment is $(I not) correct for slurping the file.
+/
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
	MemoryImage[] images;
	int spot;
	loadIcoOrCurFromMemoryCallback(
		data,
		(int imageType, int numberOfImages) {
			if(imageType > 1)
				throw new Exception("Not an icon file - invalid image type header");

			images.length = numberOfImages;
		},
		(MemoryImage mi, int hotspotX, int hotspotY) {
			images[spot++] = mi;
		}
	);

	assert(spot == images.length);

	return images;
}

/++
	Loads a .cur file.

	History:
		Added April 21, 2023 (dub v11.0)
+/
IcoCursor[] loadCurFromMemory(const(ubyte)[] data) {
	IcoCursor[] images;
	int spot;
	loadIcoOrCurFromMemoryCallback(
		data,
		(int imageType, int numberOfImages) {
			if(imageType != 2)
				throw new Exception("Not an cursor file - invalid image type header");

			images.length = numberOfImages;
		},
		(MemoryImage mi, int hotspotX, int hotspotY) {
			images[spot++] = IcoCursor(mi, hotspotX, hotspotY);
		}
	);

	assert(spot == images.length);

	return images;

}

/++
	Load implementation. Api subject to change.
+/
void loadIcoOrCurFromMemoryCallback(
	const(ubyte)[] data,
	scope void delegate(int imageType, int numberOfImages) imageTypeChecker,
	scope void delegate(MemoryImage mi, int hotspotX, int hotspotY) encounteredImage,
) {
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

	imageTypeChecker(header.imageType, header.numberOfImages);

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

	foreach(image; ides) {
		if(image.imageDataOffset >= originalData.length)
			throw new Exception("Invalid icon file - image data offset beyond file size");
		if(image.imageDataOffset + image.imageDataSize > originalData.length)
			throw new Exception("Invalid icon file - image data extends beyond file size");

		auto idata = originalData[image.imageDataOffset .. image.imageDataOffset + image.imageDataSize];

		if(idata.length < 4)
			throw new Exception("Invalid image, not long enough to identify");

		if(idata[0 .. 4] == "\x89PNG") {
			encounteredImage(readPngFromBytes(idata), image.planesOrHotspotX, image.bppOrHotspotY);
		} else {
			encounteredImage(readBmp(idata, false, false, true), image.planesOrHotspotX, image.bppOrHotspotY);
		}
	}
}

/++
	History:
		Added April 21, 2023 (dub v11.0)
+/
void writeIco(string filename, MemoryImage[] images) {
	writeIcoOrCur(filename, false, cast(int) images.length, (int idx) { return IcoCursor(images[idx]); });
}

/// ditto
void writeCur(string filename, IcoCursor[] images) {
	writeIcoOrCur(filename, true, cast(int) images.length, (int idx) { return images[idx]; });
}

/++
	Save implementation. Api subject to change.
+/
void writeIcoOrCur(string filename, bool isCursor, int count, scope IcoCursor delegate(int) getImageAndHotspots) {
	IcoHeader header;
	header.reserved = 0;
	header.imageType = isCursor ? 2 : 1;
	if(count > ushort.max)
		throw new Exception("too many images for icon file");
	header.numberOfImages = cast(ushort) count;

	enum headerSize = 6;
	enum dirEntrySize = 16;

	int dataFilePos = headerSize + dirEntrySize * cast(int) count;

	ubyte[][] pngs;
	ICONDIRENTRY[] dirEntries;
	dirEntries.length = count;
	pngs.length = count;
	foreach(idx, ref entry; dirEntries) {
		auto image = getImageAndHotspots(cast(int) idx);
		if(image.image.width > 256 || image.image.height > 256)
			throw new Exception("image too big for icon file");
		entry.width = image.image.width == 256 ? 0 : cast(ubyte) image.image.width;
		entry.height = image.image.height == 256 ? 0 : cast(ubyte) image.image.height;

		entry.planesOrHotspotX = isCursor ? cast(ushort) image.hotspotX : 0;
		entry.bppOrHotspotY = isCursor ? cast(ushort) image.hotspotY : 0;

		auto png = writePngToArray(image.image);

		entry.imageDataSize = cast(uint) png.length;
		entry.imageDataOffset = dataFilePos;
		dataFilePos += entry.imageDataSize;

		pngs[idx] = png;
	}

	ubyte[] data;
	data.length = dataFilePos;
	int pos = 0;

	data[pos++] = (header.reserved >> 0) & 0xff;
	data[pos++] = (header.reserved >> 8) & 0xff;
	data[pos++] = (header.imageType >> 0) & 0xff;
	data[pos++] = (header.imageType >> 8) & 0xff;
	data[pos++] = (header.numberOfImages >> 0) & 0xff;
	data[pos++] = (header.numberOfImages >> 8) & 0xff;

	foreach(entry; dirEntries) {
		data[pos++] = (entry.width >> 0) & 0xff;
		data[pos++] = (entry.height >> 0) & 0xff;
		data[pos++] = (entry.numColors >> 0) & 0xff;
		data[pos++] = (entry.reserved >> 0) & 0xff;
		data[pos++] = (entry.planesOrHotspotX >> 0) & 0xff;
		data[pos++] = (entry.planesOrHotspotX >> 8) & 0xff;
		data[pos++] = (entry.bppOrHotspotY >> 0) & 0xff;
		data[pos++] = (entry.bppOrHotspotY >> 8) & 0xff;

		data[pos++] = (entry.imageDataSize >> 0) & 0xff;
		data[pos++] = (entry.imageDataSize >> 8) & 0xff;
		data[pos++] = (entry.imageDataSize >> 16) & 0xff;
		data[pos++] = (entry.imageDataSize >> 24) & 0xff;

		data[pos++] = (entry.imageDataOffset >> 0) & 0xff;
		data[pos++] = (entry.imageDataOffset >> 8) & 0xff;
		data[pos++] = (entry.imageDataOffset >> 16) & 0xff;
		data[pos++] = (entry.imageDataOffset >> 24) & 0xff;
	}

	foreach(png; pngs) {
		data[pos .. pos + png.length] = png[];
		pos += png.length;
	}

	assert(pos == dataFilePos);

	import std.file;
	std.file.write(filename, data);
}
