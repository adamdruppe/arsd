module arsd.jpg;

import std.typecons;
import std.stdio;
import std.conv;

struct JpegSection {
	ubyte identifier;
	ubyte[] data;
}

// gives as a range of file sections
struct LazyJpegFile {
	File f;
	JpegSection _front;
	bool _frontIsValid;
	this(File f) {
		this.f = f;

		ubyte[2] headerBuffer;
		auto data = f.rawRead(headerBuffer);
		if(data != [0xff, 0xd8])
			throw new Exception("no jpeg header");
		popFront(); // prime
	}

	void popFront() {
		ubyte[4] startingBuffer;
		auto read = f.rawRead(startingBuffer);
		if(read.length != 4) {
			_frontIsValid = false;
			return; // end of file
		}

		if(startingBuffer[0] != 0xff)
			throw new Exception("not lined up in file");

		_front.identifier = startingBuffer[1];
		ushort length = cast(ushort) (startingBuffer[2]) * 256 + startingBuffer[3];

		if(length < 2)
			throw new Exception("wtf");
		length -= 2; // the length in the file includes the block header, but we just want the data here

		_front.data = new ubyte[](length);
		read = f.rawRead(_front.data);
		if(read.length != length)
			throw new Exception("didn't read the file right, got " ~ to!string(read.length) ~ " instead of " ~ to!string(length));

		_frontIsValid = true;
	}

	JpegSection front() {
		return _front;
	}

	bool empty() {
		return !_frontIsValid;
	}
}

// returns width, height
Tuple!(int, int) getSizeFromFile(string filename) {
	import std.stdio;

	auto file = File(filename, "rb");

	auto jpeg = LazyJpegFile(file);

	auto firstSection = jpeg.front();
	jpeg.popFront();

	// commented because exif and jfif are both readable by this so no need to be picky
	//if(firstSection.identifier != 0xe0)
		//throw new Exception("bad header");

	for(; !jpeg.empty(); jpeg.popFront()) {
		if(jpeg.front.identifier != 0xc0)
			continue;
		auto data = jpeg.front.data[1..$]; // skip the precision byte

		ushort height = data[0] * 256 + data[1];
		ushort width  = data[2] * 256 + data[3];
		return tuple(cast(int) width, cast(int) height);
	}

	throw new Exception("idk about the length");
}
