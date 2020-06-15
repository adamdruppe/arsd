/++
	Basic .wav file reading and writing.

	History:
		Written May 15, 2020, but loosely based on code I wrote a
		long time ago, at least August 2008 which is the oldest
		file I have generated from the original code.

		The old code could only write files, the reading support
		was all added in 2020.
+/
module arsd.wav;

import core.stdc.stdio;

/++

+/
struct WavWriter {
	private FILE* fp;

	/++
		Opens the file with the given header params.

		Make sure you pass the correct params to header, except,
		if you have a seekable stream, the data length can be zero
		and it will be fixed when you close. If you have a non-seekable
		stream though, you must give the size up front.

		If you need to go to memory, the best way is to just
		append your data to your own buffer, then create a [WavFileHeader]
		separately and prepend it. Wav files are simple, aside from
		the header and maybe a terminating byte (which isn't really important
		anyway), there's nothing special going on.

		Throws: Exception on error from [open].

		---
		auto writer = WavWriter("myfile.wav", WavFileHeader(44100, 2, 16));
		writer.write(shortSamples);
		---
	+/
	this(string filename, WavFileHeader header) {
		this.header = header;

		if(!open(filename))
			throw new Exception("Couldn't open file for writing"); // FIXME: errno
	}

	/++
		`WavWriter(WavFileHeader(44100, 2, 16));`
	+/
	this(WavFileHeader header) @nogc nothrow {
		this.header = header;
	}

	/++
		Calls [close]. Errors are ignored.
	+/
	~this() @nogc {
		close();
	}

	@disable this(this);

	private uint size;
	private WavFileHeader header;

	@nogc:

	/++
		Returns: true on success, false on error. Check errno for details.
	+/
	bool open(string filename) {
		assert(fp is null);
		assert(filename.length < 290);

		char[300] fn;
		fn[0 .. filename.length] = filename[];
		fn[filename.length] = 0;

		fp = fopen(fn.ptr, "wb");
		if(fp is null)
			return false;
		if(fwrite(&header, header.sizeof, 1, fp) != 1)
			return false;

		return true;
	}

	/++
		Writes 8-bit samples to the file. You must have constructed the object with an 8 bit header.

		Returns: true on success, false on error. Check errno for details.
	+/
	bool write(ubyte[] data) {
		assert(header.bitsPerSample == 8);
		if(fp is null)
			return false;
		if(fwrite(data.ptr, 1, data.length, fp) != data.length)
			return false;
		size += data.length;
		return true;
	}

	/++
		Writes 16-bit samples to the file. You must have constructed the object with 16 bit header.

		Returns: true on success, false on error. Check errno for details.
	+/
	bool write(short[] data) {
		assert(header.bitsPerSample == 16);
		if(fp is null)
			return false;
		if(fwrite(data.ptr, 2, data.length, fp) != data.length)
			return false;
		size += data.length * 2;
		return true;
	}

	/++
		Returns: true on success, false on error. Check errno for details.
	+/
	bool close() {
		if(fp is null)
			return true;

		// pad odd sized file as required by spec...
		if(size & 1) {
			fputc(0, fp);
		}

		if(!header.dataLength) {
			// put the length back at the beginning of the file
			if(fseek(fp, 0, SEEK_SET) != 0)
				return false;
			auto n = header.withDataLengthInBytes(size);
			if(fwrite(&n, 1, n.sizeof, fp) != 1)
				return false;
		} else {
			assert(header.dataLength == size);
		}
		if(fclose(fp))
			return false;
		fp = null;
		return true;
	}
}

version(LittleEndian) {} else static assert(0, "just needs endian conversion coded in but i was lazy");

align(1)
///
struct WavFileHeader {
	align(1):
	const ubyte[4] header = ['R', 'I', 'F', 'F'];
	int topSize; // dataLength + 36
	const ubyte[4] type = ['W', 'A', 'V', 'E'];
	const ubyte[4] fmtHeader = ['f', 'm', 't', ' '];
	const int fmtHeaderSize = 16;
	const ushort audioFormat = 1; // PCM

	ushort numberOfChannels;
	uint sampleRate;

	uint bytesPerSeconds; // bytesPerSampleTimesChannels * sampleRate
	ushort bytesPerSampleTimesChannels; // bitsPerSample * channels / 8

	ushort bitsPerSample; // 16

	const ubyte[4] dataHeader = ['d', 'a', 't', 'a'];
	uint dataLength;
	// data follows. put a 0 at the end if dataLength is odd.

	///
	this(uint sampleRate, ushort numberOfChannels, ushort bitsPerSample, uint dataLengthInBytes = 0) @nogc pure @safe nothrow {
		assert(bitsPerSample == 8 || bitsPerSample == 16);

		this.numberOfChannels = numberOfChannels;
		this.sampleRate = sampleRate;
		this.bitsPerSample = bitsPerSample;

		this.bytesPerSampleTimesChannels = cast(ushort) (numberOfChannels * bitsPerSample / 8);
		this.bytesPerSeconds = this.bytesPerSampleTimesChannels * sampleRate;

		this.topSize = dataLengthInBytes + 36;
		this.dataLength = dataLengthInBytes;
	}

	///
	WavFileHeader withDataLengthInBytes(int dataLengthInBytes) const @nogc pure @safe nothrow {
		return WavFileHeader(sampleRate, numberOfChannels, bitsPerSample, dataLengthInBytes);
	}
}
static assert(WavFileHeader.sizeof == 44);


/++
	After construction, the parameters are set and you can set them.
	After that, you process the samples range-style.

	It ignores chunks in the file that aren't the basic standard.
	It throws exceptions if it isn't a bare-basic PCM wav file.

	See [wavReader] for the convenience constructors.

	Note that if you are reading a 16 bit file (`bitsPerSample == 16`),
	you'll actually need to `cast(short[]) front`.

	---
		auto reader = wavReader(data[]);
		foreach(chunk; reader)
			play(chunk);
	---
+/
struct WavReader(Range) {
	const ushort numberOfChannels;
	const int sampleRate;
	const ushort bitsPerSample;
	int dataLength; // don't modify plz

	private uint remainingDataLength;

	private Range underlying;

	private const(ubyte)[] frontBuffer;

	static if(is(Range == CFileChunks)) {
		this(FILE* fp) {
			underlying = CFileChunks(fp);
			this(0);
		}
	} else {
		this(Range r) {
			this.underlying = r;
			this(0);
		}
	}

	private this(int _initializationDummyVariable) {
		this.frontBuffer = underlying.front;

		WavFileHeader header;
		ubyte[] headerBytes = (cast(ubyte*) &header)[0 .. header.sizeof - 8];

		if(this.frontBuffer.length >= headerBytes.length) {
			headerBytes[] = this.frontBuffer[0 .. headerBytes.length];
			this.frontBuffer = this.frontBuffer[headerBytes.length .. $];
		} else {
			throw new Exception("Probably not a wav file, or else pass bigger chunks please");
		}

		if(header.header != ['R', 'I', 'F', 'F'])
			throw new Exception("Not a wav file; no RIFF header");
		if(header.type != ['W', 'A', 'V', 'E'])
			throw new Exception("Not a wav file");
		// so technically the spec does NOT require fmt to be the first chunk..
		// but im gonna just be lazy
		if(header.fmtHeader != ['f', 'm', 't', ' '])
			throw new Exception("Malformed or unsupported wav file");

		if(header.fmtHeaderSize < 16)
			throw new Exception("Unsupported wav format header");

		auto additionalSkip = header.fmtHeaderSize - 16;

		if(header.audioFormat != 1)
			throw new Exception("arsd.wav only supports the most basic wav files and this one has advanced encoding. try converting to a .mp3 file and use arsd.mp3.");

		this.numberOfChannels = header.numberOfChannels;
		this.sampleRate = header.sampleRate;
		this.bitsPerSample = header.bitsPerSample;

		if(header.bytesPerSampleTimesChannels != header.bitsPerSample * header.numberOfChannels / 8)
			throw new Exception("Malformed wav file: header.bytesPerSampleTimesChannels didn't match");
		if(header.bytesPerSeconds != header.bytesPerSampleTimesChannels * header.sampleRate)
			throw new Exception("Malformed wav file: header.bytesPerSeconds didn't match");

		this.frontBuffer = this.frontBuffer[additionalSkip .. $];

		static struct ChunkHeader {
			align(1):
			ubyte[4] type;
			uint size;
		}
		static assert(ChunkHeader.sizeof == 8);

		ChunkHeader current;
		ubyte[] chunkHeader = (cast(ubyte*) &current)[0 .. current.sizeof];

		another_chunk:

		// now we're at the next chunk. want to skip until we hit data.
		if(this.frontBuffer.length < chunkHeader.length)
			throw new Exception("bug in arsd.wav the chunk isn't big enough to handle and im lazy. if you hit this send me your file plz");

		chunkHeader[] = frontBuffer[0 .. chunkHeader.length];
		frontBuffer = frontBuffer[chunkHeader.length .. $];

		if(current.type != ['d', 'a', 't', 'a']) {
			// skip unsupported chunk...
			drop_more:
			if(frontBuffer.length > current.size) {
				frontBuffer = frontBuffer[current.size .. $];
			} else {
				current.size -= frontBuffer.length;
				underlying.popFront();
				if(underlying.empty) {
					throw new Exception("Ran out of data while trying to read wav chunks");
				} else {
					frontBuffer = underlying.front;
					goto drop_more;
				}
			}
			goto another_chunk;
		} else {
			this.remainingDataLength = current.size;
		}

		this.dataLength = this.remainingDataLength;
	}

	@property const(ubyte)[] front() {
		return frontBuffer;
	}

	version(none)
	void consumeBytes(size_t count) {
		if(this.frontBuffer.length)
			this.frontBuffer = this.frontBuffer[count .. $];
	}

	void popFront() {
		remainingDataLength -= front.length;

		underlying.popFront();
		if(underlying.empty)
			frontBuffer = null;
		else
			frontBuffer = underlying.front;
	}

	@property bool empty() {
		return remainingDataLength == 0 || this.underlying.empty;
	}
}

/++
	Convenience constructor for [WavReader]

	To read from a file, pass a filename, a FILE*, or a range that
	reads chunks from a file.

	To read from a memory block, just pass it a `ubyte[]` slice.
+/
WavReader!T wavReader(T)(T t) {
	return WavReader!T(t);
}

/// ditto
WavReader!DataBlock wavReader(const(ubyte)[] data) {
	return WavReader!DataBlock(DataBlock(data));
}

struct DataBlock {
	const(ubyte)[] front;
	bool empty() { return front.length == 0; }
	void popFront() { front = null; }
}

/// Construct a [WavReader] from a filename.
WavReader!CFileChunks wavReader(string filename) {
	assert(filename.length < 290);

	char[300] fn;
	fn[0 .. filename.length] = filename[];
	fn[filename.length] = 0;

	auto fp = fopen(fn.ptr, "rb");
	if(fp is null)
		throw new Exception("wav file unopenable"); // FIXME details

	return WavReader!CFileChunks(fp);
}

struct CFileChunks {
	FILE* fp;
	this(FILE* fp) {
		this.fp = fp;
		buffer = new ubyte[](4096);
		refcount = new int;
		*refcount = 1;
		popFront();
	}
	this(this) {
		if(refcount !is null)
			(*refcount) += 1;
	}
	~this() {
		if(refcount is null) return;
		(*refcount) -= 1;
		if(*refcount == 0) {
			fclose(fp);
		}
	}

	//ubyte[4096] buffer;
	ubyte[] buffer;
	int* refcount;

	ubyte[] front;

	void popFront() {
		auto got = fread(buffer.ptr, 1, buffer.length, fp);
		front = buffer[0 .. got];
	}

	bool empty() {
		return front.length == 0 && (feof(fp) ? true : false);
	}
}
