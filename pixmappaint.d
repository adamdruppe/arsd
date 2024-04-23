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

	/// Clears the buffer’s contents (by setting each pixel to the same color)
	void clear(Pixel value) {
		data[] = value;
	}
}
