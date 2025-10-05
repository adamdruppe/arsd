/++
	Some support for the Microsoft Excel Spreadsheet file format.

	Don't expect much from it, not even API stability.

	Some code is borrowed from the xlsxreader package.

	History:
		Added February 13, 2025

	See_Also:
		https://github.com/symmetryinvestments/xlsxd which supports writing xlsx files. I might add write support here too someday but I kinda doubt it.
+/
module arsd.xlsx;

/+
./csv-viewer ~/Downloads/UI_comparison.xlsx
arsd.dom.ElementNotFoundException@/home/me/program/lib/arsd/xlsx.d(823): Element of type 'Element' matching {worksheet > dimension} not found.
+/

/+
	sheet at double[]:

	nan payloads for blank, errors, then strings as indexes into a table.
+/

// FIXME: does excel save errors like DIV0 to content in the file?

// See also Robert's impl: https://github.com/symmetryinvestments/xlsxreader/blob/master/source/xlsxreader.d

import arsd.core;
import arsd.zip;
import arsd.dom;
import arsd.color;

import std.conv;

private struct ExcelFormatStringLexeme {
	string lexeme;
	bool isLiteral;
}

class ExcelFormatStringException : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__) {
		super(msg, file, line);
	}
}

// FIXME: out contract that asserts s_io.length has indeed been reduced
private ExcelFormatStringLexeme extractExcelFormatStringLexeme(ref string s_io) {
	assert(s_io.length);
	string s = s_io;

	switch(s[0]) {
		case '[':
			// condition or color
			// or elapsed time thing.
			// or a locale setting thing for dates (and more?)
			int count = 0;
			int size = 0;
			while(s[0]) {
				if(s[0] == '[')
					count++;
				if(s[0] == ']')
					count--;
				s = s[1 .. $];
				size++;
				if(count == 0)
					break;
				if(s.length == 0)
					throw new ExcelFormatStringException("unclosed [");
			}

			string ret = s_io[0 .. size];
			s_io = s_io[size .. $];

			return ExcelFormatStringLexeme(ret, false);
		case '"':
			// quoted thing watching for backslash
			bool escaped;
			int size;

			size++;
			s = s[1 .. $]; // skip the first "

			string ret;

			while(escaped || s[0] != '"') {
				if(!escaped) {
					if(s[0] == '"') {
						break;
					}
					if(s[0] == '\\')
						escaped = true;
					else
						ret ~= s[0];
				} else {
					ret ~= s[0];
					escaped = false;
				}

				s = s[1 .. $];
				size++;
			}
			if(s.length == 0)
				throw new ExcelFormatStringException("unclosed \"");
			size++;

			s_io = s_io[size .. $];
			return ExcelFormatStringLexeme(ret, true);

		case '\\':
			// escaped character
			s = s[1 .. $]; // skip the \
			s_io = s_io[1 .. $];

			// FIXME: need real stride
			auto stride = 1;
			s_io = s_io[stride .. $];
			return ExcelFormatStringLexeme(s[0 .. stride], true);
		case '$', '+', '(', ':', '^', '\'', '{', '<', '=', '-', ')', '!', '&', '~', '}', '>', ' ': // they say slash but that seems to be fraction instead
			// character literals w/o needing to be quoted
			s_io = s_io[1 .. $];
			return ExcelFormatStringLexeme(s[0 .. 1], true);
		case 'A', 'a', 'P', 'p':
			// am/pm

			int size = 0;
			while(
				s[0] == 'a' || s[0] == 'A' ||
				s[0] == 'p' || s[0] == 'P' ||
				s[0] == 'm' || s[0] == 'M' ||
				s[0] == '/'
			) {
				size++;
				s = s[1 .. $];
				if(s.length == 0)
					break;
			}
			// also switches hour to 12 hour format when it happens
			string ret = s_io[0 .. size];
			s_io = s_io[size .. $];

			return ExcelFormatStringLexeme(ret, false);

		// the single char directives
		case '@': // text placeholder
		case ';': // clause separator
			s_io = s_io[1 .. $];
			return ExcelFormatStringLexeme(s[0 .. 1], false);
		case '_': // padding char - this adds a space with the same width as the char that follows it, for column alignment.
		case '*': // fill char
			// the padding or fill is the next lexeme, not the next char!
			s_io = s_io[1 .. $];
			return ExcelFormatStringLexeme(s[0 .. 1], false);
		case 'e', 'E': // scientific notation request
		case '%': // percent indicator
		case ',': // thousands separator
		case '.': // decimal separator
		case '/': // fraction or date separator
			s_io = s_io[1 .. $];
			return ExcelFormatStringLexeme(s[0 .. 1], false);
		case /*'m',*/ 'd', 'y': // date parts
		case 'h', 'm', 's': // time parts

			/+
			Note: The m or mm code must appear immediately after the h or hh code or immediately before the ss code; otherwise, Excel displays the month instead of minutes.

			it can be either a date/time OR a number/fraction, not both.
			+/

			auto thing = s[0];
			int size;
			while(s.length && s[0] == thing) {
				s = s[1 .. $];
				size++;
			}
			auto keep = s_io[0 .. size];
			s_io = s_io[size .. $];
			return ExcelFormatStringLexeme(keep, false);
		case '1': .. case '9': // fraction denominators or just literal numbers
			int size;
			while(s.length && s[0] >= '1' && s[0] <= '9') {
				s = s[1 .. $];
				size++;
			}
			auto keep = s_io[0 .. size];
			s_io = s_io[size .. $];
			return ExcelFormatStringLexeme(keep, false);
		case '0', '#', '?': // digit placeholder
			int size;

			while(s[0] == '0' || s[0] == '#' || s[0] == '?') {
				s = s[1 .. $];
				size++;
				if(s.length == 0)
					break;
			}

			auto keep = s_io[0 .. size];
			s_io = s_io[size .. $];
			return ExcelFormatStringLexeme(keep, false);

		default:
			// idk
			throw new ExcelFormatStringException("unknown char " ~ s);
	}

	assert(0);
}

unittest {
	string thing = `[>50][Red]"foo"`;
	ExcelFormatStringLexeme lexeme;

	lexeme = extractExcelFormatStringLexeme(thing);
	assert(thing == `[Red]"foo"`);
	lexeme = extractExcelFormatStringLexeme(thing);
	assert(thing == `"foo"`);
	lexeme = extractExcelFormatStringLexeme(thing);
	assert(thing == "");
	assert(lexeme.lexeme == "foo");

	thing = `"\""`;
	lexeme = extractExcelFormatStringLexeme(thing);
	assert(thing == "");
	assert(lexeme.lexeme == `"`);

	thing = `\,`;
	lexeme = extractExcelFormatStringLexeme(thing);
	assert(thing == "");
	assert(lexeme.lexeme == `,`);

	/*
	thing = `"A\""`;
	lexeme = extractExcelFormatStringLexeme(thing);
	assert(thing == "");
	assert(lexeme.lexeme == `"`);
	*/

	/+
	thing = "mm-yyyy";
	lexeme = extractExcelFormatStringLexeme(thing);
	import std.stdio; writeln(thing); writeln(lexeme);
	+/
}

struct XlsxFormat {
	string originalFormatString;

	Color foregroundColor;
	Color backgroundColor;

	int alignment; // 0 = left, 1 = right, 2 = center

	enum Type {
		/++
		+/
		String,
		/++

		+/
		Number,
		/++
			A Date is a special kind of number in Excel.
		+/
		Date,
		/++
			things like # ?/4

		+/
		Fraction,
		Percent
	}
	Type type;

	/++
	+/
	static struct Result {
		string content;
		string color;
		int alignment;
	}

	/++
	+/
	Result applyTo(string s) const {
		if(this.type == Type.String || originalFormatString == "@" || originalFormatString.length == 0)
			return Result(s, null, alignment);

		int alignment = this.alignment;

		// need to check for a text thing and if conversion fails, we use that
		double value;
		try {
			value = to!double(s);
		} catch(Exception e) {
			value = double.nan;
		}

		DateTime date_;
		bool dateCalculated;

		DateTime getDate() {
			// make sure value is not nan before here or it will throw "negative overflow"!
			if(!dateCalculated) {
				date_ = doubleToDateTime(value);
				dateCalculated = true;
			}

			return date_;
		}

		// parse out the original format string
		// the ordering by default is positive;negative;zero;text
		//
		// these can also be like [Color][Condition]fmt;generic
		// color is allowed anywhere
		// but condition can only have two things following: `[Color][Condition];` repeated any number of times then `;generic-number;text`. no more negative/zero stuff.
		// once we see a condition, it switches modes - following things MUST have condition or else are treated as just generic catch all for number and then text.
		//
		// it matches linearly.
		/+
			so it goes:
				implicit match >0
				implicit match <0
				implicit match =0
				text

			but if at any point one of them has a condition, the following ones must be either more conditions (immediately!) or unconditional:
				fallthrough for number
				text


			and if i dont support a format thing i can always fall back to the original text.
		+/

		try {
			string fmt = originalFormatString;

			int state = 0; // 0 == positive, 1 == negative or custom, 2 == other, 3 == text
			bool matchesCurrentCondition = value > 0;

			bool hasMultipleClauses = false;
			{
				string fmt2 = fmt;
				while(fmt2.length) {
					auto next = extractExcelFormatStringLexeme(fmt2);
					if(!next.isLiteral && next.lexeme == ";")
						hasMultipleClauses = true;
						break;
				}
			}
			if(hasMultipleClauses == false)
				matchesCurrentCondition = true; // only one thing means we must always match it

			int numericState;
			bool inDenominator;
			bool inAmPm;
			bool inDecimal;
			bool justSawHours;

			// these are populated below once we match a clause
			bool hasAmPm;
			bool hasFraction;
			bool hasScientificNotation;
			bool hasPercent;
			bool first = true;

			string color;
			string ret;

			while(fmt.length) {
				auto lexeme = extractExcelFormatStringLexeme(fmt);

				ExcelFormatStringLexeme peekLexeme(bool returnLiteral = false) {
					string fmt2 = fmt;
					skip:
					if(fmt2.length == 0)
						return ExcelFormatStringLexeme.init;
					auto next = extractExcelFormatStringLexeme(fmt2);
					if(next.isLiteral && !returnLiteral)
						goto skip;
					return next;
				}

				if(!lexeme.isLiteral && lexeme.lexeme[0] == ';') {
					// we finished the format of the match, so no need to continue
					if(matchesCurrentCondition)
						break;
					// otherwise, we go to the next thing
					state++;
					if(state == 1) {
						matchesCurrentCondition = value < 0;
					} else if(state == 2) {
						// this is going to be either the catch-all fallback or another custom one
						// for now, assume it is a catch-all
						import std.math;
						matchesCurrentCondition = !isNaN(value) ? true : false; // only numbers, so not text, matches the catch-all
					} else if(state == 3) {
						matchesCurrentCondition = true; // this needs to match, we're at the end, so this is the text display
					} else {
						throw new ExcelFormatStringException("too many ; pieces");
					}

					continue;
				}

				if(!matchesCurrentCondition)
					continue;

				// scan ahead to see if we're doing some special cases: fractions, 12 hour clock, percentages, and sci notation
				if(first) {
					string fmt2 = fmt;
					while(fmt2.length) {
						auto next = extractExcelFormatStringLexeme(fmt2);
						if(!next.isLiteral) {
							// don't proceed into the next clause
							if(next.lexeme == ";")
								break;

							char c = next.lexeme[0] | 0x20;
							if(next.lexeme == "/")
								hasFraction = true;
							else if(next.lexeme == "%") {
								hasPercent = true;
								value *= 100.0;
							} else if(c == 'e')
								hasScientificNotation = true;
							else if(c == 'a' || c == 'p')
								hasAmPm = true;
						}
					}
					first = false;
				}

				if(hasScientificNotation)
					return Result(s, "unsupported feature: scientific notation"); // FIXME
				if(hasFraction)
					return Result(s, "unsupported feature: fractions"); // FIXME

				if(!lexeme.isLiteral && lexeme.lexeme[0] == '[') {
					// look for color, condition, or locale
					char nc = lexeme.lexeme[1];
					if(nc == '$')
						continue; // locale i think, skip it
					if(nc == '<' || nc == '>' || nc == '=') {
						// condition

						if(state == 1 || state == 2) {
							state = 1;
							// read the condition, see if we match it
							auto condition = lexeme.lexeme[1 .. $-1];

							string operator;
							string num;
							if(condition[1] == '=') {
								operator = condition[0 .. 2];
								num = condition[2 .. $];
							} else {
								operator = condition[0 .. 1];
								num = condition[1 .. $];
							}

							double compareTo;
							try {
								compareTo = to!double(num);
							} catch(Exception e) {
								throw new ExcelFormatStringException("not a number: " ~ num);
							}
							switch(operator) {
								case "<":
									matchesCurrentCondition = value < compareTo;
								break;
								case "<=":
									matchesCurrentCondition = value <= compareTo;
								break;
								case ">":
									matchesCurrentCondition = value > compareTo;
								break;
								case ">=":
									matchesCurrentCondition = value >= compareTo;
								break;
								case "=":
									// FIXME: approxEqual?
									matchesCurrentCondition = value == compareTo;
								break;

								default:
									throw new ExcelFormatStringException("not a supported comparison operator " ~ operator);
							}

							continue;
						} else {
							throw new ExcelFormatStringException("inappropriately placed custom condition");
						}
					} else {
						// color, we hope. FIXME can also be [s], [m], or [h] or maybe [ss], [mm], [hh]
						// colors are capitalized...
						color = lexeme.lexeme[1 .. $-1];
						continue;
					}
				}

				// if we're here, it should actually match and need some processing.

				if(lexeme.isLiteral) {
					// literals are easy...
					ret ~= lexeme.lexeme;
				} else {
					// but the rest of these are formatting commands
					switch(lexeme.lexeme[0]) {
						case ',':
							// thousands separator requested,
							// handled below in the decimal placeholder thing
						break;
						case '_', '*':
							auto lexemeToPadWith = extractExcelFormatStringLexeme(fmt);
							if(lexeme.lexeme[0] == '_')
								ret ~= " "; // FIXME supposed to match width of the char
							else if(lexeme.lexeme[0] == '*')
								ret ~= lexemeToPadWith.lexeme; // FIXME: supposed to repeat to fill the column width
						break;
						case '@': // the original text
							ret ~= s;
						break;
						case '%':
							ret ~= lexeme.lexeme;
						break;
						case '.':
							inDecimal = true;
							ret ~= lexeme.lexeme;
						break;
						case '/':
							if(!inAmPm) {
								inDenominator = true;
								ret ~= lexeme.lexeme;
							}
						break;
						case '#', '0', '?':
							// decimal group
							// # = digit
							// 0 = digit, pad with 0 if not significant
							// ? = digit, pad with space (same sized as digit) if not significant

							if(value is double.nan)
								return Result(s, "NaN");

							alignment = 1; // if we are printing numbers let's assume right align FIXME
							/+
							if(s.length == 0 && value is double.nan) // and if we printing numbers, treat empty cell as 0
								value = 0.0;
							+/

							bool appendNumber(double v, bool includeThousandsSeparator) {
								if(v < 0)
									v = -v;
								string f = to!string(cast(int) v);
								if(f.length < lexeme.lexeme.length)
								foreach(l; lexeme.lexeme[0 .. $ - f.length]) {
									if(l == '0')
										ret ~= '0';
									else if(l == '?')
										ret ~= ' ';
								}
								if(f.length) {
									if(includeThousandsSeparator) {
										// 14532
										// 1234
										// 123
										auto offset = cast(int) f.length % 3;
										while(f.length > 3) {
											ret ~= f[offset .. offset + 3];
											ret ~= ",";
											f = f[3 .. $];
										}
										ret ~= f;
									} else {
										ret ~= f;
									}
									return true;
								}
								return false;
							}

							if(peekLexeme().lexeme == ",") {
								// thousands separator requested...
								auto v = cast(int) value / 1000;

								if(v == 0)
									continue; // FIXME? maybe we want some leading 0 padding?

								auto hadOutput = appendNumber(v, true);

								value = value - v * 1000; // take the remainder for the next iteration of the loop

								if(hadOutput)
									ret ~= ","; // append the comma before the final thousands digits in the next iteration

								continue;
							}


							if(inDecimal) {
								// FIXME: no more std.format
								import std.format;
								string f = format("%."~to!string(lexeme.lexeme.length)~"f", value - cast(int) value)[2..$]; // slice off the "0."
								ret ~= f;
							} else {
								appendNumber(value, false);
							}

							inDenominator = false;
						break;
						case '1': .. case '9':
							// number,  if in denominator position
							// otherwise treat as string
							if(inDenominator)
								inDenominator = false; // the rest is handled elsewhere
							else
								ret ~= lexeme.lexeme;
						break;
						case 'y':
							if(value is double.nan)
								return Result(s, "NaN date");

							justSawHours = false;
							auto y = getDate().year;

							char[16] buffer;

							switch(lexeme.lexeme.length) {
								case 2:
									ret ~= intToString(y % 100, buffer[], IntToStringArgs().withPadding(2));
								break;
								case 4:
									ret ~= intToString(y, buffer[], IntToStringArgs().withPadding(4));
								break;
								default:
									throw new ExcelFormatStringException("unknown thing " ~ lexeme.lexeme);
							}
						break;
						case 'm':
							if(value is double.nan)
								return Result(s, "NaN date");
							auto peek = peekLexeme(false);
							bool precedesSeconds =
								(peek.lexeme.length && peek.lexeme[0] == 's')
								||
								(peek.lexeme.length > 1 && peek.lexeme[1] == 's')
							;

							if(justSawHours || precedesSeconds) {
								// minutes
								auto m = getDate().timeOfDay.minute;

								char[16] buffer;

								switch(lexeme.lexeme.length) {
									case 1:
										ret ~= intToString(m, buffer[]);
									break;
									case 2:
										ret ~= intToString(m, buffer[], IntToStringArgs().withPadding(2));
									break;
									default:
										throw new ExcelFormatStringException("unknown thing " ~ lexeme.lexeme);
								}
							} else {
								// month
								auto m = cast(int) getDate().month;

								char[16] buffer;

								import arsd.calendar;

								switch(lexeme.lexeme.length) {
									case 1:
										ret ~= intToString(m, buffer[]);
									break;
									case 2:
										ret ~= intToString(m, buffer[], IntToStringArgs().withPadding(2));
									break;
									case 3: // abbreviation
										ret ~= monthNames[m][0 .. 3];
									break;
									case 4: // full name
										ret ~= monthNames[m];
									break;
									case 5: // single letter
										ret ~= monthNames[m][0 .. 1]; // FIXME?
									break;
									default:
										throw new ExcelFormatStringException("unknown thing " ~ lexeme.lexeme);
								}
							}

							justSawHours = false;
						break;
						case 'd':
							if(value is double.nan)
								return Result(s, "NaN date");
							justSawHours = false;

							char[16] buffer;

							import arsd.calendar;

							auto d = getDate().day;
							auto dow = cast(int) getDate().dayOfWeek;

							switch(lexeme.lexeme.length) {
								case 1:
									ret ~= intToString(d, buffer[]);
								break;
								case 2:
									ret ~= intToString(d, buffer[], IntToStringArgs().withPadding(2));
								break;
								case 3:
									// abbreviation
									ret ~= daysOfWeekNames[dow][0 .. 3];
								break;
								case 4:
									// full name
									ret ~= daysOfWeekNames[dow];
								break;
								default:
									throw new ExcelFormatStringException("unknown thing " ~ lexeme.lexeme);
							}
						break;
						case 'h':
							if(value is double.nan)
								return Result(s, "NaN date");
							justSawHours = true;

							auto m = getDate().timeOfDay.hour;
							char[16] buffer;

							if(hasAmPm && m > 12)
								m -= 12;
							if(hasAmPm && m == 0)
								m = 12;

							switch(lexeme.lexeme.length) {
								case 1:
									ret ~= intToString(m, buffer[]);
								break;
								case 2:
									ret ~= intToString(m, buffer[], IntToStringArgs().withPadding(2));
								break;
								default:
									throw new ExcelFormatStringException("unknown thing " ~ lexeme.lexeme);
							}
						break;
						case 'a', 'A':
							if(value is double.nan)
								return Result(s, "NaN date");
							inAmPm = true;
							auto m = getDate().timeOfDay.hour;
							if(m >= 12)
								ret ~= lexeme.lexeme[0] == 'a' ? "pm" : "PM";
							else
								ret ~= lexeme.lexeme[0] == 'a' ? "am" : "AM";
						break;
						case 'p', 'P':
							inAmPm = false;
						break;
						case 's':
							if(value is double.nan)
								return Result(s, "NaN date");
							auto m = getDate().timeOfDay.second;
							char[16] buffer;
							switch(lexeme.lexeme.length) {
								case 1:
									ret ~= intToString(m, buffer[]);
								break;
								case 2:
									ret ~= intToString(m, buffer[], IntToStringArgs().withPadding(2));
								break;
								default:
									throw new ExcelFormatStringException("unknown thing " ~ lexeme.lexeme);
							}
						break;
						case 'e', 'E':
							// FIXME: scientific notation
						break;
						default:
							assert(0, "unsupported formatting command: " ~ lexeme.lexeme);
					}
				}
			}

			return Result(ret, color, alignment);
		} catch(ExcelFormatStringException e) {
			// we'll fall back to just displaying the original input text
			return Result(s, e.msg /* FIXME should be null */, alignment);
		}
	}

	/+
		positive;negative;zero;text
		can include formats and dates and tons of stuff.
		https://support.microsoft.com/en-us/office/review-guidelines-for-customizing-a-number-format-c0a1d1fa-d3f4-4018-96b7-9c9354dd99f5
	+/
	private this(XlsxFile file, XlsxFile.StyleInternal.xf formatting) {
		if(formatting.applyNumberFormat) {
			// dates too depending on format
			 //import std.stdio; writeln(formatting.numFmtId); writeln(file.styleInternal.numFmts);
			this.originalFormatString = file.styleInternal.numFmts[formatting.numFmtId];

			this.type = Type.Number;
		} else {
			this.type = Type.String;
		}

		/+
			xf also has:

			int xfId;
			int numFmtId;
			int fontId;
			int fillId;
			int borderId;
		+/
	}

	private this(string f) {
		this.originalFormatString = f;
		this.type = Type.Number;
	}
}

unittest {
	assert(XlsxFormat(`;;;"foo"`).applyTo("anything") == XlsxFormat.Result("foo", null));
	assert(XlsxFormat(`#.#;;;"foo"`).applyTo("2.0") == XlsxFormat.Result("2.0", null, 1));
	assert(XlsxFormat(`0#.##;;;"foo"`).applyTo("24.25") == XlsxFormat.Result("24.25", null, 1));
	assert(XlsxFormat(`0#.##;;;"foo"`).applyTo("2.25") == XlsxFormat.Result("02.25", null, 1));
	assert(XlsxFormat(`#,#.##`).applyTo("2.25") == XlsxFormat.Result("2.25", null, 1));
	assert(XlsxFormat(`#,#.##`).applyTo("123.25") == XlsxFormat.Result("123.25", null, 1));
	assert(XlsxFormat(`#,#.##`).applyTo("1234.25") == XlsxFormat.Result("1,234.25", null, 1));
	assert(XlsxFormat(`#,#.##`).applyTo("123456.25") == XlsxFormat.Result("123,456.25", null, 1));
}

struct XlsxCell {
	string formula;
	string content;
	XlsxFormat formatting;

	XlsxFormat.Result displayableResult() {
		return formatting.applyTo(content);
	}

	string toString() {
		return displayableResult().content;
	}
}

struct CellReference {
	string name;

	static CellReference fromInts(int column, int row) {
		string ret;

		string piece;
		int adjustment = 0;
		do {
			piece ~= cast(char)(column % 26 + 'A' - adjustment);
			if(adjustment == 0)
				adjustment = 1;
			column /= 26;
		} while(column);

		foreach_reverse(ch; piece)
			ret ~= ch;
		piece = null;

		do {
			piece ~= cast(char)(row % 10 + '0');
			row /= 10;
		} while(row);

		foreach_reverse(ch; piece)
			ret ~= ch;
		piece = null;

		return CellReference(ret);
	}

	string toString() {
		return name;
	}

	int toColumnIndex() {
		size_t endSlice = name.length;
		foreach(idx, ch; name) {
			if(ch < 'A' || ch > 'Z') {
				endSlice = idx;
				break;
			}
		}

		int accumulator;
		foreach(idx, ch; name[0 .. endSlice]) {
			int value;
			if(idx + 1 == endSlice) {
				// an A in the last "digit" is a 0, elsewhere it is a 1
				value = ch - 'A';
			} else {
				value = ch - 'A' + 1;
			}

			accumulator *= 26;
			accumulator += value;
		}
		return accumulator;
	}

	int toRowIndex() {
		int accumulator;
		foreach(ch; name) {
			if(ch >= 'A' && ch <= 'Z')
				continue;
			accumulator *= 10;
			accumulator += ch - '0';
		}
		return accumulator;
	}
}

unittest {
	auto cr = CellReference("AE434");
	assert(cr.toColumnIndex == 30);
	cr = CellReference("E434");
	assert(cr.toColumnIndex == 4); // zero-based

	// zero-based column, 1-based row. wtf?
	assert(CellReference("AE434") == CellReference.fromInts(30, 434));

	assert(CellReference("Z1") == CellReference.fromInts(25, 1));
}

/++

+/
class XlsxSheet {
	private string name_;
	private XlsxFile file;
	private XmlDocument document;
	private this(XlsxFile file, string name, XmlDocument document) {
		this.file = file;
		this.name_ = name;
		this.document = document;

		this.dimension = document.requireSelector("worksheet > dimension").getAttribute("ref");
		// there's also sheetView with selection, activeCell, etc
		// and cols with widths and such

		auto ul = this.upperLeft;
		this.minRow = ul.toRowIndex;
		this.minColumn = ul.toColumnIndex;

		auto lr = this.lowerRight;
		this.maxRow = lr.toRowIndex + 1;
		this.maxColumn = lr.toColumnIndex + 1;
	}

	private string dimension;

	private int minRow;
	private int minColumn;
	private int maxRow;
	private int maxColumn;

	/++
	+/
	Size size() {
		return Size(maxColumn - minColumn, maxRow - minRow);
	}

	private CellReference upperLeft() {
		foreach(idx, ch; dimension)
			if(ch == ':')
				return CellReference(dimension[0 .. idx]);
		//assert(0); // it has no lower right...
		return CellReference(dimension);
	}

	private CellReference lowerRight() {
		foreach(idx, ch; dimension)
			if(ch == ':')
				return CellReference(dimension[idx + 1 .. $]);
		assert(0);
	}

	// opIndex could be like sheet["A1:B4"] and sheet["A1", "B4"] and stuff maybe.

	/++
	+/
	string name() {
		return name_;
	}

	/++
		Suitable for passing to [arsd.csv.toCsv]
	+/
	string[][] toStringGrid() {
		auto grid = this.toGrid();

		string[][] ret;
		ret.length = size.height;
		foreach(i, ref row; ret) {
			row.length = size.width;
			foreach(k, ref cell; row)
				cell = grid[i][k].toString();
		}

		return ret;
	}

	/++

	+/
	XlsxCell[][] toGrid() {
		// FIXME: this crashes on opend dmd!
		// string[][] ret = new string[][](size.height, size.width);

		/+
		// almost everything we allocate in here is to keep, so
		// turning off the GC while working prevents unnecessary
		// collection attempts that won't find any garbage anyway.

		// but meh no significant difference in perf anyway.
		import core.memory;
		GC.disable();
		scope(exit)
			GC.enable();
		+/

		XlsxCell[][] ret;
		ret.length = size.height;
		foreach(ref row; ret)
			row.length = size.width;

		//alloc done

		auto sheetData = document.requireSelector("sheetData");
		Element[] rowElements = sheetData.childNodes;

		Element[] nextRow(int expected) {
			if(rowElements.length == 0)
				throw new Exception("ran out of row elements...");

			Element rowElement;
			Element[] before = rowElements;

			do {
				rowElement = rowElements[0];
				rowElements = rowElements[1 .. $];
			} while(rowElement.tagName != "row");

			if(rowElement.attrs.r.to!int != expected) {
				// a row was skipped in the file, so we'll
				// return an empty placeholder too
				rowElements = before;
				return null;
			}

			return rowElement.childNodes;
		}

		foreach(int rowIdx, row; ret) {
			auto cellElements = nextRow(rowIdx + 1);

			foreach(int cellIdx, ref cell; row) {
				string cellReference = CellReference.fromInts(cellIdx + minColumn, rowIdx + minRow).name;

				Element element = null;
				foreach(idx, thing; cellElements) {
					if(thing.attrs.r == cellReference) {
						element = thing;
						cellElements = cellElements[idx + 1 .. $];
						break;
					}
				}

				if(element is null)
					continue;
				string v = element.optionSelector("v").textContent;
				if(element.attrs.t == "s")
					v = file.sharedStrings[v.to!int()];

				auto sString = element.attrs.s;
				auto sId = sString.length ? to!int(sString) : 0;

				string f = element.optionSelector("f").textContent;

				cell = XlsxCell(f, v, XlsxFormat(file, file.styleInternal.xfs[sId]));
			}
		}
		return ret;
	}
}

/++

+/
class XlsxFile {
	private ZipFile zipFile;

	/++

	+/
	this(FilePath file) {
		this.zipFile = new ZipFile(file);

		load();
	}

	/// ditto
	this(immutable(ubyte)[] rawData) {
		this.zipFile = new ZipFile(rawData);

		load();
	}

	/++
	+/
	int sheetCount() {
		return cast(int) sheetsInternal.length;
	}

	/++
	+/
	string[] sheetNames() {
		string[] ret;
		foreach(sheet; sheetsInternal)
			ret ~= sheet.name;
		return ret;
	}

	/++
	+/
	XlsxSheet getSheet(string name) {
		foreach(ref sheet; sheetsInternal)
			if(sheet.name == name)
				return getSheetParsed(sheet);
		return null;

	}

	/// ditto
	XlsxSheet getSheet(int indexZeroBased) {
		// FIXME: if it is out of range do what?
		return getSheetParsed(sheetsInternal[indexZeroBased]);
	}

	// docProps/core.xml has creator, last modified, etc.

	private string[string] contentTypes;
	private struct Relationship {
		string id;
		string type;
		string target;
	}
	private Relationship[string] relationships;
	private string[] sharedStrings;

	private struct SheetInternal {
		string name;
		string id;
		string rel;

		XmlDocument cached;
		XlsxSheet parsed;
	}
	private SheetInternal[] sheetsInternal;

	// https://stackoverflow.com/questions/3154646/what-does-the-s-attribute-signify-in-a-cell-tag-in-xlsx
	private struct StyleInternal {
		string[int] numFmts;
		// fonts
			// font references color theme from xl/themes
		// fills
		// borders
		// cellStyleXfs
		// cellXfs
		struct xf {
			int xfId;
			int numFmtId;
			int fontId;
			int fillId;
			int borderId;

			bool applyNumberFormat; // if yes, you get default right alignment
		}
		xf[] xfs;

		// cellStyles
		// dxfs
		// tableStyles

	}
	private StyleInternal styleInternal;

	private XmlDocument getSheetXml(ref SheetInternal sheet) {
		if(sheet.cached is null)
			loadXml("xl/" ~ relationships[sheet.rel].target, (document) { sheet.cached = document; });

		return sheet.cached;
	}

	private XlsxSheet getSheetParsed(ref SheetInternal sheet) {
		if(sheet.parsed is null)
			sheet.parsed = new XlsxSheet(this, sheet.name, getSheetXml(sheet));

		return sheet.parsed;
	}


	private void load() {
		loadXml("[Content_Types].xml", (document) {
			foreach(element; document.querySelectorAll("Override"))
				contentTypes[element.attrs.PartName] = element.attrs.ContentType;
		});

		loadXml("xl/_rels/workbook.xml.rels", (document) {
			foreach(element; document.querySelectorAll("Relationship"))
				relationships[element.attrs.Id] = Relationship(element.attrs.Id, element.attrs.Type, element.attrs.Target);
		});

		loadXml("xl/sharedStrings.xml", (document) {
			foreach(element; document.querySelectorAll("si t"))
				sharedStrings ~= element.textContent;
		});

		loadXml("xl/styles.xml", (document) {
			// need to keep the generic hardcoded formats first
			styleInternal.numFmts = [
				 0: "@",
				 1: "0",
				 2: "0.00",
				 3: "#,##0",
				 4: "#,##0.00",
				 5: "$#,##0_);($#,##0)",
				 6: "$#,##0_);[Red]($#,##0)",
				 7: "$#,##0.00_);($#,##0.00)",
				 8: "$#,##0.00_);[Red]($#,##0.00)",
				 9: "0%",
				10: "0.00%",
				11: "0.00E+00",
				12: "# ?/?",
				13: "# ??/??",
				14: "m/d/yyyy", // ive heard this one does different things in different locales
				15: "d-mmm-yy",
				16: "d-mmm",
				17: "mmm-yy",
				18: "h:mm AM/PM",
				19: "h:mm:ss AM/PM",
				20: "h:mm",
				21: "h:mm:ss",
				22: "m/d/yyyy h:mm",
				37: "#,##0_);(#,##0)",
				38: "#,##0_);[Red](#,##0)",
				39: "#,##0.00_);(#,##0.00)",
				40: "#,##0.00_);[Red](#,##0.00)",
				45: "mm:ss",
				46: "[h]:mm:ss",
				47: "mm:ss.0",
				48: "##0.0E+0",
				49: "@",
			];


			foreach(element; document.querySelectorAll("numFmts > numFmt")) {
				styleInternal.numFmts[to!int(element.attrs.numFmtId)] = element.attrs.formatCode;
			}

			foreach(element; document.querySelectorAll("cellXfs > xf")) {
				StyleInternal.xf xf;

				xf.xfId = element.attrs.xfId.to!int;
				xf.fontId = element.attrs.fontId.to!int;
				xf.fillId = element.attrs.fillId.to!int;
				xf.borderId = element.attrs.borderId.to!int;
				xf.numFmtId = element.attrs.numFmtId.to!int;

				if(element.attrs.applyNumberFormat == "1")
					xf.applyNumberFormat = true;

				styleInternal.xfs ~= xf;
			}
		});

		loadXml("xl/workbook.xml", (document) {
			foreach(element; document.querySelectorAll("sheets > sheet")) {
				sheetsInternal ~= SheetInternal(element.attrs.name, element.attrs.sheetId, element.getAttribute("r:id"));
			}
		});
	}

	private void loadXml(string filename, scope void delegate(XmlDocument document) handler) {
		auto document = new XmlDocument(cast(string) zipFile.getContent(filename));
		handler(document);
	}
}


// from Robert Schadek's code {

import std.datetime;
version(unittest) import std.format;

Date longToDate(long d) @safe {
	// modifed from https://www.codeproject.com/Articles/2750/
	// Excel-Serial-Date-to-Day-Month-Year-and-Vice-Versa

	// Excel/Lotus 123 have a bug with 29-02-1900. 1900 is not a
	// leap year, but Excel/Lotus 123 think it is...
	if(d == 60) {
		return Date(1900, 2,  29);
	} else if(d < 60) {
		// Because of the 29-02-1900 bug, any serial date
		// under 60 is one off... Compensate.
		++d;
	}

	// Modified Julian to DMY calculation with an addition of 2415019
	int l = cast(int)d + 68569 + 2415019;
	int n = int(( 4 * l ) / 146097);
	l = l - int(( 146097 * n + 3 ) / 4);
	int i = int(( 4000 * ( l + 1 ) ) / 1461001);
	l = l - int(( 1461 * i ) / 4) + 31;
	int j = int(( 80 * l ) / 2447);
	int nDay = l - int(( 2447 * j ) / 80);
	l = int(j / 11);
	int nMonth = j + 2 - ( 12 * l );
	int nYear = 100 * ( n - 49 ) + i + l;
	return Date(nYear, nMonth, nDay);
}

long dateToLong(Date d) @safe {
	// modifed from https://www.codeproject.com/Articles/2750/
	// Excel-Serial-Date-to-Day-Month-Year-and-Vice-Versa

	// Excel/Lotus 123 have a bug with 29-02-1900. 1900 is not a
	// leap year, but Excel/Lotus 123 think it is...
	if(d.day == 29 && d.month == 2 && d.year == 1900) {
		return 60;
	}

	// DMY to Modified Julian calculated with an extra subtraction of 2415019.
	long nSerialDate =
			int(( 1461 * ( d.year + 4800 + int(( d.month - 14 ) / 12) ) ) / 4) +
			int(( 367 * ( d.month - 2 - 12 *
				( ( d.month - 14 ) / 12 ) ) ) / 12) -
				int(( 3 * ( int(( d.year + 4900
				+ int(( d.month - 14 ) / 12) ) / 100) ) ) / 4) +
				d.day - 2415019 - 32075;

	if(nSerialDate < 60) {
		// Because of the 29-02-1900 bug, any serial date
		// under 60 is one off... Compensate.
		nSerialDate--;
	}

	return nSerialDate;
}

@safe unittest {
	auto ds = [ Date(1900,2,1), Date(1901, 2, 28), Date(2019, 06, 05) ];
	foreach(const d; ds) {
		long l = dateToLong(d);
		Date r = longToDate(l);
		assert(r == d, format("%s %s", r, d));
	}
}

TimeOfDay doubleToTimeOfDay(double s) @safe {
	import core.stdc.math : lround;
	double secs = (24.0 * 60.0 * 60.0) * s;

	// TODO not one-hundred my lround is needed
	int secI = to!int(lround(secs));

	return TimeOfDay(secI / 3600, (secI / 60) % 60, secI % 60);
}

double timeOfDayToDouble(TimeOfDay tod) @safe {
	long h = tod.hour * 60 * 60;
	long m = tod.minute * 60;
	long s = tod.second;
	return (h + m + s) / (24.0 * 60.0 * 60.0);
}

@safe unittest {
	auto tods = [ TimeOfDay(23, 12, 11), TimeOfDay(11, 0, 11),
		 TimeOfDay(0, 0, 0), TimeOfDay(0, 1, 0),
		 TimeOfDay(23, 59, 59), TimeOfDay(0, 0, 0)];
	foreach(const tod; tods) {
		double d = timeOfDayToDouble(tod);
		assert(d <= 1.0, format("%s", d));
		TimeOfDay r = doubleToTimeOfDay(d);
		assert(r == tod, format("%s %s", r, tod));
	}
}

double datetimeToDouble(DateTime dt) @safe {
	double d = dateToLong(dt.date);
	double t = timeOfDayToDouble(dt.timeOfDay);
	return d + t;
}

DateTime doubleToDateTime(double d) @safe {
	long l = cast(long)d;
	Date dt = longToDate(l);
	TimeOfDay t = doubleToTimeOfDay(d - l);
	return DateTime(dt, t);
}

@safe unittest {
	auto ds = [ Date(1900,2,1), Date(1901, 2, 28), Date(2019, 06, 05) ];
	auto tods = [ TimeOfDay(23, 12, 11), TimeOfDay(11, 0, 11),
		 TimeOfDay(0, 0, 0), TimeOfDay(0, 1, 0),
		 TimeOfDay(23, 59, 59), TimeOfDay(0, 0, 0)];
	foreach(const d; ds) {
		foreach(const tod; tods) {
			DateTime dt = DateTime(d, tod);
			double dou = datetimeToDouble(dt);

			Date rd = longToDate(cast(long)dou);
			assert(rd == d, format("%s %s", rd, d));

			double rest = dou - cast(long)dou;
			TimeOfDay rt = doubleToTimeOfDay(dou - cast(long)dou);
			assert(rt == tod, format("%s %s", rt, tod));

			DateTime r = doubleToDateTime(dou);
			assert(r == dt, format("%s %s", r, dt));
		}
	}
}
// end from burner's code }
