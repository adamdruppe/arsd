module arsd.sha;

/*
	By Adam D. Ruppe, 26 Nov 2009
	I release this file into the public domain
*/
import std.stdio;

immutable(ubyte)[/*20*/] SHA1(T)(T data) if(isInputRange!(T)) /*const(ubyte)[] data)*/ {
	uint[5] h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0];

	SHARange!(T) range;
	static if(is(data == SHARange))
		range = data;
	else {
		range.r = data;
	}
	/*
		ubyte[] message = data.dup;
		message ~= 0b1000_0000;
		while(((message.length+8) * 8) % 512)
			message ~= 0;

		ulong originalLength = cast(ulong) data.length * 8;

		for(int a = 7; a >= 0; a--)
			message ~= (originalLength >> (a*8)) & 0xff; // to big-endian

		assert(((message.length * 8) % 512) == 0);

		uint pos = 0;
		while(pos < message.length) {
	*/
		while(!range.empty) {
			uint[80] words;

			for(int a = 0; a < 16; a++) {
				for(int b = 3; b >= 0; b--) {
					words[a] |= cast(uint)(range.front()) << (b*8);
					range.popFront;
				//	words[a] |= cast(uint)(message[pos]) << (b*8);
				//	pos++;
				}
			}

			for(int a = 16; a < 80; a++) {
				uint t  = words[a-3];
				     t ^= words[a-8];
				     t ^= words[a-14];
				     t ^= words[a-16];
				asm { rol t, 1; }
				words[a] = t;
			}

			uint a = h[0];
			uint b = h[1];
			uint c = h[2];
			uint d = h[3];
			uint e = h[4];

			for(int i = 0; i < 80; i++) {
				uint f, k;
				if(i >= 0 && i < 20) {
					f = (b & c) | ((~b) & d);
					k = 0x5A827999;
				} else
				if(i >= 20 && i < 40) {
					f = b ^ c ^ d;
					k = 0x6ED9EBA1;
				} else
				if(i >= 40 && i < 60) {
					f = (b & c) | (b & d) | (c & d);
					k = 0x8F1BBCDC;
				} else
				if(i >= 60 && i < 80) {
					f = b ^ c ^ d;
					k = 0xCA62C1D6;
				} else assert(0);

				uint temp;
				asm { 
					mov EAX, a;
					rol EAX, 5;
					add EAX, f;
					add EAX, e;
					add EAX, k;
					mov temp, EAX;
				}
				temp += words[i];
				e = d;
				d = c;
				asm {
					mov EAX, b;
					rol EAX, 30;
					mov c, EAX;
				}
				b = a;
				a = temp;
			}

			h[0] += a;
			h[1] += b;
			h[2] += c;
			h[3] += d;
			h[4] += e;
		}


		ubyte[] hash;
		for(int j = 0; j < 5; j++)
		for(int i = 3; i >= 0; i--) {
			hash ~= cast(ubyte)(h[j] >> (i*8))&0xff;
		}

		return hash.idup;
}

import core.stdc.stdio;
import std.string;
// i wish something like this was in phobos.
struct FileByByte {
	FILE* fp;
	this(string filename) {
		fp = fopen(toStringz(filename), "rb".ptr);
		if(fp is null)
			throw new Exception("couldn't open " ~ filename);
		popFront();
	}

	// FIXME: this should prolly be recounted or something. blargh.

	~this() {
		if(fp !is null)
			fclose(fp);
	}

	void popFront() {
		f = cast(ubyte) fgetc(fp);
	}

	@property ubyte front() {
		return f;
	}

	@property bool empty() {
		return feof(fp) ? true : false;
	}

	ubyte f;
}

import std.range;

// This does the preprocessing of input data, fetching one byte at a time of the data until it is empty, then the padding and length at the end
template SHARange(T) if(isInputRange!(T)) {
	struct SHARange {
		T r;

		bool empty() {
			return state == 5;
		}

		void popFront() {
		static int lol = 0;
			if(state == 0) {
				r.popFront;
				/*
				static if(__traits(compiles, r.front.length))
					length += r.front.length;
				else
					length += r.front().sizeof;
				*/
				length++; // FIXME

				if(r.empty) {
					state = 1;
					position = 2;
					current = 0x80;
				}
			} else {
				bool hackforward = false;
				if(state == 1) {
					current = 0x0;
					state = 2;
					if((((position + length + 8) * 8) % 512) == 8) {
						position--;
						hackforward = true;
					}
					goto proceed;
				//	position++;
				} else if( state == 2) {
				proceed:
					if(!(((position + length + 8) * 8) % 512)) {
						state = 3;
						position = 7;
						length *= 8;
						if(hackforward)
							goto proceedmoar;
					} else
						position++;
				} else if (state == 3) {
				proceedmoar:
					current = (length >> (position*8)) & 0xff;
					if(position == 0)
						state = 4;
					else
						position--;
				} else if (state == 4) {
					current = 0xff;
					state = 5;
				}
			}
		}

		ubyte front() {
			if(state == 0) {
				return cast(ubyte) r.front();
			}
			assert(state != 5);
			//writefln("%x", current);
			return current;
		}

		ubyte current;
		uint position;
		ulong length;
		int state = 0; // reading range, reading appended bit, reading padding, reading length, done
	}
}

immutable(ubyte)[] SHA256(T)(T data) if ( isInputRange!(T)) {
	uint[8] h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
	immutable(uint[64]) k = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
			0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
			0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
			0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
			0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
			0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
			0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
			0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];

	SHARange!(T) range;
	static if(is(data == SHARange))
		range = data;
	else {
		range.r = data;
	}
/*
   	ubyte[] message = cast(ubyte[]) data.dup;
	message ~= 0b1000_0000;
	while(((message.length+8) * 8) % 512)
		message ~= 0;

	ulong originalLength = cast(ulong) data.length * 8;

	for(int a = 7; a >= 0; a--)
		message ~= (originalLength >> (a*8)) & 0xff; // to big-endian

	assert(((message.length * 8) % 512) == 0);
*/
//	uint pos = 0;
	while(!range.empty) {
//	while(pos < message.length) {
		uint[64] words;

		for(int a = 0; a < 16; a++) {
			for(int b = 3; b >= 0; b--) {
				words[a] |= cast(uint)(range.front()) << (b*8);
				//words[a] |= cast(uint)(message[pos]) << (b*8);
				range.popFront;
//				pos++;
			}
		}

		for(int a = 16; a < 64; a++) {
			uint t1 = words[a-15];
			asm {
				mov EAX, t1;
				mov EBX, EAX;
				mov ECX, EAX;
				ror EAX, 7;
				ror EBX, 18;
				shr ECX, 3;
				xor EAX, EBX;
				xor EAX, ECX;
				mov t1, EAX;
			}
			uint t2 = words[a-2];
			asm {
				mov EAX, t2;
				mov EBX, EAX;
				mov ECX, EAX;
				ror EAX, 17;
				ror EBX, 19;
				shr ECX, 10;
				xor EAX, EBX;
				xor EAX, ECX;
				mov t2, EAX;
			}

			words[a] = words[a-16] + t1 + words[a-7] + t2;
		}

		uint A = h[0];
		uint B = h[1];
		uint C = h[2];
		uint D = h[3];
		uint E = h[4];
		uint F = h[5];
		uint G = h[6];
		uint H = h[7];

		for(int i = 0; i < 64; i++) {
			uint s0;
			asm {
				mov EAX, A;
				mov EBX, EAX;
				mov ECX, EAX;
				ror EAX, 2;
				ror EBX, 13;
				ror ECX, 22;
				xor EAX, EBX;
				xor EAX, ECX;
				mov s0, EAX;
			}
			uint maj = (A & B) ^ (A & C) ^ (B & C);
			uint t2 = s0 + maj;
			uint s1;
			asm {
				mov EAX, E;
				mov EBX, EAX;
				mov ECX, EAX;
				ror EAX, 6;
				ror EBX, 11;
				ror ECX, 25;
				xor EAX, EBX;
				xor EAX, ECX;
				mov s1, EAX;
			}
			uint ch = (E & F) ^ ((~E) & G);
			uint t1 = H + s1 + ch + k[i] + words[i];

			H = G;
			G = F;
			F = E;
			E = D + t1;
			D = C;
			C = B;
			B = A;
			A = t1 + t2;
		}

		h[0] += A;
		h[1] += B;
		h[2] += C;
		h[3] += D;
		h[4] += E;
		h[5] += F;
		h[6] += G;
		h[7] += H;
	}

	ubyte[] hash;
	for(int j = 0; j < 8; j++)
	for(int i = 3; i >= 0; i--) {
		hash ~= cast(ubyte)(h[j] >> (i*8))&0xff;
	}

	return hash.idup;
}

import std.exception;

string hashToString(const(ubyte)[] hash) {
	char[] s;

	s.length = hash.length * 2;

	char toHex(int a) {
		if(a < 10)
			return cast(char) (a + '0');
		else
			return cast(char) (a + 'a' - 10);
	}

	for(int a = 0; a < hash.length; a++) {
		s[a*2]   = toHex(hash[a] >> 4);
		s[a*2+1] = toHex(hash[a] & 0x0f);
	}

	return assumeUnique(s);
}
/*
string tee(string t) {
	writefln("%s", t);
	return t;
}
*/
unittest {
	assert(hashToString(SHA1("abc")) == "a9993e364706816aba3e25717850c26c9cd0d89d");
	assert(hashToString(SHA1("sdfj983yr2ih")) == "335f1f5a4af4aa2c8e93b88d69dda2c22baeb94d");
	assert(hashToString(SHA1("$%&^54ylkufg09fd7f09sa7udsiouhcx987yw98etf7yew98yfds987f632<F7>uw90ruds09fudsf09dsuhfoidschyds98fydovipsdaidsd9fsa GA UIA duisguifgsuifgusaufisgfuisafguisagasuidgsaufsauifhuisahfuisafaoisahasiosafhffdasasdisayhfdoisayf8saiuhgduifyds8fiydsufisafoisayf8sayfd98wqyr98wqy98sayd98sayd098sayd09sayd98sayd98saicxyhckxnvjbpovc pousa09cusa 09csau csa9 dusa90d usa9d0sau dsa90 as09posufpodsufodspufdspofuds 9tu sapfusaa daosjdoisajdsapoihdsaiodyhsaioyfg d98ytewq89rysa 98yc98sdxych sa89ydsa89dy sa98ydas98c ysx9v8y cxv89ysd f8ysa89f ysa89fd sg8yhds9g8 rfjcxhvslkhdaiosy09wq7r987t98e7ys98aIYOIYOIY)(*YE (*WY *A(YSA* HDUIHDUIAYT&*ATDAUID AUI DUIAT DUIAG saoidusaoid ysqoid yhsaduiayh UIZYzuI YUIYEDSA UIDYUIADYISA YTDGS UITGUID")) == "e38a1220eaf8103d6176df2e0dd0a933e2f52001");

	assert(hashToString(SHA256("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
	assert(hashToString(SHA256("$%&^54ylkufg09fd7f09sa7udsiouhcx987yw98etf7yew98yfds987f632<F7>uw90ruds09fudsf09dsuhfoidschyds98fydovipsdaidsd9fsa GA UIA duisguifgsuifgusaufisgfuisafguisagasuidgsaufsauifhuisahfuisafaoisahasiosafhffdasasdisayhfdoisayf8saiuhgduifyds8fiydsufisafoisayf8sayfd98wqyr98wqy98sayd98sayd098sayd09sayd98sayd98saicxyhckxnvjbpovc pousa09cusa 09csau csa9 dusa90d usa9d0sau dsa90 as09posufpodsufodspufdspofuds 9tu sapfusaa daosjdoisajdsapoihdsaiodyhsaioyfg d98ytewq89rysa 98yc98sdxych sa89ydsa89dy sa98ydas98c ysx9v8y cxv89ysd f8ysa89f ysa89fd sg8yhds9g8 rfjcxhvslkhdaiosy09wq7r987t98e7ys98aIYOIYOIY)(*YE (*WY *A(YSA* HDUIHDUIAYT&*ATDAUID AUI DUIAT DUIAG saoidusaoid ysqoid yhsaduiayh UIZYzuI YUIYEDSA UIDYUIADYISA YTDGS UITGUID")) == "64ff79c67ad5ddf9ba5b2d83e07a6937ef9a5b4eb39c54fe1e913e21aad0e95c");
}
/*
void main() {
	auto hash = SHA256(InputByChar(stdin));
	writefln("%s", hashToString(hash));
}
*/
