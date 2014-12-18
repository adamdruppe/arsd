/**
	The purpose of this module is to provide audio functions for
	things like playback, capture, and volume on both Windows and
	Linux (through ALSA).

	It is only aimed at the basics, and will be filled in as I want
	a particular feature.

	For example, I'm starting this because I want to write a volume
	control program for my linux box, so that's what is going first.
	That will consist of a listening callback for volume changes and
	being able to get/set the volume.


	TODO:
		* register callbacks for volume change
		* play audio with options to wait until completion or return immediately
		* capture audio

		* Windows support

		* I'll also write midi and .wav functions at least eventually with maybe some synthesizer stuff.
*/
module arsd.simpleaudio;

import core.stdc.config;

version(linux) version=ALSA;

/// Interfaces with the default sound card. You should only have a single instance of this and it should
/// be stack allocated, so its destructor cleans up after it.
struct AudioIO {
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
		snd_mixer_t* mixerHandle;
		snd_mixer_selem_id_t* sid;
		snd_mixer_elem_t* selem;

		c_long maxVolume, minVolume;

		enum cardName = "default";
		enum selemName = "Master";
	}

	@disable this();
	@disable this(this);

	/// Only cardId == 0 is supported
	this(int cardId) {
		assert(cardId == 0, "Pass 0 to use default sound card.");

		version(ALSA) {
			if(snd_mixer_open(&mixerHandle, 0))
				throw new Exception("open sound");
			scope(failure)
				snd_mixer_close(mixerHandle);
			if(snd_mixer_attach(mixerHandle, cardName))
				throw new Exception("attach to sound card");
			if(snd_mixer_selem_register(mixerHandle, null, null))
				throw new Exception("register mixer");
			if(snd_mixer_load(mixerHandle))
				throw new Exception("load mixer");

			if(snd_mixer_selem_id_malloc(&sid))
				throw new Exception("master channel open");
			scope(failure)
				snd_mixer_selem_id_free(sid);
			snd_mixer_selem_id_set_index(sid, 0);
			snd_mixer_selem_id_set_name(sid, selemName);
			selem = snd_mixer_find_selem(mixerHandle, sid);
			if(selem is null)
				throw new Exception("find master element");

			if(snd_mixer_selem_get_playback_volume_range(selem, &minVolume, &maxVolume))
				throw new Exception("get volume range");
		} else static assert(0);
	}

	~this() {
		version(ALSA) {
			snd_mixer_selem_id_free(sid);
			snd_mixer_close(mixerHandle);
		} else static assert(0);
	}

	/// Gets the master channel's mute state
	@property bool muteMaster() {
		version(ALSA) {
			int result;
			if(snd_mixer_selem_get_playback_switch(selem, 0, &result))
				throw new Exception("get mute state");
			return result == 0;
		} else static assert(0);
	}

	/// Mutes or unmutes the master channel
	@property void muteMaster(bool mute) {
		version(ALSA) {
			if(snd_mixer_selem_set_playback_switch_all(selem, mute ? 0 : 1))
				throw new Exception("set mute state");
		} else static assert(0);
	}

	/// returns a percentage, between 0 and 100 (inclusive)
	int getMasterVolume() {
		version(ALSA) {
			c_long volume;
			snd_mixer_selem_get_playback_volume(selem, 0, &volume);
			return volume * 100 / (maxVolume - minVolume);
		} else static assert(0);
	}

	/// sets a percentage on the volume, so it must be 0 <= volume <= 100
	void setMasterVolume(int volume) {
		version(ALSA) {
			assert(volume >= 0 && volume <= 100);
			snd_mixer_selem_set_playback_volume_all(selem,
				volume * (maxVolume - minVolume) / 100); 
		} else static assert(0);
	}
}

// version(Test)
void main() {
	auto aio = AudioIO(0);

	import std.stdio;
	writeln(aio.muteMaster);
}

// Bindings follow

version(ALSA) {
extern(C):
@nogc nothrow:
	pragma(lib, "asound");

	struct snd_mixer_t {}
	struct snd_mixer_elem_t {}
	struct snd_mixer_selem_id_t {}

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


	// FIXME: the first int should be an enum for channel identifier
	int snd_mixer_selem_get_playback_switch(snd_mixer_elem_t*, int, int* value);
	int snd_mixer_selem_set_playback_switch_all(snd_mixer_elem_t*, int);
}
