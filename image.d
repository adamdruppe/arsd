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

// the basic image definitions have all been moved to the color module
public import arsd.color;
