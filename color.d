///
module arsd.color;

@safe:

// importing phobos explodes the size of this code 10x, so not doing it.

private {
	real toInternal(T)(string s) {
		real accumulator = 0.0;
		size_t i = s.length;
		foreach(idx, c; s) {
			if(c >= '0' && c <= '9') {
				accumulator *= 10;
				accumulator += c - '0';
			} else if(c == '.') {
				i = idx + 1;
				break;
			} else
				throw new Exception("bad char to make real from " ~ s);
		}

		real accumulator2 = 0.0;
		real count = 1;
		foreach(c; s[i .. $]) {
			if(c >= '0' && c <= '9') {
				accumulator2 *= 10;
				accumulator2 += c - '0';
				count *= 10;
			} else
				throw new Exception("bad char to make real from " ~ s);
		}

		return accumulator + accumulator2 / count;
	}

	@trusted
	string toInternal(T)(int a) {
		if(a == 0)
			return "0";
		char[] ret;
		while(a) {
			ret ~= (a % 10) + '0';
			a /= 10;
		}
		for(int i = 0; i < ret.length / 2; i++) {
			char c = ret[i];
			ret[i] = ret[$ - i - 1];
			ret[$ - i - 1] = c;
		}
		return cast(string) ret;
	}
	string toInternal(T)(real a) {
		// a simplifying assumption here is the fact that we only use this in one place: toInternal!string(cast(real) a / 255)
		// thus we know this will always be between 0.0 and 1.0, inclusive.
		if(a <= 0.0)
			return "0.0";
		if(a >= 1.0)
			return "1.0";
		string ret = "0.";
		// I wonder if I can handle round off error any better. Phobos does, but that isn't worth 100 KB of code.
		int amt = cast(int)(a * 1000);
		return ret ~ toInternal!string(amt);
	}

	nothrow @safe @nogc pure
	real absInternal(real a) { return a < 0 ? -a : a; }
	nothrow @safe @nogc pure
	real minInternal(real a, real b, real c) {
		auto m = a;
		if(b < m) m = b;
		if(c < m) m = c;
		return m;
	}
	nothrow @safe @nogc pure
	real maxInternal(real a, real b, real c) {
		auto m = a;
		if(b > m) m = b;
		if(c > m) m = c;
		return m;
	}
	nothrow @safe @nogc pure
	bool startsWithInternal(string a, string b) {
		return (a.length >= b.length && a[0 .. b.length] == b);
	}
	string[] splitInternal(string a, char c) {
		string[] ret;
		size_t previous = 0;
		foreach(i, char ch; a) {
			if(ch == c) {
				ret ~= a[previous .. i];
				previous = i + 1;
			}
		}
		if(previous != a.length)
			ret ~= a[previous .. $];
		return ret;
	}
	nothrow @safe @nogc pure
	string stripInternal(string s) {
		foreach(i, char c; s)
			if(c != ' ' && c != '\t' && c != '\n') {
				s = s[i .. $];
				break;
			}
		for(int a = cast(int)(s.length - 1); a > 0; a--) {
			char c = s[a];
			if(c != ' ' && c != '\t' && c != '\n') {
				s = s[0 .. a + 1];
				break;
			}
		}

		return s;
	}
}

// done with mini-phobos

/// Represents an RGBA color
struct Color {
@safe:
	/++
		The color components are available as a static array, individual bytes, and a uint inside this union.

		Since it is anonymous, you can use the inner members' names directly.
	+/
	union {
		ubyte[4] components; /// [r, g, b, a]

		/// Holder for rgba individual components.
		struct {
			ubyte r; /// red
			ubyte g; /// green
			ubyte b; /// blue
			ubyte a; /// alpha. 255 == opaque
		}

		uint asUint; /// The components as a single 32 bit value (beware of endian issues!)
	}

	/++
		Like the constructor, but this makes sure they are in range before casting. If they are out of range, it saturates: anything less than zero becomes zero and anything greater than 255 becomes 255.
	+/
	nothrow pure
	static Color fromIntegers(int red, int green, int blue, int alpha = 255) {
		if(red < 0) red = 0; if(red > 255) red = 255;
		if(green < 0) green = 0; if(green > 255) green = 255;
		if(blue < 0) blue = 0; if(blue > 255) blue = 255;
		if(alpha < 0) alpha = 0; if(alpha > 255) alpha = 255;
		return Color(red, green, blue, alpha);
	}

	/// Construct a color with the given values. They should be in range 0 <= x <= 255, where 255 is maximum intensity and 0 is minimum intensity.
	nothrow pure @nogc
	this(int red, int green, int blue, int alpha = 255) {
		// workaround dmd bug 10937
		if(__ctfe)
			this.components[0] = cast(ubyte) red;
		else
			this.r = cast(ubyte) red;
		this.g = cast(ubyte) green;
		this.b = cast(ubyte) blue;
		this.a = cast(ubyte) alpha;
	}

	/// Static convenience functions for common color names
	nothrow pure @nogc
	static Color transparent() { return Color(0, 0, 0, 0); }
	/// Ditto
	nothrow pure @nogc
	static Color white() { return Color(255, 255, 255); }
	/// Ditto
	nothrow pure @nogc
	static Color black() { return Color(0, 0, 0); }
	/// Ditto
	nothrow pure @nogc
	static Color red() { return Color(255, 0, 0); }
	/// Ditto
	nothrow pure @nogc
	static Color green() { return Color(0, 255, 0); }
	/// Ditto
	nothrow pure @nogc
	static Color blue() { return Color(0, 0, 255); }
	/// Ditto
	nothrow pure @nogc
	static Color yellow() { return Color(255, 255, 0); }
	/// Ditto
	nothrow pure @nogc
	static Color teal() { return Color(0, 255, 255); }
	/// Ditto
	nothrow pure @nogc
	static Color purple() { return Color(255, 0, 255); }

	/*
	ubyte[4] toRgbaArray() {
		return [r,g,b,a];
	}
	*/

  /// Return black-and-white color
	Color toBW() () {
		int intens = cast(int)(0.2126*r+0.7152*g+0.0722*b);
		if (intens < 0) intens = 0; else if (intens > 255) intens = 255;
		return Color(intens, intens, intens, a);
	}

	/// Makes a string that matches CSS syntax for websites
	string toCssString() {
		if(a == 255)
			return "#" ~ toHexInternal(r) ~ toHexInternal(g) ~ toHexInternal(b);
		else {
			return "rgba("~toInternal!string(r)~", "~toInternal!string(g)~", "~toInternal!string(b)~", "~toInternal!string(cast(real)a / 255.0)~")";
		}
	}

	/// Makes a hex string RRGGBBAA (aa only present if it is not 255)
	string toString() {
		if(a == 255)
			return toCssString()[1 .. $];
		else
			return toRgbaHexString();
	}

	/// returns RRGGBBAA, even if a== 255
	string toRgbaHexString() {
		return toHexInternal(r) ~ toHexInternal(g) ~ toHexInternal(b) ~ toHexInternal(a);
	}

	/// Gets a color by name, iff the name is one of the static members listed above
	static Color fromNameString(string s) {
		Color c;
		foreach(member; __traits(allMembers, Color)) {
			static if(__traits(compiles, c = __traits(getMember, Color, member))) {
				if(s == member)
					return __traits(getMember, Color, member);
			}
		}
		throw new Exception("Unknown color " ~ s);
	}

	/// Reads a CSS style string to get the color. Understands #rrggbb, rgba(), hsl(), and rrggbbaa
	static Color fromString(string s) {
		s = s.stripInternal();

		Color c;
		c.a = 255;

		// trying named colors via the static no-arg methods here
		foreach(member; __traits(allMembers, Color)) {
			static if(__traits(compiles, c = __traits(getMember, Color, member))) {
				if(s == member)
					return __traits(getMember, Color, member);
			}
		}

		// try various notations borrowed from CSS (though a little extended)

		// hsl(h,s,l,a) where h is degrees and s,l,a are 0 >= x <= 1.0
		if(s.startsWithInternal("hsl(") || s.startsWithInternal("hsla(")) {
			assert(s[$-1] == ')');
			s = s[s.startsWithInternal("hsl(") ? 4 : 5  .. $ - 1]; // the closing paren

			real[3] hsl;
			ubyte a = 255;

			auto parts = s.splitInternal(',');
			foreach(i, part; parts) {
				if(i < 3)
					hsl[i] = toInternal!real(part.stripInternal);
				else
					a = cast(ubyte) (toInternal!real(part.stripInternal) * 255);
			}

			c = .fromHsl(hsl);
			c.a = a;

			return c;
		}

		// rgb(r,g,b,a) where r,g,b are 0-255 and a is 0-1.0
		if(s.startsWithInternal("rgb(") || s.startsWithInternal("rgba(")) {
			assert(s[$-1] == ')');
			s = s[s.startsWithInternal("rgb(") ? 4 : 5  .. $ - 1]; // the closing paren

			auto parts = s.splitInternal(',');
			foreach(i, part; parts) {
				// lol the loop-switch pattern
				auto v = toInternal!real(part.stripInternal);
				switch(i) {
					case 0: // red
						c.r = cast(ubyte) v;
					break;
					case 1:
						c.g = cast(ubyte) v;
					break;
					case 2:
						c.b = cast(ubyte) v;
					break;
					case 3:
						c.a = cast(ubyte) (v * 255);
					break;
					default: // ignore
				}
			}

			return c;
		}




		// otherwise let's try it as a hex string, really loosely

		if(s.length && s[0] == '#')
			s = s[1 .. $];

		// not a built in... do it as a hex string
		if(s.length >= 2) {
			c.r = fromHexInternal(s[0 .. 2]);
			s = s[2 .. $];
		}
		if(s.length >= 2) {
			c.g = fromHexInternal(s[0 .. 2]);
			s = s[2 .. $];
		}
		if(s.length >= 2) {
			c.b = fromHexInternal(s[0 .. 2]);
			s = s[2 .. $];
		}
		if(s.length >= 2) {
			c.a = fromHexInternal(s[0 .. 2]);
			s = s[2 .. $];
		}

		return c;
	}

	/// from hsl
	static Color fromHsl(real h, real s, real l) {
		return .fromHsl(h, s, l);
	}
}

nothrow @safe
private string toHexInternal(ubyte b) {
	string s;
	if(b < 16)
		s ~= '0';
	else {
		ubyte t = (b & 0xf0) >> 4;
		if(t >= 10)
			s ~= 'A' + t - 10;
		else
			s ~= '0' + t;
		b &= 0x0f;
	}
	if(b >= 10)
		s ~= 'A' + b - 10;
	else
		s ~= '0' + b;

	return s;
}

nothrow @safe @nogc pure
private ubyte fromHexInternal(string s) {
	int result = 0;

	int exp = 1;
	//foreach(c; retro(s)) { // FIXME: retro doesn't work right in dtojs
	foreach_reverse(c; s) {
		if(c >= 'A' && c <= 'F')
			result += exp * (c - 'A' + 10);
		else if(c >= 'a' && c <= 'f')
			result += exp * (c - 'a' + 10);
		else if(c >= '0' && c <= '9')
			result += exp * (c - '0');
		else
			// throw new Exception("invalid hex character: " ~ cast(char) c);
			return 0;

		exp *= 16;
	}

	return cast(ubyte) result;
}

/// Converts hsl to rgb
Color fromHsl(real[3] hsl) {
	return fromHsl(hsl[0], hsl[1], hsl[2]);
}

/// Converts hsl to rgb
Color fromHsl(real h, real s, real l, real a = 255) {
	h = h % 360;

	real C = (1 - absInternal(2 * l - 1)) * s;

	real hPrime = h / 60;

	real X = C * (1 - absInternal(hPrime % 2 - 1));

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
		cast(ubyte)(a));
}

/// Converts an RGB color into an HSL triplet. useWeightedLightness will try to get a better value for luminosity for the human eye, which is more sensitive to green than red and more to red than blue. If it is false, it just does average of the rgb.
real[3] toHsl(Color c, bool useWeightedLightness = false) {
	real r1 = cast(real) c.r / 255;
	real g1 = cast(real) c.g / 255;
	real b1 = cast(real) c.b / 255;

	real maxColor = maxInternal(r1, g1, b1);
	real minColor = minInternal(r1, g1, b1);

	real L = (maxColor + minColor) / 2 ;
	if(useWeightedLightness) {
		// the colors don't affect the eye equally
		// this is a little more accurate than plain HSL numbers
		L = 0.2126*r1 + 0.7152*g1 + 0.0722*b1;
	}
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

/// .
Color lighten(Color c, real percentage) {
	auto hsl = toHsl(c);
	hsl[2] *= (1 + percentage);
	if(hsl[2] > 1)
		hsl[2] = 1;
	return fromHsl(hsl);
}

/// .
Color darken(Color c, real percentage) {
	auto hsl = toHsl(c);
	hsl[2] *= (1 - percentage);
	return fromHsl(hsl);
}

/// for light colors, call darken. for dark colors, call lighten.
/// The goal: get toward center grey.
Color moderate(Color c, real percentage) {
	auto hsl = toHsl(c);
	if(hsl[2] > 0.5)
		hsl[2] *= (1 - percentage);
	else {
		if(hsl[2] <= 0.01) // if we are given black, moderating it means getting *something* out
			hsl[2] = percentage;
		else
			hsl[2] *= (1 + percentage);
	}
	if(hsl[2] > 1)
		hsl[2] = 1;
	return fromHsl(hsl);
}

/// the opposite of moderate. Make darks darker and lights lighter
Color extremify(Color c, real percentage) {
	auto hsl = toHsl(c, true);
	if(hsl[2] < 0.5)
		hsl[2] *= (1 - percentage);
	else
		hsl[2] *= (1 + percentage);
	if(hsl[2] > 1)
		hsl[2] = 1;
	return fromHsl(hsl);
}

/// Move around the lightness wheel, trying not to break on moderate things
Color oppositeLightness(Color c) {
	auto hsl = toHsl(c);

	auto original = hsl[2];

	if(original > 0.4 && original < 0.6)
		hsl[2] = 0.8 - original; // so it isn't quite the same
	else
		hsl[2] = 1 - original;

	return fromHsl(hsl);
}

/// Try to determine a text color - either white or black - based on the input
Color makeTextColor(Color c) {
	auto hsl = toHsl(c, true); // give green a bonus for contrast
	if(hsl[2] > 0.71)
		return Color(0, 0, 0);
	else
		return Color(255, 255, 255);
}

// These provide functional access to hsl manipulation; useful if you need a delegate

Color setLightness(Color c, real lightness) {
	auto hsl = toHsl(c);
	hsl[2] = lightness;
	return fromHsl(hsl);
}


///
Color rotateHue(Color c, real degrees) {
	auto hsl = toHsl(c);
	hsl[0] += degrees;
	return fromHsl(hsl);
}

///
Color setHue(Color c, real hue) {
	auto hsl = toHsl(c);
	hsl[0] = hue;
	return fromHsl(hsl);
}

///
Color desaturate(Color c, real percentage) {
	auto hsl = toHsl(c);
	hsl[1] *= (1 - percentage);
	return fromHsl(hsl);
}

///
Color saturate(Color c, real percentage) {
	auto hsl = toHsl(c);
	hsl[1] *= (1 + percentage);
	if(hsl[1] > 1)
		hsl[1] = 1;
	return fromHsl(hsl);
}

///
Color setSaturation(Color c, real saturation) {
	auto hsl = toHsl(c);
	hsl[1] = saturation;
	return fromHsl(hsl);
}


/*
void main(string[] args) {
	auto color1 = toHsl(Color(255, 0, 0));
	auto color = fromHsl(color1[0] + 60, color1[1], color1[2]);

	writefln("#%02x%02x%02x", color.r, color.g, color.b);
}
*/

/* Color algebra functions */

/* Alpha putpixel looks like this:

void putPixel(Image i, Color c) {
	Color b;
	b.r = i.data[(y * i.width + x) * bpp + 0];
	b.g = i.data[(y * i.width + x) * bpp + 1];
	b.b = i.data[(y * i.width + x) * bpp + 2];
	b.a = i.data[(y * i.width + x) * bpp + 3];

	float ca = cast(float) c.a / 255;

	i.data[(y * i.width + x) * bpp + 0] = alpha(c.r, ca, b.r);
	i.data[(y * i.width + x) * bpp + 1] = alpha(c.g, ca, b.g);
	i.data[(y * i.width + x) * bpp + 2] = alpha(c.b, ca, b.b);
	i.data[(y * i.width + x) * bpp + 3] = alpha(c.a, ca, b.a);
}

ubyte alpha(ubyte c1, float alpha, ubyte onto) {
	auto got = (1 - alpha) * onto + alpha * c1;

	if(got > 255)
		return 255;
	return cast(ubyte) got;
}

So, given the background color and the resultant color, what was
composited on to it?
*/

///
ubyte unalpha(ubyte colorYouHave, float alpha, ubyte backgroundColor) {
	// resultingColor = (1-alpha) * backgroundColor + alpha * answer
	auto resultingColorf = cast(float) colorYouHave;
	auto backgroundColorf = cast(float) backgroundColor;

	auto answer = (resultingColorf - backgroundColorf + alpha * backgroundColorf) / alpha;
	if(answer > 255)
		return 255;
	if(answer < 0)
		return 0;
	return cast(ubyte) answer;
}

///
ubyte makeAlpha(ubyte colorYouHave, ubyte backgroundColor/*, ubyte foreground = 0x00*/) {
	//auto foregroundf = cast(float) foreground;
	auto foregroundf = 0.00f;
	auto colorYouHavef = cast(float) colorYouHave;
	auto backgroundColorf = cast(float) backgroundColor;

	// colorYouHave = backgroundColorf - alpha * backgroundColorf + alpha * foregroundf
	auto alphaf = 1 - colorYouHave / backgroundColorf;
	alphaf *= 255;

	if(alphaf < 0)
		return 0;
	if(alphaf > 255)
		return 255;
	return cast(ubyte) alphaf;
}


int fromHex(string s) {
	int result = 0;

	int exp = 1;
	// foreach(c; retro(s)) {
	foreach_reverse(c; s) {
		if(c >= 'A' && c <= 'F')
			result += exp * (c - 'A' + 10);
		else if(c >= 'a' && c <= 'f')
			result += exp * (c - 'a' + 10);
		else if(c >= '0' && c <= '9')
			result += exp * (c - '0');
		else
			throw new Exception("invalid hex character: " ~ cast(char) c);

		exp *= 16;
	}

	return result;
}

///
Color colorFromString(string s) {
	if(s.length == 0)
		return Color(0,0,0,255);
	if(s[0] == '#')
		s = s[1..$];
	assert(s.length == 6 || s.length == 8);

	Color c;

	c.r = cast(ubyte) fromHex(s[0..2]);
	c.g = cast(ubyte) fromHex(s[2..4]);
	c.b = cast(ubyte) fromHex(s[4..6]);
	if(s.length == 8)
		c.a = cast(ubyte) fromHex(s[6..8]);
	else
		c.a = 255;

	return c;
}

/*
import browser.window;
import std.conv;
void main() {
	import browser.document;
	foreach(ele; document.querySelectorAll("input")) {
		ele.addEventListener("change", {
			auto h = toInternal!real(document.querySelector("input[name=h]").value);
			auto s = toInternal!real(document.querySelector("input[name=s]").value);
			auto l = toInternal!real(document.querySelector("input[name=l]").value);

			Color c = Color.fromHsl(h, s, l);

			auto e = document.getElementById("example");
			e.style.backgroundColor = c.toCssString();

			// JSElement __js_this;
			// __js_this.style.backgroundColor = c.toCssString();
		}, false);
	}
}
*/



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

/// An image in memory
interface MemoryImage {
	//IndexedImage convertToIndexedImage() const;
	//TrueColorImage convertToTrueColor() const;

	/// gets it as a TrueColorImage. May return this or may do a conversion and return a new image
	TrueColorImage getAsTrueColorImage();

	/// Image width, in pixels
	int width() const;

	/// Image height, in pixels
	int height() const;

	/// Get image pixel. Slow, but returns valid RGBA color (completely transparent for off-image pixels).
	Color getPixel(int x, int y) const;

  // Set image pixel.
	void setPixel(int x, int y, in Color clr);
}

/// An image that consists of indexes into a color palette. Use getAsTrueColorImage() if you don't care about palettes
class IndexedImage : MemoryImage {
	bool hasAlpha;

	/// .
	Color[] palette;
	/// the data as indexes into the palette. Stored left to right, top to bottom, no padding.
	ubyte[] data;

	/// .
	override int width() const {
		return _width;
	}

	/// .
	override int height() const {
		return _height;
	}

	override Color getPixel(int x, int y) const @trusted {
		if (x >= 0 && y >= 0 && x < _width && y < _height) {
			uint pos = y*_width+x;
			if (pos >= data.length) return Color(0, 0, 0, 0);
			ubyte b = data.ptr[pos];
			if (b >= palette.length) return Color(0, 0, 0, 0);
			return palette.ptr[b];
		} else {
			return Color(0, 0, 0, 0);
		}
	}

	override void setPixel(int x, int y, in Color clr) @trusted {
		if (x >= 0 && y >= 0 && x < _width && y < _height) {
			uint pos = y*_width+x;
			if (pos >= data.length) return;
			ubyte pidx = findNearestColor(palette, clr);
			if (palette.length < 255 &&
				 (palette.ptr[pidx].r != clr.r || palette.ptr[pidx].g != clr.g || palette.ptr[pidx].b != clr.b || palette.ptr[pidx].a != clr.a)) {
				// add new color
				pidx = addColor(clr);
			}
			data.ptr[pos] = pidx;
		}
	}

	private int _width;
	private int _height;

	/// .
	this(int w, int h) {
		_width = w;
		_height = h;
		data = new ubyte[w*h];
	}

	/*
	void resize(int w, int h, bool scale) {

	}
	*/

	/// returns a new image
	override TrueColorImage getAsTrueColorImage() {
		return convertToTrueColor();
	}

	/// Creates a new TrueColorImage based on this data
	TrueColorImage convertToTrueColor() const {
		auto tci = new TrueColorImage(width, height);
		foreach(i, b; data) {
			/*
			if(b >= palette.length) {
				string fuckyou;
				fuckyou ~= b + '0';
				fuckyou ~= " ";
				fuckyou ~= palette.length + '0';
				assert(0, fuckyou);
			}
			*/
			tci.imageData.colors[i] = palette[b];
		}
		return tci;
	}

	/// Gets an exact match, if possible, adds if not. See also: the findNearestColor free function.
	ubyte getOrAddColor(Color c) {
		foreach(i, co; palette) {
			if(c == co)
				return cast(ubyte) i;
		}

		return addColor(c);
	}

	/// Number of colors currently in the palette (note: palette entries are not necessarily used in the image data)
	int numColors() const {
		return cast(int) palette.length;
	}

	/// Adds an entry to the palette, returning its inded
	ubyte addColor(Color c) {
		assert(palette.length < 256);
		if(c.a != 255)
			hasAlpha = true;
		palette ~= c;

		return cast(ubyte) (palette.length - 1);
	}
}

/// An RGBA array of image data. Use the free function quantize() to convert to an IndexedImage
class TrueColorImage : MemoryImage {
//	bool hasAlpha;
//	bool isGreyscale;

	//ubyte[] data; // stored as rgba quads, upper left to right to bottom
	/// .
	struct Data {
		ubyte[] bytes; /// the data as rgba bytes. Stored left to right, top to bottom, no padding.
		// the union is no good because the length of the struct is wrong!

		/// the same data as Color structs
		@trusted // the cast here is typically unsafe, but it is ok
		// here because I guarantee the layout, note the static assert below
		@property inout(Color)[] colors() inout {
			return cast(inout(Color)[]) bytes;
		}

		static assert(Color.sizeof == 4);
	}

	/// .
	Data imageData;
	alias imageData.bytes data;

	int _width;
	int _height;

	/// .
	override int width() const { return _width; }
	///.
	override int height() const { return _height; }

	override Color getPixel(int x, int y) const @trusted {
		if (x >= 0 && y >= 0 && x < _width && y < _height) {
			uint pos = y*_width+x;
			if (pos+3 >= imageData.bytes.length/4) return Color(0, 0, 0, 0);
			return imageData.colors.ptr[pos];
		} else {
			return Color(0, 0, 0, 0);
		}
	}

	override void setPixel(int x, int y, in Color clr) @trusted {
		if (x >= 0 && y >= 0 && x < _width && y < _height) {
			uint pos = y*_width+x;
			if (pos+3 < imageData.bytes.length/4) imageData.colors.ptr[pos] = clr;
		}
	}

	/// .
	this(int w, int h) {
		_width = w;
		_height = h;
		imageData.bytes = new ubyte[w*h*4];
	}

	/// Creates with existing data. The data pointer is stored here.
	this(int w, int h, ubyte[] data) {
		_width = w;
		_height = h;
		assert(data.length == w * h * 4);
		imageData.bytes = data;
	}

	/// Returns this
	override TrueColorImage getAsTrueColorImage() {
		return this;
	}
}

/// Converts true color to an indexed image. It uses palette as the starting point, adding entries
/// until maxColors as needed. If palette is null, it creates a whole new palette.
///
/// After quantizing the image, it applies a dithering algorithm.
///
/// This is not written for speed.
IndexedImage quantize(in TrueColorImage img, Color[] palette = null, in int maxColors = 256)
	// this is just because IndexedImage assumes ubyte palette values
	in { assert(maxColors <= 256); }
body {
	int[Color] uses;
	foreach(pixel; img.imageData.colors) {
		if(auto i = pixel in uses) {
			(*i)++;
		} else {
			uses[pixel] = 1;
		}
	}

	struct ColorUse {
		Color c;
		int uses;
		//string toString() { import std.conv; return c.toCssString() ~ " x " ~ to!string(uses); }
		int opCmp(ref const ColorUse co) const {
			return co.uses - uses;
		}
	}

	ColorUse[] sorted;

	foreach(color, count; uses)
		sorted ~= ColorUse(color, count);

	uses = null;
	version(no_phobos)
		sorted = sorted.sort;
	else {
		import std.algorithm : sort;
		sort(sorted);
	}

	ubyte[Color] paletteAssignments;
	foreach(idx, entry; palette)
		paletteAssignments[entry] = cast(ubyte) idx;

	// For the color assignments from the image, I do multiple passes, decreasing the acceptable
	// distance each time until we're full.

	// This is probably really slow.... but meh it gives pretty good results.

	auto ddiff = 32;
	outer: for(int d1 = 128; d1 >= 0; d1 -= ddiff) {
	auto minDist = d1*d1;
	if(d1 <= 64)
		ddiff = 16;
	if(d1 <= 32)
		ddiff = 8;
	foreach(possibility; sorted) {
		if(palette.length == maxColors)
			break;
		if(palette.length) {
			auto co = palette[findNearestColor(palette, possibility.c)];
			auto pixel = possibility.c;

			auto dr = cast(int) co.r - pixel.r;
			auto dg = cast(int) co.g - pixel.g;
			auto db = cast(int) co.b - pixel.b;

			auto dist = dr*dr + dg*dg + db*db;
			// not good enough variety to justify an allocation yet
			if(dist < minDist)
				continue;
		}
		paletteAssignments[possibility.c] = cast(ubyte) palette.length;
		palette ~= possibility.c;
	}
	}

	// Final pass: just fill in any remaining space with the leftover common colors
	while(palette.length < maxColors && sorted.length) {
		if(sorted[0].c !in paletteAssignments) {
			paletteAssignments[sorted[0].c] = cast(ubyte) palette.length;
			palette ~= sorted[0].c;
		}
		sorted = sorted[1 .. $];
	}


	bool wasPerfect = true;
	auto newImage = new IndexedImage(img.width, img.height);
	newImage.palette = palette;
	foreach(idx, pixel; img.imageData.colors) {
		if(auto p = pixel in paletteAssignments)
			newImage.data[idx] = *p;
		else {
			// gotta find the closest one...
			newImage.data[idx] = findNearestColor(palette, pixel);
			wasPerfect = false;
		}
	}

	if(!wasPerfect)
		floydSteinbergDither(newImage, img);

	return newImage;
}

/// Finds the best match for pixel in palette (currently by checking for minimum euclidean distance in rgb colorspace)
ubyte findNearestColor(in Color[] palette, in Color pixel) {
	int best = 0;
	int bestDistance = int.max;
	foreach(pe, co; palette) {
		auto dr = cast(int) co.r - pixel.r;
		auto dg = cast(int) co.g - pixel.g;
		auto db = cast(int) co.b - pixel.b;
		int dist = dr*dr + dg*dg + db*db;

		if(dist < bestDistance) {
			best = cast(int) pe;
			bestDistance = dist;
		}
	}

	return cast(ubyte) best;
}

/+

// Quantizing and dithering test program

void main( ){
/*
	auto img = new TrueColorImage(256, 32);
	foreach(y; 0 .. img.height) {
		foreach(x; 0 .. img.width) {
			img.imageData.colors[x + y * img.width] = Color(x, y * (255 / img.height), 0);
		}
	}
*/

TrueColorImage img;

{

import arsd.png;

struct P {
	ubyte[] range;
	void put(ubyte[] a) { range ~= a; }
}

P range;
import std.algorithm;

import std.stdio;
writePngLazy(range, pngFromBytes(File("/home/me/nyesha.png").byChunk(4096)).byRgbaScanline.map!((line) {
	foreach(ref pixel; line.pixels) {
	continue;
		auto sum = cast(int) pixel.r + pixel.g + pixel.b;
		ubyte a = cast(ubyte)(sum / 3);
		pixel.r = a;
		pixel.g = a;
		pixel.b = a;
	}
	return line;
}));

img = imageFromPng(readPng(range.range)).getAsTrueColorImage;


}



	auto qimg = quantize(img, null, 2);

	import arsd.simpledisplay;
	auto win = new SimpleWindow(img.width, img.height * 3);
	auto painter = win.draw();
	painter.drawImage(Point(0, 0), Image.fromMemoryImage(img));
	painter.drawImage(Point(0, img.height), Image.fromMemoryImage(qimg));
	floydSteinbergDither(qimg, img);
	painter.drawImage(Point(0, img.height * 2), Image.fromMemoryImage(qimg));
	win.eventLoop(0);
}
+/

/+
/// If the background is transparent, it simply erases the alpha channel.
void removeTransparency(IndexedImage img, Color background)
+/

Color alphaBlend(Color foreground, Color background) {
	if(foreground.a != 255)
	foreach(idx, ref part; foreground.components) {
		part = cast(ubyte) (part * foreground.a / 255 +
			background.components[idx] * (255 - foreground.a) / 255);
	}

	return foreground;
}

/*
/// Reduces the number of colors in a palette.
void reducePaletteSize(IndexedImage img, int maxColors = 16) {

}
*/

// I think I did this wrong... but the results aren't too bad so the bug can't be awful.
/// Dithers img in place to look more like original.
void floydSteinbergDither(IndexedImage img, in TrueColorImage original) {
	assert(img.width == original.width);
	assert(img.height == original.height);

	auto buffer = new Color[](original.imageData.colors.length);

	int x, y;

	foreach(idx, c; original.imageData.colors) {
		auto n = img.palette[img.data[idx]];
		int errorR = cast(int) c.r - n.r;
		int errorG = cast(int) c.g - n.g;
		int errorB = cast(int) c.b - n.b;

		void doit(int idxOffset, int multiplier) {
		//	if(idx + idxOffset < buffer.length)
				buffer[idx + idxOffset] = Color.fromIntegers(
					c.r + multiplier * errorR / 16,
					c.g + multiplier * errorG / 16,
					c.b + multiplier * errorB / 16,
					c.a
				);
		}

		if((x+1) != original.width)
			doit(1, 7);
		if((y+1) != original.height) {
			if(x != 0)
				doit(-1 + img.width, 3);
			doit(img.width, 5);
			if(x+1 != original.width)
				doit(1 + img.width, 1);
		}

		img.data[idx] = findNearestColor(img.palette, buffer[idx]);

		x++;
		if(x == original.width) {
			x = 0;
			y++;
		}
	}
}

// these are just really useful in a lot of places where the color/image functions are used,
// so I want them available with Color
///
struct Point {
	int x; ///
	int y; ///
}

///
struct Size {
	int width; ///
	int height; ///
}

///
struct Rectangle {
	int left; ///
	int top; ///
	int right; ///
	int bottom; ///
}
