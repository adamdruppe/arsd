/+
	== pixmappaint ==
	Copyright Elias Batek (0xEAB) 2024.
	Distributed under the Boost Software License, Version 1.0.
 +/
module arsd.pixmappaint;

import arsd.color;
import arsd.core;

///
alias Pixel = Color;

///
alias ColorF = arsd.color.ColorF;

///
alias Size = arsd.color.Size;

///
alias Point = arsd.color.Point;

// verify assumption(s)
static assert(Pixel.sizeof == uint.sizeof);

@safe pure nothrow @nogc {
	///
	Pixel rgba(ubyte r, ubyte g, ubyte b, ubyte a = 0xFF) {
		return Pixel(r, g, b, a);
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

@safe pure nothrow @nogc:

	/// Height of the buffer, i.e. the number of lines
	int height() inout {
		if (width == 0) {
			return 0;
		}

		return typeCast!int(data.length / width);
	}

	/// Rectangular size of the buffer
	Size size() inout {
		return Size(width, height);
	}

	/// Length of the buffer, i.e. the number of pixels
	int length() inout {
		return typeCast!int(data.length);
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

// Alpha-blending functions
@safe pure nothrow @nogc {

	///
	public void alphaBlend(scope Pixel[] target, scope const Pixel[] source) @trusted
	in (source.length == target.length) {
		foreach (immutable idx, ref pxtarget; target) {
			alphaBlend(pxtarget, source.ptr[idx]);
		}
	}

	///
	public void alphaBlend(ref Pixel pxTarget, const Pixel pxSource) @trusted {
		pragma(inline, true);

		immutable alphaSource = (pxSource.a | (pxSource.a << 8));
		immutable alphaTarget = (0xFFFF - alphaSource);

		foreach (immutable ib, ref px; pxTarget.components) {
			immutable d = cast(ubyte)(((px * alphaTarget) + 0x8080) >> 16);
			immutable s = cast(ubyte)(((pxSource.components.ptr[ib] * alphaSource) + 0x8080) >> 16);
			px = cast(ubyte)(d + s);
		}
	}
}

// Drawing functions
@safe pure nothrow @nogc {

	private {
		struct OriginRectangle {
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

		Point pos(Rectangle r) => r.upperLeft;
	}

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
		import std.math : round, sqrt;

		// TODO: line width
		// TODO: anti-aliasing (looks awful without it!)

		float deltaX = b.x - a.x;
		float deltaY = b.y - a.y;
		int steps = sqrt(deltaX * deltaX + deltaY * deltaY).typeCast!int;

		float[2] step = [
			(deltaX / steps),
			(deltaY / steps),
		];

		foreach (i; 0 .. steps) {
			// dfmt off
			immutable Point p = a + Point(
				round(step[0] * i).typeCast!int,
				round(step[1] * i).typeCast!int,
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
	void drawPixmap(Pixmap target, Pixmap image, Point pos) {
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
			target.sliceAt(Point(drawingTarget.x, y), drawingWidth)[] =
				source.sliceAt(Point(drawingSource.x, y + drawingSource.y), drawingWidth);
		}
	}
}
