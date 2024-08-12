/++
	The "keyboard palette widget" is a thing for visually representing hotkeys.

	It lays out a bunch of clickable buttons similar to the ascii latter keys on a qwerty keyboard. Each one has an icon and a letter associated with it. If you hold shift, it can change to a second page of items.

	The intention is that input would be layered through some redirects. Normally, ctrl+letters are shortcuts for menu items. Alt+letters are for menu opening. Logo+letters are reserved for the window manager. So this leaves unshifted and shifted keys for you to use.

	My convention is that F-keys are shortcuts for either tabs or menu items.

	Numbers are for switching other things like your brush.

	Letters are thus your main interaction, and symbols can be secondary tool changes.
		You could be in one of three modes:
			1) Pick a tool, pick a color, and place with a thing (really mouse interaction mode)
			2) Pick a tool, place colors directly on press (keyboard interaction?)
			3) Pick a color, use a tool
			4) vi style sentences

	It will emit a selection changed event when the user changes the selection. (what about right click? want separate selections for different buttons?)
	It will emit a rebind request event when the user tries to rebind it (typically a double click)

	LETTERS (26 total plus shifts)
	NUMBERS / NUMPAD (10 total plus shifts)
	OTHER KEYS (11 total plus shifts)
	`   - =
	     [ ] \
	    ; '
	  , . /

	Leaves: tab, space, enter, backspace and of course: arrows, the six pak insert etc. and the F-keys

	Each thing has: Icon / Label / Hotkey / Code or Associated Object.

	USAGE:

		Create a container widget
		Put the keyboard palette widget in the container
		Put your other content in the container
		Make the container get the actual keyboard focus, let this hook into its parent events.

	TOOLS:
		place, stamp, select (circle, rectangle, free-form, path)
		flood fill
		move selection.. move selected contents
		scroll (click and drag on the map scrolls the view)

	So really you'd first select tool then select subthing of tool.

	1 = pen. letters = what thing you're placing
	2 = select. letters = shape or operation of selection
		r = rectangle
		p = path
		c = circle
		e = ellipse
		q = freeform
		a = all
		n = none
		z = fuzzy (select similar things)
		f = flood fill <convenience operator>, then letter to pick a color/tile. fill whole selection, fill zone inside selection
		m = move

		select wants add, replace, subtract, intersect.

	2 = replace selection
	3 = add to selection
	4 = remove from selection
	5 = intersect selection

	save/recall selection
	save/goto marked scroll place. it can be an icon of a minimap with a highlight: 3x pixel, black/white/black, pointing to it from each edge then a 7x7 px highlight of the thing
+/
module arsd.minigui_addons.keyboard_palette_widget;

import arsd.minigui;

enum KeyGroups {
	letters,
	numbers,
	symbols,
	fkeys
}

struct PaletteItem {
	string label;
	MemoryImage icon;
	Key hotkey;
	Object obj;
}

class KeyboardPaletteWidget : Widget {
	this(Widget parent) {
		super(parent);
	}
}
