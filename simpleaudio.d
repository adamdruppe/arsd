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

enum BUFFER_SIZE_FRAMES = 1024;//512;//2048;
enum BUFFER_SIZE_SHORT = BUFFER_SIZE_FRAMES * 2;

/// A reasonable default volume for an individual sample. It doesn't need to be large; in fact it needs to not be large so mixing doesn't clip too much.
enum DEFAULT_VOLUME = 20;

version(Demo)
void main() {
/+

	version(none) {
	import iv.stb.vorbis;

	int channels;
	short* decoded;
	auto v = new VorbisDecoder("test.ogg");

	auto ao = AudioOutput(0);
	ao.fillData = (short[] buffer) {
		auto got = v.getSamplesShortInterleaved(2, buffer.ptr, buffer.length);
		if(got == 0) {
			ao.stop();
		}
	};

	ao.play();
	return;
	}




	auto thread = new AudioPcmOutThread();
	thread.start();

	thread.playOgg("test.ogg");

	Thread.sleep(5.seconds);

	//Thread.sleep(150.msecs);
	thread.beep();
	Thread.sleep(250.msecs);
	thread.blip();
	Thread.sleep(250.msecs);
	thread.boop();
	Thread.sleep(1000.msecs);
	/*
	thread.beep(800, 500);
	Thread.sleep(500.msecs);
	thread.beep(366, 500);
	Thread.sleep(600.msecs);
	thread.beep(800, 500);
	thread.beep(366, 500);
	Thread.sleep(500.msecs);
	Thread.sleep(150.msecs);
	thread.beep(200);
	Thread.sleep(150.msecs);
	thread.beep(100);
	Thread.sleep(150.msecs);
	thread.noise();
	Thread.sleep(150.msecs);
	*/


	thread.stop();

	thread.join();

	return;

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
	//writeln("Should be about ", loopCount * BUFFER_SIZE_FRAMES * 1000 / SampleRate, " microseconds");

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
+/
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

/++
	Wraps [AudioPcmOutThreadImplementation] with RAII semantics for better
	error handling and disposal than the old way.

	DO NOT USE THE `new` OPERATOR ON THIS! Just construct it inline:

	---
		auto audio = AudioOutputThread(true);
		audio.beep();
	---

	History:
		Added May 9, 2020 to replace the old [AudioPcmOutThread] class
		that proved pretty difficult to use correctly.
+/
struct AudioOutputThread {
	@disable this();

	/++
		Pass `true` to enable the audio thread. Otherwise, it will
		just live as a dummy mock object that you should not actually
		try to use.
	+/
	this(bool enable) {
		if(enable) {
			impl = new AudioPcmOutThreadImplementation();
			impl.refcount++;
			impl.start();
			impl.waitForInitialization();
		}
	}

	/// Keeps an internal refcount.
	this(this) {
		if(impl)
			impl.refcount++;
	}

	/// When the internal refcount reaches zero, it stops the audio and rejoins the thread, throwing any pending exception (yes the dtor can throw! extremely unlikely though).
	~this() {
		if(impl) {
			impl.refcount--;
			if(impl.refcount == 0) {
				impl.stop();
				impl.join();
			}
		}
	}

	/++
		This allows you to check `if(audio)` to see if it is enabled.
	+/
	bool opCast(T : bool)() {
		return impl !is null;
	}

	/++
		Other methods are forwarded to the implementation of type
		[AudioPcmOutThreadImplementation]. See that for more information
		on what you can do.

		This opDispatch template will forward all other methods directly
		to that [AudioPcmOutThreadImplementation] if this is live, otherwise
		it does nothing.
	+/
	template opDispatch(string name) {
		static if(is(typeof(__traits(getMember, impl, name)) Params == __parameters))
		auto opDispatch(Params params) {
			if(impl)
				return __traits(getMember, impl, name)(params);
			static if(!is(typeof(return) == void))
				return typeof(return).init;
		}
		else static assert(0);
	}


	/// provides automatic [arsd.jsvar] script wrapping capability. Make sure the
	/// script also finishes before this goes out of scope or it may end up talking
	/// to a dead object....
	auto toArsdJsvar() {
		return impl;
	}

	/+
	alias getImpl this;
	AudioPcmOutThreadImplementation getImpl() {
		assert(impl !is null);
		return impl;
	}
	+/
	private AudioPcmOutThreadImplementation impl;
}

/++
	Old thread implementation. I decided to deprecate it in favor of [AudioOutputThread] because
	RAII semantics make it easier to get right at the usage point. See that to go forward.

	History:
		Deprecated on May 9, 2020.
+/
deprecated("Use AudioOutputThread instead.") class AudioPcmOutThread {}

import core.thread;
/++
	Makes an audio thread for you that you can make
	various sounds on and it will mix them with good
	enough latency for simple games.

	DO NOT USE THIS DIRECTLY. Instead, access it through
	[AudioOutputThread].

	---
		auto audio = AudioOutputThread(true);
		audio.beep();

		// you need to keep the main program alive long enough
		// to keep this thread going to hear anything
		Thread.sleep(1.seconds);
	---
+/
final class AudioPcmOutThreadImplementation : Thread {
	private this() {
		this.isDaemon = true;

		super(&run);
	}

	private int refcount;

	private void waitForInitialization() {
		shared(AudioOutput*)* ao = cast(shared(AudioOutput*)*) &this.ao;
		while(isRunning && *ao is null) {
			Thread.sleep(5.msecs);
		}

		if(*ao is null)
			join(); // it couldn't initialize, just rethrow the exception
	}

	///
	@scriptable
	void pause() {
		if(ao) {
			ao.pause();
		}
	}

	///
	@scriptable
	void unpause() {
		if(ao) {
			ao.unpause();
		}
	}

	///
	void stop() {
		if(ao) {
			ao.stop();
		}
	}

	/// Args in hertz and milliseconds
	@scriptable
	void beep(int freq = 900, int dur = 150, int volume = DEFAULT_VOLUME) {
		Sample s;
		s.operation = 0; // square wave
		s.frequency = SampleRate / freq;
		s.duration = dur * SampleRate / 1000;
		s.volume = volume;
		addSample(s);
	}

	///
	@scriptable
	void noise(int dur = 150, int volume = DEFAULT_VOLUME) {
		Sample s;
		s.operation = 1; // noise
		s.frequency = 0;
		s.volume = volume;
		s.duration = dur * SampleRate / 1000;
		addSample(s);
	}

	///
	@scriptable
	void boop(float attack = 8, int freqBase = 500, int dur = 150, int volume = DEFAULT_VOLUME) {
		Sample s;
		s.operation = 5; // custom
		s.volume = volume;
		s.duration = dur * SampleRate / 1000;
		s.f = delegate short(int x) {
			auto currentFrequency = cast(float) freqBase / (1 + cast(float) x / (cast(float) SampleRate / attack));
			import std.math;
			auto freq = 2 * PI /  (cast(float) SampleRate / currentFrequency);
			return cast(short) (sin(cast(float) freq * cast(float) x) * short.max * volume / 100);
		};
		addSample(s);
	}

	///
	@scriptable
	void blip(float attack = 6, int freqBase = 800, int dur = 150, int volume = DEFAULT_VOLUME) {
		Sample s;
		s.operation = 5; // custom
		s.volume = volume;
		s.duration = dur * SampleRate / 1000;
		s.f = delegate short(int x) {
			auto currentFrequency = cast(float) freqBase * (1 + cast(float) x / (cast(float) SampleRate / attack));
			import std.math;
			auto freq = 2 * PI /  (cast(float) SampleRate / currentFrequency);
			return cast(short) (sin(cast(float) freq * cast(float) x) * short.max * volume / 100);
		};
		addSample(s);
	}

	version(none)
	void custom(int dur = 150, int volume = DEFAULT_VOLUME) {
		Sample s;
		s.operation = 5; // custom
		s.volume = volume;
		s.duration = dur * SampleRate / 1000;
		s.f = delegate short(int x) {
			auto currentFrequency = 500.0 / (1 + cast(float) x / (cast(float) SampleRate / 8));
			import std.math;
			auto freq = 2 * PI /  (cast(float) SampleRate / currentFrequency);
			return cast(short) (sin(cast(float) freq * cast(float) x) * short.max * volume / 100);
		};
		addSample(s);
	}

	/// Requires vorbis.d to be compiled in (module arsd.vorbis)
	void playOgg()(string filename, bool loop = false) {
		import arsd.vorbis;

		auto v = new VorbisDecoder(filename);

		addChannel(
			delegate bool(short[] buffer) {
				if(cast(int) buffer.length != buffer.length)
					throw new Exception("eeeek");
				auto got = v.getSamplesShortInterleaved(2, buffer.ptr, cast(int) buffer.length);
				if(got == 0) {
					if(loop) {
						v.seekStart();
						return true;
					}

					return false;
				}
				return true;
			}
		);
	}


	struct Sample {
		int operation;
		int frequency; /* in samples */
		int duration; /* in samples */
		int volume; /* between 1 and 100. You should generally shoot for something lowish, like 20. */
		int delay; /* in samples */

		int x;
		short delegate(int x) f;
	}

	final void addSample(Sample currentSample) {
		int frequencyCounter;
		short val = cast(short) (cast(int) short.max * currentSample.volume / 100);
		addChannel(
			delegate bool (short[] buffer) {
				if(currentSample.duration) {
					size_t i = 0;
					if(currentSample.delay) {
						if(buffer.length <= currentSample.delay * 2) {
							// whole buffer consumed by delay
							buffer[] = 0;
							currentSample.delay -= buffer.length / 2;
						} else {
							i = currentSample.delay * 2;
							buffer[0 .. i] = 0;
							currentSample.delay = 0;
						}
					}
					if(currentSample.delay > 0)
						return true;

					size_t sampleFinish;
					if(currentSample.duration * 2 <= buffer.length) {
						sampleFinish = currentSample.duration * 2;
						currentSample.duration = 0;
					} else {
						sampleFinish = buffer.length;
						currentSample.duration -= buffer.length / 2;
					}

					switch(currentSample.operation) {
						case 0: // square wave
							for(; i < sampleFinish; i++) {
								buffer[i] = val;
								// left and right do the same thing so we only count
								// every other sample
								if(i & 1) {
									if(frequencyCounter)
										frequencyCounter--;
									if(frequencyCounter == 0) {
										// are you kidding me dmd? random casts suck
										val = cast(short) -cast(int)(val);
										frequencyCounter = currentSample.frequency / 2;
									}
								}
							}
						break;
						case 1: // noise
							for(; i < sampleFinish; i++) {
								import std.random;
								buffer[i] = uniform(cast(short) -cast(int)val, val);
							}
						break;
						/+
						case 2: // triangle wave
							for(; i < sampleFinish; i++) {
								buffer[i] = val;
								// left and right do the same thing so we only count
								// every other sample
								if(i & 1) {
									if(frequencyCounter)
										frequencyCounter--;
									if(frequencyCounter == 0) {
										val = 0;
										frequencyCounter = currentSample.frequency / 2;
									}
								}
							}

						break;
						case 3: // sawtooth wave
						case 4: // sine wave
						+/
						case 5: // custom function
							val = currentSample.f(currentSample.x);
							for(; i < sampleFinish; i++) {
								buffer[i] = val;
								if(i & 1) {
									currentSample.x++;
									val = currentSample.f(currentSample.x);
								}
							}
						break;
						default: // unknown; use silence
							currentSample.duration = 0;
					}

					if(i < buffer.length)
						buffer[i .. $] = 0;

					return currentSample.duration > 0;
				} else {
					return false;
				}
			}
		);
	}

	/++
		The delegate returns false when it is finished (true means keep going).
		It must fill the buffer with waveform data on demand and must be latency
		sensitive; as fast as possible.
	+/
	public void addChannel(bool delegate(short[] buffer) dg) {
		synchronized(this) {
			// silently drops info if we don't have room in the buffer...
			// don't do a lot of long running things lol
			if(fillDatasLength < fillDatas.length)
				fillDatas[fillDatasLength++] = dg;
		}
	}

	private {
		AudioOutput* ao;

		bool delegate(short[] buffer)[32] fillDatas;
		int fillDatasLength = 0;
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

		AudioOutput ao = AudioOutput(0);
		this.ao = &ao;
		scope(exit) this.ao = null;
		auto omg = this;
		ao.fillData = (short[] buffer) {
			short[BUFFER_SIZE_SHORT] bfr;
			bool first = true;
			if(fillDatasLength) {
				for(int idx = 0; idx < fillDatasLength; idx++) {
					auto dg = fillDatas[idx];
					auto ret = dg(bfr[0 .. buffer.length][]);
					foreach(i, v; bfr[0 .. buffer.length][]) {
						int val;
						if(first)
							val = 0;
						else
							val = buffer[i];

						int a = val;
						int b = v;
						int cap = a + b;
						if(cap > short.max) cap = short.max;
						else if(cap < short.min) cap = short.min;
						val = cast(short) cap;
						buffer[i] = cast(short) val;
					}
					if(!ret) {
						// it returned false meaning this one is finished...
						synchronized(omg) {
							fillDatas[idx] = fillDatas[fillDatasLength - 1];
							fillDatasLength--;
						}
						idx--;
					}

					first = false;
				}
			} else {
				buffer[] = 0;
			}
		};
		ao.play();
	}
}


import core.stdc.config;

version(linux) version=ALSA;
version(Windows) version=WinMM;

enum SampleRate = 44100;

version(ALSA) {
	enum cardName = "default";

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
	enum midiName = "hw:3,0";

	enum midiCaptureName = "hw:4,0";

	// fyi raw midi dump:  amidi -d --port hw:4,0
	// connect my midi out to fluidsynth: aconnect 28:0 128:0
	// and my keyboard to it: aconnect 32:0 128:0
}

/// Thrown on audio failures.
/// Subclass this to provide OS-specific exceptions
class AudioException : Exception {
	this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		super(message, file, line, next);
	}
}

/++
	Gives PCM input access (such as a microphone).

	History:
		Windows support added May 10, 2020 and the API got overhauled too.
+/
struct AudioInput {
	version(ALSA) {
		snd_pcm_t* handle;
	} else version(WinMM) {
		HWAVEIN handle;
		HANDLE event;
	} else static assert(0);

	@disable this();
	@disable this(this);

	/// Always pass card == 0.
	this(int card) {
		assert(card == 0);

		version(ALSA) {
			handle = openAlsaPcm(snd_pcm_stream_t.SND_PCM_STREAM_CAPTURE);
		} else version(WinMM) {
			event = CreateEvent(null, false /* manual reset */, false /* initially triggered */, null);

			WAVEFORMATEX format;
			format.wFormatTag = WAVE_FORMAT_PCM;
			format.nChannels = 2;
			format.nSamplesPerSec = SampleRate;
			format.nAvgBytesPerSec = SampleRate * 2 * 2; // two channels, two bytes per sample
			format.nBlockAlign = 4;
			format.wBitsPerSample = 16;
			format.cbSize = 0;
			if(auto err = waveInOpen(&handle, WAVE_MAPPER, &format, cast(DWORD_PTR) event, cast(DWORD_PTR) &this, CALLBACK_EVENT))
				throw new WinMMException("wave in open", err);

		} else static assert(0);
	}

	/// Data is delivered as interleaved stereo, LE 16 bit, 44.1 kHz
	/// Each item in the array thus alternates between left and right channel
	/// and it takes a total of 88,200 items to make one second of sound.
	///
	/// Returns the slice of the buffer actually read into
	///
	/// LINUX ONLY. You should prolly use [record] instead
	version(ALSA)
	short[] read(short[] buffer) {
		snd_pcm_sframes_t read;

		read = snd_pcm_readi(handle, buffer.ptr, buffer.length / 2 /* div number of channels apparently */);
		if(read < 0)
			throw new AlsaException("pcm read", cast(int)read);

		return buffer[0 .. read * 2];
	}

	/// passes a buffer of data to fill
	///
	/// Data is delivered as interleaved stereo, LE 16 bit, 44.1 kHz
	/// Each item in the array thus alternates between left and right channel
	/// and it takes a total of 88,200 items to make one second of sound.
	void delegate(short[]) receiveData;

	///
	void stop() {
		recording = false;
	}

	/// First, set [receiveData], then call this.
	void record() {
		assert(receiveData !is null);
		recording = true;

		version(ALSA) {
			short[BUFFER_SIZE_SHORT] buffer;
			while(recording) {
				auto got = read(buffer);
				receiveData(got);
			}
		} else version(WinMM) {

			enum numBuffers = 2; // use a lot of buffers to get smooth output with Sleep, see below
			short[BUFFER_SIZE_SHORT][numBuffers] buffers;

			WAVEHDR[numBuffers] headers;

			foreach(i, ref header; headers) {
				auto buffer = buffers[i][];
				header.lpData = cast(char*) buffer.ptr;
				header.dwBufferLength = cast(int) buffer.length * cast(int) short.sizeof;
				header.dwFlags = 0;// WHDR_BEGINLOOP | WHDR_ENDLOOP;
				header.dwLoops = 0;

				if(auto err = waveInPrepareHeader(handle, &header, header.sizeof))
					throw new WinMMException("prepare header", err);

				header.dwUser = 1; // mark that the driver is using it
				if(auto err = waveInAddBuffer(handle, &header, header.sizeof))
					throw new WinMMException("wave in read", err);
			}

			waveInStart(handle);
			scope(failure) waveInReset(handle);

			while(recording) {
				if(auto err = WaitForSingleObject(event, INFINITE))
					throw new Exception("WaitForSingleObject");
				if(!recording)
					break;

				foreach(ref header; headers) {
					if(!(header.dwFlags & WHDR_DONE)) continue;

					receiveData((cast(short*) header.lpData)[0 .. header.dwBytesRecorded / short.sizeof]);
					if(!recording) break;
					header.dwUser = 1; // mark that the driver is using it
					if(auto err = waveInAddBuffer(handle, &header, header.sizeof)) {
                                                throw new WinMMException("waveInAddBuffer", err);
                                        }
				}
			}

			/*
			if(auto err = waveInStop(handle))
				throw new WinMMException("wave in stop", err);
			*/

			if(auto err = waveInReset(handle)) {
				throw new WinMMException("wave in reset", err);
			}

			still_in_use:
			foreach(idx, header; headers)
				if(!(header.dwFlags & WHDR_DONE)) {
					Sleep(1);
					goto still_in_use;
				}

			foreach(ref header; headers)
				if(auto err = waveInUnprepareHeader(handle, &header, header.sizeof)) {
					throw new WinMMException("unprepare header", err);
				}

			ResetEvent(event);
		} else static assert(0);
	}

	private bool recording;

	~this() {
		receiveData = null;
		version(ALSA) {
			snd_pcm_close(handle);
		} else version(WinMM) {
			if(auto err = waveInClose(handle))
				throw new WinMMException("close", err);

			CloseHandle(event);
			// in wine (though not Windows nor winedbg as far as I can tell)
			// this randomly segfaults. the sleep prevents it. idk why.
			Sleep(5);
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
			format.nSamplesPerSec = SampleRate;
			format.nAvgBytesPerSec = SampleRate * 2 * 2; // two channels, two bytes per sample
			format.nBlockAlign = 4;
			format.wBitsPerSample = 16;
			format.cbSize = 0;
			if(auto err = waveOutOpen(&handle, WAVE_MAPPER, &format, cast(DWORD_PTR) &mmCallback, cast(DWORD_PTR) &this, CALLBACK_FUNCTION))
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
					throw new AlsaException("avail", cast(int)ready);
				if(ready > BUFFER_SIZE_FRAMES)
					ready = BUFFER_SIZE_FRAMES;
				//import std.stdio; writeln("filling ", ready);
				fillData(buffer[0 .. ready * 2]);
				if(playing) {
					snd_pcm_sframes_t written;
					auto data = buffer[0 .. ready * 2];

					while(data.length) {
						written = snd_pcm_writei(handle, data.ptr, data.length / 2);
						if(written < 0) {
							written = snd_pcm_recover(handle, cast(int)written, 0);
							if (written < 0) throw new AlsaException("pcm write", cast(int)written);
						}
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
				header.lpData = cast(char*) buffer.ptr;
				header.dwBufferLength = cast(int) buffer.length * cast(int) short.sizeof;
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

	///
	void pause() {
		version(WinMM)
			waveOutPause(handle);
		else version(ALSA)
			snd_pcm_pause(handle, 1);
	}

	///
	void unpause() {
		version(WinMM)
			waveOutRestart(handle);
		else version(ALSA)
			snd_pcm_pause(handle, 0);

	}

	version(WinMM) {
		extern(Windows)
		static void mmCallback(HWAVEOUT handle, UINT msg, void* userData, WAVEHDR* header, DWORD_PTR param2) {
			AudioOutput* ao = cast(AudioOutput*) userData;
			if(msg == WOM_DONE) {
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

/++
	For reading midi events from hardware, for example, an electronic piano keyboard
	attached to the computer.
+/
struct MidiInput {
	// reading midi devices...
	version(ALSA) {
		snd_rawmidi_t* handle;
	} else version(WinMM) {
		HMIDIIN handle;
	}

	@disable this();
	@disable this(this);

	/+
B0 40 7F # pedal on
B0 40 00 # sustain pedal off
	+/

	/// Always pass card == 0.
	this(int card) {
		assert(card == 0);

		version(ALSA) {
			if(auto err = snd_rawmidi_open(&handle, null, midiCaptureName, 0))
				throw new AlsaException("rawmidi open", err);
		} else version(WinMM) {
			if(auto err = midiInOpen(&handle, 0, cast(DWORD_PTR) &mmCallback, cast(DWORD_PTR) &this, CALLBACK_FUNCTION))
				throw new WinMMException("midi in open", err);
		} else static assert(0);
	}

	private bool recording = false;

	///
	void stop() {
		recording = false;
	}

	/++
		Records raw midi input data from the device.

		The timestamp is given in milliseconds since recording
		began (if you keep this program running for 23ish days
		it might overflow! so... don't do that.). The other bytes
		are the midi messages.

		$(PITFALL Do not call any other multimedia functions from the callback!)
	+/
	void record(void delegate(uint timestamp, ubyte b1, ubyte b2, ubyte b3) dg) {
		version(ALSA) {
			recording = true;
			ubyte[1024] data;
			import core.time;
			auto start = MonoTime.currTime;
			while(recording) {
				auto read = snd_rawmidi_read(handle, data.ptr, data.length);
				if(read < 0)
					throw new AlsaException("midi read", cast(int) read);

				auto got = data[0 .. read];
				while(got.length) {
					// FIXME some messages are fewer bytes....
					dg(cast(uint) (MonoTime.currTime - start).total!"msecs", got[0], got[1], got[2]);
					got = got[3 .. $];
				}
			}
		} else version(WinMM) {
			recording = true;
			this.dg = dg;
			scope(exit)
				this.dg = null;
			midiInStart(handle);
			scope(exit)
				midiInReset(handle);

			while(recording) {
				Sleep(1);
			}
		} else static assert(0);
	}

	version(WinMM)
	private void delegate(uint timestamp, ubyte b1, ubyte b2, ubyte b3) dg;


	version(WinMM)
	extern(Windows)
	static
	void mmCallback(HMIDIIN handle, UINT msg, DWORD_PTR user, DWORD_PTR param1, DWORD_PTR param2) {
		MidiInput* mi = cast(MidiInput*) user;
		if(msg == MIM_DATA) {
			mi.dg(
				cast(uint) param2,
				param1 & 0xff,
				(param1 >> 8) & 0xff,
				(param1 >> 16) & 0xff
			);
		}
	}

	~this() {
		version(ALSA) {
			snd_rawmidi_close(handle);
		} else version(WinMM) {
			midiInClose(handle);
		} else static assert(0);
	}
}

// plays a midi file in the background with methods to tweak song as it plays
struct MidiOutputThread {
	void injectCommand() {}
	void pause() {}
	void unpause() {}

	void trackEnabled(bool on) {}
	void channelEnabled(bool on) {}

	void loopEnabled(bool on) {}

	// stops the current song, pushing its position to the stack for later
	void pushSong() {}
	// restores a popped song from where it was.
	void popSong() {}
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

	void silenceAllNotes() {
		foreach(a; 0 .. 16)
			writeMidiMessage((0x0b << 4)|a /*MIDI_EVENT_CONTROLLER*/, 123, 0);
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
			return cast(int)(volume * 100 / (maxVolume - minVolume));
		} else static assert(0);
	}

	/// Gets the exact value returned from the operating system. The range may vary.
	int getMasterVolumeExact() {
		version(ALSA) {
			c_long volume;
			snd_mixer_selem_get_playback_volume(selem, 0, &volume);
			return cast(int)volume;
		} else static assert(0);
	}

	/// sets a percentage on the volume, so it must be 0 <= volume <= 100
	/// Note: this affects shared system state and you should not use it unless the end user wants you to.
	void setMasterVolume(int volume) {
		version(ALSA) {
			assert(volume >= 0 && volume <= 100);
			setMasterVolumeExact(cast(int)(volume * (maxVolume - minVolume) / 100));
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
		// can actually survive a failure here, we will just move forward
		{} // throw new AlsaException("params init", err);

	if (auto err = snd_pcm_hw_params_set_access(handle, hwParams, snd_pcm_access_t.SND_PCM_ACCESS_RW_INTERLEAVED))
		throw new AlsaException("params access", err);

	if (auto err = snd_pcm_hw_params_set_format(handle, hwParams, snd_pcm_format.SND_PCM_FORMAT_S16_LE))
		throw new AlsaException("params format", err);

	uint rate = SampleRate;
	int dir = 0;
	if (auto err = snd_pcm_hw_params_set_rate_near(handle, hwParams, &rate, &dir))
		throw new AlsaException("params rate", err);

	assert(rate == SampleRate); // cheap me

	if (auto err = snd_pcm_hw_params_set_channels(handle, hwParams, 2))
		throw new AlsaException("params channels", err);

	uint periods = 2;
	{
	auto err = snd_pcm_hw_params_set_periods_near(handle, hwParams, &periods, 0);
	if(err < 0)
		throw new AlsaException("periods", err);

	snd_pcm_uframes_t sz = (BUFFER_SIZE_FRAMES * periods);
	err = snd_pcm_hw_params_set_buffer_size_near(handle, hwParams, &sz);
	if(err < 0)
		throw new AlsaException("buffer size", err);
	}

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
	int snd_pcm_pause(snd_pcm_t*, int);
	int snd_pcm_prepare(snd_pcm_t*);
	int snd_pcm_hw_params(snd_pcm_t*, snd_pcm_hw_params_t*);
	int snd_pcm_hw_params_set_periods(snd_pcm_t*, snd_pcm_hw_params_t*, uint, int);
	int snd_pcm_hw_params_set_periods_near(snd_pcm_t*, snd_pcm_hw_params_t*, uint*, int);
	int snd_pcm_hw_params_set_buffer_size(snd_pcm_t*, snd_pcm_hw_params_t*, snd_pcm_uframes_t);
	int snd_pcm_hw_params_set_buffer_size_near(snd_pcm_t*, snd_pcm_hw_params_t*, snd_pcm_uframes_t*);
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

	int snd_pcm_recover (snd_pcm_t* pcm, int err, int silent);

	alias snd_lib_error_handler_t = void function (const(char)* file, int line, const(char)* function_, int err, const(char)* fmt, ...);
	int snd_lib_error_set_handler (snd_lib_error_handler_t handler);

	import core.stdc.stdarg;
	private void alsa_message_silencer (const(char)* file, int line, const(char)* function_, int err, const(char)* fmt, ...) {}
	//k8: ALSAlib loves to trash stderr; shut it up
	void silence_alsa_messages () { snd_lib_error_set_handler(&alsa_message_silencer); }
	shared static this () { silence_alsa_messages(); }

	// raw midi

	static if(is(size_t == uint))
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
/+
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

+/
}

private enum scriptable = "arsd_jsvar_compatible";
