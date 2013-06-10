module arsd.image;

/**
	This provides two image classes and a bunch of functions that work on them.

	Why are they separate classes? I think the operations on the two of them
	are necessarily different. There's a whole bunch of operations that only
	really work on truecolor (blurs, gradients), and a few that only work
	on indexed images (palette swaps).

	Even putpixel is pretty different. On indexed, it is a palette entry's
	index number. On truecolor, it is the actual color.

	A greyscale image is the weird thing in the middle. It is truecolor, but
	fits in the same size as indexed. Still, I'd say it is a specialization
	of truecolor.

	There is a subset that works on both

*/

import arsd.color;

interface Image {
	//IndexedImage convertToIndexedImage() const;
	//TrueColorImage convertToTrueColor() const;
	TrueColorImage getAsTrueColorImage();
}

class IndexedImage : Image {
	bool hasAlpha;
	Color[] palette;
	ubyte[] data;

	int width;
	int height;

	this(int w, int h) {
		width = w;
		height = h;
		data = new ubyte[w*h];
	}

	/*
	void resize(int w, int h, bool scale) {

	}
	*/

	override TrueColorImage getAsTrueColorImage() {
		return convertToTrueColor();
	}

	TrueColorImage convertToTrueColor() const {
		auto tci = new TrueColorImage(width, height);
		foreach(i, b; data) {
			tci.imageData.colors[i] = palette[b];
		}
		return tci;
	}

	ubyte getOrAddColor(Color c) {
		foreach(i, co; palette) {
			if(c == co)
				return cast(ubyte) i;
		}

		return addColor(c);
	}

	int numColors() const {
		return palette.length;
	}

	ubyte addColor(Color c) {
		assert(palette.length < 256);
		if(c.a != 255)
			hasAlpha = true;
		palette ~= c;

		return cast(ubyte) (palette.length - 1);
	}
}

class TrueColorImage : Image {
//	bool hasAlpha;
//	bool isGreyscale;
	//ubyte[] data; // stored as rgba quads, upper left to right to bottom
	union Data {
		ubyte[] bytes;
		Color[] colors;

		static assert(Color.sizeof == 4);
	}

	Data imageData;
	alias imageData.bytes data;

	int width;
	int height;

	this(int w, int h) {
		width = w;
		height = h;
		imageData.bytes = new ubyte[w*h*4];
	}

	override TrueColorImage getAsTrueColorImage() {
		return this;
	}

/+
	IndexedImage convertToIndexedImage(int maxColors = 256) {

	}
+/
}

/**
	Operations take a mask, which tells them where to apply.

	ImageMask.All means to just apply it

*/

/+
struct ImageMask {
	int width;
	int height;
	int left;
	int top;
	enum Shape { Rect, Custom }

	// Fills in each line, from the far left most set bit to the far right.
	// So you can take an outline, do filled and affect it all
	ImageMask filled() {

	}
}
+/
//TrueColorImage gradient
