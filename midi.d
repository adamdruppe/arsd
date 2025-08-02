/**
	This file is a port of some old C code I had for reading and writing .mid files. Not much docs, but viewing the source may be helpful.

	I'll eventually refactor it into something more D-like

	History:
		Written in C in August 2008

		Minimally ported to D in September 2017

		Updated May 2020 with significant changes.
*/
module arsd.midi;


/+
	So the midi ticks are defined in terms of per quarter note so that's good stuff.

	If you're reading live though you have milliseconds, and probably want to round them
	off a little to fit the beat.
+/

import core.time;

version(NewMidiDemo)
void main(string[] args) {
	auto f = new MidiFile();

	import std.file;

	//f.loadFromBytes(cast(ubyte[]) read("test.mid"));
	f.loadFromBytes(cast(ubyte[]) read(args[1]));

	import arsd.simpleaudio;
	import core.thread;

	auto o = MidiOutput(0);
	setSigIntHandler();
	scope(exit) {
		o.silenceAllNotes();
		o.reset();
		restoreSigIntHandler();
	}

	import std.stdio : writeln;
	foreach(item; f.playbackStream) {
		if(interrupted) return;

		Thread.sleep(item.wait);
		if(!item.event.isMeta)
			o.writeMidiMessage(item.event.status, item.event.data1, item.event.data2);
		else
			writeln(item);
	}

	return;

	auto t = new MidiTrack();
	auto t2 = new MidiTrack();

	f.tracks ~= t;
	f.tracks ~= t2;

	t.events ~= MidiEvent(0, 0x90, C, 127);
	t.events ~= MidiEvent(256, 0x90, C, 0);
	t.events ~= MidiEvent(256, 0x90, D, 127);
	t.events ~= MidiEvent(256, 0x90, D, 0);
	t.events ~= MidiEvent(256, 0x90, E, 127);
	t.events ~= MidiEvent(256, 0x90, E, 0);
	t.events ~= MidiEvent(256, 0x90, F, 127);
	t.events ~= MidiEvent(0, 0xff, 0x05, 0 /* unused */, ['h', 'a', 'm']);
	t.events ~= MidiEvent(256, 0x90, F, 0);

	t2.events ~= MidiEvent(0, (MIDI_EVENT_PROGRAM_CHANGE << 4) | 0x01, 68);
	t2.events ~= MidiEvent(128, 0x91, E, 127);
	t2.events ~= MidiEvent(0, 0xff, 0x05, 0 /* unused */, ['a', 'd', 'r']);
	t2.events ~= MidiEvent(1024, 0x91, E, 0);

	write("test.mid", f.toBytes());
}

@safe:

class MidiFile {
	///
	ubyte[] toBytes() {
		MidiWriteBuffer buf;

		buf.write("MThd");
		buf.write4(6);

		buf.write2(format);
		buf.write2(cast(ushort) tracks.length);
		buf.write2(timing);

		foreach(track; tracks) {
			auto data = track.toBytes();
			buf.write("MTrk");
			buf.write4(cast(int) data.length);
			buf.write(data);
		}

		return buf.bytes;
	}

	///
	void loadFromBytes(ubyte[] bytes) {
		// FIXME: actually read the riff header to skip properly
		if(bytes.length && bytes[0] == 'R')
			bytes = bytes[0x14 .. $];

		MidiReadBuffer buf = MidiReadBuffer(bytes);
		if(buf.readChars(4) != "MThd")
			throw new Exception("not midi");
		if(buf.read4() != 6)
			throw new Exception("idk what this even is");
		this.format = buf.read2();
		this.tracks = new MidiTrack[](buf.read2());
		this.timing = buf.read2();

		foreach(ref track; tracks) {
			track = new MidiTrack();
			track.loadFromBuffer(buf);
		}
	}

	// when I read, I plan to cut the end of track marker off.

	// 0 == combined into one track
	// 1 == multiple tracks
	// 2 == multiple one-track patterns
	ushort format = 1;

	// FIXME
	ushort timing = 0x80; // 128 ticks per quarter note

	MidiTrack[] tracks;

	/++
		Returns a forward range for playback. Each item is a command, which
		is like the midi event but with some more annotations and control methods.

		Modifying this MidiFile object or any of its children during playback
		may cause trouble.

		Note that you do not need to handle any meta events, it keeps the
		tempo internally, but you can look at it if you like.
	+/
	const(PlayStreamEvent)[] playbackStream() {
		PlayStreamEvent[] stream;
		size_t size;
		foreach(track; tracks)
			size += track.events.length;
		stream.reserve(size);

		Duration position;

		static struct NoteOnInfo {
			PlayStreamEvent* event;
			int turnedOnTicks;
			Duration turnedOnPosition;
		}
		NoteOnInfo[] noteOnInfo = new NoteOnInfo[](128 * 16);
		scope(exit) noteOnInfo = null;

		static struct LastNoteInfo {
			PlayStreamEvent*[6] event; // in case there's a chord
			int eventCount;
			int turnedOnTicks;
		}
		LastNoteInfo[/*16*/] lastNoteInfo = new LastNoteInfo[](16); // it doesn't allow the static array cuz of @safe and i don't wanna deal with that so just doing this, nbd alloc anyway

		void recordOff(scope NoteOnInfo* noi, int midiClockPosition) {
			noi.event.noteOnDuration = position - noi.turnedOnPosition;

			noi.event = null;
		}

		// FIXME: what about rests?
		foreach(item; flattenedTrackStream) {
			position += item.wait;

			stream ~= item;

			if(item.event.event == MIDI_EVENT_NOTE_ON) {
				if(item.event.data2 == 0)
					goto off;

				auto ptr = &stream[$-1];

				auto noi = &noteOnInfo[(item.event.channel & 0x0f) * 128 + (item.event.data1 & 0x7f)];

				if(noi.event) {
					recordOff(noi, item.midiClockPosition);
				}

				noi.event = ptr;
				noi.turnedOnTicks = item.midiClockPosition;
				noi.turnedOnPosition = position;

				auto lni = &lastNoteInfo[(item.event.channel & 0x0f)];
				if(lni.eventCount) {
					if(item.midiClockPosition == lni.turnedOnTicks) {
						if(lni.eventCount == lni.event.length)
							goto maxedOut;
						lni.event[lni.eventCount++] = ptr;
					} else {
						maxedOut:
						foreach(ref e; lni.event[0 .. lni.eventCount])
							e.midiTicksToNextNoteOnChannel = item.midiClockPosition - lni.turnedOnTicks;

						goto frist;
					}
				} else {
					frist:
					lni.event[0] = ptr;
					lni.eventCount = 1;
					lni.turnedOnTicks = item.midiClockPosition;
				}

			} else if(item.event.event == MIDI_EVENT_NOTE_OFF) {
				off:
				auto noi = &noteOnInfo[(item.event.channel & 0x0f) * 128 + (item.event.data1 & 0x7f)];

				if(noi.event) {
					recordOff(noi, item.midiClockPosition);
				}
			}
		}

		return stream;
	}

	/++
		Returns a forward range for playback or analysis that flattens the midi
		tracks into a single stream. Each item is a command, which
		is like the midi event but with some more annotations and control methods.

		Modifying this MidiFile object or any of its children during iteration
		may cause trouble.

		Note that you do not need to handle any meta events, it keeps the
		tempo internally, but you can look at it if you like.
	+/
	FlattenedTrackStream flattenedTrackStream() {
		return FlattenedTrackStream(this);
	}
}

static struct PlayStreamEvent {
	/// This is how long you wait until triggering this event.
	/// Note it may be zero.
	Duration wait;

	/// And this is the midi event message.
	MidiEvent event;

	string toString() const {
		return event.toString();
	}

	/// informational. May be null if the stream didn't come from a file or tracks.
	MidiFile file;
	/// ditto
	MidiTrack track;

	/++
		Gives the position ot the global midi clock for this event. The `event.deltaTime`
		is in units of the midi clock, but the actual event has the clock per-track whereas
		this value is global, meaning it might not be the sum of event.deltaTime to this point.
		(It should add up if you only sum ones with the same [track] though.

		The midi clock is used in conjunction with the [MidiFile.timing] and current tempo
		state to determine a real time wait value, which you can find in the [wait] member.

		This position is probably less useful than the running sum of [wait]s, but is provided
		just in case it is useful to you.
	+/
	int midiClockPosition;

	/++
		The duration between this non-zero velocity note on and its associated note off.

		Will be zero if this isn't actually a note on, the input stream was not seekable (e.g.
		a real time recording), or if a note off was not found ahead in the stream.

		It is basically how long the pianist held down the key.

		Be aware that that the note on to note off is not necessarily associated with the
		note you'd see on sheet music. It is more about the time the sound actually rings,
		but it may not exactly be that either due to the time it takes for the note to
		fade out.
	+/
	Duration noteOnDuration;
	/++
		This is the count of midi clock ticks after this non-zero velocity note on event (if
		it is not one of those, this value will be zero) and the next note that will be sounded
		on its same channel.

		While rests may throw this off, this number is the most help in this struct for determining
		the note length you'd put on sheet music. Divide it by [MidiFile.timing] to get the number
		of midi quarter notes, which is directly correlated to the musical beat.

		Will be zero if this isn't actually a note on, the input stream was not seekable (e.g.
		a real time recording where the next note hasn't been struck yet), or if a note off was
		not found ahead in the stream.
	+/
	int midiTicksToNextNoteOnChannel;

	// when recording and working in milliseconds we prolly want to round off to the nearest 64th note, or even less fine grained at user command todeal with bad musicians (i.e. me) being off beat
}

static immutable(PlayStreamEvent)[] longWait = [{wait: 1.weeks, event: {status: 0xff, data1: 0x01, meta: null}}];

struct FlattenedTrackStream {

	FlattenedTrackStream save() {
		auto copy = this;
		copy.trackPositions = this.trackPositions.dup;
		return copy;
	}

	MidiFile file;
	this(MidiFile file) {
		this.file = file;
		this.trackPositions.length = file.tracks.length;
		foreach(idx, ref tp; this.trackPositions) {
			tp.remaining = file.tracks[idx].events[];

			{
				bool copyPerformed = false;

				// some midis do weird things
				// see: https://github.com/adamdruppe/arsd/issues/508
				// to correct:
				// first need to segment by the deltaTime - a non-zero, then all zeros that follow it.
				// then inside the same timestamp segments, put the note off (or note on with data2 == 0) first in the stream
				// make sure the first item has the non-zero deltaTime for the segment, then all others have 0.

				// returns true if you need to copy then try again
				bool sortSegment(MidiEvent[] events) {
					if(events.length <= 1)
						return false;

					bool hasNoteOn = false;
					bool needsChange = false;
					foreach(event; events) {
						if(hasNoteOn) {
							if(event.isNoteOff) {
								needsChange = true;
								break;
							}
						} else if(event.isNoteOn) {
							hasNoteOn = true;
						}
					}

					if(!needsChange)
						return false;

					if(!copyPerformed) {
						// so we don't modify the original file unnecessarily...
						return true;
					}

					auto dt = events[0].deltaTime;

					MidiEvent[8] staticBuffer;
					MidiEvent[] buffer;
					if(events.length < staticBuffer.length)
						buffer = staticBuffer[0 .. events.length];
					else
						buffer = new MidiEvent[](events.length);

					size_t bufferPos;

					// first pass, keep the note offs
					foreach(event; events) {
						if(event.isNoteOff)
							buffer[bufferPos++] = event;
					}

					// second pass, keep the rest
					foreach(event; events) {
						if(!event.isNoteOff)
							buffer[bufferPos++] = event;
					}

					assert(bufferPos == events.length);
					events[] = buffer[];

					foreach(ref e; events)
						e.deltaTime = 0;
					events[0].deltaTime = dt;

					return false;
				}

				size_t first = 0;
				foreach(sortIndex, f; tp.remaining) {
					if(f.deltaTime != 0) {
						if(sortSegment(tp.remaining[first .. sortIndex])) {
							//  if it returns true, it needs to modify the array
							// but it doesn't change the iteration result, just we need to send it the copy after making it
							tp.remaining = tp.remaining.dup;
							copyPerformed = true;
							sortSegment(tp.remaining[first .. sortIndex]);
						}
						first = sortIndex;
					}
				}

				if(sortSegment(tp.remaining[first .. $])) {
					tp.remaining = tp.remaining.dup;
					copyPerformed = true;
					sortSegment(tp.remaining[first .. $]);
				}
			}

			tp.track = file.tracks[idx];
		}

		this.currentTrack = -1;
		this.tempo = 500000; // microseconds per quarter note
		popFront();
	}

	//@nogc:

	int midiClock;

	void popFront() {
		done = true;
		for(auto c = currentTrack + 1; c < trackPositions.length; c++) {
			auto tp = trackPositions[c];

			if(tp.remaining.length && tp.remaining[0].deltaTime == tp.clock) {
				auto f = tp.remaining[0];
				trackPositions[c].remaining = tp.remaining[1 .. $];
				trackPositions[c].clock = 0;
				if(tp.remaining.length == 0 || tp.remaining[0].deltaTime > 0) {
					currentTrack += 1;
				}

				// import arsd.core; debug writeln(c, " ", f);

				pending = PlayStreamEvent(0.seconds, f, file, tp.track, midiClock);
				processPending();
				done = false;
				return;
			}
		}

		// if nothing happened there, time to advance the clock
		int minWait = int.max;
		int minWaitTrack = -1;
		foreach(idx, track; trackPositions) {
			if(track.remaining.length) {
				auto dt = track.remaining[0].deltaTime - track.clock;
				if(dt < minWait) {
					minWait = dt;
					minWaitTrack = cast(int) idx;
				}
			}
		}

		if(minWaitTrack == -1) {
			done = true;
			return;
		}

		foreach(ref tp; trackPositions) {
			tp.clock += minWait;
		}

		done = false;

		// file.timing, if high bit clear, is ticks per quarter note
		// if high bit set... idk it is different.
		//
		// then the temp is microseconds per quarter note.

		auto time = (cast(long) minWait * tempo / file.timing).usecs;
		midiClock += minWait;

		pending = PlayStreamEvent(time, trackPositions[minWaitTrack].remaining[0], file, trackPositions[minWaitTrack].track, midiClock);
		processPending();
		trackPositions[minWaitTrack].remaining = trackPositions[minWaitTrack].remaining[1 .. $];
		trackPositions[minWaitTrack].clock = 0;
		currentTrack = minWaitTrack;

		return;
	}

	private struct TrackPosition {
		MidiEvent[] remaining;
		int clock;
		MidiTrack track;
	}
	private TrackPosition[] trackPositions;
	private int currentTrack;

	private void processPending() {
		if(pending.event.status == 0xff && pending.event.data1 == MetaEvent.Tempo) {
			this.tempo = 0;
			foreach(i; pending.event.meta) {
				this.tempo <<= 8;
				this.tempo |= i;
			}
		}
	}

	@property
	PlayStreamEvent front() {
		return pending;
	}

	private uint tempo;
	private PlayStreamEvent pending;
	private bool done;

	@property
	bool empty() {
		return done;
	}

}

class MidiTrack {
	ubyte[] toBytes() {
		MidiWriteBuffer buf;
		foreach(event; events)
			event.writeToBuffer(buf);

		MidiEvent end;
		end.status = 0xff;
		end.data1 = 0x2f;
		end.meta = null;

		end.writeToBuffer(buf);

		return buf.bytes;
	}

	void loadFromBuffer(ref MidiReadBuffer buf) {
		if(buf.readChars(4) != "MTrk")
			throw new Exception("wtf no track header");

		auto trackLength = buf.read4();
		auto begin = buf.bytes.length;

		ubyte runningStatus;

		while(buf.bytes.length) {
			MidiEvent newEvent = MidiEvent.fromBuffer(buf, runningStatus);

			if(newEvent.isMeta && newEvent.data1 == MetaEvent.Name)
				name_ = cast(string) newEvent.meta.idup;

			if(newEvent.status == 0xff && newEvent.data1 == MetaEvent.EndOfTrack) {
				break;
			}
			events ~= newEvent;
		}
		//assert(begin - trackLength == buf.bytes.length);
	}

	/++
		All the midi events found in the track.
	+/
	MidiEvent[] events;
	/++
		The name of the track, as found from metadata at load time.

		This may change to scan events to see updates without the cache in the future.
	+/
	@property string name() {
		return name_;
	}

	private string name_;

	/++
		This field is not used or stored in a midi file; it is just
		a place to store some state in your player.

		I use it to keep flags like if the track is currently enabled.
	+/
	int customPlayerInfo;

	override string toString() const {
		string s;
		foreach(event; events)
			s ~= event.toString ~ "\n";
		return s;
	}
}

enum MetaEvent {
	SequenceNumber = 0,
	// these take a text param
	Text = 1,
	Copyright = 2,
	Name = 3,
	Instrument = 4,
	Lyric = 5,
	Marker = 6,
	CuePoint = 7,
	PatchName = 8,
	DeviceName = 9,

	// no param
	EndOfTrack = 0x2f,

	// different ones
	Tempo = 0x51, // 3 bytes form big-endian micro-seconds per quarter note. 120 BPM default.
	SMPTEOffset = 0x54, // 5 bytes. I don't get this one....
	TimeSignature = 0x58, // 4 bytes: numerator, denominator, clocks per click, 32nd notes per quarter note. (8 == quarter note gets the beat)
	KeySignature = 0x59, // 2 bytes: first byte is signed offset from C in semitones, second byte is 0 for major, 1 for minor

	// arbitrary length custom param
	Proprietary = 0x7f,

}

struct MidiEvent {
	int deltaTime;

	ubyte status;

	ubyte data1; // if meta, this is the identifier

	//union {
		//struct {
			ubyte data2;
		//}

		const(ubyte)[] meta; // iff status == 0xff
	//}

	invariant () {
		assert(status & 0x80);
		assert(!(data1 & 0x80));
		assert(!(data2 & 0x80));
		assert(status == 0xff || meta is null);
	}

	/// Convenience factories for various meta-events
	static MidiEvent Text(string t) { return MidiEvent(0, 0xff, MetaEvent.Text, 0, cast(const(ubyte)[]) t); }
	/// ditto
	static MidiEvent Copyright(string t) { return MidiEvent(0, 0xff, MetaEvent.Copyright, 0, cast(const(ubyte)[]) t); }
	/// ditto
	static MidiEvent Name(string t) { return MidiEvent(0, 0xff, MetaEvent.Name, 0, cast(const(ubyte)[]) t); }
	/// ditto
	static MidiEvent Lyric(string t) { return MidiEvent(0, 0xff, MetaEvent.Lyric, 0, cast(const(ubyte)[]) t); }
	/// ditto
	static MidiEvent Marker(string t) { return MidiEvent(0, 0xff, MetaEvent.Marker, 0, cast(const(ubyte)[]) t); }
	/// ditto
	static MidiEvent CuePoint(string t) { return MidiEvent(0, 0xff, MetaEvent.CuePoint, 0, cast(const(ubyte)[]) t); }

	/++
		Conveneince factories for normal events. These just put your given values into the event as raw data so you're responsible to know what they do.

		History:
			Added January 2, 2022 (dub v10.5)
	+/
	static MidiEvent NoteOn(int channel, int note, int velocity) { return MidiEvent(0, (MIDI_EVENT_NOTE_ON << 4) | (channel & 0x0f), note & 0x7f, velocity & 0x7f); }
	/// ditto
	static MidiEvent NoteOff(int channel, int note, int velocity) { return MidiEvent(0, (MIDI_EVENT_NOTE_OFF << 4) | (channel & 0x0f), note & 0x7f, velocity & 0x7f); }

	/+
	// FIXME: this is actually a relatively complicated one i should fix, it combines bits... 8192 == 0.
	// This is a bit of a magical function, it takes a signed bend between 0 and 81
	static MidiEvent PitchBend(int channel, int bend) {
		return MidiEvent(0, (MIDI_EVENT_PITCH_BEND << 4) | (channel & 0x0f), bend & 0x7f, bend & 0x7f);
	}
	+/
	// this overload ok, it is what the thing actually tells. coarse == 64 means we're at neutral.
	/// ditto
	static MidiEvent PitchBend(int channel, int fine, int coarse) { return MidiEvent(0, (MIDI_EVENT_PITCH_BEND << 4) | (channel & 0x0f), fine & 0x7f, coarse & 0x7f); }

	/// ditto
	static MidiEvent NoteAftertouch(int channel, int note, int velocity) { return MidiEvent(0, (MIDI_EVENT_NOTE_AFTERTOUCH << 4) | (channel & 0x0f), note & 0x7f, velocity & 0x7f); }
	// FIXME the different controllers do have standard IDs we could look up in an enum... and many of them have coarse/fine things you can send as two messages.
	/// ditto
	static MidiEvent Controller(int channel, int controller, int value) { return MidiEvent(0, (MIDI_EVENT_CONTROLLER << 4) | (channel & 0x0f), controller & 0x7f, value & 0x7f); }

	// the two byte ones
	/// ditto
	static MidiEvent ProgramChange(int channel, int program) { return MidiEvent(0, (MIDI_EVENT_PROGRAM_CHANGE << 4) | (channel & 0x0f), program & 0x7f); }
	/// ditto
	static MidiEvent ChannelAftertouch(int channel, int param) { return MidiEvent(0, (MIDI_EVENT_CHANNEL_AFTERTOUCH << 4) | (channel & 0x0f), param & 0x7f); }

	///
	bool isMeta() const {
		return status == 0xff;
	}

	///
	ubyte event() const {
		return status >> 4;
	}

	///
	ubyte channel() const {
		return status & 0x0f;
	}

	/++
		Returns true if it is either note off or note on with zero velocity, both of which should silence the note.

		History:
			Added July 20, 2025
	+/
	bool isNoteOff() const {
		// data1 is the note fyi
		return this.event == MIDI_EVENT_NOTE_OFF || (this.event == MIDI_EVENT_NOTE_ON && this.data2 == 0);
	}

	/++
		Returns true if it is a note on with non-zero velocity, which should sound a note.

		History:
			Added July 20, 2025

	+/
	bool isNoteOn() const {
		return this.event == MIDI_EVENT_NOTE_ON && this.data2 != 0;
	}

	///
	string toString() const {

		static string tos(int a) {
			char[16] buffer;
			auto bufferPos = buffer.length;
			do {
				buffer[--bufferPos] = a % 10 + '0';
				a /= 10;
			} while(a);

			return buffer[bufferPos .. $].idup;
		}

		static string toh(ubyte b) {
			char[2] buffer;
			buffer[0] = (b >> 4) & 0x0f;
			if(buffer[0] < 10)
				buffer[0] += '0';
			else
				buffer[0] += 'A' - 10;
			buffer[1] = b & 0x0f;
			if(buffer[1] < 10)
				buffer[1] += '0';
			else
				buffer[1] += 'A' - 10;

			return buffer.idup;
		}

		string s;
		s ~= tos(deltaTime);
		s ~= ": ";
		s ~= toh(status);
		s ~= " ";
		s ~= toh(data1);
		s ~= " ";

		if(isMeta) {
			switch(data1) {
				case MetaEvent.Text:
				case MetaEvent.Copyright:
				case MetaEvent.Name:
				case MetaEvent.Instrument:
				case MetaEvent.Lyric:
				case MetaEvent.Marker:
				case MetaEvent.CuePoint:
				case MetaEvent.PatchName:
				case MetaEvent.DeviceName:
					s ~= cast(const(char)[]) meta;
				break;
				case MetaEvent.TimeSignature:
					ubyte numerator = meta[0];
					ubyte denominator = meta[1];
					ubyte clocksPerClick = meta[2];
					ubyte notesPerQuarter = meta[3]; // 32nd notes / Q so 8 = quarter note gets the beat

					s ~= tos(numerator);
					s ~= "/";
					s ~= tos(denominator);
					s ~= " ";
					s ~= tos(clocksPerClick);
					s ~= " ";
					s ~= tos(notesPerQuarter);
				break;
				case MetaEvent.KeySignature:
					byte offset = meta[0];
					ubyte minor = meta[1];

					if(offset < 0) {
						s ~= "-";
						s ~= tos(-cast(int) offset);
					} else {
						s ~= tos(offset);
					}
					s ~= minor ? " minor" : " major";
				break;
				// case MetaEvent.Tempo:
					// could process this but idk if it needs to be shown
				// break;
				case MetaEvent.Proprietary:
					foreach(m; meta) {
						s ~= toh(m);
						s ~= " ";
					}
				break;
				default:
					s ~= cast(const(char)[]) meta;
			}
		} else {
			s ~= toh(data2);

			s ~= " ";
			s ~= tos(channel);
			s ~= " ";
			switch(event) {
				case MIDI_EVENT_NOTE_OFF: s ~= "NOTE_OFF"; break;
				case MIDI_EVENT_NOTE_ON: s ~=  data2 ? "NOTE_ON" : "NOTE_ON_ZERO"; break;
				case MIDI_EVENT_NOTE_AFTERTOUCH: s ~= "NOTE_AFTERTOUCH"; break;
				case MIDI_EVENT_CONTROLLER: s ~= "CONTROLLER"; break;
				case MIDI_EVENT_PROGRAM_CHANGE: s ~= "PROGRAM_CHANGE"; break;
				case MIDI_EVENT_CHANNEL_AFTERTOUCH: s ~= "CHANNEL_AFTERTOUCH"; break;
				case MIDI_EVENT_PITCH_BEND: s ~= "PITCH_BEND"; break;
				default:
			}
		}

		return s;
	}

	static MidiEvent fromBuffer(ref MidiReadBuffer buf, ref ubyte runningStatus) {
		MidiEvent event;

		start_over:

		event.deltaTime = buf.readv();

		auto nb = buf.read1();

		if(nb == 0xff) {
			// meta...
			event.status = 0xff;
			event.data1 = buf.read1(); // the type
			int len = buf.readv();
			auto meta = new ubyte[](len);
			foreach(idx; 0 .. len)
				meta[idx] = buf.read1();
			event.meta = meta;
		} else if(nb >= 0xf0) {
			// FIXME I'm just skipping this entirely but there might be value in here
			nb = buf.read1();
			while(nb < 0xf0)
				nb = buf.read1();
			goto start_over;
		} else if(nb & 0b1000_0000) {
			event.status = nb;
			runningStatus = nb;
			event.data1 = buf.read1();

			if(event.event != MIDI_EVENT_CHANNEL_AFTERTOUCH &&
				event.event != MIDI_EVENT_PROGRAM_CHANGE)
			{
				event.data2 = buf.read1();
			}
		} else {
			event.status = runningStatus;
			event.data1 = nb;

			if(event.event != MIDI_EVENT_CHANNEL_AFTERTOUCH &&
				event.event != MIDI_EVENT_PROGRAM_CHANGE)
			{
				event.data2 = buf.read1();
			}
		}

		return event;
	}

	void writeToBuffer(ref MidiWriteBuffer buf) const {
		buf.writev(deltaTime);
		buf.write1(status);
		// FIXME: what about other sysex stuff?
		if(meta) {
			buf.write1(data1);
			buf.writev(cast(int) meta.length);
			buf.write(meta);
		} else {
			buf.write1(data1);

			if(event != MIDI_EVENT_CHANNEL_AFTERTOUCH &&
				event != MIDI_EVENT_PROGRAM_CHANGE)
			{
				buf.write1(data2);
			}
		}
	}
}

struct MidiReadBuffer {
	ubyte[] bytes;

	char[] readChars(int len) {
		auto c = bytes[0 .. len];
		bytes = bytes[len .. $];
		return cast(char[]) c;
	}
	ubyte[] readBytes(int len) {
		auto c = bytes[0 .. len];
		bytes = bytes[len .. $];
		return c;
	}
	int read4() {
		int i;
		foreach(a; 0 .. 4) {
			i <<= 8;
			i |= bytes[0];
			bytes = bytes[1 .. $];
		}
		return i;
	}
	ushort read2() {
		ushort i;
		foreach(a; 0 .. 2) {
			i <<= 8;
			i |= bytes[0];
			bytes = bytes[1 .. $];
		}
		return i;
	}
	ubyte read1() {
		auto b = bytes[0];
		bytes = bytes[1 .. $];
		return b;
	}
	int readv() {
		int value = read1();
		ubyte c;
		if(value & 0x80) {
			value &= 0x7f;
			do
				value = (value << 7) | ((c = read1) & 0x7f);
			while(c & 0x80);
		}
		return value;
	}
}

struct MidiWriteBuffer {
	ubyte[] bytes;

	void write(const char[] a) {
		bytes ~= a;
	}

	void write(const ubyte[] a) {
		bytes ~= a;
	}

	void write4(int v) {
		// big endian
		bytes ~= (v >> 24) & 0xff;
		bytes ~= (v >> 16) & 0xff;
		bytes ~= (v >> 8) & 0xff;
		bytes ~= v & 0xff;
	}

	void write2(ushort v) {
		// big endian
		bytes ~= v >> 8;
		bytes ~= v & 0xff;
	}

	void write1(ubyte v) {
		bytes ~= v;
	}

	void writev(int v) {
		// variable
		uint buffer = v & 0x7f;
		while((v >>= 7)) {
			buffer <<= 8;
			buffer |= ((v & 0x7f) | 0x80);
		}

		while(true) {
			bytes ~= buffer & 0xff;
			if(buffer & 0x80)
				buffer >>= 8;
			else
				break;
		}
	}
}

import core.stdc.stdio;
import core.stdc.stdlib;

int freq(int note){
	import std.math;
	float r = note - 69;
	r /= 12;
	r = pow(2, r);
	r*= 440;
	return cast(int) r;
}

enum A =  69; // 440 hz per midi spec
enum As = 70;
enum B =  71;
enum C =  72; // middle C + 1 octave
enum Cs = 73;
enum D =  74;
enum Ds = 75;
enum E =  76;
enum F =  77;
enum Fs = 78;
enum G =  79;
enum Gs = 80;

immutable string[] noteNames = [ // just do note % 12 to index this
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
];

enum MIDI_EVENT_NOTE_OFF =		0x08;
enum MIDI_EVENT_NOTE_ON =		0x09;
enum MIDI_EVENT_NOTE_AFTERTOUCH =	0x0a;
enum MIDI_EVENT_CONTROLLER =		0x0b;
enum MIDI_EVENT_PROGRAM_CHANGE =	0x0c;// only one param
enum MIDI_EVENT_CHANNEL_AFTERTOUCH =	0x0d;// only one param
enum MIDI_EVENT_PITCH_BEND =		0x0e;


 /+
 35   Acoustic Bass Drum     59   Ride Cymbal 2
 36   Bass Drum 1            60   Hi Bongo
 37   Side Stick             61   Low Bongo
 38   Acoustic Snare         62   Mute Hi Conga
 39   Hand Clap              63   Open Hi Conga
 40   Electric Snare         64   Low Conga
 41   Low Floor Tom          65   High Timbale
 42   Closed Hi-Hat          66   Low Timbale
 43   High Floor Tom         67   High Agogo
 44   Pedal Hi-Hat           68   Low Agogo
 45   Low Tom                69   Cabasa
 46   Open Hi-Hat            70   Maracas
 47   Low-Mid Tom            71   Short Whistle
 48   Hi-Mid Tom             72   Long Whistle
 49   Crash Cymbal 1         73   Short Guiro
 50   High Tom               74   Long Guiro
 51   Ride Cymbal 1          75   Claves
 52   Chinese Cymbal         76   Hi Wood Block
 53   Ride Bell              77   Low Wood Block
 54   Tambourine             78   Mute Cuica
 55   Splash Cymbal          79   Open Cuica
 56   Cowbell                80   Mute Triangle
 57   Crash Cymbal 2         81   Open Triangle
 58   Vibraslap
 +/

static immutable string[] instrumentNames = [
"", // 0 is nothing
// Piano:
"Acoustic Grand Piano",
"Bright Acoustic Piano",
"Electric Grand Piano",
"Honky-tonk Piano",
"Electric Piano 1",
"Electric Piano 2",
"Harpsichord",
"Clavinet",

// Chromatic Percussion:
"Celesta",
"Glockenspiel",
"Music Box",
"Vibraphone",
"Marimba",
"Xylophone",
"Tubular Bells",
"Dulcimer",

// Organ:
"Drawbar Organ",
"Percussive Organ",
"Rock Organ",
"Church Organ",
"Reed Organ",
"Accordion",
"Harmonica",
"Tango Accordion",

// Guitar:
"Acoustic Guitar (nylon)",
"Acoustic Guitar (steel)",
"Electric Guitar (jazz)",
"Electric Guitar (clean)",
"Electric Guitar (muted)",
"Overdriven Guitar",
"Distortion Guitar",
"Guitar harmonics",

// Bass:
"Acoustic Bass",
"Electric Bass (finger)",
"Electric Bass (pick)",
"Fretless Bass",
"Slap Bass 1",
"Slap Bass 2",
"Synth Bass 1",
"Synth Bass 2",

// Strings:
"Violin",
"Viola",
"Cello",
"Contrabass",
"Tremolo Strings",
"Pizzicato Strings",
"Orchestral Harp",
"Timpani",

// Strings (continued):
"String Ensemble 1",
"String Ensemble 2",
"Synth Strings 1",
"Synth Strings 2",
"Choir Aahs",
"Voice Oohs",
"Synth Voice",
"Orchestra Hit",

// Brass:
"Trumpet",
"Trombone",
"Tuba",
"Muted Trumpet",
"French Horn",
"Brass Section",
"Synth Brass 1",
"Synth Brass 2",

// Reed:
"Soprano Sax",
"Alto Sax",
"Tenor Sax",
"Baritone Sax",
"Oboe",
"English Horn",
"Bassoon",
"Clarinet",

// Pipe:
"Piccolo",
"Flute",
"Recorder",
"Pan Flute",
"Blown Bottle",
"Shakuhachi",
"Whistle",
"Ocarina",

// Synth Lead:
"Lead 1 (square)",
"Lead 2 (sawtooth)",
"Lead 3 (calliope)",
"Lead 4 (chiff)",
"Lead 5 (charang)",
"Lead 6 (voice)",
"Lead 7 (fifths)",
"Lead 8 (bass + lead)",

// Synth Pad:
"Pad 1 (new age)",
"Pad 2 (warm)",
"Pad 3 (polysynth)",
"Pad 4 (choir)",
"Pad 5 (bowed)",
"Pad 6 (metallic)",
"Pad 7 (halo)",
"Pad 8 (sweep)",

// Synth Effects:
"FX 1 (rain)",
"FX 2 (soundtrack)",
"FX 3 (crystal)",
"FX 4 (atmosphere)",
"FX 5 (brightness)",
"FX 6 (goblins)",
"FX 7 (echoes)",
"FX 8 (sci-fi)",

// Ethnic:
"Sitar",
"Banjo",
"Shamisen",
"Koto",
"Kalimba",
"Bag pipe",
"Fiddle",
"Shanai",

// Percussive:
"Tinkle Bell",
"Agogo",
"Steel Drums",
"Woodblock",
"Taiko Drum",
"Melodic Tom",
"Synth Drum",

// Sound effects:
"Reverse Cymbal",
"Guitar Fret Noise",
"Breath Noise",
"Seashore",
"Bird Tweet",
"Telephone Ring",
"Helicopter",
"Applause",
"Gunshot"
];

version(MidiDemo) {


enum SKIP_MAX = 3000; // allow no more than about 3 seconds of silence
			 // if the -k option is set

// Potential FIXME: it doesn't support more than 128 tracks.

void awesome(void* midiptr, int note, int wait) {
	printf("%d %d ", wait, note);
	fflush(stdout);
}

// FIXME: add support for displaying lyrics
extern(C) int main(int argc, char** argv){

	for(a = 1; a < argc; a++){
		if(argv[a][0] == '-')
		switch(argv[a][1]){
			case 't':
				for(b = 0; b< 128; b++)
					playtracks[b] = 0;
				num = 0;
				b = 0;
				a++;
				if(a == argc){
					printf("%s: option %s requires an argument\n", argv[0], argv[a-1]);
					return 1;
				}
				for(b = 0; argv[a][b]; b++){
					if(argv[a][b] == ','){
						playtracks[num] = 1;
						num = 0;
						continue;
					}
					num *= 10;
					num += argv[a][b] - '0';
				}
				playtracks[num] = 1;
			break;
			case 's':
				a++;
				if(a == argc){
					printf("%s: option %s requires an argument\n", argv[0], argv[a-1]);
					return 1;
				}
				tempoMultiplier = atof(argv[a]);
			break;
			case 'i': // FIXME
				displayinfo = 1;
				// tracks, guesstimated length
			break;
			// -o loop to from
			// -b begin at
			// -e end at
			case 'l':
				tracing = 1;
			break;
			case 'n':
				play = 0;
			break;
			case 'k':
				skip = 1;
			break;
			case 'c':
				channelMask = 0;
				// channels
				num = 0;
				b = 0;
				a++;
				if(a == argc){
					printf("%s: option %s requires an argument\n", argv[0], argv[a-1]);
					return 1;
				}
				for(b = 0; argv[a][b]; b++){
					if(argv[a][b] == ','){
						channelMask |= (1 << num);
						num = 0;
						continue;
					}
					num *= 10;
					num += argv[a][b] - '0';
				}
					channelMask |= (1 << num);
			break;
			case 'r':
				a++;
				if(a == argc){
					printf("%s: option %s requires an argument\n", argv[0], argv[a-1]);
					return 1;
				}
				transpose = atoi(argv[a]);
			break;
			case 'v':
				verbose = 1;
			break;
			case 'h':
				printf("Usage: %s [options...] file\n", argv[0]);
				printf("  Options:\n");
				printf("  -t comma separated list of tracks to play (default: all)\n");
				printf("  -s tempo (speed) multiplier (default: 1.0)\n");
				printf("  -i file info (track list)\n");
				printf("  -l list notes as they are played (in the format totablature expects)\n");
				printf("  -n no sound; don't actually play the midi\n");
				printf("  -c comma separated list of channels to play (default: all)\n");
				printf("  -r transpose notes by amount (default: 0)\n");
				printf("  -k skip long sections of silence (good for playing single tracks)\n");

				printf("  -v verbose; list all events except note on / note off\n");
				printf("  -h shows this help screen\n");

				return 0;
			break;
			default:
				printf("%s: unknown command line option: %s\n", argv[0], argv[1]);
				return 1;
		}
		else
			filename = argv[a];
	}

	if(filename == null){
		printf("%s: no file given. Try %s -h for help.\n", argv[0], argv[0]);
		return 1;
	}

	loadMidi(&mid, filename);
	if(mid == null){
		printf("%s: unable to read file %s\n", argv[0], filename);
		return 1;
	}

	if(displayinfo){
		int len = getMidiLength(mid);
		printf("File: %s\n", filename);
		printf("Ticks per quarter note: %d\n", mid.speed);
		printf("Initial tempo: %d\n", getMidiTempo(mid));
		printf("Length: %d:%d\n", len / 60, len%60);
		printf("Tracks:\n");
		for(a = 0; a < mid.numTracks; a++){
			c[0] = getTrackNameChunk(mid, a);
			if(c[0] != null){
				printf("%d: ", a);
				for(b = 0; b < c[0].length; b++)
					fputc(c[0].data[b], stdout);
				printf("\n");
			}
		}

		freeMidi(&mid);
		return 0;
	}

	return 0;
}
}
