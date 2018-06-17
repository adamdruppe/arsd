/**
	This file is a port of some old C code I had.

	I'll eventually refactor it into something more D-like
*/
module arsd.midi;


import core.stdc.stdio;
import core.stdc.stdlib;

/* NOTE: MIDI files are BIG ENDIAN! */

struct MidiChunk {
	int timeStamp; // this is encoded my way. real file is msb == 1, more ubytes
	ubyte event; 	// Event << 8 | channel is how it is actually stored

	// for channel events
	ubyte channel; 	// see above - it is stored with event!
			// channel == track btw
	ubyte param1; 	// pitch (usually)
	ubyte param2; 	// volume  - not necessarily present

	ubyte status; // event << 4 | channel

	// for meta events (event = f, channel = f
	ubyte type;
	int length; // stored as variable length
	ubyte* data; // only allocated if event == 255

	MidiChunk* next; // next in the track

	// This stuff is just for playing help and such
	// It is only set if you call recalculateMidiAbsolutes, and probably
	// not maintained if you do edits
	int track;
	uint absoluteTime;
	uint absoluteTimeInMilliSeconds; // for convenience
	int absoluteWait;
	MidiChunk* nextAbsolute;
}

/*
	Meta event
	timeStamp = 0
	event = 255
	channel = event
	param1 param2 = not in gile
	length = variable
	data[length]
*/

struct MidiTrack {
	// MTrk header
	int lengthInBytes;
	MidiChunk* chunks; // linked list
		// the linked list should NOT hold the track ending chunk
		// just hold a null instead
}

struct Midi {
	// headers go here
	short type;
	short numTracks;
	short speed;
	MidiTrack* tracks; /* Array of numTracks size */

	// only set if you call recalculateMidiAbsolutes
	MidiChunk* firstAbsolute;
}


enum MIDI_EVENT_NOTE_OFF =		0x08;
enum MIDI_EVENT_NOTE_ON =		0x09;
enum MIDI_EVENT_NOTE_AFTERTOUCH =	0x0a;
enum MIDI_EVENT_CONTROLLER =		0x0b;
enum MIDI_EVENT_PROGRAM_CHANGE =	0x0c;// only one param
enum MIDI_EVENT_CHANNEL_AFTERTOUCH =	0x0d;// only one param
enum MIDI_EVENT_PITCH_BEND =		0x0e;



/*
static char[][] instrumentNames = {
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
};
*/


int addMidiTrack(Midi* mid){
	int trackNum;
	MidiTrack* tracks;
	tracks = cast(MidiTrack*) realloc(mid.tracks, MidiTrack.sizeof * (mid.numTracks + 1));
	if(tracks is null)
		return -1;
	
	mid.tracks = tracks;
	trackNum = mid.numTracks;
	mid.numTracks++;

	mid.tracks[trackNum].lengthInBytes = 0;
	mid.tracks[trackNum].chunks = null;

	return trackNum;
}

int addMidiEvent(Midi* mid, int track, int deltatime, int event, int channel, int value1, int value2){
	int length = 2;
	MidiChunk* c;
	MidiChunk* current, previous;
	if(track >= mid.numTracks)
		return -1;

	c = cast(MidiChunk*) malloc(MidiChunk.sizeof);
	if(c is null)
		return -1;

	c.timeStamp = deltatime;
	c.event = cast(ubyte) event;
	c.channel = cast(ubyte) channel;
	c.param1 = cast(ubyte) value1;
	c.param2 = cast(ubyte) value2;

	c.status = cast(ubyte) ((event << 4) | channel);

	c.type = 0;
	c.length = 0;
	c.data = null;

	c.next = null;


	previous = null;
	current = mid.tracks[track].chunks;
	while(current != null){
		previous = current;
		current = current . next;
	}

	if(previous){
		previous.next = c;
	} else {
		mid.tracks[track].chunks = c;
	}

	length += getvldLength(deltatime);
	if(event != MIDI_EVENT_CHANNEL_AFTERTOUCH &&
	   event != MIDI_EVENT_PROGRAM_CHANGE)
	   	length++; // param2
	mid.tracks[track].lengthInBytes += length;

	return 0;
}

int addMidiMetaEvent(Midi* mid, int track, int dt, int type, int length, ubyte* data){
	int len = 2;
	int a;
	MidiChunk* c;
	MidiChunk* current, previous;

	if(track >= mid.numTracks)
		return -1;

	c = cast(MidiChunk*) malloc(MidiChunk.sizeof);
	if(c == null)
		return -1;

	c.timeStamp = dt;
	c.event = 0xff;
	c.channel = 0;
	c.param1 = 0;
	c.param2 = 0;

	c.type = cast(ubyte) type;
	c.length = length;
	// copy data in
	c.data = cast(typeof(c.data)) malloc(length);
	if(c.data == null){
		free(c);
		return -1;
	}
	for(a = 0; a < length; a++)
		c.data[a] = data[a];


	c.next = null;


	previous = null;
	current = mid.tracks[track].chunks;
	while(current != null){
		previous = current;
		current = current . next;
	}

	if(previous){
		previous.next = c;
	} else {
		mid.tracks[track].chunks = c;
	}

	len += getvldLength(dt);
	len += length;

	mid.tracks[track].lengthInBytes += len;

	return 0;
}

int createMidi(Midi** midWhere){
	Midi* mid;

	mid = cast(Midi*) malloc(Midi.sizeof);
	if(mid == null)
		return 1;
	
	mid.type = 1;
	mid.numTracks = 0;
	mid.speed = 0x80; // 128 ticks per quarter note - potential FIXME
	mid.tracks = null;

	*midWhere = mid;
	return 0;
}

void freeChunkList(MidiChunk* c){
	if(c == null)
		return;
	freeChunkList(c.next);
	if(c.event == 255)
		free(c.data);
	free(c);
}

void freeMidi(Midi** mid){
	int a;
	Midi* m = *mid;

	for(a = 0; a < m.numTracks; a++)
		freeChunkList(m.tracks[a].chunks);
	free(m.tracks);
	free(m);
	*mid = null;
}

// FIXME: these fail on big endian machines
void write4(int v, FILE* fp){
	fputc(*(cast(ubyte*)&v + 3), fp);
	fputc(*(cast(ubyte*)&v + 2), fp);
	fputc(*(cast(ubyte*)&v + 1), fp);
	fputc(*(cast(ubyte*)&v + 0), fp);
}

void write2(short v, FILE* fp){
	fputc(*(cast(ubyte*)&v + 1), fp);
	fputc(*(cast(ubyte*)&v + 0), fp);
}

void writevld(uint v, FILE* fp){
	uint omg = v;
	ubyte a;
	ubyte[4] ubytes;
	int c = 0;
  more:
	a = cast(ubyte) (omg&(~(1 << 7)));
	omg >>= 7;
	if(omg){
		ubytes[c++]  = a;
		goto more;
	}

	ubytes[c] = a;

	for(; c >= 0; c--)
		fputc(ubytes[c] | (c ? (1<<7):0), fp);
}


int read4(FILE* fp){
	int v;

	*(cast(ubyte*)&v + 3) = cast(ubyte) fgetc(fp);
	*(cast(ubyte*)&v + 2) = cast(ubyte) fgetc(fp);
	*(cast(ubyte*)&v + 1) = cast(ubyte) fgetc(fp);
	*(cast(ubyte*)&v + 0) = cast(ubyte) fgetc(fp);

	return v;
}

short read2(FILE* fp){
	short v;
	*(cast(ubyte*)&v + 1) = cast(ubyte) fgetc(fp);
	*(cast(ubyte*)&v + 0) = cast(ubyte) fgetc(fp);

	return v;
}

uint readvld(FILE* fp){
	uint omg = 0;
	ubyte a;
  more:
	a = cast(ubyte) fgetc(fp);
	if(a & (1<<7)){
		a &= ~(1<<7);
		omg <<= 7;
		omg |= a;
		goto more;
	}

	omg <<= 7;
	omg |= a;

	return omg;
}



int getvldLength(uint v){
	int count = 0;
	uint omg = v;
	ubyte a;
  more:
	a = omg&((1 << 7)-1); //
	omg >>= 7;
	if(omg){
		a &= 1<<7;
		count++;
		goto more;
	}
	count++;
	return count;
}

// END: big endian fixme

int loadMidi(Midi** midWhere, const char* filename){
	int error = 0;
	FILE* fp;
	Midi* mid = null;
	int runningStatus;
	int t, a;
	int numtrk;

	int timestamp;
	int event;
	int channel;
	int param1;
	int type;
	int length;
	int param2;
	ubyte* data;

	int done;

	fp = fopen(filename, "rb");
	if(fp == null){
		fprintf(stderr, "Cannot load file %s.\n", filename);
		error = 1;
		goto cleanup1;
	}


	if(fgetc(fp) != 'M') goto badfile;
	if(fgetc(fp) != 'T') goto badfile;
	if(fgetc(fp) != 'h') goto badfile;
	if(fgetc(fp) != 'd') goto badfile;
	if(read4(fp) !=   6) goto badfile;

	if(createMidi(&mid) != 0){
		fprintf(stderr, "Could not allocate struct\n");
		error = 3;
		goto cleanup3;
	}

	mid.type = read2(fp);
	numtrk = read2(fp);
	mid.speed = read2(fp);

	for(t = 0; t < numtrk; t++){
		if(fgetc(fp) != 'M') goto badfile;
		if(fgetc(fp) != 'T') goto badfile;
		if(fgetc(fp) != 'r') goto badfile;
		if(fgetc(fp) != 'k') goto badfile;

		if(addMidiTrack(mid) < 0){
			fprintf(stderr, "add midi track failed \n");
			error = 3;
			goto cleanup3;
		}

//		mid.tracks[t].lengthInBytes = read4(fp) - 4;
		read4(fp); // ignoring it for now FIXME?

		done = 0;
		do{
			timestamp = readvld(fp);
			event = fgetc(fp);
			if(event == 0xff){
				type = fgetc(fp);
				length = readvld(fp);

				// potential optimization for malloc
				if(length){
					data = cast(typeof(data)) malloc(length);
					for(a = 0; a < length; a++)
						data[a] = cast(ubyte) fgetc(fp);
				} else
					data = null;


				if(type == 0x2f){
					done = 1;
				} else {
					// add the event to the list here
					// FIXME: error check
					addMidiMetaEvent(mid, t, timestamp,
						type, length, data);
				}
				if(data)
					free(data);
			} else {
				if(event < 0x80){
					param1 = event;
					event = runningStatus;
				} else {
					runningStatus = event;
					param1 = fgetc(fp);
				}

				channel = event&0x0f;
				event = event >> 4;
				if(event != MIDI_EVENT_PROGRAM_CHANGE
			 	&& event != MIDI_EVENT_CHANNEL_AFTERTOUCH)
					param2 = fgetc(fp);

				// add the event
				// FIXME: error check
				addMidiEvent(mid, t, timestamp, event, channel, param1, param2);
			}
		} while(!done);
	}

	goto success;
  badfile:
	fprintf(stderr, "The file is not in the right format. %c\n", fgetc(fp));
	error = 2;
  cleanup3:
  	if(mid != null)
		freeMidi(&mid);
  success:
	fclose(fp);
	*midWhere = mid;
  cleanup1:
	return error;
}






int saveMidi(Midi* mid, char* filename){
	int error = 0;
	FILE* fp;
	int t, a;
	int runningStatus = -1;
	int status;
	
	fp = fopen(filename, "wb");
	if(fp == null){
		fprintf(stderr, "Unable to open midi file (%s) for writing.\n", filename);
		error = 1;
		goto cleanup1;
	}

	fputc('M', fp);
	fputc('T', fp);
	fputc('h', fp);
	fputc('d', fp);

	write4(6, fp);
	write2(mid.type, fp);
	write2(mid.numTracks, fp);
	write2(mid.speed, fp);

	for(t = 0; t < mid.numTracks; t++){
		fputc('M', fp);
		fputc('T', fp);
		fputc('r', fp);
		fputc('k', fp);

		runningStatus = -1;

		write4(mid.tracks[t].lengthInBytes + 4, fp);
		MidiChunk* current;
		current = mid.tracks[t].chunks;
		while(current != null){
			writevld(current.timeStamp, fp);
			if(current.event == 0xff){
				fputc(current.event, fp);
				fputc(current.type, fp);
				writevld(current.length, fp);
				for(a = 0; a < current.length; a++)
					fputc(current.data[a], fp);
			} else {
				// FIXME: add support for writing running status
				status = current.event << 4 | current.channel;

			//	if(status != runningStatus){
					runningStatus = status;
					fputc(status, fp);
			//	}

				fputc(current.param1, fp);
				if(current.event != MIDI_EVENT_PROGRAM_CHANGE
			 &&current.event != MIDI_EVENT_CHANNEL_AFTERTOUCH)
					fputc(current.param2, fp);
			}
			current = current.next;
		}
		/* the end of track chunk */
		fputc(0, fp);
		fputc(0xff, fp);
		fputc(0x2f, fp);
		fputc(0x00, fp);
	}
/*  cleanup2:*/
	fclose(fp);
  cleanup1:
	return error;
}


int removeMidiTrack(Midi* m, int track){
	int a;
	if(track >= m.numTracks)
		return -1;

	for(a = track; a < m.numTracks-1; a++){
		m.tracks[a] = m.tracks[a+1];
	}

	m.numTracks--;

	return 0;
}

void printMidiEvent(MidiChunk* c){
	int e = c.event;
	printf("%d %s %d %d\n", c.timeStamp,
		 e == MIDI_EVENT_NOTE_OFF ? "Note off".ptr
		:e == MIDI_EVENT_NOTE_ON  ? "Note on".ptr
		:e == MIDI_EVENT_PROGRAM_CHANGE ? "Program change".ptr
		:e == MIDI_EVENT_NOTE_AFTERTOUCH ? "Aftertouch".ptr
		: "I dunno".ptr
	, c.param1, c.param2);
}

MidiChunk* getTrackNameChunk(Midi* m, int track){
	MidiChunk* c;

	if(track >= m.numTracks)
		return null;

	c = m.tracks[track].chunks;
	while(c){
		if(c.event == 0xff && c.type == 3)
			return c;

		c = c.next;
	}

	return c;
}

int getMidiTempo(Midi* m){
	int a;
	MidiChunk* c;
	for(a = 0; a < m.numTracks; a++){
		c = m.tracks[a].chunks;
		while(c){
			if(c.event == 0xff)
			if(c.type == 0x51){
				int p = 0;
				p |= cast(int)(c.data[0]) << 16;
				p |= cast(int)(c.data[1]) << 8;
				p |= cast(int)(c.data[2]) << 0;
				
				return 60000000 / p;
			}
			c = c.next;
		}
	}

	return 120;
}

int getTempoFromTempoEvent(MidiChunk* c){
	int tempo = -1;
	if(c.event == 0xff && c.type == 0x51){
		int p = 0;
		p |= cast(int)(c.data[0]) << 16;
		p |= cast(int)(c.data[1]) << 8;
		p |= cast(int)(c.data[2]) << 0;
		tempo = 60000000 / p;
	}
	return tempo;
}

// returns milliseconds to wait given the params
int getMidiWaitTime(Midi* mid, int timeStamp, int tempo){
	return (timeStamp * 60000) / (tempo * mid.speed);
}

// sets absolute values and links up, useful for playing or editing
// but remember you must recalculate them yourself if you change anything
// Returns the final absolute time in seconds
int recalculateMidiAbsolutes(Midi* mid){
	MidiChunk*[128] c;
	int[128] trackWaits;
	int playing;
	int waited;
	int minWait = 100000;
	int a;
	uint absoluteTime = 0;
	int tempo = 120;
	uint absoluteTimeInMilliSeconds = 0;
	int t;
	int timeOfLastEvent = 0;

	MidiChunk* absoulteCurrent;

	mid.firstAbsolute = null;
	absoulteCurrent = null;

	playing = mid.numTracks;
	for(a = 0; a < mid.numTracks; a++){
		c[a] = mid.tracks[a].chunks;
		if(c[a]){
		trackWaits[a] = c[a].timeStamp;
		if(trackWaits[a] < minWait)
			minWait = trackWaits[a];
		} else
			playing--;
	}

	while(playing){
		waited = minWait;
		minWait = 1000000;
		absoluteTime += waited;
		absoluteTimeInMilliSeconds += getMidiWaitTime(mid, waited, tempo);
	for(a = 0; a < mid.numTracks; a++){
		if(!c[a])
			continue;
		trackWaits[a] -= waited;
		if(trackWaits[a] == 0){

		t = getTempoFromTempoEvent(c[a]);
		if(t != -1)
			tempo = t;

		// append it to the list
		if(absoulteCurrent == null){
			mid.firstAbsolute = c[a];
			absoulteCurrent = c[a];
		} else {
			absoulteCurrent.nextAbsolute = c[a];
			absoulteCurrent = absoulteCurrent.nextAbsolute;
		}
			absoulteCurrent.nextAbsolute = null;
			absoulteCurrent.absoluteTime = absoluteTime;
			absoulteCurrent.absoluteTimeInMilliSeconds = absoluteTimeInMilliSeconds;
			absoulteCurrent.track = a;
			absoulteCurrent.absoluteWait = absoluteTime - timeOfLastEvent;

		timeOfLastEvent = absoluteTime;
		c[a] = c[a].next;
		if(c[a] == null){
			playing --;
			trackWaits[a] = 1000000;
		}
		else
			trackWaits[a] = c[a].timeStamp;
		}
		if(trackWaits[a] < minWait )
			minWait = trackWaits[a];
	}
	}


	return absoluteTimeInMilliSeconds / 1000;
}

// returns approximate seconds
int getMidiLength(Midi* mid){
	return recalculateMidiAbsolutes(mid);
}






import arsd.simpleaudio;

struct PlayingMidi {
	ushort channelMask; /* The channels that will be played */
	int[128] playtracks;

	// Callbacks
	// onPlayedNote. Args: this, note, midi ticks waited since last message
	// This is intended for tablature creation
	void function(void*, int, int) onPlayedNote;
	// onMidiEvent. Args: this, event being executed
	// This can be used to print it or whatever
	// If you return 1, it skips the event. Return 0 for normal operation
	int function(void*, MidiChunk*) onMidiEvent;

	Midi* mid;
	MidiOutput* dev;

	int transpose;
	float tempoMultiplier;

	/* This stuff is state for the midi in progress */
	int tempo;

	MidiChunk* current;

	int wait;
}


// the main loop for the first time
int resetPlayingMidi(PlayingMidi* pmid){
	pmid.current = pmid.mid.firstAbsolute;
	pmid.tempo = 120;
	pmid.wait = 0;
	if(pmid.current)
		return getMidiWaitTime(pmid.mid, pmid.current.absoluteWait, cast(int) (pmid.tempo * pmid.tempoMultiplier));
	return 0;
}

void setPlayingMidiDefaults(PlayingMidi* pmid){
	int a;
	pmid.channelMask =0xffff;
	for(a = 0; a < 128; a++)
		pmid.playtracks[a] = 1;

	pmid.onPlayedNote = null;
	pmid.onMidiEvent = null;

	pmid.mid = null;
	pmid.dev = null;

	pmid.transpose = 0;
	pmid.tempoMultiplier = 1.0;

}


void seekPlayingMidi(PlayingMidi* pmid, int sec){
	pmid.dev.silenceAllNotes();
	pmid.dev.reset();

	pmid.current = pmid.mid.firstAbsolute;
	while(pmid.current){
		if(pmid.current.absoluteTimeInMilliSeconds >= sec * 1000)
			break;
		pmid.current = pmid.current.next;
	}
}


// This is the main loop. Returns how many milliseconds to wait before
// calling it again. If zero, then the song is over.
int advancePlayingMidi(PlayingMidi* pmid){
	MidiChunk* c;
	if(pmid.current == null)
		return 0;
  more:
	c = pmid.current;
  	pmid.wait += c.absoluteWait;

	if(pmid.onMidiEvent){
		if(pmid.onMidiEvent(pmid, c))
			goto skip;
	}

	if(c.event != 0xff){
		if(pmid.playtracks[c.track]){
			if(pmid.channelMask & (1 << c.channel)){
				int note = c.param1;
				if(c.event == MIDI_EVENT_NOTE_ON
				  || c.event == MIDI_EVENT_NOTE_AFTERTOUCH
				  || c.event == MIDI_EVENT_NOTE_OFF){
					note += pmid.transpose;
					//skipCounter = SKIP_MAX;
				}

				if(pmid.dev)
					pmid.dev.writeMidiMessage(c.status, note, c.param2);
				if(pmid.onPlayedNote)
					if(c.event == MIDI_EVENT_NOTE_ON
							&& c.param2 != 0){
						pmid.onPlayedNote(pmid,
							note,
							(pmid.wait * 4) / (pmid.mid.speed));
						pmid.wait = 0;
					}
			}
		}
	} else {
		if(c.type == 0x51)
			pmid.tempo = getTempoFromTempoEvent(c);
	}

  skip:
	pmid.current = pmid.current.nextAbsolute;
	if(pmid.current)
		if(pmid.current.absoluteWait == 0)
			goto more;
		else
			return getMidiWaitTime(
				pmid.mid,
				pmid.current.absoluteWait,
				cast(int) (pmid.tempo * pmid.tempoMultiplier));
	else return 0;
}




version(MidiDemo) {





MidiOutput* globaldev;

version(Windows)
	import core.sys.windows.windows;
else {
	import core.sys.posix.unistd;
	void Sleep(int ms){
		usleep(ms*1000);
	}

	import core.stdc.signal;
	// FIXME: this sucks.
	extern(C)
	alias fuckyou = void function(int) @nogc nothrow @system;
	extern(C)
	void sigint(){
		if(globaldev){
			globaldev.silenceAllNotes();
			globaldev.reset();
			destroy(*globaldev);
		}
		exit(1);
	}
}

enum SKIP_MAX = 3000; // allow no more than about 3 seconds of silence
			 // if the -k option is set

// Potential FIXME: it doesn't support more than 128 tracks.

void awesome(void* midiptr, int note, int wait) {
	printf("%d %d ", wait, note);
	fflush(stdout);
}

// FIXME: add support for displaying lyrics
extern(C) int main(int argc, char** argv){
	int a, b;

	PlayingMidi pmid;

	int tempo = 120;
	Midi* mid;
	MidiOutput midiout = MidiOutput(0);
	MidiChunk*[128] c;

	int minWait = 10000, waited;
	int playing;

	int wait = 0;
	int num;

	char* filename = null;

	int verbose = 0;
	float tempoMultiplier = 1;
	int transpose = 0;
	int displayinfo = 0;
	int play = 1;
	int tracing = 0;
	int skip = 0;
	int[128] playtracks;
	int skipCounter = SKIP_MAX;

	ushort channelMask = 0xffff;

	int sleepTime = 0;

	version(Posix) {
		signal(SIGINT, cast(fuckyou) &sigint);
	}

	for(a = 0; a< 128; a++)
		playtracks[a] = 1;


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



	if(play){
		globaldev = &midiout;
	} else
		globaldev = null;


	recalculateMidiAbsolutes(mid);
	setPlayingMidiDefaults(&pmid);

	if(tracing)
		pmid.onPlayedNote = &awesome;
	pmid.mid = mid;
	pmid.dev = &midiout;

	for(a = 0; a < 127; a++)
		pmid.playtracks[a] = playtracks[a];
	
	pmid.channelMask = channelMask;
	pmid.transpose = transpose;
	pmid.tempoMultiplier = tempoMultiplier;


	sleepTime = resetPlayingMidi(&pmid);
	do {
	//printf("%d\n", sleepTime);
		if(play) {
			if(skip && sleepTime > 1000)
				 sleepTime = 1000;
			Sleep(sleepTime);
		}
		sleepTime = advancePlayingMidi(&pmid);
	} while(sleepTime);


/*
	playing = mid.numTracks;

	// prepare!
	for(a = 0; a < mid.numTracks; a++){
		c[a] = mid.tracks[a].chunks;
		if(c[a]){
		trackWaits[a] = c[a].timeStamp;
		if(trackWaits[a] < minWait)
			minWait = trackWaits[a];
		} else
			playing--;
	}

	while(playing){
		if(play && (!skip || skipCounter > 100)){
			Sleep(getMidiWaitTime(mid, minWait, (int)(tempo * tempoMultiplier)));
			if(skip)
			skipCounter -= getMidiWaitTime(mid, minWait, (int)(tempo*tempoMultiplier));
		}
		waited = minWait;
		minWait = 1000000;
		wait += waited;
	for(a = 0; a < mid.numTracks; a++){
		if(!c[a])
			continue;
		trackWaits[a] -= waited;
		if(trackWaits[a] == 0){
			if(c[a].event != 0xff){
				if(playtracks[a]){
				if(playchannels[c[a].channel]){
					int note = c[a].param1;
					if(c[a].event == MIDI_EVENT_NOTE_ON
					|| c[a].event == MIDI_EVENT_NOTE_AFTERTOUCH
					|| c[a].event == MIDI_EVENT_NOTE_OFF){
						note += transpose;
						skipCounter = SKIP_MAX;
					}

				if(play)
					writeMidiMessage(dev, c[a].status, note, c[a].param2);
				if(tracing)
				if(c[a].event == MIDI_EVENT_NOTE_ON
					&& c[a].param2 != 0){
					printf("%d %d ",
						(wait * 4) / (mid.speed),
						note);
					fflush(stdout);
					wait = 0;
				}
				}
				}
				// data output:
				// waittime note
				// waittime is in 1/16 notes
			} else {
				if(c[a].type == 0x51){
					tempo = getTempoFromTempoEvent(c[a]);
					if(verbose)
						printf("Tempo change: %d\n", tempo);
				}
			}
			c[a] = c[a].next;
			if(c[a] == null){
				playing --;
				trackWaits[a] = 1000000;
			}
			else
				trackWaits[a] = c[a].timeStamp;
		}

		if(trackWaits[a] < minWait )
			minWait = trackWaits[a];
	}
	}
*/

	freeMidi(&mid);

	return 0;
}
}
