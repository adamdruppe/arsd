/++
	Support for [https://wiki.mozilla.org/APNG_Specification|animated png] files.

	History:
		Originally written March 2019 with read support.

		Render support added December 28, 2020.
+/
module arsd.apng;

///
unittest {
	import arsd.simpledisplay;
	import arsd.game;
	import arsd.apng;

	void main(string[] args) {
		import std.file;
		auto a = readApng(cast(ubyte[]) std.file.read(args[1]));

		auto window = create2dWindow("Animated PNG viewer", a.header.width, a.header.height);

		auto render = a.renderer();
		OpenGlTexture[] frames;
		int[] waits;
		foreach(frame; a.frames) {
			waits ~= render.nextFrame();
			// this would be the raw data for the frame
			//frames ~= new OpenGlTexture(frame.frameData.getAsTrueColorImage);
			// or the current rendered ersion
			frames ~= new OpenGlTexture(render.buffer);
		}

		int pos;
		int currentWait;

		void update() {
			currentWait += waits[pos];
			pos++;
			if(pos == frames.length)
				pos = 0;
		}

		window.redrawOpenGlScene = () {
			glClear(GL_COLOR_BUFFER_BIT);
			frames[pos].draw(0, 0);
		};

		auto tick = 50;
		window.eventLoop(tick, delegate() {
			currentWait -= tick;
			auto updateNeeded = currentWait <= 0;
			while(currentWait <= 0)
				update();
			if(updateNeeded)
				window.redrawOpenGlSceneNow();
		//},
		//(KeyEvent ev) {
		//if(ev.pressed)
		});
	}

	version(Demo) main(["", "/home/me/test/apngexample.apng"]); // remove from docs
}

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
	MemoryImage frameData;
	void populateData() {
		if(data !is null)
			return;

		import std.zlib;

		auto raw = cast(ubyte[]) uncompress(compressedDatastream);
		auto bpp = bytesPerPixel(parent.header);

		auto width = frameControlChunk.width;
		auto height = frameControlChunk.height;

		auto bytesPerLine = bytesPerLineOfPng(parent.header.depth, parent.header.type, width);
		bytesPerLine--; // removing filter byte from this calculation since we handle separately

		size_t idataIdx;
		ubyte[] idata;

		MemoryImage img;
		if(parent.header.type == 3) {
			auto i = new IndexedImage(width, height);
			img = i;
			i.palette = parent.palette;
			idata = i.data;
		} else {
			auto i = new TrueColorImage(width, height);
			img = i;
			idata = i.imageData.bytes;
		}

		immutable(ubyte)[] previousLine;
		foreach(y; 0 .. height) {
			auto filter = raw[0];
			raw = raw[1 .. $];
			auto line = raw[0 .. bytesPerLine];
			raw = raw[bytesPerLine .. $];

			auto unfiltered = unfilter(filter, line, previousLine, bpp);
			previousLine = unfiltered;

			convertPngData(parent.header.type, parent.header.depth, unfiltered, width, idata, idataIdx);
		}

		this.data = idata;
		this.frameData = img;
	}
}

struct ApngRenderBuffer {
	ApngAnimation animation;

	public TrueColorImage buffer;
	public int frameNumber;

	private FrameControlChunk prevFcc;
	private TrueColorImage[] convertedFrames;
	private TrueColorImage previousFrame;

	/++
		Returns number of millisecond to wait until the next frame.
	+/
	int nextFrame() {
		if(frameNumber == animation.frames.length) {
			frameNumber = 0;
			prevFcc = FrameControlChunk.init;
		}

		auto frame = animation.frames[frameNumber];
		auto fcc = frame.frameControlChunk;
		if(convertedFrames is null) {
			convertedFrames = new TrueColorImage[](animation.frames.length);
		}
		if(convertedFrames[frameNumber] is null) {
			frame.populateData();
			convertedFrames[frameNumber] = frame.frameData.getAsTrueColorImage();
		}

		final switch(prevFcc.dispose_op) {
			case APNG_DISPOSE_OP.NONE:
				break;
			case APNG_DISPOSE_OP.BACKGROUND:
				// clear area to 0
				foreach(y; prevFcc.y_offset .. prevFcc.y_offset + prevFcc.height)
					buffer.imageData.bytes[
						4 * (prevFcc.x_offset + y * buffer.width)
						..
						4 * (prevFcc.x_offset + prevFcc.width + y * buffer.width)
					] = 0;
				break;
			case APNG_DISPOSE_OP.PREVIOUS:
				// put the buffer back in

				// this could prolly be more efficient, it only really cares about the prevFcc bounding box
				buffer.imageData.bytes[] = previousFrame.imageData.bytes[];
				break;
		}

		prevFcc = fcc;
		// should copy the buffer at this point for a PREVIOUS case happening
		if(fcc.dispose_op == APNG_DISPOSE_OP.PREVIOUS) {
			// this could prolly be more efficient, it only really cares about the prevFcc bounding box
			if(previousFrame is null){
				previousFrame = buffer.clone();
			} else {
				previousFrame.imageData.bytes[] = buffer.imageData.bytes[];
			}
		}

		size_t foff;
		foreach(y; fcc.y_offset .. fcc.y_offset + fcc.height) {
			final switch(fcc.blend_op) {
				case APNG_BLEND_OP.SOURCE:
					buffer.imageData.bytes[
						4 * (fcc.x_offset + y * buffer.width)
						..
						4 * (fcc.x_offset + y * buffer.width + fcc.width)
					] = convertedFrames[frameNumber].imageData.bytes[foff .. foff + fcc.width * 4];
					foff += fcc.width * 4;
				break;
				case APNG_BLEND_OP.OVER:
					foreach(x; fcc.x_offset .. fcc.x_offset + fcc.width) {
						buffer.imageData.colors[y * buffer.width + x] =
							alphaBlend(
								convertedFrames[frameNumber].imageData.colors[foff],
								buffer.imageData.colors[y * buffer.width + x]
							);
						foff++;
					}
				break;
			}
		}

		frameNumber++;

		return fcc.delay_num * 1000 / fcc.delay_den;
	}
}

class ApngAnimation {
	PngHeader header;
	AnimationControlChunk acc;
	Color[] palette;
	ApngFrame[] frames;
	// default image? tho i can just load it as a png for that too.

	ApngRenderBuffer renderer() {
		return ApngRenderBuffer(this, new TrueColorImage(header.width, header.height), 0);
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

/++
	Loads an apng file.

	If it is a normal png file without animation it will
	just load it as a single frame "animation" FIXME
+/
ApngAnimation readApng(in ubyte[] data) {
	auto png = readPng(data);
	auto header = PngHeader.fromChunk(png.chunks[0]);

	auto obj = new ApngAnimation();
	obj.header = header;

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

				assert(frameNumber == 1); // we work on frame 0 but fcTL advances it
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
