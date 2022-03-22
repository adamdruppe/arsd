/++
	Add-on to [arsd.minigui] to provide date and time widgets.

	History:
		Added March 22, 2022 (dub v10.7)

	Bugs:
		The Linux implementation is currently extremely minimal. The Windows implementation has more actual graphical functionality.
+/
module arsd.minigui_addons.datetime_picker;

import arsd.minigui;

import std.datetime;

static if(UsingWin32Widgets) {
	import core.sys.windows.windows;
	import core.sys.windows.commctrl;
}

/++
	A DatePicker is a single row input for picking a date. It can drop down a calendar to help the user pick the date they want.

	See also: [TimePicker], [CalendarPicker]
+/
// on Windows these support a min/max range too
class DatePicker : Widget {
	///
	this(Widget parent) {
		super(parent);
		static if(UsingWin32Widgets) {
			createWin32Window(this, "SysDateTimePick32"w, null, 0);
		} else {
			date = new LabeledLineEdit("Date (YYYY-Mon-DD)", TextAlignment.Right, this);

			date.addEventListener((ChangeEvent!string ce) { changed(); });

			this.tabStop = false;
		}
	}

	private Date value_;

	/++
		Current value the user selected. Please note this is NOT valid until AFTER a change event is emitted.
	+/
	Date value() {
		return value_;
	}

	/++
		Changes the current value displayed. Will not send a change event.
	+/
	void value(Date v) {
		static if(UsingWin32Widgets) {
			SYSTEMTIME st;
			st.wYear = v.year;
			st.wMonth = v.month;
			st.wDay = v.day;
			SendMessage(hwnd, DTM_SETSYSTEMTIME, GDT_VALID, cast(LPARAM) &st);
		} else {
			date.content = value_.toSimpleString();
		}
	}

	static if(UsingCustomWidgets) private {
		LabeledLineEdit date;
		string lastMsg;

		void changed() {
			try {
				value_ = Date.fromSimpleString(date.content);

				this.emit!(ChangeEvent!Date)(&value);
			} catch(Exception e) {
				if(e.msg != lastMsg) {
					messageBox(e.msg);
					lastMsg = e.msg;
				}
			}
		}
	}



	static if(UsingWin32Widgets) {
		override int minHeight() { return defaultLineHeight + 6; }
		override int maxHeight() { return defaultLineHeight + 6; }

		override int handleWmNotify(NMHDR* hdr, int code, out int mustReturn) {
			switch(code) {
				case DTN_DATETIMECHANGE:
					auto lpChange = cast(LPNMDATETIMECHANGE) hdr;
					if(true || (lpChange.dwFlags & GDT_VALID)) { // this flag only set if you use SHOWNONE
						auto st = lpChange.st;
						value_ = Date(st.wYear, st.wMonth, st.wDay);

						this.emit!(ChangeEvent!Date)(&value);

						mustReturn = true;
					}
				break;
				default:
			}
			return false;
		}
	} else {
		override int minHeight() { return defaultLineHeight + 4; }
		override int maxHeight() { return defaultLineHeight + 4; }
	}

	override bool encapsulatedChildren() {
		return true;
	}

	mixin Emits!(ChangeEvent!Date);
}

/++
	A TimePicker is a single row input for picking a time. It does not work with timezones.

	See also: [DatePicker]
+/
class TimePicker : Widget {
	///
	this(Widget parent) {
		super(parent);
		static if(UsingWin32Widgets) {
			createWin32Window(this, "SysDateTimePick32"w, null, DTS_TIMEFORMAT);
		} else {
			time = new LabeledLineEdit("Time", TextAlignment.Right, this);

			time.addEventListener((ChangeEvent!string ce) { changed(); });

			this.tabStop = false;
		}

	}

	private TimeOfDay value_;

	static if(UsingCustomWidgets) private {
		LabeledLineEdit time;
		string lastMsg;

		void changed() {
			try {
				value_ = TimeOfDay.fromISOExtString(time.content);

				this.emit!(ChangeEvent!TimeOfDay)(&value);
			} catch(Exception e) {
				if(e.msg != lastMsg) {
					messageBox(e.msg);
					lastMsg = e.msg;
				}
			}
		}
	}


	/++
		Current value the user selected. Please note this is NOT valid until AFTER a change event is emitted.
	+/
	TimeOfDay value() {
		return value_;
	}

	/++
		Changes the current value displayed. Will not send a change event.
	+/
	void value(TimeOfDay v) {
		static if(UsingWin32Widgets) {
			SYSTEMTIME st;
			st.wHour = v.hour;
			st.wMinute = v.minute;
			st.wSecond = v.second;
			SendMessage(hwnd, DTM_SETSYSTEMTIME, GDT_VALID, cast(LPARAM) &st);
		} else {
			time.content = value_.toISOExtString();
		}
	}

	static if(UsingWin32Widgets) {
		override int minHeight() { return defaultLineHeight + 6; }
		override int maxHeight() { return defaultLineHeight + 6; }

		override int handleWmNotify(NMHDR* hdr, int code, out int mustReturn) {
			switch(code) {
				case DTN_DATETIMECHANGE:
					auto lpChange = cast(LPNMDATETIMECHANGE) hdr;
					if(true || (lpChange.dwFlags & GDT_VALID)) { // this flag only set if you use SHOWNONE
						auto st = lpChange.st;
						value_ = TimeOfDay(st.wHour, st.wMinute, st.wSecond);

						this.emit!(ChangeEvent!TimeOfDay)(&value);

						mustReturn = true;
					}
				break;
				default:
			}
			return false;
		}

	} else {
		override int minHeight() { return defaultLineHeight + 4; }
		override int maxHeight() { return defaultLineHeight + 4; }
	}

	override bool encapsulatedChildren() {
		return true;
	}

	mixin Emits!(ChangeEvent!TimeOfDay);
}

/++
	A CalendarPicker is a rectangular input for picking a date or a range of dates on a
	calendar viewer.

	The current value is an [Interval] of dates. Please note that the interval is non-inclusive,
	that is, the end day is one day $(I after) the final date the user selected.

	If the user only selected one date, start will be the selection and end is the day after.
+/
/+
	Note the Windows control also supports bolding dates, changing the max selection count,
	week numbers, and more.
+/
class CalendarPicker : Widget {
	///
	this(Widget parent) {
		super(parent);
		static if(UsingWin32Widgets) {
			createWin32Window(this, "SysMonthCal32"w, null, MCS_MULTISELECT);
			SendMessage(hwnd, MCM_SETMAXSELCOUNT, int.max, 0);
		} else {
			start = new LabeledLineEdit("Start", this);
			end = new LabeledLineEdit("End", this);

			start.addEventListener((ChangeEvent!string ce) { changed(); });
			end.addEventListener((ChangeEvent!string ce) { changed(); });

			this.tabStop = false;
		}
	}

	static if(UsingCustomWidgets) private {
		LabeledLineEdit start;
		LabeledLineEdit end;
		string lastMsg;

		void changed() {
			try {
				value_ = Interval!Date(
					Date.fromSimpleString(start.content),
					Date.fromSimpleString(end.content) + 1.days
				);

				this.emit!(ChangeEvent!(Interval!Date))(&value);
			} catch(Exception e) {
				if(e.msg != lastMsg) {
					messageBox(e.msg);
					lastMsg = e.msg;
				}
			}
		}
	}

	private Interval!Date value_;

	/++
		Current value the user selected. Please note this is NOT valid until AFTER a change event is emitted.
	+/
	Interval!Date value() { return value_; }

	/++
		Sets a new interval. Remember, the end date of the interval is NOT included. You might want to `end + 1.days` when creating it.
	+/
	void value(Interval!Date v) {
		value_ = v;

		auto end = v.end - 1.days;

		static if(UsingWin32Widgets) {
			SYSTEMTIME[2] arr;

			arr[0].wYear = v.begin.year;
			arr[0].wMonth = v.begin.month;
			arr[0].wDay = v.begin.day;

			arr[1].wYear = end.year;
			arr[1].wMonth = end.month;
			arr[1].wDay = end.day;

			SendMessage(hwnd, MCM_SETSELRANGE, 0, cast(LPARAM) arr.ptr);
		} else {
			this.start.content = v.begin.toString();
			this.end.content = end.toString();
		}
	}

	static if(UsingWin32Widgets) {
		override int handleWmNotify(NMHDR* hdr, int code, out int mustReturn) {
			switch(code) {
				case MCN_SELECT:
					auto lpChange = cast(LPNMSELCHANGE) hdr;
					auto start = lpChange.stSelStart;
					auto end = lpChange.stSelEnd;

					auto et = Date(end.wYear, end.wMonth, end.wDay);
					et += dur!"days"(1);

					value_ = Interval!Date(
						Date(start.wYear, start.wMonth, start.wDay),
						Date(end.wYear, end.wMonth, end.wDay) + 1.days // the interval is non-inclusive
					);

					this.emit!(ChangeEvent!(Interval!Date))(&value);

					mustReturn = true;
				break;
				default:
			}
			return false;
		}
	}

	override bool encapsulatedChildren() {
		return true;
	}

	mixin Emits!(ChangeEvent!(Interval!Date));
}
