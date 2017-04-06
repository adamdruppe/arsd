/++
	Displays a color-picker dialog box.
+/
module arsd.minigui_addons.color_dialog;

import arsd.minigui;

static if(UsingWin32Widgets)
	pragma(lib, "comdlg32");

/++

+/
void showColorDialog(Window owner, Color current, void delegate(Color choice) onOK, void delegate() onCancel = null) {
	static if(UsingWin32Widgets) {
		import core.sys.windows.windows;
		static COLORREF[16] customColors;
		CHOOSECOLOR cc;
		cc.lStructSize = cc.sizeof;
		cc.hwndOwner = owner ? owner.win.impl.hwnd : null;
		cc.lpCustColors = cast(LPDWORD) customColors.ptr;
		cc.rgbResult = RGB(current.r, current.g, current.b);
		cc.Flags = CC_FULLOPEN | CC_RGBINIT;
		if(ChooseColor(&cc)) {
			onOK(Color(GetRValue(cc.rgbResult), GetGValue(cc.rgbResult), GetBValue(cc.rgbResult)));
		} else {
			if(onCancel)
				onCancel();
		}
	} else static if(UsingCustomWidgets) {
		auto cpd = new ColorPickerDialog(current, onOK, owner);
		cpd.show();
	} else static assert(0);
}

/*
	Hue / Saturation picker
	Lightness Picker

	Text selections

	Graphical representation

	Cancel OK
*/

static if(UsingCustomWidgets)
class ColorPickerDialog : Dialog {
	static arsd.simpledisplay.Sprite hslImage;

	static bool canUseImage;

	void delegate(Color) onOK;

	this(Color current, void delegate(Color) onOK, Window owner) {
		super(360, 350, "Color picker");

		this.onOK = onOK;
 

	/*
	statusBar.parts ~= new StatusBar.Part(140);
	statusBar.parts ~= new StatusBar.Part(140);
	statusBar.parts ~= new StatusBar.Part(140);
	statusBar.parts ~= new StatusBar.Part(140);
        this.addEventListener("mouseover", (Event ev) {
		import std.conv;
                this.statusBar.parts[2].content = to!string(ev.target.minHeight) ~ " - " ~ to!string(ev.target.maxHeight);
                this.statusBar.parts[3].content = ev.target.toString();
        });
	*/


		static if(UsingSimpledisplayX11)
			// it is brutally slow over the network if we don't
			// have xshm, so we've gotta do something else.
			canUseImage = Image.impl.xshmAvailable;
		else
			canUseImage = true;

		if(hslImage is null && canUseImage) {
			auto img = new TrueColorImage(180, 128);
			double h = 0.0, s = 1.0, l = 0.5;
			foreach(y; 0 .. img.height) {
				foreach(x; 0 .. img.width) {
					img.imageData.colors[y * img.width + x] = Color.fromHsl(h,s,l);
					h += 360.0 / img.width;
				}
				h = 0.0;
				s -= 1.0 / img.height;
			}

			hslImage = new arsd.simpledisplay.Sprite(this.win, Image.fromMemoryImage(img));
		}

		auto t = this;

		auto wid = new class Widget {
			this() { super(t); }
			override int minHeight() { return hslImage ? hslImage.height : 4; }
			override int maxHeight() { return hslImage ? hslImage.height : 4; }
		};
		wid.paint = (ScreenPainter painter) {
			if(hslImage)
				hslImage.drawAt(painter, Point(0, 0));
		};

		auto vlRgb = new class VerticalLayout {
			this() {
				super(t);
			}
			override int maxWidth() { return 150; };
		};

		r = new LabeledLineEdit("Red:", vlRgb);
		g = new LabeledLineEdit("Green:", vlRgb);
		b = new LabeledLineEdit("Blue:", vlRgb);
		a = new LabeledLineEdit("Alpha:", vlRgb);

		import std.conv;

		r.content = to!string(current.r);
		g.content = to!string(current.g);
		b.content = to!string(current.b);
		a.content = to!string(current.a);


		if(hslImage !is null)
		wid.addEventListener("mousedown", (Event event) {
			auto h = cast(double) event.clientX / hslImage.width * 360.0;
			auto s = 1.0 - (cast(double) event.clientY / hslImage.height * 1.0);
			auto l = 0.5;

			auto color = Color.fromHsl(h, s, l);

			r.content = to!string(color.r);
			g.content = to!string(color.g);
			b.content = to!string(color.b);
			a.content = to!string(color.a);

		});

		Color currentColor() {
			try {
				return Color(to!int(r.content), to!int(g.content), to!int(b.content), to!int(a.content));
			} catch(Exception e) {
				return Color.transparent;
			}
		}

		this.addEventListener("keydown", (Event event) {
			if(event.key == Key.Enter)
				OK();
			if(event.character == Key.Escape)
				Cancel();
		});

		this.addEventListener("change", {
			redraw();
		});

		auto currentColorWidget = new Widget(this);
		currentColorWidget.paint = (ScreenPainter painter) {
			auto c = currentColor();

			auto c1 = alphaBlend(c, Color(64, 64, 64));
			auto c2 = alphaBlend(c, Color(192, 192, 192));

			painter.outlineColor = c1;
			painter.fillColor = c1;
			painter.drawRectangle(Point(0, 0), currentColorWidget.width / 2, currentColorWidget.height / 2);
			painter.drawRectangle(Point(currentColorWidget.width / 2, currentColorWidget.height / 2), currentColorWidget.width / 2, currentColorWidget.height / 2);

			painter.outlineColor = c2;
			painter.fillColor = c2;
			painter.drawRectangle(Point(currentColorWidget.width / 2, 0), currentColorWidget.width / 2, currentColorWidget.height / 2);
			painter.drawRectangle(Point(0, currentColorWidget.height / 2), currentColorWidget.width / 2, currentColorWidget.height / 2);
		};

		auto hl = new HorizontalLayout(this);
		auto cancelButton = new Button("Cancel", hl);
		auto okButton = new Button("OK", hl);

		recomputeChildLayout(); // FIXME hack

		cancelButton.addEventListener(EventType.triggered, &Cancel);
		okButton.addEventListener(EventType.triggered, &OK);
	}

	LabeledLineEdit r;
	LabeledLineEdit g;
	LabeledLineEdit b;
	LabeledLineEdit a;

	override void OK() {
		import std.conv;
		try {
			onOK(Color(to!int(r.content), to!int(g.content), to!int(b.content), to!int(a.content)));
			this.close();
		} catch(Exception e) {
			auto mb = new MessageBox("Bad value");
			mb.show();
		}
	}
}


