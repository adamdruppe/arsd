/++
	An add-on to [arsd.simpleaudio] that provides a MidiOutputThread
	that can play files from [arsd.midi].

	History:
		Added January 1, 2022 (dub v10.5). Not fully stablized but this
		release does almost everything I want right now, so I don't
		expect to change it much.
+/
module arsd.midiplayer;

// FIXME:  I want a record stream somewhere too, perhaps to a MidiFile and then a callback so you can inject events here as well.

import arsd.simpleaudio;
import arsd.midi;

/++
	[arsd.simpleaudio] provides a MidiEvent enum, but the one we're more
	interested here is the midi file format event, which is found in [arsd.midi].

	This alias disambiguates that we're interested in the file format one, not the enum.
+/
alias MidiEvent = arsd.midi.MidiEvent;

import core.thread;
import core.atomic;

/++
	This is the main feature of this module - a struct representing an automatic midi thread.

	It wraps [MidiOutputThreadImplementation] for convenient refcounting and raii messaging.

	You create this, optionally set your callbacks to filter/process events as they happen
	and deal with end of stream, then pass it a stream and events. The methods will give you
	control while the thread manages the timing and dispatching of events.
+/
struct MidiOutputThread {
	@disable this();

	static if(__VERSION__ < 2098)
		mixin(q{ @disable new(size_t); }); // gdc9 requires the arg fyi, but i mix it in because dmd deprecates before semantic so it can't be versioned out ugh
	else
		@disable new(); // but new dmd is strict about not allowing it

	/// it refcounts the impl.
	this(this) {
		if(impl)
			atomicOp!"+="(impl.refcount, 1);
	}
	/// when the refcount reaches zero, it exits the impl thread and waits for it to join.
	~this() {
		if(impl)
		if(atomicOp!"-="(impl.refcount, 1) == 0) {
			impl.exit();
			(cast() impl).join();
		}
		impl = null;
	}

	/++
		Creates a midi output thread using the given device, and starts it.
	+/
	this(string device, bool startSuspended = false) {
		auto thing = new MidiOutputThreadImplementation(device, startSuspended);
		impl = cast(shared) thing;
		thing.isDaemon = true;
		thing.start();

		// FIXME: check if successfully initialized
	}

	// FIXME: prolly opDispatch wrap it instead
	auto getImpl() { return impl; }
	/++
		You can call any `shared` member of [MidiOutputThreadImplementation] through this
		struct.
	+/
	alias getImpl this;

	private shared(MidiOutputThreadImplementation) impl;
}

class MidiOutputThreadImplementation : Thread {
	private int refcount = 1;

	/++
		Set this if you want to filter or otherwise respond to events.

		Return true to continue processing the event, return false if you want
		to skip it.

		The midi thread calls this function, so beware of cross-thread issues
		and make sure you spend as little time as possible in the callback to
		avoid throwing off time.
	+/
	void setCallback(bool delegate(const PlayStreamEvent) callback) shared {
		auto us = cast() this;
		synchronized(this)
			us.callback = callback;
	}

	/++
		Set this to customize what happens when a stream finishes.

		You can call [suspend], [loadStream], or [exit] to override
		the default behavior of looping the song. Or, return without
		calling anything to let it automatically start back over.
	+/
	void setStreamFinishedCallback(void delegate() callback) shared {
		auto us = cast() this;
		synchronized(this)
			us.streamFinishedCallback = callback;
	}

	/++
		Injects a midi event to the stream. It will be triggered as
		soon as possible and will NOT trigger you callback.
	+/
	void injectEvent(ubyte a, ubyte b, ubyte c) shared {
		auto us = cast() this;
		uint injected = a | (b << 8) | (c << 16);

		synchronized(this) {
			us.injectedEvents[(us.injectedEnd++) & 0x0f] = injected;
		}

		us.event.set();
	}

	/// ditto
	void injectEvent(MidiEvent event) shared {
		injectEvent(event.status, event.data1, event.data2);
	}

	/++
		Stops playback and closes the midi device, but keeps the thread waiting
		for an [unsuspend] call.

		When you do unsuspend, any stream will be restarted from the beginning.
	+/
	void suspend() shared {
		auto us = cast() this;
		us.suspended = true;
		us.event.set();
	}

	/// ditto
	void unsuspend() shared {
		auto us = cast() this;
		synchronized(this) {
			if(!this.filePending) {
				pendingStream = stream;
				filePending = true;
			}
		}
		us.suspended = false;
		us.event.set();
	}

	/++
		Pauses the midi playback. Will send a silence notes controller message to all channels, but otherwise leaves everything in place for a future call to [unpause].
	+/
	void pause() shared {
		auto us = cast() this;
		us.paused = true;
		us.event.set();
	}

	/// ditto
	void unpause() shared {
		auto us = cast() this;
		us.paused = false;
		us.event.set();
	}

	/// ditto
	void togglePause() shared {
		if(paused)
			unpause();
		else
			pause();
	}

	/++
		Stops the current playback stream. Will call the callback you set in [setCallback].

		Note: if you didn't set a callback, `stop` will end the stream, but then it will
		automatically loop back to the beginning!
	+/
	void stop() shared {
		auto us = cast() this;
		us.stopRequested = true;
		us.event.set();
	}

	/++
		Exits the thread. The object is not usable again after calling this.
	+/
	void exit() shared {
		auto us = cast() this;
		us.exiting = true;
		us.event.set();
	}

	/++
		Changes the speed of the playback clock to the given multiplier. So
		passing `2.0` will play at double real time. Calling it again will still
		play a double real time; the multiplier is always relative to real time
		and will not stack.
	+/
	void setSpeed(float multiplier) shared {
		auto us = cast() this;
		auto s = cast(int) (1000 * multiplier);
		if(s <= 0)
			s = 1;
		synchronized(this) {
			us.speed = s;
		}
		us.event.set();
	}

	/++
		If you want to use only injected events as a play stream,
		you might use arsd.midi.longWait here and just inject
		things as they come.
	+/
	void loadStream(const(PlayStreamEvent)[] pendingStream) shared {
		auto us = cast() this;
		synchronized(this) {
			us.pendingStream = pendingStream;
			us.filePending = true;
		}
		us.event.set();
	}

	/++
		Instructs the player to start playing - unsuspend if suspended,
		unpause if paused. If it is already playing, it will do nothing.
	+/
	void play() shared {
		auto us = cast() this;
		if(us.paused)
			unpause();
		if(us.suspended)
			unsuspend();
		us.event.set();
	}

	import core.sync.event;

	private Event event;
	private bool delegate(const PlayStreamEvent) callback;
	private void delegate() streamFinishedCallback;
	private bool paused;

	private uint[16] injectedEvents;
	private int injectedStart;
	private int injectedEnd;

	private string device;
	private bool filePending;
	private const(PlayStreamEvent)[] stream;
	private const(PlayStreamEvent)[] pendingStream;
	private const(PlayStreamEvent)[] loopStream;
	private bool suspended;
	private int speed = 1000;
	private bool exiting;
	private bool stopRequested;

	/+
		Do not modify the stream from outside!
	+/

	/++
		If you use the device string "DUMMY", it will still give you
		a timed thread with callbacks, but will not actually write to
		any midi device. You might use this if you want, for example,
		to display notes visually but not play them so a student can
		follow along with the computer.
	+/
	this(string device = "default", bool startSuspended = false) {
		this.device = device;
		super(&run);
		event.initialize(false, false);
		if(startSuspended)
			suspended = true;
	}

	private void run() {

		version(linux) {
			// this thread has no business intercepting signals from the main thread,
			// so gonna block a couple of them
			import core.sys.posix.signal;
			sigset_t sigset;
			auto err = sigemptyset(&sigset);
			assert(!err);

			err = sigaddset(&sigset, SIGINT); assert(!err);
			err = sigaddset(&sigset, SIGCHLD); assert(!err);

			err = sigprocmask(SIG_BLOCK, &sigset, null);
			assert(!err);
		}

		typeof(this.streamFinishedCallback) streamFinishedCallback;

		suspend:

		if(exiting)
			return;

		while(suspended) {
			event.wait();
			if(exiting)
				return;
		}

		MidiOutput midiOut = MidiOutput(device);
		bool justConstructed = true;
		scope(exit) {
			// the midi pages say not to send reset upon power up
			// so im trying not to send it too much. idk if it actually
			// matters tho.
			if(!justConstructed)
				midiOut.reset();
		}

		typeof(this.callback) callback;

		while(!filePending) {
			event.wait();
			if(exiting)
				return;
			if(suspended)
				goto suspend;
		}

		newFile:

		if(exiting)
			return;

		synchronized(this) {
			stream = pendingStream;
			filePending = false;
			pendingStream = null;
		}

		restart_song:

		if(exiting)
			return;

		if(!justConstructed) {
			midiOut.reset();
		}
		justConstructed = false;

		MMClock mmclock;
		Duration position;

		loopStream = stream;//.save();
		mmclock.restart();

		foreach(item; stream) {
			if(exiting)
				return;

			while(paused) {
				pause:
				midiOut.silenceAllNotes();
				mmclock.pause();
				event.wait();
				if(exiting)
					return;
				if(stopRequested)
					break;
				if(suspended)
					goto suspend;
				if(filePending)
					goto newFile;
			}

			mmclock.unpause();

			synchronized(this) {
				mmclock.speed = this.speed;

				callback = this.callback;
				playInjectedEvents(&midiOut);
			}

			position += item.wait;

			another_event:
			// FIXME: seeking
			// FIXME: push and pop song...
			// FIXME: note duration down to 64th notes would be like 30 ms at 120 bpm time....
			auto diff = mmclock.timeUntil(position);
			if(diff > 0.msecs) {
				if(!event.wait(diff)) {
					if(exiting)
						return;
					if(stopRequested)
						break;
					if(suspended)
						goto suspend;
					if(filePending)
						goto newFile;
					if(paused)
						goto pause;
					goto another_event;
				}
			}

			if(callback is null || callback(item)) {
				if(item.event.isMeta)
					continue;

				midiOut.writeMidiMessage(item.event.status, item.event.data1, item.event.data2);
			}
		}

		stopRequested = false;
		stream = loopStream;
		if(stream.length == 0) {
			// there's nothing to loop... exiting or suspending is the only real choice
			// this really should never happen but the idea is to avoid being stuck in
			// a busy loop.
			suspended = true;
		}

		synchronized(this)
			streamFinishedCallback = this.streamFinishedCallback;

		if(streamFinishedCallback) {
			streamFinishedCallback();
		} else {
			// default behavior?
			// maybe prepare loop and suspend...
			if(!filePending) {
				suspended = true;
			}
		}

		finalLoop:
		if(exiting)
			return;
		if(suspended)
			goto suspend;
		if(filePending)
			goto newFile;
		goto restart_song;
	}

	// Assumes this holds the `this` synchronized lock!!!
	private void playInjectedEvents(MidiOutput* midiOut) {
		while((injectedStart & 0x0f) != (injectedEnd & 0x0f)) {
			auto a = injectedEvents[injectedStart & 0x0f];
			injectedStart++;
			midiOut.writeMidiMessage(a & 0xff, (a >> 8) & 0xff, (a >> 16) & 0xff);
		}
	}
}

version(midiplayer_demo)
void main(string[] args) {
	import std.stdio;
	import std.file;
	auto f = new MidiFile;
	f.loadFromBytes(cast(ubyte[]) read(args[1]));

	auto t = MidiOutputThread("hw:4");
	t.setCallback(delegate(const PlayStreamEvent item) {

		if(item.event.channel == 0 && item.midiTicksToNextNoteOnChannel)
			writeln(item.midiTicksToNextNoteOnChannel * 64 / f.timing);
		return item.event.channel == 0;
	});

	t.loadStream(f.playbackStream);

	readln();

	/+
	t.loadStream(longWait);

	string s = readln();
	while(s.length) {
		t.injectEvent(MidiEvent.NoteOn(0, s[0], 127));
		s = readln()[0 .. $-1];
	}

	return;
	+/


	/+
	t.loadStream(f.playbackStream);

	//f = new MidiFile;
	//f.loadFromBytes(cast(ubyte[]) read(args[2]));

	//t.loadStream(f.playbackStream);


	t.setStreamFinishedCallback(delegate() {
		writeln("finished!");
		t.pause();
		//t.exit();
	});

	writeln("1");
	readln();
	writeln("2");
	//t.pause();

	t.setSpeed(12.0);

	while(readln().length) {
		t.injectEvent(MIDI_EVENT_NOTE_ON << 4, 55, 0);
	}

	//t.injectEvent(MIDI_EVENT_PROGRAM_CHANGE << 4, 55, 0);
	//t.injectEvent(1 | (MIDI_EVENT_PROGRAM_CHANGE << 4), 55, 0);

	writeln("3");
	readln();
	t.setSpeed(0.5);
	writeln("4");
	t.unpause();
	+/
}
