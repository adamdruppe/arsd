// This code is D 1.0

/***
	The base class from which a game engine should inherit.

	Version: 1.0
	License: GNU General Public License
*/
module arsd.engine; //@-L-lSDL -L-lSDL_mixer -L-lSDL_ttf -L-lSDL_image -L-lGL -L-lSDL_net

// FIXME: the difference between directions and buttons should be removed


import sdl.SDL;
import sdl.SDL_net;

import std.string;
version(D_Version2) {
	import random = core.stdc.stdlib;
	alias random.srand srand;

	import std.conv;
	char[] convToString(T)(T t) { return to!(char[])(t); }
	string immutableString(in char[] a) { return a.idup; }
} else {
	import random = std.random;
	void srand(uint a) {
		random.rand_seed(a, 0);
	}
	alias std.string.toString convToString;

	char[] immutableString(in char[] a) { return a; }
}
import std.math;
public import arsd.screen;
public import arsd.audio;

public import sdl.SDL_keysym_;

version(D_Version2)
	import core.stdc.stdarg;
else
	import std.stdarg;

import std.stdio;
//version(linux) pragma(lib, "kbhit.o");

extern(C) bool kbhit();

int randomNumber(int min, int max){
	if(min == max)
		return min;
	max++; // make it inclusive

	uint a = random.rand();
	a %= (max - min);
	a += min;
	return a;
}


// HACK!
	bool waiting;
	uint globalTimer;
class Callable{
  public:
	  abstract void run(int timer);
	  // after is the other thing that is calling this to be paused and then unpaused
	  final void start(Callable after = null){
		After = after;
		if(After !is null)
			After.paused = true;
		paused = false;
		for(int a = 0; a < objs.length; a++)
			if(objs[a] is null){
				objs[a] = this;
				goto done;

		}
		objs.length = objs.length + 1;
		objs[objs.length - 1] = this;

		done:
		frame();
	}

	  final void queue(){
	  	int a;
		paused = true;
		for(a = 0; a < objs.length; a++)
			if(objs[a] is null){
				objs[a] = this;
				goto done;

		}
		objs.length = a + 1;
		objs[a] = this;

		done:
		if(a == 1){
			objs[0].paused = true;
			paused = false;
		} else {
			objs[a - 1].After = this;
		}
		After = objs[0];

		frame();
	}




	final void terminate(){
		for(int a = 0; a < objs.length; a++)
			if(objs[a] !is null && objs[a] == this)
				objs[a] = null;
		if(After !is null){
			After.paused = false;
			After.frame();
		}
	}

	bool paused;
  private:
	void frame(){
		if(!paused){
			if(globalTimer > lastFrame){
				lastFrame = globalTimer;
				run(Timer);
				Timer++;
			}
		}
	}
	int Timer;
	uint lastFrame;
	Callable After;
}

Callable[] objs;
// end HACK

//	enum {up = 0, down, left, right};
	enum {select = 8, start = 9, square = 3, cross = 2, circle = 1, triangle = 0,
		R1 = 7, R2 = 5, L2 = 4, L1 = 6, L3 = 10, R3 = 11, special = 12,
		up = 13, down = 14, left = 15, right = 16,  // dpad and left stick
		up2 = 17, down2 = 18, left2 = 19, right2 = 20}; // right stick
	const int NUM_BUTTONS = 21;
class Engine{
	const int NoVideo = 0;
	const int Video1024x768 = 1;
	const int Video640x480 = 2;
	const int Video800x600 = 3;
	const int Video320x200 = 4;
	const int Video512x512 = 5;

	const int VideoFullScreen = 32;


	alias int Direction;
	alias int Buttons;

	const int MAX_NET = 8;
	const int NET_PORT = 7777;

	// For being a network server.....
	bool isServer;
	struct NetClient {
		TCPsocket sock;
		int numPlayers;
		int startingPlayer;
		int latency; // in milliseconds

		int state; // Only valid if sock is non null.
				// 0: waiting on initial timestamp
				// 1: waiting on lag response
				// 2: ready for starting
	}
	NetClient[MAX_NET] clients;
	int numberOfClients;

	int maxLatency;


	// For being a network client
	TCPsocket clientsock;

	// All done.

	void beginServing(){
		TCPsocket serversock;

		socketset = SDLNet_AllocSocketSet(MAX_NET+1);
		if(socketset is null)
			throw new Exception("AllocSocketSet");
		scope(failure)
			SDLNet_FreeSocketSet(socketset);

		IPaddress serverIP;

		SDLNet_ResolveHost(&serverIP, null, NET_PORT);
		serversock = SDLNet_TCP_Open(&serverIP);
		if(serversock is null)
			throw new Exception("Server sock");
		scope(exit)
			SDLNet_TCP_Close(serversock);

		if(SDLNet_AddSocket(socketset, cast(SDLNet_GenericSocket) serversock) < 0)
			throw new Exception("addsocket");
		scope(exit)
			SDLNet_DelSocket(socketset, cast(SDLNet_GenericSocket) serversock);

		writefln("Waiting for players to join the game.\nPress enter when everyone has joined to start the game.");


		uint randomSeed = random.rand();
		srand(randomSeed);
		writefln("TEST: %d", randomNumber(0, 100));


		bool loopingNeeeded = false; // potential FIXME for later
		while(!kbhit() || loopingNeeeded){
			int n = SDLNet_CheckSockets(socketset, 10);
			if(n < 0)
				throw new Exception("Check sockets");
			if(n == 0)
				continue;
			if(SDLNet_SocketReady(serversock)){
				TCPsocket newsock;

				newsock = SDLNet_TCP_Accept(serversock);
				if(newsock is null){
					continue;
				}


				SDLNet_AddSocket(socketset, cast(SDLNet_GenericSocket) newsock);

				// accept the connection

				writefln("New player:");

				clients[numberOfClients].sock = newsock;
				numberOfClients++;
			}

			// Check the rest of our sockets for data

			for(int a = 0; a < numberOfClients; a++){
				if(SDLNet_SocketReady(clients[a].sock)){
					byte[16] data; // this needs to be EXACTLY the size we are actually going to get.
					if(SDLNet_TCP_Recv(clients[a].sock, data.ptr, 16) <= 0){
						// the connection was closed
						for(int b = a; b < numberOfClients; b++)
							clients[b] = clients[b+1];
						clients[numberOfClients] = NetClient.init;
						numberOfClients--;
						a--;
						continue;
					}

					// And handle the data here.
					switch(clients[a].state){
					  default: assert(0);
					  case 0: // this is the timestamp and stuff
						int ts = SDLNet_Read32(data.ptr);
						clients[a].numPlayers = SDLNet_Read32(data.ptr+4);

						int startingPlayer = numberOfPlayers;
						numberOfPlayers+= clients[a].numPlayers;
						clients[a].startingPlayer = startingPlayer;

						SDLNet_Write32(ts, data.ptr);
						SDLNet_Write32(SDL_GetTicks(), data.ptr+4);
						SDLNet_Write32(randomSeed, data.ptr+8);
						SDLNet_Write32(startingPlayer, data.ptr+12);

						if(SDLNet_TCP_Send(clients[a].sock, data.ptr, 16) <= 0)
							throw new Exception("TCP send");

						clients[a].state++;
					  break;
					  case 1: // this is telling of the latency

						clients[a].latency = SDLNet_Read32(data.ptr);

						if(clients[a].latency > maxLatency)
							maxLatency = clients[a].latency;

						writefln("Latency: %d", clients[a].latency);

						clients[a].state++;
					  break;
					  case 2:
					  	throw new Exception("unknown data came in");
					}
				}
			}
		}



		isServer = true;
	}

	void connectTo(in char[] whom){
		socketset = SDLNet_AllocSocketSet(1);
		if(socketset is null)
			throw new Exception("AllocSocketSet");
		scope(failure)
			SDLNet_FreeSocketSet(socketset);

		IPaddress ip;

		if(SDLNet_ResolveHost(&ip, std.string.toStringz(whom), NET_PORT) == -1)
			throw new Exception("Resolve host");

		clientsock = SDLNet_TCP_Open(&ip);

		if(clientsock is null)
			throw new Exception("open socket");

		if(SDLNet_AddSocket(socketset, cast(SDLNet_GenericSocket) clientsock) < 0)
			throw new Exception("addsocket");
		scope(failure) SDLNet_DelSocket(socketset, cast(SDLNet_GenericSocket) clientsock);

		byte[16] data;

		int timeStamp = SDL_GetTicks();
		SDLNet_Write32(timeStamp, data.ptr);
		SDLNet_Write32(numberOfLocalPlayers, data.ptr+4);
		if(SDLNet_TCP_Send(clientsock, data.ptr, 16) <= 0)
			throw new Exception("TCP send");

		if(SDLNet_TCP_Recv(clientsock, data.ptr, 16) <= 0)
			throw new Exception("TCP recv");

		int receivedTimeStamp = SDLNet_Read32(data.ptr);
		int serverTimeStamp = SDLNet_Read32(data.ptr+4);
		uint randomSeed = SDLNet_Read32(data.ptr+8);
		firstLocalPlayer = SDLNet_Read32(data.ptr+12);
		writefln("First local player = %d", firstLocalPlayer);

		srand(randomSeed);
		writefln("TEST: %d", randomNumber(0, 100));

		int ourLatency = SDL_GetTicks() - receivedTimeStamp;

		SDLNet_Write32(ourLatency, data.ptr);
		SDLNet_Write32(serverTimeStamp, data.ptr+4);

		if(SDLNet_TCP_Send(clientsock, data.ptr, 16) <= 0)
			throw new Exception("TCP send 2");

		waiting = true;
	}

	// This should be called AFTER most initialization, but BEFORE you initialize your players; you don't
	// know the number of players for sure until this call returns.
	void waitOnNetwork(){
		if(!net)
			return;

		if(isServer){

			// Calculate when to start, then send the signal to everyone.
			int desiredLag = cast(int) round(cast(float) maxLatency / msPerTick) + 2;//1;
			lag = desiredLag;
			writefln("Lag = %d", lag);

			for(int a = 0; a < numberOfClients; a++){
				int delay = maxLatency - clients[a].latency;

				byte[16] data;

				// FIXME: We need to send all player data here!

				SDLNet_Write32(desiredLag, data.ptr);
				SDLNet_Write32(delay, data.ptr + 4);
				SDLNet_Write32(numberOfPlayers, data.ptr + 8);


				if(SDLNet_TCP_Send(clients[a].sock, data.ptr, 16) < 16)
					throw new Exception("Sending failed");
			}

			SDL_Delay(maxLatency); // After waiting for the signal to reach everyone, we can now begin the game!
			return;
		} else {
			// handle the data
			byte[16] data;

			// FIXME: we need to read special per game player data here!

			if(SDLNet_TCP_Recv(clientsock, data.ptr, 16) <= 0)
				throw new Exception("Server closed the connection");

			int lagAmount   = SDLNet_Read32(data.ptr); 
			int delayAmount = SDLNet_Read32(data.ptr + 4);
			numberOfPlayers = SDLNet_Read32(data.ptr+8);


			lag = lagAmount;
			writefln("Lag = %d", lag);

			SDL_Delay(delayAmount);
			// And finally, we're done, and the game can begin.
			waiting = false;
			return;
		}
	}

	SDLNet_SocketSet socketset;

	int msPerTick;

	int numberOfPlayers;
	int numberOfLocalPlayers;
	int firstLocalPlayer;

  public:
	int getNumberOfPlayers(){ // good for main looping and controls and such
		return numberOfPlayers;
	}

	// returns < 0 if the player is not local
	int getLocalPlayerNumber(int absolutePlayerNumber){ // useful for split screening
		if(absolutePlayerNumber >= firstLocalPlayer && absolutePlayerNumber < firstLocalPlayer + numberOfLocalPlayers)
			return  absolutePlayerNumber - firstLocalPlayer;

		return -1;
	}

	int getNumberOfLocalPlayers(){ // only useful for deciding how to split the screen
		return numberOfLocalPlayers;
	}

	int getFirstLocalPlayerNumber(){
		return firstLocalPlayer;
	}


	this(int graphics = NoVideo, bool sound = false, int timerClick = 0, int numOfLocalPlayers = 1, in char[] network = null){
		bool joystick = true;

		int init = 0;

		numberOfPlayers = numberOfLocalPlayers = numOfLocalPlayers;



		if(graphics)
			init |= SDL_INIT_VIDEO;
		if(timerClick)
			init |= SDL_INIT_TIMER;
		if(sound)
			init |= SDL_INIT_AUDIO;
		if(joystick)
			init |= SDL_INIT_JOYSTICK;

		msPerTick = timerClick;

		if(SDL_Init(init) == -1 ){
			throw new Exception("SDL_Init");
		}
		scope(failure) SDL_Quit();


// SDL_WM_SetIcon(SDL_LoadBMP("icon.bmp"), NULL);


		if(network !is null){
			if(SDLNet_Init() < 0)
				throw new Exception("SDLNet_Init");
			scope(failure) SDLNet_Quit();


			if(network == "SERVER")
				beginServing();
			else
				connectTo(network);

			net = true;
		}

		switch(graphics & ~32){
			case NoVideo:
				screen = null;
			break;
			case Video1024x768:
				screen = new Screen(1024, 768, 24, true, (graphics & 32) ? true : false);
			break;
			case Video640x480:
				screen = new Screen(640, 480);
			break;
			case Video800x600:
				screen = new Screen(800, 600);
			break;
			case Video512x512:
				screen = new Screen(512, 512);
			break;
			case Video320x200:
				screen = new Screen(320, 200);
			break;
			default:
				throw new Exception("Invalid screen type");
		}
		scope(failure) delete screen;

		if(timerClick)
			SDL_AddTimer(timerClick, &tcallback, null);

		if(sound)
			audio = new Audio;
		else
			audio = new Audio(false);

		scope(failure) delete audio;

		if(joystick && SDL_NumJoysticks() > 0){
			SDL_JoystickEventState(SDL_ENABLE);
			for(int a = 0; a < SDL_NumJoysticks(); a++)
				joyStick[a] = SDL_JoystickOpen(a);
		}
		else
			joyStick[0] = null;

		scope(failure){	for(int a = 0; a < 16; a++) if(joyStick[a]) SDL_JoystickClose(joyStick[a]); }


		//SDL_ShowCursor(SDL_DISABLE); // FIXME: make this a call

//***********************************************************************
	// FIXME: it should load controller maps from a config file

		// My playstation controller
		for(int a = 0; a < 13; a++)
			mapJoystickKeyToButton(a, cast(Buttons) a, 0, firstLocalPlayer);

		leftStickXAxis[0] = 0;
		leftStickYAxis[0] = 1;
		dpadXAxis[0] = 4;
		dpadYAxis[0] = 5;
		rightStickXAxis[0] = 2;
		rightStickYAxis[0] = 3;
		leftTriggerAxis[0] = -1;
		rightTriggerAxis[0] = -1;

		// 360 controllers
		for(int b = 1; b < 16; b++){
			mapJoystickKeyToButton(1, circle, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(0, cross, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(4, square, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(3, triangle, b, firstLocalPlayer + b);

			mapJoystickKeyToButton(16, select, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(8, start, b, firstLocalPlayer + b);

			mapJoystickKeyToButton(10, L3, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(11, R3, b, firstLocalPlayer + b);

			mapJoystickKeyToButton(6, L1, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(7, R1, b, firstLocalPlayer + b);

			mapJoystickKeyToButton(9, special, b, firstLocalPlayer + b);

			mapJoystickKeyToButton(15, left, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(12, up, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(13, right, b, firstLocalPlayer + b);
			mapJoystickKeyToButton(14, down, b, firstLocalPlayer + b);

			leftStickXAxis[b] = 0;
			dpadXAxis[b] = -1;
			leftStickYAxis[b] = 1;
			dpadYAxis[b] = -1;
			rightStickXAxis[b] = 4;
			rightStickYAxis[b] = 3;
			leftTriggerAxis[b] = 2;
			rightTriggerAxis[b] = 5;
		}



		// Some sane keyboard defaults

		keyboardMap['s'] = InputMap(circle, firstLocalPlayer);
		keyboardMap['x'] = InputMap(cross, firstLocalPlayer);
		keyboardMap['w'] = InputMap(triangle, firstLocalPlayer);
		keyboardMap['a'] = InputMap(square, firstLocalPlayer);
		keyboardMap[' '] = InputMap(circle, firstLocalPlayer);
		keyboardMap['d'] = InputMap(L1, firstLocalPlayer);
		keyboardMap['f'] = InputMap(R1, firstLocalPlayer);
		keyboardMap['e'] = InputMap(L2, firstLocalPlayer);
		keyboardMap['r'] = InputMap(R2, firstLocalPlayer);
		keyboardMap['c'] = InputMap(L3, firstLocalPlayer);
		keyboardMap['v'] = InputMap(R3, firstLocalPlayer);
		keyboardMap['['] = InputMap(start, firstLocalPlayer);
		keyboardMap[']'] = InputMap(select, firstLocalPlayer);
		keyboardMap['='] = InputMap(special, firstLocalPlayer);

		keyboardMap[SDLK_UP] = InputMap(up, firstLocalPlayer);
		keyboardMap[SDLK_DOWN] = InputMap(down, firstLocalPlayer);
		keyboardMap[SDLK_LEFT] = InputMap(left, firstLocalPlayer);
		keyboardMap[SDLK_RIGHT] = InputMap(right, firstLocalPlayer);

		keyboardMap['k'] = InputMap(up, firstLocalPlayer);
		keyboardMap['j'] = InputMap(down, firstLocalPlayer);
		keyboardMap['h'] = InputMap(left, firstLocalPlayer);
		keyboardMap['l'] = InputMap(right, firstLocalPlayer);



	}

	void moveMouse(Point pos){
		SDL_WarpMouse(cast(ushort) pos.x, cast(ushort) pos.y);

	}

	bool capturedInput = false;

	void captureInput(){
		if(capturedInput)
			return;
		SDL_WM_GrabInput(1);
		capturedInput = true;
	}

	void unCaptureInput(){
		if(!capturedInput)
			return;
		SDL_WM_GrabInput(0);
		capturedInput = false;
	}

	~this(){
		unCaptureInput();
		if(net){
			SDLNet_FreeSocketSet(socketset);
			SDLNet_Quit();
		}
		for(int a = 0; a < 16; a++)
		if(joyStick[a])
			SDL_JoystickClose(joyStick[a]);
		delete audio;
		delete screen;

		foreach(a; objs)
			if(a !is null)
				delete a;
		SDL_Quit();
	}

	void run(){
		eventLoop();
	}

	void setTitle(in char[] title){
		SDL_WM_SetCaption(std.string.toStringz(title), null);
	}

	bool buttonWasPressed(Buttons button, int which = 0){
		if(!buttonsChecked[button][which] && buttonsDown[button][which]){
			buttonsChecked[button][which] = true;
			return true;
		}
		return false;
	}

	bool buttonIsDown(Buttons button, int which = 0){
		if(button < NUM_BUTTONS && button >= 0)
			return buttonsDown[button][which];
		return false;
	}
	
	bool keyWasPressed(int button){
		if(button < 400 && button >= 0)
		if(!keysChecked[button] && keysDown[button]){
			keysChecked[button] = true;
			return true;
		}
		return false;
	}

	bool keyIsDown(int button){
		if(button < 400 && button >= 0)
			return keysDown[button];
		assert(0);
	}

	int getStickX(int stick, int which = 0){
		if( stick >= 0 && stick < 2)
			return stickX[stick][which];
		else
			return 0;
	}

	int getStickY(int stick, int which = 0){
		if( stick >= 0 && stick < 2)
			return stickY[stick][which];
		else
			return 0;
	}

	int getMouseX(){
		return mouseX;
	}

	int getMouseY(){
		return mouseY;
	}

	int getMouseChangeX(){
		int a = mousedx;
		mousedx = 0;
		return a;
	}

	int getMouseChangeY(){
		int a = mousedy;
		mousedy = 0;
		return a;
	}

	bool mouseHasMoved(){
		return (getMouseChangeY != 0 || getMouseChangeX != 0);
	}

	bool mouseButtonWasPressed(int button){
		if(!mouseButtonsChecked[button] && mouseButtonsDown[button]){
			mouseButtonsChecked[button] = true;
			return true;
		}
		return false;
	}

	bool mouseButtonIsDown(int button){
		if(button < 8 && button >= 0)
			return mouseButtonsDown[button];
		return false;
	}

	Point mouseLocation(){
		return XY(mouseX, mouseY);
	}

	void quit(){
		wantToQuit = true;
	}

	bool isAltDown(){
		return (SDL_GetModState() & KMOD_ALT) ? true : false;
	}
	bool isControlDown(){
		return  (SDL_GetModState() & KMOD_CTRL) ? true : false;
	}
	bool isShiftDown(){
		return  (SDL_GetModState() & KMOD_SHIFT) ? true : false;
	}

  protected:
	const int BUTTONDOWN = 0;
	const int BUTTONUP   = 1;
	const int MOTION     = 2;

	void keyEvent(int type, int keyCode, int character, int modifiers){
		defaultKeyEvent(type, keyCode, character, modifiers);
	}

	void defaultKeyEvent(int type, int keyCode, int character, int modifiers){
		if(character == 'q' || keyCode == 'q')
			quit();
		if(type == BUTTONUP && keyCode == SDLK_F3){
			if(capturedInput)
				unCaptureInput();
			else
				captureInput();
		}
	}

	void mouseEvent(int type, int x, int y, int xrel, int yrel, int button, int flags){
		defaultMouseEvent(type, x, y, xrel, yrel, button, flags);
	}

	final void defaultMouseEvent(int type, int x, int y, int xrel, int yrel, int button, int flags){

	}

	void joystickEvent(int type, int whichStick, int button, int state){
		defaultJoystickEvent(type, whichStick, button, state);
	}

	final void defaultJoystickEvent(int type, int whichStick, int button, int state){

	}

	bool quitEvent(){
		return true;
	}

	void timerEvent(){

		// Need to add network receives and the lag timer loops
		if(net)
			getNetworkControllerData();

		// do we actually need to lag here? hmmm.....

		globalTimer++;
		foreach(a; objs){//copy){
			if(a is null)
				continue;
			a.frame();
		}

		if(lag)
			updateControllers();

	}

	public Screen screen;
	public Audio audio;

  private:

	bool net;


	SDL_Joystick*[16] joyStick;
		struct InputMap{
			int button; // or direction
			int which; // which player
		}
	InputMap[int] keyboardMap;
	InputMap[int][16] joystickMap; // joystickMap[which][button] = translated val

	int leftStickXAxis[16];
	int dpadXAxis[16];
	int leftStickYAxis[16];
	int dpadYAxis[16];
	int rightStickXAxis[16];
	int rightStickYAxis[16];
	int leftTriggerAxis[16];
	int rightTriggerAxis[16];




	bool[400] keysDown;
	bool[400] keysChecked;

	bool wantToQuit;

	bool buttonsDown[NUM_BUTTONS][16];
	bool buttonsChecked[NUM_BUTTONS][16];

	const int LAG_QUEUE_SIZE = 10;
	// This lag is used for network games. It sends you old data until the lag time is up,
	// to try and keep all the players synchronized.
	int buttonLagRemaining[NUM_BUTTONS][16][LAG_QUEUE_SIZE];

	// This way we can queue up activities happening while the lag is waiting
	int buttonLagQueueStart[NUM_BUTTONS][16];
	int buttonLagQueueEnd[NUM_BUTTONS][16];
	int buttonLagQueueLength[NUM_BUTTONS][16];

	// These store what the state was before the lag began; it is what is returned while
	// waiting on the lag to complete
	bool lagbuttonsDown[NUM_BUTTONS][16][LAG_QUEUE_SIZE];



	int stickX[3][16];
	int stickY[3][16];

	bool mouseButtonsDown[8];
	bool mouseButtonsChecked[8];
	const int LEFT = SDL_BUTTON_LEFT;//1;
	const int MIDDLE = SDL_BUTTON_MIDDLE;//2;
	const int RIGHT = SDL_BUTTON_RIGHT;//3;
	const int SCROLL_UP = 4;
	const int SCROLL_DOWN = 5;

	int mouseX;
	int mouseY;
	int mousedx;
	int mousedy;

	bool altDown;
	bool controlDown;
	bool shiftDown;

	void mapJoystickKeyToButton(int a, Buttons b, int whichJoystick, int whichPlayer){
		if(b > NUM_BUTTONS)
			return;
		joystickMap[whichJoystick][a] = InputMap(cast(int) b, whichPlayer);
	}

	/*
		How does this work?

		when and local are the fancy ones.

		Maybe when should always be globalTimer + 1. This way, you have a local wait of 1 frame
		and the remote ones are set to go off one frame later, which gives them time to get down the wire.

		I think that works.

	*/


	uint lag = 0; // should not be > 10 XXX

	void getNetworkControllerData(){
		int type, when, which, button;

		if(!net) return;

			int n = SDLNet_CheckSockets(socketset, 0); // timeout of 1000 might be good too
			if(n < 0)
				throw new Exception("Check sockets");
			if(n == 0)
				return;

			if(isServer){
			for(int a = 0; a < numberOfClients; a++){
				if(SDLNet_SocketReady(clients[a].sock)){
					byte[16] data;
					if(SDLNet_TCP_Recv(clients[a].sock, data.ptr, 16) <= 0){
						throw new Exception("someone closed");
					}

					type = SDLNet_Read32(data.ptr);
					when = SDLNet_Read32(data.ptr+4);
					which = SDLNet_Read32(data.ptr+8);
					button = SDLNet_Read32(data.ptr+12);

					changeButtonState(cast(Buttons) button, type == 0 ? true : false, which, when);

					// don't forget to forward the data to everyone else
					for(int b = 0; b< numberOfClients; b++)
						if(b != a)
						if(SDLNet_TCP_Send(clients[b].sock, data.ptr, 16) < 16)
							throw new Exception("network send failure");

				}
			}
			} else if(SDLNet_SocketReady(clientsock)) {
				byte[16] data;
				if(SDLNet_TCP_Recv(clientsock, data.ptr, 16) <= 0){
					throw new Exception("connection closed");
				}
				type = SDLNet_Read32(data.ptr);
				when = SDLNet_Read32(data.ptr+4);
				which = SDLNet_Read32(data.ptr+8);
				button = SDLNet_Read32(data.ptr+12);

				changeButtonState(cast(Buttons) button, type == 0 ? true : false, which, when);
			}


	}

	void changeButtonState(Buttons button, bool type, int which, uint when, bool sendToNet = false){
	if(when  <= lag)
		return;
		if(when > globalTimer){
			lagbuttonsDown[button][which][buttonLagQueueEnd[button][which]] = type;
			buttonLagRemaining[button][which][buttonLagQueueEnd[button][which]] = when - globalTimer;

			buttonLagQueueLength[button][which]++;
			buttonLagQueueEnd[button][which]++;
			if(buttonLagQueueEnd[button][which] == LAG_QUEUE_SIZE)
				buttonLagQueueEnd[button][which] = 0;
		} else {
			if(when < globalTimer)
				throw new Exception(immutableString("Impossible control timing " ~ convToString(when) ~ " @ " ~ convToString(globalTimer)));
			buttonsDown[button][which] = type;
			buttonsChecked[button][which] = false;
		}

		if(net && sendToNet){
			byte[16] data;
			SDLNet_Write32(type ? 0 : 1, data.ptr);
			SDLNet_Write32(when, data.ptr+4);
			SDLNet_Write32(which, data.ptr+8);
			SDLNet_Write32(button, data.ptr+12);
			if(isServer){
				for(int a = 0; a< numberOfClients; a++)
					if(SDLNet_TCP_Send(clients[a].sock, data.ptr, 16) < 16)
						throw new Exception("network send failure");

			} else {
				if(SDLNet_TCP_Send(clientsock, data.ptr, 16) < 16)
					throw new Exception("network send failure");
			}
		}
	}

	void updateControllers(){
		for(int a = 0; a < 16; a++){ // FIXME: should be changed to number of players
			for(int b = 0; b < NUM_BUTTONS; b++)
				for(int co = 0, q = buttonLagQueueStart[b][a]; co < buttonLagQueueLength[b][a]; q++, co++){
				if(q == LAG_QUEUE_SIZE)
					q = 0;
				if(buttonLagRemaining[b][a][q]){
					buttonLagRemaining[b][a][q]--;
					if(!buttonLagRemaining[b][a][q]){
						changeButtonState(cast(Buttons) b, lagbuttonsDown[b][a][q], a, globalTimer);
						buttonLagQueueStart[b][a]++;
						buttonLagQueueLength[b][a]--;
						if(buttonLagQueueStart[b][a] == LAG_QUEUE_SIZE)
							buttonLagQueueStart[b][a] = 0;
					}
				}
				}
		}
	}

	int eventLoop(){
		SDL_Event event;
	  while(SDL_WaitEvent(&event) >= 0 && !wantToQuit){
	    switch(event.type){
		case SDL_KEYUP:
		case SDL_KEYDOWN:
			bool type = event.key.type == SDL_KEYDOWN ? true : false;
				if(event.key.keysym.sym in keyboardMap){
					int button = keyboardMap[event.key.keysym.sym].button;
					int which = keyboardMap[event.key.keysym.sym].which;
					changeButtonState(cast(Buttons) button, type, which, globalTimer + lag, true);
				}

			if(event.key.keysym.sym < 400){
				keysDown[event.key.keysym.sym] = (event.key.type == SDL_KEYDOWN) ? true : false;
				keysChecked[event.key.keysym.sym] = false;
			}


			keyEvent(
				event.key.type == SDL_KEYDOWN ? BUTTONDOWN : BUTTONUP,
				event.key.keysym.sym,
				event.key.keysym.unicode,
				event.key.keysym.mod
			);
		break;
		case SDL_JOYAXISMOTION:
		// the things here are to avoid little changes around the center if the stick isn't perfect
		if ( ( event.jaxis.value < -3200 ) || (event.jaxis.value > 3200 ) || event.jaxis.value == 0){
			int stick;
			if(event.jaxis.axis >= 0 && event.jaxis.axis < 6)

				stick = event.jaxis.axis;
			else
				break;

			int which = event.jaxis.which;
			if(stick == leftStickXAxis[which] || stick == dpadXAxis[which]){
				changeButtonState(left, event.jaxis.value < -28000, which, globalTimer + lag, true);
				changeButtonState(right, event.jaxis.value > 28000, which, globalTimer + lag, true);

				stickX[0][which] = event.jaxis.value;
			}
			if(stick == leftStickYAxis[which] || stick == dpadYAxis[which]){
				changeButtonState(up, event.jaxis.value < -28000, which, globalTimer + lag, true);
				changeButtonState(down, event.jaxis.value > 28000, which, globalTimer + lag, true);

				stickY[0][which] = event.jaxis.value;
			}
			if(stick == rightStickXAxis[which]){
				stickX[1][which] = event.jaxis.value;
				changeButtonState(left2, event.jaxis.value < -28000, which, globalTimer + lag, true);
				changeButtonState(right2, event.jaxis.value > 28000, which, globalTimer + lag, true);
			}
			if(stick == rightStickYAxis[which]){
				stickY[1][which] = event.jaxis.value;
				changeButtonState(up2, event.jaxis.value < -28000, which, globalTimer + lag, true);
				changeButtonState(down2, event.jaxis.value > 28000, which, globalTimer + lag, true);
			}
			// x-box 360 controller stuff
			if(stick == leftTriggerAxis[which]){
				stickX[2][which] = event.jaxis.value;

				changeButtonState(L2, event.jaxis.value > 32000, which, globalTimer + lag, true);
			}
			if(stick == rightTriggerAxis[which]){
				stickY[2][which] = event.jaxis.value;
				changeButtonState(R2, event.jaxis.value > 32000, which, globalTimer + lag, true);
			}


			joystickEvent(
				MOTION,
				event.jaxis.which,
				event.jaxis.axis,
				event.jaxis.value
			);
		}
		break;
		case SDL_JOYHATMOTION:
		/+
			joystickEvent(
				HATMOTION,
				event.jhat.which,
				event.jhat.hat,
				event.jhat.value
			);
		+/
		break;
		case SDL_JOYBUTTONDOWN:
		case SDL_JOYBUTTONUP:
			if(event.jbutton.button in joystickMap[event.jbutton.which]){
				int which = joystickMap[event.jbutton.which][event.jbutton.button].which;
				int button = joystickMap[event.jbutton.which][event.jbutton.button].button;

				changeButtonState(cast(Buttons) button, event.jbutton.type == SDL_JOYBUTTONDOWN ? true : false, which, globalTimer + lag, true);
			}

			joystickEvent(
				event.jbutton.type == SDL_JOYBUTTONDOWN ? BUTTONDOWN : BUTTONUP,
				event.jbutton.which,
				event.jbutton.button,
				event.jbutton.state
			);
		break;

		case SDL_MOUSEBUTTONDOWN:
		case SDL_MOUSEBUTTONUP:
			mouseButtonsDown[event.button.button] = event.button.type == SDL_MOUSEBUTTONDOWN ? true : false;
			mouseButtonsChecked[event.button.button] = false;
			mouseEvent(
				event.button.type == SDL_MOUSEBUTTONDOWN ? BUTTONDOWN : BUTTONUP,
				event.button.x,
				event.button.y,
				0,		// xrel
				0,		// yrel
				event.button.button,
				0		//state
			);
		break;
		case SDL_MOUSEMOTION:
			mouseX = event.motion.x;
			mouseY = event.motion.y;
			mousedx += event.motion.xrel;
			mousedy += event.motion.yrel;
		
			mouseEvent(
				MOTION,
				event.motion.x,
				event.motion.y,
				event.motion.xrel,
				event.motion.yrel,
				0,
				event.motion.state
			);
		break;

		case SDL_USEREVENT:
			timerEvent();
		break;
		case SDL_QUIT:
			if(quitEvent() == true)
				quit();
		break;
		default:
	    }
	  }
		return 0;
	}

}
extern(C){
	Uint32 tcallback(Uint32 interval, void* param){
		if(waiting)
			return interval;
		SDL_Event event;

		event.type = SDL_USEREVENT;
		event.user.code = 0;
		event.user.data1 = null;
		event.user.data2 = null;
		SDL_PushEvent(&event);

		return interval;
	}
}

int SDLNet_SocketReady(void* sock) {
        SDLNet_GenericSocket s = cast(SDLNet_GenericSocket)sock;
        return sock != cast(TCPsocket)0 && s.ready;             
}



Engine engine;

bool buttonWasPressed(Engine.Buttons button, int which = 0){
	return engine.buttonWasPressed(button, which);
}

bool buttonIsDown(Engine.Buttons button, int which = 0){
	return engine.buttonIsDown(button, which);
}
/*
bool directionWasPressed(Engine.Direction direction, int which = 0){
	return engine.directionWasPressed(direction, which);
}

bool directionIsDown(Engine.Direction d, int which = 0){
	return engine.directionIsDown(d, which);
}
*/


