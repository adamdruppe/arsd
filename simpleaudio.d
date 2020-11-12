/**
	The purpose of this module is to provide audio functions for
	things like playback, capture, and volume on both Windows
	(via the mmsystem calls) and Linux (through ALSA).

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

	TODO:
		* pre-resampler that loads a clip and prepares it for repeated fast use
		* controls so you can tell a particular thing to keep looping until you tell it to stop, or stop after the next loop, etc (think a phaser sound as long as you hold the button down)
		* playFile function that detects automatically. basically:
			        if(args[1].endsWith("ogg"))
					a.playOgg(args[1]);
				else if(args[1].endsWith("wav"))
					a.playWav(args[1]);
				else if(mp3)
					a.playMp3(args[1]);


		* play audio high level with options to wait until completion or return immediately
		* midi mid-level stuff but see [arsd.midi]!

		* some kind of encoder???????

	I will probably NOT do OSS anymore, since my computer doesn't even work with it now.
	Ditto for Macintosh, as I don't have one and don't really care about them.

	License:
		GPL3 unless you compile with `-version=without_resampler` and do *not* use
		the mp3 functions, in which case it is BSL-1.0.
*/
module arsd.simpleaudio;

version(without_resampler) {

} else {
	version(X86)
		version=with_resampler;
	version(X86_64)
		version=with_resampler;
}

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

		History:
			Parameter `default` added on Nov 8, 2020.
	+/
	this(bool enable, int SampleRate = 44100, int channels = 2, string device = "default") {
		if(enable) {
			impl = new AudioPcmOutThreadImplementation(SampleRate, channels, device);
			impl.refcount++;
			impl.start();
			impl.waitForInitialization();
		}
	}

	/// ditto
	this(bool enable, string device, int SampleRate = 44100, int channels = 2) {
		this(enable, SampleRate, channels, device);
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

	void playOgg()(string filename, bool loop = false) {
		if(impl)
		impl.playOgg(filename, loop);
	}
	void playMp3()(string filename) {
		if(impl)
		impl.playMp3(filename);
	}
	void playWav()(string filename) {
		if(impl)
		impl.playWav(filename);
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
	private this(int SampleRate, int channels, string device = "default") {
		this.isDaemon = true;

		this.SampleRate = SampleRate;
		this.channels = channels;
		this.device = device;

		super(&run);
	}

	private int SampleRate;
	private int channels;
	private int refcount;
	private string device;

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

	/++
		Requires vorbis.d to be compiled in (module arsd.vorbis)

		History:
			Automatic resampling support added Nov 7, 2020.
	+/
	void playOgg()(string filename, bool loop = false) {
		import arsd.vorbis;

		auto v = new VorbisDecoder(filename);

		/+
			If you want 2 channels:
				if the file has 2+, use them.
				If the file has 1, duplicate it for the two outputs.
			If you want 1 channel:
				if the file has 1, use it
				if the file has 2, average them.
		+/

		if(v.sampleRate == SampleRate && v.chans == channels) {
			plain_fallback:
			addChannel(
				delegate bool(short[] buffer) {
					if(cast(int) buffer.length != buffer.length)
						throw new Exception("eeeek");

					plain:
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
			return;
		} else {
			version(with_resampler) {
				auto resampleContext = new class ResamplingContext {
					this() {
						super(v.sampleRate, SampleRate, v.chans, channels);
					}

					override void loadMoreSamples() {
						float*[2] tmp;
						tmp[0] = buffersIn[0].ptr;
						tmp[1] = buffersIn[1].ptr;

						auto actuallyGot = v.getSamplesFloat(v.chans, tmp.ptr, cast(int) buffersIn[0].length);

						resamplerDataLeft.dataIn = buffersIn[0][0 .. actuallyGot];
						if(v.chans > 1)
							resamplerDataRight.dataIn = buffersIn[1][0 .. actuallyGot];
					}
				};

				addChannel(&resampleContext.fillBuffer);
			} else goto plain_fallback;
		}
	}

	/++
		Requires mp3.d to be compiled in (module arsd.mp3) which is LGPL licensed.

		History:
			Automatic resampling support added Nov 7, 2020.
	+/
	void playMp3()(string filename) {
		import arsd.mp3;

		import std.stdio;
		auto fi = new File(filename); // just let the GC close it... otherwise random segfaults happen... blargh
		scope auto reader = delegate(void[] buf) {
			return cast(int) fi.rawRead(buf[]).length;
		};

		auto mp3 = new MP3Decoder(reader);
		if(!mp3.valid)
			throw new Exception("no file");

		if(mp3.sampleRate == SampleRate && mp3.channels == channels) {
			plain_fallback:

			auto next = mp3.frameSamples;

			addChannel(
				delegate bool(short[] buffer) {
					if(cast(int) buffer.length != buffer.length)
						throw new Exception("eeeek");

					more:
					if(next.length >= buffer.length) {
						buffer[] = next[0 .. buffer.length];
						next = next[buffer.length .. $];
					} else {
						buffer[0 .. next.length] = next[];
						buffer = buffer[next.length .. $];

						next = next[$..$];

						if(buffer.length) {
							if(mp3.valid) {
								mp3.decodeNextFrame(reader);
								next = mp3.frameSamples;
								goto more;
							} else {
								buffer[] = 0;
								return false;
							}
						}
					}

					return true;
				}
			);
		} else {
			version(with_resampler) {
				auto next = mp3.frameSamples;

				auto resampleContext = new class ResamplingContext {
					this() {
						super(mp3.sampleRate, SampleRate, mp3.channels, channels);
					}

					override void loadMoreSamples() {
						if(mp3.channels == 1) {
							int actuallyGot;

							foreach(ref b; buffersIn[0]) {
								if(next.length == 0) break;
								b = cast(float) next[0] / short.max;
								next = next[1 .. $];
								if(next.length == 0) {
									mp3.decodeNextFrame(reader);
									next = mp3.frameSamples;
								}
								actuallyGot++;
							}
							resamplerDataLeft.dataIn = buffersIn[0][0 .. actuallyGot];
						} else {
							int actuallyGot;

							foreach(idx, ref b; buffersIn[0]) {
								if(next.length == 0) break;
								b = cast(float) next[0] / short.max;
								next = next[1 .. $];
								if(next.length == 0) {
									mp3.decodeNextFrame(reader);
									next = mp3.frameSamples;
								}
								buffersIn[1][idx] = cast(float) next[0] / short.max;
								next = next[1 .. $];
								if(next.length == 0) {
									mp3.decodeNextFrame(reader);
									next = mp3.frameSamples;
								}
								actuallyGot++;
							}
							resamplerDataLeft.dataIn = buffersIn[0][0 .. actuallyGot];
							resamplerDataRight.dataIn = buffersIn[1][0 .. actuallyGot];
						}
					}
				};

				addChannel(&resampleContext.fillBuffer);

			} else goto plain_fallback;
		}
	}

	/++
		Requires [arsd.wav]. Only supports simple 8 or 16 bit wav files, no extensible or float formats at this time.

		Also requires the resampler to be compiled in at this time, but that may change in the future, I was just lazy.

		History:
			Added Nov 8, 2020.
	+/
	void playWav()(string filename) {
		version(with_resampler) {
			auto resampleContext = new class ResamplingContext {
				import arsd.wav;

				this() {
					reader = wavReader(filename);

					super(reader.sampleRate, SampleRate, reader.numberOfChannels, channels);
				}

				WavReader!CFileChunks reader;
				const(ubyte)[] next;

				override void loadMoreSamples() {

					bool moar() {
						if(next.length == 0) {
							if(reader.empty)
								return false;
							reader.popFront;
							next = reader.front;
							if(next.length == 0)
								return false;
						}
						return true;
					}

					if(reader.numberOfChannels == 1) {
						int actuallyGot;

						foreach(ref b; buffersIn[0]) {
							if(!moar) break;
							if(reader.bitsPerSample == 8) {
								b = (cast(float) next[0] - 128.0f) / 127.0f;
								next = next[1 .. $];
							} else if(reader.bitsPerSample == 16) {
								short n = next[0];
								next = next[1 .. $];
								if(!moar) break;
								n |= cast(ushort)(next[0]) << 8;
								next = next[1 .. $];

								b = (cast(float) n) / short.max;
							} else assert(0);

							actuallyGot++;
						}
						resamplerDataLeft.dataIn = buffersIn[0][0 .. actuallyGot];
					} else {
						int actuallyGot;

						foreach(idx, ref b; buffersIn[0]) {
							if(!moar) break;
							if(reader.bitsPerSample == 8) {
								b = (cast(float) next[0] - 128.0f) / 127.0f;
								next = next[1 .. $];

								if(!moar) break;
								buffersIn[1][idx] = (cast(float) next[0] - 128.0f) / 127.0f;
								next = next[1 .. $];
							} else if(reader.bitsPerSample == 16) {
								short n = next[0];
								next = next[1 .. $];
								if(!moar) break;
								n |= cast(ushort)(next[0]) << 8;
								next = next[1 .. $];

								b = (cast(float) n) / short.max;

								if(!moar) break;
								n = next[0];
								next = next[1 .. $];
								if(!moar) break;
								n |= cast(ushort)(next[0]) << 8;
								next = next[1 .. $];

								buffersIn[1][idx] = (cast(float) n) / short.max;
							} else assert(0);


							actuallyGot++;
						}
						resamplerDataLeft.dataIn = buffersIn[0][0 .. actuallyGot];
						resamplerDataRight.dataIn = buffersIn[1][0 .. actuallyGot];
					}
				}
			};

			addChannel(&resampleContext.fillBuffer);

		} else static assert(0, "I was lazy and didn't implement straight-through playing");
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

		short[] tone;
		tone.length = 22050 * len / 1000;

		short valmax = cast(short) (cast(int) volume * short.max / 100);
		int wavelength = 22050 / freq;
		wavelength /= 2;
		int da = valmax / wavelength;
		int val = 0;

		for(int a = 0; a < tone.length; a++){
			tone[a] = cast(short) val;
			val+= da;
			if(da > 0 && val >= valmax)
				da *= -1;
			if(da < 0 && val <= -valmax)
				da *= -1;
		}

		data ~= tone;


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
		short[] tone;
		tone.length = 22050 * len / 1000;

		int valmax = volume * short.max / 100;
		int wavelength = 22050 / freq;
		int da = valmax / wavelength;
		short val = 0;

		for(int a = 0; a < tone.length; a++){
			tone[a] = val;
			val+= da;
			if(val >= valmax)
				val = 0;
		}

		data ~= tone;
						case 4: // sine wave
		short[] tone;
		tone.length = 22050 * len / 1000;

		int valmax = volume * short.max / 100;
		int val = 0;

		float i = 2*PI / (22050/freq);

		float f = 0;
		for(int a = 0; a < tone.length; a++){
			tone[a] = cast(short) (valmax * sin(f));
			f += i;
			if(f>= 2*PI)
				f -= 2*PI;
		}

		data ~= tone;

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

version(ALSA) {
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

	int channels;
	int SampleRate;

	/// Always pass card == 0.
	this(int card, int SampleRate = 44100, int channels = 2) {
		assert(card == 0);
		this("default", SampleRate, channels);
	}

	/++
		`device` is a device name. On Linux, it is the ALSA string.
		On Windows, it is currently ignored, so you should pass "default"
		or null so when it does get implemented your code won't break.

		History:
			Added Nov 8, 2020.
	+/
	this(string device, int SampleRate = 44100, int channels = 2) {
		assert(channels == 1 || channels == 2);

		this.channels = channels;
		this.SampleRate = SampleRate;

		version(ALSA) {
			handle = openAlsaPcm(snd_pcm_stream_t.SND_PCM_STREAM_CAPTURE, SampleRate, channels, device);
		} else version(WinMM) {
			event = CreateEvent(null, false /* manual reset */, false /* initially triggered */, null);

			WAVEFORMATEX format;
			format.wFormatTag = WAVE_FORMAT_PCM;
			format.nChannels = 2;
			format.nSamplesPerSec = SampleRate;
			format.nAvgBytesPerSec = SampleRate * channels * 2; // two channels, two bytes per sample
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

		read = snd_pcm_readi(handle, buffer.ptr, buffer.length / channels /* div number of channels apparently */);
		if(read < 0)
			throw new AlsaException("pcm read", cast(int)read);

		return buffer[0 .. read * channels];
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

///
enum SampleRateFull = 44100;

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

	private int SampleRate;
	private int channels;

	/++
		`device` is a device name. On Linux, it is the ALSA string.
		On Windows, it is currently ignored, so you should pass "default"
		or null so when it does get implemented your code won't break.

		History:
			Added Nov 8, 2020.
	+/
	this(string device, int SampleRate = 44100, int channels = 2) {
		assert(channels == 1 || channels == 2);

		this.SampleRate = SampleRate;
		this.channels = channels;

		version(ALSA) {
			handle = openAlsaPcm(snd_pcm_stream_t.SND_PCM_STREAM_PLAYBACK, SampleRate, channels, device);
		} else version(WinMM) {
			WAVEFORMATEX format;
			format.wFormatTag = WAVE_FORMAT_PCM;
			format.nChannels = cast(ushort) channels;
			format.nSamplesPerSec = SampleRate;
			format.nAvgBytesPerSec = SampleRate * channels * 2; // two channels, two bytes per sample
			format.nBlockAlign = 4;
			format.wBitsPerSample = 16;
			format.cbSize = 0;
			if(auto err = waveOutOpen(&handle, WAVE_MAPPER, &format, cast(DWORD_PTR) &mmCallback, cast(DWORD_PTR) &this, CALLBACK_FUNCTION))
				throw new WinMMException("wave out open", err);
		} else static assert(0);
	}

	/// Always pass card == 0.
	this(int card, int SampleRate = 44100, int channels = 2) {
		assert(card == 0);

		this("default", SampleRate, channels);
	}

	/// passes a buffer of data to fill
	///
	/// Data is assumed to be interleaved stereo, LE 16 bit, 44.1 kHz (unless you change that in the ctor)
	/// Each item in the array thus alternates between left and right channel (unless you change that in the ctor)
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
				fillData(buffer[0 .. ready * channels]);
				if(playing) {
					snd_pcm_sframes_t written;
					auto data = buffer[0 .. ready * channels];

					while(data.length) {
						written = snd_pcm_writei(handle, data.ptr, data.length / channels);
						if(written < 0) {
							written = snd_pcm_recover(handle, cast(int)written, 0);
							if (written < 0) throw new AlsaException("pcm write", cast(int)written);
						}
						data = data[written * channels .. $];
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

		this("default"); // "hw:4,0"
	}

	/++
		`device` is a device name. On Linux, it is the ALSA string.
		On Windows, it is currently ignored, so you should pass "default"
		or null so when it does get implemented your code won't break.

		History:
			Added Nov 8, 2020.
	+/
	this(string device) {
		version(ALSA) {
			if(auto err = snd_rawmidi_open(&handle, null, device.toStringz, 0))
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

version(Posix) {
	import core.sys.posix.signal;
	private sigaction_t oldSigIntr;
	void setSigIntHandler() {
		sigaction_t n;
		n.sa_handler = &interruptSignalHandler;
		n.sa_mask = cast(sigset_t) 0;
		n.sa_flags = 0;
		sigaction(SIGINT, &n, &oldSigIntr);
	}
	void restoreSigIntHandler() {
		sigaction(SIGINT, &oldSigIntr, null);
	}

	__gshared bool interrupted;

	private
	extern(C)
	void interruptSignalHandler(int sigNumber) nothrow {
		interrupted = true;
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

		this("default"); // "hw:3,0"
	}

	/++
		`device` is a device name. On Linux, it is the ALSA string.
		On Windows, it is currently ignored, so you should pass "default"
		or null so when it does get implemented your code won't break.

		History:
			Added Nov 8, 2020.
	+/
	this(string device) {
		version(ALSA) {
			if(auto err = snd_rawmidi_open(null, &handle, device.toStringz, 0))
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
			static immutable ubyte[1] resetCmd = [0xff];
			writeRawMessageData(resetCmd[]);
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
		if(data.length == 0)
			return;
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

		this("default");
	}

	/++
		`device` is a device name. On Linux, it is the ALSA string.
		On Windows, it is currently ignored, so you should pass "default"
		or null so when it does get implemented your code won't break.

		History:
			Added Nov 8, 2020.
	+/
	this(string device) {
		version(ALSA) {
			if(auto err = snd_mixer_open(&handle, 0))
				throw new AlsaException("open sound", err);
			scope(failure)
				snd_mixer_close(handle);
			if(auto err = snd_mixer_attach(handle, device.toStringz))
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

private const(char)* toStringz(string s) {
	return s.ptr; // FIXME jic
}

version(ALSA)
// Opens the PCM device with default settings: stereo, 16 bit, 44.1 kHz, interleaved R/W.
snd_pcm_t* openAlsaPcm(snd_pcm_stream_t direction, int SampleRate, int channels, string cardName = "default") {
	snd_pcm_t* handle;
	snd_pcm_hw_params_t* hwParams;

	/* Open PCM and initialize hardware */

	if (auto err = snd_pcm_open(&handle, cardName.toStringz, direction, 0))
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

	if (auto err = snd_pcm_hw_params_set_channels(handle, hwParams, channels))
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
	extern(D) shared static this () { silence_alsa_messages(); }

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

version(with_resampler) {
	/* Copyright (C) 2007-2008 Jean-Marc Valin
	 * Copyright (C) 2008      Thorvald Natvig
	 * D port by Ketmar // Invisible Vector
	 *
	 * Arbitrary resampling code
	 *
	 * Redistribution and use in source and binary forms, with or without
	 * modification, are permitted provided that the following conditions are
	 * met:
	 *
	 * 1. Redistributions of source code must retain the above copyright notice,
	 * this list of conditions and the following disclaimer.
	 *
	 * 2. Redistributions in binary form must reproduce the above copyright
	 * notice, this list of conditions and the following disclaimer in the
	 * documentation and/or other materials provided with the distribution.
	 *
	 * 3. The name of the author may not be used to endorse or promote products
	 * derived from this software without specific prior written permission.
	 *
	 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
	 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
	 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	 * DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
	 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
	 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
	 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
	 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
	 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
	 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
	 * POSSIBILITY OF SUCH DAMAGE.
	 */

	/* A-a-a-and now... D port is covered by the following license!
	 *
	 * This program is free software: you can redistribute it and/or modify
	 * it under the terms of the GNU General Public License as published by
	 * the Free Software Foundation, either version 3 of the License, or
	 * (at your option) any later version.
	 *
	 * This program is distributed in the hope that it will be useful,
	 * but WITHOUT ANY WARRANTY; without even the implied warranty of
	 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	 * GNU General Public License for more details.
	 *
	 * You should have received a copy of the GNU General Public License
	 * along with this program. If not, see <http://www.gnu.org/licenses/>.
	 */
	//module iv.follin.resampler /*is aliced*/;
	//import iv.alice;

	/*
	   The design goals of this code are:
	      - Very fast algorithm
	      - SIMD-friendly algorithm
	      - Low memory requirement
	      - Good *perceptual* quality (and not best SNR)

	   Warning: This resampler is relatively new. Although I think I got rid of
	   all the major bugs and I don't expect the API to change anymore, there
	   may be something I've missed. So use with caution.

	   This algorithm is based on this original resampling algorithm:
	   Smith, Julius O. Digital Audio Resampling Home Page
	   Center for Computer Research in Music and Acoustics (CCRMA),
	   Stanford University, 2007.
	   Web published at http://www-ccrma.stanford.edu/~jos/resample/.

	   There is one main difference, though. This resampler uses cubic
	   interpolation instead of linear interpolation in the above paper. This
	   makes the table much smaller and makes it possible to compute that table
	   on a per-stream basis. In turn, being able to tweak the table for each
	   stream makes it possible to both reduce complexity on simple ratios
	   (e.g. 2/3), and get rid of the rounding operations in the inner loop.
	   The latter both reduces CPU time and makes the algorithm more SIMD-friendly.
	*/
	version = sincresample_use_full_table;
	version(X86) {
	  version(sincresample_disable_sse) {
	  } else {
	    version(D_PIC) {} else version = sincresample_use_sse;
	  }
	}


	// ////////////////////////////////////////////////////////////////////////// //
	public struct SpeexResampler {
	public:
	  alias Quality = int;
	  enum : uint {
	    Fastest = 0,
	    Voip = 3,
	    Default = 4,
	    Desktop = 5,
	    Music = 8,
	    Best = 10,
	  }

	  enum Error {
	    OK = 0,
	    NoMemory,
	    BadState,
	    BadArgument,
	    BadData,
	  }

	private:
	nothrow @trusted @nogc:
	  alias ResamplerFn = int function (ref SpeexResampler st, uint chanIdx, const(float)* indata, uint *indataLen, float *outdata, uint *outdataLen);

	private:
	  uint inRate;
	  uint outRate;
	  uint numRate; // from
	  uint denRate; // to

	  Quality srQuality;
	  uint chanCount;
	  uint filterLen;
	  uint memAllocSize;
	  uint bufferSize;
	  int intAdvance;
	  int fracAdvance;
	  float cutoff;
	  uint oversample;
	  bool started;

	  // these are per-channel
	  int[64] lastSample;
	  uint[64] sampFracNum;
	  uint[64] magicSamples;

	  float* mem;
	  uint realMemLen; // how much memory really allocated
	  float* sincTable;
	  uint sincTableLen;
	  uint realSincTableLen; // how much memory really allocated
	  ResamplerFn resampler;

	  int inStride;
	  int outStride;

	public:
	  static string errorStr (int err) {
	    switch (err) with (Error) {
	      case OK: return "success";
	      case NoMemory: return "memory allocation failed";
	      case BadState: return "bad resampler state";
	      case BadArgument: return "invalid argument";
	      case BadData: return "bad data passed";
	      default:
	    }
	    return "unknown error";
	  }

	public:
	  @disable this (this);
	  ~this () { deinit(); }

	  @property bool inited () const pure { return (resampler !is null); }

	  void deinit () {
	    import core.stdc.stdlib : free;
	    if (mem !is null) { free(mem); mem = null; }
	    if (sincTable !is null) { free(sincTable); sincTable = null; }
	    /*
	    memAllocSize = realMemLen = 0;
	    sincTableLen = realSincTableLen = 0;
	    resampler = null;
	    started = false;
	    */
	    inRate = outRate = numRate = denRate = 0;
	    srQuality = cast(Quality)666;
	    chanCount = 0;
	    filterLen = 0;
	    memAllocSize = 0;
	    bufferSize = 0;
	    intAdvance = 0;
	    fracAdvance = 0;
	    cutoff = 0;
	    oversample = 0;
	    started = 0;

	    mem = null;
	    realMemLen = 0; // how much memory really allocated
	    sincTable = null;
	    sincTableLen = 0;
	    realSincTableLen = 0; // how much memory really allocated
	    resampler = null;

	    inStride = outStride = 0;
	  }

	  /** Create a new resampler with integer input and output rates.
	   *
	   * Params:
	   *  chans = Number of channels to be processed
	   *  inRate = Input sampling rate (integer number of Hz).
	   *  outRate = Output sampling rate (integer number of Hz).
	   *  aquality = Resampling quality between 0 and 10, where 0 has poor quality and 10 has very high quality.
	   *
	   * Returns:
	   *  0 or error code
	   */
	  Error setup (uint chans, uint ainRate, uint aoutRate, Quality aquality/*, usize line=__LINE__*/) {
	    //{ import core.stdc.stdio; printf("init: %u -> %u at %u\n", ainRate, aoutRate, cast(uint)line); }
	    import core.stdc.stdlib : malloc, free;

	    deinit();
	    if (aquality < 0) aquality = 0;
	    if (aquality > SpeexResampler.Best) aquality = SpeexResampler.Best;
	    if (chans < 1 || chans > 16) return Error.BadArgument;

	    started = false;
	    inRate = 0;
	    outRate = 0;
	    numRate = 0;
	    denRate = 0;
	    srQuality = cast(Quality)666; // it's ok
	    sincTableLen = 0;
	    memAllocSize = 0;
	    filterLen = 0;
	    mem = null;
	    resampler = null;

	    cutoff = 1.0f;
	    chanCount = chans;
	    inStride = 1;
	    outStride = 1;

	    bufferSize = 160;

	    // per channel data
	    lastSample[] = 0;
	    magicSamples[] = 0;
	    sampFracNum[] = 0;

	    setQuality(aquality);
	    setRate(ainRate, aoutRate);

	    if (auto filterErr = updateFilter()) { deinit(); return filterErr; }
	    skipZeros(); // make sure that the first samples to go out of the resamplers don't have leading zeros

	    return Error.OK;
	  }

	  /** Set (change) the input/output sampling rates (integer value).
	   *
	   * Params:
	   *  ainRate = Input sampling rate (integer number of Hz).
	   *  aoutRate = Output sampling rate (integer number of Hz).
	   *
	   * Returns:
	   *  0 or error code
	   */
	  Error setRate (uint ainRate, uint aoutRate/*, usize line=__LINE__*/) {
	    //{ import core.stdc.stdio; printf("changing rate: %u -> %u at %u\n", ainRate, aoutRate, cast(uint)line); }
	    if (inRate == ainRate && outRate == aoutRate) return Error.OK;
	    //{ import core.stdc.stdio; printf("changing rate: %u -> %u at %u\n", ratioNum, ratioDen, cast(uint)line); }

	    uint oldDen = denRate;
	    inRate = ainRate;
	    outRate = aoutRate;
	    auto div = gcd(ainRate, aoutRate);
	    numRate = ainRate/div;
	    denRate = aoutRate/div;

	    if (oldDen > 0) {
	      foreach (ref v; sampFracNum.ptr[0..chanCount]) {
		v = v*denRate/oldDen;
		// safety net
		if (v >= denRate) v = denRate-1;
	      }
	    }

	    return (inited ? updateFilter() : Error.OK);
	  }

	  /** Get the current input/output sampling rates (integer value).
	   *
	   * Params:
	   *  ainRate = Input sampling rate (integer number of Hz) copied.
	   *  aoutRate = Output sampling rate (integer number of Hz) copied.
	   */
	  void getRate (out uint ainRate, out uint aoutRate) {
	    ainRate = inRate;
	    aoutRate = outRate;
	  }

	  @property uint getInRate () { return inRate; }
	  @property uint getOutRate () { return outRate; }

	  @property uint getChans () { return chanCount; }

	  /** Get the current resampling ratio. This will be reduced to the least common denominator.
	   *
	   * Params:
	   *  ratioNum = Numerator of the sampling rate ratio copied
	   *  ratioDen = Denominator of the sampling rate ratio copied
	   */
	  void getRatio (out uint ratioNum, out uint ratioDen) {
	    ratioNum = numRate;
	    ratioDen = denRate;
	  }

	  /** Set (change) the conversion quality.
	   *
	   * Params:
	   *  quality = Resampling quality between 0 and 10, where 0 has poor quality and 10 has very high quality.
	   *
	   * Returns:
	   *  0 or error code
	   */
	  Error setQuality (Quality aquality) {
	    if (aquality < 0) aquality = 0;
	    if (aquality > SpeexResampler.Best) aquality = SpeexResampler.Best;
	    if (srQuality == aquality) return Error.OK;
	    srQuality = aquality;
	    return (inited ? updateFilter() : Error.OK);
	  }

	  /** Get the conversion quality.
	   *
	   * Returns:
	   *  Resampling quality between 0 and 10, where 0 has poor quality and 10 has very high quality.
	   */
	  int getQuality () { return srQuality; }

	  /** Get the latency introduced by the resampler measured in input samples.
	   *
	   * Returns:
	   *  Input latency;
	   */
	  int inputLatency () { return filterLen/2; }

	  /** Get the latency introduced by the resampler measured in output samples.
	   *
	   * Returns:
	   *  Output latency.
	   */
	  int outputLatency () { return ((filterLen/2)*denRate+(numRate>>1))/numRate; }

	  /* Make sure that the first samples to go out of the resamplers don't have
	   * leading zeros. This is only useful before starting to use a newly created
	   * resampler. It is recommended to use that when resampling an audio file, as
	   * it will generate a file with the same length. For real-time processing,
	   * it is probably easier not to use this call (so that the output duration
	   * is the same for the first frame).
	   *
	   * Setup/reset sequence will automatically call this, so it is private.
	   */
	  private void skipZeros () { foreach (immutable i; 0..chanCount) lastSample.ptr[i] = filterLen/2; }

	  static struct Data {
	    const(float)[] dataIn;
	    float[] dataOut;
	    uint inputSamplesUsed; // out value, in samples (i.e. multiplied by channel count)
	    uint outputSamplesUsed; // out value, in samples (i.e. multiplied by channel count)
	  }

	  /** Resample (an interleaved) float array. The input and output buffers must *not* overlap.
	   * `data.dataIn` can be empty, but `data.dataOut` can't.
	   * Function will return number of consumed samples (*not* *frames*!) in `data.inputSamplesUsed`,
	   * and number of produced samples in `data.outputSamplesUsed`.
	   * You should provide enough samples for all channels, and all channels will be processed.
	   *
	   * Params:
	   *  data = input and output buffers, number of frames consumed and produced
	   *
	   * Returns:
	   *  0 or error code
	   */
	  Error process(string mode="interleaved") (ref Data data) {
	    static assert(mode == "interleaved" || mode == "sequential");

	    data.inputSamplesUsed = data.outputSamplesUsed = 0;
	    if (!inited) return Error.BadState;

	    if (data.dataIn.length%chanCount || data.dataOut.length < 1 || data.dataOut.length%chanCount) return Error.BadData;
	    if (data.dataIn.length > uint.max/4 || data.dataOut.length > uint.max/4) return Error.BadData;

	    static if (mode == "interleaved") {
	      inStride = outStride = chanCount;
	    } else {
	      inStride = outStride = 1;
	    }
	    uint iofs = 0, oofs = 0;
	    immutable uint idclen = cast(uint)(data.dataIn.length/chanCount);
	    immutable uint odclen = cast(uint)(data.dataOut.length/chanCount);
	    foreach (immutable i; 0..chanCount) {
	      data.inputSamplesUsed = idclen;
	      data.outputSamplesUsed = odclen;
	      if (data.dataIn.length) {
		processOneChannel(i, data.dataIn.ptr+iofs, &data.inputSamplesUsed, data.dataOut.ptr+oofs, &data.outputSamplesUsed);
	      } else {
		processOneChannel(i, null, &data.inputSamplesUsed, data.dataOut.ptr+oofs, &data.outputSamplesUsed);
	      }
	      static if (mode == "interleaved") {
		++iofs;
		++oofs;
	      } else {
		iofs += idclen;
		oofs += odclen;
	      }
	    }
	    data.inputSamplesUsed *= chanCount;
	    data.outputSamplesUsed *= chanCount;
	    return Error.OK;
	  }


	  //HACK for libswresample
	  // return -1 or number of outframes
	  int swrconvert (float** outbuf, int outframes, const(float)**inbuf, int inframes) {
	    if (!inited || outframes < 1 || inframes < 0) return -1;
	    inStride = outStride = 1;
	    Data data;
	    foreach (immutable i; 0..chanCount) {
	      data.dataIn = (inframes ? inbuf[i][0..inframes] : null);
	      data.dataOut = (outframes ? outbuf[i][0..outframes] : null);
	      data.inputSamplesUsed = inframes;
	      data.outputSamplesUsed = outframes;
	      if (inframes > 0) {
		processOneChannel(i, data.dataIn.ptr, &data.inputSamplesUsed, data.dataOut.ptr, &data.outputSamplesUsed);
	      } else {
		processOneChannel(i, null, &data.inputSamplesUsed, data.dataOut.ptr, &data.outputSamplesUsed);
	      }
	    }
	    return data.outputSamplesUsed;
	  }

	  /// Reset a resampler so a new (unrelated) stream can be processed.
	  void reset () {
	    lastSample[] = 0;
	    magicSamples[] = 0;
	    sampFracNum[] = 0;
	    //foreach (immutable i; 0..chanCount*(filterLen-1)) mem[i] = 0;
	    if (mem !is null) mem[0..chanCount*(filterLen-1)] = 0;
	    skipZeros(); // make sure that the first samples to go out of the resamplers don't have leading zeros
	  }

	private:
	  Error processOneChannel (uint chanIdx, const(float)* indata, uint* indataLen, float* outdata, uint* outdataLen) {
	    uint ilen = *indataLen;
	    uint olen = *outdataLen;
	    float* x = mem+chanIdx*memAllocSize;
	    immutable int filterOfs = filterLen-1;
	    immutable uint xlen = memAllocSize-filterOfs;
	    immutable int istride = inStride;
	    if (magicSamples.ptr[chanIdx]) olen -= magic(chanIdx, &outdata, olen);
	    if (!magicSamples.ptr[chanIdx]) {
	      while (ilen && olen) {
		uint ichunk = (ilen > xlen ? xlen : ilen);
		uint ochunk = olen;
		if (indata !is null) {
		  //foreach (immutable j; 0..ichunk) x[j+filterOfs] = indata[j*istride];
		  if (istride == 1) {
		    x[filterOfs..filterOfs+ichunk] = indata[0..ichunk];
		  } else {
		    auto sp = indata;
		    auto dp = x+filterOfs;
		    foreach (immutable j; 0..ichunk) { *dp++ = *sp; sp += istride; }
		  }
		} else {
		  //foreach (immutable j; 0..ichunk) x[j+filterOfs] = 0;
		  x[filterOfs..filterOfs+ichunk] = 0;
		}
		processNative(chanIdx, &ichunk, outdata, &ochunk);
		ilen -= ichunk;
		olen -= ochunk;
		outdata += ochunk*outStride;
		if (indata !is null) indata += ichunk*istride;
	      }
	    }
	    *indataLen -= ilen;
	    *outdataLen -= olen;
	    return Error.OK;
	  }

	  Error processNative (uint chanIdx, uint* indataLen, float* outdata, uint* outdataLen) {
	    immutable N = filterLen;
	    int outSample = 0;
	    float* x = mem+chanIdx*memAllocSize;
	    uint ilen;
	    started = true;
	    // call the right resampler through the function ptr
	    outSample = resampler(this, chanIdx, x, indataLen, outdata, outdataLen);
	    if (lastSample.ptr[chanIdx] < cast(int)*indataLen) *indataLen = lastSample.ptr[chanIdx];
	    *outdataLen = outSample;
	    lastSample.ptr[chanIdx] -= *indataLen;
	    ilen = *indataLen;
	    foreach (immutable j; 0..N-1) x[j] = x[j+ilen];
	    return Error.OK;
	  }

	  int magic (uint chanIdx, float **outdata, uint outdataLen) {
	    uint tempInLen = magicSamples.ptr[chanIdx];
	    float* x = mem+chanIdx*memAllocSize;
	    processNative(chanIdx, &tempInLen, *outdata, &outdataLen);
	    magicSamples.ptr[chanIdx] -= tempInLen;
	    // if we couldn't process all "magic" input samples, save the rest for next time
	    if (magicSamples.ptr[chanIdx]) {
	      immutable N = filterLen;
	      foreach (immutable i; 0..magicSamples.ptr[chanIdx]) x[N-1+i] = x[N-1+i+tempInLen];
	    }
	    *outdata += outdataLen*outStride;
	    return outdataLen;
	  }

	  Error updateFilter () {
	    uint oldFilterLen = filterLen;
	    uint oldAllocSize = memAllocSize;
	    bool useDirect;
	    uint minSincTableLen;
	    uint minAllocSize;

	    intAdvance = numRate/denRate;
	    fracAdvance = numRate%denRate;
	    oversample = qualityMap.ptr[srQuality].oversample;
	    filterLen = qualityMap.ptr[srQuality].baseLength;

	    if (numRate > denRate) {
	      // down-sampling
	      cutoff = qualityMap.ptr[srQuality].downsampleBandwidth*denRate/numRate;
	      // FIXME: divide the numerator and denominator by a certain amount if they're too large
	      filterLen = filterLen*numRate/denRate;
	      // round up to make sure we have a multiple of 8 for SSE
	      filterLen = ((filterLen-1)&(~0x7))+8;
	      if (2*denRate < numRate) oversample >>= 1;
	      if (4*denRate < numRate) oversample >>= 1;
	      if (8*denRate < numRate) oversample >>= 1;
	      if (16*denRate < numRate) oversample >>= 1;
	      if (oversample < 1) oversample = 1;
	    } else {
	      // up-sampling
	      cutoff = qualityMap.ptr[srQuality].upsampleBandwidth;
	    }

	    // choose the resampling type that requires the least amount of memory
	    version(sincresample_use_full_table) {
	      useDirect = true;
	      if (int.max/float.sizeof/denRate < filterLen) goto fail;
	    } else {
	      useDirect = (filterLen*denRate <= filterLen*oversample+8 && int.max/float.sizeof/denRate >= filterLen);
	    }

	    if (useDirect) {
	      minSincTableLen = filterLen*denRate;
	    } else {
	      if ((int.max/float.sizeof-8)/oversample < filterLen) goto fail;
	      minSincTableLen = filterLen*oversample+8;
	    }

	    if (sincTableLen < minSincTableLen) {
	      import core.stdc.stdlib : realloc;
	      auto nslen = cast(uint)(minSincTableLen*float.sizeof);
	      if (nslen > realSincTableLen) {
		if (nslen < 512*1024) nslen = 512*1024; // inc to 3 mb?
		auto x = cast(float*)realloc(sincTable, nslen);
		if (!x) goto fail;
		sincTable = x;
		realSincTableLen = nslen;
	      }
	      sincTableLen = minSincTableLen;
	    }

	    if (useDirect) {
	      foreach (int i; 0..denRate) {
		foreach (int j; 0..filterLen) {
		  sincTable[i*filterLen+j] = sinc(cutoff, ((j-cast(int)filterLen/2+1)-(cast(float)i)/denRate), filterLen, qualityMap.ptr[srQuality].windowFunc);
		}
	      }
	      if (srQuality > 8) {
		resampler = &resamplerBasicDirect!double;
	      } else {
		resampler = &resamplerBasicDirect!float;
	      }
	    } else {
	      foreach (immutable int i; -4..cast(int)(oversample*filterLen+4)) {
		sincTable[i+4] = sinc(cutoff, (i/cast(float)oversample-filterLen/2), filterLen, qualityMap.ptr[srQuality].windowFunc);
	      }
	      if (srQuality > 8) {
		resampler = &resamplerBasicInterpolate!double;
	      } else {
		resampler = &resamplerBasicInterpolate!float;
	      }
	    }

	    /* Here's the place where we update the filter memory to take into account
	       the change in filter length. It's probably the messiest part of the code
	       due to handling of lots of corner cases. */

	    // adding bufferSize to filterLen won't overflow here because filterLen could be multiplied by float.sizeof above
	    minAllocSize = filterLen-1+bufferSize;
	    if (minAllocSize > memAllocSize) {
	      import core.stdc.stdlib : realloc;
	      if (int.max/float.sizeof/chanCount < minAllocSize) goto fail;
	      auto nslen = cast(uint)(chanCount*minAllocSize*mem[0].sizeof);
	      if (nslen > realMemLen) {
		if (nslen < 16384) nslen = 16384;
		auto x = cast(float*)realloc(mem, nslen);
		if (x is null) goto fail;
		mem = x;
		realMemLen = nslen;
	      }
	      memAllocSize = minAllocSize;
	    }
	    if (!started) {
	      //foreach (i=0;i<chanCount*memAllocSize;i++) mem[i] = 0;
	      mem[0..chanCount*memAllocSize] = 0;
	    } else if (filterLen > oldFilterLen) {
	      // increase the filter length
	      foreach_reverse (uint i; 0..chanCount) {
		uint j;
		uint olen = oldFilterLen;
		{
		  // try and remove the magic samples as if nothing had happened
		  //FIXME: this is wrong but for now we need it to avoid going over the array bounds
		  olen = oldFilterLen+2*magicSamples.ptr[i];
		  for (j = oldFilterLen-1+magicSamples.ptr[i]; j--; ) mem[i*memAllocSize+j+magicSamples.ptr[i]] = mem[i*oldAllocSize+j];
		  //for (j = 0; j < magicSamples.ptr[i]; ++j) mem[i*memAllocSize+j] = 0;
		  mem[i*memAllocSize..i*memAllocSize+magicSamples.ptr[i]] = 0;
		  magicSamples.ptr[i] = 0;
		}
		if (filterLen > olen) {
		  // if the new filter length is still bigger than the "augmented" length
		  // copy data going backward
		  for (j = 0; j < olen-1; ++j) mem[i*memAllocSize+(filterLen-2-j)] = mem[i*memAllocSize+(olen-2-j)];
		  // then put zeros for lack of anything better
		  for (; j < filterLen-1; ++j) mem[i*memAllocSize+(filterLen-2-j)] = 0;
		  // adjust lastSample
		  lastSample.ptr[i] += (filterLen-olen)/2;
		} else {
		  // put back some of the magic!
		  magicSamples.ptr[i] = (olen-filterLen)/2;
		  for (j = 0; j < filterLen-1+magicSamples.ptr[i]; ++j) mem[i*memAllocSize+j] = mem[i*memAllocSize+j+magicSamples.ptr[i]];
		}
	      }
	    } else if (filterLen < oldFilterLen) {
	      // reduce filter length, this a bit tricky
	      // we need to store some of the memory as "magic" samples so they can be used directly as input the next time(s)
	      foreach (immutable i; 0..chanCount) {
		uint j;
		uint oldMagic = magicSamples.ptr[i];
		magicSamples.ptr[i] = (oldFilterLen-filterLen)/2;
		// we must copy some of the memory that's no longer used
		// copy data going backward
		for (j = 0; j < filterLen-1+magicSamples.ptr[i]+oldMagic; ++j) {
		  mem[i*memAllocSize+j] = mem[i*memAllocSize+j+magicSamples.ptr[i]];
		}
		magicSamples.ptr[i] += oldMagic;
	      }
	    }
	    return Error.OK;

	  fail:
	    resampler = null;
	    /* mem may still contain consumed input samples for the filter.
	       Restore filterLen so that filterLen-1 still points to the position after
	       the last of these samples. */
	    filterLen = oldFilterLen;
	    return Error.NoMemory;
	  }
	}


	// ////////////////////////////////////////////////////////////////////////// //
	static immutable double[68] kaiser12Table = [
	  0.99859849, 1.00000000, 0.99859849, 0.99440475, 0.98745105, 0.97779076,
	  0.96549770, 0.95066529, 0.93340547, 0.91384741, 0.89213598, 0.86843014,
	  0.84290116, 0.81573067, 0.78710866, 0.75723148, 0.72629970, 0.69451601,
	  0.66208321, 0.62920216, 0.59606986, 0.56287762, 0.52980938, 0.49704014,
	  0.46473455, 0.43304576, 0.40211431, 0.37206735, 0.34301800, 0.31506490,
	  0.28829195, 0.26276832, 0.23854851, 0.21567274, 0.19416736, 0.17404546,
	  0.15530766, 0.13794294, 0.12192957, 0.10723616, 0.09382272, 0.08164178,
	  0.07063950, 0.06075685, 0.05193064, 0.04409466, 0.03718069, 0.03111947,
	  0.02584161, 0.02127838, 0.01736250, 0.01402878, 0.01121463, 0.00886058,
	  0.00691064, 0.00531256, 0.00401805, 0.00298291, 0.00216702, 0.00153438,
	  0.00105297, 0.00069463, 0.00043489, 0.00025272, 0.00013031, 0.0000527734,
	  0.00001000, 0.00000000];

	static immutable double[36] kaiser10Table = [
	  0.99537781, 1.00000000, 0.99537781, 0.98162644, 0.95908712, 0.92831446,
	  0.89005583, 0.84522401, 0.79486424, 0.74011713, 0.68217934, 0.62226347,
	  0.56155915, 0.50119680, 0.44221549, 0.38553619, 0.33194107, 0.28205962,
	  0.23636152, 0.19515633, 0.15859932, 0.12670280, 0.09935205, 0.07632451,
	  0.05731132, 0.04193980, 0.02979584, 0.02044510, 0.01345224, 0.00839739,
	  0.00488951, 0.00257636, 0.00115101, 0.00035515, 0.00000000, 0.00000000];

	static immutable double[36] kaiser8Table = [
	  0.99635258, 1.00000000, 0.99635258, 0.98548012, 0.96759014, 0.94302200,
	  0.91223751, 0.87580811, 0.83439927, 0.78875245, 0.73966538, 0.68797126,
	  0.63451750, 0.58014482, 0.52566725, 0.47185369, 0.41941150, 0.36897272,
	  0.32108304, 0.27619388, 0.23465776, 0.19672670, 0.16255380, 0.13219758,
	  0.10562887, 0.08273982, 0.06335451, 0.04724088, 0.03412321, 0.02369490,
	  0.01563093, 0.00959968, 0.00527363, 0.00233883, 0.00050000, 0.00000000];

	static immutable double[36] kaiser6Table = [
	  0.99733006, 1.00000000, 0.99733006, 0.98935595, 0.97618418, 0.95799003,
	  0.93501423, 0.90755855, 0.87598009, 0.84068475, 0.80211977, 0.76076565,
	  0.71712752, 0.67172623, 0.62508937, 0.57774224, 0.53019925, 0.48295561,
	  0.43647969, 0.39120616, 0.34752997, 0.30580127, 0.26632152, 0.22934058,
	  0.19505503, 0.16360756, 0.13508755, 0.10953262, 0.08693120, 0.06722600,
	  0.05031820, 0.03607231, 0.02432151, 0.01487334, 0.00752000, 0.00000000];

	struct FuncDef {
	  immutable(double)* table;
	  int oversample;
	}

	static immutable FuncDef Kaiser12 = FuncDef(kaiser12Table.ptr, 64);
	static immutable FuncDef Kaiser10 = FuncDef(kaiser10Table.ptr, 32);
	static immutable FuncDef Kaiser8 = FuncDef(kaiser8Table.ptr, 32);
	static immutable FuncDef Kaiser6 = FuncDef(kaiser6Table.ptr, 32);


	struct QualityMapping {
	  int baseLength;
	  int oversample;
	  float downsampleBandwidth;
	  float upsampleBandwidth;
	  immutable FuncDef* windowFunc;
	}


	/* This table maps conversion quality to internal parameters. There are two
	   reasons that explain why the up-sampling bandwidth is larger than the
	   down-sampling bandwidth:
	   1) When up-sampling, we can assume that the spectrum is already attenuated
	      close to the Nyquist rate (from an A/D or a previous resampling filter)
	   2) Any aliasing that occurs very close to the Nyquist rate will be masked
	      by the sinusoids/noise just below the Nyquist rate (guaranteed only for
	      up-sampling).
	*/
	static immutable QualityMapping[11] qualityMap = [
	  QualityMapping(  8,  4, 0.830f, 0.860f, &Kaiser6 ), /* Q0 */
	  QualityMapping( 16,  4, 0.850f, 0.880f, &Kaiser6 ), /* Q1 */
	  QualityMapping( 32,  4, 0.882f, 0.910f, &Kaiser6 ), /* Q2 */  /* 82.3% cutoff ( ~60 dB stop) 6  */
	  QualityMapping( 48,  8, 0.895f, 0.917f, &Kaiser8 ), /* Q3 */  /* 84.9% cutoff ( ~80 dB stop) 8  */
	  QualityMapping( 64,  8, 0.921f, 0.940f, &Kaiser8 ), /* Q4 */  /* 88.7% cutoff ( ~80 dB stop) 8  */
	  QualityMapping( 80, 16, 0.922f, 0.940f, &Kaiser10), /* Q5 */  /* 89.1% cutoff (~100 dB stop) 10 */
	  QualityMapping( 96, 16, 0.940f, 0.945f, &Kaiser10), /* Q6 */  /* 91.5% cutoff (~100 dB stop) 10 */
	  QualityMapping(128, 16, 0.950f, 0.950f, &Kaiser10), /* Q7 */  /* 93.1% cutoff (~100 dB stop) 10 */
	  QualityMapping(160, 16, 0.960f, 0.960f, &Kaiser10), /* Q8 */  /* 94.5% cutoff (~100 dB stop) 10 */
	  QualityMapping(192, 32, 0.968f, 0.968f, &Kaiser12), /* Q9 */  /* 95.5% cutoff (~100 dB stop) 10 */
	  QualityMapping(256, 32, 0.975f, 0.975f, &Kaiser12), /* Q10 */ /* 96.6% cutoff (~100 dB stop) 10 */
	];


	nothrow @trusted @nogc:
	/*8, 24, 40, 56, 80, 104, 128, 160, 200, 256, 320*/
	double computeFunc (float x, immutable FuncDef* func) {
	  version(Posix) import core.stdc.math : lrintf;
	  import std.math : floor;
	  //double[4] interp;
	  float y = x*func.oversample;
	  version(Posix) {
	    int ind = cast(int)lrintf(floor(y));
	  } else {
	    int ind = cast(int)(floor(y));
	  }
	  float frac = (y-ind);
	  immutable f2 = frac*frac;
	  immutable f3 = f2*frac;
	  double interp3 = -0.1666666667*frac+0.1666666667*(f3);
	  double interp2 = frac+0.5*(f2)-0.5*(f3);
	  //double interp2 = 1.0f-0.5f*frac-f2+0.5f*f3;
	  double interp0 = -0.3333333333*frac+0.5*(f2)-0.1666666667*(f3);
	  // just to make sure we don't have rounding problems
	  double interp1 = 1.0f-interp3-interp2-interp0;
	  //sum = frac*accum[1]+(1-frac)*accum[2];
	  return interp0*func.table[ind]+interp1*func.table[ind+1]+interp2*func.table[ind+2]+interp3*func.table[ind+3];
	}


	// the slow way of computing a sinc for the table; should improve that some day
	float sinc (float cutoff, float x, int N, immutable FuncDef *windowFunc) {
	  version(LittleEndian) {
	    align(1) union temp_float { align(1): float f; uint n; }
	  } else {
	    static T fabs(T) (T n) pure { static if (__VERSION__ > 2067) pragma(inline, true); return (n < 0 ? -n : n); }
	  }
	  import std.math : sin, PI;
	  version(LittleEndian) {
	    temp_float txx = void;
	    txx.f = x;
	    txx.n &= 0x7fff_ffff; // abs
	    if (txx.f < 1.0e-6f) return cutoff;
	    if (txx.f > 0.5f*N) return 0;
	  } else {
	    if (fabs(x) < 1.0e-6f) return cutoff;
	    if (fabs(x) > 0.5f*N) return 0;
	  }
	  //FIXME: can it really be any slower than this?
	  immutable float xx = x*cutoff;
	  immutable pixx = PI*xx;
	  version(LittleEndian) {
	    return cutoff*sin(pixx)/pixx*computeFunc(2.0*txx.f/N, windowFunc);
	  } else {
	    return cutoff*sin(pixx)/pixx*computeFunc(fabs(2.0*x/N), windowFunc);
	  }
	}


	void cubicCoef (in float frac, float* interp) {
	  immutable f2 = frac*frac;
	  immutable f3 = f2*frac;
	  // compute interpolation coefficients; i'm not sure whether this corresponds to cubic interpolation but I know it's MMSE-optimal on a sinc
	  interp[0] =  -0.16667f*frac+0.16667f*f3;
	  interp[1] = frac+0.5f*f2-0.5f*f3;
	  //interp[2] = 1.0f-0.5f*frac-f2+0.5f*f3;
	  interp[3] = -0.33333f*frac+0.5f*f2-0.16667f*f3;
	  // just to make sure we don't have rounding problems
	  interp[2] = 1.0-interp[0]-interp[1]-interp[3];
	}


	// ////////////////////////////////////////////////////////////////////////// //
	int resamplerBasicDirect(T) (ref SpeexResampler st, uint chanIdx, const(float)* indata, uint* indataLen, float* outdata, uint* outdataLen)
	if (is(T == float) || is(T == double))
	{
	  auto N = st.filterLen;
	  static if (is(T == double)) assert(N%4 == 0);
	  int outSample = 0;
	  int lastSample = st.lastSample.ptr[chanIdx];
	  uint sampFracNum = st.sampFracNum.ptr[chanIdx];
	  const(float)* sincTable = st.sincTable;
	  immutable outStride = st.outStride;
	  immutable intAdvance = st.intAdvance;
	  immutable fracAdvance = st.fracAdvance;
	  immutable denRate = st.denRate;
	  T sum = void;
	  while (!(lastSample >= cast(int)(*indataLen) || outSample >= cast(int)(*outdataLen))) {
	    const(float)* sinct = &sincTable[sampFracNum*N];
	    const(float)* iptr = &indata[lastSample];
	    static if (is(T == float)) {
	      // at least 2x speedup with SSE here (but for unrolled loop)
	      if (N%4 == 0) {
		version(sincresample_use_sse) {
		  //align(64) __gshared float[4] zero = 0;
		  align(64) __gshared float[4+128] zeroesBuf = 0; // dmd cannot into such aligns, alas
		  __gshared uint zeroesptr = 0;
		  if (zeroesptr == 0) {
		    zeroesptr = cast(uint)zeroesBuf.ptr;
		    if (zeroesptr&0x3f) zeroesptr = (zeroesptr|0x3f)+1;
		  }
		  //assert((zeroesptr&0x3f) == 0, "wtf?!");
		  asm nothrow @safe @nogc {
		    mov       ECX,[N];
		    shr       ECX,2;
		    mov       EAX,[zeroesptr];
		    movaps    XMM0,[EAX];
		    mov       EAX,[sinct];
		    mov       EBX,[iptr];
		    mov       EDX,16;
		    align 8;
		   rbdseeloop:
		    movups    XMM1,[EAX];
		    movups    XMM2,[EBX];
		    mulps     XMM1,XMM2;
		    addps     XMM0,XMM1;
		    add       EAX,EDX;
		    add       EBX,EDX;
		    dec       ECX;
		    jnz       rbdseeloop;
		    // store result in sum
		    movhlps   XMM1,XMM0; // now low part of XMM1 contains high part of XMM0
		    addps     XMM0,XMM1; // low part of XMM0 is ok
		    movaps    XMM1,XMM0;
		    shufps    XMM1,XMM0,0b_01_01_01_01; // 2nd float of XMM0 goes to the 1st float of XMM1
		    addss     XMM0,XMM1;
		    movss     [sum],XMM0;
		  }
		  /*
		  float sum1 = 0;
		  foreach (immutable j; 0..N) sum1 += sinct[j]*iptr[j];
		  import std.math;
		  if (fabs(sum-sum1) > 0.000001f) {
		    import core.stdc.stdio;
		    printf("sum=%f; sum1=%f\n", sum, sum1);
		    assert(0);
		  }
		  */
		} else {
		  // no SSE; for my i3 unrolled loop is almost of the speed of SSE code
		  T[4] accum = 0;
		  foreach (immutable j; 0..N/4) {
		    accum.ptr[0] += *sinct++ * *iptr++;
		    accum.ptr[1] += *sinct++ * *iptr++;
		    accum.ptr[2] += *sinct++ * *iptr++;
		    accum.ptr[3] += *sinct++ * *iptr++;
		  }
		  sum = accum.ptr[0]+accum.ptr[1]+accum.ptr[2]+accum.ptr[3];
		}
	      } else {
		sum = 0;
		foreach (immutable j; 0..N) sum += *sinct++ * *iptr++;
	      }
	      outdata[outStride*outSample++] = sum;
	    } else {
	      if (N%4 == 0) {
		//TODO: write SSE code here!
		// for my i3 unrolled loop is ~2 times faster
		T[4] accum = 0;
		foreach (immutable j; 0..N/4) {
		  accum.ptr[0] += cast(double)*sinct++ * cast(double)*iptr++;
		  accum.ptr[1] += cast(double)*sinct++ * cast(double)*iptr++;
		  accum.ptr[2] += cast(double)*sinct++ * cast(double)*iptr++;
		  accum.ptr[3] += cast(double)*sinct++ * cast(double)*iptr++;
		}
		sum = accum.ptr[0]+accum.ptr[1]+accum.ptr[2]+accum.ptr[3];
	      } else {
		sum = 0;
		foreach (immutable j; 0..N) sum += cast(double)*sinct++ * cast(double)*iptr++;
	      }
	      outdata[outStride*outSample++] = cast(float)sum;
	    }
	    lastSample += intAdvance;
	    sampFracNum += fracAdvance;
	    if (sampFracNum >= denRate) {
	      sampFracNum -= denRate;
	      ++lastSample;
	    }
	  }
	  st.lastSample.ptr[chanIdx] = lastSample;
	  st.sampFracNum.ptr[chanIdx] = sampFracNum;
	  return outSample;
	}


	int resamplerBasicInterpolate(T) (ref SpeexResampler st, uint chanIdx, const(float)* indata, uint *indataLen, float *outdata, uint *outdataLen)
	if (is(T == float) || is(T == double))
	{
	  immutable N = st.filterLen;
	  assert(N%4 == 0);
	  int outSample = 0;
	  int lastSample = st.lastSample.ptr[chanIdx];
	  uint sampFracNum = st.sampFracNum.ptr[chanIdx];
	  immutable outStride = st.outStride;
	  immutable intAdvance = st.intAdvance;
	  immutable fracAdvance = st.fracAdvance;
	  immutable denRate = st.denRate;
	  float sum;

	  float[4] interp = void;
	  T[4] accum = void;
	  while (!(lastSample >= cast(int)(*indataLen) || outSample >= cast(int)(*outdataLen))) {
	    const(float)* iptr = &indata[lastSample];
	    const int offset = sampFracNum*st.oversample/st.denRate;
	    const float frac = (cast(float)((sampFracNum*st.oversample)%st.denRate))/st.denRate;
	    accum[] = 0;
	    //TODO: optimize!
	    foreach (immutable j; 0..N) {
	      immutable T currIn = iptr[j];
	      accum.ptr[0] += currIn*(st.sincTable[4+(j+1)*st.oversample-offset-2]);
	      accum.ptr[1] += currIn*(st.sincTable[4+(j+1)*st.oversample-offset-1]);
	      accum.ptr[2] += currIn*(st.sincTable[4+(j+1)*st.oversample-offset]);
	      accum.ptr[3] += currIn*(st.sincTable[4+(j+1)*st.oversample-offset+1]);
	    }

	    cubicCoef(frac, interp.ptr);
	    sum = (interp.ptr[0]*accum.ptr[0])+(interp.ptr[1]*accum.ptr[1])+(interp.ptr[2]*accum.ptr[2])+(interp.ptr[3]*accum.ptr[3]);

	    outdata[outStride*outSample++] = sum;
	    lastSample += intAdvance;
	    sampFracNum += fracAdvance;
	    if (sampFracNum >= denRate) {
	      sampFracNum -= denRate;
	      ++lastSample;
	    }
	  }

	  st.lastSample.ptr[chanIdx] = lastSample;
	  st.sampFracNum.ptr[chanIdx] = sampFracNum;
	  return outSample;
	}


	// ////////////////////////////////////////////////////////////////////////// //
	uint gcd (uint a, uint b) pure {
	  if (a == 0) return b;
	  if (b == 0) return a;
	  for (;;) {
	    if (a > b) {
	      a %= b;
	      if (a == 0) return b;
	      if (a == 1) return 1;
	    } else {
	      b %= a;
	      if (b == 0) return a;
	      if (b == 1) return 1;
	    }
	  }
	}


	// ////////////////////////////////////////////////////////////////////////// //
	// very simple and cheap cubic upsampler
	struct CubicUpsampler {
	public:
	nothrow @trusted @nogc:
	  float[2] curposfrac; // current position offset [0..1)
	  float step; // how long we should move on one step?
	  float[4][2] data; // -1..3
	  uint[2] drain;

	  void reset () {
	    curposfrac[] = 0.0f;
	    foreach (ref d; data) d[] = 0.0f;
	    drain[] = 0;
	  }

	  bool setup (float astep) {
	    if (astep >= 1.0f) return false;
	    step = astep;
	    return true;
	  }

	  /*
	  static struct Data {
	    const(float)[] dataIn;
	    float[] dataOut;
	    uint inputSamplesUsed; // out value, in samples (i.e. multiplied by channel count)
	    uint outputSamplesUsed; // out value, in samples (i.e. multiplied by channel count)
	  }
	  */

	  SpeexResampler.Error process (ref SpeexResampler.Data d) {
	    d.inputSamplesUsed = d.outputSamplesUsed = 0;
	    if (d.dataOut.length < 2) return SpeexResampler.Error.OK;
	    foreach (uint cidx; 0..2) {
	      uint inleft = cast(uint)d.dataIn.length/2;
	      uint outleft = cast(uint)d.dataOut.length/2;
	      processChannel(inleft, outleft, (d.dataIn.length ? d.dataIn.ptr+cidx : null), (d.dataOut.length ? d.dataOut.ptr+cidx : null), cidx);
	      d.outputSamplesUsed += cast(uint)(d.dataOut.length/2)-outleft;
	      d.inputSamplesUsed += cast(uint)(d.dataIn.length/2)-inleft;
	    }
	    return SpeexResampler.Error.OK;
	  }

	  private void processChannel (ref uint inleft, ref uint outleft, const(float)* dataIn, float* dataOut, uint cidx) {
	    if (outleft == 0) return;
	    if (inleft == 0 && drain.ptr[cidx] <= 1) return;
	    auto dt = data.ptr[cidx].ptr;
	    auto drn = drain.ptr+cidx;
	    auto cpf = curposfrac.ptr+cidx;
	    immutable float st = step;
	    for (;;) {
	      // fill buffer
	      while ((*drn) < 4) {
		if (inleft == 0) return;
		dt[(*drn)++] = *dataIn;
		dataIn += 2;
		--inleft;
	      }
	      if (outleft == 0) return;
	      --outleft;
	      // cubic interpolation
	      /*version(none)*/ {
		// interpolate between y1 and y2
		immutable float mu = (*cpf); // how far we are moved from y1 to y2
		immutable float mu2 = mu*mu; // wow
		immutable float y0 = dt[0], y1 = dt[1], y2 = dt[2], y3 = dt[3];
		version(complex_cubic) {
		  immutable float z0 = 0.5*y3;
		  immutable float z1 = 0.5*y0;
		  immutable float a0 = 1.5*y1-z1-1.5*y2+z0;
		  immutable float a1 = y0-2.5*y1+2*y2-z0;
		  immutable float a2 = 0.5*y2-z1;
		} else {
		  immutable float a0 = y3-y2-y0+y1;
		  immutable float a1 = y0-y1-a0;
		  immutable float a2 = y2-y0;
		}
		*dataOut = a0*mu*mu2+a1*mu2+a2*mu+y1;
	      }// else *dataOut = dt[1];
	      dataOut += 2;
	      if (((*cpf) += st) >= 1.0f) {
		(*cpf) -= 1.0f;
		dt[0] = dt[1];
		dt[1] = dt[2];
		dt[2] = dt[3];
		dt[3] = 0.0f;
		--(*drn); // will request more input bytes
	      }
	    }
	  }
	}
}

version(with_resampler)
abstract class ResamplingContext {
	int inputSampleRate;
	int outputSampleRate;

	int inputChannels;
	int outputChannels;

	SpeexResampler resamplerLeft;
	SpeexResampler resamplerRight;

	SpeexResampler.Data resamplerDataLeft;
	SpeexResampler.Data resamplerDataRight;

	float[][2] buffersIn;
	float[][2] buffersOut;

	uint rateNum;
	uint rateDem;

	float[][2] dataReady;


	this(int inputSampleRate, int outputSampleRate, int inputChannels, int outputChannels) {
		this.inputSampleRate = inputSampleRate;
		this.outputSampleRate = outputSampleRate;
		this.inputChannels = inputChannels;
		this.outputChannels = outputChannels;


		if(auto err = resamplerLeft.setup(1, inputSampleRate, outputSampleRate, 5))
			throw new Exception("ugh");
		resamplerRight.setup(1, inputSampleRate, outputSampleRate, 5);

		resamplerLeft.getRatio(rateNum, rateDem);

		int add = (rateNum % rateDem) ? 1 : 0;

		buffersIn[0] = new float[](BUFFER_SIZE_FRAMES * rateNum / rateDem + add);
		buffersOut[0] = new float[](BUFFER_SIZE_FRAMES);
		if(inputChannels > 1) {
			buffersIn[1] = new float[](BUFFER_SIZE_FRAMES * rateNum / rateDem + add);
			buffersOut[1] = new float[](BUFFER_SIZE_FRAMES);
		}
	}

	/+
		float*[2] tmp;
		tmp[0] = buffersIn[0].ptr;
		tmp[1] = buffersIn[1].ptr;

		auto actuallyGot = v.getSamplesFloat(v.chans, tmp.ptr, cast(int) buffersIn[0].length);

		resamplerDataLeft.dataIn should be a slice of buffersIn[0] that is filled up
		ditto for resamplerDataRight if the source has two channels
	+/
	abstract void loadMoreSamples();

	bool loadMore() {
		resamplerDataLeft.dataIn = buffersIn[0];
		resamplerDataLeft.dataOut = buffersOut[0];

		resamplerDataRight.dataIn = buffersIn[1];
		resamplerDataRight.dataOut = buffersOut[1];

		loadMoreSamples();

		//resamplerLeft.reset();

		if(auto err = resamplerLeft.process(resamplerDataLeft))
			throw new Exception("ugh");
		if(inputChannels > 1)
			//resamplerRight.reset();
			resamplerRight.process(resamplerDataRight);

		resamplerDataLeft.dataOut = resamplerDataLeft.dataOut[0 .. resamplerDataLeft.outputSamplesUsed];
		resamplerDataRight.dataOut = resamplerDataRight.dataOut[0 .. resamplerDataRight.outputSamplesUsed];

		if(resamplerDataLeft.dataOut.length == 0) {
			return true;
		}
		return false;
	}


	bool fillBuffer(short[] buffer) {
		if(cast(int) buffer.length != buffer.length)
			throw new Exception("eeeek");

		if(outputChannels == 1) {
			foreach(ref s; buffer) {
				if(resamplerDataLeft.dataOut.length == 0) {
					if(loadMore())
						return false;
				}

				if(inputChannels == 1) {
					s = cast(short) (resamplerDataLeft.dataOut[0] * short.max);
					resamplerDataLeft.dataOut = resamplerDataLeft.dataOut[1 .. $];
				} else {
					s = cast(short) ((resamplerDataLeft.dataOut[0] + resamplerDataRight.dataOut[0]) * short.max / 2);

					resamplerDataLeft.dataOut = resamplerDataLeft.dataOut[1 .. $];
					resamplerDataRight.dataOut = resamplerDataRight.dataOut[1 .. $];
				}
			}
		} else if(outputChannels == 2) {
			foreach(idx, ref s; buffer) {
				if(resamplerDataLeft.dataOut.length == 0) {
					if(loadMore())
						return false;
				}

				if(inputChannels == 1) {
					s = cast(short) (resamplerDataLeft.dataOut[0] * short.max);
					if(idx & 1)
						resamplerDataLeft.dataOut = resamplerDataLeft.dataOut[1 .. $];
				} else {
					if(idx & 1) {
						s = cast(short) (resamplerDataRight.dataOut[0] * short.max);
						resamplerDataRight.dataOut = resamplerDataRight.dataOut[1 .. $];
					} else {
						s = cast(short) (resamplerDataLeft.dataOut[0] * short.max);
						resamplerDataLeft.dataOut = resamplerDataLeft.dataOut[1 .. $];
					}
				}
			}
		} else assert(0);

		return true;
	}
}

private enum scriptable = "arsd_jsvar_compatible";
