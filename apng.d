/++
	Support for [animated png|https://wiki.mozilla.org/APNG_Specification] files.
+/
module arsd.apng;

import arsd.png;

// acTL
// must be in the file before the IDAT
struct AnimationControlChunk {
	uint num_frames;
	uint num_plays;
}

// fcTL
struct FrameControlChunk {
	align(1):
	// this should go up each time, for frame control AND for frame data, each increases.
	uint sequence_number;
	uint width;
	uint height;
	uint x_offset;
	uint y_offset;
	ushort delay_num;
	ushort delay_den;
	APNG_DISPOSE_OP dispose_op;
	APNG_BLEND_OP blend_op;

	static assert(dispose_op.offsetof == 24);
	static assert(blend_op.offsetof == 25);
}

// fdAT
class ApngFrame {

	ApngAnimation parent;

	this(ApngAnimation parent) {
		this.parent = parent;
	}

	FrameControlChunk frameControlChunk;

	ubyte[] compressedDatastream;

	ubyte[] data;
	void populateData() {
		if(data !is null)
			return;

		import std.zlib;

		auto raw = cast(ubyte[]) uncompress(compressedDatastream);
		auto bpp = bytesPerPixel(parent.header);

		auto width = frameControlChunk.width;
		auto height = frameControlChunk.height;

		auto bytesPerLine = bytesPerLineOfPng(parent.header.depth, parent.header.type, width);
		bytesPerLine--; // removing filter byte from this calculation since we handle separtely

		size_t idataIdx;
		ubyte[] idata;

		idata.length = width * height * (parent.header.type == 3 ? 1 : 4);

		ubyte[] previousLine;
		foreach(y; 0 .. height) {
			auto filter = raw[0];
			raw = raw[1 .. $];
			auto line = raw[0 .. bytesPerLine];
			raw = raw[bytesPerLine .. $];

			auto unfiltered = unfilter(filter, line, previousLine, bpp);
			previousLine = line;

			convertPngData(parent.header.type, parent.header.depth, unfiltered, width, idata, idataIdx);
		}

		this.data = idata;
	}

	//MemoryImage frameData;
}

class ApngAnimation {
	PngHeader header;
	AnimationControlChunk acc;
	Color[] palette;
	ApngFrame[] frames;
	// default image? tho i can just load it as a png for that too.

	MemoryImage render() {
		return null;
	}
}

enum APNG_DISPOSE_OP : byte {
	NONE = 0,
	BACKGROUND = 1,
	PREVIOUS = 2
}

enum APNG_BLEND_OP : byte {
	SOURCE = 0,
	OVER = 1
}

ApngAnimation readApng(in ubyte[] data) {
	auto png = readPng(data);
	auto header = PngHeader.fromChunk(png.chunks[0]);

	auto obj = new ApngAnimation();

	if(header.type == 3) {
		obj.palette = fetchPalette(png);
	}

	bool seenIdat = false;
	bool seenFctl = false;

	int frameNumber;
	int expectedSequenceNumber = 0;

	foreach(chunk; png.chunks) {
		switch(chunk.stype) {
			case "IDAT":
				seenIdat = true;
				// all I care about here are animation frames,
				// so if this isn't after a control chunk, I'm
				// just going to ignore it. Read the file with
				// readPng if you want that.
				if(!seenFctl)
					continue;

				assert(obj.frames[0]);

				obj.frames[0].compressedDatastream ~= chunk.payload;
			break;
			case "acTL":
				AnimationControlChunk c;
				int offset = 0;
				c.num_frames |= chunk.payload[offset++] << 24;
				c.num_frames |= chunk.payload[offset++] << 16;
				c.num_frames |= chunk.payload[offset++] <<  8;
				c.num_frames |= chunk.payload[offset++] <<  0;

				c.num_plays |= chunk.payload[offset++] << 24;
				c.num_plays |= chunk.payload[offset++] << 16;
				c.num_plays |= chunk.payload[offset++] <<  8;
				c.num_plays |= chunk.payload[offset++] <<  0;

				assert(offset == chunk.payload.length);

				obj.acc = c;
				obj.frames = new ApngFrame[](c.num_frames);
			break;
			case "fcTL":
				FrameControlChunk c;
				int offset = 0;

				seenFctl = true;

				c.sequence_number |= chunk.payload[offset++] << 24;
				c.sequence_number |= chunk.payload[offset++] << 16;
				c.sequence_number |= chunk.payload[offset++] <<  8;
				c.sequence_number |= chunk.payload[offset++] <<  0;

				c.width |= chunk.payload[offset++] << 24;
				c.width |= chunk.payload[offset++] << 16;
				c.width |= chunk.payload[offset++] <<  8;
				c.width |= chunk.payload[offset++] <<  0;

				c.height |= chunk.payload[offset++] << 24;
				c.height |= chunk.payload[offset++] << 16;
				c.height |= chunk.payload[offset++] <<  8;
				c.height |= chunk.payload[offset++] <<  0;

				c.x_offset |= chunk.payload[offset++] << 24;
				c.x_offset |= chunk.payload[offset++] << 16;
				c.x_offset |= chunk.payload[offset++] <<  8;
				c.x_offset |= chunk.payload[offset++] <<  0;

				c.y_offset |= chunk.payload[offset++] << 24;
				c.y_offset |= chunk.payload[offset++] << 16;
				c.y_offset |= chunk.payload[offset++] <<  8;
				c.y_offset |= chunk.payload[offset++] <<  0;

				c.delay_num |= chunk.payload[offset++] <<  8;
				c.delay_num |= chunk.payload[offset++] <<  0;

				c.delay_den |= chunk.payload[offset++] <<  8;
				c.delay_den |= chunk.payload[offset++] <<  0;

				c.dispose_op = cast(APNG_DISPOSE_OP) chunk.payload[offset++];
				c.blend_op = cast(APNG_BLEND_OP) chunk.payload[offset++];

				assert(offset == chunk.payload.length);

				if(expectedSequenceNumber != c.sequence_number)
					throw new Exception("malformed apng file");

				expectedSequenceNumber++;


				if(obj.frames[frameNumber] is null)
					obj.frames[frameNumber] = new ApngFrame(obj);
				obj.frames[frameNumber].frameControlChunk = c;

				frameNumber++;
			break;
			case "fdAT":
				uint sequence_number;
				int offset;

				sequence_number |= chunk.payload[offset++] << 24;
				sequence_number |= chunk.payload[offset++] << 16;
				sequence_number |= chunk.payload[offset++] <<  8;
				sequence_number |= chunk.payload[offset++] <<  0;

				if(expectedSequenceNumber != sequence_number)
					throw new Exception("malformed apng file");

				expectedSequenceNumber++;

				// and the rest of it is a datastream...
				obj.frames[frameNumber - 1].compressedDatastream ~= chunk.payload[offset .. $];
			break;
			default:
				// ignore
		}

	}

	return obj;
}
