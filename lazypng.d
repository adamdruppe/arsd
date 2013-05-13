// this is like png.d but all range based so more complicated...
// and I don't remember how to actually use it.

// some day I'll prolly merge it with png.d but for now just throwing it up there

module arsd.lazypng;

import arsd.color;

import std.stdio;

import std.range;
import std.traits;
import std.exception;
import std.string;
import std.conv;

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

//import simpledisplay;

struct RgbaScanline {
	Color[] pixels;
}


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

					enforce(chunk.size < palette.length);

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
			std.zlib.UnCompress decompressor;
			int chunkSize;
			T chunks;

			this(int cs, T chunks) {
				decompressor = new std.zlib.UnCompress();
				this.chunkSize = cs;
				this.chunks = chunks;

				popFront(); // priming
			}

			ubyte[] front() {
				assert(current.length == chunkSize);
				return current;
			}

			ubyte[] current;
			ubyte[] buffer;

			void popFront() {
				if(buffer.length < chunkSize) {
					if(chunks.front().stype != "IDAT") {
						buffer ~= cast(ubyte[]) decompressor.flush();
						if(buffer.length != 0)
							goto stillMore;
						current = null;
						buffer = null;
						return;
					}

					buffer ~= cast(ubyte[])
						decompressor.uncompress(chunks.front().payload);
					chunks.popFront();
				}
				stillMore:
				current = buffer[0 .. chunkSize];
				buffer = buffer[chunkSize .. $];
			}

			bool empty() {
				return (current.length == 0);
			}
		}

		auto range = DatastreamByChunk!(typeof(chunks))(chunkSize, chunks);

		return range;
	}

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

			int length() {
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
		immutable bitsPerChannel = header.depth;

		int bitsPerPixel = bitsPerChannel;
		if(header.type & 2 && !(header.type & 1)) // in color, but no palette
			bitsPerPixel *= 3;
		if(header.type & 4) // has alpha channel
			bitsPerPixel += bitsPerChannel;

		return (bitsPerPixel + 7) / 8;
	}

	// FIXME: doesn't handle interlacing... I think
	int bytesPerLine() {
		immutable bitsPerChannel = header.depth;

		int bitsPerPixel = bitsPerChannel;
		if(header.type & 2 && !(header.type & 1)) // in color, but no palette
			bitsPerPixel *= 3;
		if(header.type & 4) // has alpha channel
			bitsPerPixel += bitsPerChannel;


		immutable int sizeInBits = header.width * bitsPerPixel;

		// need to round up to the nearest byte
		int sizeInBytes = (sizeInBits + 7) / 8;

		return sizeInBytes + 1; // the +1 is for the filter byte that precedes all lines
	}

	PngHeader header;
	Color[] palette;
}


/**************************************************
 * Buffered input range - generic, non-image code
***************************************************/

/// Is the given range a buffered input range? That is, an input range
/// that also provides consumeFromFront(int) and appendToFront()
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

import std.zlib;
import std.math;

/// All PNG files are supposed to open with these bytes according to the spec
enum immutable(ubyte[]) PNG_MAGIC_NUMBER = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/// A PNG file consists of the magic number then a stream of chunks. This
/// struct represents those chunks.
struct Chunk {
	uint size;
	ubyte[4] type;
	ubyte[] payload;
	uint checksum;

	/// returns the type as a string for easier comparison with literals
	string stype() const {
		return cast(string) type;
	}

	static Chunk* create(string type, ubyte[] payload)
		in {
			assert(type.length == 4);
		}
	body {
		Chunk* c = new Chunk;
		c.size = payload.length;
		c.type = cast(ubyte[]) type;
		c.payload = payload;

		c.checksum = crcPng(type, payload);

		return c;
	}

	/// Puts it into the format for outputting to a file
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

	static PngHeader fromChunk(in Chunk c) {
		enforce(c.stype == "IHDR",
			"The chunk is not an image header");

		PngHeader h;
		auto data = c.payload;
		int pos = 0;

		enforce(data.length == 13,
			"Malformed PNG file - the IHDR is the wrong size");

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

void writePng(OutputRange, InputRange)(OutputRange where, InputRange image)
	if(
		isOutputRange!(OutputRange, ubyte[]) &&
		isInputRange!(InputRange) &&
		is(ElementType!InputRange == RgbaScanline))
{
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


// Private: used for checking/updating PNG checksums
uint update_crc(in uint crc, in ubyte[] buf){
	static const uint[256] crc_table = [0, 1996959894, 3993919788, 2567524794, 124634137, 1886057615, 3915621685, 2657392035, 249268274, 2044508324, 3772115230, 2547177864, 162941995, 2125561021, 3887607047, 2428444049, 498536548, 1789927666, 4089016648, 2227061214, 450548861, 1843258603, 4107580753, 2211677639, 325883990, 1684777152, 4251122042, 2321926636, 335633487, 1661365465, 4195302755, 2366115317, 997073096, 1281953886, 3579855332, 2724688242, 1006888145, 1258607687, 3524101629, 2768942443, 901097722, 1119000684, 3686517206, 2898065728, 853044451, 1172266101, 3705015759, 2882616665, 651767980, 1373503546, 3369554304, 3218104598, 565507253, 1454621731, 3485111705, 3099436303, 671266974, 1594198024, 3322730930, 2970347812, 795835527, 1483230225, 3244367275, 3060149565, 1994146192, 31158534, 2563907772, 4023717930, 1907459465, 112637215, 2680153253, 3904427059, 2013776290, 251722036, 2517215374, 3775830040, 2137656763, 141376813, 2439277719, 3865271297, 1802195444, 476864866, 2238001368, 4066508878, 1812370925, 453092731, 2181625025, 4111451223, 1706088902, 314042704, 2344532202, 4240017532, 1658658271, 366619977, 2362670323, 4224994405, 1303535960, 984961486, 2747007092, 3569037538, 1256170817, 1037604311, 2765210733, 3554079995, 1131014506, 879679996, 2909243462, 3663771856, 1141124467, 855842277, 2852801631, 3708648649, 1342533948, 654459306, 3188396048, 3373015174, 1466479909, 544179635, 3110523913, 3462522015, 1591671054, 702138776, 2966460450, 3352799412, 1504918807, 783551873, 3082640443, 3233442989, 3988292384, 2596254646, 62317068, 1957810842, 3939845945, 2647816111, 81470997, 1943803523, 3814918930, 2489596804, 225274430, 2053790376, 3826175755, 2466906013, 167816743, 2097651377, 4027552580, 2265490386, 503444072, 1762050814, 4150417245, 2154129355, 426522225, 1852507879, 4275313526, 2312317920, 282753626, 1742555852, 4189708143, 2394877945, 397917763, 1622183637, 3604390888, 2714866558, 953729732, 1340076626, 3518719985, 2797360999, 1068828381, 1219638859, 3624741850, 2936675148, 906185462, 1090812512, 3747672003, 2825379669, 829329135, 1181335161, 3412177804, 3160834842, 628085408, 1382605366, 3423369109, 3138078467, 570562233, 1426400815, 3317316542, 2998733608, 733239954, 1555261956, 3268935591, 3050360625, 752459403, 1541320221, 2607071920, 3965973030, 1969922972, 40735498, 2617837225, 3943577151, 1913087877, 83908371, 2512341634, 3803740692, 2075208622, 213261112, 2463272603, 3855990285, 2094854071, 198958881, 2262029012, 4057260610, 1759359992, 534414190, 2176718541, 4139329115, 1873836001, 414664567, 2282248934, 4279200368, 1711684554, 285281116, 2405801727, 4167216745, 1634467795, 376229701, 2685067896, 3608007406, 1308918612, 956543938, 2808555105, 3495958263, 1231636301, 1047427035, 2932959818, 3654703836, 1088359270, 936918000, 2847714899, 3736837829, 1202900863, 817233897, 3183342108, 3401237130, 1404277552, 615818150, 3134207493, 3453421203, 1423857449, 601450431, 3009837614, 3294710456, 1567103746, 711928724, 3020668471, 3272380065, 1510334235, 755167117];

	uint c = crc;

	foreach(b; buf)
		c = crc_table[(c ^ b) & 0xff] ^ (c >> 8);

	return c;
}

uint crcPng(in string chunkName, in ubyte[] buf){
	uint c = update_crc(0xffffffffL, cast(ubyte[]) chunkName);
	return update_crc(c, buf) ^ 0xffffffffL;
}

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
			foreach(i; 0 .. arr.length) {
				arr[i] += previousLine[i];
			}

			return assumeUnique(arr);
		case 3:
			auto arr = data.dup;
			foreach(i; 0 .. arr.length) {
				auto prev = i < bpp ? 0 : arr[i - bpp];
				arr[i] += cast(ubyte)
					std.math.floor( cast(int) (prev + previousLine[i]) / 2);
			}

			return assumeUnique(arr);
		case 4:
			auto arr = data.dup;
			foreach(i; 0 .. arr.length) {
				ubyte prev   = i < bpp ? 0 : arr[i - bpp];
				ubyte prevLL = i < bpp ? 0 : previousLine[i - bpp];

				arr[i] += PaethPredictor(prev, previousLine[i], prevLL);
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
