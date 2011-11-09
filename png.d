module arsd.png;

// By Adam D. Ruppe, 2009-2010, released into the public domain
import std.stdio;
import std.conv;
import std.file;

import std.zlib;

public import arsd.image;

/**
	The return value should be casted to indexed or truecolor depending on what you need.

	To get an image from a png file, do this:

	auto i = cast(TrueColorImage) imageFromPng(readPng(cast(ubyte)[]) std.file.read("file.png")));
*/
Image imageFromPng(PNG* png) {
	PNGHeader h = getHeader(png);

	return new IndexedImage(h.width, h.height);
}

/*
struct PNGHeader {
	uint width;
	uint height;
	ubyte depth = 8;
	ubyte type = 6; // 0 - greyscale, 2 - truecolor, 3 - indexed color, 4 - grey with alpha, 6 - true with alpha
	ubyte compressionMethod = 0; // should be zero
	ubyte filterMethod = 0; // should be zero
	ubyte interlaceMethod = 0; // bool
}
*/


PNG* pngFromImage(IndexedImage i) {
	PNGHeader h;
	h.width = i.width;
	h.height = i.height;
	h.type = 3;
	if(i.numColors() <= 2)
		h.depth = 1;
	else if(i.numColors() <= 4)
		h.depth = 2;
	else if(i.numColors() <= 16)
		h.depth = 4;
	else if(i.numColors() <= 256)
		h.depth = 8;
	else throw new Exception("can't save this as an indexed png");

	auto png = blankPNG(h);

	// do palette and alpha
	// FIXME: if there is only one transparent color, set it as the special chunk for that

	// FIXME: we'd get a smaller file size if the transparent pixels were arranged first
	Chunk palette;
	palette.type = ['P', 'L', 'T', 'E'];
	palette.size = i.palette.length * 3;
	palette.payload.length = palette.size;

	Chunk alpha;
	if(i.hasAlpha) {
		alpha.type = ['t', 'R', 'N', 'S'];
		alpha.size = i.palette.length;
		alpha.payload.length = alpha.size;
	}

	for(int a = 0; a < i.palette.length; a++) {
		palette.payload[a*3+0] = i.palette[a].r;
		palette.payload[a*3+1] = i.palette[a].g;
		palette.payload[a*3+2] = i.palette[a].b;
		if(i.hasAlpha)
			alpha.payload[a] = i.palette[a].a;
	}

	palette.checksum = crc("PLTE", palette.payload);
	png.chunks ~= palette;
	if(i.hasAlpha) {
		alpha.checksum = crc("tRNS", alpha.payload);
		png.chunks ~= alpha;
	}

	// do the datastream
	if(h.depth == 8) {
		addImageDatastreamToPng(i.data, png);
	} else {
		// gotta convert it
		ubyte[] datastream = new ubyte[i.width * i.height * 8 / h.depth]; // FIXME?
		int shift = 0;

		switch(h.depth) {
			default: assert(0); break;
			case 1: shift = 7; break;
			case 2: shift = 6; break;
			case 4: shift = 4; break;
			case 8: shift = 0; break;
		}
		int dsp = 0;
		int dpos = 0;
		bool justAdvanced;
		for(int y = 0; y < i.height; y++) {
		for(int x = 0; x < i.width; x++) {
			datastream[dsp] |= i.data[dpos++] << shift;

			switch(h.depth) {
				default: assert(0); break;
				case 1: shift-= 1; break;
				case 2: shift-= 2; break;
				case 4: shift-= 4; break;
				case 8: shift-= 8; break;
			}
			
			justAdvanced = shift < 0;
			if(shift < 0) {
				dsp++;
				switch(h.depth) {
					default: assert(0); break;
					case 1: shift = 7; break;
					case 2: shift = 6; break;
					case 4: shift = 4; break;
					case 8: shift = 0; break;
				}
			}
		}
			if(!justAdvanced)
				dsp++;
			switch(h.depth) {
				default: assert(0); break;
				case 1: shift = 7; break;
				case 2: shift = 6; break;
				case 4: shift = 4; break;
				case 8: shift = 0; break;
			}

		}

		addImageDatastreamToPng(datastream, png);
	}

	return png;
}

PNG* pngFromImage(TrueColorImage i) {
	PNGHeader h;
	h.width = i.width;
	h.height = i.height;
	// FIXME: optimize it if it is greyscale or doesn't use alpha alpha

	auto png = blankPNG(h);
	addImageDatastreamToPng(i.data, png);

	return png;
}

/*
void main(string[] args) {
	auto a = readPng(cast(ubyte[]) read(args[1]));
	auto f = getDatastream(a);

	foreach(i; f) {
		writef("%d ", i);
	}

	writefln("\n\n%d", f.length);
}
*/

struct Chunk {
	uint size;
	ubyte[4] type;
	ubyte[] payload;
	uint checksum;
}

struct PNG {
	uint length;
	ubyte[8] header;
	Chunk[] chunks;

	Chunk* getChunk(string what) {
		foreach(ref c; chunks) {
			if(cast(string) c.type == what)
				return &c;
		}
		throw new Exception("no such chunk " ~ what);
	}

	Chunk* getChunkNullable(string what) {
		foreach(ref c; chunks) {
			if(cast(string) c.type == what)
				return &c;
		}
		return null;
	}
}

ubyte[] writePng(PNG* p) {
	ubyte[] a;
	if(p.length)
		a.length = p.length;
	else {
		a.length = 8;
		foreach(c; p.chunks)
			a.length += c.size + 12;
	}
	uint pos;

	a[0..8] = p.header[0..8];
	pos = 8;
	foreach(c; p.chunks) {
		a[pos++] = (c.size & 0xff000000) >> 24;
		a[pos++] = (c.size & 0x00ff0000) >> 16;
		a[pos++] = (c.size & 0x0000ff00) >> 8;
		a[pos++] = (c.size & 0x000000ff) >> 0;

		a[pos..pos+4] = c.type[0..4];
		pos += 4;
		a[pos..pos+c.size] = c.payload[0..c.size];
		pos += c.size;

		a[pos++] = (c.checksum & 0xff000000) >> 24;
		a[pos++] = (c.checksum & 0x00ff0000) >> 16;
		a[pos++] = (c.checksum & 0x0000ff00) >> 8;
		a[pos++] = (c.checksum & 0x000000ff) >> 0;
	}

	return a;
}

PNG* readPng(ubyte[] data) {
	auto p = new PNG;

	p.length = data.length;
	p.header[0..8] = data[0..8];

	uint pos = 8;

	while(pos < data.length) {
		Chunk n;
		n.size |= data[pos++] << 24;
		n.size |= data[pos++] << 16;
		n.size |= data[pos++] << 8;
		n.size |= data[pos++] << 0;
		n.type[0..4] = data[pos..pos+4];
		pos += 4;
		n.payload.length = n.size;
		n.payload[0..n.size] = data[pos..pos+n.size];
		pos += n.size;

		n.checksum |= data[pos++] << 24;
		n.checksum |= data[pos++] << 16;
		n.checksum |= data[pos++] << 8;
		n.checksum |= data[pos++] << 0;

		p.chunks ~= n;
	}

	return p;
}

PNG* blankPNG(PNGHeader h) {
	auto p = new PNG;
	p.header = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

	Chunk c;

	c.size = 13;
	c.type = ['I', 'H', 'D', 'R'];

	c.payload.length = 13;
	int pos = 0;

	c.payload[pos++] = h.width >> 24;
	c.payload[pos++] = (h.width >> 16) & 0xff;
	c.payload[pos++] = (h.width >> 8) & 0xff;
	c.payload[pos++] = h.width & 0xff;

	c.payload[pos++] = h.height >> 24;
	c.payload[pos++] = (h.height >> 16) & 0xff;
	c.payload[pos++] = (h.height >> 8) & 0xff;
	c.payload[pos++] = h.height & 0xff;

	c.payload[pos++] = h.depth;
	c.payload[pos++] = h.type;
	c.payload[pos++] = h.compressionMethod;
	c.payload[pos++] = h.filterMethod;
	c.payload[pos++] = h.interlaceMethod;


	c.checksum = crc("IHDR", c.payload);

	p.chunks ~= c;

	return p;
}

// should NOT have any idata already.
// FIXME: doesn't handle palettes
void addImageDatastreamToPng(const(ubyte)[] data, PNG* png) {
	// we need to go through the lines and add the filter byte
	// then compress it into an IDAT chunk
	// then add the IEND chunk

	PNGHeader h = getHeader(png);

	auto bytesPerLine = h.width * 4;
	if(h.type == 3)
		bytesPerLine = h.width * 8 /  h.depth;
	Chunk dat;
	dat.type = ['I', 'D', 'A', 'T'];
	int pos = 0;

	const(ubyte)[] output;
	while(pos+bytesPerLine <= data.length) {
		output ~= 0;
		output ~= data[pos..pos+bytesPerLine];
		pos += bytesPerLine;
	}

	auto com = cast(ubyte[]) compress(output);
	dat.size = com.length;
	dat.payload = com;
	dat.checksum = crc("IDAT", dat.payload);

	png.chunks ~= dat;

	Chunk c;

	c.size = 0;
	c.type = ['I', 'E', 'N', 'D'];
	c.checksum = crc("IEND", c.payload);

	png.chunks ~= c;

}

struct PNGHeader {
	uint width;
	uint height;
	ubyte depth = 8;
	ubyte type = 6; // 0 - greyscale, 2 - truecolor, 3 - indexed color, 4 - grey with alpha, 6 - true with alpha
	ubyte compressionMethod = 0; // should be zero
	ubyte filterMethod = 0; // should be zero
	ubyte interlaceMethod = 0; // bool
}

// bKGD - palette entry for background or the RGB (16 bits each) for that. or 16 bits of grey

ubyte[] getDatastream(PNG* p) {
	ubyte[] compressed;

	foreach(c; p.chunks) {
		if(cast(string) c.type != "IDAT")
			continue;
		compressed ~= c.payload;
	}

	return cast(ubyte[]) uncompress(compressed);
}

// FIXME: Assuming 8 bits per pixel
ubyte[] getUnfilteredDatastream(PNG* p) {
	PNGHeader h = getHeader(p);
	assert(h.filterMethod == 0);

	assert(h.type == 3); // FIXME
	assert(h.depth == 8); // FIXME

	ubyte[] data = getDatastream(p);
	ubyte[] ufdata = new ubyte[data.length - h.height];

	int bytesPerLine = ufdata.length / h.height;

	int pos = 0, pos2 = 0;
	for(int a = 0; a < h.height; a++) {
		assert(data[pos2] == 0);
		ufdata[pos..pos+bytesPerLine] = data[pos2+1..pos2+bytesPerLine+1];
		pos+= bytesPerLine;
		pos2+= bytesPerLine + 1;
	}

	return ufdata;
}

ubyte[] getFlippedUnfilteredDatastream(PNG* p) {
	PNGHeader h = getHeader(p);
	assert(h.filterMethod == 0);

	assert(h.type == 3); // FIXME
	assert(h.depth == 8 || h.depth == 4); // FIXME

	ubyte[] data = getDatastream(p);
	ubyte[] ufdata = new ubyte[data.length - h.height];

	int bytesPerLine = ufdata.length / h.height;


	int pos = ufdata.length - bytesPerLine, pos2 = 0;
	for(int a = 0; a < h.height; a++) {
		assert(data[pos2] == 0);
		ufdata[pos..pos+bytesPerLine] = data[pos2+1..pos2+bytesPerLine+1];
		pos-= bytesPerLine;
		pos2+= bytesPerLine + 1;
	}

	return ufdata;
}

ubyte getHighNybble(ubyte a) {
	return cast(ubyte)(a >> 4); // FIXME
}

ubyte getLowNybble(ubyte a) {
	return a & 0x0f;
}

// Takes the transparency info and returns
ubyte[] getANDMask(PNG* p) {
	PNGHeader h = getHeader(p);
	assert(h.filterMethod == 0);

	assert(h.type == 3); // FIXME
	assert(h.depth == 8 || h.depth == 4); // FIXME

	assert(h.width % 8 == 0); // might actually be %2

	ubyte[] data = getDatastream(p);
	ubyte[] ufdata = new ubyte[h.height*((((h.width+7)/8)+3)&~3)]; // gotta pad to DWORDs...

	Color[] colors = fetchPalette(p);

	int pos = 0, pos2 = (h.width/((h.depth == 8) ? 1 : 2)+1)*(h.height-1);
	bool bits = false;
	for(int a = 0; a < h.height; a++) {
		assert(data[pos2++] == 0);
		for(int b = 0; b < h.width; b++) {
			if(h.depth == 4) {
				ufdata[pos/8] |= ((colors[bits? getLowNybble(data[pos2]) : getHighNybble(data[pos2])].a <= 30) << (7-(pos%8)));
			} else
				ufdata[pos/8] |= ((colors[data[pos2]].a == 0) << (7-(pos%8)));
			pos++;
			if(h.depth == 4) {
				if(bits) {
					pos2++;
				}
				bits = !bits;
			} else
				pos2++;
		}

		int pad = 0;
		for(; pad < ((pos/8) % 4); pad++) {
			ufdata[pos/8] = 0;
			pos+=8;
		}
		if(h.depth == 4)
			pos2 -= h.width + 2;
		else
			pos2-= 2*(h.width) +2;
	}

	return ufdata;
}

// Done with assumption

PNGHeader getHeader(PNG* p) {
	PNGHeader h;
	ubyte[] data = p.getChunk("IHDR").payload;

	int pos = 0;

	h.width |= data[pos++] << 24;
	h.width |= data[pos++] << 16;
	h.width |= data[pos++] << 8;
	h.width |= data[pos++] << 0;

	h.height |= data[pos++] << 24;
	h.height |= data[pos++] << 16;
	h.height |= data[pos++] << 8;
	h.height |= data[pos++] << 0;

	h.depth = data[pos++];
	h.type = data[pos++];
	h.compressionMethod = data[pos++];
	h.filterMethod = data[pos++];
	h.interlaceMethod = data[pos++];

	return h;
}

struct Color {
	ubyte r;
	ubyte g;
	ubyte b;
	ubyte a;
}

/+
class Image {
	Color[][] trueColorData;
	ubyte[] indexData;

	Color[] palette;

	uint width;
	uint height;

	this(uint w, uint h) {}
}

Image fromPNG(PNG* p) {

}

PNG* toPNG(Image i) {

}
+/		struct RGBQUAD {
			ubyte rgbBlue;
			ubyte rgbGreen;
			ubyte rgbRed;
			ubyte rgbReserved;
		}

RGBQUAD[] fetchPaletteWin32(PNG* p) {
	RGBQUAD[] colors;

	auto palette = p.getChunk("PLTE");

	colors.length = (palette.size) / 3;

	for(int i = 0; i < colors.length; i++) {
		colors[i].rgbRed = palette.payload[i*3+0];
		colors[i].rgbGreen = palette.payload[i*3+1];
		colors[i].rgbBlue = palette.payload[i*3+2];
		colors[i].rgbReserved = 0;
	}

	return colors;

}

Color[] fetchPalette(PNG* p) {
	Color[] colors;

	auto palette = p.getChunk("PLTE");

	Chunk* alpha = p.getChunkNullable("tRNS");

	colors.length = palette.size / 3;

	for(int i = 0; i < colors.length; i++) {
		colors[i].r = palette.payload[i*3+0];
		colors[i].g = palette.payload[i*3+1];
		colors[i].b = palette.payload[i*3+2];
		if(alpha !is null && i < alpha.size)
			colors[i].a = alpha.payload[i];
		else
			colors[i].a = 255;

		//writefln("%2d: %3d %3d %3d %3d", i, colors[i].r, colors[i].g, colors[i].b, colors[i].a);
	}

	return colors;
}

void replacePalette(PNG* p, Color[] colors) {
	auto palette = p.getChunk("PLTE");
	auto alpha = p.getChunk("tRNS");

	assert(colors.length == alpha.size);

	for(int i = 0; i < colors.length; i++) {
		palette.payload[i*3+0] = colors[i].r;
		palette.payload[i*3+1] = colors[i].g;
		palette.payload[i*3+2] = colors[i].b;
		alpha.payload[i] = colors[i].a;
	}

	palette.checksum = crc("PLTE", palette.payload);
	alpha.checksum = crc("tRNS", alpha.payload);
}

uint update_crc(in uint crc, in ubyte[] buf){
	static const uint[256] crc_table = [0, 1996959894, 3993919788, 2567524794, 124634137, 1886057615, 3915621685, 2657392035, 249268274, 2044508324, 3772115230, 2547177864, 162941995, 2125561021, 3887607047, 2428444049, 498536548, 1789927666, 4089016648, 2227061214, 450548861, 1843258603, 4107580753, 2211677639, 325883990, 1684777152, 4251122042, 2321926636, 335633487, 1661365465, 4195302755, 2366115317, 997073096, 1281953886, 3579855332, 2724688242, 1006888145, 1258607687, 3524101629, 2768942443, 901097722, 1119000684, 3686517206, 2898065728, 853044451, 1172266101, 3705015759, 2882616665, 651767980, 1373503546, 3369554304, 3218104598, 565507253, 1454621731, 3485111705, 3099436303, 671266974, 1594198024, 3322730930, 2970347812, 795835527, 1483230225, 3244367275, 3060149565, 1994146192, 31158534, 2563907772, 4023717930, 1907459465, 112637215, 2680153253, 3904427059, 2013776290, 251722036, 2517215374, 3775830040, 2137656763, 141376813, 2439277719, 3865271297, 1802195444, 476864866, 2238001368, 4066508878, 1812370925, 453092731, 2181625025, 4111451223, 1706088902, 314042704, 2344532202, 4240017532, 1658658271, 366619977, 2362670323, 4224994405, 1303535960, 984961486, 2747007092, 3569037538, 1256170817, 1037604311, 2765210733, 3554079995, 1131014506, 879679996, 2909243462, 3663771856, 1141124467, 855842277, 2852801631, 3708648649, 1342533948, 654459306, 3188396048, 3373015174, 1466479909, 544179635, 3110523913, 3462522015, 1591671054, 702138776, 2966460450, 3352799412, 1504918807, 783551873, 3082640443, 3233442989, 3988292384, 2596254646, 62317068, 1957810842, 3939845945, 2647816111, 81470997, 1943803523, 3814918930, 2489596804, 225274430, 2053790376, 3826175755, 2466906013, 167816743, 2097651377, 4027552580, 2265490386, 503444072, 1762050814, 4150417245, 2154129355, 426522225, 1852507879, 4275313526, 2312317920, 282753626, 1742555852, 4189708143, 2394877945, 397917763, 1622183637, 3604390888, 2714866558, 953729732, 1340076626, 3518719985, 2797360999, 1068828381, 1219638859, 3624741850, 2936675148, 906185462, 1090812512, 3747672003, 2825379669, 829329135, 1181335161, 3412177804, 3160834842, 628085408, 1382605366, 3423369109, 3138078467, 570562233, 1426400815, 3317316542, 2998733608, 733239954, 1555261956, 3268935591, 3050360625, 752459403, 1541320221, 2607071920, 3965973030, 1969922972, 40735498, 2617837225, 3943577151, 1913087877, 83908371, 2512341634, 3803740692, 2075208622, 213261112, 2463272603, 3855990285, 2094854071, 198958881, 2262029012, 4057260610, 1759359992, 534414190, 2176718541, 4139329115, 1873836001, 414664567, 2282248934, 4279200368, 1711684554, 285281116, 2405801727, 4167216745, 1634467795, 376229701, 2685067896, 3608007406, 1308918612, 956543938, 2808555105, 3495958263, 1231636301, 1047427035, 2932959818, 3654703836, 1088359270, 936918000, 2847714899, 3736837829, 1202900863, 817233897, 3183342108, 3401237130, 1404277552, 615818150, 3134207493, 3453421203, 1423857449, 601450431, 3009837614, 3294710456, 1567103746, 711928724, 3020668471, 3272380065, 1510334235, 755167117];

	uint c = crc;

	foreach(b; buf)
		c = crc_table[(c ^ b) & 0xff] ^ (c >> 8);

	return c;
}

// lol is just the chunk name
uint crc(in string lol, in ubyte[] buf){
	uint c = update_crc(0xffffffffL, cast(ubyte[]) lol);
	return update_crc(c, buf) ^ 0xffffffffL;
}

