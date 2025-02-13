/// Part of my old D1 game library along with [arsd.screen] and [arsd.engine]. Do not use in new projects.
module arsd.audio;

import sdl.SDL;
import sdl.SDL_mixer;

import arsd.engine;

bool audioIsLoaded; // potential hack material

class Sound {
  public:
	this(char[] filename){
		if(!audioIsLoaded)
			return;
		sfx = Mix_LoadWAV((filename ~ "\0").ptr);
		if(sfx is null)
			throw new Exception(immutableString("Sound load " ~ filename));
	}

	/*
	this(Wav wav){
		auto w = wav.toMemory;
		SDL_RWops* a = SDL_RWFromMem(w, w.length)
		if(a is null) throw new Exception("sdl rw ops");
		scope(exit) SDL_FreeRW(a);
		sfx = Mix_LoadWAV_RW(a, 0);
		if(sfx is null) throw new Exception("loadwav rw");
	}
	*/

	~this(){
		if(sfx !is null)
			Mix_FreeChunk(sfx);
	}

  private:
	Mix_Chunk* sfx;
}

class Music {
  public:
	this(char[] filename){
		if(!audioIsLoaded)
			return;
		mus = Mix_LoadMUS((filename~"\0").ptr);
		if(mus is null)
			throw new Exception(immutableString("Music load " ~ filename));
	}

	~this(){
		if(mus !is null)
			Mix_FreeMusic(mus);
	}
  private:
	Mix_Music* mus;
}

class Audio{
  public:
	this(bool act = true){
		if(audioIsLoaded)
			throw new Exception("Cannot load audio twice");

		if(!act){
			audioIsLoaded = false;
			active = false;
			return;
		}
		if(1) { // if(Mix_OpenAudio(22050, AUDIO_S16SYS, 2, 4096/2 /* the /2 is new */) != 0){
			active = false; //throw new Error;
			error = true;
			audioIsLoaded = false;
		} else {
			active = true;
			error = false;
			audioIsLoaded = true;
		}

		sfxChannel = 1;

		careAboutErrors = false;
	}

	void activate(){
		if(!audioIsLoaded) return;
		if(!error)
			active = true;
	}

	void deactivate(){
		if(!audioIsLoaded) return;
		active = false;
	}

	void toggleActivation(){
		if(!audioIsLoaded) return;
		if(error)
			return;
		active = !active;
	}

	~this(){
		if(audioIsLoaded){
			Mix_HaltMusic();
			Mix_HaltChannel(-1);
			Mix_CloseAudio();
		}
	}

	void playEffect(Sound snd, bool loop = false){
		if(!active || snd is null)
			return;

		//if(Mix_Playing(sfxChannel))
		//	return;

		sfxChannel = Mix_PlayChannel(-1, snd.sfx, loop == true ? -1 : 0);

	}
	void stopEffect(){
		if(!active)
			return;

		Mix_HaltChannel(sfxChannel);
	}

	void playMusic(Music mus, bool loop = true){
		if(!active || mus is null)
			return;

		if(Mix_PlayMusic(mus.mus, loop == true ? -1 : 0) == -1)
			throw new Exception("play music");
		//	musicIsPlaying = false;
		else
			musicIsPlaying = true;
	}

	void pauseMusic(){
		if(!active)
			return;

		if(musicIsPlaying){
			Mix_PauseMusic();
			musicIsPaused = true;
		}
	}

	void unpauseMusic(){
		if(!active)
			return;

		if(musicIsPaused){
			Mix_ResumeMusic();
			musicIsPaused = false;
		}
	}

	void stopMusic(){
		if(!active)
			return;

		Mix_HaltMusic();
	}


	void stopAll(){
		if(!active)
			return;

		Mix_HaltMusic();
		Mix_HaltChannel(-1);
	}

  private:
  	int sfxChannel;
	bool active;
	bool error;

	bool musicIsPaused;
	bool musicIsPlaying;

	bool careAboutErrors;
}

	int Mix_PlayChannel(int channel, Mix_Chunk* chunk, int loops) {
		return Mix_PlayChannelTimed(channel,chunk,loops,-1);
	}
	Mix_Chunk * Mix_LoadWAV(in char *file) {
		return Mix_LoadWAV_RW(SDL_RWFromFile(file, "rb"), 1);
	}
