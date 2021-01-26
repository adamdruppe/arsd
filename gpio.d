// See:  https://github.com/torvalds/linux/commit/b53911aa872db462be2e5f1dd611b25c4c2e663b
// and:  https://github.com/torvalds/linux/blob/a409ed156a90093a03fe6a93721ddf4c591eac87/include/uapi/linux/gpio.h
// the kernel didn't keep the v1 abi for long, there's a v2 thing less than a year later. This v2 thing is new in kernel 5.10
/++
	PRERELEASE EXPERIMENTAL MODULE / SUBJECT TO CHANGE WITHOUT WARNING / LIKELY TO CONTAIN BUGS

	Wrapper for gpio use on Linux. It uses the new kernel interface directly, and thus requires a Linux kernel version newer than 4.9. It also requires a Linux kernel newer than 4.9 (apt upgrade your raspian install if you don't already have that).

	Note that the kernel documentation is very clear: do NOT use this for anything you plan to distribute to others. It is really just for tinkering, not production. And if the kernel people say that, I say it like 1000x more.


	$(PITFALL This is a PRERELEASE EXPERIMENTAL MODULE SUBJECT TO CHANGE WITHOUT WARNING. It is LIKELY TO CONTAIN BUGS!)

	GPIOHANDLE_REQUEST_BIAS_PULL_UP and friends were added to the kernel in early 2020, so bleeding edge feature that is unlikely to work if you aren't that new too. My rpis do NOT support it. (the python library sets similar values tho by poking memory registers. I'm not gonna do that here, you can also solve it with electric circuit design (6k-ish ohm pull up and/or pull down resistor) or just knowing your own setup... so meh.)

	License: GPL-2.0 WITH Linux-syscall-note because it includes copy/pasted Linux kernel header code.
+/
module arsd.gpio;

version(linux):

import core.sys.posix.unistd;
import core.sys.posix.fcntl;
import core.sys.posix.sys.ioctl;

///
class CErrorException : Exception {
	this(string operation, string file = __FILE__, size_t line = __LINE__) {
		import core.stdc.errno;
		import core.stdc.string;
		auto err = strerror(errno);
		super(operation ~ ": " ~ cast(string) err[0 .. strlen(err)], file, line);
	}
}

private string c_dup(ref char[32] c) {
	foreach(idx, ch; c)
		if(ch == 0)
			return c[0 .. idx].idup;
	return null;
}

///
struct GpioChip {
	int fd = -1;

	///
	string name;
	///
	string label;
	///
	int lines;

	@disable this(this);

	/// "/dev/gpiochip0". Note it MUST be zero terminated!
	this(string name) {
		gpiochip_info info;

		fd = open(name.ptr, O_RDWR);
		if(fd == -1)
			throw new CErrorException("open " ~ name);

		if(ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &info) == -1)
			throw new CErrorException("ioctl get chip info");

		name = info.name.c_dup;
		label = info.label.c_dup;
		lines = info.lines;
	}

	///
	void getLineInfo(int line, out gpioline_info info) {
		info.line_offset = line;

		if(ioctl(fd, GPIO_GET_LINEINFO_IOCTL, &info) == -1)
			throw new CErrorException("ioctl get line info");
	}

	/// Returns a file descriptor you can pass to [pullLine] or [getLine] (pullLine for OUTPUT, getLine for INPUT).
	int requestLine(string label, scope uint[] lines, int flags, scope ubyte[] defaults) {
		assert(lines.length == defaults.length);

		gpiohandle_request req;

		req.lines = cast(uint) lines.length;
		req.flags = flags;
		req.lineoffsets[0 .. lines.length] = lines[];
		req.default_values[0 .. defaults.length] = defaults[];

		req.consumer_label[0 .. label.length] = label[];

		if(ioctl(fd, GPIO_GET_LINEHANDLE_IOCTL, &req) == -1)
			throw new CErrorException("ioctl get line handle");

		if(req.fd <= 0)
			throw new Exception("request line failed");

		return req.fd;
	}

	/// Returns a file descriptor you can poll and read for events. Read [gpioevent_data] from the fd.
	int requestEvent(string label, int line, int handleFlags, int eventFlags) {
		gpioevent_request req;
		req.lineoffset = line;
		req.handleflags = handleFlags;
		req.eventflags = eventFlags;
		req.consumer_label[0 .. label.length] = label[];


		if(ioctl(fd, GPIO_GET_LINEEVENT_IOCTL, &req) == -1)
			throw new CErrorException("get event handle");
		if(req.fd <= 0)
			throw new Exception("request event failed");

		return req.fd;
	}

	/// named as in "pull it high"; it sets the status.
	void pullLine(int handle, scope ubyte[] high) {
		gpiohandle_data data;

		data.values[0 .. high.length] = high[];

		if(ioctl(handle, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &data) == -1)
			throw new CErrorException("ioctl pull line");
	}

	///
	void getLine(int handle, scope ubyte[] status) {
		gpiohandle_data data;

		if(ioctl(handle, GPIOHANDLE_GET_LINE_VALUES_IOCTL, &data) == -1)
			throw new CErrorException("ioctl get line");

		status = data.values[0 .. status.length];
	}

	~this() {
		if(fd != -1)
			close(fd);
		fd = -1;
	}
}

void main() {
	import std.stdio;
	GpioChip g = GpioChip("/dev/gpiochip0");

	auto ledfd = g.requestLine("D test", [18], GPIOHANDLE_REQUEST_OUTPUT, [0]);
	scope(exit) close(ledfd);
	auto btnfd = g.requestEvent("D test", 15, GPIOHANDLE_REQUEST_INPUT, GPIOEVENT_REQUEST_BOTH_EDGES);
	scope(exit) close(btnfd);

	/*
	gpioline_info info;
	foreach(line; 0 .. g.lines) {
		g.getLineInfo(line, info);
		writeln(line, ": ", info.flags, " ", info.name, " ", info.consumer);
	}
	*/

	import core.thread;

	writeln("LED on");
	g.pullLine(ledfd, [1]);

	foreach(i; 0 .. 3) {
	gpioevent_data event;
	read(btnfd, &event, event.sizeof);

	writeln(event);
	}

	writeln("LED off");
	g.pullLine(ledfd, [0]);
}




// copy/paste port of linux/gpio.h from the kernel
// (this is why it inherited the GPL btw)
extern(C) {

	import core.sys.posix.sys.ioctl;

	/**
		Information about a certain GPIO chip. ioctl [GPIO_GET_CHIPINFO_IOCTL]
	*/
	struct gpiochip_info {
		/// the Linux kernel name of this GPIO chip
		char[32] name = 0;
		/// a functional name for this GPIO chip, such as a product number, may be null
		char[32] label = 0;
		/// number of GPIO lines on this chip
		uint lines;
	}

	enum GPIOLINE_FLAG_KERNEL = (1 << 0); /// Informational flags
	enum GPIOLINE_FLAG_IS_OUT = (1 << 1); /// ditto
	enum GPIOLINE_FLAG_ACTIVE_LOW = (1 << 2); /// ditto
	enum GPIOLINE_FLAG_OPEN_DRAIN = (1 << 3); /// ditto
	enum GPIOLINE_FLAG_OPEN_SOURCE = (1 << 4); /// ditto
	enum GPIOLINE_FLAG_BIAS_PULL_UP = (1 << 5); /// ditto
	enum GPIOLINE_FLAG_BIAS_PULL_DOWN = (1 << 6); /// ditto
	enum GPIOLINE_FLAG_BIAS_DISABLE = (1 << 7); /// ditto

	/**
		Information about a certain GPIO line
	*/
	struct gpioline_info {
		/// the local offset on this GPIO device, fill this in when requesting the line information from the kernel
		uint line_offset;
		/// various flags for this line
		uint flags;
		/// the name of this GPIO line, such as the output pin of the line on the chip, a rail or a pin header name on a board, as specified by the gpio chip, may be null
		char[32] c_name = 0;
		/// a functional name for the consumer of this GPIO line as set by whatever is using it, will be null if there is no current user but may also be null if the consumer doesn't set this up
		char[32] c_consumer = 0;

		///
		string name() { return c_dup(c_name); }
		///
		string consumer() { return c_dup(c_consumer); }
	};

	/** Maximum number of requested handles */
	enum GPIOHANDLES_MAX = 64;

	/// line status change events
	enum {
		GPIOLINE_CHANGED_REQUESTED = 1,
		GPIOLINE_CHANGED_RELEASED,
		GPIOLINE_CHANGED_CONFIG,
	}

	/**
		Information about a change in status of a GPIO line


		Note: struct gpioline_info embedded here has 32-bit alignment on its own,
		but it works fine with 64-bit alignment too. With its 72 byte size, we can
		guarantee there are no implicit holes between it and subsequent members.
		The 20-byte padding at the end makes sure we don't add any implicit padding
		at the end of the structure on 64-bit architectures.
	*/
	struct gpioline_info_changed {
		gpioline_info info; /// updated line information
		ulong timestamp; /// estimate of time of status change occurrence, in nanoseconds and GPIOLINE_CHANGED_CONFIG
		uint event_type; /// one of GPIOLINE_CHANGED_REQUESTED, GPIOLINE_CHANGED_RELEASED
		uint[5] padding; /* for future use */
	}

	enum GPIOHANDLE_REQUEST_INPUT = (1 << 0); /// Linerequest flags
	enum GPIOHANDLE_REQUEST_OUTPUT = (1 << 1); /// ditto
	enum GPIOHANDLE_REQUEST_ACTIVE_LOW = (1 << 2); /// ditto
	enum GPIOHANDLE_REQUEST_OPEN_DRAIN = (1 << 3); /// ditto
	enum GPIOHANDLE_REQUEST_OPEN_SOURCE = (1 << 4); /// ditto
	enum GPIOHANDLE_REQUEST_BIAS_PULL_UP = (1 << 5); /// ditto
	enum GPIOHANDLE_REQUEST_BIAS_PULL_DOWN = (1 << 6); /// ditto
	enum GPIOHANDLE_REQUEST_BIAS_DISABLE = (1 << 7); /// ditto


	/**
		Information about a GPIO handle request
	*/
	struct gpiohandle_request {
		/// an array desired lines, specified by offset index for the associated GPIO device
		uint[GPIOHANDLES_MAX] lineoffsets;

		/// desired flags for the desired GPIO lines, such as GPIOHANDLE_REQUEST_OUTPUT, GPIOHANDLE_REQUEST_ACTIVE_LOW etc, OR:ed together. Note that even if multiple lines are requested, the same flags must be applicable to all of them, if you want lines with individual flags set, request them one by one. It is possible to select a batch of input or output lines, but they must all have the same characteristics, i.e. all inputs or all outputs, all active low etc
		uint flags;
		/// if the GPIOHANDLE_REQUEST_OUTPUT is set for a requested line, this specifies the default output value, should be 0 (low) or 1 (high), anything else than 0 or 1 will be interpreted as 1 (high)
		ubyte[GPIOHANDLES_MAX] default_values;
		/// a desired consumer label for the selected GPIO line(s) such as "my-bitbanged-relay"
		char[32] consumer_label = 0;
		/// number of lines requested in this request, i.e. the number of valid fields in the above arrays, set to 1 to request a single line
		uint lines;
		/// if successful this field will contain a valid anonymous file handle after a GPIO_GET_LINEHANDLE_IOCTL operation, zero or negative value means error
		int fd;
	}

	/// Configuration for a GPIO handle request
	/// Note: only in kernel newer than early 2020
	struct gpiohandle_config {
		uint flags; /// updated flags for the requested GPIO lines, such as GPIOHANDLE_REQUEST_OUTPUT, GPIOHANDLE_REQUEST_ACTIVE_LOW etc, OR:ed together
		ubyte[GPIOHANDLES_MAX] default_values; /// if the GPIOHANDLE_REQUEST_OUTPUT is set in flags, this specifies the default output value, should be 0 (low) or 1 (high), anything else than 0 or 1 will be interpreted as 1 (high)
		uint[4] padding; /// must be 0
	}

	///
	enum GPIOHANDLE_SET_CONFIG_IOCTL = _IOWR!gpiohandle_config(0xB4, 0x0a);


	/**
		Information of values on a GPIO handle
	*/
	struct gpiohandle_data {
		/// when getting the state of lines this contains the current state of a line, when setting the state of lines these should contain the desired target state
		ubyte[GPIOHANDLES_MAX] values;
	}

	enum GPIOHANDLE_GET_LINE_VALUES_IOCTL = _IOWR!gpiohandle_data(0xB4, 0x08); /// .
	enum GPIOHANDLE_SET_LINE_VALUES_IOCTL = _IOWR!gpiohandle_data(0xB4, 0x09); /// ditto
	enum GPIOEVENT_REQUEST_RISING_EDGE = (1 << 0); /// Eventrequest flags
	enum GPIOEVENT_REQUEST_FALLING_EDGE = (1 << 1); /// ditto
	enum GPIOEVENT_REQUEST_BOTH_EDGES = ((1 << 0) | (1 << 1)); /// ditto

	/**
		Information about a GPIO event request
	*/
	struct gpioevent_request {
		/// the desired line to subscribe to events from, specified by offset index for the associated GPIO device
		uint lineoffset;
		/// desired handle flags for the desired GPIO line, such as GPIOHANDLE_REQUEST_ACTIVE_LOW or GPIOHANDLE_REQUEST_OPEN_DRAIN
		uint handleflags;
		/// desired flags for the desired GPIO event line, such as GPIOEVENT_REQUEST_RISING_EDGE or GPIOEVENT_REQUEST_FALLING_EDGE
		uint eventflags;
		/// a desired consumer label for the selected GPIO line(s) such as "my-listener"
		char[32] consumer_label = 0;
		/// if successful this field will contain a valid anonymous file handle after a GPIO_GET_LINEEVENT_IOCTL operation, zero or negative value means error
		int fd;
	}

	enum GPIOEVENT_EVENT_RISING_EDGE = 0x01; /// GPIO event types
	enum GPIOEVENT_EVENT_FALLING_EDGE = 0x02; /// ditto


	/**
		The actual event being pushed to userspace
	*/
	struct gpioevent_data {
		/// best estimate of time of event occurrence, in nanoseconds
		ulong timestamp;
		/// event identifier
		uint id;
	}

	enum GPIO_GET_CHIPINFO_IOCTL = _IOR!gpiochip_info(0xB4, 0x01); /// .
	enum GPIO_GET_LINEINFO_WATCH_IOCTL = _IOWR!gpioline_info(0xB4, 0x0b); /// ditto
	enum GPIO_GET_LINEINFO_UNWATCH_IOCTL = _IOWR!uint(0xB4, 0x0c); /// ditto
	enum GPIO_GET_LINEINFO_IOCTL = _IOWR!gpioline_info(0xB4, 0x02); /// ditto
	enum GPIO_GET_LINEHANDLE_IOCTL = _IOWR!gpiohandle_request(0xB4, 0x03); /// ditto
	enum GPIO_GET_LINEEVENT_IOCTL = _IOWR!gpioevent_request(0xB4, 0x04); /// ditto
}
