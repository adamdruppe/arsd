/++
	DO NOT USE - ZERO STABILITY AT THIS TIME.

	Support for reading (and later, writing) .zip files.

	Currently a wrapper around phobos to change the interface for consistency
	and compatibility with my other modules.

	You're better off using Phobos [std.zip] for stability at this time.

	History:
		Added February 19, 2025
+/
module arsd.zip;

import arsd.core;

import std.zip;

// https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

/++

+/
class ZipFile {
	ZipArchive phobos;

	/++

	+/
	this(immutable(ubyte)[] fileData) {
		phobos = new ZipArchive(cast(void[]) fileData);
	}

	/// ditto
	this(FilePath filename) {
		import std.file;
		this(cast(immutable(ubyte)[]) std.file.read(filename.toString()));
	}

	/++
		Unstable, avoid.
	+/
	immutable(ubyte)[] getContent(string filename, bool allowEmptyIfNotExist = false) {
		if(filename !in phobos.directory) {
			if(allowEmptyIfNotExist)
				return null;
			throw ArsdException!"Zip content not found"(filename);
		}
		return cast(immutable(ubyte)[]) phobos.expand(phobos.directory[filename]);
	}
}
