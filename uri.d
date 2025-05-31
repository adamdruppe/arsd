/++
	Future public interface to the Uri struct and encode/decode component functions.

	History:
		Added May 26, 2025
+/
module arsd.uri;

import arsd.core;

alias encodeUriComponent = arsd.core.encodeUriComponent;
alias decodeUriComponent = arsd.core.decodeUriComponent;

// phobos compatibility names
alias encodeComponent = encodeUriComponent;
alias decodeComponent = decodeUriComponent;

// FIXME: merge and pull Uri struct from http2 and cgi. maybe via core.

// might also put base64 in here....
