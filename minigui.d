/+
	BreakpointSplitter
		- if not all widgets fit, it collapses to tabs
		- if they do, you get a splitter
		- you set priority to display things first and optional breakpoint (otherwise it uses flex basis and min width)
+/

// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775498%28v=vs.85%29.aspx

// if doing nested menus, make sure the straight line from where it pops up to any destination on the new popup is not going to disappear the menu until at least a delay

// me@arsd:~/.kde/share/config$ vim kdeglobals

// FIXME: i kinda like how you can show find locations in scrollbars in the chrome browisers i wanna support that here too.

// https://www.freedesktop.org/wiki/Accessibility/AT-SPI2/

// for responsive design, a collapsible widget that if it doesn't have enough room, it just automatically becomes a "more" button or whatever.

// responsive minigui, menu search, and file open with a preview hook on the side.

// FIXME: add menu checkbox and menu icon eventually

// FIXME: checkbox menus and submenus and stuff

// FOXME: look at Windows rebar control too

/*

im tempted to add some css kind of thing to minigui. i've not done in the past cuz i have a lot of virtual functins i use but i think i have an evil plan

the virtual functions remain as the default calculated values. then the reads go through some proxy object that can override it...
*/

// FIXME: a popup with slightly shaped window pointing at the mouse might eb useful in places

// FIXME: text label must be copyable to the clipboard, at least as a full chunk.

// FIXME: opt-in file picker widget with image support

// FIXME: number widget

// https://www.codeguru.com/cpp/controls/buttonctrl/advancedbuttons/article.php/c5161/Native-Win32-ThemeAware-OwnerDraw-Controls-No-MFC.htm
// https://docs.microsoft.com/en-us/windows/win32/controls/using-visual-styles

// osx style menu search.

// would be cool for a scroll bar to have marking capabilities
// kinda like vim's marks just on clicks etc and visual representation
// generically. may be cool to add an up arrow to the bottom too
//
// leave a shadow of where you last were for going back easily

// So a window needs to have a selection, and that can be represented by a type. This is manipulated by various
// functions like cut, copy, paste. Widgets can have a selection and that would assert teh selection ownership for
// the window.

// so what about context menus?

// https://docs.microsoft.com/en-us/windows/desktop/Controls/about-custom-draw

// FIXME: make the scroll thing go to bottom when the content changes.

// add a knob slider view... you click and go up and down so basically same as a vertical slider, just presented as a round image

// FIXME: the scroll area MUST be fixed to use the proper apis under the hood.


// FIXME: add a command search thingy built in and implement tip.
// FIXME: omg omg what if menu functions have arguments and it can pop up a gui or command line script them?!

// On Windows:
// FIXME: various labels look broken in high contrast mode
// FIXME: changing themes while the program is upen doesn't trigger a redraw

// add note about manifest to documentation. also icons.

// a pager control is just a horizontal scroll area just with arrows on the sides instead of a scroll bar
// FIXME: clear the corner of scrollbars if they pop up

// minigui needs to have a stdout redirection for gui mode on windows writeln

// I kinda wanna do state reacting. sort of. idk tho

// need a viewer widget that works like a web page - arrows scroll down consistently

// I want a nanovega widget, and a svg widget with some kind of event handlers attached to the inside.

// FIXME: the menus should be a bit more discoverable, at least a single click to open the others instead of two.
// and help info about menu items.
// and search in menus?

// FIXME: a scroll area event signaling when a thing comes into view might be good
// FIXME: arrow key navigation and accelerators in dialog boxes will be a must

// FIXME: unify Windows style line endings

/*
	TODO:

	pie menu

	class Form with submit behavior -- see AutomaticDialog

	disabled widgets and menu items

	event cleanup
	tooltips.
	api improvements

	margins are kinda broken, they don't collapse like they should. at least.

	a table form btw would be a horizontal layout of vertical layouts holding each column
	that would give the same width things
*/

/*

1(15:19:48) NotSpooky: Menus, text entry, label, notebook, box, frame, file dialogs and layout (this one is very useful because I can draw lines between its child widgets
*/

/++
	minigui is a smallish GUI widget library, aiming to be on par with at least
	HTML4 forms and a few other expected gui components. It uses native controls
	on Windows and does its own thing on Linux (Mac is not currently supported but
	I'm slowly working on it).


	$(H3 Conceptual Overviews)

	A gui application is made out of widgets laid out in windows that display information and respond to events from the user. They also typically have actions available in menus, and you might also want to customize the appearance. How do we do these things with minigui? Let's break it down into several categories.

	$(H4 Code structure)

	You will typically want to create the ui, prepare event handlers, then run an event loop. The event loop drives the program, calling your methods to respond to user activity.

	---
	import arsd.minigui;

	void main() {
		// first, create a window, the (optional) string here is its title
		auto window = new MainWindow("Hello, World!");

		// lay out some widgets inside the window to create the ui
		auto name = new LabeledLineEdit("What is your name?", window);
		auto button = new Button("Say Hello", window);

		// prepare event handlers
		button.addEventListener(EventType.triggered, () {
			window.messageBox("Hello, " ~ name.content ~ "!");
		});

		// show the window and run the event loop until this window is closed
		window.loop();
	}
	---

	To compile, run `opend hello.d`, then run the generated `hello` program.

	While the specifics will change, nearly all minigui applications will roughly follow this pattern.

	$(TIP
		There are two other ways to run event loops: `arsd.simpledisplay.EventLoop.get.run();` and `arsd.core.getThisThreadEventLoop().run();`. They all call the same underlying functions, but have different exit conditions - the `EventLoop.get.run()` keeps running until all top-level windows are closed, and `getThisThreadEventLoop().run` keeps running until all "tasks are resolved"; it is more abstract, supporting more than just windows.

		You may call this if you don't have a single main window.

		Even a basic minigui window can benefit from these if you don't have a single main window:

		---
		import arsd.minigui;

		void main() {
			// create a struct to hold gathered info
			struct Hello { string name; }
			// let minigui create a dialog box to get that
			// info from the user. If you have a main window,
			// you'd pass that here, but it is not required
			dialog((Hello info) {
				// inline handler of the "OK" button
				messageBox("Hello, " ~ info.name);
			});

			// since there is no main window to loop on,
			// we instead call the event loop singleton ourselves
			EventLoop.get.run;
		}
		---

		This is also useful when your programs lives as a notification area (aka systray) icon instead of as a window. But let's not get too far ahead of ourselves!
	)

	$(H4 How to lay out widgets)

	To better understand the details of layout algorithms and see more available included classes, see [Layout].

	$(H5 Default layouts)

	minigui windows default to a flexible vertical layout, where widgets are added, from top to bottom on the window, in the same order of you creating them, then they are sized according to layout hints on the widget itself to fill the available space. This gives a reasonably usable setup but you'll probably want to customize it.

	$(TIP
		minigui's default [VerticalLayout] and [HorizontalLayout] are roughly based on css flexbox with wrap turned off.
	)

	Generally speaking, there are two ways to customize layouts: either subclass the widget and change its hints, or wrap it in another layout widget. You can also create your own layout classes and do it all yourself, but that's fairly complicated. Wrapping existing widgets in other layout widgets is usually the easiest way to make things work.

	$(NOTE
		minigui widgets are not supposed to overlap, but can contain children, and are always rectangular. Children are laid out as rectangles inside the parent's rectangular area.
	)

	For example, to display two widgets side-by-side, you can wrap them in a [HorizontalLayout]:

	---
	import arsd.minigui;
	void main() {
		auto window = new MainWindow();

		// make the layout a child of our window
		auto hl = new HorizontalLayout(window);

		// then make the widgets children of the layout
		auto leftButton = new Button("Left", hl);
		auto rightButton = new Button("Right", hl);

		window.loop();
	}
	---

	A [HorizontalLayout] works just like the default [VerticalLayout], except in the other direction. These two buttons will take up all the available vertical space, then split available horizontal space equally.

	$(H5 Nesting layouts)

	Nesting layouts lets you carve up the rectangle in different ways.

	$(EMBED_UNITTEST layout-example)

	$(H5 Special layouts)

	[TabWidget] can show pages of layouts as tabs.

	See [ScrollableWidget] but be warned that it is weird. You might want to consider something like [GenericListViewWidget] instead.

	$(H5 Other common layout classes)

	[HorizontalLayout], [VerticalLayout], [InlineBlockLayout], [GridLayout]

	$(H4 How to respond to widget events)

	To better understanding the underlying event system, see [Event].

	Each widget emits its own events, which propagate up through their parents until they reach their top-level window.

	$(H4 How to do overall ui - title, icons, menus, toolbar, hotkeys, statuses, etc.)

	We started this series with a [MainWindow], but only added widgets to it. MainWindows also support menus and toolbars with various keyboard shortcuts. You can construct these menus by constructing classes and calling methods, but minigui also lets you just write functions in a command object and it does the rest!

	See [MainWindow.setMenuAndToolbarFromAnnotatedCode] for an example.

	Note that toggleable menu or toolbar items are not yet implemented, but on the todolist. Submenus and disabled items are also not supported at this time and not currently on the work list (but if you need it, let me know and MAYBE we can work something out. Emphasis on $(I maybe)).

	$(TIP
		The automatic dialog box logic is also available for you to invoke on demand with [dialog] and the data setting logic can be used with a child widget inside an existing window [addDataControllerWidget], which also has annotation-based layout capabilities.
	)

	All windows also have titles. You can change this at any time with the `window.title = "string";` property.

	Windows also have icons, which can be set with the `window.icon` property. It takes a [arsd.color.MemoryImage] object, which is an in-memory bitmap. [arsd.image] can load common file formats into these objects, or you can make one yourself. The default icon on Windows is the icon of your exe, which you can set through a resource file. (FIXME: explain how to do this easily.)

	The `MainWindow` also provides a status bar across the bottom. These aren't so common in new applications, but I love them - on my own computer, I even have a global status bar for my whole desktop! I suggest you use it: a status bar is a consistent place to put information and notifications that will never overlap other content.

	A status bar has parts, and the parts have content. The first part's content is assumed to change frequently; the default mouse over event will set it to [Widget.statusTip], a public `string` you can assign to any widget you want at any time.

	Other parts can be added by you and are under your control. You add them with:

	---
	window.statusBar.parts ~= StatusBar.Part(optional_size, optional_units);
	---

	The size can be in a variety of units and what you get with mixes can get complicated. The rule is: explicit pixel sizes are used first. Then, proportional sizes are applied to the remaining space. Then, finally, if there is any space left, any items without an explicit size split them equally.

	You may prefer to set them all at once, with:

	---
	window.statusBar.parts.setSizes(1, 1, 1);
	---

	This makes a three-part status bar, each with the same size - they all take the same proportion of the total size. Negative numbers here will use auto-scaled pixels.

	You should call this right after creating your `MainWindow` as part of your setup code.

	Once you make parts, you can explicitly change their content with `window.statusBar.parts[index].content = "some string";`

	$(NOTE
		I'm thinking about making the other parts do other things by default too, but if I do change it, I'll try not to break any explicitly set things you do anyway.
	)

	If you really don't want a status bar on your main window, you can remove it with `window.statusBar = null;` Make sure you don't try to use it again, or your program will likely crash!

	Status bars, at this time, cannot hold non-text content, but I do want to change that. They also cannot have event listeners at this time, but again, that is likely to change. I have something in mind where they can hold clickable messages with a history and maybe icons, but haven't implemented any of that yet. Right now, they're just a (still very useful!) display area.

	$(H4 How to do custom styles)

	Minigui's custom widgets support styling parameters on the level of individual widgets, or application-wide with [VisualTheme]s.

	$(WARNING
		These don't apply to non-custom widgets! They will use the operating system's native theme unless the documentation for that specific class says otherwise.

		At this time, custom widgets gain capability in styling, but lose capability in terms of keeping all the right integrated details of the user experience and availability to accessibility and other automation tools. Evaluate if the benefit is worth the costs before making your decision.

		I'd like to erase more and more of these gaps, but no promises as to when - or even if - that will ever actually happen.
	)

	See [Widget.Style] for more information.

	$(H4 Selection of categorized widgets)

	$(LIST
		* Buttons: [Button]
		* Text display widgets: [TextLabel], [TextDisplay]
		* Text edit widgets: [LineEdit] (and [LabeledLineEdit]), [PasswordEdit] (and [LabeledPasswordEdit]), [TextEdit]
		* Selecting multiple on/off options: [Checkbox]
		* Selecting just one from a list of options: [Fieldset], [Radiobox], [DropDownSelection]
		* Getting rough numeric input: [HorizontalSlider], [VerticalSlider]
		* Displaying data: [ImageBox], [ProgressBar], [TableView]
		* Showing a list of editable items: [GenericListViewWidget]
		* Helpers for building your own widgets: [OpenGlWidget], [ScrollMessageWidget]
	)

	And more. See [#members] until I write up more of this later and also be aware of the package [arsd.minigui_addons].

	If none of these do what you need, you'll want to write your own. More on that in the following section.

	$(H4 custom widgets - how to write your own)

	See some example programs: https://github.com/adamdruppe/minigui-samples

	When you can't build your application out of existing widgets, you'll want to make your own. The general pattern is to subclass [Widget], write a constructor that takes a `Widget` parent argument you pass to `super`, then set some values, override methods you want to customize, and maybe add child widgets and events as appropriate. You might also be able to subclass an existing other Widget and customize that way.

	To get more specific, let's consider a few illustrative examples, then we'll come back to some principles.

	$(H5 Custom Widget Examples)

	$(H5 More notes)

	See [Widget].

	If you override [Widget.recomputeChildLayout], don't forget to call `registerMovement()` at the top of it, then call recomputeChildLayout of all its children too!

		If you need a nested OS level window, see [NestedChildWindowWidget]. Use [Widget.scaleWithDpi] to convert logical pixels to physical pixels, as required.

		See [Widget.OverrideStyle], [Widget.paintContent], [Widget.dynamicState] for some useful starting points.

		You may also want to provide layout and style hints by overriding things like [Widget.flexBasisWidth], [Widget.flexBasisHeight], [Widget.minHeight], yada, yada, yada.

		You might make a compound widget out of other widgets. [Widget.encapsulatedChildren] can help hide this from the outside world (though is not necessary and might hurt some debugging!)

		$(TIP
			Compile your application with the `-debug` switch and press F12 in your window to open a web-browser-inspired debug window. It sucks right now and doesn't do a lot, but is sometimes better than nothing.
		)

	$(H5 Timers and animations)

	The [Timer] class is available and you can call `widget.redraw();` to trigger a redraw from a timer handler.

	I generally don't like animations in my programs, so it hasn't been a priority for me to do more than this. I also hate uis that move outside of explicit user action, so minigui kinda supports this but I'd rather you didn't. I kinda wanna do something like `requestAnimationFrame` or something but haven't yet so it is just the `Timer` class.

	$(H5 Clipboard integrations, drag and drop)

	GUI application users tend to expect integration with their system, so clipboard support is basically a must, and drag and drop is nice to offer too. The functions for these are provided in [arsd.simpledisplay], which is public imported from minigui, and thus available to you here too.

	I'd like to think of some better abstractions to make this more automagic, but you must do it yourself when implementing your custom widgets right now.

	See: [draggable], [DropHandler], [setClipboardText], [setClipboardImage], [getClipboardText], [getClipboardImage], [setPrimarySelection], and others from simpledisplay.

	$(H5 Context menus)

	Override [Widget.contextMenu] in your subclass.

	$(H4 Coming later)

	Among the unfinished features: unified selections, translateable strings, external integrations.

	$(H2 Running minigui programs)

	Note the environment variable ARSD_SCALING_FACTOR on Linux can set multi-monitor scaling factors. I should also read it from a root window property so it easier to do with migrations... maybe a default theme selector from there too.

	$(H2 Building minigui programs)

	minigui's only required dependencies are [arsd.simpledisplay], [arsd.color], and
	[arsd.textlayouter], on which it is built. simpledisplay provides the low-level
	interfaces and minigui builds the concept of widgets inside the windows on top of it.

	Its #1 goal is to be useful without being large and complicated like GTK and Qt.
	It isn't hugely concerned with appearance - on Windows, it just uses the native
	controls and native theme, and on Linux, it keeps it simple and I may change that
	at any time, though after May 2021, you can customize some things with css-inspired
	[Widget.Style] classes. (On Windows, if you compile with `-version=custom_widgets`,
	you can use the custom implementation there too, but... you shouldn't.)

	The event model is similar to what you use in the browser with Javascript and the
	layout engine tries to automatically fit things in, similar to a css flexbox.

	FOR BEST RESULTS: be sure to link with the appropriate subsystem command
	`-L/SUBSYSTEM:WINDOWS` and -L/entry:mainCRTStartup`. If using ldc instead
	of dmd, use `-L/entry:wmainCRTStartup` instead of `mainCRTStartup`; note the "w".

	Otherwise you'll get a console and possibly other visual bugs. But if you do use
	the subsystem:windows, note that Phobos' writeln will crash the program!

	HTML_To_Classes:
	$(SMALL_TABLE
		HTML Code | Minigui Class

		`<input type="text">` | [LineEdit]
		`<input type="password">` | [PasswordEdit]
		`<textarea>` | [TextEdit]
		`<select>` | [DropDownSelection]
		`<input type="checkbox">` | [Checkbox]
		`<input type="radio">` | [Radiobox]
		`<button>` | [Button]
	)


	Stretchiness:
		The default is 4. You can use larger numbers for things that should
		consume a lot of space, and lower numbers for ones that are better at
		smaller sizes.

	Overlapped_input:
		COMING EVENTUALLY:
		minigui will include a little bit of I/O functionality that just works
		with the event loop. If you want to get fancy, I suggest spinning up
		another thread and posting events back and forth.

	$(H2 Add ons)
		See the `minigui_addons` directory in the arsd repo for some add on widgets
		you can import separately too.

	$(H3 XML definitions)
		If you use [arsd.minigui_xml], you can create widget trees from XML at runtime.

	$(H3 Scriptability)
		minigui is compatible with [arsd.script]. If you see `@scriptable` on a method
		in this documentation, it means you can call it from the script language.

		Tip: to allow easy creation of widget trees from script, import [arsd.minigui_xml]
		and make [arsd.minigui_xml.makeWidgetFromString] available to your script:

		---
		import arsd.minigui_xml;
		import arsd.script;

		var globals = var.emptyObject;
		globals.makeWidgetFromString = &makeWidgetFromString;

		// this now works
		interpret(`var window = makeWidgetFromString("<MainWindow />");`, globals);
		---

		More to come.

	Widget_tree_notes:
		minigui doesn't really formalize these distinctions, but in practice, there are multiple types of widgets:

		$(LIST
			* Containers - a widget that holds other widgets directly, generally [Layout]s. [WidgetContainer] is an attempt to formalize this but is nothing really special.

			* Reparenting containers - a widget that holds other widgets inside a different one of their parents. [MainWindow] is an example - any time you try to add a child to the main window, it actually goes to a special container one layer deeper. [ScrollMessageWidget] also works this way.

			---
			auto child = new Widget(mainWindow);
			assert(child.parent is mainWindow); // fails, its actual parent is mainWindow's inner container instead.
			---

			* Limiting containers - a widget that can only hold children of a particular type. See [TabWidget], which can only hold [TabWidgetPage]s.

			* Simple controls - a widget that cannot have children, but instead does a specific job.

			* Compound controls - a widget that is comprised of children internally to help it do a specific job, but externally acts like a simple control that does not allow any more children. Ideally, this is encapsulated, but in practice, it leaks right now.
		)

		In practice, all of these are [Widget]s right now, but this violates the OOP principles of substitutability since some operations are not actually valid on all subclasses.

		Future breaking changes might be related to making this more structured but im not sure it is that important to actually break stuff over.

	My_UI_Guidelines:
		Note that the Linux custom widgets generally aim to be efficient on remote X network connections.

		In a perfect world, you'd achieve all the following goals:

		$(LIST
			* All operations are present in the menu
			* The operations the user wants at the moment are right where they want them
			* All operations can be scripted
			* The UI does not move any elements without explicit user action
			* All numbers can be seen and typed in if wanted, even if the ui usually hides them
		)

	$(H2 Future Directions)

	I want to do some newer ideas that might not be easy to keep working fully on Windows, like adding a menu search feature and scrollbar custom marks and typing in numbers. I might make them a default part of the widget with custom, and let you provide them through a menu or something elsewhere.

	History:
		In January 2025 (dub v12.0), minigui got a few more breaking changes:

		$(LIST
			* `defaultEventHandler_*` functions take more specific objects. So if you see errors like:

			---
			Error: function `void arsd.minigui.EditableTextWidget.defaultEventHandler_focusin(Event foe)` does not override any function, did you mean to override `void arsd.minigui.Widget.defaultEventHandler_focusin(arsd.minigui.FocusInEvent event)`?
			---

			Go to the file+line number from the error message and change `Event` to `FocusInEvent` (or whatever one it tells you in the "did you mean" part of the error) and recompile. No other changes should be necessary to be compatible with this change.

			* Most event classes, except those explicitly used as a base class, are now marked `final`. If you depended on this subclassing, let me know and I'll see what I can do, but I expect there's little use of it. I now recommend all event classes the `final` unless you are specifically planning on extending it.
		)

		Minigui had mostly additive changes or bug fixes since its inception until May 2021.

		In May 2021 (dub v10.0), minigui got an overhaul. If it was versioned independently, I'd
		tag this as version 2.0.

		Among the changes:
		$(LIST
			* The event model changed to prefer strongly-typed events, though the Javascript string style ones still work, using properties off them is deprecated. It will still compile and function, but you should change the handler to use the classes in its argument list. I adapted my code to use the new model in just a few minutes, so it shouldn't too hard.

			See [Event] for details.

			* A [DoubleClickEvent] was added. Previously, you'd get two rapidly repeated click events. Now, you get one click event followed by a double click event. If you must recreate the old way exactly, you can listen for a DoubleClickEvent, set a flag upon receiving one, then send yourself a synthetic ClickEvent on the next MouseUpEvent, but your program might be better served just working with [MouseDownEvent]s instead.

			See [DoubleClickEvent] for details.

			* Styling hints were added, and the few that existed before have been moved to a new helper class. Deprecated forwarders exist for the (few) old properties to help you transition. Note that most of these only affect a `custom_events` build, which is the default on Linux, but opt in only on Windows.

			See [Widget.Style] for details.

			* Widgets now draw their keyboard focus by default instead of opt in. You may wish to set `tabStop = false;` if it wasn't supposed to receive it.

			* Most Widget constructors no longer have a default `parent` argument. You must pass the parent to almost all widgets, or in rare cases, an explict `null`, but more often than not, you need the parent so the default argument was not very useful at best and misleading to a crash at worst.

			* [LabeledLineEdit] changed its default layout to vertical instead of horizontal. You can restore the old behavior by passing a `TextAlignment` argument to the constructor.

			* Several conversions of public fields to properties, deprecated, or made private. It is unlikely this will affect you, but the compiler will tell you if it does.

			* Various non-breaking additions.
		)
+/
module arsd.minigui;
			// * A widget must now opt in to receiving keyboard focus, rather than opting out.

/++
	This hello world sample will have an oversized button, but that's ok, you see your first window!
+/
version(Demo)
unittest {
	import arsd.minigui;

	void main() {
		auto window = new MainWindow();

		// note the parent widget is almost always passed as the last argument to a constructor
		auto hello = new TextLabel("Hello, world!", TextAlignment.Center, window);
		auto button = new Button("Close", window);
		button.addWhenTriggered({
			window.close();
		});

		window.loop();
	}

	main(); // exclude from docs
}

/++
	$(ID layout-example)

	This example shows one way you can partition your window into a header
	and sidebar. Here, the header and sidebar have a fixed width, while the
	rest of the content sizes with the window.

	It might be a new way of thinking about window layout to do things this
	way - perhaps [GridLayout] more matches your style of thought - but the
	concept here is to partition the window into sub-boxes with a particular
	size, then partition those boxes into further boxes.

	$(IMG //arsdnet.net/minigui-screenshots/windows/layout.png, The example window has a header across the top, then below it a sidebar to the left and a content area to the right.)

	So to make the header, start with a child layout that has a max height.
	It will use that space from the top, then the remaining children will
	split the remaining area, meaning you can think of is as just being another
	box you can split again. Keep splitting until you have the look you desire.
+/
// https://github.com/adamdruppe/arsd/issues/310
version(minigui_screenshots)
@Screenshot("layout")
unittest {
	import arsd.minigui;

	// This helper class is just to help make the layout boxes visible.
	// think of it like a <div style="background-color: whatever;"></div> in HTML.
	class ColorWidget : Widget {
		this(Color color, Widget parent) {
			this.color = color;
			super(parent);
		}
		Color color;
		class Style : Widget.Style {
			override WidgetBackground background() { return WidgetBackground(color); }
		}
		mixin OverrideStyle!Style;
	}

	void main() {
		auto window = new Window;

		// the key is to give it a max height. This is one way to do it:
		auto header = new class HorizontalLayout {
			this() { super(window); }
			override int maxHeight() { return 50; }
		};
		// this next line is a shortcut way of doing it too, but it only works
		// for HorizontalLayout and VerticalLayout, and is less explicit, so it
		// is good to know how to make a new class like above anyway.
		// auto header = new HorizontalLayout(50, window);

		auto bar = new HorizontalLayout(window);

		// or since this is so common, VerticalLayout and HorizontalLayout both
		// can just take an argument in their constructor for max width/height respectively

		// (could have tone this above too, but I wanted to demo both techniques)
		auto left = new VerticalLayout(100, bar);

		// and this is the main section's container. A plain Widget instance is good enough here.
		auto container = new Widget(bar);

		// and these just add color to the containers we made above for the screenshot.
		// in a real application, you can just add your actual controls instead of these.
		auto headerColorBox = new ColorWidget(Color.teal, header);
		auto leftColorBox = new ColorWidget(Color.green, left);
		auto rightColorBox = new ColorWidget(Color.purple, container);

		window.loop();
	}

	main(); // exclude from docs
}


import arsd.core;
import arsd.textlayouter;

alias Timer = arsd.simpledisplay.Timer;
public import arsd.simpledisplay;
/++
	Convenience import to override the Windows GDI Rectangle function (you can still use it through fully-qualified imports)

	History:
		Was private until May 15, 2021.
+/
public alias Rectangle = arsd.color.Rectangle; // I specifically want this in here, not the win32 GDI Rectangle()

version(Windows) {
	import core.sys.windows.winnls;
	import core.sys.windows.windef;
	import core.sys.windows.basetyps;
	import core.sys.windows.winbase;
	import core.sys.windows.winuser;
	import core.sys.windows.wingdi;
	static import gdi = core.sys.windows.wingdi;
}

version(Windows) {
	// to swap the default
	// version(minigui_manifest) {} else version=minigui_no_manifest;

	version(minigui_no_manifest) {} else {
		version(D_OpenD) {
			// OpenD always supports it
			version=UseManifestMinigui;
		} else {
			static if(__VERSION__ >= 2_083)
			version(CRuntime_Microsoft) // FIXME: mingw?
				version=UseManifestMinigui;
		}

	}


	version(UseManifestMinigui) {
		// assume we want commctrl6 whenever possible since there's really no reason not to
		// and this avoids some of the manifest hassle
		pragma(linkerDirective, "\"/manifestdependency:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"");
	}
}

// this is a hack to call the original window procedure on native win32 widgets if our event listener thing prevents default.
private bool lastDefaultPrevented;

/// Methods marked with this are available from scripts if added to the [arsd.script] engine.
alias scriptable = arsd_jsvar_compatible;

version(Windows) {
	// use native widgets when available unless specifically asked otherwise
	version(custom_widgets) {
		enum bool UsingCustomWidgets = true;
		enum bool UsingWin32Widgets = false;
	} else {
		version = win32_widgets;
		enum bool UsingCustomWidgets = false;
		enum bool UsingWin32Widgets = true;
	}
	// and native theming when needed
	//version = win32_theming;
} else {
	enum bool UsingCustomWidgets = true;
	enum bool UsingWin32Widgets = false;
	version=custom_widgets;
}



/*

	The main goals of minigui.d are to:
		1) Provide basic widgets that just work in a lightweight lib.
		   I basically want things comparable to a plain HTML form,
		   plus the easy and obvious things you expect from Windows
		   apps like a menu.
		2) Use native things when possible for best functionality with
		   least library weight.
		3) Give building blocks to provide easy extension for your
		   custom widgets, or hooking into additional native widgets
		   I didn't wrap.
		4) Provide interfaces for easy interaction between third
		   party minigui extensions. (event model, perhaps
		   signals/slots, drop-in ease of use bits.)
		5) Zero non-system dependencies, including Phobos as much as
		   I reasonably can. It must only import arsd.color and
		   my simpledisplay.d. If you need more, it will have to be
		   an extension module.
		6) An easy layout system that generally works.

	A stretch goal is to make it easy to make gui forms with code,
	some kind of resource file (xml?) and even a wysiwyg designer.

	Another stretch goal is to make it easy to hook data into the gui,
	including from reflection. So like auto-generate a form from a
	function signature or struct definition, or show a list from an
	array that automatically updates as the array is changed. Then,
	your program focuses on the data more than the gui interaction.



	STILL NEEDED:
		* combo box. (this is diff than select because you can free-form edit too. more like a lineedit with autoselect)
		* slider
		* listbox
		* spinner
		* label?
		* rich text
*/


/+
	enum LayoutMethods {
		 verticalFlex,
		 horizontalFlex,
		 inlineBlock, // left to right, no stretch, goes to next line as needed
		 static, // just set to x, y
		 verticalNoStretch, // browser style default

		 inlineBlockFlex, // goes left to right, flexing, but when it runs out of space, it spills into next line

		 grid, // magic
	}
+/

/++
	The `Widget` is the base class for minigui's functionality, ranging from UI components like checkboxes or text displays to abstract groupings of other widgets like a layout container or a html `<div>`. You will likely want to use pre-made widgets as well as creating your own.


	To create your own widget, you must inherit from it and create a constructor that passes a parent to `super`. Everything else after that is optional.

	---
	class MinimalWidget : Widget {
		this(Widget parent) {
			super(parent);
		}
	}
	---

	$(SIDEBAR
		I'm not entirely happy with leaf, container, and windows all coming from the same base Widget class, but I so far haven't thought of a better solution that's good enough to justify the breakage of a transition. It hasn't been a major problem in practice anyway.
	)

	Broadly, there's two kinds of widgets: leaf widgets, which are intended to be the direct user-interactive components, and container widgets, which organize, lay out, and aggregate other widgets in the object tree. A special case of a container widget is [Window], which represents a separate top-level window on the screen. Both leaf and container widgets inherit from `Widget`, so this distinction is more conventional than formal.

	Among the things you'll most likely want to change in your custom widget:

	$(LIST
		* In your constructor, set `tabStop = false;` if the widget is not supposed to receive keyboard focus. (Please note its childen still can, so `tabStop = false;` is appropriate on most container widgets.)

		You may explicitly set `tabStop = true;` to ensure you get it, even against future changes to the library, though that's the default right now.

		Do this $(I after) calling the `super` constructor.

		* Override [paint] if you want full control of the widget's drawing area (except the area obscured by children!), or [paintContent] if you want to participate in the styling engine's system. You'll also possibly want to make a subclass of [Style] and use [OverrideStyle] to change the default hints given to the styling engine for widget.

		Generally, painting is a job for leaf widgets, since child widgets would obscure your drawing area anyway. However, it is your decision.

		* Override default event handlers with your behavior. For example [defaultEventHandler_click] may be overridden to make clicks do something. Again, this is generally a job for leaf widgets rather than containers; most events are dispatched to the lowest leaf on the widget tree, but they also pass through all their parents. See [Event] for more details about the event model.

		* You may also want to override the various layout hints like [minWidth], [maxHeight], etc. In particular [Padding] and [Margin] are often relevant for both container and leaf widgets and the default values of 0 are often not what you want.
	)

	On Microsoft Windows, many widgets are also based on native controls. You can also do this if `static if(UsingWin32Widgets)` passes. You should use the helper function [createWin32Window] to create the window and let minigui do what it needs to do to create its bridge structures. This will populate [Widget.hwnd] which you can access later for communcating with the native window. You may also consider overriding [Widget.handleWmCommand] and [Widget.handleWmNotify] for the widget to translate those messages into appropriate minigui [Event]s.

	It is also possible to embed a [SimpleWindow]-based native window inside a widget. See [OpenGlWidget]'s source code as an example.

	Your own custom-drawn and native system controls can exist side-by-side.

	Later I'll add more complete examples, but for now [TextLabel] and [LabeledPasswordEdit] are both simple widgets you can view implementation to get some ideas.
+/
class Widget : ReflectableProperties {

	private int toolbarIconSize() {
		return scaleWithDpi(24);
	}


	/++
		Returns the current size of the widget.

		History:
			Added January 3, 2025
	+/
	final Size size() const {
		return Size(width, height);
	}

	private bool willDraw() {
		return true;
	}

	/+
	/++
		Calling this directly after constructor can give you a reflectable object as-needed so you don't pay for what you don't need.

		History:
			Added September 15, 2021
			implemented.... ???
	+/
	void prepareReflection(this This)() {

	}
	+/

	private bool _enabled = true;

	/++
		Determines whether the control is marked enabled. Disabled controls are generally displayed as greyed out and clicking on them does nothing. It is also possible for a control to be disabled because its parent is disabled, in which case this will still return `true`, but setting `enabled = true` may have no effect. Check [disabledBy] to see which parent caused it to be disabled.

		I also recommend you set a [disabledReason] if you chose to set `enabled = false` to tell the user why the control does not work and what they can do to enable it.

		History:
			Added November 23, 2021 (dub v10.4)

			Warning: the specific behavior of disabling with parents may change in the future.
		Bugs:
			Currently only implemented for widgets backed by native Windows controls.

		See_Also: [disabledReason], [disabledBy]
	+/
	@property bool enabled() {
		return disabledBy() is null;
	}

	/// ditto
	@property void enabled(bool yes) {
		_enabled = yes;
		version(win32_widgets) {
			if(hwnd)
				EnableWindow(hwnd, yes);
		}
		setDynamicState(DynamicState.disabled, yes);
	}

	private string disabledReason_;

	/++
		If the widget is not [enabled] this string may be presented to the user when they try to use it. The exact manner and time it gets displayed is up to the implementation of the control.

		Setting this does NOT disable the widget. You need to call `enabled = false;` separately. It does set the data though.

		History:
			Added November 23, 2021 (dub v10.4)
		See_Also: [enabled], [disabledBy]
	+/
	@property string disabledReason() {
		auto w = disabledBy();
		return (w is null) ? null : w.disabledReason_;
	}

	/// ditto
	@property void disabledReason(string reason) {
		disabledReason_ = reason;
	}

	/++
		Returns the widget that disabled this. It might be this or one of its parents all the way up the chain, or `null` if the widget is not disabled by anything. You can check [disabledReason] on the return value (after the null check!) to get a hint to display to the user.

		History:
			Added November 25, 2021 (dub v10.4)
		See_Also: [enabled], [disabledReason]
	+/
	Widget disabledBy() {
		Widget p = this;
		while(p) {
			if(!p._enabled)
				return p;
			p = p.parent;
		}
		return null;
	}

	/// Implementations of [ReflectableProperties] interface. See the interface for details.
	SetPropertyResult setPropertyFromString(string name, scope const(char)[] value, bool valueIsJson) {
		if(valueIsJson)
			return SetPropertyResult.wrongFormat;
		switch(name) {
			case "name":
				this.name = value.idup;
				return SetPropertyResult.success;
			case "statusTip":
				this.statusTip = value.idup;
				return SetPropertyResult.success;
			default:
				return SetPropertyResult.noSuchProperty;
		}
	}
	/// ditto
	void getPropertiesList(scope void delegate(string name) sink) const {
		sink("name");
		sink("statusTip");
	}
	/// ditto
	void getPropertyAsString(string name, scope void delegate(string name, scope const(char)[] value, bool valueIsJson) sink) {
		switch(name) {
			case "name":
				sink(name, this.name, false);
				return;
			case "statusTip":
				sink(name, this.statusTip, false);
				return;
			default:
				sink(name, null, true);
		}
	}

	/++
		Scales the given value to the system-reported DPI for the monitor on which the widget resides.

		History:
			Added November 25, 2021 (dub v10.5)
			`Point` overload added January 12, 2022 (dub v10.6)
	+/
	int scaleWithDpi(int value, int assumedDpi = 96) {
		// avoid potential overflow with common special values
		if(value == int.max)
			return int.max;
		if(value == int.min)
			return int.min;
		if(value == 0)
			return 0;
		return value * currentDpi(assumedDpi) / assumedDpi;
	}

	/// ditto
	Point scaleWithDpi(Point value, int assumedDpi = 96) {
		return Point(scaleWithDpi(value.x, assumedDpi), scaleWithDpi(value.y, assumedDpi));
	}

	/++
		Returns the current scaling factor as a logical dpi value for this widget. Generally speaking, this divided by 96 gives you the user scaling factor.

		Not entirely stable.

		History:
			Added August 25, 2023 (dub v11.1)
	+/
	final int currentDpi(int assumedDpi = 96) {
		// assert(parentWindow !is null);
		// assert(parentWindow.win !is null);
		auto divide = (parentWindow && parentWindow.win) ? parentWindow.win.actualDpi : assumedDpi;
		//divide = 138; // to test 1.5x
		// for lower values it is something i don't really want changed anyway since it is an old monitor and you don't want to scale down.
		// this also covers the case when actualDpi returns 0.
		if(divide < 96)
			divide = 96;
		return divide;
	}

	// avoid this it just forwards to a soon-to-be-deprecated function and is not remotely stable
	// I'll think up something better eventually

	// FIXME: the defaultLineHeight should probably be removed and replaced with the calculations on the outside based on defaultTextHeight.
	protected final int defaultLineHeight() {
		auto cs = getComputedStyle();
		if(cs.font && !cs.font.isNull)
			return cs.font.height() * 5 / 4;
		else
			return scaleWithDpi(Window.lineHeightNotDeprecatedButShouldBeSinceItIsJustAFallback * 5/4);
	}

	/++

		History:
			Added August 25, 2023 (dub v11.1)
	+/
	protected final int defaultTextHeight(int numberOfLines = 1) {
		auto cs = getComputedStyle();
		if(cs.font && !cs.font.isNull)
			return cs.font.height() * numberOfLines;
		else
			return Window.lineHeightNotDeprecatedButShouldBeSinceItIsJustAFallback * numberOfLines;
	}

	protected final int defaultTextWidth(const(char)[] text) {
		auto cs = getComputedStyle();
		if(cs.font && !cs.font.isNull)
			return cs.font.stringWidth(text);
		else
			return scaleWithDpi(Window.lineHeightNotDeprecatedButShouldBeSinceItIsJustAFallback * cast(int) text.length / 2);
	}

	/++
		If `encapsulatedChildren` returns true, it changes the event handling mechanism to act as if events from the child widgets are actually targeted on this widget.

		The idea is then you can use child widgets as part of your implementation, but not expose those details through the event system; if someone checks the mouse coordinates and target of the event once it bubbles past you, it will show as it it came from you.

		History:
			Added May 22, 2021
	+/
	protected bool encapsulatedChildren() {
		return false;
	}

	private void privateDpiChanged() {
		dpiChanged();
		foreach(child; children)
			child.privateDpiChanged();
	}

	/++
		Virtual hook to update any caches or fonts you need on the event of a dpi scaling change.

		History:
			Added January 12, 2022 (dub v10.6)
	+/
	protected void dpiChanged() {

	}

	// Default layout properties {

		int minWidth() { return 0; }
		int minHeight() {
			// default widgets have a vertical layout, therefore the minimum height is the sum of the contents
			int sum = this.paddingTop + this.paddingBottom;
			foreach(child; children) {
				if(child.hidden)
					continue;
				sum += child.minHeight();
				sum += child.marginTop();
				sum += child.marginBottom();
			}

			return sum;
		}
		int maxWidth() { return int.max; }
		int maxHeight() { return int.max; }
		int widthStretchiness() { return 4; }
		int heightStretchiness() { return 4; }

		/++
			Where stretchiness will grow from the flex basis, this shrinkiness will let it get smaller if needed to make room for other items.

			History:
				Added June 15, 2021 (dub v10.1)
		+/
		int widthShrinkiness() { return 0; }
		/// ditto
		int heightShrinkiness() { return 0; }

		/++
			The initial size of the widget for layout calculations. Default is 0.

			See_Also: [https://developer.mozilla.org/en-US/docs/Web/CSS/flex-basis|CSS flex-basis]

			History:
				Added June 15, 2021 (dub v10.1)
		+/
		int flexBasisWidth() { return 0; }
		/// ditto
		int flexBasisHeight() { return 0; }

		/++
			Not stable.

			Values are scaled with dpi after assignment. If you override the virtual functions, this may be ignored.

			So if you set defaultPadding to 4 and the user is on 150% zoom, it will multiply to return 6.

			History:
				Added January 5, 2023
		+/
		Rectangle defaultMargin;
		/// ditto
		Rectangle defaultPadding;

		int marginLeft() { return scaleWithDpi(defaultMargin.left); }
		int marginRight() { return scaleWithDpi(defaultMargin.right); }
		int marginTop() { return scaleWithDpi(defaultMargin.top); }
		int marginBottom() { return scaleWithDpi(defaultMargin.bottom); }
		int paddingLeft() { return scaleWithDpi(defaultPadding.left); }
		int paddingRight() { return scaleWithDpi(defaultPadding.right); }
		int paddingTop() { return scaleWithDpi(defaultPadding.top); }
		int paddingBottom() { return scaleWithDpi(defaultPadding.bottom); }
		//LinePreference linePreference() { return LinePreference.PreferOwnLine; }

		private bool recomputeChildLayoutRequired = true;
		private static class RecomputeEvent {}
		private __gshared rce = new RecomputeEvent();
		protected final void queueRecomputeChildLayout() {
			recomputeChildLayoutRequired = true;

			if(this.parentWindow) {
				auto sw = this.parentWindow.win;
				assert(sw !is null);
				if(!sw.eventQueued!RecomputeEvent) {
					sw.postEvent(rce);
					// writeln("redraw requested from ", file,":",line," ", this.parentWindow.win.impl.window);
				}
			}

		}

		protected final void recomputeChildLayoutEntry() {
			if(recomputeChildLayoutRequired) {
				recomputeChildLayout();
				recomputeChildLayoutRequired = false;
				redraw();
			} else {
				// I still need to check the tree just in case one of them was queued up
				// and the event came up here instead of there.
				foreach(child; children)
					child.recomputeChildLayoutEntry();
			}
		}

		// this function should (almost) never be called directly anymore... call recomputeChildLayoutEntry when executing it and queueRecomputeChildLayout if you just want it done soon
		void recomputeChildLayout() {
			.recomputeChildLayout!"height"(this);
		}

	// }


	/++
		Returns the style's tag name string this object uses.

		The default is to use the typeid() name trimmed down to whatever is after the last dot which is typically the identifier of the class.

		This tag may never be used, it is just available for the [VisualTheme.getPropertyString] if it chooses to do something like CSS.

		History:
			Added May 10, 2021
	+/
	string styleTagName() const {
		string n = typeid(this).name;
		foreach_reverse(idx, ch; n)
			if(ch == '.') {
				n = n[idx + 1 .. $];
				break;
			}
		return n;
	}

	/// API for the [styleClassList]
	static struct ClassList {
		private Widget widget;

		///
		void add(string s) {
			widget.styleClassList_ ~= s;
		}

		///
		void remove(string s) {
			foreach(idx, s1; widget.styleClassList_)
				if(s1 == s) {
					widget.styleClassList_[idx] = widget.styleClassList_[$-1];
					widget.styleClassList_ = widget.styleClassList_[0 .. $-1];
					widget.styleClassList_.assumeSafeAppend();
					return;
				}
		}

		/// Returns true if it was added, false if it was removed.
		bool toggle(string s) {
			if(contains(s)) {
				remove(s);
				return false;
			} else {
				add(s);
				return true;
			}
		}

		///
		bool contains(string s) const {
			foreach(s1; widget.styleClassList_)
				if(s1 == s)
					return true;
			return false;

		}
	}

	private string[] styleClassList_;

	/++
		Returns a "class list" that can be used by the visual theme's style engine via [VisualTheme.getPropertyString] if it chooses to do something like CSS.

		It has no inherent meaning, it is really just a place to put some metadata tags on individual objects.

		History:
			Added May 10, 2021
	+/
	inout(ClassList) styleClassList() inout {
		return cast(inout(ClassList)) ClassList(cast() this);
	}

	/++
		List of dynamic states made available to the style engine, for cases like CSS pseudo-classes and also used by default paint methods. It is stored in a 64 bit variable attached to the widget that you can update. The style cache is aware of the fact that these can frequently change.

		The lower 32 bits are defined here or reserved for future use by the library. You should keep these updated if you reasonably can on custom widgets if they apply to you, but don't use them for a purpose they aren't defined for.

		The upper 32 bits are available for your own extensions.

		History:
			Added May 10, 2021

		Examples:

		---
		addEventListener((MouseUpEvent ev) {
			if(ev.button == MouseButton.left) {
				// the first arg is the state to modify, the second arg is what to set it to
				setDynamicState(DynamicState.depressed, false);
			}
		});
		---

	+/
	enum DynamicState : ulong {
		focus = (1 << 0), /// the widget currently has the keyboard focus
		hover = (1 << 1), /// the mouse is currently hovering over the widget (may not always be updated)
		valid = (1 << 2), /// the widget's content has been validated and it passed (do not set if no validation has been performed!)
		invalid = (1 << 3), /// the widget's content has been validated and it failed (do not set if no validation has been performed!)
		checked = (1 << 4), /// the widget is toggleable and currently toggled on
		selected = (1 << 5), /// the widget represents one option of many and is currently selected, but is not necessarily focused nor checked.
		disabled = (1 << 6), /// the widget is currently unable to perform its designated task
		indeterminate = (1 << 7), /// the widget has tri-state and is between checked and not checked
		depressed = (1 << 8), /// the widget is being actively pressed or clicked (compare to css `:active`). Can be combined with hover to visually indicate if a mouse up would result in a click event.

		USER_BEGIN = (1UL << 32),
	}

	// I want to add the primary and cancel styles to buttons at least at some point somehow.

	/// ditto
	@property ulong dynamicState() { return dynamicState_; }
	/// ditto
	@property ulong dynamicState(ulong newValue) {
		if(dynamicState != newValue) {
			auto old = dynamicState_;
			dynamicState_ = newValue;

			useStyleProperties((scope Widget.Style s) {
				if(s.variesWithState(old ^ newValue))
					redraw();
			});
		}
		return dynamicState_;
	}

	/// ditto
	void setDynamicState(ulong flags, bool state) {
		auto ds = dynamicState_;
		if(state)
			ds |= flags;
		else
			ds &= ~flags;

		dynamicState = ds;
	}

	private ulong dynamicState_;

	deprecated("Use dynamic styles instead now") {
		Color backgroundColor() { return backgroundColor_; }
		void backgroundColor(Color c){ this.backgroundColor_ = c; }

		MouseCursor cursor() { return GenericCursor.Default; }
	} private Color backgroundColor_ = Color.transparent;


	/++
		Style properties are defined as an accessory class so they can be referenced and overridden independently, but they are nested so you can refer to them easily by name (e.g. generic `Widget.Style` vs `Button.Style` and such).

		It is here so there can be a specificity switch.

		See [OverrideStyle] for a helper function to use your own.

		History:
			Added May 11, 2021
	+/
	static class Style/* : StyleProperties*/ {
		public Widget widget; // public because the mixin template needs access to it

		/++
			You must override this to trigger automatic redraws if you ever uses the `dynamicState` flag in your style.

			History:
				Added May 11, 2021, but changed on July 2, 2021 to return false by default. You MUST override this if you want declarative hover effects etc to take effect.
		+/
		bool variesWithState(ulong dynamicStateFlags) {
			version(win32_widgets) {
				if(widget.hwnd)
					return false;
			}
			return widget.tabStop && ((dynamicStateFlags & DynamicState.focus) ? true : false);
		}

		///
		Color foregroundColor() {
			return WidgetPainter.visualTheme.foregroundColor;
		}

		///
		WidgetBackground background() {
			// the default is a "transparent" background, which means
			// it goes as far up as it can to get the color
			if (widget.backgroundColor_ != Color.transparent)
				return WidgetBackground(widget.backgroundColor_);
			if (widget.parent)
				return widget.parent.getComputedStyle.background;
			return WidgetBackground(widget.backgroundColor_);
		}

		private static OperatingSystemFont fontCached_;
		private OperatingSystemFont fontCached() {
			if(fontCached_ is null)
				fontCached_ = font();
			return fontCached_;
		}

		/++
			Returns the default font to be used with this widget. The return value will be cached by the library, so you can not expect live updates.
		+/
		OperatingSystemFont font() {
			return null;
		}

		/++
			Returns the cursor that should be used over this widget. You may change this and updates will be reflected next time the mouse enters the widget.

			You can return a member of [GenericCursor] or your own [MouseCursor] instance.

			History:
				Was previously a method directly on [Widget], moved to [Widget.Style] on May 12, 2021
		+/
		MouseCursor cursor() {
			return GenericCursor.Default;
		}

		FrameStyle borderStyle() {
			return FrameStyle.none;
		}

		/++
		+/
		Color borderColor() {
			return Color.transparent;
		}

		FrameStyle outlineStyle() {
			if(widget.dynamicState & DynamicState.focus)
				return FrameStyle.dotted;
			else
				return FrameStyle.none;
		}

		Color outlineColor() {
			return foregroundColor;
		}
	}

	/++
		This mixin overrides the [useStyleProperties] method to direct it toward your own style class.
		The basic usage is simple:

		---
		static class Style : YourParentClass.Style { /* YourParentClass is frequently Widget, of course, but not always */
			// override style hints as-needed here
		}
		OverrideStyle!Style; // add the method
		---

		$(TIP
			While the class is not forced to be `static`, for best results, it should be. A non-static class
			can not be inherited by other objects whereas the static one can. A property on the base class,
			called [Widget.Style.widget|widget], is available for you to access its properties.
		)

		This exists just because [useStyleProperties] has a somewhat convoluted signature and its overrides must
		repeat them. Moreover, its implementation uses a stack class to optimize GC pressure from small fetches
		and that's a little tedious to repeat in your child classes too when you only care about changing the type.


		It also has a further facility to pick a wholly differnet class based on the [DynamicState] of the Widget.
		You may also just override `variesWithState` when you use this flag.

		---
		mixin OverrideStyle!(
			DynamicState.focus, YourFocusedStyle,
			DynamicState.hover, YourHoverStyle,
			YourDefaultStyle
		)
		---

		It checks if `dynamicState` matches the state and if so, returns the object given.

		If there is no state mask given, the next one matches everything. The first match given is used.

		However, since in most cases you'll want check state inside your individual methods, you probably won't
		find much use for this whole-class swap out.

		History:
			Added May 16, 2021
	+/
	static protected mixin template OverrideStyle(S...) {
		static import amg = arsd.minigui;
		override void useStyleProperties(scope void delegate(scope amg.Widget.Style props) dg) {
			ulong mask = 0;
			foreach(idx, thing; S) {
				static if(is(typeof(thing) : ulong)) {
					mask = thing;
				} else {
					if(!(idx & 1) || (this.dynamicState & mask) == mask) {
						//static assert(!__traits(isNested, thing), thing.stringof ~ " is a nested class. For best results, mark it `static`. You can still access the widget through a `widget` variable inside the Style class.");
						scope amg.Widget.Style s = new thing();
						s.widget = this;
						dg(s);
						return;
					}
				}
			}
		}
	}
	/++
		You can override this by hand, or use the [OverrideStyle] helper which is a bit less verbose.
	+/
	void useStyleProperties(scope void delegate(scope Style props) dg) {
		scope Style s = new Style();
		s.widget = this;
		dg(s);
	}


	protected void sendResizeEvent() {
		this.emit!ResizeEvent();
	}

	/++
		Override this to provide a custom context menu for your widget. (x, y) is where the menu was requested. If x == -1 && y == -1, the menu was triggered by the keyboard instead of the mouse and it should use the current cursor, selection, or whatever would make sense for where a keyboard user's attention would currently be.

		It should return an instance of the [Menu] object. You may choose to cache this object. To construct one, either make `new Menu("", this);` (the empty string there is the menu's label, but for a context menu, that is not important), then call the `menu.addItem(new Action("Label Text", 0 /* icon id */, () { on clicked handler }), menu);` and `menu.addSeparator() methods, or use `return createContextMenuFromAnnotatedCode(this, some_command_struct);`

		Context menus are automatically triggered by default by the keyboard menu key, mouse right click, and possibly other conventions per platform. You can also invoke one by calling the [showContextMenu] method.

		See_Also:
			[createContextMenuFromAnnotatedCode]
	+/
	Menu contextMenu(int x, int y) { return null; }

	/++
		Shows the widget's context menu, as if the user right clicked at the x, y position. You should rarely, if ever, have to call this, since default event handlers will do it for you automatically. To control what menu shows up, you can pass one as `menuToShow`, but if you don't, it will call [contextMenu], which you can override on a per-widget basis.

		History:
			The `menuToShow` parameter was added on March 19, 2025.
	+/
	final bool showContextMenu(int x, int y, Menu menuToShow = null) {
		return showContextMenu(x, y, -2, -2, menuToShow);
	}

	private final bool showContextMenu(int x, int y, int screenX, int screenY, Menu menu = null) {
		if(parentWindow is null || parentWindow.win is null) return false;

		if(menu is null)
			menu = this.contextMenu(x, y);

		if(menu is null)
			return false;

		version(win32_widgets) {
			// FIXME: if it is -1, -1, do it at the current selection location instead
			// tho the corner of the window, which it does now, isn't the literal worst.

			// i see notepad just seems to put it in the center of the window so idk

			if(screenX < 0 && screenY < 0) {
				auto p = this.globalCoordinates();
				if(screenX == -2)
					p.x += x;
				if(screenY == -2)
					p.y += y;

				screenX = p.x;
				screenY = p.y;
			}

			if(!TrackPopupMenuEx(menu.handle, 0, screenX, screenY, parentWindow.win.impl.hwnd, null))
				throw new Exception("TrackContextMenuEx");
		} else version(custom_widgets) {
			menu.popup(this, x, y);
		}

		return true;
	}

	/++
		Removes this widget from its parent.

		History:
			`removeWidget` was made `final` on May 11, 2021.
	+/
	@scriptable
	final void removeWidget() {
		auto p = this.parent;
		if(p) {
			int item;
			for(item = 0; item < p._children.length; item++)
				if(p._children[item] is this)
					break;
			auto idx = item;
			for(; item < p._children.length - 1; item++)
				p._children[item] = p._children[item + 1];
			p._children = p._children[0 .. $-1];

			this.parent.widgetRemoved(idx, this);
			//this.parent = null;

			p.queueRecomputeChildLayout();
		}
		version(win32_widgets) {
			removeAllChildren();
			if(hwnd) {
				DestroyWindow(hwnd);
				hwnd = null;
			}
		}
	}

	/++
		Notifies the subclass that a widget was removed. If you keep auxillary data about your children, you can override this to help keep that data in sync.

		History:
			Added September 19, 2021
	+/
	protected void widgetRemoved(size_t oldIndex, Widget oldReference) { }

	/++
		Removes all child widgets from `this`. You should not use the removed widgets again.

		Note that on Windows, it also destroys the native handles for the removed children recursively.

		History:
			Added July 1, 2021 (dub v10.2)
	+/
	void removeAllChildren() {
		version(win32_widgets)
		foreach(child; _children) {
			child.removeAllChildren();
			if(child.hwnd) {
				DestroyWindow(child.hwnd);
				child.hwnd = null;
			}
		}
		auto orig = this._children;
		this._children = null;
		foreach(idx, w; orig)
			this.widgetRemoved(idx, w);

		queueRecomputeChildLayout();
	}

	/++
		Calls [getByName] with the generic type of Widget. Meant for script interop where instantiating a template is impossible.
	+/
	@scriptable
	Widget getChildByName(string name) {
		return getByName(name);
	}
	/++
		Finds the nearest descendant with the requested type and [name]. May return `this`.
	+/
	final WidgetClass getByName(WidgetClass = Widget)(string name) {
		if(this.name == name)
			if(auto c = cast(WidgetClass) this)
				return c;
		foreach(child; children) {
			auto w = child.getByName(name);
			if(auto c = cast(WidgetClass) w)
				return c;
		}
		return null;
	}

	/++
		The name is a string tag that is used to reference the widget from scripts, gui loaders, declarative ui templates, etc. Similar to a HTML id attribute.
		Names should be unique in a window.

		See_Also: [getByName], [getChildByName]
	+/
	@scriptable string name;

	private EventHandler[][string] bubblingEventHandlers;
	private EventHandler[][string] capturingEventHandlers;

	/++
		Default event handlers. These are called on the appropriate
		event unless [Event.preventDefault] is called on the event at
		some point through the bubbling process.


		If you are implementing your own widget and want to add custom
		events, you should follow the same pattern here: create a virtual
		function named `defaultEventHandler_eventname` with the implementation,
		then, override [setupDefaultEventHandlers] and add a wrapped caller to
		`defaultEventHandlers["eventname"]`. It should be wrapped like so:
		`defaultEventHandlers["eventname"] = (Widget t, Event event) { t.defaultEventHandler_name(event); };`.
		This ensures virtual dispatch based on the correct subclass.

		Also, don't forget to call `super.setupDefaultEventHandlers();` too in your
		overridden version.

		You only need to do that on parent classes adding NEW event types. If you
		just want to change the default behavior of an existing event type in a subclass,
		you override the function (and optionally call `super.method_name`) like normal.

		History:
			Some of the events changed to take specific subclasses instead of generic `Event`
			on January 3, 2025.

	+/
	protected EventHandler[string] defaultEventHandlers;

	/// ditto
	void setupDefaultEventHandlers() {
		defaultEventHandlers["click"] = (Widget t, Event event)      { if(auto e = cast(ClickEvent) event) t.defaultEventHandler_click(e); };
		defaultEventHandlers["dblclick"] = (Widget t, Event event)   { if(auto e = cast(DoubleClickEvent) event) t.defaultEventHandler_dblclick(e); };
		defaultEventHandlers["keydown"] = (Widget t, Event event)    { if(auto e = cast(KeyDownEvent) event) t.defaultEventHandler_keydown(e); };
		defaultEventHandlers["keyup"] = (Widget t, Event event)      { if(auto e = cast(KeyUpEvent) event) t.defaultEventHandler_keyup(e); };
		defaultEventHandlers["mouseover"] = (Widget t, Event event)  { if(auto e = cast(MouseOverEvent) event) t.defaultEventHandler_mouseover(e); };
		defaultEventHandlers["mouseout"] = (Widget t, Event event)   { if(auto e = cast(MouseOutEvent) event) t.defaultEventHandler_mouseout(e); };
		defaultEventHandlers["mousedown"] = (Widget t, Event event)  { if(auto e = cast(MouseDownEvent) event) t.defaultEventHandler_mousedown(e); };
		defaultEventHandlers["mouseup"] = (Widget t, Event event)    { if(auto e = cast(MouseUpEvent) event) t.defaultEventHandler_mouseup(e); };
		defaultEventHandlers["mouseenter"] = (Widget t, Event event) { if(auto e = cast(MouseEnterEvent) event) t.defaultEventHandler_mouseenter(e); };
		defaultEventHandlers["mouseleave"] = (Widget t, Event event) { if(auto e = cast(MouseLeaveEvent) event) t.defaultEventHandler_mouseleave(e); };
		defaultEventHandlers["mousemove"] = (Widget t, Event event)  { if(auto e = cast(MouseMoveEvent) event) t.defaultEventHandler_mousemove(e); };
		defaultEventHandlers["char"] = (Widget t, Event event)       { if(auto e = cast(CharEvent) event) t.defaultEventHandler_char(e); };
		defaultEventHandlers["triggered"] = (Widget t, Event event)  { if(auto e = cast(Event) event) t.defaultEventHandler_triggered(e); };
		defaultEventHandlers["change"] = (Widget t, Event event)     { if(auto e = cast(ChangeEventBase) event) t.defaultEventHandler_change(e); };
		defaultEventHandlers["focus"] = (Widget t, Event event)      { if(auto e = cast(FocusEvent) event) t.defaultEventHandler_focus(e); };
		defaultEventHandlers["blur"] = (Widget t, Event event)       { if(auto e = cast(BlurEvent) event) t.defaultEventHandler_blur(e); };
		defaultEventHandlers["focusin"] = (Widget t, Event event)    { if(auto e = cast(FocusInEvent) event) t.defaultEventHandler_focusin(e); };
		defaultEventHandlers["focusout"] = (Widget t, Event event)   { if(auto e = cast(FocusOutEvent) event) t.defaultEventHandler_focusout(e); };
	}

	/// ditto
	void defaultEventHandler_click(ClickEvent event) {}
	/// ditto
	void defaultEventHandler_dblclick(DoubleClickEvent event) {}
	/// ditto
	void defaultEventHandler_keydown(KeyDownEvent event) {}
	/// ditto
	void defaultEventHandler_keyup(KeyUpEvent event) {}
	/// ditto
	void defaultEventHandler_mousedown(MouseDownEvent event) {
		if(event.button == MouseButton.left) {
			if(this.tabStop) {
				this.focus();
			}
		} else if(event.button == MouseButton.right) {
			showContextMenu(event.clientX, event.clientY);
		}
	}
	/// ditto
	void defaultEventHandler_mouseover(MouseOverEvent event) {}
	/// ditto
	void defaultEventHandler_mouseout(MouseOutEvent event) {}
	/// ditto
	void defaultEventHandler_mouseup(MouseUpEvent event) {}
	/// ditto
	void defaultEventHandler_mousemove(MouseMoveEvent event) {}
	/// ditto
	void defaultEventHandler_mouseenter(MouseEnterEvent event) {}
	/// ditto
	void defaultEventHandler_mouseleave(MouseLeaveEvent event) {}
	/// ditto
	void defaultEventHandler_char(CharEvent event) {}
	/// ditto
	void defaultEventHandler_triggered(Event event) {}
	/// ditto
	void defaultEventHandler_change(ChangeEventBase event) {}
	/// ditto
	void defaultEventHandler_focus(FocusEvent event) {}
	/// ditto
	void defaultEventHandler_blur(BlurEvent event) {}
	/// ditto
	void defaultEventHandler_focusin(FocusInEvent event) {}
	/// ditto
	void defaultEventHandler_focusout(FocusOutEvent event) {}

	/++
		[Event]s use a Javascript-esque model. See more details on the [Event] page.

		[addEventListener] returns an opaque handle that you can later pass to [removeEventListener].

		addDirectEventListener just inserts a check `if(e.target !is this) return;` meaning it opts out
		of participating in handler delegation.

		$(TIP
			Use `scope` on your handlers when you can. While it currently does nothing, this will future-proof your code against future optimizations I want to do. Instead of copying whole event objects out if you do need to store them, just copy the properties you need.
		)
	+/
	EventListener addDirectEventListener(string event, void delegate() handler, bool useCapture = false) {
		return addEventListener(event, (Widget, scope Event e) {
			if(e.srcElement is this)
				handler();
		}, useCapture);
	}

	/// ditto
	EventListener addDirectEventListener(string event, void delegate(Event) handler, bool useCapture = false) {
		return addEventListener(event, (Widget, Event e) {
			if(e.srcElement is this)
				handler(e);
		}, useCapture);
	}

	/// ditto
	EventListener addDirectEventListener(Handler)(Handler handler, bool useCapture = false) {
		static if(is(Handler Fn == delegate)) {
		static if(is(Fn Params == __parameters)) {
			return addEventListener(EventString!(Params[0]), (Widget, Event e) {
				if(e.srcElement !is this)
					return;
				auto ty = cast(Params[0]) e;
				if(ty !is null)
					handler(ty);
			}, useCapture);
		} else static assert(0);
		} else static assert(0, "Your handler wasn't usable because it wasn't passed a delegate. Use the delegate keyword at the call site.");
	}

	/// ditto
	@scriptable
	EventListener addEventListener(string event, void delegate() handler, bool useCapture = false) {
		return addEventListener(event, (Widget, scope Event) { handler(); }, useCapture);
	}

	/// ditto
	EventListener addEventListener(Handler)(Handler handler, bool useCapture = false) {
		static if(is(Handler Fn == delegate)) {
		static if(is(Fn Params == __parameters)) {
			return addEventListener(EventString!(Params[0]), (Widget, Event e) {
				auto ty = cast(Params[0]) e;
				if(ty !is null)
					handler(ty);
			}, useCapture);
		} else static assert(0);
		} else static assert(0, "Your handler wasn't usable because it wasn't passed a delegate. Use the delegate keyword at the call site.");
	}

	/// ditto
	EventListener addEventListener(string event, void delegate(Event) handler, bool useCapture = false) {
		return addEventListener(event, (Widget, Event e) { handler(e); }, useCapture);
	}

	/// ditto
	EventListener addEventListener(string event, EventHandler handler, bool useCapture = false) {
		if(event.length > 2 && event[0..2] == "on")
			event = event[2 .. $];

		if(useCapture)
			capturingEventHandlers[event] ~= handler;
		else
			bubblingEventHandlers[event] ~= handler;

		return EventListener(this, event, handler, useCapture);
	}

	/// ditto
	void removeEventListener(string event, EventHandler handler, bool useCapture = false) {
		if(event.length > 2 && event[0..2] == "on")
			event = event[2 .. $];

		if(useCapture) {
			if(event in capturingEventHandlers)
			foreach(ref evt; capturingEventHandlers[event])
				if(evt is handler) evt = null;
		} else {
			if(event in bubblingEventHandlers)
			foreach(ref evt; bubblingEventHandlers[event])
				if(evt is handler) evt = null;
		}
	}

	/// ditto
	void removeEventListener(EventListener listener) {
		removeEventListener(listener.event, listener.handler, listener.useCapture);
	}

	static if(UsingSimpledisplayX11) {
		void discardXConnectionState() {
			foreach(child; children)
				child.discardXConnectionState();
		}

		void recreateXConnectionState() {
			foreach(child; children)
				child.recreateXConnectionState();
			redraw();
		}
	}

	/++
		Returns the coordinates of this widget on the screen, relative to the upper left corner of the whole screen.

		History:
			`globalCoordinates` was made `final` on May 11, 2021.
	+/
	Point globalCoordinates() {
		int x = this.x;
		int y = this.y;
		auto p = this.parent;
		while(p) {
			x += p.x;
			y += p.y;
			p = p.parent;
		}

		static if(UsingSimpledisplayX11) {
			auto dpy = XDisplayConnection.get;
			arsd.simpledisplay.Window dummyw;
			XTranslateCoordinates(dpy, this.parentWindow.win.impl.window, RootWindow(dpy, DefaultScreen(dpy)), x, y, &x, &y, &dummyw);
		} else version(Windows) {
			POINT pt;
			pt.x = x;
			pt.y = y;
			MapWindowPoints(this.parentWindow.win.impl.hwnd, null, &pt, 1);
			x = pt.x;
			y = pt.y;
		} else {
			featureNotImplemented();
		}

		return Point(x, y);
	}

	version(win32_widgets)
	int handleWmDrawItem(DRAWITEMSTRUCT* dis) { return 0; }

	version(win32_widgets)
	/// Called when a WM_COMMAND is sent to the associated hwnd.
	void handleWmCommand(ushort cmd, ushort id) {}

	version(win32_widgets)
	/++
		Called when a WM_NOTIFY is sent to the associated hwnd.

		History:
	+/
	int handleWmNotify(NMHDR* hdr, int code, out int mustReturn) { return 0; }

	version(win32_widgets)
	deprecated("This overload is problematic since it is liable to discard return values. Add the `out int mustReturn` to your override as the last parameter and set it to 1 when you must forward the return value to Windows. Otherwise, you can just add the parameter then ignore it and use the default value of 0 to maintain the status quo.") int handleWmNotify(NMHDR* hdr, int code) { int ignored; return handleWmNotify(hdr, code, ignored); }

	/++
		This tip is displayed in the status bar (if there is one in the containing window) when the mouse moves over this widget.

		Updates to this variable will only be made visible on the next mouse enter event.
	+/
	@scriptable string statusTip;
	// string toolTip;
	// string helpText;

	/++
		If true, this widget can be focused via keyboard control with the tab key.

		If false, it is assumed the widget itself does will never receive the keyboard focus (though its childen are free to).
	+/
	bool tabStop = true;
	/++
		The tab key cycles through widgets by the order of a.tabOrder < b.tabOrder. If they are equal, it does them in child order (which is typically the order they were added to the widget.)
	+/
	int tabOrder;

	version(win32_widgets) {
		static Widget[HWND] nativeMapping;
		/// The native handle, if there is one.
		HWND hwnd;
		WNDPROC originalWindowProcedure;

		SimpleWindow simpleWindowWrappingHwnd;

		// please note it IGNORES your return value and does NOT forward it to Windows!
		int hookedWndProc(UINT iMessage, WPARAM wParam, LPARAM lParam) {
			return 0;
		}
	}
	private bool implicitlyCreated;

	/// Child's position relative to the parent's origin. only the layout manager should be modifying this and even reading it is of limited utility. It may be made `private` at some point in the future without advance notice. Do NOT depend on it being available unless you are writing a layout manager.
	int x;
	/// ditto
	int y;
	private int _width;
	private int _height;
	private Widget[] _children;
	private Widget _parent;
	private Window _parentWindow;

	/++
		Returns the window to which this widget is attached.

		History:
			Prior to May 11, 2021, the `Window parentWindow` variable was directly available. Now, only this property getter is available and the actual store is private.
	+/
	final @property inout(Window) parentWindow() inout @nogc nothrow pure { return _parentWindow; }
	private @property void parentWindow(Window parent) {
		auto old = _parentWindow;
		_parentWindow = parent;
		newParentWindow(old, _parentWindow);
		foreach(child; children)
			child.parentWindow = parent; // please note that this is recursive
	}

	/++
		Called when the widget has been added to or remove from a parent window.

		Note that either oldParent and/or newParent may be null any time this is called.

		History:
			Added September 13, 2024
	+/
	protected void newParentWindow(Window oldParent, Window newParent) {}

	/++
		Returns the list of the widget's children.

		History:
			Prior to May 11, 2021, the `Widget[] children` was directly available. Now, only this property getter is available and the actual store is private.

			Children should be added by the constructor most the time, but if that's impossible, use [addChild] and [removeWidget] to manage the list.
	+/
	final @property inout(Widget)[] children() inout @nogc nothrow pure { return _children; }

	/++
		Returns the widget's parent.

		History:
			Prior to May 11, 2021, the `Widget parent` variable was directly available. Now, only this property getter is permitted.

			The parent should only be managed by the [addChild] and [removeWidget] method.
	+/
	final @property inout(Widget) parent() inout nothrow @nogc pure @safe return { return _parent; }

	/// The widget's current size.
	final @scriptable public @property int width() const nothrow @nogc pure @safe { return _width; }
	/// ditto
	final @scriptable public @property int height() const nothrow @nogc pure @safe { return _height; }

	/// Only the layout manager should be calling these.
	final protected @property int width(int a) @safe { return _width = a; }
	/// ditto
	final protected @property int height(int a) @safe { return _height = a; }

	/++
		This function is called by the layout engine after it has updated the position (in variables `x` and `y`) and the size (in properties `width` and `height`) to give you a chance to update the actual position of the native child window (if there is one) or whatever.

		It is also responsible for calling [sendResizeEvent] to notify other listeners that the widget has changed size.
	+/
	protected void registerMovement() {
		version(win32_widgets) {
			if(hwnd) {
				auto pos = getChildPositionRelativeToParentHwnd(this);
				MoveWindow(hwnd, pos[0], pos[1], width, height, true); // setting this to false can sometimes speed things up but only if it is actually drawn later and that's kinda iffy to do right here so being slower but safer rn
				this.redraw();
			}
		}
		sendResizeEvent();
	}

	/// Creates the widget and adds it to the parent.
	this(Widget parent) {
		if(parent !is null)
			parent.addChild(this);
		setupDefaultEventHandlers();
	}

	/// Returns true if this is the current focused widget inside the parent window. Please note it may return `true` when the window itself is unfocused. In that case, it indicates this widget will receive focuse again when the window does.
	@scriptable
	bool isFocused() {
		return parentWindow && parentWindow.focusedWidget is this;
	}

	private bool showing_ = true;
	///
	bool showing() const { return showing_; }
	///
	bool hidden() const { return !showing_; }
	/++
		Shows or hides the window. Meant to be assigned as a property. If `recalculate` is true (the default), it recalculates the layout of the parent widget to use the space this widget being hidden frees up or make space for this widget to appear again.

		Note that a widget only ever shows if all its parents are showing too.
	+/
	void showing(bool s, bool recalculate = true) {
		if(s != showing_) {
			showing_ = s;
			// writeln(typeid(this).toString, " ", this.parent ? typeid(this.parent).toString : "null", " ", s);

			showNativeWindowChildren(s);

			if(parent && recalculate) {
				parent.queueRecomputeChildLayout();
				parent.redraw();
			}

			if(s) {
				queueRecomputeChildLayout();
				redraw();
			}
		}
	}
	/// Convenience method for `showing = true`
	@scriptable
	void show() {
		showing = true;
	}
	/// Convenience method for `showing = false`
	@scriptable
	void hide() {
		showing = false;
	}

	/++
		If you are a native window, show/hide it based on shouldShow and return `true`.

		Otherwise, do nothing and return false.
	+/
	protected bool showOrHideIfNativeWindow(bool shouldShow) {
		version(win32_widgets) {
			if(hwnd) {
				ShowWindow(hwnd, shouldShow ? SW_SHOW : SW_HIDE);
				return true;
			} else {
				return false;
			}
		} else {
			return false;
		}
	}

	private void showNativeWindowChildren(bool s) {
		if(!showOrHideIfNativeWindow(s && showing))
			foreach(child; children)
				child.showNativeWindowChildren(s);
	}

	///
	@scriptable
	void focus() {
		assert(parentWindow !is null);
		if(isFocused())
			return;

		if(parentWindow.focusedWidget) {
			// FIXME: more details here? like from and to
			auto from = parentWindow.focusedWidget;
			parentWindow.focusedWidget.setDynamicState(DynamicState.focus, false);
			parentWindow.focusedWidget = null;
			from.emit!BlurEvent();
			from.emit!FocusOutEvent();
		}


		version(win32_widgets) {
			if(this.hwnd !is null)
				SetFocus(this.hwnd);
		}
		//else static if(UsingSimpledisplayX11)
			//this.parentWindow.win.focus();

		parentWindow.focusedWidget = this;
		parentWindow.focusedWidget.setDynamicState(DynamicState.focus, true);
		this.emit!FocusEvent();
		this.emit!FocusInEvent();
	}

	/+
	/++
		Unfocuses the widget. This may reset
	+/
	@scriptable
	void blur() {

	}
	+/


	/++
		This is called when the widget is added to a window. It gives you a chance to set up event hooks.

		Update on May 11, 2021: I'm considering removing this method. You can usually achieve these things through looser-coupled methods.
	+/
	void attachedToWindow(Window w) {}
	/++
		Callback when the widget is added to another widget.

		Update on May 11, 2021: I'm considering removing this method since I've never actually found it useful.
	+/
	void addedTo(Widget w) {}

	/++
		Adds a child to the given position. This is `protected` because you generally shouldn't be calling this directly. Instead, construct widgets with the parent directly.

		This is available primarily to be overridden. For example, [MainWindow] overrides it to redirect its children into a central widget.
	+/
	protected void addChild(Widget w, int position = int.max) {
		assert(w._parent !is this, "Child cannot be added twice to the same parent");
		assert(w !is this, "Child cannot be its own parent!");
		w._parent = this;
		if(position == int.max || position == children.length) {
			_children ~= w;
		} else {
			assert(position < _children.length);
			_children.length = _children.length + 1;
			for(int i = cast(int) _children.length - 1; i > position; i--)
				_children[i] = _children[i - 1];
			_children[position] = w;
		}

		this.parentWindow = this._parentWindow;

		w.addedTo(this);

		bool parentIsNative;
		version(win32_widgets) {
			parentIsNative = hwnd !is null;
		}
		if(!parentIsNative && !showing)
			w.showOrHideIfNativeWindow(false);

		if(parentWindow !is null) {
			w.attachedToWindow(parentWindow);
			parentWindow.queueRecomputeChildLayout();
			parentWindow.redraw();
		}
	}

	/++
		Finds the child at the top of the z-order at the given coordinates (relative to the `this` widget's origin), or null if none are found.
	+/
	Widget getChildAtPosition(int x, int y) {
		// it goes backward so the last one to show gets picked first
		// might use z-index later
		foreach_reverse(child; children) {
			if(child.hidden)
				continue;
			if(child.x <= x && child.y <= y
				&& ((x - child.x) < child.width)
				&& ((y - child.y) < child.height))
			{
				return child;
			}
		}

		return null;
	}

	/++
		If the widget is a scrollable container, this should add the current scroll position to the given coordinates so the mouse events can be dispatched correctly.

		History:
			Added July 2, 2021 (v10.2)
	+/
	protected void addScrollPosition(ref int x, ref int y) {}

	/++
		Responsible for actually painting the widget to the screen. The clip rectangle and coordinate translation in the [WidgetPainter] are pre-configured so you can draw independently.

		This function paints the entire widget, including styled borders, backgrounds, etc. You are also responsible for displaying any important active state to the user, including if you hold the active keyboard focus. If you only want to be responsible for the content while letting the style engine draw the rest, override [paintContent] instead.

		[paint] is not called for system widgets as the OS library draws them instead.


		The default implementation forwards to [WidgetPainter.drawThemed], passing [paintContent] as the delegate. If you override this, you might use those same functions or you can do your own thing.

		You should also look at [WidgetPainter.visualTheme] to be theme aware.

		History:
			Prior to May 15, 2021, the default implementation was empty. Now, it is `painter.drawThemed(&paintContent);`. You may wish to override [paintContent] instead of [paint] to take advantage of the new styling engine.
	+/
	void paint(WidgetPainter painter) {
		version(win32_widgets)
			if(hwnd) {
				return;
			}
		painter.drawThemed(&paintContent); // note this refers to the following overload
	}

	/++
		Responsible for drawing the content as the theme engine is responsible for other elements.

		$(WARNING If you override [paint], this method may never be used as it is only called from inside the default implementation of `paint`.)

		Params:
			painter = your painter (forwarded from [paint]) for drawing on the widget. The clip rectangle and coordinate translation are prepared for you ahead of time so you can use widget coordinates. It also has the theme foreground preloaded into the painter outline color, the theme font preloaded as the painter's active font, and the theme background preloaded as the painter's fill color.

			bounds = the bounds, inside the widget, where your content should be drawn. This is the rectangle inside the border and padding (if any). The stuff outside is not clipped - it is still part of your widget - but you should respect these bounds for visual consistency and respecting the theme's area.

			If you do want to clip it, you can of course call `auto oldClip = painter.setClipRectangle(bounds); scope(exit) painter.setClipRectangle(oldClip);` to modify it and return to the previous setting when you return.

		Returns:
			The rectangle representing your actual content. Typically, this is simply `return bounds;`. The theme engine uses this return value to determine where the outline and overlay should be.

		History:
			Added May 15, 2021
	+/
	Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		return bounds;
	}

	deprecated("Change ScreenPainter to WidgetPainter")
	final void paint(ScreenPainter) { assert(0, "Change ScreenPainter to WidgetPainter and recompile your code"); }

	/// I don't actually like the name of this
	/// this draws a background on it
	void erase(WidgetPainter painter) {
		version(win32_widgets)
			if(hwnd) return; // Windows will do it. I think.

		auto c = getComputedStyle().background.color;
		painter.fillColor = c;
		painter.outlineColor = c;

		version(win32_widgets) {
			HANDLE b, p;
			if(c.a == 0 && parent is parentWindow) {
				// I don't remember why I had this really...
				b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
				p = SelectObject(painter.impl.hdc, GetStockObject(NULL_PEN));
			}
		}
		painter.drawRectangle(Point(0, 0), width, height);
		version(win32_widgets) {
			if(c.a == 0 && parent is parentWindow) {
				SelectObject(painter.impl.hdc, p);
				SelectObject(painter.impl.hdc, b);
			}
		}
	}

	///
	WidgetPainter draw() {
		int x = this.x, y = this.y;
		auto parent = this.parent;
		while(parent) {
			x += parent.x;
			y += parent.y;
			parent = parent.parent;
		}

		auto painter = parentWindow.win.draw(true);
		painter.originX = x;
		painter.originY = y;
		painter.setClipRectangle(Point(0, 0), width, height);
		return WidgetPainter(painter, this);
	}

	/// This can be overridden by scroll things. It is responsible for actually calling [paint]. Do not override unless you've studied minigui.d's source code. There are no stability guarantees if you do override this; it can (and likely will) break without notice.
	protected void privatePaint(WidgetPainter painter, int lox, int loy, Rectangle containment, bool force, bool invalidate) {
		if(hidden)
			return;

		int paintX = x;
		int paintY = y;
		if(this.useNativeDrawing()) {
			paintX = 0;
			paintY = 0;
			lox = 0;
			loy = 0;
			containment = Rectangle(0, 0, int.max, int.max);
		}

		painter.originX = lox + paintX;
		painter.originY = loy + paintY;

		bool actuallyPainted = false;

		const clip = containment.intersectionOf(Rectangle(Point(lox + paintX, loy + paintY), Size(width, height)));
		if(clip == Rectangle.init) {
			// writeln(this, " clipped out");
			return;
		}

		bool invalidateChildren = invalidate;

		if(redrawRequested || force) {
			painter.setClipRectangleForWidget(clip.upperLeft - Point(painter.originX, painter.originY), clip.width, clip.height);

			painter.drawingUpon = this;

			erase(painter);
			if(painter.visualTheme)
				painter.visualTheme.doPaint(this, painter);
			else
				paint(painter);

			if(invalidate) {
				// sdpyPrintDebugString("invalidate " ~ typeid(this).name);
				auto region = Rectangle(Point(clip.upperLeft.x - painter.originX, clip.upperRight.y - painter.originY), Size(clip.width, clip.height));
				painter.invalidateRect(region);
				// children are contained inside this, so no need to do extra work
				invalidateChildren = false;
			}

			redrawRequested = false;
			actuallyPainted = true;
		}

		foreach(child; children) {
			version(win32_widgets)
				if(child.useNativeDrawing()) continue;
			child.privatePaint(painter, painter.originX, painter.originY, clip, actuallyPainted, invalidateChildren);
		}

		version(win32_widgets)
		foreach(child; children) {
			if(child.useNativeDrawing) {
				painter = WidgetPainter(child.simpleWindowWrappingHwnd.draw(true), child);
				child.privatePaint(painter, painter.originX, painter.originY, clip, actuallyPainted, true); // have to reset the invalidate flag since these are not necessarily affected the same way, being native children with a clip
			}
		}
	}

	protected bool useNativeDrawing() nothrow {
		version(win32_widgets)
			return hwnd !is null;
		else
			return false;
	}

	private static class RedrawEvent {}
	private __gshared re = new RedrawEvent();

	private bool redrawRequested;
	///
	final void redraw(string file = __FILE__, size_t line = __LINE__) {
		redrawRequested = true;

		if(this.parentWindow) {
			auto sw = this.parentWindow.win;
			assert(sw !is null);
			if(!sw.eventQueued!RedrawEvent) {
				sw.postEvent(re);
				//  writeln("redraw requested from ", file,":",line," ", this.parentWindow.win.impl.window);
			}
		}
	}

	private SimpleWindow drawableWindow;

	/++
		Allows a class to easily dispatch its own statically-declared event (see [Emits]). The main benefit of using this over constructing an event yourself is simply that you ensure you haven't sent something you haven't documented you can send.

		Returns:
			`true` if you should do your default behavior.

		History:
			Added May 5, 2021

		Bugs:
			It does not do the static checks on gdc right now.
	+/
	final protected bool emit(EventType, this This, Args...)(Args args) {
		version(GNU) {} else
		static assert(classStaticallyEmits!(This, EventType), "The " ~ This.stringof ~ " class is not declared to emit " ~ EventType.stringof);
		auto e = new EventType(this, args);
		e.dispatch();
		return !e.defaultPrevented;
	}
	/// ditto
	final protected bool emit(string eventString, this This)() {
		auto e = new Event(eventString, this);
		e.dispatch();
		return !e.defaultPrevented;
	}

	/++
		Does the same as [addEventListener]'s delegate overload, but adds an additional check to ensure the event you are subscribing to is actually emitted by the static type you are using. Since it works on static types, if you have a generic [Widget], this can only subscribe to events declared as [Emits] inside [Widget] itself, not any child classes nor any child elements. If this is too restrictive, simply use [addEventListener] instead.

		History:
			Added May 5, 2021
	+/
	final public EventListener subscribe(EventType, this This)(void delegate(EventType) handler) {
		static assert(classStaticallyEmits!(This, EventType), "The " ~ This.stringof ~ " class is not declared to emit " ~ EventType.stringof);
		return addEventListener(handler);
	}

	/++
		Gets the computed style properties from the visual theme.

		You should use this in your paint and layout functions instead of the direct properties on the widget if you want to be style aware. (But when setting defaults in your classes, overriding is the right thing to do. Override to set defaults, but then read out of [getComputedStyle].)

		History:
			Added May 8, 2021
	+/
	final StyleInformation getComputedStyle() {
		return StyleInformation(this);
	}

	int focusableWidgets(scope int delegate(Widget) dg) {
		foreach(widget; WidgetStream(this)) {
			if(widget.tabStop && !widget.hidden) {
				int result = dg(widget);
				if (result)
					return result;
			}
		}
		return 0;
	}

	/++
		Calculates the border box (that is, the full width/height of the widget, from border edge to border edge)
		for the given content box (the area between the padding)

		History:
			Added January 4, 2023 (dub v11.0)
	+/
	Rectangle borderBoxForContentBox(Rectangle contentBox) {
		auto cs = getComputedStyle();

		auto borderWidth = getBorderWidth(cs.borderStyle);

		auto rect = contentBox;

		rect.left -= borderWidth;
		rect.right += borderWidth;
		rect.top -= borderWidth;
		rect.bottom += borderWidth;

		auto insideBorderRect = rect;

		rect.left -= cs.paddingLeft;
		rect.right += cs.paddingRight;
		rect.top -= cs.paddingTop;
		rect.bottom += cs.paddingBottom;

		return rect;
	}


	// FIXME: I kinda want to hide events from implementation widgets
	// so it just catches them all and stops propagation...
	// i guess i can do it with a event listener on star.

	mixin Emits!KeyDownEvent; ///
	mixin Emits!KeyUpEvent; ///
	mixin Emits!CharEvent; ///

	mixin Emits!MouseDownEvent; ///
	mixin Emits!MouseUpEvent; ///
	mixin Emits!ClickEvent; ///
	mixin Emits!DoubleClickEvent; ///
	mixin Emits!MouseMoveEvent; ///
	mixin Emits!MouseOverEvent; ///
	mixin Emits!MouseOutEvent; ///
	mixin Emits!MouseEnterEvent; ///
	mixin Emits!MouseLeaveEvent; ///

	mixin Emits!ResizeEvent; ///

	mixin Emits!BlurEvent; ///
	mixin Emits!FocusEvent; ///

	mixin Emits!FocusInEvent; ///
	mixin Emits!FocusOutEvent; ///
}

/+
/++
	Interface to indicate that the widget has a simple value property.

	History:
		Added August 26, 2021
+/
interface HasValue!T {
	/// Getter
	@property T value();
	/// Setter
	@property void value(T);
}

/++
	Interface to indicate that the widget has a range of possible values for its simple value property.
	This would be present on something like a slider or possibly a number picker.

	History:
		Added September 11, 2021
+/
interface HasRangeOfValues!T : HasValue!T {
	/// The minimum and maximum values in the range, inclusive.
	@property T minValue();
	@property void minValue(T); /// ditto
	@property T maxValue(); /// ditto
	@property void maxValue(T); /// ditto

	/// The smallest step the user interface allows. User may still type in values without this limitation.
	@property void step(T);
	@property T step(); /// ditto
}

/++
	Interface to indicate that the widget has a list of possible values the user can choose from.
	This would be present on something like a drop-down selector.

	The value is NOT necessarily one of the items on the list. Consider the case of a free-entry
	combobox.

	History:
		Added September 11, 2021
+/
interface HasListOfValues!T : HasValue!T {
	@property T[] values;
	@property void values(T[]);

	@property int selectedIndex(); // note it may return -1!
	@property void selectedIndex(int);
}
+/

/++
	History:
		Added September 2021 (dub v10.4)
+/
class GridLayout : Layout {

	// FIXME: grid padding around edges and also cell spacing between units. even though you could do that by just specifying some gutter yourself in the layout.

	/++
		If a widget is too small to fill a grid cell, the graviy tells where it "sticks" to.
	+/
	enum Gravity {
		Center    = 0,
		NorthWest = North | West,
		North     = 0b10_00,
		NorthEast = North | East,
		West      = 0b00_10,
		East      = 0b00_01,
		SouthWest = South | West,
		South     = 0b01_00,
		SouthEast = South | East,
	}

	/++
		The width and height are in some proportional units and can often just be 12.
	+/
	this(int width, int height, Widget parent) {
		this.gridWidth = width;
		this.gridHeight = height;
		super(parent);
	}

	/++
		Sets the position of the given child.

		The units of these arguments are in the proportional grid units you set in the constructor.
	+/
	Widget setChildPosition(return Widget child, int x, int y, int width, int height, Gravity gravity = Gravity.Center) {
		// ensure it is in bounds
		// then ensure no overlaps

		ChildPosition p = ChildPosition(child, x, y, width, height, gravity);

		foreach(ref position; positions) {
			if(position.widget is child) {
				position = p;
				goto set;
			}
		}

		positions ~= p;

		set:

		// FIXME: should this batch?
		queueRecomputeChildLayout();

		return child;
	}

	override void addChild(Widget w, int position = int.max) {
		super.addChild(w, position);
		//positions ~= ChildPosition(w);
		if(position != int.max) {
			// FIXME: align it so they actually match.
		}
	}

	override void widgetRemoved(size_t idx, Widget w) {
		// FIXME: keep the positions array aligned
		// positions[idx].widget = null;
	}

	override void recomputeChildLayout() {
		registerMovement();
		int onGrid = cast(int) positions.length;
		c: foreach(child; children) {
			// just snap it to the grid
			if(onGrid)
			foreach(position; positions)
				if(position.widget is child) {
					child.x = this.width * position.x / this.gridWidth;
					child.y = this.height * position.y / this.gridHeight;
					child.width = this.width * position.width / this.gridWidth;
					child.height = this.height * position.height / this.gridHeight;

					auto diff = child.width - child.maxWidth();
					// FIXME: gravity?
					if(diff > 0) {
						child.width = child.width - diff;

						if(position.gravity & Gravity.West) {
							// nothing needed, already aligned
						} else if(position.gravity & Gravity.East) {
							child.x += diff;
						} else {
							child.x += diff / 2;
						}
					}

					diff = child.height - child.maxHeight();
					// FIXME: gravity?
					if(diff > 0) {
						child.height = child.height - diff;

						if(position.gravity & Gravity.North) {
							// nothing needed, already aligned
						} else if(position.gravity & Gravity.South) {
							child.y += diff;
						} else {
							child.y += diff / 2;
						}
					}
					child.recomputeChildLayout();
					onGrid--;
					continue c;
				}
			// the position isn't given on the grid array, we'll just fill in from where the explicit ones left off.
		}
	}

	private struct ChildPosition {
		Widget widget;
		int x;
		int y;
		int width;
		int height;
		Gravity gravity;
	}
	private ChildPosition[] positions;

	int gridWidth = 12;
	int gridHeight = 12;
}

///
abstract class ComboboxBase : Widget {
	// if the user can enter arbitrary data, we want to use  2 == CBS_DROPDOWN
	// or to always show the list, we want CBS_SIMPLE == 1
	version(win32_widgets)
		this(uint style, Widget parent) {
			super(parent);
			createWin32Window(this, "ComboBox"w, null, style);
		}
	else version(custom_widgets)
		this(Widget parent) {
			super(parent);

			addEventListener((KeyDownEvent event) {
				if(event.key == Key.Up) {
					setSelection(selection_-1);
					event.preventDefault();
				}
				if(event.key == Key.Down) {
					setSelection(selection_+1);
					event.preventDefault();
				}

			});

		}
	else static assert(false);

	protected void scrollSelectionIntoView() {}

	/++
		Returns the current list of options in the selection.

		History:
			Property accessor added March 1, 2022 (dub v10.7). Prior to that, it was private.
	+/
	final @property string[] options() const {
		return cast(string[]) options_;
	}

	/++
		Replaces the list of options in the box. Note that calling this will also reset the selection.

		History:
			Added December, 29 2024
	+/
	final @property void options(string[] options) {
		version(win32_widgets)
			SendMessageW(hwnd, 331 /*CB_RESETCONTENT*/, 0, 0);
		selection_ = -1;
		options_ = null;
		foreach(opt; options)
			addOption(opt);

		version(custom_widgets)
			redraw();
	}

	private string[] options_;
	private int selection_ = -1;

	/++
		Adds an option to the end of options array.
	+/
	void addOption(string s) {
		options_ ~= s;
		version(win32_widgets)
		SendMessageW(hwnd, 323 /*CB_ADDSTRING*/, 0, cast(LPARAM) toWstringzInternal(s));
	}

	/++
		Gets the current selection as an index into the [options] array. Returns -1 if nothing is selected.
	+/
	int getSelection() {
		return selection_;
	}

	/++
		Returns the current selection as a string.

		History:
			Added November 17, 2021
	+/
	string getSelectionString() {
		return selection_ == -1 ? null : options[selection_];
	}

	/++
		Sets the current selection to an index in the options array, or to the given option if present.
		Please note that the string version may do a linear lookup.

		Returns:
			the index you passed in

		History:
			The `string` based overload was added on March 1, 2022 (dub v10.7).

			The return value was `void` prior to March 1, 2022.
	+/
	int setSelection(int idx) {
		if(idx < -1)
			idx = -1;
		if(idx + 1 > options.length)
			idx = cast(int) options.length - 1;

		selection_ = idx;

		version(win32_widgets)
		SendMessageW(hwnd, 334 /*CB_SETCURSEL*/, idx, 0);

		auto t = new SelectionChangedEvent(this, selection_, selection_ == -1 ? null : options[selection_]);
		t.dispatch();

		scrollSelectionIntoView();

		return idx;
	}

	/// ditto
	int setSelection(string s) {
		if(s !is null)
		foreach(idx, item; options)
			if(item == s) {
				return setSelection(cast(int) idx);
			}
		return setSelection(-1);
	}

	/++
		This event is fired when the selection changes. Both [Event.stringValue] and
		[Event.intValue] are filled in - `stringValue` is the text in the selection
		and `intValue` is the index of the selection. If the combo box allows multiple
		selection, these values will include only one of the selected items - for those,
		you should loop through the values and check their selected flag instead.

		(I know that sucks, but it is how it is right now.)

		History:
			It originally inherited from `ChangeEvent!String`, but now does from [ChangeEventBase] as of January 3, 2025.
			This shouldn't break anything if you used it through either its own name `SelectionChangedEvent` or through the
			base `Event`, only if you specifically used `ChangeEvent!string` - those handlers may now get `null` or fail to
			be called. If you did do this, just change it to generic `Event`, as `stringValue` and `intValue` are already there.
	+/
	static final class SelectionChangedEvent : ChangeEventBase {
		this(Widget target, int iv, string sv) {
			super(target);
			this.iv = iv;
			this.sv = sv;
		}
		immutable int iv;
		immutable string sv;

		deprecated("Use stringValue or intValue instead") @property string value() {
			return sv;
		}

		override @property string stringValue() { return sv; }
		override @property int intValue() { return iv; }
	}

	version(win32_widgets)
	override void handleWmCommand(ushort cmd, ushort id) {
		if(cmd == CBN_SELCHANGE) {
			selection_ = cast(int) SendMessageW(hwnd, 327 /* CB_GETCURSEL */, 0, 0);
			fireChangeEvent();
		}
	}

	private void fireChangeEvent() {
		if(selection_ >= options.length)
			selection_ = -1;

		auto t = new SelectionChangedEvent(this, selection_, selection_ == -1 ? null : options[selection_]);
		t.dispatch();
	}

	override int minWidth() { return scaleWithDpi(32); }

	version(win32_widgets) {
		override int minHeight() { return defaultLineHeight + 6; }
		override int maxHeight() { return defaultLineHeight + 6; }
	} else {
		override int minHeight() { return defaultLineHeight + 4; }
		override int maxHeight() { return defaultLineHeight + 4; }
	}

	version(custom_widgets)
	void popup() {
		CustomComboBoxPopup popup = new CustomComboBoxPopup(this);
	}

}

private class CustomComboBoxPopup : Window {
	private ComboboxBase associatedWidget;
	private ListWidget lw;
	private bool cancelled;

	this(ComboboxBase associatedWidget) {
		this.associatedWidget = associatedWidget;

		// FIXME: this should scroll if there's too many elements to reasonably fit on screen

		auto w = associatedWidget.width;
		// FIXME: suggestedDropdownHeight see below
		auto h = cast(int) associatedWidget.options.length * associatedWidget.defaultLineHeight + associatedWidget.scaleWithDpi(8);

		// FIXME: this sux
		if(h > associatedWidget.parentWindow.height)
			h = associatedWidget.parentWindow.height;

		auto mh = associatedWidget.scaleWithDpi(16 + 16 + 32); // to make the scrollbar look ok
		if(h < mh)
			h = mh;

		auto coord = associatedWidget.globalCoordinates();
		auto dropDown = new SimpleWindow(
			w, h,
			null, OpenGlOptions.no, Resizability.fixedSize, WindowTypes.dropdownMenu, WindowFlags.dontAutoShow, associatedWidget.parentWindow ? associatedWidget.parentWindow.win : null);

		super(dropDown);

		dropDown.move(coord.x, coord.y + associatedWidget.height);

		this.lw = new ListWidget(this);
		version(custom_widgets)
			lw.multiSelect = false;
		foreach(option; associatedWidget.options)
			lw.addOption(option);

		auto originalSelection = associatedWidget.getSelection;
		lw.setSelection(originalSelection);
		lw.scrollSelectionIntoView();

		/+
		{
			auto cs = getComputedStyle();
			auto painter = dropDown.draw();
			draw3dFrame(0, 0, w, h, painter, FrameStyle.risen, getComputedStyle().background.color);
			auto p = Point(4, 4);
			painter.outlineColor = cs.foregroundColor;
			foreach(option; associatedWidget.options) {
				painter.drawText(p, option);
				p.y += defaultLineHeight;
			}
		}

		dropDown.setEventHandlers(
			(MouseEvent event) {
				if(event.type == MouseEventType.buttonReleased) {
					dropDown.close();
					auto element = (event.y - 4) / defaultLineHeight;
					if(element >= 0 && element <= associatedWidget.options.length) {
						associatedWidget.selection_ = element;

						associatedWidget.fireChangeEvent();
					}
				}
			}
		);
		+/

		Widget previouslyFocusedWidget;

		dropDown.visibilityChanged = (bool visible) {
			if(visible) {
				this.redraw();
				captureMouse(this);
				//dropDown.grabInput();

				if(previouslyFocusedWidget is null)
					previouslyFocusedWidget = associatedWidget.parentWindow.focusedWidget;
				associatedWidget.parentWindow.focusedWidget = lw;
			} else {
				//dropDown.releaseInputGrab();
				releaseMouseCapture();

				if(!cancelled)
					associatedWidget.setSelection(lw.getSelection);

				associatedWidget.parentWindow.focusedWidget = previouslyFocusedWidget;
			}
		};

		dropDown.show();
	}

	private bool shouldCloseIfClicked(Widget w) {
		if(w is this)
			return true;
		version(custom_widgets)
		if(cast(TextListViewWidget.TextListViewItem) w)
			return true;
		return false;
	}

	override void defaultEventHandler_click(ClickEvent ce) {
		if(ce.button == MouseButton.left && shouldCloseIfClicked(ce.target)) {
			this.win.close();
		}
	}

	override void defaultEventHandler_char(CharEvent ce) {
		if(ce.character == '\n')
			this.win.close();
	}

	override void defaultEventHandler_keydown(KeyDownEvent kde) {
		if(kde.key == Key.Escape) {
			cancelled = true;
			this.win.close();
		}/+ else if(kde.key == Key.Up || kde.key == Key.Down)
			{} // intentionally blank, the list view handles these
			// separately from the scroll message widget default handler
		else if(lw && lw.glvw && lw.glvw.smw)
			lw.glvw.smw.defaultKeyboardListener(kde);+/
	}
}

/++
	A drop-down list where the user must select one of the
	given options. Like `<select>` in HTML.

	The current selection is given as a string or an index.
	It emits a SelectionChangedEvent when it changes.
+/
class DropDownSelection : ComboboxBase {
	/++
		Creates a drop down selection, optionally passing its initial list of options.

		History:
			The overload with the `options` parameter was added December 29, 2024.
	+/
	this(Widget parent) {
		version(win32_widgets)
			super(3 /* CBS_DROPDOWNLIST */ | WS_VSCROLL, parent);
		else version(custom_widgets) {
			super(parent);

			addEventListener("focus", () { this.redraw; });
			addEventListener("blur", () { this.redraw; });
			addEventListener(EventType.change, () { this.redraw; });
			addEventListener("mousedown", () { this.focus(); this.popup(); });
			addEventListener((KeyDownEvent event) {
				if(event.key == Key.Space)
					popup();
			});
		} else static assert(false);
	}

	/// ditto
	this(string[] options, Widget parent) {
		this(parent);
		this.options = options;
	}

	mixin Padding!q{2};
	static class Style : Widget.Style {
		override FrameStyle borderStyle() { return FrameStyle.risen; }
	}
	mixin OverrideStyle!Style;

	version(custom_widgets)
	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		auto cs = getComputedStyle();

		painter.drawText(bounds.upperLeft, selection_ == -1 ? "" : options[selection_]);

		painter.outlineColor = cs.foregroundColor;
		painter.fillColor = cs.foregroundColor;

		/+
		Point[4] triangle;
		enum padding = 6;
		enum paddingV = 7;
		enum triangleWidth = 10;
		triangle[0] = Point(width - padding - triangleWidth, paddingV);
		triangle[1] = Point(width - padding - triangleWidth / 2, height - paddingV);
		triangle[2] = Point(width - padding - 0, paddingV);
		triangle[3] = triangle[0];
		painter.drawPolygon(triangle[]);
		+/

		auto offset = Point((this.width - scaleWithDpi(16)), (this.height - scaleWithDpi(16)) / 2);

		painter.drawPolygon(
			scaleWithDpi(Point(2, 6) + offset),
			scaleWithDpi(Point(7, 11) + offset),
			scaleWithDpi(Point(12, 6) + offset),
			scaleWithDpi(Point(2, 6) + offset)
		);


		return bounds;
	}

	version(win32_widgets)
	override void registerMovement() {
		version(win32_widgets) {
			if(hwnd) {
				auto pos = getChildPositionRelativeToParentHwnd(this);
				// the height given to this from Windows' perspective is supposed
				// to include the drop down's height. so I add to it to give some
				// room for that.
				// FIXME: maybe make the subclass provide a suggestedDropdownHeight thing
				MoveWindow(hwnd, pos[0], pos[1], width, height + 200, true);
			}
		}
		sendResizeEvent();
	}
}

/++
	A text box with a drop down arrow listing selections.
	The user can choose from the list, or type their own.
+/
class FreeEntrySelection : ComboboxBase {
	this(Widget parent) {
		this(null, parent);
	}

	this(string[] options, Widget parent) {
		version(win32_widgets)
			super(2 /* CBS_DROPDOWN */, parent);
		else version(custom_widgets) {
			super(parent);
			auto hl = new HorizontalLayout(this);
			lineEdit = new LineEdit(hl);

			tabStop = false;

			// lineEdit.addEventListener((FocusEvent fe) {  lineEdit.selectAll(); } );

			auto btn = new class ArrowButton {
				this() {
					super(ArrowDirection.down, hl);
				}
				override int heightStretchiness() {
					return 1;
				}
				override int heightShrinkiness() {
					return 1;
				}
				override int maxHeight() {
					return lineEdit.maxHeight;
				}
			};
			//btn.addDirectEventListener("focus", &lineEdit.focus);
			btn.addEventListener("triggered", &this.popup);
			addEventListener(EventType.change, (Event event) {
				lineEdit.content = event.stringValue;
				lineEdit.focus();
				redraw();
			});
		}
		else static assert(false);

		this.options = options;
	}

	string content() {
		version(win32_widgets)
			assert(0, "not implemented");
		else version(custom_widgets)
			return lineEdit.content;
		else static assert(0);
	}

	void content(string s) {
		version(win32_widgets)
			assert(0, "not implemented");
		else version(custom_widgets)
			lineEdit.content = s;
		else static assert(0);
	}

	version(custom_widgets) {
		LineEdit lineEdit;

		override int widthStretchiness() {
			return lineEdit ? lineEdit.widthStretchiness : super.widthStretchiness;
		}
		override int flexBasisWidth() {
			return lineEdit ? lineEdit.flexBasisWidth : super.flexBasisWidth;
		}
	}
}

/++
	A combination of free entry with a list below it.
+/
class ComboBox : ComboboxBase {
	this(Widget parent) {
		version(win32_widgets)
			super(1 /* CBS_SIMPLE */ | CBS_NOINTEGRALHEIGHT, parent);
		else version(custom_widgets) {
			super(parent);
			lineEdit = new LineEdit(this);
			listWidget = new ListWidget(this);
			listWidget.multiSelect = false;
			listWidget.addEventListener(EventType.change, delegate(Widget, Event) {
				string c = null;
				foreach(option; listWidget.options)
					if(option.selected) {
						c = option.label;
						break;
					}
				lineEdit.content = c;
			});

			listWidget.tabStop = false;
			this.tabStop = false;
			listWidget.addEventListener("focusin", &lineEdit.focus);
			this.addEventListener("focusin", &lineEdit.focus);

			addDirectEventListener(EventType.change, {
				listWidget.setSelection(selection_);
				if(selection_ != -1)
					lineEdit.content = options[selection_];
				lineEdit.focus();
				redraw();
			});

			lineEdit.addEventListener("focusin", &lineEdit.selectAll);

			listWidget.addDirectEventListener(EventType.change, {
				int set = -1;
				foreach(idx, opt; listWidget.options)
					if(opt.selected) {
						set = cast(int) idx;
						break;
					}
				if(set != selection_)
					this.setSelection(set);
			});
		} else static assert(false);
	}

	override int minHeight() { return defaultLineHeight * 3; }
	override int maxHeight() { return cast(int) options.length * defaultLineHeight + defaultLineHeight; }
	override int heightStretchiness() { return 5; }

	version(custom_widgets) {
		LineEdit lineEdit;
		ListWidget listWidget;

		override void addOption(string s) {
			listWidget.addOption(s);
			ComboboxBase.addOption(s);
		}

		override void scrollSelectionIntoView() {
			listWidget.scrollSelectionIntoView();
		}
	}
}

/+
class Spinner : Widget {
	version(win32_widgets)
	this(Widget parent) {
		super(parent);
		parentWindow = parent.parentWindow;
		auto hlayout = new HorizontalLayout(this);
		lineEdit = new LineEdit(hlayout);
		upDownControl = new UpDownControl(hlayout);
	}

	LineEdit lineEdit;
	UpDownControl upDownControl;
}

class UpDownControl : Widget {
	version(win32_widgets)
	this(Widget parent) {
		super(parent);
		parentWindow = parent.parentWindow;
		createWin32Window(this, "msctls_updown32"w, null, 4/*UDS_ALIGNRIGHT*/| 2 /* UDS_SETBUDDYINT */ | 16 /* UDS_AUTOBUDDY */ | 32 /* UDS_ARROWKEYS */);
	}

	override int minHeight() { return defaultLineHeight; }
	override int maxHeight() { return defaultLineHeight * 3/2; }

	override int minWidth() { return defaultLineHeight * 3/2; }
	override int maxWidth() { return defaultLineHeight * 3/2; }
}
+/

/+
class DataView : Widget {
	// this is the omnibus data viewer
	// the internal data layout is something like:
	// string[string][] but also each node can have parents
}
+/


// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775491(v=vs.85).aspx#PROGRESS_CLASS

// http://svn.dsource.org/projects/bindings/trunk/win32/commctrl.d

// FIXME: menus should prolly capture the mouse. ugh i kno.
/*
	TextEdit needs:

	* caret manipulation
	* selection control
	* convenience functions for appendText, insertText, insertTextAtCaret, etc.

	For example:

	connect(paste, &textEdit.insertTextAtCaret);

	would be nice.



	I kinda want an omnibus dataview that combines list, tree,
	and table - it can be switched dynamically between them.

	Flattening policy: only show top level, show recursive, show grouped
	List styles: plain list (e.g. <ul>), tiles (some details next to it), icons (like Windows explorer)

	Single select, multi select, organization, drag+drop
*/

//static if(UsingSimpledisplayX11)
version(win32_widgets) {}
else version(custom_widgets) {
	enum scrollClickRepeatInterval = 50;

deprecated("Get these properties off `Widget.getComputedStyle` instead. The defaults are now set in the `WidgetPainter.visualTheme`.") {
	enum windowBackgroundColor = Color(212, 212, 212); // used to be 192
	enum activeTabColor = lightAccentColor;
	enum hoveringColor = Color(228, 228, 228);
	enum buttonColor = windowBackgroundColor;
	enum depressedButtonColor = darkAccentColor;
	enum activeListXorColor = Color(255, 255, 127);
	enum progressBarColor = Color(0, 0, 128);
	enum activeMenuItemColor = Color(0, 0, 128);

}}
else static assert(false);
deprecated("Get these properties off the `visualTheme` instead.") {
	// these are used by horizontal rule so not just custom_widgets. for now at least.
	enum darkAccentColor = Color(172, 172, 172);
	enum lightAccentColor = Color(223, 223, 223); // used to be 223
}

private const(wchar)* toWstringzInternal(in char[] s) {
	wchar[] str;
	str.reserve(s.length + 1);
	foreach(dchar ch; s)
		str ~= ch;
	str ~= '\0';
	return str.ptr;
}

static if(SimpledisplayTimerAvailable)
void setClickRepeat(Widget w, int interval, int delay = 250) {
	Timer timer;
	int delayRemaining = delay / interval;
	if(delayRemaining <= 1)
		delayRemaining = 2;

	immutable originalDelayRemaining = delayRemaining;

	w.addDirectEventListener((scope MouseDownEvent ev) {
		if(ev.srcElement !is w)
			return;
		if(timer !is null) {
			timer.destroy();
			timer = null;
		}
		delayRemaining = originalDelayRemaining;
		timer = new Timer(interval, () {
			if(delayRemaining > 0)
				delayRemaining--;
			else {
				auto ev = new Event("triggered", w);
				ev.sendDirectly();
			}
		});
	});

	w.addDirectEventListener((scope MouseUpEvent ev) {
		if(ev.srcElement !is w)
			return;
		if(timer !is null) {
			timer.destroy();
			timer = null;
		}
	});

	w.addDirectEventListener((scope MouseLeaveEvent ev) {
		if(ev.srcElement !is w)
			return;
		if(timer !is null) {
			timer.destroy();
			timer = null;
		}
	});

}
else
void setClickRepeat(Widget w, int interval, int delay = 250) {}

enum FrameStyle {
	none, ///
	risen, /// a 3d pop-out effect (think Windows 95 button)
	sunk, /// a 3d sunken effect (think Windows 95 button as you click on it)
	solid, ///
	dotted, ///
	fantasy, /// a style based on a popular fantasy video game
	rounded, /// a rounded rectangle
}

version(custom_widgets)
deprecated
void draw3dFrame(Widget widget, ScreenPainter painter, FrameStyle style) {
	draw3dFrame(0, 0, widget.width, widget.height, painter, style, WidgetPainter.visualTheme.windowBackgroundColor);
}

version(custom_widgets)
void draw3dFrame(Widget widget, ScreenPainter painter, FrameStyle style, Color background) {
	draw3dFrame(0, 0, widget.width, widget.height, painter, style, background);
}

version(custom_widgets)
deprecated
void draw3dFrame(int x, int y, int width, int height, ScreenPainter painter, FrameStyle style) {
	draw3dFrame(x, y, width, height, painter, style, WidgetPainter.visualTheme.windowBackgroundColor);
}

int getBorderWidth(FrameStyle style) {
	final switch(style) {
		case FrameStyle.sunk, FrameStyle.risen:
			return 2;
		case FrameStyle.none:
			return 0;
		case FrameStyle.solid:
			return 1;
		case FrameStyle.dotted:
			return 1;
		case FrameStyle.fantasy:
			return 3;
		case FrameStyle.rounded:
			return 2;
	}
}

int draw3dFrame(int x, int y, int width, int height, ScreenPainter painter, FrameStyle style, Color background, Color border = Color.transparent) {
	int borderWidth = getBorderWidth(style);
	final switch(style) {
		case FrameStyle.sunk, FrameStyle.risen:
			// outer layer
			painter.outlineColor = style == FrameStyle.sunk ? Color.white : Color.black;
		break;
		case FrameStyle.none:
			painter.outlineColor = background;
		break;
		case FrameStyle.solid:
		case FrameStyle.rounded:
			painter.pen = Pen(border, 1);
		break;
		case FrameStyle.dotted:
			painter.pen = Pen(border, 1, Pen.Style.Dotted);
		break;
		case FrameStyle.fantasy:
			painter.pen = Pen(border, 3);
		break;
	}

	painter.fillColor = background;

	if(style == FrameStyle.rounded) {
		painter.drawRectangleRounded(Point(x, y), Size(width, height), 6);
	} else {
		painter.drawRectangle(Point(x + 0, y + 0), width, height);

		if(style == FrameStyle.sunk || style == FrameStyle.risen) {
			// 3d effect
			auto vt = WidgetPainter.visualTheme;

			painter.outlineColor = (style == FrameStyle.sunk) ? vt.darkAccentColor : vt.lightAccentColor;
			painter.drawLine(Point(x + 0, y + 0), Point(x + width, y + 0));
			painter.drawLine(Point(x + 0, y + 0), Point(x + 0, y + height - 1));

			// inner layer
			//right, bottom
			painter.outlineColor = (style == FrameStyle.sunk) ? vt.lightAccentColor : vt.darkAccentColor;
			painter.drawLine(Point(x + width - 2, y + 2), Point(x + width - 2, y + height - 2));
			painter.drawLine(Point(x + 2, y + height - 2), Point(x + width - 2, y + height - 2));
			// left, top
			painter.outlineColor = (style == FrameStyle.sunk) ? Color.black : Color.white;
			painter.drawLine(Point(x + 1, y + 1), Point(x + width, y + 1));
			painter.drawLine(Point(x + 1, y + 1), Point(x + 1, y + height - 2));
		} else if(style == FrameStyle.fantasy) {
			painter.pen = Pen(Color.white, 1, Pen.Style.Solid);
			painter.fillColor = Color.transparent;
			painter.drawRectangle(Point(x + 1, y + 1), Point(x + width - 1, y + height - 1));
		}
	}

	return borderWidth;
}

/++
	An `Action` represents some kind of user action they can trigger through menu options, toolbars, hotkeys, and similar mechanisms. The text label, icon, and handlers are centrally held here instead of repeated in each UI element.

	See_Also:
		[MenuItem]
		[ToolButton]
		[Menu.addItem]
+/
class Action {
	version(win32_widgets) {
		private int id;
		private static int lastId = 9000;
		private static Action[int] mapping;
	}

	KeyEvent accelerator;

	// FIXME: disable message
	// and toggle thing?
	// ??? and trigger arguments too ???

	/++
		Params:
			label = the textual label
			icon = icon ID. See [GenericIcons]. There is currently no way to do custom icons.
			triggered = initial handler, more can be added via the [triggered] member.
	+/
	this(string label, ushort icon = 0, void delegate() triggered = null) {
		this.label = label;
		this.iconId = icon;
		if(triggered !is null)
			this.triggered ~= triggered;
		version(win32_widgets) {
			id = ++lastId;
			mapping[id] = this;
		}
	}

	private string label;
	private ushort iconId;
	// icon

	// when it is triggered, the triggered event is fired on the window
	/// The list of handlers when it is triggered.
	void delegate()[] triggered;
}

/*
	plan:
		keyboard accelerators

		* menus (and popups and tooltips)
		* status bar
		* toolbars and buttons

		sortable table view

		maybe notification area icons
		basic clipboard

		* radio box
		splitter
		toggle buttons (optionally mutually exclusive, like in Paint)
		label, rich text display, multi line plain text (selectable)
		* fieldset
		* nestable grid layout
		single line text input
		* multi line text input
		slider
		spinner
		list box
		drop down
		combo box
		auto complete box
		* progress bar

		terminal window/widget (on unix it might even be a pty but really idk)

		ok button
		cancel button

		keyboard hotkeys

		scroll widget

		event redirections and network transparency
		script integration
*/


/*
	MENUS

	auto bar = new MenuBar(window);
	window.menuBar = bar;

	auto fileMenu = bar.addItem(new Menu("&File"));
	fileMenu.addItem(new MenuItem("&Exit"));


	EVENTS

	For controls, you should usually use "triggered" rather than "click", etc., because
	triggered handles both keyboard (focus and press as well as hotkeys) and mouse activation.
	This is the case on menus and pushbuttons.

	"click", on the other hand, currently only fires when it is literally clicked by the mouse.
*/


/*
enum LinePreference {
	AlwaysOnOwnLine, // always on its own line
	PreferOwnLine, // it will always start a new line, and if max width <= line width, it will expand all the way
	PreferToShareLine, // does not force new line, and if the next child likes to share too, they will div it up evenly. otherwise, it will expand as much as it can
}
*/

/++
	Convenience mixin for overriding all four sides of margin or padding in a [Widget] with the same code. It mixes in the given string as the return value of the four overridden methods.

	---
	class MyWidget : Widget {
		this(Widget parent) { super(parent); }

		// set paddingLeft, paddingRight, paddingTop, and paddingBottom all to `return 4;` in one go:
		mixin Padding!q{4};

		// set marginLeft, marginRight, marginTop, and marginBottom all to `return 8;` in one go:
		mixin Margin!q{8};

		// but if I specify one outside, it overrides the override, so now marginLeft is 2,
		// while Top/Bottom/Right remain 8 from the mixin above.
		override int marginLeft() { return 2; }
	}
	---


	The minigui layout model is based on the web's CSS box model. The layout engine* arranges widgets based on their margin for separation and assigns them a size based on thier preferences (e.g. [Widget.minHeight]) and the available space. Widgets are assigned a size by the layout engine. Inside this size, they have a border (see [Widget.Style.borderWidth]), then padding space, and then their content. Their content box may also have an outline drawn on top of it (see [Widget.Style.outlineStyle]).

	Padding is the area inside a widget where its background is drawn, but the content avoids.

	Margin is the area between widgets. The algorithm is the spacing between any two widgets is the max of their adjacent margins (not the sum!).

	* Some widgets do not participate in placement, e.g. [StaticPosition], and some layout systems do their own separate thing too; ultimately, these properties are just hints to the layout function and you can always implement your own to do whatever you want. But this statement is still mostly true.
+/
mixin template Padding(string code) {
	override int paddingLeft() { return mixin(code);}
	override int paddingRight() { return mixin(code);}
	override int paddingTop() { return mixin(code);}
	override int paddingBottom() { return mixin(code);}
}

/// ditto
mixin template Margin(string code) {
	override int marginLeft() { return mixin(code);}
	override int marginRight() { return mixin(code);}
	override int marginTop() { return mixin(code);}
	override int marginBottom() { return mixin(code);}
}

private
void recomputeChildLayout(string relevantMeasure)(Widget parent) {
	enum calcingV = relevantMeasure == "height";

	parent.registerMovement();

	if(parent.children.length == 0)
		return;

	auto parentStyle = parent.getComputedStyle();

	enum firstThingy = relevantMeasure == "height" ? "Top" : "Left";
	enum secondThingy = relevantMeasure == "height" ? "Bottom" : "Right";

	enum otherFirstThingy = relevantMeasure == "height" ? "Left" : "Top";
	enum otherSecondThingy = relevantMeasure == "height" ? "Right" : "Bottom";

	// my own width and height should already be set by the caller of this function...
	int spaceRemaining = mixin("parent." ~ relevantMeasure) -
		mixin("parentStyle.padding"~firstThingy~"()") -
		mixin("parentStyle.padding"~secondThingy~"()");

	int stretchinessSum;
	int stretchyChildSum;
	int lastMargin = 0;

	int shrinkinessSum;
	int shrinkyChildSum;

	// set initial size
	foreach(child; parent.children) {

		auto childStyle = child.getComputedStyle();

		if(cast(StaticPosition) child)
			continue;
		if(child.hidden)
			continue;

		const iw = child.flexBasisWidth();
		const ih = child.flexBasisHeight();

		static if(calcingV) {
			child.width = parent.width -
				mixin("childStyle.margin"~otherFirstThingy~"()") -
				mixin("childStyle.margin"~otherSecondThingy~"()") -
				mixin("parentStyle.padding"~otherFirstThingy~"()") -
				mixin("parentStyle.padding"~otherSecondThingy~"()");

			if(child.width < 0)
				child.width = 0;
			if(child.width > childStyle.maxWidth())
				child.width = childStyle.maxWidth();

			if(iw > 0) {
				auto totalPossible = child.width;
				if(child.width > iw && child.widthStretchiness() == 0)
					child.width = iw;
			}

			child.height = mymax(childStyle.minHeight(), ih);
		} else {
			// set to take all the space
			child.height = parent.height -
				mixin("childStyle.margin"~firstThingy~"()") -
				mixin("childStyle.margin"~secondThingy~"()") -
				mixin("parentStyle.padding"~firstThingy~"()") -
				mixin("parentStyle.padding"~secondThingy~"()");

			// then clamp it
			if(child.height < 0)
				child.height = 0;
			if(child.height > childStyle.maxHeight())
				child.height = childStyle.maxHeight();

			// and if possible, respect the ideal target
			if(ih > 0) {
				auto totalPossible = child.height;
				if(child.height > ih && child.heightStretchiness() == 0)
					child.height = ih;
			}

			// if we have an ideal, try to respect it, otehrwise, just use the minimum
			child.width = mymax(childStyle.minWidth(), iw);
		}

		spaceRemaining -= mixin("child." ~ relevantMeasure);

		int thisMargin = mymax(lastMargin, mixin("childStyle.margin"~firstThingy~"()"));
		auto margin = mixin("childStyle.margin" ~ secondThingy ~ "()");
		lastMargin = margin;
		spaceRemaining -= thisMargin + margin;

		auto s = mixin("child." ~ relevantMeasure ~ "Stretchiness()");
		stretchinessSum += s;
		if(s > 0)
			stretchyChildSum++;

		auto s2 = mixin("child." ~ relevantMeasure ~ "Shrinkiness()");
		shrinkinessSum += s2;
		if(s2 > 0)
			shrinkyChildSum++;
	}

	if(spaceRemaining < 0 && shrinkyChildSum) {
		// shrink to get into the space if it is possible
		auto toRemove = -spaceRemaining;
		auto removalPerItem = toRemove / shrinkinessSum;
		auto remainder = toRemove % shrinkinessSum;

		// FIXME: wtf why am i shrinking things with no shrinkiness?

		foreach(child; parent.children) {
			auto childStyle = child.getComputedStyle();
			if(cast(StaticPosition) child)
				continue;
			if(child.hidden)
				continue;
			static if(calcingV) {
				auto minimum = childStyle.minHeight();
				auto stretch = childStyle.heightShrinkiness();
			} else {
				auto minimum = childStyle.minWidth();
				auto stretch = childStyle.widthShrinkiness();
			}

			if(mixin("child._" ~ relevantMeasure) <= minimum)
				continue;
			// import arsd.core; writeln(typeid(child).toString, " ", child._width, " > ", minimum, " :: ", removalPerItem, "*", stretch);

			mixin("child._" ~ relevantMeasure) -= removalPerItem * stretch + remainder / shrinkyChildSum; // this is removing more than needed to trigger the next thing. ugh.

			spaceRemaining += removalPerItem * stretch + remainder / shrinkyChildSum;
		}
	}

	// stretch to fill space
	while(spaceRemaining > 0 && stretchinessSum && stretchyChildSum) {
		auto spacePerChild = spaceRemaining / stretchinessSum;
		bool spreadEvenly;
		bool giveToBiggest;
		if(spacePerChild <= 0) {
			spacePerChild = spaceRemaining / stretchyChildSum;
			spreadEvenly = true;
		}
		if(spacePerChild <= 0) {
			giveToBiggest = true;
		}
		int previousSpaceRemaining = spaceRemaining;
		stretchinessSum = 0;
		Widget mostStretchy;
		int mostStretchyS;
		foreach(child; parent.children) {
			auto childStyle = child.getComputedStyle();
			if(cast(StaticPosition) child)
				continue;
			if(child.hidden)
				continue;
			static if(calcingV) {
				auto maximum = childStyle.maxHeight();
			} else {
				auto maximum = childStyle.maxWidth();
			}

			if(mixin("child." ~ relevantMeasure) >= maximum) {
				auto adj = mixin("child." ~ relevantMeasure) - maximum;
				mixin("child._" ~ relevantMeasure) -= adj;
				spaceRemaining += adj;
				continue;
			}
			auto s = mixin("child." ~ relevantMeasure ~ "Stretchiness()");
			if(s <= 0)
				continue;
			auto spaceAdjustment = spacePerChild * (spreadEvenly ? 1 : s);
			mixin("child._" ~ relevantMeasure) += spaceAdjustment;
			spaceRemaining -= spaceAdjustment;
			if(mixin("child." ~ relevantMeasure) > maximum) {
				auto diff = mixin("child." ~ relevantMeasure) - maximum;
				mixin("child._" ~ relevantMeasure) -= diff;
				spaceRemaining += diff;
			} else if(mixin("child._" ~ relevantMeasure) < maximum) {
				stretchinessSum += mixin("child." ~ relevantMeasure ~ "Stretchiness()");
				if(mostStretchy is null || s >= mostStretchyS) {
					mostStretchy = child;
					mostStretchyS = s;
				}
			}
		}

		if(giveToBiggest && mostStretchy !is null) {
			auto child = mostStretchy;
			auto childStyle = child.getComputedStyle();
			int spaceAdjustment = spaceRemaining;

			static if(calcingV)
				auto maximum = childStyle.maxHeight();
			else
				auto maximum = childStyle.maxWidth();

			mixin("child._" ~ relevantMeasure) += spaceAdjustment;
			spaceRemaining -= spaceAdjustment;
			if(mixin("child._" ~ relevantMeasure) > maximum) {
				auto diff = mixin("child." ~ relevantMeasure) - maximum;
				mixin("child._" ~ relevantMeasure) -= diff;
				spaceRemaining += diff;
			}
		}

		if(spaceRemaining == previousSpaceRemaining) {
			if(mostStretchy !is null) {
				static if(calcingV)
					auto maximum = mostStretchy.maxHeight();
				else
					auto maximum = mostStretchy.maxWidth();

				mixin("mostStretchy._" ~ relevantMeasure) += spaceRemaining;
				if(mixin("mostStretchy._" ~ relevantMeasure) > maximum)
					mixin("mostStretchy._" ~ relevantMeasure) = maximum;
			}
			break; // apparently nothing more we can do
		}
	}

	foreach(child; parent.children) {
		auto childStyle = child.getComputedStyle();
		if(cast(StaticPosition) child)
			continue;
		if(child.hidden)
			continue;

		static if(calcingV)
			auto maximum = childStyle.maxHeight();
		else
			auto maximum = childStyle.maxWidth();
		if(mixin("child._" ~ relevantMeasure) > maximum)
			mixin("child._" ~ relevantMeasure) = maximum;
	}

	// position
	lastMargin = 0;
	int currentPos = mixin("parent.padding"~firstThingy~"()");
	foreach(child; parent.children) {
		auto childStyle = child.getComputedStyle();
		if(cast(StaticPosition) child) {
			child.recomputeChildLayout();
			continue;
		}
		if(child.hidden)
			continue;
		auto margin = mixin("childStyle.margin" ~ secondThingy ~ "()");
		int thisMargin = mymax(lastMargin, mixin("childStyle.margin"~firstThingy~"()"));
		currentPos += thisMargin;
		static if(calcingV) {
			child.x = parentStyle.paddingLeft() + childStyle.marginLeft();
			child.y = currentPos;
		} else {
			child.x = currentPos;
			child.y = parentStyle.paddingTop() + childStyle.marginTop();

		}
		currentPos += mixin("child." ~ relevantMeasure);
		currentPos += margin;
		lastMargin = margin;

		child.recomputeChildLayout();
	}
}

int mymax(int a, int b) { return a > b ? a : b; }
int mymax(int a, int b, int c) {
	auto d = mymax(a, b);
	return c > d ? c : d;
}

// OK so we need to make getting at the native window stuff possible in simpledisplay.d
// and here, it must be integrable with the layout, the event system, and not be painted over.
version(win32_widgets) {

	// this function just does stuff that a parent window needs for redirection
	int WindowProcedureHelper(Widget this_, HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, out int mustReturn) {
		this_.hookedWndProc(msg, wParam, lParam);

		switch(msg) {

			case WM_VSCROLL, WM_HSCROLL:
				auto pos = HIWORD(wParam);
				auto m = LOWORD(wParam);

				auto scrollbarHwnd = cast(HWND) lParam;

				if(auto widgetp = scrollbarHwnd in Widget.nativeMapping) {

					//auto smw = cast(ScrollMessageWidget) widgetp.parent;

					switch(m) {
						/+
						// I don't think those messages are ever actually sent normally by the widget itself,
						// they are more used for the keyboard interface. methinks.
						case SB_BOTTOM:
							// writeln("end");
							auto event = new Event("scrolltoend", *widgetp);
							event.dispatch();
							//if(!event.defaultPrevented)
						break;
						case SB_TOP:
							// writeln("top");
							auto event = new Event("scrolltobeginning", *widgetp);
							event.dispatch();
						break;
						case SB_ENDSCROLL:
							// idk
						break;
						+/
						case SB_LINEDOWN:
							(*widgetp).emitCommand!"scrolltonextline"();
						return 0;
						case SB_LINEUP:
							(*widgetp).emitCommand!"scrolltopreviousline"();
						return 0;
						case SB_PAGEDOWN:
							(*widgetp).emitCommand!"scrolltonextpage"();
						return 0;
						case SB_PAGEUP:
							(*widgetp).emitCommand!"scrolltopreviouspage"();
						return 0;
						case SB_THUMBPOSITION:
							auto ev = new ScrollToPositionEvent(*widgetp, pos);
							ev.dispatch();
						return 0;
						case SB_THUMBTRACK:
							// eh kinda lying but i like the real time update display
							auto ev = new ScrollToPositionEvent(*widgetp, pos);
							ev.dispatch();

							// the event loop doesn't seem to carry on with a requested redraw..
							// so we request it to get our dirty bit set...
							// then we need to immediately actually redraw it too for instant feedback to user
							SimpleWindow.processAllCustomEvents();
							SimpleWindow.processAllCustomEvents();
							//if(this_.parentWindow)
								//this_.parentWindow.actualRedraw();

							// and this ensures the WM_PAINT message is sent fairly quickly
							// still seems to lag a little in large windows but meh it basically works.
							if(this_.parentWindow) {
								// FIXME: if painting is slow, this does still lag
								// we probably will want to expose some user hook to ScrollWindowEx
								// or something.
								UpdateWindow(this_.parentWindow.hwnd);
							}
						return 0;
						default:
					}
				}
			break;

			case WM_CONTEXTMENU:
				auto hwndFrom = cast(HWND) wParam;

				auto xPos = cast(short) LOWORD(lParam);
				auto yPos = cast(short) HIWORD(lParam);

				if(auto widgetp = hwndFrom in Widget.nativeMapping) {
					POINT p;
					p.x = xPos;
					p.y = yPos;
					ScreenToClient(hwnd, &p);
					auto clientX = cast(ushort) p.x;
					auto clientY = cast(ushort) p.y;

					auto wap = widgetAtPoint(*widgetp, clientX, clientY);

					if(wap.widget.showContextMenu(wap.x, wap.y, xPos, yPos)) {
						return 0;
					}
				}
			break;

			case WM_DRAWITEM:
				auto dis = cast(DRAWITEMSTRUCT*) lParam;
				if(auto widgetp = dis.hwndItem in Widget.nativeMapping) {
					return (*widgetp).handleWmDrawItem(dis);
				}
			break;

			case WM_NOTIFY:
				auto hdr = cast(NMHDR*) lParam;
				auto hwndFrom = hdr.hwndFrom;
				auto code = hdr.code;

				if(auto widgetp = hwndFrom in Widget.nativeMapping) {
					return (*widgetp).handleWmNotify(hdr, code, mustReturn);
				}
			break;
			case WM_COMMAND:
				auto handle = cast(HWND) lParam;
				auto cmd = HIWORD(wParam);
				return processWmCommand(hwnd, handle, cmd, LOWORD(wParam));

			default:
				// pass it on
		}
		return 0;
	}



	extern(Windows)
	private
	// this is called by native child windows, whereas the other hook is done by simpledisplay windows
	// but can i merge them?!
	LRESULT HookedWndProc(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) nothrow {
		// try { writeln(iMessage); } catch(Exception e) {};

		if(auto te = hWnd in Widget.nativeMapping) {
			try {

				te.hookedWndProc(iMessage, wParam, lParam);

				int mustReturn;
				auto ret = WindowProcedureHelper(*te, hWnd, iMessage, wParam, lParam, mustReturn);
				if(mustReturn)
					return ret;

				if(iMessage == WM_SETFOCUS) {
					auto lol = *te;
					while(lol !is null && lol.implicitlyCreated)
						lol = lol.parent;
					lol.focus();
					//(*te).parentWindow.focusedWidget = lol;
				}


				if(iMessage == WM_CTLCOLOREDIT) {

				}
				if(iMessage == WM_CTLCOLORBTN || iMessage == WM_CTLCOLORSTATIC) {
					SetBkMode(cast(HDC) wParam, TRANSPARENT);
					return cast(typeof(return)) GetSysColorBrush(COLOR_3DFACE); // this is the window background color...
						//GetStockObject(NULL_BRUSH);
				}

				auto pos = getChildPositionRelativeToParentOrigin(*te);
				lastDefaultPrevented = false;
				// try { writeln(typeid(*te)); } catch(Exception e) {}
				if(SimpleWindow.triggerEvents(hWnd, iMessage, wParam, lParam, pos[0], pos[1], (*te).parentWindow.win) || !lastDefaultPrevented)
					return CallWindowProcW((*te).originalWindowProcedure, hWnd, iMessage, wParam, lParam);
				else {
					// it was something we recognized, should only call the window procedure if the default was not prevented
				}
			} catch(Exception e) {
				assert(0, e.toString());
			}
			return 0;
		}
		assert(0, "shouldn't be receiving messages for this window....");
		//assert(0, to!string(hWnd) ~ " :: " ~ to!string(TextEdit.nativeMapping)); // not supposed to happen
	}

	extern(Windows)
	private
	// see for info https://jeffpar.github.io/kbarchive/kb/079/Q79982/
	LRESULT HookedWndProcBSGROUPBOX_HACK(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) nothrow {
		if(iMessage == WM_ERASEBKGND) {
			auto dc = GetDC(hWnd);
			auto b = SelectObject(dc, GetSysColorBrush(COLOR_3DFACE));
			auto p = SelectObject(dc, GetStockObject(NULL_PEN));
			RECT r;
			GetWindowRect(hWnd, &r);
			// since the pen is null, to fill the whole space, we need the +1 on both.
			gdi.Rectangle(dc, 0, 0, r.right - r.left + 1, r.bottom - r.top + 1);
			SelectObject(dc, p);
			SelectObject(dc, b);
			ReleaseDC(hWnd, dc);
			InvalidateRect(hWnd, null, false); // redraw the border
			return 1;
		}
		return HookedWndProc(hWnd, iMessage, wParam, lParam);
	}

	/++
		Calls MS Windows' CreateWindowExW function to create a native backing for the given widget. It will create
		needed mappings, window procedure hooks, and other private member variables needed to tie it into the rest
		of minigui's expectations.

		This should be called in your widget's constructor AFTER you call `super(parent);`. The parent window
		member MUST already be initialized for this function to succeed, which is done by [Widget]'s base constructor.

		It assumes `className` is zero-terminated. It should come from a `"wide string literal"w`.

		To check if you can use this, use `static if(UsingWin32Widgets)`.
	+/
	void createWin32Window(Widget p, const(wchar)[] className, string windowText, DWORD style, DWORD extStyle = 0) {
		assert(p.parentWindow !is null);
		assert(p.parentWindow.win.impl.hwnd !is null);

		auto bsgroupbox = style == BS_GROUPBOX;

		HWND phwnd;

		auto wtf = p.parent;
		while(wtf) {
			if(wtf.hwnd !is null) {
				phwnd = wtf.hwnd;
				break;
			}
			wtf = wtf.parent;
		}

		if(phwnd is null)
			phwnd = p.parentWindow.win.impl.hwnd;

		assert(phwnd !is null);

		WCharzBuffer wt = WCharzBuffer(windowText);

		style |= WS_VISIBLE | WS_CHILD;
		//if(className != WC_TABCONTROL)
			style |= WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
		p.hwnd = CreateWindowExW(extStyle, className.ptr, wt.ptr, style,
				CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
				phwnd, null, cast(HINSTANCE) GetModuleHandle(null), null);

		assert(p.hwnd !is null);


		static HFONT font;
		if(font is null) {
			NONCLIENTMETRICS params;
			params.cbSize = params.sizeof;
			if(SystemParametersInfo(SPI_GETNONCLIENTMETRICS, params.sizeof, &params, 0)) {
				font = CreateFontIndirect(&params.lfMessageFont);
			}
		}

		if(font)
			SendMessage(p.hwnd, WM_SETFONT, cast(uint) font, true);

		p.simpleWindowWrappingHwnd = new SimpleWindow(p.hwnd);
		p.simpleWindowWrappingHwnd.beingOpenKeepsAppOpen = false;
		Widget.nativeMapping[p.hwnd] = p;

		if(bsgroupbox)
		p.originalWindowProcedure = cast(WNDPROC) SetWindowLongPtr(p.hwnd, GWL_WNDPROC, cast(size_t) &HookedWndProcBSGROUPBOX_HACK);
		else
		p.originalWindowProcedure = cast(WNDPROC) SetWindowLongPtr(p.hwnd, GWL_WNDPROC, cast(size_t) &HookedWndProc);

		EnumChildWindows(p.hwnd, &childHandler, cast(LPARAM) cast(void*) p);

		p.registerMovement();
	}
}

version(win32_widgets)
private
extern(Windows) BOOL childHandler(HWND hwnd, LPARAM lparam) {
	if(hwnd is null || hwnd in Widget.nativeMapping)
		return true;
	auto parent = cast(Widget) cast(void*) lparam;
	Widget p = new Widget(null);
	p._parent = parent;
	p.parentWindow = parent.parentWindow;
	p.hwnd = hwnd;
	p.implicitlyCreated = true;
	Widget.nativeMapping[p.hwnd] = p;
	p.originalWindowProcedure = cast(WNDPROC) SetWindowLongPtr(p.hwnd, GWL_WNDPROC, cast(size_t) &HookedWndProc);
	return true;
}

/++
	Encapsulates the simpledisplay [ScreenPainter] for use on a [Widget], with [VisualTheme] and invalidated area awareness.
+/
struct WidgetPainter {
	this(ScreenPainter screenPainter, Widget drawingUpon) {
		this.drawingUpon = drawingUpon;
		this.screenPainter = screenPainter;

		this.widgetClipRectangle = screenPainter.currentClipRectangle;

		// this.screenPainter.impl.enableXftDraw();
		if(auto font = visualTheme.defaultFontCached(drawingUpon.currentDpi))
			this.screenPainter.setFont(font);
	}

	/++
		EXPERIMENTAL. subject to change.

		When you draw a cursor, you can draw this to notify your window of where it is,
		for IME systems to use.
	+/
	void notifyCursorPosition(int x, int y, int width, int height) {
		if(auto a = drawingUpon.parentWindow)
		if(auto w = a.inputProxy) {
			w.setIMEPopupLocation(x + screenPainter.originX + width, y + screenPainter.originY + height);
		}
	}

	private Rectangle widgetClipRectangle;

	private Rectangle setClipRectangleForWidget(Point upperLeft, int width, int height) {
		widgetClipRectangle = Rectangle(upperLeft, Size(width, height));

		return screenPainter.setClipRectangle(widgetClipRectangle);
	}

	/++
		Sets the clip rectangle to the given settings. It will automatically calculate the intersection
		of your widget's content boundaries and your requested clip rectangle.

		History:
			Before February 26, 2025, you could sometimes exceed widget boundaries, as this forwarded
			directly to the underlying `ScreenPainter`. It now wraps it to calculate the intersection.
	+/
	Rectangle setClipRectangle(Rectangle rectangle) {
		return screenPainter.setClipRectangle(rectangle.intersectionOf(widgetClipRectangle));
	}
	/// ditto
	Rectangle setClipRectangle(Point upperLeft, int width, int height) {
		return setClipRectangle(Rectangle(upperLeft, Size(width, height)));
	}
	/// ditto
	Rectangle setClipRectangle(Point upperLeft, Size size) {
		return setClipRectangle(Rectangle(upperLeft, size));
	}

	///
	ScreenPainter screenPainter;
	/// Forward to the screen painter for all other methods, see [arsd.simpledisplay.ScreenPainter] for more information
	alias screenPainter this;

	private Widget drawingUpon;

	/++
		This is the list of rectangles that actually need to be redrawn.

		Not actually implemented yet.
	+/
	Rectangle[] invalidatedRectangles;

	private static BaseVisualTheme _visualTheme;

	/++
		Functions to access the visual theme and helpers to easily use it.

		These are aware of the current widget's computed style out of the theme.
	+/
	static @property BaseVisualTheme visualTheme() {
		if(_visualTheme is null)
			_visualTheme = new DefaultVisualTheme();
		return _visualTheme;
	}

	/// ditto
	static @property void visualTheme(BaseVisualTheme theme) {
		_visualTheme = theme;

		// FIXME: notify all windows about the new theme, they should recompute layout and redraw.
	}

	/// ditto
	Color themeForeground() {
		return drawingUpon.getComputedStyle().foregroundColor();
	}

	/// ditto
	Color themeBackground() {
		return drawingUpon.getComputedStyle().background.color;
	}

	int isDarkTheme() {
		return 0; // unspecified, yes, no as enum. FIXME
	}

	/++
		Draws the general pattern of a widget if you don't need anything particularly special and/or control the other details through your widget's style theme hints.

		It gives your draw delegate a [Rectangle] representing the coordinates inside your border and padding.

		If you change teh clip rectangle, you should change it back before you return.


		The sequence it uses is:
			background
			content (delegated to you)
			border
			focused outline
			selected overlay

		Example code:

		---
		void paint(WidgetPainter painter) {
			painter.drawThemed((bounds) {
				return bounds; // if the selection overlay should be contained, you can return it here.
			});
		}
		---
	+/
	void drawThemed(scope Rectangle delegate(const Rectangle bounds) drawBody) {
		drawThemed((WidgetPainter painter, const Rectangle bounds) {
			return drawBody(bounds);
		});
	}
	// this overload is actually mroe for setting the delegate to a virtual function
	void drawThemed(scope Rectangle delegate(WidgetPainter painter, const Rectangle bounds) drawBody) {
		Rectangle rect = Rectangle(0, 0, drawingUpon.width, drawingUpon.height);

		auto cs = drawingUpon.getComputedStyle();

		auto bg = cs.background.color;

		auto borderWidth = draw3dFrame(0, 0, drawingUpon.width, drawingUpon.height, this, cs.borderStyle, bg, cs.borderColor);

		rect.left += borderWidth;
		rect.right -= borderWidth;
		rect.top += borderWidth;
		rect.bottom -= borderWidth;

		auto insideBorderRect = rect;

		rect.left += cs.paddingLeft;
		rect.right -= cs.paddingRight;
		rect.top += cs.paddingTop;
		rect.bottom -= cs.paddingBottom;

		this.outlineColor = this.themeForeground;
		this.fillColor = bg;

		auto widgetFont = cs.fontCached;
		if(widgetFont !is null)
			this.setFont(widgetFont);

		rect = drawBody(this, rect);

		if(widgetFont !is null) {
			if(auto vtFont = visualTheme.defaultFontCached(drawingUpon.currentDpi))
				this.setFont(vtFont);
			else
				this.setFont(null);
		}

		if(auto os = cs.outlineStyle()) {
			this.pen = Pen(cs.outlineColor(), 1, os == FrameStyle.dotted ? Pen.Style.Dotted : Pen.Style.Solid);
			this.fillColor = Color.transparent;
			this.drawRectangle(insideBorderRect);
		}
	}

	/++
		First, draw the background.
		Then draw your content.
		Next, draw the border.
		And the focused indicator.
		And the is-selected box.

		If it is focused i can draw the outline too...

		If selected i can even do the xor action but that's at the end.
	+/
	void drawThemeBackground() {

	}

	void drawThemeBorder() {

	}

	// all this stuff is a dangerous experiment....
	static class ScriptableVersion {
		ScreenPainterImplementation* p;
		int originX, originY;

		@scriptable:
		void drawRectangle(int x, int y, int width, int height) {
			p.drawRectangle(x + originX, y + originY, width, height);
		}
		void drawLine(int x1, int y1, int x2, int y2) {
			p.drawLine(x1 + originX, y1 + originY, x2 + originX, y2 + originY);
		}
		void drawText(int x, int y, string text) {
			p.drawText(x + originX, y + originY, 100000, 100000, text, 0);
		}
		void setOutlineColor(int r, int g, int b) {
			p.pen = Pen(Color(r,g,b), 1);
		}
		void setFillColor(int r, int g, int b) {
			p.fillColor = Color(r,g,b);
		}
	}

	ScriptableVersion toArsdJsvar() {
		auto sv = new ScriptableVersion;
		sv.p = this.screenPainter.impl;
		sv.originX = this.screenPainter.originX;
		sv.originY = this.screenPainter.originY;
		return sv;
	}

	static WidgetPainter fromJsVar(T)(T t) {
		return WidgetPainter.init;
	}
	// done..........
}


struct Style {
	static struct helper(string m, T) {
		enum method = m;
		T v;

		mixin template MethodOverride(typeof(this) v) {
			mixin("override typeof(v.v) "~v.method~"() { return v.v; }");
		}
	}

	static auto opDispatch(string method, T)(T value) {
		return helper!(method, T)(value);
	}
}

/++
	Implementation detail of the [ControlledBy] UDA.

	History:
		Added Oct 28, 2020
+/
struct ControlledBy_(T, Args...) {
	Args args;

	static if(Args.length)
	this(Args args) {
		this.args = args;
	}

	private T construct(Widget parent) {
		return new T(args, parent);
	}
}

/++
	User-defined attribute you can add to struct members contrlled by [addDataControllerWidget] or [dialog] to tell which widget you want created for them.

	History:
		Added Oct 28, 2020
+/
auto ControlledBy(T, Args...)(Args args) {
	return ControlledBy_!(T, Args)(args);
}

struct ContainerMeta {
	string name;
	ContainerMeta[] children;
	Widget function(Widget parent) factory;

	Widget instantiate(Widget parent) {
		auto n = factory(parent);
		n.name = name;
		foreach(child; children)
			child.instantiate(n);
		return n;
	}
}

/++
	This is a helper for [addDataControllerWidget]. You can use it as a UDA on the type. See
	http://dpldocs.info/this-week-in-d/Blog.Posted_2020_11_02.html for more information.

	Please note that as of May 28, 2021, a dmd bug prevents this from compiling on module-level
	structures. It works fine on structs declared inside functions though.

	See: https://issues.dlang.org/show_bug.cgi?id=21984
+/
template Container(CArgs...) {
	static if(CArgs.length && is(CArgs[0] : Widget)) {
		private alias Super = CArgs[0];
		private alias CArgs2 = CArgs[1 .. $];
	} else {
		private alias Super = Layout;
		private alias CArgs2 = CArgs;
	}

	class Container : Super {
		this(Widget parent) { super(parent); }

		// just to partially support old gdc versions
		version(GNU) {
			static if(CArgs2.length >= 1) { enum tmp0 = CArgs2[0]; mixin typeof(tmp0).MethodOverride!(CArgs2[0]); }
			static if(CArgs2.length >= 2) { enum tmp1 = CArgs2[1]; mixin typeof(tmp1).MethodOverride!(CArgs2[1]); }
			static if(CArgs2.length >= 3) { enum tmp2 = CArgs2[2]; mixin typeof(tmp2).MethodOverride!(CArgs2[2]); }
			static if(CArgs2.length > 3) static assert(0, "only a few overrides like this supported on your compiler version at this time");
		} else mixin(q{
			static foreach(Arg; CArgs2) {
				mixin Arg.MethodOverride!(Arg);
			}
		});

		static ContainerMeta opCall(string name, ContainerMeta[] children...) {
			return ContainerMeta(
				name,
				children.dup,
				function (Widget parent) { return new typeof(this)(parent); }
			);
		}

		static ContainerMeta opCall(ContainerMeta[] children...) {
			return opCall(null, children);
		}
	}
}

/++
	The data controller widget is created by reflecting over the given
	data type. You can use [ControlledBy] as a UDA on a struct or
	just let it create things automatically.

	Unlike [dialog], this uses real-time updating of the data and
	you add it to another window yourself.

	---
		struct Test {
			int x;
			int y;
		}

		auto window = new Window();
		auto dcw = new DataControllerWidget!Test(new Test, window);
	---

	The way it works is any public members are given a widget based
	on their data type, and public methods trigger an action button
	if no relevant parameters or a dialog action if it does have
	parameters, similar to the [menu] facility.

	If you change data programmatically, without going through the
	DataControllerWidget methods, you will have to tell it something
	has changed and it needs to redraw. This is done with the `invalidate`
	method.

	History:
		Added Oct 28, 2020
+/
/// Group: generating_from_code
class DataControllerWidget(T) : WidgetContainer {
	static if(is(T == class) || is(T == interface) || is(T : const E[], E))
		private alias Tref = T;
	else
		private alias Tref = T*;

	Tref datum;

	/++
		See_also: [addDataControllerWidget]
	+/
	this(Tref datum, Widget parent) {
		this.datum = datum;

		Widget cp = this;

		super(parent);

		foreach(attr; __traits(getAttributes, T))
			static if(is(typeof(attr) == ContainerMeta)) {
				cp = attr.instantiate(this);
			}

		auto def = this.getByName("default");
		if(def !is null)
			cp = def;

		Widget helper(string name) {
			auto maybe = this.getByName(name);
			if(maybe is null)
				return cp;
			return maybe;

		}

		foreach(member; __traits(allMembers, T))
		static if(member != "this") // wtf https://issues.dlang.org/show_bug.cgi?id=22011
		static if(is(typeof(__traits(getMember, this.datum, member))))
		static if(__traits(getProtection, __traits(getMember, this.datum, member)) == "public") {
			void delegate() update;

			auto w = widgetFor!(__traits(getMember, T, member))(&__traits(getMember, this.datum, member), helper(member), update);

			if(update)
				updaters ~= update;

			static if(is(typeof(__traits(getMember, this.datum, member)) == function)) {
				w.addEventListener("triggered", delegate() {
					makeAutomaticHandler!(__traits(getMember, this.datum, member))(this.parentWindow, &__traits(getMember, this.datum, member))();
					notifyDataUpdated();
				});
			} else static if(is(typeof(w.isChecked) == bool)) {
				w.addEventListener(EventType.change, (Event ev) {
					__traits(getMember, this.datum, member) = w.isChecked;
				});
			} else static if(is(typeof(w.value) == string) || is(typeof(w.content) == string)) {
				w.addEventListener("change", (Event e) { genericSetValue(&__traits(getMember, this.datum, member), e.stringValue); } );
			} else static if(is(typeof(w.value) == int)) {
				w.addEventListener("change", (Event e) { genericSetValue(&__traits(getMember, this.datum, member), e.intValue); } );
			} else static if(is(typeof(w) == DropDownSelection)) {
				// special case for this to kinda support enums and such. coudl be better though
				w.addEventListener("change", (Event e) { genericSetValue(&__traits(getMember, this.datum, member), e.intValue); } );
			} else {
				//static assert(0, "unsupported type " ~ typeof(__traits(getMember, this.datum, member)).stringof ~ " " ~ typeof(w).stringof);
			}
		}
	}

	/++
		If you modify the data in the structure directly, you need to call this to update the UI and propagate any change messages.

		History:
			Added May 28, 2021
	+/
	void notifyDataUpdated() {
		foreach(updater; updaters)
			updater();

		this.emit!(ChangeEvent!void)(delegate{});
	}

	private Widget[string] memberWidgets;
	private void delegate()[] updaters;

	mixin Emits!(ChangeEvent!void);
}

private int saturatedSum(int[] values...) {
	int sum;
	foreach(value; values) {
		if(value == int.max)
			return int.max;
		sum += value;
	}
	return sum;
}

void genericSetValue(T, W)(T* where, W what) {
	import std.conv;
	*where = to!T(what);
	//*where = cast(T) stringToLong(what);
}

/++
	Creates a widget for the value `tt`, which is pointed to at runtime by `valptr`, with the given parent.

	The `update` delegate can be called if you change `*valptr` to reflect those changes in the widget.

	Note that this creates the widget but does not attach any event handlers to it.
+/
private static auto widgetFor(alias tt, P)(P valptr, Widget parent, out void delegate() update) {

	string displayName = __traits(identifier, tt).beautify;

	static if(controlledByCount!tt == 1) {
		foreach(i, attr; __traits(getAttributes, tt)) {
			static if(is(typeof(attr) == ControlledBy_!(T, Args), T, Args...)) {
				auto w = attr.construct(parent);
				static if(__traits(compiles, w.setPosition(*valptr)))
					update = () { w.setPosition(*valptr); };
				else static if(__traits(compiles, w.setValue(*valptr)))
					update = () { w.setValue(*valptr); };

				if(update)
					update();
				return w;
			}
		}
	} else static if(controlledByCount!tt == 0) {
		static if(is(typeof(tt) == enum)) {
			// FIXME: update
			auto dds = new DropDownSelection(parent);
			foreach(idx, option; __traits(allMembers, typeof(tt))) {
				dds.addOption(option);
				if(__traits(getMember, typeof(tt), option) == *valptr)
					dds.setSelection(cast(int) idx);
			}
			return dds;
		} else static if(is(typeof(tt) == bool)) {
			auto box = new Checkbox(displayName, parent);
			update = () { box.isChecked = *valptr; };
			update();
			return box;
		} else static if(is(typeof(tt) : const long)) {
			auto le = new LabeledLineEdit(displayName, parent);
			update = () { le.content = toInternal!string(*valptr); };
			update();
			return le;
		} else static if(is(typeof(tt) : const double)) {
			auto le = new LabeledLineEdit(displayName, parent);
			import std.conv;
			update = () { le.content = to!string(*valptr); };
			update();
			return le;
		} else static if(is(typeof(tt) : const string)) {
			auto le = new LabeledLineEdit(displayName, parent);
			update = () { le.content = *valptr; };
			update();
			return le;
		} else static if(is(typeof(tt) == E[], E)) {
			auto w = new ArrayEditingWidget!E(parent);
			// FIXME update
			return w;
		} else static if(is(typeof(tt) == function)) {
			auto w = new Button(displayName, parent);
			return w;
		} else static if(is(typeof(tt) == class) || is(typeof(tt) == interface)) {
			return parent.addDataControllerWidget(tt);
		} else static assert(0, typeof(tt).stringof);
	} else static assert(0, "multiple controllers not yet supported");
}

class ArrayEditingWidget(T) : ArrayEditingWidgetBase {
	this(Widget parent) {
		super(parent);
	}
}

class ArrayEditingWidgetBase : Widget {
	this(Widget parent) {
		super(parent);

		// FIXME: a trash can to move items into to delete them?
		static class MyListViewItem : GenericListViewItem {
			this(Widget parent) {
				super(parent);

				/+
					drag handle
						left click lets you move the whole selection. if the current element is not selected, it changes the selection to it.
						right click here gives you the movement controls too
					index/key view zone
						left click here selects/unselects
					element view/edit zone
					delete button
				+/

				// FIXME: make sure the index is viewable

				auto hl = new HorizontalLayout(this);

				button = new CommandButton("d", hl);

				label = new TextLabel("unloaded", TextAlignment.Left, hl);
				// if member editable, have edit view... get from the subclass.

				// or a "..." menu?
				button = new CommandButton("Up", hl); // shift+click is move to top
				button = new CommandButton("Down", hl); // shift+click is move to bottom
				button = new CommandButton("Move to", hl); // move before, after, or swap
				button = new CommandButton("Delete", hl);

				button.addEventListener("triggered", delegate(){
					//messageBox(text("clicked ", currentIndexLoaded()));
				});
			}
			override void showItem(int idx) {
				label.label = "Item ";// ~ to!string(idx);
			}

			TextLabel label;
			Button button;
		}

		auto outer_this = this;

		// FIXME: make sure item count is easy to see

		glvw = new class GenericListViewWidget {
			this() {
				super(outer_this);
			}
			override GenericListViewItem itemFactory(Widget parent) {
				return new MyListViewItem(parent);
			}
			override Size itemSize() {
				return Size(0, scaleWithDpi(80));
			}

			override Menu contextMenu(int x, int y) {
				return createContextMenuFromAnnotatedCode(this);
			}

			@context_menu {
				void Select_All() {

				}

				void Undo() {

				}

				void Redo() {

				}

				void Cut() {

				}

				void Copy() {

				}

				void Paste() {

				}

				void Delete() {

				}

				void Find() {

				}
			}
		};

		glvw.setItemCount(400);

		auto hl = new HorizontalLayout(this);
		add = new FreeEntrySelection(hl);
		addButton = new Button("Add", hl);
	}

	GenericListViewWidget glvw;
	ComboboxBase add;
	Button addButton;
	/+
		Controls:
			clear (select all / delete)
			reset (confirmation blocked button, maybe only on the whole form? or hit undo so many times to get back there)
			add item
				palette of options to add to the array (add prolly a combo box)
			rearrange - move up/down, drag and drop a selection? right click can always do, left click only drags when on a selection handle.
			edit/input/view items (GLVW? or it could be a table view in a way.)
			undo/redo
			select whole elements (even if a struct)
			cut/copy/paste elements

			could have an element picker, a details pane, and an add bare?


			put a handle on the elements for left click dragging. allow right click drag anywhere but pretty big wiggle until it enables.
			left click and drag should never work for plain text, i more want to change selection there and there no room to put a handle on it.
			the handle should let dragging w/o changing the selection, or if part of the selection, drag the whole selection i think.
			make it textured and use the grabby hand mouse cursor.
	+/
}

/++
	A button that pops up a menu on click for working on a particular item or selection.

	History:
		Added March 23, 2025
+/
class MenuPopupButton : Button {
	/++
		You might consider using [createContextMenuFromAnnotatedCode] to populate the `menu` argument.

		You also may want to set the [prepare] delegate after construction.
	+/
	this(Menu menu, Widget parent) {
		assert(menu !is null);

		this.menu = menu;
		super("...", parent);
	}

	private Menu menu;
	/++
		If set, this delegate is called before popping up the window. This gives you a chance
		to prepare your dynamic data structures for the element(s) selected.

		For example, if your `MenuPopupButton` is attached to a [GenericListViewItem], you can call
		[GenericListViewItem.currentIndexLoaded] in here and set it to a variable in the object you
		called [createContextMenuFromAnnotatedCode] to apply the operation to the right object.

		(The api could probably be simpler...)
	+/
	void delegate() prepare;

	override void defaultEventHandler_triggered(scope Event e) {
		if(prepare)
			prepare();
		showContextMenu(this.x, this.y + this.height, -2, -2, menu);
	}

	override int maxHeight() {
		return defaultLineHeight;
	}

	override int maxWidth() {
		return defaultLineHeight;
	}
}

/++
	A button that pops up an information box, similar to a tooltip, but explicitly triggered.

	FIXME: i want to be able to easily embed these in other things too.
+/
class TipPopupButton : Button {
	/++
	+/
	this(Widget delegate(Widget p) factory, Widget parent) {
		this.factory = factory;
		super("?", parent);
	}

	private Widget delegate(Widget p) factory;

	override void defaultEventHandler_triggered(scope Event e) {
		auto window = new TooltipWindow(factory, this);
		window.popup(this);
	}
}

/++
	History:
		Added March 23, 2025
+/
class TooltipWindow : Window {
	void popup(Widget parent, int offsetX = 0, int offsetY = int.min) {
		/+
		this.menuParent = parent;

		previouslyFocusedWidget = parent.parentWindow.focusedWidget;
		previouslyFocusedWidgetBelongsIn = &parent.parentWindow.focusedWidget;
		parent.parentWindow.focusedWidget = this;

		int w = 150;
		int h = paddingTop + paddingBottom;
		if(this.children.length) {
			// hacking it to get the ideal height out of recomputeChildLayout
			this.width = w;
			this.height = h;
			this.recomputeChildLayoutEntry();
			h = this.children[$-1].y + this.children[$-1].height + this.children[$-1].marginBottom;
			h += paddingBottom;

			h -= 2; // total hack, i just like the way it looks a bit tighter even though technically MenuItem reserves some space to center in normal circumstances
		}
		+/

		if(offsetY == int.min)
			offsetY = parent.defaultLineHeight;

		int w = 150;
		int h = 50;

		auto coord = parent.globalCoordinates();
		dropDown.moveResize(coord.x + offsetX, coord.y + offsetY, w, h);

		static if(UsingSimpledisplayX11)
			XSync(XDisplayConnection.get, 0);

		dropDown.visibilityChanged = (bool visible) {
			if(visible) {
				this.redraw();
				dropDown.grabInput();
			} else {
				dropDown.releaseInputGrab();
			}
		};

		dropDown.show();

		clickListener = this.addEventListener((scope ClickEvent ev) {
			unpopup();
			// need to unlock asap just in case other user handlers block...
			static if(UsingSimpledisplayX11)
				flushGui();
		}, true /* again for asap action */);
	}

	private EventListener clickListener;

	void unpopup() {
		mouseLastOver = mouseLastDownOn = null;
		dropDown.hide();
		clickListener.disconnect();
	}

	private SimpleWindow dropDown;
	private Widget child;

	///
	this(Widget delegate(Widget p) factory, Widget parent) {
		assert(parent);
		assert(parent.parentWindow);
		assert(parent.parentWindow.win);
		dropDown = new SimpleWindow(
			250, 40,
			null, OpenGlOptions.no, Resizability.fixedSize,
			WindowTypes.tooltip,
			WindowFlags.dontAutoShow,
			parent ? parent.parentWindow.win : null
		);

		super(dropDown);

		child = factory(this);
	}
}

private template controlledByCount(alias tt) {
	static int helper() {
		int count;
		foreach(i, attr; __traits(getAttributes, tt))
			static if(is(typeof(attr) == ControlledBy_!(T, Args), T, Args...))
				count++;
		return count;
	}

	enum controlledByCount = helper;
}

/++
	Intended for UFCS action like `window.addDataControllerWidget(new MyObject());`

	If you provide a `redrawOnChange` widget, it will automatically register a change event handler that calls that widget's redraw method.

	History:
		The `redrawOnChange` parameter was added on May 28, 2021.
+/
DataControllerWidget!T addDataControllerWidget(T)(Widget parent, T t, Widget redrawOnChange = null) if(is(T == class) || is(T == interface)) {
	auto dcw = new DataControllerWidget!T(t, parent);
	initializeDataControllerWidget(dcw, redrawOnChange);
	return dcw;
}

/// ditto
DataControllerWidget!T addDataControllerWidget(T)(Widget parent, T* t, Widget redrawOnChange = null) if(is(T == struct)) {
	auto dcw = new DataControllerWidget!T(t, parent);
	initializeDataControllerWidget(dcw, redrawOnChange);
	return dcw;
}

private void initializeDataControllerWidget(Widget w, Widget redrawOnChange) {
	if(redrawOnChange !is null)
		w.addEventListener("change", delegate() { redrawOnChange.redraw(); });
}

/++
	Get this through [Widget.getComputedStyle]. It provides access to the [Widget.Style] style hints and [Widget] layout hints, possibly modified through the [VisualTheme], through a unifed interface.

	History:
		Finalized on June 3, 2021 for the dub v10.0 release
+/
struct StyleInformation {
	private Widget w;
	private BaseVisualTheme visualTheme;

	private this(Widget w) {
		this.w = w;
		this.visualTheme = WidgetPainter.visualTheme;
	}

	/++
		Forwards to [Widget.Style]

		Bugs:
			It is supposed to fall back to the [VisualTheme] if
			the style doesn't override the default, but that is
			not generally implemented. Many of them may end up
			being explicit overloads instead of the generic
			opDispatch fallback, like [font] is now.
	+/
	public @property opDispatch(string name)() {
		typeof(__traits(getMember, Widget.Style.init, name)()) prop;
		w.useStyleProperties((scope Widget.Style props) {
		//visualTheme.useStyleProperties(w, (props) {
			prop = __traits(getMember, props, name);
		});
		return prop;
	}

	/++
		Returns the cached font object associated with the widget,
		if overridden by the [Widget.Style|Style], or the [VisualTheme] if not.

		History:
			Prior to March 21, 2022 (dub v10.7), `font` went through
			[opDispatch], which did not use the cache. You can now call it
			repeatedly without guilt.
	+/
	public @property OperatingSystemFont font() {
		OperatingSystemFont prop;
		w.useStyleProperties((scope Widget.Style props) {
			prop = props.fontCached;
		});
		if(prop is null) {
			prop = visualTheme.defaultFontCached(w.currentDpi);
		}
		return prop;
	}

	@property {
		// Layout helpers. Currently just forwarding since I haven't made up my mind on a better way.
		/** */ int paddingLeft() { return w.paddingLeft(); }
		/** */ int paddingRight() { return w.paddingRight(); }
		/** */ int paddingTop() { return w.paddingTop(); }
		/** */ int paddingBottom() { return w.paddingBottom(); }

		/** */ int marginLeft() { return w.marginLeft(); }
		/** */ int marginRight() { return w.marginRight(); }
		/** */ int marginTop() { return w.marginTop(); }
		/** */ int marginBottom() { return w.marginBottom(); }

		/** */ int maxHeight() { return w.maxHeight(); }
		/** */ int minHeight() { return w.minHeight(); }

		/** */ int maxWidth() { return w.maxWidth(); }
		/** */ int minWidth() { return w.minWidth(); }

		/** */ int flexBasisWidth() { return w.flexBasisWidth(); }
		/** */ int flexBasisHeight() { return w.flexBasisHeight(); }

		/** */ int heightStretchiness() { return w.heightStretchiness(); }
		/** */ int widthStretchiness() { return w.widthStretchiness(); }

		/** */ int heightShrinkiness() { return w.heightShrinkiness(); }
		/** */ int widthShrinkiness() { return w.widthShrinkiness(); }

		// Global helpers some of these are unstable.
		static:
		/** */ Color windowBackgroundColor() { return WidgetPainter.visualTheme.windowBackgroundColor(); }
		/** */ Color widgetBackgroundColor() { return WidgetPainter.visualTheme.widgetBackgroundColor(); }
		/** */ Color lightAccentColor() { return WidgetPainter.visualTheme.lightAccentColor(); }
		/** */ Color darkAccentColor() { return WidgetPainter.visualTheme.darkAccentColor(); }
		/** */ Color selectionForegroundColor() { return WidgetPainter.visualTheme.selectionForegroundColor(); }
		/** */ Color selectionBackgroundColor() { return WidgetPainter.visualTheme.selectionBackgroundColor(); }

		/** */ Color activeTabColor() { return lightAccentColor; }
		/** */ Color buttonColor() { return windowBackgroundColor; }
		/** */ Color depressedButtonColor() { return darkAccentColor; }
		/** the background color of the widget when mouse hovering over it, if it responds to mouse hovers */ Color hoveringColor() { return lightAccentColor; }
		deprecated("Use selectionForegroundColor and selectionBackgroundColor instead") Color activeListXorColor() {
			auto c = WidgetPainter.visualTheme.selectionColor();
			return Color(c.r ^ 255, c.g ^ 255, c.b ^ 255, c.a);
		}
		/** */ Color progressBarColor() { return WidgetPainter.visualTheme.selectionBackgroundColor(); }
		/** */ Color activeMenuItemColor() { return WidgetPainter.visualTheme.selectionBackgroundColor(); }
	}



	/+

	private static auto extractStyleProperty(string name)(Widget w) {
		typeof(__traits(getMember, Widget.Style.init, name)()) prop;
		w.useStyleProperties((props) {
			prop = __traits(getMember, props, name);
		});
		return prop;
	}

	// FIXME: clear this upon a X server disconnect
	private static OperatingSystemFont[string] fontCache;

	T getProperty(T)(string name, lazy T default_) {
		if(visualTheme !is null) {
			auto str = visualTheme.getPropertyString(w, name);
			if(str is null)
				return default_;
			static if(is(T == Color))
				return Color.fromString(str);
			else static if(is(T == Measurement))
				return Measurement(cast(int) toInternal!int(str));
			else static if(is(T == WidgetBackground))
				return WidgetBackground.fromString(str);
			else static if(is(T == OperatingSystemFont)) {
				if(auto f = str in fontCache)
					return *f;
				else
					return fontCache[str] = new OperatingSystemFont(str);
			} else static if(is(T == FrameStyle)) {
				switch(str) {
					default:
						return FrameStyle.none;
					foreach(style; __traits(allMembers, FrameStyle))
					case style:
						return __traits(getMember, FrameStyle, style);
				}
			} else static assert(0);
		} else
			return default_;
	}

	static struct Measurement {
		int value;
		alias value this;
	}

	@property:

	int paddingLeft() { return getProperty("padding-left", Measurement(w.paddingLeft())); }
	int paddingRight() { return getProperty("padding-right", Measurement(w.paddingRight())); }
	int paddingTop() { return getProperty("padding-top", Measurement(w.paddingTop())); }
	int paddingBottom() { return getProperty("padding-bottom", Measurement(w.paddingBottom())); }

	int marginLeft() { return getProperty("margin-left", Measurement(w.marginLeft())); }
	int marginRight() { return getProperty("margin-right", Measurement(w.marginRight())); }
	int marginTop() { return getProperty("margin-top", Measurement(w.marginTop())); }
	int marginBottom() { return getProperty("margin-bottom", Measurement(w.marginBottom())); }

	int maxHeight() { return getProperty("max-height", Measurement(w.maxHeight())); }
	int minHeight() { return getProperty("min-height", Measurement(w.minHeight())); }

	int maxWidth() { return getProperty("max-width", Measurement(w.maxWidth())); }
	int minWidth() { return getProperty("min-width", Measurement(w.minWidth())); }


	WidgetBackground background() { return getProperty("background", extractStyleProperty!"background"(w)); }
	Color foregroundColor() { return getProperty("foreground-color", extractStyleProperty!"foregroundColor"(w)); }

	OperatingSystemFont font() { return getProperty("font", extractStyleProperty!"fontCached"(w)); }

	FrameStyle borderStyle() { return getProperty("border-style", extractStyleProperty!"borderStyle"(w)); }
	Color borderColor() { return getProperty("border-color", extractStyleProperty!"borderColor"(w)); }

	FrameStyle outlineStyle() { return getProperty("outline-style", extractStyleProperty!"outlineStyle"(w)); }
	Color outlineColor() { return getProperty("outline-color", extractStyleProperty!"outlineColor"(w)); }


	Color windowBackgroundColor() { return WidgetPainter.visualTheme.windowBackgroundColor(); }
	Color widgetBackgroundColor() { return WidgetPainter.visualTheme.widgetBackgroundColor(); }
	Color lightAccentColor() { return WidgetPainter.visualTheme.lightAccentColor(); }
	Color darkAccentColor() { return WidgetPainter.visualTheme.darkAccentColor(); }

	Color activeTabColor() { return lightAccentColor; }
	Color buttonColor() { return windowBackgroundColor; }
	Color depressedButtonColor() { return darkAccentColor; }
	Color hoveringColor() { return Color(228, 228, 228); }
	Color activeListXorColor() {
		auto c = WidgetPainter.visualTheme.selectionColor();
		return Color(c.r ^ 255, c.g ^ 255, c.b ^ 255, c.a);
	}
	Color progressBarColor() { return WidgetPainter.visualTheme.selectionColor(); }
	Color activeMenuItemColor() { return WidgetPainter.visualTheme.selectionColor(); }
	+/
}



// pragma(msg, __traits(classInstanceSize, Widget));

/*private*/ template EventString(E) {
	static if(is(typeof(E.EventString)))
		enum EventString = E.EventString;
	else
		enum EventString = E.mangleof; // FIXME fqn? or something more user friendly
}

/*private*/ template EventStringIdentifier(E) {
	string helper() {
		auto es = EventString!E;
		char[] id = new char[](es.length * 2);
		size_t idx;
		foreach(char ch; es) {
			id[idx++] = cast(char)('a' + (ch >> 4));
			id[idx++] = cast(char)('a' + (ch & 0x0f));
		}
		return cast(string) id;
	}

	enum EventStringIdentifier = helper();
}


template classStaticallyEmits(This, EventType) {
	static if(is(This Base == super))
		static if(is(Base : Widget))
			enum baseEmits = classStaticallyEmits!(Base, EventType);
		else
			enum baseEmits = false;
	else
		enum baseEmits = false;

	enum thisEmits = is(typeof(__traits(getMember, This, "emits_" ~ EventStringIdentifier!EventType)) == EventType[0]);

	enum classStaticallyEmits = thisEmits || baseEmits;
}

/++
	A helper to make widgets out of other native windows.

	History:
		Factored out of OpenGlWidget on November 5, 2021
+/
class NestedChildWindowWidget : Widget {
	SimpleWindow win;

	/++
		Used on X to send focus to the appropriate child window when requested by the window manager.

		Normally returns its own nested window. Can also return another child or null to revert to the parent
		if you override it in a child class.

		History:
			Added April 2, 2022 (dub v10.8)
	+/
	SimpleWindow focusableWindow() {
		return win;
	}

	///
	// win = new SimpleWindow(640, 480, null, OpenGlOptions.yes, Resizability.automaticallyScaleIfPossible, WindowTypes.nestedChild, WindowFlags.normal, getParentWindow(parent));
	this(SimpleWindow win, Widget parent) {
		this.parentWindow = parent.parentWindow;
		this.win = win;

		super(parent);
		windowsetup(win);
	}

	static protected SimpleWindow getParentWindow(Widget parent) {
		assert(parent !is null);
		SimpleWindow pwin = parent.parentWindow.win;

		version(win32_widgets) {
			HWND phwnd;
			auto wtf = parent;
			while(wtf) {
				if(wtf.hwnd) {
					phwnd = wtf.hwnd;
					break;
				}
				wtf = wtf.parent;
			}
			// kinda a hack here just because the ctor below just needs a SimpleWindow wrapper....
			if(phwnd)
				pwin = new SimpleWindow(phwnd);
		}

		return pwin;
	}

	/++
		Called upon the nested window being destroyed.
		Remember the window has already been destroyed at
		this point, so don't use the native handle for anything.

		History:
			Added April 3, 2022 (dub v10.8)
	+/
	protected void dispose() {

	}

	protected void windowsetup(SimpleWindow w) {
		/*
		win.onFocusChange = (bool getting) {
			if(getting)
				this.focus();
		};
		*/

		/+
		win.onFocusChange = (bool getting) {
			if(getting) {
				this.parentWindow.focusedWidget = this;
				this.emit!FocusEvent();
				this.emit!FocusInEvent();
			} else {
				this.emit!BlurEvent();
				this.emit!FocusOutEvent();
			}
		};
		+/

		win.onDestroyed = () {
			this.dispose();
		};

		version(win32_widgets) {
			Widget.nativeMapping[win.hwnd] = this;
			this.originalWindowProcedure = cast(WNDPROC) SetWindowLongPtr(win.hwnd, GWL_WNDPROC, cast(size_t) &HookedWndProc);
		} else {
			win.setEventHandlers(
				(MouseEvent e) {
					Widget p = this;
					while(p ! is parentWindow) {
						e.x += p.x;
						e.y += p.y;
						p = p.parent;
					}
					parentWindow.dispatchMouseEvent(e);
				},
				(KeyEvent e) {
					//writefln("%s %x   %s", cast(void*) win, cast(uint) e.key, e.key);
					parentWindow.dispatchKeyEvent(e);
				},
				(dchar e) {
					parentWindow.dispatchCharEvent(e);
				},
			);
		}

	}

	override bool showOrHideIfNativeWindow(bool shouldShow) {
		auto cur = hidden;
		win.hidden = !shouldShow;
		if(cur != shouldShow && shouldShow)
			redraw();
		return true;
	}

	/// OpenGL widgets cannot have child widgets. Do not call this.
	/* @disable */ final override void addChild(Widget, int) {
		throw new Error("cannot add children to OpenGL widgets");
	}

	/// When an opengl widget is laid out, it will adjust the glViewport for you automatically.
	/// Keep in mind that events like mouse coordinates are still relative to your size.
	override void registerMovement() {
		// writefln("%d %d %d %d", x,y,width,height);
		version(win32_widgets)
			auto pos = getChildPositionRelativeToParentHwnd(this);
		else
			auto pos = getChildPositionRelativeToParentOrigin(this);
		win.moveResize(pos[0], pos[1], width, height);

		registerMovementAdditionalWork();
		sendResizeEvent();
	}

	abstract void registerMovementAdditionalWork();
}

/++
	Nests an opengl capable window inside this window as a widget.

	You may also just want to create an additional [SimpleWindow] with
	[OpenGlOptions.yes] yourself.

	An OpenGL widget cannot have child widgets. It will throw if you try.
+/
static if(OpenGlEnabled)
class OpenGlWidget : NestedChildWindowWidget {

	override void registerMovementAdditionalWork() {
		win.setAsCurrentOpenGlContext();
	}

	///
	this(Widget parent) {
		auto win = new SimpleWindow(640, 480, null, OpenGlOptions.yes, Resizability.automaticallyScaleIfPossible, WindowTypes.nestedChild, WindowFlags.normal, getParentWindow(parent));
		super(win, parent);
	}

	override void paint(WidgetPainter painter) {
		win.setAsCurrentOpenGlContext();
		glViewport(0, 0, this.width, this.height);
		win.redrawOpenGlSceneNow();
	}

	void redrawOpenGlScene(void delegate() dg) {
		win.redrawOpenGlScene = dg;
	}
}

/++
	This demo shows how to draw text in an opengl scene.
+/
unittest {
	import arsd.minigui;
	import arsd.ttf;

	void main() {
		auto window = new Window();

		auto widget = new OpenGlWidget(window);

		// old means non-shader code so compatible with glBegin etc.
		// tbh I haven't implemented new one in font yet...
		// anyway, declaring here, will construct soon.
		OpenGlLimitedFont!(OpenGlFontGLVersion.old) glfont;

		// this is a little bit awkward, calling some methods through
		// the underlying SimpleWindow `win` method, and you can't do this
		// on a nanovega widget due to conflicts so I should probably fix
		// the api to be a bit easier. But here it will work.
		//
		// Alternatively, you could load the font on the first draw, inside
		// the redrawOpenGlScene, and keep a flag so you don't do it every
		// time. That'd be a bit easier since the lib sets up the context
		// by then guaranteed.
		//
		// But still, I wanna show this.
		widget.win.visibleForTheFirstTime = delegate {
			// must set the opengl context
			widget.win.setAsCurrentOpenGlContext();

			// if you were doing a OpenGL 3+ shader, this
			// gets especially important to do in order. With
			// old-style opengl, I think you can even do it
			// in main(), but meh, let's show it more correctly.

			// Anyway, now it is time to load the font from the
			// OS (you can alternatively load one from a .ttf file
			// you bundle with the application), then load the
			// font into texture for drawing.

			auto osfont = new OperatingSystemFont("DejaVu Sans", 18);

			assert(!osfont.isNull()); // make sure it actually loaded

			// using typeof to avoid repeating the long name lol
			glfont = new typeof(glfont)(
				// get the raw data from the font for loading in here
				// since it doesn't use the OS function to draw the
				// text, we gotta treat it more as a file than as
				// a drawing api.
				osfont.getTtfBytes(),
				18, // need to respecify size since opengl world is different coordinate system

				// these last two numbers are why it is called
				// "Limited" font. It only loads the characters
				// in the given range, since the texture atlas
				// it references is all a big image generated ahead
				// of time. You could maybe do the whole thing but
				// idk how much memory that is.
				//
				// But here, 0-128 represents the ASCII range, so
				// good enough for most English things, numeric labels,
				// etc.
				0,
				128
			);
		};

		widget.redrawOpenGlScene = () {
			// now we can use the glfont's drawString function

			// first some opengl setup. You can do this in one place
			// on window first visible too in many cases, just showing
			// here cuz it is easier for me.

			// gonna need some alpha blending or it just looks awful
			glEnable(GL_BLEND);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			glClearColor(0,0,0,0);
			glDepthFunc(GL_LEQUAL);

			// Also need to enable 2d textures, since it draws the
			// font characters as images baked in
			glMatrixMode(GL_MODELVIEW);
			glLoadIdentity();
			glDisable(GL_DEPTH_TEST);
			glEnable(GL_TEXTURE_2D);

			// the orthographic matrix is best for 2d things like text
			// so let's set that up. This matrix makes the coordinates
			// in the opengl scene be one-to-one with the actual pixels
			// on screen. (Not necessarily best, you may wish to scale
			// things, but it does help keep fonts looking normal.)
			glMatrixMode(GL_PROJECTION);
			glLoadIdentity();
			glOrtho(0, widget.width, widget.height, 0, 0, 1);

			// you can do other glScale, glRotate, glTranslate, etc
			// to the matrix here of course if you want.

			// note the x,y coordinates here are for the text baseline
			// NOT the upper-left corner. The baseline is like the line
			// in the notebook you write on. Most the letters are actually
			// above it, but some, like p and q, dip a bit below it.
			//
			// So if you're used to the upper left coordinate like the
			// rest of simpledisplay/minigui usually do, do the
			// y + glfont.ascent to bring it down a little. So this
			// example puts the string in the upper left of the window.
			glfont.drawString(0, 0 + glfont.ascent, "Hello!!", Color.green);

			// re color btw: the function sets a solid color internally,
			// but you actually COULD do your own thing for rainbow effects
			// and the sort if you wanted too, by pulling its guts out.
			// Just view its source for an idea of how it actually draws:
			// http://arsd-official.dpldocs.info/source/arsd.ttf.d.html#L332

			// it gets a bit complicated with the character positioning,
			// but the opengl parts are fairly simple: bind a texture,
			// set the color, draw a quad for each letter.


			// the last optional argument there btw is a bounding box
			// it will/ use to word wrap and return an object you can
			// use to implement scrolling or pagination; it tells how
			// much of the string didn't fit in the box. But for simple
			// labels we can just ignore that.


			// I'd suggest drawing text as the last step, after you
			// do your other drawing. You might use the push/pop matrix
			// stuff to keep your place. You, in theory, should be able
			// to do text in a 3d space but I've never actually tried
			// that....
		};

		window.loop();
	}
}

version(custom_widgets)
private class TextListViewWidget : GenericListViewWidget {
	static class TextListViewItem : GenericListViewItem {
		ListWidget controller;
		this(ListWidget controller, Widget parent) {
			this.controller = controller;
			this.tabStop = false;
			super(parent);
		}

		ListWidget.Option* showing;

		override void showItem(int idx) {
			showing = idx < controller.options.length ? &controller.options[idx] : null;
			redraw(); // is this necessary? the generic thing might call it...
		}

		override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
			if(showing is null)
				return bounds;
			painter.drawText(bounds.upperLeft, showing.label);
			return bounds;
		}

		static class Style : Widget.Style {
			override WidgetBackground background() {
				// FIXME: change it if it is focused or not
				// needs to reliably detect if focused (noting the actual focus may be on a parent or child... or even sibling for FreeEntrySelection. maybe i just need a better way to proxy focus in widgets generically). also will need to redraw correctly without defaultEventHandler_focusin hacks like EditableTextWidget uses
				auto tlvi = cast(TextListViewItem) widget;
				if(tlvi && tlvi.showing && tlvi && tlvi.showing.selected)
					return WidgetBackground(true /*widget.parent.isFocused*/ ? WidgetPainter.visualTheme.selectionBackgroundColor : Color(128, 128, 128)); // FIXME: don't hardcode
				return super.background();
			}

			override Color foregroundColor() {
				auto tlvi = cast(TextListViewItem) widget;
				return tlvi && tlvi.showing && tlvi && tlvi.showing.selected ? WidgetPainter.visualTheme.selectionForegroundColor : super.foregroundColor();
			}

			override FrameStyle outlineStyle() {
				// FIXME: change it if it is focused or not
				auto tlvi = cast(TextListViewItem) widget;
				return (tlvi && tlvi.currentIndexLoaded() == tlvi.controller.focusOn) ? FrameStyle.dotted : super.outlineStyle();
			}
		}
		mixin OverrideStyle!Style;

		mixin Padding!q{2};

		override void defaultEventHandler_click(ClickEvent event) {
			if(event.button == MouseButton.left) {
				controller.setSelection(currentIndexLoaded());
				controller.focusOn = currentIndexLoaded();
			}
		}

	}

	ListWidget controller;

	this(ListWidget parent) {
		this.controller = parent;
		this.tabStop = false; // this is only used as a child of the ListWidget
		super(parent);

		smw.movementPerButtonClick(1, itemSize().height);
	}

	override Size itemSize() {
		return Size(0, defaultLineHeight + scaleWithDpi(4 /* the top and bottom padding */));
	}

	override GenericListViewItem itemFactory(Widget parent) {
		return new TextListViewItem(controller, parent);
	}

	static class Style : Widget.Style {
		override FrameStyle borderStyle() {
			return FrameStyle.sunk;
		}

		override WidgetBackground background() {
			return WidgetBackground(WidgetPainter.visualTheme.widgetBackgroundColor);
		}
	}
	mixin OverrideStyle!Style;
}

/++
	A list widget contains a list of strings that the user can examine and select.


	In the future, items in the list may be possible to be more than just strings.

	See_Also:
		[TableView]
+/
class ListWidget : Widget {
	/// Sends a change event when the selection changes, but the data is not attached to the event. You must instead loop the options to see if they are selected.
	mixin Emits!(ChangeEvent!void);

	version(custom_widgets)
		TextListViewWidget glvw;

	static struct Option {
		string label;
		bool selected;
		void* tag;
	}
	private Option[] options;

	/++
		Sets the current selection to the `y`th item in the list. Will emit [ChangeEvent] when complete.
	+/
	void setSelection(int y) {
		if(!multiSelect)
			foreach(ref opt; options)
				opt.selected = false;
		if(y >= 0 && y < options.length)
			options[y].selected = !options[y].selected;

		version(custom_widgets)
			focusOn = y;

		this.emit!(ChangeEvent!void)(delegate {});

		version(custom_widgets)
			redraw();
	}

	/++
		Gets the index of the selected item. In case of multi select, the index of the first selected item is returned.
		Returns -1 if nothing is selected.
	+/
	int getSelection()
	{
		foreach(i, opt; options) {
			if (opt.selected)
				return cast(int) i;
		}
		return -1;
	}

	version(custom_widgets)
	private int focusOn;

	this(Widget parent) {
		super(parent);

		version(custom_widgets)
			glvw = new TextListViewWidget(this);

		version(win32_widgets)
			createWin32Window(this, WC_LISTBOX, "",
				0|WS_CHILD|WS_VISIBLE|LBS_NOTIFY, 0);
	}

	version(win32_widgets)
	override void handleWmCommand(ushort code, ushort id) {
		switch(code) {
			case LBN_SELCHANGE:
				auto sel = SendMessageW(hwnd, LB_GETCURSEL, 0, 0);
				setSelection(cast(int) sel);
			break;
			default:
		}
	}


	void addOption(string text, void* tag = null) {
		options ~= Option(text, false, tag);
		version(win32_widgets) {
			WCharzBuffer buffer = WCharzBuffer(text);
			SendMessageW(hwnd, LB_ADDSTRING, 0, cast(LPARAM) buffer.ptr);
		}
		version(custom_widgets) {
			glvw.setItemCount(cast(int) options.length);
			//setContentSize(width, cast(int) (options.length * defaultLineHeight));
			redraw();
		}
	}

	void clear() {
		options = null;
		version(win32_widgets) {
			while(SendMessageW(hwnd, LB_DELETESTRING, 0, 0) > 0)
				{}

		} else version(custom_widgets) {
			focusOn = -1;
			glvw.setItemCount(0);
			redraw();
		}
	}

	version(custom_widgets)
	override void defaultEventHandler_keydown(KeyDownEvent kde) {
		void changedFocusOn() {
			scrollFocusIntoView();
			if(multiSelect)
				redraw();
			else
				setSelection(focusOn);
		}
		switch(kde.key) {
			case Key.Up:
				if(focusOn) {
					focusOn--;
					changedFocusOn();
				}
			break;
			case Key.Down:
				if(focusOn + 1 < options.length) {
					focusOn++;
					changedFocusOn();
				}
			break;
			case Key.Home:
				if(focusOn) {
					focusOn = 0;
					changedFocusOn();
				}
			break;
			case Key.End:
				if(options.length && focusOn + 1 != options.length) {
					focusOn = cast(int) options.length - 1;
					changedFocusOn();
				}
			break;
			case Key.PageUp:
				auto n = glvw.numberOfCurrentlyFullyVisibleItems;
				focusOn -= n;
				if(focusOn < 0)
					focusOn = 0;
				changedFocusOn();
			break;
			case Key.PageDown:
				if(options.length == 0)
					break;
				auto n = glvw.numberOfCurrentlyFullyVisibleItems;
				focusOn += n;
				if(focusOn >= options.length)
					focusOn = cast(int) options.length - 1;
				changedFocusOn();
			break;

			default:
		}
	}

	version(custom_widgets)
	override void defaultEventHandler_char(CharEvent ce) {
		if(ce.character == '\n' || ce.character == ' ') {
			setSelection(focusOn);
		} else {
			// search for the item that best matches and jump to it
			// FIXME this sucks in tons of ways. the normal thing toolkits
			// do here is to search for a substring on a timer, but i'd kinda
			// rather make an actual little dialog with some options. still meh for now.
			dchar search = ce.character;
			if(search >= 'A' && search <= 'Z')
				search += 32;
			foreach(idx, option; options) {
				auto ch = option.label.length ? option.label[0] : 0;
				if(ch >= 'A' && ch <= 'Z')
					ch += 32;
				if(ch == search) {
					setSelection(cast(int) idx);
					scrollSelectionIntoView();
					break;
				}
			}

		}
	}

	version(win32_widgets)
		enum multiSelect = false; /// not implemented yet
	else
		bool multiSelect;

	override int heightStretchiness() { return 6; }

	version(custom_widgets)
	void scrollFocusIntoView() {
		glvw.ensureItemVisibleInScroll(focusOn);
	}

	void scrollSelectionIntoView() {
		// FIXME: implement on Windows

		version(custom_widgets)
			glvw.ensureItemVisibleInScroll(getSelection());
	}

	/*
	version(custom_widgets)
	override void defaultEventHandler_focusout(Event foe) {
		glvw.redraw();
	}

	version(custom_widgets)
	override void defaultEventHandler_focusin(Event foe) {
		glvw.redraw();
	}
	*/

}



/// For [ScrollableWidget], determines when to show the scroll bar to the user.
/// NEVER USED
enum ScrollBarShowPolicy {
	automatic, /// automatically show the scroll bar if it is necessary
	never, /// never show the scroll bar (scrolling must be done programmatically)
	always /// always show the scroll bar, even if it is disabled
}

/++
	A widget that tries (with, at best, limited success) to offer scrolling that is transparent to the inner.

	It isn't very good and will very likely be removed. Try [ScrollMessageWidget] or [ScrollableContainerWidget] instead for new code.
+/
// FIXME ScrollBarShowPolicy
// FIXME: use the ScrollMessageWidget in here now that it exists
deprecated("Use ScrollMessageWidget or ScrollableContainerWidget instead") // ugh compiler won't let me do it
class ScrollableWidget : Widget {
	// FIXME: make line size configurable
	// FIXME: add keyboard controls
	version(win32_widgets) {
		override int hookedWndProc(UINT msg, WPARAM wParam, LPARAM lParam) {
			if(msg == WM_VSCROLL || msg == WM_HSCROLL) {
				auto pos = HIWORD(wParam);
				auto m = LOWORD(wParam);

				// FIXME: I can reintroduce the
				// scroll bars now by using this
				// in the top-level window handler
				// to forward comamnds
				auto scrollbarHwnd = lParam;
				switch(m) {
					case SB_BOTTOM:
						if(msg == WM_HSCROLL)
							horizontalScrollTo(contentWidth_);
						else
							verticalScrollTo(contentHeight_);
					break;
					case SB_TOP:
						if(msg == WM_HSCROLL)
							horizontalScrollTo(0);
						else
							verticalScrollTo(0);
					break;
					case SB_ENDSCROLL:
						// idk
					break;
					case SB_LINEDOWN:
						if(msg == WM_HSCROLL)
							horizontalScroll(scaleWithDpi(16));
						else
							verticalScroll(scaleWithDpi(16));
					break;
					case SB_LINEUP:
						if(msg == WM_HSCROLL)
							horizontalScroll(scaleWithDpi(-16));
						else
							verticalScroll(scaleWithDpi(-16));
					break;
					case SB_PAGEDOWN:
						if(msg == WM_HSCROLL)
							horizontalScroll(scaleWithDpi(100));
						else
							verticalScroll(scaleWithDpi(100));
					break;
					case SB_PAGEUP:
						if(msg == WM_HSCROLL)
							horizontalScroll(scaleWithDpi(-100));
						else
							verticalScroll(scaleWithDpi(-100));
					break;
					case SB_THUMBPOSITION:
					case SB_THUMBTRACK:
						if(msg == WM_HSCROLL)
							horizontalScrollTo(pos);
						else
							verticalScrollTo(pos);

						if(m == SB_THUMBTRACK) {
							// the event loop doesn't seem to carry on with a requested redraw..
							// so we request it to get our dirty bit set...
							redraw();

							// then we need to immediately actually redraw it too for instant feedback to user

							SimpleWindow.processAllCustomEvents();
							//if(parentWindow)
								//parentWindow.actualRedraw();
						}
					break;
					default:
				}
			}
			return super.hookedWndProc(msg, wParam, lParam);
		}
	}
	///
	this(Widget parent) {
		this.parentWindow = parent.parentWindow;

		version(win32_widgets) {
			createWin32Window(this, Win32Class!"arsd_minigui_ScrollableWidget"w, "",
				0|WS_CHILD|WS_VISIBLE|WS_HSCROLL|WS_VSCROLL, 0);
			super(parent);
		} else version(custom_widgets) {
			outerContainer = new InternalScrollableContainerWidget(this, parent);
			super(outerContainer);
		} else static assert(0);
	}

	version(custom_widgets)
		InternalScrollableContainerWidget outerContainer;

	override void defaultEventHandler_click(ClickEvent event) {
		if(event.button == MouseButton.wheelUp)
			verticalScroll(scaleWithDpi(-16));
		if(event.button == MouseButton.wheelDown)
			verticalScroll(scaleWithDpi(16));
		super.defaultEventHandler_click(event);
	}

	override void defaultEventHandler_keydown(KeyDownEvent event) {
		switch(event.key) {
			case Key.Left:
				horizontalScroll(scaleWithDpi(-16));
			break;
			case Key.Right:
				horizontalScroll(scaleWithDpi(16));
			break;
			case Key.Up:
				verticalScroll(scaleWithDpi(-16));
			break;
			case Key.Down:
				verticalScroll(scaleWithDpi(16));
			break;
			case Key.Home:
				verticalScrollTo(0);
			break;
			case Key.End:
				verticalScrollTo(contentHeight);
			break;
			case Key.PageUp:
				verticalScroll(scaleWithDpi(-160));
			break;
			case Key.PageDown:
				verticalScroll(scaleWithDpi(160));
			break;
			default:
		}
		super.defaultEventHandler_keydown(event);
	}


	version(win32_widgets)
	override void recomputeChildLayout() {
		super.recomputeChildLayout();
		SCROLLINFO info;
		info.cbSize = info.sizeof;
		info.nPage = viewportHeight;
		info.fMask = SIF_PAGE | SIF_RANGE;
		info.nMin = 0;
		info.nMax = contentHeight_;
		SetScrollInfo(hwnd, SB_VERT, &info, true);

		info.cbSize = info.sizeof;
		info.nPage = viewportWidth;
		info.fMask = SIF_PAGE | SIF_RANGE;
		info.nMin = 0;
		info.nMax = contentWidth_;
		SetScrollInfo(hwnd, SB_HORZ, &info, true);
	}

	/*
		Scrolling
		------------

		You are assigned a width and a height by the layout engine, which
		is your viewport box. However, you may draw more than that by setting
		a contentWidth and contentHeight.

		If these can be contained by the viewport, no scrollbar is displayed.
		If they cannot fit though, it will automatically show scroll as necessary.

		If contentWidth == 0, no horizontal scrolling is performed. If contentHeight
		is zero, no vertical scrolling is performed.

		If scrolling is necessary, the lib will automatically work with the bars.
		When you redraw, the origin and clipping info in the painter is set so if
		you just draw everything, it will work, but you can be more efficient by checking
		the viewportWidth, viewportHeight, and scrollOrigin members.
	*/

	///
	final @property int viewportWidth() {
		return width - (showingVerticalScroll ? scaleWithDpi(16) : 0);
	}
	///
	final @property int viewportHeight() {
		return height - (showingHorizontalScroll ? scaleWithDpi(16) : 0);
	}

	// FIXME property
	Point scrollOrigin_;

	///
	final const(Point) scrollOrigin() {
		return scrollOrigin_;
	}

	// the user sets these two
	private int contentWidth_ = 0;
	private int contentHeight_ = 0;

	///
	int contentWidth() { return contentWidth_; }
	///
	int contentHeight() { return contentHeight_; }

	///
	void setContentSize(int width, int height) {
		contentWidth_ = width;
		contentHeight_ = height;

		version(custom_widgets) {
			if(showingVerticalScroll || showingHorizontalScroll) {
				outerContainer.queueRecomputeChildLayout();
			}

			if(showingVerticalScroll())
				outerContainer.verticalScrollBar.redraw();
			if(showingHorizontalScroll())
				outerContainer.horizontalScrollBar.redraw();
		} else version(win32_widgets) {
			queueRecomputeChildLayout();
		} else static assert(0);
	}

	///
	void verticalScroll(int delta) {
		verticalScrollTo(scrollOrigin.y + delta);
	}
	///
	void verticalScrollTo(int pos) {
		scrollOrigin_.y = pos;
		if(pos == int.max || (scrollOrigin_.y + viewportHeight > contentHeight))
			scrollOrigin_.y = contentHeight - viewportHeight;

		if(scrollOrigin_.y < 0)
			scrollOrigin_.y = 0;

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = scrollOrigin_.y;
			SetScrollInfo(hwnd, SB_VERT, &info, true);
		} else version(custom_widgets) {
			outerContainer.verticalScrollBar.setPosition(scrollOrigin_.y);
		} else static assert(0);

		redraw();
	}

	///
	void horizontalScroll(int delta) {
		horizontalScrollTo(scrollOrigin.x + delta);
	}
	///
	void horizontalScrollTo(int pos) {
		scrollOrigin_.x = pos;
		if(pos == int.max || (scrollOrigin_.x + viewportWidth > contentWidth))
			scrollOrigin_.x = contentWidth - viewportWidth;

		if(scrollOrigin_.x < 0)
			scrollOrigin_.x = 0;

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = scrollOrigin_.x;
			SetScrollInfo(hwnd, SB_HORZ, &info, true);
		} else version(custom_widgets) {
			outerContainer.horizontalScrollBar.setPosition(scrollOrigin_.x);
		} else static assert(0);

		redraw();
	}
	///
	void scrollTo(Point p) {
		verticalScrollTo(p.y);
		horizontalScrollTo(p.x);
	}

	///
	void ensureVisibleInScroll(Point p) {
		auto rect = viewportRectangle();
		if(rect.contains(p))
			return;
		if(p.x < rect.left)
			horizontalScroll(p.x - rect.left);
		else if(p.x > rect.right)
			horizontalScroll(p.x - rect.right);

		if(p.y < rect.top)
			verticalScroll(p.y - rect.top);
		else if(p.y > rect.bottom)
			verticalScroll(p.y - rect.bottom);
	}

	///
	void ensureVisibleInScroll(Rectangle rect) {
		ensureVisibleInScroll(rect.upperLeft);
		ensureVisibleInScroll(rect.lowerRight);
	}

	///
	Rectangle viewportRectangle() {
		return Rectangle(scrollOrigin, Size(viewportWidth, viewportHeight));
	}

	///
	bool showingHorizontalScroll() {
		return contentWidth > width;
	}
	///
	bool showingVerticalScroll() {
		return contentHeight > height;
	}

	/// This is called before the ordinary paint delegate,
	/// giving you a chance to draw the window frame, etc,
	/// before the scroll clip takes effect
	void paintFrameAndBackground(WidgetPainter painter) {
		version(win32_widgets) {
			auto b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
			auto p = SelectObject(painter.impl.hdc, GetStockObject(NULL_PEN));
			// since the pen is null, to fill the whole space, we need the +1 on both.
			gdi.Rectangle(painter.impl.hdc, 0, 0, this.width + 1, this.height + 1);
			SelectObject(painter.impl.hdc, p);
			SelectObject(painter.impl.hdc, b);
		}

	}

	// make space for the scroll bar, and that's it.
	final override int paddingRight() { return scaleWithDpi(16); }
	final override int paddingBottom() { return scaleWithDpi(16); }

	/*
		END SCROLLING
	*/

	override WidgetPainter draw() {
		int x = this.x, y = this.y;
		auto parent = this.parent;
		while(parent) {
			x += parent.x;
			y += parent.y;
			parent = parent.parent;
		}

		//version(win32_widgets) {
			//auto painter = simpleWindowWrappingHwnd ? simpleWindowWrappingHwnd.draw(true) : parentWindow.win.draw(true);
		//} else {
			auto painter = parentWindow.win.draw(true);
		//}
		painter.originX = x;
		painter.originY = y;

		painter.originX = painter.originX - scrollOrigin.x;
		painter.originY = painter.originY - scrollOrigin.y;
		painter.setClipRectangle(scrollOrigin, viewportWidth(), viewportHeight());

		return WidgetPainter(painter, this);
	}

	override void addScrollPosition(ref int x, ref int y) {
		x += scrollOrigin.x;
		y += scrollOrigin.y;
	}

	mixin ScrollableChildren;
}

// you need to have a Point scrollOrigin in the class somewhere
// and a paintFrameAndBackground
private mixin template ScrollableChildren() {
	static assert(!__traits(isSame, this.addScrollPosition, Widget.addScrollPosition), "Your widget should provide `Point scrollOrigin()` and `override void addScrollPosition`");

	override protected void privatePaint(WidgetPainter painter, int lox, int loy, Rectangle containment, bool force, bool invalidate) {
		if(hidden)
			return;

		//version(win32_widgets)
			//painter = simpleWindowWrappingHwnd ? simpleWindowWrappingHwnd.draw(true) : parentWindow.win.draw(true);

		painter.originX = lox + x;
		painter.originY = loy + y;

		bool actuallyPainted = false;

		const clip = containment.intersectionOf(Rectangle(Point(lox + x, loy + y), Size(width, height)));
		if(clip == Rectangle.init)
			return;

		if(force || redrawRequested) {
			//painter.setClipRectangle(scrollOrigin, width, height);
			painter.setClipRectangleForWidget(clip.upperLeft - Point(painter.originX, painter.originY), clip.width, clip.height);
			paintFrameAndBackground(painter);
		}

		/+
		version(win32_widgets) {
			if(hwnd) RedrawWindow(hwnd, null, null, RDW_ERASE | RDW_INVALIDATE | RDW_UPDATENOW);// | RDW_ALLCHILDREN | RDW_UPDATENOW);
		}
		+/

		painter.originX = painter.originX - scrollOrigin.x;
		painter.originY = painter.originY - scrollOrigin.y;
		if(force || redrawRequested) {
			painter.setClipRectangleForWidget(clip.upperLeft - Point(painter.originX, painter.originY) + Point(2, 2) /* border */, clip.width - 4, clip.height - 4);
			//painter.setClipRectangle(scrollOrigin + Point(2, 2) /* border */, width - 4, height - 4);

			//erase(painter); // we paintFrameAndBackground above so no need
			if(painter.visualTheme)
				painter.visualTheme.doPaint(this, painter);
			else
				paint(painter);

			if(invalidate) {
				painter.invalidateRect(Rectangle(Point(clip.upperLeft.x - painter.originX, clip.upperRight.y - painter.originY), Size(clip.width, clip.height)));
				// children are contained inside this, so no need to do extra work
				invalidate = false;
			}


			actuallyPainted = true;
			redrawRequested = false;
		}

		foreach(child; children) {
			if(cast(FixedPosition) child)
				child.privatePaint(painter, painter.originX + scrollOrigin.x, painter.originY + scrollOrigin.y, clip, actuallyPainted, invalidate);
			else
				child.privatePaint(painter, painter.originX, painter.originY, clip, actuallyPainted, invalidate);
		}
	}
}

private class InternalScrollableContainerInsideWidget : ContainerWidget {
	ScrollableContainerWidget scw;

	this(ScrollableContainerWidget parent) {
		scw = parent;
		super(parent);
	}

	version(custom_widgets)
	override protected void privatePaint(WidgetPainter painter, int lox, int loy, Rectangle containment, bool force, bool invalidate) {
		if(hidden)
			return;

		bool actuallyPainted = false;

		auto scrollOrigin = Point(scw.scrollX_, scw.scrollY_);

		const clip = containment.intersectionOf(Rectangle(Point(lox + x, loy + y), Size(width + scw.scrollX_, height + scw.scrollY_)));
		if(clip == Rectangle.init)
			return;

		painter.originX = lox + x - scrollOrigin.x;
		painter.originY = loy + y - scrollOrigin.y;
		if(force || redrawRequested) {
			painter.setClipRectangleForWidget(clip.upperLeft - Point(painter.originX, painter.originY), clip.width, clip.height);

			erase(painter);
			if(painter.visualTheme)
				painter.visualTheme.doPaint(this, painter);
			else
				paint(painter);

			if(invalidate) {
				painter.invalidateRect(Rectangle(Point(clip.upperLeft.x - painter.originX, clip.upperRight.y - painter.originY), Size(clip.width, clip.height)));
				// children are contained inside this, so no need to do extra work
				invalidate = false;
			}

			actuallyPainted = true;
			redrawRequested = false;
		}
		foreach(child; children) {
			if(cast(FixedPosition) child)
				child.privatePaint(painter, painter.originX + scrollOrigin.x, painter.originY + scrollOrigin.y, clip, actuallyPainted, invalidate);
			else
				child.privatePaint(painter, painter.originX, painter.originY, clip, actuallyPainted, invalidate);
		}
	}

	version(custom_widgets)
	override protected void addScrollPosition(ref int x, ref int y) {
		x += scw.scrollX_;
		y += scw.scrollY_;
	}
}

/++
	A widget meant to contain other widgets that may need to scroll.

	Currently buggy.

	History:
		Added July 1, 2021 (dub v10.2)

		On January 3, 2022, I tried to use it in a few other cases
		and found it only worked well in the original test case. Since
		it still sucks, I think I'm going to rewrite it again.
+/
class ScrollableContainerWidget : ContainerWidget {
	///
	this(Widget parent) {
		super(parent);

		container = new InternalScrollableContainerInsideWidget(this);
		hsb = new HorizontalScrollbar(this);
		vsb = new VerticalScrollbar(this);

		tabStop = false;
		container.tabStop = false;
		magic = true;


		vsb.addEventListener("scrolltonextline", () {
			scrollBy(0, scaleWithDpi(16));
		});
		vsb.addEventListener("scrolltopreviousline", () {
			scrollBy(0,scaleWithDpi( -16));
		});
		vsb.addEventListener("scrolltonextpage", () {
			scrollBy(0, container.height);
		});
		vsb.addEventListener("scrolltopreviouspage", () {
			scrollBy(0, -container.height);
		});
		vsb.addEventListener((scope ScrollToPositionEvent spe) {
			scrollTo(scrollX_, spe.value);
		});

		this.addEventListener(delegate (scope ClickEvent e) {
			if(e.button == MouseButton.wheelUp) {
				if(!e.defaultPrevented)
					scrollBy(0, scaleWithDpi(-16));
				e.stopPropagation();
			} else if(e.button == MouseButton.wheelDown) {
				if(!e.defaultPrevented)
					scrollBy(0, scaleWithDpi(16));
				e.stopPropagation();
			}
		});
	}

	/+
	override void defaultEventHandler_click(ClickEvent e) {
	}
	+/

	override void removeAllChildren() {
		container.removeAllChildren();
	}

	void scrollTo(int x, int y) {
		scrollBy(x - scrollX_, y - scrollY_);
	}

	void scrollBy(int x, int y) {
		auto ox = scrollX_;
		auto oy = scrollY_;

		auto nx = ox + x;
		auto ny = oy + y;

		if(nx < 0)
			nx = 0;
		if(ny < 0)
			ny = 0;

		auto maxX = hsb.max - container.width;
		if(maxX < 0) maxX = 0;
		auto maxY = vsb.max - container.height;
		if(maxY < 0) maxY = 0;

		if(nx > maxX)
			nx = maxX;
		if(ny > maxY)
			ny = maxY;

		auto dx = nx - ox;
		auto dy = ny - oy;

		if(dx || dy) {
			version(win32_widgets)
				ScrollWindowEx(container.hwnd, -dx, -dy, null, null, null, null, SW_SCROLLCHILDREN | SW_INVALIDATE | SW_ERASE);
			else {
				redraw();
			}

			hsb.setPosition = nx;
			vsb.setPosition = ny;

			scrollX_ = nx;
			scrollY_ = ny;
		}
	}

	private int scrollX_;
	private int scrollY_;

	void setTotalArea(int width, int height) {
		hsb.setMax(width);
		vsb.setMax(height);
	}

	///
	void setViewableArea(int width, int height) {
		hsb.setViewableArea(width);
		vsb.setViewableArea(height);
	}

	private bool magic;
	override void addChild(Widget w, int position = int.max) {
		if(magic)
			container.addChild(w, position);
		else
			super.addChild(w, position);
	}

	override void recomputeChildLayout() {
		if(hsb is null || vsb is null || container is null) return;

		/+
		writeln(x, " ", y , " ", width, " ", height);
		writeln(this.ContainerWidget.minWidth(), "x", this.ContainerWidget.minHeight());
		+/

		registerMovement();

		hsb.height = scaleWithDpi(16); // FIXME? are tese 16s sane?
		hsb.x = 0;
		hsb.y = this.height - hsb.height;
		hsb.width = this.width - scaleWithDpi(16);
		hsb.recomputeChildLayout();

		vsb.width = scaleWithDpi(16); // FIXME?
		vsb.x = this.width - vsb.width;
		vsb.y = 0;
		vsb.height = this.height - scaleWithDpi(16);
		vsb.recomputeChildLayout();

		container.x = 0;
		container.y = 0;
		container.width = this.width - vsb.width;
		container.height = this.height - hsb.height;
		container.recomputeChildLayout();

		scrollX_ = 0;
		scrollY_ = 0;

		hsb.setPosition(0);
		vsb.setPosition(0);

		int mw, mh;
		Widget c = container;
		// FIXME: hack here to handle a layout inside...
		if(c.children.length == 1 && cast(Layout) c.children[0])
			c = c.children[0];
		foreach(child; c.children) {
			auto w = child.x + child.width;
			auto h = child.y + child.height;

			if(w > mw) mw = w;
			if(h > mh) mh = h;
		}

		setTotalArea(mw, mh);
		setViewableArea(width, height);
	}

	override int minHeight() { return scaleWithDpi(64); }

	HorizontalScrollbar hsb;
	VerticalScrollbar vsb;
	ContainerWidget container;
}


version(custom_widgets)
deprecated
private class InternalScrollableContainerWidget : Widget {

	ScrollableWidget sw;

	VerticalScrollbar verticalScrollBar;
	HorizontalScrollbar horizontalScrollBar;

	this(ScrollableWidget sw, Widget parent) {
		this.sw = sw;

		this.tabStop = false;

		super(parent);

		horizontalScrollBar = new HorizontalScrollbar(this);
		verticalScrollBar = new VerticalScrollbar(this);

		horizontalScrollBar.showing_ = false;
		verticalScrollBar.showing_ = false;

		horizontalScrollBar.addEventListener("scrolltonextline", {
			horizontalScrollBar.setPosition(horizontalScrollBar.position + 1);
			sw.horizontalScrollTo(horizontalScrollBar.position);
		});
		horizontalScrollBar.addEventListener("scrolltopreviousline", {
			horizontalScrollBar.setPosition(horizontalScrollBar.position - 1);
			sw.horizontalScrollTo(horizontalScrollBar.position);
		});
		verticalScrollBar.addEventListener("scrolltonextline", {
			verticalScrollBar.setPosition(verticalScrollBar.position + 1);
			sw.verticalScrollTo(verticalScrollBar.position);
		});
		verticalScrollBar.addEventListener("scrolltopreviousline", {
			verticalScrollBar.setPosition(verticalScrollBar.position - 1);
			sw.verticalScrollTo(verticalScrollBar.position);
		});
		horizontalScrollBar.addEventListener("scrolltonextpage", {
			horizontalScrollBar.setPosition(horizontalScrollBar.position + horizontalScrollBar.step_);
			sw.horizontalScrollTo(horizontalScrollBar.position);
		});
		horizontalScrollBar.addEventListener("scrolltopreviouspage", {
			horizontalScrollBar.setPosition(horizontalScrollBar.position - horizontalScrollBar.step_);
			sw.horizontalScrollTo(horizontalScrollBar.position);
		});
		verticalScrollBar.addEventListener("scrolltonextpage", {
			verticalScrollBar.setPosition(verticalScrollBar.position + verticalScrollBar.step_);
			sw.verticalScrollTo(verticalScrollBar.position);
		});
		verticalScrollBar.addEventListener("scrolltopreviouspage", {
			verticalScrollBar.setPosition(verticalScrollBar.position - verticalScrollBar.step_);
			sw.verticalScrollTo(verticalScrollBar.position);
		});
		horizontalScrollBar.addEventListener("scrolltoposition", (Event event) {
			horizontalScrollBar.setPosition(event.intValue);
			sw.horizontalScrollTo(horizontalScrollBar.position);
		});
		verticalScrollBar.addEventListener("scrolltoposition", (Event event) {
			verticalScrollBar.setPosition(event.intValue);
			sw.verticalScrollTo(verticalScrollBar.position);
		});
		horizontalScrollBar.addEventListener("scrolltrack", (Event event) {
			horizontalScrollBar.setPosition(event.intValue);
			sw.horizontalScrollTo(horizontalScrollBar.position);
		});
		verticalScrollBar.addEventListener("scrolltrack", (Event event) {
			verticalScrollBar.setPosition(event.intValue);
		});
	}

	// this is supposed to be basically invisible...
	override int minWidth() { return sw.minWidth; }
	override int minHeight() { return sw.minHeight; }
	override int maxWidth() { return sw.maxWidth; }
	override int maxHeight() { return sw.maxHeight; }
	override int widthStretchiness() { return sw.widthStretchiness; }
	override int heightStretchiness() { return sw.heightStretchiness; }
	override int marginLeft() { return sw.marginLeft; }
	override int marginRight() { return sw.marginRight; }
	override int marginTop() { return sw.marginTop; }
	override int marginBottom() { return sw.marginBottom; }
	override int paddingLeft() { return sw.paddingLeft; }
	override int paddingRight() { return sw.paddingRight; }
	override int paddingTop() { return sw.paddingTop; }
	override int paddingBottom() { return sw.paddingBottom; }
	override void focus() { sw.focus(); }


	override void recomputeChildLayout() {
		// The stupid thing needs to calculate if a scroll bar is needed...
		recomputeChildLayoutHelper();
		// then running it again will position things correctly if the bar is NOT needed
		recomputeChildLayoutHelper();

		// this sucks but meh it barely works
	}

	private void recomputeChildLayoutHelper() {
		if(sw is null) return;

		bool both = sw.showingVerticalScroll && sw.showingHorizontalScroll;
		if(horizontalScrollBar && verticalScrollBar) {
			horizontalScrollBar.width = this.width - (both ? verticalScrollBar.minWidth() : 0);
			horizontalScrollBar.height = horizontalScrollBar.minHeight();
			horizontalScrollBar.x = 0;
			horizontalScrollBar.y = this.height - horizontalScrollBar.minHeight();

			verticalScrollBar.width = verticalScrollBar.minWidth();
			verticalScrollBar.height = this.height - (both ? horizontalScrollBar.minHeight() : 0) - 2 - 2;
			verticalScrollBar.x = this.width - verticalScrollBar.minWidth();
			verticalScrollBar.y = 0 + 2;

			sw.x = 0;
			sw.y = 0;
			sw.width = this.width - (verticalScrollBar.showing ? verticalScrollBar.width : 0);
			sw.height = this.height - (horizontalScrollBar.showing ? horizontalScrollBar.height : 0);

			if(sw.contentWidth_ <= this.width)
				sw.scrollOrigin_.x = 0;
			if(sw.contentHeight_ <= this.height)
				sw.scrollOrigin_.y = 0;

			horizontalScrollBar.recomputeChildLayout();
			verticalScrollBar.recomputeChildLayout();
			sw.recomputeChildLayout();
		}

		if(sw.contentWidth_ <= this.width)
			sw.scrollOrigin_.x = 0;
		if(sw.contentHeight_ <= this.height)
			sw.scrollOrigin_.y = 0;

		if(sw.showingHorizontalScroll())
			horizontalScrollBar.showing(true, false);
		else
			horizontalScrollBar.showing(false, false);
		if(sw.showingVerticalScroll())
			verticalScrollBar.showing(true, false);
		else
			verticalScrollBar.showing(false, false);

		verticalScrollBar.setViewableArea(sw.viewportHeight());
		verticalScrollBar.setMax(sw.contentHeight);
		verticalScrollBar.setPosition(sw.scrollOrigin.y);

		horizontalScrollBar.setViewableArea(sw.viewportWidth());
		horizontalScrollBar.setMax(sw.contentWidth);
		horizontalScrollBar.setPosition(sw.scrollOrigin.x);
	}
}

/*
class ScrollableClientWidget : Widget {
	this(Widget parent) {
		super(parent);
	}
	override void paint(WidgetPainter p) {
		parent.paint(p);
	}
}
*/

/++
	A slider, also known as a trackbar control, is commonly used in applications like volume controls where you want the user to select a value between a min and a max without needing a specific value or otherwise precise input.
+/
abstract class Slider : Widget {
	this(int min, int max, int step, Widget parent) {
		min_ = min;
		max_ = max;
		step_ = step;
		page_ = step;
		super(parent);
	}

	private int min_;
	private int max_;
	private int step_;
	private int position_;
	private int page_;

	// selection start and selection end
	// tics
	// tooltip?
	// some way to see and just type the value
	// win32 buddy controls are labels

	///
	void setMin(int a) {
		min_ = a;
		version(custom_widgets)
			redraw();
		version(win32_widgets)
			SendMessage(hwnd, TBM_SETRANGEMIN, true, a);
	}
	///
	int min() {
		return min_;
	}
	///
	void setMax(int a) {
		max_ = a;
		version(custom_widgets)
			redraw();
		version(win32_widgets)
			SendMessage(hwnd, TBM_SETRANGEMAX, true, a);
	}
	///
	int max() {
		return max_;
	}
	///
	void setPosition(int a) {
		if(a > max)
			a = max;
		if(a < min)
			a = min;
		position_ = a;
		version(custom_widgets)
			setPositionCustom(a);

		version(win32_widgets)
			setPositionWindows(a);
	}
	version(win32_widgets) {
		protected abstract void setPositionWindows(int a);
	}

	protected abstract int win32direction();

	/++
		Alias for [position] for better compatibility with generic code.

		History:
			Added October 5, 2021
	+/
	@property int value() {
		return position;
	}

	///
	int position() {
		return position_;
	}
	///
	void setStep(int a) {
		step_ = a;
		version(win32_widgets)
			SendMessage(hwnd, TBM_SETLINESIZE, 0, a);
	}
	///
	int step() {
		return step_;
	}
	///
	void setPageSize(int a) {
		page_ = a;
		version(win32_widgets)
			SendMessage(hwnd, TBM_SETPAGESIZE, 0, a);
	}
	///
	int pageSize() {
		return page_;
	}

	private void notify() {
		auto event = new ChangeEvent!int(this, &this.position);
		event.dispatch();
	}

	version(win32_widgets)
	void win32Setup(int style) {
		createWin32Window(this, TRACKBAR_CLASS, "",
			0|WS_CHILD|WS_VISIBLE|style|TBS_TOOLTIPS, 0);

		// the trackbar sends the same messages as scroll, which
		// our other layer sends as these... just gonna translate
		// here
		this.addDirectEventListener("scrolltoposition", (Event event) {
			event.stopPropagation();
			this.setPosition(this.win32direction > 0 ? event.intValue : max - event.intValue);
			notify();
		});
		this.addDirectEventListener("scrolltonextline", (Event event) {
			event.stopPropagation();
			this.setPosition(this.position + this.step_ * this.win32direction);
			notify();
		});
		this.addDirectEventListener("scrolltopreviousline", (Event event) {
			event.stopPropagation();
			this.setPosition(this.position - this.step_ * this.win32direction);
			notify();
		});
		this.addDirectEventListener("scrolltonextpage", (Event event) {
			event.stopPropagation();
			this.setPosition(this.position + this.page_ * this.win32direction);
			notify();
		});
		this.addDirectEventListener("scrolltopreviouspage", (Event event) {
			event.stopPropagation();
			this.setPosition(this.position - this.page_ * this.win32direction);
			notify();
		});

		setMin(min_);
		setMax(max_);
		setStep(step_);
		setPageSize(page_);
	}

	version(custom_widgets) {
		protected MouseTrackingWidget thumb;

		protected abstract void setPositionCustom(int a);

		override void defaultEventHandler_keydown(KeyDownEvent event) {
			switch(event.key) {
				case Key.Up:
				case Key.Right:
					setPosition(position() - step() * win32direction);
					changed();
				break;
				case Key.Down:
				case Key.Left:
					setPosition(position() + step() * win32direction);
					changed();
				break;
				case Key.Home:
					setPosition(win32direction > 0 ? min() : max());
					changed();
				break;
				case Key.End:
					setPosition(win32direction > 0 ? max() : min());
					changed();
				break;
				case Key.PageUp:
					setPosition(position() - pageSize() * win32direction);
					changed();
				break;
				case Key.PageDown:
					setPosition(position() + pageSize() * win32direction);
					changed();
				break;
				default:
			}
			super.defaultEventHandler_keydown(event);
		}

		protected void changed() {
			auto ev = new ChangeEvent!int(this, &position);
			ev.dispatch();
		}
	}
}

/++

+/
class VerticalSlider : Slider {
	this(int min, int max, int step, Widget parent) {
		version(custom_widgets)
			initialize();

		super(min, max, step, parent);

		version(win32_widgets)
			win32Setup(TBS_VERT | 0x0200 /* TBS_REVERSED */);
	}

	protected override int win32direction() {
		return -1;
	}

	version(win32_widgets)
	protected override void setPositionWindows(int a) {
		// the windows thing makes the top 0 and i don't like that.
		SendMessage(hwnd, TBM_SETPOS, true, max - a);
	}

	version(custom_widgets)
	private void initialize() {
		thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.vertical, this);

		thumb.tabStop = false;

		thumb.thumbWidth = width;
		thumb.thumbHeight = scaleWithDpi(16);

		thumb.addEventListener(EventType.change, () {
			auto sx = thumb.positionY * max() / (thumb.height - scaleWithDpi(16));
			sx = max - sx;
			//informProgramThatUserChangedPosition(sx);

			position_ = sx;

			changed();
		});
	}

	version(custom_widgets)
	override void recomputeChildLayout() {
		thumb.thumbWidth = this.width;
		super.recomputeChildLayout();
		setPositionCustom(position_);
	}

	version(custom_widgets)
	protected override void setPositionCustom(int a) {
		if(max())
			thumb.positionY = (max - a) * (thumb.height - scaleWithDpi(16)) / max();
		redraw();
	}
}

/++

+/
class HorizontalSlider : Slider {
	this(int min, int max, int step, Widget parent) {
		version(custom_widgets)
			initialize();

		super(min, max, step, parent);

		version(win32_widgets)
			win32Setup(TBS_HORZ);
	}

	version(win32_widgets)
	protected override void setPositionWindows(int a) {
		SendMessage(hwnd, TBM_SETPOS, true, a);
	}

	protected override int win32direction() {
		return 1;
	}

	version(custom_widgets)
	private void initialize() {
		thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.horizontal, this);

		thumb.tabStop = false;

		thumb.thumbWidth = scaleWithDpi(16);
		thumb.thumbHeight = height;

		thumb.addEventListener(EventType.change, () {
			auto sx = thumb.positionX * max() / (thumb.width - scaleWithDpi(16));
			//informProgramThatUserChangedPosition(sx);

			position_ = sx;

			changed();
		});
	}

	version(custom_widgets)
	override void recomputeChildLayout() {
		thumb.thumbHeight = this.height;
		super.recomputeChildLayout();
		setPositionCustom(position_);
	}

	version(custom_widgets)
	protected override void setPositionCustom(int a) {
		if(max())
			thumb.positionX = a * (thumb.width - scaleWithDpi(16)) / max();
		redraw();
	}
}


///
abstract class ScrollbarBase : Widget {
	///
	this(Widget parent) {
		super(parent);
		tabStop = false;
		step_ = scaleWithDpi(16);
	}

	private int viewableArea_;
	private int max_;
	private int step_;// = 16;
	private int position_;

	///
	bool atEnd() {
		return position_ + viewableArea_ >= max_;
	}

	///
	bool atStart() {
		return position_ == 0;
	}

	///
	void setViewableArea(int a) {
		viewableArea_ = a;
		version(custom_widgets)
			redraw();
	}
	///
	void setMax(int a) {
		max_ = a;
		version(custom_widgets)
			redraw();
	}
	///
	int max() {
		return max_;
	}
	///
	void setPosition(int a) {
		auto logicalMax = max_ - viewableArea_;
		if(a == int.max)
			a = logicalMax;

		if(a > logicalMax)
			a = logicalMax;
		if(a < 0)
			a = 0;

		position_ = a;

		version(custom_widgets)
			redraw();
	}
	///
	int position() {
		return position_;
	}
	///
	void setStep(int a) {
		step_ = a;
	}
	///
	int step() {
		return step_;
	}

	// FIXME: remove this.... maybe
	/+
	protected void informProgramThatUserChangedPosition(int n) {
		position_ = n;
		auto evt = new Event(EventType.change, this);
		evt.intValue = n;
		evt.dispatch();
	}
	+/

	version(custom_widgets) {
		enum MIN_THUMB_SIZE = 8;

		abstract protected int getBarDim();
		int thumbSize() {
			if(viewableArea_ >= max_ || max_ == 0)
				return getBarDim();

			int res = viewableArea_ * getBarDim() / max_;

			if(res < scaleWithDpi(MIN_THUMB_SIZE))
				res = scaleWithDpi(MIN_THUMB_SIZE);

			return res;
		}

		int thumbPosition() {
			/*
				viewableArea_ is the viewport height/width
				position_ is where we are
			*/
			//if(position_ + viewableArea_ >= max_)
				//return getBarDim - thumbSize;

			auto maximumPossibleValue = getBarDim() - thumbSize;
			auto maximiumLogicalValue = max_ - viewableArea_;

			auto p = (maximiumLogicalValue > 0) ? cast(int) (cast(long) position_ * maximumPossibleValue / maximiumLogicalValue) : 0;

			return p;
		}
	}
}

//public import mgt;

/++
	A mouse tracking widget is one that follows the mouse when dragged inside it.

	Concrete subclasses may include a scrollbar thumb and a volume control.
+/
//version(custom_widgets)
class MouseTrackingWidget : Widget {

	///
	int positionX() { return positionX_; }
	///
	int positionY() { return positionY_; }

	///
	void positionX(int p) { positionX_ = p; }
	///
	void positionY(int p) { positionY_ = p; }

	private int positionX_;
	private int positionY_;

	///
	enum Orientation {
		horizontal, ///
		vertical, ///
		twoDimensional, ///
	}

	private int thumbWidth_;
	private int thumbHeight_;

	///
	int thumbWidth() { return thumbWidth_; }
	///
	int thumbHeight() { return thumbHeight_; }
	///
	int thumbWidth(int a) { return thumbWidth_ = a; }
	///
	int thumbHeight(int a) { return thumbHeight_ = a; }

	private bool dragging;
	private bool hovering;
	private int startMouseX, startMouseY;

	///
	this(Orientation orientation, Widget parent) {
		super(parent);

		//assert(parentWindow !is null);

		addEventListener((MouseDownEvent event) {
			if(event.clientX >= positionX && event.clientX < positionX + thumbWidth && event.clientY >= positionY && event.clientY < positionY + thumbHeight) {
				dragging = true;
				startMouseX = event.clientX - positionX;
				startMouseY = event.clientY - positionY;
				parentWindow.captureMouse(this);
			} else {
				if(orientation == Orientation.horizontal || orientation == Orientation.twoDimensional)
					positionX = event.clientX - thumbWidth / 2;
				if(orientation == Orientation.vertical || orientation == Orientation.twoDimensional)
					positionY = event.clientY - thumbHeight / 2;

				if(positionX + thumbWidth > this.width)
					positionX = this.width - thumbWidth;
				if(positionY + thumbHeight > this.height)
					positionY = this.height - thumbHeight;

				if(positionX < 0)
					positionX = 0;
				if(positionY < 0)
					positionY = 0;


				// this.emit!(ChangeEvent!void)();
				auto evt = new Event(EventType.change, this);
				evt.sendDirectly();

				redraw();

			}
		});

		addEventListener(EventType.mouseup, (Event event) {
			dragging = false;
			parentWindow.releaseMouseCapture();
		});

		addEventListener(EventType.mouseout, (Event event) {
			if(!hovering)
				return;
			hovering = false;
			redraw();
		});

		int lpx, lpy;

		addEventListener((MouseMoveEvent event) {
			auto oh = hovering;
			if(event.clientX >= positionX && event.clientX < positionX + thumbWidth && event.clientY >= positionY && event.clientY < positionY + thumbHeight) {
				hovering = true;
			} else {
				hovering = false;
			}
			if(!dragging) {
				if(hovering != oh)
					redraw();
				return;
			}

			if(orientation == Orientation.horizontal || orientation == Orientation.twoDimensional)
				positionX = event.clientX - startMouseX; // FIXME: click could be in the middle of it
			if(orientation == Orientation.vertical || orientation == Orientation.twoDimensional)
				positionY = event.clientY - startMouseY;

			if(positionX + thumbWidth > this.width)
				positionX = this.width - thumbWidth;
			if(positionY + thumbHeight > this.height)
				positionY = this.height - thumbHeight;

			if(positionX < 0)
				positionX = 0;
			if(positionY < 0)
				positionY = 0;

			if(positionX != lpx || positionY != lpy) {
				lpx = positionX;
				lpy = positionY;

				auto evt = new Event(EventType.change, this);
				evt.sendDirectly();
			}

			redraw();
		});
	}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		auto c = darken(cs.windowBackgroundColor, 0.2);
		painter.outlineColor = c;
		painter.fillColor = c;
		painter.drawRectangle(Point(0, 0), this.width, this.height);

		auto color = hovering ? cs.hoveringColor : cs.windowBackgroundColor;
		draw3dFrame(positionX, positionY, thumbWidth, thumbHeight, painter, FrameStyle.risen, color);
	}
}

//version(custom_widgets)
//private
class HorizontalScrollbar : ScrollbarBase {

	version(custom_widgets) {
		private MouseTrackingWidget thumb;

		override int getBarDim() {
			return thumb.width;
		}
	}

	override void setViewableArea(int a) {
		super.setViewableArea(a);

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nPage = a + 1;
			info.fMask = SIF_PAGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionX = thumbPosition;
			thumb.thumbWidth = thumbSize;
			thumb.redraw();
		} else static assert(0);

	}

	override void setMax(int a) {
		super.setMax(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nMin = 0;
			info.nMax = max;
			info.fMask = SIF_RANGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionX = thumbPosition;
			thumb.thumbWidth = thumbSize;
			thumb.redraw();
		}
	}

	override void setPosition(int a) {
		super.setPosition(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = position;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionX = thumbPosition();
			thumb.thumbWidth = thumbSize;
			thumb.redraw();
		} else static assert(0);
	}

	this(Widget parent) {
		super(parent);

		version(win32_widgets) {
			createWin32Window(this, "Scrollbar"w, "",
				0|WS_CHILD|WS_VISIBLE|SBS_HORZ|SBS_BOTTOMALIGN, 0);
		} else version(custom_widgets) {
			auto vl = new HorizontalLayout(this);
			auto leftButton = new ArrowButton(ArrowDirection.left, vl);
			leftButton.setClickRepeat(scrollClickRepeatInterval);
			thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.horizontal, vl);
			auto rightButton = new ArrowButton(ArrowDirection.right, vl);
			rightButton.setClickRepeat(scrollClickRepeatInterval);

			leftButton.tabStop = false;
			rightButton.tabStop = false;
			thumb.tabStop = false;

			leftButton.addEventListener(EventType.triggered, () {
				this.emitCommand!"scrolltopreviousline"();
				//informProgramThatUserChangedPosition(position - step());
			});
			rightButton.addEventListener(EventType.triggered, () {
				this.emitCommand!"scrolltonextline"();
				//informProgramThatUserChangedPosition(position + step());
			});

			thumb.thumbWidth = this.minWidth;
			thumb.thumbHeight = scaleWithDpi(16);

			thumb.addEventListener(EventType.change, () {
				auto maximumPossibleValue = thumb.width - thumb.thumbWidth;
				auto sx = maximumPossibleValue ? cast(int)(cast(long) thumb.positionX * (max()-viewableArea_) / maximumPossibleValue) : 0;

				//informProgramThatUserChangedPosition(sx);

				auto ev = new ScrollToPositionEvent(this, sx);
				ev.dispatch();
			});
		}
	}

	override int minHeight() { return scaleWithDpi(16); }
	override int maxHeight() { return scaleWithDpi(16); }
	override int minWidth() { return scaleWithDpi(48); }
}

final class ScrollToPositionEvent : Event {
	enum EventString = "scrolltoposition";

	this(Widget target, int value) {
		this.value = value;
		super(EventString, target);
	}

	immutable int value;

	override @property int intValue() {
		return value;
	}
}

//version(custom_widgets)
//private
class VerticalScrollbar : ScrollbarBase {

	version(custom_widgets) {
		override int getBarDim() {
			return thumb.height;
		}

		private MouseTrackingWidget thumb;
	}

	override void setViewableArea(int a) {
		super.setViewableArea(a);

		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nPage = a + 1;
			info.fMask = SIF_PAGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionY = thumbPosition;
			thumb.thumbHeight = thumbSize;
			thumb.redraw();
		} else static assert(0);

	}

	override void setMax(int a) {
		super.setMax(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.nMin = 0;
			info.nMax = max;
			info.fMask = SIF_RANGE;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionY = thumbPosition;
			thumb.thumbHeight = thumbSize;
			thumb.redraw();
		}
	}

	override void setPosition(int a) {
		super.setPosition(a);
		version(win32_widgets) {
			SCROLLINFO info;
			info.cbSize = info.sizeof;
			info.fMask = SIF_POS;
			info.nPos = position;
			SetScrollInfo(hwnd, SB_CTL, &info, true);
		} else version(custom_widgets) {
			thumb.positionY = thumbPosition;
			thumb.thumbHeight = thumbSize;
			thumb.redraw();
		} else static assert(0);
	}

	this(Widget parent) {
		super(parent);

		version(win32_widgets) {
			createWin32Window(this, "Scrollbar"w, "",
				0|WS_CHILD|WS_VISIBLE|SBS_VERT|SBS_RIGHTALIGN, 0);
		} else version(custom_widgets) {
			auto vl = new VerticalLayout(this);
			auto upButton = new ArrowButton(ArrowDirection.up, vl);
			upButton.setClickRepeat(scrollClickRepeatInterval);
			thumb = new MouseTrackingWidget(MouseTrackingWidget.Orientation.vertical, vl);
			auto downButton = new ArrowButton(ArrowDirection.down, vl);
			downButton.setClickRepeat(scrollClickRepeatInterval);

			upButton.addEventListener(EventType.triggered, () {
				this.emitCommand!"scrolltopreviousline"();
				//informProgramThatUserChangedPosition(position - step());
			});
			downButton.addEventListener(EventType.triggered, () {
				this.emitCommand!"scrolltonextline"();
				//informProgramThatUserChangedPosition(position + step());
			});

			thumb.thumbWidth = this.minWidth;
			thumb.thumbHeight = scaleWithDpi(16);

			thumb.addEventListener(EventType.change, () {
				auto maximumPossibleValue = thumb.height - thumb.thumbHeight;
				auto sy = maximumPossibleValue ? cast(int) (cast(long) thumb.positionY * (max()-viewableArea_) / maximumPossibleValue) : 0;

				auto ev = new ScrollToPositionEvent(this, sy);
				ev.dispatch();

				//informProgramThatUserChangedPosition(sy);
			});

			upButton.tabStop = false;
			downButton.tabStop = false;
			thumb.tabStop = false;
		}
	}

	override int minWidth() { return scaleWithDpi(16); }
	override int maxWidth() { return scaleWithDpi(16); }
	override int minHeight() { return scaleWithDpi(48); }
}


/++
	EXPERIMENTAL

	A widget specialized for being a container for other widgets.

	History:
		Added May 29, 2021. Not stabilized at this time.
+/
class WidgetContainer : Widget {
	this(Widget parent) {
		tabStop = false;
		super(parent);
	}

	override int maxHeight() {
		if(this.children.length == 1) {
			return saturatedSum(this.children[0].maxHeight, this.children[0].marginTop, this.children[0].marginBottom);
		} else {
			return int.max;
		}
	}

	override int maxWidth() {
		if(this.children.length == 1) {
			return saturatedSum(this.children[0].maxWidth, this.children[0].marginLeft, this.children[0].marginRight);
		} else {
			return int.max;
		}
	}

	/+

	override int minHeight() {
		int largest = 0;
		int margins = 0;
		int lastMargin = 0;
		foreach(child; children) {
			auto mh = child.minHeight();
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

	override int maxHeight() {
		int largest = 0;
		int margins = 0;
		int lastMargin = 0;
		foreach(child; children) {
			auto mh = child.maxHeight();
			if(mh == int.max)
				return int.max;
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

	override int minWidth() {
		int min;
		foreach(child; children) {
			auto cm = child.minWidth;
			if(cm > min)
				min = cm;
		}
		return min + paddingLeft + paddingRight;
	}

	override int minHeight() {
		int min;
		foreach(child; children) {
			auto cm = child.minHeight;
			if(cm > min)
				min = cm;
		}
		return min + paddingTop + paddingBottom;
	}

	override int maxHeight() {
		int largest = 0;
		int margins = 0;
		int lastMargin = 0;
		foreach(child; children) {
			auto mh = child.maxHeight();
			if(mh == int.max)
				return int.max;
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

	override int heightStretchiness() {
		int max;
		foreach(child; children) {
			auto c = child.heightStretchiness;
			if(c > max)
				max = c;
		}
		return max;
	}

	override int marginTop() {
		if(this.children.length)
			return this.children[0].marginTop;
		return 0;
	}
	+/
}

///
abstract class Layout : Widget {
	this(Widget parent) {
		tabStop = false;
		super(parent);
	}
}

/++
	Makes all children minimum width and height, placing them down
	left to right, top to bottom.

	Useful if you want to make a list of buttons that automatically
	wrap to a new line when necessary.
+/
class InlineBlockLayout : Layout {
	///
	this(Widget parent) { super(parent); }

	override void recomputeChildLayout() {
		registerMovement();

		int x = this.paddingLeft, y = this.paddingTop;

		int lineHeight;
		int previousMargin = 0;
		int previousMarginBottom = 0;

		foreach(child; children) {
			if(child.hidden)
				continue;
			if(cast(FixedPosition) child) {
				child.recomputeChildLayout();
				continue;
			}
			child.width = child.flexBasisWidth();
			if(child.width == 0)
				child.width = child.minWidth();
			if(child.width == 0)
				child.width = 32;

			child.height = child.flexBasisHeight();
			if(child.height == 0)
				child.height = child.minHeight();
			if(child.height == 0)
				child.height = 32;

			if(x + child.width + paddingRight > this.width) {
				x = this.paddingLeft;
				y += lineHeight;
				lineHeight = 0;
				previousMargin = 0;
				previousMarginBottom = 0;
			}

			auto margin = child.marginLeft;
			if(previousMargin > margin)
				margin = previousMargin;

			x += margin;

			child.x = x;
			child.y = y;

			int marginTopApplied;
			if(child.marginTop > previousMarginBottom) {
				child.y += child.marginTop;
				marginTopApplied = child.marginTop;
			}

			x += child.width;
			previousMargin = child.marginRight;

			if(child.marginBottom > previousMarginBottom)
				previousMarginBottom = child.marginBottom;

			auto h = child.height + previousMarginBottom + marginTopApplied;
			if(h > lineHeight)
				lineHeight = h;

			child.recomputeChildLayout();
		}

	}

	override int minWidth() {
		int min;
		foreach(child; children) {
			auto cm = child.minWidth;
			if(cm > min)
				min = cm;
		}
		return min + paddingLeft + paddingRight;
	}

	override int minHeight() {
		int min;
		foreach(child; children) {
			auto cm = child.minHeight;
			if(cm > min)
				min = cm;
		}
		return min + paddingTop + paddingBottom;
	}
}

/++
	A TabMessageWidget is a clickable row of tabs followed by a content area, very similar
	to the [TabWidget]. The difference is the TabMessageWidget only sends messages, whereas
	the [TabWidget] will automatically change pages of child widgets.

	This allows you to react to it however you see fit rather than having to
	be tied to just the new sets of child widgets.

	It sends the message in the form of `this.emitCommand!"changetab"();`.

	History:
		Added December 24, 2021 (dub v10.5)
+/
class TabMessageWidget : Widget {

	protected void tabIndexClicked(int item) {
		this.emitCommand!"changetab"();
	}

	/++
		Adds the a new tab to the control with the given title.

		Returns:
			The index of the newly added tab. You will need to know
			this index to refer to it later and to know which tab to
			change to when you get a changetab message.
	+/
	int addTab(string title, int pos = int.max) {
		version(win32_widgets) {
			TCITEM item;
			item.mask = TCIF_TEXT;
			WCharzBuffer buf = WCharzBuffer(title);
			item.pszText = buf.ptr;
			return cast(int) SendMessage(hwnd, TCM_INSERTITEM, pos, cast(LPARAM) &item);
		} else version(custom_widgets) {
			if(pos >= tabs.length) {
				tabs ~= title;
				redraw();
				return cast(int) tabs.length - 1;
			} else if(pos <= 0) {
				tabs = title ~ tabs;
				redraw();
				return 0;
			} else {
				tabs = tabs[0 .. pos] ~ title ~ title[pos .. $];
				redraw();
				return pos;
			}
		}
	}

	override void addChild(Widget child, int pos = int.max) {
		if(container)
			container.addChild(child, pos);
		else
			super.addChild(child, pos);
	}

	protected Widget makeContainer() {
		return new Widget(this);
	}

	private Widget container;

	override void recomputeChildLayout() {
		version(win32_widgets) {
			this.registerMovement();

			RECT rect;
			GetWindowRect(hwnd, &rect);

			auto left = rect.left;
			auto top = rect.top;

			TabCtrl_AdjustRect(hwnd, false, &rect);
			foreach(child; children) {
				if(!child.showing) continue;
				child.x = rect.left - left;
				child.y = rect.top - top;
				child.width = rect.right - rect.left;
				child.height = rect.bottom - rect.top;
				child.recomputeChildLayout();
			}
		} else version(custom_widgets) {
			this.registerMovement();
			foreach(child; children) {
				if(!child.showing) continue;
				child.x = 2;
				child.y = tabBarHeight + 2; // for the border
				child.width = width - 4; // for the border
				child.height = height - tabBarHeight - 2 - 2; // for the border
				child.recomputeChildLayout();
			}
		} else static assert(0);
	}

	version(custom_widgets)
		string[] tabs;

	this(Widget parent) {
		super(parent);

		tabStop = false;

		version(win32_widgets) {
			createWin32Window(this, WC_TABCONTROL, "", 0);
		} else version(custom_widgets) {
			addEventListener((ClickEvent event) {
				if(event.target !is this)
					return;
				if(event.clientY >= 0 && event.clientY < tabBarHeight) {
					auto t = (event.clientX / tabWidth);
					if(t >= 0 && t < tabs.length) {
						currentTab_ = t;
						tabIndexClicked(t);
						redraw();
					}
				}
			});
		} else static assert(0);

		this.container = makeContainer();
	}

	override int marginTop() { return 4; }
	override int paddingBottom() { return 4; }

	override int minHeight() {
		int max = 0;
		foreach(child; children)
			max = mymax(child.minHeight, max);


		version(win32_widgets) {
			RECT rect;
			rect.right = this.width;
			rect.bottom = max;
			TabCtrl_AdjustRect(hwnd, true, &rect);

			max = rect.bottom;
		} else {
			max += defaultLineHeight + 4;
		}


		return max;
	}

	version(win32_widgets)
	override int handleWmNotify(NMHDR* hdr, int code, out int mustReturn) {
		switch(code) {
			case TCN_SELCHANGE:
				auto sel = TabCtrl_GetCurSel(hwnd);
				tabIndexClicked(sel);
			break;
			default:
		}
		return 0;
	}

	version(custom_widgets) {
		private int currentTab_;
		private int tabBarHeight() { return defaultLineHeight; }
		int tabWidth() { return scaleWithDpi(80); }
	}

	version(win32_widgets)
	override void paint(WidgetPainter painter) {}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();

		draw3dFrame(0, tabBarHeight - 2, width, height - tabBarHeight + 2, painter, FrameStyle.risen, cs.background.color);

		int posX = 0;
		foreach(idx, title; tabs) {
			auto isCurrent = idx == getCurrentTab();

			painter.setClipRectangle(Point(posX, 0), tabWidth, tabBarHeight);

			draw3dFrame(posX, 0, tabWidth, tabBarHeight, painter, isCurrent ? FrameStyle.risen : FrameStyle.sunk, isCurrent ? cs.windowBackgroundColor : darken(cs.windowBackgroundColor, 0.1));
			painter.outlineColor = cs.foregroundColor;
			painter.drawText(Point(posX + 4, 2), title, Point(posX + tabWidth, tabBarHeight - 2), TextAlignment.VerticalCenter);

			if(isCurrent) {
				painter.outlineColor = cs.windowBackgroundColor;
				painter.fillColor = Color.transparent;
				painter.drawLine(Point(posX + 2, tabBarHeight - 1), Point(posX + tabWidth, tabBarHeight - 1));
				painter.drawLine(Point(posX + 2, tabBarHeight - 2), Point(posX + tabWidth, tabBarHeight - 2));

				painter.outlineColor = Color.white;
				painter.drawPixel(Point(posX + 1, tabBarHeight - 1));
				painter.drawPixel(Point(posX + 1, tabBarHeight - 2));
				painter.outlineColor = cs.activeTabColor;
				painter.drawPixel(Point(posX, tabBarHeight - 1));
			}

			posX += tabWidth - 2;
		}
	}

	///
	@scriptable
	void setCurrentTab(int item) {
		version(win32_widgets)
			TabCtrl_SetCurSel(hwnd, item);
		else version(custom_widgets)
			currentTab_ = item;
		else static assert(0);

		tabIndexClicked(item);
	}

	///
	@scriptable
	int getCurrentTab() {
		version(win32_widgets)
			return TabCtrl_GetCurSel(hwnd);
		else version(custom_widgets)
			return currentTab_; // FIXME
		else static assert(0);
	}

	///
	@scriptable
	void removeTab(int item) {
		if(item && item == getCurrentTab())
			setCurrentTab(item - 1);

		version(win32_widgets) {
			TabCtrl_DeleteItem(hwnd, item);
		}

		for(int a = item; a < children.length - 1; a++)
			this._children[a] = this._children[a + 1];
		this._children = this._children[0 .. $-1];
	}

}


/++
	A tab widget is a set of clickable tab buttons followed by a content area.


	Tabs can change existing content or can be new pages.

	When the user picks a different tab, a `change` message is generated.
+/
class TabWidget : TabMessageWidget {
	this(Widget parent) {
		super(parent);
	}

	override protected Widget makeContainer() {
		return null;
	}

	override void addChild(Widget child, int pos = int.max) {
		if(auto twp = cast(TabWidgetPage) child) {
			Widget.addChild(child, pos);
			if(pos == int.max)
				pos = cast(int) this.children.length - 1;

			super.addTab(twp.title, pos); // need to bypass the override here which would get into a loop...

			if(pos != getCurrentTab) {
				child.showing = false;
			}
		} else {
			assert(0, "Don't add children directly to a tab widget, instead add them to a page (see addPage)");
		}
	}

	// FIXME: add tab icons at some point, Windows supports them
	/++
		Adds a page and its associated tab with the given label to the widget.

		Returns:
			The added page object, to which you can add other widgets.
	+/
	@scriptable
	TabWidgetPage addPage(string title) {
		return new TabWidgetPage(title, this);
	}

	/++
		Gets the page at the given tab index, or `null` if the index is bad.

		History:
			Added December 24, 2021.
	+/
	TabWidgetPage getPage(int index) {
		if(index < this.children.length)
			return null;
		return cast(TabWidgetPage) this.children[index];
	}

	/++
		While you can still use the addTab from the parent class,
		*strongly* recommend you use [addPage] insteaad.

		History:
			Added December 24, 2021 to fulful the interface
			requirement that came from adding [TabMessageWidget].

			You should not use it though since the [addPage] function
			is much easier to use here.
	+/
	override int addTab(string title, int pos = int.max) {
		auto p = addPage(title);
		foreach(idx, child; this.children)
			if(child is p)
				return cast(int) idx;
		return -1;
	}

	protected override void tabIndexClicked(int item) {
		foreach(idx, child; children) {
			child.showing(false, false); // batch the recalculates for the end
		}

		foreach(idx, child; children) {
			if(idx == item) {
				child.showing(true, false);
				if(parentWindow) {
					auto f = parentWindow.getFirstFocusable(child);
					if(f)
						f.focus();
				}
				recomputeChildLayout();
			}
		}

		version(win32_widgets) {
			InvalidateRect(hwnd, null, true);
		} else version(custom_widgets) {
			this.redraw();
		}
	}

}

/++
	A page widget is basically a tab widget with hidden tabs. It is also sometimes called a "StackWidget".

	You add [TabWidgetPage]s to it.
+/
class PageWidget : Widget {
	this(Widget parent) {
		super(parent);
	}

	override int minHeight() {
		int max = 0;
		foreach(child; children)
			max = mymax(child.minHeight, max);

		return max;
	}


	override void addChild(Widget child, int pos = int.max) {
		if(auto twp = cast(TabWidgetPage) child) {
			super.addChild(child, pos);
			if(pos == int.max)
				pos = cast(int) this.children.length - 1;

			if(pos != getCurrentTab) {
				child.showing = false;
			}
		} else {
			assert(0, "Don't add children directly to a page widget, instead add them to a page (see addPage)");
		}
	}

	override void recomputeChildLayout() {
		this.registerMovement();
		foreach(child; children) {
			child.x = 0;
			child.y = 0;
			child.width = width;
			child.height = height;
			child.recomputeChildLayout();
		}
	}

	private int currentTab_;

	///
	@scriptable
	void setCurrentTab(int item) {
		currentTab_ = item;

		showOnly(item);
	}

	///
	@scriptable
	int getCurrentTab() {
		return currentTab_;
	}

	///
	@scriptable
	void removeTab(int item) {
		if(item && item == getCurrentTab())
			setCurrentTab(item - 1);

		for(int a = item; a < children.length - 1; a++)
			this._children[a] = this._children[a + 1];
		this._children = this._children[0 .. $-1];
	}

	///
	@scriptable
	TabWidgetPage addPage(string title) {
		return new TabWidgetPage(title, this);
	}

	private void showOnly(int item) {
		foreach(idx, child; children)
			if(idx == item) {
				child.show();
				child.queueRecomputeChildLayout();
			} else {
				child.hide();
			}
	}
}

/++

+/
class TabWidgetPage : Widget {
	string title;
	this(string title, Widget parent) {
		this.title = title;
		this.tabStop = false;
		super(parent);

		///*
		version(win32_widgets) {
			createWin32Window(this, Win32Class!"arsd_minigui_TabWidgetPage"w, "", 0);
		}
		//*/
	}

	override int minHeight() {
		int sum = 0;
		foreach(child; children)
			sum += child.minHeight();
		return sum;
	}
}

version(none)
/++
	A collapsable sidebar is a container that shows if its assigned width is greater than its minimum and otherwise shows as a button.

	I think I need to modify the layout algorithms to support this.
+/
class CollapsableSidebar : Widget {

}

/// Stacks the widgets vertically, taking all the available width for each child.
class VerticalLayout : Layout {
	// most of this is intentionally blank - widget's default is vertical layout right now
	///
	this(Widget parent) { super(parent); }

	/++
		Sets a max width for the layout so you don't have to subclass. The max width
		is in device-independent pixels, meaning pixels at 96 dpi that are auto-scaled.

		History:
			Added November 29, 2021 (dub v10.5)
	+/
	this(int maxWidth, Widget parent) {
		this.mw = maxWidth;
		super(parent);
	}

	private int mw = int.max;

	override int maxWidth() { return scaleWithDpi(mw); }
}

/// Stacks the widgets horizontally, taking all the available height for each child.
class HorizontalLayout : Layout {
	///
	this(Widget parent) { super(parent); }

	/++
		Sets a max height for the layout so you don't have to subclass. The max height
		is in device-independent pixels, meaning pixels at 96 dpi that are auto-scaled.

		History:
			Added November 29, 2021 (dub v10.5)
	+/
	this(int maxHeight, Widget parent) {
		this.mh = maxHeight;
		super(parent);
	}

	private int mh = 0;



	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}

	override int minHeight() {
		int largest = 0;
		int margins = 0;
		int lastMargin = 0;
		foreach(child; children) {
			auto mh = child.minHeight();
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

	override int maxHeight() {
		if(mh != 0)
			return mymax(minHeight, scaleWithDpi(mh));

		int largest = 0;
		int margins = 0;
		int lastMargin = 0;
		foreach(child; children) {
			auto mh = child.maxHeight();
			if(mh == int.max)
				return int.max;
			if(mh > largest)
				largest = mh;
			margins += mymax(lastMargin, child.marginTop());
			lastMargin = child.marginBottom();
		}
		return largest + margins;
	}

	override int heightStretchiness() {
		int max;
		foreach(child; children) {
			auto c = child.heightStretchiness;
			if(c > max)
				max = c;
		}
		return max;
	}
}

version(win32_widgets)
private
extern(Windows)
LRESULT DoubleBufferWndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) nothrow {
	Widget* pwin = hwnd in Widget.nativeMapping;
	if(pwin is null)
		return DefWindowProc(hwnd, message, wparam, lparam);
	SimpleWindow win = pwin.simpleWindowWrappingHwnd;
	if(win is null)
		return DefWindowProc(hwnd, message, wparam, lparam);

	switch(message) {
		case WM_SIZE:
			auto width = LOWORD(lparam);
			auto height = HIWORD(lparam);

			auto hdc = GetDC(hwnd);
			auto hdcBmp = CreateCompatibleDC(hdc);

			// FIXME: could this be more efficient? it never relinquishes a large bitmap
			if(width > win.bmpWidth || height > win.bmpHeight) {
				auto oldBuffer = win.buffer;
				win.buffer = CreateCompatibleBitmap(hdc, width, height);

				if(oldBuffer)
					DeleteObject(oldBuffer);

				win.bmpWidth = width;
				win.bmpHeight = height;
			}

			// just always erase it upon resizing so minigui can draw over with a clean slate
			auto oldBmp = SelectObject(hdcBmp, win.buffer);

			auto brush = GetSysColorBrush(COLOR_3DFACE);
			RECT r;
			r.left = 0;
			r.top = 0;
			r.right = width;
			r.bottom = height;
			FillRect(hdcBmp, &r, brush);

			SelectObject(hdcBmp, oldBmp);
			DeleteDC(hdcBmp);
			ReleaseDC(hwnd, hdc);
		break;
		case WM_PAINT:
			if(win.buffer is null)
				goto default;

			BITMAP bm;
			PAINTSTRUCT ps;

			HDC hdc = BeginPaint(hwnd, &ps);

			HDC hdcMem = CreateCompatibleDC(hdc);
			HBITMAP hbmOld = SelectObject(hdcMem, win.buffer);

			GetObject(win.buffer, bm.sizeof, &bm);

			BitBlt(hdc, 0, 0, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, SRCCOPY);

			SelectObject(hdcMem, hbmOld);
			DeleteDC(hdcMem);
			EndPaint(hwnd, &ps);
		break;
		default:
			return DefWindowProc(hwnd, message, wparam, lparam);
	}

	return 0;
}

private wstring Win32Class(wstring name)() {
	static bool classRegistered;
	if(!classRegistered) {
		HINSTANCE hInstance = cast(HINSTANCE) GetModuleHandle(null);
		WNDCLASSEX wc;
		wc.cbSize = wc.sizeof;
		wc.hInstance = hInstance;
		wc.hbrBackground = cast(HBRUSH) (COLOR_3DFACE+1); // GetStockObject(WHITE_BRUSH);
		wc.lpfnWndProc = &DoubleBufferWndProc;
		wc.lpszClassName = name.ptr;
		if(!RegisterClassExW(&wc))
			throw new Exception("RegisterClass ");// ~ to!string(GetLastError()));
		classRegistered = true;
	}

		return name;
}

/+
version(win32_widgets)
extern(Windows)
private
LRESULT CustomDrawWindowProc(HWND hWnd, UINT iMessage, WPARAM wParam, LPARAM lParam) nothrow {
	switch(iMessage) {
		case WM_PAINT:
			if(auto te = hWnd in Widget.nativeMapping) {
				try {
					//te.redraw();
					writeln(te, " drawing");
				} catch(Exception) {}
			}
			return DefWindowProc(hWnd, iMessage, wParam, lParam);
		default:
			return DefWindowProc(hWnd, iMessage, wParam, lParam);
	}
}
+/


/++
	A widget specifically designed to hold other widgets.

	History:
		Added July 1, 2021
+/
class ContainerWidget : Widget {
	this(Widget parent) {
		super(parent);
		this.tabStop = false;

		version(win32_widgets) {
			createWin32Window(this, Win32Class!"arsd_minigui_ContainerWidget"w, "", 0);
		}
	}
}

/++
	A widget that takes your widget, puts scroll bars around it, and sends
	messages to it when the user scrolls. Unlike [ScrollableWidget], it makes
	no effort to automatically scroll or clip its child widgets - it just sends
	the messages.


	A ScrollMessageWidget notifies you with a [ScrollEvent] that it has changed.
	The scroll coordinates are all given in a unit you interpret as you wish. One
	of these units is moved on each press of the arrow buttons and represents the
	smallest amount the user can scroll. The intention is for this to be one line,
	one item in a list, one row in a table, etc. Whatever makes sense for your widget
	in each direction that the user might be interested in.

	You can set a "page size" with the [step] property. (Yes, I regret the name...)
	This is the amount it jumps when the user pressed page up and page down, or clicks
	in the exposed part of the scroll bar.

	You should add child content to the ScrollMessageWidget. However, it is important to
	note that the coordinates are always independent of the scroll position! It is YOUR
	responsibility to do any necessary transforms, clipping, etc., while drawing the
	content and interpreting mouse events if they are supposed to change with the scroll.
	This is in contrast to the (likely to be deprecated) [ScrollableWidget], which tries
	to maintain the illusion that there's an infinite space. The [ScrollMessageWidget] gives
	you more control (which can be considerably more efficient and adapted to your actual data)
	at the expense of you also needing to be aware of its reality.

	Please note that it does NOT react to mouse wheel events or various keyboard events as of
	version 10.3. Maybe this will change in the future.... but for now you must call
	[addDefaultKeyboardListeners] and/or [addDefaultWheelListeners] or set something up yourself.
+/
class ScrollMessageWidget : Widget {
	this(Widget parent) {
		super(parent);

		container = new Widget(this);
		hsb = new HorizontalScrollbar(this);
		vsb = new VerticalScrollbar(this);

		hsb.addEventListener("scrolltonextline", {
			hsb.setPosition(hsb.position + movementPerButtonClickH_);
			notify();
		});
		hsb.addEventListener("scrolltopreviousline", {
			hsb.setPosition(hsb.position - movementPerButtonClickH_);
			notify();
		});
		vsb.addEventListener("scrolltonextline", {
			vsb.setPosition(vsb.position + movementPerButtonClickV_);
			notify();
		});
		vsb.addEventListener("scrolltopreviousline", {
			vsb.setPosition(vsb.position - movementPerButtonClickV_);
			notify();
		});
		hsb.addEventListener("scrolltonextpage", {
			hsb.setPosition(hsb.position + hsb.step_);
			notify();
		});
		hsb.addEventListener("scrolltopreviouspage", {
			hsb.setPosition(hsb.position - hsb.step_);
			notify();
		});
		vsb.addEventListener("scrolltonextpage", {
			vsb.setPosition(vsb.position + vsb.step_);
			notify();
		});
		vsb.addEventListener("scrolltopreviouspage", {
			vsb.setPosition(vsb.position - vsb.step_);
			notify();
		});
		hsb.addEventListener("scrolltoposition", (Event event) {
			hsb.setPosition(event.intValue);
			notify();
		});
		vsb.addEventListener("scrolltoposition", (Event event) {
			vsb.setPosition(event.intValue);
			notify();
		});


		tabStop = false;
		container.tabStop = false;
		magic = true;
	}

	private int movementPerButtonClickH_ = 1;
	private int movementPerButtonClickV_ = 1;
	public void movementPerButtonClick(int h, int v) {
		movementPerButtonClickH_ = h;
		movementPerButtonClickV_ = v;
	}

	/++
		Add default event listeners for keyboard and mouse wheel scrolling shortcuts.


		The defaults for [addDefaultWheelListeners] are:

			$(LIST
				* Mouse wheel scrolls vertically
				* Alt key + mouse wheel scrolls horiontally
				* Shift + mouse wheel scrolls faster.
				* Any mouse click or wheel event will focus the inner widget if it has `tabStop = true`
			)

		The defaults for [addDefaultKeyboardListeners] are:

			$(LIST
				* Arrow keys scroll by the given amounts
				* Shift+arrow keys scroll by the given amounts times the given shiftMultiplier
				* Page up and down scroll by the vertical viewable area
				* Home and end scroll to the start and end of the verticle viewable area.
				* Alt + page up / page down / home / end will horizonally scroll instead of vertical.
			)

		My recommendation is to change the scroll amounts if you are scrolling by pixels, but otherwise keep them at one line.

		Params:
			horizontalArrowScrollAmount =
			verticalArrowScrollAmount =
			verticalWheelScrollAmount = how much should be scrolled vertically on each tick of the mouse wheel
			horizontalWheelScrollAmount = how much should be scrolled horizontally when alt is held on each tick of the mouse wheel
			shiftMultiplier = multiplies the scroll amount by this when shift is held
	+/
	void addDefaultKeyboardListeners(int verticalArrowScrollAmount = 1, int horizontalArrowScrollAmount = 1, int shiftMultiplier = 3) {
		defaultKeyboardListener_verticalArrowScrollAmount = verticalArrowScrollAmount;
		defaultKeyboardListener_horizontalArrowScrollAmount = horizontalArrowScrollAmount;
		defaultKeyboardListener_shiftMultiplier = shiftMultiplier;

		container.addEventListener(&defaultKeyboardListener);
	}

	/// ditto
	void addDefaultWheelListeners(int verticalWheelScrollAmount = 1, int horizontalWheelScrollAmount = 1, int shiftMultiplier = 3) {
		auto _this = this;
		container.addEventListener((scope ClickEvent ce) {

			//if(ce.target && ce.target.tabStop)
				//ce.target.focus();

			// ctrl is reserved for the application
			if(ce.ctrlKey)
				return;

			if(horizontalWheelScrollAmount == 0 && ce.altKey)
				return;

			if(shiftMultiplier == 0 && ce.shiftKey)
				return;

			if(ce.button == MouseButton.wheelDown) {
				if(ce.altKey)
					_this.scrollRight(horizontalWheelScrollAmount * (ce.shiftKey ? shiftMultiplier : 1));
				else
					_this.scrollDown(verticalWheelScrollAmount * (ce.shiftKey ? shiftMultiplier : 1));
			} else if(ce.button == MouseButton.wheelUp) {
				if(ce.altKey)
					_this.scrollLeft(horizontalWheelScrollAmount * (ce.shiftKey ? shiftMultiplier : 1));
				else
					_this.scrollUp(verticalWheelScrollAmount * (ce.shiftKey ? shiftMultiplier : 1));
			}
		});
	}

	int defaultKeyboardListener_verticalArrowScrollAmount = 1;
	int defaultKeyboardListener_horizontalArrowScrollAmount = 1;
	int defaultKeyboardListener_shiftMultiplier = 3;

	void defaultKeyboardListener(scope KeyDownEvent ke) {
		switch(ke.key) {
			case Key.Left:
				this.scrollLeft(defaultKeyboardListener_horizontalArrowScrollAmount * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
			break;
			case Key.Right:
				this.scrollRight(defaultKeyboardListener_horizontalArrowScrollAmount * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
			break;
			case Key.Up:
				this.scrollUp(defaultKeyboardListener_verticalArrowScrollAmount * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
			break;
			case Key.Down:
				this.scrollDown(defaultKeyboardListener_verticalArrowScrollAmount * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
			break;
			case Key.PageUp:
				if(ke.altKey)
					this.scrollLeft(this.vsb.viewableArea_ * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
				else
					this.scrollUp(this.vsb.viewableArea_ * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
			break;
			case Key.PageDown:
				if(ke.altKey)
					this.scrollRight(this.vsb.viewableArea_ * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
				else
					this.scrollDown(this.vsb.viewableArea_ * (ke.shiftKey ? defaultKeyboardListener_shiftMultiplier : 1));
			break;
			case Key.Home:
				if(ke.altKey)
					this.scrollLeft(short.max * 16);
				else
					this.scrollUp(short.max * 16);
			break;
			case Key.End:
				if(ke.altKey)
					this.scrollRight(short.max * 16);
				else
					this.scrollDown(short.max * 16);
			break;

			default:
				// ignore, not for us.
		}
	}

	/++
		Scrolls the given amount.

		History:
			The scroll up and down functions was here in the initial release of the class, but the `amount` parameter and left/right functions were added on September 28, 2021.
	+/
	void scrollUp(int amount = 1) {
		vsb.setPosition(vsb.position.NonOverflowingInt - amount);
		notify();
	}
	/// ditto
	void scrollDown(int amount = 1) {
		vsb.setPosition(vsb.position.NonOverflowingInt + amount);
		notify();
	}
	/// ditto
	void scrollLeft(int amount = 1) {
		hsb.setPosition(hsb.position.NonOverflowingInt - amount);
		notify();
	}
	/// ditto
	void scrollRight(int amount = 1) {
		hsb.setPosition(hsb.position.NonOverflowingInt + amount);
		notify();
	}

	///
	VerticalScrollbar verticalScrollBar() { return vsb; }
	///
	HorizontalScrollbar horizontalScrollBar() { return hsb; }

	void notify() {
		static bool insideNotify;

		if(insideNotify)
			return; // avoid the recursive call, even if it isn't strictly correct

		insideNotify = true;
		scope(exit) insideNotify = false;

		this.emit!ScrollEvent();
	}

	mixin Emits!ScrollEvent;

	///
	Point position() {
		return Point(hsb.position, vsb.position);
	}

	///
	void setPosition(int x, int y) {
		hsb.setPosition(x);
		vsb.setPosition(y);
	}

	///
	void setPageSize(int unitsX, int unitsY) {
		hsb.setStep(unitsX);
		vsb.setStep(unitsY);
	}

	/// Always call this BEFORE setViewableArea
	void setTotalArea(int width, int height) {
		hsb.setMax(width);
		vsb.setMax(height);
	}

	/++
		Always set the viewable area AFTER setitng the total area if you are going to change both.
		NEVER call this from inside a scroll event. This includes through recomputeChildLayout.
		If you need to do that, use [queueRecomputeChildLayout].
	+/
	void setViewableArea(int width, int height) {

		// actually there IS A need to dothis cuz the max might have changed since then
		//if(width == hsb.viewableArea_ && height == vsb.viewableArea_)
			//return; // no need to do what is already done
		hsb.setViewableArea(width);
		vsb.setViewableArea(height);

		bool needsNotify = false;

		// FIXME: if at any point the rhs is outside the scrollbar, we need
		// to reset to 0. but it should remember the old position in case the
		// window resizes again, so it can kinda return ot where it was.
		//
		// so there's an inner position and a exposed position. the exposed one is always in bounds and thus may be (0,0)
		if(width >= hsb.max) {
			// there's plenty of room to display it all so we need to reset to zero
			// FIXME: adjust so it matches the note above
			hsb.setPosition(0);
			needsNotify = true;
		}
		if(height >= vsb.max) {
			// there's plenty of room to display it all so we need to reset to zero
			// FIXME: adjust so it matches the note above
			vsb.setPosition(0);
			needsNotify = true;
		}
		if(needsNotify)
			notify();
	}

	private bool magic;
	override void addChild(Widget w, int position = int.max) {
		if(magic)
			container.addChild(w, position);
		else
			super.addChild(w, position);
	}

	override void recomputeChildLayout() {
		if(hsb is null || vsb is null || container is null) return;

		registerMovement();

		enum BUTTON_SIZE = 16;

		hsb.height = scaleWithDpi(BUTTON_SIZE); // FIXME? are tese 16s sane?
		hsb.x = 0;
		hsb.y = this.height - hsb.height;

		vsb.width = scaleWithDpi(BUTTON_SIZE); // FIXME?
		vsb.x = this.width - vsb.width;
		vsb.y = 0;

		auto vsb_width = vsb.showing ? vsb.width : 0;
		auto hsb_height = hsb.showing ? hsb.height : 0;

		hsb.width = this.width - vsb_width;
		vsb.height = this.height - hsb_height;

		hsb.recomputeChildLayout();
		vsb.recomputeChildLayout();

		if(this.header is null) {
			container.x = 0;
			container.y = 0;
			container.width = this.width - vsb_width;
			container.height = this.height - hsb_height;
			container.recomputeChildLayout();
		} else {
			header.x = 0;
			header.y = 0;
			header.width = this.width - vsb_width;
			header.height = scaleWithDpi(BUTTON_SIZE); // size of the button
			header.recomputeChildLayout();

			container.x = 0;
			container.y = scaleWithDpi(BUTTON_SIZE);
			container.width = this.width - vsb_width;
			container.height = this.height - hsb_height - scaleWithDpi(BUTTON_SIZE);
			container.recomputeChildLayout();
		}
	}

	private HorizontalScrollbar hsb;
	private VerticalScrollbar vsb;
	Widget container;
	private Widget header;

	/++
		Adds a fixed-size "header" widget. This will be positioned to align with the scroll up button.

		History:
			Added September 27, 2021 (dub v10.3)
	+/
	Widget getHeader() {
		if(this.header is null) {
			magic = false;
			scope(exit) magic = true;
			this.header = new Widget(this);
			queueRecomputeChildLayout();
		}
		return this.header;
	}

	/++
		Makes an effort to ensure as much of `rect` is visible as possible, scrolling if necessary.

		History:
			Added January 3, 2023 (dub v11.0)
	+/
	void scrollIntoView(Rectangle rect) {
		Rectangle viewRectangle = Rectangle(position, Size(hsb.viewableArea_, vsb.viewableArea_));

		// import std.stdio;writeln(viewRectangle, "\n", rect, " ", viewRectangle.contains(rect.lowerRight - Point(1, 1)));

		// the lower right is exclusive normally
		auto test = rect.lowerRight;
		if(test.x > 0) test.x--;
		if(test.y > 0) test.y--;

		if(!viewRectangle.contains(test) || !viewRectangle.contains(rect.upperLeft)) {
			// try to scroll only one dimension at a time if we can
			if(!viewRectangle.contains(Point(test.x, position.y)) || !viewRectangle.contains(Point(rect.upperLeft.x, position.y)))
				setPosition(rect.upperLeft.x, position.y);
			if(!viewRectangle.contains(Point(position.x, test.y)) || !viewRectangle.contains(Point(position.x, rect.upperLeft.y)))
				setPosition(position.x, rect.upperLeft.y);
		}

	}

	override int minHeight() {
		int min = mymax(container ? container.minHeight : 0, (verticalScrollBar.showing ? verticalScrollBar.minHeight : 0));
		if(header !is null)
			min += header.minHeight;
		if(horizontalScrollBar.showing)
			min += horizontalScrollBar.minHeight;
		return min;
	}

	override int maxHeight() {
		int max = container ? container.maxHeight : int.max;
		if(max == int.max)
			return max;
		if(horizontalScrollBar.showing)
			max += horizontalScrollBar.minHeight;
		return max;
	}

	static class Style : Widget.Style {
		override WidgetBackground background() {
			return WidgetBackground(WidgetPainter.visualTheme.windowBackgroundColor);
		}
	}
	mixin OverrideStyle!Style;
}

/++
	$(IMG //arsdnet.net/minigui-screenshots/windows/ScrollMessageWidget.png, A box saying "baby will" with three round buttons inside it for the options of "eat", "cry", and "sleep")
	$(IMG //arsdnet.net/minigui-screenshots/linux/ScrollMessageWidget.png, Same thing, but in the default Linux theme.)
+/
version(minigui_screenshots)
@Screenshot("ScrollMessageWidget")
unittest {
	auto window = new Window("ScrollMessageWidget");

	auto smw = new ScrollMessageWidget(window);
	smw.addDefaultKeyboardListeners();
	smw.addDefaultWheelListeners();

	window.loop();
}

/++
	Bypasses automatic layout for its children, using manual positioning and sizing only.
	While you need to manually position them, you must ensure they are inside the StaticLayout's
	bounding box to avoid undefined behavior.

	You should almost never use this.
+/
class StaticLayout : Layout {
	///
	this(Widget parent) { super(parent); }
	override void recomputeChildLayout() {
		registerMovement();
		foreach(child; children)
			child.recomputeChildLayout();
	}
}

/++
	Bypasses automatic positioning when being laid out. It is your responsibility to make
	room for this widget in the parent layout.

	Its children are laid out normally, unless there is exactly one, in which case it takes
	on the full size of the `StaticPosition` object (if you plan to put stuff on the edge, you
	can do that with `padding`).
+/
class StaticPosition : Layout {
	///
	this(Widget parent) { super(parent); }

	override void recomputeChildLayout() {
		registerMovement();
		if(this.children.length == 1) {
			auto child = children[0];
			child.x = 0;
			child.y = 0;
			child.width = this.width;
			child.height = this.height;
			child.recomputeChildLayout();
		} else
		foreach(child; children)
			child.recomputeChildLayout();
	}

	alias width = typeof(super).width;
	alias height = typeof(super).height;

	@property int width(int w) @nogc pure @safe nothrow {
		return this._width = w;
	}

	@property int height(int w) @nogc pure @safe nothrow {
		return this._height = w;
	}

}

/++
	FixedPosition is like [StaticPosition], but its coordinates
	are always relative to the viewport, meaning they do not scroll with
	the parent content.
+/
class FixedPosition : StaticPosition {
	///
	this(Widget parent) { super(parent); }
}

version(win32_widgets)
int processWmCommand(HWND parentWindow, HWND handle, ushort cmd, ushort idm) {
	if(true) {
		// cmd == 0 = menu, cmd == 1 = accelerator
		if(auto item = idm in Action.mapping) {
			foreach(handler; (*item).triggered)
				handler();
		/*
			auto event = new Event("triggered", *item);
			event.button = idm;
			event.dispatch();
		*/
			return 0;
		}
	}
	if(handle)
	if(auto widgetp = handle in Widget.nativeMapping) {
		(*widgetp).handleWmCommand(cmd, idm);
		return 0;
	}
	return 1;
}


///
class Window : Widget {
	Widget[] mouseCapturedBy;
	void captureMouse(Widget byWhom) {
		assert(byWhom !is null);
		if(mouseCapturedBy.length > 0) {
			auto cc = mouseCapturedBy[$-1];
			if(cc is byWhom)
				return; // or should it throw?
			auto par = byWhom;
			while(par) {
				if(cc is par)
					goto allowed;
				par = par.parent;
			}

			throw new Exception("mouse is already captured by other widget");
		}
		allowed:
		mouseCapturedBy ~= byWhom;
		if(mouseCapturedBy.length == 1)
			win.grabInput(false, true, false);
		//void grabInput(bool keyboard = true, bool mouse = true, bool confine = false) {
	}
	void releaseMouseCapture() {
		if(mouseCapturedBy.length == 0)
			return; // or should it throw?
		mouseCapturedBy = mouseCapturedBy[0 .. $-1];
		mouseCapturedBy.assumeSafeAppend();
		if(mouseCapturedBy.length == 0)
			win.releaseInputGrab();
	}


	/++

	+/
	MessageBoxButton messageBox(string title, string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
		return .messageBox(this, title, message, style, icon);
	}

	/// ditto
	int messageBox(string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
		return messageBox(null, message, style, icon);
	}


	/++
		Sets the window icon which is often seen in title bars and taskbars.

		A future plan is to offer an overload that takes an array too for multiple sizes, but right now you should probably set 16x16 or 32x32 images here.

		History:
			Added April 5, 2022 (dub v10.8)
	+/
	@property void icon(MemoryImage icon) {
		if(win && icon)
			win.icon = icon;
	}

	// forwarder to the top-level icon thing so this doesn't conflict too much with the UDAs seen inside the class ins ome older examples
	// this does NOT change the icon on the window! That's what the other overload is for
	static @property .icon icon(GenericIcons i) {
		return .icon(i);
	}

	///
	@scriptable
	@property bool focused() {
		return win.focused;
	}

	static class Style : Widget.Style {
		override WidgetBackground background() {
			version(custom_widgets)
				return WidgetBackground(WidgetPainter.visualTheme.windowBackgroundColor);
			else version(win32_widgets)
				return WidgetBackground(Color.transparent);
			else static assert(0);
		}
	}
	mixin OverrideStyle!Style;

	/++
		Gives the height of a line according to the default font. You should try to use your computed font instead of this, but until May 8, 2021, this was the only real option.
	+/
	deprecated("Use the non-static Widget.defaultLineHeight() instead") static int lineHeight() {
		return lineHeightNotDeprecatedButShouldBeSinceItIsJustAFallback();
	}

	private static int lineHeightNotDeprecatedButShouldBeSinceItIsJustAFallback() {
		OperatingSystemFont font;
		if(auto vt = WidgetPainter.visualTheme) {
			font = vt.defaultFontCached(96); // FIXME
		}

		if(font is null) {
			static int defaultHeightCache;
			if(defaultHeightCache == 0) {
				font = new OperatingSystemFont;
				font.loadDefault;
				defaultHeightCache = font.height();// * 5 / 4;
			}
			return defaultHeightCache;
		}

		return font.height();// * 5 / 4;
	}

	Widget focusedWidget;

	private SimpleWindow win_;

	@property {
		/++
			Provides access to the underlying [SimpleWindow]. Note that changing properties on this window may disconnect minigui's event dispatchers.

			History:
				Prior to June 21, 2021, it was a public (but undocumented) member. Now it a semi-protected property.
		+/
		public SimpleWindow win() {
			return win_;
		}
		///
		protected void win(SimpleWindow w) {
			win_ = w;
		}
	}

	/// YOU ALMOST CERTAINLY SHOULD NOT USE THIS. This is really only for special purposes like pseudowindows or popup windows doing their own thing.
	this(Widget p) {
		tabStop = false;
		super(p);
	}

	private void actualRedraw() {
		if(recomputeChildLayoutRequired)
			recomputeChildLayoutEntry();
		if(!showing) return;

		assert(parentWindow !is null);

		auto w = drawableWindow;
		if(w is null)
			w = parentWindow.win;

		if(w.closed())
			return;

		auto ugh = this.parent;
		int lox, loy;
		while(ugh) {
			lox += ugh.x;
			loy += ugh.y;
			ugh = ugh.parent;
		}
		auto painter = w.draw(true);
		privatePaint(WidgetPainter(painter, this), lox, loy, Rectangle(0, 0, int.max, int.max), false, willDraw());
	}


	private bool skipNextChar = false;

	/++
		Creates a window from an existing [SimpleWindow]. This constructor attaches various event handlers to the SimpleWindow object which may overwrite your existing handlers.

		This constructor is intended primarily for internal use and may be changed to `protected` later.
	+/
	this(SimpleWindow win) {

		static if(UsingSimpledisplayX11) {
			win.discardAdditionalConnectionState = &discardXConnectionState;
			win.recreateAdditionalConnectionState = &recreateXConnectionState;
		}

		tabStop = false;
		super(null);
		this.win = win;

		win.addEventListener((Widget.RedrawEvent) {
			if(win.eventQueued!RecomputeEvent) {
				// writeln("skipping");
				return; // let the recompute event do the actual redraw
			}
			this.actualRedraw();
		});

		win.addEventListener((Widget.RecomputeEvent) {
			recomputeChildLayoutEntry();
			if(win.eventQueued!RedrawEvent)
				return; // let the queued one do it
			else {
				// writeln("drawing");
				this.actualRedraw(); // if not queued, it needs to be done now anyway
			}
		});

		this.width = win.width;
		this.height = win.height;
		this.parentWindow = this;

		win.closeQuery = () {
			if(this.emit!ClosingEvent())
				win.close();
		};
		win.onClosing = () {
			this.emit!ClosedEvent();
		};

		win.windowResized = (int w, int h) {
			this.width = w;
			this.height = h;
			queueRecomputeChildLayout();
			// this causes a HUGE performance problem for no apparent benefit, hence the commenting
			//version(win32_widgets)
				//InvalidateRect(hwnd, null, true);
			redraw();
		};

		win.onFocusChange = (bool getting) {
			// sdpyPrintDebugString("onFocusChange ", getting, " ", this.toString);
			if(this.focusedWidget) {
				if(getting) {
					this.focusedWidget.emit!FocusEvent();
					this.focusedWidget.emit!FocusInEvent();
				} else {
					this.focusedWidget.emit!BlurEvent();
					this.focusedWidget.emit!FocusOutEvent();
				}
			}

			if(getting) {
				this.emit!FocusEvent();
				this.emit!FocusInEvent();
			} else {
				this.emit!BlurEvent();
				this.emit!FocusOutEvent();
			}
		};

		win.onDpiChanged = {
			this.queueRecomputeChildLayout();
			auto event = new DpiChangedEvent(this);
			event.sendDirectly();

			privateDpiChanged();
		};

		win.setEventHandlers(
			(MouseEvent e) {
				dispatchMouseEvent(e);
			},
			(KeyEvent e) {
				//writefln("%x   %s", cast(uint) e.key, e.key);
				dispatchKeyEvent(e);
			},
			(dchar e) {
				if(e == 13) e = 10; // hack?
				if(e == 127) return; // linux sends this, windows doesn't. we don't want it.
				dispatchCharEvent(e);
			},
		);

		addEventListener("char", (Widget, Event ev) {
			if(skipNextChar) {
				ev.preventDefault();
				skipNextChar = false;
			}
		});

		version(win32_widgets)
		win.handleNativeEvent = delegate int(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, out int mustReturn) {
			if(hwnd !is this.win.impl.hwnd)
				return 1; // we don't care... pass it on
			auto ret = WindowProcedureHelper(this, hwnd, msg, wParam, lParam, mustReturn);
			if(mustReturn)
				return ret;
			return 1; // pass it on
		};

		if(Window.newWindowCreated)
			Window.newWindowCreated(this);
	}

	version(custom_widgets)
	override void defaultEventHandler_click(ClickEvent event) {
		if(event.button != MouseButton.wheelDown && event.button != MouseButton.wheelUp) {
			if(event.target && event.target.tabStop)
				event.target.focus();
		}
	}

	private static void delegate(Window) newWindowCreated;

	version(win32_widgets)
	override void paint(WidgetPainter painter) {
		/*
		RECT rect;
		rect.right = this.width;
		rect.bottom = this.height;
		DrawThemeBackground(theme, painter.impl.hdc, 4, 1, &rect, null);
		*/
		// 3dface is used as window backgrounds by Windows too, so that's why I'm using it here
		auto b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
		auto p = SelectObject(painter.impl.hdc, GetStockObject(NULL_PEN));
		// since the pen is null, to fill the whole space, we need the +1 on both.
		gdi.Rectangle(painter.impl.hdc, 0, 0, this.width + 1, this.height + 1);
		SelectObject(painter.impl.hdc, p);
		SelectObject(painter.impl.hdc, b);
	}
	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		painter.fillColor = cs.windowBackgroundColor;
		painter.outlineColor = cs.windowBackgroundColor;
		painter.drawRectangle(Point(0, 0), this.width, this.height);
	}


	override void defaultEventHandler_keydown(KeyDownEvent event) {
		Widget _this = event.target;

		if(event.key == Key.Tab) {
			/* Window tab ordering is a recursive thingy with each group */

			// FIXME inefficient
			Widget[] helper(Widget p) {
				if(p.hidden)
					return null;
				Widget[] childOrdering;

				auto children = p.children.dup;

				while(true) {
					// UIs should be generally small, so gonna brute force it a little
					// note that it must be a stable sort here; if all are index 0, it should be in order of declaration

					Widget smallestTab;
					foreach(ref c; children) {
						if(c is null) continue;
						if(smallestTab is null || c.tabOrder < smallestTab.tabOrder) {
							smallestTab = c;
							c = null;
						}
					}
					if(smallestTab !is null) {
						if(smallestTab.tabStop && !smallestTab.hidden)
							childOrdering ~= smallestTab;
						if(!smallestTab.hidden)
							childOrdering ~= helper(smallestTab);
					} else
						break;

				}

				return childOrdering;
			}

			Widget[] tabOrdering = helper(this);

			Widget recipient;

			if(tabOrdering.length) {
				bool seenThis = false;
				Widget previous;
				foreach(idx, child; tabOrdering) {
					if(child is focusedWidget) {

						if(event.shiftKey) {
							if(idx == 0)
								recipient = tabOrdering[$-1];
							else
								recipient = tabOrdering[idx - 1];
							break;
						}

						seenThis = true;
						if(idx + 1 == tabOrdering.length) {
							// we're at the end, either move to the next group
							// or start back over
							recipient = tabOrdering[0];
						}
						continue;
					}
					if(seenThis) {
						recipient = child;
						break;
					}
					previous = child;
				}
			}

			if(recipient !is null) {
				//  writeln(typeid(recipient));
				recipient.focus();

				skipNextChar = true;
			}
		}

		debug if(event.key == Key.F12) {
			if(devTools) {
				devTools.close();
				devTools = null;
			} else {
				devTools = new DevToolWindow(this);
				devTools.show();
			}
		}
	}

	debug DevToolWindow devTools;


	/++
		Creates a window. Please note windows are created in a hidden state, so you must call [show] or [loop] to get it to display.

		History:
			Prior to May 12, 2021, the default title was "D Application" (simpledisplay.d's default). After that, the default is `Runtime.args[0]` instead.

			The width and height arguments were added to the overload that takes `string` first on June 21, 2021.
	+/
	this(int width = 500, int height = 500, string title = null, WindowTypes windowType = WindowTypes.normal, WindowFlags windowFlags = WindowFlags.dontAutoShow | WindowFlags.managesChildWindowFocus, SimpleWindow parent = null) {
		if(title is null) {
			import core.runtime;
			if(Runtime.args.length)
				title = Runtime.args[0];
		}
		win = new SimpleWindow(width, height, title, OpenGlOptions.no, Resizability.allowResizing, windowType, windowFlags, parent);

		static if(UsingSimpledisplayX11)
		if(windowFlags & WindowFlags.managesChildWindowFocus) {
		///+
		// for input proxy
		auto display = XDisplayConnection.get;
		auto inputProxy = XCreateSimpleWindow(display, win.window, -1, -1, 1, 1, 0, 0, 0);
		XSelectInput(display, inputProxy, EventMask.KeyPressMask | EventMask.KeyReleaseMask | EventMask.FocusChangeMask);
		XMapWindow(display, inputProxy);
		// writefln("input proxy: 0x%0x", inputProxy);
		this.inputProxy = new SimpleWindow(inputProxy);

		/+
		this.inputProxy.onFocusChange = (bool getting) {
			sdpyPrintDebugString("input proxy focus change ", getting);
		};
		+/

		XEvent lastEvent;
		this.inputProxy.handleNativeEvent = (XEvent ev) {
			lastEvent = ev;
			return 1;
		};
		this.inputProxy.setEventHandlers(
			(MouseEvent e) {
				dispatchMouseEvent(e);
			},
			(KeyEvent e) {
				//writefln("%x   %s", cast(uint) e.key, e.key);
				if(dispatchKeyEvent(e)) {
					// FIXME: i should trap error
					if(auto nw = cast(NestedChildWindowWidget) focusedWidget) {
						auto thing = nw.focusableWindow();
						if(thing && thing.window) {
							lastEvent.xkey.window = thing.window;
							// writeln("sending event ", lastEvent.xkey);
							trapXErrors( {
								XSendEvent(XDisplayConnection.get, thing.window, false, 0, &lastEvent);
							});
						}
					}
				}
			},
			(dchar e) {
				if(e == 13) e = 10; // hack?
				if(e == 127) return; // linux sends this, windows doesn't. we don't want it.
				dispatchCharEvent(e);
			},
		);

		this.inputProxy.populateXic();
		// done
		//+/
		}



		win.setRequestedInputFocus = &this.setRequestedInputFocus;

		this(win);
	}

	SimpleWindow inputProxy;

	private SimpleWindow setRequestedInputFocus() {
		return inputProxy;
	}

	/// ditto
	this(string title, int width = 500, int height = 500) {
		this(width, height, title);
	}

	///
	@property string title() { return parentWindow.win.title; }
	///
	@property void title(string title) { parentWindow.win.title = title; }

	///
	@scriptable
	void close() {
		win.close();
		// I synchronize here upon window closing to ensure all child windows
		// get updated too before the event loop. This avoids some random X errors.
		static if(UsingSimpledisplayX11) {
			runInGuiThread( {
				XSync(XDisplayConnection.get, false);
			});
		}
	}

	bool dispatchKeyEvent(KeyEvent ev) {
		auto wid = focusedWidget;
		if(wid is null)
			wid = this;
		KeyEventBase event = ev.pressed ? new KeyDownEvent(wid) : new KeyUpEvent(wid);
		event.originalKeyEvent = ev;
		event.key = ev.key;
		event.state = ev.modifierState;
		event.shiftKey = (ev.modifierState & ModifierState.shift) ? true : false;
		event.altKey = (ev.modifierState & ModifierState.alt) ? true : false;
		event.ctrlKey = (ev.modifierState & ModifierState.ctrl) ? true : false;
		event.dispatch();

		return !event.propagationStopped;
	}

	// returns true if propagation should continue into nested things.... prolly not a great thing to do.
	bool dispatchCharEvent(dchar ch) {
		if(focusedWidget) {
			auto event = new CharEvent(focusedWidget, ch);
			event.dispatch();
			return !event.propagationStopped;
		}
		return true;
	}

	Widget mouseLastOver;
	Widget mouseLastDownOn;
	bool lastWasDoubleClick;
	bool dispatchMouseEvent(MouseEvent ev) {
		auto eleR = widgetAtPoint(this, ev.x, ev.y);
		auto ele = eleR.widget;

		auto captureEle = ele;

		auto mouseCapturedBy = this.mouseCapturedBy.length ? this.mouseCapturedBy[$-1] : null;
		if(mouseCapturedBy !is null) {
			if(ele !is mouseCapturedBy && !mouseCapturedBy.isAParentOf(ele))
				captureEle = mouseCapturedBy;
		}

		// a hack to get it relative to the widget.
		eleR.x = ev.x;
		eleR.y = ev.y;
		auto pain = captureEle;

		auto vpx = eleR.x;
		auto vpy = eleR.y;

		while(pain) {
			eleR.x -= pain.x;
			eleR.y -= pain.y;
			pain.addScrollPosition(eleR.x, eleR.y);

			vpx -= pain.x;
			vpy -= pain.y;

			pain = pain.parent;
		}

		void populateMouseEventBase(MouseEventBase event) {
			event.button = ev.button;
			event.buttonLinear = ev.buttonLinear;
			event.state = ev.modifierState;
			event.clientX = eleR.x;
			event.clientY = eleR.y;

			event.viewportX = vpx;
			event.viewportY = vpy;

			event.shiftKey = (ev.modifierState & ModifierState.shift) ? true : false;
			event.altKey = (ev.modifierState & ModifierState.alt) ? true : false;
			event.ctrlKey = (ev.modifierState & ModifierState.ctrl) ? true : false;
		}

		if(ev.type == MouseEventType.buttonPressed) {
			{
				auto event = new MouseDownEvent(captureEle);
				populateMouseEventBase(event);
				event.dispatch();
			}

			if(ev.button != MouseButton.wheelDown && ev.button != MouseButton.wheelUp && mouseLastDownOn is ele && ev.doubleClick) {
				auto event = new DoubleClickEvent(captureEle);
				populateMouseEventBase(event);
				event.dispatch();
				lastWasDoubleClick = ev.doubleClick;
			} else {
				lastWasDoubleClick = false;
			}

			mouseLastDownOn = ele;
		} else if(ev.type == MouseEventType.buttonReleased) {
			{
				auto event = new MouseUpEvent(captureEle);
				populateMouseEventBase(event);
				event.dispatch();
			}
			if(!lastWasDoubleClick && mouseLastDownOn is ele) {
				auto event = new ClickEvent(captureEle);
				populateMouseEventBase(event);
				event.dispatch();
			}
		} else if(ev.type == MouseEventType.motion) {
			// motion
			{
				auto event = new MouseMoveEvent(captureEle);
				populateMouseEventBase(event); // fills in button which is meaningless but meh
				event.dispatch();
			}

			if(mouseLastOver !is ele) {
				if(ele !is null) {
					if(!isAParentOf(ele, mouseLastOver)) {
						ele.setDynamicState(DynamicState.hover, true);
						auto event = new MouseEnterEvent(ele);
						event.relatedTarget = mouseLastOver;
						event.sendDirectly();

						ele.useStyleProperties((scope Widget.Style s) {
							ele.parentWindow.win.cursor = s.cursor;
						});
					}
				}

				if(mouseLastOver !is null) {
					if(!isAParentOf(mouseLastOver, ele)) {
						mouseLastOver.setDynamicState(DynamicState.hover, false);
						auto event = new MouseLeaveEvent(mouseLastOver);
						event.relatedTarget = ele;
						event.sendDirectly();
					}
				}

				if(ele !is null) {
					auto event = new MouseOverEvent(ele);
					event.relatedTarget = mouseLastOver;
					event.dispatch();
				}

				if(mouseLastOver !is null) {
					auto event = new MouseOutEvent(mouseLastOver);
					event.relatedTarget = ele;
					event.dispatch();
				}

				mouseLastOver = ele;
			}
		}

		return true; // FIXME: the event default prevented?
	}

	/++
		Shows the window and runs the application event loop.

		Blocks until this window is closed.

		Bugs:

		$(PITFALL
			You should always have one event loop live for your application.
			If you make two windows in sequence, the second call to loop (or
			simpledisplay's [SimpleWindow.eventLoop], upon which this is built)
			might fail:

			---
			// don't do this!
			auto window = new Window();
			window.loop();

			// or new Window or new MainWindow, all the same
			auto window2 = new SimpleWindow();
			window2.eventLoop(0); // problematic! might crash
			---

			simpledisplay's current implementation assumes that final cleanup is
			done when the event loop refcount reaches zero. So after the first
			eventLoop returns, when there isn't already another one active, it assumes
			the program will exit soon and cleans up.

			This is arguably a bug that it doesn't reinitialize, and I'll probably change
			it eventually, but in the mean time, there's an easy solution:

			---
			// do this
			EventLoop mainEventLoop = EventLoop.get; // just add this line

			auto window = new Window();
			window.loop();

			// or any other type of Window etc.
			auto window2 = new Window();
			window2.loop(); // perfectly fine since mainEventLoop still alive
			---

			By adding a top-level reference to the event loop, it ensures the final cleanup
			is not performed until it goes out of scope too, letting the individual window loops
			work without trouble despite the bug.
		)

		History:
			The [BlockingMode] parameter was added on December 8, 2021.
			The default behavior is to block until the application quits
			(so all windows have been closed), unless another minigui or
			simpledisplay event loop is already running, in which case it
			will block until this window closes specifically.
	+/
	@scriptable
	void loop(BlockingMode bm = BlockingMode.automatic) {
		if(win.closed)
			return; // otherwise show will throw
		show();
		win.eventLoopWithBlockingMode(bm, 0);
	}

	private bool firstShow = true;

	@scriptable
	override void show() {
		bool rd = false;
		if(firstShow) {
			firstShow = false;
			queueRecomputeChildLayout();
			// unless the programmer already called focus on something, pick something ourselves
			auto f = focusedWidget is null ? getFirstFocusable(this) : focusedWidget; // FIXME: autofocus?
			if(f)
				f.focus();
			redraw();
		}
		win.show();
		super.show();
	}
	@scriptable
	override void hide() {
		win.hide();
		super.hide();
	}

	static Widget getFirstFocusable(Widget start) {
		if(start is null)
			return null;

		foreach(widget; &start.focusableWidgets) {
			return widget;
		}

		return null;
	}

	static Widget getLastFocusable(Widget start) {
		if(start is null)
			return null;

		Widget last;
		foreach(widget; &start.focusableWidgets) {
			last = widget;
		}

		return last;
	}


	mixin Emits!ClosingEvent;
	mixin Emits!ClosedEvent;
}

/++
	History:
		Added January 12, 2022

		Made `final` on January 3, 2025
+/
final class DpiChangedEvent : Event {
	enum EventString = "dpichanged";

	this(Widget target) {
		super(EventString, target);
	}
}

debug private class DevToolWindow : Window {
	Window p;

	TextEdit parentList;
	TextEdit logWindow;
	TextLabel clickX, clickY;

	this(Window p) {
		this.p = p;
		super(400, 300, "Developer Toolbox");

		logWindow = new TextEdit(this);
		parentList = new TextEdit(this);

		auto hl = new HorizontalLayout(this);
		clickX = new TextLabel("", TextAlignment.Right, hl);
		clickY = new TextLabel("", TextAlignment.Right, hl);

		parentListeners ~= p.addEventListener("*", (Event ev) {
			log(typeid(ev.source).name, " emitted ", typeid(ev).name);
		});

		parentListeners ~= p.addEventListener((ClickEvent ev) {
			auto s = ev.srcElement;

			string list;

			void addInfo(Widget s) {
				list ~= s.toString();
				list ~= "\n\tminHeight: " ~ toInternal!string(s.minHeight);
				list ~= "\n\tmaxHeight: " ~ toInternal!string(s.maxHeight);
				list ~= "\n\theightStretchiness: " ~ toInternal!string(s.heightStretchiness);
				list ~= "\n\theight: " ~ toInternal!string(s.height);
				list ~= "\n\tminWidth: " ~ toInternal!string(s.minWidth);
				list ~= "\n\tmaxWidth: " ~ toInternal!string(s.maxWidth);
				list ~= "\n\twidthStretchiness: " ~ toInternal!string(s.widthStretchiness);
				list ~= "\n\twidth: " ~ toInternal!string(s.width);
				list ~= "\n\tmarginTop: " ~ toInternal!string(s.marginTop);
				list ~= "\n\tmarginBottom: " ~ toInternal!string(s.marginBottom);
			}

			addInfo(s);

			s = s.parent;
			while(s) {
				list ~= "\n";
				addInfo(s);
				s = s.parent;
			}
			parentList.content = list;

			clickX.label = toInternal!string(ev.clientX);
			clickY.label = toInternal!string(ev.clientY);
		});
	}

	EventListener[] parentListeners;

	override void close() {
		assert(p !is null);
		foreach(p; parentListeners)
			p.disconnect();
		parentListeners = null;
		p.devTools = null;
		p = null;
		super.close();
	}

	override void defaultEventHandler_keydown(KeyDownEvent ev) {
		if(ev.key == Key.F12) {
			this.close();
			if(p)
				p.devTools = null;
		} else {
			super.defaultEventHandler_keydown(ev);
		}
	}

	void log(T...)(T t) {
		string str;
		import std.conv;
		foreach(i; t)
			str ~= to!string(i);
		str ~= "\n";
		logWindow.addText(str);
		logWindow.scrollToBottom();

		//version(custom_widgets)
		//logWindow.ensureVisibleInScroll(logWindow.textLayout.caretBoundingBox());
	}
}

/++
	A dialog is a transient window that intends to get information from
	the user before being dismissed.
+/
class Dialog : Window {
	///
	this(Window parent, int width, int height, string title = null) {
		super(width, height, title, WindowTypes.dialog, WindowFlags.dontAutoShow | WindowFlags.transient, parent is null ? null : parent.win);

		// this(int width = 500, int height = 500, string title = null, WindowTypes windowType = WindowTypes.normal, WindowFlags windowFlags = WindowFlags.dontAutoShow | WindowFlags.managesChildWindowFocus, SimpleWindow parent = null) {
	}

	///
	this(Window parent, string title, int width, int height) {
		this(parent, width, height, title);
	}

	deprecated("Pass an explicit parent window, even if it is `null`")
	this(int width, int height, string title = null) {
		this(null, width, height, title);
	}

	///
	void OK() {

	}

	///
	void Cancel() {
		this.close();
	}
}

/++
	A custom widget similar to the HTML5 <details> tag.
+/
version(none)
class DetailsView : Widget {

}

// FIXME: maybe i should expose the other list views Windows offers too

/++
	A TableView is a widget made to display a table of data strings.


	Future_Directions:
		Each item should be able to take an icon too and maybe I'll allow more of the view modes Windows offers.

		I will add a selection changed event at some point, as well as item clicked events.
	History:
		Added September 24, 2021. Initial api stabilized in dub v10.4, but it isn't completely feature complete yet.
	See_Also:
		[ListWidget] which displays a list of strings without additional columns.
+/
class TableView : Widget {
	/++

	+/
	this(Widget parent) {
		super(parent);

		version(win32_widgets) {
			// LVS_EX_LABELTIP might be worth too
			// LVS_OWNERDRAWFIXED
			createWin32Window(this, WC_LISTVIEW, "", LVS_REPORT | LVS_OWNERDATA);//, LVS_EX_TRACKSELECT); // ex style for for LVN_HOTTRACK
		} else version(custom_widgets) {
			auto smw = new ScrollMessageWidget(this);
			smw.addDefaultKeyboardListeners();
			smw.addDefaultWheelListeners(1, scaleWithDpi(16));
			tvwi = new TableViewWidgetInner(this, smw);
		}
	}

	// FIXME: auto-size columns on double click of header thing like in Windows
	// it need only make the currently displayed things fit well.


	private ColumnInfo[] columns;
	private int itemCount;

	version(custom_widgets) private {
		TableViewWidgetInner tvwi;
	}

	/// Passed to [setColumnInfo]
	static struct ColumnInfo {
		const(char)[] name; /// the name displayed in the header
		/++
			The default width, in pixels. As a special case, you can set this to -1
			if you want the system to try to automatically size the width to fit visible
			content. If it can't, it will try to pick a sensible default size.

			Any other negative value is not allowed and may lead to unpredictable results.

			History:
				The -1 behavior was specified on December 3, 2021. It actually worked before
				anyway on Win32 but now it is a formal feature with partial Linux support.

			Bugs:
				It doesn't actually attempt to calculate a best-fit width on Linux as of
				December 3, 2021. I do plan to fix this in the future, but Windows is the
				priority right now. At least it doesn't break things when you use it now.
		+/
		int width;

		/++
			Alignment of the text in the cell. Applies to the header as well as all data in this
			column.

			Bugs:
				On Windows, the first column ignores this member and is always left aligned.
				You can work around this by inserting a dummy first column with width = 0
				then putting your actual data in the second column, which does respect the
				alignment.

				This is a quirk of the operating system's implementation going back a very
				long time and is unlikely to ever be fixed.
		+/
		TextAlignment alignment;

		/++
			After all the pixel widths have been assigned, any left over
			space is divided up among all columns and distributed to according
			to the widthPercent field.


			For example, if you have two fields, both with width 50 and one with
			widthPercent of 25 and the other with widthPercent of 75, and the
			container is 200 pixels wide, first both get their width of 50.
			then the 100 remaining pixels are split up, so the one gets a total
			of 75 pixels and the other gets a total of 125.

			This is automatically applied as the window is resized.

			If there is not enough space - that is, when a horizontal scrollbar
			needs to appear - there are 0 pixels divided up, and thus everyone
			gets 0. This can cause a column to shrink out of proportion when
			passing the scroll threshold.

			It is important to still set a fixed width (that is, to populate the
			`width` field) even if you use the percents because that will be the
			default minimum in the event of a scroll bar appearing.

			The percents total in the column can never exceed 100 or be less than 0.
			Doing this will trigger an assert error.

			Implementation note:

			Please note that percentages are only recalculated 1) upon original
			construction and 2) upon resizing the control. If the user adjusts the
			width of a column, the percentage items will not be updated.

			On the other hand, if the user adjusts the width of a percentage column
			then resizes the window, it is recalculated, meaning their hand adjustment
			is discarded. This specific behavior may change in the future as it is
			arguably a bug, but I'm not certain yet.

			History:
				Added November 10, 2021 (dub v10.4)
		+/
		int widthPercent;


		private int calculatedWidth;
	}
	/++
		Sets the number of columns along with information about the headers.

		Please note: on Windows, the first column ignores your alignment preference
		and is always left aligned.
	+/
	void setColumnInfo(ColumnInfo[] columns...) {

		foreach(ref c; columns) {
			c.name = c.name.idup;
		}
		this.columns = columns.dup;

		updateCalculatedWidth(false);

		version(custom_widgets) {
			tvwi.header.updateHeaders();
			tvwi.updateScrolls();
		} else version(win32_widgets)
		foreach(i, column; this.columns) {
			LVCOLUMN lvColumn;
			lvColumn.mask = LVCF_FMT | LVCF_WIDTH | LVCF_TEXT | LVCF_SUBITEM;
			lvColumn.cx = column.width == -1 ? -1 : column.calculatedWidth;

			auto bfr = WCharzBuffer(column.name);
			lvColumn.pszText = bfr.ptr;

			if(column.alignment & TextAlignment.Center)
				lvColumn.fmt = LVCFMT_CENTER;
			else if(column.alignment & TextAlignment.Right)
				lvColumn.fmt = LVCFMT_RIGHT;
			else
				lvColumn.fmt = LVCFMT_LEFT;

			if(SendMessage(hwnd, LVM_INSERTCOLUMN, cast(WPARAM) i, cast(LPARAM) &lvColumn) == -1)
				throw new WindowsApiException("Insert Column Fail", GetLastError());
		}
	}

	version(custom_widgets)
	private int getColumnSizeForContent(size_t columnIndex) {
		// FIXME: idk where the problem is but with a 2x scale the horizontal scroll is insuffiicent. i think the SMW is doing it wrong.
		// might also want a user-defined max size too
		int padding = scaleWithDpi(6);
		int m = this.defaultTextWidth(this.columns[columnIndex].name) + padding;

		if(getData !is null)
		foreach(row; 0 .. itemCount)
			getData(row, cast(int) columnIndex, (txt) {
				m = mymax(m, this.defaultTextWidth(txt) + padding);
			});

		if(m < 32)
			m = 32;

		return m;
	}

	/++
		History:
			Added February 26, 2025
	+/
	void autoSizeColumnsToContent() {
		version(custom_widgets) {
			foreach(idx, ref c; columns) {
				c.width = getColumnSizeForContent(idx);
			}
			updateCalculatedWidth(false);
			tvwi.updateScrolls();
		} else version(win32_widgets) {
			foreach(i, c; columns)
				SendMessage(hwnd, LVM_SETCOLUMNWIDTH, i, LVSCW_AUTOSIZE); // LVSCW_AUTOSIZE or LVSCW_AUTOSIZE_USEHEADER are amazing omg
		}
	}

	/++
		History:
			Added March 1, 2025
	+/
	bool supportsPerCellAlignment() {
		version(custom_widgets)
			return true;
		else version(win32_widgets)
			return false;
		return false;
	}

	private int getActualSetSize(size_t i, bool askWindows) {
		version(win32_widgets)
			if(askWindows)
				return cast(int) SendMessage(hwnd, LVM_GETCOLUMNWIDTH, cast(WPARAM) i, 0);
		auto w = columns[i].width;
		if(w == -1)
			return 50; // idk, just give it some space so the percents aren't COMPLETELY off FIXME
		return w;
	}

	private void updateCalculatedWidth(bool informWindows) {
		int padding;
		version(win32_widgets)
			padding = 4;
		int remaining = this.width;
		foreach(i, column; columns)
			remaining -= this.getActualSetSize(i, informWindows && column.widthPercent == 0) + padding;
		remaining -= padding;
		if(remaining < 0)
			remaining = 0;

		int percentTotal;
		foreach(i, ref column; columns) {
			percentTotal += column.widthPercent;

			auto c = this.getActualSetSize(i, informWindows && column.widthPercent == 0) + (remaining * column.widthPercent) / 100;

			column.calculatedWidth = c;

			version(win32_widgets)
			if(informWindows)
				SendMessage(hwnd, LVM_SETCOLUMNWIDTH, i, c); // LVSCW_AUTOSIZE or LVSCW_AUTOSIZE_USEHEADER are amazing omg
		}

		assert(percentTotal >= 0, "The total percents in your column definitions were negative. They must add up to something between 0 and 100.");
		assert(percentTotal <= 100, "The total percents in your column definitions exceeded 100. They must add up to no more than 100 (can be less though).");


	}

	override void registerMovement() {
		super.registerMovement();

		updateCalculatedWidth(true);
	}

	/++
		Tells the view how many items are in it. It uses this to set the scroll bar, but the items are not added per se; it calls [getData] as-needed.
	+/
	void setItemCount(int count) {
		this.itemCount = count;
		version(custom_widgets) {
			tvwi.updateScrolls();
			redraw();
		} else version(win32_widgets) {
			SendMessage(hwnd, LVM_SETITEMCOUNT, count, 0);
		}
	}

	/++
		Clears all items;
	+/
	void clear() {
		this.itemCount = 0;
		this.columns = null;
		version(custom_widgets) {
			tvwi.header.updateHeaders();
			tvwi.updateScrolls();
			redraw();
		} else version(win32_widgets) {
			SendMessage(hwnd, LVM_DELETEALLITEMS, 0, 0);
		}
	}

	/+
	version(win32_widgets)
	override int handleWmDrawItem(DRAWITEMSTRUCT* dis)
		auto itemId = dis.itemID;
		auto hdc = dis.hDC;
		auto rect = dis.rcItem;
		switch(dis.itemAction) {
			case ODA_DRAWENTIRE:

				// FIXME: do other items
				// FIXME: do the focus rectangle i guess
				// FIXME: alignment
				// FIXME: column width
				// FIXME: padding left
				// FIXME: check dpi scaling
				// FIXME: don't owner draw unless it is necessary.

				auto padding = GetSystemMetrics(SM_CXEDGE); // FIXME: for dpi
				RECT itemRect;
				itemRect.top = 1; // subitem idx, 1-based
				itemRect.left = LVIR_BOUNDS;

				SendMessage(hwnd, LVM_GETSUBITEMRECT, itemId, cast(LPARAM) &itemRect);
				itemRect.left += padding;

				getData(itemId, 0, (in char[] data) {
					auto wdata = WCharzBuffer(data);
					DrawTextW(hdc, wdata.ptr, wdata.length, &itemRect, DT_RIGHT| DT_END_ELLIPSIS);

				});
			goto case;
			case ODA_FOCUS:
				if(dis.itemState & ODS_FOCUS)
					DrawFocusRect(hdc, &rect);
			break;
			case ODA_SELECT:
				// itemState & ODS_SELECTED
			break;
			default:
		}
		return 1;
	}
	+/

	version(win32_widgets) {
		CellStyle last;
		COLORREF defaultColor;
		COLORREF defaultBackground;
	}

	version(win32_widgets)
	override int handleWmNotify(NMHDR* hdr, int code, out int mustReturn) {
		switch(code) {
			case NM_CUSTOMDRAW:
				auto s = cast(NMLVCUSTOMDRAW*) hdr;
				switch(s.nmcd.dwDrawStage) {
					case CDDS_PREPAINT:
						if(getCellStyle is null)
							return 0;

						mustReturn = true;
						return CDRF_NOTIFYITEMDRAW;
					case CDDS_ITEMPREPAINT:
						mustReturn = true;
						return CDRF_NOTIFYSUBITEMDRAW;
					case CDDS_ITEMPREPAINT | CDDS_SUBITEM:
						mustReturn = true;

						if(getCellStyle is null) // this SHOULD never happen...
							return 0;

						if(s.iSubItem == 0) {
							// Windows resets it per row so we'll use item 0 as a chance
							// to capture these for later
							defaultColor = s.clrText;
							defaultBackground = s.clrTextBk;
						}

						auto style = getCellStyle(cast(int) s.nmcd.dwItemSpec, cast(int) s.iSubItem);
						// if no special style and no reset needed...
						if(style == CellStyle.init && (s.iSubItem == 0 || last == CellStyle.init))
							return 0; // allow default processing to continue

						last = style;

						// might still need to reset or use the preference.

						if(style.flags & CellStyle.Flags.textColorSet)
							s.clrText = style.textColor.asWindowsColorRef;
						else
							s.clrText = defaultColor; // reset in case it was set from last iteration not a fan
						if(style.flags & CellStyle.Flags.backgroundColorSet)
							s.clrTextBk = style.backgroundColor.asWindowsColorRef;
						else
							s.clrTextBk = defaultBackground; // need to reset it... not a fan of this

						return CDRF_NEWFONT;
					default:
						return 0;

				}
			case NM_RETURN: // no need since i subclass keydown
			break;
			case LVN_COLUMNCLICK:
				auto info = cast(LPNMLISTVIEW) hdr;
				this.emit!HeaderClickedEvent(info.iSubItem);
			break;
			case (LVN_FIRST-21) /* LVN_HOTTRACK */:
				// requires LVS_EX_TRACKSELECT
				// sdpyPrintDebugString("here");
				mustReturn = 1; // override Windows' auto selection
			break;
			case NM_CLICK:
				NMITEMACTIVATE* info = cast(NMITEMACTIVATE*) hdr;
				this.emit!CellClickedEvent(info.iItem, info.iSubItem, MouseButton.left, MouseButtonLinear.left, info.ptAction.x, info.ptAction.y, !!(info.uKeyFlags & LVKF_ALT), !!(info.uKeyFlags & LVKF_CONTROL), !!(info.uKeyFlags & LVKF_SHIFT), false);
			break;
			case NM_DBLCLK:
				NMITEMACTIVATE* info = cast(NMITEMACTIVATE*) hdr;
				this.emit!CellClickedEvent(info.iItem, info.iSubItem, MouseButton.left, MouseButtonLinear.left, info.ptAction.x, info.ptAction.y, !!(info.uKeyFlags & LVKF_ALT), !!(info.uKeyFlags & LVKF_CONTROL), !!(info.uKeyFlags & LVKF_SHIFT), true);
			break;
			case NM_RCLICK:
				NMITEMACTIVATE* info = cast(NMITEMACTIVATE*) hdr;
				this.emit!CellClickedEvent(info.iItem, info.iSubItem, MouseButton.right, MouseButtonLinear.left, info.ptAction.x, info.ptAction.y, !!(info.uKeyFlags & LVKF_ALT), !!(info.uKeyFlags & LVKF_CONTROL), !!(info.uKeyFlags & LVKF_SHIFT), false);
			break;
			case NM_RDBLCLK:
				NMITEMACTIVATE* info = cast(NMITEMACTIVATE*) hdr;
				this.emit!CellClickedEvent(info.iItem, info.iSubItem, MouseButton.right, MouseButtonLinear.left, info.ptAction.x, info.ptAction.y, !!(info.uKeyFlags & LVKF_ALT), !!(info.uKeyFlags & LVKF_CONTROL), !!(info.uKeyFlags & LVKF_SHIFT), true);
			break;
			case LVN_GETDISPINFO:
				LV_DISPINFO* info = cast(LV_DISPINFO*) hdr;
				if(info.item.mask & LVIF_TEXT) {
					if(getData) {
						getData(info.item.iItem, info.item.iSubItem, (in char[] dataReceived) {
							auto bfr = WCharzBuffer(dataReceived);
							auto len = info.item.cchTextMax;
							if(bfr.length < len)
								len = cast(typeof(len)) bfr.length;
							info.item.pszText[0 .. len] = bfr.ptr[0 .. len];
							info.item.pszText[len] = 0;
						});
					} else {
						info.item.pszText[0] = 0;
					}
					//info.item.iItem
					//if(info.item.iSubItem)
				}
			break;
			default:
		}
		return 0;
	}

	// FIXME: this throws off mouse calculations, it should only happen when we're at the top level or something idk
	override bool encapsulatedChildren() {
		return true;
	}

	/++
		Informs the control that content has changed.

		History:
			Added November 10, 2021 (dub v10.4)
	+/
	void update() {
		version(custom_widgets)
			redraw();
		else {
			SendMessage(hwnd, LVM_REDRAWITEMS, 0, SendMessage(hwnd, LVM_GETITEMCOUNT, 0, 0));
			UpdateWindow(hwnd);
		}


	}

	/++
		Called by the system to request the text content of an individual cell. You
		should pass the text into the provided `sink` delegate. This function will be
		called for each visible cell as-needed when drawing.
	+/
	void delegate(int row, int column, scope void delegate(in char[]) sink) getData;

	/++
		Available per-cell style customization options. Use one of the constructors
		provided to set the values conveniently, or default construct it and set individual
		values yourself. Just remember to set the `flags` so your values are actually used.
		If the flag isn't set, the field is ignored and the system default is used instead.

		This is returned by the [getCellStyle] delegate.

		Examples:
			---
			// assumes you have a variables called `my_data` which is an array of arrays of numbers
			auto table = new TableView(window);
			// snip: you would set up columns here

			// this is how you provide data to the table view class
			table.getData = delegate(int row, int column, scope void delegate(in char[]) sink) {
				import std.conv;
				sink(to!string(my_data[row][column]));
			};

			// and this is how you customize the colors
			table.getCellStyle = delegate(int row, int column) {
				return (my_data[row][column] < 0) ?
					TableView.CellStyle(Color.red); // make negative numbers red
					: TableView.CellStyle.init; // leave the rest alone
			};
			// snip: you would call table.setItemCount here then continue with the rest of your window setup work
			---

		History:
			Added November 27, 2021 (dub v10.4)
	+/
	struct CellStyle {
		/// Sets just a custom text color, leaving the background as the default. Use caution with certain colors as it may have illeglible contrast on the (unknown to you) background color.
		this(Color textColor) {
			this.textColor = textColor;
			this.flags |= Flags.textColorSet;
		}
		/// Sets a custom text and background color.
		this(Color textColor, Color backgroundColor) {
			this.textColor = textColor;
			this.backgroundColor = backgroundColor;
			this.flags |= Flags.textColorSet | Flags.backgroundColorSet;
		}
		/++
			Alignment is only supported on some platforms.
		+/
		this(TextAlignment alignment) {
			this.alignment = alignment;
			this.flags |= Flags.alignmentSet;
		}
		/// ditto
		this(TextAlignment alignment, Color textColor) {
			this.alignment = alignment;
			this.textColor = textColor;
			this.flags |= Flags.alignmentSet | Flags.textColorSet;
		}
		/// ditto
		this(TextAlignment alignment, Color textColor, Color backgroundColor) {
			this.alignment = alignment;
			this.textColor = textColor;
			this.backgroundColor = backgroundColor;
			this.flags |= Flags.alignmentSet | Flags.textColorSet | Flags.backgroundColorSet;
		}

		TextAlignment alignment;
		Color textColor;
		Color backgroundColor;
		int flags; /// bitmask of [Flags]
		/// available options to combine into [flags]
		enum Flags {
			textColorSet = 1 << 0,
			backgroundColorSet = 1 << 1,
			alignmentSet = 1 << 2,
		}
	}
	/++
		Companion delegate to [getData] that allows you to custom style each
		cell of the table.

		Returns:
			A [CellStyle] structure that describes the desired style for the
			given cell. `return CellStyle.init` if you want the default style.

		History:
			Added November 27, 2021 (dub v10.4)
	+/
	CellStyle delegate(int row, int column) getCellStyle;

	// i want to be able to do things like draw little colored things to show red for negative numbers
	// or background color indicators or even in-cell charts
	// void delegate(int row, int column, WidgetPainter painter, int width, int height, in char[] text) drawCell;

	/++
		When the user clicks on a header, this event is emitted. It has a member to identify which header (by index) was clicked.
	+/
	mixin Emits!HeaderClickedEvent;

	/++
		History:
			Added March 2, 2025
	+/
	mixin Emits!CellClickedEvent;
}

/++
	This is emitted by the [TableView] when a user clicks on a column header.

	Its member `columnIndex` has the zero-based index of the column that was clicked.

	The default behavior of this event is to do nothing, so `preventDefault` has no effect.

	History:
		Added November 27, 2021 (dub v10.4)

		Made `final` on January 3, 2025
+/
final class HeaderClickedEvent : Event {
	enum EventString = "HeaderClicked";
	this(Widget target, int columnIndex) {
		this.columnIndex = columnIndex;
		super(EventString, target);
	}

	/// The index of the column
	int columnIndex;

	///
	override @property int intValue() {
		return columnIndex;
	}
}

/++
	History:
		Added March 2, 2025
+/
final class CellClickedEvent : MouseEventBase {
	enum EventString = "CellClicked";
	this(Widget target, int rowIndex, int columnIndex, MouseButton button, MouseButtonLinear mouseButtonLinear, int x, int y, bool altKey, bool ctrlKey, bool shiftKey, bool isDoubleClick) {
		this.rowIndex = rowIndex;
		this.columnIndex = columnIndex;
		this.button = button;
		this.buttonLinear = mouseButtonLinear;
		this.isDoubleClick = isDoubleClick;
		this.clientX = x;
		this.clientY = y;

		this.altKey = altKey;
		this.ctrlKey = ctrlKey;
		this.shiftKey = shiftKey;

		// import std.stdio; std.stdio.writeln(rowIndex, "x", columnIndex, " @ ", x, ",", y, " ", button, " ", isDoubleClick, " ", altKey, " ", ctrlKey, " ", shiftKey);

		// FIXME: x, y, state, altButton etc?
		super(EventString, target);
	}

	/++
		See also: [button] inherited from the base class.

		clientX and clientY are irrespective of scrolling - FIXME is that sane?
	+/
	int columnIndex;

	/// ditto
	int rowIndex;

	/// ditto
	bool isDoubleClick;

	/+
	// i could do intValue as a linear index if we know the width
	// and a stringValue with the string in the cell. but idk if worth.
	override @property int intValue() {
		return columnIndex;
	}
	+/

}

version(custom_widgets)
private class TableViewWidgetInner : Widget {

// wrap this thing in a ScrollMessageWidget

	TableView tvw;
	ScrollMessageWidget smw;
	HeaderWidget header;

	this(TableView tvw, ScrollMessageWidget smw) {
		this.tvw = tvw;
		this.smw = smw;
		super(smw);

		this.tabStop = true;

		header = new HeaderWidget(this, smw.getHeader());

		smw.addEventListener("scroll", () {
			this.redraw();
			header.redraw();
		});


		// I need headers outside the scroll area but rendered on the same line as the up arrow
		// FIXME: add a fixed header to the SMW
	}

	enum padding = 3;

	void updateScrolls() {
		int w;
		foreach(idx, column; tvw.columns) {
			w += column.calculatedWidth;
		}
		smw.setTotalArea(w, tvw.itemCount);
		columnsWidth = w;
	}

	private int columnsWidth;

	private int lh() { return scaleWithDpi(16); } // FIXME lineHeight

	override void registerMovement() {
		super.registerMovement();
		// FIXME: actual column width. it might need to be done per-pixel instead of per-column
		smw.setViewableArea(this.width, this.height / lh);
	}

	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		int x;
		int y;

		int row = smw.position.y;

		foreach(lol; 0 .. this.height / lh) {
			if(row >= tvw.itemCount)
				break;
			x = 0;
			foreach(columnNumber, column; tvw.columns) {
				auto x2 = x + column.calculatedWidth;
				auto smwx = smw.position.x;

				if(x2 > smwx /* if right side of it is visible at all */ || (x >= smwx && x < smwx + this.width) /* left side is visible at all*/) {
					auto startX = x;
					auto endX = x + column.calculatedWidth;
					switch (column.alignment & (TextAlignment.Left | TextAlignment.Center | TextAlignment.Right)) {
						case TextAlignment.Left: startX += padding; break;
						case TextAlignment.Center: startX += padding; endX -= padding; break;
						case TextAlignment.Right: endX -= padding; break;
						default: /* broken */ break;
					}
					if(column.width != 0) // no point drawing an invisible column
					tvw.getData(row, cast(int) columnNumber, (in char[] info) {
						auto endClip = endX - smw.position.x;
						if(endClip > this.width - padding)
							endClip = this.width - padding;
						auto clip = painter.setClipRectangle(Rectangle(Point(startX - smw.position.x, y), Point(endClip, y + lh)));

						void dotext(WidgetPainter painter, TextAlignment alignment) {
							painter.drawText(Point(startX - smw.position.x, y), info, Point(endX - smw.position.x - padding, y + lh), alignment);
						}

						if(tvw.getCellStyle !is null) {
							auto style = tvw.getCellStyle(row, cast(int) columnNumber);

							if(style.flags & TableView.CellStyle.Flags.backgroundColorSet) {
								auto tempPainter = painter;
								tempPainter.fillColor = style.backgroundColor;
								tempPainter.outlineColor = style.backgroundColor;

								tempPainter.drawRectangle(Point(startX - smw.position.x, y),
									Point(endX - smw.position.x, y + lh));
							}
							auto tempPainter = painter;
							if(style.flags & TableView.CellStyle.Flags.textColorSet)
								tempPainter.outlineColor = style.textColor;

							auto alignment = column.alignment;
							if(style.flags & TableView.CellStyle.Flags.alignmentSet)
								alignment = style.alignment;
							dotext(tempPainter, alignment);
						} else {
							dotext(painter, column.alignment);
						}
					});
				}

				x += column.calculatedWidth;
			}
			row++;
			y += lh;
		}
		return bounds;
	}

	static class Style : Widget.Style {
		override WidgetBackground background() {
			return WidgetBackground(WidgetPainter.visualTheme.widgetBackgroundColor);
		}
	}
	mixin OverrideStyle!Style;

	private static class HeaderWidget : Widget {
		/+
			maybe i should do a splitter thing on top of the other widgets
			so the splitter itself isn't really drawn but still replies to mouse events?
		+/
		this(TableViewWidgetInner tvw, Widget parent) {
			super(parent);
			this.tvw = tvw;

			this.remainder = new Button("", this);

			this.addEventListener((scope ClickEvent ev) {
				int header = -1;
				foreach(idx, child; this.children[1 .. $]) {
					if(child is ev.target) {
						header = cast(int) idx;
						break;
					}
				}

				if(header != -1) {
					auto hce = new HeaderClickedEvent(tvw.tvw, header);
					hce.dispatch();
				}

			});
		}

		override int minHeight() {
			return defaultLineHeight + 4; // same as Button
		}

		void updateHeaders() {
			foreach(child; children[1 .. $])
				child.removeWidget();

			foreach(column; tvw.tvw.columns) {
				// the cast is ok because I dup it above, just the type is never changed.
				// all this is private so it should never get messed up.
				new Button(ImageLabel(cast(string) column.name, column.alignment), this);
			}
		}

		Button remainder;
		TableViewWidgetInner tvw;

		override void recomputeChildLayout() {
			registerMovement();
			int pos;
			foreach(idx, child; children[1 .. $]) {
				if(idx >= tvw.tvw.columns.length)
					continue;
				child.x = pos;
				child.y = 0;
				child.width = tvw.tvw.columns[idx].calculatedWidth;
				child.height = scaleWithDpi(16);// this.height;
				pos += child.width;

				child.recomputeChildLayout();
			}

			if(remainder is null)
				return;

			remainder.x = pos;
			remainder.y = 0;
			if(pos < this.width)
				remainder.width = this.width - pos;// + 4;
			else
				remainder.width = 0;
			remainder.height = scaleWithDpi(16);

			remainder.recomputeChildLayout();
		}

		// for the scrollable children mixin
		Point scrollOrigin() {
			return Point(tvw.smw.position.x, 0);
		}
		void paintFrameAndBackground(WidgetPainter painter) { }

		// for mouse event dispatching
		override protected void addScrollPosition(ref int x, ref int y) {
			x += scrollOrigin.x;
			y += scrollOrigin.y;
		}

		mixin ScrollableChildren;
	}

	private void emitCellClickedEvent(scope MouseEventBase event, bool isDoubleClick) {
		int mx = event.clientX + smw.position.x;
		int my = event.clientY;

		Widget par = this;
		while(par && !par.encapsulatedChildren) {
			my -= par.y; // to undo the encapsulatedChildren adjustClientCoordinates effect
			par = par.parent;
		}
		if(par is null)
			my = event.clientY; // encapsulatedChildren not present?

		int row = my / lh + smw.position.y; // scrolling here is done per-item, not per pixel
		if(row > tvw.itemCount)
			row = -1;

		int column = -1;
		if(row != -1) {
			int pos;
			foreach(idx, col; tvw.columns) {
				pos += col.calculatedWidth;
				if(mx < pos) {
					column = cast(int) idx;
					break;
				}
			}
		}

		// wtf are these casts about?
		tvw.emit!CellClickedEvent(row, column, cast(MouseButton) event.button, cast(MouseButtonLinear) event.buttonLinear, event.clientX, event.clientY, event.altKey, event.ctrlKey, event.shiftKey, isDoubleClick);
	}

	override void defaultEventHandler_click(scope ClickEvent ce) {
		// FIXME: should i filter mouse wheel events? Windows doesn't send them but i can.
		emitCellClickedEvent(ce, false);
	}

	override void defaultEventHandler_dblclick(scope DoubleClickEvent ce) {
		emitCellClickedEvent(ce, true);
	}
}

/+

// given struct / array / number / string / etc, make it viewable and editable
class DataViewerWidget : Widget {

}
+/

/++
	A line edit box with an associated label.

	History:
		On May 17, 2021, the default internal layout was changed from horizontal to vertical.

		```
		Old: ________

		New:
		____________
		```

		To restore the old behavior, use `new LabeledLineEdit("label", TextAlignment.Right, parent);`

		You can also use `new LabeledLineEdit("label", TextAlignment.Left, parent);` if you want a
		horizontal label but left aligned. You may also consider a [GridLayout].
+/
alias LabeledLineEdit = Labeled!LineEdit;

private int widthThatWouldFitChildLabels(Widget w) {
	if(w is null)
		return 0;

	int max;

	if(auto label = cast(TextLabel) w) {
		return label.TextLabel.flexBasisWidth() + label.paddingLeft() + label.paddingRight();
	} else {
		foreach(child; w.children) {
			max = mymax(max, widthThatWouldFitChildLabels(child));
		}
	}

	return max;
}

/++
	History:
		Added May 19, 2021
+/
class Labeled(T) : Widget {
	///
	this(string label, Widget parent) {
		super(parent);
		initialize!VerticalLayout(label, TextAlignment.Left, parent);
	}

	/++
		History:
			The alignment parameter was added May 17, 2021
	+/
	this(string label, TextAlignment alignment, Widget parent) {
		super(parent);
		initialize!HorizontalLayout(label, alignment, parent);
	}

	private void initialize(L)(string label, TextAlignment alignment, Widget parent) {
		tabStop = false;
		horizontal = is(L == HorizontalLayout);
		auto hl = new L(this);
		if(horizontal) {
			static class SpecialTextLabel : TextLabel {
				Widget outerParent;

				this(string label, TextAlignment alignment, Widget outerParent, Widget parent) {
					this.outerParent = outerParent;
					super(label, alignment, parent);
				}

				override int flexBasisWidth() {
					return widthThatWouldFitChildLabels(outerParent);
				}
				/+
				override int widthShrinkiness() { return 0; }
				override int widthStretchiness() { return 1; }
				+/

				override int paddingRight() { return 6; }
				override int paddingLeft() { return 9; }

				override int paddingTop() { return 3; }
			}
			this.label = new SpecialTextLabel(label, alignment, parent, hl);
		} else
			this.label = new TextLabel(label, alignment, hl);
		this.lineEdit = new T(hl);

		this.label.labelFor = this.lineEdit;
	}

	private bool horizontal;

	TextLabel label; ///
	T lineEdit; ///

	override int flexBasisWidth() { return 250; }
	override int widthShrinkiness() { return 1; }

	override int minHeight() {
		return this.children[0].minHeight;
	}
	override int maxHeight() { return minHeight(); }
	override int marginTop() { return 4; }
	override int marginBottom() { return 4; }

	// FIXME: i should prolly call it value as well as content tbh

	///
	@property string content() {
		return lineEdit.content;
	}
	///
	@property void content(string c) {
		return lineEdit.content(c);
	}

	///
	void selectAll() {
		lineEdit.selectAll();
	}

	override void focus() {
		lineEdit.focus();
	}
}

/++
	A labeled password edit.

	History:
		Added as a class on January 25, 2021, changed into an alias of the new [Labeled] template on May 19, 2021

		The default parameters for the constructors were also removed on May 19, 2021
+/
alias LabeledPasswordEdit = Labeled!PasswordEdit;

private string toMenuLabel(string s) {
	string n;
	n.reserve(s.length);
	foreach(c; s)
		if(c == '_')
			n ~= ' ';
		else
			n ~= c;
	return n;
}

private void autoExceptionHandler(Exception e) {
	messageBox(e.msg);
}

void callAsIfClickedFromMenu(alias fn)(auto ref __traits(parent, fn) _this, Window window) {
	makeAutomaticHandler!(fn)(window, &__traits(child, _this, fn))();
}

private void delegate() makeAutomaticHandler(alias fn, T)(Window window, T t) {
	static if(is(T : void delegate())) {
		return () {
			try
				t();
			catch(Exception e)
				autoExceptionHandler(e);
		};
	} else static if(is(typeof(fn) Params == __parameters)) {
		static if(Params.length == 1 && is(Params[0] == FileName!(member, filters, type), alias member, string[] filters, FileDialogType type)) {
			return () {
				void onOK(string s) {
					member = s;
					try
						t(Params[0](s));
					catch(Exception e)
						autoExceptionHandler(e);
				}

				if(
					(type == FileDialogType.Automatic && (__traits(identifier, fn).startsWith("Save") || __traits(identifier, fn).startsWith("Export")))
					|| type == FileDialogType.Save)
				{
					getSaveFileName(window, &onOK, member, filters, null);
				} else
					getOpenFileName(window, &onOK, member, filters, null);
			};
		} else {
			struct S {
				static if(!__traits(compiles, mixin(`{ static foreach(i; 1..4) {} }`))) {
					pragma(msg, "warning: automatic handler of params not yet implemented on your compiler");
				} else mixin(q{
				static foreach(idx, ignore; Params) {
					mixin("Params[idx] " ~ __traits(identifier, Params[idx .. idx + 1]) ~ ";");
				}
				});
			}
			return () {
				dialog(window, (S s) {
					try {
						static if(is(typeof(t) Ret == return)) {
							static if(is(Ret == void)) {
								t(s.tupleof);
							} else {
								auto ret = t(s.tupleof);
								import std.conv;
								messageBox(to!string(ret), "Returned Value");
							}
						}
					} catch(Exception e)
						autoExceptionHandler(e);
				}, null, __traits(identifier, fn));
			};
		}
	}
}

private template hasAnyRelevantAnnotations(a...) {
	bool helper() {
		bool any;
		foreach(attr; a) {
			static if(is(typeof(attr) == .menu))
				any = true;
			else static if(is(typeof(attr) == .toolbar))
				any = true;
			else static if(is(attr == .separator))
				any = true;
			else static if(is(typeof(attr) == .accelerator))
				any = true;
			else static if(is(typeof(attr) == .hotkey))
				any = true;
			else static if(is(typeof(attr) == .icon))
				any = true;
			else static if(is(typeof(attr) == .label))
				any = true;
			else static if(is(typeof(attr) == .tip))
				any = true;
		}
		return any;
	}

	enum bool hasAnyRelevantAnnotations = helper();
}

/++
	A `MainWindow` is a window that includes turnkey support for a menu bar, tool bar, and status bar automatically positioned around a client area where you put your widgets.
+/
class MainWindow : Window {
	///
	this(string title = null, int initialWidth = 500, int initialHeight = 500) {
		super(initialWidth, initialHeight, title);

		_clientArea = new ClientAreaWidget();
		_clientArea.x = 0;
		_clientArea.y = 0;
		_clientArea.width = this.width;
		_clientArea.height = this.height;
		_clientArea.tabStop = false;

		super.addChild(_clientArea);

		statusBar = new StatusBar(this);
	}

	/++
		Adds a menu and toolbar from annotated functions. It uses the top-level annotations from this module, so it is better to put the commands in a separate struct instad of in your window subclass, to avoid potential conflicts with method names (if you do hit one though, you can use `@(.icon(...))` instead of plain `@icon(...)` to disambiguate, though).

		The only required annotation on a function is `@menu("Label")` to make it appear, but there are several optional ones I'd recommend considering, including `@toolbar("group name")`, `@icon()`, `@accelerator("keyboard shortcut string")`, and `@hotkey('char')`.

		You can also use `@separator` to put a separating line in the menu before the function.

		Functions may have zero or one argument. If they have an argument, an automatic dialog box (see: [dialog]) will be created to request the data from the user before calling your function. Some types have special treatment, like [FileName], will invoke the file dialog, assuming open or save based on the name of your function.

		Let's look at a complete example:

	---
	import arsd.minigui;

	void main() {
		auto window = new MainWindow();

		// we can add widgets before or after setting the menu, either way is fine.
		// i'll do it before here so the local variables are available to the commands.

		auto textEdit = new TextEdit(window);

		// Remember, in D, you can define structs inside of functions
		// and those structs can access the function's local variables.
		//
		// Of course, you might also want to do this separately, and if you
		// do, make sure you keep a reference to the window as a struct data
		// member so you can refer to it in cases like this Exit function.
		struct Commands {
			// the & in the string indicates that the next letter is the hotkey
			// to access it from the keyboard (so here, alt+f will open the
			// file menu)
			@menu("&File") {
				@accelerator("Ctrl+N")
				@hotkey('n')
				@icon(GenericIcons.New) // add an icon to the action
				@toolbar("File") // adds it to a toolbar.
				// The toolbar name is never visible to the user, but is used to group icons.
				void New() {
					previousFileReferenced = null;
					textEdit.content = "";
				}

				@icon(GenericIcons.Open)
				@toolbar("File")
				@hotkey('s')
				@accelerator("Ctrl+O")
				void Open(FileName!() filename) {
					import std.file;
					textEdit.content = std.file.readText(filename);
				}

				@icon(GenericIcons.Save)
				@toolbar("File")
				@accelerator("Ctrl+S")
				@hotkey('s')
				void Save() {
					// these are still functions, so of course you can
					// still call them yourself too
					Save_As(previousFileReferenced);
				}

				// underscores translate to spaces in the visible name
				@hotkey('a')
				void Save_As(FileName!() filename) {
					import std.file;
					std.file.write(previousFileReferenced, textEdit.content);
				}

				// you can put the annotations before or after the function name+args and it works the same way
				@separator
				void Exit() @accelerator("Alt+F4") @hotkey('x') {
					window.close();
				}
			}

			@menu("&Edit") {
				// not putting accelerators here because the text edit widget
				// does it locally, so no need to duplicate it globally.

				@icon(GenericIcons.Undo)
				void Undo() @toolbar("Undo") {
					textEdit.undo();
				}

				@separator

				@icon(GenericIcons.Cut)
				void Cut() @toolbar("Edit") {
					textEdit.cut();
				}
				@icon(GenericIcons.Copy)
				void Copy() @toolbar("Edit") {
					textEdit.copy();
				}
				@icon(GenericIcons.Paste)
				void Paste() @toolbar("Edit") {
					textEdit.paste();
				}

				@separator
				void Select_All() {
					textEdit.selectAll();
				}
			}

			@menu("Help") {
				void About() @accelerator("F1") {
					window.messageBox("A minigui sample program.");
				}

				// @label changes the name in the menu from what is in the code
				@label("In Menu Name")
				void otherNameInCode() {}
			}
		}

		// declare the object that holds the commands, and set
		// and members you want from it
		Commands commands;

		// and now tell minigui to do its magic and create the ui for it!
		window.setMenuAndToolbarFromAnnotatedCode(commands);

		// then, loop the window normally;
		window.loop();

		// important to note that the `commands` variable must live through the window's whole life cycle,
		// or you can have crashes. If you declare the variable and loop in different functions, make sure
		// you do `new Commands` so the garbage collector can take over management of it for you.
	}
	---

	Note that you can call this function multiple times and it will add the items in order to the given items.

	+/
	void setMenuAndToolbarFromAnnotatedCode(T)(ref T t) if(!is(T == class) && !is(T == interface)) {
		setMenuAndToolbarFromAnnotatedCode_internal(t);
	}
	/// ditto
	void setMenuAndToolbarFromAnnotatedCode(T)(T t) if(is(T == class) || is(T == interface)) {
		setMenuAndToolbarFromAnnotatedCode_internal(t);
	}
	void setMenuAndToolbarFromAnnotatedCode_internal(T)(ref T t) {
		auto menuBar = this.menuBar is null ? new MenuBar() : this.menuBar;
		Menu[string] mcs;

		alias ToolbarSection = ToolBar.ToolbarSection;
		ToolbarSection[] toolbarSections;

		foreach(menu; menuBar.subMenus) {
			mcs[menu.label] = menu;
		}

		foreach(memberName; __traits(derivedMembers, T)) {
			static if(memberName != "this")
			static if(hasAnyRelevantAnnotations!(__traits(getAttributes, __traits(getMember, T, memberName)))) {
				.menu menu;
				.toolbar toolbar;
				bool separator;
				.accelerator accelerator;
				.hotkey hotkey;
				.icon icon;
				string label;
				string tip;
				foreach(attr; __traits(getAttributes, __traits(getMember, T, memberName))) {
					static if(is(typeof(attr) == .menu))
						menu = attr;
					else static if(is(typeof(attr) == .toolbar))
						toolbar = attr;
					else static if(is(attr == .separator))
						separator = true;
					else static if(is(typeof(attr) == .accelerator))
						accelerator = attr;
					else static if(is(typeof(attr) == .hotkey))
						hotkey = attr;
					else static if(is(typeof(attr) == .icon))
						icon = attr;
					else static if(is(typeof(attr) == .label))
						label = attr.label;
					else static if(is(typeof(attr) == .tip))
						tip = attr.tip;
				}

				if(menu !is .menu.init || toolbar !is .toolbar.init) {
					ushort correctIcon = icon.id; // FIXME
					if(label.length == 0)
						label = memberName.toMenuLabel;

					auto handler = makeAutomaticHandler!(__traits(getMember, T, memberName))(this.parentWindow, &__traits(getMember, t, memberName));

					auto action = new Action(label, correctIcon, handler);

					if(accelerator.keyString.length) {
						auto ke = KeyEvent.parse(accelerator.keyString);
						action.accelerator = ke;
						accelerators[ke.toStr] = handler;
					}

					if(toolbar !is .toolbar.init) {
						bool found;
						foreach(ref section; toolbarSections)
							if(section.name == toolbar.groupName) {
								section.actions ~= action;
								found = true;
								break;
							}
						if(!found) {
							toolbarSections ~= ToolbarSection(toolbar.groupName, [action]);
						}
					}
					if(menu !is .menu.init) {
						Menu mc;
						if(menu.name in mcs) {
							mc = mcs[menu.name];
						} else {
							mc = new Menu(menu.name, this);
							menuBar.addItem(mc);
							mcs[menu.name] = mc;
						}

						if(separator)
							mc.addSeparator();
						auto mi = mc.addItem(new MenuItem(action));

						if(hotkey !is .hotkey.init)
							mi.hotkey = hotkey.ch;
					}
				}
			}
		}

		this.menuBar = menuBar;

		if(toolbarSections.length) {
			auto tb = new ToolBar(toolbarSections, this);
		}
	}

	void delegate()[string] accelerators;

	override void defaultEventHandler_keydown(KeyDownEvent event) {
		auto str = event.originalKeyEvent.toStr;
		if(auto acl = str in accelerators)
			(*acl)();

		// Windows this this automatically so only on custom need we implement it
		version(custom_widgets) {
			if(event.altKey && this.menuBar) {
				foreach(item; this.menuBar.items) {
					if(item.hotkey == keyToLetterCharAssumingLotsOfThingsThatYouMightBetterNotAssume(event.key)) {
						// FIXME this kinda sucks but meh just pretending to click on it to trigger other existing mediocre code
						item.dynamicState = DynamicState.hover | DynamicState.depressed;
						item.redraw();
						auto e = new MouseDownEvent(item);
						e.dispatch();
						break;
					}
				}
			}

			if(event.key == Key.Menu) {
				showContextMenu(-1, -1);
			}
		}

		super.defaultEventHandler_keydown(event);
	}

	override void defaultEventHandler_mouseover(MouseOverEvent event) {
		super.defaultEventHandler_mouseover(event);
		if(this.statusBar !is null && event.target.statusTip.length)
			this.statusBar.parts[0].content = event.target.statusTip;
		else if(this.statusBar !is null && this.statusTip.length)
			this.statusBar.parts[0].content = this.statusTip; // ~ " " ~ event.target.toString();
	}

	override void addChild(Widget c, int position = int.max) {
		if(auto tb = cast(ToolBar) c)
			version(win32_widgets)
				super.addChild(c, 0);
			else version(custom_widgets)
				super.addChild(c, menuBar ? 1 : 0);
			else static assert(0);
		else
			clientArea.addChild(c, position);
	}

	ToolBar _toolBar;
	///
	ToolBar toolBar() { return _toolBar; }
	///
	ToolBar toolBar(ToolBar t) {
		_toolBar = t;
		foreach(child; this.children)
			if(child is t)
				return t;
		version(win32_widgets)
			super.addChild(t, 0);
		else version(custom_widgets)
			super.addChild(t, menuBar ? 1 : 0);
		else static assert(0);
		return t;
	}

	MenuBar _menu;
	///
	MenuBar menuBar() { return _menu; }
	///
	MenuBar menuBar(MenuBar m) {
		if(m is _menu) {
			version(custom_widgets)
				queueRecomputeChildLayout();
			return m;
		}

		if(_menu !is null) {
			// make sure it is sanely removed
			// FIXME
		}

		_menu = m;

		version(win32_widgets) {
			SetMenu(parentWindow.win.impl.hwnd, m.handle);
		} else version(custom_widgets) {
			super.addChild(m, 0);

		//	clientArea.y = menu.height;
		//	clientArea.height = this.height - menu.height;

			queueRecomputeChildLayout();
		} else static assert(false);

		return _menu;
	}
	private Widget _clientArea;
	///
	@property Widget clientArea() { return _clientArea; }
	protected @property void clientArea(Widget wid) {
		_clientArea = wid;
	}

	private StatusBar _statusBar;
	/++
		Returns the window's [StatusBar]. Be warned it may be `null`.
	+/
	@property StatusBar statusBar() { return _statusBar; }
	/// ditto
	@property void statusBar(StatusBar bar) {
		if(_statusBar !is null)
			_statusBar.removeWidget();
		_statusBar = bar;
		if(bar !is null)
			super.addChild(_statusBar);
	}
}

/+
	This is really an implementation detail of [MainWindow]
+/
private class ClientAreaWidget : Widget {
	this() {
		this.tabStop = false;
		super(null);
		//sa = new ScrollableWidget(this);
	}
	/*
	ScrollableWidget sa;
	override void addChild(Widget w, int position) {
		if(sa is null)
			super.addChild(w, position);
		else {
			sa.addChild(w, position);
			sa.setContentSize(this.minWidth + 1, this.minHeight);
			writeln(sa.contentWidth, "x", sa.contentHeight);
		}
	}
	*/
}

/**
	Toolbars are lists of buttons (typically icons) that appear under the menu.
	Each button ought to correspond to a menu item, represented by [Action] objects.
*/
class ToolBar : Widget {
	version(win32_widgets) {
		private int idealHeight;
		override int minHeight() { return idealHeight; }
		override int maxHeight() { return idealHeight; }
	} else version(custom_widgets) {
		override int minHeight() { return toolbarIconSize; }// defaultLineHeight * 3/2; }
		override int maxHeight() { return toolbarIconSize; } //defaultLineHeight * 3/2; }
	} else static assert(false);
	override int heightStretchiness() { return 0; }

	static struct ToolbarSection {
		string name;
		Action[] actions;
	}

	version(win32_widgets) {
		HIMAGELIST imageListSmall;
		HIMAGELIST imageListLarge;
	}

	this(Widget parent) {
		this(cast(ToolbarSection[]) null, parent);
	}

	version(win32_widgets)
	void changeIconSize(bool useLarge) {
		SendMessageW(hwnd, TB_SETIMAGELIST, cast(WPARAM) 0, cast(LPARAM) (useLarge ? imageListLarge : imageListSmall));

		/+
		SIZE size;
		import core.sys.windows.commctrl;
		SendMessageW(hwnd, TB_GETMAXSIZE, 0, cast(LPARAM) &size);
		idealHeight = size.cy + 4; // the plus 4 is a hack
		+/

		idealHeight = useLarge ? 34 : 26;

		if(parent) {
			parent.queueRecomputeChildLayout();
			parent.redraw();
		}

		SendMessageW(hwnd, TB_SETBUTTONSIZE, 0, (idealHeight-4) << 16 | (idealHeight-4));
		SendMessageW(hwnd, TB_AUTOSIZE, 0, 0);
	}

	/++
		History:
			The `ToolbarSection` overload was added December 31, 2024
	+/
	this(Action[] actions, Widget parent) {
		this([ToolbarSection(null, actions)], parent);
	}

	/// ditto
	this(ToolbarSection[] sections, Widget parent) {
		super(parent);

		tabStop = false;

		version(win32_widgets) {
			// so i like how the flat thing looks on windows, but not on wine
			// and eh, with windows visual styles enabled it looks cool anyway soooo gonna
			// leave it commented
			createWin32Window(this, "ToolbarWindow32"w, "", TBSTYLE_LIST|/*TBSTYLE_FLAT|*/TBSTYLE_TOOLTIPS);

			SendMessageW(hwnd, TB_SETEXTENDEDSTYLE, 0, 8/*TBSTYLE_EX_MIXEDBUTTONS*/);

			imageListSmall = ImageList_Create(
				// width, height
				16, 16,
				ILC_COLOR16 | ILC_MASK,
				16 /*numberOfButtons*/, 0);

			imageListLarge = ImageList_Create(
				// width, height
				24, 24,
				ILC_COLOR16 | ILC_MASK,
				16 /*numberOfButtons*/, 0);

			SendMessageW(hwnd, TB_SETIMAGELIST, cast(WPARAM) 0, cast(LPARAM) imageListSmall);
			SendMessageW(hwnd, TB_LOADIMAGES, cast(WPARAM) IDB_STD_SMALL_COLOR, cast(LPARAM) HINST_COMMCTRL);

			SendMessageW(hwnd, TB_SETIMAGELIST, cast(WPARAM) 0, cast(LPARAM) imageListLarge);
			SendMessageW(hwnd, TB_LOADIMAGES, cast(WPARAM) IDB_STD_LARGE_COLOR, cast(LPARAM) HINST_COMMCTRL);

			SendMessageW(hwnd, TB_SETMAXTEXTROWS, 0, 0);

			TBBUTTON[] buttons;

			// FIXME: I_IMAGENONE is if here is no icon
			foreach(sidx, section; sections) {
				if(sidx)
					buttons ~= TBBUTTON(
						scaleWithDpi(4),
						0,
						TBSTATE_ENABLED, // state
						TBSTYLE_SEP | BTNS_SEP, // style
						0, // reserved array, just zero it out
						0, // dwData
						-1
					);

				foreach(action; section.actions)
					buttons ~= TBBUTTON(
						MAKELONG(cast(ushort)(action.iconId ? (action.iconId - 1) : -2 /* I_IMAGENONE */), 0),
						action.id,
						TBSTATE_ENABLED, // state
						0, // style
						0, // reserved array, just zero it out
						0, // dwData
						cast(size_t) toWstringzInternal(action.label) // INT_PTR
					);
			}

			SendMessageW(hwnd, TB_BUTTONSTRUCTSIZE, cast(WPARAM)TBBUTTON.sizeof, 0);
			SendMessageW(hwnd, TB_ADDBUTTONSW, cast(WPARAM) buttons.length, cast(LPARAM)buttons.ptr);

			/*
			RECT rect;
			GetWindowRect(hwnd, &rect);
			idealHeight = rect.bottom - rect.top + 10; // the +10 is a hack since the size right now doesn't look right on a real Windows XP box
			*/

			dpiChanged(); // to load the things calling changeIconSize the first time

			assert(idealHeight);
		} else version(custom_widgets) {
			foreach(sidx, section; sections) {
				if(sidx)
					new HorizontalSpacer(4, this);
				foreach(action; section.actions)
					new ToolButton(action, this);
			}
		} else static assert(false);
	}

	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}


	version(win32_widgets)
	override protected void dpiChanged() {
		auto sz = scaleWithDpi(16);
		if(sz >= 20)
			changeIconSize(true);
		else
			changeIconSize(false);
	}
}

/// An implementation helper for [ToolBar]. Generally, you shouldn't create these yourself and instead just pass [Action]s to [ToolBar]'s constructor and let it create the buttons for you.
class ToolButton : Button {
	///
	this(Action action, Widget parent) {
		super(action.label, parent);
		tabStop = false;
		this.action = action;
	}

	version(custom_widgets)
	override void defaultEventHandler_click(ClickEvent event) {
		foreach(handler; action.triggered)
			handler();
	}

	Action action;

	override int maxWidth() { return toolbarIconSize; }
	override int minWidth() { return toolbarIconSize; }
	override int maxHeight() { return toolbarIconSize; }
	override int minHeight() { return toolbarIconSize; }

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
	painter.drawThemed(delegate Rectangle (const Rectangle bounds) {
		painter.outlineColor = Color.black;

		immutable multiplier = toolbarIconSize / 4;
		immutable divisor = 16 / 4;

		int ScaledNumber(int n) {
			// return n * multiplier / divisor;
			auto s = n * multiplier;
			auto it = s / divisor;
			auto rem = s % divisor;
			if(rem && n >= 8) // cuz the original used 0 .. 16 and we want to try to stay centered so things in the bottom half tend to be added a it
				it++;
			return it;
		}

		arsd.color.Point Point(int x, int y) {
			return arsd.color.Point(ScaledNumber(x), ScaledNumber(y));
		}

		switch(action.iconId) {
			case GenericIcons.New:
				painter.fillColor = Color.white;
				painter.drawPolygon(
					Point(3, 2), Point(3, 13), Point(12, 13), Point(12, 6),
					Point(8, 2), Point(8, 6), Point(12, 6), Point(8, 2),
					Point(3, 2), Point(3, 13)
				);
			break;
			case GenericIcons.Save:
				painter.fillColor = Color.white;
				painter.outlineColor = Color.black;
				painter.drawRectangle(Point(2, 2), Point(13, 13));

				// the label
				painter.drawRectangle(Point(4, 8), Point(11, 13));

				// the slider
				painter.fillColor = Color.black;
				painter.outlineColor = Color.black;
				painter.drawRectangle(Point(4, 3), Point(10, 6));

				painter.fillColor = Color.white;
				painter.outlineColor = Color.white;
				// the disc window
				painter.drawRectangle(Point(5, 3), Point(6, 5));
			break;
			case GenericIcons.Open:
				painter.fillColor = Color.white;
				painter.drawPolygon(
					Point(4, 4), Point(4, 12), Point(13, 12), Point(13, 3),
					Point(9, 3), Point(9, 4), Point(4, 4));
				painter.drawPolygon(
					Point(2, 6), Point(11, 6),
					Point(12, 12), Point(4, 12),
					Point(2, 6));
				//painter.drawLine(Point(9, 6), Point(13, 7));
			break;
			case GenericIcons.Copy:
				painter.fillColor = Color.white;
				painter.drawRectangle(Point(3, 2), Point(9, 10));
				painter.drawRectangle(Point(6, 5), Point(12, 13));
			break;
			case GenericIcons.Cut:
				painter.fillColor = Color.transparent;
				painter.outlineColor = getComputedStyle.foregroundColor();
				painter.drawLine(Point(3, 2), Point(10, 9));
				painter.drawLine(Point(4, 9), Point(11, 2));
				painter.drawRectangle(Point(3, 9), Point(5, 13));
				painter.drawRectangle(Point(9, 9), Point(11, 12));
			break;
			case GenericIcons.Paste:
				painter.fillColor = Color.white;
				painter.drawRectangle(Point(2, 3), Point(11, 11));
				painter.drawRectangle(Point(6, 8), Point(13, 13));
				painter.drawLine(Point(6, 2), Point(4, 5));
				painter.drawLine(Point(6, 2), Point(9, 5));
				painter.fillColor = Color.black;
				painter.drawRectangle(Point(4, 5), Point(9, 6));
			break;
			case GenericIcons.Help:
				painter.outlineColor = getComputedStyle.foregroundColor();
				painter.drawText(arsd.color.Point(0, 0), "?", arsd.color.Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);
			break;
			case GenericIcons.Undo:
				painter.fillColor = Color.transparent;
				painter.drawArc(Point(3, 4), ScaledNumber(9), ScaledNumber(9), 0, 360 * 64);
				painter.outlineColor = Color.black;
				painter.fillColor = Color.black;
				painter.drawPolygon(
					Point(4, 4),
					Point(8, 2),
					Point(8, 6),
					Point(4, 4),
				);
			break;
			case GenericIcons.Redo:
				painter.fillColor = Color.transparent;
				painter.drawArc(Point(3, 4), ScaledNumber(9), ScaledNumber(9), 0, 360 * 64);
				painter.outlineColor = Color.black;
				painter.fillColor = Color.black;
				painter.drawPolygon(
					Point(10, 4),
					Point(6, 2),
					Point(6, 6),
					Point(10, 4),
				);
			break;
			default:
				painter.outlineColor = getComputedStyle.foregroundColor;
				painter.drawText(arsd.color.Point(0, 0), action.label, arsd.color.Point(width, height), TextAlignment.Center | TextAlignment.VerticalCenter);
		}
		return bounds;
		});
	}

}


/++
	You can make one of thse yourself but it is generally easer to use [MainWindow.setMenuAndToolbarFromAnnotatedCode].
+/
class MenuBar : Widget {
	MenuItem[] items;
	Menu[] subMenus;

	version(win32_widgets) {
		HMENU handle;
		///
		this(Widget parent = null) {
			super(parent);

			handle = CreateMenu();
			tabStop = false;
		}
	} else version(custom_widgets) {
		///
		this(Widget parent = null) {
			tabStop = false; // these are selected some other way
			super(parent);
		}

		mixin Padding!q{2};
	} else static assert(false);

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		draw3dFrame(this, painter, FrameStyle.risen, getComputedStyle().background.color);
	}

	///
	MenuItem addItem(MenuItem item) {
		this.addChild(item);
		items ~= item;
		version(win32_widgets) {
			AppendMenuW(handle, MF_STRING, item.action is null ? 9000 : item.action.id, toWstringzInternal(item.label));
		}
		return item;
	}


	///
	Menu addItem(Menu item) {

		subMenus ~= item;

		auto mbItem = new MenuItem(item.label, null);// this.parentWindow); // I'ma add the child down below so hopefully this isn't too insane

		addChild(mbItem);
		items ~= mbItem;

		version(win32_widgets) {
			AppendMenuW(handle, MF_STRING | MF_POPUP, cast(UINT) item.handle, toWstringzInternal(item.label));
		} else version(custom_widgets) {
			mbItem.defaultEventHandlers["mousedown"] = (Widget e, Event ev) {
				item.popup(mbItem);
			};
		} else static assert(false);

		return item;
	}

	override void recomputeChildLayout() {
		.recomputeChildLayout!"width"(this);
	}

	override int maxHeight() { return defaultLineHeight + 4; }
	override int minHeight() { return defaultLineHeight + 4; }
}


/**
	Status bars appear at the bottom of a MainWindow.
	They are made out of Parts, with a width and content.

	They can have multiple parts or be in simple mode. FIXME: implement simple mode.


	sb.parts[0].content = "Status bar text!";
*/
// https://learn.microsoft.com/en-us/windows/win32/controls/status-bars#owner-drawn-status-bars
class StatusBar : Widget {
	private Part[] partsArray;
	///
	struct Parts {
		@disable this();
		this(StatusBar owner) { this.owner = owner; }
		//@disable this(this);
		///
		@property int length() { return cast(int) owner.partsArray.length; }
		private StatusBar owner;
		private this(StatusBar owner, Part[] parts) {
			this.owner.partsArray = parts;
			this.owner = owner;
		}
		///
		Part opIndex(int p) {
			if(owner.partsArray.length == 0)
				this ~= new StatusBar.Part(0);
			return owner.partsArray[p];
		}

		///
		Part opOpAssign(string op : "~" )(Part p) {
			assert(owner.partsArray.length < 255);
			p.owner = this.owner;
			p.idx = cast(int) owner.partsArray.length;
			owner.partsArray ~= p;

			owner.queueRecomputeChildLayout();

			version(win32_widgets) {
				int[256] pos;
				int cpos;
				foreach(idx, part; owner.partsArray) {
					if(idx + 1 == owner.partsArray.length)
						pos[idx] = -1;
					else {
						cpos += part.currentlyAssignedWidth;
						pos[idx] = cpos;
					}
				}
				SendMessageW(owner.hwnd, WM_USER + 4 /*SB_SETPARTS*/, owner.partsArray.length, cast(size_t) pos.ptr);
			} else version(custom_widgets) {
				owner.redraw();
			} else static assert(false);

			return p;
		}

		/++
			Sets up proportional parts in one function call. You can use negative numbers to indicate device-independent pixels, and positive numbers to indicate proportions.

			No given item should be 0.

			History:
				Added December 31, 2024
		+/
		void setSizes(int[] proportions...) {
			assert(this.owner);
			this.owner.partsArray = null;

			foreach(n; proportions) {
				assert(n, "do not give 0 to statusBar.parts.set, it would make an invisible part. Try 1 instead.");

				this.opOpAssign!"~"(new StatusBar.Part(n > 0 ? n : -n, n > 0 ? StatusBar.Part.WidthUnits.Proportional : StatusBar.Part.WidthUnits.DeviceIndependentPixels));
			}

		}
	}

	private Parts _parts;
	///
	final @property Parts parts() {
		return _parts;
	}

	/++

	+/
	static class Part {
		/++
			History:
				Added September 1, 2023 (dub v11.1)
		+/
		enum WidthUnits {
			/++
				Unscaled pixels as they appear on screen.

				If you pass 0, it will treat it as a [Proportional] unit for compatibility with code written against older versions of minigui.
			+/
			DeviceDependentPixels,
			/++
				Pixels at the assumed DPI, but will be automatically scaled with the rest of the ui.
			+/
			DeviceIndependentPixels,
			/++
				An approximate character count in the currently selected font (at layout time) of the status bar. This will use the x-width (similar to css `ch`).
			+/
			ApproximateCharacters,
			/++
				These take a proportion of the remaining space in the window after all other parts have been assigned. The sum of all proportional parts is then divided by the current item to get the amount of space it uses.

				If you pass 0, it will assume that this item takes an average of all remaining proportional space. This is there primarily to provide compatibility with code written against older versions of minigui.
			+/
			Proportional
		}
		private WidthUnits units;
		private int width;
		private StatusBar owner;

		private int currentlyAssignedWidth;

		/++
			History:
				Prior to September 1, 2023, this took a default value of 100 and was interpreted as pixels, unless the value was 0 and it was the last item in the list, in which case it would use the remaining space in the window.

				It now allows you to provide your own value for [WidthUnits].

				Additionally, the default value used to be an arbitrary value of 100. It is now 0, to take advantage of the automatic proportional calculator in the new version. If you want the old behavior, pass `100, StatusBar.Part.WidthUnits.DeviceIndependentPixels`.
		+/
		this(int w, WidthUnits units = WidthUnits.Proportional) {
			this.units = units;
			this.width = w;
		}

		/// ditto
		this(int w = 0) {
			if(w == 0)
				this(w, WidthUnits.Proportional);
			else
				this(w, WidthUnits.DeviceDependentPixels);
		}

		private int idx;
		private string _content;
		///
		@property string content() { return _content; }
		///
		@property void content(string s) {
			version(win32_widgets) {
				_content = s;
				WCharzBuffer bfr = WCharzBuffer(s);
				SendMessageW(owner.hwnd, SB_SETTEXT, idx, cast(LPARAM) bfr.ptr);
			} else version(custom_widgets) {
				if(_content != s) {
					_content = s;
					owner.redraw();
				}
			} else static assert(false);
		}
	}
	string simpleModeContent;
	bool inSimpleMode;


	///
	this(Widget parent) {
		super(null); // FIXME
		_parts = Parts(this);
		tabStop = false;
		version(win32_widgets) {
			parentWindow = parent.parentWindow;
			createWin32Window(this, "msctls_statusbar32"w, "", 0);

			RECT rect;
			GetWindowRect(hwnd, &rect);
			idealHeight = rect.bottom - rect.top;
			assert(idealHeight);
		} else version(custom_widgets) {
		} else static assert(false);
	}

	override void recomputeChildLayout() {
		int remainingLength = this.width;

		int proportionalSum;
		int proportionalCount;
		foreach(idx, part; this.partsArray) {
			with(Part.WidthUnits)
			final switch(part.units) {
				case DeviceDependentPixels:
					part.currentlyAssignedWidth = part.width;
					remainingLength -= part.currentlyAssignedWidth;
				break;
				case DeviceIndependentPixels:
					part.currentlyAssignedWidth = scaleWithDpi(part.width);
					remainingLength -= part.currentlyAssignedWidth;
				break;
				case ApproximateCharacters:
					auto cs = getComputedStyle();
					auto font = cs.font;

					part.currentlyAssignedWidth = font.averageWidth * this.width;
					remainingLength -= part.currentlyAssignedWidth;
				break;
				case Proportional:
					proportionalSum += part.width;
					proportionalCount ++;
				break;
			}
		}

		foreach(part; this.partsArray) {
			if(part.units == Part.WidthUnits.Proportional) {
				auto proportion = part.width == 0 ? proportionalSum / proportionalCount : part.width;
				if(proportion == 0)
					proportion = 1;

				if(proportionalSum == 0)
					proportionalSum = proportionalCount;

				part.currentlyAssignedWidth = remainingLength * proportion / proportionalSum;
			}
		}

		super.recomputeChildLayout();
	}

	version(win32_widgets)
	override protected void dpiChanged() {
		RECT rect;
		GetWindowRect(hwnd, &rect);
		idealHeight = rect.bottom - rect.top;
		assert(idealHeight);
	}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		this.draw3dFrame(painter, FrameStyle.sunk, cs.background.color);
		int cpos = 0;
		foreach(idx, part; this.partsArray) {
			auto partWidth = part.currentlyAssignedWidth;
			// part.width ? part.width : ((idx + 1 == this.partsArray.length) ? remainingLength : 100);
			painter.setClipRectangle(Point(cpos, 0), partWidth, height);
			draw3dFrame(cpos, 0, partWidth, height, painter, FrameStyle.sunk, cs.background.color);
			painter.setClipRectangle(Point(cpos + 2, 2), partWidth - 4, height - 4);

			painter.outlineColor = cs.foregroundColor();
			painter.fillColor = cs.foregroundColor();

			painter.drawText(Point(cpos + 4, 0), part.content, Point(width, height), TextAlignment.VerticalCenter);
			cpos += partWidth;
		}
	}


	version(win32_widgets) {
		private int idealHeight;
		override int maxHeight() { return idealHeight; }
		override int minHeight() { return idealHeight; }
	} else version(custom_widgets) {
		override int maxHeight() { return defaultLineHeight + 4; }
		override int minHeight() { return defaultLineHeight + 4; }
	} else static assert(false);
}

/// Displays an in-progress indicator without known values
version(none)
class IndefiniteProgressBar : Widget {
	version(win32_widgets)
	this(Widget parent) {
		super(parent);
		createWin32Window(this, "msctls_progress32"w, "", 8 /* PBS_MARQUEE */);
		tabStop = false;
	}
	override int minHeight() { return 10; }
}

/// A progress bar with a known endpoint and completion amount
class ProgressBar : Widget {
	/++
		History:
			Added March 16, 2022 (dub v10.7)
	+/
	this(int min, int max, Widget parent) {
		this(parent);
		setRange(cast(ushort) min, cast(ushort) max); // FIXME
	}
	this(Widget parent) {
		version(win32_widgets) {
			super(parent);
			createWin32Window(this, "msctls_progress32"w, "", 0);
			tabStop = false;
		} else version(custom_widgets) {
			super(parent);
			max = 100;
			step = 10;
			tabStop = false;
		} else static assert(0);
	}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		this.draw3dFrame(painter, FrameStyle.sunk, cs.background.color);
		painter.fillColor = cs.progressBarColor;
		painter.drawRectangle(Point(0, 0), width * current / max, height);
	}


	version(custom_widgets) {
		int current;
		int max;
		int step;
	}

	///
	void advanceOneStep() {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_STEPIT, 0, 0);
		else version(custom_widgets)
			addToPosition(step);
		else static assert(false);
	}

	///
	void setStepIncrement(int increment) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_SETSTEP, increment, 0);
		else version(custom_widgets)
			step = increment;
		else static assert(false);
	}

	///
	void addToPosition(int amount) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_DELTAPOS, amount, 0);
		else version(custom_widgets)
			setPosition(current + amount);
		else static assert(false);
	}

	///
	void setPosition(int pos) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_SETPOS, pos, 0);
		else version(custom_widgets) {
			current = pos;
			if(current > max)
				current = max;
			redraw();
		}
		else static assert(false);
	}

	///
	void setRange(ushort min, ushort max) {
		version(win32_widgets)
			SendMessageW(hwnd, PBM_SETRANGE, 0, MAKELONG(min, max));
		else version(custom_widgets) {
			this.max = max;
		}
		else static assert(false);
	}

	override int minHeight() { return 10; }
}

version(custom_widgets)
private void extractWindowsStyleLabel(scope const char[] label, out string thisLabel, out dchar thisAccelerator) {
	thisLabel.reserve(label.length);
	bool justSawAmpersand;
	foreach(ch; label) {
		if(justSawAmpersand) {
			justSawAmpersand = false;
			if(ch == '&') {
				goto plain;
			}
			thisAccelerator = ch;
		} else {
			if(ch == '&') {
				justSawAmpersand = true;
				continue;
			}
			plain:
			thisLabel ~= ch;
		}
	}
}

/++
	Creates the fieldset (also known as a group box) with the given label. A fieldset is generally used a container for mutually exclusive [Radiobox]s.


	Please note that the ampersand (&) character gets special treatment as described on this page https://docs.microsoft.com/en-us/windows/win32/menurc/common-control-parameters?redirectedfrom=MSDN

	Use double-ampersand, "First && Second", to be displayed as a single one, "First & Second".

	History:
		The ampersand behavior was always the case on Windows, but it wasn't until June 15, 2021 when Linux was changed to match it and the documentation updated to reflect it.
+/
class Fieldset : Widget {
	// FIXME: on Windows,it doesn't draw the background on the label
	// on X, it doesn't fix the clipping rectangle for it
	version(win32_widgets)
		override int paddingTop() { return defaultLineHeight; }
	else version(custom_widgets)
		override int paddingTop() { return defaultLineHeight + 2; }
	else static assert(false);
	override int paddingBottom() { return 6; }
	override int paddingLeft() { return 6; }
	override int paddingRight() { return 6; }

	override int marginLeft() { return 6; }
	override int marginRight() { return 6; }
	override int marginTop() { return 2; }
	override int marginBottom() { return 2; }

	string legend;

	version(custom_widgets) private dchar accelerator;

	this(string legend, Widget parent) {
		version(win32_widgets) {
			super(parent);
			this.legend = legend;
			createWin32Window(this, "button"w, legend, BS_GROUPBOX);
			tabStop = false;
		} else version(custom_widgets) {
			super(parent);
			tabStop = false;

			legend.extractWindowsStyleLabel(this.legend, this.accelerator);
		} else static assert(0);
	}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto dlh = defaultLineHeight;

		painter.fillColor = Color.transparent;
		auto cs = getComputedStyle();
		painter.pen = Pen(cs.foregroundColor, 1);
		painter.drawRectangle(Point(0, dlh / 2), width, height - dlh / 2);

		auto tx = painter.textSize(legend);
		painter.outlineColor = Color.transparent;

		version(Windows) {
			auto b = SelectObject(painter.impl.hdc, GetSysColorBrush(COLOR_3DFACE));
			painter.drawRectangle(Point(8, -tx.height/2), tx.width, tx.height);
			SelectObject(painter.impl.hdc, b);
		} else static if(UsingSimpledisplayX11) {
			painter.fillColor = getComputedStyle().windowBackgroundColor;
			painter.drawRectangle(Point(8, 0), tx.width, tx.height);
		}
		painter.outlineColor = cs.foregroundColor;
		painter.drawText(Point(8, 0), legend);
	}

	override int maxHeight() {
		auto m = paddingTop() + paddingBottom();
		foreach(child; children) {
			auto mh = child.maxHeight();
			if(mh == int.max)
				return int.max;
			m += mh;
			m += child.marginBottom();
			m += child.marginTop();
		}
		m += 6;
		if(m < minHeight)
			return minHeight;
		return m;
	}

	override int minHeight() {
		auto m = paddingTop() + paddingBottom();
		foreach(child; children) {
			m += child.minHeight();
			m += child.marginBottom();
			m += child.marginTop();
		}
		return m + 6;
	}

	override int minWidth() {
		return 6 + cast(int) this.legend.length * 7;
	}
}

/++
	$(IMG //arsdnet.net/minigui-screenshots/windows/Fieldset.png, A box saying "baby will" with three round buttons inside it for the options of "eat", "cry", and "sleep")
	$(IMG //arsdnet.net/minigui-screenshots/linux/Fieldset.png, Same thing, but in the default Linux theme.)
+/
version(minigui_screenshots)
@Screenshot("Fieldset")
unittest {
	auto window = new Window(200, 100);
	auto set = new Fieldset("Baby will", window);
	auto option1 = new Radiobox("Eat", set);
	auto option2 = new Radiobox("Cry", set);
	auto option3 = new Radiobox("Sleep", set);
	window.loop();
}

/// Draws a line
class HorizontalRule : Widget {
	mixin Margin!q{ 2 };
	override int minHeight() { return 2; }
	override int maxHeight() { return 2; }

	///
	this(Widget parent) {
		super(parent);
	}

	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		painter.outlineColor = cs.darkAccentColor;
		painter.drawLine(Point(0, 0), Point(width, 0));
		painter.outlineColor = cs.lightAccentColor;
		painter.drawLine(Point(0, 1), Point(width, 1));
	}
}

version(minigui_screenshots)
@Screenshot("HorizontalRule")
/++
	$(IMG //arsdnet.net/minigui-screenshots/linux/HorizontalRule.png, Same thing, but in the default Linux theme.)

+/
unittest {
	auto window = new Window(200, 100);
	auto above = new TextLabel("Above the line", TextAlignment.Left, window);
	new HorizontalRule(window);
	auto below = new TextLabel("Below the line", TextAlignment.Left, window);
	window.loop();
}

/// ditto
class VerticalRule : Widget {
	mixin Margin!q{ 2 };
	override int minWidth() { return 2; }
	override int maxWidth() { return 2; }

	///
	this(Widget parent) {
		super(parent);
	}

	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		painter.outlineColor = cs.darkAccentColor;
		painter.drawLine(Point(0, 0), Point(0, height));
		painter.outlineColor = cs.lightAccentColor;
		painter.drawLine(Point(1, 0), Point(1, height));
	}
}


///
class Menu : Window {
	void remove() {
		foreach(i, child; parentWindow.children)
			if(child is this) {
				parentWindow._children = parentWindow._children[0 .. i] ~ parentWindow._children[i + 1 .. $];
				break;
			}
		parentWindow.redraw();

		parentWindow.releaseMouseCapture();
	}

	///
	void addSeparator() {
		version(win32_widgets)
			AppendMenu(handle, MF_SEPARATOR, 0, null);
		else version(custom_widgets)
			auto hr = new HorizontalRule(this);
		else static assert(0);
	}

	override int paddingTop() { return 4; }
	override int paddingBottom() { return 4; }
	override int paddingLeft() { return 2; }
	override int paddingRight() { return 2; }

	version(win32_widgets) {}
	else version(custom_widgets) {

		Widget previouslyFocusedWidget;
		Widget* previouslyFocusedWidgetBelongsIn;

		SimpleWindow dropDown;
		Widget menuParent;
		void popup(Widget parent, int offsetX = 0, int offsetY = int.min) {
			this.menuParent = parent;

			previouslyFocusedWidget = parent.parentWindow.focusedWidget;
			previouslyFocusedWidgetBelongsIn = &parent.parentWindow.focusedWidget;
			parent.parentWindow.focusedWidget = this;

			int w = 150;
			int h = paddingTop + paddingBottom;
			if(this.children.length) {
				// hacking it to get the ideal height out of recomputeChildLayout
				this.width = w;
				this.height = h;
				this.recomputeChildLayoutEntry();
				h = this.children[$-1].y + this.children[$-1].height + this.children[$-1].marginBottom;
				h += paddingBottom;

				h -= 2; // total hack, i just like the way it looks a bit tighter even though technically MenuItem reserves some space to center in normal circumstances
			}

			if(offsetY == int.min)
				offsetY = parent.defaultLineHeight;

			auto coord = parent.globalCoordinates();
			dropDown.moveResize(coord.x + offsetX, coord.y + offsetY, w, h);
			this.x = 0;
			this.y = 0;
			this.width = dropDown.width;
			this.height = dropDown.height;
			this.drawableWindow = dropDown;
			this.recomputeChildLayoutEntry();

			static if(UsingSimpledisplayX11)
				XSync(XDisplayConnection.get, 0);

			dropDown.visibilityChanged = (bool visible) {
				if(visible) {
					this.redraw();
					dropDown.grabInput();
				} else {
					dropDown.releaseInputGrab();
				}
			};

			dropDown.show();

			clickListener = this.addEventListener((scope ClickEvent ev) {
				unpopup();
				// need to unlock asap just in case other user handlers block...
				static if(UsingSimpledisplayX11)
					flushGui();
			}, true /* again for asap action */);
		}

		EventListener clickListener;
	}
	else static assert(false);

	version(custom_widgets)
	void unpopup() {
		mouseLastOver = mouseLastDownOn = null;
		dropDown.hide();
		if(!menuParent.parentWindow.win.closed) {
			if(auto maw = cast(MouseActivatedWidget) menuParent) {
				maw.setDynamicState(DynamicState.depressed, false);
				maw.setDynamicState(DynamicState.hover, false);
				maw.redraw();
			}
			// menuParent.parentWindow.win.focus();
		}
		clickListener.disconnect();

		if(previouslyFocusedWidgetBelongsIn)
			*previouslyFocusedWidgetBelongsIn = previouslyFocusedWidget;
	}

	MenuItem[] items;

	///
	MenuItem addItem(MenuItem item) {
		addChild(item);
		items ~= item;
		version(win32_widgets) {
			AppendMenuW(handle, MF_STRING, item.action is null ? 9000 : item.action.id, toWstringzInternal(item.label));
		}
		return item;
	}

	string label;

	version(win32_widgets) {
		HMENU handle;
		///
		this(string label, Widget parent) {
			// not actually passing the parent since it effs up the drawing
			super(cast(Widget) null);// parent);
			this.label = label;
			handle = CreatePopupMenu();
		}
	} else version(custom_widgets) {
		///
		this(string label, Widget parent) {

			if(dropDown) {
				dropDown.close();
			}
			dropDown = new SimpleWindow(
				150, 4,
				// FIXME: what if it is a popupMenu ?
				null, OpenGlOptions.no, Resizability.fixedSize, WindowTypes.dropdownMenu, WindowFlags.dontAutoShow, parent ? parent.parentWindow.win : null);

			this.label = label;

			super(dropDown);
		}
	} else static assert(false);

	override int maxHeight() { return defaultLineHeight; }
	override int minHeight() { return defaultLineHeight; }

	version(custom_widgets) {
		Widget currentPlace;

		void changeCurrentPlace(Widget n) {
			if(currentPlace) {
				currentPlace.dynamicState = 0;
			}

			if(n) {
				n.dynamicState = DynamicState.hover;
			}

			currentPlace = n;
		}

		override void paint(WidgetPainter painter) {
			this.draw3dFrame(painter, FrameStyle.risen, getComputedStyle.background.color);
		}

		override void defaultEventHandler_keydown(KeyDownEvent ke) {
			switch(ke.key) {
				case Key.Down:
					Widget next;
					Widget first;
					foreach(w; this.children) {
						if((cast(MenuItem) w) is null)
							continue;

						if(first is null)
							first = w;

						if(next !is null) {
							next = w;
							break;
						}

						if(currentPlace is null) {
							next = w;
							break;
						}

						if(w is currentPlace) {
							next = w;
						}
					}

					if(next is currentPlace)
						next = first;

					changeCurrentPlace(next);
					break;
				case Key.Up:
					Widget prev;
					foreach(w; this.children) {
						if((cast(MenuItem) w) is null)
							continue;
						if(w is currentPlace) {
							if(prev is null) {
								foreach_reverse(c; this.children) {
									if((cast(MenuItem) c) !is null) {
										prev = c;
										break;
									}
								}
							}
							break;
						}
						prev = w;
					}
					changeCurrentPlace(prev);
					break;
				case Key.Left:
				case Key.Right:
					if(menuParent) {
						Menu first;
						Menu last;
						Menu prev;
						Menu next;
						bool found;

						size_t prev_idx;
						size_t next_idx;

						MenuBar mb = cast(MenuBar) menuParent.parent;

						if(mb) {
							foreach(idx, menu; mb.subMenus) {
								if(first is null)
									first = menu;
								last = menu;
								if(found && next is null) {
									next = menu;
									next_idx = idx;
								}
								if(menu is this)
									found = true;
								if(!found) {
									prev = menu;
									prev_idx = idx;
								}
							}

							Menu nextMenu;
							size_t nextMenuIdx;
							if(ke.key == Key.Left) {
								nextMenu = prev ? prev : last;
								nextMenuIdx = prev ? prev_idx : mb.subMenus.length - 1;
							} else {
								nextMenu = next ? next : first;
								nextMenuIdx = next ? next_idx : 0;
							}

							unpopup();

							auto rent = mb.children[nextMenuIdx]; // FIXME thsi is not necessarily right
							rent.dynamicState = DynamicState.depressed | DynamicState.hover;
							nextMenu.popup(rent);
						}
					}
					break;
				case Key.Enter:
				case Key.PadEnter:
					// because the key up and char events will go back to the other window after we unpopup!
					// we will wait for the char event to come (in the following method)
					break;
				case Key.Escape:
					unpopup();
					break;
				default:
			}
		}
		override void defaultEventHandler_char(CharEvent ke) {
			// if one is selected, enter activates it
			if(currentPlace) {
				if(ke.character == '\n') {
					// enter selects
					auto event = new Event(EventType.triggered, currentPlace);
					event.dispatch();
					unpopup();
					return;
				}
			}

			// otherwise search for a hotkey
			foreach(item; items) {
				if(item.hotkey == ke.character) {
					auto event = new Event(EventType.triggered, item);
					event.dispatch();
					unpopup();
					return;
				}
			}
		}
		override void defaultEventHandler_mouseover(MouseOverEvent moe) {
			if(moe.target && moe.target.parent is this)
				changeCurrentPlace(moe.target);
		}
	}
}

/++
	A MenuItem belongs to a [Menu] - use [Menu.addItem] to add one - and calls an [Action] when it is clicked.
+/
class MenuItem : MouseActivatedWidget {
	Menu submenu;

	Action action;
	string label;
	dchar hotkey;

	override int paddingLeft() { return 4; }

	override int maxHeight() { return defaultLineHeight + 4; }
	override int minHeight() { return defaultLineHeight + 4; }
	override int minWidth() { return defaultTextWidth(label) + 8 + scaleWithDpi(12); }
	override int maxWidth() {
		if(cast(MenuBar) parent) {
			return minWidth();
		}
		return int.max;
	}
	/// This should ONLY be used if there is no associated action, for example, if the menu item is just a submenu.
	this(string lbl, Widget parent = null) {
		super(parent);
		//label = lbl; // FIXME
		foreach(idx, char ch; lbl) // FIXME
			if(ch != '&') { // FIXME
				label ~= ch; // FIXME
			} else {
				if(idx + 1 < lbl.length) {
					hotkey = lbl[idx + 1];
					if(hotkey >= 'A' && hotkey <= 'Z')
						hotkey += 32;
				}
			}
		tabStop = false; // these are selected some other way
	}

	///
	this(Action action, Widget parent = null) {
		assert(action !is null);
		this(action.label, parent);
		this.action = action;
		tabStop = false; // these are selected some other way
	}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		if(dynamicState & DynamicState.depressed)
			this.draw3dFrame(painter, FrameStyle.sunk, cs.background.color);
		else {
			if(dynamicState & DynamicState.hover) {
				painter.fillColor = cs.hoveringColor;
				painter.outlineColor = Color.transparent;
			} else {
				painter.fillColor = cs.background.color;
				painter.outlineColor = Color.transparent;
			}

			painter.drawRectangle(Point(0, 0), Size(this.width, this.height));
		}

		if(dynamicState & DynamicState.hover)
			painter.outlineColor = cs.activeMenuItemColor;
		else
			painter.outlineColor = cs.foregroundColor;
		painter.fillColor = Color.transparent;
		painter.drawText(scaleWithDpi(Point(cast(MenuBar) this.parent ? 4 : 20, 0)), label, Point(width, height), TextAlignment.Left | TextAlignment.VerticalCenter);
		if(action && action.accelerator !is KeyEvent.init) {
			painter.drawText(scaleWithDpi(Point(cast(MenuBar) this.parent ? 4 : 20, 0)), action.accelerator.toStr(), Point(width - 4, height), TextAlignment.Right | TextAlignment.VerticalCenter);

		}
	}

	static class Style : Widget.Style {
		override bool variesWithState(ulong dynamicStateFlags) {
			return super.variesWithState(dynamicStateFlags) || (dynamicStateFlags & (DynamicState.depressed | DynamicState.hover));
		}
	}
	mixin OverrideStyle!Style;

	override void defaultEventHandler_triggered(Event event) {
		if(action)
		foreach(handler; action.triggered)
			handler();

		if(auto pmenu = cast(Menu) this.parent)
			pmenu.remove();

		super.defaultEventHandler_triggered(event);
	}
}

version(win32_widgets)
/// A "mouse activiated widget" is really just an abstract variant of button.
class MouseActivatedWidget : Widget {
	@property bool isChecked() {
		assert(hwnd);
		return SendMessageW(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED;

	}
	@property void isChecked(bool state) {
		assert(hwnd);
		SendMessageW(hwnd, BM_SETCHECK, state ? BST_CHECKED : BST_UNCHECKED, 0);

	}

	override void handleWmCommand(ushort cmd, ushort id) {
		if(cmd == 0) {
			auto event = new Event(EventType.triggered, this);
			event.dispatch();
		}
	}

	this(Widget parent) {
		super(parent);
	}
}
else version(custom_widgets)
/// ditto
class MouseActivatedWidget : Widget {
	@property bool isChecked() { return isChecked_; }
	@property bool isChecked(bool b) { isChecked_ = b; this.redraw(); return isChecked_;}

	private bool isChecked_;

	this(Widget parent) {
		super(parent);

		addEventListener((MouseDownEvent ev) {
			if(ev.button == MouseButton.left) {
				setDynamicState(DynamicState.depressed, true);
				setDynamicState(DynamicState.hover, true);
				redraw();
			}
		});

		addEventListener((MouseUpEvent ev) {
			if(ev.button == MouseButton.left) {
				setDynamicState(DynamicState.depressed, false);
				setDynamicState(DynamicState.hover, false);
				redraw();
			}
		});

		addEventListener((MouseMoveEvent mme) {
			if(!(mme.state & ModifierState.leftButtonDown)) {
				if(dynamicState_ & DynamicState.depressed) {
					setDynamicState(DynamicState.depressed, false);
					redraw();
				}
			}
		});
	}

	override void defaultEventHandler_focus(FocusEvent ev) {
		super.defaultEventHandler_focus(ev);
		this.redraw();
	}
	override void defaultEventHandler_blur(BlurEvent ev) {
		super.defaultEventHandler_blur(ev);
		setDynamicState(DynamicState.depressed, false);
		this.redraw();
	}
	override void defaultEventHandler_keydown(KeyDownEvent ev) {
		super.defaultEventHandler_keydown(ev);
		if(ev.key == Key.Space || ev.key == Key.Enter || ev.key == Key.PadEnter) {
			setDynamicState(DynamicState.depressed, true);
			setDynamicState(DynamicState.hover, true);
			this.redraw();
		}
	}
	override void defaultEventHandler_keyup(KeyUpEvent ev) {
		super.defaultEventHandler_keyup(ev);
		if(!(dynamicState & DynamicState.depressed))
			return;
		setDynamicState(DynamicState.depressed, false);
		setDynamicState(DynamicState.hover, false);
		this.redraw();

		auto event = new Event(EventType.triggered, this);
		event.sendDirectly();
	}
	override void defaultEventHandler_click(ClickEvent ev) {
		super.defaultEventHandler_click(ev);
		if(ev.button == MouseButton.left) {
			auto event = new Event(EventType.triggered, this);
			event.sendDirectly();
		}
	}

}
else static assert(false);

/*
/++
	Like the tablet thing, it would have a label, a description, and a switch slider thingy.

	Basically the same as a checkbox.
+/
class OnOffSwitch : MouseActivatedWidget {

}
*/

/++
	History:
		Added June 15, 2021 (dub v10.1)
+/
struct ImageLabel {
	/++
		Defines a label+image combo used by some widgets.

		If you provide just a text label, that is all the widget will try to
		display. Or just an image will display just that. If you provide both,
		it may display both text and image side by side or display the image
		and offer text on an input event depending on the widget.

		History:
			The `alignment` parameter was added on September 27, 2021
	+/
	this(string label, TextAlignment alignment = TextAlignment.Center) {
		this.label = label;
		this.displayFlags = DisplayFlags.displayText;
		this.alignment = alignment;
	}

	/// ditto
	this(string label, MemoryImage image, TextAlignment alignment = TextAlignment.Center) {
		this.label = label;
		this.image = image;
		this.displayFlags = DisplayFlags.displayText | DisplayFlags.displayImage;
		this.alignment = alignment;
	}

	/// ditto
	this(MemoryImage image, TextAlignment alignment = TextAlignment.Center) {
		this.image = image;
		this.displayFlags = DisplayFlags.displayImage;
		this.alignment = alignment;
	}

	/// ditto
	this(string label, MemoryImage image, int displayFlags, TextAlignment alignment = TextAlignment.Center) {
		this.label = label;
		this.image = image;
		this.alignment = alignment;
		this.displayFlags = displayFlags;
	}

	string label;
	MemoryImage image;

	enum DisplayFlags {
		displayText = 1 << 0,
		displayImage = 1 << 1,
	}

	int displayFlags = DisplayFlags.displayText | DisplayFlags.displayImage;

	TextAlignment alignment;
}

/++
	A basic checked or not checked box with an attached label.


	Please note that the ampersand (&) character gets special treatment as described on this page https://docs.microsoft.com/en-us/windows/win32/menurc/common-control-parameters?redirectedfrom=MSDN

	Use double-ampersand, "First && Second", to be displayed as a single one, "First & Second".

	History:
		The ampersand behavior was always the case on Windows, but it wasn't until June 15, 2021 when Linux was changed to match it and the documentation updated to reflect it.
+/
class Checkbox : MouseActivatedWidget {
	version(win32_widgets) {
		override int maxHeight() { return scaleWithDpi(16); }
		override int minHeight() { return scaleWithDpi(16); }
	} else version(custom_widgets) {
		private enum buttonSize = 16;
		override int maxHeight() { return mymax(defaultLineHeight, scaleWithDpi(buttonSize)); }
		override int minHeight() { return maxHeight(); }
	} else static assert(0);

	override int marginLeft() { return 4; }

	override int flexBasisWidth() { return 24 + cast(int) label.length * 7; }

	/++
		Just an alias because I keep typing checked out of web habit.

		History:
			Added May 31, 2021
	+/
	alias checked = isChecked;

	private string label;
	private dchar accelerator;

	/++
	+/
	this(string label, Widget parent) {
		this(ImageLabel(label), Appearance.checkbox, parent);
	}

	/// ditto
	this(string label, Appearance appearance, Widget parent) {
		this(ImageLabel(label), appearance, parent);
	}

	/++
		Changes the look and may change the ideal size of the widget without changing its behavior. The precise look is platform-specific.

		History:
			Added June 29, 2021 (dub v10.2)
	+/
	enum Appearance {
		checkbox, /// a normal checkbox
		pushbutton, /// a button that is showed as pushed when checked and up when unchecked. Similar to the bold button in a toolbar in Wordpad.
		//sliderswitch,
	}
	private Appearance appearance;

	/// ditto
	private this(ImageLabel label, Appearance appearance, Widget parent) {
		super(parent);
		version(win32_widgets) {
			this.label = label.label;

			uint extraStyle;
			final switch(appearance) {
				case Appearance.checkbox:
				break;
				case Appearance.pushbutton:
					extraStyle |= BS_PUSHLIKE;
				break;
			}

			createWin32Window(this, "button"w, label.label, BS_CHECKBOX | extraStyle);
		} else version(custom_widgets) {
			label.label.extractWindowsStyleLabel(this.label, this.accelerator);
		} else static assert(0);
	}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();
		if(isFocused()) {
			painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
			painter.fillColor = cs.windowBackgroundColor;
			painter.drawRectangle(Point(0, 0), width, height);
			painter.pen = Pen(Color.black, 1, Pen.Style.Solid);
		} else {
			painter.pen = Pen(cs.windowBackgroundColor, 1, Pen.Style.Solid);
			painter.fillColor = cs.windowBackgroundColor;
			painter.drawRectangle(Point(0, 0), width, height);
		}


		painter.outlineColor = Color.black;
		painter.fillColor = Color.white;
		enum rectOffset = 2;
		painter.drawRectangle(scaleWithDpi(Point(rectOffset, rectOffset)), scaleWithDpi(buttonSize - rectOffset - rectOffset), scaleWithDpi(buttonSize - rectOffset - rectOffset));

		if(isChecked) {
			auto size = scaleWithDpi(2);
			painter.pen = Pen(Color.black, size);
			// I'm using height so the checkbox is square
			enum padding = 3;
			painter.drawLine(
				scaleWithDpi(Point(rectOffset + padding, rectOffset + padding)),
				scaleWithDpi(Point(buttonSize - padding - rectOffset, buttonSize - padding - rectOffset)) - Point(1 - size % 2, 1 - size % 2)
			);
			painter.drawLine(
				scaleWithDpi(Point(buttonSize - padding - rectOffset, padding + rectOffset)) - Point(1 - size % 2, 0),
				scaleWithDpi(Point(padding + rectOffset, buttonSize - padding - rectOffset)) - Point(0,1 -  size % 2)
			);

			painter.pen = Pen(Color.black, 1);
		}

		if(label !is null) {
			painter.outlineColor = cs.foregroundColor();
			painter.fillColor = cs.foregroundColor();

			// i want the centerline of the text to be aligned with the centerline of the checkbox
			/+
			auto font = cs.font();
			auto y = scaleWithDpi(rectOffset + buttonSize / 2) - font.height / 2;
			painter.drawText(Point(scaleWithDpi(buttonSize + 4), y), label);
			+/
			painter.drawText(scaleWithDpi(Point(buttonSize + 4, rectOffset)), label, Point(width, height - scaleWithDpi(rectOffset)), TextAlignment.Left | TextAlignment.VerticalCenter);
		}
	}

	override void defaultEventHandler_triggered(Event ev) {
		isChecked = !isChecked;

		this.emit!(ChangeEvent!bool)(&isChecked);

		redraw();
	}

	/// Emits a change event with the checked state
	mixin Emits!(ChangeEvent!bool);
}

/// Adds empty space to a layout.
class VerticalSpacer : Widget {
	private int mh;

	/++
		History:
			The overload with `maxHeight` was added on December 31, 2024
	+/
	this(Widget parent) {
		this(0, parent);
	}

	/// ditto
	this(int maxHeight, Widget parent) {
		this.mh = maxHeight;
		super(parent);
		this.tabStop = false;
	}

	override int maxHeight() {
		return mh ? scaleWithDpi(mh) : super.maxHeight();
	}
}


/// ditto
class HorizontalSpacer : Widget {
	private int mw;

	/++
		History:
			The overload with `maxWidth` was added on December 31, 2024
	+/
	this(Widget parent) {
		this(0, parent);
	}

	/// ditto
	this(int maxWidth, Widget parent) {
		this.mw = maxWidth;
		super(parent);
		this.tabStop = false;
	}

	override int maxWidth() {
		return mw ? scaleWithDpi(mw) : super.maxWidth();
	}
}


/++
	Creates a radio button with an associated label. These are usually put inside a [Fieldset].


	Please note that the ampersand (&) character gets special treatment as described on this page https://docs.microsoft.com/en-us/windows/win32/menurc/common-control-parameters?redirectedfrom=MSDN

	Use double-ampersand, "First && Second", to be displayed as a single one, "First & Second".

	History:
		The ampersand behavior was always the case on Windows, but it wasn't until June 15, 2021 when Linux was changed to match it and the documentation updated to reflect it.
+/
class Radiobox : MouseActivatedWidget {

	version(win32_widgets) {
		override int maxHeight() { return scaleWithDpi(16); }
		override int minHeight() { return scaleWithDpi(16); }
	} else version(custom_widgets) {
		private enum buttonSize = 16;
		override int maxHeight() { return mymax(defaultLineHeight, scaleWithDpi(buttonSize)); }
		override int minHeight() { return maxHeight(); }
	} else static assert(0);

	override int marginLeft() { return 4; }

	// FIXME: make a label getter
	private string label;
	private dchar accelerator;

	/++

	+/
	this(string label, Widget parent) {
		super(parent);
		version(win32_widgets) {
			this.label = label;
			createWin32Window(this, "button"w, label, BS_AUTORADIOBUTTON);
		} else version(custom_widgets) {
			label.extractWindowsStyleLabel(this.label, this.accelerator);
			height = 16;
			width = height + 4 + cast(int) label.length * 16;
		}
	}

	version(custom_widgets)
	override void paint(WidgetPainter painter) {
		auto cs = getComputedStyle();

		if(isFocused) {
			painter.fillColor = cs.windowBackgroundColor;
			painter.pen = Pen(Color.black, 1, Pen.Style.Dotted);
		} else {
			painter.fillColor = cs.windowBackgroundColor;
			painter.outlineColor = cs.windowBackgroundColor;
		}
		painter.drawRectangle(Point(0, 0), width, height);

		painter.pen = Pen(Color.black, 1, Pen.Style.Solid);

		painter.outlineColor = Color.black;
		painter.fillColor = Color.white;
		painter.drawEllipse(scaleWithDpi(Point(2, 2)), scaleWithDpi(Point(buttonSize - 2, buttonSize - 2)));
		if(isChecked) {
			painter.outlineColor = Color.black;
			painter.fillColor = Color.black;
			// I'm using height so the checkbox is square
			auto size = scaleWithDpi(2);
			painter.drawEllipse(scaleWithDpi(Point(5, 5)), scaleWithDpi(Point(buttonSize - 5, buttonSize - 5)) + Point(size % 2, size % 2));
		}

		painter.outlineColor = cs.foregroundColor();
		painter.fillColor = cs.foregroundColor();

		painter.drawText(scaleWithDpi(Point(buttonSize + 4, 0)), label, Point(width, height), TextAlignment.Left | TextAlignment.VerticalCenter);
	}


	override void defaultEventHandler_triggered(Event ev) {
		isChecked = true;

		if(this.parent) {
			foreach(child; this.parent.children) {
				if(child is this) continue;
				if(auto rb = cast(Radiobox) child) {
					rb.isChecked = false;
					rb.emit!(ChangeEvent!bool)(&rb.isChecked);
					rb.redraw();
				}
			}
		}

		this.emit!(ChangeEvent!bool)(&this.isChecked);

		redraw();
	}

	/// Emits a change event with if it is checked. Note that when you select one in a group, that one will emit changed with value == true, and the previous one will emit changed with value == false right before. A button group may catch this and change the event.
	mixin Emits!(ChangeEvent!bool);
}


/++
	Creates a push button with unbounded size. When it is clicked, it emits a `triggered` event.


	Please note that the ampersand (&) character gets special treatment as described on this page https://docs.microsoft.com/en-us/windows/win32/menurc/common-control-parameters?redirectedfrom=MSDN

	Use double-ampersand, "First && Second", to be displayed as a single one, "First & Second".

	History:
		The ampersand behavior was always the case on Windows, but it wasn't until June 15, 2021 when Linux was changed to match it and the documentation updated to reflect it.
+/
class Button : MouseActivatedWidget {
	override int heightStretchiness() { return 3; }
	override int widthStretchiness() { return 3; }

	/++
		If true, this button will emit trigger events on double (and other quick events, if added) click events as well as on normal single click events.

		History:
			Added July 2, 2021
	+/
	public bool triggersOnMultiClick;

	private string label_;
	private TextAlignment alignment;
	private dchar accelerator;

	///
	string label() { return label_; }
	///
	void label(string l) {
		label_ = l;
		version(win32_widgets) {
			WCharzBuffer bfr = WCharzBuffer(l);
			SetWindowTextW(hwnd, bfr.ptr);
		} else version(custom_widgets) {
			redraw();
		}
	}

	override void defaultEventHandler_dblclick(DoubleClickEvent ev) {
		super.defaultEventHandler_dblclick(ev);
		if(triggersOnMultiClick) {
			if(ev.button == MouseButton.left) {
				auto event = new Event(EventType.triggered, this);
				event.sendDirectly();
			}
		}
	}

	private Sprite sprite;
	private int displayFlags;

	protected bool needsOwnerDraw() {
		return &this.paint !is &Button.paint || &this.useStyleProperties !is &Button.useStyleProperties || &this.paintContent !is &Button.paintContent;
	}

	version(win32_widgets)
	override int handleWmDrawItem(DRAWITEMSTRUCT* dis) {
		auto itemId = dis.itemID;
		auto hdc = dis.hDC;
		auto rect = dis.rcItem;
		switch(dis.itemAction) {
			// skipping setDynamicState because i don't want to queue the redraw unnecessarily
			case ODA_SELECT:
				dynamicState_ &= ~DynamicState.depressed;
				if(dis.itemState & ODS_SELECTED)
					dynamicState_ |= DynamicState.depressed;
			goto case;
			case ODA_FOCUS:
				dynamicState_ &= ~DynamicState.focus;
				if(dis.itemState & ODS_FOCUS)
					dynamicState_ |= DynamicState.focus;
			goto case;
			case ODA_DRAWENTIRE:
				auto painter = WidgetPainter(this.simpleWindowWrappingHwnd.draw(true), this);
				//painter.impl.hdc = hdc;
				paint(painter);
			break;
			default:
		}
		return 1;

	}

	/++
		Creates a push button with the given label, which may be an image or some text.

		Bugs:
			If the image is bigger than the button, it may not be displayed in the right position on Linux.

		History:
			The [ImageLabel] overload was added on June 21, 2021 (dub v10.1).

			The button with label and image will respect requests to show both on Windows as
			of March 28, 2022 iff you provide a manifest file to opt into common controls v6.
	+/
	this(string label, Widget parent) {
		this(ImageLabel(label), parent);
	}

	/// ditto
	this(ImageLabel label, Widget parent) {
		bool needsImage;
		version(win32_widgets) {
			super(parent);

			// BS_BITMAP is set when we want image only, so checking for exactly that combination
			enum imgFlags = ImageLabel.DisplayFlags.displayImage | ImageLabel.DisplayFlags.displayText;
			auto extraStyle = ((label.displayFlags & imgFlags) == ImageLabel.DisplayFlags.displayImage) ? BS_BITMAP : 0;

			// could also do a virtual method needsOwnerDraw which default returns true and we control it here. typeid(this) == typeid(Button) for override check.

			if(needsOwnerDraw) {
				extraStyle |= BS_OWNERDRAW;
				needsImage = true;
			}

			// the transparent thing can mess up borders in other cases, so only going to keep it for bitmap things where it might matter
			createWin32Window(this, "button"w, label.label, BS_PUSHBUTTON | extraStyle, extraStyle == BS_BITMAP ? WS_EX_TRANSPARENT : 0 );

			if(label.image) {
				sprite = Sprite.fromMemoryImage(parentWindow.win, label.image, true);

				SendMessageW(hwnd, BM_SETIMAGE, IMAGE_BITMAP, cast(LPARAM) sprite.nativeHandle);
			}

			this.label = label.label;
		} else version(custom_widgets) {
			super(parent);

			label.label.extractWindowsStyleLabel(this.label_, this.accelerator);
			needsImage = true;
		}


		if(needsImage && label.image) {
			this.sprite = Sprite.fromMemoryImage(parentWindow.win, label.image);
			this.displayFlags = label.displayFlags;
		}

		this.alignment = label.alignment;
	}

	override int minHeight() { return defaultLineHeight + 4; }

	static class Style : Widget.Style {
		override WidgetBackground background() {
			auto cs = widget.getComputedStyle(); // FIXME: this is potentially recursive

			auto pressed = DynamicState.depressed | DynamicState.hover;
			if((widget.dynamicState & pressed) == pressed) {
				return WidgetBackground(cs.depressedButtonColor());
			} else if(widget.dynamicState & DynamicState.hover) {
				return WidgetBackground(cs.hoveringColor());
			} else {
				return WidgetBackground(cs.buttonColor());
			}
		}

		override FrameStyle borderStyle() {
			auto pressed = DynamicState.depressed | DynamicState.hover;
			if((widget.dynamicState & pressed) == pressed) {
				return FrameStyle.sunk;
			} else {
				return FrameStyle.risen;
			}

		}

		override bool variesWithState(ulong dynamicStateFlags) {
			return super.variesWithState(dynamicStateFlags) || (dynamicStateFlags & (DynamicState.depressed | DynamicState.hover));
		}
	}
	mixin OverrideStyle!Style;

	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		if(sprite) {
			sprite.drawAt(
				painter,
				bounds.upperLeft + Point((bounds.width - sprite.width) / 2, (bounds.height - sprite.height) / 2),
				Point(0, 0)
			);
		} else {
			Point pos = bounds.upperLeft;
			if(this.height == 16)
				pos.y -= 2; // total hack omg
			painter.drawText(pos, label, bounds.lowerRight, alignment | TextAlignment.VerticalCenter);
		}
		return bounds;
	}

	override int flexBasisWidth() {
		version(win32_widgets) {
			SIZE size;
			SendMessage(hwnd, BCM_GETIDEALSIZE, 0, cast(LPARAM) &size);
			if(size.cx == 0)
				goto fallback;
			return size.cx + scaleWithDpi(16);
		}
		fallback:
			return scaleWithDpi(cast(int) label.length * 8 + 16);
	}

	override int flexBasisHeight() {
		version(win32_widgets) {
			SIZE size;
			SendMessage(hwnd, BCM_GETIDEALSIZE, 0, cast(LPARAM) &size);
			if(size.cy == 0)
				goto fallback;
			return size.cy + scaleWithDpi(6);
		}
		fallback:
			return defaultLineHeight + 4;
	}
}

/++
	A button with a custom appearance, even on systems where there is a standard button. You can subclass it to override its style, paint, or paintContent functions, or you can modify its members for common changes.

	History:
		Added January 14, 2024
+/
class CustomButton : Button {
	this(ImageLabel label, Widget parent) {
		super(label, parent);
	}

	this(string label, Widget parent) {
		super(label, parent);
	}

	version(win32_widgets)
	override protected void privatePaint(WidgetPainter painter, int lox, int loy, Rectangle containment, bool force, bool invalidate) {
		// paint is driven by handleWmDrawItem instead of minigui's redraw events
		if(hwnd)
			InvalidateRect(hwnd, null, false); // get Windows to trigger the actual redraw
		return;
	}

	override void paint(WidgetPainter painter) {
		// the parent does `if(hwnd) return;` because
		// normally we don't want to draw on standard controls,
		// but this is an exception if it is an owner drawn button
		// (which is determined in the constructor by testing,
		// at runtime, for the existence of an overridden paint
		// member anyway, so this needed to trigger BS_OWNERDRAW)
		// sdpyPrintDebugString("drawing");
		painter.drawThemed(&paintContent);
	}
}

/++
	A button with a consistent size, suitable for user commands like OK and CANCEL.
+/
class CommandButton : Button {
	this(string label, Widget parent) {
		super(label, parent);
	}

	// FIXME: I think I can simply make this 0 stretchiness instead of max now that the flex basis is there

	override int maxHeight() {
		return defaultLineHeight + 4;
	}

	override int maxWidth() {
		return defaultLineHeight * 4;
	}

	override int marginLeft() { return 12; }
	override int marginRight() { return 12; }
	override int marginTop() { return 12; }
	override int marginBottom() { return 12; }
}

///
enum ArrowDirection {
	left, ///
	right, ///
	up, ///
	down ///
}

///
version(custom_widgets)
class ArrowButton : Button {
	///
	this(ArrowDirection direction, Widget parent) {
		super("", parent);
		this.direction = direction;
		triggersOnMultiClick = true;
	}

	private ArrowDirection direction;

	override int minHeight() { return scaleWithDpi(16); }
	override int maxHeight() { return scaleWithDpi(16); }
	override int minWidth() { return scaleWithDpi(16); }
	override int maxWidth() { return scaleWithDpi(16); }

	override void paint(WidgetPainter painter) {
		super.paint(painter);

		auto cs = getComputedStyle();

		painter.outlineColor = cs.foregroundColor;
		painter.fillColor = cs.foregroundColor;

		auto offset = Point((this.width - scaleWithDpi(16)) / 2, (this.height - scaleWithDpi(16)) / 2);

		final switch(direction) {
			case ArrowDirection.up:
				painter.drawPolygon(
					scaleWithDpi(Point(2, 10) + offset),
					scaleWithDpi(Point(7, 5) + offset),
					scaleWithDpi(Point(12, 10) + offset),
					scaleWithDpi(Point(2, 10) + offset)
				);
			break;
			case ArrowDirection.down:
				painter.drawPolygon(
					scaleWithDpi(Point(2, 6) + offset),
					scaleWithDpi(Point(7, 11) + offset),
					scaleWithDpi(Point(12, 6) + offset),
					scaleWithDpi(Point(2, 6) + offset)
				);
			break;
			case ArrowDirection.left:
				painter.drawPolygon(
					scaleWithDpi(Point(10, 2) + offset),
					scaleWithDpi(Point(5, 7) + offset),
					scaleWithDpi(Point(10, 12) + offset),
					scaleWithDpi(Point(10, 2) + offset)
				);
			break;
			case ArrowDirection.right:
				painter.drawPolygon(
					scaleWithDpi(Point(6, 2) + offset),
					scaleWithDpi(Point(11, 7) + offset),
					scaleWithDpi(Point(6, 12) + offset),
					scaleWithDpi(Point(6, 2) + offset)
				);
			break;
		}
	}
}

private
int[2] getChildPositionRelativeToParentOrigin(Widget c) nothrow {
	int x, y;
	Widget par = c;
	while(par) {
		x += par.x;
		y += par.y;
		par = par.parent;
	}
	return [x, y];
}

version(win32_widgets)
private
int[2] getChildPositionRelativeToParentHwnd(Widget c) nothrow {
// MapWindowPoints?
	int x, y;
	Widget par = c;
	while(par) {
		x += par.x;
		y += par.y;
		par = par.parent;
		if(par !is null && par.useNativeDrawing())
			break;
	}
	return [x, y];
}

///
class ImageBox : Widget {
	private MemoryImage image_;

	override int widthStretchiness() { return 1; }
	override int heightStretchiness() { return 1; }
	override int widthShrinkiness() { return 1; }
	override int heightShrinkiness() { return 1; }

	override int flexBasisHeight() {
		return image_.height;
	}

	override int flexBasisWidth() {
		return image_.width;
	}

	///
	public void setImage(MemoryImage image){
		this.image_ = image;
		if(this.parentWindow && this.parentWindow.win) {
			if(sprite)
				sprite.dispose();
			sprite = new Sprite(this.parentWindow.win, Image.fromMemoryImage(image_, true));
		}
		redraw();
	}

	/// How to fit the image in the box if they aren't an exact match in size?
	enum HowToFit {
		center, /// centers the image, cropping around all the edges as needed
		crop, /// always draws the image in the upper left, cropping the lower right if needed
		// stretch, /// not implemented
	}

	private Sprite sprite;
	private HowToFit howToFit_;

	private Color backgroundColor_;

	///
	this(MemoryImage image, HowToFit howToFit, Color backgroundColor, Widget parent) {
		this.image_ = image;
		this.tabStop = false;
		this.howToFit_ = howToFit;
		this.backgroundColor_ = backgroundColor;
		super(parent);
		updateSprite();
	}

	/// ditto
	this(MemoryImage image, HowToFit howToFit, Widget parent) {
		this(image, howToFit, Color.transparent, parent);
	}

	private void updateSprite() {
		if(sprite is null && this.parentWindow && this.parentWindow.win) {
			sprite = new Sprite(this.parentWindow.win, Image.fromMemoryImage(image_, true));
		}
	}

	override void paint(WidgetPainter painter) {
		updateSprite();
		if(backgroundColor_.a) {
			painter.fillColor = backgroundColor_;
			painter.drawRectangle(Point(0, 0), width, height);
		}
		if(howToFit_ == HowToFit.crop)
			sprite.drawAt(painter, Point(0, 0));
		else if(howToFit_ == HowToFit.center) {
			sprite.drawAt(painter, Point((width - image_.width) / 2, (height - image_.height) / 2));
		}
	}
}

///
class TextLabel : Widget {
	override int minHeight() { return borderBoxForContentBox(Rectangle(Point(0, 0), Size(0, defaultTextHeight()))).height; }
	override int maxHeight() { return minHeight; }
	override int minWidth() { return 32; }

	override int flexBasisHeight() { return minHeight(); }
	override int flexBasisWidth() { return defaultTextWidth(label); }

	string label_;

	/++
		Indicates which other control this label is here for. Similar to HTML `for` attribute.

		In practice this means a click on the label will focus the `labelFor`. In future versions
		it will also set screen reader hints but that is not yet implemented.

		History:
			Added October 3, 2021 (dub v10.4)
	+/
	Widget labelFor;

	///
	@scriptable
	string label() { return label_; }

	///
	@scriptable
	void label(string l) {
		label_ = l;
		version(win32_widgets) {
			WCharzBuffer bfr = WCharzBuffer(l);
			SetWindowTextW(hwnd, bfr.ptr);
		} else version(custom_widgets)
			redraw();
	}

	override void defaultEventHandler_click(scope ClickEvent ce) {
		if(this.labelFor !is null)
			this.labelFor.focus();
	}

	/++
		WARNING: this currently sets TextAlignment.Right as the default. That will change in a future version.
		For future-proofing of your code, if you rely on TextAlignment.Right, you MUST specify that explicitly.
	+/
	this(string label, TextAlignment alignment, Widget parent) {
		this.label_ = label;
		this.alignment = alignment;
		this.tabStop = false;
		super(parent);

		version(win32_widgets)
		createWin32Window(this, "static"w, label, (alignment & TextAlignment.Center) ? SS_CENTER : 0, (alignment & TextAlignment.Right) ? WS_EX_RIGHT : WS_EX_LEFT);
	}

	/// ditto
	this(string label, Widget parent) {
		this(label, TextAlignment.Right, parent);
	}

	TextAlignment alignment;

	version(custom_widgets)
	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		painter.outlineColor = getComputedStyle().foregroundColor;
		painter.drawText(bounds.upperLeft, this.label, bounds.lowerRight, alignment);
		return bounds;
	}
}

class TextDisplayHelper : Widget {
	protected TextLayouter l;
	protected ScrollMessageWidget smw;

	private const(TextLayouter.State)*[] undoStack;
	private const(TextLayouter.State)*[] redoStack;

	private string preservedPrimaryText;
	protected void selectionChanged() {
		// sdpyPrintDebugString("selectionChanged"); try throw new Exception("e"); catch(Exception e) sdpyPrintDebugString(e.toString());
		static if(UsingSimpledisplayX11)
		with(l.selection()) {
			if(!isEmpty()) {
				//sdpyPrintDebugString("!isEmpty");

				getPrimarySelection(parentWindow.win, (in char[] txt) {
					// sdpyPrintDebugString("getPrimarySelection: " ~ getContentString() ~ " (old " ~ txt ~ ")");
					// import std.stdio; writeln("txt: ", txt, " sel: ", getContentString);
					if(txt.length) {
						preservedPrimaryText = txt.idup;
						// writeln(preservedPrimaryText);
					}

					setPrimarySelection(parentWindow.win, getContentString());
				});
			}
		}
	}

	final TextLayouter layouter() {
		return l;
	}

	bool readonly;
	bool caretNavigation; // scroll lock can flip this
	bool singleLine;
	bool acceptsTabInput;

	private Menu ctx;
	override Menu contextMenu(int x, int y) {
		if(ctx is null) {
			ctx = new Menu("Actions", this);
			if(!readonly) {
				ctx.addItem(new MenuItem(new Action("&Undo", GenericIcons.Undo, &undo)));
				ctx.addItem(new MenuItem(new Action("&Redo", GenericIcons.Redo, &redo)));
				ctx.addSeparator();
			}
			if(!readonly)
				ctx.addItem(new MenuItem(new Action("Cu&t", GenericIcons.Cut, &cut)));
			ctx.addItem(new MenuItem(new Action("&Copy", GenericIcons.Copy, &copy)));
			if(!readonly)
				ctx.addItem(new MenuItem(new Action("&Paste", GenericIcons.Paste, &paste)));
			if(!readonly)
				ctx.addItem(new MenuItem(new Action("&Delete", 0, &deleteContentOfSelection)));
			ctx.addSeparator();
			ctx.addItem(new MenuItem(new Action("Select &All", 0, &selectAll)));
		}
		return ctx;
	}

	override void defaultEventHandler_blur(BlurEvent ev) {
		super.defaultEventHandler_blur(ev);
		if(l.wasMutated()) {
			auto evt = new ChangeEvent!string(this, &this.content);
			evt.dispatch();
			l.clearWasMutatedFlag();
		}
	}

	private string content() {
		return l.getTextString();
	}

	void undo() {
		if(readonly) return;
		if(undoStack.length) {
			auto state = undoStack[$-1];
			undoStack = undoStack[0 .. $-1];
			undoStack.assumeSafeAppend();
			redoStack ~= l.saveState();
			l.restoreState(state);
			adjustScrollbarSizes();
			scrollForCaret();
			redraw();
			stateCheckpoint = true;
		}
	}

	void redo() {
		if(readonly) return;
		if(redoStack.length) {
			doStateCheckpoint();
			auto state = redoStack[$-1];
			redoStack = redoStack[0 .. $-1];
			redoStack.assumeSafeAppend();
			l.restoreState(state);
			adjustScrollbarSizes();
			scrollForCaret();
			redraw();
			stateCheckpoint = true;
		}
	}

	void cut() {
		if(readonly) return;
		with(l.selection()) {
			if(!isEmpty()) {
				setClipboardText(parentWindow.win, getContentString());
				doStateCheckpoint();
				replaceContent("");
				adjustScrollbarSizes();
				scrollForCaret();
				this.redraw();
			}
		}

	}

	void copy() {
		with(l.selection()) {
			if(!isEmpty()) {
				setClipboardText(parentWindow.win, getContentString());
				this.redraw();
			}
		}
	}

	void paste() {
		if(readonly) return;
		getClipboardText(parentWindow.win, (txt) {
			doStateCheckpoint();
			if(singleLine)
				l.selection.replaceContent(txt.stripInternal());
			else
				l.selection.replaceContent(txt);
			adjustScrollbarSizes();
			scrollForCaret();
			this.redraw();
		});
	}

	void deleteContentOfSelection() {
		if(readonly) return;
		doStateCheckpoint();
		l.selection.replaceContent("");
		l.selection.setUserXCoordinate();
		adjustScrollbarSizes();
		scrollForCaret();
		redraw();
	}

	void selectAll() {
		with(l.selection) {
			moveToStartOfDocument();
			setAnchor();
			moveToEndOfDocument();
			setFocus();

			selectionChanged();
		}
		redraw();
	}

	protected bool stateCheckpoint = true;

	protected void doStateCheckpoint() {
		if(stateCheckpoint) {
			undoStack ~= l.saveState();
			stateCheckpoint = false;
		}
	}

	protected void adjustScrollbarSizes() {
		// FIXME: will want a content area helper function instead of doing all these subtractions myself
		auto borderWidth = 2;
		this.smw.setTotalArea(l.width, l.height);
		this.smw.setViewableArea(
			this.width - this.paddingLeft - this.paddingRight - borderWidth * 2,
			this.height - this.paddingTop - this.paddingBottom - borderWidth * 2);
	}

	protected void scrollForCaret() {
		// writeln(l.width, "x", l.height); writeln(this.width - this.paddingLeft - this.paddingRight, " ", this.height - this.paddingTop - this.paddingBottom);
		smw.scrollIntoView(l.selection.focusBoundingBox());
	}

	// FIXME: this should be a theme changed event listener instead
	private BaseVisualTheme currentTheme;
	override void recomputeChildLayout() {
		if(currentTheme is null)
			currentTheme = WidgetPainter.visualTheme;
		if(WidgetPainter.visualTheme !is currentTheme) {
			currentTheme = WidgetPainter.visualTheme;
			auto ds = this.l.defaultStyle;
			if(auto ms = cast(MyTextStyle) ds) {
				auto cs = getComputedStyle();
				auto font = cs.font();
				if(font !is null)
					ms.font_ = font;
				else {
					auto osc = new OperatingSystemFont();
					osc.loadDefault;
					ms.font_ = osc;
				}
			}
		}
		super.recomputeChildLayout();
	}

	private Point adjustForSingleLine(Point p) {
		if(singleLine)
			return Point(p.x, this.height / 2);
		else
			return p;
	}

	private bool wordWrapEnabled_;

	this(TextLayouter l, ScrollMessageWidget parent) {
		this.smw = parent;

		smw.addDefaultWheelListeners(16, 16, 8);
		smw.movementPerButtonClick(16, 16);

		this.defaultPadding = Rectangle(2, 2, 2, 2);

		this.l = l;
		super(parent);

		smw.addEventListener((scope ScrollEvent se) {
			this.redraw();
		});

		this.addEventListener((scope ResizeEvent re) {
			// FIXME: I should add a method to give this client area width thing
			if(wordWrapEnabled_)
				this.l.wordWrapWidth = this.width - this.paddingLeft - this.paddingRight;

			adjustScrollbarSizes();
			scrollForCaret();

			this.redraw();
		});

	}

	private {
		bool mouseDown;
		bool mouseActuallyMoved;

		Point downAt;

		Timer autoscrollTimer;
		int autoscrollDirection;
		int autoscrollAmount;

		void autoscroll() {
			switch(autoscrollDirection) {
				case 0: smw.scrollUp(autoscrollAmount); break;
				case 1: smw.scrollDown(autoscrollAmount); break;
				case 2: smw.scrollLeft(autoscrollAmount); break;
				case 3: smw.scrollRight(autoscrollAmount); break;
				default: assert(0);
			}

			this.redraw();
		}

		void setAutoscrollTimer(int direction, int amount) {
			if(autoscrollTimer is null) {
				autoscrollTimer = new Timer(1000 / 60, &autoscroll);
			}

			autoscrollDirection = direction;
			autoscrollAmount = amount;
		}

		void stopAutoscrollTimer() {
			if(autoscrollTimer !is null) {
				autoscrollTimer.dispose();
				autoscrollTimer = null;
			}
			autoscrollAmount = 0;
			autoscrollDirection = 0;
		}
	}

	override void defaultEventHandler_mousemove(scope MouseMoveEvent ce) {
		if(mouseDown) {
			auto movedTo = Point(ce.clientX - this.paddingLeft, ce.clientY - this.paddingTop);

			// FIXME: when scrolling i actually do want a timer.
			// i also want a zone near the sides of the window where i can auto scroll

			auto scrollMultiplier = scaleWithDpi(16);
			auto scrollDivisor = scaleWithDpi(16); // if you go more than 64px up it will scroll faster

			if(!singleLine && movedTo.y < 4) {
				setAutoscrollTimer(0, scrollMultiplier * -(movedTo.y-4) / scrollDivisor);
			} else
			if(!singleLine && (movedTo.y + 6) > this.height) {
				setAutoscrollTimer(1, scrollMultiplier * (movedTo.y + 6 - this.height) / scrollDivisor);
			} else
			if(movedTo.x < 4) {
				setAutoscrollTimer(2, scrollMultiplier * -(movedTo.x-4) / scrollDivisor);
			} else
			if((movedTo.x + 6) > this.width) {
				setAutoscrollTimer(3, scrollMultiplier * (movedTo.x + 6 - this.width) / scrollDivisor);
			} else
				stopAutoscrollTimer();

			l.selection.moveTo(adjustForSingleLine(smw.position + movedTo));
			l.selection.setFocus();
			mouseActuallyMoved = true;
			this.redraw();
		}

		super.defaultEventHandler_mousemove(ce);
	}

	override void defaultEventHandler_mouseup(scope MouseUpEvent ce) {
		// FIXME: assert primary selection
		if(mouseDown && ce.button == MouseButton.left) {
			stateCheckpoint = true;
			//l.selection.moveTo(adjustForSingleLine(smw.position + Point(ce.clientX - this.paddingLeft, ce.clientY - this.paddingTop)));
			//l.selection.setFocus();
			mouseDown = false;
			parentWindow.releaseMouseCapture();
			stopAutoscrollTimer();
			this.redraw();

			if(mouseActuallyMoved)
				selectionChanged();
		}
		//writeln(ce.clientX, ", ", ce.clientY, " = ", l.offsetOfClick(Point(ce.clientX, ce.clientY)));

		super.defaultEventHandler_mouseup(ce);
	}

	static if(UsingSimpledisplayX11)
	override void defaultEventHandler_click(scope ClickEvent ce) {
		if(ce.button == MouseButton.middle) {
			parentWindow.win.getPrimarySelection((txt) {
				doStateCheckpoint();

				// import arsd.core; writeln(txt);writeln(l.selection.getContentString);writeln(preservedPrimaryText);

				if(txt == l.selection.getContentString && preservedPrimaryText.length)
					l.selection.replaceContent(preservedPrimaryText);
				else
					l.selection.replaceContent(txt);
				redraw();
			});
		}

		super.defaultEventHandler_click(ce);
	}

	override void defaultEventHandler_dblclick(scope DoubleClickEvent dce) {
		if(dce.button == MouseButton.left) {
			with(l.selection()) {
				// FIXME: for a url or file picker i might wanna use / as a separator intead
				scope dg = delegate const(char)[] (scope return const(char)[] ch) {
					if(ch == " " || ch == "\t" || ch == "\n" || ch == "\r")
						return ch;
					return null;
				};
				find(dg, 1, true).moveToEnd.setAnchor;
				find(dg, 1, false).moveTo.setFocus;
				selectionChanged();
				redraw();
			}
		}

		super.defaultEventHandler_dblclick(dce);
	}

	override void defaultEventHandler_mousedown(scope MouseDownEvent ce) {
		if(ce.button == MouseButton.left) {
			downAt = Point(ce.clientX - this.paddingLeft, ce.clientY - this.paddingTop);
			l.selection.moveTo(adjustForSingleLine(smw.position + downAt));
			if(ce.shiftKey)
				l.selection.setFocus();
			else
				l.selection.setAnchor();
			mouseDown = true;
			mouseActuallyMoved = false;
			parentWindow.captureMouse(this);
			this.redraw();
		}
		//writeln(ce.clientX, ", ", ce.clientY, " = ", l.offsetOfClick(Point(ce.clientX, ce.clientY)));

		super.defaultEventHandler_mousedown(ce);
	}

	override void defaultEventHandler_char(scope CharEvent ce) {
		super.defaultEventHandler_char(ce);

		if(readonly)
			return;
		if(ce.character < 32 && ce.character != '\t' && ce.character != '\n' && ce.character != '\b')
			return; // skip the ctrl+x characters we don't care about as plain text

		if(singleLine && ce.character == '\n')
			return;
		if(!acceptsTabInput && ce.character == '\t')
			return;

		doStateCheckpoint();

		char[4] buffer;
		import arsd.core;
		auto stride = encodeUtf8(buffer, ce.character);
		l.selection.replaceContent(buffer[0 .. stride]);
		l.selection.setUserXCoordinate();
		adjustScrollbarSizes();
		scrollForCaret();
		redraw();

	}

	override void defaultEventHandler_keydown(scope KeyDownEvent kde) {
		switch(kde.key) {
			case Key.Up, Key.Down, Key.Left, Key.Right:
			case Key.Home, Key.End:
				stateCheckpoint = true;
				bool setPosition = false;
				switch(kde.key) {
					case Key.Up: l.selection.moveUp(); break;
					case Key.Down: l.selection.moveDown(); break;
					case Key.Left: l.selection.moveLeft(); setPosition = true; break;
					case Key.Right: l.selection.moveRight(); setPosition = true; break;
					case Key.Home: l.selection.moveToStartOfLine(); setPosition = true; break;
					case Key.End: l.selection.moveToEndOfLine(); setPosition = true; break;
					default: assert(0);
				}

				if(kde.shiftKey)
					l.selection.setFocus();
				else
					l.selection.setAnchor();

				selectionChanged();

				if(setPosition)
					l.selection.setUserXCoordinate();
				scrollForCaret();
				redraw();
			break;
			case Key.PageUp, Key.PageDown:
				// want to act like the user clicked on the caret again
				// after the scroll operation completed, so it would remain at
				// about the same place on the viewport
				auto oldY = smw.vsb.position;
				smw.defaultKeyboardListener(kde);
				auto newY = smw.vsb.position;
				with(l.selection) {
					auto uc = getUserCoordinate();
					uc.y += newY - oldY;
					moveTo(uc);

					if(kde.shiftKey)
						setFocus();
					else
						setAnchor();
				}
			break;
			case Key.Delete:
				if(l.selection.isEmpty()) {
					l.selection.setAnchor();
					l.selection.moveRight();
					l.selection.setFocus();
				}
				deleteContentOfSelection();
				adjustScrollbarSizes();
				scrollForCaret();
			break;
			case Key.Insert:
			break;
			case Key.A:
				if(kde.ctrlKey)
					selectAll();
			break;
			case Key.F:
				// find
			break;
			case Key.Z:
				if(kde.ctrlKey)
					undo();
			break;
			case Key.R:
				if(kde.ctrlKey)
					redo();
			break;
			case Key.X:
				if(kde.ctrlKey)
					cut();
			break;
			case Key.C:
				if(kde.ctrlKey)
					copy();
			break;
			case Key.V:
				if(kde.ctrlKey)
					paste();
			break;
			case Key.F1:
				with(l.selection()) {
					moveToStartOfLine();
					setAnchor();
					moveToEndOfLine();
					moveToIncludeAdjacentEndOfLineMarker();
					setFocus();
					replaceContent("");
				}

				redraw();
			break;
			/*
			case Key.F2:
				l.selection().changeStyle((old) => l.registerStyle(new MyTextStyle(
					//(cast(MyTextStyle) old).font,
					font2,
					Color.red)));
				redraw();
			break;
			*/
			case Key.Tab:
				// we process the char event, so don't want to change focus on it, unless the user overrides that with ctrl
				if(acceptsTabInput && !kde.ctrlKey)
					kde.preventDefault();
			break;
			default:
		}

		if(!kde.defaultPrevented)
			super.defaultEventHandler_keydown(kde);
	}

	// we want to delegate all the Widget.Style stuff up to the other class that the user can see
	override void useStyleProperties(scope void delegate(scope .Widget.Style props) dg) {
		// this should be the upper container - first parent is a ScrollMessageWidget content area container, then ScrollMessageWidget itself, next parent is finally the EditableTextWidget Parent
		if(parent && parent.parent && parent.parent.parent)
			parent.parent.parent.useStyleProperties(dg);
		else
			super.useStyleProperties(dg);
	}

	override int minHeight() { return borderBoxForContentBox(Rectangle(Point(0, 0), Size(0, defaultTextHeight))).height; }
	override int maxHeight() {
		if(singleLine)
			return minHeight;
		else
			return super.maxHeight();
	}

	void drawTextSegment(MyTextStyle myStyle, WidgetPainter painter, Point upperLeft, scope const(char)[] text) {
		painter.setFont(myStyle.font);
		painter.drawText(upperLeft, text);
	}

	override Rectangle paintContent(WidgetPainter painter, const Rectangle bounds) {
		//painter.setFont(font);

		auto cs = getComputedStyle();
		auto defaultColor = cs.foregroundColor;

		auto old = painter.setClipRectangleForWidget(bounds.upperLeft, bounds.width, bounds.height);
		scope(exit) painter.setClipRectangleForWidget(old.upperLeft, old.width, old.height);

		l.getDrawableText(delegate bool(txt, style, info, carets...) {
			//writeln("Segment: ", txt);
			assert(style !is null);

			if(info.selections && info.boundingBox.width > 0) {
				auto color = this.isFocused ? cs.selectionBackgroundColor : Color(128, 128, 128); // FIXME don't hardcode
				painter.fillColor = color;
				painter.outlineColor = color;
				painter.drawRectangle(Rectangle(info.boundingBox.upperLeft - smw.position() + bounds.upperLeft, info.boundingBox.size));
				painter.outlineColor = cs.selectionForegroundColor;
				//painter.fillColor = Color.white;
			} else {
				painter.outlineColor = defaultColor;
			}

			if(this.isFocused)
			foreach(idx, caret; carets) {
				if(idx == 0)
					painter.notifyCursorPosition(caret.boundingBox.left - smw.position.x + bounds.left, caret.boundingBox.top - smw.position.y + bounds.top, caret.boundingBox.width, caret.boundingBox.height);
				painter.drawLine(
					caret.boundingBox.upperLeft + bounds.upperLeft - smw.position(),
					bounds.upperLeft + Point(caret.boundingBox.left, caret.boundingBox.bottom) - smw.position()
				);
			}

			if(txt.stripInternal.length) {
				// defaultColor = myStyle.color; // FIXME: so wrong
				if(auto myStyle = cast(MyTextStyle) style)
					drawTextSegment(myStyle, painter, info.boundingBox.upperLeft - smw.position() + bounds.upperLeft, txt.stripRightInternal);
				else if(auto myStyle = cast(MyImageStyle) style)
					myStyle.draw(painter, info.boundingBox.upperLeft - smw.position() + bounds.upperLeft, txt.stripRightInternal);
			}

			if(info.boundingBox.upperLeft.y - smw.position().y > this.height) {
				return false;
			} else {
				return true;
			}
		}, Rectangle(smw.position(), bounds.size));

		/+
		int place = 0;
		int y = 75;
		foreach(width; widths) {
			painter.fillColor = Color.red;
			painter.drawRectangle(Point(place, y), Size(width, 75));
			//y += 15;
			place += width;
		}
		+/

		return bounds;
	}

	static class MyTextStyle : TextStyle {
		OperatingSystemFont font_;
		this(OperatingSystemFont font, bool passwordMode = false) {
			this.font_ = font;
		}

		override OperatingSystemFont font() {
			return font_;
		}

		bool foregroundColorOverridden;
		bool backgroundColorOverridden;
		Color foregroundColor;
		Color backgroundColor; // should this be inline segment or the whole paragraph block?
		bool italic;
		bool bold;
		bool underline;
		bool strikeout;
		bool subscript;
		bool superscript;
	}

	static class MyImageStyle : TextStyle, MeasurableFont {
		MemoryImage image_;
		Image converted;
		this(MemoryImage image) {
			this.image_ =  image;
			this.converted = Image.fromMemoryImage(image);
		}

		bool isMonospace() { return false; }
		int averageWidth() { return image_.width; }
		int height() { return image_.height; }
		int ascent() { return image_.height; }
		int descent() { return 0; }

		int stringWidth(scope const(char)[] s, SimpleWindow window = null) {
			return image_.width;
		}

		override MeasurableFont font() {
			return this;
		}

		void draw(WidgetPainter painter, Point upperLeft, scope const(char)[] text) {
			painter.drawImage(upperLeft, converted);
		}
	}
}

/+
class TextWidget : Widget {
	TextLayouter l;
	ScrollMessageWidget smw;
	TextDisplayHelper helper;
	this(TextLayouter l, Widget parent) {
		this.l = l;
		super(parent);

		smw = new ScrollMessageWidget(this);
		//smw.horizontalScrollBar.hide;
		//smw.verticalScrollBar.hide;
		smw.addDefaultWheelListeners(16, 16, 8);
		smw.movementPerButtonClick(16, 16);
		helper = new TextDisplayHelper(l, smw);

		// no need to do this here since there's gonna be a resize
		// event immediately before any drawing
		// smw.setTotalArea(l.width, l.height);
		smw.setViewableArea(
			this.width - this.paddingLeft - this.paddingRight,
			this.height - this.paddingTop - this.paddingBottom);

		/+
		writeln(l.width, "x", l.height);
		+/
	}
}
+/




/+
	make sure it calls parentWindow.inputProxy.setIMEPopupLocation too
+/

/++
	Contains the implementation of text editing and shared basic api. You should construct one of the child classes instead, like [TextEdit], [LineEdit], or [PasswordEdit].
+/
abstract class EditableTextWidget : Widget {
	protected this(Widget parent) {
		version(custom_widgets)
			this(true, parent);
		else
			this(false, parent);
	}

	private bool useCustomWidget;

	protected this(bool useCustomWidget, Widget parent) {
		this.useCustomWidget = useCustomWidget;

		super(parent);

		if(useCustomWidget)
			setupCustomTextEditing();
	}

	private bool wordWrapEnabled_;
	/++
		Enables or disables wrapping of long lines on word boundaries.
	+/
	void wordWrapEnabled(bool enabled) {
		if(useCustomWidget) {
			wordWrapEnabled_ = enabled;
			if(tdh)
				tdh.wordWrapEnabled_ = true;
			textLayout.wordWrapWidth = enabled ? this.width : 0; // FIXME
		} else version(win32_widgets) {
			SendMessageW(hwnd, EM_FMTLINES, enabled ? 1 : 0, 0);
		}
	}

	override int minWidth() { return scaleWithDpi(16); }
	override int widthStretchiness() { return 7; }
	override int widthShrinkiness() { return 1; }

	override int maxHeight() {
		if(useCustomWidget)
			return tdh.maxHeight;
		else
			return super.maxHeight();
	}

	override void focus() {
		if(useCustomWidget && tdh)
			tdh.focus();
		else
			super.focus();
	}

	override void defaultEventHandler_focusout(FocusOutEvent foe) {
		if(tdh !is null && foe.target is tdh)
			tdh.redraw();
	}

	override void defaultEventHandler_focusin(FocusInEvent foe) {
		if(tdh !is null && foe.target is tdh)
			tdh.redraw();
	}


	/++
		Selects all the text in the control, as if the user did it themselves. When the user types in a widget, the selected text is replaced with the new input, so this might be useful for putting in default text that is easy for the user to replace.
	+/
	void selectAll() {
		if(useCustomWidget) {
			tdh.selectAll();
		} else version(win32_widgets) {
			SendMessage(hwnd, EM_SETSEL, 0, -1);
		}
	}

	/++
		Basic clipboard operations.

		History:
			Added December 31, 2024
	+/
	void copy() {
		if(useCustomWidget) {
			tdh.copy();
		} else version(win32_widgets) {
			SendMessage(hwnd, WM_COPY, 0, 0);
		}
	}

	/// ditto
	void cut() {
		if(useCustomWidget) {
			tdh.cut();
		} else version(win32_widgets) {
			SendMessage(hwnd, WM_CUT, 0, 0);
		}
	}

	/// ditto
	void paste() {
		if(useCustomWidget) {
			tdh.paste();
		} else version(win32_widgets) {
			SendMessage(hwnd, WM_PASTE, 0, 0);
		}
	}

	///
	void undo() {
		if(useCustomWidget) {
			tdh.undo();
		} else version(win32_widgets) {
			SendMessage(hwnd, EM_UNDO, 0, 0);
		}
	}

	// note that WM_CLEAR deletes the selection without copying it to the clipboard
	// also windows supports margins, modified flag, and much more

	// EM_UNDO and EM_CANUNDO. EM_REDO is only supported in rich text boxes here

	// EM_GETSEL, EM_REPLACESEL, and EM_SETSEL might be usable for find etc.



	/*protected*/ TextDisplayHelper tdh;
	/*protected*/ TextLayouter textLayout;

	/++
		Gets or sets the current content of the control, as a plain text string. Setting the content will reset the cursor position and overwrite any changes the user made.
	+/
	@property string content() {
		if(useCustomWidget) {
			return textLayout.getTextString();
		} else version(win32_widgets) {
			wchar[4096] bufferstack;
			wchar[] buffer;
			auto len = GetWindowTextLength(hwnd);
			if(len < bufferstack.length)
				buffer = bufferstack[0 .. len + 1];
			else
				buffer = new wchar[](len + 1);

			auto l = GetWindowTextW(hwnd, buffer.ptr, cast(int) buffer.length);
			if(l >= 0)
				return makeUtf8StringFromWindowsString(buffer[0 .. l]);
			else
				return null;
		}

		assert(0);
	}
	/// ditto
	@property void content(string s) {
		if(useCustomWidget) {
			with(textLayout.selection) {
				moveToStartOfDocument();
				setAnchor();
				moveToEndOfDocument();
				setFocus();
				replaceContent(s);
			}

			tdh.adjustScrollbarSizes();
			// these don't seem to help
			// tdh.smw.setPosition(0, 0);
			// tdh.scrollForCaret();

			redraw();
		} else version(win32_widgets) {
			WCharzBuffer bfr = WCharzBuffer(s, WindowsStringConversionFlags.convertNewLines);
			SetWindowTextW(hwnd, bfr.ptr);
		}
	}

	/++
		Appends some text to the widget at the end, without affecting the user selection or cursor position.
	+/
	void addText(string txt) {
		if(useCustomWidget) {
			textLayout.appendText(txt);
			tdh.adjustScrollbarSizes();
			redraw();
		} else version(win32_widgets) {
			// get the current selection
			DWORD StartPos, EndPos;
			SendMessageW( hwnd, EM_GETSEL, cast(WPARAM)(&StartPos), cast(LPARAM)(&EndPos) );

			// move the caret to the end of the text
			int outLength = GetWindowTextLengthW(hwnd);
			SendMessageW( hwnd, EM_SETSEL, outLength, outLength );

			// insert the text at the new caret position
			WCharzBuffer bfr = WCharzBuffer(txt, WindowsStringConversionFlags.convertNewLines);
			SendMessageW( hwnd, EM_REPLACESEL, TRUE, cast(LPARAM) bfr.ptr );

			// restore the previous selection
			SendMessageW( hwnd, EM_SETSEL, StartPos, EndPos );
		}
	}

	// EM_SCROLLCARET scrolls the caret into view

	void scrollToBottom() {
		if(useCustomWidget) {
			tdh.smw.scrollDown(int.max);
		} else version(win32_widgets) {
			SendMessageW( hwnd, EM_LINESCROLL, 0, int.max );
		}
	}

	protected TextDisplayHelper textDisplayHelperFactory(TextLayouter textLayout, ScrollMessageWidget smw) {
		return new TextDisplayHelper(textLayout, smw);
	}

	protected TextStyle defaultTextStyle() {
		return new TextDisplayHelper.MyTextStyle(getUsedFont());
	}

	private OperatingSystemFont getUsedFont() {
		auto cs = getComputedStyle();
		auto font = cs.font;
		if(font is null) {
			font = new OperatingSystemFont;
			font.loadDefault();
		}
		return font;
	}

	protected void setupCustomTextEditing() {
		textLayout = new TextLayouter(defaultTextStyle());

		auto smw = new ScrollMessageWidget(this);
		if(!showingHorizontalScroll)
			smw.horizontalScrollBar.hide();
		if(!showingVerticalScroll)
			smw.verticalScrollBar.hide();
		this.tabStop = false;
		smw.tabStop = false;
		tdh = textDisplayHelperFactory(textLayout, smw);
	}

	override void newParentWindow(Window old, Window n) {
		if(n is null) return;
		this.parentWindow.addEventListener((scope DpiChangedEvent dce) {
			if(textLayout) {
				if(auto style = cast(TextDisplayHelper.MyTextStyle) textLayout.defaultStyle()) {
					// the dpi change can change the font, so this informs the layouter that it has changed too
					style.font_ = getUsedFont();

					// arsd.core.writeln(this.parentWindow.win.actualDpi);
				}
			}
		});
	}

	static class Style : Widget.Style {
		override WidgetBackground background() {
			return WidgetBackground(WidgetPainter.visualTheme.widgetBackgroundColor);
		}

		override Color foregroundColor() {
			return WidgetPainter.visualTheme.foregroundColor;
		}

		override FrameStyle borderStyle() {
			return FrameStyle.sunk;
		}

		override MouseCursor cursor() {
			return GenericCursor.Text;
		}
	}
	mixin OverrideStyle!Style;

	version(win32_widgets) {
		private string lastContentBlur;

		override void defaultEventHandler_blur(BlurEvent ev) {
			super.defaultEventHandler_blur(ev);

			if(!useCustomWidget)
			if(this.content != lastContentBlur) {
				auto evt = new ChangeEvent!string(this, &this.content);
				evt.dispatch();
				lastContentBlur = this.content;
			}
		}
	}


	bool showingVerticalScroll() { return true; }
	bool showingHorizontalScroll() { return true; }
}

/++
	A `LineEdit` is an editor of a single line of text, comparable to a HTML `<input type="text" />`.

	A `CustomLineEdit` always uses the custom implementation, even on operating systems where the native control is implemented in minigui, which may provide more api styling features but at the cost of poorer integration with the OS and potentially worse user experience in other ways.

	See_Also:
		[PasswordEdit] for a `LineEdit` that obscures its input.

		[TextEdit] for a multi-line plain text editor widget.

		[TextLabel] for a single line piece of static text.

		[TextDisplay] for a read-only display of a larger piece of plain text.
+/
class LineEdit : EditableTextWidget {
	override bool showingVerticalScroll() { return false; }
	override bool showingHorizontalScroll() { return false; }

	override int flexBasisWidth() { return 250; }
	override int widthShrinkiness() { return 10; }

	///
	this(Widget parent) {
		super(parent);
		version(win32_widgets) {
			createWin32Window(this, "edit"w, "",
				0, WS_EX_CLIENTEDGE);//|WS_HSCROLL|ES_AUTOHSCROLL);
		} else version(custom_widgets) {
		} else static assert(false);
	}

	private this(bool useCustomWidget, Widget parent) {
		if(!useCustomWidget)
			this(parent);
		else
			super(true, parent);
	}

	override TextDisplayHelper textDisplayHelperFactory(TextLayouter textLayout, ScrollMessageWidget smw) {
		auto tdh = new TextDisplayHelper(textLayout, smw);
		tdh.singleLine = true;
		return tdh;
	}

	version(win32_widgets) {
		mixin Padding!q{0};
		override int minHeight() { return borderBoxForContentBox(Rectangle(Point(0, 0), Size(0, defaultLineHeight))).height; }
		override int maxHeight() { return minHeight; }
	}

	/+
	@property void passwordMode(bool p) {
		SetWindowLongPtr(hwnd, GWL_STYLE, GetWindowLongPtr(hwnd, GWL_STYLE) | ES_PASSWORD);
	}
	+/
}

/// ditto
class CustomLineEdit : LineEdit {
	this(Widget parent) {
		super(true, parent);
	}
}

/++
	A [LineEdit] that displays `*` in place of the actual characters.

	Alas, Windows requires the window to be created differently to use this style,
	so it had to be a new class instead of a toggle on and off on an existing object.

	History:
		Added January 24, 2021

		Implemented on Linux on January 31, 2023.
+/
class PasswordEdit : EditableTextWidget {
	override bool showingVerticalScroll() { return false; }
	override bool showingHorizontalScroll() { return false; }

	override int flexBasisWidth() { return 250; }

	override TextStyle defaultTextStyle() {
		auto cs = getComputedStyle();

		auto osf = new class OperatingSystemFont {
			this() {
				super(cs.font);
			}
			override int stringWidth(scope const(char)[] text, SimpleWindow window = null) {
				int count = 0;
				foreach(dchar ch; text)
					count++;
				return count * super.stringWidth("*", window);
			}
		};

		return new TextDisplayHelper.MyTextStyle(osf);
	}

	override TextDisplayHelper textDisplayHelperFactory(TextLayouter textLayout, ScrollMessageWidget smw) {
		static class TDH : TextDisplayHelper {
			this(TextLayouter textLayout, ScrollMessageWidget smw) {
				singleLine = true;
				super(textLayout, smw);
			}

			override void drawTextSegment(MyTextStyle myStyle, WidgetPainter painter, Point upperLeft, scope const(char)[] text) {
				char[256] buffer = void;
				int bufferLength = 0;
				foreach(dchar ch; text)
					buffer[bufferLength++] = '*';
				painter.setFont(myStyle.font);
				painter.drawText(upperLeft, buffer[0..bufferLength]);
			}
		}

		return new TDH(textLayout, smw);
	}

	///
	this(Widget parent) {
		super(parent);
		version(win32_widgets) {
			createWin32Window(this, "edit"w, "",
				ES_PASSWORD, WS_EX_CLIENTEDGE);//|WS_HSCROLL|ES_AUTOHSCROLL);
		} else version(custom_widgets) {
		} else static assert(false);
	}

	private this(bool useCustomWidget, Widget parent) {
		if(!useCustomWidget)
			this(parent);
		else
			super(true, parent);
	}

	version(win32_widgets) {
		mixin Padding!q{2};
		override int minHeight() { return borderBoxForContentBox(Rectangle(Point(0, 0), Size(0, defaultLineHeight))).height; }
		override int maxHeight() { return minHeight; }
	}
}

/// ditto
class CustomPasswordEdit : PasswordEdit {
	this(Widget parent) {
		super(true, parent);
	}
}


/++
	A `TextEdit` is a multi-line plain text editor, comparable to a HTML `<textarea>`.

	See_Also:
		[TextDisplay] for a read-only text display.

		[LineEdit] for a single line text editor.

		[PasswordEdit] for a single line text editor that obscures its input.
+/
class TextEdit : EditableTextWidget {
	///
	this(Widget parent) {
		super(parent);
		version(win32_widgets) {
			createWin32Window(this, "edit"w, "",
				0|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_WANTRETURN|ES_AUTOHSCROLL|ES_AUTOVSCROLL, WS_EX_CLIENTEDGE);
		} else version(custom_widgets) {
		} else static assert(false);
	}

	private this(bool useCustomWidget, Widget parent) {
		if(!useCustomWidget)
			this(parent);
		else
			super(true, parent);
	}

	override int maxHeight() { return int.max; }
	override int heightStretchiness() { return 7; }

	override int flexBasisWidth() { return 250; }
	override int flexBasisHeight() { return 25; }
}

/// ditto
class CustomTextEdit : TextEdit {
	this(Widget parent) {
		super(true, parent);
	}
}

/+
/++

+/
version(none)
class RichTextDisplay : Widget {
	@property void content(string c) {}
	void appendContent(string c) {}
}
+/

/++
	A read-only text display. It is based on the editable widget base, but does not allow user edits and displays it on the direct background instead of on an editable background.

	History:
		Added October 31, 2023 (dub v11.3)
+/
class TextDisplay : EditableTextWidget {
	this(string text, Widget parent) {
		super(true, parent);
		this.content = text;
	}

	override int maxHeight() { return int.max; }
	override int minHeight() { return Window.defaultLineHeight; }
	override int heightStretchiness() { return 7; }
	override int heightShrinkiness() { return 2; }

	override int flexBasisWidth() {
		return scaleWithDpi(250);
	}
	override int flexBasisHeight() {
		if(textLayout is null || this.tdh is null)
			return Window.defaultLineHeight;

		auto textHeight = borderBoxForContentBox(Rectangle(Point(0, 0), Size(0, textLayout.height))).height;
		return this.tdh.borderBoxForContentBox(Rectangle(Point(0, 0), Size(0, textHeight))).height;
	}

	override TextDisplayHelper textDisplayHelperFactory(TextLayouter textLayout, ScrollMessageWidget smw) {
		return new MyTextDisplayHelper(textLayout, smw);
	}

	override void registerMovement() {
		super.registerMovement();
		this.wordWrapEnabled = true; // FIXME: hack it should do this movement recalc internally
	}

	static class MyTextDisplayHelper : TextDisplayHelper {
		this(TextLayouter textLayout, ScrollMessageWidget smw) {
			smw.verticalScrollBar.hide();
			smw.horizontalScrollBar.hide();
			super(textLayout, smw);
			this.readonly = true;
		}

		override void registerMovement() {
			super.registerMovement();

			// FIXME: do the horizontal one too as needed and make sure that it does
			// wordwrapping again
			if(l.height + smw.horizontalScrollBar.height > this.height)
				smw.verticalScrollBar.show();
			else
				smw.verticalScrollBar.hide();

			l.wordWrapWidth = this.width;

			smw.verticalScrollBar.setPosition = 0;
		}
	}

	class Style : Widget.Style {
		// just want the generic look for these
	}

	mixin OverrideStyle!Style;
}

// FIXME: if a item currently has keyboard focus, even if it is scrolled away, we could keep that item active
/++
	A scrollable viewer for an array of widgets. The widgets inside a list item can be whatever you want, and you can have any number of total items you want because only the visible widgets need to actually exist and load their data at a time, giving constantly predictable performance.


	When you use this, you must subclass it and implement minimally `itemFactory` and `itemSize`, optionally also `layoutMode`.

	Your `itemFactory` must return a subclass of `GenericListViewItem` that implements the abstract method to load item from your list on-demand.

	Note that some state in reused widget objects may either be preserved or reset when the user isn't expecting it. It is your responsibility to handle this when you load an item (try to save it when it is unloaded, then set it when reloaded), but my recommendation would be to have minimal extra state. For example, avoid having a scrollable widget inside a list, since the scroll state might change as it goes out and into view. Instead, I'd suggest making the list be a loader for a details pane on the side.

	History:
		Added August 12, 2024 (dub v11.6)
+/
abstract class GenericListViewWidget : Widget {
	/++

	+/
	this(Widget parent) {
		super(parent);

		smw = new ScrollMessageWidget(this);
		smw.addDefaultKeyboardListeners(itemSize.height, itemSize.width);
		smw.addDefaultWheelListeners(itemSize.height, itemSize.width);
		smw.hsb.hide(); // FIXME: this might actually be useful but we can't really communicate that yet

		inner = new GenericListViewWidgetInner(this, smw, new GenericListViewInnerContainer(smw));
		inner.tabStop = this.tabStop;
		this.tabStop = false;
	}

	private ScrollMessageWidget smw;
	private GenericListViewWidgetInner inner;

	/++

	+/
	abstract GenericListViewItem itemFactory(Widget parent);
	// in device-dependent pixels
	/++

	+/
	abstract Size itemSize(); // use 0 to indicate it can stretch?

	enum LayoutMode {
		rows,
		columns,
		gridRowsFirst,
		gridColumnsFirst
	}
	LayoutMode layoutMode() {
		return LayoutMode.rows;
	}

	private int itemCount_;

	/++
		Sets the count of available items in the list. This will not allocate any items, but it will adjust the scroll bars and try to load items up to this count on-demand as they appear visible.
	+/
	void setItemCount(int count) {
		smw.setTotalArea(inner.width, count * itemSize().height);
		smw.setViewableArea(inner.width, inner.height);
		this.itemCount_ = count;
	}

	/++
		Returns the current count of items expected to available in the list.
	+/
	int itemCount() {
		return this.itemCount_;
	}

	/++
		Call these when the watched data changes. It will cause any visible widgets affected by the change to reload and redraw their data.

		Note you must $(I also) call [setItemCount] if the total item count has changed.
	+/
	void notifyItemsChanged(int index, int count = 1) {
	}
	/// ditto
	void notifyItemsInserted(int index, int count = 1) {
	}
	/// ditto
	void notifyItemsRemoved(int index, int count = 1) {
	}
	/// ditto
	void notifyItemsMoved(int movedFromIndex, int movedToIndex, int count = 1) {
	}

	/++
		History:
			Added January 1, 2025
	+/
	void ensureItemVisibleInScroll(int index) {
		auto itemPos = index * itemSize().height;
		auto vsb = smw.verticalScrollBar;
		auto viewable = vsb.viewableArea_;

		if(viewable == 0) {
			// viewable == 0 isn't actually supposed to happen, this means
			// this method is being called before having our size assigned, it should
			// probably just queue it up for later.
			queuedScroll = index;
			return;
		}

		queuedScroll = int.min;

		if(itemPos < vsb.position) {
			// scroll up to it
			vsb.setPosition(itemPos);
			smw.notify();
		} else if(itemPos + itemSize().height > (vsb.position + viewable)) {
			// scroll down to it, so it is at the bottom

			auto lastViewableItemPosition = (viewable - itemSize.height) / itemSize.height * itemSize.height;
			// need the itemPos to be at the lastViewableItemPosition after scrolling, so subtraction does it

			vsb.setPosition(itemPos - lastViewableItemPosition);
			smw.notify();
		}
	}

	/++
		History:
			Added January 1, 2025;
	+/
	int numberOfCurrentlyFullyVisibleItems() {
		return smw.verticalScrollBar.viewableArea_ / itemSize.height;
	}

	private int queuedScroll = int.min;

	override void recomputeChildLayout() {
		super.recomputeChildLayout();
		if(queuedScroll != int.min)
			ensureItemVisibleInScroll(queuedScroll);
	}

	private GenericListViewItem[] items;

	override void paint(WidgetPainter painter) {}
}

/// ditto
abstract class GenericListViewItem : Widget {
	/++
	+/
	this(Widget parent) {
		super(parent);
	}

	private int _currentIndex = -1;

	private void showItemPrivate(int idx) {
		showItem(idx);
		_currentIndex = idx;
	}

	/++
		Implement this to show an item from your data backing to the list.

		Note that even if you are showing the requested index already, you should still try to reload it because it is possible the index now points to a different item (e.g. an item was added so all the indexes have changed) or if data has changed in this index and it is requesting you to update it prior to a repaint.
	+/
	abstract void showItem(int idx);

	/++
		Maintained by the library after calling [showItem] so the object knows which data index it currently has.

		It may be -1, indicating nothing is currently loaded (or a load failed, and the current data is potentially inconsistent).

		Inside the call to `showItem`, `currentIndexLoaded` is the old index, and the argument to `showItem` is the new index. You might use that to save state to the right place as needed before you overwrite it with the new item.
	+/
	final int currentIndexLoaded() {
		return _currentIndex;
	}
}

///
unittest {
	import arsd.minigui;

	import std.conv;

	void main() {
		auto mw = new MainWindow();

		static class MyListViewItem : GenericListViewItem {
			this(Widget parent) {
				super(parent);

				label = new TextLabel("unloaded", TextAlignment.Left, this);
				button = new Button("Click", this);

				button.addEventListener("triggered", (){
					messageBox(text("clicked ", currentIndexLoaded()));
				});
			}
			override void showItem(int idx) {
				label.label = "Item " ~ to!string(idx);
			}

			TextLabel label;
			Button button;
		}

		auto widget = new class GenericListViewWidget {
			this() {
				super(mw);
			}
			override GenericListViewItem itemFactory(Widget parent) {
				return new MyListViewItem(parent);
			}
			override Size itemSize() {
				return Size(0, scaleWithDpi(80));
			}
		};

		widget.setItemCount(5000);

		mw.loop();
	}
}

// this exists just to wrap the actual GenericListViewWidgetInner so borders
// and padding and stuff can work
private class GenericListViewInnerContainer : Widget {
	this(Widget parent) {
		super(parent);
		this.tabStop = false;
	}

	override void recomputeChildLayout() {
		registerMovement();

		auto cs = getComputedStyle();
		auto bw = getBorderWidth(cs.borderStyle);

		assert(children.length < 2);
		foreach(child; children) {
			child.x = bw + paddingLeft();
			child.y = bw + paddingTop();
			child.width = this.width.NonOverflowingUint - bw - bw - paddingLeft() - paddingRight();
			child.height = this.height.NonOverflowingUint - bw - bw - paddingTop() - paddingBottom();

			child.recomputeChildLayout();
		}
	}

	override void useStyleProperties(scope void delegate(scope .Widget.Style props) dg) {
		if(parent && parent.parent && parent.parent.parent) // ScrollMessageWidgetInner then ScrollMessageWidget then GenericListViewWidget
			return parent.parent.parent.useStyleProperties(dg);
		else
			return super.useStyleProperties(dg);
	}

	override int paddingTop() {
		if(parent && parent.parent && parent.parent.parent) // ScrollMessageWidgetInner then ScrollMessageWidget then GenericListViewWidget
			return parent.parent.parent.paddingTop();
		else
			return super.paddingTop();
	}

	override int paddingBottom() {
		if(parent && parent.parent && parent.parent.parent) // ScrollMessageWidgetInner then ScrollMessageWidget then GenericListViewWidget
			return parent.parent.parent.paddingBottom();
		else
			return super.paddingBottom();
	}

	override int paddingLeft() {
		if(parent && parent.parent && parent.parent.parent) // ScrollMessageWidgetInner then ScrollMessageWidget then GenericListViewWidget
			return parent.parent.parent.paddingLeft();
		else
			return super.paddingLeft();
	}

	override int paddingRight() {
		if(parent && parent.parent && parent.parent.parent) // ScrollMessageWidgetInner then ScrollMessageWidget then GenericListViewWidget
			return parent.parent.parent.paddingRight();
		else
			return super.paddingRight();
	}


}

private class GenericListViewWidgetInner : Widget {
	this(GenericListViewWidget glvw, ScrollMessageWidget smw, GenericListViewInnerContainer parent) {
		super(parent);
		this.glvw = glvw;

		reloadVisible();

		smw.addEventListener("scroll", () {
			reloadVisible();
		});
	}

	override void registerMovement() {
		super.registerMovement();
		if(glvw && glvw.smw)
			glvw.smw.setViewableArea(this.width, this.height);
	}

	void reloadVisible() {
		auto y = glvw.smw.position.y / glvw.itemSize.height;

		// idk why i had this here it doesn't seem to be ueful and actually made last items diasppear
		//int offset = glvw.smw.position.y % glvw.itemSize.height;
		//if(offset || y >= glvw.itemCount())
			//y--;

		if(y < 0)
			y = 0;

		recomputeChildLayout();

		foreach(item; glvw.items) {
			if(y < glvw.itemCount()) {
				item.showItemPrivate(y);
				item.show();
			} else {
				item.hide();
			}
			y++;
		}

		this.redraw();
	}

	private GenericListViewWidget glvw;

	private bool inRcl;
	override void recomputeChildLayout() {
		if(inRcl)
			return;
		inRcl = true;
		scope(exit)
			inRcl = false;

		registerMovement();

		auto ih = glvw.itemSize().height;

		auto itemCount = this.height / ih + 2; // extra for partial display before and after
		bool hadNew;
		while(glvw.items.length < itemCount) {
			// FIXME: free the old items? maybe just set length
			glvw.items ~= glvw.itemFactory(this);
			hadNew = true;
		}

		if(hadNew)
			reloadVisible();

		int y = -(glvw.smw.position.y % ih) + this.paddingTop();
		foreach(child; children) {
			child.x = this.paddingLeft();
			child.y = y;
			y += glvw.itemSize().height;
			child.width = this.width.NonOverflowingUint - this.paddingLeft() - this.paddingRight();
			child.height = ih;

			child.recomputeChildLayout();
		}
	}
}



/++
	History:
		It was a child of Window before, but as of September 29, 2024, it is now a child of `Dialog`.
+/
class MessageBox : Dialog {
	private string message;
	MessageBoxButton buttonPressed = MessageBoxButton.None;
	/++

		History:
		The overload that takes `Window originator` was added on September 29, 2024.
	+/
	this(string message, string[] buttons = ["OK"], MessageBoxButton[] buttonIds = [MessageBoxButton.OK]) {
		this(null, message, buttons, buttonIds);
	}
	/// ditto
	this(Window originator, string message, string[] buttons = ["OK"], MessageBoxButton[] buttonIds = [MessageBoxButton.OK]) {
		message = message.stripRightInternal;
		int mainWidth;

		// estimate longest line
		int count;
		foreach(ch; message) {
			if(ch == '\n') {
				if(count > mainWidth)
					mainWidth = count;
				count = 0;
			} else {
				count++;
			}
		}
		mainWidth *= 8;
		if(mainWidth < 300)
			mainWidth = 300;
		if(mainWidth > 600)
			mainWidth = 600;

		super(originator, mainWidth, 100);

		assert(buttons.length);
		assert(buttons.length ==  buttonIds.length);

		this.message = message;

		auto label = new TextDisplay(message, this);

		auto hl = new HorizontalLayout(this);
		auto spacer = new HorizontalSpacer(hl); // to right align

		foreach(idx, buttonText; buttons) {
			auto button = new CommandButton(buttonText, hl);

			button.addEventListener(EventType.triggered, ((size_t idx) { return () {
				this.buttonPressed = buttonIds[idx];
				win.close();
			}; })(idx));

			if(idx == 0)
				button.focus();
		}

		if(buttons.length == 1)
			auto spacer2 = new HorizontalSpacer(hl); // to center it

		auto size = label.flexBasisHeight() + hl.minHeight() + this.paddingTop + this.paddingBottom;
		auto max = scaleWithDpi(600); // random max height
		if(size > max)
			size = max;

		win.resize(scaleWithDpi(mainWidth), size);

		win.show();
		redraw();
	}

	override void OK() {
		this.win.close();
	}

	mixin Padding!q{16};
}

///
enum MessageBoxStyle {
	OK, ///
	OKCancel, ///
	RetryCancel, ///
	YesNo, ///
	YesNoCancel, ///
	RetryCancelContinue /// In a multi-part process, if one part fails, ask the user if you should retry that failed step, cancel the entire process, or just continue with the next step, accepting failure on this step.
}

///
enum MessageBoxIcon {
	None, ///
	Info, ///
	Warning, ///
	Error ///
}

/// Identifies the button the user pressed on a message box.
enum MessageBoxButton {
	None, /// The user closed the message box without clicking any of the buttons.
	OK, ///
	Cancel, ///
	Retry, ///
	Yes, ///
	No, ///
	Continue ///
}


/++
	Displays a modal message box, blocking until the user dismisses it. These global ones are discouraged in favor of the same methods on [Window], which give better user experience since the message box is tied the parent window instead of acting independently.

	Returns: the button pressed.
+/
MessageBoxButton messageBox(string title, string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
	return messageBox(null, title, message, style, icon);
}

/// ditto
int messageBox(string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
	return messageBox(null, null, message, style, icon);
}

/++

+/
MessageBoxButton messageBox(Window originator, string title, string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
	version(win32_widgets) {
		WCharzBuffer t = WCharzBuffer(title);
		WCharzBuffer m = WCharzBuffer(message);
		UINT type;
		with(MessageBoxStyle)
		final switch(style) {
			case OK: type |= MB_OK; break;
			case OKCancel: type |= MB_OKCANCEL; break;
			case RetryCancel: type |= MB_RETRYCANCEL; break;
			case YesNo: type |= MB_YESNO; break;
			case YesNoCancel: type |= MB_YESNOCANCEL; break;
			case RetryCancelContinue: type |= MB_CANCELTRYCONTINUE; break;
		}
		with(MessageBoxIcon)
		final switch(icon) {
			case None: break;
			case Info: type |= MB_ICONINFORMATION; break;
			case Warning: type |= MB_ICONWARNING; break;
			case Error: type |= MB_ICONERROR; break;
		}
		switch(MessageBoxW(originator is null ? null : originator.win.hwnd, m.ptr, t.ptr, type)) {
			case IDOK: return MessageBoxButton.OK;
			case IDCANCEL: return MessageBoxButton.Cancel;
			case IDTRYAGAIN, IDRETRY: return MessageBoxButton.Retry;
			case IDYES: return MessageBoxButton.Yes;
			case IDNO: return MessageBoxButton.No;
			case IDCONTINUE: return MessageBoxButton.Continue;
			default: return MessageBoxButton.None;
		}
	} else {
		string[] buttons;
		MessageBoxButton[] buttonIds;
		with(MessageBoxStyle)
		final switch(style) {
			case OK:
				buttons = ["OK"];
				buttonIds = [MessageBoxButton.OK];
			break;
			case OKCancel:
				buttons = ["OK", "Cancel"];
				buttonIds = [MessageBoxButton.OK, MessageBoxButton.Cancel];
			break;
			case RetryCancel:
				buttons = ["Retry", "Cancel"];
				buttonIds = [MessageBoxButton.Retry, MessageBoxButton.Cancel];
			break;
			case YesNo:
				buttons = ["Yes", "No"];
				buttonIds = [MessageBoxButton.Yes, MessageBoxButton.No];
			break;
			case YesNoCancel:
				buttons = ["Yes", "No", "Cancel"];
				buttonIds = [MessageBoxButton.Yes, MessageBoxButton.No, MessageBoxButton.Cancel];
			break;
			case RetryCancelContinue:
				buttons = ["Try Again", "Cancel", "Continue"];
				buttonIds = [MessageBoxButton.Retry, MessageBoxButton.Cancel, MessageBoxButton.Continue];
			break;
		}
		auto mb = new MessageBox(originator, message, buttons, buttonIds);
		EventLoop el = EventLoop.get;
		el.run(() { return !mb.win.closed; });
		return mb.buttonPressed;
	}

}

/// ditto
int messageBox(Window originator, string message, MessageBoxStyle style = MessageBoxStyle.OK, MessageBoxIcon icon = MessageBoxIcon.None) {
	return messageBox(originator, null, message, style, icon);
}


///
alias void delegate(Widget handlerAttachedTo, Event event) EventHandler;

/++
	This is an opaque type you can use to disconnect an event handler when you're no longer interested.

	History:
		The data members were `public` (albeit undocumented and not intended for use) prior to May 13, 2021. They are now `private`, reflecting the single intended use of this object.
+/
struct EventListener {
	private Widget widget;
	private string event;
	private EventHandler handler;
	private bool useCapture;

	///
	void disconnect() {
		if(widget !is null && handler !is null)
			widget.removeEventListener(this);
	}
}

/++
	The purpose of this enum was to give a compile-time checked version of various standard event strings.

	Now, I recommend you use a statically typed event object instead.

	See_Also: [Event]
+/
enum EventType : string {
	click = "click", ///

	mouseenter = "mouseenter", ///
	mouseleave = "mouseleave", ///
	mousein = "mousein", ///
	mouseout = "mouseout", ///
	mouseup = "mouseup", ///
	mousedown = "mousedown", ///
	mousemove = "mousemove", ///

	keydown = "keydown", ///
	keyup = "keyup", ///
	char_ = "char", ///

	focus = "focus", ///
	blur = "blur", ///

	triggered = "triggered", ///

	change = "change", ///
}

/++
	Represents an event that is currently being processed.


	Minigui's event model is based on the web browser. An event has a name, a target,
	and an associated data object. It starts from the window and works its way down through
	the target through all intermediate [Widget]s, triggering capture phase handlers as it goes,
	then goes back up again all the way back to the window, triggering bubble phase handlers. At
	the end, if [Event.preventDefault] has not been called, it calls the target widget's default
	handlers for the event (please note that default handlers will be called even if [Event.stopPropagation]
	was called; that just stops it from calling other handlers in the widget tree, but the default happens
	whenever propagation is done, not only if it gets to the end of the chain).

	This model has several nice points:

	$(LIST
		* It is easy to delegate dynamic handlers to a parent. You can have a parent container
		  with event handlers set, then add/remove children as much as you want without needing
		  to manage the event handlers on them - the parent alone can manage everything.

		* It is easy to create new custom events in your application.

		* It is familiar to many web developers.
	)

	There's a few downsides though:

	$(LIST
		* There's not a lot of type safety.

		* You don't get a static list of what events a widget can emit.

		* Tracing where an event got cancelled along the chain can get difficult; the downside of
		  the central delegation benefit is it can be lead to debugging of action at a distance.
	)

	In May 2021, I started to adjust this model to minigui takes better advantage of D over Javascript
	while keeping the benefits - and most compatibility with - the existing model. The main idea is
	to simply use a D object type which provides a static interface as well as a built-in event name.
	Then, a new static interface allows you to see what an event can emit and attach handlers to it
	similarly to C#, which just forwards to the JS style api. They're fully compatible so you can still
	delegate to a parent and use custom events as well as using the runtime dynamic access, in addition
	to having a little more help from the D compiler and documentation generator.

	Your code would change like this:

	---
	// old
	widget.addEventListener("keydown", (Event ev) { ... }, /* optional arg */ useCapture );

	// new
	widget.addEventListener((KeyDownEvent ev) { ... }, /* optional arg */ useCapture );
	---

	The old-style code will still work, but using certain members of the [Event] class will generate deprecation warnings. Changing handlers to the new style will silence all those warnings at once without requiring any other changes to your code.

	All you have to do is replace the string with a specific Event subclass. It will figure out the event string from the class.

	Alternatively, you can cast the Event yourself to the appropriate subclass, but it is easier to let the library do it for you!

	Thus the family of functions are:

	[Widget.addEventListener] is the fully-flexible base method. It has two main overload families: one with the string and one without. The one with the string takes the Event object, the one without determines the string from the type you pass. The string "*" matches ALL events that pass through.

	[Widget.addDirectEventListener] is addEventListener, but only calls the handler if target == this. Useful for something you can't afford to delegate.

	[Widget.setDefaultEventHandler] is what is called if no preventDefault was called. This should be called in the widget's constructor to set default behaivor. Default event handlers are only called on the event target.

	Let's implement a custom widget that can emit a ChangeEvent describing its `checked` property:

	---
	class MyCheckbox : Widget {
		/// This gives a chance to document it and generates a convenience function to send it and attach handlers.
		/// It is NOT actually required but should be used whenever possible.
		mixin Emits!(ChangeEvent!bool);

		this(Widget parent) {
			super(parent);
			setDefaultEventHandler((ClickEvent) { checked = !checked; });
		}

		private bool _checked;
		@property bool checked() { return _checked; }
		@property void checked(bool set) {
			_checked = set;
			emit!(ChangeEvent!bool)(&checked);
		}
	}
	---

	## Creating Your Own Events

	To avoid clashing in the string namespace, your events should use your module and class name as the event string. The simple code `mixin Register;` in your Event subclass will do this for you. You should mark events `final` unless you specifically plan to use it as a shared base. Only `Widget` and final classes should actually be sent (and preferably, not even `Widget`), with few exceptions.

	---
	final class MyEvent : Event {
		this(Widget target) { super(EventString, target); }
		mixin Register; // adds EventString and other reflection information
	}
	---

	Then declare that it is sent with the [Emits] mixin, so you can use [Widget.emit] to dispatch it.

	History:
		Prior to May 2021, Event had a set of pre-made members with no extensibility (outside of diy casts) and no static checks on field presence.

		After that, those old pre-made members are deprecated accessors and the fields are moved to child classes. To transition, change string events to typed events or do a dynamic cast (don't forget the null check!) in your handler.
+/
/+

	## General Conventions

	Change events should NOT be emitted when a value is changed programmatically. Indeed, methods should usually not send events. The point of an event is to know something changed and when you call a method, you already know about it.


	## Qt-style signals and slots

	Some events make sense to use with just name and data type. These are one-way notifications with no propagation nor default behavior and thus separate from the other event system.

	The intention is for events to be used when

	---
	class Demo : Widget {
		this() {
			myPropertyChanged = Signal!int(this);
		}
		@property myProperty(int v) {
			myPropertyChanged.emit(v);
		}

		Signal!int myPropertyChanged; // i need to get `this` off it and inspect the name...
		// but it can just genuinely not care about `this` since that's not really passed.
	}

	class Foo : Widget {
		// the slot uda is not necessary, but it helps the script and ui builder find it.
		@slot void setValue(int v) { ... }
	}

	demo.myPropertyChanged.connect(&foo.setValue);
	---

	The Signal type has a disabled default constructor, meaning your widget constructor must pass `this` to it in its constructor.

	Some events may also wish to implement the Signal interface. These use particular arguments to call a method automatically.

	class StringChangeEvent : ChangeEvent, Signal!string {
		mixin SignalImpl
	}

+/
class Event : ReflectableProperties {
	/// Creates an event without populating any members and without sending it. See [dispatch]
	this(string eventName, Widget emittedBy) {
		this.eventName = eventName;
		this.srcElement = emittedBy;
	}


	/// Implementations for the [ReflectableProperties] interface/
	void getPropertiesList(scope void delegate(string name) sink) const {}
	/// ditto
	void getPropertyAsString(string name, scope void delegate(string name, scope const(char)[] value, bool valueIsJson) sink) { }
	/// ditto
	SetPropertyResult setPropertyFromString(string name, scope const(char)[] str, bool strIsJson) {
		return SetPropertyResult.notPermitted;
	}


	/+
	/++
		This is an internal implementation detail of [Register] and is subject to be changed or removed at any time without notice.

		It is just protected so the mixin template can see it from user modules. If I made it private, even my own mixin template couldn't see it due to mixin scoping rules.
	+/
	protected final void sinkJsonString(string memberName, scope const(char)[] value, scope void delegate(string name, scope const(char)[] value) finalSink) {
		if(value.length == 0) {
			finalSink(memberName, `""`);
			return;
		}

		char[1024] bufferBacking;
		char[] buffer = bufferBacking;
		int bufferPosition;

		void sink(char ch) {
			if(bufferPosition >= buffer.length)
				buffer.length = buffer.length + 1024;
			buffer[bufferPosition++] = ch;
		}

		sink('"');

		foreach(ch; value) {
			switch(ch) {
				case '\\':
					sink('\\'); sink('\\');
				break;
				case '"':
					sink('\\'); sink('"');
				break;
				case '\n':
					sink('\\'); sink('n');
				break;
				case '\r':
					sink('\\'); sink('r');
				break;
				case '\t':
					sink('\\'); sink('t');
				break;
				default:
					sink(ch);
			}
		}

		sink('"');

		finalSink(memberName, buffer[0 .. bufferPosition]);
	}
	+/

	/+
	enum EventInitiator {
		system,
		minigui,
		user
	}

	immutable EventInitiator; initiatedBy;
	+/

	/++
		Events should generally follow the propagation model, but there's some exceptions
		to that rule. If so, they should override this to return false. In that case, only
		bubbling event handlers on the target itself and capturing event handlers on the containing
		window will be called. (That is, [dispatch] will call [sendDirectly] instead of doing the normal
		capture -> target -> bubble process.)

		History:
			Added May 12, 2021
	+/
	bool propagates() const pure nothrow @nogc @safe {
		return true;
	}

	/++
		hints as to whether preventDefault will actually do anything. not entirely reliable.

		History:
			Added May 14, 2021
	+/
	bool cancelable() const pure nothrow @nogc @safe {
		return true;
	}

	/++
		You can mix this into child class to register some boilerplate. It includes the `EventString`
		member, a constructor, and implementations of the dynamic get data interfaces.

		If you fail to do this, your event will probably not have full compatibility but it might still work for you.


		You can override the default EventString by simply providing your own in the form of
		`enum string EventString = "some.name";` The default is the name of your class and its parent entity
		which provides some namespace protection against conflicts in other libraries while still being fairly
		easy to use.

		If you provide your own constructor, it will override the default constructor provided here. A constructor
		must call `super(EventString, passed_widget_target)` at some point. The `passed_widget_target` must be the
		first argument to your constructor.

		History:
			Added May 13, 2021.
	+/
	protected static mixin template Register() {
		public enum string EventString = __traits(identifier, __traits(parent, typeof(this))) ~ "." ~  __traits(identifier, typeof(this));
		this(Widget target) { super(EventString, target); }

		mixin ReflectableProperties.RegisterGetters;
	}

	/++
		This is the widget that emitted the event.


		The aliased names come from Javascript for ease of web developers to transition in, but they're all synonyms.

		History:
			The `source` name was added on May 14, 2021. It is a little weird that `source` and `target` are synonyms,
			but that's a side effect of it doing both capture and bubble handlers and people are used to it from the web
			so I don't intend to remove these aliases.
	+/
	Widget source;
	/// ditto
	alias source target;
	/// ditto
	alias source srcElement;

	Widget relatedTarget; /// Note: likely to be deprecated at some point.

	/// Prevents the default event handler (if there is one) from being called
	void preventDefault() {
		lastDefaultPrevented = true;
		defaultPrevented = true;
	}

	/// Stops the event propagation immediately.
	void stopPropagation() {
		propagationStopped = true;
	}

	private bool defaultPrevented;
	private bool propagationStopped;
	private string eventName;

	private bool isBubbling;

	/// This is an internal implementation detail you should not use. It would be private if the language allowed it and it may be removed without notice.
	protected void adjustClientCoordinates(int deltaX, int deltaY) { }

	/++
		this sends it only to the target. If you want propagation, use dispatch() instead.

		This should be made private!!!

	+/
	void sendDirectly() {
		if(srcElement is null)
			return;

		// i capturing on the parent too. The main reason for this is that gives a central place to log all events for the debug window.

		//debug if(eventName != "mousemove" && target !is null && target.parentWindow && target.parentWindow.devTools)
			//target.parentWindow.devTools.log("Event ", eventName, " dispatched directly to ", srcElement);

		if(auto e = target.parentWindow) {
			if(auto handlers = "*" in e.capturingEventHandlers)
			foreach(handler; *handlers)
				if(handler) handler(e, this);
			if(auto handlers = eventName in e.capturingEventHandlers)
			foreach(handler; *handlers)
				if(handler) handler(e, this);
		}

		auto e = srcElement;

		if(auto handlers = eventName in e.bubblingEventHandlers)
		foreach(handler; *handlers)
			if(handler) handler(e, this);

		if(auto handlers = "*" in e.bubblingEventHandlers)
		foreach(handler; *handlers)
			if(handler) handler(e, this);

		// there's never a default for a catch-all event
		if(!defaultPrevented)
			if(eventName in e.defaultEventHandlers)
				e.defaultEventHandlers[eventName](e, this);
	}

	/// this dispatches the element using the capture -> target -> bubble process
	void dispatch() {
		if(srcElement is null)
			return;

		if(!propagates) {
			sendDirectly;
			return;
		}

		//debug if(eventName != "mousemove" && target !is null && target.parentWindow && target.parentWindow.devTools)
			//target.parentWindow.devTools.log("Event ", eventName, " dispatched to ", srcElement);

		// first capture, then bubble

		Widget[] chain;
		Widget curr = srcElement;
		while(curr) {
			auto l = curr;
			chain ~= l;
			curr = curr.parent;
		}

		isBubbling = false;

		foreach_reverse(e; chain) {
			if(auto handlers = "*" in e.capturingEventHandlers)
				foreach(handler; *handlers) if(handler !is null) handler(e, this);

			if(propagationStopped)
				break;

			if(auto handlers = eventName in e.capturingEventHandlers)
				foreach(handler; *handlers) if(handler !is null) handler(e, this);

			// the default on capture should really be to always do nothing

			//if(!defaultPrevented)
			//	if(eventName in e.defaultEventHandlers)
			//		e.defaultEventHandlers[eventName](e.element, this);

			if(propagationStopped)
				break;
		}

		int adjustX;
		int adjustY;

		isBubbling = true;
		if(!propagationStopped)
		foreach(e; chain) {
			if(auto handlers = eventName in e.bubblingEventHandlers)
				foreach(handler; *handlers) if(handler !is null) handler(e, this);

			if(propagationStopped)
				break;

			if(auto handlers = "*" in e.bubblingEventHandlers)
				foreach(handler; *handlers) if(handler !is null) handler(e, this);

			if(propagationStopped)
				break;

			if(e.encapsulatedChildren()) {
				adjustClientCoordinates(adjustX, adjustY);
				target = e;
			} else {
				adjustX += e.x;
				adjustY += e.y;
			}
		}

		if(!defaultPrevented)
		foreach(e; chain) {
			if(eventName in e.defaultEventHandlers)
				e.defaultEventHandlers[eventName](e, this);
		}
	}


	/* old compatibility things */
	deprecated("Use some subclass of KeyEventBase instead of plain Event in your handler going forward. WARNING these may crash on non-key events!")
	final @property {
		Key key() { return (cast(KeyEventBase) this).key; }
		KeyEvent originalKeyEvent() { return (cast(KeyEventBase) this).originalKeyEvent; }

		bool ctrlKey() { return (cast(KeyEventBase) this).ctrlKey; }
		bool altKey() { return (cast(KeyEventBase) this).altKey; }
		bool shiftKey() { return (cast(KeyEventBase) this).shiftKey; }
	}

	deprecated("Use some subclass of MouseEventBase instead of Event in your handler going forward. WARNING these may crash on non-mouse events!")
	final @property {
		int clientX() { return (cast(MouseEventBase) this).clientX; }
		int clientY() { return (cast(MouseEventBase) this).clientY; }

		int viewportX() { return (cast(MouseEventBase) this).viewportX; }
		int viewportY() { return (cast(MouseEventBase) this).viewportY; }

		int button() { return (cast(MouseEventBase) this).button; }
		int buttonLinear() { return (cast(MouseEventBase) this).buttonLinear; }
	}

	deprecated("Use either a KeyEventBase or a MouseEventBase instead of Event in your handler going forward")
	final @property {
		int state() {
			if(auto meb = cast(MouseEventBase) this)
				return meb.state;
			if(auto keb = cast(KeyEventBase) this)
				return keb.state;
			assert(0);
		}
	}

	deprecated("Use a CharEvent instead of Event in your handler going forward")
	final @property {
		dchar character() {
			if(auto ce = cast(CharEvent) this)
				return ce.character;
			return dchar.init;
		}
	}

	// for change events
	@property {
		///
		int intValue() { return 0; }
		///
		string stringValue() { return null; }
	}
}

/++
	This lets you statically verify you send the events you claim you send and gives you a hook to document them.

	Please note that a widget may send events not listed as Emits. You can always construct and dispatch
	dynamic and custom events, but the static list helps ensure you get them right.

	If this is declared, you can use [Widget.emit] to send the event.

	All events work the same way though, following the capture->widget->bubble model described under [Event].

	History:
		Added May 4, 2021
+/
mixin template Emits(EventType) {
	import arsd.minigui : EventString;
	static if(is(EventType : Event) && !is(EventType == Event))
		mixin("private EventType[0] emits_" ~ EventStringIdentifier!EventType ~";");
	else
		static assert(0, "You can only emit subclasses of Event");
}

/// ditto
mixin template Emits(string eventString) {
	mixin("private Event[0] emits_" ~ eventString ~";");
}

/*
class SignalEvent(string name) : Event {

}
*/

/++
	Command Events are used with a widget wants to issue a higher-level, yet loosely coupled command do its parents and other interested listeners, for example, "scroll up".


	Command Events are a bit special in the way they're used. You don't typically refer to them by object, but instead by a name string and a set of arguments. The expectation is that they will be delegated to a parent, which "consumes" the command - it handles it and stops its propagation upward. The [consumesCommand] method will call your handler with the arguments, then stop the command event's propagation for you, meaning you don't have to call [Event.stopPropagation]. A command event should have no default behavior, so calling [Event.preventDefault] is not necessary either.

	History:
		Added on May 13, 2021. Prior to that, you'd most likely `addEventListener(EventType.triggered, ...)` to handle similar things.
+/
class CommandEvent : Event {
	enum EventString = "command";
	this(Widget source, string CommandString = EventString) {
		super(CommandString, source);
	}
}

/++
	A [CommandEvent] is typically actually an instance of these to hold the strongly-typed arguments.
+/
class CommandEventWithArgs(Args...) : CommandEvent {
	this(Widget source, string CommandString, Args args) { super(source, CommandString); this.args = args; }
	Args args;
}

/++
	Declares that the given widget consumes a command identified by the `CommandString` AND containing `Args`. Your `handler` is called with the arguments, then the event's propagation is stopped, so it will not be seen by the consumer's parents.

	See [CommandEvent] for more information.

	Returns:
		The [EventListener] you can use to remove the handler.
+/
EventListener consumesCommand(string CommandString, WidgetType, Args...)(WidgetType w, void delegate(Args) handler) {
	return w.addEventListener(CommandString, (Event ev) {
		if(ev.target is w)
			return; // it does not consume its own commands!
		if(auto cev = cast(CommandEventWithArgs!Args) ev) {
			handler(cev.args);
			ev.stopPropagation();
		}
	});
}

/++
	Emits a command to the sender widget's parents with the given `CommandString` and `args`. You have no way of knowing if it was ever actually consumed due to the loose coupling. Instead, the consumer may broadcast a state update back toward you.
+/
void emitCommand(string CommandString, WidgetType, Args...)(WidgetType w, Args args) {
	auto event = new CommandEventWithArgs!Args(w, CommandString, args);
	event.dispatch();
}

/++
	Widgets emit `ResizeEvent`s any time they are resized. You check [Widget.width] and [Widget.height] upon receiving this event to know the new size.

	If you need to know the old size, you need to store it yourself.

	History:
		Made final on January 3, 2025 (dub v12.0)
+/
final class ResizeEvent : Event {
	enum EventString = "resize";

	this(Widget target) { super(EventString, target); }

	override bool propagates() const { return false; }
}

/++
	ClosingEvent is fired when a user is attempting to close a window. You can `preventDefault` to cancel the close.

	ClosedEvent happens when the window has been closed. It is already gone by the time this event fires, meaning you cannot prevent the close. Use [ClosingEvent] if you want to cancel, use [ClosedEvent] if you simply want to be notified.

	History:
		Added June 21, 2021 (dub v10.1)

		Made final on January 3, 2025 (dub v12.0)
+/
final class ClosingEvent : Event {
	enum EventString = "closing";

	this(Widget target) { super(EventString, target); }

	override bool propagates() const { return false; }
	override bool cancelable() const { return true; }
}

/// ditto
final class ClosedEvent : Event {
	enum EventString = "closed";

	this(Widget target) { super(EventString, target); }

	override bool propagates() const { return false; }
	override bool cancelable() const { return false; }
}

///
final class BlurEvent : Event {
	enum EventString = "blur";

	// FIXME: related target?
	this(Widget target) { super(EventString, target); }

	override bool propagates() const { return false; }
}

///
final class FocusEvent : Event {
	enum EventString = "focus";

	// FIXME: related target?
	this(Widget target) { super(EventString, target); }

	override bool propagates() const { return false; }
}

/++
	FocusInEvent is a FocusEvent that propagates, while FocusOutEvent is a BlurEvent that propagates.

	History:
		Added July 3, 2021
+/
final class FocusInEvent : Event {
	enum EventString = "focusin";

	// FIXME: related target?
	this(Widget target) { super(EventString, target); }

	override bool cancelable() const { return false; }
}

/// ditto
final class FocusOutEvent : Event {
	enum EventString = "focusout";

	// FIXME: related target?
	this(Widget target) { super(EventString, target); }

	override bool cancelable() const { return false; }
}

///
final class ScrollEvent : Event {
	enum EventString = "scroll";
	this(Widget target) { super(EventString, target); }

	override bool cancelable() const { return false; }
}

/++
	Indicates that a character has been typed by the user. Normally dispatched to the currently focused widget.

	History:
		Added May 2, 2021. Previously, this was simply a "char" event and `character` as a member of the [Event] base class.
+/
final class CharEvent : Event {
	enum EventString = "char";
	this(Widget target, dchar ch) {
		character = ch;
		super(EventString, target);
	}

	immutable dchar character;
}

/++
	You should generally use a `ChangeEvent!Type` instead of this directly. See [ChangeEvent] for more information.
+/
abstract class ChangeEventBase : Event {
	enum EventString = "change";
	this(Widget target) {
		super(EventString, target);
	}

	/+
		// idk where or how exactly i want to do this.
		// i might come back to it later.

	// If a widget itself broadcasts one of theses itself, it stops propagation going down
	// this way the source doesn't get too confused (think of a nested scroll widget)
	//
	// the idea is like the scroll bar emits a command event saying like "scroll left one line"
	// then you consume that command and change you scroll x position to whatever. then you do
	// some kind of change event that is broadcast back to the children and any horizontal scroll
	// listeners are now able to update, without having an explicit connection between them.
	void broadcastToChildren(string fieldName) {

	}
	+/
}

/++
	Single-value widgets (that is, ones with a programming interface that just expose a value that the user has control over) should emit this after their value changes.


	Generally speaking, if your widget can reasonably have a `@property T value();` or `@property bool checked();` method, it should probably emit this event when that value changes to inform its parents that they can now read a new value. Whether you emit it on each keystroke or other intermediate values or only when a value is committed (e.g. when the user leaves the field) is up to the widget. You might even make that a togglable property depending on your needs (emitting events can get expensive).

	The delegate you pass to the constructor ought to be a handle to your getter property. If your widget has `@property string value()` for example, you emit `ChangeEvent!string(&value);`

	Since it is emitted after the value has already changed, [preventDefault] is unlikely to do anything.

	History:
		Added May 11, 2021. Prior to that, widgets would more likely just send `new Event("change")`. These typed ChangeEvents are still compatible with listeners subscribed to generic change events.
+/
final class ChangeEvent(T) : ChangeEventBase {
	this(Widget target, T delegate() getNewValue) {
		assert(getNewValue !is null);
		this.getNewValue = getNewValue;
		super(target);
	}

	private T delegate() getNewValue;

	/++
		Gets the new value that just changed.
	+/
	@property T value() {
		return getNewValue();
	}

	/// compatibility method for old generic Events
	static if(is(immutable T == immutable int))
		override int intValue() { return value; }
	/// ditto
	static if(is(immutable T == immutable string))
		override string stringValue() { return value; }
}

/++
	Contains shared properties for [KeyDownEvent]s and [KeyUpEvent]s.


	You can construct these yourself, but generally the system will send them to you and there's little need to emit your own.

	History:
		Added May 2, 2021. Previously, its properties were members of the [Event] base class.
+/
abstract class KeyEventBase : Event {
	this(string name, Widget target) {
		super(name, target);
	}

	// for key events
	Key key; ///

	KeyEvent originalKeyEvent;

	/++
		Indicates the current state of the given keyboard modifier keys.

		History:
			Added to events on April 15, 2020.
	+/
	bool ctrlKey;

	/// ditto
	bool altKey;

	/// ditto
	bool shiftKey;

	/++
		The raw bitflags that are parsed out into [ctrlKey], [altKey], and [shiftKey].

		See [arsd.simpledisplay.ModifierState] for other possible flags.
	+/
	int state;

	mixin Register;
}

/++
	Indicates that the user has pressed a key on the keyboard, or if they've been holding it long enough to repeat (key down events are sent both on the initial press then repeated by the OS on its own time.) For available properties, see [KeyEventBase].


	You can construct these yourself, but generally the system will send them to you and there's little need to emit your own.

	Please note that a `KeyDownEvent` will also often send a [CharEvent], but there is not necessarily a one-to-one relationship between them. For example, a capital letter may send KeyDownEvent for Key.Shift, then KeyDownEvent for the letter's key (this key may not match the letter due to keyboard mappings), then CharEvent for the letter, then KeyUpEvent for the letter, and finally, KeyUpEvent for shift.

	For some characters, there are other key down events as well. A compose key can be pressed and released, followed by several letters pressed and released to generate one character. This is why [CharEvent] is a separate entity.

	See_Also: [KeyUpEvent], [CharEvent]

	History:
		Added May 2, 2021. Previously, it was only seen as the base [Event] class on "keydown" event listeners.
+/
final class KeyDownEvent : KeyEventBase {
	enum EventString = "keydown";
	this(Widget target) { super(EventString, target); }
}

/++
	Indicates that the user has released a key on the keyboard. For available properties, see [KeyEventBase].


	You can construct these yourself, but generally the system will send them to you and there's little need to emit your own.

	See_Also: [KeyDownEvent], [CharEvent]

	History:
		Added May 2, 2021. Previously, it was only seen as the base [Event] class on "keyup" event listeners.
+/
final class KeyUpEvent : KeyEventBase {
	enum EventString = "keyup";
	this(Widget target) { super(EventString, target); }
}

/++
	Contains shared properties for various mouse events;


	You can construct these yourself, but generally the system will send them to you and there's little need to emit your own.

	History:
		Added May 2, 2021. Previously, its properties were members of the [Event] base class.
+/
abstract class MouseEventBase : Event {
	this(string name, Widget target) {
		super(name, target);
	}

	// for mouse events
	int clientX; /// The mouse event location relative to the target widget
	int clientY; /// ditto

	int viewportX; /// The mouse event location relative to the window origin
	int viewportY; /// ditto

	int button; /// See: [MouseEvent.button]
	int buttonLinear; /// See: [MouseEvent.buttonLinear]

	/++
		Indicates the current state of the given keyboard modifier keys.

		History:
			Added to mouse events on September 28, 2010.
	+/
	bool ctrlKey;

	/// ditto
	bool altKey;

	/// ditto
	bool shiftKey;



	int state; ///

	/++
		for consistent names with key event.

		History:
			Added September 28, 2021 (dub v10.3)
	+/
	alias modifierState = state;

	/++
		Mouse wheel movement sends down/up/click events just like other buttons clicking. This method is to help you filter that out.

		History:
			Added May 15, 2021
	+/
	bool isMouseWheel() {
		return button == MouseButton.wheelUp || button == MouseButton.wheelDown;
	}

	// private
	override void adjustClientCoordinates(int deltaX, int deltaY) {
		clientX += deltaX;
		clientY += deltaY;
	}

	mixin Register;
}

/++
	Indicates that the user has worked with the mouse over your widget. For available properties, see [MouseEventBase].


	$(WARNING
		Important: MouseDownEvent, MouseUpEvent, ClickEvent, and DoubleClickEvent are all sent for all mouse buttons and
		for wheel movement! You should check the [MouseEventBase.button|button] property in most your handlers to get correct
		behavior.

		Use [MouseEventBase.isMouseWheel] to filter wheel events while keeping others.
	)

	[MouseDownEvent] is sent when the user presses a mouse button. It is also sent on mouse wheel movement.

	[MouseUpEvent] is sent when the user releases a mouse button.

	[MouseMoveEvent] is sent when the mouse is moved. Please note you may not receive this in some cases unless a button is also pressed; the system is free to withhold them as an optimization. (In practice, [arsd.simpledisplay] does not request mouse motion event without a held button if it is on a remote X11 link, but does elsewhere at this time.)

	[ClickEvent] is sent when the user clicks on the widget. It may also be sent with keyboard control, though minigui prefers to send a "triggered" event in addition to a mouse click and instead of a simulated mouse click in cases like keyboard activation of a button.

	[DoubleClickEvent] is sent when the user clicks twice on a thing quickly, immediately after the second MouseDownEvent. The sequence is: MouseDownEvent, MouseUpEvent, ClickEvent, MouseDownEvent, DoubleClickEvent, MouseUpEvent. The second ClickEvent is NOT sent. Note that this is different than Javascript! They would send down,up,click,down,up,click,dblclick. Minigui does it differently because this is the way the Windows OS reports it.

	[MouseOverEvent] is sent then the mouse first goes over a widget. Please note that this participates in event propagation of children! Use [MouseEnterEvent] instead if you are only interested in a specific element's whole bounding box instead of the top-most element in any particular location.

	[MouseOutEvent] is sent when the mouse exits a target. Please note that this participates in event propagation of children! Use [MouseLeaveEvent] instead if you are only interested in a specific element's whole bounding box instead of the top-most element in any particular location.

	[MouseEnterEvent] is sent when the mouse enters the bounding box of a widget.

	[MouseLeaveEvent] is sent when the mouse leaves the bounding box of a widget.

	You can construct these yourself, but generally the system will send them to you and there's little need to emit your own.

	Rationale:

		If you only want to do drag, mousedown/up works just fine being consistently sent.

		If you want click, that event does what you expect (if the user mouse downs then moves the mouse off the widget before going up, no click event happens - a click is only down and back up on the same thing).

		If you want double click and listen to that specifically, it also just works, and if you only cared about clicks, odds are the double click should do the same thing as a single click anyway - the double was prolly accidental - so only sending the event once is prolly what user intended.

	History:
		Added May 2, 2021. Previously, it was only seen as the base [Event] class on event listeners. See the member [EventString] to see what the associated string is with these elements.
+/
final class MouseUpEvent : MouseEventBase {
	enum EventString = "mouseup"; ///
	this(Widget target) { super(EventString, target); }
}
/// ditto
final class MouseDownEvent : MouseEventBase {
	enum EventString = "mousedown"; ///
	this(Widget target) { super(EventString, target); }
}
/// ditto
final class MouseMoveEvent : MouseEventBase {
	enum EventString = "mousemove"; ///
	this(Widget target) { super(EventString, target); }
}
/// ditto
final class ClickEvent : MouseEventBase {
	enum EventString = "click"; ///
	this(Widget target) { super(EventString, target); }
}
/// ditto
final class DoubleClickEvent : MouseEventBase {
	enum EventString = "dblclick"; ///
	this(Widget target) { super(EventString, target); }
}
/// ditto
final class MouseOverEvent : Event {
	enum EventString = "mouseover"; ///
	this(Widget target) { super(EventString, target); }
}
/// ditto
final class MouseOutEvent : Event {
	enum EventString = "mouseout"; ///
	this(Widget target) { super(EventString, target); }
}
/// ditto
final class MouseEnterEvent : Event {
	enum EventString = "mouseenter"; ///
	this(Widget target) { super(EventString, target); }

	override bool propagates() const { return false; }
}
/// ditto
final class MouseLeaveEvent : Event {
	enum EventString = "mouseleave"; ///
	this(Widget target) { super(EventString, target); }

	override bool propagates() const { return false; }
}

private bool isAParentOf(Widget a, Widget b) {
	if(a is null || b is null)
		return false;

	while(b !is null) {
		if(a is b)
			return true;
		b = b.parent;
	}

	return false;
}

private struct WidgetAtPointResponse {
	Widget widget;

	// x, y relative to the widget in the response.
	int x;
	int y;
}

private WidgetAtPointResponse widgetAtPoint(Widget starting, int x, int y) {
	assert(starting !is null);

	starting.addScrollPosition(x, y);

	auto child = starting.getChildAtPosition(x, y);
	while(child) {
		if(child.hidden)
			continue;
		starting = child;
		x -= child.x;
		y -= child.y;
		auto r = starting.widgetAtPoint(x, y);//starting.getChildAtPosition(x, y);
		child = r.widget;
		if(child is starting)
			break;
	}
	return WidgetAtPointResponse(starting, x, y);
}

version(win32_widgets) {
private:
	import core.sys.windows.commctrl;

	pragma(lib, "comctl32");
	shared static this() {
		// http://msdn.microsoft.com/en-us/library/windows/desktop/bb775507(v=vs.85).aspx
		INITCOMMONCONTROLSEX ic;
		ic.dwSize = cast(DWORD) ic.sizeof;
		ic.dwICC = ICC_UPDOWN_CLASS | ICC_WIN95_CLASSES | ICC_BAR_CLASSES | ICC_PROGRESS_CLASS | ICC_COOL_CLASSES | ICC_STANDARD_CLASSES | ICC_USEREX_CLASSES;
		if(!InitCommonControlsEx(&ic)) {
			//writeln("ICC failed");
		}
	}


	// everything from here is just win32 headers copy pasta
private:
extern(Windows):

	alias HANDLE HMENU;
	HMENU CreateMenu();
	bool SetMenu(HWND, HMENU);
	HMENU CreatePopupMenu();
	enum MF_POPUP = 0x10;
	enum MF_STRING = 0;


	BOOL InitCommonControlsEx(const INITCOMMONCONTROLSEX*);
	struct INITCOMMONCONTROLSEX {
		DWORD dwSize;
		DWORD dwICC;
	}
	enum HINST_COMMCTRL = cast(HINSTANCE) (-1);
enum {
        IDB_STD_SMALL_COLOR,
        IDB_STD_LARGE_COLOR,
        IDB_VIEW_SMALL_COLOR = 4,
        IDB_VIEW_LARGE_COLOR = 5
}
enum {
        STD_CUT,
        STD_COPY,
        STD_PASTE,
        STD_UNDO,
        STD_REDOW,
        STD_DELETE,
        STD_FILENEW,
        STD_FILEOPEN,
        STD_FILESAVE,
        STD_PRINTPRE,
        STD_PROPERTIES,
        STD_HELP,
        STD_FIND,
        STD_REPLACE,
        STD_PRINT // = 14
}

alias HANDLE HIMAGELIST;
	HIMAGELIST ImageList_Create(int, int, UINT, int, int);
	int ImageList_Add(HIMAGELIST, HBITMAP, HBITMAP);
        BOOL ImageList_Destroy(HIMAGELIST);

uint MAKELONG(ushort a, ushort b) {
        return cast(uint) ((b << 16) | a);
}


struct TBBUTTON {
	int   iBitmap;
	int   idCommand;
	BYTE  fsState;
	BYTE  fsStyle;
	version(Win64)
	BYTE[6] bReserved;
	else
	BYTE[2]  bReserved;
	DWORD dwData;
	INT_PTR   iString;
}

	enum {
		TB_ADDBUTTONSA   = WM_USER + 20,
		TB_INSERTBUTTONA = WM_USER + 21,
		TB_GETIDEALSIZE = WM_USER + 99,
	}

struct SIZE {
	LONG cx;
	LONG cy;
}


enum {
	TBSTATE_CHECKED       = 1,
	TBSTATE_PRESSED       = 2,
	TBSTATE_ENABLED       = 4,
	TBSTATE_HIDDEN        = 8,
	TBSTATE_INDETERMINATE = 16,
	TBSTATE_WRAP          = 32
}



enum {
	ILC_COLOR    = 0,
	ILC_COLOR4   = 4,
	ILC_COLOR8   = 8,
	ILC_COLOR16  = 16,
	ILC_COLOR24  = 24,
	ILC_COLOR32  = 32,
	ILC_COLORDDB = 254,
	ILC_MASK     = 1,
	ILC_PALETTE  = 2048
}


alias TBBUTTON*       PTBBUTTON, LPTBBUTTON;


enum {
	TB_ENABLEBUTTON          = WM_USER + 1,
	TB_CHECKBUTTON,
	TB_PRESSBUTTON,
	TB_HIDEBUTTON,
	TB_INDETERMINATE, //     = WM_USER + 5,
	TB_ISBUTTONENABLED       = WM_USER + 9,
	TB_ISBUTTONCHECKED,
	TB_ISBUTTONPRESSED,
	TB_ISBUTTONHIDDEN,
	TB_ISBUTTONINDETERMINATE, // = WM_USER + 13,
	TB_SETSTATE              = WM_USER + 17,
	TB_GETSTATE              = WM_USER + 18,
	TB_ADDBITMAP             = WM_USER + 19,
	TB_DELETEBUTTON          = WM_USER + 22,
	TB_GETBUTTON,
	TB_BUTTONCOUNT,
	TB_COMMANDTOINDEX,
	TB_SAVERESTOREA,
	TB_CUSTOMIZE,
	TB_ADDSTRINGA,
	TB_GETITEMRECT,
	TB_BUTTONSTRUCTSIZE,
	TB_SETBUTTONSIZE,
	TB_SETBITMAPSIZE,
	TB_AUTOSIZE, //          = WM_USER + 33,
	TB_GETTOOLTIPS           = WM_USER + 35,
	TB_SETTOOLTIPS           = WM_USER + 36,
	TB_SETPARENT             = WM_USER + 37,
	TB_SETROWS               = WM_USER + 39,
	TB_GETROWS,
	TB_GETBITMAPFLAGS,
	TB_SETCMDID,
	TB_CHANGEBITMAP,
	TB_GETBITMAP,
	TB_GETBUTTONTEXTA,
	TB_REPLACEBITMAP, //     = WM_USER + 46,
	TB_GETBUTTONSIZE         = WM_USER + 58,
	TB_SETBUTTONWIDTH        = WM_USER + 59,
	TB_GETBUTTONTEXTW        = WM_USER + 75,
	TB_SAVERESTOREW          = WM_USER + 76,
	TB_ADDSTRINGW            = WM_USER + 77,
}

extern(Windows)
BOOL EnumChildWindows(HWND, WNDENUMPROC, LPARAM);

alias extern(Windows) BOOL function (HWND, LPARAM) WNDENUMPROC;


	enum {
		TB_SETINDENT = WM_USER + 47,
		TB_SETIMAGELIST,
		TB_GETIMAGELIST,
		TB_LOADIMAGES,
		TB_GETRECT,
		TB_SETHOTIMAGELIST,
		TB_GETHOTIMAGELIST,
		TB_SETDISABLEDIMAGELIST,
		TB_GETDISABLEDIMAGELIST,
		TB_SETSTYLE,
		TB_GETSTYLE,
		//TB_GETBUTTONSIZE,
		//TB_SETBUTTONWIDTH,
		TB_SETMAXTEXTROWS,
		TB_GETTEXTROWS // = WM_USER + 61
	}

enum {
	CCM_FIRST            = 0x2000,
	CCM_LAST             = CCM_FIRST + 0x200,
	CCM_SETBKCOLOR       = 8193,
	CCM_SETCOLORSCHEME   = 8194,
	CCM_GETCOLORSCHEME   = 8195,
	CCM_GETDROPTARGET    = 8196,
	CCM_SETUNICODEFORMAT = 8197,
	CCM_GETUNICODEFORMAT = 8198,
	CCM_SETVERSION       = 0x2007,
	CCM_GETVERSION       = 0x2008,
	CCM_SETNOTIFYWINDOW  = 0x2009
}


enum {
	PBM_SETRANGE     = WM_USER + 1,
	PBM_SETPOS,
	PBM_DELTAPOS,
	PBM_SETSTEP,
	PBM_STEPIT,   // = WM_USER + 5
	PBM_SETRANGE32   = 1030,
	PBM_GETRANGE,
	PBM_GETPOS,
	PBM_SETBARCOLOR, // = 1033
	PBM_SETBKCOLOR   = CCM_SETBKCOLOR
}

enum {
	PBS_SMOOTH   = 1,
	PBS_VERTICAL = 4
}

enum {
        ICC_LISTVIEW_CLASSES = 1,
        ICC_TREEVIEW_CLASSES = 2,
        ICC_BAR_CLASSES      = 4,
        ICC_TAB_CLASSES      = 8,
        ICC_UPDOWN_CLASS     = 16,
        ICC_PROGRESS_CLASS   = 32,
        ICC_HOTKEY_CLASS     = 64,
        ICC_ANIMATE_CLASS    = 128,
        ICC_WIN95_CLASSES    = 255,
        ICC_DATE_CLASSES     = 256,
        ICC_USEREX_CLASSES   = 512,
        ICC_COOL_CLASSES     = 1024,
	ICC_STANDARD_CLASSES = 0x00004000,
}

	enum WM_USER = 1024;
}

version(win32_widgets)
	pragma(lib, "comdlg32");


///
enum GenericIcons : ushort {
	None, ///
	// these happen to match the win32 std icons numerically if you just subtract one from the value
	Cut, ///
	Copy, ///
	Paste, ///
	Undo, ///
	Redo, ///
	Delete, ///
	New, ///
	Open, ///
	Save, ///
	PrintPreview, ///
	Properties, ///
	Help, ///
	Find, ///
	Replace, ///
	Print, ///
}

enum FileDialogType {
	Automatic,
	Open,
	Save
}

/++
	The default string [FileName] refers to to store the last file referenced. You can use this if you like, or provide a different variable to `FileName` in your function.
+/
string previousFileReferenced;

/++
	Used in automatic menu functions to indicate that the user should be able to browse for a file.

	Params:
		storage = an alias to a `static string` variable that stores the last file referenced. It will
		use this to pre-fill the dialog with a suggestion.

		Please note that it MUST be `static` or you will get compile errors.

		filters = the filters param to [getFileName]

		type = the type if dialog to show. If `FileDialogType.Automatic`, it the driver code will
		guess based on the function name. If it has the word "Save" or "Export" in it, it will show
		a save dialog box. Otherwise, it will show an open dialog box.
+/
struct FileName(alias storage = previousFileReferenced, string[] filters = null, FileDialogType type = FileDialogType.Automatic) {
	string name;
	alias name this;

	@implicit this(string name) {
		this.name = name;
	}
}

/++
	Gets a file name for an open or save operation, calling your `onOK` function when the user has selected one. This function may or may not block depending on the operating system, you MUST assume it will complete asynchronously.

	History:
		onCancel was added November 6, 2021.

		The dialog itself on Linux was modified on December 2, 2021 to include
		a directory picker in addition to the command line completion view.

		The `initialDirectory` argument was added November 9, 2022 (dub v10.10)

		The `owner` argument was added September 29, 2024. The overloads without this argument are likely to be deprecated in the next major version.
	Future_directions:
		I want to add some kind of custom preview and maybe thumbnail thing in the future,
		at least on Linux, maybe on Windows too.
+/
void getOpenFileName(
	Window owner,
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null,
	void delegate() onCancel = null,
	string initialDirectory = null,
)
{
	return getFileName(owner, true, onOK, prefilledName, filters, onCancel, initialDirectory);
}

/// ditto
void getSaveFileName(
	Window owner,
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null,
	void delegate() onCancel = null,
	string initialDirectory = null,
)
{
	return getFileName(owner, false, onOK, prefilledName, filters, onCancel, initialDirectory);
}

// deprecated("Pass an explicit owner window as the first argument, even if `null`. You can usually pass the `parentWindow` member of the widget that prompted this interaction.")
/// ditto
void getOpenFileName(
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null,
	void delegate() onCancel = null,
	string initialDirectory = null,
)
{
	return getFileName(null, true, onOK, prefilledName, filters, onCancel, initialDirectory);
}

/// ditto
void getSaveFileName(
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null,
	void delegate() onCancel = null,
	string initialDirectory = null,
)
{
	return getFileName(null, false, onOK, prefilledName, filters, onCancel, initialDirectory);
}

/++
	It is possible to override or customize the file dialog in some cases. These members provide those hooks: you do `fileDialogDelegate = new YourSubclassOf_FileDialogDelegate;` and you can do your own thing.

	This is a customization hook and you should not call methods on this class directly. Use the public functions [getOpenFileName] and [getSaveFileName], or make an automatic dialog with [FileName] instead.

	History:
		Added January 1, 2025
+/
class FileDialogDelegate {

	/++

	+/
	static abstract class PreviewWidget : Widget {
		/// Call this from your subclass' constructor
		this(Widget parent) {
			super(parent);
		}

		/// Load the file given to you and show its preview inside the widget here
		abstract void previewFile(string filename);
	}

	/++
		Override this to add preview capabilities to the dialog for certain files.
	+/
	protected PreviewWidget makePreviewWidget(Widget parent) {
		return null;
	}

	/++
		Override this to change the dialog entirely.

		This function IS allowed to block, but is NOT required to.
	+/
	protected void getFileName(
		Window owner,
		bool openOrSave, // true if open, false if save
		void delegate(string) onOK,
		string prefilledName,
		string[] filters, // format here is like ["Text files\0*.txt;*.text", "Image files\0*.png;*.jpg"]
		void delegate() onCancel,
		string initialDirectory,
	)
	{

		version(win32_widgets) {
			import core.sys.windows.commdlg;
		/*
		Ofn.lStructSize = sizeof(OPENFILENAME);
		Ofn.hwndOwner = hWnd;
		Ofn.lpstrFilter = szFilter;
		Ofn.lpstrFile= szFile;
		Ofn.nMaxFile = sizeof(szFile)/ sizeof(*szFile);
		Ofn.lpstrFileTitle = szFileTitle;
		Ofn.nMaxFileTitle = sizeof(szFileTitle);
		Ofn.lpstrInitialDir = (LPSTR)NULL;
		Ofn.Flags = OFN_SHOWHELP | OFN_OVERWRITEPROMPT;
		Ofn.lpstrTitle = szTitle;
		 */


			wchar[1024] file = 0;
			wchar[1024] filterBuffer = 0;
			makeWindowsString(prefilledName, file[]);
			OPENFILENAME ofn;
			ofn.lStructSize = ofn.sizeof;
			ofn.hwndOwner = owner is null ? null : owner.win.hwnd;
			if(filters.length) {
				string filter;
				foreach(i, f; filters) {
					filter ~= f;
					filter ~= "\0";
				}
				filter ~= "\0";
				ofn.lpstrFilter = makeWindowsString(filter, filterBuffer[], 0 /* already terminated */).ptr;
			}
			ofn.lpstrFile = file.ptr;
			ofn.nMaxFile = file.length;

			wchar[1024] initialDir = 0;
			if(initialDirectory !is null) {
				makeWindowsString(initialDirectory, initialDir[]);
				ofn.lpstrInitialDir = file.ptr;
			}

			if(openOrSave ? GetOpenFileName(&ofn) : GetSaveFileName(&ofn))
			{
				string okString = makeUtf8StringFromWindowsString(ofn.lpstrFile);
				if(okString.length && okString[$-1] == '\0')
					okString = okString[0..$-1];
				onOK(okString);
			} else {
				if(onCancel)
					onCancel();
			}
		} else version(custom_widgets) {
			filters ~= ["All Files\0*.*"];
			auto picker = new FilePicker(openOrSave, prefilledName, filters, initialDirectory, owner);
			picker.onOK = onOK;
			picker.onCancel = onCancel;
			picker.show();
		}
	}

}

/// ditto
FileDialogDelegate fileDialogDelegate() {
	if(fileDialogDelegate_ is null)
		fileDialogDelegate_ = new FileDialogDelegate();
	return fileDialogDelegate_;
}

/// ditto
void fileDialogDelegate(FileDialogDelegate replacement) {
	fileDialogDelegate_ = replacement;
}

private FileDialogDelegate fileDialogDelegate_;

struct FileNameFilter {
	string description;
	string[] globPatterns;

	string toString() {
		string ret;
		ret ~= description;
		ret ~= " (";
		foreach(idx, pattern; globPatterns) {
			if(idx)
				ret ~= "; ";
			ret ~= pattern;
		}
		ret ~= ")";

		return ret;
	}

	static FileNameFilter fromString(string s) {
		size_t end = s.length;
		size_t start = 0;
		foreach_reverse(idx, ch; s) {
			if(ch == ')' && end == s.length)
				end = idx;
			else if(ch == '(' && end != s.length) {
				start = idx + 1;
				break;
			}
		}

		FileNameFilter fnf;
		fnf.description = s[0 .. start ? start - 1 : 0];
		size_t globStart = 0;
		s = s[start .. end];
		foreach(idx, ch; s)
			if(ch == ';') {
				auto ptn = stripInternal(s[globStart .. idx]);
				if(ptn.length)
					fnf.globPatterns ~= ptn;
				globStart = idx + 1;

			}
		auto ptn = stripInternal(s[globStart .. $]);
		if(ptn.length)
			fnf.globPatterns ~= ptn;
		return fnf;
	}
}

struct FileNameFilterSet {
	FileNameFilter[] filters;

	static FileNameFilterSet fromWindowsFileNameFilterDescription(string[] filters) {
		FileNameFilter[] ret;

		foreach(filter; filters) {
			FileNameFilter fnf;
			size_t filterStartPoint;
			foreach(idx, ch; filter) {
				if(ch == 0) {
					fnf.description = filter[0 .. idx];
					filterStartPoint = idx + 1;
				} else if(filterStartPoint && ch == ';') {
					fnf.globPatterns ~= filter[filterStartPoint .. idx];
					filterStartPoint = idx + 1;
				}
			}
			fnf.globPatterns ~= filter[filterStartPoint .. $];

			ret ~= fnf;
		}

		return FileNameFilterSet(ret);
	}
}

void getFileName(
	Window owner,
	bool openOrSave,
	void delegate(string) onOK,
	string prefilledName = null,
	string[] filters = null, // format here is like ["Text files\0*.txt;*.text", "Image files\0*.png;*.jpg"]
	void delegate() onCancel = null,
	string initialDirectory = null,
)
{
	return fileDialogDelegate().getFileName(owner, openOrSave, onOK, prefilledName, filters, onCancel, initialDirectory);
}

version(custom_widgets)
private
class FilePicker : Dialog {
	void delegate(string) onOK;
	void delegate() onCancel;
	LabeledLineEdit lineEdit;
	bool isOpenDialogInsteadOfSave;

	static struct HistoryItem {
		string cwd;
		FileNameFilter filters;
	}
	HistoryItem[] historyStack;
	size_t historyStackPosition;

	void back() {
		if(historyStackPosition) {
			historyStackPosition--;
			currentDirectory = historyStack[historyStackPosition].cwd;
			currentFilter = historyStack[historyStackPosition].filters;
			filesOfType.content = currentFilter.toString();
			loadFiles(historyStack[historyStackPosition].cwd, historyStack[historyStackPosition].filters, true);
			lineEdit.focus();
		}
	}

	void forward() {
		if(historyStackPosition + 1 < historyStack.length) {
			historyStackPosition++;
			currentDirectory = historyStack[historyStackPosition].cwd;
			currentFilter = historyStack[historyStackPosition].filters;
			filesOfType.content = currentFilter.toString();
			loadFiles(historyStack[historyStackPosition].cwd, historyStack[historyStackPosition].filters, true);
			lineEdit.focus();
		}
	}

	void up() {
		currentDirectory = currentDirectory ~ "..";
		loadFiles(currentDirectory, currentFilter);
		lineEdit.focus();
	}

	void refresh() {
		loadFiles(currentDirectory, currentFilter);
		lineEdit.focus();
	}

	// returns common prefix
	static struct CommonPrefixInfo {
		string commonPrefix;
		int fileCount;
		string exactMatch;
	}
	CommonPrefixInfo loadFiles(string cwd, FileNameFilter filters, bool comingFromHistory = false) {

		if(!comingFromHistory) {
			if(historyStack.length) {
				historyStack = historyStack[0 .. historyStackPosition + 1];
				historyStack.assumeSafeAppend();
			}
			historyStack ~= HistoryItem(cwd, filters);
			historyStackPosition = historyStack.length - 1;
		}

		string[] files;
		string[] dirs;

		dirs ~= "$HOME";
		dirs ~= "$PWD";

		string commonPrefix;
		int commonPrefixCount;
		string exactMatch;

		bool matchesFilter(string name) {
			foreach(filter; filters.globPatterns) {
			if(
				filter.length <= 1 ||
				filter == "*.*" || // we always treat *.* the same as *, but it is a bit different than .*
				(filter[0] == '*' && name.endsWith(filter[1 .. $])) ||
				(filter[$-1] == '*' && name.startsWith(filter[0 .. $ - 1]))
			)
			{
				if(name.length > 1 && name[0] == '.')
					if(filter.length == 0 || filter[0] != '.')
						return false;

				return true;
			}
			}

			return false;
		}

		void considerCommonPrefix(string name, bool prefiltered) {
			if(!prefiltered && !matchesFilter(name))
				return;

			if(commonPrefix is null) {
				commonPrefix = name;
				commonPrefixCount = 1;
				exactMatch = commonPrefix;
			} else {
				foreach(idx, char i; name) {
					if(idx >= commonPrefix.length || i != commonPrefix[idx]) {
						commonPrefix = commonPrefix[0 .. idx];
						commonPrefixCount ++;
						exactMatch = null;
						break;
					}
				}
			}
		}

		bool applyFilterToDirectories = true;
		bool showDotFiles = false;
		foreach(filter; filters.globPatterns) {
			if(filter == ".*")
				showDotFiles = true;
			else foreach(ch; filter)
				if(ch == '.') {
					// a filter like *.exe should not apply to the directory
					applyFilterToDirectories = false;
					break;
				}
		}

		try
		getFiles(cwd, (string name, bool isDirectory) {
			if(name == ".")
				return; // skip this as unnecessary
			if(isDirectory) {
				if(applyFilterToDirectories) {
					if(matchesFilter(name)) {
						dirs ~= name;
						considerCommonPrefix(name, false);
					}
				} else if(name != ".." && name.length > 1 && name[0] == '.') {
					if(showDotFiles) {
						dirs ~= name;
						considerCommonPrefix(name, false);
					}
				} else {
					dirs ~= name;
					considerCommonPrefix(name, false);
				}
			} else {
				if(matchesFilter(name)) {
					files ~= name;

					//if(filter.length > 0 && filter[$-1] == '*') {
						considerCommonPrefix(name, true);
					//}
				}
			}
		});
		catch(ArsdExceptionBase e) {
			messageBox("Unable to read requested directory");
			// FIXME: give them a chance to create it? or at least go back?
			/+
			comingFromHistory = true;
			back();
			return null;
			+/
		}

		extern(C) static int comparator(scope const void* a, scope const void* b) {
			auto sa = *cast(string*) a;
			auto sb = *cast(string*) b;

			/+
				Goal here:

				Dot first. This puts `foo.d` before `foo2.d`
				Then numbers , natural sort order (so 9 comes before 10) for positive numbers
				Then letters, in order Aa, Bb, Cc
				Then other symbols in ascii order
			+/
			static int nextPiece(ref string whole) {
				if(whole.length == 0)
					return -1;

				enum specialZoneSize = 1;

				char current = whole[0];
				if(current >= '0' && current <= '9') {
					int accumulator;
					do {
						whole = whole[1 .. $];
						accumulator *= 10;
						accumulator += current - '0';
						current = whole.length ? whole[0] : 0;
					} while (current >= '0' && current <= '9');

					return accumulator + specialZoneSize + cast(int) char.max; // leave room for symbols
				} else {
					whole = whole[1 .. $];

					if(current == '.')
						return 0; // the special case to put it before numbers

					// anything above should be < specialZoneSize

					int letterZoneSize = 26 * 2;
					int base = int.max - letterZoneSize - char.max; // leaves space at end for symbols too if we want them after chars

					if(current >= 'A' && current <= 'Z')
						return base + (current - 'A') * 2;
					if(current >= 'a' && current <= 'z')
						return base + (current - 'a') * 2 + 1;
					// return base + letterZoneSize + current; // would put symbols after numbers and letters
					return specialZoneSize + current; // puts symbols before numbers and letters, but after the special zone
				}
			}

			while(sa.length || sb.length) {
				auto pa = nextPiece(sa);
				auto pb = nextPiece(sb);

				auto diff = pa - pb;
				if(diff)
					return diff;
			}

			return 0;
		}

		nonPhobosSort(files, &comparator);
		nonPhobosSort(dirs, &comparator);

		listWidget.clear();
		dirWidget.clear();
		foreach(name; dirs)
			dirWidget.addOption(name);
		foreach(name; files)
			listWidget.addOption(name);

		return CommonPrefixInfo(commonPrefix, commonPrefixCount, exactMatch);
	}

	ListWidget listWidget;
	ListWidget dirWidget;

	FreeEntrySelection filesOfType;
	LineEdit directoryHolder;

	string currentDirectory_;
	FileNameFilter currentNonTabFilter;
	FileNameFilter currentFilter;
	FileNameFilterSet filterOptions;

	void currentDirectory(string s) {
		currentDirectory_ = FilePath(s).makeAbsolute(getCurrentWorkingDirectory()).toString();
		directoryHolder.content = currentDirectory_;
	}
	string currentDirectory() {
		return currentDirectory_;
	}

	private string getUserHomeDir() {
		import core.stdc.stdlib;
		version(Windows)
			return (stringz(getenv("HOMEDRIVE")).borrow ~ stringz(getenv("HOMEPATH")).borrow).idup;
		else
			return (stringz(getenv("HOME")).borrow).idup;
	}

	private string expandTilde(string s) {
		// FIXME: cannot look up other user dirs
		if(s.length == 1 && s == "~")
			return getUserHomeDir();
		if(s.length > 1 && s[0] == '~' && s[1] == '/')
			return getUserHomeDir() ~ s[1 .. $];
		return s;
	}

	// FIXME: allow many files to be picked too sometimes

	//string[] filters = null, // format here is like ["Text files\0*.txt;*.text", "Image files\0*.png;*.jpg"]
	this(bool isOpenDialogInsteadOfSave, string prefilledName, string[] filtersInWindowsFormat, string initialDirectory, Window owner = null) {
		this.filterOptions = FileNameFilterSet.fromWindowsFileNameFilterDescription(filtersInWindowsFormat);
		this.isOpenDialogInsteadOfSave = isOpenDialogInsteadOfSave;
		super(owner, 500, 400, "Choose File..."); // owner);

		{
			auto navbar = new HorizontalLayout(24, this);
			auto backButton = new ToolButton(new Action("<", 0, &this.back), navbar);
			auto forwardButton = new ToolButton(new Action(">", 0, &this.forward), navbar);
			auto upButton = new ToolButton(new Action("^", 0, &this.up), navbar); // hmm with .. in the dir list we don't really need an up button

			directoryHolder = new LineEdit(navbar);

			directoryHolder.addEventListener(delegate(scope KeyDownEvent kde) {
				if(kde.key == Key.Enter || kde.key == Key.PadEnter) {
					kde.stopPropagation();

					currentDirectory = directoryHolder.content;
					loadFiles(currentDirectory, currentFilter);

					lineEdit.focus();
				}
			});

			auto refreshButton = new ToolButton(new Action("R", 0, &this.refresh), navbar); // can live without refresh since you can cancel and reopen but still nice. it should be automatic when it can maybe.

			/+
			auto newDirectoryButton = new ToolButton(new Action("N"), navbar);

			// FIXME: make sure putting `.` in the dir filter goes back to the CWD
			// and that ~ goes back to the home dir
			// and blanking it goes back to the suggested dir

			auto homeButton = new ToolButton(new Action("H"), navbar);
			auto cwdButton = new ToolButton(new Action("."), navbar);
			auto suggestedDirectoryButton = new ToolButton(new Action("*"), navbar);
			+/

			filesOfType = new class FreeEntrySelection {
				this() {
					string[] opt;
					foreach(option; filterOptions.filters)
						opt ~=  option.toString;
					super(opt, navbar);
				}
				override int flexBasisWidth() {
					return scaleWithDpi(150);
				}
				override int widthStretchiness() {
					return 1;//super.widthStretchiness() / 2;
				}
			};
			filesOfType.setSelection(0);
			currentFilter = filterOptions.filters[0];
			currentNonTabFilter = currentFilter;
		}

		{
			auto mainGrid = new GridLayout(4, 1, this);

			dirWidget = new ListWidget(mainGrid);
			listWidget = new ListWidget(mainGrid);
			listWidget.tabStop = false;
			dirWidget.tabStop = false;

			FileDialogDelegate.PreviewWidget previewWidget = fileDialogDelegate.makePreviewWidget(mainGrid);

			mainGrid.setChildPosition(dirWidget, 0, 0, 1, 1);
			mainGrid.setChildPosition(listWidget, 1, 0, previewWidget !is null ? 2 : 3, 1);
			if(previewWidget)
				mainGrid.setChildPosition(previewWidget, 2, 0, 1, 1);

			// double click events normally trigger something else but
			// here user might be clicking kinda fast and we'd rather just
			// keep it
			dirWidget.addEventListener((scope DoubleClickEvent dev) {
				auto ce = new ChangeEvent!void(dirWidget, () {});
				ce.dispatch();
				lineEdit.focus();
			});

			dirWidget.addEventListener((scope ChangeEvent!void sce) {
				string v;
				foreach(o; dirWidget.options)
					if(o.selected) {
						v = o.label;
						break;
					}
				if(v.length) {
					if(v == "$HOME")
						currentDirectory = getUserHomeDir();
					else if(v == "$PWD")
						currentDirectory = ".";
					else
						currentDirectory = currentDirectory ~ "/" ~ v;
					loadFiles(currentDirectory, currentFilter);
				}

				dirWidget.focusOn = -1;
				lineEdit.focus();
			});

			// double click here, on the other hand, selects the file
			// and moves on
			listWidget.addEventListener((scope DoubleClickEvent dev) {
				OK();
			});
		}

		lineEdit = new LabeledLineEdit("File name:", TextAlignment.Right, this);
		lineEdit.focus();
		lineEdit.addEventListener(delegate(CharEvent event) {
			if(event.character == '\t' || event.character == '\n')
				event.preventDefault();
		});

		listWidget.addEventListener(EventType.change, () {
			foreach(o; listWidget.options)
				if(o.selected)
					lineEdit.content = o.label;
		});

		currentDirectory = initialDirectory is null ? "." : initialDirectory;

		auto prefilledPath = FilePath(expandTilde(prefilledName)).makeAbsolute(FilePath(currentDirectory));
		currentDirectory = prefilledPath.directoryName;
		prefilledName = prefilledPath.filename;
		loadFiles(currentDirectory, currentFilter);

		filesOfType.addEventListener(delegate (FreeEntrySelection.SelectionChangedEvent ce) {
			currentFilter = FileNameFilter.fromString(ce.stringValue);
			currentNonTabFilter = currentFilter;
			loadFiles(currentDirectory, currentFilter);
			// lineEdit.focus(); // this causes a recursive crash.....
		});

		filesOfType.addEventListener(delegate(KeyDownEvent event) {
			if(event.key == Key.Enter) {
				currentFilter = FileNameFilter.fromString(filesOfType.content);
				currentNonTabFilter = currentFilter;
				loadFiles(currentDirectory, currentFilter);
				event.stopPropagation();
				// FIXME: refocus on the line edit
			}
		});

		lineEdit.addEventListener((KeyDownEvent event) {
			if(event.key == Key.Tab && !event.ctrlKey && !event.shiftKey) {

				auto path = FilePath(expandTilde(lineEdit.content)).makeAbsolute(FilePath(currentDirectory));
				currentDirectory = path.directoryName;
				auto current = path.filename;

				auto newFilter = current;
				if(current.length && current[0] != '*' && current[$-1] != '*')
					newFilter ~= "*";
				else if(newFilter.length == 0)
					newFilter = "*";

				auto newFilterObj = FileNameFilter("Custom filter", [newFilter]);

				CommonPrefixInfo commonPrefix = loadFiles(currentDirectory, newFilterObj);
				if(commonPrefix.fileCount == 1) {
					// exactly one file, let's see what it is
					auto specificFile = FilePath(commonPrefix.exactMatch).makeAbsolute(FilePath(currentDirectory));
					if(getFileType(specificFile.toString) == FileType.dir) {
						// a directory means we should change to it and keep the old filter
						currentDirectory = specificFile.toString();
						lineEdit.content = specificFile.toString() ~ "/";
						loadFiles(currentDirectory, currentFilter);
					} else {
						// any other file should be selected in the list
						currentDirectory = specificFile.directoryName;
						current = specificFile.filename;
						lineEdit.content = current;
						loadFiles(currentDirectory, currentFilter);
					}
				} else if(commonPrefix.fileCount > 1) {
					currentFilter = newFilterObj;
					filesOfType.content = currentFilter.toString();
					lineEdit.content = commonPrefix.commonPrefix;
				} else {
					// if there were no files, we don't really want to change the filter..
					//sdpyPrintDebugString("no files");
				}

				// FIXME: if that is a directory, add the slash? or even go inside?

				event.preventDefault();
			}
			else if(event.key == Key.Left && event.altKey) {
				this.back();
				event.preventDefault();
			}
			else if(event.key == Key.Right && event.altKey) {
				this.forward();
				event.preventDefault();
			}
		});


		lineEdit.content = prefilledName;

		auto hl = new HorizontalLayout(60, this);
		auto cancelButton = new Button("Cancel", hl);
		auto okButton = new Button(isOpenDialogInsteadOfSave ? "Open" : "Save"/*"OK"*/, hl);

		cancelButton.addEventListener(EventType.triggered, &Cancel);
		okButton.addEventListener(EventType.triggered, &OK);

		this.addEventListener((KeyDownEvent event) {
			if(event.key == Key.Enter || event.key == Key.PadEnter) {
				event.preventDefault();
				OK();
			}
			else if(event.key == Key.Escape)
				Cancel();
			else if(event.key == Key.F5)
				refresh();
			else if(event.key == Key.Up && event.altKey)
				up(); // ditto
			else if(event.key == Key.Left && event.altKey)
				back(); // FIXME: it sends the key to the line edit too
			else if(event.key == Key.Right && event.altKey)
				forward(); // ditto
			else if(event.key == Key.Up)
				listWidget.setSelection(listWidget.getSelection() - 1);
			else if(event.key == Key.Down)
				listWidget.setSelection(listWidget.getSelection() + 1);
		});

		// FIXME: set the list view's focusOn to -1 on most interactions so it doesn't keep a thing highlighted
		// FIXME: button to create new directory
		// FIXME: show dirs in the files list too? idk.

		// FIXME: support ~ as alias for home in the input
		// FIXME: tab complete ought to be able to change+complete dir too
	}

	override void OK() {
		if(lineEdit.content.length) {
			auto c = expandTilde(lineEdit.content);

			FilePath accepted = FilePath(c).makeAbsolute(FilePath(currentDirectory));

			auto ft = getFileType(accepted.toString);

			if(ft == FileType.error && isOpenDialogInsteadOfSave) {
				// FIXME: tell the user why
				messageBox("Cannot open file: " ~ accepted.toString ~ "\nTry another or cancel.");
				lineEdit.focus();
				return;

			}

			// FIXME: symlinks to dirs should prolly also get this behavior
			if(ft == FileType.dir) {
				currentDirectory = accepted.toString;

				currentFilter = currentNonTabFilter;
				filesOfType.content = currentFilter.toString();

				loadFiles(currentDirectory, currentFilter);
				lineEdit.content = "";

				lineEdit.focus();

				return;
			}

			if(onOK)
				onOK(accepted.toString);
		}
		close();
	}

	override void Cancel() {
		if(onCancel)
			onCancel();
		close();
	}
}

private enum FileType {
	error,
	dir,
	other
}

private FileType getFileType(string name) {
	version(Windows) {
		auto ws = WCharzBuffer(name);
		auto ret = GetFileAttributesW(ws.ptr);
		if(ret == INVALID_FILE_ATTRIBUTES)
			return FileType.error;
		return ((ret & FILE_ATTRIBUTE_DIRECTORY) != 0) ? FileType.dir : FileType.other;
	} else version(Posix) {
		import core.sys.posix.sys.stat;
		stat_t buf;
		auto ret = stat((name ~ '\0').ptr, &buf);
		if(ret == -1)
			return FileType.error;
		return ((buf.st_mode & S_IFMT) == S_IFDIR) ? FileType.dir : FileType.other;
	} else assert(0, "Not implemented");
}

/*
http://msdn.microsoft.com/en-us/library/windows/desktop/bb775947%28v=vs.85%29.aspx#check_boxes
http://msdn.microsoft.com/en-us/library/windows/desktop/ms633574%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb775943%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb775951%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms632680%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/ms644996%28v=vs.85%29.aspx#message_box
http://www.sbin.org/doc/Xlib/chapt_03.html

http://msdn.microsoft.com/en-us/library/windows/desktop/bb760433%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb760446%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb760443%28v=vs.85%29.aspx
http://msdn.microsoft.com/en-us/library/windows/desktop/bb760476%28v=vs.85%29.aspx
*/


// These are all for setMenuAndToolbarFromAnnotatedCode
/// This item in the menu will be preceded by a separator line
/// Group: generating_from_code
struct separator {}
deprecated("It was misspelled, use separator instead") alias seperator = separator;
/// Program-wide keyboard shortcut to trigger the action
/// Group: generating_from_code
struct accelerator { string keyString; } // FIXME: allow multiple aliases here
/// tells which menu the action will be on
/// Group: generating_from_code
struct menu { string name; }
/// Describes which toolbar section the action appears on
/// Group: generating_from_code
struct toolbar { string groupName; }
///
/// Group: generating_from_code
struct icon { ushort id; }
///
/// Group: generating_from_code
struct label { string label; }
///
/// Group: generating_from_code
struct hotkey { dchar ch; }
///
/// Group: generating_from_code
struct tip { string tip; }
///
/// Group: generating_from_code
enum context_menu = menu.init;
/++
	// FIXME: the options should have both a label and a value

	if label is null, it will try to just stringify value.

	if type is int or size_t and it returns a string array, we can use the index but this will implicitly not allow custom, even if allowCustom is set.
+/
/// Group: generating_from_code
Choices!T choices(T)(T[] options, bool allowCustom = false, bool allowReordering = true, bool allowDuplicates = true) {
	return Choices!T(() => options, allowCustom, allowReordering, allowDuplicates);
}
/// ditto
Choices!T choices(T)(T[] delegate() options, bool allowCustom = false, bool allowReordering = true, bool allowDuplicates = true) {
	return Choices!T(options, allowCustom, allowReordering, allowDuplicates);
}
/// ditto
struct Choices(T) {
	///
	T[] delegate() options;
	bool allowCustom = false;
	/// only relevant if attached to an array
	bool allowReordering = true;
	/// ditto
	bool allowDuplicates = true;
	/// makes no sense on a set
	bool requireAll = false;
}


/++
	Observes and allows inspection of an object via automatic gui
+/
/// Group: generating_from_code
ObjectInspectionWindow objectInspectionWindow(T)(T t) if(is(T == class)) {
	return new ObjectInspectionWindowImpl!(T)(t);
}

class ObjectInspectionWindow : Window {
	this(int a, int b, string c) {
		super(a, b, c);
	}

	abstract void readUpdatesFromObject();
}

class ObjectInspectionWindowImpl(T) : ObjectInspectionWindow {
	T t;
	this(T t) {
		this.t = t;

		super(300, 400, "ObjectInspectionWindow - " ~ T.stringof);

		foreach(memberName; __traits(derivedMembers, T)) {{
			alias member = I!(__traits(getMember, t, memberName))[0];
			alias type = typeof(member);
			static if(is(type == int)) {
				auto le = new LabeledLineEdit(memberName ~ ": ", this);
				//le.addEventListener("char", (Event ev) {
					//if((ev.character < '0' || ev.character > '9') && ev.character != '-')
						//ev.preventDefault();
				//});
				le.addEventListener(EventType.change, (Event ev) {
					__traits(getMember, t, memberName) = cast(type) stringToLong(ev.stringValue);
				});

				updateMemberDelegates[memberName] = () {
					le.content = toInternal!string(__traits(getMember, t, memberName));
				};
			}
		}}
	}

	void delegate()[string] updateMemberDelegates;

	override void readUpdatesFromObject() {
		foreach(k, v; updateMemberDelegates)
			v();
	}
}

/++
	Creates a dialog based on a data structure.

	---
	dialog(window, (YourStructure value) {
		// the user filled in the struct and clicked OK,
		// you can check the members now
	});
	---

	Params:
		initialData = the initial value to show in the dialog. It will not modify this unless
		it is a class then it might, no promises.

	History:
		The overload that lets you specify `initialData` was added on December 30, 2021 (dub v10.5)

		The overloads with `parent` were added September 29, 2024. The ones without it are likely to
		be deprecated soon.
+/
/// Group: generating_from_code
void dialog(T)(void delegate(T) onOK, void delegate() onCancel = null, string title = T.stringof) {
	dialog(null, T.init, onOK, onCancel, title);
}
/// ditto
void dialog(T)(T initialData, void delegate(T) onOK, void delegate() onCancel = null, string title = T.stringof) {
	dialog(null, T.init, onOK, onCancel, title);
}
/// ditto
void dialog(T)(Window parent, void delegate(T) onOK, void delegate() onCancel = null, string title = T.stringof) {
	dialog(parent, T.init, onOK, onCancel, title);
}
/// ditto
void dialog(T)(T initialData, Window parent, void delegate(T) onOK, void delegate() onCancel = null, string title = T.stringof) {
	dialog(parent, initialData, onOK, onCancel, title);
}
/// ditto
void dialog(T)(Window parent, T initialData, void delegate(T) onOK, void delegate() onCancel = null, string title = T.stringof) {
	auto dg = new AutomaticDialog!T(parent, initialData, onOK, onCancel, title);
	dg.show();
}

private static template I(T...) { alias I = T; }


private string beautify(string name, char space = ' ', bool allLowerCase = false) {
	if(name == "id")
		return allLowerCase ? name : "ID";

	char[160] buffer;
	int bufferIndex = 0;
	bool shouldCap = true;
	bool shouldSpace;
	bool lastWasCap;
	foreach(idx, char ch; name) {
		if(bufferIndex == buffer.length) return name; // out of space, just give up, not that important

		if((ch >= 'A' && ch <= 'Z') || ch == '_') {
			if(lastWasCap) {
				// two caps in a row, don't change. Prolly acronym.
			} else {
				if(idx)
					shouldSpace = true; // new word, add space
			}

			lastWasCap = true;
		} else {
			lastWasCap = false;
		}

		if(shouldSpace) {
			buffer[bufferIndex++] = space;
			if(bufferIndex == buffer.length) return name; // out of space, just give up, not that important
			shouldSpace = false;
		}
		if(shouldCap) {
			if(ch >= 'a' && ch <= 'z')
				ch -= 32;
			shouldCap = false;
		}
		if(allLowerCase && ch >= 'A' && ch <= 'Z')
			ch += 32;
		buffer[bufferIndex++] = ch;
	}
	return buffer[0 .. bufferIndex].idup;
}

/++
	This is the implementation for [dialog]. None of its details are guaranteed stable and may change at any time; the stable interface is just the [dialog] function at this time.
+/
class AutomaticDialog(T) : Dialog {
	T t;

	void delegate(T) onOK;
	void delegate() onCancel;

	override int paddingTop() { return defaultLineHeight; }
	override int paddingBottom() { return defaultLineHeight; }
	override int paddingRight() { return defaultLineHeight; }
	override int paddingLeft() { return defaultLineHeight; }

	this(Window parent, T initialData, void delegate(T) onOK, void delegate() onCancel, string title) {
		assert(onOK !is null);

		t = initialData;

		static if(is(T == class)) {
			if(t is null)
				t = new T();
		}
		this.onOK = onOK;
		this.onCancel = onCancel;
		super(parent, 400, cast(int)(__traits(allMembers, T).length * 2) * (defaultLineHeight + scaleWithDpi(4 + 2)) + defaultLineHeight + scaleWithDpi(56), title);

		static if(is(T == class))
			this.addDataControllerWidget(t);
		else
			this.addDataControllerWidget(&t);

		auto hl = new HorizontalLayout(this);
		auto stretch = new HorizontalSpacer(hl); // to right align
		auto ok = new CommandButton("OK", hl);
		auto cancel = new CommandButton("Cancel", hl);
		ok.addEventListener(EventType.triggered, &OK);
		cancel.addEventListener(EventType.triggered, &Cancel);

		this.addEventListener((KeyDownEvent ev) {
			if(ev.key == Key.Enter || ev.key == Key.PadEnter) {
				ok.focus();
				OK();
				ev.preventDefault();
			}
			if(ev.key == Key.Escape) {
				Cancel();
				ev.preventDefault();
			}
		});

		this.addEventListener((scope ClosedEvent ce) {
			if(onCancel)
				onCancel();
		});

		//this.children[0].focus();
	}

	override void OK() {
		onOK(t);
		close();
	}

	override void Cancel() {
		if(onCancel)
			onCancel();
		close();
	}
}

private template baseClassCount(Class) {
	private int helper() {
		int count = 0;
		static if(is(Class bases == super)) {
			foreach(base; bases)
				static if(is(base == class))
					count += 1 + baseClassCount!base;
		}
		return count;
	}

	enum int baseClassCount = helper();
}

private long stringToLong(string s) {
	long ret;
	if(s.length == 0)
		return ret;
	bool negative = s[0] == '-';
	if(negative)
		s = s[1 .. $];
	foreach(ch; s) {
		if(ch >= '0' && ch <= '9') {
			ret *= 10;
			ret += ch - '0';
		}
	}
	if(negative)
		ret = -ret;
	return ret;
}


interface ReflectableProperties {
	/++
		Iterates the event's properties as strings. Note that keys may be repeated and a get property request may
		call your sink with `null`. It it does, it means the key either doesn't request or cannot be represented by
		json in the current implementation.

		This is auto-implemented for you if you mixin [RegisterGetters] in your child classes and only have
		properties of type `bool`, `int`, `double`, or `string`. For other ones, you will need to do it yourself
		as of the June 2, 2021 release.

		History:
			Added June 2, 2021.

		See_Also: [getPropertyAsString], [setPropertyFromString]
	+/
	void getPropertiesList(scope void delegate(string name) sink) const;// @nogc pure nothrow;
	/++
		Requests a property to be delivered to you as a string, through your `sink` delegate.

		If the `value` is null, it means the property could not be retreived. If `valueIsJson`, it should
		be interpreted as json, otherwise, it is just a plain string.

		The sink should always be called exactly once for each call (it is basically a return value, but it might
		use a local buffer it maintains instead of allocating a return value).

		History:
			Added June 2, 2021.

		See_Also: [getPropertiesList], [setPropertyFromString]
	+/
	void getPropertyAsString(string name, scope void delegate(string name, scope const(char)[] value, bool valueIsJson) sink);
	/++
		Sets the given property, if it exists, to the given value, if possible. If `strIsJson` is true, it will json decode (if the implementation wants to) then apply the value, otherwise it will treat it as a plain string.

		History:
			Added June 2, 2021.

		See_Also: [getPropertiesList], [getPropertyAsString], [SetPropertyResult]
	+/
	SetPropertyResult setPropertyFromString(string name, scope const(char)[] str, bool strIsJson);

	/// [setPropertyFromString] possible return values
	enum SetPropertyResult {
		success = 0, /// the property has been successfully set to the request value
		notPermitted = -1, /// the property exists but it cannot be changed at this time
		notImplemented = -2, /// the set function is not implemented for the given property (which may or may not exist)
		noSuchProperty = -3, /// there is no property by that name
		wrongFormat = -4, /// the string was given in the wrong format, e.g. passing "two" for an int value
		invalidValue = -5, /// the string is in the correct format, but the specific given value could not be used (for example, because it was out of bounds)
	}

	/++
		You can mix this in to get an implementation in child classes. This does [setPropertyFromString].

		Your original base class, however, must implement its own methods. I recommend doing the initial ones by hand.

		For [Widget] and [Event], the library provides [Widget.Register] and [Event.Register] that call these for you, so you should
		rarely need to use these building blocks directly.
	+/
	mixin template RegisterSetters() {
		override SetPropertyResult setPropertyFromString(string name, scope const(char)[] value, bool valueIsJson) {
			switch(name) {
				foreach(memberName; __traits(derivedMembers, typeof(this))) {
					case memberName:
						static if(is(typeof(__traits(getMember, this, memberName)) : const bool)) {
							if(value != "true" && value != "false")
								return SetPropertyResult.wrongFormat;
							__traits(getMember, this, memberName) = value == "true" ? true : false;
							return SetPropertyResult.success;
						} else static if(is(typeof(__traits(getMember, this, memberName)) : const long)) {
							import core.stdc.stdlib;
							char[128] zero = 0;
							if(buffer.length + 1 >= zero.length)
								return SetPropertyResult.wrongFormat;
							zero[0 .. buffer.length] = buffer[];
							__traits(getMember, this, memberName) = strtol(buffer.ptr, null, 10);
						} else static if(is(typeof(__traits(getMember, this, memberName)) : const double)) {
							import core.stdc.stdlib;
							char[128] zero = 0;
							if(buffer.length + 1 >= zero.length)
								return SetPropertyResult.wrongFormat;
							zero[0 .. buffer.length] = buffer[];
							__traits(getMember, this, memberName) = strtod(buffer.ptr, null, 10);
						} else static if(is(typeof(__traits(getMember, this, memberName)) : const string)) {
							__traits(getMember, this, memberName) = value.idup;
						} else {
							return SetPropertyResult.notImplemented;
						}

				}
				default:
					return super.setPropertyFromString(name, value, valueIsJson);
			}
		}
	}

	/++
		You can mix this in to get an implementation in child classes. This does [getPropertyAsString] and [getPropertiesList].

		Your original base class, however, must implement its own methods. I recommend doing the initial ones by hand.

		For [Widget] and [Event], the library provides [Widget.Register] and [Event.Register] that call these for you, so you should
		rarely need to use these building blocks directly.
	+/
	mixin template RegisterGetters() {
		override void getPropertiesList(scope void delegate(string name) sink) const {
			super.getPropertiesList(sink);

			foreach(memberName; __traits(derivedMembers, typeof(this))) {
				sink(memberName);
			}
		}
		override void getPropertyAsString(string name, scope void delegate(string name, scope const(char)[] value, bool valueIsJson) sink) {
			switch(name) {
				foreach(memberName; __traits(derivedMembers, typeof(this))) {
					case memberName:
						static if(is(typeof(__traits(getMember, this, memberName)) : const bool)) {
							sink(name, __traits(getMember, this, memberName) ? "true" : "false", true);
						} else static if(is(typeof(__traits(getMember, this, memberName)) : const long)) {
							import core.stdc.stdio;
							char[32] buffer;
							auto len = snprintf(buffer.ptr, buffer.length, "%lld", cast(long) __traits(getMember, this, memberName));
							sink(name, buffer[0 .. len], true);
						} else static if(is(typeof(__traits(getMember, this, memberName)) : const double)) {
							import core.stdc.stdio;
							char[32] buffer;
							auto len = snprintf(buffer.ptr, buffer.length, "%f", cast(double) __traits(getMember, this, memberName));
							sink(name, buffer[0 .. len], true);
						} else static if(is(typeof(__traits(getMember, this, memberName)) : const string)) {
							sink(name, __traits(getMember, this, memberName), false);
							//sinkJsonString(memberName, __traits(getMember, this, memberName), sink);
						} else {
							sink(name, null, true);
						}

					return;
				}
				default:
					return super.getPropertyAsString(name, sink);
			}
		}
	}
}

private struct Stack(T) {
	this(int maxSize) {
		internalLength = 0;
		arr = initialBuffer[];
	}

	///.
	void push(T t) {
		if(internalLength >= arr.length) {
			auto oldarr = arr;
			if(arr.length < 4096)
				arr = new T[arr.length * 2];
			else
				arr = new T[arr.length + 4096];
			arr[0 .. oldarr.length] = oldarr[];
		}

		arr[internalLength] = t;
		internalLength++;
	}

	///.
	T pop() {
		assert(internalLength);
		internalLength--;
		return arr[internalLength];
	}

	///.
	T peek() {
		assert(internalLength);
		return arr[internalLength - 1];
	}

	///.
	@property bool empty() {
		return internalLength ? false : true;
	}

	///.
	private T[] arr;
	private size_t internalLength;
	private T[64] initialBuffer;
	// the static array is allocated with this object, so if we have a small stack (which we prolly do; dom trees usually aren't insanely deep),
	// using this saves us a bunch of trips to the GC. In my last profiling, I got about a 50x improvement in the push()
	// function thanks to this, and push() was actually one of the slowest individual functions in the code!
}

/// This is the lazy range that walks the tree for you. It tries to go in the lexical order of the source: node, then children from first to last, each recursively.
private struct WidgetStream {

	///.
	@property Widget front() {
		return current.widget;
	}

	/// Use Widget.tree instead.
	this(Widget start) {
		current.widget = start;
		current.childPosition = -1;
		isEmpty = false;
		stack = typeof(stack)(0);
	}

	/*
		Handle it
		handle its children

	*/

	///.
	void popFront() {
	    more:
	    	if(isEmpty) return;

		// FIXME: the profiler says this function is somewhat slow (noticeable because it can be called a lot of times)

		current.childPosition++;
		if(current.childPosition >= current.widget.children.length) {
			if(stack.empty())
				isEmpty = true;
			else {
				current = stack.pop();
				goto more;
			}
		} else {
			stack.push(current);
			current.widget = current.widget.children[current.childPosition];
			current.childPosition = -1;
		}
	}

	///.
	@property bool empty() {
		return isEmpty;
	}

	private:

	struct Current {
		Widget widget;
		int childPosition;
	}

	Current current;

	Stack!(Current) stack;

	bool isEmpty;
}


/+

	I could fix up the hierarchy kinda like this

	class Widget {
		Widget[] children() { return null; }
	}
	interface WidgetContainer {
		Widget asWidget();
		void addChild(Widget w);

		// alias asWidget this; // but meh
	}

	Widget can keep a (Widget parent) ctor, but it should prolly deprecate and tell people to instead change their ctors to take WidgetContainer instead.

	class Layout : Widget, WidgetContainer {}

	class Window : WidgetContainer {}


	All constructors that previously took Widgets should now take WidgetContainers instead



	But I'm kinda meh toward it, im not sure this is a real problem even though there are some addChild things that throw "plz don't".
+/

/+
	LAYOUTS 2.0

	can just be assigned as a function. assigning a new one will cause it to be immediately called.

	they simply are responsible for the recomputeChildLayout. If this pointer is null, it uses the default virtual one.

	recomputeChildLayout only really needs a property accessor proxy... just the layout info too.

	and even Paint can just use computedStyle...

		background color
		font
		border color and style

	And actually the style proxy can offer some helper routines to draw these like the draw 3d box
		please note that many widgets and in some modes will completely ignore properties as they will.
		they are just hints you set, not promises.





	So generally the existing virtual functions are just the default for the class. But individual objects
	or stylesheets can override this. The virtual ones count as tag-level specificity in css.
+/

/++
	Structure to represent a collection of background hints. New features can be added here, so make sure you use the provided constructors and factories for maximum compatibility.

	History:
		Added May 24, 2021.
+/
struct WidgetBackground {
	/++
		A background with the given solid color.
	+/
	this(Color color) {
		this.color = color;
	}

	this(WidgetBackground bg) {
		this = bg;
	}

	/++
		Creates a widget from the string.

		Currently, it only supports solid colors via [Color.fromString], but it will likely be expanded in the future to something more like css.
	+/
	static WidgetBackground fromString(string s) {
		return WidgetBackground(Color.fromString(s));
	}

	/++
		The background is not necessarily a solid color, but you can always specify a color as a fallback.

		History:
			Made `public` on December 18, 2022 (dub v10.10).
	+/
	Color color;
}

/++
	Interface to a custom visual theme which is able to access and use style hint properties, draw stylistic elements, and even completely override existing class' paint methods (though I'd note that can be a lot harder than it may seem due to the various little details of state you need to reflect visually, so that should be your last result!)

	Please note that this is only guaranteed to be used by custom widgets, and custom widgets are generally inferior to system widgets. Layout properties may be used by sytstem widgets though.

	You should not inherit from this directly, but instead use [VisualTheme].

	History:
		Added May 8, 2021
+/
abstract class BaseVisualTheme {
	/// Don't implement this, instead use [VisualTheme] and implement `paint` methods on specific subclasses you want to override.
	abstract void doPaint(Widget widget, WidgetPainter painter);

	/+
	/// Don't implement this, instead use [VisualTheme] and implement `StyleOverride` aliases on specific subclasses you want to override.
	abstract void useStyleProperties(Widget w, scope void delegate(scope Widget.Style props) dg);
	+/

	/++
		Returns the property as a string, or null if it was not overridden in the style definition. The idea here is something like css,
		where the interpretation of the string varies for each property and may include things like measurement units.
	+/
	abstract string getPropertyString(Widget widget, string propertyName);

	/++
		Default background color of the window. Widgets also use this to simulate transparency.

		Probably some shade of grey.
	+/
	abstract Color windowBackgroundColor();
	abstract Color widgetBackgroundColor();
	abstract Color foregroundColor();
	abstract Color lightAccentColor();
	abstract Color darkAccentColor();

	/++
		Colors used to indicate active selections in lists and text boxes, etc.
	+/
	abstract Color selectionForegroundColor();
	/// ditto
	abstract Color selectionBackgroundColor();

	deprecated("Use selectionForegroundColor and selectionBackgroundColor instead") Color selectionColor() { return selectionBackgroundColor(); }

	/++
		If you return `null` it will use simpledisplay's default. Otherwise, you return what font you want and it will cache it internally.
	+/
	abstract OperatingSystemFont defaultFont(int dpi);

	private OperatingSystemFont[int] defaultFontCache_;
	private OperatingSystemFont defaultFontCached(int dpi) {
		if(dpi !in defaultFontCache_) {
			// FIXME: set this to false if X disconnect or if visual theme changes
			defaultFontCache_[dpi] = defaultFont(dpi);
		}
		return defaultFontCache_[dpi];
	}
}

/+
	A widget should have:
		classList
		dataset
		attributes
		computedStyles
		state (persistent)
		dynamic state (focused, hover, etc)
+/

// visualTheme.computedStyle(this).paddingLeft


/++
	This is your entry point to create your own visual theme for custom widgets.

	You will want to inherit from this with a `final` class, passing your own class as the `CRTP` argument, then define the necessary methods.

	Compatibility note: future versions of minigui may add new methods here. You will likely need to implement them when updating.
+/
abstract class VisualTheme(CRTP) : BaseVisualTheme {
	override string getPropertyString(Widget widget, string propertyName) {
		return null;
	}

	/+
		mixin StyleOverride!Widget
	final override void useStyleProperties(Widget w, scope void delegate(scope Widget.Style props) dg) {
		w.useStyleProperties(dg);
	}
	+/

	final override void doPaint(Widget widget, WidgetPainter painter) {
		auto derived = cast(CRTP) cast(void*) this;

		scope void delegate(Widget, WidgetPainter) bestMatch;
		int bestMatchScore;

		static if(__traits(hasMember, CRTP, "paint"))
		foreach(overload; __traits(getOverloads, CRTP, "paint")) {
			static if(is(typeof(overload) Params == __parameters)) {
				static assert(Params.length == 2);
				static assert(is(Params[0] : Widget));
				static assert(is(Params[1] == WidgetPainter));
				static assert(is(typeof(&__traits(child, derived, overload)) == delegate), "Found a paint method that doesn't appear to be a delegate. One cause of this can be your dmd being too old, make sure it is version 2.094 or newer to use this feature."); // , __traits(getLocation, overload).stringof ~ " is not a delegate " ~ typeof(&__traits(child, derived, overload)).stringof);

				alias type = Params[0];
				if(cast(type) widget) {
					auto score = baseClassCount!type;

					if(score > bestMatchScore) {
						bestMatch = cast(typeof(bestMatch)) &__traits(child, derived, overload);
						bestMatchScore = score;
					}
				}
			} else static assert(0, "paint should be a method.");
		}

		if(bestMatch)
			bestMatch(widget, painter);
		else
			widget.paint(painter);
	}

	deprecated("Add an `int dpi` argument to your override now.") OperatingSystemFont defaultFont() { return null; }

	// I have to put these here even though I kinda don't want to since dmd regressed on detecting unimplemented interface functions through abstract classes
	// mixin Beautiful95Theme;
	mixin DefaultLightTheme;

	private static struct Cached {
		// i prolly want to do this
	}
}

/// ditto
mixin template Beautiful95Theme() {
	override Color windowBackgroundColor() { return Color(212, 212, 212); }
	override Color widgetBackgroundColor() { return Color.white; }
	override Color foregroundColor() { return Color.black; }
	override Color darkAccentColor() { return Color(172, 172, 172); }
	override Color lightAccentColor() { return Color(223, 223, 223); }
	override Color selectionForegroundColor() { return Color.white; }
	override Color selectionBackgroundColor() { return Color(0, 0, 128); }
	override OperatingSystemFont defaultFont(int dpi) { return null; } // will just use the default out of simpledisplay's xfontstr
}

/// ditto
mixin template DefaultLightTheme() {
	override Color windowBackgroundColor() { return Color(232, 232, 232); }
	override Color widgetBackgroundColor() { return Color.white; }
	override Color foregroundColor() { return Color.black; }
	override Color darkAccentColor() { return Color(172, 172, 172); }
	override Color lightAccentColor() { return Color(223, 223, 223); }
	override Color selectionForegroundColor() { return Color.white; }
	override Color selectionBackgroundColor() { return Color(0, 0, 128); }
	override OperatingSystemFont defaultFont(int dpi) {
		version(Windows)
			return new OperatingSystemFont("Segoe UI");
		else static if(UsingSimpledisplayCocoa) {
			return (new OperatingSystemFont()).loadDefault;
		} else {
			// FIXME: undo xft's scaling so we don't end up double scaled
			return new OperatingSystemFont("DejaVu Sans", 9 * dpi / 96);
		}
	}
}

/// ditto
mixin template DefaultDarkTheme() {
	override Color windowBackgroundColor() { return Color(64, 64, 64); }
	override Color widgetBackgroundColor() { return Color.black; }
	override Color foregroundColor() { return Color.white; }
	override Color darkAccentColor() { return Color(20, 20, 20); }
	override Color lightAccentColor() { return Color(80, 80, 80); }
	override Color selectionForegroundColor() { return Color.white; }
	override Color selectionBackgroundColor() { return Color(128, 0, 128); }
	override OperatingSystemFont defaultFont(int dpi) {
		version(Windows)
			return new OperatingSystemFont("Segoe UI", 12);
		else static if(UsingSimpledisplayCocoa) {
			return (new OperatingSystemFont()).loadDefault;
		} else {
			return new OperatingSystemFont("DejaVu Sans", 9 * dpi / 96);
		}
	}
}

/// ditto
alias DefaultTheme = DefaultLightTheme;

final class DefaultVisualTheme : VisualTheme!DefaultVisualTheme {
	/+
	OperatingSystemFont defaultFont() { return new OperatingSystemFont("Times New Roman", 8, FontWeight.medium); }
	Color windowBackgroundColor() { return Color(242, 242, 242); }
	Color darkAccentColor() { return windowBackgroundColor; }
	Color lightAccentColor() { return windowBackgroundColor; }
	+/
}

/++
	Event fired when an [Observeable] variable changes. You will want to add an event listener referencing
	the field like `widget.addEventListener((scope StateChanged!(Whatever.field) ev) { });`

	History:
		Moved from minigui_addons.webview to main minigui on November 27, 2021 (dub v10.4)

		Made `final` on January 3, 2025
+/
final class StateChanged(alias field) : Event {
	enum EventString = __traits(identifier, __traits(parent, field)) ~ "." ~ __traits(identifier, field) ~ ":change";
	override bool cancelable() const { return false; }
	this(Widget target, typeof(field) newValue) {
		this.newValue = newValue;
		super(EventString, target);
	}

	typeof(field) newValue;
}

/++
	Convenience function to add a `triggered` event listener.

	Its implementation is simply `w.addEventListener("triggered", dg);`

	History:
		Added November 27, 2021 (dub v10.4)
+/
void addWhenTriggered(Widget w, void delegate() dg) {
	w.addEventListener("triggered", dg);
}

/++
	Observable variables can be added to widgets and when they are changed, it fires
	off a [StateChanged] event so you can react to it.

	It is implemented as a getter and setter property, along with another helper you
	can use to subscribe with is `name_changed`. You can also subscribe to the [StateChanged]
	event through the usual means. Just give the name of the variable. See [StateChanged] for an
	example.

	To get an `ObservableReference` to the observable, use `&yourname_changed`.

	History:
		Moved from minigui_addons.webview to main minigui on November 27, 2021 (dub v10.4)

		As of March 5, 2025, the changed function now returns an [EventListener] handle, which
		you can use to disconnect the observer.
+/
mixin template Observable(T, string name) {
	private T backing;

	mixin(q{
		EventListener } ~ name ~ q{_changed (void delegate(T) dg) {
			return this.addEventListener((StateChanged!this_thing ev) {
				dg(ev.newValue);
			});
		}

		@property T } ~ name ~ q{ () {
			return backing;
		}

		@property void } ~ name ~ q{ (T t) {
			backing = t;
			auto event = new StateChanged!this_thing(this, t);
			event.dispatch();
		}
	});

	mixin("private alias this_thing = " ~ name ~ ";");
}

/// ditto
alias ObservableReference(T) = EventListener delegate(void delegate(T));

private bool startsWith(string test, string thing) {
	if(test.length < thing.length)
		return false;
	return test[0 .. thing.length] == thing;
}

private bool endsWith(string test, string thing) {
	if(test.length < thing.length)
		return false;
	return test[$ - thing.length .. $] == thing;
}

/++
	Context menus can have `@hotkey`, `@label`, `@tip`, `@separator`, and `@icon`

	Note they can NOT have accelerators or toolbars; those annotations will be ignored.

	Mark the functions callable from it with `@context_menu { ... }` Presence of other `@menu(...)` annotations will exclude it from the context menu at this time.

	See_Also:
		[Widget.setMenuAndToolbarFromAnnotatedCode]
+/
Menu createContextMenuFromAnnotatedCode(TWidget)(TWidget w) if(is(TWidget : Widget)) {
	return createContextMenuFromAnnotatedCode(w, w);
}

/// ditto
Menu createContextMenuFromAnnotatedCode(T)(Widget w, ref T t) if(!is(T == class) && !is(T == interface)) {
	return createContextMenuFromAnnotatedCode_internal(w, t);
}
/// ditto
Menu createContextMenuFromAnnotatedCode(T)(Widget w, T t) if(is(T == class) || is(T == interface)) {
	return createContextMenuFromAnnotatedCode_internal(w, t);
}
Menu createContextMenuFromAnnotatedCode_internal(T)(Widget w, ref T t) {
	Menu ret = new Menu("", w);

	foreach(memberName; __traits(derivedMembers, T)) {
		static if(memberName != "this")
		static if(hasAnyRelevantAnnotations!(__traits(getAttributes, __traits(getMember, T, memberName)))) {
			.menu menu;
			bool separator;
			.hotkey hotkey;
			.icon icon;
			string label;
			string tip;
			foreach(attr; __traits(getAttributes, __traits(getMember, T, memberName))) {
				static if(is(typeof(attr) == .menu))
					menu = attr;
				else static if(is(attr == .separator))
					separator = true;
				else static if(is(typeof(attr) == .hotkey))
					hotkey = attr;
				else static if(is(typeof(attr) == .icon))
					icon = attr;
				else static if(is(typeof(attr) == .label))
					label = attr.label;
				else static if(is(typeof(attr) == .tip))
					tip = attr.tip;
			}

			if(menu is .menu.init) {
				ushort correctIcon = icon.id; // FIXME
				if(label.length == 0)
					label = memberName.toMenuLabel;

				auto handler = makeAutomaticHandler!(__traits(getMember, T, memberName))(w.parentWindow, &__traits(getMember, t, memberName));

				auto action = new Action(label, correctIcon, handler);

				if(separator)
					ret.addSeparator();
					ret.addItem(new MenuItem(action));
			}
		}
	}

	return ret;
}

// still do layout delegation
// and... split off Window from Widget.

version(minigui_screenshots)
struct Screenshot {
	string name;
}

version(minigui_screenshots)
static if(__VERSION__ > 2092)
mixin(q{
shared static this() {
	import core.runtime;

	static UnitTestResult screenshotMagic() {
		string name;

		import arsd.png;

		auto results = new Window();
		auto button = new Button("do it", results);

		Window.newWindowCreated = delegate(Window w) {
			Timer timer;
			timer = new Timer(250, {
				auto img = w.win.takeScreenshot();
				timer.destroy();

				version(Windows)
					writePng("/var/www/htdocs/minigui-screenshots/windows/" ~ name ~ ".png", img);
				else
					writePng("/var/www/htdocs/minigui-screenshots/linux/" ~ name ~ ".png", img);

				w.close();
			});
		};

		button.addWhenTriggered( {

		foreach(test; __traits(getUnitTests, mixin("arsd.minigui"))) {
			name = null;
			static foreach(attr; __traits(getAttributes, test)) {
				static if(is(typeof(attr) == Screenshot))
					name = attr.name;
			}
			if(name.length) {
				test();
			}
		}

		});

		results.loop();

		return UnitTestResult(0, 0, false, false);
	}


	Runtime.extendedModuleUnitTester = &screenshotMagic;
}
});
version(minigui_screenshots) {
	version(unittest)
		void main() {}
	else static assert(0, "dont forget the -unittest flag to dmd");
}

// FIXME: i called hotkey accelerator in some places. hotkey = key when menu is active like E&xit. accelerator = global shortcut.
// FIXME: make multiple accelerators disambiguate based ona rgs
// FIXME: MainWindow ctor should have same arg order as Window
// FIXME: mainwindow ctor w/ client area size instead of total size.
// Push on/off button (basically an alternate display of a checkbox) -- BS_PUSHLIKE and maybe BS_TEXT (BS_TOP moves it). see also BS_FLAT.
// FIXME: tri-state checkbox
// FIXME: subordinate controls grouping...
