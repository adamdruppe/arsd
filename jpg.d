/// Reads a jpg header without reading the rest of the file. Use [arsd.jpeg] for an actual image loader if you need actual data, but this is kept around for times when you only care about basic info like image dimensions.
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

version(with_libjpeg) {
/+
	import arsd.color;

	TrueColorImage read_JPEG_file(string filename) {
		/* This struct contains the JPEG decompression parameters and pointers to
		 * working space (which is allocated as needed by the JPEG library).
		 */
		struct jpeg_decompress_struct cinfo;
		/* We use our private extension JPEG error handler.
		 * Note that this struct must live as long as the main JPEG parameter
		 * struct, to avoid dangling-pointer problems.
		 */
		struct my_error_mgr jerr;
		/* More stuff */
		FILE * infile;		/* source file */
		JSAMPARRAY buffer;		/* Output row buffer */
		int row_stride;		/* physical row width in output buffer */

		/* In this example we want to open the input file before doing anything else,
		 * so that the setjmp() error recovery below can assume the file is open.
		 * VERY IMPORTANT: use "b" option to fopen() if you are on a machine that
		 * requires it in order to read binary files.
		 */

		if ((infile = fopen(filename, "rb")) == NULL) {
			fprintf(stderr, "can't open %s\n", filename);
			return 0;
		}

		/* Step 1: allocate and initialize JPEG decompression object */

		/* We set up the normal JPEG error routines, then override error_exit. */
		cinfo.err = jpeg_std_error(&jerr.pub);
		jerr.pub.error_exit = my_error_exit;
		/* Establish the setjmp return context for my_error_exit to use. */
		if (setjmp(jerr.setjmp_buffer)) {
			/* If we get here, the JPEG code has signaled an error.
			 * We need to clean up the JPEG object, close the input file, and return.
			 */
			jpeg_destroy_decompress(&cinfo);
			fclose(infile);
			return 0;
		}
		/* Now we can initialize the JPEG decompression object. */
		jpeg_create_decompress(&cinfo);

		/* Step 2: specify data source (eg, a file) */

		jpeg_stdio_src(&cinfo, infile);

		/* Step 3: read file parameters with jpeg_read_header() */

		(void) jpeg_read_header(&cinfo, TRUE);
		/* We can ignore the return value from jpeg_read_header since
		 *   (a) suspension is not possible with the stdio data source, and
		 *   (b) we passed TRUE to reject a tables-only JPEG file as an error.
		 * See libjpeg.txt for more info.
		 */

		/* Step 4: set parameters for decompression */

		/* In this example, we don't need to change any of the defaults set by
		 * jpeg_read_header(), so we do nothing here.
		 */

		/* Step 5: Start decompressor */

		(void) jpeg_start_decompress(&cinfo);
		/* We can ignore the return value since suspension is not possible
		 * with the stdio data source.
		 */

		/* We may need to do some setup of our own at this point before reading
		 * the data.  After jpeg_start_decompress() we have the correct scaled
		 * output image dimensions available, as well as the output colormap
		 * if we asked for color quantization.
		 * In this example, we need to make an output work buffer of the right size.
		 */ 
		/* JSAMPLEs per row in output buffer */
		row_stride = cinfo.output_width * cinfo.output_components;
		/* Make a one-row-high sample array that will go away when done with image */
		buffer = (*cinfo.mem->alloc_sarray)
			((j_common_ptr) &cinfo, JPOOL_IMAGE, row_stride, 1);

		/* Step 6: while (scan lines remain to be read) */
		/*           jpeg_read_scanlines(...); */

		/* Here we use the library's state variable cinfo.output_scanline as the
		 * loop counter, so that we don't have to keep track ourselves.
		 */
		while (cinfo.output_scanline < cinfo.output_height) {
			/* jpeg_read_scanlines expects an array of pointers to scanlines.
			 * Here the array is only one element long, but you could ask for
			 * more than one scanline at a time if that's more convenient.
			 */
			(void) jpeg_read_scanlines(&cinfo, buffer, 1);
			/* Assume put_scanline_someplace wants a pointer and sample count. */
			put_scanline_someplace(buffer[0], row_stride);
		}

		/* Step 7: Finish decompression */

		(void) jpeg_finish_decompress(&cinfo);
		/* We can ignore the return value since suspension is not possible
		 * with the stdio data source.
		 */

		/* Step 8: Release JPEG decompression object */

		/* This is an important step since it will release a good deal of memory. */
		jpeg_destroy_decompress(&cinfo);

		/* After finish_decompress, we can close the input file.
		 * Here we postpone it until after no more JPEG errors are possible,
		 * so as to simplify the setjmp error logic above.  (Actually, I don't
		 * think that jpeg_destroy can do an error exit, but why assume anything...)
		 */
		fclose(infile);

		/* At this point you may want to check to see whether any corrupt-data
		 * warnings occurred (test whether jerr.pub.num_warnings is nonzero).
		 */

		/* And we're done! */
		return 1;
	}
+/
}
