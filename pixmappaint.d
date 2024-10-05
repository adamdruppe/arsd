/+
	== pixmappaint ==
	Copyright Elias Batek (0xEAB) 2024.
	Distributed under the Boost Software License, Version 1.0.
+/
/++
	Pixmap image manipulation

	$(WARNING
		$(B Early Technology Preview.)
	)

	$(PITFALL
		This module is $(B work in progress).
		API is subject to changes until further notice.
	)
 +/
module arsd.pixmappaint;

import arsd.color;
import arsd.core;

private float roundImpl(float f) {
	import std.math : round;

	return round(f);
}

// `pure` rounding function.
// std.math.round() isn’t pure on all targets.
private float round(float f) pure @nogc nothrow @trusted {
	return (castTo!(float function(float) pure @nogc nothrow)(&roundImpl))(f);
}

/*
	## TODO:

	- Refactoring the template-mess of blendPixel() & co.
	- Scaling
	- Cropping
	- Rotating
	- Skewing
	- HSL
	- Advanced blend modes (maybe)
 */

///
alias Color = arsd.color.Color;

///
alias ColorF = arsd.color.ColorF;

///
alias Pixel = Color;

///
alias Point = arsd.color.Point;

///
alias Rectangle = arsd.color.Rectangle;

///
alias Size = arsd.color.Size;

// verify assumption(s)
static assert(Pixel.sizeof == uint.sizeof);

@safe pure nothrow @nogc {
	///
	Pixel rgba(ubyte r, ubyte g, ubyte b, ubyte a = 0xFF) {
		return Pixel(r, g, b, a);
	}

	///
	Pixel rgba(ubyte r, ubyte g, ubyte b, float aPct)
	in (aPct >= 0 && aPct <= 1) {
		return Pixel(r, g, b, castTo!ubyte(aPct * 255));
	}

	///
	Pixel rgb(ubyte r, ubyte g, ubyte b) {
		return rgba(r, g, b, 0xFF);
	}
}

/++
	Pixel data container
 +/
struct Pixmap {

	/// Pixel data
	Pixel[] data;

	/// Pixel per row
	int width;

@safe pure nothrow:

	///
	this(Size size) {
		this.size = size;
	}

	///
	this(int width, int height)
	in (width > 0)
	in (height > 0) {
		this(Size(width, height));
	}

	///
	this(inout(Pixel)[] data, int width) inout @nogc
	in (data.length % width == 0) {
		this.data = data;
		this.width = width;
	}

	/++
		Creates a $(I deep clone) of the Pixmap
	 +/
	Pixmap clone() const {
		auto c = Pixmap();
		c.width = this.width;
		c.data = this.data.dup;
		return c;
	}

	// undocumented: really shouldn’t be used.
	// carries the risks of `length` and `width` getting out of sync accidentally.
	deprecated("Use `size` instead.")
	void length(int value) {
		data.length = value;
	}

	/++
		Changes the size of the buffer

		Reallocates the underlying pixel array.
	 +/
	void size(Size value) {
		data.length = value.area;
		width = value.width;
	}

	/// ditto
	void size(int totalPixels, int width)
	in (totalPixels % width == 0) {
		data.length = totalPixels;
		this.width = width;
	}

	static {
		/++
			Creates a Pixmap wrapping the pixel data from the provided `TrueColorImage`.

			Interoperability function: `arsd.color`
		 +/
		Pixmap fromTrueColorImage(TrueColorImage source) @nogc {
			return Pixmap(source.imageData.colors, source.width);
		}

		/++
			Creates a Pixmap wrapping the pixel data from the provided `MemoryImage`.

			Interoperability function: `arsd.color`
		 +/
		Pixmap fromMemoryImage(MemoryImage source) {
			return fromTrueColorImage(source.getAsTrueColorImage());
		}
	}

@safe pure nothrow @nogc:

	/// Height of the buffer, i.e. the number of lines
	int height() inout {
		if (width == 0) {
			return 0;
		}

		return castTo!int(data.length / width);
	}

	/// Rectangular size of the buffer
	Size size() inout {
		return Size(width, height);
	}

	/// Length of the buffer, i.e. the number of pixels
	int length() inout {
		return castTo!int(data.length);
	}

	/++
		Number of bytes per line

		Returns:
			width × Pixel.sizeof
	 +/
	int pitch() inout {
		return (width * int(Pixel.sizeof));
	}

	/++
		Calculates the index (linear offset) of the requested position
		within the pixmap data.
	+/
	int scanTo(Point pos) inout {
		return linearOffset(width, pos);
	}

	/++
		Accesses the pixel at the requested position within the pixmap data.
	 +/
	ref inout(Pixel) scan(Point pos) inout {
		return data[scanTo(pos)];
	}

	/++
		Retrieves a linear slice of the pixmap.

		Returns:
			`n` pixels starting at the top-left position `pos`.
	 +/
	inout(Pixel)[] scan(Point pos, int n) inout {
		immutable size_t offset = linearOffset(width, pos);
		immutable size_t end = (offset + n);
		return data[offset .. end];
	}

	/// ditto
	inout(Pixel)[] sliceAt(Point pos, int n) inout {
		return scan(pos, n);
	}

	/++
		Retrieves a rectangular subimage of the pixmap.
	 +/
	inout(SubPixmap) scan2D(Point pos, Size size) inout {
		return inout(SubPixmap)(this, size, pos);
	}

	/++
		Retrieves the first line of the Pixmap.

		See_also:
			Check out [PixmapScanner] for more useful scanning functionality.
	 +/
	inout(Pixel)[] scanLine() inout {
		return data[0 .. width];
	}

	/// Clears the buffer’s contents (by setting each pixel to the same color)
	void clear(Pixel value) {
		data[] = value;
	}
}

/++
	A subpixmap represents a subimage of a [Pixmap].

	This wrapper provides convenient access to a rectangular slice of a Pixmap.

	```
	╔═════════════╗
	║ Pixmap      ║
	║             ║
	║      ┌───┐  ║
	║      │Sub│  ║
	║      └───┘  ║
	╚═════════════╝
	```
 +/
struct SubPixmap {

	/++
		Source image referenced by the subimage
	 +/
	Pixmap source;

	/++
		Size of the subimage
	 +/
	Size size;

	/++
		2D offset of the subimage
	 +/
	Point offset;

	public @safe pure nothrow @nogc {
		///
		this(inout Pixmap source, Size size = Size(0, 0), Point offset = Point(0, 0)) inout {
			this.source = source;
			this.size = size;
			this.offset = offset;
		}

		///
		this(inout Pixmap source, Point offset, Size size = Size(0, 0)) inout {
			this(source, size, offset);
		}
	}

@safe pure nothrow @nogc:

	public {
		/++
			Width of the subimage.
		 +/
		int width() const {
			return size.width;
		}

		/// ditto
		void width(int value) {
			size.width = value;
		}

		/++
			Height of the subimage.
		 +/
		int height() const {
			return size.height;
		}

		/// height
		void height(int value) {
			size.height = value;
		}
	}

	public {
		/++
			Linear offset of the subimage within the source image.

			Calculates the index of the “first pixel of the subimage”
			in the “pixel data of the source image”.
		 +/
		int sourceOffsetLinear() const {
			return linearOffset(offset, source.width);
		}

		/// ditto
		void sourceOffsetLinear(int value) {
			this.offset = Point.fromLinearOffset(value, source.width);
		}

		/++
			$(I Advanced functionality.)

			Offset of the bottom right corner of the subimage
			from the top left corner the source image.
		 +/
		Point sourceOffsetEnd() const {
			return (offset + castTo!Point(size));
		}

		/++
			Linear offset of the subimage within the source image.

			Calculates the index of the “first pixel of the subimage”
			in the “pixel data of the source image”.
		 +/
		int sourceOffsetLinearEnd() const {
			return linearOffset(sourceOffsetEnd, source.width);
		}
	}

	/++
		Determines whether the area of the subimage
		lies within the source image
		and does not overflow its lines.

		$(TIP
			If the offset and/or size of a subimage are off, two issues can occur:

			$(LIST
				* The resulting subimage will look displaced.
				  (As if the lines were shifted.)
				  This indicates that one scanline of the subimage spans over
				  two ore more lines of the source image.
				  (Happens when `(subimage.offset.x + subimage.size.width) > source.size.width`.)
				* When accessing the pixel data, bounds checks will fail.
				  This suggests that the area of the subimage extends beyond
				  the bottom end (and optionally also beyond the right end) of
				  the source.
			)

			Both defects could indicate an invalid subimage.
			Use this function to verify the SubPixmap.
		)
	 +/
	bool isValid() const {
		return (
			(sourceMarginLeft >= 0)
				&& (sourceMarginTop >= 0)
				&& (sourceMarginBottom >= 0)
				&& (sourceMarginRight >= 0)
		);
	}

	public inout {
		/++
			Retrieves the pixel at the requested position of the subimage.
		 +/
		ref inout(Pixel) scan(Point pos) {
			return source.scan(offset + pos);
		}

		/++
			Retrieves the first line of the subimage.
		 +/
		inout(Pixel)[] scanLine() {
			const lo = linearOffset(offset, size.width);
			return source.data[lo .. size.width];
		}
	}

	public void xferTo(SubPixmap target, Blend blend = blendNormal) const {
		auto src = SubPixmapScanner(this);
		auto dst = SubPixmapScannerRW(target);

		foreach (dstLine; dst) {
			blendPixels(dstLine, src.front, blend);
			src.popFront();
		}
	}

	// opposite offset
	public const {
		/++
			$(I Advanced functionality.)

			Offset of the bottom right corner of the source image
			to the bottom right corner of the subimage.

			```
			╔═══════════╗
			║           ║
			║   ┌───┐   ║
			║   │   │   ║
			║   └───┘   ║
			║         ↘ ║
			╚═══════════╝
			```
		 +/
		Point oppositeOffset() {
			return Point(oppositeOffsetX, oppositeOffsetY);
		}

		/++
			$(I Advanced functionality.)

			Offset of the right edge of the source image
			to the right edge of the subimage.

			```
			╔═══════════╗
			║           ║
			║   ┌───┐   ║
			║   │ S │ → ║
			║   └───┘   ║
			║           ║
			╚═══════════╝
			```
		 +/
		int oppositeOffsetX() {
			return (offset.x + size.width);
		}

		/++
			$(I Advanced functionality.)

			Offset of the bottom edge of the source image
			to the bottom edge of the subimage.

			```
			╔═══════════╗
			║           ║
			║   ┌───┐   ║
			║   │ S │   ║
			║   └───┘   ║
			║     ↓     ║
			╚═══════════╝
			```
		 +/
		int oppositeOffsetY() {
			return (offset.y + size.height);
		}

	}

	// source-image margins
	public const {
		/++
			$(I Advanced functionality.)

			X-axis margin (left + right) of the subimage within the source image.

			```
			╔═══════════╗
			║           ║
			║   ┌───┐   ║
			║ ↔ │ S │ ↔ ║
			║   └───┘   ║
			║           ║
			╚═══════════╝
			```
		 +/
		int sourceMarginX() {
			return (source.width - size.width);
		}

		/++
			$(I Advanced functionality.)

			Y-axis margin (top + bottom) of the subimage within the source image.

			```
			╔═══════════╗
			║     ↕     ║
			║   ┌───┐   ║
			║   │ S │   ║
			║   └───┘   ║
			║     ↕     ║
			╚═══════════╝
			```
		 +/
		int sourceMarginY() {
			return (source.height - size.height);
		}

		/++
			$(I Advanced functionality.)

			Top margin of the subimage within the source image.

			```
			╔═══════════╗
			║     ↕     ║
			║   ┌───┐   ║
			║   │ S │   ║
			║   └───┘   ║
			║           ║
			╚═══════════╝
			```
		 +/
		int sourceMarginTop() {
			return offset.y;
		}

		/++
			$(I Advanced functionality.)

			Right margin of the subimage within the source image.

			```
			╔═══════════╗
			║           ║
			║   ┌───┐   ║
			║   │ S │ ↔ ║
			║   └───┘   ║
			║           ║
			╚═══════════╝
			```
		 +/
		int sourceMarginRight() {
			return (sourceMarginX - sourceMarginLeft);
		}

		/++
			$(I Advanced functionality.)

			Bottom margin of the subimage within the source image.

			```
			╔═══════════╗
			║           ║
			║   ┌───┐   ║
			║   │ S │   ║
			║   └───┘   ║
			║     ↕     ║
			╚═══════════╝
			```
		 +/
		int sourceMarginBottom() {
			return (sourceMarginY - sourceMarginTop);
		}

		/++
			$(I Advanced functionality.)

			Left margin of the subimage within the source image.

			```
			╔═══════════╗
			║           ║
			║   ┌───┐   ║
			║ ↔ │ S │   ║
			║   └───┘   ║
			║           ║
			╚═══════════╝
			```
		 +/
		int sourceMarginLeft() {
			return offset.x;
		}
	}

	public const {
		/++
			$(I Advanced functionality.)

			Calculates the linear offset of the provided point in the subimage
			relative to the source image.
		 +/
		int sourceOffsetOf(Point pos) {
			pos = (pos + offset);
			debug {
				import std.stdio : writeln;

				try {
					writeln(pos);
				} catch (Exception) {
				}
			}
			return linearOffset(pos, source.width);
		}
	}
}

/++
	Wrapper for scanning a [Pixmap] line by line.
 +/
struct PixmapScanner {
	private {
		const(Pixel)[] _data;
		int _width;
	}

@safe pure nothrow @nogc:

	///
	public this(const(Pixmap) pixmap) {
		_data = pixmap.data;
		_width = pixmap.width;
	}

	///
	bool empty() const {
		return (_data.length == 0);
	}

	///
	const(Pixel)[] front() const {
		return _data[0 .. _width];
	}

	///
	void popFront() {
		_data = _data[_width .. $];
	}
}

/++
	Wrapper for scanning a [Pixmap] line by line.
 +/
struct SubPixmapScanner {
	private {
		const(Pixel)[] _data;
		int _width;
		int _feed;
	}

@safe pure nothrow @nogc:

	///
	public this(const(SubPixmap) subPixmap) {
		_data = subPixmap.source.data[subPixmap.sourceOffsetLinear .. subPixmap.sourceOffsetLinearEnd];
		_width = subPixmap.size.width;
		_feed = subPixmap.source.width;
	}

	///
	bool empty() const {
		return (_data.length == 0);
	}

	///
	const(Pixel)[] front() const {
		return _data[0 .. _width];
	}

	///
	void popFront() {
		if (_data.length < _feed) {
			_data.length = 0;
			return;
		}

		_data = _data[_feed .. $];
	}
}

/++
	Wrapper for scanning a [Pixmap] line by line.

	See_also:
		Unlike [SubPixmapScanner], this does not work with `const(Pixmap)`.
 +/
struct SubPixmapScannerRW {
	private {
		Pixel[] _data;
		int _width;
		int _feed;
	}

@safe pure nothrow @nogc:

	///
	public this(SubPixmap subPixmap) {
		_data = subPixmap.source.data[subPixmap.sourceOffsetLinear .. subPixmap.sourceOffsetLinearEnd];
		_width = subPixmap.size.width;
		_feed = subPixmap.source.width;
	}

	///
	bool empty() const {
		return (_data.length == 0);
	}

	///
	Pixel[] front() {
		return _data[0 .. _width];
	}

	///
	void popFront() {
		if (_data.length < _feed) {
			_data.length = 0;
			return;
		}

		_data = _data[_feed .. $];
	}
}

///
struct SpriteSheet {
	private {
		Pixmap _pixmap;
		Size _spriteDimensions;
		Size _layout; // pre-computed upon construction
	}

@safe pure nothrow @nogc:

	///
	public this(Pixmap pixmap, Size spriteSize) {
		_pixmap = pixmap;
		_spriteDimensions = spriteSize;

		_layout = Size(
			_pixmap.width / _spriteDimensions.width,
			_pixmap.height / _spriteDimensions.height,
		);
	}

	///
	inout(Pixmap) pixmap() inout {
		return _pixmap;
	}

	///
	Size spriteSize() inout {
		return _spriteDimensions;
	}

	///
	Size layout() inout {
		return _layout;
	}

	///
	Point getSpriteColumn(int index) inout {
		immutable x = index % layout.width;
		immutable y = (index - x) / layout.height;
		return Point(x, y);
	}

	///
	Point getSpritePixelOffset2D(int index) inout {
		immutable col = this.getSpriteColumn(index);
		return Point(
			col.x * _spriteDimensions.width,
			col.y * _spriteDimensions.height,
		);
	}
}

// Silly micro-optimization
private struct OriginRectangle {
	Size size;

@safe pure nothrow @nogc:

	int left() const => 0;
	int top() const => 0;
	int right() const => size.width;
	int bottom() const => size.height;

	bool intersect(const Rectangle b) const {
		// dfmt off
		return (
			(b.right    > 0          ) &&
			(b.left     < this.right ) &&
			(b.bottom   > 0          ) &&
			(b.top      < this.bottom)
		);
		// dfmt on
	}
}

@safe pure nothrow @nogc:

// misc
private {
	Point pos(Rectangle r) => r.upperLeft;

	T max(T)(T a, T b) => (a >= b) ? a : b;
	T min(T)(T a, T b) => (a <= b) ? a : b;
}

/++
	Calculates the square root
	of an integer number
	as an integer number.
 +/
ubyte intSqrt(const ubyte value) @safe pure nothrow @nogc {
	switch (value) {
	default:
		// unreachable
		assert(false, "ubyte != uint8");
	case 0:
		return 0;
	case 1: .. case 2:
		return 1;
	case 3: .. case 6:
		return 2;
	case 7: .. case 12:
		return 3;
	case 13: .. case 20:
		return 4;
	case 21: .. case 30:
		return 5;
	case 31: .. case 42:
		return 6;
	case 43: .. case 56:
		return 7;
	case 57: .. case 72:
		return 8;
	case 73: .. case 90:
		return 9;
	case 91: .. case 110:
		return 10;
	case 111: .. case 132:
		return 11;
	case 133: .. case 156:
		return 12;
	case 157: .. case 182:
		return 13;
	case 183: .. case 210:
		return 14;
	case 211: .. case 240:
		return 15;
	case 241: .. case 255:
		return 16;
	}
}

///
unittest {
	assert(intSqrt(4) == 2);
	assert(intSqrt(9) == 3);
	assert(intSqrt(10) == 3);
}

unittest {
	import std.math : round, sqrt;

	foreach (n; ubyte.min .. ubyte.max + 1) {
		ubyte fp = sqrt(float(n)).round().castTo!ubyte;
		ubyte i8 = intSqrt(n.castTo!ubyte);
		assert(fp == i8);
	}
}

/++
	Calculates the square root
	of the normalized value
	representated by the input integer number.

	Normalization:
		`[0x00 .. 0xFF]` → `[0.0 .. 1.0]`

	Returns:
		sqrt(value / 255f) * 255
 +/
ubyte intNormalizedSqrt(const ubyte value) {
	switch (value) {
	default:
		// unreachable
		assert(false, "ubyte != uint8");
	case 0x00:
		return 0x00;
	case 0x01:
		return 0x10;
	case 0x02:
		return 0x17;
	case 0x03:
		return 0x1C;
	case 0x04:
		return 0x20;
	case 0x05:
		return 0x24;
	case 0x06:
		return 0x27;
	case 0x07:
		return 0x2A;
	case 0x08:
		return 0x2D;
	case 0x09:
		return 0x30;
	case 0x0A:
		return 0x32;
	case 0x0B:
		return 0x35;
	case 0x0C:
		return 0x37;
	case 0x0D:
		return 0x3A;
	case 0x0E:
		return 0x3C;
	case 0x0F:
		return 0x3E;
	case 0x10:
		return 0x40;
	case 0x11:
		return 0x42;
	case 0x12:
		return 0x44;
	case 0x13:
		return 0x46;
	case 0x14:
		return 0x47;
	case 0x15:
		return 0x49;
	case 0x16:
		return 0x4B;
	case 0x17:
		return 0x4D;
	case 0x18:
		return 0x4E;
	case 0x19:
		return 0x50;
	case 0x1A:
		return 0x51;
	case 0x1B:
		return 0x53;
	case 0x1C:
		return 0x54;
	case 0x1D:
		return 0x56;
	case 0x1E:
		return 0x57;
	case 0x1F:
		return 0x59;
	case 0x20:
		return 0x5A;
	case 0x21:
		return 0x5C;
	case 0x22:
		return 0x5D;
	case 0x23:
		return 0x5E;
	case 0x24:
		return 0x60;
	case 0x25:
		return 0x61;
	case 0x26:
		return 0x62;
	case 0x27:
		return 0x64;
	case 0x28:
		return 0x65;
	case 0x29:
		return 0x66;
	case 0x2A:
		return 0x67;
	case 0x2B:
		return 0x69;
	case 0x2C:
		return 0x6A;
	case 0x2D:
		return 0x6B;
	case 0x2E:
		return 0x6C;
	case 0x2F:
		return 0x6D;
	case 0x30:
		return 0x6F;
	case 0x31:
		return 0x70;
	case 0x32:
		return 0x71;
	case 0x33:
		return 0x72;
	case 0x34:
		return 0x73;
	case 0x35:
		return 0x74;
	case 0x36:
		return 0x75;
	case 0x37:
		return 0x76;
	case 0x38:
		return 0x77;
	case 0x39:
		return 0x79;
	case 0x3A:
		return 0x7A;
	case 0x3B:
		return 0x7B;
	case 0x3C:
		return 0x7C;
	case 0x3D:
		return 0x7D;
	case 0x3E:
		return 0x7E;
	case 0x3F:
		return 0x7F;
	case 0x40:
		return 0x80;
	case 0x41:
		return 0x81;
	case 0x42:
		return 0x82;
	case 0x43:
		return 0x83;
	case 0x44:
		return 0x84;
	case 0x45:
		return 0x85;
	case 0x46:
		return 0x86;
	case 0x47: .. case 0x48:
		return 0x87;
	case 0x49:
		return 0x88;
	case 0x4A:
		return 0x89;
	case 0x4B:
		return 0x8A;
	case 0x4C:
		return 0x8B;
	case 0x4D:
		return 0x8C;
	case 0x4E:
		return 0x8D;
	case 0x4F:
		return 0x8E;
	case 0x50:
		return 0x8F;
	case 0x51:
		return 0x90;
	case 0x52: .. case 0x53:
		return 0x91;
	case 0x54:
		return 0x92;
	case 0x55:
		return 0x93;
	case 0x56:
		return 0x94;
	case 0x57:
		return 0x95;
	case 0x58:
		return 0x96;
	case 0x59: .. case 0x5A:
		return 0x97;
	case 0x5B:
		return 0x98;
	case 0x5C:
		return 0x99;
	case 0x5D:
		return 0x9A;
	case 0x5E:
		return 0x9B;
	case 0x5F: .. case 0x60:
		return 0x9C;
	case 0x61:
		return 0x9D;
	case 0x62:
		return 0x9E;
	case 0x63:
		return 0x9F;
	case 0x64: .. case 0x65:
		return 0xA0;
	case 0x66:
		return 0xA1;
	case 0x67:
		return 0xA2;
	case 0x68:
		return 0xA3;
	case 0x69: .. case 0x6A:
		return 0xA4;
	case 0x6B:
		return 0xA5;
	case 0x6C:
		return 0xA6;
	case 0x6D: .. case 0x6E:
		return 0xA7;
	case 0x6F:
		return 0xA8;
	case 0x70:
		return 0xA9;
	case 0x71: .. case 0x72:
		return 0xAA;
	case 0x73:
		return 0xAB;
	case 0x74:
		return 0xAC;
	case 0x75: .. case 0x76:
		return 0xAD;
	case 0x77:
		return 0xAE;
	case 0x78:
		return 0xAF;
	case 0x79: .. case 0x7A:
		return 0xB0;
	case 0x7B:
		return 0xB1;
	case 0x7C:
		return 0xB2;
	case 0x7D: .. case 0x7E:
		return 0xB3;
	case 0x7F:
		return 0xB4;
	case 0x80: .. case 0x81:
		return 0xB5;
	case 0x82:
		return 0xB6;
	case 0x83: .. case 0x84:
		return 0xB7;
	case 0x85:
		return 0xB8;
	case 0x86:
		return 0xB9;
	case 0x87: .. case 0x88:
		return 0xBA;
	case 0x89:
		return 0xBB;
	case 0x8A: .. case 0x8B:
		return 0xBC;
	case 0x8C:
		return 0xBD;
	case 0x8D: .. case 0x8E:
		return 0xBE;
	case 0x8F:
		return 0xBF;
	case 0x90: .. case 0x91:
		return 0xC0;
	case 0x92:
		return 0xC1;
	case 0x93: .. case 0x94:
		return 0xC2;
	case 0x95:
		return 0xC3;
	case 0x96: .. case 0x97:
		return 0xC4;
	case 0x98:
		return 0xC5;
	case 0x99: .. case 0x9A:
		return 0xC6;
	case 0x9B: .. case 0x9C:
		return 0xC7;
	case 0x9D:
		return 0xC8;
	case 0x9E: .. case 0x9F:
		return 0xC9;
	case 0xA0:
		return 0xCA;
	case 0xA1: .. case 0xA2:
		return 0xCB;
	case 0xA3: .. case 0xA4:
		return 0xCC;
	case 0xA5:
		return 0xCD;
	case 0xA6: .. case 0xA7:
		return 0xCE;
	case 0xA8:
		return 0xCF;
	case 0xA9: .. case 0xAA:
		return 0xD0;
	case 0xAB: .. case 0xAC:
		return 0xD1;
	case 0xAD:
		return 0xD2;
	case 0xAE: .. case 0xAF:
		return 0xD3;
	case 0xB0: .. case 0xB1:
		return 0xD4;
	case 0xB2:
		return 0xD5;
	case 0xB3: .. case 0xB4:
		return 0xD6;
	case 0xB5: .. case 0xB6:
		return 0xD7;
	case 0xB7:
		return 0xD8;
	case 0xB8: .. case 0xB9:
		return 0xD9;
	case 0xBA: .. case 0xBB:
		return 0xDA;
	case 0xBC:
		return 0xDB;
	case 0xBD: .. case 0xBE:
		return 0xDC;
	case 0xBF: .. case 0xC0:
		return 0xDD;
	case 0xC1: .. case 0xC2:
		return 0xDE;
	case 0xC3:
		return 0xDF;
	case 0xC4: .. case 0xC5:
		return 0xE0;
	case 0xC6: .. case 0xC7:
		return 0xE1;
	case 0xC8: .. case 0xC9:
		return 0xE2;
	case 0xCA:
		return 0xE3;
	case 0xCB: .. case 0xCC:
		return 0xE4;
	case 0xCD: .. case 0xCE:
		return 0xE5;
	case 0xCF: .. case 0xD0:
		return 0xE6;
	case 0xD1: .. case 0xD2:
		return 0xE7;
	case 0xD3:
		return 0xE8;
	case 0xD4: .. case 0xD5:
		return 0xE9;
	case 0xD6: .. case 0xD7:
		return 0xEA;
	case 0xD8: .. case 0xD9:
		return 0xEB;
	case 0xDA: .. case 0xDB:
		return 0xEC;
	case 0xDC: .. case 0xDD:
		return 0xED;
	case 0xDE: .. case 0xDF:
		return 0xEE;
	case 0xE0:
		return 0xEF;
	case 0xE1: .. case 0xE2:
		return 0xF0;
	case 0xE3: .. case 0xE4:
		return 0xF1;
	case 0xE5: .. case 0xE6:
		return 0xF2;
	case 0xE7: .. case 0xE8:
		return 0xF3;
	case 0xE9: .. case 0xEA:
		return 0xF4;
	case 0xEB: .. case 0xEC:
		return 0xF5;
	case 0xED: .. case 0xEE:
		return 0xF6;
	case 0xEF: .. case 0xF0:
		return 0xF7;
	case 0xF1: .. case 0xF2:
		return 0xF8;
	case 0xF3: .. case 0xF4:
		return 0xF9;
	case 0xF5: .. case 0xF6:
		return 0xFA;
	case 0xF7: .. case 0xF8:
		return 0xFB;
	case 0xF9: .. case 0xFA:
		return 0xFC;
	case 0xFB: .. case 0xFC:
		return 0xFD;
	case 0xFD: .. case 0xFE:
		return 0xFE;
	case 0xFF:
		return 0xFF;
	}
}

unittest {
	import std.math : round, sqrt;

	foreach (n; ubyte.min .. ubyte.max + 1) {
		ubyte fp = (sqrt(n / 255.0f) * 255).round().castTo!ubyte;
		ubyte i8 = intNormalizedSqrt(n.castTo!ubyte);
		assert(fp == i8);
	}
}

/++
	Limits a value to a maximum of 0xFF (= 255).
 +/
ubyte clamp255(Tint)(const Tint value) {
	pragma(inline, true);
	return (value < 0xFF) ? value.castTo!ubyte : 0xFF;
}

/++
	Fast 8-bit “percentage” function

	This function optimizes its runtime performance by substituting
	the division by 255 with an approximation using bitshifts.

	Nonetheless, its result are as accurate as a floating point
	division with 64-bit precision.

	Params:
		nPercentage = percentage as the number of 255ths (“two hundred fifty-fifths”)
		value = base value (“total”)

	Returns:
		`round(value * nPercentage / 255.0)`
 +/
ubyte n255thsOf(const ubyte nPercentage, const ubyte value) {
	immutable factor = (nPercentage | (nPercentage << 8));
	return (((value * factor) + 0x8080) >> 16);
}

@safe unittest {
	// Accuracy verification

	static ubyte n255thsOfFP64(const ubyte nPercentage, const ubyte value) {
		return (double(value) * double(nPercentage) / 255.0).round().castTo!ubyte();
	}

	for (int value = ubyte.min; value <= ubyte.max; ++value) {
		for (int percent = ubyte.min; percent <= ubyte.max; ++percent) {
			immutable v = cast(ubyte) value;
			immutable p = cast(ubyte) percent;

			immutable approximated = n255thsOf(p, v);
			immutable precise = n255thsOfFP64(p, v);
			assert(approximated == precise);
		}
	}
}

/++
	Sets the opacity of a [Pixmap].

	This lossy operation updates the alpha-channel value of each pixel.
	→ `alpha *= opacity`

	See_Also:
		Use [opacityF] with opacity values in percent (%).
 +/
void opacity(Pixmap pixmap, const ubyte opacity) {
	foreach (ref px; pixmap.data) {
		px.a = opacity.n255thsOf(px.a);
	}
}

/++
	Sets the opacity of a [Pixmap].

	This lossy operation updates the alpha-channel value of each pixel.
	→ `alpha *= opacity`

	See_Also:
		Use [opacity] with 8-bit integer opacity values (in 255ths).
 +/
void opacityF(Pixmap pixmap, const float opacity)
in (opacity >= 0)
in (opacity <= 1.0) {
	immutable opacity255 = round(opacity * 255).castTo!ubyte;
	pixmap.opacity = opacity255;
}

/++
	Inverts a color (to its negative color).
 +/
Pixel invert(const Pixel color) {
	return Pixel(
		0xFF - color.r,
		0xFF - color.g,
		0xFF - color.b,
		color.a,
	);
}

/++
	Inverts all colors to produce a $(B negative image).

	$(TIP
		Develops a positive image when applied to a negative one.
	)
 +/
void invert(Pixmap pixmap) {
	foreach (ref px; pixmap.data) {
		px = invert(px);
	}
}

// ==== Blending functions ====

/++
	Alpha-blending accuracy level

	$(TIP
		This primarily exists for performance reasons.
		In my tests LLVM manages to auto-vectorize the RGB-only codepath significantly better,
		while the codegen for the accurate RGBA path is pretty conservative.

		This provides an optimization opportunity for use-cases
		that don’t require an alpha-channel on the result.
	)
 +/
enum BlendAccuracy {
	/++
		Only RGB channels will have the correct result.

		A(lpha) channel can contain any value.

		Suitable for blending into non-transparent targets (e.g. framebuffer, canvas)
		where the resulting alpha-channel (opacity) value does not matter.
	 +/
	rgb = false,

	/++
		All RGBA channels will have the correct result.

		Suitable for blending into transparent targets (e.g. images)
		where the resulting alpha-channel (opacity) value matters.

		Use this mode for image manipulation.
	 +/
	rgba = true,
}

/++
	Blend modes

	$(NOTE
		As blending operations are implemented as integer calculations,
		results may be slightly less precise than those from image manipulation
		programs using floating-point math.
	)

	See_Also:
		<https://www.w3.org/TR/compositing/#blending>
 +/
enum BlendMode {
	///
	none = 0,
	///
	replace = none,
	///
	normal = 1,
	///
	alpha = normal,

	///
	multiply,
	///
	screen,

	///
	overlay,
	///
	hardLight,
	///
	softLight,

	///
	darken,
	///
	lighten,

	///
	colorDodge,
	///
	colorBurn,

	///
	difference,
	///
	exclusion,
	///
	subtract,
	///
	divide,
}

///
alias Blend = BlendMode;

// undocumented
enum blendNormal = BlendMode.normal;

///
alias BlendFn = ubyte function(const ubyte background, const ubyte foreground) pure nothrow @nogc;

/++
	Blends `source` into `target`
	with respect to the opacity of the source image (as stored in the alpha channel).

	See_Also:
		[alphaBlendRGBA] and [alphaBlendRGB] are shorthand functions
		in cases where no special blending algorithm is needed.
 +/
template alphaBlend(BlendFn blend = null, BlendAccuracy accuracy = BlendAccuracy.rgba) {
	/// ditto
	public void alphaBlend(scope Pixel[] target, scope const Pixel[] source) @trusted
	in (source.length == target.length) {
		foreach (immutable idx, ref pxTarget; target) {
			alphaBlend(pxTarget, source.ptr[idx]);
		}
	}

	/// ditto
	public void alphaBlend(ref Pixel pxTarget, const Pixel pxSource) @trusted {
		pragma(inline, true);

		static if (accuracy == BlendAccuracy.rgba) {
			immutable alphaResult = clamp255(pxSource.a + n255thsOf(pxTarget.a, (0xFF - pxSource.a)));
			//immutable alphaResult = clamp255(pxTarget.a + n255thsOf(pxSource.a, (0xFF - pxTarget.a)));
		}

		immutable alphaSource = (pxSource.a | (pxSource.a << 8));
		immutable alphaTarget = (0xFFFF - alphaSource);

		foreach (immutable ib, ref px; pxTarget.components) {
			static if (blend !is null) {
				immutable bx = blend(px, pxSource.components.ptr[ib]);
			} else {
				immutable bx = pxSource.components.ptr[ib];
			}
			immutable d = cast(ubyte)(((px * alphaTarget) + 0x8080) >> 16);
			immutable s = cast(ubyte)(((bx * alphaSource) + 0x8080) >> 16);
			px = cast(ubyte)(d + s);
		}

		static if (accuracy == BlendAccuracy.rgba) {
			pxTarget.a = alphaResult;
		}
	}
}

/// ditto
template alphaBlend(BlendAccuracy accuracy, BlendFn blend = null) {
	alias alphaBlend = alphaBlend!(blend, accuracy);
}

/++
	Blends `source` into `target`
	with respect to the opacity of the source image (as stored in the alpha channel).

	This variant is $(slower than) [alphaBlendRGB],
	but calculates the correct alpha-channel value of the target.
	See [BlendAccuracy] for further explanation.
 +/
public void alphaBlendRGBA(scope Pixel[] target, scope const Pixel[] source) @safe {
	return alphaBlend!(null, BlendAccuracy.rgba)(target, source);
}

/// ditto
public void alphaBlendRGBA(ref Pixel pxTarget, const Pixel pxSource) @safe {
	return alphaBlend!(null, BlendAccuracy.rgba)(pxTarget, pxSource);
}

/++
	Blends `source` into `target`
	with respect to the opacity of the source image (as stored in the alpha channel).

	This variant is $(B faster than) [alphaBlendRGBA],
	but leads to a wrong alpha-channel value in the target.
	Useful because of the performance advantage in cases where the resulting
	alpha does not matter.
	See [BlendAccuracy] for further explanation.
 +/
public void alphaBlendRGB(scope Pixel[] target, scope const Pixel[] source) @safe {
	return alphaBlend!(null, BlendAccuracy.rgb)(target, source);
}

/// ditto
public void alphaBlendRGB(ref Pixel pxTarget, const Pixel pxSource) @safe {
	return alphaBlend!(null, BlendAccuracy.rgb)(pxTarget, pxSource);
}

/++
	Blends pixel `source` into pixel `target`
	using the requested $(B blending mode).
 +/
template blendPixel(BlendMode mode, BlendAccuracy accuracy = BlendAccuracy.rgba) {

	static if (mode == BlendMode.replace) {
		/// ditto
		void blendPixel(ref Pixel target, const Pixel source) {
			target = source;
		}
	}

	static if (mode == BlendMode.alpha) {
		/// ditto
		void blendPixel(ref Pixel target, const Pixel source) {
			return alphaBlend!accuracy(target, source);
		}
	}

	static if (mode == BlendMode.multiply) {
		/// ditto
		void blendPixel(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(a, b) => n255thsOf(a, b)
			)(target, source);
		}
	}

	static if (mode == BlendMode.screen) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(a, b) => castTo!ubyte(0xFF - n255thsOf((0xFF - a), (0xFF - b)))
			)(target, source);
		}
	}

	static if (mode == BlendMode.darken) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(a, b) => min(a, b)
			)(target, source);
		}
	}
	static if (mode == BlendMode.lighten) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(a, b) => max(a, b)
			)(target, source);
		}
	}

	static if (mode == BlendMode.overlay) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy, function(const ubyte b, const ubyte f) {
				if (b < 0x80) {
					return n255thsOf((2 * b).castTo!ubyte, f);
				}
				return castTo!ubyte(
					0xFF - n255thsOf(castTo!ubyte(2 * (0xFF - b)), (0xFF - f))
				);
			})(target, source);
		}
	}

	static if (mode == BlendMode.hardLight) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy, function(const ubyte b, const ubyte f) {
				if (f < 0x80) {
					return n255thsOf(castTo!ubyte(2 * f), b);
				}
				return castTo!ubyte(
					0xFF - n255thsOf(castTo!ubyte(2 * (0xFF - f)), (0xFF - b))
				);
			})(target, source);
		}
	}

	static if (mode == BlendMode.softLight) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy, function(const ubyte b, const ubyte f) {
				if (f < 0x80) {
					// dfmt off
					return castTo!ubyte(
						b - n255thsOf(
								n255thsOf((0xFF - 2 * f).castTo!ubyte, b),
								(0xFF - b),
							)
					);
					// dfmt on
				}

				// TODO: optimize if possible
				// dfmt off
				immutable ubyte d = (b < 0x40)
					? castTo!ubyte((b * (0x3FC + (((16 * b - 0xBF4) * b) / 255))) / 255)
					: intNormalizedSqrt(b);
				//dfmt on

				return castTo!ubyte(
					b + n255thsOf((2 * f - 0xFF).castTo!ubyte, (d - b).castTo!ubyte)
				);
			})(target, source);
		}
	}

	static if (mode == BlendMode.colorDodge) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy, function(const ubyte b, const ubyte f) {
				if (b == 0x00) {
					return ubyte(0x00);
				}
				if (f == 0xFF) {
					return ubyte(0xFF);
				}
				return min(
					ubyte(0xFF),
					clamp255((255 * b) / (0xFF - f))
				);
			})(target, source);
		}
	}

	static if (mode == BlendMode.colorBurn) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy, function(const ubyte b, const ubyte f) {
				if (b == 0xFF) {
					return ubyte(0xFF);
				}
				if (f == 0x00) {
					return ubyte(0x00);
				}

				immutable m = min(
					ubyte(0xFF),
					clamp255(((0xFF - b) * 255) / f)
				);
				return castTo!ubyte(0xFF - m);
			})(target, source);
		}
	}

	static if (mode == BlendMode.difference) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(b, f) => (b > f) ? castTo!ubyte(b - f) : castTo!ubyte(f - b)
			)(target, source);
		}
	}

	static if (mode == BlendMode.exclusion) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(b, f) => castTo!ubyte(b + f - (2 * n255thsOf(f, b)))
			)(target, source);
		}
	}

	static if (mode == BlendMode.subtract) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(b, f) => (b > f) ? castTo!ubyte(b - f) : ubyte(0)
			)(target, source);
		}
	}

	static if (mode == BlendMode.divide) {
		/// ditto
		void blendPixel()(ref Pixel target, const Pixel source) {
			return alphaBlend!(accuracy,
				(b, f) => (f == 0) ? ubyte(0xFF) : clamp255(0xFF * b / f)
			)(target, source);
		}
	}

	//else {
	//	static assert(false, "Missing `blendPixel()` implementation for `BlendMode`.`" ~ mode ~ "`.");
	//}
}

/++
	Blends the pixel data of `source` into `target`
	using the requested $(B blending mode).

	`source` and `target` MUST have the same length.
 +/
void blendPixels(
	BlendMode mode,
	BlendAccuracy accuracy,
)(scope Pixel[] target, scope const Pixel[] source) @trusted
in (source.length == target.length) {
	static if (mode == BlendMode.replace) {
		// explicit optimization
		target.ptr[0 .. target.length] = source.ptr[0 .. target.length];
	} else {

		// better error message in case it’s not implemented
		static if (!is(typeof(blendPixel!(mode, accuracy)))) {
			pragma(msg, "Hint: Missing or bad `blendPixel!(" ~ mode.stringof ~ ")`.");
		}

		foreach (immutable idx, ref pxTarget; target) {
			blendPixel!(mode, accuracy)(pxTarget, source.ptr[idx]);
		}
	}
}

/// ditto
void blendPixels(BlendAccuracy accuracy)(scope Pixel[] target, scope const Pixel[] source, BlendMode mode) {
	import std.meta : NoDuplicates;
	import std.traits : EnumMembers;

	final switch (mode) with (BlendMode) {
		static foreach (m; NoDuplicates!(EnumMembers!BlendMode)) {
	case m:
			return blendPixels!(m, accuracy)(target, source);
		}
	}
}

/// ditto
void blendPixels(
	scope Pixel[] target,
	scope const Pixel[] source,
	BlendMode mode,
	BlendAccuracy accuracy = BlendAccuracy.rgba,
) {
	if (accuracy == BlendAccuracy.rgb) {
		return blendPixels!(BlendAccuracy.rgb)(target, source, mode);
	} else {
		return blendPixels!(BlendAccuracy.rgba)(target, source, mode);
	}
}

// ==== Drawing functions ====

/++
	Draws a single pixel
 +/
void drawPixel(Pixmap target, Point pos, Pixel color) {
	immutable size_t offset = linearOffset(target.width, pos);
	target.data[offset] = color;
}

/++
	Draws a rectangle
 +/
void drawRectangle(Pixmap target, Rectangle rectangle, Pixel color) {
	alias r = rectangle;

	immutable tRect = OriginRectangle(
		Size(target.width, target.height),
	);

	// out of bounds?
	if (!tRect.intersect(r)) {
		return;
	}

	immutable drawingTarget = Point(
		(r.pos.x >= 0) ? r.pos.x : 0,
		(r.pos.y >= 0) ? r.pos.y : 0,
	);

	immutable drawingEnd = Point(
		(r.right < tRect.right) ? r.right : tRect.right,
		(r.bottom < tRect.bottom) ? r.bottom : tRect.bottom,
	);

	immutable int drawingWidth = drawingEnd.x - drawingTarget.x;

	foreach (y; drawingTarget.y .. drawingEnd.y) {
		target.sliceAt(Point(drawingTarget.x, y), drawingWidth)[] = color;
	}
}

/++
	Draws a line
 +/
void drawLine(Pixmap target, Point a, Point b, Pixel color) {
	import std.math : sqrt;

	// TODO: line width
	// TODO: anti-aliasing (looks awful without it!)

	float deltaX = b.x - a.x;
	float deltaY = b.y - a.y;
	int steps = sqrt(deltaX * deltaX + deltaY * deltaY).castTo!int;

	float[2] step = [
		(deltaX / steps),
		(deltaY / steps),
	];

	foreach (i; 0 .. steps) {
		// dfmt off
		immutable Point p = a + Point(
			round(step[0] * i).castTo!int,
			round(step[1] * i).castTo!int,
		);
		// dfmt on

		immutable offset = linearOffset(p, target.width);
		target.data[offset] = color;
	}

	immutable offsetEnd = linearOffset(b, target.width);
	target.data[offsetEnd] = color;
}

/++
	Draws an image (a source pixmap) on a target pixmap

	Params:
		target = target pixmap to draw on
		image = source pixmap
		pos = top-left destination position (on the target pixmap)
 +/
void drawPixmap(Pixmap target, const Pixmap image, Point pos, Blend blend = blendNormal) {
	alias source = image;

	immutable tRect = OriginRectangle(
		Size(target.width, target.height),
	);

	immutable sRect = Rectangle(pos, source.size);

	// out of bounds?
	if (!tRect.intersect(sRect)) {
		return;
	}

	immutable drawingTarget = Point(
		(pos.x >= 0) ? pos.x : 0,
		(pos.y >= 0) ? pos.y : 0,
	);

	immutable drawingEnd = Point(
		(sRect.right < tRect.right) ? sRect.right : tRect.right,
		(sRect.bottom < tRect.bottom) ? sRect.bottom : tRect.bottom,
	);

	immutable drawingSource = Point(drawingTarget.x, 0) - Point(sRect.pos.x, sRect.pos.y);
	immutable int drawingWidth = drawingEnd.x - drawingTarget.x;

	foreach (y; drawingTarget.y .. drawingEnd.y) {
		blendPixels(
			target.sliceAt(Point(drawingTarget.x, y), drawingWidth),
			source.sliceAt(Point(drawingSource.x, y + drawingSource.y), drawingWidth),
			blend,
		);
	}
}

/++
	Draws an image (a subimage from a source pixmap) on a target pixmap

	Params:
		target = target pixmap to draw on
		image = source subpixmap
		pos = top-left destination position (on the target pixmap)
 +/
void drawPixmap(Pixmap target, const SubPixmap image, Point pos, Blend blend = blendNormal) {
	alias source = image;

	debug assert(source.isValid);

	immutable tRect = OriginRectangle(
		Size(target.width, target.height),
	);

	immutable sRect = Rectangle(pos, source.size);

	// out of bounds?
	if (!tRect.intersect(sRect)) {
		return;
	}

	Point sourceOffset = source.offset;
	Point drawingTarget;
	Size drawingSize = source.size;

	if (pos.x <= 0) {
		sourceOffset.x -= pos.x;
		drawingTarget.x = 0;
		drawingSize.width += pos.x;
	} else {
		drawingTarget.x = pos.x;
	}

	if (pos.y <= 0) {
		sourceOffset.y -= pos.y;
		drawingTarget.y = 0;
		drawingSize.height += pos.y;
	} else {
		drawingTarget.y = pos.y;
	}

	Point drawingEnd = drawingTarget + drawingSize.castTo!Point();
	if (drawingEnd.x >= source.width) {
		drawingSize.width -= (drawingEnd.x - source.width);
	}
	if (drawingEnd.y >= source.height) {
		drawingSize.height -= (drawingEnd.y - source.height);
	}

	auto dst = SubPixmap(target, drawingTarget, drawingSize);
	auto src = const(SubPixmap)(
		source.source,
		drawingSize,
		sourceOffset,
	);

	src.xferTo(dst, blend);
}

/++
	Draws a sprite from a spritesheet
 +/
void drawSprite(Pixmap target, const SpriteSheet sheet, int spriteIndex, Point pos, Blend blend = blendNormal) {
	immutable tRect = OriginRectangle(
		Size(target.width, target.height),
	);

	immutable spriteOffset = sheet.getSpritePixelOffset2D(spriteIndex);
	immutable sRect = Rectangle(pos, sheet.spriteSize);

	// out of bounds?
	if (!tRect.intersect(sRect)) {
		return;
	}

	immutable drawingTarget = Point(
		(pos.x >= 0) ? pos.x : 0,
		(pos.y >= 0) ? pos.y : 0,
	);

	immutable drawingEnd = Point(
		(sRect.right < tRect.right) ? sRect.right : tRect.right,
		(sRect.bottom < tRect.bottom) ? sRect.bottom : tRect.bottom,
	);

	immutable drawingSource =
		spriteOffset
		+ Point(drawingTarget.x, 0)
		- Point(sRect.pos.x, sRect.pos.y);
	immutable int drawingWidth = drawingEnd.x - drawingTarget.x;

	foreach (y; drawingTarget.y .. drawingEnd.y) {
		blendPixels(
			target.sliceAt(Point(drawingTarget.x, y), drawingWidth),
			sheet.pixmap.sliceAt(Point(drawingSource.x, y + drawingSource.y), drawingWidth),
			blend,
		);
	}
}
