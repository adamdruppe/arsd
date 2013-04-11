// helper program is in ~me/encodings.d to make more tables from wikipedia

/**
	This is meant to help get data from the wild into utf8 strings
	so you can work with them easily inside D.

	The main function is convertToUtf8(), which takes a byte array
	of your raw data (a byte array because it isn't really a D string
	yet until it is utf8), and a runtime string telling it's current
	encoding.

	The current encoding argument is meant to come from the data's
	metadata, and is flexible on exact format - it is case insensitive
	and takes several variations on the names.

	This way, you should be able to send it the encoding string directly
	from an XML document, a HTTP header, or whatever you have, and it
	ought to just work.

	Example:
		auto data = cast(immutable(ubyte)[])
			std.file.read("my-windows-file.txt");
		string utf8String = convertToUtf8(data, "windows-1252");
		// utf8String can now be used


	The encodings currently implemented for decoding are:
		UTF-8 (a no-op; it simply casts the array to string)
		UTF-16,
		UTF-32,
		Windows-1252,
		ISO 8859 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, and 16.

	It treats ISO 8859-1, Latin-1, and Windows-1252 the same way, since
	those labels are pretty much de-facto the same thing in wild documents.


	This module currently makes no attempt to look at control characters.
*/
module arsd.characterencodings;

import std.string;
import std.array;
import std.conv;

/// Takes data from a given character encoding and returns it as UTF-8
string convertToUtf8(immutable(ubyte)[] data, string dataCharacterEncoding) {
	// just to normalize the passed string...
	auto encoding = dataCharacterEncoding.toLower();
	encoding = encoding.replace(" ", "");
	encoding = encoding.replace("-", "");
	encoding = encoding.replace("_", "");
	// should be good enough.

	switch(encoding) {
		default:
			throw new Exception("I don't know how to convert " ~ dataCharacterEncoding ~ " to UTF-8");
		// since the input is immutable, these are ok too.
		// just want to cover all the bases with one runtime function.
		case "utf16":
		case "utf16le":
			return to!string(cast(wstring) data);
		case "utf32":
		case "utf32le":
			return to!string(cast(dstring) data);
		// FIXME: does the big endian to little endian conversion work?
		case "ascii":
		case "usascii": // utf-8 is a superset of ascii
		case "utf8":
			return cast(string) data;
		// and now the various 8 bit encodings we support.
		case "windows1252":
			return decodeImpl(data, ISO_8859_1, Windows_1252);
		case "windows1251":
			return decodeImpl(data, Windows_1251, Windows_1251_Lower);
		case "koi8r":
			return decodeImpl(data, KOI8_R, KOI8_R_Lower);
		case "latin1":
		case "iso88591":
			// Why am I putting Windows_1252 here? A lot of
			// stuff in the wild is mislabeled, so this will
			// do some good in the Just Works department.
			// Regardless, I don't handle the
			// control char set in that zone anyway right now.
			return decodeImpl(data, ISO_8859_1, Windows_1252);
		case "iso88592":
			return decodeImpl(data, ISO_8859_2);
		case "iso88593":
			return decodeImpl(data, ISO_8859_3);
		case "iso88594":
			return decodeImpl(data, ISO_8859_4);
		case "iso88595":
			return decodeImpl(data, ISO_8859_5);
		case "iso88596":
			return decodeImpl(data, ISO_8859_6);
		case "iso88597":
			return decodeImpl(data, ISO_8859_7);
		case "iso88598":
			return decodeImpl(data, ISO_8859_8);
		case "iso88599":
			return decodeImpl(data, ISO_8859_9);
		case "iso885910":
			return decodeImpl(data, ISO_8859_10);
		case "iso885911":
			return decodeImpl(data, ISO_8859_11);
		case "iso885913":
			return decodeImpl(data, ISO_8859_13);
		case "iso885914":
			return decodeImpl(data, ISO_8859_14);
		case "iso885915":
			return decodeImpl(data, ISO_8859_15);
		case "iso885916":
			return decodeImpl(data, ISO_8859_16);
	}

	assert(0);
}

/// Tries to determine the current encoding based on the content.
/// Only really helps with the UTF variants.
/// Returns null if it can't be reasonably sure.
string tryToDetermineEncoding(in ubyte[] rawdata) {
	import std.utf;
	try {
		validate!string(cast(string) rawdata);
		// the odds of non stuff validating as utf-8 are pretty low
		return "UTF-8";
	} catch(UTFException t) {
		// it's definitely not UTF-8!
		// we'll look at the first few characters. If there's a
		// BOM, it's probably UTF-16 or UTF-32

		if(rawdata.length > 4) {
			// not checking for utf8 bom; if it was that, we
			// wouldn't be here.
			if(rawdata[0] == 0xff && rawdata[1] == 0xfe)
				return "UTF-16 LE";
			else if(rawdata[0] == 0xfe && rawdata[1] == 0xff)
				return "UTF-16 BE";
			else if(rawdata[0] == 0x00 && rawdata[1] == 0x00
			     && rawdata[2] == 0xfe && rawdata[3] == 0xff)
				return "UTF-32 BE";
			else if(rawdata[0] == 0xff && rawdata[1] == 0xfe
			     && rawdata[2] == 0x00 && rawdata[3] == 0x00)
				return "UTF-32 LE";
			else {
				// this space is intentionally left blank
			}
		}
	}

	// we don't know with enough confidence. The app will have to find another way.
	return null;
}

// this function actually does the work, using the translation tables
// below.
string decodeImpl(in ubyte[] data, in dchar[] chars160to255, in dchar[] chars128to159 = null, in dchar[] chars0to127 = null)
	in {
		assert(chars160to255.length == 256 - 160);
		assert(chars128to159 is null || chars128to159.length == 160 - 128);
		assert(chars0to127 is null || chars0to127.length == 128 - 0);
	}
	out(ret) {
		import std.utf;
		validate(ret);
	}
body {
	string utf8;

	/// I'm sure this could be a lot more efficient, but whatever, it
	/// works.
	foreach(octet; data) {
		if(octet < 128) {
			if(chars0to127 !is null)
				utf8 ~= chars0to127[octet];
			else
				utf8 ~= cast(char) octet; // ascii is the same
		} else if(octet < 160) {
			if(chars128to159 !is null)
				utf8 ~= chars128to159[octet - 128];
			else
				utf8 ~= " ";
		} else {
			utf8 ~= chars160to255[octet - 160];
		}
	}

	return utf8;
}


// Here come the translation tables.

// this table gives characters for decimal 128 through 159.
// the < 128 characters are the same as ascii, and > 159 the same as
// iso 8859 1, seen below.
immutable dchar[] Windows_1252 = [
	'€', ' ', '‚', 'ƒ', '„', '…', '†', '‡',
	'ˆ', '‰', 'Š', '‹', 'Œ', ' ', 'Ž', ' ',
	' ', '‘', '’', '“', '”', '•', '–', '—',
	'˜', '™', 'š', '›', 'œ', ' ', 'ž', 'Ÿ'];

// the following tables give the characters from decimal 160 up to 255
// in the given encodings.

immutable dchar[] ISO_8859_1 = [ 
	' ', '¡', '¢', '£', '¤', '¥', '¦', '§',
	'¨', '©', 'ª', '«', '¬', '­', '®', '¯',
	'°', '±', '²', '³', '´', 'µ', '¶', '·',
	'¸', '¹', 'º', '»', '¼', '½', '¾', '¿',
	'À', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'Æ', 'Ç',
	'È', 'É', 'Ê', 'Ë', 'Ì', 'Í', 'Î', 'Ï',
	'Ð', 'Ñ', 'Ò', 'Ó', 'Ô', 'Õ', 'Ö', '×',
	'Ø', 'Ù', 'Ú', 'Û', 'Ü', 'Ý', 'Þ', 'ß',
	'à', 'á', 'â', 'ã', 'ä', 'å', 'æ', 'ç',
	'è', 'é', 'ê', 'ë', 'ì', 'í', 'î', 'ï',
	'ð', 'ñ', 'ò', 'ó', 'ô', 'õ', 'ö', '÷',
	'ø', 'ù', 'ú', 'û', 'ü', 'ý', 'þ', 'ÿ'];

immutable dchar[] ISO_8859_2 = [ 
	' ', 'Ą', '˘', 'Ł', '¤', 'Ľ', 'Ś', '§',
	'¨', 'Š', 'Ş', 'Ť', 'Ź', '­', 'Ž', 'Ż',
	'°', 'ą', '˛', 'ł', '´', 'ľ', 'ś', 'ˇ',
	'¸', 'š', 'ş', 'ť', 'ź', '˝', 'ž', 'ż',
	'Ŕ', 'Á', 'Â', 'Ă', 'Ä', 'Ĺ', 'Ć', 'Ç',
	'Č', 'É', 'Ę', 'Ë', 'Ě', 'Í', 'Î', 'Ď',
	'Đ', 'Ń', 'Ň', 'Ó', 'Ô', 'Ő', 'Ö', '×',
	'Ř', 'Ů', 'Ú', 'Ű', 'Ü', 'Ý', 'Ţ', 'ß',
	'ŕ', 'á', 'â', 'ă', 'ä', 'ĺ', 'ć', 'ç',
	'č', 'é', 'ę', 'ë', 'ě', 'í', 'î', 'ď',
	'đ', 'ń', 'ň', 'ó', 'ô', 'ő', 'ö', '÷',
	'ř', 'ů', 'ú', 'ű', 'ü', 'ý', 'ţ', '˙'];

immutable dchar[] ISO_8859_3 = [ 
	' ', 'Ħ', '˘', '£', '¤', ' ', 'Ĥ', '§',
	'¨', 'İ', 'Ş', 'Ğ', 'Ĵ', '­', ' ', 'Ż',
	'°', 'ħ', '²', '³', '´', 'µ', 'ĥ', '·',
	'¸', 'ı', 'ş', 'ğ', 'ĵ', '½', ' ', 'ż',
	'À', 'Á', 'Â', ' ', 'Ä', 'Ċ', 'Ĉ', 'Ç',
	'È', 'É', 'Ê', 'Ë', 'Ì', 'Í', 'Î', 'Ï',
	' ', 'Ñ', 'Ò', 'Ó', 'Ô', 'Ġ', 'Ö', '×',
	'Ĝ', 'Ù', 'Ú', 'Û', 'Ü', 'Ŭ', 'Ŝ', 'ß',
	'à', 'á', 'â', ' ', 'ä', 'ċ', 'ĉ', 'ç',
	'è', 'é', 'ê', 'ë', 'ì', 'í', 'î', 'ï',
	' ', 'ñ', 'ò', 'ó', 'ô', 'ġ', 'ö', '÷',
	'ĝ', 'ù', 'ú', 'û', 'ü', 'ŭ', 'ŝ', '˙'];

immutable dchar[] ISO_8859_4 = [ 
	' ', 'Ą', 'ĸ', 'Ŗ', '¤', 'Ĩ', 'Ļ', '§',
	'¨', 'Š', 'Ē', 'Ģ', 'Ŧ', '­', 'Ž', '¯',
	'°', 'ą', '˛', 'ŗ', '´', 'ĩ', 'ļ', 'ˇ',
	'¸', 'š', 'ē', 'ģ', 'ŧ', 'Ŋ', 'ž', 'ŋ',
	'Ā', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'Æ', 'Į',
	'Č', 'É', 'Ę', 'Ë', 'Ė', 'Í', 'Î', 'Ī',
	'Đ', 'Ņ', 'Ō', 'Ķ', 'Ô', 'Õ', 'Ö', '×',
	'Ø', 'Ų', 'Ú', 'Û', 'Ü', 'Ũ', 'Ū', 'ß',
	'ā', 'á', 'â', 'ã', 'ä', 'å', 'æ', 'į',
	'č', 'é', 'ę', 'ë', 'ė', 'í', 'î', 'ī',
	'đ', 'ņ', 'ō', 'ķ', 'ô', 'õ', 'ö', '÷',
	'ø', 'ų', 'ú', 'û', 'ü', 'ũ', 'ū', '˙'];

immutable dchar[] ISO_8859_5 = [ 
	' ', 'Ё', 'Ђ', 'Ѓ', 'Є', 'Ѕ', 'І', 'Ї',
	'Ј', 'Љ', 'Њ', 'Ћ', 'Ќ', '­', 'Ў', 'Џ',
	'А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'З',
	'И', 'Й', 'К', 'Л', 'М', 'Н', 'О', 'П',
	'Р', 'С', 'Т', 'У', 'Ф', 'Х', 'Ц', 'Ч',
	'Ш', 'Щ', 'Ъ', 'Ы', 'Ь', 'Э', 'Ю', 'Я',
	'а', 'б', 'в', 'г', 'д', 'е', 'ж', 'з',
	'и', 'й', 'к', 'л', 'м', 'н', 'о', 'п',
	'р', 'с', 'т', 'у', 'ф', 'х', 'ц', 'ч',
	'ш', 'щ', 'ъ', 'ы', 'ь', 'э', 'ю', 'я',
	'№', 'ё', 'ђ', 'ѓ', 'є', 'ѕ', 'і', 'ї',
	'ј', 'љ', 'њ', 'ћ', 'ќ', '§', 'ў', 'џ'];

immutable dchar[] ISO_8859_6 = [ 
	' ', ' ', ' ', ' ', '¤', ' ', ' ', ' ',
	' ', ' ', ' ', ' ', '،', '­', ' ', ' ',
	' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
	' ', ' ', ' ', '؛', ' ', ' ', ' ', '؟',
	' ', 'ء', 'آ', 'أ', 'ؤ', 'إ', 'ئ', 'ا',
	'ب', 'ة', 'ت', 'ث', 'ج', 'ح', 'خ', 'د',
	'ذ', 'ر', 'ز', 'س', 'ش', 'ص', 'ض', 'ط',
	'ظ', 'ع', 'غ', ' ', ' ', ' ', ' ', ' ',
	'ـ', 'ف', 'ق', 'ك', 'ل', 'م', 'ن', 'ه',
	'و', 'ى', 'ي', 'ً', 'ٌ', 'ٍ', 'َ', 'ُ',
	'ِ', 'ّ', 'ْ', ' ', ' ', ' ', ' ', ' ',
	' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '];

immutable dchar[] ISO_8859_7 = [ 
	' ', '‘', '’', '£', '€', '₯', '¦', '§',
	'¨', '©', 'ͺ', '«', '¬', '­', ' ', '―',
	'°', '±', '²', '³', '΄', '΅', 'Ά', '·',
	'Έ', 'Ή', 'Ί', '»', 'Ό', '½', 'Ύ', 'Ώ',
	'ΐ', 'Α', 'Β', 'Γ', 'Δ', 'Ε', 'Ζ', 'Η',
	'Θ', 'Ι', 'Κ', 'Λ', 'Μ', 'Ν', 'Ξ', 'Ο',
	'Π', 'Ρ', ' ', 'Σ', 'Τ', 'Υ', 'Φ', 'Χ',
	'Ψ', 'Ω', 'Ϊ', 'Ϋ', 'ά', 'έ', 'ή', 'ί',
	'ΰ', 'α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η',
	'θ', 'ι', 'κ', 'λ', 'μ', 'ν', 'ξ', 'ο',
	'π', 'ρ', 'ς', 'σ', 'τ', 'υ', 'φ', 'χ',
	'ψ', 'ω', 'ϊ', 'ϋ', 'ό', 'ύ', 'ώ', ' '];

immutable dchar[] ISO_8859_8 = [ 
	' ', ' ', '¢', '£', '¤', '¥', '¦', '§',
	'¨', '©', '×', '«', '¬', '­', '®', '¯',
	'°', '±', '²', '³', '´', 'µ', '¶', '·',
	'¸', '¹', '÷', '»', '¼', '½', '¾', ' ',
	' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
	' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
	' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
	' ', ' ', ' ', ' ', ' ', ' ', ' ', '‗',
	'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח',
	'ט', 'י', 'ך', 'כ', 'ל', 'ם', 'מ', 'ן',
	'נ', 'ס', 'ע', 'ף', 'פ', 'ץ', 'צ', 'ק',
	//                        v    v    those are wrong
	'ר', 'ש', 'ת', ' ', ' ', ' ', ' ', ' ']; // FIXME:  those ones marked wrong are supposed to be left to right and right to left markers, not spaces. lol maybe it isn't wrong

immutable dchar[] ISO_8859_9 = [ 
	' ', '¡', '¢', '£', '¤', '¥', '¦', '§',
	'¨', '©', 'ª', '«', '¬', '­', '®', '¯',
	'°', '±', '²', '³', '´', 'µ', '¶', '·',
	'¸', '¹', 'º', '»', '¼', '½', '¾', '¿',
	'À', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'Æ', 'Ç',
	'È', 'É', 'Ê', 'Ë', 'Ì', 'Í', 'Î', 'Ï',
	'Ğ', 'Ñ', 'Ò', 'Ó', 'Ô', 'Õ', 'Ö', '×',
	'Ø', 'Ù', 'Ú', 'Û', 'Ü', 'İ', 'Ş', 'ß',
	'à', 'á', 'â', 'ã', 'ä', 'å', 'æ', 'ç',
	'è', 'é', 'ê', 'ë', 'ì', 'í', 'î', 'ï',
	'ğ', 'ñ', 'ò', 'ó', 'ô', 'õ', 'ö', '÷',
	'ø', 'ù', 'ú', 'û', 'ü', 'ı', 'ş', 'ÿ'];

immutable dchar[] ISO_8859_10 = [ 
	' ', 'Ą', 'Ē', 'Ģ', 'Ī', 'Ĩ', 'Ķ', '§',
	'Ļ', 'Đ', 'Š', 'Ŧ', 'Ž', '­', 'Ū', 'Ŋ',
	'°', 'ą', 'ē', 'ģ', 'ī', 'ĩ', 'ķ', '·',
	'ļ', 'đ', 'š', 'ŧ', 'ž', '―', 'ū', 'ŋ',
	'Ā', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'Æ', 'Į',
	'Č', 'É', 'Ę', 'Ë', 'Ė', 'Í', 'Î', 'Ï',
	'Ð', 'Ņ', 'Ō', 'Ó', 'Ô', 'Õ', 'Ö', 'Ũ',
	'Ø', 'Ų', 'Ú', 'Û', 'Ü', 'Ý', 'Þ', 'ß',
	'ā', 'á', 'â', 'ã', 'ä', 'å', 'æ', 'į',
	'č', 'é', 'ę', 'ë', 'ė', 'í', 'î', 'ï',
	'ð', 'ņ', 'ō', 'ó', 'ô', 'õ', 'ö', 'ũ',
	'ø', 'ų', 'ú', 'û', 'ü', 'ý', 'þ', 'ĸ'];

immutable dchar[] ISO_8859_11 = [ 
	' ', 'ก', 'ข', 'ฃ', 'ค', 'ฅ', 'ฆ', 'ง',
	'จ', 'ฉ', 'ช', 'ซ', 'ฌ', 'ญ', 'ฎ', 'ฏ',
	'ฐ', 'ฑ', 'ฒ', 'ณ', 'ด', 'ต', 'ถ', 'ท',
	'ธ', 'น', 'บ', 'ป', 'ผ', 'ฝ', 'พ', 'ฟ',
	'ภ', 'ม', 'ย', 'ร', 'ฤ', 'ล', 'ฦ', 'ว',
	'ศ', 'ษ', 'ส', 'ห', 'ฬ', 'อ', 'ฮ', 'ฯ',
	'ะ', 'ั', 'า', 'ำ', 'ิ', 'ี', 'ึ', 'ื',
	'ุ', 'ู', 'ฺ', ' ', ' ', ' ', ' ', '฿',
	'เ', 'แ', 'โ', 'ใ', 'ไ', 'ๅ', 'ๆ', '็',
	'่', '้', '๊', '๋', '์', 'ํ', '๎', '๏',
	'๐', '๑', '๒', '๓', '๔', '๕', '๖', '๗',
	'๘', '๙', '๚', '๛', ' ', ' ', ' ', ' '];

immutable dchar[] ISO_8859_13 = [ 
	' ', '”', '¢', '£', '¤', '„', '¦', '§',
	'Ø', '©', 'Ŗ', '«', '¬', '­', '®', 'Æ',
	'°', '±', '²', '³', '“', 'µ', '¶', '·',
	'ø', '¹', 'ŗ', '»', '¼', '½', '¾', 'æ',
	'Ą', 'Į', 'Ā', 'Ć', 'Ä', 'Å', 'Ę', 'Ē',
	'Č', 'É', 'Ź', 'Ė', 'Ģ', 'Ķ', 'Ī', 'Ļ',
	'Š', 'Ń', 'Ņ', 'Ó', 'Ō', 'Ő', 'Ö', '×',
	'Ų', 'Ł', 'Ś', 'Ū', 'Ü', 'Ż', 'Ž', 'ß',
	'ą', 'į', 'ā', 'ć', 'ä', 'å', 'ę', 'ē',
	'č', 'é', 'ź', 'ė', 'ģ', 'ķ', 'ī', 'ļ',
	'š', 'ń', 'ņ', 'ó', 'ō', 'ő', 'ö', '÷',
	'ų', 'ł', 'ś', 'ū', 'ü', 'ż', 'ž', '’'];

immutable dchar[] ISO_8859_14 = [ 
	' ', 'Ḃ', 'ḃ', '£', 'Ċ', 'ċ', 'Ḋ', '§',
	'Ẁ', '©', 'Ẃ', 'ḋ', 'Ỳ', '­', '®', 'Ÿ',
	'Ḟ', 'ḟ', 'Ġ', 'ġ', 'Ṁ', 'ṁ', '¶', 'Ṗ',
	'ẁ', 'ṗ', 'ẃ', 'Ṡ', 'ỳ', 'Ẅ', 'ẅ', 'ṡ',
	'À', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'Æ', 'Ç',
	'È', 'É', 'Ê', 'Ë', 'Ì', 'Í', 'Î', 'Ï',
	'Ŵ', 'Ñ', 'Ò', 'Ó', 'Ô', 'Ő', 'Ö', 'Ṫ',
	'Ø', 'Ù', 'Ú', 'Û', 'Ü', 'Ý', 'Ŷ', 'ß',
	'à', 'á', 'â', 'ã', 'ä', 'å', 'æ', 'ç',
	'è', 'é', 'ê', 'ë', 'ì', 'í', 'î', 'ï',
	'ŵ', 'ñ', 'ò', 'ó', 'ô', 'ő', 'ö', 'ṫ',
	'ø', 'ù', 'ú', 'û', 'ü', 'ý', 'ŷ', 'ÿ'];

immutable dchar[] ISO_8859_15 = [ 
	' ', '¡', '¢', '£', '€', '¥', 'Š', '§',
	'š', '©', 'ª', '«', '¬', '­', '®', '¯',
	'°', '±', '²', '³', 'Ž', 'µ', '¶', '·',
	'ž', '¹', 'º', '»', 'Œ', 'œ', 'Ÿ', '¿',
	'À', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'Æ', 'Ç',
	'È', 'É', 'Ê', 'Ë', 'Ì', 'Í', 'Î', 'Ï',
	'Ð', 'Ñ', 'Ò', 'Ó', 'Ô', 'Ő', 'Ö', '×',
	'Ø', 'Ù', 'Ú', 'Û', 'Ü', 'Ý', 'Þ', 'ß',
	'à', 'á', 'â', 'ã', 'ä', 'å', 'æ', 'ç',
	'è', 'é', 'ê', 'ë', 'ì', 'í', 'î', 'ï',
	'ð', 'ñ', 'ò', 'ó', 'ô', 'ő', 'ö', '÷',
	'ø', 'ù', 'ú', 'û', 'ü', 'ý', 'þ', 'ÿ'];

immutable dchar[] ISO_8859_16 = [ 
	' ', 'Ą', 'ą', 'Ł', '€', '„', 'Š', '§',
	'š', '©', 'Ș', '«', 'Ź', '­', 'ź', 'Ż',
	'°', '±', 'Č', 'ł', 'Ž', '”', '¶', '·',
	'ž', 'č', 'ș', '»', 'Œ', 'œ', 'Ÿ', 'ż',
	'À', 'Á', 'Â', 'Ă', 'Ä', 'Ć', 'Æ', 'Ç',
	'È', 'É', 'Ê', 'Ë', 'Ì', 'Í', 'Î', 'Ï',
	'Ð', 'Ń', 'Ò', 'Ó', 'Ô', 'Ő', 'Ö', 'Ś',
	'Ű', 'Ù', 'Ú', 'Û', 'Ü', 'Ę', 'Ț', 'ß',
	'à', 'á', 'â', 'ă', 'ä', 'ć', 'æ', 'ç',
	'è', 'é', 'ê', 'ë', 'ì', 'í', 'î', 'ï',
	'đ', 'ń', 'ò', 'ó', 'ô', 'ő', 'ö', 'ś',
	'ű', 'ù', 'ú', 'û', 'ü', 'ę', 'ț', 'ÿ'];

immutable dchar[] KOI8_R_Lower = [
	'─', '│', '┌', '┐', '└', '┘', '├', '┤',
	'┬', '┴', '┼', '▀', '▄', '█', '▌', '▐',
	'░', '▒', '▓', '⌠', '■', '∙', '√', '≈',
	'≤', '≥', '\u00a0', '⌡', '°', '²', '·', '÷'];

immutable dchar[] KOI8_R = [
	'═', '║', '╒', 'ё', '╓', '╔', '╕', '╖',
	'╗', '╘', '╙', '╚', '╛', '╜', '╝', '╞',
	'╟', '╠', '╡', 'ё', '╢', '╣', '╤', '╥',
	'╦', '╧', '╨', '╩', '╪', '╫', '╬', '©',
	'ю', 'а', 'б', 'ц', 'д', 'е', 'ф', 'г',
	'х', 'и', 'й', 'к', 'л', 'м', 'н', 'о',
	'п', 'я', 'р', 'с', 'т', 'у', 'ж', 'в',
	'ь', 'ы', 'з', 'ш', 'э', 'щ', 'ч', 'ъ',
	'ю', 'а', 'б', 'ц', 'д', 'е', 'ф', 'г',
	'х', 'и', 'й', 'к', 'л', 'м', 'н', 'о',
	'п', 'я', 'р', 'с', 'т', 'у', 'ж', 'в',
	'ь', 'ы', 'з', 'ш', 'э', 'щ', 'ч', 'ъ'];

immutable dchar[] Windows_1251_Lower = [
	'Ђ', 'Ѓ', '‚', 'ѓ', '„', '…', '†', '‡',
	'€', '‰', 'Љ', '‹', 'Њ', 'Ќ', 'Ћ', 'Џ',
	'ђ', '‘', '’', '“', '”', '•', '–', '—',
	' ', '™', 'љ', '›', 'њ', 'ќ', 'ћ', 'џ'];

immutable dchar[] Windows_1251 = [
	' ', 'Ў', 'ў', 'Ј', '¤', 'Ґ', '¦', '§',
	'Ё', '©', 'Є', '«', '¬', '­', '®', 'Ї',
	'°', '±', 'І', 'і', 'ґ', 'µ', '¶', '·',
	'ё', '№', 'є', '»', 'ј', 'Ѕ', 'ѕ', 'ї',
	'А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'З',
	'И', 'Й', 'К', 'Л', 'М', 'Н', 'О', 'П',
	'Р', 'С', 'Т', 'У', 'Ф', 'Х', 'Ц', 'Ч',
	'Ш', 'Щ', 'Ъ', 'Ы', 'Ь', 'Э', 'Ю', 'Я',
	'а', 'б', 'в', 'г', 'д', 'е', 'ж', 'з',
	'и', 'й', 'к', 'л', 'м', 'н', 'о', 'п',
	'р', 'с', 'т', 'у', 'ф', 'х', 'ц', 'ч',
	'ш', 'щ', 'ъ', 'ы', 'ь', 'э', 'ю', 'я'];

