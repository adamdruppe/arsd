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
				import std.conv;
				secondsCount += multiplier * to!int(part);
				multiplier /= 60;
			}

			if(wasPm)
				secondsCount += 12 * 3600;
		} else if(word.isNumeric()) {
			import std.conv;
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
	auto testTime = SysTime(DateTime(Date(2024, 07, 03), TimeOfDay(10, 0, 0)), UTC());
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
	DateWithOptionalTime start;
	DateWithOptionalTime end;

	Recurrence recurrence;

	int color;
	string title; // summary
	string details;

	string uid;

	this(DateWithOptionalTime start, DateWithOptionalTime end, Recurrence recurrence = Recurrence.none) {
		this.start = start;
		this.end = end;
		this.recurrence = recurrence;
	}
}

/++

+/
struct DateWithOptionalTime {
	string tzlocation;
	DateTime dt;
	bool hadTime;

	@implicit
	this(DateTime dt) {
		this.dt = dt;
		this.hadTime = true;
	}

	@implicit
	this(Date d) {
		this.dt = DateTime(d, TimeOfDay.init);
		this.hadTime = false;
	}

	this(in char[] s) {
		// FIXME
	}
}

/++

+/
struct Recurrence {
	static Recurrence none() {
		return Recurrence.init;
	}
}

/+

enum FREQ {

}

struct RRULE {
	FREQ freq;
	int interval;
	int count;
	DAY wkst;

	// these can be negative too indicating the xth from the last...
	DAYSET byday; // ubyte bitmask... except it can also have numbers atached wtf

	// so like `BYDAY=-2MO` means second-to-last monday

	MONTHDAYSET byMonthDay; // uint bitmask
	HOURSET byHour; // uint bitmask
	MONTHDSET byMonth; // ushort bitmask

	WEEKSET byWeekNo; // ulong bitmask

	int BYSETPOS;
}

+/

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
