/++
	An [arsd.minigui] widget that can embed [arsd.nanovega].

	History:
		Added February 7, 2020 (version 9.2)
+/
module arsd.minigui_addons.nanovega;

import arsd.minigui;
/// Since the nvg context uses UFCS, you probably want this anyway.
public import arsd.nanovega;

static if(OpenGlEnabled)
/++
	The NanoVegaWidget has a class you can use with [arsd.nanovega].

	History:
		Included in initial release on February 7, 2020 (dub package version 9.2).
+/
class NanoVegaWidget : OpenGlWidget {
	NVGContext nvg;

	this(Widget parent) {
		super(parent);

		win.onClosing = delegate() {
			nvg.kill();
		};

		win.visibleForTheFirstTime = delegate() {
			nvg = nvgCreateContext();
			if(nvg is null) throw new Exception("cannot initialize NanoVega");
		};

		win.redrawOpenGlScene = delegate() {
			if(redrawNVGScene is null)
				return;
			glViewport(0, 0, this.width, this.height);
			if(clearOnEachFrame) {
				glClearColor(0, 0, 0, 0);
				glClear(glNVGClearFlags);
			}

			nvg.beginFrame(this.width, this.height);
			scope(exit) nvg.endFrame();

			redrawNVGScene(nvg);
		};
	}
	/// Set this to draw your nanovega frame.
	void delegate(NVGContext nvg) redrawNVGScene;

	/// If true, it automatically clears the widget canvas between each redraw call.
	bool clearOnEachFrame = true;
}

/// Nanovega requires at least OpenGL 3.0, so this sets that requirement. You can override it later still, of course.
shared static this() {
	setOpenGLContextVersion(3, 0);
}

