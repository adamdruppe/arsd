module arsd.color;

// NOTE: this is obsolete. use color.d instead.

import std.stdio;
import std.math;
import std.conv;
import std.algorithm;

struct Color {
	ubyte r;
	ubyte g;
	ubyte b;
	ubyte a;

	this(int red, int green, int blue, int alpha = 255) {
		this.r = cast(ubyte) red;
		this.g = cast(ubyte) green;
		this.b = cast(ubyte) blue;
		this.a = cast(ubyte) alpha;
	}

	static Color transparent() {
		return Color(0, 0, 0, 0);
	}

	static Color white() {
		return Color(255, 255, 255);
	}

	static Color black() {
		return Color(0, 0, 0);
	}
}


Color fromHsl(real[3] hsl) {
	return fromHsl(hsl[0], hsl[1], hsl[2]);
}

Color fromHsl(real h, real s, real l) {
	h = h % 360;

	real C = (1 - abs(2 * l - 1)) * s;

	real hPrime = h / 60;

	real X = C * (1 - abs(hPrime % 2 - 1));

	real r, g, b;

	if(h is real.nan)
		r = g = b = 0;
	else if (hPrime >= 0 && hPrime < 1) {
		r = C;
		g = X;
		b = 0;
	} else if (hPrime >= 1 && hPrime < 2) {
		r = X;
		g = C;
		b = 0;
	} else if (hPrime >= 2 && hPrime < 3) {
		r = 0;
		g = C;
		b = X;
	} else if (hPrime >= 3 && hPrime < 4) {
		r = 0;
		g = X;
		b = C;
	} else if (hPrime >= 4 && hPrime < 5) {
		r = X;
		g = 0;
		b = C;
	} else if (hPrime >= 5 && hPrime < 6) {
		r = C;
		g = 0;
		b = X;
	}

	real m = l - C / 2;

	r += m;
	g += m;
	b += m;

	return Color(
		cast(ubyte)(r * 255),
		cast(ubyte)(g * 255),
		cast(ubyte)(b * 255),
		255);
}

real[3] toHsl(Color c) {
	real r1 = cast(real) c.r / 255;
	real g1 = cast(real) c.g / 255;
	real b1 = cast(real) c.b / 255;

	real maxColor = max(r1, g1, b1);
	real minColor = min(r1, g1, b1);

	real L = (maxColor + minColor) / 2 ;
	real S = 0;
	real H = 0;
	if(maxColor != minColor) {
		if(L < 0.5) {
			S = (maxColor - minColor) / (maxColor + minColor);
		} else {
			S = (maxColor - minColor) / (2.0 - maxColor - minColor);
		}
		if(r1 == maxColor) {
			H = (g1-b1) / (maxColor - minColor);
		} else if(g1 == maxColor) {
			H = 2.0 + (b1 - r1) / (maxColor - minColor);
		} else {
			H = 4.0 + (r1 - g1) / (maxColor - minColor);
		}
	}

	H = H * 60;
	if(H < 0){
		H += 360;
	}

	return [H, S, L]; 
}
/*
void main(string[] args) {
	auto color1 = toHsl(Color(255, 0, 0));
	auto color = fromHsl(color1[0] + 60, color1[1], color1[2]);

	writefln("#%02x%02x%02x", color.r, color.g, color.b);
}
*/
