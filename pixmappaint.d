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

	Pixmap refers to raster graphics, a subset of “bitmap” graphics.
	A pixmap is an array of pixels and the corresponding meta data to describe
	how an image if formed from those pixels.
	In the case of this library, a “width” field is used to map a specified
	number of pixels to a row of an image.




	### Pixel mapping

	```text
	pixels := [ 0, 1, 2, 3 ]
	width  := 2

	pixmap(pixels, width)
		=> [
			[ 0, 1 ]
			[ 2, 3 ]
		]
	```

	```text
	pixels := [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 ]
	width  := 3

	pixmap(pixels, width)
		=> [
			[ 0,  1,  2 ]
			[ 3,  4,  5 ]
			[ 6,  7,  8 ]
			[ 9, 10, 11 ]
		]
	```

	```text
	pixels := [ 0, 1, 2, 3, 4, 5, 6, 7 ]
	width  := 4

	pixmap(pixels, width)
		=> [
			[ 0, 1, 2, 3 ]
			[ 4, 5, 6, 7 ]
		]
	```




	### Colors

	Colors are stored in an RGBA format with 8 bit per channel.
	See [arsd.color.Color|Pixel] for details.


	### The coordinate system

	The top left corner of a pixmap is its $(B origin) `(0,0)`.

	The $(horizontal axis) is called `x`.
	Its corresponding length/dimension is known as `width`.

	The letter `y` is used to describe the $(B vertical axis).
	Its corresponding length/dimension is known as `height`.

	```
	0 → x
	↓
	y
	```

	Furthermore, $(B length) refers to the areal size of a pixmap.
	It represents the total number of pixels in a pixmap.
	It follows from the foregoing that the term $(I long) usually refers to
	the length (not the width).




	### Pixmaps

	A [Pixmap] consist of two fields:
	$(LIST
		* a slice (of an array of [Pixel|Pixels])
		* a width
	)

	This design comes with many advantages.
	First and foremost it brings simplicity.

	Pixel data buffers can be reused across pixmaps,
	even when those have different sizes.
	Simply slice the buffer to fit just enough pixels for the new pixmap.

	Memory management can also happen outside of the pixmap.
	It is possible to use a buffer allocated elsewhere. (Such a one shouldn’t
	be mixed with the built-in memory management facilities of the pixmap type.
	Otherwise one will end up with GC-allocated copies.)

	The most important downside is that it makes pixmaps basically a partial
	reference type.

	Copying a pixmap creates a shallow copy still poiting to the same pixel
	data that is also used by the source pixmap.
	This implies that manipulating the source pixels also manipulates the
	pixels of the copy – and vice versa.

	The issues implied by this become an apparent when one of the references
	modifies the pixel data in a way that also affects the dimensions of the
	image; such as cropping.

	Pixmaps describe how pixel data stored in a 1-dimensional memory space is
	meant to be interpreted as a 2-dimensional image.

	A notable implication of this 1D ↔ 2D mapping is, that slicing the 1D data
	leads to non-sensical results in the 2D space when the 1D-slice is
	reinterpreted as 2D-image.

	Especially slicing across scanlines (→ horizontal rows of an image) is
	prone to such errors.

	(Slicing of the 1D array data can actually be utilized to cut off the
	top or bottom part of an image. Any other naiv cropping operations will run
	into the aforementioned issues.)




	### Image manipulation

	The term “image manipulation function” here refers to functions that
	manipulate (e.g. transform) an image as a whole.

	Image manipulation functions in this library are provided in up to three
	flavors:

	$(LIST
		* a “source to target” function
		* a “source to newly allocated target” wrapper
		* $(I optionally) an “in-place” adaption
	)

	Additionally, a “compute dimensions of target” function is provided.


	#### Source to Target

	The regular “source to target” function takes (at least) two parameters:
	A source [Pixmap] and a target [Pixmap].

	(Additional operation-specific arguments may be required as well.)

	The target pixmap usually needs to be able to fit at least the same number
	of pixels as the source holds.
	Use the corresponding “compute size of target function” to calculate the
	required size when needed.
	(A notable exception would be cropping, where to target pixmap must be only
	at least long enough to hold the area of the size to crop to.)

	The data stored in the buffer of the target pixmap is overwritten by the
	operation.

	A modified Pixmap structure with adjusted dimensions is returned.

	These functions are named plain and simple after the respective operation
	they perform; e.g. [flipHorizontally] or [crop].

	---
	// Allocate a new target Pixmap.
	Pixmap target = Pixmap.makeNew(
		flipHorizontallyCalcDims(sourceImage)
	);

	// Flip the image horizontally and store the updated structure.
	// (Note: As a horizontal flip does not affect the dimensions of a Pixmap,
	//        storing the updated structure would not be necessary
	//        in this specific scenario.)
	target = sourceImage.flipHorizontally(target);
	---

	---
	const cropOffset = Point(0, 0);
	const cropSize = Size(100, 100);

	// Allocate a new target Pixmap.
	Pixmap target = Pixmap.makeNew(
		cropCalcDims(sourceImage, cropSize, cropOffset)
	);

	// Crop the Pixmap.
	target = sourceImage.crop(target, cropSize, cropOffset);
	---

	$(PITFALL
		“Source to target” functions do not work in place.
		Do not attempt to pass Pixmaps sharing the same buffer for both source
		and target. Such would lead to bad results with heavy artifacts.

		Use the “in-place” variant of the operation instead.

		Moreover:
		Do not use the artifacts produced by this as a creative effect.
		Those are an implementation detail (and may change at any point).
	)


	#### Source to New Target

	The “source to newly allocated target” wrapper allocates a new buffer to
	hold the manipulated target.

	These wrappers are provided for user convenience.

	They are identified by the suffix `-New` that is appended to the name of
	the corresponding “source to target” function;
	e.g. [flipHorizontallyNew] or [cropNew].

	---
	// Create a new flipped Pixmap.
	Pixmap target = sourceImage.flipHorizontallyNew();
	---

	---
	const cropOffset = Point(0, 0);
	const cropSize = Size(100, 100);

	// Create a new cropped Pixmap.
	Pixmap target = sourceImage.cropNew(cropSize, cropOffset);
	---


	#### In-Place

	For selected image manipulation functions a special adaption is provided
	that stores the result in the source pixel data buffer.

	Depending on the operation, implementing in-place transformations can be
	either straightforward or a major undertaking (and topic of research).
	This library focuses and the former case and leaves out those where the
	latter applies.
	In particular, algorithms that require allocating further buffers to store
	temporary results or auxiliary data will probably not get implemented.

	Furthermore, operations where to result is larger than the source cannot
	be performed in-place.

	Certain in-place manipulation functions return a shallow-copy of the
	source structure with dimensions adjusted accordingly.
	This is behavior is not streamlined consistently as the lack of an
	in-place option for certain operations makes them a special case anyway.

	These function are suffixed with `-InPlace`;
	e.g. [flipHorizontallyInPlace] or [cropInPlace].

	$(TIP
		Manipulating the source image directly can lead to unexpected results
		when the source image is used in multiple places.
	)

	$(NOTE
		Users are usually better off to utilize the regular “source to target”
		functions with a reused pixel data buffer.

		These functions do not serve as a performance optimization.
		Some of them might perform significantly worse than their regular
		variant. Always benchmark and profile.
	)

	---
	image.flipHorizontallyInPlace();
	---

	---
	const cropOffset = Point(0, 0);
	const cropSize = Size(100, 100);

	image = image.cropInPlace(cropSize, cropOffset);
	---


	#### Compute size of target

	Functions to “compute (the) dimensions of (a) target” are primarily meant
	to be utilized to calculate the size for allocating new pixmaps to be used
	as a target for manipulation functions.

	They are provided for all manipulation functions even in cases where they
	are provide little to no benefit. This is for consistency and to ease
	development.

	Such functions are identified by a `-CalcDims` suffix;
	e.g. [flipHorizontallyCalcDims] or [cropCalcDims].

	They usually take the same parameters as their corresponding
	“source to new target” function. This does not apply in cases where
	certain parameters are irrelevant for the computation of the target size.
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
// → <https://issues.dlang.org/show_bug.cgi?id=11320>
private float round(float f) pure @nogc nothrow @trusted {
	return (castTo!(float function(float) pure @nogc nothrow)(&roundImpl))(f);
}

/*
	## TODO:

	- Refactoring the template-mess of blendPixel() & co.
	- Rotating (by arbitrary angles)
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
	Pixel rgba(ubyte r, ubyte g, ubyte b, float aPct) {
		return Pixel(r, g, b, percentageDecimalToUInt8(aPct));
	}

	///
	Pixel rgb(ubyte r, ubyte g, ubyte b) {
		return rgba(r, g, b, 0xFF);
	}
}

/++
	Unsigned 64-bit fixed-point decimal type

	Assigns 32 bits to the digits of the pre-decimal point portion
	and the other 32 bits to fractional digits.
 +/
struct UDecimal {
	private {
		ulong _value = 0;
	}

@safe pure nothrow @nogc:

	///
	public this(uint initialValue) {
		_value = (ulong(initialValue) << 32);
	}

	private static UDecimal make(ulong internal) {
		auto result = UDecimal();
		result._value = internal;
		return result;
	}

	///
	T opCast(T : uint)() const {
		return (_value >> 32).castTo!uint;
	}

	///
	T opCast(T : double)() const {
		return (_value / double(0xFFFF_FFFF));
	}

	///
	T opCast(T : float)() const {
		return (_value / float(0xFFFF_FFFF));
	}

	///
	public UDecimal round() const {
		const truncated = (_value & 0xFFFF_FFFF_0000_0000);
		const delta = _value - truncated;

		// dfmt off
		const rounded = (delta >= 0x8000_0000)
			? truncated + 0x1_0000_0000
			: truncated;
		// dfmt on

		return UDecimal.make(rounded);
	}

	///
	public UDecimal roundEven() const {
		const truncated = (_value & 0xFFFF_FFFF_0000_0000);
		const delta = _value - truncated;

		ulong rounded;

		if (delta == 0x8000_0000) {
			const bool floorIsOdd = ((truncated & 0x1_0000_0000) != 0);
			// dfmt off
			rounded = (floorIsOdd)
				? truncated + 0x1_0000_0000 // ceil
				: truncated;                // floor
			// dfmt on
		} else if (delta > 0x8000_0000) {
			rounded = truncated + 0x1_0000_0000;
		} else {
			rounded = truncated;
		}

		return UDecimal.make(rounded);
	}

	///
	public UDecimal floor() const {
		const truncated = (_value & 0xFFFF_FFFF_0000_0000);
		return UDecimal.make(truncated);
	}

	///
	public UDecimal ceil() const {
		const truncated = (_value & 0xFFFF_FFFF_0000_0000);

		// dfmt off
		const ceiling = (truncated != _value)
			? truncated + 0x1_0000_0000
			: truncated;
		// dfmt on

		return UDecimal.make(ceiling);
	}

	///
	public uint fractionalDigits() const {
		return (_value & 0x0000_0000_FFFF_FFFF);
	}

	public {
		///
		int opCmp(const UDecimal that) const {
			return ((this._value > that._value) - (this._value < that._value));
		}
	}

	public {
		///
		UDecimal opBinary(string op : "+")(const uint rhs) const {
			return UDecimal.make(_value + (ulong(rhs) << 32));
		}

		/// ditto
		UDecimal opBinary(string op : "+")(const UDecimal rhs) const {
			return UDecimal.make(_value + rhs._value);
		}

		/// ditto
		UDecimal opBinary(string op : "-")(const uint rhs) const {
			return UDecimal.make(_value - (ulong(rhs) << 32));
		}

		/// ditto
		UDecimal opBinary(string op : "-")(const UDecimal rhs) const {
			return UDecimal.make(_value - rhs._value);
		}

		/// ditto
		UDecimal opBinary(string op : "*")(const uint rhs) const {
			return UDecimal.make(_value * rhs);
		}

		/// ditto
		UDecimal opBinary(string op : "/")(const uint rhs) const {
			return UDecimal.make(_value / rhs);
		}

		/// ditto
		UDecimal opBinary(string op : "<<")(const uint rhs) const {
			return UDecimal.make(_value << rhs);
		}

		/// ditto
		UDecimal opBinary(string op : ">>")(const uint rhs) const {
			return UDecimal.make(_value >> rhs);
		}
	}

	public {
		///
		UDecimal opBinaryRight(string op : "+")(const uint lhs) const {
			return UDecimal.make((ulong(lhs) << 32) + _value);
		}

		/// ditto
		UDecimal opBinaryRight(string op : "-")(const uint lhs) const {
			return UDecimal.make((ulong(lhs) << 32) - _value);
		}

		/// ditto
		UDecimal opBinaryRight(string op : "*")(const uint lhs) const {
			return UDecimal.make(lhs * _value);
		}

		/// ditto
		UDecimal opBinaryRight(string op : "/")(const uint) const {
			static assert(false, "Use `uint(…) / cast(uint)(UDecimal(…))` instead.");
		}
	}

	public {
		///
		UDecimal opOpAssign(string op : "+")(const uint rhs) {
			_value += (ulong(rhs) << 32);
			return this;
		}

		/// ditto
		UDecimal opOpAssign(string op : "+")(const UDecimal rhs) {
			_value += rhs._value;
			return this;
		}

		/// ditto
		UDecimal opOpAssign(string op : "-")(const uint rhs) {
			_value -= (ulong(rhs) << 32);
			return this;
		}

		/// ditto
		UDecimal opOpAssign(string op : "-")(const UDecimal rhs) {
			_value -= rhs._value;
			return this;
		}

		/// ditto
		UDecimal opOpAssign(string op : "*")(const uint rhs) {
			_value *= rhs;
			return this;
		}

		/// ditto
		UDecimal opOpAssign(string op : "/")(const uint rhs) {
			_value /= rhs;
			return this;
		}

		/// ditto
		UDecimal opOpAssign(string op : "<<")(const uint rhs) const {
			_value <<= rhs;
			return this;
		}

		/// ditto
		UDecimal opOpAssign(string op : ">>")(const uint rhs) const {
			_value >>= rhs;
			return this;
		}
	}
}

@safe unittest {
	assert(UDecimal(uint.max).castTo!uint == uint.max);
	assert(UDecimal(uint.min).castTo!uint == uint.min);
	assert(UDecimal(1).castTo!uint == 1);
	assert(UDecimal(2).castTo!uint == 2);
	assert(UDecimal(1_991_007).castTo!uint == 1_991_007);

	assert((UDecimal(10) + 9).castTo!uint == 19);
	assert((UDecimal(10) - 9).castTo!uint == 1);
	assert((UDecimal(10) * 9).castTo!uint == 90);
	assert((UDecimal(99) / 9).castTo!uint == 11);

	assert((4 + UDecimal(4)).castTo!uint == 8);
	assert((4 - UDecimal(4)).castTo!uint == 0);
	assert((4 * UDecimal(4)).castTo!uint == 16);

	assert((UDecimal(uint.max) / 2).castTo!uint == 2_147_483_647);
	assert((UDecimal(uint.max) / 2).round().castTo!uint == 2_147_483_648);

	assert((UDecimal(10) / 8).round().castTo!uint == 1);
	assert((UDecimal(10) / 8).floor().castTo!uint == 1);
	assert((UDecimal(10) / 8).ceil().castTo!uint == 2);

	assert((UDecimal(10) / 4).round().castTo!uint == 3);
	assert((UDecimal(10) / 4).floor().castTo!uint == 2);
	assert((UDecimal(10) / 4).ceil().castTo!uint == 3);

	assert((UDecimal(10) / 5).round().castTo!uint == 2);
	assert((UDecimal(10) / 5).floor().castTo!uint == 2);
	assert((UDecimal(10) / 5).ceil().castTo!uint == 2);
}

@safe unittest {
	UDecimal val;

	val = (UDecimal(1) / 2);
	assert(val.roundEven().castTo!uint == 0);
	assert(val.castTo!double > 0.49);
	assert(val.castTo!double < 0.51);

	val = (UDecimal(3) / 2);
	assert(val.roundEven().castTo!uint == 2);
	assert(val.castTo!double > 1.49);
	assert(val.castTo!double < 1.51);
}

@safe unittest {
	UDecimal val;

	val = UDecimal(10);
	val += 12;
	assert(val.castTo!uint == 22);

	val = UDecimal(1024);
	val -= 24;
	assert(val.castTo!uint == 1000);
	val -= 100;
	assert(val.castTo!uint == 900);
	val += 5;
	assert(val.castTo!uint == 905);

	val = UDecimal(256);
	val *= 4;
	assert(val.castTo!uint == (256 * 4));

	val = UDecimal(2048);
	val /= 10;
	val *= 10;
	assert(val.castTo!uint == 2047);
}

@safe unittest {
	UDecimal val;

	val = UDecimal(9_000_000);
	val /= 13;
	val *= 4;

	// ≈ 2,769,230.8
	assert(val.castTo!uint == 2_769_230);
	assert(val.round().castTo!uint == 2_769_231);
	// assert(uint(9_000_000) / uint(13) * uint(4) == 2_769_228);

	val = UDecimal(64);
	val /= 31;
	val *= 30;
	val /= 29;
	val *= 28;

	// ≈ 59.8
	assert(val.castTo!uint == 59);
	assert(val.round().castTo!uint == 60);
	// assert(((((64 / 31) * 30) / 29) * 28) == 56);
}

/++
	$(I Advanced functionality.)

	Meta data for the construction of a Pixmap.
 +/
struct PixmapBlueprint {
	/++
		Total number of pixels stored in a Pixmap.
	 +/
	size_t length;

	/++
		Width of a Pixmap.
	 +/
	int width;

@safe pure nothrow @nogc:

	///
	public static PixmapBlueprint fromSize(const Size size) {
		return PixmapBlueprint(
			size.area,
			size.width,
		);
	}

	///
	public static PixmapBlueprint fromPixmap(const Pixmap pixmap) {
		return PixmapBlueprint(
			pixmap.length,
			pixmap.width,
		);
	}

	/++
		Determines whether the blueprint is plausible.
	 +/
	bool isValid() const {
		return ((length % width) == 0);
	}

	/++
		Height of a Pixmap.

		See_also:
			This is the counterpart to the dimension known as [width].
	 +/
	int height() const {
		return castTo!int(length / width);
	}

	///
	Size size() const {
		return Size(width, height);
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
	deprecated("Use `Pixmap.makeNew(size)` instead.")
	this(Size size) {
		this.size = size;
	}

	///
	deprecated("Use `Pixmap.makeNew(Size(width, height))` instead.")
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

	///
	static Pixmap makeNew(PixmapBlueprint blueprint) {
		auto data = new Pixel[](blueprint.length);
		return Pixmap(data, blueprint.width);
	}

	///
	static Pixmap makeNew(Size size) {
		return Pixmap.makeNew(PixmapBlueprint.fromSize(size));
	}

	/++
		Creates a $(I deep copy) of the Pixmap
	 +/
	Pixmap clone() const {
		return Pixmap(
			this.data.dup,
			this.width,
		);
	}

	/++
		Copies the pixel data to the target Pixmap.

		Returns:
			A size-adjusted shallow copy of the input Pixmap overwritten
			with the image data of the SubPixmap.

		$(PITFALL
			While the returned Pixmap utilizes the buffer provided by the input,
			the returned Pixmap might not exactly match the input.

			Always use the returned Pixmap structure.

			---
			// Same buffer, but new structure:
			auto pixmap2 = source.copyTo(pixmap);

			// Alternatively, replace the old structure:
			pixmap = source.copyTo(pixmap);
			---
		)
	 +/
	Pixmap copyTo(Pixmap target) @nogc const {
		// Length adjustment
		const l = this.length;
		if (target.data.length < l) {
			assert(false, "The target Pixmap is too small.");
		} else if (target.data.length > l) {
			target.data = target.data[0 .. l];
		}

		copyToImpl(target);

		return target;
	}

	private void copyToImpl(Pixmap target) @nogc const {
		target.data[] = this.data[];
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
		Adjusts the Pixmap according to the provided blueprint.

		The blueprint must not be larger than the data buffer of the pixmap.

		This function does not reallocate the pixel data buffer.

		If the blueprint is larger than the data buffer of the pixmap,
		this will result in a bounds-check error if applicable.
	 +/
	void adjustTo(PixmapBlueprint blueprint) {
		debug assert(this.data.length >= blueprint.length);
		debug assert(blueprint.isValid);
		this.data = this.data[0 .. blueprint.length];
		this.width = blueprint.width;
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
	inout(SubPixmap) scanArea(Point pos, Size size) inout {
		return inout(SubPixmap)(this, size, pos);
	}

	/// TODO: remove
	deprecated alias scanSubPixmap = scanArea;

	/// TODO: remove
	deprecated alias scan2D = scanArea;

	/++
		Retrieves the first line of the Pixmap.

		See_also:
			Check out [PixmapScanner] for more useful scanning functionality.
	 +/
	inout(Pixel)[] scanLine() inout {
		return data[0 .. width];
	}

	public {
		/++
			Provides access to a single pixel at the requested 2D-position.

			See_also:
				Accessing pixels through the [data] array will be more useful,
				usually.
		 +/
		ref inout(Pixel) accessPixel(Point pos) inout @system {
			const idx = linearOffset(pos, this.width);
			return this.data[idx];
		}

		/// ditto
		Pixel getPixel(Point pos) const {
			const idx = linearOffset(pos, this.width);
			return this.data[idx];
		}

		/// ditto
		Pixel getPixel(int x, int y) const {
			return this.getPixel(Point(x, y));
		}

		/// ditto
		void setPixel(Point pos, Pixel value) {
			const idx = linearOffset(pos, this.width);
			this.data[idx] = value;
		}

		/// ditto
		void setPixel(int x, int y, Pixel value) {
			return this.setPixel(Point(x, y), value);
		}
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

@safe pure nothrow:

	public {
		/++
			Allocates a new Pixmap cropped to the pixel data of the subimage.

			See_also:
				Use [extractToPixmap] for a non-allocating variant with a
				target parameter.
		 +/
		Pixmap extractToNewPixmap() const {
			auto pm = Pixmap.makeNew(size);
			this.extractToPixmap(pm);
			return pm;
		}

		/++
			Copies the pixel data – cropped to the subimage region –
			into the target Pixmap.

			$(PITFALL
				Do not attempt to extract a subimage back into the source pixmap.
				This will fail in cases where source and target regions overlap
				and potentially crash the program.
			)

			Returns:
				A size-adjusted shallow copy of the input Pixmap overwritten
				with the image data of the SubPixmap.

			$(PITFALL
				While the returned Pixmap utilizes the buffer provided by the input,
				the returned Pixmap might not exactly match the input.
				The dimensions (width and height) and the length might have changed.

				Always use the returned Pixmap structure.

				---
				// Same buffer, but new structure:
				auto pixmap2 = subPixmap.extractToPixmap(pixmap);

				// Alternatively, replace the old structure:
				pixmap = subPixmap.extractToPixmap(pixmap);
				---
			)
		 +/
		Pixmap extractToPixmap(Pixmap target) @nogc const {
			// Length adjustment
			const l = this.length;
			if (target.data.length < l) {
				assert(false, "The target Pixmap is too small.");
			} else if (target.data.length > l) {
				target.data = target.data[0 .. l];
			}

			target.width = this.width;

			extractToPixmapCopyImpl(target);
			return target;
		}

		private void extractToPixmapCopyImpl(Pixmap target) @nogc const {
			auto src = SubPixmapScanner(this);
			auto dst = PixmapScannerRW(target);

			foreach (dstLine; dst) {
				dstLine[] = src.front[];
				src.popFront();
			}
		}

		private void extractToPixmapCopyPixelByPixelImpl(Pixmap target) @nogc const {
			auto src = SubPixmapScanner(this);
			auto dst = PixmapScannerRW(target);

			foreach (dstLine; dst) {
				const srcLine = src.front;
				foreach (idx, ref px; dstLine) {
					px = srcLine[idx];
				}
				src.popFront();
			}
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

		/// ditto
		void height(int value) {
			size.height = value;
		}

		/++
			Number of pixels in the subimage.
		 +/
		int length() const {
			return size.area;
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

			Offset of the pixel following the bottom right corner of the subimage.

			(`Point(O, 0)` is the top left corner of the source image.)
		 +/
		Point sourceOffsetEnd() const {
			auto vec = Point(size.width, (size.height - 1));
			return (offset + vec);
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

		$(WARNING
			Do not use invalid SubPixmaps.
			The library assumes that the SubPixmaps it receives are always valid.

			Non-valid SubPixmaps are not meant to be used for creative effects
			or similar either. Such uses might lead to unexpected quirks or
			crashes eventually.
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

	/++
		Copies the pixels of this subimage to a target image.

		The target MUST have the same size.

		See_also:
			Usually you’ll want to use [extractToPixmap] or [drawPixmap] instead.
	 +/
	public void xferTo(SubPixmap target) const {
		debug assert(target.size == this.size);

		auto src = SubPixmapScanner(this);
		auto dst = SubPixmapScannerRW(target);

		foreach (dstLine; dst) {
			dstLine[] = src.front[];
			src.popFront();
		}
	}

	/++
		Blends the pixels of this subimage into a target image.

		The target MUST have the same size.

		See_also:
			Usually you’ll want to use [extractToPixmap] or [drawPixmap] instead.
	 +/
	public void xferTo(SubPixmap target, Blend blend) const {
		debug assert(target.size == this.size);

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
			return linearOffset(pos, source.width);
		}
	}
}

/++
	$(I Advanced functionality.)

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
	typeof(this) save() {
		return this;
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

	///
	const(Pixel)[] back() const {
		return _data[($ - _width) .. $];
	}

	///
	void popBack() {
		_data = _data[0 .. ($ - _width)];
	}
}

/++
	$(I Advanced functionality.)

	Wrapper for scanning a [Pixmap] line by line.

	See_also:
		Unlike [PixmapScanner], this does not work with `const(Pixmap)`.
 +/
struct PixmapScannerRW {
	private {
		Pixel[] _data;
		int _width;
	}

@safe pure nothrow @nogc:

	///
	public this(Pixmap pixmap) {
		_data = pixmap.data;
		_width = pixmap.width;
	}

	///
	typeof(this) save() {
		return this;
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
		_data = _data[_width .. $];
	}

	///
	Pixel[] back() {
		return _data[($ - _width) .. $];
	}

	///
	void popBack() {
		_data = _data[0 .. ($ - _width)];
	}
}

/++
	$(I Advanced functionality.)

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
	typeof(this) save() {
		return this;
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

	///
	const(Pixel)[] back() const {
		return _data[($ - _width) .. $];
	}

	///
	void popBack() {
		if (_data.length < _feed) {
			_data.length = 0;
			return;
		}

		_data = _data[0 .. ($ - _feed)];
	}
}

/++
	$(I Advanced functionality.)

	Wrapper for scanning a [Pixmap] line by line.

	See_also:
		Unlike [SubPixmapScanner], this does not work with `const(SubPixmap)`.
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
	typeof(this) save() {
		return this;
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

	///
	Pixel[] back() {
		return _data[($ - _width) .. $];
	}

	///
	void popBack() {
		if (_data.length < _feed) {
			_data.length = 0;
			return;
		}

		_data = _data[0 .. ($ - _feed)];
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

@safe pure nothrow:

// misc
private @nogc {
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
ubyte intNormalizedSqrt(const ubyte value) @nogc {
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
ubyte clamp255(Tint)(const Tint value) @nogc {
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
ubyte n255thsOf(const ubyte nPercentage, const ubyte value) @nogc {
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

///
ubyte percentageDecimalToUInt8(const float decimal) @nogc
in (decimal >= 0)
in (decimal <= 1) {
	return round(decimal * 255).castTo!ubyte;
}

///
float percentageUInt8ToDecimal(const ubyte n255ths) @nogc {
	return (float(n255ths) / 255.0f);
}

// ==== Image manipulation functions ====

/++
	Lowers the opacity of a Pixel.

	This function multiplies the opacity of the input
	with the given percentage.

	See_Also:
		Use [decreaseOpacityF] with decimal opacity values in percent (%).
 +/
Pixel decreaseOpacity(const Pixel source, ubyte opacityPercentage) @nogc {
	return Pixel(
		source.r,
		source.g,
		source.b,
		opacityPercentage.n255thsOf(source.a),
	);
}

/++
	Lowers the opacity of a Pixel.

	This function multiplies the opacity of the input
	with the given percentage.

	Value Range:
		0.0 =   0%
		1.0 = 100%

	See_Also:
		Use [opacity] with 8-bit integer opacity values (in 255ths).
 +/
Pixel decreaseOpacityF(const Pixel source, float opacityPercentage) @nogc {
	return decreaseOpacity(source, percentageDecimalToUInt8(opacityPercentage));
}

// Don’t get fooled by the name of this function.
// It’s called like that for consistency reasons.
private void decreaseOpacityInto(const Pixmap source, Pixmap target, ubyte opacityPercentage) @trusted @nogc {
	debug assert(source.data.length == target.data.length);
	foreach (idx, ref px; target.data) {
		px = decreaseOpacity(source.data.ptr[idx], opacityPercentage);
	}
}

/++
	Lowers the opacity of a [Pixmap].

	This operation updates the alpha-channel value of each pixel.
	→ `alpha *= opacity`

	See_Also:
		Use [decreaseOpacityF] with decimal opacity values in percent (%).
 +/
Pixmap decreaseOpacity(const Pixmap source, Pixmap target, ubyte opacityPercentage) @nogc {
	target.adjustTo(source.decreaseOpacityCalcDims());
	source.decreaseOpacityInto(target, opacityPercentage);
	return target;
}

/// ditto
Pixmap decreaseOpacityNew(const Pixmap source, ubyte opacityPercentage) {
	auto target = Pixmap.makeNew(source.decreaseOpacityCalcDims());
	source.decreaseOpacityInto(target, opacityPercentage);
	return target;
}

/// ditto
void decreaseOpacityInPlace(Pixmap source, ubyte opacityPercentage) @nogc {
	foreach (ref px; source.data) {
		px.a = opacityPercentage.n255thsOf(px.a);
	}
}

/// ditto
PixmapBlueprint decreaseOpacityCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint.fromPixmap(source);
}

/++
	Adjusts the opacity of a [Pixmap].

	This operation updates the alpha-channel value of each pixel.
	→ `alpha *= opacity`

	See_Also:
		Use [decreaseOpacity] with 8-bit integer opacity values (in 255ths).
 +/
Pixmap decreaseOpacityF(const Pixmap source, Pixmap target, float opacityPercentage) @nogc {
	return source.decreaseOpacity(target, percentageDecimalToUInt8(opacityPercentage));
}

/// ditto
Pixmap decreaseOpacityFNew(const Pixmap source, float opacityPercentage) {
	return source.decreaseOpacityNew(percentageDecimalToUInt8(opacityPercentage));
}

/// ditto
void decreaseOpacityFInPlace(Pixmap source, float opacityPercentage) @nogc {
	return source.decreaseOpacityInPlace(percentageDecimalToUInt8(opacityPercentage));
}

/// ditto
PixmapBlueprint decreaseOpacityF(Pixmap source) @nogc {
	return PixmapBlueprint.fromPixmap(source);
}

/++
	Inverts a color (to its negative color).
 +/
Pixel invert(const Pixel color) @nogc {
	return Pixel(
		0xFF - color.r,
		0xFF - color.g,
		0xFF - color.b,
		color.a,
	);
}

private void invertInto(const Pixmap source, Pixmap target) @trusted @nogc {
	debug assert(source.length == target.length);
	foreach (idx, ref px; target.data) {
		px = invert(source.data.ptr[idx]);
	}
}

/++
	Inverts all colors to produce a $(I negative image).

	$(TIP
		Develops a positive image when applied to a negative one.
	)
 +/
Pixmap invert(const Pixmap source, Pixmap target) @nogc {
	target.adjustTo(source.invertCalcDims());
	source.invertInto(target);
	return target;
}

/// ditto
Pixmap invertNew(const Pixmap source) {
	auto target = Pixmap.makeNew(source.invertCalcDims());
	source.invertInto(target);
	return target;
}

/// ditto
void invertInPlace(Pixmap pixmap) @nogc {
	foreach (ref px; pixmap.data) {
		px = invert(px);
	}
}

/// ditto
PixmapBlueprint invertCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint.fromPixmap(source);
}

/++
	Crops an image and stores the result in the provided target Pixmap.

	The size of the area to crop the image to
	is derived from the size of the target.

	---
	// This function can be used to omit a redundant size parameter
	// in cases like this:
	target = crop(source, target, target.size, offset);

	// → Instead do:
	cropTo(source, target, offset);
	---
 +/
void cropTo(const Pixmap source, Pixmap target, Point offset = Point(0, 0)) @nogc {
	auto src = const(SubPixmap)(source, target.size, offset);
	src.extractToPixmapCopyImpl(target);
}

// consistency
private alias cropInto = cropTo;

/++
	Crops an image to the provided size with the requested offset.

	The target Pixmap must be big enough in length to hold the cropped image.
 +/
Pixmap crop(const Pixmap source, Pixmap target, Size cropToSize, Point offset = Point(0, 0)) @nogc {
	target.adjustTo(cropCalcDims(cropToSize));
	cropInto(source, target, offset);
	return target;
}

/// ditto
Pixmap cropNew(const Pixmap source, Size cropToSize, Point offset = Point(0, 0)) {
	auto target = Pixmap.makeNew(cropToSize);
	cropInto(source, target, offset);
	return target;
}

/// ditto
Pixmap cropInPlace(Pixmap source, Size cropToSize, Point offset = Point(0, 0)) @nogc {
	Pixmap target = source;
	target.width = cropToSize.width;
	target.data = target.data[0 .. cropToSize.area];

	auto src = const(SubPixmap)(source, cropToSize, offset);
	src.extractToPixmapCopyPixelByPixelImpl(target);
	return target;
}

/// ditto
PixmapBlueprint cropCalcDims(Size cropToSize) @nogc {
	return PixmapBlueprint.fromSize(cropToSize);
}

private void transposeInto(const Pixmap source, Pixmap target) @nogc {
	foreach (y; 0 .. target.width) {
		foreach (x; 0 .. source.width) {
			const idxSrc = linearOffset(Point(x, y), source.width);
			const idxDst = linearOffset(Point(y, x), target.width);

			target.data[idxDst] = source.data[idxSrc];
		}
	}
}

/++
	Transposes an image.

	```
	╔══╗   ╔══╗
	║# ║   ║#+║
	║+x║ → ║ x║
	╚══╝   ╚══╝
	```
 +/
Pixmap transpose(const Pixmap source, Pixmap target) @nogc {
	target.adjustTo(source.transposeCalcDims());
	source.transposeInto(target);
	return target;
}

/// ditto
Pixmap transposeNew(const Pixmap source) {
	auto target = Pixmap.makeNew(source.transposeCalcDims());
	source.transposeInto(target);
	return target;
}

/// ditto
PixmapBlueprint transposeCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint(source.length, source.height);
}

private void rotateClockwiseInto(const Pixmap source, Pixmap target) @nogc {
	const area = source.data.length;
	const rowLength = source.size.height;
	ptrdiff_t cursor = -1;

	foreach (px; source.data) {
		cursor += rowLength;
		if (cursor > area) {
			cursor -= (area + 1);
		}

		target.data[cursor] = px;
	}
}

/++
	Rotates an image by 90° clockwise.

	```
	╔══╗   ╔══╗
	║# ║   ║+#║
	║+x║ → ║x ║
	╚══╝   ╚══╝
	```
 +/
Pixmap rotateClockwise(const Pixmap source, Pixmap target) @nogc {
	target.adjustTo(source.rotateClockwiseCalcDims());
	source.rotateClockwiseInto(target);
	return target;
}

/// ditto
Pixmap rotateClockwiseNew(const Pixmap source) {
	auto target = Pixmap.makeNew(source.rotateClockwiseCalcDims());
	source.rotateClockwiseInto(target);
	return target;
}

/// ditto
PixmapBlueprint rotateClockwiseCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint(source.length, source.height);
}

private void rotateCounterClockwiseInto(const Pixmap source, Pixmap target) @nogc {
	// TODO: can this be optimized?
	target = transpose(source, target);
	target.flipVerticallyInPlace();
}

/++
	Rotates an image by 90° counter-clockwise.

	```
	╔══╗   ╔══╗
	║# ║   ║ x║
	║+x║ → ║#+║
	╚══╝   ╚══╝
	```
 +/
Pixmap rotateCounterClockwise(const Pixmap source, Pixmap target) @nogc {
	target.adjustTo(source.rotateCounterClockwiseCalcDims());
	source.rotateCounterClockwiseInto(target);
	return target;
}

/// ditto
Pixmap rotateCounterClockwiseNew(const Pixmap source) {
	auto target = Pixmap.makeNew(source.rotateCounterClockwiseCalcDims());
	source.rotateCounterClockwiseInto(target);
	return target;
}

/// ditto
PixmapBlueprint rotateCounterClockwiseCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint(source.length, source.height);
}

private void rotate180degInto(const Pixmap source, Pixmap target) @nogc {
	// Technically, this is implemented as flip vertical + flip horizontal.
	auto src = PixmapScanner(source);
	auto dst = PixmapScannerRW(target);

	foreach (srcLine; src) {
		auto dstLine = dst.back;
		foreach (idxSrc, px; srcLine) {
			const idxDst = (dstLine.length - (idxSrc + 1));
			dstLine[idxDst] = px;
		}
		dst.popBack();
	}
}

/++
	Rotates an image by 180°.

	```
	╔═══╗   ╔═══╗
	║#- ║   ║%~~║
	║~~%║ → ║ -#║
	╚═══╝   ╚═══╝
	```
 +/
Pixmap rotate180deg(const Pixmap source, Pixmap target) @nogc {
	target.adjustTo(source.rotate180degCalcDims());
	source.rotate180degInto(target);
	return target;
}

/// ditto
Pixmap rotate180degNew(const Pixmap source) {
	auto target = Pixmap.makeNew(source.size);
	source.rotate180degInto(target);
	return target;
}

/// ditto
void rotate180degInPlace(Pixmap source) @nogc {
	auto scanner = PixmapScannerRW(source);

	// Technically, this is implemented as a flip vertical + flip horizontal
	// combo, i.e. the image is flipped vertically line by line, but the lines
	// are overwritten in a horizontally flipped way.
	while (!scanner.empty) {
		auto a = scanner.front;
		auto b = scanner.back;

		// middle line? (odd number of lines)
		if (a.ptr is b.ptr) {
			break;
		}

		foreach (idxSrc, ref pxA; a) {
			const idxDst = (b.length - (idxSrc + 1));
			const tmp = pxA;
			pxA = b[idxDst];
			b[idxDst] = tmp;
		}

		scanner.popFront();
		scanner.popBack();
	}
}

///
PixmapBlueprint rotate180degCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint.fromPixmap(source);
}

private void flipHorizontallyInto(const Pixmap source, Pixmap target) @nogc {
	auto src = PixmapScanner(source);
	auto dst = PixmapScannerRW(target);

	foreach (srcLine; src) {
		auto dstLine = dst.front;
		foreach (idxSrc, px; srcLine) {
			const idxDst = (dstLine.length - (idxSrc + 1));
			dstLine[idxDst] = px;
		}

		dst.popFront();
	}
}

/++
	Flips an image horizontally.

	```
	╔═══╗   ╔═══╗
	║#-.║ → ║.-#║
	╚═══╝   ╚═══╝
	```
 +/
Pixmap flipHorizontally(const Pixmap source, Pixmap target) @nogc {
	target.adjustTo(source.flipHorizontallyCalcDims());
	source.flipHorizontallyInto(target);
	return target;
}

/// ditto
Pixmap flipHorizontallyNew(const Pixmap source) {
	auto target = Pixmap.makeNew(source.size);
	source.flipHorizontallyInto(target);
	return target;
}

/// ditto
void flipHorizontallyInPlace(Pixmap source) @nogc {
	auto scanner = PixmapScannerRW(source);

	foreach (line; scanner) {
		const idxMiddle = (1 + (line.length >> 1));
		auto halfA = line[0 .. idxMiddle];

		foreach (idxA, ref px; halfA) {
			const idxB = (line.length - (idxA + 1));
			const tmp = line[idxB];
			// swap
			line[idxB] = px;
			px = tmp;
		}
	}
}

/// ditto
PixmapBlueprint flipHorizontallyCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint.fromPixmap(source);
}

private void flipVerticallyInto(const Pixmap source, Pixmap target) @nogc {
	auto src = PixmapScanner(source);
	auto dst = PixmapScannerRW(target);

	foreach (srcLine; src) {
		dst.back[] = srcLine[];
		dst.popBack();
	}
}

/++
	Flips an image vertically.

	```
	╔═══╗   ╔═══╗
	║## ║   ║  -║
	║  -║ → ║## ║
	╚═══╝   ╚═══╝
	```
 +/
Pixmap flipVertically(const Pixmap source, Pixmap target) @nogc {
	target.adjustTo(source.flipVerticallyCalcDims());
	source.flipVerticallyInto(target);
	return target;
}

/// ditto
Pixmap flipVerticallyNew(const Pixmap source) {
	auto target = Pixmap.makeNew(source.flipVerticallyCalcDims());
	source.flipVerticallyInto(target);
	return target;
}

/// ditto
void flipVerticallyInPlace(Pixmap source) @nogc {
	auto scanner = PixmapScannerRW(source);

	while (!scanner.empty) {
		auto a = scanner.front;
		auto b = scanner.back;

		// middle line? (odd number of lines)
		if (a.ptr is b.ptr) {
			break;
		}

		foreach (idx, ref pxA; a) {
			const tmp = pxA;
			pxA = b[idx];
			b[idx] = tmp;
		}

		scanner.popFront();
		scanner.popBack();
	}
}

/// ditto
PixmapBlueprint flipVerticallyCalcDims(const Pixmap source) @nogc {
	return PixmapBlueprint.fromPixmap(source);
}

/++
	Interpolation methods to apply when scaling images

	Each filter has its own distinctive properties.

	$(TIP
		Bilinear filtering (`linear`) is general-purpose.
		Works well with photos.

		For pixel graphics the retro look of `nearest` (as
		in $(I nearest neighbor)) is usually the option of choice.
	)

	$(NOTE
		When used as a parameter, it shall be understood as a hint.

		Implementations are not required to support all enumerated options
		and may pick a different filter as a substitute at their own discretion.
	)
 +/
enum ScalingFilter {
	/++
		Nearest neighbor interpolation

		Also known as $(B proximal interpolation)
		and $(B point sampling).

		$(TIP
			Visual impression: “blocky”, “pixelated”, “slightly displaced”
		)
	 +/
	nearest,

	/++
		Bilinear interpolation

		(Uses arithmetic mean for downscaling.)

		$(TIP
			Visual impression: “smooth”, “blurred”
		)
	 +/
	bilinear,

	///
	linear = bilinear,
}

private enum ScalingDirection {
	none,
	up,
	down,
}

private static ScalingDirection scalingDirectionFromDelta(const int delta) @nogc {
	if (delta == 0) {
		return ScalingDirection.none;
	} else if (delta > 0) {
		return ScalingDirection.up;
	} else {
		return ScalingDirection.down;
	}
}

private void scaleToImpl(ScalingFilter filter)(const Pixmap source, Pixmap target) @nogc {
	enum none = ScalingDirection.none;
	enum up = ScalingDirection.up;
	enum down = ScalingDirection.down;

	enum udecimalHalf = UDecimal.make(0x8000_0000);
	enum uint udecimalHalfFD = udecimalHalf.fractionalDigits;

	enum idxX = 0, idxY = 1;
	enum idxL = 0, idxR = 1;
	enum idxT = 0, idxB = 1;

	const int[2] sourceMax = [
		(source.width - 1),
		(source.height - 1),
	];

	const UDecimal[2] ratios = [
		(UDecimal(source.width) / target.width),
		(UDecimal(source.height) / target.height),
	];

	const UDecimal[2] ratiosHalf = [
		(ratios[idxX] >> 1),
		(ratios[idxY] >> 1),
	];

	// ==== Nearest Neighbor ====
	static if (filter == ScalingFilter.nearest) {

		Point translate(const Point dstPos) {
			pragma(inline, true);
			const x = (dstPos.x * ratios[idxX]).castTo!int;
			const y = (dstPos.y * ratios[idxY]).castTo!int;
			return Point(x, y);
		}

		auto dst = PixmapScannerRW(target);

		size_t y = 0;
		foreach (dstLine; dst) {
			foreach (x, ref pxDst; dstLine) {
				const posDst = Point(x.castTo!int, y.castTo!int);
				const posSrc = translate(posDst);
				const pxInt = source.getPixel(posSrc);
				pxDst = pxInt;
			}
			++y;
		}
	}

	// ==== Bilinear ====
	static if (filter == ScalingFilter.bilinear) {
		void scaleToLinearImpl(ScalingDirection directionX, ScalingDirection directionY)() {

			alias InterPixel = ulong[4];

			static Pixel toPixel(const InterPixel ipx) @safe pure nothrow @nogc {
				pragma(inline, true);
				return Pixel(
					clamp255(ipx[0]),
					clamp255(ipx[1]),
					clamp255(ipx[2]),
					clamp255(ipx[3]),
				);
			}

			static InterPixel toInterPixel(const Pixel ipx) @safe pure nothrow @nogc {
				pragma(inline, true);
				InterPixel result = [
					ipx.r,
					ipx.g,
					ipx.b,
					ipx.a,
				];
				return result;
			}

			int[2] posSrcCenterToInterpolationTargets(
				ScalingDirection direction,
			)(
				UDecimal posSrcCenter,
				int sourceMax,
			) {
				pragma(inline, true);

				int[2] result;
				static if (direction == none) {
					const value = posSrcCenter.castTo!int;
					result = [
						value,
						value,
					];
				}

				static if (direction == up || direction == down) {
					if (posSrcCenter < udecimalHalf) {
						result = [
							0,
							0,
						];
					} else {
						const floor = posSrcCenter.castTo!uint;
						if (posSrcCenter.fractionalDigits == udecimalHalfFD) {
							result = [
								floor,
								floor,
							];
						} else if (posSrcCenter.fractionalDigits > udecimalHalfFD) {
							const upper = min((floor + 1), sourceMax);
							result = [
								floor,
								upper,
							];
						} else {
							result = [
								floor - 1,
								floor,
							];
						}
					}
				}

				return result;
			}

			auto dst = PixmapScannerRW(target);

			size_t y = 0;
			foreach (dstLine; dst) {
				const posDstY = y.castTo!uint;
				const UDecimal posSrcCenterY = posDstY * ratios[idxY] + ratiosHalf[idxY];

				const int[2] posSrcY = posSrcCenterToInterpolationTargets!(directionY)(
					posSrcCenterY,
					sourceMax[idxY],
				);

				static if (directionY == down) {
					const nLines = 1 + posSrcY[idxB] - posSrcY[idxT];
				}

				static if (directionY == up) {
					const ulong[2] weightsY = () {
						ulong[2] result;
						result[0] = (udecimalHalf + posSrcY[1] - posSrcCenterY).fractionalDigits;
						result[1] = ulong(uint.max) + 1 - result[0];
						return result;
					}();
				}

				foreach (const x, ref pxDst; dstLine) {
					const posDstX = x.castTo!uint;
					const int[2] posDst = [
						posDstX,
						posDstY,
					];

					const posSrcCenterX = posDst[idxX] * ratios[idxX] + ratiosHalf[idxX];

					const int[2] posSrcX = posSrcCenterToInterpolationTargets!(directionX)(
						posSrcCenterX,
						sourceMax[idxX],
					);

					static if (directionX == down) {
						const nSamples = 1 + posSrcX[idxR] - posSrcX[idxL];
					}

					const Point[4] posNeighs = [
						Point(posSrcX[idxL], posSrcY[idxT]),
						Point(posSrcX[idxR], posSrcY[idxT]),
						Point(posSrcX[idxL], posSrcY[idxB]),
						Point(posSrcX[idxR], posSrcY[idxB]),
					];

					const Color[4] pxNeighs = [
						source.getPixel(posNeighs[0]),
						source.getPixel(posNeighs[1]),
						source.getPixel(posNeighs[2]),
						source.getPixel(posNeighs[3]),
					];

					enum idxTL = 0, idxTR = 1, idxBL = 2, idxBR = 3;

					// ====== Proper bilinear (up) + Avg (down) ======
					static if (filter == ScalingFilter.bilinear) {
						auto pxInt = Pixel(0, 0, 0, 0);

						// ======== Interpolate X ========
						auto sampleX() {
							pragma(inline, true);

							static if (directionY == down) {
								alias ForeachLineCallback =
									InterPixel delegate(const Point posLine) @safe pure nothrow @nogc;

								InterPixel foreachLine(scope ForeachLineCallback apply) {
									pragma(inline, true);
									InterPixel linesSum = 0;
									foreach (const lineY; posSrcY[idxT] .. (1 + posSrcY[idxB])) {
										const posLine = Point(posSrcX[idxL], lineY);
										const lineValues = apply(posLine);
										linesSum[] += lineValues[];
									}
									return linesSum;
								}
							}

							// ========== None ==========
							static if (directionX == none) {
								static if (directionY == none) {
									return pxNeighs[idxTL];
								}

								static if (directionY == up) {
									return () @trusted {
										InterPixel[2] result = [
											toInterPixel(pxNeighs[idxTL]),
											toInterPixel(pxNeighs[idxBL]),
										];
										return result;
									}();
								}

								static if (directionY == down) {
									auto ySum = foreachLine(delegate(const Point posLine) {
										const pxSrc = source.getPixel(posLine);
										return toInterPixel(pxSrc);
									});
									ySum[] /= nLines;
									return ySum;
								}
							}

							// ========== Down ==========
							static if (directionX == down) {
								static if (directionY == none) {
									const posSampling = posNeighs[idxTL];
									const samplingOffset = source.scanTo(posSampling);
									const srcSamples = () @trusted {
										return source.data.ptr[samplingOffset .. (samplingOffset + nSamples)];
									}();

									InterPixel xSum = [0, 0, 0, 0];

									foreach (const srcSample; srcSamples) {
										foreach (immutable ib, const c; srcSample.components) {
											() @trusted { xSum.ptr[ib] += c; }();
										}
									}

									xSum[] /= nSamples;
									return toPixel(xSum);
								}

								static if (directionY == up) {
									const Point[2] posSampling = [
										posNeighs[idxTL],
										posNeighs[idxBL],
									];

									const int[2] samplingOffsets = [
										source.scanTo(posSampling[idxT]),
										source.scanTo(posSampling[idxB]),
									];

									const srcSamples2 = () @trusted {
										const(const(Pixel)[])[2] result = [
											source.data.ptr[samplingOffsets[idxT] .. (samplingOffsets[idxT] + nSamples)],
											source.data.ptr[samplingOffsets[idxB] .. (samplingOffsets[idxB] + nSamples)],
										];
										return result;
									}();

									InterPixel[2] xSums = [[0, 0, 0, 0], [0, 0, 0, 0]];

									foreach (immutable idx, const srcSamples; srcSamples2) {
										foreach (const srcSample; srcSamples) {
											foreach (immutable ib, const c; srcSample.components)
												() @trusted { xSums.ptr[idx].ptr[ib] += c; }();
										}
									}

									foreach (ref xSum; xSums) {
										xSum[] /= nSamples;
									}

									return xSums;
								}

								static if (directionY == down) {
									auto ySum = foreachLine(delegate(const Point posLine) {
										const samplingOffset = source.scanTo(posLine);
										const srcSamples = () @trusted {
											return source.data.ptr[samplingOffset .. (samplingOffset + nSamples)];
										}();

										InterPixel xSum = 0;

										foreach (srcSample; srcSamples) {
											foreach (immutable ib, const c; srcSample.components) {
												() @trusted { xSum.ptr[ib] += c; }();
											}
										}

										return xSum;
									});

									ySum[] /= nSamples;
									ySum[] /= nLines;
									return ySum;
								}
							}

							// ========== Up ==========
							static if (directionX == up) {

								if (posSrcX[0] == posSrcX[1]) {
									static if (directionY == none) {
										return pxNeighs[idxTL];
									}
									static if (directionY == up) {
										return () @trusted {
											InterPixel[2] result = [
												toInterPixel(pxNeighs[idxTL]),
												toInterPixel(pxNeighs[idxBL]),
											];
											return result;
										}();
									}
									static if (directionY == down) {
										auto ySum = foreachLine(delegate(const Point posLine) {
											const samplingOffset = source.scanTo(posLine);
											return toInterPixel(
												(() @trusted => source.data.ptr[samplingOffset])()
											);
										});
										ySum[] /= nLines;
										return ySum;
									}
								}

								const ulong[2] weightsX = () {
									ulong[2] result;
									result[0] = (udecimalHalf + posSrcX[1] - posSrcCenterX).fractionalDigits;
									result[1] = ulong(uint.max) + 1 - result[0];
									return result;
								}();

								static if (directionY == none) {
									InterPixel xSum = [0, 0, 0, 0];

									foreach (immutable ib, ref c; xSum) {
										c += ((() @trusted => pxNeighs[idxTL].components.ptr[ib])() * weightsX[0]);
										c += ((() @trusted => pxNeighs[idxTR].components.ptr[ib])() * weightsX[1]);
									}

									foreach (ref c; xSum) {
										c >>= 32;
									}
									return toPixel(xSum);
								}

								static if (directionY == up) {
									InterPixel[2] xSums = [[0, 0, 0, 0], [0, 0, 0, 0]];

									() @trusted {
										foreach (immutable ib, ref c; xSums[0]) {
											c += (pxNeighs[idxTL].components.ptr[ib] * weightsX[idxL]);
											c += (pxNeighs[idxTR].components.ptr[ib] * weightsX[idxR]);
										}

										foreach (immutable ib, ref c; xSums[1]) {
											c += (pxNeighs[idxBL].components.ptr[ib] * weightsX[idxL]);
											c += (pxNeighs[idxBR].components.ptr[ib] * weightsX[idxR]);
										}
									}();

									foreach (ref sum; xSums) {
										foreach (ref c; sum) {
											c >>= 32;
										}
									}

									return xSums;
								}

								static if (directionY == down) {
									auto ySum = foreachLine(delegate(const Point posLine) {
										InterPixel xSum = [0, 0, 0, 0];

										const samplingOffset = source.scanTo(posLine);
										Pixel[2] pxcLR = () @trusted {
											Pixel[2] result = [
												source.data.ptr[samplingOffset],
												source.data.ptr[samplingOffset + 1],
											];
											return result;
										}();

										foreach (immutable ib, ref c; xSum) {
											c += ((() @trusted => pxcLR[idxL].components.ptr[ib])() * weightsX[idxL]);
											c += ((() @trusted => pxcLR[idxR].components.ptr[ib])() * weightsX[idxR]);
										}

										foreach (ref c; xSum) {
											c >>= 32;
										}
										return xSum;
									});

									ySum[] /= nLines;
									return ySum;
								}
							}
						}

						// ======== Interpolate Y ========
						static if (directionY == none) {
							const Pixel tmp = sampleX();
							pxInt = tmp;
						}
						static if (directionY == down) {
							const InterPixel tmp = sampleX();
							pxInt = toPixel(tmp);
						}
						static if (directionY == up) {
							const InterPixel[2] xSums = sampleX();
							foreach (immutable ib, ref c; pxInt.components) {
								ulong ySum = 0;
								ySum += ((() @trusted => xSums[idxT].ptr[ib])() * weightsY[idxT]);
								ySum += ((() @trusted => xSums[idxB].ptr[ib])() * weightsY[idxB]);

								const xySum = (ySum >> 32);
								c = clamp255(xySum);
							}
						}
					}

					pxDst = pxInt;
				}

				++y;
			}
		}

		const Size delta = (target.size - source.size);

		const ScalingDirection[2] directions = [
			scalingDirectionFromDelta(delta.width),
			scalingDirectionFromDelta(delta.height),
		];

		if (directions[0] == none) {
			if (directions[1] == none) {
				version (none) {
					scaleToLinearImpl!(none, none)();
				} else {
					target.data[] = source.data[];
				}
			} else if (directions[1] == up) {
				scaleToLinearImpl!(none, up)();
			} else /* if (directions[1] == down) */ {
				scaleToLinearImpl!(none, down)();
			}
		} else if (directions[0] == up) {
			if (directions[1] == none) {
				scaleToLinearImpl!(up, none)();
			} else if (directions[1] == up) {
				scaleToLinearImpl!(up, up)();
			} else /* if (directions[1] == down) */ {
				scaleToLinearImpl!(up, down)();
			}
		} else /* if (directions[0] == down) */ {
			if (directions[1] == none) {
				scaleToLinearImpl!(down, none)();
			} else if (directions[1] == up) {
				scaleToLinearImpl!(down, up)();
			} else /* if (directions[1] == down) */ {
				scaleToLinearImpl!(down, down)();
			}
		}
	}
}

/++
	Scales a pixmap and stores the result in the provided target Pixmap.

	The size to scale the image to
	is derived from the size of the target.

	---
	// This function can be used to omit a redundant size parameter
	// in cases like this:
	target = scale(source, target, target.size, ScalingFilter.bilinear);

	// → Instead do:
	scaleTo(source, target, ScalingFilter.bilinear);
	---
 +/
void scaleTo(const Pixmap source, Pixmap target, ScalingFilter filter) @nogc {
	import std.meta : NoDuplicates;
	import std.traits : EnumMembers;

	// dfmt off
	final switch (filter) {
		static foreach (scalingFilter; NoDuplicates!(EnumMembers!ScalingFilter))
			case scalingFilter: {
				scaleToImpl!scalingFilter(source, target);
				return;
			}
	}
	// dfmt on
}

// consistency
private alias scaleInto = scaleTo;

/++
	Scales an image to a new size.

	```
	╔═══╗   ╔═╗
	║———║ → ║—║
	╚═══╝   ╚═╝
	```
 +/
Pixmap scale(const Pixmap source, Pixmap target, Size scaleToSize, ScalingFilter filter) @nogc {
	target.adjustTo(scaleCalcDims(scaleToSize));
	source.scaleInto(target, filter);
	return target;
}

/// ditto
Pixmap scaleNew(const Pixmap source, Size scaleToSize, ScalingFilter filter) {
	auto target = Pixmap.makeNew(scaleToSize);
	source.scaleInto(target, filter);
	return target;
}

/// ditto
PixmapBlueprint scaleCalcDims(Size scaleToSize) @nogc {
	return PixmapBlueprint.fromSize(scaleToSize);
}

@safe pure nothrow @nogc:

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
	using the requested [BlendMode|blending mode].
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
	using the requested [BlendMode|blending mode].

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
	if (drawingEnd.x >= target.width) {
		drawingSize.width -= (drawingEnd.x - target.width);
	}
	if (drawingEnd.y >= target.height) {
		drawingSize.height -= (drawingEnd.y - target.height);
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
