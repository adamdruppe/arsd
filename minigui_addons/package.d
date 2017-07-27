/++
	This package consists of additional widgets for [arsd.minigui].

	Each module stands alone on top of minigui.d; none in this package
	depend on each other, so you can pick and choose the modules that
	look useful to you and ignore the others.

	These modules may or may not expose native widgets, refer to the
	documentation in each individual to see what it does.


	When writing a minigui addon module, keep the following in mind:

	$(LIST
		* Use `static if(UsingWin32Widgets)` and `static if(UsingCustomWidgets)`
		  if you want to provide both native Windows and custom drawn alternatives.
		  Do NOT use `version` because versions are not imported across modules.

		* Similarly, if you need to write platform-specific code, you can use
		  `static if(UsingSimpledisplayX11)` to check for X. However, here,
		  `version(Windows)` also works pretty well.

		* It is not allowed to import any other minigui_addon module. This is to
		  ensure it remains individual addons, not a webby mess of a library.
	)
+/
module arsd.minigui_addons;
