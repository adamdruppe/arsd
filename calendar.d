/++

	OpenD could use automatic mixin to child class...

	Extensions: color. exrule? trash day - if holiday occurred that week, move it forward a day

	Standards: categories

	UI idea for rrule: show a mini two year block with the day highlighted
		-> also just let user click on a bunch of days so they can make a list

	Want ability to add special info to a single item of a recurring event

	Can use inotify to reload ui when sqlite db changes (or a trigger on postgres?)

	https://datatracker.ietf.org/doc/html/rfc5545
	https://icalendar.org/
+/
module arsd.calendar;

import arsd.core;
import core.time;
import std.datetime;

/++
	History:
		Added July 3, 2024
+/
SimplifiedUtcTimestamp parseTimestampString(string when, SysTime relativeTo) /*pure*/ {
	import std.string;

	int parsingWhat;
	int bufferedNumber = int.max;

	int secondsCount;

	void addSeconds(string word, int bufferedNumber, int multiplier) {
		if(parsingWhat == 0)
			parsingWhat = 1;
		if(parsingWhat != 1)
			throw ArsdException!"unusable timestamp string"("you said 'at' but gave a relative time", when);
		if(bufferedNumber == int.max)
			throw ArsdException!"unusable timestamp string"("no number before unit", when, word);
		secondsCount += bufferedNumber * multiplier;
		bufferedNumber = int.max;
	}

	foreach(word; when.split(" ")) {
		word = strip(word).toLower().replace(",", "");
		if(word == "in")
			parsingWhat = 1;
		else if(word == "at")
			parsingWhat = 2;
		else if(word == "and") {
			// intentionally blank
		} else if(word.indexOf(":") != -1) {
			if(secondsCount != 0)
				throw ArsdException!"unusable timestamp string"("cannot mix time styles", when, word);

			if(parsingWhat == 0)
				parsingWhat = 2; // assume absolute time when this comes in

			bool wasPm;

			if(word.length > 2 && word[$-2 .. $] == "pm") {
				word = word[0 .. $-2];
				wasPm = true;
			} else if(word.length > 2 && word[$-2 .. $] == "am") {
				word = word[0 .. $-2];
			}

			// FIXME: what about midnight?
			int multiplier = 3600;
			foreach(part; word.split(":")) {
				import arsd.conv;
				secondsCount += multiplier * to!int(part);
				multiplier /= 60;
			}

			if(wasPm)
				secondsCount += 12 * 3600;
		} else if(word.isNumeric()) {
			import arsd.conv;
			bufferedNumber = to!int(word);
		} else if(word == "seconds" || word == "second") {
			addSeconds(word, bufferedNumber, 1);
		} else if(word == "minutes" || word == "minute") {
			addSeconds(word, bufferedNumber, 60);
		} else if(word == "hours" || word == "hour") {
			addSeconds(word, bufferedNumber, 60 * 60);
		} else
			throw ArsdException!"unusable timestamp string"("i dont know what this word means", when, word);
	}

	if(parsingWhat == 0)
		throw ArsdException!"unusable timestamp string"("couldn't figure out what to do with this input", when);

	else if(parsingWhat == 1) // relative time
		return SimplifiedUtcTimestamp((relativeTo + seconds(secondsCount)).stdTime);
	else if(parsingWhat == 2) { // absolute time (assuming it is today in our time zone)
		auto today = relativeTo;
		today.hour = 0;
		today.minute = 0;
		today.second = 0;
		return SimplifiedUtcTimestamp((today + seconds(secondsCount)).stdTime);
	} else
		assert(0);
}

unittest {
	auto testTime = SysTime(std.datetime.DateTime(std.datetime.Date(2024, 07, 03), TimeOfDay(10, 0, 0)), UTC());
	void test(string what, string expected) {
		auto result = parseTimestampString(what, testTime).toString;
		assert(result == expected, result);
	}

	test("in 5 minutes", "2024-07-03T10:05:00Z");
	test("in 5 minutes and 5 seconds", "2024-07-03T10:05:05Z");
	test("in 5 minutes, 45 seconds", "2024-07-03T10:05:45Z");
	test("at 5:44", "2024-07-03T05:44:00Z");
	test("at 5:44pm", "2024-07-03T17:44:00Z");
}

private alias UErrorCode = int;
private enum UErrorCode U_ZERO_ERROR = 0;
private bool U_SUCCESS(UErrorCode code) { return code <= U_ZERO_ERROR; }
/+
int ucal_getWindowsTimeZoneID(
	const wchar* od, int len,
	wchar* winIdBuffer, int winIdLength,
	UErrorCode* status);
+/
private extern(C) alias TF = int function(const wchar*, int, wchar*, int, UErrorCode*);

/++
	Gets a Phobos TimeZone object for the given tz-style location, including on newer Windows computers using their built in database.

	History:
		Added December 13, 2025

	See_Also:
		https://devblogs.microsoft.com/oldnewthing/20210527-00/?p=105255
+/
immutable(std.datetime.TimeZone) getTimeZoneForLocation(string location) {
	version(Windows) {
		import core.sys.windows.windows;
		auto handle = LoadLibrary("icu.dll");
		if(handle is null)
			throw new WindowsApiException("LoadLibrary", GetLastError());
		scope(exit)
			FreeLibrary(handle);
		auto addr = GetProcAddress(handle, "ucal_getWindowsTimeZoneID");
		if(addr is null)
			throw new WindowsApiException("GetProcAddress", GetLastError());

		auto fn = cast(TF) addr;

		WCharzBuffer wloc = location;

		wchar[128] buffer = void;
		UErrorCode status;
		auto result = fn(wloc.ptr, -1, buffer.ptr, cast(int) buffer.length, &status);
		if(U_SUCCESS(status)) {
			buffer[result] = 0;
			string converted = makeUtf8StringFromWindowsString(buffer[0 .. result]);
			return WindowsTimeZone.getTimeZone(converted);
		} else {
			throw new Exception("failure in time zone lookup");
		}
	} else {
		return PosixTimeZone.getTimeZone(location);
	}
}
version(none)
unittest {
	getTimeZoneForLocation("America/New_York");
}

/++
	Does an efficient search to determine which iteration of the interval on the given date comes closest to the target point without going past it.
+/
int findNearestIterationTo(PackedDateTime targetPoint, PackedDateTime startPoint, PackedInterval pi) {
	return 0;
}

version(none)
void main() {
	auto e = new CalendarEvent(
		start: DateTime(2024, 4, 22),
		end: Date(2024, 04, 22),
	);
}

class Calendar {
	CalendarEvent[] events;
}

/++

+/
class CalendarEvent {
	string tzlocation;
	PackedDateTime start;
	PackedDateTime end;

	Recurrence recurrence;

	int color;
	string title; // summary
	string details;

	string uid;

	this(PackedDateTime start, PackedDateTime end, Recurrence recurrence = Recurrence.none) {
		this.start = start;
		this.end = end;
		this.recurrence = recurrence;
	}
}

/+
struct Date {
	int year;
	int month;
	int day;
}

struct Time {
	int hour;
	int minute;
	int second;
	int fractionalSeconds;
}

struct DateTime {
	Date date;
	Time time;
}
+/

/++

+/
struct Recurrence {
	static Recurrence none() {
		return Recurrence.init;
	}
}

enum FREQ {
	SECONDLY,
	MINUTELY,
	HOURLY,
	DAILY,
	WEEKLY,
	MONTHLY,
	YEARLY,
}

PackedInterval packedIntervalForRruleFreq(FREQ freq, int interval) {
	final switch(freq) {
		case FREQ.SECONDLY:
			return PackedInterval(0, 0, 1000 * interval);
		case FREQ.MINUTELY:
			return PackedInterval(0, 0, 60 * 1000 * interval);
		case FREQ.HOURLY:
			return PackedInterval(0, 0, 60 * 60 * 1000 * interval);
		case FREQ.DAILY:
			return PackedInterval(0, 1 * interval, 0);
		case FREQ.WEEKLY:
			return PackedInterval(0, 7 * interval, 0);
		case FREQ.MONTHLY:
			return PackedInterval(1 * interval, 0, 0);
		case FREQ.YEARLY:
			return PackedInterval(12 * interval, 0, 0);
	}
}

// https://datatracker.ietf.org/doc/html/rfc5545
struct RRULE {
	FREQ freq;
	int interval;
	int count;

	DAY wkst; // this determines, i think, how you determine how often a thing is allowed to occur. so if wkstart == wednesday and you set every other tuesday/thursday starting from a tuesday... it starts then, then +2 weeks for the next. but when you get to wednesday, it reset the counter figuring one happened last week, so it'll be another wek. thus it alternates tue/thurs each week. kinda nuts.

	alias DAY = int;
	static struct DAYSET {
		ulong firstBits;
		ushort moreBits;
	}
	alias MONTHDAYSET = ulong;
	alias HOURSET = uint;
	alias MONTHDSET = ushort;
	alias WEEKSET = ulong;

	// if there's a BYsomething available, that changes the start time for the interval. multiple by things make multiple intervals.

	// i don't think it ever really filters.

	// these can be negative too indicating the xth from the last...
	DAYSET byday; // ubyte bitmask... except it can also have numbers attached wtf.
	// so like `BYDAY=-2MO` means second-to-last monday
	// we can prolly have anything from -5 to +5 for each of the 7 days. 0 means all of them. and you can have multiple of any.
	// but who would ever say -5 lol? i guess that would be the first day in a month where there are 5.
	// so that's 11 numbers * 7 days = 77 bits.

	MONTHDAYSET byMonthDay; // uint bitmask. can also be negative numbers so probably two.. or just a ulong.
	HOURSET byHour; // uint bitmask
	MONTHDSET byMonth; // ushort bitmask

	WEEKSET byWeekNo; // ulong bitmask. can also be negative.

	short[4] BYSETPOS; // can be like -365 inclusive to +365. you can have multiple of these but i don't think packing it is useful. just a sorted array prolly... if there's more than 4, meh, wtf.

	PackedDateTime DTSTART;
	PackedDateTime UNTIL; // inclusive
}

struct ICalParser {
	// if the following line starts with whitespace, remove the cr/lf/ and that ONE ws char, then add to the previous line
	// it is supposed to support this even if it is in the middle of a utf-8 sequence
	//      contentline   = name *(";" param ) ":" value CRLF
	// you're supposed to split lines longer than 75 octets when generating.

	void feedEntireFile(in ubyte[] data) {
		feed(data);
		feed(null);
	}
	void feedEntireFile(in char[] data) {
		feed(data);
		feed(null);
	}

	/++
		Feed it some data you have ready.

		Feed it an empty array or `null` to indicate end of input.
	+/
	void feed(in char[] data) {
		feed(cast(const(ubyte)[]) data);
	}

	/// ditto
	void feed(in ubyte[] data) {
		const(ubyte)[] toProcess;
		if(unprocessedData.length) {
			unprocessedData ~= data;
			toProcess = unprocessedData;
		} else {
			toProcess = data;
		}

		auto eol = toProcess.indexOf("\n");
		if(eol == -1) {
			unprocessedData = cast(ubyte[]) toProcess;
		} else {
			// if it is \r\n, remove the \r FIXME
			// if it is \r\n<space>, need to concat
			// if it is \r\n\t, also need to concat
			processLine(toProcess[0 .. eol]);
		}
	}

	/// ditto
	void feed(typeof(null)) {
		feed(cast(const(ubyte)[]) null);
	}

	private ubyte[] unprocessedData;

	private void processLine(in ubyte[] line) {

	}
}

immutable monthNames = [
	"",
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December"
];

immutable daysOfWeekNames = [
	"Sunday",
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday",
];
