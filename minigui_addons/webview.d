/++
	A webview (based on [arsd.webview]) for minigui.

	For now at least, to use this, you MUST have a CefApp in scope in main for the duration of your gui application.

	History:
		Added November 5, 2021. NOT YET STABLE.
+/
module minigui_addons.webview;

version(linux)
	version=cef;
version(Windows)
	version=wv2;


class StateChanged(alias field) : Event {
	enum EventString = __traits(identifier, __traits(parent, field)) ~ "." ~ __traits(identifier, field) ~ ":change";
	override bool cancelable() const { return false; }
	this(Widget target, typeof(field) newValue) {
		this.newValue = newValue;
		super(EventString, target);
	}

	typeof(field) newValue;
}

void addWhenTriggered(Widget w, void delegate() dg) {
	w.addEventListener("triggered", dg);
}

mixin template Observable(T, string name) {
	private T backing;

	mixin(q{
		void } ~ name ~ q{_changed (void delegate(T) dg) {
			this.addEventListener((StateChanged!this_thing ev) {
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

/+
	SPA mode: put favicon on top level window, no other user controls at top level, links to different domains always open in new window.
+/

// FIXME: look in /opt/cef for the dll and the locales

import arsd.minigui;
import arsd.webview;

version(wv2)
	alias WebViewWidget = WebViewWidget_WV2;
else version(cef)
	alias WebViewWidget = WebViewWidget_CEF;
else static assert(0, "no webview available");

class WebViewWidgetBase : NestedChildWindowWidget {
	protected SimpleWindow containerWindow;

	protected this(Widget parent) {
		containerWindow = new SimpleWindow(640, 480, null, OpenGlOptions.no, Resizability.allowResizing, WindowTypes.nestedChild, WindowFlags.normal, getParentWindow(parent));

		super(containerWindow, parent);
	}

	mixin Observable!(string, "title");
	mixin Observable!(string, "url");
	mixin Observable!(string, "status");
	mixin Observable!(int, "loadingProgress");

	abstract void refresh();
	abstract void back();
	abstract void forward();
	abstract void stop();

	abstract void navigate(string url);

	// the url and line are for error reporting purposes
	abstract void executeJavascript(string code, string url = null, int line = 0);

	abstract void showDevTools();

	// this is implemented as a do-nothing in the NestedChildWindowWidget base
	// but you will almost certainly need to override it in implementations.
	// abstract void registerMovementAdditionalWork();
}


version(wv2)
class WebViewWidget_WV2 : WebViewWidgetBase {
	private RC!ICoreWebView2 webview_window;
	private RC!ICoreWebView2Environment webview_env;
	private RC!ICoreWebView2Controller controller;

	private bool initialized;

	this(Widget parent) {
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

					RC!ICoreWebView2Settings Settings = webview_window.Settings;
					Settings.IsScriptEnabled = TRUE;
					Settings.AreDefaultScriptDialogsEnabled = TRUE;
					Settings.IsWebMessageEnabled = TRUE;


					auto ert = webview_window.add_NavigationStarting(
						delegate (sender, args) {
							wchar* t;
							args.get_Uri(&t);
							auto ot = t;

							string s;

							while(*t) {
								s ~= *t;
								t++;
							}

							this.url = s;

							CoTaskMemFree(ot);

							return S_OK;
						});

					RECT bounds;
					GetClientRect(containerWindow.impl.hwnd, &bounds);
					controller.Bounds = bounds;
					error = webview_window.Navigate("http://arsdnet.net/test.html"w.ptr);
					//error = webview_window.NavigateToString("<html><body>Hello</body></html>"w.ptr);
					//error = webview_window.Navigate("http://192.168.1.10/"w.ptr);

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

version(cef)
class WebViewWidget_CEF : WebViewWidgetBase {
	this(Widget parent) {
		//semaphore = new Semaphore;
		assert(CefApp.active);

		super(parent);

		flushGui();

		mapping[containerWindow.nativeWindowHandle()] = this;

		cef_window_info_t window_info;
		window_info.parent_window = containerWindow.nativeWindowHandle;

		cef_string_t cef_url = cef_string_t("http://arsdnet.net/test.html");

		cef_browser_settings_t browser_settings;
		browser_settings.size = cef_browser_settings_t.sizeof;

		client = new MiniguiCefClient();

		auto got = libcef.browser_host_create_browser(&window_info, client.passable, &cef_url, &browser_settings, null, null);

		/+
		containerWindow.closeQuery = delegate() {
			browserHandle.get_host.close_browser(true);
			//containerWindow.close();
		};
		+/

	}

	private MiniguiCefClient client;

	/+
	override void close() {
		// FIXME: this should prolly be on the onclose event instead
		mapping.remove[win.nativeWindowHandle()];
		super.close();
	}
	+/

	override void registerMovementAdditionalWork() {
		if(browserWindow) {
			static if(UsingSimpledisplayX11)
				XResizeWindow(XDisplayConnection.get, browserWindow, width, height);
			// FIXME: do for Windows too
		}
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
		runInGuiThreadAsync({
			if(auto wvp = wh in WebViewWidget.browserMapping) {
				dg(*wvp);
			} else {
				//writeln("not found ", wh, WebViewWidget.browserMapping);
			}
		});
	}

	class MiniguiCefLifeSpanHandler : CEF!cef_life_span_handler_t {
		override int on_before_popup(RC!cef_browser_t, RC!cef_frame_t, const(cef_string_utf16_t)*, const(cef_string_utf16_t)*, cef_window_open_disposition_t, int, const(cef_popup_features_t)*, cef_window_info_t*, cef_client_t**, cef_browser_settings_t*, cef_dictionary_value_t**, int*) {
			return 0;
		}
		override void on_after_created(RC!cef_browser_t browser) {
			auto handle = cast(NativeWindowHandle) browser.get_host().get_window_handle();
			auto ptr = browser.passable; // this adds to the refcount until it gets inside

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

					wv.registerMovementAdditionalWork();

					WebViewWidget.browserMapping[handle] = wv;
				} else assert(0);
			});
		}
		override int do_close(RC!cef_browser_t browser) {
			return 0;
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
				runInGuiThreadAsync({
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
		override void on_favicon_urlchange(RC!(cef_browser_t) browser, cef_string_list_t) {
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

	class MiniguiCefClient : CEF!cef_client_t {
		MiniguiCefLifeSpanHandler lsh;
		MiniguiLoadHandler loadHandler;
		MiniguiDialogHandler dialogHandler;
		MiniguiDisplayHandler displayHandler;
		this() {
			lsh = new MiniguiCefLifeSpanHandler();
			loadHandler = new MiniguiLoadHandler();
			dialogHandler = new MiniguiDialogHandler();
			displayHandler = new MiniguiDisplayHandler();
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
			return null;
		}
		override cef_drag_handler_t* get_drag_handler() {
			return null;
		}
		override cef_find_handler_t* get_find_handler() {
			return null;
		}
		override cef_focus_handler_t* get_focus_handler() {
			return null;
		}
		override cef_jsdialog_handler_t* get_jsdialog_handler() {
			// needed for alert etc.
			return null;
		}
		override cef_keyboard_handler_t* get_keyboard_handler() {
			// this can handle keyboard shortcuts etc
			return null;
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
