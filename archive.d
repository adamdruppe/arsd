/++
	Provides LZMA (aka .xz), gzip (.gz) and .tar file read-only support.
	Combine to read .tar.xz and .tar.gz files, or use in conjunction with
	other libraries to read other kinds of files.

	Also has a custom archive called arcz read and write support.
	It is designed to efficiently pack and randomly access large
	numbers of similar files. Unlike .zip files, it will do
	cross-file compression (meaning it can significantly shrink
	archives with several small but similar files), and unlike
	tar.gz files, it supports random access without decompressing
	the whole archive to get an individual file. It is designed
	for large numbers of small, similar files.

	History:
		tar code (and arsd module formed) originally written December 2019 to support my d_android library downloader. It was added to dub in March 2020 (dub v7.0).

		The LZMA code is a D port of Igor Pavlov's LzmaDec.h, written in 2017 with contributions by Lasse Collin. It was ported to D by ketmar some time after that and included in the original version of `arsd.archive` in the first December 2019 release.

		The arcz code was written by ketmar in 2016 and added to arsd.archive in March 2020.

		A number of improvements were made with the help of Steven Schveighoffer on March 22, 2023.

		`arsd.archive` was changed to require [arsd.core] on March 23, 2023 (dub v11.0). Previously, it was a standalone module. It uses arsd.core's exception helpers only at this time and you could turn them back into plain (though uninformative) D base `Exception` instances to remove the dependency if you wanted to keep the file independent.

                The [ArzArchive] class had a memory leak prior to November 2, 2024. It now uses the GC instead.
+/
module arsd.archive;

import arsd.core;

version(WithoutLzmaDecoder) {} else
version=WithLzmaDecoder;

version(WithoutArczCode) {} else
version=WithArczCode;

/+
/++
	Reads a tar file and passes the chunks to your handler. Use it like:

	TarFile f = TarFile("filename.tar");
	foreach(part; f) {
		if(part.isNewFile) {

		}
	}

	FIXME not implemented
+/
struct TarFile {
	this(string filename) {

	}
}
+/

inout(char)[] upToZero(inout(char)[] a) {
	int i = 0;
	while(i < a.length && a[i]) i++;
	return a[0 .. i];
}


/++
	A header of a file in the archive. This represents the
	binary format of the header block.
+/
align(512)
struct TarFileHeader {
	align(1):
	char[100] fileName_ = 0;
	char[8] fileMode_ = 0;
	char[8] ownerUid_ = 0;
	char[8] ownerGid_ = 0;
	char[12] size_ = 0; // in octal
	char[12] mtime_ = 0; // octal unix timestamp
	char[8] checksum_ = 0; // right?????
	char[1] fileType_ = 0; // hard link, soft link, etc
	char[100] linkFileName_ = 0;
	char[6] ustarMagic_ = 0; // if "ustar\0", remaining fields are set
	char[2] ustarVersion_ = 0;
	char[32] ownerName_ = 0;
	char[32] groupName_ = 0;
	char[8] deviceMajorNumber_ = 0;
	char[8] deviceMinorNumber_ = 0;
	char[155] filenamePrefix_ = 0;

	/// Returns the filename. You should cache the return value as long as TarFileHeader is in scope (it returns a slice after calling strlen)
	const(char)[] filename() {
		import core.stdc.string;
		if(filenamePrefix_[0])
			return upToZero(filenamePrefix_[]) ~ upToZero(fileName_[]);
		return upToZero(fileName_[]);
	}

	/++
		Returns the target of a symlink or hardlink. Remember, this returns a slice of the TarFileHeader structure, so once it goes out of scope, this slice will be dangling!

		History:
			Added March 24, 2023 (dub v11.0)
	+/
	const(char)[] linkFileName() {
		return upToZero(linkFileName_[]);
	}

	///
	ulong size() {
		import core.stdc.stdlib;
		return strtoul(size_.ptr, null, 8);
	}

	///
	TarFileType type() {
		if(fileType_[0] == 0)
			return TarFileType.normal;
		else
			return cast(TarFileType) (fileType_[0] - '0');
	}

	///
	uint mode() {
		import core.stdc.stdlib;
		return cast(uint) strtoul(fileMode_.ptr, null, 8);
	}
}

/// There's other types but this is all I care about. You can still detect the char by `((cast(char) type) + '0')`
enum TarFileType {
	normal = 0, ///
	hardLink = 1, ///
	symLink = 2, ///
	characterSpecial = 3, ///
	blockSpecial = 4, ///
	directory = 5, ///
	fifo = 6 ///
}




/++
	Low level tar file processor. You must pass it a
	TarFileHeader buffer as well as a size_t for context.
	Both must be initialized to all zeroes on first call,
	then not modified in between calls.

	Each call must populate the dataBuffer with 512 bytes.

	returns true if still work to do.

	Please note that it currently only passes regular files, hard and soft links, and directories to your handler.

	History:
		[TarFileType.symLink] and [TarFileType.hardLink] used to be skipped by this function. On March 24, 2023, it was changed to send them to your `handleData` delegate too. The `data` argument to your handler will have the target of the link. Check `header.type` to know if it is a hard link, symbolic link, directory, normal file, or other special type (which are still currently skipped, but future proof yourself by either skipping or handling them now).
+/
bool processTar(
	TarFileHeader* header,
	long* bytesRemainingOnCurrentFile,
	const(ubyte)[] dataBuffer,
	scope void delegate(TarFileHeader* header, bool isNewFile, bool fileFinished, const(ubyte)[] data) handleData
)
{
	assert(dataBuffer.length == 512);
	assert(bytesRemainingOnCurrentFile !is null);
	assert(header !is null);

	if(*bytesRemainingOnCurrentFile) {
		bool isNew = *bytesRemainingOnCurrentFile == header.size();
		if(*bytesRemainingOnCurrentFile <= 512) {
			handleData(header, isNew, true, dataBuffer[0 .. cast(size_t) *bytesRemainingOnCurrentFile]);
			*bytesRemainingOnCurrentFile = 0;
		} else {
			handleData(header, isNew, false, dataBuffer[]);
			*bytesRemainingOnCurrentFile -= 512;
		}
	} else {
		*header = *(cast(TarFileHeader*) dataBuffer.ptr);
		auto s = header.size();
		*bytesRemainingOnCurrentFile = s;
		if(header.type() == TarFileType.directory)
			handleData(header, true, false, null);
		if(header.type() == TarFileType.hardLink || header.type() == TarFileType.symLink)
			handleData(header, true, true, cast(ubyte[]) header.linkFileName());
		if(s == 0 && header.type == TarFileType.normal)
			return false;
	}

	return true;
}

///
unittest {
/+
	void main() {
		TarFileHeader tfh;
		long size;

		import std.stdio;
		ubyte[512] buffer;
		foreach(chunk; File("/home/me/test/pl.tar", "r").byChunk(buffer[])) {
			processTar(&tfh, &size, buffer[],
			(header, isNewFile, fileFinished, data) {
				if(isNewFile)
					writeln("**** " , header.filename, " ", header.size);
				write(cast(string) data);
				if(fileFinished)
					writeln("+++++++++++++++");

			});
		}
	}

	main();
+/
}


// Advances data up to the end of the vla
ulong readVla(ref const(ubyte)[] data) {
	ulong n = 0;
	int i = 0;

	while (data[0] & 0x80) {
		ubyte b = data[0];
		data = data[1 .. $];

		assert(b != 0);
		if(b == 0) return 0;

		n |= cast(ulong)(b & 0x7F) << (i * 7);
		i++;
	}
	ubyte b = data[0];
	data = data[1 .. $];
	n |= cast(ulong)(b & 0x7F) << (i * 7);

	return n;
}

/++
	decompressLzma lzma (.xz file) decoder/decompressor that works by passed functions. Can be used as a higher-level alternative to [XzDecoder]. decompressGzip is  gzip (.gz file) decoder/decompresser) that works by passed functions. Can be used as an alternative to [std.zip], while using the same underlying zlib library.

	Params:
		chunkReceiver = a function that receives chunks of uncompressed data and processes them. Note that the chunk you receive will be overwritten once your function returns, so make sure you write it to a file or copy it to an outside array if you want to keep the data

		bufferFiller = a function that fills the provided buffer as much as you can, then returns the slice of the buffer you actually filled.

		chunkBuffer = an optional parameter providing memory that will be used to buffer uncompressed data chunks. If you pass `null`, it will allocate one for you. Any data in the buffer will be immediately overwritten.

		inputBuffer = an optional parameter providing memory that will hold compressed input data. If you pass `null`, it will allocate one for you. You should NOT populate this buffer with any data; it will be immediately overwritten upon calling this function. The `inputBuffer` must be at least 64 bytes in size.

		allowPartialChunks = can be set to true if you want `chunkReceiver` to be called as soon as possible, even if it is only partially full before the end of the input stream. The default is to fill the input buffer for every call to `chunkReceiver` except the last which has remainder data from the input stream.

	History:
		Added March 24, 2023 (dub v11.0)

		On October 25, 2024, the implementation got a major fix - it can read multiple blocks off the xz file now, were as before it would stop at the first one. This changed the requirement of the input buffer minimum size from 32 to 64 bytes (but it is always better to go more, I recommend 32 KB).
+/
version(WithLzmaDecoder)
void decompressLzma(scope void delegate(in ubyte[] chunk) chunkReceiver, scope ubyte[] delegate(ubyte[] buffer) bufferFiller, ubyte[] chunkBuffer = null, ubyte[] inputBuffer = null, bool allowPartialChunks = false) @trusted {
	if(chunkBuffer is null)
		chunkBuffer = new ubyte[](1024 * 32);
	if(inputBuffer is null)
		inputBuffer = new ubyte[](1024 * 32);

	assert(inputBuffer.length >= 64);

	bool isStartOfFile = true;

	const(ubyte)[] compressedData = bufferFiller(inputBuffer[]);

	XzDecoder decoder = XzDecoder(compressedData);

	compressedData = decoder.unprocessed;

	auto usableChunkBuffer = chunkBuffer;

	while(!decoder.finished) {
		auto newChunk = decoder.processData(usableChunkBuffer, compressedData);

		auto chunk = chunkBuffer[0 .. (newChunk.ptr - chunkBuffer.ptr) + newChunk.length];

		if(chunk.length && (decoder.finished || allowPartialChunks || chunk.length == chunkBuffer.length)) {
			chunkReceiver(chunk);
			usableChunkBuffer = chunkBuffer;
		} else if(!decoder.finished) {
			// if we're here we got a partial chunk
			usableChunkBuffer = chunkBuffer[chunk.length .. $];
		}

		if(decoder.needsMoreData) {
			import core.stdc.string;
			memmove(inputBuffer.ptr, decoder.unprocessed.ptr, decoder.unprocessed.length);

			auto newlyRead = bufferFiller(inputBuffer[decoder.unprocessed.length .. $]);
			assert(newlyRead.ptr >= inputBuffer.ptr && newlyRead.ptr < inputBuffer.ptr + inputBuffer.length);

			compressedData = inputBuffer[0 .. decoder.unprocessed.length + newlyRead.length];
		} else {
			compressedData = decoder.unprocessed;
		}
	}
}

/// ditto
void decompressGzip(scope void delegate(in ubyte[] chunk) chunkReceiver, scope ubyte[] delegate(ubyte[] buffer) bufferFiller, ubyte[] chunkBuffer = null, ubyte[] inputBuffer = null, bool allowPartialChunks = false) @trusted {

	import etc.c.zlib;

	if(chunkBuffer is null)
		chunkBuffer = new ubyte[](1024 * 32);
	if(inputBuffer is null)
		inputBuffer = new ubyte[](1024 * 32);

	const(ubyte)[] compressedData = bufferFiller(inputBuffer[]);

	z_stream zs;

	scope(exit)
		inflateEnd(&zs); // can return Z_STREAM_ERROR if state inconsistent

	int windowBits = 15 + 32; // determine header from data

	int err = inflateInit2(&zs, 15 + 32); // determine header from data
	if(err)
		throw ArsdException!"zlib"(err, zs.msg[0 .. 80].upToZero.idup); // FIXME: the 80 limit is arbitrary
	// zs.msg is also an error message string

	zs.next_in = compressedData.ptr;
	zs.avail_in = cast(uint) compressedData.length;

	while(true) {
		zs.next_out = chunkBuffer.ptr;
		zs.avail_out = cast(uint) chunkBuffer.length;

		fill_more_chunk:

		err = inflate(&zs, Z_NO_FLUSH);

		if(err == Z_OK || err == Z_STREAM_END || err == Z_BUF_ERROR) {
			import core.stdc.string;

			auto decompressed = chunkBuffer[0 .. chunkBuffer.length - zs.avail_out];

			// if the buffer is full, we always send a chunk.
			// partial chunks can be enabled, but we still will never send an empty chunk
			// if we're at the end of a stream, we always send the final chunk
			if(zs.avail_out == 0 || ((err == Z_STREAM_END || allowPartialChunks) && decompressed.length)) {
				chunkReceiver(decompressed);
			} else if(err != Z_STREAM_END) {
				// need more data to fill the next chunk
				if(zs.avail_in) {
					memmove(inputBuffer.ptr, zs.next_in, zs.avail_in);
				}
				auto newlyRead = bufferFiller(inputBuffer[zs.avail_in .. $ - zs.avail_in]);

				assert(newlyRead.ptr >= inputBuffer.ptr && newlyRead.ptr < inputBuffer.ptr + inputBuffer.length);

				zs.next_in = inputBuffer.ptr;
				zs.avail_in = cast(int) (zs.avail_in + newlyRead.length);

				if(zs.avail_out)
					goto fill_more_chunk;
			} else {
				assert(0, "progress impossible; your input buffer of compressed data might be too small");
			}

			if(err == Z_STREAM_END)
				break;
		} else {
			throw ArsdException!"zlib"(err, zs.msg[0 .. 80].upToZero.idup); // FIXME: the 80 limit is arbitrary
		}
	}
}



/// [decompressLzma] and [processTar] can be used together like this:
unittest {
/+
	import arsd.archive;

	void main() {
		import std.stdio;
		auto file = File("test.tar.xz");

		TarFileHeader tfh;
		long size;
		ubyte[512] tarBuffer;

		decompressLzma(
			(in ubyte[] chunk) => cast(void) processTar(&tfh, &size, chunk,
				(header, isNewFile, fileFinished, data) {
					if(isNewFile)
						writeln("**** " , header.filename, " ", header.size);
					//write(cast(string) data);
					if(fileFinished)
						writeln("+++++++++++++++");
				}),
			(ubyte[] buffer) => file.rawRead(buffer),
			tarBuffer[]
		);
	}
+/
}

/++
	A simple .xz file decoder.

	See the constructor and [processData] docs for details.

	You might prefer using [decompressLzma] for a higher-level api.

	FIXME: it doesn't implement very many checks, instead
	assuming things are what it expects. Don't use this without
	assertions enabled!
+/
version(WithLzmaDecoder)
struct XzDecoder {
	/++
		Start decoding by feeding it some initial data. You must
		send it at least enough bytes for the header (> 16 bytes prolly);
		try to send it a reasonably sized chunk.

		It sets `this.unprocessed` to be a slice of the *tail* of the `initialData`
		member, indicating leftover data after parsing the header. You will need to
		pass this to [processData] at least once to start decoding the data left over
		after the header. See [processData] for more information.
	+/
	this(const(ubyte)[] initialData) {

		ubyte[6] magic;

		magic[] = initialData[0 .. magic.length];
		initialData = initialData[magic.length .. $];

		if(cast(string) magic != "\xFD7zXZ\0")
			throw new Exception("not an xz file");

		ubyte[2] streamFlags = initialData[0 .. 2];
		initialData = initialData[2 .. $];

		// size of the check at the end in the footer. im just ignoring tbh
		checkSize = streamFlags[1] == 0 ? 0 : (4 << ((streamFlags[1]-1) / 3));

		//uint crc32 = initialData[0 .. 4]; // FIXME just cast it. this is the crc of the flags.
		initialData = initialData[4 .. $];

		state = State.readingHeader;
		readBlockHeader(initialData);
	}

	private enum State {
		readingHeader,
		readingData,
		readingFooter,
	}
	private State state;

	// returns true if it successfully read it, false if it needs more data
	private bool readBlockHeader(const(ubyte)[] initialData) {
		// now we are into an xz block...

		if(initialData.length == 0) {
			unprocessed = initialData;
			needsMoreData_ = true;
			finished_ = false;
			return false;
		}

		if(initialData[0] == 0) {
			// this is actually an index and a footer...
			// we could process it but this also really marks us being done!

			// FIXME: should actually pull the data out and finish it off
			// see Index records etc at https://tukaani.org/xz/xz-file-format.txt
			unprocessed = null;
			finished_ = true;
			needsMoreData_ = false;
			return true;
		}

		int blockHeaderSize = (initialData[0] + 1) * 4;

		auto first = initialData.ptr;

		if(blockHeaderSize > initialData.length) {
			unprocessed = initialData;
			needsMoreData_ = true;
			finished_ = false;
			return false;
		}

		auto srcPostHeader = initialData[blockHeaderSize .. $];

		initialData = initialData[1 .. $];

		ubyte blockFlags = initialData[0];
		initialData = initialData[1 .. $];

		if(blockFlags & 0x40) {
			compressedSize = readVla(initialData);
		} else {
			compressedSize = 0;
		}

		if(blockFlags & 0x80) {
			uncompressedSize = readVla(initialData);
		} else {
			uncompressedSize = 0;
		}

		//import std.stdio; writeln(compressedSize , " compressed, expands to ", uncompressedSize);

		auto filterCount = (blockFlags & 0b11) + 1;

		ubyte props;

		foreach(f; 0 .. filterCount) {
			auto fid = readVla(initialData);
			auto sz = readVla(initialData);

			// import std.stdio; writefln("%02x %d", fid, sz);
			assert(fid == 0x21);
			assert(sz == 1);

			props = initialData[0];
			initialData = initialData[1 .. $];
		}

		// writeln(initialData.ptr);
		// writeln(srcPostHeader.ptr);

		// there should be some padding to a multiple of 4...
		// three bytes of zeroes given the assumptions here

		assert(blockHeaderSize >= 4);
		long expectedRemainder = cast(long) blockHeaderSize - 4;
		expectedRemainder -= initialData.ptr - first;
		assert(expectedRemainder >= 0);

		while(expectedRemainder) {
			expectedRemainder--;
			if(initialData[0] != 0)
				throw new Exception("non-zero where padding byte expected in xz file");
			initialData = initialData[1 .. $];
		}

		// and then a header crc

		initialData = initialData[4 .. $]; // skip header crc

		assert(initialData.ptr is srcPostHeader.ptr);

		// skip unknown header bytes
		while(initialData.ptr < srcPostHeader.ptr) {
			initialData = initialData[1 .. $];
		}

		// should finally be at compressed data...

		//writeln(compressedSize);
		//writeln(uncompressedSize);

		if(Lzma2Dec_Allocate(&lzmaDecoder, props) != SRes.OK) {
			assert(0);
		}

		Lzma2Dec_Init(&lzmaDecoder);

		unprocessed = initialData;
		state = State.readingData;

		return true;
	}

	private bool readBlockFooter(const(ubyte)[] data) {
		// skip block padding
		while(data.length && data[0] == 0) {
			data = data[1 .. $];
		}

		if(data.length < checkSize) {
			unprocessed = data;
			finished_ = false;
			needsMoreData_ = true;
			return false;
		}

		// skip the check
		data = data[checkSize .. $];

		state = State.readingHeader;

		return readBlockHeader(data);
		//return true;
	}

	~this() {
		LzmaDec_FreeProbs(&lzmaDecoder.decoder);
	}

	/++
		Continues an in-progress decompression of the `src` data, putting it into the `dest` buffer.
		The `src` data must be at least 20 bytes long, but I'd recommend making it at larger.

		Returns the slice of the head of the `dest` buffer actually filled, then updates the following
		member variables of `XzDecoder`:

		$(LIST
			* [finished] will be `true` if the compressed data has been completely decompressed.
			* [needsMoreData] will be `true` if more src data was needed to fill the `dest` buffer. Note that you can also check this from the return value; if the return value's length is less than the destination buffer's length and the decoder is not finished, that means you needed more data to fill it.
			* And very importantly, [unprocessed] will contain a slice of the $(I tail of the `src` buffer) holding thus-far unprocessed data from the source buffer. This will almost always be set unless `dest` was big enough to hold the entire remaining uncompressed data.
		)

		This function will not modify the `src` buffer in any way. This is why the [unprocessed] member holds a slice to its tail - it is your own responsibility to decide how to proceed.

		If your `src` buffer contains the entire compressed file, you can pass `unprocessed` in a loop until finished:

		---
		static import std.file;
		auto compressedData = cast(immutable(ubyte)[]) std.file.read("file.xz"); // load it all into memory at once
		XzDecoder decoder = XzDecoder(compressedData);
		auto buffer = new ubyte[](4096); // to hold chunks of uncompressed data
		ubyte[] wholeUncompressedFile;
		while(!decoder.finished) {
			// it returns the slice of buffer with new data, so we can append that
			// to reconstruct the whole file. and then it sets `decoded.unprocessed` to
			// a slice of what is left out of the source file to continue processing in
			// the next iteration of the loop.
			wholeUncompressedFile ~= decoder.processData(buffer, decoder.unprocessed);
		}
		// wholeUncompressedFile is now fully populated
		---

		If you are reading from a file or some other streaming source, you may need to either move the unprocessed data back to the beginning of the buffer then load more into it, or copy it to a new, larger buffer and append more data then.

		---
		import std.stdio;
		auto file = File("file.xz");
		ubyte[] compressedDataBuffer = new ubyte[](1024 * 32);

		// read the first chunk. all modifications will be done through `compressedDataBuffer`
		// so we can make this part const for easier assignment to the slices `decoder.unprocessed` will hold
		const(ubyte)[] compressedData = file.rawRead(compressedDataBuffer);

		XzDecoder decoder = XzDecoder(compressedData);

		// need to keep what was unprocessed after construction
		compressedData = decoder.unprocessed;

		auto buffer = new ubyte[](4096); // to hold chunks of uncompressed data
		ubyte[] wholeUncompressedFile;
		while(!decoder.finished) {
			wholeUncompressedFile ~= decoder.processData(buffer, compressedData);

			if(decoder.needsMoreData) {
				// it needed more data to fill the buffer

				// first, move the unprocessed data bask to the head
				// you cannot necessarily use a D slice assign operator
				// because the `unprocessed` is a slice of the `compressedDataBuffer`,
				// meaning they might overlap. Instead, we'll use C's `memmove`
				import core.stdc.string;
				memmove(compressedDataBuffer.ptr, decoder.unprocessed.ptr, decoder.unprocessed.length);


				// now we can read more data to fill in the tail of the buffer again
				auto newlyRead = file.rawRead(compressedDataBuffer[decoder.unprocessed.length .. $]);

				// the new compressed data ready to process is what we moved from before,
				// now at the head of the buffer, plus what was just read, at the end of
				// the same buffer
				compressedData = compressedDataBuffer[0 .. decoder.unprocessed.length + newlyRead.length];
			} else {
				// otherwise, the output buffer was full, but there's probably
				// still more unprocessed data. Set it to be used on the next
				// loop iteration.
				compressedData = decoder.unprocessed;
			}
		}
		// wholeUncompressedFile is now fully populated
		---


	+/
	ubyte[] processData(ubyte[] dest, const(ubyte)[] src) {
		if(state == State.readingHeader) {
			if(!readBlockHeader(src))
				return dest[0 .. 0];
			src = unprocessed;
		}

		size_t destLen = dest.length;
		size_t srcLen = src.length;

		ELzmaStatus status;

		auto res = Lzma2Dec_DecodeToBuf(
			&lzmaDecoder,
			dest.ptr,
			&destLen,
			src.ptr,
			&srcLen,
			LZMA_FINISH_ANY,
			&status
		);

		if(res != 0) {
			throw ArsdException!"Lzma2Dec_DecodeToBuf"(res);
		}

		/+
		import std.stdio;
		writeln(res, " ", status);
		writeln(srcLen);
		writeln(destLen, ": ",  cast(string) dest[0 .. destLen]);
		+/

		if(status == LZMA_STATUS_NEEDS_MORE_INPUT) {
			unprocessed = src[srcLen .. $];
			finished_ = false;
			needsMoreData_ = true;
		} else if(status == LZMA_STATUS_FINISHED_WITH_MARK || status == LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK) {
			// this is the end of a block, but not necessarily the end of the file
			state = State.readingFooter;

			// the readBlockFooter function updates state, unprocessed, finished, and needs more data
			readBlockFooter(src[srcLen .. $]);
		} else if(status == LZMA_STATUS_NOT_FINISHED) {
			unprocessed = src[srcLen .. $];
			finished_ = false;
			needsMoreData_ = false;
		} else {
			// wtf
			throw ArsdException!"Unhandled LZMA_STATUS"(status);
		}

		return dest[0 .. destLen];
	}

	/++
		Returns true after [processData] has finished decoding the compressed data.
	+/
	bool finished() {
		return finished_;
	}

	/++
		After calling [processData], this will return `true` if more data is required to fill
		the destination buffer.

		Please note that `needsMoreData` can return `false` before decompression is completely
		[finished]; this would simply mean it satisfied the request to fill that one buffer.

		In this case, you will want to concatenate [unprocessed] with new data, then call [processData]
		again. Remember that [unprocessed] is a slice of the tail of the source buffer you passed to
		`processData`, so if you want to reuse the same buffer, you may want to `memmove` it to the
		head, then fill he tail again.
	+/
	bool needsMoreData() {
		return needsMoreData_;
	}

	private bool finished_;
	private bool needsMoreData_;

	CLzma2Dec lzmaDecoder;
	int checkSize;

	ulong compressedSize; ///
	ulong uncompressedSize; ///

	const(ubyte)[] unprocessed; ///
}

///
/+
version(WithLzmaDecoder)
unittest {

	void main() {
		ubyte[512] dest; // into tar size chunks!
		ubyte[1024] src;

		import std.stdio;

		//auto file = File("/home/me/test/amazing.txt.xz", "rb");
		auto file = File("/home/me/Android/ldcdl/test.tar.xz", "rb");
		auto bfr = file.rawRead(src[]);

		XzDecoder xzd = XzDecoder(bfr);

		// not necessarily set, don't rely on them
		writeln(xzd.compressedSize, " / ", xzd.uncompressedSize);

		// for tar
		TarFileHeader tfh;
		long size;

		long sum = 0;
		while(!xzd.finished) {
			// as long as your are not finished, there is more work to do. But it doesn't
			// necessarily need more data, so that is a separate check.
			if(xzd.needsMoreData) {
				// if it needs more data, append new stuff to the end of the buffer, after
				// the existing unprocessed stuff. If your buffer is too small, you may be
				// forced to grow it here, but anything >= 1 KB seems OK in my tests.
				bfr = file.rawRead(src[bfr.length - xzd.unprocessed.length .. $]);
			} else {
				// otherwise, you want to continue working with existing unprocessed data
				bfr = cast(ubyte[]) xzd.unprocessed;
			}
			//write(cast(string) xzd.processData(dest[], bfr));

			auto buffer = xzd.processData(dest[], bfr);

			// if the buffer is empty we are probably done
			// or need more data, so continue the loop to evaluate.
			if(buffer.length == 0)
				continue;

			// our tar code requires specifically 512 byte pieces
			while(!xzd.finished && buffer.length != 512) {
				// need more data hopefully
				assert(xzd.needsMoreData);
				// using the existing buffer...
				bfr = file.rawRead(src[bfr.length - xzd.unprocessed.length .. $]);
				auto nbuffer = xzd.processData(dest[buffer.length .. $], bfr);
				buffer = dest[0 .. buffer.length + nbuffer.length];
			}

			sum += buffer.length;

			// process the buffer through the tar file handler
			processTar(&tfh, &size, buffer[],
			(header, isNewFile, fileFinished, data) {
				if(isNewFile)
					writeln("**** " , header.filename, " ", header.size);
				//write(cast(string) data);
				if(fileFinished)
					writeln("+++++++++++++++");

			});
		}

		writeln(sum);
	}

	main();
}
+/

version(WithArczCode) {
/* The code in this section was originally written by Ketmar Dark for his arcz.d module. I modified it afterward. */

/** ARZ chunked archive format processor.
 *
 * This module provides `std.stdio.File`-like interface to ARZ archives.
 *
 * Copyright: Copyright Ketmar Dark, 2016
 *
 * License: Boost License 1.0
 */
// module iv.arcz;

// use Balz compressor if available
static if (__traits(compiles, { import iv.balz; })) enum arcz_has_balz = true; else enum arcz_has_balz = false;
static if (__traits(compiles, { import iv.zopfli; })) enum arcz_has_zopfli = true; else enum arcz_has_zopfli = false;
static if (arcz_has_balz) import iv.balz;
static if (arcz_has_zopfli) import iv.zopfli;

// comment this to free pakced chunk buffer right after using
// i.e. `AZFile` will allocate new block for each new chunk
//version = arcz_use_more_memory;

public import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;


// ////////////////////////////////////////////////////////////////////////// //
/// ARZ archive accessor. Use this to open ARZ archives, and open packed files from ARZ archives.
public struct ArzArchive {
private:
  static assert(size_t.sizeof >= (void*).sizeof);
  private import core.stdc.stdio : FILE, fopen, fclose, fread, fseek;
  private import etc.c.zlib;

  static struct ChunkInfo {
    uint ofs; // offset in file
    uint pksize; // packed chunk size (same as chunk size: chunk is unpacked)
  }

  static struct FileInfo {
    string name;
    uint chunk;
    uint chunkofs; // offset of first file byte in unpacked chunk
    uint size; // unpacked file size
  }

  static struct Nfo {
    uint rc = 1; // refcounter
    ChunkInfo[] chunks;
    FileInfo[string] files;
    uint chunkSize;
    uint lastChunkSize;
    bool useBalz;
    FILE* afl; // archive file, we'll keep it opened

    @disable this (this); // no copies!

    static void decRef (size_t me) {
      if (me) {
        auto nfo = cast(Nfo*)me;
        assert(nfo.rc);
        if (--nfo.rc == 0) {
          import core.memory : GC;
          // import core.stdc.stdlib : free;
          if (nfo.afl !is null) fclose(nfo.afl);
          nfo.chunks.destroy;
          nfo.files.destroy;
          nfo.afl = null;
          GC.removeRange(cast(void*)nfo/*, Nfo.sizeof*/);
          xfree(nfo);
          debug(arcz_rc) { import core.stdc.stdio : printf; printf("Nfo %p freed\n", nfo); }
        }
      }
    }
  }

  size_t nfop; // hide it from GC

  private @property Nfo* nfo () { pragma(inline, true); return cast(Nfo*)nfop; }
  void decRef () { pragma(inline, true); Nfo.decRef(nfop); nfop = 0; }

  static uint readUint (FILE* fl) {
    if (fl is null) throw new Exception("cannot read from closed file");
    uint v;
    if (fread(&v, 1, v.sizeof, fl) != v.sizeof) throw new Exception("file reading error");
    version(BigEndian) {
      import core.bitop : bswap;
      v = bswap(v);
    } else version(LittleEndian) {
      // nothing to do
    } else {
      static assert(0, "wtf?!");
    }
    return v;
  }

  static uint readUbyte (FILE* fl) {
    if (fl is null) throw new Exception("cannot read from closed file");
    ubyte v;
    if (fread(&v, 1, v.sizeof, fl) != v.sizeof) throw new Exception("file reading error");
    return v;
  }

  static void readBuf (FILE* fl, void[] buf) {
    if (buf.length > 0) {
      if (fl is null) throw new Exception("cannot read from closed file");
      if (fread(buf.ptr, 1, buf.length, fl) != buf.length) throw new Exception("file reading error");
    }
  }

  static T* xalloc(T, bool clear=true) (uint mem) if (T.sizeof > 0) {
    import core.memory;
    import core.exception : onOutOfMemoryError;
    assert(mem != 0);
    static if (clear) {
      // import core.stdc.stdlib : calloc;
      // auto res = calloc(mem, T.sizeof);
      auto res = GC.calloc(mem * T.sizeof, GC.BlkAttr.NO_SCAN);
      if (res is null) onOutOfMemoryError();
      static if (is(T == struct)) {
        import core.stdc.string : memcpy;
        static immutable T i = T.init;
        foreach (immutable idx; 0..mem) memcpy(res+idx, &i, T.sizeof);
      }
      debug(arcz_alloc) { import core.stdc.stdio : printf; printf("allocated %u bytes at %p\n", cast(uint)(mem*T.sizeof), res); }
      debug(arcz_alloc) { try { throw new Exception("mem trace c"); } catch(Exception e) { import std.stdio; writeln(e.toString()); } }
      return cast(T*)res;
    } else {
      //import core.stdc.stdlib : malloc;
      //auto res = malloc(mem*T.sizeof);
      auto res = GC.malloc(mem*T.sizeof, GC.BlkAttr.NO_SCAN);
      if (res is null) onOutOfMemoryError();
      static if (is(T == struct)) {
        import core.stdc.string : memcpy;
        static immutable T i = T.init;
        foreach (immutable idx; 0..mem) memcpy(res+idx, &i, T.sizeof);
      }
      debug(arcz_alloc) { import core.stdc.stdio : printf; printf("allocated %u bytes at %p\n", cast(uint)(mem*T.sizeof), res); }
      debug(arcz_alloc) { try { throw new Exception("mem trace"); } catch(Exception e) { import std.stdio; writeln(e.toString()); } }
      return cast(T*)res;
    }
  }

  static void xfree(T) (T* ptr) {
    // just let the GC do it
    if(ptr !is null) {
        import core.memory;
        GC.free(ptr);
    }


    /+
    if (ptr !is null) {
      import core.stdc.stdlib : free;
      debug(arcz_alloc) { import core.stdc.stdio : printf; printf("freing at %p\n", ptr); }
      free(ptr);
    }
    +/
  }

  static if (arcz_has_balz) static ubyte balzDictSize (uint blockSize) {
    foreach (ubyte bits; Balz.MinDictBits..Balz.MaxDictBits+1) {
      if ((1U<<bits) >= blockSize) return bits;
    }
    return Balz.MaxDictBits;
  }

  // unpack exactly `destlen` bytes
  static if (arcz_has_balz) static void unpackBlockBalz (void* dest, uint destlen, const(void)* src, uint srclen, uint blocksize) {
    Unbalz bz;
    bz.reinit(balzDictSize(blocksize));
    int ipos, opos;
    auto dc = bz.decompress(
      // reader
      (buf) {
        import core.stdc.string : memcpy;
        if (ipos >= srclen) return 0;
        uint rd = destlen-ipos;
        if (rd > buf.length) rd = cast(uint)buf.length;
        memcpy(buf.ptr, src+ipos, rd);
        ipos += rd;
        return rd;
      },
      // writer
      (buf) {
        //if (opos+buf.length > destlen) throw new Exception("error unpacking archive");
        uint wr = destlen-opos;
        if (wr > buf.length) wr = cast(uint)buf.length;
        if (wr > 0) {
          import core.stdc.string : memcpy;
          memcpy(dest+opos, buf.ptr, wr);
          opos += wr;
        }
      },
      // unpack length
      destlen
    );
    if (opos != destlen) throw new Exception("error unpacking archive");
  }

  static void unpackBlockZLib (void* dest, uint destlen, const(void)* src, uint srclen, uint blocksize) {
    z_stream zs;
    zs.avail_in = 0;
    zs.avail_out = 0;
    // initialize unpacker
    if (inflateInit2(&zs, 15) != Z_OK) throw new Exception("can't initialize zlib");
    scope(exit) inflateEnd(&zs);
    zs.next_in = cast(typeof(zs.next_in))src;
    zs.avail_in = srclen;
    zs.next_out = cast(typeof(zs.next_out))dest;
    zs.avail_out = destlen;
    while (zs.avail_out > 0) {
      auto err = inflate(&zs, Z_SYNC_FLUSH);
      if (err != Z_STREAM_END && err != Z_OK) throw new Exception("error unpacking archive");
      if (err == Z_STREAM_END) break;
    }
    if (zs.avail_out != 0) throw new Exception("error unpacking archive");
  }

  static void unpackBlock (void* dest, uint destlen, const(void)* src, uint srclen, uint blocksize, bool useBalz) {
    if (useBalz) {
      static if (arcz_has_balz) {
        unpackBlockBalz(dest, destlen, src, srclen, blocksize);
      } else {
        throw new Exception("no Balz support was compiled in ArcZ");
      }
    } else {
      unpackBlockZLib(dest, destlen, src, srclen, blocksize);
    }
  }

public:
  this (in ArzArchive arc) {
    assert(nfop == 0);
    nfop = arc.nfop;
    if (nfop) ++nfo.rc;
  }

  this (this) {
    if (nfop) ++nfo.rc;
  }

  ~this () { close(); }

  void opAssign (in ArzArchive arc) {
    if (arc.nfop) {
      auto n = cast(Nfo*)arc.nfop;
      ++n.rc;
    }
    decRef();
    nfop = arc.nfop;
  }

  void close () { decRef(); }

  @property FileInfo[string] files () { return (nfop ? nfo.files : null); }

  void openArchive (const(char)[] filename) {
    debug/*(arcz)*/ import core.stdc.stdio : printf;
    FILE* fl = null;
    scope(exit) if (fl !is null) fclose(fl);
    close();
    if (filename.length == 0) throw new Exception("cannot open unnamed archive file");
    if (false && filename.length < 2048) { // FIXME the alloca fails on win64 for some reason
      import core.stdc.stdlib : alloca;
      auto tfn = (cast(char*)alloca(filename.length+1))[0..filename.length+1];
      tfn[0..filename.length] = filename[];
      tfn[filename.length] = 0;
      fl = fopen(tfn.ptr, "rb");
    } else {
      import core.stdc.stdlib : malloc, free;
      auto tfn = (cast(char*)malloc(filename.length+1))[0..filename.length+1];
      if (tfn !is null) {
      	tfn[0 .. filename.length] = filename[];
	tfn[filename.length] = 0;
        scope(exit) free(tfn.ptr);
        fl = fopen(tfn.ptr, "rb");
      }
    }
    if (fl is null) throw new Exception("cannot open archive file '"~filename.idup~"'");
    char[4] sign;
    bool useBalz;
    readBuf(fl, sign[]);
    if (sign != "CZA2") throw new Exception("invalid archive file '"~filename.idup~"'");
    switch (readUbyte(fl)) {
      case 0: useBalz = false; break;
      case 1: useBalz = true; break;
      default: throw new Exception("invalid version of archive file '"~filename.idup~"'");
    }
    uint indexofs = readUint(fl); // index offset in file
    uint pkidxsize = readUint(fl); // packed index size
    uint idxsize = readUint(fl); // unpacked index size
    if (pkidxsize == 0 || idxsize == 0 || indexofs == 0) throw new Exception("invalid archive file '"~filename.idup~"'");
    // now read index
    ubyte* idxbuf = null;
    scope(exit) xfree(idxbuf);
    {
      auto pib = xalloc!ubyte(pkidxsize);
      scope(exit) xfree(pib);
      if (fseek(fl, indexofs, 0) < 0) throw new Exception("seek error in archive file '"~filename.idup~"'");
      readBuf(fl, pib[0..pkidxsize]);
      idxbuf = xalloc!ubyte(idxsize);
      unpackBlock(idxbuf, idxsize, pib, pkidxsize, idxsize, useBalz);
    }

    // parse index and build structures
    uint idxbufpos = 0;

    ubyte getUbyte () {
      if (idxsize-idxbufpos < ubyte.sizeof) throw new Exception("invalid index for archive file '"~filename.idup~"'");
      return idxbuf[idxbufpos++];
    }

    uint getUint () {
      if (idxsize-idxbufpos < uint.sizeof) throw new Exception("invalid index for archive file '"~filename.idup~"'");
      version(BigEndian) {
        import core.bitop : bswap;
        uint v = *cast(uint*)(idxbuf+idxbufpos);
        idxbufpos += 4;
        return bswap(v);
      } else version(LittleEndian) {
        uint v = *cast(uint*)(idxbuf+idxbufpos);
        idxbufpos += 4;
        return v;
      } else {
        static assert(0, "wtf?!");
      }
    }

    void getBuf (void[] buf) {
      if (buf.length > 0) {
        import core.stdc.string : memcpy;
        if (idxsize-idxbufpos < buf.length) throw new Exception("invalid index for archive file '"~filename.idup~"'");
        memcpy(buf.ptr, idxbuf+idxbufpos, buf.length);
        idxbufpos += buf.length;
      }
    }

    // allocate shared info struct
    Nfo* nfo = xalloc!Nfo(1);
    assert(nfo.rc == 1);
    debug(arcz_rc) { import core.stdc.stdio : printf; printf("Nfo %p allocated\n", nfo); }
    scope(failure) decRef();
    nfop = cast(size_t)nfo;
    {
      import core.memory : GC;
      GC.addRange(nfo, Nfo.sizeof);
    }

    // read chunk info and data
    nfo.useBalz = useBalz;
    nfo.chunkSize = getUint;
    auto ccount = getUint; // chunk count
    nfo.lastChunkSize = getUint;
    debug(arcz_dirread) printf("chunk size: %u\nchunk count: %u\nlast chunk size:%u\n", nfo.chunkSize, ccount, nfo.lastChunkSize);
    if (ccount == 0 || nfo.chunkSize < 1 || nfo.lastChunkSize < 1 || nfo.lastChunkSize > nfo.chunkSize) throw new Exception("invalid archive file '"~filename.idup~"'");
    nfo.chunks.length = ccount;
    // chunk offsets and sizes
    foreach (ref ci; nfo.chunks) {
      ci.ofs = getUint;
      ci.pksize = getUint;
    }
    // read file count and info
    auto fcount = getUint;
    if (fcount == 0) throw new Exception("empty archive file '"~filename.idup~"'");
    // calc name buffer position and size
    //immutable uint nbofs = idxbufpos+fcount*(5*4);
    //if (nbofs >= idxsize) throw new Exception("invalid index in archive file '"~filename.idup~"'");
    //immutable uint nbsize = idxsize-nbofs;
    debug(arcz_dirread) printf("file count: %u\n", fcount);
    foreach (immutable _; 0..fcount) {
      uint nameofs = getUint;
      uint namelen = getUint;
      if (namelen == 0) {
        // skip unnamed file
        //throw new Exception("invalid archive file '"~filename.idup~"'");
        getUint; // chunk number
        getUint; // offset in chunk
        getUint; // unpacked size
        debug(arcz_dirread) printf("skipped empty file\n");
      } else {
        //if (nameofs >= nbsize || namelen > nbsize || nameofs+namelen > nbsize) throw new Exception("invalid index in archive file '"~filename.idup~"'");
        if (nameofs >= idxsize || namelen > idxsize || nameofs+namelen > idxsize) throw new Exception("invalid index in archive file '"~filename.idup~"'");
        FileInfo fi;
        auto nb = new char[](namelen);
        nb[0..namelen] = (cast(char*)idxbuf)[nameofs..nameofs+namelen];
        fi.name = cast(string)(nb); // it is safe here
        fi.chunk = getUint; // chunk number
        fi.chunkofs = getUint; // offset in chunk
        fi.size = getUint; // unpacked size
        debug(arcz_dirread) printf("file size: %u\nfile chunk: %u\noffset in chunk:%u; name: [%.*s]\n", fi.size, fi.chunk, fi.chunkofs, cast(uint)fi.name.length, fi.name.ptr);
        nfo.files[fi.name] = fi;
      }
    }
    // transfer achive file ownership
    nfo.afl = fl;
    fl = null;
  }

  bool exists (const(char)[] name) { if (nfop) return ((name in nfo.files) !is null); else return false; }

  AZFile open (const(char)[] name) {
    if (!nfop) throw new Exception("can't open file from non-opened archive");
    if (auto fi = name in nfo.files) {
      auto zl = xalloc!LowLevelPackedRO(1);
      scope(failure) xfree(zl);
      debug(arcz_rc) { import core.stdc.stdio : printf; printf("Zl %p allocated\n", zl); }
      zl.setup(nfo, fi.chunk, fi.chunkofs, fi.size);
      AZFile fl;
      fl.zlp = cast(size_t)zl;
      return fl;
    }
    throw new Exception("can't open file '"~name.idup~"' from archive");
  }

private:
  static struct LowLevelPackedRO {
    private import etc.c.zlib;

    uint rc = 1;
    size_t nfop; // hide it from GC

    private @property inout(Nfo*) nfo () inout pure nothrow @trusted @nogc { pragma(inline, true); return cast(typeof(return))nfop; }
    static void decRef (size_t me) {
      if (me) {
        auto zl = cast(LowLevelPackedRO*)me;
        assert(zl.rc);
        if (--zl.rc == 0) {
          //import core.stdc.stdlib : free;
          if (zl.chunkData !is null) xfree(zl.chunkData);
          version(arcz_use_more_memory) if (zl.pkdata !is null) xfree(zl.pkdata);
          Nfo.decRef(zl.nfop);
          xfree(zl);
          debug(arcz_rc) { import core.stdc.stdio : printf; printf("Zl %p freed\n", zl); }
        } else {
          //debug(arcz_rc) { import core.stdc.stdio : printf; printf("Zl %p; rc after decRef is %u\n", zl, zl.rc); }
        }
      }
    }

    uint nextchunk; // next chunk to read
    uint curcpos; // position in current chunk
    uint curcsize; // number of valid bytes in `chunkData`
    uint stchunk; // starting chunk
    uint stofs; // offset in starting chunk
    uint totalsize; // total file size
    uint pos; // current file position
    uint lastrdpos; // last actual read position
    z_stream zs;
    ubyte* chunkData; // can be null
    version(arcz_use_more_memory) {
      ubyte* pkdata;
      uint pkdatasize;
    }

    @disable this (this);

    void setup (Nfo* anfo, uint astchunk, uint astofs, uint asize) {
      assert(anfo !is null);
      assert(rc == 1);
      nfop = cast(size_t)anfo;
      ++anfo.rc;
      nextchunk = stchunk = astchunk;
      //curcpos = 0;
      stofs = astofs;
      totalsize = asize;
    }

    @property bool eof () { pragma(inline, true); return (pos >= totalsize); }

    // return less than chunk size if our file fits in one non-full chunk completely
    uint justEnoughMemory () pure const nothrow @safe @nogc {
      pragma(inline, true);
      version(none) {
        return nfo.chunkSize;
      } else {
        return (totalsize < nfo.chunkSize && stofs+totalsize < nfo.chunkSize ? stofs+totalsize : nfo.chunkSize);
      }
    }

    void unpackNextChunk () @system {
      if (nfop == 0) assert(0, "wtf?!");
      //scope(failure) if (chunkData !is null) { xfree(chunkData); chunkData = null; }
      debug(arcz_unp) { import core.stdc.stdio : printf; printf("unpacking chunk %u\n", nextchunk); }
      // allocate buffer for unpacked data
      if (chunkData is null) {
        // optimize things a little: if our file fits in less then one chunk, allocate "just enough" memory
        chunkData = xalloc!(ubyte, false)(justEnoughMemory);
      }
      auto chunk = &nfo.chunks[nextchunk];
      if (chunk.pksize == nfo.chunkSize) {
        // unpacked chunk, just read it
        debug(arcz_unp) { import core.stdc.stdio : printf; printf(" chunk is not packed\n"); }
        if (fseek(nfo.afl, chunk.ofs, 0) < 0) throw new Exception("ARCZ reading error");
        if (fread(chunkData, 1, nfo.chunkSize, nfo.afl) != nfo.chunkSize) throw new Exception("ARCZ reading error");
        curcsize = nfo.chunkSize;
      } else {
        // packed chunk, unpack it
        // allocate buffer for packed data
        version(arcz_use_more_memory) {
          import core.stdc.stdlib : realloc;
          if (pkdatasize < chunk.pksize) {
            import core.exception : onOutOfMemoryError;
            auto newpk = realloc(pkdata, chunk.pksize);
            if (newpk is null) onOutOfMemoryError();
            debug(arcz_alloc) { import core.stdc.stdio : printf; printf("reallocated from %u to %u bytes; %p -> %p\n", cast(uint)pkdatasize, cast(uint)chunk.pksize, pkdata, newpk); }
            pkdata = cast(ubyte*)newpk;
            pkdatasize = chunk.pksize;
          }
          alias pkd = pkdata;
        } else {
          auto pkd = xalloc!(ubyte, false)(chunk.pksize);
          scope(exit) xfree(pkd);
        }
        if (fseek(nfo.afl, chunk.ofs, 0) < 0) throw new Exception("ARCZ reading error");
        if (fread(pkd, 1, chunk.pksize, nfo.afl) != chunk.pksize) throw new Exception("ARCZ reading error");
        uint upsize = (nextchunk == nfo.chunks.length-1 ? nfo.lastChunkSize : nfo.chunkSize); // unpacked chunk size
        immutable uint cksz = upsize;
        immutable uint jem = justEnoughMemory;
        if (upsize > jem) upsize = jem;
        debug(arcz_unp) { import core.stdc.stdio : printf; printf(" unpacking %u bytes to %u bytes\n", chunk.pksize, upsize); }
        ArzArchive.unpackBlock(chunkData, upsize, pkd, chunk.pksize, cksz, nfo.useBalz);
        curcsize = upsize;
      }
      curcpos = 0;
      // fix first chunk offset if necessary
      if (nextchunk == stchunk && stofs > 0) {
        // it's easier to just memmove it
        import core.stdc.string : memmove;
        assert(stofs < curcsize);
        memmove(chunkData, chunkData+stofs, curcsize-stofs);
        curcsize -= stofs;
      }
      ++nextchunk; // advance to next chunk
    }

    void syncReadPos () {
      if (pos >= totalsize || pos == lastrdpos) return;
      immutable uint fcdata = nfo.chunkSize-stofs; // number of our bytes in the first chunk
      // does our pos lie in the first chunk?
      if (pos < fcdata) {
        // yep, just read it
        if (nextchunk != stchunk+1) {
          nextchunk = stchunk;
          unpackNextChunk(); // we'll need it anyway
        } else {
          // just rewind
          curcpos = 0;
        }
        curcpos += pos;
        lastrdpos = pos;
        return;
      }
      // find the chunk we want
      uint npos = pos-fcdata;
      uint xblock = stchunk+1+npos/nfo.chunkSize;
      uint curcstart = (xblock-(stchunk+1))*nfo.chunkSize+fcdata;
      if (xblock != nextchunk-1) {
        // read and unpack this chunk
        nextchunk = xblock;
        unpackNextChunk();
      } else {
        // just rewind
        curcpos = 0;
      }
      assert(pos >= curcstart && pos < curcstart+nfo.chunkSize);
      uint skip = pos-curcstart;
      lastrdpos = pos;
      curcpos += skip;
    }

    int read (void* buf, uint count) @system {
      if (buf is null) return -1;
      if (count == 0 || totalsize == 0) return 0;
      if (totalsize >= 0 && pos >= totalsize) return 0; // EOF
      syncReadPos();
      assert(lastrdpos == pos);
      if (cast(long)pos+count > totalsize) count = totalsize-pos;
      auto res = count;
      while (count > 0) {
        debug(arcz_read) { import core.stdc.stdio : printf; printf("reading %u bytes; pos=%u; lastrdpos=%u; curcpos=%u; curcsize=%u\n", count, pos, lastrdpos, curcpos, curcsize); }
        import core.stdc.string : memcpy;
        if (curcpos >= curcsize) {
          unpackNextChunk(); // we want next chunk!
          debug(arcz_read) { import core.stdc.stdio : printf; printf(" *reading %u bytes; pos=%u; lastrdpos=%u; curcpos=%u; curcsize=%u\n", count, pos, lastrdpos, curcpos, curcsize); }
        }
        assert(curcpos < curcsize && curcsize != 0);
        int rd = (curcsize-curcpos >= count ? count : curcsize-curcpos);
        assert(rd > 0);
        memcpy(buf, chunkData+curcpos, rd);
        curcpos += rd;
        pos += rd;
        lastrdpos += rd;
        buf += rd;
        count -= rd;
      }
      assert(pos == lastrdpos);
      return res;
    }

    long lseek (long ofs, int origin) {
      //TODO: overflow checks
      switch (origin) {
        case SEEK_SET: break;
        case SEEK_CUR: ofs += pos; break;
        case SEEK_END:
          if (ofs > 0) ofs = 0;
          if (-ofs > totalsize) ofs = -cast(long)totalsize;
          ofs += totalsize;
          break;
        default:
          return -1;
      }
      if (ofs < 0) return -1;
      if (totalsize >= 0 && ofs > totalsize) ofs = totalsize;
      pos = cast(uint)ofs;
      return pos;
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
/// Opened file.
public struct AZFile {
private:
  size_t zlp;

  private @property inout(ArzArchive.LowLevelPackedRO)* zl () inout pure nothrow @trusted @nogc { pragma(inline, true); return cast(typeof(return))zlp; }
  private void decRef () { pragma(inline, true); ArzArchive.LowLevelPackedRO.decRef(zlp); zlp = 0; }

public:
  this (in AZFile afl) {
    assert(zlp == 0);
    zlp = afl.zlp;
    if (zlp) ++zl.rc;
  }

  this (this) {
    if (zlp) ++zl.rc;
  }

  ~this () { close(); }

  void opAssign (in AZFile afl) {
    if (afl.zlp) {
      auto n = cast(ArzArchive.LowLevelPackedRO*)afl.zlp;
      ++n.rc;
    }
    decRef();
    zlp = afl.zlp;
  }

  void close () { decRef(); }

  @property bool isOpen () const pure nothrow @safe @nogc { pragma(inline, true); return (zlp != 0); }
  @property uint size () const pure nothrow @safe @nogc { pragma(inline, true); return (zlp ? zl.totalsize : 0); }
  @property uint tell () const pure nothrow @safe @nogc { pragma(inline, true); return (zlp ? zl.pos : 0); }

  void seek (long ofs, int origin=SEEK_SET) {
    if (!zlp) throw new Exception("can't seek in closed file");
    auto res = zl.lseek(ofs, origin);
    if (res < 0) throw new Exception("seek error");
  }

  //TODO: overflow check
  T[] rawRead(T) (T[] buf) {
    if (!zlp) throw new Exception("can't read from closed file");
    if (buf.length > 0) {
      auto res = zl.read(buf.ptr, cast(int) (buf.length*T.sizeof));
      if (res == -1 || res%T.sizeof != 0) throw new Exception("read error");
      return buf[0..res/T.sizeof];
    } else {
      return buf[0..0];
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
/** this class can be used to create archive file.
 *
 * Example:
 * --------------------
 *  import std.file, std.path, std.stdio : File;
 *
 *  enum ArcName = "z00.arz";
 *  enum DirName = "experimental-docs";
 *
 *  ubyte[] rdbuf;
 *  rdbuf.length = 65536;
 *
 *  auto arcz = new ArzCreator(ArcName);
 *  long total = 0;
 *  foreach (DirEntry e; dirEntries(DirName, SpanMode.breadth)) {
 *    if (e.isFile) {
 *      assert(e.size < uint.max);
 *      //writeln(e.name);
 *      total += e.size;
 *      string fname = e.name[DirName.length+1..$];
 *      arcz.newFile(fname, cast(uint)e.size);
 *      auto fi = File(e.name);
 *      for (;;) {
 *        auto rd = fi.rawRead(rdbuf[]);
 *        if (rd.length == 0) break;
 *        arcz.rawWrite(rd[]);
 *      }
 *    }
 *  }
 *  arcz.close();
 *  writeln(total, " bytes packed to ", getSize(ArcName), " (", arcz.chunksWritten, " chunks, ", arcz.filesWritten, " files)");
 * --------------------
 */
final class ArzCreator {
private import etc.c.zlib;
private import core.stdc.stdio : FILE, fopen, fclose, ftell, fseek, fwrite;

public:
  //WARNING! don't change the order!
  enum Compressor {
    ZLib, // default
    Balz,
    BalzMax, // Balz, maximum compression
    Zopfli, // this will fallback to zlib if no zopfli support was compiled in
  }

private:
  static struct ChunkInfo {
    uint ofs; // offset in file
    uint pksize; // packed chunk size
  }

  static struct FileInfo {
    string name;
    uint chunk;
    uint chunkofs; // offset of first file byte in unpacked chunk
    uint size; // unpacked file size
  }

private:
  ubyte[] chunkdata;
  uint cdpos;
  FILE* arcfl;
  ChunkInfo[] chunks;
  FileInfo[] files;
  uint lastChunkSize;
  uint statChunks, statFiles;
  Compressor cpr = Compressor.ZLib;

private:
  void writeUint (uint v) {
    if (arcfl is null) throw new Exception("write error");
    version(BigEndian) {
      import core.bitop : bswap;
      v = bswap(v);
    } else version(LittleEndian) {
      // nothing to do
    } else {
      static assert(0, "wtf?!");
    }
    if (fwrite(&v, 1, v.sizeof, arcfl) != v.sizeof) throw new Exception("write error"); // signature
  }

  void writeUbyte (ubyte v) {
    if (arcfl is null) throw new Exception("write error");
    if (fwrite(&v, 1, v.sizeof, arcfl) != v.sizeof) throw new Exception("write error"); // signature
  }

  void writeBuf (const(void)[] buf) {
    if (buf.length > 0) {
      if (arcfl is null) throw new Exception("write error");
      if (fwrite(buf.ptr, 1, buf.length, arcfl) != buf.length) throw new Exception("write error"); // signature
    }
  }

  static if (arcz_has_balz) long writePackedBalz (const(void)[] upbuf) {
    assert(upbuf.length > 0 && upbuf.length < int.max);
    long res = 0;
    Balz bz;
    int ipos, opos;
    bz.reinit(ArzArchive.balzDictSize(cast(uint)upbuf.length));
    bz.compress(
      // reader
      (buf) {
        import core.stdc.string : memcpy;
        if (ipos >= upbuf.length) return 0;
        uint rd = cast(uint)upbuf.length-ipos;
        if (rd > buf.length) rd = cast(uint)buf.length;
        memcpy(buf.ptr, upbuf.ptr+ipos, rd);
        ipos += rd;
        return rd;
      },
      // writer
      (buf) {
        res += buf.length;
        writeBuf(buf[]);
      },
      // max mode
      (cpr == Compressor.BalzMax)
    );
    return res;
  }

  static if (arcz_has_zopfli) long writePackedZopfli (const(void)[] upbuf) {
    ubyte[] indata;
    void* odata;
    size_t osize;
    ZopfliOptions opts;
    ZopfliCompress(opts, ZOPFLI_FORMAT_ZLIB, upbuf.ptr, upbuf.length, &odata, &osize);
    writeBuf(odata[0..osize]);
    ZopfliFree(odata);
    return cast(long)osize;
  }

  long writePackedZLib (const(void)[] upbuf) {
    assert(upbuf.length > 0 && upbuf.length < int.max);
    long res = 0;
    z_stream zs;
    ubyte[2048] obuf;
    zs.next_out = obuf.ptr;
    zs.avail_out = cast(uint)obuf.length;
    zs.next_in = null;
    zs.avail_in = 0;
    // initialize packer
    if (deflateInit2(&zs, Z_BEST_COMPRESSION, Z_DEFLATED, 15, 9, 0) != Z_OK) throw new Exception("can't write packed data");
    scope(exit) deflateEnd(&zs);
    zs.next_in = cast(typeof(zs.next_in))upbuf.ptr;
    zs.avail_in = cast(uint)upbuf.length;
    while (zs.avail_in > 0) {
      if (zs.avail_out == 0) {
        res += cast(uint)obuf.length;
        writeBuf(obuf[]);
        zs.next_out = obuf.ptr;
        zs.avail_out = cast(uint)obuf.length;
      }
      auto err = deflate(&zs, Z_NO_FLUSH);
      if (err != Z_OK) throw new Exception("zlib compression error");
    }
    while (zs.avail_out != obuf.length) {
      res += cast(uint)obuf.length-zs.avail_out;
      writeBuf(obuf[0..$-zs.avail_out]);
      zs.next_out = obuf.ptr;
      zs.avail_out = cast(uint)obuf.length;
      auto err = deflate(&zs, Z_FINISH);
      if (err != Z_OK && err != Z_STREAM_END) throw new Exception("zlib compression error");
      // succesfully flushed?
      //if (err != Z_STREAM_END) throw new VFSException("zlib compression error");
    }
    return res;
  }

  // return size of packed data written
  uint writePackedBuf (const(void)[] upbuf) {
    assert(upbuf.length > 0 && upbuf.length < int.max);
    long res = 0;
    final switch (cpr) {
      case Compressor.ZLib:
        res = writePackedZLib(upbuf);
        break;
      case Compressor.Balz:
      case Compressor.BalzMax:
        static if (arcz_has_balz) {
          res = writePackedBalz(upbuf);
          break;
        } else {
          throw new Exception("no Balz support was compiled in ArcZ");
        }
      case Compressor.Zopfli:
        static if (arcz_has_zopfli) {
          res = writePackedZopfli(upbuf);
          //break;
        } else {
          //new Exception("no Zopfli support was compiled in ArcZ");
          res = writePackedZLib(upbuf);
        }
        break;
    }
    if (res > uint.max) throw new Exception("output archive too big");
    return cast(uint)res;
  }

  void flushData () {
    if (cdpos > 0) {
      ChunkInfo ci;
      auto pos = ftell(arcfl);
      if (pos < 0 || pos >= uint.max) throw new Exception("output archive too big");
      ci.ofs = cast(uint)pos;
      auto wlen = writePackedBuf(chunkdata[0..cdpos]);
      ci.pksize = wlen;
      if (cdpos == chunkdata.length && ci.pksize >= chunkdata.length) {
        // wow, this chunk is unpackable
        //{ import std.stdio; writeln("unpackable chunk found!"); }
        if (fseek(arcfl, pos, 0) < 0) throw new Exception("can't seek in output file");
        writeBuf(chunkdata[0..cdpos]);
        version(Posix) {
          import core.stdc.stdio : fileno;
          import core.sys.posix.unistd : ftruncate;
          pos = ftell(arcfl);
          if (pos < 0 || pos >= uint.max) throw new Exception("output archive too big");
          if (ftruncate(fileno(arcfl), cast(uint)pos) < 0) throw new Exception("error truncating output file");
        }
        ci.pksize = cdpos;
      }
      if (cdpos < chunkdata.length) lastChunkSize = cast(uint)cdpos;
      cdpos = 0;
      chunks ~= ci;
    } else {
      lastChunkSize = cast(uint)chunkdata.length;
    }
  }

  void closeArc () {
    flushData();
    // write index
    //assert(ftell(arcfl) > 0 && ftell(arcfl) < uint.max);
    assert(chunkdata.length < uint.max);
    assert(chunks.length < uint.max);
    assert(files.length < uint.max);
    // create index in memory
    ubyte[] index;

    void putUint (uint v) {
      index ~= v&0xff;
      index ~= (v>>8)&0xff;
      index ~= (v>>16)&0xff;
      index ~= (v>>24)&0xff;
    }

    void putUbyte (ubyte v) {
      index ~= v;
    }

    void putBuf (const(void)[] buf) {
      assert(buf.length > 0);
      index ~= (cast(const(ubyte)[])buf)[];
    }

    // create index in memory
    {
      // chunk size
      putUint(cast(uint)chunkdata.length);
      // chunk count
      putUint(cast(uint)chunks.length);
      // last chunk size
      putUint(lastChunkSize); // 0: last chunk is full
      // chunk offsets and sizes
      foreach (ref ci; chunks) {
        putUint(ci.ofs);
        putUint(ci.pksize);
      }
      // file count
      putUint(cast(uint)files.length);
      uint nbofs = cast(uint)index.length+cast(uint)files.length*(5*4);
      //uint nbofs = 0;
      // files
      foreach (ref fi; files) {
        // name: length(byte), chars
        assert(fi.name.length > 0 && fi.name.length <= 16384);
        putUint(nbofs);
        putUint(cast(uint)fi.name.length);
        nbofs += cast(uint)fi.name.length+1; // put zero byte there to ease C interfacing
        //putBuf(fi.name[]);
        // chunk number
        putUint(fi.chunk);
        // offset in unpacked chunk
        putUint(fi.chunkofs);
        // unpacked size
        putUint(fi.size);
      }
      // names
      foreach (ref fi; files) {
        putBuf(fi.name[]);
        putUbyte(0); // this means nothing, it is here just for convenience (hello, C!)
      }
      assert(index.length < uint.max);
    }
    auto cpos = ftell(arcfl);
    if (cpos < 0 || cpos > uint.max) throw new Exception("output archive too big");
    // write packed index
    debug(arcz_writer) { import core.stdc.stdio : pinrtf; printf("index size: %u\n", cast(uint)index.length); }
    auto pkisz = writePackedBuf(index[]);
    debug(arcz_writer) { import core.stdc.stdio : pinrtf; printf("packed index size: %u\n", cast(uint)pkisz); }
    // write index info
    if (fseek(arcfl, 5, 0) < 0) throw new Exception("seek error");
    // index offset in file
    writeUint(cast(uint) cpos);
    // packed index size
    writeUint(pkisz);
    // unpacked index size
    writeUint(cast(uint)index.length);
    // done
    statChunks = cast(uint)chunks.length;
    statFiles = cast(uint)files.length;
  }

public:
  this (const(char)[] fname, uint chunkSize=256*1024, Compressor acpr=Compressor.ZLib) {
    assert(chunkSize > 0 && chunkSize < 32*1024*1024); // arbitrary limit
    static if (!arcz_has_balz) {
      if (acpr == Compressor.Balz || acpr == Compressor.BalzMax) throw new Exception("no Balz support was compiled in ArcZ");
    }
    static if (!arcz_has_zopfli) {
      //if (acpr == Compressor.Zopfli) throw new Exception("no Zopfli support was compiled in ArcZ");
    }
    cpr = acpr;
    arcfl = fopen((fname ~ "\0").ptr, "wb");
    if (arcfl is null) throw new Exception("can't create output file '"~fname.idup~"'");
    cdpos = 0;
    chunkdata.length = chunkSize;
    scope(failure) { fclose(arcfl); arcfl = null; }
    writeBuf("CZA2"); // signature
    if (cpr == Compressor.Balz || cpr == Compressor.BalzMax) {
      writeUbyte(1); // version
    } else {
      writeUbyte(0); // version
    }
    writeUint(0); // offset to index
    writeUint(0); // packed index size
    writeUint(0); // unpacked index size
  }

  ~this () { close(); }

  void close () {
    if (arcfl !is null) {
      scope(exit) { fclose(arcfl); arcfl = null; }
      closeArc();
    }
    chunkdata = null;
    chunks = null;
    files = null;
    lastChunkSize = 0;
    cdpos = 0;
  }

  // valid after closing
  @property uint chunksWritten () const pure nothrow @safe @nogc { pragma(inline, true); return statChunks; }
  @property uint filesWritten () const pure nothrow @safe @nogc { pragma(inline, true); return statFiles; }

  void newFile (string name, uint size) {
    FileInfo fi;
    assert(name.length <= 255);
    fi.name = name;
    fi.chunk = cast(uint)chunks.length;
    fi.chunkofs = cast(uint)cdpos;
    fi.size = size;
    files ~= fi;
  }

  void rawWrite(T) (const(T)[] buffer) {
    if (buffer.length > 0) {
      auto src = cast(const(ubyte)*)buffer.ptr;
      auto len = buffer.length*T.sizeof;
      while (len > 0) {
        if (cdpos == chunkdata.length) flushData();
        if (cdpos < chunkdata.length) {
          auto wr = chunkdata.length-cdpos;
          if (wr > len) wr = len;
          chunkdata[cdpos..cdpos+wr] = src[0..wr];
          cdpos += wr;
          len -= wr;
          src += wr;
        }
      }
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
/* arcz file format:
header
======
db 'CZA2'     ; signature
db version    ; 0: zlib; 1: balz
dd indexofs   ; offset to packed index
dd pkindexsz  ; size of packed index
dd upindexsz  ; size of unpacked index


index
=====
dd chunksize    ; unpacked chunk size in bytes
dd chunkcount   ; number of chunks in file
dd lastchunksz  ; size of last chunk (it may be incomplete); 0: last chunk is completely used (all `chunksize` bytes)

then chunk offsets and sizes follows:
  dd chunkofs   ; from file start
  dd pkchunksz  ; size of (possibly packed) chunk data; if it equals to `chunksize`, this chunk is not packed

then file list follows:
dd filecount  ; number of files in archive

then file info follows:
  dd nameofs     ; (in index)
  dd namelen     ; length of name (can't be 0)
  dd firstchunk  ; chunk where file starts
  dd firstofs    ; offset in first chunk (unpacked) where file starts
  dd filesize    ; unpacked file size

then name buffer follows -- just bytes
*/

}

version(WithLzmaDecoder) {

/* *************************************************** */
/* The rest of the file is copy/paste of external code */
/* *************************************************** */

/* LzmaDec.h -- LZMA Decoder
2017-04-03 : Igor Pavlov : Public domain */
// also by Lasse Collin
/* ported to D by ketmar */
private nothrow @trusted @nogc:

//version = _LZMA_PROB32;
/* _LZMA_PROB32 can increase the speed on some CPUs,
   but memory usage for CLzmaDec::probs will be doubled in that case */

//version = _LZMA_SIZE_OPT;

alias Byte = ubyte;
alias UInt16 = ushort;
alias UInt32 = uint;
alias SizeT = size_t;

version(_LZMA_PROB32) {
  alias CLzmaProb = UInt32;
} else {
  alias CLzmaProb = UInt16;
}

public enum SRes {
  OK,
  ERROR_UNSUPPORTED,
  ERROR_MEM,
  ERROR_DATA,
  ERROR_INPUT_EOF,
  ERROR_FAIL,
}

/* ---------- LZMA Properties ---------- */

public enum LZMA_PROPS_SIZE = 5;

public struct CLzmaProps {
  uint lc, lp, pb;
  UInt32 dicSize;
}

/* LzmaProps_Decode - decodes properties
Returns:
  SRes.OK
  SRes.ERROR_UNSUPPORTED - Unsupported properties
*/

//!SRes LzmaProps_Decode(CLzmaProps *p, const(Byte)* data, uint size);


/* ---------- LZMA Decoder state ---------- */

/* LZMA_REQUIRED_INPUT_MAX = number of required input bytes for worst case.
   Num bits = log2((2^11 / 31) ^ 22) + 26 < 134 + 26 = 160; */

enum LZMA_REQUIRED_INPUT_MAX = 20;

public struct CLzmaDec {
private:
  CLzmaProps prop;
  CLzmaProb* probs;
  public Byte* dic;
  const(Byte)* buf;
  UInt32 range, code;
  public SizeT dicPos;
  public SizeT dicBufSize;
  UInt32 processedPos;
  UInt32 checkDicSize;
  uint state;
  UInt32[4] reps;
  uint remainLen;
  int needFlush;
  int needInitState;
  UInt32 numProbs;
  uint tempBufSize;
  Byte[LZMA_REQUIRED_INPUT_MAX] tempBuf;
}

//#define LzmaDec_Construct(p) { (p).dic = 0; (p).probs = 0; }

//void LzmaDec_Init(CLzmaDec *p);

/* There are two types of LZMA streams:
     0) Stream with end mark. That end mark adds about 6 bytes to compressed size.
     1) Stream without end mark. You must know exact uncompressed size to decompress such stream. */

public alias ELzmaFinishMode = int;
public enum /*ELzmaFinishMode*/ {
  LZMA_FINISH_ANY,   /* finish at any point */
  LZMA_FINISH_END    /* block must be finished at the end */
}

/* ELzmaFinishMode has meaning only if the decoding reaches output limit !!!

   You must use LZMA_FINISH_END, when you know that current output buffer
   covers last bytes of block. In other cases you must use LZMA_FINISH_ANY.

   If LZMA decoder sees end marker before reaching output limit, it returns SRes.OK,
   and output value of destLen will be less than output buffer size limit.
   You can check status result also.

   You can use multiple checks to test data integrity after full decompression:
     1) Check Result and "status" variable.
     2) Check that output(destLen) = uncompressedSize, if you know real uncompressedSize.
     3) Check that output(srcLen) = compressedSize, if you know real compressedSize.
        You must use correct finish mode in that case. */

public alias ELzmaStatus = int;
public enum /*ELzmaStatus*/ {
  LZMA_STATUS_NOT_SPECIFIED,               /* use main error code instead */
  LZMA_STATUS_FINISHED_WITH_MARK,          /* stream was finished with end mark. */
  LZMA_STATUS_NOT_FINISHED,                /* stream was not finished */
  LZMA_STATUS_NEEDS_MORE_INPUT,            /* you must provide more input bytes */
  LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK  /* there is probability that stream was finished without end mark */
}

/* ELzmaStatus is used only as output value for function call */


/* ---------- Interfaces ---------- */

/* There are 3 levels of interfaces:
     1) Dictionary Interface
     2) Buffer Interface
     3) One Call Interface
   You can select any of these interfaces, but don't mix functions from different
   groups for same object. */


/* There are two variants to allocate state for Dictionary Interface:
     1) LzmaDec_Allocate / LzmaDec_Free
     2) LzmaDec_AllocateProbs / LzmaDec_FreeProbs
   You can use variant 2, if you set dictionary buffer manually.
   For Buffer Interface you must always use variant 1.

LzmaDec_Allocate* can return:
  SRes.OK
  SRes.ERROR_MEM         - Memory allocation error
  SRes.ERROR_UNSUPPORTED - Unsupported properties
*/

/*
SRes LzmaDec_AllocateProbs(CLzmaDec *p, const(Byte)* props, uint propsSize);
void LzmaDec_FreeProbs(CLzmaDec *p);

SRes LzmaDec_Allocate(CLzmaDec *state, const(Byte)* prop, uint propsSize);
void LzmaDec_Free(CLzmaDec *state);
*/

/* ---------- Dictionary Interface ---------- */

/* You can use it, if you want to eliminate the overhead for data copying from
   dictionary to some other external buffer.
   You must work with CLzmaDec variables directly in this interface.

   STEPS:
     LzmaDec_Constr()
     LzmaDec_Allocate()
     for (each new stream)
     {
       LzmaDec_Init()
       while (it needs more decompression)
       {
         LzmaDec_DecodeToDic()
         use data from CLzmaDec::dic and update CLzmaDec::dicPos
       }
     }
     LzmaDec_Free()
*/

/* LzmaDec_DecodeToDic

   The decoding to internal dictionary buffer (CLzmaDec::dic).
   You must manually update CLzmaDec::dicPos, if it reaches CLzmaDec::dicBufSize !!!

finishMode:
  It has meaning only if the decoding reaches output limit (dicLimit).
  LZMA_FINISH_ANY - Decode just dicLimit bytes.
  LZMA_FINISH_END - Stream must be finished after dicLimit.

Returns:
  SRes.OK
    status:
      LZMA_STATUS_FINISHED_WITH_MARK
      LZMA_STATUS_NOT_FINISHED
      LZMA_STATUS_NEEDS_MORE_INPUT
      LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK
  SRes.ERROR_DATA - Data error
*/

//SRes LzmaDec_DecodeToDic(CLzmaDec *p, SizeT dicLimit, const(Byte)* src, SizeT *srcLen, ELzmaFinishMode finishMode, ELzmaStatus *status);


/* ---------- Buffer Interface ---------- */

/* It's zlib-like interface.
   See LzmaDec_DecodeToDic description for information about STEPS and return results,
   but you must use LzmaDec_DecodeToBuf instead of LzmaDec_DecodeToDic and you don't need
   to work with CLzmaDec variables manually.

finishMode:
  It has meaning only if the decoding reaches output limit (*destLen).
  LZMA_FINISH_ANY - Decode just destLen bytes.
  LZMA_FINISH_END - Stream must be finished after (*destLen).
*/

//SRes LzmaDec_DecodeToBuf(CLzmaDec *p, Byte *dest, SizeT *destLen, const(Byte)* src, SizeT *srcLen, ELzmaFinishMode finishMode, ELzmaStatus *status);


/* ---------- One Call Interface ---------- */

/* LzmaDecode

finishMode:
  It has meaning only if the decoding reaches output limit (*destLen).
  LZMA_FINISH_ANY - Decode just destLen bytes.
  LZMA_FINISH_END - Stream must be finished after (*destLen).

Returns:
  SRes.OK
    status:
      LZMA_STATUS_FINISHED_WITH_MARK
      LZMA_STATUS_NOT_FINISHED
      LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK
  SRes.ERROR_DATA - Data error
  SRes.ERROR_MEM  - Memory allocation error
  SRes.ERROR_UNSUPPORTED - Unsupported properties
  SRes.ERROR_INPUT_EOF - It needs more bytes in input buffer (src).
*/

/*
SRes LzmaDecode(Byte *dest, SizeT *destLen, const(Byte)* src, SizeT *srcLen,
    const(Byte)* propData, uint propSize, ELzmaFinishMode finishMode,
    ELzmaStatus *status, ISzAllocPtr alloc);
*/

// ////////////////////////////////////////////////////////////////////////// //
private:

enum kNumTopBits = 24;
enum kTopValue = 1U<<kNumTopBits;

enum kNumBitModelTotalBits = 11;
enum kBitModelTotal = 1<<kNumBitModelTotalBits;
enum kNumMoveBits = 5;

enum RC_INIT_SIZE = 5;

//enum NORMALIZE = "if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); }";

//#define IF_BIT_0(p) ttt = *(p); NORMALIZE; bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
//#define UPDATE_0(p) range = bound; *(p) = (CLzmaProb)(ttt + ((kBitModelTotal - ttt) >> kNumMoveBits));
//#define UPDATE_1(p) range -= bound; code -= bound; *(p) = (CLzmaProb)(ttt - (ttt >> kNumMoveBits));
enum GET_BIT2(string p, string i, string A0, string A1) =
  "ttt = *("~p~"); if (range < kTopValue) { range <<= 8; code = (code<<8)|(*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)\n"~
  "{ range = bound; *("~p~") = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits)); "~i~" = ("~i~"+"~i~"); "~A0~" } else\n"~
  "{ range -= bound; code -= bound; *("~p~") = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits)); "~i~" = ("~i~"+"~i~")+1; "~A1~" }";
//#define GET_BIT(p, i) GET_BIT2(p, i, ; , ;)
enum GET_BIT(string p, string i) = GET_BIT2!(p, i, "", "");

enum TREE_GET_BIT(string probs, string i) = "{"~GET_BIT!("("~probs~"+"~i~")", i)~"}";

enum TREE_DECODE(string probs, string limit, string i) =
  "{ "~i~" = 1; do { "~TREE_GET_BIT!(probs, i)~" } while ("~i~" < "~limit~"); "~i~" -= "~limit~"; }";


version(_LZMA_SIZE_OPT) {
  enum TREE_6_DECODE(string probs, string i) = TREE_DECODE!(probs, "(1<<6)", i);
} else {
enum TREE_6_DECODE(string probs, string i) =
  "{ "~i~" = 1;\n"~
  TREE_GET_BIT!(probs, i)~
  TREE_GET_BIT!(probs, i)~
  TREE_GET_BIT!(probs, i)~
  TREE_GET_BIT!(probs, i)~
  TREE_GET_BIT!(probs, i)~
  TREE_GET_BIT!(probs, i)~
  i~" -= 0x40; }";
}

enum NORMAL_LITER_DEC = GET_BIT!("prob + symbol", "symbol");
enum MATCHED_LITER_DEC =
  "matchByte <<= 1;\n"~
  "bit = (matchByte & offs);\n"~
  "probLit = prob + offs + bit + symbol;\n"~
  GET_BIT2!("probLit", "symbol", "offs &= ~bit;", "offs &= bit;");

enum NORMALIZE_CHECK = "if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); }";

//#define IF_BIT_0_CHECK(p) ttt = *(p); NORMALIZE_CHECK; bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
//#define UPDATE_0_CHECK range = bound;
//#define UPDATE_1_CHECK range -= bound; code -= bound;
enum GET_BIT2_CHECK(string p, string i, string A0, string A1) =
  "ttt = *("~p~"); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)\n"~
  "{ range = bound; "~i~" = ("~i~" + "~i~"); "~A0~" } else\n"~
  "{ range -= bound; code -= bound; "~i~" = ("~i~" + "~i~") + 1; "~A1~" }";
enum GET_BIT_CHECK(string p, string i) = GET_BIT2_CHECK!(p, i, "{}", "{}");
enum TREE_DECODE_CHECK(string probs, string limit, string i) =
  "{ "~i~" = 1; do { "~GET_BIT_CHECK!(probs~"+"~i, i)~" } while ("~i~" < "~limit~"); "~i~" -= "~limit~"; }";


enum kNumPosBitsMax = 4;
enum kNumPosStatesMax = (1 << kNumPosBitsMax);

enum kLenNumLowBits = 3;
enum kLenNumLowSymbols = (1 << kLenNumLowBits);
enum kLenNumMidBits = 3;
enum kLenNumMidSymbols = (1 << kLenNumMidBits);
enum kLenNumHighBits = 8;
enum kLenNumHighSymbols = (1 << kLenNumHighBits);

enum LenChoice = 0;
enum LenChoice2 = (LenChoice + 1);
enum LenLow = (LenChoice2 + 1);
enum LenMid = (LenLow + (kNumPosStatesMax << kLenNumLowBits));
enum LenHigh = (LenMid + (kNumPosStatesMax << kLenNumMidBits));
enum kNumLenProbs = (LenHigh + kLenNumHighSymbols);


enum kNumStates = 12;
enum kNumLitStates = 7;

enum kStartPosModelIndex = 4;
enum kEndPosModelIndex = 14;
enum kNumFullDistances = (1 << (kEndPosModelIndex >> 1));

enum kNumPosSlotBits = 6;
enum kNumLenToPosStates = 4;

enum kNumAlignBits = 4;
enum kAlignTableSize = (1 << kNumAlignBits);

enum kMatchMinLen = 2;
enum kMatchSpecLenStart = (kMatchMinLen + kLenNumLowSymbols + kLenNumMidSymbols + kLenNumHighSymbols);

enum IsMatch = 0;
enum IsRep = (IsMatch + (kNumStates << kNumPosBitsMax));
enum IsRepG0 = (IsRep + kNumStates);
enum IsRepG1 = (IsRepG0 + kNumStates);
enum IsRepG2 = (IsRepG1 + kNumStates);
enum IsRep0Long = (IsRepG2 + kNumStates);
enum PosSlot = (IsRep0Long + (kNumStates << kNumPosBitsMax));
enum SpecPos = (PosSlot + (kNumLenToPosStates << kNumPosSlotBits));
enum Align = (SpecPos + kNumFullDistances - kEndPosModelIndex);
enum LenCoder = (Align + kAlignTableSize);
enum RepLenCoder = (LenCoder + kNumLenProbs);
enum Literal = (RepLenCoder + kNumLenProbs);

enum LZMA_BASE_SIZE = 1846;
enum LZMA_LIT_SIZE = 0x300;

static assert(Literal == LZMA_BASE_SIZE);

//#define LzmaProps_GetNumProbs(p) (Literal + ((UInt32)LZMA_LIT_SIZE << ((p).lc + (p).lp)))

enum LZMA_DIC_MIN = (1 << 12);

/* First LZMA-symbol is always decoded.
And it decodes new LZMA-symbols while (buf < bufLimit), but "buf" is without last normalization
Out:
  Result:
    SRes.OK - OK
    SRes.ERROR_DATA - Error
  p->remainLen:
    < kMatchSpecLenStart : normal remain
    = kMatchSpecLenStart : finished
    = kMatchSpecLenStart + 1 : Flush marker (unused now)
    = kMatchSpecLenStart + 2 : State Init Marker (unused now)
*/

private SRes LzmaDec_DecodeReal (CLzmaDec* p, SizeT limit, const(Byte)* bufLimit) {
  CLzmaProb* probs = p.probs;

  uint state = p.state;
  UInt32 rep0 = p.reps.ptr[0], rep1 = p.reps.ptr[1], rep2 = p.reps.ptr[2], rep3 = p.reps.ptr[3];
  uint pbMask = (1U<<(p.prop.pb))-1;
  uint lpMask = (1U<<(p.prop.lp))-1;
  uint lc = p.prop.lc;

  Byte* dic = p.dic;
  SizeT dicBufSize = p.dicBufSize;
  SizeT dicPos = p.dicPos;

  UInt32 processedPos = p.processedPos;
  UInt32 checkDicSize = p.checkDicSize;
  uint len = 0;

  const(Byte)* buf = p.buf;
  UInt32 range = p.range;
  UInt32 code = p.code;

  do {
    CLzmaProb *prob;
    UInt32 bound;
    uint ttt;
    uint posState = processedPos & pbMask;

    prob = probs + IsMatch + (state << kNumPosBitsMax) + posState;
    ttt = *(prob); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
    {
      uint symbol;
      range = bound; *(prob) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
      prob = probs + Literal;
      if (processedPos != 0 || checkDicSize != 0)
        prob += (cast(UInt32)LZMA_LIT_SIZE * (((processedPos & lpMask) << lc) +
            (dic[(dicPos == 0 ? dicBufSize : dicPos) - 1] >> (8 - lc))));
      processedPos++;

      if (state < kNumLitStates)
      {
        state -= (state < 4) ? state : 3;
        symbol = 1;
        version(_LZMA_SIZE_OPT) {
          do { mixin(NORMAL_LITER_DEC); } while (symbol < 0x100);
        } else {
          mixin(NORMAL_LITER_DEC);
          mixin(NORMAL_LITER_DEC);
          mixin(NORMAL_LITER_DEC);
          mixin(NORMAL_LITER_DEC);
          mixin(NORMAL_LITER_DEC);
          mixin(NORMAL_LITER_DEC);
          mixin(NORMAL_LITER_DEC);
          mixin(NORMAL_LITER_DEC);
        }
      }
      else
      {
        uint matchByte = dic[dicPos - rep0 + (dicPos < rep0 ? dicBufSize : 0)];
        uint offs = 0x100;
        state -= (state < 10) ? 3 : 6;
        symbol = 1;
        version(_LZMA_SIZE_OPT) {
          do
          {
            uint bit;
            CLzmaProb *probLit;
            mixin(MATCHED_LITER_DEC);
          }
          while (symbol < 0x100);
        } else {
          {
            uint bit;
            CLzmaProb *probLit;
            mixin(MATCHED_LITER_DEC);
            mixin(MATCHED_LITER_DEC);
            mixin(MATCHED_LITER_DEC);
            mixin(MATCHED_LITER_DEC);
            mixin(MATCHED_LITER_DEC);
            mixin(MATCHED_LITER_DEC);
            mixin(MATCHED_LITER_DEC);
            mixin(MATCHED_LITER_DEC);
          }
        }
      }

      dic[dicPos++] = cast(Byte)symbol;
      continue;
    }

    {
      range -= bound; code -= bound; *(prob) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
      prob = probs + IsRep + state;
      ttt = *(prob); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
      {
        range = bound; *(prob) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
        state += kNumStates;
        prob = probs + LenCoder;
      }
      else
      {
        range -= bound; code -= bound; *(prob) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
        if (checkDicSize == 0 && processedPos == 0)
          return SRes.ERROR_DATA;
        prob = probs + IsRepG0 + state;
        ttt = *(prob); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
        {
          range = bound; *(prob) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
          prob = probs + IsRep0Long + (state << kNumPosBitsMax) + posState;
          ttt = *(prob); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
          {
            range = bound; *(prob) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
            dic[dicPos] = dic[dicPos - rep0 + (dicPos < rep0 ? dicBufSize : 0)];
            dicPos++;
            processedPos++;
            state = state < kNumLitStates ? 9 : 11;
            continue;
          }
          range -= bound; code -= bound; *(prob) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
        }
        else
        {
          UInt32 distance;
          range -= bound; code -= bound; *(prob) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
          prob = probs + IsRepG1 + state;
          ttt = *(prob); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
          {
            range = bound; *(prob) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
            distance = rep1;
          }
          else
          {
            range -= bound; code -= bound; *(prob) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
            prob = probs + IsRepG2 + state;
            ttt = *(prob); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
            {
              range = bound; *(prob) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
              distance = rep2;
            }
            else
            {
              range -= bound; code -= bound; *(prob) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
              distance = rep3;
              rep3 = rep2;
            }
            rep2 = rep1;
          }
          rep1 = rep0;
          rep0 = distance;
        }
        state = state < kNumLitStates ? 8 : 11;
        prob = probs + RepLenCoder;
      }

      version(_LZMA_SIZE_OPT) {
        {
          uint lim, offset;
          CLzmaProb *probLen = prob + LenChoice;
          ttt = *(probLen); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
          {
            range = bound; *(probLen) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
            probLen = prob + LenLow + (posState << kLenNumLowBits);
            offset = 0;
            lim = (1 << kLenNumLowBits);
          }
          else
          {
            range -= bound; code -= bound; *(probLen) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
            probLen = prob + LenChoice2;
            ttt = *(probLen); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
            {
              range = bound; *(probLen) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
              probLen = prob + LenMid + (posState << kLenNumMidBits);
              offset = kLenNumLowSymbols;
              lim = (1 << kLenNumMidBits);
            }
            else
            {
              range -= bound; code -= bound; *(probLen) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
              probLen = prob + LenHigh;
              offset = kLenNumLowSymbols + kLenNumMidSymbols;
              lim = (1 << kLenNumHighBits);
            }
          }
          mixin(TREE_DECODE!("probLen", "lim", "len"));
          len += offset;
        }
      } else {
        {
          CLzmaProb *probLen = prob + LenChoice;
          ttt = *(probLen); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
          {
            range = bound; *(probLen) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
            probLen = prob + LenLow + (posState << kLenNumLowBits);
            len = 1;
            mixin(TREE_GET_BIT!("probLen", "len"));
            mixin(TREE_GET_BIT!("probLen", "len"));
            mixin(TREE_GET_BIT!("probLen", "len"));
            len -= 8;
          }
          else
          {
            range -= bound; code -= bound; *(probLen) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
            probLen = prob + LenChoice2;
            ttt = *(probLen); if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); } bound = (range>>kNumBitModelTotalBits)*ttt; if (code < bound)
            {
              range = bound; *(probLen) = cast(CLzmaProb)(ttt+((kBitModelTotal-ttt)>>kNumMoveBits));
              probLen = prob + LenMid + (posState << kLenNumMidBits);
              len = 1;
              mixin(TREE_GET_BIT!("probLen", "len"));
              mixin(TREE_GET_BIT!("probLen", "len"));
              mixin(TREE_GET_BIT!("probLen", "len"));
            }
            else
            {
              range -= bound; code -= bound; *(probLen) = cast(CLzmaProb)(ttt-(ttt>>kNumMoveBits));
              probLen = prob + LenHigh;
              mixin(TREE_DECODE!("probLen", "(1 << kLenNumHighBits)", "len"));
              len += kLenNumLowSymbols + kLenNumMidSymbols;
            }
          }
        }
      }

      if (state >= kNumStates)
      {
        UInt32 distance;
        prob = probs + PosSlot +
            ((len < kNumLenToPosStates ? len : kNumLenToPosStates - 1) << kNumPosSlotBits);
        mixin(TREE_6_DECODE!("prob", "distance"));
        if (distance >= kStartPosModelIndex)
        {
          uint posSlot = cast(uint)distance;
          uint numDirectBits = cast(uint)(((distance >> 1) - 1));
          distance = (2 | (distance & 1));
          if (posSlot < kEndPosModelIndex)
          {
            distance <<= numDirectBits;
            prob = probs + SpecPos + distance - posSlot - 1;
            {
              UInt32 mask = 1;
              uint i = 1;
              do
              {
                mixin(GET_BIT2!("prob + i", "i", "{}" , "distance |= mask;"));
                mask <<= 1;
              }
              while (--numDirectBits != 0);
            }
          }
          else
          {
            numDirectBits -= kNumAlignBits;
            do
            {
              if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); }
              range >>= 1;

              {
                UInt32 t;
                code -= range;
                t = (0 - (cast(UInt32)code >> 31)); /* (UInt32)((Int32)code >> 31) */
                distance = (distance << 1) + (t + 1);
                code += range & t;
              }
              /*
              distance <<= 1;
              if (code >= range)
              {
                code -= range;
                distance |= 1;
              }
              */
            }
            while (--numDirectBits != 0);
            prob = probs + Align;
            distance <<= kNumAlignBits;
            {
              uint i = 1;
              mixin(GET_BIT2!("prob + i", "i", "", "distance |= 1;"));
              mixin(GET_BIT2!("prob + i", "i", "", "distance |= 2;"));
              mixin(GET_BIT2!("prob + i", "i", "", "distance |= 4;"));
              mixin(GET_BIT2!("prob + i", "i", "", "distance |= 8;"));
            }
            if (distance == cast(UInt32)0xFFFFFFFF)
            {
              len += kMatchSpecLenStart;
              state -= kNumStates;
              break;
            }
          }
        }

        rep3 = rep2;
        rep2 = rep1;
        rep1 = rep0;
        rep0 = distance + 1;
        if (checkDicSize == 0)
        {
          if (distance >= processedPos)
          {
            p.dicPos = dicPos;
            return SRes.ERROR_DATA;
          }
        }
        else if (distance >= checkDicSize)
        {
          p.dicPos = dicPos;
          return SRes.ERROR_DATA;
        }
        state = (state < kNumStates + kNumLitStates) ? kNumLitStates : kNumLitStates + 3;
      }

      len += kMatchMinLen;

      {
        SizeT rem;
        uint curLen;
        SizeT pos;

        if ((rem = limit - dicPos) == 0)
        {
          p.dicPos = dicPos;
          return SRes.ERROR_DATA;
        }

        curLen = ((rem < len) ? cast(uint)rem : len);
        pos = dicPos - rep0 + (dicPos < rep0 ? dicBufSize : 0);

        processedPos += curLen;

        len -= curLen;
        if (curLen <= dicBufSize - pos)
        {
          Byte *dest = dic + dicPos;
          ptrdiff_t src = cast(ptrdiff_t)pos - cast(ptrdiff_t)dicPos;
          const(Byte)* lim = dest + curLen;
          dicPos += curLen;
          do
            *(dest) = cast(Byte)*(dest + src);
          while (++dest != lim);
        }
        else
        {
          do
          {
            dic[dicPos++] = dic[pos];
            if (++pos == dicBufSize)
              pos = 0;
          }
          while (--curLen != 0);
        }
      }
    }
  }
  while (dicPos < limit && buf < bufLimit);

  if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); }

  p.buf = buf;
  p.range = range;
  p.code = code;
  p.remainLen = len;
  p.dicPos = dicPos;
  p.processedPos = processedPos;
  p.reps.ptr[0] = rep0;
  p.reps.ptr[1] = rep1;
  p.reps.ptr[2] = rep2;
  p.reps.ptr[3] = rep3;
  p.state = state;

  return SRes.OK;
}

private void LzmaDec_WriteRem (CLzmaDec* p, SizeT limit) {
  if (p.remainLen != 0 && p.remainLen < kMatchSpecLenStart)
  {
    Byte *dic = p.dic;
    SizeT dicPos = p.dicPos;
    SizeT dicBufSize = p.dicBufSize;
    uint len = p.remainLen;
    SizeT rep0 = p.reps.ptr[0]; /* we use SizeT to avoid the BUG of VC14 for AMD64 */
    SizeT rem = limit - dicPos;
    if (rem < len)
      len = cast(uint)(rem);

    if (p.checkDicSize == 0 && p.prop.dicSize - p.processedPos <= len)
      p.checkDicSize = p.prop.dicSize;

    p.processedPos += len;
    p.remainLen -= len;
    while (len != 0)
    {
      len--;
      dic[dicPos] = dic[dicPos - rep0 + (dicPos < rep0 ? dicBufSize : 0)];
      dicPos++;
    }
    p.dicPos = dicPos;
  }
}

private SRes LzmaDec_DecodeReal2(CLzmaDec *p, SizeT limit, const(Byte)* bufLimit)
{
  do
  {
    SizeT limit2 = limit;
    if (p.checkDicSize == 0)
    {
      UInt32 rem = p.prop.dicSize - p.processedPos;
      if (limit - p.dicPos > rem)
        limit2 = p.dicPos + rem;
    }

    if (auto sres = LzmaDec_DecodeReal(p, limit2, bufLimit)) return sres;

    if (p.checkDicSize == 0 && p.processedPos >= p.prop.dicSize)
      p.checkDicSize = p.prop.dicSize;

    LzmaDec_WriteRem(p, limit);
  }
  while (p.dicPos < limit && p.buf < bufLimit && p.remainLen < kMatchSpecLenStart);

  if (p.remainLen > kMatchSpecLenStart)
    p.remainLen = kMatchSpecLenStart;

  return SRes.OK;
}

alias ELzmaDummy = int;
enum /*ELzmaDummy*/ {
  DUMMY_ERROR, /* unexpected end of input stream */
  DUMMY_LIT,
  DUMMY_MATCH,
  DUMMY_REP
}

private ELzmaDummy LzmaDec_TryDummy(const(CLzmaDec)* p, const(Byte)* buf, SizeT inSize)
{
  UInt32 range = p.range;
  UInt32 code = p.code;
  const(Byte)* bufLimit = buf + inSize;
  const(CLzmaProb)* probs = p.probs;
  uint state = p.state;
  ELzmaDummy res;

  {
    const(CLzmaProb)* prob;
    UInt32 bound;
    uint ttt;
    uint posState = (p.processedPos) & ((1 << p.prop.pb) - 1);

    prob = probs + IsMatch + (state << kNumPosBitsMax) + posState;
    ttt = *(prob); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
    {
      range = bound;

      /* if (bufLimit - buf >= 7) return DUMMY_LIT; */

      prob = probs + Literal;
      if (p.checkDicSize != 0 || p.processedPos != 0)
        prob += (cast(UInt32)LZMA_LIT_SIZE *
            ((((p.processedPos) & ((1 << (p.prop.lp)) - 1)) << p.prop.lc) +
            (p.dic[(p.dicPos == 0 ? p.dicBufSize : p.dicPos) - 1] >> (8 - p.prop.lc))));

      if (state < kNumLitStates)
      {
        uint symbol = 1;
        do { mixin(GET_BIT_CHECK!("prob + symbol", "symbol")); } while (symbol < 0x100);
      }
      else
      {
        uint matchByte = p.dic[p.dicPos - p.reps.ptr[0] +
            (p.dicPos < p.reps.ptr[0] ? p.dicBufSize : 0)];
        uint offs = 0x100;
        uint symbol = 1;
        do
        {
          uint bit;
          const(CLzmaProb)* probLit;
          matchByte <<= 1;
          bit = (matchByte & offs);
          probLit = prob + offs + bit + symbol;
          mixin(GET_BIT2_CHECK!("probLit", "symbol", "offs &= ~bit;", "offs &= bit;"));
        }
        while (symbol < 0x100);
      }
      res = DUMMY_LIT;
    }
    else
    {
      uint len;
      range -= bound; code -= bound;

      prob = probs + IsRep + state;
      ttt = *(prob); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
      {
        range = bound;
        state = 0;
        prob = probs + LenCoder;
        res = DUMMY_MATCH;
      }
      else
      {
        range -= bound; code -= bound;
        res = DUMMY_REP;
        prob = probs + IsRepG0 + state;
        ttt = *(prob); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
        {
          range = bound;
          prob = probs + IsRep0Long + (state << kNumPosBitsMax) + posState;
          ttt = *(prob); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
          {
            range = bound;
            if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); }
            return DUMMY_REP;
          }
          else
          {
            range -= bound; code -= bound;
          }
        }
        else
        {
          range -= bound; code -= bound;
          prob = probs + IsRepG1 + state;
          ttt = *(prob); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
          {
            range = bound;
          }
          else
          {
            range -= bound; code -= bound;
            prob = probs + IsRepG2 + state;
            ttt = *(prob); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
            {
              range = bound;
            }
            else
            {
              range -= bound; code -= bound;
            }
          }
        }
        state = kNumStates;
        prob = probs + RepLenCoder;
      }
      {
        uint limit, offset;
        const(CLzmaProb)* probLen = prob + LenChoice;
        ttt = *(probLen); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
        {
          range = bound;
          probLen = prob + LenLow + (posState << kLenNumLowBits);
          offset = 0;
          limit = 1 << kLenNumLowBits;
        }
        else
        {
          range -= bound; code -= bound;
          probLen = prob + LenChoice2;
          ttt = *(probLen); if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); } bound = (range >> kNumBitModelTotalBits) * ttt; if (code < bound)
          {
            range = bound;
            probLen = prob + LenMid + (posState << kLenNumMidBits);
            offset = kLenNumLowSymbols;
            limit = 1 << kLenNumMidBits;
          }
          else
          {
            range -= bound; code -= bound;
            probLen = prob + LenHigh;
            offset = kLenNumLowSymbols + kLenNumMidSymbols;
            limit = 1 << kLenNumHighBits;
          }
        }
        mixin(TREE_DECODE_CHECK!("probLen", "limit", "len"));
        len += offset;
      }

      if (state < 4)
      {
        uint posSlot;
        prob = probs + PosSlot +
            ((len < kNumLenToPosStates ? len : kNumLenToPosStates - 1) <<
            kNumPosSlotBits);
        mixin(TREE_DECODE_CHECK!("prob", "1 << kNumPosSlotBits", "posSlot"));
        if (posSlot >= kStartPosModelIndex)
        {
          uint numDirectBits = ((posSlot >> 1) - 1);

          /* if (bufLimit - buf >= 8) return DUMMY_MATCH; */

          if (posSlot < kEndPosModelIndex)
          {
            prob = probs + SpecPos + ((2 | (posSlot & 1)) << numDirectBits) - posSlot - 1;
          }
          else
          {
            numDirectBits -= kNumAlignBits;
            do
            {
              if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); }
              range >>= 1;
              code -= range & (((code - range) >> 31) - 1);
              /* if (code >= range) code -= range; */
            }
            while (--numDirectBits != 0);
            prob = probs + Align;
            numDirectBits = kNumAlignBits;
          }
          {
            uint i = 1;
            do
            {
              mixin(GET_BIT_CHECK!("prob + i", "i"));
            }
            while (--numDirectBits != 0);
          }
        }
      }
    }
  }
  if (range < kTopValue) { if (buf >= bufLimit) return DUMMY_ERROR; range <<= 8; code = (code << 8) | (*buf++); }
  return res;
}


void LzmaDec_InitDicAndState(CLzmaDec *p, bool initDic, bool initState)
{
  p.needFlush = 1;
  p.remainLen = 0;
  p.tempBufSize = 0;

  if (initDic)
  {
    p.processedPos = 0;
    p.checkDicSize = 0;
    p.needInitState = 1;
  }
  if (initState)
    p.needInitState = 1;
}

public void LzmaDec_Init(CLzmaDec *p)
{
  p.dicPos = 0;
  LzmaDec_InitDicAndState(p, true, true);
}

private void LzmaDec_InitStateReal(CLzmaDec *p)
{
  SizeT numProbs = (Literal+(cast(UInt32)LZMA_LIT_SIZE<<((&p.prop).lc+(&p.prop).lp)));
  SizeT i;
  CLzmaProb *probs = p.probs;
  for (i = 0; i < numProbs; i++)
    probs[i] = kBitModelTotal >> 1;
  p.reps.ptr[0] = p.reps.ptr[1] = p.reps.ptr[2] = p.reps.ptr[3] = 1;
  p.state = 0;
  p.needInitState = 0;
}

public SRes LzmaDec_DecodeToDic(CLzmaDec *p, SizeT dicLimit, const(Byte)* src, SizeT *srcLen,
    ELzmaFinishMode finishMode, ELzmaStatus *status)
{
  SizeT inSize = *srcLen;
  (*srcLen) = 0;
  LzmaDec_WriteRem(p, dicLimit);

  *status = LZMA_STATUS_NOT_SPECIFIED;

  while (p.remainLen != kMatchSpecLenStart)
  {
      int checkEndMarkNow;

      if (p.needFlush)
      {
        for (; inSize > 0 && p.tempBufSize < RC_INIT_SIZE; (*srcLen)++, inSize--)
          p.tempBuf.ptr[p.tempBufSize++] = *src++;
        if (p.tempBufSize < RC_INIT_SIZE)
        {
          *status = LZMA_STATUS_NEEDS_MORE_INPUT;
          return SRes.OK;
        }
        if (p.tempBuf.ptr[0] != 0)
          return SRes.ERROR_DATA;
        p.code =
              (cast(UInt32)p.tempBuf.ptr[1] << 24)
            | (cast(UInt32)p.tempBuf.ptr[2] << 16)
            | (cast(UInt32)p.tempBuf.ptr[3] << 8)
            | (cast(UInt32)p.tempBuf.ptr[4]);
        p.range = 0xFFFFFFFF;
        p.needFlush = 0;
        p.tempBufSize = 0;
      }

      checkEndMarkNow = 0;
      if (p.dicPos >= dicLimit)
      {
        if (p.remainLen == 0 && p.code == 0)
        {
          *status = LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK;
          return SRes.OK;
        }
        if (finishMode == LZMA_FINISH_ANY)
        {
          *status = LZMA_STATUS_NOT_FINISHED;
          return SRes.OK;
        }
        if (p.remainLen != 0)
        {
          *status = LZMA_STATUS_NOT_FINISHED;
          return SRes.ERROR_DATA;
        }
        checkEndMarkNow = 1;
      }

      if (p.needInitState)
        LzmaDec_InitStateReal(p);

      if (p.tempBufSize == 0)
      {
        SizeT processed;
        const(Byte)* bufLimit;
        if (inSize < LZMA_REQUIRED_INPUT_MAX || checkEndMarkNow)
        {
          int dummyRes = LzmaDec_TryDummy(p, src, inSize);
          if (dummyRes == DUMMY_ERROR)
          {
            import core.stdc.string : memcpy;
            memcpy(p.tempBuf.ptr, src, inSize);
            p.tempBufSize = cast(uint)inSize;
            (*srcLen) += inSize;
            *status = LZMA_STATUS_NEEDS_MORE_INPUT;
            return SRes.OK;
          }
          if (checkEndMarkNow && dummyRes != DUMMY_MATCH)
          {
            *status = LZMA_STATUS_NOT_FINISHED;
            return SRes.ERROR_DATA;
          }
          bufLimit = src;
        }
        else
          bufLimit = src + inSize - LZMA_REQUIRED_INPUT_MAX;
        p.buf = src;
        if (LzmaDec_DecodeReal2(p, dicLimit, bufLimit) != 0)
          return SRes.ERROR_DATA;
        processed = cast(SizeT)(p.buf - src);
        (*srcLen) += processed;
        src += processed;
        inSize -= processed;
      }
      else
      {
        uint rem = p.tempBufSize, lookAhead = 0;
        while (rem < LZMA_REQUIRED_INPUT_MAX && lookAhead < inSize)
          p.tempBuf.ptr[rem++] = src[lookAhead++];
        p.tempBufSize = rem;
        if (rem < LZMA_REQUIRED_INPUT_MAX || checkEndMarkNow)
        {
          int dummyRes = LzmaDec_TryDummy(p, p.tempBuf.ptr, rem);
          if (dummyRes == DUMMY_ERROR)
          {
            (*srcLen) += lookAhead;
            *status = LZMA_STATUS_NEEDS_MORE_INPUT;
            return SRes.OK;
          }
          if (checkEndMarkNow && dummyRes != DUMMY_MATCH)
          {
            *status = LZMA_STATUS_NOT_FINISHED;
            return SRes.ERROR_DATA;
          }
        }
        p.buf = p.tempBuf.ptr;
        if (LzmaDec_DecodeReal2(p, dicLimit, p.buf) != 0)
          return SRes.ERROR_DATA;

        {
          uint kkk = cast(uint)(p.buf - p.tempBuf.ptr);
          if (rem < kkk)
            return SRes.ERROR_FAIL; /* some internal error */
          rem -= kkk;
          if (lookAhead < rem)
            return SRes.ERROR_FAIL; /* some internal error */
          lookAhead -= rem;
        }
        (*srcLen) += lookAhead;
        src += lookAhead;
        inSize -= lookAhead;
        p.tempBufSize = 0;
      }
  }
  if (p.code == 0)
    *status = LZMA_STATUS_FINISHED_WITH_MARK;
  return (p.code == 0) ? SRes.OK : SRes.ERROR_DATA;
}

public SRes LzmaDec_DecodeToBuf(CLzmaDec *p, Byte *dest, SizeT *destLen, const(Byte)* src, SizeT *srcLen, ELzmaFinishMode finishMode, ELzmaStatus *status)
{
  import core.stdc.string : memcpy;
  SizeT outSize = *destLen;
  SizeT inSize = *srcLen;
  *srcLen = *destLen = 0;
  for (;;)
  {
    SizeT inSizeCur = inSize, outSizeCur, dicPos;
    ELzmaFinishMode curFinishMode;
    SRes res;
    if (p.dicPos == p.dicBufSize)
      p.dicPos = 0;
    dicPos = p.dicPos;
    if (outSize > p.dicBufSize - dicPos)
    {
      outSizeCur = p.dicBufSize;
      curFinishMode = LZMA_FINISH_ANY;
    }
    else
    {
      outSizeCur = dicPos + outSize;
      curFinishMode = finishMode;
    }

    res = LzmaDec_DecodeToDic(p, outSizeCur, src, &inSizeCur, curFinishMode, status);
    src += inSizeCur;
    inSize -= inSizeCur;
    *srcLen += inSizeCur;
    outSizeCur = p.dicPos - dicPos;
    memcpy(dest, p.dic + dicPos, outSizeCur);
    dest += outSizeCur;
    outSize -= outSizeCur;
    *destLen += outSizeCur;
    if (res != 0)
      return res;
    if (outSizeCur == 0 || outSize == 0)
      return SRes.OK;
  }
}

public void LzmaDec_FreeProbs(CLzmaDec *p) {
  import core.stdc.stdlib : free;
  if (p.probs !is null) free(p.probs);
  p.probs = null;
}

private void LzmaDec_FreeDict(CLzmaDec *p) {
  import core.stdc.stdlib : free;
  if (p.dic !is null) free(p.dic);
  p.dic = null;
}

public void LzmaDec_Free(CLzmaDec *p) {
  LzmaDec_FreeProbs(p);
  LzmaDec_FreeDict(p);
}

public SRes LzmaProps_Decode(CLzmaProps *p, const(Byte)*data, uint size)
{
  UInt32 dicSize;
  Byte d;

  if (size < LZMA_PROPS_SIZE)
    return SRes.ERROR_UNSUPPORTED;
  else
    dicSize = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);

  if (dicSize < LZMA_DIC_MIN)
    dicSize = LZMA_DIC_MIN;
  p.dicSize = dicSize;

  d = data[0];
  if (d >= (9 * 5 * 5))
    return SRes.ERROR_UNSUPPORTED;

  p.lc = d % 9;
  d /= 9;
  p.pb = d / 5;
  p.lp = d % 5;

  return SRes.OK;
}

private SRes LzmaDec_AllocateProbs2(CLzmaDec *p, const(CLzmaProps)* propNew) {
  import core.stdc.stdlib : malloc;
  UInt32 numProbs = (Literal+(cast(UInt32)LZMA_LIT_SIZE<<((propNew).lc+(propNew).lp)));
  if (!p.probs || numProbs != p.numProbs)
  {
    LzmaDec_FreeProbs(p);
    p.probs = cast(CLzmaProb *)malloc(numProbs * CLzmaProb.sizeof);
    p.numProbs = numProbs;
    if (!p.probs)
      return SRes.ERROR_MEM;
  }
  return SRes.OK;
}

public SRes LzmaDec_AllocateProbs(CLzmaDec *p, const(Byte)* props, uint propsSize)
{
  CLzmaProps propNew;
  if (auto sres = LzmaProps_Decode(&propNew, props, propsSize)) return sres;
  if (auto sres = LzmaDec_AllocateProbs2(p, &propNew)) return sres;
  p.prop = propNew;
  return SRes.OK;
}

public SRes LzmaDec_Allocate(CLzmaDec *p, const(Byte)*props, uint propsSize)
{
  import core.stdc.stdlib : malloc;
  CLzmaProps propNew;
  SizeT dicBufSize;
  if (auto sres = LzmaProps_Decode(&propNew, props, propsSize)) return sres;
  if (auto sres = LzmaDec_AllocateProbs2(p, &propNew)) return sres;

  {
    UInt32 dictSize = propNew.dicSize;
    SizeT mask = (1U << 12) - 1;
         if (dictSize >= (1U << 30)) mask = (1U << 22) - 1;
    else if (dictSize >= (1U << 22)) mask = (1U << 20) - 1;
    dicBufSize = (cast(SizeT)dictSize + mask) & ~mask;
    if (dicBufSize < dictSize)
      dicBufSize = dictSize;
  }

  if (!p.dic || dicBufSize != p.dicBufSize)
  {
    LzmaDec_FreeDict(p);
    p.dic = cast(Byte *)malloc(dicBufSize);
    if (!p.dic)
    {
      LzmaDec_FreeProbs(p);
      return SRes.ERROR_MEM;
    }
  }
  p.dicBufSize = dicBufSize;
  p.prop = propNew;
  return SRes.OK;
}

public SRes LzmaDecode(Byte *dest, SizeT *destLen, const(Byte)* src, SizeT *srcLen,
    const(Byte)* propData, uint propSize, ELzmaFinishMode finishMode,
    ELzmaStatus *status)
{
  CLzmaDec p;
  SRes res;
  SizeT outSize = *destLen, inSize = *srcLen;
  *destLen = *srcLen = 0;
  *status = LZMA_STATUS_NOT_SPECIFIED;
  if (inSize < RC_INIT_SIZE)
    return SRes.ERROR_INPUT_EOF;
  //LzmaDec_Construct(&p);
  p.dic = null; p.probs = null;
  if (auto sres = LzmaDec_AllocateProbs(&p, propData, propSize)) return sres;
  p.dic = dest;
  p.dicBufSize = outSize;
  LzmaDec_Init(&p);
  *srcLen = inSize;
  res = LzmaDec_DecodeToDic(&p, outSize, src, srcLen, finishMode, status);
  *destLen = p.dicPos;
  if (res == SRes.OK && *status == LZMA_STATUS_NEEDS_MORE_INPUT)
    res = SRes.ERROR_INPUT_EOF;
  LzmaDec_FreeProbs(&p);
  return res;
}



/* Lzma2Dec.c -- LZMA2 Decoder
2009-05-03 : Igor Pavlov : Public domain */
// also by Lasse Collin
// ported to D by adr.

/*
00000000  -  EOS
00000001 U U  -  Uncompressed Reset Dic
00000010 U U  -  Uncompressed No Reset
100uuuuu U U P P  -  LZMA no reset
101uuuuu U U P P  -  LZMA reset state
110uuuuu U U P P S  -  LZMA reset state + new prop
111uuuuu U U P P S  -  LZMA reset state + new prop + reset dic

  u, U - Unpack Size
  P - Pack Size
  S - Props
*/

struct CLzma2Dec
{
  CLzmaDec decoder;
  UInt32 packSize;
  UInt32 unpackSize;
  int state;
  Byte control;
  bool needInitDic;
  bool needInitState;
  bool needInitProp;
}

enum LZMA2_CONTROL_LZMA = (1 << 7);
enum LZMA2_CONTROL_COPY_NO_RESET = 2;
enum LZMA2_CONTROL_COPY_RESET_DIC = 1;
enum LZMA2_CONTROL_EOF = 0;

auto LZMA2_IS_UNCOMPRESSED_STATE(P)(P p) { return (((p).control & LZMA2_CONTROL_LZMA) == 0); }

auto LZMA2_GET_LZMA_MODE(P)(P p) { return (((p).control >> 5) & 3); }
auto LZMA2_IS_THERE_PROP(P)(P mode) { return ((mode) >= 2); }

enum LZMA2_LCLP_MAX = 4;
auto LZMA2_DIC_SIZE_FROM_PROP(P)(P p) { return ((cast(UInt32)2 | ((p) & 1)) << ((p) / 2 + 11)); }

enum ELzma2State
{
  LZMA2_STATE_CONTROL,
  LZMA2_STATE_UNPACK0,
  LZMA2_STATE_UNPACK1,
  LZMA2_STATE_PACK0,
  LZMA2_STATE_PACK1,
  LZMA2_STATE_PROP,
  LZMA2_STATE_DATA,
  LZMA2_STATE_DATA_CONT,
  LZMA2_STATE_FINISHED,
  LZMA2_STATE_ERROR
}

static SRes Lzma2Dec_GetOldProps(Byte prop, Byte *props)
{
  UInt32 dicSize;
  if (prop > 40)
    return SRes.ERROR_UNSUPPORTED;
  dicSize = (prop == 40) ? 0xFFFFFFFF : LZMA2_DIC_SIZE_FROM_PROP(prop);
  props[0] = cast(Byte)LZMA2_LCLP_MAX;
  props[1] = cast(Byte)(dicSize);
  props[2] = cast(Byte)(dicSize >> 8);
  props[3] = cast(Byte)(dicSize >> 16);
  props[4] = cast(Byte)(dicSize >> 24);
  return SRes.OK;
}

SRes Lzma2Dec_AllocateProbs(CLzma2Dec *p, Byte prop)
{
  Byte[LZMA_PROPS_SIZE] props;
  auto wtf = Lzma2Dec_GetOldProps(prop, props.ptr);
  if(wtf != 0) return wtf;
  return LzmaDec_AllocateProbs(&p.decoder, props.ptr, LZMA_PROPS_SIZE);
}

SRes Lzma2Dec_Allocate(CLzma2Dec *p, Byte prop)
{
  Byte[LZMA_PROPS_SIZE] props;
  auto wtf = Lzma2Dec_GetOldProps(prop, props.ptr);
  if(wtf != 0) return wtf;
  return LzmaDec_Allocate(&p.decoder, props.ptr, LZMA_PROPS_SIZE);
}

void Lzma2Dec_Init(CLzma2Dec *p)
{
  p.state = ELzma2State.LZMA2_STATE_CONTROL;
  p.needInitDic = true;
  p.needInitState = true;
  p.needInitProp = true;
  LzmaDec_Init(&p.decoder);
}

static ELzma2State Lzma2Dec_UpdateState(CLzma2Dec *p, Byte b)
{
  switch(p.state)
  {
    default: return ELzma2State.LZMA2_STATE_ERROR;
    case ELzma2State.LZMA2_STATE_CONTROL:
      p.control = b;
      if (p.control == 0)
        return ELzma2State.LZMA2_STATE_FINISHED;
      if (LZMA2_IS_UNCOMPRESSED_STATE(p))
      {
        if ((p.control & 0x7F) > 2)
          return ELzma2State.LZMA2_STATE_ERROR;
        p.unpackSize = 0;
      }
      else
        p.unpackSize = cast(UInt32)(p.control & 0x1F) << 16;
      return ELzma2State.LZMA2_STATE_UNPACK0;

    case ELzma2State.LZMA2_STATE_UNPACK0:
      p.unpackSize |= cast(UInt32)b << 8;
      return ELzma2State.LZMA2_STATE_UNPACK1;

    case ELzma2State.LZMA2_STATE_UNPACK1:
      p.unpackSize |= cast(UInt32)b;
      p.unpackSize++;
      return (LZMA2_IS_UNCOMPRESSED_STATE(p)) ? ELzma2State.LZMA2_STATE_DATA : ELzma2State.LZMA2_STATE_PACK0;

    case ELzma2State.LZMA2_STATE_PACK0:
      p.packSize = cast(UInt32)b << 8;
      return ELzma2State.LZMA2_STATE_PACK1;

    case ELzma2State.LZMA2_STATE_PACK1:
      p.packSize |= cast(UInt32)b;
      p.packSize++;
      return LZMA2_IS_THERE_PROP(LZMA2_GET_LZMA_MODE(p)) ? ELzma2State.LZMA2_STATE_PROP:
        (p.needInitProp ? ELzma2State.LZMA2_STATE_ERROR : ELzma2State.LZMA2_STATE_DATA);

    case ELzma2State.LZMA2_STATE_PROP:
    {
      int lc, lp;
      if (b >= (9 * 5 * 5))
        return ELzma2State.LZMA2_STATE_ERROR;
      lc = b % 9;
      b /= 9;
      p.decoder.prop.pb = b / 5;
      lp = b % 5;
      if (lc + lp > LZMA2_LCLP_MAX)
        return ELzma2State.LZMA2_STATE_ERROR;
      p.decoder.prop.lc = lc;
      p.decoder.prop.lp = lp;
      p.needInitProp = false;
      return ELzma2State.LZMA2_STATE_DATA;
    }
  }
}

static void LzmaDec_UpdateWithUncompressed(CLzmaDec *p, const(Byte) *src, SizeT size)
{
  import core.stdc.string;
  memcpy(p.dic + p.dicPos, src, size);
  p.dicPos += size;
  if (p.checkDicSize == 0 && p.prop.dicSize - p.processedPos <= size)
    p.checkDicSize = p.prop.dicSize;
  p.processedPos += cast(UInt32)size;
}

SRes Lzma2Dec_DecodeToDic(CLzma2Dec *p, SizeT dicLimit,
    const(Byte) *src, SizeT *srcLen, ELzmaFinishMode finishMode, ELzmaStatus *status)
{
  SizeT inSize = *srcLen;
  *srcLen = 0;
  *status = LZMA_STATUS_NOT_SPECIFIED;

  while (p.state != ELzma2State.LZMA2_STATE_FINISHED)
  {
    SizeT dicPos = p.decoder.dicPos;
    if (p.state == ELzma2State.LZMA2_STATE_ERROR)
      return SRes.ERROR_DATA;
    if (dicPos == dicLimit && finishMode == LZMA_FINISH_ANY)
    {
      *status = LZMA_STATUS_NOT_FINISHED;
      return SRes.OK;
    }
    if (p.state != ELzma2State.LZMA2_STATE_DATA && p.state != ELzma2State.LZMA2_STATE_DATA_CONT)
    {
      if (*srcLen == inSize)
      {
        *status = LZMA_STATUS_NEEDS_MORE_INPUT;
        return SRes.OK;
      }
      (*srcLen)++;
      p.state = Lzma2Dec_UpdateState(p, *src++);
      continue;
    }
    {
      SizeT destSizeCur = dicLimit - dicPos;
      SizeT srcSizeCur = inSize - *srcLen;
      ELzmaFinishMode curFinishMode = LZMA_FINISH_ANY;

      if (p.unpackSize <= destSizeCur)
      {
        destSizeCur = cast(SizeT)p.unpackSize;
        curFinishMode = LZMA_FINISH_END;
      }

      if (LZMA2_IS_UNCOMPRESSED_STATE(p))
      {
        if (*srcLen == inSize)
        {
          *status = LZMA_STATUS_NEEDS_MORE_INPUT;
          return SRes.OK;
        }

        if (p.state == ELzma2State.LZMA2_STATE_DATA)
        {
          bool initDic = (p.control == LZMA2_CONTROL_COPY_RESET_DIC);
          if (initDic)
            p.needInitProp = p.needInitState = true;
          else if (p.needInitDic)
            return SRes.ERROR_DATA;
          p.needInitDic = false;
          LzmaDec_InitDicAndState(&p.decoder, initDic, false);
        }

        if (srcSizeCur > destSizeCur)
          srcSizeCur = destSizeCur;

        if (srcSizeCur == 0)
          return SRes.ERROR_DATA;

        LzmaDec_UpdateWithUncompressed(&p.decoder, src, srcSizeCur);

        src += srcSizeCur;
        *srcLen += srcSizeCur;
        p.unpackSize -= cast(UInt32)srcSizeCur;
        p.state = (p.unpackSize == 0) ? ELzma2State.LZMA2_STATE_CONTROL : ELzma2State.LZMA2_STATE_DATA_CONT;
      }
      else
      {
        SizeT outSizeProcessed;
        SRes res;

        if (p.state == ELzma2State.LZMA2_STATE_DATA)
        {
          int mode = LZMA2_GET_LZMA_MODE(p);
          bool initDic = (mode == 3);
          bool initState = (mode > 0);
          if ((!initDic && p.needInitDic) || (!initState && p.needInitState))
            return SRes.ERROR_DATA;

          LzmaDec_InitDicAndState(&p.decoder, initDic, initState);
          p.needInitDic = false;
          p.needInitState = false;
          p.state = ELzma2State.LZMA2_STATE_DATA_CONT;
        }
        if (srcSizeCur > p.packSize)
          srcSizeCur = cast(SizeT)p.packSize;

        res = LzmaDec_DecodeToDic(&p.decoder, dicPos + destSizeCur, src, &srcSizeCur, curFinishMode, status);

        src += srcSizeCur;
        *srcLen += srcSizeCur;
        p.packSize -= cast(UInt32)srcSizeCur;

        outSizeProcessed = p.decoder.dicPos - dicPos;
        p.unpackSize -= cast(UInt32)outSizeProcessed;

        if(res != 0) return res;
        if (*status == LZMA_STATUS_NEEDS_MORE_INPUT)
          return res;

        if (srcSizeCur == 0 && outSizeProcessed == 0)
        {
          if (*status != LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK ||
              p.unpackSize != 0 || p.packSize != 0)
            return SRes.ERROR_DATA;
          p.state = ELzma2State.LZMA2_STATE_CONTROL;
        }
        if (*status == LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK)
          *status = LZMA_STATUS_NOT_FINISHED;
      }
    }
  }
  *status = LZMA_STATUS_FINISHED_WITH_MARK;
  return SRes.OK;
}

SRes Lzma2Dec_DecodeToBuf(CLzma2Dec *p, Byte *dest, SizeT *destLen, const(Byte) *src, SizeT *srcLen, ELzmaFinishMode finishMode, ELzmaStatus *status)
{
  import core.stdc.string;
  SizeT outSize = *destLen, inSize = *srcLen;
  *srcLen = *destLen = 0;
  for (;;)
  {
    SizeT srcSizeCur = inSize, outSizeCur, dicPos;
    ELzmaFinishMode curFinishMode;
    SRes res;
    if (p.decoder.dicPos == p.decoder.dicBufSize)
      p.decoder.dicPos = 0;
    dicPos = p.decoder.dicPos;
    if (outSize > p.decoder.dicBufSize - dicPos)
    {
      outSizeCur = p.decoder.dicBufSize;
      curFinishMode = LZMA_FINISH_ANY;
    }
    else
    {
      outSizeCur = dicPos + outSize;
      curFinishMode = finishMode;
    }

    res = Lzma2Dec_DecodeToDic(p, outSizeCur, src, &srcSizeCur, curFinishMode, status);
    src += srcSizeCur;
    inSize -= srcSizeCur;
    *srcLen += srcSizeCur;
    outSizeCur = p.decoder.dicPos - dicPos;
    memcpy(dest, p.decoder.dic + dicPos, outSizeCur);
    dest += outSizeCur;
    outSize -= outSizeCur;
    *destLen += outSizeCur;
    if (res != 0)
      return res;
    if (outSizeCur == 0 || outSize == 0)
      return SRes.OK;
  }
}

SRes Lzma2Decode(Byte *dest, SizeT *destLen, const(Byte) *src, SizeT *srcLen,
    Byte prop, ELzmaFinishMode finishMode, ELzmaStatus *status)
{
  CLzma2Dec decoder;
  SRes res;
  SizeT outSize = *destLen, inSize = *srcLen;
  Byte[LZMA_PROPS_SIZE] props;

  //Lzma2Dec_Construct(&decoder);

  *destLen = *srcLen = 0;
  *status = LZMA_STATUS_NOT_SPECIFIED;
  decoder.decoder.dic = dest;
  decoder.decoder.dicBufSize = outSize;

  auto wtf = Lzma2Dec_GetOldProps(prop, props.ptr);
  if(wtf != 0) return wtf;
  wtf = LzmaDec_AllocateProbs(&decoder.decoder, props.ptr, LZMA_PROPS_SIZE);
  if(wtf != 0) return wtf;

  *srcLen = inSize;
  res = Lzma2Dec_DecodeToDic(&decoder, outSize, src, srcLen, finishMode, status);
  *destLen = decoder.decoder.dicPos;
  if (res == SRes.OK && *status == LZMA_STATUS_NEEDS_MORE_INPUT)
    res = SRes.ERROR_INPUT_EOF;

  LzmaDec_FreeProbs(&decoder.decoder);
  return res;
}

}
