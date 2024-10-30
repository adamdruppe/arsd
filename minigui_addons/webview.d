/++
	A webview (based on [arsd.webview]) for minigui.

	For now at least, to use this, you MUST have a [WebViewApp] in scope in main for the duration of your gui application.

	Warning: CEF spams the current directory with a bunch of files and directories. You might want to run your program in a dedicated location.

	History:
		Added November 5, 2021. NOT YET STABLE.

		status text and favicon change notifications implemented on Windows WebView2 on December 16, 2023 (so long as the necessary api version is available, otherwise it will silently drop it).

	Dependencies:
		Requires arsd.png on Windows for favicons, may require more in the future.

	Examples:
	---
	/+ dub.sdl:
		name "web"
		dependency "arsd-official:minigui-webview" version="*"
	+/

	import arsd.minigui;
	import arsd.minigui_addons.webview;

	void main() {
		auto app = WebViewApp(null);
		auto window = new Window;
		auto webview = new WebViewWidget("http://dlang.org/", window);
		window.loop;
	}
	---
+/
module arsd.minigui_addons.webview;
// FIXME: i think i can download the cef automatically if needed.

// want to add mute support
// https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2_8?view=webview2-1.0.2210.55

// javascript : AddScriptToExecuteOnDocumentCreated / cef_register_extension or https://bitbucket.org/chromiumembedded/cef/wiki/JavaScriptIntegration.md idk
// need a: post web message / on web message posted

// and some magic reply to certain url schemes.

// also want to make sure it can prefix http:// and such when typing in a url bar cross platform

import arsd.core;

version(linux)
	version=cef;
version(Windows)
	version=wv2;

/+
	SPA mode: put favicon on top level window, no other user controls at top level, links to different domains always open in new window.
+/

// FIXME: look in /opt/cef for the dll and the locales

import arsd.minigui;
import arsd.webview;

version(wv2) {
	alias WebViewWidget = WebViewWidget_WV2;
	alias WebViewApp = Wv2App;
} else version(cef) {
	alias WebViewWidget = WebViewWidget_CEF;
	alias WebViewApp = CefApp;
} else static assert(0, "no webview available");

class WebViewWidgetBase : NestedChildWindowWidget {
	protected SimpleWindow containerWindow;

	protected this(Widget parent) {
		containerWindow = new SimpleWindow(640, 480, null, OpenGlOptions.no, Resizability.allowResizing, WindowTypes.nestedChild, WindowFlags.normal, getParentWindow(parent));
		// import std.stdio; writefln("container window %d created", containerWindow.window);

		super(containerWindow, parent);
	}

	mixin Observable!(string, "title");
	mixin Observable!(string, "url");
	mixin Observable!(string, "status");

	// not implemented on WV2
	mixin Observable!(int, "loadingProgress");

	// not implemented on WV2
	mixin Observable!(string, "favicon_url");
	mixin Observable!(MemoryImage, "favicon"); // please note it can be changed to null!

	abstract void refresh();
	abstract void back();
	abstract void forward();
	abstract void stop();

	abstract void navigate(string url);

	// the url and line are for error reporting purposes. They might be ignored.
	// FIXME: add a callback with the reply. this can send a message from the js thread in cef and just ExecuteScript inWV2
	// FIXME: add AddScriptToExecuteOnDocumentCreated for cef....
	abstract void executeJavascript(string code, string url = null, int line = 0);
	// for injecting stuff into the context
	// abstract void executeJavascriptBeforeEachLoad(string code);

	abstract void showDevTools();

	/++
		Your communication consists of running Javascript and sending string messages back and forth,
		kinda similar to your communication with a web server.
	+/
	// these form your communcation channel between the web view and the native world
	// abstract void sendMessageToHost(string json);
	// void delegate(string json) receiveMessageFromHost;

	/+
		I also need a url filter
	+/

	// this is implemented as a do-nothing in the NestedChildWindowWidget base
	// but you will almost certainly need to override it in implementations.
	// abstract void registerMovementAdditionalWork();
}

// AddScriptToExecuteOnDocumentCreated



version(wv2)
class WebViewWidget_WV2 : WebViewWidgetBase {
	private RC!ICoreWebView2 webview_window;
	// 12 introduces status bar
	// 15 introduces favicon notifications
	// 16 introduces printing
	private RC!ICoreWebView2_16 webview_window_ext_1;
	private RC!ICoreWebView2Environment webview_env;
	private RC!ICoreWebView2Controller controller;

	private bool initialized;

	private HRESULT initializeWithController(ICoreWebView2Controller controller_raw) {

		// need to keep this beyond the callback or we're doomed.
		this.controller = RC!ICoreWebView2Controller(controller_raw);

		this.webview_window = controller.CoreWebView2;

		this.webview_window_ext_1 = this.webview_window.queryInterface!(ICoreWebView2_16);

		bool enableStatusBar = true;

		if(this.webview_window_ext_1) {
			enableStatusBar = false;
			this.webview_window_ext_1.add_StatusBarTextChanged!(typeof(this))((sender, args, this_) {
				this_.status = toGC(&this_.webview_window_ext_1.raw.get_StatusBarText);
				return S_OK;
			}, this);

			webview_window_ext_1.add_FaviconChanged!(typeof(this))((sender, args, this_) {
				this_.webview_window_ext_1.GetFavicon(
					COREWEBVIEW2_FAVICON_IMAGE_FORMAT_PNG,
					callback!(ICoreWebView2GetFaviconCompletedHandler, typeof(this_))(function(error, streamPtrConst, ctx2) {

						auto streamPtr = cast(IStream) streamPtrConst;

						ubyte[] buffer = new ubyte[](640); // most favicons are pretty small
						enum growth_size = 1024; // and we'll grow linearly by the kilobyte
						size_t at;

						more:
						ULONG actuallyRead;
						auto ret = streamPtr.Read(buffer.ptr + at, cast(UINT) (buffer.length - at), &actuallyRead);
						if(ret == S_OK) {
							// read completed, possibly more data pending
							auto moreData = actuallyRead >= (buffer.length - at);

							at += actuallyRead;
							if(moreData && (buffer.length - at < growth_size))
								buffer.length += growth_size;
							goto more;
						} else if(ret == S_FALSE) {
							// end of file reached
							at += actuallyRead;
							buffer = buffer[0 .. at];

							import arsd.png;
							ctx2.favicon = readPngFromBytes(buffer);
						} else {
							// other error
							throw new ComException(ret);
						}

						return S_OK;
					}, this_)
				);

				return S_OK;
			}, this);
		}

		webview_window.add_DocumentTitleChanged!(typeof(this))((sender, args, this_) {
			this_.title = toGC(&sender.get_DocumentTitle);
			return S_OK;
		}, this);

		webview_window.add_NewWindowRequested!(typeof(this))((sender, args, this_) {
			// args.get_Uri
			// args.get_IsUserInitiated
			// args.put_NewWindow();

			string url = toGC(&args.get_Uri);
			int ret;

			WebViewWidget_WV2 widget;

			runInGuiThread({
				ret = 0;

				scope WebViewWidget delegate(Widget, BrowserSettings) accept = (parent, passed_settings) {
					ret = 1;
					if(parent !is null) {
						auto widget = new WebViewWidget_WV2(url, this_.openNewWindow, passed_settings, parent);

						return widget;
					}
					return null;
				};
				this_.openNewWindow(OpenNewWindowParams(url, accept));
				return;
			});

			if(ret) {
				args.put_Handled(true);
				// args.put_NewWindow(widget.webview_window.returnable);
			}

			return S_OK;

		}, this);

		// add_HistoryChanged
		// that's where CanGoBack and CanGoForward can be rechecked.

		RC!ICoreWebView2Settings Settings = this.webview_window.Settings;
		Settings.IsScriptEnabled = TRUE;
		Settings.AreDefaultScriptDialogsEnabled = TRUE;
		Settings.IsWebMessageEnabled = TRUE;
		Settings.IsStatusBarEnabled = enableStatusBar;

		auto ert = this.webview_window.add_NavigationStarting!(typeof(this))(
			function (sender, args, this_) {
				this_.url = toGC(&args.get_Uri);
				return S_OK;
			}, this);

		RECT bounds;
		GetClientRect(this.containerWindow.impl.hwnd, &bounds);
		controller.Bounds = bounds;
		//error = webview_window.Navigate("http://arsdnet.net/test.html"w.ptr);
		//error = webview_window.NavigateToString("<html><body>Hello</body></html>"w.ptr);
		//error = webview_window.Navigate("http://192.168.1.10/"w.ptr);

		if(url !is null) {
			WCharzBuffer bfr = WCharzBuffer(url);
			this.webview_window.Navigate(bfr.ptr);
		}

		controller.IsVisible = true;

		this.initialized = true;

		return S_OK;
	}

	private void delegate(scope OpenNewWindowParams) openNewWindow;

	this(string url, void delegate(scope OpenNewWindowParams) openNewWindow, BrowserSettings settings, Widget parent) {
		this.openNewWindow = openNewWindow;
		super(parent);
		// that ctor sets containerWindow

		this.url = url;

		Wv2App.useEnvironment((env) {
			env.CreateCoreWebView2Controller(containerWindow.impl.hwnd,
				callback!(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, typeof(this))(function(error, controller_raw, ctx) {
					if(error || controller_raw is null)
						return error;

					return ctx.initializeWithController(controller_raw);
				}, this));
		});
	}

	override void registerMovementAdditionalWork() {
		if(initialized) {
			RECT bounds;
			GetClientRect(containerWindow.impl.hwnd, &bounds);
			controller.Bounds = bounds;

			controller.NotifyParentWindowPositionChanged();
		}
	}

	override void refresh() {
		if(!initialized) return;
		webview_window.Reload();
	}
	override void back() {
		if(!initialized) return;
		webview_window.GoBack();
	}
	override void forward() {
		if(!initialized) return;
		webview_window.GoForward();
	}
	override void stop() {
		if(!initialized) return;
		webview_window.Stop();
	}

	override void navigate(string url) {
		if(!initialized) return;
		import std.utf;
		auto error = webview_window.Navigate(url.toUTF16z);
	}

	// the url and line are for error reporting purposes
	override void executeJavascript(string code, string url = null, int line = 0) {
		if(!initialized) return;
		import std.utf;
		webview_window.ExecuteScript(code.toUTF16z, null);
	}

	override void showDevTools() {
		if(!initialized) return;
		webview_window.OpenDevToolsWindow();
	}
}

/++
	The openInNewWindow delegate is given these params.

	To accept the new window, call

	params.accept(parent_widget);

	Please note, you can force it to replace the current tab
	by just navigating your current thing to the given url instead
	of accepting it.

	If you accept with a null widget, it will create a new window
	but then return null, since the new window is managed by the
	underlying webview instead of by minigui.

	If you do not call accept, the pop up will be blocked.

	accept returns an instance to the newly created widget, which will
	be a parent to the widget you passed.

	accept will be called from the gui thread and it MUST not call into
	any other webview methods. It should only create windows/widgets
	and set event handlers etc.

	You MUST not escape references to anything in this structure. It
	is entirely strictly temporary!
+/
struct OpenNewWindowParams {
	string url;
	WebViewWidget delegate(Widget parent, BrowserSettings settings = BrowserSettings.init) accept;
}

/++
	Represents a browser setting that can be left default or specifically turned on or off.
+/
struct SettingValue {
	private byte value = -1;

	/++
		Set it with `= true` or `= false`.
	+/
	void opAssign(bool enable) {
		value = enable ? 1 : 0;
	}

	/++
		And this resets it to the default value.
	+/
	void setDefault() {
		value = -1;
	}

	/// If isDefault, it will use the default setting from the browser. Else, the getValue return value will be used. getValue is invalid if !isDefault.
	bool isDefault() {
		return value == -1;
	}

	/// ditto
	bool getValue() {
		return value == 1;
	}
}

/++
	Defines settings for a browser widget. Not all backends will respect all settings.

	The order of members of this struct may change at any time. Refer to its members by
	name.
+/
struct BrowserSettings {
	/// This is just disabling the automatic positional constructor, since that is not stable here.
	this(typeof(null)) {}

	string standardFontFamily;
	string fixedFontFamily;
	string serifFontFamily;
	string sansSerifFontFamily;
	string cursiveFontFamily;
	string fantasyFontFamily;

	int defaultFontSize;
	int defaultFixedFontSize;
	int minimumFontSize;
	//int minimumLogicalFontSize;

	SettingValue remoteFontsEnabled;
	SettingValue javascriptEnabled;
	SettingValue imagesEnabled;
	SettingValue clipboardAccessEnabled;
	SettingValue localStorageEnabled;

	version(cef)
	private void set(cef_browser_settings_t* browser_settings) {
		alias settings = this;
		if(settings.standardFontFamily)
			browser_settings.standard_font_family = cef_string_t(settings.standardFontFamily);
		if(settings.fixedFontFamily)
			browser_settings.fixed_font_family = cef_string_t(settings.fixedFontFamily);
		if(settings.serifFontFamily)
			browser_settings.serif_font_family = cef_string_t(settings.serifFontFamily);
		if(settings.sansSerifFontFamily)
			browser_settings.sans_serif_font_family = cef_string_t(settings.sansSerifFontFamily);
		if(settings.cursiveFontFamily)
			browser_settings.cursive_font_family = cef_string_t(settings.cursiveFontFamily);
		if(settings.fantasyFontFamily)
			browser_settings.fantasy_font_family = cef_string_t(settings.fantasyFontFamily);
		if(settings.defaultFontSize)
			browser_settings.default_font_size = settings.defaultFontSize;
		if(settings.defaultFixedFontSize)
			browser_settings.default_fixed_font_size = settings.defaultFixedFontSize;
		if(settings.minimumFontSize)
			browser_settings.minimum_font_size = settings.minimumFontSize;

		if(!settings.remoteFontsEnabled.isDefault())
			browser_settings.remote_fonts = settings.remoteFontsEnabled.getValue() ? cef_state_t.STATE_ENABLED : cef_state_t.STATE_DISABLED;
		if(!settings.javascriptEnabled.isDefault())
			browser_settings.javascript = settings.javascriptEnabled.getValue() ? cef_state_t.STATE_ENABLED : cef_state_t.STATE_DISABLED;
		if(!settings.imagesEnabled.isDefault())
			browser_settings.image_loading = settings.imagesEnabled.getValue() ? cef_state_t.STATE_ENABLED : cef_state_t.STATE_DISABLED;
		if(!settings.clipboardAccessEnabled.isDefault())
			browser_settings.javascript_access_clipboard = settings.clipboardAccessEnabled.getValue() ? cef_state_t.STATE_ENABLED : cef_state_t.STATE_DISABLED;
		if(!settings.localStorageEnabled.isDefault())
			browser_settings.local_storage = settings.localStorageEnabled.getValue() ? cef_state_t.STATE_ENABLED : cef_state_t.STATE_DISABLED;

	}
}

version(cef)
class WebViewWidget_CEF : WebViewWidgetBase {
	/++
		Create a webview that does not support opening links in new windows and uses default settings to load the given url.
	+/
	this(string url, Widget parent) {
		this(url, null, BrowserSettings.init, parent);
	}

	/++
		Full-featured constructor.
	+/
	this(string url, void delegate(scope OpenNewWindowParams) openNewWindow, BrowserSettings settings, Widget parent) {
		//semaphore = new Semaphore;
		assert(CefApp.active);

		this(new MiniguiCefClient(openNewWindow), parent, false);

		cef_window_info_t window_info;
		window_info.parent_window = containerWindow.nativeWindowHandle;

		cef_string_t cef_url = cef_string_t(url);//"http://arsdnet.net/test.html");

		cef_browser_settings_t browser_settings;
		browser_settings.size = cef_browser_settings_t.sizeof;

		settings.set(&browser_settings);

		auto got = libcef.browser_host_create_browser(&window_info, client.passable, &cef_url, &browser_settings, null, null);
	}

	/+
	~this() {
		import core.stdc.stdio;
		import core.memory;
		printf("CLEANUP %s\n", GC.inFinalizer ? "GC".ptr : "destroy".ptr);
	}
	+/

	override void dispose() {
		// sdpyPrintDebugString("closed");
		// the window is already gone so too late to do this really....
		// if(browserHandle) browserHandle.get_host.close_browser(true);

		// sdpyPrintDebugString("DISPOSE");

		if(win && win.nativeWindowHandle())
			mapping.remove(win.nativeWindowHandle());
		if(browserWindow)
			browserMapping.remove(browserWindow);

		.destroy(this); // but this is ok to do some memory management cleanup
	}

	private this(MiniguiCefClient client, Widget parent, bool isDevTools) {
		super(parent);

		this.client = client;

		flushGui();

		mapping[containerWindow.nativeWindowHandle()] = this;

		this.addEventListener(delegate(KeyDownEvent ke) {
			if(ke.key == Key.Tab)
				ke.preventDefault();
		});

		this.addEventListener((FocusEvent fe) {
			if(!browserHandle) return;

			XFocusChangeEvent ev;
			ev.type = arsd.simpledisplay.EventType.FocusIn;
			ev.display = XDisplayConnection.get;
			ev.window = ozone;
			ev.mode = NotifyModes.NotifyNormal;
			ev.detail = NotifyDetail.NotifyVirtual;

			// sdpyPrintDebugString("Sending FocusIn");

			trapXErrors( {
				XSendEvent(XDisplayConnection.get, ozone, false, 0, cast(XEvent*) &ev);
			});

			// this also works if the message is buggy and it avoids weirdness from raising window etc
			//executeJavascript("if(window.__arsdPreviouslyFocusedNode) window.__arsdPreviouslyFocusedNode.focus(); window.dispatchEvent(new FocusEvent(\"focus\"));");
		});
		this.addEventListener((BlurEvent be) {
			if(!browserHandle) return;

			XFocusChangeEvent ev;
			ev.type = arsd.simpledisplay.EventType.FocusOut;
			ev.display = XDisplayConnection.get;
			ev.window = ozone;
			ev.mode = NotifyModes.NotifyNormal;
			ev.detail = NotifyDetail.NotifyNonlinearVirtual;

			// sdpyPrintDebugString("Sending FocusOut");

			trapXErrors( {
				XSendEvent(XDisplayConnection.get, ozone, false, 0, cast(XEvent*) &ev);
			});

			//executeJavascript("if(document.activeElement) { window.__arsdPreviouslyFocusedNode = document.activeElement; document.activeElement.blur(); } window.dispatchEvent(new FocusEvent(\"blur\"));");
		});

		bool closeAttempted = false;

		if(isDevTools)
		this.parentWindow.addEventListener((scope ClosingEvent ce) {
			this.parentWindow.hide();
			ce.preventDefault();
		});
		else
		this.parentWindow.addEventListener((scope ClosingEvent ce) {
			if(devTools)
				devTools.close();
			if(browserHandle) {
				if(!closeAttempted) {
					closeAttempted = true;
					browserHandle.get_host.close_browser(false);
					ce.preventDefault();
				 	sdpyPrintDebugString("closing 1");
				} else {
					browserHandle.get_host.close_browser(true);
				 	sdpyPrintDebugString("closing 2");
				}
			}
		});
	}

	~this() {
		import core.stdc.stdio;
		printf("GC'd %p\n", cast(void*) this);
	}

	private MiniguiCefClient client;

	override void registerMovementAdditionalWork() {
		if(browserWindow) {
			// import std.stdio; writeln("new size ", width, "x", height);
			static if(UsingSimpledisplayX11) {
				XResizeWindow(XDisplayConnection.get, browserWindow, width, height);
				if(ozone) XResizeWindow(XDisplayConnection.get, ozone, width, height);
			}
			// FIXME: do for Windows too
		}
	}

	SimpleWindow browserHostWrapped;
	SimpleWindow browserWindowWrapped;
	override SimpleWindow focusableWindow() {
		if(browserWindowWrapped is null && browserWindow) {
			browserWindowWrapped = new SimpleWindow(browserWindow);
			// FIXME: this should never actually happen should it
		}
		return browserWindowWrapped;
	}

	private NativeWindowHandle browserWindow;
	private NativeWindowHandle ozone;
	private RC!cef_browser_t browserHandle;

	private static WebViewWidget[NativeWindowHandle] mapping;
	private static WebViewWidget[NativeWindowHandle] browserMapping;

	private {
		string findingText;
		bool findingCase;
	}

	// might not be stable, webview does this fully integrated
	void findText(string text, bool forward = true, bool matchCase = false, bool findNext = false) {
		if(browserHandle) {
			auto host = browserHandle.get_host();

			auto txt = cef_string_t(text);
			host.find(&txt, forward, matchCase, findNext);

			findingText = text;
			findingCase = matchCase;
		}
	}

	// ditto
	void findPrevious() {
		if(!browserHandle)
			return;
		auto host = browserHandle.get_host();
		auto txt = cef_string_t(findingText);
		host.find(&txt, 0, findingCase, 1);
	}

	// ditto
	void findNext() {
		if(!browserHandle)
			return;
		auto host = browserHandle.get_host();
		auto txt = cef_string_t(findingText);
		host.find(&txt, 1, findingCase, 1);
	}

	// ditto
	void stopFind() {
		if(!browserHandle)
			return;
		auto host = browserHandle.get_host();
		host.stop_finding(1);
	}

	override void refresh() { if(browserHandle) browserHandle.reload(); }
	override void back() { if(browserHandle) browserHandle.go_back(); }
	override void forward() { if(browserHandle) browserHandle.go_forward(); }
	override void stop() { if(browserHandle) browserHandle.stop_load(); }

	override void navigate(string url) {
		if(!browserHandle) return;
		auto s = cef_string_t(url);
		browserHandle.get_main_frame.load_url(&s);
	}

	// the url and line are for error reporting purposes
	override void executeJavascript(string code, string url = null, int line = 0) {
		if(!browserHandle) return;

		auto c = cef_string_t(code);
		auto u = cef_string_t(url);
		browserHandle.get_main_frame.execute_java_script(&c, &u, line);
	}

	private Window devTools;
	override void showDevTools() {
		if(!browserHandle) return;

		if(devTools is null) {
			auto host = browserHandle.get_host;

			if(host.has_dev_tools()) {
				host.close_dev_tools();
				return;
			}

			cef_window_info_t windowinfo;
			version(linux) {
				auto sw = new Window("DevTools");
				//sw.win.beingOpenKeepsAppOpen = false;
				devTools = sw;

				auto wv = new WebViewWidget_CEF(client, sw, true);

				sw.show();

				windowinfo.parent_window = wv.containerWindow.nativeWindowHandle;
			}
			host.show_dev_tools(&windowinfo, client.passable, null /* settings */, null /* inspect element at coordinates */);
		} else {
			if(devTools.hidden)
				devTools.show();
			else
				devTools.hide();
		}
	}

	// FYI the cef browser host also allows things like custom spelling dictionaries and getting navigation entries.

	// JS on init?
	// JS bindings?
	// user styles?
	// navigate to string? (can just use a data uri maybe?)
	// custom scheme handlers?

	// navigation callbacks to prohibit certain things or move links to new window etc?
}

version(cef) {

	//import core.sync.semaphore;
	//__gshared Semaphore semaphore;

	/+
		Finds the WebViewWidget associated with the given browser, then runs the given code in the gui thread on it.
	+/
	void runOnWebView(RC!cef_browser_t browser, void delegate(WebViewWidget) dg) nothrow {
		auto wh = cast(NativeWindowHandle) browser.get_host.get_window_handle;

		import core.thread;
		try { thread_attachThis(); } catch(Exception e) {}

		runInGuiThreadAsync({
			if(auto wvp = wh in WebViewWidget.browserMapping) {
				dg(*wvp);
			} else {
				writeln("not found ", wh, WebViewWidget.browserMapping);
			}
		});
	}

	class MiniguiCefLifeSpanHandler : CEF!cef_life_span_handler_t {
		private MiniguiCefClient client;
		this(MiniguiCefClient client) {
			this.client = client;
		}

		override void on_before_dev_tools_popup(RC!(cef_browser_t), cef_window_info_t*, cef_client_t**, cef_browser_settings_t*, cef_dictionary_value_t**, int*) nothrow {

		}

		override int on_before_popup(
			RC!cef_browser_t browser,
			RC!cef_frame_t frame,
			const(cef_string_t)* target_url,
			const(cef_string_t)* target_frame_name,
			cef_window_open_disposition_t target_disposition,
			int user_gesture,
			const(cef_popup_features_t)* popupFeatures,
			cef_window_info_t* windowInfo,
			cef_client_t** client,
			cef_browser_settings_t* browser_settings,
			cef_dictionary_value_t** extra_info,
			int* no_javascript_access
		) {
		sdpyPrintDebugString("on_before_popup");
			if(this.client.openNewWindow is null)
				return 1; // new windows disabled

			try {
				int ret;

				import core.thread;
				try { thread_attachThis(); } catch(Exception e) {}

				// FIXME: change settings here

				runInGuiThread({
					ret = 1;
					scope WebViewWidget delegate(Widget, BrowserSettings) accept = (parent, passed_settings) {
						ret = 0;
						if(parent !is null) {
							auto widget = new WebViewWidget_CEF(this.client, parent, false);
							(*windowInfo).parent_window = widget.containerWindow.nativeWindowHandle;

							passed_settings.set(browser_settings);

							return widget;
						}
						return null;
					};
					this.client.openNewWindow(OpenNewWindowParams(target_url.toGC, accept));
					return;
				});

				return ret;
			} catch(Exception e) {
				return 1;
			}
			/+
			if(!user_gesture)
				return 1; // if not created by the user, cancel it; basic popup blocking
			+/
		}
		override void on_after_created(RC!cef_browser_t browser) {
			auto handle = cast(NativeWindowHandle) browser.get_host().get_window_handle();
			auto ptr = browser.passable; // this adds to the refcount until it gets inside

			import core.thread;
			try { thread_attachThis(); } catch(Exception e) {}

			// the only reliable key (at least as far as i can tell) is the window handle
			// so gonna look that up and do the sync mapping that way.
			runInGuiThreadAsync({
				version(Windows) {
					auto parent = GetParent(handle);
				} else static if(UsingSimpledisplayX11) {
					import arsd.simpledisplay : Window;
					Window root;
					Window parent;
					Window ozone;
					uint c = 0;
					auto display = XDisplayConnection.get;
					Window* children;
					XQueryTree(display, handle, &root, &parent, &children, &c);
					if(c == 1)
						ozone = children[0];
					XFree(children);
				} else static assert(0);

				if(auto wvp = parent in WebViewWidget.mapping) {
					auto wv = *wvp;
					wv.browserWindow = handle;
					wv.browserHandle = RC!cef_browser_t(ptr);
					wv.ozone = ozone ? ozone : handle;

					wv.browserHostWrapped = new SimpleWindow(handle);
					// XSelectInput(XDisplayConnection.get, handle, EventMask.StructureNotifyMask);

					wv.browserHostWrapped.onDestroyed = delegate{
						import std.stdio; writefln("browser host %d destroyed (handle %d)", wv.browserWindowWrapped.window, wv.browserWindow);

						auto bce = new BrowserClosedEvent(wv);
						bce.dispatch();
					};

					// need this to forward key events to
					wv.browserWindowWrapped = new SimpleWindow(wv.ozone);

					/+
					XSelectInput(XDisplayConnection.get, wv.ozone, EventMask.StructureNotifyMask);
					wv.browserWindowWrapped.onDestroyed = delegate{
						import std.stdio; writefln("browser core %d destroyed (handle %d)", wv.browserWindowWrapped.window, wv.browserWindow);

						//auto bce = new BrowserClosedEvent(wv);
						//bce.dispatch();
					};
					+/

					/+
					XSelectInput(XDisplayConnection.get, ozone, EventMask.FocusChangeMask);
					wv.browserWindowWrapped.onFocusChange = (bool got) {
						import std.format;
						sdpyPrintDebugString(format("focus change %s %x", got, wv.browserWindowWrapped.impl.window));
					};
					+/

					wv.registerMovementAdditionalWork();

					WebViewWidget.browserMapping[handle] = wv;
				} else assert(0);
			});
		}
		override int do_close(RC!cef_browser_t browser) {
						import std.stdio;
						debug writeln("do_close");
			/+
			browser.runOnWebView((wv) {
				wv.browserWindowWrapped.close();
				.destroy(wv.browserHandle);
			});

			return 1;
			+/

			return 0;
		}
		override void on_before_close(RC!cef_browser_t browser) {
			import std.stdio; debug writeln("notify");
			browser.runOnWebView((wv) {
				.destroy(wv.browserHandle);
			});
			/+
			try
			semaphore.notify;
			catch(Exception e) { assert(0); }
			+/
		}
	}

	class MiniguiLoadHandler : CEF!cef_load_handler_t {
		override void on_loading_state_change(RC!(cef_browser_t) browser, int isLoading, int canGoBack, int canGoForward) {
			/+
			browser.runOnWebView((WebViewWidget wvw) {
				wvw.parentWindow.win.title = wvw.browserHandle.get_main_frame.get_url.toGCAndFree;
			});
			+/
		}
		override void on_load_start(RC!(cef_browser_t), RC!(cef_frame_t), cef_transition_type_t) {
		}
		override void on_load_error(RC!(cef_browser_t), RC!(cef_frame_t), cef_errorcode_t, const(cef_string_utf16_t)*, const(cef_string_utf16_t)*) {
		}
		override void on_load_end(RC!(cef_browser_t), RC!(cef_frame_t), int) {
		}
	}

	class MiniguiDialogHandler : CEF!cef_dialog_handler_t {
		override int on_file_dialog(RC!(cef_browser_t) browser, cef_file_dialog_mode_t mode, const(cef_string_utf16_t)* title, const(cef_string_utf16_t)* default_file_path,
			cef_string_list_t accept_filters,
			cef_string_list_t accept_extensions,
			cef_string_list_t accept_descriptions,
			RC!(cef_file_dialog_callback_t) callback)
		{
			try {
				auto ptr = callback.passable();
				browser.runOnWebView((wv) {
					getOpenFileName(wv.parentWindow, (string name) {
						auto callback = RC!cef_file_dialog_callback_t(ptr);
						auto list = libcef.string_list_alloc();
						auto item = cef_string_t(name);
						libcef.string_list_append(list, &item);
						callback.cont(list);
					}, null, null, () {
						auto callback = RC!cef_file_dialog_callback_t(ptr);
						callback.cancel();
					}, "/home/me/");
				});
			} catch(Exception e) {}

			return 1;
		}
	}

	class MiniguiDownloadHandler : CEF!cef_download_handler_t {
		override int on_before_download(
			RC!cef_browser_t browser,
			RC!cef_download_item_t download_item,
			const(cef_string_t)* suggested_name,
			RC!cef_before_download_callback_t callback
		) nothrow
		{
			// FIXME: different filename and check if exists for overwrite etc
			auto fn = cef_string_t(cast(wstring)("/home/me/Downloads/"w ~ suggested_name.str[0..suggested_name.length]));
			sdpyPrintDebugString(fn.toGC);
			callback.cont(&fn, false);

			return 1;
		}

		override void on_download_updated(
			RC!cef_browser_t browser,
			RC!cef_download_item_t download_item,
			RC!cef_download_item_callback_t cancel
		) nothrow
		{
			sdpyPrintDebugString(download_item.get_percent_complete());
			// FIXME
		}

		override int can_download(RC!(cef_browser_t), const(cef_string_utf16_t)*, const(cef_string_utf16_t)*) {
			return 1;
		}
	}

	class MiniguiKeyboardHandler : CEF!cef_keyboard_handler_t {
		override int on_pre_key_event(
			RC!(cef_browser_t) browser,
			const(cef_key_event_t)* event,
			XEvent* osEvent,
			int* isShortcut
		) nothrow {
		/+
			sdpyPrintDebugString("---pre---");
			sdpyPrintDebugString(event.focus_on_editable_field);
			sdpyPrintDebugString(event.windows_key_code);
			sdpyPrintDebugString(event.modifiers);
			sdpyPrintDebugString(event.unmodified_character);
		+/
			//*isShortcut = 1;
			return 0; // 1 if handled, which cancels sending it to browser
		}

		override int on_key_event(
			RC!(cef_browser_t) browser,
			const(cef_key_event_t)* event,
			XEvent* osEvent
		) nothrow {
		/+
			sdpyPrintDebugString("---key---");
			sdpyPrintDebugString(event.focus_on_editable_field);
			sdpyPrintDebugString(event.windows_key_code);
			sdpyPrintDebugString(event.modifiers);
		+/
			return 0; // 1 if handled
		}
	}

	class MiniguiDisplayHandler : CEF!cef_display_handler_t {
		override void on_address_change(RC!(cef_browser_t) browser, RC!(cef_frame_t), const(cef_string_utf16_t)* address) {
			auto url = address.toGC;
			browser.runOnWebView((wv) {
				wv.url = url;
			});
		}
		override void on_title_change(RC!(cef_browser_t) browser, const(cef_string_utf16_t)* title) {
			auto t = title.toGC;
			browser.runOnWebView((wv) {
				wv.title = t;
			});
		}
		override void on_favicon_urlchange(RC!(cef_browser_t) browser, cef_string_list_t urls) {
			string url;
			auto size = libcef.string_list_size(urls);
			if(size > 0) {
				cef_string_t str;
				libcef.string_list_value(urls, 0, &str);
				url = str.toGC;

				static class Thing : CEF!cef_download_image_callback_t {
					RC!cef_browser_t browserHandle;
					this(RC!cef_browser_t browser) nothrow {
						this.browserHandle = browser;
					}
					override void on_download_image_finished(const(cef_string_t)* image_url, int http_status_code, RC!cef_image_t image) nothrow {
						int width;
						int height;
						if(image.getRawPointer is null) {
							browserHandle.runOnWebView((wv) {
								wv.favicon = null;
							});
							return;
						}

						auto data = image.get_as_bitmap(1.0, cef_color_type_t.CEF_COLOR_TYPE_RGBA_8888, cef_alpha_type_t.CEF_ALPHA_TYPE_POSTMULTIPLIED, &width, &height);

						if(data.getRawPointer is null || width == 0 || height == 0) {
							browserHandle.runOnWebView((wv) {
								wv.favicon = null;
							});
						} else {
							auto s = data.get_size();
							auto buffer = new ubyte[](s);
							auto got = data.get_data(buffer.ptr, buffer.length, 0);
							auto slice = buffer[0 .. got];

							auto img = new TrueColorImage (width, height, slice);

							browserHandle.runOnWebView((wv) {
								wv.favicon = img;
							});
						}
					}
				}

				if(url.length) {
					auto callback = new Thing(browser);

					browser.get_host().download_image(&str, true, 16, 0, callback.passable);
				} else {
					browser.runOnWebView((wv) {
						wv.favicon = null;
					});
				}
			}

			browser.runOnWebView((wv) {
				wv.favicon_url = url;
			});
		}
		override void on_fullscreen_mode_change(RC!(cef_browser_t) browser, int) {
		}
		override int on_tooltip(RC!(cef_browser_t) browser, cef_string_utf16_t*) {
			return 0;
		}
		override void on_status_message(RC!(cef_browser_t) browser, const(cef_string_utf16_t)* msg) {
			auto status = msg.toGC;
			browser.runOnWebView((wv) {
				wv.status = status;
			});
		}
		override void on_loading_progress_change(RC!(cef_browser_t) browser, double progress) {
			// progress is from 0.0 to 1.0
			browser.runOnWebView((wv) {
				wv.loadingProgress = cast(int) (progress * 100);
			});
		}
		override int on_console_message(RC!(cef_browser_t), cef_log_severity_t, const(cef_string_utf16_t)*, const(cef_string_utf16_t)*, int) {
			return 1; // 1 means to suppress it being automatically output
		}
		override int on_auto_resize(RC!(cef_browser_t), const(cef_size_t)*) {
			return 0;
		}
		override int on_cursor_change(RC!(cef_browser_t), cef_cursor_handle_t, cef_cursor_type_t, const(cef_cursor_info_t)*) {
			return 0;
		}
		override void on_media_access_change(RC!(cef_browser_t), int, int) {

		}
	}

	class MiniguiRequestHandler : CEF!cef_request_handler_t {

		override int on_render_process_unresponsive(RC!(cef_browser_t), RC!(cef_unresponsive_process_callback_t)) nothrow {
			return 0;
		}
		override void on_render_process_responsive(RC!(cef_browser_t) p) nothrow {

		}

		override int on_before_browse(RC!(cef_browser_t), RC!(cef_frame_t), RC!(cef_request_t), int, int) nothrow {
			return 0;
		}
		override int on_open_urlfrom_tab(RC!(cef_browser_t), RC!(cef_frame_t), const(cef_string_utf16_t)*, cef_window_open_disposition_t, int) nothrow {
			return 0;
		}
		override cef_resource_request_handler_t* get_resource_request_handler(RC!(cef_browser_t), RC!(cef_frame_t), RC!(cef_request_t), int, int, const(cef_string_utf16_t)*, int*) nothrow {
			return null;
		}
		override int get_auth_credentials(RC!(cef_browser_t), const(cef_string_utf16_t)*, int, const(cef_string_utf16_t)*, int, const(cef_string_utf16_t)*, const(cef_string_utf16_t)*, RC!(cef_auth_callback_t)) nothrow {
			// this is for http basic auth popup.....
			return 0;
		}
		override int on_certificate_error(RC!(cef_browser_t), cef_errorcode_t, const(cef_string_utf16_t)*, RC!(cef_sslinfo_t), RC!(cef_callback_t)) nothrow {
			return 0;
		}
		override int on_select_client_certificate(RC!(cef_browser_t), int, const(cef_string_utf16_t)*, int, ulong, cef_x509certificate_t**, RC!(cef_select_client_certificate_callback_t)) nothrow {
			return 0;
		}
		override void on_render_view_ready(RC!(cef_browser_t) p) nothrow {

		}
		override void on_render_process_terminated(RC!(cef_browser_t), cef_termination_status_t, int error_code, const(cef_string_utf16_t)*) nothrow {

		}
		override void on_document_available_in_main_frame(RC!(cef_browser_t) browser) nothrow {
			browser.runOnWebView(delegate(wv) {
				wv.executeJavascript("console.log('here');");
			});

		}
	}

	class MiniguiContextMenuHandler : CEF!cef_context_menu_handler_t {
		private MiniguiCefClient client;
		this(MiniguiCefClient client) {
			this.client = client;
		}

		override void on_before_context_menu(RC!(cef_browser_t) browser, RC!(cef_frame_t) frame, RC!(cef_context_menu_params_t) params, RC!(cef_menu_model_t) model) nothrow {
			// FIXME: should i customize these? it is kinda specific to my browser
			int itemNo;

			void addItem(string label, int commandNo) {
				auto lbl = cef_string_t(label);
				model.insert_item_at(/* index */ itemNo, /* command id */ cef_menu_id_t.MENU_ID_USER_FIRST + commandNo, &lbl);
				itemNo++;
			}

			void addSeparator() {
				model.insert_separator_at(itemNo);
				itemNo++;
			}

			auto flags = params.get_type_flags();

			if(flags & cef_context_menu_type_flags_t.CM_TYPEFLAG_LINK) {
				// cef_string_userfree_t linkUrl = params.get_unfiltered_link_url();
				// toGCAndFree
				addItem("Open link in new window", 1);
				addItem("Copy link URL", 2);

				// FIXME: open in other browsers
				// FIXME: open in ytv
				addSeparator();
			}

			if(flags & cef_context_menu_type_flags_t.CM_TYPEFLAG_MEDIA) {
				// cef_string_userfree_t linkUrl = params.get_source_url();
				// toGCAndFree
				addItem("Open media in new window", 3);
				addItem("Copy source URL", 4);
				addItem("Download media", 5);
				addSeparator();
			}


			// get_page_url
			// get_title_text
			// has_image_contents ???
			// get_source_url
			// get_xcoord and get_ycoord
			// get_selection_text

		}
		override int run_context_menu(RC!(cef_browser_t), RC!(cef_frame_t), RC!(cef_context_menu_params_t), RC!(cef_menu_model_t), RC!(cef_run_context_menu_callback_t)) nothrow {
			// could do a custom display here if i want but i think it is good enough as it is
			return 0;
		}
		override int on_context_menu_command(RC!(cef_browser_t) browser, RC!(cef_frame_t) frame, RC!(cef_context_menu_params_t) params, int commandId, cef_event_flags_t flags) nothrow {
			switch(commandId) {
				case cef_menu_id_t.MENU_ID_USER_FIRST + 1: // open link in new window
					auto what = params.get_unfiltered_link_url().toGCAndFree();

					browser.runOnWebView((widget) {
						auto event = new NewWindowRequestedEvent(what, widget);
						event.dispatch();
					});
					return 1;
				case cef_menu_id_t.MENU_ID_USER_FIRST + 2: // copy link url
					auto what = params.get_link_url().toGCAndFree();

					browser.runOnWebView((widget) {
						auto event = new CopyRequestedEvent(what, widget);
						event.dispatch();
					});
					return 1;
				case cef_menu_id_t.MENU_ID_USER_FIRST + 3: // open media in new window
					auto what = params.get_source_url().toGCAndFree();

					browser.runOnWebView((widget) {
						auto event = new NewWindowRequestedEvent(what, widget);
						event.dispatch();
					});
					return 1;
				case cef_menu_id_t.MENU_ID_USER_FIRST + 4: // copy source url
					auto what = params.get_source_url().toGCAndFree();

					browser.runOnWebView((widget) {
						auto event = new CopyRequestedEvent(what, widget);
						event.dispatch();
					});
					return 1;
				case cef_menu_id_t.MENU_ID_USER_FIRST + 5: // download media
					auto str = cef_string_t(params.get_source_url().toGCAndFree());
					browser.get_host().start_download(&str);
					return 1;
				default:
					return 0;
			}
		}
		override void on_context_menu_dismissed(RC!(cef_browser_t), RC!(cef_frame_t)) nothrow {
			// to close the custom display
		}

		override int run_quick_menu(RC!(cef_browser_t), RC!(cef_frame_t), const(cef_point_t)*, const(cef_size_t)*, cef_quick_menu_edit_state_flags_t, RC!(cef_run_quick_menu_callback_t)) nothrow {
			return 0;
		}
		override int on_quick_menu_command(RC!(cef_browser_t), RC!(cef_frame_t), int, cef_event_flags_t) nothrow {
			return 0;
		}
		override void on_quick_menu_dismissed(RC!(cef_browser_t), RC!(cef_frame_t)) nothrow {

		}
	}

	class MiniguiFocusHandler : CEF!cef_focus_handler_t {
		override void on_take_focus(RC!(cef_browser_t) browser, int next) nothrow {
			// sdpyPrintDebugString("taking");
			browser.runOnWebView(delegate(wv) {
				Widget f;
				if(next) {
					f = Window.getFirstFocusable(wv.parentWindow);
				} else {
					foreach(w; &wv.parentWindow.focusableWidgets) {
						if(w is wv)
							break;
						f = w;
					}
				}
				if(f)
					f.focus();
			});
		}
		override int on_set_focus(RC!(cef_browser_t) browser, cef_focus_source_t source) nothrow {
			/+
			browser.runOnWebView((ev) {
				ev.focus(); // even this can steal focus from other parts of my application!
			});
			+/
			// sdpyPrintDebugString("setting");

			// if either the parent window or the ozone window has the focus, we
			// can redirect it to the input focus. CEF calls this method sometimes
			// before setting the focus (where return 1 can override) and sometimes
			// after... which is totally inappropriate for it to do but it does anyway
			// and we want to undo the damage of this.
			browser.runOnWebView((ev) {
				arsd.simpledisplay.Window focus_window;
				int revert_to_return;
				XGetInputFocus(XDisplayConnection.get, &focus_window, &revert_to_return);
				if(focus_window is ev.parentWindow.win.impl.window || focus_window is ev.ozone) {
					// refocus our correct input focus
					ev.parentWindow.win.focus();
					XSync(XDisplayConnection.get, 0);

					// and then tell the chromium thing it still has it
					// so it will think it got it, lost it, then got it again
					// and hopefully not try to get it again
					XFocusChangeEvent eve;
					eve.type = arsd.simpledisplay.EventType.FocusIn;
					eve.display = XDisplayConnection.get;
					eve.window = ev.ozone;
					eve.mode = NotifyModes.NotifyNormal;
					eve.detail = NotifyDetail.NotifyVirtual;

					// sdpyPrintDebugString("Sending FocusIn hack here");

					trapXErrors( {
						XSendEvent(XDisplayConnection.get, ev.ozone, false, 0, cast(XEvent*) &eve);
					});

				}
			});

			return 1; // otherwise, cancel because this bullshit tends to steal focus from other applications and i never, ever, ever want that to happen.
			// seems to happen because of race condition in it getting a focus event and then stealing the focus from the parent
			// even though things work fine if i always cancel except
			// it still keeps the decoration assuming focus though even though it doesn't have it which is kinda fucked up but meh
			// it also breaks its own pop up menus and drop down boxes to allow this! wtf
		}
		override void on_got_focus(RC!(cef_browser_t) browser) nothrow {
			// sdpyPrintDebugString("got");
			browser.runOnWebView((ev) {
				// this sometimes steals from the app too but it is relatively acceptable
				// steals when i mouse in from the side of the window quickly, but still
				// i want the minigui state to match so i'll allow it

				//if(ev.parentWindow) ev.parentWindow.focus();
				ev.focus();
			});
		}
	}

	class MiniguiCefClient : CEF!cef_client_t {

		void delegate(scope OpenNewWindowParams) openNewWindow;

		MiniguiCefLifeSpanHandler lsh;
		MiniguiLoadHandler loadHandler;
		MiniguiDialogHandler dialogHandler;
		MiniguiDisplayHandler displayHandler;
		MiniguiDownloadHandler downloadHandler;
		MiniguiKeyboardHandler keyboardHandler;
		MiniguiFocusHandler focusHandler;
		MiniguiRequestHandler requestHandler;
		MiniguiContextMenuHandler contextMenuHandler;
		this(void delegate(scope OpenNewWindowParams) openNewWindow) {
			this.openNewWindow = openNewWindow;
			lsh = new MiniguiCefLifeSpanHandler(this);
			loadHandler = new MiniguiLoadHandler();
			dialogHandler = new MiniguiDialogHandler();
			displayHandler = new MiniguiDisplayHandler();
			downloadHandler = new MiniguiDownloadHandler();
			keyboardHandler = new MiniguiKeyboardHandler();
			focusHandler = new MiniguiFocusHandler();
			requestHandler = new MiniguiRequestHandler();
			contextMenuHandler = new MiniguiContextMenuHandler(this);
		}

		override cef_audio_handler_t* get_audio_handler() {
			return null;
		}
		override cef_context_menu_handler_t* get_context_menu_handler() {
			return contextMenuHandler.returnable;
		}
		override cef_dialog_handler_t* get_dialog_handler() {
			return dialogHandler.returnable;
		}
		override cef_display_handler_t* get_display_handler() {
			return displayHandler.returnable;
		}
		override cef_download_handler_t* get_download_handler() {
			return downloadHandler.returnable;
		}
		override cef_drag_handler_t* get_drag_handler() {
			return null;
		}
		override cef_find_handler_t* get_find_handler() {
			return null;
		}
		override cef_focus_handler_t* get_focus_handler() {
			return focusHandler.returnable;
		}
		override cef_jsdialog_handler_t* get_jsdialog_handler() {
			// needed for alert etc.
			return null;
		}
		override cef_keyboard_handler_t* get_keyboard_handler() {
			// this can handle keyboard shortcuts etc
			return keyboardHandler.returnable;
		}
		override cef_life_span_handler_t* get_life_span_handler() {
			return lsh.returnable;
		}
		override cef_load_handler_t* get_load_handler() {
			return loadHandler.returnable;
		}
		override cef_render_handler_t* get_render_handler() {
			// this thing might work for an off-screen thing
			// like to an image or to a video stream maybe
			//
			// might be useful to have it render here then send it over too for remote X sharing a process
			return null;
		}
		override cef_request_handler_t* get_request_handler() {
			return requestHandler.returnable;
		}
		override int on_process_message_received(RC!cef_browser_t, RC!cef_frame_t, cef_process_id_t, RC!cef_process_message_t) {
			return 0; // return 1 if you can actually handle the message
		}
		override cef_frame_handler_t* get_frame_handler() nothrow {
			return null;
		}
		override cef_print_handler_t* get_print_handler() nothrow {
			return null;
		}

		override cef_command_handler_t* get_command_handler() {
			return null;
		}

		override cef_permission_handler_t* get_permission_handler() {
			return null;
		}

	}
}

class BrowserClosedEvent : Event {
	enum EventString = "browserclosed";

	this(Widget target) { super(EventString, target); }
	override bool cancelable() const { return false; }
}

class CopyRequestedEvent : Event {
	enum EventString = "browsercopyrequested";

	string what;

	this(string what, Widget target) { this.what = what; super(EventString, target); }
	override bool cancelable() const { return false; }
}

class NewWindowRequestedEvent : Event {
	enum EventString = "browserwindowrequested";

	string url;

	this(string url, Widget target) { this.url = url; super(EventString, target); }
	override bool cancelable() const { return false; }
}



/+
pragma(mangle, "_ZN12CefWindowX115FocusEv")
//pragma(mangle, "_ZN3x116XProto13SetInputFocusERKNS_20SetInputFocusRequestE")
extern(C++)
export void _ZN12CefWindowX115FocusEv() {
	sdpyPrintDebugString("OVERRIDDEN");
}
+/
