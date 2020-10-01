/**
	This file is a port of some old C code I had for reading and writing .mid files. Not much docs, but viewing the source may be helpful.

	I'll eventually refactor it into something more D-like

	History:
		Written in C in August 2008

		Minimally ported to D in September 2017

		Updated May 2020 with significant changes.
*/
module arsd.midi;

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
	PlayStream playbackStream() {
		return PlayStream(this);
	}
}

struct PlayStream {
	static struct Event {
		/// This is how long you wait until triggering this event.
		/// Note it may be zero.
		Duration wait;

		/// And this is the event.
		MidiEvent event;

		string toString() {
			return event.toString();
		}

		/// informational
		MidiFile file;
		/// ditto
		MidiTrack track;
	}

	PlayStream save() {
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
			tp.track = file.tracks[idx];
		}

		this.currentTrack = -1;
		this.tempo = 500000;
		popFront();
	}

	//@nogc:

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

				pending = Event(0.seconds, f, file, tp.track);
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
		auto time = (minWait * tempo / file.timing).usecs;

		pending = Event(time, trackPositions[minWaitTrack].remaining[0], file, trackPositions[minWaitTrack].track);
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
	Event front() {
		return pending;
	}

	private uint tempo;
	private Event pending;
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
			if(newEvent.status == 0xff && newEvent.data1 == MetaEvent.EndOfTrack) {
				break;
			}
			events ~= newEvent;
		}
		//assert(begin - trackLength == buf.bytes.length);
	}

	MidiEvent[] events;

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
