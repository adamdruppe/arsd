/++
	Displays a color-picker dialog box. On Windows, uses the standard system dialog you know from Paint. On X, uses a custom one with hsla and rgba support.

	History:
		Written April 2017.

		Added to dub on December 9, 2021.
+/
module arsd.minigui_addons.color_dialog;

import arsd.minigui;

static if(UsingWin32Widgets)
	pragma(lib, "comdlg32");

/++

+/
auto showColorDialog(Window owner, Color current, void delegate(Color choice) onOK, void delegate() onCancel = null) {
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
		return cpd;
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
		super(owner, 360, 460, "Color picker");

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
			auto img = new TrueColorImage(360, 255);
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
			override int marginBottom() { return 4; }
			override void paint(WidgetPainter painter) {
				if(hslImage)
					hslImage.drawAt(painter, Point(0, 0));
			}
		};

		auto hs = new HorizontalSlider(0, 1000, 50, t);

		auto hr = new HorizontalLayout(t);

		auto vlRgb = new VerticalLayout(180, hr);
		auto vlHsl = new VerticalLayout(180, hr);

		h = new LabeledLineEdit("Hue:", TextAlignment.Right, vlHsl);
		s = new LabeledLineEdit("Saturation:", TextAlignment.Right, vlHsl);
		l = new LabeledLineEdit("Lightness:", TextAlignment.Right, vlHsl);

		css = new LabeledLineEdit("CSS:", TextAlignment.Right, vlHsl);

		r = new LabeledLineEdit("Red:", TextAlignment.Right, vlRgb);
		g = new LabeledLineEdit("Green:", TextAlignment.Right, vlRgb);
		b = new LabeledLineEdit("Blue:", TextAlignment.Right, vlRgb);
		a = new LabeledLineEdit("Alpha:", TextAlignment.Right, vlRgb);

		import std.conv;
		import std.format;

		double[3] lastHsl;

		void updateCurrent() {
			r.content = to!string(current.r);
			g.content = to!string(current.g);
			b.content = to!string(current.b);
			a.content = to!string(current.a);

			auto hsl = current.toHsl;
			if(hsl[2] == 0.0 || hsl[2] == 1.0) {
				hsl[0 .. 2] = lastHsl[0 .. 2];
			}

			h.content = format("%0.3f", hsl[0]);
			s.content = format("%0.3f", hsl[1]);
			l.content = format("%0.3f", hsl[2]);

			hs.setPosition(cast(int) (hsl[2] * 1000));

			css.content = current.toCssString();
			lastHsl = hsl;
		}

		updateCurrent();

		r.addEventListener("focus", &r.selectAll);
		g.addEventListener("focus", &g.selectAll);
		b.addEventListener("focus", &b.selectAll);
		a.addEventListener("focus", &a.selectAll);

		h.addEventListener("focus", &h.selectAll);
		s.addEventListener("focus", &s.selectAll);
		l.addEventListener("focus", &l.selectAll);

		css.addEventListener("focus", &css.selectAll);

		void convertFromHsl() {
			try {
				auto c = Color.fromHsl(h.content.to!double, s.content.to!double, l.content.to!double);
				c.a = a.content.to!ubyte;
				current = c;
				updateCurrent();
			} catch(Exception e) {
			}
		}

		hs.addEventListener((ChangeEvent!int ce) {
			// this should only change l, not hs
			auto ch = h.content;
			auto cs = s.content;
			l.content = to!string(ce.value / 1000.0);
			convertFromHsl();

			h.content = ch;
			s.content = cs;
		});


		h.addEventListener("change", &convertFromHsl);
		s.addEventListener("change", &convertFromHsl);
		l.addEventListener("change", &convertFromHsl);

		css.addEventListener("change", () {
			current = Color.fromString(css.content);
			updateCurrent();
		});

		void helper(MouseEventBase event) {
			try {
				// this should ONLY actually change hue and saturation

				auto h = cast(double) event.clientX / hslImage.width * 360.0;
				auto s = 1.0 - (cast(double) event.clientY / hslImage.height * 1.0);
				auto oldl = this.l.content;
				auto oldhsp = hs.position;
				auto l = this.l.content.to!double;

				current = Color.fromHsl(h, s, l);
				// import std.stdio; writeln(current.toHsl, " ", h, " ", s, " ", l);
				current.a = a.content.to!ubyte;

				updateCurrent();

				this.l.content = oldl;
				hs.setPosition(oldhsp);

				auto e2 = new Event("change", this);
				e2.dispatch();
			} catch(Exception e) {
			}
		}

		if(hslImage !is null)
			wid.addEventListener((MouseDownEvent ev) { helper(ev); });

		if(hslImage !is null)
			wid.addEventListener((MouseMoveEvent event) {
				if(event.state & ModifierState.leftButtonDown)
					helper(event);
			});

		this.addEventListener((KeyDownEvent event) {
			if(event.key == Key.Enter || event.key == Key.PadEnter)
				OK();
			if(event.key == Key.Escape)
				Cancel();
		});

		this.addEventListener("change", {
			redraw();
		});

		auto s = this;
		auto currentColorWidget = new class Widget {
			this() {
				super(s);
			}

			override void paint(WidgetPainter painter) {
				auto c = currentColor();

				auto c1 = alphaBlend(c, Color(64, 64, 64));
				auto c2 = alphaBlend(c, Color(192, 192, 192));

				painter.outlineColor = c1;
				painter.fillColor = c1;
				painter.drawRectangle(Point(0, 0), this.width / 2, this.height / 2);
				painter.drawRectangle(Point(this.width / 2, this.height / 2), this.width / 2, this.height / 2);

				painter.outlineColor = c2;
				painter.fillColor = c2;
				painter.drawRectangle(Point(this.width / 2, 0), this.width / 2, this.height / 2);
				painter.drawRectangle(Point(0, this.height / 2), this.width / 2, this.height / 2);
			}
		};

		auto hl = new HorizontalLayout(this);
		auto cancelButton = new Button("Cancel", hl);
		auto okButton = new Button("OK", hl);

		recomputeChildLayout(); // FIXME hack

		cancelButton.addEventListener(EventType.triggered, &Cancel);
		okButton.addEventListener(EventType.triggered, &OK);

		r.focus();
	}

	LabeledLineEdit r;
	LabeledLineEdit g;
	LabeledLineEdit b;
	LabeledLineEdit a;

	LabeledLineEdit h;
	LabeledLineEdit s;
	LabeledLineEdit l;

	LabeledLineEdit css;

	Color currentColor() {
		import std.conv;
		try {
			return Color(to!int(r.content), to!int(g.content), to!int(b.content), to!int(a.content));
		} catch(Exception e) {
			return Color.transparent;
		}
	}


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


