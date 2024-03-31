/++
	This is a port of the C code from https://www.nayuki.io/page/qr-code-generator-library

	History:
		Originally written in C by Project Nayuki.

		Ported to D by me on July 26, 2021
+/
/*
 * QR Code generator library (C)
 *
 * Copyright (c) Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/qr-code-generator-library
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising from,
 *   out of or in connection with the Software or the use or other dealings in the
 *   Software.
 */
module arsd.qrcode;

///
unittest {
	import arsd.qrcode;

	void main() {
		import arsd.simpledisplay;

		QrCode code = QrCode("http://arsdnet.net/");

		enum drawsize = 4;
		// you have to have some border around it
		auto window = new SimpleWindow(code.size * drawsize + 80, code.size * drawsize + 80);

		{
			auto painter = window.draw;
			painter.clear(Color.white);

			foreach(y; 0 .. code.size)
			foreach(x; 0 .. code.size) {
				if(code[x, y]) {
					painter.outlineColor = Color.black;
					painter.fillColor = Color.black;
				} else {
					painter.outlineColor = Color.white;
					painter.fillColor = Color.white;
				}
				painter.drawRectangle(Point(x * drawsize + 40, y * drawsize + 40), Size(drawsize, drawsize));
			}
		}

		window.eventLoop(0);
	}

	main; // exclude from docs
}

@system:

import core.stdc.stddef;
import core.stdc.stdint;
import core.stdc.string;
import core.stdc.config;
import core.stdc.stdlib;
import core.stdc.math;

/*
 * This library creates QR Code symbols, which is a type of two-dimension barcode.
 * Invented by Denso Wave and described in the ISO/IEC 18004 standard.
 * A QR Code structure is an immutable square grid of black and white cells.
 * The library provides functions to create a QR Code from text or binary data.
 * The library covers the QR Code Model 2 specification, supporting all versions (sizes)
 * from 1 to 40, all 4 error correction levels, and 4 character encoding modes.
 *
 * Ways to create a QR Code object:
 * - High level: Take the payload data and call qrcodegen_encodeText() or qrcodegen_encodeBinary().
 * - Low level: Custom-make the list of segments and call
 *   qrcodegen_encodeSegments() or qrcodegen_encodeSegmentsAdvanced().
 * (Note that all ways require supplying the desired error correction level and various byte buffers.)
 */


/*---- Enum and struct types----*/

/*
 * The error correction level in a QR Code symbol.
 */

alias qrcodegen_Ecc = int;

enum /*qrcodegen_Ecc*/ {
	// Must be declared in ascending order of error protection
	// so that an internal qrcodegen function works properly
	qrcodegen_Ecc_LOW = 0 ,  // The QR Code can tolerate about  7% erroneous codewords
	qrcodegen_Ecc_MEDIUM  ,  // The QR Code can tolerate about 15% erroneous codewords
	qrcodegen_Ecc_QUARTILE,  // The QR Code can tolerate about 25% erroneous codewords
	qrcodegen_Ecc_HIGH    ,  // The QR Code can tolerate about 30% erroneous codewords
}


/*
 * The mask pattern used in a QR Code symbol.
 */
alias qrcodegen_Mask = int;
enum /* qrcodegen_Mask */ {
	// A special value to tell the QR Code encoder to
	// automatically select an appropriate mask pattern
	qrcodegen_Mask_AUTO = -1,
	// The eight actual mask patterns
	qrcodegen_Mask_0 = 0,
	qrcodegen_Mask_1,
	qrcodegen_Mask_2,
	qrcodegen_Mask_3,
	qrcodegen_Mask_4,
	qrcodegen_Mask_5,
	qrcodegen_Mask_6,
	qrcodegen_Mask_7,
}


/*
 * Describes how a segment's data bits are interpreted.
 */
alias qrcodegen_Mode = int;
enum /*qrcodegen_Mode*/ {
	qrcodegen_Mode_NUMERIC      = 0x1,
	qrcodegen_Mode_ALPHANUMERIC = 0x2,
	qrcodegen_Mode_BYTE         = 0x4,
	qrcodegen_Mode_KANJI        = 0x8,
	qrcodegen_Mode_ECI          = 0x7,
}


/*
 * A segment of character/binary/control data in a QR Code symbol.
 * The mid-level way to create a segment is to take the payload data
 * and call a factory function such as qrcodegen_makeNumeric().
 * The low-level way to create a segment is to custom-make the bit buffer
 * and initialize a qrcodegen_Segment struct with appropriate values.
 * Even in the most favorable conditions, a QR Code can only hold 7089 characters of data.
 * Any segment longer than this is meaningless for the purpose of generating QR Codes.
 * Moreover, the maximum allowed bit length is 32767 because
 * the largest QR Code (version 40) has 31329 modules.
 */
struct qrcodegen_Segment {
	// The mode indicator of this segment.
	qrcodegen_Mode mode;

	// The length of this segment's unencoded data. Measured in characters for
	// numeric/alphanumeric/kanji mode, bytes for byte mode, and 0 for ECI mode.
	// Always zero or positive. Not the same as the data's bit length.
	int numChars;

	// The data bits of this segment, packed in bitwise big endian.
	// Can be null if the bit length is zero.
	uint8_t *data;

	// The number of valid data bits used in the buffer. Requires
	// 0 <= bitLength <= 32767, and bitLength <= (capacity of data array) * 8.
	// The character count (numChars) must agree with the mode and the bit buffer length.
	int bitLength;
};



/*---- Macro constants and functions ----*/

enum qrcodegen_VERSION_MIN =   1;  // The minimum version number supported in the QR Code Model 2 standard
enum qrcodegen_VERSION_MAX =  40;  // The maximum version number supported in the QR Code Model 2 standard

// Calculates the number of bytes needed to store any QR Code up to and including the given version number,
// as a compile-time constant. For example, 'uint8_t buffer[qrcodegen_BUFFER_LEN_FOR_VERSION(25)];'
// can store any single QR Code from version 1 to 25 (inclusive). The result fits in an int (or int16).
// Requires qrcodegen_VERSION_MIN <= n <= qrcodegen_VERSION_MAX.
auto qrcodegen_BUFFER_LEN_FOR_VERSION(int n) { return ((((n) * 4 + 17) * ((n) * 4 + 17) + 7) / 8 + 1); }

// The worst-case number of bytes needed to store one QR Code, up to and including
// version 40. This value equals 3918, which is just under 4 kilobytes.
// Use this more convenient value to avoid calculating tighter memory bounds for buffers.
auto qrcodegen_BUFFER_LEN_MAX() { return qrcodegen_BUFFER_LEN_FOR_VERSION(qrcodegen_VERSION_MAX); }



/*---- Functions (high level) to generate QR Codes ----*/

/*
 * Encodes the given text string to a QR Code, returning true if encoding succeeded.
 * If the data is too long to fit in any version in the given range
 * at the given ECC level, then false is returned.
 * - The input text must be encoded in UTF-8 and contain no NULs.
 * - The variables ecl and mask must correspond to enum constant values.
 * - Requires 1 <= minVersion <= maxVersion <= 40.
 * - The arrays tempBuffer and qrcode must each have a length
 *   of at least qrcodegen_BUFFER_LEN_FOR_VERSION(maxVersion).
 * - After the function returns, tempBuffer contains no useful data.
 * - If successful, the resulting QR Code may use numeric,
 *   alphanumeric, or byte mode to encode the text.
 * - In the most optimistic case, a QR Code at version 40 with low ECC
 *   can hold any UTF-8 string up to 2953 bytes, or any alphanumeric string
 *   up to 4296 characters, or any digit string up to 7089 characters.
 *   These numbers represent the hard upper limit of the QR Code standard.
 * - Please consult the QR Code specification for information on
 *   data capacities per version, ECC level, and text encoding mode.
 */
bool qrcodegen_encodeText(const char *text, uint8_t* tempBuffer, uint8_t* qrcode,
	qrcodegen_Ecc ecl, int minVersion, int maxVersion, qrcodegen_Mask mask, bool boostEcl);


/*
 * Encodes the given binary data to a QR Code, returning true if encoding succeeded.
 * If the data is too long to fit in any version in the given range
 * at the given ECC level, then false is returned.
 * - The input array range dataAndTemp[0 : dataLen] should normally be
 *   valid UTF-8 text, but is not required by the QR Code standard.
 * - The variables ecl and mask must correspond to enum constant values.
 * - Requires 1 <= minVersion <= maxVersion <= 40.
 * - The arrays dataAndTemp and qrcode must each have a length
 *   of at least qrcodegen_BUFFER_LEN_FOR_VERSION(maxVersion).
 * - After the function returns, the contents of dataAndTemp may have changed,
 *   and does not represent useful data anymore.
 * - If successful, the resulting QR Code will use byte mode to encode the data.
 * - In the most optimistic case, a QR Code at version 40 with low ECC can hold any byte
 *   sequence up to length 2953. This is the hard upper limit of the QR Code standard.
 * - Please consult the QR Code specification for information on
 *   data capacities per version, ECC level, and text encoding mode.
 */
bool qrcodegen_encodeBinary(uint8_t* dataAndTemp, size_t dataLen, uint8_t* qrcode,
	qrcodegen_Ecc ecl, int minVersion, int maxVersion, qrcodegen_Mask mask, bool boostEcl);



/*---- Functions to extract raw data from QR Codes ----*/


/*
 * QR Code generator library (C)
 *
 * Copyright (c) Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/qr-code-generator-library
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising from,
 *   out of or in connection with the Software or the use or other dealings in the
 *   Software.
 */

/*---- Forward declarations for private functions ----*/

// Regarding all public and private functions defined in this source file:
// - They require all pointer/array arguments to be not null unless the array length is zero.
// - They only read input scalar/array arguments, write to output pointer/array
//   arguments, and return scalar values; they are "pure" functions.
// - They don't read mutable global variables or write to any global variables.
// - They don't perform I/O, read the clock, print to console, etc.
// - They allocate a small and constant amount of stack memory.
// - They don't allocate or free any memory on the heap.
// - They don't recurse or mutually recurse. All the code
//   could be inlined into the top-level public functions.
// - They run in at most quadratic time with respect to input arguments.
//   Most functions run in linear time, and some in constant time.
//   There are no unbounded loops or non-obvious termination conditions.
// - They are completely thread-safe if the caller does not give the
//   same writable buffer to concurrent calls to these functions.

/*---- Private tables of constants ----*/

// The set of all legal characters in alphanumeric mode, where each character
// value maps to the index in the string. For checking text and encoding segments.
static const char *ALPHANUMERIC_CHARSET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

// For generating error correction codes.
private const int8_t[41][4] ECC_CODEWORDS_PER_BLOCK = [
	// Version: (note that index 0 is for padding, and is set to an illegal value)
	//0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40    Error correction level
	[-1,  7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // Low
	[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],  // Medium
	[-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // Quartile
	[-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // High
];

enum qrcodegen_REED_SOLOMON_DEGREE_MAX = 30;  // Based on the table above

// For generating error correction codes.
private const int8_t[41][4] NUM_ERROR_CORRECTION_BLOCKS = [
	// Version: (note that index 0 is for padding, and is set to an illegal value)
	//0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40    Error correction level
	[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4,  4,  4,  4,  4,  6,  6,  6,  6,  7,  8,  8,  9,  9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],  // Low
	[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5,  5,  8,  9,  9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],  // Medium
	[-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8,  8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],  // Quartile
	[-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],  // High
];

// For automatic mask pattern selection.
static const int PENALTY_N1 =  3;
static const int PENALTY_N2 =  3;
static const int PENALTY_N3 = 40;
static const int PENALTY_N4 = 10;



/*---- High-level QR Code encoding functions ----*/

// Public function - see documentation comment in header file.
bool qrcodegen_encodeText(const char *text, uint8_t* tempBuffer, uint8_t* qrcode,
		qrcodegen_Ecc ecl, int minVersion, int maxVersion, qrcodegen_Mask mask, bool boostEcl) {

	size_t textLen = strlen(text);
	if (textLen == 0)
		return qrcodegen_encodeSegmentsAdvanced(null, 0, ecl, minVersion, maxVersion, mask, boostEcl, tempBuffer, qrcode);
	size_t bufLen = qrcodegen_BUFFER_LEN_FOR_VERSION(maxVersion);

	qrcodegen_Segment seg;
	if (qrcodegen_isNumeric(text)) {
		if (qrcodegen_calcSegmentBufferSize(qrcodegen_Mode_NUMERIC, textLen) > bufLen)
			goto fail;
		seg = qrcodegen_makeNumeric(text, tempBuffer);
	} else if (qrcodegen_isAlphanumeric(text)) {
		if (qrcodegen_calcSegmentBufferSize(qrcodegen_Mode_ALPHANUMERIC, textLen) > bufLen)
			goto fail;
		seg = qrcodegen_makeAlphanumeric(text, tempBuffer);
	} else {
		if (textLen > bufLen)
			goto fail;
		for (size_t i = 0; i < textLen; i++)
			tempBuffer[i] = cast(uint8_t)text[i];
		seg.mode = qrcodegen_Mode_BYTE;
		seg.bitLength = calcSegmentBitLength(seg.mode, textLen);
		if (seg.bitLength == -1)
			goto fail;
		seg.numChars = cast(int)textLen;
		seg.data = tempBuffer;
	}
	return qrcodegen_encodeSegmentsAdvanced(&seg, 1, ecl, minVersion, maxVersion, mask, boostEcl, tempBuffer, qrcode);

fail:
	qrcode[0] = 0;  // Set size to invalid value for safety
	return false;
}


// Public function - see documentation comment in header file.
bool qrcodegen_encodeBinary(uint8_t* dataAndTemp, size_t dataLen, uint8_t* qrcode,
		qrcodegen_Ecc ecl, int minVersion, int maxVersion, qrcodegen_Mask mask, bool boostEcl) {

	qrcodegen_Segment seg;
	seg.mode = qrcodegen_Mode_BYTE;
	seg.bitLength = calcSegmentBitLength(seg.mode, dataLen);
	if (seg.bitLength == -1) {
		qrcode[0] = 0;  // Set size to invalid value for safety
		return false;
	}
	seg.numChars = cast(int)dataLen;
	seg.data = dataAndTemp;
	return qrcodegen_encodeSegmentsAdvanced(&seg, 1, ecl, minVersion, maxVersion, mask, boostEcl, dataAndTemp, qrcode);
}


// Appends the given number of low-order bits of the given value to the given byte-based
// bit buffer, increasing the bit length. Requires 0 <= numBits <= 16 and val < 2^numBits.
private void appendBitsToBuffer(uint val, int numBits, uint8_t* buffer, int *bitLen) {
	assert(0 <= numBits && numBits <= 16 && cast(c_ulong)val >> numBits == 0);
	for (int i = numBits - 1; i >= 0; i--, (*bitLen)++)
		buffer[*bitLen >> 3] |= ((val >> i) & 1) << (7 - (*bitLen & 7));
}



/*---- Low-level QR Code encoding functions ----*/

// Public function - see documentation comment in header file.

/*
 * Renders a QR Code representing the given segments at the given error correction level.
 * The smallest possible QR Code version is automatically chosen for the output. Returns true if
 * QR Code creation succeeded, or false if the data is too long to fit in any version. The ECC level
 * of the result may be higher than the ecl argument if it can be done without increasing the version.
 * This function allows the user to create a custom sequence of segments that switches
 * between modes (such as alphanumeric and byte) to encode text in less space.
 * This is a low-level API; the high-level API is qrcodegen_encodeText() and qrcodegen_encodeBinary().
 * To save memory, the segments' data buffers can alias/overlap tempBuffer, and will
 * result in them being clobbered, but the QR Code output will still be correct.
 * But the qrcode array must not overlap tempBuffer or any segment's data buffer.
 */

bool qrcodegen_encodeSegments(const qrcodegen_Segment* segs, size_t len,
		qrcodegen_Ecc ecl, uint8_t* tempBuffer, uint8_t* qrcode) {
	return qrcodegen_encodeSegmentsAdvanced(segs, len, ecl,
		qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true, tempBuffer, qrcode);
}


// Public function - see documentation comment in header file.


/*
 * Renders a QR Code representing the given segments with the given encoding parameters.
 * Returns true if QR Code creation succeeded, or false if the data is too long to fit in the range of versions.
 * The smallest possible QR Code version within the given range is automatically
 * chosen for the output. Iff boostEcl is true, then the ECC level of the result
 * may be higher than the ecl argument if it can be done without increasing the
 * version. The mask is either between qrcodegen_Mask_0 to 7 to force that mask, or
 * qrcodegen_Mask_AUTO to automatically choose an appropriate mask (which may be slow).
 * This function allows the user to create a custom sequence of segments that switches
 * between modes (such as alphanumeric and byte) to encode text in less space.
 * This is a low-level API; the high-level API is qrcodegen_encodeText() and qrcodegen_encodeBinary().
 * To save memory, the segments' data buffers can alias/overlap tempBuffer, and will
 * result in them being clobbered, but the QR Code output will still be correct.
 * But the qrcode array must not overlap tempBuffer or any segment's data buffer.
 */

bool qrcodegen_encodeSegmentsAdvanced(const qrcodegen_Segment* segs, size_t len, qrcodegen_Ecc ecl,
		int minVersion, int maxVersion, qrcodegen_Mask mask, bool boostEcl, uint8_t* tempBuffer, uint8_t* qrcode) {
	assert(segs != null || len == 0);
	assert(qrcodegen_VERSION_MIN <= minVersion && minVersion <= maxVersion && maxVersion <= qrcodegen_VERSION_MAX);
	assert(0 <= cast(int)ecl && cast(int)ecl <= 3 && -1 <= cast(int)mask && cast(int)mask <= 7);

	// Find the minimal version_ number to use
	int version_, dataUsedBits;
	for (version_ = minVersion; ; version_++) {
		int dataCapacityBits = getNumDataCodewords(version_, ecl) * 8;  // Number of data bits available
		dataUsedBits = getTotalBits(segs, len, version_);
		if (dataUsedBits != -1 && dataUsedBits <= dataCapacityBits)
			break;  // This version_ number is found to be suitable
		if (version_ >= maxVersion) {  // All version_s in the range could not fit the given data
			qrcode[0] = 0;  // Set size to invalid value for safety
			return false;
		}
	}
	assert(dataUsedBits != -1);

	// Increase the error correction level while the data still fits in the current version_ number
	for (int i = cast(int)qrcodegen_Ecc_MEDIUM; i <= cast(int)qrcodegen_Ecc_HIGH; i++) {  // From low to high
		if (boostEcl && dataUsedBits <= getNumDataCodewords(version_, cast(qrcodegen_Ecc)i) * 8)
			ecl = cast(qrcodegen_Ecc)i;
	}

	// Concatenate all segments to create the data bit string
	memset(qrcode, 0, cast(size_t)qrcodegen_BUFFER_LEN_FOR_VERSION(version_) * (qrcode[0]).sizeof);
	int bitLen = 0;
	for (size_t i = 0; i < len; i++) {
		const qrcodegen_Segment *seg = &segs[i];
		appendBitsToBuffer(cast(uint)seg.mode, 4, qrcode, &bitLen);
		appendBitsToBuffer(cast(uint)seg.numChars, numCharCountBits(seg.mode, version_), qrcode, &bitLen);
		for (int j = 0; j < seg.bitLength; j++) {
			int bit = (seg.data[j >> 3] >> (7 - (j & 7))) & 1;
			appendBitsToBuffer(cast(uint)bit, 1, qrcode, &bitLen);
		}
	}
	assert(bitLen == dataUsedBits);

	// Add terminator and pad up to a byte if applicable
	int dataCapacityBits = getNumDataCodewords(version_, ecl) * 8;
	assert(bitLen <= dataCapacityBits);
	int terminatorBits = dataCapacityBits - bitLen;
	if (terminatorBits > 4)
		terminatorBits = 4;
	appendBitsToBuffer(0, terminatorBits, qrcode, &bitLen);
	appendBitsToBuffer(0, (8 - bitLen % 8) % 8, qrcode, &bitLen);
	assert(bitLen % 8 == 0);

	// Pad with alternating bytes until data capacity is reached
	for (uint8_t padByte = 0xEC; bitLen < dataCapacityBits; padByte ^= 0xEC ^ 0x11)
		appendBitsToBuffer(padByte, 8, qrcode, &bitLen);

	// Draw function and data codeword modules
	addEccAndInterleave(qrcode, version_, ecl, tempBuffer);
	initializeFunctionModules(version_, qrcode);
	drawCodewords(tempBuffer, getNumRawDataModules(version_) / 8, qrcode);
	drawWhiteFunctionModules(qrcode, version_);
	initializeFunctionModules(version_, tempBuffer);

	// Handle masking
	if (mask == qrcodegen_Mask_AUTO) {  // Automatically choose best mask
		long minPenalty = long.max;
		for (int i = 0; i < 8; i++) {
			qrcodegen_Mask msk = cast(qrcodegen_Mask)i;
			applyMask(tempBuffer, qrcode, msk);
			drawFormatBits(ecl, msk, qrcode);
			long penalty = getPenaltyScore(qrcode);
			if (penalty < minPenalty) {
				mask = msk;
				minPenalty = penalty;
			}
			applyMask(tempBuffer, qrcode, msk);  // Undoes the mask due to XOR
		}
	}
	assert(0 <= cast(int)mask && cast(int)mask <= 7);
	applyMask(tempBuffer, qrcode, mask);
	drawFormatBits(ecl, mask, qrcode);
	return true;
}



/*---- Error correction code generation functions ----*/

// Appends error correction bytes to each block of the given data array, then interleaves
// bytes from the blocks and stores them in the result array. data[0 : dataLen] contains
// the input data. data[dataLen : rawCodewords] is used as a temporary work area and will
// be clobbered by this function. The final answer is stored in result[0 : rawCodewords].
private void addEccAndInterleave(uint8_t* data, int version_, qrcodegen_Ecc ecl, uint8_t* result) {
	// Calculate parameter numbers
	assert(0 <= cast(int)ecl && cast(int)ecl < 4 && qrcodegen_VERSION_MIN <= version_ && version_ <= qrcodegen_VERSION_MAX);
	int numBlocks = NUM_ERROR_CORRECTION_BLOCKS[cast(int)ecl][version_];
	int blockEccLen = ECC_CODEWORDS_PER_BLOCK  [cast(int)ecl][version_];
	int rawCodewords = getNumRawDataModules(version_) / 8;
	int dataLen = getNumDataCodewords(version_, ecl);
	int numShortBlocks = numBlocks - rawCodewords % numBlocks;
	int shortBlockDataLen = rawCodewords / numBlocks - blockEccLen;

	// Split data into blocks, calculate ECC, and interleave
	// (not concatenate) the bytes into a single sequence
	uint8_t[qrcodegen_REED_SOLOMON_DEGREE_MAX] rsdiv;
	reedSolomonComputeDivisor(blockEccLen, rsdiv.ptr);
	const(uint8_t)* dat = data;
	for (int i = 0; i < numBlocks; i++) {
		int datLen = shortBlockDataLen + (i < numShortBlocks ? 0 : 1);
		uint8_t *ecc = &data[dataLen];  // Temporary storage
		reedSolomonComputeRemainder(dat, datLen, rsdiv.ptr, blockEccLen, ecc);
		for (int j = 0, k = i; j < datLen; j++, k += numBlocks) {  // Copy data
			if (j == shortBlockDataLen)
				k -= numShortBlocks;
			result[k] = dat[j];
		}
		for (int j = 0, k = dataLen + i; j < blockEccLen; j++, k += numBlocks)  // Copy ECC
			result[k] = ecc[j];
		dat += datLen;
	}
}


// Returns the number of 8-bit codewords that can be used for storing data (not ECC),
// for the given version_ number and error correction level. The result is in the range [9, 2956].
private int getNumDataCodewords(int version_, qrcodegen_Ecc ecl) {
	int v = version_, e = cast(int)ecl;
	assert(0 <= e && e < 4);
	return getNumRawDataModules(v) / 8
		- ECC_CODEWORDS_PER_BLOCK    [e][v]
		* NUM_ERROR_CORRECTION_BLOCKS[e][v];
}


// Returns the number of data bits that can be stored in a QR Code of the given version_ number, after
// all function modules are excluded. This includes remainder bits, so it might not be a multiple of 8.
// The result is in the range [208, 29648]. This could be implemented as a 40-entry lookup table.
private int getNumRawDataModules(int ver) {
	assert(qrcodegen_VERSION_MIN <= ver && ver <= qrcodegen_VERSION_MAX);
	int result = (16 * ver + 128) * ver + 64;
	if (ver >= 2) {
		int numAlign = ver / 7 + 2;
		result -= (25 * numAlign - 10) * numAlign - 55;
		if (ver >= 7)
			result -= 36;
	}
	assert(208 <= result && result <= 29648);
	return result;
}



/*---- Reed-Solomon ECC generator functions ----*/

// Computes a Reed-Solomon ECC generator polynomial for the given degree, storing in result[0 : degree].
// This could be implemented as a lookup table over all possible parameter values, instead of as an algorithm.
private void reedSolomonComputeDivisor(int degree, uint8_t* result) {
	assert(1 <= degree && degree <= qrcodegen_REED_SOLOMON_DEGREE_MAX);
	// Polynomial coefficients are stored from highest to lowest power, excluding the leading term which is always 1.
	// For example the polynomial x^3 + 255x^2 + 8x + 93 is stored as the uint8 array {255, 8, 93}.
	memset(result, 0, cast(size_t)degree * (result[0]).sizeof);
	result[degree - 1] = 1;  // Start off with the monomial x^0

	// Compute the product polynomial (x - r^0) * (x - r^1) * (x - r^2) * ... * (x - r^{degree-1}),
	// drop the highest monomial term which is always 1x^degree.
	// Note that r = 0x02, which is a generator element of this field GF(2^8/0x11D).
	uint8_t root = 1;
	for (int i = 0; i < degree; i++) {
		// Multiply the current product by (x - r^i)
		for (int j = 0; j < degree; j++) {
			result[j] = reedSolomonMultiply(result[j], root);
			if (j + 1 < degree)
				result[j] ^= result[j + 1];
		}
		root = reedSolomonMultiply(root, 0x02);
	}
}


// Computes the Reed-Solomon error correction codeword for the given data and divisor polynomials.
// The remainder when data[0 : dataLen] is divided by divisor[0 : degree] is stored in result[0 : degree].
// All polynomials are in big endian, and the generator has an implicit leading 1 term.
private void reedSolomonComputeRemainder(const uint8_t* data, int dataLen,
		const uint8_t* generator, int degree, uint8_t* result) {
	assert(1 <= degree && degree <= qrcodegen_REED_SOLOMON_DEGREE_MAX);
	memset(result, 0, cast(size_t)degree * (result[0]).sizeof);
	for (int i = 0; i < dataLen; i++) {  // Polynomial division
		uint8_t factor = data[i] ^ result[0];
		memmove(&result[0], &result[1], cast(size_t)(degree - 1) * (result[0]).sizeof);
		result[degree - 1] = 0;
		for (int j = 0; j < degree; j++)
			result[j] ^= reedSolomonMultiply(generator[j], factor);
	}
}

// Returns the product of the two given field elements modulo GF(2^8/0x11D).
// All inputs are valid. This could be implemented as a 256*256 lookup table.
private uint8_t reedSolomonMultiply(uint8_t x, uint8_t y) {
	// Russian peasant multiplication
	uint8_t z = 0;
	for (int i = 7; i >= 0; i--) {
		z = cast(uint8_t)((z << 1) ^ ((z >> 7) * 0x11D));
		z ^= ((y >> i) & 1) * x;
	}
	return z;
}



/*---- Drawing function modules ----*/

// Clears the given QR Code grid with white modules for the given
// version_'s size, then marks every function module as black.
private void initializeFunctionModules(int version_, uint8_t* qrcode) {
	// Initialize QR Code
	int qrsize = version_ * 4 + 17;
	memset(qrcode, 0, cast(size_t)((qrsize * qrsize + 7) / 8 + 1) * (qrcode[0]).sizeof);
	qrcode[0] = cast(uint8_t)qrsize;

	// Fill horizontal and vertical timing patterns
	fillRectangle(6, 0, 1, qrsize, qrcode);
	fillRectangle(0, 6, qrsize, 1, qrcode);

	// Fill 3 finder patterns (all corners except bottom right) and format bits
	fillRectangle(0, 0, 9, 9, qrcode);
	fillRectangle(qrsize - 8, 0, 8, 9, qrcode);
	fillRectangle(0, qrsize - 8, 9, 8, qrcode);

	// Fill numerous alignment patterns
	uint8_t[7] alignPatPos;
	int numAlign = getAlignmentPatternPositions(version_, alignPatPos);
	for (int i = 0; i < numAlign; i++) {
		for (int j = 0; j < numAlign; j++) {
			// Don't draw on the three finder corners
			if (!((i == 0 && j == 0) || (i == 0 && j == numAlign - 1) || (i == numAlign - 1 && j == 0)))
				fillRectangle(alignPatPos[i] - 2, alignPatPos[j] - 2, 5, 5, qrcode);
		}
	}

	// Fill version_ blocks
	if (version_ >= 7) {
		fillRectangle(qrsize - 11, 0, 3, 6, qrcode);
		fillRectangle(0, qrsize - 11, 6, 3, qrcode);
	}
}


// Draws white function modules and possibly some black modules onto the given QR Code, without changing
// non-function modules. This does not draw the format bits. This requires all function modules to be previously
// marked black (namely by initializeFunctionModules()), because this may skip redrawing black function modules.
static void drawWhiteFunctionModules(uint8_t* qrcode, int version_) {
	// Draw horizontal and vertical timing patterns
	int qrsize = qrcodegen_getSize(qrcode);
	for (int i = 7; i < qrsize - 7; i += 2) {
		setModule(qrcode, 6, i, false);
		setModule(qrcode, i, 6, false);
	}

	// Draw 3 finder patterns (all corners except bottom right; overwrites some timing modules)
	for (int dy = -4; dy <= 4; dy++) {
		for (int dx = -4; dx <= 4; dx++) {
			int dist = abs(dx);
			if (abs(dy) > dist)
				dist = abs(dy);
			if (dist == 2 || dist == 4) {
				setModuleBounded(qrcode, 3 + dx, 3 + dy, false);
				setModuleBounded(qrcode, qrsize - 4 + dx, 3 + dy, false);
				setModuleBounded(qrcode, 3 + dx, qrsize - 4 + dy, false);
			}
		}
	}

	// Draw numerous alignment patterns
	uint8_t[7] alignPatPos;
	int numAlign = getAlignmentPatternPositions(version_, alignPatPos);
	for (int i = 0; i < numAlign; i++) {
		for (int j = 0; j < numAlign; j++) {
			if ((i == 0 && j == 0) || (i == 0 && j == numAlign - 1) || (i == numAlign - 1 && j == 0))
				continue;  // Don't draw on the three finder corners
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++)
					setModule(qrcode, alignPatPos[i] + dx, alignPatPos[j] + dy, dx == 0 && dy == 0);
			}
		}
	}

	// Draw version_ blocks
	if (version_ >= 7) {
		// Calculate error correction code and pack bits
		int rem = version_;  // version_ is uint6, in the range [7, 40]
		for (int i = 0; i < 12; i++)
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
		c_long bits = cast(c_long)version_ << 12 | rem;  // uint18
		assert(bits >> 18 == 0);

		// Draw two copies
		for (int i = 0; i < 6; i++) {
			for (int j = 0; j < 3; j++) {
				int k = qrsize - 11 + j;
				setModule(qrcode, k, i, (bits & 1) != 0);
				setModule(qrcode, i, k, (bits & 1) != 0);
				bits >>= 1;
			}
		}
	}
}


// Draws two copies of the format bits (with its own error correction code) based
// on the given mask and error correction level. This always draws all modules of
// the format bits, unlike drawWhiteFunctionModules() which might skip black modules.
static void drawFormatBits(qrcodegen_Ecc ecl, qrcodegen_Mask mask, uint8_t* qrcode) {
	// Calculate error correction code and pack bits
	assert(0 <= cast(int)mask && cast(int)mask <= 7);
	static const int[] table = [1, 0, 3, 2];
	int data = table[cast(int)ecl] << 3 | cast(int)mask;  // errCorrLvl is uint2, mask is uint3
	int rem = data;
	for (int i = 0; i < 10; i++)
		rem = (rem << 1) ^ ((rem >> 9) * 0x537);
	int bits = (data << 10 | rem) ^ 0x5412;  // uint15
	assert(bits >> 15 == 0);

	// Draw first copy
	for (int i = 0; i <= 5; i++)
		setModule(qrcode, 8, i, getBit(bits, i));
	setModule(qrcode, 8, 7, getBit(bits, 6));
	setModule(qrcode, 8, 8, getBit(bits, 7));
	setModule(qrcode, 7, 8, getBit(bits, 8));
	for (int i = 9; i < 15; i++)
		setModule(qrcode, 14 - i, 8, getBit(bits, i));

	// Draw second copy
	int qrsize = qrcodegen_getSize(qrcode);
	for (int i = 0; i < 8; i++)
		setModule(qrcode, qrsize - 1 - i, 8, getBit(bits, i));
	for (int i = 8; i < 15; i++)
		setModule(qrcode, 8, qrsize - 15 + i, getBit(bits, i));
	setModule(qrcode, 8, qrsize - 8, true);  // Always black
}


// Calculates and stores an ascending list of positions of alignment patterns
// for this version_ number, returning the length of the list (in the range [0,7]).
// Each position is in the range [0,177), and are used on both the x and y axes.
// This could be implemented as lookup table of 40 variable-length lists of unsigned bytes.
private int getAlignmentPatternPositions(int version_, ref uint8_t[7] result) {
	if (version_ == 1)
		return 0;
	int numAlign = version_ / 7 + 2;
	int step = (version_ == 32) ? 26 :
		(version_*4 + numAlign*2 + 1) / (numAlign*2 - 2) * 2;
	for (int i = numAlign - 1, pos = version_ * 4 + 10; i >= 1; i--, pos -= step)
		result[i] = cast(uint8_t)pos;
	result[0] = 6;
	return numAlign;
}


// Sets every pixel in the range [left : left + width] * [top : top + height] to black.
static void fillRectangle(int left, int top, int width, int height, uint8_t* qrcode) {
	for (int dy = 0; dy < height; dy++) {
		for (int dx = 0; dx < width; dx++)
			setModule(qrcode, left + dx, top + dy, true);
	}
}



/*---- Drawing data modules and masking ----*/

// Draws the raw codewords (including data and ECC) onto the given QR Code. This requires the initial state of
// the QR Code to be black at function modules and white at codeword modules (including unused remainder bits).
static void drawCodewords(const uint8_t* data, int dataLen, uint8_t* qrcode) {
	int qrsize = qrcodegen_getSize(qrcode);
	int i = 0;  // Bit index into the data
	// Do the funny zigzag scan
	for (int right = qrsize - 1; right >= 1; right -= 2) {  // Index of right column in each column pair
		if (right == 6)
			right = 5;
		for (int vert = 0; vert < qrsize; vert++) {  // Vertical counter
			for (int j = 0; j < 2; j++) {
				int x = right - j;  // Actual x coordinate
				bool upward = ((right + 1) & 2) == 0;
				int y = upward ? qrsize - 1 - vert : vert;  // Actual y coordinate
				if (!getModule(qrcode, x, y) && i < dataLen * 8) {
					bool black = getBit(data[i >> 3], 7 - (i & 7));
					setModule(qrcode, x, y, black);
					i++;
				}
				// If this QR Code has any remainder bits (0 to 7), they were assigned as
				// 0/false/white by the constructor and are left unchanged by this method
			}
		}
	}
	assert(i == dataLen * 8);
}


// XORs the codeword modules in this QR Code with the given mask pattern.
// The function modules must be marked and the codeword bits must be drawn
// before masking. Due to the arithmetic of XOR, calling applyMask() with
// the same mask value a second time will undo the mask. A final well-formed
// QR Code needs exactly one (not zero, two, etc.) mask applied.
static void applyMask(const uint8_t* functionModules, uint8_t* qrcode, qrcodegen_Mask mask) {
	assert(0 <= cast(int)mask && cast(int)mask <= 7);  // Disallows qrcodegen_Mask_AUTO
	int qrsize = qrcodegen_getSize(qrcode);
	for (int y = 0; y < qrsize; y++) {
		for (int x = 0; x < qrsize; x++) {
			if (getModule(functionModules, x, y))
				continue;
			bool invert;
			switch (cast(int)mask) {
				case 0:  invert = (x + y) % 2 == 0;                    break;
				case 1:  invert = y % 2 == 0;                          break;
				case 2:  invert = x % 3 == 0;                          break;
				case 3:  invert = (x + y) % 3 == 0;                    break;
				case 4:  invert = (x / 3 + y / 2) % 2 == 0;            break;
				case 5:  invert = x * y % 2 + x * y % 3 == 0;          break;
				case 6:  invert = (x * y % 2 + x * y % 3) % 2 == 0;    break;
				case 7:  invert = ((x + y) % 2 + x * y % 3) % 2 == 0;  break;
				default:  assert(false);
			}
			bool val = getModule(qrcode, x, y);
			setModule(qrcode, x, y, val ^ invert);
		}
	}
}


// Calculates and returns the penalty score based on state of the given QR Code's current modules.
// This is used by the automatic mask choice algorithm to find the mask pattern that yields the lowest score.
static long getPenaltyScore(const uint8_t* qrcode) {
	int qrsize = qrcodegen_getSize(qrcode);
	long result = 0;

	// Adjacent modules in row having same color, and finder-like patterns
	for (int y = 0; y < qrsize; y++) {
		bool runColor = false;
		int runX = 0;
		int[7] runHistory = 0;
		for (int x = 0; x < qrsize; x++) {
			if (getModule(qrcode, x, y) == runColor) {
				runX++;
				if (runX == 5)
					result += PENALTY_N1;
				else if (runX > 5)
					result++;
			} else {
				finderPenaltyAddHistory(runX, runHistory, qrsize);
				if (!runColor)
					result += finderPenaltyCountPatterns(runHistory, qrsize) * PENALTY_N3;
				runColor = getModule(qrcode, x, y);
				runX = 1;
			}
		}
		result += finderPenaltyTerminateAndCount(runColor, runX, runHistory, qrsize) * PENALTY_N3;
	}
	// Adjacent modules in column having same color, and finder-like patterns
	for (int x = 0; x < qrsize; x++) {
		bool runColor = false;
		int runY = 0;
		int[7] runHistory = 0;
		for (int y = 0; y < qrsize; y++) {
			if (getModule(qrcode, x, y) == runColor) {
				runY++;
				if (runY == 5)
					result += PENALTY_N1;
				else if (runY > 5)
					result++;
			} else {
				finderPenaltyAddHistory(runY, runHistory, qrsize);
				if (!runColor)
					result += finderPenaltyCountPatterns(runHistory, qrsize) * PENALTY_N3;
				runColor = getModule(qrcode, x, y);
				runY = 1;
			}
		}
		result += finderPenaltyTerminateAndCount(runColor, runY, runHistory, qrsize) * PENALTY_N3;
	}

	// 2*2 blocks of modules having same color
	for (int y = 0; y < qrsize - 1; y++) {
		for (int x = 0; x < qrsize - 1; x++) {
			bool  color = getModule(qrcode, x, y);
			if (  color == getModule(qrcode, x + 1, y) &&
			      color == getModule(qrcode, x, y + 1) &&
			      color == getModule(qrcode, x + 1, y + 1))
				result += PENALTY_N2;
		}
	}

	// Balance of black and white modules
	int black = 0;
	for (int y = 0; y < qrsize; y++) {
		for (int x = 0; x < qrsize; x++) {
			if (getModule(qrcode, x, y))
				black++;
		}
	}
	int total = qrsize * qrsize;  // Note that size is odd, so black/total != 1/2
	// Compute the smallest integer k >= 0 such that (45-5k)% <= black/total <= (55+5k)%
	int k = cast(int)((labs(black * 20 - total * 10) + total - 1) / total) - 1;
	result += k * PENALTY_N4;
	return result;
}


// Can only be called immediately after a white run is added, and
// returns either 0, 1, or 2. A helper function for getPenaltyScore().
static int finderPenaltyCountPatterns(const int[7] runHistory, int qrsize) {
	int n = runHistory[1];
	assert(n <= qrsize * 3);
	bool core = n > 0 && runHistory[2] == n && runHistory[3] == n * 3 && runHistory[4] == n && runHistory[5] == n;
	// The maximum QR Code size is 177, hence the black run length n <= 177.
	// Arithmetic is promoted to int, so n*4 will not overflow.
	return (core && runHistory[0] >= n * 4 && runHistory[6] >= n ? 1 : 0)
	     + (core && runHistory[6] >= n * 4 && runHistory[0] >= n ? 1 : 0);
}


// Must be called at the end of a line (row or column) of modules. A helper function for getPenaltyScore().
static int finderPenaltyTerminateAndCount(bool currentRunColor, int currentRunLength, ref int[7] runHistory, int qrsize) {
	if (currentRunColor) {  // Terminate black run
		finderPenaltyAddHistory(currentRunLength, runHistory, qrsize);
		currentRunLength = 0;
	}
	currentRunLength += qrsize;  // Add white border to final run
	finderPenaltyAddHistory(currentRunLength, runHistory, qrsize);
	return finderPenaltyCountPatterns(runHistory, qrsize);
}


// Pushes the given value to the front and drops the last value. A helper function for getPenaltyScore().
static void finderPenaltyAddHistory(int currentRunLength, ref int[7] runHistory, int qrsize) {
	if (runHistory[0] == 0)
		currentRunLength += qrsize;  // Add white border to initial run
	memmove(&runHistory[1], &runHistory[0], 6 * (runHistory[0]).sizeof);
	runHistory[0] = currentRunLength;
}



/*---- Basic QR Code information ----*/

// Public function - see documentation comment in header file.

/*
 * Returns the side length of the given QR Code, assuming that encoding succeeded.
 * The result is in the range [21, 177]. Note that the length of the array buffer
 * is related to the side length - every 'uint8_t qrcode[]' must have length at least
 * qrcodegen_BUFFER_LEN_FOR_VERSION(version), which equals ceil(size^2 / 8 + 1).
 */

int qrcodegen_getSize(const uint8_t* qrcode) {
	assert(qrcode != null);
	int result = qrcode[0];
	assert((qrcodegen_VERSION_MIN * 4 + 17) <= result
		&& result <= (qrcodegen_VERSION_MAX * 4 + 17));
	return result;
}


// Public function - see documentation comment in header file.

/*
 * Returns the color of the module (pixel) at the given coordinates, which is false
 * for white or true for black. The top left corner has the coordinates (x=0, y=0).
 * If the given coordinates are out of bounds, then false (white) is returned.
 */

bool qrcodegen_getModule(const uint8_t* qrcode, int x, int y) {
	assert(qrcode != null);
	int qrsize = qrcode[0];
	return (0 <= x && x < qrsize && 0 <= y && y < qrsize) && getModule(qrcode, x, y);
}


// Gets the module at the given coordinates, which must be in bounds.
private bool getModule(const uint8_t* qrcode, int x, int y) {
	int qrsize = qrcode[0];
	assert(21 <= qrsize && qrsize <= 177 && 0 <= x && x < qrsize && 0 <= y && y < qrsize);
	int index = y * qrsize + x;
	return getBit(qrcode[(index >> 3) + 1], index & 7);
}


// Sets the module at the given coordinates, which must be in bounds.
private void setModule(uint8_t* qrcode, int x, int y, bool isBlack) {
	int qrsize = qrcode[0];
	assert(21 <= qrsize && qrsize <= 177 && 0 <= x && x < qrsize && 0 <= y && y < qrsize);
	int index = y * qrsize + x;
	int bitIndex = index & 7;
	int byteIndex = (index >> 3) + 1;
	if (isBlack)
		qrcode[byteIndex] |= 1 << bitIndex;
	else
		qrcode[byteIndex] &= (1 << bitIndex) ^ 0xFF;
}


// Sets the module at the given coordinates, doing nothing if out of bounds.
private void setModuleBounded(uint8_t* qrcode, int x, int y, bool isBlack) {
	int qrsize = qrcode[0];
	if (0 <= x && x < qrsize && 0 <= y && y < qrsize)
		setModule(qrcode, x, y, isBlack);
}


// Returns true iff the i'th bit of x is set to 1. Requires x >= 0 and 0 <= i <= 14.
static bool getBit(int x, int i) {
	return ((x >> i) & 1) != 0;
}



/*---- Segment handling ----*/

// Public function - see documentation comment in header file.

/*
 * Tests whether the given string can be encoded as a segment in alphanumeric mode.
 * A string is encodable iff each character is in the following set: 0 to 9, A to Z
 * (uppercase only), space, dollar, percent, asterisk, plus, hyphen, period, slash, colon.
 */
bool qrcodegen_isAlphanumeric(const(char)* text) {
	assert(text != null);
	for (; *text != '\0'; text++) {
		if (strchr(ALPHANUMERIC_CHARSET, *text) == null)
			return false;
	}
	return true;
}


// Public function - see documentation comment in header file.

/*
 * Tests whether the given string can be encoded as a segment in numeric mode.
 * A string is encodable iff each character is in the range 0 to 9.
 */
bool qrcodegen_isNumeric(const(char)* text) {
	assert(text != null);
	for (; *text != '\0'; text++) {
		if (*text < '0' || *text > '9')
			return false;
	}
	return true;
}


// Public function - see documentation comment in header file.

/*
 * Returns the number of bytes (uint8_t) needed for the data buffer of a segment
 * containing the given number of characters using the given mode. Notes:
 * - Returns SIZE_MAX on failure, i.e. numChars > INT16_MAX or
 *   the number of needed bits exceeds INT16_MAX (i.e. 32767).
 * - Otherwise, all valid results are in the range [0, ceil(INT16_MAX / 8)], i.e. at most 4096.
 * - It is okay for the user to allocate more bytes for the buffer than needed.
 * - For byte mode, numChars measures the number of bytes, not Unicode code points.
 * - For ECI mode, numChars must be 0, and the worst-case number of bytes is returned.
 *   An actual ECI segment can have shorter data. For non-ECI modes, the result is exact.
 */

size_t qrcodegen_calcSegmentBufferSize(qrcodegen_Mode mode, size_t numChars) {
	int temp = calcSegmentBitLength(mode, numChars);
	if (temp == -1)
		return SIZE_MAX;
	assert(0 <= temp && temp <= INT16_MAX);
	return (cast(size_t)temp + 7) / 8;
}


// Returns the number of data bits needed to represent a segment
// containing the given number of characters using the given mode. Notes:
// - Returns -1 on failure, i.e. numChars > INT16_MAX or
//   the number of needed bits exceeds INT16_MAX (i.e. 32767).
// - Otherwise, all valid results are in the range [0, INT16_MAX].
// - For byte mode, numChars measures the number of bytes, not Unicode code points.
// - For ECI mode, numChars must be 0, and the worst-case number of bits is returned.
//   An actual ECI segment can have shorter data. For non-ECI modes, the result is exact.
private int calcSegmentBitLength(qrcodegen_Mode mode, size_t numChars) {
	// All calculations are designed to avoid overflow on all platforms
	if (numChars > cast(uint)INT16_MAX)
		return -1;
	c_long result = cast(c_long)numChars;
	if (mode == qrcodegen_Mode_NUMERIC)
		result = (result * 10 + 2) / 3;  // ceil(10/3 * n)
	else if (mode == qrcodegen_Mode_ALPHANUMERIC)
		result = (result * 11 + 1) / 2;  // ceil(11/2 * n)
	else if (mode == qrcodegen_Mode_BYTE)
		result *= 8;
	else if (mode == qrcodegen_Mode_KANJI)
		result *= 13;
	else if (mode == qrcodegen_Mode_ECI && numChars == 0)
		result = 3 * 8;
	else {  // Invalid argument
		assert(false);
	}
	assert(result >= 0);
	if (result > INT16_MAX)
		return -1;
	return cast(int)result;
}


// Public function - see documentation comment in header file.

/*
 * Returns a segment representing the given binary data encoded in
 * byte mode. All input byte arrays are acceptable. Any text string
 * can be converted to UTF-8 bytes and encoded as a byte mode segment.
 */

qrcodegen_Segment qrcodegen_makeBytes(const uint8_t* data, size_t len, uint8_t* buf) {
	assert(data != null || len == 0);
	qrcodegen_Segment result;
	result.mode = qrcodegen_Mode_BYTE;
	result.bitLength = calcSegmentBitLength(result.mode, len);
	assert(result.bitLength != -1);
	result.numChars = cast(int)len;
	if (len > 0)
		memcpy(buf, data, len * (buf[0]).sizeof);
	result.data = buf;
	return result;
}


// Public function - see documentation comment in header file.

/*
 * Returns a segment representing the given string of decimal digits encoded in numeric mode.
 */

qrcodegen_Segment qrcodegen_makeNumeric(const(char)* digits, uint8_t* buf) {
	assert(digits != null);
	qrcodegen_Segment result;
	size_t len = strlen(digits);
	result.mode = qrcodegen_Mode_NUMERIC;
	int bitLen = calcSegmentBitLength(result.mode, len);
	assert(bitLen != -1);
	result.numChars = cast(int)len;
	if (bitLen > 0)
		memset(buf, 0, (cast(size_t)bitLen + 7) / 8 * (buf[0]).sizeof);
	result.bitLength = 0;

	uint accumData = 0;
	int accumCount = 0;
	for (; *digits != '\0'; digits++) {
		char c = *digits;
		assert('0' <= c && c <= '9');
		accumData = accumData * 10 + cast(uint)(c - '0');
		accumCount++;
		if (accumCount == 3) {
			appendBitsToBuffer(accumData, 10, buf, &result.bitLength);
			accumData = 0;
			accumCount = 0;
		}
	}
	if (accumCount > 0)  // 1 or 2 digits remaining
		appendBitsToBuffer(accumData, accumCount * 3 + 1, buf, &result.bitLength);
	assert(result.bitLength == bitLen);
	result.data = buf;
	return result;
}


// Public function - see documentation comment in header file.

/*
 * Returns a segment representing the given text string encoded in alphanumeric mode.
 * The characters allowed are: 0 to 9, A to Z (uppercase only), space,
 * dollar, percent, asterisk, plus, hyphen, period, slash, colon.
 */

qrcodegen_Segment qrcodegen_makeAlphanumeric(const(char)* text, uint8_t* buf) {
	assert(text != null);
	qrcodegen_Segment result;
	size_t len = strlen(text);
	result.mode = qrcodegen_Mode_ALPHANUMERIC;
	int bitLen = calcSegmentBitLength(result.mode, len);
	assert(bitLen != -1);
	result.numChars = cast(int)len;
	if (bitLen > 0)
		memset(buf, 0, (cast(size_t)bitLen + 7) / 8 * (buf[0]).sizeof);
	result.bitLength = 0;

	uint accumData = 0;
	int accumCount = 0;
	for (; *text != '\0'; text++) {
		const char *temp = strchr(ALPHANUMERIC_CHARSET, *text);
		assert(temp != null);
		accumData = accumData * 45 + cast(uint)(temp - ALPHANUMERIC_CHARSET);
		accumCount++;
		if (accumCount == 2) {
			appendBitsToBuffer(accumData, 11, buf, &result.bitLength);
			accumData = 0;
			accumCount = 0;
		}
	}
	if (accumCount > 0)  // 1 character remaining
		appendBitsToBuffer(accumData, 6, buf, &result.bitLength);
	assert(result.bitLength == bitLen);
	result.data = buf;
	return result;
}


// Public function - see documentation comment in header file.

/*
 * Returns a segment representing an Extended Channel Interpretation
 * (ECI) designator with the given assignment value.
 */

qrcodegen_Segment qrcodegen_makeEci(c_long assignVal, uint8_t* buf) {
	qrcodegen_Segment result;
	result.mode = qrcodegen_Mode_ECI;
	result.numChars = 0;
	result.bitLength = 0;
	if (assignVal < 0)
		assert(false);
	else if (assignVal < (1 << 7)) {
		memset(buf, 0, 1 * (buf[0]).sizeof);
		appendBitsToBuffer(cast(uint)assignVal, 8, buf, &result.bitLength);
	} else if (assignVal < (1 << 14)) {
		memset(buf, 0, 2 * (buf[0]).sizeof);
		appendBitsToBuffer(2, 2, buf, &result.bitLength);
		appendBitsToBuffer(cast(uint)assignVal, 14, buf, &result.bitLength);
	} else if (assignVal < 1000000L) {
		memset(buf, 0, 3 * (buf[0]).sizeof);
		appendBitsToBuffer(6, 3, buf, &result.bitLength);
		appendBitsToBuffer(cast(uint)(assignVal >> 10), 11, buf, &result.bitLength);
		appendBitsToBuffer(cast(uint)(assignVal & 0x3FF), 10, buf, &result.bitLength);
	} else
		assert(false);
	result.data = buf;
	return result;
}


// Calculates the number of bits needed to encode the given segments at the given version_.
// Returns a non-negative number if successful. Otherwise returns -1 if a segment has too
// many characters to fit its length field, or the total bits exceeds INT16_MAX.
private int getTotalBits(const qrcodegen_Segment* segs, size_t len, int version_) {
	assert(segs != null || len == 0);
	long result = 0;
	for (size_t i = 0; i < len; i++) {
		int numChars  = segs[i].numChars;
		int bitLength = segs[i].bitLength;
		assert(0 <= numChars  && numChars  <= INT16_MAX);
		assert(0 <= bitLength && bitLength <= INT16_MAX);
		int ccbits = numCharCountBits(segs[i].mode, version_);
		assert(0 <= ccbits && ccbits <= 16);
		if (numChars >= (1L << ccbits))
			return -1;  // The segment's length doesn't fit the field's bit width
		result += 4L + ccbits + bitLength;
		if (result > INT16_MAX)
			return -1;  // The sum might overflow an int type
	}
	assert(0 <= result && result <= INT16_MAX);
	return cast(int)result;
}


// Returns the bit width of the character count field for a segment in the given mode
// in a QR Code at the given version_ number. The result is in the range [0, 16].
static int numCharCountBits(qrcodegen_Mode mode, int version_) {
	assert(qrcodegen_VERSION_MIN <= version_ && version_ <= qrcodegen_VERSION_MAX);
	int i = (version_ + 7) / 17;
	switch (mode) {
		case qrcodegen_Mode_NUMERIC     : { static immutable int[] temp1 = [10, 12, 14]; return temp1[i]; }
		case qrcodegen_Mode_ALPHANUMERIC: { static immutable int[] temp2 = [ 9, 11, 13]; return temp2[i]; }
		case qrcodegen_Mode_BYTE        : { static immutable int[] temp3 = [ 8, 16, 16]; return temp3[i]; }
		case qrcodegen_Mode_KANJI       : { static immutable int[] temp4 = [ 8, 10, 12]; return temp4[i]; }
		case qrcodegen_Mode_ECI         : return 0;
		default:  assert(false);  // Dummy value
	}
}

/++

+/
struct QrCode {
	ubyte[qrcodegen_BUFFER_LEN_MAX] qrcode;

	this(string text) {
		ubyte[qrcodegen_BUFFER_LEN_MAX] tempBuffer;
		bool ok = qrcodegen_encodeText((text ~ "\0").ptr, tempBuffer.ptr, qrcode.ptr,
			qrcodegen_Ecc_MEDIUM, qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
		if(!ok)
			throw new Exception("qr code generation failed");
	}

	/++
		The size of the square of the code. It is size x size.
	+/
	int size() {
		return qrcodegen_getSize(qrcode.ptr);
	}

	/++
		Returns true if it is a dark square, false if it is a light one.
	+/
	bool opIndex(int x, int y) {
		return qrcodegen_getModule(qrcode.ptr, x, y);
	}
}

