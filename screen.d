// This code is D 1.0

/**
	Part of my old D 1.0 game helper code that used SDL. I keep it compiling on new D compilers too, but it is not meant to be used in new projects.
*/
module arsd.screen;

import sdl.SDL;
import sdl.SDL_image;
import sdl.SDL_ttf;
import std.string;

import std.stdio;
import std.format;

import arsd.engine;

version(D_Version2)
static import stdcstring = core.stdc.string;
else
static import stdcstring = std.c.string;

version(none)
char[] fmt(...){
    char[] o;
    void putc(dchar c)
    {
    	o ~= c;
    }

    std.format.doFormat(&putc, _arguments, _argptr);

	return o;
}


extern(C){
	void glGetIntegerv(int, void*);
	void glMatrixMode(int);
	void glPushMatrix();
	void glLoadIdentity();
	void glOrtho(double, double, double, double, double, double);
	void glPopMatrix();
	void glEnable(int);
	void glDisable(int);
	void glClear(int);
	void glBegin(int);
	void glVertex2f(float, float);
	void glEnd();
	void glColor3b(ubyte, ubyte, ubyte);
	void glColor3i(int, int, int);
	void glColor3f(float, float, float);
	void glColor4f(float, float, float, float);
	void glTranslatef(float, float, float);

	void glRotatef(float, float, float, float);

	uint glGetError();

	void glDeleteTextures(int, uint*);

	char* gluErrorString(uint);

	void glRasterPos2i(int, int);
	void glDrawPixels(int, int, uint, uint, void*);
	void glClearColor(float, float, float, float);



	void glGenTextures(uint, uint*);
	void glBindTexture(int, int);
	void glTexParameteri(uint, uint, int);
	void glTexImage2D(int, int, int, int, int, int, int, int, void*);


	void glTexCoord2f(float, float);
	void glVertex2i(int, int);
	void glBlendFunc (int, int);
	void glViewport(int, int, int, int);

	void glReadBuffer(uint);
	void glReadPixels(int, int, int, int, int, int, void*);


	const uint GL_FRONT = 0x0404;

	const uint GL_BLEND = 0x0be2;
	const uint GL_SRC_ALPHA = 0x0302;
	const uint GL_ONE_MINUS_SRC_ALPHA = 0x0303;


	const uint GL_UNSIGNED_BYTE = 0x1401;
	const uint GL_RGB = 0x1907;
	const uint GL_BGRA = 0x80e1;
	const uint GL_RGBA = 0x1908;
	const uint GL_TEXTURE_2D =   0x0DE1;
	const uint GL_TEXTURE_MIN_FILTER = 0x2801;
	const uint GL_NEAREST = 0x2600;
	const uint GL_LINEAR = 0x2601;
	const uint GL_TEXTURE_MAG_FILTER = 0x2800;

	const uint GL_NO_ERROR = 0;



	const int GL_VIEWPORT = 0x0BA2;
	const int GL_MODELVIEW = 0x1700;
	const int GL_TEXTURE = 0x1702;
	const int GL_PROJECTION = 0x1701;
	const int GL_DEPTH_TEST = 0x0B71;

	const int GL_COLOR_BUFFER_BIT = 0x00004000;
	const int GL_ACCUM_BUFFER_BIT = 0x00000200;
	const int GL_DEPTH_BUFFER_BIT = 0x00000100;

	const int GL_POINTS = 0x0000;
	const int GL_LINES =  0x0001;
	const int GL_LINE_LOOP = 0x0002;
	const int GL_LINE_STRIP = 0x0003;
	const int GL_TRIANGLES = 0x0004;
	const int GL_TRIANGLE_STRIP = 5;
	const int GL_TRIANGLE_FAN = 6;
	const int GL_QUADS = 7;
	const int GL_QUAD_STRIP = 8;
	const int GL_POLYGON = 9;

}

public struct Point{
	int x;
	int y;
	Point opAddAssign(Point p){
		x += p.x;
		y += p.y;
		version(D_Version2)
			return this;
		else
			return *this;
	}

	Point opAdd(Point p){
		Point a;
		a.x = x + p.x;
		a.y = y + p.y;
		return a;
	}

	Point opSub(Point p){
		Point a;
		a.x = x - p.x;
		a.y = y - p.y;
		return a;
	}
}

Point XY(int x, int y){
	Point p;
	p.x = x;
	p.y = y;
	return p;
}

Point XY(float x, float y){
	Point p;
	p.x = cast(int)x;
	p.y = cast(int)y;
	return p;
}

public struct Color{
	int r;
	int g;
	int b;
	int a;

	uint toInt(){
		return r << 24 | g << 16 | b << 8 | a;
	}

	void fromInt(uint i){
		r = i >> 24;
		g = (i >> 16) & 0x0ff;
		b = (i >> 8) & 0x0ff;
		a = i & 0x0ff;
	}
}

Color white = {255, 255, 255, 255};
Color black = {0, 0, 0, 255};

Color RGB(int r, int g, int b){
	Color c;
	c.r = r;
	c.g = g;
	c.b = b;
	c.a = 255;
	return c;
}

Color RGBA(int r, int g, int b, int a){
	Color c;
	c.r = r;
	c.g = g;
	c.b = b;
	c.a = a;
	return c;
}

Color XRGB(Color c, int alpha = -1){
	Color a;
	a.r = c.r ^ 255;
	a.g = c.g ^ 255;
	a.b = c.b ^ 255;
	if(alpha == -1)
		a.a = c.a;// ^ 255;
	else
		a.a = alpha;
	return a;
}

class FontEngine{
  public:

	static FontEngine instance;

	~this(){
		foreach(a; fonts)
			if(a != null)
				TTF_CloseFont(a);
		TTF_Quit();
	}

	void loadFont(in char[] font, int size = 12, int index = 0){
		if(fonts[index] != null)
			freeFont(index);
		TTF_Font* temp;
		temp = TTF_OpenFont(std.string.toStringz(font), size);
		if(temp == null)
			throw new Exception("load font");

		fonts[index] = temp;
	}

	void freeFont(int index = 0){
		if(fonts[index] != null){
			TTF_CloseFont(fonts[index]);
			fonts[index] = null;
		}
	}

	Image renderText(in char[] text, Color foreground = RGB(255,255,255), int font = 0){
		Image* a = immutableString(text) in cache[font];
		if(a !is null)
			return *a;
		SDL_Color f;
		f.r = cast(ubyte) foreground.r;
		f.g = cast(ubyte) foreground.g;
		f.b = cast(ubyte) foreground.b;
		f.unused = cast(ubyte) foreground.a;

		SDL_Surface* s = TTF_RenderText_Blended(fonts[font], std.string.toStringz(text), f);
		Image i = new Image(s);
		cache[font][text]/*[font]*/ = i;

		return i;
	}

	int textHeight(in char[] text=" ",int font = 0){
		int w, h;
		TTF_SizeText(FontEngine.instance.fonts[font], std.string.toStringz(text), &w, &h);
		return h;
	}

	void textSize(in char[] text, out int w, out int h, int font = 0){
		TTF_SizeText(fonts[font], std.string.toStringz(text), &w, &h);
	}
  private:
	static this() {
		instance = new FontEngine;
	}

	this(){
		if(TTF_Init() == -1)
			throw new Exception("TTF_Init");

	}

	TTF_Font*[8] fonts;
	Image[char[]][8] cache;
}

interface Drawable{
  public:
	void flip();
	int width();
	int height();
	int bpp();
	/*
	uint toGL();
	float texWidth();
	float texHeight();
	*/
  protected:
	SDL_Surface* surface();
}

int total = 0;


class Image : Drawable{
  public:
  	this(SDL_Surface* s){
		if(s == null)
			throw new Exception("Image");
		sur = s;
	}

	/// Loads an image with the filename checking to see if it has already been loaded into the cache
	/// loads it as read-only
//	static Image load(char[] filename){

//	}

	this(char[] filename){
		sur = IMG_Load(std.string.toStringz(filename));
		if(sur == null)
			throw new Exception(immutableString("Load " ~ filename));
		name = filename;
	}


	void replace(char[] filename){
		if(t){
			glDeleteTextures(1, &tex);
			total--;
			writef("[%s]OpenGL texture destroyed %d. %d remain\n", name, tex, total);
			t = 0;
		}
		if(sur){
			SDL_FreeSurface(sur);
			sur = null;
		}
		sur = IMG_Load(std.string.toStringz(filename));
		if(sur == null)
			throw new Exception(immutableString("Load " ~ filename));
		name = filename;
	}


	// loads a slice of an image
	this(char[] filename, int x, int y, int wid, int hei){
	/*
		Image i = new Image(filename);
		this(wid, hei);

		scope Painter p = new Painter(this);
		for(int a = 0; a < wid; a++)
		for(int b = 0; b < hei; b++)
			p.putpixel(XY(a, b), i.getPixel(XY(a + x, b + y)));
	*/
	
		SDL_Surface* s1;

		s1 = IMG_Load(std.string.toStringz(filename));
		if(s1 == null)
			throw new Exception(immutableString("Loading " ~ filename));
		scope(exit)
			SDL_FreeSurface(s1);


		sur = SDL_CreateRGBSurface(SDL_SWSURFACE, wid, hei, 32, 0xff0000, 0x00ff00, 0x0000ff, 0xff000000);
		if(sur == null)
			throw new Exception(immutableString("Create"));


		for(int b = 0; b < hei; b++){
			for(int a = 0; a < wid; a++){
			if(b+y >= s1.h || a+x >= s1.w){
				break;
			//	throw new Exception("eat my cum");
			}
				ubyte* wtf;
				if(s1.format.BitsPerPixel == 32){
					wtf = cast(ubyte*)(cast(ubyte*)s1.pixels + (b+y)*s1.pitch + (a+x) * 4);
				}
				else
				if(s1.format.BitsPerPixel == 24)
					wtf = cast(ubyte*)(cast(ubyte*)s1.pixels + (b+y)*s1.pitch + (a+x) * 3);
				else
					throw new Exception("fuck me in the ass");

				ubyte* good = cast(ubyte*)(cast(ubyte*)sur.pixels + b*sur.pitch + a * 4);

				good[0] = wtf[2];
				good[1] = wtf[1];
				good[2] = wtf[0];
				good[3] = wtf[3];

			}
		}


/*
		SDL_Rect r;
		r.x = x;
		r.y = y;
		r.w = wid;
		r.h = hei;

		SDL_Rect r2;
		r2.x = 0;
		r2.y = 0;
		r2.w = wid;
		r2.h = hei;
		if(SDL_BlitSurface(s1, &r, sur, &r2))
			throw new Exception("Blit");
*/
	}

	this(int wid, int hei){
		sur = SDL_CreateRGBSurface(SDL_SWSURFACE, wid, hei, 32, 0xff0000, 0x00ff00, 0x0000ff, 0xff000000);
		if(sur == null)
			throw new Exception("Create");
		t = false;
	}

	~this(){
		if(t){
			glDeleteTextures(1, &tex);
			total--;
			writef("[%s]OpenGL texture destroyed %d. %d remain\n", name, tex, total);
		}
		if(sur)
			SDL_FreeSurface(sur);
	}

	void flip(){

	}

	int width(){
		return surface.w;
	}

	int height(){
		return surface.h;
	}

	int bpp(){
		return sur.format.BitsPerPixel;
	}

	Color getPixel(Point p){
		ubyte* bufp;
		Color a;

		if(bpp == 32){
			bufp = cast(ubyte*)(cast(ubyte*)surface.pixels + p.y*surface.pitch + p.x * 4);
			a.a = bufp[3];
		        a.r = bufp[2];
		        a.g = bufp[1];
        		a.b = bufp[0];
		}else{
			bufp = cast(ubyte*)(cast(ubyte*)surface.pixels + p.y*surface.pitch + p.x * 3);
		        a.a = 255;
			a.r = bufp[2];
		       	a.g = bufp[1];
	        	a.b = bufp[0];
		}
	
		return a;
	}

	uint toGL(){
		if(t)
			return tex;
		else{
			float[4] f;
			tex = SDL_GL_LoadTexture(surface, f.ptr);
			t = true;
			total++;
			texWidth = f[2];
			texHeight = f[3];

//			total++;
//			writef("OpenGL texture created %d. %d exist\n", tex, total);

			return tex;
		}
	}
  protected:
	SDL_Surface* surface(){
		return sur;
	}
  private:
  	SDL_Surface* sur;
	uint tex;
	bool t;
	float texWidth;
	float texHeight;
	char[] name;
}

bool useGL;

class Screen : Drawable{
  public:
	this(int xres = 1024, int yres = 768, int bpp = 24, bool oGL = false, bool fullScreen = false){//true){
//	oGL = false;
	oGL = true;
		if(!oGL)
			screen = SDL_SetVideoMode(xres, yres, bpp/*32*/, SDL_SWSURFACE);
		else{
			SDL_GL_SetAttribute( SDL_GL_RED_SIZE, 8 );
			SDL_GL_SetAttribute( SDL_GL_GREEN_SIZE, 8 );
			SDL_GL_SetAttribute( SDL_GL_BLUE_SIZE, 8 );
			SDL_GL_SetAttribute( SDL_GL_DEPTH_SIZE, 24 );
			SDL_GL_SetAttribute( SDL_GL_DOUBLEBUFFER, 1 );
			if(fullScreen){
			screen = SDL_SetVideoMode(xres, yres, 24, SDL_OPENGL| SDL_FULLSCREEN);
			}
			else
			screen = SDL_SetVideoMode(xres, yres, 0, SDL_OPENGL);
			//screen = SDL_SetVideoMode(xres, yres, bpp, SDL_OPENGL);
			if(screen is null)
				throw new Exception("screen");

   			glMatrixMode(GL_PROJECTION);
   			glLoadIdentity();
   			//glOrtho(0, 1000, yres, 0, 0, 1);
   			glOrtho(0, xres, yres, 0, 0, 1);
   			glMatrixMode(GL_MODELVIEW);

			glDisable(GL_DEPTH_TEST);

			glEnable(GL_TEXTURE_2D);


			glEnable (GL_BLEND); glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);


			glClearColor(0,0,0,0);

//			glViewport(0,0,1024,1024);
		}

		useGL = oGL;

		if(screen == null)
			throw new Exception("screen");

//		SDL_SetAlpha(screen, SDL_SRCALPHA | SDL_RLEACCEL, 128);

		xr = xres;
		yr = yres;
	}

	void switchSplitScreenMode(int player, int numberOfPlayers, bool horizontal){
			switch(numberOfPlayers){
				default: assert(0);
				case 1:
					return;
//					glViewport(0, 0, xr, yr);
				break;
				case 2:
					switch(player){
						default: assert(0);
						case 0:
							if(horizontal)
								glViewport(0, yr / 2, xr, yr / 2);
							else
								glViewport(0, 0, xr / 2, yr);
						break;
						case 1:
							if(horizontal)
								glViewport(0, 0, xr, yr / 2);
							else
								glViewport(xr / 2, 0, xr / 2, yr);
						break;
					}
				break;
				case 3:
				case 4:
					switch(player){
						default: assert(0);
					  case 0:
						glViewport(0, yr / 2, xr / 2, yr / 2);
					  break;
					  case 1:
						glViewport(xr / 2, yr / 2, xr / 2, yr / 2);
					  break;
					  case 2:
						glViewport(0, 0, xr / 2, yr / 2);
					  break;
					  case 3:
						glViewport(xr / 2, 0, xr / 2, yr / 2);
					  break;
					}

				break;
			}
			glMatrixMode(GL_PROJECTION);
			glLoadIdentity();
			glOrtho(0, xr, yr, 0, 0, 1);
	}


	~this(){
		delete FontEngine.instance;
	}

	Image screenshot(){
		if(!useGL)
			throw new Exception("Not yet implemented");
		Image image = new Image(xr, yr);
		glReadBuffer(GL_FRONT);
		glReadPixels(0, 0, xr, yr, GL_BGRA, GL_UNSIGNED_BYTE, image.sur.pixels);

		Image temp = new Image(xr, yr);


	// FIXME
	version(Windows)
		return image;

		// FIXME: this crashes on Windows
		for(int i = 0; i < yr; i++)
			stdcstring.memcpy(temp.sur.pixels + 4 * xr * i, image.sur.pixels + 4 * xr * (yr-1 - i), 4 * xr);
//        memcpy(image.sur.pixels, tem.psur.pixels, xres * yres * 4);

		return temp;
	}




	void flip(){
		if(useGL)
			SDL_GL_SwapBuffers();
		else
			SDL_Flip(screen);
	}

	int width(){
		return xr;
	}

	int height(){
		return yr;
	}

	int bpp(){
		return 124;
	}
	/*
	uint toGL(){
		throw new Error;
	}
	float texWidth(){
		return 1.0;
	}
	float texHeight(){
		return 1.0;
	}
*/
  protected:
	SDL_Surface* surface(){
		return screen;
	}

  private:
	SDL_Surface* screen;
	int xr;
	int yr;
}

scope class Painter{
  public:
	bool special;
	bool manualFlipped;
	Point translate;
	this(Painter p, Point t){
		s = p.s;
		special = true;
		translate = t;
	}

	this(Drawable d){
	/+
		in {
			assert(!(s is null));
		}
	+/
		s = d;
		if(s is null)
			throw new Exception("christ what were you thinking");

		if ( !(useGL
		&& s.bpp() == 124)
		&& SDL_MUSTLOCK(s.surface()) ) {
			if ( SDL_LockSurface(s.surface()) < 0 ) {
				throw new Exception("locking");
			}
			locked = true;
		}
	}

	~this(){
		if(!manualFlipped){
		if(glbegin)
			endDrawingShapes();
		if(!special){
		if (locked){
			SDL_UnlockSurface(s.surface);
		}
		s.flip();
		}
		}
	}

	void manualFlip(){
		if(glbegin)
			endDrawingShapes();
		if(!special){
		if (locked){
			SDL_UnlockSurface(s.surface);
		}
		s.flip();
		}
		manualFlipped = true;
	}

	void setGLColor(Color color){
		if(useGL && s.bpp == 124){
			glColor4f(cast(float)color.r/255.0, cast(float)color.g/255.0, cast(float)color.b/255.0, cast(float)color.a / 255.0);
			return;
		}
	}

	void putpixel(Point where, Color color){
		if(special) where += translate;
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

//		if(color.a == 255)
//			return;
		int x = where.x;
		int y = where.y;
		if(x < 0 || x >= s.width || y < 0 || y >= s.height)
			return;



		if(useGL && s.bpp == 124){
		//	y = 480 - y;
			glBegin(GL_POINTS);
			setGLColor(color);
			glVertex2f(cast(float)x, cast(float)y);
			glEnd();
			return;
		}


		ubyte *bufp;

		if(s.bpp == 32){
			bufp = cast(ubyte*)(cast(ubyte*)s.surface.pixels + y*s.surface.pitch + x * 4);
				bufp[3] = cast(ubyte) color.a;
			        bufp[2] = cast(ubyte) color.r;
			        bufp[1] = cast(ubyte) color.g;
        			bufp[0] = cast(ubyte) color.b;
		}else{
			bufp = cast(ubyte*)(cast(ubyte*)s.surface.pixels + y*s.surface.pitch + x * 3);
			if(color.a == 255){
			        bufp[2] = cast(ubyte) color.r;
		        	bufp[1] = cast(ubyte) color.g;
	        		bufp[0] = cast(ubyte) color.b;
			}
			else{
			        bufp[2] = cast(ubyte)(bufp[2] * (255-color.a) + (color.r * (color.a)) / 255);
			        bufp[1] = cast(ubyte)(bufp[1] * (255-color.a) + (color.g * (color.a)) / 255);
		        	bufp[0] = cast(ubyte)(bufp[0] * (255-color.a) + (color.b * (color.a)) / 255);
			}
		}
	}

	void beginDrawingLines(){
		if(glbegin)
			throw new Exception("Can only draw one kind at a time");
		glbegin = true;
		if(useGL && s.bpp == 124)
			glBegin(GL_LINES);
	}
	void beginDrawingConnectedLines(){
		if(glbegin)
			throw new Exception("Can only draw one kind at a time");
		glbegin = true;
		if(useGL && s.bpp == 124)
			glBegin(GL_LINE_STRIP);
	}
	void beginDrawingPolygon(){
		if(glbegin)
			throw new Exception("Can only draw one kind at a time");
		glbegin = true;
		if(useGL && s.bpp == 124)
			glBegin(GL_POLYGON);
	}
	void beginDrawingTriangles(){
		if(glbegin)
			throw new Exception("Can only draw one kind at a time");
		glbegin = true;
		if(useGL && s.bpp == 124)
			glBegin(GL_TRIANGLES);
	}
	void beginDrawingBoxes(){
		if(glbegin)
			throw new Exception("Can only draw one kind at a time");
		glbegin = true;
		if(useGL && s.bpp == 124)
			glBegin(GL_QUADS);
	}
	void beginDrawingPoints(){
		if(glbegin)
			throw new Exception("Can only draw one kind at a time");
		glbegin = true;
		if(useGL && s.bpp == 124)
			glBegin(GL_POINTS);
	}

	void endDrawingShapes(){
		if(!glbegin)
			return;
		glbegin = false;
		if(useGL && s.bpp == 124)
			glEnd();
	}
	void vertex(Point p){
		if(special) p += translate;
		if(!glbegin)
			throw new Exception("Can't use vertex without beginning first");
		if(useGL && s.bpp == 124)
			glVertex2i(p.x, p.y);
	}
	bool glbegin;

	void drawImageRotated(Point where, Image i, float a, Color color = RGB(255,255,255)){
		if(i is null)
			return;
		glPushMatrix();
	//	glRotatef(a, cast(float)(where.x + 32) / s.width, cast(float)(where.y + 32) / s.height, 1);
		glTranslatef(where.x, where.y, 0);
		glRotatef(a, 0,0, 1);
		drawImage(XY(-i.width/2,-i.height/2), i, i.width, i.height, color);
		glPopMatrix();
	}

	void drawImage(Point where, Image i, Color c){
		drawImage(where, i, 0, 0, c);
	}

	void drawImage(Point where, Image i, int W = 0, int H = 0, Color c = RGBA(255,255,255,255)){
		if(i is null)
			return;

		if(special) where += translate;
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");
		if(useGL && s.bpp == 124){
			int x = where.x;
			int y = where.y;
			int w = W == 0 ? i.width : W;
			int h = H == 0 ? i.height : H;

//			glColor4f(.5,.5,.5,1);
			setGLColor(c);
			glBindTexture(GL_TEXTURE_2D, i.toGL);
			glBegin(GL_QUADS);
				glTexCoord2f(0, 0); 			glVertex2i(x, y);
				glTexCoord2f(i.texWidth, 0); 		glVertex2i(x+w, y);
				glTexCoord2f(i.texWidth, i.texHeight); 	glVertex2i(x+w, y+h);
				glTexCoord2f(0, i.texHeight); 		glVertex2i(x, y+h);
			glEnd();

			glBindTexture(GL_TEXTURE_2D, 0); // unbind the texture... I guess
				// I don't actually understand why that is needed
				// but without it, everything drawn after it is wrong (too light or dark)
			return;
		}

		if((W == 0 && H == 0) || (i.width == W && i.height == H)){
		SDL_Rect r;
		r.x = cast(short)( where.x);
		r.y = cast(short)( where.y);
		r.w = cast(short)( i.width);
		r.h = cast(short)( i.height);
		if(locked)
			SDL_UnlockSurface(s.surface);

		if(SDL_BlitSurface(i.surface, null, s.surface, &r) == -1)
			throw new Exception("blit");

		if ( SDL_MUSTLOCK(s.surface) ) {
			if ( SDL_LockSurface(s.surface) < 0 ) {
				throw new Exception("lock");
			}
			locked = true;
		}
		} else { // quick and dirty scaling needed
			float dx = cast(float)i.width / cast(float)W;
			float dy = cast(float)i.height / cast(float)H;
			int X = where.x, Y = where.y;

			for(float y = 0; y < i.height; y += dy){
				for(float x = 0; x < i.width; x += dx){
					putpixel(XY(X, Y), i.getPixel(XY(cast(int) x, cast(int) y)));
					X++;
				}
				X = where.x;
				Y++;
			}

		}

	}

	void drawText(Point where, in char[] text, Color foreground = RGB(255,255,255), int font = 0){
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

		if(useGL && s.bpp == 124){
			Image i = FontEngine.instance.renderText(text, RGB(255,255,255), font);
			drawImage(where, i, foreground);
		}else{
			Image i = FontEngine.instance.renderText(text, foreground, font);
			drawImage(where, i);
		}
	}

	version(D_Version2) {
		import std.format;
		void drawTextf(T...)(Point where, T args) {
			char[] t;
			t.length = 80;
			int a = 0;
			void putc(dchar c){
				if(a == t.length)
					t.length = t.length + 80;
				t[a] = cast(char) c;
				a++;
			}
			formattedWrite(&putc, args);
			t.length = a;

			drawText(where, t);
		}
	} else
	void drawTextf(Point where, ...){
		char[] t;
		t.length = 80;
		int a = 0;
		void putc(dchar c){
			if(a == t.length)
				t.length = t.length + 80;
			t[a] = cast(char) c;
			a++;
		}
		std.format.doFormat(&putc, _arguments, _argptr);
		t.length = a;

		drawText(where, t);
	}

	int wordLength(in char[] w, int font = 0){
		int a,b;
		FontEngine.instance.textSize(w, a, b, font);
		return a;
	}

	int drawTextBoxed(Point where, char[] text, int width, int height, Color foreground = RGB(255,255,255), int font = 0){
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");


		int xc;
		int yc = TTF_FontLineSkip(FontEngine.instance.fonts[font]);

		int w = 0;
		int h = 0;

		int l;

char[] getWord(){
	int a = l;
	while(a < text.length && text[a] != ' ' && text[a] != '\n' && text[a] != '\t')
		a++;
	return text[l..a];
}

int wordLength(in char[] w){
	int a,b;
	FontEngine.instance.textSize(w, a, b, font);
	return a;
}

		Point ww = where;
		while(l < text.length){
			if(text[l] == '\n'){
				l++;
				goto newline;
			}
			if(wordLength(getWord()) + w > width){
				goto newline;
			}

			if(!(w == 0 && text[l] == ' ')){
				TTF_GlyphMetrics(FontEngine.instance.fonts[font], text[l], null,null,null,null,&xc);
				drawText(ww, text[l..(l+1)], foreground, font);
				w+=xc;
				ww.x += xc;
			}
			l++;
			if(w > (width - xc)){
			newline:
				w = 0;
				h += yc;
				ww.x = cast(short)(where.x);
				ww.y += cast(short)(yc);

				if(h > (height - yc))
					break;
			}
		}
		return l;
	}

	void drawTextCenteredHoriz(int top, char[] text, Color foreground, int font = 0){
		Point where;
		where.y = top;
		int w, h;
		TTF_SizeText(FontEngine.instance.fonts[font], std.string.toStringz(text), &w, &h);
		where.x = (s.width - w) / 2;
		drawText(where, text, foreground, font);
	}

	void line(Point start, Point end, Color color){
		if(special){ start += translate; end += translate; }
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

		if(useGL && s.bpp == 124){
			setGLColor(color);
			glBegin(GL_LINES);
			glVertex2i(start.x, start.y);
			glVertex2i(end.x, end.y);
			glEnd();
		}
	}
	
	void hline(Point start, int width, Color color){
	if(useGL && s.bpp == 124){
		line(start, XY(start.x + width, start.y), color);
		return;
	}
		Point point = start;
		for(int a = 0; a < width; a++){
			putpixel(point, color);
			point.x++;
		}
	}

	void vline(Point start, int height, Color color){
	if(useGL && s.bpp == 124){
		line(start, XY(start.x, start.y + height), color);
		return;
	}

		Point point = start;
		for(int a = 0; a < height; a++){
			putpixel(point, color);
			point.y++;
		}
	}
	

	void circle(Point center, int radius, Color color){
		if(special) center += translate;
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

	}

	void arc(Point center, int radius, float start, float end, Color color){
		if(special) center += translate;
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

//		for(float a = start; a <= end; a+= (3.14159265358 / 50.0))
//			putpixel((int)(cos(a) * (float)radius + center.x()),(int)( sin(a) * (float) radius + center.y()), color);
	}

	void box(Point upperLeft, Point lowerRight, Color color){
		if(special) { upperLeft += translate; lowerRight += translate; }
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

		if(useGL && s.bpp == 124){
			int x1 = upperLeft.x;
			int y1 = upperLeft.y;
			int x2 = lowerRight.x;
			int y2 = lowerRight.y;
			glBegin(GL_QUADS);
			//glColor3b(color.r, color.g, color.b);
			setGLColor(color);
			//glColor4f(1,1,1,1);
			glVertex2i(x1, y1);
			glVertex2i(x2, y1);
			glVertex2i(x2, y2);
			glVertex2i(x1, y2);
			glEnd();
			return;
		}
		SDL_Rect r;
		r.x = cast(short) upperLeft.x;
		r.y = cast(short) upperLeft.y;
		r.w = cast(short) (lowerRight.x - upperLeft.x);
		r.h = cast(short) (lowerRight.y - upperLeft.y);
		if(s.bpp == 32)
			SDL_FillRect(s.surface, &r, color.a << 24 | color.r << 16 | color.g << 8 | color.b);
		else
			SDL_FillRect(s.surface, &r, color.r << 16 | color.g << 8 | color.b);
	}

	void rect(Point upperLeft, Point lowerRight, Color color){
		if(special) { upperLeft += translate; lowerRight += translate; }
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

		if(useGL && s.bpp == 124){
			int x1 = upperLeft.x;
			int y1 = upperLeft.y;
			int x2 = lowerRight.x;
			int y2 = lowerRight.y;
			glBegin(GL_LINE_LOOP);
			//glColor3b(color.r, color.g, color.b);
			setGLColor(color);
			//glColor4f(1,1,1,1);
			glVertex2i(x1, y1);
			glVertex2i(x2+1, y1);
			glVertex2i(x2, y2);
			glVertex2i(x1, y2);
			glEnd();
			return;
		}
		/*
		SDL_Rect r;
		r.x = upperLeft.x;
		r.y = upperLeft.y;
		r.w = lowerRight.x - upperLeft.x;
		r.h = lowerRight.y - upperLeft.y;
		if(s.bpp == 32)
			SDL_FillRect(s.surface, &r, color.a << 24 | color.r << 16 | color.g << 8 | color.b);
		else
			SDL_FillRect(s.surface, &r, color.r << 16 | color.g << 8 | color.b);
		*/
	}

	void gbox(Point upperLeft, Point lowerRight, Color color1, Color color2, Color color3, Color color4){
		if(special) { upperLeft += translate; lowerRight += translate; }
		if(glbegin)
			throw new Exception("Must end shape before doing anything else");

		Color color = color1;
		if(useGL && s.bpp == 124){
			int x1 = upperLeft.x;
			int y1 = upperLeft.y;
			int x2 = lowerRight.x;
			int y2 = lowerRight.y;
			glBegin(GL_QUADS);
			setGLColor(color1);
			glVertex2i(x1, y1);
			setGLColor(color2);
			glVertex2i(x2, y1);
			setGLColor(color4);
			glVertex2i(x2, y2);
			setGLColor(color3);
			glVertex2i(x1, y2);
			glEnd();
		return;
		}
		SDL_Rect r;
		r.x = cast(short) upperLeft.x;
		r.y = cast(short) upperLeft.y;
		r.w = cast(short) (lowerRight.x - upperLeft.x);
		r.h = cast(short) (lowerRight.y - upperLeft.y);
		if(s.bpp == 32)
			SDL_FillRect(s.surface, &r, color.a << 24 | color.r << 16 | color.g << 8 | color.b);
		else
			SDL_FillRect(s.surface, &r, color.r << 16 | color.g << 8 | color.b);
	}


	void clear(){
		if(useGL && s.bpp == 124){
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_ACCUM_BUFFER_BIT);
			return;
		}
		box(XY(0,0), XY(s.width, s.height), RGB(0,0,0));
	}

	void fill(Color color){
		box(XY(0,0), XY(s.width, s.height), color);
	}

	void blend(Color color){
		if(useGL && s.bpp == 124){
			box(XY(0,0), XY(s.width, s.height), color);
			return;
		}

		ubyte *bufp;

		bufp = cast(ubyte*)s.surface.pixels;
		for(int y = 0; y < s.height; y++)
			for(int x = 0; x < s.width; x++){
			
				bufp[2] = cast(ubyte)((bufp[2] * (255-color.a) + color.r * color.a) / 255);
			        bufp[1] = cast(ubyte)((bufp[1] * (255-color.a) + color.g * color.a) / 255);
		        	bufp[0] = cast(ubyte)((bufp[0] * (255-color.a) + color.b * color.a) / 255);

				bufp += (s.bpp == 24 ? 3 : 4);
			}
	}

  private:
  	Drawable s;
	bool locked;
}







int SDL_BlitSurface
			(SDL_Surface *src, SDL_Rect *srcrect,
			 SDL_Surface *dst, SDL_Rect *dstrect)
{
	return SDL_UpperBlit(src, srcrect, dst, dstrect);
}

bit SDL_MUSTLOCK(SDL_Surface *surface)
{
	return surface.offset || ((surface.flags &
		(SDL_HWSURFACE | SDL_ASYNCBLIT | SDL_RLEACCEL)) != 0);
}

/* Quick utility function for texture creation */
int power_of_two(int input)
{
    int value = 1;

    while ( value < input ) {
        value <<= 1;
    }
    return value;
}

uint SDL_GL_LoadTexture(SDL_Surface *surface, float *texcoord)
{
    uint texture;
    int w, h;
    SDL_Surface *image;
    SDL_Rect area;
    uint saved_flags;
    ubyte  saved_alpha;

    /* Use the surface width and height expanded to powers of 2 */
    w = power_of_two(surface.w);
    h = power_of_two(surface.h);
    texcoord[0] = 0.0f;         /* Min X */
    texcoord[1] = 0.0f;         /* Min Y */
    texcoord[2] = cast(float)surface.w / cast(float)w;  /* Max X */
    texcoord[3] = cast(float)surface.h / cast(float)h;  /* Max Y */

    image = SDL_CreateRGBSurface(
            SDL_SWSURFACE,
            w, h,
            32,
            0x000000FF,
            0x0000FF00,
            0x00FF0000,
            0xFF000000
               );
    if ( image == null) {
        throw new Exception("make image");
    }


    /* Save the alpha blending attributes */
    saved_flags = surface.flags&(SDL_SRCALPHA|SDL_RLEACCELOK);
    saved_alpha = surface.format.alpha;
    if ( (saved_flags & SDL_SRCALPHA) == SDL_SRCALPHA ) {
        SDL_SetAlpha(surface, 0, 0);
    }

    /* Copy the surface into the GL texture image */
    area.x = 0;
    area.y = 0;
    area.w = cast(ushort) surface.w;
    area.h = cast(ushort) surface.h;
    SDL_BlitSurface(surface, &area, image, &area);

    /* Restore the alpha blending attributes */
    if ( (saved_flags & SDL_SRCALPHA) == SDL_SRCALPHA ) {
        SDL_SetAlpha(surface, saved_flags, saved_alpha);
    }

    /* Create an OpenGL texture for the image */
    glGenTextures(1, &texture);

    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

    glTexImage2D(GL_TEXTURE_2D,
             0,
             GL_RGBA,
             w, h,
             0,
             GL_RGBA,
             GL_UNSIGNED_BYTE,
             image.pixels);
    SDL_FreeSurface(image); /* No longer needed */



    return texture;
}






		Color c1;
		Color c2;
		Color c3;
		Color c4;
static this(){
	c1 = RGBA(0,0,255,160);
	c2 = RGBA(0,0,255,160);
	c3 = RGBA(0,0,255,160);
	c4 = RGBA(0,0,0,160);
}

void drawHighlightBox(Painter p, Point where, int width, int height = 16){
	p.gbox(where, where + XY(width, height), XRGB(c1, 128), XRGB(c2, 128), XRGB(c3, 128), XRGB(c4, 128));
}

// Real size is width + 8, height + 8. Size given if of the client area
/*
Point drawShadedRect(Painter p, Point where, int width, int height){
	int x = where.x;
	int y = where.y;

	Color gray = RGB(128,128,128);

	p.box(XY(x + 2, y), XY( x + 2 + width + 2, y + 4), gray);
	p.box(XY(x + 2, y + height + 4), XY( x + 2 + width + 2, y + 4 + height + 4 ), gray);

	p.box(XY(x, y + 2), XY(x + 4, y + 2 + height + 2), gray);
	p.box(XY(x + 4 + width, y + 2), XY(x + 4 + width + 4, y + 2 + height + 2), gray);

//	p.putpixel(XY(x + 1, y + 1), gray);
//	p.putpixel(XY(x + 1, y + 4 + 3 + height), gray);
//	p.putpixel(XY(x + 4 + width + 3, y + 1), gray);
//	p.putpixel(XY(x + 4 + width + 3, y + 4 + 3 + height), gray);


	p.hline(XY(x + 4, y + 1),              width + 2, white);
	p.hline(XY(x + 4 - 2, y + 4 + height + 1), width + 2 + 1, white);

	p.vline(XY(x + 1 - 1, y + 3),             height + 2, white);
	p.vline(XY(x + 4 + width + 3, y + 3), height + 2, white);

	p.gbox(XY(x + 4, y + 4), XY(x + width + 4, y + height + 4), c1, c2, c3, c4);

	return XY(x + 4, y + 4);
}
*/

const int BORDER_WIDTH = 4;

Point drawShadedRect(Painter p, Point where, int width, int height){
	Color gray = RGB(128,128,128);

	Point w;
	
	// top section
	w = where + XY( BORDER_WIDTH, 0);
		p.box( 	w + XY(0, 				0 * BORDER_WIDTH / 4),
			w + XY(width, 				1 * BORDER_WIDTH / 4),
			gray);
		p.box( 	w + XY(-BORDER_WIDTH / 2, 		1 * BORDER_WIDTH / 4),
			w + XY(BORDER_WIDTH / 2 + width, 	3 * BORDER_WIDTH / 4),
			white);
		p.box( 	w + XY( -1 * BORDER_WIDTH / 4, 		3 * BORDER_WIDTH / 4),
			w + XY( 1 * BORDER_WIDTH / 4 + width , 		4 * BORDER_WIDTH / 4),
			black);
	// bottom section
	w = where + XY(BORDER_WIDTH, height + BORDER_WIDTH);
		p.box( 	w + XY(-1 * BORDER_WIDTH / 4,		0 * BORDER_WIDTH / 4),
			w + XY(1 * BORDER_WIDTH / 4 + width,			1 * BORDER_WIDTH / 4),
			black);
		p.box( 	w + XY(-BORDER_WIDTH / 2, 		1 * BORDER_WIDTH / 4),
			w + XY(BORDER_WIDTH / 2 + width, 	3 * BORDER_WIDTH / 4),
			white);
		p.box( 	w + XY(-1 *BORDER_WIDTH / 4,		3 * BORDER_WIDTH / 4),
			w + XY( 1 *BORDER_WIDTH / 4 + width, 	4 * BORDER_WIDTH / 4),
			gray);
			
	// left section
	w = where + XY( 0, BORDER_WIDTH);
		p.box( 	w + XY(0 * BORDER_WIDTH / 4, -1),
			w + XY(1 * BORDER_WIDTH / 4, height + 1),
			gray);
		p.box( 	w + XY(1 * BORDER_WIDTH / 4, -BORDER_WIDTH / 2),
			w + XY(3 * BORDER_WIDTH / 4, BORDER_WIDTH / 2 + height),
			white);
		p.box( 	w + XY(3 * BORDER_WIDTH / 4, 0),
			w + XY(4 * BORDER_WIDTH / 4, height),
			black);

	// right section
	w = where + XY( BORDER_WIDTH + width, BORDER_WIDTH);
		p.box( 	w + XY(0 * BORDER_WIDTH / 4, 0),
			w + XY(1 * BORDER_WIDTH / 4, height),
			black);
		p.box( 	w + XY(1 * BORDER_WIDTH / 4, -BORDER_WIDTH / 2),
			w + XY(3 * BORDER_WIDTH / 4, BORDER_WIDTH / 2 + height),
			white);
		p.box( 	w + XY(3 * BORDER_WIDTH / 4, -1),
			w + XY(4 * BORDER_WIDTH / 4, 1 + height),
			gray);
	w = where + XY(BORDER_WIDTH, BORDER_WIDTH);
	p.gbox(w, w + XY(width, height), c1, c2, c3, c4);
	return w;
}

