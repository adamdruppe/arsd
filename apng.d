/++
	Support for [https://wiki.mozilla.org/APNG_Specification|animated png] files.

	$(WARNING Please note this interface is not exactly stable and may break with minimum notice.)

	History:
		Originally written March 2019 with read support.

		Render support added December 28, 2020.

		Write support added February 27, 2021.
+/
module arsd.apng;

/// Demo creating one from scratch
unittest {
	import arsd.apng;

	void main() {
		auto apng = new ApngAnimation(50, 50);

		auto frame = apng.addFrame(25, 25);
		frame.data[] = 255;

		frame = apng.addFrame(25, 25);
		frame.data[] = 255;
		frame.frameControlChunk.delay_num = 10;

		frame = apng.addFrame(25, 25);
		frame.data[] = 255;
		frame.frameControlChunk.x_offset = 25;
		frame.frameControlChunk.delay_num = 10;

		frame = apng.addFrame(25, 25);
		frame.data[] = 255;
		frame.frameControlChunk.y_offset = 25;
		frame.frameControlChunk.delay_num = 10;

		frame = apng.addFrame(25, 25);
		frame.data[] = 255;
		frame.frameControlChunk.x_offset = 25;
		frame.frameControlChunk.y_offset = 25;
		frame.frameControlChunk.delay_num = 10;


		writeApngToFile(apng, "/home/me/test.apng");
	}

	version(Demo) main(); // exclude from docs
}

/// Demo reading and rendering
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

		// writeApngToFile(a, "/home/me/test.apng");
	}

	version(Demo) main(["", "/home/me/test.apng"]); // exclude from docs
	//version(Demo) main(["", "/home/me/small-clouds.png"]); // exclude from docs
}

import arsd.png;

// must be in the file before the IDAT
/// acTL chunk direct representation
struct AnimationControlChunk {
	uint num_frames;
	uint num_plays;

	/// Adds it to a chunk payload buffer, returning the slice of `buffer` actually used
	/// Used internally by the [writeApngToFile] family of functions.
	ubyte[] toChunkPayload(ubyte[] buffer)
		in { assert(buffer.length >= 8); }
	do {
		int offset = 0;
		buffer[offset++] = (num_frames >> 24) & 0xff;
		buffer[offset++] = (num_frames >> 16) & 0xff;
		buffer[offset++] = (num_frames >>  8) & 0xff;
		buffer[offset++] = (num_frames >>  0) & 0xff;

		buffer[offset++] = (num_plays >> 24) & 0xff;
		buffer[offset++] = (num_plays >> 16) & 0xff;
		buffer[offset++] = (num_plays >>  8) & 0xff;
		buffer[offset++] = (num_plays >>  0) & 0xff;

		return buffer[0 .. offset];
	}
}

/// fcTL chunk direct representation
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

	ubyte[] toChunkPayload(int sequenceNumber, ubyte[] buffer)
		in { assert(buffer.length >= typeof(this).sizeof); }
	do {
		int offset = 0;

		sequence_number = sequenceNumber;

		buffer[offset++] = (sequence_number >> 24) & 0xff;
		buffer[offset++] = (sequence_number >> 16) & 0xff;
		buffer[offset++] = (sequence_number >>  8) & 0xff;
		buffer[offset++] = (sequence_number >>  0) & 0xff;

		buffer[offset++] = (width >> 24) & 0xff;
		buffer[offset++] = (width >> 16) & 0xff;
		buffer[offset++] = (width >>  8) & 0xff;
		buffer[offset++] = (width >>  0) & 0xff;

		buffer[offset++] = (height >> 24) & 0xff;
		buffer[offset++] = (height >> 16) & 0xff;
		buffer[offset++] = (height >>  8) & 0xff;
		buffer[offset++] = (height >>  0) & 0xff;

		buffer[offset++] = (x_offset >> 24) & 0xff;
		buffer[offset++] = (x_offset >> 16) & 0xff;
		buffer[offset++] = (x_offset >>  8) & 0xff;
		buffer[offset++] = (x_offset >>  0) & 0xff;

		buffer[offset++] = (y_offset >> 24) & 0xff;
		buffer[offset++] = (y_offset >> 16) & 0xff;
		buffer[offset++] = (y_offset >>  8) & 0xff;
		buffer[offset++] = (y_offset >>  0) & 0xff;

		buffer[offset++] = (delay_num >>  8) & 0xff;
		buffer[offset++] = (delay_num >>  0) & 0xff;

		buffer[offset++] = (delay_den >>  8) & 0xff;
		buffer[offset++] = (delay_den >>  0) & 0xff;

		buffer[offset++] = cast(ubyte) dispose_op;
		buffer[offset++] = cast(ubyte) blend_op;

		return buffer[0 .. offset];
	}
}

/++
	Represents a single frame from the file, directly corresponding to the fcTL and fdAT data from the file.
+/
class ApngFrame {

	ApngAnimation parent;

	this(ApngAnimation parent) {
		this.parent = parent;
	}

	this(ApngAnimation parent, int width, int height) {
		this.parent = parent;
		frameControlChunk.width = width;
		frameControlChunk.height = height;

		if(parent.header.type == 3) { // FIXME: other types?!
			auto ii = new IndexedImage(width, height);
			ii.palette = parent.palette;
			frameData = ii;
			data = ii.data;
		} else {
			auto tci = new TrueColorImage(width, height);
			frameData = tci;
			data = tci.imageData.bytes;
		}
	}

	void resyncData() {
		if(frameData is null)
			populateData();

		assert(frameData !is null);
		assert(frameData.width == frameControlChunk.width);
		assert(frameData.height == frameControlChunk.height);

		if(auto tci = cast(TrueColorImage) frameData) {
			data = tci.imageData.bytes;
			assert(parent.header.type == 6);
		} else if(auto ii = cast(IndexedImage) frameData) {
			data = ii.data;
			assert(parent.header.type == 3);
			assert(ii.palette == parent.palette);
		}
	}

	/++
		You're allowed to edit these values but remember it is your responsibility to keep
		it consistent with the rest of the file (at least for now, I might change this in the future).
	+/
	FrameControlChunk frameControlChunk;

	private ubyte[] compressedDatastream; /// Raw datastream from the file.

	/++
		A reference to frameData's bytes. May be 8 bit if indexed or 32 bit rgba if not.

		Do not replace this reference but you may edit the content.
	+/
	ubyte[] data;

	/++
		Processed frame data as an image. only set after you call populateData.

		You are allowed to edit the bytes on this but don't change the width/height or palette. Also don't replace the object.

		This also means `getAsTrueColorImage` is not that useful, instead cast to [IndexedImage] or [TrueColorImage] depending
		on your type.
	+/
	MemoryImage frameData;
	/++
		Loads the raw [compressedDatastream] into raw uncompressed [data] and processed [frameData]
	+/
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
		} else { // FIXME: other types?!
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

/++

+/
struct ApngRenderBuffer {
	/// Load this yourself
	ApngAnimation animation;

	/// Then these are populated when you call [nextFrame]
	public TrueColorImage buffer;
	/// ditto
	public int frameNumber;

	private FrameControlChunk prevFcc;
	private TrueColorImage[] convertedFrames;
	private TrueColorImage previousFrame;

	/++
		Returns number of millisecond to wait until the next frame and populates [buffer] and [frameNumber].
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

		if(fcc.delay_den == 0)
			return fcc.delay_num * 1000 / 100;
		else
			return fcc.delay_num * 1000 / fcc.delay_den;
	}
}

/++
	Class that represents an apng file.
+/
class ApngAnimation {
	PngHeader header;
	AnimationControlChunk acc;
	Color[] palette;
	ApngFrame[] frames;
	// default image? tho i can just load it as a png for that too.

	/++
		This is an uninitialized thing, you're responsible for filling in all data yourself. You probably don't want to
		use this except for use in the `factory` function you pass to [readApng].
	+/
	this() {

	}

	/++
		If palette is null, it is a true color image. If it has data, it is indexed.
	+/
	this(int width, int height, Color[] palette = null) {
		header.type = (palette !is null) ? 3 : 6;
		header.width = width;
		header.height = height;

		this.palette = palette;
	}

	/++
		Adds a frame with the given size and returns the object. You can change other values in the frameControlChunk on it
		and get the data bytes out of there.
	+/
	ApngFrame addFrame(int width, int height) {
		assert(width <= header.width);
		assert(height <= header.height);
		auto f = new ApngFrame(this, width, height);
		frames ~= f;
		acc.num_frames++;
		return f;
	}

	// call before writing or trying to render again
	void resyncData() {
		acc.num_frames = cast(int) frames.length;
		foreach(frame; frames)
			frame.resyncData();
	}

	///
	ApngRenderBuffer renderer() {
		return ApngRenderBuffer(this, new TrueColorImage(header.width, header.height), 0);
	}

	/++
		Hook for subclasses to handle custom chunks in the png file as it is loaded by [readApng].

		Examples:
			---
			override void handleOtherChunkWhenLoading(Chunk chunk) {
				if(chunk.stype == "mine") {
					ubyte[] data = chunk.payload;
					// process it
				}
			}
			---

		History:
			Added December 26, 2021 (dub v10.5)
	+/
	protected void handleOtherChunkWhenLoading(Chunk chunk) {
		// intentionally blank to ignore it since the main function does the whole base functionality
	}

	/++
		Hook for subclasses to add custom chunks to the png file as it is written by [writeApngToData] and [writeApngToFile].

		Standards:
			See the png spec for guidelines on how to create non-essential, private chunks in a file:

			http://www.libpng.org/pub/png/spec/1.2/PNG-Encoders.html#E.Use-of-private-chunks

		Examples:
			---
			override createOtherChunksWhenSaving(scope void delegate(Chunk c) sink) {
				sink(*Chunk.create("mine", [payload, bytes, here]));
			}
			---

		History:
			Added December 26, 2021 (dub v10.5)
	+/
	protected void createOtherChunksWhenSaving(scope void delegate(Chunk c) sink) {
		// no other chunks by default

		// I can now do the repeat frame thing for start / cycle / end bits of the animation in the game!
	}
}

///
enum APNG_DISPOSE_OP : byte {
	NONE = 0, ///
	BACKGROUND = 1, ///
	PREVIOUS = 2 ///
}

///
enum APNG_BLEND_OP : byte {
	SOURCE = 0, ///
	OVER = 1 ///
}

/++
	Loads an apng file.

	Params:
		data = the raw data bytes of the file
		strictApng = if true, it will strictly interpret
		the file as apng and ignore the default image. If there
		are no animation chunks, it will return an empty ApngAnimation
		object.

		If false, it will use the default image as the first
		(and only) frame of animation if there are no apng chunks.

		factory = factory function for constructing the [ApngAnimation]
		object the function returns. You can use this to override the
		allocation pattern or to return a subclass instead, which can handle
		custom chunks and other things.

	History:
		Parameter `strictApng` added February 27, 2021
		Parameter `factory` added December 26, 2021
+/
ApngAnimation readApng(in ubyte[] data, bool strictApng = false, scope ApngAnimation delegate() factory = null) {
	auto png = readPng(data);
	auto header = PngHeader.fromChunk(png.chunks[0]);

	ApngAnimation obj;
	if(factory)
		obj = factory();
	else
		obj = new ApngAnimation();

	obj.header = header;

	if(header.type == 3) {
		obj.palette = fetchPalette(png);
	}

	bool seenIdat = false;
	bool seenFctl = false;

	int frameNumber;
	int expectedSequenceNumber = 0;

	bool seenacTL = false;

	foreach(chunk; png.chunks) {
		switch(chunk.stype) {
			case "IDAT":

				if(!seenacTL && !strictApng) {
					// acTL chunks must appear before IDAT per spec,
					// so if there isn't one by now, it isn't an apng file.
					// but unless we care about strictApng, we can salvage
					// by making some dummy data.

					{
						AnimationControlChunk c;
						c.num_frames = 1;
						c.num_plays = 1;

						obj.acc = c;
						obj.frames = new ApngFrame[](c.num_frames);

						seenacTL = true;
					}

					{
						FrameControlChunk c;
						c.sequence_number = 1;
						c.width = header.width;
						c.height = header.height;
						c.x_offset = 0;
						c.y_offset = 0;
						c.delay_num = short.max;
						c.delay_den = 1;
						c.dispose_op = APNG_DISPOSE_OP.NONE;
						c.blend_op = APNG_BLEND_OP.SOURCE;

						seenFctl = true;

						// not increasing expectedSequenceNumber since if something is present, this is malformed!

						if(obj.frames[frameNumber] is null)
							obj.frames[frameNumber] = new ApngFrame(obj);
						obj.frames[frameNumber].frameControlChunk = c;

						frameNumber++;
					}
				}


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

				seenacTL = true;
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

				import std.conv;
				if(expectedSequenceNumber != c.sequence_number)
					throw new Exception("malformed apng file expected fcTL seq " ~ to!string(expectedSequenceNumber) ~ " got " ~ to!string(c.sequence_number));

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

				import std.conv;
				if(expectedSequenceNumber != sequence_number)
					throw new Exception("malformed apng file expected fdAT seq " ~ to!string(expectedSequenceNumber) ~ " got " ~ to!string(sequence_number));

				expectedSequenceNumber++;

				// and the rest of it is a datastream...
				obj.frames[frameNumber - 1].compressedDatastream ~= chunk.payload[offset .. $];
			break;
			default:
				obj.handleOtherChunkWhenLoading(chunk);
		}

	}

	return obj;
}


/++
	It takes the apng file and feeds the file data to your `sink` delegate, the given file,
	or simply returns it as an in-memory array.
+/
void writeApngToData(ApngAnimation apng, scope void delegate(in ubyte[] data) sink) {

	apng.resyncData();

	PNG* p = blankPNG(apng.header);
	if(apng.palette.length)
		p.replacePalette(apng.palette);

	// I want acTL first, then frames, then idat last.

	ubyte[128] buffer;

	p.chunks ~= *(Chunk.create("acTL", apng.acc.toChunkPayload(buffer[]).dup));

	// then IDAT is required
	// FIXME: it might be better to just legit use the first frame but meh gotta check size and stuff too
	auto render = apng.renderer();
	render.nextFrame();
	auto data = render.buffer.imageData.bytes;
	addImageDatastreamToPng(data, p, false);

	// then the frames
	int sequenceNumber = 0;
	foreach(frame; apng.frames) {
		p.chunks ~= *(Chunk.create("fcTL", frame.frameControlChunk.toChunkPayload(sequenceNumber++, buffer[]).dup));
		// fdAT

		import std.zlib;

		size_t bytesPerLine;
		switch(apng.header.type) {
			case 0:
				// FIXME: < 8 depth not supported here but should be
				bytesPerLine = cast(size_t) frame.frameControlChunk.width * 1 * apng.header.depth / 8;
			break;
			case 2:
				bytesPerLine = cast(size_t) frame.frameControlChunk.width * 3 * apng.header.depth / 8;
			break;
			case 3:
				bytesPerLine = cast(size_t) frame.frameControlChunk.width * 1 * apng.header.depth / 8;
			break;
			case 4:
				// FIXME: < 8 depth not supported here but should be
				bytesPerLine = cast(size_t) frame.frameControlChunk.width * 2 * apng.header.depth / 8;
			break;
			case 6:
				bytesPerLine = cast(size_t) frame.frameControlChunk.width * 4 * apng.header.depth / 8;
			break;
			default: assert(0);

		}

		Chunk dat;
		dat.type = ['f', 'd', 'A', 'T'];
		size_t pos = 0;

		const(ubyte)[] output;

		frame.populateData();

		while(pos+bytesPerLine <= frame.data.length) {
			output ~= 0;
			output ~= frame.data[pos..pos+bytesPerLine];
			pos += bytesPerLine;
		}

		auto com = cast(ubyte[]) compress(output);
		dat.size = cast(int) com.length + 4;

		buffer[0] = (sequenceNumber >> 24) & 0xff;
		buffer[1] = (sequenceNumber >> 16) & 0xff;
		buffer[2] = (sequenceNumber >>  8) & 0xff;
		buffer[3] = (sequenceNumber >>  0) & 0xff;

		sequenceNumber++;


		dat.payload = buffer[0 .. 4] ~ com;
		dat.checksum = crc("fdAT", dat.payload);

		p.chunks ~= dat;
	}

	{
		Chunk c;

		c.size = 0;
		c.type = ['I', 'E', 'N', 'D'];
		c.checksum = crc("IEND", c.payload);
		p.chunks ~= c;
	}

	sink(writePng(p));
}

/// ditto
void writeApngToFile(ApngAnimation apng, string filename) {
	import std.stdio;
	auto file = File(filename, "wb");
	writeApngToData(apng, delegate(in ubyte[] data) {
		file.rawWrite(data);
	});
}

/// ditto
ubyte[] getApngBytes(ApngAnimation apng) {
	ubyte[] ret;
	writeApngToData(apng, (in ubyte[] data) { ret ~= data; });
	return ret;
}
