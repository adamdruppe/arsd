// just docs: General Concepts
/++
	This document describes some general programming concepts and tricks and tips that will make using my APIs easier.

	This document is primarily focused on $(B users) of the library. If you would like to learn more about the $(B implementation) of the library, browser my blog: http://dpldocs.info/this-week-in-d/Blog.html


	$(H2 Bitmasks)

	See [#bitflags].

	$(H2 Bitflags)

	Many functions, for example, [arsd.simpledisplay.ScreenPainter.drawText] and [arsd.terminal.Terminal.color], take a `uint` typed argument that is supposed to be made from a combination of `enum` flags defined elsewhere in the file. These are often called "bit flags".

	To create one of these arguments, you use D's bitwise or operator to combine various options. `Color.red | Bright` will combine the values of `Color.red` and `Bright` to make a new argument that [arsd.terminal.Terminal.color] can comprehend. `TextAlignment.Center | TextAlignment.VerticalCenter` makes a combined argument for `drawText`'s `alignment` parameter.

	The `enum` values will have values that go up multiplying by two. If you see values like `1, 2, 4, 8` in an `enum`'s members, there's a good chance it is meant to be combined with the `|` operator when passed to a function.

	The inverse is called a "bit mask" because various bits are "masked" - imagine just seeing someone's eyes through a mask but not their nose - out by the function to deconstruct the combined result back into its individual pieces for processing. D's `&` operator, bitwise and, is used inside the functions to undo the result of `|` on the outside. You can do this too if a function returns a combined result like this. [arsd.simpledisplay.MouseEvent.modifierState] is an example of a struct member made out of individual bits. If you check `if(event.modifierState & ModifierState.leftButtonDown) {}`, you can check for the individual items.

	$(TIP
		You can actually combine `|` and `&` in a check.

		```
		if(event.modifierState & (ModifierState.leftButtonDown | ModifierState.rightButtonDown)) {
			// this will be true if either the left OR right buttons are down
		}
		```
	)
+/
module arsd.docs.general_concepts;
