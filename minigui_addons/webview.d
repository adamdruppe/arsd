/++
	A webview (based on [arsd.webview]) for minigui.

	For now at least, to use this, you MUST have a [WebViewApp] in scope in main for the duration of your gui application.

	Warning: CEF spams the current directory with a bunch of files and directories. You might want to run your program in a dedicated location.

	History:
		Added November 5, 2021. NOT YET STABLE.

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
module minigui_addons.webview;
// FIXME: i think i can download the cef automatically if needed.

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
	private RC!ICoreWebView2Environment webview_env;
	private RC!ICoreWebView2Controller controller;

	private bool initialized;

	this(string url, void delegate(scope OpenNewWindowParams) openNewWindow, BrowserSettings settings, Widget parent) {
		// FIXME: openNewWindow
		super(parent);
		// that ctor sets containerWindow

		Wv2App.useEnvironment((env) {
			env.CreateCoreWebView2Controller(containerWindow.impl.hwnd,
				callback!(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)(delegate(error, controller_raw) {
					if(error || controller_raw is null)
						return error;

					// need to keep this beyond the callback or we're doomed.
					controller = RC!ICoreWebView2Controller(controller_raw);

					webview_window = controller.CoreWebView2;

					webview_window.add_DocumentTitleChanged((sender, args) {
						this.title = toGC(&sender.get_DocumentTitle);
						return S_OK;
					});

					// add_HistoryChanged
					// that's where CanGoBack and CanGoForward can be rechecked.

					RC!ICoreWebView2Settings Settings = webview_window.Settings;
					Settings.IsScriptEnabled = TRUE;
					Settings.AreDefaultScriptDialogsEnabled = TRUE;
					Settings.IsWebMessageEnabled = TRUE;


					auto ert = webview_window.add_NavigationStarting(
						delegate (sender, args) {
							this.url = toGC(&args.get_Uri);
							return S_OK;
						});

					RECT bounds;
					GetClientRect(containerWindow.impl.hwnd, &bounds);
					controller.Bounds = bounds;
					//error = webview_window.Navigate("http://arsdnet.net/test.html"w.ptr);
					//error = webview_window.NavigateToString("<html><body>Hello</body></html>"w.ptr);
					//error = webview_window.Navigate("http://192.168.1.10/"w.ptr);

					WCharzBuffer bfr = WCharzBuffer(url);
					webview_window.Navigate(bfr.ptr);

					controller.IsVisible = true;

					initialized = true;

					return S_OK;
				}));
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

		this(new MiniguiCefClient(openNewWindow), parent);

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

	private this(MiniguiCefClient client, Widget parent) {
		super(parent);

		this.client = client;

		flushGui();

		mapping[containerWindow.nativeWindowHandle()] = this;


		this.parentWindow.addEventListener((FocusEvent fe) {
			if(!browserHandle) return;
			//browserHandle.get_host.set_focus(true);

			executeJavascript("if(window.__arsdPreviouslyFocusedNode) window.__arsdPreviouslyFocusedNode.focus(); window.dispatchEvent(new FocusEvent(\"focus\"));");
		});
		this.parentWindow.addEventListener((BlurEvent be) {
			if(!browserHandle) return;

			executeJavascript("if(document.activeElement) { window.__arsdPreviouslyFocusedNode = document.activeElement; document.activeElement.blur(); } window.dispatchEvent(new FocusEvent(\"blur\"));");
		});

		bool closeAttempted = false;

		this.parentWindow.addEventListener((scope ClosingEvent ce) {
			if(!closeAttempted && browserHandle) {
				browserHandle.get_host.close_browser(true);
				ce.preventDefault();
				// sdpyPrintDebugString("closing");
			}
			closeAttempted = true;
		});
	}

	private MiniguiCefClient client;

	override void registerMovementAdditionalWork() {
		if(browserWindow) {
			static if(UsingSimpledisplayX11)
				XResizeWindow(XDisplayConnection.get, browserWindow, width, height);
			// FIXME: do for Windows too
		}
	}

	SimpleWindow browserWindowWrapped;
	override SimpleWindow focusableWindow() {
		if(browserWindowWrapped is null && browserWindow)
			browserWindowWrapped = new SimpleWindow(browserWindow);
		return browserWindowWrapped;
	}

	private NativeWindowHandle browserWindow;
	private RC!cef_browser_t browserHandle;

	private static WebViewWidget[NativeWindowHandle] mapping;
	private static WebViewWidget[NativeWindowHandle] browserMapping;

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

	override void showDevTools() {
		if(!browserHandle) return;
		browserHandle.get_host.show_dev_tools(null /* window info */, client.passable, null /* settings */, null /* inspect element at coordinates */);
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
				//writeln("not found ", wh, WebViewWidget.browserMapping);
			}
		});
	}

	class MiniguiCefLifeSpanHandler : CEF!cef_life_span_handler_t {
		private MiniguiCefClient client;
		this(MiniguiCefClient client) {
			this.client = client;
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
							auto widget = new WebViewWidget_CEF(this.client, parent);
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
					uint c = 0;
					auto display = XDisplayConnection.get;
					Window* children;
					XQueryTree(display, handle, &root, &parent, &children, &c);
					XFree(children);
				} else static assert(0);

				if(auto wvp = parent in WebViewWidget.mapping) {
					auto wv = *wvp;
					wv.browserWindow = handle;
					wv.browserHandle = RC!cef_browser_t(ptr);

					wv.browserWindowWrapped = new SimpleWindow(wv.browserWindow);
					/+
					XSelectInput(XDisplayConnection.get, handle, EventMask.FocusChangeMask);
					
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
			browser.runOnWebView((wv) {
				auto bce = new BrowserClosedEvent(wv);
				bce.dispatch();
			});
			return 1;
		}
		override void on_before_close(RC!cef_browser_t browser) {
			/+
			import std.stdio; debug writeln("notify");
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

		override int on_file_dialog(RC!(cef_browser_t) browser, cef_file_dialog_mode_t mode, const(cef_string_utf16_t)* title, const(cef_string_utf16_t)* default_file_path, cef_string_list_t accept_filters, int selected_accept_filter, RC!(cef_file_dialog_callback_t) callback) {
			try {
				auto ptr = callback.passable();
				browser.runOnWebView((wv) {
					getOpenFileName((string name) {
						auto callback = RC!cef_file_dialog_callback_t(ptr);
						auto list = libcef.string_list_alloc();
						auto item = cef_string_t(name);
						libcef.string_list_append(list, &item);
						callback.cont(selected_accept_filter, list);
					}, null, null, () {
						auto callback = RC!cef_file_dialog_callback_t(ptr);
						callback.cancel();
					});
				});
			} catch(Exception e) {}

			return 1;
		}
	}

	class MiniguiDownloadHandler : CEF!cef_download_handler_t {
		override void on_before_download(
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
			return 0; // 1 means to suppress it being automatically output
		}
		override int on_auto_resize(RC!(cef_browser_t), const(cef_size_t)*) {
			return 0;
		}
		override int on_cursor_change(RC!(cef_browser_t), cef_cursor_handle_t, cef_cursor_type_t, const(cef_cursor_info_t)*) {
			return 0;
		}
	}

	class MiniguiFocusHandler : CEF!cef_focus_handler_t {
		override void on_take_focus(RC!(cef_browser_t) browser, int next) nothrow {
			// sdpyPrintDebugString("take");
		}
		override int on_set_focus(RC!(cef_browser_t) browser, cef_focus_source_t source) nothrow {
			/+
			browser.runOnWebView((ev) {
			sdpyPrintDebugString("setting");
				ev.parentWindow.focusedWidget = ev;
			});
			+/

			return 1; // otherwise, cancel because this bullshit tends to steal focus from other applications and i never, ever, ever want that to happen.
			// seems to happen because of race condition in it getting a focus event and then stealing the focus from the parent
			// even though things work fine if i always cancel except
			// it still keeps the decoration assuming focus though even though it doesn't have it which is kinda fucked up but meh
			// it also breaks its own pop up menus and drop down boxes to allow this! wtf
		}
		override void on_got_focus(RC!(cef_browser_t) browser) nothrow {
			// sdpyPrintDebugString("got");
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
		this(void delegate(scope OpenNewWindowParams) openNewWindow) {
			this.openNewWindow = openNewWindow;
			lsh = new MiniguiCefLifeSpanHandler(this);
			loadHandler = new MiniguiLoadHandler();
			dialogHandler = new MiniguiDialogHandler();
			displayHandler = new MiniguiDisplayHandler();
			downloadHandler = new MiniguiDownloadHandler();
			keyboardHandler = new MiniguiKeyboardHandler();
			focusHandler = new MiniguiFocusHandler();
		}

		override cef_audio_handler_t* get_audio_handler() {
			return null;
		}
		override cef_context_menu_handler_t* get_context_menu_handler() {
			return null;
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
			return null;
		}
		override cef_request_handler_t* get_request_handler() {
			return null;
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

	}
}

class BrowserClosedEvent : Event {
	enum EventString = "browserclosed";

	this(Widget target) { super(EventString, target); }
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
