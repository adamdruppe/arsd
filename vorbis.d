// Ogg Vorbis audio decoder - v1.10 - public domain
// http://nothings.org/stb_vorbis/
//
// Original version written by Sean Barrett in 2007.
//
// Originally sponsored by RAD Game Tools. Seeking sponsored
// by Phillip Bennefall, Marc Andersen, Aaron Baker, Elias Software,
// Aras Pranckevicius, and Sean Barrett.
//
// LICENSE
//
//   See end of file for license information.
//
// Limitations:
//
//   - floor 0 not supported (used in old ogg vorbis files pre-2004)
//   - lossless sample-truncation at beginning ignored
//   - cannot concatenate multiple vorbis streams
//   - sample positions are 32-bit, limiting seekable 192Khz
//       files to around 6 hours (Ogg supports 64-bit)
//
// Feature contributors:
//    Dougall Johnson (sample-exact seeking)
//
// Bugfix/warning contributors:
//    Terje Mathisen     Niklas Frykholm     Andy Hill
//    Casey Muratori     John Bolton         Gargaj
//    Laurent Gomila     Marc LeBlanc        Ronny Chevalier
//    Bernhard Wodo      Evan Balster        alxprd@github
//    Tom Beaumont       Ingo Leitgeb        Nicolas Guillemot
//    Phillip Bennefall  Rohit               Thiago Goulart
//    manxorist@github   saga musix
//
// Partial history:
//    1.10    - 2017/03/03 - more robust seeking; fix negative ilog(); clear error in open_memory
//    1.09    - 2016/04/04 - back out 'avoid discarding last frame' fix from previous version
//    1.08    - 2016/04/02 - fixed multiple warnings; fix setup memory leaks;
//                           avoid discarding last frame of audio data
//    1.07    - 2015/01/16 - fixed some warnings, fix mingw, const-correct API
//                           some more crash fixes when out of memory or with corrupt files
//    1.06    - 2015/08/31 - full, correct support for seeking API (Dougall Johnson)
//                           some crash fixes when out of memory or with corrupt files
//                           fix some inappropriately signed shifts
//    1.05    - 2015/04/19 - don't define __forceinline if it's redundant
//    1.04    - 2014/08/27 - fix missing const-correct case in API
//    1.03    - 2014/08/07 - warning fixes
//    1.02    - 2014/07/09 - declare qsort comparison as explicitly _cdecl in Windows
//    1.01    - 2014/06/18 - fix stb_vorbis_get_samples_float (interleaved was correct)
//    1.0     - 2014/05/26 - fix memory leaks; fix warnings; fix bugs in >2-channel;
//                           (API change) report sample rate for decode-full-file funcs
//    0.99996 -            - bracket #include <malloc.h> for macintosh compilation
//    0.99995 -            - avoid alias-optimization issue in float-to-int conversion
//
// See end of file for full version history.
// D translation by Ketmar // Invisible Vector
// stolen by adam and module renamed.
/++
	Port of stb_vorbis to D. Provides .ogg audio file reading capabilities. See [arsd.simpleaudio] for code that can use this to actually load and play the file.
+/
module arsd.vorbis;

import core.stdc.stdio : FILE;

version(Windows)
	extern(C) int lrintf(float f) { return cast(int) f; }

nothrow /*@trusted*/:
@nogc { // code block, as c macro helper is not @nogc; yet it's CTFE-only
// import it here, as druntime has no `@nogc` on it (for a reason)
private extern(C) void qsort (void* base, size_t nmemb, size_t size, int function(in void*, in void*) compar);


//////////////////////////////////////////////////////////////////////////////
//
//  HEADER BEGINS HERE
//

///////////   THREAD SAFETY

// Individual VorbisDecoder handles are not thread-safe; you cannot decode from
// them from multiple threads at the same time. However, you can have multiple
// VorbisDecoder handles and decode from them independently in multiple thrads.


///////////   MEMORY ALLOCATION

// normally stb_vorbis uses malloc() to allocate memory at startup,
// and alloca() to allocate temporary memory during a frame on the
// stack. (Memory consumption will depend on the amount of setup
// data in the file and how you set the compile flags for speed
// vs. size. In my test files the maximal-size usage is ~150KB.)
//
// You can modify the wrapper functions in the source (setup_malloc,
// setup_temp_malloc, temp_malloc) to change this behavior, or you
// can use a simpler allocation model: you pass in a buffer from
// which stb_vorbis will allocate _all_ its memory (including the
// temp memory). "open" may fail with a VORBIS_outofmem if you
// do not pass in enough data; there is no way to determine how
// much you do need except to succeed (at which point you can
// query get_info to find the exact amount required. yes I know
// this is lame).
//
// If you pass in a non-null buffer of the type below, allocation
// will occur from it as described above. Otherwise just pass null
// to use malloc()/alloca()

public struct stb_vorbis_alloc {
  ubyte* alloc_buffer;
  int alloc_buffer_length_in_bytes;
}


///////////   FUNCTIONS USEABLE WITH ALL INPUT MODES

/*
public struct stb_vorbis_info {
  uint sample_rate;
  int channels;

  uint setup_memory_required;
  uint setup_temp_memory_required;
  uint temp_memory_required;

  int max_frame_size;
}
*/


/* ************************************************************************** *
// get general information about the file
stb_vorbis_info stb_vorbis_get_info (VorbisDecoder f);

// get the last error detected (clears it, too)
int stb_vorbis_get_error (VorbisDecoder f);

// close an ogg vorbis file and free all memory in use
void stb_vorbis_close (VorbisDecoder f);

// this function returns the offset (in samples) from the beginning of the
// file that will be returned by the next decode, if it is known, or -1
// otherwise. after a flush_pushdata() call, this may take a while before
// it becomes valid again.
// NOT WORKING YET after a seek with PULLDATA API
int stb_vorbis_get_sample_offset (VorbisDecoder f);

// returns the current seek point within the file, or offset from the beginning
// of the memory buffer. In pushdata mode it returns 0.
uint stb_vorbis_get_file_offset (VorbisDecoder f);


///////////   PUSHDATA API

// this API allows you to get blocks of data from any source and hand
// them to stb_vorbis. you have to buffer them; stb_vorbis will tell
// you how much it used, and you have to give it the rest next time;
// and stb_vorbis may not have enough data to work with and you will
// need to give it the same data again PLUS more. Note that the Vorbis
// specification does not bound the size of an individual frame.

// create a vorbis decoder by passing in the initial data block containing
//    the ogg&vorbis headers (you don't need to do parse them, just provide
//    the first N bytes of the file--you're told if it's not enough, see below)
// on success, returns an VorbisDecoder, does not set error, returns the amount of
//    data parsed/consumed on this call in *datablock_memory_consumed_in_bytes;
// on failure, returns null on error and sets *error, does not change *datablock_memory_consumed
// if returns null and *error is VORBIS_need_more_data, then the input block was
//       incomplete and you need to pass in a larger block from the start of the file
VorbisDecoder stb_vorbis_open_pushdata (
              ubyte* datablock, int datablock_length_in_bytes,
              int* datablock_memory_consumed_in_bytes,
              int* error,
              stb_vorbis_alloc* alloc_buffer
            );

// decode a frame of audio sample data if possible from the passed-in data block
//
// return value: number of bytes we used from datablock
//
// possible cases:
//     0 bytes used, 0 samples output (need more data)
//     N bytes used, 0 samples output (resynching the stream, keep going)
//     N bytes used, M samples output (one frame of data)
// note that after opening a file, you will ALWAYS get one N-bytes, 0-sample
// frame, because Vorbis always "discards" the first frame.
//
// Note that on resynch, stb_vorbis will rarely consume all of the buffer,
// instead only datablock_length_in_bytes-3 or less. This is because it wants
// to avoid missing parts of a page header if they cross a datablock boundary,
// without writing state-machiney code to record a partial detection.
//
// The number of channels returned are stored in *channels (which can be
// null--it is always the same as the number of channels reported by
// get_info). *output will contain an array of float* buffers, one per
// channel. In other words, (*output)[0][0] contains the first sample from
// the first channel, and (*output)[1][0] contains the first sample from
// the second channel.
int stb_vorbis_decode_frame_pushdata (
      VorbisDecoder f, ubyte* datablock, int datablock_length_in_bytes,
      int* channels,   // place to write number of float * buffers
      float*** output, // place to write float ** array of float * buffers
      int* samples     // place to write number of output samples
    );

// inform stb_vorbis that your next datablock will not be contiguous with
// previous ones (e.g. you've seeked in the data); future attempts to decode
// frames will cause stb_vorbis to resynchronize (as noted above), and
// once it sees a valid Ogg page (typically 4-8KB, as large as 64KB), it
// will begin decoding the _next_ frame.
//
// if you want to seek using pushdata, you need to seek in your file, then
// call stb_vorbis_flush_pushdata(), then start calling decoding, then once
// decoding is returning you data, call stb_vorbis_get_sample_offset, and
// if you don't like the result, seek your file again and repeat.
void stb_vorbis_flush_pushdata (VorbisDecoder f);


//////////   PULLING INPUT API

// This API assumes stb_vorbis is allowed to pull data from a source--
// either a block of memory containing the _entire_ vorbis stream, or a
// FILE* that you or it create, or possibly some other reading mechanism
// if you go modify the source to replace the FILE* case with some kind
// of callback to your code. (But if you don't support seeking, you may
// just want to go ahead and use pushdata.)

// decode an entire file and output the data interleaved into a malloc()ed
// buffer stored in *output. The return value is the number of samples
// decoded, or -1 if the file could not be opened or was not an ogg vorbis file.
// When you're done with it, just free() the pointer returned in *output.
int stb_vorbis_decode_filename (const(char)* filename, int* channels, int* sample_rate, short** output);
int stb_vorbis_decode_memory (const(ubyte)* mem, int len, int* channels, int* sample_rate, short** output);

// create an ogg vorbis decoder from an ogg vorbis stream in memory (note
// this must be the entire stream!). on failure, returns null and sets *error
VorbisDecoder stb_vorbis_open_memory (const(ubyte)* data, int len, int* error, stb_vorbis_alloc* alloc_buffer);

// create an ogg vorbis decoder from a filename via fopen(). on failure,
// returns null and sets *error (possibly to VORBIS_file_open_failure).
VorbisDecoder stb_vorbis_open_filename (const(char)* filename, int* error, stb_vorbis_alloc* alloc_buffer);

// create an ogg vorbis decoder from an open FILE*, looking for a stream at
// the _current_ seek point (ftell). on failure, returns null and sets *error.
// note that stb_vorbis must "own" this stream; if you seek it in between
// calls to stb_vorbis, it will become confused. Morever, if you attempt to
// perform stb_vorbis_seek_*() operations on this file, it will assume it
// owns the _entire_ rest of the file after the start point. Use the next
// function, stb_vorbis_open_file_section(), to limit it.
VorbisDecoder stb_vorbis_open_file (FILE* f, int close_handle_on_close, int* error, stb_vorbis_alloc* alloc_buffer);

// create an ogg vorbis decoder from an open FILE*, looking for a stream at
// the _current_ seek point (ftell); the stream will be of length 'len' bytes.
// on failure, returns null and sets *error. note that stb_vorbis must "own"
// this stream; if you seek it in between calls to stb_vorbis, it will become
// confused.
VorbisDecoder stb_vorbis_open_file_section (FILE* f, int close_handle_on_close, int* error, stb_vorbis_alloc* alloc_buffer, uint len);

// these functions seek in the Vorbis file to (approximately) 'sample_number'.
// after calling seek_frame(), the next call to get_frame_*() will include
// the specified sample. after calling stb_vorbis_seek(), the next call to
// stb_vorbis_get_samples_* will start with the specified sample. If you
// do not need to seek to EXACTLY the target sample when using get_samples_*,
// you can also use seek_frame().
int stb_vorbis_seek_frame (VorbisDecoder f, uint sample_number);
int stb_vorbis_seek (VorbisDecoder f, uint sample_number);

// this function is equivalent to stb_vorbis_seek(f, 0)
int stb_vorbis_seek_start (VorbisDecoder f);

// these functions return the total length of the vorbis stream
uint stb_vorbis_stream_length_in_samples (VorbisDecoder f);
float stb_vorbis_stream_length_in_seconds (VorbisDecoder f);

// decode the next frame and return the number of samples. the number of
// channels returned are stored in *channels (which can be null--it is always
// the same as the number of channels reported by get_info). *output will
// contain an array of float* buffers, one per channel. These outputs will
// be overwritten on the next call to stb_vorbis_get_frame_*.
//
// You generally should not intermix calls to stb_vorbis_get_frame_*()
// and stb_vorbis_get_samples_*(), since the latter calls the former.
int stb_vorbis_get_frame_float (VorbisDecoder f, int* channels, float*** output);

// decode the next frame and return the number of *samples* per channel.
// Note that for interleaved data, you pass in the number of shorts (the
// size of your array), but the return value is the number of samples per
// channel, not the total number of samples.
//
// The data is coerced to the number of channels you request according to the
// channel coercion rules (see below). You must pass in the size of your
// buffer(s) so that stb_vorbis will not overwrite the end of the buffer.
// The maximum buffer size needed can be gotten from get_info(); however,
// the Vorbis I specification implies an absolute maximum of 4096 samples
// per channel.
int stb_vorbis_get_frame_short_interleaved (VorbisDecoder f, int num_c, short* buffer, int num_shorts);
int stb_vorbis_get_frame_short (VorbisDecoder f, int num_c, short** buffer, int num_samples);

// Channel coercion rules:
//    Let M be the number of channels requested, and N the number of channels present,
//    and Cn be the nth channel; let stereo L be the sum of all L and center channels,
//    and stereo R be the sum of all R and center channels (channel assignment from the
//    vorbis spec).
//        M    N       output
//        1    k      sum(Ck) for all k
//        2    *      stereo L, stereo R
//        k    l      k > l, the first l channels, then 0s
//        k    l      k <= l, the first k channels
//    Note that this is not _good_ surround etc. mixing at all! It's just so
//    you get something useful.

// gets num_samples samples, not necessarily on a frame boundary--this requires
// buffering so you have to supply the buffers. DOES NOT APPLY THE COERCION RULES.
// Returns the number of samples stored per channel; it may be less than requested
// at the end of the file. If there are no more samples in the file, returns 0.
int stb_vorbis_get_samples_float_interleaved (VorbisDecoder f, int channels, float* buffer, int num_floats);
int stb_vorbis_get_samples_float (VorbisDecoder f, int channels, float** buffer, int num_samples);

// gets num_samples samples, not necessarily on a frame boundary--this requires
// buffering so you have to supply the buffers. Applies the coercion rules above
// to produce 'channels' channels. Returns the number of samples stored per channel;
// it may be less than requested at the end of the file. If there are no more
// samples in the file, returns 0.
int stb_vorbis_get_samples_short_interleaved (VorbisDecoder f, int channels, short* buffer, int num_shorts);
int stb_vorbis_get_samples_short (VorbisDecoder f, int channels, short** buffer, int num_samples);
*/

////////   ERROR CODES

public enum STBVorbisError {
  no_error,

  need_more_data = 1,    // not a real error

  invalid_api_mixing,    // can't mix API modes
  outofmem,              // not enough memory
  feature_not_supported, // uses floor 0
  too_many_channels,     // STB_VORBIS_MAX_CHANNELS is too small
  file_open_failure,     // fopen() failed
  seek_without_length,   // can't seek in unknown-length file

  unexpected_eof = 10,   // file is truncated?
  seek_invalid,          // seek past EOF

  // decoding errors (corrupt/invalid stream) -- you probably
  // don't care about the exact details of these

  // vorbis errors:
  invalid_setup = 20,
  invalid_stream,

  // ogg errors:
  missing_capture_pattern = 30,
  invalid_stream_structure_version,
  continued_packet_flag_invalid,
  incorrect_stream_serial_number,
  invalid_first_page,
  bad_packet_type,
  cant_find_last_page,
  seek_failed,
}
//
//  HEADER ENDS HERE
//
//////////////////////////////////////////////////////////////////////////////


// global configuration settings (e.g. set these in the project/makefile),
// or just set them in this file at the top (although ideally the first few
// should be visible when the header file is compiled too, although it's not
// crucial)

// STB_VORBIS_NO_INTEGER_CONVERSION
//     does not compile the code for converting audio sample data from
//     float to integer (implied by STB_VORBIS_NO_PULLDATA_API)
//version = STB_VORBIS_NO_INTEGER_CONVERSION;

// STB_VORBIS_NO_FAST_SCALED_FLOAT
//      does not use a fast float-to-int trick to accelerate float-to-int on
//      most platforms which requires endianness be defined correctly.
//version = STB_VORBIS_NO_FAST_SCALED_FLOAT;

// STB_VORBIS_MAX_CHANNELS [number]
//     globally define this to the maximum number of channels you need.
//     The spec does not put a restriction on channels except that
//     the count is stored in a byte, so 255 is the hard limit.
//     Reducing this saves about 16 bytes per value, so using 16 saves
//     (255-16)*16 or around 4KB. Plus anything other memory usage
//     I forgot to account for. Can probably go as low as 8 (7.1 audio),
//     6 (5.1 audio), or 2 (stereo only).
enum STB_VORBIS_MAX_CHANNELS = 16; // enough for anyone?

// STB_VORBIS_PUSHDATA_CRC_COUNT [number]
//     after a flush_pushdata(), stb_vorbis begins scanning for the
//     next valid page, without backtracking. when it finds something
//     that looks like a page, it streams through it and verifies its
//     CRC32. Should that validation fail, it keeps scanning. But it's
//     possible that _while_ streaming through to check the CRC32 of
//     one candidate page, it sees another candidate page. This #define
//     determines how many "overlapping" candidate pages it can search
//     at once. Note that "real" pages are typically ~4KB to ~8KB, whereas
//     garbage pages could be as big as 64KB, but probably average ~16KB.
//     So don't hose ourselves by scanning an apparent 64KB page and
//     missing a ton of real ones in the interim; so minimum of 2
enum STB_VORBIS_PUSHDATA_CRC_COUNT = 4;

// STB_VORBIS_FAST_HUFFMAN_LENGTH [number]
//     sets the log size of the huffman-acceleration table.  Maximum
//     supported value is 24. with larger numbers, more decodings are O(1),
//     but the table size is larger so worse cache missing, so you'll have
//     to probe (and try multiple ogg vorbis files) to find the sweet spot.
enum STB_VORBIS_FAST_HUFFMAN_LENGTH = 10;

// STB_VORBIS_FAST_BINARY_LENGTH [number]
//     sets the log size of the binary-search acceleration table. this
//     is used in similar fashion to the fast-huffman size to set initial
//     parameters for the binary search

// STB_VORBIS_FAST_HUFFMAN_INT
//     The fast huffman tables are much more efficient if they can be
//     stored as 16-bit results instead of 32-bit results. This restricts
//     the codebooks to having only 65535 possible outcomes, though.
//     (At least, accelerated by the huffman table.)
//version = STB_VORBIS_FAST_HUFFMAN_INT;
version(STB_VORBIS_FAST_HUFFMAN_INT) {} else version = STB_VORBIS_FAST_HUFFMAN_SHORT;

// STB_VORBIS_NO_HUFFMAN_BINARY_SEARCH
//     If the 'fast huffman' search doesn't succeed, then stb_vorbis falls
//     back on binary searching for the correct one. This requires storing
//     extra tables with the huffman codes in sorted order. Defining this
//     symbol trades off space for speed by forcing a linear search in the
//     non-fast case, except for "sparse" codebooks.
//version = STB_VORBIS_NO_HUFFMAN_BINARY_SEARCH;

// STB_VORBIS_DIVIDES_IN_RESIDUE
//     stb_vorbis precomputes the result of the scalar residue decoding
//     that would otherwise require a divide per chunk. you can trade off
//     space for time by defining this symbol.
//version = STB_VORBIS_DIVIDES_IN_RESIDUE;

// STB_VORBIS_DIVIDES_IN_CODEBOOK
//     vorbis VQ codebooks can be encoded two ways: with every case explicitly
//     stored, or with all elements being chosen from a small range of values,
//     and all values possible in all elements. By default, stb_vorbis expands
//     this latter kind out to look like the former kind for ease of decoding,
//     because otherwise an integer divide-per-vector-element is required to
//     unpack the index. If you define STB_VORBIS_DIVIDES_IN_CODEBOOK, you can
//     trade off storage for speed.
//version = STB_VORBIS_DIVIDES_IN_CODEBOOK;

version(STB_VORBIS_CODEBOOK_SHORTS) static assert(0, "STB_VORBIS_CODEBOOK_SHORTS is no longer supported as it produced incorrect results for some input formats");

// STB_VORBIS_DIVIDE_TABLE
//     this replaces small integer divides in the floor decode loop with
//     table lookups. made less than 1% difference, so disabled by default.
//version = STB_VORBIS_DIVIDE_TABLE;

// STB_VORBIS_NO_DEFER_FLOOR
//     Normally we only decode the floor without synthesizing the actual
//     full curve. We can instead synthesize the curve immediately. This
//     requires more memory and is very likely slower, so I don't think
//     you'd ever want to do it except for debugging.
//version = STB_VORBIS_NO_DEFER_FLOOR;
//version(STB_VORBIS_CODEBOOK_FLOATS) static assert(0);


// ////////////////////////////////////////////////////////////////////////// //
private:
static assert(STB_VORBIS_MAX_CHANNELS <= 256, "Value of STB_VORBIS_MAX_CHANNELS outside of allowed range");
static assert(STB_VORBIS_FAST_HUFFMAN_LENGTH <= 24, "Value of STB_VORBIS_FAST_HUFFMAN_LENGTH outside of allowed range");

enum MAX_BLOCKSIZE_LOG = 13; // from specification
enum MAX_BLOCKSIZE = (1 << MAX_BLOCKSIZE_LOG);


alias codetype = float;

// @NOTE
//
// Some arrays below are tagged "//varies", which means it's actually
// a variable-sized piece of data, but rather than malloc I assume it's
// small enough it's better to just allocate it all together with the
// main thing
//
// Most of the variables are specified with the smallest size I could pack
// them into. It might give better performance to make them all full-sized
// integers. It should be safe to freely rearrange the structures or change
// the sizes larger--nothing relies on silently truncating etc., nor the
// order of variables.

enum FAST_HUFFMAN_TABLE_SIZE = (1<<STB_VORBIS_FAST_HUFFMAN_LENGTH);
enum FAST_HUFFMAN_TABLE_MASK = (FAST_HUFFMAN_TABLE_SIZE-1);

struct Codebook {
  int dimensions, entries;
  ubyte* codeword_lengths;
  float minimum_value;
  float delta_value;
  ubyte value_bits;
  ubyte lookup_type;
  ubyte sequence_p;
  ubyte sparse;
  uint lookup_values;
  codetype* multiplicands;
  uint *codewords;
  version(STB_VORBIS_FAST_HUFFMAN_SHORT) {
    short[FAST_HUFFMAN_TABLE_SIZE] fast_huffman;
  } else {
    int[FAST_HUFFMAN_TABLE_SIZE] fast_huffman;
  }
  uint* sorted_codewords;
  int* sorted_values;
  int sorted_entries;
}

struct Floor0 {
  ubyte order;
  ushort rate;
  ushort bark_map_size;
  ubyte amplitude_bits;
  ubyte amplitude_offset;
  ubyte number_of_books;
  ubyte[16] book_list; // varies
}

struct Floor1 {
  ubyte partitions;
  ubyte[32] partition_class_list; // varies
  ubyte[16] class_dimensions; // varies
  ubyte[16] class_subclasses; // varies
  ubyte[16] class_masterbooks; // varies
  short[8][16] subclass_books; // varies
  ushort[31*8+2] Xlist; // varies
  ubyte[31*8+2] sorted_order;
  ubyte[2][31*8+2] neighbors;
  ubyte floor1_multiplier;
  ubyte rangebits;
  int values;
}

union Floor {
  Floor0 floor0;
  Floor1 floor1;
}

struct Residue {
  uint begin, end;
  uint part_size;
  ubyte classifications;
  ubyte classbook;
  ubyte** classdata;
  //int16 (*residue_books)[8];
  short[8]* residue_books;
}

struct MappingChannel {
  ubyte magnitude;
  ubyte angle;
  ubyte mux;
}

struct Mapping {
  ushort coupling_steps;
  MappingChannel* chan;
  ubyte submaps;
  ubyte[15] submap_floor; // varies
  ubyte[15] submap_residue; // varies
}

struct Mode {
  ubyte blockflag;
  ubyte mapping;
  ushort windowtype;
  ushort transformtype;
}

struct CRCscan {
  uint goal_crc;   // expected crc if match
  int bytes_left;  // bytes left in packet
  uint crc_so_far; // running crc
  int bytes_done;  // bytes processed in _current_ chunk
  uint sample_loc; // granule pos encoded in page
}

struct ProbedPage {
  uint page_start, page_end;
  uint last_decoded_sample;
}

private int error (VorbisDecoder f, STBVorbisError e) {
  f.error = e;
  if (!f.eof && e != STBVorbisError.need_more_data) {
    // import std.stdio; debug writeln(e);
    f.error = e; // breakpoint for debugging
  }
  return 0;
}

// these functions are used for allocating temporary memory
// while decoding. if you can afford the stack space, use
// alloca(); otherwise, provide a temp buffer and it will
// allocate out of those.
uint temp_alloc_save (VorbisDecoder f) nothrow @nogc { static if (__VERSION__ > 2067) pragma(inline, true); return f.alloc.tempSave(f); }
void temp_alloc_restore (VorbisDecoder f, uint p) nothrow @nogc { static if (__VERSION__ > 2067) pragma(inline, true); f.alloc.tempRestore(p, f); }
void temp_free (VorbisDecoder f, void* p) nothrow @nogc {}
/*
T* temp_alloc(T) (VorbisDecoder f, uint count) nothrow @nogc {
  auto res = f.alloc.alloc(count*T.sizeof, f);
  return cast(T*)res;
}
*/

/+
enum array_size_required(string count, string size) = q{((${count})*((void*).sizeof+(${size})))}.cmacroFixVars!("count", "size")(count, size);

// has to be a mixin, due to `alloca`
template temp_alloc(string size) {
  enum temp_alloc = q{(f.alloc.alloc_buffer ? setup_temp_malloc(f, (${size})) : alloca(${size}))}.cmacroFixVars!("size")(size);
}

// has to be a mixin, due to `alloca`
template temp_block_array(string count, string size) {
  enum temp_block_array = q{(make_block_array(${tam}, (${count}), (${size})))}
    .cmacroFixVars!("count", "size", "tam")(count, size, temp_alloc!(array_size_required!(count, size)));
}
+/
enum array_size_required(string count, string size) = q{((${count})*((void*).sizeof+(${size})))}.cmacroFixVars!("count", "size")(count, size);

template temp_alloc(string size) {
  enum temp_alloc = q{alloca(${size})}.cmacroFixVars!("size")(size);
}

template temp_block_array(string count, string size) {
  enum temp_block_array = q{(make_block_array(${tam}, (${count}), (${size})))}
    .cmacroFixVars!("count", "size", "tam")(count, size, temp_alloc!(array_size_required!(count, size)));
}

/*
T** temp_block_array(T) (VorbisDecoder f, uint count, uint size) {
  size *= T.sizeof;
  auto mem = f.alloc.alloc(count*(void*).sizeof+size, f);
  if (mem !is null) make_block_array(mem, count, size);
  return cast(T**)mem;
}
*/

// given a sufficiently large block of memory, make an array of pointers to subblocks of it
private void* make_block_array (void* mem, int count, int size) {
  void** p = cast(void**)mem;
  char* q = cast(char*)(p+count);
  foreach (immutable i; 0..count) {
    p[i] = q;
    q += size;
  }
  return p;
}

private T* setup_malloc(T) (VorbisDecoder f, uint sz) {
  sz *= T.sizeof;
  /*
  f.setup_memory_required += sz;
  if (f.alloc.alloc_buffer) {
    void* p = cast(char*)f.alloc.alloc_buffer+f.setup_offset;
    if (f.setup_offset+sz > f.temp_offset) return null;
    f.setup_offset += sz;
    return cast(T*)p;
  }
  */
  auto res = f.alloc.alloc(sz+8, f); // +8 to compensate dmd codegen bug: it can read dword(qword?) when told to read only byte
  if (res !is null) {
    import core.stdc.string : memset;
    memset(res, 0, sz+8);
  }
  return cast(T*)res;
}

private void setup_free (VorbisDecoder f, void* p) {
  //if (f.alloc.alloc_buffer) return; // do nothing; setup mem is a stack
  if (p !is null) f.alloc.free(p, f);
}

private void* setup_temp_malloc (VorbisDecoder f, uint sz) {
  auto res = f.alloc.allocTemp(sz+8, f); // +8 to compensate dmd codegen bug: it can read dword(qword?) when told to read only byte
  if (res !is null) {
    import core.stdc.string : memset;
    memset(res, 0, sz+8);
  }
  return res;
}

private void setup_temp_free (VorbisDecoder f, void* p, uint sz) {
  if (p !is null) f.alloc.freeTemp(p, (sz ? sz : 1)+8, f); // +8 to compensate dmd codegen bug: it can read dword(qword?) when told to read only byte
}

immutable uint[256] crc_table;
shared static this () {
  enum CRC32_POLY = 0x04c11db7; // from spec
  // init crc32 table
  foreach (uint i; 0..256) {
    uint s = i<<24;
    foreach (immutable _; 0..8) s = (s<<1)^(s >= (1U<<31) ? CRC32_POLY : 0);
    crc_table[i] = s;
  }
}

uint crc32_update (uint crc, ubyte b) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  return (crc<<8)^crc_table[b^(crc>>24)];
}

// used in setup, and for huffman that doesn't go fast path
private uint bit_reverse (uint n) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  n = ((n&0xAAAAAAAA)>>1)|((n&0x55555555)<<1);
  n = ((n&0xCCCCCCCC)>>2)|((n&0x33333333)<<2);
  n = ((n&0xF0F0F0F0)>>4)|((n&0x0F0F0F0F)<<4);
  n = ((n&0xFF00FF00)>>8)|((n&0x00FF00FF)<<8);
  return (n>>16)|(n<<16);
}

private float square (float x) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  return x*x;
}

// this is a weird definition of log2() for which log2(1) = 1, log2(2) = 2, log2(4) = 3
// as required by the specification. fast(?) implementation from stb.h
// @OPTIMIZE: called multiple times per-packet with "constants"; move to setup
immutable byte[16] log2_4 = [0,1,2,2,3,3,3,3,4,4,4,4,4,4,4,4];
private int ilog (int n) {
  //static if (__VERSION__ > 2067) pragma(inline, true);
  if (n < 0) return 0; // signed n returns 0
  // 2 compares if n < 16, 3 compares otherwise (4 if signed or n > 1<<29)
  if (n < (1<<14)) {
    if (n < (1<<4)) return 0+log2_4[n];
    if (n < (1<<9)) return 5+log2_4[n>>5];
    return 10+log2_4[n>>10];
  } else if (n < (1<<24)) {
    if (n < (1<<19)) return 15+log2_4[n>>15];
    return 20+log2_4[n>>20];
  } else {
    if (n < (1<<29)) return 25+log2_4[n>>25];
    return 30+log2_4[n>>30];
  }
}


// code length assigned to a value with no huffman encoding
enum NO_CODE = 255;

/////////////////////// LEAF SETUP FUNCTIONS //////////////////////////
//
// these functions are only called at setup, and only a few times per file
private float float32_unpack (uint x) {
  import core.math : ldexp;
  //static if (__VERSION__ > 2067) pragma(inline, true);
  // from the specification
  uint mantissa = x&0x1fffff;
  uint sign = x&0x80000000;
  uint exp = (x&0x7fe00000)>>21;
  double res = (sign ? -cast(double)mantissa : cast(double)mantissa);
  return cast(float)ldexp(cast(float)res, cast(int)exp-788);
}

// zlib & jpeg huffman tables assume that the output symbols
// can either be arbitrarily arranged, or have monotonically
// increasing frequencies--they rely on the lengths being sorted;
// this makes for a very simple generation algorithm.
// vorbis allows a huffman table with non-sorted lengths. This
// requires a more sophisticated construction, since symbols in
// order do not map to huffman codes "in order".
private void add_entry (Codebook* c, uint huff_code, int symbol, int count, ubyte len, uint* values) {
  if (!c.sparse) {
    c.codewords[symbol] = huff_code;
  } else {
    c.codewords[count] = huff_code;
    c.codeword_lengths[count] = len;
    values[count] = symbol;
  }
}

private int compute_codewords (Codebook* c, ubyte* len, int n, uint* values) {
  import core.stdc.string : memset;

  int i, k, m = 0;
  uint[32] available;

  memset(available.ptr, 0, available.sizeof);
  // find the first entry
  for (k = 0; k < n; ++k) if (len[k] < NO_CODE) break;
  if (k == n) { assert(c.sorted_entries == 0); return true; }
  // add to the list
  add_entry(c, 0, k, m++, len[k], values);
  // add all available leaves
  for (i = 1; i <= len[k]; ++i) available[i] = 1U<<(32-i);
  // note that the above code treats the first case specially,
  // but it's really the same as the following code, so they
  // could probably be combined (except the initial code is 0,
  // and I use 0 in available[] to mean 'empty')
  for (i = k+1; i < n; ++i) {
    uint res;
    int z = len[i];
    if (z == NO_CODE) continue;
    // find lowest available leaf (should always be earliest,
    // which is what the specification calls for)
    // note that this property, and the fact we can never have
    // more than one free leaf at a given level, isn't totally
    // trivial to prove, but it seems true and the assert never
    // fires, so!
    while (z > 0 && !available[z]) --z;
    if (z == 0) return false;
    res = available[z];
    assert(z >= 0 && z < 32);
    available[z] = 0;
    ubyte xxx = len[i];
    add_entry(c,
      bit_reverse(res),
      i,
      m++,
      xxx, // dmd bug: it reads 4 bytes without temp
      values);
    // propogate availability up the tree
    if (z != len[i]) {
      assert(len[i] >= 0 && len[i] < 32);
      for (int y = len[i]; y > z; --y) {
        assert(available[y] == 0);
        available[y] = res+(1<<(32-y));
      }
    }
  }
  return true;
}

// accelerated huffman table allows fast O(1) match of all symbols
// of length <= STB_VORBIS_FAST_HUFFMAN_LENGTH
private void compute_accelerated_huffman (Codebook* c) {
  //for (i=0; i < FAST_HUFFMAN_TABLE_SIZE; ++i) c.fast_huffman.ptr[i] = -1;
  c.fast_huffman.ptr[0..FAST_HUFFMAN_TABLE_SIZE] = -1;
  auto len = (c.sparse ? c.sorted_entries : c.entries);
  version(STB_VORBIS_FAST_HUFFMAN_SHORT) {
    if (len > 32767) len = 32767; // largest possible value we can encode!
  }
  foreach (uint i; 0..len) {
    if (c.codeword_lengths[i] <= STB_VORBIS_FAST_HUFFMAN_LENGTH) {
      uint z = (c.sparse ? bit_reverse(c.sorted_codewords[i]) : c.codewords[i]);
      // set table entries for all bit combinations in the higher bits
      while (z < FAST_HUFFMAN_TABLE_SIZE) {
        c.fast_huffman.ptr[z] = cast(typeof(c.fast_huffman[0]))i; //k8
        z += 1<<c.codeword_lengths[i];
      }
    }
  }
}

extern(C) int uint32_compare (const void* p, const void* q) {
  uint x = *cast(uint*)p;
  uint y = *cast(uint*)q;
  return (x < y ? -1 : x > y);
}

private int include_in_sort (Codebook* c, uint len) {
  if (c.sparse) { assert(len != NO_CODE); return true; }
  if (len == NO_CODE) return false;
  if (len > STB_VORBIS_FAST_HUFFMAN_LENGTH) return true;
  return false;
}

// if the fast table above doesn't work, we want to binary
// search them... need to reverse the bits
private void compute_sorted_huffman (Codebook* c, ubyte* lengths, uint* values) {
  // build a list of all the entries
  // OPTIMIZATION: don't include the short ones, since they'll be caught by FAST_HUFFMAN.
  // this is kind of a frivolous optimization--I don't see any performance improvement,
  // but it's like 4 extra lines of code, so.
  if (!c.sparse) {
    int k = 0;
    foreach (uint i; 0..c.entries) if (include_in_sort(c, lengths[i])) c.sorted_codewords[k++] = bit_reverse(c.codewords[i]);
    assert(k == c.sorted_entries);
  } else {
    foreach (uint i; 0..c.sorted_entries) c.sorted_codewords[i] = bit_reverse(c.codewords[i]);
  }

  qsort(c.sorted_codewords, c.sorted_entries, (c.sorted_codewords[0]).sizeof, &uint32_compare);
  c.sorted_codewords[c.sorted_entries] = 0xffffffff;

  auto len = (c.sparse ? c.sorted_entries : c.entries);
  // now we need to indicate how they correspond; we could either
  //   #1: sort a different data structure that says who they correspond to
  //   #2: for each sorted entry, search the original list to find who corresponds
  //   #3: for each original entry, find the sorted entry
  // #1 requires extra storage, #2 is slow, #3 can use binary search!
  foreach (uint i; 0..len) {
    auto huff_len = (c.sparse ? lengths[values[i]] : lengths[i]);
    if (include_in_sort(c, huff_len)) {
      uint code = bit_reverse(c.codewords[i]);
      int x = 0, n = c.sorted_entries;
      while (n > 1) {
        // invariant: sc[x] <= code < sc[x+n]
        int m = x+(n>>1);
        if (c.sorted_codewords[m] <= code) {
          x = m;
          n -= (n>>1);
        } else {
          n >>= 1;
        }
      }
      assert(c.sorted_codewords[x] == code);
      if (c.sparse) {
        c.sorted_values[x] = values[i];
        c.codeword_lengths[x] = huff_len;
      } else {
        c.sorted_values[x] = i;
      }
    }
  }
}

// only run while parsing the header (3 times)
private int vorbis_validate (const(void)* data) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  immutable char[6] vorbis = "vorbis";
  return ((cast(char*)data)[0..6] == vorbis[]);
}

// called from setup only, once per code book
// (formula implied by specification)
private int lookup1_values (int entries, int dim) {
  import core.stdc.math : lrintf;
  import std.math : floor, exp, pow, log;
  int r = cast(int)lrintf(floor(exp(cast(float)log(cast(float)entries)/dim)));
  if (lrintf(floor(pow(cast(float)r+1, dim))) <= entries) ++r; // (int) cast for MinGW warning; floor() to avoid _ftol() when non-CRT
  assert(pow(cast(float)r+1, dim) > entries);
  assert(lrintf(floor(pow(cast(float)r, dim))) <= entries); // (int), floor() as above
  return r;
}

// called twice per file
private void compute_twiddle_factors (int n, float* A, float* B, float* C) {
  import std.math : cos, sin, PI;
  int n4 = n>>2, n8 = n>>3;
  int k, k2;
  for (k = k2 = 0; k < n4; ++k, k2 += 2) {
    A[k2  ] = cast(float) cos(4*k*PI/n);
    A[k2+1] = cast(float)-sin(4*k*PI/n);
    B[k2  ] = cast(float) cos((k2+1)*PI/n/2)*0.5f;
    B[k2+1] = cast(float) sin((k2+1)*PI/n/2)*0.5f;
  }
  for (k = k2 = 0; k < n8; ++k, k2 += 2) {
    C[k2  ] = cast(float) cos(2*(k2+1)*PI/n);
    C[k2+1] = cast(float)-sin(2*(k2+1)*PI/n);
  }
}

private void compute_window (int n, float* window) {
  import std.math : sin, PI;
  int n2 = n>>1;
  foreach (int i; 0..n2) *window++ = cast(float)sin(0.5*PI*square(cast(float)sin((i-0+0.5)/n2*0.5*PI)));
}

private void compute_bitreverse (int n, ushort* rev) {
  int ld = ilog(n)-1; // ilog is off-by-one from normal definitions
  int n8 = n>>3;
  foreach (int i; 0..n8) *rev++ = cast(ushort)((bit_reverse(i)>>(32-ld+3))<<2); //k8
}

private int init_blocksize (VorbisDecoder f, int b, int n) {
  int n2 = n>>1, n4 = n>>2, n8 = n>>3;
  f.A[b] = setup_malloc!float(f, n2);
  f.B[b] = setup_malloc!float(f, n2);
  f.C[b] = setup_malloc!float(f, n4);
  if (f.A[b] is null || f.B[b] is null || f.C[b] is null) return error(f, STBVorbisError.outofmem);
  compute_twiddle_factors(n, f.A[b], f.B[b], f.C[b]);
  f.window[b] = setup_malloc!float(f, n2);
  if (f.window[b] is null) return error(f, STBVorbisError.outofmem);
  compute_window(n, f.window[b]);
  f.bit_reverse[b] = setup_malloc!ushort(f, n8);
  if (f.bit_reverse[b] is null) return error(f, STBVorbisError.outofmem);
  compute_bitreverse(n, f.bit_reverse[b]);
  return true;
}

private void neighbors (ushort* x, int n, ushort* plow, ushort* phigh) {
  int low = -1;
  int high = 65536;
  assert(n >= 0 && n <= ushort.max);
  foreach (ushort i; 0..cast(ushort)n) {
    if (x[i] > low  && x[i] < x[n]) { *plow = i; low = x[i]; }
    if (x[i] < high && x[i] > x[n]) { *phigh = i; high = x[i]; }
  }
}

// this has been repurposed so y is now the original index instead of y
struct Point {
  ushort x, y;
}

extern(C) int point_compare (const void *p, const void *q) {
  auto a = cast(const(Point)*)p;
  auto b = cast(const(Point)*)q;
  return (a.x < b.x ? -1 : a.x > b.x);
}
/////////////////////// END LEAF SETUP FUNCTIONS //////////////////////////

// ///////////////////////////////////////////////////////////////////// //
private ubyte get8 (VorbisDecoder f) {
  ubyte b = void;
  if (!f.eof) {
    if (f.rawRead((&b)[0..1]) != 1) { f.eof = true; b = 0; }
  }
  return b;
}

private uint get32 (VorbisDecoder f) {
  uint x = 0;
  if (!f.eof) {
    version(LittleEndian) {
      if (f.rawRead((&x)[0..1]) != x.sizeof) { f.eof = true; x = 0; }
    } else {
      x = get8(f);
      x |= cast(uint)get8(f)<<8;
      x |= cast(uint)get8(f)<<16;
      x |= cast(uint)get8(f)<<24;
    }
  }
  return x;
}

private bool getn (VorbisDecoder f, void* data, int n) {
  if (f.eof || n < 0) return false;
  if (n == 0) return true;
  if (f.rawRead(data[0..n]) != n) { f.eof = true; return false; }
  return true;
}

private void skip (VorbisDecoder f, int n) {
  if (f.eof || n == 0) return;
  f.rawSkip(n);
}

private void set_file_offset (VorbisDecoder f, uint loc) {
  /+if (f.push_mode) return;+/
  f.eof = false;
  if (loc >= 0x80000000) { f.eof = true; return; }
  f.rawSeek(loc);
}


immutable char[4] ogg_page_header = "OggS"; //[ 0x4f, 0x67, 0x67, 0x53 ];

private bool capture_pattern (VorbisDecoder f) {
  static if (__VERSION__ > 2067) pragma(inline, true);
  char[4] sign = void;
  if (!getn(f, sign.ptr, 4)) return false;
  return (sign == "OggS");
}

enum PAGEFLAG_continued_packet = 1;
enum PAGEFLAG_first_page = 2;
enum PAGEFLAG_last_page = 4;

private int start_page_no_capturepattern (VorbisDecoder f) {
  uint loc0, loc1, n;
  // stream structure version
  if (get8(f) != 0) return error(f, STBVorbisError.invalid_stream_structure_version);
  // header flag
  f.page_flag = get8(f);
  // absolute granule position
  loc0 = get32(f);
  loc1 = get32(f);
  // @TODO: validate loc0, loc1 as valid positions?
  // stream serial number -- vorbis doesn't interleave, so discard
  get32(f);
  //if (f.serial != get32(f)) return error(f, STBVorbisError.incorrect_stream_serial_number);
  // page sequence number
  n = get32(f);
  f.last_page = n;
  // CRC32
  get32(f);
  // page_segments
  f.segment_count = get8(f);
  if (!getn(f, f.segments.ptr, f.segment_count)) return error(f, STBVorbisError.unexpected_eof);
  // assume we _don't_ know any the sample position of any segments
  f.end_seg_with_known_loc = -2;
  if (loc0 != ~0U || loc1 != ~0U) {
    int i;
    // determine which packet is the last one that will complete
    for (i = f.segment_count-1; i >= 0; --i) if (f.segments.ptr[i] < 255) break;
    // 'i' is now the index of the _last_ segment of a packet that ends
    if (i >= 0) {
      f.end_seg_with_known_loc = i;
      f.known_loc_for_packet = loc0;
    }
  }
  if (f.first_decode) {
    int len;
    ProbedPage p;
    len = 0;
    foreach (int i; 0..f.segment_count) len += f.segments.ptr[i];
    len += 27+f.segment_count;
    p.page_start = f.first_audio_page_offset;
    p.page_end = p.page_start+len;
    p.last_decoded_sample = loc0;
    f.p_first = p;
  }
  f.next_seg = 0;
  return true;
}

private int start_page (VorbisDecoder f) {
  if (!capture_pattern(f)) return error(f, STBVorbisError.missing_capture_pattern);
  return start_page_no_capturepattern(f);
}

private int start_packet (VorbisDecoder f) {
  while (f.next_seg == -1) {
    if (!start_page(f)) return false;
    if (f.page_flag&PAGEFLAG_continued_packet) return error(f, STBVorbisError.continued_packet_flag_invalid);
  }
  f.last_seg = false;
  f.valid_bits = 0;
  f.packet_bytes = 0;
  f.bytes_in_seg = 0;
  // f.next_seg is now valid
  return true;
}

private int maybe_start_packet (VorbisDecoder f) {
  if (f.next_seg == -1) {
    auto x = get8(f);
    if (f.eof) return false; // EOF at page boundary is not an error!
    // import std.stdio; debug writefln("CAPTURE %x %x", x, f.stpos);
    if (0x4f != x      ) return error(f, STBVorbisError.missing_capture_pattern);
    if (0x67 != get8(f)) return error(f, STBVorbisError.missing_capture_pattern);
    if (0x67 != get8(f)) return error(f, STBVorbisError.missing_capture_pattern);
    if (0x53 != get8(f)) return error(f, STBVorbisError.missing_capture_pattern);
    if (!start_page_no_capturepattern(f)) return false;
    if (f.page_flag&PAGEFLAG_continued_packet) {
      // set up enough state that we can read this packet if we want,
      // e.g. during recovery
      f.last_seg = false;
      f.bytes_in_seg = 0;
      return error(f, STBVorbisError.continued_packet_flag_invalid);
    }
  }
  return start_packet(f);
}

private int next_segment (VorbisDecoder f) {
  if (f.last_seg) return 0;
  if (f.next_seg == -1) {
    f.last_seg_which = f.segment_count-1; // in case start_page fails
    if (!start_page(f)) { f.last_seg = 1; return 0; }
    if (!(f.page_flag&PAGEFLAG_continued_packet)) return error(f, STBVorbisError.continued_packet_flag_invalid);
  }
  auto len = f.segments.ptr[f.next_seg++];
  if (len < 255) {
    f.last_seg = true;
    f.last_seg_which = f.next_seg-1;
  }
  if (f.next_seg >= f.segment_count) f.next_seg = -1;
  debug(stb_vorbis) assert(f.bytes_in_seg == 0);
  f.bytes_in_seg = len;
  return len;
}

enum EOP = (-1);
enum INVALID_BITS = (-1);

private int get8_packet_raw (VorbisDecoder f) {
  if (!f.bytes_in_seg) {  // CLANG!
    if (f.last_seg) return EOP;
    else if (!next_segment(f)) return EOP;
  }
  debug(stb_vorbis) assert(f.bytes_in_seg > 0);
  --f.bytes_in_seg;
  ++f.packet_bytes;
  return get8(f);
}

private int get8_packet (VorbisDecoder f) {
  int x = get8_packet_raw(f);
  f.valid_bits = 0;
  return x;
}

private uint get32_packet (VorbisDecoder f) {
  uint x = get8_packet(f), b;
  if (x == EOP) return EOP;
  if ((b = get8_packet(f)) == EOP) return EOP;
  x += b<<8;
  if ((b = get8_packet(f)) == EOP) return EOP;
  x += b<<16;
  if ((b = get8_packet(f)) == EOP) return EOP;
  x += b<<24;
  return x;
}

private void flush_packet (VorbisDecoder f) {
  while (get8_packet_raw(f) != EOP) {}
}

// @OPTIMIZE: this is the secondary bit decoder, so it's probably not as important
// as the huffman decoder?
private uint get_bits_main (VorbisDecoder f, int n) {
  uint z;
  if (f.valid_bits < 0) return 0;
  if (f.valid_bits < n) {
    if (n > 24) {
      // the accumulator technique below would not work correctly in this case
      z = get_bits_main(f, 24);
      z += get_bits_main(f, n-24)<<24;
      return z;
    }
    if (f.valid_bits == 0) f.acc = 0;
    while (f.valid_bits < n) {
      z = get8_packet_raw(f);
      if (z == EOP) {
        f.valid_bits = INVALID_BITS;
        return 0;
      }
      f.acc += z<<f.valid_bits;
      f.valid_bits += 8;
    }
  }
  if (f.valid_bits < 0) return 0;
  z = f.acc&((1<<n)-1);
  f.acc >>= n;
  f.valid_bits -= n;
  return z;
}

// chooses minimal possible integer type
private auto get_bits(ubyte n) (VorbisDecoder f) if (n >= 1 && n <= 64) {
  static if (n <= 8) return cast(ubyte)get_bits_main(f, n);
  else static if (n <= 16) return cast(ushort)get_bits_main(f, n);
  else static if (n <= 32) return cast(uint)get_bits_main(f, n);
  else static if (n <= 64) return cast(ulong)get_bits_main(f, n);
  else static assert(0, "wtf?!");
}

// chooses minimal possible integer type, assume no overflow
private auto get_bits_add_no(ubyte n) (VorbisDecoder f, ubyte add) if (n >= 1 && n <= 64) {
  static if (n <= 8) return cast(ubyte)(get_bits_main(f, n)+add);
  else static if (n <= 16) return cast(ushort)(get_bits_main(f, n)+add);
  else static if (n <= 32) return cast(uint)(get_bits_main(f, n)+add);
  else static if (n <= 64) return cast(ulong)(get_bits_main(f, n)+add);
  else static assert(0, "wtf?!");
}

// @OPTIMIZE: primary accumulator for huffman
// expand the buffer to as many bits as possible without reading off end of packet
// it might be nice to allow f.valid_bits and f.acc to be stored in registers,
// e.g. cache them locally and decode locally
//private /*__forceinline*/ void prep_huffman (VorbisDecoder f)
enum PrepHuffmanMixin = q{
  if (f.valid_bits <= 24) {
    if (f.valid_bits == 0) f.acc = 0;
    int phmz = void;
    do {
      if (f.last_seg && !f.bytes_in_seg) break;
      phmz = get8_packet_raw(f);
      if (phmz == EOP) break;
      f.acc += cast(uint)phmz<<f.valid_bits;
      f.valid_bits += 8;
    } while (f.valid_bits <= 24);
  }
};

enum VorbisPacket {
  id = 1,
  comment = 3,
  setup = 5,
}

private int codebook_decode_scalar_raw (VorbisDecoder f, Codebook *c) {
  mixin(PrepHuffmanMixin);

  if (c.codewords is null && c.sorted_codewords is null) return -1;
  // cases to use binary search: sorted_codewords && !c.codewords
  //                             sorted_codewords && c.entries > 8
  auto cond = (c.entries > 8 ? c.sorted_codewords !is null : !c.codewords);
  if (cond) {
    // binary search
    uint code = bit_reverse(f.acc);
    int x = 0, n = c.sorted_entries, len;
    while (n > 1) {
      // invariant: sc[x] <= code < sc[x+n]
      int m = x+(n>>1);
      if (c.sorted_codewords[m] <= code) {
        x = m;
        n -= (n>>1);
      } else {
        n >>= 1;
      }
    }
    // x is now the sorted index
    if (!c.sparse) x = c.sorted_values[x];
    // x is now sorted index if sparse, or symbol otherwise
    len = c.codeword_lengths[x];
    if (f.valid_bits >= len) {
      f.acc >>= len;
      f.valid_bits -= len;
      return x;
    }
    f.valid_bits = 0;
    return -1;
  }
  // if small, linear search
  debug(stb_vorbis) assert(!c.sparse);
  foreach (uint i; 0..c.entries) {
    if (c.codeword_lengths[i] == NO_CODE) continue;
    if (c.codewords[i] == (f.acc&((1<<c.codeword_lengths[i])-1))) {
      if (f.valid_bits >= c.codeword_lengths[i]) {
        f.acc >>= c.codeword_lengths[i];
        f.valid_bits -= c.codeword_lengths[i];
        return i;
      }
      f.valid_bits = 0;
      return -1;
    }
  }
  error(f, STBVorbisError.invalid_stream);
  f.valid_bits = 0;
  return -1;
}


template DECODE_RAW(string var, string c) {
  enum DECODE_RAW = q{
    if (f.valid_bits < STB_VORBIS_FAST_HUFFMAN_LENGTH) { mixin(PrepHuffmanMixin); }
    // fast huffman table lookup
    ${i} = f.acc&FAST_HUFFMAN_TABLE_MASK;
    ${i} = ${c}.fast_huffman.ptr[${i}];
    if (${i} >= 0) {
      auto ${__temp_prefix__}n = ${c}.codeword_lengths[${i}];
      f.acc >>= ${__temp_prefix__}n;
      f.valid_bits -= ${__temp_prefix__}n;
      if (f.valid_bits < 0) { f.valid_bits = 0; ${i} = -1; }
    } else {
      ${i} = codebook_decode_scalar_raw(f, ${c});
    }
  }.cmacroFixVars!("i", "c")(var, c);
}

enum DECODE(string var, string c) = q{
  ${DECODE_RAW}
  if (${c}.sparse) ${var} = ${c}.sorted_values[${var}];
}.cmacroFixVars!("var", "c", "DECODE_RAW")(var, c, DECODE_RAW!(var, c));


version(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
  alias DECODE_VQ = DECODE;
} else {
  alias DECODE_VQ = DECODE_RAW;
}



// CODEBOOK_ELEMENT_FAST is an optimization for the CODEBOOK_FLOATS case
// where we avoid one addition
enum CODEBOOK_ELEMENT(string c, string off) = "("~c~".multiplicands["~off~"])";
enum CODEBOOK_ELEMENT_FAST(string c, string off) = "("~c~".multiplicands["~off~"])";
enum CODEBOOK_ELEMENT_BASE(string c) = "(0)";


private int codebook_decode_start (VorbisDecoder f, Codebook* c) {
  int z = -1;
  // type 0 is only legal in a scalar context
  if (c.lookup_type == 0) {
    error(f, STBVorbisError.invalid_stream);
  } else {
    mixin(DECODE_VQ!("z", "c"));
    debug(stb_vorbis) if (c.sparse) assert(z < c.sorted_entries);
    if (z < 0) {  // check for EOP
      if (!f.bytes_in_seg && f.last_seg) return z;
      error(f, STBVorbisError.invalid_stream);
    }
  }
  return z;
}

private int codebook_decode (VorbisDecoder f, Codebook* c, float* output, int len) {
  int z = codebook_decode_start(f, c);
  if (z < 0) return false;
  if (len > c.dimensions) len = c.dimensions;

  version(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
    if (c.lookup_type == 1) {
      float last = mixin(CODEBOOK_ELEMENT_BASE!"c");
      int div = 1;
      foreach (immutable i; 0..len) {
        int off = (z/div)%c.lookup_values;
        float val = mixin(CODEBOOK_ELEMENT_FAST!("c", "off"))+last;
        output[i] += val;
        if (c.sequence_p) last = val+c.minimum_value;
        div *= c.lookup_values;
      }
      return true;
    }
  }

  z *= c.dimensions;
  if (c.sequence_p) {
    float last = mixin(CODEBOOK_ELEMENT_BASE!"c");
    foreach (immutable i; 0..len) {
      float val = mixin(CODEBOOK_ELEMENT_FAST!("c", "z+i"))+last;
      output[i] += val;
      last = val+c.minimum_value;
    }
  } else {
    float last = mixin(CODEBOOK_ELEMENT_BASE!"c");
    foreach (immutable i; 0..len) output[i] += mixin(CODEBOOK_ELEMENT_FAST!("c", "z+i"))+last;
  }

  return true;
}

private int codebook_decode_step (VorbisDecoder f, Codebook* c, float* output, int len, int step) {
  int z = codebook_decode_start(f, c);
  float last = mixin(CODEBOOK_ELEMENT_BASE!"c");
  if (z < 0) return false;
  if (len > c.dimensions) len = c.dimensions;

  version(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
    if (c.lookup_type == 1) {
      int div = 1;
      foreach (immutable i; 0..len) {
        int off = (z/div)%c.lookup_values;
        float val = mixin(CODEBOOK_ELEMENT_FAST!("c", "off"))+last;
        output[i*step] += val;
        if (c.sequence_p) last = val;
        div *= c.lookup_values;
      }
      return true;
    }
  }

  z *= c.dimensions;
  foreach (immutable i; 0..len) {
    float val = mixin(CODEBOOK_ELEMENT_FAST!("c", "z+i"))+last;
    output[i*step] += val;
    if (c.sequence_p) last = val;
  }

  return true;
}

private int codebook_decode_deinterleave_repeat (VorbisDecoder f, Codebook* c, ref float*[STB_VORBIS_MAX_CHANNELS] outputs, int ch, int* c_inter_p, int* p_inter_p, int len, int total_decode) {
  int c_inter = *c_inter_p;
  int p_inter = *p_inter_p;
  int z, effective = c.dimensions;

  // type 0 is only legal in a scalar context
  if (c.lookup_type == 0) return error(f, STBVorbisError.invalid_stream);

  while (total_decode > 0) {
    float last = mixin(CODEBOOK_ELEMENT_BASE!"c");
    mixin(DECODE_VQ!("z", "c"));
    version(STB_VORBIS_DIVIDES_IN_CODEBOOK) {} else {
      debug(stb_vorbis) assert(!c.sparse || z < c.sorted_entries);
    }
    if (z < 0) {
      if (!f.bytes_in_seg && f.last_seg) return false;
      return error(f, STBVorbisError.invalid_stream);
    }

    // if this will take us off the end of the buffers, stop short!
    // we check by computing the length of the virtual interleaved
    // buffer (len*ch), our current offset within it (p_inter*ch)+(c_inter),
    // and the length we'll be using (effective)
    if (c_inter+p_inter*ch+effective > len*ch) effective = len*ch-(p_inter*ch-c_inter);

    version(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
      if (c.lookup_type == 1) {
        int div = 1;
        foreach (immutable i; 0..effective) {
          int off = (z/div)%c.lookup_values;
          float val = mixin(CODEBOOK_ELEMENT_FAST!("c", "off"))+last;
          if (outputs.ptr[c_inter]) outputs.ptr[c_inter].ptr[p_inter] += val;
          if (++c_inter == ch) { c_inter = 0; ++p_inter; }
          if (c.sequence_p) last = val;
          div *= c.lookup_values;
        }
        goto skipit;
      }
    }
    z *= c.dimensions;
    if (c.sequence_p) {
      foreach (immutable i; 0..effective) {
        float val = mixin(CODEBOOK_ELEMENT_FAST!("c", "z+i"))+last;
        if (outputs.ptr[c_inter]) outputs.ptr[c_inter][p_inter] += val;
        if (++c_inter == ch) { c_inter = 0; ++p_inter; }
        last = val;
      }
    } else {
      foreach (immutable i; 0..effective) {
        float val = mixin(CODEBOOK_ELEMENT_FAST!("c","z+i"))+last;
        if (outputs.ptr[c_inter]) outputs.ptr[c_inter][p_inter] += val;
        if (++c_inter == ch) { c_inter = 0; ++p_inter; }
      }
    }
   skipit:
    total_decode -= effective;
  }
  *c_inter_p = c_inter;
  *p_inter_p = p_inter;
  return true;
}

//private int predict_point (int x, int x0, int x1, int y0, int y1)
enum predict_point(string dest, string x, string x0, string x1, string y0, string y1) = q{{
  //import std.math : abs;
  int dy = ${y1}-${y0};
  int adx = ${x1}-${x0};
  // @OPTIMIZE: force int division to round in the right direction... is this necessary on x86?
  int err = /*abs(dy)*/(dy < 0 ? -dy : dy)*(${x}-${x0});
  int off = err/adx;
  /*return*/${dest} = (dy < 0 ? ${y0}-off : ${y0}+off);
}}.cmacroFixVars!("dest", "x", "x0", "x1", "y0", "y1")(dest, x, x0, x1, y0, y1);

// the following table is block-copied from the specification
immutable float[256] inverse_db_table = [
  1.0649863e-07f, 1.1341951e-07f, 1.2079015e-07f, 1.2863978e-07f,
  1.3699951e-07f, 1.4590251e-07f, 1.5538408e-07f, 1.6548181e-07f,
  1.7623575e-07f, 1.8768855e-07f, 1.9988561e-07f, 2.1287530e-07f,
  2.2670913e-07f, 2.4144197e-07f, 2.5713223e-07f, 2.7384213e-07f,
  2.9163793e-07f, 3.1059021e-07f, 3.3077411e-07f, 3.5226968e-07f,
  3.7516214e-07f, 3.9954229e-07f, 4.2550680e-07f, 4.5315863e-07f,
  4.8260743e-07f, 5.1396998e-07f, 5.4737065e-07f, 5.8294187e-07f,
  6.2082472e-07f, 6.6116941e-07f, 7.0413592e-07f, 7.4989464e-07f,
  7.9862701e-07f, 8.5052630e-07f, 9.0579828e-07f, 9.6466216e-07f,
  1.0273513e-06f, 1.0941144e-06f, 1.1652161e-06f, 1.2409384e-06f,
  1.3215816e-06f, 1.4074654e-06f, 1.4989305e-06f, 1.5963394e-06f,
  1.7000785e-06f, 1.8105592e-06f, 1.9282195e-06f, 2.0535261e-06f,
  2.1869758e-06f, 2.3290978e-06f, 2.4804557e-06f, 2.6416497e-06f,
  2.8133190e-06f, 2.9961443e-06f, 3.1908506e-06f, 3.3982101e-06f,
  3.6190449e-06f, 3.8542308e-06f, 4.1047004e-06f, 4.3714470e-06f,
  4.6555282e-06f, 4.9580707e-06f, 5.2802740e-06f, 5.6234160e-06f,
  5.9888572e-06f, 6.3780469e-06f, 6.7925283e-06f, 7.2339451e-06f,
  7.7040476e-06f, 8.2047000e-06f, 8.7378876e-06f, 9.3057248e-06f,
  9.9104632e-06f, 1.0554501e-05f, 1.1240392e-05f, 1.1970856e-05f,
  1.2748789e-05f, 1.3577278e-05f, 1.4459606e-05f, 1.5399272e-05f,
  1.6400004e-05f, 1.7465768e-05f, 1.8600792e-05f, 1.9809576e-05f,
  2.1096914e-05f, 2.2467911e-05f, 2.3928002e-05f, 2.5482978e-05f,
  2.7139006e-05f, 2.8902651e-05f, 3.0780908e-05f, 3.2781225e-05f,
  3.4911534e-05f, 3.7180282e-05f, 3.9596466e-05f, 4.2169667e-05f,
  4.4910090e-05f, 4.7828601e-05f, 5.0936773e-05f, 5.4246931e-05f,
  5.7772202e-05f, 6.1526565e-05f, 6.5524908e-05f, 6.9783085e-05f,
  7.4317983e-05f, 7.9147585e-05f, 8.4291040e-05f, 8.9768747e-05f,
  9.5602426e-05f, 0.00010181521f, 0.00010843174f, 0.00011547824f,
  0.00012298267f, 0.00013097477f, 0.00013948625f, 0.00014855085f,
  0.00015820453f, 0.00016848555f, 0.00017943469f, 0.00019109536f,
  0.00020351382f, 0.00021673929f, 0.00023082423f, 0.00024582449f,
  0.00026179955f, 0.00027881276f, 0.00029693158f, 0.00031622787f,
  0.00033677814f, 0.00035866388f, 0.00038197188f, 0.00040679456f,
  0.00043323036f, 0.00046138411f, 0.00049136745f, 0.00052329927f,
  0.00055730621f, 0.00059352311f, 0.00063209358f, 0.00067317058f,
  0.00071691700f, 0.00076350630f, 0.00081312324f, 0.00086596457f,
  0.00092223983f, 0.00098217216f, 0.0010459992f,  0.0011139742f,
  0.0011863665f,  0.0012634633f,  0.0013455702f,  0.0014330129f,
  0.0015261382f,  0.0016253153f,  0.0017309374f,  0.0018434235f,
  0.0019632195f,  0.0020908006f,  0.0022266726f,  0.0023713743f,
  0.0025254795f,  0.0026895994f,  0.0028643847f,  0.0030505286f,
  0.0032487691f,  0.0034598925f,  0.0036847358f,  0.0039241906f,
  0.0041792066f,  0.0044507950f,  0.0047400328f,  0.0050480668f,
  0.0053761186f,  0.0057254891f,  0.0060975636f,  0.0064938176f,
  0.0069158225f,  0.0073652516f,  0.0078438871f,  0.0083536271f,
  0.0088964928f,  0.009474637f,   0.010090352f,   0.010746080f,
  0.011444421f,   0.012188144f,   0.012980198f,   0.013823725f,
  0.014722068f,   0.015678791f,   0.016697687f,   0.017782797f,
  0.018938423f,   0.020169149f,   0.021479854f,   0.022875735f,
  0.024362330f,   0.025945531f,   0.027631618f,   0.029427276f,
  0.031339626f,   0.033376252f,   0.035545228f,   0.037855157f,
  0.040315199f,   0.042935108f,   0.045725273f,   0.048696758f,
  0.051861348f,   0.055231591f,   0.058820850f,   0.062643361f,
  0.066714279f,   0.071049749f,   0.075666962f,   0.080584227f,
  0.085821044f,   0.091398179f,   0.097337747f,   0.10366330f,
  0.11039993f,    0.11757434f,    0.12521498f,    0.13335215f,
  0.14201813f,    0.15124727f,    0.16107617f,    0.17154380f,
  0.18269168f,    0.19456402f,    0.20720788f,    0.22067342f,
  0.23501402f,    0.25028656f,    0.26655159f,    0.28387361f,
  0.30232132f,    0.32196786f,    0.34289114f,    0.36517414f,
  0.38890521f,    0.41417847f,    0.44109412f,    0.46975890f,
  0.50028648f,    0.53279791f,    0.56742212f,    0.60429640f,
  0.64356699f,    0.68538959f,    0.72993007f,    0.77736504f,
  0.82788260f,    0.88168307f,    0.9389798f,     1.0f
];


// @OPTIMIZE: if you want to replace this bresenham line-drawing routine,
// note that you must produce bit-identical output to decode correctly;
// this specific sequence of operations is specified in the spec (it's
// drawing integer-quantized frequency-space lines that the encoder
// expects to be exactly the same)
//     ... also, isn't the whole point of Bresenham's algorithm to NOT
// have to divide in the setup? sigh.
version(STB_VORBIS_NO_DEFER_FLOOR) {
  enum LINE_OP(string a, string b) = a~" = "~b~";";
} else {
  enum LINE_OP(string a, string b) = a~" *= "~b~";";
}

version(STB_VORBIS_DIVIDE_TABLE) {
  enum DIVTAB_NUMER = 32;
  enum DIVTAB_DENOM = 64;
  byte[DIVTAB_DENOM][DIVTAB_NUMER] integer_divide_table; // 2KB
}

// nobranch abs trick
enum ABS(string v) = q{(((${v})+((${v})>>31))^((${v})>>31))}.cmacroFixVars!"v"(v);

// this is forceinline, but dmd inliner sux
// but hey, i have my k00l macrosystem!
//void draw_line (float* ${output}, int ${x0}, int ${y0}, int ${x1}, int ${y1}, int ${n})
enum draw_line(string output, string x0, string y0, string x1, string y1, string n) = q{{
  int ${__temp_prefix__}dy = ${y1}-${y0};
  int ${__temp_prefix__}adx = ${x1}-${x0};
  int ${__temp_prefix__}ady = mixin(ABS!"${__temp_prefix__}dy");
  int ${__temp_prefix__}base;
  int ${__temp_prefix__}x = ${x0}, ${__temp_prefix__}y = ${y0};
  int ${__temp_prefix__}err = 0;
  int ${__temp_prefix__}sy;

  version(STB_VORBIS_DIVIDE_TABLE) {
    if (${__temp_prefix__}adx < DIVTAB_DENOM && ${__temp_prefix__}ady < DIVTAB_NUMER) {
      if (${__temp_prefix__}dy < 0) {
        ${__temp_prefix__}base = -integer_divide_table[${__temp_prefix__}ady].ptr[${__temp_prefix__}adx];
        ${__temp_prefix__}sy = ${__temp_prefix__}base-1;
      } else {
        ${__temp_prefix__}base = integer_divide_table[${__temp_prefix__}ady].ptr[${__temp_prefix__}adx];
        ${__temp_prefix__}sy = ${__temp_prefix__}base+1;
      }
    } else {
      ${__temp_prefix__}base = ${__temp_prefix__}dy/${__temp_prefix__}adx;
      ${__temp_prefix__}sy = ${__temp_prefix__}base+(${__temp_prefix__}dy < 0 ? -1 : 1);
    }
  } else {
    ${__temp_prefix__}base = ${__temp_prefix__}dy/${__temp_prefix__}adx;
    ${__temp_prefix__}sy = ${__temp_prefix__}base+(${__temp_prefix__}dy < 0 ? -1 : 1);
  }
  ${__temp_prefix__}ady -= mixin(ABS!"${__temp_prefix__}base")*${__temp_prefix__}adx;
  if (${x1} > ${n}) ${x1} = ${n};
  if (${__temp_prefix__}x < ${x1}) {
    mixin(LINE_OP!("${output}[${__temp_prefix__}x]", "inverse_db_table[${__temp_prefix__}y]"));
    for (++${__temp_prefix__}x; ${__temp_prefix__}x < ${x1}; ++${__temp_prefix__}x) {
      ${__temp_prefix__}err += ${__temp_prefix__}ady;
      if (${__temp_prefix__}err >= ${__temp_prefix__}adx) {
        ${__temp_prefix__}err -= ${__temp_prefix__}adx;
        ${__temp_prefix__}y += ${__temp_prefix__}sy;
      } else {
        ${__temp_prefix__}y += ${__temp_prefix__}base;
      }
      mixin(LINE_OP!("${output}[${__temp_prefix__}x]", "inverse_db_table[${__temp_prefix__}y]"));
    }
  }
  /*
  mixin(LINE_OP!("${output}[${__temp_prefix__}x]", "inverse_db_table[${__temp_prefix__}y]"));
  for (++${__temp_prefix__}x; ${__temp_prefix__}x < ${x1}; ++${__temp_prefix__}x) {
    ${__temp_prefix__}err += ${__temp_prefix__}ady;
    if (${__temp_prefix__}err >= ${__temp_prefix__}adx) {
      ${__temp_prefix__}err -= ${__temp_prefix__}adx;
      ${__temp_prefix__}y += ${__temp_prefix__}sy;
    } else {
      ${__temp_prefix__}y += ${__temp_prefix__}base;
    }
    mixin(LINE_OP!("${output}[${__temp_prefix__}x]", "inverse_db_table[${__temp_prefix__}y]"));
  }
  */
}}.cmacroFixVars!("output", "x0", "y0", "x1", "y1", "n")(output, x0, y0, x1, y1, n);

private int residue_decode (VorbisDecoder f, Codebook* book, float* target, int offset, int n, int rtype) {
  if (rtype == 0) {
    int step = n/book.dimensions;
    foreach (immutable k; 0..step) if (!codebook_decode_step(f, book, target+offset+k, n-offset-k, step)) return false;
  } else {
    for (int k = 0; k < n; ) {
      if (!codebook_decode(f, book, target+offset, n-k)) return false;
      k += book.dimensions;
      offset += book.dimensions;
    }
  }
  return true;
}

private void decode_residue (VorbisDecoder f, ref float*[STB_VORBIS_MAX_CHANNELS] residue_buffers, int ch, int n, int rn, ubyte* do_not_decode) {
  import core.stdc.stdlib : alloca;
  import core.stdc.string : memset;

  Residue* r = f.residue_config+rn;
  int rtype = f.residue_types.ptr[rn];
  int c = r.classbook;
  int classwords = f.codebooks[c].dimensions;
  int n_read = r.end-r.begin;
  int part_read = n_read/r.part_size;
  uint temp_alloc_point = temp_alloc_save(f);
  version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
    int** classifications = cast(int**)mixin(temp_block_array!("f.vrchannels", "part_read*int.sizeof"));
  } else {
    ubyte*** part_classdata = cast(ubyte***)mixin(temp_block_array!("f.vrchannels", "part_read*cast(int)(ubyte*).sizeof"));
  }

  //stb_prof(2);
  foreach (immutable i; 0..ch) if (!do_not_decode[i]) memset(residue_buffers.ptr[i], 0, float.sizeof*n);

  if (rtype == 2 && ch != 1) {
    int j = void;
    for (j = 0; j < ch; ++j) if (!do_not_decode[j]) break;
    if (j == ch) goto done;

    //stb_prof(3);
    foreach (immutable pass; 0..8) {
      int pcount = 0, class_set = 0;
      if (ch == 2) {
        //stb_prof(13);
        while (pcount < part_read) {
          int z = r.begin+pcount*r.part_size;
          int c_inter = (z&1), p_inter = z>>1;
          if (pass == 0) {
            Codebook *cc = f.codebooks+r.classbook;
            int q;
            mixin(DECODE!("q", "cc"));
            if (q == EOP) goto done;
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              for (int i = classwords-1; i >= 0; --i) {
                classifications[0].ptr[i+pcount] = q%r.classifications;
                q /= r.classifications;
              }
            } else {
              part_classdata[0][class_set] = r.classdata[q];
            }
          }
          //stb_prof(5);
          for (int i = 0; i < classwords && pcount < part_read; ++i, ++pcount) {
            int zz = r.begin+pcount*r.part_size;
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              int cc = classifications[0].ptr[pcount];
            } else {
              int cc = part_classdata[0][class_set][i];
            }
            int b = r.residue_books[cc].ptr[pass];
            if (b >= 0) {
              Codebook* book = f.codebooks+b;
              //stb_prof(20); // accounts for X time
              version(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
                if (!codebook_decode_deinterleave_repeat(f, book, residue_buffers, ch, &c_inter, &p_inter, n, r.part_size)) goto done;
              } else {
                // saves 1%
                //if (!codebook_decode_deinterleave_repeat_2(f, book, residue_buffers, &c_inter, &p_inter, n, r.part_size)) goto done; // according to C source
                if (!codebook_decode_deinterleave_repeat(f, book, residue_buffers, ch, &c_inter, &p_inter, n, r.part_size)) goto done;
              }
              //stb_prof(7);
            } else {
              zz += r.part_size;
              c_inter = zz&1;
              p_inter = zz>>1;
            }
          }
          //stb_prof(8);
          version(STB_VORBIS_DIVIDES_IN_RESIDUE) {} else {
            ++class_set;
          }
        }
      } else if (ch == 1) {
        while (pcount < part_read) {
          int z = r.begin+pcount*r.part_size;
          int c_inter = 0, p_inter = z;
          if (pass == 0) {
            Codebook* cc = f.codebooks+r.classbook;
            int q;
            mixin(DECODE!("q", "cc"));
            if (q == EOP) goto done;
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              for (int i = classwords-1; i >= 0; --i) {
                classifications[0].ptr[i+pcount] = q%r.classifications;
                q /= r.classifications;
              }
            } else {
              part_classdata[0][class_set] = r.classdata[q];
            }
          }
          for (int i = 0; i < classwords && pcount < part_read; ++i, ++pcount) {
            int zz = r.begin+pcount*r.part_size;
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              int cc = classifications[0].ptr[pcount];
            } else {
              int cc = part_classdata[0][class_set][i];
            }
            int b = r.residue_books[cc].ptr[pass];
            if (b >= 0) {
              Codebook* book = f.codebooks+b;
              //stb_prof(22);
              if (!codebook_decode_deinterleave_repeat(f, book, residue_buffers, ch, &c_inter, &p_inter, n, r.part_size)) goto done;
              //stb_prof(3);
            } else {
              zz += r.part_size;
              c_inter = 0;
              p_inter = zz;
            }
          }
          version(STB_VORBIS_DIVIDES_IN_RESIDUE) {} else {
            ++class_set;
          }
        }
      } else {
        while (pcount < part_read) {
          int z = r.begin+pcount*r.part_size;
          int c_inter = z%ch, p_inter = z/ch;
          if (pass == 0) {
            Codebook* cc = f.codebooks+r.classbook;
            int q;
            mixin(DECODE!("q", "cc"));
            if (q == EOP) goto done;
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              for (int i = classwords-1; i >= 0; --i) {
                classifications[0].ptr[i+pcount] = q%r.classifications;
                q /= r.classifications;
              }
            } else {
              part_classdata[0][class_set] = r.classdata[q];
            }
          }
          for (int i = 0; i < classwords && pcount < part_read; ++i, ++pcount) {
            int zz = r.begin+pcount*r.part_size;
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              int cc = classifications[0].ptr[pcount];
            } else {
              int cc = part_classdata[0][class_set][i];
            }
            int b = r.residue_books[cc].ptr[pass];
            if (b >= 0) {
              Codebook* book = f.codebooks+b;
              //stb_prof(22);
              if (!codebook_decode_deinterleave_repeat(f, book, residue_buffers, ch, &c_inter, &p_inter, n, r.part_size)) goto done;
              //stb_prof(3);
            } else {
              zz += r.part_size;
              c_inter = zz%ch;
              p_inter = zz/ch;
            }
          }
          version(STB_VORBIS_DIVIDES_IN_RESIDUE) {} else {
            ++class_set;
          }
        }
      }
    }
    goto done;
  }
  //stb_prof(9);

  foreach (immutable pass; 0..8) {
    int pcount = 0, class_set=0;
    while (pcount < part_read) {
      if (pass == 0) {
        foreach (immutable j; 0..ch) {
          if (!do_not_decode[j]) {
            Codebook* cc = f.codebooks+r.classbook;
            int temp;
            mixin(DECODE!("temp", "cc"));
            if (temp == EOP) goto done;
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              for (int i = classwords-1; i >= 0; --i) {
                classifications[j].ptr[i+pcount] = temp%r.classifications;
                temp /= r.classifications;
              }
            } else {
              part_classdata[j][class_set] = r.classdata[temp];
            }
          }
        }
      }
      for (int i = 0; i < classwords && pcount < part_read; ++i, ++pcount) {
        foreach (immutable j; 0..ch) {
          if (!do_not_decode[j]) {
            version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
              int cc = classifications[j].ptr[pcount];
            } else {
              int cc = part_classdata[j][class_set][i];
            }
            int b = r.residue_books[cc].ptr[pass];
            if (b >= 0) {
              float* target = residue_buffers.ptr[j];
              int offset = r.begin+pcount*r.part_size;
              int nn = r.part_size;
              Codebook* book = f.codebooks+b;
              if (!residue_decode(f, book, target, offset, nn, rtype)) goto done;
            }
          }
        }
      }
      version(STB_VORBIS_DIVIDES_IN_RESIDUE) {} else {
        ++class_set;
      }
    }
  }
 done:
  //stb_prof(0);
  version(STB_VORBIS_DIVIDES_IN_RESIDUE) temp_free(f, classifications); else temp_free(f, part_classdata);
  temp_alloc_restore(f, temp_alloc_point);
}


// the following were split out into separate functions while optimizing;
// they could be pushed back up but eh. __forceinline showed no change;
// they're probably already being inlined.
private void imdct_step3_iter0_loop (int n, float* e, int i_off, int k_off, float* A) {
  float* ee0 = e+i_off;
  float* ee2 = ee0+k_off;
  debug(stb_vorbis) assert((n&3) == 0);
  foreach (immutable _; 0..n>>2) {
    float k00_20, k01_21;
    k00_20 = ee0[ 0]-ee2[ 0];
    k01_21 = ee0[-1]-ee2[-1];
    ee0[ 0] += ee2[ 0];//ee0[ 0] = ee0[ 0]+ee2[ 0];
    ee0[-1] += ee2[-1];//ee0[-1] = ee0[-1]+ee2[-1];
    ee2[ 0] = k00_20*A[0]-k01_21*A[1];
    ee2[-1] = k01_21*A[0]+k00_20*A[1];
    A += 8;

    k00_20 = ee0[-2]-ee2[-2];
    k01_21 = ee0[-3]-ee2[-3];
    ee0[-2] += ee2[-2];//ee0[-2] = ee0[-2]+ee2[-2];
    ee0[-3] += ee2[-3];//ee0[-3] = ee0[-3]+ee2[-3];
    ee2[-2] = k00_20*A[0]-k01_21*A[1];
    ee2[-3] = k01_21*A[0]+k00_20*A[1];
    A += 8;

    k00_20 = ee0[-4]-ee2[-4];
    k01_21 = ee0[-5]-ee2[-5];
    ee0[-4] += ee2[-4];//ee0[-4] = ee0[-4]+ee2[-4];
    ee0[-5] += ee2[-5];//ee0[-5] = ee0[-5]+ee2[-5];
    ee2[-4] = k00_20*A[0]-k01_21*A[1];
    ee2[-5] = k01_21*A[0]+k00_20*A[1];
    A += 8;

    k00_20 = ee0[-6]-ee2[-6];
    k01_21 = ee0[-7]-ee2[-7];
    ee0[-6] += ee2[-6];//ee0[-6] = ee0[-6]+ee2[-6];
    ee0[-7] += ee2[-7];//ee0[-7] = ee0[-7]+ee2[-7];
    ee2[-6] = k00_20*A[0]-k01_21*A[1];
    ee2[-7] = k01_21*A[0]+k00_20*A[1];
    A += 8;
    ee0 -= 8;
    ee2 -= 8;
  }
}

private void imdct_step3_inner_r_loop (int lim, float* e, int d0, int k_off, float* A, int k1) {
  float k00_20, k01_21;
  float* e0 = e+d0;
  float* e2 = e0+k_off;
  foreach (immutable _; 0..lim>>2) {
    k00_20 = e0[-0]-e2[-0];
    k01_21 = e0[-1]-e2[-1];
    e0[-0] += e2[-0];//e0[-0] = e0[-0]+e2[-0];
    e0[-1] += e2[-1];//e0[-1] = e0[-1]+e2[-1];
    e2[-0] = (k00_20)*A[0]-(k01_21)*A[1];
    e2[-1] = (k01_21)*A[0]+(k00_20)*A[1];

    A += k1;

    k00_20 = e0[-2]-e2[-2];
    k01_21 = e0[-3]-e2[-3];
    e0[-2] += e2[-2];//e0[-2] = e0[-2]+e2[-2];
    e0[-3] += e2[-3];//e0[-3] = e0[-3]+e2[-3];
    e2[-2] = (k00_20)*A[0]-(k01_21)*A[1];
    e2[-3] = (k01_21)*A[0]+(k00_20)*A[1];

    A += k1;

    k00_20 = e0[-4]-e2[-4];
    k01_21 = e0[-5]-e2[-5];
    e0[-4] += e2[-4];//e0[-4] = e0[-4]+e2[-4];
    e0[-5] += e2[-5];//e0[-5] = e0[-5]+e2[-5];
    e2[-4] = (k00_20)*A[0]-(k01_21)*A[1];
    e2[-5] = (k01_21)*A[0]+(k00_20)*A[1];

    A += k1;

    k00_20 = e0[-6]-e2[-6];
    k01_21 = e0[-7]-e2[-7];
    e0[-6] += e2[-6];//e0[-6] = e0[-6]+e2[-6];
    e0[-7] += e2[-7];//e0[-7] = e0[-7]+e2[-7];
    e2[-6] = (k00_20)*A[0]-(k01_21)*A[1];
    e2[-7] = (k01_21)*A[0]+(k00_20)*A[1];

    e0 -= 8;
    e2 -= 8;

    A += k1;
  }
}

private void imdct_step3_inner_s_loop (int n, float* e, int i_off, int k_off, float* A, int a_off, int k0) {
  float A0 = A[0];
  float A1 = A[0+1];
  float A2 = A[0+a_off];
  float A3 = A[0+a_off+1];
  float A4 = A[0+a_off*2+0];
  float A5 = A[0+a_off*2+1];
  float A6 = A[0+a_off*3+0];
  float A7 = A[0+a_off*3+1];
  float k00, k11;
  float *ee0 = e  +i_off;
  float *ee2 = ee0+k_off;
  foreach (immutable _; 0..n) {
    k00 = ee0[ 0]-ee2[ 0];
    k11 = ee0[-1]-ee2[-1];
    ee0[ 0] = ee0[ 0]+ee2[ 0];
    ee0[-1] = ee0[-1]+ee2[-1];
    ee2[ 0] = (k00)*A0-(k11)*A1;
    ee2[-1] = (k11)*A0+(k00)*A1;

    k00 = ee0[-2]-ee2[-2];
    k11 = ee0[-3]-ee2[-3];
    ee0[-2] = ee0[-2]+ee2[-2];
    ee0[-3] = ee0[-3]+ee2[-3];
    ee2[-2] = (k00)*A2-(k11)*A3;
    ee2[-3] = (k11)*A2+(k00)*A3;

    k00 = ee0[-4]-ee2[-4];
    k11 = ee0[-5]-ee2[-5];
    ee0[-4] = ee0[-4]+ee2[-4];
    ee0[-5] = ee0[-5]+ee2[-5];
    ee2[-4] = (k00)*A4-(k11)*A5;
    ee2[-5] = (k11)*A4+(k00)*A5;

    k00 = ee0[-6]-ee2[-6];
    k11 = ee0[-7]-ee2[-7];
    ee0[-6] = ee0[-6]+ee2[-6];
    ee0[-7] = ee0[-7]+ee2[-7];
    ee2[-6] = (k00)*A6-(k11)*A7;
    ee2[-7] = (k11)*A6+(k00)*A7;

    ee0 -= k0;
    ee2 -= k0;
  }
}

// this was forceinline
//void iter_54(float *z)
enum iter_54(string z) = q{{
  auto ${__temp_prefix__}z = (${z});
  float ${__temp_prefix__}k00, ${__temp_prefix__}k11, ${__temp_prefix__}k22, ${__temp_prefix__}k33;
  float ${__temp_prefix__}y0, ${__temp_prefix__}y1, ${__temp_prefix__}y2, ${__temp_prefix__}y3;

  ${__temp_prefix__}k00 = ${__temp_prefix__}z[ 0]-${__temp_prefix__}z[-4];
  ${__temp_prefix__}y0  = ${__temp_prefix__}z[ 0]+${__temp_prefix__}z[-4];
  ${__temp_prefix__}y2  = ${__temp_prefix__}z[-2]+${__temp_prefix__}z[-6];
  ${__temp_prefix__}k22 = ${__temp_prefix__}z[-2]-${__temp_prefix__}z[-6];

  ${__temp_prefix__}z[-0] = ${__temp_prefix__}y0+${__temp_prefix__}y2;   // z0+z4+z2+z6
  ${__temp_prefix__}z[-2] = ${__temp_prefix__}y0-${__temp_prefix__}y2;   // z0+z4-z2-z6

  // done with ${__temp_prefix__}y0, ${__temp_prefix__}y2

  ${__temp_prefix__}k33 = ${__temp_prefix__}z[-3]-${__temp_prefix__}z[-7];

  ${__temp_prefix__}z[-4] = ${__temp_prefix__}k00+${__temp_prefix__}k33; // z0-z4+z3-z7
  ${__temp_prefix__}z[-6] = ${__temp_prefix__}k00-${__temp_prefix__}k33; // z0-z4-z3+z7

  // done with ${__temp_prefix__}k33

  ${__temp_prefix__}k11 = ${__temp_prefix__}z[-1]-${__temp_prefix__}z[-5];
  ${__temp_prefix__}y1  = ${__temp_prefix__}z[-1]+${__temp_prefix__}z[-5];
  ${__temp_prefix__}y3  = ${__temp_prefix__}z[-3]+${__temp_prefix__}z[-7];

  ${__temp_prefix__}z[-1] = ${__temp_prefix__}y1+${__temp_prefix__}y3;   // z1+z5+z3+z7
  ${__temp_prefix__}z[-3] = ${__temp_prefix__}y1-${__temp_prefix__}y3;   // z1+z5-z3-z7
  ${__temp_prefix__}z[-5] = ${__temp_prefix__}k11-${__temp_prefix__}k22; // z1-z5+z2-z6
  ${__temp_prefix__}z[-7] = ${__temp_prefix__}k11+${__temp_prefix__}k22; // z1-z5-z2+z6
}}.cmacroFixVars!"z"(z);

static void imdct_step3_inner_s_loop_ld654(int n, float *e, int i_off, float *A, int base_n)
{
    int a_off = base_n >> 3;
    float A2 = A[0+a_off];
    float *z = e + i_off;
    float *base = z - 16 * n;

    while (z > base) {
        float k00,k11;
        float l00,l11;

        k00    = z[-0] - z[ -8];
        k11    = z[-1] - z[ -9];
        l00    = z[-2] - z[-10];
        l11    = z[-3] - z[-11];
        z[ -0] = z[-0] + z[ -8];
        z[ -1] = z[-1] + z[ -9];
        z[ -2] = z[-2] + z[-10];
        z[ -3] = z[-3] + z[-11];
        z[ -8] = k00;
        z[ -9] = k11;
        z[-10] = (l00+l11) * A2;
        z[-11] = (l11-l00) * A2;

        k00    = z[ -4] - z[-12];
        k11    = z[ -5] - z[-13];
        l00    = z[ -6] - z[-14];
        l11    = z[ -7] - z[-15];
        z[ -4] = z[ -4] + z[-12];
        z[ -5] = z[ -5] + z[-13];
        z[ -6] = z[ -6] + z[-14];
        z[ -7] = z[ -7] + z[-15];
        z[-12] = k11;
        z[-13] = -k00;
        z[-14] = (l11-l00) * A2;
        z[-15] = (l00+l11) * -A2;

        mixin(iter_54!"z");
        mixin(iter_54!"z-8");
        z -= 16;
    }
}

private void inverse_mdct (float* buffer, int n, VorbisDecoder f, int blocktype) {
  import core.stdc.stdlib : alloca;

  int n2 = n>>1, n4 = n>>2, n8 = n>>3, l;
  int ld;
  // @OPTIMIZE: reduce register pressure by using fewer variables?
  int save_point = temp_alloc_save(f);
  float *buf2;
  buf2 = cast(float*)mixin(temp_alloc!("n2*float.sizeof"));
  float *u = null, v = null;
  // twiddle factors
  float *A = f.A.ptr[blocktype];

  // IMDCT algorithm from "The use of multirate filter banks for coding of high quality digital audio"
  // See notes about bugs in that paper in less-optimal implementation 'inverse_mdct_old' after this function.

  // kernel from paper


  // merged:
  //   copy and reflect spectral data
  //   step 0

  // note that it turns out that the items added together during
  // this step are, in fact, being added to themselves (as reflected
  // by step 0). inexplicable inefficiency! this became obvious
  // once I combined the passes.

  // so there's a missing 'times 2' here (for adding X to itself).
  // this propogates through linearly to the end, where the numbers
  // are 1/2 too small, and need to be compensated for.

  {
    float* d, e, AA, e_stop;
    d = &buf2[n2-2];
    AA = A;
    e = &buffer[0];
    e_stop = &buffer[n2];
    while (e != e_stop) {
      d[1] = (e[0]*AA[0]-e[2]*AA[1]);
      d[0] = (e[0]*AA[1]+e[2]*AA[0]);
      d -= 2;
      AA += 2;
      e += 4;
    }
    e = &buffer[n2-3];
    while (d >= buf2) {
      d[1] = (-e[2]*AA[0]- -e[0]*AA[1]);
      d[0] = (-e[2]*AA[1]+ -e[0]*AA[0]);
      d -= 2;
      AA += 2;
      e -= 4;
    }
  }

  // now we use symbolic names for these, so that we can
  // possibly swap their meaning as we change which operations
  // are in place

  u = buffer;
  v = buf2;

  // step 2    (paper output is w, now u)
  // this could be in place, but the data ends up in the wrong
  // place... _somebody_'s got to swap it, so this is nominated
  {
    float* AA = &A[n2-8];
    float* d0, d1, e0, e1;
    e0 = &v[n4];
    e1 = &v[0];
    d0 = &u[n4];
    d1 = &u[0];
    while (AA >= A) {
      float v40_20, v41_21;

      v41_21 = e0[1]-e1[1];
      v40_20 = e0[0]-e1[0];
      d0[1]  = e0[1]+e1[1];
      d0[0]  = e0[0]+e1[0];
      d1[1]  = v41_21*AA[4]-v40_20*AA[5];
      d1[0]  = v40_20*AA[4]+v41_21*AA[5];

      v41_21 = e0[3]-e1[3];
      v40_20 = e0[2]-e1[2];
      d0[3]  = e0[3]+e1[3];
      d0[2]  = e0[2]+e1[2];
      d1[3]  = v41_21*AA[0]-v40_20*AA[1];
      d1[2]  = v40_20*AA[0]+v41_21*AA[1];

      AA -= 8;

      d0 += 4;
      d1 += 4;
      e0 += 4;
      e1 += 4;
    }
  }

  // step 3
  ld = ilog(n)-1; // ilog is off-by-one from normal definitions

  // optimized step 3:

  // the original step3 loop can be nested r inside s or s inside r;
  // it's written originally as s inside r, but this is dumb when r
  // iterates many times, and s few. So I have two copies of it and
  // switch between them halfway.

  // this is iteration 0 of step 3
  imdct_step3_iter0_loop(n>>4, u, n2-1-n4*0, -(n>>3), A);
  imdct_step3_iter0_loop(n>>4, u, n2-1-n4*1, -(n>>3), A);

  // this is iteration 1 of step 3
  imdct_step3_inner_r_loop(n>>5, u, n2-1-n8*0, -(n>>4), A, 16);
  imdct_step3_inner_r_loop(n>>5, u, n2-1-n8*1, -(n>>4), A, 16);
  imdct_step3_inner_r_loop(n>>5, u, n2-1-n8*2, -(n>>4), A, 16);
  imdct_step3_inner_r_loop(n>>5, u, n2-1-n8*3, -(n>>4), A, 16);

  l = 2;
  for (; l < (ld-3)>>1; ++l) {
    int k0 = n>>(l+2), k0_2 = k0>>1;
    int lim = 1<<(l+1);
    foreach (int i; 0..lim) imdct_step3_inner_r_loop(n>>(l+4), u, n2-1-k0*i, -k0_2, A, 1<<(l+3));
  }

  for (; l < ld-6; ++l) {
    int k0 = n>>(l+2), k1 = 1<<(l+3), k0_2 = k0>>1;
    int rlim = n>>(l+6);
    int lim = 1<<(l+1);
    int i_off;
    float *A0 = A;
    i_off = n2-1;
    foreach (immutable _; 0..rlim) {
      imdct_step3_inner_s_loop(lim, u, i_off, -k0_2, A0, k1, k0);
      A0 += k1*4;
      i_off -= 8;
    }
  }

  // iterations with count:
  //   ld-6,-5,-4 all interleaved together
  //       the big win comes from getting rid of needless flops
  //         due to the constants on pass 5 & 4 being all 1 and 0;
  //       combining them to be simultaneous to improve cache made little difference
  imdct_step3_inner_s_loop_ld654(n>>5, u, n2-1, A, n);

  // output is u

  // step 4, 5, and 6
  // cannot be in-place because of step 5
  {
    ushort *bitrev = f.bit_reverse.ptr[blocktype];
    // weirdly, I'd have thought reading sequentially and writing
    // erratically would have been better than vice-versa, but in
    // fact that's not what my testing showed. (That is, with
    // j = bitreverse(i), do you read i and write j, or read j and write i.)
    float *d0 = &v[n4-4];
    float *d1 = &v[n2-4];
    int k4;
    while (d0 >= v) {
      k4 = bitrev[0];
      d1[3] = u[k4+0];
      d1[2] = u[k4+1];
      d0[3] = u[k4+2];
      d0[2] = u[k4+3];

      k4 = bitrev[1];
      d1[1] = u[k4+0];
      d1[0] = u[k4+1];
      d0[1] = u[k4+2];
      d0[0] = u[k4+3];

      d0 -= 4;
      d1 -= 4;
      bitrev += 2;
    }
  }
  // (paper output is u, now v)


  // data must be in buf2
  debug(stb_vorbis) assert(v == buf2);

  // step 7   (paper output is v, now v)
  // this is now in place
  {
    float a02, a11, b0, b1, b2, b3;
    float* C = f.C.ptr[blocktype];
    float* d, e;
    d = v;
    e = v+n2-4;
    while (d < e) {
      a02 = d[0]-e[2];
      a11 = d[1]+e[3];

      b0 = C[1]*a02+C[0]*a11;
      b1 = C[1]*a11-C[0]*a02;

      b2 = d[0]+e[ 2];
      b3 = d[1]-e[ 3];

      d[0] = b2+b0;
      d[1] = b3+b1;
      e[2] = b2-b0;
      e[3] = b1-b3;

      a02 = d[2]-e[0];
      a11 = d[3]+e[1];

      b0 = C[3]*a02+C[2]*a11;
      b1 = C[3]*a11-C[2]*a02;

      b2 = d[2]+e[ 0];
      b3 = d[3]-e[ 1];

      d[2] = b2+b0;
      d[3] = b3+b1;
      e[0] = b2-b0;
      e[1] = b1-b3;

      C += 4;
      d += 4;
      e -= 4;
    }
  }

  // data must be in buf2


  // step 8+decode   (paper output is X, now buffer)
  // this generates pairs of data a la 8 and pushes them directly through
  // the decode kernel (pushing rather than pulling) to avoid having
  // to make another pass later

  // this cannot POSSIBLY be in place, so we refer to the buffers directly
  {
    float p0, p1, p2, p3;
    float* d0, d1, d2, d3;
    float* B = f.B.ptr[blocktype]+n2-8;
    float* e = buf2+n2-8;
    d0 = &buffer[0];
    d1 = &buffer[n2-4];
    d2 = &buffer[n2];
    d3 = &buffer[n-4];
    while (e >= v) {
      p3 =  e[6]*B[7]-e[7]*B[6];
      p2 = -e[6]*B[6]-e[7]*B[7];

      d0[0] =   p3;
      d1[3] =  -p3;
      d2[0] =   p2;
      d3[3] =   p2;

      p1 =  e[4]*B[5]-e[5]*B[4];
      p0 = -e[4]*B[4]-e[5]*B[5];

      d0[1] =   p1;
      d1[2] = - p1;
      d2[1] =   p0;
      d3[2] =   p0;

      p3 =  e[2]*B[3]-e[3]*B[2];
      p2 = -e[2]*B[2]-e[3]*B[3];

      d0[2] =   p3;
      d1[1] = - p3;
      d2[2] =   p2;
      d3[1] =   p2;

      p1 =  e[0]*B[1]-e[1]*B[0];
      p0 = -e[0]*B[0]-e[1]*B[1];

      d0[3] =   p1;
      d1[0] = - p1;
      d2[3] =   p0;
      d3[0] =   p0;

      B -= 8;
      e -= 8;
      d0 += 4;
      d2 += 4;
      d1 -= 4;
      d3 -= 4;
    }
  }

  temp_free(f, buf2);
  temp_alloc_restore(f, save_point);
}

private float *get_window (VorbisDecoder f, int len) {
  len <<= 1;
  if (len == f.blocksize_0) return f.window.ptr[0];
  if (len == f.blocksize_1) return f.window.ptr[1];
  assert(0);
}

version(STB_VORBIS_NO_DEFER_FLOOR) {
  alias YTYPE = int;
} else {
  alias YTYPE = short;
}

private int do_floor (VorbisDecoder f, Mapping* map, int i, int n, float* target, YTYPE* finalY, ubyte* step2_flag) {
  int n2 = n>>1;
  int s = map.chan[i].mux, floor;
  floor = map.submap_floor.ptr[s];
  if (f.floor_types.ptr[floor] == 0) {
    return error(f, STBVorbisError.invalid_stream);
  } else {
    Floor1* g = &f.floor_config[floor].floor1;
    int lx = 0, ly = finalY[0]*g.floor1_multiplier;
    foreach (immutable q; 1..g.values) {
      int j = g.sorted_order.ptr[q];
      version(STB_VORBIS_NO_DEFER_FLOOR) {
        auto cond = step2_flag[j];
      } else {
        auto cond = (finalY[j] >= 0);
      }
      if (cond) {
        int hy = finalY[j]*g.floor1_multiplier;
        int hx = g.Xlist.ptr[j];
        if (lx != hx) { mixin(draw_line!("target", "lx", "ly", "hx", "hy", "n2")); }
        lx = hx; ly = hy;
      }
    }
    if (lx < n2) {
      // optimization of: draw_line(target, lx, ly, n, ly, n2);
      foreach (immutable j; lx..n2) { mixin(LINE_OP!("target[j]", "inverse_db_table[ly]")); }
    }
  }
  return true;
}

// The meaning of "left" and "right"
//
// For a given frame:
//     we compute samples from 0..n
//     window_center is n/2
//     we'll window and mix the samples from left_start to left_end with data from the previous frame
//     all of the samples from left_end to right_start can be output without mixing; however,
//        this interval is 0-length except when transitioning between short and long frames
//     all of the samples from right_start to right_end need to be mixed with the next frame,
//        which we don't have, so those get saved in a buffer
//     frame N's right_end-right_start, the number of samples to mix with the next frame,
//        has to be the same as frame N+1's left_end-left_start (which they are by
//        construction)

private int vorbis_decode_initial (VorbisDecoder f, int* p_left_start, int* p_left_end, int* p_right_start, int* p_right_end, int* mode) {
  Mode *m;
  int i, n, prev, next, window_center;
  f.channel_buffer_start = f.channel_buffer_end = 0;

 retry:
  if (f.eof) return false;
  if (!maybe_start_packet(f)) return false;
  // check packet type
  if (get_bits!1(f) != 0) {
    /+if (f.push_mode) return error(f, STBVorbisError.bad_packet_type);+/
    while (EOP != get8_packet(f)) {}
    goto retry;
  }

  //debug(stb_vorbis) if (f.alloc.alloc_buffer) assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);

  i = get_bits_main(f, ilog(f.mode_count-1));
  if (i == EOP) return false;
  if (i >= f.mode_count) return false;
  *mode = i;
  m = f.mode_config.ptr+i;
  if (m.blockflag) {
    n = f.blocksize_1;
    prev = get_bits!1(f);
    next = get_bits!1(f);
  } else {
    prev = next = 0;
    n = f.blocksize_0;
  }

  // WINDOWING
  window_center = n>>1;
  if (m.blockflag && !prev) {
    *p_left_start = (n-f.blocksize_0)>>2;
    *p_left_end   = (n+f.blocksize_0)>>2;
  } else {
    *p_left_start = 0;
    *p_left_end   = window_center;
  }
  if (m.blockflag && !next) {
    *p_right_start = (n*3-f.blocksize_0)>>2;
    *p_right_end   = (n*3+f.blocksize_0)>>2;
  } else {
    *p_right_start = window_center;
    *p_right_end   = n;
  }
  return true;
}

private int vorbis_decode_packet_rest (VorbisDecoder f, int* len, Mode* m, int left_start, int left_end, int right_start, int right_end, int* p_left) {
  import core.stdc.string : memcpy, memset;

  Mapping* map;
  int n, n2;
  int[256] zero_channel;
  int[256] really_zero_channel;

  // WINDOWING
  n = f.blocksize.ptr[m.blockflag];
  map = &f.mapping[m.mapping];

  // FLOORS
  n2 = n>>1;

  //stb_prof(1);
  foreach (immutable i; 0..f.vrchannels) {
    int s = map.chan[i].mux, floor;
    zero_channel[i] = false;
    floor = map.submap_floor.ptr[s];
    if (f.floor_types.ptr[floor] == 0) {
      return error(f, STBVorbisError.invalid_stream);
    } else {
      Floor1* g = &f.floor_config[floor].floor1;
      if (get_bits!1(f)) {
        short* finalY;
        ubyte[256] step2_flag = void;
        immutable int[4] range_list = [ 256, 128, 86, 64 ];
        int range = range_list[g.floor1_multiplier-1];
        int offset = 2;
        finalY = f.finalY.ptr[i];
        finalY[0] = cast(short)get_bits_main(f, ilog(range)-1); //k8
        finalY[1] = cast(short)get_bits_main(f, ilog(range)-1); //k8
        foreach (immutable j; 0..g.partitions) {
          int pclass = g.partition_class_list.ptr[j];
          int cdim = g.class_dimensions.ptr[pclass];
          int cbits = g.class_subclasses.ptr[pclass];
          int csub = (1<<cbits)-1;
          int cval = 0;
          if (cbits) {
            Codebook *cc = f.codebooks+g.class_masterbooks.ptr[pclass];
            mixin(DECODE!("cval", "cc"));
          }
          foreach (immutable k; 0..cdim) {
            int book = g.subclass_books.ptr[pclass].ptr[cval&csub];
            cval = cval>>cbits;
            if (book >= 0) {
              int temp;
              Codebook *cc = f.codebooks+book;
              mixin(DECODE!("temp", "cc"));
              finalY[offset++] = cast(short)temp; //k8
            } else {
              finalY[offset++] = 0;
            }
          }
        }
        if (f.valid_bits == INVALID_BITS) goto error; // behavior according to spec
        step2_flag[0] = step2_flag[1] = 1;
        foreach (immutable j; 2..g.values) {
          int low = g.neighbors.ptr[j].ptr[0];
          int high = g.neighbors.ptr[j].ptr[1];
          //neighbors(g.Xlist, j, &low, &high);
          int pred = void;
          mixin(predict_point!("pred", "g.Xlist.ptr[j]", "g.Xlist.ptr[low]", "g.Xlist.ptr[high]", "finalY[low]", "finalY[high]"));
          int val = finalY[j];
          int highroom = range-pred;
          int lowroom = pred;
          auto room = (highroom < lowroom ? highroom : lowroom)*2;
          if (val) {
            step2_flag[low] = step2_flag[high] = 1;
            step2_flag[j] = 1;
            if (val >= room) {
              finalY[j] = cast(short)(highroom > lowroom ? val-lowroom+pred : pred-val+highroom-1); //k8
            } else {
              finalY[j] = cast(short)(val&1 ? pred-((val+1)>>1) : pred+(val>>1)); //k8
            }
          } else {
            step2_flag[j] = 0;
            finalY[j] = cast(short)pred; //k8
          }
        }

        version(STB_VORBIS_NO_DEFER_FLOOR) {
          do_floor(f, map, i, n, f.floor_buffers.ptr[i], finalY, step2_flag);
        } else {
          // defer final floor computation until _after_ residue
          foreach (immutable j; 0..g.values) if (!step2_flag[j]) finalY[j] = -1;
        }
      } else {
  error:
        zero_channel[i] = true;
      }
      // So we just defer everything else to later
      // at this point we've decoded the floor into buffer
    }
  }
  //stb_prof(0);
  // at this point we've decoded all floors

  //debug(stb_vorbis) if (f.alloc.alloc_buffer) assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);

  // re-enable coupled channels if necessary
  memcpy(really_zero_channel.ptr, zero_channel.ptr, (really_zero_channel[0]).sizeof*f.vrchannels);
  foreach (immutable i; 0..map.coupling_steps) {
    if (!zero_channel[map.chan[i].magnitude] || !zero_channel[map.chan[i].angle]) {
      zero_channel[map.chan[i].magnitude] = zero_channel[map.chan[i].angle] = false;
    }
  }

  // RESIDUE DECODE
  foreach (immutable i; 0..map.submaps) {
    float*[STB_VORBIS_MAX_CHANNELS] residue_buffers;
    ubyte[256] do_not_decode = void;
    int ch = 0;
    foreach (immutable j; 0..f.vrchannels) {
      if (map.chan[j].mux == i) {
        if (zero_channel[j]) {
          do_not_decode[ch] = true;
          residue_buffers.ptr[ch] = null;
        } else {
          do_not_decode[ch] = false;
          residue_buffers.ptr[ch] = f.channel_buffers.ptr[j];
        }
        ++ch;
      }
    }
    int r = map.submap_residue.ptr[i];
    decode_residue(f, residue_buffers, ch, n2, r, do_not_decode.ptr);
  }

  //debug(stb_vorbis) if (f.alloc.alloc_buffer) assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);

   // INVERSE COUPLING
  //stb_prof(14);
  foreach_reverse (immutable i; 0..map.coupling_steps) {
    int n2n = n>>1;
    float* mm = f.channel_buffers.ptr[map.chan[i].magnitude];
    float* a = f.channel_buffers.ptr[map.chan[i].angle];
    foreach (immutable j; 0..n2n) {
      float a2, m2;
      if (mm[j] > 0) {
        if (a[j] > 0) { m2 = mm[j]; a2 = mm[j]-a[j]; } else { a2 = mm[j]; m2 = mm[j]+a[j]; }
      } else {
        if (a[j] > 0) { m2 = mm[j]; a2 = mm[j]+a[j]; } else { a2 = mm[j]; m2 = mm[j]-a[j]; }
      }
      mm[j] = m2;
      a[j] = a2;
    }
  }

  // finish decoding the floors
  version(STB_VORBIS_NO_DEFER_FLOOR) {
    foreach (immutable i; 0..f.vrchannels) {
      if (really_zero_channel[i]) {
        memset(f.channel_buffers.ptr[i], 0, (*f.channel_buffers.ptr[i]).sizeof*n2);
      } else {
        foreach (immutable j; 0..n2) f.channel_buffers.ptr[i].ptr[j] *= f.floor_buffers.ptr[i].ptr[j];
      }
    }
  } else {
    //stb_prof(15);
    foreach (immutable i; 0..f.vrchannels) {
      if (really_zero_channel[i]) {
        memset(f.channel_buffers.ptr[i], 0, (*f.channel_buffers.ptr[i]).sizeof*n2);
      } else {
        do_floor(f, map, i, n, f.channel_buffers.ptr[i], f.finalY.ptr[i], null);
      }
    }
  }

  // INVERSE MDCT
  //stb_prof(16);
  foreach (immutable i; 0..f.vrchannels) inverse_mdct(f.channel_buffers.ptr[i], n, f, m.blockflag);
  //stb_prof(0);

  // this shouldn't be necessary, unless we exited on an error
  // and want to flush to get to the next packet
  flush_packet(f);

  if (f.first_decode) {
    // assume we start so first non-discarded sample is sample 0
    // this isn't to spec, but spec would require us to read ahead
    // and decode the size of all current frames--could be done,
    // but presumably it's not a commonly used feature
    f.current_loc = -n2; // start of first frame is positioned for discard
    // we might have to discard samples "from" the next frame too,
    // if we're lapping a large block then a small at the start?
    f.discard_samples_deferred = n-right_end;
    f.current_loc_valid = true;
    f.first_decode = false;
  } else if (f.discard_samples_deferred) {
    if (f.discard_samples_deferred >= right_start-left_start) {
      f.discard_samples_deferred -= (right_start-left_start);
      left_start = right_start;
      *p_left = left_start;
    } else {
      left_start += f.discard_samples_deferred;
      *p_left = left_start;
      f.discard_samples_deferred = 0;
    }
  } else if (f.previous_length == 0 && f.current_loc_valid) {
    // we're recovering from a seek... that means we're going to discard
    // the samples from this packet even though we know our position from
    // the last page header, so we need to update the position based on
    // the discarded samples here
    // but wait, the code below is going to add this in itself even
    // on a discard, so we don't need to do it here...
  }

  // check if we have ogg information about the sample # for this packet
  if (f.last_seg_which == f.end_seg_with_known_loc) {
    // if we have a valid current loc, and this is final:
    if (f.current_loc_valid && (f.page_flag&PAGEFLAG_last_page)) {
      uint current_end = f.known_loc_for_packet-(n-right_end);
      // then let's infer the size of the (probably) short final frame
      if (current_end < f.current_loc+right_end) {
        if (current_end < f.current_loc+(right_end-left_start)) {
          // negative truncation, that's impossible!
          *len = 0;
        } else {
          *len = current_end-f.current_loc;
        }
        *len += left_start;
        if (*len > right_end) *len = right_end; // this should never happen
        f.current_loc += *len;
        return true;
      }
    }
    // otherwise, just set our sample loc
    // guess that the ogg granule pos refers to the _middle_ of the
    // last frame?
    // set f.current_loc to the position of left_start
    f.current_loc = f.known_loc_for_packet-(n2-left_start);
    f.current_loc_valid = true;
  }
  if (f.current_loc_valid) f.current_loc += (right_start-left_start);

  //debug(stb_vorbis) if (f.alloc.alloc_buffer) assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);

  *len = right_end;  // ignore samples after the window goes to 0
  return true;
}

private int vorbis_decode_packet (VorbisDecoder f, int* len, int* p_left, int* p_right) {
  int mode, left_end, right_end;
  if (!vorbis_decode_initial(f, p_left, &left_end, p_right, &right_end, &mode)) return 0;
  return vorbis_decode_packet_rest(f, len, f.mode_config.ptr+mode, *p_left, left_end, *p_right, right_end, p_left);
}

private int vorbis_finish_frame (VorbisDecoder f, int len, int left, int right) {
  // we use right&left (the start of the right- and left-window sin()-regions)
  // to determine how much to return, rather than inferring from the rules
  // (same result, clearer code); 'left' indicates where our sin() window
  // starts, therefore where the previous window's right edge starts, and
  // therefore where to start mixing from the previous buffer. 'right'
  // indicates where our sin() ending-window starts, therefore that's where
  // we start saving, and where our returned-data ends.

  // mixin from previous window
  if (f.previous_length) {
    int n = f.previous_length;
    float *w = get_window(f, n);
    foreach (immutable i; 0..f.vrchannels) {
      foreach (immutable j; 0..n) {
        (f.channel_buffers.ptr[i])[left+j] =
          (f.channel_buffers.ptr[i])[left+j]*w[    j]+
          (f.previous_window.ptr[i])[     j]*w[n-1-j];
      }
    }
  }

  auto prev = f.previous_length;

  // last half of this data becomes previous window
  f.previous_length = len-right;

  // @OPTIMIZE: could avoid this copy by double-buffering the
  // output (flipping previous_window with channel_buffers), but
  // then previous_window would have to be 2x as large, and
  // channel_buffers couldn't be temp mem (although they're NOT
  // currently temp mem, they could be (unless we want to level
  // performance by spreading out the computation))
  foreach (immutable i; 0..f.vrchannels) {
    for (uint j = 0; right+j < len; ++j) (f.previous_window.ptr[i])[j] = (f.channel_buffers.ptr[i])[right+j];
  }

  if (!prev) {
    // there was no previous packet, so this data isn't valid...
    // this isn't entirely true, only the would-have-overlapped data
    // isn't valid, but this seems to be what the spec requires
    return 0;
  }

  // truncate a short frame
  if (len < right) right = len;

  f.samples_output += right-left;

  return right-left;
}

private bool vorbis_pump_first_frame (VorbisDecoder f) {
  int len, right, left;
  if (vorbis_decode_packet(f, &len, &left, &right)) {
    vorbis_finish_frame(f, len, left, right);
    return true;
  }
  return false;
}

/+ k8: i don't need that, so it's dead
private int is_whole_packet_present (VorbisDecoder f, int end_page) {
  import core.stdc.string : memcmp;

  // make sure that we have the packet available before continuing...
  // this requires a full ogg parse, but we know we can fetch from f.stream

  // instead of coding this out explicitly, we could save the current read state,
  // read the next packet with get8() until end-of-packet, check f.eof, then
  // reset the state? but that would be slower, esp. since we'd have over 256 bytes
  // of state to restore (primarily the page segment table)

  int s = f.next_seg, first = true;
  ubyte *p = f.stream;

  if (s != -1) { // if we're not starting the packet with a 'continue on next page' flag
    for (; s < f.segment_count; ++s) {
      p += f.segments[s];
      if (f.segments[s] < 255) break; // stop at first short segment
    }
    // either this continues, or it ends it...
    if (end_page && s < f.segment_count-1) return error(f, STBVorbisError.invalid_stream);
    if (s == f.segment_count) s = -1; // set 'crosses page' flag
    if (p > f.stream_end) return error(f, STBVorbisError.need_more_data);
    first = false;
  }
  while (s == -1) {
    ubyte* q = void;
    int n = void;
    // check that we have the page header ready
    if (p+26 >= f.stream_end) return error(f, STBVorbisError.need_more_data);
    // validate the page
    if (memcmp(p, ogg_page_header.ptr, 4)) return error(f, STBVorbisError.invalid_stream);
    if (p[4] != 0) return error(f, STBVorbisError.invalid_stream);
    if (first) { // the first segment must NOT have 'continued_packet', later ones MUST
      if (f.previous_length && (p[5]&PAGEFLAG_continued_packet)) return error(f, STBVorbisError.invalid_stream);
      // if no previous length, we're resynching, so we can come in on a continued-packet,
      // which we'll just drop
    } else {
      if (!(p[5]&PAGEFLAG_continued_packet)) return error(f, STBVorbisError.invalid_stream);
    }
    n = p[26]; // segment counts
    q = p+27; // q points to segment table
    p = q+n; // advance past header
    // make sure we've read the segment table
    if (p > f.stream_end) return error(f, STBVorbisError.need_more_data);
    for (s = 0; s < n; ++s) {
      p += q[s];
      if (q[s] < 255) break;
    }
    if (end_page && s < n-1) return error(f, STBVorbisError.invalid_stream);
    if (s == n) s = -1; // set 'crosses page' flag
    if (p > f.stream_end) return error(f, STBVorbisError.need_more_data);
    first = false;
  }
  return true;
}
+/

private int start_decoder (VorbisDecoder f) {
  import core.stdc.string : memcpy, memset;

  ubyte[6] header;
  ubyte x, y;
  int len, max_submaps = 0;
  int longest_floorlist = 0;

  // first page, first packet

  if (!start_page(f)) return false;
  // validate page flag
  if (!(f.page_flag&PAGEFLAG_first_page)) return error(f, STBVorbisError.invalid_first_page);
  if (f.page_flag&PAGEFLAG_last_page) return error(f, STBVorbisError.invalid_first_page);
  if (f.page_flag&PAGEFLAG_continued_packet) return error(f, STBVorbisError.invalid_first_page);
  // check for expected packet length
  if (f.segment_count != 1) return error(f, STBVorbisError.invalid_first_page);
  if (f.segments[0] != 30) return error(f, STBVorbisError.invalid_first_page);
  // read packet
  // check packet header
  if (get8(f) != VorbisPacket.id) return error(f, STBVorbisError.invalid_first_page);
  if (!getn(f, header.ptr, 6)) return error(f, STBVorbisError.unexpected_eof);
  if (!vorbis_validate(header.ptr)) return error(f, STBVorbisError.invalid_first_page);
  // vorbis_version
  if (get32(f) != 0) return error(f, STBVorbisError.invalid_first_page);
  f.vrchannels = get8(f); if (!f.vrchannels) return error(f, STBVorbisError.invalid_first_page);
  if (f.vrchannels > STB_VORBIS_MAX_CHANNELS) return error(f, STBVorbisError.too_many_channels);
  f.sample_rate = get32(f); if (!f.sample_rate) return error(f, STBVorbisError.invalid_first_page);
  get32(f); // bitrate_maximum
  get32(f); // bitrate_nominal
  get32(f); // bitrate_minimum
  x = get8(f);
  {
    int log0 = x&15;
    int log1 = x>>4;
    f.blocksize_0 = 1<<log0;
    f.blocksize_1 = 1<<log1;
    if (log0 < 6 || log0 > 13) return error(f, STBVorbisError.invalid_setup);
    if (log1 < 6 || log1 > 13) return error(f, STBVorbisError.invalid_setup);
    if (log0 > log1) return error(f, STBVorbisError.invalid_setup);
  }

  // framing_flag
  x = get8(f);
  if (!(x&1)) return error(f, STBVorbisError.invalid_first_page);

  // second packet! (comments)
  if (!start_page(f)) return false;

  // read comments
  if (!start_packet(f)) return false;

  if (f.read_comments) {
    /+if (f.push_mode) {
      if (!is_whole_packet_present(f, true)) {
        // convert error in ogg header to write type
        if (f.error == STBVorbisError.invalid_stream) f.error = STBVorbisError.invalid_setup;
        return false;
      }
    }+/
    if (get8_packet(f) != VorbisPacket.comment) return error(f, STBVorbisError.invalid_setup);
    foreach (immutable i; 0..6) header[i] = cast(ubyte)get8_packet(f); //k8
    if (!vorbis_validate(header.ptr)) return error(f, STBVorbisError.invalid_setup);

    // skip vendor id
    uint vidsize = get32_packet(f);
    //{ import core.stdc.stdio; printf("vendor size: %u\n", vidsize); }
    if (vidsize == EOP) return error(f, STBVorbisError.invalid_setup);
    while (vidsize--) get8_packet(f);

    // read comments section
    uint cmtcount = get32_packet(f);
    if (cmtcount == EOP) return error(f, STBVorbisError.invalid_setup);
    if (cmtcount > 0) {
      uint cmtsize = 32768; // this should be enough for everyone
      f.comment_data = setup_malloc!ubyte(f, cmtsize);
      if (f.comment_data is null) return error(f, STBVorbisError.outofmem);
      auto cmtpos = 0;
      auto d = f.comment_data;
      while (cmtcount--) {
        uint linelen = get32_packet(f);
        //{ import core.stdc.stdio; printf("linelen: %u; lines left: %u\n", linelen, cmtcount); }
        if (linelen == EOP || linelen > ushort.max-2) break;
        if (linelen == 0) { continue; }
        if (cmtpos+2+linelen > cmtsize) break;
        cmtpos += linelen+2;
        *d++ = (linelen+2)&0xff;
        *d++ = ((linelen+2)>>8)&0xff;
        while (linelen--) {
          auto b = get8_packet(f);
          if (b == EOP) return error(f, STBVorbisError.outofmem);
          *d++ = cast(ubyte)b;
        }
        //{ import core.stdc.stdio; printf("%u bytes of comments read\n", cmtpos); }
        f.comment_size = cmtpos;
      }
    }
    flush_packet(f);
    f.comment_rewind();
  } else {
    // skip comments
    do {
      len = next_segment(f);
      skip(f, len);
      f.bytes_in_seg = 0;
    } while (len);
  }

  // third packet!
  if (!start_packet(f)) return false;

  /+if (f.push_mode) {
    if (!is_whole_packet_present(f, true)) {
      // convert error in ogg header to write type
      if (f.error == STBVorbisError.invalid_stream) f.error = STBVorbisError.invalid_setup;
      return false;
    }
  }+/

  if (get8_packet(f) != VorbisPacket.setup) return error(f, STBVorbisError.invalid_setup);
  foreach (immutable i; 0..6) header[i] = cast(ubyte)get8_packet(f); //k8
  if (!vorbis_validate(header.ptr)) return error(f, STBVorbisError.invalid_setup);

  // codebooks
  f.codebook_count = get_bits!8(f)+1;
  f.codebooks = setup_malloc!Codebook(f, f.codebook_count);
  static assert((*f.codebooks).sizeof == Codebook.sizeof);
  if (f.codebooks is null) return error(f, STBVorbisError.outofmem);
  memset(f.codebooks, 0, (*f.codebooks).sizeof*f.codebook_count);
  foreach (immutable i; 0..f.codebook_count) {
    uint* values;
    int ordered, sorted_count;
    int total = 0;
    ubyte* lengths;
    Codebook* c = f.codebooks+i;
    x = get_bits!8(f); if (x != 0x42) return error(f, STBVorbisError.invalid_setup);
    x = get_bits!8(f); if (x != 0x43) return error(f, STBVorbisError.invalid_setup);
    x = get_bits!8(f); if (x != 0x56) return error(f, STBVorbisError.invalid_setup);
    x = get_bits!8(f);
    c.dimensions = (get_bits!8(f)<<8)+x;
    x = get_bits!8(f);
    y = get_bits!8(f);
    c.entries = (get_bits!8(f)<<16)+(y<<8)+x;
    ordered = get_bits!1(f);
    c.sparse = (ordered ? 0 : get_bits!1(f));

    if (c.dimensions == 0 && c.entries != 0) return error(f, STBVorbisError.invalid_setup);

    if (c.sparse) {
      lengths = cast(ubyte*)setup_temp_malloc(f, c.entries);
    } else {
      lengths = c.codeword_lengths = setup_malloc!ubyte(f, c.entries);
    }

    if (lengths is null) return error(f, STBVorbisError.outofmem);

    if (ordered) {
      int current_entry = 0;
      int current_length = get_bits_add_no!5(f, 1);
      while (current_entry < c.entries) {
        int limit = c.entries-current_entry;
        int n = get_bits_main(f, ilog(limit));
        if (current_entry+n > cast(int)c.entries) return error(f, STBVorbisError.invalid_setup);
        memset(lengths+current_entry, current_length, n);
        current_entry += n;
        ++current_length;
      }
    } else {
      foreach (immutable j; 0..c.entries) {
        int present = (c.sparse ? get_bits!1(f) : 1);
        if (present) {
          lengths[j] = get_bits_add_no!5(f, 1);
          ++total;
          if (lengths[j] == 32) return error(f, STBVorbisError.invalid_setup);
        } else {
          lengths[j] = NO_CODE;
        }
      }
    }

    if (c.sparse && total >= c.entries>>2) {
      // convert sparse items to non-sparse!
      if (c.entries > cast(int)f.setup_temp_memory_required) f.setup_temp_memory_required = c.entries;
      c.codeword_lengths = setup_malloc!ubyte(f, c.entries);
      if (c.codeword_lengths is null) return error(f, STBVorbisError.outofmem);
      memcpy(c.codeword_lengths, lengths, c.entries);
      setup_temp_free(f, lengths, c.entries); // note this is only safe if there have been no intervening temp mallocs!
      lengths = c.codeword_lengths;
      c.sparse = 0;
    }

    // compute the size of the sorted tables
    if (c.sparse) {
      sorted_count = total;
    } else {
      sorted_count = 0;
      version(STB_VORBIS_NO_HUFFMAN_BINARY_SEARCH) {} else {
        foreach (immutable j; 0..c.entries) if (lengths[j] > STB_VORBIS_FAST_HUFFMAN_LENGTH && lengths[j] != NO_CODE) ++sorted_count;
      }
    }

    c.sorted_entries = sorted_count;
    values = null;

    if (!c.sparse) {
      c.codewords = setup_malloc!uint(f, c.entries);
      if (!c.codewords) return error(f, STBVorbisError.outofmem);
    } else {
      if (c.sorted_entries) {
        c.codeword_lengths = setup_malloc!ubyte(f, c.sorted_entries);
        if (!c.codeword_lengths) return error(f, STBVorbisError.outofmem);
        c.codewords = cast(uint*)setup_temp_malloc(f, cast(int)(*c.codewords).sizeof*c.sorted_entries);
        if (!c.codewords) return error(f, STBVorbisError.outofmem);
        values = cast(uint*)setup_temp_malloc(f, cast(int)(*values).sizeof*c.sorted_entries);
        if (!values) return error(f, STBVorbisError.outofmem);
      }
      uint size = c.entries+cast(int)((*c.codewords).sizeof+(*values).sizeof)*c.sorted_entries;
      if (size > f.setup_temp_memory_required) f.setup_temp_memory_required = size;
    }

    if (!compute_codewords(c, lengths, c.entries, values)) {
      if (c.sparse) setup_temp_free(f, values, 0);
      return error(f, STBVorbisError.invalid_setup);
    }

    if (c.sorted_entries) {
      // allocate an extra slot for sentinels
      c.sorted_codewords = setup_malloc!uint(f, c.sorted_entries+1);
      if (c.sorted_codewords is null) return error(f, STBVorbisError.outofmem);
      // allocate an extra slot at the front so that c.sorted_values[-1] is defined
      // so that we can catch that case without an extra if
      c.sorted_values = setup_malloc!int(f, c.sorted_entries+1);
      if (c.sorted_values is null) return error(f, STBVorbisError.outofmem);
      ++c.sorted_values;
      c.sorted_values[-1] = -1;
      compute_sorted_huffman(c, lengths, values);
    }

    if (c.sparse) {
      setup_temp_free(f, values, cast(int)(*values).sizeof*c.sorted_entries);
      setup_temp_free(f, c.codewords, cast(int)(*c.codewords).sizeof*c.sorted_entries);
      setup_temp_free(f, lengths, c.entries);
      c.codewords = null;
    }

    compute_accelerated_huffman(c);

    c.lookup_type = get_bits!4(f);
    if (c.lookup_type > 2) return error(f, STBVorbisError.invalid_setup);
    if (c.lookup_type > 0) {
      ushort* mults;
      c.minimum_value = float32_unpack(get_bits!32(f));
      c.delta_value = float32_unpack(get_bits!32(f));
      c.value_bits = get_bits_add_no!4(f, 1);
      c.sequence_p = get_bits!1(f);
      if (c.lookup_type == 1) {
        c.lookup_values = lookup1_values(c.entries, c.dimensions);
      } else {
        c.lookup_values = c.entries*c.dimensions;
      }
      if (c.lookup_values == 0) return error(f, STBVorbisError.invalid_setup);
      mults = cast(ushort*)setup_temp_malloc(f, cast(int)(mults[0]).sizeof*c.lookup_values);
      if (mults is null) return error(f, STBVorbisError.outofmem);
      foreach (immutable j; 0..cast(int)c.lookup_values) {
        int q = get_bits_main(f, c.value_bits);
        if (q == EOP) { setup_temp_free(f, mults, cast(int)(mults[0]).sizeof*c.lookup_values); return error(f, STBVorbisError.invalid_setup); }
        mults[j] = cast(ushort)q; //k8
      }

      version(STB_VORBIS_DIVIDES_IN_CODEBOOK) {} else {
        if (c.lookup_type == 1) {
          int sparse = c.sparse; //len
          float last = 0;
          // pre-expand the lookup1-style multiplicands, to avoid a divide in the inner loop
          if (sparse) {
            if (c.sorted_entries == 0) goto skip;
            c.multiplicands = setup_malloc!codetype(f, c.sorted_entries*c.dimensions);
          } else {
            c.multiplicands = setup_malloc!codetype(f, c.entries*c.dimensions);
          }
          if (c.multiplicands is null) { setup_temp_free(f, mults, cast(int)(mults[0]).sizeof*c.lookup_values); return error(f, STBVorbisError.outofmem); }
          foreach (immutable j; 0..(sparse ? c.sorted_entries : c.entries)) {
            uint z = (sparse ? c.sorted_values[j] : j);
            uint div = 1;
            foreach (immutable k; 0..c.dimensions) {
              int off = (z/div)%c.lookup_values;
              float val = mults[off];
              val = val*c.delta_value+c.minimum_value+last;
              c.multiplicands[j*c.dimensions+k] = val;
              if (c.sequence_p) last = val;
              if (k+1 < c.dimensions) {
                 if (div > uint.max/cast(uint)c.lookup_values) {
                    setup_temp_free(f, mults, cast(uint)(mults[0]).sizeof*c.lookup_values);
                    return error(f, STBVorbisError.invalid_setup);
                 }
                 div *= c.lookup_values;
              }
            }
          }
          c.lookup_type = 2;
          goto skip;
        }
        //else
      }
      {
        float last = 0;
        c.multiplicands = setup_malloc!codetype(f, c.lookup_values);
        if (c.multiplicands is null) { setup_temp_free(f, mults, cast(uint)(mults[0]).sizeof*c.lookup_values); return error(f, STBVorbisError.outofmem); }
        foreach (immutable j; 0..cast(int)c.lookup_values) {
          float val = mults[j]*c.delta_value+c.minimum_value+last;
          c.multiplicands[j] = val;
          if (c.sequence_p) last = val;
        }
      }
     //version(STB_VORBIS_DIVIDES_IN_CODEBOOK)
     skip: // this is versioned out in C
      setup_temp_free(f, mults, cast(uint)(mults[0]).sizeof*c.lookup_values);
    }
  }

  // time domain transfers (notused)
  x = get_bits_add_no!6(f, 1);
  foreach (immutable i; 0..x) {
    auto z = get_bits!16(f);
    if (z != 0) return error(f, STBVorbisError.invalid_setup);
  }

  // Floors
  f.floor_count = get_bits_add_no!6(f, 1);
  f.floor_config = setup_malloc!Floor(f, f.floor_count);
  if (f.floor_config is null) return error(f, STBVorbisError.outofmem);
  foreach (immutable i; 0..f.floor_count) {
    f.floor_types[i] = get_bits!16(f);
    if (f.floor_types[i] > 1) return error(f, STBVorbisError.invalid_setup);
    if (f.floor_types[i] == 0) {
      Floor0* g = &f.floor_config[i].floor0;
      g.order = get_bits!8(f);
      g.rate = get_bits!16(f);
      g.bark_map_size = get_bits!16(f);
      g.amplitude_bits = get_bits!6(f);
      g.amplitude_offset = get_bits!8(f);
      g.number_of_books = get_bits_add_no!4(f, 1);
      foreach (immutable j; 0..g.number_of_books) g.book_list[j] = get_bits!8(f);
      return error(f, STBVorbisError.feature_not_supported);
    } else {
      Point[31*8+2] p;
      Floor1 *g = &f.floor_config[i].floor1;
      int max_class = -1;
      g.partitions = get_bits!5(f);
      foreach (immutable j; 0..g.partitions) {
        g.partition_class_list[j] = get_bits!4(f);
        if (g.partition_class_list[j] > max_class) max_class = g.partition_class_list[j];
      }
      foreach (immutable j; 0..max_class+1) {
        g.class_dimensions[j] = get_bits_add_no!3(f, 1);
        g.class_subclasses[j] = get_bits!2(f);
        if (g.class_subclasses[j]) {
          g.class_masterbooks[j] = get_bits!8(f);
          if (g.class_masterbooks[j] >= f.codebook_count) return error(f, STBVorbisError.invalid_setup);
        }
        foreach (immutable k; 0..1<<g.class_subclasses[j]) {
          g.subclass_books[j].ptr[k] = get_bits!8(f)-1;
          if (g.subclass_books[j].ptr[k] >= f.codebook_count) return error(f, STBVorbisError.invalid_setup);
        }
      }
      g.floor1_multiplier = get_bits_add_no!2(f, 1);
      g.rangebits = get_bits!4(f);
      g.Xlist[0] = 0;
      g.Xlist[1] = cast(ushort)(1<<g.rangebits); //k8
      g.values = 2;
      foreach (immutable j; 0..g.partitions) {
        int c = g.partition_class_list[j];
        foreach (immutable k; 0..g.class_dimensions[c]) {
          g.Xlist[g.values] = cast(ushort)get_bits_main(f, g.rangebits); //k8
          ++g.values;
        }
      }
      assert(g.values <= ushort.max);
      // precompute the sorting
      foreach (ushort j; 0..cast(ushort)g.values) {
        p[j].x = g.Xlist[j];
        p[j].y = j;
      }
      qsort(p.ptr, g.values, (p[0]).sizeof, &point_compare);
      foreach (uint j; 0..g.values) g.sorted_order.ptr[j] = cast(ubyte)p.ptr[j].y;
      // precompute the neighbors
      foreach (uint j; 2..g.values) {
        ushort low = void, hi = void;
        neighbors(g.Xlist.ptr, j, &low, &hi);
        assert(low <= ubyte.max);
        assert(hi <= ubyte.max);
        g.neighbors[j].ptr[0] = cast(ubyte)low;
        g.neighbors[j].ptr[1] = cast(ubyte)hi;
      }
      if (g.values > longest_floorlist) longest_floorlist = g.values;
    }
  }

  // Residue
  f.residue_count = get_bits_add_no!6(f, 1);
  f.residue_config = setup_malloc!Residue(f, f.residue_count);
  if (f.residue_config is null) return error(f, STBVorbisError.outofmem);
  memset(f.residue_config, 0, f.residue_count*(f.residue_config[0]).sizeof);
  foreach (immutable i; 0..f.residue_count) {
    ubyte[64] residue_cascade;
    Residue* r = f.residue_config+i;
    f.residue_types[i] = get_bits!16(f);
    if (f.residue_types[i] > 2) return error(f, STBVorbisError.invalid_setup);
    r.begin = get_bits!24(f);
    r.end = get_bits!24(f);
    if (r.end < r.begin) return error(f, STBVorbisError.invalid_setup);
    r.part_size = get_bits_add_no!24(f, 1);
    r.classifications = get_bits_add_no!6(f, 1);
    r.classbook = get_bits!8(f);
    if (r.classbook >= f.codebook_count) return error(f, STBVorbisError.invalid_setup);
    foreach (immutable j; 0..r.classifications) {
      ubyte high_bits = 0;
      ubyte low_bits = get_bits!3(f);
      if (get_bits!1(f)) high_bits = get_bits!5(f);
      assert(high_bits*8+low_bits <= ubyte.max);
      residue_cascade[j] = cast(ubyte)(high_bits*8+low_bits);
    }
    static assert(r.residue_books[0].sizeof == 16);
    r.residue_books = setup_malloc!(short[8])(f, r.classifications);
    if (r.residue_books is null) return error(f, STBVorbisError.outofmem);
    foreach (immutable j; 0..r.classifications) {
      foreach (immutable k; 0..8) {
        if (residue_cascade[j]&(1<<k)) {
          r.residue_books[j].ptr[k] = get_bits!8(f);
          if (r.residue_books[j].ptr[k] >= f.codebook_count) return error(f, STBVorbisError.invalid_setup);
        } else {
          r.residue_books[j].ptr[k] = -1;
        }
      }
    }
    // precompute the classifications[] array to avoid inner-loop mod/divide
    // call it 'classdata' since we already have r.classifications
    r.classdata = setup_malloc!(ubyte*)(f, f.codebooks[r.classbook].entries);
    if (!r.classdata) return error(f, STBVorbisError.outofmem);
    memset(r.classdata, 0, (*r.classdata).sizeof*f.codebooks[r.classbook].entries);
    foreach (immutable j; 0..f.codebooks[r.classbook].entries) {
      int classwords = f.codebooks[r.classbook].dimensions;
      int temp = j;
      r.classdata[j] = setup_malloc!ubyte(f, classwords);
      if (r.classdata[j] is null) return error(f, STBVorbisError.outofmem);
      foreach_reverse (immutable k; 0..classwords) {
        assert(temp%r.classifications >= 0 && temp%r.classifications <= ubyte.max);
        r.classdata[j][k] = cast(ubyte)(temp%r.classifications);
        temp /= r.classifications;
      }
    }
  }

  f.mapping_count = get_bits_add_no!6(f, 1);
  f.mapping = setup_malloc!Mapping(f, f.mapping_count);
  if (f.mapping is null) return error(f, STBVorbisError.outofmem);
  memset(f.mapping, 0, f.mapping_count*(*f.mapping).sizeof);
  foreach (immutable i; 0..f.mapping_count) {
    Mapping* m = f.mapping+i;
    int mapping_type = get_bits!16(f);
    if (mapping_type != 0) return error(f, STBVorbisError.invalid_setup);
    m.chan = setup_malloc!MappingChannel(f, f.vrchannels);
    if (m.chan is null) return error(f, STBVorbisError.outofmem);
    m.submaps = (get_bits!1(f) ? get_bits_add_no!4(f, 1) : 1);
    if (m.submaps > max_submaps) max_submaps = m.submaps;
    if (get_bits!1(f)) {
      m.coupling_steps = get_bits_add_no!8(f, 1);
      foreach (immutable k; 0..m.coupling_steps) {
        m.chan[k].magnitude = cast(ubyte)get_bits_main(f, ilog(f.vrchannels-1)); //k8
        m.chan[k].angle = cast(ubyte)get_bits_main(f, ilog(f.vrchannels-1)); //k8
        if (m.chan[k].magnitude >= f.vrchannels) return error(f, STBVorbisError.invalid_setup);
        if (m.chan[k].angle     >= f.vrchannels) return error(f, STBVorbisError.invalid_setup);
        if (m.chan[k].magnitude == m.chan[k].angle) return error(f, STBVorbisError.invalid_setup);
      }
    } else {
      m.coupling_steps = 0;
    }

    // reserved field
    if (get_bits!2(f)) return error(f, STBVorbisError.invalid_setup);
    if (m.submaps > 1) {
      foreach (immutable j; 0..f.vrchannels) {
        m.chan[j].mux = get_bits!4(f);
        if (m.chan[j].mux >= m.submaps) return error(f, STBVorbisError.invalid_setup);
      }
    } else {
      // @SPECIFICATION: this case is missing from the spec
      foreach (immutable j; 0..f.vrchannels) m.chan[j].mux = 0;
    }
    foreach (immutable j; 0..m.submaps) {
      get_bits!8(f); // discard
      m.submap_floor[j] = get_bits!8(f);
      m.submap_residue[j] = get_bits!8(f);
      if (m.submap_floor[j] >= f.floor_count) return error(f, STBVorbisError.invalid_setup);
      if (m.submap_residue[j] >= f.residue_count) return error(f, STBVorbisError.invalid_setup);
    }
  }

  // Modes
  f.mode_count = get_bits_add_no!6(f, 1);
  foreach (immutable i; 0..f.mode_count) {
    Mode* m = f.mode_config.ptr+i;
    m.blockflag = get_bits!1(f);
    m.windowtype = get_bits!16(f);
    m.transformtype = get_bits!16(f);
    m.mapping = get_bits!8(f);
    if (m.windowtype != 0) return error(f, STBVorbisError.invalid_setup);
    if (m.transformtype != 0) return error(f, STBVorbisError.invalid_setup);
    if (m.mapping >= f.mapping_count) return error(f, STBVorbisError.invalid_setup);
  }

  flush_packet(f);

  f.previous_length = 0;

  foreach (immutable i; 0..f.vrchannels) {
    f.channel_buffers.ptr[i] = setup_malloc!float(f, f.blocksize_1);
    f.previous_window.ptr[i] = setup_malloc!float(f, f.blocksize_1/2);
    f.finalY.ptr[i]          = setup_malloc!short(f, longest_floorlist);
    if (f.channel_buffers.ptr[i] is null || f.previous_window.ptr[i] is null || f.finalY.ptr[i] is null) return error(f, STBVorbisError.outofmem);
    version(STB_VORBIS_NO_DEFER_FLOOR) {
      f.floor_buffers.ptr[i] = setup_malloc!float(f, f.blocksize_1/2);
      if (f.floor_buffers.ptr[i] is null) return error(f, STBVorbisError.outofmem);
    }
  }

  if (!init_blocksize(f, 0, f.blocksize_0)) return false;
  if (!init_blocksize(f, 1, f.blocksize_1)) return false;
  f.blocksize.ptr[0] = f.blocksize_0;
  f.blocksize.ptr[1] = f.blocksize_1;

  version(STB_VORBIS_DIVIDE_TABLE) {
    if (integer_divide_table[1].ptr[1] == 0) {
      foreach (immutable i; 0..DIVTAB_NUMER) foreach (immutable j; 1..DIVTAB_DENOM) integer_divide_table[i].ptr[j] = i/j;
    }
  }

  // compute how much temporary memory is needed

  // 1.
  {
    uint imdct_mem = (f.blocksize_1*cast(uint)(float).sizeof>>1);
    uint classify_mem;
    int max_part_read = 0;
    foreach (immutable i; 0..f.residue_count) {
      Residue* r = f.residue_config+i;
      int n_read = r.end-r.begin;
      int part_read = n_read/r.part_size;
      if (part_read > max_part_read) max_part_read = part_read;
    }
    version(STB_VORBIS_DIVIDES_IN_RESIDUE) {
      classify_mem = f.vrchannels*cast(uint)((void*).sizeof+max_part_read*(int*).sizeof);
    } else {
      classify_mem = f.vrchannels*cast(uint)((void*).sizeof+max_part_read*(ubyte*).sizeof);
    }
    f.temp_memory_required = classify_mem;
    if (imdct_mem > f.temp_memory_required) f.temp_memory_required = imdct_mem;
  }

  f.first_decode = true;

  /+
  if (f.alloc.alloc_buffer) {
    debug(stb_vorbis) assert(f.temp_offset == f.alloc.alloc_buffer_length_in_bytes);
    // check if there's enough temp memory so we don't error later
    if (f.setup_offset+ /*(*f).sizeof+*/ f.temp_memory_required > cast(uint)f.temp_offset) return error(f, STBVorbisError.outofmem);
  }
  +/

  f.first_audio_page_offset = f.fileOffset();

  return true;
}

/+
private int vorbis_search_for_page_pushdata (VorbisDecoder f, ubyte* data, int data_len) {
  import core.stdc.string : memcmp;

  foreach (immutable i; 0..f.page_crc_tests) f.scan.ptr[i].bytes_done = 0;

  // if we have room for more scans, search for them first, because
  // they may cause us to stop early if their header is incomplete
  if (f.page_crc_tests < STB_VORBIS_PUSHDATA_CRC_COUNT) {
    if (data_len < 4) return 0;
    data_len -= 3; // need to look for 4-byte sequence, so don't miss one that straddles a boundary
    foreach (immutable i; 0..data_len) {
      if (data[i] == 0x4f) {
        if (memcmp(data+i, ogg_page_header.ptr, 4) == 0) {
          // make sure we have the whole page header
          if (i+26 >= data_len || i+27+data[i+26] >= data_len) {
            // only read up to this page start, so hopefully we'll
            // have the whole page header start next time
            data_len = i;
            break;
          }
          // ok, we have it all; compute the length of the page
          auto len = 27+data[i+26];
          foreach (immutable j; 0..data[i+26]) len += data[i+27+j];
          // scan everything up to the embedded crc (which we must 0)
          uint crc = 0;
          foreach (immutable j; 0..22) crc = crc32_update(crc, data[i+j]);
          // now process 4 0-bytes
          foreach (immutable j; 22..26) crc = crc32_update(crc, 0);
          // len is the total number of bytes we need to scan
          auto n = f.page_crc_tests++;
          f.scan.ptr[n].bytes_left = len-/*j*/26;
          f.scan.ptr[n].crc_so_far = crc;
          f.scan.ptr[n].goal_crc = data[i+22]+(data[i+23]<<8)+(data[i+24]<<16)+(data[i+25]<<24);
          // if the last frame on a page is continued to the next, then
          // we can't recover the sample_loc immediately
          if (data[i+27+data[i+26]-1] == 255) {
            f.scan.ptr[n].sample_loc = ~0;
          } else {
            f.scan.ptr[n].sample_loc = data[i+6]+(data[i+7]<<8)+(data[i+8]<<16)+(data[i+9]<<24);
          }
          f.scan.ptr[n].bytes_done = i+26/*j*/;
          if (f.page_crc_tests == STB_VORBIS_PUSHDATA_CRC_COUNT) break;
          // keep going if we still have room for more
        }
      }
    }
  }

  for (uint i = 0; i < f.page_crc_tests; ) {
    int nn = f.scan.ptr[i].bytes_done;
    int m = f.scan.ptr[i].bytes_left;
    if (m > data_len-nn) m = data_len-nn;
    // m is the bytes to scan in the current chunk
    uint crc = f.scan.ptr[i].crc_so_far;
    foreach (immutable j; 0..m) crc = crc32_update(crc, data[nn+j]);
    f.scan.ptr[i].bytes_left -= m;
    f.scan.ptr[i].crc_so_far = crc;
    if (f.scan.ptr[i].bytes_left == 0) {
      // does it match?
      if (f.scan.ptr[i].crc_so_far == f.scan.ptr[i].goal_crc) {
        // Houston, we have page
        data_len = nn+m; // consumption amount is wherever that scan ended
        f.page_crc_tests = -1; // drop out of page scan mode
        f.previous_length = 0; // decode-but-don't-output one frame
        f.next_seg = -1;       // start a new page
        f.current_loc = f.scan.ptr[i].sample_loc; // set the current sample location to the amount we'd have decoded had we decoded this page
        f.current_loc_valid = f.current_loc != ~0U;
        return data_len;
      }
      // delete entry
      f.scan.ptr[i] = f.scan.ptr[--f.page_crc_tests];
    } else {
      ++i;
    }
  }

  return data_len;
}
+/

private uint vorbis_find_page (VorbisDecoder f, uint* end, uint* last) {
  for (;;) {
    if (f.eof) return 0;
    auto n = get8(f);
    if (n == 0x4f) { // page header candidate
      uint retry_loc = f.fileOffset;
      // check if we're off the end of a file_section stream
      if (retry_loc-25 > f.stream_len) return 0;
      // check the rest of the header
      int i = void;
      for (i = 1; i < 4; ++i) if (get8(f) != ogg_page_header[i]) break;
      if (f.eof) return 0;
      if (i == 4) {
        ubyte[27] header;
        //for (i=0; i < 4; ++i) header[i] = ogg_page_header[i];
        header[0..4] = cast(immutable(ubyte)[])ogg_page_header[0..4];
        for (i = 4; i < 27; ++i) header[i] = get8(f);
        if (f.eof) return 0;
        if (header[4] != 0) goto invalid;
        uint goal = header[22]+(header[23]<<8)+(header[24]<<16)+(header[25]<<24);
        for (i = 22; i < 26; ++i) header[i] = 0;
        uint crc = 0;
        for (i = 0; i < 27; ++i) crc = crc32_update(crc, header[i]);
        uint len = 0;
        for (i = 0; i < header[26]; ++i) {
          auto s = get8(f);
          crc = crc32_update(crc, s);
          len += s;
        }
        if (len && f.eof) return 0;
        for (i = 0; i < len; ++i) crc = crc32_update(crc, get8(f));
        // finished parsing probable page
        if (crc == goal) {
          // we could now check that it's either got the last
          // page flag set, OR it's followed by the capture
          // pattern, but I guess TECHNICALLY you could have
          // a file with garbage between each ogg page and recover
          // from it automatically? So even though that paranoia
          // might decrease the chance of an invalid decode by
          // another 2^32, not worth it since it would hose those
          // invalid-but-useful files?
          if (end) *end = f.fileOffset;
          if (last) *last = (header[5]&0x04 ? 1 : 0);
          set_file_offset(f, retry_loc-1);
          return 1;
        }
      }
     invalid:
      // not a valid page, so rewind and look for next one
      set_file_offset(f, retry_loc);
    }
  }
  assert(0);
}

enum SAMPLE_unknown = 0xffffffff;

// seeking is implemented with a binary search, which narrows down the range to
// 64K, before using a linear search (because finding the synchronization
// pattern can be expensive, and the chance we'd find the end page again is
// relatively high for small ranges)
//
// two initial interpolation-style probes are used at the start of the search
// to try to bound either side of the binary search sensibly, while still
// working in O(log n) time if they fail.
private int get_seek_page_info (VorbisDecoder f, ProbedPage* z) {
  ubyte[27] header;
  ubyte[255] lacing;

  // record where the page starts
  z.page_start = f.fileOffset;

  // parse the header
  getn(f, header.ptr, 27);
  if (header[0] != 'O' || header[1] != 'g' || header[2] != 'g' || header[3] != 'S') return 0;
  getn(f, lacing.ptr, header[26]);

  // determine the length of the payload
  uint len = 0;
  foreach (immutable i; 0..header[26]) len += lacing[i];

  // this implies where the page ends
  z.page_end = z.page_start+27+header[26]+len;

  // read the last-decoded sample out of the data
  z.last_decoded_sample = header[6]+(header[7]<<8)+(header[8]<<16)+(header[9]<<24);

  // restore file state to where we were
  set_file_offset(f, z.page_start);
  return 1;
}

// rarely used function to seek back to the preceeding page while finding the start of a packet
private int go_to_page_before (VorbisDecoder f, uint limit_offset) {
  uint previous_safe, end;

  // now we want to seek back 64K from the limit
  if (limit_offset >= 65536 && limit_offset-65536 >= f.first_audio_page_offset) {
    previous_safe = limit_offset-65536;
  } else {
    previous_safe = f.first_audio_page_offset;
  }

  set_file_offset(f, previous_safe);

  while (vorbis_find_page(f, &end, null)) {
    if (end >= limit_offset && f.fileOffset < limit_offset) return 1;
    set_file_offset(f, end);
  }

  return 0;
}

// implements the search logic for finding a page and starting decoding. if
// the function succeeds, current_loc_valid will be true and current_loc will
// be less than or equal to the provided sample number (the closer the
// better).
private int seek_to_sample_coarse (VorbisDecoder f, uint sample_number) {
  ProbedPage left, right, mid;
  int i, start_seg_with_known_loc, end_pos, page_start;
  uint delta, stream_length, padding;
  double offset, bytes_per_sample;
  int probe = 0;

  // find the last page and validate the target sample
  stream_length = f.streamLengthInSamples;
  if (stream_length == 0) return error(f, STBVorbisError.seek_without_length);
  if (sample_number > stream_length) return error(f, STBVorbisError.seek_invalid);

  // this is the maximum difference between the window-center (which is the
  // actual granule position value), and the right-start (which the spec
  // indicates should be the granule position (give or take one)).
  padding = ((f.blocksize_1-f.blocksize_0)>>2);
  if (sample_number < padding) sample_number = 0; else sample_number -= padding;

  left = f.p_first;
  while (left.last_decoded_sample == ~0U) {
    // (untested) the first page does not have a 'last_decoded_sample'
    set_file_offset(f, left.page_end);
    if (!get_seek_page_info(f, &left)) goto error;
  }

  right = f.p_last;
  debug(stb_vorbis) assert(right.last_decoded_sample != ~0U);

  // starting from the start is handled differently
  if (sample_number <= left.last_decoded_sample) {
    f.seekStart;
    return 1;
  }

  while (left.page_end != right.page_start) {
    debug(stb_vorbis) assert(left.page_end < right.page_start);
    // search range in bytes
    delta = right.page_start-left.page_end;
    if (delta <= 65536) {
      // there's only 64K left to search - handle it linearly
      set_file_offset(f, left.page_end);
    } else {
      if (probe < 2) {
        if (probe == 0) {
          // first probe (interpolate)
          double data_bytes = right.page_end-left.page_start;
          bytes_per_sample = data_bytes/right.last_decoded_sample;
          offset = left.page_start+bytes_per_sample*(sample_number-left.last_decoded_sample);
        } else {
          // second probe (try to bound the other side)
          double error = (cast(double)sample_number-mid.last_decoded_sample)*bytes_per_sample;
          if (error >= 0 && error <  8000) error =  8000;
          if (error <  0 && error > -8000) error = -8000;
          offset += error*2;
        }

        // ensure the offset is valid
        if (offset < left.page_end) offset = left.page_end;
        if (offset > right.page_start-65536) offset = right.page_start-65536;

        set_file_offset(f, cast(uint)offset);
      } else {
        // binary search for large ranges (offset by 32K to ensure
        // we don't hit the right page)
        set_file_offset(f, left.page_end+(delta/2)-32768);
      }

      if (!vorbis_find_page(f, null, null)) goto error;
    }

    for (;;) {
      if (!get_seek_page_info(f, &mid)) goto error;
      if (mid.last_decoded_sample != ~0U) break;
      // (untested) no frames end on this page
      set_file_offset(f, mid.page_end);
      debug(stb_vorbis) assert(mid.page_start < right.page_start);
    }

    // if we've just found the last page again then we're in a tricky file,
    // and we're close enough.
    if (mid.page_start == right.page_start) break;

    if (sample_number < mid.last_decoded_sample) right = mid; else left = mid;

    ++probe;
  }

  // seek back to start of the last packet
  page_start = left.page_start;
  set_file_offset(f, page_start);
  if (!start_page(f)) return error(f, STBVorbisError.seek_failed);
  end_pos = f.end_seg_with_known_loc;
  debug(stb_vorbis) assert(end_pos >= 0);

  for (;;) {
    for (i = end_pos; i > 0; --i) if (f.segments.ptr[i-1] != 255) break;
    start_seg_with_known_loc = i;
    if (start_seg_with_known_loc > 0 || !(f.page_flag&PAGEFLAG_continued_packet)) break;
    // (untested) the final packet begins on an earlier page
    if (!go_to_page_before(f, page_start)) goto error;
    page_start = f.fileOffset;
    if (!start_page(f)) goto error;
    end_pos = f.segment_count-1;
  }

  // prepare to start decoding
  f.current_loc_valid = false;
  f.last_seg = false;
  f.valid_bits = 0;
  f.packet_bytes = 0;
  f.bytes_in_seg = 0;
  f.previous_length = 0;
  f.next_seg = start_seg_with_known_loc;

  for (i = 0; i < start_seg_with_known_loc; ++i) skip(f, f.segments.ptr[i]);

  // start decoding (optimizable - this frame is generally discarded)
  if (!vorbis_pump_first_frame(f)) return 0;
  if (f.current_loc > sample_number) return error(f, STBVorbisError.seek_failed);
  return 1;

error:
  // try to restore the file to a valid state
  f.seekStart;
  return error(f, STBVorbisError.seek_failed);
}

// the same as vorbis_decode_initial, but without advancing
private int peek_decode_initial (VorbisDecoder f, int* p_left_start, int* p_left_end, int* p_right_start, int* p_right_end, int* mode) {
  if (!vorbis_decode_initial(f, p_left_start, p_left_end, p_right_start, p_right_end, mode)) return 0;

  // either 1 or 2 bytes were read, figure out which so we can rewind
  int bits_read = 1+ilog(f.mode_count-1);
  if (f.mode_config.ptr[*mode].blockflag) bits_read += 2;
  int bytes_read = (bits_read+7)/8;

  f.bytes_in_seg += bytes_read;
  f.packet_bytes -= bytes_read;
  skip(f, -bytes_read);
  if (f.next_seg == -1) f.next_seg = f.segment_count-1; else --f.next_seg;
  f.valid_bits = 0;

  return 1;
}

// ////////////////////////////////////////////////////////////////////////// //
// utility and supporting functions for getting s16 samples
enum PLAYBACK_MONO  = (1<<0);
enum PLAYBACK_LEFT  = (1<<1);
enum PLAYBACK_RIGHT = (1<<2);

enum L = (PLAYBACK_LEFT |PLAYBACK_MONO);
enum C = (PLAYBACK_LEFT |PLAYBACK_RIGHT|PLAYBACK_MONO);
enum R = (PLAYBACK_RIGHT|PLAYBACK_MONO);

immutable byte[6][7] channel_position = [
  [ 0 ],
  [ C ],
  [ L, R ],
  [ L, C, R ],
  [ L, R, L, R ],
  [ L, C, R, L, R ],
  [ L, C, R, L, R, C ],
];


version(STB_VORBIS_NO_FAST_SCALED_FLOAT) {
  enum declfcvar(string name) = "{}";
  template FAST_SCALED_FLOAT_TO_INT(string x, string s) {
    static assert(s == "15");
    enum FAST_SCALED_FLOAT_TO_INT = q{import core.stdc.math : lrintf; int v = lrintf((${x})*32768.0f);}.cmacroFixVars!"x"(x);
  }
} else {
  //k8: actually, this is only marginally faster than using `lrintf()`, but anyway...
  align(1) union float_conv {
  align(1):
    float f;
    int i;
  }
  enum declfcvar(string name) = "float_conv "~name~" = void;";
  static assert(float_conv.i.sizeof == 4 && float_conv.f.sizeof == 4);
  // add (1<<23) to convert to int, then divide by 2^SHIFT, then add 0.5/2^SHIFT to round
  //#define check_endianness()
  enum MAGIC(string SHIFT) = q{(1.5f*(1<<(23-${SHIFT}))+0.5f/(1<<${SHIFT}))}.cmacroFixVars!("SHIFT")(SHIFT);
  enum ADDEND(string SHIFT) = q{(((150-${SHIFT})<<23)+(1<<22))}.cmacroFixVars!("SHIFT")(SHIFT);
  enum FAST_SCALED_FLOAT_TO_INT(string x, string s) = q{temp.f = (${x})+${MAGIC}; int v = temp.i-${ADDEND};}
    .cmacroFixVars!("x", "s", "MAGIC", "ADDEND")(x, s, MAGIC!(s), ADDEND!(s));
}

private void copy_samples (short* dest, float* src, int len) {
  //check_endianness();
  mixin(declfcvar!"temp");
  foreach (immutable _; 0..len) {
    mixin(FAST_SCALED_FLOAT_TO_INT!("*src", "15"));
    if (cast(uint)(v+32768) > 65535) v = (v < 0 ? -32768 : 32767);
    *dest++ = cast(short)v; //k8
    ++src;
  }
}

private void compute_samples (int mask, short* output, int num_c, float** data, int d_offset, int len) {
  import core.stdc.string : memset;
  enum BUFFER_SIZE = 32;
  float[BUFFER_SIZE] buffer;
  int n = BUFFER_SIZE;
  //check_endianness();
  mixin(declfcvar!"temp");
  for (uint o = 0; o < len; o += BUFFER_SIZE) {
    memset(buffer.ptr, 0, (buffer).sizeof);
    if (o+n > len) n = len-o;
    foreach (immutable j; 0..num_c) {
      if (channel_position[num_c].ptr[j]&mask) foreach (immutable i; 0..n) buffer.ptr[i] += data[j][d_offset+o+i];
    }
    foreach (immutable i; 0..n) {
      mixin(FAST_SCALED_FLOAT_TO_INT!("buffer[i]", "15"));
      if (cast(uint)(v+32768) > 65535) v = (v < 0 ? -32768 : 32767);
      output[o+i] = cast(short)v; //k8
    }
  }
}

private void compute_stereo_samples (short* output, int num_c, float** data, int d_offset, int len) {
  import core.stdc.string : memset;

  enum BUFFER_SIZE = 32;
  float[BUFFER_SIZE] buffer;
  int n = BUFFER_SIZE>>1;
  // o is the offset in the source data
  //check_endianness();
  mixin(declfcvar!"temp");
  for (uint o = 0; o < len; o += BUFFER_SIZE>>1) {
    // o2 is the offset in the output data
    int o2 = o<<1;
    memset(buffer.ptr, 0, buffer.sizeof);
    if (o+n > len) n = len-o;
    foreach (immutable j; 0..num_c) {
      int m = channel_position[num_c].ptr[j]&(PLAYBACK_LEFT|PLAYBACK_RIGHT);
      if (m == (PLAYBACK_LEFT|PLAYBACK_RIGHT)) {
        foreach (immutable i; 0..n) {
          buffer.ptr[i*2+0] += data[j][d_offset+o+i];
          buffer.ptr[i*2+1] += data[j][d_offset+o+i];
        }
      } else if (m == PLAYBACK_LEFT) {
        foreach (immutable i; 0..n) buffer.ptr[i*2+0] += data[j][d_offset+o+i];
      } else if (m == PLAYBACK_RIGHT) {
        foreach (immutable i; 0..n) buffer.ptr[i*2+1] += data[j][d_offset+o+i];
      }
    }
    foreach (immutable i; 0..n<<1) {
      mixin(FAST_SCALED_FLOAT_TO_INT!("buffer[i]", "15"));
      if (cast(uint)(v+32768) > 65535) v = (v < 0 ? -32768 : 32767);
      output[o2+i] = cast(short)v; //k8
    }
  }
}

private void convert_samples_short (int buf_c, short** buffer, int b_offset, int data_c, float** data, int d_offset, int samples) {
  import core.stdc.string : memset;

  if (buf_c != data_c && buf_c <= 2 && data_c <= 6) {
    immutable int[2][3] channel_selector = [ [0,0], [PLAYBACK_MONO,0], [PLAYBACK_LEFT, PLAYBACK_RIGHT] ];
    foreach (immutable i; 0..buf_c) compute_samples(channel_selector[buf_c].ptr[i], buffer[i]+b_offset, data_c, data, d_offset, samples);
  } else {
    int limit = (buf_c < data_c ? buf_c : data_c);
    foreach (immutable i; 0..limit) copy_samples(buffer[i]+b_offset, data[i]+d_offset, samples);
    foreach (immutable i; limit..buf_c) memset(buffer[i]+b_offset, 0, short.sizeof*samples);
  }
}

private void convert_channels_short_interleaved (int buf_c, short* buffer, int data_c, float** data, int d_offset, int len) {
  //check_endianness();
  mixin(declfcvar!"temp");
  if (buf_c != data_c && buf_c <= 2 && data_c <= 6) {
    debug(stb_vorbis) assert(buf_c == 2);
    foreach (immutable i; 0..buf_c) compute_stereo_samples(buffer, data_c, data, d_offset, len);
  } else {
    int limit = (buf_c < data_c ? buf_c : data_c);
    foreach (immutable j; 0..len) {
      foreach (immutable i; 0..limit) {
        float f = data[i][d_offset+j];
        mixin(FAST_SCALED_FLOAT_TO_INT!("f", "15"));//data[i][d_offset+j], 15);
        if (cast(uint)(v+32768) > 65535) v = (v < 0 ? -32768 : 32767);
        *buffer++ = cast(short)v; //k8
      }
      foreach (immutable i; limit..buf_c) *buffer++ = 0;
    }
  }
}
} // @nogc


public class VorbisDecoder {
  // return # of bytes read, 0 on eof, -1 on error
  // if called with `buf is null`, do `close()`
  alias readCB = int delegate (void[] buf, uint ofs, VorbisDecoder vb) nothrow @nogc;

  //TODO
  static struct Allocator {
  static nothrow @nogc: // because
    void* alloc (uint sz, VorbisDecoder vb) {
      import core.stdc.stdlib : malloc;
      return malloc(sz);
    }
    void free (void* p, VorbisDecoder vb) {
      import core.stdc.stdlib : free;
      free(p);
    }
    void* allocTemp (uint sz, VorbisDecoder vb) {
      import core.stdc.stdlib : malloc;
      return malloc(sz);
    }
    void freeTemp (void* p, uint sz, VorbisDecoder vb) {
      import core.stdc.stdlib : free;
      free(p);
    }
    uint tempSave (VorbisDecoder vb) { return 0; }
    void tempRestore (uint pos, VorbisDecoder vb) {}
  }

nothrow @nogc:
private:
  bool isOpened;
  readCB stmread;
  uint stlastofs = uint.max;
  uint stst;
  uint stpos;
  uint stend;
  bool stclose;
  FILE* stfl;

private:
  //ubyte* stream;
  //ubyte* stream_start;
  //ubyte* stream_end;
  //uint stream_len;

  /+bool push_mode;+/

  uint first_audio_page_offset;

  ProbedPage p_first, p_last;

  // memory management
  Allocator alloc;
  int setup_offset;
  int temp_offset;

  // run-time results
  bool eof = true;
  STBVorbisError error;

  // header info
  int[2] blocksize;
  int blocksize_0, blocksize_1;
  int codebook_count;
  Codebook* codebooks;
  int floor_count;
  ushort[64] floor_types; // varies
  Floor* floor_config;
  int residue_count;
  ushort[64] residue_types; // varies
  Residue* residue_config;
  int mapping_count;
  Mapping* mapping;
  int mode_count;
  Mode[64] mode_config;  // varies

  uint total_samples;

  // decode buffer
  float*[STB_VORBIS_MAX_CHANNELS] channel_buffers;
  float*[STB_VORBIS_MAX_CHANNELS] outputs;

  float*[STB_VORBIS_MAX_CHANNELS] previous_window;
  int previous_length;

  version(STB_VORBIS_NO_DEFER_FLOOR) {
    float*[STB_VORBIS_MAX_CHANNELS] floor_buffers;
  } else {
    short*[STB_VORBIS_MAX_CHANNELS] finalY;
  }

  uint current_loc; // sample location of next frame to decode
  int current_loc_valid;

  // per-blocksize precomputed data

  // twiddle factors
  float*[2] A, B, C;
  float*[2] window;
  ushort*[2] bit_reverse;

  // current page/packet/segment streaming info
  uint serial; // stream serial number for verification
  int last_page;
  int segment_count;
  ubyte[255] segments;
  ubyte page_flag;
  ubyte bytes_in_seg;
  ubyte first_decode;
  int next_seg;
  int last_seg;  // flag that we're on the last segment
  int last_seg_which; // what was the segment number of the last seg?
  uint acc;
  int valid_bits;
  int packet_bytes;
  int end_seg_with_known_loc;
  uint known_loc_for_packet;
  int discard_samples_deferred;
  uint samples_output;

  // push mode scanning
  /+
  int page_crc_tests; // only in push_mode: number of tests active; -1 if not searching
  CRCscan[STB_VORBIS_PUSHDATA_CRC_COUNT] scan;
  +/

  // sample-access
  int channel_buffer_start;
  int channel_buffer_end;

private: // k8: 'cause i'm evil
  // user-accessible info
  uint sample_rate;
  int vrchannels;

  uint setup_memory_required;
  uint temp_memory_required;
  uint setup_temp_memory_required;

  bool read_comments;
  ubyte* comment_data;
  uint comment_size;

  // functions to get comment data
  uint comment_data_pos;

private:
  int rawRead (void[] buf) {
    static if (__VERSION__ > 2067) pragma(inline, true);
    if (isOpened && buf.length > 0 && stpos < stend) {
      if (stend-stpos < buf.length) buf = buf[0..stend-stpos];
      auto rd = stmread(buf, stpos, this);
      if (rd > 0) stpos += rd;
      return rd;
    }
    return 0;
  }
  void rawSkip (int n) { static if (__VERSION__ > 2067) pragma(inline, true);
  	if (isOpened) {
		stpos += n;
		if(stpos < stst)
			stpos = stst;
		else if(stpos > stend)
			stpos = stend;
	}
  }
  void rawSeek (int n) { static if (__VERSION__ > 2067) pragma(inline, true); if (isOpened) { stpos = stst+(n < 0 ? 0 : n); if (stpos > stend) stpos = stend; } }
  void rawClose () { static if (__VERSION__ > 2067) pragma(inline, true); if (isOpened) { isOpened = false; stmread(null, 0, this); } }

final:
private:
  void doInit () {
    import core.stdc.string : memset;
    /*
    if (z) {
      alloc = *z;
      alloc.alloc_buffer_length_in_bytes = (alloc.alloc_buffer_length_in_bytes+3)&~3;
      temp_offset = alloc.alloc_buffer_length_in_bytes;
    }
    */
    eof = false;
    error = STBVorbisError.no_error;
    /+stream = null;+/
    codebooks = null;
    /+page_crc_tests = -1;+/
  }

  static int stflRead (void[] buf, uint ofs, VorbisDecoder vb) {
    if (buf !is null) {
      if (vb.stlastofs != ofs) {
      	// { import core.stdc.stdio; printf("stflRead: ofs=%u; len=%u\n", ofs, cast(uint)buf.length); }
        import core.stdc.stdio : fseek, SEEK_SET;
        vb.stlastofs = ofs;
        fseek(vb.stfl, ofs, SEEK_SET);
      }
      import core.stdc.stdio : fread;
      auto rd = cast(int)fread(buf.ptr, 1, buf.length, vb.stfl);
      if(rd > 0)
      	vb.stlastofs += rd;
      return rd;
    } else {
      if (vb.stclose) {
        import core.stdc.stdio : fclose;
        if (vb.stfl !is null) fclose(vb.stfl);
      }
      vb.stfl = null;
      return 0;
    }
  }

public:
  this () {}
  ~this () { close(); }

  this (int asize, readCB rcb) {
  	assert(rcb !is null);
	stend = (asize > 0 ? asize : 0);
	stmread = rcb;
	isOpened = true;
	eof = false;
	read_comments = true;
	if (start_decoder(this)) {
		vorbis_pump_first_frame(this);
		return;
	}
  }
  this (FILE* fl, bool doclose=true) { open(fl, doclose); }
  this (const(char)[] filename) { open(filename); }

  @property bool closed () { return !isOpened; }

  void open (FILE *fl, bool doclose=true) {
    import core.stdc.stdio : ftell, fseek, SEEK_SET, SEEK_END;
    close();
    if (fl is null) { error = STBVorbisError.invalid_stream; return; }
    stclose = doclose;
    stst = stpos = cast(uint)ftell(fl);
    fseek(fl, 0, SEEK_END);
    stend = cast(uint)ftell(fl);
    stlastofs = stlastofs.max;
    stclose = false;
    stfl = fl;
    import std.functional : toDelegate;
    stmread = toDelegate(&stflRead);
    isOpened = true;
    eof = false;
    read_comments = true;
    if (start_decoder(this)) {
      vorbis_pump_first_frame(this);
      return;
    }
    auto err = error;
    close();
    error = err;
  }

  void open (const(char)[] filename) {
    import core.stdc.stdio : fopen;
    import std.internal.cstring; // sorry
    close();
    FILE* fl = fopen(filename.tempCString, "rb");
    if (fl is null) { error = STBVorbisError.file_open_failure; return; }
    open(fl, true);
  }

  /+
  void openPushdata(void* data, int data_len, // the memory available for decoding
                    int* data_used)           // only defined on success
  {
    close();
    eof = false;
    stream = cast(ubyte*)data;
    stream_end = stream+data_len;
    push_mode = true;
    if (!start_decoder(this)) {
      auto err = error;
      if (eof) err = STBVorbisError.need_more_data; else close();
      error = err;
      return;
    }
    *data_used = stream-(cast(ubyte*)data);
    error = STBVorbisError.no_error;
  }
  +/

  void close () {
    import core.stdc.string : memset;

    setup_free(this, this.comment_data);
    if (this.residue_config) {
      foreach (immutable i; 0..this.residue_count) {
        Residue* r = this.residue_config+i;
        if (r.classdata) {
          foreach (immutable j; 0..this.codebooks[r.classbook].entries) setup_free(this, r.classdata[j]);
          setup_free(this, r.classdata);
        }
        setup_free(this, r.residue_books);
      }
    }

    if (this.codebooks) {
      foreach (immutable i; 0..this.codebook_count) {
        Codebook* c = this.codebooks+i;
        setup_free(this, c.codeword_lengths);
        setup_free(this, c.multiplicands);
        setup_free(this, c.codewords);
        setup_free(this, c.sorted_codewords);
        // c.sorted_values[-1] is the first entry in the array
        setup_free(this, c.sorted_values ? c.sorted_values-1 : null);
      }
      setup_free(this, this.codebooks);
    }
    setup_free(this, this.floor_config);
    setup_free(this, this.residue_config);
    if (this.mapping) {
      foreach (immutable i; 0..this.mapping_count) setup_free(this, this.mapping[i].chan);
      setup_free(this, this.mapping);
    }
    foreach (immutable i; 0..(this.vrchannels > STB_VORBIS_MAX_CHANNELS ? STB_VORBIS_MAX_CHANNELS : this.vrchannels)) {
      setup_free(this, this.channel_buffers.ptr[i]);
      setup_free(this, this.previous_window.ptr[i]);
      version(STB_VORBIS_NO_DEFER_FLOOR) setup_free(this, this.floor_buffers.ptr[i]);
      setup_free(this, this.finalY.ptr[i]);
    }
    foreach (immutable i; 0..2) {
      setup_free(this, this.A.ptr[i]);
      setup_free(this, this.B.ptr[i]);
      setup_free(this, this.C.ptr[i]);
      setup_free(this, this.window.ptr[i]);
      setup_free(this, this.bit_reverse.ptr[i]);
    }

    rawClose();
    isOpened = false;
    stmread = null;
    stlastofs = uint.max;
    stst = 0;
    stpos = 0;
    stend = 0;
    stclose = false;
    stfl = null;

    sample_rate = 0;
    vrchannels = 0;

    setup_memory_required = 0;
    temp_memory_required = 0;
    setup_temp_memory_required = 0;

    read_comments = 0;
    comment_data = null;
    comment_size = 0;

    comment_data_pos = 0;

    /+
    stream = null;
    stream_start = null;
    stream_end = null;
    +/

    //stream_len = 0;

    /+push_mode = false;+/

    first_audio_page_offset = 0;

    p_first = p_first.init;
    p_last = p_last.init;

    setup_offset = 0;
    temp_offset = 0;

    eof = true;
    error = STBVorbisError.no_error;

    blocksize[] = 0;
    blocksize_0 = 0;
    blocksize_1 = 0;
    codebook_count = 0;
    codebooks = null;
    floor_count = 0;
    floor_types[] = 0;
    floor_config = null;
    residue_count = 0;
    residue_types[] = 0;
    residue_config = null;
    mapping_count = 0;
    mapping = null;
    mode_count = 0;
    mode_config[] = Mode.init;

    total_samples = 0;

    channel_buffers[] = null;
    outputs[] = null;

    previous_window[] = null;
    previous_length = 0;

    version(STB_VORBIS_NO_DEFER_FLOOR) {
      floor_buffers[] = null;
    } else {
      finalY[] = null;
    }

    current_loc = 0;
    current_loc_valid = 0;

    A[] = null;
    B[] = null;
    C[] = null;
    window[] = null;
    bit_reverse = null;

    serial = 0;
    last_page = 0;
    segment_count = 0;
    segments[] = 0;
    page_flag = 0;
    bytes_in_seg = 0;
    first_decode = 0;
    next_seg = 0;
    last_seg = 0;
    last_seg_which = 0;
    acc = 0;
    valid_bits = 0;
    packet_bytes = 0;
    end_seg_with_known_loc = 0;
    known_loc_for_packet = 0;
    discard_samples_deferred = 0;
    samples_output = 0;

    /+
    page_crc_tests = -1;
    scan[] = CRCscan.init;
    +/

    channel_buffer_start = 0;
    channel_buffer_end = 0;
  }

  @property const pure {
    int getSampleOffset () { return (current_loc_valid ? current_loc : -1); }

    @property ubyte chans () { return (isOpened ? cast(ubyte)this.vrchannels : 0); }
    @property uint sampleRate () { return (isOpened ? this.sample_rate : 0); }
    @property uint maxFrameSize () { return (isOpened ? this.blocksize_1>>1 : 0); }

    @property uint getSetupMemoryRequired () { return (isOpened ? this.setup_memory_required : 0); }
    @property uint getSetupTempMemoryRequired () { return (isOpened ? this.setup_temp_memory_required : 0); }
    @property uint getTempMemoryRequired () { return (isOpened ? this.temp_memory_required : 0); }
  }

  // will clear last error
  @property int lastError () {
    int e = error;
    error = STBVorbisError.no_error;
    return e;
  }

  // PUSHDATA API
  /+
  void flushPushdata () {
    if (push_mode) {
      previous_length = 0;
      page_crc_tests = 0;
      discard_samples_deferred = 0;
      current_loc_valid = false;
      first_decode = false;
      samples_output = 0;
      channel_buffer_start = 0;
      channel_buffer_end = 0;
    }
  }

  // return value: number of bytes we used
  int decodeFramePushdata(
           void* data, int data_len, // the memory available for decoding
           int* channels,            // place to write number of float* buffers
           float*** output,          // place to write float** array of float* buffers
           int* samples              // place to write number of output samples
       )
  {
    if (!this.push_mode) return .error(this, STBVorbisError.invalid_api_mixing);

    if (this.page_crc_tests >= 0) {
      *samples = 0;
      return vorbis_search_for_page_pushdata(this, cast(ubyte*)data, data_len);
    }

    this.stream = cast(ubyte*)data;
    this.stream_end = this.stream+data_len;
    this.error = STBVorbisError.no_error;

    // check that we have the entire packet in memory
    if (!is_whole_packet_present(this, false)) {
      *samples = 0;
      return 0;
    }

    int len, left, right;

    if (!vorbis_decode_packet(this, &len, &left, &right)) {
      // save the actual error we encountered
      STBVorbisError error = this.error;
      if (error == STBVorbisError.bad_packet_type) {
        // flush and resynch
        this.error = STBVorbisError.no_error;
        while (get8_packet(this) != EOP) if (this.eof) break;
        *samples = 0;
        return this.stream-data;
      }
      if (error == STBVorbisError.continued_packet_flag_invalid) {
        if (this.previous_length == 0) {
          // we may be resynching, in which case it's ok to hit one
          // of these; just discard the packet
          this.error = STBVorbisError.no_error;
          while (get8_packet(this) != EOP) if (this.eof) break;
          *samples = 0;
          return this.stream-data;
        }
      }
      // if we get an error while parsing, what to do?
      // well, it DEFINITELY won't work to continue from where we are!
      flushPushdata();
      // restore the error that actually made us bail
      this.error = error;
      *samples = 0;
      return 1;
    }

    // success!
    len = vorbis_finish_frame(this, len, left, right);
    foreach (immutable i; 0..this.vrchannels) this.outputs.ptr[i] = this.channel_buffers.ptr[i]+left;

    if (channels) *channels = this.vrchannels;
    *samples = len;
    *output = this.outputs.ptr;
    return this.stream-data;
  }
  +/

  public uint fileOffset () {
    if (/+push_mode ||+/ !isOpened) return 0;
    /+if (stream !is null) return cast(uint)(stream-stream_start);+/
    return (stpos > stst ? stpos-stst : 0);
  }

  public uint stream_len () { return stend-stst; }

  // DATA-PULLING API
  public int seekFrame (uint sample_number) {
    uint max_frame_samples;

    /+if (this.push_mode) return -.error(this, STBVorbisError.invalid_api_mixing);+/

    // fast page-level search
    if (!seek_to_sample_coarse(this, sample_number)) return 0;

    assert(this.current_loc_valid);
    assert(this.current_loc <= sample_number);

    import std.stdio;

    // linear search for the relevant packet
    max_frame_samples = (this.blocksize_1*3-this.blocksize_0)>>2;
    while (this.current_loc < sample_number) {
      int left_start, left_end, right_start, right_end, mode, frame_samples;
      if (!peek_decode_initial(this, &left_start, &left_end, &right_start, &right_end, &mode)) return .error(this, STBVorbisError.seek_failed);
      // calculate the number of samples returned by the next frame
      frame_samples = right_start-left_start;
      if (this.current_loc+frame_samples > sample_number) {
        return 1; // the next frame will contain the sample
      } else if (this.current_loc+frame_samples+max_frame_samples > sample_number) {
        // there's a chance the frame after this could contain the sample
        vorbis_pump_first_frame(this);
      } else {
        // this frame is too early to be relevant
        this.current_loc += frame_samples;
        this.previous_length = 0;
        maybe_start_packet(this);
        flush_packet(this);
      }
    }
    // the next frame will start with the sample
    assert(this.current_loc == sample_number);

    return 1;
  }

  public int seek (uint sample_number) {
    if (!seekFrame(sample_number)) return 0;
    if (sample_number != this.current_loc) {
      int n;
      uint frame_start = this.current_loc;
      getFrameFloat(&n, null);
      assert(sample_number > frame_start);
      assert(this.channel_buffer_start+cast(int)(sample_number-frame_start) <= this.channel_buffer_end);
      this.channel_buffer_start += (sample_number-frame_start);
    }
    return 1;
  }

  public bool seekStart () {
    /+if (push_mode) { .error(this, STBVorbisError.invalid_api_mixing); return; }+/
    set_file_offset(this, first_audio_page_offset);
    previous_length = 0;
    first_decode = true;
    next_seg = -1;
    return vorbis_pump_first_frame(this);
  }

  public uint streamLengthInSamples () {
    uint restore_offset, previous_safe;
    uint end, last_page_loc;

    /+if (this.push_mode) return .error(this, STBVorbisError.invalid_api_mixing);+/
    if (!this.total_samples) {
      uint last;
      uint lo, hi;
      char[6] header;

      // first, store the current decode position so we can restore it
      restore_offset = fileOffset;

      // now we want to seek back 64K from the end (the last page must
      // be at most a little less than 64K, but let's allow a little slop)
      if (this.stream_len >= 65536 && this.stream_len-65536 >= this.first_audio_page_offset) {
        previous_safe = this.stream_len-65536;
      } else {
        previous_safe = this.first_audio_page_offset;
      }

      set_file_offset(this, previous_safe);
      // previous_safe is now our candidate 'earliest known place that seeking
      // to will lead to the final page'

      if (!vorbis_find_page(this, &end, &last)) {
        // if we can't find a page, we're hosed!
        this.error = STBVorbisError.cant_find_last_page;
        this.total_samples = 0xffffffff;
        goto done;
      }

      // check if there are more pages
      last_page_loc = fileOffset;

      // stop when the last_page flag is set, not when we reach eof;
      // this allows us to stop short of a 'file_section' end without
      // explicitly checking the length of the section
      while (!last) {
        set_file_offset(this, end);
        if (!vorbis_find_page(this, &end, &last)) {
          // the last page we found didn't have the 'last page' flag set. whoops!
          break;
        }
        previous_safe = last_page_loc+1;
        last_page_loc = fileOffset;
      }

      set_file_offset(this, last_page_loc);

      // parse the header
      getn(this, cast(ubyte*)header, 6);
      // extract the absolute granule position
      lo = get32(this);
      hi = get32(this);
      if (lo == 0xffffffff && hi == 0xffffffff) {
        this.error = STBVorbisError.cant_find_last_page;
        this.total_samples = SAMPLE_unknown;
        goto done;
      }
      if (hi) lo = 0xfffffffe; // saturate
      this.total_samples = lo;

      this.p_last.page_start = last_page_loc;
      this.p_last.page_end = end;
      this.p_last.last_decoded_sample = lo;

     done:
      set_file_offset(this, restore_offset);
    }
    return (this.total_samples == SAMPLE_unknown ? 0 : this.total_samples);
  }

  public float streamLengthInSeconds () {
    return (isOpened ? streamLengthInSamples()/cast(float)sample_rate : 0.0f);
  }

  public int getFrameFloat (int* channels, float*** output) {
    int len, right, left;
    /+if (push_mode) return .error(this, STBVorbisError.invalid_api_mixing);+/

    if (!vorbis_decode_packet(this, &len, &left, &right)) {
      channel_buffer_start = channel_buffer_end = 0;
      return 0;
    }

    len = vorbis_finish_frame(this, len, left, right);
    foreach (immutable i; 0..this.vrchannels) this.outputs.ptr[i] = this.channel_buffers.ptr[i]+left;

    channel_buffer_start = left;
    channel_buffer_end = left+len;

    if (channels) *channels = this.vrchannels;
    if (output) *output = this.outputs.ptr;
    return len;
  }

  /+
  public VorbisDecoder stb_vorbis_open_memory (const(void)* data, int len, int* error=null, stb_vorbis_alloc* alloc=null) {
    VorbisDecoder this;
    stb_vorbis_ctx p = void;
    if (data is null) return null;
    vorbis_init(&p, alloc);
    p.stream = cast(ubyte*)data;
    p.stream_end = cast(ubyte*)data+len;
    p.stream_start = cast(ubyte*)p.stream;
    p.stream_len = len;
    p.push_mode = false;
    if (start_decoder(&p)) {
      this = vorbis_alloc(&p);
      if (this) {
        *this = p;
        vorbis_pump_first_frame(this);
        return this;
      }
    }
    if (error) *error = p.error;
    vorbis_deinit(&p);
    return null;
  }
  +/

  // s16 samples API
  int getFrameShort (int num_c, short** buffer, int num_samples) {
    float** output;
    int len = getFrameFloat(null, &output);
    if (len > num_samples) len = num_samples;
    if (len) convert_samples_short(num_c, buffer, 0, vrchannels, output, 0, len);
    return len;
  }

  int getFrameShortInterleaved (int num_c, short* buffer, int num_shorts) {
    float** output;
    int len;
    if (num_c == 1) return getFrameShort(num_c, &buffer, num_shorts);
    len = getFrameFloat(null, &output);
    if (len) {
      if (len*num_c > num_shorts) len = num_shorts/num_c;
      convert_channels_short_interleaved(num_c, buffer, vrchannels, output, 0, len);
    }
    return len;
  }

  int getSamplesShortInterleaved (int channels, short* buffer, int num_shorts) {
    float** outputs;
    int len = num_shorts/channels;
    int n = 0;
    int z = this.vrchannels;
    if (z > channels) z = channels;
    while (n < len) {
      int k = channel_buffer_end-channel_buffer_start;
      if (n+k >= len) k = len-n;
      if (k) convert_channels_short_interleaved(channels, buffer, vrchannels, channel_buffers.ptr, channel_buffer_start, k);
      buffer += k*channels;
      n += k;
      channel_buffer_start += k;
      if (n == len) break;
      if (!getFrameFloat(null, &outputs)) break;
    }
    return n;
  }

  int getSamplesShort (int channels, short** buffer, int len) {
    float** outputs;
    int n = 0;
    int z = this.vrchannels;
    if (z > channels) z = channels;
    while (n < len) {
      int k = channel_buffer_end-channel_buffer_start;
      if (n+k >= len) k = len-n;
      if (k) convert_samples_short(channels, buffer, n, vrchannels, channel_buffers.ptr, channel_buffer_start, k);
      n += k;
      channel_buffer_start += k;
      if (n == len) break;
      if (!getFrameFloat(null, &outputs)) break;
    }
    return n;
  }

  /+
  public int stb_vorbis_decode_filename (string filename, int* channels, int* sample_rate, short** output) {
    import core.stdc.stdlib : malloc, realloc;

    int data_len, offset, total, limit, error;
    short* data;
    VorbisDecoder v = stb_vorbis_open_filename(filename, &error, null);
    if (v is null) return -1;
    limit = v.vrchannels*4096;
    *channels = v.vrchannels;
    if (sample_rate) *sample_rate = v.sample_rate;
    offset = data_len = 0;
    total = limit;
    data = cast(short*)malloc(total*(*data).sizeof);
    if (data is null) {
      stb_vorbis_close(v);
      return -2;
    }
    for (;;) {
      int n = stb_vorbis_get_frame_short_interleaved(v, v.vrchannels, data+offset, total-offset);
      if (n == 0) break;
      data_len += n;
      offset += n*v.vrchannels;
      if (offset+limit > total) {
        short *data2;
        total *= 2;
        data2 = cast(short*)realloc(data, total*(*data).sizeof);
        if (data2 is null) {
          import core.stdc.stdlib : free;
          free(data);
          stb_vorbis_close(v);
          return -2;
        }
        data = data2;
      }
    }
    *output = data;
    stb_vorbis_close(v);
    return data_len;
  }

  public int stb_vorbis_decode_memory (const(void)* mem, int len, int* channels, int* sample_rate, short** output) {
    import core.stdc.stdlib : malloc, realloc;

    int data_len, offset, total, limit, error;
    short* data;
    VorbisDecoder v = stb_vorbis_open_memory(mem, len, &error, null);
    if (v is null) return -1;
    limit = v.vrchannels*4096;
    *channels = v.vrchannels;
    if (sample_rate) *sample_rate = v.sample_rate;
    offset = data_len = 0;
    total = limit;
    data = cast(short*)malloc(total*(*data).sizeof);
    if (data is null) {
      stb_vorbis_close(v);
      return -2;
    }
    for (;;) {
      int n = stb_vorbis_get_frame_short_interleaved(v, v.vrchannels, data+offset, total-offset);
      if (n == 0) break;
      data_len += n;
      offset += n*v.vrchannels;
      if (offset+limit > total) {
        short *data2;
        total *= 2;
        data2 = cast(short*)realloc(data, total*(*data).sizeof);
        if (data2 is null) {
          import core.stdc.stdlib : free;
          free(data);
          stb_vorbis_close(v);
          return -2;
        }
        data = data2;
      }
    }
    *output = data;
    stb_vorbis_close(v);
    return data_len;
  }

  public int stb_vorbis_get_samples_float_interleaved (VorbisDecoder this, int channels, float* buffer, int num_floats) {
    float** outputs;
    int len = num_floats/channels;
    int n = 0;
    int z = this.vrchannels;
    if (z > channels) z = channels;
    while (n < len) {
      int k = this.channel_buffer_end-this.channel_buffer_start;
      if (n+k >= len) k = len-n;
      foreach (immutable j; 0..k) {
        foreach (immutable i; 0..z) *buffer++ = (this.channel_buffers.ptr[i])[this.channel_buffer_start+j];
        foreach (immutable i; z..channels) *buffer++ = 0;
      }
      n += k;
      this.channel_buffer_start += k;
      if (n == len) break;
      if (!stb_vorbis_get_frame_float(this, null, &outputs)) break;
    }
    return n;
  }
  +/

  public int getSamplesFloat (int achans, float** buffer, int num_samples) {
    import core.stdc.string : memcpy, memset;
    float** outputs;
    int n = 0;
    int z = vrchannels;
    if (z > achans) z = achans;
    while (n < num_samples) {
      int k = channel_buffer_end-channel_buffer_start;
      if (n+k >= num_samples) k = num_samples-n;
      if (k) {
        foreach (immutable i; 0..z) memcpy(buffer[i]+n, channel_buffers.ptr[i]+channel_buffer_start, float.sizeof*k);
        foreach (immutable i; z..achans) memset(buffer[i]+n, 0, float.sizeof*k);
      }
      n += k;
      channel_buffer_start += k;
      if (n == num_samples) break;
      if (!getFrameFloat(null, &outputs)) break;
    }
    return n;
  }

private: // k8: 'cause i'm evil
  private enum cmt_len_size = 2;
  nothrow /*@trusted*/ @nogc {
    public @property bool comment_empty () const pure { return (comment_get_line_len == 0); }

    // 0: error
    // includes length itself
    private uint comment_get_line_len () const pure {
      if (comment_data_pos >= comment_size) return 0;
      if (comment_size-comment_data_pos < cmt_len_size) return 0;
      uint len = comment_data[comment_data_pos];
      len += cast(uint)comment_data[comment_data_pos+1]<<8;
      return (len >= cmt_len_size && comment_data_pos+len <= comment_size ? len : 0);
    }

    public bool comment_rewind () {
      comment_data_pos = 0;
      for (;;) {
        auto len = comment_get_line_len();
        if (!len) { comment_data_pos = comment_size; return false; }
        if (len != cmt_len_size) return true;
        comment_data_pos += len;
      }
    }

    // true: has something to read after skip
    public bool comment_skip () {
      comment_data_pos += comment_get_line_len();
      for (;;) {
        auto len = comment_get_line_len();
        if (!len) { comment_data_pos = comment_size; return false; }
        if (len != cmt_len_size) break;
        comment_data_pos += len;
      }
      return true;
    }

    public const(char)[] comment_line () {
      auto len = comment_get_line_len();
      if (len < cmt_len_size) return null;
      if (len == cmt_len_size) return "";
      return (cast(char*)comment_data+comment_data_pos+cmt_len_size)[0..len-cmt_len_size];
    }

    public const(char)[] comment_name () {
      auto line = comment_line();
      if (line.length == 0) return line;
      uint epos = 0;
      while (epos < line.length && line.ptr[epos] != '=') ++epos;
      return (epos < line.length ? line[0..epos] : "");
    }

    public const(char)[] comment_value () {
      auto line = comment_line();
      if (line.length == 0) return line;
      uint epos = 0;
      while (epos < line.length && line.ptr[epos] != '=') ++epos;
      return (epos < line.length ? line[epos+1..$] : line);
    }
  }
}


// ////////////////////////////////////////////////////////////////////////// //
private:
// cool helper to translate C defines
template cmacroFixVars(T...) {
  /**
   * 64-bit implementation of fasthash
   *
   * Params:
   *   buf =  data buffer
   *   seed = the seed
   *
   * Returns:
   *   32-bit or 64-bit hash
   */
  size_t hashOf (const(void)* buf, size_t len, size_t seed=0) pure nothrow @trusted @nogc {
    enum Get8Bytes = q{
      cast(ulong)data[0]|
      (cast(ulong)data[1]<<8)|
      (cast(ulong)data[2]<<16)|
      (cast(ulong)data[3]<<24)|
      (cast(ulong)data[4]<<32)|
      (cast(ulong)data[5]<<40)|
      (cast(ulong)data[6]<<48)|
      (cast(ulong)data[7]<<56)
    };
    enum m = 0x880355f21e6d1965UL;
    auto data = cast(const(ubyte)*)buf;
    ulong h = seed;
    ulong t;
    foreach (immutable _; 0..len/8) {
      version(HasUnalignedOps) {
        if (__ctfe) {
          t = mixin(Get8Bytes);
        } else {
          t = *cast(ulong*)data;
        }
      } else {
        t = mixin(Get8Bytes);
      }
      data += 8;
      t ^= t>>23;
      t *= 0x2127599bf4325c37UL;
      t ^= t>>47;
      h ^= t;
      h *= m;
    }

    h ^= len*m;
    t = 0;
    switch (len&7) {
      case 7: t ^= cast(ulong)data[6]<<48; goto case 6;
      case 6: t ^= cast(ulong)data[5]<<40; goto case 5;
      case 5: t ^= cast(ulong)data[4]<<32; goto case 4;
      case 4: t ^= cast(ulong)data[3]<<24; goto case 3;
      case 3: t ^= cast(ulong)data[2]<<16; goto case 2;
      case 2: t ^= cast(ulong)data[1]<<8; goto case 1;
      case 1: t ^= cast(ulong)data[0]; goto default;
      default:
        t ^= t>>23;
        t *= 0x2127599bf4325c37UL;
        t ^= t>>47;
        h ^= t;
        h *= m;
        break;
    }

    h ^= h>>23;
    h *= 0x2127599bf4325c37UL;
    h ^= h>>47;
    static if (size_t.sizeof == 4) {
      // 32-bit hash
      // the following trick converts the 64-bit hashcode to Fermat
      // residue, which shall retain information from both the higher
      // and lower parts of hashcode.
      return cast(size_t)(h-(h>>32));
    } else {
      return h;
    }
  }

  string cmacroFixVars (string s, string[] names...) {
    assert(T.length == names.length, "cmacroFixVars: names and arguments count mismatch");
    enum tmpPfxName = "__temp_prefix__";
    string res;
    string tmppfx;
    uint pos = 0;
    // skip empty lines (for pretty printing)
    // trim trailing spaces
    while (s.length > 0 && s[$-1] <= ' ') s = s[0..$-1];
    uint linestpos = 0; // start of the current line
    while (pos < s.length) {
      if (s[pos] > ' ') break;
      if (s[pos] == '\n') linestpos = pos+1;
      ++pos;
    }
    pos = linestpos;
    while (pos+2 < s.length) {
      int epos = pos;
      while (epos+2 < s.length && (s[epos] != '$' || s[epos+1] != '{')) ++epos;
      if (epos > pos) {
        if (s.length-epos < 3) break;
        res ~= s[pos..epos];
        pos = epos;
      }
      assert(s[pos] == '$' && s[pos+1] == '{');
      pos += 2;
      bool found = false;
      if (s.length-pos >= tmpPfxName.length+1 && s[pos+tmpPfxName.length] == '}' && s[pos..pos+tmpPfxName.length] == tmpPfxName) {
        if (tmppfx.length == 0) {
          // generate temporary prefix
          auto hash = hashOf(s.ptr, s.length);
          immutable char[16] hexChars = "0123456789abcdef";
          tmppfx = "_temp_macro_var_";
          foreach_reverse (immutable idx; 0..size_t.sizeof*2) {
            tmppfx ~= hexChars[hash&0x0f];
            hash >>= 4;
          }
          tmppfx ~= "_";
        }
        pos += tmpPfxName.length+1;
        res ~= tmppfx;
        found = true;
      } else {
        foreach (immutable nidx, string oname; T) {
          static assert(oname.length > 0);
          if (s.length-pos >= oname.length+1 && s[pos+oname.length] == '}' && s[pos..pos+oname.length] == oname) {
            found = true;
            pos += oname.length+1;
            res ~= names[nidx];
            break;
          }
        }
      }
      assert(found, "unknown variable in macro");
    }
    if (pos < s.length) res ~= s[pos..$];
    return res;
  }
}

// ////////////////////////////////////////////////////////////////////////// //
/* Version history
    1.09    - 2016/04/04 - back out 'avoid discarding last frame' fix from previous version
    1.08    - 2016/04/02 - fixed multiple warnings; fix setup memory leaks;
                           avoid discarding last frame of audio data
    1.07    - 2015/01/16 - fixed some warnings, fix mingw, const-correct API
                           some more crash fixes when out of memory or with corrupt files
    1.06    - 2015/08/31 - full, correct support for seeking API (Dougall Johnson)
                           some crash fixes when out of memory or with corrupt files
    1.05    - 2015/04/19 - don't define __forceinline if it's redundant
    1.04    - 2014/08/27 - fix missing const-correct case in API
    1.03    - 2014/08/07 - Warning fixes
    1.02    - 2014/07/09 - Declare qsort compare function _cdecl on windows
    1.01    - 2014/06/18 - fix stb_vorbis_get_samples_float
    1.0     - 2014/05/26 - fix memory leaks; fix warnings; fix bugs in multichannel
                           (API change) report sample rate for decode-full-file funcs
    0.99996 - bracket #include <malloc.h> for macintosh compilation by Laurent Gomila
    0.99995 - use union instead of pointer-cast for fast-float-to-int to avoid alias-optimization problem
    0.99994 - change fast-float-to-int to work in single-precision FPU mode, remove endian-dependence
    0.99993 - remove assert that fired on legal files with empty tables
    0.99992 - rewind-to-start
    0.99991 - bugfix to stb_vorbis_get_samples_short by Bernhard Wodo
    0.9999 - (should have been 0.99990) fix no-CRT support, compiling as C++
    0.9998 - add a full-decode function with a memory source
    0.9997 - fix a bug in the read-from-FILE case in 0.9996 addition
    0.9996 - query length of vorbis stream in samples/seconds
    0.9995 - bugfix to another optimization that only happened in certain files
    0.9994 - bugfix to one of the optimizations that caused significant (but inaudible?) errors
    0.9993 - performance improvements; runs in 99% to 104% of time of reference implementation
    0.9992 - performance improvement of IMDCT; now performs close to reference implementation
    0.9991 - performance improvement of IMDCT
    0.999 - (should have been 0.9990) performance improvement of IMDCT
    0.998 - no-CRT support from Casey Muratori
    0.997 - bugfixes for bugs found by Terje Mathisen
    0.996 - bugfix: fast-huffman decode initialized incorrectly for sparse codebooks; fixing gives 10% speedup - found by Terje Mathisen
    0.995 - bugfix: fix to 'effective' overrun detection - found by Terje Mathisen
    0.994 - bugfix: garbage decode on final VQ symbol of a non-multiple - found by Terje Mathisen
    0.993 - bugfix: pushdata API required 1 extra byte for empty page (failed to consume final page if empty) - found by Terje Mathisen
    0.992 - fixes for MinGW warning
    0.991 - turn fast-float-conversion on by default
    0.990 - fix push-mode seek recovery if you seek into the headers
    0.98b - fix to bad release of 0.98
    0.98 - fix push-mode seek recovery; robustify float-to-int and support non-fast mode
    0.97 - builds under c++ (typecasting, don't use 'class' keyword)
    0.96 - somehow MY 0.95 was right, but the web one was wrong, so here's my 0.95 rereleased as 0.96, fixes a typo in the clamping code
    0.95 - clamping code for 16-bit functions
    0.94 - not publically released
    0.93 - fixed all-zero-floor case (was decoding garbage)
    0.92 - fixed a memory leak
    0.91 - conditional compiles to omit parts of the API and the infrastructure to support them: STB_VORBIS_NO_PULLDATA_API, STB_VORBIS_NO_PUSHDATA_API, STB_VORBIS_NO_STDIO, STB_VORBIS_NO_INTEGER_CONVERSION
    0.90 - first public release
*/

/*
------------------------------------------------------------------------------
This software is available under 2 licenses -- choose whichever you prefer.
------------------------------------------------------------------------------
ALTERNATIVE A - MIT License
Copyright (c) 2017 Sean Barrett
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
------------------------------------------------------------------------------
ALTERNATIVE B - Public Domain (www.unlicense.org)
This is free and unencumbered software released into the public domain.
Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.
In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
------------------------------------------------------------------------------
*/
