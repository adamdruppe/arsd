/++
	A declarative file/stream loader/saver. You define structs with a handful of annotations, this read and writes them to/from files.
+/
module arsd.declarativeloader;

import std.range;

///
enum BigEndian;
///
enum LittleEndian;
/// @VariableLength indicates the value is saved in a MIDI like format
enum VariableLength;
/// @NumBytes!Field or @NumElements!Field controls length of embedded arrays
struct NumBytes(alias field) {}
/// ditto
struct NumElements(alias field) {}
/// @Tagged!Field indicates a tagged union. Each struct within should have @Tag(X) which is a value of Field
struct Tagged(alias field) {}
/// ditto
auto Tag(T)(T t) {
	return TagStruct!T(t);
}
/// For example `@presentIf("version >= 2") int addedInVersion2;`
struct presentIf { string code; }


struct TagStruct(T) { T t; }
struct MustBeStruct(T) { T t; }
/// The marked field is not in the actual file
enum NotSaved;
/// Insists the field must be a certain value, like for magic numbers
auto MustBe(T)(T t) {
	return MustBeStruct!T(t);
}

static bool fieldSaved(alias a)() {
	bool saved;
	static if(is(typeof(a.offsetof))) {
		saved = true;
		static foreach(attr; __traits(getAttributes, a))
			static if(is(attr == NotSaved))
				saved = false;
	}
	return saved;
}

static bool bigEndian(alias a)(bool def) {
	bool be = def;
	static foreach(attr; __traits(getAttributes, a)) {
		static if(is(attr == BigEndian))
			be = true;
		else static if(is(attr == LittleEndian))
			be = false;
	}
	return be;
}

static auto getTag(alias a)() {
	static foreach(attr; __traits(getAttributes, a)) {
		static if(is(typeof(attr) == TagStruct!T, T)) {
			return attr.t;
		}
	}
	assert(0);
}

union N(ty) {
	ty member;
	ubyte[ty.sizeof] bytes;
}

static bool fieldPresent(alias field, T)(T t) {
	bool p = true;
	static foreach(attr; __traits(getAttributes, field)) {
		static if(is(typeof(attr) == presentIf)) {
			bool p2 = false;
			with(t) p2 = mixin(attr.code);
			p = p && p2;
		}
	}
	return p;
}

/// input range of ubytes...
int loadFrom(T, Range)(ref T t, auto ref Range r, bool assumeBigEndian = false) {
	int bytesConsumed;
	string currentItem;

	import std.conv;
	try {

	ubyte next() {
		if(r.empty)
			throw new Exception(T.stringof ~ "." ~ currentItem ~ " trouble " ~ to!string(t));
		auto bfr = r.front;
		r.popFront;
		bytesConsumed++;
		return bfr;
	}

	bool endianness = bigEndian!T(assumeBigEndian);
	static foreach(memberName; __traits(allMembers, T)) {{
	currentItem = memberName;
	static if(is(typeof(__traits(getMember, T, memberName)))) {
		alias f = __traits(getMember, T, memberName);
		alias ty = typeof(f);
		static if(fieldSaved!f)
		if(fieldPresent!f(t)) {
			endianness = bigEndian!f(endianness);
			// FIXME VariableLength
			static if(is(ty : ulong) || is(ty : double)) {
				N!ty n;
				if(endianness) {
					foreach(i; 0 .. ty.sizeof) {
						version(BigEndian)
							n.bytes[i] = next();
						else
							n.bytes[$ - 1 - i] = next();
					}
				} else {
					foreach(i; 0 .. ty.sizeof) {
						version(BigEndian)
							n.bytes[$ - 1 - i] = next();
						else
							n.bytes[i] = next();
					}
				}

				// FIXME: MustBe

				__traits(getMember, t, memberName) = n.member;
			} else static if(is(ty == struct)) {
				bytesConsumed += loadFrom(__traits(getMember, t, memberName), r, endianness);
			} else static if(is(ty == union)) {
				static foreach(attr; __traits(getAttributes, ty))
					static if(is(attr == Tagged!Field, alias Field))
						enum tagField = __traits(identifier, Field);
				static assert(is(typeof(tagField)), "Unions need a Tagged UDA on the union type (not the member) indicating the field that identifies the union");

				auto tag = __traits(getMember, t, tagField);
				// find the child of the union matching the tag...
				bool found = false;
				static foreach(um; __traits(allMembers, ty)) {
					if(tag == getTag!(__traits(getMember, ty, um))) {
						bytesConsumed += loadFrom(__traits(getMember, __traits(getMember, t, memberName), um), r, endianness);
						found = true;
					}
				}
				if(!found) {
					import std.format;
					throw new Exception(format("found unknown union tag %s at %s", tag, t));
				}
			} else static if(is(ty == E[], E)) {
				static foreach(attr; __traits(getAttributes, f)) {
					static if(is(attr == NumBytes!Field, alias Field))
						ulong numBytesRemaining = __traits(getMember, t, __traits(identifier, Field));
					else static if(is(attr == NumElements!Field, alias Field)) {
						ulong numElementsRemaining = __traits(getMember, t, __traits(identifier, Field));
					}
				}

				static if(is(typeof(numBytesRemaining))) {
					static if(is(E : const(ubyte)) || is(E : const(char))) {
						while(numBytesRemaining) {
							__traits(getMember, t, memberName) ~= next;
							numBytesRemaining--;
						}
					} else {
						while(numBytesRemaining) {
							E piece;
							auto by = loadFrom(e, r, endianness);
							numBytesRemaining -= by;
							bytesConsumed += by;
							__traits(getMember, t, memberName) ~= piece;
						}
					}
				} else static if(is(typeof(numElementsRemaining))) {
					static if(is(E : const(ubyte)) || is(E : const(char))) {
						while(numElementsRemaining) {
							__traits(getMember, t, memberName) ~= next;
							numElementsRemaining--;
						}
					} else static if(is(E : const(ushort))) {
						while(numElementsRemaining) {
							ushort n;
							n = next << 8;
							n |= next;
							// FIXME all of this filth
							__traits(getMember, t, memberName) ~= n;
							numElementsRemaining--;
						}
					} else {
						while(numElementsRemaining) {
							//import std.stdio; writeln(memberName);
							E piece;
							auto by = loadFrom(piece, r, endianness);
							numElementsRemaining--;

							// such a filthy hack, needed for Java's mistake though :(
							static if(__traits(compiles, piece.takesTwoSlots())) {
								if(piece.takesTwoSlots()) {
									__traits(getMember, t, memberName) ~= piece;
									numElementsRemaining--;
								}
							}

							bytesConsumed += by;
							__traits(getMember, t, memberName) ~= piece;
						}
					}
				} else static assert(0, "no way to identify length... " ~ memberName);

			} else static assert(0, ty.stringof);
		}
	}
	}}

	} catch(Exception e) {
		throw new Exception(T.stringof ~ "." ~ currentItem ~ " trouble " ~ to!string(t), e.file, e.line, e);
	}

	return bytesConsumed;
}

int saveTo(T, Range)(ref T t, ref Range r, bool assumeBigEndian = false) {
	int bytesWritten;
	string currentItem;

	import std.conv;
	try {

	void write(ubyte b) {
		bytesWritten++;
		static if(is(Range == ubyte[]))
			r ~= b;
		else
			r.put(b);
	}

	bool endianness = bigEndian!T(assumeBigEndian);
	static foreach(memberName; __traits(allMembers, T)) {{
	currentItem = memberName;
	static if(is(typeof(__traits(getMember, T, memberName)))) {
		alias f = __traits(getMember, T, memberName);
		alias ty = typeof(f);
		static if(fieldSaved!f)
		if(fieldPresent!f(t)) {
			endianness = bigEndian!f(endianness);
			// FIXME VariableLength
			static if(is(ty : ulong) || is(ty : double)) {
				N!ty n;
				n.member = __traits(getMember, t, memberName);
				if(endianness) {
					foreach(i; 0 .. ty.sizeof) {
						version(BigEndian)
							write(n.bytes[i]);
						else
							write(n.bytes[$ - 1 - i]);
					}
				} else {
					foreach(i; 0 .. ty.sizeof) {
						version(BigEndian)
							write(n.bytes[$ - 1 - i]);
						else
							write(n.bytes[i]);
					}
				}

				// FIXME: MustBe
			} else static if(is(ty == struct)) {
				bytesWritten += saveTo(__traits(getMember, t, memberName), r, endianness);
			} else static if(is(ty == union)) {
				static foreach(attr; __traits(getAttributes, ty))
					static if(is(attr == Tagged!Field, alias Field))
						enum tagField = __traits(identifier, Field);
				static assert(is(typeof(tagField)), "Unions need a Tagged UDA on the union type (not the member) indicating the field that identifies the union");

				auto tag = __traits(getMember, t, tagField);
				// find the child of the union matching the tag...
				bool found = false;
				static foreach(um; __traits(allMembers, ty)) {
					if(tag == getTag!(__traits(getMember, ty, um))) {
						bytesWritten += saveTo(__traits(getMember, __traits(getMember, t, memberName), um), r, endianness);
						found = true;
					}
				}
				if(!found) {
					import std.format;
					throw new Exception(format("found unknown union tag %s at %s", tag, t));
				}
			} else static if(is(ty == E[], E)) {

				// the numBytesRemaining / numElementsRemaining thing here ASSUMING the
				// arrays are already the correct size. the struct itself could invariant that maybe

				foreach(item; __traits(getMember, t, memberName)) {
					static if(is(typeof(item) == struct)) {
						bytesWritten += saveTo(item, r, endianness);
					} else {
						static struct dummy {
							typeof(item) i;
						}
						dummy d = dummy(item);
						bytesWritten += saveTo(d, r, endianness);
					}
				}

			} else static assert(0, ty.stringof);
		}
	}
	}}

	} catch(Exception e) {
		throw new Exception(T.stringof ~ "." ~ currentItem ~ " save trouble " ~ to!string(t), e.file, e.line, e);
	}

	return bytesWritten;
}

unittest {
	static struct A {
		int a;
		@presentIf("a > 5") int b;
		int c;
		@NumElements!c ubyte[] d;
	}

	A a;
	a.loadFrom(cast(ubyte[]) [1, 1, 0, 0, 7, 0, 0, 0, 3, 0, 0, 0, 6, 7, 8]);

	assert(a.a == 257);
	assert(a.b == 7);
	assert(a.c == 3);
	assert(a.d == [6,7,8]);

	a = A.init;

	a.loadFrom(cast(ubyte[]) [0, 0, 0, 0, 7, 0, 0, 0,1,2,3,4,5,6,7]);
	assert(a.b == 0);
	assert(a.c == 7);
	assert(a.d == [1,2,3,4,5,6,7]);

	a.a = 44;
	a.c = 3;
	a.d = [5,4,3];

	ubyte[] saved;

	a.saveTo(saved);

	A b;
	b.loadFrom(saved);

	assert(a == b);
}
