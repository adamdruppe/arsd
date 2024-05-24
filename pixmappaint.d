/+
	== pixmappaint ==
	Copyright Elias Batek (0xEAB) 2024.
	Distributed under the Boost Software License, Version 1.0.

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
import std.math : round;

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
	this(Pixel[] data, int width) @nogc
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
		Retrieves a linear slice of the pixmap.

		Returns:
			`n` pixels starting at the top-left position `pos`.
	 +/
	inout(Pixel)[] sliceAt(Point pos, int n) inout {
		immutable size_t offset = linearOffset(width, pos);
		immutable size_t end = (offset + n);
		return data[offset .. end];
	}

	/// Clears the buffer’s contents (by setting each pixel to the same color)
	void clear(Pixel value) {
		data[] = value;
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
	Limits a value to a maximum 0xFF (= 255).
 +/
ubyte clamp255(Tint)(const Tint value) {
	pragma(inline, true);
	return (value < 0xFF) ? value.castTo!ubyte : 0xFF;
}

/++
	Fast 8-bit “percentage” function

	This function optimizes its runtime performance by substituting
	the division by 255 with an approximation using bitshifts.

	Nonetheless, the its result are as accurate as a floating point
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
		return (value * nPercentage / 255.0).round().castTo!ubyte();
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
void opacity(ref Pixmap pixmap, const ubyte opacity) {
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
void opacityF(ref Pixmap pixmap, const float opacity)
in (opacity >= 0)
in (opacity <= 1.0) {
	immutable opacity255 = round(opacity * 255).castTo!ubyte;
	pixmap.opacity = opacity255;
}

// ==== Alpha-blending functions ====

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

///
public void alphaBlend(
	BlendAccuracy accuracy,
	ubyte function(const ubyte, const ubyte) pure blend = null,
)(
	scope Pixel[] target,
	scope const Pixel[] source,
) @trusted
in (source.length == target.length) {
	foreach (immutable idx, ref pxTarget; target) {
		alphaBlend(pxTarget, source.ptr[idx]);
	}
}

/// ditto
public void alphaBlend(scope Pixel[] target, scope const Pixel[] source) @safe {
	return alphaBlend!(BlendAccuracy.rgba, null)(target, source);
}

///
public void alphaBlend(
	BlendAccuracy accuracy,
	ubyte function(const ubyte, const ubyte) blend = null,
)(
	ref Pixel pxTarget,
	const Pixel pxSource,
) @trusted {
	pragma(inline, true);

	static if (accuracy) {
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

	static if (accuracy) {
		pxTarget.a = alphaResult;
	}
}

/// ditto
public void alphaBlend(ref Pixel pxTarget, const Pixel pxSource) @safe {
	return alphaBlend!(BlendAccuracy.rgba, null)(pxTarget, pxSource);
}

// ==== Blending functions ====

enum BlendMode {
	none = 0,
	replace = none,
	normal = 1,
	alpha = normal,

	multiply,
	screen,

	darken,
	lighten,
}

///
alias Blend = BlendMode;

// undocumented
enum blendNormal = BlendMode.normal;

/++
	Blends pixel `source` into pixel `target`.
 +/
void blendPixel(BlendMode mode, BlendAccuracy accuracy = BlendAccuracy.rgba)(
	ref Pixel target,
	const Pixel source,
) if (mode == BlendMode.replace) {
	target = source;
}

/// ditto
void blendPixel(BlendMode mode, BlendAccuracy accuracy = BlendAccuracy.rgba)(
	ref Pixel target,
	const Pixel source,
) if (mode == Blend.alpha) {
	return alphaBlend!accuracy(target, source);
}

/// ditto
void blendPixel(BlendMode mode, BlendAccuracy accuracy = BlendAccuracy.rgba)(
	ref Pixel target,
	const Pixel source,
) if (mode == Blend.multiply) {

	return alphaBlend!(accuracy,
		(a, b) => n255thsOf(a, b)
	)(target, source);
}

/// ditto
void blendPixel(BlendMode mode, BlendAccuracy accuracy = BlendAccuracy.rgba)(
	ref Pixel target,
	const Pixel source,
) if (mode == Blend.screen) {

	return alphaBlend!(accuracy,
		(a, b) => castTo!ubyte(0xFF - n255thsOf((0xFF - a), (0xFF - b)))
	)(target, source);
}

/// ditto
void blendPixel(BlendMode mode, BlendAccuracy accuracy = BlendAccuracy.rgba)(
	ref Pixel target,
	const Pixel source,
) if (mode == Blend.darken) {

	return alphaBlend!(accuracy,
		(a, b) => min(a, b)
	)(target, source);
}

/// ditto
void blendPixel(BlendMode mode, BlendAccuracy accuracy = BlendAccuracy.rgba)(
	ref Pixel target,
	const Pixel source,
) if (mode == Blend.lighten) {

	return alphaBlend!(accuracy,
		(a, b) => max(a, b)
	)(target, source);
}

/++
	Blends the pixel data of `source` into `target`.

	`source` and `target` MUST have the same length.
 +/
void blendPixels(BlendMode mode, BlendAccuracy accuracy)(scope Pixel[] target, scope const Pixel[] source) @trusted
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
void blendPixels(BlendAccuracy accuracy = BlendAccuracy.rgba)(
	scope Pixel[] target,
	scope const Pixel[] source,
	BlendMode mode,
) {
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
void drawPixmap(Pixmap target, Pixmap image, Point pos, Blend blend = blendNormal) {
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
