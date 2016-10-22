/**
	The purpose of this module is to provide audio functions for
	things like playback, capture, and volume on both Windows
	(via the mmsystem calls)and Linux (through ALSA).

	It is only aimed at the basics, and will be filled in as I want
	a particular feature. I don't generally need super configurability
	and see it as a minus, since I don't generally care either, so I'm
	going to be going for defaults that just work. If you need more though,
	you can hack the source or maybe just use it for the operating system
	bindings.

	For example, I'm starting this because I want to write a volume
	control program for my linux box, so that's what is going first.
	That will consist of a listening callback for volume changes and
	being able to get/set the volume.


	HOW IT WORKS:
		You make a callback which feeds data to the device. Make an
		AudioOutput struct then feed your callback to it. Then play.

		Then call loop? Or that could be in play?

		Methods:
			setCallback
			play
			pause


	TODO:
		* play audio high level with options to wait until completion or return immediately
		* midi mid-level stuff
		* audio callback stuff (it tells us when to fill the buffer)

		* Windows support for waveOut and waveIn. Maybe mixer too, but that's lowest priority.

		* I'll also write .mid and .wav functions at least eventually. Maybe in separate modules but probably here since they aren't that complex.

	I will probably NOT do OSS anymore, since my computer doesn't even work with it now.
	Ditto for Macintosh, as I don't have one and don't really care about them.
*/
module arsd.simpleaudio;

enum BUFFER_SIZE_FRAMES = 2048;
enum BUFFER_SIZE_SHORT = BUFFER_SIZE_FRAMES * 2;

version(Demo)
void main() {
	/*
	auto aio = AudioMixer(0);

	import std.stdio;
	writeln(aio.muteMaster);
	*/

	/*
	mciSendStringA("play test.wav", null, 0, null);
	Sleep(3000);
	import std.stdio;
	if(auto err = mciSendStringA("play test2.wav", null, 0, null))
		writeln(err);
	Sleep(6000);
	return;
	*/

	// output about a second of random noise to demo PCM
	auto ao = AudioOutput(0);
	short[BUFFER_SIZE_SHORT] randomSpam = void;
	import core.stdc.stdlib;
	foreach(ref s; randomSpam)
		s = cast(short)((cast(short) rand()) - short.max / 2);

	int loopCount = 40;

	//import std.stdio;
	//writeln("Should be about ", loopCount * BUFFER_SIZE_FRAMES * 1000 / 44100, " microseconds");

	int loops = 0;
	// only do simple stuff in here like fill the data, set simple
	// variables, or call stop anything else might cause deadlock
	ao.fillData = (short[] buffer) {
		buffer[] = randomSpam[0 .. buffer.length];
		loops++;
		if(loops == loopCount)
			ao.stop();
	};

	ao.play();

	return;

	// Play a C major scale on the piano to demonstrate midi
	auto midi = MidiOutput(0);

	ubyte[16] buffer = void;
	ubyte[] where = buffer[];
	midi.writeRawMessageData(where.midiProgramChange(1, 1));
	for(ubyte note = MidiNote.C; note <= MidiNote.C + 12; note++) {
		where = buffer[];
		midi.writeRawMessageData(where.midiNoteOn(1, note, 127));
		import core.thread;
		Thread.sleep(dur!"msecs"(500));
		midi.writeRawMessageData(where.midiNoteOff(1, note, 127));

		if(note != 76 && note != 83)
			note++;
	}
	import core.thread;
	Thread.sleep(dur!"msecs"(500)); // give the last note a chance to finish
}


import core.stdc.config;

version(linux) version=ALSA;
version(Windows) version=WinMM;

version(ALSA) {
	enum cardName = "plug:default";
	enum SampleRate = 44100;

	// this is the virtual rawmidi device on my computer at least
	// maybe later i'll make it probe
	//
	// Getting midi to actually play on Linux is a bit of a pain.
	// Here's what I did:
	/*
		# load the kernel driver, if amidi -l gives ioctl error,
		# you haven't done this yet!
		modprobe snd-virmidi

		# start a software synth. timidity -iA is also an option
		fluidsynth soundfont.sf2

		# connect the virtual hardware port to the synthesizer
		aconnect 24:0 128:0


		I might also add a snd_seq client here which is a bit
		easier to setup but for now I'm using the rawmidi so you
		gotta get them connected somehow.
	*/
	enum midiName = "hw:2,0";
}

/// Thrown on audio failures.
/// Subclass this to provide OS-specific exceptions
class AudioException : Exception {
	this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		super(message, file, line, next);
	}
}

/// Gives PCM input access (such as a microphone).
version(ALSA) // FIXME
struct AudioInput {
	version(ALSA) {
		snd_pcm_t* handle;
	}

	@disable this();
	@disable this(this);

	/// Always pass card == 0.
	this(int card) {
		assert(card == 0);

		version(ALSA) {
			handle = openAlsaPcm(snd_pcm_stream_t.SND_PCM_STREAM_CAPTURE);
		} else static assert(0);
	}

	/// Data is delivered as interleaved stereo, LE 16 bit, 44.1 kHz
	/// Each item in the array thus alternates between left and right channel
	/// and it takes a total of 88,200 items to make one second of sound.
	///
	/// Returns the slice of the buffer actually read into
	short[] read(short[] buffer) {
		version(ALSA) {
			snd_pcm_sframes_t read;

			read = snd_pcm_readi(handle, buffer.ptr, buffer.length / 2 /* div number of channels apparently */);
			if(read < 0)
				throw new AlsaException("pcm read", read);

			return buffer[0 .. read * 2];
		} else static assert(0);
	}

	// FIXME: add async function hooks

	~this() {
		version(ALSA) {
			snd_pcm_close(handle);
		} else static assert(0);
	}
}

/// Gives PCM output access (such as the speakers).
struct AudioOutput {
	version(ALSA) {
		snd_pcm_t* handle;
	} else version(WinMM) {
		HWAVEOUT handle;
	}

	@disable this();
	// This struct must NEVER be moved or copied, a pointer to it may
	// be passed to a device driver and stored!
	@disable this(this);

	/// Always pass card == 0.
	this(int card) {
		assert(card == 0);

		version(ALSA) {
			handle = openAlsaPcm(snd_pcm_stream_t.SND_PCM_STREAM_PLAYBACK);
		} else version(WinMM) {
			WAVEFORMATEX format;
			format.wFormatTag = WAVE_FORMAT_PCM;
			format.nChannels = 2;
			format.nSamplesPerSec = 44100;
			format.nAvgBytesPerSec = 44100 * 2 * 2; // two channels, two bytes per sample
			format.nBlockAlign = 4;
			format.wBitsPerSample = 16;
			format.cbSize = 0;
			if(auto err = waveOutOpen(&handle, WAVE_MAPPER, &format, &mmCallback, &this, CALLBACK_FUNCTION))
				throw new WinMMException("wave out open", err);
		} else static assert(0);
	}

	/// passes a buffer of data to fill
	///
	/// Data is assumed to be interleaved stereo, LE 16 bit, 44.1 kHz
	/// Each item in the array thus alternates between left and right channel
	/// and it takes a total of 88,200 items to make one second of sound.
	void delegate(short[]) fillData;

	shared(bool) playing = false; // considered to be volatile

	/// Starts playing, loops until stop is called
	void play() {
		assert(fillData !is null);
		playing = true;

		version(ALSA) {
			short[BUFFER_SIZE_SHORT] buffer;
			while(playing) {
				auto err = snd_pcm_wait(handle, 500);
				if(err < 0)
					throw new AlsaException("uh oh", err);
				// err == 0 means timeout
				// err == 1 means ready

				auto ready = snd_pcm_avail_update(handle);
				if(ready < 0)
					throw new AlsaException("avail", ready);
				if(ready > BUFFER_SIZE_FRAMES)
					ready = BUFFER_SIZE_FRAMES;
				fillData(buffer[0 .. ready * 2]);
				if(playing) {
					snd_pcm_sframes_t written;
					auto data = buffer[];

					while(data.length) {
						written = snd_pcm_writei(handle, data.ptr, data.length / 2);
						if(written < 0)
							throw new AlsaException("pcm write", written);
						data = data[written * 2 .. $];
					}
				}
			}
		} else version(WinMM) {

			enum numBuffers = 4; // use a lot of buffers to get smooth output with Sleep, see below
			short[BUFFER_SIZE_SHORT][numBuffers] buffers;

			WAVEHDR[numBuffers] headers;

			foreach(i, ref header; headers) {
				// since this is wave out, it promises not to write...
				auto buffer = buffers[i][];
				header.lpData = cast(void*) buffer.ptr;
				header.dwBufferLength = buffer.length * short.sizeof;
				header.dwFlags = WHDR_BEGINLOOP | WHDR_ENDLOOP;
				header.dwLoops = 1;

				if(auto err = waveOutPrepareHeader(handle, &header, header.sizeof))
					throw new WinMMException("prepare header", err);

				// prime it
				fillData(buffer[]);

				// indicate that they are filled and good to go
				header.dwUser = 1;
			}

			while(playing) {
				// and queue both to be played, if they are ready
				foreach(ref header; headers)
					if(header.dwUser) {
						if(auto err = waveOutWrite(handle, &header, header.sizeof))
							throw new WinMMException("wave out write", err);
						header.dwUser = 0;
					}
				Sleep(1);
				// the system resolution may be lower than this sleep. To avoid gaps
				// in output, we use multiple buffers. Might introduce latency, not
				// sure how best to fix. I don't want to busy loop...
			}

			// wait for the system to finish with our buffers
			bool anyInUse = true;

			while(anyInUse) {
				anyInUse = false;
				foreach(header; headers) {
					if(!header.dwUser) {
						anyInUse = true;
						break;
					}
				}
				if(anyInUse)
					Sleep(1);
			}

			foreach(ref header; headers) 
				if(auto err = waveOutUnprepareHeader(handle, &header, header.sizeof))
					throw new WinMMException("unprepare", err);
		} else static assert(0);
	}

	/// Breaks the play loop
	void stop() {
		playing = false;
	}

	version(WinMM) {
		extern(Windows)
		static void mmCallback(HWAVEOUT handle, UINT msg, void* userData, DWORD param1, DWORD param2) {
			AudioOutput* ao = cast(AudioOutput*) userData;
			if(msg == WOM_DONE) {
				auto header = cast(WAVEHDR*) param1;
				// we want to bounce back and forth between two buffers
				// to keep the sound going all the time
				if(ao.playing) {
					ao.fillData((cast(short*) header.lpData)[0 .. header.dwBufferLength / short.sizeof]);
				}
				header.dwUser = 1;
			}
		}
	}

	// FIXME: add async function hooks

	~this() {
		version(ALSA) {
			snd_pcm_close(handle);
		} else version(WinMM) {
			waveOutClose(handle);
		} else static assert(0);
	}
}

/// Gives MIDI output access.
struct MidiOutput {
	version(ALSA) {
		snd_rawmidi_t* handle;
	} else version(WinMM) {
		HMIDIOUT handle;
	}

	@disable this();
	@disable this(this);

	/// Always pass card == 0.
	this(int card) {
		assert(card == 0);

		version(ALSA) {
			if(auto err = snd_rawmidi_open(null, &handle, midiName, 0))
				throw new AlsaException("rawmidi open", err);
		} else version(WinMM) {
			if(auto err = midiOutOpen(&handle, 0, 0, 0, CALLBACK_NULL))
				throw new WinMMException("midi out open", err);
		} else static assert(0);
	}

	/// Send a reset message, silencing all notes
	void reset() {
		version(ALSA) {
			static immutable ubyte[3] resetSequence = [0x0b << 4, 123, 0];
			// send a controller event to reset it
			writeRawMessageData(resetSequence[]);
			// and flush it immediately
			snd_rawmidi_drain(handle);
		} else version(WinMM) {
			if(auto error = midiOutReset(handle))
				throw new WinMMException("midi reset", error);
		} else static assert(0);
	}

	/// Writes a single low-level midi message
	/// Timing and sending sane data is your responsibility!
	void writeMidiMessage(int status, int param1, int param2) {
		version(ALSA) {
			ubyte[3] dataBuffer;

			dataBuffer[0] = cast(ubyte) status;
			dataBuffer[1] = cast(ubyte) param1;
			dataBuffer[2] = cast(ubyte) param2;

			auto msg = status >> 4;
			ubyte[] data;
			if(msg == MidiEvent.ProgramChange || msg == MidiEvent.ChannelAftertouch)
				data = dataBuffer[0 .. 2];
			else
				data = dataBuffer[];

			writeRawMessageData(data);
		} else version(WinMM) {
			DWORD word = (param2 << 16) | (param1 << 8) | status;
			if(auto error = midiOutShortMsg(handle, word))
				throw new WinMMException("midi out", error);
		} else static assert(0);

	}

	/// Writes a series of individual raw messages.
	/// Timing and sending sane data is your responsibility!
	/// The data should NOT include any timestamp bytes - each midi message should be 2 or 3 bytes.
	void writeRawMessageData(scope const(ubyte)[] data) {
		version(ALSA) {
			ssize_t written;

			while(data.length) {
				written = snd_rawmidi_write(handle, data.ptr, data.length);
				if(written < 0)
					throw new AlsaException("midi write", cast(int) written);
				data = data[cast(int) written .. $];
			}
		} else version(WinMM) {
			while(data.length) {
				auto msg = data[0] >> 4;
				if(msg == MidiEvent.ProgramChange || msg == MidiEvent.ChannelAftertouch) {
					writeMidiMessage(data[0], data[1], 0);
					data = data[2 .. $];
				} else {
					writeMidiMessage(data[0], data[1], data[2]);
					data = data[3 .. $];
				}
			}
		} else static assert(0);
	}

	~this() {
		version(ALSA) {
			snd_rawmidi_close(handle);
		} else version(WinMM) {
			midiOutClose(handle);
		} else static assert(0);
	}
}


// FIXME: maybe add a PC speaker beep function for completeness

/// Interfaces with the default sound card. You should only have a single instance of this and it should
/// be stack allocated, so its destructor cleans up after it.
///
/// A mixer gives access to things like volume controls and mute buttons. It should also give a
/// callback feature to alert you of when the settings are changed by another program.
version(ALSA) // FIXME
struct AudioMixer {
	// To port to a new OS: put the data in the right version blocks
	// then implement each function. Leave else static assert(0) at the
	// end of each version group in a function so it is easier to implement elsewhere later.
	//
	// If a function is only relevant on your OS, put the whole function in a version block
	// and give it an OS specific name of some sort.
	//
	// Feel free to do that btw without worrying about lowest common denominator: we want low level access when we want it.
	//
	// Put necessary bindings at the end of the file, or use an import if you like, but I prefer these files to be standalone.
	version(ALSA) {
		snd_mixer_t* handle;
		snd_mixer_selem_id_t* sid;
		snd_mixer_elem_t* selem;

		c_long maxVolume, minVolume; // these are ok to use if you are writing ALSA specific code i guess

		enum selemName = "Master";
	}

	@disable this();
	@disable this(this);

	/// Only cardId == 0 is supported
	this(int cardId) {
		assert(cardId == 0, "Pass 0 to use default sound card.");

		version(ALSA) {
			if(auto err = snd_mixer_open(&handle, 0))
				throw new AlsaException("open sound", err);
			scope(failure)
				snd_mixer_close(handle);
			if(auto err = snd_mixer_attach(handle, cardName))
				throw new AlsaException("attach to sound card", err);
			if(auto err = snd_mixer_selem_register(handle, null, null))
				throw new AlsaException("register mixer", err);
			if(auto err = snd_mixer_load(handle))
				throw new AlsaException("load mixer", err);

			if(auto err = snd_mixer_selem_id_malloc(&sid))
				throw new AlsaException("master channel open", err);
			scope(failure)
				snd_mixer_selem_id_free(sid);
			snd_mixer_selem_id_set_index(sid, 0);
			snd_mixer_selem_id_set_name(sid, selemName);
			selem = snd_mixer_find_selem(handle, sid);
			if(selem is null)
				throw new AlsaException("find master element", 0);

			if(auto err = snd_mixer_selem_get_playback_volume_range(selem, &minVolume, &maxVolume))
				throw new AlsaException("get volume range", err);

			version(with_eventloop) {
				import arsd.eventloop;
				addFileEventListeners(getAlsaFileDescriptors()[0], &eventListener, null, null);
				setAlsaElemCallback(&alsaCallback);
			}
		} else static assert(0);
	}

	~this() {
		version(ALSA) {
			version(with_eventloop) {
				import arsd.eventloop;
				removeFileEventListeners(getAlsaFileDescriptors()[0]);
			}
			snd_mixer_selem_id_free(sid);
			snd_mixer_close(handle);
		} else static assert(0);
	}

	version(ALSA)
	version(with_eventloop) {
		static struct MixerEvent {}
		nothrow @nogc
		extern(C) static int alsaCallback(snd_mixer_elem_t*, uint) {
			import arsd.eventloop;
			try
				send(MixerEvent());
			catch(Exception)
				return 1;

			return 0;
		}

		void eventListener(int fd) {
			handleAlsaEvents();
		}
	}

	/// Gets the master channel's mute state
	/// Note: this affects shared system state and you should not use it unless the end user wants you to.
	@property bool muteMaster() {
		version(ALSA) {
			int result;
			if(auto err = snd_mixer_selem_get_playback_switch(selem, 0, &result))
				throw new AlsaException("get mute state", err);
			return result == 0;
		} else static assert(0);
	}

	/// Mutes or unmutes the master channel
	/// Note: this affects shared system state and you should not use it unless the end user wants you to.
	@property void muteMaster(bool mute) {
		version(ALSA) {
			if(auto err = snd_mixer_selem_set_playback_switch_all(selem, mute ? 0 : 1))
				throw new AlsaException("set mute state", err);
		} else static assert(0);
	}

	/// returns a percentage, between 0 and 100 (inclusive)
	int getMasterVolume() {
		version(ALSA) {
			auto volume = getMasterVolumeExact();
			return volume * 100 / (maxVolume - minVolume);
		} else static assert(0);
	}

	/// Gets the exact value returned from the operating system. The range may vary.
	int getMasterVolumeExact() {
		version(ALSA) {
			c_long volume;
			snd_mixer_selem_get_playback_volume(selem, 0, &volume);
			return volume;
		} else static assert(0);
	}

	/// sets a percentage on the volume, so it must be 0 <= volume <= 100
	/// Note: this affects shared system state and you should not use it unless the end user wants you to.
	void setMasterVolume(int volume) {
		version(ALSA) {
			assert(volume >= 0 && volume <= 100);
			setMasterVolumeExact(volume * (maxVolume - minVolume) / 100);
		} else static assert(0);
	}

	/// Sets an exact volume. Must be in range of the OS provided min and max.
	void setMasterVolumeExact(int volume) {
		version(ALSA) {
			if(auto err = snd_mixer_selem_set_playback_volume_all(selem, volume))
				throw new AlsaException("set volume", err);
		} else static assert(0);
	}

	version(ALSA) {
		/// Gets the ALSA descriptors which you can watch for events
		/// on using regular select, poll, epoll, etc.
		int[] getAlsaFileDescriptors() {
			import core.sys.posix.poll;
			pollfd[32] descriptors = void;
			int got = snd_mixer_poll_descriptors(handle, descriptors.ptr, descriptors.length);
			int[] result;
			result.length = got;
			foreach(i, desc; descriptors[0 .. got])
				result[i] = desc.fd;
			return result;
		}

		/// When the FD is ready, call this to let ALSA do its thing.
		void handleAlsaEvents() {
			snd_mixer_handle_events(handle);
		}

		/// Set a callback for the master volume change events.
		void setAlsaElemCallback(snd_mixer_elem_callback_t dg) {
			snd_mixer_elem_set_callback(selem, dg);
		}
	}
}

// ****************
// Midi helpers
// ****************

// FIXME: code the .mid file format, read and write

enum MidiEvent {
	NoteOff           = 0x08,
	NoteOn            = 0x09,
	NoteAftertouch    = 0x0a,
	Controller        = 0x0b,
	ProgramChange     = 0x0c, // one param
	ChannelAftertouch = 0x0d, // one param
	PitchBend         = 0x0e,
}

enum MidiNote : ubyte {
	middleC = 60,
	A =  69, // 440 Hz
	As = 70,
	B =  71,
	C =  72,
	Cs = 73,
	D =  74,
	Ds = 75,
	E =  76,
	F =  77,
	Fs = 78,
	G =  79,
	Gs = 80,
}

/// Puts a note on at the beginning of the passed slice, advancing it by the amount of the message size.
/// Returns the message slice.
///
/// See: http://www.midi.org/techspecs/midimessages.php
ubyte[] midiNoteOn(ref ubyte[] where, ubyte channel, byte note, byte velocity) {
	where[0] = (MidiEvent.NoteOn << 4) | (channel&0x0f);
	where[1] = note;
	where[2] = velocity;
	auto it = where[0 .. 3];
	where = where[3 .. $];
	return it;
}

/// Note off.
ubyte[] midiNoteOff(ref ubyte[] where, ubyte channel, byte note, byte velocity) {
	where[0] = (MidiEvent.NoteOff << 4) | (channel&0x0f);
	where[1] = note;
	where[2] = velocity;
	auto it = where[0 .. 3];
	where = where[3 .. $];
	return it;
}

/// Aftertouch.
ubyte[] midiNoteAftertouch(ref ubyte[] where, ubyte channel, byte note, byte pressure) {
	where[0] = (MidiEvent.NoteAftertouch << 4) | (channel&0x0f);
	where[1] = note;
	where[2] = pressure;
	auto it = where[0 .. 3];
	where = where[3 .. $];
	return it;
}

/// Controller.
ubyte[] midiNoteController(ref ubyte[] where, ubyte channel, byte controllerNumber, byte controllerValue) {
	where[0] = (MidiEvent.Controller << 4) | (channel&0x0f);
	where[1] = controllerNumber;
	where[2] = controllerValue;
	auto it = where[0 .. 3];
	where = where[3 .. $];
	return it;
}

/// Program change.
ubyte[] midiProgramChange(ref ubyte[] where, ubyte channel, byte program) {
	where[0] = (MidiEvent.ProgramChange << 4) | (channel&0x0f);
	where[1] = program;
	auto it = where[0 .. 2];
	where = where[2 .. $];
	return it;
}

/// Channel aftertouch.
ubyte[] midiChannelAftertouch(ref ubyte[] where, ubyte channel, byte amount) {
	where[0] = (MidiEvent.ProgramChange << 4) | (channel&0x0f);
	where[1] = amount;
	auto it = where[0 .. 2];
	where = where[2 .. $];
	return it;
}

/// Pitch bend. FIXME doesn't work right
ubyte[] midiNotePitchBend(ref ubyte[] where, ubyte channel, short change) {
/*
first byte is llllll
second byte is mmmmmm

Pitch Bend Change. 0mmmmmmm This message is sent to indicate a change in the pitch bender (wheel or lever, typically). The pitch bender is measured by a fourteen bit value. Center (no pitch change) is 2000H. Sensitivity is a function of the transmitter. (llllll) are the least significant 7 bits. (mmmmmm) are the most significant 7 bits.
*/
	where[0] = (MidiEvent.PitchBend << 4) | (channel&0x0f);
	// FIXME
	where[1] = 0;
	where[2] = 0;
	auto it = where[0 .. 3];
	where = where[3 .. $];
	return it;
}


// ****************
// Wav helpers
// ****************

// FIXME: the .wav file format should be here, read and write (at least basics)
// as well as some kind helpers to generate some sounds.

// ****************
// OS specific helper stuff follows
// ****************

version(ALSA)
// Opens the PCM device with default settings: stereo, 16 bit, 44.1 kHz, interleaved R/W.
snd_pcm_t* openAlsaPcm(snd_pcm_stream_t direction) {
	snd_pcm_t* handle;
	snd_pcm_hw_params_t* hwParams;

	/* Open PCM and initialize hardware */

	if (auto err = snd_pcm_open(&handle, cardName, direction, 0))
		throw new AlsaException("open device", err);
	scope(failure)
		snd_pcm_close(handle);

	if (auto err = snd_pcm_hw_params_malloc(&hwParams))
		throw new AlsaException("params malloc", err);
	scope(exit)
		snd_pcm_hw_params_free(hwParams);
			 
	if (auto err = snd_pcm_hw_params_any(handle, hwParams))
		throw new AlsaException("params init", err);

	if (auto err = snd_pcm_hw_params_set_access(handle, hwParams, snd_pcm_access_t.SND_PCM_ACCESS_RW_INTERLEAVED))
		throw new AlsaException("params access", err);

	if (auto err = snd_pcm_hw_params_set_format(handle, hwParams, snd_pcm_format.SND_PCM_FORMAT_S16_LE))
		throw new AlsaException("params format", err);

	uint rate = SampleRate;
	int dir = 0;
	if (auto err = snd_pcm_hw_params_set_rate_near(handle, hwParams, &rate, &dir))
		throw new AlsaException("params rate", err);

	if (auto err = snd_pcm_hw_params_set_channels(handle, hwParams, 2))
		throw new AlsaException("params channels", err);

	if (auto err = snd_pcm_hw_params(handle, hwParams))
		throw new AlsaException("params install", err);

	/* Setting up the callbacks */

	snd_pcm_sw_params_t* swparams;
	if(auto err = snd_pcm_sw_params_malloc(&swparams))
		throw new AlsaException("sw malloc", err);
	scope(exit)
		snd_pcm_sw_params_free(swparams);
	if(auto err = snd_pcm_sw_params_current(handle, swparams))
		throw new AlsaException("sw set", err);
	if(auto err = snd_pcm_sw_params_set_avail_min(handle, swparams, BUFFER_SIZE_FRAMES))
		throw new AlsaException("sw min", err);
	if(auto err = snd_pcm_sw_params_set_start_threshold(handle, swparams, 0))
		throw new AlsaException("sw threshold", err);
	if(auto err = snd_pcm_sw_params(handle, swparams))
		throw new AlsaException("sw params", err);

	/* finish setup */

	if (auto err = snd_pcm_prepare(handle))
		throw new AlsaException("prepare", err);

	assert(handle !is null);
	return handle;
}

version(ALSA)
class AlsaException : AudioException {
	this(string message, int error, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		auto msg = snd_strerror(error);
		import core.stdc.string;
		super(cast(string) (message ~ ": " ~ msg[0 .. strlen(msg)]), file, line, next);
	}
}

version(WinMM)
class WinMMException : AudioException {
	this(string message, int error, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		// FIXME: format the error
		// midiOutGetErrorText, etc.
		super(message, file, line, next);
	}
}

// ****************
// Bindings follow
// ****************

version(ALSA) {
extern(C):
@nogc nothrow:
	pragma(lib, "asound");
	private import core.sys.posix.poll;

	const(char)* snd_strerror(int);

	// pcm
	enum snd_pcm_stream_t {
		SND_PCM_STREAM_PLAYBACK,
		SND_PCM_STREAM_CAPTURE
	}

	enum snd_pcm_access_t {
		/** mmap access with simple interleaved channels */ 
		SND_PCM_ACCESS_MMAP_INTERLEAVED = 0, 
		/** mmap access with simple non interleaved channels */ 
		SND_PCM_ACCESS_MMAP_NONINTERLEAVED, 
		/** mmap access with complex placement */ 
		SND_PCM_ACCESS_MMAP_COMPLEX, 
		/** snd_pcm_readi/snd_pcm_writei access */ 
		SND_PCM_ACCESS_RW_INTERLEAVED, 
		/** snd_pcm_readn/snd_pcm_writen access */ 
		SND_PCM_ACCESS_RW_NONINTERLEAVED, 
		SND_PCM_ACCESS_LAST = SND_PCM_ACCESS_RW_NONINTERLEAVED
	}

	enum snd_pcm_format {
		/** Unknown */
		SND_PCM_FORMAT_UNKNOWN = -1,
		/** Signed 8 bit */
		SND_PCM_FORMAT_S8 = 0,
		/** Unsigned 8 bit */
		SND_PCM_FORMAT_U8,
		/** Signed 16 bit Little Endian */
		SND_PCM_FORMAT_S16_LE,
		/** Signed 16 bit Big Endian */
		SND_PCM_FORMAT_S16_BE,
		/** Unsigned 16 bit Little Endian */
		SND_PCM_FORMAT_U16_LE,
		/** Unsigned 16 bit Big Endian */
		SND_PCM_FORMAT_U16_BE,
		/** Signed 24 bit Little Endian using low three bytes in 32-bit word */
		SND_PCM_FORMAT_S24_LE,
		/** Signed 24 bit Big Endian using low three bytes in 32-bit word */
		SND_PCM_FORMAT_S24_BE,
		/** Unsigned 24 bit Little Endian using low three bytes in 32-bit word */
		SND_PCM_FORMAT_U24_LE,
		/** Unsigned 24 bit Big Endian using low three bytes in 32-bit word */
		SND_PCM_FORMAT_U24_BE,
		/** Signed 32 bit Little Endian */
		SND_PCM_FORMAT_S32_LE,
		/** Signed 32 bit Big Endian */
		SND_PCM_FORMAT_S32_BE,
		/** Unsigned 32 bit Little Endian */
		SND_PCM_FORMAT_U32_LE,
		/** Unsigned 32 bit Big Endian */
		SND_PCM_FORMAT_U32_BE,
		/** Float 32 bit Little Endian, Range -1.0 to 1.0 */
		SND_PCM_FORMAT_FLOAT_LE,
		/** Float 32 bit Big Endian, Range -1.0 to 1.0 */
		SND_PCM_FORMAT_FLOAT_BE,
		/** Float 64 bit Little Endian, Range -1.0 to 1.0 */
		SND_PCM_FORMAT_FLOAT64_LE,
		/** Float 64 bit Big Endian, Range -1.0 to 1.0 */
		SND_PCM_FORMAT_FLOAT64_BE,
		/** IEC-958 Little Endian */
		SND_PCM_FORMAT_IEC958_SUBFRAME_LE,
		/** IEC-958 Big Endian */
		SND_PCM_FORMAT_IEC958_SUBFRAME_BE,
		/** Mu-Law */
		SND_PCM_FORMAT_MU_LAW,
		/** A-Law */
		SND_PCM_FORMAT_A_LAW,
		/** Ima-ADPCM */
		SND_PCM_FORMAT_IMA_ADPCM,
		/** MPEG */
		SND_PCM_FORMAT_MPEG,
		/** GSM */
		SND_PCM_FORMAT_GSM,
		/** Special */
		SND_PCM_FORMAT_SPECIAL = 31,
		/** Signed 24bit Little Endian in 3bytes format */
		SND_PCM_FORMAT_S24_3LE = 32,
		/** Signed 24bit Big Endian in 3bytes format */
		SND_PCM_FORMAT_S24_3BE,
		/** Unsigned 24bit Little Endian in 3bytes format */
		SND_PCM_FORMAT_U24_3LE,
		/** Unsigned 24bit Big Endian in 3bytes format */
		SND_PCM_FORMAT_U24_3BE,
		/** Signed 20bit Little Endian in 3bytes format */
		SND_PCM_FORMAT_S20_3LE,
		/** Signed 20bit Big Endian in 3bytes format */
		SND_PCM_FORMAT_S20_3BE,
		/** Unsigned 20bit Little Endian in 3bytes format */
		SND_PCM_FORMAT_U20_3LE,
		/** Unsigned 20bit Big Endian in 3bytes format */
		SND_PCM_FORMAT_U20_3BE,
		/** Signed 18bit Little Endian in 3bytes format */
		SND_PCM_FORMAT_S18_3LE,
		/** Signed 18bit Big Endian in 3bytes format */
		SND_PCM_FORMAT_S18_3BE,
		/** Unsigned 18bit Little Endian in 3bytes format */
		SND_PCM_FORMAT_U18_3LE,
		/** Unsigned 18bit Big Endian in 3bytes format */
		SND_PCM_FORMAT_U18_3BE,
		/* G.723 (ADPCM) 24 kbit/s, 8 samples in 3 bytes */
		SND_PCM_FORMAT_G723_24,
		/* G.723 (ADPCM) 24 kbit/s, 1 sample in 1 byte */
		SND_PCM_FORMAT_G723_24_1B,
		/* G.723 (ADPCM) 40 kbit/s, 8 samples in 3 bytes */
		SND_PCM_FORMAT_G723_40,
		/* G.723 (ADPCM) 40 kbit/s, 1 sample in 1 byte */
		SND_PCM_FORMAT_G723_40_1B,
		/* Direct Stream Digital (DSD) in 1-byte samples (x8) */
		SND_PCM_FORMAT_DSD_U8,
		/* Direct Stream Digital (DSD) in 2-byte samples (x16) */
		SND_PCM_FORMAT_DSD_U16_LE,
		SND_PCM_FORMAT_LAST = SND_PCM_FORMAT_DSD_U16_LE,

		// I snipped a bunch of endian-specific ones!
	}

	struct snd_pcm_t {}
	struct snd_pcm_hw_params_t {}
	struct snd_pcm_sw_params_t {}

	int snd_pcm_open(snd_pcm_t**, const char*, snd_pcm_stream_t, int);
	int snd_pcm_close(snd_pcm_t*);
	int snd_pcm_prepare(snd_pcm_t*);
	int snd_pcm_hw_params(snd_pcm_t*, snd_pcm_hw_params_t*);
	int snd_pcm_hw_params_set_channels(snd_pcm_t*, snd_pcm_hw_params_t*, uint);
	int snd_pcm_hw_params_malloc(snd_pcm_hw_params_t**);
	void snd_pcm_hw_params_free(snd_pcm_hw_params_t*);
	int snd_pcm_hw_params_any(snd_pcm_t*, snd_pcm_hw_params_t*);
	int snd_pcm_hw_params_set_access(snd_pcm_t*, snd_pcm_hw_params_t*, snd_pcm_access_t);
	int snd_pcm_hw_params_set_format(snd_pcm_t*, snd_pcm_hw_params_t*, snd_pcm_format);
	int snd_pcm_hw_params_set_rate_near(snd_pcm_t*, snd_pcm_hw_params_t*, uint*, int*);

	int snd_pcm_sw_params_malloc(snd_pcm_sw_params_t**);
	void snd_pcm_sw_params_free(snd_pcm_sw_params_t*);

	int snd_pcm_sw_params_current(snd_pcm_t *pcm, snd_pcm_sw_params_t *params);
	int snd_pcm_sw_params(snd_pcm_t *pcm, snd_pcm_sw_params_t *params);
	int snd_pcm_sw_params_set_avail_min(snd_pcm_t*, snd_pcm_sw_params_t*, snd_pcm_uframes_t);
	int snd_pcm_sw_params_set_start_threshold(snd_pcm_t*, snd_pcm_sw_params_t*, snd_pcm_uframes_t);
	int snd_pcm_sw_params_set_stop_threshold(snd_pcm_t*, snd_pcm_sw_params_t*, snd_pcm_uframes_t);

	alias snd_pcm_sframes_t = c_long;
	alias snd_pcm_uframes_t = c_ulong;
	snd_pcm_sframes_t snd_pcm_writei(snd_pcm_t*, const void*, snd_pcm_uframes_t size);
	snd_pcm_sframes_t snd_pcm_readi(snd_pcm_t*, void*, snd_pcm_uframes_t size);

	int snd_pcm_wait(snd_pcm_t *pcm, int timeout);
	snd_pcm_sframes_t snd_pcm_avail(snd_pcm_t *pcm);
	snd_pcm_sframes_t snd_pcm_avail_update(snd_pcm_t *pcm);

	// raw midi

	static if(is(ssize_t == uint))
		alias ssize_t = int;
	else
		alias ssize_t = long;


	struct snd_rawmidi_t {}
	int snd_rawmidi_open(snd_rawmidi_t**, snd_rawmidi_t**, const char*, int);
	int snd_rawmidi_close(snd_rawmidi_t*);
	int snd_rawmidi_drain(snd_rawmidi_t*);
	ssize_t snd_rawmidi_write(snd_rawmidi_t*, const void*, size_t);
	ssize_t snd_rawmidi_read(snd_rawmidi_t*, void*, size_t);

	// mixer

	struct snd_mixer_t {}
	struct snd_mixer_elem_t {}
	struct snd_mixer_selem_id_t {}

	alias snd_mixer_elem_callback_t = int function(snd_mixer_elem_t*, uint);

	int snd_mixer_open(snd_mixer_t**, int mode);
	int snd_mixer_close(snd_mixer_t*);
	int snd_mixer_attach(snd_mixer_t*, const char*);
	int snd_mixer_load(snd_mixer_t*);

	// FIXME: those aren't actually void*
	int snd_mixer_selem_register(snd_mixer_t*, void*, void*);
	int snd_mixer_selem_id_malloc(snd_mixer_selem_id_t**);
	void snd_mixer_selem_id_free(snd_mixer_selem_id_t*);
	void snd_mixer_selem_id_set_index(snd_mixer_selem_id_t*, uint);
	void snd_mixer_selem_id_set_name(snd_mixer_selem_id_t*, const char*);
	snd_mixer_elem_t* snd_mixer_find_selem(snd_mixer_t*, in snd_mixer_selem_id_t*);

	// FIXME: the int should be an enum for channel identifier
	int snd_mixer_selem_get_playback_volume(snd_mixer_elem_t*, int, c_long*);

	int snd_mixer_selem_get_playback_volume_range(snd_mixer_elem_t*, c_long*, c_long*);

	int snd_mixer_selem_set_playback_volume_all(snd_mixer_elem_t*, c_long);

	void snd_mixer_elem_set_callback(snd_mixer_elem_t*, snd_mixer_elem_callback_t);
	int snd_mixer_poll_descriptors(snd_mixer_t*, pollfd*, uint space);

	int snd_mixer_handle_events(snd_mixer_t*);

	// FIXME: the first int should be an enum for channel identifier
	int snd_mixer_selem_get_playback_switch(snd_mixer_elem_t*, int, int* value);
	int snd_mixer_selem_set_playback_switch_all(snd_mixer_elem_t*, int);
}

version(WinMM) {
extern(Windows):
@nogc nothrow:
	pragma(lib, "winmm");
	import core.sys.windows.windows;

/*
	Windows functions include:
	http://msdn.microsoft.com/en-us/library/ms713762%28VS.85%29.aspx
	http://msdn.microsoft.com/en-us/library/ms713504%28v=vs.85%29.aspx
	http://msdn.microsoft.com/en-us/library/windows/desktop/dd798480%28v=vs.85%29.aspx#
	http://msdn.microsoft.com/en-US/subscriptions/ms712109.aspx
*/

	// pcm

	// midi

	alias HMIDIOUT = HANDLE;
	alias MMRESULT = UINT;

	MMRESULT midiOutOpen(HMIDIOUT*, UINT, DWORD, DWORD, DWORD);
	MMRESULT midiOutClose(HMIDIOUT);
	MMRESULT midiOutReset(HMIDIOUT);
	MMRESULT midiOutShortMsg(HMIDIOUT, DWORD);

	alias HWAVEOUT = HANDLE;

	struct WAVEFORMATEX {
		WORD wFormatTag;
		WORD nChannels;
		DWORD nSamplesPerSec;
		DWORD nAvgBytesPerSec;
		WORD nBlockAlign;
		WORD wBitsPerSample;
		WORD cbSize;
	}

	struct WAVEHDR {
		void* lpData;
		DWORD dwBufferLength;
		DWORD dwBytesRecorded;
		DWORD dwUser;
		DWORD dwFlags;
		DWORD dwLoops;
		WAVEHDR *lpNext;
		DWORD reserved;
	}

	enum UINT WAVE_MAPPER= -1;

	MMRESULT waveOutOpen(HWAVEOUT*, UINT_PTR, WAVEFORMATEX*, void* callback, void*, DWORD);
	MMRESULT waveOutClose(HWAVEOUT);
	MMRESULT waveOutPrepareHeader(HWAVEOUT, WAVEHDR*, UINT);
	MMRESULT waveOutUnprepareHeader(HWAVEOUT, WAVEHDR*, UINT);
	MMRESULT waveOutWrite(HWAVEOUT, WAVEHDR*, UINT);

	MMRESULT waveOutGetVolume(HWAVEOUT, PDWORD);
	MMRESULT waveOutSetVolume(HWAVEOUT, DWORD);

	enum CALLBACK_TYPEMASK = 0x70000;
	enum CALLBACK_NULL     = 0;
	enum CALLBACK_WINDOW   = 0x10000;
	enum CALLBACK_TASK     = 0x20000;
	enum CALLBACK_FUNCTION = 0x30000;
	enum CALLBACK_THREAD   = CALLBACK_TASK;
	enum CALLBACK_EVENT    = 0x50000;

	enum WAVE_FORMAT_PCM = 1;

	enum WHDR_PREPARED = 2;
	enum WHDR_BEGINLOOP = 4;
	enum WHDR_ENDLOOP = 8;
	enum WHDR_INQUEUE = 16;

	enum WinMMMessage : UINT {
		MM_JOY1MOVE            = 0x3A0,
		MM_JOY2MOVE,
		MM_JOY1ZMOVE,
		MM_JOY2ZMOVE,       // = 0x3A3
		MM_JOY1BUTTONDOWN      = 0x3B5,
		MM_JOY2BUTTONDOWN,
		MM_JOY1BUTTONUP,
		MM_JOY2BUTTONUP,
		MM_MCINOTIFY,       // = 0x3B9
		MM_WOM_OPEN            = 0x3BB,
		MM_WOM_CLOSE,
		MM_WOM_DONE,
		MM_WIM_OPEN,
		MM_WIM_CLOSE,
		MM_WIM_DATA,
		MM_MIM_OPEN,
		MM_MIM_CLOSE,
		MM_MIM_DATA,
		MM_MIM_LONGDATA,
		MM_MIM_ERROR,
		MM_MIM_LONGERROR,
		MM_MOM_OPEN,
		MM_MOM_CLOSE,
		MM_MOM_DONE,        // = 0x3C9
		MM_DRVM_OPEN           = 0x3D0,
		MM_DRVM_CLOSE,
		MM_DRVM_DATA,
		MM_DRVM_ERROR,
		MM_STREAM_OPEN,
		MM_STREAM_CLOSE,
		MM_STREAM_DONE,
		MM_STREAM_ERROR,    // = 0x3D7
		MM_MOM_POSITIONCB      = 0x3CA,
		MM_MCISIGNAL,
		MM_MIM_MOREDATA,    // = 0x3CC
		MM_MIXM_LINE_CHANGE    = 0x3D0,
		MM_MIXM_CONTROL_CHANGE = 0x3D1
	}


	enum WOM_OPEN  = WinMMMessage.MM_WOM_OPEN;
	enum WOM_CLOSE = WinMMMessage.MM_WOM_CLOSE;
	enum WOM_DONE  = WinMMMessage.MM_WOM_DONE;
	enum WIM_OPEN  = WinMMMessage.MM_WIM_OPEN;
	enum WIM_CLOSE = WinMMMessage.MM_WIM_CLOSE;
	enum WIM_DATA  = WinMMMessage.MM_WIM_DATA;


	uint mciSendStringA(in char*,char*,uint,void*);
}
