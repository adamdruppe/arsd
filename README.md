# IMPORTANT NOTE

As of January 1, 2024, this repo is written in the [OpenD Programming Language](https://dpldocs.info/opend/). This is very similar to, but NOT the same as Walter Bright's version of the D Programming Language.

There will be no further public updates with supported compatibility with WB's D Language. If you depend on this code, either [contact me](mailto:destructionator@gmail.com) to negotiate a commercial support contract or switch to the [OpenD Programming Language](https://dpldocs.info/opend/). If things keep working from here on out, it is purely coincidental: support requests relating to WB's D are likely to go unanswered and new features are not guaranteed to work.

# About

This is a collection of modules that I've released over the years (the oldest module in here was originally written in 2006, pre-D1!) for a wide variety of purposes. Most of them stand alone, or have just one or two dependencies in here, so you don't have to download this whole repo. Feel free to email me, destructionator@gmail.com or ping me as `adam_d_ruppe` on the #d IRC channel if you want to ask me anything.

I'm always adding to it, but my policy on dependencies means you can ignore what you don't need. I am also committed to long-term support for OpenD users. Even the obsolete modules I haven't used for years I usually keep compiling at least, and the ones I do use I am very hesitant to break backward compatibility on. My semver increases are *very* conservative.

See the full list of (at least slightly) documented module here: http://arsd-official.dpldocs.info/arsd.html and refer to https://code.dlang.org/packages/arsd-official for the list of `dub`-enabled subpackages. Please note that `dub` is no longer officially supported, but it may work for you anyway.

## Links

I have [a patreon](https://www.patreon.com/adam_d_ruppe) and my (almost) [weekly blog](http://dpldocs.info/this-week-in-arsd/) you can check out if you'd like to financially support this work or see the updates and tips I write about.

# Breaking Changelog

This only lists changes that broke things and got a major version bump. I didn't start keeping track here until 9.0.

Please note that I DO consider changes to build process to be a breaking change, but I do NOT consider symbol additions, changes to undocumented members, or the occasional non-fatal deprecation to be breaking changes. Undocumented members may be changed at any time, whereas additions and/or deprecations will be a minor version change.

## 13.0

Future release, likely May 2026 or later.

Nothing is planned for it at this time.

## 12.0

Released: January 2025

minigui's `defaultEventHandler_*` functions take more specific objects. So if you see errors like:

```
Error: function `void arsd.minigui.EditableTextWidget.defaultEventHandler_focusin(Event foe)` does not override any function, did you mean to override `void arsd.minigui.Widget.defaultEventHandler_focusin(arsd.minigui.FocusInEvent event)`?
```

Go to the file+line number from the error message and change `Event` to `FocusInEvent` (or whatever one it tells you in the "did you mean" part of the error) and recompile. No other changes should be necessary, however if you constructed your own `Event` object and dispatched it with the loosely typed `"focus"`, etc., strings, it may not trigger the default handlers anymore. To fix this, change any `new Event` to use the appropriate subclass, when available, like old `new Event("focus", widget);` changes to `new FocusEvent(widget)`. This only applies to ones that trigger default handlers present in `Widget` base class; your custom events still work the same way.

arsd.pixmappresenter, arsd.pixmappaint and arsd.pixmaprecorder were added.

## 11.0

Released: Planned for May 2023, actually out August 2023.

arsd.core was added, causing a general build system break for users who download individual files:

simpledisplay.d used to depend only on color.d. It now also depends on core.d.

terminal.d and http2.d used to be stand-alone. They now depend on core.d.

minigui.d now also depends on a new textlayouter.d, bringing its total dependencies from minigui.d, simpledisplay.d, color.d up to minigui.d, simpledisplay.d, color.d, core.d, and textlayouter.d

dom.d, database.d, png.d, and others may start importing it at any time, so you have to assume they do from here on and have the file in your build.

Generally speaking, I am relaxing my dependency policy somewhat to permit a little more code sharing and interoperability throughout the modules. While I will make efforts to maintain some degree of stand-alone functionality, many new features and even some old features may be changed to use the new module. As such, I reserve to right to use core.d from *any* module from this point forward. You should be prepared to add it to your builds using any arsd component.

Note that arsd.core may require user32.lib and ws2_32.lib on Windows. This is added automatically in most cases, and is a core component so it will be there, but if you see a linker error, this might be why.

I recommend you clone the repo and use `dmd -i` to let the compiler automatically included imported modules. It really is quite nice to use! But, of course, I don't require it and will call out other required cross-module dependencies in the future too.

Also:

	* dom.d's XmlDocument no longer treats `<script>` and `<style>` tags as CDATA; that was meant to be a html-specific behavior, not applicable to generic xml.
	* game.d had significant changes, making the Game object be a manager of GameScreen objects, which use delta time interpolated renders and fixed time updates (before it was vice versa). As of 11.0, its new api is not fully stable.
	* database.d got some tweaks. A greater overhaul is still planned but might be delayed to 12.0. Nevertheless, some types are already changed from `string` to `DatabaseDatum` (which converts back to string via `alias this` so it should limit the code breakage).
	* Support for Windows XP has been dropped (though it may still work in certain places, there's no promises since arsd.core uses some Windows Vista features without fallback.)
	* Support for older compilers has been dropped (arsd.core uses some newer druntime features). The new minimum version is likely gdc 10, the tester now runs gdc version 12. gdc 9 might still sometimes work but I'm going to be removing some of those compatibility branches soon anyway.
	* minigui's default theme has been slightly modified to use a different font on linux.

Note that dub currently gives a warning when you do `dub test` about there being no import paths. Ignore this, it is meaningless.

### Diagnostics

```
lld-link: error: undefined symbol: _MsgWaitForMultipleObjectsEx@20
>>> referenced by core.obj:(__D4arsd4core27CoreEventLoopImplementation7runOnceMFZv)
```

Indicates a missing `user32.lib` in the link. This should generally be automatic but if not, you can simply mention it on the dmd command line (like `dmd yourfile.d user32.lb`) or add it to an explicit dub config `libs`.

Errors like:
```
lld-link: error: undefined symbol: _D4arsd4core21AsyncOperationRequest5startMFZv
>> referenced by yourfile.obj:(_D4arsd4core21AsyncOperationRequest6__vtblZ)
```

Generally, any symbol that starts with `_D4arsd4core` indicates a missing `core.d` in the build. Make sure you have it downloaded and included.

### Still coming

11.0 focused on getting breaking changes in before the deadline. Some additive features that had to be deferred will be coming in 11.1 and beyond, including, but not limited to:

	* simpleaudio synthesis
	* game.d reorganization (11.0 marks it broken, then it will restablize later)
	* minigui drag and drop
	* simpledisplay touch
	* ssl server for cgi.d
	* tui helpers
	* database improvements if I can do it without breakage, if it has major breakage, I'll leave it to 12.0.
	* click and drag capture behavior in minigui and the terminal emulator widget in particular
	* more dox
	* i should prolly rewrite the script.d parser someday but maybe that will be a 12.0 thing

## 10.0

Released: May 2021

minigui 2.0 came out with deprecations on some event properties, moved style properties, and various other changes. See http://arsd-official.dpldocs.info/arsd.minigui.html#history for details.

database.d now considers null strings as NULL when inserting/updating. before it would consider it '' to the database. Empty strings are still ''.

## 9.0

Released: December 2020

simpledisplay's OperatingSystemFont, which is also used by terminalemulator.d (which is used by terminal.d's -version=TerminalDirectToEmulator function) would previously only load X Core Fonts. It now prefers TrueType fonts via Xft. This loads potentially different fonts and the sizes are interpreted differently, so you may need to adjust your preferences there. To restore previous behavior, prefix your font name strings with "core:".

http2.d's "connection refused" handler used to throw an exception for any pending connection. Now it instead just sets that connection to `aborted` and carries on with other ones. When you are doing a request, be sure to check `response.code`. It may be < 100 if connection refused and other errors. You should already have been checking the http response code, but now some things that were exceptions are now codes, so it is even more important to check this properly.

## Prehistory:

8.0 Released: June 2020

7.0 and 6.0 Released: March 2020 (these were changes to the terminal.d virtual methods, tag 6.0 was a mistake, i pressed it too early)

5.0 Released: January 2019

4.0 and 3.0 Released: July 2019 and June 2019, respectively. These had to do with dub subpackage configuration changes IIRC.

2.0 Released (first use of semver tagging, before this I would only push to master): March 2018

April 2016: simpledisplay and terminal renamed to arsd.simpledisplay and arsd.terminal

September 2015: simpledisplay started to depend on color.d instead of being standalone

Joined dub (tagged 1.0): June 2015

Joined github: July 2011

Started project on my website: 2008

## Credits

Thanks go to Nick Sabalausky, Trass3r, Stanislav Blinov, ketmar, maartenvd, and many others over the years for input and patches.

Several of the modules are also ports of other C code, see the comments in those files for their original authors.

# Conventions

Many http-based functions in the lib also support unix sockets as an alternative to tcp.

With cgi.d, use

	--host unix:/path/here

or, on Linux:

	--host abstract:/path/here

after compiling with `-version=embedded_httpd_thread` to serve http on the given socket. (`abstract:` does a unix socket in the Linux-specific abstract namespace).

With http2.d, use

	Uri("http://whatever_host/path?args").viaUnixSocket("/path/here")

any time you are constructing a client. Note that `navigateTo` may lose the unix socket unless you specify it again.

