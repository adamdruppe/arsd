/++
	String manipulation functions.

	See_Also:
		To get a substring, you can use the built-in array slice operator.

		For reading various encodings into a standard string, see [arsd.characterencodings].

		For converting things to and from strings, see [arsd.conv].

		For sorting an array of strings, see... std.algorithm for now but maybe here later.

	History:
		Added May 23, 2025
+/
module arsd.string;

static import arsd.core;

/// Public interface to arsd.core
alias startsWith = arsd.core.startsWith;
/// ditto
alias endsWith = arsd.core.endsWith;
/// ditto
alias indexOf = arsd.core.indexOf;

// replace? replaceFirst, replaceAll, replaceAny etc

// limitSize - truncates to the last code point under the given length of code units

/// Strips (aka trims) leading and/or trailing whitespace from the string.
alias strip = arsd.core.stripInternal;
/// ditto
deprecated("D calls this `strip` instead") alias trim = strip;

/// ditto
alias stripRight = arsd.core.stripInternal;
/// ditto
deprecated("D calls this `stripRight` instead") alias trimRight = stripRight;

// stripLeft? variants where you can list the chars to strip?

// ascii to upper, to lower, capitalize words, from camel case to dash separated

// ********* UTF **************
// utf8 stride and such?
// get the starting code unit of the given point in the string
// get the next code unit start after the given point (compare upstream popFront)
// iterate over a string putting a replacement char in any invalid utf 8 spot

// ********* C INTEROP **************

alias stringz = arsd.core.stringz;
// CharzBuffer
// WCharzBuffer
