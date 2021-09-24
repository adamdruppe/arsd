// https://dpaste.dzfl.pl/7a77355acaec

// https://freedesktop.org/wiki/Specifications/XDND/

// https://docs.microsoft.com/en-us/windows/win32/dataxchg/html-clipboard-format

// https://www.x.org/releases/X11R7.7/doc/libXext/dbelib.html
// https://www.x.org/releases/X11R7.6/doc/libXext/synclib.html


// on Mac with X11: -L-L/usr/X11/lib 

/+

* I might need to set modal hints too _NET_WM_STATE_MODAL and make sure that TRANSIENT_FOR legit works

	Progress bar in taskbar
		- i can probably just set a property on the window...
		  it sets that prop to an integer 0 .. 100. Taskbar
		  deletes it or window deletes it when it is handled.
		- prolly display it as a nice little line at the bottom.


from gtk:

#define PROGRESS_HINT  "_NET_WM_XAPP_PROGRESS"
#define PROGRESS_PULSE_HINT  "_NET_WM_XAPP_PROGRESS_PULSE"

>+  if (cardinal > 0)
>+  {
>+    XChangeProperty (GDK_DISPLAY_XDISPLAY (display),
>+                     xid,
>+                     gdk_x11_get_xatom_by_name_for_display (display, atom_name),
>+                     XA_CARDINAL, 32,
>+                     PropModeReplace,
>+                     (guchar *) &cardinal, 1);
>+  }
>+  else
>+  {
>+    XDeleteProperty (GDK_DISPLAY_XDISPLAY (display),
>+                     xid,
>+                     gdk_x11_get_xatom_by_name_for_display (display, atom_name));
>+  }

from Windows:

see: https://docs.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-itaskbarlist3

interface
CoCreateInstance( CLSID_TaskbarList, nullptr, CLSCTX_ALL, __uuidof(ITaskbarList3), (LPVOID*)&m_pTL3 ); 
auto msg = RegisterWindowMessage(TEXT(“TaskbarButtonCreated”)); 
listen for msg, return TRUE
interface->SetProgressState(hwnd, TBPF_NORMAL); 
interface->SetProgressValue(hwnd, 40, 100); 


	My new notification system.
		- use a unix socket? or a x property? or a udp port?
		- could of course also get on the dbus train but ugh.
		- it could also reply with the info as a string for easy remote examination.

+/

/*
	Event Loop would be nices:

	* add on idle - runs when nothing else happens
		* which can specify how long to yield for
	* send messages without a recipient window
	* setTimeout
	* setInterval
*/

/*
	Classic games I want to add:
		* my tetris clone
		* pac man
*/

/*
	Text layout needs a lot of work. Plain drawText is useful but too
	limited. It will need some kind of text context thing which it will
	update and you can pass it on and get more details out of it.

	It will need a bounding box, a current cursor location that is updated
	as drawing continues, and various changable facts (which can also be
	changed on the painter i guess) like font, color, size, background,
	etc.

	We can also fetch the caret location from it somehow.

	Should prolly be an overload of drawText

		blink taskbar / demand attention cross platform. FlashWindow and demandAttention

		WS_EX_NOACTIVATE
		WS_CHILD - owner and owned vs parent and child. Does X have something similar?
		full screen windows. Can just set the atom on X. Windows will be harder.

		moving windows. resizing windows.

		hide cursor, capture cursor, change cursor.

	REMEMBER: simpledisplay does NOT have to do everything! It just needs to make
	sure the pieces are there to do its job easily and make other jobs possible.
*/

/++
	simpledisplay.d (often abbreviated to "sdpy") provides basic cross-platform GUI-related functionality,
	including creating windows, drawing on them, working with the clipboard,
	timers, OpenGL, and more. However, it does NOT provide high level GUI
	widgets. See my minigui.d, an extension to this module, for that
	functionality.

	simpledisplay provides cross-platform wrapping for Windows and Linux
	(and perhaps other OSes that use X11), but also does not prevent you
	from using the underlying facilities if you need them. It has a goal
	of working efficiently over a remote X link (at least as far as Xlib
	reasonably allows.)

	simpledisplay depends on [arsd.color|color.d], which should be available from the
	same place where you got this file. Other than that, however, it has
	very few dependencies and ones that don't come with the OS and/or the
	compiler are all opt-in.

	simpledisplay.d's home base is on my arsd repo on Github. The file is:
	https://github.com/adamdruppe/arsd/blob/master/simpledisplay.d

	simpledisplay is basically stable. I plan to refactor the internals,
	and may add new features and fix bugs, but It do not expect to
	significantly change the API. It has been stable a few years already now.

	Installation_instructions:

	`simpledisplay.d` does not have any dependencies outside the
	operating system and `color.d`, so it should just work most the
	time, but there are a few caveats on some systems:

	Please note when compiling on Win64, you need to explicitly list
	`-Lgdi32.lib -Luser32.lib` on the build command. If you want the Windows
	subsystem too, use `-L/subsystem:windows -L/entry:mainCRTStartup`.

	If using ldc instead of dmd, use `-L/entry:wmainCRTStartup` instead of `mainCRTStartup`;
	note the "w".

	On Win32, you can pass `-L/subsystem:windows` if you don't want a
	console to be automatically allocated.

	On Mac, when compiling with X11, you need XQuartz and -L-L/usr/X11R6/lib passed to dmd. If using the Cocoa implementation on Mac, you need to pass `-L-framework -LCocoa` to dmd. For OpenGL, add `-L-framework -LOpenGL` to the build command.

	On Ubuntu, you might need to install X11 development libraries to
	successfully link.

	$(CONSOLE
		$ sudo apt-get install libglc-dev
		$ sudo apt-get install libx11-dev
	)


	Jump_list:

	Don't worry, you don't have to read this whole documentation file!

	Check out the [#event-example] and [#Pong-example] to get started quickly.

	The main classes you may want to create are [SimpleWindow], [Timer],
	[Image], and [Sprite].

	The main functions you'll want are [setClipboardText] and [getClipboardText].

	There are also platform-specific functions available such as [XDisplayConnection]
	and [GetAtom] for X11, among others.

	See the examples and topics list below to learn more.

	$(WARNING
		There should only be one GUI thread per application,
		and all windows should be created in it and your
		event loop should run there.

		To do otherwise is undefined behavior and has no
		cross platform guarantees.
	)

	$(H2 About this documentation)

	The goal here is to give some complete programs as overview examples first, then a look at each major feature with working examples first, then, finally, the inline class and method list will follow.

	Scan for headers for a topic - $(B they will visually stand out) - you're interested in to get started quickly and feel free to copy and paste any example as a starting point for your program. I encourage you to learn the library by experimenting with the examples!

	All examples are provided with no copyright restrictions whatsoever. You do not need to credit me or carry any kind of notice with the source if you copy and paste from them.

	To get started, download `simpledisplay.d` and `color.d` to a working directory. Copy an example info a file called `example.d` and compile using the command given at the top of each example.

	If you need help, email me: destructionator@gmail.com or IRC us, #d on Freenode (I am destructionator or adam_d_ruppe there). If you learn something that isn't documented, I appreciate pull requests on github to this file.

	At points, I will talk about implementation details in the documentation. These are sometimes
	subject to change, but nevertheless useful to understand what is really going on. You can learn
	more about some of the referenced things by searching the web for info about using them from C.
	You can always look at the source of simpledisplay.d too for the most authoritative source on
	its specific implementation. If you disagree with how I did something, please contact me so we
	can discuss it!

	$(H2 Using with fibers)

	simpledisplay can be used with [core.thread.Fiber], but be warned many of the functions can use a significant amount of stack space. I recommend at least 64 KB stack for each fiber (just set through the second argument to Fiber's constructor).

	$(H2 Topics)

	$(H3 $(ID topic-windows) Windows)
		The [SimpleWindow] class is simpledisplay's flagship feature. It represents a single
		window on the user's screen.

		You may create multiple windows, if the underlying platform supports it. You may check
		`static if(multipleWindowsSupported)` at compile time, or catch exceptions thrown by
		SimpleWindow's constructor at runtime to handle those cases.

		A single running event loop will handle as many windows as needed.

	$(H3 $(ID topic-event-loops) Event loops)
		The simpledisplay event loop is designed to handle common cases easily while being extensible for more advanced cases, or replaceable by other libraries.

		The most common scenario is creating a window, then calling [SimpleWindow.eventLoop|window.eventLoop] when setup is complete. You can pass several handlers to the `eventLoop` method right there:

		---
		// dmd example.d simpledisplay.d color.d
		import arsd.simpledisplay;
		void main() {
			auto window = new SimpleWindow(200, 200);
			window.eventLoop(0,
			  delegate (dchar) { /* got a character key press */ }
			);
		}
		---

		$(TIP If you get a compile error saying "I can't use this event handler", the most common thing in my experience is passing a function instead of a delegate. The simple solution is to use the `delegate` keyword, like I did in the example above.)

		On Linux, the event loop is implemented with the `epoll` system call for efficiency an extensibility to other files. On Windows, it runs a traditional `GetMessage` + `DispatchMessage` loop, with a call to `SleepEx` in each iteration to allow the thread to enter an alertable wait state regularly, primarily so Overlapped I/O callbacks will get a chance to run.

		On Linux, simpledisplay also supports my (deprecated) [arsd.eventloop] module. Compile your program, including the eventloop.d file, with the `-version=with_eventloop` switch.

		It should be possible to integrate simpledisplay with vibe.d as well, though I haven't tried.

		You can also run the event loop independently of a window, with [EventLoop.run|EventLoop.get.run], though since it will automatically terminate when there are no open windows, you will want to have one anyway.

	$(H3 $(ID topic-notification-areas) Notification area (aka systray) icons)
		Notification area icons are currently implemented on X11 and Windows. On X11, it defaults to using `libnotify` to show bubbles, if available, and will do a custom bubble window if not. You can `version=without_libnotify` to avoid this run-time dependency, if you like.

		See the [NotificationAreaIcon] class.

	$(H3 $(ID topic-input-handling) Input handling)
		There are event handlers for low-level keyboard and mouse events, and higher level handlers for character events.

		See [SimpleWindow.handleCharEvent], [SimpleWindow.handleKeyEvent], [SimpleWindow.handleMouseEvent].

	$(H3 $(ID topic-2d-drawing) 2d Drawing)
		To draw on your window, use the [SimpleWindow.draw] method. It returns a [ScreenPainter] structure with drawing methods.

		Important: `ScreenPainter` double-buffers and will not actually update the window until its destructor is run. Always ensure the painter instance goes out-of-scope before proceeding. You can do this by calling it inside an event handler, a timer callback, or an small scope inside main. For example:

		---
		// dmd example.d simpledisplay.d color.d
		import arsd.simpledisplay;
		void main() {
			auto window = new SimpleWindow(200, 200);
			{ // introduce sub-scope
				auto painter = window.draw(); // begin drawing
				/* draw here */
				painter.outlineColor = Color.red;
				painter.fillColor = Color.black;
				painter.drawRectangle(Point(0, 0), 200, 200);
			} // end scope, calling `painter`'s destructor, drawing to the screen.
			window.eventLoop(0); // handle events
		}
		---

		Painting is done based on two color properties, a pen and a brush.

		At this time, the 2d drawing does not support alpha blending, except for the [Sprite] class. If you need that, use a 2d OpenGL context instead.

		FIXME Add example of 2d opengl drawing here.
	$(H3 $(ID topic-3d-drawing) 3d Drawing (or 2d with OpenGL))
		simpledisplay can create OpenGL contexts on your window. It works quite differently than 2d drawing.

		Note that it is still possible to draw 2d on top of an OpenGL window, using the `draw` method, though I don't recommend it.

		To start, you create a [SimpleWindow] with OpenGL enabled by passing the argument [OpenGlOptions.yes] to the constructor.

		Next, you set [SimpleWindow.redrawOpenGlScene|window.redrawOpenGlScene] to a delegate which draws your frame.

		To force a redraw of the scene, call [SimpleWindow.redrawOpenGlSceneNow|window.redrawOpenGlSceneNow()] or to queue a redraw after processing the next batch of pending events, use [SimpleWindow.redrawOpenGlSceneSoon|window.redrawOpenGlSceneSoon].

		simpledisplay supports both old-style `glBegin` and newer-style shader-based code all through its built-in bindings. See the next section of the docs to see a shader-based program.

		This example program will draw a rectangle on your window using old-style OpenGL with a pulsating color:

		---
		import arsd.simpledisplay;

		void main() {
			auto window = new SimpleWindow(800, 600, "opengl 1", OpenGlOptions.yes, Resizability.allowResizing);

			float otherColor = 0.0;
			float colorDelta = 0.05;

			window.redrawOpenGlScene = delegate() {
				glLoadIdentity();
				glBegin(GL_QUADS);

				glColor3f(1.0, otherColor, 0);
				glVertex3f(-0.8, -0.8, 0);

				glColor3f(1.0, otherColor, 1.0);
				glVertex3f(0.8, -0.8, 0);

				glColor3f(0, 1.0, otherColor);
				glVertex3f(0.8, 0.8, 0);

				glColor3f(otherColor, 0, 1.0);
				glVertex3f(-0.8, 0.8, 0);

				glEnd();
			};

			window.eventLoop(50, () {
				otherColor += colorDelta;
				if(otherColor > 1.0) {
					otherColor = 1.0;
					colorDelta = -0.05;
				}
				if(otherColor < 0) {
					otherColor = 0;
					colorDelta = 0.05;
				}
				// at the end of the timer, we have to request a redraw
				// or we won't see the changes.
				window.redrawOpenGlSceneSoon();
			});
		}
		---

		My [arsd.game] module has some helpers for using old-style opengl to make 2D windows too. See: [arsd.game.create2dWindow].
	$(H3 $(ID topic-modern-opengl) Modern OpenGL)
		simpledisplay's opengl support, by default, is for "legacy" opengl. To use "modern" functions, you must opt-into them with a little more setup. But the library provides helpers for this too.

		This example program shows how you can set up a shader to draw a rectangle:

		---
		module opengl3test;
		import arsd.simpledisplay;

		// based on https://learnopengl.com/Getting-started/Hello-Triangle

		void main() {
			// First thing we do, before creating the window, is declare what version we want.
			setOpenGLContextVersion(3, 3);
			// turning off legacy compat is required to use version 3.3 and newer
			openGLContextCompatible = false;

			uint VAO;
			OpenGlShader shader;

			// then we can create the window.
			auto window = new SimpleWindow(800, 600, "opengl 3", OpenGlOptions.yes, Resizability.allowResizing);

			// additional setup needs to be done when it is visible, simpledisplay offers a property
			// for exactly that:
			window.visibleForTheFirstTime = delegate() {
				// now with the window loaded, we can start loading the modern opengl functions.

				// you MUST set the context first.
				window.setAsCurrentOpenGlContext;
				// then load the remainder of the library
				gl3.loadDynamicLibrary();

				// now you can create the shaders, etc.
				shader = new OpenGlShader(
					OpenGlShader.Source(GL_VERTEX_SHADER, `
						#version 330 core
						layout (location = 0) in vec3 aPos;
						void main() {
							gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
						}
					`),
					OpenGlShader.Source(GL_FRAGMENT_SHADER, `
						#version 330 core
						out vec4 FragColor;
						uniform vec4 mycolor;
						void main() {
							FragColor = mycolor;
						}
					`),
				);

				// and do whatever other setup you want.

				float[] vertices = [
					0.5f,  0.5f, 0.0f,  // top right
					0.5f, -0.5f, 0.0f,  // bottom right
					-0.5f, -0.5f, 0.0f,  // bottom left
					-0.5f,  0.5f, 0.0f   // top left 
				];
				uint[] indices = [  // note that we start from 0!
					0, 1, 3,  // first Triangle
					1, 2, 3   // second Triangle
				];
				uint VBO, EBO;
				glGenVertexArrays(1, &VAO);
				// bind the Vertex Array Object first, then bind and set vertex buffer(s), and then configure vertex attributes(s).
				glBindVertexArray(VAO);

				glGenBuffers(1, &VBO);
				glGenBuffers(1, &EBO);

				glBindBuffer(GL_ARRAY_BUFFER, VBO);
				glBufferDataSlice(GL_ARRAY_BUFFER, vertices, GL_STATIC_DRAW);

				glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO);
				glBufferDataSlice(GL_ELEMENT_ARRAY_BUFFER, indices, GL_STATIC_DRAW);

				glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * float.sizeof, null);
				glEnableVertexAttribArray(0);

				// the library will set the initial viewport and trigger our first draw,
				// so these next two lines are NOT needed. they are just here as comments
				// to show what would happen next.

				// glViewport(0, 0, window.width, window.height);
				// window.redrawOpenGlSceneNow();
			};

			// this delegate is called any time the window needs to be redrawn or if you call `window.redrawOpenGlSceneNow;`
			// it is our render method.
			window.redrawOpenGlScene = delegate() {
				glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
				glClear(GL_COLOR_BUFFER_BIT);

				glUseProgram(shader.shaderProgram);

				// the shader helper class has methods to set uniforms too
				shader.uniforms.mycolor.opAssign(1.0, 1.0, 0, 1.0);

				glBindVertexArray(VAO);
				glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, null);
			};

			window.eventLoop(0);
		}
		---

	This program only draws the image once because that's all that is necessary, since it is static. If you want to do animation, you might set a pulse timer (which would be a fixed max fps, not necessarily consistent) or use a render loop in a separate thread.


	$(H3 $(ID topic-images) Displaying images)
		You can also load PNG images using [arsd.png].

		---
		// dmd example.d simpledisplay.d color.d png.d
		import arsd.simpledisplay;
		import arsd.png;

		void main() {
			auto image = Image.fromMemoryImage(readPng("image.png"));
			displayImage(image);
		}
		---

		Compile with `dmd example.d simpledisplay.d png.d`.

		If you find an image file which is a valid png that [arsd.png] fails to load, please let me know. In the mean time of fixing the bug, you can probably convert the file into an easier-to-load format. Be sure to turn OFF png interlacing, as that isn't supported. Other things to try would be making the image smaller, or trying 24 bit truecolor mode with an alpha channel.

	$(H3 $(ID topic-sprites) Sprites)
		The [Sprite] class is used to make images on the display server for fast blitting to screen. This is especially important to use to support fast drawing of repeated images on a remote X11 link.

		[Sprite] is also the only facility that currently supports alpha blending without using OpenGL .

	$(H3 $(ID topic-clipboard) Clipboard)
		The free functions [getClipboardText] and [setClipboardText] consist of simpledisplay's cross-platform clipboard support at this time.

		It also has helpers for handling X-specific events.

	$(H3 $(ID topic-dnd) Drag and Drop)
		See [enableDragAndDrop] and [draggable].

	$(H3 $(ID topic-timers) Timers)
		There are two timers in simpledisplay: one is the pulse timeout you can set on the call to `window.eventLoop`, and the other is a customizable class, [Timer].

		The pulse timeout is used by setting a non-zero interval as the first argument to `eventLoop` function and adding a zero-argument delegate to handle the pulse.

		---
			import arsd.simpledisplay;

			void main() {
				auto window = new SimpleWindow(400, 400);
				// every 100 ms, it will draw a random line
				// on the window.
				window.eventLoop(100, {
					auto painter = window.draw();

					import std.random;
					// random color
					painter.outlineColor = Color(uniform(0, 256), uniform(0, 256), uniform(0, 256));
					// random line
					painter.drawLine(
						Point(uniform(0, window.width), uniform(0, window.height)),
						Point(uniform(0, window.width), uniform(0, window.height)));

				});
			}
		---

		The `Timer` class works similarly, but is created separately from the event loop. (It still fires through the event loop, though.) You may make as many instances of `Timer` as you wish.

		The pulse timer and instances of the [Timer] class may be combined at will.

		---
			import arsd.simpledisplay;

			void main() {
				auto window = new SimpleWindow(400, 400);
				auto timer = new Timer(1000, delegate {
					auto painter = window.draw();
					painter.clear();
				});

				window.eventLoop(0);
			}
		---

		Timers are currently only implemented on Windows, using `SetTimer` and Linux, using `timerfd_create`. These deliver timeout messages through your application event loop.

	$(H3 $(ID topic-os-helpers) OS-specific helpers)
		simpledisplay carries a lot of code to help implement itself without extra dependencies, and much of this code is available for you too, so you may extend the functionality yourself.

		See also: `xwindows.d` from my github.

	$(H3 $(ID topic-os-extension) Extending with OS-specific functionality)
		`handleNativeEvent` and `handleNativeGlobalEvent`.

	$(H3 $(ID topic-integration) Integration with other libraries)
		Integration with a third-party event loop is possible.

		On Linux, you might want to support both terminal input and GUI input. You can do this by using simpledisplay together with eventloop.d and terminal.d.

	$(H3 $(ID topic-guis) GUI widgets)
		simpledisplay does not provide GUI widgets such as text areas, buttons, checkboxes, etc. It only gives basic windows, the ability to draw on it, receive input from it, and access native information for extension. You may write your own gui widgets with these, but you don't have to because I already did for you!

		Download `minigui.d` from my github repository and add it to your project. minigui builds these things on top of simpledisplay and offers its own Window class (and subclasses) to use that wrap SimpleWindow, adding a new event and drawing model that is hookable by subwidgets, represented by their own classes.

		Migrating to minigui from simpledisplay is often easy though, because they both use the same ScreenPainter API, and the same simpledisplay events are available, if you want them. (Though you may like using the minigui model, especially if you are familiar with writing web apps in the browser with Javascript.)

		minigui still needs a lot of work to be finished at this time, but it already offers a number of useful classes.

	$(H2 Platform-specific tips and tricks)

	Windows_tips:

	You can add icons or manifest files to your exe using a resource file.

	To create a Windows .ico file, use the gimp or something. I'll write a helper
	program later.

	Create `yourapp.rc`:

	```rc
		1 ICON filename.ico
		CREATEPROCESS_MANIFEST_RESOURCE_ID RT_MANIFEST "YourApp.exe.manifest"
	```

	And `yourapp.exe.manifest`:

	```xml
		<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
		<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
		<assemblyIdentity
		    version="1.0.0.0"
		    processorArchitecture="*"
		    name="CompanyName.ProductName.YourApplication"
		    type="win32"
		/>
		<description>Your application description here.</description>
		<dependency>
		    <dependentAssembly>
			<assemblyIdentity
			    type="win32"
			    name="Microsoft.Windows.Common-Controls"
			    version="6.0.0.0"
			    processorArchitecture="*"
			    publicKeyToken="6595b64144ccf1df"
			    language="*"
			/>
		    </dependentAssembly>
		</dependency>
		</assembly>
	```

	$(H2 Tips)

	$(H3 Name conflicts)

	simpledisplay has a lot of symbols and more are liable to be added without notice, since it contains its own bindings as needed to accomplish its goals. Some of these may conflict with other bindings you use. If so, you can use a static import in D, possibly combined with a selective import:

	---
	static import sdpy = arsd.simpledisplay;
	import arsd.simpledisplay : SimpleWindow;

	void main() {
		auto window = new SimpleWindow();
		sdpy.EventLoop.get.run();
	}
	---

	$(H2 $(ID developer-notes) Developer notes)

	I don't have a Mac, so that code isn't maintained. I would like to have a Cocoa
	implementation though.

	The NativeSimpleWindowImplementation and NativeScreenPainterImplementation both
	suck. If I was rewriting it, I wouldn't do it that way again.

	This file must not have any more required dependencies. If you need bindings, add
	them right to this file. Once it gets into druntime and is there for a while, remove
	bindings from here to avoid conflicts (or put them in an appropriate version block
	so it continues to just work on old dmd), but wait a couple releases before making the
	transition so this module remains usable with older versions of dmd.

	You may have optional dependencies if needed by putting them in version blocks or
	template functions. You may also extend the module with other modules with UFCS without
	actually editing this - that is nice to do if you can.

	Try to make functions work the same way across operating systems. I typically make
	it thinly wrap Windows, then emulate that on Linux.

	A goal of this is to keep a gui hello world to less than 250 KB. This means avoiding
	Phobos! So try to avoid it.

	See more comments throughout the source.

	I realize this file is fairly large, but over half that is just bindings at the bottom
	or documentation at the top. Some of the classes are a bit big too, but hopefully easy
	to understand. I suggest you jump around the source by looking for a particular
	declaration you're interested in, like `class SimpleWindow` using your editor's search
	function, then look at one piece at a time.

	Authors: Adam D. Ruppe with the help of others. If you need help, please email me with
	destructionator@gmail.com or find me on IRC. Our channel is #d on Freenode and you can
	ping me, adam_d_ruppe, and I'll usually see it if I'm around.

	I live in the eastern United States, so I will most likely not be around at night in
	that US east timezone.

	License: Copyright Adam D. Ruppe, 2011-2021. Released under the Boost Software License.

	Building documentation: use my adrdox generator, `dub run adrdox`.

	Examples:

	$(DIV $(ID Event-example))
	$(H3 $(ID event-example) Event example)
	This program creates a window and draws events inside them as they
	happen, scrolling the text in the window as needed. Run this program
	and experiment to get a feel for where basic input events take place
	in the library.

	---
	// dmd example.d simpledisplay.d color.d
	import arsd.simpledisplay;
	import std.conv;

	void main() {
		auto window = new SimpleWindow(Size(500, 500), "Event example - simpledisplay.d");

		int y = 0;

		void addLine(string text) {
			auto painter = window.draw();

			if(y + painter.fontHeight >= window.height) {
				painter.scrollArea(Point(0, 0), window.width, window.height, 0, painter.fontHeight);
				y -= painter.fontHeight;
			}

			painter.outlineColor = Color.red;
			painter.fillColor = Color.black;
			painter.drawRectangle(Point(0, y), window.width, painter.fontHeight);

			painter.outlineColor = Color.white;

			painter.drawText(Point(10, y), text);

			y += painter.fontHeight;
		}

		window.eventLoop(1000,
		  () {
			addLine("Timer went off!");
		  },
		  (KeyEvent event) {
			addLine(to!string(event));
		  },
		  (MouseEvent event) {
			addLine(to!string(event));
		  },
		  (dchar ch) {
			addLine(to!string(ch));
		  }
		);
	}
	---

	If you are interested in more game writing with D, check out my gamehelpers.d which builds upon simpledisplay, and its other stand-alone support modules, simpleaudio.d and joystick.d, too.

	$(COMMENT
	This program displays a pie chart. Clicking on a color will increase its share of the pie.

	---

	---
	)


+/
module arsd.simpledisplay;

// FIXME: tetris demo
// FIXME: space invaders demo
// FIXME: asteroids demo

/++ $(ID Pong-example)
	$(H3 Pong)

	This program creates a little Pong-like game. Player one is controlled
	with the keyboard.  Player two is controlled with the mouse. It demos
	the pulse timer, event handling, and some basic drawing.
+/
version(demos)
unittest {
	// dmd example.d simpledisplay.d color.d
	import arsd.simpledisplay;

	enum paddleMovementSpeed = 8;
	enum paddleHeight = 48;

	void main() {
		auto window = new SimpleWindow(600, 400, "Pong game!");

		int playerOnePosition, playerTwoPosition;
		int playerOneMovement, playerTwoMovement;
		int playerOneScore, playerTwoScore;

		int ballX, ballY;
		int ballDx, ballDy;

		void serve() {
			import std.random;

			ballX = window.width / 2;
			ballY = window.height / 2;
			ballDx = uniform(-4, 4) * 3;
			ballDy = uniform(-4, 4) * 3;
			if(ballDx == 0)
				ballDx = uniform(0, 2) == 0 ? 3 : -3;
		}

		serve();

		window.eventLoop(50, // set a 50 ms timer pulls
			// This runs once per timer pulse
			delegate () {
				auto painter = window.draw();

				painter.clear();

				// Update everyone's motion
				playerOnePosition += playerOneMovement;
				playerTwoPosition += playerTwoMovement;

				ballX += ballDx;
				ballY += ballDy;

				// Bounce off the top and bottom edges of the window
				if(ballY + 7 >= window.height)
					ballDy = -ballDy;
				if(ballY - 8 <= 0)
					ballDy = -ballDy;

				// Bounce off the paddle, if it is in position
				if(ballX - 8 <= 16) {
					if(ballY + 7 > playerOnePosition && ballY - 8 < playerOnePosition + paddleHeight) {
						ballDx = -ballDx + 1; // add some speed to keep it interesting
						ballDy += playerOneMovement; // and y movement based on your controls too
						ballX = 24; // move it past the paddle so it doesn't wiggle inside
					} else {
						// Missed it
						playerTwoScore ++;
						serve();
					}
				}

				if(ballX + 7 >= window.width - 16) { // do the same thing but for player 1
					if(ballY + 7 > playerTwoPosition && ballY - 8 < playerTwoPosition + paddleHeight) {
						ballDx = -ballDx - 1;
						ballDy += playerTwoMovement;
						ballX = window.width - 24;
					} else {
						// Missed it
						playerOneScore ++;
						serve();
					}
				}

				// Draw the paddles
				painter.outlineColor = Color.black;
				painter.drawLine(Point(16, playerOnePosition), Point(16, playerOnePosition + paddleHeight));
				painter.drawLine(Point(window.width - 16, playerTwoPosition), Point(window.width - 16, playerTwoPosition + paddleHeight));

				// Draw the ball
				painter.fillColor = Color.red;
				painter.outlineColor = Color.yellow;
				painter.drawEllipse(Point(ballX - 8, ballY - 8), Point(ballX + 7, ballY + 7));

				// Draw the score
				painter.outlineColor = Color.blue;
				import std.conv;
				painter.drawText(Point(64, 4), to!string(playerOneScore));
				painter.drawText(Point(window.width - 64, 4), to!string(playerTwoScore));

			},
			delegate (KeyEvent event) {
				// Player 1's controls are the arrow keys on the keyboard
				if(event.key == Key.Down)
					playerOneMovement = event.pressed ? paddleMovementSpeed : 0;
				if(event.key == Key.Up)
					playerOneMovement = event.pressed ? -paddleMovementSpeed : 0;

			},
			delegate (MouseEvent event) {
				// Player 2's controls are mouse movement while the left button is held down
				if(event.type == MouseEventType.motion && (event.modifierState & ModifierState.leftButtonDown)) {
					if(event.dy > 0)
						playerTwoMovement = paddleMovementSpeed;
					else if(event.dy < 0)
						playerTwoMovement = -paddleMovementSpeed;
				} else {
					playerTwoMovement = 0;
				}
			}
		);
	}
}

/++ $(H3 $(ID example-minesweeper) Minesweeper)

	This minesweeper demo shows how we can implement another classic
	game with simpledisplay and shows some mouse input and basic output
	code.
+/
version(demos)
unittest {
	import arsd.simpledisplay;

	enum GameSquare {
		mine = 0,
		clear,
		m1, m2, m3, m4, m5, m6, m7, m8
	}

	enum UserSquare {
		unknown,
		revealed,
		flagged,
		questioned
	}

	enum GameState {
		inProgress,
		lose,
		win
	}

	GameSquare[] board;
	UserSquare[] userState;
	GameState gameState;
	int boardWidth;
	int boardHeight;

	bool isMine(int x, int y) {
		if(x < 0 || y < 0 || x >= boardWidth || y >= boardHeight)
			return false;
		return board[y * boardWidth + x] == GameSquare.mine;
	}

	GameState reveal(int x, int y) {
		if(board[y * boardWidth + x] == GameSquare.clear) {
			floodFill(userState, boardWidth, boardHeight,
				UserSquare.unknown, UserSquare.revealed,
				x, y,
				(x, y) {
					if(board[y * boardWidth + x] == GameSquare.clear)
						return true;
					else {
						userState[y * boardWidth + x] = UserSquare.revealed;
						return false;
					}
				});
		} else {
			userState[y * boardWidth + x] = UserSquare.revealed;
			if(isMine(x, y))
				return GameState.lose;
		}

		foreach(state; userState) {
			if(state == UserSquare.unknown || state == UserSquare.questioned)
				return GameState.inProgress;
		}

		return GameState.win;
	}

	void initializeBoard(int width, int height, int numberOfMines) {
		boardWidth = width;
		boardHeight = height;
		board.length = width * height;

		userState.length = width * height;
		userState[] = UserSquare.unknown; 

		import std.algorithm, std.random, std.range;

		board[] = GameSquare.clear;

		foreach(minePosition; randomSample(iota(0, board.length), numberOfMines))
			board[minePosition] = GameSquare.mine;

		int x;
		int y;
		foreach(idx, ref square; board) {
			if(square == GameSquare.clear) {
				int danger = 0;
				danger += isMine(x-1, y-1)?1:0;
				danger += isMine(x-1, y)?1:0;
				danger += isMine(x-1, y+1)?1:0;
				danger += isMine(x, y-1)?1:0;
				danger += isMine(x, y+1)?1:0;
				danger += isMine(x+1, y-1)?1:0;
				danger += isMine(x+1, y)?1:0;
				danger += isMine(x+1, y+1)?1:0;

				square = cast(GameSquare) (danger + 1);
			}

			x++;
			if(x == width) {
				x = 0;
				y++;
			}
		}
	}

	void redraw(SimpleWindow window) {
		import std.conv;

		auto painter = window.draw();

		painter.clear();

		final switch(gameState) with(GameState) {
			case inProgress:
				break;
			case win:
				painter.fillColor = Color.green;
				painter.drawRectangle(Point(0, 0), window.width, window.height);
				return;
			case lose:
				painter.fillColor = Color.red;
				painter.drawRectangle(Point(0, 0), window.width, window.height);
				return;
		}

		int x = 0;
		int y = 0;

		foreach(idx, square; board) {
			auto state = userState[idx];

			final switch(state) with(UserSquare) {
				case unknown:
					painter.outlineColor = Color.black;
					painter.fillColor = Color(128,128,128);

					painter.drawRectangle(
						Point(x * 20, y * 20),
						20, 20
					);
				break;
				case revealed:
					if(square == GameSquare.clear) {
						painter.outlineColor = Color.white;
						painter.fillColor = Color.white;

						painter.drawRectangle(
							Point(x * 20, y * 20),
							20, 20
						);
					} else {
						painter.outlineColor = Color.black;
						painter.fillColor = Color.white;

						painter.drawText(
							Point(x * 20, y * 20),
							to!string(square)[1..2],
							Point(x * 20 + 20, y * 20 + 20),
							TextAlignment.Center | TextAlignment.VerticalCenter);
					}
				break;
				case flagged:
					painter.outlineColor = Color.black;
					painter.fillColor = Color.red;
					painter.drawRectangle(
						Point(x * 20, y * 20),
						20, 20
					);
				break;
				case questioned:
					painter.outlineColor = Color.black;
					painter.fillColor = Color.yellow;
					painter.drawRectangle(
						Point(x * 20, y * 20),
						20, 20
					);
				break;
			}

			x++;
			if(x == boardWidth) {
				x = 0;
				y++;
			}
		}

	}

	void main() {
		auto window = new SimpleWindow(200, 200);

		initializeBoard(10, 10, 10);

		redraw(window);
		window.eventLoop(0,
			delegate (MouseEvent me) {
				if(me.type != MouseEventType.buttonPressed)
					return;
				auto x = me.x / 20;
				auto y = me.y / 20;
				if(x >= 0 && x < boardWidth && y >= 0 && y < boardHeight) {
					if(me.button == MouseButton.left) {
						gameState = reveal(x, y);
					} else {
						userState[y*boardWidth+x] = UserSquare.flagged;
					}
					redraw(window);
				}
			}
		);
	}
}

/*
version(OSX) {
	version=without_opengl;
	version=allow_unimplemented_features;
	version=OSXCocoa;
	pragma(linkerDirective, "-framework Cocoa");
}
*/

version(without_opengl) {
	enum SdpyIsUsingIVGLBinds = false;
} else /*version(Posix)*/ {
	static if (__traits(compiles, (){import iv.glbinds;})) {
		enum SdpyIsUsingIVGLBinds = true;
		public import iv.glbinds;
		//pragma(msg, "SDPY: using iv.glbinds");
	} else {
		enum SdpyIsUsingIVGLBinds = false;
	}
//} else {
//	enum SdpyIsUsingIVGLBinds = false;
}


version(Windows) {
	//import core.sys.windows.windows;
	import core.sys.windows.winnls;
	import core.sys.windows.windef;
	import core.sys.windows.basetyps;
	import core.sys.windows.winbase;
	import core.sys.windows.winuser;
	import core.sys.windows.shellapi;
	import core.sys.windows.wingdi;
	static import gdi = core.sys.windows.wingdi; // so i

	pragma(lib, "gdi32");
	pragma(lib, "user32");

	// for AlphaBlend... a breaking change....
	version(CRuntime_DigitalMars) { } else
		pragma(lib, "msimg32");
} else version (linux) {
	//k8: this is hack for rdmd. sorry.
	static import core.sys.linux.epoll;
	static import core.sys.linux.timerfd;
}


// FIXME: icons on Windows don't look quite right, I think the transparency mask is off.

// http://wiki.dlang.org/Simpledisplay.d

// see : http://www.sbin.org/doc/Xlib/chapt_09.html section on Keyboard Preferences re: scroll lock led

// Cool stuff: I want right alt and scroll lock to do different stuff for personal use. maybe even right ctrl
// but can i control the scroll lock led


// Note: if you are using Image on X, you might want to do:
/*
	static if(UsingSimpledisplayX11) {
		if(!Image.impl.xshmAvailable) {
			// the images will use the slower XPutImage, you might
			// want to consider an alternative method to get better speed
		}
	}

	If the shared memory extension is available though, simpledisplay uses it
	for a significant speed boost whenever you draw large Images.
*/

// CHANGE FROM LAST VERSION: the window background is no longer fixed, so you might want to fill the screen with a particular color before drawing.

// WARNING: if you are using with_eventloop, don't forget to call XFlush(XDisplayConnection.get()); before calling loop()!

/*
	Biggest FIXME:
		make sure the key event numbers match between X and Windows OR provide symbolic constants on each system

		clean up opengl contexts when their windows close

		fix resizing the bitmaps/pixmaps
*/

// BTW on Windows:
// -L/SUBSYSTEM:WINDOWS:5.0
// to dmd will make a nice windows binary w/o a console if you want that.

/*
	Stuff to add:

	use multibyte functions everywhere we can

	OpenGL windows
	more event stuff
	extremely basic windows w/ no decoration for tooltips, splash screens, etc.


	resizeEvent
		and make the windows non-resizable by default,
		or perhaps stretched (if I can find something in X like StretchBlt)

	take a screenshot function!

	Pens and brushes?
	Maybe a global event loop?

	Mouse deltas
	Key items
*/

/*
From MSDN:

You can also use the GET_X_LPARAM or GET_Y_LPARAM macro to extract the x- or y-coordinate.

Important  Do not use the LOWORD or HIWORD macros to extract the x- and y- coordinates of the cursor position because these macros return incorrect results on systems with multiple monitors. Systems with multiple monitors can have negative x- and y- coordinates, and LOWORD and HIWORD treat the coordinates as unsigned quantities.

*/

version(linux) {
	version = X11;
	version(without_libnotify) {
		// we cool
	}
	else
		version = libnotify;
}

version(libnotify) {
	pragma(lib, "dl");
	import core.sys.posix.dlfcn;

	void delegate()[int] libnotify_action_delegates;
	int libnotify_action_delegates_count;
	extern(C) static void libnotify_action_callback_sdpy(void* notification, char* action, void* user_data) {
		auto idx = cast(int) user_data;
		if(auto dgptr = idx in libnotify_action_delegates) {
			(*dgptr)();
			libnotify_action_delegates.remove(idx);
		}
	}

	struct C_DynamicLibrary {
		void* handle;
		this(string name) {
			handle = dlopen((name ~ "\0").ptr, RTLD_NOW);
			if(handle is null)
				throw new Exception("dlopen");
		}

		void close() {
			dlclose(handle);
		}

		~this() {
			// close
		}

		// FIXME: this looks up by name every time.... 
		template call(string func, Ret, Args...) {
			extern(C) Ret function(Args) fptr;
			typeof(fptr) call() {
				fptr = cast(typeof(fptr)) dlsym(handle, func);
				return fptr;
			}
		}
	}

	C_DynamicLibrary* libnotify;
}

version(OSX) {
	version(OSXCocoa) {}
	else { version = X11; }
}
	//version = OSXCocoa; // this was written by KennyTM
version(FreeBSD)
	version = X11;
version(Solaris)
	version = X11;

version(X11) {
	version(without_xft) {}
	else version=with_xft;
}

void featureNotImplemented()() {
	version(allow_unimplemented_features)
		throw new NotYetImplementedException();
	else
		static assert(0);
}

// these are so the static asserts don't trigger unless you want to
// add support to it for an OS
version(Windows)
	version = with_timer;
version(linux)
	version = with_timer;

version(with_timer)
	enum bool SimpledisplayTimerAvailable = true;
else
	enum bool SimpledisplayTimerAvailable = false;

/// If you have to get down and dirty with implementation details, this helps figure out if Windows is available you can `static if(UsingSimpledisplayWindows) ...` more reliably than `version()` because `version` is module-local.
version(Windows)
	enum bool UsingSimpledisplayWindows = true;
else
	enum bool UsingSimpledisplayWindows = false;

/// If you have to get down and dirty with implementation details, this helps figure out if X is available you can `static if(UsingSimpledisplayX11) ...` more reliably than `version()` because `version` is module-local.
version(X11)
	enum bool UsingSimpledisplayX11 = true;
else
	enum bool UsingSimpledisplayX11 = false;

/// If you have to get down and dirty with implementation details, this helps figure out if Cocoa is available you can `static if(UsingSimpledisplayCocoa) ...` more reliably than `version()` because `version` is module-local.
version(OSXCocoa)
	enum bool UsingSimpledisplayCocoa = true;
else
	enum bool UsingSimpledisplayCocoa = false;

/// Does this platform support multiple windows? If not, trying to create another will cause it to throw an exception.
version(Windows)
	enum multipleWindowsSupported = true;
else version(X11)
	enum multipleWindowsSupported = true;
else version(OSXCocoa)
	enum multipleWindowsSupported = true;
else
	static assert(0);

version(without_opengl)
	enum bool OpenGlEnabled = false;
else
	enum bool OpenGlEnabled = true;


/++
	After selecting a type from [WindowTypes], you may further customize
	its behavior by setting one or more of these flags.


	The different window types have different meanings of `normal`. If the
	window type already is a good match for what you want to do, you should
	just use [WindowFlags.normal], the default, which will do the right thing
	for your users.

	The window flags will not always be honored by the operating system
	and window managers; they are hints, not commands.
+/
enum WindowFlags : int {
	normal = 0, ///
	skipTaskbar = 1, ///
	alwaysOnTop = 2, ///
	alwaysOnBottom = 4, ///
	cannotBeActivated = 8, ///
	alwaysRequestMouseMotionEvents = 16, /// By default, simpledisplay will attempt to optimize mouse motion event reporting when it detects a remote connection, causing them to only be issued if input is grabbed (see: [SimpleWindow.grabInput]). This means doing hover effects and mouse game control on a remote X connection may not work right. Include this flag to override this optimization and always request the motion events. However btw, if you are doing mouse game control, you probably want to grab input anyway, and hover events are usually expendable! So think before you use this flag.
	extraComposite = 32, /// On windows this will make this a layered windows (not supported for child windows before windows 8) to support transparency and improve animation performance.
	/++
		Sets the window as a short-lived child of its parent, but unlike an ordinary child,
		it is still a top-level window. This should NOT be set separately for most window types.

		A transient window will not keep the application open if its main window closes.

		$(PITFALL This may not be correctly implemented and its behavior is subject to change.)


		From the ICCM:

		$(BLOCKQUOTE
			It is important not to confuse WM_TRANSIENT_FOR with override-redirect. WM_TRANSIENT_FOR should be used in those cases where the pointer is not grabbed while the window is mapped (in other words, if other windows are allowed to be active while the transient is up). If other windows must be prevented from processing input (for example, when implementing pop-up menus), use override-redirect and grab the pointer while the window is mapped. 

			$(CITE https://tronche.com/gui/x/icccm/sec-4.html)
		)

		So if you are using a window type that already describes this like [WindowTypes.dropdownMenu] etc., you should not use this flag.

		History:
			Added February 23, 2021 but not yet stabilized.
	+/
	transient = 64,
	dontAutoShow = 0x1000_0000, /// Don't automatically show window after creation; you will have to call `show()` manually.
}

/++
	When creating a window, you can pass a type to SimpleWindow's constructor,
	then further customize the window by changing `WindowFlags`.


	You should mostly only need [normal], [undecorated], and [eventOnly] for normal
	use. The others are there to build a foundation for a higher level GUI toolkit,
	but are themselves not as high level as you might think from their names.

	This list is based on the EMWH spec for X11.
	http://standards.freedesktop.org/wm-spec/1.4/ar01s05.html#idm139704063786896
+/
enum WindowTypes : int {
	/// An ordinary application window.
	normal,
	/// A generic window without a title bar or border. You can draw on the entire area of the screen it takes up and use it as you wish. Remember that users don't really expect these though, so don't use it where a window of any other type is appropriate.
	undecorated,
	/// A window that doesn't actually display on screen. You can use it for cases where you need a dummy window handle to communicate with or something.
	eventOnly,
	/// A drop down menu, such as from a menu bar
	dropdownMenu,
	/// A popup menu, such as from a right click
	popupMenu,
	/// A popup bubble notification
	notification,
	/*
	menu, /// a tearable menu bar
	splashScreen, /// a loading splash screen for your application
	tooltip, /// A tiny window showing temporary help text or something.
	comboBoxDropdown,
	dialog,
	toolbar
	*/
	/// a child nested inside the parent. You must pass a parent window to the ctor
	nestedChild,
}


private __gshared ushort sdpyOpenGLContextVersion = 0; // default: use legacy call
private __gshared bool sdpyOpenGLContextCompatible = true; // default: allow "deprecated" features
private __gshared char* sdpyWindowClassStr = null;
private __gshared bool sdpyOpenGLContextAllowFallback = false;

/**
	Set OpenGL context version to use. This has no effect on non-OpenGL windows.
	You may want to change context version if you want to use advanced shaders or
	other modern OpenGL techinques. This setting doesn't affect already created
	windows. You may use version 2.1 as your default, which should be supported
	by any box since 2006, so seems to be a reasonable choice.

	Note that by default version is set to `0`, which forces SimpleDisplay to use
	old context creation code without any version specified. This is the safest
	way to init OpenGL, but it may not give you access to advanced features.

	See available OpenGL versions here: https://en.wikipedia.org/wiki/OpenGL
*/
void setOpenGLContextVersion() (ubyte hi, ubyte lo) { sdpyOpenGLContextVersion = cast(ushort)(hi<<8|lo); }

/**
	Set OpenGL context mode. Modern (3.0+) OpenGL versions deprecated old fixed
	pipeline functions, and without "compatible" mode you won't be able to use
	your old non-shader-based code with such contexts. By default SimpleDisplay
	creates compatible context, so you can gradually upgrade your OpenGL code if
	you want to (or leave it as is, as it should "just work").
*/
@property void openGLContextCompatible() (bool v) { sdpyOpenGLContextCompatible = v; }

/**
	Set to `true` to allow creating OpenGL context with lower version than requested
	instead of throwing. If fallback was activated (or legacy OpenGL was requested),
	`openGLContextFallbackActivated()` will return `true`.
	*/
@property void openGLContextAllowFallback() (bool v) { sdpyOpenGLContextAllowFallback = v; }

/**
	After creating OpenGL window, you can check this to see if you got only "legacy" OpenGL context.
	*/
@property bool openGLContextFallbackActivated() () { return (sdpyOpenGLContextVersion == 0); }


/**
	Set window class name for all following `new SimpleWindow()` calls.

	WARNING! For Windows, you should set your class name before creating any
	window, and NEVER change it after that!
*/
void sdpyWindowClass (const(char)[] v) {
	import core.stdc.stdlib : realloc;
	if (v.length == 0) v = "SimpleDisplayWindow";
	sdpyWindowClassStr = cast(char*)realloc(sdpyWindowClassStr, v.length+1);
	if (sdpyWindowClassStr is null) return; // oops
	sdpyWindowClassStr[0..v.length+1] = 0;
	sdpyWindowClassStr[0..v.length] = v[];
}

/**
	Get current window class name.
*/
string sdpyWindowClass () {
	if (sdpyWindowClassStr is null) return null;
	foreach (immutable idx; 0..size_t.max-1) {
		if (sdpyWindowClassStr[idx] == 0) return sdpyWindowClassStr[0..idx].idup;
	}
	return null;
}

/++
	Returns the DPI of the default monitor. [0] is width, [1] is height (they are usually the same though). You may wish to round the numbers off.
+/
float[2] getDpi() {
	float[2] dpi;
	version(Windows) {
		HDC screen = GetDC(null);
		dpi[0] = GetDeviceCaps(screen, LOGPIXELSX);
		dpi[1] = GetDeviceCaps(screen, LOGPIXELSY);
	} else version(X11) {
		auto display = XDisplayConnection.get;
		auto screen = DefaultScreen(display);

		void fallback() {
			// 25.4 millimeters in an inch...
			dpi[0] = cast(float) DisplayWidth(display, screen) / DisplayWidthMM(display, screen) * 25.4;
			dpi[1] = cast(float) DisplayHeight(display, screen) / DisplayHeightMM(display, screen) * 25.4;
		}

		char* resourceString = XResourceManagerString(display);
		XrmInitialize();

		auto db = XrmGetStringDatabase(resourceString);

		if (resourceString) {
			XrmValue value;
			char* type;
			if (XrmGetResource(db, "Xft.dpi", "String", &type, &value) == true) {
				if (value.addr) {
					import core.stdc.stdlib;
					dpi[0] = atof(cast(char*) value.addr);
					dpi[1] = dpi[0];
				} else {
					fallback();
				}
			} else {
				fallback();
			}
		} else {
			fallback();
		}
	}

	return dpi;
}

/++
	Implementation used by [SimpleWindow.takeScreenshot].

	Params:
		handle = the native window handle. If `NativeWindowHandle.init`, it will attempt to get the whole screen.
		width = the width of the image you wish to capture. If 0, it will attempt to capture the full width of the target.
		height = the height of the image you wish to capture. If 0, it will attempt to capture the full height of the target.
		x = the x-offset of the image to capture, from the left.
		y = the y-offset of the image to capture, from the top.

	History:
		Added on March 14, 2021

		Documented public on September 23, 2021 with full support for null params (dub 10.3)
		
+/
TrueColorImage trueColorImageFromNativeHandle(NativeWindowHandle handle, int width = 0, int height = 0, int x = 0, int y = 0) {
	TrueColorImage got;
	version(X11) {
		auto display = XDisplayConnection.get;
		if(handle == 0)
			handle = RootWindow(display, DefaultScreen(display));

		if(width == 0 || height == 0) {
			Window root;
			int xpos, ypos;
			uint widthret, heightret, borderret, depthret;
			XGetGeometry(display, handle, &root, &xpos, &ypos, &widthret, &heightret, &borderret, &depthret);

			if(width == 0)
				width = widthret;
			if(height == 0)
				height = heightret;
		}

		auto image = XGetImage(display, handle, x, y, width, height, (cast(c_ulong) ~0) /*AllPlanes*/, ImageFormat.ZPixmap);

		// https://github.com/adamdruppe/arsd/issues/98

		auto i = new Image(image);
		got = i.toTrueColorImage();

		XDestroyImage(image);
	} else version(Windows) {
		auto hdc = GetDC(handle);
		scope(exit) ReleaseDC(handle, hdc);

		if(width == 0 || height == 0) {
			BITMAP bmHeader;
			auto bm  = GetCurrentObject(hdc, OBJ_BITMAP);
			GetObject(bm, BITMAP.sizeof, &bmHeader);
			if(width == 0)
				width = bmHeader.bmWidth;
			if(height == 0)
				height = bmHeader.bmHeight;
		}

		auto i = new Image(width, height);
		HDC hdcMem = CreateCompatibleDC(hdc);
		HBITMAP hbmOld = SelectObject(hdcMem, i.handle);
		BitBlt(hdcMem, x, y, width, height, hdc, 0, 0, SRCCOPY);
		SelectObject(hdcMem, hbmOld);
		DeleteDC(hdcMem);

		got = i.toTrueColorImage();
	} else featureNotImplemented();

	return got;
}

/++
	The flagship window class.


	SimpleWindow tries to make ordinary windows very easy to create and use without locking you
	out of more advanced or complex features of the underlying windowing system.

	For many applications, you can simply call `new SimpleWindow(some_width, some_height, "some title")`
	and get a suitable window to work with.

	From there, you can opt into additional features, like custom resizability and OpenGL support
	with the next two constructor arguments. Or, if you need even more, you can set a window type
	and customization flags with the final two constructor arguments.

	If none of that works for you, you can also create a window using native function calls, then
	wrap the window in a SimpleWindow instance by calling `new SimpleWindow(native_handle)`. Remember,
	though, if you do this, managing the window is still your own responsibility! Notably, you
	will need to destroy it yourself.
+/
class SimpleWindow : CapableOfHandlingNativeEvent, CapableOfBeingDrawnUpon {

	/++
		Copies the window's current state into a [TrueColorImage].

		Be warned: this can be a very slow operation

		History:
			Actually implemented on March 14, 2021
	+/
	TrueColorImage takeScreenshot() {
		version(Windows)
			return trueColorImageFromNativeHandle(impl.hwnd, width, height);
		else version(OSXCocoa)
			throw new NotYetImplementedException();
		else
			return trueColorImageFromNativeHandle(impl.window, width, height);
	}

	version(X11) {
		void recreateAfterDisconnect() {
			if(!stateDiscarded) return;

			if(_parent !is null && _parent.stateDiscarded)
				_parent.recreateAfterDisconnect();

			bool wasHidden = hidden;

			activeScreenPainter = null; // should already be done but just to confirm

			impl.createWindow(_width, _height, _title, openglMode, _parent);

			if(auto dh = dropHandler) {
				dropHandler = null;
				enableDragAndDrop(this, dh);
			}

			if(recreateAdditionalConnectionState)
				recreateAdditionalConnectionState();

			hidden = wasHidden;
			stateDiscarded = false;
		}

		bool stateDiscarded;
		void discardConnectionState() {
			if(XDisplayConnection.display)
				impl.dispose(); // if display is already null, it is hopeless to try to destroy stuff on it anyway
			if(discardAdditionalConnectionState)
				discardAdditionalConnectionState();
			stateDiscarded = true;
		}

		void delegate() discardAdditionalConnectionState;
		void delegate() recreateAdditionalConnectionState;

	}

	private DropHandler dropHandler;

	SimpleWindow _parent;
	bool beingOpenKeepsAppOpen = true;
	/++
		This creates a window with the given options. The window will be visible and able to receive input as soon as you start your event loop. You may draw on it immediately after creating the window, without needing to wait for the event loop to start if you want.

		The constructor tries to have sane default arguments, so for many cases, you only need to provide a few of them.

		Params:

		width = the width of the window's client area, in pixels
		height = the height of the window's client area, in pixels
		title = the title of the window (seen in the title bar, taskbar, etc.). You can change it after construction with the [SimpleWindow.title] property.
		opengl = [OpenGlOptions] are yes and no. If yes, it creates an OpenGL context on the window.
		resizable = [Resizability] has three options:
			$(P `allowResizing`, which allows the window to be resized by the user. The `windowResized` delegate will be called when the size is changed.)
			$(P `fixedSize` will not allow the user to resize the window.)
			$(P `automaticallyScaleIfPossible` will allow the user to resize, but will still present the original size to the API user. The contents you draw will be scaled to the size the user chose. If this scaling is not efficient, the window will be fixed size. The `windowResized` event handler will never be called. This is the default.)
		windowType = The type of window you want to make.
		customizationFlags = A way to make a window without a border, always on top, skip taskbar, and more. Do not use this if one of the pre-defined [WindowTypes], given in the `windowType` argument, is a good match for what you need.
		parent = the parent window, if applicable. This makes the child window nested inside the parent unless you set [WindowFlags.transient], which makes it a top-level window merely owned by the "parent".
	+/
	this(int width = 640, int height = 480, string title = null, OpenGlOptions opengl = OpenGlOptions.no, Resizability resizable = Resizability.automaticallyScaleIfPossible, WindowTypes windowType = WindowTypes.normal, int customizationFlags = WindowFlags.normal, SimpleWindow parent = null) {
		claimGuiThread();
		version(sdpy_thread_checks) assert(thisIsGuiThread);
		this._width = width;
		this._height = height;
		this.openglMode = opengl;
		this.resizability = resizable;
		this.windowType = windowType;
		this.customizationFlags = customizationFlags;
		this._title = (title is null ? "D Application" : title);
		this._parent = parent;
		impl.createWindow(width, height, this._title, opengl, parent);

		if(windowType == WindowTypes.dropdownMenu || windowType == WindowTypes.popupMenu || windowType == WindowTypes.nestedChild || (customizationFlags & WindowFlags.transient))
			beingOpenKeepsAppOpen = false;
	}

	/// ditto
	this(int width, int height, string title, Resizability resizable, OpenGlOptions opengl = OpenGlOptions.no, WindowTypes windowType = WindowTypes.normal, int customizationFlags = WindowFlags.normal, SimpleWindow parent = null) {
		this(width, height, title, opengl, resizable, windowType, customizationFlags, parent);
	}

	/// Same as above, except using the `Size` struct instead of separate width and height.
	this(Size size, string title = null, OpenGlOptions opengl = OpenGlOptions.no, Resizability resizable = Resizability.automaticallyScaleIfPossible) {
		this(size.width, size.height, title, opengl, resizable);
	}

	/// ditto
	this(Size size, string title, Resizability resizable, OpenGlOptions opengl = OpenGlOptions.no) {
		this(size, title, opengl, resizable);
	}


	/++
		Creates a window based on the given [Image]. It's client area
		width and height is equal to the image. (A window's client area
		is the drawable space inside; it excludes the title bar, etc.)

		Windows based on images will not be resizable and do not use OpenGL.

		It will draw the image in upon creation, but this will be overwritten
		upon any draws, including the initial window visible event.

		You probably do not want to use this and it may be removed from
		the library eventually, or I might change it to be a "permanent"
		background image; one that is automatically drawn on it before any
		other drawing event. idk.
	+/
	this(Image image, string title = null) {
		this(image.width, image.height, title);
		this.image = image;
	}

	/++
		Wraps a native window handle with very little additional processing - notably no destruction
		this is incomplete so don't use it for much right now. The purpose of this is to make native
		windows created through the low level API (so you can use platform-specific options and
		other details SimpleWindow does not expose) available to the event loop wrappers.
	+/
	this(NativeWindowHandle nativeWindow) {
		version(Windows)
			impl.hwnd = nativeWindow;
		else version(X11) {
			impl.window = nativeWindow;
			display = XDisplayConnection.get(); // get initial display to not segfault
		} else version(OSXCocoa)
			throw new NotYetImplementedException();
		else featureNotImplemented();
		// FIXME: set the size correctly
		_width = 1;
		_height = 1;
		nativeMapping[nativeWindow] = this;

		beingOpenKeepsAppOpen = false;

		CapableOfHandlingNativeEvent.nativeHandleMapping[nativeWindow] = this;
		_suppressDestruction = true; // so it doesn't try to close
	}

	/// Experimental, do not use yet
	/++
		Grabs exclusive input from the user until you release it with
		[releaseInputGrab].


		Note: it is extremely rude to do this without good reason.
		Reasons may include doing some kind of mouse drag operation
		or popping up a temporary menu that should get events and will
		be dismissed at ease by the user clicking away.

		Params:
			keyboard = do you want to grab keyboard input?
			mouse = grab mouse input?
			confine = confine the mouse cursor to inside this window?

		History:
			Prior to March 11, 2021, grabbing the keyboard would always also
			set the X input focus. Now, it only focuses if it is a non-transient
			window and otherwise manages the input direction internally.

			This means spurious focus/blur events will no longer be sent and the
			application will not steal focus from other applications (which the
			window manager may have rejected anyway).
	+/
	void grabInput(bool keyboard = true, bool mouse = true, bool confine = false) {
		static if(UsingSimpledisplayX11) {
			XSync(XDisplayConnection.get, 0);
			if(keyboard) {
				if(isTransient && _parent) {
					/*
					FIXME:
						setting the keyboard focus is not actually that helpful, what I more likely want
						is the events from the parent window to be sent over here if we're transient.
					*/

					_parent.inputProxy = this;
				} else {
					XSetInputFocus(XDisplayConnection.get, this.impl.window, RevertToParent, CurrentTime);
				}
			}
			if(mouse) {
			if(auto res = XGrabPointer(XDisplayConnection.get, this.impl.window, false /* owner_events */, 
				EventMask.PointerMotionMask // FIXME: not efficient
				| EventMask.ButtonPressMask
				| EventMask.ButtonReleaseMask
			/* event mask */, GrabMode.GrabModeAsync, GrabMode.GrabModeAsync, confine ? this.impl.window : None, None, CurrentTime)
				)
			{
				XSync(XDisplayConnection.get, 0);
				import core.stdc.stdio;
				printf("Grab input failed %d\n", res);
				//throw new Exception("Grab input failed");
			} else {
				// cool
			}
			}

		} else version(Windows) {
			// FIXME: keyboard?
			SetCapture(impl.hwnd);
			if(confine) {
				RECT rcClip;
				//RECT rcOldClip;
				//GetClipCursor(&rcOldClip); 
				GetWindowRect(hwnd, &rcClip); 
				ClipCursor(&rcClip); 
			}
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	private bool isTransient() {
		with(WindowTypes)
		final switch(windowType) {
			case normal, undecorated, eventOnly:
			case nestedChild:
				return (customizationFlags & WindowFlags.transient) ? true : false;
			case dropdownMenu, popupMenu, notification:
				return true;
		}
	}

	private SimpleWindow inputProxy;

	/++
		Releases the grab acquired by [grabInput].
	+/
	void releaseInputGrab() {
		static if(UsingSimpledisplayX11) {
			XUngrabPointer(XDisplayConnection.get, CurrentTime);
			if(_parent)
				_parent.inputProxy = null;
		} else version(Windows) {
			ReleaseCapture();
			ClipCursor(null); 
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	/++
		Sets the input focus to this window.

		You shouldn't call this very often - please let the user control the input focus.
	+/
	void focus() {
		static if(UsingSimpledisplayX11) {
			XSetInputFocus(XDisplayConnection.get, this.impl.window, RevertToParent, CurrentTime);
		} else version(Windows) {
			SetFocus(this.impl.hwnd);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	/++
		Requests attention from the user for this window.


		The typical result of this function is to change the color
		of the taskbar icon, though it may be tweaked on specific
		platforms.

		It is meant to unobtrusively tell the user that something
		relevant to them happened in the background and they should
		check the window when they get a chance. Upon receiving the
		keyboard focus, the window will automatically return to its
		natural state.

		If the window already has the keyboard focus, this function
		may do nothing, because the user is presumed to already be
		giving the window attention.

		Implementation_note:

		`requestAttention` uses the _NET_WM_STATE_DEMANDS_ATTENTION
		atom on X11 and the FlashWindow function on Windows.
	+/
	void requestAttention() {
		if(_focused)
			return;

		version(Windows) {
			FLASHWINFO info;
			info.cbSize = info.sizeof;
			info.hwnd = impl.hwnd;
			info.dwFlags = FLASHW_TRAY;
			info.uCount = 1;

			FlashWindowEx(&info);

		} else version(X11) {
			demandingAttention = true;
			demandAttention(this, true);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	private bool _focused;

	version(X11) private bool demandingAttention;

	/// This will be called when WM wants to close your window (i.e. user clicked "close" icon, for example).
	/// You'll have to call `close()` manually if you set this delegate.
	void delegate () closeQuery;

	/// This will be called when window visibility was changed.
	void delegate (bool becomesVisible) visibilityChanged;

	/// This will be called when window becomes visible for the first time.
	/// You can do OpenGL initialization here. Note that in X11 you can't call
	/// [setAsCurrentOpenGlContext] right after window creation, or X11 may
	/// fail to send reparent and map events (hit that with proprietary NVidia drivers).
	private bool _visibleForTheFirstTimeCalled;
	void delegate () visibleForTheFirstTime;

	/// Returns true if the window has been closed.
	final @property bool closed() { return _closed; }

	/// Returns true if the window is focused.
	final @property bool focused() { return _focused; }

	private bool _visible;
	/// Returns true if the window is visible (mapped).
	final @property bool visible() { return _visible; }

	/// Closes the window. If there are no more open windows, the event loop will terminate.
	void close() {
		if (!_closed) {
			runInGuiThread( {
				if(_closed) return; // another thread got to it first. this isn't a big deal, it just means our message was queued
				if (onClosing !is null) onClosing();
				impl.closeWindow();
				_closed = true;
			} );
		}
	}

	/++
		`close` is one of the few methods that can be called from other threads. This `shared` overload reflects that.

		History:
			Overload added on March 7, 2021.
	+/
	void close() shared {
		(cast() this).close();
	}

	/++

	+/
	void maximize() {
		version(Windows)
			ShowWindow(impl.hwnd, SW_MAXIMIZE);
		else version(X11) {
			setNetWmStateAtom(this.impl.window, GetAtom!("_NET_WM_STATE_MAXIMIZED_VERT", false)(XDisplayConnection.get), true, GetAtom!("_NET_WM_STATE_MAXIMIZED_HORZ", false)(XDisplayConnection.get));

			// also note _NET_WM_STATE_FULLSCREEN
		}

	}

	private bool _fullscreen;

	/// not fully implemented but planned for a future release
	void fullscreen(bool yes) {
		version(X11)
			setNetWmStateAtom(this.impl.window, GetAtom!("_NET_WM_STATE_FULLSCREEN", false)(XDisplayConnection.get), yes);

		_fullscreen = yes;

	}

	bool fullscreen() {
		return _fullscreen;
	}

	/++
		Note: only implemented on Windows. No-op on other platforms. You may want to use [hide] instead.

	+/
	void minimize() {
		version(Windows)
			ShowWindow(impl.hwnd, SW_MINIMIZE);
		//else version(X11)
			//setNetWmStateAtom(this, GetAtom!("_NET_WM_STATE_MINIMIZED", false)(XDisplayConnection.get), true);
	}

	/// Alias for `hidden = false`
	void show() {
		hidden = false;
	}

	/// Alias for `hidden = true`
	void hide() {
		hidden = true;
	}

	/// Hide cursor when it enters the window.
	void hideCursor() {
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.hideCursor();
	}

	/// Don't hide cursor when it enters the window.
	void showCursor() {
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.showCursor();
	}

	/** "Warp" mouse pointer to coordinates relative to window top-left corner. Return "success" flag.
	 *
	 * Please remember that the cursor is a shared resource that should usually be left to the user's
	 * control. Try to think for other approaches before using this function.
	 *
	 * Note: "warping" pointer will not send any synthesised mouse events, so you probably doesn't want
	 *       to use it to move mouse pointer to some active GUI area, for example, as your window won't
	 *       receive "mouse moved here" event.
	 */
	bool warpMouse (int x, int y) {
		version(X11) {
			if (!_closed) { impl.warpMouse(x, y); return true; }
		} else version(Windows) {
			if (!_closed) {
				POINT point;
				point.x = x;
				point.y = y;
				if(ClientToScreen(impl.hwnd, &point)) {
					SetCursorPos(point.x, point.y);
					return true;
				}
			}
		}
		return false;
	}

	/// Send dummy window event to ping event loop. Required to process NotificationIcon on X11, for example.
	void sendDummyEvent () {
		version(X11) {
			if (!_closed) { impl.sendDummyEvent(); }
		}
	}

	/// Set window minimal size.
	void setMinSize (int minwidth, int minheight) {
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.setMinSize(minwidth, minheight);
	}

	/// Set window maximal size.
	void setMaxSize (int maxwidth, int maxheight) {
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.setMaxSize(maxwidth, maxheight);
	}

	/// Set window resize step (window size will be changed with the given granularity on supported platforms).
	/// Currently only supported on X11.
	void setResizeGranularity (int granx, int grany) {
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.setResizeGranularity(granx, grany);
	}

	/// Move window.
	void move(int x, int y) {
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.move(x, y);
	}

	/// ditto
	void move(Point p) {
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.move(p.x, p.y);
	}

	/++
		Resize window.

		Note that the width and height of the window are NOT instantly
		updated - it waits for the window manager to approve the resize
		request, which means you must return to the event loop before the
		width and height are actually changed.
	+/
	void resize(int w, int h) {
		if(!_closed && _fullscreen) fullscreen = false;
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.resize(w, h);
	}

	/// Move and resize window (this can be faster and more visually pleasant than doing it separately).
	void moveResize (int x, int y, int w, int h) {
		if(!_closed && _fullscreen) fullscreen = false;
		version(OSXCocoa) throw new NotYetImplementedException(); else
		if (!_closed) impl.moveResize(x, y, w, h);
	}

	private bool _hidden;

	/// Returns true if the window is hidden.
	final @property bool hidden() {
		return _hidden;
	}

	/// Shows or hides the window based on the bool argument.
	final @property void hidden(bool b) {
		_hidden = b;
		version(Windows) {
			ShowWindow(impl.hwnd, b ? SW_HIDE : SW_SHOW);
		} else version(X11) {
			if(b)
				//XUnmapWindow(impl.display, impl.window);
				XWithdrawWindow(impl.display, impl.window, DefaultScreen(impl.display));
			else
				XMapWindow(impl.display, impl.window);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	/// Sets the window opacity. On X11 this requires a compositor to be running. On windows the WindowFlags.extraComposite must be set at window creation.
	void opacity(double opacity) @property
	in {
		assert(opacity >= 0 && opacity <= 1);
	} do {
		version (Windows) {
			impl.setOpacity(cast(ubyte)(255 * opacity));
		} else version (X11) {
			impl.setOpacity(cast(uint)(uint.max * opacity));
		} else throw new NotYetImplementedException();
	}

	/++
		Sets your event handlers, without entering the event loop. Useful if you
		have multiple windows - set the handlers on each window, then only do eventLoop on your main window.
	+/
	void setEventHandlers(T...)(T eventHandlers) {
		// FIXME: add more events
		foreach(handler; eventHandlers) {
			static if(__traits(compiles, handleKeyEvent = handler)) {
				handleKeyEvent = handler;
			} else static if(__traits(compiles, handleCharEvent = handler)) {
				handleCharEvent = handler;
			} else static if(__traits(compiles, handlePulse = handler)) {
				handlePulse = handler;
			} else static if(__traits(compiles, handleMouseEvent = handler)) {
				handleMouseEvent = handler;
			} else static assert(0, "I can't use this event handler " ~ typeof(handler).stringof ~ "\nHave you tried using the delegate keyword?");
		}
	}

	/// The event loop automatically returns when the window is closed
	/// pulseTimeout is given in milliseconds. If pulseTimeout == 0, no
	/// pulse timer is created. The event loop will block until an event
	/// arrives or the pulse timer goes off.
	final int eventLoop(T...)(
		long pulseTimeout,    /// set to zero if you don't want a pulse.
		T eventHandlers) /// delegate list like std.concurrency.receive
	{
		setEventHandlers(eventHandlers);

		version(with_eventloop) {
			// delegates event loop to my other module
			version(X11)
				XFlush(display);

			import arsd.eventloop;
			auto handle = setInterval(handlePulse, cast(int) pulseTimeout);
			scope(exit) clearInterval(handle);

			loop();
			return 0;
		} else version(OSXCocoa) {
			// FIXME
			if (handlePulse !is null && pulseTimeout != 0) {
				timer = scheduledTimer(pulseTimeout*1e-3,
					view, sel_registerName("simpledisplay_pulse"),
					null, true);
			}

            		setNeedsDisplay(view, true);
            		run(NSApp);
            		return 0;
        	} else {
			EventLoop el = EventLoop(pulseTimeout, handlePulse);
			return el.run();
		}
	}

	/++
		This lets you draw on the window (or its backing buffer) using basic
		2D primitives.

		Be sure to call this in a limited scope because your changes will not
		actually appear on the window until ScreenPainter's destructor runs.

		Returns: an instance of [ScreenPainter], which has the drawing methods
		on it to draw on this window.
	+/
	ScreenPainter draw() {
		return impl.getPainter();
	}

	// This is here to implement the interface we use for various native handlers.
	NativeEventHandler getNativeEventHandler() { return handleNativeEvent; }

	// maps native window handles to SimpleWindow instances, if there are any
	// you shouldn't need this, but it is public in case you do in a native event handler or something
	public __gshared SimpleWindow[NativeWindowHandle] nativeMapping;

	/// Width of the window's drawable client area, in pixels.
	@scriptable
	final @property int width() const pure nothrow @safe @nogc { return _width; }

	/// Height of the window's drawable client area, in pixels.
	@scriptable
	final @property int height() const pure nothrow @safe @nogc { return _height; }

	private int _width;
	private int _height;

	// HACK: making the best of some copy constructor woes with refcounting
	private ScreenPainterImplementation* activeScreenPainter_;

	protected ScreenPainterImplementation* activeScreenPainter() { return activeScreenPainter_; }
	protected void activeScreenPainter(ScreenPainterImplementation* i) { activeScreenPainter_ = i; }

	private OpenGlOptions openglMode;
	private Resizability resizability;
	private WindowTypes windowType;
	private int customizationFlags;

	/// `true` if OpenGL was initialized for this window.
	@property bool isOpenGL () const pure nothrow @safe @nogc {
		version(without_opengl)
			return false;
		else
			return (openglMode == OpenGlOptions.yes);
	}
	@property Resizability resizingMode () const pure nothrow @safe @nogc { return resizability; } /// Original resizability.
	@property WindowTypes type () const pure nothrow @safe @nogc { return windowType; } /// Original window type.
	@property int customFlags () const pure nothrow @safe @nogc { return customizationFlags; } /// Original customization flags.

	/// "Lock" this window handle, to do multithreaded synchronization. You probably won't need
	/// to call this, as it's not recommended to share window between threads.
	void mtLock () {
		version(X11) {
			XLockDisplay(this.display);
		}
	}

	/// "Unlock" this window handle, to do multithreaded synchronization. You probably won't need
	/// to call this, as it's not recommended to share window between threads.
	void mtUnlock () {
		version(X11) {
			XUnlockDisplay(this.display);
		}
	}

	/// Emit a beep to get user's attention.
	void beep () {
		version(X11) {
			XBell(this.display, 100);
		} else version(Windows) {
			MessageBeep(0xFFFFFFFF);
		}
	}



	version(without_opengl) {} else {

		/// Put your code in here that you want to be drawn automatically when your window is uncovered. Set a handler here *before* entering your event loop any time you pass `OpenGlOptions.yes` to the constructor. Ideally, you will set this delegate immediately after constructing the `SimpleWindow`.
		void delegate() redrawOpenGlScene;

		/// This will allow you to change OpenGL vsync state.
		final @property void vsync (bool wait) {
		  if (this._closed) return; // window may be closed, but timer is still firing; avoid GLXBadDrawable error
		  version(X11) {
		    setAsCurrentOpenGlContext();
		    glxSetVSync(display, impl.window, wait);
		  } else version(Windows) {
		    setAsCurrentOpenGlContext();
                    wglSetVSync(wait);
		  }
		}

		/// Set this to `false` if you don't need to do `glFinish()` after `swapOpenGlBuffers()`.
		/// Note that at least NVidia proprietary driver may segfault if you will modify texture fast
		/// enough without waiting 'em to finish their frame bussiness.
		bool useGLFinish = true;

		// FIXME: it should schedule it for the end of the current iteration of the event loop...
		/// call this to invoke your delegate. It automatically sets up the context and flips the buffer. If you need to redraw the scene in response to an event, call this.
		void redrawOpenGlSceneNow() {
		  version(X11) if (!this._visible) return; // no need to do this if window is invisible
			if (this._closed) return; // window may be closed, but timer is still firing; avoid GLXBadDrawable error
			if(redrawOpenGlScene is null)
				return;

			this.mtLock();
			scope(exit) this.mtUnlock();

			this.setAsCurrentOpenGlContext();

			redrawOpenGlScene();

			this.swapOpenGlBuffers();
			// at least nvidia proprietary crap segfaults on exit if you won't do this and will call glTexSubImage2D() too fast; no, `glFlush()` won't work.
			if (useGLFinish) glFinish();
		}

		private bool redrawOpenGlSceneSoonSet = false;
		private static class RedrawOpenGlSceneEvent {
			SimpleWindow w;
			this(SimpleWindow w) { this.w = w; }
		}
		private RedrawOpenGlSceneEvent redrawOpenGlSceneEvent;
		/++
			Queues an opengl redraw as soon as the other pending events are cleared.
		+/
		void redrawOpenGlSceneSoon() {
			if(!redrawOpenGlSceneSoonSet) {
				redrawOpenGlSceneEvent = new RedrawOpenGlSceneEvent(this);
				this.addEventListener((RedrawOpenGlSceneEvent e) { e.w.redrawOpenGlSceneNow(); });
				redrawOpenGlSceneSoonSet = true;
			}
			this.postEvent(redrawOpenGlSceneEvent, true);
		}


		/// Makes all gl* functions target this window until changed. This is only valid if you passed `OpenGlOptions.yes` to the constructor.
		void setAsCurrentOpenGlContext() {
			assert(openglMode == OpenGlOptions.yes);
			version(X11) {
				if(glXMakeCurrent(display, impl.window, impl.glc) == 0)
					throw new Exception("glXMakeCurrent");
			} else version(Windows) {
				static if (SdpyIsUsingIVGLBinds) import iv.glbinds; // override druntime windows imports
				if (!wglMakeCurrent(ghDC, ghRC))
					throw new Exception("wglMakeCurrent"); // let windows users suffer too
			}
		}

		/// Makes all gl* functions target this window until changed. This is only valid if you passed `OpenGlOptions.yes` to the constructor.
		/// This doesn't throw, returning success flag instead.
		bool setAsCurrentOpenGlContextNT() nothrow {
			assert(openglMode == OpenGlOptions.yes);
			version(X11) {
				return (glXMakeCurrent(display, impl.window, impl.glc) != 0);
			} else version(Windows) {
				static if (SdpyIsUsingIVGLBinds) import iv.glbinds; // override druntime windows imports
				return wglMakeCurrent(ghDC, ghRC) ? true : false;
			}
		}

		/// Releases OpenGL context, so it can be reused in, for example, different thread. This is only valid if you passed `OpenGlOptions.yes` to the constructor.
		/// This doesn't throw, returning success flag instead.
		bool releaseCurrentOpenGlContext() nothrow {
			assert(openglMode == OpenGlOptions.yes);
			version(X11) {
				return (glXMakeCurrent(display, 0, null) != 0);
			} else version(Windows) {
				static if (SdpyIsUsingIVGLBinds) import iv.glbinds; // override druntime windows imports
				return wglMakeCurrent(ghDC, null) ? true : false;
			}
		}

		/++
			simpledisplay always uses double buffering, usually automatically. This
			manually swaps the OpenGL buffers.


			You should not need to call this yourself because simpledisplay will do it
			for you after calling your `redrawOpenGlScene`.

			Remember that this may throw an exception, which you can catch in a multithreaded
			application to keep your thread from dying from an unhandled exception.
		+/
		void swapOpenGlBuffers() {
			assert(openglMode == OpenGlOptions.yes);
			version(X11) {
				if (!this._visible) return; // no need to do this if window is invisible
				if (this._closed) return; // window may be closed, but timer is still firing; avoid GLXBadDrawable error
				glXSwapBuffers(display, impl.window);
			} else version(Windows) {
				SwapBuffers(ghDC);
			}
		}
	}

	/++
		Set the window title, which is visible on the window manager title bar, operating system taskbar, etc.


		---
			auto window = new SimpleWindow(100, 100, "First title");
			window.title = "A new title";
		---

		You may call this function at any time.
	+/
	@property void title(string title) {
		_title = title;
		version(OSXCocoa) throw new NotYetImplementedException(); else
		impl.setTitle(title);
	}

	private string _title;

	/// Gets the title
	@property string title() {
		if(_title is null)
			_title = getRealTitle();
		return _title;
	}

	/++
		Get the title as set by the window manager.
		May not match what you attempted to set.
	+/
	string getRealTitle() {
		static if(is(typeof(impl.getTitle())))
			return impl.getTitle();
		else
			return null;
	}

	// don't use this generally it is not yet really released
	version(X11)
	@property Image secret_icon() {
		return secret_icon_inner;
	}
	private Image secret_icon_inner;


	/// Set the icon that is seen in the title bar or taskbar, etc., for the user.
	@property void icon(MemoryImage icon) {
		auto tci = icon.getAsTrueColorImage();
		version(Windows) {
			winIcon = new WindowsIcon(icon);
			 SendMessageA(impl.hwnd, 0x0080 /*WM_SETICON*/, 0 /*ICON_SMALL*/, cast(LPARAM) winIcon.hIcon); // there is also 1 == ICON_BIG
		} else version(X11) {
			secret_icon_inner = Image.fromMemoryImage(icon);
			// FIXME: ensure this is correct
			auto display = XDisplayConnection.get;
			arch_ulong[] buffer;
			buffer ~= icon.width;
			buffer ~= icon.height;
			foreach(c; tci.imageData.colors) {
				arch_ulong b;
				b |= c.a << 24;
				b |= c.r << 16;
				b |= c.g << 8;
				b |= c.b;
				buffer ~= b;
			}

			XChangeProperty(
				display,
				impl.window,
				GetAtom!("_NET_WM_ICON", true)(display),
				GetAtom!"CARDINAL"(display),
				32 /* bits */,
				0 /*PropModeReplace*/,
				buffer.ptr,
				cast(int) buffer.length);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	version(Windows)
		private WindowsIcon winIcon;

	bool _suppressDestruction;

	~this() {
		if(_suppressDestruction)
			return;
		impl.dispose();
	}

	private bool _closed;

	// the idea here is to draw something temporary on top of the main picture e.g. a blinking cursor
	/*
	ScreenPainter drawTransiently() {
		return impl.getPainter();
	}
	*/

	/// Draws an image on the window. This is meant to provide quick look
	/// of a static image generated elsewhere.
	@property void image(Image i) {
	/+
		version(Windows) {
			BITMAP bm;
			HDC hdc = GetDC(hwnd);
			HDC hdcMem = CreateCompatibleDC(hdc);
			HBITMAP hbmOld = SelectObject(hdcMem, i.handle);

			GetObject(i.handle, bm.sizeof, &bm);

			BitBlt(hdc, 0, 0, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, SRCCOPY);

			SelectObject(hdcMem, hbmOld);
			DeleteDC(hdcMem);
			ReleaseDC(hwnd, hdc);

			/*
			RECT r;
			r.right = i.width;
			r.bottom = i.height;
			InvalidateRect(hwnd, &r, false);
			*/
		} else
		version(X11) {
			if(!destroyed) {
				if(i.usingXshm)
				XShmPutImage(display, cast(Drawable) window, gc, i.handle, 0, 0, 0, 0, i.width, i.height, false);
				else
				XPutImage(display, cast(Drawable) window, gc, i.handle, 0, 0, 0, 0, i.width, i.height);
			}
		} else
		version(OSXCocoa) {
			draw().drawImage(Point(0, 0), i);
			setNeedsDisplay(view, true);
		} else static assert(0);
	+/
		auto painter = this.draw;
		painter.drawImage(Point(0, 0), i);
	}

	/++
		Changes the cursor for the window. If the cursor is hidden via [hideCursor], this has no effect.

		---
		window.cursor = GenericCursor.Help;
		// now the window mouse cursor is set to a generic help
		---

	+/
	@property void cursor(MouseCursor cursor) {
		version(OSXCocoa)
			featureNotImplemented();
		else
		if(this.impl.curHidden <= 0) {
			static if(UsingSimpledisplayX11) {
				auto ch = cursor.cursorHandle;
				XDefineCursor(XDisplayConnection.get(), this.impl.window, ch);
			} else version(Windows) {
				auto ch = cursor.cursorHandle;
				impl.currentCursor = ch;
				SetCursor(ch); // redraw without waiting for mouse movement to update
			} else featureNotImplemented();
		}

	}

	/// What follows are the event handlers. These are set automatically
	/// by the eventLoop function, but are still public so you can change
	/// them later. wasPressed == true means key down. false == key up.

	/// Handles a low-level keyboard event. Settable through setEventHandlers.
	void delegate(KeyEvent ke) handleKeyEvent;

	/// Handles a higher level keyboard event - c is the character just pressed. Settable through setEventHandlers.
	void delegate(dchar c) handleCharEvent;

	/// Handles a timer pulse. Settable through setEventHandlers.
	void delegate() handlePulse;

	/// Called when the focus changes, param is if we have it (true) or are losing it (false).
	void delegate(bool) onFocusChange;

	/** Called inside `close()` method. Our window is still alive, and we can free various resources.
	 * Sometimes it is easier to setup the delegate instead of subclassing. */
	void delegate() onClosing;

	/** Called when we received destroy notification. At this stage we cannot do much with our window
	 * (as it is already dead, and it's native handle cannot be used), but we still can do some
	 * last minute cleanup. */
	void delegate() onDestroyed;

	static if (UsingSimpledisplayX11)
	/** Called when Expose event comes. See Xlib manual to understand the arguments.
	 * Return `false` if you want Simpledisplay to copy backbuffer, or `true` if you did it yourself.
	 * You will probably never need to setup this handler, it is for very low-level stuff.
	 *
	 * WARNING! Xlib is multithread-locked when this handles is called! */
	bool delegate(int x, int y, int width, int height, int eventsLeft) handleExpose;

	//version(Windows)
	//bool delegate(WPARAM wParam, LPARAM lParam) handleWM_PAINT;

	private {
		int lastMouseX = int.min;
		int lastMouseY = int.min;
		void mdx(ref MouseEvent ev) {
			if(lastMouseX == int.min || lastMouseY == int.min) {
				ev.dx = 0;
				ev.dy = 0;
			} else {
				ev.dx = ev.x - lastMouseX;
				ev.dy = ev.y - lastMouseY;
			}

			lastMouseX = ev.x;
			lastMouseY = ev.y;
		}
	}

	/// Mouse event handler. Settable through setEventHandlers.
	void delegate(MouseEvent) handleMouseEvent;

	/// use to redraw child widgets if you use system apis to add stuff
	void delegate() paintingFinished;

	void delegate() paintingFinishedDg() {
		return paintingFinished;
	}

	/// handle a resize, after it happens. You must construct the window with Resizability.allowResizing
	/// for this to ever happen.
	void delegate(int width, int height) windowResized;

	/** Platform specific - handle any native messages this window gets.
	  *
	  * Note: this is called *in addition to* other event handlers, unless you return zero indicating that you handled it.

	  * On Windows, it takes the form of int delegate(HWND,UINT, WPARAM, LPARAM).

	  * On X11, it takes the form of int delegate(XEvent).

	  * IMPORTANT: it used to be static in old versions of simpledisplay.d, but I always used
	  * it as if it wasn't static... so now I just fixed it so it isn't anymore.
	**/
	NativeEventHandler handleNativeEvent;

	/// This is the same as handleNativeEvent, but static so it can hook ALL events in the loop.
	/// If you used to use handleNativeEvent depending on it being static, just change it to use
	/// this instead and it will work the same way.
	__gshared NativeEventHandler handleNativeGlobalEvent;

//  private:
	/// The native implementation is available, but you shouldn't use it unless you are
	/// familiar with the underlying operating system, don't mind depending on it, and
	/// know simpledisplay.d's internals too. It is virtually private; you can hopefully
	/// do what you need to do with handleNativeEvent instead.
	///
	/// This is likely to eventually change to be just a struct holding platform-specific
	/// handles instead of a template mixin at some point because I'm not happy with the
	/// code duplication here (ironically).
	mixin NativeSimpleWindowImplementation!() impl;

	/**
		This is in-process one-way (from anything to window) event sending mechanics.
		It is thread-safe, so it can be used in multi-threaded applications to send,
		for example, "wake up and repaint" events when thread completed some operation.
		This will allow to avoid using timer pulse to check events with synchronization,
		'cause event handler will be called in UI thread. You can stop guessing which
		pulse frequency will be enough for your app.
		Note that events handlers may be called in arbitrary order, i.e. last registered
		handler can be called first, and vice versa.
	*/
public:
	/** Is our custom event queue empty? Can be used in simple cases to prevent
	 * "spamming" window with events it can't cope with.
	 * It is safe to call this from non-UI threads.
	 */
	@property bool eventQueueEmpty() () {
		synchronized(this) {
			foreach (const ref o; eventQueue[0..eventQueueUsed]) if (!o.doProcess) return false;
		}
		return true;
	}

	/** Does our custom event queue contains at least one with the given type?
	 * Can be used in simple cases to prevent "spamming" window with events
	 * it can't cope with.
	 * It is safe to call this from non-UI threads.
	 */
	@property bool eventQueued(ET:Object) () {
		synchronized(this) {
			foreach (const ref o; eventQueue[0..eventQueueUsed]) {
				if (!o.doProcess) {
					if (cast(ET)(o.evt)) return true;
				}
			}
		}
		return false;
	}

	/++
		Event listeners added with [addEventListener] have their exceptions swallowed by the event loop. This delegate can handle them again before it proceeds.

		History:
			Added May 12, 2021
	+/
	void delegate(Exception e) nothrow eventUncaughtException;

	/** Add listener for custom event. Can be used like this:
	 *
	 * ---------------------
	 *   auto eid = win.addEventListener((MyStruct evt) { ... });
	 *   ...
	 *   win.removeEventListener(eid);
	 * ---------------------
	 *
	 * Returns: 0 on failure (should never happen, so ignore it)
	 *
	 * $(WARNING Don't use this method in object destructors!)
	 *
	 * $(WARNING It is better to register all event handlers and don't remove 'em,
	 *           'cause if event handler id counter will overflow, you won't be able
	 *           to register any more events.)
	 */
	uint addEventListener(ET:Object) (void delegate (ET) dg) {
		if (dg is null) return 0; // ignore empty handlers
		synchronized(this) {
			//FIXME: abort on overflow?
			if (++lastUsedHandlerId == 0) { --lastUsedHandlerId; return 0; } // alas, can't register more events. at all.
			EventHandlerEntry e;
			e.dg = delegate (Object o) {
				if (auto co = cast(ET)o) {
					try {
						dg(co);
					} catch (Exception e) {
						// sorry!
						if(eventUncaughtException)
							eventUncaughtException(e);
					}
					return true;
				}
				return false;
			};
			e.id = lastUsedHandlerId;
			auto optr = eventHandlers.ptr;
			eventHandlers ~= e;
			if (eventHandlers.ptr !is optr) {
				import core.memory : GC;
				if (eventHandlers.ptr is GC.addrOf(eventHandlers.ptr)) GC.setAttr(eventHandlers.ptr, GC.BlkAttr.NO_INTERIOR);
			}
			return lastUsedHandlerId;
		}
	}

	/// Remove event listener. It is safe to pass invalid event id here.
	/// $(WARNING Don't use this method in object destructors!)
	void removeEventListener() (uint id) {
		if (id == 0 || id > lastUsedHandlerId) return;
		synchronized(this) {
			foreach (immutable idx; 0..eventHandlers.length) {
				if (eventHandlers[idx].id == id) {
					foreach (immutable c; idx+1..eventHandlers.length) eventHandlers[c-1] = eventHandlers[c];
					eventHandlers[$-1].dg = null;
					eventHandlers.length -= 1;
					eventHandlers.assumeSafeAppend;
					return;
				}
			}
		}
	}

	/// Post event to queue. It is safe to call this from non-UI threads.
	/// If `timeoutmsecs` is greater than zero, the event will be delayed for at least `timeoutmsecs` milliseconds.
	/// if `replace` is `true`, replace all existing events typed `ET` with the new one (if `evt` is empty, remove 'em all)
	/// Returns `true` if event was queued. Always returns `false` if `evt` is null.
	bool postTimeout(ET:Object) (ET evt, uint timeoutmsecs, bool replace=false) {
		if (this.closed) return false; // closed windows can't handle events

		// remove all events of type `ET`
		void removeAllET () {
			uint eidx = 0, ec = eventQueueUsed;
			auto eptr = eventQueue.ptr;
			while (eidx < ec) {
				if (eptr.doProcess) { ++eidx; ++eptr; continue; }
				if (cast(ET)eptr.evt !is null) {
					// i found her!
					if (inCustomEventProcessor) {
						// if we're in custom event processing loop, processor will clear it for us
						eptr.evt = null;
						++eidx;
						++eptr;
					} else {
						foreach (immutable c; eidx+1..ec) eventQueue.ptr[c-1] = eventQueue.ptr[c];
						ec = --eventQueueUsed;
						// clear last event (it is already copied)
						eventQueue.ptr[ec].evt = null;
					}
				} else {
					++eidx;
					++eptr;
				}
			}
		}

		if (evt is null) {
			if (replace) { synchronized(this) removeAllET(); }
			// ignore empty events, they can't be handled anyway
			return false;
		}

		// add events even if no event FD/event object created yet
		synchronized(this) {
			if (replace) removeAllET();
			if (eventQueueUsed == uint.max) return false; // just in case
			if (eventQueueUsed < eventQueue.length) {
				eventQueue[eventQueueUsed++] = QueuedEvent(evt, timeoutmsecs);
			} else {
				if (eventQueue.capacity == eventQueue.length) {
					// need to reallocate; do a trick to ensure that old array is cleared
					auto oarr = eventQueue;
					eventQueue ~= QueuedEvent(evt, timeoutmsecs);
					// just in case, do yet another check
					if (oarr.length != 0 && oarr.ptr !is eventQueue.ptr) foreach (ref e; oarr[0..eventQueueUsed]) e.evt = null;
					import core.memory : GC;
					if (eventQueue.ptr is GC.addrOf(eventQueue.ptr)) GC.setAttr(eventQueue.ptr, GC.BlkAttr.NO_INTERIOR);
				} else {
					auto optr = eventQueue.ptr;
					eventQueue ~= QueuedEvent(evt, timeoutmsecs);
					assert(eventQueue.ptr is optr);
				}
				++eventQueueUsed;
				assert(eventQueueUsed == eventQueue.length);
			}
			if (!eventWakeUp()) {
				// can't wake up event processor, so there is no reason to keep the event
				assert(eventQueueUsed > 0);
				eventQueue[--eventQueueUsed].evt = null;
				return false;
			}
			return true;
		}
	}

	/// Post event to queue. It is safe to call this from non-UI threads.
	/// if `replace` is `true`, replace all existing events typed `ET` with the new one (if `evt` is empty, remove 'em all)
	/// Returns `true` if event was queued. Always returns `false` if `evt` is null.
	bool postEvent(ET:Object) (ET evt, bool replace=false) {
		return postTimeout!ET(evt, 0, replace);
	}

private:
	private import core.time : MonoTime;

	version(Posix) {
		__gshared int customEventFDRead = -1;
		__gshared int customEventFDWrite = -1;
		__gshared int customSignalFD = -1;
	} else version(Windows) {
		__gshared HANDLE customEventH = null;
	}

	// wake up event processor
	static bool eventWakeUp () {
		version(X11) {
			import core.sys.posix.unistd : write;
			ulong n = 1;
			if (customEventFDWrite >= 0) write(customEventFDWrite, &n, n.sizeof);
			return true;
		} else version(Windows) {
			if (customEventH !is null) SetEvent(customEventH);
			return true;
		} else {
			// not implemented for other OSes
			return false;
		}
	}

	static struct QueuedEvent {
		Object evt;
		bool timed = false;
		MonoTime hittime = MonoTime.zero;
		bool doProcess = false; // process event at the current iteration (internal flag)

		this (Object aevt, uint toutmsecs) {
			evt = aevt;
			if (toutmsecs > 0) {
				import core.time : msecs;
				timed = true;
				hittime = MonoTime.currTime+toutmsecs.msecs;
			}
		}
	}

	alias CustomEventHandler = bool delegate (Object o) nothrow;
	static struct EventHandlerEntry {
		CustomEventHandler dg;
		uint id;
	}

	uint lastUsedHandlerId;
	EventHandlerEntry[] eventHandlers;
	QueuedEvent[] eventQueue = null;
	uint eventQueueUsed = 0; // to avoid `.assumeSafeAppend` and length changes
	bool inCustomEventProcessor = false; // required to properly remove events

	// process queued events and call custom event handlers
	// this will not process events posted from called handlers (such events are postponed for the next iteration)
	void processCustomEvents () {
		bool hasSomethingToDo = false;
		uint ecount;
		bool ocep;
		synchronized(this) {
			ocep = inCustomEventProcessor;
			inCustomEventProcessor = true;
			ecount = eventQueueUsed; // user may want to post new events from an event handler; process 'em on next iteration
			auto ctt = MonoTime.currTime;
			bool hasEmpty = false;
			// mark events to process (this is required for `eventQueued()`)
			foreach (ref qe; eventQueue[0..ecount]) {
				if (qe.evt is null) { hasEmpty = true; continue; }
				if (qe.timed) {
					qe.doProcess = (qe.hittime <= ctt);
				} else {
					qe.doProcess = true;
				}
				hasSomethingToDo = (hasSomethingToDo || qe.doProcess);
			}
			if (!hasSomethingToDo) {
				// remove empty events
				if (hasEmpty) {
					uint eidx = 0, ec = eventQueueUsed;
					auto eptr = eventQueue.ptr;
					while (eidx < ec) {
						if (eptr.evt is null) {
							foreach (immutable c; eidx+1..ec) eventQueue.ptr[c-1] = eventQueue.ptr[c];
							ec = --eventQueueUsed;
							eventQueue.ptr[ec].evt = null; // make GC life easier
						} else {
							++eidx;
							++eptr;
						}
					}
				}
				inCustomEventProcessor = ocep;
				return;
			}
		}
		// process marked events
		uint efree = 0; // non-processed events will be put at this index
		EventHandlerEntry[] eh;
		Object evt;
		foreach (immutable eidx; 0..ecount) {
			synchronized(this) {
				if (!eventQueue[eidx].doProcess) {
					// skip this event
					assert(efree <= eidx);
					if (efree != eidx) {
						// copy this event to queue start
						eventQueue[efree] = eventQueue[eidx];
						eventQueue[eidx].evt = null; // just in case
					}
					++efree;
					continue;
				}
				evt = eventQueue[eidx].evt;
				eventQueue[eidx].evt = null; // in case event handler will hit GC
				if (evt is null) continue; // just in case
				// try all handlers; this can be slow, but meh...
				eh = eventHandlers;
			}
			foreach (ref evhan; eh) if (evhan.dg !is null) evhan.dg(evt);
			evt = null;
			eh = null;
		}
		synchronized(this) {
			// move all unprocessed events to queue top; efree holds first "free index"
			foreach (immutable eidx; ecount..eventQueueUsed) {
				assert(efree <= eidx);
				if (efree != eidx) eventQueue[efree] = eventQueue[eidx];
				++efree;
			}
			eventQueueUsed = efree;
			// wake up event processor on next event loop iteration if we have more queued events
			// also, remove empty events
			bool awaken = false;
			uint eidx = 0, ec = eventQueueUsed;
			auto eptr = eventQueue.ptr;
			while (eidx < ec) {
				if (eptr.evt is null) {
					foreach (immutable c; eidx+1..ec) eventQueue.ptr[c-1] = eventQueue.ptr[c];
					ec = --eventQueueUsed;
					eventQueue.ptr[ec].evt = null; // make GC life easier
				} else {
					if (!awaken && !eptr.timed) { eventWakeUp(); awaken = true; }
					++eidx;
					++eptr;
				}
			}
			inCustomEventProcessor = ocep;
		}
	}

	// for all windows in nativeMapping
	static void processAllCustomEvents () {
		foreach (SimpleWindow sw; SimpleWindow.nativeMapping.byValue) {
			if (sw is null || sw.closed) continue;
			sw.processCustomEvents();
		}

		runPendingRunInGuiThreadDelegates();
	}

	// 0: infinite (i.e. no scheduled events in queue)
	uint eventQueueTimeoutMSecs () {
		synchronized(this) {
			if (eventQueueUsed == 0) return 0;
			if (inCustomEventProcessor) assert(0, "WUTAFUUUUUUU..."); // the thing that should not be. ABSOLUTELY! (c)
			uint res = int.max;
			auto ctt = MonoTime.currTime;
			foreach (const ref qe; eventQueue[0..eventQueueUsed]) {
				if (qe.evt is null) assert(0, "WUTAFUUUUUUU..."); // the thing that should not be. ABSOLUTELY! (c)
				if (qe.doProcess) continue; // just in case
				if (!qe.timed) return 1; // minimal
				if (qe.hittime <= ctt) return 1; // minimal
				auto tms = (qe.hittime-ctt).total!"msecs";
				if (tms < 1) tms = 1; // safety net
				if (tms >= int.max) tms = int.max-1; // and another safety net
				if (res > tms) res = cast(uint)tms;
			}
			return (res >= int.max ? 0 : res);
		}
	}

	// for all windows in nativeMapping
	static uint eventAllQueueTimeoutMSecs () {
		uint res = uint.max;
		foreach (SimpleWindow sw; SimpleWindow.nativeMapping.byValue) {
			if (sw is null || sw.closed) continue;
			uint to = sw.eventQueueTimeoutMSecs();
			if (to && to < res) {
				res = to;
				if (to == 1) break; // can't have less than this
			}
		}
		return (res >= int.max ? 0 : res);
	}
}

/* Drag and drop support { */
version(X11) {

} else version(Windows) {
	import core.sys.windows.uuid;
	import core.sys.windows.ole2;
	import core.sys.windows.oleidl;
	import core.sys.windows.objidl;
	import core.sys.windows.wtypes;

	pragma(lib, "ole32");
	void initDnd() {
		auto err = OleInitialize(null);
		if(err != S_OK && err != S_FALSE)
			throw new Exception("init");//err);
	}
}
/* } End drag and drop support */


/// Represents a mouse cursor (aka the mouse pointer, the image seen on screen that indicates where the mouse is pointing).
/// See [GenericCursor].
class MouseCursor {
	int osId;
	bool isStockCursor;
	private this(int osId) {
		this.osId = osId;
		this.isStockCursor = true;
	}

	// https://msdn.microsoft.com/en-us/library/windows/desktop/ms648385(v=vs.85).aspx
	this(int xHotSpot, int yHotSpot, ubyte[] andMask, ubyte[] xorMask) {}

	version(Windows) {
		HCURSOR cursor_;
		HCURSOR cursorHandle() {
			if(cursor_ is null)
				cursor_ = LoadCursor(null, MAKEINTRESOURCE(osId));
			return cursor_;
		}

	} else static if(UsingSimpledisplayX11) {
		Cursor cursor_ = None;
		int xDisplaySequence;

		Cursor cursorHandle() {
			if(this.osId == None)
				return None;

			// we need to reload if we on a new X connection
			if(cursor_ == None || XDisplayConnection.connectionSequenceNumber != xDisplaySequence) {
				cursor_ = XCreateFontCursor(XDisplayConnection.get(), this.osId);
				xDisplaySequence = XDisplayConnection.connectionSequenceNumber;
			}
			return cursor_;
		}
	}
}

// https://developer.mozilla.org/en-US/docs/Web/CSS/cursor
// https://tronche.com/gui/x/xlib/appendix/b/
// https://msdn.microsoft.com/en-us/library/windows/desktop/ms648391(v=vs.85).aspx
/// Note that there is no exact appearance guaranteed for any of these items; it may change appearance on different operating systems or future simpledisplay versions.
enum GenericCursorType {
	Default, /// The default arrow pointer.
	Wait, /// A cursor indicating something is loading and the user must wait.
	Hand, /// A pointing finger, like the one used hovering over hyperlinks in a web browser.
	Help, /// A cursor indicating the user can get help about the pointer location.
	Cross, /// A crosshair.
	Text, /// An i-beam shape, typically used to indicate text selection is possible.
	Move, /// Pointer indicating movement is possible. May also be used as SizeAll.
	UpArrow, /// An arrow pointing straight up.
	Progress, /// The hourglass and arrow, indicating the computer is working but the user can still work. Not great results on X11.
	NotAllowed, /// Indicates the current operation is not allowed. Not great results on X11.
	SizeNesw, /// Arrow pointing northeast and southwest (lower-left corner resize indicator).
	SizeNs, /// Arrow pointing north and south (upper/lower edge resize indicator).
	SizeNwse, /// Arrow pointing northwest and southeast (upper-left corner resize indicator).
	SizeWe, /// Arrow pointing west and east (left/right edge resize indicator).

}

/*
	X_plus == css cell == Windows ?
*/

/// You get one by `GenericCursor.SomeTime`. See [GenericCursorType] for a list of types.
static struct GenericCursor {
	static:
	///
	MouseCursor opDispatch(string str)() if(__traits(hasMember, GenericCursorType, str)) {
		static MouseCursor mc;

		auto type = __traits(getMember, GenericCursorType, str);

		if(mc is null) {

			version(Windows) {
				int osId;
				final switch(type) {
					case GenericCursorType.Default: osId = IDC_ARROW; break;
					case GenericCursorType.Wait: osId = IDC_WAIT; break;
					case GenericCursorType.Hand: osId = IDC_HAND; break;
					case GenericCursorType.Help: osId = IDC_HELP; break;
					case GenericCursorType.Cross: osId = IDC_CROSS; break;
					case GenericCursorType.Text: osId = IDC_IBEAM; break;
					case GenericCursorType.Move: osId = IDC_SIZEALL; break;
					case GenericCursorType.UpArrow: osId = IDC_UPARROW; break;
					case GenericCursorType.Progress: osId = IDC_APPSTARTING; break;
					case GenericCursorType.NotAllowed: osId = IDC_NO; break;
					case GenericCursorType.SizeNesw: osId = IDC_SIZENESW; break;
					case GenericCursorType.SizeNs: osId = IDC_SIZENS; break;
					case GenericCursorType.SizeNwse: osId = IDC_SIZENWSE; break;
					case GenericCursorType.SizeWe: osId = IDC_SIZEWE; break;
				}
			} else static if(UsingSimpledisplayX11) {
				int osId;
				final switch(type) {
					case GenericCursorType.Default: osId = None; break;
					case GenericCursorType.Wait: osId = 150 /* XC_watch */; break;
					case GenericCursorType.Hand: osId = 60 /* XC_hand2 */; break;
					case GenericCursorType.Help: osId = 92 /* XC_question_arrow */; break;
					case GenericCursorType.Cross: osId = 34 /* XC_crosshair */; break;
					case GenericCursorType.Text: osId = 152 /* XC_xterm */; break;
					case GenericCursorType.Move: osId = 52 /* XC_fleur */; break;
					case GenericCursorType.UpArrow: osId = 22 /* XC_center_ptr */; break;
					case GenericCursorType.Progress: osId = 150 /* XC_watch, best i can do i think */; break;

					case GenericCursorType.NotAllowed: osId = 24 /* XC_circle. not great */; break;
					case GenericCursorType.SizeNesw: osId = 12 /* XC_bottom_left_corner */ ; break;
					case GenericCursorType.SizeNs: osId = 116 /* XC_sb_v_double_arrow */; break;
					case GenericCursorType.SizeNwse: osId = 14 /* XC_bottom_right_corner */; break;
					case GenericCursorType.SizeWe: osId = 108 /* XC_sb_h_double_arrow */; break;
				}

			} else featureNotImplemented();

			mc = new MouseCursor(osId);
		}
		return mc;
	}
}


/++
	If you want to get more control over the event loop, you can use this.

	Typically though, you can just call [SimpleWindow.eventLoop].
+/
struct EventLoop {
	@disable this();

	/// Gets a reference to an existing event loop
	static EventLoop get() {
		return EventLoop(0, null);
	}

	__gshared static Object monitor = new Object(); // deliberate CTFE usage here fyi

	/// Construct an application-global event loop for yourself
	/// See_Also: [SimpleWindow.setEventHandlers]
	this(long pulseTimeout, void delegate() handlePulse) {
		synchronized(monitor) {
			if(impl is null) {
				claimGuiThread();
				version(sdpy_thread_checks) assert(thisIsGuiThread);
				impl = new EventLoopImpl(pulseTimeout, handlePulse);
			} else {
				if(pulseTimeout) {
					impl.pulseTimeout = pulseTimeout;
					impl.handlePulse = handlePulse;
				}
			}
			impl.refcount++;
		}
	}

	~this() {
		if(impl is null)
			return;
		impl.refcount--;
		if(impl.refcount == 0) {
			impl.dispose();
			if(thisIsGuiThread)
				guiThreadFinalize();
		}

	}

	this(this) {
		if(impl is null)
			return;
		impl.refcount++;
	}

	/// Runs the event loop until the whileCondition, if present, returns false
	int run(bool delegate() whileCondition = null) {
		assert(impl !is null);
		impl.notExited = true;
		return impl.run(whileCondition);
	}

	/// Exits the event loop
	void exit() {
		assert(impl !is null);
		impl.notExited = false;
	}

	version(linux)
	ref void delegate(int) signalHandler() {
		assert(impl !is null);
		return impl.signalHandler;
	}

	__gshared static EventLoopImpl* impl;
}

version(linux)
	void delegate(int, int) globalHupHandler;

version(Posix)
	void makeNonBlocking(int fd) {
		import fcntl = core.sys.posix.fcntl;
		auto flags = fcntl.fcntl(fd, fcntl.F_GETFL, 0);
		if(flags == -1)
			throw new Exception("fcntl get");
		flags |= fcntl.O_NONBLOCK;
		auto s = fcntl.fcntl(fd, fcntl.F_SETFL, flags);
		if(s == -1)
			throw new Exception("fcntl set");
	}

struct EventLoopImpl {
	int refcount;

	bool notExited = true;

	version(linux) {
		static import ep = core.sys.linux.epoll;
		static import unix = core.sys.posix.unistd;
		static import err = core.stdc.errno;
		import core.sys.linux.timerfd;

		void delegate(int) signalHandler;
	}

	version(X11) {
		int pulseFd = -1;
		version(linux) ep.epoll_event[16] events = void;
	} else version(Windows) {
		Timer pulser;
		HANDLE[] handles;
	}


	/// "Lock" this window handle, to do multithreaded synchronization. You probably won't need
	/// to call this, as it's not recommended to share window between threads.
	void mtLock () {
		version(X11) {
			XLockDisplay(this.display);
		}
	}

	version(X11)
	auto display() { return XDisplayConnection.get; }

	/// "Unlock" this window handle, to do multithreaded synchronization. You probably won't need
	/// to call this, as it's not recommended to share window between threads.
	void mtUnlock () {
		version(X11) {
			XUnlockDisplay(this.display);
		}
	}

	version(with_eventloop)
	void initialize(long pulseTimeout) {}
	else
	void initialize(long pulseTimeout) {
		version(Windows) {
			if(pulseTimeout && handlePulse !is null)
				pulser = new Timer(cast(int) pulseTimeout, handlePulse);

			if (customEventH is null) {
				customEventH = CreateEvent(null, FALSE/*autoreset*/, FALSE/*initial state*/, null);
				if (customEventH !is null) {
					handles ~= customEventH;
				} else {
					// this is something that should not be; better be safe than sorry
					throw new Exception("can't create eventfd for custom event processing");
				}
			}

			SimpleWindow.processAllCustomEvents(); // process events added before event object creation
		}

		version(linux) {
			prepareEventLoop();
			{
				auto display = XDisplayConnection.get;
				// adding Xlib file
				ep.epoll_event ev = void;
				{ import core.stdc.string : memset; memset(&ev, 0, ev.sizeof); } // this makes valgrind happy
				ev.events = ep.EPOLLIN;
				ev.data.fd = display.fd;
				//import std.conv;
				if(ep.epoll_ctl(epollFd, ep.EPOLL_CTL_ADD, display.fd, &ev) == -1)
					throw new Exception("add x fd");// ~ to!string(epollFd));
				displayFd = display.fd;
			}

			if(pulseTimeout && handlePulse !is null) {
				pulseFd = timerfd_create(CLOCK_MONOTONIC, 0);
				if(pulseFd == -1)
					throw new Exception("pulse timer create failed");

				itimerspec value;
				value.it_value.tv_sec = cast(int) (pulseTimeout / 1000);
				value.it_value.tv_nsec = (pulseTimeout % 1000) * 1000_000;

				value.it_interval.tv_sec = cast(int) (pulseTimeout / 1000);
				value.it_interval.tv_nsec = (pulseTimeout % 1000) * 1000_000;

				if(timerfd_settime(pulseFd, 0, &value, null) == -1)
					throw new Exception("couldn't make pulse timer");

				ep.epoll_event ev = void;
				{ import core.stdc.string : memset; memset(&ev, 0, ev.sizeof); } // this makes valgrind happy
				ev.events = ep.EPOLLIN;
				ev.data.fd = pulseFd;
				ep.epoll_ctl(epollFd, ep.EPOLL_CTL_ADD, pulseFd, &ev);
			}

			// eventfd for custom events
			if (customEventFDWrite == -1) {
				customEventFDWrite = eventfd(0, 0);
				customEventFDRead = customEventFDWrite;
				if (customEventFDRead >= 0) {
					ep.epoll_event ev = void;
					{ import core.stdc.string : memset; memset(&ev, 0, ev.sizeof); } // this makes valgrind happy
					ev.events = ep.EPOLLIN;
					ev.data.fd = customEventFDRead;
					ep.epoll_ctl(epollFd, ep.EPOLL_CTL_ADD, customEventFDRead, &ev);
				} else {
					// this is something that should not be; better be safe than sorry
					throw new Exception("can't create eventfd for custom event processing");
				}
			}

			if (customSignalFD == -1) {
				import core.sys.linux.sys.signalfd;

				sigset_t sigset;
				auto err = sigemptyset(&sigset);
				assert(!err);
				err = sigaddset(&sigset, SIGINT);
				assert(!err);
				err = sigaddset(&sigset, SIGHUP);
				assert(!err);
				err = sigprocmask(SIG_BLOCK, &sigset, null);
				assert(!err);

				customSignalFD = signalfd(-1, &sigset, SFD_NONBLOCK);
				assert(customSignalFD != -1);

				ep.epoll_event ev = void;
				{ import core.stdc.string : memset; memset(&ev, 0, ev.sizeof); } // this makes valgrind happy
				ev.events = ep.EPOLLIN;
				ev.data.fd = customSignalFD;
				ep.epoll_ctl(epollFd, ep.EPOLL_CTL_ADD, customSignalFD, &ev);
			}
		} else version(Posix) {
			prepareEventLoop();
			if (customEventFDRead == -1) {
				int[2] bfr;
				import core.sys.posix.unistd;
				auto ret = pipe(bfr);
				if(ret == -1) throw new Exception("pipe");
				customEventFDRead = bfr[0];
				customEventFDWrite = bfr[1];
			}

		}

		SimpleWindow.processAllCustomEvents(); // process events added before event FD creation

		version(linux) {
			this.mtLock();
			scope(exit) this.mtUnlock();
			XPending(display); // no, really
		}

		disposed = false;
	}

	bool disposed = true;
	version(X11)
		int displayFd = -1;

	version(with_eventloop)
	void dispose() {}
	else
	void dispose() {
		disposed = true;
		version(X11) {
			if(pulseFd != -1) {
				import unix = core.sys.posix.unistd;
				unix.close(pulseFd);
				pulseFd = -1;
			}

				version(linux)
				if(displayFd != -1) {
					// clean up xlib fd when we exit, in case we come back later e.g. X disconnect and reconnect with new FD, don't want to still keep the old one around
					ep.epoll_event ev = void;
					{ import core.stdc.string : memset; memset(&ev, 0, ev.sizeof); } // this makes valgrind happy
					ev.events = ep.EPOLLIN;
					ev.data.fd = displayFd;
					//import std.conv;
					ep.epoll_ctl(epollFd, ep.EPOLL_CTL_DEL, displayFd, &ev);
					displayFd = -1;
				}

		} else version(Windows) {
			if(pulser !is null) {
				pulser.destroy();
				pulser = null;
			}
			if (customEventH !is null) {
				CloseHandle(customEventH);
				customEventH = null;
			}
		}
	}

	this(long pulseTimeout, void delegate() handlePulse) {
		this.pulseTimeout = pulseTimeout;
		this.handlePulse = handlePulse;
		initialize(pulseTimeout);
	}

	private long pulseTimeout;
	void delegate() handlePulse;

	~this() {
		dispose();
	}

	version(Posix)
	ref int customEventFDRead() { return SimpleWindow.customEventFDRead; }
	version(Posix)
	ref int customEventFDWrite() { return SimpleWindow.customEventFDWrite; }
	version(linux)
	ref int customSignalFD() { return SimpleWindow.customSignalFD; }
	version(Windows)
	ref auto customEventH() { return SimpleWindow.customEventH; }

	version(with_eventloop) {
		int loopHelper(bool delegate() whileCondition) {
			// FIXME: whileCondition
			import arsd.eventloop;
			loop();
			return 0;
		}
	} else
	int loopHelper(bool delegate() whileCondition) {
		version(X11) {
			bool done = false;

			XFlush(display);
			insideXEventLoop = true;
			scope(exit) insideXEventLoop = false;

			version(linux) {
				while(!done && (whileCondition is null || whileCondition() == true) && notExited) {
					bool forceXPending = false;
					auto wto = SimpleWindow.eventAllQueueTimeoutMSecs();
					// eh... some events may be queued for "squashing" (or "late delivery"), so we have to do the following magic
					{
						this.mtLock();
						scope(exit) this.mtUnlock();
						if (XEventsQueued(this.display, QueueMode.QueuedAlready)) { forceXPending = true; if (wto > 10 || wto <= 0) wto = 10; } // so libX event loop will be able to do it's work
					}
					//{ import core.stdc.stdio; printf("*** wto=%d; force=%d\n", wto, (forceXPending ? 1 : 0)); }
					auto nfds = ep.epoll_wait(epollFd, events.ptr, events.length, (wto == 0 || wto >= int.max ? -1 : cast(int)wto));
					if(nfds == -1) {
						if(err.errno == err.EINTR) {
							//if(forceXPending) goto xpending;
							continue; // interrupted by signal, just try again
						}
						throw new Exception("epoll wait failure");
					}

					SimpleWindow.processAllCustomEvents(); // anyway
					//version(sdddd) { import std.stdio; writeln("nfds=", nfds, "; [0]=", events[0].data.fd); }
					foreach(idx; 0 .. nfds) {
						if(done) break;
						auto fd = events[idx].data.fd;
						assert(fd != -1); // should never happen cuz the api doesn't do that but better to assert than assume.
						auto flags = events[idx].events;
						if(flags & ep.EPOLLIN) {
							if (fd == customSignalFD) {
								version(linux) {
									import core.sys.linux.sys.signalfd;
									import core.sys.posix.unistd : read;
									signalfd_siginfo info;
									read(customSignalFD, &info, info.sizeof);

									auto sig = info.ssi_signo;

									if(EventLoop.get.signalHandler !is null) {
										EventLoop.get.signalHandler()(sig);
									} else {
										EventLoop.get.exit();
									}
								}
							} else if(fd == display.fd) {
								version(sdddd) { import std.stdio; writeln("X EVENT PENDING!"); }
								this.mtLock();
								scope(exit) this.mtUnlock();
								while(!done && XPending(display)) {
									done = doXNextEvent(this.display);
								}
								forceXPending = false;
							} else if(fd == pulseFd) {
								long expirationCount;
								// if we go over the count, I ignore it because i don't want the pulse to go off more often and eat tons of cpu time...

								handlePulse();

								// read just to clear the buffer so poll doesn't trigger again
								// BTW I read AFTER the pulse because if the pulse handler takes
								// a lot of time to execute, we don't want the app to get stuck
								// in a loop of timer hits without a chance to do anything else
								//
								// IOW handlePulse happens at most once per pulse interval.
								unix.read(pulseFd, &expirationCount, expirationCount.sizeof);
								forceXPending = true; // some events might have been added while the pulse was going off and xlib already read it from the fd (like as a result of a draw done in the timer handler). if so we need to flush that separately to ensure it is not delayed
							} else if (fd == customEventFDRead) {
								// we have some custom events; process 'em
								import core.sys.posix.unistd : read;
								ulong n;
								read(customEventFDRead, &n, n.sizeof); // reset counter value to zero again
								//{ import core.stdc.stdio; printf("custom event! count=%u\n", eventQueueUsed); }
								//SimpleWindow.processAllCustomEvents();
							} else {
								// some other timer
								version(sdddd) { import std.stdio; writeln("unknown fd: ", fd); }

								if(Timer* t = fd in Timer.mapping)
									(*t).trigger();

								if(PosixFdReader* pfr = fd in PosixFdReader.mapping)
									(*pfr).ready(flags);

								// or i might add support for other FDs too
								// but for now it is just timer
								// (if you want other fds, use arsd.eventloop and compile with -version=with_eventloop), it offers a fuller api for arbitrary stuff.
							}
						}
						if(flags & ep.EPOLLHUP) {
							if(PosixFdReader* pfr = fd in PosixFdReader.mapping)
								(*pfr).hup(flags);
							if(globalHupHandler)
								globalHupHandler(fd, flags);
						}
						/+
						} else {
							// not interested in OUT, we are just reading here.
							//
							// error or hup might also be reported
							// but it shouldn't here since we are only
							// using a few types of FD and Xlib will report
							// if it dies.
							// so instead of thoughtfully handling it, I'll
							// just throw. for now at least

							throw new Exception("epoll did something else");
						}
						+/
					}
					// if we won't call `XPending()` here, libX may delay some internal event delivery.
					// i.e. we HAVE to repeatedly call `XPending()` even if libX fd wasn't signalled!
					xpending:
					if (!done && forceXPending) {
						this.mtLock();
						scope(exit) this.mtUnlock();
						//{ import core.stdc.stdio; printf("*** queued: %d\n", XEventsQueued(this.display, QueueMode.QueuedAlready)); }
						while(!done && XPending(display)) {
							done = doXNextEvent(this.display);
						}
					}
				}
			} else {
				// Generic fallback: yes to simple pulse support,
				// but NO timer support!

				// FIXME: we could probably support the POSIX timer_create
				// signal-based option, but I'm in no rush to write it since
				// I prefer the fd-based functions.
				while (!done && (whileCondition is null || whileCondition() == true) && notExited) {

					import core.sys.posix.poll;

					pollfd[] pfds;
					pollfd[32] pfdsBuffer;
					auto len = PosixFdReader.mapping.length + 2;
					// FIXME: i should just reuse the buffer
					if(len < pfdsBuffer.length)
						pfds = pfdsBuffer[0 .. len];
					else
						pfds = new pollfd[](len);

					pfds[0].fd = display.fd;
					pfds[0].events = POLLIN;
					pfds[0].revents = 0;

					int slot = 1;

					if(customEventFDRead != -1) {
						pfds[slot].fd = customEventFDRead;
						pfds[slot].events = POLLIN;
						pfds[slot].revents = 0;

						slot++;
					}

					foreach(fd, obj; PosixFdReader.mapping) {
						if(!obj.enabled) continue;
						pfds[slot].fd = fd;
						pfds[slot].events = POLLIN;
						pfds[slot].revents = 0;

						slot++;
					}

					auto ret = poll(pfds.ptr, slot, pulseTimeout > 0 ? cast(int) pulseTimeout : -1);
					if(ret == -1) throw new Exception("poll");

					if(ret == 0) {
						// FIXME it may not necessarily time out if events keep coming
						if(handlePulse !is null)
							handlePulse();
					} else {
						foreach(s; 0 .. slot) {
							if(pfds[s].revents == 0) continue;

							if(pfds[s].fd == display.fd) {
								while(!done && XPending(display)) {
									this.mtLock();
									scope(exit) this.mtUnlock();
									done = doXNextEvent(this.display);
								}
							} else if(customEventFDRead != -1 && pfds[s].fd == customEventFDRead) {

								import core.sys.posix.unistd : read;
								ulong n;
								read(customEventFDRead, &n, n.sizeof);
								SimpleWindow.processAllCustomEvents();
							} else {
								auto obj = PosixFdReader.mapping[pfds[s].fd];
								if(pfds[s].revents & POLLNVAL) {
									obj.dispose();
								} else {
									obj.ready(pfds[s].revents);
								}
							}

							ret--;
							if(ret == 0) break;
						}
					}
				}
			}
		}
		
		version(Windows) {
			int ret = -1;
			MSG message;
			while(ret != 0 && (whileCondition is null || whileCondition() == true) && notExited) {
				eventLoopRound++;
				auto wto = SimpleWindow.eventAllQueueTimeoutMSecs();
				auto waitResult = MsgWaitForMultipleObjectsEx(
					cast(int) handles.length, handles.ptr,
					(wto == 0 ? INFINITE : wto), /* timeout */
					0x04FF, /* QS_ALLINPUT */
					0x0002 /* MWMO_ALERTABLE */ | 0x0004 /* MWMO_INPUTAVAILABLE */);

				SimpleWindow.processAllCustomEvents(); // anyway
				enum WAIT_OBJECT_0 = 0;
				if(waitResult >= WAIT_OBJECT_0 && waitResult < handles.length + WAIT_OBJECT_0) {
					auto h = handles[waitResult - WAIT_OBJECT_0];
					if(auto e = h in WindowsHandleReader.mapping) {
						(*e).ready();
					}
				} else if(waitResult == handles.length + WAIT_OBJECT_0) {
					// message ready
					while(PeekMessage(&message, null, 0, 0, PM_NOREMOVE)) { // need to peek since sometimes MsgWaitForMultipleObjectsEx returns even though GetMessage can block. tbh i don't fully understand it but the docs say it is foreground activation
						ret = GetMessage(&message, null, 0, 0);
						if(ret == -1)
							throw new Exception("GetMessage failed");
						TranslateMessage(&message);
						DispatchMessage(&message);

						if(ret == 0) // WM_QUIT
							break;
					}
				} else if(waitResult == 0x000000C0L /* WAIT_IO_COMPLETION */) {
					SleepEx(0, true); // I call this to give it a chance to do stuff like async io
				} else if(waitResult == 258L /* WAIT_TIMEOUT */) {
					// timeout, should never happen since we aren't using it
				} else if(waitResult == 0xFFFFFFFF) {
						// failed
						throw new Exception("MsgWaitForMultipleObjectsEx failed");
				} else {
					// idk....
				}
			}

			// return message.wParam;
			return 0;
		} else {
			return 0;
		}
	}

	int run(bool delegate() whileCondition = null) {
		if(disposed)
			initialize(this.pulseTimeout);

		version(X11) {
			try {
				return loopHelper(whileCondition);
			} catch(XDisconnectException e) {
				if(e.userRequested) {
					foreach(item; CapableOfHandlingNativeEvent.nativeHandleMapping)
						item.discardConnectionState();
					XCloseDisplay(XDisplayConnection.display);
				}

				XDisplayConnection.display = null;

				this.dispose();

				throw e;
			}
		} else {
			return loopHelper(whileCondition);
		}
	}
}


/++
	Provides an icon on the system notification area (also known as the system tray).


	If a notification area is not available with the NotificationIcon object is created,
	it will silently succeed and simply attempt to create one when an area becomes available.


	NotificationAreaIcon on Windows assumes you are on Windows Vista or later.
	If this is wrong, pass -version=WindowsXP to dmd when compiling and it will
	use the older version.
+/
version(OSXCocoa) {} else // NotYetImplementedException
class NotificationAreaIcon : CapableOfHandlingNativeEvent {

	version(X11) {
		void recreateAfterDisconnect() {
			stateDiscarded = false;
			clippixmap = None;
			throw new Exception("NOT IMPLEMENTED");
		}

		bool stateDiscarded;
		void discardConnectionState() {
			stateDiscarded = true;
		}
	}


	version(X11) {
		Image img;

		NativeEventHandler getNativeEventHandler() {
			return delegate int(XEvent e) {
				switch(e.type) {
					case EventType.Expose:
					//case EventType.VisibilityNotify:
						redraw();
					break;
					case EventType.ClientMessage:
						version(sddddd) {
						import std.stdio;
						writeln("\t", e.xclient.message_type == GetAtom!("_XEMBED")(XDisplayConnection.get));
						writeln("\t", e.xclient.format);
						writeln("\t", e.xclient.data.l);
						}
					break;
					case EventType.ButtonPress:
						auto event = e.xbutton;
						if (onClick !is null || onClickEx !is null) {
							MouseButton mb = cast(MouseButton)0;
							switch (event.button) {
								case 1: mb = MouseButton.left; break; // left
								case 2: mb = MouseButton.middle; break; // middle
								case 3: mb = MouseButton.right; break; // right
								case 4: mb = MouseButton.wheelUp; break; // scroll up
								case 5: mb = MouseButton.wheelDown; break; // scroll down
								case 6: break; // idk
								case 7: break; // idk
								case 8: mb = MouseButton.backButton; break;
								case 9: mb = MouseButton.forwardButton; break;
								default:
							}
							if (mb) {
								try { onClick()(mb); } catch (Exception) {}
								if (onClickEx !is null) try { onClickEx(event.x_root, event.y_root, mb, cast(ModifierState)event.state); } catch (Exception) {}
							}
						}
					break;
					case EventType.EnterNotify:
						if (onEnter !is null) {
							onEnter(e.xcrossing.x_root, e.xcrossing.y_root, cast(ModifierState)e.xcrossing.state);
						}
						break;
					case EventType.LeaveNotify:
						if (onLeave !is null) try { onLeave(); } catch (Exception) {}
						break;
					case EventType.DestroyNotify:
						active = false;
						CapableOfHandlingNativeEvent.nativeHandleMapping.remove(nativeHandle);
					break;
					case EventType.ConfigureNotify:
						auto event = e.xconfigure;
						this.width = event.width;
						this.height = event.height;
						//import std.stdio; writeln(width, " x " , height, " @ ", event.x, " ", event.y);
						redraw();
					break;
					default: return 1;
				}
				return 1;
			};
		}

		/* private */ void hideBalloon() {
			balloon.close();
			version(with_timer)
				timer.destroy();
			balloon = null;
			version(with_timer)
				timer = null;
		}

		void redraw() {
			if (!active) return;

			auto display = XDisplayConnection.get;
			auto gc = DefaultGC(display, DefaultScreen(display));
			XClearWindow(display, nativeHandle);

			XSetClipMask(display, gc, clippixmap);

			XSetForeground(display, gc,
				cast(uint) 0 << 16 |
				cast(uint) 0 << 8 |
				cast(uint) 0);
			XFillRectangle(display, nativeHandle, gc, 0, 0, width, height);

			if (img is null) {
				XSetForeground(display, gc,
					cast(uint) 0 << 16 |
					cast(uint) 127 << 8 |
					cast(uint) 0);
				XFillArc(display, nativeHandle,
					gc, width / 4, height / 4, width * 2 / 4, height * 2 / 4, 0 * 64, 360 * 64);
			} else {
				int dx = 0;
				int dy = 0;
				if(width > img.width)
					dx = (width - img.width) / 2;
				if(height > img.height)
					dy = (height - img.height) / 2;
				XSetClipOrigin(display, gc, dx, dy);

				if (img.usingXshm)
					XShmPutImage(display, cast(Drawable)nativeHandle, gc, img.handle, 0, 0, dx, dy, img.width, img.height, false);
				else
					XPutImage(display, cast(Drawable)nativeHandle, gc, img.handle, 0, 0, dx, dy, img.width, img.height);
			}
			XSetClipMask(display, gc, None);
			flushGui();
		}

		static Window getTrayOwner() {
			auto display = XDisplayConnection.get;
			auto i = cast(int) DefaultScreen(display);
			if(i < 10 && i >= 0) {
				static Atom atom;
				if(atom == None)
					atom = XInternAtom(display, cast(char*) ("_NET_SYSTEM_TRAY_S"~(cast(char) (i + '0')) ~ '\0').ptr, false);
				return XGetSelectionOwner(display, atom);
			}
			return None;
		}

		static void sendTrayMessage(arch_long message, arch_long d1, arch_long d2, arch_long d3) {
			auto to = getTrayOwner();
			auto display = XDisplayConnection.get;
			XEvent ev;
			ev.xclient.type = EventType.ClientMessage;
			ev.xclient.window = to;
			ev.xclient.message_type = GetAtom!("_NET_SYSTEM_TRAY_OPCODE", true)(display);
			ev.xclient.format = 32;
			ev.xclient.data.l[0] = CurrentTime;
			ev.xclient.data.l[1] = message;
			ev.xclient.data.l[2] = d1;
			ev.xclient.data.l[3] = d2;
			ev.xclient.data.l[4] = d3;

			XSendEvent(XDisplayConnection.get, to, false, EventMask.NoEventMask, &ev);
		}

		private static NotificationAreaIcon[] activeIcons;

		// FIXME: possible leak with this stuff, should be able to clear it and stuff.
		private void newManager() {
			close();
			createXWin();

			if(this.clippixmap)
				XFreePixmap(XDisplayConnection.get, clippixmap);
			if(this.originalMemoryImage)
				this.icon = this.originalMemoryImage;
			else if(this.img)
				this.icon = this.img;
		}

		private void createXWin () {
			// create window
			auto display = XDisplayConnection.get;

			// to check for MANAGER on root window to catch new/changed tray owners
			XDisplayConnection.addRootInput(EventMask.StructureNotifyMask);
			// so if a thing does appear, we can handle it
			foreach(ai; activeIcons)
				if(ai is this)
					goto alreadythere;
			activeIcons ~= this;
			alreadythere:

			// and check for an existing tray
			auto trayOwner = getTrayOwner();
			if(trayOwner == None)
				return;
				//throw new Exception("No notification area found");

			Visual* v = cast(Visual*) CopyFromParent;
			/+
			auto visualProp = getX11PropertyData(trayOwner, GetAtom!("_NET_SYSTEM_TRAY_VISUAL", true)(display));
			if(visualProp !is null) {
				c_ulong[] info = cast(c_ulong[]) visualProp;
				if(info.length == 1) {
					auto vid = info[0];
					int returned;
					XVisualInfo t;
					t.visualid = vid;
					auto got = XGetVisualInfo(display, VisualIDMask, &t, &returned);
					if(got !is null) {
						if(returned == 1) {
							v = got.visual;
							import std.stdio;
							writeln("using special visual ", *got);
						}
						XFree(got);
					}
				}
			}
			+/

			auto nativeWindow = XCreateWindow(display, RootWindow(display, DefaultScreen(display)), 0, 0, 16, 16, 0, 24, InputOutput, v, 0, null);
			assert(nativeWindow);

			XSetWindowBackgroundPixmap(display, nativeWindow, 1 /* ParentRelative */);

			nativeHandle = nativeWindow;

			///+
			arch_ulong[2] info;
			info[0] = 0;
			info[1] = 1;

			string title = this.name is null ? "simpledisplay.d program" : this.name;
			auto XA_UTF8 = XInternAtom(display, "UTF8_STRING".ptr, false);
			auto XA_NETWM_NAME = XInternAtom(display, "_NET_WM_NAME".ptr, false);
			XChangeProperty(display, nativeWindow, XA_NETWM_NAME, XA_UTF8, 8, PropModeReplace, title.ptr, cast(uint)title.length);

			XChangeProperty(
				display,
				nativeWindow,
				GetAtom!("_XEMBED_INFO", true)(display),
				GetAtom!("_XEMBED_INFO", true)(display),
				32 /* bits */,
				0 /*PropModeReplace*/,
				info.ptr,
				2);

			import core.sys.posix.unistd;
			arch_ulong pid = getpid();

			XChangeProperty(
				display,
				nativeWindow,
				GetAtom!("_NET_WM_PID", true)(display),
				XA_CARDINAL,
				32 /* bits */,
				0 /*PropModeReplace*/,
				&pid,
				1);

			updateNetWmIcon();

			if (sdpyWindowClassStr !is null && sdpyWindowClassStr[0]) {
				//{ import core.stdc.stdio; printf("winclass: [%s]\n", sdpyWindowClassStr); }
				XClassHint klass;
				XWMHints wh;
				XSizeHints size;
				klass.res_name = sdpyWindowClassStr;
				klass.res_class = sdpyWindowClassStr;
				XSetWMProperties(display, nativeWindow, null, null, null, 0, &size, &wh, &klass);
			}

				// believe it or not, THIS is what xfce needed for the 9999 issue
				XSizeHints sh;
					c_long spr;
					XGetWMNormalHints(display, nativeWindow, &sh, &spr);
					sh.flags |= PMaxSize | PMinSize;
				// FIXME maybe nicer resizing
				sh.min_width = 16;
				sh.min_height = 16;
				sh.max_width = 16;
				sh.max_height = 16;
				XSetWMNormalHints(display, nativeWindow, &sh);


			//+/


			XSelectInput(display, nativeWindow,
				EventMask.ButtonPressMask | EventMask.ExposureMask | EventMask.StructureNotifyMask | EventMask.VisibilityChangeMask |
				EventMask.EnterWindowMask | EventMask.LeaveWindowMask);

			sendTrayMessage(SYSTEM_TRAY_REQUEST_DOCK, nativeWindow, 0, 0);
			CapableOfHandlingNativeEvent.nativeHandleMapping[nativeWindow] = this;
			active = true;
		}

		void updateNetWmIcon() {
			if(img is null) return;
			auto display = XDisplayConnection.get;
			// FIXME: ensure this is correct
			arch_ulong[] buffer;
			auto imgMi = img.toTrueColorImage;
			buffer ~= imgMi.width;
			buffer ~= imgMi.height;
			foreach(c; imgMi.imageData.colors) {
				arch_ulong b;
				b |= c.a << 24;
				b |= c.r << 16;
				b |= c.g << 8;
				b |= c.b;
				buffer ~= b;
			}

			XChangeProperty(
				display,
				nativeHandle,
				GetAtom!"_NET_WM_ICON"(display),
				GetAtom!"CARDINAL"(display),
				32 /* bits */,
				0 /*PropModeReplace*/,
				buffer.ptr,
				cast(int) buffer.length);
		}



		private SimpleWindow balloon;
		version(with_timer)
		private Timer timer;

		private Window nativeHandle;
		private Pixmap clippixmap = None;
		private int width = 16;
		private int height = 16;
		private bool active = false;

		void delegate (int x, int y, MouseButton button, ModifierState mods) onClickEx; /// x and y are globals (relative to root window). X11 only.
		void delegate (int x, int y, ModifierState mods) onEnter; /// x and y are global window coordinates. X11 only.
		void delegate () onLeave; /// X11 only.

		@property bool closed () const pure nothrow @safe @nogc { return !active; } ///

		/// X11 only. Get global window coordinates and size. This can be used to show various notifications.
		void getWindowRect (out int x, out int y, out int width, out int height) {
			if (!active) { width = 1; height = 1; return; } // 1: just in case
			Window dummyw;
			auto dpy = XDisplayConnection.get;
			//XWindowAttributes xwa;
			//XGetWindowAttributes(dpy, nativeHandle, &xwa);
			//XTranslateCoordinates(dpy, nativeHandle, RootWindow(dpy, DefaultScreen(dpy)), xwa.x, xwa.y, &x, &y, &dummyw);
			XTranslateCoordinates(dpy, nativeHandle, RootWindow(dpy, DefaultScreen(dpy)), x, y, &x, &y, &dummyw);
			width = this.width;
			height = this.height;
		}
	}

	/+
		What I actually want from this:

		* set / change: icon, tooltip
		* handle: mouse click, right click
		* show: notification bubble.
	+/

	version(Windows) {
		WindowsIcon win32Icon;
		HWND hwnd;

		NOTIFYICONDATAW data;

		NativeEventHandler getNativeEventHandler() {
			return delegate int(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
				if(msg == WM_USER) {
					auto event = LOWORD(lParam);
					auto iconId = HIWORD(lParam);
					//auto x = GET_X_LPARAM(wParam);
					//auto y = GET_Y_LPARAM(wParam);
					switch(event) {
						case WM_LBUTTONDOWN:
							onClick()(MouseButton.left);
						break;
						case WM_RBUTTONDOWN:
							onClick()(MouseButton.right);
						break;
						case WM_MBUTTONDOWN:
							onClick()(MouseButton.middle);
						break;
						case WM_MOUSEMOVE:
							// sent, we could use it.
						break;
						case WM_MOUSEWHEEL:
							// NOT SENT
						break;
						//case NIN_KEYSELECT:
						//case NIN_SELECT:
						//break;
						default: {}
					}
				}
				return 0;
			};
		}

		enum NIF_SHOWTIP = 0x00000080;

		private static struct NOTIFYICONDATAW {
			DWORD cbSize;
			HWND  hWnd;
			UINT  uID;
			UINT  uFlags;
			UINT  uCallbackMessage;
			HICON hIcon;
			WCHAR[128] szTip;
			DWORD dwState;
			DWORD dwStateMask;
			WCHAR[256] szInfo;
			union {
				UINT uTimeout;
				UINT uVersion;
			}
			WCHAR[64] szInfoTitle;
			DWORD dwInfoFlags;
			GUID  guidItem;
			HICON hBalloonIcon;
		}

	}

	/++
		Note that on Windows, only left, right, and middle buttons are sent.
		Mouse wheel buttons are NOT set, so don't rely on those events if your
		program is meant to be used on Windows too.
	+/
	this(string name, MemoryImage icon, void delegate(MouseButton button) onClick) {
		// The canonical constructor for Windows needs the MemoryImage, so it is here,
		// but on X, we need an Image, so its canonical ctor is there. They should
		// forward to each other though.
		version(X11) {
			this.name = name;
			this.onClick = onClick;
			createXWin();
			this.icon = icon;
		} else version(Windows) {
			this.onClick = onClick;
			this.win32Icon = new WindowsIcon(icon);

			HINSTANCE hInstance = cast(HINSTANCE) GetModuleHandle(null);

			static bool registered = false;
			if(!registered) {
				WNDCLASSEX wc;
				wc.cbSize = wc.sizeof;
				wc.hInstance = hInstance;
				wc.lpfnWndProc = &WndProc;
				wc.lpszClassName = "arsd_simpledisplay_notification_icon"w.ptr;
				if(!RegisterClassExW(&wc))
					throw new WindowsApiException("RegisterClass");
				registered = true;
			}

			this.hwnd = CreateWindowW("arsd_simpledisplay_notification_icon"w.ptr, "test"w.ptr /* name */, 0 /* dwStyle */, 0, 0, 0, 0, HWND_MESSAGE, null, hInstance, null);
			if(hwnd is null)
				throw new Exception("CreateWindow");

			data.cbSize = data.sizeof;
			data.hWnd = hwnd;
			data.uID = cast(uint) cast(void*) this;
			data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_STATE | NIF_SHOWTIP /* use default tooltip, for now. */;
				// NIF_INFO means show balloon
			data.uCallbackMessage = WM_USER;
			data.hIcon = this.win32Icon.hIcon;
			data.szTip = ""; // FIXME
			data.dwState = 0; // NIS_HIDDEN; // windows vista
			data.dwStateMask = NIS_HIDDEN; // windows vista

			data.uVersion = 4; // NOTIFYICON_VERSION_4; // Windows Vista and up


			Shell_NotifyIcon(NIM_ADD, cast(NOTIFYICONDATA*) &data);

			CapableOfHandlingNativeEvent.nativeHandleMapping[this.hwnd] = this;
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	/// ditto
	this(string name, Image icon, void delegate(MouseButton button) onClick) {
		version(X11) {
			this.onClick = onClick;
			this.name = name;
			createXWin();
			this.icon = icon;
		} else version(Windows) {
			this(name, icon is null ? null : icon.toTrueColorImage(), onClick);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	version(X11) {
		/++
			X-specific extension (for now at least)
		+/
		this(string name, MemoryImage icon, void delegate(int x, int y, MouseButton button, ModifierState mods) onClickEx) {
			this.onClickEx = onClickEx;
			createXWin();
			if (icon !is null) this.icon = icon;
		}

		/// ditto
		this(string name, Image icon, void delegate(int x, int y, MouseButton button, ModifierState mods) onClickEx) {
			this.onClickEx = onClickEx;
			createXWin();
			this.icon = icon;
		}
	}

	private void delegate (MouseButton button) onClick_;

	///
	@property final void delegate(MouseButton) onClick() {
		if(onClick_ is null)
			onClick_ = delegate void(MouseButton) {};
		return onClick_;
	}

	/// ditto
	@property final void onClick(void delegate(MouseButton) handler) {
		// I made this a property setter so we can wrap smaller arg
		// delegates and just forward all to onClickEx or something.
		onClick_ = handler;
	}


	string name_;
	@property void name(string n) {
		name_ = n;
	}

	@property string name() {
		return name_;
	}

	private MemoryImage originalMemoryImage;

	///
	@property void icon(MemoryImage i) {
		version(X11) {
			this.originalMemoryImage = i;
			if (!active) return;
			if (i !is null) {
				this.img = Image.fromMemoryImage(i);
				this.clippixmap = transparencyMaskFromMemoryImage(i, nativeHandle);
				//import std.stdio; writeln("using pixmap ", clippixmap);
				updateNetWmIcon();
				redraw();
			} else {
				if (this.img !is null) {
					this.img = null;
					redraw();
				}
			}
		} else version(Windows) {
			this.win32Icon = new WindowsIcon(i);

			data.uFlags = NIF_ICON;
			data.hIcon = this.win32Icon.hIcon;

			Shell_NotifyIcon(NIM_MODIFY, cast(NOTIFYICONDATA*) &data);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	/// ditto
	@property void icon (Image i) {
		version(X11) {
			if (!active) return;
			if (i !is img) {
				originalMemoryImage = null;
				img = i;
				redraw();
			}
		} else version(Windows) {
			this.icon(i is null ? null : i.toTrueColorImage());
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	/++
		Shows a balloon notification. You can only show one balloon at a time, if you call
		it twice while one is already up, the first balloon will be replaced.
		
		
		The user is free to block notifications and they will automatically disappear after
		a timeout period.

		Params:
			title = Title of the notification. Must be 40 chars or less or the OS may truncate it.
			message = The message to pop up. Must be 220 chars or less or the OS may truncate it.
			icon = the icon to display with the notification. If null, it uses your existing icon.
			onclick = delegate called if the user clicks the balloon. (not yet implemented)
			timeout = your suggested timeout period. The operating system is free to ignore your suggestion.
	+/
	void showBalloon(string title, string message, MemoryImage icon = null, void delegate() onclick = null, int timeout = 2_500) {
		bool useCustom = true;
		version(libnotify) {
			if(onclick is null) // libnotify impl doesn't support callbacks yet because it doesn't do a dbus message loop
			try {
				if(!active) return;

				if(libnotify is null) {
					libnotify = new C_DynamicLibrary("libnotify.so");
					libnotify.call!("notify_init", int, const char*)()((ApplicationName ~ "\0").ptr);
				}

				auto n = libnotify.call!("notify_notification_new", void*, const char*, const char*, const char*)()((title~"\0").ptr, (message~"\0").ptr, null /* icon */);

				libnotify.call!("notify_notification_set_timeout", void, void*, int)()(n, timeout);

				if(onclick) {
					libnotify_action_delegates[libnotify_action_delegates_count] = onclick;
					libnotify.call!("notify_notification_add_action", void, void*, const char*, const char*, typeof(&libnotify_action_callback_sdpy), void*, void*)()(n, "DEFAULT".ptr, "Go".ptr, &libnotify_action_callback_sdpy, cast(void*) libnotify_action_delegates_count, null);
					libnotify_action_delegates_count++;
				}

				// FIXME icon

				// set hint image-data
				// set default action for onclick

				void* error;
				libnotify.call!("notify_notification_show", bool, void*, void**)()(n, &error);

				useCustom = false;
			} catch(Exception e) {

			}
		}
		
		version(X11) {
		if(useCustom) {
			if(!active) return;
			if(balloon) {
				hideBalloon();
			}
			// I know there are two specs for this, but one is never
			// implemented by any window manager I have ever seen, and
			// the other is a bloated mess and too complicated for simpledisplay...
			// so doing my own little window instead.
			balloon = new SimpleWindow(380, 120, null, OpenGlOptions.no, Resizability.fixedSize, WindowTypes.notification, WindowFlags.dontAutoShow/*, window*/);

			int x, y, width, height;
			getWindowRect(x, y, width, height);

			int bx = x - balloon.width;
			int by = y - balloon.height;
			if(bx < 0)
				bx = x + width + balloon.width;
			if(by < 0)
				by = y + height;

			// just in case, make sure it is actually on scren
			if(bx < 0)
				bx = 0;
			if(by < 0)
				by = 0;

			balloon.move(bx, by);
			auto painter = balloon.draw();
			painter.fillColor = Color(220, 220, 220);
			painter.outlineColor = Color.black;
			painter.drawRectangle(Point(0, 0), balloon.width, balloon.height);
			auto iconWidth = icon is null ? 0 : icon.width;
			if(icon)
				painter.drawImage(Point(4, 4), Image.fromMemoryImage(icon));
			iconWidth += 6; // margin around the icon

			// draw a close button
			painter.outlineColor = Color(44, 44, 44);
			painter.fillColor = Color(255, 255, 255);
			painter.drawRectangle(Point(balloon.width - 15, 3), 13, 13);
			painter.pen = Pen(Color.black, 3);
			painter.drawLine(Point(balloon.width - 14, 4), Point(balloon.width - 4, 14));
			painter.drawLine(Point(balloon.width - 4, 4), Point(balloon.width - 14, 13));
			painter.pen = Pen(Color.black, 1);
			painter.fillColor = Color(220, 220, 220);

			// Draw the title and message
			painter.drawText(Point(4 + iconWidth, 4), title);
			painter.drawLine(
				Point(4 + iconWidth, 4 + painter.fontHeight + 1),
				Point(balloon.width - 4, 4 + painter.fontHeight + 1),
			);
			painter.drawText(Point(4 + iconWidth, 4 + painter.fontHeight + 4), message);

			balloon.setEventHandlers(
				(MouseEvent ev) {
					if(ev.type == MouseEventType.buttonPressed) {
						if(ev.x > balloon.width - 16 && ev.y < 16)
							hideBalloon();
						else if(onclick)
							onclick();
					}
				}
			);
			balloon.show();

			version(with_timer)
			timer = new Timer(timeout, &hideBalloon);
			else {} // FIXME
		}
		} else version(Windows) {
			enum NIF_INFO = 0x00000010;

			data.uFlags = NIF_INFO;

			// FIXME: go back to the last valid unicode code point
			if(title.length > 40)
				title = title[0 .. 40];
			if(message.length > 220)
				message = message[0 .. 220];

			enum NIIF_RESPECT_QUIET_TIME = 0x00000080;
			enum NIIF_LARGE_ICON  = 0x00000020;
			enum NIIF_NOSOUND = 0x00000010;
			enum NIIF_USER = 0x00000004;
			enum NIIF_ERROR = 0x00000003;
			enum NIIF_WARNING = 0x00000002;
			enum NIIF_INFO = 0x00000001;
			enum NIIF_NONE = 0;

			WCharzBuffer t = WCharzBuffer(title);
			WCharzBuffer m = WCharzBuffer(message);

			t.copyInto(data.szInfoTitle);
			m.copyInto(data.szInfo);
			data.dwInfoFlags = NIIF_RESPECT_QUIET_TIME;

			if(icon !is null) {
				auto i = new WindowsIcon(icon);
				data.hBalloonIcon = i.hIcon;
				data.dwInfoFlags |= NIIF_USER;
			}

			Shell_NotifyIcon(NIM_MODIFY, cast(NOTIFYICONDATA*) &data);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	///
	//version(Windows)
	void show() {
		version(X11) {
			if(!hidden)
				return;
			sendTrayMessage(SYSTEM_TRAY_REQUEST_DOCK, nativeHandle, 0, 0);
			hidden = false;
		} else version(Windows) {
			data.uFlags = NIF_STATE;
			data.dwState = 0; // NIS_HIDDEN; // windows vista
			data.dwStateMask = NIS_HIDDEN; // windows vista
			Shell_NotifyIcon(NIM_MODIFY, cast(NOTIFYICONDATA*) &data);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	version(X11)
		bool hidden = false;

	///
	//version(Windows)
	void hide() {
		version(X11) {
			if(hidden)
				return;
			hidden = true;
			XUnmapWindow(XDisplayConnection.get, nativeHandle);
		} else version(Windows) {
			data.uFlags = NIF_STATE;
			data.dwState = NIS_HIDDEN; // windows vista
			data.dwStateMask = NIS_HIDDEN; // windows vista
			Shell_NotifyIcon(NIM_MODIFY, cast(NOTIFYICONDATA*) &data);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	///
	void close () {
		version(X11) {
			if (active) {
				active = false; // event handler will set this too, but meh
				XUnmapWindow(XDisplayConnection.get, nativeHandle); // 'cause why not; let's be polite
				XDestroyWindow(XDisplayConnection.get, nativeHandle);
				flushGui();
			}
		} else version(Windows) {
			Shell_NotifyIcon(NIM_DELETE, cast(NOTIFYICONDATA*) &data);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	~this() {
		version(X11)
			if(clippixmap != None)
				XFreePixmap(XDisplayConnection.get, clippixmap);
		close();
	}
}

version(X11)
/// Call `XFreePixmap` on the return value.
Pixmap transparencyMaskFromMemoryImage(MemoryImage i, Window window) {
	char[] data = new char[](i.width * i.height / 8 + 2);
	data[] = 0;

	int bitOffset = 0;
	foreach(c; i.getAsTrueColorImage().imageData.colors) { // FIXME inefficient unnecessary conversion in palette cases
		ubyte v = c.a > 128 ? 1 : 0;
		data[bitOffset / 8] |= v << (bitOffset%8);
		bitOffset++;
	}
	auto handle = XCreateBitmapFromData(XDisplayConnection.get, cast(Drawable) window, data.ptr, i.width, i.height);
	return handle;
}


// basic functions to make timers
/**
	A timer that will trigger your function on a given interval.


	You create a timer with an interval and a callback. It will continue
	to fire on the interval until it is destroyed.

	There are currently no one-off timers (instead, just create one and
	destroy it when it is triggered) nor are there pause/resume functions -
	the timer must again be destroyed and recreated if you want to pause it.

	auto timer = new Timer(50, { it happened!; });
	timer.destroy();

	Timers can only be expected to fire when the event loop is running and only
	once per iteration through the event loop.

	History:
		Prior to December 9, 2020, a timer pulse set too high with a handler too
		slow could lock up the event loop. It now guarantees other things will
		get a chance to run between timer calls, even if that means not keeping up
		with the requested interval.
*/
version(with_timer) {
class Timer {
// FIXME: needs pause and unpause
	// FIXME: I might add overloads for ones that take a count of
	// how many elapsed since last time (on Windows, it will divide
	// the ticks thing given, on Linux it is just available) and
	// maybe one that takes an instance of the Timer itself too
	/// Create a timer with a callback when it triggers.
	this(int intervalInMilliseconds, void delegate() onPulse) {
		assert(onPulse !is null);

		this.intervalInMilliseconds = intervalInMilliseconds;
		this.onPulse = onPulse;

		version(Windows) {
			/*
			handle = SetTimer(null, handle, intervalInMilliseconds, &timerCallback);
			if(handle == 0)
				throw new Exception("SetTimer fail");
			*/

			// thanks to Archival 998 for the WaitableTimer blocks
			handle = CreateWaitableTimer(null, false, null);
			long initialTime = -intervalInMilliseconds;
			if(handle is null || !SetWaitableTimer(handle, cast(LARGE_INTEGER*)&initialTime, intervalInMilliseconds, &timerCallback, handle, false))
				throw new Exception("SetWaitableTimer Failed");

			mapping[handle] = this;

		} else version(linux) {
			static import ep = core.sys.linux.epoll;

			import core.sys.linux.timerfd;

			fd = timerfd_create(CLOCK_MONOTONIC, 0);
			if(fd == -1)
				throw new Exception("timer create failed");

			mapping[fd] = this;

			itimerspec value;
			value.it_value.tv_sec = cast(int) (intervalInMilliseconds / 1000);
			value.it_value.tv_nsec = (intervalInMilliseconds % 1000) * 1000_000;

			value.it_interval.tv_sec = cast(int) (intervalInMilliseconds / 1000);
			value.it_interval.tv_nsec = (intervalInMilliseconds % 1000) * 1000_000;

			if(timerfd_settime(fd, 0, &value, null) == -1)
				throw new Exception("couldn't make pulse timer");

			version(with_eventloop) {
				import arsd.eventloop;
				addFileEventListeners(fd, &trigger, null, null);
			} else {
				prepareEventLoop();

				ep.epoll_event ev = void;
				ev.events = ep.EPOLLIN;
				ev.data.fd = fd;
				ep.epoll_ctl(epollFd, ep.EPOLL_CTL_ADD, fd, &ev);
			}
		} else featureNotImplemented();
	}

	private int intervalInMilliseconds;

	/// Stop and destroy the timer object.
	void destroy() {
		version(Windows) {
			if(handle) {
				// KillTimer(null, handle);
				CancelWaitableTimer(cast(void*)handle);
				mapping.remove(handle);
				CloseHandle(handle);
				handle = null;
			}
		} else version(linux) {
			if(fd != -1) {
				import unix = core.sys.posix.unistd;
				static import ep = core.sys.linux.epoll;

				version(with_eventloop) {
					import arsd.eventloop;
					removeFileEventListeners(fd);
				} else {
					ep.epoll_event ev = void;
					ev.events = ep.EPOLLIN;
					ev.data.fd = fd;

					ep.epoll_ctl(epollFd, ep.EPOLL_CTL_DEL, fd, &ev);
				}
				unix.close(fd);
				mapping.remove(fd);
				fd = -1;
			}
		} else featureNotImplemented();
	}

	~this() {
		destroy();
	}


	void changeTime(int intervalInMilliseconds)
	{
		this.intervalInMilliseconds = intervalInMilliseconds;
		version(Windows)
		{
			if(handle)
			{
				//handle = SetTimer(null, handle, intervalInMilliseconds, &timerCallback);
				long initialTime = -intervalInMilliseconds;
				if(handle is null || !SetWaitableTimer(handle, cast(LARGE_INTEGER*)&initialTime, intervalInMilliseconds, &timerCallback, handle, false))
					throw new Exception("couldn't change pulse timer");
			}
		}
	}


	private:

	void delegate() onPulse;

	int lastEventLoopRoundTriggered;

	void trigger() {
		version(linux) {
			import unix = core.sys.posix.unistd;
			long val;
			unix.read(fd, &val, val.sizeof); // gotta clear the pipe
		} else version(Windows) {
			if(this.lastEventLoopRoundTriggered == eventLoopRound)
				return; // never try to actually run faster than the event loop
			lastEventLoopRoundTriggered = eventLoopRound;
		} else featureNotImplemented();

		onPulse();
	}

	version(Windows)
	void rearm() {

	}

	version(Windows)
		extern(Windows)
		//static void timerCallback(HWND, UINT, UINT_PTR timer, DWORD dwTime) nothrow {
		static void timerCallback(HANDLE timer, DWORD lowTime, DWORD hiTime) nothrow {
			if(Timer* t = timer in mapping) {
				try
				(*t).trigger();
				catch(Exception e) { sdpy_abort(e); assert(0); }
			}
		}

	version(Windows) {
		//UINT_PTR handle;
		//static Timer[UINT_PTR] mapping;
		HANDLE handle;
		__gshared Timer[HANDLE] mapping;
	} else version(linux) {
		int fd = -1;
		__gshared Timer[int] mapping;
	} else static assert(0, "timer not supported");
}
}

version(Windows)
private int eventLoopRound;

version(Windows)
/// Lets you add HANDLEs to the event loop. Not meant to be used for async I/O per se, but for other handles (it can only handle a few handles at a time.) Only works on certain types of handles! See: https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-msgwaitformultipleobjectsex
class WindowsHandleReader {
	///
	this(void delegate() onReady, HANDLE handle) {
		this.onReady = onReady;
		this.handle = handle;

		mapping[handle] = this;

		enable();
	}

	///
	void enable() {
		auto el = EventLoop.get().impl;
		el.handles ~= handle;
	}

	///
	void disable() {
		auto el = EventLoop.get().impl;
		for(int i = 0; i < el.handles.length; i++) {
			if(el.handles[i] is handle) {
				el.handles[i] = el.handles[$-1];
				el.handles = el.handles[0 .. $-1];
				return;
			}
		}
	}

	void dispose() {
		disable();
		if(handle)
			mapping.remove(handle);
		handle = null;
	}

	void ready() {
		if(onReady)
			onReady();
	}

	HANDLE handle;
	void delegate() onReady;

	__gshared WindowsHandleReader[HANDLE] mapping;
}

version(Posix)
/// Lets you add files to the event loop for reading. Use at your own risk.
class PosixFdReader {
	///
	this(void delegate() onReady, int fd, bool captureReads = true, bool captureWrites = false) {
		this((int, bool, bool) { onReady(); }, fd, captureReads, captureWrites);
	}

	///
	this(void delegate(int) onReady, int fd, bool captureReads = true, bool captureWrites = false) {
		this((int fd, bool, bool) { onReady(fd); }, fd, captureReads, captureWrites);
	}

	///
	this(void delegate(int fd, bool read, bool write) onReady, int fd, bool captureReads = true, bool captureWrites = false) {
		this.onReady = onReady;
		this.fd = fd;
		this.captureWrites = captureWrites;
		this.captureReads = captureReads;

		mapping[fd] = this;

		version(with_eventloop) {
			import arsd.eventloop;
			addFileEventListeners(fd, &readyel);
		} else {
			enable();
		}
	}

	bool captureReads;
	bool captureWrites;

	version(with_eventloop) {} else
	///
	void enable() {
		prepareEventLoop();

		enabled = true;

		version(linux) {
			static import ep = core.sys.linux.epoll;
			ep.epoll_event ev = void;
			ev.events = (captureReads ? ep.EPOLLIN : 0) | (captureWrites ? ep.EPOLLOUT : 0);
			//import std.stdio; writeln("enable ", fd, " ", captureReads, " ", captureWrites);
			ev.data.fd = fd;
			ep.epoll_ctl(epollFd, ep.EPOLL_CTL_ADD, fd, &ev);
		} else {

		}
	}

	version(with_eventloop) {} else
	///
	void disable() {
		prepareEventLoop();

		enabled = false;

		version(linux) {
			static import ep = core.sys.linux.epoll;
			ep.epoll_event ev = void;
			ev.events = (captureReads ? ep.EPOLLIN : 0) | (captureWrites ? ep.EPOLLOUT : 0);
			//import std.stdio; writeln("disable ", fd, " ", captureReads, " ", captureWrites);
			ev.data.fd = fd;
			ep.epoll_ctl(epollFd, ep.EPOLL_CTL_DEL, fd, &ev);
		}
	}

	version(with_eventloop) {} else
	///
	void dispose() {
		if(enabled)
			disable();
		if(fd != -1)
			mapping.remove(fd);
		fd = -1;
	}

	void delegate(int, bool, bool) onReady;

	version(with_eventloop)
	void readyel() {
		onReady(fd, true, true);
	}

	void ready(uint flags) {
		version(linux) {
			static import ep = core.sys.linux.epoll;
			onReady(fd, (flags & ep.EPOLLIN) ? true : false, (flags & ep.EPOLLOUT) ? true : false);
		} else {
			import core.sys.posix.poll;
			onReady(fd, (flags & POLLIN) ? true : false, (flags & POLLOUT) ? true : false);
		}
	}

	void hup(uint flags) {
		if(onHup)
			onHup();
	}

	void delegate() onHup;

	int fd = -1;
	private bool enabled;
	__gshared PosixFdReader[int] mapping;
}

// basic functions to access the clipboard
/+


http://msdn.microsoft.com/en-us/library/windows/desktop/ff729168%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms649039%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms649035%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms649051%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms649037%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms649035%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms649016%28v=vs.85%29.aspx

+/

/++
	this does a delegate because it is actually an async call on X...
	the receiver may never be called if the clipboard is empty or unavailable
	gets plain text from the clipboard.
+/
void getClipboardText(SimpleWindow clipboardOwner, void delegate(in char[]) receiver) {
	version(Windows) {
		HWND hwndOwner = clipboardOwner ? clipboardOwner.impl.hwnd : null;
		if(OpenClipboard(hwndOwner) == 0)
			throw new Exception("OpenClipboard");
		scope(exit)
			CloseClipboard();
		// see: https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getpriorityclipboardformat
		if(auto dataHandle = GetClipboardData(CF_UNICODETEXT)) {

			if(auto data = cast(wchar*) GlobalLock(dataHandle)) {
				scope(exit)
					GlobalUnlock(dataHandle);

				// FIXME: CR/LF conversions
				// FIXME: I might not have to copy it now that the receiver is in char[] instead of string
				int len = 0;
				auto d = data;
				while(*d) {
					d++;
					len++;
				}
				string s;
				s.reserve(len);
				foreach(dchar ch; data[0 .. len]) {
					s ~= ch;
				}
				receiver(s);
			}
		}
	} else version(X11) {
		getX11Selection!"CLIPBOARD"(clipboardOwner, receiver);
	} else version(OSXCocoa) {
		throw new NotYetImplementedException();
	} else static assert(0);
}

// FIXME: a clipboard listener might be cool btw

/++
	this does a delegate because it is actually an async call on X...
	the receiver may never be called if the clipboard is empty or unavailable
	gets image from the clipboard.

	templated because it introduces an optional dependency on arsd.bmp
+/
void getClipboardImage()(SimpleWindow clipboardOwner, void delegate(MemoryImage) receiver) {
	version(Windows) {
		HWND hwndOwner = clipboardOwner ? clipboardOwner.impl.hwnd : null;
		if(OpenClipboard(hwndOwner) == 0)
			throw new Exception("OpenClipboard");
		scope(exit)
			CloseClipboard();
		if(auto dataHandle = GetClipboardData(CF_DIBV5)) {
			if(auto data = cast(ubyte*) GlobalLock(dataHandle)) {
				scope(exit)
					GlobalUnlock(dataHandle);

				auto len = GlobalSize(dataHandle);

				import arsd.bmp;
				auto img = readBmp(data[0 .. len], false);
				receiver(img);
			}
		}
	} else version(X11) {
		getX11Selection!"CLIPBOARD"(clipboardOwner, receiver);
	} else version(OSXCocoa) {
		throw new NotYetImplementedException();
	} else static assert(0);
}

version(Windows)
struct WCharzBuffer {
	wchar[] buffer;
	wchar[256] staticBuffer = void;

	size_t length() {
		return buffer.length;
	}

	wchar* ptr() {
		return buffer.ptr;
	}

	wchar[] slice() {
		return buffer;
	}

	void copyInto(R)(ref R r) {
		static if(is(R == wchar[N], size_t N)) {
			r[0 .. this.length] = slice[];
			r[this.length] = 0;
		} else static assert(0, "can only copy into wchar[n], not " ~ R.stringof);
	}

	/++
		conversionFlags = [WindowsStringConversionFlags]
	+/
	this(in char[] data, int conversionFlags = 0) {
		conversionFlags |= WindowsStringConversionFlags.zeroTerminate; // this ALWAYS zero terminates cuz of its name
		auto sz = sizeOfConvertedWstring(data, conversionFlags);
		if(sz > staticBuffer.length)
			buffer = new wchar[](sz);
		else
			buffer = staticBuffer[];

		buffer = makeWindowsString(data, buffer, conversionFlags);
	}
}

version(Windows)
int sizeOfConvertedWstring(in char[] s, int conversionFlags) {
	int size = 0;

	if(conversionFlags & WindowsStringConversionFlags.convertNewLines) {
		// need to convert line endings, which means the length will get bigger.

		// BTW I betcha this could be faster with some simd stuff.
		char last;
		foreach(char ch; s) {
			if(ch == 10 && last != 13)
				size++; // will add a 13 before it...
			size++;
			last = ch;
		}
	} else {
		// no conversion necessary, just estimate based on length
		/*
			I don't think there's any string with a longer length
			in code units when encoded in UTF-16 than it has in UTF-8.
			This will probably over allocate, but that's OK.
		*/
		size = cast(int) s.length;
	}

	if(conversionFlags & WindowsStringConversionFlags.zeroTerminate)
		size++;

	return size;
}

version(Windows)
enum WindowsStringConversionFlags : int {
	zeroTerminate = 1,
	convertNewLines = 2,
}

version(Windows)
class WindowsApiException : Exception {
	char[256] buffer;
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		assert(msg.length < 100);

		auto error = GetLastError();
		buffer[0 .. msg.length] = msg;
		buffer[msg.length] = ' ';

		int pos = cast(int) msg.length + 1;

		if(error == 0)
			buffer[pos++] = '0';
		else {

			auto ec = error;
			auto init = pos;
			while(ec) {
				buffer[pos++] = (ec % 10) + '0';
				ec /= 10;
			}

			buffer[pos++] = ' ';

			size_t size = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), &(buffer[pos]), cast(DWORD) buffer.length - pos, null);

			pos += size;
		}


		super(cast(string) buffer[0 .. pos], file, line, next);
	}
}

class ErrnoApiException : Exception {
	char[256] buffer;
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
		assert(msg.length < 100);

		import core.stdc.errno;
		auto error = errno;
		buffer[0 .. msg.length] = msg;
		buffer[msg.length] = ' ';

		int pos = cast(int) msg.length + 1;

		if(error == 0)
			buffer[pos++] = '0';
		else {
			auto init = pos;
			while(error) {
				buffer[pos++] = (error % 10) + '0';
				error /= 10;
			}
			for(int i = 0; i < (pos - init) / 2; i++) {
				char c = buffer[i + init];
				buffer[i + init] = buffer[pos - (i + init) - 1];
				buffer[pos - (i + init) - 1] = c;
			}
		}


		super(cast(string) buffer[0 .. pos], file, line, next);
	}

}

version(Windows)
wchar[] makeWindowsString(in char[] str, wchar[] buffer, int conversionFlags = WindowsStringConversionFlags.zeroTerminate) {
	if(str.length == 0)
		return null;

	int pos = 0;
	dchar last;
	foreach(dchar c; str) {
		if(c <= 0xFFFF) {
			if((conversionFlags & WindowsStringConversionFlags.convertNewLines) && c == 10 && last != 13)
				buffer[pos++] = 13;
			buffer[pos++] = cast(wchar) c;
		} else if(c <= 0x10FFFF) {
			buffer[pos++] = cast(wchar)((((c - 0x10000) >> 10) & 0x3FF) + 0xD800);
			buffer[pos++] = cast(wchar)(((c - 0x10000) & 0x3FF) + 0xDC00);
		}

		last = c;
	}

	if(conversionFlags & WindowsStringConversionFlags.zeroTerminate) {
		buffer[pos] = 0;
	}

	return buffer[0 .. pos];
}

version(Windows)
char[] makeUtf8StringFromWindowsString(in wchar[] str, char[] buffer) {
	if(str.length == 0)
		return null;

	auto got = WideCharToMultiByte(CP_UTF8, 0, str.ptr, cast(int) str.length, buffer.ptr, cast(int) buffer.length, null, null);
	if(got == 0) {
		if(GetLastError() == ERROR_INSUFFICIENT_BUFFER)
			throw new Exception("not enough buffer");
		else
			throw new Exception("conversion"); // FIXME: GetLastError
	}
	return buffer[0 .. got];
}

version(Windows)
string makeUtf8StringFromWindowsString(in wchar[] str) {
	char[] buffer;
	auto got = WideCharToMultiByte(CP_UTF8, 0, str.ptr, cast(int) str.length, null, 0, null, null);
	buffer.length = got;

	// it is unique because we just allocated it above!
	return cast(string) makeUtf8StringFromWindowsString(str, buffer);
}

version(Windows)
string makeUtf8StringFromWindowsString(wchar* str) {
	char[] buffer;
	auto got = WideCharToMultiByte(CP_UTF8, 0, str, -1, null, 0, null, null);
	buffer.length = got;

	got = WideCharToMultiByte(CP_UTF8, 0, str, -1, buffer.ptr, cast(int) buffer.length, null, null);
	if(got == 0) {
		if(GetLastError() == ERROR_INSUFFICIENT_BUFFER)
			throw new Exception("not enough buffer");
		else
			throw new Exception("conversion"); // FIXME: GetLastError
	}
	return cast(string) buffer[0 .. got];
}

int findIndexOfZero(in wchar[] str) {
	foreach(idx, wchar ch; str)
		if(ch == 0)
			return cast(int) idx;
	return cast(int) str.length;
}
int findIndexOfZero(in char[] str) {
	foreach(idx, char ch; str)
		if(ch == 0)
			return cast(int) idx;
	return cast(int) str.length;
}

/// Copies some text to the clipboard.
void setClipboardText(SimpleWindow clipboardOwner, string text) {
	assert(clipboardOwner !is null);
	version(Windows) {
		if(OpenClipboard(clipboardOwner.impl.hwnd) == 0)
			throw new Exception("OpenClipboard");
		scope(exit)
			CloseClipboard();
		EmptyClipboard();
		auto sz = sizeOfConvertedWstring(text, WindowsStringConversionFlags.convertNewLines | WindowsStringConversionFlags.zeroTerminate);
		auto handle = GlobalAlloc(GMEM_MOVEABLE, sz * 2); // zero terminated wchars
		if(handle is null) throw new Exception("GlobalAlloc");
		if(auto data = cast(wchar*) GlobalLock(handle)) {
			auto slice = data[0 .. sz];
			scope(failure)
				GlobalUnlock(handle);

			auto str = makeWindowsString(text, slice, WindowsStringConversionFlags.convertNewLines | WindowsStringConversionFlags.zeroTerminate);

			GlobalUnlock(handle);
			SetClipboardData(CF_UNICODETEXT, handle);
		}
	} else version(X11) {
		setX11Selection!"CLIPBOARD"(clipboardOwner, text);
	} else version(OSXCocoa) {
		throw new NotYetImplementedException();
	} else static assert(0);
}

void setClipboardImage()(SimpleWindow clipboardOwner, MemoryImage img) {
	assert(clipboardOwner !is null);
	version(Windows) {
		if(OpenClipboard(clipboardOwner.impl.hwnd) == 0)
			throw new Exception("OpenClipboard");
		scope(exit)
			CloseClipboard();
		EmptyClipboard();


		import arsd.bmp;
		ubyte[] mdata;
		mdata.reserve(img.width * img.height);
		void sink(ubyte b) {
			mdata ~= b;
		}
		writeBmpIndirect(img, &sink, false);

		auto handle = GlobalAlloc(GMEM_MOVEABLE, mdata.length);
		if(handle is null) throw new Exception("GlobalAlloc");
		if(auto data = cast(ubyte*) GlobalLock(handle)) {
			auto slice = data[0 .. mdata.length];
			scope(failure)
				GlobalUnlock(handle);

			slice[] = mdata[];

			GlobalUnlock(handle);
			SetClipboardData(CF_DIB, handle);
		}
	} else version(X11) {
		static class X11SetSelectionHandler_Image : X11SetSelectionHandler {
			mixin X11SetSelectionHandler_Basics;
			private const(ubyte)[] mdata;
			private const(ubyte)[] mdata_original;
			this(MemoryImage img) {
				import arsd.bmp;

				mdata.reserve(img.width * img.height);
				void sink(ubyte b) {
					mdata ~= b;
				}
				writeBmpIndirect(img, &sink, true);

				mdata_original = mdata;
			}

			Atom[] availableFormats() {
				auto display = XDisplayConnection.get;
				return [
					GetAtom!"image/bmp"(display),
					GetAtom!"TARGETS"(display)
				];
			}

			ubyte[] getData(Atom format, return scope ubyte[] data) {
				if(mdata.length < data.length) {
					data[0 .. mdata.length] = mdata[];
					auto ret = data[0 .. mdata.length];
					mdata = mdata[$..$];
					return ret;
				} else {
					data[] = mdata[0 .. data.length];
					mdata = mdata[data.length .. $];
					return data[];
				}
			}

			void done() {
				mdata = mdata_original;
			}
		}

		setX11Selection!"CLIPBOARD"(clipboardOwner, new X11SetSelectionHandler_Image(img));
	} else version(OSXCocoa) {
		throw new NotYetImplementedException();
	} else static assert(0);
}


version(X11) {
	// and the PRIMARY on X, be sure to put these in static if(UsingSimpledisplayX11)

	private Atom*[] interredAtoms; // for discardAndRecreate

	// FIXME: do a GetAtomUpfront too that just queues all at CT and combines it all.
	/// Platform-specific for X11.
	/// History: On February 21, 2021, I changed the default value of `create` to be true.
	@property Atom GetAtom(string name, bool create = true)(Display* display) {
		static Atom a;
		if(!a) {
			a = XInternAtom(display, name, !create);
			interredAtoms ~= &a;
		}
		if(a == None)
			throw new Exception("XInternAtom " ~ name ~ " " ~ (create ? "true":"false"));
		return a;
	}

	/// Platform-specific for X11 - gets atom names as a string.
	string getAtomName(Atom atom, Display* display) {
		auto got = XGetAtomName(display, atom);
		scope(exit) XFree(got);
		import core.stdc.string;
		string s = got[0 .. strlen(got)].idup;
		return s;
	}

	/// Asserts ownership of PRIMARY and copies the text into a buffer that clients can request later.
	void setPrimarySelection(SimpleWindow window, string text) {
		setX11Selection!"PRIMARY"(window, text);
	}

	/// Asserts ownership of SECONDARY and copies the text into a buffer that clients can request later.
	void setSecondarySelection(SimpleWindow window, string text) {
		setX11Selection!"SECONDARY"(window, text);
	}

	interface X11SetSelectionHandler {
		// should include TARGETS right now
		Atom[] availableFormats();
		// Return the slice of data you filled, empty slice if done.
		// this is to support the incremental thing
		ubyte[] getData(Atom format, return scope ubyte[] data);

		void done();

		void handleRequest(XEvent);

		bool matchesIncr(Window, Atom);
		void sendMoreIncr(XPropertyEvent*);
	}

	mixin template X11SetSelectionHandler_Basics() {
		Window incrWindow;
		Atom incrAtom;
		Atom selectionAtom;
		Atom formatAtom;
		ubyte[] toSend;
		bool matchesIncr(Window w, Atom a) {
			return incrAtom && incrAtom == a && w == incrWindow;
		}
		void sendMoreIncr(XPropertyEvent* event) {
			auto display = XDisplayConnection.get;

			XChangeProperty (display,
				incrWindow,
				incrAtom,
				formatAtom,
				8 /* bits */, PropModeReplace,
				toSend.ptr, cast(int) toSend.length);

			if(toSend.length != 0) {
				toSend = this.getData(formatAtom, toSend[]);
			} else {
				this.done();
				incrWindow = None;
				incrAtom = None;
				selectionAtom = None;
				formatAtom = None;
				toSend = null;
			}
		}
		void handleRequest(XEvent ev) {

			auto display = XDisplayConnection.get;

			XSelectionRequestEvent* event = &ev.xselectionrequest;
			XSelectionEvent selectionEvent;
			selectionEvent.type = EventType.SelectionNotify;
			selectionEvent.display = event.display;
			selectionEvent.requestor = event.requestor;
			selectionEvent.selection = event.selection;
			selectionEvent.time = event.time;
			selectionEvent.target = event.target;

			bool supportedType() {
				foreach(t; this.availableFormats())
					if(t == event.target)
						return true;
				return false;
			}

			if(event.property == None) {
				selectionEvent.property = event.target;

				XSendEvent(display, selectionEvent.requestor, false, 0, cast(XEvent*) &selectionEvent);
				XFlush(display);
			} if(event.target == GetAtom!"TARGETS"(display)) {
				/* respond with the supported types */
				auto tlist = this.availableFormats();
				XChangeProperty(display, event.requestor, event.property, XA_ATOM, 32, PropModeReplace, cast(void*)tlist.ptr, cast(int) tlist.length);
				selectionEvent.property = event.property;

				XSendEvent(display, selectionEvent.requestor, false, 0, cast(XEvent*) &selectionEvent);
				XFlush(display);
			} else if(supportedType()) {
				auto buffer = new ubyte[](1024 * 64);
				auto toSend = this.getData(event.target, buffer[]);

				if(toSend.length < 32 * 1024) {
					// small enough to send directly...
					selectionEvent.property = event.property;
					XChangeProperty (display,
						selectionEvent.requestor,
						selectionEvent.property,
						event.target,
						8 /* bits */, 0 /* PropModeReplace */,
						toSend.ptr, cast(int) toSend.length);

					XSendEvent(display, selectionEvent.requestor, false, 0, cast(XEvent*) &selectionEvent);
					XFlush(display);
				} else {
					// large, let's send incrementally
					arch_ulong l = toSend.length;

					// if I wanted other events from this window don't want to clear that out....
					XWindowAttributes xwa;
					XGetWindowAttributes(display, selectionEvent.requestor, &xwa);

					XSelectInput(display, selectionEvent.requestor, cast(EventMask) (xwa.your_event_mask | EventMask.PropertyChangeMask));

					incrWindow = event.requestor;
					incrAtom = event.property;
					formatAtom = event.target;
					selectionAtom = event.selection;
					this.toSend = toSend;

					selectionEvent.property = event.property;
					XChangeProperty (display,
						selectionEvent.requestor,
						selectionEvent.property,
						GetAtom!"INCR"(display),
						32 /* bits */, PropModeReplace,
						&l, 1);

					XSendEvent(display, selectionEvent.requestor, false, 0, cast(XEvent*) &selectionEvent);
					XFlush(display);
				}
				//if(after)
					//after();
			} else {
				debug(sdpy_clip) {
					import std.stdio; writeln("Unsupported data ", getAtomName(event.target, display));
				}
				selectionEvent.property = None; // I don't know how to handle this type...
				XSendEvent(display, selectionEvent.requestor, false, EventMask.NoEventMask, cast(XEvent*) &selectionEvent);
				XFlush(display);
			}
		}
	}

	class X11SetSelectionHandler_Text : X11SetSelectionHandler {
		mixin X11SetSelectionHandler_Basics;
		private const(ubyte)[] text;
		private const(ubyte)[] text_original;
		this(string text) {
			this.text = cast(const ubyte[]) text;
			this.text_original = this.text;
		}
		Atom[] availableFormats() {
			auto display = XDisplayConnection.get;
			return [
				GetAtom!"UTF8_STRING"(display),
				GetAtom!"text/plain"(display),
				XA_STRING,
				GetAtom!"TARGETS"(display)
			];
		}

		ubyte[] getData(Atom format, return scope ubyte[] data) {
			if(text.length < data.length) {
				data[0 .. text.length] = text[];
				return data[0 .. text.length];
			} else {
				data[] = text[0 .. data.length];
				text = text[data.length .. $];
				return data[];
			}
		}

		void done() {
			text = text_original;
		}
	}

	/// The `after` delegate is called after a client requests the UTF8_STRING thing. it is a mega-hack right now! (note to self july 2020... why did i do that?!)
	void setX11Selection(string atomName)(SimpleWindow window, string text, void delegate() after = null) {
		setX11Selection!atomName(window, new X11SetSelectionHandler_Text(text), after);
	}

	void setX11Selection(string atomName)(SimpleWindow window, X11SetSelectionHandler data, void delegate() after = null) {
		assert(window !is null);

		auto display = XDisplayConnection.get();
		static if (atomName == "PRIMARY") Atom a = XA_PRIMARY;
		else static if (atomName == "SECONDARY") Atom a = XA_SECONDARY;
		else Atom a = GetAtom!atomName(display);

		XSetSelectionOwner(display, a, window.impl.window, 0 /* CurrentTime */);

		window.impl.setSelectionHandlers[a] = data;
	}

	///
	void getPrimarySelection(SimpleWindow window, void delegate(in char[]) handler) {
		getX11Selection!"PRIMARY"(window, handler);
	}

	// added July 28, 2020
	// undocumented as experimental tho
	interface X11GetSelectionHandler {
		void handleData(Atom target, in ubyte[] data);
		Atom findBestFormat(Atom[] answer);

		void prepareIncremental(Window, Atom);
		bool matchesIncr(Window, Atom);
		void handleIncrData(Atom, in ubyte[] data);
	}

	mixin template X11GetSelectionHandler_Basics() {
		Window incrWindow;
		Atom incrAtom;

		void prepareIncremental(Window w, Atom a) {
			incrWindow = w;
			incrAtom = a;
		}
		bool matchesIncr(Window w, Atom a) {
			return incrWindow == w && incrAtom == a;
		}

		Atom incrFormatAtom;
		ubyte[] incrData;
		void handleIncrData(Atom format, in ubyte[] data) {
			incrFormatAtom = format;

			if(data.length)
				incrData ~= data;
			else
				handleData(incrFormatAtom, incrData);

		}
	}

	///
	void getX11Selection(string atomName)(SimpleWindow window, void delegate(in char[]) handler, Time timestamp = 0 /* CurrentTime */) {
		assert(window !is null);

		auto display = XDisplayConnection.get();
		auto atom = GetAtom!atomName(display);

		static class X11GetSelectionHandler_Text : X11GetSelectionHandler {
			this(void delegate(in char[]) handler) {
				this.handler = handler;
			}

			mixin X11GetSelectionHandler_Basics;

			void delegate(in char[]) handler;

			void handleData(Atom target, in ubyte[] data) {
				if(target == GetAtom!"UTF8_STRING"(XDisplayConnection.get) || target == XA_STRING || target == GetAtom!"text/plain"(XDisplayConnection.get))
					handler(cast(const char[]) data);
			}

			Atom findBestFormat(Atom[] answer) {
				Atom best = None;
				foreach(option; answer) {
					if(option == GetAtom!"UTF8_STRING"(XDisplayConnection.get)) {
						best = option;
						break;
					} else if(option == XA_STRING) {
						best = option;
					} else if(option == GetAtom!"text/plain"(XDisplayConnection.get)) {
						best = option;
					}
				}
				return best;
			}
		}

		window.impl.getSelectionHandlers[atom] = new X11GetSelectionHandler_Text(handler);

		auto target = GetAtom!"TARGETS"(display);

		// SDD_DATA is "simpledisplay.d data"
		XConvertSelection(display, atom, target, GetAtom!("SDD_DATA", true)(display), window.impl.window, timestamp);
	}

	/// Gets the image on the clipboard, if there is one. Added July 2020.
	void getX11Selection(string atomName)(SimpleWindow window, void delegate(MemoryImage) handler) {
		assert(window !is null);

		auto display = XDisplayConnection.get();
		auto atom = GetAtom!atomName(display);

		static class X11GetSelectionHandler_Image : X11GetSelectionHandler {
			this(void delegate(MemoryImage) handler) {
				this.handler = handler;
			}

			mixin X11GetSelectionHandler_Basics;

			void delegate(MemoryImage) handler;

			void handleData(Atom target, in ubyte[] data) {
				if(target == GetAtom!"image/bmp"(XDisplayConnection.get)) {
					import arsd.bmp;
					handler(readBmp(data));
				}
			}

			Atom findBestFormat(Atom[] answer) {
				Atom best = None;
				foreach(option; answer) {
					if(option == GetAtom!"image/bmp"(XDisplayConnection.get)) {
						best = option;
					}
				}
				return best;
			}

		}


		window.impl.getSelectionHandlers[atom] = new X11GetSelectionHandler_Image(handler);

		auto target = GetAtom!"TARGETS"(display);

		// SDD_DATA is "simpledisplay.d data"
		XConvertSelection(display, atom, target, GetAtom!("SDD_DATA", true)(display), window.impl.window, 0 /*CurrentTime*/);
	}


	///
	void[] getX11PropertyData(Window window, Atom property, Atom type = AnyPropertyType) {
		Atom actualType;
		int actualFormat;
		arch_ulong actualItems;
		arch_ulong bytesRemaining;
		void* data;

		auto display = XDisplayConnection.get();
		if(XGetWindowProperty(display, window, property, 0, 0x7fffffff, false, type, &actualType, &actualFormat, &actualItems, &bytesRemaining, &data) == Success) {
			if(actualFormat == 0)
				return null;
			else {
				int byteLength;
				if(actualFormat == 32) {
					// 32 means it is a C long... which is variable length
					actualFormat = cast(int) arch_long.sizeof * 8;
				}

				// then it is just a bit count
				byteLength = cast(int) (actualItems * actualFormat / 8);

				auto d = new ubyte[](byteLength);
				d[] = cast(ubyte[]) data[0 .. byteLength];
				XFree(data);
				return d;
			}
		}
		return null;
	}

	/* defined in the systray spec */
	enum SYSTEM_TRAY_REQUEST_DOCK   = 0;
	enum SYSTEM_TRAY_BEGIN_MESSAGE  = 1;
	enum SYSTEM_TRAY_CANCEL_MESSAGE = 2;


	/** Global hotkey handler. Simpledisplay will usually create one for you, but if you want to use subclassing
	 * instead of delegates, you can subclass this, and override `doHandle()` method. */
	public class GlobalHotkey {
		KeyEvent key;
		void delegate () handler;

		void doHandle () { if (handler !is null) handler(); } /// this will be called by hotkey manager

		/// Create from initialzed KeyEvent object
		this (KeyEvent akey, void delegate () ahandler=null) {
			if (akey.key == 0 || !GlobalHotkeyManager.isGoodModifierMask(akey.modifierState)) throw new Exception("invalid global hotkey");
			key = akey;
			handler = ahandler;
		}

		/// Create from emacs-like key name ("C-M-Y", etc.)
		this (const(char)[] akey, void delegate () ahandler=null) {
			key = KeyEvent.parse(akey);
			if (key.key == 0 || !GlobalHotkeyManager.isGoodModifierMask(key.modifierState)) throw new Exception("invalid global hotkey");
			handler = ahandler;
		}

	}

	private extern(C) int XGrabErrorHandler (Display* dpy, XErrorEvent* evt) nothrow @nogc {
		//conwriteln("failed to grab key");
		GlobalHotkeyManager.ghfailed = true;
		return 0;
	}

	private extern(C) int XShmErrorHandler (Display* dpy, XErrorEvent* evt) nothrow @nogc {
		Image.impl.xshmfailed = true;
		return 0;
	}

	private extern(C) int adrlogger (Display* dpy, XErrorEvent* evt) nothrow @nogc {
		import core.stdc.stdio;
		char[265] buffer;
		XGetErrorText(dpy, evt.error_code, buffer.ptr, cast(int) buffer.length);
		debug printf("X Error %d: %s / Serial: %lld, Opcode: %d.%d, XID: 0x%llx\n", evt.error_code, buffer.ptr, evt.serial, evt.request_code, evt.minor_code, evt.resourceid);
		return 0;
	}

	/++
		Global hotkey manager. It contains static methods to manage global hotkeys.

		---
		 try {
			GlobalHotkeyManager.register("M-H-A", delegate () { hideShowWindows(); });
		} catch (Exception e) {
			conwriteln("ERROR registering hotkey!");
		}
		---

		The key strings are based on Emacs. In practical terms,
		`M` means `alt` and `H` means the Windows logo key. `C`
		is `ctrl`.

		$(WARNING
			This is X-specific right now. If you are on
			Windows, try [registerHotKey] instead.

			We will probably merge these into a single
			interface later.
		)
	+/
	public class GlobalHotkeyManager : CapableOfHandlingNativeEvent {
		version(X11) {
			void recreateAfterDisconnect() {
				throw new Exception("NOT IMPLEMENTED");
			}
			void discardConnectionState() {
				throw new Exception("NOT IMPLEMENTED");
			}
		}

		private static immutable uint[8] masklist = [ 0,
			KeyOrButtonMask.LockMask,
			KeyOrButtonMask.Mod2Mask,
			KeyOrButtonMask.Mod3Mask,
			KeyOrButtonMask.LockMask|KeyOrButtonMask.Mod2Mask,
			KeyOrButtonMask.LockMask|KeyOrButtonMask.Mod3Mask,
			KeyOrButtonMask.LockMask|KeyOrButtonMask.Mod2Mask|KeyOrButtonMask.Mod3Mask,
			KeyOrButtonMask.Mod2Mask|KeyOrButtonMask.Mod3Mask,
		];
		private __gshared GlobalHotkeyManager ghmanager;
		private __gshared bool ghfailed = false;

		private static bool isGoodModifierMask (uint modmask) pure nothrow @safe @nogc {
			if (modmask == 0) return false;
			if (modmask&(KeyOrButtonMask.LockMask|KeyOrButtonMask.Mod2Mask|KeyOrButtonMask.Mod3Mask)) return false;
			if (modmask&~(KeyOrButtonMask.Mod5Mask-1)) return false;
			return true;
		}

		private static uint cleanupModifiers (uint modmask) pure nothrow @safe @nogc {
			modmask &= ~(KeyOrButtonMask.LockMask|KeyOrButtonMask.Mod2Mask|KeyOrButtonMask.Mod3Mask); // remove caps, num, scroll
			modmask &= (KeyOrButtonMask.Mod5Mask-1); // and other modifiers
			return modmask;
		}

		private static uint keyEvent2KeyCode() (in auto ref KeyEvent ke) {
			uint keycode = cast(uint)ke.key;
			auto dpy = XDisplayConnection.get;
			return XKeysymToKeycode(dpy, keycode);
		}

		private static ulong keyCode2Hash() (uint keycode, uint modstate) pure nothrow @safe @nogc { return ((cast(ulong)modstate)<<32)|keycode; }

		private __gshared GlobalHotkey[ulong] globalHotkeyList;

		NativeEventHandler getNativeEventHandler () {
			return delegate int (XEvent e) {
				if (e.type != EventType.KeyPress) return 1;
				auto kev = cast(const(XKeyEvent)*)&e;
				auto hash = keyCode2Hash(e.xkey.keycode, cleanupModifiers(e.xkey.state));
				if (auto ghkp = hash in globalHotkeyList) {
					try {
						ghkp.doHandle();
					} catch (Exception e) {
						import core.stdc.stdio : stderr, fprintf;
						stderr.fprintf("HOTKEY HANDLER EXCEPTION: %.*s", cast(uint)e.msg.length, e.msg.ptr);
					}
				}
				return 1;
			};
		}

		private this () {
			auto dpy = XDisplayConnection.get;
			auto root = RootWindow(dpy, DefaultScreen(dpy));
			CapableOfHandlingNativeEvent.nativeHandleMapping[root] = this;
			XDisplayConnection.addRootInput(EventMask.KeyPressMask);
		}

		/// Register new global hotkey with initialized `GlobalHotkey` object.
		/// This function will throw if it failed to register hotkey (i.e. hotkey is invalid or already taken).
		static void register (GlobalHotkey gh) {
			if (gh is null) return;
			if (gh.key.key == 0 || !isGoodModifierMask(gh.key.modifierState)) throw new Exception("invalid global hotkey");

			auto dpy = XDisplayConnection.get;
			immutable keycode = keyEvent2KeyCode(gh.key);

			auto hash = keyCode2Hash(keycode, gh.key.modifierState);
			if (hash in globalHotkeyList) throw new Exception("duplicate global hotkey");
			if (ghmanager is null) ghmanager = new GlobalHotkeyManager();
			XSync(dpy, 0/*False*/);

			Window root = RootWindow(dpy, DefaultScreen(dpy));
			XErrorHandler savedErrorHandler = XSetErrorHandler(&XGrabErrorHandler);
			ghfailed = false;
			foreach (immutable uint ormask; masklist[]) {
				XGrabKey(dpy, keycode, gh.key.modifierState|ormask, /*grab_window*/root, /*owner_events*/0/*False*/, GrabMode.GrabModeAsync, GrabMode.GrabModeAsync);
			}
			XSync(dpy, 0/*False*/);
			XSetErrorHandler(savedErrorHandler);

			if (ghfailed) {
				savedErrorHandler = XSetErrorHandler(&XGrabErrorHandler);
				foreach (immutable uint ormask; masklist[]) XUngrabKey(dpy, keycode, gh.key.modifierState|ormask, /*grab_window*/root);
				XSync(dpy, 0/*False*/);
				XSetErrorHandler(savedErrorHandler);
				throw new Exception("cannot register global hotkey");
			}

			globalHotkeyList[hash] = gh;
		}

		/// Ditto
		static void register (const(char)[] akey, void delegate () ahandler) {
			register(new GlobalHotkey(akey, ahandler));
		}

		private static void removeByHash (ulong hash) {
			if (auto ghp = hash in globalHotkeyList) {
				auto dpy = XDisplayConnection.get;
				immutable keycode = keyEvent2KeyCode(ghp.key);
				Window root = RootWindow(dpy, DefaultScreen(dpy));
				XSync(dpy, 0/*False*/);
				XErrorHandler savedErrorHandler = XSetErrorHandler(&XGrabErrorHandler);
				foreach (immutable uint ormask; masklist[]) XUngrabKey(dpy, keycode, ghp.key.modifierState|ormask, /*grab_window*/root);
				XSync(dpy, 0/*False*/);
				XSetErrorHandler(savedErrorHandler);
				globalHotkeyList.remove(hash);
			}
		}

		/// Register new global hotkey with previously used `GlobalHotkey` object.
		/// It is safe to unregister unknown or invalid hotkey.
		static void unregister (GlobalHotkey gh) {
			//TODO: add second AA for faster search? prolly doesn't worth it.
			if (gh is null) return;
			foreach (const ref kv; globalHotkeyList.byKeyValue) {
				if (kv.value is gh) {
					removeByHash(kv.key);
					return;
				}
			}
		}

		/// Ditto.
		static void unregister (const(char)[] key) {
			auto kev = KeyEvent.parse(key);
			immutable keycode = keyEvent2KeyCode(kev);
			removeByHash(keyCode2Hash(keycode, kev.modifierState));
		}
	}
}

version(Windows) {
	/// Platform-specific for Windows. Sends a string as key press and release events to the actively focused window (not necessarily your application).
	void sendSyntheticInput(wstring s) {
		INPUT[] inputs;
		inputs.reserve(s.length * 2);

		foreach(wchar c; s) {
			INPUT input;
			input.type = INPUT_KEYBOARD;
			input.ki.wScan = c;
			input.ki.dwFlags = KEYEVENTF_UNICODE;
			inputs ~= input;

			input.ki.dwFlags |= KEYEVENTF_KEYUP;
			inputs ~= input;
		}

		if(SendInput(cast(int) inputs.length, inputs.ptr, INPUT.sizeof) != inputs.length) {
			throw new Exception("SendInput failed");
		}
	}


	// global hotkey helper function

	/// Platform-specific for Windows. Registers a global hotkey. Returns a registration ID.
	int registerHotKey(SimpleWindow window, UINT modifiers, UINT vk, void delegate() handler) {
		__gshared int hotkeyId = 0;
		int id = ++hotkeyId;
		if(!RegisterHotKey(window.impl.hwnd, id, modifiers, vk))
			throw new Exception("RegisterHotKey failed");

		__gshared void delegate()[WPARAM][HWND] handlers;

		handlers[window.impl.hwnd][id] = handler;

		int delegate(HWND, UINT, WPARAM, LPARAM) oldHandler;

		auto nativeEventHandler = delegate int(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
			switch(msg) {
				// http://msdn.microsoft.com/en-us/library/windows/desktop/ms646279%28v=vs.85%29.aspx
				case WM_HOTKEY:
					if(auto list = hwnd in handlers) {
						if(auto h = wParam in *list) {
							(*h)();
							return 0;
						}
					}
				goto default;
				default:
			}
			if(oldHandler)
				return oldHandler(hwnd, msg, wParam, lParam);
			return 1; // pass it on
		};

		if(window.handleNativeEvent.funcptr !is nativeEventHandler.funcptr) {
			oldHandler = window.handleNativeEvent;
			window.handleNativeEvent = nativeEventHandler;
		}

		return id;
	}

	/// Platform-specific for Windows. Unregisters a key. The id is the value returned by [registerHotKey].
	void unregisterHotKey(SimpleWindow window, int id) {
		if(!UnregisterHotKey(window.impl.hwnd, id))
			throw new Exception("UnregisterHotKey");
	}
}

version (X11) {
	pragma(lib, "dl");
	import core.sys.posix.dlfcn;

	/++
		Allows for sending synthetic input to the X server via the Xtst
		extension.

		Please remember user input is meant to be user - don't use this
		if you have some other alternative!

		If you need this on Windows btw, the top-level [sendSyntheticInput] shows
		the Win32 api to start it, but I only did basics there, PR welcome if you like,
		it is an easy enough function to use.

		History: Added May 17, 2020.
	+/
	struct SyntheticInput {
		@disable this();

		private void* lib;
		private int* refcount;

		private extern(C) {
			void function(Display*, uint keycode, bool press, arch_ulong delay) XTestFakeKeyEvent;
			void function(Display*, uint button, bool press, arch_ulong delay) XTestFakeButtonEvent;
		}

		/// The dummy param must be 0.
		this(int dummy) {
			lib = dlopen("libXtst.so", RTLD_NOW);
			if(lib is null)
				throw new Exception("cannot load xtest lib extension");
			scope(failure)
				dlclose(lib);

			XTestFakeButtonEvent = cast(typeof(XTestFakeButtonEvent)) dlsym(lib, "XTestFakeButtonEvent");
			XTestFakeKeyEvent = cast(typeof(XTestFakeKeyEvent)) dlsym(lib, "XTestFakeKeyEvent");

			if(XTestFakeKeyEvent is null)
				throw new Exception("No XTestFakeKeyEvent");
			if(XTestFakeButtonEvent is null)
				throw new Exception("No XTestFakeButtonEvent");

			refcount = new int;
			*refcount = 1;
		}

		this(this) {
			if(refcount)
				*refcount += 1;
		}

		~this() {
			if(refcount) {
				*refcount -= 1;
				if(*refcount == 0)
					// I commented this because if I close the lib before
					// XCloseDisplay, it is liable to segfault... so just
					// gonna keep it loaded if it is loaded, no big deal
					// anyway.
					{} // dlclose(lib);
			}
		}

		/// This ONLY works with basic ascii!
		void sendSyntheticInput(string s) {
			int delay = 0;
			foreach(ch; s) {
				pressKey(cast(Key) ch, true, delay);
				pressKey(cast(Key) ch, false, delay);
				delay += 5;
			}
		}

		/++
			Sends a fake press key event.

			Please note you need to call [flushGui] or return to the event loop for this to actually be sent.
		+/
		void pressKey(Key key, bool pressed, int delay = 0) {
			XTestFakeKeyEvent(XDisplayConnection.get, XKeysymToKeycode(XDisplayConnection.get, key), pressed, delay + pressed ? 0 : 5);
		}

		///
		void pressMouseButton(MouseButton button, bool pressed, int delay = 0) {
			int btn;

			switch(button) {
				case MouseButton.left: btn = 1; break;
				case MouseButton.middle: btn = 2; break;
				case MouseButton.right: btn = 3; break;
				case MouseButton.wheelUp: btn = 4; break;
				case MouseButton.wheelDown: btn = 5; break;
				case MouseButton.backButton: btn = 8; break;
				case MouseButton.forwardButton: btn = 9; break;
				default:
			}

			assert(btn);

			XTestFakeButtonEvent(XDisplayConnection.get, btn, pressed, delay);
		}

		///
		static void moveMouseArrowBy(int dx, int dy) {
			auto disp = XDisplayConnection.get();
			XWarpPointer(disp, None, None, 0, 0, 0, 0, dx, dy);
			XFlush(disp);
		}

		///
		static void moveMouseArrowTo(int x, int y) {
			auto disp = XDisplayConnection.get();
			auto root = RootWindow(disp, DefaultScreen(disp));
			XWarpPointer(disp, None, root, 0, 0, 0, 0, x, y);
			XFlush(disp);
		}
	}
}



/++
	[ScreenPainter] operations can use different operations to combine the color with the color on screen.

	See_Also:
	$(LIST
		*[ScreenPainter]
		*[ScreenPainter.rasterOp]
	)
+/
enum RasterOp {
	normal, /// Replaces the pixel.
	xor, /// Uses bitwise xor to draw.
}

// being phobos-free keeps the size WAY down
private const(char)* toStringz(string s) { return (s ~ '\0').ptr; }
package(arsd) const(wchar)* toWStringz(wstring s) { return (s ~ '\0').ptr; }
package(arsd) const(wchar)* toWStringz(string s) {
	wstring r;
	foreach(dchar c; s)
		r ~= c;
	r ~= '\0';
	return r.ptr;
}
private string[] split(in void[] a, char c) {
		string[] ret;
		size_t previous = 0;
		foreach(i, char ch; cast(ubyte[]) a) {
			if(ch == c) {
				ret ~= cast(string) a[previous .. i];
				previous = i + 1;
			}
		}
		if(previous != a.length)
			ret ~= cast(string) a[previous .. $];
		return ret;
	}

version(without_opengl) {
	enum OpenGlOptions {
		no,
	}
} else {
	/++
		Determines if you want an OpenGL context created on the new window.


		See more: [#topics-3d|in the 3d topic].

		---
		import arsd.simpledisplay;
		void main() {
			auto window = new SimpleWindow(500, 500, "OpenGL Test", OpenGlOptions.yes);

			// Set up the matrix
			window.setAsCurrentOpenGlContext(); // make this window active

			// This is called on each frame, we will draw our scene
			window.redrawOpenGlScene = delegate() {

			};

			window.eventLoop(0);
		}
		---
	+/
	enum OpenGlOptions {
		no, /// No OpenGL context is created
		yes, /// Yes, create an OpenGL context
	}

	version(X11) {
		static if (!SdpyIsUsingIVGLBinds) {


			struct __GLXFBConfigRec {}
			alias GLXFBConfig = __GLXFBConfigRec*;

			//pragma(lib, "GL");
			//pragma(lib, "GLU");
			interface GLX {
			extern(C) nothrow @nogc {
				 XVisualInfo* glXChooseVisual(Display *dpy, int screen,
						const int *attrib_list);

				 void glXCopyContext(Display *dpy, GLXContext src,
						GLXContext dst, arch_ulong mask);

				 GLXContext glXCreateContext(Display *dpy, XVisualInfo *vis,
						GLXContext share_list, Bool direct);

				 GLXPixmap glXCreateGLXPixmap(Display *dpy, XVisualInfo *vis,
						Pixmap pixmap);

				 void glXDestroyContext(Display *dpy, GLXContext ctx);

				 void glXDestroyGLXPixmap(Display *dpy, GLXPixmap pix);

				 int glXGetConfig(Display *dpy, XVisualInfo *vis,
						int attrib, int *value);

				 GLXContext glXGetCurrentContext();

				 GLXDrawable glXGetCurrentDrawable();

				 Bool glXIsDirect(Display *dpy, GLXContext ctx);

				 Bool glXMakeCurrent(Display *dpy, GLXDrawable drawable,
						GLXContext ctx);

				 Bool glXQueryExtension(Display *dpy, int *error_base, int *event_base);

				 Bool glXQueryVersion(Display *dpy, int *major, int *minor);

				 void glXSwapBuffers(Display *dpy, GLXDrawable drawable);

				 void glXUseXFont(Font font, int first, int count, int list_base);

				 void glXWaitGL();

				 void glXWaitX();


				GLXFBConfig* glXChooseFBConfig (Display*, int, int*, int*);
				int glXGetFBConfigAttrib (Display*, GLXFBConfig, int, int*);
				XVisualInfo* glXGetVisualFromFBConfig (Display*, GLXFBConfig);

				char* glXQueryExtensionsString (Display*, int);
				void* glXGetProcAddress (const(char)*);

			}
			}

			version(OSX)
			mixin DynamicLoad!(GLX, "GL", 0, openGlLibrariesSuccessfullyLoaded) glx;
			else
			mixin DynamicLoad!(GLX, "GLX", 0, openGlLibrariesSuccessfullyLoaded) glx;
			shared static this() {
				glx.loadDynamicLibrary();
			}

			alias glbindGetProcAddress = glXGetProcAddress;
		}
	} else version(Windows) {
		/* it is done below by interface GL */
	} else
		static assert(0, "OpenGL not supported on your system yet. Try -version=X11 if you have X Windows available, or -version=without_opengl to go without.");
}

deprecated("Sorry, I misspelled it in the first version! Use `Resizability` instead.")
alias Resizablity = Resizability;

/// When you create a SimpleWindow, you can see its resizability to be one of these via the constructor...
enum Resizability {
	fixedSize, /// the window cannot be resized
	allowResizing, /// the window can be resized. The buffer (if there is one) will automatically adjust size, but not stretch the contents. the windowResized delegate will be called so you can respond to the new size yourself.
	automaticallyScaleIfPossible, /// if possible, your drawing buffer will remain the same size and simply be automatically scaled to the new window size. If this is impossible, it will not allow the user to resize the window at all. Note: window.width and window.height WILL be adjusted, which might throw you off if you draw based on them, so keep track of your expected width and height separately. That way, when it is scaled, things won't be thrown off.

	// FIXME: automaticallyScaleIfPossible should adjust the OpenGL viewport on resize events
}


/++
	Alignment for [ScreenPainter.drawText]. Left, Center, or Right may be combined with VerticalTop, VerticalCenter, or VerticalBottom via bitwise or.
+/
enum TextAlignment : uint {
	Left = 0, ///
	Center = 1, ///
	Right = 2, ///

	VerticalTop = 0, ///
	VerticalCenter = 4, ///
	VerticalBottom = 8, ///
}

public import arsd.color; // no longer stand alone... :-( but i need a common type for this to work with images easily.
alias Rectangle = arsd.color.Rectangle;


/++
	Keyboard press and release events.
+/
struct KeyEvent {
	/// see table below. Always use the symbolic names, even for ASCII characters, since the actual numbers vary across platforms. See [Key]
	Key key;
	ubyte hardwareCode; /// A platform and hardware specific code for the key
	bool pressed; /// true if the key was just pressed, false if it was just released. note: released events aren't always sent...

	deprecated("This never actually worked anyway, you should do a character event handler instead.") dchar character;

	uint modifierState; /// see enum [ModifierState]. They are bitwise combined together.

	SimpleWindow window; /// associated Window

	/++
		A view into the upcoming buffer holding coming character events that are sent if and only if neither
		the alt or super modifier keys are pressed (check this with `!(modifierState & (ModifierState.window | ModifierState.alt))`
		to predict if char events are actually coming..

		Only available on X systems since this information is not given ahead of time elsewhere.
		(Well, you COULD probably dig it up, but as far as I know right now, it isn't terribly pretty.)

		I'm adding this because it is useful to the terminal emulator, but given its platform specificness
		and potential quirks I'd recommend avoiding it.

		History:
			Added April 26, 2021 (dub v9.5)
	+/
	version(X11)
		dchar[] charsPossible;

	// convert key event to simplified string representation a-la emacs
	const(char)[] toStrBuf(bool growdest=false) (char[] dest) const nothrow @trusted {
		uint dpos = 0;
		void put (const(char)[] s...) nothrow @trusted {
			static if (growdest) {
				foreach (char ch; s) if (dpos < dest.length) dest.ptr[dpos++] = ch; else { dest ~= ch; ++dpos; }
			} else {
				foreach (char ch; s) if (dpos < dest.length) dest.ptr[dpos++] = ch;
			}
		}

		void putMod (ModifierState mod, Key key, string text) nothrow @trusted {
			if ((this.modifierState&mod) != 0 && (this.pressed || this.key != key)) put(text);
		}

		if (!this.key && !(this.modifierState&(ModifierState.ctrl|ModifierState.alt|ModifierState.shift|ModifierState.windows))) return null;

		// put modifiers
		// releasing modifier keys can produce bizarre things like "Ctrl+Ctrl", so hack around it
		putMod(ModifierState.ctrl, Key.Ctrl, "Ctrl+");
		putMod(ModifierState.alt, Key.Alt, "Alt+");
		putMod(ModifierState.windows, Key.Shift, "Windows+");
		putMod(ModifierState.shift, Key.Shift, "Shift+");

		if (this.key) {
			foreach (string kn; __traits(allMembers, Key)) {
				if (this.key == __traits(getMember, Key, kn)) {
					// HACK!
					static if (kn == "N0") put("0");
					else static if (kn == "N1") put("1");
					else static if (kn == "N2") put("2");
					else static if (kn == "N3") put("3");
					else static if (kn == "N4") put("4");
					else static if (kn == "N5") put("5");
					else static if (kn == "N6") put("6");
					else static if (kn == "N7") put("7");
					else static if (kn == "N8") put("8");
					else static if (kn == "N9") put("9");
					else put(kn);
					return dest[0..dpos];
				}
			}
			put("Unknown");
		} else {
			if (dpos && dest[dpos-1] == '+') --dpos;
		}
		return dest[0..dpos];
	}

	string toStr() () { return cast(string)toStrBuf!true(null); } // it is safe to cast here

	/** Parse string into key name with modifiers. It accepts things like:
	 *
	 * C-H-1 -- emacs style (ctrl, and windows, and 1)
	 *
	 * Ctrl+Win+1 -- windows style
	 *
	 * Ctrl-Win-1 -- '-' is a valid delimiter too
	 *
	 * Ctrl Win 1 -- and space
	 *
	 * and even "Win + 1 + Ctrl".
	 */
	static KeyEvent parse (const(char)[] name, bool* ignoreModsOut=null, int* updown=null) nothrow @trusted @nogc {
		auto nanchor = name; // keep it anchored, 'cause `name` may have NO_INTERIOR set

		// remove trailing spaces
		while (name.length && name[$-1] <= ' ') name = name[0..$-1];

		// tokens delimited by blank, '+', or '-'
		// null on eol
		const(char)[] getToken () nothrow @trusted @nogc {
			// remove leading spaces and delimiters
			while (name.length && (name[0] <= ' ' || name[0] == '+' || name[0] == '-')) name = name[1..$];
			if (name.length == 0) return null; // oops, no more tokens
			// get token
			size_t epos = 0;
			while (epos < name.length && name[epos] > ' ' && name[epos] != '+' && name[epos] != '-') ++epos;
			assert(epos > 0 && epos <= name.length);
			auto res = name[0..epos];
			name = name[epos..$];
			return res;
		}

		static bool strEquCI (const(char)[] s0, const(char)[] s1) pure nothrow @trusted @nogc {
			if (s0.length != s1.length) return false;
			foreach (immutable ci, char c0; s0) {
				if (c0 >= 'A' && c0 <= 'Z') c0 += 32; // poor man's tolower
				char c1 = s1[ci];
				if (c1 >= 'A' && c1 <= 'Z') c1 += 32; // poor man's tolower
				if (c0 != c1) return false;
			}
			return true;
		}

		if (ignoreModsOut !is null) *ignoreModsOut = false;
		if (updown !is null) *updown = -1;
		KeyEvent res;
		res.key = cast(Key)0; // just in case
		const(char)[] tk, tkn; // last token
		bool allowEmascStyle = true;
		bool ignoreModifiers = false;
		tokenloop: for (;;) {
			tk = tkn;
			tkn = getToken();
			//k8: yay, i took "Bloody Mess" trait from Fallout!
			if (tkn.length != 0 && tk.length == 0) { tk = tkn; continue tokenloop; }
			if (tkn.length == 0 && tk.length == 0) break; // no more tokens
			if (allowEmascStyle && tkn.length != 0) {
				if (tk.length == 1) {
					char mdc = tk[0];
					if (mdc >= 'a' && mdc <= 'z') mdc -= 32; // poor man's toupper()
					if (mdc == 'C' && (res.modifierState&ModifierState.ctrl) == 0) {res.modifierState |= ModifierState.ctrl; continue tokenloop; }
					if (mdc == 'M' && (res.modifierState&ModifierState.alt) == 0) { res.modifierState |= ModifierState.alt; continue tokenloop; }
					if (mdc == 'H' && (res.modifierState&ModifierState.windows) == 0) { res.modifierState |= ModifierState.windows; continue tokenloop; }
					if (mdc == 'S' && (res.modifierState&ModifierState.shift) == 0) { res.modifierState |= ModifierState.shift; continue tokenloop; }
					if (mdc == '*') { ignoreModifiers = true; continue tokenloop; }
					if (mdc == 'U' || mdc == 'R') { if (updown !is null) *updown = 0; continue tokenloop; }
					if (mdc == 'D' || mdc == 'P') { if (updown !is null) *updown = 1; continue tokenloop; }
				}
			}
			allowEmascStyle = false;
			if (strEquCI(tk, "Ctrl")) { res.modifierState |= ModifierState.ctrl; continue tokenloop; }
			if (strEquCI(tk, "Alt")) { res.modifierState |= ModifierState.alt; continue tokenloop; }
			if (strEquCI(tk, "Win") || strEquCI(tk, "Windows")) { res.modifierState |= ModifierState.windows; continue tokenloop; }
			if (strEquCI(tk, "Shift")) { res.modifierState |= ModifierState.shift; continue tokenloop; }
			if (strEquCI(tk, "Release")) { if (updown !is null) *updown = 0; continue tokenloop; }
			if (strEquCI(tk, "Press")) { if (updown !is null) *updown = 1; continue tokenloop; }
			if (tk == "*") { ignoreModifiers = true; continue tokenloop; }
			if (tk.length == 0) continue;
			// try key name
			if (res.key == 0) {
				// little hack
				if (tk.length == 1 && tk[0] >= '0' && tk[0] <= '9') {
					final switch (tk[0]) {
						case '0': tk = "N0"; break;
						case '1': tk = "N1"; break;
						case '2': tk = "N2"; break;
						case '3': tk = "N3"; break;
						case '4': tk = "N4"; break;
						case '5': tk = "N5"; break;
						case '6': tk = "N6"; break;
						case '7': tk = "N7"; break;
						case '8': tk = "N8"; break;
						case '9': tk = "N9"; break;
					}
				}
				foreach (string kn; __traits(allMembers, Key)) {
					if (strEquCI(tk, kn)) { res.key = __traits(getMember, Key, kn); continue tokenloop; }
				}
			}
			// unknown or duplicate key name, get out of here
			break;
		}
		if (ignoreModsOut !is null) *ignoreModsOut = ignoreModifiers;
		return res; // something
	}

	bool opEquals() (const(char)[] name) const nothrow @trusted @nogc {
		enum modmask = (ModifierState.ctrl|ModifierState.alt|ModifierState.shift|ModifierState.windows);
		void doModKey (ref uint mask, ref Key kk, Key k, ModifierState mst) {
			if (kk == k) { mask |= mst; kk = cast(Key)0; }
		}
		bool ignoreMods;
		int updown;
		auto ke = KeyEvent.parse(name, &ignoreMods, &updown);
		if ((updown == 0 && this.pressed) || (updown == 1 && !this.pressed)) return false;
		if (this.key != ke.key) {
			// things like "ctrl+alt" are complicated
			uint tkm = this.modifierState&modmask;
			uint kkm = ke.modifierState&modmask;
			Key tk = this.key;
			// ke
			doModKey(kkm, ke.key, Key.Ctrl, ModifierState.ctrl);
			doModKey(kkm, ke.key, Key.Alt, ModifierState.alt);
			doModKey(kkm, ke.key, Key.Windows, ModifierState.windows);
			doModKey(kkm, ke.key, Key.Shift, ModifierState.shift);
			// this
			doModKey(tkm, tk, Key.Ctrl, ModifierState.ctrl);
			doModKey(tkm, tk, Key.Alt, ModifierState.alt);
			doModKey(tkm, tk, Key.Windows, ModifierState.windows);
			doModKey(tkm, tk, Key.Shift, ModifierState.shift);
			return (tk == ke.key && tkm == kkm);
		}
		return (ignoreMods || ((this.modifierState&modmask) == (ke.modifierState&modmask)));
	}
}

/// Sets the application name.
@property string ApplicationName(string name) {
	return _applicationName = name;
}

string _applicationName;

/// ditto
@property string ApplicationName() {
	if(_applicationName is null) {
		import core.runtime;
		return Runtime.args[0];
	}
	return _applicationName;
}


/// Type of a [MouseEvent].
enum MouseEventType : int {
	motion = 0, /// The mouse moved inside the window
	buttonPressed = 1, /// A mouse button was pressed or the wheel was spun
	buttonReleased = 2, /// A mouse button was released
}

// FIXME: mouse move should be distinct from presses+releases, so we can avoid subscribing to those events in X unnecessarily
/++
	Listen for this on your event listeners if you are interested in mouse action.

	Note that [button] is used on mouse press and release events. If you are curious about which button is being held in during motion, use [modifierState] and check the bitmask for [ModifierState.leftButtonDown], etc.

	Examples:

	This will draw boxes on the window with the mouse as you hold the left button.
	---
	import arsd.simpledisplay;

	void main() {
		auto window = new SimpleWindow();

		window.eventLoop(0,
			(MouseEvent ev) {
				if(ev.modifierState & ModifierState.leftButtonDown) {
					auto painter = window.draw();
					painter.fillColor = Color.red;
					painter.outlineColor = Color.black;
					painter.drawRectangle(Point(ev.x / 16 * 16, ev.y / 16 * 16), 16, 16);
				}
			}
		);
	}
	---
+/
struct MouseEvent {
	MouseEventType type; /// movement, press, release, double click. See [MouseEventType]

	int x; /// Current X position of the cursor when the event fired, relative to the upper-left corner of the window, reported in pixels. (0, 0) is the upper left, (window.width - 1, window.height - 1) is the lower right corner of the window.
	int y; /// Current Y position of the cursor when the event fired.

	int dx; /// Change in X position since last report
	int dy; /// Change in Y position since last report

	MouseButton button; /// See [MouseButton]
	int modifierState; /// See [ModifierState]

	version(X11)
		private Time timestamp;

	/// Returns a linear representation of mouse button,
	/// for use with static arrays. Guaranteed to be >= 0 && <= 15
	///
	/// Its implementation is based on range-limiting `core.bitop.bsf(button) + 1`.
	@property ubyte buttonLinear() const {
		import core.bitop;
		if(button == 0)
			return 0;
		return (bsf(button) + 1) & 0b1111;
	}

	bool doubleClick; /// was it a double click? Only set on type == [MouseEventType.buttonPressed]

	SimpleWindow window; /// The window in which the event happened.

	Point globalCoordinates() {
		Point p;
		if(window is null)
			throw new Exception("wtf");
		static if(UsingSimpledisplayX11) {
			Window child;
			XTranslateCoordinates(
				XDisplayConnection.get,
				window.impl.window,
				RootWindow(XDisplayConnection.get, DefaultScreen(XDisplayConnection.get)),
				x, y, &p.x, &p.y, &child);
			return p;
		} else version(Windows) {
			POINT[1] points;
			points[0].x = x;
			points[0].y = y;
			MapWindowPoints(
				window.impl.hwnd,
				null,
				points.ptr,
				points.length
			);
			p.x = points[0].x;
			p.y = points[0].y;

			return p;
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	bool opEquals() (const(char)[] str) pure nothrow @trusted @nogc { return equStr(this, str); }

	/**
	can contain emacs-like modifier prefix
	case-insensitive names:
		lmbX/leftX
		rmbX/rightX
		mmbX/middleX
		wheelX
		motion (no prefix allowed)
	'X' is either "up" or "down" (or "-up"/"-down"); if omited, means "down"
	*/
	static bool equStr() (in auto ref MouseEvent event, const(char)[] str) pure nothrow @trusted @nogc {
		if (str.length == 0) return false; // just in case
		debug(arsd_mevent_strcmp) { import iv.cmdcon; conwriteln("str=<", str, ">"); }
		enum Flag : uint { Up = 0x8000_0000U, Down = 0x4000_0000U, Any = 0x1000_0000U }
		auto anchor = str;
		uint mods = 0; // uint.max == any
		// interesting bits in kmod
		uint kmodmask =
			ModifierState.shift|
			ModifierState.ctrl|
			ModifierState.alt|
			ModifierState.windows|
			ModifierState.leftButtonDown|
			ModifierState.middleButtonDown|
			ModifierState.rightButtonDown|
			0;
		uint lastButt = uint.max; // otherwise, bit 31 means "down"
		bool wasButtons = false;
		while (str.length) {
			if (str.ptr[0] <= ' ') {
				while (str.length && str.ptr[0] <= ' ') str = str[1..$];
				continue;
			}
			// one-letter modifier?
			if (str.length >= 2 && str.ptr[1] == '-') {
				switch (str.ptr[0]) {
					case '*': // "any" modifier (cannot be undone)
						mods = mods.max;
						break;
					case 'C': case 'c': // emacs "ctrl"
						if (mods != mods.max) mods |= ModifierState.ctrl;
						break;
					case 'M': case 'm': // emacs "meta"
						if (mods != mods.max) mods |= ModifierState.alt;
						break;
					case 'S': case 's': // emacs "shift"
						if (mods != mods.max) mods |= ModifierState.shift;
						break;
					case 'H': case 'h': // emacs "hyper" (aka winkey)
						if (mods != mods.max) mods |= ModifierState.windows;
						break;
					default:
						return false; // unknown modifier
				}
				str = str[2..$];
				continue;
			}
			// word
			char[16] buf = void; // locased
			auto wep = 0;
			while (str.length) {
				immutable char ch = str.ptr[0];
				if (ch <= ' ' || ch == '-') break;
				str = str[1..$];
				if (wep > buf.length) return false; // too long
						 if (ch >= 'A' && ch <= 'Z') buf.ptr[wep++] = cast(char)(ch+32); // poor man tolower
				else if (ch >= 'a' && ch <= 'z') buf.ptr[wep++] = ch;
				else return false; // invalid char
			}
			if (wep == 0) return false; // just in case
			uint bnum;
			enum UpDown { None = -1, Up, Down, Any }
			auto updown = UpDown.None; // 0: up; 1: down
			switch (buf[0..wep]) {
				// left button
				case "lmbup": case "leftup": updown = UpDown.Up; goto case "lmb";
				case "lmbdown": case "leftdown": updown = UpDown.Down; goto case "lmb";
				case "lmbany": case "leftany": updown = UpDown.Any; goto case "lmb";
				case "lmb": case "left": bnum = 0; break;
				// middle button
				case "mmbup": case "middleup": updown = UpDown.Up; goto case "mmb";
				case "mmbdown": case "middledown": updown = UpDown.Down; goto case "mmb";
				case "mmbany": case "middleany": updown = UpDown.Any; goto case "mmb";
				case "mmb": case "middle": bnum = 1; break;
				// right button
				case "rmbup": case "rightup": updown = UpDown.Up; goto case "rmb";
				case "rmbdown": case "rightdown": updown = UpDown.Down; goto case "rmb";
				case "rmbany": case "rightany": updown = UpDown.Any; goto case "rmb";
				case "rmb": case "right": bnum = 2; break;
				// wheel
				case "wheelup": updown = UpDown.Up; goto case "wheel";
				case "wheeldown": updown = UpDown.Down; goto case "wheel";
				case "wheelany": updown = UpDown.Any; goto case "wheel";
				case "wheel": bnum = 3; break;
				// motion
				case "motion": bnum = 7; break;
				// unknown
				default: return false;
			}
			debug(arsd_mevent_strcmp) { import iv.cmdcon; conprintfln("  0: mods=0x%08x; bnum=%u; updown=%s [%s]", mods, bnum, updown, str); }
			// parse possible "-up" or "-down"
			if (updown == UpDown.None && bnum < 7 && str.length > 0 && str.ptr[0] == '-') {
				wep = 0;
				foreach (immutable idx, immutable char ch; str[1..$]) {
					if (ch <= ' ' || ch == '-') break;
					assert(idx == wep); // for now; trick
					if (wep > buf.length) { wep = 0; break; } // too long
							 if (ch >= 'A' && ch <= 'Z') buf.ptr[wep++] = cast(char)(ch+32); // poor man tolower
					else if (ch >= 'a' && ch <= 'z') buf.ptr[wep++] = ch;
					else { wep = 0; break; } // invalid char
				}
						 if (wep == 2 && buf[0..wep] == "up") updown = UpDown.Up;
				else if (wep == 4 && buf[0..wep] == "down") updown = UpDown.Down;
				else if (wep == 3 && buf[0..wep] == "any") updown = UpDown.Any;
				// remove parsed part
				if (updown != UpDown.None) str = str[wep+1..$];
			}
			if (updown == UpDown.None) {
				updown = UpDown.Down;
			}
			wasButtons = wasButtons || (bnum <= 2);
			//assert(updown != UpDown.None);
			debug(arsd_mevent_strcmp) { import iv.cmdcon; conprintfln("  1: mods=0x%08x; bnum=%u; updown=%s [%s]", mods, bnum, updown, str); }
			// if we have a previous button, it goes to modifiers (unless it is a wheel or motion)
			if (lastButt != lastButt.max) {
				if ((lastButt&0xff) >= 3) return false; // wheel or motion
				if (mods != mods.max) {
					uint butbit = 0;
					final switch (lastButt&0x03) {
						case 0: butbit = ModifierState.leftButtonDown; break;
						case 1: butbit = ModifierState.middleButtonDown; break;
						case 2: butbit = ModifierState.rightButtonDown; break;
					}
					     if (lastButt&Flag.Down) mods |= butbit;
					else if (lastButt&Flag.Up) mods &= ~butbit;
					else if (lastButt&Flag.Any) kmodmask &= ~butbit;
				}
			}
			// remember last button
			lastButt = bnum|(updown == UpDown.Up ? Flag.Up : updown == UpDown.Any ? Flag.Any : Flag.Down);
		}
		// no button -- nothing to do
		if (lastButt == lastButt.max) return false;
		// done parsing, check if something's left
		foreach (immutable char ch; str) if (ch > ' ') return false; // oops
		// remove action button from mask
		if ((lastButt&0xff) < 3) {
			final switch (lastButt&0x03) {
				case 0: kmodmask &= ~cast(uint)ModifierState.leftButtonDown; break;
				case 1: kmodmask &= ~cast(uint)ModifierState.middleButtonDown; break;
				case 2: kmodmask &= ~cast(uint)ModifierState.rightButtonDown; break;
			}
		}
		// special case: "Motion" means "ignore buttons"
		if ((lastButt&0xff) == 7 && !wasButtons) {
			debug(arsd_mevent_strcmp) { import iv.cmdcon; conwriteln("  *: special motion"); }
			kmodmask &= ~cast(uint)(ModifierState.leftButtonDown|ModifierState.middleButtonDown|ModifierState.rightButtonDown);
		}
		uint kmod = event.modifierState&kmodmask;
		debug(arsd_mevent_strcmp) { import iv.cmdcon; conprintfln("  *: mods=0x%08x; lastButt=0x%08x; kmod=0x%08x; type=%s", mods, lastButt, kmod, event.type); }
		// check modifier state
		if (mods != mods.max) {
			if (kmod != mods) return false;
		}
		// now check type
		if ((lastButt&0xff) == 7) {
			// motion
			if (event.type != MouseEventType.motion) return false;
		} else if ((lastButt&0xff) == 3) {
			// wheel
			if (lastButt&Flag.Up) return (event.type == MouseEventType.buttonPressed && event.button == MouseButton.wheelUp);
			if (lastButt&Flag.Down) return (event.type == MouseEventType.buttonPressed && event.button == MouseButton.wheelDown);
			if (lastButt&Flag.Any) return (event.type == MouseEventType.buttonPressed && (event.button == MouseButton.wheelUp || event.button == MouseButton.wheelUp));
			return false;
		} else {
			// buttons
			if (((lastButt&Flag.Down) != 0 && event.type != MouseEventType.buttonPressed) ||
			    ((lastButt&Flag.Up) != 0 && event.type != MouseEventType.buttonReleased))
			{
				return false;
			}
			// button number
			switch (lastButt&0x03) {
				case 0: if (event.button != MouseButton.left) return false; break;
				case 1: if (event.button != MouseButton.middle) return false; break;
				case 2: if (event.button != MouseButton.right) return false; break;
				default: return false;
			}
		}
		return true;
	}
}

version(arsd_mevent_strcmp_test) unittest {
	MouseEvent event;
	event.type = MouseEventType.buttonPressed;
	event.button = MouseButton.left;
	event.modifierState = ModifierState.ctrl;
	assert(event == "C-LMB");
	assert(event != "C-LMBUP");
	assert(event != "C-LMB-UP");
	assert(event != "C-S-LMB");
	assert(event == "*-LMB");
	assert(event != "*-LMB-UP");

	event.type = MouseEventType.buttonReleased;
	assert(event != "C-LMB");
	assert(event == "C-LMBUP");
	assert(event == "C-LMB-UP");
	assert(event != "C-S-LMB");
	assert(event != "*-LMB");
	assert(event == "*-LMB-UP");

	event.button = MouseButton.right;
	event.modifierState |= ModifierState.shift;
	event.type = MouseEventType.buttonPressed;
	assert(event != "C-LMB");
	assert(event != "C-LMBUP");
	assert(event != "C-LMB-UP");
	assert(event != "C-S-LMB");
	assert(event != "*-LMB");
	assert(event != "*-LMB-UP");

	assert(event != "C-RMB");
	assert(event != "C-RMBUP");
	assert(event != "C-RMB-UP");
	assert(event == "C-S-RMB");
	assert(event == "*-RMB");
	assert(event != "*-RMB-UP");
}

/// This gives a few more options to drawing lines and such
struct Pen {
	Color color; /// the foreground color
	int width = 1; /// width of the line. please note that on X, wide lines are drawn centered on the coordinates, so you may have to offset things.
	Style style; /// See [Style]
/+
// From X.h

#define LineSolid		0
#define LineOnOffDash		1
#define LineDoubleDash		2
       LineDou-        The full path of the line is drawn, but the
       bleDash         even dashes are filled differently from the
                       odd dashes (see fill-style) with CapButt
                       style used where even and odd dashes meet.



/* capStyle */

#define CapNotLast		0
#define CapButt			1
#define CapRound		2
#define CapProjecting		3

/* joinStyle */

#define JoinMiter		0
#define JoinRound		1
#define JoinBevel		2

/* fillStyle */

#define FillSolid		0
#define FillTiled		1
#define FillStippled		2
#define FillOpaqueStippled	3


+/
	/// Style of lines drawn
	enum Style {
		Solid, /// a solid line
		Dashed, /// a dashed line
		Dotted, /// a dotted line
	}
}


/++
	Represents an in-memory image in the format that the GUI expects, but with its raw data available to your program.


	On Windows, this means a device-independent bitmap. On X11, it is an XImage.

	$(NOTE If you are writing platform-aware code and need to know low-level details, uou may check `if(Image.impl.xshmAvailable)` to see if MIT-SHM is used on X11 targets to draw `Image`s and `Sprite`s. Use `static if(UsingSimpledisplayX11)` to determine if you are compiling for an X11 target.)

	Drawing an image to screen is not necessarily fast, but applying algorithms to draw to the image itself should be fast. An `Image` is also the first step in loading and displaying images loaded from files.

	If you intend to draw an image to screen several times, you will want to convert it into a [Sprite].

	$(PITFALL `Image` may represent a scarce, shared resource that persists across process termination, and should be disposed of properly. On X11, it uses the MIT-SHM extension, if available, which uses shared memory handles with the X server, which is a long-lived process that holds onto them after your program terminates if you don't free it.

	It is possible for your user's system to run out of these handles over time, forcing them to clean it up with extraordinary measures - their GUI is liable to stop working!

	Be sure these are cleaned up properly. simpledisplay will do its best to do the right thing, including cleaning them up in garbage collection sweeps (one of which is run at most normal program terminations) and catching some deadly signals. It will almost always do the right thing. But, this is no substitute for you managing the resource properly yourself. (And try not to segfault, as recovery from them is alway dicey!)

	Please call `destroy(image);` when you are done with it. The easiest way to do this is with scope:

	---
		auto image = new Image(256, 256);
		scope(exit) destroy(image);
	---

	As long as you don't hold on to it outside the scope.

	I might change it to be an owned pointer at some point in the future.

	)

	Drawing pixels on the image may be simple, using the `opIndexAssign` function, but
	you can also often get a fair amount of speedup by getting the raw data format and
	writing some custom code.

	FIXME INSERT EXAMPLES HERE


+/
final class Image {
	///
	this(int width, int height, bool forcexshm=false, bool enableAlpha = false) {
		this.width = width;
		this.height = height;
		this.enableAlpha = enableAlpha;

		impl.createImage(width, height, forcexshm, enableAlpha);
	}

	///
	this(Size size, bool forcexshm=false, bool enableAlpha = false) {
		this(size.width, size.height, forcexshm, enableAlpha);
	}

	private bool suppressDestruction;

	version(X11)
	this(XImage* handle) {
		this.handle = handle;
		this.rawData = cast(ubyte*) handle.data;
		this.width = handle.width;
		this.height = handle.height;
		this.enableAlpha = handle.depth == 32;
		suppressDestruction = true;
	}

	~this() {
		if(suppressDestruction) return;
		impl.dispose();
	}

	// these numbers are used for working with rawData itself, skipping putPixel and getPixel
	/// if you do the math yourself you might be able to optimize it. Call these functions only once and cache the value.
	pure const @system nothrow {
		/*
			To use these to draw a blue rectangle with size WxH at position X,Y...

			// make certain that it will fit before we proceed
			enforce(X + W <= img.width && Y + H <= img.height); // you could also adjust the size to clip it, but be sure not to run off since this here will do raw pointers with no bounds checks!

			// gather all the values you'll need up front. These can be kept until the image changes size if you want
			// (though calculating them isn't really that expensive).
			auto nextLineAdjustment = img.adjustmentForNextLine();
			auto offR = img.redByteOffset();
			auto offB = img.blueByteOffset();
			auto offG = img.greenByteOffset();
			auto bpp = img.bytesPerPixel();

			auto data = img.getDataPointer();

			// figure out the starting byte offset
			auto offset = img.offsetForTopLeftPixel() + nextLineAdjustment*Y + bpp * X;

			auto startOfLine = data + offset; // get our pointer lined up on the first pixel

			// and now our drawing loop for the rectangle
			foreach(y; 0 .. H) {
				auto data = startOfLine; // we keep the start of line separately so moving to the next line is simple and portable
				foreach(x; 0 .. W) {
					// write our color
					data[offR] = 0;
					data[offG] = 0;
					data[offB] = 255;

					data += bpp; // moving to the next pixel is just an addition...
				}
				startOfLine += nextLineAdjustment;
			}


			As you can see, the loop itself was very simple thanks to the calculations being moved outside.

			FIXME: I wonder if I can make the pixel formats consistently 32 bit across platforms, so the color offsets
			can be made into a bitmask or something so we can write them as *uint...
		*/

		///
		int offsetForTopLeftPixel() {
			version(X11) {
				return 0;
			} else version(Windows) {
				if(enableAlpha) {
					return (width * 4) * (height - 1);
				} else {
					return (((cast(int) width * 3 + 3) / 4) * 4) * (height - 1);
				}
			} else version(OSXCocoa) {
				return 0 ; //throw new NotYetImplementedException();
			} else static assert(0, "fill in this info for other OSes");
		}

		///
		int offsetForPixel(int x, int y) {
			version(X11) {
				auto offset = (y * width + x) * 4;
				return offset;
			} else version(Windows) {
				if(enableAlpha) {
					auto itemsPerLine = width * 4;
					// remember, bmps are upside down
					auto offset = itemsPerLine * (height - y - 1) + x * 4;
					return offset;
				} else {
					auto itemsPerLine = ((cast(int) width * 3 + 3) / 4) * 4;
					// remember, bmps are upside down
					auto offset = itemsPerLine * (height - y - 1) + x * 3;
					return offset;
				}
			} else version(OSXCocoa) {
				return 0 ; //throw new NotYetImplementedException();
			} else static assert(0, "fill in this info for other OSes");
		}

		///
		int adjustmentForNextLine() {
			version(X11) {
				return width * 4;
			} else version(Windows) {
				// windows bmps are upside down, so the adjustment is actually negative
				if(enableAlpha)
					return - (cast(int) width * 4);
				else
					return -((cast(int) width * 3 + 3) / 4) * 4;
			} else version(OSXCocoa) {
				return 0 ; //throw new NotYetImplementedException();
			} else static assert(0, "fill in this info for other OSes");
		}

		/// once you have the position of a pixel, use these to get to the proper color
		int redByteOffset() {
			version(X11) {
				return 2;
			} else version(Windows) {
				return 2;
			} else version(OSXCocoa) {
				return 0 ; //throw new NotYetImplementedException();
			} else static assert(0, "fill in this info for other OSes");
		}

		///
		int greenByteOffset() {
			version(X11) {
				return 1;
			} else version(Windows) {
				return 1;
			} else version(OSXCocoa) {
				return 0 ; //throw new NotYetImplementedException();
			} else static assert(0, "fill in this info for other OSes");
		}

		///
		int blueByteOffset() {
			version(X11) {
				return 0;
			} else version(Windows) {
				return 0;
			} else version(OSXCocoa) {
				return 0 ; //throw new NotYetImplementedException();
			} else static assert(0, "fill in this info for other OSes");
		}

		/// Only valid if [enableAlpha] is true
		int alphaByteOffset() {
			version(X11) {
				return 3;
			} else version(Windows) {
				return 3;
			} else version(OSXCocoa) {
				return 3; //throw new NotYetImplementedException();
			} else static assert(0, "fill in this info for other OSes");
		}
	}

	///
	final void putPixel(int x, int y, Color c) {
		if(x < 0 || x >= width)
			return;
		if(y < 0 || y >= height)
			return;

		impl.setPixel(x, y, c);
	}

	///
	final Color getPixel(int x, int y) {
		if(x < 0 || x >= width)
			return Color.transparent;
		if(y < 0 || y >= height)
			return Color.transparent;

		version(OSXCocoa) throw new NotYetImplementedException(); else
		return impl.getPixel(x, y);
	}

	///
	final void opIndexAssign(Color c, int x, int y) {
		putPixel(x, y, c);
	}

	///
	TrueColorImage toTrueColorImage() {
		auto tci = new TrueColorImage(width, height);
		convertToRgbaBytes(tci.imageData.bytes);
		return tci;
	}

	///
	static Image fromMemoryImage(MemoryImage i, bool enableAlpha = false) {
		auto tci = i.getAsTrueColorImage();
		auto img = new Image(tci.width, tci.height, false, enableAlpha);
		img.setRgbaBytes(tci.imageData.bytes);
		return img;
	}

	/// this is here for interop with arsd.image. where can be a TrueColorImage's data member
	/// if you pass in a buffer, it will put it right there. length must be width*height*4 already
	/// if you pass null, it will allocate a new one.
	ubyte[] getRgbaBytes(ubyte[] where = null) {
		if(where is null)
			where = new ubyte[this.width*this.height*4];
		convertToRgbaBytes(where);
		return where;
	}

	/// this is here for interop with arsd.image. from can be a TrueColorImage's data member
	void setRgbaBytes(in ubyte[] from ) {
		assert(from.length == this.width * this.height * 4);
		setFromRgbaBytes(from);
	}

	// FIXME: make properly cross platform by getting rgba right

	/// warning: this is not portable across platforms because the data format can change
	ubyte* getDataPointer() {
		return impl.rawData;
	}

	/// for use with getDataPointer
	final int bytesPerLine() const pure @safe nothrow {
		version(Windows)
			return enableAlpha ? (width * 4) : (((cast(int) width * 3 + 3) / 4) * 4);
		else version(X11)
			return 4 * width;
		else version(OSXCocoa)
			return 4 * width;
		else static assert(0);
	}

	/// for use with getDataPointer
	final int bytesPerPixel() const pure @safe nothrow {
		version(Windows)
			return enableAlpha ? 4 : 3;
		else version(X11)
			return 4;
		else version(OSXCocoa)
			return 4;
		else static assert(0);
	}

	///
	immutable int width;

	///
	immutable int height;

	///
	immutable bool enableAlpha;
    //private:
	mixin NativeImageImplementation!() impl;
}

/// A convenience function to pop up a window displaying the image.
/// If you pass a win, it will draw the image in it. Otherwise, it will
/// create a window with the size of the image and run its event loop, closing
/// when a key is pressed.
void displayImage(Image image, SimpleWindow win = null) {
	if(win is null) {
		win = new SimpleWindow(image);
		{
			auto p = win.draw;
			p.drawImage(Point(0, 0), image);
		}
		win.eventLoop(0,
			(KeyEvent ev) {
				if (ev.pressed && (ev.key == Key.Escape || ev.key == Key.Space)) win.close();
			} );
	} else {
		win.image = image;
	}
}

enum FontWeight : int {
	dontcare = 0,
	thin = 100,
	extralight = 200,
	light = 300,
	regular = 400,
	medium = 500,
	semibold = 600,
	bold = 700,
	extrabold = 800,
	heavy = 900
}

// FIXME: i need a font cache and it needs to handle disconnects.

/++
	Represents a font loaded off the operating system or the X server.


	While the api here is unified cross platform, the fonts are not necessarily
	available, even across machines of the same platform, so be sure to always check
	for null (using [isNull]) and have a fallback plan.

	When you have a font you like, use [ScreenPainter.setFont] to load it for drawing.

	Worst case, a null font will automatically fall back to the default font loaded
	for your system.
+/
class OperatingSystemFont {
	// FIXME: when the X Connection is lost, these need to be invalidated!
	// that means I need to store the original stuff again to reconstruct it too.

	version(X11) {
		XFontStruct* font;
		XFontSet fontset;

		version(with_xft) {
			XftFont* xftFont;
			bool isXft;
		}
	} else version(Windows) {
		HFONT font;
		int width_;
		int height_;
	} else version(OSXCocoa) {
		// FIXME
	} else static assert(0);

	/++
		Constructs the class and immediately calls [load].
	+/
	this(string name, int size = 0, FontWeight weight = FontWeight.dontcare, bool italic = false) {
		load(name, size, weight, italic);
	}

	/++
		Constructs the object, but does nothing. Call one of [load] or [loadDefault] to populate the object.

		You can also call the platform-specific [loadXft], [loadCoreX], or [loadWin32] functions if appropriate for you.

		History:
			Added January 24, 2021.
	+/
	this() {
		// this space intentionally left blank
	}

	/++
		Loads specifically with the Xft library - a freetype font from a fontconfig string.

		History:
			Added November 13, 2020.
	+/
	version(with_xft)
	bool loadXft(string name, int size = 0, FontWeight weight = FontWeight.dontcare, bool italic = false) {
		unload();

		if(!XftLibrary.attempted) {
			XftLibrary.loadDynamicLibrary();
		}

		if(!XftLibrary.loadSuccessful)
			return false;

		auto display = XDisplayConnection.get;

		char[256] nameBuffer = void;
		int nbp = 0;

		void add(in char[] a) {
			nameBuffer[nbp .. nbp + a.length] = a[];
			nbp += a.length;
		}
		add(name);

		if(size) {
			add(":size=");
			add(toInternal!string(size));
		}
		if(weight != FontWeight.dontcare) {
			add(":weight=");
			add(weightToString(weight));
		}
		if(italic)
			add(":slant=100");

		nameBuffer[nbp] = 0;

		this.xftFont = XftFontOpenName(
			display,
			DefaultScreen(display),
			nameBuffer.ptr
		);

		this.isXft = true;

		if(xftFont !is null) {
			isMonospace_ = stringWidth("x") == stringWidth("M");
			ascent_ = xftFont.ascent;
			descent_ = xftFont.descent;
		}

		return !isNull();
	}

	/++
		Lists available fonts from the system that match the given pattern, finding names that are suitable for passing to [OperatingSystemFont]'s constructor.


		Fonts will be fed to you (possibly! it is platform and implementation dependent on if it is called immediately or later) asynchronously through the given delegate. It should return `true` if you want more, `false` if you are done. The delegate will be called once after finishing with a `init` value to let you know it is done and you can do final processing.

		If `pattern` is null, it returns all available font families.

		Please note that you may also receive fonts that do not match your given pattern. You should still filter them in the handler; the pattern is really just an optimization hint rather than a formal guarantee.

		The format of the pattern is platform-specific.

		History:
			Added May 1, 2021 (dub v9.5)
	+/
	static void listFonts(string pattern, bool delegate(in char[] name) handler) {
		version(Windows) {
			auto hdc = GetDC(null);
			scope(exit) ReleaseDC(null, hdc);
			LOGFONT logfont;
			static extern(Windows) int proc(const LOGFONT* lf, const TEXTMETRIC* tm, DWORD type, LPARAM p) {
				auto localHandler = *(cast(typeof(handler)*) p);
				return localHandler(lf.lfFaceName[].sliceCString) ? 1 : 0;
			}
			EnumFontFamiliesEx(hdc, &logfont, &proc, cast(LPARAM) &handler, 0);
		} else version(X11) {
			//import core.stdc.stdio;
			bool done = false;
			version(with_xft) {
				if(!XftLibrary.attempted) {
					XftLibrary.loadDynamicLibrary();
				}

				if(!XftLibrary.loadSuccessful)
					goto skipXft;

				if(!FontConfigLibrary.attempted)
					FontConfigLibrary.loadDynamicLibrary();
				if(!FontConfigLibrary.loadSuccessful)
					goto skipXft;

				{
					auto got = XftListFonts(XDisplayConnection.get, 0, null, "family".ptr, "style".ptr, null);
					if(got is null)
						goto skipXft;
					scope(exit) FcFontSetDestroy(got);

					auto fontPatterns = got.fonts[0 .. got.nfont];
					foreach(candidate; fontPatterns) {
						char* where, whereStyle;

						char* pmg = FcNameUnparse(candidate);

						//FcPatternGetString(candidate, "family", 0, &where);
						//FcPatternGetString(candidate, "style", 0, &whereStyle);
						//if(where && whereStyle) {
						if(pmg) {
							if(!handler(pmg.sliceCString))
								return;
							//printf("%s || %s %s\n", pmg, where, whereStyle);
						}
					}
				}
			}

			skipXft:

			if(pattern is null)
				pattern = "*";

			int count;
			auto coreFontsRaw = XListFonts(XDisplayConnection.get, pattern.toStringz, 10000 /* max return */, &count);
			scope(exit) XFreeFontNames(coreFontsRaw);

			auto coreFonts = coreFontsRaw[0 .. count];

			foreach(font; coreFonts) {
				char[128] tmp;
				tmp[0 ..5] = "core:";
				auto cf = font.sliceCString;
				if(5 + cf.length > tmp.length)
					assert(0, "a font name was too long, sorry i didn't bother implementing a fallback");
				tmp[5 .. 5 + cf.length] = cf;
				if(!handler(tmp[0 .. 5 + cf.length]))
					return;
			}
		}
	}

	/++
		Returns the raw content of the ttf file, if possible. This allows you to use OperatingSystemFont
		to look up fonts that you then pass to things like [arsd.game.OpenGlLimitedFont] or [arsd.nanovega].

		Returns null if impossible. It is impossible if the loaded font is not a local TTF file or if the
		underlying system doesn't support returning the raw bytes.

		History:
			Added September 10, 2021 (dub v10.3)
	+/
	ubyte[] getTtfBytes() {
		if(isNull)
			return null;

		version(Windows) {
			auto dc = GetDC(null);
			auto orig = SelectObject(dc, font);

			scope(exit) {
				SelectObject(dc, orig);
				ReleaseDC(null, dc);
			}

			auto res = GetFontData(dc, 0 /* whole file */, 0 /* offset */, null, 0);
			if(res == GDI_ERROR)
				return null;

			ubyte[] buffer = new ubyte[](res);
			res = GetFontData(dc, 0 /* whole file */, 0 /* offset */, buffer.ptr, cast(DWORD) buffer.length);
			if(res == GDI_ERROR)
				return null; // wtf really tbh

			return buffer;
		} else version(with_xft) {
			if(isXft && xftFont) {
				if(!FontConfigLibrary.attempted)
					FontConfigLibrary.loadDynamicLibrary();
				if(!FontConfigLibrary.loadSuccessful)
					return null;

				char* file;
				if (FcPatternGetString(xftFont.pattern, "file", 0, &file) == 0 /*FcResultMatch*/) {
					if (file !is null && file[0]) {
						import core.stdc.stdio;
						auto fp = fopen(file, "rb");
						if(fp is null)
							return null;
						scope(exit)
							fclose(fp);
						fseek(fp, 0, SEEK_END);
						ubyte[] buffer = new ubyte[](ftell(fp));
						fseek(fp, 0, SEEK_SET);

						auto got = fread(buffer.ptr, 1, buffer.length, fp);
						if(got != buffer.length)
							return null;

						return buffer;
					}
				}
			}
			return null;
		}
	}

	// see also: XftLockFace(font) which gives a FT_Face. from /usr/include/X11/Xft/Xft.h line 352

	private string weightToString(FontWeight weight) {
		with(FontWeight)
		final switch(weight) {
			case dontcare: return "*";
			case thin: return "extralight";
			case extralight: return "extralight";
			case light: return "light";
			case regular: return "regular";
			case medium: return "medium";
			case semibold: return "demibold";
			case bold: return "bold";
			case extrabold: return "demibold";
			case heavy: return "black";
		}
	}

	/++
		Loads specifically a Core X font - rendered on the X server without antialiasing. Best performance.

		History:
			Added November 13, 2020. Before then, this code was integrated in the [load] function.
	+/
	version(X11)
	bool loadCoreX(string name, int size = 0, FontWeight weight = FontWeight.dontcare, bool italic = false) {
		unload();

		string xfontstr;

		if(name.length > 3 && name[0 .. 3] == "-*-") {
			// this is kinda a disgusting hack but if the user sends an exact
			// string I'd like to honor it...
			xfontstr = name;
		} else {
			string weightstr = weightToString(weight);
			string sizestr;
			if(size == 0)
				sizestr = "*";
			else
				sizestr = toInternal!string(size);
			xfontstr = "-*-"~name~"-"~weightstr~"-"~(italic ? "i" : "r")~"-*-*-"~sizestr~"-*-*-*-*-*-*-*\0";
		}

		//import std.stdio; writeln(xfontstr);

		auto display = XDisplayConnection.get;

		font = XLoadQueryFont(display, xfontstr.ptr);
		if(font is null)
			return false;

		char** lol;
		int lol2;
		char* lol3;
		fontset = XCreateFontSet(display, xfontstr.ptr, &lol, &lol2, &lol3);

		prepareFontInfo();

		return !isNull();
	}

	version(X11)
	private void prepareFontInfo() {
		if(font !is null) {
			isMonospace_ = stringWidth("l") == stringWidth("M");
			ascent_ = font.max_bounds.ascent;
			descent_ = font.max_bounds.descent;
		}
	}

	/++
		Loads a Windows font. You probably want to use [load] instead to be more generic.

		History:
			Added November 13, 2020. Before then, this code was integrated in the [load] function.
	+/
	version(Windows)
	bool loadWin32(string name, int size = 0, FontWeight weight = FontWeight.dontcare, bool italic = false, HDC hdc = null) {
		unload();

		WCharzBuffer buffer = WCharzBuffer(name);
		font = CreateFont(size, 0, 0, 0, cast(int) weight, italic, 0, 0, 0, 0, 0, 0, 0, buffer.ptr);

		prepareFontInfo(hdc);

		return !isNull();
	}

	version(Windows)
	void prepareFontInfo(HDC hdc = null) {
		if(font is null)
			return;

		TEXTMETRIC tm;
		auto dc = hdc ? hdc : GetDC(null);
		auto orig = SelectObject(dc, font);
		GetTextMetrics(dc, &tm);
		SelectObject(dc, orig);
		if(hdc is null)
			ReleaseDC(null, dc);

		width_ = tm.tmAveCharWidth;
		height_ = tm.tmHeight;
		ascent_ = tm.tmAscent;
		descent_ = tm.tmDescent;
		// If this bit is set the font is a variable pitch font. If this bit is clear the font is a fixed pitch font. Note very carefully that those meanings are the opposite of what the constant name implies.
		isMonospace_ = (tm.tmPitchAndFamily & TMPF_FIXED_PITCH) == 0;
	}


	/++
		`name` is a font name, but it can also be a more complicated string parsed in an OS-specific way.

		On X, you may prefix a name with `core:` to bypass the freetype engine causing this function to forward to [loadCoreX]. Otherwise,
		it calls [loadXft] if the library is available. If the library or font is not available on Xft, it falls back on [loadCoreX].

		On Windows, it forwards directly to [loadWin32].

		Params:
			name = font name. This is looked up by the operating system and may be interpreted differently across platforms or user machines and their preferences.
			size = font size. This may be interpreted differently by different systems and different fonts. Size 0 means load a default, which may not exist and cause [isNull] to become true.
			weight = approximate boldness, results may vary.
			italic = try to get a slanted version of the given font.

		History:
			Xft support was added on November 13, 2020. It would only load core fonts. Xft inclusion changed font lookup and interpretation of the `size` parameter, requiring a major version bump. This caused release v9.0.
	+/
	bool load(string name, int size = 0, FontWeight weight = FontWeight.dontcare, bool italic = false) {
		version(X11) {
			version(with_xft) {
				if(name.length > 5 && name[0 .. 5] == "core:") {
					goto core;
				}

				if(loadXft(name, size, weight, italic))
					return true;
				// if xft fails, fallback to core to avoid breaking
				// code that already depended on this.
			}

			core:

			if(name.length > 5 && name[0 .. 5] == "core:") {
				name = name[5 .. $];
			}

			return loadCoreX(name, size, weight, italic);
		} else version(Windows) {
			return loadWin32(name, size, weight, italic);
		} else version(OSXCocoa) {
			// FIXME
			return false;
		} else static assert(0);
	}

	///
	void unload() {
		if(isNull())
			return;

		version(X11) {
			auto display = XDisplayConnection.display;

			if(display is null)
				return;

			version(with_xft) {
				if(isXft) {
					if(xftFont)
						XftFontClose(display, xftFont);
					isXft = false;
					xftFont = null;
					return;
				}
			}

			if(font && font !is ScreenPainterImplementation.defaultfont)
				XFreeFont(display, font);
			if(fontset && fontset !is ScreenPainterImplementation.defaultfontset)
				XFreeFontSet(display, fontset);

			font = null;
			fontset = null;
		} else version(Windows) {
			DeleteObject(font);
			font = null;
		} else version(OSXCocoa) {
			// FIXME
		} else static assert(0);
	}

	private bool isMonospace_;

	/++
		History:
			Added January 16, 2021
	+/
	bool isMonospace() {
		return isMonospace_;
	}

	/++
		Returns the average width of the font, conventionally defined as the width of the lowercase 'x' character.

		History:
			Added March 26, 2020
			Documented January 16, 2021
	+/
	int averageWidth() {
		version(X11) {
			return stringWidth("x");
		} else version(Windows)
			return width_;
		else assert(0);
	}

	/++
		Returns the width of the string as drawn on the specified window, or the default screen if the window is null.

		History:
			Added January 16, 2021
	+/
	int stringWidth(scope const(char)[] s, SimpleWindow window = null) {
	// FIXME: what about tab?
		if(isNull)
			return 0;

		version(X11) {
			version(with_xft)
				if(isXft && xftFont !is null) {
					//return xftFont.max_advance_width;
					XGlyphInfo extents;
					XftTextExtentsUtf8(XDisplayConnection.get, xftFont, s.ptr, cast(int) s.length, &extents);
					//import std.stdio; writeln(extents);
					return extents.xOff;
				}
			if(font is null)
				return 0;
			else if(fontset) {
				XRectangle rect;
				Xutf8TextExtents(fontset, s.ptr, cast(int) s.length, null, &rect);

				return rect.width;
			} else {
				return XTextWidth(font, s.ptr, cast(int) s.length);
			}
		} else version(Windows) {
			WCharzBuffer buffer = WCharzBuffer(s);

			return stringWidth(buffer.slice, window);
		}
		else assert(0);
	}

	version(Windows)
	/// ditto
	int stringWidth(scope const(wchar)[] s, SimpleWindow window = null) {
		if(isNull)
			return 0;
		version(Windows) {
			SIZE size;

			prepareContext(window);
			scope(exit) releaseContext();

			GetTextExtentPoint32W(dc, s.ptr, cast(int) s.length, &size);

			return size.cx;
		} else {
			// std.conv can do this easily but it is slow to import and i don't think it is worth it
			static assert(0, "not implemented yet");
			//return stringWidth(s, window);
		}
	}

	private {
		int prepRefcount;

		version(Windows) {
			HDC dc;
			HANDLE orig;
			HWND hwnd;
		}
	}
	/++
		[stringWidth] can be slow. This helps speed it up if you are doing a lot of calculations. Just prepareContext when you start this work and releaseContext when you are done. Important to release before too long though as it can be a scarce system resource.

		History:
			Added January 23, 2021
	+/
	void prepareContext(SimpleWindow window = null) {
		prepRefcount++;
		if(prepRefcount == 1) {
			version(Windows) {
				hwnd = window is null ? null : window.impl.hwnd;
				dc = GetDC(hwnd);
				orig = SelectObject(dc, font);
			}
		}
	}
	/// ditto
	void releaseContext() {
		prepRefcount--;
		if(prepRefcount == 0) {
			version(Windows) {
				SelectObject(dc, orig);
				ReleaseDC(hwnd, dc);
				hwnd = null;
				dc = null;
				orig = null;
			}
		}
	}

	/+
		FIXME: I think I need advance and kerning pair

		int advance(dchar from, dchar to) { } // use dchar.init for first item in string
	+/

	/++
		Returns the height of the font.

		History:
			Added March 26, 2020
			Documented January 16, 2021
	+/
	int height() {
		version(X11) {
			version(with_xft)
				if(isXft && xftFont !is null) {
					return xftFont.ascent + xftFont.descent; // i don't use height here because it doesn't include the baseline pixel
				}
			if(font is null)
				return 0;
			return font.max_bounds.ascent + font.max_bounds.descent;
		} else version(Windows)
			return height_;
		else assert(0);
	}

	private int ascent_;
	private int descent_;

	/++
		Max ascent above the baseline.

		History:
			Added January 22, 2021
	+/
	int ascent() {
		return ascent_;
	}

	/++
		Max descent below the baseline.

		History:
			Added January 22, 2021
	+/
	int descent() {
		return descent_;
	}

	/++
		Loads the default font used by [ScreenPainter] if none others are loaded.

		Returns:
			This method mutates the `this` object, but then returns `this` for
			easy chaining like:

			---
			auto font = foo.isNull ? foo : foo.loadDefault
			---

		History:
			Added previously, but left unimplemented until January 24, 2021.
	+/
	OperatingSystemFont loadDefault() {
		unload();

		version(X11) {
			// another option would be https://tronche.com/gui/x/xlib/graphics/font-metrics/XQueryFont.html
			// but meh since sdpy does its own thing, this should be ok too

			ScreenPainterImplementation.ensureDefaultFontLoaded();
			this.font = ScreenPainterImplementation.defaultfont;
			this.fontset = ScreenPainterImplementation.defaultfontset;

			prepareFontInfo();
		} else version(Windows) {
			ScreenPainterImplementation.ensureDefaultFontLoaded();
			this.font = ScreenPainterImplementation.defaultGuiFont;

			prepareFontInfo();
		} else throw new NotYetImplementedException();

		return this;
	}

	///
	bool isNull() {
		version(OSXCocoa) throw new NotYetImplementedException(); else {
			version(with_xft)
				if(isXft)
					return xftFont is null;
			return font is null;
		}
	}

	/* Metrics */
	/+
		GetABCWidth
		GetKerningPairs

		if I do it right, I can size it all here, and match
		what happens when I draw the full string with the OS functions.

		subclasses might do the same thing while getting the glyphs on images
	struct GlyphInfo {
		int glyph;

		size_t stringIdxStart;
		size_t stringIdxEnd;

		Rectangle boundingBox;
	}
	GlyphInfo[] getCharBoxes() {
		// XftTextExtentsUtf8
		return null;

	}
	+/

	~this() {
		unload();
	}
}

version(Windows)
private string sliceCString(const(wchar)[] w) {
	return makeUtf8StringFromWindowsString(cast(wchar*) w.ptr);
}

private inout(char)[] sliceCString(inout(char)* s) {
	import core.stdc.string;
	auto len = strlen(s);
	return s[0 .. len];
}

/**
	The 2D drawing proxy. You acquire one of these with [SimpleWindow.draw] rather
	than constructing it directly. Then, it is reference counted so you can pass it
	at around and when the last ref goes out of scope, the buffered drawing activities
	are all carried out.


	Most functions use the outlineColor instead of taking a color themselves.
	ScreenPainter is reference counted and draws its buffer to the screen when its
	final reference goes out of scope.
*/
struct ScreenPainter {
	CapableOfBeingDrawnUpon window;
	this(CapableOfBeingDrawnUpon window, NativeWindowHandle handle) {
		this.window = window;
		if(window.closed)
			return; // null painter is now allowed so no need to throw anymore, this likely happens at the end of a program anyway
		//currentClipRectangle = arsd.color.Rectangle(0, 0, window.width, window.height);
		currentClipRectangle = arsd.color.Rectangle(short.min, short.min, short.max, short.max);
		if(window.activeScreenPainter !is null) {
			impl = window.activeScreenPainter;
			if(impl.referenceCount == 0) {
				impl.window = window;
				impl.create(handle);
			}
			impl.referenceCount++;
		//	writeln("refcount ++ ", impl.referenceCount);
		} else {
			impl = new ScreenPainterImplementation;
			impl.window = window;
			impl.create(handle);
			impl.referenceCount = 1;
			window.activeScreenPainter = impl;
			//import std.stdio; writeln("constructed");
		}

		copyActiveOriginals();
	}

	private Pen originalPen;
	private Color originalFillColor;
	private arsd.color.Rectangle originalClipRectangle;
	void copyActiveOriginals() {
		if(impl is null) return;
		originalPen = impl._activePen;
		originalFillColor = impl._fillColor;
		originalClipRectangle = impl._clipRectangle;
	}

	~this() {
		if(impl is null) return;
		impl.referenceCount--;
		//writeln("refcount -- ", impl.referenceCount);
		if(impl.referenceCount == 0) {
			//import std.stdio; writeln("destructed");
			impl.dispose();
			*window.activeScreenPainter = ScreenPainterImplementation.init;
			//import std.stdio; writeln("paint finished");
		} else {
			// there is still an active reference, reset stuff so the
			// next user doesn't get weirdness via the reference
			this.rasterOp = RasterOp.normal;
			pen = originalPen;
			fillColor = originalFillColor;
			impl.setClipRectangle(originalClipRectangle.left, originalClipRectangle.top, originalClipRectangle.width, originalClipRectangle.height);
		}
	}

	this(this) {
		if(impl is null) return;
		impl.referenceCount++;
		//writeln("refcount ++ ", impl.referenceCount);

		copyActiveOriginals();
	}

	private int _originX;
	private int _originY;
	@property int originX() { return _originX; }
	@property int originY() { return _originY; }
	@property int originX(int a) {
		_originX = a;
		return _originX;
	}
	@property int originY(int a) {
		_originY = a;
		return _originY;
	}
	arsd.color.Rectangle currentClipRectangle; // set BEFORE doing any transformations
	private void transform(ref Point p) {
		if(impl is null) return;
		p.x += _originX;
		p.y += _originY;
	}

	// this needs to be checked BEFORE the originX/Y transformation
	private bool isClipped(Point p) {
		return !currentClipRectangle.contains(p);
	}
	private bool isClipped(Point p, int width, int height) {
		return !currentClipRectangle.overlaps(arsd.color.Rectangle(p, Size(width + 1, height + 1)));
	}
	private bool isClipped(Point p, Size s) {
		return !currentClipRectangle.overlaps(arsd.color.Rectangle(p, Size(s.width + 1, s.height + 1)));
	}
	private bool isClipped(Point p, Point p2) {
		// need to ensure the end points are actually included inside, so the +1 does that
		return !currentClipRectangle.overlaps(arsd.color.Rectangle(p, p2 + Point(1, 1)));
	}


	/++
		Sets the clipping region for drawing. If width == 0 && height == 0, disabled clipping.

		Returns:
			The old clip rectangle.

		History:
			Return value was `void` prior to May 10, 2021.

	+/
	arsd.color.Rectangle setClipRectangle(Point pt, int width, int height) {
		if(impl is null) return currentClipRectangle;
		if(pt == currentClipRectangle.upperLeft && width == currentClipRectangle.width && height == currentClipRectangle.height)
			return currentClipRectangle; // no need to do anything
		auto old = currentClipRectangle;
		currentClipRectangle = arsd.color.Rectangle(pt, Size(width, height));
		transform(pt);

		impl.setClipRectangle(pt.x, pt.y, width, height);

		return old;
	}

	/// ditto
	arsd.color.Rectangle setClipRectangle(arsd.color.Rectangle rect) {
		if(impl is null) return currentClipRectangle;
		return setClipRectangle(rect.upperLeft, rect.width, rect.height);
	}

	///
	void setFont(OperatingSystemFont font) {
		if(impl is null) return;
		impl.setFont(font);
	}

	///
	int fontHeight() {
		if(impl is null) return 0;
		return impl.fontHeight();
	}

	private Pen activePen;

	///
	@property void pen(Pen p) {
		if(impl is null) return;
		activePen = p;
		impl.pen(p);
	}

	///
	@scriptable
	@property void outlineColor(Color c) {
		if(impl is null) return;
		if(activePen.color == c)
			return;
		activePen.color = c;
		impl.pen(activePen);
	}

	///
	@scriptable
	@property void fillColor(Color c) {
		if(impl is null) return;
		impl.fillColor(c);
	}

	///
	@property void rasterOp(RasterOp op) {
		if(impl is null) return;
		impl.rasterOp(op);
	}


	void updateDisplay() {
		// FIXME this should do what the dtor does
	}

	/// Scrolls the contents in the bounding rectangle by dx, dy. Positive dx means scroll left (make space available at the right), positive dy means scroll up (make space available at the bottom)
	void scrollArea(Point upperLeft, int width, int height, int dx, int dy) {
		if(impl is null) return;
		if(isClipped(upperLeft, width, height)) return;
		transform(upperLeft);
		version(Windows) {
			// http://msdn.microsoft.com/en-us/library/windows/desktop/bb787589%28v=vs.85%29.aspx
			RECT scroll = RECT(upperLeft.x, upperLeft.y, upperLeft.x + width, upperLeft.y + height);
			RECT clip = scroll;
			RECT uncovered;
			HRGN hrgn;
			if(!ScrollDC(impl.hdc, -dx, -dy, &scroll, &clip, hrgn, &uncovered))
				throw new Exception("ScrollDC");

		} else version(X11) {
			// FIXME: clip stuff outside this rectangle
			XCopyArea(impl.display, impl.d, impl.d, impl.gc, upperLeft.x, upperLeft.y, width, height, upperLeft.x - dx, upperLeft.y - dy);
		} else version(OSXCocoa) {
			throw new NotYetImplementedException();
		} else static assert(0);
	}

	///
	void clear(Color color = Color.white()) {
		if(impl is null) return;
		fillColor = color;
		outlineColor = color;
		drawRectangle(Point(0, 0), window.width, window.height);
	}

	/++
		Draws a pixmap (represented by the [Sprite] class) on the drawable.

		Params:
			upperLeft = point on the window where the upper left corner of the image will be drawn
			imageUpperLeft = point on the image to start the slice to draw
			sliceSize = size of the slice of the image to draw on the window. If width or height is 0, it uses the entire width or height of the image.
		History:
			The `imageUpperLeft` and `sliceSize` parameters were added on March 11, 2021 (dub v9.3.0)
	+/
	version(OSXCocoa) {} else // NotYetImplementedException
	void drawPixmap(Sprite s, Point upperLeft, Point imageUpperLeft = Point(0, 0), Size sliceSize = Size(0, 0)) {
		if(impl is null) return;
		if(isClipped(upperLeft, s.width, s.height)) return;
		transform(upperLeft);
		impl.drawPixmap(s, upperLeft.x, upperLeft.y, imageUpperLeft.x, imageUpperLeft.y, sliceSize.width, sliceSize.height);
	}

	///
	void drawImage(Point upperLeft, Image i, Point upperLeftOfImage = Point(0, 0), int w = 0, int h = 0) {
		if(impl is null) return;
		//if(isClipped(upperLeft, w, h)) return; // FIXME
		transform(upperLeft);
		if(w == 0 || w > i.width)
			w = i.width;
		if(h == 0 || h > i.height)
			h = i.height;
		if(upperLeftOfImage.x < 0)
			upperLeftOfImage.x = 0;
		if(upperLeftOfImage.y < 0)
			upperLeftOfImage.y = 0;

		impl.drawImage(upperLeft.x, upperLeft.y, i, upperLeftOfImage.x, upperLeftOfImage.y, w, h);
	}

	///
	Size textSize(in char[] text) {
		if(impl is null) return Size(0, 0);
		return impl.textSize(text);
	}

	/++
		Draws a string in the window with the set font (see [setFont] to change it).

		Params:
			upperLeft = the upper left point of the bounding box of the text
			text = the string to draw
			lowerRight = the lower right point of the bounding box of the text. If 0, 0, there is no lower right bound.
			alignment = A [arsd.docs.general_concepts#bitflags|combination] of [TextAlignment] flags
	+/
	@scriptable
	void drawText(Point upperLeft, in char[] text, Point lowerRight = Point(0, 0), uint alignment = 0) {
		if(impl is null) return;
		if(lowerRight.x != 0 || lowerRight.y != 0) {
			if(isClipped(upperLeft, lowerRight)) return;
			transform(lowerRight);
		} else {
			if(isClipped(upperLeft, textSize(text))) return;
		}
		transform(upperLeft);
		impl.drawText(upperLeft.x, upperLeft.y, lowerRight.x, lowerRight.y, text, alignment);
	}

	/++
		Draws text using a custom font.

		This is still MAJOR work in progress.

		Creating a [DrawableFont] can be tricky and require additional dependencies.
	+/
	void drawText(DrawableFont font, Point upperLeft, in char[] text) {
		if(impl is null) return;
		if(isClipped(upperLeft, Point(int.max, int.max))) return;
		transform(upperLeft);
		font.drawString(this, upperLeft, text);
	}

	version(Windows)
	void drawText(Point upperLeft, scope const(wchar)[] text) {
		if(impl is null) return;
		if(isClipped(upperLeft, Point(int.max, int.max))) return;
		transform(upperLeft);

		if(text.length && text[$-1] == '\n')
			text = text[0 .. $-1]; // tailing newlines are weird on windows...

		TextOutW(impl.hdc, upperLeft.x, upperLeft.y, text.ptr, cast(int) text.length);
	}

	static struct TextDrawingContext {
		Point boundingBoxUpperLeft;
		Point boundingBoxLowerRight;

		Point currentLocation;

		Point lastDrewUpperLeft;
		Point lastDrewLowerRight;

		// how do i do right aligned rich text?
		// i kinda want to do a pre-made drawing then right align
		// draw the whole block.
		//
		// That's exactly the diff: inline vs block stuff.

		// I need to get coordinates of an inline section out too,
		// not just a bounding box, but a series of bounding boxes
		// should be ok. Consider what's needed to detect a click
		// on a link in the middle of a paragraph breaking a line.
		//
		// Generally, we should be able to get the rectangles of
		// any portion we draw.
		//
		// It also needs to tell what text is left if it overflows
		// out of the box, so we can do stuff like float images around
		// it. It should not attempt to draw a letter that would be
		// clipped.
		//
		// I might also turn off word wrap stuff.
	}

	void drawText(TextDrawingContext context, in char[] text, uint alignment = 0) {
		if(impl is null) return;
		// FIXME
	}

	/// Drawing an individual pixel is slow. Avoid it if possible.
	void drawPixel(Point where) {
		if(impl is null) return;
		if(isClipped(where)) return;
		transform(where);
		impl.drawPixel(where.x, where.y);
	}


	/// Draws a pen using the current pen / outlineColor
	@scriptable
	void drawLine(Point starting, Point ending) {
		if(impl is null) return;
		if(isClipped(starting, ending)) return;
		transform(starting);
		transform(ending);
		impl.drawLine(starting.x, starting.y, ending.x, ending.y);
	}

	/// Draws a rectangle using the current pen/outline color for the border and brush/fill color for the insides
	/// The outer lines, inclusive of x = 0, y = 0, x = width - 1, and y = height - 1 are drawn with the outlineColor
	/// The rest of the pixels are drawn with the fillColor. If fillColor is transparent, those pixels are not drawn.
	@scriptable
	void drawRectangle(Point upperLeft, int width, int height) {
		if(impl is null) return;
		if(isClipped(upperLeft, width, height)) return;
		transform(upperLeft);
		impl.drawRectangle(upperLeft.x, upperLeft.y, width, height);
	}

	/// ditto
	void drawRectangle(Point upperLeft, Size size) {
		if(impl is null) return;
		if(isClipped(upperLeft, size.width, size.height)) return;
		transform(upperLeft);
		impl.drawRectangle(upperLeft.x, upperLeft.y, size.width, size.height);
	}

	/// ditto
	void drawRectangle(Point upperLeft, Point lowerRightInclusive) {
		if(impl is null) return;
		if(isClipped(upperLeft, lowerRightInclusive + Point(1, 1))) return;
		transform(upperLeft);
		transform(lowerRightInclusive);
		impl.drawRectangle(upperLeft.x, upperLeft.y,
			lowerRightInclusive.x - upperLeft.x + 1, lowerRightInclusive.y - upperLeft.y + 1);
	}

	// overload added on May 12, 2021
	/// ditto
	void drawRectangle(Rectangle rect) {
		drawRectangle(rect.upperLeft, rect.size);
	}

	/// Arguments are the points of the bounding rectangle
	void drawEllipse(Point upperLeft, Point lowerRight) {
		if(impl is null) return;
		if(isClipped(upperLeft, lowerRight)) return;
		transform(upperLeft);
		transform(lowerRight);
		impl.drawEllipse(upperLeft.x, upperLeft.y, lowerRight.x, lowerRight.y);
	}

	/++
		start and finish are units of degrees * 64
	+/
	void drawArc(Point upperLeft, int width, int height, int start, int finish) {
		if(impl is null) return;
		// FIXME: not actually implemented
		if(isClipped(upperLeft, width, height)) return;
		transform(upperLeft);
		impl.drawArc(upperLeft.x, upperLeft.y, width, height, start, finish);
	}

	//this function draws a circle with the drawEllipse() function above, it requires the upper left point and the radius
	void drawCircle(Point upperLeft, int diameter) {
		drawEllipse(upperLeft, Point(upperLeft.x + diameter, upperLeft.y + diameter));
	}

	/// .
	void drawPolygon(Point[] vertexes) {
		if(impl is null) return;
		assert(vertexes.length);
		int minX = int.max, minY = int.max, maxX = int.min, maxY = int.min;
		foreach(ref vertex; vertexes) {
			if(vertex.x < minX)
				minX = vertex.x;
			if(vertex.y < minY)
				minY = vertex.y;
			if(vertex.x > maxX)
				maxX = vertex.x;
			if(vertex.y > maxY)
				maxY = vertex.y;
			transform(vertex);
		}
		if(isClipped(Point(minX, maxY), Point(maxX + 1, maxY + 1))) return;
		impl.drawPolygon(vertexes);
	}

	/// ditto
	void drawPolygon(Point[] vertexes...) {
		if(impl is null) return;
		drawPolygon(vertexes);
	}


	// and do a draw/fill in a single call maybe. Windows can do it... but X can't, though it could do two calls.

	//mixin NativeScreenPainterImplementation!() impl;


	// HACK: if I mixin the impl directly, it won't let me override the copy
	// constructor! The linker complains about there being multiple definitions.
	// I'll make the best of it and reference count it though.
	ScreenPainterImplementation* impl;
}

	// HACK: I need a pointer to the implementation so it's separate
	struct ScreenPainterImplementation {
		CapableOfBeingDrawnUpon window;
		int referenceCount;
		mixin NativeScreenPainterImplementation!();
	}

// FIXME: i haven't actually tested the sprite class on MS Windows

/**
	Sprites are optimized for fast drawing on the screen, but slow for direct pixel
	access. They are best for drawing a relatively unchanging image repeatedly on the screen.


	On X11, this corresponds to an `XPixmap`. On Windows, it still uses a bitmap,
	though I'm not sure that's ideal and the implementation might change.

	You create one by giving a window and an image. It optimizes for that window,
	and copies the image into it to use as the initial picture. Creating a sprite
	can be quite slow (especially over a network connection) so you should do it
	as little as possible and just hold on to your sprite handles after making them.
	simpledisplay does try to do its best though, using the XSHM extension if available,
	but you should still write your code as if it will always be slow.

	Then you can use `sprite.drawAt(painter, point);` to draw it, which should be
	a fast operation - much faster than drawing the Image itself every time.

	`Sprite` represents a scarce resource which should be freed when you
	are done with it. Use the `dispose` method to do this. Do not use a `Sprite`
	after it has been disposed. If you are unsure about this, don't take chances,
	just let the garbage collector do it for you. But ideally, you can manage its
	lifetime more efficiently.

	$(NOTE `Sprite`, like the rest of simpledisplay's `ScreenPainter`, does not
	support alpha blending in its drawing at this time. That might change in the
	future, but if you need alpha blending right now, use OpenGL instead. See
	`gamehelpers.d` for a similar class to `Sprite` that uses OpenGL: `OpenGlTexture`.)

	Update: on April 23, 2021, I finally added alpha blending support. You must opt
	in by setting the enableAlpha = true in the constructor.
*/
version(OSXCocoa) {} else // NotYetImplementedException
class Sprite : CapableOfBeingDrawnUpon {

	///
	ScreenPainter draw() {
		return ScreenPainter(this, handle);
	}

	/++
		Copies the sprite's current state into a [TrueColorImage].

		Be warned: this can be a very slow operation

		History:
			Actually implemented on March 14, 2021
	+/
	TrueColorImage takeScreenshot() {
		return trueColorImageFromNativeHandle(handle, width, height);
	}

	void delegate() paintingFinishedDg() { return null; }
	bool closed() { return false; }
	ScreenPainterImplementation* activeScreenPainter_;
	protected ScreenPainterImplementation* activeScreenPainter() { return activeScreenPainter_; }
	protected void activeScreenPainter(ScreenPainterImplementation* i) { activeScreenPainter_ = i; }

	version(Windows)
		private ubyte* rawData;
	// FIXME: sprites are lost when disconnecting from X! We need some way to invalidate them...
	// ditto on the XPicture stuff

	version(X11) {
		private static XRenderPictFormat* RGB24;
		private static XRenderPictFormat* ARGB32;

		private Picture xrenderPicture;
	}

	this(SimpleWindow win, int width, int height, bool enableAlpha = false) {
		this._width = width;
		this._height = height;
		this.enableAlpha = enableAlpha;

		version(X11) {
			auto display = XDisplayConnection.get();

			if(enableAlpha) {
				if(!XRenderLibrary.loadAttempted) {
					XRenderLibrary.loadDynamicLibrary();
				}

				if(!XRenderLibrary.loadSuccessful)
					throw new Exception("XRender library load failure");
			}

			handle = XCreatePixmap(display, cast(Drawable) win.window, width, height, enableAlpha ? 32 : DefaultDepthOfDisplay(display));

			if(enableAlpha) {
				if(RGB24 is null)
					RGB24 = XRenderFindStandardFormat(display, PictStandardRGB24);
				if(ARGB32 is null)
					ARGB32 = XRenderFindStandardFormat(display, PictStandardARGB32);

				XRenderPictureAttributes attrs;
				xrenderPicture = XRenderCreatePicture(display, handle, ARGB32, 0, &attrs);
			}
		} else version(Windows) {
			version(CRuntime_DigitalMars) {
				//if(enableAlpha)
					//throw new Exception("Alpha support not available, try recompiling with -m32mscoff");
			}

			BITMAPINFO infoheader;
			infoheader.bmiHeader.biSize = infoheader.bmiHeader.sizeof;
			infoheader.bmiHeader.biWidth = width;
			infoheader.bmiHeader.biHeight = height;
			infoheader.bmiHeader.biPlanes = 1;
			infoheader.bmiHeader.biBitCount = enableAlpha ? 32 : 24;
			infoheader.bmiHeader.biCompression = BI_RGB;

			// FIXME: this should prolly be a device dependent bitmap...
			handle = CreateDIBSection(
				null,
				&infoheader,
				DIB_RGB_COLORS,
				cast(void**) &rawData,
				null,
				0);

			if(handle is null)
				throw new Exception("couldn't create pixmap");
		}
	}

	/// Makes a sprite based on the image with the initial contents from the Image
	this(SimpleWindow win, Image i) {
		this(win, i.width, i.height, i.enableAlpha);

		version(X11) {
			auto display = XDisplayConnection.get();
			auto gc = XCreateGC(display, this.handle, 0, null);
			scope(exit) XFreeGC(display, gc);
			if(i.usingXshm)
				XShmPutImage(display, cast(Drawable) handle, gc, i.handle, 0, 0, 0, 0, i.width, i.height, false);
			else
				XPutImage(display, cast(Drawable) handle, gc, i.handle, 0, 0, 0, 0, i.width, i.height);
		} else version(Windows) {
			auto itemsPerLine = enableAlpha ? (4 * width) : (((cast(int) width * 3 + 3) / 4) * 4);
			auto arrLength = itemsPerLine * height;
			rawData[0..arrLength] = i.rawData[0..arrLength];
		} else version(OSXCocoa) {
			// FIXME: I have no idea if this is even any good
			ubyte* rawData;

			auto colorSpace = CGColorSpaceCreateDeviceRGB();
			context = CGBitmapContextCreate(null, width, height, 8, 4*width,
				colorSpace,
				kCGImageAlphaPremultipliedLast
				|kCGBitmapByteOrder32Big);
			CGColorSpaceRelease(colorSpace);
			rawData = CGBitmapContextGetData(context);

			auto rdl = (width * height * 4);
			rawData[0 .. rdl] = i.rawData[0 .. rdl];
		} else static assert(0);
	}

	/++
		Draws the image on the specified painter at the specified point. The point is the upper-left point where the image will be drawn.

		Params:
			where = point on the window where the upper left corner of the image will be drawn
			imageUpperLeft = point on the image to start the slice to draw
			sliceSize = size of the slice of the image to draw on the window. If width or height is 0, it uses the entire width or height of the image.
		History:
			The `imageUpperLeft` and `sliceSize` parameters were added on March 11, 2021 (dub v9.3.0)
	+/
	void drawAt(ScreenPainter painter, Point where, Point imageUpperLeft = Point(0, 0), Size sliceSize = Size(0, 0)) {
		painter.drawPixmap(this, where, imageUpperLeft, sliceSize);
	}

	/// Call this when you're ready to get rid of it
	void dispose() {
		version(X11) {
			if(xrenderPicture) {
				XRenderFreePicture(XDisplayConnection.get, xrenderPicture);
				xrenderPicture = None;
			}
			if(handle)
				XFreePixmap(XDisplayConnection.get(), handle);
			handle = None;
		} else version(Windows) {
			if(handle)
				DeleteObject(handle);
			handle = null;
		} else version(OSXCocoa) {
			if(context)
				CGContextRelease(context);
			context = null;
		} else static assert(0);

	}

	~this() {
		dispose();
	}

	///
	final @property int width() { return _width; }

	///
	final @property int height() { return _height; }

	///
	static Sprite fromMemoryImage(SimpleWindow win, MemoryImage img, bool enableAlpha = false) {
		return new Sprite(win, Image.fromMemoryImage(img, enableAlpha));
	}

	auto nativeHandle() {
		return handle;
	}

	private:

	int _width;
	int _height;
	bool enableAlpha;
	version(X11)
		Pixmap handle;
	else version(Windows)
		HBITMAP handle;
	else version(OSXCocoa)
		CGContextRef context;
	else static assert(0);
}

/++
	NOT IMPLEMENTED

	A display-stored image optimized for relatively quick drawing, like
	[Sprite], but this one supports alpha channel blending and does NOT
	support direct drawing upon it with a [ScreenPainter].

	You can think of it as an [arsd.game.OpenGlTexture] for usage with a
	plain [ScreenPainter]... sort of.

	On X11, it requires the Xrender extension and library. This is available
	almost everywhere though.

	History:
		Added November 14, 2020 but NOT ACTUALLY IMPLEMENTED
+/
version(none)
class AlphaSprite {
	/++
		Copies the given image into it.
	+/
	this(MemoryImage img) {

		if(!XRenderLibrary.loadAttempted) {
			XRenderLibrary.loadDynamicLibrary();

			// FIXME: this needs to be reconstructed when the X server changes
			repopulateX();
		}
		if(!XRenderLibrary.loadSuccessful)
			throw new Exception("XRender library load failure");

		// I probably need to put the alpha mask in a separate Picture
		// ugh
		// maybe the Sprite itself can have an alpha bitmask anyway


		auto display = XDisplayConnection.get();
		pixmap = XCreatePixmap(display, cast(Drawable) win.window, width, height, DefaultDepthOfDisplay(display));


		XRenderPictureAttributes attrs;

		handle = XRenderCreatePicture(
			XDisplayConnection.get,
			pixmap,
			RGBA,
			0,
			&attrs
		);

	}

	// maybe i'll use the create gradient functions too with static factories..

	void drawAt(ScreenPainter painter, Point where) {
		//painter.drawPixmap(this, where);

		XRenderPictureAttributes attrs;

		auto pic = XRenderCreatePicture(
			XDisplayConnection.get,
			painter.impl.d,
			RGB,
			0,
			&attrs
		);

		XRenderComposite(
			XDisplayConnection.get,
			3, // PictOpOver
			handle,
			None,
			pic,
			0, // src
			0,
			0, // mask
			0,
			10, // dest
			10,
			100, // width
			100
		);

		/+
		XRenderFreePicture(
			XDisplayConnection.get,
			pic
		);

		XRenderFreePicture(
			XDisplayConnection.get,
			fill
		);
		+/
		// on Windows you can stretch but Xrender still can't :(
	}

	static XRenderPictFormat* RGB;
	static XRenderPictFormat* RGBA;
	static void repopulateX() {
		auto display = XDisplayConnection.get;
		RGB  = XRenderFindStandardFormat(display, PictStandardRGB24);
		RGBA = XRenderFindStandardFormat(display, PictStandardARGB32);
	}

	XPixmap pixmap;
	Picture handle;
}

///
interface CapableOfBeingDrawnUpon {
	///
	ScreenPainter draw();
	///
	int width();
	///
	int height();
	protected ScreenPainterImplementation* activeScreenPainter();
	protected void activeScreenPainter(ScreenPainterImplementation*);
	bool closed();

	void delegate() paintingFinishedDg();

	/// Be warned: this can be a very slow operation
	TrueColorImage takeScreenshot();
}

/// Flushes any pending gui buffers. Necessary if you are using with_eventloop with X - flush after you create your windows but before you call [arsd.eventloop.loop].
void flushGui() {
	version(X11) {
		auto dpy = XDisplayConnection.get();
		XLockDisplay(dpy);
		scope(exit) XUnlockDisplay(dpy);
		XFlush(dpy);
	}
}

/++
	Runs the given code in the GUI thread when its event loop
	is available, blocking until it completes. This allows you
	to create and manipulate windows from another thread without
	invoking undefined behavior.

	If this is the gui thread, it runs the code immediately.

	If no gui thread exists yet, the current thread is assumed
	to be it. Attempting to create windows or run the event loop
	in any other thread will cause an assertion failure.


	$(TIP
		Did you know you can use UFCS on delegate literals?

		() {
			// code here
		}.runInGuiThread;
	)

	Returns:
		`true` if the function was called, `false` if it was not.
		The function may not be called because the gui thread had
		already terminated by the time you called this.

	History:
		Added April 10, 2020 (v7.2.0)

		Return value added and implementation tweaked to avoid locking
		at program termination on February 24, 2021 (v9.2.1).
+/
bool runInGuiThread(scope void delegate() dg) @trusted {
	claimGuiThread();

	if(thisIsGuiThread) {
		dg();
		return true;
	}

	if(guiThreadTerminating)
		return false;

	import core.sync.semaphore;
	static Semaphore sc;
	if(sc is null)
		sc = new Semaphore();

	static RunQueueMember* rqm;
	if(rqm is null)
		rqm = new RunQueueMember;
	rqm.dg = cast(typeof(rqm.dg)) dg;
	rqm.signal = sc;
	rqm.thrown = null;

	synchronized(runInGuiThreadLock) {
		runInGuiThreadQueue ~= rqm;
	}

	if(!SimpleWindow.eventWakeUp())
		throw new Error("runInGuiThread impossible; eventWakeUp failed");

	rqm.signal.wait();
	auto t = rqm.thrown;

	if(t)
		throw t;

	return true;
}

private void runPendingRunInGuiThreadDelegates() {
	more:
	RunQueueMember* next;
	synchronized(runInGuiThreadLock) {
		if(runInGuiThreadQueue.length) {
			next = runInGuiThreadQueue[0];
			runInGuiThreadQueue = runInGuiThreadQueue[1 .. $];
		} else {
			next = null;
		}
	}

	if(next) {
		try {
			next.dg();
			next.thrown = null;
		} catch(Throwable t) {
			next.thrown = t;
		}

		next.signal.notify();

		goto more;
	}
}

private void claimGuiThread() {
	import core.atomic;
	if(cas(&guiThreadExists, false, true))
		thisIsGuiThread = true;
}

private struct RunQueueMember {
	void delegate() dg;
	import core.sync.semaphore;
	Semaphore signal;
	Throwable thrown;
}

private __gshared RunQueueMember*[] runInGuiThreadQueue;
private __gshared Object runInGuiThreadLock = new Object; // intentional CTFE
private bool thisIsGuiThread = false;
private shared bool guiThreadExists = false;
private shared bool guiThreadTerminating = false;

private void guiThreadFinalize() {
	assert(thisIsGuiThread);

	guiThreadTerminating = true; // don't add any more from this point on
	runPendingRunInGuiThreadDelegates();
}

/+
interface IPromise {
	void reportProgress(int current, int max, string message);

	/+ // not formally in cuz of templates but still
	IPromise Then();
	IPromise Catch();
	IPromise Finally();
	+/
}

/+
	auto promise = async({ ... });
	promise.Then(whatever).
		Then(whateverelse).
		Catch((exception) { });


	A promise is run inside a fiber and it looks something like:

	try {
		auto res = whatever();
		auto res2 = whateverelse(res);
	} catch(Exception e) {
		{ }(e);
	}

	When a thing succeeds, it is passed as an arg to the next
+/
class Promise(T) : IPromise {
	auto Then() { return null; }
	auto Catch() { return null; }
	auto Finally() { return null; }

	// wait for it to resolve and return the value, or rethrow the error if that occurred.
	// cannot be called from the gui thread, but this is caught at runtime instead of compile time.
	T await();
}

interface Task {
}

interface Resolvable(T) : Task {
	void run();

	void resolve(T);

	Resolvable!T then(void delegate(T)); // returns a new promise
	Resolvable!T error(Throwable); // js catch
	Resolvable!T completed(); // js finally

}

/++
	Runs `work` in a helper thread and sends its return value back to the main gui
	thread as the argument to `uponCompletion`. If `work` throws, the exception is
	sent to the `uponThrown` if given, or if null, rethrown from the event loop to
	kill the program.

	You can call reportProgress(position, max, message) to update your parent window
	on your progress.

	I should also use `shared` methods. FIXME

	History:
		Added March 6, 2021 (dub version 9.3).
+/
void runInWorkerThread(T)(T delegate(Task) work, void delegate(T) uponCompletion) {
	uponCompletion(work(null));
}

+/

/// Used internal to dispatch events to various classes.
interface CapableOfHandlingNativeEvent {
	NativeEventHandler getNativeEventHandler();

	/*private*//*protected*/ __gshared CapableOfHandlingNativeEvent[NativeWindowHandle] nativeHandleMapping;

	version(X11) {
		// if this is impossible, you are allowed to just throw from it
		// Note: if you call it from another object, set a flag cuz the manger will call you again
		void recreateAfterDisconnect();
		// discard any *connection specific* state, but keep enough that you
		// can be recreated if possible. discardConnectionState() is always called immediately
		// before recreateAfterDisconnect(), so you can set a flag there to decide if
		// you need initialization order
		void discardConnectionState();
	}
}

version(X11)
/++
	State of keys on mouse events, especially motion.

	Do not trust the actual integer values in this, they are platform-specific. Always use the names.
+/
enum ModifierState : uint {
	shift = 1, ///
	capsLock = 2, ///
	ctrl = 4, ///
	alt = 8, /// Not always available on Windows
	windows = 64, /// ditto
	numLock = 16, ///

	leftButtonDown = 256, /// these aren't available on Windows for key events, so don't use them for that unless your app is X only.
	middleButtonDown = 512, /// ditto
	rightButtonDown = 1024, /// ditto
}
else version(Windows)
/// ditto
enum ModifierState : uint {
	shift = 4, ///
	ctrl = 8, ///

	// i'm not sure if the next two are available
	alt = 256, /// not always available on Windows
	windows = 512, /// ditto

	capsLock = 1024, ///
	numLock = 2048, ///

	leftButtonDown = 1, /// not available on key events
	middleButtonDown = 16, /// ditto
	rightButtonDown = 2, /// ditto

	backButtonDown = 0x20, /// not available on X
	forwardButtonDown = 0x40, /// ditto
}
else version(OSXCocoa)
// FIXME FIXME NotYetImplementedException
enum ModifierState : uint {
	shift = 1, ///
	capsLock = 2, ///
	ctrl = 4, ///
	alt = 8, /// Not always available on Windows
	windows = 64, /// ditto
	numLock = 16, ///

	leftButtonDown = 256, /// these aren't available on Windows for key events, so don't use them for that unless your app is X only.
	middleButtonDown = 512, /// ditto
	rightButtonDown = 1024, /// ditto
}

/// The names assume a right-handed mouse. These are bitwise combined on the events that use them.
enum MouseButton : int {
	none = 0,
	left = 1, ///
	right = 2, ///
	middle = 4, ///
	wheelUp = 8, ///
	wheelDown = 16, ///
	backButton = 32, /// often found on the thumb and used for back in browsers
	forwardButton = 64, /// often found on the thumb and used for forward in browsers
}

version(X11) {
	// FIXME: match ASCII whenever we can. Most of it is already there,
	// but there's a few exceptions and mismatches with Windows

	/// Do not trust the numeric values as they are platform-specific. Always use the symbolic name.
	enum Key {
		Escape = 0xff1b, ///
		F1 = 0xffbe, ///
		F2 = 0xffbf, ///
		F3 = 0xffc0, ///
		F4 = 0xffc1, ///
		F5 = 0xffc2, ///
		F6 = 0xffc3, ///
		F7 = 0xffc4, ///
		F8 = 0xffc5, ///
		F9 = 0xffc6, ///
		F10 = 0xffc7, ///
		F11 = 0xffc8, ///
		F12 = 0xffc9, ///
		PrintScreen = 0xff61, ///
		ScrollLock = 0xff14, ///
		Pause = 0xff13, ///
		Grave = 0x60, /// The $(BACKTICK) ~ key
		// number keys across the top of the keyboard
		N1 = 0x31, /// Number key atop the keyboard
		N2 = 0x32, ///
		N3 = 0x33, ///
		N4 = 0x34, ///
		N5 = 0x35, ///
		N6 = 0x36, ///
		N7 = 0x37, ///
		N8 = 0x38, ///
		N9 = 0x39, ///
		N0 = 0x30, ///
		Dash = 0x2d, ///
		Equals = 0x3d, ///
		Backslash = 0x5c, /// The \ | key
		Backspace = 0xff08, ///
		Insert = 0xff63, ///
		Home = 0xff50, ///
		PageUp = 0xff55, ///
		Delete = 0xffff, ///
		End = 0xff57, ///
		PageDown = 0xff56, ///
		Up = 0xff52, ///
		Down = 0xff54, ///
		Left = 0xff51, ///
		Right = 0xff53, ///

		Tab = 0xff09, ///
		Q = 0x71, ///
		W = 0x77, ///
		E = 0x65, ///
		R = 0x72, ///
		T = 0x74, ///
		Y = 0x79, ///
		U = 0x75, ///
		I = 0x69, ///
		O = 0x6f, ///
		P = 0x70, ///
		LeftBracket = 0x5b, /// the [ { key
		RightBracket = 0x5d, /// the ] } key
		CapsLock = 0xffe5, ///
		A = 0x61, ///
		S = 0x73, ///
		D = 0x64, ///
		F = 0x66, ///
		G = 0x67, ///
		H = 0x68, ///
		J = 0x6a, ///
		K = 0x6b, ///
		L = 0x6c, ///
		Semicolon = 0x3b, ///
		Apostrophe = 0x27, ///
		Enter = 0xff0d, ///
		Shift = 0xffe1, ///
		Z = 0x7a, ///
		X = 0x78, ///
		C = 0x63, ///
		V = 0x76, ///
		B = 0x62, ///
		N = 0x6e, ///
		M = 0x6d, ///
		Comma = 0x2c, ///
		Period = 0x2e, ///
		Slash = 0x2f, /// the / ? key
		Shift_r = 0xffe2, /// Note: this isn't sent on all computers, sometimes it just sends Shift, so don't rely on it. If it is supported though, it is the right Shift key, as opposed to the left Shift key
		Ctrl = 0xffe3, ///
		Windows = 0xffeb, ///
		Alt = 0xffe9, ///
		Space = 0x20, ///
		Alt_r = 0xffea, /// ditto of shift_r
		Windows_r = 0xffec, ///
		Menu = 0xff67, ///
		Ctrl_r = 0xffe4, ///

		NumLock = 0xff7f, ///
		Divide = 0xffaf, /// The / key on the number pad
		Multiply = 0xffaa, /// The * key on the number pad
		Minus = 0xffad, /// The - key on the number pad
		Plus = 0xffab, /// The + key on the number pad
		PadEnter = 0xff8d, /// Numberpad enter key
		Pad1 = 0xff9c, /// Numberpad keys
		Pad2 = 0xff99, ///
		Pad3 = 0xff9b, ///
		Pad4 = 0xff96, ///
		Pad5 = 0xff9d, ///
		Pad6 = 0xff98, ///
		Pad7 = 0xff95, ///
		Pad8 = 0xff97, ///
		Pad9 = 0xff9a, ///
		Pad0 = 0xff9e, ///
		PadDot = 0xff9f, ///
	}
} else version(Windows) {
	// the character here is for en-us layouts and for illustration only
	// if you actually want to get characters, wait for character events
	// (the argument to your event handler is simply a dchar)
	// those will be converted by the OS for the right locale.

	enum Key {
		Escape = 0x1b,
		F1 = 0x70,
		F2 = 0x71,
		F3 = 0x72,
		F4 = 0x73,
		F5 = 0x74,
		F6 = 0x75,
		F7 = 0x76,
		F8 = 0x77,
		F9 = 0x78,
		F10 = 0x79,
		F11 = 0x7a,
		F12 = 0x7b,
		PrintScreen = 0x2c,
		ScrollLock = 0x91,
		Pause = 0x13,
		Grave = 0xc0,
		// number keys across the top of the keyboard
		N1 = 0x31,
		N2 = 0x32,
		N3 = 0x33,
		N4 = 0x34,
		N5 = 0x35,
		N6 = 0x36,
		N7 = 0x37,
		N8 = 0x38,
		N9 = 0x39,
		N0 = 0x30,
		Dash = 0xbd,
		Equals = 0xbb,
		Backslash = 0xdc,
		Backspace = 0x08,
		Insert = 0x2d,
		Home = 0x24,
		PageUp = 0x21,
		Delete = 0x2e,
		End = 0x23,
		PageDown = 0x22,
		Up = 0x26,
		Down = 0x28,
		Left = 0x25,
		Right = 0x27,

		Tab = 0x09,
		Q = 0x51,
		W = 0x57,
		E = 0x45,
		R = 0x52,
		T = 0x54,
		Y = 0x59,
		U = 0x55,
		I = 0x49,
		O = 0x4f,
		P = 0x50,
		LeftBracket = 0xdb,
		RightBracket = 0xdd,
		CapsLock = 0x14,
		A = 0x41,
		S = 0x53,
		D = 0x44,
		F = 0x46,
		G = 0x47,
		H = 0x48,
		J = 0x4a,
		K = 0x4b,
		L = 0x4c,
		Semicolon = 0xba,
		Apostrophe = 0xde,
		Enter = 0x0d,
		Shift = 0x10,
		Z = 0x5a,
		X = 0x58,
		C = 0x43,
		V = 0x56,
		B = 0x42,
		N = 0x4e,
		M = 0x4d,
		Comma = 0xbc,
		Period = 0xbe,
		Slash = 0xbf,
		Shift_r = 0xa1, // FIXME Note: this isn't sent on all computers, sometimes it just sends Shift, so don't rely on it
		Ctrl = 0x11,
		Windows = 0x5b,
		Alt = -5, // FIXME
		Space = 0x20,
		Alt_r = 0xffea, // ditto of shift_r
		Windows_r = 0x5c, // ditto of shift_r
		Menu = 0x5d,
		Ctrl_r = 0xa3, // ditto of shift_r

		NumLock = 0x90,
		Divide = 0x6f,
		Multiply = 0x6a,
		Minus = 0x6d,
		Plus = 0x6b,
		PadEnter = -8, // FIXME
		Pad1 = 0x61,
		Pad2 = 0x62,
		Pad3 = 0x63,
		Pad4 = 0x64,
		Pad5 = 0x65,
		Pad6 = 0x66,
		Pad7 = 0x67,
		Pad8 = 0x68,
		Pad9 = 0x69,
		Pad0 = 0x60,
		PadDot = 0x6e,
	}

	// I'm keeping this around for reference purposes
	// ideally all these buttons will be listed for all platforms,
	// but now now I'm just focusing on my US keyboard
	version(none)
	enum Key {
		LBUTTON = 0x01,
		RBUTTON = 0x02,
		CANCEL = 0x03,
		MBUTTON = 0x04,
		//static if (_WIN32_WINNT > =  0x500) {
		XBUTTON1 = 0x05,
		XBUTTON2 = 0x06,
		//}
		BACK = 0x08,
		TAB = 0x09,
		CLEAR = 0x0C,
		RETURN = 0x0D,
		SHIFT = 0x10,
		CONTROL = 0x11,
		MENU = 0x12,
		PAUSE = 0x13,
		CAPITAL = 0x14,
		KANA = 0x15,
		HANGEUL = 0x15,
		HANGUL = 0x15,
		JUNJA = 0x17,
		FINAL = 0x18,
		HANJA = 0x19,
		KANJI = 0x19,
		ESCAPE = 0x1B,
		CONVERT = 0x1C,
		NONCONVERT = 0x1D,
		ACCEPT = 0x1E,
		MODECHANGE = 0x1F,
		SPACE = 0x20,
		PRIOR = 0x21,
		NEXT = 0x22,
		END = 0x23,
		HOME = 0x24,
		LEFT = 0x25,
		UP = 0x26,
		RIGHT = 0x27,
		DOWN = 0x28,
		SELECT = 0x29,
		PRINT = 0x2A,
		EXECUTE = 0x2B,
		SNAPSHOT = 0x2C,
		INSERT = 0x2D,
		DELETE = 0x2E,
		HELP = 0x2F,
		LWIN = 0x5B,
		RWIN = 0x5C,
		APPS = 0x5D,
		SLEEP = 0x5F,
		NUMPAD0 = 0x60,
		NUMPAD1 = 0x61,
		NUMPAD2 = 0x62,
		NUMPAD3 = 0x63,
		NUMPAD4 = 0x64,
		NUMPAD5 = 0x65,
		NUMPAD6 = 0x66,
		NUMPAD7 = 0x67,
		NUMPAD8 = 0x68,
		NUMPAD9 = 0x69,
		MULTIPLY = 0x6A,
		ADD = 0x6B,
		SEPARATOR = 0x6C,
		SUBTRACT = 0x6D,
		DECIMAL = 0x6E,
		DIVIDE = 0x6F,
		F1 = 0x70,
		F2 = 0x71,
		F3 = 0x72,
		F4 = 0x73,
		F5 = 0x74,
		F6 = 0x75,
		F7 = 0x76,
		F8 = 0x77,
		F9 = 0x78,
		F10 = 0x79,
		F11 = 0x7A,
		F12 = 0x7B,
		F13 = 0x7C,
		F14 = 0x7D,
		F15 = 0x7E,
		F16 = 0x7F,
		F17 = 0x80,
		F18 = 0x81,
		F19 = 0x82,
		F20 = 0x83,
		F21 = 0x84,
		F22 = 0x85,
		F23 = 0x86,
		F24 = 0x87,
		NUMLOCK = 0x90,
		SCROLL = 0x91,
		LSHIFT = 0xA0,
		RSHIFT = 0xA1,
		LCONTROL = 0xA2,
		RCONTROL = 0xA3,
		LMENU = 0xA4,
		RMENU = 0xA5,
		//static if (_WIN32_WINNT > =  0x500) {
		BROWSER_BACK = 0xA6,
		BROWSER_FORWARD = 0xA7,
		BROWSER_REFRESH = 0xA8,
		BROWSER_STOP = 0xA9,
		BROWSER_SEARCH = 0xAA,
		BROWSER_FAVORITES = 0xAB,
		BROWSER_HOME = 0xAC,
		VOLUME_MUTE = 0xAD,
		VOLUME_DOWN = 0xAE,
		VOLUME_UP = 0xAF,
		MEDIA_NEXT_TRACK = 0xB0,
		MEDIA_PREV_TRACK = 0xB1,
		MEDIA_STOP = 0xB2,
		MEDIA_PLAY_PAUSE = 0xB3,
		LAUNCH_MAIL = 0xB4,
		LAUNCH_MEDIA_SELECT = 0xB5,
		LAUNCH_APP1 = 0xB6,
		LAUNCH_APP2 = 0xB7,
		//}
		OEM_1 = 0xBA,
		//static if (_WIN32_WINNT > =  0x500) {
		OEM_PLUS = 0xBB,
		OEM_COMMA = 0xBC,
		OEM_MINUS = 0xBD,
		OEM_PERIOD = 0xBE,
		//}
		OEM_2 = 0xBF,
		OEM_3 = 0xC0,
		OEM_4 = 0xDB,
		OEM_5 = 0xDC,
		OEM_6 = 0xDD,
		OEM_7 = 0xDE,
		OEM_8 = 0xDF,
		//static if (_WIN32_WINNT > =  0x500) {
		OEM_102 = 0xE2,
		//}
		PROCESSKEY = 0xE5,
		//static if (_WIN32_WINNT > =  0x500) {
		PACKET = 0xE7,
		//}
		ATTN = 0xF6,
		CRSEL = 0xF7,
		EXSEL = 0xF8,
		EREOF = 0xF9,
		PLAY = 0xFA,
		ZOOM = 0xFB,
		NONAME = 0xFC,
		PA1 = 0xFD,
		OEM_CLEAR = 0xFE,
	}

} else version(OSXCocoa) {
	// FIXME
	enum Key {
		Escape = 0x1b,
		F1 = 0x70,
		F2 = 0x71,
		F3 = 0x72,
		F4 = 0x73,
		F5 = 0x74,
		F6 = 0x75,
		F7 = 0x76,
		F8 = 0x77,
		F9 = 0x78,
		F10 = 0x79,
		F11 = 0x7a,
		F12 = 0x7b,
		PrintScreen = 0x2c,
		ScrollLock = -2, // FIXME
		Pause = -3, // FIXME
		Grave = 0xc0,
		// number keys across the top of the keyboard
		N1 = 0x31,
		N2 = 0x32,
		N3 = 0x33,
		N4 = 0x34,
		N5 = 0x35,
		N6 = 0x36,
		N7 = 0x37,
		N8 = 0x38,
		N9 = 0x39,
		N0 = 0x30,
		Dash = 0xbd,
		Equals = 0xbb,
		Backslash = 0xdc,
		Backspace = 0x08,
		Insert = 0x2d,
		Home = 0x24,
		PageUp = 0x21,
		Delete = 0x2e,
		End = 0x23,
		PageDown = 0x22,
		Up = 0x26,
		Down = 0x28,
		Left = 0x25,
		Right = 0x27,

		Tab = 0x09,
		Q = 0x51,
		W = 0x57,
		E = 0x45,
		R = 0x52,
		T = 0x54,
		Y = 0x59,
		U = 0x55,
		I = 0x49,
		O = 0x4f,
		P = 0x50,
		LeftBracket = 0xdb,
		RightBracket = 0xdd,
		CapsLock = 0x14,
		A = 0x41,
		S = 0x53,
		D = 0x44,
		F = 0x46,
		G = 0x47,
		H = 0x48,
		J = 0x4a,
		K = 0x4b,
		L = 0x4c,
		Semicolon = 0xba,
		Apostrophe = 0xde,
		Enter = 0x0d,
		Shift = 0x10,
		Z = 0x5a,
		X = 0x58,
		C = 0x43,
		V = 0x56,
		B = 0x42,
		N = 0x4e,
		M = 0x4d,
		Comma = 0xbc,
		Period = 0xbe,
		Slash = 0xbf,
		Shift_r = -4, // FIXME Note: this isn't sent on all computers, sometimes it just sends Shift, so don't rely on it
		Ctrl = 0x11,
		Windows = 0x5b,
		Alt = -5, // FIXME
		Space = 0x20,
		Alt_r = 0xffea, // ditto of shift_r
		Windows_r = -6, // FIXME
		Menu = 0x5d,
		Ctrl_r = -7, // FIXME

		NumLock = 0x90,
		Divide = 0x6f,
		Multiply = 0x6a,
		Minus = 0x6d,
		Plus = 0x6b,
		PadEnter = -8, // FIXME
		// FIXME for the rest of these:
		Pad1 = 0xff9c,
		Pad2 = 0xff99,
		Pad3 = 0xff9b,
		Pad4 = 0xff96,
		Pad5 = 0xff9d,
		Pad6 = 0xff98,
		Pad7 = 0xff95,
		Pad8 = 0xff97,
		Pad9 = 0xff9a,
		Pad0 = 0xff9e,
		PadDot = 0xff9f,
	}

}

/* Additional utilities */


Color fromHsl(real h, real s, real l) {
	return arsd.color.fromHsl([h,s,l]);
}



/* ********** What follows is the system-specific implementations *********/
version(Windows) {


	// helpers for making HICONs from MemoryImages
	class WindowsIcon {
		struct Win32Icon(int colorCount) {
		align(1):
			uint biSize;
			int biWidth;
			int biHeight;
			ushort biPlanes;
			ushort biBitCount;
			uint biCompression;
			uint biSizeImage;
			int biXPelsPerMeter;
			int biYPelsPerMeter;
			uint biClrUsed;
			uint biClrImportant;
			RGBQUAD[colorCount] biColors;
			/* Pixels:
			Uint8 pixels[]
			*/
			/* Mask:
			Uint8 mask[]
			*/

			ubyte[4096] data;

			void fromMemoryImage(MemoryImage mi, out int icon_len, out int width, out int height) {
				width = mi.width;
				height = mi.height;

				auto indexedImage = cast(IndexedImage) mi;
				if(indexedImage is null)
					indexedImage = quantize(mi.getAsTrueColorImage());

				assert(width %8 == 0); // i don't want padding nor do i want the and mask to get fancy
				assert(height %4 == 0);

				int icon_plen = height*((width+3)&~3);
				int icon_mlen = height*((((width+7)/8)+3)&~3);
				icon_len = 40+icon_plen+icon_mlen + cast(int) RGBQUAD.sizeof * colorCount;

				biSize = 40;
				biWidth = width;
				biHeight = height*2;
				biPlanes = 1;
				biBitCount = 8;
				biSizeImage = icon_plen+icon_mlen;

				int offset = 0;
				int andOff = icon_plen * 8; // the and offset is in bits
				for(int y = height - 1; y >= 0; y--) {
					int off2 = y * width;
					foreach(x; 0 .. width) {
						const b = indexedImage.data[off2 + x];
						data[offset] = b;
						offset++;

						const andBit = andOff % 8;
						const andIdx = andOff / 8;
						assert(b < indexedImage.palette.length);
						// this is anded to the destination, since and 0 means erase,
						// we want that to  be opaque, and 1 for transparent
						auto transparent = (indexedImage.palette[b].a <= 127);
						data[andIdx] |= (transparent ? (1 << (7-andBit)) : 0);

						andOff++;
					}

					andOff += andOff % 32;
				}

				foreach(idx, entry; indexedImage.palette) {
					if(entry.a > 127) {
						biColors[idx].rgbBlue = entry.b;
						biColors[idx].rgbGreen = entry.g;
						biColors[idx].rgbRed = entry.r;
					} else {
						biColors[idx].rgbBlue = 255;
						biColors[idx].rgbGreen = 255;
						biColors[idx].rgbRed = 255;
					}
				}

				/*
				data[0..icon_plen] = getFlippedUnfilteredDatastream(png);
				data[icon_plen..icon_plen+icon_mlen] = getANDMask(png);
				//icon_win32.biColors[1] = Win32Icon.RGBQUAD(0,255,0,0);
				auto pngMap = fetchPaletteWin32(png);
				biColors[0..pngMap.length] = pngMap[];
				*/
			}
		}


		Win32Icon!(256) icon_win32;


		this(MemoryImage mi) {
			int icon_len, width, height;

			icon_win32.fromMemoryImage(mi, icon_len, width, height);

			/*
			PNG* png = readPnpngData);
			PNGHeader pngh = getHeader(png);
			void* icon_win32;
			if(pngh.depth == 4) {
				auto i = new Win32Icon!(16);
				i.fromPNG(png, pngh, icon_len, width, height);
				icon_win32 = i;
			}
			else if(pngh.depth == 8) {
				auto i = new Win32Icon!(256);
				i.fromPNG(png, pngh, icon_len, width, height);
				icon_win32 = i;
			} else assert(0);
			*/

			hIcon = CreateIconFromResourceEx(cast(ubyte*) &icon_win32, icon_len, true, 0x00030000, width, height, 0);

			if(hIcon is null) throw new Exception("CreateIconFromResourceEx");
		}

		~this() {
			DestroyIcon(hIcon);
		}

		HICON hIcon;
	}






	alias int delegate(HWND, UINT, WPARAM, LPARAM) NativeEventHandler;
	alias HWND NativeWindowHandle;

	extern(Windows)
	LRESULT WndProc(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) nothrow {
		try {
			if(SimpleWindow.handleNativeGlobalEvent !is null) {
				// it returns zero if the message is handled, so we won't do anything more there
				// do I like that though?
				auto ret = SimpleWindow.handleNativeGlobalEvent(hWnd, iMessage, wParam, lParam);
				if(ret == 0)
					return ret;
			}

			if(auto window = hWnd in CapableOfHandlingNativeEvent.nativeHandleMapping) {
				if(window.getNativeEventHandler !is null) {
					auto ret = window.getNativeEventHandler()(hWnd, iMessage, wParam, lParam);
					if(ret == 0)
						return ret;
				}
				if(auto w = cast(SimpleWindow) (*window))
					return w.windowProcedure(hWnd, iMessage, wParam, lParam);
				else
					return DefWindowProc(hWnd, iMessage, wParam, lParam);
			} else {
				return DefWindowProc(hWnd, iMessage, wParam, lParam);
			}
		} catch (Exception e) {
			try {
				sdpy_abort(e);
				return 0;
			} catch(Exception e) { assert(0); }
		}
	}

	void sdpy_abort(Throwable e) nothrow {
		try
			MessageBoxA(null, (e.toString() ~ "\0").ptr, "Exception caught in WndProc", 0);
		catch(Exception e)
			MessageBoxA(null, "Exception.toString threw too!", "Exception caught in WndProc", 0);
		ExitProcess(1);
	}

	mixin template NativeScreenPainterImplementation() {
		HDC hdc;
		HWND hwnd;
		//HDC windowHdc;
		HBITMAP oldBmp;

		void create(NativeWindowHandle window) {
			hwnd = window;

			if(auto sw = cast(SimpleWindow) this.window) {
				// drawing on a window, double buffer
				auto windowHdc = GetDC(hwnd);

				auto buffer = sw.impl.buffer;
				if(buffer is null) {
					hdc = windowHdc;
					windowDc = true;
				} else {
					hdc = CreateCompatibleDC(windowHdc);

					ReleaseDC(hwnd, windowHdc);

					oldBmp = SelectObject(hdc, buffer);
				}
			} else {
				// drawing on something else, draw directly
				hdc = CreateCompatibleDC(null);
				SelectObject(hdc, window);

			}

			// X doesn't draw a text background, so neither should we
			SetBkMode(hdc, TRANSPARENT);

			ensureDefaultFontLoaded();

			if(defaultGuiFont) {
				SelectObject(hdc, defaultGuiFont);
				// DeleteObject(defaultGuiFont);
			}
		}

		static HFONT defaultGuiFont;
		static void ensureDefaultFontLoaded() {
			static bool triedDefaultGuiFont = false;
			if(!triedDefaultGuiFont) {
				NONCLIENTMETRICS params;
				params.cbSize = params.sizeof;
				if(SystemParametersInfo(SPI_GETNONCLIENTMETRICS, params.sizeof, &params, 0)) {
					defaultGuiFont = CreateFontIndirect(&params.lfMessageFont);
				}
				triedDefaultGuiFont = true;
			}
		}

		void setFont(OperatingSystemFont font) {
			if(font && font.font) {
				if(SelectObject(hdc, font.font) == HGDI_ERROR) {
					// error... how to handle tho?
				}
			}
			else if(defaultGuiFont)
				SelectObject(hdc, defaultGuiFont);
		}

		arsd.color.Rectangle _clipRectangle;

		void setClipRectangle(int x, int y, int width, int height) {
			_clipRectangle = arsd.color.Rectangle(Point(x, y), Size(width, height));

			if(width == 0 || height == 0) {
				SelectClipRgn(hdc, null);
			} else {
				auto region = CreateRectRgn(x, y, x + width, y + height);
				SelectClipRgn(hdc, region);
				DeleteObject(region);
			}
		}


		// just because we can on Windows...
		//void create(Image image);

		void dispose() {
			// FIXME: this.window.width/height is probably wrong
			// BitBlt(windowHdc, 0, 0, this.window.width, this.window.height, hdc, 0, 0, SRCCOPY);
			// ReleaseDC(hwnd, windowHdc);

			// FIXME: it shouldn't invalidate the whole thing in all cases... it would be ideal to do this right
			if(cast(SimpleWindow) this.window)
			InvalidateRect(hwnd, cast(RECT*)null, false); // no need to erase bg as the whole thing gets bitblt'd ove

			if(originalPen !is null)
				SelectObject(hdc, originalPen);
			if(currentPen !is null)
				DeleteObject(currentPen);
			if(originalBrush !is null)
				SelectObject(hdc, originalBrush);
			if(currentBrush !is null)
				DeleteObject(currentBrush);

			SelectObject(hdc, oldBmp);

			if(windowDc)
				ReleaseDC(hwnd, hdc);
			else
				DeleteDC(hdc);

			if(window.paintingFinishedDg !is null)
				window.paintingFinishedDg()();
		}

		bool windowDc;
		HPEN originalPen;
		HPEN currentPen;

		Pen _activePen;

		@property void pen(Pen p) {
			_activePen = p;

			HPEN pen;
			if(p.color.a == 0) {
				pen = GetStockObject(NULL_PEN);
			} else {
				int style = PS_SOLID;
				final switch(p.style) {
					case Pen.Style.Solid:
						style = PS_SOLID;
					break;
					case Pen.Style.Dashed:
						style = PS_DASH;
					break;
					case Pen.Style.Dotted:
						style = PS_DOT;
					break;
				}
				pen = CreatePen(style, p.width, RGB(p.color.r, p.color.g, p.color.b));
			}
			auto orig = SelectObject(hdc, pen);
			if(originalPen is null)
				originalPen = orig;

			if(currentPen !is null)
				DeleteObject(currentPen);

			currentPen = pen;

			// the outline is like a foreground since it's done that way on X
			SetTextColor(hdc, RGB(p.color.r, p.color.g, p.color.b));

		}

		@property void rasterOp(RasterOp op) {
			int mode;
			final switch(op) {
				case RasterOp.normal:
					mode = R2_COPYPEN;
				break;
				case RasterOp.xor:
					mode = R2_XORPEN;
				break;
			}
			SetROP2(hdc, mode);
		}

		HBRUSH originalBrush;
		HBRUSH currentBrush;
		Color _fillColor = Color(1, 1, 1, 1); // what are the odds that they'd set this??
		@property void fillColor(Color c) {
			if(c == _fillColor)
				return;
			_fillColor = c;
			HBRUSH brush;
			if(c.a == 0) {
				brush = GetStockObject(HOLLOW_BRUSH);
			} else {
				brush = CreateSolidBrush(RGB(c.r, c.g, c.b));
			}
			auto orig = SelectObject(hdc, brush);
			if(originalBrush is null)
				originalBrush = orig;

			if(currentBrush !is null)
				DeleteObject(currentBrush);

			currentBrush = brush;

			// background color is NOT set because X doesn't draw text backgrounds
			//   SetBkColor(hdc, RGB(255, 255, 255));
		}

		void drawImage(int x, int y, Image i, int ix, int iy, int w, int h) {
			BITMAP bm;

			HDC hdcMem = CreateCompatibleDC(hdc);
			HBITMAP hbmOld = SelectObject(hdcMem, i.handle);

			GetObject(i.handle, bm.sizeof, &bm);

			// or should I AlphaBlend!??!?!
			BitBlt(hdc, x, y, w /* bm.bmWidth */, /*bm.bmHeight*/ h, hdcMem, ix, iy, SRCCOPY);

			SelectObject(hdcMem, hbmOld);
			DeleteDC(hdcMem);
		}

		void drawPixmap(Sprite s, int x, int y, int ix, int iy, int w, int h) {
			BITMAP bm;

			HDC hdcMem = CreateCompatibleDC(hdc);
			HBITMAP hbmOld = SelectObject(hdcMem, s.handle);

			GetObject(s.handle, bm.sizeof, &bm);

			version(CRuntime_DigitalMars) goto noalpha;

			// or should I AlphaBlend!??!?! note it is supposed to be premultiplied  http://www.fengyuan.com/article/alphablend.html
			if(s.enableAlpha) {
				auto dw = w ? w : bm.bmWidth;
				auto dh = h ? h : bm.bmHeight;
				BLENDFUNCTION bf;
				bf.BlendOp = AC_SRC_OVER;
				bf.SourceConstantAlpha = 255;
				bf.AlphaFormat = AC_SRC_ALPHA;
				AlphaBlend(hdc, x, y, dw, dh, hdcMem, ix, iy, dw, dh, bf);
			} else {
				noalpha:
				BitBlt(hdc, x, y, w ? w : bm.bmWidth, h ? h : bm.bmHeight, hdcMem, ix, iy, SRCCOPY);
			}

			SelectObject(hdcMem, hbmOld);
			DeleteDC(hdcMem);
		}

		Size textSize(scope const(char)[] text) {
			bool dummyX;
			if(text.length == 0) {
				text = " ";
				dummyX = true;
			}
			RECT rect;
			WCharzBuffer buffer = WCharzBuffer(text);
			DrawTextW(hdc, buffer.ptr, cast(int) buffer.length, &rect, DT_CALCRECT | DT_NOPREFIX);
			return Size(dummyX ? 0 : rect.right, rect.bottom);
		}

		void drawText(int x, int y, int x2, int y2, scope const(char)[] text, uint alignment) {
			if(text.length && text[$-1] == '\n')
				text = text[0 .. $-1]; // tailing newlines are weird on windows...
			if(text.length && text[$-1] == '\r')
				text = text[0 .. $-1];

			WCharzBuffer buffer = WCharzBuffer(text, WindowsStringConversionFlags.convertNewLines);
			if(x2 == 0 && y2 == 0) {
				TextOutW(hdc, x, y, buffer.ptr, cast(int) buffer.length);
			} else {
				RECT rect;
				rect.left = x;
				rect.top = y;
				rect.right = x2;
				rect.bottom = y2;

				uint mode = DT_LEFT;
				if(alignment & TextAlignment.Right)
					mode = DT_RIGHT;
				else if(alignment & TextAlignment.Center)
					mode = DT_CENTER;

				// FIXME: vcenter on windows only works with single line, but I want it to work in all cases
				if(alignment & TextAlignment.VerticalCenter)
					mode |= DT_VCENTER | DT_SINGLELINE;

				DrawTextW(hdc, buffer.ptr, cast(int) buffer.length, &rect, mode | DT_NOPREFIX);
			}

			/*
			uint mode;

			if(alignment & TextAlignment.Center)
				mode = TA_CENTER;

			SetTextAlign(hdc, mode);
			*/
		}

		int fontHeight() {
			TEXTMETRIC metric;
			if(GetTextMetricsW(hdc, &metric)) {
				return metric.tmHeight;
			}

			return 16; // idk just guessing here, maybe we should throw
		}

		void drawPixel(int x, int y) {
			SetPixel(hdc, x, y, RGB(_activePen.color.r, _activePen.color.g, _activePen.color.b));
		}

		// The basic shapes, outlined

		void drawLine(int x1, int y1, int x2, int y2) {
			MoveToEx(hdc, x1, y1, null);
			LineTo(hdc, x2, y2);
		}

		void drawRectangle(int x, int y, int width, int height) {
			// FIXME: with a wider pen this might not draw quite right. im not sure.
			gdi.Rectangle(hdc, x, y, x + width, y + height);
		}

		/// Arguments are the points of the bounding rectangle
		void drawEllipse(int x1, int y1, int x2, int y2) {
			Ellipse(hdc, x1, y1, x2, y2);
		}

		void drawArc(int x1, int y1, int width, int height, int start, int finish) {
			if((start % (360*64)) == (finish % (360*64)))
				drawEllipse(x1, y1, x1 + width, y1 + height);
			else {
				import core.stdc.math;
				float startAngle = cast(float) start / 64.0 / 180.0 * 3.14159265358979323;
				float endAngle = cast(float) finish / 64.0 / 180.0 * 3.14159265358979323;

				auto c1 = cast(int)(cos(startAngle) * width / 2 + x1 + width / 2);
				auto c2 = cast(int)(-sin(startAngle) * height / 2 + y1 + height / 2);
				auto c3 = cast(int)(cos(endAngle) * width / 2 + x1 + width / 2);
				auto c4 = cast(int)(-sin(endAngle) * height / 2 + y1 + height / 2);
				import std.stdio; writeln(c1, " ", c2, " ", c3, " ", c4);


				if(_activePen.color.a)
					Arc(hdc, x1, y1, x1 + width + 1, y1 + height + 1, c1, c2, c3, c4);
				if(_fillColor.a)
					Pie(hdc, x1, y1, x1 + width + 1, y1 + height + 1, c1, c2, c3, c4);
			}
		}

		void drawPolygon(Point[] vertexes) {
			POINT[] points;
			points.length = vertexes.length;

			foreach(i, p; vertexes) {
				points[i].x = p.x;
				points[i].y = p.y;
			}

			Polygon(hdc, points.ptr, cast(int) points.length);
		}
	}


	// Mix this into the SimpleWindow class
	mixin template NativeSimpleWindowImplementation() {
		int curHidden = 0; // counter
		__gshared static bool[string] knownWinClasses;
		static bool altPressed = false;

		HANDLE oldCursor;

		void hideCursor () {
			if(curHidden == 0)
				oldCursor = SetCursor(null);
			++curHidden;
		}

		void showCursor () {
			--curHidden;
			if(curHidden == 0) {
				SetCursor(currentCursor is null ? oldCursor : currentCursor); // show it immediately without waiting for mouse movement
			}
		}


		int minWidth = 0, minHeight = 0, maxWidth = int.max, maxHeight = int.max;

		void setMinSize (int minwidth, int minheight) {
			minWidth = minwidth;
			minHeight = minheight;
		}
		void setMaxSize (int maxwidth, int maxheight) {
			maxWidth = maxwidth;
			maxHeight = maxheight;
		}

		// FIXME i'm not sure that Windows has this functionality
		// though it is nonessential anyway.
		void setResizeGranularity (int granx, int grany) {}

		ScreenPainter getPainter() {
			return ScreenPainter(this, hwnd);
		}

		HBITMAP buffer;

		void setTitle(string title) {
			WCharzBuffer bfr = WCharzBuffer(title);
			SetWindowTextW(hwnd, bfr.ptr);
		}

		string getTitle() {
			auto len = GetWindowTextLengthW(hwnd);
			if (!len)
				return null;
			wchar[256] tmpBuffer;
			wchar[] buffer = (len <= tmpBuffer.length) ? tmpBuffer[] :  new wchar[len];
			auto len2 = GetWindowTextW(hwnd, buffer.ptr, cast(int) buffer.length);
			auto str = buffer[0 .. len2];
			return makeUtf8StringFromWindowsString(str);
		}

		void move(int x, int y) {
			RECT rect;
			GetWindowRect(hwnd, &rect);
			// move it while maintaining the same size...
			MoveWindow(hwnd, x, y, rect.right - rect.left, rect.bottom - rect.top, true);
		}

		void resize(int w, int h) {
			RECT rect;
			GetWindowRect(hwnd, &rect);

			RECT client;
			GetClientRect(hwnd, &client);

			rect.right = rect.right - client.right + w;
			rect.bottom = rect.bottom - client.bottom + h;

			// same position, new size for the client rectangle
			MoveWindow(hwnd, rect.left, rect.top, rect.right, rect.bottom, true);

			version(without_opengl) {} else if (openglMode == OpenGlOptions.yes) glViewport(0, 0, w, h);
		}

		void moveResize (int x, int y, int w, int h) {
			// what's given is the client rectangle, we need to adjust

			RECT rect;
			rect.left = x;
			rect.top = y;
			rect.right = w + x;
			rect.bottom = h + y;
			if(!AdjustWindowRect(&rect, GetWindowLong(hwnd, GWL_STYLE), GetMenu(hwnd) !is null))
				throw new Exception("AdjustWindowRect");

			MoveWindow(hwnd, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, true);
			version(without_opengl) {} else if (openglMode == OpenGlOptions.yes) glViewport(0, 0, w, h);
			if (windowResized !is null) windowResized(w, h);
		}

		version(without_opengl) {} else {
			HGLRC ghRC;
			HDC ghDC;
		}

		void createWindow(int width, int height, string title, OpenGlOptions opengl, SimpleWindow parent) {
			string cnamec;
			if (sdpyWindowClassStr is null) loadBinNameToWindowClassName();
			if (sdpyWindowClassStr is null || sdpyWindowClassStr[0] == 0) {
				cnamec = "DSimpleWindow";
			} else {
				cnamec = sdpyWindowClass;
			}

			WCharzBuffer cn = WCharzBuffer(cnamec);

			HINSTANCE hInstance = cast(HINSTANCE) GetModuleHandle(null);

			if(cnamec !in knownWinClasses) {
				WNDCLASSEX wc;

				// FIXME: I might be able to use cbWndExtra to hold the pointer back
				// to the object. Maybe.
				wc.cbSize = wc.sizeof;
				wc.cbClsExtra = 0;
				wc.cbWndExtra = 0;
				wc.hbrBackground = cast(HBRUSH) (COLOR_WINDOW+1); // GetStockObject(WHITE_BRUSH);
				wc.hCursor = LoadCursorW(null, IDC_ARROW);
				wc.hIcon = LoadIcon(hInstance, null);
				wc.hInstance = hInstance;
				wc.lpfnWndProc = &WndProc;
				wc.lpszClassName = cn.ptr;
				wc.hIconSm = null;
				wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
				if(!RegisterClassExW(&wc))
					throw new WindowsApiException("RegisterClassExW");
				knownWinClasses[cnamec] = true;
			}

			int style;
			uint flags = WS_EX_ACCEPTFILES; // accept drag-drop files

			// FIXME: windowType and customizationFlags
			final switch(windowType) {
				case WindowTypes.normal:
					style = WS_OVERLAPPEDWINDOW;
				break;
				case WindowTypes.undecorated:
					style = WS_POPUP | WS_SYSMENU;
				break;
				case WindowTypes.eventOnly:
					_hidden = true;
				break;
				case WindowTypes.dropdownMenu:
				case WindowTypes.popupMenu:
				case WindowTypes.notification:
					style = WS_POPUP;
					flags |= WS_EX_NOACTIVATE;
				break;
				case WindowTypes.nestedChild:
					style = WS_CHILD;
				break;
			}

			if ((customizationFlags & WindowFlags.extraComposite) != 0)
				flags |= WS_EX_LAYERED; // composite window for better performance and effects support

			hwnd = CreateWindowEx(flags, cn.ptr, toWStringz(title), style | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, // the clip children helps avoid flickering in minigui and doesn't seem to harm other use (mostly, sdpy is no child windows anyway) sooo i think it is ok
				CW_USEDEFAULT, CW_USEDEFAULT, width, height,
				parent is null ? null : parent.impl.hwnd, null, hInstance, null);

			if ((customizationFlags & WindowFlags.extraComposite) != 0)
				setOpacity(255);

			SimpleWindow.nativeMapping[hwnd] = this;
			CapableOfHandlingNativeEvent.nativeHandleMapping[hwnd] = this;

			if(windowType == WindowTypes.eventOnly)
				return;

			HDC hdc = GetDC(hwnd);


			version(without_opengl) {}
			else {
				if(opengl == OpenGlOptions.yes) {
					if(!openGlLibrariesSuccessfullyLoaded) throw new Exception("OpenGL libraries did not load");
					static if (SdpyIsUsingIVGLBinds) {if (glbindGetProcAddress("glHint") is null) assert(0, "GL: error loading OpenGL"); } // loads all necessary functions
					static if (SdpyIsUsingIVGLBinds) import iv.glbinds; // override druntime windows imports
					ghDC = hdc;
					PIXELFORMATDESCRIPTOR pfd;

					pfd.nSize = PIXELFORMATDESCRIPTOR.sizeof;
					pfd.nVersion = 1;
					pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL |  PFD_DOUBLEBUFFER;
					pfd.dwLayerMask = PFD_MAIN_PLANE;
					pfd.iPixelType = PFD_TYPE_RGBA;
					pfd.cColorBits = 24;
					pfd.cDepthBits = 24;
					pfd.cAccumBits = 0;
					pfd.cStencilBits = 8; // any reasonable OpenGL implementation should support this anyway

					auto pixelformat = ChoosePixelFormat(hdc, &pfd);

					if (pixelformat == 0)
						throw new WindowsApiException("ChoosePixelFormat");

					if (SetPixelFormat(hdc, pixelformat, &pfd) == 0)
						throw new WindowsApiException("SetPixelFormat");

					if (sdpyOpenGLContextVersion && wglCreateContextAttribsARB is null) {
						// windoze is idiotic: we have to have OpenGL context to get function addresses
						// so we will create fake context to get that stupid address
						auto tmpcc = wglCreateContext(ghDC);
						if (tmpcc !is null) {
							scope(exit) { wglMakeCurrent(ghDC, null); wglDeleteContext(tmpcc); }
							wglMakeCurrent(ghDC, tmpcc);
							wglInitOtherFunctions();
						}
					}

					if (wglCreateContextAttribsARB !is null && sdpyOpenGLContextVersion) {
						int[9] contextAttribs = [
							WGL_CONTEXT_MAJOR_VERSION_ARB, (sdpyOpenGLContextVersion>>8),
							WGL_CONTEXT_MINOR_VERSION_ARB, (sdpyOpenGLContextVersion&0xff),
							WGL_CONTEXT_PROFILE_MASK_ARB, (sdpyOpenGLContextCompatible ? WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB : WGL_CONTEXT_CORE_PROFILE_BIT_ARB),
							// for modern context, set "forward compatibility" flag too
							(sdpyOpenGLContextCompatible ? 0/*None*/ : WGL_CONTEXT_FLAGS_ARB), WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
							0/*None*/,
						];
						ghRC = wglCreateContextAttribsARB(ghDC, null, contextAttribs.ptr);
						if (ghRC is null && sdpyOpenGLContextAllowFallback) {
							// activate fallback mode
							// sdpyOpenGLContextVeto-type focus management policy leads to race conditions because the window becoming unviewable may coincide with the window manager deciding to move the focus elsrsion = 0;
							ghRC = wglCreateContext(ghDC);
						}
						if (ghRC is null)
							throw new WindowsApiException("wglCreateContextAttribsARB");
					} else {
						// try to do at least something
						if (sdpyOpenGLContextAllowFallback || sdpyOpenGLContextVersion == 0) {
							sdpyOpenGLContextVersion = 0;
							ghRC = wglCreateContext(ghDC);
						}
						if (ghRC is null)
							throw new WindowsApiException("wglCreateContext");
					}
				}
			}

			if(opengl == OpenGlOptions.no) {
				buffer = CreateCompatibleBitmap(hdc, width, height);

				auto hdcBmp = CreateCompatibleDC(hdc);
				// make sure it's filled with a blank slate
				auto oldBmp = SelectObject(hdcBmp, buffer);
				auto oldBrush = SelectObject(hdcBmp, GetStockObject(WHITE_BRUSH));
				auto oldPen = SelectObject(hdcBmp, GetStockObject(WHITE_PEN));
				gdi.Rectangle(hdcBmp, 0, 0, width, height);
				SelectObject(hdcBmp, oldBmp);
				SelectObject(hdcBmp, oldBrush);
				SelectObject(hdcBmp, oldPen);
				DeleteDC(hdcBmp);

				ReleaseDC(hwnd, hdc); // we keep this in opengl mode since it is a class member now
			}

			// We want the window's client area to match the image size
			RECT rcClient, rcWindow;
			POINT ptDiff;
			GetClientRect(hwnd, &rcClient);
			GetWindowRect(hwnd, &rcWindow);
			ptDiff.x = (rcWindow.right - rcWindow.left) - rcClient.right;
			ptDiff.y = (rcWindow.bottom - rcWindow.top) - rcClient.bottom;
			MoveWindow(hwnd,rcWindow.left, rcWindow.top, width + ptDiff.x, height + ptDiff.y, true);

			if ((customizationFlags&WindowFlags.dontAutoShow) == 0) {
				ShowWindow(hwnd, SW_SHOWNORMAL);
			} else {
				_hidden = true;
			}
			this._visibleForTheFirstTimeCalled = false; // hack!
		}


		void dispose() {
			if(buffer)
				DeleteObject(buffer);
		}

		void closeWindow() {
			DestroyWindow(hwnd);
		}

		bool setOpacity(ubyte alpha) {
			return SetLayeredWindowAttributes(hwnd, 0, alpha, LWA_ALPHA) == TRUE;
		}

		HANDLE currentCursor;

		// returns zero if it recognized the event
		static int triggerEvents(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam, int offsetX, int offsetY, SimpleWindow wind) {
			MouseEvent mouse;

			void mouseEvent(bool isScreen, ulong mods) {
				auto x = LOWORD(lParam);
				auto y = HIWORD(lParam);
				if(isScreen) {
					POINT p;
					p.x = x;
					p.y = y;
					ScreenToClient(hwnd, &p);
					x = cast(ushort) p.x;
					y = cast(ushort) p.y;
				}
				mouse.x = x + offsetX;
				mouse.y = y + offsetY;

				wind.mdx(mouse);
				mouse.modifierState = cast(int) mods;
				mouse.window = wind;

				if(wind.handleMouseEvent)
					wind.handleMouseEvent(mouse);
			}

			switch(msg) {
				case WM_GETMINMAXINFO:
					MINMAXINFO* mmi = cast(MINMAXINFO*) lParam;

					if(wind.minWidth > 0) {
						RECT rect;
						rect.left = 100;
						rect.top = 100;
						rect.right = wind.minWidth + 100;
						rect.bottom = wind.minHeight + 100;
						if(!AdjustWindowRect(&rect, GetWindowLong(wind.hwnd, GWL_STYLE), GetMenu(wind.hwnd) !is null))
							throw new WindowsApiException("AdjustWindowRect");

						mmi.ptMinTrackSize.x = rect.right - rect.left;
						mmi.ptMinTrackSize.y = rect.bottom - rect.top;
					}

					if(wind.maxWidth < int.max) {
						RECT rect;
						rect.left = 100;
						rect.top = 100;
						rect.right = wind.maxWidth + 100;
						rect.bottom = wind.maxHeight + 100;
						if(!AdjustWindowRect(&rect, GetWindowLong(wind.hwnd, GWL_STYLE), GetMenu(wind.hwnd) !is null))
							throw new WindowsApiException("AdjustWindowRect");

						mmi.ptMaxTrackSize.x = rect.right - rect.left;
						mmi.ptMaxTrackSize.y = rect.bottom - rect.top;
					}
				break;
				case WM_CHAR:
					wchar c = cast(wchar) wParam;
					if(wind.handleCharEvent)
						wind.handleCharEvent(cast(dchar) c);
				break;
				  case WM_SETFOCUS:
				  case WM_KILLFOCUS:
					wind._focused = (msg == WM_SETFOCUS);
					if (msg == WM_SETFOCUS) altPressed = false; //k8: reset alt state on defocus (it is better than nothing...)
					if(wind.onFocusChange)
						wind.onFocusChange(msg == WM_SETFOCUS);
				  break;
				case WM_SYSKEYDOWN:
					goto case;
				case WM_SYSKEYUP:
					if(lParam & (1 << 29)) {
						goto case;
					} else {
						// no window has keyboard focus
						goto default;
					}
				case WM_KEYDOWN:
				case WM_KEYUP:
					KeyEvent ev;
					ev.key = cast(Key) wParam;
					ev.pressed = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
					if (wParam == 0x12) ev.key = Key.Alt; // windows does it this way

					ev.hardwareCode = (lParam & 0xff0000) >> 16;

					if(GetKeyState(Key.Shift)&0x8000 || GetKeyState(Key.Shift_r)&0x8000)
						ev.modifierState |= ModifierState.shift;
					//k8: this doesn't work; thanks for nothing, windows
					/*if(GetKeyState(Key.Alt)&0x8000 || GetKeyState(Key.Alt_r)&0x8000)
						ev.modifierState |= ModifierState.alt;*/
					if (wParam == 0x12) altPressed = (msg == WM_SYSKEYDOWN);
					if (altPressed) ev.modifierState |= ModifierState.alt; else ev.modifierState &= ~ModifierState.alt;
					if(GetKeyState(Key.Ctrl)&0x8000 || GetKeyState(Key.Ctrl_r)&0x8000)
						ev.modifierState |= ModifierState.ctrl;
					if(GetKeyState(Key.Windows)&0x8000 || GetKeyState(Key.Windows_r)&0x8000)
						ev.modifierState |= ModifierState.windows;
					if(GetKeyState(Key.NumLock))
						ev.modifierState |= ModifierState.numLock;
					if(GetKeyState(Key.CapsLock))
						ev.modifierState |= ModifierState.capsLock;

					/+
					// we always want to send the character too, so let's convert it
					ubyte[256] state;
					wchar[16] buffer;
					GetKeyboardState(state.ptr);
					ToUnicodeEx(wParam, lParam, state.ptr, buffer.ptr, buffer.length, 0, null);

					foreach(dchar d; buffer) {
						ev.character = d;
						break;
					}
					+/

					ev.window = wind;
					if(wind.handleKeyEvent)
						wind.handleKeyEvent(ev);
				break;
				case 0x020a /*WM_MOUSEWHEEL*/:
					// send click
					mouse.type = cast(MouseEventType) 1;
					mouse.button = ((HIWORD(wParam) > 120) ? MouseButton.wheelDown : MouseButton.wheelUp);
					mouseEvent(true, LOWORD(wParam));

					// also send release
					mouse.type = cast(MouseEventType) 2;
					mouse.button = ((HIWORD(wParam) > 120) ? MouseButton.wheelDown : MouseButton.wheelUp);
					mouseEvent(true, LOWORD(wParam));
				break;
				case WM_MOUSEMOVE:
					mouse.type = cast(MouseEventType) 0;
					mouseEvent(false, wParam);
				break;
				case WM_LBUTTONDOWN:
				case WM_LBUTTONDBLCLK:
					mouse.type = cast(MouseEventType) 1;
					mouse.button = MouseButton.left;
					mouse.doubleClick = msg == WM_LBUTTONDBLCLK;
					mouseEvent(false, wParam);
				break;
				case WM_LBUTTONUP:
					mouse.type = cast(MouseEventType) 2;
					mouse.button = MouseButton.left;
					mouseEvent(false, wParam);
				break;
				case WM_RBUTTONDOWN:
				case WM_RBUTTONDBLCLK:
					mouse.type = cast(MouseEventType) 1;
					mouse.button = MouseButton.right;
					mouse.doubleClick = msg == WM_RBUTTONDBLCLK;
					mouseEvent(false, wParam);
				break;
				case WM_RBUTTONUP:
					mouse.type = cast(MouseEventType) 2;
					mouse.button = MouseButton.right;
					mouseEvent(false, wParam);
				break;
				case WM_MBUTTONDOWN:
				case WM_MBUTTONDBLCLK:
					mouse.type = cast(MouseEventType) 1;
					mouse.button = MouseButton.middle;
					mouse.doubleClick = msg == WM_MBUTTONDBLCLK;
					mouseEvent(false, wParam);
				break;
				case WM_MBUTTONUP:
					mouse.type = cast(MouseEventType) 2;
					mouse.button = MouseButton.middle;
					mouseEvent(false, wParam);
				break;
				case WM_XBUTTONDOWN:
				case WM_XBUTTONDBLCLK:
					mouse.type = cast(MouseEventType) 1;
					mouse.button = HIWORD(wParam) == 1 ? MouseButton.backButton : MouseButton.forwardButton;
					mouse.doubleClick = msg == WM_XBUTTONDBLCLK;
					mouseEvent(false, wParam);
				return 1; // MSDN says special treatment here, return TRUE to bypass simulation programs
				case WM_XBUTTONUP:
					mouse.type = cast(MouseEventType) 2;
					mouse.button = HIWORD(wParam) == 1 ? MouseButton.backButton : MouseButton.forwardButton;
					mouseEvent(false, wParam);
				return 1; // see: https://msdn.microsoft.com/en-us/library/windows/desktop/ms646246(v=vs.85).aspx

				default: return 1;
			}
			return 0;
		}

		HWND hwnd;
		int oldWidth;
		int oldHeight;
		bool inSizeMove;

		// the extern(Windows) wndproc should just forward to this
		LRESULT windowProcedure(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam) {
			assert(hwnd is this.hwnd);

			if(triggerEvents(hwnd, msg, wParam, lParam, 0, 0, this))
			switch(msg) {
				case WM_SETCURSOR:
					if(cast(HWND) wParam !is hwnd)
						return 0; // further processing elsewhere

					if(LOWORD(lParam) == HTCLIENT && (this.curHidden > 0 || currentCursor !is null)) {
						SetCursor(this.curHidden > 0 ? null : currentCursor);
						return 1;
					} else {
						return DefWindowProc(hwnd, msg, wParam, lParam);
					}
				//break;

				case WM_CLOSE:
					if (this.closeQuery !is null) this.closeQuery(); else this.close();
				break;
				case WM_DESTROY:
					if (this.onDestroyed !is null) try { this.onDestroyed(); } catch (Exception e) {} // sorry
					SimpleWindow.nativeMapping.remove(hwnd);
					CapableOfHandlingNativeEvent.nativeHandleMapping.remove(hwnd);

					bool anyImportant = false;
					foreach(SimpleWindow w; SimpleWindow.nativeMapping)
						if(w.beingOpenKeepsAppOpen) {
							anyImportant = true;
							break;
						}
					if(!anyImportant) {
						PostQuitMessage(0);
					}
				break;
				case WM_SIZE:
					if(wParam == 1 /* SIZE_MINIMIZED */)
						break;
					_width = LOWORD(lParam);
					_height = HIWORD(lParam);

					// I want to avoid tearing in the windows (my code is inefficient
					// so this is a hack around that) so while sizing, we don't trigger,
					// but we do want to trigger on events like mazimize.
					if(!inSizeMove)
						goto size_changed;
				break;
				// I don't like the tearing I get when redrawing on WM_SIZE
				// (I know there's other ways to fix that but I don't like that behavior anyway)
				// so instead it is going to redraw only at the end of a size.
				case 0x0231: /* WM_ENTERSIZEMOVE */
					oldWidth = this.width;
					oldHeight = this.height;
					inSizeMove = true;
				break;
				case 0x0232: /* WM_EXITSIZEMOVE */
					inSizeMove = false;
					// nothing relevant changed, don't bother redrawing
					if(oldWidth == width && oldHeight == height)
						break;

					size_changed:

					// note: OpenGL windows don't use a backing bmp, so no need to change them
					// if resizability is anything other than allowResizing, it is meant to either stretch the one image or just do nothing
					if(openglMode == OpenGlOptions.no) { // && resizability == Resizability.allowResizing) {
						// gotta get the double buffer bmp to match the window
					// FIXME: could this be more efficient? It isn't really necessary to make
					// a new buffer if we're sizing down at least.
						auto hdc = GetDC(hwnd);
						auto oldBuffer = buffer;
						buffer = CreateCompatibleBitmap(hdc, width, height);

						auto hdcBmp = CreateCompatibleDC(hdc);
						auto oldBmp = SelectObject(hdcBmp, buffer);

						auto hdcOldBmp = CreateCompatibleDC(hdc);
						auto oldOldBmp = SelectObject(hdcOldBmp, oldBmp);

						BitBlt(hdcBmp, 0, 0, width, height, hdcOldBmp, oldWidth, oldHeight, SRCCOPY);

						SelectObject(hdcOldBmp, oldOldBmp);
						DeleteDC(hdcOldBmp);

						SelectObject(hdcBmp, oldBmp);
						DeleteDC(hdcBmp);

						ReleaseDC(hwnd, hdc);

						DeleteObject(oldBuffer);
					}

					version(without_opengl) {} else
					if(openglMode == OpenGlOptions.yes && resizability == Resizability.automaticallyScaleIfPossible) {
						glViewport(0, 0, width, height);
					}

					if(windowResized !is null)
						windowResized(width, height);
				break;
				case WM_ERASEBKGND:
					// call `visibleForTheFirstTime` here, so we can do initialization as early as possible
					if (!this._visibleForTheFirstTimeCalled) {
						this._visibleForTheFirstTimeCalled = true;
						if (this.visibleForTheFirstTime !is null) {
							version(without_opengl) {} else {
								if(openglMode == OpenGlOptions.yes) {
									this.setAsCurrentOpenGlContextNT();
									glViewport(0, 0, width, height);
								}
							}
							this.visibleForTheFirstTime();
						}
					}
					// block it in OpenGL mode, 'cause no sane person will (or should) draw windows controls over OpenGL scene
					version(without_opengl) {} else {
						if (openglMode == OpenGlOptions.yes) return 1;
					}
					// call windows default handler, so it can paint standard controls
					goto default;
				case WM_CTLCOLORBTN:
				case WM_CTLCOLORSTATIC:
					SetBkMode(cast(HDC) wParam, TRANSPARENT);
					return cast(typeof(return)) //GetStockObject(NULL_BRUSH);
					GetSysColorBrush(COLOR_3DFACE);
				//break;
				case WM_SHOWWINDOW:
					this._visible = (wParam != 0);
					if (!this._visibleForTheFirstTimeCalled && this._visible) {
						this._visibleForTheFirstTimeCalled = true;
						if (this.visibleForTheFirstTime !is null) {
							version(without_opengl) {} else {
								if(openglMode == OpenGlOptions.yes) {
									this.setAsCurrentOpenGlContextNT();
									glViewport(0, 0, width, height);
								}
							}
							this.visibleForTheFirstTime();
						}
					}
					if (this.visibilityChanged !is null) this.visibilityChanged(this._visible);
					break;
				case WM_PAINT: {
					if (!this._visibleForTheFirstTimeCalled) {
						this._visibleForTheFirstTimeCalled = true;
						if (this.visibleForTheFirstTime !is null) {
							version(without_opengl) {} else {
								if(openglMode == OpenGlOptions.yes) {
									this.setAsCurrentOpenGlContextNT();
									glViewport(0, 0, width, height);
								}
							}
							this.visibleForTheFirstTime();
						}
					}

					BITMAP bm;
					PAINTSTRUCT ps;

					HDC hdc = BeginPaint(hwnd, &ps);

					if(openglMode == OpenGlOptions.no) {

						HDC hdcMem = CreateCompatibleDC(hdc);
						HBITMAP hbmOld = SelectObject(hdcMem, buffer);

						GetObject(buffer, bm.sizeof, &bm);

						// FIXME: only BitBlt the invalidated rectangle, not the whole thing
						if(resizability == Resizability.automaticallyScaleIfPossible)
						StretchBlt(hdc, 0, 0, this.width, this.height, hdcMem, 0, 0, bm.bmWidth, bm.bmHeight, SRCCOPY);
						else
						BitBlt(hdc, 0, 0, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, SRCCOPY);

						SelectObject(hdcMem, hbmOld);
						DeleteDC(hdcMem);
						EndPaint(hwnd, &ps);
					} else {
						EndPaint(hwnd, &ps);
						version(without_opengl) {} else
							redrawOpenGlSceneNow();
					}
				} break;
				  default:
					return DefWindowProc(hwnd, msg, wParam, lParam);
			}
			 return 0;

		}
	}

	mixin template NativeImageImplementation() {
		HBITMAP handle;
		ubyte* rawData;

	final:

		Color getPixel(int x, int y) {
			auto itemsPerLine = ((cast(int) width * 3 + 3) / 4) * 4;
			// remember, bmps are upside down
			auto offset = itemsPerLine * (height - y - 1) + x * 3;

			Color c;
			if(enableAlpha)
				c.a = rawData[offset + 3];
			else
				c.a = 255;
			c.b = rawData[offset + 0];
			c.g = rawData[offset + 1];
			c.r = rawData[offset + 2];
			c.unPremultiply();
			return c;
		}

		void setPixel(int x, int y, Color c) {
			auto itemsPerLine = ((cast(int) width * 3 + 3) / 4) * 4;
			// remember, bmps are upside down
			auto offset = itemsPerLine * (height - y - 1) + x * 3;

			if(enableAlpha)
				c.premultiply();

			rawData[offset + 0] = c.b;
			rawData[offset + 1] = c.g;
			rawData[offset + 2] = c.r;
			if(enableAlpha)
				rawData[offset + 3] = c.a;
		}

		void convertToRgbaBytes(ubyte[] where) {
			assert(where.length == this.width * this.height * 4);

			auto itemsPerLine = ((cast(int) width * 3 + 3) / 4) * 4;
			int idx = 0;
			int offset = itemsPerLine * (height - 1);
			// remember, bmps are upside down
			for(int y = height - 1; y >= 0; y--) {
				auto offsetStart = offset;
				for(int x = 0; x < width; x++) {
					where[idx + 0] = rawData[offset + 2]; // r
					where[idx + 1] = rawData[offset + 1]; // g
					where[idx + 2] = rawData[offset + 0]; // b
					if(enableAlpha) {
						where[idx + 3] = rawData[offset + 3]; // a
						unPremultiplyRgba(where[idx .. idx + 4]);
						offset++;
					} else
						where[idx + 3] = 255; // a
					idx += 4;
					offset += 3;
				}

				offset = offsetStart - itemsPerLine;
			}
		}

		void setFromRgbaBytes(in ubyte[] what) {
			assert(what.length == this.width * this.height * 4);

			auto itemsPerLine = enableAlpha ? (width * 4) : (((cast(int) width * 3 + 3) / 4) * 4);
			int idx = 0;
			int offset = itemsPerLine * (height - 1);
			// remember, bmps are upside down
			for(int y = height - 1; y >= 0; y--) {
				auto offsetStart = offset;
				for(int x = 0; x < width; x++) {
					if(enableAlpha) {
						auto a = what[idx + 3];

						rawData[offset + 2] = (a * what[idx + 0]) / 255; // r
						rawData[offset + 1] = (a * what[idx + 1]) / 255; // g
						rawData[offset + 0] = (a * what[idx + 2]) / 255; // b
						rawData[offset + 3] = a; // a
						premultiplyBgra(rawData[offset .. offset + 4]);
						offset++;
					} else {
						rawData[offset + 2] = what[idx + 0]; // r
						rawData[offset + 1] = what[idx + 1]; // g
						rawData[offset + 0] = what[idx + 2]; // b
					}
					idx += 4;
					offset += 3;
				}

				offset = offsetStart - itemsPerLine;
			}
		}


		void createImage(int width, int height, bool forcexshm=false, bool enableAlpha = false) {
			BITMAPINFO infoheader;
			infoheader.bmiHeader.biSize = infoheader.bmiHeader.sizeof;
			infoheader.bmiHeader.biWidth = width;
			infoheader.bmiHeader.biHeight = height;
			infoheader.bmiHeader.biPlanes = 1;
			infoheader.bmiHeader.biBitCount = enableAlpha ? 32: 24;
			infoheader.bmiHeader.biCompression = BI_RGB;

			handle = CreateDIBSection(
				null,
				&infoheader,
				DIB_RGB_COLORS,
				cast(void**) &rawData,
				null,
				0);
			if(handle is null)
				throw new WindowsApiException("create image failed");

		}

		void dispose() {
			DeleteObject(handle);
		}
	}

	enum KEY_ESCAPE = 27;
}
version(X11) {
	/// This is the default font used. You might change this before doing anything else with
	/// the library if you want to try something else. Surround that in `static if(UsingSimpledisplayX11)`
	/// for cross-platform compatibility.
	//__gshared string xfontstr = "-*-dejavu sans-medium-r-*-*-12-*-*-*-*-*-*-*";
	//__gshared string xfontstr = "-*-dejavu sans-medium-r-*-*-12-*-*-*-*-*-*-*";
	__gshared string xfontstr = "-*-lucida-medium-r-normal-sans-12-*-*-*-*-*-*-*";
	//__gshared string xfontstr = "-*-fixed-medium-r-*-*-14-*-*-*-*-*-*-*";

	alias int delegate(XEvent) NativeEventHandler;
	alias Window NativeWindowHandle;

	enum KEY_ESCAPE = 9;

	mixin template NativeScreenPainterImplementation() {
		Display* display;
		Drawable d;
		Drawable destiny;

		// FIXME: should the gc be static too so it isn't recreated every time draw is called?
		GC gc;

		__gshared bool fontAttempted;

		__gshared XFontStruct* defaultfont;
		__gshared XFontSet defaultfontset;

		XFontStruct* font;
		XFontSet fontset;

		void create(NativeWindowHandle window) {
			this.display = XDisplayConnection.get();

			Drawable buffer = None;
			if(auto sw = cast(SimpleWindow) this.window) {
				buffer = sw.impl.buffer;
				this.destiny = cast(Drawable) window;
			} else {
				buffer = cast(Drawable) window;
				this.destiny = None;
			}

			this.d = cast(Drawable) buffer;

			auto dgc = DefaultGC(display, DefaultScreen(display));

			this.gc = XCreateGC(display, d, 0, null);

			XCopyGC(display, dgc, 0xffffffff, this.gc);

			ensureDefaultFontLoaded();

			font = defaultfont;
			fontset = defaultfontset;

			if(font) {
				XSetFont(display, gc, font.fid);
			}
		}

		static void ensureDefaultFontLoaded() {
			if(!fontAttempted) {
				auto display = XDisplayConnection.get;
				auto font = XLoadQueryFont(display, xfontstr.ptr);
				// if the user font choice fails, fixed is pretty reliable (required by X to start!) and not bad either
				if(font is null) {
					xfontstr = "-*-fixed-medium-r-*-*-13-*-*-*-*-*-*-*";
					font = XLoadQueryFont(display, xfontstr.ptr);
				}

				char** lol;
				int lol2;
				char* lol3;
				auto fontset = XCreateFontSet(display, xfontstr.ptr, &lol, &lol2, &lol3);

				fontAttempted = true;

				defaultfont = font;
				defaultfontset = fontset;
			}
		}

		arsd.color.Rectangle _clipRectangle;
		void setClipRectangle(int x, int y, int width, int height) {
			_clipRectangle = arsd.color.Rectangle(Point(x, y), Size(width, height));
			if(width == 0 || height == 0) {
				XSetClipMask(display, gc, None);

				version(with_xft) {
					if(xftFont is null || xftDraw is null)
						return;
					XftDrawSetClip(xftDraw, null);
				}
			} else {
				XRectangle[1] rects;
				rects[0] = XRectangle(cast(short)(x), cast(short)(y), cast(short) width, cast(short) height);
				XSetClipRectangles(XDisplayConnection.get, gc, 0, 0, rects.ptr, 1, 0);

				version(with_xft) {
					if(xftFont is null || xftDraw is null)
						return;
					XftDrawSetClipRectangles(xftDraw, 0, 0, rects.ptr, 1);
				}
			}
		}

		version(with_xft) {
			XftFont* xftFont;
			XftDraw* xftDraw;

			XftColor xftColor;

			void updateXftColor() {
				if(xftFont is null)
					return;

				// not bothering with XftColorFree since p sure i don't need it on 24 bit displays....
				XRenderColor colorIn = XRenderColor(_outlineColor.r * 255, _outlineColor.g * 255, _outlineColor.b * 255, _outlineColor.a * 255);

				XftColorAllocValue(
					display,
					DefaultVisual(display, DefaultScreen(display)),
					DefaultColormap(display, 0),
					&colorIn,
					&xftColor
				);
			}
		}

		void setFont(OperatingSystemFont font) {
			version(with_xft) {
				if(font && font.isXft && font.xftFont)
					this.xftFont = font.xftFont;
				else
					this.xftFont = null;

				if(this.xftFont) {
					if(xftDraw is null) {
						xftDraw = XftDrawCreate(
							display,
							d,
							DefaultVisual(display, DefaultScreen(display)),
							DefaultColormap(display, 0)
						);

						updateXftColor();
					}

					return;
				}
			}

			if(font && font.font) {
				this.font = font.font;
				this.fontset = font.fontset;
				XSetFont(display, gc, font.font.fid);
			} else {
				this.font = defaultfont;
				this.fontset = defaultfontset;
			}

		}

		private Picture xrenderPicturePainter;

		void dispose() {
			this.rasterOp = RasterOp.normal;

			if(xrenderPicturePainter) {
				XRenderFreePicture(display, xrenderPicturePainter);
				xrenderPicturePainter = None;
			}

			// FIXME: this.window.width/height is probably wrong

			// src x,y     then dest x, y
			if(destiny != None) {
				XSetClipMask(display, gc, None);
				XCopyArea(display, d, destiny, gc, 0, 0, this.window.width, this.window.height, 0, 0);
			}

			XFreeGC(display, gc);

			version(with_xft)
			if(xftDraw) {
				XftDrawDestroy(xftDraw);
				xftDraw = null;
			}

			/+
			// this should prolly legit never be used since if it destroys the font handle from a OperatingSystemFont, it also ruins a reusable resource.
			if(font && font !is defaultfont) {
				XFreeFont(display, font);
				font = null;
			}
			if(fontset && fontset !is defaultfontset) {
				XFreeFontSet(display, fontset);
				fontset = null;
			}
			+/
			XFlush(display);

			if(window.paintingFinishedDg !is null)
				window.paintingFinishedDg()();
		}

		bool backgroundIsNotTransparent = true;
		bool foregroundIsNotTransparent = true;

		bool _penInitialized = false;
		Pen _activePen;

		Color _outlineColor;
		Color _fillColor;

		@property void pen(Pen p) {
			if(_penInitialized && p == _activePen) {
				return;
			}
			_penInitialized = true;
			_activePen = p;
			_outlineColor = p.color;

			int style;

			byte dashLength;

			final switch(p.style) {
				case Pen.Style.Solid:
					style = 0 /*LineSolid*/;
				break;
				case Pen.Style.Dashed:
					style = 1 /*LineOnOffDash*/;
					dashLength = 4;
				break;
				case Pen.Style.Dotted:
					style = 1 /*LineOnOffDash*/;
					dashLength = 1;
				break;
			}

			XSetLineAttributes(display, gc, p.width, style, 0, 0);
			if(dashLength)
				XSetDashes(display, gc, 0, &dashLength, 1);

			if(p.color.a == 0) {
				foregroundIsNotTransparent = false;
				return;
			}

			foregroundIsNotTransparent = true;

			XSetForeground(display, gc, colorToX(p.color, display));

			version(with_xft)
				updateXftColor();
		}

		RasterOp _currentRasterOp;
		bool _currentRasterOpInitialized = false;
		@property void rasterOp(RasterOp op) {
			if(_currentRasterOpInitialized && _currentRasterOp == op)
				return;
			_currentRasterOp = op;
			_currentRasterOpInitialized = true;
			int mode;
			final switch(op) {
				case RasterOp.normal:
					mode = GXcopy;
				break;
				case RasterOp.xor:
					mode = GXxor;
				break;
			}
			XSetFunction(display, gc, mode);
		}


		bool _fillColorInitialized = false;

		@property void fillColor(Color c) {
			if(_fillColorInitialized && _fillColor == c)
				return; // already good, no need to waste time calling it
			_fillColor = c;
			_fillColorInitialized = true;
			if(c.a == 0) {
				backgroundIsNotTransparent = false;
				return;
			}

			backgroundIsNotTransparent = true;

			XSetBackground(display, gc, colorToX(c, display));

		}

		void swapColors() {
			auto tmp = _fillColor;
			fillColor = _outlineColor;
			auto newPen = _activePen;
			newPen.color = tmp;
			pen(newPen);
		}

		uint colorToX(Color c, Display* display) {
			auto visual = DefaultVisual(display, DefaultScreen(display));
			import core.bitop;
			uint color = 0;
			{
			auto startBit = bsf(visual.red_mask);
			auto lastBit = bsr(visual.red_mask);
			auto r = cast(uint) c.r;
			r >>= 7 - (lastBit - startBit);
			r <<= startBit;
			color |= r;
			}
			{
			auto startBit = bsf(visual.green_mask);
			auto lastBit = bsr(visual.green_mask);
			auto g = cast(uint) c.g;
			g >>= 7 - (lastBit - startBit);
			g <<= startBit;
			color |= g;
			}
			{
			auto startBit = bsf(visual.blue_mask);
			auto lastBit = bsr(visual.blue_mask);
			auto b = cast(uint) c.b;
			b >>= 7 - (lastBit - startBit);
			b <<= startBit;
			color |= b;
			}



			return color;
		}

		void drawImage(int x, int y, Image i, int ix, int iy, int w, int h) {
			// source x, source y
			if(ix >= i.width) return;
			if(iy >= i.height) return;
			if(ix + w > i.width) w = i.width - ix;
			if(iy + h > i.height) h = i.height - iy;
			if(i.usingXshm)
				XShmPutImage(display, d, gc, i.handle, ix, iy, x, y, w, h, false);
			else
				XPutImage(display, d, gc, i.handle, ix, iy, x, y, w, h);
		}

		void drawPixmap(Sprite s, int x, int y, int ix, int iy, int w, int h) {
			if(s.enableAlpha) {
				// the Sprite must be created first, meaning if we're here, XRender is already loaded
				if(this.xrenderPicturePainter == None) {
					XRenderPictureAttributes attrs;
					// FIXME: I can prolly reuse this as long as the pixmap itself is valid.
					xrenderPicturePainter = XRenderCreatePicture(display, d, Sprite.RGB24, 0, &attrs);
				}

				XRenderComposite(
					display,
					3, // PicOpOver
					s.xrenderPicture,
					None,
					this.xrenderPicturePainter,
					ix,
					iy,
					0,
					0,
					x,
					y,
					w ? w : s.width,
					h ? h : s.height
				);
			} else {
				XCopyArea(display, s.handle, d, gc, ix, iy, w ? w : s.width, h ? h : s.height, x, y);
			}
		}

		int fontHeight() {
			version(with_xft)
				if(xftFont !is null)
					return xftFont.height;
			if(font)
				return font.max_bounds.ascent + font.max_bounds.descent;
			return 12; // pretty common default...
		}

		int textWidth(in char[] line) {
			version(with_xft)
			if(xftFont) {
				if(line.length == 0)
					return 0;
				XGlyphInfo extents;
				XftTextExtentsUtf8(display, xftFont, line.ptr, cast(int) line.length, &extents);
				return extents.width;
			}

			if(fontset) {
				if(line.length == 0)
					return 0;
				XRectangle rect;
				Xutf8TextExtents(fontset, line.ptr, cast(int) line.length, null, &rect);

				return rect.width;
			}

			if(font)
				// FIXME: unicode
				return XTextWidth( font, line.ptr, cast(int) line.length);
			else
				return fontHeight / 2 * cast(int) line.length; // if no font is loaded, it is prolly Fixed, which is a 2:1 ratio
		}

		Size textSize(in char[] text) {
			auto maxWidth = 0;
			auto lineHeight = fontHeight;
			int h = text.length ? 0 : lineHeight + 4; // if text is empty, it still gives the line height
			foreach(line; text.split('\n')) {
				int textWidth = this.textWidth(line);
				if(textWidth > maxWidth)
					maxWidth = textWidth;
				h += lineHeight + 4;
			}
			return Size(maxWidth, h);
		}

		void drawText(in int x, in int y, in int x2, in int y2, in char[] originalText, in uint alignment) {
			const(char)[] text;
			version(with_xft)
			if(xftFont) {
				text = originalText;
				goto loaded;
			}

			if(fontset)
				text = originalText;
			else {
				text.reserve(originalText.length);
				// the first 256 unicode codepoints are the same as ascii and latin-1, which is what X expects, so we can keep all those
				// then strip the rest so there isn't garbage
				foreach(dchar ch; originalText)
					if(ch < 256)
						text ~= cast(ubyte) ch;
					else
						text ~= 191; // FIXME: using a random character (upside down question mark) to fill the space
			}
			loaded:
			if(text.length == 0)
				return;

			// FIXME: should we clip it to the bounding box?
			int textHeight = fontHeight;

			auto lines = text.split('\n');

			const lineHeight = textHeight;
			textHeight *= lines.length;

			int cy = y;

			if(alignment & TextAlignment.VerticalBottom) {
				assert(y2);
				auto h = y2 - y;
				if(h > textHeight) {
					cy += h - textHeight;
					cy -= lineHeight / 2;
				}
			} else if(alignment & TextAlignment.VerticalCenter) {
				assert(y2);
				auto h = y2 - y;
				if(textHeight < h) {
					cy += (h - textHeight) / 2;
					//cy -= lineHeight / 4;
				}
			}

			foreach(line; text.split('\n')) {
				int textWidth = this.textWidth(line);

				int px = x, py = cy;

				if(alignment & TextAlignment.Center) {
					assert(x2);
					auto w = x2 - x;
					if(w > textWidth)
						px += (w - textWidth) / 2;
				} else if(alignment & TextAlignment.Right) {
					assert(x2);
					auto pos = x2 - textWidth;
					if(pos > x)
						px = pos;
				}

				version(with_xft)
				if(xftFont) {
					XftDrawStringUtf8(xftDraw, &xftColor, xftFont, px, py + xftFont.ascent, line.ptr, cast(int) line.length);

					goto carry_on;
				}

				if(fontset)
					Xutf8DrawString(display, d, fontset, gc, px, py + (font ? font.max_bounds.ascent : lineHeight), line.ptr, cast(int) line.length);
				else
					XDrawString(display, d, gc, px, py + (font ? font.max_bounds.ascent : lineHeight), line.ptr, cast(int) line.length);
				carry_on:
				cy += lineHeight + 4;
			}
		}

		void drawPixel(int x, int y) {
			XDrawPoint(display, d, gc, x, y);
		}

		// The basic shapes, outlined

		void drawLine(int x1, int y1, int x2, int y2) {
			if(foregroundIsNotTransparent)
				XDrawLine(display, d, gc, x1, y1, x2, y2);
		}

		void drawRectangle(int x, int y, int width, int height) {
			if(backgroundIsNotTransparent) {
				swapColors();
				XFillRectangle(display, d, gc, x+1, y+1, width-2, height-2); // Need to ensure pixels are only drawn once...
				swapColors();
			}
			// since X centers the line on the coordinates, we try to undo that with the width/2 thing here so it is aligned in the rectangle's bounds
			if(foregroundIsNotTransparent)
				XDrawRectangle(display, d, gc, x + _activePen.width / 2, y + _activePen.width / 2, width - 1 - _activePen.width / 2, height - 1 - _activePen.width / 2);
		}

		/// Arguments are the points of the bounding rectangle
		void drawEllipse(int x1, int y1, int x2, int y2) {
			drawArc(x1, y1, x2 - x1, y2 - y1, 0, 360 * 64);
		}

		// NOTE: start and finish are in units of degrees * 64
		void drawArc(int x1, int y1, int width, int height, int start, int finish) {
			if(backgroundIsNotTransparent) {
				swapColors();
				XFillArc(display, d, gc, x1, y1, width, height, start, finish);
				swapColors();
			}
			if(foregroundIsNotTransparent) {
				XDrawArc(display, d, gc, x1, y1, width, height, start, finish);
				// Windows draws the straight lines on the edges too so FIXME sort of
			}
		}

		void drawPolygon(Point[] vertexes) {
			XPoint[16] pointsBuffer;
			XPoint[] points;
			if(vertexes.length <= pointsBuffer.length)
				points = pointsBuffer[0 .. vertexes.length];
			else
				points.length = vertexes.length;

			foreach(i, p; vertexes) {
				points[i].x = cast(short) p.x;
				points[i].y = cast(short) p.y;
			}

			if(backgroundIsNotTransparent) {
				swapColors();
				XFillPolygon(display, d, gc, points.ptr, cast(int) points.length, PolygonShape.Complex, CoordMode.CoordModeOrigin);
				swapColors();
			}
			if(foregroundIsNotTransparent) {
				XDrawLines(display, d, gc, points.ptr, cast(int) points.length, CoordMode.CoordModeOrigin);
			}
		}
	}

	/* XRender { */

	struct XRenderColor {
		ushort red;
		ushort green;
		ushort blue;
		ushort alpha;
	}

	alias Picture = XID;
	alias PictFormat = XID;

	struct XGlyphInfo {
		ushort width;
		ushort height;
		short x;
		short y;
		short xOff;
		short yOff;
	}

struct XRenderDirectFormat {
    short   red;
    short   redMask;
    short   green;
    short   greenMask;
    short   blue;
    short   blueMask;
    short   alpha;
    short   alphaMask;
}

struct XRenderPictFormat {
    PictFormat		id;
    int			type;
    int			depth;
    XRenderDirectFormat	direct;
    Colormap		colormap;
}

enum PictFormatID	=   (1 << 0);
enum PictFormatType	=   (1 << 1);
enum PictFormatDepth	=   (1 << 2);
enum PictFormatRed	=   (1 << 3);
enum PictFormatRedMask  =(1 << 4);
enum PictFormatGreen	=   (1 << 5);
enum PictFormatGreenMask=(1 << 6);
enum PictFormatBlue	=   (1 << 7);
enum PictFormatBlueMask =(1 << 8);
enum PictFormatAlpha	=   (1 << 9);
enum PictFormatAlphaMask=(1 << 10);
enum PictFormatColormap =(1 << 11);

struct XRenderPictureAttributes {
	int 		repeat;
	Picture		alpha_map;
	int			alpha_x_origin;
	int			alpha_y_origin;
	int			clip_x_origin;
	int			clip_y_origin;
	Pixmap		clip_mask;
	Bool		graphics_exposures;
	int			subwindow_mode;
	int			poly_edge;
	int			poly_mode;
	Atom		dither;
	Bool		component_alpha;
}

alias int XFixed;

struct XPointFixed {
    XFixed  x, y;
}

struct XCircle {
    XFixed x;
    XFixed y;
    XFixed radius;
}

struct XTransform {
    XFixed[3][3]  matrix;
}

struct XFilters {
    int	    nfilter;
    char    **filter;
    int	    nalias;
    short   *alias_;
}

struct XIndexValue {
    c_ulong    pixel;
    ushort   red, green, blue, alpha;
}

struct XAnimCursor {
    Cursor	    cursor;
    c_ulong   delay;
}

struct XLinearGradient {
    XPointFixed p1;
    XPointFixed p2;
}

struct XRadialGradient {
    XCircle inner;
    XCircle outer;
}

struct XConicalGradient {
    XPointFixed center;
    XFixed angle; /* in degrees */
}

enum PictStandardARGB32  = 0;
enum PictStandardRGB24   = 1;
enum PictStandardA8	 =  2;
enum PictStandardA4	 =  3;
enum PictStandardA1	 =  4;
enum PictStandardNUM	 =  5;

interface XRender {
extern(C) @nogc:

	Bool XRenderQueryExtension (Display *dpy, int *event_basep, int *error_basep);

	Status XRenderQueryVersion (Display *dpy,
			int     *major_versionp,
			int     *minor_versionp);

	Status XRenderQueryFormats (Display *dpy);

	int XRenderQuerySubpixelOrder (Display *dpy, int screen);

	Bool XRenderSetSubpixelOrder (Display *dpy, int screen, int subpixel);

	XRenderPictFormat *
		XRenderFindVisualFormat (Display *dpy, const Visual *visual);

	XRenderPictFormat *
		XRenderFindFormat (Display			*dpy,
				c_ulong		mask,
				const XRenderPictFormat	*templ,
				int				count);
	XRenderPictFormat *
		XRenderFindStandardFormat (Display		*dpy,
				int			format);

	XIndexValue *
		XRenderQueryPictIndexValues(Display			*dpy,
				const XRenderPictFormat	*format,
				int				*num);

	Picture XRenderCreatePicture(
		Display *dpy,
		Drawable drawable,
		const XRenderPictFormat *format,
		c_ulong valuemask,
		const XRenderPictureAttributes *attributes);

	void XRenderChangePicture (Display				*dpy,
				Picture				picture,
				c_ulong			valuemask,
				const XRenderPictureAttributes  *attributes);

	void
		XRenderSetPictureClipRectangles (Display	    *dpy,
				Picture	    picture,
				int		    xOrigin,
				int		    yOrigin,
				const XRectangle *rects,
				int		    n);

	void
		XRenderSetPictureClipRegion (Display	    *dpy,
				Picture	    picture,
				Region	    r);

	void
		XRenderSetPictureTransform (Display	    *dpy,
				Picture	    picture,
				XTransform	    *transform);

	void
		XRenderFreePicture (Display                   *dpy,
				Picture                   picture);

	void
		XRenderComposite (Display   *dpy,
				int	    op,
				Picture   src,
				Picture   mask,
				Picture   dst,
				int	    src_x,
				int	    src_y,
				int	    mask_x,
				int	    mask_y,
				int	    dst_x,
				int	    dst_y,
				uint	width,
				uint	height);


	Picture XRenderCreateSolidFill (Display *dpy,
			const XRenderColor *color);

	Picture XRenderCreateLinearGradient (Display *dpy,
			const XLinearGradient *gradient,
			const XFixed *stops,
			const XRenderColor *colors,
			int nstops);

	Picture XRenderCreateRadialGradient (Display *dpy,
			const XRadialGradient *gradient,
			const XFixed *stops,
			const XRenderColor *colors,
			int nstops);

	Picture XRenderCreateConicalGradient (Display *dpy,
			const XConicalGradient *gradient,
			const XFixed *stops,
			const XRenderColor *colors,
			int nstops);



	Cursor
		XRenderCreateCursor (Display	    *dpy,
				Picture	    source,
				uint   x,
				uint   y);

	XFilters *
		XRenderQueryFilters (Display *dpy, Drawable drawable);

	void
		XRenderSetPictureFilter (Display    *dpy,
				Picture    picture,
				const char *filter,
				XFixed	    *params,
				int	    nparams);

	Cursor
		XRenderCreateAnimCursor (Display	*dpy,
				int		ncursor,
				XAnimCursor	*cursors);
}

__gshared bool XRenderLibrarySuccessfullyLoaded = true;
mixin DynamicLoad!(XRender, "Xrender", 1, XRenderLibrarySuccessfullyLoaded) XRenderLibrary;



	/* XRender } */

	/* Xft { */

	// actually freetype
	alias void FT_Face;

	// actually fontconfig
	private alias FcBool = int;
	alias void FcCharSet;
	alias void FcPattern;
	alias void FcResult;
	enum FcEndian { FcEndianBig, FcEndianLittle }
	struct FcFontSet {
		int nfont;
		int sfont;
		FcPattern** fonts;
	}

	// actually XRegion
	struct BOX {
		short x1, x2, y1, y2;
	}
	struct _XRegion {
		c_long size;
		c_long numRects;
		BOX* rects;
		BOX extents;
	}

	alias Region = _XRegion*;

	// ok actually Xft

	struct XftFontInfo;

	struct XftFont {
		int         ascent;
		int         descent;
		int         height;
		int         max_advance_width;
		FcCharSet*  charset;
		FcPattern*  pattern;
	}

	struct XftDraw;

	struct XftColor {
		c_ulong pixel;
		XRenderColor color;
	}

	struct XftCharSpec {
		dchar           ucs4;
		short           x;
		short           y;
	}

	struct XftCharFontSpec {
		XftFont         *font;
		dchar           ucs4;
		short           x;
		short           y;
	}

	struct XftGlyphSpec {
		uint            glyph;
		short           x;
		short           y;
	}

	struct XftGlyphFontSpec {
		XftFont         *font;
		uint            glyph;
		short           x;
		short           y;
	}

	interface Xft {
	extern(C) @nogc pure:

	Bool XftColorAllocName (Display  *dpy,
				const Visual   *visual,
				Colormap cmap,
				const char     *name,
				XftColor *result);

	Bool XftColorAllocValue (Display         *dpy,
				Visual          *visual,
				Colormap        cmap,
				const XRenderColor    *color,
				XftColor        *result);

	void XftColorFree (Display   *dpy,
				Visual    *visual,
				Colormap  cmap,
				XftColor  *color);

	Bool XftDefaultHasRender (Display *dpy);

	Bool XftDefaultSet (Display *dpy, FcPattern *defaults);

	void XftDefaultSubstitute (Display *dpy, int screen, FcPattern *pattern);

	XftDraw * XftDrawCreate (Display   *dpy,
		       Drawable  drawable,
		       Visual    *visual,
		       Colormap  colormap);

	XftDraw * XftDrawCreateBitmap (Display  *dpy,
			     Pixmap   bitmap);

	XftDraw * XftDrawCreateAlpha (Display *dpy,
			    Pixmap  pixmap,
			    int     depth);

	void XftDrawChange (XftDraw  *draw,
		       Drawable drawable);

	Display * XftDrawDisplay (XftDraw *draw);

	Drawable XftDrawDrawable (XftDraw *draw);

	Colormap XftDrawColormap (XftDraw *draw);

	Visual * XftDrawVisual (XftDraw *draw);

	void XftDrawDestroy (XftDraw *draw);

	Picture XftDrawPicture (XftDraw *draw);

	Picture XftDrawSrcPicture (XftDraw *draw, const XftColor *color);

	void XftDrawGlyphs (XftDraw          *draw,
				const XftColor *color,
				XftFont          *pub,
				int              x,
				int              y,
				const uint  *glyphs,
				int              nglyphs);

	void XftDrawString8 (XftDraw             *draw,
				const XftColor    *color,
				XftFont             *pub,
				int                 x,
				int                 y,
				const char     *string,
				int                 len);

	void XftDrawString16 (XftDraw            *draw,
				const XftColor   *color,
				XftFont            *pub,
				int                x,
				int                y,
				const wchar   *string,
				int                len);

	void XftDrawString32 (XftDraw            *draw,
				const XftColor   *color,
				XftFont            *pub,
				int                x,
				int                y,
				const dchar   *string,
				int                len);

	void XftDrawStringUtf8 (XftDraw          *draw,
				const XftColor *color,
				XftFont          *pub,
				int              x,
				int              y,
				const char  *string,
				int              len);
	void XftDrawStringUtf16 (XftDraw             *draw,
				const XftColor    *color,
				XftFont             *pub,
				int                 x,
				int                 y,
				const char     *string,
				FcEndian            endian,
				int                 len);

	void XftDrawCharSpec (XftDraw                *draw,
				const XftColor       *color,
				XftFont                *pub,
				const XftCharSpec    *chars,
				int                    len);

	void XftDrawCharFontSpec (XftDraw                    *draw,
				const XftColor           *color,
				const XftCharFontSpec    *chars,
				int                        len);

	void XftDrawGlyphSpec (XftDraw               *draw,
				const XftColor      *color,
				XftFont               *pub,
				const XftGlyphSpec  *glyphs,
				int                   len);

	void XftDrawGlyphFontSpec (XftDraw                   *draw,
				const XftColor          *color,
				const XftGlyphFontSpec  *glyphs,
				int                       len);

	void XftDrawRect (XftDraw            *draw,
				const XftColor   *color,
				int                x,
				int                y,
				uint       width,
				uint       height);

	Bool XftDrawSetClip (XftDraw     *draw,
				Region      r);


	Bool XftDrawSetClipRectangles (XftDraw               *draw,
				int                   xOrigin,
				int                   yOrigin,
				const XRectangle    *rects,
				int                   n);

	void XftDrawSetSubwindowMode (XftDraw    *draw,
				int        mode);

	void XftGlyphExtents (Display            *dpy,
				XftFont            *pub,
				const uint    *glyphs,
				int                nglyphs,
				XGlyphInfo         *extents);

	void XftTextExtents8 (Display            *dpy,
				XftFont            *pub,
				const char    *string,
				int                len,
				XGlyphInfo         *extents);

	void XftTextExtents16 (Display           *dpy,
				XftFont           *pub,
				const wchar  *string,
				int               len,
				XGlyphInfo        *extents);

	void XftTextExtents32 (Display           *dpy,
				XftFont           *pub,
				const dchar  *string,
				int               len,
				XGlyphInfo        *extents);

	void XftTextExtentsUtf8 (Display         *dpy,
				XftFont         *pub,
				const char *string,
				int             len,
				XGlyphInfo      *extents);

	void XftTextExtentsUtf16 (Display            *dpy,
				XftFont            *pub,
				const char    *string,
				FcEndian           endian,
				int                len,
				XGlyphInfo         *extents);

	FcPattern * XftFontMatch (Display           *dpy,
				int               screen,
				const FcPattern *pattern,
				FcResult          *result);

	XftFont * XftFontOpen (Display *dpy, int screen, ...);

	XftFont * XftFontOpenName (Display *dpy, int screen, const char *name);

	XftFont * XftFontOpenXlfd (Display *dpy, int screen, const char *xlfd);

	FT_Face XftLockFace (XftFont *pub);

	void XftUnlockFace (XftFont *pub);

	XftFontInfo * XftFontInfoCreate (Display *dpy, const FcPattern *pattern);

	void XftFontInfoDestroy (Display *dpy, XftFontInfo *fi);

	dchar XftFontInfoHash (const XftFontInfo *fi);

	FcBool XftFontInfoEqual (const XftFontInfo *a, const XftFontInfo *b);

	XftFont * XftFontOpenInfo (Display        *dpy,
				FcPattern      *pattern,
				XftFontInfo    *fi);

	XftFont * XftFontOpenPattern (Display *dpy, FcPattern *pattern);

	XftFont * XftFontCopy (Display *dpy, XftFont *pub);

	void XftFontClose (Display *dpy, XftFont *pub);

	FcBool XftInitFtLibrary();
	void XftFontLoadGlyphs (Display          *dpy,
				XftFont          *pub,
				FcBool           need_bitmaps,
				const uint  *glyphs,
				int              nglyph);

	void XftFontUnloadGlyphs (Display            *dpy,
				XftFont            *pub,
				const uint    *glyphs,
				int                nglyph);

	FcBool XftFontCheckGlyph (Display  *dpy,
				XftFont  *pub,
				FcBool   need_bitmaps,
				uint  glyph,
				uint  *missing,
				int      *nmissing);

	FcBool XftCharExists (Display      *dpy,
				XftFont      *pub,
				dchar    ucs4);

	uint XftCharIndex (Display       *dpy,
				XftFont       *pub,
				dchar      ucs4);
	FcBool XftInit (const char *config);

	int XftGetVersion ();

	FcFontSet * XftListFonts (Display   *dpy,
				int       screen,
				...);

	FcPattern *XftNameParse (const char *name);

	void XftGlyphRender (Display         *dpy,
				int             op,
				Picture         src,
				XftFont         *pub,
				Picture         dst,
				int             srcx,
				int             srcy,
				int             x,
				int             y,
				const uint *glyphs,
				int             nglyphs);

	void XftGlyphSpecRender (Display                 *dpy,
				int                     op,
				Picture                 src,
				XftFont                 *pub,
				Picture                 dst,
				int                     srcx,
				int                     srcy,
				const XftGlyphSpec    *glyphs,
				int                     nglyphs);

	void XftCharSpecRender (Display              *dpy,
				int                  op,
				Picture              src,
				XftFont              *pub,
				Picture              dst,
				int                  srcx,
				int                  srcy,
				const XftCharSpec  *chars,
				int                  len);
	void XftGlyphFontSpecRender (Display                     *dpy,
				int                         op,
				Picture                     src,
				Picture                     dst,
				int                         srcx,
				int                         srcy,
				const XftGlyphFontSpec    *glyphs,
				int                         nglyphs);

	void XftCharFontSpecRender (Display                  *dpy,
				int                      op,
				Picture                  src,
				Picture                  dst,
				int                      srcx,
				int                      srcy,
				const XftCharFontSpec  *chars,
				int                      len);

	void XftTextRender8 (Display         *dpy,
				int             op,
				Picture         src,
				XftFont         *pub,
				Picture         dst,
				int             srcx,
				int             srcy,
				int             x,
				int             y,
				const char *string,
				int             len);
	void XftTextRender16 (Display            *dpy,
				int                op,
				Picture            src,
				XftFont            *pub,
				Picture            dst,
				int                srcx,
				int                srcy,
				int                x,
				int                y,
				const wchar   *string,
				int                len);

	void XftTextRender16BE (Display          *dpy,
				int              op,
				Picture          src,
				XftFont          *pub,
				Picture          dst,
				int              srcx,
				int              srcy,
				int              x,
				int              y,
				const char  *string,
				int              len);

	void XftTextRender16LE (Display          *dpy,
				int              op,
				Picture          src,
				XftFont          *pub,
				Picture          dst,
				int              srcx,
				int              srcy,
				int              x,
				int              y,
				const char  *string,
				int              len);

	void XftTextRender32 (Display            *dpy,
				int                op,
				Picture            src,
				XftFont            *pub,
				Picture            dst,
				int                srcx,
				int                srcy,
				int                x,
				int                y,
				const dchar   *string,
				int                len);

	void XftTextRender32BE (Display          *dpy,
				int              op,
				Picture          src,
				XftFont          *pub,
				Picture          dst,
				int              srcx,
				int              srcy,
				int              x,
				int              y,
				const char  *string,
				int              len);

	void XftTextRender32LE (Display          *dpy,
				int              op,
				Picture          src,
				XftFont          *pub,
				Picture          dst,
				int              srcx,
				int              srcy,
				int              x,
				int              y,
				const char  *string,
				int              len);

	void XftTextRenderUtf8 (Display          *dpy,
				int              op,
				Picture          src,
				XftFont          *pub,
				Picture          dst,
				int              srcx,
				int              srcy,
				int              x,
				int              y,
				const char  *string,
				int              len);

	void XftTextRenderUtf16 (Display         *dpy,
				int             op,
				Picture         src,
				XftFont         *pub,
				Picture         dst,
				int             srcx,
				int             srcy,
				int             x,
				int             y,
				const char *string,
				FcEndian        endian,
				int             len);
	FcPattern * XftXlfdParse (const char *xlfd_orig, Bool ignore_scalable, Bool complete);

	}

	interface FontConfig {
	extern(C) @nogc pure:
		int FcPatternGetString(const FcPattern *p, const char *object, int n, char ** s);
		void FcFontSetDestroy(FcFontSet*);
		char* FcNameUnparse(const FcPattern *);
	}

	mixin DynamicLoad!(Xft, "Xft", 2, librariesSuccessfullyLoaded) XftLibrary;
	mixin DynamicLoad!(FontConfig, "fontconfig", 1, librariesSuccessfullyLoaded) FontConfigLibrary;


	/* Xft } */

	class XDisconnectException : Exception {
		bool userRequested;
		this(bool userRequested = true) {
			this.userRequested = userRequested;
			super("X disconnected");
		}
	}

	/// Platform-specific for X11. A singleton class (well, all its methods are actually static... so more like a namespace) wrapping a `Display*`.
	class XDisplayConnection {
		private __gshared Display* display;
		private __gshared XIM xim;
		private __gshared char* displayName;

		private __gshared int connectionSequence_;
		private __gshared bool isLocal_;

		/// use this for lazy caching when reconnection
		static int connectionSequenceNumber() { return connectionSequence_; }

		/++
			Guesses if the connection appears to be local.

			History:
				Added June 3, 2021
		+/
		static @property bool isLocal() nothrow @trusted @nogc {
			return isLocal_;
		}

		/// Attempts recreation of state, may require application assistance
		/// You MUST call this OUTSIDE the event loop. Let the exception kill the loop,
		/// then call this, and if successful, reenter the loop.
		static void discardAndRecreate(string newDisplayString = null) {
			if(insideXEventLoop)
				throw new Error("You MUST call discardAndRecreate from OUTSIDE the event loop");

			// auto swnm = SimpleWindow.nativeMapping.dup; // this SHOULD be unnecessary because all simple windows are capable of handling native events, so the latter ought to do it all
			auto chnenhm = CapableOfHandlingNativeEvent.nativeHandleMapping.dup;

			foreach(handle; chnenhm) {
				handle.discardConnectionState();
			}

			discardState();

			if(newDisplayString !is null)
				setDisplayName(newDisplayString);

			auto display = get();

			foreach(handle; chnenhm) {
				handle.recreateAfterDisconnect();
			}
		}

		private __gshared EventMask rootEventMask;

		/++
			Requests the specified input from the root window on the connection, in addition to any other request.

			
			Since plain XSelectInput will replace the existing mask, adding input from multiple locations is tricky. This central function will combine all the masks for you.

			$(WARNING it calls XSelectInput itself, which will override any other root window input you have!)
		+/
		static void addRootInput(EventMask mask) {
			auto old = rootEventMask;
			rootEventMask |= mask;
			get(); // to ensure display connected
			if(display !is null && rootEventMask != old)
				XSelectInput(display, RootWindow(display, DefaultScreen(display)), rootEventMask);
		}

		static void discardState() {
			freeImages();

			foreach(atomPtr; interredAtoms)
				*atomPtr = 0;
			interredAtoms = null;
			interredAtoms.assumeSafeAppend();

			ScreenPainterImplementation.fontAttempted = false;
			ScreenPainterImplementation.defaultfont = null;
			ScreenPainterImplementation.defaultfontset = null;

			Image.impl.xshmQueryCompleted = false;
			Image.impl._xshmAvailable = false;

			SimpleWindow.nativeMapping = null;
			CapableOfHandlingNativeEvent.nativeHandleMapping = null;
			// GlobalHotkeyManager

			display = null;
			xim = null;
		}

		// Do you want to know why do we need all this horrible-looking code? See comment at the bottom.
		private static void createXIM () {
			import core.stdc.locale : setlocale, LC_ALL;
			import core.stdc.stdio : stderr, fprintf;
			import core.stdc.stdlib : free;
			import core.stdc.string : strdup;

			static immutable string[3] mtry = [ null, "@im=local", "@im=" ];

			auto olocale = strdup(setlocale(LC_ALL, null));
			setlocale(LC_ALL, (sdx_isUTF8Locale ? "" : "en_US.UTF-8"));
			scope(exit) { setlocale(LC_ALL, olocale); free(olocale); }

			//fprintf(stderr, "opening IM...\n");
			foreach (string s; mtry) {
				if (s.length) XSetLocaleModifiers(s.ptr); // it's safe, as `s` is string literal
				if ((xim = XOpenIM(display, null, null, null)) !is null) return;
			}
			fprintf(stderr, "createXIM: XOpenIM failed!\n");
		}

		// for X11 we will keep all XShm-allocated images in this list, so we can free 'em on connection closing.
		// we'll use glibc malloc()/free(), 'cause `unregisterImage()` can be called from object dtor.
		static struct ImgList {
			size_t img; // class; hide it from GC
			ImgList* next;
		}

		static __gshared ImgList* imglist = null;
		static __gshared bool imglistLocked = false; // true: don't register and unregister images

		static void registerImage (Image img) {
			if (!imglistLocked && img !is null) {
				import core.stdc.stdlib : malloc;
				auto it = cast(ImgList*)malloc(ImgList.sizeof);
				assert(it !is null); // do proper checks
				it.img = cast(size_t)cast(void*)img;
				it.next = imglist;
				imglist = it;
				version(sdpy_debug_xshm) { import core.stdc.stdio : printf; printf("registering image %p\n", cast(void*)img); }
			}
		}

		static void unregisterImage (Image img) {
			if (!imglistLocked && img !is null) {
				import core.stdc.stdlib : free;
				ImgList* prev = null;
				ImgList* cur = imglist;
				while (cur !is null) {
					if (cur.img == cast(size_t)cast(void*)img) break; // i found her!
					prev = cur;
					cur = cur.next;
				}
				if (cur !is null) {
					if (prev is null) imglist = cur.next; else prev.next = cur.next;
					free(cur);
					version(sdpy_debug_xshm) { import core.stdc.stdio : printf; printf("unregistering image %p\n", cast(void*)img); }
				} else {
					version(sdpy_debug_xshm) { import core.stdc.stdio : printf; printf("trying to unregister unknown image %p\n", cast(void*)img); }
				}
			}
		}

		static void freeImages () { // needed for discardAndRecreate
			imglistLocked = true;
			scope(exit) imglistLocked = false;
			ImgList* cur = imglist;
			ImgList* next = null;
			while (cur !is null) {
				import core.stdc.stdlib : free;
				next = cur.next;
				version(sdpy_debug_xshm) { import core.stdc.stdio : printf; printf("disposing image %p\n", cast(void*)cur.img); }
				(cast(Image)cast(void*)cur.img).dispose();
				free(cur);
				cur = next;
			}
			imglist = null;
		}

		/// can be used to override normal handling of display name
		/// from environment and/or command line
		static setDisplayName(string newDisplayName) {
			displayName = cast(char*) (newDisplayName ~ '\0');
		}

		/// resets to the default display string
		static resetDisplayName() {
			displayName = null;
		}

		///
		static Display* get() {
			if(display is null) {
				if(!librariesSuccessfullyLoaded)
					throw new Exception("Unable to load X11 client libraries");
				display = XOpenDisplay(displayName);

				isLocal_ = false;

				connectionSequence_++;
				if(display is null)
					throw new Exception("Unable to open X display");

				auto str = display.display_name;
				// this is a bit of a hack but like if it looks like a unix socket we assume it is local
				// and otherwise it probably isn't
				if(str is null || (str[0] != ':' && str[0] != '/'))
					isLocal_ = false;
				else
					isLocal_ = true;

				//XSetErrorHandler(&adrlogger);
				//XSynchronize(display, true);


				XSetIOErrorHandler(&x11ioerrCB);
				Bool sup;
				XkbSetDetectableAutoRepeat(display, 1, &sup); // so we will not receive KeyRelease until key is really released
				createXIM();
				version(with_eventloop) {
					import arsd.eventloop;
					addFileEventListeners(display.fd, &eventListener, null, null);
				}
			}

			return display;
		}

		extern(C)
		static int x11ioerrCB(Display* dpy) {
			throw new XDisconnectException(false);
		}

		version(with_eventloop) {
			import arsd.eventloop;
			static void eventListener(OsFileHandle fd) {
				//this.mtLock();
				//scope(exit) this.mtUnlock();
				while(XPending(display))
					doXNextEvent(display);
			}
		}

		// close connection on program exit -- we need this to properly free all images
		static ~this () {
			// the gui thread must clean up after itself or else Xlib might deadlock
			// using this flag on any thread destruction is the easiest way i know of
			// (shared static this is run by the LAST thread to exit, which may not be
			// the gui thread, and normal static this run by ALL threads, so we gotta check.)
			if(thisIsGuiThread)
				close();
		}

		///
		static void close() {
			if(display is null)
				return;

			version(with_eventloop) {
				import arsd.eventloop;
				removeFileEventListeners(display.fd);
			}

			// now remove all registered images to prevent shared memory leaks
			freeImages();

			// tbh I don't know why it is doing this but like if this happens to run
			// from the other thread there's frequent hanging inside here.
			if(thisIsGuiThread)
				XCloseDisplay(display);
			display = null;
		}
	}

	mixin template NativeImageImplementation() {
		XImage* handle;
		ubyte* rawData;

		XShmSegmentInfo shminfo;

		__gshared bool xshmQueryCompleted;
		__gshared bool _xshmAvailable;
		public static @property bool xshmAvailable() {
			if(!xshmQueryCompleted) {
				int i1, i2, i3;
				xshmQueryCompleted = true;

				if(!XDisplayConnection.isLocal)
					_xshmAvailable = false;
				else
					_xshmAvailable = XQueryExtension(XDisplayConnection.get(), "MIT-SHM", &i1, &i2, &i3) != 0;
			}
			return _xshmAvailable;
		}

		bool usingXshm;
	final:

		private __gshared bool xshmfailed;

		void createImage(int width, int height, bool forcexshm=false, bool enableAlpha = false) {
			auto display = XDisplayConnection.get();
			assert(display !is null);
			auto screen = DefaultScreen(display);

			// it will only use shared memory for somewhat largish images,
			// since otherwise we risk wasting shared memory handles on a lot of little ones
			if (xshmAvailable && (forcexshm || (width > 100 && height > 100))) {


				// it is possible for the query extension to return true, the DISPLAY check to pass, yet
				// the actual use still fails. For example, if the program is in a container and permission denied
				// on shared memory, or if it is a local thing forwarded to a remote server, etc.
				//
				// If it does fail, we need to detect it now, abort the xshm and fall back to core protocol.


				// synchronize so preexisting buffers are clear
				XSync(display, false);
				xshmfailed = false;

				auto oldErrorHandler = XSetErrorHandler(&XShmErrorHandler);


				usingXshm = true;
				handle = XShmCreateImage(
					display,
					DefaultVisual(display, screen),
					enableAlpha ? 32: 24,
					ImageFormat.ZPixmap,
					null,
					&shminfo,
					width, height);
				if(handle is null)
					goto abortXshm1;

				if(handle.bytes_per_line != 4 * width)
					goto abortXshm2;

				shminfo.shmid = shmget(IPC_PRIVATE, handle.bytes_per_line * height, IPC_CREAT | 511 /* 0777 */);
				if(shminfo.shmid < 0)
					goto abortXshm3;
				handle.data = shminfo.shmaddr = rawData = cast(ubyte*) shmat(shminfo.shmid, null, 0);
				if(rawData == cast(ubyte*) -1)
					goto abortXshm4;
				shminfo.readOnly = 0;
				XShmAttach(display, &shminfo);

				// and now to the final error check to ensure it actually worked.
				XSync(display, false);
				if(xshmfailed)
					goto abortXshm5;

				XSetErrorHandler(oldErrorHandler);

				XDisplayConnection.registerImage(this);
				// if I don't flush here there's a chance the dtor will run before the
				// ctor and lead to a bad value X error. While this hurts the efficiency
				// it is local anyway so prolly better to keep it simple
				XFlush(display);

				return;

				abortXshm5:
					shmdt(shminfo.shmaddr);
					rawData = null;

				abortXshm4:
					shmctl(shminfo.shmid, IPC_RMID, null);

				abortXshm3:
					// nothing needed, the shmget failed so there's nothing to free

				abortXshm2:
					XDestroyImage(handle);
					handle = null;

				abortXshm1:
					XSetErrorHandler(oldErrorHandler);
					usingXshm = false;
					handle = null;

					shminfo = typeof(shminfo).init;

					_xshmAvailable = false; // don't try again in the future

					//import std.stdio; writeln("fallingback");

					goto fallback;

			} else {
				fallback:

				if (forcexshm) throw new Exception("can't create XShm Image");
				// This actually needs to be malloc to avoid a double free error when XDestroyImage is called
				import core.stdc.stdlib : malloc;
				rawData = cast(ubyte*) malloc(width * height * 4);

				handle = XCreateImage(
					display,
					DefaultVisual(display, screen),
					enableAlpha ? 32 : 24, // bpp
					ImageFormat.ZPixmap,
					0, // offset
					rawData,
					width, height,
					enableAlpha ? 32 : 8 /* FIXME */, 4 * width); // padding, bytes per line
			}
		}

		void dispose() {
			// note: this calls free(rawData) for us
			if(handle) {
				if (usingXshm) {
					XDisplayConnection.unregisterImage(this);
					if (XDisplayConnection.get()) XShmDetach(XDisplayConnection.get(), &shminfo);
				}
				XDestroyImage(handle);
				if(usingXshm) {
					shmdt(shminfo.shmaddr);
					shmctl(shminfo.shmid, IPC_RMID, null);
				}
				handle = null;
			}
		}

		Color getPixel(int x, int y) {
			auto offset = (y * width + x) * 4;
			Color c;
			c.a = enableAlpha ? rawData[offset + 3] : 255;
			c.b = rawData[offset + 0];
			c.g = rawData[offset + 1];
			c.r = rawData[offset + 2];
			if(enableAlpha)
				c.unPremultiply;
			return c;
		}

		void setPixel(int x, int y, Color c) {
			if(enableAlpha)
				c.premultiply();
			auto offset = (y * width + x) * 4;
			rawData[offset + 0] = c.b;
			rawData[offset + 1] = c.g;
			rawData[offset + 2] = c.r;
			if(enableAlpha)
				rawData[offset + 3] = c.a;
		}

		void convertToRgbaBytes(ubyte[] where) {
			assert(where.length == this.width * this.height * 4);

			// if rawData had a length....
			//assert(rawData.length == where.length);
			for(int idx = 0; idx < where.length; idx += 4) {
				where[idx + 0] = rawData[idx + 2]; // r
				where[idx + 1] = rawData[idx + 1]; // g
				where[idx + 2] = rawData[idx + 0]; // b
				where[idx + 3] = enableAlpha ? rawData[idx + 3] : 255; // a

				if(enableAlpha)
					unPremultiplyRgba(where[idx .. idx + 4]);
			}
		}

		void setFromRgbaBytes(in ubyte[] where) {
			assert(where.length == this.width * this.height * 4);

			// if rawData had a length....
			//assert(rawData.length == where.length);
			for(int idx = 0; idx < where.length; idx += 4) {
				rawData[idx + 2] = where[idx + 0]; // r
				rawData[idx + 1] = where[idx + 1]; // g
				rawData[idx + 0] = where[idx + 2]; // b
				if(enableAlpha) {
					rawData[idx + 3] = where[idx + 3]; // a
					premultiplyBgra(rawData[idx .. idx + 4]);
				}
			}
		}

	}

	mixin template NativeSimpleWindowImplementation() {
		GC gc;
		Window window;
		Display* display;

		Pixmap buffer;
		int bufferw, bufferh; // size of the buffer; can be bigger than window
		XIC xic; // input context
		int curHidden = 0; // counter
		Cursor blankCurPtr = 0;
		int cursorSequenceNumber = 0;
		int warpEventCount = 0; // number of mouse movement events to eat

		__gshared X11SetSelectionHandler[Atom] setSelectionHandlers;
		X11GetSelectionHandler[Atom] getSelectionHandlers;

		version(without_opengl) {} else
		GLXContext glc;

		private void fixFixedSize(bool forced=false) (int width, int height) {
			if (forced || this.resizability == Resizability.fixedSize) {
				//{ import core.stdc.stdio; printf("fixing size to: %dx%d\n", width, height); }
				XSizeHints sh;
				static if (!forced) {
					c_long spr;
					XGetWMNormalHints(display, window, &sh, &spr);
					sh.flags |= PMaxSize | PMinSize;
				} else {
					sh.flags = PMaxSize | PMinSize;
				}
				sh.min_width = width;
				sh.min_height = height;
				sh.max_width = width;
				sh.max_height = height;
				XSetWMNormalHints(display, window, &sh);
				//XFlush(display);
			}
		}

		ScreenPainter getPainter() {
			return ScreenPainter(this, window);
		}

		void move(int x, int y) {
			XMoveWindow(display, window, x, y);
		}

		void resize(int w, int h) {
			if (w < 1) w = 1;
			if (h < 1) h = 1;
			XResizeWindow(display, window, w, h);

			// calling this now to avoid waiting for the server to
			// acknowledge the resize; draws without returning to the
			// event loop will thus actually work. the server's event
			// btw might overrule this and resize it again
			recordX11Resize(display, this, w, h);

			// FIXME: do we need to set this as the opengl context to do the glViewport change?
			version(without_opengl) {} else if (openglMode == OpenGlOptions.yes) glViewport(0, 0, w, h);
		}

		void moveResize (int x, int y, int w, int h) {
			if (w < 1) w = 1;
			if (h < 1) h = 1;
			XMoveResizeWindow(display, window, x, y, w, h);
			version(without_opengl) {} else if (openglMode == OpenGlOptions.yes) glViewport(0, 0, w, h);
		}

		void hideCursor () {
			if (curHidden++ == 0) {
				if (!blankCurPtr || cursorSequenceNumber != XDisplayConnection.connectionSequenceNumber) {
					static const(char)[1] cmbmp = 0;
					XColor blackcolor = { 0, 0, 0, 0, 0, 0 };
					Pixmap pm = XCreateBitmapFromData(display, window, cmbmp.ptr, 1, 1);
					blankCurPtr = XCreatePixmapCursor(display, pm, pm, &blackcolor, &blackcolor, 0, 0);
					cursorSequenceNumber = XDisplayConnection.connectionSequenceNumber;
					XFreePixmap(display, pm);
				}
				XDefineCursor(display, window, blankCurPtr);
			}
		}

		void showCursor () {
			if (--curHidden == 0) XUndefineCursor(display, window);
		}

		void warpMouse (int x, int y) {
			// here i will send dummy "ignore next mouse motion" event,
			// 'cause `XWarpPointer()` sends synthesised mouse motion,
			// and we don't need to report it to the user (as warping is
			// used when the user needs movement deltas).
			//XClientMessageEvent xclient;
			XEvent e;
			e.xclient.type = EventType.ClientMessage;
			e.xclient.window = window;
			e.xclient.message_type = GetAtom!("_X11SDPY_INSMME_FLAG_EVENT_", true)(display); // let's hope nobody else will use such stupid name ;-)
			e.xclient.format = 32;
			e.xclient.data.l[0] = 0;
			debug(x11sdpy_warp_debug) { import core.stdc.stdio : printf; printf("X11: sending \"INSMME\"...\n"); }
			//{ import core.stdc.stdio : printf; printf("*X11 CLIENT: w=%u; type=%u; [0]=%u\n", cast(uint)e.xclient.window, cast(uint)e.xclient.message_type, cast(uint)e.xclient.data.l[0]); }
			XSendEvent(display, window, false, EventMask.NoEventMask, /*cast(XEvent*)&xclient*/&e);
			// now warp pointer...
			debug(x11sdpy_warp_debug) { import core.stdc.stdio : printf; printf("X11: sending \"warp\"...\n"); }
			XWarpPointer(display, None, window, 0, 0, 0, 0, x, y);
			// ...and flush
			debug(x11sdpy_warp_debug) { import core.stdc.stdio : printf; printf("X11: flushing...\n"); }
			XFlush(display);
		}

		void sendDummyEvent () {
			// here i will send dummy event to ping event queue
			XEvent e;
			e.xclient.type = EventType.ClientMessage;
			e.xclient.window = window;
			e.xclient.message_type = GetAtom!("_X11SDPY_DUMMY_EVENT_", true)(display); // let's hope nobody else will use such stupid name ;-)
			e.xclient.format = 32;
			e.xclient.data.l[0] = 0;
			XSendEvent(display, window, false, EventMask.NoEventMask, /*cast(XEvent*)&xclient*/&e);
			XFlush(display);
		}

		void setTitle(string title) {
			if (title.ptr is null) title = "";
			auto XA_UTF8 = XInternAtom(display, "UTF8_STRING".ptr, false);
			auto XA_NETWM_NAME = XInternAtom(display, "_NET_WM_NAME".ptr, false);
			XTextProperty windowName;
			windowName.value = title.ptr;
			windowName.encoding = XA_UTF8; //XA_STRING;
			windowName.format = 8;
			windowName.nitems = cast(uint)title.length;
			XSetWMName(display, window, &windowName);
			char[1024] namebuf = 0;
			auto maxlen = namebuf.length-1;
			if (maxlen > title.length) maxlen = title.length;
			namebuf[0..maxlen] = title[0..maxlen];
			XStoreName(display, window, namebuf.ptr);
			XChangeProperty(display, window, XA_NETWM_NAME, XA_UTF8, 8, PropModeReplace, title.ptr, cast(uint)title.length);
			flushGui(); // without this OpenGL windows has a LONG delay before changing title
		}

		string[] getTitles() {
			auto XA_UTF8 = XInternAtom(display, "UTF8_STRING".ptr, false);
			auto XA_NETWM_NAME = XInternAtom(display, "_NET_WM_NAME".ptr, false);
			XTextProperty textProp;
			if (XGetTextProperty(display, window, &textProp, XA_NETWM_NAME) != 0 || XGetWMName(display, window, &textProp) != 0) {
				if ((textProp.encoding == XA_UTF8 || textProp.encoding == XA_STRING) && textProp.format == 8) {
					return textProp.value[0 .. textProp.nitems].idup.split('\0');
				} else
					return [];
			} else
				return null;
		}

		string getTitle() {
			auto titles = getTitles();
			return titles.length ? titles[0] : null;
		}

		void setMinSize (int minwidth, int minheight) {
			import core.stdc.config : c_long;
			if (minwidth < 1) minwidth = 1;
			if (minheight < 1) minheight = 1;
			XSizeHints sh;
			c_long spr;
			XGetWMNormalHints(display, window, &sh, &spr);
			sh.min_width = minwidth;
			sh.min_height = minheight;
			sh.flags |= PMinSize;
			XSetWMNormalHints(display, window, &sh);
			flushGui();
		}

		void setMaxSize (int maxwidth, int maxheight) {
			import core.stdc.config : c_long;
			if (maxwidth < 1) maxwidth = 1;
			if (maxheight < 1) maxheight = 1;
			XSizeHints sh;
			c_long spr;
			XGetWMNormalHints(display, window, &sh, &spr);
			sh.max_width = maxwidth;
			sh.max_height = maxheight;
			sh.flags |= PMaxSize;
			XSetWMNormalHints(display, window, &sh);
			flushGui();
		}

		void setResizeGranularity (int granx, int grany) {
			import core.stdc.config : c_long;
			if (granx < 1) granx = 1;
			if (grany < 1) grany = 1;
			XSizeHints sh;
			c_long spr;
			XGetWMNormalHints(display, window, &sh, &spr);
			sh.width_inc = granx;
			sh.height_inc = grany;
			sh.flags |= PResizeInc;
			XSetWMNormalHints(display, window, &sh);
			flushGui();
		}

		void setOpacity (uint opacity) {
			arch_ulong o = opacity;
			if (opacity == uint.max)
				XDeleteProperty(display, window, XInternAtom(display, "_NET_WM_WINDOW_OPACITY".ptr, false));
			else
				XChangeProperty(display, window, XInternAtom(display, "_NET_WM_WINDOW_OPACITY".ptr, false),
					XA_CARDINAL, 32, PropModeReplace, &o, 1);
		}

		void createWindow(int width, int height, string title, in OpenGlOptions opengl, SimpleWindow parent) {
			version(without_opengl) {} else if(opengl == OpenGlOptions.yes && !openGlLibrariesSuccessfullyLoaded) throw new Exception("OpenGL libraries did not load");
			display = XDisplayConnection.get();
			auto screen = DefaultScreen(display);

			version(without_opengl) {}
			else {
				if(opengl == OpenGlOptions.yes) {
					GLXFBConfig fbconf = null;
					XVisualInfo* vi = null;
					bool useLegacy = false;
					static if (SdpyIsUsingIVGLBinds) {if (glbindGetProcAddress("glHint") is null) assert(0, "GL: error loading OpenGL"); } // loads all necessary functions
					if (sdpyOpenGLContextVersion != 0 && glXCreateContextAttribsARB_present()) {
						int[23] visualAttribs = [
							GLX_X_RENDERABLE , 1/*True*/,
							GLX_DRAWABLE_TYPE, GLX_WINDOW_BIT,
							GLX_RENDER_TYPE  , GLX_RGBA_BIT,
							GLX_X_VISUAL_TYPE, GLX_TRUE_COLOR,
							GLX_RED_SIZE     , 8,
							GLX_GREEN_SIZE   , 8,
							GLX_BLUE_SIZE    , 8,
							GLX_ALPHA_SIZE   , 8,
							GLX_DEPTH_SIZE   , 24,
							GLX_STENCIL_SIZE , 8,
							GLX_DOUBLEBUFFER , 1/*True*/,
							0/*None*/,
						];
						int fbcount;
						GLXFBConfig* fbc = glXChooseFBConfig(display, screen, visualAttribs.ptr, &fbcount);
						if (fbcount == 0) {
							useLegacy = true; // try to do at least something
						} else {
							// pick the FB config/visual with the most samples per pixel
							int bestidx = -1, bestns = -1;
							foreach (int fbi; 0..fbcount) {
								int sb, samples;
								glXGetFBConfigAttrib(display, fbc[fbi], GLX_SAMPLE_BUFFERS, &sb);
								glXGetFBConfigAttrib(display, fbc[fbi], GLX_SAMPLES, &samples);
								if (bestidx < 0 || sb && samples > bestns) { bestidx = fbi; bestns = samples; }
							}
							//{ import core.stdc.stdio; printf("found gl visual with %d samples\n", bestns); }
							fbconf = fbc[bestidx];
							// Be sure to free the FBConfig list allocated by glXChooseFBConfig()
							XFree(fbc);
							vi = cast(XVisualInfo*)glXGetVisualFromFBConfig(display, fbconf);
						}
					}
					if (vi is null || useLegacy) {
						static immutable GLint[5] attrs = [ GLX_RGBA, GLX_DEPTH_SIZE, 24, GLX_DOUBLEBUFFER, None ];
						vi = cast(XVisualInfo*)glXChooseVisual(display, 0, attrs.ptr);
						useLegacy = true;
					}
					if (vi is null) throw new Exception("no open gl visual found");

					XSetWindowAttributes swa;
					auto root = RootWindow(display, screen);
					swa.colormap = XCreateColormap(display, root, vi.visual, AllocNone);

					window = XCreateWindow(display, (windowType != WindowTypes.nestedChild || parent is null) ? root : parent.impl.window,
						0, 0, width, height,
						0, vi.depth, 1 /* InputOutput */, vi.visual, CWColormap, &swa);

					// now try to use `glXCreateContextAttribsARB()` if it's here
					if (!useLegacy) {
						// request fairly advanced context, even with stencil buffer!
						int[9] contextAttribs = [
							GLX_CONTEXT_MAJOR_VERSION_ARB, (sdpyOpenGLContextVersion>>8),
							GLX_CONTEXT_MINOR_VERSION_ARB, (sdpyOpenGLContextVersion&0xff),
							/*GLX_CONTEXT_PROFILE_MASK_ARB*/0x9126, (sdpyOpenGLContextCompatible ? /*GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB*/0x02 : /*GLX_CONTEXT_CORE_PROFILE_BIT_ARB*/ 0x01),
							// for modern context, set "forward compatibility" flag too
							(sdpyOpenGLContextCompatible ? None : /*GLX_CONTEXT_FLAGS_ARB*/ 0x2094), /*GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB*/ 0x02,
							0/*None*/,
						];
						glc = glXCreateContextAttribsARB(display, fbconf, null, 1/*True*/, contextAttribs.ptr);
						if (glc is null && sdpyOpenGLContextAllowFallback) {
							sdpyOpenGLContextVersion = 0;
							glc = glXCreateContext(display, vi, null, /*GL_TRUE*/1);
						}
						//{ import core.stdc.stdio; printf("using modern ogl v%d.%d\n", contextAttribs[1], contextAttribs[3]); }
					} else {
						// fallback to old GLX call
						if (sdpyOpenGLContextAllowFallback || sdpyOpenGLContextVersion == 0) {
							sdpyOpenGLContextVersion = 0;
							glc = glXCreateContext(display, vi, null, /*GL_TRUE*/1);
						}
					}
					// sync to ensure any errors generated are processed
					XSync(display, 0/*False*/);
					//{ import core.stdc.stdio; printf("ogl is here\n"); }
					if(glc is null)
						throw new Exception("glc");
				}
			}

			if(opengl == OpenGlOptions.no) {

				bool overrideRedirect = false;
				if(windowType == WindowTypes.dropdownMenu || windowType == WindowTypes.popupMenu || windowType == WindowTypes.notification)
					overrideRedirect = true;

				XSetWindowAttributes swa;
				swa.background_pixel = WhitePixel(display, screen);
				swa.border_pixel = BlackPixel(display, screen);
				swa.override_redirect = overrideRedirect;
				auto root = RootWindow(display, screen);
				swa.colormap = XCreateColormap(display, root, DefaultVisual(display, screen), AllocNone);

				window = XCreateWindow(display, (windowType != WindowTypes.nestedChild || parent is null) ? root : parent.impl.window,
					0, 0, width, height,
					0, CopyFromParent, 1 /* InputOutput */, cast(Visual*) CopyFromParent, CWColormap | CWBackPixel | CWBorderPixel | CWOverrideRedirect, &swa);



				/*
				window = XCreateSimpleWindow(
					display,
					parent is null ? RootWindow(display, screen) : parent.impl.window,
					0, 0, // x, y
					width, height,
					1, // border width
					BlackPixel(display, screen), // border
					WhitePixel(display, screen)); // background
				*/

				buffer = XCreatePixmap(display, cast(Drawable) window, width, height, DefaultDepthOfDisplay(display));
				bufferw = width;
				bufferh = height;

				gc = DefaultGC(display, screen);

				// clear out the buffer to get us started...
				XSetForeground(display, gc, WhitePixel(display, screen));
				XFillRectangle(display, cast(Drawable) buffer, gc, 0, 0, width, height);
				XSetForeground(display, gc, BlackPixel(display, screen));
			}

			// input context
			//TODO: create this only for top-level windows, and reuse that?
			if (XDisplayConnection.xim !is null) {
				xic = XCreateIC(XDisplayConnection.xim,
						/*XNInputStyle*/"inputStyle".ptr, XIMPreeditNothing|XIMStatusNothing,
						/*XNClientWindow*/"clientWindow".ptr, window,
						/*XNFocusWindow*/"focusWindow".ptr, window,
						null);
				if (xic is null) {
					import core.stdc.stdio : stderr, fprintf;
					fprintf(stderr, "XCreateIC failed for window %u\n", cast(uint)window);
				}
			}

			if (sdpyWindowClassStr is null) loadBinNameToWindowClassName();
			if (sdpyWindowClassStr is null) sdpyWindowClass = "DSimpleWindow";
			// window class
			if (sdpyWindowClassStr !is null && sdpyWindowClassStr[0]) {
				//{ import core.stdc.stdio; printf("winclass: [%s]\n", sdpyWindowClassStr); }
				XClassHint klass;
				XWMHints wh;
				XSizeHints size;
				klass.res_name = sdpyWindowClassStr;
				klass.res_class = sdpyWindowClassStr;
				XSetWMProperties(display, window, null, null, null, 0, &size, &wh, &klass);
			}

			setTitle(title);
			SimpleWindow.nativeMapping[window] = this;
			CapableOfHandlingNativeEvent.nativeHandleMapping[window] = this;

			// This gives our window a close button
			if (windowType != WindowTypes.eventOnly) {
				// FIXME: actually implement the WM_TAKE_FOCUS correctly
				//Atom[2] atoms = [GetAtom!"WM_DELETE_WINDOW"(display), GetAtom!"WM_TAKE_FOCUS"(display)];
				Atom[1] atoms = [GetAtom!"WM_DELETE_WINDOW"(display)];
				XSetWMProtocols(display, window, atoms.ptr, cast(int) atoms.length);
			}

			// FIXME: windowType and customizationFlags
			Atom[8] wsatoms; // here, due to goto
			int wmsacount = 0; // here, due to goto

			try
			final switch(windowType) {
				case WindowTypes.normal:
					setNetWMWindowType(GetAtom!"_NET_WM_WINDOW_TYPE_NORMAL"(display));
				break;
				case WindowTypes.undecorated:
					motifHideDecorations();
					setNetWMWindowType(GetAtom!"_NET_WM_WINDOW_TYPE_NORMAL"(display));
				break;
				case WindowTypes.eventOnly:
					_hidden = true;
					XSelectInput(display, window, EventMask.StructureNotifyMask); // without this, we won't get destroy notification
					goto hiddenWindow;
				//break;
				case WindowTypes.nestedChild:
					// handled in XCreateWindow calls
				break;

				case WindowTypes.dropdownMenu:
					motifHideDecorations();
					setNetWMWindowType(GetAtom!"_NET_WM_WINDOW_TYPE_DROPDOWN_MENU"(display));
					customizationFlags |= WindowFlags.skipTaskbar | WindowFlags.alwaysOnTop;
				break;
				case WindowTypes.popupMenu:
					motifHideDecorations();
					setNetWMWindowType(GetAtom!"_NET_WM_WINDOW_TYPE_POPUP_MENU"(display));
					customizationFlags |= WindowFlags.skipTaskbar | WindowFlags.alwaysOnTop;
				break;
				case WindowTypes.notification:
					motifHideDecorations();
					setNetWMWindowType(GetAtom!"_NET_WM_WINDOW_TYPE_NOTIFICATION"(display));
					customizationFlags |= WindowFlags.skipTaskbar | WindowFlags.alwaysOnTop;
				break;
				/+
				case WindowTypes.menu:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_MENU"(display);
					motifHideDecorations();
				break;
				case WindowTypes.desktop:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_DESKTOP"(display);
				break;
				case WindowTypes.dock:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_DOCK"(display);
				break;
				case WindowTypes.toolbar:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_TOOLBAR"(display);
				break;
				case WindowTypes.menu:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_MENU"(display);
				break;
				case WindowTypes.utility:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_UTILITY"(display);
				break;
				case WindowTypes.splash:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_SPLASH"(display);
				break;
				case WindowTypes.dialog:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_DIALOG"(display);
				break;
				case WindowTypes.tooltip:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_TOOLTIP"(display);
				break;
				case WindowTypes.notification:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_NOTIFICATION"(display);
				break;
				case WindowTypes.combo:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_COMBO"(display);
				break;
				case WindowTypes.dnd:
					atoms[0] = GetAtom!"_NET_WM_WINDOW_TYPE_DND"(display);
				break;
				+/
			}
			catch(Exception e) {
				// XInternAtom failed, prolly a WM
				// that doesn't support these things
			}

			if (customizationFlags&WindowFlags.skipTaskbar) wsatoms[wmsacount++] = GetAtom!("_NET_WM_STATE_SKIP_TASKBAR", true)(display);
			// the two following flags may be ignored by WM
			if (customizationFlags&WindowFlags.alwaysOnTop) wsatoms[wmsacount++] = GetAtom!("_NET_WM_STATE_ABOVE", true)(display);
			if (customizationFlags&WindowFlags.alwaysOnBottom) wsatoms[wmsacount++] = GetAtom!("_NET_WM_STATE_BELOW", true)(display);

			if (wmsacount != 0) XChangeProperty(display, window, GetAtom!("_NET_WM_STATE", true)(display), XA_ATOM, 32 /* bits */,0 /*PropModeReplace*/, wsatoms.ptr, wmsacount);

			if (this.resizability == Resizability.fixedSize || (opengl == OpenGlOptions.no && this.resizability != Resizability.allowResizing)) fixFixedSize!true(width, height);

			// What would be ideal here is if they only were
			// selected if there was actually an event handler
			// for them...

			selectDefaultInput((customizationFlags & WindowFlags.alwaysRequestMouseMotionEvents)?true:false);

			hiddenWindow:

			// set the pid property for lookup later by window managers
			// a standard convenience
			import core.sys.posix.unistd;
			arch_ulong pid = getpid();

			XChangeProperty(
				display,
				impl.window,
				GetAtom!("_NET_WM_PID", true)(display),
				XA_CARDINAL,
				32 /* bits */,
				0 /*PropModeReplace*/,
				&pid,
				1);

			if(isTransient && parent) { // customizationFlags & WindowFlags.transient) {
				if(parent is null) assert(0);
				XChangeProperty(
					display,
					impl.window,
					GetAtom!("WM_TRANSIENT_FOR", true)(display),
					XA_WINDOW,
					32 /* bits */,
					0 /*PropModeReplace*/,
					&parent.impl.window,
					1);

			}

			if(windowType != WindowTypes.eventOnly && (customizationFlags&WindowFlags.dontAutoShow) == 0) {
				XMapWindow(display, window);
			} else {
				_hidden = true;
			}
		}

		void selectDefaultInput(bool forceIncludeMouseMotion) {
			auto mask = EventMask.ExposureMask |
				EventMask.KeyPressMask |
				EventMask.KeyReleaseMask |
				EventMask.PropertyChangeMask |
				EventMask.FocusChangeMask |
				EventMask.StructureNotifyMask |
				EventMask.VisibilityChangeMask
				| EventMask.ButtonPressMask
				| EventMask.ButtonReleaseMask
			;

			// xshm is our shortcut for local connections
			if(XDisplayConnection.isLocal || forceIncludeMouseMotion)
				mask |= EventMask.PointerMotionMask;
			else
				mask |= EventMask.ButtonMotionMask;

			XSelectInput(display, window, mask);
		}


		void setNetWMWindowType(Atom type) {
			Atom[2] atoms;

			atoms[0] = type;
			// generic fallback
			atoms[1] = GetAtom!"_NET_WM_WINDOW_TYPE_NORMAL"(display);

			XChangeProperty(
				display,
				impl.window,
				GetAtom!"_NET_WM_WINDOW_TYPE"(display),
				XA_ATOM,
				32 /* bits */,
				0 /*PropModeReplace*/,
				atoms.ptr,
				cast(int) atoms.length);
		}

		void motifHideDecorations() {
			MwmHints hints;
			hints.flags = MWM_HINTS_DECORATIONS;

			XChangeProperty(
				display,
				impl.window,
				GetAtom!"_MOTIF_WM_HINTS"(display),
				GetAtom!"_MOTIF_WM_HINTS"(display),
				32 /* bits */,
				0 /*PropModeReplace*/,
				&hints,
				hints.sizeof / 4);
		}

		/*k8: unused
		void createOpenGlContext() {

		}
		*/

		void closeWindow() {
			// I can't close this or a child window closing will
			// break events for everyone. So I'm just leaking it right
			// now and that is probably perfectly fine...
			version(none)
			if (customEventFDRead != -1) {
				import core.sys.posix.unistd : close;
				auto same = customEventFDRead == customEventFDWrite;

				close(customEventFDRead);
				if(!same)
					close(customEventFDWrite);
				customEventFDRead = -1;
				customEventFDWrite = -1;
			}
			if(buffer)
				XFreePixmap(display, buffer);
			bufferw = bufferh = 0;
			if (blankCurPtr && cursorSequenceNumber == XDisplayConnection.connectionSequenceNumber) XFreeCursor(display, blankCurPtr);
			XDestroyWindow(display, window);
			XFlush(display);
		}

		void dispose() {
		}

		bool destroyed = false;
	}

	bool insideXEventLoop;
}

version(X11) {

	int mouseDoubleClickTimeout = 350; /// Double click timeout. X only, you probably shouldn't change this.

	void recordX11Resize(Display* display, SimpleWindow win, int width, int height) {
		if(width != win.width || height != win.height) {
			win._width = width;
			win._height = height;

			if(win.openglMode == OpenGlOptions.no) {
				// FIXME: could this be more efficient?

				if (win.bufferw < width || win.bufferh < height) {
					//{ import core.stdc.stdio; printf("new buffer; old size: %dx%d; new size: %dx%d\n", win.bufferw, win.bufferh, cast(int)width, cast(int)height); }
					// grow the internal buffer to match the window...
					auto newPixmap = XCreatePixmap(display, cast(Drawable) win.window, width, height, DefaultDepthOfDisplay(display));
					{
						GC xgc = XCreateGC(win.display, cast(Drawable)win.window, 0, null);
						XCopyGC(win.display, win.gc, 0xffffffff, xgc);
						scope(exit) XFreeGC(win.display, xgc);
						XSetClipMask(win.display, xgc, None);
						XSetForeground(win.display, xgc, 0);
						XFillRectangle(display, cast(Drawable)newPixmap, xgc, 0, 0, width, height);
					}
					XCopyArea(display,
						cast(Drawable) win.buffer,
						cast(Drawable) newPixmap,
						win.gc, 0, 0,
						win.bufferw < width ? win.bufferw : win.width,
						win.bufferh < height ? win.bufferh : win.height,
						0, 0);

					XFreePixmap(display, win.buffer);
					win.buffer = newPixmap;
					win.bufferw = width;
					win.bufferh = height;
				}

				// clear unused parts of the buffer
				if (win.bufferw > width || win.bufferh > height) {
					GC xgc = XCreateGC(win.display, cast(Drawable)win.window, 0, null);
					XCopyGC(win.display, win.gc, 0xffffffff, xgc);
					scope(exit) XFreeGC(win.display, xgc);
					XSetClipMask(win.display, xgc, None);
					XSetForeground(win.display, xgc, 0);
					immutable int maxw = (win.bufferw > width ? win.bufferw : width);
					immutable int maxh = (win.bufferh > height ? win.bufferh : height);
					XFillRectangle(win.display, cast(Drawable)win.buffer, xgc, width, 0, maxw, maxh); // let X11 do clipping
					XFillRectangle(win.display, cast(Drawable)win.buffer, xgc, 0, height, maxw, maxh); // let X11 do clipping
				}

			}

			version(without_opengl) {} else
			if(win.openglMode == OpenGlOptions.yes && win.resizability == Resizability.automaticallyScaleIfPossible) {
				glViewport(0, 0, width, height);
			}

			win.fixFixedSize(width, height); //k8: this does nothing on my FluxBox; wtf?!

			if(win.windowResized !is null) {
				XUnlockDisplay(display);
				scope(exit) XLockDisplay(display);
				win.windowResized(width, height);
			}
		}
	}


	/// Platform-specific, you might use it when doing a custom event loop.
	bool doXNextEvent(Display* display) {
		bool done;
		XEvent e;
		XNextEvent(display, &e);
		version(sddddd) {
			import std.stdio, std.conv : to;
			if(auto win = e.xany.window in CapableOfHandlingNativeEvent.nativeHandleMapping) {
				if(typeid(cast(Object) *win) == NotificationAreaIcon.classinfo)
				writeln("event for: ", e.xany.window, "; type is ", to!string(cast(EventType)e.type));
			}
		}

		// filter out compose events
		if (XFilterEvent(&e, None)) {
			//{ import core.stdc.stdio : printf; printf("XFilterEvent filtered!\n"); }
			//NOTE: we should ungrab keyboard here, but simpledisplay doesn't use keyboard grabbing (yet)
			return false;
		}
		// process keyboard mapping changes
		if (e.type == EventType.KeymapNotify) {
			//{ import core.stdc.stdio : printf; printf("KeymapNotify processed!\n"); }
			XRefreshKeyboardMapping(&e.xmapping);
			return false;
		}

		version(with_eventloop)
			import arsd.eventloop;

		if(SimpleWindow.handleNativeGlobalEvent !is null) {
			// see windows impl's comments
			XUnlockDisplay(display);
			scope(exit) XLockDisplay(display);
			auto ret = SimpleWindow.handleNativeGlobalEvent(e);
			if(ret == 0)
				return done;
		}


		if(auto win = e.xany.window in CapableOfHandlingNativeEvent.nativeHandleMapping) {
			if(win.getNativeEventHandler !is null) {
				XUnlockDisplay(display);
				scope(exit) XLockDisplay(display);
				auto ret = win.getNativeEventHandler()(e);
				if(ret == 0)
					return done;
			}
		}

		switch(e.type) {
		  case EventType.SelectionClear:
		  	if(auto win = e.xselectionclear.window in SimpleWindow.nativeMapping) {
				// FIXME so it is supposed to finish any in progress transfers... but idk...
				//import std.stdio; writeln("SelectionClear");
				SimpleWindow.impl.setSelectionHandlers.remove(e.xselectionclear.selection);
			}
		  break;
		  case EventType.SelectionRequest:
		  	if(auto win = e.xselectionrequest.owner in SimpleWindow.nativeMapping)
			if(auto ssh = e.xselectionrequest.selection in SimpleWindow.impl.setSelectionHandlers) {
				// import std.stdio; printf("SelectionRequest %s\n", XGetAtomName(e.xselectionrequest.display, e.xselectionrequest.target));
				XUnlockDisplay(display);
				scope(exit) XLockDisplay(display);
				(*ssh).handleRequest(e);
			}
		  break;
		  case EventType.PropertyNotify:
			// import std.stdio; printf("PropertyNotify %s %d\n", XGetAtomName(e.xproperty.display, e.xproperty.atom), e.xproperty.state);

			foreach(ssh; SimpleWindow.impl.setSelectionHandlers) {
				if(ssh.matchesIncr(e.xproperty.window, e.xproperty.atom) && e.xproperty.state == PropertyNotification.PropertyDelete)
					ssh.sendMoreIncr(&e.xproperty);
			}


		  	if(auto win = e.xproperty.window in SimpleWindow.nativeMapping)
		  	if(auto handler = e.xproperty.atom in win.getSelectionHandlers) {
				if(handler.matchesIncr(e.xproperty.window, e.xproperty.atom) && e.xproperty.state == PropertyNotification.PropertyNewValue) {
					Atom target;
					int format;
					arch_ulong bytesafter, length;
					void* value;

					ubyte[] s;
					Atom targetToKeep;

					XGetWindowProperty(
						e.xproperty.display,
						e.xproperty.window,
						e.xproperty.atom,
						0,
						100000 /* length */,
						true, /* erase it to signal we got it and want more */
						0 /*AnyPropertyType*/,
						&target, &format, &length, &bytesafter, &value);

					if(!targetToKeep)
						targetToKeep = target;

					auto id = (cast(ubyte*) value)[0 .. length];

					handler.handleIncrData(targetToKeep, id);

					XFree(value);
				}
			}
		  break;
		  case EventType.SelectionNotify:
		  	if(auto win = e.xselection.requestor in SimpleWindow.nativeMapping)
		  	if(auto handler = e.xproperty.atom in win.getSelectionHandlers) {
				if(e.xselection.property == None) { // || e.xselection.property == GetAtom!("NULL", true)(e.xselection.display)) {
					XUnlockDisplay(display);
					scope(exit) XLockDisplay(display);
					handler.handleData(None, null);
				} else {
					Atom target;
					int format;
					arch_ulong bytesafter, length;
					void* value;
					XGetWindowProperty(
						e.xselection.display,
						e.xselection.requestor,
						e.xselection.property,
						0,
						100000 /* length */,
						//false, /* don't erase it */
						true, /* do erase it lol */
						0 /*AnyPropertyType*/,
						&target, &format, &length, &bytesafter, &value);

					// FIXME: I don't have to copy it now since it is in char[] instead of string

					{
						XUnlockDisplay(display);
						scope(exit) XLockDisplay(display);

						if(target == XA_ATOM) {
							// initial request, see what they are able to work with and request the best one
							// we can handle, if available

							Atom[] answer = (cast(Atom*) value)[0 .. length];
							Atom best = handler.findBestFormat(answer);

							/+
							writeln("got ", answer);
							foreach(a; answer)
								printf("%s\n", XGetAtomName(display, a));
							writeln("best ", best);
							+/

							if(best != None) {
								// actually request the best format
								XConvertSelection(e.xselection.display, e.xselection.selection, best, GetAtom!("SDD_DATA", true)(display), e.xselection.requestor, 0 /*CurrentTime*/);
							}
						} else if(target == GetAtom!"INCR"(display)) {
							// incremental

							handler.prepareIncremental(e.xselection.requestor, e.xselection.property);

							// signal the sending program that we see
							// the incr and are ready to receive more.
							XDeleteProperty(
								e.xselection.display,
								e.xselection.requestor,
								e.xselection.property);
						} else {
							// unsupported type... maybe, forward
							handler.handleData(target, cast(ubyte[]) value[0 .. length]);
						}
					}
					XFree(value);
					/*
					XDeleteProperty(
						e.xselection.display,
						e.xselection.requestor,
						e.xselection.property);
					*/
				}
			}
		  break;
		  case EventType.ConfigureNotify:
			auto event = e.xconfigure;
		 	if(auto win = event.window in SimpleWindow.nativeMapping) {
					//version(sdddd) { import std.stdio; writeln(" w=", event.width, "; h=", event.height); }

				recordX11Resize(display, *win, event.width, event.height);
			}
		  break;
		  case EventType.Expose:
		 	if(auto win = e.xexpose.window in SimpleWindow.nativeMapping) {
				// if it is closing from a popup menu, it can get
				// an Expose event right by the end and trigger a
				// BadDrawable error ... we'll just check
				// closed to handle that.
				if((*win).closed) break;
				if((*win).openglMode == OpenGlOptions.no) {
					bool doCopy = true;// e.xexpose.count == 0; // the count is better if we copy all area but meh
					if (win.handleExpose !is null) doCopy = !win.handleExpose(e.xexpose.x, e.xexpose.y, e.xexpose.width, e.xexpose.height, e.xexpose.count);
					if (doCopy) XCopyArea(display, cast(Drawable) (*win).buffer, cast(Drawable) (*win).window, (*win).gc, e.xexpose.x, e.xexpose.y, e.xexpose.width, e.xexpose.height, e.xexpose.x, e.xexpose.y);
				} else {
					// need to redraw the scene somehow
					if(e.xexpose.count == 0) { // only do the last one since redrawOpenGlSceneNow always does it all
						XUnlockDisplay(display);
						scope(exit) XLockDisplay(display);
						version(without_opengl) {} else
						win.redrawOpenGlSceneSoon();
					}
				}
			}
		  break;
		  case EventType.FocusIn:
		  case EventType.FocusOut:
		  	if(auto win = e.xfocus.window in SimpleWindow.nativeMapping) {
				if (win.xic !is null) {
					//{ import core.stdc.stdio : printf; printf("XIC focus change!\n"); }
					if (e.type == EventType.FocusIn) XSetICFocus(win.xic); else XUnsetICFocus(win.xic);
				}

				win._focused = e.type == EventType.FocusIn;

				if(win.demandingAttention)
					demandAttention(*win, false);

				if(win.onFocusChange) {
					XUnlockDisplay(display);
					scope(exit) XLockDisplay(display);
					win.onFocusChange(e.type == EventType.FocusIn);
				}
			}
		  break;
		  case EventType.VisibilityNotify:
				if(auto win = e.xfocus.window in SimpleWindow.nativeMapping) {
					if (e.xvisibility.state == VisibilityNotify.VisibilityFullyObscured) {
						if (win.visibilityChanged !is null) {
								XUnlockDisplay(display);
								scope(exit) XLockDisplay(display);
								win.visibilityChanged(false);
							}
					} else {
						if (win.visibilityChanged !is null) {
							XUnlockDisplay(display);
							scope(exit) XLockDisplay(display);
							win.visibilityChanged(true);
						}
					}
				}
				break;
		  case EventType.ClientMessage:
				if (e.xclient.message_type == GetAtom!("_X11SDPY_INSMME_FLAG_EVENT_", true)(e.xany.display)) {
					// "ignore next mouse motion" event, increment ignore counter for teh window
					if (auto win = e.xclient.window in SimpleWindow.nativeMapping) {
						++(*win).warpEventCount;
						debug(x11sdpy_warp_debug) { import core.stdc.stdio : printf; printf("X11: got \"INSMME\" message, new count=%d\n", (*win).warpEventCount); }
					} else {
						debug(x11sdpy_warp_debug) { import core.stdc.stdio : printf; printf("X11: got \"INSMME\" WTF?!!\n"); }
					}
				} else if(e.xclient.data.l[0] == GetAtom!"WM_DELETE_WINDOW"(e.xany.display)) {
					// user clicked the close button on the window manager
					if(auto win = e.xclient.window in SimpleWindow.nativeMapping) {
						XUnlockDisplay(display);
						scope(exit) XLockDisplay(display);
						if ((*win).closeQuery !is null) (*win).closeQuery(); else (*win).close();
					}

				} else if(e.xclient.data.l[0] == GetAtom!"WM_TAKE_FOCUS"(e.xany.display)) {
					import std.stdio; writeln("HAPPENED");
					// user clicked the close button on the window manager
					if(auto win = e.xclient.window in SimpleWindow.nativeMapping) {
						XUnlockDisplay(display);
						scope(exit) XLockDisplay(display);

						// FIXME: so this is actually supposed to focus to a relevant child window if appropriate
						XSetInputFocus(display, e.xclient.window, RevertToParent, e.xclient.data.l[1]);
					}
				} else if(e.xclient.message_type == GetAtom!"MANAGER"(e.xany.display)) {
					foreach(nai; NotificationAreaIcon.activeIcons)
						nai.newManager();
				} else if(auto win = e.xclient.window in SimpleWindow.nativeMapping) {

					bool xDragWindow = true;
					if(xDragWindow && e.xclient.message_type == GetAtom!"XdndStatus"(e.xany.display)) {
						//XDefineCursor(display, xDragWindow.impl.window,
							//import std.stdio; writeln("XdndStatus ", e.xclient.data.l);
					}
					if(auto dh = win.dropHandler) {

						static Atom[3] xFormatsBuffer;
						static Atom[] xFormats;

						void resetXFormats() {
							xFormatsBuffer[] = 0;
							xFormats = xFormatsBuffer[];
						}

						if(e.xclient.message_type == GetAtom!"XdndEnter"(e.xany.display)) {
							// on Windows it is supposed to return the effect you actually do FIXME

							auto sourceWindow =  e.xclient.data.l[0];

							xFormatsBuffer[0] = e.xclient.data.l[2];
							xFormatsBuffer[1] = e.xclient.data.l[3];
							xFormatsBuffer[2] = e.xclient.data.l[4];

							if(e.xclient.data.l[1] & 1) {
								// can just grab it all but like we don't necessarily need them...
								xFormats = cast(Atom[]) getX11PropertyData(sourceWindow, GetAtom!"XdndTypeList"(display), XA_ATOM);
							} else {
								int len;
								foreach(fmt; xFormatsBuffer)
									if(fmt) len++;
								xFormats = xFormatsBuffer[0 .. len];
							}

							auto pkg = DropPackage(*win, e.xclient.data.l[0], 0, xFormats);

							dh.dragEnter(&pkg);
						} else if(e.xclient.message_type == GetAtom!"XdndPosition"(e.xany.display)) {

							auto pack = e.xclient.data.l[2];

							auto result = dh.dragOver(Point((pack & 0xffff0000) >> 16, pack & 0xffff)); // FIXME: translate screen coordinates back to window coords


							XClientMessageEvent xclient;

							xclient.type = EventType.ClientMessage;
							xclient.window = e.xclient.data.l[0];
							xclient.message_type = GetAtom!"XdndStatus"(display);
							xclient.format = 32;
							xclient.data.l[0] = win.impl.window;
							xclient.data.l[1] = (result.action != DragAndDropAction.none) ? 1 : 0; // will accept
							auto r = result.consistentWithin;
							xclient.data.l[2] = ((cast(short) r.left) << 16) | (cast(short) r.top);
							xclient.data.l[3] = ((cast(short) r.width) << 16) | (cast(short) r.height);
							xclient.data.l[4] = dndActionAtom(e.xany.display, result.action);

							XSendEvent(
								display,
								e.xclient.data.l[0],
								false,
								EventMask.NoEventMask,
								cast(XEvent*) &xclient
							);


						} else if(e.xclient.message_type == GetAtom!"XdndLeave"(e.xany.display)) {
							//import std.stdio; writeln("XdndLeave");
							// drop cancelled.
							// data.l[0] is the source window
							dh.dragLeave();

							resetXFormats();
						} else if(e.xclient.message_type == GetAtom!"XdndDrop"(e.xany.display)) {
							// drop happening, should fetch data, then send finished
							//import std.stdio; writeln("XdndDrop");

							auto pkg = DropPackage(*win, e.xclient.data.l[0], e.xclient.data.l[2], xFormats);

							dh.drop(&pkg);

							resetXFormats();
						} else if(e.xclient.message_type == GetAtom!"XdndFinished"(e.xany.display)) {
							// import std.stdio; writeln("XdndFinished");

							dh.finish();
						}

					}
				}
		  break;
		  case EventType.MapNotify:
				if(auto win = e.xmap.window in SimpleWindow.nativeMapping) {
					(*win)._visible = true;
					if (!(*win)._visibleForTheFirstTimeCalled) {
						(*win)._visibleForTheFirstTimeCalled = true;
						if ((*win).visibleForTheFirstTime !is null) {
							XUnlockDisplay(display);
							scope(exit) XLockDisplay(display);
							version(without_opengl) {} else {
								if((*win).openglMode == OpenGlOptions.yes) {
									(*win).setAsCurrentOpenGlContextNT();
									glViewport(0, 0, (*win).width, (*win).height);
								}
							}
							(*win).visibleForTheFirstTime();
						}
					}
					if ((*win).visibilityChanged !is null) {
						XUnlockDisplay(display);
						scope(exit) XLockDisplay(display);
						(*win).visibilityChanged(true);
					}
				}
		  break;
		  case EventType.UnmapNotify:
				if(auto win = e.xunmap.window in SimpleWindow.nativeMapping) {
					win._visible = false;
					if (win.visibilityChanged !is null) {
						XUnlockDisplay(display);
						scope(exit) XLockDisplay(display);
						win.visibilityChanged(false);
					}
			}
		  break;
		  case EventType.DestroyNotify:
			if(auto win = e.xdestroywindow.window in SimpleWindow.nativeMapping) {
				if (win.onDestroyed !is null) try { win.onDestroyed(); } catch (Exception e) {} // sorry
				win._closed = true; // just in case
				win.destroyed = true;
				if (win.xic !is null) {
					XDestroyIC(win.xic);
					win.xic = null; // just in calse
				}
				SimpleWindow.nativeMapping.remove(e.xdestroywindow.window);
				bool anyImportant = false;
				foreach(SimpleWindow w; SimpleWindow.nativeMapping)
					if(w.beingOpenKeepsAppOpen) {
						anyImportant = true;
						break;
					}
				if(!anyImportant)
					done = true;
			}
			auto window = e.xdestroywindow.window;
			if(window in CapableOfHandlingNativeEvent.nativeHandleMapping)
				CapableOfHandlingNativeEvent.nativeHandleMapping.remove(window);

			version(with_eventloop) {
				if(done) exit();
			}
		  break;

		  case EventType.MotionNotify:
			MouseEvent mouse;
			auto event = e.xmotion;

			mouse.type = MouseEventType.motion;
			mouse.x = event.x;
			mouse.y = event.y;
			mouse.modifierState = event.state;

			mouse.timestamp = event.time;

			if(auto win = e.xmotion.window in SimpleWindow.nativeMapping) {
				mouse.window = *win;
				if (win.warpEventCount > 0) {
					debug(x11sdpy_warp_debug) { import core.stdc.stdio : printf; printf("X11: got \"warp motion\" message, current count=%d\n", (*win).warpEventCount); }
					--(*win).warpEventCount;
					(*win).mdx(mouse); // so deltas will be correctly updated
				} else {
					win.warpEventCount = 0; // just in case
					(*win).mdx(mouse);
					if((*win).handleMouseEvent) {
						XUnlockDisplay(display);
						scope(exit) XLockDisplay(display);
						(*win).handleMouseEvent(mouse);
					}
				}
			}

		  	version(with_eventloop)
				send(mouse);
		  break;
		  case EventType.ButtonPress:
		  case EventType.ButtonRelease:
			MouseEvent mouse;
			auto event = e.xbutton;

			mouse.timestamp = event.time;

			mouse.type = cast(MouseEventType) (e.type == EventType.ButtonPress ? 1 : 2);
			mouse.x = event.x;
			mouse.y = event.y;

			static Time lastMouseDownTime = 0;

			mouse.doubleClick = e.type == EventType.ButtonPress && (event.time - lastMouseDownTime) < mouseDoubleClickTimeout;
			if(e.type == EventType.ButtonPress) lastMouseDownTime = event.time;

			switch(event.button) {
				case 1: mouse.button = MouseButton.left; break; // left
				case 2: mouse.button = MouseButton.middle; break; // middle
				case 3: mouse.button = MouseButton.right; break; // right
				case 4: mouse.button = MouseButton.wheelUp; break; // scroll up
				case 5: mouse.button = MouseButton.wheelDown; break; // scroll down
				case 6: break; // idk
				case 7: break; // idk
				case 8: mouse.button = MouseButton.backButton; break;
				case 9: mouse.button = MouseButton.forwardButton; break;
				default:
			}

			// FIXME: double check this
			mouse.modifierState = event.state;

			//mouse.modifierState = event.detail;

			if(auto win = e.xbutton.window in SimpleWindow.nativeMapping) {
				mouse.window = *win;
				(*win).mdx(mouse);
				if((*win).handleMouseEvent) {
					XUnlockDisplay(display);
					scope(exit) XLockDisplay(display);
					(*win).handleMouseEvent(mouse);
				}
			}
			version(with_eventloop)
				send(mouse);
		  break;

		  case EventType.KeyPress:
		  case EventType.KeyRelease:
			//if (e.type == EventType.KeyPress) { import core.stdc.stdio : stderr, fprintf; fprintf(stderr, "X11 keyboard event!\n"); }
			KeyEvent ke;
			ke.pressed = e.type == EventType.KeyPress;
			ke.hardwareCode = cast(ubyte) e.xkey.keycode;

			auto sym = XKeycodeToKeysym(
				XDisplayConnection.get(),
				e.xkey.keycode,
				0);

			ke.key = cast(Key) sym;//e.xkey.keycode;

			ke.modifierState = e.xkey.state;

			// import std.stdio; writefln("%x", sym);
			wchar_t[128] charbuf = void; // buffer for XwcLookupString; composed value can consist of many chars!
			int charbuflen = 0; // return value of XwcLookupString
			if (ke.pressed) {
				auto win = e.xkey.window in SimpleWindow.nativeMapping;
				if (win !is null && win.xic !is null) {
					//{ import core.stdc.stdio : printf; printf("using xic!\n"); }
					Status status;
					charbuflen = XwcLookupString(win.xic, &e.xkey, charbuf.ptr, cast(int)charbuf.length, &sym, &status);
					//{ import core.stdc.stdio : printf; printf("charbuflen=%d\n", charbuflen); }
				} else {
					//{ import core.stdc.stdio : printf; printf("NOT using xic!\n"); }
					// If XIM initialization failed, don't process intl chars. Sorry, boys and girls.
					char[16] buffer;
					auto res = XLookupString(&e.xkey, buffer.ptr, buffer.length, null, null);
					if (res && buffer[0] < 128) charbuf[charbuflen++] = cast(wchar_t)buffer[0];
				}
			}

			// if there's no char, subst one
			if (charbuflen == 0) {
				switch (sym) {
					case 0xff09: charbuf[charbuflen++] = '\t'; break;
					case 0xff8d: // keypad enter
					case 0xff0d: charbuf[charbuflen++] = '\n'; break;
					default : // ignore
				}
			}

			if (auto win = e.xkey.window in SimpleWindow.nativeMapping) {
				ke.window = *win;


				if(win.inputProxy)
					win = &win.inputProxy;

				// char events are separate since they are on Windows too
				// also, xcompose can generate long char sequences
				// don't send char events if Meta and/or Hyper is pressed
				// TODO: ctrl+char should only send control chars; not yet
				if ((e.xkey.state&ModifierState.ctrl) != 0) {
					if (charbuflen > 1 || charbuf[0] >= ' ') charbuflen = 0;
				}

				dchar[32] charsComingBuffer;
				int charsComingPosition;
				dchar[] charsComing = charsComingBuffer[];

				if (ke.pressed && charbuflen > 0) {
					// FIXME: I think Windows sends these on releases... we should try to match that, but idk about repeats.
					foreach (immutable dchar ch; charbuf[0..charbuflen]) {
						if(charsComingPosition >= charsComing.length)
							charsComing.length = charsComingPosition + 8;

						charsComing[charsComingPosition++] = ch;
					}

					charsComing = charsComing[0 .. charsComingPosition];
				} else {
					charsComing = null;
				}

				ke.charsPossible = charsComing;

				if (win.handleKeyEvent) {
					XUnlockDisplay(display);
					scope(exit) XLockDisplay(display);
					win.handleKeyEvent(ke);
				}

				// Super and alt modifier keys never actually send the chars, they are assumed to be special.
				if ((e.xkey.state&(ModifierState.alt|ModifierState.windows)) == 0 && win.handleCharEvent) {
					XUnlockDisplay(display);
					scope(exit) XLockDisplay(display);
					foreach(ch; charsComing)
						win.handleCharEvent(ch);
				}
			}

			version(with_eventloop)
				send(ke);
		  break;
		  default:
		}

		return done;
	}
}

/* *************************************** */
/*      Done with simpledisplay stuff      */
/* *************************************** */

// Necessary C library bindings follow
version(Windows) {} else
version(X11) {

extern(C) int eventfd (uint initval, int flags) nothrow @trusted @nogc;

// X11 bindings needed here
/*
	A little of this is from the bindings project on
	D Source and some of it is copy/paste from the C
	header.

	The DSource listing consistently used D's long
	where C used long. That's wrong - C long is 32 bit, so
	it should be int in D. I changed that here.

	Note:
	This isn't complete, just took what I needed for myself.
*/

import core.stdc.stddef : wchar_t;

interface XLib {
extern(C) nothrow @nogc {
	char* XResourceManagerString(Display*);
	void XrmInitialize();
	XrmDatabase XrmGetStringDatabase(char* data);
	bool XrmGetResource(XrmDatabase, const char*, const char*, char**, XrmValue*);

	Cursor XCreateFontCursor(Display*, uint shape);
	int XDefineCursor(Display* display, Window w, Cursor cursor);
	int XUndefineCursor(Display* display, Window w);

	Pixmap XCreateBitmapFromData(Display* display, Drawable d, const(char)* data, uint width, uint height);
	Cursor XCreatePixmapCursor(Display* display, Pixmap source, Pixmap mask, XColor* foreground_color, XColor* background_color, uint x, uint y);
	int XFreeCursor(Display* display, Cursor cursor);

	int XLookupString(XKeyEvent *event_struct, char *buffer_return, int bytes_buffer, KeySym *keysym_return, void *status_in_out);

	int XwcLookupString(XIC ic, XKeyPressedEvent* event, wchar_t* buffer_return, int wchars_buffer, KeySym* keysym_return, Status* status_return);

	char *XKeysymToString(KeySym keysym);
	KeySym XKeycodeToKeysym(
		Display*		/* display */,
		KeyCode		/* keycode */,
		int			/* index */
	);

	int XConvertSelection(Display *display, Atom selection, Atom target, Atom property, Window requestor, Time time);

	int XFree(void*);
	int XDeleteProperty(Display *display, Window w, Atom property);

	int XChangeProperty(Display *display, Window w, Atom property, Atom type, int format, int mode, in void *data, int nelements);

	int XGetWindowProperty(Display *display, Window w, Atom property, arch_long
		long_offset, arch_long long_length, Bool del, Atom req_type, Atom
		*actual_type_return, int *actual_format_return, arch_ulong
		*nitems_return, arch_ulong *bytes_after_return, void** prop_return);
	Atom* XListProperties(Display *display, Window w, int *num_prop_return);
	Status XGetTextProperty(Display *display, Window w, XTextProperty *text_prop_return, Atom property);
	Status XQueryTree(Display *display, Window w, Window *root_return, Window *parent_return, Window **children_return, uint *nchildren_return);

	int XSetSelectionOwner(Display *display, Atom selection, Window owner, Time time);

	Window XGetSelectionOwner(Display *display, Atom selection);

	XVisualInfo* XGetVisualInfo(Display*, c_long, XVisualInfo*, int*);

	char** XListFonts(Display*, const char*, int, int*);
	void XFreeFontNames(char**);

	Display* XOpenDisplay(const char*);
	int XCloseDisplay(Display*);

	int XSynchronize(Display*, bool);

	Bool XQueryExtension(Display*, const char*, int*, int*, int*);

	Bool XSupportsLocale();
	char* XSetLocaleModifiers(const(char)* modifier_list);
	XOM XOpenOM(Display* display, _XrmHashBucketRec* rdb, const(char)* res_name, const(char)* res_class);
	Status XCloseOM(XOM om);

	XIM XOpenIM(Display* dpy, _XrmHashBucketRec* rdb, const(char)* res_name, const(char)* res_class);
	Status XCloseIM(XIM im);

	char* XGetIMValues(XIM im, ...) /*_X_SENTINEL(0)*/;
	char* XSetIMValues(XIM im, ...) /*_X_SENTINEL(0)*/;
	Display* XDisplayOfIM(XIM im);
	char* XLocaleOfIM(XIM im);
	XIC XCreateIC(XIM im, ...) /*_X_SENTINEL(0)*/;
	void XDestroyIC(XIC ic);
	void XSetICFocus(XIC ic);
	void XUnsetICFocus(XIC ic);
	//wchar_t* XwcResetIC(XIC ic);
	char* XmbResetIC(XIC ic);
	char* Xutf8ResetIC(XIC ic);
	char* XSetICValues(XIC ic, ...) /*_X_SENTINEL(0)*/;
	char* XGetICValues(XIC ic, ...) /*_X_SENTINEL(0)*/;
	XIM XIMOfIC(XIC ic);

	uint XSendEvent(Display* display, Window w, Bool propagate, arch_long event_mask, XEvent* event_send);


	XFontStruct *XLoadQueryFont(Display *display, in char *name);
	int XFreeFont(Display *display, XFontStruct *font_struct);
	int XSetFont(Display* display, GC gc, Font font);
	int XTextWidth(XFontStruct*, in char*, int);

	int XSetLineAttributes(Display *display, GC gc, uint line_width, int line_style, int cap_style, int join_style);
	int XSetDashes(Display *display, GC gc, int dash_offset, in byte* dash_list, int n);

	Window XCreateSimpleWindow(
		Display*	/* display */,
		Window		/* parent */,
		int			/* x */,
		int			/* y */,
		uint		/* width */,
		uint		/* height */,
		uint		/* border_width */,
		uint		/* border */,
		uint		/* background */
	);
	Window XCreateWindow(Display *display, Window parent, int x, int y, uint width, uint height, uint border_width, int depth, uint class_, Visual *visual, arch_ulong valuemask, XSetWindowAttributes *attributes);

	int XReparentWindow(Display*, Window, Window, int, int);
	int XClearWindow(Display*, Window);
	int XMoveResizeWindow(Display*, Window, int, int, uint, uint);
	int XMoveWindow(Display*, Window, int, int);
	int XResizeWindow(Display *display, Window w, uint width, uint height);

	Colormap XCreateColormap(Display *display, Window w, Visual *visual, int alloc);

	Status XGetWindowAttributes(Display*, Window, XWindowAttributes*);

	XImage *XCreateImage(
		Display*		/* display */,
		Visual*		/* visual */,
		uint	/* depth */,
		int			/* format */,
		int			/* offset */,
		ubyte*		/* data */,
		uint	/* width */,
		uint	/* height */,
		int			/* bitmap_pad */,
		int			/* bytes_per_line */
	);

	Status XInitImage (XImage* image);

	Atom XInternAtom(
		Display*		/* display */,
		const char*	/* atom_name */,
		Bool		/* only_if_exists */
	);

	Status XInternAtoms(Display*, const char**, int, Bool, Atom*);
	char* XGetAtomName(Display*, Atom);
	Status XGetAtomNames(Display*, Atom*, int count, char**);

	int XPutImage(
		Display*	/* display */,
		Drawable	/* d */,
		GC			/* gc */,
		XImage*	/* image */,
		int			/* src_x */,
		int			/* src_y */,
		int			/* dest_x */,
		int			/* dest_y */,
		uint		/* width */,
		uint		/* height */
	);

	XImage *XGetImage(Display *display, Drawable d, int x, int y, uint width, uint height, c_ulong plane_mask, int format);


	int XDestroyWindow(
		Display*	/* display */,
		Window		/* w */
	);

	int XDestroyImage(XImage*);

	int XSelectInput(
		Display*	/* display */,
		Window		/* w */,
		EventMask	/* event_mask */
	);

	int XMapWindow(
		Display*	/* display */,
		Window		/* w */
	);

	Status XIconifyWindow(Display*, Window, int);
	int XMapRaised(Display*, Window);
	int XMapSubwindows(Display*, Window);

	int XNextEvent(
		Display*	/* display */,
		XEvent*		/* event_return */
	);

	int XMaskEvent(Display*, arch_long, XEvent*);

	Bool XFilterEvent(XEvent *event, Window window);
	int XRefreshKeyboardMapping(XMappingEvent *event_map);

	Status XSetWMProtocols(
		Display*	/* display */,
		Window		/* w */,
		Atom*		/* protocols */,
		int			/* count */
	);

	void XSetWMNormalHints(Display *display, Window w, XSizeHints *hints);
	Status XGetWMNormalHints(Display *display, Window w, XSizeHints *hints, c_long* supplied_return);


	Status XInitThreads();
	void XLockDisplay (Display* display);
	void XUnlockDisplay (Display* display);

	void XSetWMProperties(Display*, Window, XTextProperty*, XTextProperty*, char**, int, XSizeHints*, XWMHints*, XClassHint*);

	int XSetWindowBackground (Display* display, Window w, c_ulong background_pixel);
	int XSetWindowBackgroundPixmap (Display* display, Window w, Pixmap background_pixmap);
	//int XSetWindowBorder (Display* display, Window w, c_ulong border_pixel);
	//int XSetWindowBorderPixmap (Display* display, Window w, Pixmap border_pixmap);
	//int XSetWindowBorderWidth (Display* display, Window w, uint width);


	// check out Xft too: http://www.keithp.com/~keithp/render/Xft.tutorial
	int XDrawString(Display*, Drawable, GC, int, int, in char*, int);
	int XDrawLine(Display*, Drawable, GC, int, int, int, int);
	int XDrawRectangle(Display*, Drawable, GC, int, int, uint, uint);
	int XDrawArc(Display*, Drawable, GC, int, int, uint, uint, int, int);
	int XFillRectangle(Display*, Drawable, GC, int, int, uint, uint);
	int XFillArc(Display*, Drawable, GC, int, int, uint, uint, int, int);
	int XDrawPoint(Display*, Drawable, GC, int, int);
	int XSetForeground(Display*, GC, uint);
	int XSetBackground(Display*, GC, uint);

	XFontSet XCreateFontSet(Display*, const char*, char***, int*, char**);
	void XFreeFontSet(Display*, XFontSet);
	void Xutf8DrawString(Display*, Drawable, XFontSet, GC, int, int, in char*, int);
	void Xutf8DrawText(Display*, Drawable, GC, int, int, XmbTextItem*, int);

	int Xutf8TextExtents(XFontSet font_set, const char *, int num_bytes, XRectangle *overall_ink_return, XRectangle *overall_logical_return);
	 	

//Status Xutf8TextPerCharExtents(XFontSet font_set, char *string, int num_bytes, XRectangle *ink_array_return, XRectangle *logical_array_return, int array_size, int *num_chars_return, XRectangle *overall_ink_return, XRectangle *overall_logical_return);

	void XDrawText(Display*, Drawable, GC, int, int, XTextItem*, int);
	int XSetFunction(Display*, GC, int);

	GC XCreateGC(Display*, Drawable, uint, void*);
	int XCopyGC(Display*, GC, uint, GC);
	int XFreeGC(Display*, GC);

	bool XCheckWindowEvent(Display*, Window, int, XEvent*);
	bool XCheckMaskEvent(Display*, int, XEvent*);

	int XPending(Display*);
	int XEventsQueued(Display* display, int mode);

	Pixmap XCreatePixmap(Display*, Drawable, uint, uint, uint);
	int XFreePixmap(Display*, Pixmap);
	int XCopyArea(Display*, Drawable, Drawable, GC, int, int, uint, uint, int, int);
	int XFlush(Display*);
	int XBell(Display*, int);
	int XSync(Display*, bool);

	int XGrabKey (Display* display, int keycode, uint modifiers, Window grab_window, Bool owner_events, int pointer_mode, int keyboard_mode);
	int XUngrabKey (Display* display, int keycode, uint modifiers, Window grab_window);
	KeyCode XKeysymToKeycode (Display* display, KeySym keysym);

	KeySym XStringToKeysym(const char *string);

	Bool XCheckTypedEvent(Display *display, int event_type, XEvent *event_return);

	Window XDefaultRootWindow(Display*);

	int XGrabButton(Display *display, uint button, uint modifiers, Window grab_window, Bool owner_events, uint event_mask, int pointer_mode, int keyboard_mode, Window confine_to, Cursor cursor);

	int XUngrabButton(Display *display, uint button, uint modifiers, Window grab_window); 

	int XDrawLines(Display*, Drawable, GC, XPoint*, int, CoordMode);
	int XFillPolygon(Display*, Drawable, GC, XPoint*, int, PolygonShape, CoordMode);

	Status XAllocColor(Display*, Colormap, XColor*);

	int XWithdrawWindow(Display*, Window, int);
	int XUnmapWindow(Display*, Window);
	int XLowerWindow(Display*, Window);
	int XRaiseWindow(Display*, Window);

	int XWarpPointer(Display *display, Window src_w, Window dest_w, int src_x, int src_y, uint src_width, uint src_height, int dest_x, int dest_y);
	Bool XTranslateCoordinates(Display *display, Window src_w, Window dest_w, int src_x, int src_y, int *dest_x_return, int *dest_y_return, Window *child_return);

	int XGetInputFocus(Display*, Window*, int*);
	int XSetInputFocus(Display*, Window, int, Time);

	XErrorHandler XSetErrorHandler(XErrorHandler);

	int XGetErrorText(Display*, int, char*, int);

	Bool XkbSetDetectableAutoRepeat(Display* dpy, Bool detectable, Bool* supported);


	int XGrabPointer(Display *display, Window grab_window, Bool owner_events, uint event_mask, int pointer_mode, int keyboard_mode, Window confine_to, Cursor cursor, Time time);
	int XUngrabPointer(Display *display, Time time);
	int XChangeActivePointerGrab(Display *display, uint event_mask, Cursor cursor, Time time);

	int XCopyPlane(Display*, Drawable, Drawable, GC, int, int, uint, uint, int, int, arch_ulong);

	Status XGetGeometry(Display*, Drawable, Window*, int*, int*, uint*, uint*, uint*, uint*);
	int XSetClipMask(Display*, GC, Pixmap);
	int XSetClipOrigin(Display*, GC, int, int);

	void XSetClipRectangles(Display*, GC, int, int, XRectangle*, int, int);

	void XSetWMName(Display*, Window, XTextProperty*);
	Status XGetWMName(Display*, Window, XTextProperty*);
	int XStoreName(Display* display, Window w, const(char)* window_name);

	XIOErrorHandler XSetIOErrorHandler (XIOErrorHandler handler);

}
}

interface Xext {
extern(C) nothrow @nogc {
	Status XShmAttach(Display*, XShmSegmentInfo*);
	Status XShmDetach(Display*, XShmSegmentInfo*);
	Status XShmPutImage(
		Display*            /* dpy */,
		Drawable            /* d */,
		GC                  /* gc */,
		XImage*             /* image */,
		int                 /* src_x */,
		int                 /* src_y */,
		int                 /* dst_x */,
		int                 /* dst_y */,
		uint        /* src_width */,
		uint        /* src_height */,
		Bool                /* send_event */
	);

	Status XShmQueryExtension(Display*);

	XImage *XShmCreateImage(
		Display*            /* dpy */,
		Visual*             /* visual */,
		uint        /* depth */,
		int                 /* format */,
		char*               /* data */,
		XShmSegmentInfo*    /* shminfo */,
		uint        /* width */,
		uint        /* height */
	);

	Pixmap XShmCreatePixmap(
		Display*            /* dpy */,
		Drawable            /* d */,
		char*               /* data */,
		XShmSegmentInfo*    /* shminfo */,
		uint        /* width */,
		uint        /* height */,
		uint        /* depth */
	);

}
}

	// this requires -lXpm
	//int XpmCreatePixmapFromData(Display*, Drawable, in char**, Pixmap*, Pixmap*, void*); // FIXME: void* should be XpmAttributes


mixin DynamicLoad!(XLib, "X11", 6, librariesSuccessfullyLoaded) xlib;
mixin DynamicLoad!(Xext, "Xext", 6, librariesSuccessfullyLoaded) xext;
shared static this() {
	xlib.loadDynamicLibrary();
	xext.loadDynamicLibrary();
}


extern(C) nothrow @nogc {

alias XrmDatabase = void*;
struct XrmValue {
	uint size;
	void* addr;
}

struct XVisualInfo {
	Visual* visual;
	VisualID visualid;
	int screen;
	uint depth;
	int c_class;
	c_ulong red_mask;
	c_ulong green_mask;
	c_ulong blue_mask;
	int colormap_size;
	int bits_per_rgb;
}

enum VisualNoMask=	0x0;
enum VisualIDMask=	0x1;
enum VisualScreenMask=0x2;
enum VisualDepthMask=	0x4;
enum VisualClassMask=	0x8;
enum VisualRedMaskMask=0x10;
enum VisualGreenMaskMask=0x20;
enum VisualBlueMaskMask=0x40;
enum VisualColormapSizeMask=0x80;
enum VisualBitsPerRGBMask=0x100;
enum VisualAllMask=	0x1FF;


// XIM and other crap
struct _XOM {}
struct _XIM {}
struct _XIC {}
alias XOM = _XOM*;
alias XIM = _XIM*;
alias XIC = _XIC*;

alias XIMStyle = arch_ulong;
enum : arch_ulong {
	XIMPreeditArea      = 0x0001,
	XIMPreeditCallbacks = 0x0002,
	XIMPreeditPosition  = 0x0004,
	XIMPreeditNothing   = 0x0008,
	XIMPreeditNone      = 0x0010,
	XIMStatusArea       = 0x0100,
	XIMStatusCallbacks  = 0x0200,
	XIMStatusNothing    = 0x0400,
	XIMStatusNone       = 0x0800,
}


/* X Shared Memory Extension functions */
	//pragma(lib, "Xshm");
	alias arch_ulong ShmSeg;
	struct XShmSegmentInfo {
		ShmSeg shmseg;
		int shmid;
		ubyte* shmaddr;
		Bool readOnly;
	}

	// and the necessary OS functions
	int shmget(int, size_t, int);
	void* shmat(int, in void*, int);
	int shmdt(in void*);
	int shmctl (int shmid, int cmd, void* ptr /*struct shmid_ds *buf*/);

	enum IPC_PRIVATE = 0;
	enum IPC_CREAT = 512;
	enum IPC_RMID = 0;

/* MIT-SHM end */


enum MappingType:int {
	MappingModifier		=0,
	MappingKeyboard		=1,
	MappingPointer		=2
}

/* ImageFormat -- PutImage, GetImage */
enum ImageFormat:int {
	XYBitmap	=0,	/* depth 1, XYFormat */
	XYPixmap	=1,	/* depth == drawable depth */
	ZPixmap	=2	/* depth == drawable depth */
}

enum ModifierName:int {
	ShiftMapIndex	=0,
	LockMapIndex	=1,
	ControlMapIndex	=2,
	Mod1MapIndex	=3,
	Mod2MapIndex	=4,
	Mod3MapIndex	=5,
	Mod4MapIndex	=6,
	Mod5MapIndex	=7
}

enum ButtonMask:int {
	Button1Mask	=1<<8,
	Button2Mask	=1<<9,
	Button3Mask	=1<<10,
	Button4Mask	=1<<11,
	Button5Mask	=1<<12,
	AnyModifier	=1<<15/* used in GrabButton, GrabKey */
}

enum KeyOrButtonMask:uint {
	ShiftMask	=1<<0,
	LockMask	=1<<1,
	ControlMask	=1<<2,
	Mod1Mask	=1<<3,
	Mod2Mask	=1<<4,
	Mod3Mask	=1<<5,
	Mod4Mask	=1<<6,
	Mod5Mask	=1<<7,
	Button1Mask	=1<<8,
	Button2Mask	=1<<9,
	Button3Mask	=1<<10,
	Button4Mask	=1<<11,
	Button5Mask	=1<<12,
	AnyModifier	=1<<15/* used in GrabButton, GrabKey */
}

enum ButtonName:int {
	Button1	=1,
	Button2	=2,
	Button3	=3,
	Button4	=4,
	Button5	=5
}

/* Notify modes */
enum NotifyModes:int
{
	NotifyNormal		=0,
	NotifyGrab			=1,
	NotifyUngrab		=2,
	NotifyWhileGrabbed	=3
}
enum NotifyHint = 1;	/* for MotionNotify events */

/* Notify detail */
enum NotifyDetail:int
{
	NotifyAncestor			=0,
	NotifyVirtual			=1,
	NotifyInferior			=2,
	NotifyNonlinear			=3,
	NotifyNonlinearVirtual	=4,
	NotifyPointer			=5,
	NotifyPointerRoot		=6,
	NotifyDetailNone		=7
}

/* Visibility notify */

enum VisibilityNotify:int
{
VisibilityUnobscured		=0,
VisibilityPartiallyObscured	=1,
VisibilityFullyObscured		=2
}


enum WindowStackingMethod:int
{
	Above		=0,
	Below		=1,
	TopIf		=2,
	BottomIf	=3,
	Opposite	=4
}

/* Circulation request */
enum CirculationRequest:int
{
	PlaceOnTop		=0,
	PlaceOnBottom	=1
}

enum PropertyNotification:int
{
	PropertyNewValue	=0,
	PropertyDelete		=1
}

enum ColorMapNotification:int
{
	ColormapUninstalled	=0,
	ColormapInstalled		=1
}


	struct _XPrivate {}
	struct _XrmHashBucketRec {}

	alias void* XPointer;
	alias void* XExtData;

	version( X86_64 ) {
		alias ulong XID;
		alias ulong arch_ulong;
		alias long arch_long;
	} else {
		alias uint XID;
		alias uint arch_ulong;
		alias int arch_long;
	}

	alias XID Window;
	alias XID Drawable;
	alias XID Pixmap;

	alias arch_ulong Atom;
	alias int Bool;
	alias Display XDisplay;

	alias int ByteOrder;
	alias arch_ulong Time;
	alias void ScreenFormat;

	struct XImage {
		int width, height;			/* size of image */
		int xoffset;				/* number of pixels offset in X direction */
		ImageFormat format;		/* XYBitmap, XYPixmap, ZPixmap */
		void *data;					/* pointer to image data */
		ByteOrder byte_order;		/* data byte order, LSBFirst, MSBFirst */
		int bitmap_unit;			/* quant. of scanline 8, 16, 32 */
		int bitmap_bit_order;		/* LSBFirst, MSBFirst */
		int bitmap_pad;			/* 8, 16, 32 either XY or ZPixmap */
		int depth;					/* depth of image */
		int bytes_per_line;			/* accelarator to next line */
		int bits_per_pixel;			/* bits per pixel (ZPixmap) */
		arch_ulong red_mask;	/* bits in z arrangment */
		arch_ulong green_mask;
		arch_ulong blue_mask;
		XPointer obdata;			/* hook for the object routines to hang on */
		static struct F {				/* image manipulation routines */
			XImage* function(
				XDisplay* 			/* display */,
				Visual*				/* visual */,
				uint				/* depth */,
				int					/* format */,
				int					/* offset */,
				ubyte*				/* data */,
				uint				/* width */,
				uint				/* height */,
				int					/* bitmap_pad */,
				int					/* bytes_per_line */) create_image;
			int function(XImage *) destroy_image;
			arch_ulong function(XImage *, int, int) get_pixel;
			int function(XImage *, int, int, arch_ulong) put_pixel;
			XImage* function(XImage *, int, int, uint, uint) sub_image;
			int function(XImage *, arch_long) add_pixel;
		}
		F f;
	}
	version(X86_64) static assert(XImage.sizeof == 136);
	else version(X86) static assert(XImage.sizeof == 88);

struct XCharStruct {
	short       lbearing;       /* origin to left edge of raster */
	short       rbearing;       /* origin to right edge of raster */
	short       width;          /* advance to next char's origin */
	short       ascent;         /* baseline to top edge of raster */
	short       descent;        /* baseline to bottom edge of raster */
	ushort attributes;  /* per char flags (not predefined) */
}

/*
 * To allow arbitrary information with fonts, there are additional properties
 * returned.
 */
struct XFontProp {
	Atom name;
	arch_ulong card32;
}

alias Atom Font;

struct XFontStruct {
	XExtData *ext_data;           /* Hook for extension to hang data */
	Font fid;                     /* Font ID for this font */
	uint direction;           /* Direction the font is painted */
	uint min_char_or_byte2;   /* First character */
	uint max_char_or_byte2;   /* Last character */
	uint min_byte1;           /* First row that exists (for two-byte fonts) */
	uint max_byte1;           /* Last row that exists (for two-byte fonts) */
	Bool all_chars_exist;         /* Flag if all characters have nonzero size */
	uint default_char;        /* Char to print for undefined character */
	int n_properties;             /* How many properties there are */
	XFontProp *properties;        /* Pointer to array of additional properties*/
	XCharStruct min_bounds;       /* Minimum bounds over all existing char*/
	XCharStruct max_bounds;       /* Maximum bounds over all existing char*/
	XCharStruct *per_char;        /* first_char to last_char information */
	int ascent;                   /* Max extent above baseline for spacing */
	int descent;                  /* Max descent below baseline for spacing */
}


/*
 * Definitions of specific events.
 */
struct XKeyEvent
{
	int type;			/* of event */
	arch_ulong serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window it is reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	KeyOrButtonMask state;	/* key or button mask */
	uint keycode;	/* detail */
	Bool same_screen;	/* same screen flag */
}
version(X86_64) static assert(XKeyEvent.sizeof == 96);
alias XKeyEvent XKeyPressedEvent;
alias XKeyEvent XKeyReleasedEvent;

struct XButtonEvent
{
	int type;		/* of event */
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window it is reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	KeyOrButtonMask state;	/* key or button mask */
	uint button;	/* detail */
	Bool same_screen;	/* same screen flag */
}
alias XButtonEvent XButtonPressedEvent;
alias XButtonEvent XButtonReleasedEvent;

struct XMotionEvent{
	int type;		/* of event */
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	KeyOrButtonMask state;	/* key or button mask */
	byte is_hint;		/* detail */
	Bool same_screen;	/* same screen flag */
}
alias XMotionEvent XPointerMovedEvent;

struct XCrossingEvent{
	int type;		/* of event */
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	        /* "event" window reported relative to */
	Window root;	        /* root window that the event occurred on */
	Window subwindow;	/* child window */
	Time time;		/* milliseconds */
	int x, y;		/* pointer x, y coordinates in event window */
	int x_root, y_root;	/* coordinates relative to root */
	NotifyModes mode;		/* NotifyNormal, NotifyGrab, NotifyUngrab */
	NotifyDetail detail;
	/*
	 * NotifyAncestor, NotifyVirtual, NotifyInferior,
	 * NotifyNonlinear,NotifyNonlinearVirtual
	 */
	Bool same_screen;	/* same screen flag */
	Bool focus;		/* Boolean focus */
	KeyOrButtonMask state;	/* key or button mask */
}
alias XCrossingEvent XEnterWindowEvent;
alias XCrossingEvent XLeaveWindowEvent;

struct XFocusChangeEvent{
	int type;		/* FocusIn or FocusOut */
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;		/* window of event */
	NotifyModes mode;		/* NotifyNormal, NotifyWhileGrabbed,
				   NotifyGrab, NotifyUngrab */
	NotifyDetail detail;
	/*
	 * NotifyAncestor, NotifyVirtual, NotifyInferior,
	 * NotifyNonlinear,NotifyNonlinearVirtual, NotifyPointer,
	 * NotifyPointerRoot, NotifyDetailNone
	 */
}
alias XFocusChangeEvent XFocusInEvent;
alias XFocusChangeEvent XFocusOutEvent;

enum CWBackPixmap              = (1L<<0);
enum CWBackPixel               = (1L<<1);
enum CWBorderPixmap            = (1L<<2);
enum CWBorderPixel             = (1L<<3);
enum CWBitGravity              = (1L<<4);
enum CWWinGravity              = (1L<<5);
enum CWBackingStore            = (1L<<6);
enum CWBackingPlanes           = (1L<<7);
enum CWBackingPixel            = (1L<<8);
enum CWOverrideRedirect        = (1L<<9);
enum CWSaveUnder               = (1L<<10);
enum CWEventMask               = (1L<<11);
enum CWDontPropagate           = (1L<<12);
enum CWColormap                = (1L<<13);
enum CWCursor                  = (1L<<14);

struct XWindowAttributes {
	int x, y;			/* location of window */
	int width, height;		/* width and height of window */
	int border_width;		/* border width of window */
	int depth;			/* depth of window */
	Visual *visual;			/* the associated visual structure */
	Window root;			/* root of screen containing window */
	int class_;			/* InputOutput, InputOnly*/
	int bit_gravity;		/* one of the bit gravity values */
	int win_gravity;		/* one of the window gravity values */
	int backing_store;		/* NotUseful, WhenMapped, Always */
	arch_ulong	 backing_planes;	/* planes to be preserved if possible */
	arch_ulong	 backing_pixel;	/* value to be used when restoring planes */
	Bool save_under;		/* boolean, should bits under be saved? */
	Colormap colormap;		/* color map to be associated with window */
	Bool map_installed;		/* boolean, is color map currently installed*/
	int map_state;			/* IsUnmapped, IsUnviewable, IsViewable */
	arch_long all_event_masks;		/* set of events all people have interest in*/
	arch_long your_event_mask;		/* my event mask */
	arch_long do_not_propagate_mask;	/* set of events that should not propagate */
	Bool override_redirect;		/* boolean value for override-redirect */
	Screen *screen;			/* back pointer to correct screen */
}

enum IsUnmapped = 0;
enum IsUnviewable = 1;
enum IsViewable = 2;

struct XSetWindowAttributes {
	Pixmap background_pixmap;/* background, None, or ParentRelative */
	arch_ulong background_pixel;/* background pixel */
	Pixmap border_pixmap;    /* border of the window or CopyFromParent */
	arch_ulong border_pixel;/* border pixel value */
	int bit_gravity;         /* one of bit gravity values */
	int win_gravity;         /* one of the window gravity values */
	int backing_store;       /* NotUseful, WhenMapped, Always */
	arch_ulong backing_planes;/* planes to be preserved if possible */
	arch_ulong backing_pixel;/* value to use in restoring planes */
	Bool save_under;         /* should bits under be saved? (popups) */
	arch_long event_mask;         /* set of events that should be saved */
	arch_long do_not_propagate_mask;/* set of events that should not propagate */
	Bool override_redirect;  /* boolean value for override_redirect */
	Colormap colormap;       /* color map to be associated with window */
	Cursor cursor;           /* cursor to be displayed (or None) */
}


alias int Status;


enum EventMask:int
{
	NoEventMask				=0,
	KeyPressMask			=1<<0,
	KeyReleaseMask			=1<<1,
	ButtonPressMask			=1<<2,
	ButtonReleaseMask		=1<<3,
	EnterWindowMask			=1<<4,
	LeaveWindowMask			=1<<5,
	PointerMotionMask		=1<<6,
	PointerMotionHintMask	=1<<7,
	Button1MotionMask		=1<<8,
	Button2MotionMask		=1<<9,
	Button3MotionMask		=1<<10,
	Button4MotionMask		=1<<11,
	Button5MotionMask		=1<<12,
	ButtonMotionMask		=1<<13,
	KeymapStateMask		=1<<14,
	ExposureMask			=1<<15,
	VisibilityChangeMask	=1<<16,
	StructureNotifyMask		=1<<17,
	ResizeRedirectMask		=1<<18,
	SubstructureNotifyMask	=1<<19,
	SubstructureRedirectMask=1<<20,
	FocusChangeMask			=1<<21,
	PropertyChangeMask		=1<<22,
	ColormapChangeMask		=1<<23,
	OwnerGrabButtonMask		=1<<24
}

struct MwmHints {
	int flags;
	int functions;
	int decorations;
	int input_mode;
	int status;
}

enum {
	MWM_HINTS_FUNCTIONS = (1L << 0),
	MWM_HINTS_DECORATIONS =  (1L << 1),

	MWM_FUNC_ALL = (1L << 0),
	MWM_FUNC_RESIZE = (1L << 1),
	MWM_FUNC_MOVE = (1L << 2),
	MWM_FUNC_MINIMIZE = (1L << 3),
	MWM_FUNC_MAXIMIZE = (1L << 4),
	MWM_FUNC_CLOSE = (1L << 5)
}

import core.stdc.config : c_long, c_ulong;

	/* Size hints mask bits */

	enum   USPosition  = (1L << 0)          /* user specified x, y */;
	enum   USSize      = (1L << 1)          /* user specified width, height */;
	enum   PPosition   = (1L << 2)          /* program specified position */;
	enum   PSize       = (1L << 3)          /* program specified size */;
	enum   PMinSize    = (1L << 4)          /* program specified minimum size */;
	enum   PMaxSize    = (1L << 5)          /* program specified maximum size */;
	enum   PResizeInc  = (1L << 6)          /* program specified resize increments */;
	enum   PAspect     = (1L << 7)          /* program specified min and max aspect ratios */;
	enum   PBaseSize   = (1L << 8);
	enum   PWinGravity = (1L << 9);
	enum   PAllHints   = (PPosition|PSize| PMinSize|PMaxSize| PResizeInc|PAspect);
	struct XSizeHints {
		arch_long flags;         /* marks which fields in this structure are defined */
		int x, y;           /* Obsolete */
		int width, height;  /* Obsolete */
		int min_width, min_height;
		int max_width, max_height;
		int width_inc, height_inc;
		struct Aspect {
			int x;       /* numerator */
			int y;       /* denominator */
		}

		Aspect min_aspect;
		Aspect max_aspect;
		int base_width, base_height;
		int win_gravity;
		/* this structure may be extended in the future */
	}



enum EventType:int
{
	KeyPress			=2,
	KeyRelease			=3,
	ButtonPress			=4,
	ButtonRelease		=5,
	MotionNotify		=6,
	EnterNotify			=7,
	LeaveNotify			=8,
	FocusIn				=9,
	FocusOut			=10,
	KeymapNotify		=11,
	Expose				=12,
	GraphicsExpose		=13,
	NoExpose			=14,
	VisibilityNotify	=15,
	CreateNotify		=16,
	DestroyNotify		=17,
	UnmapNotify		=18,
	MapNotify			=19,
	MapRequest			=20,
	ReparentNotify		=21,
	ConfigureNotify		=22,
	ConfigureRequest	=23,
	GravityNotify		=24,
	ResizeRequest		=25,
	CirculateNotify		=26,
	CirculateRequest	=27,
	PropertyNotify		=28,
	SelectionClear		=29,
	SelectionRequest	=30,
	SelectionNotify		=31,
	ColormapNotify		=32,
	ClientMessage		=33,
	MappingNotify		=34,
	LASTEvent			=35	/* must be bigger than any event # */
}
/* generated on EnterWindow and FocusIn  when KeyMapState selected */
struct XKeymapEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	byte[32] key_vector;
}

struct XExposeEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	int x, y;
	int width, height;
	int count;		/* if non-zero, at least this many more */
}

struct XGraphicsExposeEvent{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Drawable drawable;
	int x, y;
	int width, height;
	int count;		/* if non-zero, at least this many more */
	int major_code;		/* core is CopyArea or CopyPlane */
	int minor_code;		/* not defined in the core */
}

struct XNoExposeEvent{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Drawable drawable;
	int major_code;		/* core is CopyArea or CopyPlane */
	int minor_code;		/* not defined in the core */
}

struct XVisibilityEvent{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	VisibilityNotify state;		/* Visibility state */
}

struct XCreateWindowEvent{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;		/* parent of the window */
	Window window;		/* window id of window created */
	int x, y;		/* window location */
	int width, height;	/* size of window */
	int border_width;	/* border width */
	Bool override_redirect;	/* creation should be overridden */
}

struct XDestroyWindowEvent
{
	int type;
	arch_ulong serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
}

struct XUnmapEvent
{
	int type;
	arch_ulong serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	Bool from_configure;
}

struct XMapEvent
{
	int type;
	arch_ulong serial;		/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	Bool override_redirect;	/* Boolean, is override set... */
}

struct XMapRequestEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;
	Window window;
}

struct XReparentEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	Window parent;
	int x, y;
	Bool override_redirect;
}

struct XConfigureEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	int x, y;
	int width, height;
	int border_width;
	Window above;
	Bool override_redirect;
}

struct XGravityEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	int x, y;
}

struct XResizeRequestEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	int width, height;
}

struct  XConfigureRequestEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;
	Window window;
	int x, y;
	int width, height;
	int border_width;
	Window above;
	WindowStackingMethod detail;		/* Above, Below, TopIf, BottomIf, Opposite */
	arch_ulong value_mask;
}

struct XCirculateEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window event;
	Window window;
	CirculationRequest place;		/* PlaceOnTop, PlaceOnBottom */
}

struct XCirculateRequestEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window parent;
	Window window;
	CirculationRequest place;		/* PlaceOnTop, PlaceOnBottom */
}

struct XPropertyEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Atom atom;
	Time time;
	PropertyNotification state;		/* NewValue, Deleted */
}

struct XSelectionClearEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Atom selection;
	Time time;
}

struct XSelectionRequestEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window owner;
	Window requestor;
	Atom selection;
	Atom target;
	Atom property;
	Time time;
}

struct XSelectionEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window requestor;
	Atom selection;
	Atom target;
	Atom property;		/* ATOM or None */
	Time time;
}
version(X86_64) static assert(XSelectionClearEvent.sizeof == 56);

struct XColormapEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Colormap colormap;	/* COLORMAP or None */
	Bool new_;		/* C++ */
	ColorMapNotification state;		/* ColormapInstalled, ColormapUninstalled */
}
version(X86_64) static assert(XColormapEvent.sizeof == 56);

struct XClientMessageEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;
	Atom message_type;
	int format;
	union Data{
		byte[20] b;
		short[10] s;
		arch_ulong[5] l;
	}
	Data data;

}
version(X86_64) static assert(XClientMessageEvent.sizeof == 96);

struct XMappingEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;		/* unused */
	MappingType request;		/* one of MappingModifier, MappingKeyboard,
				   MappingPointer */
	int first_keycode;	/* first keycode */
	int count;		/* defines range of change w. first_keycode*/
}

struct XErrorEvent
{
	int type;
	Display *display;	/* Display the event was read from */
	XID resourceid;		/* resource id */
	arch_ulong serial;	/* serial number of failed request */
	ubyte error_code;	/* error code of failed request */
	ubyte request_code;	/* Major op-code of failed request */
	ubyte minor_code;	/* Minor op-code of failed request */
}

struct XAnyEvent
{
	int type;
	arch_ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;/* Display the event was read from */
	Window window;	/* window on which event was requested in event mask */
}

union XEvent{
	int type;		/* must not be changed; first element */
	XAnyEvent xany;
	XKeyEvent xkey;
	XButtonEvent xbutton;
	XMotionEvent xmotion;
	XCrossingEvent xcrossing;
	XFocusChangeEvent xfocus;
	XExposeEvent xexpose;
	XGraphicsExposeEvent xgraphicsexpose;
	XNoExposeEvent xnoexpose;
	XVisibilityEvent xvisibility;
	XCreateWindowEvent xcreatewindow;
	XDestroyWindowEvent xdestroywindow;
	XUnmapEvent xunmap;
	XMapEvent xmap;
	XMapRequestEvent xmaprequest;
	XReparentEvent xreparent;
	XConfigureEvent xconfigure;
	XGravityEvent xgravity;
	XResizeRequestEvent xresizerequest;
	XConfigureRequestEvent xconfigurerequest;
	XCirculateEvent xcirculate;
	XCirculateRequestEvent xcirculaterequest;
	XPropertyEvent xproperty;
	XSelectionClearEvent xselectionclear;
	XSelectionRequestEvent xselectionrequest;
	XSelectionEvent xselection;
	XColormapEvent xcolormap;
	XClientMessageEvent xclient;
	XMappingEvent xmapping;
	XErrorEvent xerror;
	XKeymapEvent xkeymap;
	arch_ulong[24] pad;
}


	struct Display {
		XExtData *ext_data;	/* hook for extension to hang data */
		_XPrivate *private1;
		int fd;			/* Network socket. */
		int private2;
		int proto_major_version;/* major version of server's X protocol */
		int proto_minor_version;/* minor version of servers X protocol */
		char *vendor;		/* vendor of the server hardware */
	    	XID private3;
		XID private4;
		XID private5;
		int private6;
		XID function(Display*)resource_alloc;/* allocator function */
		ByteOrder byte_order;		/* screen byte order, LSBFirst, MSBFirst */
		int bitmap_unit;	/* padding and data requirements */
		int bitmap_pad;		/* padding requirements on bitmaps */
		ByteOrder bitmap_bit_order;	/* LeastSignificant or MostSignificant */
		int nformats;		/* number of pixmap formats in list */
		ScreenFormat *pixmap_format;	/* pixmap format list */
		int private8;
		int release;		/* release of the server */
		_XPrivate *private9;
		_XPrivate *private10;
		int qlen;		/* Length of input event queue */
		arch_ulong last_request_read; /* seq number of last event read */
		arch_ulong request;	/* sequence number of last request. */
		XPointer private11;
		XPointer private12;
		XPointer private13;
		XPointer private14;
		uint max_request_size; /* maximum number 32 bit words in request*/
		_XrmHashBucketRec *db;
		int function  (Display*)private15;
		char *display_name;	/* "host:display" string used on this connect*/
		int default_screen;	/* default screen for operations */
		int nscreens;		/* number of screens on this server*/
		Screen *screens;	/* pointer to list of screens */
		arch_ulong motion_buffer;	/* size of motion buffer */
		arch_ulong private16;
		int min_keycode;	/* minimum defined keycode */
		int max_keycode;	/* maximum defined keycode */
		XPointer private17;
		XPointer private18;
		int private19;
		byte *xdefaults;	/* contents of defaults from server */
		/* there is more to this structure, but it is private to Xlib */
	}

	// I got these numbers from a C program as a sanity test
	version(X86_64) {
		static assert(Display.sizeof == 296);
		static assert(XPointer.sizeof == 8);
		static assert(XErrorEvent.sizeof == 40);
		static assert(XAnyEvent.sizeof == 40);
		static assert(XMappingEvent.sizeof == 56);
		static assert(XEvent.sizeof == 192);
	} else {
		static assert(Display.sizeof == 176);
		static assert(XPointer.sizeof == 4);
		static assert(XEvent.sizeof == 96);
	}

struct Depth
{
	int depth;		/* this depth (Z) of the depth */
	int nvisuals;		/* number of Visual types at this depth */
	Visual *visuals;	/* list of visuals possible at this depth */
}

alias void* GC;
alias c_ulong VisualID;
alias XID Colormap;
alias XID Cursor;
alias XID KeySym;
alias uint KeyCode;
enum None = 0;
}

version(without_opengl) {}
else {
extern(C) nothrow @nogc {


static if(!SdpyIsUsingIVGLBinds) {
enum GLX_USE_GL=            1;       /* support GLX rendering */
enum GLX_BUFFER_SIZE=       2;       /* depth of the color buffer */
enum GLX_LEVEL=             3;       /* level in plane stacking */
enum GLX_RGBA=              4;       /* true if RGBA mode */
enum GLX_DOUBLEBUFFER=      5;       /* double buffering supported */
enum GLX_STEREO=            6;       /* stereo buffering supported */
enum GLX_AUX_BUFFERS=       7;       /* number of aux buffers */
enum GLX_RED_SIZE=          8;       /* number of red component bits */
enum GLX_GREEN_SIZE=        9;       /* number of green component bits */
enum GLX_BLUE_SIZE=         10;      /* number of blue component bits */
enum GLX_ALPHA_SIZE=        11;      /* number of alpha component bits */
enum GLX_DEPTH_SIZE=        12;      /* number of depth bits */
enum GLX_STENCIL_SIZE=      13;      /* number of stencil bits */
enum GLX_ACCUM_RED_SIZE=    14;      /* number of red accum bits */
enum GLX_ACCUM_GREEN_SIZE=  15;      /* number of green accum bits */
enum GLX_ACCUM_BLUE_SIZE=   16;      /* number of blue accum bits */
enum GLX_ACCUM_ALPHA_SIZE=  17;      /* number of alpha accum bits */


//XVisualInfo* glXChooseVisual(Display *dpy, int screen, in int *attrib_list);



enum GL_TRUE = 1;
enum GL_FALSE = 0;
alias int GLint;
}

alias XID GLXContextID;
alias XID GLXPixmap;
alias XID GLXDrawable;
alias XID GLXPbuffer;
alias XID GLXWindow;
alias XID GLXFBConfigID;
alias void* GLXContext;

}
}

enum AllocNone = 0;

extern(C) {
	/* WARNING, this type not in Xlib spec */
	extern(C) alias XIOErrorHandler = int function (Display* display);
}

extern(C) nothrow @nogc {
struct Screen{
	XExtData *ext_data;		/* hook for extension to hang data */
	Display *display;		/* back pointer to display structure */
	Window root;			/* Root window id. */
	int width, height;		/* width and height of screen */
	int mwidth, mheight;	/* width and height of  in millimeters */
	int ndepths;			/* number of depths possible */
	Depth *depths;			/* list of allowable depths on the screen */
	int root_depth;			/* bits per pixel */
	Visual *root_visual;	/* root visual */
	GC default_gc;			/* GC for the root root visual */
	Colormap cmap;			/* default color map */
	uint white_pixel;
	uint black_pixel;		/* White and Black pixel values */
	int max_maps, min_maps;	/* max and min color maps */
	int backing_store;		/* Never, WhenMapped, Always */
	bool save_unders;
	int root_input_mask;	/* initial root input mask */
}

struct Visual
{
	XExtData *ext_data;	/* hook for extension to hang data */
	VisualID visualid;	/* visual id of this visual */
	int class_;			/* class of screen (monochrome, etc.) */
	c_ulong red_mask, green_mask, blue_mask;	/* mask values */
	int bits_per_rgb;	/* log base 2 of distinct color values */
	int map_entries;	/* color map entries */
}

	alias Display* _XPrivDisplay;

	Screen* ScreenOfDisplay(Display* dpy, int scr) {
		assert(dpy !is null);
		return &dpy.screens[scr];
	}

	Window	RootWindow(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).root;
	}

	struct XWMHints {
		arch_long flags;
		Bool input;
		int initial_state;
		Pixmap icon_pixmap;
		Window icon_window;
		int icon_x, icon_y;
		Pixmap icon_mask;
		XID window_group;
	}

	struct XClassHint {
		char* res_name;
		char* res_class;
	}

	int DefaultScreen(Display *dpy) {
		return dpy.default_screen;
	}

	int DefaultDepth(Display* dpy, int scr) { return ScreenOfDisplay(dpy, scr).root_depth; }
	int DisplayWidth(Display* dpy, int scr) { return ScreenOfDisplay(dpy, scr).width; }
	int DisplayHeight(Display* dpy, int scr) { return ScreenOfDisplay(dpy, scr).height; }
	int DisplayWidthMM(Display* dpy, int scr) { return ScreenOfDisplay(dpy, scr).mwidth; }
	int DisplayHeightMM(Display* dpy, int scr) { return ScreenOfDisplay(dpy, scr).mheight; }
	auto DefaultColormap(Display* dpy, int scr) { return ScreenOfDisplay(dpy, scr).cmap; }

	int ConnectionNumber(Display* dpy) { return dpy.fd; }

	enum int AnyPropertyType = 0;
	enum int Success = 0;

	enum int RevertToNone = None;
	enum int PointerRoot = 1;
	enum Time CurrentTime = 0;
	enum int RevertToPointerRoot = PointerRoot;
	enum int RevertToParent = 2;

	int DefaultDepthOfDisplay(Display* dpy) {
		return ScreenOfDisplay(dpy, DefaultScreen(dpy)).root_depth;
	}

	Visual* DefaultVisual(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).root_visual;
	}

	GC DefaultGC(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).default_gc;
	}

	uint BlackPixel(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).black_pixel;
	}

	uint WhitePixel(Display *dpy,int scr) {
		return ScreenOfDisplay(dpy,scr).white_pixel;
	}

	alias void* XFontSet; // i think
	struct XmbTextItem {
		char* chars;
		int nchars;
		int delta;
		XFontSet font_set;
	}

	struct XTextItem {
		char* chars;
		int nchars;
		int delta;
		Font font;
	}

	enum {
		GXclear        = 0x0, /* 0 */
		GXand          = 0x1, /* src AND dst */
		GXandReverse   = 0x2, /* src AND NOT dst */
		GXcopy         = 0x3, /* src */
		GXandInverted  = 0x4, /* NOT src AND dst */
		GXnoop         = 0x5, /* dst */
		GXxor          = 0x6, /* src XOR dst */
		GXor           = 0x7, /* src OR dst */
		GXnor          = 0x8, /* NOT src AND NOT dst */
		GXequiv        = 0x9, /* NOT src XOR dst */
		GXinvert       = 0xa, /* NOT dst */
		GXorReverse    = 0xb, /* src OR NOT dst */
		GXcopyInverted = 0xc, /* NOT src */
		GXorInverted   = 0xd, /* NOT src OR dst */
		GXnand         = 0xe, /* NOT src OR NOT dst */
		GXset          = 0xf, /* 1 */
	}
	enum QueueMode : int {
		QueuedAlready,
		QueuedAfterReading,
		QueuedAfterFlush
	}

	enum GrabMode { GrabModeSync = 0, GrabModeAsync = 1 }

	struct XPoint {
		short x;
		short y;
	}

	enum CoordMode:int {
		CoordModeOrigin = 0,
		CoordModePrevious = 1
	}

	enum PolygonShape:int {
		Complex = 0,
		Nonconvex = 1,
		Convex = 2
	}

	struct XTextProperty {
		const(char)* value;		/* same as Property routines */
		Atom encoding;			/* prop type */
		int format;				/* prop data format: 8, 16, or 32 */
		arch_ulong nitems;		/* number of data items in value */
	}

	version( X86_64 ) {
		static assert(XTextProperty.sizeof == 32);
	}


	struct XGCValues {
		int function_;           /* logical operation */
		arch_ulong plane_mask;/* plane mask */
		arch_ulong foreground;/* foreground pixel */
		arch_ulong background;/* background pixel */
		int line_width;         /* line width */
		int line_style;         /* LineSolid, LineOnOffDash, LineDoubleDash */
		int cap_style;          /* CapNotLast, CapButt,
					   CapRound, CapProjecting */
		int join_style;         /* JoinMiter, JoinRound, JoinBevel */
		int fill_style;         /* FillSolid, FillTiled,
					   FillStippled, FillOpaeueStippled */
		int fill_rule;          /* EvenOddRule, WindingRule */
		int arc_mode;           /* ArcChord, ArcPieSlice */
		Pixmap tile;            /* tile pixmap for tiling operations */
		Pixmap stipple;         /* stipple 1 plane pixmap for stipping */
		int ts_x_origin;        /* offset for tile or stipple operations */
		int ts_y_origin;
		Font font;              /* default text font for text operations */
		int subwindow_mode;     /* ClipByChildren, IncludeInferiors */
		Bool graphics_exposures;/* boolean, should exposures be generated */
		int clip_x_origin;      /* origin for clipping */
		int clip_y_origin;
		Pixmap clip_mask;       /* bitmap clipping; other calls for rects */
		int dash_offset;        /* patterned/dashed line information */
		char dashes;
	}

	struct XColor {
		arch_ulong pixel;
		ushort red, green, blue;
		byte flags;
		byte pad;
	}

	alias XErrorHandler = int function(Display*, XErrorEvent*);

	struct XRectangle {
		short x;
		short y;
		ushort width;
		ushort height;
	}

	enum ClipByChildren = 0;
	enum IncludeInferiors = 1;

	enum Atom XA_PRIMARY = 1;
	enum Atom XA_SECONDARY = 2;
	enum Atom XA_STRING = 31;
	enum Atom XA_CARDINAL = 6;
	enum Atom XA_WM_NAME = 39;
	enum Atom XA_ATOM = 4;
	enum Atom XA_WINDOW = 33;
	enum Atom XA_WM_HINTS = 35;
	enum int PropModeAppend = 2;
	enum int PropModeReplace = 0;
	enum int PropModePrepend = 1;

	enum int CopyFromParent = 0;
	enum int InputOutput = 1;

	// XWMHints
	enum InputHint = 1 << 0;
	enum StateHint = 1 << 1;
	enum IconPixmapHint = (1L << 2);
	enum IconWindowHint = (1L << 3);
	enum IconPositionHint = (1L << 4);
	enum IconMaskHint = (1L << 5);
	enum WindowGroupHint = (1L << 6);
	enum AllHints = (InputHint|StateHint|IconPixmapHint|IconWindowHint|IconPositionHint|IconMaskHint|WindowGroupHint);
	enum XUrgencyHint = (1L << 8);

	// GC Components
	enum GCFunction           =   (1L<<0);
	enum GCPlaneMask         =    (1L<<1);
	enum GCForeground       =     (1L<<2);
	enum GCBackground      =      (1L<<3);
	enum GCLineWidth      =       (1L<<4);
	enum GCLineStyle     =        (1L<<5);
	enum GCCapStyle     =         (1L<<6);
	enum GCJoinStyle   =          (1L<<7);
	enum GCFillStyle  =           (1L<<8);
	enum GCFillRule  =            (1L<<9);
	enum GCTile     =             (1L<<10);
	enum GCStipple           =    (1L<<11);
	enum GCTileStipXOrigin  =     (1L<<12);
	enum GCTileStipYOrigin =      (1L<<13);
	enum GCFont               =   (1L<<14);
	enum GCSubwindowMode     =    (1L<<15);
	enum GCGraphicsExposures=     (1L<<16);
	enum GCClipXOrigin     =      (1L<<17);
	enum GCClipYOrigin    =       (1L<<18);
	enum GCClipMask      =        (1L<<19);
	enum GCDashOffset   =         (1L<<20);
	enum GCDashList    =          (1L<<21);
	enum GCArcMode    =           (1L<<22);
	enum GCLastBit   =            22;


	enum int WithdrawnState = 0;
	enum int NormalState = 1;
	enum int IconicState = 3;

}
} else version (OSXCocoa) {
private:
	alias void* id;
	alias void* Class;
	alias void* SEL;
	alias void* IMP;
	alias void* Ivar;
	alias byte BOOL;
	alias const(void)* CFStringRef;
	alias const(void)* CFAllocatorRef;
	alias const(void)* CFTypeRef;
	alias const(void)* CGContextRef;
	alias const(void)* CGColorSpaceRef;
	alias const(void)* CGImageRef;
	alias ulong CGBitmapInfo;

	struct objc_super {
		id self;
		Class superclass;
	}

	struct CFRange {
		long location, length;
	}

	struct NSPoint {
		double x, y;

		static fromTuple(T)(T tupl) {
			return NSPoint(tupl.tupleof);
		}
	}
	struct NSSize {
		double width, height;
	}
	struct NSRect {
		NSPoint origin;
		NSSize size;
	}
	alias NSPoint CGPoint;
	alias NSSize CGSize;
	alias NSRect CGRect;

	struct CGAffineTransform {
		double a, b, c, d, tx, ty;
	}

	enum NSApplicationActivationPolicyRegular = 0;
	enum NSBackingStoreBuffered = 2;
	enum kCFStringEncodingUTF8 = 0x08000100;

	enum : size_t {
		NSBorderlessWindowMask = 0,
		NSTitledWindowMask = 1 << 0,
		NSClosableWindowMask = 1 << 1,
		NSMiniaturizableWindowMask = 1 << 2,
		NSResizableWindowMask = 1 << 3,
		NSTexturedBackgroundWindowMask = 1 << 8
	}

	enum : ulong {
		kCGImageAlphaNone,
		kCGImageAlphaPremultipliedLast,
		kCGImageAlphaPremultipliedFirst,
		kCGImageAlphaLast,
		kCGImageAlphaFirst,
		kCGImageAlphaNoneSkipLast,
		kCGImageAlphaNoneSkipFirst
	}
	enum : ulong {
		kCGBitmapAlphaInfoMask = 0x1F,
		kCGBitmapFloatComponents = (1 << 8),
		kCGBitmapByteOrderMask = 0x7000,
		kCGBitmapByteOrderDefault = (0 << 12),
		kCGBitmapByteOrder16Little = (1 << 12),
		kCGBitmapByteOrder32Little = (2 << 12),
		kCGBitmapByteOrder16Big = (3 << 12),
		kCGBitmapByteOrder32Big = (4 << 12)
	}
	enum CGPathDrawingMode {
		kCGPathFill,
		kCGPathEOFill,
		kCGPathStroke,
		kCGPathFillStroke,
		kCGPathEOFillStroke
	}
	enum objc_AssociationPolicy : size_t {
		OBJC_ASSOCIATION_ASSIGN = 0,
		OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
		OBJC_ASSOCIATION_COPY_NONATOMIC = 3,
		OBJC_ASSOCIATION_RETAIN = 0x301, //01401,
		OBJC_ASSOCIATION_COPY = 0x303 //01403
	}

	extern(C) {
		id objc_msgSend(id receiver, SEL selector, ...);
		id objc_msgSendSuper(objc_super* superStruct, SEL selector, ...);
		id objc_getClass(const(char)* name);
		SEL sel_registerName(const(char)* str);
		Class objc_allocateClassPair(Class superclass, const(char)* name,
									 size_t extra_bytes);
		void objc_registerClassPair(Class cls);
		BOOL class_addMethod(Class cls, SEL name, IMP imp, const(char)* types);
		id objc_getAssociatedObject(id object, void* key);
		void objc_setAssociatedObject(id object, void* key, id value,
									  objc_AssociationPolicy policy);
		Ivar class_getInstanceVariable(Class cls, const(char)* name);
		id object_getIvar(id object, Ivar ivar);
		void object_setIvar(id object, Ivar ivar, id value);
		BOOL class_addIvar(Class cls, const(char)* name,
						   size_t size, ubyte alignment, const(char)* types);

		extern __gshared id NSApp;

		void CFRelease(CFTypeRef obj);

		CFStringRef CFStringCreateWithBytes(CFAllocatorRef allocator,
											const(char)* bytes, long numBytes,
											long encoding,
											BOOL isExternalRepresentation);
		long CFStringGetBytes(CFStringRef theString, CFRange range, long encoding,
							 char lossByte, bool isExternalRepresentation,
							 char* buffer, long maxBufLen, long* usedBufLen);
		long CFStringGetLength(CFStringRef theString);

		CGContextRef CGBitmapContextCreate(void* data,
										   size_t width, size_t height,
										   size_t bitsPerComponent,
										   size_t bytesPerRow,
										   CGColorSpaceRef colorspace,
										   CGBitmapInfo bitmapInfo);
		void CGContextRelease(CGContextRef c);
		ubyte* CGBitmapContextGetData(CGContextRef c);
		CGImageRef CGBitmapContextCreateImage(CGContextRef c);
		size_t CGBitmapContextGetWidth(CGContextRef c);
		size_t CGBitmapContextGetHeight(CGContextRef c);

		CGColorSpaceRef CGColorSpaceCreateDeviceRGB();
		void CGColorSpaceRelease(CGColorSpaceRef cs);

		void CGContextSetRGBStrokeColor(CGContextRef c,
										double red, double green, double blue,
										double alpha);
		void CGContextSetRGBFillColor(CGContextRef c,
									  double red, double green, double blue,
									  double alpha);
		void CGContextDrawImage(CGContextRef c, CGRect rect, CGImageRef image);
		void CGContextShowTextAtPoint(CGContextRef c, double x, double y,
									  const(char)* str, size_t length);
		void CGContextStrokeLineSegments(CGContextRef c,
										 const(CGPoint)* points, size_t count);

		void CGContextBeginPath(CGContextRef c);
		void CGContextDrawPath(CGContextRef c, CGPathDrawingMode mode);
		void CGContextAddEllipseInRect(CGContextRef c, CGRect rect);
		void CGContextAddArc(CGContextRef c, double x, double y, double radius,
							 double startAngle, double endAngle, long clockwise);
		void CGContextAddRect(CGContextRef c, CGRect rect);
		void CGContextAddLines(CGContextRef c,
							   const(CGPoint)* points, size_t count);
		void CGContextSaveGState(CGContextRef c);
		void CGContextRestoreGState(CGContextRef c);
		void CGContextSelectFont(CGContextRef c, const(char)* name, double size,
								 ulong textEncoding);
		CGAffineTransform CGContextGetTextMatrix(CGContextRef c);
		void CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t);

		void CGImageRelease(CGImageRef image);
	}

private:
    // A convenient method to create a CFString (=NSString) from a D string.
    CFStringRef createCFString(string str) {
        return CFStringCreateWithBytes(null, str.ptr, cast(long) str.length,
                                             kCFStringEncodingUTF8, false);
    }

    // Objective-C calls.
    RetType objc_msgSend_specialized(string selector, RetType, T...)(id self, T args) {
        auto _cmd = sel_registerName(selector.ptr);
        alias extern(C) RetType function(id, SEL, T) ExpectedType;
        return (cast(ExpectedType)&objc_msgSend)(self, _cmd, args);
    }
    RetType objc_msgSend_classMethod(string selector, RetType, T...)(const(char)* className, T args) {
        auto _cmd = sel_registerName(selector.ptr);
        auto cls = objc_getClass(className);
        alias extern(C) RetType function(id, SEL, T) ExpectedType;
        return (cast(ExpectedType)&objc_msgSend)(cls, _cmd, args);
    }
    RetType objc_msgSend_classMethod(string className, string selector, RetType, T...)(T args) {
        return objc_msgSend_classMethod!(selector, RetType, T)(className.ptr, args);
    }

    alias objc_msgSend_specialized!("setNeedsDisplay:", void, BOOL) setNeedsDisplay;
    alias objc_msgSend_classMethod!("alloc", id) alloc;
    alias objc_msgSend_specialized!("initWithContentRect:styleMask:backing:defer:",
                                    id, NSRect, size_t, size_t, BOOL) initWithContentRect;
    alias objc_msgSend_specialized!("setTitle:", void, CFStringRef) setTitle;
    alias objc_msgSend_specialized!("center", void) center;
    alias objc_msgSend_specialized!("initWithFrame:", id, NSRect) initWithFrame;
    alias objc_msgSend_specialized!("setContentView:", void, id) setContentView;
    alias objc_msgSend_specialized!("release", void) release;
    alias objc_msgSend_classMethod!("NSColor", "whiteColor", id) whiteNSColor;
    alias objc_msgSend_specialized!("setBackgroundColor:", void, id) setBackgroundColor;
    alias objc_msgSend_specialized!("makeKeyAndOrderFront:", void, id) makeKeyAndOrderFront;
    alias objc_msgSend_specialized!("invalidate", void) invalidate;
    alias objc_msgSend_specialized!("close", void) close;
    alias objc_msgSend_classMethod!("NSTimer", "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:",
                                    id, double, id, SEL, id, BOOL) scheduledTimer;
    alias objc_msgSend_specialized!("run", void) run;
    alias objc_msgSend_classMethod!("NSGraphicsContext", "currentContext",
                                    id) currentNSGraphicsContext;
    alias objc_msgSend_specialized!("graphicsPort", CGContextRef) graphicsPort;
    alias objc_msgSend_specialized!("characters", CFStringRef) characters;
    alias objc_msgSend_specialized!("superclass", Class) superclass;
    alias objc_msgSend_specialized!("init", id) init;
    alias objc_msgSend_specialized!("addItem:", void, id) addItem;
    alias objc_msgSend_specialized!("setMainMenu:", void, id) setMainMenu;
    alias objc_msgSend_specialized!("initWithTitle:action:keyEquivalent:",
                                    id, CFStringRef, SEL, CFStringRef) initWithTitle;
    alias objc_msgSend_specialized!("setSubmenu:", void, id) setSubmenu;
    alias objc_msgSend_specialized!("setDelegate:", void, id) setDelegate;
    alias objc_msgSend_specialized!("activateIgnoringOtherApps:",
                                    void, BOOL) activateIgnoringOtherApps;
    alias objc_msgSend_classMethod!("NSApplication", "sharedApplication",
                                    id) sharedNSApplication;
    alias objc_msgSend_specialized!("setActivationPolicy:", void, ptrdiff_t) setActivationPolicy;
} else static assert(0, "Unsupported operating system");


version(OSXCocoa) {
	// I don't know anything about the Mac, but a couple years ago, KennyTM on the newsgroup wrote this for me
	//
	// http://forum.dlang.org/thread/innr0v$1deh$1@digitalmars.com?page=4#post-int88l:24uaf:241:40digitalmars.com
	// https://github.com/kennytm/simpledisplay.d/blob/osx/simpledisplay.d
	//
	// and it is about time I merged it in here. It is available with -version=OSXCocoa until someone tests it for me!
	// Probably won't even fully compile right now

    import std.math : PI;
    import std.algorithm : map;
    import std.array : array;

    alias SimpleWindow NativeWindowHandle;
    alias void delegate(id) NativeEventHandler;

    __gshared Ivar simpleWindowIvar;

    enum KEY_ESCAPE = 27;

    mixin template NativeImageImplementation() {
        CGContextRef context;
        ubyte* rawData;
    final:

	void convertToRgbaBytes(ubyte[] where) {
		assert(where.length == this.width * this.height * 4);

		// if rawData had a length....
		//assert(rawData.length == where.length);
		for(long idx = 0; idx < where.length; idx += 4) {
			auto alpha = rawData[idx + 3];
			if(alpha == 255) {
				where[idx + 0] = rawData[idx + 0]; // r
				where[idx + 1] = rawData[idx + 1]; // g
				where[idx + 2] = rawData[idx + 2]; // b
				where[idx + 3] = rawData[idx + 3]; // a
			} else {
				where[idx + 0] = cast(ubyte)(rawData[idx + 0] * 255 / alpha); // r
				where[idx + 1] = cast(ubyte)(rawData[idx + 1] * 255 / alpha); // g
				where[idx + 2] = cast(ubyte)(rawData[idx + 2] * 255 / alpha); // b
				where[idx + 3] = rawData[idx + 3]; // a

			}
		}
	}

	void setFromRgbaBytes(in ubyte[] where) {
		// FIXME: this is probably wrong
		assert(where.length == this.width * this.height * 4);

		// if rawData had a length....
		//assert(rawData.length == where.length);
		for(long idx = 0; idx < where.length; idx += 4) {
			auto alpha = rawData[idx + 3];
			if(alpha == 255) {
				rawData[idx + 0] = where[idx + 0]; // r
				rawData[idx + 1] = where[idx + 1]; // g
				rawData[idx + 2] = where[idx + 2]; // b
				rawData[idx + 3] = where[idx + 3]; // a
			} else {
				rawData[idx + 0] = cast(ubyte)(where[idx + 0] * 255 / alpha); // r
				rawData[idx + 1] = cast(ubyte)(where[idx + 1] * 255 / alpha); // g
				rawData[idx + 2] = cast(ubyte)(where[idx + 2] * 255 / alpha); // b
				rawData[idx + 3] = where[idx + 3]; // a

			}
		}
	}


        void createImage(int width, int height, bool forcexshm=false) {
            auto colorSpace = CGColorSpaceCreateDeviceRGB();
            context = CGBitmapContextCreate(null, width, height, 8, 4*width,
                                            colorSpace,
                                            kCGImageAlphaPremultipliedLast
                                                   |kCGBitmapByteOrder32Big);
            CGColorSpaceRelease(colorSpace);
            rawData = CGBitmapContextGetData(context);
        }
        void dispose() {
            CGContextRelease(context);
        }

        void setPixel(int x, int y, Color c) {
            auto offset = (y * width + x) * 4;
            if (c.a == 255) {
                rawData[offset + 0] = c.r;
                rawData[offset + 1] = c.g;
                rawData[offset + 2] = c.b;
                rawData[offset + 3] = c.a;
            } else {
                rawData[offset + 0] = cast(ubyte)(c.r*c.a/255);
                rawData[offset + 1] = cast(ubyte)(c.g*c.a/255);
                rawData[offset + 2] = cast(ubyte)(c.b*c.a/255);
                rawData[offset + 3] = c.a;
            }
        }
    }

    mixin template NativeScreenPainterImplementation() {
        CGContextRef context;
        ubyte[4] _outlineComponents;
	id view;

        void create(NativeWindowHandle window) {
            context = window.drawingContext;
	    view = window.view;
        }

        void dispose() {
            	setNeedsDisplay(view, true);
        }

	// NotYetImplementedException
	Size textSize(in char[] txt) { return Size(32, 16); throw new NotYetImplementedException(); }
	void rasterOp(RasterOp op) {}
	Pen _activePen;
	Color _fillColor;
	Rectangle _clipRectangle;
	void setClipRectangle(int, int, int, int) {}
	void setFont(OperatingSystemFont) {}
	int fontHeight() { return 14; }

	// end

        void pen(Pen pen) {
	    _activePen = pen;
	    auto color = pen.color; // FIXME
            double alphaComponent = color.a/255.0f;
            CGContextSetRGBStrokeColor(context,
                                       color.r/255.0f, color.g/255.0f, color.b/255.0f, alphaComponent);

            if (color.a != 255) {
                _outlineComponents[0] = cast(ubyte)(color.r*color.a/255);
                _outlineComponents[1] = cast(ubyte)(color.g*color.a/255);
                _outlineComponents[2] = cast(ubyte)(color.b*color.a/255);
                _outlineComponents[3] = color.a;
            } else {
                _outlineComponents[0] = color.r;
                _outlineComponents[1] = color.g;
                _outlineComponents[2] = color.b;
                _outlineComponents[3] = color.a;
            }
        }

        @property void fillColor(Color color) {
            CGContextSetRGBFillColor(context,
                                     color.r/255.0f, color.g/255.0f, color.b/255.0f, color.a/255.0f);
        }

        void drawImage(int x, int y, Image image, int ulx, int upy, int width, int height) {
		// NotYetImplementedException for upper left/width/height
            auto cgImage = CGBitmapContextCreateImage(image.context);
            auto size = CGSize(CGBitmapContextGetWidth(image.context),
                               CGBitmapContextGetHeight(image.context));
            CGContextDrawImage(context, CGRect(CGPoint(x, y), size), cgImage);
            CGImageRelease(cgImage);
        }

	version(OSXCocoa) {} else // NotYetImplementedException
        void drawPixmap(Sprite image, int x, int y) {
		// FIXME: is this efficient?
            auto cgImage = CGBitmapContextCreateImage(image.context);
            auto size = CGSize(CGBitmapContextGetWidth(image.context),
                               CGBitmapContextGetHeight(image.context));
            CGContextDrawImage(context, CGRect(CGPoint(x, y), size), cgImage);
            CGImageRelease(cgImage);
        }


        void drawText(int x, int y, int x2, int y2, in char[] text, uint alignment) {
		// FIXME: alignment
            if (_outlineComponents[3] != 0) {
                CGContextSaveGState(context);
                auto invAlpha = 1.0f/_outlineComponents[3];
                CGContextSetRGBFillColor(context, _outlineComponents[0]*invAlpha,
                                                  _outlineComponents[1]*invAlpha,
                                                  _outlineComponents[2]*invAlpha,
                                                  _outlineComponents[3]/255.0f);
                CGContextShowTextAtPoint(context, x, y + 12 /* this is cuz this picks baseline but i want bounding box */, text.ptr, text.length);
// auto cfstr = cast(id)createCFString(text);
// objc_msgSend(cfstr, sel_registerName("drawAtPoint:withAttributes:"),
// NSPoint(x, y), null);
// CFRelease(cfstr);
                CGContextRestoreGState(context);
            }
        }

        void drawPixel(int x, int y) {
            auto rawData = CGBitmapContextGetData(context);
            auto width = CGBitmapContextGetWidth(context);
            auto height = CGBitmapContextGetHeight(context);
            auto offset = ((height - y - 1) * width + x) * 4;
            rawData[offset .. offset+4] = _outlineComponents;
        }

        void drawLine(int x1, int y1, int x2, int y2) {
            CGPoint[2] linePoints;
            linePoints[0] = CGPoint(x1, y1);
            linePoints[1] = CGPoint(x2, y2);
            CGContextStrokeLineSegments(context, linePoints.ptr, linePoints.length);
        }

        void drawRectangle(int x, int y, int width, int height) {
            CGContextBeginPath(context);
            auto rect = CGRect(CGPoint(x, y), CGSize(width, height));
            CGContextAddRect(context, rect);
            CGContextDrawPath(context, CGPathDrawingMode.kCGPathFillStroke);
        }

        void drawEllipse(int x1, int y1, int x2, int y2) {
            CGContextBeginPath(context);
            auto rect = CGRect(CGPoint(x1, y1), CGSize(x2-x1, y2-y1));
            CGContextAddEllipseInRect(context, rect);
            CGContextDrawPath(context, CGPathDrawingMode.kCGPathFillStroke);
        }

        void drawArc(int x1, int y1, int width, int height, int start, int finish) {
            // @@@BUG@@@ Does not support elliptic arc (width != height).
            CGContextBeginPath(context);
            CGContextAddArc(context, x1+width*0.5f, y1+height*0.5f, width,
                            start*PI/(180*64), finish*PI/(180*64), 0);
            CGContextDrawPath(context, CGPathDrawingMode.kCGPathFillStroke);
        }

        void drawPolygon(Point[] intPoints) {
            CGContextBeginPath(context);
            auto points = array(map!(CGPoint.fromTuple)(intPoints));
            CGContextAddLines(context, points.ptr, points.length);
            CGContextDrawPath(context, CGPathDrawingMode.kCGPathFillStroke);
        }
    }

    mixin template NativeSimpleWindowImplementation() {
        void createWindow(int width, int height, string title, OpenGlOptions opengl, SimpleWindow parent) {
            synchronized {
                if (NSApp == null) initializeApp();
            }

            auto contentRect = NSRect(NSPoint(0, 0), NSSize(width, height));

            // create the window.
            window = initWithContentRect(alloc("NSWindow"),
                                         contentRect,
                                         NSTitledWindowMask
                                            |NSClosableWindowMask
                                            |NSMiniaturizableWindowMask
                                            |NSResizableWindowMask,
                                         NSBackingStoreBuffered,
                                         true);

            // set the title & move the window to center.
            auto windowTitle = createCFString(title);
            setTitle(window, windowTitle);
            CFRelease(windowTitle);
            center(window);

            // create area to draw on.
            auto colorSpace = CGColorSpaceCreateDeviceRGB();
            drawingContext = CGBitmapContextCreate(null, width, height,
                                                   8, 4*width, colorSpace,
                                                   kCGImageAlphaPremultipliedLast
                                                      |kCGBitmapByteOrder32Big);
            CGColorSpaceRelease(colorSpace);
            CGContextSelectFont(drawingContext, "Lucida Grande", 12.0f, 1);
            auto matrix = CGContextGetTextMatrix(drawingContext);
            matrix.c = -matrix.c;
            matrix.d = -matrix.d;
            CGContextSetTextMatrix(drawingContext, matrix);

            // create the subview that things will be drawn on.
            view = initWithFrame(alloc("SDGraphicsView"), contentRect);
            setContentView(window, view);
            object_setIvar(view, simpleWindowIvar, cast(id)this);
            release(view);

            setBackgroundColor(window, whiteNSColor);
            makeKeyAndOrderFront(window, null);
        }
        void dispose() {
            closeWindow();
            release(window);
        }
        void closeWindow() {
            invalidate(timer);
            .close(window);
        }

        ScreenPainter getPainter() {
		return ScreenPainter(this, this);
	}

        id window;
        id timer;
        id view;
        CGContextRef drawingContext;
    }

    extern(C) {
    private:
        BOOL returnTrue3(id self, SEL _cmd, id app) {
            return true;
        }
        BOOL returnTrue2(id self, SEL _cmd) {
            return true;
        }

        void pulse(id self, SEL _cmd) {
            auto simpleWindow = cast(SimpleWindow)object_getIvar(self, simpleWindowIvar);
            simpleWindow.handlePulse();
            setNeedsDisplay(self, true);
        }
        void drawRect(id self, SEL _cmd, NSRect rect) {
            auto simpleWindow = cast(SimpleWindow)object_getIvar(self, simpleWindowIvar);
            auto curCtx = graphicsPort(currentNSGraphicsContext);
            auto cgImage = CGBitmapContextCreateImage(simpleWindow.drawingContext);
            auto size = CGSize(CGBitmapContextGetWidth(simpleWindow.drawingContext),
                               CGBitmapContextGetHeight(simpleWindow.drawingContext));
            CGContextDrawImage(curCtx, CGRect(CGPoint(0, 0), size), cgImage);
            CGImageRelease(cgImage);
        }
        void keyDown(id self, SEL _cmd, id event) {
            auto simpleWindow = cast(SimpleWindow)object_getIvar(self, simpleWindowIvar);

            // the event may have multiple characters, and we send them all at
            // once.
            if (simpleWindow.handleCharEvent || simpleWindow.handleKeyEvent) {
                auto chars = characters(event);
                auto range = CFRange(0, CFStringGetLength(chars));
                auto buffer = new char[range.length*3];
                long actualLength;
                CFStringGetBytes(chars, range, kCFStringEncodingUTF8, 0, false,
                                 buffer.ptr, cast(int) buffer.length, &actualLength);
                foreach (dchar dc; buffer[0..actualLength]) {
                    if (simpleWindow.handleCharEvent)
                        simpleWindow.handleCharEvent(dc);
		    // NotYetImplementedException
                    //if (simpleWindow.handleKeyEvent)
                        //simpleWindow.handleKeyEvent(KeyEvent(dc)); // FIXME: what about keyUp?
                }
            }

            // the event's 'keyCode' is hardware-dependent. I don't think people
            // will like it. Let's leave it to the native handler.

            // perform the default action.

	    // so the default action is to make a bomp sound and i dont want that
	    // sooooooooo yeah not gonna do that.

            //auto superData = objc_super(self, superclass(self));
            //alias extern(C) void function(objc_super*, SEL, id) T;
            //(cast(T)&objc_msgSendSuper)(&superData, _cmd, event);
        }
    }

    // initialize the app so that it can be interacted with the user.
    // based on http://cocoawithlove.com/2010/09/minimalist-cocoa-programming.html
    private void initializeApp() {
        // push an autorelease pool to avoid leaking.
        init(alloc("NSAutoreleasePool"));

        // create a new NSApp instance
        sharedNSApplication;
        setActivationPolicy(NSApp, NSApplicationActivationPolicyRegular);

        // create the "Quit" menu.
        auto menuBar = init(alloc("NSMenu"));
        auto appMenuItem = init(alloc("NSMenuItem"));
        addItem(menuBar, appMenuItem);
        setMainMenu(NSApp, menuBar);
        release(appMenuItem);
        release(menuBar);

        auto appMenu = init(alloc("NSMenu"));
        auto quitTitle = createCFString("Quit");
        auto q = createCFString("q");
        auto quitItem = initWithTitle(alloc("NSMenuItem"),
                                      quitTitle, sel_registerName("terminate:"), q);
        addItem(appMenu, quitItem);
        setSubmenu(appMenuItem, appMenu);
        release(quitItem);
        release(appMenu);
        CFRelease(q);
        CFRelease(quitTitle);

        // assign a delegate for the application, allow it to quit when the last
        // window is closed.
        auto delegateClass = objc_allocateClassPair(objc_getClass("NSObject"),
                                                    "SDWindowCloseDelegate", 0);
        class_addMethod(delegateClass,
                        sel_registerName("applicationShouldTerminateAfterLastWindowClosed:"),
                        &returnTrue3, "c@:@");
        objc_registerClassPair(delegateClass);

        auto appDelegate = init(alloc("SDWindowCloseDelegate"));
        setDelegate(NSApp, appDelegate);
        activateIgnoringOtherApps(NSApp, true);

        // create a new view that draws the graphics and respond to keyDown
        // events.
        auto viewClass = objc_allocateClassPair(objc_getClass("NSView"),
                                                "SDGraphicsView", (void*).sizeof);
        class_addIvar(viewClass, "simpledisplay_simpleWindow",
                      (void*).sizeof, (void*).alignof, "^v");
        class_addMethod(viewClass, sel_registerName("simpledisplay_pulse"),
                        &pulse, "v@:");
        class_addMethod(viewClass, sel_registerName("drawRect:"),
                        &drawRect, "v@:{NSRect={NSPoint=ff}{NSSize=ff}}");
        class_addMethod(viewClass, sel_registerName("isFlipped"),
                        &returnTrue2, "c@:");
        class_addMethod(viewClass, sel_registerName("acceptsFirstResponder"),
                        &returnTrue2, "c@:");
        class_addMethod(viewClass, sel_registerName("keyDown:"),
                        &keyDown, "v@:@");
        objc_registerClassPair(viewClass);
        simpleWindowIvar = class_getInstanceVariable(viewClass,
                                                     "simpledisplay_simpleWindow");
    }
}

version(without_opengl) {} else
extern(System) nothrow @nogc {
	//enum uint GL_VERSION = 0x1F02;
	//const(char)* glGetString (/*GLenum*/uint);
	version(X11) {
	static if (!SdpyIsUsingIVGLBinds) {

		enum GLX_X_RENDERABLE = 0x8012;
		enum GLX_DRAWABLE_TYPE = 0x8010;
		enum GLX_RENDER_TYPE = 0x8011;
		enum GLX_X_VISUAL_TYPE = 0x22;
		enum GLX_TRUE_COLOR = 0x8002;
		enum GLX_WINDOW_BIT = 0x00000001;
		enum GLX_RGBA_BIT = 0x00000001;
		enum GLX_COLOR_INDEX_BIT = 0x00000002;
		enum GLX_SAMPLE_BUFFERS = 0x186a0;
		enum GLX_SAMPLES = 0x186a1;
		enum GLX_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
		enum GLX_CONTEXT_MINOR_VERSION_ARB = 0x2092;
	}

		// GLX_EXT_swap_control
		alias glXSwapIntervalEXT = void function (Display* dpy, /*GLXDrawable*/Drawable drawable, int interval);
		private __gshared glXSwapIntervalEXT _glx_swapInterval_fn = null;

		//k8: ugly code to prevent warnings when sdpy is compiled into .a
		extern(System) {
			alias glXCreateContextAttribsARB_fna = GLXContext function (Display *dpy, GLXFBConfig config, GLXContext share_context, /*Bool*/int direct, const(int)* attrib_list);
		}
		private __gshared /*glXCreateContextAttribsARB_fna*/void* glXCreateContextAttribsARBFn = cast(void*)1; //HACK!

		// this made public so we don't have to get it again and again
		public bool glXCreateContextAttribsARB_present () {
			if (glXCreateContextAttribsARBFn is cast(void*)1) {
				// get it
				glXCreateContextAttribsARBFn = cast(void*)glbindGetProcAddress("glXCreateContextAttribsARB");
				//{ import core.stdc.stdio; printf("checking glXCreateContextAttribsARB: %shere\n", (glXCreateContextAttribsARBFn !is null ? "".ptr : "not ".ptr)); }
			}
			return (glXCreateContextAttribsARBFn !is null);
		}

		// this made public so we don't have to get it again and again
		public GLXContext glXCreateContextAttribsARB (Display *dpy, GLXFBConfig config, GLXContext share_context, /*Bool*/int direct, const(int)* attrib_list) {
			if (!glXCreateContextAttribsARB_present()) assert(0, "glXCreateContextAttribsARB is not present");
			return (cast(glXCreateContextAttribsARB_fna)glXCreateContextAttribsARBFn)(dpy, config, share_context, direct, attrib_list);
		}

		// extern(C) private __gshared int function(int) glXSwapIntervalSGI; // seems totally redundant to the tohers
		extern(C) private __gshared int function(int) glXSwapIntervalMESA;

		void glxSetVSync (Display* dpy, /*GLXDrawable*/Drawable drawable, bool wait) {
			if (cast(void*)_glx_swapInterval_fn is cast(void*)1) return;
			if (_glx_swapInterval_fn is null) {
				_glx_swapInterval_fn = cast(glXSwapIntervalEXT)glXGetProcAddress("glXSwapIntervalEXT");
				if (_glx_swapInterval_fn is null) {
					_glx_swapInterval_fn = cast(glXSwapIntervalEXT)1;
					return;
				}
				version(sdddd) { import std.stdio; debug writeln("glXSwapIntervalEXT found!"); }
			}

			if(glXSwapIntervalMESA is null) {
				// it seems to require both to actually take effect on many computers
				// idk why
				glXSwapIntervalMESA = cast(typeof(glXSwapIntervalMESA)) glXGetProcAddress("glXSwapIntervalMESA");
				if(glXSwapIntervalMESA is null)
					glXSwapIntervalMESA = cast(typeof(glXSwapIntervalMESA)) 1;
			}

			if(cast(void*) glXSwapIntervalMESA > cast(void*) 1)
				glXSwapIntervalMESA(wait ? 1 : 0);

			_glx_swapInterval_fn(dpy, drawable, (wait ? 1 : 0));
		}
	} else version(Windows) {
	static if (!SdpyIsUsingIVGLBinds) {
	enum GL_TRUE = 1;
	enum GL_FALSE = 0;
	alias int GLint;

	public void* glbindGetProcAddress (const(char)* name) {
		void* res = wglGetProcAddress(name);
		if (res is null) {
			/+
			//{ import core.stdc.stdio; printf("GL: '%s' not found (0)\n", name); }
			import core.sys.windows.windef, core.sys.windows.winbase;
			__gshared HINSTANCE dll = null;
			if (dll is null) {
				dll = LoadLibraryA("opengl32.dll");
				if (dll is null) return null; // <32, but idc
			}
			res = GetProcAddress(dll, name);
			+/
			res = GetProcAddress(gl.libHandle, name);
		}
		//{ import core.stdc.stdio; printf(" GL: '%s' is 0x%08x\n", name, cast(uint)res); }
		return res;
	}
	}

 
 	private __gshared extern(System) BOOL function(int) wglSwapIntervalEXT;
        void wglSetVSync(bool wait) {
		if(wglSwapIntervalEXT is null) {
			wglSwapIntervalEXT = cast(typeof(wglSwapIntervalEXT)) wglGetProcAddress("wglSwapIntervalEXT");
			if(wglSwapIntervalEXT is null)
				wglSwapIntervalEXT = cast(typeof(wglSwapIntervalEXT)) 1;
		}
		if(cast(void*) wglSwapIntervalEXT is cast(void*) 1)
			return;

		wglSwapIntervalEXT(wait ? 1 : 0);
	}

		enum WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
		enum WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
		enum WGL_CONTEXT_LAYER_PLANE_ARB = 0x2093;
		enum WGL_CONTEXT_FLAGS_ARB = 0x2094;
		enum WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;

		enum WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001;
		enum WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;

		enum WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
		enum WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;

		alias wglCreateContextAttribsARB_fna = HGLRC function (HDC hDC, HGLRC hShareContext, const(int)* attribList);
		__gshared wglCreateContextAttribsARB_fna wglCreateContextAttribsARB = null;

		void wglInitOtherFunctions () {
			if (wglCreateContextAttribsARB is null) {
				wglCreateContextAttribsARB = cast(wglCreateContextAttribsARB_fna)glbindGetProcAddress("wglCreateContextAttribsARB");
			}
		}
	}

	static if (!SdpyIsUsingIVGLBinds) {

	interface GL {
		extern(System) @nogc nothrow:

		void glGetIntegerv(int, void*);
		void glMatrixMode(int);
		void glPushMatrix();
		void glLoadIdentity();
		void glOrtho(double, double, double, double, double, double);
		void glFrustum(double, double, double, double, double, double);

		void glPopMatrix();
		void glEnable(int);
		void glDisable(int);
		void glClear(int);
		void glBegin(int);
		void glVertex2f(float, float);
		void glVertex3f(float, float, float);
		void glEnd();
		void glColor3b(byte, byte, byte);
		void glColor3ub(ubyte, ubyte, ubyte);
		void glColor4b(byte, byte, byte, byte);
		void glColor4ub(ubyte, ubyte, ubyte, ubyte);
		void glColor3i(int, int, int);
		void glColor3ui(uint, uint, uint);
		void glColor4i(int, int, int, int);
		void glColor4ui(uint, uint, uint, uint);
		void glColor3f(float, float, float);
		void glColor4f(float, float, float, float);
		void glTranslatef(float, float, float);
		void glScalef(float, float, float);
		version(X11) {
			void glSecondaryColor3b(byte, byte, byte);
			void glSecondaryColor3ub(ubyte, ubyte, ubyte);
			void glSecondaryColor3i(int, int, int);
			void glSecondaryColor3ui(uint, uint, uint);
			void glSecondaryColor3f(float, float, float);
		}

		void glDrawElements(int, int, int, void*);

		void glRotatef(float, float, float, float);

		uint glGetError();

		void glDeleteTextures(int, uint*);


		void glRasterPos2i(int, int);
		void glDrawPixels(int, int, uint, uint, void*);
		void glClearColor(float, float, float, float);


		void glPixelStorei(uint, int);

		void glGenTextures(uint, uint*);
		void glBindTexture(int, int);
		void glTexParameteri(uint, uint, int);
		void glTexParameterf(uint/*GLenum*/ target, uint/*GLenum*/ pname, float param);
		void glTexImage2D(int, int, int, int, int, int, int, int, in void*);
		void glTexSubImage2D(uint/*GLenum*/ target, int level, int xoffset, int yoffset,
			/*GLsizei*/int width, /*GLsizei*/int height,
			uint/*GLenum*/ format, uint/*GLenum*/ type, in void* pixels);
		void glTexEnvf(uint/*GLenum*/ target, uint/*GLenum*/ pname, float param);

		void glLineWidth(int);


		void glTexCoord2f(float, float);
		void glVertex2i(int, int);
		void glBlendFunc (int, int);
		void glDepthFunc (int);
		void glViewport(int, int, int, int);

		void glClearDepth(double);

		void glReadBuffer(uint);
		void glReadPixels(int, int, int, int, int, int, void*);

		void glFlush();
		void glFinish();

		version(Windows) {
			BOOL wglCopyContext(HGLRC, HGLRC, UINT);
			HGLRC wglCreateContext(HDC);
			HGLRC wglCreateLayerContext(HDC, int);
			BOOL wglDeleteContext(HGLRC);
			BOOL wglDescribeLayerPlane(HDC, int, int, UINT, LPLAYERPLANEDESCRIPTOR);
			HGLRC wglGetCurrentContext();
			HDC wglGetCurrentDC();
			int wglGetLayerPaletteEntries(HDC, int, int, int, COLORREF*);
			PROC wglGetProcAddress(LPCSTR);
			BOOL wglMakeCurrent(HDC, HGLRC);
			BOOL wglRealizeLayerPalette(HDC, int, BOOL);
			int wglSetLayerPaletteEntries(HDC, int, int, int, const(COLORREF)*);
			BOOL wglShareLists(HGLRC, HGLRC);
			BOOL wglSwapLayerBuffers(HDC, UINT);
			BOOL wglUseFontBitmapsA(HDC, DWORD, DWORD, DWORD);
			BOOL wglUseFontBitmapsW(HDC, DWORD, DWORD, DWORD);
			BOOL wglUseFontOutlinesA(HDC, DWORD, DWORD, DWORD, FLOAT, FLOAT, int, LPGLYPHMETRICSFLOAT);
			BOOL wglUseFontOutlinesW(HDC, DWORD, DWORD, DWORD, FLOAT, FLOAT, int, LPGLYPHMETRICSFLOAT);
		}

	}

	interface GL3 {
		extern(System) @nogc nothrow:

		void glGenVertexArrays(GLsizei, GLuint*);
		void glBindVertexArray(GLuint);
		void glDeleteVertexArrays(GLsizei, const(GLuint)*);
		void glGenerateMipmap(GLenum);
		void glBufferSubData(GLenum, GLintptr, GLsizeiptr, const(GLvoid)*);
		void glStencilMask(GLuint);
		void glStencilFunc(GLenum, GLint, GLuint);
		void glGetShaderInfoLog(GLuint, GLsizei, GLsizei*, GLchar*);
		void glGetProgramInfoLog(GLuint, GLsizei, GLsizei*, GLchar*);
		GLuint glCreateProgram();
		GLuint glCreateShader(GLenum);
		void glShaderSource(GLuint, GLsizei, const(GLchar*)*, const(GLint)*);
		void glCompileShader(GLuint);
		void glGetShaderiv(GLuint, GLenum, GLint*);
		void glAttachShader(GLuint, GLuint);
		void glBindAttribLocation(GLuint, GLuint, const(GLchar)*);
		void glLinkProgram(GLuint);
		void glGetProgramiv(GLuint, GLenum, GLint*);
		void glDeleteProgram(GLuint);
		void glDeleteShader(GLuint);
		GLint glGetUniformLocation(GLuint, const(GLchar)*);
		void glGenBuffers(GLsizei, GLuint*);
		void glUniform4fv(GLint, GLsizei, const(GLfloat)*);
		void glUniform4f(GLint, float, float, float, float);
		void glColorMask(GLboolean, GLboolean, GLboolean, GLboolean);
		void glStencilOpSeparate(GLenum, GLenum, GLenum, GLenum);
		void glDrawArrays(GLenum, GLint, GLsizei);
		void glStencilOp(GLenum, GLenum, GLenum);
		void glUseProgram(GLuint);
		void glCullFace(GLenum);
		void glFrontFace(GLenum);
		void glActiveTexture(GLenum);
		void glBindBuffer(GLenum, GLuint);
		void glBufferData(GLenum, GLsizeiptr, const(void)*, GLenum);
		void glEnableVertexAttribArray(GLuint);
		void glVertexAttribPointer(GLuint, GLint, GLenum, GLboolean, GLsizei, const(void)*);
		void glUniform1i(GLint, GLint);
		void glUniform2fv(GLint, GLsizei, const(GLfloat)*);
		void glDisableVertexAttribArray(GLuint);
		void glDeleteBuffers(GLsizei, const(GLuint)*);
		void glBlendFuncSeparate(GLenum, GLenum, GLenum, GLenum);
		void glLogicOp (GLenum opcode);
		void glFramebufferTexture2D (GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
		void glDeleteFramebuffers (GLsizei n, const(GLuint)* framebuffers);
		void glGenFramebuffers (GLsizei n, GLuint* framebuffers);
		GLenum glCheckFramebufferStatus (GLenum target);
		void glBindFramebuffer (GLenum target, GLuint framebuffer);
	}

	interface GL4 {
		extern(System) @nogc nothrow:

		void glTextureSubImage2D(uint texture, int level, int xoffset, int yoffset,
			/*GLsizei*/int width, /*GLsizei*/int height,
			uint/*GLenum*/ format, uint/*GLenum*/ type, in void* pixels);
	}

	interface GLU {
		extern(System) @nogc nothrow:

		void gluLookAt(double, double, double, double, double, double, double, double, double);
		void gluPerspective(double, double, double, double);

		char* gluErrorString(uint);
	}


	enum GL_RED = 0x1903;
	enum GL_ALPHA = 0x1906;

	enum uint GL_FRONT = 0x0404;

	enum uint GL_BLEND = 0x0be2;
	enum uint GL_LEQUAL = 0x0203;


	enum uint GL_RGB = 0x1907;
	enum uint GL_BGRA = 0x80e1;
	enum uint GL_RGBA = 0x1908;
	enum uint GL_TEXTURE_2D =   0x0DE1;
	enum uint GL_TEXTURE_MIN_FILTER = 0x2801;
	enum uint GL_NEAREST = 0x2600;
	enum uint GL_LINEAR = 0x2601;
	enum uint GL_TEXTURE_MAG_FILTER = 0x2800;
	enum uint GL_TEXTURE_WRAP_S = 0x2802;
	enum uint GL_TEXTURE_WRAP_T = 0x2803;
	enum uint GL_REPEAT = 0x2901;
	enum uint GL_CLAMP = 0x2900;
	enum uint GL_CLAMP_TO_EDGE = 0x812F;
	enum uint GL_CLAMP_TO_BORDER = 0x812D;
	enum uint GL_DECAL = 0x2101;
	enum uint GL_MODULATE = 0x2100;
	enum uint GL_TEXTURE_ENV = 0x2300;
	enum uint GL_TEXTURE_ENV_MODE = 0x2200;
	enum uint GL_REPLACE = 0x1E01;
	enum uint GL_LIGHTING = 0x0B50;
	enum uint GL_DITHER = 0x0BD0;

	enum uint GL_NO_ERROR = 0;



	enum int GL_VIEWPORT = 0x0BA2;
	enum int GL_MODELVIEW = 0x1700;
	enum int GL_TEXTURE = 0x1702;
	enum int GL_PROJECTION = 0x1701;
	enum int GL_DEPTH_TEST = 0x0B71;

	enum int GL_COLOR_BUFFER_BIT = 0x00004000;
	enum int GL_ACCUM_BUFFER_BIT = 0x00000200;
	enum int GL_DEPTH_BUFFER_BIT = 0x00000100;
	enum uint GL_STENCIL_BUFFER_BIT = 0x00000400;

	enum int GL_POINTS = 0x0000;
	enum int GL_LINES =  0x0001;
	enum int GL_LINE_LOOP = 0x0002;
	enum int GL_LINE_STRIP = 0x0003;
	enum int GL_TRIANGLES = 0x0004;
	enum int GL_TRIANGLE_STRIP = 5;
	enum int GL_TRIANGLE_FAN = 6;
	enum int GL_QUADS = 7;
	enum int GL_QUAD_STRIP = 8;
	enum int GL_POLYGON = 9;

	alias GLvoid = void;
	alias GLboolean = ubyte;
	alias GLuint = uint;
	alias GLenum = uint;
	alias GLchar = char;
	alias GLsizei = int;
	alias GLfloat = float;
	alias GLintptr = size_t;
	alias GLsizeiptr = ptrdiff_t;


	enum uint GL_INVALID_ENUM = 0x0500;

	enum uint GL_ZERO = 0;
	enum uint GL_ONE = 1;

	enum uint GL_BYTE = 0x1400;
	enum uint GL_UNSIGNED_BYTE = 0x1401;
	enum uint GL_SHORT = 0x1402;
	enum uint GL_UNSIGNED_SHORT = 0x1403;
	enum uint GL_INT = 0x1404;
	enum uint GL_UNSIGNED_INT = 0x1405;
	enum uint GL_FLOAT = 0x1406;
	enum uint GL_2_BYTES = 0x1407;
	enum uint GL_3_BYTES = 0x1408;
	enum uint GL_4_BYTES = 0x1409;
	enum uint GL_DOUBLE = 0x140A;

	enum uint GL_STREAM_DRAW = 0x88E0;

	enum uint GL_CCW = 0x0901;

	enum uint GL_STENCIL_TEST = 0x0B90;
	enum uint GL_SCISSOR_TEST = 0x0C11;

	enum uint GL_EQUAL = 0x0202;
	enum uint GL_NOTEQUAL = 0x0205;

	enum uint GL_ALWAYS = 0x0207;
	enum uint GL_KEEP = 0x1E00;

	enum uint GL_INCR = 0x1E02;

	enum uint GL_INCR_WRAP = 0x8507;
	enum uint GL_DECR_WRAP = 0x8508;

	enum uint GL_CULL_FACE = 0x0B44;
	enum uint GL_BACK = 0x0405;

	enum uint GL_FRAGMENT_SHADER = 0x8B30;
	enum uint GL_VERTEX_SHADER = 0x8B31;

	enum uint GL_COMPILE_STATUS = 0x8B81;
	enum uint GL_LINK_STATUS = 0x8B82;

	enum uint GL_ELEMENT_ARRAY_BUFFER = 0x8893;

	enum uint GL_STATIC_DRAW = 0x88E4;

	enum uint GL_UNPACK_ALIGNMENT = 0x0CF5;
	enum uint GL_UNPACK_ROW_LENGTH = 0x0CF2;
	enum uint GL_UNPACK_SKIP_PIXELS = 0x0CF4;
	enum uint GL_UNPACK_SKIP_ROWS = 0x0CF3;

	enum uint GL_GENERATE_MIPMAP = 0x8191;
	enum uint GL_LINEAR_MIPMAP_LINEAR = 0x2703;

	enum uint GL_TEXTURE0 = 0x84C0U;
	enum uint GL_TEXTURE1 = 0x84C1U;

	enum uint GL_ARRAY_BUFFER = 0x8892;

	enum uint GL_SRC_COLOR = 0x0300;
	enum uint GL_ONE_MINUS_SRC_COLOR = 0x0301;
	enum uint GL_SRC_ALPHA = 0x0302;
	enum uint GL_ONE_MINUS_SRC_ALPHA = 0x0303;
	enum uint GL_DST_ALPHA = 0x0304;
	enum uint GL_ONE_MINUS_DST_ALPHA = 0x0305;
	enum uint GL_DST_COLOR = 0x0306;
	enum uint GL_ONE_MINUS_DST_COLOR = 0x0307;
	enum uint GL_SRC_ALPHA_SATURATE = 0x0308;

	enum uint GL_INVERT = 0x150AU;

	enum uint GL_DEPTH_STENCIL = 0x84F9U;
	enum uint GL_UNSIGNED_INT_24_8 = 0x84FAU;

	enum uint GL_FRAMEBUFFER = 0x8D40U;
	enum uint GL_COLOR_ATTACHMENT0 = 0x8CE0U;
	enum uint GL_DEPTH_STENCIL_ATTACHMENT = 0x821AU;

	enum uint GL_FRAMEBUFFER_COMPLETE = 0x8CD5U;
	enum uint GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT = 0x8CD6U;
	enum uint GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT = 0x8CD7U;
	enum uint GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS = 0x8CD9U;
	enum uint GL_FRAMEBUFFER_UNSUPPORTED = 0x8CDDU;

	enum uint GL_COLOR_LOGIC_OP = 0x0BF2U;
	enum uint GL_CLEAR = 0x1500U;
	enum uint GL_COPY = 0x1503U;
	enum uint GL_XOR = 0x1506U;

	enum uint GL_FRAMEBUFFER_BINDING = 0x8CA6U;

	enum uint GL_TEXTURE_LOD_BIAS = 0x8501;

	}
}

/++
	History:
		Added September 10, 2021. Previously it would have listed openGlLibrariesSuccessfullyLoaded as false if it couldn't find GLU but really opengl3 works fine without it so I didn't want to keep it required anymore.
+/
__gshared bool gluSuccessfullyLoaded = true;

version(without_opengl) {} else {
static if(!SdpyIsUsingIVGLBinds) {
	version(Windows) {
		mixin DynamicLoad!(GL, "opengl32", 1, openGlLibrariesSuccessfullyLoaded) gl;
		mixin DynamicLoad!(GLU, "glu32", 1, gluSuccessfullyLoaded) glu;
	} else {
		mixin DynamicLoad!(GL, "GL", 1, openGlLibrariesSuccessfullyLoaded) gl;
		mixin DynamicLoad!(GLU, "GLU", 3, gluSuccessfullyLoaded) glu;
	}
	mixin DynamicLoadSupplementalOpenGL!(GL3) gl3;


	shared static this() {
		gl.loadDynamicLibrary();

		// FIXME: this is NOT actually required and should NOT fail if it is not loaded
		// unless those functions are actually used
		// go to mark b openGlLibrariesSuccessfullyLoaded = false;
		glu.loadDynamicLibrary();
	}
}
}

/++
	Convenience method for converting D arrays to opengl buffer data

	I would LOVE to overload it with the original glBufferData, but D won't
	let me since glBufferData is a function pointer :(

	Added: August 25, 2020 (version 8.5)
+/
version(without_opengl) {} else
void glBufferDataSlice(GLenum target, const(void[]) data, GLenum usage) {
	glBufferData(target, data.length, data.ptr, usage);
}

/+
/++
	A matrix for simple uses that easily integrates with [OpenGlShader].

	Might not be useful to you since it only as some simple functions and
	probably isn't that fast.

	Note it uses an inline static array for its storage, so copying it
	may be expensive.
+/
struct BasicMatrix(int columns, int rows, T = float) {
	import core.stdc.math;

	T[columns * rows] data = 0.0;

	/++
		Basic operations that operate *in place*.
	+/
	void translate() {

	}

	/// ditto
	void scale() {

	}

	/// ditto
	void rotate() {

	}

	/++

	+/
	static if(columns == rows)
	static BasicMatrix identity() {
		BasicMatrix m;
		foreach(i; 0 .. columns)
			data[0 + i + i * columns] = 1.0;
		return m;
	}

	static BasicMatrix ortho() {
		return BasicMatrix.init;
	}
}
+/

/++
	Convenience class for using opengl shaders.

	Ensure that you've loaded opengl 3+ and set your active
	context before trying to use this.

	Added: August 25, 2020 (version 8.5)
+/
version(without_opengl) {} else
final class OpenGlShader {
	private int shaderProgram_;
	private @property void shaderProgram(int a) {
		shaderProgram_ = a;
	}
	/// Get the program ID for use in OpenGL functions.
	public @property int shaderProgram() {
		return shaderProgram_;
	}

	/++

	+/
	static struct Source {
		uint type; /// GL_FRAGMENT_SHADER, GL_VERTEX_SHADER, etc.
		string code; ///
	}

	/++
		Helper method to just compile some shader code and check for errors
		while you do glCreateShader, etc. on the outside yourself.

		This just does `glShaderSource` and `glCompileShader` for the given code.

		If you the OpenGlShader class constructor, you never need to call this yourself.
	+/
	static void compile(int sid, Source code) {
		const(char)*[1] buffer;
		int[1] lengthBuffer;

		buffer[0] = code.code.ptr;
		lengthBuffer[0] = cast(int) code.code.length;

		glShaderSource(sid, 1, buffer.ptr, lengthBuffer.ptr);
		glCompileShader(sid);

		int success;
		glGetShaderiv(sid, GL_COMPILE_STATUS, &success);
		if(!success) {
			char[512] info;
			int len;
			glGetShaderInfoLog(sid, info.length, &len, info.ptr);

			throw new Exception("Shader compile failure: " ~ cast(immutable) info[0 .. len]);
		}
	}

	/++
		Calls `glLinkProgram` and throws if error a occurs.

		If you the OpenGlShader class constructor, you never need to call this yourself.
	+/
	static void link(int shaderProgram) {
		glLinkProgram(shaderProgram);
		int success;
		glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success);
		if(!success) {
			char[512] info;
			int len;
			glGetProgramInfoLog(shaderProgram, info.length, &len, info.ptr);

			throw new Exception("Shader link failure: " ~ cast(immutable) info[0 .. len]);
		}
	}

	/++
		Constructs the shader object by calling `glCreateProgram`, then
		compiling each given [Source], and finally, linking them together.

		Throws: on compile or link failure.
	+/
	this(Source[] codes...) {
		shaderProgram = glCreateProgram();

		int[16] shadersBufferStack;

		int[] shadersBuffer = codes.length <= shadersBufferStack.length ? 
			shadersBufferStack[0 .. codes.length] :
			new int[](codes.length);

		foreach(idx, code; codes) {
			shadersBuffer[idx] = glCreateShader(code.type);

			compile(shadersBuffer[idx], code);

			glAttachShader(shaderProgram, shadersBuffer[idx]);
		}

		link(shaderProgram);

		foreach(s; shadersBuffer)
			glDeleteShader(s);
	}

	/// Calls `glUseProgram(this.shaderProgram)`
	void use() {
		glUseProgram(this.shaderProgram);
	}

	/// Deletes the program.
	void delete_() {
		glDeleteProgram(shaderProgram);
		shaderProgram = 0;
	}

	/++
		[OpenGlShader.uniforms].name gives you one of these.

		You can get the id out of it or just assign
	+/
	static struct Uniform {
		/// the id passed to glUniform*
		int id;

		/// Assigns the 4 floats. You will probably have to call this via the .opAssign name
		void opAssign(float x, float y, float z, float w) {
			glUniform4f(id, x, y, z, w);
		}
	}

	static struct UniformsHelper {
		OpenGlShader _shader;

		@property Uniform opDispatch(string name)() {
			auto i = glGetUniformLocation(_shader.shaderProgram, name.ptr);
			if(i == -1)
				throw new Exception("Could not find uniform " ~ name);
			return Uniform(i);
		}
	}

	/++
		Gives access to the uniforms through dot access.
		`OpenGlShader.Uniform = shader.uniforms.foo; // calls glGetUniformLocation(this, "foo");
	+/
	@property UniformsHelper uniforms() { return UniformsHelper(this); }
}

version(linux) {
	version(with_eventloop) {} else {
		private int epollFd = -1;
		void prepareEventLoop() {
			if(epollFd != -1)
				return; // already initialized, no need to do it again
			import ep = core.sys.linux.epoll;

			epollFd = ep.epoll_create1(ep.EPOLL_CLOEXEC);
			if(epollFd == -1)
				throw new Exception("epoll create failure");
		}
	}
} else version(Posix) {
	void prepareEventLoop() {}
}

version(X11) {
	import core.stdc.locale : LC_ALL; // rdmd fix
	__gshared bool sdx_isUTF8Locale;

	// This whole crap is used to initialize X11 locale, so that you can use XIM methods later.
	// Yes, there are people with non-utf locale (it's me, Ketmar!), but XIM (composing) will
	// not work right if app/X11 locale is not utf. This sux. That's why all that "utf detection"
	// anal magic is here. I (Ketmar) hope you like it.
	// We will use `sdx_isUTF8Locale` on XIM creation to enforce UTF-8 locale, so XCompose will
	// always return correct unicode symbols. The detection is here 'cause user can change locale
	// later.

	// NOTE: IT IS VERY IMPORTANT THAT THIS BE THE LAST STATIC CTOR OF THE FILE since it tests librariesSuccessfullyLoaded
	shared static this () {
		if(!librariesSuccessfullyLoaded)
			return;

		import core.stdc.locale : setlocale, LC_ALL, LC_CTYPE;

		// this doesn't hurt; it may add some locking, but the speed is still
		// allows doing 60 FPS videogames; also, ignore the result, as most
		// users will probably won't do mulththreaded X11 anyway (and I (ketmar)
		// never seen this failing).
		if (XInitThreads() == 0) { import core.stdc.stdio; fprintf(stderr, "XInitThreads() failed!\n"); }

		setlocale(LC_ALL, "");
		// check if out locale is UTF-8
		auto lct = setlocale(LC_CTYPE, null);
		if (lct is null) {
			sdx_isUTF8Locale = false;
		} else {
			for (size_t idx = 0; lct[idx] && lct[idx+1] && lct[idx+2]; ++idx) {
				if ((lct[idx+0] == 'u' || lct[idx+0] == 'U') &&
						(lct[idx+1] == 't' || lct[idx+1] == 'T') &&
						(lct[idx+2] == 'f' || lct[idx+2] == 'F'))
				{
					sdx_isUTF8Locale = true;
					break;
				}
			}
		}
		//{ import core.stdc.stdio : stderr, fprintf; fprintf(stderr, "UTF8: %s\n", sdx_isUTF8Locale ? "tan".ptr : "ona".ptr); }
	}
}

class ExperimentalTextComponent2 {
	/+
		Stage 1: get it working monospace
		Stage 2: use proportional font
		Stage 3: allow changes in inline style
		Stage 4: allow new fonts and sizes in the middle
		Stage 5: optimize gap buffer
		Stage 6: optimize layout
		Stage 7: word wrap
		Stage 8: justification
		Stage 9: editing, selection, etc.

			Operations:
				insert text
				overstrike text
				select
				cut
				modify
	+/

	/++
		It asks for a window so it can translate abstract font sizes to actual on-screen values depending on the window's current dpi, scaling settings, etc.
	+/
	this(SimpleWindow window) {
		this.window = window;
	}

	private SimpleWindow window;


	/++
		When you render a [ComponentInFlow], it returns an arbitrary number of these interfaces
		representing the internal parts. The first pass is focused on the x parameter, then the
		renderer is responsible for going back to the parts in the current line and calling
		adjustDownForAscent to change the y params.
	+/
	static interface ComponentRenderHelper {

		/+
			When you do an edit, possibly stuff on the same line previously need to move (to adjust
			the baseline), stuff subsequent needs to move (adjust x) and possibly stuff below needs
			to move (adjust y to make room for new line) until you get back to the same position,
			then you can stop - if one thing is unchanged, nothing after it is changed too.

			Word wrap might change this as if can rewrap tons of stuff, but the same idea applies,
			once you reach something that is unchanged, you can stop.
		+/

		void adjustDownForAscent(int amount); // at the end of the line it needs to do these

		int ascent() const;
		int descent() const;

		int advance() const;

		bool endsWithExplititLineBreak() const;
	}

	static interface RenderResult {
		/++
			This is responsible for using what space is left (your object is responsible for keeping its own state after getting it updated from [repositionForNextLine]) and not going over if at all possible. If you can word wrap, you should when space is out. Otherwise, you can keep going if it means overflow hidden or scroll.
		+/
		void popFront();
		@property bool empty() const;
		@property ComponentRenderHelper front() const;

		void repositionForNextLine(Point baseline, int availableWidth);
	}

	static interface ComponentInFlow {
		void draw(ScreenPainter painter);
		//RenderResult render(Point baseline, int availableWidth); // FIXME: it needs to be able to say "my cache is good, nothing different"

		bool startsWithExplicitLineBreak() const;
	}

	static class TextFlowComponent : ComponentInFlow {
		bool startsWithExplicitLineBreak() const { return false; } // FIXME: if it is block this can return true

		Color foreground;
		Color background;

		OperatingSystemFont font; // should NEVER be null

		ubyte attributes; // underline, strike through, display on new block

		version(Windows)
			const(wchar)[] content;
		else
			const(char)[] content; // this should NEVER have a newline, except at the end

		RenderedComponent[] rendered; // entirely controlled by [rerender]

		// could prolly put some spacing around it too like margin / padding

		this(Color f, Color b, OperatingSystemFont font, ubyte attr, const(char)[] c)
			in { assert(font !is null);
			     assert(!font.isNull); }
			do
		{
			this.foreground = f;
			this.background = b;
			this.font = font;

			this.attributes = attr;
			version(Windows) {
				auto conversionFlags = 0;//WindowsStringConversionFlags.convertNewLines;
				auto sz = sizeOfConvertedWstring(c, conversionFlags);
				auto buffer = new wchar[](sz);
				this.content = makeWindowsString(c, buffer, conversionFlags);
			} else {
				this.content = c.dup;
			}
		}

		void draw(ScreenPainter painter) {
			painter.setFont(this.font);
			painter.outlineColor = this.foreground;
			painter.fillColor = Color.transparent;
			foreach(rendered; this.rendered) {
				// the component works in term of baseline,
				// but the painter works in term of upper left bounding box
				// so need to translate that

				if(this.background.a) {
					painter.fillColor = this.background;
					painter.outlineColor = this.background;

					painter.drawRectangle(Point(rendered.startX, rendered.startY - this.font.ascent), Size(rendered.width, this.font.height));

					painter.outlineColor = this.foreground;
					painter.fillColor = Color.transparent;
				}

				painter.drawText(Point(rendered.startX, rendered.startY - this.font.ascent), rendered.slice);

				// FIXME: strike through, underline, highlight selection, etc.
			}
		}
	}

	// I could split the parts into words on render
	// for easier word-wrap, each one being an unbreakable "inline-block"
	private TextFlowComponent[] parts;
	private int needsRerenderFrom;

	void addPart(Color f, Color b, OperatingSystemFont font, ubyte attr, const(char)[] c) {
		// FIXME: needsRerenderFrom. Basically if the bounding box and baseline is the same as the previous thing, it can prolly just stop.
		parts ~= new TextFlowComponent(f, b, font, attr, c);
	}

	static struct RenderedComponent {
		int startX;
		int startY;
		short width;
		// height is always from the containing part's font. This saves some space and means recalculations need not continue past the current line, unless a new part is added with a different font!
		// for individual chars in here you've gotta process on demand
		version(Windows)
			const(wchar)[] slice;
		else
			const(char)[] slice;
	}


	void rerender(Rectangle boundingBox) {
		Point baseline = boundingBox.upperLeft;

		this.boundingBox.left = boundingBox.left;
		this.boundingBox.top = boundingBox.top;

		auto remainingParts = parts;

		int largestX;


		foreach(part; parts)
			part.font.prepareContext(window);
		scope(exit)
		foreach(part; parts)
			part.font.releaseContext();

		calculateNextLine:

		int nextLineHeight = 0;
		int nextBiggestDescent = 0;

		foreach(part; remainingParts) {
			auto height = part.font.ascent;
			if(height > nextLineHeight)
				nextLineHeight = height;
			if(part.font.descent > nextBiggestDescent)
				nextBiggestDescent = part.font.descent;
			if(part.content.length && part.content[$-1] == '\n')
				break;
		}

		baseline.y += nextLineHeight;
		auto lineStart = baseline;

		while(remainingParts.length) {
			remainingParts[0].rendered = null;

			bool eol;
			if(remainingParts[0].content.length && remainingParts[0].content[$-1] == '\n')
				eol = true;

			// FIXME: word wrap
			auto font = remainingParts[0].font;
			auto slice = remainingParts[0].content[0 .. $ - (eol ? 1 : 0)];
			auto width = font.stringWidth(slice, window);
			remainingParts[0].rendered ~= RenderedComponent(baseline.x, baseline.y, cast(short) width, slice);

			remainingParts = remainingParts[1 .. $];
			baseline.x += width;

			if(eol) {
				baseline.y += nextBiggestDescent;
				if(baseline.x > largestX)
					largestX = baseline.x;
				baseline.x = lineStart.x;
				goto calculateNextLine;
			}
		}

		if(baseline.x > largestX)
			largestX = baseline.x;

		this.boundingBox.right = largestX;
		this.boundingBox.bottom = baseline.y;
	}

	// you must call rerender first!
	void draw(ScreenPainter painter) {
		foreach(part; parts) {
			part.draw(painter);
		}
	}

	struct IdentifyResult {
		TextFlowComponent part;
		int charIndexInPart;
		int totalCharIndex = -1; // if this is -1, it just means the end

		Rectangle boundingBox;
	}

	IdentifyResult identify(Point pt, bool exact = false) {
		if(parts.length == 0)
			return IdentifyResult(null, 0);

		if(pt.y < boundingBox.top) {
			if(exact)
				return IdentifyResult(null, 1);
			return IdentifyResult(parts[0], 0);
		}
		if(pt.y > boundingBox.bottom) {
			if(exact)
				return IdentifyResult(null, 2);
			return IdentifyResult(parts[$-1], cast(int) parts[$-1].content.length);
		}

		int tci = 0;

		// I should probably like binary search this or something...
		foreach(ref part; parts) {
			foreach(rendered; part.rendered) {
				auto rect = Rectangle(rendered.startX, rendered.startY - part.font.ascent, rendered.startX + rendered.width, rendered.startY + part.font.descent);
				if(rect.contains(pt)) {
					auto x = pt.x - rendered.startX;
					auto estimatedIdx = x / part.font.averageWidth;

					if(estimatedIdx < 0)
						estimatedIdx = 0;

					if(estimatedIdx > rendered.slice.length)
						estimatedIdx = cast(int) rendered.slice.length;

					int idx;
					int x1, x2;
					if(part.font.isMonospace) {
						auto w = part.font.averageWidth;
						if(!exact && x > (estimatedIdx + 1) * w)
							return IdentifyResult(null, 4);
						idx = estimatedIdx;
						x1 = idx * w;
						x2 = (idx + 1) * w;
					} else {
						idx = estimatedIdx;

						part.font.prepareContext(window);
						scope(exit) part.font.releaseContext();

						// int iterations;

						while(true) {
							// iterations++;
							x1 = idx ? part.font.stringWidth(rendered.slice[0 .. idx - 1]) : 0;
							x2 = part.font.stringWidth(rendered.slice[0 .. idx]); // should be the maximum since `averageWidth` kinda lies.

							x1 += rendered.startX;
							x2 += rendered.startX;

							if(pt.x < x1) {
								if(idx == 0) {
									if(exact)
										return IdentifyResult(null, 6);
									else
										break;
								}
								idx--;
							} else if(pt.x > x2) {
								idx++;
								if(idx > rendered.slice.length) {
									if(exact)
										return IdentifyResult(null, 5);
									else
										break;
								}
							} else if(pt.x >= x1 && pt.x <= x2) {
								if(idx)
									idx--; // point it at the original index
								break; // we fit
							}
						}

						// import std.stdio; writeln(iterations)
					}


					return IdentifyResult(part, idx, tci + idx, Rectangle(x1, rect.top, x2, rect.bottom)); // FIXME: utf-8?
				}
			}
			tci += cast(int) part.content.length; // FIXME: utf-8?
		}
		return IdentifyResult(null, 3);
	}

	Rectangle boundingBox; // only set after [rerender]

	// text will be positioned around the exclusion zone
	static struct ExclusionZone {

	}

	ExclusionZone[] exclusionZones;
}


// Don't use this yet. When I'm happy with it, I will move it to the
// regular module namespace.
mixin template ExperimentalTextComponent() {

static:

	alias Rectangle = arsd.color.Rectangle;

	struct ForegroundColor {
		Color color;
		alias color this;

		this(Color c) {
			color = c;
		}

		this(int r, int g, int b, int a = 255) {
			color = Color(r, g, b, a);
		}

		static ForegroundColor opDispatch(string s)() if(__traits(compiles, ForegroundColor(mixin("Color." ~ s)))) {
			return ForegroundColor(mixin("Color." ~ s));
		}
	}

	struct BackgroundColor {
		Color color;
		alias color this;

		this(Color c) {
			color = c;
		}

		this(int r, int g, int b, int a = 255) {
			color = Color(r, g, b, a);
		}

		static BackgroundColor opDispatch(string s)() if(__traits(compiles, BackgroundColor(mixin("Color." ~ s)))) {
			return BackgroundColor(mixin("Color." ~ s));
		}
	}

	static class InlineElement {
		string text;

		BlockElement containingBlock;

		Color color = Color.black;
		Color backgroundColor = Color.transparent;
		ushort styles;

		string font;
		int fontSize;

		int lineHeight;

		void* identifier;

		Rectangle boundingBox;
		int[] letterXs; // FIXME: maybe i should do bounding boxes for every character

		bool isMergeCompatible(InlineElement other) {
			return
				containingBlock is other.containingBlock &&
				color == other.color &&
				backgroundColor == other.backgroundColor &&
				styles == other.styles &&
				font == other.font &&
				fontSize == other.fontSize &&
				lineHeight == other.lineHeight &&
				true;
		}

		int xOfIndex(size_t index) {
			if(index < letterXs.length)
				return letterXs[index];
			else
				return boundingBox.right;
		}

		InlineElement clone() {
			auto ie = new InlineElement();
			ie.tupleof = this.tupleof;
			return ie;
		}

		InlineElement getPreviousInlineElement() {
			InlineElement prev = null;
			foreach(ie; this.containingBlock.parts) {
				if(ie is this)
					break;
				prev = ie;
			}
			if(prev is null) {
				BlockElement pb;
				BlockElement cb = this.containingBlock;
				moar:
				foreach(ie; this.containingBlock.containingLayout.blocks) {
					if(ie is cb)
						break;
					pb = ie;
				}
				if(pb is null)
					return null;
				if(pb.parts.length == 0) {
					cb = pb;
					goto moar;
				}

				prev = pb.parts[$-1];

			}
			return prev;
		}

		InlineElement getNextInlineElement() {
			InlineElement next = null;
			foreach(idx, ie; this.containingBlock.parts) {
				if(ie is this) {
					if(idx + 1 < this.containingBlock.parts.length)
						next = this.containingBlock.parts[idx + 1];
					break;
				}
			}
			if(next is null) {
				BlockElement n;
				foreach(idx, ie; this.containingBlock.containingLayout.blocks) {
					if(ie is this.containingBlock) {
						if(idx + 1 < this.containingBlock.containingLayout.blocks.length)
							n = this.containingBlock.containingLayout.blocks[idx + 1];
						break;
					}
				}
				if(n is null)
					return null;

				if(n.parts.length)
					next = n.parts[0];
				else {} // FIXME

			}
			return next;
		}

	}

	// Block elements are used entirely for positioning inline elements,
	// which are the things that are actually drawn.
	class BlockElement {
		InlineElement[] parts;
		uint alignment;

		int whiteSpace; // pre, pre-wrap, wrap

		TextLayout containingLayout;

		// inputs
		Point where;
		Size minimumSize;
		Size maximumSize;
		Rectangle[] excludedBoxes; // like if you want it to write around a floated image or something. Coordinates are relative to the bounding box.
		void* identifier;

		Rectangle margin;
		Rectangle padding;

		// outputs
		Rectangle[] boundingBoxes;
	}

	struct TextIdentifyResult {
		InlineElement element;
		int offset;

		private TextIdentifyResult fixupNewline() {
			if(element !is null && offset < element.text.length && element.text[offset] == '\n') {
				offset--;
			} else if(element !is null && offset == element.text.length && element.text.length > 1 && element.text[$-1] == '\n') {
				offset--;
			}
			return this;
		}
	}

	class TextLayout {
		BlockElement[] blocks;
		Rectangle boundingBox_;
		Rectangle boundingBox() { return boundingBox_; }
		void boundingBox(Rectangle r) {
			if(r != boundingBox_) {
				boundingBox_ = r;
				layoutInvalidated = true;
			}
		}

		Rectangle contentBoundingBox() {
			Rectangle r;
			foreach(block; blocks)
			foreach(ie; block.parts) {
				if(ie.boundingBox.right > r.right)
					r.right = ie.boundingBox.right;
				if(ie.boundingBox.bottom > r.bottom)
					r.bottom = ie.boundingBox.bottom;
			}
			return r;
		}

		BlockElement[] getBlocks() {
			return blocks;
		}

		InlineElement[] getTexts() {
			InlineElement[] elements;
			foreach(block; blocks)
				elements ~= block.parts;
			return elements;
		}

		string getPlainText() {
			string text;
			foreach(block; blocks)
				foreach(part; block.parts)
					text ~= part.text;
			return text;
		}

		string getHtml() {
			return null; // FIXME
		}

		this(Rectangle boundingBox) {
			this.boundingBox = boundingBox;
		}

		BlockElement addBlock(InlineElement after = null, Rectangle margin = Rectangle(0, 0, 0, 0), Rectangle padding = Rectangle(0, 0, 0, 0)) {
			auto be = new BlockElement();
			be.containingLayout = this;
			if(after is null)
				blocks ~= be;
			else {
				foreach(idx, b; blocks) {
					if(b is after.containingBlock) {
						blocks = blocks[0 .. idx + 1] ~  be ~ blocks[idx + 1 .. $];
						break;
					}
				}
			}
			return be;
		}

		void clear() {
			blocks = null;
			selectionStart = selectionEnd = caret = Caret.init;
		}

		void addText(Args...)(Args args) {
			if(blocks.length == 0)
				addBlock();

			InlineElement ie = new InlineElement();
			foreach(idx, arg; args) {
				static if(is(typeof(arg) == ForegroundColor))
					ie.color = arg;
				else static if(is(typeof(arg) == TextFormat)) {
					if(arg & 0x8000) // ~TextFormat.something turns it off
						ie.styles &= arg;
					else
						ie.styles |= arg;
				} else static if(is(typeof(arg) == string)) {
					static if(idx == 0 && args.length > 1)
						static assert(0, "Put styles before the string.");
					size_t lastLineIndex;
					foreach(cidx, char a; arg) {
						if(a == '\n') {
							ie.text = arg[lastLineIndex .. cidx + 1];
							lastLineIndex = cidx + 1;
							ie.containingBlock = blocks[$-1];
							blocks[$-1].parts ~= ie.clone;
							ie.text = null;
						} else {

						}
					}

					ie.text = arg[lastLineIndex .. $];
					ie.containingBlock = blocks[$-1];
					blocks[$-1].parts ~= ie.clone;
					caret = Caret(this, blocks[$-1].parts[$-1], cast(int) blocks[$-1].parts[$-1].text.length);
				}
			}

			invalidateLayout();
		}

		void tryMerge(InlineElement into, InlineElement what) {
			if(!into.isMergeCompatible(what)) {
				return; // cannot merge, different configs
			}

			// cool, can merge, bring text together...
			into.text ~= what.text;

			// and remove what
			for(size_t a = 0; a < what.containingBlock.parts.length; a++) {
				if(what.containingBlock.parts[a] is what) {
					for(size_t i = a; i < what.containingBlock.parts.length - 1; i++)
						what.containingBlock.parts[i] = what.containingBlock.parts[i + 1];
					what.containingBlock.parts = what.containingBlock.parts[0 .. $-1];

				}
			}

			// FIXME: ensure no other carets have a reference to it
		}

		/// exact = true means return null if no match. otherwise, get the closest one that makes sense for a mouse click.
		TextIdentifyResult identify(int x, int y, bool exact = false) {
			TextIdentifyResult inexactMatch;
			foreach(block; blocks) {
				foreach(part; block.parts) {
					if(x >= part.boundingBox.left && x < part.boundingBox.right && y >= part.boundingBox.top && y < part.boundingBox.bottom) {

						// FIXME binary search
						int tidx;
						int lastX;
						foreach_reverse(idxo, lx; part.letterXs) {
							int idx = cast(int) idxo;
							if(lx <= x) {
								if(lastX && lastX - x < x - lx)
									tidx = idx + 1;
								else
									tidx = idx;
								break;
							}
							lastX = lx;
						}

						return TextIdentifyResult(part, tidx).fixupNewline;
					} else if(!exact) {
						// we're not in the box, but are we on the same line?
						if(y >= part.boundingBox.top && y < part.boundingBox.bottom)
							inexactMatch = TextIdentifyResult(part, x == 0 ? 0 : cast(int) part.text.length);
					}
				}
			}

			if(!exact && inexactMatch is TextIdentifyResult.init && blocks.length && blocks[$-1].parts.length)
				return TextIdentifyResult(blocks[$-1].parts[$-1], cast(int) blocks[$-1].parts[$-1].text.length).fixupNewline;

			return exact ? TextIdentifyResult.init : inexactMatch.fixupNewline;
		}

		void moveCaretToPixelCoordinates(int x, int y) {
			auto result = identify(x, y);
			caret.inlineElement = result.element;
			caret.offset = result.offset;
		}

		void selectToPixelCoordinates(int x, int y) {
			auto result = identify(x, y);

			if(y < caretLastDrawnY1) {
				// on a previous line, carat is selectionEnd
				selectionEnd = caret;

				selectionStart = Caret(this, result.element, result.offset);
			} else if(y > caretLastDrawnY2) {
				// on a later line
				selectionStart = caret;

				selectionEnd = Caret(this, result.element, result.offset);
			} else {
				// on the same line...
				if(x <= caretLastDrawnX) {
					selectionEnd = caret;
					selectionStart = Caret(this, result.element, result.offset);
				} else {
					selectionStart = caret;
					selectionEnd = Caret(this, result.element, result.offset);
				}

			}
		}


		/// Call this if the inputs change. It will reflow everything
		void redoLayout(ScreenPainter painter) {
			//painter.setClipRectangle(boundingBox);
			auto pos = Point(boundingBox.left, boundingBox.top);

			int lastHeight;
			void nl() {
				pos.x = boundingBox.left;
				pos.y += lastHeight;
			}
			foreach(block; blocks) {
				nl();
				foreach(part; block.parts) {
					part.letterXs = null;

					auto size = painter.textSize(part.text);
					version(Windows)
						if(part.text.length && part.text[$-1] == '\n')
							size.height /= 2; // windows counts the new line at the end, but we don't want that

					part.boundingBox = Rectangle(pos.x, pos.y, pos.x + size.width, pos.y + size.height);

					foreach(idx, char c; part.text) {
							// FIXME: unicode
						part.letterXs ~= painter.textSize(part.text[0 .. idx]).width + pos.x;
					}

					pos.x += size.width;
					if(pos.x >= boundingBox.right) {
						pos.y += size.height;
						pos.x = boundingBox.left;
						lastHeight = 0;
					} else {
						lastHeight = size.height;
					}

					if(part.text.length && part.text[$-1] == '\n')
						nl();
				}
			}

			layoutInvalidated = false;
		}

		bool layoutInvalidated = true;
		void invalidateLayout() {
			layoutInvalidated = true;
		}

// FIXME: caret can remain sometimes when inserting
// FIXME: inserting at the beginning once you already have something can eff it up.
		void drawInto(ScreenPainter painter, bool focused = false) {
			if(layoutInvalidated)
				redoLayout(painter);
			foreach(block; blocks) {
				foreach(part; block.parts) {
					painter.outlineColor = part.color;
					painter.fillColor = part.backgroundColor;

					auto pos = part.boundingBox.upperLeft;
					auto size = part.boundingBox.size;

					painter.drawText(pos, part.text);
					if(part.styles & TextFormat.underline)
						painter.drawLine(Point(pos.x, pos.y + size.height - 4), Point(pos.x + size.width, pos.y + size.height - 4));
					if(part.styles & TextFormat.strikethrough)
						painter.drawLine(Point(pos.x, pos.y + size.height/2), Point(pos.x + size.width, pos.y + size.height/2));
				}
			}

			// on every redraw, I will force the caret to be
			// redrawn too, in order to eliminate perceived lag
			// when moving around with the mouse.
			eraseCaret(painter);

			if(focused) {
				highlightSelection(painter);
				drawCaret(painter);
			}
		}

		Color selectionXorColor = Color(255, 255, 127);

		void highlightSelection(ScreenPainter painter) {
			if(selectionStart is selectionEnd)
				return; // no selection

			if(selectionStart.inlineElement is null) return;
			if(selectionEnd.inlineElement is null) return;

			assert(selectionStart.inlineElement !is null);
			assert(selectionEnd.inlineElement !is null);

			painter.rasterOp = RasterOp.xor;
			painter.outlineColor = Color.transparent;
			painter.fillColor = selectionXorColor;

			auto at = selectionStart.inlineElement;
			auto atOffset = selectionStart.offset;
			bool done;
			while(at) {
				auto box = at.boundingBox;
				if(atOffset < at.letterXs.length)
					box.left = at.letterXs[atOffset];

				if(at is selectionEnd.inlineElement) {
					if(selectionEnd.offset < at.letterXs.length)
						box.right = at.letterXs[selectionEnd.offset];
					done = true;
				}

				painter.drawRectangle(box.upperLeft, box.width, box.height);

				if(done)
					break;

				at = at.getNextInlineElement();
				atOffset = 0;
			}
		}

		int caretLastDrawnX, caretLastDrawnY1, caretLastDrawnY2;
		bool caretShowingOnScreen = false;
		void drawCaret(ScreenPainter painter) {
			//painter.setClipRectangle(boundingBox);
			int x, y1, y2;
			if(caret.inlineElement is null) {
				x = boundingBox.left;
				y1 = boundingBox.top + 2;
				y2 = boundingBox.top + painter.fontHeight;
			} else {
				x = caret.inlineElement.xOfIndex(caret.offset);
				y1 = caret.inlineElement.boundingBox.top + 2;
				y2 = caret.inlineElement.boundingBox.bottom - 2;
			}

			if(caretShowingOnScreen && (x != caretLastDrawnX || y1 != caretLastDrawnY1 || y2 != caretLastDrawnY2))
				eraseCaret(painter);

			painter.pen = Pen(Color.white, 1);
			painter.rasterOp = RasterOp.xor;
			painter.drawLine(
				Point(x, y1),
				Point(x, y2)
			);
			painter.rasterOp = RasterOp.normal;
			caretShowingOnScreen = !caretShowingOnScreen;

			if(caretShowingOnScreen) {
				caretLastDrawnX = x;
				caretLastDrawnY1 = y1;
				caretLastDrawnY2 = y2;
			}
		}

		Rectangle caretBoundingBox() {
			int x, y1, y2;
			if(caret.inlineElement is null) {
				x = boundingBox.left;
				y1 = boundingBox.top + 2;
				y2 = boundingBox.top + 16;
			} else {
				x = caret.inlineElement.xOfIndex(caret.offset);
				y1 = caret.inlineElement.boundingBox.top + 2;
				y2 = caret.inlineElement.boundingBox.bottom - 2;
			}

			return Rectangle(x, y1, x + 1, y2);
		}

		void eraseCaret(ScreenPainter painter) {
			//painter.setClipRectangle(boundingBox);
			if(!caretShowingOnScreen) return;
			painter.pen = Pen(Color.white, 1);
			painter.rasterOp = RasterOp.xor;
			painter.drawLine(
				Point(caretLastDrawnX, caretLastDrawnY1),
				Point(caretLastDrawnX, caretLastDrawnY2)
			);

			caretShowingOnScreen = false;
			painter.rasterOp = RasterOp.normal;
		}

		/// Caret movement api
		/// These should give the user a logical result based on what they see on screen...
		/// thus they locate predominately by *pixels* not char index. (These will generally coincide with monospace fonts tho!)
		void moveUp() {
			if(caret.inlineElement is null) return;
			auto x = caret.inlineElement.xOfIndex(caret.offset);
			auto y = caret.inlineElement.boundingBox.top + 2;

			y -= caret.inlineElement.boundingBox.bottom - caret.inlineElement.boundingBox.top;
			if(y < 0)
				return;

			auto i = identify(x, y);

			if(i.element) {
				caret.inlineElement = i.element;
				caret.offset = i.offset;
			}
		}
		void moveDown() {
			if(caret.inlineElement is null) return;
			auto x = caret.inlineElement.xOfIndex(caret.offset);
			auto y = caret.inlineElement.boundingBox.bottom - 2;

			y += caret.inlineElement.boundingBox.bottom - caret.inlineElement.boundingBox.top;

			auto i = identify(x, y);
			if(i.element) {
				caret.inlineElement = i.element;
				caret.offset = i.offset;
			}
		}
		void moveLeft() {
			if(caret.inlineElement is null) return;
			if(caret.offset)
				caret.offset--;
			else {
				auto p = caret.inlineElement.getPreviousInlineElement();
				if(p) {
					caret.inlineElement = p;
					if(p.text.length && p.text[$-1] == '\n')
						caret.offset = cast(int) p.text.length - 1;
					else
						caret.offset = cast(int) p.text.length;
				}
			}
		}
		void moveRight() {
			if(caret.inlineElement is null) return;
			if(caret.offset < caret.inlineElement.text.length && caret.inlineElement.text[caret.offset] != '\n') {
				caret.offset++;
			} else {
				auto p = caret.inlineElement.getNextInlineElement();
				if(p) {
					caret.inlineElement = p;
					caret.offset = 0;
				}
			}
		}
		void moveHome() {
			if(caret.inlineElement is null) return;
			auto x = 0;
			auto y = caret.inlineElement.boundingBox.top + 2;

			auto i = identify(x, y);

			if(i.element) {
				caret.inlineElement = i.element;
				caret.offset = i.offset;
			}
		}
		void moveEnd() {
			if(caret.inlineElement is null) return;
			auto x = int.max;
			auto y = caret.inlineElement.boundingBox.top + 2;

			auto i = identify(x, y);

			if(i.element) {
				caret.inlineElement = i.element;
				caret.offset = i.offset;
			}

		}
		void movePageUp(ref Caret caret) {}
		void movePageDown(ref Caret caret) {}

		void moveDocumentStart(ref Caret caret) {
			if(blocks.length && blocks[0].parts.length)
				caret = Caret(this, blocks[0].parts[0], 0);
			else
				caret = Caret.init;
		}

		void moveDocumentEnd(ref Caret caret) {
			if(blocks.length) {
				auto parts = blocks[$-1].parts;
				if(parts.length) {
					caret = Caret(this, parts[$-1], cast(int) parts[$-1].text.length);
				} else {
					caret = Caret.init;
				}
			} else
				caret = Caret.init;
		}

		void deleteSelection() {
			if(selectionStart is selectionEnd)
				return;

			if(selectionStart.inlineElement is null) return;
			if(selectionEnd.inlineElement is null) return;

			assert(selectionStart.inlineElement !is null);
			assert(selectionEnd.inlineElement !is null);

			auto at = selectionStart.inlineElement;

			if(selectionEnd.inlineElement is at) {
				// same element, need to chop out
				at.text = at.text[0 .. selectionStart.offset] ~ at.text[selectionEnd.offset .. $];
				at.letterXs = at.letterXs[0 .. selectionStart.offset] ~ at.letterXs[selectionEnd.offset .. $];
				selectionEnd.offset -= selectionEnd.offset - selectionStart.offset;
			} else {
				// different elements, we can do it with slicing
				at.text = at.text[0 .. selectionStart.offset];
				if(selectionStart.offset < at.letterXs.length)
					at.letterXs = at.letterXs[0 .. selectionStart.offset];

				at = at.getNextInlineElement();

				while(at) {
					if(at is selectionEnd.inlineElement) {
						at.text = at.text[selectionEnd.offset .. $];
						if(selectionEnd.offset < at.letterXs.length)
							at.letterXs = at.letterXs[selectionEnd.offset .. $];
						selectionEnd.offset = 0;
						break;
					} else {
						auto cfd = at;
						cfd.text = null; // delete the whole thing

						at = at.getNextInlineElement();

						if(cfd.text.length == 0) {
							// and remove cfd
							for(size_t a = 0; a < cfd.containingBlock.parts.length; a++) {
								if(cfd.containingBlock.parts[a] is cfd) {
									for(size_t i = a; i < cfd.containingBlock.parts.length - 1; i++)
										cfd.containingBlock.parts[i] = cfd.containingBlock.parts[i + 1];
									cfd.containingBlock.parts = cfd.containingBlock.parts[0 .. $-1];

								}
							}
						}
					}
				}
			}

			caret = selectionEnd;
			selectNone();

			invalidateLayout();

		}

		/// Plain text editing api. These work at the current caret inside the selected inline element.
		void insert(in char[] text) {
			foreach(dchar ch; text)
				insert(ch);
		}
		/// ditto
		void insert(dchar ch) {

			bool selectionDeleted = false;
			if(selectionStart !is selectionEnd) {
				deleteSelection();
				selectionDeleted = true;
			}

			if(ch == 127) {
				delete_();
				return;
			}
			if(ch == 8) {
				if(!selectionDeleted)
					backspace();
				return;
			}

			invalidateLayout();

			if(ch == 13) ch = 10;
			auto e = caret.inlineElement;
			if(e is null) {
				addText("" ~ cast(char) ch) ; // FIXME
				return;
			}

			if(caret.offset == e.text.length) {
				e.text ~= cast(char) ch; // FIXME
				caret.offset++;
				if(ch == 10) {
					auto c = caret.inlineElement.clone;
					c.text = null;
					c.letterXs = null;
					insertPartAfter(c,e);
					caret = Caret(this, c, 0);
				}
			} else {
				// FIXME cast char sucks
				if(ch == 10) {
					auto c = caret.inlineElement.clone;
					c.text = e.text[caret.offset .. $];
					if(caret.offset < c.letterXs.length)
						c.letterXs = e.letterXs[caret.offset .. $]; // FIXME boundingBox
					e.text = e.text[0 .. caret.offset] ~ cast(char) ch;
					if(caret.offset <= e.letterXs.length) {
						e.letterXs = e.letterXs[0 .. caret.offset] ~ 0; // FIXME bounding box
					}
					insertPartAfter(c,e);
					caret = Caret(this, c, 0);
				} else {
					e.text = e.text[0 .. caret.offset] ~ cast(char) ch ~ e.text[caret.offset .. $];
					caret.offset++;
				}
			}
		}

		void insertPartAfter(InlineElement what, InlineElement where) {
			foreach(idx, p; where.containingBlock.parts) {
				if(p is where) {
					if(idx + 1 == where.containingBlock.parts.length)
						where.containingBlock.parts ~= what;
					else
						where.containingBlock.parts = where.containingBlock.parts[0 .. idx + 1] ~ what ~ where.containingBlock.parts[idx + 1 .. $];
					return;
				}
			}
		}

		void cleanupStructures() {
			for(size_t i = 0; i < blocks.length; i++) {
				auto block = blocks[i];
				for(size_t a = 0; a < block.parts.length; a++) {
					auto part = block.parts[a];
					if(part.text.length == 0) {
						for(size_t b = a; b < block.parts.length - 1; b++)
							block.parts[b] = block.parts[b+1];
						block.parts = block.parts[0 .. $-1];
					}
				}
				if(block.parts.length == 0) {
					for(size_t a = i; a < blocks.length - 1; a++)
						blocks[a] = blocks[a+1];
					blocks = blocks[0 .. $-1];
				}
			}
		}

		void backspace() {
			try_again:
			auto e = caret.inlineElement;
			if(e is null)
				return;
			if(caret.offset == 0) {
				auto prev = e.getPreviousInlineElement();
				if(prev is null)
					return;
				auto newOffset = cast(int) prev.text.length;
				tryMerge(prev, e);
				caret.inlineElement = prev;
				caret.offset = prev is null ? 0 : newOffset;

				goto try_again;
			} else if(caret.offset == e.text.length) {
				e.text = e.text[0 .. $-1];
				caret.offset--;
			} else {
				e.text = e.text[0 .. caret.offset - 1] ~ e.text[caret.offset .. $];
				caret.offset--;
			}
			//cleanupStructures();

			invalidateLayout();
		}
		void delete_() {
			if(selectionStart !is selectionEnd)
				deleteSelection();
			else {
				auto before = caret;
				moveRight();
				if(caret != before) {
					backspace();
				}
			}

			invalidateLayout();
		}
		void overstrike() {}

		/// Selection API. See also: caret movement.
		void selectAll() {
			moveDocumentStart(selectionStart);
			moveDocumentEnd(selectionEnd);
		}
		bool selectNone() {
			if(selectionStart != selectionEnd) {
				selectionStart = selectionEnd = Caret.init;
				return true;
			}
			return false;
		}

		/// Rich text editing api. These allow you to manipulate the meta data of the current element and add new elements.
		/// They will modify the current selection if there is one and will splice one in if needed.
		void changeAttributes() {}


		/// Text search api. They manipulate the selection and/or caret.
		void findText(string text) {}
		void findIndex(size_t textIndex) {}

		// sample event handlers

		void handleEvent(KeyEvent event) {
			//if(event.type == KeyEvent.Type.KeyPressed) {

			//}
		}

		void handleEvent(dchar ch) {

		}

		void handleEvent(MouseEvent event) {

		}

		bool contentEditable; // can it be edited?
		bool contentCaretable; // is there a caret/cursor that moves around in there?
		bool contentSelectable; // selectable?

		Caret caret;
		Caret selectionStart;
		Caret selectionEnd;

		bool insertMode;
	}

	struct Caret {
		TextLayout layout;
		InlineElement inlineElement;
		int offset;
	}

	enum TextFormat : ushort {
		// decorations
		underline = 1,
		strikethrough = 2,

		// font selectors

		bold = 0x4000 | 1, // weight 700
		light = 0x4000 | 2, // weight 300
		veryBoldOrLight = 0x4000 | 4, // weight 100 with light, weight 900 with bold
		// bold | light is really invalid but should give weight 500
		// veryBoldOrLight without one of the others should just give the default for the font; it should be ignored.

		italic = 0x4000 | 8,
		smallcaps = 0x4000 | 16,
	}

	void* findFont(string family, int weight, TextFormat formats) {
		return null;
	}

}

/++
	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 19, 2021
+/
/// Group: drag_and_drop
interface DropHandler {
	/++
		Called when the drag enters the handler's area.
	+/
	DragAndDropAction dragEnter(DropPackage*);
	/++
		Called when the drag leaves the handler's area or is
		cancelled. You should free your resources when this is called.
	+/
	void dragLeave();
	/++
		Called continually as the drag moves over the handler's area.

		Returns: feedback to the dragger
	+/
	DropParameters dragOver(Point pt);
	/++
		The user dropped the data and you should process it now. You can
		access the data through the given [DropPackage].
	+/
	void drop(scope DropPackage*);
	/++
		Called when the drop is complete. You should free whatever temporary
		resources you were using. It is often reasonable to simply forward
		this call to [dragLeave].
	+/
	void finish();

	/++
		Parameters returned by [DropHandler.drop].
	+/
	static struct DropParameters {
		/++
			Acceptable action over this area.
		+/
		DragAndDropAction action;
		/++
			Rectangle, in client coordinates, where the dragger can expect the same result during this drag session and thus need not ask again.

			If you leave this as Rectangle.init, the dragger will continue to ask and this can waste resources.
		+/
		Rectangle consistentWithin;
	}
}

/++
	History:
		Added February 19, 2021
+/
/// Group: drag_and_drop
enum DragAndDropAction {
	none = 0,
	copy,
	move,
	link,
	ask,
	custom
}

/++
	An opaque structure representing dropped data. It contains
	private, platform-specific data that your `drop` function
	should simply forward.

	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 19, 2021
+/
/// Group: drag_and_drop
struct DropPackage {
	/++
		Lists the available formats as magic numbers. You should compare these
		against looked-up formats (see [DraggableData.getFormatId]) you know you support and can
		understand the passed data.
	+/
	DraggableData.FormatId[] availableFormats() {
		version(X11) {
			return xFormats;
		} else version(Windows) {
			if(pDataObj is null)
				return null;

			typeof(return) ret;

			IEnumFORMATETC ef;
			if(pDataObj.EnumFormatEtc(DATADIR.DATADIR_GET, &ef) == S_OK) {
				FORMATETC fmt;
				ULONG fetched;
				while(ef.Next(1, &fmt, &fetched) == S_OK) {
					if(fetched == 0)
						break;

					if(fmt.lindex != -1)
						continue;
					if(fmt.dwAspect != DVASPECT.DVASPECT_CONTENT)
						continue;
					if(!(fmt.tymed & TYMED.TYMED_HGLOBAL))
						continue;

					ret ~= fmt.cfFormat;
				}
			}

			return ret;
		}
	}

	/++
		Gets data from the drop and optionally accepts it.

		Returns:
			void because the data is fed asynchronously through the `dg` parameter.

		Params:
			acceptedAction = the action to report back to the ender. If it is [DragAndDropAction.none], you are just inspecting the data, but not accepting the drop.

			This is useful to tell the sender that you accepted a move, for example, so they can update their data source as well. For other cases, accepting a drop also indicates that any memory associated with the transfer can be freed.

			Calling `getData` again after accepting a drop is not permitted.

			format = the format you want, from [availableFormats]. Use [DraggableData.getFormatId] to convert from a MIME string or well-known standard format.

			dg = delegate to receive the data asynchronously. Please note this delegate may be called immediately, never be called, or be called somewhere in between during event loop processing depending on the platform, requested format, and other conditions beyond your control.

		Throws:
			if `format` was not compatible with the [availableFormats] or if the drop has already been accepted.

		History:
			Included in first release of [DropPackage].
	+/
	void getData(DragAndDropAction acceptedAction, DraggableData.FormatId format, void delegate(scope ubyte[] data) dg) {
		version(X11) {

			auto display = XDisplayConnection.get();
			auto selectionAtom = GetAtom!"XdndSelection"(display);
			auto best = format;

			static class X11GetSelectionHandler_Drop : X11GetSelectionHandler {

				XDisplay* display;
				Atom selectionAtom;
				DraggableData.FormatId best;
				DraggableData.FormatId format;
				void delegate(scope ubyte[] data) dg;
				DragAndDropAction acceptedAction;
				Window sourceWindow;
				SimpleWindow win;
				this(XDisplay* display, SimpleWindow win, Window sourceWindow, DraggableData.FormatId format, Atom selectionAtom, DraggableData.FormatId best, void delegate(scope ubyte[] data) dg, DragAndDropAction acceptedAction) {
					this.display = display;
					this.win = win;
					this.sourceWindow = sourceWindow;
					this.format = format;
					this.selectionAtom = selectionAtom;
					this.best = best;
					this.dg = dg;
					this.acceptedAction = acceptedAction;
				}


				mixin X11GetSelectionHandler_Basics;

				void handleData(Atom target, in ubyte[] data) {
					//if(target == GetAtom!"UTF8_STRING"(XDisplayConnection.get) || target == XA_STRING || target == GetAtom!"text/plain"(XDisplayConnection.get))

					dg(cast(ubyte[]) data);

					if(acceptedAction != DragAndDropAction.none) {
						auto display = XDisplayConnection.get;

						XClientMessageEvent xclient;

						xclient.type = EventType.ClientMessage;
						xclient.window = sourceWindow;
						xclient.message_type = GetAtom!"XdndFinished"(display);
						xclient.format = 32;
						xclient.data.l[0] = win.impl.window;
						xclient.data.l[1] = 1; // drop successful
						xclient.data.l[2] = dndActionAtom(display, acceptedAction);

						XSendEvent(
							display,
							sourceWindow,
							false,
							EventMask.NoEventMask,
							cast(XEvent*) &xclient
						);

						XFlush(display);
					}
				}

				Atom findBestFormat(Atom[] answer) {
					Atom best = None;
					foreach(option; answer) {
						if(option == format) {
							best = option;
							break;
						}
						/*
						if(option == GetAtom!"UTF8_STRING"(XDisplayConnection.get)) {
							best = option;
							break;
						} else if(option == XA_STRING) {
							best = option;
						} else if(option == GetAtom!"text/plain"(XDisplayConnection.get)) {
							best = option;
						}
						*/
					}
					return best;
				}
			}

			win.impl.getSelectionHandlers[selectionAtom] = new X11GetSelectionHandler_Drop(display, win, sourceWindow, format, selectionAtom, best, dg, acceptedAction);

			XConvertSelection(display, selectionAtom, best, GetAtom!("SDD_DATA", true)(display), win.impl.window, dataTimestamp);

		} else version(Windows) {

			// clean up like DragLeave
			// pass effect back up

			FORMATETC t;
			assert(format >= 0 && format <= ushort.max);
			t.cfFormat = cast(ushort) format;
			t.lindex = -1;
			t.dwAspect = DVASPECT.DVASPECT_CONTENT;
			t.tymed = TYMED.TYMED_HGLOBAL;

			STGMEDIUM m;

			if(pDataObj.GetData(&t, &m) != S_OK) {
				// fail
			} else {
				// succeed, take the data and clean up

				// FIXME: ensure it is legit HGLOBAL
				auto handle = m.hGlobal;

				if(handle) {
					auto sz = GlobalSize(handle);
					if(auto ptr = cast(ubyte*) GlobalLock(handle)) {
						scope(exit) GlobalUnlock(handle);
						scope(exit) GlobalFree(handle);

						auto data = ptr[0 .. sz];

						dg(data);
					}
				}
			}
		}
	}

	private:

	version(X11) {
		SimpleWindow win;
		Window sourceWindow;
		Time dataTimestamp;

		Atom[] xFormats;
	}
	version(Windows) {
		IDataObject pDataObj;
	}
}

/++
	A generic helper base class for making a drop handler with a preference list of custom types.
	This is the base for [TextDropHandler] and [FilesDropHandler] and you can use it for your own
	droppers too.

	It assumes the whole window it used, but you can subclass to change that.

	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 19, 2021
+/
/// Group: drag_and_drop
class GenericDropHandlerBase : DropHandler {
	// no fancy state here so no need to do anything here
	void finish() { }
	void dragLeave() { }

	private DragAndDropAction acceptedAction;
	private DraggableData.FormatId acceptedFormat;
	private void delegate(scope ubyte[]) acceptedHandler;

	struct FormatHandler {
		DraggableData.FormatId format;
		void delegate(scope ubyte[]) handler;
	}

	protected abstract FormatHandler[] formatHandlers();

	DragAndDropAction dragEnter(DropPackage* pkg) {
		debug(sdpy_dnd) { import std.stdio; foreach(fmt; pkg.availableFormats()) writeln(fmt, " ", DraggableData.getFormatName(fmt)); }
		foreach(fmt; formatHandlers())
		foreach(f; pkg.availableFormats())
			if(f == fmt.format) {
				acceptedFormat = f;
				acceptedHandler = fmt.handler;
				return acceptedAction = DragAndDropAction.copy;
			}
		return acceptedAction = DragAndDropAction.none;
	}
	DropParameters dragOver(Point pt) {
		return DropParameters(acceptedAction);
	}

	void drop(scope DropPackage* dropPackage) {
		if(!acceptedFormat || acceptedHandler is null) {
			debug(sdpy_dnd) { import std.stdio; writeln("drop called w/ handler ", acceptedHandler, " and format ", acceptedFormat); }
			return; // prolly shouldn't happen anyway...
		}

		dropPackage.getData(acceptedAction, acceptedFormat, acceptedHandler);
	}
}

/++
	A simple handler for making your window accept drops of plain text.

	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 22, 2021
+/
/// Group: drag_and_drop
class TextDropHandler : GenericDropHandlerBase {
	private void delegate(in char[] text) dg;

	/++

	+/
	this(void delegate(in char[] text) dg) {
		this.dg = dg;
	}

	protected override FormatHandler[] formatHandlers() {
		version(X11)
			return [
				FormatHandler(GetAtom!"UTF8_STRING"(XDisplayConnection.get), &translator),
				FormatHandler(GetAtom!"text/plain;charset=utf-8"(XDisplayConnection.get), &translator),
			];
		else version(Windows)
			return [
				FormatHandler(CF_UNICODETEXT, &translator),
			];
	}

	private void translator(scope ubyte[] data) {
		version(X11)
			dg(cast(char[]) data);
		else version(Windows)
			dg(makeUtf8StringFromWindowsString(cast(wchar[]) data));
	}
}

/++
	A simple handler for making your window accept drops of files, issued to you as file names.

	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 22, 2021
+/
/// Group: drag_and_drop

class FilesDropHandler : GenericDropHandlerBase {
	private void delegate(in char[][]) dg;

	/++

	+/
	this(void delegate(in char[][] fileNames) dg) {
		this.dg = dg;
	}

	protected override FormatHandler[] formatHandlers() {
		version(X11)
			return [
				FormatHandler(GetAtom!"text/uri-list"(XDisplayConnection.get), &translator),
			];
		else version(Windows)
			return [
				FormatHandler(CF_HDROP, &translator),
			];
	}

	private void translator(scope ubyte[] data) {
		version(X11) {
			char[] listString = cast(char[]) data;
			char[][16] buffer;
			int count;
			char[][] result = buffer[];

			void commit(char[] s) {
				if(count == result.length)
					result.length += 16;
				if(s.length > 7 && s[0 ..7] == "file://")
					s = s[7 .. $]; // FIXME: also may need to trim out the host and do some entity decoding
				result[count++] = s;
			}

			size_t last;
			foreach(idx, char c; listString) {
				if(c == '\n') {
					commit(listString[last .. idx - 1]); // a \r
					last = idx + 1; // a \n
				}
			}

			if(last < listString.length) {
				commit(listString[last .. $]);
			}

			// FIXME: they are uris now, should I translate it to local file names?
			// of course the host name is supposed to be there cuz of X rokking...

			dg(result[0 .. count]);
		} else version(Windows) {

			static struct DROPFILES {
				DWORD pFiles;
				POINT pt;
				BOOL  fNC;
				BOOL  fWide;
			}


			const(char)[][16] buffer;
			int count;
			const(char)[][] result = buffer[];
			size_t last;

			void commitA(in char[] stuff) {
				if(count == result.length)
					result.length += 16;
				result[count++] = stuff;
			}

			void commitW(in wchar[] stuff) {
				commitA(makeUtf8StringFromWindowsString(stuff));
			}

			void magic(T)(T chars) {
				size_t idx;
				while(chars[idx]) {
					last = idx;
					while(chars[idx]) {
						idx++;
					}
					static if(is(T == char*))
						commitA(chars[last .. idx]);
					else
						commitW(chars[last .. idx]);
					idx++;
				}
			}

			auto df = cast(DROPFILES*) data.ptr;
			if(df.fWide) {
				wchar* chars = cast(wchar*) (data.ptr + df.pFiles);
				magic(chars);
			} else {
				char* chars = cast(char*) (data.ptr + df.pFiles);
				magic(chars);
			}
			dg(result[0 .. count]);
		}
	}
}

/++
	Interface to describe data being dragged. See also [draggable] helper function.

	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 19, 2021
+/
interface DraggableData {
	version(X11)
		alias FormatId = Atom;
	else
		alias FormatId = uint;
	/++
		Gets the platform-specific FormatId associated with the given named format.

		This may be a MIME type, but may also be other various strings defined by the
		programs you want to interoperate with.

		FIXME: sdpy needs to offer data adapter things that look for compatible formats
		and convert it to some particular type for you.
	+/
	static FormatId getFormatId(string name)() {
		version(X11)
			return GetAtom!name(XDisplayConnection.get);
		else version(Windows) {
			static UINT cache;
			if(!cache)
				cache = RegisterClipboardFormatA(name);
			return cache;
		} else
			throw new NotYetImplementedException();
	}

	/++
		Looks up a string to represent the name for the given format, if there is one.

		You should avoid using this function because it is slow. It is provided more for
		debugging than for primary use.
	+/
	static string getFormatName(FormatId format) {
		version(X11) {
			if(format == 0)
				return "None";
			else
				return getAtomName(format, XDisplayConnection.get);
		} else version(Windows) {
			switch(format) {
				case CF_UNICODETEXT: return "CF_UNICODETEXT";
				case CF_DIBV5: return "CF_DIBV5";
				case CF_RIFF: return "CF_RIFF";
				case CF_WAVE: return "CF_WAVE";
				case CF_HDROP: return "CF_HDROP";
				default:
					char[1024] name;
					auto count = GetClipboardFormatNameA(format, name.ptr, name.length);
					return name[0 .. count].idup;
			}
		}
	}

	FormatId[] availableFormats();
	// Return the slice of data you filled, empty slice if done.
	// this is to support the incremental thing
	ubyte[] getData(FormatId format, return scope ubyte[] data);

	size_t dataLength(FormatId format);
}

/++
	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 19, 2021
+/
DraggableData draggable(string s) {
	version(X11)
	return new class X11SetSelectionHandler_Text, DraggableData {
		this() {
			super(s);
		}

		override FormatId[] availableFormats() {
			return X11SetSelectionHandler_Text.availableFormats();
		}

		override ubyte[] getData(FormatId format, return scope ubyte[] data) {
			return X11SetSelectionHandler_Text.getData(format, data);
		}

		size_t dataLength(FormatId format) {
			return s.length;
		}
	};
	version(Windows)
	return new class DraggableData {
		FormatId[] availableFormats() {
			return [CF_UNICODETEXT];
		}

		ubyte[] getData(FormatId format, return scope ubyte[] data) {
			return cast(ubyte[]) makeWindowsString(s, cast(wchar[]) data, WindowsStringConversionFlags.convertNewLines | WindowsStringConversionFlags.zeroTerminate);
		}

		size_t dataLength(FormatId format) {
			return sizeOfConvertedWstring(s, WindowsStringConversionFlags.convertNewLines | WindowsStringConversionFlags.zeroTerminate) * wchar.sizeof;
		}
	};
}

/++
	$(PITFALL This is not yet stable and may break in future versions without notice.)

	History:
		Added February 19, 2021
+/
/// Group: drag_and_drop
int doDragDrop(SimpleWindow window, DraggableData handler, DragAndDropAction action = DragAndDropAction.copy)
in {
	assert(window !is null);
	assert(handler !is null);
}
do
{
	version(X11) {
		auto sh = cast(X11SetSelectionHandler) handler;
		if(sh is null) {
			// gotta make my own adapter.
			sh = new class X11SetSelectionHandler {
				mixin X11SetSelectionHandler_Basics;

				Atom[] availableFormats() { return handler.availableFormats(); }
				ubyte[] getData(Atom format, return scope ubyte[] data) {
					return handler.getData(format, data);
				}

				// since the drop selection is only ever used once it isn't important
				// to reset it.
				void done() {}
			};
		}
		return doDragDropX11(window, sh, action);
	} else version(Windows) {
		return doDragDropWindows(window, handler, action);
	} else throw new NotYetImplementedException();
}

version(Windows)
private int doDragDropWindows(SimpleWindow window, DraggableData handler, DragAndDropAction action = DragAndDropAction.copy) {
	IDataObject obj = new class IDataObject {
		ULONG refCount;
		ULONG AddRef() {
			return ++refCount;
		}
		ULONG Release() {
			return --refCount;
		}
		HRESULT QueryInterface(const (IID)*riid, LPVOID *ppv) {
			if (IID_IUnknown == *riid) {
				*ppv = cast(void*) cast(IUnknown) this;
			}
			else if (IID_IDataObject == *riid) {
				*ppv = cast(void*) cast(IDataObject) this;
			}
			else {
				*ppv = null;
				return E_NOINTERFACE;
			}

			AddRef();
			return NOERROR;
		}

		HRESULT DAdvise(FORMATETC* pformatetc, DWORD advf, IAdviseSink pAdvSink, DWORD* pdwConnection) {
			// import std.stdio; writeln("Advise");
			return E_NOTIMPL;
		}
		HRESULT DUnadvise(DWORD dwConnection) {
			return E_NOTIMPL;
		}
		HRESULT EnumDAdvise(IEnumSTATDATA* ppenumAdvise) {
			// import std.stdio; writeln("EnumDAdvise");
			return OLE_E_ADVISENOTSUPPORTED;
		}
		// tell what formats it supports

		FORMATETC[] types;
		this() {
			FORMATETC t;
			foreach(ty; handler.availableFormats()) {
				assert(ty <= ushort.max && ty >= 0);
				t.cfFormat = cast(ushort) ty;
				t.lindex = -1;
				t.dwAspect = DVASPECT.DVASPECT_CONTENT;
				t.tymed = TYMED.TYMED_HGLOBAL;
			}
			types ~= t;
		}
		HRESULT EnumFormatEtc(DWORD dwDirection, IEnumFORMATETC* ppenumFormatEtc) {
			if(dwDirection == DATADIR.DATADIR_GET) {
				*ppenumFormatEtc = new class IEnumFORMATETC {
					ULONG refCount;
					ULONG AddRef() {
						return ++refCount;
					}
					ULONG Release() {
						return --refCount;
					}
					HRESULT QueryInterface(const (IID)*riid, LPVOID *ppv) {
						if (IID_IUnknown == *riid) {
							*ppv = cast(void*) cast(IUnknown) this;
						}
						else if (IID_IEnumFORMATETC == *riid) {
							*ppv = cast(void*) cast(IEnumFORMATETC) this;
						}
						else {
							*ppv = null;
							return E_NOINTERFACE;
						}

						AddRef();
						return NOERROR;
					}


					int pos;
					this() {
						pos = 0;
					}

					HRESULT Clone(IEnumFORMATETC* ppenum) {
						// import std.stdio; writeln("clone");
						return E_NOTIMPL; // FIXME
					}

					// Caller is responsible for freeing memory
					HRESULT Next(ULONG celt, FORMATETC* rgelt, ULONG* pceltFetched) {
						// fetched may be null if celt is one
						if(celt != 1)
							return E_NOTIMPL; // FIXME

						if(celt + pos > types.length)
							return S_FALSE;

						*rgelt = types[pos++];

						if(pceltFetched !is null)
							*pceltFetched = 1;

						// import std.stdio; writeln("ok celt ", celt);
						return S_OK;
					}

					HRESULT Reset() {
						pos = 0;
						return S_OK;
					}

					HRESULT Skip(ULONG celt) {
						if(celt + pos <= types.length) {
							pos += celt;
							return S_OK;
						}
						return S_FALSE;
					}
				};

				return S_OK;
			} else
				return E_NOTIMPL;
		}
		// given a format, return the format you'd prefer to use cuz it is identical
		HRESULT GetCanonicalFormatEtc(FORMATETC* pformatectIn, FORMATETC* pformatetcOut) {
			// FIXME: prolly could be better but meh
			// import std.stdio; writeln("gcf: ", *pformatectIn);
			*pformatetcOut = *pformatectIn;
			return S_OK;
		}
		HRESULT GetData(FORMATETC* pformatetcIn, STGMEDIUM* pmedium) {
			foreach(ty; types) {
				if(ty == *pformatetcIn) {
					auto format = ty.cfFormat;
					// import std.stdio; writeln("A: ", *pformatetcIn, "\nB: ", ty);
					STGMEDIUM medium;
					medium.tymed = TYMED.TYMED_HGLOBAL;

					auto sz = handler.dataLength(format);
					auto handle = GlobalAlloc(GMEM_MOVEABLE, sz);
					if(handle is null) throw new Exception("GlobalAlloc");
					if(auto data = cast(wchar*) GlobalLock(handle)) {
						auto slice = data[0 .. sz];
						scope(exit)
							GlobalUnlock(handle);

						handler.getData(format, cast(ubyte[]) slice[]);
					}


					medium.hGlobal = handle; // FIXME
					*pmedium = medium;
					return S_OK;
				}
			}
			return DV_E_FORMATETC;
		}
		HRESULT GetDataHere(FORMATETC* pformatetcIn, STGMEDIUM* pmedium) {
			// import std.stdio; writeln("GDH: ", *pformatetcIn);
			return E_NOTIMPL; // FIXME
		}
		HRESULT QueryGetData(FORMATETC* pformatetc) {
			auto search = *pformatetc;
			search.tymed &= TYMED.TYMED_HGLOBAL;
			foreach(ty; types)
				if(ty == search) {
					// import std.stdio; writeln("QueryGetData ", search, " ", types[0]);
					return S_OK;
				}
			if(pformatetc.cfFormat==CF_UNICODETEXT) {
				//import std.stdio; writeln("QueryGetData FALSE ", search, " ", types[0]);
			}
			return S_FALSE;
		}
		HRESULT SetData(FORMATETC* pformatetc, STGMEDIUM* pmedium, BOOL fRelease) {
			// import std.stdio; writeln("SetData: ");
			return E_NOTIMPL;
		}
	};


	IDropSource src = new class IDropSource {
		ULONG refCount;
		ULONG AddRef() {
			return ++refCount;
		}
		ULONG Release() {
			return --refCount;
		}
		HRESULT QueryInterface(const (IID)*riid, LPVOID *ppv) {
			if (IID_IUnknown == *riid) {
				*ppv = cast(void*) cast(IUnknown) this;
			}
			else if (IID_IDropSource == *riid) {
				*ppv = cast(void*) cast(IDropSource) this;
			}
			else {
				*ppv = null;
				return E_NOINTERFACE;
			}

			AddRef();
			return NOERROR;
		}

		int QueryContinueDrag(int fEscapePressed, uint grfKeyState) {
			if(fEscapePressed)
				return DRAGDROP_S_CANCEL;
			if(!(grfKeyState & MK_LBUTTON))
				return DRAGDROP_S_DROP;
			return S_OK;
		}

		int GiveFeedback(uint dwEffect) {
			return DRAGDROP_S_USEDEFAULTCURSORS;
		}
	};

	DWORD effect;

	if(action == DragAndDropAction.none) assert(0, "Don't drag something with a none effect.");

	DROPEFFECT de = win32DragAndDropAction(action);

	// I'm not as concerned about the GC here since DoDragDrop blocks so the stack frame still sane the whole time
	// but still prolly a FIXME

	auto ret = DoDragDrop(obj, src, de, &effect);
	/+
	import std.stdio;
	if(ret == DRAGDROP_S_DROP)
		writeln("drop ", effect);
	else if(ret == DRAGDROP_S_CANCEL)
		writeln("cancel");
	else if(ret == S_OK)
		writeln("ok");
	else writeln(ret);
	+/

	return ret;
}

version(Windows)
DROPEFFECT win32DragAndDropAction(DragAndDropAction action) {
	DROPEFFECT de;

	with(DragAndDropAction)
	with(DROPEFFECT)
	final switch(action) {
		case none: de = DROPEFFECT_NONE; break;
		case copy: de = DROPEFFECT_COPY; break;
		case move: de = DROPEFFECT_MOVE; break;
		case link: de = DROPEFFECT_LINK; break;
		case ask: throw new Exception("ask not implemented yet");
		case custom: throw new Exception("custom not implemented yet");
	}

	return de;
}


/++
	History:
		Added February 19, 2021
+/
/// Group: drag_and_drop
void enableDragAndDrop(SimpleWindow window, DropHandler handler) {
	version(X11) {
		auto display = XDisplayConnection.get;

		Atom atom = 5; // right???

		XChangeProperty(
			display,
			window.impl.window,
			GetAtom!"XdndAware"(display),
			XA_ATOM,
			32 /* bits */,
			PropModeReplace,
			&atom,
			1);

		window.dropHandler = handler;
	} else version(Windows) {

		initDnd();

		auto dropTarget = new class (handler) IDropTarget {
			DropHandler handler;
			this(DropHandler handler) {
				this.handler = handler;
			}
			ULONG refCount;
			ULONG AddRef() {
				return ++refCount;
			}
			ULONG Release() {
				return --refCount;
			}
			HRESULT QueryInterface(const (IID)*riid, LPVOID *ppv) {
				if (IID_IUnknown == *riid) {
					*ppv = cast(void*) cast(IUnknown) this;
				}
				else if (IID_IDropTarget == *riid) {
					*ppv = cast(void*) cast(IDropTarget) this;
				}
				else {
					*ppv = null;
					return E_NOINTERFACE;
				}

				AddRef();
				return NOERROR;
			}


			// ///////////////////

			HRESULT DragEnter(IDataObject pDataObj, DWORD grfKeyState, POINTL pt, DWORD* pdwEffect) {
				DropPackage dropPackage = DropPackage(pDataObj);
				*pdwEffect = win32DragAndDropAction(handler.dragEnter(&dropPackage));
				return S_OK; // https://docs.microsoft.com/en-us/windows/win32/api/oleidl/nf-oleidl-idroptarget-dragenter
			}

			HRESULT DragLeave() {
				handler.dragLeave();
				// release the IDataObject if needed
				return S_OK;
			}

			HRESULT DragOver(DWORD grfKeyState, POINTL pt, DWORD* pdwEffect) {
				auto res = handler.dragOver(Point(pt.x, pt.y)); // FIXME: translate screen coordinates back to window coordinates

				*pdwEffect = win32DragAndDropAction(res.action);
				// same as DragEnter basically
				return S_OK;
			}

			HRESULT Drop(IDataObject pDataObj, DWORD grfKeyState, POINTL pt, DWORD* pdwEffect) {
				DropPackage pkg = DropPackage(pDataObj);
				handler.drop(&pkg);

				return S_OK;
			}
		};
		// Windows can hold on to the handler and try to call it
		// during which time the GC can't see it. so important to
		// manually manage this. At some point i'll FIXME and make
		// all my com instances manually managed since they supposed
		// to respect the refcount.
		import core.memory;
		GC.addRoot(cast(void*) dropTarget);

		if(RegisterDragDrop(window.impl.hwnd, dropTarget) != S_OK)
			throw new Exception("register");

		window.dropHandler = handler;
	} else throw new NotYetImplementedException();
}



static if(UsingSimpledisplayX11) {

enum _NET_WM_STATE_ADD = 1;
enum _NET_WM_STATE_REMOVE = 0;
enum _NET_WM_STATE_TOGGLE = 2;

/// X-specific. Use [SimpleWindow.requestAttention] instead for most cases.
void demandAttention(SimpleWindow window, bool needs = true) {
	demandAttention(window.impl.window, needs);
}

/// ditto
void demandAttention(Window window, bool needs = true) {
	setNetWmStateAtom(window, GetAtom!("_NET_WM_STATE_DEMANDS_ATTENTION", false)(XDisplayConnection.get), needs);
}

void setNetWmStateAtom(Window window, Atom atom, bool set = true, Atom atom2 = None) {
	auto display = XDisplayConnection.get();
	if(atom == None)
		return; // non-failure error
	//auto atom2 = GetAtom!"_NET_WM_STATE_SHADED"(display);

	XClientMessageEvent xclient;

	xclient.type = EventType.ClientMessage;
	xclient.window = window;
	xclient.message_type = GetAtom!"_NET_WM_STATE"(display);
	xclient.format = 32;
	xclient.data.l[0] = set ? _NET_WM_STATE_ADD : _NET_WM_STATE_REMOVE;
	xclient.data.l[1] = atom;
	xclient.data.l[2] = atom2;
	xclient.data.l[3] = 1;
	// [3] == source. 0 == unknown, 1 == app, 2 == else

	XSendEvent(
		display,
		RootWindow(display, DefaultScreen(display)),
		false,
		EventMask.SubstructureRedirectMask | EventMask.SubstructureNotifyMask,
		cast(XEvent*) &xclient
	);

	/+
	XChangeProperty(
		display,
		window.impl.window,
		GetAtom!"_NET_WM_STATE"(display),
		XA_ATOM,
		32 /* bits */,
		PropModeAppend,
		&atom,
		1);
	+/
}

private Atom dndActionAtom(Display* display, DragAndDropAction action) {
	Atom actionAtom;
	with(DragAndDropAction)
	final switch(action) {
		case none: actionAtom = None; break;
		case copy: actionAtom = GetAtom!"XdndActionCopy"(display); break;
		case move: actionAtom = GetAtom!"XdndActionMove"(display); break;
		case link: actionAtom = GetAtom!"XdndActionLink"(display); break;
		case ask: actionAtom = GetAtom!"XdndActionAsk"(display); break;
		case custom: actionAtom = GetAtom!"XdndActionCustom"(display); break;
	}

	return actionAtom;
}

private int doDragDropX11(SimpleWindow window, X11SetSelectionHandler handler, DragAndDropAction action) {
	// FIXME: I need to show user feedback somehow.
	auto display = XDisplayConnection.get;

	auto actionAtom = dndActionAtom(display, action);
	assert(actionAtom, "Don't use action none to accept a drop");

	setX11Selection!"XdndSelection"(window, handler, null);

	auto oldKeyHandler = window.handleKeyEvent;
	scope(exit) window.handleKeyEvent = oldKeyHandler;

	auto oldCharHandler = window.handleCharEvent;
	scope(exit) window.handleCharEvent = oldCharHandler;

	auto oldMouseHandler = window.handleMouseEvent;
	scope(exit) window.handleMouseEvent = oldMouseHandler;

	Window[Window] eligibility; // 0 == not eligible, otherwise it is the window id of an eligible child

	import core.sys.posix.sys.time;
	timeval tv;
	gettimeofday(&tv, null);

	Time dataTimestamp = tv.tv_sec * 1000 + tv.tv_usec / 1000;

	Time lastMouseTimestamp;

	bool dnding = true;
	Window lastIn = None;

	void leave() {
		if(lastIn == None)
			return;

		XEvent ev;
		ev.xclient.type = EventType.ClientMessage;
		ev.xclient.window = lastIn;
		ev.xclient.message_type = GetAtom!("XdndLeave", true)(display);
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = window.impl.window;

		XSendEvent(XDisplayConnection.get, lastIn, false, EventMask.NoEventMask, &ev);
		XFlush(display);

		lastIn = None;
	}

	void enter(Window w) {
		assert(lastIn == None);

		lastIn = w;

		XEvent ev;
		ev.xclient.type = EventType.ClientMessage;
		ev.xclient.window = lastIn;
		ev.xclient.message_type = GetAtom!("XdndEnter", true)(display);
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = window.impl.window;
		ev.xclient.data.l[1] = (5 << 24) | 0; // version 5, no more sources. FIXME source types

		auto types = handler.availableFormats();
		assert(types.length > 0);

		ev.xclient.data.l[2] = types[0];
		if(types.length > 1)
			ev.xclient.data.l[3] = types[1];
		if(types.length > 2)
			ev.xclient.data.l[4] = types[2];

		// FIXME: other types?!?!? and make sure we skip TARGETS

		XSendEvent(XDisplayConnection.get, lastIn, false, EventMask.NoEventMask, &ev);
		XFlush(display);
	}

	void position(int rootX, int rootY) {
		assert(lastIn != None);

		XEvent ev;
		ev.xclient.type = EventType.ClientMessage;
		ev.xclient.window = lastIn;
		ev.xclient.message_type = GetAtom!("XdndPosition", true)(display);
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = window.impl.window;
		ev.xclient.data.l[1] = 0; // reserved
		ev.xclient.data.l[2] = (rootX << 16) | rootY;
		ev.xclient.data.l[3] = dataTimestamp;
		ev.xclient.data.l[4] = actionAtom;

		XSendEvent(XDisplayConnection.get, lastIn, false, EventMask.NoEventMask, &ev);
		XFlush(display);

	}

	void drop() {
		XEvent ev;
		ev.xclient.type = EventType.ClientMessage;
		ev.xclient.window = lastIn;
		ev.xclient.message_type = GetAtom!("XdndDrop", true)(display);
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = window.impl.window;
		ev.xclient.data.l[1] = 0; // reserved
		ev.xclient.data.l[2] = dataTimestamp;

		XSendEvent(XDisplayConnection.get, lastIn, false, EventMask.NoEventMask, &ev);
		XFlush(display);

		lastIn = None;
		dnding = false;
	}

	// fyi nativeEventHandler can return 0 if it handles it, or otherwise it goes back to the normal handler
	// but idk if i should...

	window.setEventHandlers(
		delegate(KeyEvent ev) {
			if(ev.pressed == true && ev.key == Key.Escape) {
				// cancel
				dnding = false;
			}
		},
		delegate(MouseEvent ev) {
			if(ev.timestamp < lastMouseTimestamp)
				return;

			lastMouseTimestamp = ev.timestamp;

			if(ev.type == MouseEventType.motion) {
				auto display = XDisplayConnection.get;
				auto root = RootWindow(display, DefaultScreen(display));

				Window topWindow;
				int rootX, rootY;

				XTranslateCoordinates(display, window.impl.window, root, ev.x, ev.y, &rootX, &rootY, &topWindow);

				if(topWindow == None)
					return;

				top:
				if(auto result = topWindow in eligibility) {
					auto dropWindow = *result;
					if(dropWindow == None) {
						leave();
						return;
					}

					if(dropWindow != lastIn) {
						leave();
						enter(dropWindow);
						position(rootX, rootY);
					} else {
						position(rootX, rootY);
					}
				} else {
					// determine eligibility
					auto data = cast(Atom[]) getX11PropertyData(topWindow, GetAtom!"XdndAware"(display), XA_ATOM);
					if(data.length == 1) {
						// in case there is no WM or it isn't reparenting
						eligibility[topWindow] = (data[0] == 5) ? topWindow : None; // FIXME I'm supposed to handle older versions too but meh
					} else {

						Window tryScanChildren(Window search, int maxRecurse) {
							// could be reparenting window manager, so gotta check the next few children too
							Window child;
							int x;
							int y;
							XTranslateCoordinates(display, window.impl.window, search, ev.x, ev.y, &x, &y, &child);

							if(child == None)
								return None;
							auto data = cast(Atom[]) getX11PropertyData(child, GetAtom!"XdndAware"(display), XA_ATOM);
							if(data.length == 1) {
								return (data[0] == 5) ? child : None; // FIXME I'm supposed to handle older versions too but meh
							} else {
								if(maxRecurse)
									return tryScanChildren(child, maxRecurse - 1);
								else
									return None;
							}

						}

						// if a WM puts more than 3 layers on it, like wtf is it doing, screw that.
						auto topResult = tryScanChildren(topWindow, 3);
						// it is easy to have a false negative due to the mouse going over a WM
						// child window like the close button if separate from the frame... so I
						// can't really cache negatives, :(
						if(topResult != None) {
							eligibility[topWindow] = topResult;
							goto top; // reload to do the positioning iff eligibility changed lest we endless loop
						}
					}

				}

			} else if(ev.type == MouseEventType.buttonReleased) {
				drop();
				dnding = false;
			}
		}
	);

	window.grabInput();
	scope(exit)
		window.releaseInputGrab();


	EventLoop.get.run(() => dnding);

	return 0;
}

/// X-specific
TrueColorImage getWindowNetWmIcon(Window window) {
	try {
		auto display = XDisplayConnection.get;

		auto data = getX11PropertyData (window, GetAtom!"_NET_WM_ICON"(display), XA_CARDINAL);

		if (data.length > arch_ulong.sizeof * 2) {
			auto meta = cast(arch_ulong[]) (data[0 .. arch_ulong.sizeof * 2]);
			// these are an array of rgba images that we have to convert into pixmaps ourself

			int width = cast(int) meta[0];
			int height = cast(int) meta[1];

			auto bytes = cast(ubyte[]) (data[arch_ulong.sizeof * 2 .. $]);

			static if(arch_ulong.sizeof == 4) {
				bytes = bytes[0 .. width * height * 4];
				alias imageData = bytes;
			} else static if(arch_ulong.sizeof == 8) {
				bytes = bytes[0 .. width * height * 8];
				auto imageData = new ubyte[](4 * width * height);
			} else static assert(0);



			// this returns ARGB. Remember it is little-endian so
			//                                         we have BGRA
			// our thing uses RGBA, which in little endian, is ABGR
			for(int idx = 0, idx2 = 0; idx < bytes.length; idx += arch_ulong.sizeof, idx2 += 4) {
				auto r = bytes[idx + 2];
				auto g = bytes[idx + 1];
				auto b = bytes[idx + 0];
				auto a = bytes[idx + 3];

				imageData[idx2 + 0] = r;
				imageData[idx2 + 1] = g;
				imageData[idx2 + 2] = b;
				imageData[idx2 + 3] = a;
			}

			return new TrueColorImage(width, height, imageData);
		}

		return null;
	} catch(Exception e) {
		return null;
	}
}

} /* UsingSimpledisplayX11 */


void loadBinNameToWindowClassName () {
	import core.stdc.stdlib : realloc;
	version(linux) {
		// args[0] MAY be empty, so we'll just use this
		import core.sys.posix.unistd : readlink;
		char[1024] ebuf = void; // 1KB should be enough for everyone!
		auto len = readlink("/proc/self/exe", ebuf.ptr, ebuf.length);
		if (len < 1) return;
	} else /*version(Windows)*/ {
		import core.runtime : Runtime;
		if (Runtime.args.length == 0 || Runtime.args[0].length == 0) return;
		auto ebuf = Runtime.args[0];
		auto len = ebuf.length;
	}
	auto pos = len;
	while (pos > 0 && ebuf[pos-1] != '/') --pos;
	sdpyWindowClassStr = cast(char*)realloc(sdpyWindowClassStr, len-pos+1);
	if (sdpyWindowClassStr is null) return; // oops
	sdpyWindowClassStr[0..len-pos+1] = 0; // just in case
	sdpyWindowClassStr[0..len-pos] = ebuf[pos..len];
}

/++
	An interface representing a font.

	This is still MAJOR work in progress.
+/
interface DrawableFont {
	void drawString(ScreenPainter painter, Point upperLeft, in char[] text);
}

/++
	Loads a true type font using [arsd.ttf]. That module must be compiled
	in if you choose to use this function.

	Be warned: this can be slow and memory hungry, especially on remote connections
	to the X server.

	This is still MAJOR work in progress.
+/
DrawableFont arsdTtfFont()(in ubyte[] data, int size) {
	import arsd.ttf;
	static class ArsdTtfFont : DrawableFont {
		TtfFont font;
		int size;
		this(in ubyte[] data, int size) {
			font = TtfFont(data);
			this.size = size;
		}

		Sprite[string] cache;

		void drawString(ScreenPainter painter, Point upperLeft, in char[] text) {
			Sprite sprite = (text in cache) ? *(text in cache) : null;

			auto fg = painter.impl._outlineColor;
			auto bg = painter.impl._fillColor;

			if(sprite is null) {
				int width, height;
				auto data = font.renderString(text, size, width, height);
				auto image = new TrueColorImage(width, height);
				int pos = 0;
				foreach(y; 0 .. height)
				foreach(x; 0 .. width) {
					fg.a = data[0];
					bg.a = 255;
					auto color = alphaBlend(fg, bg);
					image.imageData.bytes[pos++] = color.r;
					image.imageData.bytes[pos++] = color.g;
					image.imageData.bytes[pos++] = color.b;
					image.imageData.bytes[pos++] = data[0];
					data = data[1 .. $];
				}
				assert(data.length == 0);

				sprite = new Sprite(painter.window, Image.fromMemoryImage(image));
				cache[text.idup] = sprite;
			}

			sprite.drawAt(painter, upperLeft);
		}
	}

	return new ArsdTtfFont(data, size);
}

class NotYetImplementedException : Exception {
	this(string file = __FILE__, size_t line = __LINE__) {
		super("Not yet implemented", file, line);
	}
}

///
__gshared bool librariesSuccessfullyLoaded = true;
///
__gshared bool openGlLibrariesSuccessfullyLoaded = true;

private mixin template DynamicLoadSupplementalOpenGL(Iface) {
	mixin(staticForeachReplacement!Iface);

	void loadDynamicLibrary() @nogc {
		(cast(void function() @nogc) &loadDynamicLibraryForReal)();
	}

        void loadDynamicLibraryForReal() {
                foreach(name; __traits(derivedMembers, Iface)) {
                        mixin("alias tmp = " ~ name ~ ";");
                        tmp = cast(typeof(tmp)) glbindGetProcAddress(name);
                        if(tmp is null) throw new Exception("load failure of function " ~ name ~ " from supplemental OpenGL");
                }
        }
}

private const(char)[] staticForeachReplacement(Iface)() pure {
/*
	// just this for gdc 9....
	// when i drop support for it and switch to gdc10, we can put this original back for a slight compile time ram decrease

        static foreach(name; __traits(derivedMembers, Iface))
                mixin("__gshared typeof(&__traits(getMember, Iface, name)) " ~ name ~ ";");
*/

	char[] code = new char[](__traits(derivedMembers, Iface).length * 64);
	size_t pos;

	void append(in char[] what) {
		if(pos + what.length > code.length)
			code.length = (code.length * 3) / 2;
		code[pos .. pos + what.length] = what[];
		pos += what.length;
	}

        foreach(name; __traits(derivedMembers, Iface)) {
                append(`__gshared typeof(&__traits(getMember, Iface, "`);
		append(name);
		append(`")) `);
		append(name);
		append(";");
	}

	return code[0 .. pos];
}

private mixin template DynamicLoad(Iface, string library, int majorVersion, alias success) {
	mixin(staticForeachReplacement!Iface);

        private void* libHandle;
	private bool attempted;

        void loadDynamicLibrary() @nogc {
		(cast(void function() @nogc) &loadDynamicLibraryForReal)();
	}

	bool loadAttempted() {
		return attempted;
	}
	bool loadSuccessful() {
		return libHandle !is null;
	}

        void loadDynamicLibraryForReal() {
		attempted = true;
                version(Posix) {
                        import core.sys.posix.dlfcn;
			version(OSX) {
				version(X11)
                        		libHandle = dlopen("/usr/X11/lib/lib" ~ library ~ ".dylib", RTLD_NOW);
				else
                        		libHandle = dlopen(library ~ ".dylib", RTLD_NOW);
			} else {
                        	libHandle = dlopen("lib" ~ library ~ ".so", RTLD_NOW);
				if(libHandle is null)
                        		libHandle = dlopen(("lib" ~ library ~ ".so." ~ toInternal!string(majorVersion) ~ "\0").ptr, RTLD_NOW);
			}

			static void* loadsym(void* l, const char* name) {
				import core.stdc.stdlib;
				if(l is null)
					return &abort;
				return dlsym(l, name);
			}
                } else version(Windows) {
                        import core.sys.windows.windows;
                        libHandle = LoadLibrary(library ~ ".dll");
			static void* loadsym(void* l, const char* name) {
				import core.stdc.stdlib;
				if(l is null)
					return &abort;
				return GetProcAddress(l, name);
			}
                }
                if(libHandle is null) {
			success = false;
                        //throw new Exception("load failure of library " ~ library);
		}
                foreach(name; __traits(derivedMembers, Iface)) {
                        mixin("alias tmp = " ~ name ~ ";");
                        tmp = cast(typeof(tmp)) loadsym(libHandle, name);
                        if(tmp is null) throw new Exception("load failure of function " ~ name ~ " from " ~ library);
                }
        }

        void unloadDynamicLibrary() {
                version(Posix) {
                        import core.sys.posix.dlfcn;
                        dlclose(libHandle);
                } else version(Windows) {
                        import core.sys.windows.windows;
                        FreeLibrary(libHandle);
                }
                foreach(name; __traits(derivedMembers, Iface))
                        mixin(name ~ " = null;");
        }
}

void guiAbortProcess(string msg) {
	import core.stdc.stdlib;
	version(Windows) {
		WCharzBuffer t = WCharzBuffer(msg);
		MessageBoxW(null, t.ptr, "Program Termination"w.ptr, 0);
	} else {
		import std.stdio;
		stderr.writeln(msg);
		stderr.flush();
	}

	abort();
}

private alias scriptable = arsd_jsvar_compatible;
