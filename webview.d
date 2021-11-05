/++
	A thin wrapper around common system webviews.
	Based on: https://github.com/zserge/webview

	Work in progress. DO NOT USE YET as I am prolly gonna break everything.
+/
module arsd.webview;

// FIXME: I think dynamic loading cef might not be that bad; there's only a handful
// of top level functions. will want to explore.

// Please note; the Microsoft terms and conditions say they may be able to collect
// information about your users if you use this on Windows.
// see: https://developer.microsoft.com/en-us/microsoft-edge/webview2/

// https://go.microsoft.com/fwlink/p/?LinkId=2124703


version(cef) {
import arsd.simpledisplay;

pragma(lib, "cef");

class MyCefClient : CEF!cef_client_t {
	MyCefLifeSpanHandler lsh;
	this() {
		lsh = new MyCefLifeSpanHandler();
	}

	override _cef_audio_handler_t* get_audio_handler() {
		return null;
	}
	override _cef_context_menu_handler_t* get_context_menu_handler() {
		return null;
	}
	override _cef_dialog_handler_t* get_dialog_handler() {
		return null;
	}
	override _cef_display_handler_t* get_display_handler() {
		return null;
	}
	override _cef_download_handler_t* get_download_handler() {
		return null;
	}
	override _cef_drag_handler_t* get_drag_handler() {
		return null;
	}
	override _cef_find_handler_t* get_find_handler() {
		return null;
	}
	override _cef_focus_handler_t* get_focus_handler() {
		return null;
	}
	override _cef_jsdialog_handler_t* get_jsdialog_handler() {
		return null;
	}
	override _cef_keyboard_handler_t* get_keyboard_handler() {
		return null;
	}
	override _cef_life_span_handler_t* get_life_span_handler() {
		return lsh.returnable;
	}
	override _cef_load_handler_t* get_load_handler() {
		return null;
	}
	override _cef_render_handler_t* get_render_handler() {
		return null;
	}
	override _cef_request_handler_t* get_request_handler() {
		return null;
	}
	override int on_process_message_received(RC!_cef_browser_t, RC!_cef_frame_t, cef_process_id_t, RC!_cef_process_message_t) {
		// FIXME: supposed to release references
		return 0; // return 1 if you can actually handle the message
	}
}

// FIXME: make a CefStruct thing that refcounts and just forwards automatically for the parameters.

class MyCefLifeSpanHandler : CEF!cef_life_span_handler_t {
	override int on_before_popup(RC!_cef_browser_t, RC!_cef_frame_t, const(_cef_string_utf16_t)*, const(_cef_string_utf16_t)*, cef_window_open_disposition_t, int, const(_cef_popup_features_t)*, _cef_window_info_t*, _cef_client_t**, _cef_browser_settings_t*, _cef_dictionary_value_t**, int*) {
		// FIXME: supposed to release references
		return 0;
	}
	override void on_after_created(RC!_cef_browser_t browser) {
	/*
		auto frame = browser.get_main_frame();
		cef_string_t omg = cef_string_t("http://dpldocs.info"w);
		frame.load_url(frame, &omg);
	*/
	}
	override int do_close(RC!_cef_browser_t browser) {
		return 0;
	}
	override void on_before_close(RC!_cef_browser_t browser) {
	}
}

class BrowserProcessHandler : CEF!cef_browser_process_handler_t {
	override void get_cookieable_schemes(void*, int* includeDefaults) { *includeDefaults = 1; }
	override void on_context_initialized() { }
	override _cef_print_handler_t* get_print_handler() {
		return null;
	}

	override void on_before_child_process_launch(RC!_cef_command_line_t) { }
	override void on_schedule_message_pump_work(long delayMs) { }
	override _cef_client_t* get_default_client() { return null; }
}


int cefProcessHelper() {
	import core.runtime;
	import core.stdc.stdlib;

	cef_main_args_t main_args;
	main_args.argc = Runtime.cArgs.argc;
	main_args.argv = Runtime.cArgs.argv;

	int code = cef_execute_process(&main_args, null, null);
	if(code >= 0)
		exit(code);
	return code;
}

shared static this() {
	cefProcessHelper();
}

struct CefApp {
	@disable this(this);
	@disable new();
	this(void delegate(cef_settings_t* settings) setSettings) {
		import core.runtime;
		import core.stdc.stdlib;

		cef_main_args_t main_args;
		main_args.argc = Runtime.cArgs.argc;
		main_args.argv = Runtime.cArgs.argv;

		cef_settings_t settings;
		settings.size = cef_settings_t.sizeof;
		settings.log_severity = cef_log_severity_t.LOGSEVERITY_DISABLE; // Show only warnings/errors
		//settings.log_severity = cef_log_severity_t.LOGSEVERITY_WARNING; // Show only warnings/errors
		//settings.external_message_pump = 1;
		settings.multi_threaded_message_loop = 1;
		settings.no_sandbox = 1;

		if(setSettings !is null)
			setSettings(&settings);


		auto app = new class CEF!cef_app_t {
			BrowserProcessHandler bph;
			this() {
				bph = new BrowserProcessHandler();
			}
			override void on_before_command_line_processing(const(cef_string_t)*, RC!cef_command_line_t) {}

			override _cef_resource_bundle_handler_t* get_resource_bundle_handler() {
				return null;
			}
			override _cef_browser_process_handler_t* get_browser_process_handler() {
				return bph.returnable;
			}
			override _cef_render_process_handler_t* get_render_process_handler() {
				return null;
			}
			override void on_register_custom_schemes(_cef_scheme_registrar_t*) {

			}
		};

		if(!cef_initialize(&main_args, &settings, app.passable, null)) {
			throw new Exception("cef_initialize failed");
		}
	}

	~this() {
		cef_shutdown();
	}
}


void main() {
	auto app = CefApp(null);

	auto window = new SimpleWindow(640, 480, "D Browser", Resizability.allowResizing);
	flushGui;

	cef_window_info_t window_info;
	/*
	window_info.x = 100;
	window_info.y = 100;
	window_info.width = 300;
	window_info.height = 300;
	*/
	//window_info.parent_window = window.nativeWindowHandle;

	cef_string_t cef_url = cef_string_t("http://youtube.com/"w);

	//string url = "http://arsdnet.net/";
	//cef_string_utf8_to_utf16(url.ptr, url.length, &cef_url);

	cef_browser_settings_t browser_settings;
	browser_settings.size = cef_browser_settings_t.sizeof;

	auto client = new MyCefClient();

	auto got = cef_browser_host_create_browser(&window_info, client.passable, &cef_url, &browser_settings, null, null); // or _sync

	window.eventLoop(0);
}
}

version(linux_gtk)
version(Demo)
void main() {
	auto wv = new WebView(true, null);
	wv.navigate("http://dpldocs.info/");
	wv.setTitle("omg a D webview");
	wv.setSize(500, 500, true);
	wv.eval("console.log('just testing');");
	wv.run();
}

version(linux_gtk)

/++

+/
class WebView : browser_engine {

	/++
		Creates a new webview instance. If dbg is non-zero - developer tools will
		be enabled (if the platform supports them). Window parameter can be a
		pointer to the native window handle. If it's non-null - then child WebView
		is embedded into the given parent window. Otherwise a new window is created.
		Depending on the platform, a GtkWindow, NSWindow or HWND pointer can be
		passed here.
	+/
	this(bool dbg, void* window) {
		super(&on_message, dbg, window);
	}

	extern(C)
	static void on_message(const char*) {}

	/// Destroys a webview and closes the native window.
	void destroy() {

	}

	/// Runs the main loop until it's terminated. After this function exits - you
	/// must destroy the webview.
	override void run() { super.run(); }

	/// Stops the main loop. It is safe to call this function from another other
	/// background thread.
	override void terminate() { super.terminate(); }

	/+
	/// Posts a function to be executed on the main thread. You normally do not need
	/// to call this function, unless you want to tweak the native window.
	void dispatch(void function(WebView w, void *arg) fn, void *arg) {}
	+/

	/// Returns a native window handle pointer. When using GTK backend the pointer
	/// is GtkWindow pointer, when using Cocoa backend the pointer is NSWindow
	/// pointer, when using Win32 backend the pointer is HWND pointer.
	void* getWindow() { return m_window; }

	/// Updates the title of the native window. Must be called from the UI thread.
	override void setTitle(const char *title) { super.setTitle(title); }

	/// Navigates webview to the given URL. URL may be a data URI.
	override void navigate(const char *url) { super.navigate(url); }

	/// Injects JavaScript code at the initialization of the new page. Every time
	/// the webview will open a the new page - this initialization code will be
	/// executed. It is guaranteed that code is executed before window.onload.
	override void init(const char *js) { super.init(js); }

	/// Evaluates arbitrary JavaScript code. Evaluation happens asynchronously, also
	/// the result of the expression is ignored. Use RPC bindings if you want to
	/// receive notifications about the results of the evaluation.
	override void eval(const char *js) { super.eval(js); }

	/// Binds a native C callback so that it will appear under the given name as a
	/// global JavaScript function. Internally it uses webview_init(). Callback
	/// receives a request string and a user-provided argument pointer. Request
	/// string is a JSON array of all the arguments passed to the JavaScript
	/// function.
	void bind(const char *name, void function(const char *, void *) fn, void *arg) {}

	/// Allows to return a value from the native binding. Original request pointer
	/// must be provided to help internal RPC engine match requests with responses.
	/// If status is zero - result is expected to be a valid JSON result value.
	/// If status is not zero - result is an error JSON object.
	void webview_return(const char *req, int status, const char *result) {}

  /*
  void on_message(const char *msg) {
    auto seq = json_parse(msg, "seq", 0);
    auto name = json_parse(msg, "name", 0);
    auto args = json_parse(msg, "args", 0);
    auto fn = bindings[name];
    if (fn == null) {
      return;
    }
    std::async(std::launch::async, [=]() {
      auto result = (*fn)(args);
      dispatch([=]() {
        eval(("var b = window['" + name + "'];b['callbacks'][" + seq + "](" +
              result + ");b['callbacks'][" + seq +
              "] = undefined;b['errors'][" + seq + "] = undefined;")
                 .c_str());
      });
    });
  }
  std::map<std::string, binding_t *> bindings;

  alias binding_t = std::function<std::string(std::string)>;

  void bind(const char *name, binding_t f) {
    auto js = "(function() { var name = '" + std::string(name) + "';" + R"(
      window[name] = function() {
        var me = window[name];
        var errors = me['errors'];
        var callbacks = me['callbacks'];
        if (!callbacks) {
          callbacks = {};
          me['callbacks'] = callbacks;
        }
        if (!errors) {
          errors = {};
          me['errors'] = errors;
        }
        var seq = (me['lastSeq'] || 0) + 1;
        me['lastSeq'] = seq;
        var promise = new Promise(function(resolve, reject) {
          callbacks[seq] = resolve;
          errors[seq] = reject;
        });
        window.external.invoke(JSON.stringify({
          name: name,
          seq:seq,
          args: Array.prototype.slice.call(arguments),
        }));
        return promise;
      }
    })())";
    init(js.c_str());
    bindings[name] = new binding_t(f);
  }

*/
}

private extern(C) {
	alias dispatch_fn_t = void function();
	alias msg_cb_t = void function(const char *msg);
}

version(WEBVIEW_GTK) {


/* Original https://github.com/zserge/webview notice below:
 * MIT License
 *
 * Copyright (c) 2017 Serge Zaitsev
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/*
	Port to D by Adam D. Ruppe, November 30, 2019
*/


	pragma(lib, "gtk-3");
	pragma(lib, "glib-2.0");
	pragma(lib, "gobject-2.0");
	pragma(lib, "webkit2gtk-4.0");
	pragma(lib, "javascriptcoregtk-4.0");

	private extern(C) {
		import core.stdc.config;
		alias GtkWidget = void;
		enum GtkWindowType {
			GTK_WINDOW_TOPLEVEL = 0
		}
		bool gtk_init_check(int*, char***);
		GtkWidget* gtk_window_new(GtkWindowType);
		c_ulong g_signal_connect_data(void*, const char*, void* /* function pointer!!! */, void*, void*, int);
		GtkWidget* webkit_web_view_new();
		alias WebKitUserContentManager = void;
		WebKitUserContentManager* webkit_web_view_get_user_content_manager(GtkWidget*);

		void gtk_container_add(GtkWidget*, GtkWidget*);
		void gtk_widget_grab_focus(GtkWidget*);
		void gtk_widget_show_all(GtkWidget*);
		void gtk_main();
		void gtk_main_quit();
		void webkit_web_view_load_uri(GtkWidget*, const char*);
		alias WebKitSettings = void;
		WebKitSettings* webkit_web_view_get_settings(GtkWidget*);
		void webkit_settings_set_enable_write_console_messages_to_stdout(WebKitSettings*, bool);
		void webkit_settings_set_enable_developer_extras(WebKitSettings*, bool);
		void webkit_user_content_manager_register_script_message_handler(WebKitUserContentManager*, const char*);
		alias JSCValue = void;
		alias WebKitJavascriptResult = void;
		JSCValue* webkit_javascript_result_get_js_value(WebKitJavascriptResult*);
		char* jsc_value_to_string(JSCValue*);
		void g_free(void*);
		void webkit_web_view_run_javascript(GtkWidget*, const char*, void*, void*, void*);
		alias WebKitUserScript = void;
		void webkit_user_content_manager_add_script(WebKitUserContentManager*, WebKitUserScript*);
		WebKitUserScript* webkit_user_script_new(const char*, WebKitUserContentInjectedFrames, WebKitUserScriptInjectionTime, const char*, const char*);
		enum WebKitUserContentInjectedFrames {
			WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
			WEBKIT_USER_CONTENT_INJECT_TOP_FRAME
		}
		enum WebKitUserScriptInjectionTime {
			WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
			WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END
		}
		void gtk_window_set_title(GtkWidget*, const char*);

		void gtk_window_set_resizable(GtkWidget*, bool);
		void gtk_window_set_default_size(GtkWidget*, int, int);
		void gtk_widget_set_size_request(GtkWidget*, int, int);
	}

	private class browser_engine {

		static extern(C)
		void ondestroy (GtkWidget *w, void* arg) {
			(cast(browser_engine) arg).terminate();
		}

		static extern(C)
		void smr(WebKitUserContentManager* m, WebKitJavascriptResult* r, void* arg) {
			auto w = cast(browser_engine) arg;
			JSCValue *value = webkit_javascript_result_get_js_value(r);
			auto s = jsc_value_to_string(value);
			w.m_cb(s);
			g_free(s);
		}

		this(msg_cb_t cb, bool dbg, void* window) {
			m_cb = cb;

			gtk_init_check(null, null);
			m_window = cast(GtkWidget*) window;
			if (m_window == null)
				m_window = gtk_window_new(GtkWindowType.GTK_WINDOW_TOPLEVEL);

			g_signal_connect_data(m_window, "destroy", &ondestroy, cast(void*) this, null, 0);

			m_webview = webkit_web_view_new();
			WebKitUserContentManager* manager = webkit_web_view_get_user_content_manager(m_webview);

			g_signal_connect_data(manager, "script-message-received::external", &smr, cast(void*) this, null, 0);
			webkit_user_content_manager_register_script_message_handler(manager, "external");
			init("window.external={invoke:function(s){window.webkit.messageHandlers.external.postMessage(s);}}");

			gtk_container_add(m_window, m_webview);
			gtk_widget_grab_focus(m_webview);

			if (dbg) {
				WebKitSettings *settings = webkit_web_view_get_settings(m_webview);
				webkit_settings_set_enable_write_console_messages_to_stdout(settings, true);
				webkit_settings_set_enable_developer_extras(settings, true);
			}

			gtk_widget_show_all(m_window);
		}
		void run() { gtk_main(); }
		void terminate() { gtk_main_quit(); }

		void navigate(const char *url) {
			webkit_web_view_load_uri(m_webview, url);
		}

		void setTitle(const char* title) {
			gtk_window_set_title(m_window, title);
		}

		/+
			void dispatch(std::function<void()> f) {
				g_idle_add_full(G_PRIORITY_HIGH_IDLE, (GSourceFunc)([](void *f) -> int {
							(*static_cast<dispatch_fn_t *>(f))();
							return G_SOURCE_REMOVE;
							}),
						new std::function<void()>(f),
						[](void *f) { delete static_cast<dispatch_fn_t *>(f); });
			}
		+/

		void setSize(int width, int height, bool resizable) {
			gtk_window_set_resizable(m_window, resizable);
			if (resizable) {
				gtk_window_set_default_size(m_window, width, height);
			}
			gtk_widget_set_size_request(m_window, width, height);
		}

		void init(const char *js) {
			WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(m_webview);
			webkit_user_content_manager_add_script(
				manager, webkit_user_script_new(
					js, WebKitUserContentInjectedFrames.WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
					WebKitUserScriptInjectionTime.WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, null, null));
			}

		void eval(const char *js) {
			webkit_web_view_run_javascript(m_webview, js, null, null, null);
		}

		protected:
		GtkWidget* m_window;
		GtkWidget* m_webview;
		msg_cb_t m_cb;
	}
} else version(WEBVIEW_COCOA) {
/+

//
// ====================================================================
//
// This implementation uses Cocoa WKWebView backend on macOS. It is
// written using ObjC runtime and uses WKWebView class as a browser runtime.
// You should pass "-framework Webkit" flag to the compiler.
//
// ====================================================================
//

#define OBJC_OLD_DISPATCH_PROTOTYPES 1
#include <CoreGraphics/CoreGraphics.h>
#include <objc/objc-runtime.h>

#define NSBackingStoreBuffered 2

#define NSWindowStyleMaskResizable 8
#define NSWindowStyleMaskMiniaturizable 4
#define NSWindowStyleMaskTitled 1
#define NSWindowStyleMaskClosable 2

#define NSApplicationActivationPolicyRegular 0

#define WKUserScriptInjectionTimeAtDocumentStart 0

id operator"" _cls(const char *s, std::size_t sz) {
  return (id)objc_getClass(s);
}
SEL operator"" _sel(const char *s, std::size_t sz) {
  return sel_registerName(s);
}
id operator"" _str(const char *s, std::size_t sz) {
  return objc_msgSend("NSString"_cls, "stringWithUTF8String:"_sel, s);
}

class browser_engine {
public:
  browser_engine(msg_cb_t cb, bool dbg, void *window) : m_cb(cb) {
    // Application
    id app = objc_msgSend("NSApplication"_cls, "sharedApplication"_sel);
    objc_msgSend(app, "setActivationPolicy:"_sel,
                 NSApplicationActivationPolicyRegular);

    // Delegate
    auto cls = objc_allocateClassPair((Class) "NSObject"_cls, "AppDelegate", 0);
    class_addProtocol(cls, objc_getProtocol("NSApplicationDelegate"));
    class_addProtocol(cls, objc_getProtocol("WKScriptMessageHandler"));
    class_addMethod(
        cls, "applicationShouldTerminateAfterLastWindowClosed:"_sel,
        (IMP)(+[](id self, SEL cmd, id notification) -> BOOL { return 1; }),
        "c@:@");
    class_addMethod(
        cls, "userContentController:didReceiveScriptMessage:"_sel,
        (IMP)(+[](id self, SEL cmd, id notification, id msg) {
          auto w = (browser_engine *)objc_getAssociatedObject(self, "webview");
          w->m_cb((const char *)objc_msgSend(objc_msgSend(msg, "body"_sel),
                                             "UTF8String"_sel));
        }),
        "v@:@@");
    objc_registerClassPair(cls);

    auto delegate = objc_msgSend((id)cls, "new"_sel);
    objc_setAssociatedObject(delegate, "webview", (id)this,
                             OBJC_ASSOCIATION_ASSIGN);
    objc_msgSend(app, sel_registerName("setDelegate:"), delegate);

    // Main window
    if (window is null) {
      m_window = objc_msgSend("NSWindow"_cls, "alloc"_sel);
      m_window = objc_msgSend(
          m_window, "initWithContentRect:styleMask:backing:defer:"_sel,
          CGRectMake(0, 0, 0, 0), 0, NSBackingStoreBuffered, 0);
      setSize(480, 320, true);
    } else {
      m_window = (id)window;
    }

    // Webview
    auto config = objc_msgSend("WKWebViewConfiguration"_cls, "new"_sel);
    m_manager = objc_msgSend(config, "userContentController"_sel);
    m_webview = objc_msgSend("WKWebView"_cls, "alloc"_sel);
    objc_msgSend(m_webview, "initWithFrame:configuration:"_sel,
                 CGRectMake(0, 0, 0, 0), config);
    objc_msgSend(m_manager, "addScriptMessageHandler:name:"_sel, delegate,
                 "external"_str);
    init(R"script(
                      window.external = {
                        invoke: function(s) {
                          window.webkit.messageHandlers.external.postMessage(s);
                        },
                      };
                     )script");
    if (dbg) {
      objc_msgSend(objc_msgSend(config, "preferences"_sel),
                   "setValue:forKey:"_sel, 1, "developerExtrasEnabled"_str);
    }
    objc_msgSend(m_window, "setContentView:"_sel, m_webview);
    objc_msgSend(m_window, "makeKeyAndOrderFront:"_sel, null);
  }
  ~browser_engine() { close(); }
  void terminate() { close(); objc_msgSend("NSApp"_cls, "terminate:"_sel, null); }
  void run() {
    id app = objc_msgSend("NSApplication"_cls, "sharedApplication"_sel);
    dispatch([&]() { objc_msgSend(app, "activateIgnoringOtherApps:"_sel, 1); });
    objc_msgSend(app, "run"_sel);
  }
  void dispatch(std::function<void()> f) {
    dispatch_async_f(dispatch_get_main_queue(), new dispatch_fn_t(f),
                     (dispatch_function_t)([](void *arg) {
                       auto f = static_cast<dispatch_fn_t *>(arg);
                       (*f)();
                       delete f;
                     }));
  }
  void setTitle(const char *title) {
    objc_msgSend(
        m_window, "setTitle:"_sel,
        objc_msgSend("NSString"_cls, "stringWithUTF8String:"_sel, title));
  }
  void setSize(int width, int height, bool resizable) {
    auto style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                 NSWindowStyleMaskMiniaturizable;
    if (resizable) {
      style = style | NSWindowStyleMaskResizable;
    }
    objc_msgSend(m_window, "setStyleMask:"_sel, style);
    objc_msgSend(m_window, "setFrame:display:animate:"_sel,
                 CGRectMake(0, 0, width, height), 1, 0);
  }
  void navigate(const char *url) {
    auto nsurl = objc_msgSend(
        "NSURL"_cls, "URLWithString:"_sel,
        objc_msgSend("NSString"_cls, "stringWithUTF8String:"_sel, url));
    objc_msgSend(
        m_webview, "loadRequest:"_sel,
        objc_msgSend("NSURLRequest"_cls, "requestWithURL:"_sel, nsurl));
  }
  void init(const char *js) {
    objc_msgSend(
        m_manager, "addUserScript:"_sel,
        objc_msgSend(
            objc_msgSend("WKUserScript"_cls, "alloc"_sel),
            "initWithSource:injectionTime:forMainFrameOnly:"_sel,
            objc_msgSend("NSString"_cls, "stringWithUTF8String:"_sel, js),
            WKUserScriptInjectionTimeAtDocumentStart, 1));
  }
  void eval(const char *js) {
    objc_msgSend(m_webview, "evaluateJavaScript:completionHandler:"_sel,
                 objc_msgSend("NSString"_cls, "stringWithUTF8String:"_sel, js),
                 null);
  }

protected:
  void close() { objc_msgSend(m_window, "close"_sel); }
  id m_window;
  id m_webview;
  id m_manager;
  msg_cb_t m_cb;
};

+/

}

version(cef)  {

/++
	This creates a base class for a thing to help you implement the function pointers.

	class MyApp : CEF!cef_app_t {

	}
+/
abstract class CEF(Base) {
	private struct Inner {
		Base c;
		CEF d_object;
	}
	private Inner inner;

	this() {
		if(!__ctfe) construct();
	}

	// ONLY call this if you did a ctfe construction
	void construct() {
		assert(inner.c.base.size == 0);

		import core.memory;
		GC.addRoot(cast(void*) this);
		inner.c.base.size = Inner.sizeof;
		inner.c.base.add_ref = &c_add_ref;
		inner.c.base.release = &c_release;
		inner.c.base.has_one_ref = &c_has_one_ref;
		inner.c.base.has_at_least_one_ref = &c_has_at_least_one_ref;
		inner.d_object = this;

		static foreach(memberName; __traits(allMembers, Base)) {
			static if(is(typeof(__traits(getMember, Base, memberName)) == return)) {
				__traits(getMember, inner.c, memberName) = mixin("&c_" ~ memberName);
			}
		}
	}

	private static nothrow @nogc extern(C) {
		void c_add_ref(cef_base_ref_counted_t* self) {
			return ((cast(Inner*) self).d_object).add_ref();
		}
		int c_release(cef_base_ref_counted_t* self) {
			return ((cast(Inner*) self).d_object).release();
		}
		int c_has_one_ref(cef_base_ref_counted_t* self) {
			return ((cast(Inner*) self).d_object).has_one_ref();
		}
		int c_has_at_least_one_ref(cef_base_ref_counted_t* self) {
			return ((cast(Inner*) self).d_object).has_at_least_one_ref();
		}
	}

	private shared(int) refcount = 1;
	final void add_ref() {
		import core.atomic;
		atomicOp!"+="(refcount, 1);
	}
	final int release() {
		import core.atomic;
		auto v = atomicOp!"-="(refcount, 1);
		if(v == 0) {
			import core.memory;
			GC.removeRoot(cast(void*) this);
			return 1;
		}
		return 0;
	}
	final int has_one_ref() {
		return (cast() refcount) == 1;
	}
	final int has_at_least_one_ref() {
		return (cast() refcount) >= 1;
	}

	/// Call this to pass to CEF. It will add ref for you.
	final Base* passable() {
		assert(inner.c.base.size);
		add_ref();
		return returnable();
	}

	final Base* returnable() {
		assert(inner.c.base.size);
		return &inner.c;
	}

	static foreach(memberName; __traits(allMembers, Base)) {
		static if(is(typeof(__traits(getMember, Base, memberName)) == return)) {
			mixin AbstractMethod!(memberName);
		} else {
			mixin(q{final ref @property } ~ memberName ~ q{() { return __traits(getMember, inner.c, memberName); }});
		}
	}
}

// you implement this in D...
private mixin template AbstractMethod(string name) {
	alias ptr = typeof(__traits(getMember, Base, name));
	static if(is(ptr Return == return))
	static if(is(typeof(*ptr) Params == function))
	{
		mixin(q{abstract nothrow Return } ~ name ~ q{(CefToD!(Params[1 .. $]) p);});
		// mixin(q{abstract nothrow Return } ~ name ~ q{(Params[1 .. $] p);});

		mixin(q{
		private static nothrow extern(C)
		Return c_}~name~q{(Params p) {
			Base* self = p[0]; // a bit of a type check here...
			auto dobj = (cast(Inner*) self).d_object; // ...before this cast.

			//return __traits(getMember, dobj, name)(p[1 .. $]);
			mixin(() {
				string code = "return __traits(getMember, dobj, name)(";

				static foreach(idx; 1 .. p.length) {
					if(idx > 1)
						code ~= ", ";
					code ~= "cefToD(p[" ~ idx.stringof ~ "])";
				}
				code ~= ");";
				return code;
			}());
		}
		});
	}
	else static assert(0, name ~ " params");
	else static assert(0, name ~ " return");
}

// you call this from D...
private mixin template ForwardMethod(string name) {
	alias ptr = typeof(__traits(getMember, Base, name));
	static if(is(ptr Return == return))
	static if(is(typeof(*ptr) Params == function))
	{
		mixin(q{nothrow auto } ~ name ~ q{(Params[1 .. $] p) {
			Base* self = inner; // a bit of a type check here...
			static if(is(Return == void))
				return __traits(getMember, inner, name)(self, p);
			else
				return cefToD(__traits(getMember, inner, name)(self, p));
		}});
	}
	else static assert(0, name ~ " params");
	else static assert(0, name ~ " return");
}


private alias AliasSeq(T...) = T;

private template CefToD(T...) {
	static if(T.length == 0) {
		alias CefToD = T;
	} else static if(T.length == 1) {
		static if(is(typeof(T[0].base) == cef_base_ref_counted_t)) {
			alias CefToD = RC!(typeof(*T[0]));
			/+
			static if(is(T[0] == I*, I)) {
				alias CefToD = CEF!(I);
			} else static assert(0, T[0]);
			+/
		} else
			alias CefToD = T[0];
	} else {
		alias CefToD = AliasSeq!(CefToD!(T[0]), CefToD!(T[1..$]));

	}
}

struct RC(Base) {
	private Base* inner;

	this(Base* t) nothrow {
		inner = t;
		// assuming the refcount is already set here
	}
	this(this) nothrow {
		if(inner is null) return;
		inner.base.add_ref(&inner.base);
	}
	~this() nothrow {
		if(inner is null) return;
		inner.base.release(&inner.base);
		inner = null;
	}

	Base* getRawPointer() nothrow {
		return inner;
	}

	Base* passable() nothrow {
		if(inner is null)
			return inner;
		inner.base.add_ref(&inner.base);
		return inner;
	}

	static foreach(memberName; __traits(allMembers, Base)) {
		static if(is(typeof(__traits(getMember, Base, memberName)) == return)) {
			mixin ForwardMethod!(memberName);
		} else {
			mixin(q{final ref @property } ~ memberName ~ q{() { return __traits(getMember, inner, memberName); }});
		}
	}

}

auto cefToD(T)(T t) {
	static if(is(typeof(T.base) == cef_base_ref_counted_t)) {
		return RC!(typeof(*T))(t);
	} else {
		return t;
	}
}

// bindings follow, first some hand-written ones for Linux, then some machine translated things.

struct cef_main_args_t {
	int argc;
	char** argv;
}
alias _cef_main_args_t = cef_main_args_t;

extern(C)
int cef_string_utf8_to_utf16(const char* src, size_t src_len, cef_string_utf16_t* output);

struct _cef_string_utf8_t {
  char* str;
  size_t length;
  void* dtor;// void (*dtor)(char* str);
}

alias cef_string_utf8_t = _cef_string_utf8_t;

struct _cef_string_utf16_t {
  char16* str;
  size_t length;
  void* dtor; // voiod (*dtor)(char16* str);

  this(wstring s) nothrow {
	this.str = cast(char16*) s.ptr;
	this.length = s.length;
  }
}

alias _cef_string_utf16_t cef_string_utf16_t;

alias cef_string_t = cef_string_utf16_t;
alias cef_window_handle_t = NativeWindowHandle;

struct cef_time_t {
  int year;          // Four or five digit year "2007" (1601 to 30827 on
                     //   Windows, 1970 to 2038 on 32-bit POSIX)
  int month;         // 1-based month (values 1 = January, etc.)
  int day_of_week;   // 0-based day of week (0 = Sunday, etc.)
  int day_of_month;  // 1-based day of month (1-31)
  int hour;          // Hour within the current day (0-23)
  int minute;        // Minute within the current hour (0-59)
  int second;        // Second within the current minute (0-59 plus leap
                     //   seconds which may take it up to 60).
  int millisecond;   // Milliseconds within the current second (0-999)
}

struct _cef_window_info_t {
  cef_string_t window_name;

  uint x;
  uint y;
  uint width;
  uint height;

  cef_window_handle_t parent_window;

  int windowless_rendering_enabled;

  int shared_texture_enabled;

  int external_begin_frame_enabled;

  cef_window_handle_t window;
}

alias cef_window_info_t = _cef_window_info_t;

import core.stdc.config;
alias int16 = short;
alias uint16 = ushort;
alias int32 = int;
alias uint32 = uint;
alias char16 = wchar;
alias int64 = long;
alias uint64 = ulong;

// FIXME
alias cef_string_list_t = void*;
alias cef_string_multimap_t = void*;
alias cef_string_map_t = void*;

version(linux) {
	import core.sys.posix.sys.types;
	alias pid_t cef_platform_thread_id_t;
	alias OS_EVENT = XEvent;
} else {
	import core.sys.windows.windows;
	alias HANDLE cef_platform_thread_id_t;
	alias OS_EVENT = void;
}

nothrow @nogc extern(C) void cef_string_userfree_utf16_free(cef_string_userfree_utf16_t str);
alias cef_string_userfree_t = const(wchar)*;
alias cef_string_userfree_utf16_t = const(wchar)*;

static assert(cef_app_t.sizeof == 80);
static assert(cef_settings_t.sizeof == 440);
static assert(cef_window_info_t.sizeof == 72);
static assert(cef_string_t.sizeof == 24);
static assert(cef_client_t.sizeof == 160);

// cef/include/capi$ for i in *.h; do dstep -I../.. $i; done
// then concatenate the bodies of them and delete the translated macros and `struct .*;` stuff

// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=00d5124d346e3f3cc3f53d67bcb766d1d798bf12$
//

extern (C):

///
// Implement this structure to receive accessibility notification when
// accessibility events have been registered. The functions of this structure
// will be called on the UI thread.
///
struct _cef_accessibility_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called after renderer process sends accessibility tree changes to the
    // browser process.
    ///
    void function (
        _cef_accessibility_handler_t* self,
        _cef_value_t* value) nothrow on_accessibility_tree_change;

    ///
    // Called after renderer process sends accessibility location changes to the
    // browser process.
    ///
    void function (
        _cef_accessibility_handler_t* self,
        _cef_value_t* value) nothrow on_accessibility_location_change;
}

alias cef_accessibility_handler_t = _cef_accessibility_handler_t;

// CEF_INCLUDE_CAPI_CEF_ACCESSIBILITY_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=04cfae434fe901644c1c78f1c30c0921518cc666$
//

extern (C):

///
// Implement this structure to provide handler implementations. Methods will be
// called by the process and/or thread indicated.
///
struct _cef_app_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Provides an opportunity to view and/or modify command-line arguments before
    // processing by CEF and Chromium. The |process_type| value will be NULL for
    // the browser process. Do not keep a reference to the cef_command_line_t
    // object passed to this function. The CefSettings.command_line_args_disabled
    // value can be used to start with an NULL command-line object. Any values
    // specified in CefSettings that equate to command-line arguments will be set
    // before this function is called. Be cautious when using this function to
    // modify command-line arguments for non-browser processes as this may result
    // in undefined behavior including crashes.
    ///
    void function (
        _cef_app_t* self,
        const(cef_string_t)* process_type,
        _cef_command_line_t* command_line) nothrow on_before_command_line_processing;

    ///
    // Provides an opportunity to register custom schemes. Do not keep a reference
    // to the |registrar| object. This function is called on the main thread for
    // each process and the registered schemes should be the same across all
    // processes.
    ///
    void function (
        _cef_app_t* self,
        _cef_scheme_registrar_t* registrar) nothrow on_register_custom_schemes;

    ///
    // Return the handler for resource bundle events. If
    // CefSettings.pack_loading_disabled is true (1) a handler must be returned.
    // If no handler is returned resources will be loaded from pack files. This
    // function is called by the browser and render processes on multiple threads.
    ///
    _cef_resource_bundle_handler_t* function (
        _cef_app_t* self) nothrow get_resource_bundle_handler;

    ///
    // Return the handler for functionality specific to the browser process. This
    // function is called on multiple threads in the browser process.
    ///
    _cef_browser_process_handler_t* function (
        _cef_app_t* self) nothrow get_browser_process_handler;

    ///
    // Return the handler for functionality specific to the render process. This
    // function is called on the render process main thread.
    ///
    _cef_render_process_handler_t* function (
        _cef_app_t* self) nothrow get_render_process_handler;
}

alias cef_app_t = _cef_app_t;

///
// This function should be called from the application entry point function to
// execute a secondary process. It can be used to run secondary processes from
// the browser client executable (default behavior) or from a separate
// executable specified by the CefSettings.browser_subprocess_path value. If
// called for the browser process (identified by no "type" command-line value)
// it will return immediately with a value of -1. If called for a recognized
// secondary process it will block until the process should exit and then return
// the process exit code. The |application| parameter may be NULL. The
// |windows_sandbox_info| parameter is only used on Windows and may be NULL (see
// cef_sandbox_win.h for details).
///
int cef_execute_process (
    const(_cef_main_args_t)* args,
    cef_app_t* application,
    void* windows_sandbox_info);

///
// This function should be called on the main application thread to initialize
// the CEF browser process. The |application| parameter may be NULL. A return
// value of true (1) indicates that it succeeded and false (0) indicates that it
// failed. The |windows_sandbox_info| parameter is only used on Windows and may
// be NULL (see cef_sandbox_win.h for details).
///
int cef_initialize (
    const(_cef_main_args_t)* args,
    const(_cef_settings_t)* settings,
    cef_app_t* application,
    void* windows_sandbox_info);

///
// This function should be called on the main application thread to shut down
// the CEF browser process before the application exits.
///
void cef_shutdown ();

///
// Perform a single iteration of CEF message loop processing. This function is
// provided for cases where the CEF message loop must be integrated into an
// existing application message loop. Use of this function is not recommended
// for most users; use either the cef_run_message_loop() function or
// CefSettings.multi_threaded_message_loop if possible. When using this function
// care must be taken to balance performance against excessive CPU usage. It is
// recommended to enable the CefSettings.external_message_pump option when using
// this function so that
// cef_browser_process_handler_t::on_schedule_message_pump_work() callbacks can
// facilitate the scheduling process. This function should only be called on the
// main application thread and only if cef_initialize() is called with a
// CefSettings.multi_threaded_message_loop value of false (0). This function
// will not block.
///
nothrow void cef_do_message_loop_work ();

///
// Run the CEF message loop. Use this function instead of an application-
// provided message loop to get the best balance between performance and CPU
// usage. This function should only be called on the main application thread and
// only if cef_initialize() is called with a
// CefSettings.multi_threaded_message_loop value of false (0). This function
// will block until a quit message is received by the system.
///
void cef_run_message_loop ();

///
// Quit the CEF message loop that was started by calling cef_run_message_loop().
// This function should only be called on the main application thread and only
// if cef_run_message_loop() was used.
///
void cef_quit_message_loop ();

///
// Set to true (1) before calling Windows APIs like TrackPopupMenu that enter a
// modal message loop. Set to false (0) after exiting the modal message loop.
///
void cef_set_osmodal_loop (int osModalLoop);

///
// Call during process startup to enable High-DPI support on Windows 7 or newer.
// Older versions of Windows should be left DPI-unaware because they do not
// support DirectWrite and GDI fonts are kerned very badly.
///
void cef_enable_highdpi_support ();

// CEF_INCLUDE_CAPI_CEF_APP_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=430877d950508a545d0baa18c8c8c0d2d183fec4$
//

extern (C):

///
// Implement this structure to handle audio events.
///
struct _cef_audio_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the UI thread to allow configuration of audio stream parameters.
    // Return true (1) to proceed with audio stream capture, or false (0) to
    // cancel it. All members of |params| can optionally be configured here, but
    // they are also pre-filled with some sensible defaults.
    ///
    int function (
        _cef_audio_handler_t* self,
        _cef_browser_t* browser,
        cef_audio_parameters_t* params) nothrow get_audio_parameters;

    ///
    // Called on a browser audio capture thread when the browser starts streaming
    // audio. OnAudioSteamStopped will always be called after
    // OnAudioStreamStarted; both functions may be called multiple times for the
    // same browser. |params| contains the audio parameters like sample rate and
    // channel layout. |channels| is the number of channels.
    ///
    void function (
        _cef_audio_handler_t* self,
        _cef_browser_t* browser,
        const(cef_audio_parameters_t)* params,
        int channels) nothrow on_audio_stream_started;

    ///
    // Called on the audio stream thread when a PCM packet is received for the
    // stream. |data| is an array representing the raw PCM data as a floating
    // point type, i.e. 4-byte value(s). |frames| is the number of frames in the
    // PCM packet. |pts| is the presentation timestamp (in milliseconds since the
    // Unix Epoch) and represents the time at which the decompressed packet should
    // be presented to the user. Based on |frames| and the |channel_layout| value
    // passed to OnAudioStreamStarted you can calculate the size of the |data|
    // array in bytes.
    ///
    void function (
        _cef_audio_handler_t* self,
        _cef_browser_t* browser,
        const(float*)* data,
        int frames,
        int64 pts) nothrow on_audio_stream_packet;

    ///
    // Called on the UI thread when the stream has stopped. OnAudioSteamStopped
    // will always be called after OnAudioStreamStarted; both functions may be
    // called multiple times for the same stream.
    ///
    void function (
        _cef_audio_handler_t* self,
        _cef_browser_t* browser) nothrow on_audio_stream_stopped;

    ///
    // Called on the UI or audio stream thread when an error occurred. During the
    // stream creation phase this callback will be called on the UI thread while
    // in the capturing phase it will be called on the audio stream thread. The
    // stream will be stopped immediately.
    ///
    void function (
        _cef_audio_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* message) nothrow on_audio_stream_error;
}

alias cef_audio_handler_t = _cef_audio_handler_t;

// CEF_INCLUDE_CAPI_CEF_AUDIO_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=58be0e24b46373bbdad28031891396ea246f446c$
//

extern (C):

///
// Callback structure used for asynchronous continuation of authentication
// requests.
///
struct _cef_auth_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Continue the authentication request.
    ///
    void function (
        _cef_auth_callback_t* self,
        const(cef_string_t)* username,
        const(cef_string_t)* password) nothrow cont;

    ///
    // Cancel the authentication request.
    ///
    void function (_cef_auth_callback_t* self) nothrow cancel;
}

alias cef_auth_callback_t = _cef_auth_callback_t;

// CEF_INCLUDE_CAPI_CEF_AUTH_CALLBACK_CAPI_H_
// Copyright (c) 2014 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

extern (C):

///
// All ref-counted framework structures must include this structure first.
///
struct _cef_base_ref_counted_t
{
    ///
    // Size of the data structure.
    ///
    size_t size;

    ///
    // Called to increment the reference count for the object. Should be called
    // for every new copy of a pointer to a given object.
    ///
    void function (_cef_base_ref_counted_t* self) nothrow add_ref;

    ///
    // Called to decrement the reference count for the object. If the reference
    // count falls to 0 the object should self-delete. Returns true (1) if the
    // resulting reference count is 0.
    ///
    int function (_cef_base_ref_counted_t* self) nothrow release;

    ///
    // Returns true (1) if the current reference count is 1.
    ///
    int function (_cef_base_ref_counted_t* self) nothrow has_one_ref;

    ///
    // Returns true (1) if the current reference count is at least 1.
    ///
    int function (_cef_base_ref_counted_t* self) nothrow has_at_least_one_ref;
}

alias cef_base_ref_counted_t = _cef_base_ref_counted_t;

///
// All scoped framework structures must include this structure first.
///
struct _cef_base_scoped_t
{
    ///
    // Size of the data structure.
    ///
    size_t size;

    ///
    // Called to delete this object. May be NULL if the object is not owned.
    ///
    void function (_cef_base_scoped_t* self) del;
}

alias cef_base_scoped_t = _cef_base_scoped_t;

// CEF_INCLUDE_CAPI_CEF_BASE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=965eb2e55afec0a4618a7acd9478b9c1215be29d$
//

import core.stdc.config;

extern (C):

///
// Structure used to represent a browser window. When used in the browser
// process the functions of this structure may be called on any thread unless
// otherwise indicated in the comments. When used in the render process the
// functions of this structure may only be called on the main thread.
///
struct _cef_browser_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the browser host object. This function can only be called in the
    // browser process.
    ///
    _cef_browser_host_t* function (_cef_browser_t* self) nothrow get_host;

    ///
    // Returns true (1) if the browser can navigate backwards.
    ///
    int function (_cef_browser_t* self) nothrow can_go_back;

    ///
    // Navigate backwards.
    ///
    void function (_cef_browser_t* self) nothrow go_back;

    ///
    // Returns true (1) if the browser can navigate forwards.
    ///
    int function (_cef_browser_t* self) nothrow can_go_forward;

    ///
    // Navigate forwards.
    ///
    void function (_cef_browser_t* self) nothrow go_forward;

    ///
    // Returns true (1) if the browser is currently loading.
    ///
    int function (_cef_browser_t* self) nothrow is_loading;

    ///
    // Reload the current page.
    ///
    void function (_cef_browser_t* self) nothrow reload;

    ///
    // Reload the current page ignoring any cached data.
    ///
    void function (_cef_browser_t* self) nothrow reload_ignore_cache;

    ///
    // Stop loading the page.
    ///
    void function (_cef_browser_t* self) nothrow stop_load;

    ///
    // Returns the globally unique identifier for this browser. This value is also
    // used as the tabId for extension APIs.
    ///
    int function (_cef_browser_t* self) nothrow get_identifier;

    ///
    // Returns true (1) if this object is pointing to the same handle as |that|
    // object.
    ///
    int function (_cef_browser_t* self, _cef_browser_t* that) nothrow is_same;

    ///
    // Returns true (1) if the window is a popup window.
    ///
    int function (_cef_browser_t* self) nothrow is_popup;

    ///
    // Returns true (1) if a document has been loaded in the browser.
    ///
    int function (_cef_browser_t* self) nothrow has_document;

    ///
    // Returns the main (top-level) frame for the browser window.
    ///
    _cef_frame_t* function (_cef_browser_t* self) nothrow get_main_frame;

    ///
    // Returns the focused frame for the browser window.
    ///
    _cef_frame_t* function (_cef_browser_t* self) nothrow get_focused_frame;

    ///
    // Returns the frame with the specified identifier, or NULL if not found.
    ///
    _cef_frame_t* function (
        _cef_browser_t* self,
        int64 identifier) nothrow get_frame_byident;

    ///
    // Returns the frame with the specified name, or NULL if not found.
    ///
    _cef_frame_t* function (
        _cef_browser_t* self,
        const(cef_string_t)* name) nothrow get_frame;

    ///
    // Returns the number of frames that currently exist.
    ///
    size_t function (_cef_browser_t* self) nothrow get_frame_count;

    ///
    // Returns the identifiers of all existing frames.
    ///
    void function (
        _cef_browser_t* self,
        size_t* identifiersCount,
        int64* identifiers) nothrow get_frame_identifiers;

    ///
    // Returns the names of all existing frames.
    ///
    void function (
        _cef_browser_t* self,
        cef_string_list_t names) nothrow get_frame_names;
}

alias cef_browser_t = _cef_browser_t;

///
// Callback structure for cef_browser_host_t::RunFileDialog. The functions of
// this structure will be called on the browser process UI thread.
///
struct _cef_run_file_dialog_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called asynchronously after the file dialog is dismissed.
    // |selected_accept_filter| is the 0-based index of the value selected from
    // the accept filters array passed to cef_browser_host_t::RunFileDialog.
    // |file_paths| will be a single value or a list of values depending on the
    // dialog mode. If the selection was cancelled |file_paths| will be NULL.
    ///
    void function (
        _cef_run_file_dialog_callback_t* self,
        int selected_accept_filter,
        cef_string_list_t file_paths) nothrow on_file_dialog_dismissed;
}

alias cef_run_file_dialog_callback_t = _cef_run_file_dialog_callback_t;

///
// Callback structure for cef_browser_host_t::GetNavigationEntries. The
// functions of this structure will be called on the browser process UI thread.
///
struct _cef_navigation_entry_visitor_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be executed. Do not keep a reference to |entry| outside of
    // this callback. Return true (1) to continue visiting entries or false (0) to
    // stop. |current| is true (1) if this entry is the currently loaded
    // navigation entry. |index| is the 0-based index of this entry and |total| is
    // the total number of entries.
    ///
    int function (
        _cef_navigation_entry_visitor_t* self,
        _cef_navigation_entry_t* entry,
        int current,
        int index,
        int total) nothrow visit;
}

alias cef_navigation_entry_visitor_t = _cef_navigation_entry_visitor_t;

///
// Callback structure for cef_browser_host_t::PrintToPDF. The functions of this
// structure will be called on the browser process UI thread.
///
struct _cef_pdf_print_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be executed when the PDF printing has completed. |path| is
    // the output path. |ok| will be true (1) if the printing completed
    // successfully or false (0) otherwise.
    ///
    void function (
        _cef_pdf_print_callback_t* self,
        const(cef_string_t)* path,
        int ok) nothrow on_pdf_print_finished;
}

alias cef_pdf_print_callback_t = _cef_pdf_print_callback_t;

///
// Callback structure for cef_browser_host_t::DownloadImage. The functions of
// this structure will be called on the browser process UI thread.
///
struct _cef_download_image_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be executed when the image download has completed.
    // |image_url| is the URL that was downloaded and |http_status_code| is the
    // resulting HTTP status code. |image| is the resulting image, possibly at
    // multiple scale factors, or NULL if the download failed.
    ///
    void function (
        _cef_download_image_callback_t* self,
        const(cef_string_t)* image_url,
        int http_status_code,
        _cef_image_t* image) nothrow on_download_image_finished;
}

alias cef_download_image_callback_t = _cef_download_image_callback_t;

///
// Structure used to represent the browser process aspects of a browser window.
// The functions of this structure can only be called in the browser process.
// They may be called on any thread in that process unless otherwise indicated
// in the comments.
///
struct _cef_browser_host_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the hosted browser object.
    ///
    _cef_browser_t* function (_cef_browser_host_t* self) nothrow get_browser;

    ///
    // Request that the browser close. The JavaScript 'onbeforeunload' event will
    // be fired. If |force_close| is false (0) the event handler, if any, will be
    // allowed to prompt the user and the user can optionally cancel the close. If
    // |force_close| is true (1) the prompt will not be displayed and the close
    // will proceed. Results in a call to cef_life_span_handler_t::do_close() if
    // the event handler allows the close or if |force_close| is true (1). See
    // cef_life_span_handler_t::do_close() documentation for additional usage
    // information.
    ///
    void function (_cef_browser_host_t* self, int force_close) nothrow close_browser;

    ///
    // Helper for closing a browser. Call this function from the top-level window
    // close handler. Internally this calls CloseBrowser(false (0)) if the close
    // has not yet been initiated. This function returns false (0) while the close
    // is pending and true (1) after the close has completed. See close_browser()
    // and cef_life_span_handler_t::do_close() documentation for additional usage
    // information. This function must be called on the browser process UI thread.
    ///
    int function (_cef_browser_host_t* self) nothrow try_close_browser;

    ///
    // Set whether the browser is focused.
    ///
    void function (_cef_browser_host_t* self, int focus) nothrow set_focus;

    ///
    // Retrieve the window handle for this browser. If this browser is wrapped in
    // a cef_browser_view_t this function should be called on the browser process
    // UI thread and it will return the handle for the top-level native window.
    ///
    c_ulong function (_cef_browser_host_t* self) nothrow get_window_handle;

    ///
    // Retrieve the window handle of the browser that opened this browser. Will
    // return NULL for non-popup windows or if this browser is wrapped in a
    // cef_browser_view_t. This function can be used in combination with custom
    // handling of modal windows.
    ///
    c_ulong function (_cef_browser_host_t* self) nothrow get_opener_window_handle;

    ///
    // Returns true (1) if this browser is wrapped in a cef_browser_view_t.
    ///
    int function (_cef_browser_host_t* self) nothrow has_view;

    ///
    // Returns the client for this browser.
    ///
    _cef_client_t* function (_cef_browser_host_t* self) nothrow get_client;

    ///
    // Returns the request context for this browser.
    ///
    _cef_request_context_t* function (
        _cef_browser_host_t* self) nothrow get_request_context;

    ///
    // Get the current zoom level. The default zoom level is 0.0. This function
    // can only be called on the UI thread.
    ///
    double function (_cef_browser_host_t* self) nothrow get_zoom_level;

    ///
    // Change the zoom level to the specified value. Specify 0.0 to reset the zoom
    // level. If called on the UI thread the change will be applied immediately.
    // Otherwise, the change will be applied asynchronously on the UI thread.
    ///
    void function (_cef_browser_host_t* self, double zoomLevel) nothrow set_zoom_level;

    ///
    // Call to run a file chooser dialog. Only a single file chooser dialog may be
    // pending at any given time. |mode| represents the type of dialog to display.
    // |title| to the title to be used for the dialog and may be NULL to show the
    // default title ("Open" or "Save" depending on the mode). |default_file_path|
    // is the path with optional directory and/or file name component that will be
    // initially selected in the dialog. |accept_filters| are used to restrict the
    // selectable file types and may any combination of (a) valid lower-cased MIME
    // types (e.g. "text/*" or "image/*"), (b) individual file extensions (e.g.
    // ".txt" or ".png"), or (c) combined description and file extension delimited
    // using "|" and ";" (e.g. "Image Types|.png;.gif;.jpg").
    // |selected_accept_filter| is the 0-based index of the filter that will be
    // selected by default. |callback| will be executed after the dialog is
    // dismissed or immediately if another dialog is already pending. The dialog
    // will be initiated asynchronously on the UI thread.
    ///
    void function (
        _cef_browser_host_t* self,
        cef_file_dialog_mode_t mode,
        const(cef_string_t)* title,
        const(cef_string_t)* default_file_path,
        cef_string_list_t accept_filters,
        int selected_accept_filter,
        _cef_run_file_dialog_callback_t* callback) nothrow run_file_dialog;

    ///
    // Download the file at |url| using cef_download_handler_t.
    ///
    void function (
        _cef_browser_host_t* self,
        const(cef_string_t)* url) nothrow start_download;

    ///
    // Download |image_url| and execute |callback| on completion with the images
    // received from the renderer. If |is_favicon| is true (1) then cookies are
    // not sent and not accepted during download. Images with density independent
    // pixel (DIP) sizes larger than |max_image_size| are filtered out from the
    // image results. Versions of the image at different scale factors may be
    // downloaded up to the maximum scale factor supported by the system. If there
    // are no image results <= |max_image_size| then the smallest image is resized
    // to |max_image_size| and is the only result. A |max_image_size| of 0 means
    // unlimited. If |bypass_cache| is true (1) then |image_url| is requested from
    // the server even if it is present in the browser cache.
    ///
    void function (
        _cef_browser_host_t* self,
        const(cef_string_t)* image_url,
        int is_favicon,
        uint32 max_image_size,
        int bypass_cache,
        _cef_download_image_callback_t* callback) nothrow download_image;

    ///
    // Print the current browser contents.
    ///
    void function (_cef_browser_host_t* self) nothrow print;

    ///
    // Print the current browser contents to the PDF file specified by |path| and
    // execute |callback| on completion. The caller is responsible for deleting
    // |path| when done. For PDF printing to work on Linux you must implement the
    // cef_print_handler_t::GetPdfPaperSize function.
    ///
    void function (
        _cef_browser_host_t* self,
        const(cef_string_t)* path,
        const(_cef_pdf_print_settings_t)* settings,
        _cef_pdf_print_callback_t* callback) nothrow print_to_pdf;

    ///
    // Search for |searchText|. |identifier| must be a unique ID and these IDs
    // must strictly increase so that newer requests always have greater IDs than
    // older requests. If |identifier| is zero or less than the previous ID value
    // then it will be automatically assigned a new valid ID. |forward| indicates
    // whether to search forward or backward within the page. |matchCase|
    // indicates whether the search should be case-sensitive. |findNext| indicates
    // whether this is the first request or a follow-up. The cef_find_handler_t
    // instance, if any, returned via cef_client_t::GetFindHandler will be called
    // to report find results.
    ///
    void function (
        _cef_browser_host_t* self,
        int identifier,
        const(cef_string_t)* searchText,
        int forward,
        int matchCase,
        int findNext) nothrow find;

    ///
    // Cancel all searches that are currently going on.
    ///
    void function (_cef_browser_host_t* self, int clearSelection) nothrow stop_finding;

    ///
    // Open developer tools (DevTools) in its own browser. The DevTools browser
    // will remain associated with this browser. If the DevTools browser is
    // already open then it will be focused, in which case the |windowInfo|,
    // |client| and |settings| parameters will be ignored. If |inspect_element_at|
    // is non-NULL then the element at the specified (x,y) location will be
    // inspected. The |windowInfo| parameter will be ignored if this browser is
    // wrapped in a cef_browser_view_t.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_window_info_t)* windowInfo,
        _cef_client_t* client,
        const(_cef_browser_settings_t)* settings,
        const(cef_point_t)* inspect_element_at) nothrow show_dev_tools;

    ///
    // Explicitly close the associated DevTools browser, if any.
    ///
    void function (_cef_browser_host_t* self) nothrow close_dev_tools;

    ///
    // Returns true (1) if this browser currently has an associated DevTools
    // browser. Must be called on the browser process UI thread.
    ///
    int function (_cef_browser_host_t* self) nothrow has_dev_tools;

    ///
    // Send a function call message over the DevTools protocol. |message| must be
    // a UTF8-encoded JSON dictionary that contains "id" (int), "function"
    // (string) and "params" (dictionary, optional) values. See the DevTools
    // protocol documentation at https://chromedevtools.github.io/devtools-
    // protocol/ for details of supported functions and the expected "params"
    // dictionary contents. |message| will be copied if necessary. This function
    // will return true (1) if called on the UI thread and the message was
    // successfully submitted for validation, otherwise false (0). Validation will
    // be applied asynchronously and any messages that fail due to formatting
    // errors or missing parameters may be discarded without notification. Prefer
    // ExecuteDevToolsMethod if a more structured approach to message formatting
    // is desired.
    //
    // Every valid function call will result in an asynchronous function result or
    // error message that references the sent message "id". Event messages are
    // received while notifications are enabled (for example, between function
    // calls for "Page.enable" and "Page.disable"). All received messages will be
    // delivered to the observer(s) registered with AddDevToolsMessageObserver.
    // See cef_dev_tools_message_observer_t::OnDevToolsMessage documentation for
    // details of received message contents.
    //
    // Usage of the SendDevToolsMessage, ExecuteDevToolsMethod and
    // AddDevToolsMessageObserver functions does not require an active DevTools
    // front-end or remote-debugging session. Other active DevTools sessions will
    // continue to function independently. However, any modification of global
    // browser state by one session may not be reflected in the UI of other
    // sessions.
    //
    // Communication with the DevTools front-end (when displayed) can be logged
    // for development purposes by passing the `--devtools-protocol-log-
    // file=<path>` command-line flag.
    ///
    int function (
        _cef_browser_host_t* self,
        const(void)* message,
        size_t message_size) nothrow send_dev_tools_message;

    ///
    // Execute a function call over the DevTools protocol. This is a more
    // structured version of SendDevToolsMessage. |message_id| is an incremental
    // number that uniquely identifies the message (pass 0 to have the next number
    // assigned automatically based on previous values). |function| is the
    // function name. |params| are the function parameters, which may be NULL. See
    // the DevTools protocol documentation (linked above) for details of supported
    // functions and the expected |params| dictionary contents. This function will
    // return the assigned message ID if called on the UI thread and the message
    // was successfully submitted for validation, otherwise 0. See the
    // SendDevToolsMessage documentation for additional usage information.
    ///
    int function (
        _cef_browser_host_t* self,
        int message_id,
        const(cef_string_t)* method,
        _cef_dictionary_value_t* params) nothrow execute_dev_tools_method;

    ///
    // Add an observer for DevTools protocol messages (function results and
    // events). The observer will remain registered until the returned
    // Registration object is destroyed. See the SendDevToolsMessage documentation
    // for additional usage information.
    ///
    _cef_registration_t* function (
        _cef_browser_host_t* self,
        _cef_dev_tools_message_observer_t* observer) nothrow add_dev_tools_message_observer;

    ///
    // Retrieve a snapshot of current navigation entries as values sent to the
    // specified visitor. If |current_only| is true (1) only the current
    // navigation entry will be sent, otherwise all navigation entries will be
    // sent.
    ///
    void function (
        _cef_browser_host_t* self,
        _cef_navigation_entry_visitor_t* visitor,
        int current_only) nothrow get_navigation_entries;

    ///
    // If a misspelled word is currently selected in an editable node calling this
    // function will replace it with the specified |word|.
    ///
    void function (
        _cef_browser_host_t* self,
        const(cef_string_t)* word) nothrow replace_misspelling;

    ///
    // Add the specified |word| to the spelling dictionary.
    ///
    void function (
        _cef_browser_host_t* self,
        const(cef_string_t)* word) nothrow add_word_to_dictionary;

    ///
    // Returns true (1) if window rendering is disabled.
    ///
    int function (_cef_browser_host_t* self) nothrow is_window_rendering_disabled;

    ///
    // Notify the browser that the widget has been resized. The browser will first
    // call cef_render_handler_t::GetViewRect to get the new size and then call
    // cef_render_handler_t::OnPaint asynchronously with the updated regions. This
    // function is only used when window rendering is disabled.
    ///
    void function (_cef_browser_host_t* self) nothrow was_resized;

    ///
    // Notify the browser that it has been hidden or shown. Layouting and
    // cef_render_handler_t::OnPaint notification will stop when the browser is
    // hidden. This function is only used when window rendering is disabled.
    ///
    void function (_cef_browser_host_t* self, int hidden) nothrow was_hidden;

    ///
    // Send a notification to the browser that the screen info has changed. The
    // browser will then call cef_render_handler_t::GetScreenInfo to update the
    // screen information with the new values. This simulates moving the webview
    // window from one display to another, or changing the properties of the
    // current display. This function is only used when window rendering is
    // disabled.
    ///
    void function (_cef_browser_host_t* self) nothrow notify_screen_info_changed;

    ///
    // Invalidate the view. The browser will call cef_render_handler_t::OnPaint
    // asynchronously. This function is only used when window rendering is
    // disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        cef_paint_element_type_t type) nothrow invalidate;

    ///
    // Issue a BeginFrame request to Chromium.  Only valid when
    // cef_window_tInfo::external_begin_frame_enabled is set to true (1).
    ///
    void function (_cef_browser_host_t* self) nothrow send_external_begin_frame;

    ///
    // Send a key event to the browser.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_key_event_t)* event) nothrow send_key_event;

    ///
    // Send a mouse click event to the browser. The |x| and |y| coordinates are
    // relative to the upper-left corner of the view.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_mouse_event_t)* event,
        cef_mouse_button_type_t type,
        int mouseUp,
        int clickCount) nothrow send_mouse_click_event;

    ///
    // Send a mouse move event to the browser. The |x| and |y| coordinates are
    // relative to the upper-left corner of the view.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_mouse_event_t)* event,
        int mouseLeave) nothrow send_mouse_move_event;

    ///
    // Send a mouse wheel event to the browser. The |x| and |y| coordinates are
    // relative to the upper-left corner of the view. The |deltaX| and |deltaY|
    // values represent the movement delta in the X and Y directions respectively.
    // In order to scroll inside select popups with window rendering disabled
    // cef_render_handler_t::GetScreenPoint should be implemented properly.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_mouse_event_t)* event,
        int deltaX,
        int deltaY) nothrow send_mouse_wheel_event;

    ///
    // Send a touch event to the browser for a windowless browser.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_touch_event_t)* event) nothrow send_touch_event;

    ///
    // Send a focus event to the browser.
    ///
    void function (_cef_browser_host_t* self, int setFocus) nothrow send_focus_event;

    ///
    // Send a capture lost event to the browser.
    ///
    void function (_cef_browser_host_t* self) nothrow send_capture_lost_event;

    ///
    // Notify the browser that the window hosting it is about to be moved or
    // resized. This function is only used on Windows and Linux.
    ///
    void function (_cef_browser_host_t* self) nothrow notify_move_or_resize_started;

    ///
    // Returns the maximum rate in frames per second (fps) that
    // cef_render_handler_t:: OnPaint will be called for a windowless browser. The
    // actual fps may be lower if the browser cannot generate frames at the
    // requested rate. The minimum value is 1 and the maximum value is 60 (default
    // 30). This function can only be called on the UI thread.
    ///
    int function (_cef_browser_host_t* self) nothrow get_windowless_frame_rate;

    ///
    // Set the maximum rate in frames per second (fps) that cef_render_handler_t::
    // OnPaint will be called for a windowless browser. The actual fps may be
    // lower if the browser cannot generate frames at the requested rate. The
    // minimum value is 1 and the maximum value is 60 (default 30). Can also be
    // set at browser creation via cef_browser_tSettings.windowless_frame_rate.
    ///
    void function (
        _cef_browser_host_t* self,
        int frame_rate) nothrow set_windowless_frame_rate;

    ///
    // Begins a new composition or updates the existing composition. Blink has a
    // special node (a composition node) that allows the input function to change
    // text without affecting other DOM nodes. |text| is the optional text that
    // will be inserted into the composition node. |underlines| is an optional set
    // of ranges that will be underlined in the resulting text.
    // |replacement_range| is an optional range of the existing text that will be
    // replaced. |selection_range| is an optional range of the resulting text that
    // will be selected after insertion or replacement. The |replacement_range|
    // value is only used on OS X.
    //
    // This function may be called multiple times as the composition changes. When
    // the client is done making changes the composition should either be canceled
    // or completed. To cancel the composition call ImeCancelComposition. To
    // complete the composition call either ImeCommitText or
    // ImeFinishComposingText. Completion is usually signaled when:
    //   A. The client receives a WM_IME_COMPOSITION message with a GCS_RESULTSTR
    //      flag (on Windows), or;
    //   B. The client receives a "commit" signal of GtkIMContext (on Linux), or;
    //   C. insertText of NSTextInput is called (on Mac).
    //
    // This function is only used when window rendering is disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        const(cef_string_t)* text,
        size_t underlinesCount,
        const(cef_composition_underline_t)* underlines,
        const(cef_range_t)* replacement_range,
        const(cef_range_t)* selection_range) nothrow ime_set_composition;

    ///
    // Completes the existing composition by optionally inserting the specified
    // |text| into the composition node. |replacement_range| is an optional range
    // of the existing text that will be replaced. |relative_cursor_pos| is where
    // the cursor will be positioned relative to the current cursor position. See
    // comments on ImeSetComposition for usage. The |replacement_range| and
    // |relative_cursor_pos| values are only used on OS X. This function is only
    // used when window rendering is disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        const(cef_string_t)* text,
        const(cef_range_t)* replacement_range,
        int relative_cursor_pos) nothrow ime_commit_text;

    ///
    // Completes the existing composition by applying the current composition node
    // contents. If |keep_selection| is false (0) the current selection, if any,
    // will be discarded. See comments on ImeSetComposition for usage. This
    // function is only used when window rendering is disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        int keep_selection) nothrow ime_finish_composing_text;

    ///
    // Cancels the existing composition and discards the composition node contents
    // without applying them. See comments on ImeSetComposition for usage. This
    // function is only used when window rendering is disabled.
    ///
    void function (_cef_browser_host_t* self) nothrow ime_cancel_composition;

    ///
    // Call this function when the user drags the mouse into the web view (before
    // calling DragTargetDragOver/DragTargetLeave/DragTargetDrop). |drag_data|
    // should not contain file contents as this type of data is not allowed to be
    // dragged into the web view. File contents can be removed using
    // cef_drag_data_t::ResetFileContents (for example, if |drag_data| comes from
    // cef_render_handler_t::StartDragging). This function is only used when
    // window rendering is disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        _cef_drag_data_t* drag_data,
        const(_cef_mouse_event_t)* event,
        cef_drag_operations_mask_t allowed_ops) nothrow drag_target_drag_enter;

    ///
    // Call this function each time the mouse is moved across the web view during
    // a drag operation (after calling DragTargetDragEnter and before calling
    // DragTargetDragLeave/DragTargetDrop). This function is only used when window
    // rendering is disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_mouse_event_t)* event,
        cef_drag_operations_mask_t allowed_ops) nothrow drag_target_drag_over;

    ///
    // Call this function when the user drags the mouse out of the web view (after
    // calling DragTargetDragEnter). This function is only used when window
    // rendering is disabled.
    ///
    void function (_cef_browser_host_t* self) nothrow drag_target_drag_leave;

    ///
    // Call this function when the user completes the drag operation by dropping
    // the object onto the web view (after calling DragTargetDragEnter). The
    // object being dropped is |drag_data|, given as an argument to the previous
    // DragTargetDragEnter call. This function is only used when window rendering
    // is disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        const(_cef_mouse_event_t)* event) nothrow drag_target_drop;

    ///
    // Call this function when the drag operation started by a
    // cef_render_handler_t::StartDragging call has ended either in a drop or by
    // being cancelled. |x| and |y| are mouse coordinates relative to the upper-
    // left corner of the view. If the web view is both the drag source and the
    // drag target then all DragTarget* functions should be called before
    // DragSource* mthods. This function is only used when window rendering is
    // disabled.
    ///
    void function (
        _cef_browser_host_t* self,
        int x,
        int y,
        cef_drag_operations_mask_t op) nothrow drag_source_ended_at;

    ///
    // Call this function when the drag operation started by a
    // cef_render_handler_t::StartDragging call has completed. This function may
    // be called immediately without first calling DragSourceEndedAt to cancel a
    // drag operation. If the web view is both the drag source and the drag target
    // then all DragTarget* functions should be called before DragSource* mthods.
    // This function is only used when window rendering is disabled.
    ///
    void function (_cef_browser_host_t* self) nothrow drag_source_system_drag_ended;

    ///
    // Returns the current visible navigation entry for this browser. This
    // function can only be called on the UI thread.
    ///
    _cef_navigation_entry_t* function (
        _cef_browser_host_t* self) nothrow get_visible_navigation_entry;

    ///
    // Set accessibility state for all frames. |accessibility_state| may be
    // default, enabled or disabled. If |accessibility_state| is STATE_DEFAULT
    // then accessibility will be disabled by default and the state may be further
    // controlled with the "force-renderer-accessibility" and "disable-renderer-
    // accessibility" command-line switches. If |accessibility_state| is
    // STATE_ENABLED then accessibility will be enabled. If |accessibility_state|
    // is STATE_DISABLED then accessibility will be completely disabled.
    //
    // For windowed browsers accessibility will be enabled in Complete mode (which
    // corresponds to kAccessibilityModeComplete in Chromium). In this mode all
    // platform accessibility objects will be created and managed by Chromium's
    // internal implementation. The client needs only to detect the screen reader
    // and call this function appropriately. For example, on macOS the client can
    // handle the @"AXEnhancedUserStructure" accessibility attribute to detect
    // VoiceOver state changes and on Windows the client can handle WM_GETOBJECT
    // with OBJID_CLIENT to detect accessibility readers.
    //
    // For windowless browsers accessibility will be enabled in TreeOnly mode
    // (which corresponds to kAccessibilityModeWebContentsOnly in Chromium). In
    // this mode renderer accessibility is enabled, the full tree is computed, and
    // events are passed to CefAccessibiltyHandler, but platform accessibility
    // objects are not created. The client may implement platform accessibility
    // objects using CefAccessibiltyHandler callbacks if desired.
    ///
    void function (
        _cef_browser_host_t* self,
        cef_state_t accessibility_state) nothrow set_accessibility_state;

    ///
    // Enable notifications of auto resize via
    // cef_display_handler_t::OnAutoResize. Notifications are disabled by default.
    // |min_size| and |max_size| define the range of allowed sizes.
    ///
    void function (
        _cef_browser_host_t* self,
        int enabled,
        const(cef_size_t)* min_size,
        const(cef_size_t)* max_size) nothrow set_auto_resize_enabled;

    ///
    // Returns the extension hosted in this browser or NULL if no extension is
    // hosted. See cef_request_context_t::LoadExtension for details.
    ///
    _cef_extension_t* function (_cef_browser_host_t* self) nothrow get_extension;

    ///
    // Returns true (1) if this browser is hosting an extension background script.
    // Background hosts do not have a window and are not displayable. See
    // cef_request_context_t::LoadExtension for details.
    ///
    int function (_cef_browser_host_t* self) nothrow is_background_host;

    ///
    //  Set whether the browser's audio is muted.
    ///
    void function (_cef_browser_host_t* self, int mute) nothrow set_audio_muted;

    ///
    // Returns true (1) if the browser's audio is muted.  This function can only
    // be called on the UI thread.
    ///
    int function (_cef_browser_host_t* self) nothrow is_audio_muted;
}

alias cef_browser_host_t = _cef_browser_host_t;

///
// Create a new browser window using the window parameters specified by
// |windowInfo|. All values will be copied internally and the actual window will
// be created on the UI thread. If |request_context| is NULL the global request
// context will be used. This function can be called on any browser process
// thread and will not block. The optional |extra_info| parameter provides an
// opportunity to specify extra information specific to the created browser that
// will be passed to cef_render_process_handler_t::on_browser_created() in the
// render process.
///
int cef_browser_host_create_browser (
    const(cef_window_info_t)* windowInfo,
    _cef_client_t* client,
    const(cef_string_t)* url,
    const(_cef_browser_settings_t)* settings,
    _cef_dictionary_value_t* extra_info,
    _cef_request_context_t* request_context);

///
// Create a new browser window using the window parameters specified by
// |windowInfo|. If |request_context| is NULL the global request context will be
// used. This function can only be called on the browser process UI thread. The
// optional |extra_info| parameter provides an opportunity to specify extra
// information specific to the created browser that will be passed to
// cef_render_process_handler_t::on_browser_created() in the render process.
///
cef_browser_t* cef_browser_host_create_browser_sync (
    const(cef_window_info_t)* windowInfo,
    _cef_client_t* client,
    const(cef_string_t)* url,
    const(_cef_browser_settings_t)* settings,
    _cef_dictionary_value_t* extra_info,
    _cef_request_context_t* request_context);

// CEF_INCLUDE_CAPI_CEF_BROWSER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=d56cbf83d6faefa9f716c7308bf7007dad98697d$
//

extern (C):

///
// Structure used to implement browser process callbacks. The functions of this
// structure will be called on the browser process main thread unless otherwise
// indicated.
///
struct _cef_browser_process_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the browser process UI thread to retrieve the list of schemes
    // that should support cookies. If |include_defaults| is true (1) the default
    // schemes ("http", "https", "ws" and "wss") will also be supported. Providing
    // an NULL |schemes| value and setting |include_defaults| to false (0) will
    // disable all loading and saving of cookies.
    //
    // This state will apply to the cef_cookie_manager_t associated with the
    // global cef_request_context_t. It will also be used as the initial state for
    // any new cef_request_context_ts created by the client. After creating a new
    // cef_request_context_t the cef_cookie_manager_t::SetSupportedSchemes
    // function may be called on the associated cef_cookie_manager_t to futher
    // override these values.
    ///
    void function (
        _cef_browser_process_handler_t* self,
        cef_string_list_t schemes,
        int* include_defaults) nothrow get_cookieable_schemes;

    ///
    // Called on the browser process UI thread immediately after the CEF context
    // has been initialized.
    ///
    void function (
        _cef_browser_process_handler_t* self) nothrow on_context_initialized;

    ///
    // Called before a child process is launched. Will be called on the browser
    // process UI thread when launching a render process and on the browser
    // process IO thread when launching a GPU or plugin process. Provides an
    // opportunity to modify the child process command line. Do not keep a
    // reference to |command_line| outside of this function.
    ///
    void function (
        _cef_browser_process_handler_t* self,
        _cef_command_line_t* command_line) nothrow on_before_child_process_launch;

    ///
    // Return the handler for printing on Linux. If a print handler is not
    // provided then printing will not be supported on the Linux platform.
    ///
    _cef_print_handler_t* function (
        _cef_browser_process_handler_t* self) nothrow get_print_handler;

    ///
    // Called from any thread when work has been scheduled for the browser process
    // main (UI) thread. This callback is used in combination with CefSettings.
    // external_message_pump and cef_do_message_loop_work() in cases where the CEF
    // message loop must be integrated into an existing application message loop
    // (see additional comments and warnings on CefDoMessageLoopWork). This
    // callback should schedule a cef_do_message_loop_work() call to happen on the
    // main (UI) thread. |delay_ms| is the requested delay in milliseconds. If
    // |delay_ms| is <= 0 then the call should happen reasonably soon. If
    // |delay_ms| is > 0 then the call should be scheduled to happen after the
    // specified delay and any currently pending scheduled call should be
    // cancelled.
    ///
    void function (
        _cef_browser_process_handler_t* self,
        int64 delay_ms) nothrow on_schedule_message_pump_work;

    ///
    // Return the default client for use with a newly created browser window. If
    // null is returned the browser will be unmanaged (no callbacks will be
    // executed for that browser) and application shutdown will be blocked until
    // the browser window is closed manually. This function is currently only used
    // with the chrome runtime.
    ///
    _cef_client_t* function (
        _cef_browser_process_handler_t* self) nothrow get_default_client;
}

alias cef_browser_process_handler_t = _cef_browser_process_handler_t;

// CEF_INCLUDE_CAPI_CEF_BROWSER_PROCESS_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=5c540e617cf2782876defad365e85cd43932ffce$
//

extern (C):

///
// Generic callback structure used for asynchronous continuation.
///
struct _cef_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Continue processing.
    ///
    void function (_cef_callback_t* self) nothrow cont;

    ///
    // Cancel processing.
    ///
    void function (_cef_callback_t* self) nothrow cancel;
}

alias cef_callback_t = _cef_callback_t;

///
// Generic callback structure used for asynchronous completion.
///
struct _cef_completion_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called once the task is complete.
    ///
    void function (_cef_completion_callback_t* self) nothrow on_complete;
}

alias cef_completion_callback_t = _cef_completion_callback_t;

// CEF_INCLUDE_CAPI_CEF_CALLBACK_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=8d4cb3e0bbf230804c93898daa4a8b2866a2c1ce$
//

extern (C):

///
// Implement this structure to provide handler implementations.
///
struct _cef_client_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Return the handler for audio rendering events.
    ///
    _cef_audio_handler_t* function (_cef_client_t* self) nothrow get_audio_handler;

    ///
    // Return the handler for context menus. If no handler is provided the default
    // implementation will be used.
    ///
    _cef_context_menu_handler_t* function (
        _cef_client_t* self) nothrow get_context_menu_handler;

    ///
    // Return the handler for dialogs. If no handler is provided the default
    // implementation will be used.
    ///
    _cef_dialog_handler_t* function (_cef_client_t* self) nothrow get_dialog_handler;

    ///
    // Return the handler for browser display state events.
    ///
    _cef_display_handler_t* function (_cef_client_t* self) nothrow get_display_handler;

    ///
    // Return the handler for download events. If no handler is returned downloads
    // will not be allowed.
    ///
    _cef_download_handler_t* function (
        _cef_client_t* self) nothrow get_download_handler;

    ///
    // Return the handler for drag events.
    ///
    _cef_drag_handler_t* function (_cef_client_t* self) nothrow get_drag_handler;

    ///
    // Return the handler for find result events.
    ///
    _cef_find_handler_t* function (_cef_client_t* self) nothrow get_find_handler;

    ///
    // Return the handler for focus events.
    ///
    _cef_focus_handler_t* function (_cef_client_t* self) nothrow get_focus_handler;

    ///
    // Return the handler for JavaScript dialogs. If no handler is provided the
    // default implementation will be used.
    ///
    _cef_jsdialog_handler_t* function (
        _cef_client_t* self) nothrow get_jsdialog_handler;

    ///
    // Return the handler for keyboard events.
    ///
    _cef_keyboard_handler_t* function (
        _cef_client_t* self) nothrow get_keyboard_handler;

    ///
    // Return the handler for browser life span events.
    ///
    _cef_life_span_handler_t* function (
        _cef_client_t* self) nothrow get_life_span_handler;

    ///
    // Return the handler for browser load status events.
    ///
    _cef_load_handler_t* function (_cef_client_t* self) nothrow get_load_handler;

    ///
    // Return the handler for off-screen rendering events.
    ///
    _cef_render_handler_t* function (_cef_client_t* self) nothrow get_render_handler;

    ///
    // Return the handler for browser request events.
    ///
    _cef_request_handler_t* function (_cef_client_t* self) nothrow get_request_handler;

    ///
    // Called when a new message is received from a different process. Return true
    // (1) if the message was handled or false (0) otherwise. Do not keep a
    // reference to or attempt to access the message outside of this callback.
    ///
    int function (
        _cef_client_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        cef_process_id_t source_process,
        _cef_process_message_t* message) nothrow on_process_message_received;
}

alias cef_client_t = _cef_client_t;

// CEF_INCLUDE_CAPI_CEF_CLIENT_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=72ba5fe0cc6fe8081ec7b2b556e9022d1c6e8c61$
//

extern (C):

///
// Structure used to create and/or parse command line arguments. Arguments with
// '--', '-' and, on Windows, '/' prefixes are considered switches. Switches
// will always precede any arguments without switch prefixes. Switches can
// optionally have a value specified using the '=' delimiter (e.g.
// "-switch=value"). An argument of "--" will terminate switch parsing with all
// subsequent tokens, regardless of prefix, being interpreted as non-switch
// arguments. Switch names are considered case-insensitive. This structure can
// be used before cef_initialize() is called.
///
struct _cef_command_line_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. Do not call any other functions
    // if this function returns false (0).
    ///
    int function (_cef_command_line_t* self) nothrow is_valid;

    ///
    // Returns true (1) if the values of this object are read-only. Some APIs may
    // expose read-only objects.
    ///
    int function (_cef_command_line_t* self) nothrow is_read_only;

    ///
    // Returns a writable copy of this object.
    ///
    _cef_command_line_t* function (_cef_command_line_t* self) nothrow copy;

    ///
    // Initialize the command line with the specified |argc| and |argv| values.
    // The first argument must be the name of the program. This function is only
    // supported on non-Windows platforms.
    ///
    void function (
        _cef_command_line_t* self,
        int argc,
        const(char*)* argv) nothrow init_from_argv;

    ///
    // Initialize the command line with the string returned by calling
    // GetCommandLineW(). This function is only supported on Windows.
    ///
    void function (
        _cef_command_line_t* self,
        const(cef_string_t)* command_line) nothrow init_from_string;

    ///
    // Reset the command-line switches and arguments but leave the program
    // component unchanged.
    ///
    void function (_cef_command_line_t* self) nothrow reset;

    ///
    // Retrieve the original command line string as a vector of strings. The argv
    // array: { program, [(--|-|/)switch[=value]]*, [--], [argument]* }
    ///
    void function (_cef_command_line_t* self, cef_string_list_t argv) nothrow get_argv;

    ///
    // Constructs and returns the represented command line string. Use this
    // function cautiously because quoting behavior is unclear.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_command_line_t* self) nothrow get_command_line_string;

    ///
    // Get the program part of the command line string (the first item).
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_command_line_t* self) nothrow get_program;

    ///
    // Set the program part of the command line string (the first item).
    ///
    void function (
        _cef_command_line_t* self,
        const(cef_string_t)* program) nothrow set_program;

    ///
    // Returns true (1) if the command line has switches.
    ///
    int function (_cef_command_line_t* self) nothrow has_switches;

    ///
    // Returns true (1) if the command line contains the given switch.
    ///
    int function (
        _cef_command_line_t* self,
        const(cef_string_t)* name) nothrow has_switch;

    ///
    // Returns the value associated with the given switch. If the switch has no
    // value or isn't present this function returns the NULL string.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_command_line_t* self,
        const(cef_string_t)* name) nothrow get_switch_value;

    ///
    // Returns the map of switch names and values. If a switch has no value an
    // NULL string is returned.
    ///
    void function (
        _cef_command_line_t* self,
        cef_string_map_t switches) nothrow get_switches;

    ///
    // Add a switch to the end of the command line. If the switch has no value
    // pass an NULL value string.
    ///
    void function (
        _cef_command_line_t* self,
        const(cef_string_t)* name) nothrow append_switch;

    ///
    // Add a switch with the specified value to the end of the command line.
    ///
    void function (
        _cef_command_line_t* self,
        const(cef_string_t)* name,
        const(cef_string_t)* value) nothrow append_switch_with_value;

    ///
    // True if there are remaining command line arguments.
    ///
    int function (_cef_command_line_t* self) nothrow has_arguments;

    ///
    // Get the remaining command line arguments.
    ///
    void function (
        _cef_command_line_t* self,
        cef_string_list_t arguments) nothrow get_arguments;

    ///
    // Add an argument to the end of the command line.
    ///
    void function (
        _cef_command_line_t* self,
        const(cef_string_t)* argument) nothrow append_argument;

    ///
    // Insert a command before the current command. Common for debuggers, like
    // "valgrind" or "gdb --args".
    ///
    void function (
        _cef_command_line_t* self,
        const(cef_string_t)* wrapper) nothrow prepend_wrapper;
}

alias cef_command_line_t = _cef_command_line_t;

///
// Create a new cef_command_line_t instance.
///
cef_command_line_t* cef_command_line_create ();

///
// Returns the singleton global cef_command_line_t object. The returned object
// will be read-only.
///
cef_command_line_t* cef_command_line_get_global ();

// CEF_INCLUDE_CAPI_CEF_COMMAND_LINE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=fcb0328c54e5f629c24bfd232d75c31c372ab6ac$
//

extern (C):

///
// Callback structure used for continuation of custom context menu display.
///
struct _cef_run_context_menu_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Complete context menu display by selecting the specified |command_id| and
    // |event_flags|.
    ///
    void function (
        _cef_run_context_menu_callback_t* self,
        int command_id,
        cef_event_flags_t event_flags) nothrow cont;

    ///
    // Cancel context menu display.
    ///
    void function (_cef_run_context_menu_callback_t* self) nothrow cancel;
}

alias cef_run_context_menu_callback_t = _cef_run_context_menu_callback_t;

///
// Implement this structure to handle context menu events. The functions of this
// structure will be called on the UI thread.
///
struct _cef_context_menu_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called before a context menu is displayed. |params| provides information
    // about the context menu state. |model| initially contains the default
    // context menu. The |model| can be cleared to show no context menu or
    // modified to show a custom menu. Do not keep references to |params| or
    // |model| outside of this callback.
    ///
    void function (
        _cef_context_menu_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_context_menu_params_t* params,
        _cef_menu_model_t* model) nothrow on_before_context_menu;

    ///
    // Called to allow custom display of the context menu. |params| provides
    // information about the context menu state. |model| contains the context menu
    // model resulting from OnBeforeContextMenu. For custom display return true
    // (1) and execute |callback| either synchronously or asynchronously with the
    // selected command ID. For default display return false (0). Do not keep
    // references to |params| or |model| outside of this callback.
    ///
    int function (
        _cef_context_menu_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_context_menu_params_t* params,
        _cef_menu_model_t* model,
        _cef_run_context_menu_callback_t* callback) nothrow run_context_menu;

    ///
    // Called to execute a command selected from the context menu. Return true (1)
    // if the command was handled or false (0) for the default implementation. See
    // cef_menu_id_t for the command ids that have default implementations. All
    // user-defined command ids should be between MENU_ID_USER_FIRST and
    // MENU_ID_USER_LAST. |params| will have the same values as what was passed to
    // on_before_context_menu(). Do not keep a reference to |params| outside of
    // this callback.
    ///
    int function (
        _cef_context_menu_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_context_menu_params_t* params,
        int command_id,
        cef_event_flags_t event_flags) nothrow on_context_menu_command;

    ///
    // Called when the context menu is dismissed irregardless of whether the menu
    // was NULL or a command was selected.
    ///
    void function (
        _cef_context_menu_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame) nothrow on_context_menu_dismissed;
}

alias cef_context_menu_handler_t = _cef_context_menu_handler_t;

///
// Provides information about the context menu state. The ethods of this
// structure can only be accessed on browser process the UI thread.
///
struct _cef_context_menu_params_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the X coordinate of the mouse where the context menu was invoked.
    // Coords are relative to the associated RenderView's origin.
    ///
    int function (_cef_context_menu_params_t* self) nothrow get_xcoord;

    ///
    // Returns the Y coordinate of the mouse where the context menu was invoked.
    // Coords are relative to the associated RenderView's origin.
    ///
    int function (_cef_context_menu_params_t* self) nothrow get_ycoord;

    ///
    // Returns flags representing the type of node that the context menu was
    // invoked on.
    ///
    cef_context_menu_type_flags_t function (
        _cef_context_menu_params_t* self) nothrow get_type_flags;

    ///
    // Returns the URL of the link, if any, that encloses the node that the
    // context menu was invoked on.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_link_url;

    ///
    // Returns the link URL, if any, to be used ONLY for "copy link address". We
    // don't validate this field in the frontend process.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_unfiltered_link_url;

    ///
    // Returns the source URL, if any, for the element that the context menu was
    // invoked on. Example of elements with source URLs are img, audio, and video.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_source_url;

    ///
    // Returns true (1) if the context menu was invoked on an image which has non-
    // NULL contents.
    ///
    int function (_cef_context_menu_params_t* self) nothrow has_image_contents;

    ///
    // Returns the title text or the alt text if the context menu was invoked on
    // an image.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_title_text;

    ///
    // Returns the URL of the top level page that the context menu was invoked on.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_page_url;

    ///
    // Returns the URL of the subframe that the context menu was invoked on.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_frame_url;

    ///
    // Returns the character encoding of the subframe that the context menu was
    // invoked on.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_frame_charset;

    ///
    // Returns the type of context node that the context menu was invoked on.
    ///
    cef_context_menu_media_type_t function (
        _cef_context_menu_params_t* self) nothrow get_media_type;

    ///
    // Returns flags representing the actions supported by the media element, if
    // any, that the context menu was invoked on.
    ///
    cef_context_menu_media_state_flags_t function (
        _cef_context_menu_params_t* self) nothrow get_media_state_flags;

    ///
    // Returns the text of the selection, if any, that the context menu was
    // invoked on.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_selection_text;

    ///
    // Returns the text of the misspelled word, if any, that the context menu was
    // invoked on.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_context_menu_params_t* self) nothrow get_misspelled_word;

    ///
    // Returns true (1) if suggestions exist, false (0) otherwise. Fills in
    // |suggestions| from the spell check service for the misspelled word if there
    // is one.
    ///
    int function (
        _cef_context_menu_params_t* self,
        cef_string_list_t suggestions) nothrow get_dictionary_suggestions;

    ///
    // Returns true (1) if the context menu was invoked on an editable node.
    ///
    int function (_cef_context_menu_params_t* self) nothrow is_editable;

    ///
    // Returns true (1) if the context menu was invoked on an editable node where
    // spell-check is enabled.
    ///
    int function (_cef_context_menu_params_t* self) nothrow is_spell_check_enabled;

    ///
    // Returns flags representing the actions supported by the editable node, if
    // any, that the context menu was invoked on.
    ///
    cef_context_menu_edit_state_flags_t function (
        _cef_context_menu_params_t* self) nothrow get_edit_state_flags;

    ///
    // Returns true (1) if the context menu contains items specified by the
    // renderer process (for example, plugin placeholder or pepper plugin menu
    // items).
    ///
    int function (_cef_context_menu_params_t* self) nothrow is_custom_menu;

    ///
    // Returns true (1) if the context menu was invoked from a pepper plugin.
    ///
    int function (_cef_context_menu_params_t* self) nothrow is_pepper_menu;
}

alias cef_context_menu_params_t = _cef_context_menu_params_t;

// CEF_INCLUDE_CAPI_CEF_CONTEXT_MENU_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=2f5721138da26a9d7cce300a635b58dae9f51a4a$
//

extern (C):

///
// Structure used for managing cookies. The functions of this structure may be
// called on any thread unless otherwise indicated.
///
struct _cef_cookie_manager_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Set the schemes supported by this manager. If |include_defaults| is true
    // (1) the default schemes ("http", "https", "ws" and "wss") will also be
    // supported. Calling this function with an NULL |schemes| value and
    // |include_defaults| set to false (0) will disable all loading and saving of
    // cookies for this manager. If |callback| is non-NULL it will be executed
    // asnychronously on the UI thread after the change has been applied. Must be
    // called before any cookies are accessed.
    ///
    void function (
        _cef_cookie_manager_t* self,
        cef_string_list_t schemes,
        int include_defaults,
        _cef_completion_callback_t* callback) nothrow set_supported_schemes;

    ///
    // Visit all cookies on the UI thread. The returned cookies are ordered by
    // longest path, then by earliest creation date. Returns false (0) if cookies
    // cannot be accessed.
    ///
    int function (
        _cef_cookie_manager_t* self,
        _cef_cookie_visitor_t* visitor) nothrow visit_all_cookies;

    ///
    // Visit a subset of cookies on the UI thread. The results are filtered by the
    // given url scheme, host, domain and path. If |includeHttpOnly| is true (1)
    // HTTP-only cookies will also be included in the results. The returned
    // cookies are ordered by longest path, then by earliest creation date.
    // Returns false (0) if cookies cannot be accessed.
    ///
    int function (
        _cef_cookie_manager_t* self,
        const(cef_string_t)* url,
        int includeHttpOnly,
        _cef_cookie_visitor_t* visitor) nothrow visit_url_cookies;

    ///
    // Sets a cookie given a valid URL and explicit user-provided cookie
    // attributes. This function expects each attribute to be well-formed. It will
    // check for disallowed characters (e.g. the ';' character is disallowed
    // within the cookie value attribute) and fail without setting the cookie if
    // such characters are found. If |callback| is non-NULL it will be executed
    // asnychronously on the UI thread after the cookie has been set. Returns
    // false (0) if an invalid URL is specified or if cookies cannot be accessed.
    ///
    int function (
        _cef_cookie_manager_t* self,
        const(cef_string_t)* url,
        const(_cef_cookie_t)* cookie,
        _cef_set_cookie_callback_t* callback) nothrow set_cookie;

    ///
    // Delete all cookies that match the specified parameters. If both |url| and
    // |cookie_name| values are specified all host and domain cookies matching
    // both will be deleted. If only |url| is specified all host cookies (but not
    // domain cookies) irrespective of path will be deleted. If |url| is NULL all
    // cookies for all hosts and domains will be deleted. If |callback| is non-
    // NULL it will be executed asnychronously on the UI thread after the cookies
    // have been deleted. Returns false (0) if a non-NULL invalid URL is specified
    // or if cookies cannot be accessed. Cookies can alternately be deleted using
    // the Visit*Cookies() functions.
    ///
    int function (
        _cef_cookie_manager_t* self,
        const(cef_string_t)* url,
        const(cef_string_t)* cookie_name,
        _cef_delete_cookies_callback_t* callback) nothrow delete_cookies;

    ///
    // Flush the backing store (if any) to disk. If |callback| is non-NULL it will
    // be executed asnychronously on the UI thread after the flush is complete.
    // Returns false (0) if cookies cannot be accessed.
    ///
    int function (
        _cef_cookie_manager_t* self,
        _cef_completion_callback_t* callback) nothrow flush_store;
}

alias cef_cookie_manager_t = _cef_cookie_manager_t;

///
// Returns the global cookie manager. By default data will be stored at
// CefSettings.cache_path if specified or in memory otherwise. If |callback| is
// non-NULL it will be executed asnychronously on the UI thread after the
// manager's storage has been initialized. Using this function is equivalent to
// calling cef_request_context_t::cef_request_context_get_global_context()->GetD
// efaultCookieManager().
///
cef_cookie_manager_t* cef_cookie_manager_get_global_manager (
    _cef_completion_callback_t* callback);

///
// Structure to implement for visiting cookie values. The functions of this
// structure will always be called on the UI thread.
///
struct _cef_cookie_visitor_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called once for each cookie. |count| is the 0-based
    // index for the current cookie. |total| is the total number of cookies. Set
    // |deleteCookie| to true (1) to delete the cookie currently being visited.
    // Return false (0) to stop visiting cookies. This function may never be
    // called if no cookies are found.
    ///
    int function (
        _cef_cookie_visitor_t* self,
        const(_cef_cookie_t)* cookie,
        int count,
        int total,
        int* deleteCookie) nothrow visit;
}

alias cef_cookie_visitor_t = _cef_cookie_visitor_t;

///
// Structure to implement to be notified of asynchronous completion via
// cef_cookie_manager_t::set_cookie().
///
struct _cef_set_cookie_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called upon completion. |success| will be true (1) if
    // the cookie was set successfully.
    ///
    void function (_cef_set_cookie_callback_t* self, int success) nothrow on_complete;
}

alias cef_set_cookie_callback_t = _cef_set_cookie_callback_t;

///
// Structure to implement to be notified of asynchronous completion via
// cef_cookie_manager_t::delete_cookies().
///
struct _cef_delete_cookies_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called upon completion. |num_deleted| will be the
    // number of cookies that were deleted.
    ///
    void function (
        _cef_delete_cookies_callback_t* self,
        int num_deleted) nothrow on_complete;
}

alias cef_delete_cookies_callback_t = _cef_delete_cookies_callback_t;

// CEF_INCLUDE_CAPI_CEF_COOKIE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=2b24c7d99c59c669719b822f5ea19763d140b001$
//

extern (C):

///
// Crash reporting is configured using an INI-style config file named
// "crash_reporter.cfg". On Windows and Linux this file must be placed next to
// the main application executable. On macOS this file must be placed in the
// top-level app bundle Resources directory (e.g.
// "<appname>.app/Contents/Resources"). File contents are as follows:
//
//  # Comments start with a hash character and must be on their own line.
//
//  [Config]
//  ProductName=<Value of the "prod" crash key; defaults to "cef">
//  ProductVersion=<Value of the "ver" crash key; defaults to the CEF version>
//  AppName=<Windows only; App-specific folder name component for storing crash
//           information; default to "CEF">
//  ExternalHandler=<Windows only; Name of the external handler exe to use
//                   instead of re-launching the main exe; default to empty>
//  BrowserCrashForwardingEnabled=<macOS only; True if browser process crashes
//                                 should be forwarded to the system crash
//                                 reporter; default to false>
//  ServerURL=<crash server URL; default to empty>
//  RateLimitEnabled=<True if uploads should be rate limited; default to true>
//  MaxUploadsPerDay=<Max uploads per 24 hours, used if rate limit is enabled;
//                    default to 5>
//  MaxDatabaseSizeInMb=<Total crash report disk usage greater than this value
//                       will cause older reports to be deleted; default to 20>
//  MaxDatabaseAgeInDays=<Crash reports older than this value will be deleted;
//                        default to 5>
//
//  [CrashKeys]
//  my_key1=<small|medium|large>
//  my_key2=<small|medium|large>
//
// Config section:
//
// If "ProductName" and/or "ProductVersion" are set then the specified values
// will be included in the crash dump metadata. On macOS if these values are set
// to NULL then they will be retrieved from the Info.plist file using the
// "CFBundleName" and "CFBundleShortVersionString" keys respectively.
//
// If "AppName" is set on Windows then crash report information (metrics,
// database and dumps) will be stored locally on disk under the
// "C:\Users\[CurrentUser]\AppData\Local\[AppName]\User Data" folder. On other
// platforms the CefSettings.user_data_path value will be used.
//
// If "ExternalHandler" is set on Windows then the specified exe will be
// launched as the crashpad-handler instead of re-launching the main process
// exe. The value can be an absolute path or a path relative to the main exe
// directory. On Linux the CefSettings.browser_subprocess_path value will be
// used. On macOS the existing subprocess app bundle will be used.
//
// If "BrowserCrashForwardingEnabled" is set to true (1) on macOS then browser
// process crashes will be forwarded to the system crash reporter. This results
// in the crash UI dialog being displayed to the user and crash reports being
// logged under "~/Library/Logs/DiagnosticReports". Forwarding of crash reports
// from non-browser processes and Debug builds is always disabled.
//
// If "ServerURL" is set then crashes will be uploaded as a multi-part POST
// request to the specified URL. Otherwise, reports will only be stored locally
// on disk.
//
// If "RateLimitEnabled" is set to true (1) then crash report uploads will be
// rate limited as follows:
//  1. If "MaxUploadsPerDay" is set to a positive value then at most the
//     specified number of crashes will be uploaded in each 24 hour period.
//  2. If crash upload fails due to a network or server error then an
//     incremental backoff delay up to a maximum of 24 hours will be applied for
//     retries.
//  3. If a backoff delay is applied and "MaxUploadsPerDay" is > 1 then the
//     "MaxUploadsPerDay" value will be reduced to 1 until the client is
//     restarted. This helps to avoid an upload flood when the network or
//     server error is resolved.
// Rate limiting is not supported on Linux.
//
// If "MaxDatabaseSizeInMb" is set to a positive value then crash report storage
// on disk will be limited to that size in megabytes. For example, on Windows
// each dump is about 600KB so a "MaxDatabaseSizeInMb" value of 20 equates to
// about 34 crash reports stored on disk. Not supported on Linux.
//
// If "MaxDatabaseAgeInDays" is set to a positive value then crash reports older
// than the specified age in days will be deleted. Not supported on Linux.
//
// CrashKeys section:
//
// A maximum of 26 crash keys of each size can be specified for use by the
// application. Crash key values will be truncated based on the specified size
// (small = 64 bytes, medium = 256 bytes, large = 1024 bytes). The value of
// crash keys can be set from any thread or process using the
// CefSetCrashKeyValue function. These key/value pairs will be sent to the crash
// server along with the crash dump file.
///
int cef_crash_reporting_enabled ();

///
// Sets or clears a specific key-value pair from the crash metadata.
///
void cef_set_crash_key_value (
    const(cef_string_t)* key,
    const(cef_string_t)* value);

// CEF_INCLUDE_CAPI_CEF_CRASH_UTIL_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=86906c2e971fea7e479738f59bbf85d71ce31953$
//

extern (C):

///
// Callback structure for cef_browser_host_t::AddDevToolsMessageObserver. The
// functions of this structure will be called on the browser process UI thread.
///
struct _cef_dev_tools_message_observer_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called on receipt of a DevTools protocol message.
    // |browser| is the originating browser instance. |message| is a UTF8-encoded
    // JSON dictionary representing either a function result or an event.
    // |message| is only valid for the scope of this callback and should be copied
    // if necessary. Return true (1) if the message was handled or false (0) if
    // the message should be further processed and passed to the
    // OnDevToolsMethodResult or OnDevToolsEvent functions as appropriate.
    //
    // Method result dictionaries include an "id" (int) value that identifies the
    // orginating function call sent from cef_browser_host_t::SendDevToolsMessage,
    // and optionally either a "result" (dictionary) or "error" (dictionary)
    // value. The "error" dictionary will contain "code" (int) and "message"
    // (string) values. Event dictionaries include a "function" (string) value and
    // optionally a "params" (dictionary) value. See the DevTools protocol
    // documentation at https://chromedevtools.github.io/devtools-protocol/ for
    // details of supported function calls and the expected "result" or "params"
    // dictionary contents. JSON dictionaries can be parsed using the CefParseJSON
    // function if desired, however be aware of performance considerations when
    // parsing large messages (some of which may exceed 1MB in size).
    ///
    int function (
        _cef_dev_tools_message_observer_t* self,
        _cef_browser_t* browser,
        const(void)* message,
        size_t message_size) nothrow on_dev_tools_message;

    ///
    // Method that will be called after attempted execution of a DevTools protocol
    // function. |browser| is the originating browser instance. |message_id| is
    // the "id" value that identifies the originating function call message. If
    // the function succeeded |success| will be true (1) and |result| will be the
    // UTF8-encoded JSON "result" dictionary value (which may be NULL). If the
    // function failed |success| will be false (0) and |result| will be the
    // UTF8-encoded JSON "error" dictionary value. |result| is only valid for the
    // scope of this callback and should be copied if necessary. See the
    // OnDevToolsMessage documentation for additional details on |result|
    // contents.
    ///
    void function (
        _cef_dev_tools_message_observer_t* self,
        _cef_browser_t* browser,
        int message_id,
        int success,
        const(void)* result,
        size_t result_size) nothrow on_dev_tools_method_result;

    ///
    // Method that will be called on receipt of a DevTools protocol event.
    // |browser| is the originating browser instance. |function| is the "function"
    // value. |params| is the UTF8-encoded JSON "params" dictionary value (which
    // may be NULL). |params| is only valid for the scope of this callback and
    // should be copied if necessary. See the OnDevToolsMessage documentation for
    // additional details on |params| contents.
    ///
    void function (
        _cef_dev_tools_message_observer_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* method,
        const(void)* params,
        size_t params_size) nothrow on_dev_tools_event;

    ///
    // Method that will be called when the DevTools agent has attached. |browser|
    // is the originating browser instance. This will generally occur in response
    // to the first message sent while the agent is detached.
    ///
    void function (
        _cef_dev_tools_message_observer_t* self,
        _cef_browser_t* browser) nothrow on_dev_tools_agent_attached;

    ///
    // Method that will be called when the DevTools agent has detached. |browser|
    // is the originating browser instance. Any function results that were pending
    // before the agent became detached will not be delivered, and any active
    // event subscriptions will be canceled.
    ///
    void function (
        _cef_dev_tools_message_observer_t* self,
        _cef_browser_t* browser) nothrow on_dev_tools_agent_detached;
}

alias cef_dev_tools_message_observer_t = _cef_dev_tools_message_observer_t;

// CEF_INCLUDE_CAPI_CEF_DEVTOOLS_MESSAGE_OBSERVER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=3253c217564ae9a85a1e971298c32a35e4cad136$
//

extern (C):

///
// Callback structure for asynchronous continuation of file dialog requests.
///
struct _cef_file_dialog_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Continue the file selection. |selected_accept_filter| should be the 0-based
    // index of the value selected from the accept filters array passed to
    // cef_dialog_handler_t::OnFileDialog. |file_paths| should be a single value
    // or a list of values depending on the dialog mode. An NULL |file_paths|
    // value is treated the same as calling cancel().
    ///
    void function (
        _cef_file_dialog_callback_t* self,
        int selected_accept_filter,
        cef_string_list_t file_paths) nothrow cont;

    ///
    // Cancel the file selection.
    ///
    void function (_cef_file_dialog_callback_t* self) nothrow cancel;
}

alias cef_file_dialog_callback_t = _cef_file_dialog_callback_t;

///
// Implement this structure to handle dialog events. The functions of this
// structure will be called on the browser process UI thread.
///
struct _cef_dialog_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called to run a file chooser dialog. |mode| represents the type of dialog
    // to display. |title| to the title to be used for the dialog and may be NULL
    // to show the default title ("Open" or "Save" depending on the mode).
    // |default_file_path| is the path with optional directory and/or file name
    // component that should be initially selected in the dialog. |accept_filters|
    // are used to restrict the selectable file types and may any combination of
    // (a) valid lower-cased MIME types (e.g. "text/*" or "image/*"), (b)
    // individual file extensions (e.g. ".txt" or ".png"), or (c) combined
    // description and file extension delimited using "|" and ";" (e.g. "Image
    // Types|.png;.gif;.jpg"). |selected_accept_filter| is the 0-based index of
    // the filter that should be selected by default. To display a custom dialog
    // return true (1) and execute |callback| either inline or at a later time. To
    // display the default dialog return false (0).
    ///
    int function (
        _cef_dialog_handler_t* self,
        _cef_browser_t* browser,
        cef_file_dialog_mode_t mode,
        const(cef_string_t)* title,
        const(cef_string_t)* default_file_path,
        cef_string_list_t accept_filters,
        int selected_accept_filter,
        _cef_file_dialog_callback_t* callback) nothrow on_file_dialog;
}

alias cef_dialog_handler_t = _cef_dialog_handler_t;

// CEF_INCLUDE_CAPI_CEF_DIALOG_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=eada7e92085d96497f4e69f3e8a7e8aa6746b175$
//

import core.stdc.config;

extern (C):

///
// Implement this structure to handle events related to browser display state.
// The functions of this structure will be called on the UI thread.
///
struct _cef_display_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called when a frame's address has changed.
    ///
    void function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        const(cef_string_t)* url) nothrow on_address_change;

    ///
    // Called when the page title changes.
    ///
    void function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* title) nothrow on_title_change;

    ///
    // Called when the page icon changes.
    ///
    void function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        cef_string_list_t icon_urls) nothrow on_favicon_urlchange;

    ///
    // Called when web content in the page has toggled fullscreen mode. If
    // |fullscreen| is true (1) the content will automatically be sized to fill
    // the browser content area. If |fullscreen| is false (0) the content will
    // automatically return to its original size and position. The client is
    // responsible for resizing the browser if desired.
    ///
    void function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        int fullscreen) nothrow on_fullscreen_mode_change;

    ///
    // Called when the browser is about to display a tooltip. |text| contains the
    // text that will be displayed in the tooltip. To handle the display of the
    // tooltip yourself return true (1). Otherwise, you can optionally modify
    // |text| and then return false (0) to allow the browser to display the
    // tooltip. When window rendering is disabled the application is responsible
    // for drawing tooltips and the return value is ignored.
    ///
    int function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        cef_string_t* text) nothrow on_tooltip;

    ///
    // Called when the browser receives a status message. |value| contains the
    // text that will be displayed in the status message.
    ///
    void function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* value) nothrow on_status_message;

    ///
    // Called to display a console message. Return true (1) to stop the message
    // from being output to the console.
    ///
    int function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        cef_log_severity_t level,
        const(cef_string_t)* message,
        const(cef_string_t)* source,
        int line) nothrow on_console_message;

    ///
    // Called when auto-resize is enabled via
    // cef_browser_host_t::SetAutoResizeEnabled and the contents have auto-
    // resized. |new_size| will be the desired size in view coordinates. Return
    // true (1) if the resize was handled or false (0) for default handling.
    ///
    int function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        const(cef_size_t)* new_size) nothrow on_auto_resize;

    ///
    // Called when the overall page loading progress has changed. |progress|
    // ranges from 0.0 to 1.0.
    ///
    void function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        double progress) nothrow on_loading_progress_change;

    ///
    // Called when the browser's cursor has changed. If |type| is CT_CUSTOM then
    // |custom_cursor_info| will be populated with the custom cursor information.
    // Return true (1) if the cursor change was handled or false (0) for default
    // handling.
    ///
    int function (
        _cef_display_handler_t* self,
        _cef_browser_t* browser,
        c_ulong cursor,
        cef_cursor_type_t type,
        const(_cef_cursor_info_t)* custom_cursor_info) nothrow on_cursor_change;
}

alias cef_display_handler_t = _cef_display_handler_t;

// CEF_INCLUDE_CAPI_CEF_DISPLAY_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=055c506e7950abba3ec1c12adbbb1a9989cf5ac5$
//

extern (C):

///
// Structure to implement for visiting the DOM. The functions of this structure
// will be called on the render process main thread.
///
struct _cef_domvisitor_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method executed for visiting the DOM. The document object passed to this
    // function represents a snapshot of the DOM at the time this function is
    // executed. DOM objects are only valid for the scope of this function. Do not
    // keep references to or attempt to access any DOM objects outside the scope
    // of this function.
    ///
    void function (
        _cef_domvisitor_t* self,
        _cef_domdocument_t* document) nothrow visit;
}

alias cef_domvisitor_t = _cef_domvisitor_t;

///
// Structure used to represent a DOM document. The functions of this structure
// should only be called on the render process main thread thread.
///
struct _cef_domdocument_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the document type.
    ///
    cef_dom_document_type_t function (_cef_domdocument_t* self) nothrow get_type;

    ///
    // Returns the root document node.
    ///
    _cef_domnode_t* function (_cef_domdocument_t* self) nothrow get_document;

    ///
    // Returns the BODY node of an HTML document.
    ///
    _cef_domnode_t* function (_cef_domdocument_t* self) nothrow get_body;

    ///
    // Returns the HEAD node of an HTML document.
    ///
    _cef_domnode_t* function (_cef_domdocument_t* self) nothrow get_head;

    ///
    // Returns the title of an HTML document.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_domdocument_t* self) nothrow get_title;

    ///
    // Returns the document element with the specified ID value.
    ///
    _cef_domnode_t* function (
        _cef_domdocument_t* self,
        const(cef_string_t)* id) nothrow get_element_by_id;

    ///
    // Returns the node that currently has keyboard focus.
    ///
    _cef_domnode_t* function (_cef_domdocument_t* self) nothrow get_focused_node;

    ///
    // Returns true (1) if a portion of the document is selected.
    ///
    int function (_cef_domdocument_t* self) nothrow has_selection;

    ///
    // Returns the selection offset within the start node.
    ///
    int function (_cef_domdocument_t* self) nothrow get_selection_start_offset;

    ///
    // Returns the selection offset within the end node.
    ///
    int function (_cef_domdocument_t* self) nothrow get_selection_end_offset;

    ///
    // Returns the contents of this selection as markup.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_domdocument_t* self) nothrow get_selection_as_markup;

    ///
    // Returns the contents of this selection as text.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_domdocument_t* self) nothrow get_selection_as_text;

    ///
    // Returns the base URL for the document.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_domdocument_t* self) nothrow get_base_url;

    ///
    // Returns a complete URL based on the document base URL and the specified
    // partial URL.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_domdocument_t* self,
        const(cef_string_t)* partialURL) nothrow get_complete_url;
}

alias cef_domdocument_t = _cef_domdocument_t;

///
// Structure used to represent a DOM node. The functions of this structure
// should only be called on the render process main thread.
///
struct _cef_domnode_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the type for this node.
    ///
    cef_dom_node_type_t function (_cef_domnode_t* self) nothrow get_type;

    ///
    // Returns true (1) if this is a text node.
    ///
    int function (_cef_domnode_t* self) nothrow is_text;

    ///
    // Returns true (1) if this is an element node.
    ///
    int function (_cef_domnode_t* self) nothrow is_element;

    ///
    // Returns true (1) if this is an editable node.
    ///
    int function (_cef_domnode_t* self) nothrow is_editable;

    ///
    // Returns true (1) if this is a form control element node.
    ///
    int function (_cef_domnode_t* self) nothrow is_form_control_element;

    ///
    // Returns the type of this form control element node.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_domnode_t* self) nothrow get_form_control_element_type;

    ///
    // Returns true (1) if this object is pointing to the same handle as |that|
    // object.
    ///
    int function (_cef_domnode_t* self, _cef_domnode_t* that) nothrow is_same;

    ///
    // Returns the name of this node.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_domnode_t* self) nothrow get_name;

    ///
    // Returns the value of this node.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_domnode_t* self) nothrow get_value;

    ///
    // Set the value of this node. Returns true (1) on success.
    ///
    int function (_cef_domnode_t* self, const(cef_string_t)* value) nothrow set_value;

    ///
    // Returns the contents of this node as markup.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_domnode_t* self) nothrow get_as_markup;

    ///
    // Returns the document associated with this node.
    ///
    _cef_domdocument_t* function (_cef_domnode_t* self) nothrow get_document;

    ///
    // Returns the parent node.
    ///
    _cef_domnode_t* function (_cef_domnode_t* self) nothrow get_parent;

    ///
    // Returns the previous sibling node.
    ///
    _cef_domnode_t* function (_cef_domnode_t* self) nothrow get_previous_sibling;

    ///
    // Returns the next sibling node.
    ///
    _cef_domnode_t* function (_cef_domnode_t* self) nothrow get_next_sibling;

    ///
    // Returns true (1) if this node has child nodes.
    ///
    int function (_cef_domnode_t* self) nothrow has_children;

    ///
    // Return the first child node.
    ///
    _cef_domnode_t* function (_cef_domnode_t* self) nothrow get_first_child;

    ///
    // Returns the last child node.
    ///
    _cef_domnode_t* function (_cef_domnode_t* self) nothrow get_last_child;

    // The following functions are valid only for element nodes.

    ///
    // Returns the tag name of this element.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_domnode_t* self) nothrow get_element_tag_name;

    ///
    // Returns true (1) if this element has attributes.
    ///
    int function (_cef_domnode_t* self) nothrow has_element_attributes;

    ///
    // Returns true (1) if this element has an attribute named |attrName|.
    ///
    int function (
        _cef_domnode_t* self,
        const(cef_string_t)* attrName) nothrow has_element_attribute;

    ///
    // Returns the element attribute named |attrName|.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_domnode_t* self,
        const(cef_string_t)* attrName) nothrow get_element_attribute;

    ///
    // Returns a map of all element attributes.
    ///
    void function (
        _cef_domnode_t* self,
        cef_string_map_t attrMap) nothrow get_element_attributes;

    ///
    // Set the value for the element attribute named |attrName|. Returns true (1)
    // on success.
    ///
    int function (
        _cef_domnode_t* self,
        const(cef_string_t)* attrName,
        const(cef_string_t)* value) nothrow set_element_attribute;

    ///
    // Returns the inner text of the element.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_domnode_t* self) nothrow get_element_inner_text;

    ///
    // Returns the bounds of the element.
    ///
    cef_rect_t function (_cef_domnode_t* self) nothrow get_element_bounds;
}

alias cef_domnode_t = _cef_domnode_t;

// CEF_INCLUDE_CAPI_CEF_DOM_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=3399f17cc69d8fbd5c09f63f81680aa1f68454f0$
//

extern (C):

///
// Callback structure used to asynchronously continue a download.
///
struct _cef_before_download_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Call to continue the download. Set |download_path| to the full file path
    // for the download including the file name or leave blank to use the
    // suggested name and the default temp directory. Set |show_dialog| to true
    // (1) if you do wish to show the default "Save As" dialog.
    ///
    void function (
        _cef_before_download_callback_t* self,
        const(cef_string_t)* download_path,
        int show_dialog) nothrow cont;
}

alias cef_before_download_callback_t = _cef_before_download_callback_t;

///
// Callback structure used to asynchronously cancel a download.
///
struct _cef_download_item_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Call to cancel the download.
    ///
    void function (_cef_download_item_callback_t* self) nothrow cancel;

    ///
    // Call to pause the download.
    ///
    void function (_cef_download_item_callback_t* self) nothrow pause;

    ///
    // Call to resume the download.
    ///
    void function (_cef_download_item_callback_t* self) nothrow resume;
}

alias cef_download_item_callback_t = _cef_download_item_callback_t;

///
// Structure used to handle file downloads. The functions of this structure will
// called on the browser process UI thread.
///
struct _cef_download_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called before a download begins. |suggested_name| is the suggested name for
    // the download file. By default the download will be canceled. Execute
    // |callback| either asynchronously or in this function to continue the
    // download if desired. Do not keep a reference to |download_item| outside of
    // this function.
    ///
    void function (
        _cef_download_handler_t* self,
        _cef_browser_t* browser,
        _cef_download_item_t* download_item,
        const(cef_string_t)* suggested_name,
        _cef_before_download_callback_t* callback) nothrow on_before_download;

    ///
    // Called when a download's status or progress information has been updated.
    // This may be called multiple times before and after on_before_download().
    // Execute |callback| either asynchronously or in this function to cancel the
    // download if desired. Do not keep a reference to |download_item| outside of
    // this function.
    ///
    void function (
        _cef_download_handler_t* self,
        _cef_browser_t* browser,
        _cef_download_item_t* download_item,
        _cef_download_item_callback_t* callback) nothrow on_download_updated;
}

alias cef_download_handler_t = _cef_download_handler_t;

// CEF_INCLUDE_CAPI_CEF_DOWNLOAD_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=d6366977af5e2a3a71b4f57042208ff7ed524c6c$
//

extern (C):

///
// Structure used to represent a download item.
///
struct _cef_download_item_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. Do not call any other functions
    // if this function returns false (0).
    ///
    int function (_cef_download_item_t* self) nothrow is_valid;

    ///
    // Returns true (1) if the download is in progress.
    ///
    int function (_cef_download_item_t* self) nothrow is_in_progress;

    ///
    // Returns true (1) if the download is complete.
    ///
    int function (_cef_download_item_t* self) nothrow is_complete;

    ///
    // Returns true (1) if the download has been canceled or interrupted.
    ///
    int function (_cef_download_item_t* self) nothrow is_canceled;

    ///
    // Returns a simple speed estimate in bytes/s.
    ///
    int64 function (_cef_download_item_t* self) nothrow get_current_speed;

    ///
    // Returns the rough percent complete or -1 if the receive total size is
    // unknown.
    ///
    int function (_cef_download_item_t* self) nothrow get_percent_complete;

    ///
    // Returns the total number of bytes.
    ///
    int64 function (_cef_download_item_t* self) nothrow get_total_bytes;

    ///
    // Returns the number of received bytes.
    ///
    int64 function (_cef_download_item_t* self) nothrow get_received_bytes;

    ///
    // Returns the time that the download started.
    ///
    cef_time_t function (_cef_download_item_t* self) nothrow get_start_time;

    ///
    // Returns the time that the download ended.
    ///
    cef_time_t function (_cef_download_item_t* self) nothrow get_end_time;

    ///
    // Returns the full path to the downloaded or downloading file.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_download_item_t* self) nothrow get_full_path;

    ///
    // Returns the unique identifier for this download.
    ///
    uint32 function (_cef_download_item_t* self) nothrow get_id;

    ///
    // Returns the URL.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_download_item_t* self) nothrow get_url;

    ///
    // Returns the original URL before any redirections.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_download_item_t* self) nothrow get_original_url;

    ///
    // Returns the suggested file name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_download_item_t* self) nothrow get_suggested_file_name;

    ///
    // Returns the content disposition.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_download_item_t* self) nothrow get_content_disposition;

    ///
    // Returns the mime type.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_download_item_t* self) nothrow get_mime_type;
}

alias cef_download_item_t = _cef_download_item_t;

// CEF_INCLUDE_CAPI_CEF_DOWNLOAD_ITEM_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=6c8c654be3e69d872b3cfa6bdfb1adf615bff3ac$
//

extern (C):

///
// Structure used to represent drag data. The functions of this structure may be
// called on any thread.
///
struct _cef_drag_data_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns a copy of the current object.
    ///
    _cef_drag_data_t* function (_cef_drag_data_t* self) nothrow clone;

    ///
    // Returns true (1) if this object is read-only.
    ///
    int function (_cef_drag_data_t* self) nothrow is_read_only;

    ///
    // Returns true (1) if the drag data is a link.
    ///
    int function (_cef_drag_data_t* self) nothrow is_link;

    ///
    // Returns true (1) if the drag data is a text or html fragment.
    ///
    int function (_cef_drag_data_t* self) nothrow is_fragment;

    ///
    // Returns true (1) if the drag data is a file.
    ///
    int function (_cef_drag_data_t* self) nothrow is_file;

    ///
    // Return the link URL that is being dragged.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_drag_data_t* self) nothrow get_link_url;

    ///
    // Return the title associated with the link being dragged.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_drag_data_t* self) nothrow get_link_title;

    ///
    // Return the metadata, if any, associated with the link being dragged.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_drag_data_t* self) nothrow get_link_metadata;

    ///
    // Return the plain text fragment that is being dragged.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_drag_data_t* self) nothrow get_fragment_text;

    ///
    // Return the text/html fragment that is being dragged.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_drag_data_t* self) nothrow get_fragment_html;

    ///
    // Return the base URL that the fragment came from. This value is used for
    // resolving relative URLs and may be NULL.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_drag_data_t* self) nothrow get_fragment_base_url;

    ///
    // Return the name of the file being dragged out of the browser window.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_drag_data_t* self) nothrow get_file_name;

    ///
    // Write the contents of the file being dragged out of the web view into
    // |writer|. Returns the number of bytes sent to |writer|. If |writer| is NULL
    // this function will return the size of the file contents in bytes. Call
    // get_file_name() to get a suggested name for the file.
    ///
    size_t function (
        _cef_drag_data_t* self,
        _cef_stream_writer_t* writer) nothrow get_file_contents;

    ///
    // Retrieve the list of file names that are being dragged into the browser
    // window.
    ///
    int function (
        _cef_drag_data_t* self,
        cef_string_list_t names) nothrow get_file_names;

    ///
    // Set the link URL that is being dragged.
    ///
    void function (
        _cef_drag_data_t* self,
        const(cef_string_t)* url) nothrow set_link_url;

    ///
    // Set the title associated with the link being dragged.
    ///
    void function (
        _cef_drag_data_t* self,
        const(cef_string_t)* title) nothrow set_link_title;

    ///
    // Set the metadata associated with the link being dragged.
    ///
    void function (
        _cef_drag_data_t* self,
        const(cef_string_t)* data) nothrow set_link_metadata;

    ///
    // Set the plain text fragment that is being dragged.
    ///
    void function (
        _cef_drag_data_t* self,
        const(cef_string_t)* text) nothrow set_fragment_text;

    ///
    // Set the text/html fragment that is being dragged.
    ///
    void function (
        _cef_drag_data_t* self,
        const(cef_string_t)* html) nothrow set_fragment_html;

    ///
    // Set the base URL that the fragment came from.
    ///
    void function (
        _cef_drag_data_t* self,
        const(cef_string_t)* base_url) nothrow set_fragment_base_url;

    ///
    // Reset the file contents. You should do this before calling
    // cef_browser_host_t::DragTargetDragEnter as the web view does not allow us
    // to drag in this kind of data.
    ///
    void function (_cef_drag_data_t* self) nothrow reset_file_contents;

    ///
    // Add a file that is being dragged into the webview.
    ///
    void function (
        _cef_drag_data_t* self,
        const(cef_string_t)* path,
        const(cef_string_t)* display_name) nothrow add_file;

    ///
    // Get the image representation of drag data. May return NULL if no image
    // representation is available.
    ///
    _cef_image_t* function (_cef_drag_data_t* self) nothrow get_image;

    ///
    // Get the image hotspot (drag start location relative to image dimensions).
    ///
    cef_point_t function (_cef_drag_data_t* self) nothrow get_image_hotspot;

    ///
    // Returns true (1) if an image representation of drag data is available.
    ///
    int function (_cef_drag_data_t* self) nothrow has_image;
}

alias cef_drag_data_t = _cef_drag_data_t;

///
// Create a new cef_drag_data_t object.
///
cef_drag_data_t* cef_drag_data_create ();

// CEF_INCLUDE_CAPI_CEF_DRAG_DATA_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=78022908355fbf836799545e67ce2e4663b85fdf$
//

extern (C):

///
// Implement this structure to handle events related to dragging. The functions
// of this structure will be called on the UI thread.
///
struct _cef_drag_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called when an external drag event enters the browser window. |dragData|
    // contains the drag event data and |mask| represents the type of drag
    // operation. Return false (0) for default drag handling behavior or true (1)
    // to cancel the drag event.
    ///
    int function (
        _cef_drag_handler_t* self,
        _cef_browser_t* browser,
        _cef_drag_data_t* dragData,
        cef_drag_operations_mask_t mask) nothrow on_drag_enter;

    ///
    // Called whenever draggable regions for the browser window change. These can
    // be specified using the '-webkit-app-region: drag/no-drag' CSS-property. If
    // draggable regions are never defined in a document this function will also
    // never be called. If the last draggable region is removed from a document
    // this function will be called with an NULL vector.
    ///
    void function (
        _cef_drag_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        size_t regionsCount,
        const(cef_draggable_region_t)* regions) nothrow on_draggable_regions_changed;
}

alias cef_drag_handler_t = _cef_drag_handler_t;

// CEF_INCLUDE_CAPI_CEF_DRAG_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=b50087959cb679e4132f0fccfd23f01f76079018$
//

extern (C):

///
// Object representing an extension. Methods may be called on any thread unless
// otherwise indicated.
///
struct _cef_extension_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the unique extension identifier. This is calculated based on the
    // extension public key, if available, or on the extension path. See
    // https://developer.chrome.com/extensions/manifest/key for details.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_extension_t* self) nothrow get_identifier;

    ///
    // Returns the absolute path to the extension directory on disk. This value
    // will be prefixed with PK_DIR_RESOURCES if a relative path was passed to
    // cef_request_context_t::LoadExtension.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_extension_t* self) nothrow get_path;

    ///
    // Returns the extension manifest contents as a cef_dictionary_value_t object.
    // See https://developer.chrome.com/extensions/manifest for details.
    ///
    _cef_dictionary_value_t* function (_cef_extension_t* self) nothrow get_manifest;

    ///
    // Returns true (1) if this object is the same extension as |that| object.
    // Extensions are considered the same if identifier, path and loader context
    // match.
    ///
    int function (_cef_extension_t* self, _cef_extension_t* that) nothrow is_same;

    ///
    // Returns the handler for this extension. Will return NULL for internal
    // extensions or if no handler was passed to
    // cef_request_context_t::LoadExtension.
    ///
    _cef_extension_handler_t* function (_cef_extension_t* self) nothrow get_handler;

    ///
    // Returns the request context that loaded this extension. Will return NULL
    // for internal extensions or if the extension has been unloaded. See the
    // cef_request_context_t::LoadExtension documentation for more information
    // about loader contexts. Must be called on the browser process UI thread.
    ///
    _cef_request_context_t* function (
        _cef_extension_t* self) nothrow get_loader_context;

    ///
    // Returns true (1) if this extension is currently loaded. Must be called on
    // the browser process UI thread.
    ///
    int function (_cef_extension_t* self) nothrow is_loaded;

    ///
    // Unload this extension if it is not an internal extension and is currently
    // loaded. Will result in a call to
    // cef_extension_handler_t::OnExtensionUnloaded on success.
    ///
    void function (_cef_extension_t* self) nothrow unload;
}

alias cef_extension_t = _cef_extension_t;

// CEF_INCLUDE_CAPI_CEF_EXTENSION_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=c930140791b9e7d4238110e24fe17b9566a34ec9$
//

extern (C):

///
// Creates a directory and all parent directories if they don't already exist.
// Returns true (1) on successful creation or if the directory already exists.
// The directory is only readable by the current user. Calling this function on
// the browser process UI or IO threads is not allowed.
///
int cef_create_directory (const(cef_string_t)* full_path);

///
// Get the temporary directory provided by the system.
//
// WARNING: In general, you should use the temp directory variants below instead
// of this function. Those variants will ensure that the proper permissions are
// set so that other users on the system can't edit them while they're open
// (which could lead to security issues).
///
int cef_get_temp_directory (cef_string_t* temp_dir);

///
// Creates a new directory. On Windows if |prefix| is provided the new directory
// name is in the format of "prefixyyyy". Returns true (1) on success and sets
// |new_temp_path| to the full path of the directory that was created. The
// directory is only readable by the current user. Calling this function on the
// browser process UI or IO threads is not allowed.
///
int cef_create_new_temp_directory (
    const(cef_string_t)* prefix,
    cef_string_t* new_temp_path);

///
// Creates a directory within another directory. Extra characters will be
// appended to |prefix| to ensure that the new directory does not have the same
// name as an existing directory. Returns true (1) on success and sets |new_dir|
// to the full path of the directory that was created. The directory is only
// readable by the current user. Calling this function on the browser process UI
// or IO threads is not allowed.
///
int cef_create_temp_directory_in_directory (
    const(cef_string_t)* base_dir,
    const(cef_string_t)* prefix,
    cef_string_t* new_dir);

///
// Returns true (1) if the given path exists and is a directory. Calling this
// function on the browser process UI or IO threads is not allowed.
///
int cef_directory_exists (const(cef_string_t)* path);

///
// Deletes the given path whether it's a file or a directory. If |path| is a
// directory all contents will be deleted.  If |recursive| is true (1) any sub-
// directories and their contents will also be deleted (equivalent to executing
// "rm -rf", so use with caution). On POSIX environments if |path| is a symbolic
// link then only the symlink will be deleted. Returns true (1) on successful
// deletion or if |path| does not exist. Calling this function on the browser
// process UI or IO threads is not allowed.
///
int cef_delete_file (const(cef_string_t)* path, int recursive);

///
// Writes the contents of |src_dir| into a zip archive at |dest_file|. If
// |include_hidden_files| is true (1) files starting with "." will be included.
// Returns true (1) on success.  Calling this function on the browser process UI
// or IO threads is not allowed.
///
int cef_zip_directory (
    const(cef_string_t)* src_dir,
    const(cef_string_t)* dest_file,
    int include_hidden_files);

///
// Loads the existing "Certificate Revocation Lists" file that is managed by
// Google Chrome. This file can generally be found in Chrome's User Data
// directory (e.g. "C:\Users\[User]\AppData\Local\Google\Chrome\User Data\" on
// Windows) and is updated periodically by Chrome's component updater service.
// Must be called in the browser process after the context has been initialized.
// See https://dev.chromium.org/Home/chromium-security/crlsets for background.
///
void cef_load_crlsets_file (const(cef_string_t)* path);

// CEF_INCLUDE_CAPI_CEF_FILE_UTIL_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=2aa57426a91e10985a5e92830bc3bcd9287708d4$
//

extern (C):

///
// Implement this structure to handle events related to find results. The
// functions of this structure will be called on the UI thread.
///
struct _cef_find_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called to report find results returned by cef_browser_host_t::find().
    // |identifer| is the identifier passed to find(), |count| is the number of
    // matches currently identified, |selectionRect| is the location of where the
    // match was found (in window coordinates), |activeMatchOrdinal| is the
    // current position in the search results, and |finalUpdate| is true (1) if
    // this is the last find notification.
    ///
    void function (
        _cef_find_handler_t* self,
        _cef_browser_t* browser,
        int identifier,
        int count,
        const(cef_rect_t)* selectionRect,
        int activeMatchOrdinal,
        int finalUpdate) nothrow on_find_result;
}

alias cef_find_handler_t = _cef_find_handler_t;

// CEF_INCLUDE_CAPI_CEF_FIND_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=091dd994f37070e9d7c27d0e2f7411ea9cf068f5$
//

extern (C):

///
// Implement this structure to handle events related to focus. The functions of
// this structure will be called on the UI thread.
///
struct _cef_focus_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called when the browser component is about to loose focus. For instance, if
    // focus was on the last HTML element and the user pressed the TAB key. |next|
    // will be true (1) if the browser is giving focus to the next component and
    // false (0) if the browser is giving focus to the previous component.
    ///
    void function (
        _cef_focus_handler_t* self,
        _cef_browser_t* browser,
        int next) nothrow on_take_focus;

    ///
    // Called when the browser component is requesting focus. |source| indicates
    // where the focus request is originating from. Return false (0) to allow the
    // focus to be set or true (1) to cancel setting the focus.
    ///
    int function (
        _cef_focus_handler_t* self,
        _cef_browser_t* browser,
        cef_focus_source_t source) nothrow on_set_focus;

    ///
    // Called when the browser component has received focus.
    ///
    void function (
        _cef_focus_handler_t* self,
        _cef_browser_t* browser) nothrow on_got_focus;
}

alias cef_focus_handler_t = _cef_focus_handler_t;

// CEF_INCLUDE_CAPI_CEF_FOCUS_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=d8f114b44d02d96b5da0ec399c99091b9ceb6871$
//

extern (C):

///
// Structure used to represent a frame in the browser window. When used in the
// browser process the functions of this structure may be called on any thread
// unless otherwise indicated in the comments. When used in the render process
// the functions of this structure may only be called on the main thread.
///
struct _cef_frame_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // True if this object is currently attached to a valid frame.
    ///
    int function (_cef_frame_t* self) nothrow is_valid;

    ///
    // Execute undo in this frame.
    ///
    void function (_cef_frame_t* self) nothrow undo;

    ///
    // Execute redo in this frame.
    ///
    void function (_cef_frame_t* self) nothrow redo;

    ///
    // Execute cut in this frame.
    ///
    void function (_cef_frame_t* self) nothrow cut;

    ///
    // Execute copy in this frame.
    ///
    void function (_cef_frame_t* self) nothrow copy;

    ///
    // Execute paste in this frame.
    ///
    void function (_cef_frame_t* self) nothrow paste;

    ///
    // Execute delete in this frame.
    ///
    void function (_cef_frame_t* self) nothrow del;

    ///
    // Execute select all in this frame.
    ///
    void function (_cef_frame_t* self) nothrow select_all;

    ///
    // Save this frame's HTML source to a temporary file and open it in the
    // default text viewing application. This function can only be called from the
    // browser process.
    ///
    void function (_cef_frame_t* self) nothrow view_source;

    ///
    // Retrieve this frame's HTML source as a string sent to the specified
    // visitor.
    ///
    void function (
        _cef_frame_t* self,
        _cef_string_visitor_t* visitor) nothrow get_source;

    ///
    // Retrieve this frame's display text as a string sent to the specified
    // visitor.
    ///
    void function (
        _cef_frame_t* self,
        _cef_string_visitor_t* visitor) nothrow get_text;

    ///
    // Load the request represented by the |request| object.
    //
    // WARNING: This function will fail with "bad IPC message" reason
    // INVALID_INITIATOR_ORIGIN (213) unless you first navigate to the request
    // origin using some other mechanism (LoadURL, link click, etc).
    ///
    void function (_cef_frame_t* self, _cef_request_t* request) nothrow load_request;

    ///
    // Load the specified |url|.
    ///
    void function (_cef_frame_t* self, const(cef_string_t)* url) nothrow load_url;

    ///
    // Execute a string of JavaScript code in this frame. The |script_url|
    // parameter is the URL where the script in question can be found, if any. The
    // renderer may request this URL to show the developer the source of the
    // error.  The |start_line| parameter is the base line number to use for error
    // reporting.
    ///
    void function (
        _cef_frame_t* self,
        const(cef_string_t)* code,
        const(cef_string_t)* script_url,
        int start_line) nothrow execute_java_script;

    ///
    // Returns true (1) if this is the main (top-level) frame.
    ///
    int function (_cef_frame_t* self) nothrow is_main;

    ///
    // Returns true (1) if this is the focused frame.
    ///
    int function (_cef_frame_t* self) nothrow is_focused;

    ///
    // Returns the name for this frame. If the frame has an assigned name (for
    // example, set via the iframe "name" attribute) then that value will be
    // returned. Otherwise a unique name will be constructed based on the frame
    // parent hierarchy. The main (top-level) frame will always have an NULL name
    // value.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_frame_t* self) nothrow get_name;

    ///
    // Returns the globally unique identifier for this frame or < 0 if the
    // underlying frame does not yet exist.
    ///
    int64 function (_cef_frame_t* self) nothrow get_identifier;

    ///
    // Returns the parent of this frame or NULL if this is the main (top-level)
    // frame.
    ///
    _cef_frame_t* function (_cef_frame_t* self) nothrow get_parent;

    ///
    // Returns the URL currently loaded in this frame.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_frame_t* self) nothrow get_url;

    ///
    // Returns the browser that this frame belongs to.
    ///
    _cef_browser_t* function (_cef_frame_t* self) nothrow get_browser;

    ///
    // Get the V8 context associated with the frame. This function can only be
    // called from the render process.
    ///
    _cef_v8context_t* function (_cef_frame_t* self) nothrow get_v8context;

    ///
    // Visit the DOM document. This function can only be called from the render
    // process.
    ///
    void function (_cef_frame_t* self, _cef_domvisitor_t* visitor) nothrow visit_dom;

    ///
    // Create a new URL request that will be treated as originating from this
    // frame and the associated browser. This request may be intercepted by the
    // client via cef_resource_request_handler_t or cef_scheme_handler_factory_t.
    // Use cef_urlrequest_t::Create instead if you do not want the request to have
    // this association, in which case it may be handled differently (see
    // documentation on that function). Requests may originate from both the
    // browser process and the render process.
    //
    // For requests originating from the browser process:
    //   - POST data may only contain a single element of type PDE_TYPE_FILE or
    //     PDE_TYPE_BYTES.
    // For requests originating from the render process:
    //   - POST data may only contain a single element of type PDE_TYPE_BYTES.
    //   - If the response contains Content-Disposition or Mime-Type header values
    //     that would not normally be rendered then the response may receive
    //     special handling inside the browser (for example, via the file download
    //     code path instead of the URL request code path).
    //
    // The |request| object will be marked as read-only after calling this
    // function.
    ///
    _cef_urlrequest_t* function (
        _cef_frame_t* self,
        _cef_request_t* request,
        _cef_urlrequest_client_t* client) nothrow create_urlrequest;

    ///
    // Send a message to the specified |target_process|. Message delivery is not
    // guaranteed in all cases (for example, if the browser is closing,
    // navigating, or if the target process crashes). Send an ACK message back
    // from the target process if confirmation is required.
    ///
    void function (
        _cef_frame_t* self,
        cef_process_id_t target_process,
        _cef_process_message_t* message) nothrow send_process_message;
}

alias cef_frame_t = _cef_frame_t;

// CEF_INCLUDE_CAPI_CEF_FRAME_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=5afa8e95e6e7bddbd3c442e99b4c2843efb18c49$
//

extern (C):

///
// Container for a single image represented at different scale factors. All
// image representations should be the same size in density independent pixel
// (DIP) units. For example, if the image at scale factor 1.0 is 100x100 pixels
// then the image at scale factor 2.0 should be 200x200 pixels -- both images
// will display with a DIP size of 100x100 units. The functions of this
// structure can be called on any browser process thread.
///
struct _cef_image_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this Image is NULL.
    ///
    int function (_cef_image_t* self) nothrow is_empty;

    ///
    // Returns true (1) if this Image and |that| Image share the same underlying
    // storage. Will also return true (1) if both images are NULL.
    ///
    int function (_cef_image_t* self, _cef_image_t* that) nothrow is_same;

    ///
    // Add a bitmap image representation for |scale_factor|. Only 32-bit RGBA/BGRA
    // formats are supported. |pixel_width| and |pixel_height| are the bitmap
    // representation size in pixel coordinates. |pixel_data| is the array of
    // pixel data and should be |pixel_width| x |pixel_height| x 4 bytes in size.
    // |color_type| and |alpha_type| values specify the pixel format.
    ///
    int function (
        _cef_image_t* self,
        float scale_factor,
        int pixel_width,
        int pixel_height,
        cef_color_type_t color_type,
        cef_alpha_type_t alpha_type,
        const(void)* pixel_data,
        size_t pixel_data_size) nothrow add_bitmap;

    ///
    // Add a PNG image representation for |scale_factor|. |png_data| is the image
    // data of size |png_data_size|. Any alpha transparency in the PNG data will
    // be maintained.
    ///
    int function (
        _cef_image_t* self,
        float scale_factor,
        const(void)* png_data,
        size_t png_data_size) nothrow add_png;

    ///
    // Create a JPEG image representation for |scale_factor|. |jpeg_data| is the
    // image data of size |jpeg_data_size|. The JPEG format does not support
    // transparency so the alpha byte will be set to 0xFF for all pixels.
    ///
    int function (
        _cef_image_t* self,
        float scale_factor,
        const(void)* jpeg_data,
        size_t jpeg_data_size) nothrow add_jpeg;

    ///
    // Returns the image width in density independent pixel (DIP) units.
    ///
    size_t function (_cef_image_t* self) nothrow get_width;

    ///
    // Returns the image height in density independent pixel (DIP) units.
    ///
    size_t function (_cef_image_t* self) nothrow get_height;

    ///
    // Returns true (1) if this image contains a representation for
    // |scale_factor|.
    ///
    int function (_cef_image_t* self, float scale_factor) nothrow has_representation;

    ///
    // Removes the representation for |scale_factor|. Returns true (1) on success.
    ///
    int function (
        _cef_image_t* self,
        float scale_factor) nothrow remove_representation;

    ///
    // Returns information for the representation that most closely matches
    // |scale_factor|. |actual_scale_factor| is the actual scale factor for the
    // representation. |pixel_width| and |pixel_height| are the representation
    // size in pixel coordinates. Returns true (1) on success.
    ///
    int function (
        _cef_image_t* self,
        float scale_factor,
        float* actual_scale_factor,
        int* pixel_width,
        int* pixel_height) nothrow get_representation_info;

    ///
    // Returns the bitmap representation that most closely matches |scale_factor|.
    // Only 32-bit RGBA/BGRA formats are supported. |color_type| and |alpha_type|
    // values specify the desired output pixel format. |pixel_width| and
    // |pixel_height| are the output representation size in pixel coordinates.
    // Returns a cef_binary_value_t containing the pixel data on success or NULL
    // on failure.
    ///
    _cef_binary_value_t* function (
        _cef_image_t* self,
        float scale_factor,
        cef_color_type_t color_type,
        cef_alpha_type_t alpha_type,
        int* pixel_width,
        int* pixel_height) nothrow get_as_bitmap;

    ///
    // Returns the PNG representation that most closely matches |scale_factor|. If
    // |with_transparency| is true (1) any alpha transparency in the image will be
    // represented in the resulting PNG data. |pixel_width| and |pixel_height| are
    // the output representation size in pixel coordinates. Returns a
    // cef_binary_value_t containing the PNG image data on success or NULL on
    // failure.
    ///
    _cef_binary_value_t* function (
        _cef_image_t* self,
        float scale_factor,
        int with_transparency,
        int* pixel_width,
        int* pixel_height) nothrow get_as_png;

    ///
    // Returns the JPEG representation that most closely matches |scale_factor|.
    // |quality| determines the compression level with 0 == lowest and 100 ==
    // highest. The JPEG format does not support alpha transparency and the alpha
    // channel, if any, will be discarded. |pixel_width| and |pixel_height| are
    // the output representation size in pixel coordinates. Returns a
    // cef_binary_value_t containing the JPEG image data on success or NULL on
    // failure.
    ///
    _cef_binary_value_t* function (
        _cef_image_t* self,
        float scale_factor,
        int quality,
        int* pixel_width,
        int* pixel_height) nothrow get_as_jpeg;
}

alias cef_image_t = _cef_image_t;

///
// Create a new cef_image_t. It will initially be NULL. Use the Add*() functions
// to add representations at different scale factors.
///
cef_image_t* cef_image_create ();

// CEF_INCLUDE_CAPI_CEF_IMAGE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=e68da1a5db612699b7b727edea2bb629f5d67103$
//

extern (C):

///
// Callback structure used for asynchronous continuation of JavaScript dialog
// requests.
///
struct _cef_jsdialog_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Continue the JS dialog request. Set |success| to true (1) if the OK button
    // was pressed. The |user_input| value should be specified for prompt dialogs.
    ///
    void function (
        _cef_jsdialog_callback_t* self,
        int success,
        const(cef_string_t)* user_input) nothrow cont;
}

alias cef_jsdialog_callback_t = _cef_jsdialog_callback_t;

///
// Implement this structure to handle events related to JavaScript dialogs. The
// functions of this structure will be called on the UI thread.
///
struct _cef_jsdialog_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called to run a JavaScript dialog. If |origin_url| is non-NULL it can be
    // passed to the CefFormatUrlForSecurityDisplay function to retrieve a secure
    // and user-friendly display string. The |default_prompt_text| value will be
    // specified for prompt dialogs only. Set |suppress_message| to true (1) and
    // return false (0) to suppress the message (suppressing messages is
    // preferable to immediately executing the callback as this is used to detect
    // presumably malicious behavior like spamming alert messages in
    // onbeforeunload). Set |suppress_message| to false (0) and return false (0)
    // to use the default implementation (the default implementation will show one
    // modal dialog at a time and suppress any additional dialog requests until
    // the displayed dialog is dismissed). Return true (1) if the application will
    // use a custom dialog or if the callback has been executed immediately.
    // Custom dialogs may be either modal or modeless. If a custom dialog is used
    // the application must execute |callback| once the custom dialog is
    // dismissed.
    ///
    int function (
        _cef_jsdialog_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* origin_url,
        cef_jsdialog_type_t dialog_type,
        const(cef_string_t)* message_text,
        const(cef_string_t)* default_prompt_text,
        _cef_jsdialog_callback_t* callback,
        int* suppress_message) nothrow on_jsdialog;

    ///
    // Called to run a dialog asking the user if they want to leave a page. Return
    // false (0) to use the default dialog implementation. Return true (1) if the
    // application will use a custom dialog or if the callback has been executed
    // immediately. Custom dialogs may be either modal or modeless. If a custom
    // dialog is used the application must execute |callback| once the custom
    // dialog is dismissed.
    ///
    int function (
        _cef_jsdialog_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* message_text,
        int is_reload,
        _cef_jsdialog_callback_t* callback) nothrow on_before_unload_dialog;

    ///
    // Called to cancel any pending dialogs and reset any saved dialog state. Will
    // be called due to events like page navigation irregardless of whether any
    // dialogs are currently pending.
    ///
    void function (
        _cef_jsdialog_handler_t* self,
        _cef_browser_t* browser) nothrow on_reset_dialog_state;

    ///
    // Called when the default implementation dialog is closed.
    ///
    void function (
        _cef_jsdialog_handler_t* self,
        _cef_browser_t* browser) nothrow on_dialog_closed;
}

alias cef_jsdialog_handler_t = _cef_jsdialog_handler_t;

// CEF_INCLUDE_CAPI_CEF_JSDIALOG_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=70108de432674485dee079e541e0dacd6a437961$
//

extern (C):

///
// Implement this structure to handle events related to keyboard input. The
// functions of this structure will be called on the UI thread.
///
struct _cef_keyboard_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called before a keyboard event is sent to the renderer. |event| contains
    // information about the keyboard event. |os_event| is the operating system
    // event message, if any. Return true (1) if the event was handled or false
    // (0) otherwise. If the event will be handled in on_key_event() as a keyboard
    // shortcut set |is_keyboard_shortcut| to true (1) and return false (0).
    ///
    int function (
        _cef_keyboard_handler_t* self,
        _cef_browser_t* browser,
        const(_cef_key_event_t)* event,
        OS_EVENT* os_event,
        int* is_keyboard_shortcut) nothrow on_pre_key_event;

    ///
    // Called after the renderer and JavaScript in the page has had a chance to
    // handle the event. |event| contains information about the keyboard event.
    // |os_event| is the operating system event message, if any. Return true (1)
    // if the keyboard event was handled or false (0) otherwise.
    ///
    int function (
        _cef_keyboard_handler_t* self,
        _cef_browser_t* browser,
        const(_cef_key_event_t)* event,
        OS_EVENT* os_event) nothrow on_key_event;
}

alias cef_keyboard_handler_t = _cef_keyboard_handler_t;

// CEF_INCLUDE_CAPI_CEF_KEYBOARD_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=d6e91d55d41f729dca94ba5766f57849f29d0796$
//

extern (C):

///
// Implement this structure to handle events related to browser life span. The
// functions of this structure will be called on the UI thread unless otherwise
// indicated.
///
struct _cef_life_span_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the UI thread before a new popup browser is created. The
    // |browser| and |frame| values represent the source of the popup request. The
    // |target_url| and |target_frame_name| values indicate where the popup
    // browser should navigate and may be NULL if not specified with the request.
    // The |target_disposition| value indicates where the user intended to open
    // the popup (e.g. current tab, new tab, etc). The |user_gesture| value will
    // be true (1) if the popup was opened via explicit user gesture (e.g.
    // clicking a link) or false (0) if the popup opened automatically (e.g. via
    // the DomContentLoaded event). The |popupFeatures| structure contains
    // additional information about the requested popup window. To allow creation
    // of the popup browser optionally modify |windowInfo|, |client|, |settings|
    // and |no_javascript_access| and return false (0). To cancel creation of the
    // popup browser return true (1). The |client| and |settings| values will
    // default to the source browser's values. If the |no_javascript_access| value
    // is set to false (0) the new browser will not be scriptable and may not be
    // hosted in the same renderer process as the source browser. Any
    // modifications to |windowInfo| will be ignored if the parent browser is
    // wrapped in a cef_browser_view_t. Popup browser creation will be canceled if
    // the parent browser is destroyed before the popup browser creation completes
    // (indicated by a call to OnAfterCreated for the popup browser). The
    // |extra_info| parameter provides an opportunity to specify extra information
    // specific to the created popup browser that will be passed to
    // cef_render_process_handler_t::on_browser_created() in the render process.
    ///
    int function (
        _cef_life_span_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        const(cef_string_t)* target_url,
        const(cef_string_t)* target_frame_name,
        cef_window_open_disposition_t target_disposition,
        int user_gesture,
        const(_cef_popup_features_t)* popupFeatures,
        _cef_window_info_t* windowInfo,
        _cef_client_t** client,
        _cef_browser_settings_t* settings,
        _cef_dictionary_value_t** extra_info,
        int* no_javascript_access) nothrow on_before_popup;

    ///
    // Called after a new browser is created. This callback will be the first
    // notification that references |browser|.
    ///
    void function (
        _cef_life_span_handler_t* self,
        _cef_browser_t* browser) nothrow on_after_created;

    ///
    // Called when a browser has recieved a request to close. This may result
    // directly from a call to cef_browser_host_t::*close_browser() or indirectly
    // if the browser is parented to a top-level window created by CEF and the
    // user attempts to close that window (by clicking the 'X', for example). The
    // do_close() function will be called after the JavaScript 'onunload' event
    // has been fired.
    //
    // An application should handle top-level owner window close notifications by
    // calling cef_browser_host_t::try_close_browser() or
    // cef_browser_host_t::CloseBrowser(false (0)) instead of allowing the window
    // to close immediately (see the examples below). This gives CEF an
    // opportunity to process the 'onbeforeunload' event and optionally cancel the
    // close before do_close() is called.
    //
    // When windowed rendering is enabled CEF will internally create a window or
    // view to host the browser. In that case returning false (0) from do_close()
    // will send the standard close notification to the browser's top-level owner
    // window (e.g. WM_CLOSE on Windows, performClose: on OS X, "delete_event" on
    // Linux or cef_window_delegate_t::can_close() callback from Views). If the
    // browser's host window/view has already been destroyed (via view hierarchy
    // tear-down, for example) then do_close() will not be called for that browser
    // since is no longer possible to cancel the close.
    //
    // When windowed rendering is disabled returning false (0) from do_close()
    // will cause the browser object to be destroyed immediately.
    //
    // If the browser's top-level owner window requires a non-standard close
    // notification then send that notification from do_close() and return true
    // (1).
    //
    // The cef_life_span_handler_t::on_before_close() function will be called
    // after do_close() (if do_close() is called) and immediately before the
    // browser object is destroyed. The application should only exit after
    // on_before_close() has been called for all existing browsers.
    //
    // The below examples describe what should happen during window close when the
    // browser is parented to an application-provided top-level window.
    //
    // Example 1: Using cef_browser_host_t::try_close_browser(). This is
    // recommended for clients using standard close handling and windows created
    // on the browser process UI thread. 1.  User clicks the window close button
    // which sends a close notification to
    //     the application's top-level window.
    // 2.  Application's top-level window receives the close notification and
    //     calls TryCloseBrowser() (which internally calls CloseBrowser(false)).
    //     TryCloseBrowser() returns false so the client cancels the window close.
    // 3.  JavaScript 'onbeforeunload' handler executes and shows the close
    //     confirmation dialog (which can be overridden via
    //     CefJSDialogHandler::OnBeforeUnloadDialog()).
    // 4.  User approves the close. 5.  JavaScript 'onunload' handler executes. 6.
    // CEF sends a close notification to the application's top-level window
    //     (because DoClose() returned false by default).
    // 7.  Application's top-level window receives the close notification and
    //     calls TryCloseBrowser(). TryCloseBrowser() returns true so the client
    //     allows the window close.
    // 8.  Application's top-level window is destroyed. 9.  Application's
    // on_before_close() handler is called and the browser object
    //     is destroyed.
    // 10. Application exits by calling cef_quit_message_loop() if no other
    // browsers
    //     exist.
    //
    // Example 2: Using cef_browser_host_t::CloseBrowser(false (0)) and
    // implementing the do_close() callback. This is recommended for clients using
    // non-standard close handling or windows that were not created on the browser
    // process UI thread. 1.  User clicks the window close button which sends a
    // close notification to
    //     the application's top-level window.
    // 2.  Application's top-level window receives the close notification and:
    //     A. Calls CefBrowserHost::CloseBrowser(false).
    //     B. Cancels the window close.
    // 3.  JavaScript 'onbeforeunload' handler executes and shows the close
    //     confirmation dialog (which can be overridden via
    //     CefJSDialogHandler::OnBeforeUnloadDialog()).
    // 4.  User approves the close. 5.  JavaScript 'onunload' handler executes. 6.
    // Application's do_close() handler is called. Application will:
    //     A. Set a flag to indicate that the next close attempt will be allowed.
    //     B. Return false.
    // 7.  CEF sends an close notification to the application's top-level window.
    // 8.  Application's top-level window receives the close notification and
    //     allows the window to close based on the flag from #6B.
    // 9.  Application's top-level window is destroyed. 10. Application's
    // on_before_close() handler is called and the browser object
    //     is destroyed.
    // 11. Application exits by calling cef_quit_message_loop() if no other
    // browsers
    //     exist.
    ///
    int function (
        _cef_life_span_handler_t* self,
        _cef_browser_t* browser) nothrow do_close;

    ///
    // Called just before a browser is destroyed. Release all references to the
    // browser object and do not attempt to execute any functions on the browser
    // object (other than GetIdentifier or IsSame) after this callback returns.
    // This callback will be the last notification that references |browser| on
    // the UI thread. Any in-progress network requests associated with |browser|
    // will be aborted when the browser is destroyed, and
    // cef_resource_request_handler_t callbacks related to those requests may
    // still arrive on the IO thread after this function is called. See do_close()
    // documentation for additional usage information.
    ///
    void function (
        _cef_life_span_handler_t* self,
        _cef_browser_t* browser) nothrow on_before_close;
}

alias cef_life_span_handler_t = _cef_life_span_handler_t;

// CEF_INCLUDE_CAPI_CEF_LIFE_SPAN_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=fa3cb1461b9d363c6c7d961f9e291c2fe736170e$
//

extern (C):

///
// Implement this structure to handle events related to browser load status. The
// functions of this structure will be called on the browser process UI thread
// or render process main thread (TID_RENDERER).
///
struct _cef_load_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called when the loading state has changed. This callback will be executed
    // twice -- once when loading is initiated either programmatically or by user
    // action, and once when loading is terminated due to completion, cancellation
    // of failure. It will be called before any calls to OnLoadStart and after all
    // calls to OnLoadError and/or OnLoadEnd.
    ///
    void function (
        _cef_load_handler_t* self,
        _cef_browser_t* browser,
        int isLoading,
        int canGoBack,
        int canGoForward) nothrow on_loading_state_change;

    ///
    // Called after a navigation has been committed and before the browser begins
    // loading contents in the frame. The |frame| value will never be NULL -- call
    // the is_main() function to check if this frame is the main frame.
    // |transition_type| provides information about the source of the navigation
    // and an accurate value is only available in the browser process. Multiple
    // frames may be loading at the same time. Sub-frames may start or continue
    // loading after the main frame load has ended. This function will not be
    // called for same page navigations (fragments, history state, etc.) or for
    // navigations that fail or are canceled before commit. For notification of
    // overall browser load status use OnLoadingStateChange instead.
    ///
    void function (
        _cef_load_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        cef_transition_type_t transition_type) nothrow on_load_start;

    ///
    // Called when the browser is done loading a frame. The |frame| value will
    // never be NULL -- call the is_main() function to check if this frame is the
    // main frame. Multiple frames may be loading at the same time. Sub-frames may
    // start or continue loading after the main frame load has ended. This
    // function will not be called for same page navigations (fragments, history
    // state, etc.) or for navigations that fail or are canceled before commit.
    // For notification of overall browser load status use OnLoadingStateChange
    // instead.
    ///
    void function (
        _cef_load_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        int httpStatusCode) nothrow on_load_end;

    ///
    // Called when a navigation fails or is canceled. This function may be called
    // by itself if before commit or in combination with OnLoadStart/OnLoadEnd if
    // after commit. |errorCode| is the error code number, |errorText| is the
    // error text and |failedUrl| is the URL that failed to load. See
    // net\base\net_error_list.h for complete descriptions of the error codes.
    ///
    void function (
        _cef_load_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        cef_errorcode_t errorCode,
        const(cef_string_t)* errorText,
        const(cef_string_t)* failedUrl) nothrow on_load_error;
}

alias cef_load_handler_t = _cef_load_handler_t;

// CEF_INCLUDE_CAPI_CEF_LOAD_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=4f4a0d76efaf87055ebf5e784f5d1b69fafdabc2$
//

extern (C):

///
// Supports discovery of and communication with media devices on the local
// network via the Cast and DIAL protocols. The functions of this structure may
// be called on any browser process thread unless otherwise indicated.
///
struct _cef_media_router_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Add an observer for MediaRouter events. The observer will remain registered
    // until the returned Registration object is destroyed.
    ///
    _cef_registration_t* function (
        _cef_media_router_t* self,
        _cef_media_observer_t* observer) nothrow add_observer;

    ///
    // Returns a MediaSource object for the specified media source URN. Supported
    // URN schemes include "cast:" and "dial:", and will be already known by the
    // client application (e.g. "cast:<appId>?clientId=<clientId>").
    ///
    _cef_media_source_t* function (
        _cef_media_router_t* self,
        const(cef_string_t)* urn) nothrow get_source;

    ///
    // Trigger an asynchronous call to cef_media_observer_t::OnSinks on all
    // registered observers.
    ///
    void function (_cef_media_router_t* self) nothrow notify_current_sinks;

    ///
    // Create a new route between |source| and |sink|. Source and sink must be
    // valid, compatible (as reported by cef_media_sink_t::IsCompatibleWith), and
    // a route between them must not already exist. |callback| will be executed on
    // success or failure. If route creation succeeds it will also trigger an
    // asynchronous call to cef_media_observer_t::OnRoutes on all registered
    // observers.
    ///
    void function (
        _cef_media_router_t* self,
        _cef_media_source_t* source,
        _cef_media_sink_t* sink,
        _cef_media_route_create_callback_t* callback) nothrow create_route;

    ///
    // Trigger an asynchronous call to cef_media_observer_t::OnRoutes on all
    // registered observers.
    ///
    void function (_cef_media_router_t* self) nothrow notify_current_routes;
}

alias cef_media_router_t = _cef_media_router_t;

///
// Returns the MediaRouter object associated with the global request context.
// Equivalent to calling cef_request_context_t::cef_request_context_get_global_c
// ontext()->get_media_router().
///
cef_media_router_t* cef_media_router_get_global ();

///
// Implemented by the client to observe MediaRouter events and registered via
// cef_media_router_t::AddObserver. The functions of this structure will be
// called on the browser process UI thread.
///
struct _cef_media_observer_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // The list of available media sinks has changed or
    // cef_media_router_t::NotifyCurrentSinks was called.
    ///
    void function (
        _cef_media_observer_t* self,
        size_t sinksCount,
        _cef_media_sink_t** sinks) nothrow on_sinks;

    ///
    // The list of available media routes has changed or
    // cef_media_router_t::NotifyCurrentRoutes was called.
    ///
    void function (
        _cef_media_observer_t* self,
        size_t routesCount,
        _cef_media_route_t** routes) nothrow on_routes;

    ///
    // The connection state of |route| has changed.
    ///
    void function (
        _cef_media_observer_t* self,
        _cef_media_route_t* route,
        cef_media_route_connection_state_t state) nothrow on_route_state_changed;

    ///
    // A message was recieved over |route|. |message| is only valid for the scope
    // of this callback and should be copied if necessary.
    ///
    void function (
        _cef_media_observer_t* self,
        _cef_media_route_t* route,
        const(void)* message,
        size_t message_size) nothrow on_route_message_received;
}

alias cef_media_observer_t = _cef_media_observer_t;

///
// Represents the route between a media source and sink. Instances of this
// object are created via cef_media_router_t::CreateRoute and retrieved via
// cef_media_observer_t::OnRoutes. Contains the status and metadata of a routing
// operation. The functions of this structure may be called on any browser
// process thread unless otherwise indicated.
///
struct _cef_media_route_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the ID for this route.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_media_route_t* self) nothrow get_id;

    ///
    // Returns the source associated with this route.
    ///
    _cef_media_source_t* function (_cef_media_route_t* self) nothrow get_source;

    ///
    // Returns the sink associated with this route.
    ///
    _cef_media_sink_t* function (_cef_media_route_t* self) nothrow get_sink;

    ///
    // Send a message over this route. |message| will be copied if necessary.
    ///
    void function (
        _cef_media_route_t* self,
        const(void)* message,
        size_t message_size) nothrow send_route_message;

    ///
    // Terminate this route. Will result in an asynchronous call to
    // cef_media_observer_t::OnRoutes on all registered observers.
    ///
    void function (_cef_media_route_t* self) nothrow terminate;
}

alias cef_media_route_t = _cef_media_route_t;

///
// Callback structure for cef_media_router_t::CreateRoute. The functions of this
// structure will be called on the browser process UI thread.
///
struct _cef_media_route_create_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be executed when the route creation has finished. |result|
    // will be CEF_MRCR_OK if the route creation succeeded. |error| will be a
    // description of the error if the route creation failed. |route| is the
    // resulting route, or NULL if the route creation failed.
    ///
    void function (
        _cef_media_route_create_callback_t* self,
        cef_media_route_create_result_t result,
        const(cef_string_t)* error,
        _cef_media_route_t* route) nothrow on_media_route_create_finished;
}

alias cef_media_route_create_callback_t = _cef_media_route_create_callback_t;

///
// Represents a sink to which media can be routed. Instances of this object are
// retrieved via cef_media_observer_t::OnSinks. The functions of this structure
// may be called on any browser process thread unless otherwise indicated.
///
struct _cef_media_sink_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the ID for this sink.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_media_sink_t* self) nothrow get_id;

    ///
    // Returns the name of this sink.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_media_sink_t* self) nothrow get_name;

    ///
    // Returns the description of this sink.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_media_sink_t* self) nothrow get_description;

    ///
    // Returns the icon type for this sink.
    ///
    cef_media_sink_icon_type_t function (
        _cef_media_sink_t* self) nothrow get_icon_type;

    ///
    // Asynchronously retrieves device info.
    ///
    void function (
        _cef_media_sink_t* self,
        _cef_media_sink_device_info_callback_t* callback) nothrow get_device_info;

    ///
    // Returns true (1) if this sink accepts content via Cast.
    ///
    int function (_cef_media_sink_t* self) nothrow is_cast_sink;

    ///
    // Returns true (1) if this sink accepts content via DIAL.
    ///
    int function (_cef_media_sink_t* self) nothrow is_dial_sink;

    ///
    // Returns true (1) if this sink is compatible with |source|.
    ///
    int function (
        _cef_media_sink_t* self,
        _cef_media_source_t* source) nothrow is_compatible_with;
}

alias cef_media_sink_t = _cef_media_sink_t;

///
// Callback structure for cef_media_sink_t::GetDeviceInfo. The functions of this
// structure will be called on the browser process UI thread.
///
struct _cef_media_sink_device_info_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be executed asyncronously once device information has been
    // retrieved.
    ///
    void function (
        _cef_media_sink_device_info_callback_t* self,
        const(_cef_media_sink_device_info_t)* device_info) nothrow on_media_sink_device_info;
}

alias cef_media_sink_device_info_callback_t = _cef_media_sink_device_info_callback_t;

///
// Represents a source from which media can be routed. Instances of this object
// are retrieved via cef_media_router_t::GetSource. The functions of this
// structure may be called on any browser process thread unless otherwise
// indicated.
///
struct _cef_media_source_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the ID (media source URN or URL) for this source.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_media_source_t* self) nothrow get_id;

    ///
    // Returns true (1) if this source outputs its content via Cast.
    ///
    int function (_cef_media_source_t* self) nothrow is_cast_source;

    ///
    // Returns true (1) if this source outputs its content via DIAL.
    ///
    int function (_cef_media_source_t* self) nothrow is_dial_source;
}

alias cef_media_source_t = _cef_media_source_t;

// CEF_INCLUDE_CAPI_CEF_MEDIA_ROUTER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=cce24dba079162b10f359769eea176c4009b5ce5$
//

extern (C):

///
// Supports creation and modification of menus. See cef_menu_id_t for the
// command ids that have default implementations. All user-defined command ids
// should be between MENU_ID_USER_FIRST and MENU_ID_USER_LAST. The functions of
// this structure can only be accessed on the browser process the UI thread.
///
struct _cef_menu_model_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this menu is a submenu.
    ///
    int function (_cef_menu_model_t* self) nothrow is_sub_menu;

    ///
    // Clears the menu. Returns true (1) on success.
    ///
    int function (_cef_menu_model_t* self) nothrow clear;

    ///
    // Returns the number of items in this menu.
    ///
    int function (_cef_menu_model_t* self) nothrow get_count;

    ///
    // Add a separator to the menu. Returns true (1) on success.
    ///
    int function (_cef_menu_model_t* self) nothrow add_separator;

    ///
    // Add an item to the menu. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        const(cef_string_t)* label) nothrow add_item;

    ///
    // Add a check item to the menu. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        const(cef_string_t)* label) nothrow add_check_item;

    ///
    // Add a radio item to the menu. Only a single item with the specified
    // |group_id| can be checked at a time. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        const(cef_string_t)* label,
        int group_id) nothrow add_radio_item;

    ///
    // Add a sub-menu to the menu. The new sub-menu is returned.
    ///
    _cef_menu_model_t* function (
        _cef_menu_model_t* self,
        int command_id,
        const(cef_string_t)* label) nothrow add_sub_menu;

    ///
    // Insert a separator in the menu at the specified |index|. Returns true (1)
    // on success.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow insert_separator_at;

    ///
    // Insert an item in the menu at the specified |index|. Returns true (1) on
    // success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int command_id,
        const(cef_string_t)* label) nothrow insert_item_at;

    ///
    // Insert a check item in the menu at the specified |index|. Returns true (1)
    // on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int command_id,
        const(cef_string_t)* label) nothrow insert_check_item_at;

    ///
    // Insert a radio item in the menu at the specified |index|. Only a single
    // item with the specified |group_id| can be checked at a time. Returns true
    // (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int command_id,
        const(cef_string_t)* label,
        int group_id) nothrow insert_radio_item_at;

    ///
    // Insert a sub-menu in the menu at the specified |index|. The new sub-menu is
    // returned.
    ///
    _cef_menu_model_t* function (
        _cef_menu_model_t* self,
        int index,
        int command_id,
        const(cef_string_t)* label) nothrow insert_sub_menu_at;

    ///
    // Removes the item with the specified |command_id|. Returns true (1) on
    // success.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow remove;

    ///
    // Removes the item at the specified |index|. Returns true (1) on success.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow remove_at;

    ///
    // Returns the index associated with the specified |command_id| or -1 if not
    // found due to the command id not existing in the menu.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow get_index_of;

    ///
    // Returns the command id at the specified |index| or -1 if not found due to
    // invalid range or the index being a separator.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow get_command_id_at;

    ///
    // Sets the command id at the specified |index|. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int command_id) nothrow set_command_id_at;

    ///
    // Returns the label for the specified |command_id| or NULL if not found.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_menu_model_t* self,
        int command_id) nothrow get_label;

    ///
    // Returns the label at the specified |index| or NULL if not found due to
    // invalid range or the index being a separator.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_menu_model_t* self,
        int index) nothrow get_label_at;

    ///
    // Sets the label for the specified |command_id|. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        const(cef_string_t)* label) nothrow set_label;

    ///
    // Set the label at the specified |index|. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        const(cef_string_t)* label) nothrow set_label_at;

    ///
    // Returns the item type for the specified |command_id|.
    ///
    cef_menu_item_type_t function (
        _cef_menu_model_t* self,
        int command_id) nothrow get_type;

    ///
    // Returns the item type at the specified |index|.
    ///
    cef_menu_item_type_t function (
        _cef_menu_model_t* self,
        int index) nothrow get_type_at;

    ///
    // Returns the group id for the specified |command_id| or -1 if invalid.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow get_group_id;

    ///
    // Returns the group id at the specified |index| or -1 if invalid.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow get_group_id_at;

    ///
    // Sets the group id for the specified |command_id|. Returns true (1) on
    // success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        int group_id) nothrow set_group_id;

    ///
    // Sets the group id at the specified |index|. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int group_id) nothrow set_group_id_at;

    ///
    // Returns the submenu for the specified |command_id| or NULL if invalid.
    ///
    _cef_menu_model_t* function (
        _cef_menu_model_t* self,
        int command_id) nothrow get_sub_menu;

    ///
    // Returns the submenu at the specified |index| or NULL if invalid.
    ///
    _cef_menu_model_t* function (
        _cef_menu_model_t* self,
        int index) nothrow get_sub_menu_at;

    ///
    // Returns true (1) if the specified |command_id| is visible.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow is_visible;

    ///
    // Returns true (1) if the specified |index| is visible.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow is_visible_at;

    ///
    // Change the visibility of the specified |command_id|. Returns true (1) on
    // success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        int visible) nothrow set_visible;

    ///
    // Change the visibility at the specified |index|. Returns true (1) on
    // success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int visible) nothrow set_visible_at;

    ///
    // Returns true (1) if the specified |command_id| is enabled.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow is_enabled;

    ///
    // Returns true (1) if the specified |index| is enabled.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow is_enabled_at;

    ///
    // Change the enabled status of the specified |command_id|. Returns true (1)
    // on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        int enabled) nothrow set_enabled;

    ///
    // Change the enabled status at the specified |index|. Returns true (1) on
    // success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int enabled) nothrow set_enabled_at;

    ///
    // Returns true (1) if the specified |command_id| is checked. Only applies to
    // check and radio items.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow is_checked;

    ///
    // Returns true (1) if the specified |index| is checked. Only applies to check
    // and radio items.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow is_checked_at;

    ///
    // Check the specified |command_id|. Only applies to check and radio items.
    // Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        int checked) nothrow set_checked;

    ///
    // Check the specified |index|. Only applies to check and radio items. Returns
    // true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int checked) nothrow set_checked_at;

    ///
    // Returns true (1) if the specified |command_id| has a keyboard accelerator
    // assigned.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow has_accelerator;

    ///
    // Returns true (1) if the specified |index| has a keyboard accelerator
    // assigned.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow has_accelerator_at;

    ///
    // Set the keyboard accelerator for the specified |command_id|. |key_code| can
    // be any virtual key or character value. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        int key_code,
        int shift_pressed,
        int ctrl_pressed,
        int alt_pressed) nothrow set_accelerator;

    ///
    // Set the keyboard accelerator at the specified |index|. |key_code| can be
    // any virtual key or character value. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int key_code,
        int shift_pressed,
        int ctrl_pressed,
        int alt_pressed) nothrow set_accelerator_at;

    ///
    // Remove the keyboard accelerator for the specified |command_id|. Returns
    // true (1) on success.
    ///
    int function (_cef_menu_model_t* self, int command_id) nothrow remove_accelerator;

    ///
    // Remove the keyboard accelerator at the specified |index|. Returns true (1)
    // on success.
    ///
    int function (_cef_menu_model_t* self, int index) nothrow remove_accelerator_at;

    ///
    // Retrieves the keyboard accelerator for the specified |command_id|. Returns
    // true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        int* key_code,
        int* shift_pressed,
        int* ctrl_pressed,
        int* alt_pressed) nothrow get_accelerator;

    ///
    // Retrieves the keyboard accelerator for the specified |index|. Returns true
    // (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        int* key_code,
        int* shift_pressed,
        int* ctrl_pressed,
        int* alt_pressed) nothrow get_accelerator_at;

    ///
    // Set the explicit color for |command_id| and |color_type| to |color|.
    // Specify a |color| value of 0 to remove the explicit color. If no explicit
    // color or default color is set for |color_type| then the system color will
    // be used. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        cef_menu_color_type_t color_type,
        cef_color_t color) nothrow set_color;

    ///
    // Set the explicit color for |command_id| and |index| to |color|. Specify a
    // |color| value of 0 to remove the explicit color. Specify an |index| value
    // of -1 to set the default color for items that do not have an explicit color
    // set. If no explicit color or default color is set for |color_type| then the
    // system color will be used. Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        cef_menu_color_type_t color_type,
        cef_color_t color) nothrow set_color_at;

    ///
    // Returns in |color| the color that was explicitly set for |command_id| and
    // |color_type|. If a color was not set then 0 will be returned in |color|.
    // Returns true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        cef_menu_color_type_t color_type,
        cef_color_t* color) nothrow get_color;

    ///
    // Returns in |color| the color that was explicitly set for |command_id| and
    // |color_type|. Specify an |index| value of -1 to return the default color in
    // |color|. If a color was not set then 0 will be returned in |color|. Returns
    // true (1) on success.
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        cef_menu_color_type_t color_type,
        cef_color_t* color) nothrow get_color_at;

    ///
    // Sets the font list for the specified |command_id|. If |font_list| is NULL
    // the system font will be used. Returns true (1) on success. The format is
    // "<FONT_FAMILY_LIST>,[STYLES] <SIZE>", where: - FONT_FAMILY_LIST is a comma-
    // separated list of font family names, - STYLES is an optional space-
    // separated list of style names (case-sensitive
    //   "Bold" and "Italic" are supported), and
    // - SIZE is an integer font size in pixels with the suffix "px".
    //
    // Here are examples of valid font description strings: - "Arial, Helvetica,
    // Bold Italic 14px" - "Arial, 14px"
    ///
    int function (
        _cef_menu_model_t* self,
        int command_id,
        const(cef_string_t)* font_list) nothrow set_font_list;

    ///
    // Sets the font list for the specified |index|. Specify an |index| value of
    // -1 to set the default font. If |font_list| is NULL the system font will be
    // used. Returns true (1) on success. The format is
    // "<FONT_FAMILY_LIST>,[STYLES] <SIZE>", where: - FONT_FAMILY_LIST is a comma-
    // separated list of font family names, - STYLES is an optional space-
    // separated list of style names (case-sensitive
    //   "Bold" and "Italic" are supported), and
    // - SIZE is an integer font size in pixels with the suffix "px".
    //
    // Here are examples of valid font description strings: - "Arial, Helvetica,
    // Bold Italic 14px" - "Arial, 14px"
    ///
    int function (
        _cef_menu_model_t* self,
        int index,
        const(cef_string_t)* font_list) nothrow set_font_list_at;
}

alias cef_menu_model_t = _cef_menu_model_t;

///
// Create a new MenuModel with the specified |delegate|.
///
cef_menu_model_t* cef_menu_model_create (_cef_menu_model_delegate_t* delegate_);

// CEF_INCLUDE_CAPI_CEF_MENU_MODEL_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=071ec8a0e17d3b33acbf36c7ccc26d0995657cf3$
//

extern (C):

///
// Implement this structure to handle menu model events. The functions of this
// structure will be called on the browser process UI thread unless otherwise
// indicated.
///
struct _cef_menu_model_delegate_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Perform the action associated with the specified |command_id| and optional
    // |event_flags|.
    ///
    void function (
        _cef_menu_model_delegate_t* self,
        _cef_menu_model_t* menu_model,
        int command_id,
        cef_event_flags_t event_flags) nothrow execute_command;

    ///
    // Called when the user moves the mouse outside the menu and over the owning
    // window.
    ///
    void function (
        _cef_menu_model_delegate_t* self,
        _cef_menu_model_t* menu_model,
        const(cef_point_t)* screen_point) nothrow mouse_outside_menu;

    ///
    // Called on unhandled open submenu keyboard commands. |is_rtl| will be true
    // (1) if the menu is displaying a right-to-left language.
    ///
    void function (
        _cef_menu_model_delegate_t* self,
        _cef_menu_model_t* menu_model,
        int is_rtl) nothrow unhandled_open_submenu;

    ///
    // Called on unhandled close submenu keyboard commands. |is_rtl| will be true
    // (1) if the menu is displaying a right-to-left language.
    ///
    void function (
        _cef_menu_model_delegate_t* self,
        _cef_menu_model_t* menu_model,
        int is_rtl) nothrow unhandled_close_submenu;

    ///
    // The menu is about to show.
    ///
    void function (
        _cef_menu_model_delegate_t* self,
        _cef_menu_model_t* menu_model) nothrow menu_will_show;

    ///
    // The menu has closed.
    ///
    void function (
        _cef_menu_model_delegate_t* self,
        _cef_menu_model_t* menu_model) nothrow menu_closed;

    ///
    // Optionally modify a menu item label. Return true (1) if |label| was
    // modified.
    ///
    int function (
        _cef_menu_model_delegate_t* self,
        _cef_menu_model_t* menu_model,
        cef_string_t* label) nothrow format_label;
}

alias cef_menu_model_delegate_t = _cef_menu_model_delegate_t;

// CEF_INCLUDE_CAPI_CEF_MENU_MODEL_DELEGATE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=c6252024911652a4881d753aeeeb2615e6be3904$
//

extern (C):

///
// Structure used to represent an entry in navigation history.
///
struct _cef_navigation_entry_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. Do not call any other functions
    // if this function returns false (0).
    ///
    int function (_cef_navigation_entry_t* self) nothrow is_valid;

    ///
    // Returns the actual URL of the page. For some pages this may be data: URL or
    // similar. Use get_display_url() to return a display-friendly version.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_navigation_entry_t* self) nothrow get_url;

    ///
    // Returns a display-friendly version of the URL.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_navigation_entry_t* self) nothrow get_display_url;

    ///
    // Returns the original URL that was entered by the user before any redirects.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_navigation_entry_t* self) nothrow get_original_url;

    ///
    // Returns the title set by the page. This value may be NULL.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_navigation_entry_t* self) nothrow get_title;

    ///
    // Returns the transition type which indicates what the user did to move to
    // this page from the previous page.
    ///
    cef_transition_type_t function (
        _cef_navigation_entry_t* self) nothrow get_transition_type;

    ///
    // Returns true (1) if this navigation includes post data.
    ///
    int function (_cef_navigation_entry_t* self) nothrow has_post_data;

    ///
    // Returns the time for the last known successful navigation completion. A
    // navigation may be completed more than once if the page is reloaded. May be
    // 0 if the navigation has not yet completed.
    ///
    cef_time_t function (_cef_navigation_entry_t* self) nothrow get_completion_time;

    ///
    // Returns the HTTP status code for the last known successful navigation
    // response. May be 0 if the response has not yet been received or if the
    // navigation has not yet completed.
    ///
    int function (_cef_navigation_entry_t* self) nothrow get_http_status_code;

    ///
    // Returns the SSL information for this navigation entry.
    ///
    _cef_sslstatus_t* function (_cef_navigation_entry_t* self) nothrow get_sslstatus;
}

alias cef_navigation_entry_t = _cef_navigation_entry_t;

// CEF_INCLUDE_CAPI_CEF_NAVIGATION_ENTRY_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=8a26e2f8273298dcf44d6fbf32fd565f6aaa912c$
//

extern (C):

///
// Add an entry to the cross-origin access whitelist.
//
// The same-origin policy restricts how scripts hosted from different origins
// (scheme + domain + port) can communicate. By default, scripts can only access
// resources with the same origin. Scripts hosted on the HTTP and HTTPS schemes
// (but no other schemes) can use the "Access-Control-Allow-Origin" header to
// allow cross-origin requests. For example, https://source.example.com can make
// XMLHttpRequest requests on http://target.example.com if the
// http://target.example.com request returns an "Access-Control-Allow-Origin:
// https://source.example.com" response header.
//
// Scripts in separate frames or iframes and hosted from the same protocol and
// domain suffix can execute cross-origin JavaScript if both pages set the
// document.domain value to the same domain suffix. For example,
// scheme://foo.example.com and scheme://bar.example.com can communicate using
// JavaScript if both domains set document.domain="example.com".
//
// This function is used to allow access to origins that would otherwise violate
// the same-origin policy. Scripts hosted underneath the fully qualified
// |source_origin| URL (like http://www.example.com) will be allowed access to
// all resources hosted on the specified |target_protocol| and |target_domain|.
// If |target_domain| is non-NULL and |allow_target_subdomains| if false (0)
// only exact domain matches will be allowed. If |target_domain| contains a top-
// level domain component (like "example.com") and |allow_target_subdomains| is
// true (1) sub-domain matches will be allowed. If |target_domain| is NULL and
// |allow_target_subdomains| if true (1) all domains and IP addresses will be
// allowed.
//
// This function cannot be used to bypass the restrictions on local or display
// isolated schemes. See the comments on CefRegisterCustomScheme for more
// information.
//
// This function may be called on any thread. Returns false (0) if
// |source_origin| is invalid or the whitelist cannot be accessed.
///
int cef_add_cross_origin_whitelist_entry (
    const(cef_string_t)* source_origin,
    const(cef_string_t)* target_protocol,
    const(cef_string_t)* target_domain,
    int allow_target_subdomains);

///
// Remove an entry from the cross-origin access whitelist. Returns false (0) if
// |source_origin| is invalid or the whitelist cannot be accessed.
///
int cef_remove_cross_origin_whitelist_entry (
    const(cef_string_t)* source_origin,
    const(cef_string_t)* target_protocol,
    const(cef_string_t)* target_domain,
    int allow_target_subdomains);

///
// Remove all entries from the cross-origin access whitelist. Returns false (0)
// if the whitelist cannot be accessed.
///
int cef_clear_cross_origin_whitelist ();

// CEF_INCLUDE_CAPI_CEF_ORIGIN_WHITELIST_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=19337a70a13352e70452be7fcc25ef2de4b1ae4c$
//

extern (C):

///
// Parse the specified |url| into its component parts. Returns false (0) if the
// URL is NULL or invalid.
///
int cef_parse_url (const(cef_string_t)* url, _cef_urlparts_t* parts);

///
// Creates a URL from the specified |parts|, which must contain a non-NULL spec
// or a non-NULL host and path (at a minimum), but not both. Returns false (0)
// if |parts| isn't initialized as described.
///
int cef_create_url (const(_cef_urlparts_t)* parts, cef_string_t* url);

///
// This is a convenience function for formatting a URL in a concise and human-
// friendly way to help users make security-related decisions (or in other
// circumstances when people need to distinguish sites, origins, or otherwise-
// simplified URLs from each other). Internationalized domain names (IDN) may be
// presented in Unicode if the conversion is considered safe. The returned value
// will (a) omit the path for standard schemes, excepting file and filesystem,
// and (b) omit the port if it is the default for the scheme. Do not use this
// for URLs which will be parsed or sent to other applications.
///
// The resulting string must be freed by calling cef_string_userfree_free().
cef_string_userfree_t cef_format_url_for_security_display (
    const(cef_string_t)* origin_url);

///
// Returns the mime type for the specified file extension or an NULL string if
// unknown.
///
// The resulting string must be freed by calling cef_string_userfree_free().
cef_string_userfree_t cef_get_mime_type (const(cef_string_t)* extension);

///
// Get the extensions associated with the given mime type. This should be passed
// in lower case. There could be multiple extensions for a given mime type, like
// "html,htm" for "text/html", or "txt,text,html,..." for "text/*". Any existing
// elements in the provided vector will not be erased.
///
void cef_get_extensions_for_mime_type (
    const(cef_string_t)* mime_type,
    cef_string_list_t extensions);

///
// Encodes |data| as a base64 string.
///
// The resulting string must be freed by calling cef_string_userfree_free().
cef_string_userfree_t cef_base64encode (const(void)* data, size_t data_size);

///
// Decodes the base64 encoded string |data|. The returned value will be NULL if
// the decoding fails.
///
_cef_binary_value_t* cef_base64decode (const(cef_string_t)* data);

///
// Escapes characters in |text| which are unsuitable for use as a query
// parameter value. Everything except alphanumerics and -_.!~*'() will be
// converted to "%XX". If |use_plus| is true (1) spaces will change to "+". The
// result is basically the same as encodeURIComponent in Javacript.
///
// The resulting string must be freed by calling cef_string_userfree_free().
cef_string_userfree_t cef_uriencode (const(cef_string_t)* text, int use_plus);

///
// Unescapes |text| and returns the result. Unescaping consists of looking for
// the exact pattern "%XX" where each X is a hex digit and converting to the
// character with the numerical value of those digits (e.g. "i%20=%203%3b"
// unescapes to "i = 3;"). If |convert_to_utf8| is true (1) this function will
// attempt to interpret the initial decoded result as UTF-8. If the result is
// convertable into UTF-8 it will be returned as converted. Otherwise the
// initial decoded result will be returned.  The |unescape_rule| parameter
// supports further customization the decoding process.
///
// The resulting string must be freed by calling cef_string_userfree_free().
cef_string_userfree_t cef_uridecode (
    const(cef_string_t)* text,
    int convert_to_utf8,
    cef_uri_unescape_rule_t unescape_rule);

///
// Parses the specified |json_string| and returns a dictionary or list
// representation. If JSON parsing fails this function returns NULL.
///
_cef_value_t* cef_parse_json (
    const(cef_string_t)* json_string,
    cef_json_parser_options_t options);

///
// Parses the specified UTF8-encoded |json| buffer of size |json_size| and
// returns a dictionary or list representation. If JSON parsing fails this
// function returns NULL.
///
_cef_value_t* cef_parse_json_buffer (
    const(void)* json,
    size_t json_size,
    cef_json_parser_options_t options);

///
// Parses the specified |json_string| and returns a dictionary or list
// representation. If JSON parsing fails this function returns NULL and
// populates |error_msg_out| with a formatted error message.
///
_cef_value_t* cef_parse_jsonand_return_error (
    const(cef_string_t)* json_string,
    cef_json_parser_options_t options,
    cef_string_t* error_msg_out);

///
// Generates a JSON string from the specified root |node| which should be a
// dictionary or list value. Returns an NULL string on failure. This function
// requires exclusive access to |node| including any underlying data.
///
// The resulting string must be freed by calling cef_string_userfree_free().
cef_string_userfree_t cef_write_json (
    _cef_value_t* node,
    cef_json_writer_options_t options);

// CEF_INCLUDE_CAPI_CEF_PARSER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=1b218a91d7f3ba0e68f0c3be21a0df91e515d28a$
//

extern (C):

///
// Retrieve the path associated with the specified |key|. Returns true (1) on
// success. Can be called on any thread in the browser process.
///
int cef_get_path (cef_path_key_t key, cef_string_t* path);

// CEF_INCLUDE_CAPI_CEF_PATH_UTIL_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=b8d7be1399d3426a3f872b12bc1438e041a16308$
//

extern (C):

///
// Callback structure for asynchronous continuation of print dialog requests.
///
struct _cef_print_dialog_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Continue printing with the specified |settings|.
    ///
    void function (
        _cef_print_dialog_callback_t* self,
        _cef_print_settings_t* settings) nothrow cont;

    ///
    // Cancel the printing.
    ///
    void function (_cef_print_dialog_callback_t* self) nothrow cancel;
}

alias cef_print_dialog_callback_t = _cef_print_dialog_callback_t;

///
// Callback structure for asynchronous continuation of print job requests.
///
struct _cef_print_job_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Indicate completion of the print job.
    ///
    void function (_cef_print_job_callback_t* self) nothrow cont;
}

alias cef_print_job_callback_t = _cef_print_job_callback_t;

///
// Implement this structure to handle printing on Linux. Each browser will have
// only one print job in progress at a time. The functions of this structure
// will be called on the browser process UI thread.
///
struct _cef_print_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called when printing has started for the specified |browser|. This function
    // will be called before the other OnPrint*() functions and irrespective of
    // how printing was initiated (e.g. cef_browser_host_t::print(), JavaScript
    // window.print() or PDF extension print button).
    ///
    void function (
        _cef_print_handler_t* self,
        _cef_browser_t* browser) nothrow on_print_start;

    ///
    // Synchronize |settings| with client state. If |get_defaults| is true (1)
    // then populate |settings| with the default print settings. Do not keep a
    // reference to |settings| outside of this callback.
    ///
    void function (
        _cef_print_handler_t* self,
        _cef_browser_t* browser,
        _cef_print_settings_t* settings,
        int get_defaults) nothrow on_print_settings;

    ///
    // Show the print dialog. Execute |callback| once the dialog is dismissed.
    // Return true (1) if the dialog will be displayed or false (0) to cancel the
    // printing immediately.
    ///
    int function (
        _cef_print_handler_t* self,
        _cef_browser_t* browser,
        int has_selection,
        _cef_print_dialog_callback_t* callback) nothrow on_print_dialog;

    ///
    // Send the print job to the printer. Execute |callback| once the job is
    // completed. Return true (1) if the job will proceed or false (0) to cancel
    // the job immediately.
    ///
    int function (
        _cef_print_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* document_name,
        const(cef_string_t)* pdf_file_path,
        _cef_print_job_callback_t* callback) nothrow on_print_job;

    ///
    // Reset client state related to printing.
    ///
    void function (
        _cef_print_handler_t* self,
        _cef_browser_t* browser) nothrow on_print_reset;

    ///
    // Return the PDF paper size in device units. Used in combination with
    // cef_browser_host_t::print_to_pdf().
    ///
    cef_size_t function (
        _cef_print_handler_t* self,
        int device_units_per_inch) nothrow get_pdf_paper_size;
}

alias cef_print_handler_t = _cef_print_handler_t;

// CEF_INCLUDE_CAPI_CEF_PRINT_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=8f7d7993691e07f4a8a42d63522c751cfba3c168$
//

extern (C):

///
// Structure representing print settings.
///
struct _cef_print_settings_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. Do not call any other functions
    // if this function returns false (0).
    ///
    int function (_cef_print_settings_t* self) nothrow is_valid;

    ///
    // Returns true (1) if the values of this object are read-only. Some APIs may
    // expose read-only objects.
    ///
    int function (_cef_print_settings_t* self) nothrow is_read_only;

    ///
    // Set the page orientation.
    ///
    void function (_cef_print_settings_t* self, int landscape) nothrow set_orientation;

    ///
    // Returns true (1) if the orientation is landscape.
    ///
    int function (_cef_print_settings_t* self) nothrow is_landscape;

    ///
    // Set the printer printable area in device units. Some platforms already
    // provide flipped area. Set |landscape_needs_flip| to false (0) on those
    // platforms to avoid double flipping.
    ///
    void function (
        _cef_print_settings_t* self,
        const(cef_size_t)* physical_size_device_units,
        const(cef_rect_t)* printable_area_device_units,
        int landscape_needs_flip) nothrow set_printer_printable_area;

    ///
    // Set the device name.
    ///
    void function (
        _cef_print_settings_t* self,
        const(cef_string_t)* name) nothrow set_device_name;

    ///
    // Get the device name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_print_settings_t* self) nothrow get_device_name;

    ///
    // Set the DPI (dots per inch).
    ///
    void function (_cef_print_settings_t* self, int dpi) nothrow set_dpi;

    ///
    // Get the DPI (dots per inch).
    ///
    int function (_cef_print_settings_t* self) nothrow get_dpi;

    ///
    // Set the page ranges.
    ///
    void function (
        _cef_print_settings_t* self,
        size_t rangesCount,
        const(cef_range_t)* ranges) nothrow set_page_ranges;

    ///
    // Returns the number of page ranges that currently exist.
    ///
    size_t function (_cef_print_settings_t* self) nothrow get_page_ranges_count;

    ///
    // Retrieve the page ranges.
    ///
    void function (
        _cef_print_settings_t* self,
        size_t* rangesCount,
        cef_range_t* ranges) nothrow get_page_ranges;

    ///
    // Set whether only the selection will be printed.
    ///
    void function (
        _cef_print_settings_t* self,
        int selection_only) nothrow set_selection_only;

    ///
    // Returns true (1) if only the selection will be printed.
    ///
    int function (_cef_print_settings_t* self) nothrow is_selection_only;

    ///
    // Set whether pages will be collated.
    ///
    void function (_cef_print_settings_t* self, int collate) nothrow set_collate;

    ///
    // Returns true (1) if pages will be collated.
    ///
    int function (_cef_print_settings_t* self) nothrow will_collate;

    ///
    // Set the color model.
    ///
    void function (
        _cef_print_settings_t* self,
        cef_color_model_t model) nothrow set_color_model;

    ///
    // Get the color model.
    ///
    cef_color_model_t function (_cef_print_settings_t* self) nothrow get_color_model;

    ///
    // Set the number of copies.
    ///
    void function (_cef_print_settings_t* self, int copies) nothrow set_copies;

    ///
    // Get the number of copies.
    ///
    int function (_cef_print_settings_t* self) nothrow get_copies;

    ///
    // Set the duplex mode.
    ///
    void function (
        _cef_print_settings_t* self,
        cef_duplex_mode_t mode) nothrow set_duplex_mode;

    ///
    // Get the duplex mode.
    ///
    cef_duplex_mode_t function (_cef_print_settings_t* self) nothrow get_duplex_mode;
}

alias cef_print_settings_t = _cef_print_settings_t;

///
// Create a new cef_print_settings_t object.
///
cef_print_settings_t* cef_print_settings_create ();

// CEF_INCLUDE_CAPI_CEF_PRINT_SETTINGS_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=79ec6d99ea47e1cf9b2cca0433704f205e14d3bd$
//

extern (C):

///
// Structure representing a message. Can be used on any process and thread.
///
struct _cef_process_message_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. Do not call any other functions
    // if this function returns false (0).
    ///
    int function (_cef_process_message_t* self) nothrow is_valid;

    ///
    // Returns true (1) if the values of this object are read-only. Some APIs may
    // expose read-only objects.
    ///
    int function (_cef_process_message_t* self) nothrow is_read_only;

    ///
    // Returns a writable copy of this object.
    ///
    _cef_process_message_t* function (_cef_process_message_t* self) nothrow copy;

    ///
    // Returns the message name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_process_message_t* self) nothrow get_name;

    ///
    // Returns the list of arguments.
    ///
    _cef_list_value_t* function (
        _cef_process_message_t* self) nothrow get_argument_list;
}

alias cef_process_message_t = _cef_process_message_t;

///
// Create a new cef_process_message_t object with the specified name.
///
cef_process_message_t* cef_process_message_create (const(cef_string_t)* name);

// CEF_INCLUDE_CAPI_CEF_PROCESS_MESSAGE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=75b16fd9d592c1d22b94d740e1deb61efe3afb97$
//

extern (C):

///
// Launches the process specified via |command_line|. Returns true (1) upon
// success. Must be called on the browser process TID_PROCESS_LAUNCHER thread.
//
// Unix-specific notes: - All file descriptors open in the parent process will
// be closed in the
//   child process except for stdin, stdout, and stderr.
// - If the first argument on the command line does not contain a slash,
//   PATH will be searched. (See man execvp.)
///
int cef_launch_process (_cef_command_line_t* command_line);

// CEF_INCLUDE_CAPI_CEF_PROCESS_UTIL_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=029e237cf80f94a25453bac5a9b1e0765bb56f37$
//

extern (C):

///
// Generic callback structure used for managing the lifespan of a registration.
///
struct _cef_registration_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;
}

alias cef_registration_t = _cef_registration_t;

// CEF_INCLUDE_CAPI_CEF_REGISTRATION_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=f9806cd79f33b6a762fff25edd4189ae42bc8fd2$
//

extern (C):

///
// Implement this structure to handle events when window rendering is disabled.
// The functions of this structure will be called on the UI thread.
///
struct _cef_render_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Return the handler for accessibility notifications. If no handler is
    // provided the default implementation will be used.
    ///
    _cef_accessibility_handler_t* function (
        _cef_render_handler_t* self) nothrow get_accessibility_handler;

    ///
    // Called to retrieve the root window rectangle in screen coordinates. Return
    // true (1) if the rectangle was provided. If this function returns false (0)
    // the rectangle from GetViewRect will be used.
    ///
    int function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        cef_rect_t* rect) nothrow get_root_screen_rect;

    ///
    // Called to retrieve the view rectangle which is relative to screen
    // coordinates. This function must always provide a non-NULL rectangle.
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        cef_rect_t* rect) nothrow get_view_rect;

    ///
    // Called to retrieve the translation from view coordinates to actual screen
    // coordinates. Return true (1) if the screen coordinates were provided.
    ///
    int function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        int viewX,
        int viewY,
        int* screenX,
        int* screenY) nothrow get_screen_point;

    ///
    // Called to allow the client to fill in the CefScreenInfo object with
    // appropriate values. Return true (1) if the |screen_info| structure has been
    // modified.
    //
    // If the screen info rectangle is left NULL the rectangle from GetViewRect
    // will be used. If the rectangle is still NULL or invalid popups may not be
    // drawn correctly.
    ///
    int function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        _cef_screen_info_t* screen_info) nothrow get_screen_info;

    ///
    // Called when the browser wants to show or hide the popup widget. The popup
    // should be shown if |show| is true (1) and hidden if |show| is false (0).
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        int show) nothrow on_popup_show;

    ///
    // Called when the browser wants to move or resize the popup widget. |rect|
    // contains the new location and size in view coordinates.
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        const(cef_rect_t)* rect) nothrow on_popup_size;

    ///
    // Called when an element should be painted. Pixel values passed to this
    // function are scaled relative to view coordinates based on the value of
    // CefScreenInfo.device_scale_factor returned from GetScreenInfo. |type|
    // indicates whether the element is the view or the popup widget. |buffer|
    // contains the pixel data for the whole image. |dirtyRects| contains the set
    // of rectangles in pixel coordinates that need to be repainted. |buffer| will
    // be |width|*|height|*4 bytes in size and represents a BGRA image with an
    // upper-left origin. This function is only called when
    // cef_window_tInfo::shared_texture_enabled is set to false (0).
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        cef_paint_element_type_t type,
        size_t dirtyRectsCount,
        const(cef_rect_t)* dirtyRects,
        const(void)* buffer,
        int width,
        int height) nothrow on_paint;

    ///
    // Called when an element has been rendered to the shared texture handle.
    // |type| indicates whether the element is the view or the popup widget.
    // |dirtyRects| contains the set of rectangles in pixel coordinates that need
    // to be repainted. |shared_handle| is the handle for a D3D11 Texture2D that
    // can be accessed via ID3D11Device using the OpenSharedResource function.
    // This function is only called when cef_window_tInfo::shared_texture_enabled
    // is set to true (1), and is currently only supported on Windows.
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        cef_paint_element_type_t type,
        size_t dirtyRectsCount,
        const(cef_rect_t)* dirtyRects,
        void* shared_handle) nothrow on_accelerated_paint;

    ///
    // Called when the user starts dragging content in the web view. Contextual
    // information about the dragged content is supplied by |drag_data|. (|x|,
    // |y|) is the drag start location in screen coordinates. OS APIs that run a
    // system message loop may be used within the StartDragging call.
    //
    // Return false (0) to abort the drag operation. Don't call any of
    // cef_browser_host_t::DragSource*Ended* functions after returning false (0).
    //
    // Return true (1) to handle the drag operation. Call
    // cef_browser_host_t::DragSourceEndedAt and DragSourceSystemDragEnded either
    // synchronously or asynchronously to inform the web view that the drag
    // operation has ended.
    ///
    int function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        _cef_drag_data_t* drag_data,
        cef_drag_operations_mask_t allowed_ops,
        int x,
        int y) nothrow start_dragging;

    ///
    // Called when the web view wants to update the mouse cursor during a drag &
    // drop operation. |operation| describes the allowed operation (none, move,
    // copy, link).
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        cef_drag_operations_mask_t operation) nothrow update_drag_cursor;

    ///
    // Called when the scroll offset has changed.
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        double x,
        double y) nothrow on_scroll_offset_changed;

    ///
    // Called when the IME composition range has changed. |selected_range| is the
    // range of characters that have been selected. |character_bounds| is the
    // bounds of each character in view coordinates.
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        const(cef_range_t)* selected_range,
        size_t character_boundsCount,
        const(cef_rect_t)* character_bounds) nothrow on_ime_composition_range_changed;

    ///
    // Called when text selection has changed for the specified |browser|.
    // |selected_text| is the currently selected text and |selected_range| is the
    // character range.
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* selected_text,
        const(cef_range_t)* selected_range) nothrow on_text_selection_changed;

    ///
    // Called when an on-screen keyboard should be shown or hidden for the
    // specified |browser|. |input_mode| specifies what kind of keyboard should be
    // opened. If |input_mode| is CEF_TEXT_INPUT_MODE_NONE, any existing keyboard
    // for this browser should be hidden.
    ///
    void function (
        _cef_render_handler_t* self,
        _cef_browser_t* browser,
        cef_text_input_mode_t input_mode) nothrow on_virtual_keyboard_requested;
}

alias cef_render_handler_t = _cef_render_handler_t;

// CEF_INCLUDE_CAPI_CEF_RENDER_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=8419eb3eba9dd372b019bd367d4f195433b21c9b$
//

extern (C):

///
// Structure used to implement render process callbacks. The functions of this
// structure will be called on the render process main thread (TID_RENDERER)
// unless otherwise indicated.
///
struct _cef_render_process_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called after WebKit has been initialized.
    ///
    void function (_cef_render_process_handler_t* self) nothrow on_web_kit_initialized;

    ///
    // Called after a browser has been created. When browsing cross-origin a new
    // browser will be created before the old browser with the same identifier is
    // destroyed. |extra_info| is a read-only value originating from
    // cef_browser_host_t::cef_browser_host_create_browser(),
    // cef_browser_host_t::cef_browser_host_create_browser_sync(),
    // cef_life_span_handler_t::on_before_popup() or
    // cef_browser_view_t::cef_browser_view_create().
    ///
    void function (
        _cef_render_process_handler_t* self,
        _cef_browser_t* browser,
        _cef_dictionary_value_t* extra_info) nothrow on_browser_created;

    ///
    // Called before a browser is destroyed.
    ///
    void function (
        _cef_render_process_handler_t* self,
        _cef_browser_t* browser) nothrow on_browser_destroyed;

    ///
    // Return the handler for browser load status events.
    ///
    _cef_load_handler_t* function (
        _cef_render_process_handler_t* self) nothrow get_load_handler;

    ///
    // Called immediately after the V8 context for a frame has been created. To
    // retrieve the JavaScript 'window' object use the
    // cef_v8context_t::get_global() function. V8 handles can only be accessed
    // from the thread on which they are created. A task runner for posting tasks
    // on the associated thread can be retrieved via the
    // cef_v8context_t::get_task_runner() function.
    ///
    void function (
        _cef_render_process_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_v8context_t* context) nothrow on_context_created;

    ///
    // Called immediately before the V8 context for a frame is released. No
    // references to the context should be kept after this function is called.
    ///
    void function (
        _cef_render_process_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_v8context_t* context) nothrow on_context_released;

    ///
    // Called for global uncaught exceptions in a frame. Execution of this
    // callback is disabled by default. To enable set
    // CefSettings.uncaught_exception_stack_size > 0.
    ///
    void function (
        _cef_render_process_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_v8context_t* context,
        _cef_v8exception_t* exception,
        _cef_v8stack_trace_t* stackTrace) nothrow on_uncaught_exception;

    ///
    // Called when a new node in the the browser gets focus. The |node| value may
    // be NULL if no specific node has gained focus. The node object passed to
    // this function represents a snapshot of the DOM at the time this function is
    // executed. DOM objects are only valid for the scope of this function. Do not
    // keep references to or attempt to access any DOM objects outside the scope
    // of this function.
    ///
    void function (
        _cef_render_process_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_domnode_t* node) nothrow on_focused_node_changed;

    ///
    // Called when a new message is received from a different process. Return true
    // (1) if the message was handled or false (0) otherwise. Do not keep a
    // reference to or attempt to access the message outside of this callback.
    ///
    int function (
        _cef_render_process_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        cef_process_id_t source_process,
        _cef_process_message_t* message) nothrow on_process_message_received;
}

alias cef_render_process_handler_t = _cef_render_process_handler_t;

// CEF_INCLUDE_CAPI_CEF_RENDER_PROCESS_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=3efd81a4bfdfca579a77f14bd37b8192122ebda4$
//

extern (C):

///
// Callback structure used for asynchronous continuation of url requests.
///
struct _cef_request_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Continue the url request. If |allow| is true (1) the request will be
    // continued. Otherwise, the request will be canceled.
    ///
    void function (_cef_request_callback_t* self, int allow) nothrow cont;

    ///
    // Cancel the url request.
    ///
    void function (_cef_request_callback_t* self) nothrow cancel;
}

alias cef_request_callback_t = _cef_request_callback_t;

// CEF_INCLUDE_CAPI_CEF_REQUEST_CALLBACK_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=b3725b8fa4118936caacda69504dc597f3620d82$
//

extern (C):

///
// Structure used to represent a web request. The functions of this structure
// may be called on any thread.
///
struct _cef_request_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is read-only.
    ///
    int function (_cef_request_t* self) nothrow is_read_only;

    ///
    // Get the fully qualified URL.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_request_t* self) nothrow get_url;

    ///
    // Set the fully qualified URL.
    ///
    void function (_cef_request_t* self, const(cef_string_t)* url) nothrow set_url;

    ///
    // Get the request function type. The value will default to POST if post data
    // is provided and GET otherwise.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_request_t* self) nothrow get_method;

    ///
    // Set the request function type.
    ///
    void function (
        _cef_request_t* self,
        const(cef_string_t)* method) nothrow set_method;

    ///
    // Set the referrer URL and policy. If non-NULL the referrer URL must be fully
    // qualified with an HTTP or HTTPS scheme component. Any username, password or
    // ref component will be removed.
    ///
    void function (
        _cef_request_t* self,
        const(cef_string_t)* referrer_url,
        cef_referrer_policy_t policy) nothrow set_referrer;

    ///
    // Get the referrer URL.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_request_t* self) nothrow get_referrer_url;

    ///
    // Get the referrer policy.
    ///
    cef_referrer_policy_t function (_cef_request_t* self) nothrow get_referrer_policy;

    ///
    // Get the post data.
    ///
    _cef_post_data_t* function (_cef_request_t* self) nothrow get_post_data;

    ///
    // Set the post data.
    ///
    void function (
        _cef_request_t* self,
        _cef_post_data_t* postData) nothrow set_post_data;

    ///
    // Get the header values. Will not include the Referer value if any.
    ///
    void function (
        _cef_request_t* self,
        cef_string_multimap_t headerMap) nothrow get_header_map;

    ///
    // Set the header values. If a Referer value exists in the header map it will
    // be removed and ignored.
    ///
    void function (
        _cef_request_t* self,
        cef_string_multimap_t headerMap) nothrow set_header_map;

    ///
    // Returns the first header value for |name| or an NULL string if not found.
    // Will not return the Referer value if any. Use GetHeaderMap instead if
    // |name| might have multiple values.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_request_t* self,
        const(cef_string_t)* name) nothrow get_header_by_name;

    ///
    // Set the header |name| to |value|. If |overwrite| is true (1) any existing
    // values will be replaced with the new value. If |overwrite| is false (0) any
    // existing values will not be overwritten. The Referer value cannot be set
    // using this function.
    ///
    void function (
        _cef_request_t* self,
        const(cef_string_t)* name,
        const(cef_string_t)* value,
        int overwrite) nothrow set_header_by_name;

    ///
    // Set all values at one time.
    ///
    void function (
        _cef_request_t* self,
        const(cef_string_t)* url,
        const(cef_string_t)* method,
        _cef_post_data_t* postData,
        cef_string_multimap_t headerMap) nothrow set;

    ///
    // Get the flags used in combination with cef_urlrequest_t. See
    // cef_urlrequest_flags_t for supported values.
    ///
    int function (_cef_request_t* self) nothrow get_flags;

    ///
    // Set the flags used in combination with cef_urlrequest_t.  See
    // cef_urlrequest_flags_t for supported values.
    ///
    void function (_cef_request_t* self, int flags) nothrow set_flags;

    ///
    // Get the URL to the first party for cookies used in combination with
    // cef_urlrequest_t.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_request_t* self) nothrow get_first_party_for_cookies;

    ///
    // Set the URL to the first party for cookies used in combination with
    // cef_urlrequest_t.
    ///
    void function (
        _cef_request_t* self,
        const(cef_string_t)* url) nothrow set_first_party_for_cookies;

    ///
    // Get the resource type for this request. Only available in the browser
    // process.
    ///
    cef_resource_type_t function (_cef_request_t* self) nothrow get_resource_type;

    ///
    // Get the transition type for this request. Only available in the browser
    // process and only applies to requests that represent a main frame or sub-
    // frame navigation.
    ///
    cef_transition_type_t function (_cef_request_t* self) nothrow get_transition_type;

    ///
    // Returns the globally unique identifier for this request or 0 if not
    // specified. Can be used by cef_resource_request_handler_t implementations in
    // the browser process to track a single request across multiple callbacks.
    ///
    uint64 function (_cef_request_t* self) nothrow get_identifier;
}

alias cef_request_t = _cef_request_t;

///
// Create a new cef_request_t object.
///
cef_request_t* cef_request_create ();

///
// Structure used to represent post data for a web request. The functions of
// this structure may be called on any thread.
///
struct _cef_post_data_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is read-only.
    ///
    int function (_cef_post_data_t* self) nothrow is_read_only;

    ///
    // Returns true (1) if the underlying POST data includes elements that are not
    // represented by this cef_post_data_t object (for example, multi-part file
    // upload data). Modifying cef_post_data_t objects with excluded elements may
    // result in the request failing.
    ///
    int function (_cef_post_data_t* self) nothrow has_excluded_elements;

    ///
    // Returns the number of existing post data elements.
    ///
    size_t function (_cef_post_data_t* self) nothrow get_element_count;

    ///
    // Retrieve the post data elements.
    ///
    void function (
        _cef_post_data_t* self,
        size_t* elementsCount,
        _cef_post_data_element_t** elements) nothrow get_elements;

    ///
    // Remove the specified post data element.  Returns true (1) if the removal
    // succeeds.
    ///
    int function (
        _cef_post_data_t* self,
        _cef_post_data_element_t* element) nothrow remove_element;

    ///
    // Add the specified post data element.  Returns true (1) if the add succeeds.
    ///
    int function (
        _cef_post_data_t* self,
        _cef_post_data_element_t* element) nothrow add_element;

    ///
    // Remove all existing post data elements.
    ///
    void function (_cef_post_data_t* self) nothrow remove_elements;
}

alias cef_post_data_t = _cef_post_data_t;

///
// Create a new cef_post_data_t object.
///
cef_post_data_t* cef_post_data_create ();

///
// Structure used to represent a single element in the request post data. The
// functions of this structure may be called on any thread.
///
struct _cef_post_data_element_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is read-only.
    ///
    int function (_cef_post_data_element_t* self) nothrow is_read_only;

    ///
    // Remove all contents from the post data element.
    ///
    void function (_cef_post_data_element_t* self) nothrow set_to_empty;

    ///
    // The post data element will represent a file.
    ///
    void function (
        _cef_post_data_element_t* self,
        const(cef_string_t)* fileName) nothrow set_to_file;

    ///
    // The post data element will represent bytes.  The bytes passed in will be
    // copied.
    ///
    void function (
        _cef_post_data_element_t* self,
        size_t size,
        const(void)* bytes) nothrow set_to_bytes;

    ///
    // Return the type of this post data element.
    ///
    cef_postdataelement_type_t function (
        _cef_post_data_element_t* self) nothrow get_type;

    ///
    // Return the file name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_post_data_element_t* self) nothrow get_file;

    ///
    // Return the number of bytes.
    ///
    size_t function (_cef_post_data_element_t* self) nothrow get_bytes_count;

    ///
    // Read up to |size| bytes into |bytes| and return the number of bytes
    // actually read.
    ///
    size_t function (
        _cef_post_data_element_t* self,
        size_t size,
        void* bytes) nothrow get_bytes;
}

alias cef_post_data_element_t = _cef_post_data_element_t;

///
// Create a new cef_post_data_element_t object.
///
cef_post_data_element_t* cef_post_data_element_create ();

// CEF_INCLUDE_CAPI_CEF_REQUEST_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=e758d8c53334b91bce818cc6e9f84915778d7827$
//

extern (C):

///
// Implement this structure to provide handler implementations. The handler
// instance will not be released until all objects related to the context have
// been destroyed.
///
struct _cef_request_context_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the browser process UI thread immediately after the request
    // context has been initialized.
    ///
    void function (
        _cef_request_context_handler_t* self,
        _cef_request_context_t* request_context) nothrow on_request_context_initialized;

    ///
    // Called on multiple browser process threads before a plugin instance is
    // loaded. |mime_type| is the mime type of the plugin that will be loaded.
    // |plugin_url| is the content URL that the plugin will load and may be NULL.
    // |is_main_frame| will be true (1) if the plugin is being loaded in the main
    // (top-level) frame, |top_origin_url| is the URL for the top-level frame that
    // contains the plugin when loading a specific plugin instance or NULL when
    // building the initial list of enabled plugins for 'navigator.plugins'
    // JavaScript state. |plugin_info| includes additional information about the
    // plugin that will be loaded. |plugin_policy| is the recommended policy.
    // Modify |plugin_policy| and return true (1) to change the policy. Return
    // false (0) to use the recommended policy. The default plugin policy can be
    // set at runtime using the `--plugin-policy=[allow|detect|block]` command-
    // line flag. Decisions to mark a plugin as disabled by setting
    // |plugin_policy| to PLUGIN_POLICY_DISABLED may be cached when
    // |top_origin_url| is NULL. To purge the plugin list cache and potentially
    // trigger new calls to this function call
    // cef_request_context_t::PurgePluginListCache.
    ///
    int function (
        _cef_request_context_handler_t* self,
        const(cef_string_t)* mime_type,
        const(cef_string_t)* plugin_url,
        int is_main_frame,
        const(cef_string_t)* top_origin_url,
        _cef_web_plugin_info_t* plugin_info,
        cef_plugin_policy_t* plugin_policy) nothrow on_before_plugin_load;

    ///
    // Called on the browser process IO thread before a resource request is
    // initiated. The |browser| and |frame| values represent the source of the
    // request, and may be NULL for requests originating from service workers or
    // cef_urlrequest_t. |request| represents the request contents and cannot be
    // modified in this callback. |is_navigation| will be true (1) if the resource
    // request is a navigation. |is_download| will be true (1) if the resource
    // request is a download. |request_initiator| is the origin (scheme + domain)
    // of the page that initiated the request. Set |disable_default_handling| to
    // true (1) to disable default handling of the request, in which case it will
    // need to be handled via cef_resource_request_handler_t::GetResourceHandler
    // or it will be canceled. To allow the resource load to proceed with default
    // handling return NULL. To specify a handler for the resource return a
    // cef_resource_request_handler_t object. This function will not be called if
    // the client associated with |browser| returns a non-NULL value from
    // cef_request_handler_t::GetResourceRequestHandler for the same request
    // (identified by cef_request_t::GetIdentifier).
    ///
    _cef_resource_request_handler_t* function (
        _cef_request_context_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        int is_navigation,
        int is_download,
        const(cef_string_t)* request_initiator,
        int* disable_default_handling) nothrow get_resource_request_handler;
}

alias cef_request_context_handler_t = _cef_request_context_handler_t;

// CEF_INCLUDE_CAPI_CEF_REQUEST_CONTEXT_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=0167eb1abe614bd6391d273a8085fa3e53e7c217$
//

extern (C):

///
// Callback structure used to select a client certificate for authentication.
///
struct _cef_select_client_certificate_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Chooses the specified certificate for client certificate authentication.
    // NULL value means that no client certificate should be used.
    ///
    void function (
        _cef_select_client_certificate_callback_t* self,
        _cef_x509certificate_t* cert) nothrow select;
}

alias cef_select_client_certificate_callback_t = _cef_select_client_certificate_callback_t;

///
// Implement this structure to handle events related to browser requests. The
// functions of this structure will be called on the thread indicated.
///
struct _cef_request_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the UI thread before browser navigation. Return true (1) to
    // cancel the navigation or false (0) to allow the navigation to proceed. The
    // |request| object cannot be modified in this callback.
    // cef_load_handler_t::OnLoadingStateChange will be called twice in all cases.
    // If the navigation is allowed cef_load_handler_t::OnLoadStart and
    // cef_load_handler_t::OnLoadEnd will be called. If the navigation is canceled
    // cef_load_handler_t::OnLoadError will be called with an |errorCode| value of
    // ERR_ABORTED. The |user_gesture| value will be true (1) if the browser
    // navigated via explicit user gesture (e.g. clicking a link) or false (0) if
    // it navigated automatically (e.g. via the DomContentLoaded event).
    ///
    int function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        int user_gesture,
        int is_redirect) nothrow on_before_browse;

    ///
    // Called on the UI thread before OnBeforeBrowse in certain limited cases
    // where navigating a new or different browser might be desirable. This
    // includes user-initiated navigation that might open in a special way (e.g.
    // links clicked via middle-click or ctrl + left-click) and certain types of
    // cross-origin navigation initiated from the renderer process (e.g.
    // navigating the top-level frame to/from a file URL). The |browser| and
    // |frame| values represent the source of the navigation. The
    // |target_disposition| value indicates where the user intended to navigate
    // the browser based on standard Chromium behaviors (e.g. current tab, new
    // tab, etc). The |user_gesture| value will be true (1) if the browser
    // navigated via explicit user gesture (e.g. clicking a link) or false (0) if
    // it navigated automatically (e.g. via the DomContentLoaded event). Return
    // true (1) to cancel the navigation or false (0) to allow the navigation to
    // proceed in the source browser's top-level frame.
    ///
    int function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        const(cef_string_t)* target_url,
        cef_window_open_disposition_t target_disposition,
        int user_gesture) nothrow on_open_urlfrom_tab;

    ///
    // Called on the browser process IO thread before a resource request is
    // initiated. The |browser| and |frame| values represent the source of the
    // request. |request| represents the request contents and cannot be modified
    // in this callback. |is_navigation| will be true (1) if the resource request
    // is a navigation. |is_download| will be true (1) if the resource request is
    // a download. |request_initiator| is the origin (scheme + domain) of the page
    // that initiated the request. Set |disable_default_handling| to true (1) to
    // disable default handling of the request, in which case it will need to be
    // handled via cef_resource_request_handler_t::GetResourceHandler or it will
    // be canceled. To allow the resource load to proceed with default handling
    // return NULL. To specify a handler for the resource return a
    // cef_resource_request_handler_t object. If this callback returns NULL the
    // same function will be called on the associated
    // cef_request_context_handler_t, if any.
    ///
    _cef_resource_request_handler_t* function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        int is_navigation,
        int is_download,
        const(cef_string_t)* request_initiator,
        int* disable_default_handling) nothrow get_resource_request_handler;

    ///
    // Called on the IO thread when the browser needs credentials from the user.
    // |origin_url| is the origin making this authentication request. |isProxy|
    // indicates whether the host is a proxy server. |host| contains the hostname
    // and |port| contains the port number. |realm| is the realm of the challenge
    // and may be NULL. |scheme| is the authentication scheme used, such as
    // "basic" or "digest", and will be NULL if the source of the request is an
    // FTP server. Return true (1) to continue the request and call
    // cef_auth_callback_t::cont() either in this function or at a later time when
    // the authentication information is available. Return false (0) to cancel the
    // request immediately.
    ///
    int function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* origin_url,
        int isProxy,
        const(cef_string_t)* host,
        int port,
        const(cef_string_t)* realm,
        const(cef_string_t)* scheme,
        _cef_auth_callback_t* callback) nothrow get_auth_credentials;

    ///
    // Called on the IO thread when JavaScript requests a specific storage quota
    // size via the webkitStorageInfo.requestQuota function. |origin_url| is the
    // origin of the page making the request. |new_size| is the requested quota
    // size in bytes. Return true (1) to continue the request and call
    // cef_request_callback_t::cont() either in this function or at a later time
    // to grant or deny the request. Return false (0) to cancel the request
    // immediately.
    ///
    int function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* origin_url,
        int64 new_size,
        _cef_request_callback_t* callback) nothrow on_quota_request;

    ///
    // Called on the UI thread to handle requests for URLs with an invalid SSL
    // certificate. Return true (1) and call cef_request_callback_t::cont() either
    // in this function or at a later time to continue or cancel the request.
    // Return false (0) to cancel the request immediately. If
    // CefSettings.ignore_certificate_errors is set all invalid certificates will
    // be accepted without calling this function.
    ///
    int function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        cef_errorcode_t cert_error,
        const(cef_string_t)* request_url,
        _cef_sslinfo_t* ssl_info,
        _cef_request_callback_t* callback) nothrow on_certificate_error;

    ///
    // Called on the UI thread when a client certificate is being requested for
    // authentication. Return false (0) to use the default behavior and
    // automatically select the first certificate available. Return true (1) and
    // call cef_select_client_certificate_callback_t::Select either in this
    // function or at a later time to select a certificate. Do not call Select or
    // call it with NULL to continue without using any certificate. |isProxy|
    // indicates whether the host is an HTTPS proxy or the origin server. |host|
    // and |port| contains the hostname and port of the SSL server. |certificates|
    // is the list of certificates to choose from; this list has already been
    // pruned by Chromium so that it only contains certificates from issuers that
    // the server trusts.
    ///
    int function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        int isProxy,
        const(cef_string_t)* host,
        int port,
        size_t certificatesCount,
        _cef_x509certificate_t** certificates,
        _cef_select_client_certificate_callback_t* callback) nothrow on_select_client_certificate;

    ///
    // Called on the browser process UI thread when a plugin has crashed.
    // |plugin_path| is the path of the plugin that crashed.
    ///
    void function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        const(cef_string_t)* plugin_path) nothrow on_plugin_crashed;

    ///
    // Called on the browser process UI thread when the render view associated
    // with |browser| is ready to receive/handle IPC messages in the render
    // process.
    ///
    void function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser) nothrow on_render_view_ready;

    ///
    // Called on the browser process UI thread when the render process terminates
    // unexpectedly. |status| indicates how the process terminated.
    ///
    void function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser,
        cef_termination_status_t status) nothrow on_render_process_terminated;

    ///
    // Called on the browser process UI thread when the window.document object of
    // the main frame has been created.
    ///
    void function (
        _cef_request_handler_t* self,
        _cef_browser_t* browser) nothrow on_document_available_in_main_frame;
}

alias cef_request_handler_t = _cef_request_handler_t;

// CEF_INCLUDE_CAPI_CEF_REQUEST_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=b0e2b63b467c6d4e990405d948908da3546ea1c7$
//

extern (C):

///
// Structure used for retrieving resources from the resource bundle (*.pak)
// files loaded by CEF during startup or via the cef_resource_bundle_handler_t
// returned from cef_app_t::GetResourceBundleHandler. See CefSettings for
// additional options related to resource bundle loading. The functions of this
// structure may be called on any thread unless otherwise indicated.
///
struct _cef_resource_bundle_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the localized string for the specified |string_id| or an NULL
    // string if the value is not found. Include cef_pack_strings.h for a listing
    // of valid string ID values.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_resource_bundle_t* self,
        int string_id) nothrow get_localized_string;

    ///
    // Returns a cef_binary_value_t containing the decompressed contents of the
    // specified scale independent |resource_id| or NULL if not found. Include
    // cef_pack_resources.h for a listing of valid resource ID values.
    ///
    _cef_binary_value_t* function (
        _cef_resource_bundle_t* self,
        int resource_id) nothrow get_data_resource;

    ///
    // Returns a cef_binary_value_t containing the decompressed contents of the
    // specified |resource_id| nearest the scale factor |scale_factor| or NULL if
    // not found. Use a |scale_factor| value of SCALE_FACTOR_NONE for scale
    // independent resources or call GetDataResource instead.Include
    // cef_pack_resources.h for a listing of valid resource ID values.
    ///
    _cef_binary_value_t* function (
        _cef_resource_bundle_t* self,
        int resource_id,
        cef_scale_factor_t scale_factor) nothrow get_data_resource_for_scale;
}

alias cef_resource_bundle_t = _cef_resource_bundle_t;

///
// Returns the global resource bundle instance.
///
cef_resource_bundle_t* cef_resource_bundle_get_global ();

// CEF_INCLUDE_CAPI_CEF_RESOURCE_BUNDLE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=fd90a707c59a8c04b1b1bfc6129a90e27934f501$
//

extern (C):

///
// Structure used to implement a custom resource bundle structure. See
// CefSettings for additional options related to resource bundle loading. The
// functions of this structure may be called on multiple threads.
///
struct _cef_resource_bundle_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called to retrieve a localized translation for the specified |string_id|.
    // To provide the translation set |string| to the translation string and
    // return true (1). To use the default translation return false (0). Include
    // cef_pack_strings.h for a listing of valid string ID values.
    ///
    int function (
        _cef_resource_bundle_handler_t* self,
        int string_id,
        cef_string_t* string) nothrow get_localized_string;

    ///
    // Called to retrieve data for the specified scale independent |resource_id|.
    // To provide the resource data set |data| and |data_size| to the data pointer
    // and size respectively and return true (1). To use the default resource data
    // return false (0). The resource data will not be copied and must remain
    // resident in memory. Include cef_pack_resources.h for a listing of valid
    // resource ID values.
    ///
    int function (
        _cef_resource_bundle_handler_t* self,
        int resource_id,
        void** data,
        size_t* data_size) nothrow get_data_resource;

    ///
    // Called to retrieve data for the specified |resource_id| nearest the scale
    // factor |scale_factor|. To provide the resource data set |data| and
    // |data_size| to the data pointer and size respectively and return true (1).
    // To use the default resource data return false (0). The resource data will
    // not be copied and must remain resident in memory. Include
    // cef_pack_resources.h for a listing of valid resource ID values.
    ///
    int function (
        _cef_resource_bundle_handler_t* self,
        int resource_id,
        cef_scale_factor_t scale_factor,
        void** data,
        size_t* data_size) nothrow get_data_resource_for_scale;
}

alias cef_resource_bundle_handler_t = _cef_resource_bundle_handler_t;

// CEF_INCLUDE_CAPI_CEF_RESOURCE_BUNDLE_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=5241e3dd5d3fa0b17dd6d6ea2f30734a32150c88$
//

extern (C):

///
// Callback for asynchronous continuation of cef_resource_handler_t::skip().
///
struct _cef_resource_skip_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Callback for asynchronous continuation of skip(). If |bytes_skipped| > 0
    // then either skip() will be called again until the requested number of bytes
    // have been skipped or the request will proceed. If |bytes_skipped| <= 0 the
    // request will fail with ERR_REQUEST_RANGE_NOT_SATISFIABLE.
    ///
    void function (
        _cef_resource_skip_callback_t* self,
        int64 bytes_skipped) nothrow cont;
}

alias cef_resource_skip_callback_t = _cef_resource_skip_callback_t;

///
// Callback for asynchronous continuation of cef_resource_handler_t::read().
///
struct _cef_resource_read_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Callback for asynchronous continuation of read(). If |bytes_read| == 0 the
    // response will be considered complete. If |bytes_read| > 0 then read() will
    // be called again until the request is complete (based on either the result
    // or the expected content length). If |bytes_read| < 0 then the request will
    // fail and the |bytes_read| value will be treated as the error code.
    ///
    void function (_cef_resource_read_callback_t* self, int bytes_read) nothrow cont;
}

alias cef_resource_read_callback_t = _cef_resource_read_callback_t;

///
// Structure used to implement a custom request handler structure. The functions
// of this structure will be called on the IO thread unless otherwise indicated.
///
struct _cef_resource_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Open the response stream. To handle the request immediately set
    // |handle_request| to true (1) and return true (1). To decide at a later time
    // set |handle_request| to false (0), return true (1), and execute |callback|
    // to continue or cancel the request. To cancel the request immediately set
    // |handle_request| to true (1) and return false (0). This function will be
    // called in sequence but not from a dedicated thread. For backwards
    // compatibility set |handle_request| to false (0) and return false (0) and
    // the ProcessRequest function will be called.
    ///
    int function (
        _cef_resource_handler_t* self,
        _cef_request_t* request,
        int* handle_request,
        _cef_callback_t* callback) nothrow open;

    ///
    // Begin processing the request. To handle the request return true (1) and
    // call cef_callback_t::cont() once the response header information is
    // available (cef_callback_t::cont() can also be called from inside this
    // function if header information is available immediately). To cancel the
    // request return false (0).
    //
    // WARNING: This function is deprecated. Use Open instead.
    ///
    int function (
        _cef_resource_handler_t* self,
        _cef_request_t* request,
        _cef_callback_t* callback) nothrow process_request;

    ///
    // Retrieve response header information. If the response length is not known
    // set |response_length| to -1 and read_response() will be called until it
    // returns false (0). If the response length is known set |response_length| to
    // a positive value and read_response() will be called until it returns false
    // (0) or the specified number of bytes have been read. Use the |response|
    // object to set the mime type, http status code and other optional header
    // values. To redirect the request to a new URL set |redirectUrl| to the new
    // URL. |redirectUrl| can be either a relative or fully qualified URL. It is
    // also possible to set |response| to a redirect http status code and pass the
    // new URL via a Location header. Likewise with |redirectUrl| it is valid to
    // set a relative or fully qualified URL as the Location header value. If an
    // error occured while setting up the request you can call set_error() on
    // |response| to indicate the error condition.
    ///
    void function (
        _cef_resource_handler_t* self,
        _cef_response_t* response,
        int64* response_length,
        cef_string_t* redirectUrl) nothrow get_response_headers;

    ///
    // Skip response data when requested by a Range header. Skip over and discard
    // |bytes_to_skip| bytes of response data. If data is available immediately
    // set |bytes_skipped| to the number of bytes skipped and return true (1). To
    // read the data at a later time set |bytes_skipped| to 0, return true (1) and
    // execute |callback| when the data is available. To indicate failure set
    // |bytes_skipped| to < 0 (e.g. -2 for ERR_FAILED) and return false (0). This
    // function will be called in sequence but not from a dedicated thread.
    ///
    int function (
        _cef_resource_handler_t* self,
        int64 bytes_to_skip,
        int64* bytes_skipped,
        _cef_resource_skip_callback_t* callback) nothrow skip;

    ///
    // Read response data. If data is available immediately copy up to
    // |bytes_to_read| bytes into |data_out|, set |bytes_read| to the number of
    // bytes copied, and return true (1). To read the data at a later time keep a
    // pointer to |data_out|, set |bytes_read| to 0, return true (1) and execute
    // |callback| when the data is available (|data_out| will remain valid until
    // the callback is executed). To indicate response completion set |bytes_read|
    // to 0 and return false (0). To indicate failure set |bytes_read| to < 0
    // (e.g. -2 for ERR_FAILED) and return false (0). This function will be called
    // in sequence but not from a dedicated thread. For backwards compatibility
    // set |bytes_read| to -1 and return false (0) and the ReadResponse function
    // will be called.
    ///
    int function (
        _cef_resource_handler_t* self,
        void* data_out,
        int bytes_to_read,
        int* bytes_read,
        _cef_resource_read_callback_t* callback) nothrow read;

    ///
    // Read response data. If data is available immediately copy up to
    // |bytes_to_read| bytes into |data_out|, set |bytes_read| to the number of
    // bytes copied, and return true (1). To read the data at a later time set
    // |bytes_read| to 0, return true (1) and call cef_callback_t::cont() when the
    // data is available. To indicate response completion return false (0).
    //
    // WARNING: This function is deprecated. Use Skip and Read instead.
    ///
    int function (
        _cef_resource_handler_t* self,
        void* data_out,
        int bytes_to_read,
        int* bytes_read,
        _cef_callback_t* callback) nothrow read_response;

    ///
    // Request processing has been canceled.
    ///
    void function (_cef_resource_handler_t* self) nothrow cancel;
}

alias cef_resource_handler_t = _cef_resource_handler_t;

// CEF_INCLUDE_CAPI_CEF_RESOURCE_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=afc96f188710bd336d09ce479a650aaa3a55357a$
//

extern (C):

///
// Implement this structure to handle events related to browser requests. The
// functions of this structure will be called on the IO thread unless otherwise
// indicated.
///
struct _cef_resource_request_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the IO thread before a resource request is loaded. The |browser|
    // and |frame| values represent the source of the request, and may be NULL for
    // requests originating from service workers or cef_urlrequest_t. To
    // optionally filter cookies for the request return a
    // cef_cookie_access_filter_t object. The |request| object cannot not be
    // modified in this callback.
    ///
    _cef_cookie_access_filter_t* function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request) nothrow get_cookie_access_filter;

    ///
    // Called on the IO thread before a resource request is loaded. The |browser|
    // and |frame| values represent the source of the request, and may be NULL for
    // requests originating from service workers or cef_urlrequest_t. To redirect
    // or change the resource load optionally modify |request|. Modification of
    // the request URL will be treated as a redirect. Return RV_CONTINUE to
    // continue the request immediately. Return RV_CONTINUE_ASYNC and call
    // cef_request_callback_t:: cont() at a later time to continue or cancel the
    // request asynchronously. Return RV_CANCEL to cancel the request immediately.
    //
    ///
    cef_return_value_t function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        _cef_request_callback_t* callback) nothrow on_before_resource_load;

    ///
    // Called on the IO thread before a resource is loaded. The |browser| and
    // |frame| values represent the source of the request, and may be NULL for
    // requests originating from service workers or cef_urlrequest_t. To allow the
    // resource to load using the default network loader return NULL. To specify a
    // handler for the resource return a cef_resource_handler_t object. The
    // |request| object cannot not be modified in this callback.
    ///
    _cef_resource_handler_t* function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request) nothrow get_resource_handler;

    ///
    // Called on the IO thread when a resource load is redirected. The |browser|
    // and |frame| values represent the source of the request, and may be NULL for
    // requests originating from service workers or cef_urlrequest_t. The
    // |request| parameter will contain the old URL and other request-related
    // information. The |response| parameter will contain the response that
    // resulted in the redirect. The |new_url| parameter will contain the new URL
    // and can be changed if desired. The |request| and |response| objects cannot
    // be modified in this callback.
    ///
    void function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        _cef_response_t* response,
        cef_string_t* new_url) nothrow on_resource_redirect;

    ///
    // Called on the IO thread when a resource response is received. The |browser|
    // and |frame| values represent the source of the request, and may be NULL for
    // requests originating from service workers or cef_urlrequest_t. To allow the
    // resource load to proceed without modification return false (0). To redirect
    // or retry the resource load optionally modify |request| and return true (1).
    // Modification of the request URL will be treated as a redirect. Requests
    // handled using the default network loader cannot be redirected in this
    // callback. The |response| object cannot be modified in this callback.
    //
    // WARNING: Redirecting using this function is deprecated. Use
    // OnBeforeResourceLoad or GetResourceHandler to perform redirects.
    ///
    int function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        _cef_response_t* response) nothrow on_resource_response;

    ///
    // Called on the IO thread to optionally filter resource response content. The
    // |browser| and |frame| values represent the source of the request, and may
    // be NULL for requests originating from service workers or cef_urlrequest_t.
    // |request| and |response| represent the request and response respectively
    // and cannot be modified in this callback.
    ///
    _cef_response_filter_t* function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        _cef_response_t* response) nothrow get_resource_response_filter;

    ///
    // Called on the IO thread when a resource load has completed. The |browser|
    // and |frame| values represent the source of the request, and may be NULL for
    // requests originating from service workers or cef_urlrequest_t. |request|
    // and |response| represent the request and response respectively and cannot
    // be modified in this callback. |status| indicates the load completion
    // status. |received_content_length| is the number of response bytes actually
    // read. This function will be called for all requests, including requests
    // that are aborted due to CEF shutdown or destruction of the associated
    // browser. In cases where the associated browser is destroyed this callback
    // may arrive after the cef_life_span_handler_t::OnBeforeClose callback for
    // that browser. The cef_frame_t::IsValid function can be used to test for
    // this situation, and care should be taken not to call |browser| or |frame|
    // functions that modify state (like LoadURL, SendProcessMessage, etc.) if the
    // frame is invalid.
    ///
    void function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        _cef_response_t* response,
        cef_urlrequest_status_t status,
        int64 received_content_length) nothrow on_resource_load_complete;

    ///
    // Called on the IO thread to handle requests for URLs with an unknown
    // protocol component. The |browser| and |frame| values represent the source
    // of the request, and may be NULL for requests originating from service
    // workers or cef_urlrequest_t. |request| cannot be modified in this callback.
    // Set |allow_os_execution| to true (1) to attempt execution via the
    // registered OS protocol handler, if any. SECURITY WARNING: YOU SHOULD USE
    // THIS METHOD TO ENFORCE RESTRICTIONS BASED ON SCHEME, HOST OR OTHER URL
    // ANALYSIS BEFORE ALLOWING OS EXECUTION.
    ///
    void function (
        _cef_resource_request_handler_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        int* allow_os_execution) nothrow on_protocol_execution;
}

alias cef_resource_request_handler_t = _cef_resource_request_handler_t;

///
// Implement this structure to filter cookies that may be sent or received from
// resource requests. The functions of this structure will be called on the IO
// thread unless otherwise indicated.
///
struct _cef_cookie_access_filter_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the IO thread before a resource request is sent. The |browser|
    // and |frame| values represent the source of the request, and may be NULL for
    // requests originating from service workers or cef_urlrequest_t. |request|
    // cannot be modified in this callback. Return true (1) if the specified
    // cookie can be sent with the request or false (0) otherwise.
    ///
    int function (
        _cef_cookie_access_filter_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        const(_cef_cookie_t)* cookie) nothrow can_send_cookie;

    ///
    // Called on the IO thread after a resource response is received. The
    // |browser| and |frame| values represent the source of the request, and may
    // be NULL for requests originating from service workers or cef_urlrequest_t.
    // |request| cannot be modified in this callback. Return true (1) if the
    // specified cookie returned with the response can be saved or false (0)
    // otherwise.
    ///
    int function (
        _cef_cookie_access_filter_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        _cef_request_t* request,
        _cef_response_t* response,
        const(_cef_cookie_t)* cookie) nothrow can_save_cookie;
}

alias cef_cookie_access_filter_t = _cef_cookie_access_filter_t;

// CEF_INCLUDE_CAPI_CEF_RESOURCE_REQUEST_HANDLER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=2bccae35945ecea55c4c79bba840b44a691f1aa3$
//

extern (C):

///
// Structure used to represent a web response. The functions of this structure
// may be called on any thread.
///
struct _cef_response_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is read-only.
    ///
    int function (_cef_response_t* self) nothrow is_read_only;

    ///
    // Get the response error code. Returns ERR_NONE if there was no error.
    ///
    cef_errorcode_t function (_cef_response_t* self) nothrow get_error;

    ///
    // Set the response error code. This can be used by custom scheme handlers to
    // return errors during initial request processing.
    ///
    void function (_cef_response_t* self, cef_errorcode_t error) nothrow set_error;

    ///
    // Get the response status code.
    ///
    int function (_cef_response_t* self) nothrow get_status;

    ///
    // Set the response status code.
    ///
    void function (_cef_response_t* self, int status) nothrow set_status;

    ///
    // Get the response status text.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_response_t* self) nothrow get_status_text;

    ///
    // Set the response status text.
    ///
    void function (
        _cef_response_t* self,
        const(cef_string_t)* statusText) nothrow set_status_text;

    ///
    // Get the response mime type.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_response_t* self) nothrow get_mime_type;

    ///
    // Set the response mime type.
    ///
    void function (
        _cef_response_t* self,
        const(cef_string_t)* mimeType) nothrow set_mime_type;

    ///
    // Get the response charset.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_response_t* self) nothrow get_charset;

    ///
    // Set the response charset.
    ///
    void function (
        _cef_response_t* self,
        const(cef_string_t)* charset) nothrow set_charset;

    ///
    // Get the value for the specified response header field.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_response_t* self,
        const(cef_string_t)* name) nothrow get_header_by_name;

    ///
    // Set the header |name| to |value|. If |overwrite| is true (1) any existing
    // values will be replaced with the new value. If |overwrite| is false (0) any
    // existing values will not be overwritten.
    ///
    void function (
        _cef_response_t* self,
        const(cef_string_t)* name,
        const(cef_string_t)* value,
        int overwrite) nothrow set_header_by_name;

    ///
    // Get all response header fields.
    ///
    void function (
        _cef_response_t* self,
        cef_string_multimap_t headerMap) nothrow get_header_map;

    ///
    // Set all response header fields.
    ///
    void function (
        _cef_response_t* self,
        cef_string_multimap_t headerMap) nothrow set_header_map;

    ///
    // Get the resolved URL after redirects or changed as a result of HSTS.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_response_t* self) nothrow get_url;

    ///
    // Set the resolved URL after redirects or changed as a result of HSTS.
    ///
    void function (_cef_response_t* self, const(cef_string_t)* url) nothrow set_url;
}

alias cef_response_t = _cef_response_t;

///
// Create a new cef_response_t object.
///
cef_response_t* cef_response_create ();

// CEF_INCLUDE_CAPI_CEF_RESPONSE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=5b2602702a13a71ac012808eecb09bb8b9494551$
//

extern (C):

///
// Implement this structure to filter resource response content. The functions
// of this structure will be called on the browser process IO thread.
///
struct _cef_response_filter_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Initialize the response filter. Will only be called a single time. The
    // filter will not be installed if this function returns false (0).
    ///
    int function (_cef_response_filter_t* self) nothrow init_filter;

    ///
    // Called to filter a chunk of data. Expected usage is as follows:
    //
    //  A. Read input data from |data_in| and set |data_in_read| to the number of
    //     bytes that were read up to a maximum of |data_in_size|. |data_in| will
    //     be NULL if |data_in_size| is zero.
    //  B. Write filtered output data to |data_out| and set |data_out_written| to
    //     the number of bytes that were written up to a maximum of
    //     |data_out_size|. If no output data was written then all data must be
    //     read from |data_in| (user must set |data_in_read| = |data_in_size|).
    //  C. Return RESPONSE_FILTER_DONE if all output data was written or
    //     RESPONSE_FILTER_NEED_MORE_DATA if output data is still pending.
    //
    // This function will be called repeatedly until the input buffer has been
    // fully read (user sets |data_in_read| = |data_in_size|) and there is no more
    // input data to filter (the resource response is complete). This function may
    // then be called an additional time with an NULL input buffer if the user
    // filled the output buffer (set |data_out_written| = |data_out_size|) and
    // returned RESPONSE_FILTER_NEED_MORE_DATA to indicate that output data is
    // still pending.
    //
    // Calls to this function will stop when one of the following conditions is
    // met:
    //
    //  A. There is no more input data to filter (the resource response is
    //     complete) and the user sets |data_out_written| = 0 or returns
    //     RESPONSE_FILTER_DONE to indicate that all data has been written, or;
    //  B. The user returns RESPONSE_FILTER_ERROR to indicate an error.
    //
    // Do not keep a reference to the buffers passed to this function.
    ///
    cef_response_filter_status_t function (
        _cef_response_filter_t* self,
        void* data_in,
        size_t data_in_size,
        size_t* data_in_read,
        void* data_out,
        size_t data_out_size,
        size_t* data_out_written) nothrow filter;
}

alias cef_response_filter_t = _cef_response_filter_t;

// CEF_INCLUDE_CAPI_CEF_RESPONSE_FILTER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=d93b4ad0b71ffe0a05326b39c3ed0bdb26a73fac$
//

extern (C):

///
// Structure that manages custom scheme registrations.
///
struct _cef_scheme_registrar_t
{
    ///
    // Base structure.
    ///
    cef_base_scoped_t base;

    ///
    // Register a custom scheme. This function should not be called for the built-
    // in HTTP, HTTPS, FILE, FTP, ABOUT and DATA schemes.
    //
    // See cef_scheme_options_t for possible values for |options|.
    //
    // This function may be called on any thread. It should only be called once
    // per unique |scheme_name| value. If |scheme_name| is already registered or
    // if an error occurs this function will return false (0).
    ///
    int function (
        _cef_scheme_registrar_t* self,
        const(cef_string_t)* scheme_name,
        int options) nothrow add_custom_scheme;
}

alias cef_scheme_registrar_t = _cef_scheme_registrar_t;

///
// Structure that creates cef_resource_handler_t instances for handling scheme
// requests. The functions of this structure will always be called on the IO
// thread.
///
struct _cef_scheme_handler_factory_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Return a new resource handler instance to handle the request or an NULL
    // reference to allow default handling of the request. |browser| and |frame|
    // will be the browser window and frame respectively that originated the
    // request or NULL if the request did not originate from a browser window (for
    // example, if the request came from cef_urlrequest_t). The |request| object
    // passed to this function cannot be modified.
    ///
    _cef_resource_handler_t* function (
        _cef_scheme_handler_factory_t* self,
        _cef_browser_t* browser,
        _cef_frame_t* frame,
        const(cef_string_t)* scheme_name,
        _cef_request_t* request) nothrow create;
}

alias cef_scheme_handler_factory_t = _cef_scheme_handler_factory_t;

///
// Register a scheme handler factory with the global request context. An NULL
// |domain_name| value for a standard scheme will cause the factory to match all
// domain names. The |domain_name| value will be ignored for non-standard
// schemes. If |scheme_name| is a built-in scheme and no handler is returned by
// |factory| then the built-in scheme handler factory will be called. If
// |scheme_name| is a custom scheme then you must also implement the
// cef_app_t::on_register_custom_schemes() function in all processes. This
// function may be called multiple times to change or remove the factory that
// matches the specified |scheme_name| and optional |domain_name|. Returns false
// (0) if an error occurs. This function may be called on any thread in the
// browser process. Using this function is equivalent to calling cef_request_con
// text_t::cef_request_context_get_global_context()->register_scheme_handler_fac
// tory().
///
int cef_register_scheme_handler_factory (
    const(cef_string_t)* scheme_name,
    const(cef_string_t)* domain_name,
    cef_scheme_handler_factory_t* factory);

///
// Clear all scheme handler factories registered with the global request
// context. Returns false (0) on error. This function may be called on any
// thread in the browser process. Using this function is equivalent to calling c
// ef_request_context_t::cef_request_context_get_global_context()->clear_scheme_
// handler_factories().
///
int cef_clear_scheme_handler_factories ();

// CEF_INCLUDE_CAPI_CEF_SCHEME_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=ffd489adc301ed88e1f30f8f38cec1730411a4b5$
//

extern (C):

///
// Structure representing a server that supports HTTP and WebSocket requests.
// Server capacity is limited and is intended to handle only a small number of
// simultaneous connections (e.g. for communicating between applications on
// localhost). The functions of this structure are safe to call from any thread
// in the brower process unless otherwise indicated.
///
struct _cef_server_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the task runner for the dedicated server thread.
    ///
    _cef_task_runner_t* function (_cef_server_t* self) nothrow get_task_runner;

    ///
    // Stop the server and shut down the dedicated server thread. See
    // cef_server_handler_t::OnServerCreated documentation for a description of
    // server lifespan.
    ///
    void function (_cef_server_t* self) nothrow shutdown;

    ///
    // Returns true (1) if the server is currently running and accepting incoming
    // connections. See cef_server_handler_t::OnServerCreated documentation for a
    // description of server lifespan. This function must be called on the
    // dedicated server thread.
    ///
    int function (_cef_server_t* self) nothrow is_running;

    ///
    // Returns the server address including the port number.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_server_t* self) nothrow get_address;

    ///
    // Returns true (1) if the server currently has a connection. This function
    // must be called on the dedicated server thread.
    ///
    int function (_cef_server_t* self) nothrow has_connection;

    ///
    // Returns true (1) if |connection_id| represents a valid connection. This
    // function must be called on the dedicated server thread.
    ///
    int function (_cef_server_t* self, int connection_id) nothrow is_valid_connection;

    ///
    // Send an HTTP 200 "OK" response to the connection identified by
    // |connection_id|. |content_type| is the response content type (e.g.
    // "text/html"), |data| is the response content, and |data_size| is the size
    // of |data| in bytes. The contents of |data| will be copied. The connection
    // will be closed automatically after the response is sent.
    ///
    void function (
        _cef_server_t* self,
        int connection_id,
        const(cef_string_t)* content_type,
        const(void)* data,
        size_t data_size) nothrow send_http200response;

    ///
    // Send an HTTP 404 "Not Found" response to the connection identified by
    // |connection_id|. The connection will be closed automatically after the
    // response is sent.
    ///
    void function (
        _cef_server_t* self,
        int connection_id) nothrow send_http404response;

    ///
    // Send an HTTP 500 "Internal Server Error" response to the connection
    // identified by |connection_id|. |error_message| is the associated error
    // message. The connection will be closed automatically after the response is
    // sent.
    ///
    void function (
        _cef_server_t* self,
        int connection_id,
        const(cef_string_t)* error_message) nothrow send_http500response;

    ///
    // Send a custom HTTP response to the connection identified by
    // |connection_id|. |response_code| is the HTTP response code sent in the
    // status line (e.g. 200), |content_type| is the response content type sent as
    // the "Content-Type" header (e.g. "text/html"), |content_length| is the
    // expected content length, and |extra_headers| is the map of extra response
    // headers. If |content_length| is >= 0 then the "Content-Length" header will
    // be sent. If |content_length| is 0 then no content is expected and the
    // connection will be closed automatically after the response is sent. If
    // |content_length| is < 0 then no "Content-Length" header will be sent and
    // the client will continue reading until the connection is closed. Use the
    // SendRawData function to send the content, if applicable, and call
    // CloseConnection after all content has been sent.
    ///
    void function (
        _cef_server_t* self,
        int connection_id,
        int response_code,
        const(cef_string_t)* content_type,
        int64 content_length,
        cef_string_multimap_t extra_headers) nothrow send_http_response;

    ///
    // Send raw data directly to the connection identified by |connection_id|.
    // |data| is the raw data and |data_size| is the size of |data| in bytes. The
    // contents of |data| will be copied. No validation of |data| is performed
    // internally so the client should be careful to send the amount indicated by
    // the "Content-Length" header, if specified. See SendHttpResponse
    // documentation for intended usage.
    ///
    void function (
        _cef_server_t* self,
        int connection_id,
        const(void)* data,
        size_t data_size) nothrow send_raw_data;

    ///
    // Close the connection identified by |connection_id|. See SendHttpResponse
    // documentation for intended usage.
    ///
    void function (_cef_server_t* self, int connection_id) nothrow close_connection;

    ///
    // Send a WebSocket message to the connection identified by |connection_id|.
    // |data| is the response content and |data_size| is the size of |data| in
    // bytes. The contents of |data| will be copied. See
    // cef_server_handler_t::OnWebSocketRequest documentation for intended usage.
    ///
    void function (
        _cef_server_t* self,
        int connection_id,
        const(void)* data,
        size_t data_size) nothrow send_web_socket_message;
}

alias cef_server_t = _cef_server_t;

///
// Create a new server that binds to |address| and |port|. |address| must be a
// valid IPv4 or IPv6 address (e.g. 127.0.0.1 or ::1) and |port| must be a port
// number outside of the reserved range (e.g. between 1025 and 65535 on most
// platforms). |backlog| is the maximum number of pending connections. A new
// thread will be created for each CreateServer call (the "dedicated server
// thread"). It is therefore recommended to use a different cef_server_handler_t
// instance for each CreateServer call to avoid thread safety issues in the
// cef_server_handler_t implementation. The
// cef_server_handler_t::OnServerCreated function will be called on the
// dedicated server thread to report success or failure. See
// cef_server_handler_t::OnServerCreated documentation for a description of
// server lifespan.
///
void cef_server_create (
    const(cef_string_t)* address,
    uint16 port,
    int backlog,
    _cef_server_handler_t* handler);

///
// Implement this structure to handle HTTP server requests. A new thread will be
// created for each cef_server_t::CreateServer call (the "dedicated server
// thread"), and the functions of this structure will be called on that thread.
// It is therefore recommended to use a different cef_server_handler_t instance
// for each cef_server_t::CreateServer call to avoid thread safety issues in the
// cef_server_handler_t implementation.
///
struct _cef_server_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called when |server| is created. If the server was started successfully
    // then cef_server_t::IsRunning will return true (1). The server will continue
    // running until cef_server_t::Shutdown is called, after which time
    // OnServerDestroyed will be called. If the server failed to start then
    // OnServerDestroyed will be called immediately after this function returns.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server) nothrow on_server_created;

    ///
    // Called when |server| is destroyed. The server thread will be stopped after
    // this function returns. The client should release any references to |server|
    // when this function is called. See OnServerCreated documentation for a
    // description of server lifespan.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server) nothrow on_server_destroyed;

    ///
    // Called when a client connects to |server|. |connection_id| uniquely
    // identifies the connection. Each call to this function will have a matching
    // call to OnClientDisconnected.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server,
        int connection_id) nothrow on_client_connected;

    ///
    // Called when a client disconnects from |server|. |connection_id| uniquely
    // identifies the connection. The client should release any data associated
    // with |connection_id| when this function is called and |connection_id|
    // should no longer be passed to cef_server_t functions. Disconnects can
    // originate from either the client or the server. For example, the server
    // will disconnect automatically after a cef_server_t::SendHttpXXXResponse
    // function is called.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server,
        int connection_id) nothrow on_client_disconnected;

    ///
    // Called when |server| receives an HTTP request. |connection_id| uniquely
    // identifies the connection, |client_address| is the requesting IPv4 or IPv6
    // client address including port number, and |request| contains the request
    // contents (URL, function, headers and optional POST data). Call cef_server_t
    // functions either synchronously or asynchronusly to send a response.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server,
        int connection_id,
        const(cef_string_t)* client_address,
        _cef_request_t* request) nothrow on_http_request;

    ///
    // Called when |server| receives a WebSocket request. |connection_id| uniquely
    // identifies the connection, |client_address| is the requesting IPv4 or IPv6
    // client address including port number, and |request| contains the request
    // contents (URL, function, headers and optional POST data). Execute
    // |callback| either synchronously or asynchronously to accept or decline the
    // WebSocket connection. If the request is accepted then OnWebSocketConnected
    // will be called after the WebSocket has connected and incoming messages will
    // be delivered to the OnWebSocketMessage callback. If the request is declined
    // then the client will be disconnected and OnClientDisconnected will be
    // called. Call the cef_server_t::SendWebSocketMessage function after
    // receiving the OnWebSocketConnected callback to respond with WebSocket
    // messages.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server,
        int connection_id,
        const(cef_string_t)* client_address,
        _cef_request_t* request,
        _cef_callback_t* callback) nothrow on_web_socket_request;

    ///
    // Called after the client has accepted the WebSocket connection for |server|
    // and |connection_id| via the OnWebSocketRequest callback. See
    // OnWebSocketRequest documentation for intended usage.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server,
        int connection_id) nothrow on_web_socket_connected;

    ///
    // Called when |server| receives an WebSocket message. |connection_id|
    // uniquely identifies the connection, |data| is the message content and
    // |data_size| is the size of |data| in bytes. Do not keep a reference to
    // |data| outside of this function. See OnWebSocketRequest documentation for
    // intended usage.
    ///
    void function (
        _cef_server_handler_t* self,
        _cef_server_t* server,
        int connection_id,
        const(void)* data,
        size_t data_size) nothrow on_web_socket_message;
}

alias cef_server_handler_t = _cef_server_handler_t;

// CEF_INCLUDE_CAPI_CEF_SERVER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=badaadcff4641fea876fb626b8ffe5a6f34a376c$
//

extern (C):

///
// Structure representing SSL information.
///
struct _cef_sslinfo_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns a bitmask containing any and all problems verifying the server
    // certificate.
    ///
    cef_cert_status_t function (_cef_sslinfo_t* self) nothrow get_cert_status;

    ///
    // Returns the X.509 certificate.
    ///
    _cef_x509certificate_t* function (
        _cef_sslinfo_t* self) nothrow get_x509certificate;
}

alias cef_sslinfo_t = _cef_sslinfo_t;

///
// Returns true (1) if the certificate status represents an error.
///
int cef_is_cert_status_error (cef_cert_status_t status);

// CEF_INCLUDE_CAPI_CEF_SSL_INFO_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=3755121a7b89de52a67885ac1c6d12de23f4b657$
//

extern (C):

///
// Structure representing the SSL information for a navigation entry.
///
struct _cef_sslstatus_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if the status is related to a secure SSL/TLS connection.
    ///
    int function (_cef_sslstatus_t* self) nothrow is_secure_connection;

    ///
    // Returns a bitmask containing any and all problems verifying the server
    // certificate.
    ///
    cef_cert_status_t function (_cef_sslstatus_t* self) nothrow get_cert_status;

    ///
    // Returns the SSL version used for the SSL connection.
    ///
    cef_ssl_version_t function (_cef_sslstatus_t* self) nothrow get_sslversion;

    ///
    // Returns a bitmask containing the page security content status.
    ///
    cef_ssl_content_status_t function (
        _cef_sslstatus_t* self) nothrow get_content_status;

    ///
    // Returns the X.509 certificate.
    ///
    _cef_x509certificate_t* function (
        _cef_sslstatus_t* self) nothrow get_x509certificate;
}

alias cef_sslstatus_t = _cef_sslstatus_t;

// CEF_INCLUDE_CAPI_CEF_SSL_STATUS_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=bd5bbcdc385f83512bf64304e180f1a05b765c16$
//

extern (C):

///
// Structure the client can implement to provide a custom stream reader. The
// functions of this structure may be called on any thread.
///
struct _cef_read_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Read raw binary data.
    ///
    size_t function (
        _cef_read_handler_t* self,
        void* ptr,
        size_t size,
        size_t n) nothrow read;

    ///
    // Seek to the specified offset position. |whence| may be any one of SEEK_CUR,
    // SEEK_END or SEEK_SET. Return zero on success and non-zero on failure.
    ///
    int function (_cef_read_handler_t* self, int64 offset, int whence) nothrow seek;

    ///
    // Return the current offset position.
    ///
    int64 function (_cef_read_handler_t* self) nothrow tell;

    ///
    // Return non-zero if at end of file.
    ///
    int function (_cef_read_handler_t* self) nothrow eof;

    ///
    // Return true (1) if this handler performs work like accessing the file
    // system which may block. Used as a hint for determining the thread to access
    // the handler from.
    ///
    int function (_cef_read_handler_t* self) nothrow may_block;
}

alias cef_read_handler_t = _cef_read_handler_t;

///
// Structure used to read data from a stream. The functions of this structure
// may be called on any thread.
///
struct _cef_stream_reader_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Read raw binary data.
    ///
    size_t function (
        _cef_stream_reader_t* self,
        void* ptr,
        size_t size,
        size_t n) nothrow read;

    ///
    // Seek to the specified offset position. |whence| may be any one of SEEK_CUR,
    // SEEK_END or SEEK_SET. Returns zero on success and non-zero on failure.
    ///
    int function (_cef_stream_reader_t* self, int64 offset, int whence) nothrow seek;

    ///
    // Return the current offset position.
    ///
    int64 function (_cef_stream_reader_t* self) nothrow tell;

    ///
    // Return non-zero if at end of file.
    ///
    int function (_cef_stream_reader_t* self) nothrow eof;

    ///
    // Returns true (1) if this reader performs work like accessing the file
    // system which may block. Used as a hint for determining the thread to access
    // the reader from.
    ///
    int function (_cef_stream_reader_t* self) nothrow may_block;
}

alias cef_stream_reader_t = _cef_stream_reader_t;

///
// Create a new cef_stream_reader_t object from a file.
///
cef_stream_reader_t* cef_stream_reader_create_for_file (
    const(cef_string_t)* fileName);

///
// Create a new cef_stream_reader_t object from data.
///
cef_stream_reader_t* cef_stream_reader_create_for_data (
    void* data,
    size_t size);

///
// Create a new cef_stream_reader_t object from a custom handler.
///
cef_stream_reader_t* cef_stream_reader_create_for_handler (
    cef_read_handler_t* handler);

///
// Structure the client can implement to provide a custom stream writer. The
// functions of this structure may be called on any thread.
///
struct _cef_write_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Write raw binary data.
    ///
    size_t function (
        _cef_write_handler_t* self,
        const(void)* ptr,
        size_t size,
        size_t n) nothrow write;

    ///
    // Seek to the specified offset position. |whence| may be any one of SEEK_CUR,
    // SEEK_END or SEEK_SET. Return zero on success and non-zero on failure.
    ///
    int function (_cef_write_handler_t* self, int64 offset, int whence) nothrow seek;

    ///
    // Return the current offset position.
    ///
    int64 function (_cef_write_handler_t* self) nothrow tell;

    ///
    // Flush the stream.
    ///
    int function (_cef_write_handler_t* self) nothrow flush;

    ///
    // Return true (1) if this handler performs work like accessing the file
    // system which may block. Used as a hint for determining the thread to access
    // the handler from.
    ///
    int function (_cef_write_handler_t* self) nothrow may_block;
}

alias cef_write_handler_t = _cef_write_handler_t;

///
// Structure used to write data to a stream. The functions of this structure may
// be called on any thread.
///
struct _cef_stream_writer_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Write raw binary data.
    ///
    size_t function (
        _cef_stream_writer_t* self,
        const(void)* ptr,
        size_t size,
        size_t n) nothrow write;

    ///
    // Seek to the specified offset position. |whence| may be any one of SEEK_CUR,
    // SEEK_END or SEEK_SET. Returns zero on success and non-zero on failure.
    ///
    int function (_cef_stream_writer_t* self, int64 offset, int whence) nothrow seek;

    ///
    // Return the current offset position.
    ///
    int64 function (_cef_stream_writer_t* self) nothrow tell;

    ///
    // Flush the stream.
    ///
    int function (_cef_stream_writer_t* self) nothrow flush;

    ///
    // Returns true (1) if this writer performs work like accessing the file
    // system which may block. Used as a hint for determining the thread to access
    // the writer from.
    ///
    int function (_cef_stream_writer_t* self) nothrow may_block;
}

alias cef_stream_writer_t = _cef_stream_writer_t;

///
// Create a new cef_stream_writer_t object for a file.
///
cef_stream_writer_t* cef_stream_writer_create_for_file (
    const(cef_string_t)* fileName);

///
// Create a new cef_stream_writer_t object for a custom handler.
///
cef_stream_writer_t* cef_stream_writer_create_for_handler (
    cef_write_handler_t* handler);

// CEF_INCLUDE_CAPI_CEF_STREAM_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=bba3a9719860f9a81c63cbb052a4c501416b2ada$
//

extern (C):

///
// Implement this structure to receive string values asynchronously.
///
struct _cef_string_visitor_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be executed.
    ///
    void function (
        _cef_string_visitor_t* self,
        const(cef_string_t)* string) nothrow visit;
}

alias cef_string_visitor_t = _cef_string_visitor_t;

// CEF_INCLUDE_CAPI_CEF_STRING_VISITOR_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=025daa5db3bf16029953da7703e3e5968bd97fe2$
//

extern (C):

///
// Implement this structure for asynchronous task execution. If the task is
// posted successfully and if the associated message loop is still running then
// the execute() function will be called on the target thread. If the task fails
// to post then the task object may be destroyed on the source thread instead of
// the target thread. For this reason be cautious when performing work in the
// task object destructor.
///
struct _cef_task_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be executed on the target thread.
    ///
    void function (_cef_task_t* self) nothrow execute;
}

alias cef_task_t = _cef_task_t;

///
// Structure that asynchronously executes tasks on the associated thread. It is
// safe to call the functions of this structure on any thread.
//
// CEF maintains multiple internal threads that are used for handling different
// types of tasks in different processes. The cef_thread_id_t definitions in
// cef_types.h list the common CEF threads. Task runners are also available for
// other CEF threads as appropriate (for example, V8 WebWorker threads).
///
struct _cef_task_runner_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is pointing to the same task runner as
    // |that| object.
    ///
    int function (_cef_task_runner_t* self, _cef_task_runner_t* that) nothrow is_same;

    ///
    // Returns true (1) if this task runner belongs to the current thread.
    ///
    int function (_cef_task_runner_t* self) nothrow belongs_to_current_thread;

    ///
    // Returns true (1) if this task runner is for the specified CEF thread.
    ///
    int function (
        _cef_task_runner_t* self,
        cef_thread_id_t threadId) nothrow belongs_to_thread;

    ///
    // Post a task for execution on the thread associated with this task runner.
    // Execution will occur asynchronously.
    ///
    int function (_cef_task_runner_t* self, _cef_task_t* task) nothrow post_task;

    ///
    // Post a task for delayed execution on the thread associated with this task
    // runner. Execution will occur asynchronously. Delayed tasks are not
    // supported on V8 WebWorker threads and will be executed without the
    // specified delay.
    ///
    int function (
        _cef_task_runner_t* self,
        _cef_task_t* task,
        int64 delay_ms) nothrow post_delayed_task;
}

alias cef_task_runner_t = _cef_task_runner_t;

///
// Returns the task runner for the current thread. Only CEF threads will have
// task runners. An NULL reference will be returned if this function is called
// on an invalid thread.
///
cef_task_runner_t* cef_task_runner_get_for_current_thread ();

///
// Returns the task runner for the specified CEF thread.
///
cef_task_runner_t* cef_task_runner_get_for_thread (cef_thread_id_t threadId);

///
// Returns true (1) if called on the specified thread. Equivalent to using
// cef_task_runner_t::GetForThread(threadId)->belongs_to_current_thread().
///
int cef_currently_on (cef_thread_id_t threadId);

///
// Post a task for execution on the specified thread. Equivalent to using
// cef_task_runner_t::GetForThread(threadId)->PostTask(task).
///
int cef_post_task (cef_thread_id_t threadId, cef_task_t* task);

///
// Post a task for delayed execution on the specified thread. Equivalent to
// using cef_task_runner_t::GetForThread(threadId)->PostDelayedTask(task,
// delay_ms).
///
int cef_post_delayed_task (
    cef_thread_id_t threadId,
    cef_task_t* task,
    int64 delay_ms);

// CEF_INCLUDE_CAPI_CEF_TASK_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=d443c0990241554b548bc946f46f35582445e818$
//

extern (C):

///
// A simple thread abstraction that establishes a message loop on a new thread.
// The consumer uses cef_task_runner_t to execute code on the thread's message
// loop. The thread is terminated when the cef_thread_t object is destroyed or
// stop() is called. All pending tasks queued on the thread's message loop will
// run to completion before the thread is terminated. cef_thread_create() can be
// called on any valid CEF thread in either the browser or render process. This
// structure should only be used for tasks that require a dedicated thread. In
// most cases you can post tasks to an existing CEF thread instead of creating a
// new one; see cef_task.h for details.
///
struct _cef_thread_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the cef_task_runner_t that will execute code on this thread's
    // message loop. This function is safe to call from any thread.
    ///
    _cef_task_runner_t* function (_cef_thread_t* self) nothrow get_task_runner;

    ///
    // Returns the platform thread ID. It will return the same value after stop()
    // is called. This function is safe to call from any thread.
    ///
    cef_platform_thread_id_t function (
        _cef_thread_t* self) nothrow get_platform_thread_id;

    ///
    // Stop and join the thread. This function must be called from the same thread
    // that called cef_thread_create(). Do not call this function if
    // cef_thread_create() was called with a |stoppable| value of false (0).
    ///
    void function (_cef_thread_t* self) nothrow stop;

    ///
    // Returns true (1) if the thread is currently running. This function must be
    // called from the same thread that called cef_thread_create().
    ///
    int function (_cef_thread_t* self) nothrow is_running;
}

alias cef_thread_t = _cef_thread_t;

///
// Create and start a new thread. This function does not block waiting for the
// thread to run initialization. |display_name| is the name that will be used to
// identify the thread. |priority| is the thread execution priority.
// |message_loop_type| indicates the set of asynchronous events that the thread
// can process. If |stoppable| is true (1) the thread will stopped and joined on
// destruction or when stop() is called; otherwise, the thread cannot be stopped
// and will be leaked on shutdown. On Windows the |com_init_mode| value
// specifies how COM will be initialized for the thread. If |com_init_mode| is
// set to COM_INIT_MODE_STA then |message_loop_type| must be set to ML_TYPE_UI.
///
cef_thread_t* cef_thread_create (
    const(cef_string_t)* display_name,
    cef_thread_priority_t priority,
    cef_message_loop_type_t message_loop_type,
    int stoppable,
    cef_com_init_mode_t com_init_mode);

// CEF_INCLUDE_CAPI_CEF_THREAD_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=b1b96b7cb636afbd201b88bc1544afc58099c0b6$
//

extern (C):

///
// Implement this structure to receive notification when tracing has completed.
// The functions of this structure will be called on the browser process UI
// thread.
///
struct _cef_end_tracing_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called after all processes have sent their trace data. |tracing_file| is
    // the path at which tracing data was written. The client is responsible for
    // deleting |tracing_file|.
    ///
    void function (
        _cef_end_tracing_callback_t* self,
        const(cef_string_t)* tracing_file) nothrow on_end_tracing_complete;
}

alias cef_end_tracing_callback_t = _cef_end_tracing_callback_t;

///
// Start tracing events on all processes. Tracing is initialized asynchronously
// and |callback| will be executed on the UI thread after initialization is
// complete.
//
// If CefBeginTracing was called previously, or if a CefEndTracingAsync call is
// pending, CefBeginTracing will fail and return false (0).
//
// |categories| is a comma-delimited list of category wildcards. A category can
// have an optional '-' prefix to make it an excluded category. Having both
// included and excluded categories in the same list is not supported.
//
// Example: "test_MyTest*" Example: "test_MyTest*,test_OtherStuff" Example:
// "-excluded_category1,-excluded_category2"
//
// This function must be called on the browser process UI thread.
///
int cef_begin_tracing (
    const(cef_string_t)* categories,
    _cef_completion_callback_t* callback);

///
// Stop tracing events on all processes.
//
// This function will fail and return false (0) if a previous call to
// CefEndTracingAsync is already pending or if CefBeginTracing was not called.
//
// |tracing_file| is the path at which tracing data will be written and
// |callback| is the callback that will be executed once all processes have sent
// their trace data. If |tracing_file| is NULL a new temporary file path will be
// used. If |callback| is NULL no trace data will be written.
//
// This function must be called on the browser process UI thread.
///
int cef_end_tracing (
    const(cef_string_t)* tracing_file,
    cef_end_tracing_callback_t* callback);

///
// Returns the current system trace time or, if none is defined, the current
// high-res time. Can be used by clients to synchronize with the time
// information in trace events.
///
int64 cef_now_from_system_trace_time ();

// CEF_INCLUDE_CAPI_CEF_TRACE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=75f4f7a9ff628a6ae699a697722caa5d49546784$
//

extern (C):

///
// Structure used to make a URL request. URL requests are not associated with a
// browser instance so no cef_client_t callbacks will be executed. URL requests
// can be created on any valid CEF thread in either the browser or render
// process. Once created the functions of the URL request object must be
// accessed on the same thread that created it.
///
struct _cef_urlrequest_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the request object used to create this URL request. The returned
    // object is read-only and should not be modified.
    ///
    _cef_request_t* function (_cef_urlrequest_t* self) nothrow get_request;

    ///
    // Returns the client.
    ///
    _cef_urlrequest_client_t* function (_cef_urlrequest_t* self) nothrow get_client;

    ///
    // Returns the request status.
    ///
    cef_urlrequest_status_t function (
        _cef_urlrequest_t* self) nothrow get_request_status;

    ///
    // Returns the request error if status is UR_CANCELED or UR_FAILED, or 0
    // otherwise.
    ///
    cef_errorcode_t function (_cef_urlrequest_t* self) nothrow get_request_error;

    ///
    // Returns the response, or NULL if no response information is available.
    // Response information will only be available after the upload has completed.
    // The returned object is read-only and should not be modified.
    ///
    _cef_response_t* function (_cef_urlrequest_t* self) nothrow get_response;

    ///
    // Returns true (1) if the response body was served from the cache. This
    // includes responses for which revalidation was required.
    ///
    int function (_cef_urlrequest_t* self) nothrow response_was_cached;

    ///
    // Cancel the request.
    ///
    void function (_cef_urlrequest_t* self) nothrow cancel;
}

alias cef_urlrequest_t = _cef_urlrequest_t;

///
// Create a new URL request that is not associated with a specific browser or
// frame. Use cef_frame_t::CreateURLRequest instead if you want the request to
// have this association, in which case it may be handled differently (see
// documentation on that function). A request created with this function may
// only originate from the browser process, and will behave as follows:
//   - It may be intercepted by the client via CefResourceRequestHandler or
//     CefSchemeHandlerFactory.
//   - POST data may only contain only a single element of type PDE_TYPE_FILE
//     or PDE_TYPE_BYTES.
//   - If |request_context| is empty the global request context will be used.
//
// The |request| object will be marked as read-only after calling this function.
///
cef_urlrequest_t* cef_urlrequest_create (
    _cef_request_t* request,
    _cef_urlrequest_client_t* client,
    _cef_request_context_t* request_context);

///
// Structure that should be implemented by the cef_urlrequest_t client. The
// functions of this structure will be called on the same thread that created
// the request unless otherwise documented.
///
struct _cef_urlrequest_client_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Notifies the client that the request has completed. Use the
    // cef_urlrequest_t::GetRequestStatus function to determine if the request was
    // successful or not.
    ///
    void function (
        _cef_urlrequest_client_t* self,
        _cef_urlrequest_t* request) nothrow on_request_complete;

    ///
    // Notifies the client of upload progress. |current| denotes the number of
    // bytes sent so far and |total| is the total size of uploading data (or -1 if
    // chunked upload is enabled). This function will only be called if the
    // UR_FLAG_REPORT_UPLOAD_PROGRESS flag is set on the request.
    ///
    void function (
        _cef_urlrequest_client_t* self,
        _cef_urlrequest_t* request,
        int64 current,
        int64 total) nothrow on_upload_progress;

    ///
    // Notifies the client of download progress. |current| denotes the number of
    // bytes received up to the call and |total| is the expected total size of the
    // response (or -1 if not determined).
    ///
    void function (
        _cef_urlrequest_client_t* self,
        _cef_urlrequest_t* request,
        int64 current,
        int64 total) nothrow on_download_progress;

    ///
    // Called when some part of the response is read. |data| contains the current
    // bytes received since the last call. This function will not be called if the
    // UR_FLAG_NO_DOWNLOAD_DATA flag is set on the request.
    ///
    void function (
        _cef_urlrequest_client_t* self,
        _cef_urlrequest_t* request,
        const(void)* data,
        size_t data_length) nothrow on_download_data;

    ///
    // Called on the IO thread when the browser needs credentials from the user.
    // |isProxy| indicates whether the host is a proxy server. |host| contains the
    // hostname and |port| contains the port number. Return true (1) to continue
    // the request and call cef_auth_callback_t::cont() when the authentication
    // information is available. If the request has an associated browser/frame
    // then returning false (0) will result in a call to GetAuthCredentials on the
    // cef_request_handler_t associated with that browser, if any. Otherwise,
    // returning false (0) will cancel the request immediately. This function will
    // only be called for requests initiated from the browser process.
    ///
    int function (
        _cef_urlrequest_client_t* self,
        int isProxy,
        const(cef_string_t)* host,
        int port,
        const(cef_string_t)* realm,
        const(cef_string_t)* scheme,
        _cef_auth_callback_t* callback) nothrow get_auth_credentials;
}

alias cef_urlrequest_client_t = _cef_urlrequest_client_t;

// CEF_INCLUDE_CAPI_CEF_URLREQUEST_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=3bb8f9801a153172981120926c7a5629e08d7131$
//

extern (C):

///
// Structure representing a V8 context handle. V8 handles can only be accessed
// from the thread on which they are created. Valid threads for creating a V8
// handle include the render process main thread (TID_RENDERER) and WebWorker
// threads. A task runner for posting tasks on the associated thread can be
// retrieved via the cef_v8context_t::get_task_runner() function.
///
struct _cef_v8context_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the task runner associated with this context. V8 handles can only
    // be accessed from the thread on which they are created. This function can be
    // called on any render process thread.
    ///
    _cef_task_runner_t* function (_cef_v8context_t* self) nothrow get_task_runner;

    ///
    // Returns true (1) if the underlying handle is valid and it can be accessed
    // on the current thread. Do not call any other functions if this function
    // returns false (0).
    ///
    int function (_cef_v8context_t* self) nothrow is_valid;

    ///
    // Returns the browser for this context. This function will return an NULL
    // reference for WebWorker contexts.
    ///
    _cef_browser_t* function (_cef_v8context_t* self) nothrow get_browser;

    ///
    // Returns the frame for this context. This function will return an NULL
    // reference for WebWorker contexts.
    ///
    _cef_frame_t* function (_cef_v8context_t* self) nothrow get_frame;

    ///
    // Returns the global object for this context. The context must be entered
    // before calling this function.
    ///
    _cef_v8value_t* function (_cef_v8context_t* self) nothrow get_global;

    ///
    // Enter this context. A context must be explicitly entered before creating a
    // V8 Object, Array, Function or Date asynchronously. exit() must be called
    // the same number of times as enter() before releasing this context. V8
    // objects belong to the context in which they are created. Returns true (1)
    // if the scope was entered successfully.
    ///
    int function (_cef_v8context_t* self) nothrow enter;

    ///
    // Exit this context. Call this function only after calling enter(). Returns
    // true (1) if the scope was exited successfully.
    ///
    int function (_cef_v8context_t* self) nothrow exit;

    ///
    // Returns true (1) if this object is pointing to the same handle as |that|
    // object.
    ///
    int function (_cef_v8context_t* self, _cef_v8context_t* that) nothrow is_same;

    ///
    // Execute a string of JavaScript code in this V8 context. The |script_url|
    // parameter is the URL where the script in question can be found, if any. The
    // |start_line| parameter is the base line number to use for error reporting.
    // On success |retval| will be set to the return value, if any, and the
    // function will return true (1). On failure |exception| will be set to the
    // exception, if any, and the function will return false (0).
    ///
    int function (
        _cef_v8context_t* self,
        const(cef_string_t)* code,
        const(cef_string_t)* script_url,
        int start_line,
        _cef_v8value_t** retval,
        _cef_v8exception_t** exception) nothrow eval;
}

alias cef_v8context_t = _cef_v8context_t;

///
// Returns the current (top) context object in the V8 context stack.
///
cef_v8context_t* cef_v8context_get_current_context ();

///
// Returns the entered (bottom) context object in the V8 context stack.
///
cef_v8context_t* cef_v8context_get_entered_context ();

///
// Returns true (1) if V8 is currently inside a context.
///
int cef_v8context_in_context ();

///
// Structure that should be implemented to handle V8 function calls. The
// functions of this structure will be called on the thread associated with the
// V8 function.
///
struct _cef_v8handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Handle execution of the function identified by |name|. |object| is the
    // receiver ('this' object) of the function. |arguments| is the list of
    // arguments passed to the function. If execution succeeds set |retval| to the
    // function return value. If execution fails set |exception| to the exception
    // that will be thrown. Return true (1) if execution was handled.
    ///
    int function (
        _cef_v8handler_t* self,
        const(cef_string_t)* name,
        _cef_v8value_t* object,
        size_t argumentsCount,
        _cef_v8value_t** arguments,
        _cef_v8value_t** retval,
        cef_string_t* exception) nothrow execute;
}

alias cef_v8handler_t = _cef_v8handler_t;

///
// Structure that should be implemented to handle V8 accessor calls. Accessor
// identifiers are registered by calling cef_v8value_t::set_value(). The
// functions of this structure will be called on the thread associated with the
// V8 accessor.
///
struct _cef_v8accessor_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Handle retrieval the accessor value identified by |name|. |object| is the
    // receiver ('this' object) of the accessor. If retrieval succeeds set
    // |retval| to the return value. If retrieval fails set |exception| to the
    // exception that will be thrown. Return true (1) if accessor retrieval was
    // handled.
    ///
    int function (
        _cef_v8accessor_t* self,
        const(cef_string_t)* name,
        _cef_v8value_t* object,
        _cef_v8value_t** retval,
        cef_string_t* exception) nothrow get;

    ///
    // Handle assignment of the accessor value identified by |name|. |object| is
    // the receiver ('this' object) of the accessor. |value| is the new value
    // being assigned to the accessor. If assignment fails set |exception| to the
    // exception that will be thrown. Return true (1) if accessor assignment was
    // handled.
    ///
    int function (
        _cef_v8accessor_t* self,
        const(cef_string_t)* name,
        _cef_v8value_t* object,
        _cef_v8value_t* value,
        cef_string_t* exception) nothrow set;
}

alias cef_v8accessor_t = _cef_v8accessor_t;

///
// Structure that should be implemented to handle V8 interceptor calls. The
// functions of this structure will be called on the thread associated with the
// V8 interceptor. Interceptor's named property handlers (with first argument of
// type CefString) are called when object is indexed by string. Indexed property
// handlers (with first argument of type int) are called when object is indexed
// by integer.
///
struct _cef_v8interceptor_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Handle retrieval of the interceptor value identified by |name|. |object| is
    // the receiver ('this' object) of the interceptor. If retrieval succeeds, set
    // |retval| to the return value. If the requested value does not exist, don't
    // set either |retval| or |exception|. If retrieval fails, set |exception| to
    // the exception that will be thrown. If the property has an associated
    // accessor, it will be called only if you don't set |retval|. Return true (1)
    // if interceptor retrieval was handled, false (0) otherwise.
    ///
    int function (
        _cef_v8interceptor_t* self,
        const(cef_string_t)* name,
        _cef_v8value_t* object,
        _cef_v8value_t** retval,
        cef_string_t* exception) nothrow get_byname;

    ///
    // Handle retrieval of the interceptor value identified by |index|. |object|
    // is the receiver ('this' object) of the interceptor. If retrieval succeeds,
    // set |retval| to the return value. If the requested value does not exist,
    // don't set either |retval| or |exception|. If retrieval fails, set
    // |exception| to the exception that will be thrown. Return true (1) if
    // interceptor retrieval was handled, false (0) otherwise.
    ///
    int function (
        _cef_v8interceptor_t* self,
        int index,
        _cef_v8value_t* object,
        _cef_v8value_t** retval,
        cef_string_t* exception) nothrow get_byindex;

    ///
    // Handle assignment of the interceptor value identified by |name|. |object|
    // is the receiver ('this' object) of the interceptor. |value| is the new
    // value being assigned to the interceptor. If assignment fails, set
    // |exception| to the exception that will be thrown. This setter will always
    // be called, even when the property has an associated accessor. Return true
    // (1) if interceptor assignment was handled, false (0) otherwise.
    ///
    int function (
        _cef_v8interceptor_t* self,
        const(cef_string_t)* name,
        _cef_v8value_t* object,
        _cef_v8value_t* value,
        cef_string_t* exception) nothrow set_byname;

    ///
    // Handle assignment of the interceptor value identified by |index|. |object|
    // is the receiver ('this' object) of the interceptor. |value| is the new
    // value being assigned to the interceptor. If assignment fails, set
    // |exception| to the exception that will be thrown. Return true (1) if
    // interceptor assignment was handled, false (0) otherwise.
    ///
    int function (
        _cef_v8interceptor_t* self,
        int index,
        _cef_v8value_t* object,
        _cef_v8value_t* value,
        cef_string_t* exception) nothrow set_byindex;
}

alias cef_v8interceptor_t = _cef_v8interceptor_t;

///
// Structure representing a V8 exception. The functions of this structure may be
// called on any render process thread.
///
struct _cef_v8exception_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the exception message.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_v8exception_t* self) nothrow get_message;

    ///
    // Returns the line of source code that the exception occurred within.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_v8exception_t* self) nothrow get_source_line;

    ///
    // Returns the resource name for the script from where the function causing
    // the error originates.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_v8exception_t* self) nothrow get_script_resource_name;

    ///
    // Returns the 1-based number of the line where the error occurred or 0 if the
    // line number is unknown.
    ///
    int function (_cef_v8exception_t* self) nothrow get_line_number;

    ///
    // Returns the index within the script of the first character where the error
    // occurred.
    ///
    int function (_cef_v8exception_t* self) nothrow get_start_position;

    ///
    // Returns the index within the script of the last character where the error
    // occurred.
    ///
    int function (_cef_v8exception_t* self) nothrow get_end_position;

    ///
    // Returns the index within the line of the first character where the error
    // occurred.
    ///
    int function (_cef_v8exception_t* self) nothrow get_start_column;

    ///
    // Returns the index within the line of the last character where the error
    // occurred.
    ///
    int function (_cef_v8exception_t* self) nothrow get_end_column;
}

alias cef_v8exception_t = _cef_v8exception_t;

///
// Callback structure that is passed to cef_v8value_t::CreateArrayBuffer.
///
struct _cef_v8array_buffer_release_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called to release |buffer| when the ArrayBuffer JS object is garbage
    // collected. |buffer| is the value that was passed to CreateArrayBuffer along
    // with this object.
    ///
    void function (
        _cef_v8array_buffer_release_callback_t* self,
        void* buffer) nothrow release_buffer;
}

alias cef_v8array_buffer_release_callback_t = _cef_v8array_buffer_release_callback_t;

///
// Structure representing a V8 value handle. V8 handles can only be accessed
// from the thread on which they are created. Valid threads for creating a V8
// handle include the render process main thread (TID_RENDERER) and WebWorker
// threads. A task runner for posting tasks on the associated thread can be
// retrieved via the cef_v8context_t::get_task_runner() function.
///
struct _cef_v8value_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if the underlying handle is valid and it can be accessed
    // on the current thread. Do not call any other functions if this function
    // returns false (0).
    ///
    int function (_cef_v8value_t* self) nothrow is_valid;

    ///
    // True if the value type is undefined.
    ///
    int function (_cef_v8value_t* self) nothrow is_undefined;

    ///
    // True if the value type is null.
    ///
    int function (_cef_v8value_t* self) nothrow is_null;

    ///
    // True if the value type is bool.
    ///
    int function (_cef_v8value_t* self) nothrow is_bool;

    ///
    // True if the value type is int.
    ///
    int function (_cef_v8value_t* self) nothrow is_int;

    ///
    // True if the value type is unsigned int.
    ///
    int function (_cef_v8value_t* self) nothrow is_uint;

    ///
    // True if the value type is double.
    ///
    int function (_cef_v8value_t* self) nothrow is_double;

    ///
    // True if the value type is Date.
    ///
    int function (_cef_v8value_t* self) nothrow is_date;

    ///
    // True if the value type is string.
    ///
    int function (_cef_v8value_t* self) nothrow is_string;

    ///
    // True if the value type is object.
    ///
    int function (_cef_v8value_t* self) nothrow is_object;

    ///
    // True if the value type is array.
    ///
    int function (_cef_v8value_t* self) nothrow is_array;

    ///
    // True if the value type is an ArrayBuffer.
    ///
    int function (_cef_v8value_t* self) nothrow is_array_buffer;

    ///
    // True if the value type is function.
    ///
    int function (_cef_v8value_t* self) nothrow is_function;

    ///
    // Returns true (1) if this object is pointing to the same handle as |that|
    // object.
    ///
    int function (_cef_v8value_t* self, _cef_v8value_t* that) nothrow is_same;

    ///
    // Return a bool value.
    ///
    int function (_cef_v8value_t* self) nothrow get_bool_value;

    ///
    // Return an int value.
    ///
    int32 function (_cef_v8value_t* self) nothrow get_int_value;

    ///
    // Return an unsigned int value.
    ///
    uint32 function (_cef_v8value_t* self) nothrow get_uint_value;

    ///
    // Return a double value.
    ///
    double function (_cef_v8value_t* self) nothrow get_double_value;

    ///
    // Return a Date value.
    ///
    cef_time_t function (_cef_v8value_t* self) nothrow get_date_value;

    ///
    // Return a string value.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_v8value_t* self) nothrow get_string_value;

    // OBJECT METHODS - These functions are only available on objects. Arrays and
    // functions are also objects. String- and integer-based keys can be used
    // interchangably with the framework converting between them as necessary.

    ///
    // Returns true (1) if this is a user created object.
    ///
    int function (_cef_v8value_t* self) nothrow is_user_created;

    ///
    // Returns true (1) if the last function call resulted in an exception. This
    // attribute exists only in the scope of the current CEF value object.
    ///
    int function (_cef_v8value_t* self) nothrow has_exception;

    ///
    // Returns the exception resulting from the last function call. This attribute
    // exists only in the scope of the current CEF value object.
    ///
    _cef_v8exception_t* function (_cef_v8value_t* self) nothrow get_exception;

    ///
    // Clears the last exception and returns true (1) on success.
    ///
    int function (_cef_v8value_t* self) nothrow clear_exception;

    ///
    // Returns true (1) if this object will re-throw future exceptions. This
    // attribute exists only in the scope of the current CEF value object.
    ///
    int function (_cef_v8value_t* self) nothrow will_rethrow_exceptions;

    ///
    // Set whether this object will re-throw future exceptions. By default
    // exceptions are not re-thrown. If a exception is re-thrown the current
    // context should not be accessed again until after the exception has been
    // caught and not re-thrown. Returns true (1) on success. This attribute
    // exists only in the scope of the current CEF value object.
    ///
    int function (_cef_v8value_t* self, int rethrow) nothrow set_rethrow_exceptions;

    ///
    // Returns true (1) if the object has a value with the specified identifier.
    ///
    int function (
        _cef_v8value_t* self,
        const(cef_string_t)* key) nothrow has_value_bykey;

    ///
    // Returns true (1) if the object has a value with the specified identifier.
    ///
    int function (_cef_v8value_t* self, int index) nothrow has_value_byindex;

    ///
    // Deletes the value with the specified identifier and returns true (1) on
    // success. Returns false (0) if this function is called incorrectly or an
    // exception is thrown. For read-only and don't-delete values this function
    // will return true (1) even though deletion failed.
    ///
    int function (
        _cef_v8value_t* self,
        const(cef_string_t)* key) nothrow delete_value_bykey;

    ///
    // Deletes the value with the specified identifier and returns true (1) on
    // success. Returns false (0) if this function is called incorrectly, deletion
    // fails or an exception is thrown. For read-only and don't-delete values this
    // function will return true (1) even though deletion failed.
    ///
    int function (_cef_v8value_t* self, int index) nothrow delete_value_byindex;

    ///
    // Returns the value with the specified identifier on success. Returns NULL if
    // this function is called incorrectly or an exception is thrown.
    ///
    _cef_v8value_t* function (
        _cef_v8value_t* self,
        const(cef_string_t)* key) nothrow get_value_bykey;

    ///
    // Returns the value with the specified identifier on success. Returns NULL if
    // this function is called incorrectly or an exception is thrown.
    ///
    _cef_v8value_t* function (
        _cef_v8value_t* self,
        int index) nothrow get_value_byindex;

    ///
    // Associates a value with the specified identifier and returns true (1) on
    // success. Returns false (0) if this function is called incorrectly or an
    // exception is thrown. For read-only values this function will return true
    // (1) even though assignment failed.
    ///
    int function (
        _cef_v8value_t* self,
        const(cef_string_t)* key,
        _cef_v8value_t* value,
        cef_v8_propertyattribute_t attribute) nothrow set_value_bykey;

    ///
    // Associates a value with the specified identifier and returns true (1) on
    // success. Returns false (0) if this function is called incorrectly or an
    // exception is thrown. For read-only values this function will return true
    // (1) even though assignment failed.
    ///
    int function (
        _cef_v8value_t* self,
        int index,
        _cef_v8value_t* value) nothrow set_value_byindex;

    ///
    // Registers an identifier and returns true (1) on success. Access to the
    // identifier will be forwarded to the cef_v8accessor_t instance passed to
    // cef_v8value_t::cef_v8value_create_object(). Returns false (0) if this
    // function is called incorrectly or an exception is thrown. For read-only
    // values this function will return true (1) even though assignment failed.
    ///
    int function (
        _cef_v8value_t* self,
        const(cef_string_t)* key,
        cef_v8_accesscontrol_t settings,
        cef_v8_propertyattribute_t attribute) nothrow set_value_byaccessor;

    ///
    // Read the keys for the object's values into the specified vector. Integer-
    // based keys will also be returned as strings.
    ///
    int function (_cef_v8value_t* self, cef_string_list_t keys) nothrow get_keys;

    ///
    // Sets the user data for this object and returns true (1) on success. Returns
    // false (0) if this function is called incorrectly. This function can only be
    // called on user created objects.
    ///
    int function (
        _cef_v8value_t* self,
        _cef_base_ref_counted_t* user_data) nothrow set_user_data;

    ///
    // Returns the user data, if any, assigned to this object.
    ///
    _cef_base_ref_counted_t* function (_cef_v8value_t* self) nothrow get_user_data;

    ///
    // Returns the amount of externally allocated memory registered for the
    // object.
    ///
    int function (_cef_v8value_t* self) nothrow get_externally_allocated_memory;

    ///
    // Adjusts the amount of registered external memory for the object. Used to
    // give V8 an indication of the amount of externally allocated memory that is
    // kept alive by JavaScript objects. V8 uses this information to decide when
    // to perform global garbage collection. Each cef_v8value_t tracks the amount
    // of external memory associated with it and automatically decreases the
    // global total by the appropriate amount on its destruction.
    // |change_in_bytes| specifies the number of bytes to adjust by. This function
    // returns the number of bytes associated with the object after the
    // adjustment. This function can only be called on user created objects.
    ///
    int function (
        _cef_v8value_t* self,
        int change_in_bytes) nothrow adjust_externally_allocated_memory;

    // ARRAY METHODS - These functions are only available on arrays.

    ///
    // Returns the number of elements in the array.
    ///
    int function (_cef_v8value_t* self) nothrow get_array_length;

    // ARRAY BUFFER METHODS - These functions are only available on ArrayBuffers.

    ///
    // Returns the ReleaseCallback object associated with the ArrayBuffer or NULL
    // if the ArrayBuffer was not created with CreateArrayBuffer.
    ///
    _cef_v8array_buffer_release_callback_t* function (
        _cef_v8value_t* self) nothrow get_array_buffer_release_callback;

    ///
    // Prevent the ArrayBuffer from using it's memory block by setting the length
    // to zero. This operation cannot be undone. If the ArrayBuffer was created
    // with CreateArrayBuffer then
    // cef_v8array_buffer_release_callback_t::ReleaseBuffer will be called to
    // release the underlying buffer.
    ///
    int function (_cef_v8value_t* self) nothrow neuter_array_buffer;

    // FUNCTION METHODS - These functions are only available on functions.

    ///
    // Returns the function name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_v8value_t* self) nothrow get_function_name;

    ///
    // Returns the function handler or NULL if not a CEF-created function.
    ///
    _cef_v8handler_t* function (_cef_v8value_t* self) nothrow get_function_handler;

    ///
    // Execute the function using the current V8 context. This function should
    // only be called from within the scope of a cef_v8handler_t or
    // cef_v8accessor_t callback, or in combination with calling enter() and
    // exit() on a stored cef_v8context_t reference. |object| is the receiver
    // ('this' object) of the function. If |object| is NULL the current context's
    // global object will be used. |arguments| is the list of arguments that will
    // be passed to the function. Returns the function return value on success.
    // Returns NULL if this function is called incorrectly or an exception is
    // thrown.
    ///
    _cef_v8value_t* function (
        _cef_v8value_t* self,
        _cef_v8value_t* object,
        size_t argumentsCount,
        _cef_v8value_t** arguments) nothrow execute_function;

    ///
    // Execute the function using the specified V8 context. |object| is the
    // receiver ('this' object) of the function. If |object| is NULL the specified
    // context's global object will be used. |arguments| is the list of arguments
    // that will be passed to the function. Returns the function return value on
    // success. Returns NULL if this function is called incorrectly or an
    // exception is thrown.
    ///
    _cef_v8value_t* function (
        _cef_v8value_t* self,
        _cef_v8context_t* context,
        _cef_v8value_t* object,
        size_t argumentsCount,
        _cef_v8value_t** arguments) nothrow execute_function_with_context;
}

alias cef_v8value_t = _cef_v8value_t;

///
// Create a new cef_v8value_t object of type undefined.
///
cef_v8value_t* cef_v8value_create_undefined ();

///
// Create a new cef_v8value_t object of type null.
///
cef_v8value_t* cef_v8value_create_null ();

///
// Create a new cef_v8value_t object of type bool.
///
cef_v8value_t* cef_v8value_create_bool (int value);

///
// Create a new cef_v8value_t object of type int.
///
cef_v8value_t* cef_v8value_create_int (int32 value);

///
// Create a new cef_v8value_t object of type unsigned int.
///
cef_v8value_t* cef_v8value_create_uint (uint32 value);

///
// Create a new cef_v8value_t object of type double.
///
cef_v8value_t* cef_v8value_create_double (double value);

///
// Create a new cef_v8value_t object of type Date. This function should only be
// called from within the scope of a cef_render_process_handler_t,
// cef_v8handler_t or cef_v8accessor_t callback, or in combination with calling
// enter() and exit() on a stored cef_v8context_t reference.
///
cef_v8value_t* cef_v8value_create_date (const(cef_time_t)* date);

///
// Create a new cef_v8value_t object of type string.
///
cef_v8value_t* cef_v8value_create_string (const(cef_string_t)* value);

///
// Create a new cef_v8value_t object of type object with optional accessor
// and/or interceptor. This function should only be called from within the scope
// of a cef_render_process_handler_t, cef_v8handler_t or cef_v8accessor_t
// callback, or in combination with calling enter() and exit() on a stored
// cef_v8context_t reference.
///
cef_v8value_t* cef_v8value_create_object (
    cef_v8accessor_t* accessor,
    cef_v8interceptor_t* interceptor);

///
// Create a new cef_v8value_t object of type array with the specified |length|.
// If |length| is negative the returned array will have length 0. This function
// should only be called from within the scope of a
// cef_render_process_handler_t, cef_v8handler_t or cef_v8accessor_t callback,
// or in combination with calling enter() and exit() on a stored cef_v8context_t
// reference.
///
cef_v8value_t* cef_v8value_create_array (int length);

///
// Create a new cef_v8value_t object of type ArrayBuffer which wraps the
// provided |buffer| of size |length| bytes. The ArrayBuffer is externalized,
// meaning that it does not own |buffer|. The caller is responsible for freeing
// |buffer| when requested via a call to cef_v8array_buffer_release_callback_t::
// ReleaseBuffer. This function should only be called from within the scope of a
// cef_render_process_handler_t, cef_v8handler_t or cef_v8accessor_t callback,
// or in combination with calling enter() and exit() on a stored cef_v8context_t
// reference.
///
cef_v8value_t* cef_v8value_create_array_buffer (
    void* buffer,
    size_t length,
    cef_v8array_buffer_release_callback_t* release_callback);

///
// Create a new cef_v8value_t object of type function. This function should only
// be called from within the scope of a cef_render_process_handler_t,
// cef_v8handler_t or cef_v8accessor_t callback, or in combination with calling
// enter() and exit() on a stored cef_v8context_t reference.
///
cef_v8value_t* cef_v8value_create_function (
    const(cef_string_t)* name,
    cef_v8handler_t* handler) nothrow;

///
// Structure representing a V8 stack trace handle. V8 handles can only be
// accessed from the thread on which they are created. Valid threads for
// creating a V8 handle include the render process main thread (TID_RENDERER)
// and WebWorker threads. A task runner for posting tasks on the associated
// thread can be retrieved via the cef_v8context_t::get_task_runner() function.
///
struct _cef_v8stack_trace_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if the underlying handle is valid and it can be accessed
    // on the current thread. Do not call any other functions if this function
    // returns false (0).
    ///
    int function (_cef_v8stack_trace_t* self) nothrow is_valid;

    ///
    // Returns the number of stack frames.
    ///
    int function (_cef_v8stack_trace_t* self) nothrow get_frame_count;

    ///
    // Returns the stack frame at the specified 0-based index.
    ///
    _cef_v8stack_frame_t* function (
        _cef_v8stack_trace_t* self,
        int index) nothrow get_frame;
}

alias cef_v8stack_trace_t = _cef_v8stack_trace_t;

///
// Returns the stack trace for the currently active context. |frame_limit| is
// the maximum number of frames that will be captured.
///
cef_v8stack_trace_t* cef_v8stack_trace_get_current (int frame_limit);

///
// Structure representing a V8 stack frame handle. V8 handles can only be
// accessed from the thread on which they are created. Valid threads for
// creating a V8 handle include the render process main thread (TID_RENDERER)
// and WebWorker threads. A task runner for posting tasks on the associated
// thread can be retrieved via the cef_v8context_t::get_task_runner() function.
///
struct _cef_v8stack_frame_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if the underlying handle is valid and it can be accessed
    // on the current thread. Do not call any other functions if this function
    // returns false (0).
    ///
    int function (_cef_v8stack_frame_t* self) nothrow is_valid;

    ///
    // Returns the name of the resource script that contains the function.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_v8stack_frame_t* self) nothrow get_script_name;

    ///
    // Returns the name of the resource script that contains the function or the
    // sourceURL value if the script name is undefined and its source ends with a
    // "//@ sourceURL=..." string.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_v8stack_frame_t* self) nothrow get_script_name_or_source_url;

    ///
    // Returns the name of the function.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_v8stack_frame_t* self) nothrow get_function_name;

    ///
    // Returns the 1-based line number for the function call or 0 if unknown.
    ///
    int function (_cef_v8stack_frame_t* self) nothrow get_line_number;

    ///
    // Returns the 1-based column offset on the line for the function call or 0 if
    // unknown.
    ///
    int function (_cef_v8stack_frame_t* self) nothrow get_column;

    ///
    // Returns true (1) if the function was compiled using eval().
    ///
    int function (_cef_v8stack_frame_t* self) nothrow is_eval;

    ///
    // Returns true (1) if the function was called as a constructor via "new".
    ///
    int function (_cef_v8stack_frame_t* self) nothrow is_constructor;
}

alias cef_v8stack_frame_t = _cef_v8stack_frame_t;

///
// Register a new V8 extension with the specified JavaScript extension code and
// handler. Functions implemented by the handler are prototyped using the
// keyword 'native'. The calling of a native function is restricted to the scope
// in which the prototype of the native function is defined. This function may
// only be called on the render process main thread.
//
// Example JavaScript extension code: <pre>
//   // create the 'example' global object if it doesn't already exist.
//   if (!example)
//     example = {};
//   // create the 'example.test' global object if it doesn't already exist.
//   if (!example.test)
//     example.test = {};
//   (function() {
//     // Define the function 'example.test.myfunction'.
//     example.test.myfunction = function() {
//       // Call CefV8Handler::Execute() with the function name 'MyFunction'
//       // and no arguments.
//       native function MyFunction();
//       return MyFunction();
//     };
//     // Define the getter function for parameter 'example.test.myparam'.
//     example.test.__defineGetter__('myparam', function() {
//       // Call CefV8Handler::Execute() with the function name 'GetMyParam'
//       // and no arguments.
//       native function GetMyParam();
//       return GetMyParam();
//     });
//     // Define the setter function for parameter 'example.test.myparam'.
//     example.test.__defineSetter__('myparam', function(b) {
//       // Call CefV8Handler::Execute() with the function name 'SetMyParam'
//       // and a single argument.
//       native function SetMyParam();
//       if(b) SetMyParam(b);
//     });
//
//     // Extension definitions can also contain normal JavaScript variables
//     // and functions.
//     var myint = 0;
//     example.test.increment = function() {
//       myint += 1;
//       return myint;
//     };
//   })();
// </pre> Example usage in the page: <pre>
//   // Call the function.
//   example.test.myfunction();
//   // Set the parameter.
//   example.test.myparam = value;
//   // Get the parameter.
//   value = example.test.myparam;
//   // Call another function.
//   example.test.increment();
// </pre>
///
int cef_register_extension (
    const(cef_string_t)* extension_name,
    const(cef_string_t)* javascript_code,
    cef_v8handler_t* handler);

// CEF_INCLUDE_CAPI_CEF_V8_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=22f935968cd7f2549def42f5d84694311bde125e$
//

extern (C):

///
// Structure that wraps other data value types. Complex types (binary,
// dictionary and list) will be referenced but not owned by this object. Can be
// used on any process and thread.
///
struct _cef_value_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if the underlying data is valid. This will always be true
    // (1) for simple types. For complex types (binary, dictionary and list) the
    // underlying data may become invalid if owned by another object (e.g. list or
    // dictionary) and that other object is then modified or destroyed. This value
    // object can be re-used by calling Set*() even if the underlying data is
    // invalid.
    ///
    int function (_cef_value_t* self) nothrow is_valid;

    ///
    // Returns true (1) if the underlying data is owned by another object.
    ///
    int function (_cef_value_t* self) nothrow is_owned;

    ///
    // Returns true (1) if the underlying data is read-only. Some APIs may expose
    // read-only objects.
    ///
    int function (_cef_value_t* self) nothrow is_read_only;

    ///
    // Returns true (1) if this object and |that| object have the same underlying
    // data. If true (1) modifications to this object will also affect |that|
    // object and vice-versa.
    ///
    int function (_cef_value_t* self, _cef_value_t* that) nothrow is_same;

    ///
    // Returns true (1) if this object and |that| object have an equivalent
    // underlying value but are not necessarily the same object.
    ///
    int function (_cef_value_t* self, _cef_value_t* that) nothrow is_equal;

    ///
    // Returns a copy of this object. The underlying data will also be copied.
    ///
    _cef_value_t* function (_cef_value_t* self) nothrow copy;

    ///
    // Returns the underlying value type.
    ///
    cef_value_type_t function (_cef_value_t* self) nothrow get_type;

    ///
    // Returns the underlying value as type bool.
    ///
    int function (_cef_value_t* self) nothrow get_bool;

    ///
    // Returns the underlying value as type int.
    ///
    int function (_cef_value_t* self) nothrow get_int;

    ///
    // Returns the underlying value as type double.
    ///
    double function (_cef_value_t* self) nothrow get_double;

    ///
    // Returns the underlying value as type string.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_value_t* self) nothrow get_string;

    ///
    // Returns the underlying value as type binary. The returned reference may
    // become invalid if the value is owned by another object or if ownership is
    // transferred to another object in the future. To maintain a reference to the
    // value after assigning ownership to a dictionary or list pass this object to
    // the set_value() function instead of passing the returned reference to
    // set_binary().
    ///
    _cef_binary_value_t* function (_cef_value_t* self) nothrow get_binary;

    ///
    // Returns the underlying value as type dictionary. The returned reference may
    // become invalid if the value is owned by another object or if ownership is
    // transferred to another object in the future. To maintain a reference to the
    // value after assigning ownership to a dictionary or list pass this object to
    // the set_value() function instead of passing the returned reference to
    // set_dictionary().
    ///
    _cef_dictionary_value_t* function (_cef_value_t* self) nothrow get_dictionary;

    ///
    // Returns the underlying value as type list. The returned reference may
    // become invalid if the value is owned by another object or if ownership is
    // transferred to another object in the future. To maintain a reference to the
    // value after assigning ownership to a dictionary or list pass this object to
    // the set_value() function instead of passing the returned reference to
    // set_list().
    ///
    _cef_list_value_t* function (_cef_value_t* self) nothrow get_list;

    ///
    // Sets the underlying value as type null. Returns true (1) if the value was
    // set successfully.
    ///
    int function (_cef_value_t* self) nothrow set_null;

    ///
    // Sets the underlying value as type bool. Returns true (1) if the value was
    // set successfully.
    ///
    int function (_cef_value_t* self, int value) nothrow set_bool;

    ///
    // Sets the underlying value as type int. Returns true (1) if the value was
    // set successfully.
    ///
    int function (_cef_value_t* self, int value) nothrow set_int;

    ///
    // Sets the underlying value as type double. Returns true (1) if the value was
    // set successfully.
    ///
    int function (_cef_value_t* self, double value) nothrow set_double;

    ///
    // Sets the underlying value as type string. Returns true (1) if the value was
    // set successfully.
    ///
    int function (_cef_value_t* self, const(cef_string_t)* value) nothrow set_string;

    ///
    // Sets the underlying value as type binary. Returns true (1) if the value was
    // set successfully. This object keeps a reference to |value| and ownership of
    // the underlying data remains unchanged.
    ///
    int function (_cef_value_t* self, _cef_binary_value_t* value) nothrow set_binary;

    ///
    // Sets the underlying value as type dict. Returns true (1) if the value was
    // set successfully. This object keeps a reference to |value| and ownership of
    // the underlying data remains unchanged.
    ///
    int function (
        _cef_value_t* self,
        _cef_dictionary_value_t* value) nothrow set_dictionary;

    ///
    // Sets the underlying value as type list. Returns true (1) if the value was
    // set successfully. This object keeps a reference to |value| and ownership of
    // the underlying data remains unchanged.
    ///
    int function (_cef_value_t* self, _cef_list_value_t* value) nothrow set_list;
}

alias cef_value_t = _cef_value_t;

///
// Creates a new object.
///
cef_value_t* cef_value_create ();

///
// Structure representing a binary value. Can be used on any process and thread.
///
struct _cef_binary_value_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. This object may become invalid if
    // the underlying data is owned by another object (e.g. list or dictionary)
    // and that other object is then modified or destroyed. Do not call any other
    // functions if this function returns false (0).
    ///
    int function (_cef_binary_value_t* self) nothrow is_valid;

    ///
    // Returns true (1) if this object is currently owned by another object.
    ///
    int function (_cef_binary_value_t* self) nothrow is_owned;

    ///
    // Returns true (1) if this object and |that| object have the same underlying
    // data.
    ///
    int function (
        _cef_binary_value_t* self,
        _cef_binary_value_t* that) nothrow is_same;

    ///
    // Returns true (1) if this object and |that| object have an equivalent
    // underlying value but are not necessarily the same object.
    ///
    int function (
        _cef_binary_value_t* self,
        _cef_binary_value_t* that) nothrow is_equal;

    ///
    // Returns a copy of this object. The data in this object will also be copied.
    ///
    _cef_binary_value_t* function (_cef_binary_value_t* self) nothrow copy;

    ///
    // Returns the data size.
    ///
    size_t function (_cef_binary_value_t* self) nothrow get_size;

    ///
    // Read up to |buffer_size| number of bytes into |buffer|. Reading begins at
    // the specified byte |data_offset|. Returns the number of bytes read.
    ///
    size_t function (
        _cef_binary_value_t* self,
        void* buffer,
        size_t buffer_size,
        size_t data_offset) nothrow get_data;
}

alias cef_binary_value_t = _cef_binary_value_t;

///
// Creates a new object that is not owned by any other object. The specified
// |data| will be copied.
///
cef_binary_value_t* cef_binary_value_create (
    const(void)* data,
    size_t data_size);

///
// Structure representing a dictionary value. Can be used on any process and
// thread.
///
struct _cef_dictionary_value_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. This object may become invalid if
    // the underlying data is owned by another object (e.g. list or dictionary)
    // and that other object is then modified or destroyed. Do not call any other
    // functions if this function returns false (0).
    ///
    int function (_cef_dictionary_value_t* self) nothrow is_valid;

    ///
    // Returns true (1) if this object is currently owned by another object.
    ///
    int function (_cef_dictionary_value_t* self) nothrow is_owned;

    ///
    // Returns true (1) if the values of this object are read-only. Some APIs may
    // expose read-only objects.
    ///
    int function (_cef_dictionary_value_t* self) nothrow is_read_only;

    ///
    // Returns true (1) if this object and |that| object have the same underlying
    // data. If true (1) modifications to this object will also affect |that|
    // object and vice-versa.
    ///
    int function (
        _cef_dictionary_value_t* self,
        _cef_dictionary_value_t* that) nothrow is_same;

    ///
    // Returns true (1) if this object and |that| object have an equivalent
    // underlying value but are not necessarily the same object.
    ///
    int function (
        _cef_dictionary_value_t* self,
        _cef_dictionary_value_t* that) nothrow is_equal;

    ///
    // Returns a writable copy of this object. If |exclude_NULL_children| is true
    // (1) any NULL dictionaries or lists will be excluded from the copy.
    ///
    _cef_dictionary_value_t* function (
        _cef_dictionary_value_t* self,
        int exclude_empty_children) nothrow copy;

    ///
    // Returns the number of values.
    ///
    size_t function (_cef_dictionary_value_t* self) nothrow get_size;

    ///
    // Removes all values. Returns true (1) on success.
    ///
    int function (_cef_dictionary_value_t* self) nothrow clear;

    ///
    // Returns true (1) if the current dictionary has a value for the given key.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow has_key;

    ///
    // Reads all keys for this dictionary into the specified vector.
    ///
    int function (
        _cef_dictionary_value_t* self,
        cef_string_list_t keys) nothrow get_keys;

    ///
    // Removes the value at the specified key. Returns true (1) is the value was
    // removed successfully.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow remove;

    ///
    // Returns the value type for the specified key.
    ///
    cef_value_type_t function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_type;

    ///
    // Returns the value at the specified key. For simple types the returned value
    // will copy existing data and modifications to the value will not modify this
    // object. For complex types (binary, dictionary and list) the returned value
    // will reference existing data and modifications to the value will modify
    // this object.
    ///
    _cef_value_t* function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_value;

    ///
    // Returns the value at the specified key as type bool.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_bool;

    ///
    // Returns the value at the specified key as type int.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_int;

    ///
    // Returns the value at the specified key as type double.
    ///
    double function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_double;

    ///
    // Returns the value at the specified key as type string.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_string;

    ///
    // Returns the value at the specified key as type binary. The returned value
    // will reference existing data.
    ///
    _cef_binary_value_t* function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_binary;

    ///
    // Returns the value at the specified key as type dictionary. The returned
    // value will reference existing data and modifications to the value will
    // modify this object.
    ///
    _cef_dictionary_value_t* function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_dictionary;

    ///
    // Returns the value at the specified key as type list. The returned value
    // will reference existing data and modifications to the value will modify
    // this object.
    ///
    _cef_list_value_t* function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow get_list;

    ///
    // Sets the value at the specified key. Returns true (1) if the value was set
    // successfully. If |value| represents simple data then the underlying data
    // will be copied and modifications to |value| will not modify this object. If
    // |value| represents complex data (binary, dictionary or list) then the
    // underlying data will be referenced and modifications to |value| will modify
    // this object.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        _cef_value_t* value) nothrow set_value;

    ///
    // Sets the value at the specified key as type null. Returns true (1) if the
    // value was set successfully.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key) nothrow set_null;

    ///
    // Sets the value at the specified key as type bool. Returns true (1) if the
    // value was set successfully.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        int value) nothrow set_bool;

    ///
    // Sets the value at the specified key as type int. Returns true (1) if the
    // value was set successfully.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        int value) nothrow set_int;

    ///
    // Sets the value at the specified key as type double. Returns true (1) if the
    // value was set successfully.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        double value) nothrow set_double;

    ///
    // Sets the value at the specified key as type string. Returns true (1) if the
    // value was set successfully.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        const(cef_string_t)* value) nothrow set_string;

    ///
    // Sets the value at the specified key as type binary. Returns true (1) if the
    // value was set successfully. If |value| is currently owned by another object
    // then the value will be copied and the |value| reference will not change.
    // Otherwise, ownership will be transferred to this object and the |value|
    // reference will be invalidated.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        _cef_binary_value_t* value) nothrow set_binary;

    ///
    // Sets the value at the specified key as type dict. Returns true (1) if the
    // value was set successfully. If |value| is currently owned by another object
    // then the value will be copied and the |value| reference will not change.
    // Otherwise, ownership will be transferred to this object and the |value|
    // reference will be invalidated.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        _cef_dictionary_value_t* value) nothrow set_dictionary;

    ///
    // Sets the value at the specified key as type list. Returns true (1) if the
    // value was set successfully. If |value| is currently owned by another object
    // then the value will be copied and the |value| reference will not change.
    // Otherwise, ownership will be transferred to this object and the |value|
    // reference will be invalidated.
    ///
    int function (
        _cef_dictionary_value_t* self,
        const(cef_string_t)* key,
        _cef_list_value_t* value) nothrow set_list;
}

alias cef_dictionary_value_t = _cef_dictionary_value_t;

///
// Creates a new object that is not owned by any other object.
///
cef_dictionary_value_t* cef_dictionary_value_create ();

///
// Structure representing a list value. Can be used on any process and thread.
///
struct _cef_list_value_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is valid. This object may become invalid if
    // the underlying data is owned by another object (e.g. list or dictionary)
    // and that other object is then modified or destroyed. Do not call any other
    // functions if this function returns false (0).
    ///
    int function (_cef_list_value_t* self) nothrow is_valid;

    ///
    // Returns true (1) if this object is currently owned by another object.
    ///
    int function (_cef_list_value_t* self) nothrow is_owned;

    ///
    // Returns true (1) if the values of this object are read-only. Some APIs may
    // expose read-only objects.
    ///
    int function (_cef_list_value_t* self) nothrow is_read_only;

    ///
    // Returns true (1) if this object and |that| object have the same underlying
    // data. If true (1) modifications to this object will also affect |that|
    // object and vice-versa.
    ///
    int function (_cef_list_value_t* self, _cef_list_value_t* that) nothrow is_same;

    ///
    // Returns true (1) if this object and |that| object have an equivalent
    // underlying value but are not necessarily the same object.
    ///
    int function (_cef_list_value_t* self, _cef_list_value_t* that) nothrow is_equal;

    ///
    // Returns a writable copy of this object.
    ///
    _cef_list_value_t* function (_cef_list_value_t* self) nothrow copy;

    ///
    // Sets the number of values. If the number of values is expanded all new
    // value slots will default to type null. Returns true (1) on success.
    ///
    int function (_cef_list_value_t* self, size_t size) nothrow set_size;

    ///
    // Returns the number of values.
    ///
    size_t function (_cef_list_value_t* self) nothrow get_size;

    ///
    // Removes all values. Returns true (1) on success.
    ///
    int function (_cef_list_value_t* self) nothrow clear;

    ///
    // Removes the value at the specified index.
    ///
    int function (_cef_list_value_t* self, size_t index) nothrow remove;

    ///
    // Returns the value type at the specified index.
    ///
    cef_value_type_t function (_cef_list_value_t* self, size_t index) nothrow get_type;

    ///
    // Returns the value at the specified index. For simple types the returned
    // value will copy existing data and modifications to the value will not
    // modify this object. For complex types (binary, dictionary and list) the
    // returned value will reference existing data and modifications to the value
    // will modify this object.
    ///
    _cef_value_t* function (_cef_list_value_t* self, size_t index) nothrow get_value;

    ///
    // Returns the value at the specified index as type bool.
    ///
    int function (_cef_list_value_t* self, size_t index) nothrow get_bool;

    ///
    // Returns the value at the specified index as type int.
    ///
    int function (_cef_list_value_t* self, size_t index) nothrow get_int;

    ///
    // Returns the value at the specified index as type double.
    ///
    double function (_cef_list_value_t* self, size_t index) nothrow get_double;

    ///
    // Returns the value at the specified index as type string.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_list_value_t* self,
        size_t index) nothrow get_string;

    ///
    // Returns the value at the specified index as type binary. The returned value
    // will reference existing data.
    ///
    _cef_binary_value_t* function (
        _cef_list_value_t* self,
        size_t index) nothrow get_binary;

    ///
    // Returns the value at the specified index as type dictionary. The returned
    // value will reference existing data and modifications to the value will
    // modify this object.
    ///
    _cef_dictionary_value_t* function (
        _cef_list_value_t* self,
        size_t index) nothrow get_dictionary;

    ///
    // Returns the value at the specified index as type list. The returned value
    // will reference existing data and modifications to the value will modify
    // this object.
    ///
    _cef_list_value_t* function (
        _cef_list_value_t* self,
        size_t index) nothrow get_list;

    ///
    // Sets the value at the specified index. Returns true (1) if the value was
    // set successfully. If |value| represents simple data then the underlying
    // data will be copied and modifications to |value| will not modify this
    // object. If |value| represents complex data (binary, dictionary or list)
    // then the underlying data will be referenced and modifications to |value|
    // will modify this object.
    ///
    int function (
        _cef_list_value_t* self,
        size_t index,
        _cef_value_t* value) nothrow set_value;

    ///
    // Sets the value at the specified index as type null. Returns true (1) if the
    // value was set successfully.
    ///
    int function (_cef_list_value_t* self, size_t index) nothrow set_null;

    ///
    // Sets the value at the specified index as type bool. Returns true (1) if the
    // value was set successfully.
    ///
    int function (_cef_list_value_t* self, size_t index, int value) nothrow set_bool;

    ///
    // Sets the value at the specified index as type int. Returns true (1) if the
    // value was set successfully.
    ///
    int function (_cef_list_value_t* self, size_t index, int value) nothrow set_int;

    ///
    // Sets the value at the specified index as type double. Returns true (1) if
    // the value was set successfully.
    ///
    int function (
        _cef_list_value_t* self,
        size_t index,
        double value) nothrow set_double;

    ///
    // Sets the value at the specified index as type string. Returns true (1) if
    // the value was set successfully.
    ///
    int function (
        _cef_list_value_t* self,
        size_t index,
        const(cef_string_t)* value) nothrow set_string;

    ///
    // Sets the value at the specified index as type binary. Returns true (1) if
    // the value was set successfully. If |value| is currently owned by another
    // object then the value will be copied and the |value| reference will not
    // change. Otherwise, ownership will be transferred to this object and the
    // |value| reference will be invalidated.
    ///
    int function (
        _cef_list_value_t* self,
        size_t index,
        _cef_binary_value_t* value) nothrow set_binary;

    ///
    // Sets the value at the specified index as type dict. Returns true (1) if the
    // value was set successfully. If |value| is currently owned by another object
    // then the value will be copied and the |value| reference will not change.
    // Otherwise, ownership will be transferred to this object and the |value|
    // reference will be invalidated.
    ///
    int function (
        _cef_list_value_t* self,
        size_t index,
        _cef_dictionary_value_t* value) nothrow set_dictionary;

    ///
    // Sets the value at the specified index as type list. Returns true (1) if the
    // value was set successfully. If |value| is currently owned by another object
    // then the value will be copied and the |value| reference will not change.
    // Otherwise, ownership will be transferred to this object and the |value|
    // reference will be invalidated.
    ///
    int function (
        _cef_list_value_t* self,
        size_t index,
        _cef_list_value_t* value) nothrow set_list;
}

alias cef_list_value_t = _cef_list_value_t;

///
// Creates a new object that is not owned by any other object.
///
cef_list_value_t* cef_list_value_create ();

// CEF_INCLUDE_CAPI_CEF_VALUES_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=aedfa5758cbf37dff244c065d55d273231470877$
//

extern (C):

///
// WaitableEvent is a thread synchronization tool that allows one thread to wait
// for another thread to finish some work. This is equivalent to using a
// Lock+ConditionVariable to protect a simple boolean value. However, using
// WaitableEvent in conjunction with a Lock to wait for a more complex state
// change (e.g., for an item to be added to a queue) is not recommended. In that
// case consider using a ConditionVariable instead of a WaitableEvent. It is
// safe to create and/or signal a WaitableEvent from any thread. Blocking on a
// WaitableEvent by calling the *wait() functions is not allowed on the browser
// process UI or IO threads.
///
struct _cef_waitable_event_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Put the event in the un-signaled state.
    ///
    void function (_cef_waitable_event_t* self) nothrow reset;

    ///
    // Put the event in the signaled state. This causes any thread blocked on Wait
    // to be woken up.
    ///
    void function (_cef_waitable_event_t* self) nothrow signal;

    ///
    // Returns true (1) if the event is in the signaled state, else false (0). If
    // the event was created with |automatic_reset| set to true (1) then calling
    // this function will also cause a reset.
    ///
    int function (_cef_waitable_event_t* self) nothrow is_signaled;

    ///
    // Wait indefinitely for the event to be signaled. This function will not
    // return until after the call to signal() has completed. This function cannot
    // be called on the browser process UI or IO threads.
    ///
    void function (_cef_waitable_event_t* self) nothrow wait;

    ///
    // Wait up to |max_ms| milliseconds for the event to be signaled. Returns true
    // (1) if the event was signaled. A return value of false (0) does not
    // necessarily mean that |max_ms| was exceeded. This function will not return
    // until after the call to signal() has completed. This function cannot be
    // called on the browser process UI or IO threads.
    ///
    int function (_cef_waitable_event_t* self, int64 max_ms) nothrow timed_wait;
}

alias cef_waitable_event_t = _cef_waitable_event_t;

///
// Create a new waitable event. If |automatic_reset| is true (1) then the event
// state is automatically reset to un-signaled after a single waiting thread has
// been released; otherwise, the state remains signaled until reset() is called
// manually. If |initially_signaled| is true (1) then the event will start in
// the signaled state.
///
cef_waitable_event_t* cef_waitable_event_create (
    int automatic_reset,
    int initially_signaled);

// CEF_INCLUDE_CAPI_CEF_WAITABLE_EVENT_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=f1b2b6203d45fdf76d72ea1e79fcef0bb2a26138$
//

extern (C):

///
// Information about a specific web plugin.
///
struct _cef_web_plugin_info_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the plugin name (i.e. Flash).
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_web_plugin_info_t* self) nothrow get_name;

    ///
    // Returns the plugin file path (DLL/bundle/library).
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_web_plugin_info_t* self) nothrow get_path;

    ///
    // Returns the version of the plugin (may be OS-specific).
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_web_plugin_info_t* self) nothrow get_version;

    ///
    // Returns a description of the plugin from the version information.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_web_plugin_info_t* self) nothrow get_description;
}

alias cef_web_plugin_info_t = _cef_web_plugin_info_t;

///
// Structure to implement for visiting web plugin information. The functions of
// this structure will be called on the browser process UI thread.
///
struct _cef_web_plugin_info_visitor_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called once for each plugin. |count| is the 0-based
    // index for the current plugin. |total| is the total number of plugins.
    // Return false (0) to stop visiting plugins. This function may never be
    // called if no plugins are found.
    ///
    int function (
        _cef_web_plugin_info_visitor_t* self,
        _cef_web_plugin_info_t* info,
        int count,
        int total) nothrow visit;
}

alias cef_web_plugin_info_visitor_t = _cef_web_plugin_info_visitor_t;

///
// Structure to implement for receiving unstable plugin information. The
// functions of this structure will be called on the browser process IO thread.
///
struct _cef_web_plugin_unstable_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called for the requested plugin. |unstable| will be
    // true (1) if the plugin has reached the crash count threshold of 3 times in
    // 120 seconds.
    ///
    void function (
        _cef_web_plugin_unstable_callback_t* self,
        const(cef_string_t)* path,
        int unstable) nothrow is_unstable;
}

alias cef_web_plugin_unstable_callback_t = _cef_web_plugin_unstable_callback_t;

///
// Implement this structure to receive notification when CDM registration is
// complete. The functions of this structure will be called on the browser
// process UI thread.
///
struct _cef_register_cdm_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Method that will be called when CDM registration is complete. |result| will
    // be CEF_CDM_REGISTRATION_ERROR_NONE if registration completed successfully.
    // Otherwise, |result| and |error_message| will contain additional information
    // about why registration failed.
    ///
    void function (
        _cef_register_cdm_callback_t* self,
        cef_cdm_registration_error_t result,
        const(cef_string_t)* error_message) nothrow on_cdm_registration_complete;
}

alias cef_register_cdm_callback_t = _cef_register_cdm_callback_t;

///
// Visit web plugin information. Can be called on any thread in the browser
// process.
///
void cef_visit_web_plugin_info (cef_web_plugin_info_visitor_t* visitor);

///
// Cause the plugin list to refresh the next time it is accessed regardless of
// whether it has already been loaded. Can be called on any thread in the
// browser process.
///
void cef_refresh_web_plugins ();

///
// Unregister an internal plugin. This may be undone the next time
// cef_refresh_web_plugins() is called. Can be called on any thread in the
// browser process.
///
void cef_unregister_internal_web_plugin (const(cef_string_t)* path);

///
// Register a plugin crash. Can be called on any thread in the browser process
// but will be executed on the IO thread.
///
void cef_register_web_plugin_crash (const(cef_string_t)* path);

///
// Query if a plugin is unstable. Can be called on any thread in the browser
// process.
///
void cef_is_web_plugin_unstable (
    const(cef_string_t)* path,
    cef_web_plugin_unstable_callback_t* callback);

///
// Register the Widevine CDM plugin.
//
// The client application is responsible for downloading an appropriate
// platform-specific CDM binary distribution from Google, extracting the
// contents, and building the required directory structure on the local machine.
// The cef_browser_host_t::StartDownload function and CefZipArchive structure
// can be used to implement this functionality in CEF. Contact Google via
// https://www.widevine.com/contact.html for details on CDM download.
//
// |path| is a directory that must contain the following files:
//   1. manifest.json file from the CDM binary distribution (see below).
//   2. widevinecdm file from the CDM binary distribution (e.g.
//      widevinecdm.dll on on Windows, libwidevinecdm.dylib on OS X,
//      libwidevinecdm.so on Linux).
//
// If any of these files are missing or if the manifest file has incorrect
// contents the registration will fail and |callback| will receive a |result|
// value of CEF_CDM_REGISTRATION_ERROR_INCORRECT_CONTENTS.
//
// The manifest.json file must contain the following keys:
//   A. "os": Supported OS (e.g. "mac", "win" or "linux").
//   B. "arch": Supported architecture (e.g. "ia32" or "x64").
//   C. "x-cdm-module-versions": Module API version (e.g. "4").
//   D. "x-cdm-interface-versions": Interface API version (e.g. "8").
//   E. "x-cdm-host-versions": Host API version (e.g. "8").
//   F. "version": CDM version (e.g. "1.4.8.903").
//   G. "x-cdm-codecs": List of supported codecs (e.g. "vp8,vp9.0,avc1").
//
// A through E are used to verify compatibility with the current Chromium
// version. If the CDM is not compatible the registration will fail and
// |callback| will receive a |result| value of
// CEF_CDM_REGISTRATION_ERROR_INCOMPATIBLE.
//
// |callback| will be executed asynchronously once registration is complete.
//
// On Linux this function must be called before cef_initialize() and the
// registration cannot be changed during runtime. If registration is not
// supported at the time that cef_register_widevine_cdm() is called then
// |callback| will receive a |result| value of
// CEF_CDM_REGISTRATION_ERROR_NOT_SUPPORTED.
///
void cef_register_widevine_cdm (
    const(cef_string_t)* path,
    cef_register_cdm_callback_t* callback);

// CEF_INCLUDE_CAPI_CEF_WEB_PLUGIN_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=2d04c2cc1791b90ddb9333fe830ad07042e9df2d$
//

extern (C):

///
// Structure representing the issuer or subject field of an X.509 certificate.
///
struct _cef_x509cert_principal_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns a name that can be used to represent the issuer. It tries in this
    // order: Common Name (CN), Organization Name (O) and Organizational Unit Name
    // (OU) and returns the first non-NULL one found.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_x509cert_principal_t* self) nothrow get_display_name;

    ///
    // Returns the common name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_x509cert_principal_t* self) nothrow get_common_name;

    ///
    // Returns the locality name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_x509cert_principal_t* self) nothrow get_locality_name;

    ///
    // Returns the state or province name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_x509cert_principal_t* self) nothrow get_state_or_province_name;

    ///
    // Returns the country name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_x509cert_principal_t* self) nothrow get_country_name;

    ///
    // Retrieve the list of street addresses.
    ///
    void function (
        _cef_x509cert_principal_t* self,
        cef_string_list_t addresses) nothrow get_street_addresses;

    ///
    // Retrieve the list of organization names.
    ///
    void function (
        _cef_x509cert_principal_t* self,
        cef_string_list_t names) nothrow get_organization_names;

    ///
    // Retrieve the list of organization unit names.
    ///
    void function (
        _cef_x509cert_principal_t* self,
        cef_string_list_t names) nothrow get_organization_unit_names;

    ///
    // Retrieve the list of domain components.
    ///
    void function (
        _cef_x509cert_principal_t* self,
        cef_string_list_t components) nothrow get_domain_components;
}

alias cef_x509cert_principal_t = _cef_x509cert_principal_t;

///
// Structure representing a X.509 certificate.
///
struct _cef_x509certificate_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns the subject of the X.509 certificate. For HTTPS server certificates
    // this represents the web server.  The common name of the subject should
    // match the host name of the web server.
    ///
    _cef_x509cert_principal_t* function (
        _cef_x509certificate_t* self) nothrow get_subject;

    ///
    // Returns the issuer of the X.509 certificate.
    ///
    _cef_x509cert_principal_t* function (
        _cef_x509certificate_t* self) nothrow get_issuer;

    ///
    // Returns the DER encoded serial number for the X.509 certificate. The value
    // possibly includes a leading 00 byte.
    ///
    _cef_binary_value_t* function (
        _cef_x509certificate_t* self) nothrow get_serial_number;

    ///
    // Returns the date before which the X.509 certificate is invalid.
    // CefTime.GetTimeT() will return 0 if no date was specified.
    ///
    cef_time_t function (_cef_x509certificate_t* self) nothrow get_valid_start;

    ///
    // Returns the date after which the X.509 certificate is invalid.
    // CefTime.GetTimeT() will return 0 if no date was specified.
    ///
    cef_time_t function (_cef_x509certificate_t* self) nothrow get_valid_expiry;

    ///
    // Returns the DER encoded data for the X.509 certificate.
    ///
    _cef_binary_value_t* function (
        _cef_x509certificate_t* self) nothrow get_derencoded;

    ///
    // Returns the PEM encoded data for the X.509 certificate.
    ///
    _cef_binary_value_t* function (
        _cef_x509certificate_t* self) nothrow get_pemencoded;

    ///
    // Returns the number of certificates in the issuer chain. If 0, the
    // certificate is self-signed.
    ///
    size_t function (_cef_x509certificate_t* self) nothrow get_issuer_chain_size;

    ///
    // Returns the DER encoded data for the certificate issuer chain. If we failed
    // to encode a certificate in the chain it is still present in the array but
    // is an NULL string.
    ///
    void function (
        _cef_x509certificate_t* self,
        size_t* chainCount,
        _cef_binary_value_t** chain) nothrow get_derencoded_issuer_chain;

    ///
    // Returns the PEM encoded data for the certificate issuer chain. If we failed
    // to encode a certificate in the chain it is still present in the array but
    // is an NULL string.
    ///
    void function (
        _cef_x509certificate_t* self,
        size_t* chainCount,
        _cef_binary_value_t** chain) nothrow get_pemencoded_issuer_chain;
}

alias cef_x509certificate_t = _cef_x509certificate_t;

// CEF_INCLUDE_CAPI_CEF_X509_CERTIFICATE_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=64f6b6477ec81b1d64517cf0af2e3b2121ff39bd$
//

extern (C):

///
// Structure that supports the reading of XML data via the libxml streaming API.
// The functions of this structure should only be called on the thread that
// creates the object.
///
struct _cef_xml_reader_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Moves the cursor to the next node in the document. This function must be
    // called at least once to set the current cursor position. Returns true (1)
    // if the cursor position was set successfully.
    ///
    int function (_cef_xml_reader_t* self) nothrow move_to_next_node;

    ///
    // Close the document. This should be called directly to ensure that cleanup
    // occurs on the correct thread.
    ///
    int function (_cef_xml_reader_t* self) nothrow close;

    ///
    // Returns true (1) if an error has been reported by the XML parser.
    ///
    int function (_cef_xml_reader_t* self) nothrow has_error;

    ///
    // Returns the error string.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_error;

    // The below functions retrieve data for the node at the current cursor
    // position.

    ///
    // Returns the node type.
    ///
    cef_xml_node_type_t function (_cef_xml_reader_t* self) nothrow get_type;

    ///
    // Returns the node depth. Depth starts at 0 for the root node.
    ///
    int function (_cef_xml_reader_t* self) nothrow get_depth;

    ///
    // Returns the local name. See http://www.w3.org/TR/REC-xml-names/#NT-
    // LocalPart for additional details.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_local_name;

    ///
    // Returns the namespace prefix. See http://www.w3.org/TR/REC-xml-names/ for
    // additional details.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_prefix;

    ///
    // Returns the qualified name, equal to (Prefix:)LocalName. See
    // http://www.w3.org/TR/REC-xml-names/#ns-qualnames for additional details.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_xml_reader_t* self) nothrow get_qualified_name;

    ///
    // Returns the URI defining the namespace associated with the node. See
    // http://www.w3.org/TR/REC-xml-names/ for additional details.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_namespace_uri;

    ///
    // Returns the base URI of the node. See http://www.w3.org/TR/xmlbase/ for
    // additional details.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_base_uri;

    ///
    // Returns the xml:lang scope within which the node resides. See
    // http://www.w3.org/TR/REC-xml/#sec-lang-tag for additional details.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_xml_lang;

    ///
    // Returns true (1) if the node represents an NULL element. <a/> is considered
    // NULL but <a></a> is not.
    ///
    int function (_cef_xml_reader_t* self) nothrow is_empty_element;

    ///
    // Returns true (1) if the node has a text value.
    ///
    int function (_cef_xml_reader_t* self) nothrow has_value;

    ///
    // Returns the text value.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_value;

    ///
    // Returns true (1) if the node has attributes.
    ///
    int function (_cef_xml_reader_t* self) nothrow has_attributes;

    ///
    // Returns the number of attributes.
    ///
    size_t function (_cef_xml_reader_t* self) nothrow get_attribute_count;

    ///
    // Returns the value of the attribute at the specified 0-based index.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_xml_reader_t* self,
        int index) nothrow get_attribute_byindex;

    ///
    // Returns the value of the attribute with the specified qualified name.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_xml_reader_t* self,
        const(cef_string_t)* qualifiedName) nothrow get_attribute_byqname;

    ///
    // Returns the value of the attribute with the specified local name and
    // namespace URI.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_xml_reader_t* self,
        const(cef_string_t)* localName,
        const(cef_string_t)* namespaceURI) nothrow get_attribute_bylname;

    ///
    // Returns an XML representation of the current node's children.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_inner_xml;

    ///
    // Returns an XML representation of the current node including its children.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_xml_reader_t* self) nothrow get_outer_xml;

    ///
    // Returns the line number for the current node.
    ///
    int function (_cef_xml_reader_t* self) nothrow get_line_number;

    // Attribute nodes are not traversed by default. The below functions can be
    // used to move the cursor to an attribute node. move_to_carrying_element()
    // can be called afterwards to return the cursor to the carrying element. The
    // depth of an attribute node will be 1 + the depth of the carrying element.

    ///
    // Moves the cursor to the attribute at the specified 0-based index. Returns
    // true (1) if the cursor position was set successfully.
    ///
    int function (
        _cef_xml_reader_t* self,
        int index) nothrow move_to_attribute_byindex;

    ///
    // Moves the cursor to the attribute with the specified qualified name.
    // Returns true (1) if the cursor position was set successfully.
    ///
    int function (
        _cef_xml_reader_t* self,
        const(cef_string_t)* qualifiedName) nothrow move_to_attribute_byqname;

    ///
    // Moves the cursor to the attribute with the specified local name and
    // namespace URI. Returns true (1) if the cursor position was set
    // successfully.
    ///
    int function (
        _cef_xml_reader_t* self,
        const(cef_string_t)* localName,
        const(cef_string_t)* namespaceURI) nothrow move_to_attribute_bylname;

    ///
    // Moves the cursor to the first attribute in the current element. Returns
    // true (1) if the cursor position was set successfully.
    ///
    int function (_cef_xml_reader_t* self) nothrow move_to_first_attribute;

    ///
    // Moves the cursor to the next attribute in the current element. Returns true
    // (1) if the cursor position was set successfully.
    ///
    int function (_cef_xml_reader_t* self) nothrow move_to_next_attribute;

    ///
    // Moves the cursor back to the carrying element. Returns true (1) if the
    // cursor position was set successfully.
    ///
    int function (_cef_xml_reader_t* self) nothrow move_to_carrying_element;
}

alias cef_xml_reader_t = _cef_xml_reader_t;

///
// Create a new cef_xml_reader_t object. The returned object's functions can
// only be called from the thread that created the object.
///
cef_xml_reader_t* cef_xml_reader_create (
    _cef_stream_reader_t* stream,
    cef_xml_encoding_type_t encodingType,
    const(cef_string_t)* URI);

// CEF_INCLUDE_CAPI_CEF_XML_READER_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=f8b7ec1654c7d62153e2670b52ed18eb4c9c58d5$
//

extern (C):

///
// Structure that supports the reading of zip archives via the zlib unzip API.
// The functions of this structure should only be called on the thread that
// creates the object.
///
struct _cef_zip_reader_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Moves the cursor to the first file in the archive. Returns true (1) if the
    // cursor position was set successfully.
    ///
    int function (_cef_zip_reader_t* self) nothrow move_to_first_file;

    ///
    // Moves the cursor to the next file in the archive. Returns true (1) if the
    // cursor position was set successfully.
    ///
    int function (_cef_zip_reader_t* self) nothrow move_to_next_file;

    ///
    // Moves the cursor to the specified file in the archive. If |caseSensitive|
    // is true (1) then the search will be case sensitive. Returns true (1) if the
    // cursor position was set successfully.
    ///
    int function (
        _cef_zip_reader_t* self,
        const(cef_string_t)* fileName,
        int caseSensitive) nothrow move_to_file;

    ///
    // Closes the archive. This should be called directly to ensure that cleanup
    // occurs on the correct thread.
    ///
    int function (_cef_zip_reader_t* self) nothrow close;

    // The below functions act on the file at the current cursor position.

    ///
    // Returns the name of the file.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (_cef_zip_reader_t* self) nothrow get_file_name;

    ///
    // Returns the uncompressed size of the file.
    ///
    int64 function (_cef_zip_reader_t* self) nothrow get_file_size;

    ///
    // Returns the last modified timestamp for the file.
    ///
    cef_time_t function (_cef_zip_reader_t* self) nothrow get_file_last_modified;

    ///
    // Opens the file for reading of uncompressed data. A read password may
    // optionally be specified.
    ///
    int function (
        _cef_zip_reader_t* self,
        const(cef_string_t)* password) nothrow open_file;

    ///
    // Closes the file.
    ///
    int function (_cef_zip_reader_t* self) nothrow close_file;

    ///
    // Read uncompressed file contents into the specified buffer. Returns < 0 if
    // an error occurred, 0 if at the end of file, or the number of bytes read.
    ///
    int function (
        _cef_zip_reader_t* self,
        void* buffer,
        size_t bufferSize) nothrow read_file;

    ///
    // Returns the current offset in the uncompressed file contents.
    ///
    int64 function (_cef_zip_reader_t* self) nothrow tell;

    ///
    // Returns true (1) if at end of the file contents.
    ///
    int function (_cef_zip_reader_t* self) nothrow eof;
}

alias cef_zip_reader_t = _cef_zip_reader_t;

///
// Create a new cef_zip_reader_t object. The returned object's functions can
// only be called from the thread that created the object.
///
cef_zip_reader_t* cef_zip_reader_create (_cef_stream_reader_t* stream);

// CEF_INCLUDE_CAPI_CEF_ZIP_READER_CAPI_H_
// Copyright (c) 2014 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import core.stdc.limits;

extern (C):

// Bring in platform-specific definitions.

// 32-bit ARGB color value, not premultiplied. The color components are always
// in a known order. Equivalent to the SkColor type.
alias cef_color_t = uint;

///
// Log severity levels.
///
enum cef_log_severity_t
{
    ///
    // Default logging (currently INFO logging).
    ///
    LOGSEVERITY_DEFAULT = 0,

    ///
    // Verbose logging.
    ///
    LOGSEVERITY_VERBOSE = 1,

    ///
    // DEBUG logging.
    ///
    LOGSEVERITY_DEBUG = LOGSEVERITY_VERBOSE,

    ///
    // INFO logging.
    ///
    LOGSEVERITY_INFO = 2,

    ///
    // WARNING logging.
    ///
    LOGSEVERITY_WARNING = 3,

    ///
    // ERROR logging.
    ///
    LOGSEVERITY_ERROR = 4,

    ///
    // FATAL logging.
    ///
    LOGSEVERITY_FATAL = 5,

    ///
    // Disable logging to file for all messages, and to stderr for messages with
    // severity less than FATAL.
    ///
    LOGSEVERITY_DISABLE = 99
}

///
// Represents the state of a setting.
///
enum cef_state_t
{
    ///
    // Use the default state for the setting.
    ///
    STATE_DEFAULT = 0,

    ///
    // Enable or allow the setting.
    ///
    STATE_ENABLED = 1,

    ///
    // Disable or disallow the setting.
    ///
    STATE_DISABLED = 2
}

///
// Initialization settings. Specify NULL or 0 to get the recommended default
// values. Many of these and other settings can also configured using command-
// line switches.
///
struct _cef_settings_t
{
    ///
    // Size of this structure.
    ///
    size_t size;

    ///
    // Set to true (1) to disable the sandbox for sub-processes. See
    // cef_sandbox_win.h for requirements to enable the sandbox on Windows. Also
    // configurable using the "no-sandbox" command-line switch.
    ///
    int no_sandbox;

    ///
    // The path to a separate executable that will be launched for sub-processes.
    // If this value is empty on Windows or Linux then the main process executable
    // will be used. If this value is empty on macOS then a helper executable must
    // exist at "Contents/Frameworks/<app> Helper.app/Contents/MacOS/<app> Helper"
    // in the top-level app bundle. See the comments on CefExecuteProcess() for
    // details. If this value is non-empty then it must be an absolute path. Also
    // configurable using the "browser-subprocess-path" command-line switch.
    ///
    cef_string_t browser_subprocess_path;

    ///
    // The path to the CEF framework directory on macOS. If this value is empty
    // then the framework must exist at "Contents/Frameworks/Chromium Embedded
    // Framework.framework" in the top-level app bundle. If this value is
    // non-empty then it must be an absolute path. Also configurable using the
    // "framework-dir-path" command-line switch.
    ///
    cef_string_t framework_dir_path;

    ///
    // The path to the main bundle on macOS. If this value is empty then it
    // defaults to the top-level app bundle. If this value is non-empty then it
    // must be an absolute path. Also configurable using the "main-bundle-path"
    // command-line switch.
    ///
    cef_string_t main_bundle_path;

    ///
    // Set to true (1) to enable use of the Chrome runtime in CEF. This feature is
    // considered experimental and is not recommended for most users at this time.
    // See issue #2969 for details.
    ///
    int chrome_runtime;

    ///
    // Set to true (1) to have the browser process message loop run in a separate
    // thread. If false (0) than the CefDoMessageLoopWork() function must be
    // called from your application message loop. This option is only supported on
    // Windows and Linux.
    ///
    int multi_threaded_message_loop;

    ///
    // Set to true (1) to control browser process main (UI) thread message pump
    // scheduling via the CefBrowserProcessHandler::OnScheduleMessagePumpWork()
    // callback. This option is recommended for use in combination with the
    // CefDoMessageLoopWork() function in cases where the CEF message loop must be
    // integrated into an existing application message loop (see additional
    // comments and warnings on CefDoMessageLoopWork). Enabling this option is not
    // recommended for most users; leave this option disabled and use either the
    // CefRunMessageLoop() function or multi_threaded_message_loop if possible.
    ///
    int external_message_pump;

    ///
    // Set to true (1) to enable windowless (off-screen) rendering support. Do not
    // enable this value if the application does not use windowless rendering as
    // it may reduce rendering performance on some systems.
    ///
    int windowless_rendering_enabled;

    ///
    // Set to true (1) to disable configuration of browser process features using
    // standard CEF and Chromium command-line arguments. Configuration can still
    // be specified using CEF data structures or via the
    // CefApp::OnBeforeCommandLineProcessing() method.
    ///
    int command_line_args_disabled;

    ///
    // The location where data for the global browser cache will be stored on
    // disk. If this value is non-empty then it must be an absolute path that is
    // either equal to or a child directory of CefSettings.root_cache_path. If
    // this value is empty then browsers will be created in "incognito mode" where
    // in-memory caches are used for storage and no data is persisted to disk.
    // HTML5 databases such as localStorage will only persist across sessions if a
    // cache path is specified. Can be overridden for individual CefRequestContext
    // instances via the CefRequestContextSettings.cache_path value.
    ///
    cef_string_t cache_path;

    ///
    // The root directory that all CefSettings.cache_path and
    // CefRequestContextSettings.cache_path values must have in common. If this
    // value is empty and CefSettings.cache_path is non-empty then it will
    // default to the CefSettings.cache_path value. If this value is non-empty
    // then it must be an absolute path. Failure to set this value correctly may
    // result in the sandbox blocking read/write access to the cache_path
    // directory.
    ///
    cef_string_t root_cache_path;

    ///
    // The location where user data such as spell checking dictionary files will
    // be stored on disk. If this value is empty then the default
    // platform-specific user data directory will be used ("~/.cef_user_data"
    // directory on Linux, "~/Library/Application Support/CEF/User Data" directory
    // on Mac OS X, "Local Settings\Application Data\CEF\User Data" directory
    // under the user profile directory on Windows). If this value is non-empty
    // then it must be an absolute path.
    ///
    cef_string_t user_data_path;

    ///
    // To persist session cookies (cookies without an expiry date or validity
    // interval) by default when using the global cookie manager set this value to
    // true (1). Session cookies are generally intended to be transient and most
    // Web browsers do not persist them. A |cache_path| value must also be
    // specified to enable this feature. Also configurable using the
    // "persist-session-cookies" command-line switch. Can be overridden for
    // individual CefRequestContext instances via the
    // CefRequestContextSettings.persist_session_cookies value.
    ///
    int persist_session_cookies;

    ///
    // To persist user preferences as a JSON file in the cache path directory set
    // this value to true (1). A |cache_path| value must also be specified
    // to enable this feature. Also configurable using the
    // "persist-user-preferences" command-line switch. Can be overridden for
    // individual CefRequestContext instances via the
    // CefRequestContextSettings.persist_user_preferences value.
    ///
    int persist_user_preferences;

    ///
    // Value that will be returned as the User-Agent HTTP header. If empty the
    // default User-Agent string will be used. Also configurable using the
    // "user-agent" command-line switch.
    ///
    cef_string_t user_agent;

    ///
    // Value that will be inserted as the product portion of the default
    // User-Agent string. If empty the Chromium product version will be used. If
    // |userAgent| is specified this value will be ignored. Also configurable
    // using the "product-version" command-line switch.
    ///
    cef_string_t product_version;

    ///
    // The locale string that will be passed to WebKit. If empty the default
    // locale of "en-US" will be used. This value is ignored on Linux where locale
    // is determined using environment variable parsing with the precedence order:
    // LANGUAGE, LC_ALL, LC_MESSAGES and LANG. Also configurable using the "lang"
    // command-line switch.
    ///
    cef_string_t locale;

    ///
    // The directory and file name to use for the debug log. If empty a default
    // log file name and location will be used. On Windows and Linux a "debug.log"
    // file will be written in the main executable directory. On Mac OS X a
    // "~/Library/Logs/<app name>_debug.log" file will be written where <app name>
    // is the name of the main app executable. Also configurable using the
    // "log-file" command-line switch.
    ///
    cef_string_t log_file;

    ///
    // The log severity. Only messages of this severity level or higher will be
    // logged. When set to DISABLE no messages will be written to the log file,
    // but FATAL messages will still be output to stderr. Also configurable using
    // the "log-severity" command-line switch with a value of "verbose", "info",
    // "warning", "error", "fatal" or "disable".
    ///
    cef_log_severity_t log_severity;

    ///
    // Custom flags that will be used when initializing the V8 JavaScript engine.
    // The consequences of using custom flags may not be well tested. Also
    // configurable using the "js-flags" command-line switch.
    ///
    cef_string_t javascript_flags;

    ///
    // The fully qualified path for the resources directory. If this value is
    // empty the cef.pak and/or devtools_resources.pak files must be located in
    // the module directory on Windows/Linux or the app bundle Resources directory
    // on Mac OS X. If this value is non-empty then it must be an absolute path.
    // Also configurable using the "resources-dir-path" command-line switch.
    ///
    cef_string_t resources_dir_path;

    ///
    // The fully qualified path for the locales directory. If this value is empty
    // the locales directory must be located in the module directory. If this
    // value is non-empty then it must be an absolute path. This value is ignored
    // on Mac OS X where pack files are always loaded from the app bundle
    // Resources directory. Also configurable using the "locales-dir-path"
    // command-line switch.
    ///
    cef_string_t locales_dir_path;

    ///
    // Set to true (1) to disable loading of pack files for resources and locales.
    // A resource bundle handler must be provided for the browser and render
    // processes via CefApp::GetResourceBundleHandler() if loading of pack files
    // is disabled. Also configurable using the "disable-pack-loading" command-
    // line switch.
    ///
    int pack_loading_disabled;

    ///
    // Set to a value between 1024 and 65535 to enable remote debugging on the
    // specified port. For example, if 8080 is specified the remote debugging URL
    // will be http://localhost:8080. CEF can be remotely debugged from any CEF or
    // Chrome browser window. Also configurable using the "remote-debugging-port"
    // command-line switch.
    ///
    int remote_debugging_port;

    ///
    // The number of stack trace frames to capture for uncaught exceptions.
    // Specify a positive value to enable the CefRenderProcessHandler::
    // OnUncaughtException() callback. Specify 0 (default value) and
    // OnUncaughtException() will not be called. Also configurable using the
    // "uncaught-exception-stack-size" command-line switch.
    ///
    int uncaught_exception_stack_size;

    ///
    // Set to true (1) to ignore errors related to invalid SSL certificates.
    // Enabling this setting can lead to potential security vulnerabilities like
    // "man in the middle" attacks. Applications that load content from the
    // internet should not enable this setting. Also configurable using the
    // "ignore-certificate-errors" command-line switch. Can be overridden for
    // individual CefRequestContext instances via the
    // CefRequestContextSettings.ignore_certificate_errors value.
    ///
    int ignore_certificate_errors;

    ///
    // Background color used for the browser before a document is loaded and when
    // no document color is specified. The alpha component must be either fully
    // opaque (0xFF) or fully transparent (0x00). If the alpha component is fully
    // opaque then the RGB components will be used as the background color. If the
    // alpha component is fully transparent for a windowed browser then the
    // default value of opaque white be used. If the alpha component is fully
    // transparent for a windowless (off-screen) browser then transparent painting
    // will be enabled.
    ///
    cef_color_t background_color;

    ///
    // Comma delimited ordered list of language codes without any whitespace that
    // will be used in the "Accept-Language" HTTP header. May be overridden on a
    // per-browser basis using the CefBrowserSettings.accept_language_list value.
    // If both values are empty then "en-US,en" will be used. Can be overridden
    // for individual CefRequestContext instances via the
    // CefRequestContextSettings.accept_language_list value.
    ///
    cef_string_t accept_language_list;

    ///
    // GUID string used for identifying the application. This is passed to the
    // system AV function for scanning downloaded files. By default, the GUID
    // will be an empty string and the file will be treated as an untrusted
    // file when the GUID is empty.
    ///
    cef_string_t application_client_id_for_file_scanning;
}

alias cef_settings_t = _cef_settings_t;

///
// Request context initialization settings. Specify NULL or 0 to get the
// recommended default values.
///
struct _cef_request_context_settings_t
{
    ///
    // Size of this structure.
    ///
    size_t size;

    ///
    // The location where cache data for this request context will be stored on
    // disk. If this value is non-empty then it must be an absolute path that is
    // either equal to or a child directory of CefSettings.root_cache_path. If
    // this value is empty then browsers will be created in "incognito mode" where
    // in-memory caches are used for storage and no data is persisted to disk.
    // HTML5 databases such as localStorage will only persist across sessions if a
    // cache path is specified. To share the global browser cache and related
    // configuration set this value to match the CefSettings.cache_path value.
    ///
    cef_string_t cache_path;

    ///
    // To persist session cookies (cookies without an expiry date or validity
    // interval) by default when using the global cookie manager set this value to
    // true (1). Session cookies are generally intended to be transient and most
    // Web browsers do not persist them. Can be set globally using the
    // CefSettings.persist_session_cookies value. This value will be ignored if
    // |cache_path| is empty or if it matches the CefSettings.cache_path value.
    ///
    int persist_session_cookies;

    ///
    // To persist user preferences as a JSON file in the cache path directory set
    // this value to true (1). Can be set globally using the
    // CefSettings.persist_user_preferences value. This value will be ignored if
    // |cache_path| is empty or if it matches the CefSettings.cache_path value.
    ///
    int persist_user_preferences;

    ///
    // Set to true (1) to ignore errors related to invalid SSL certificates.
    // Enabling this setting can lead to potential security vulnerabilities like
    // "man in the middle" attacks. Applications that load content from the
    // internet should not enable this setting. Can be set globally using the
    // CefSettings.ignore_certificate_errors value. This value will be ignored if
    // |cache_path| matches the CefSettings.cache_path value.
    ///
    int ignore_certificate_errors;

    ///
    // Comma delimited ordered list of language codes without any whitespace that
    // will be used in the "Accept-Language" HTTP header. Can be set globally
    // using the CefSettings.accept_language_list value or overridden on a per-
    // browser basis using the CefBrowserSettings.accept_language_list value. If
    // all values are empty then "en-US,en" will be used. This value will be
    // ignored if |cache_path| matches the CefSettings.cache_path value.
    ///
    cef_string_t accept_language_list;
}

alias cef_request_context_settings_t = _cef_request_context_settings_t;

///
// Browser initialization settings. Specify NULL or 0 to get the recommended
// default values. The consequences of using custom values may not be well
// tested. Many of these and other settings can also configured using command-
// line switches.
///
struct _cef_browser_settings_t
{
    ///
    // Size of this structure.
    ///
    size_t size;

    ///
    // The maximum rate in frames per second (fps) that CefRenderHandler::OnPaint
    // will be called for a windowless browser. The actual fps may be lower if
    // the browser cannot generate frames at the requested rate. The minimum
    // value is 1 and the maximum value is 60 (default 30). This value can also be
    // changed dynamically via CefBrowserHost::SetWindowlessFrameRate.
    ///
    int windowless_frame_rate;

    // The below values map to WebPreferences settings.

    ///
    // Font settings.
    ///
    cef_string_t standard_font_family;
    cef_string_t fixed_font_family;
    cef_string_t serif_font_family;
    cef_string_t sans_serif_font_family;
    cef_string_t cursive_font_family;
    cef_string_t fantasy_font_family;
    int default_font_size;
    int default_fixed_font_size;
    int minimum_font_size;
    int minimum_logical_font_size;

    ///
    // Default encoding for Web content. If empty "ISO-8859-1" will be used. Also
    // configurable using the "default-encoding" command-line switch.
    ///
    cef_string_t default_encoding;

    ///
    // Controls the loading of fonts from remote sources. Also configurable using
    // the "disable-remote-fonts" command-line switch.
    ///
    cef_state_t remote_fonts;

    ///
    // Controls whether JavaScript can be executed. Also configurable using the
    // "disable-javascript" command-line switch.
    ///
    cef_state_t javascript;

    ///
    // Controls whether JavaScript can be used to close windows that were not
    // opened via JavaScript. JavaScript can still be used to close windows that
    // were opened via JavaScript or that have no back/forward history. Also
    // configurable using the "disable-javascript-close-windows" command-line
    // switch.
    ///
    cef_state_t javascript_close_windows;

    ///
    // Controls whether JavaScript can access the clipboard. Also configurable
    // using the "disable-javascript-access-clipboard" command-line switch.
    ///
    cef_state_t javascript_access_clipboard;

    ///
    // Controls whether DOM pasting is supported in the editor via
    // execCommand("paste"). The |javascript_access_clipboard| setting must also
    // be enabled. Also configurable using the "disable-javascript-dom-paste"
    // command-line switch.
    ///
    cef_state_t javascript_dom_paste;

    ///
    // Controls whether any plugins will be loaded. Also configurable using the
    // "disable-plugins" command-line switch.
    ///
    cef_state_t plugins;

    ///
    // Controls whether file URLs will have access to all URLs. Also configurable
    // using the "allow-universal-access-from-files" command-line switch.
    ///
    cef_state_t universal_access_from_file_urls;

    ///
    // Controls whether file URLs will have access to other file URLs. Also
    // configurable using the "allow-access-from-files" command-line switch.
    ///
    cef_state_t file_access_from_file_urls;

    ///
    // Controls whether web security restrictions (same-origin policy) will be
    // enforced. Disabling this setting is not recommend as it will allow risky
    // security behavior such as cross-site scripting (XSS). Also configurable
    // using the "disable-web-security" command-line switch.
    ///
    cef_state_t web_security;

    ///
    // Controls whether image URLs will be loaded from the network. A cached image
    // will still be rendered if requested. Also configurable using the
    // "disable-image-loading" command-line switch.
    ///
    cef_state_t image_loading;

    ///
    // Controls whether standalone images will be shrunk to fit the page. Also
    // configurable using the "image-shrink-standalone-to-fit" command-line
    // switch.
    ///
    cef_state_t image_shrink_standalone_to_fit;

    ///
    // Controls whether text areas can be resized. Also configurable using the
    // "disable-text-area-resize" command-line switch.
    ///
    cef_state_t text_area_resize;

    ///
    // Controls whether the tab key can advance focus to links. Also configurable
    // using the "disable-tab-to-links" command-line switch.
    ///
    cef_state_t tab_to_links;

    ///
    // Controls whether local storage can be used. Also configurable using the
    // "disable-local-storage" command-line switch.
    ///
    cef_state_t local_storage;

    ///
    // Controls whether databases can be used. Also configurable using the
    // "disable-databases" command-line switch.
    ///
    cef_state_t databases;

    ///
    // Controls whether the application cache can be used. Also configurable using
    // the "disable-application-cache" command-line switch.
    ///
    cef_state_t application_cache;

    ///
    // Controls whether WebGL can be used. Note that WebGL requires hardware
    // support and may not work on all systems even when enabled. Also
    // configurable using the "disable-webgl" command-line switch.
    ///
    cef_state_t webgl;

    ///
    // Background color used for the browser before a document is loaded and when
    // no document color is specified. The alpha component must be either fully
    // opaque (0xFF) or fully transparent (0x00). If the alpha component is fully
    // opaque then the RGB components will be used as the background color. If the
    // alpha component is fully transparent for a windowed browser then the
    // CefSettings.background_color value will be used. If the alpha component is
    // fully transparent for a windowless (off-screen) browser then transparent
    // painting will be enabled.
    ///
    cef_color_t background_color;

    ///
    // Comma delimited ordered list of language codes without any whitespace that
    // will be used in the "Accept-Language" HTTP header. May be set globally
    // using the CefBrowserSettings.accept_language_list value. If both values are
    // empty then "en-US,en" will be used.
    ///
    cef_string_t accept_language_list;
}

alias cef_browser_settings_t = _cef_browser_settings_t;

///
// Return value types.
///
enum cef_return_value_t
{
    ///
    // Cancel immediately.
    ///
    RV_CANCEL = 0,

    ///
    // Continue immediately.
    ///
    RV_CONTINUE = 1,

    ///
    // Continue asynchronously (usually via a callback).
    ///
    RV_CONTINUE_ASYNC = 2
}

///
// URL component parts.
///
struct _cef_urlparts_t
{
    ///
    // The complete URL specification.
    ///
    cef_string_t spec;

    ///
    // Scheme component not including the colon (e.g., "http").
    ///
    cef_string_t scheme;

    ///
    // User name component.
    ///
    cef_string_t username;

    ///
    // Password component.
    ///
    cef_string_t password;

    ///
    // Host component. This may be a hostname, an IPv4 address or an IPv6 literal
    // surrounded by square brackets (e.g., "[2001:db8::1]").
    ///
    cef_string_t host;

    ///
    // Port number component.
    ///
    cef_string_t port;

    ///
    // Origin contains just the scheme, host, and port from a URL. Equivalent to
    // clearing any username and password, replacing the path with a slash, and
    // clearing everything after that. This value will be empty for non-standard
    // URLs.
    ///
    cef_string_t origin;

    ///
    // Path component including the first slash following the host.
    ///
    cef_string_t path;

    ///
    // Query string component (i.e., everything following the '?').
    ///
    cef_string_t query;

    ///
    // Fragment (hash) identifier component (i.e., the string following the '#').
    ///
    cef_string_t fragment;
}

alias cef_urlparts_t = _cef_urlparts_t;

///
// Cookie priority values.
///
enum cef_cookie_priority_t
{
    CEF_COOKIE_PRIORITY_LOW = -1,
    CEF_COOKIE_PRIORITY_MEDIUM = 0,
    CEF_COOKIE_PRIORITY_HIGH = 1
}

///
// Cookie same site values.
///
enum cef_cookie_same_site_t
{
    CEF_COOKIE_SAME_SITE_UNSPECIFIED = 0,
    CEF_COOKIE_SAME_SITE_NO_RESTRICTION = 1,
    CEF_COOKIE_SAME_SITE_LAX_MODE = 2,
    CEF_COOKIE_SAME_SITE_STRICT_MODE = 3
}

///
// Cookie information.
///
struct _cef_cookie_t
{
    ///
    // The cookie name.
    ///
    cef_string_t name;

    ///
    // The cookie value.
    ///
    cef_string_t value;

    ///
    // If |domain| is empty a host cookie will be created instead of a domain
    // cookie. Domain cookies are stored with a leading "." and are visible to
    // sub-domains whereas host cookies are not.
    ///
    cef_string_t domain;

    ///
    // If |path| is non-empty only URLs at or below the path will get the cookie
    // value.
    ///
    cef_string_t path;

    ///
    // If |secure| is true the cookie will only be sent for HTTPS requests.
    ///
    int secure;

    ///
    // If |httponly| is true the cookie will only be sent for HTTP requests.
    ///
    int httponly;

    ///
    // The cookie creation date. This is automatically populated by the system on
    // cookie creation.
    ///
    cef_time_t creation;

    ///
    // The cookie last access date. This is automatically populated by the system
    // on access.
    ///
    cef_time_t last_access;

    ///
    // The cookie expiration date is only valid if |has_expires| is true.
    ///
    int has_expires;
    cef_time_t expires;

    ///
    // Same site.
    ///
    cef_cookie_same_site_t same_site;

    ///
    // Priority.
    ///
    cef_cookie_priority_t priority;
}

alias cef_cookie_t = _cef_cookie_t;

///
// Process termination status values.
///
enum cef_termination_status_t
{
    ///
    // Non-zero exit status.
    ///
    TS_ABNORMAL_TERMINATION = 0,

    ///
    // SIGKILL or task manager kill.
    ///
    TS_PROCESS_WAS_KILLED = 1,

    ///
    // Segmentation fault.
    ///
    TS_PROCESS_CRASHED = 2,

    ///
    // Out of memory. Some platforms may use TS_PROCESS_CRASHED instead.
    ///
    TS_PROCESS_OOM = 3
}

///
// Path key values.
///
enum cef_path_key_t
{
    ///
    // Current directory.
    ///
    PK_DIR_CURRENT = 0,

    ///
    // Directory containing PK_FILE_EXE.
    ///
    PK_DIR_EXE = 1,

    ///
    // Directory containing PK_FILE_MODULE.
    ///
    PK_DIR_MODULE = 2,

    ///
    // Temporary directory.
    ///
    PK_DIR_TEMP = 3,

    ///
    // Path and filename of the current executable.
    ///
    PK_FILE_EXE = 4,

    ///
    // Path and filename of the module containing the CEF code (usually the libcef
    // module).
    ///
    PK_FILE_MODULE = 5,

    ///
    // "Local Settings\Application Data" directory under the user profile
    // directory on Windows.
    ///
    PK_LOCAL_APP_DATA = 6,

    ///
    // "Application Data" directory under the user profile directory on Windows
    // and "~/Library/Application Support" directory on Mac OS X.
    ///
    PK_USER_DATA = 7,

    ///
    // Directory containing application resources. Can be configured via
    // CefSettings.resources_dir_path.
    ///
    PK_DIR_RESOURCES = 8
}

///
// Storage types.
///
enum cef_storage_type_t
{
    ST_LOCALSTORAGE = 0,
    ST_SESSIONSTORAGE = 1
}

///
// Supported error code values.
///
enum cef_errorcode_t
{
    // No error.
    ERR_NONE = 0,
    ERR_IO_PENDING = -1,
    ERR_FAILED = -2,
    ERR_ABORTED = -3,
    ERR_INVALID_ARGUMENT = -4,
    ERR_INVALID_HANDLE = -5,
    ERR_FILE_NOT_FOUND = -6,
    ERR_TIMED_OUT = -7,
    ERR_FILE_TOO_BIG = -8,
    ERR_UNEXPECTED = -9,
    ERR_ACCESS_DENIED = -10,
    ERR_NOT_IMPLEMENTED = -11,
    ERR_INSUFFICIENT_RESOURCES = -12,
    ERR_OUT_OF_MEMORY = -13,
    ERR_UPLOAD_FILE_CHANGED = -14,
    ERR_SOCKET_NOT_CONNECTED = -15,
    ERR_FILE_EXISTS = -16,
    ERR_FILE_PATH_TOO_LONG = -17,
    ERR_FILE_NO_SPACE = -18,
    ERR_FILE_VIRUS_INFECTED = -19,
    ERR_BLOCKED_BY_CLIENT = -20,
    ERR_NETWORK_CHANGED = -21,
    ERR_BLOCKED_BY_ADMINISTRATOR = -22,
    ERR_SOCKET_IS_CONNECTED = -23,
    ERR_BLOCKED_ENROLLMENT_CHECK_PENDING = -24,
    ERR_UPLOAD_STREAM_REWIND_NOT_SUPPORTED = -25,
    ERR_CONTEXT_SHUT_DOWN = -26,
    ERR_BLOCKED_BY_RESPONSE = -27,
    ERR_CLEARTEXT_NOT_PERMITTED = -29,
    ERR_BLOCKED_BY_CSP = -30,
    ERR_H2_OR_QUIC_REQUIRED = -31,
    ERR_INSECURE_PRIVATE_NETWORK_REQUEST = -32,
    ERR_CONNECTION_CLOSED = -100,
    ERR_CONNECTION_RESET = -101,
    ERR_CONNECTION_REFUSED = -102,
    ERR_CONNECTION_ABORTED = -103,
    ERR_CONNECTION_FAILED = -104,
    ERR_NAME_NOT_RESOLVED = -105,
    ERR_INTERNET_DISCONNECTED = -106,
    ERR_SSL_PROTOCOL_ERROR = -107,
    ERR_ADDRESS_INVALID = -108,
    ERR_ADDRESS_UNREACHABLE = -109,
    ERR_SSL_CLIENT_AUTH_CERT_NEEDED = -110,
    ERR_TUNNEL_CONNECTION_FAILED = -111,
    ERR_NO_SSL_VERSIONS_ENABLED = -112,
    ERR_SSL_VERSION_OR_CIPHER_MISMATCH = -113,
    ERR_SSL_RENEGOTIATION_REQUESTED = -114,
    ERR_PROXY_AUTH_UNSUPPORTED = -115,
    ERR_CERT_ERROR_IN_SSL_RENEGOTIATION = -116,
    ERR_BAD_SSL_CLIENT_AUTH_CERT = -117,
    ERR_CONNECTION_TIMED_OUT = -118,
    ERR_HOST_RESOLVER_QUEUE_TOO_LARGE = -119,
    ERR_SOCKS_CONNECTION_FAILED = -120,
    ERR_SOCKS_CONNECTION_HOST_UNREACHABLE = -121,
    ERR_ALPN_NEGOTIATION_FAILED = -122,
    ERR_SSL_NO_RENEGOTIATION = -123,
    ERR_WINSOCK_UNEXPECTED_WRITTEN_BYTES = -124,
    ERR_SSL_DECOMPRESSION_FAILURE_ALERT = -125,
    ERR_SSL_BAD_RECORD_MAC_ALERT = -126,
    ERR_PROXY_AUTH_REQUESTED = -127,
    ERR_PROXY_CONNECTION_FAILED = -130,
    ERR_MANDATORY_PROXY_CONFIGURATION_FAILED = -131,
    ERR_PRECONNECT_MAX_SOCKET_LIMIT = -133,
    ERR_SSL_CLIENT_AUTH_PRIVATE_KEY_ACCESS_DENIED = -134,
    ERR_SSL_CLIENT_AUTH_CERT_NO_PRIVATE_KEY = -135,
    ERR_PROXY_CERTIFICATE_INVALID = -136,
    ERR_NAME_RESOLUTION_FAILED = -137,
    ERR_NETWORK_ACCESS_DENIED = -138,
    ERR_TEMPORARILY_THROTTLED = -139,
    ERR_HTTPS_PROXY_TUNNEL_RESPONSE_REDIRECT = -140,
    ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED = -141,
    ERR_MSG_TOO_BIG = -142,
    ERR_WS_PROTOCOL_ERROR = -145,
    ERR_ADDRESS_IN_USE = -147,
    ERR_SSL_HANDSHAKE_NOT_COMPLETED = -148,
    ERR_SSL_BAD_PEER_PUBLIC_KEY = -149,
    ERR_SSL_PINNED_KEY_NOT_IN_CERT_CHAIN = -150,
    ERR_CLIENT_AUTH_CERT_TYPE_UNSUPPORTED = -151,
    ERR_SSL_DECRYPT_ERROR_ALERT = -153,
    ERR_WS_THROTTLE_QUEUE_TOO_LARGE = -154,
    ERR_SSL_SERVER_CERT_CHANGED = -156,
    ERR_SSL_UNRECOGNIZED_NAME_ALERT = -159,
    ERR_SOCKET_SET_RECEIVE_BUFFER_SIZE_ERROR = -160,
    ERR_SOCKET_SET_SEND_BUFFER_SIZE_ERROR = -161,
    ERR_SOCKET_RECEIVE_BUFFER_SIZE_UNCHANGEABLE = -162,
    ERR_SOCKET_SEND_BUFFER_SIZE_UNCHANGEABLE = -163,
    ERR_SSL_CLIENT_AUTH_CERT_BAD_FORMAT = -164,
    ERR_ICANN_NAME_COLLISION = -166,
    ERR_SSL_SERVER_CERT_BAD_FORMAT = -167,
    ERR_CT_STH_PARSING_FAILED = -168,
    ERR_CT_STH_INCOMPLETE = -169,
    ERR_UNABLE_TO_REUSE_CONNECTION_FOR_PROXY_AUTH = -170,
    ERR_CT_CONSISTENCY_PROOF_PARSING_FAILED = -171,
    ERR_SSL_OBSOLETE_CIPHER = -172,
    ERR_WS_UPGRADE = -173,
    ERR_READ_IF_READY_NOT_IMPLEMENTED = -174,
    ERR_NO_BUFFER_SPACE = -176,
    ERR_SSL_CLIENT_AUTH_NO_COMMON_ALGORITHMS = -177,
    ERR_EARLY_DATA_REJECTED = -178,
    ERR_WRONG_VERSION_ON_EARLY_DATA = -179,
    ERR_TLS13_DOWNGRADE_DETECTED = -180,
    ERR_SSL_KEY_USAGE_INCOMPATIBLE = -181,
    ERR_CERT_COMMON_NAME_INVALID = -200,
    ERR_CERT_DATE_INVALID = -201,
    ERR_CERT_AUTHORITY_INVALID = -202,
    ERR_CERT_CONTAINS_ERRORS = -203,
    ERR_CERT_NO_REVOCATION_MECHANISM = -204,
    ERR_CERT_UNABLE_TO_CHECK_REVOCATION = -205,
    ERR_CERT_REVOKED = -206,
    ERR_CERT_INVALID = -207,
    ERR_CERT_WEAK_SIGNATURE_ALGORITHM = -208,
    ERR_CERT_NON_UNIQUE_NAME = -210,
    ERR_CERT_WEAK_KEY = -211,
    ERR_CERT_NAME_CONSTRAINT_VIOLATION = -212,
    ERR_CERT_VALIDITY_TOO_LONG = -213,
    ERR_CERTIFICATE_TRANSPARENCY_REQUIRED = -214,
    ERR_CERT_SYMANTEC_LEGACY = -215,
    ERR_CERT_KNOWN_INTERCEPTION_BLOCKED = -217,
    ERR_SSL_OBSOLETE_VERSION = -218,
    ERR_CERT_END = -219,
    ERR_INVALID_URL = -300,
    ERR_DISALLOWED_URL_SCHEME = -301,
    ERR_UNKNOWN_URL_SCHEME = -302,
    ERR_INVALID_REDIRECT = -303,
    ERR_TOO_MANY_REDIRECTS = -310,
    ERR_UNSAFE_REDIRECT = -311,
    ERR_UNSAFE_PORT = -312,
    ERR_INVALID_RESPONSE = -320,
    ERR_INVALID_CHUNKED_ENCODING = -321,
    ERR_METHOD_NOT_SUPPORTED = -322,
    ERR_UNEXPECTED_PROXY_AUTH = -323,
    ERR_EMPTY_RESPONSE = -324,
    ERR_RESPONSE_HEADERS_TOO_BIG = -325,
    ERR_PAC_SCRIPT_FAILED = -327,
    ERR_REQUEST_RANGE_NOT_SATISFIABLE = -328,
    ERR_MALFORMED_IDENTITY = -329,
    ERR_CONTENT_DECODING_FAILED = -330,
    ERR_NETWORK_IO_SUSPENDED = -331,
    ERR_SYN_REPLY_NOT_RECEIVED = -332,
    ERR_ENCODING_CONVERSION_FAILED = -333,
    ERR_UNRECOGNIZED_FTP_DIRECTORY_LISTING_FORMAT = -334,
    ERR_NO_SUPPORTED_PROXIES = -336,
    ERR_HTTP2_PROTOCOL_ERROR = -337,
    ERR_INVALID_AUTH_CREDENTIALS = -338,
    ERR_UNSUPPORTED_AUTH_SCHEME = -339,
    ERR_ENCODING_DETECTION_FAILED = -340,
    ERR_MISSING_AUTH_CREDENTIALS = -341,
    ERR_UNEXPECTED_SECURITY_LIBRARY_STATUS = -342,
    ERR_MISCONFIGURED_AUTH_ENVIRONMENT = -343,
    ERR_UNDOCUMENTED_SECURITY_LIBRARY_STATUS = -344,
    ERR_RESPONSE_BODY_TOO_BIG_TO_DRAIN = -345,
    ERR_RESPONSE_HEADERS_MULTIPLE_CONTENT_LENGTH = -346,
    ERR_INCOMPLETE_HTTP2_HEADERS = -347,
    ERR_PAC_NOT_IN_DHCP = -348,
    ERR_RESPONSE_HEADERS_MULTIPLE_CONTENT_DISPOSITION = -349,
    ERR_RESPONSE_HEADERS_MULTIPLE_LOCATION = -350,
    ERR_HTTP2_SERVER_REFUSED_STREAM = -351,
    ERR_HTTP2_PING_FAILED = -352,
    ERR_CONTENT_LENGTH_MISMATCH = -354,
    ERR_INCOMPLETE_CHUNKED_ENCODING = -355,
    ERR_QUIC_PROTOCOL_ERROR = -356,
    ERR_RESPONSE_HEADERS_TRUNCATED = -357,
    ERR_QUIC_HANDSHAKE_FAILED = -358,
    ERR_HTTP2_INADEQUATE_TRANSPORT_SECURITY = -360,
    ERR_HTTP2_FLOW_CONTROL_ERROR = -361,
    ERR_HTTP2_FRAME_SIZE_ERROR = -362,
    ERR_HTTP2_COMPRESSION_ERROR = -363,
    ERR_PROXY_AUTH_REQUESTED_WITH_NO_CONNECTION = -364,
    ERR_HTTP_1_1_REQUIRED = -365,
    ERR_PROXY_HTTP_1_1_REQUIRED = -366,
    ERR_PAC_SCRIPT_TERMINATED = -367,
    ERR_INVALID_HTTP_RESPONSE = -370,
    ERR_CONTENT_DECODING_INIT_FAILED = -371,
    ERR_HTTP2_RST_STREAM_NO_ERROR_RECEIVED = -372,
    ERR_HTTP2_PUSHED_STREAM_NOT_AVAILABLE = -373,
    ERR_HTTP2_CLAIMED_PUSHED_STREAM_RESET_BY_SERVER = -374,
    ERR_TOO_MANY_RETRIES = -375,
    ERR_HTTP2_STREAM_CLOSED = -376,
    ERR_HTTP2_CLIENT_REFUSED_STREAM = -377,
    ERR_HTTP2_PUSHED_RESPONSE_DOES_NOT_MATCH = -378,
    ERR_HTTP_RESPONSE_CODE_FAILURE = -379,
    ERR_QUIC_CERT_ROOT_NOT_KNOWN = -380,
    ERR_QUIC_GOAWAY_REQUEST_CAN_BE_RETRIED = -381,
    ERR_CACHE_MISS = -400,
    ERR_CACHE_READ_FAILURE = -401,
    ERR_CACHE_WRITE_FAILURE = -402,
    ERR_CACHE_OPERATION_NOT_SUPPORTED = -403,
    ERR_CACHE_OPEN_FAILURE = -404,
    ERR_CACHE_CREATE_FAILURE = -405,
    ERR_CACHE_RACE = -406,

    ///
    // Supported certificate status code values. See net\cert\cert_status_flags.h
    // for more information. CERT_STATUS_NONE is new in CEF because we use an
    // enum while cert_status_flags.h uses a typedef and static const variables.
    ERR_CACHE_CHECKSUM_READ_FAILURE = -407,
    ///

    // 1 << 3 is reserved for ERR_CERT_CONTAINS_ERRORS (not useful with WinHTTP).
    ERR_CACHE_CHECKSUM_MISMATCH = -408,
    ERR_CACHE_LOCK_TIMEOUT = -409,

    // 1 << 9 was used for CERT_STATUS_NOT_IN_DNS
    ERR_CACHE_AUTH_FAILURE_AFTER_READ = -410,

    // 1 << 12 was used for CERT_STATUS_WEAK_DH_KEY

    // Bits 16 to 31 are for non-error statuses.
    ERR_CACHE_ENTRY_NOT_SUITABLE = -411,

    // Bit 18 was CERT_STATUS_IS_DNSSEC
    ERR_CACHE_DOOM_FAILURE = -412,
    ERR_CACHE_OPEN_OR_CREATE_FAILURE = -413,

    ///
    // The manner in which a link click should be opened. These constants match
    ERR_INSECURE_RESPONSE = -501,
    // their equivalents in Chromium's window_open_disposition.h and should not be
    // renumbered.
    ///
    ERR_NO_PRIVATE_KEY_FOR_CERT = -502,
    ERR_ADD_USER_CERT_FAILED = -503,

    ///
    ERR_INVALID_SIGNED_EXCHANGE = -504,
    // "Verb" of a drag-and-drop operation as negotiated between the source and
    // destination. These constants match their equivalents in WebCore's
    ERR_INVALID_WEB_BUNDLE = -505,
    // DragActions.h and should not be renumbered.
    ///
    ERR_TRUST_TOKEN_OPERATION_FAILED = -506,

    ///
    // Input mode of a virtual keyboard. These constants match their equivalents
    ERR_TRUST_TOKEN_OPERATION_CACHE_HIT = -507,
    // in Chromium's text_input_mode.h and should not be renumbered.
    // See https://html.spec.whatwg.org/#input-modalities:-the-inputmode-attribute
    ///
    ERR_FTP_FAILED = -601,
    ERR_FTP_SERVICE_UNAVAILABLE = -602,
    ERR_FTP_TRANSFER_ABORTED = -603,

    ///
    // V8 access control values.
    ///
    ERR_FTP_FILE_BUSY = -604,

    ///
    // V8 property attribute values.
    ERR_FTP_SYNTAX_ERROR = -605,
    ///

    // Writeable, Enumerable,
    ERR_FTP_COMMAND_NOT_SUPPORTED = -606,
    //   Configurable
    // Not writeable
    ERR_FTP_BAD_COMMAND_SEQUENCE = -607,
    // Not enumerable
    // Not configurable
    ERR_PKCS12_IMPORT_BAD_PASSWORD = -701,

    ///
    // Post data elements may represent either bytes or files.
    ERR_PKCS12_IMPORT_FAILED = -702,
    ///
    ERR_IMPORT_CA_CERT_NOT_CA = -703,

    ///
    // Resource type for a request.
    ///

    ///
    // Top level page.
    ///

    ///
    // Frame or iframe.
    ///

    ///
    // CSS stylesheet.
    ERR_IMPORT_CERT_ALREADY_EXISTS = -704,
    ///

    ///
    // External script.
    ///

    ///
    // Image (jpg/gif/png/etc).
    ERR_IMPORT_CA_CERT_FAILED = -705,
    ///

    ///
    // Font.
    ///

    ///
    // Some other subresource. This is the default type if the actual type is
    ERR_IMPORT_SERVER_CERT_FAILED = -706,
    // unknown.
    ///
    ERR_PKCS12_IMPORT_INVALID_MAC = -707,

    ///
    // Object (or embed) tag for a plugin, or a resource that a plugin requested.
    ERR_PKCS12_IMPORT_INVALID_FILE = -708,
    ///

    ///
    // Media resource.
    ///

    ///
    // Main resource of a dedicated worker.
    ERR_PKCS12_IMPORT_UNSUPPORTED = -709,
    ///

    ///
    // Main resource of a shared worker.
    ERR_KEY_GENERATION_FAILED = -710,
    ///

    ///
    // Explicitly requested prefetch.
    ///

    ///
    // Favicon.
    ///
    ERR_PRIVATE_KEY_EXPORT_FAILED = -712,

    ///
    // XMLHttpRequest.
    ///

    ///
    // A request for a <ping>
    ///
    ERR_SELF_SIGNED_CERT_GENERATION_FAILED = -713,

    ///
    // Main resource of a service worker.
    ///

    ///
    // A report of Content Security Policy violations.
    ERR_CERT_DATABASE_CHANGED = -714,
    ///

    ///
    // A resource that a plugin requested.
    ///

    ///
    ERR_DNS_MALFORMED_RESPONSE = -800,
    // Transition type for a request. Made up of one source value and 0 or more
    ERR_DNS_SERVER_REQUIRES_TCP = -801,
    // qualifiers.
    ///

    ///
    // Source is a link click or the JavaScript window.open function. This is
    // also the default value for requests like sub-resource loads that are not
    // navigations.
    ///

    ///
    // Source is some other "explicit" navigation. This is the default value for
    // navigations where the actual type is unknown. See also TT_DIRECT_LOAD_FLAG.
    ///

    ///
    // Source is a subframe navigation. This is any content that is automatically
    ERR_DNS_SERVER_FAILED = -802,
    // loaded in a non-toplevel frame. For example, if a page consists of several
    ERR_DNS_TIMED_OUT = -803,
    // frames containing ads, those ad URLs will have this transition type.
    // The user may not even realize the content in these pages is a separate
    // frame, so may not care about the URL.
    ///

    ///
    // Source is a subframe navigation explicitly requested by the user that will
    ERR_DNS_CACHE_MISS = -804,
    // generate new navigation entries in the back/forward list. These are
    ERR_DNS_SEARCH_EMPTY = -805,
    // probably more important than frames that were automatically loaded in
    ERR_DNS_SORT_ERROR = -806,
    // the background because the user probably cares about the fact that this
    // link was loaded.
    ///
    ERR_DNS_SECURE_RESOLVER_HOSTNAME_RESOLUTION_FAILED = -808
}

enum cef_cert_status_t
{
    CERT_STATUS_NONE = 0,
    CERT_STATUS_COMMON_NAME_INVALID = 1 << 0,
    CERT_STATUS_DATE_INVALID = 1 << 1,
    CERT_STATUS_AUTHORITY_INVALID = 1 << 2,
    CERT_STATUS_NO_REVOCATION_MECHANISM = 1 << 4,
    CERT_STATUS_UNABLE_TO_CHECK_REVOCATION = 1 << 5,
    CERT_STATUS_REVOKED = 1 << 6,
    CERT_STATUS_INVALID = 1 << 7,
    CERT_STATUS_WEAK_SIGNATURE_ALGORITHM = 1 << 8,
    CERT_STATUS_NON_UNIQUE_NAME = 1 << 10,
    CERT_STATUS_WEAK_KEY = 1 << 11,
    CERT_STATUS_PINNED_KEY_MISSING = 1 << 13,
    CERT_STATUS_NAME_CONSTRAINT_VIOLATION = 1 << 14,
    CERT_STATUS_VALIDITY_TOO_LONG = 1 << 15,
    CERT_STATUS_IS_EV = 1 << 16,
    CERT_STATUS_REV_CHECKING_ENABLED = 1 << 17,
    CERT_STATUS_SHA1_SIGNATURE_PRESENT = 1 << 19,
    CERT_STATUS_CT_COMPLIANCE_FAILED = 1 << 20
}

enum cef_window_open_disposition_t
{
    WOD_UNKNOWN = 0,
    WOD_CURRENT_TAB = 1,
    WOD_SINGLETON_TAB = 2,
    WOD_NEW_FOREGROUND_TAB = 3,
    WOD_NEW_BACKGROUND_TAB = 4,
    WOD_NEW_POPUP = 5,
    WOD_NEW_WINDOW = 6,
    WOD_SAVE_TO_DISK = 7,
    WOD_OFF_THE_RECORD = 8,
    WOD_IGNORE_ACTION = 9
}

enum cef_drag_operations_mask_t
{
    DRAG_OPERATION_NONE = 0,
    DRAG_OPERATION_COPY = 1,
    DRAG_OPERATION_LINK = 2,
    DRAG_OPERATION_GENERIC = 4,
    DRAG_OPERATION_PRIVATE = 8,
    DRAG_OPERATION_MOVE = 16,
    DRAG_OPERATION_DELETE = 32,
    DRAG_OPERATION_EVERY = UINT_MAX
}

enum cef_text_input_mode_t
{
    CEF_TEXT_INPUT_MODE_DEFAULT = 0,
    CEF_TEXT_INPUT_MODE_NONE = 1,
    CEF_TEXT_INPUT_MODE_TEXT = 2,
    CEF_TEXT_INPUT_MODE_TEL = 3,
    CEF_TEXT_INPUT_MODE_URL = 4,
    CEF_TEXT_INPUT_MODE_EMAIL = 5,
    CEF_TEXT_INPUT_MODE_NUMERIC = 6,
    CEF_TEXT_INPUT_MODE_DECIMAL = 7,
    CEF_TEXT_INPUT_MODE_SEARCH = 8,
    CEF_TEXT_INPUT_MODE_MAX = CEF_TEXT_INPUT_MODE_SEARCH
}

enum cef_v8_accesscontrol_t
{
    V8_ACCESS_CONTROL_DEFAULT = 0,
    V8_ACCESS_CONTROL_ALL_CAN_READ = 1,
    V8_ACCESS_CONTROL_ALL_CAN_WRITE = 1 << 1,
    V8_ACCESS_CONTROL_PROHIBITS_OVERWRITING = 1 << 2
}

enum cef_v8_propertyattribute_t
{
    V8_PROPERTY_ATTRIBUTE_NONE = 0,
    V8_PROPERTY_ATTRIBUTE_READONLY = 1 << 0,
    V8_PROPERTY_ATTRIBUTE_DONTENUM = 1 << 1,
    V8_PROPERTY_ATTRIBUTE_DONTDELETE = 1 << 2
}

enum cef_postdataelement_type_t
{
    PDE_TYPE_EMPTY = 0,
    PDE_TYPE_BYTES = 1,
    PDE_TYPE_FILE = 2
}

enum cef_resource_type_t
{
    RT_MAIN_FRAME = 0,
    RT_SUB_FRAME = 1,
    RT_STYLESHEET = 2,
    RT_SCRIPT = 3,
    RT_IMAGE = 4,
    RT_FONT_RESOURCE = 5,
    RT_SUB_RESOURCE = 6,
    RT_OBJECT = 7,
    RT_MEDIA = 8,
    RT_WORKER = 9,
    RT_SHARED_WORKER = 10,
    RT_PREFETCH = 11,
    RT_FAVICON = 12,
    RT_XHR = 13,
    RT_PING = 14,
    RT_SERVICE_WORKER = 15,
    RT_CSP_REPORT = 16,
    RT_PLUGIN_RESOURCE = 17
}

enum cef_transition_type_t
{
    TT_LINK = 0,
    TT_EXPLICIT = 1,
    TT_AUTO_SUBFRAME = 3,
    TT_MANUAL_SUBFRAME = 4,

    ///
    // Source is a form submission by the user. NOTE: In some situations
    // submitting a form does not result in this transition type. This can happen
    // if the form uses a script to submit the contents.
    ///
    TT_FORM_SUBMIT = 7,

    ///
    // Source is a "reload" of the page via the Reload function or by re-visiting
    // the same URL. NOTE: This is distinct from the concept of whether a
    // particular load uses "reload semantics" (i.e. bypasses cached data).
    ///
    TT_RELOAD = 8,

    ///
    // General mask defining the bits used for the source values.
    ///
    TT_SOURCE_MASK = 0xFF,

    // Qualifiers.
    // Any of the core values above can be augmented by one or more qualifiers.
    // These qualifiers further define the transition.

    ///
    // Attempted to visit a URL but was blocked.
    ///
    TT_BLOCKED_FLAG = 0x00800000,

    ///
    // Used the Forward or Back function to navigate among browsing history.
    // Will be ORed to the transition type for the original load.
    ///
    TT_FORWARD_BACK_FLAG = 0x01000000,

    ///
    // Loaded a URL directly via CreateBrowser, LoadURL or LoadRequest.
    ///
    TT_DIRECT_LOAD_FLAG = 0x02000000,

    ///
    // The beginning of a navigation chain.
    ///
    TT_CHAIN_START_FLAG = 0x10000000,

    ///
    // The last transition in a redirect chain.
    ///
    TT_CHAIN_END_FLAG = 0x20000000,

    ///
    // Redirects caused by JavaScript or a meta refresh tag on the page.
    ///
    TT_CLIENT_REDIRECT_FLAG = 0x40000000,

    ///
    // Redirects sent from the server by HTTP headers.
    ///
    TT_SERVER_REDIRECT_FLAG = 0x80000000,

    ///
    // Used to test whether a transition involves a redirect.
    ///
    TT_IS_REDIRECT_MASK = 0xC0000000,

    ///
    // General mask defining the bits used for the qualifiers.
    ///
    TT_QUALIFIER_MASK = 0xFFFFFF00
}

///
// Flags used to customize the behavior of CefURLRequest.
///
enum cef_urlrequest_flags_t
{
    ///
    // Default behavior.
    ///
    UR_FLAG_NONE = 0,

    ///
    // If set the cache will be skipped when handling the request. Setting this
    // value is equivalent to specifying the "Cache-Control: no-cache" request
    // header. Setting this value in combination with UR_FLAG_ONLY_FROM_CACHE will
    // cause the request to fail.
    ///
    UR_FLAG_SKIP_CACHE = 1 << 0,

    ///
    // If set the request will fail if it cannot be served from the cache (or some
    // equivalent local store). Setting this value is equivalent to specifying the
    // "Cache-Control: only-if-cached" request header. Setting this value in
    // combination with UR_FLAG_SKIP_CACHE or UR_FLAG_DISABLE_CACHE will cause the
    // request to fail.
    ///
    UR_FLAG_ONLY_FROM_CACHE = 1 << 1,

    ///
    // If set the cache will not be used at all. Setting this value is equivalent
    // to specifying the "Cache-Control: no-store" request header. Setting this
    // value in combination with UR_FLAG_ONLY_FROM_CACHE will cause the request to
    // fail.
    ///
    UR_FLAG_DISABLE_CACHE = 1 << 2,

    ///
    // If set user name, password, and cookies may be sent with the request, and
    // cookies may be saved from the response.
    ///
    UR_FLAG_ALLOW_STORED_CREDENTIALS = 1 << 3,

    ///
    // If set upload progress events will be generated when a request has a body.
    ///
    UR_FLAG_REPORT_UPLOAD_PROGRESS = 1 << 4,

    ///
    // If set the CefURLRequestClient::OnDownloadData method will not be called.
    ///
    UR_FLAG_NO_DOWNLOAD_DATA = 1 << 5,

    ///
    // If set 5XX redirect errors will be propagated to the observer instead of
    // automatically re-tried. This currently only applies for requests
    // originated in the browser process.
    ///
    UR_FLAG_NO_RETRY_ON_5XX = 1 << 6,

    ///
    // If set 3XX responses will cause the fetch to halt immediately rather than
    // continue through the redirect.
    ///
    UR_FLAG_STOP_ON_REDIRECT = 1 << 7
}

///
// Flags that represent CefURLRequest status.
///
enum cef_urlrequest_status_t
{
    ///
    // Unknown status.
    ///
    UR_UNKNOWN = 0,

    ///
    // Request succeeded.
    ///
    UR_SUCCESS = 1,

    ///
    // An IO request is pending, and the caller will be informed when it is
    // completed.
    ///
    UR_IO_PENDING = 2,

    ///
    // Request was canceled programatically.
    ///
    UR_CANCELED = 3,

    ///
    // Request failed for some reason.
    ///
    UR_FAILED = 4
}

///
// Structure representing a point.
///
struct _cef_point_t
{
    int x;
    int y;
}

alias cef_point_t = _cef_point_t;

///
// Structure representing a rectangle.
///
struct _cef_rect_t
{
    int x;
    int y;
    int width;
    int height;
}

alias cef_rect_t = _cef_rect_t;

///
// Structure representing a size.
///
struct _cef_size_t
{
    int width;
    int height;
}

alias cef_size_t = _cef_size_t;

///
// Structure representing a range.
///
struct _cef_range_t
{
    int from;
    int to;
}

alias cef_range_t = _cef_range_t;

///
// Structure representing insets.
///
struct _cef_insets_t
{
    int top;
    int left;
    int bottom;
    int right;
}

alias cef_insets_t = _cef_insets_t;

///
// Structure representing a draggable region.
///
struct _cef_draggable_region_t
{
    ///
    // Bounds of the region.
    ///
    cef_rect_t bounds;

    ///
    // True (1) this this region is draggable and false (0) otherwise.
    ///
    int draggable;
}

alias cef_draggable_region_t = _cef_draggable_region_t;

///
// Existing process IDs.
///
enum cef_process_id_t
{
    ///
    // Browser process.
    ///
    PID_BROWSER = 0,
    ///
    // Renderer process.
    ///
    PID_RENDERER = 1
}

///
// Existing thread IDs.
///
enum cef_thread_id_t
{
    // BROWSER PROCESS THREADS -- Only available in the browser process.

    ///
    // The main thread in the browser. This will be the same as the main
    // application thread if CefInitialize() is called with a
    // CefSettings.multi_threaded_message_loop value of false. Do not perform
    // blocking tasks on this thread. All tasks posted after
    // CefBrowserProcessHandler::OnContextInitialized() and before CefShutdown()
    // are guaranteed to run. This thread will outlive all other CEF threads.
    ///
    TID_UI = 0,

    ///
    // Used for blocking tasks (e.g. file system access) where the user won't
    // notice if the task takes an arbitrarily long time to complete. All tasks
    // posted after CefBrowserProcessHandler::OnContextInitialized() and before
    // CefShutdown() are guaranteed to run.
    ///
    TID_FILE_BACKGROUND = 1,
    TID_FILE = TID_FILE_BACKGROUND,

    ///
    // Used for blocking tasks (e.g. file system access) that affect UI or
    // responsiveness of future user interactions. Do not use if an immediate
    // response to a user interaction is expected. All tasks posted after
    // CefBrowserProcessHandler::OnContextInitialized() and before CefShutdown()
    // are guaranteed to run.
    // Examples:
    // - Updating the UI to reflect progress on a long task.
    // - Loading data that might be shown in the UI after a future user
    //   interaction.
    ///
    TID_FILE_USER_VISIBLE = 2,

    ///
    // Used for blocking tasks (e.g. file system access) that affect UI
    // immediately after a user interaction. All tasks posted after
    // CefBrowserProcessHandler::OnContextInitialized() and before CefShutdown()
    // are guaranteed to run.
    // Example: Generating data shown in the UI immediately after a click.
    ///
    TID_FILE_USER_BLOCKING = 3,

    ///
    // Used to launch and terminate browser processes.
    ///
    TID_PROCESS_LAUNCHER = 4,

    ///
    // Used to process IPC and network messages. Do not perform blocking tasks on
    // this thread. All tasks posted after
    // CefBrowserProcessHandler::OnContextInitialized() and before CefShutdown()
    // are guaranteed to run.
    ///
    TID_IO = 5,

    // RENDER PROCESS THREADS -- Only available in the render process.

    ///
    // The main thread in the renderer. Used for all WebKit and V8 interaction.
    // Tasks may be posted to this thread after
    // CefRenderProcessHandler::OnWebKitInitialized but are not guaranteed to
    // run before sub-process termination (sub-processes may be killed at any time
    // without warning).
    ///
    TID_RENDERER = 6
}

///
// Thread priority values listed in increasing order of importance.
///
enum cef_thread_priority_t
{
    ///
    // Suitable for threads that shouldn't disrupt high priority work.
    ///
    TP_BACKGROUND = 0,

    ///
    // Default priority level.
    ///
    TP_NORMAL = 1,

    ///
    // Suitable for threads which generate data for the display (at ~60Hz).
    ///
    TP_DISPLAY = 2,

    ///
    // Suitable for low-latency, glitch-resistant audio.
    ///
    TP_REALTIME_AUDIO = 3
}

///
// Message loop types. Indicates the set of asynchronous events that a message
// loop can process.
///
enum cef_message_loop_type_t
{
    ///
    // Supports tasks and timers.
    ///
    ML_TYPE_DEFAULT = 0,

    ///
    // Supports tasks, timers and native UI events (e.g. Windows messages).
    ///
    ML_TYPE_UI = 1,

    ///
    // Supports tasks, timers and asynchronous IO events.
    ///
    ML_TYPE_IO = 2
}

///
// Windows COM initialization mode. Specifies how COM will be initialized for a
// new thread.
///
enum cef_com_init_mode_t
{
    ///
    // No COM initialization.
    ///
    COM_INIT_MODE_NONE = 0,

    ///
    // Initialize COM using single-threaded apartments.
    ///
    COM_INIT_MODE_STA = 1,

    ///
    // Initialize COM using multi-threaded apartments.
    ///
    COM_INIT_MODE_MTA = 2
}

///
// Supported value types.
///
enum cef_value_type_t
{
    VTYPE_INVALID = 0,
    VTYPE_NULL = 1,
    VTYPE_BOOL = 2,
    VTYPE_INT = 3,
    VTYPE_DOUBLE = 4,
    VTYPE_STRING = 5,
    VTYPE_BINARY = 6,
    VTYPE_DICTIONARY = 7,
    VTYPE_LIST = 8
}

///
// Supported JavaScript dialog types.
///
enum cef_jsdialog_type_t
{
    JSDIALOGTYPE_ALERT = 0,
    JSDIALOGTYPE_CONFIRM = 1,
    JSDIALOGTYPE_PROMPT = 2
}

///
// Screen information used when window rendering is disabled. This structure is
// passed as a parameter to CefRenderHandler::GetScreenInfo and should be filled
// in by the client.
///
struct _cef_screen_info_t
{
    ///
    // Device scale factor. Specifies the ratio between physical and logical
    // pixels.
    ///
    float device_scale_factor;

    ///
    // The screen depth in bits per pixel.
    ///
    int depth;

    ///
    // The bits per color component. This assumes that the colors are balanced
    // equally.
    ///
    int depth_per_component;

    ///
    // This can be true for black and white printers.
    ///
    int is_monochrome;

    ///
    // This is set from the rcMonitor member of MONITORINFOEX, to whit:
    //   "A RECT structure that specifies the display monitor rectangle,
    //   expressed in virtual-screen coordinates. Note that if the monitor
    //   is not the primary display monitor, some of the rectangle's
    //   coordinates may be negative values."
    //
    // The |rect| and |available_rect| properties are used to determine the
    // available surface for rendering popup views.
    ///
    cef_rect_t rect;

    ///
    // This is set from the rcWork member of MONITORINFOEX, to whit:
    //   "A RECT structure that specifies the work area rectangle of the
    //   display monitor that can be used by applications, expressed in
    //   virtual-screen coordinates. Windows uses this rectangle to
    //   maximize an application on the monitor. The rest of the area in
    //   rcMonitor contains system windows such as the task bar and side
    //   bars. Note that if the monitor is not the primary display monitor,
    //   some of the rectangle's coordinates may be negative values".
    //
    // The |rect| and |available_rect| properties are used to determine the
    // available surface for rendering popup views.
    ///
    cef_rect_t available_rect;
}

alias cef_screen_info_t = _cef_screen_info_t;

///
// Supported menu IDs. Non-English translations can be provided for the
// IDS_MENU_* strings in CefResourceBundleHandler::GetLocalizedString().
///
enum cef_menu_id_t
{
    // Navigation.
    MENU_ID_BACK = 100,
    MENU_ID_FORWARD = 101,
    MENU_ID_RELOAD = 102,
    MENU_ID_RELOAD_NOCACHE = 103,
    MENU_ID_STOPLOAD = 104,

    // Editing.
    MENU_ID_UNDO = 110,
    MENU_ID_REDO = 111,
    MENU_ID_CUT = 112,
    MENU_ID_COPY = 113,
    MENU_ID_PASTE = 114,
    MENU_ID_DELETE = 115,
    MENU_ID_SELECT_ALL = 116,

    // Miscellaneous.
    MENU_ID_FIND = 130,
    MENU_ID_PRINT = 131,
    MENU_ID_VIEW_SOURCE = 132,

    // Spell checking word correction suggestions.
    MENU_ID_SPELLCHECK_SUGGESTION_0 = 200,
    MENU_ID_SPELLCHECK_SUGGESTION_1 = 201,
    MENU_ID_SPELLCHECK_SUGGESTION_2 = 202,
    MENU_ID_SPELLCHECK_SUGGESTION_3 = 203,
    MENU_ID_SPELLCHECK_SUGGESTION_4 = 204,
    MENU_ID_SPELLCHECK_SUGGESTION_LAST = 204,
    MENU_ID_NO_SPELLING_SUGGESTIONS = 205,
    MENU_ID_ADD_TO_DICTIONARY = 206,

    // Custom menu items originating from the renderer process. For example,
    // plugin placeholder menu items or Flash menu items.
    MENU_ID_CUSTOM_FIRST = 220,
    MENU_ID_CUSTOM_LAST = 250,

    // All user-defined menu IDs should come between MENU_ID_USER_FIRST and
    // MENU_ID_USER_LAST to avoid overlapping the Chromium and CEF ID ranges
    // defined in the tools/gritsettings/resource_ids file.
    MENU_ID_USER_FIRST = 26500,
    MENU_ID_USER_LAST = 28500
}

///
// Mouse button types.
///
enum cef_mouse_button_type_t
{
    MBT_LEFT = 0,
    MBT_MIDDLE = 1,
    MBT_RIGHT = 2
}

///
// Structure representing mouse event information.
///
struct _cef_mouse_event_t
{
    ///
    // X coordinate relative to the left side of the view.
    ///
    int x;

    ///
    // Y coordinate relative to the top side of the view.
    ///
    int y;

    ///
    // Bit flags describing any pressed modifier keys. See
    // cef_event_flags_t for values.
    ///
    uint32 modifiers;
}

alias cef_mouse_event_t = _cef_mouse_event_t;

///
// Touch points states types.
///
enum cef_touch_event_type_t
{
    CEF_TET_RELEASED = 0,
    CEF_TET_PRESSED = 1,
    CEF_TET_MOVED = 2,
    CEF_TET_CANCELLED = 3
}

///
// The device type that caused the event.
///
enum cef_pointer_type_t
{
    CEF_POINTER_TYPE_TOUCH = 0,
    CEF_POINTER_TYPE_MOUSE = 1,
    CEF_POINTER_TYPE_PEN = 2,
    CEF_POINTER_TYPE_ERASER = 3,
    CEF_POINTER_TYPE_UNKNOWN = 4
}

///
// Structure representing touch event information.
///
struct _cef_touch_event_t
{
    ///
    // Id of a touch point. Must be unique per touch, can be any number except -1.
    // Note that a maximum of 16 concurrent touches will be tracked; touches
    // beyond that will be ignored.
    ///
    int id;

    ///
    // X coordinate relative to the left side of the view.
    ///
    float x;

    ///
    // Y coordinate relative to the top side of the view.
    ///
    float y;

    ///
    // X radius in pixels. Set to 0 if not applicable.
    ///
    float radius_x;

    ///
    // Y radius in pixels. Set to 0 if not applicable.
    ///
    float radius_y;

    ///
    // Rotation angle in radians. Set to 0 if not applicable.
    ///
    float rotation_angle;

    ///
    // The normalized pressure of the pointer input in the range of [0,1].
    // Set to 0 if not applicable.
    ///
    float pressure;

    ///
    // The state of the touch point. Touches begin with one CEF_TET_PRESSED event
    // followed by zero or more CEF_TET_MOVED events and finally one
    // CEF_TET_RELEASED or CEF_TET_CANCELLED event. Events not respecting this
    // order will be ignored.
    ///
    cef_touch_event_type_t type;

    ///
    // Bit flags describing any pressed modifier keys. See
    // cef_event_flags_t for values.
    ///
    uint32 modifiers;

    ///
    // The device type that caused the event.
    ///
    cef_pointer_type_t pointer_type;
}

alias cef_touch_event_t = _cef_touch_event_t;

///
// Paint element types.
///
enum cef_paint_element_type_t
{
    PET_VIEW = 0,
    PET_POPUP = 1
}

///
// Supported event bit flags.
///
enum cef_event_flags_t
{
    EVENTFLAG_NONE = 0,
    EVENTFLAG_CAPS_LOCK_ON = 1 << 0,
    EVENTFLAG_SHIFT_DOWN = 1 << 1,
    EVENTFLAG_CONTROL_DOWN = 1 << 2,
    EVENTFLAG_ALT_DOWN = 1 << 3,
    EVENTFLAG_LEFT_MOUSE_BUTTON = 1 << 4,
    EVENTFLAG_MIDDLE_MOUSE_BUTTON = 1 << 5,
    EVENTFLAG_RIGHT_MOUSE_BUTTON = 1 << 6,
    // Mac OS-X command key.
    EVENTFLAG_COMMAND_DOWN = 1 << 7,
    EVENTFLAG_NUM_LOCK_ON = 1 << 8,
    EVENTFLAG_IS_KEY_PAD = 1 << 9,
    EVENTFLAG_IS_LEFT = 1 << 10,
    EVENTFLAG_IS_RIGHT = 1 << 11,
    EVENTFLAG_ALTGR_DOWN = 1 << 12
}

///
// Supported menu item types.
///
enum cef_menu_item_type_t
{
    MENUITEMTYPE_NONE = 0,
    MENUITEMTYPE_COMMAND = 1,
    MENUITEMTYPE_CHECK = 2,
    MENUITEMTYPE_RADIO = 3,
    MENUITEMTYPE_SEPARATOR = 4,
    MENUITEMTYPE_SUBMENU = 5
}

///
// Supported context menu type flags.
///
enum cef_context_menu_type_flags_t
{
    ///
    // No node is selected.
    ///
    CM_TYPEFLAG_NONE = 0,
    ///
    // The top page is selected.
    ///
    CM_TYPEFLAG_PAGE = 1 << 0,
    ///
    // A subframe page is selected.
    ///
    CM_TYPEFLAG_FRAME = 1 << 1,
    ///
    // A link is selected.
    ///
    CM_TYPEFLAG_LINK = 1 << 2,
    ///
    // A media node is selected.
    ///
    CM_TYPEFLAG_MEDIA = 1 << 3,
    ///
    // There is a textual or mixed selection that is selected.
    ///
    CM_TYPEFLAG_SELECTION = 1 << 4,
    ///
    // An editable element is selected.
    ///
    CM_TYPEFLAG_EDITABLE = 1 << 5
}

///
// Supported context menu media types.
///
enum cef_context_menu_media_type_t
{
    ///
    // No special node is in context.
    ///
    CM_MEDIATYPE_NONE = 0,
    ///
    // An image node is selected.
    ///
    CM_MEDIATYPE_IMAGE = 1,
    ///
    // A video node is selected.
    ///
    CM_MEDIATYPE_VIDEO = 2,
    ///
    // An audio node is selected.
    ///
    CM_MEDIATYPE_AUDIO = 3,
    ///
    // A file node is selected.
    ///
    CM_MEDIATYPE_FILE = 4,
    ///
    // A plugin node is selected.
    ///
    CM_MEDIATYPE_PLUGIN = 5
}

///
// Supported context menu media state bit flags.
///
enum cef_context_menu_media_state_flags_t
{
    CM_MEDIAFLAG_NONE = 0,
    CM_MEDIAFLAG_ERROR = 1 << 0,
    CM_MEDIAFLAG_PAUSED = 1 << 1,
    CM_MEDIAFLAG_MUTED = 1 << 2,
    CM_MEDIAFLAG_LOOP = 1 << 3,
    CM_MEDIAFLAG_CAN_SAVE = 1 << 4,
    CM_MEDIAFLAG_HAS_AUDIO = 1 << 5,
    CM_MEDIAFLAG_HAS_VIDEO = 1 << 6,
    CM_MEDIAFLAG_CONTROL_ROOT_ELEMENT = 1 << 7,
    CM_MEDIAFLAG_CAN_PRINT = 1 << 8,
    CM_MEDIAFLAG_CAN_ROTATE = 1 << 9
}

///
// Supported context menu edit state bit flags.
///
enum cef_context_menu_edit_state_flags_t
{
    CM_EDITFLAG_NONE = 0,
    CM_EDITFLAG_CAN_UNDO = 1 << 0,
    CM_EDITFLAG_CAN_REDO = 1 << 1,
    CM_EDITFLAG_CAN_CUT = 1 << 2,
    CM_EDITFLAG_CAN_COPY = 1 << 3,
    CM_EDITFLAG_CAN_PASTE = 1 << 4,
    CM_EDITFLAG_CAN_DELETE = 1 << 5,
    CM_EDITFLAG_CAN_SELECT_ALL = 1 << 6,
    CM_EDITFLAG_CAN_TRANSLATE = 1 << 7
}

///
// Key event types.
///
enum cef_key_event_type_t
{
    ///
    // Notification that a key transitioned from "up" to "down".
    ///
    KEYEVENT_RAWKEYDOWN = 0,

    ///
    // Notification that a key was pressed. This does not necessarily correspond
    // to a character depending on the key and language. Use KEYEVENT_CHAR for
    // character input.
    ///
    KEYEVENT_KEYDOWN = 1,

    ///
    // Notification that a key was released.
    ///
    KEYEVENT_KEYUP = 2,

    ///
    // Notification that a character was typed. Use this for text input. Key
    // down events may generate 0, 1, or more than one character event depending
    // on the key, locale, and operating system.
    ///
    KEYEVENT_CHAR = 3
}

///
// Structure representing keyboard event information.
///
struct _cef_key_event_t
{
    ///
    // The type of keyboard event.
    ///
    cef_key_event_type_t type;

    ///
    // Bit flags describing any pressed modifier keys. See
    // cef_event_flags_t for values.
    ///
    uint32 modifiers;

    ///
    // The Windows key code for the key event. This value is used by the DOM
    // specification. Sometimes it comes directly from the event (i.e. on
    // Windows) and sometimes it's determined using a mapping function. See
    // WebCore/platform/chromium/KeyboardCodes.h for the list of values.
    ///
    int windows_key_code;

    ///
    // The actual key code genenerated by the platform.
    ///
    int native_key_code;

    ///
    // Indicates whether the event is considered a "system key" event (see
    // http://msdn.microsoft.com/en-us/library/ms646286(VS.85).aspx for details).
    // This value will always be false on non-Windows platforms.
    ///
    int is_system_key;

    ///
    // The character generated by the keystroke.
    ///
    char16 character;

    ///
    // Same as |character| but unmodified by any concurrently-held modifiers
    // (except shift). This is useful for working out shortcut keys.
    ///
    char16 unmodified_character;

    ///
    // True if the focus is currently on an editable field on the page. This is
    // useful for determining if standard key events should be intercepted.
    ///
    int focus_on_editable_field;
}

alias cef_key_event_t = _cef_key_event_t;

///
// Focus sources.
///
enum cef_focus_source_t
{
    ///
    // The source is explicit navigation via the API (LoadURL(), etc).
    ///
    FOCUS_SOURCE_NAVIGATION = 0,
    ///
    // The source is a system-generated focus event.
    ///
    FOCUS_SOURCE_SYSTEM = 1
}

///
// Navigation types.
///
enum cef_navigation_type_t
{
    NAVIGATION_LINK_CLICKED = 0,
    NAVIGATION_FORM_SUBMITTED = 1,
    NAVIGATION_BACK_FORWARD = 2,
    NAVIGATION_RELOAD = 3,
    NAVIGATION_FORM_RESUBMITTED = 4,
    NAVIGATION_OTHER = 5
}

///
// Supported XML encoding types. The parser supports ASCII, ISO-8859-1, and
// UTF16 (LE and BE) by default. All other types must be translated to UTF8
// before being passed to the parser. If a BOM is detected and the correct
// decoder is available then that decoder will be used automatically.
///
enum cef_xml_encoding_type_t
{
    XML_ENCODING_NONE = 0,
    XML_ENCODING_UTF8 = 1,
    XML_ENCODING_UTF16LE = 2,
    XML_ENCODING_UTF16BE = 3,
    XML_ENCODING_ASCII = 4
}

///
// XML node types.
///
enum cef_xml_node_type_t
{
    XML_NODE_UNSUPPORTED = 0,
    XML_NODE_PROCESSING_INSTRUCTION = 1,
    XML_NODE_DOCUMENT_TYPE = 2,
    XML_NODE_ELEMENT_START = 3,
    XML_NODE_ELEMENT_END = 4,
    XML_NODE_ATTRIBUTE = 5,
    XML_NODE_TEXT = 6,
    XML_NODE_CDATA = 7,
    XML_NODE_ENTITY_REFERENCE = 8,
    XML_NODE_WHITESPACE = 9,
    XML_NODE_COMMENT = 10
}

///
// Popup window features.
///
struct _cef_popup_features_t
{
    int x;
    int xSet;
    int y;
    int ySet;
    int width;
    int widthSet;
    int height;
    int heightSet;

    int menuBarVisible;
    int statusBarVisible;
    int toolBarVisible;
    int scrollbarsVisible;
}

alias cef_popup_features_t = _cef_popup_features_t;

///
// DOM document types.
///
enum cef_dom_document_type_t
{
    DOM_DOCUMENT_TYPE_UNKNOWN = 0,
    DOM_DOCUMENT_TYPE_HTML = 1,
    DOM_DOCUMENT_TYPE_XHTML = 2,
    DOM_DOCUMENT_TYPE_PLUGIN = 3
}

///
// DOM event category flags.
///
enum cef_dom_event_category_t
{
    DOM_EVENT_CATEGORY_UNKNOWN = 0x0,
    DOM_EVENT_CATEGORY_UI = 0x1,
    DOM_EVENT_CATEGORY_MOUSE = 0x2,
    DOM_EVENT_CATEGORY_MUTATION = 0x4,
    DOM_EVENT_CATEGORY_KEYBOARD = 0x8,
    DOM_EVENT_CATEGORY_TEXT = 0x10,
    DOM_EVENT_CATEGORY_COMPOSITION = 0x20,
    DOM_EVENT_CATEGORY_DRAG = 0x40,
    DOM_EVENT_CATEGORY_CLIPBOARD = 0x80,
    DOM_EVENT_CATEGORY_MESSAGE = 0x100,
    DOM_EVENT_CATEGORY_WHEEL = 0x200,
    DOM_EVENT_CATEGORY_BEFORE_TEXT_INSERTED = 0x400,
    DOM_EVENT_CATEGORY_OVERFLOW = 0x800,
    DOM_EVENT_CATEGORY_PAGE_TRANSITION = 0x1000,
    DOM_EVENT_CATEGORY_POPSTATE = 0x2000,
    DOM_EVENT_CATEGORY_PROGRESS = 0x4000,
    DOM_EVENT_CATEGORY_XMLHTTPREQUEST_PROGRESS = 0x8000
}

///
// DOM event processing phases.
///
enum cef_dom_event_phase_t
{
    DOM_EVENT_PHASE_UNKNOWN = 0,
    DOM_EVENT_PHASE_CAPTURING = 1,
    DOM_EVENT_PHASE_AT_TARGET = 2,
    DOM_EVENT_PHASE_BUBBLING = 3
}

///
// DOM node types.
///
enum cef_dom_node_type_t
{
    DOM_NODE_TYPE_UNSUPPORTED = 0,
    DOM_NODE_TYPE_ELEMENT = 1,
    DOM_NODE_TYPE_ATTRIBUTE = 2,
    DOM_NODE_TYPE_TEXT = 3,
    DOM_NODE_TYPE_CDATA_SECTION = 4,
    DOM_NODE_TYPE_PROCESSING_INSTRUCTIONS = 5,
    DOM_NODE_TYPE_COMMENT = 6,
    DOM_NODE_TYPE_DOCUMENT = 7,
    DOM_NODE_TYPE_DOCUMENT_TYPE = 8,
    DOM_NODE_TYPE_DOCUMENT_FRAGMENT = 9
}

///
// Supported file dialog modes.
///
enum cef_file_dialog_mode_t
{
    ///
    // Requires that the file exists before allowing the user to pick it.
    ///
    FILE_DIALOG_OPEN = 0,

    ///
    // Like Open, but allows picking multiple files to open.
    ///
    FILE_DIALOG_OPEN_MULTIPLE = 1,

    ///
    // Like Open, but selects a folder to open.
    ///
    FILE_DIALOG_OPEN_FOLDER = 2,

    ///
    // Allows picking a nonexistent file, and prompts to overwrite if the file
    // already exists.
    ///
    FILE_DIALOG_SAVE = 3,

    ///
    // General mask defining the bits used for the type values.
    ///
    FILE_DIALOG_TYPE_MASK = 0xFF,

    // Qualifiers.
    // Any of the type values above can be augmented by one or more qualifiers.
    // These qualifiers further define the dialog behavior.

    ///
    // Prompt to overwrite if the user selects an existing file with the Save
    // dialog.
    ///
    FILE_DIALOG_OVERWRITEPROMPT_FLAG = 0x01000000,

    ///
    // Do not display read-only files.
    ///
    FILE_DIALOG_HIDEREADONLY_FLAG = 0x02000000
}

///
// Print job color mode values.
///
enum cef_color_model_t
{
    COLOR_MODEL_UNKNOWN = 0,
    COLOR_MODEL_GRAY = 1,
    COLOR_MODEL_COLOR = 2,
    COLOR_MODEL_CMYK = 3,
    COLOR_MODEL_CMY = 4,
    COLOR_MODEL_KCMY = 5,
    COLOR_MODEL_CMY_K = 6, // CMY_K represents CMY+K.
    COLOR_MODEL_BLACK = 7,
    COLOR_MODEL_GRAYSCALE = 8,
    COLOR_MODEL_RGB = 9,
    COLOR_MODEL_RGB16 = 10,
    COLOR_MODEL_RGBA = 11,
    COLOR_MODEL_COLORMODE_COLOR = 12, // Used in samsung printer ppds.
    COLOR_MODEL_COLORMODE_MONOCHROME = 13, // Used in samsung printer ppds.
    COLOR_MODEL_HP_COLOR_COLOR = 14, // Used in HP color printer ppds.
    COLOR_MODEL_HP_COLOR_BLACK = 15, // Used in HP color printer ppds.
    COLOR_MODEL_PRINTOUTMODE_NORMAL = 16, // Used in foomatic ppds.
    COLOR_MODEL_PRINTOUTMODE_NORMAL_GRAY = 17, // Used in foomatic ppds.
    COLOR_MODEL_PROCESSCOLORMODEL_CMYK = 18, // Used in canon printer ppds.
    COLOR_MODEL_PROCESSCOLORMODEL_GREYSCALE = 19, // Used in canon printer ppds.
    COLOR_MODEL_PROCESSCOLORMODEL_RGB = 20 // Used in canon printer ppds
}

///
// Print job duplex mode values.
///
enum cef_duplex_mode_t
{
    DUPLEX_MODE_UNKNOWN = -1,
    DUPLEX_MODE_SIMPLEX = 0,
    DUPLEX_MODE_LONG_EDGE = 1,
    DUPLEX_MODE_SHORT_EDGE = 2
}

///
// Cursor type values.
///
enum cef_cursor_type_t
{
    CT_POINTER = 0,
    CT_CROSS = 1,
    CT_HAND = 2,
    CT_IBEAM = 3,
    CT_WAIT = 4,
    CT_HELP = 5,
    CT_EASTRESIZE = 6,
    CT_NORTHRESIZE = 7,
    CT_NORTHEASTRESIZE = 8,
    CT_NORTHWESTRESIZE = 9,
    CT_SOUTHRESIZE = 10,
    CT_SOUTHEASTRESIZE = 11,
    CT_SOUTHWESTRESIZE = 12,
    CT_WESTRESIZE = 13,
    CT_NORTHSOUTHRESIZE = 14,
    CT_EASTWESTRESIZE = 15,
    CT_NORTHEASTSOUTHWESTRESIZE = 16,
    CT_NORTHWESTSOUTHEASTRESIZE = 17,
    CT_COLUMNRESIZE = 18,
    CT_ROWRESIZE = 19,
    CT_MIDDLEPANNING = 20,
    CT_EASTPANNING = 21,
    CT_NORTHPANNING = 22,
    CT_NORTHEASTPANNING = 23,
    CT_NORTHWESTPANNING = 24,
    CT_SOUTHPANNING = 25,
    CT_SOUTHEASTPANNING = 26,
    CT_SOUTHWESTPANNING = 27,
    CT_WESTPANNING = 28,
    CT_MOVE = 29,
    CT_VERTICALTEXT = 30,
    CT_CELL = 31,
    CT_CONTEXTMENU = 32,
    CT_ALIAS = 33,
    CT_PROGRESS = 34,
    CT_NODROP = 35,
    CT_COPY = 36,
    CT_NONE = 37,
    CT_NOTALLOWED = 38,
    CT_ZOOMIN = 39,
    CT_ZOOMOUT = 40,
    CT_GRAB = 41,
    CT_GRABBING = 42,
    CT_MIDDLE_PANNING_VERTICAL = 43,
    CT_MIDDLE_PANNING_HORIZONTAL = 44,
    CT_CUSTOM = 45,
    CT_DND_NONE = 46,
    CT_DND_MOVE = 47,
    CT_DND_COPY = 48,
    CT_DND_LINK = 49
}

///
// Structure representing cursor information. |buffer| will be
// |size.width|*|size.height|*4 bytes in size and represents a BGRA image with
// an upper-left origin.
///
struct _cef_cursor_info_t
{
    cef_point_t hotspot;
    float image_scale_factor;
    void* buffer;
    cef_size_t size;
}

alias cef_cursor_info_t = _cef_cursor_info_t;

///
// URI unescape rules passed to CefURIDecode().
///
enum cef_uri_unescape_rule_t
{
    ///
    // Don't unescape anything at all.
    ///
    UU_NONE = 0,

    ///
    // Don't unescape anything special, but all normal unescaping will happen.
    // This is a placeholder and can't be combined with other flags (since it's
    // just the absence of them). All other unescape rules imply "normal" in
    // addition to their special meaning. Things like escaped letters, digits,
    // and most symbols will get unescaped with this mode.
    ///
    UU_NORMAL = 1 << 0,

    ///
    // Convert %20 to spaces. In some places where we're showing URLs, we may
    // want this. In places where the URL may be copied and pasted out, then
    // you wouldn't want this since it might not be interpreted in one piece
    // by other applications.
    ///
    UU_SPACES = 1 << 1,

    ///
    // Unescapes '/' and '\\'. If these characters were unescaped, the resulting
    // URL won't be the same as the source one. Moreover, they are dangerous to
    // unescape in strings that will be used as file paths or names. This value
    // should only be used when slashes don't have special meaning, like data
    // URLs.
    ///
    UU_PATH_SEPARATORS = 1 << 2,

    ///
    // Unescapes various characters that will change the meaning of URLs,
    // including '%', '+', '&', '#'. Does not unescape path separators.
    // If these characters were unescaped, the resulting URL won't be the same
    // as the source one. This flag is used when generating final output like
    // filenames for URLs where we won't be interpreting as a URL and want to do
    // as much unescaping as possible.
    ///
    UU_URL_SPECIAL_CHARS_EXCEPT_PATH_SEPARATORS = 1 << 3,

    ///
    // URL queries use "+" for space. This flag controls that replacement.
    ///
    UU_REPLACE_PLUS_WITH_SPACE = 1 << 4
}

///
// Options that can be passed to CefParseJSON.
///
enum cef_json_parser_options_t
{
    ///
    // Parses the input strictly according to RFC 4627. See comments in Chromium's
    // base/json/json_reader.h file for known limitations/deviations from the RFC.
    ///
    JSON_PARSER_RFC = 0,

    ///
    // Allows commas to exist after the last element in structures.
    ///
    JSON_PARSER_ALLOW_TRAILING_COMMAS = 1 << 0
}

///
// Options that can be passed to CefWriteJSON.
///
enum cef_json_writer_options_t
{
    ///
    // Default behavior.
    ///
    JSON_WRITER_DEFAULT = 0,

    ///
    // This option instructs the writer that if a Binary value is encountered,
    // the value (and key if within a dictionary) will be omitted from the
    // output, and success will be returned. Otherwise, if a binary value is
    // encountered, failure will be returned.
    ///
    JSON_WRITER_OMIT_BINARY_VALUES = 1 << 0,

    ///
    // This option instructs the writer to write doubles that have no fractional
    // part as a normal integer (i.e., without using exponential notation
    // or appending a '.0') as long as the value is within the range of a
    // 64-bit int.
    ///
    JSON_WRITER_OMIT_DOUBLE_TYPE_PRESERVATION = 1 << 1,

    ///
    // Return a slightly nicer formatted json string (pads with whitespace to
    // help with readability).
    ///
    JSON_WRITER_PRETTY_PRINT = 1 << 2
}

///
// Margin type for PDF printing.
///
enum cef_pdf_print_margin_type_t
{
    ///
    // Default margins.
    ///
    PDF_PRINT_MARGIN_DEFAULT = 0,

    ///
    // No margins.
    ///
    PDF_PRINT_MARGIN_NONE = 1,

    ///
    // Minimum margins.
    ///
    PDF_PRINT_MARGIN_MINIMUM = 2,

    ///
    // Custom margins using the |margin_*| values from cef_pdf_print_settings_t.
    ///
    PDF_PRINT_MARGIN_CUSTOM = 3
}

///
// Structure representing PDF print settings.
///
struct _cef_pdf_print_settings_t
{
    ///
    // Page title to display in the header. Only used if |header_footer_enabled|
    // is set to true (1).
    ///
    cef_string_t header_footer_title;

    ///
    // URL to display in the footer. Only used if |header_footer_enabled| is set
    // to true (1).
    ///
    cef_string_t header_footer_url;

    ///
    // Output page size in microns. If either of these values is less than or
    // equal to zero then the default paper size (A4) will be used.
    ///
    int page_width;
    int page_height;

    ///
    // The percentage to scale the PDF by before printing (e.g. 50 is 50%).
    // If this value is less than or equal to zero the default value of 100
    // will be used.
    ///
    int scale_factor;

    ///
    // Margins in points. Only used if |margin_type| is set to
    // PDF_PRINT_MARGIN_CUSTOM.
    ///
    int margin_top;
    int margin_right;
    int margin_bottom;
    int margin_left;

    ///
    // Margin type.
    ///
    cef_pdf_print_margin_type_t margin_type;

    ///
    // Set to true (1) to print headers and footers or false (0) to not print
    // headers and footers.
    ///
    int header_footer_enabled;

    ///
    // Set to true (1) to print the selection only or false (0) to print all.
    ///
    int selection_only;

    ///
    // Set to true (1) for landscape mode or false (0) for portrait mode.
    ///
    int landscape;

    ///
    // Set to true (1) to print background graphics or false (0) to not print
    // background graphics.
    ///
    int backgrounds_enabled;
}

alias cef_pdf_print_settings_t = _cef_pdf_print_settings_t;

///
// Supported UI scale factors for the platform. SCALE_FACTOR_NONE is used for
// density independent resources such as string, html/js files or an image that
// can be used for any scale factors (such as wallpapers).
///
enum cef_scale_factor_t
{
    SCALE_FACTOR_NONE = 0,
    SCALE_FACTOR_100P = 1,
    SCALE_FACTOR_125P = 2,
    SCALE_FACTOR_133P = 3,
    SCALE_FACTOR_140P = 4,
    SCALE_FACTOR_150P = 5,
    SCALE_FACTOR_180P = 6,
    SCALE_FACTOR_200P = 7,
    SCALE_FACTOR_250P = 8,
    SCALE_FACTOR_300P = 9
}

///
// Plugin policies supported by CefRequestContextHandler::OnBeforePluginLoad.
///
enum cef_plugin_policy_t
{
    ///
    // Allow the content.
    ///
    PLUGIN_POLICY_ALLOW = 0,

    ///
    // Allow important content and block unimportant content based on heuristics.
    // The user can manually load blocked content.
    ///
    PLUGIN_POLICY_DETECT_IMPORTANT = 1,

    ///
    // Block the content. The user can manually load blocked content.
    ///
    PLUGIN_POLICY_BLOCK = 2,

    ///
    // Disable the content. The user cannot load disabled content.
    ///
    PLUGIN_POLICY_DISABLE = 3
}

///
// Policy for how the Referrer HTTP header value will be sent during navigation.
// If the `--no-referrers` command-line flag is specified then the policy value
// will be ignored and the Referrer value will never be sent.
// Must be kept synchronized with net::URLRequest::ReferrerPolicy from Chromium.
///
enum cef_referrer_policy_t
{
    ///
    // Clear the referrer header if the header value is HTTPS but the request
    // destination is HTTP. This is the default behavior.
    ///
    REFERRER_POLICY_CLEAR_REFERRER_ON_TRANSITION_FROM_SECURE_TO_INSECURE = 0,
    REFERRER_POLICY_DEFAULT = REFERRER_POLICY_CLEAR_REFERRER_ON_TRANSITION_FROM_SECURE_TO_INSECURE,

    ///
    // A slight variant on CLEAR_REFERRER_ON_TRANSITION_FROM_SECURE_TO_INSECURE:
    // If the request destination is HTTP, an HTTPS referrer will be cleared. If
    // the request's destination is cross-origin with the referrer (but does not
    // downgrade), the referrer's granularity will be stripped down to an origin
    // rather than a full URL. Same-origin requests will send the full referrer.
    ///
    REFERRER_POLICY_REDUCE_REFERRER_GRANULARITY_ON_TRANSITION_CROSS_ORIGIN = 1,

    ///
    // Strip the referrer down to an origin when the origin of the referrer is
    // different from the destination's origin.
    ///
    REFERRER_POLICY_ORIGIN_ONLY_ON_TRANSITION_CROSS_ORIGIN = 2,

    ///
    // Never change the referrer.
    ///
    REFERRER_POLICY_NEVER_CLEAR_REFERRER = 3,

    ///
    // Strip the referrer down to the origin regardless of the redirect location.
    ///
    REFERRER_POLICY_ORIGIN = 4,

    ///
    // Clear the referrer when the request's referrer is cross-origin with the
    // request's destination.
    ///
    REFERRER_POLICY_CLEAR_REFERRER_ON_TRANSITION_CROSS_ORIGIN = 5,

    ///
    // Strip the referrer down to the origin, but clear it entirely if the
    // referrer value is HTTPS and the destination is HTTP.
    ///
    REFERRER_POLICY_ORIGIN_CLEAR_ON_TRANSITION_FROM_SECURE_TO_INSECURE = 6,

    ///
    // Always clear the referrer regardless of the request destination.
    ///
    REFERRER_POLICY_NO_REFERRER = 7,

    // Always the last value in this enumeration.
    REFERRER_POLICY_LAST_VALUE = REFERRER_POLICY_NO_REFERRER
}

///
// Return values for CefResponseFilter::Filter().
///
enum cef_response_filter_status_t
{
    ///
    // Some or all of the pre-filter data was read successfully but more data is
    // needed in order to continue filtering (filtered output is pending).
    ///
    RESPONSE_FILTER_NEED_MORE_DATA = 0,

    ///
    // Some or all of the pre-filter data was read successfully and all available
    // filtered output has been written.
    ///
    RESPONSE_FILTER_DONE = 1,

    ///
    // An error occurred during filtering.
    ///
    RESPONSE_FILTER_ERROR = 2
}

///
// Describes how to interpret the components of a pixel.
///
enum cef_color_type_t
{
    ///
    // RGBA with 8 bits per pixel (32bits total).
    ///
    CEF_COLOR_TYPE_RGBA_8888 = 0,

    ///
    // BGRA with 8 bits per pixel (32bits total).
    ///
    CEF_COLOR_TYPE_BGRA_8888 = 1
}

///
// Describes how to interpret the alpha component of a pixel.
///
enum cef_alpha_type_t
{
    ///
    // No transparency. The alpha component is ignored.
    ///
    CEF_ALPHA_TYPE_OPAQUE = 0,

    ///
    // Transparency with pre-multiplied alpha component.
    ///
    CEF_ALPHA_TYPE_PREMULTIPLIED = 1,

    ///
    // Transparency with post-multiplied alpha component.
    ///
    CEF_ALPHA_TYPE_POSTMULTIPLIED = 2
}

///
// Text style types. Should be kepy in sync with gfx::TextStyle.
///
enum cef_text_style_t
{
    CEF_TEXT_STYLE_BOLD = 0,
    CEF_TEXT_STYLE_ITALIC = 1,
    CEF_TEXT_STYLE_STRIKE = 2,
    CEF_TEXT_STYLE_DIAGONAL_STRIKE = 3,
    CEF_TEXT_STYLE_UNDERLINE = 4
}

///
// Specifies where along the main axis the CefBoxLayout child views should be
// laid out.
///
enum cef_main_axis_alignment_t
{
    ///
    // Child views will be left-aligned.
    ///
    CEF_MAIN_AXIS_ALIGNMENT_START = 0,

    ///
    // Child views will be center-aligned.
    ///
    CEF_MAIN_AXIS_ALIGNMENT_CENTER = 1,

    ///
    // Child views will be right-aligned.
    ///
    CEF_MAIN_AXIS_ALIGNMENT_END = 2
}

///
// Specifies where along the cross axis the CefBoxLayout child views should be
// laid out.
///
enum cef_cross_axis_alignment_t
{
    ///
    // Child views will be stretched to fit.
    ///
    CEF_CROSS_AXIS_ALIGNMENT_STRETCH = 0,

    ///
    // Child views will be left-aligned.
    ///
    CEF_CROSS_AXIS_ALIGNMENT_START = 1,

    ///
    // Child views will be center-aligned.
    ///
    CEF_CROSS_AXIS_ALIGNMENT_CENTER = 2,

    ///
    // Child views will be right-aligned.
    ///
    CEF_CROSS_AXIS_ALIGNMENT_END = 3
}

///
// Settings used when initializing a CefBoxLayout.
///
struct _cef_box_layout_settings_t
{
    ///
    // If true (1) the layout will be horizontal, otherwise the layout will be
    // vertical.
    ///
    int horizontal;

    ///
    // Adds additional horizontal space between the child view area and the host
    // view border.
    ///
    int inside_border_horizontal_spacing;

    ///
    // Adds additional vertical space between the child view area and the host
    // view border.
    ///
    int inside_border_vertical_spacing;

    ///
    // Adds additional space around the child view area.
    ///
    cef_insets_t inside_border_insets;

    ///
    // Adds additional space between child views.
    ///
    int between_child_spacing;

    ///
    // Specifies where along the main axis the child views should be laid out.
    ///
    cef_main_axis_alignment_t main_axis_alignment;

    ///
    // Specifies where along the cross axis the child views should be laid out.
    ///
    cef_cross_axis_alignment_t cross_axis_alignment;

    ///
    // Minimum cross axis size.
    ///
    int minimum_cross_axis_size;

    ///
    // Default flex for views when none is specified via CefBoxLayout methods.
    // Using the preferred size as the basis, free space along the main axis is
    // distributed to views in the ratio of their flex weights. Similarly, if the
    // views will overflow the parent, space is subtracted in these ratios. A flex
    // of 0 means this view is not resized. Flex values must not be negative.
    ///
    int default_flex;
}

alias cef_box_layout_settings_t = _cef_box_layout_settings_t;

///
// Specifies the button display state.
///
enum cef_button_state_t
{
    CEF_BUTTON_STATE_NORMAL = 0,
    CEF_BUTTON_STATE_HOVERED = 1,
    CEF_BUTTON_STATE_PRESSED = 2,
    CEF_BUTTON_STATE_DISABLED = 3
}

///
// Specifies the horizontal text alignment mode.
///
enum cef_horizontal_alignment_t
{
    ///
    // Align the text's left edge with that of its display area.
    ///
    CEF_HORIZONTAL_ALIGNMENT_LEFT = 0,

    ///
    // Align the text's center with that of its display area.
    ///
    CEF_HORIZONTAL_ALIGNMENT_CENTER = 1,

    ///
    // Align the text's right edge with that of its display area.
    ///
    CEF_HORIZONTAL_ALIGNMENT_RIGHT = 2
}

///
// Specifies how a menu will be anchored for non-RTL languages. The opposite
// position will be used for RTL languages.
///
enum cef_menu_anchor_position_t
{
    CEF_MENU_ANCHOR_TOPLEFT = 0,
    CEF_MENU_ANCHOR_TOPRIGHT = 1,
    CEF_MENU_ANCHOR_BOTTOMCENTER = 2
}

///
// Supported color types for menu items.
///
enum cef_menu_color_type_t
{
    CEF_MENU_COLOR_TEXT = 0,
    CEF_MENU_COLOR_TEXT_HOVERED = 1,
    CEF_MENU_COLOR_TEXT_ACCELERATOR = 2,
    CEF_MENU_COLOR_TEXT_ACCELERATOR_HOVERED = 3,
    CEF_MENU_COLOR_BACKGROUND = 4,
    CEF_MENU_COLOR_BACKGROUND_HOVERED = 5,
    CEF_MENU_COLOR_COUNT = 6
}

// Supported SSL version values. See net/ssl/ssl_connection_status_flags.h
// for more information.
enum cef_ssl_version_t
{
    SSL_CONNECTION_VERSION_UNKNOWN = 0, // Unknown SSL version.
    SSL_CONNECTION_VERSION_SSL2 = 1,
    SSL_CONNECTION_VERSION_SSL3 = 2,
    SSL_CONNECTION_VERSION_TLS1 = 3,
    SSL_CONNECTION_VERSION_TLS1_1 = 4,
    SSL_CONNECTION_VERSION_TLS1_2 = 5,
    SSL_CONNECTION_VERSION_TLS1_3 = 6,
    SSL_CONNECTION_VERSION_QUIC = 7
}

// Supported SSL content status flags. See content/public/common/ssl_status.h
// for more information.
enum cef_ssl_content_status_t
{
    SSL_CONTENT_NORMAL_CONTENT = 0,
    SSL_CONTENT_DISPLAYED_INSECURE_CONTENT = 1 << 0,
    SSL_CONTENT_RAN_INSECURE_CONTENT = 1 << 1
}

//
// Configuration options for registering a custom scheme.
// These values are used when calling AddCustomScheme.
//
enum cef_scheme_options_t
{
    CEF_SCHEME_OPTION_NONE = 0,

    ///
    // If CEF_SCHEME_OPTION_STANDARD is set the scheme will be treated as a
    // standard scheme. Standard schemes are subject to URL canonicalization and
    // parsing rules as defined in the Common Internet Scheme Syntax RFC 1738
    // Section 3.1 available at http://www.ietf.org/rfc/rfc1738.txt
    //
    // In particular, the syntax for standard scheme URLs must be of the form:
    // <pre>
    //  [scheme]://[username]:[password]@[host]:[port]/[url-path]
    // </pre> Standard scheme URLs must have a host component that is a fully
    // qualified domain name as defined in Section 3.5 of RFC 1034 [13] and
    // Section 2.1 of RFC 1123. These URLs will be canonicalized to
    // "scheme://host/path" in the simplest case and
    // "scheme://username:password@host:port/path" in the most explicit case. For
    // example, "scheme:host/path" and "scheme:///host/path" will both be
    // canonicalized to "scheme://host/path". The origin of a standard scheme URL
    // is the combination of scheme, host and port (i.e., "scheme://host:port" in
    // the most explicit case).
    //
    // For non-standard scheme URLs only the "scheme:" component is parsed and
    // canonicalized. The remainder of the URL will be passed to the handler as-
    // is. For example, "scheme:///some%20text" will remain the same. Non-standard
    // scheme URLs cannot be used as a target for form submission.
    ///
    CEF_SCHEME_OPTION_STANDARD = 1 << 0,

    ///
    // If CEF_SCHEME_OPTION_LOCAL is set the scheme will be treated with the same
    // security rules as those applied to "file" URLs. Normal pages cannot link to
    // or access local URLs. Also, by default, local URLs can only perform
    // XMLHttpRequest calls to the same URL (origin + path) that originated the
    // request. To allow XMLHttpRequest calls from a local URL to other URLs with
    // the same origin set the CefSettings.file_access_from_file_urls_allowed
    // value to true (1). To allow XMLHttpRequest calls from a local URL to all
    // origins set the CefSettings.universal_access_from_file_urls_allowed value
    // to true (1).
    ///
    CEF_SCHEME_OPTION_LOCAL = 1 << 1,

    ///
    // If CEF_SCHEME_OPTION_DISPLAY_ISOLATED is set the scheme can only be
    // displayed from other content hosted with the same scheme. For example,
    // pages in other origins cannot create iframes or hyperlinks to URLs with the
    // scheme. For schemes that must be accessible from other schemes don't set
    // this, set CEF_SCHEME_OPTION_CORS_ENABLED, and use CORS
    // "Access-Control-Allow-Origin" headers to further restrict access.
    ///
    CEF_SCHEME_OPTION_DISPLAY_ISOLATED = 1 << 2,

    ///
    // If CEF_SCHEME_OPTION_SECURE is set the scheme will be treated with the same
    // security rules as those applied to "https" URLs. For example, loading this
    // scheme from other secure schemes will not trigger mixed content warnings.
    ///
    CEF_SCHEME_OPTION_SECURE = 1 << 3,

    ///
    // If CEF_SCHEME_OPTION_CORS_ENABLED is set the scheme can be sent CORS
    // requests. This value should be set in most cases where
    // CEF_SCHEME_OPTION_STANDARD is set.
    ///
    CEF_SCHEME_OPTION_CORS_ENABLED = 1 << 4,

    ///
    // If CEF_SCHEME_OPTION_CSP_BYPASSING is set the scheme can bypass Content-
    // Security-Policy (CSP) checks. This value should not be set in most cases
    // where CEF_SCHEME_OPTION_STANDARD is set.
    ///
    CEF_SCHEME_OPTION_CSP_BYPASSING = 1 << 5,

    ///
    // If CEF_SCHEME_OPTION_FETCH_ENABLED is set the scheme can perform Fetch API
    // requests.
    ///
    CEF_SCHEME_OPTION_FETCH_ENABLED = 1 << 6
}

///
// Error codes for CDM registration. See cef_web_plugin.h for details.
///
enum cef_cdm_registration_error_t
{
    ///
    // No error. Registration completed successfully.
    ///
    CEF_CDM_REGISTRATION_ERROR_NONE = 0,

    ///
    // Required files or manifest contents are missing.
    ///
    CEF_CDM_REGISTRATION_ERROR_INCORRECT_CONTENTS = 1,

    ///
    // The CDM is incompatible with the current Chromium version.
    ///
    CEF_CDM_REGISTRATION_ERROR_INCOMPATIBLE = 2,

    ///
    // CDM registration is not supported at this time.
    ///
    CEF_CDM_REGISTRATION_ERROR_NOT_SUPPORTED = 3
}

///
// Composition underline style.
///
enum cef_composition_underline_style_t
{
    CEF_CUS_SOLID = 0,
    CEF_CUS_DOT = 1,
    CEF_CUS_DASH = 2,
    CEF_CUS_NONE = 3
}

///
// Structure representing IME composition underline information. This is a thin
// wrapper around Blink's WebCompositionUnderline class and should be kept in
// sync with that.
///
struct _cef_composition_underline_t
{
    ///
    // Underline character range.
    ///
    cef_range_t range;

    ///
    // Text color.
    ///
    cef_color_t color;

    ///
    // Background color.
    ///
    cef_color_t background_color;

    ///
    // Set to true (1) for thick underline.
    ///
    int thick;

    ///
    // Style.
    ///
    cef_composition_underline_style_t style;
}

alias cef_composition_underline_t = _cef_composition_underline_t;

///
// Enumerates the various representations of the ordering of audio channels.
// Must be kept synchronized with media::ChannelLayout from Chromium.
// See media\base\channel_layout.h
///
enum cef_channel_layout_t
{
    CEF_CHANNEL_LAYOUT_NONE = 0,
    CEF_CHANNEL_LAYOUT_UNSUPPORTED = 1,

    // Front C
    CEF_CHANNEL_LAYOUT_MONO = 2,

    // Front L, Front R
    CEF_CHANNEL_LAYOUT_STEREO = 3,

    // Front L, Front R, Back C
    CEF_CHANNEL_LAYOUT_2_1 = 4,

    // Front L, Front R, Front C
    CEF_CHANNEL_LAYOUT_SURROUND = 5,

    // Front L, Front R, Front C, Back C
    CEF_CHANNEL_LAYOUT_4_0 = 6,

    // Front L, Front R, Side L, Side R
    CEF_CHANNEL_LAYOUT_2_2 = 7,

    // Front L, Front R, Back L, Back R
    CEF_CHANNEL_LAYOUT_QUAD = 8,

    // Front L, Front R, Front C, Side L, Side R
    CEF_CHANNEL_LAYOUT_5_0 = 9,

    // Front L, Front R, Front C, LFE, Side L, Side R
    CEF_CHANNEL_LAYOUT_5_1 = 10,

    // Front L, Front R, Front C, Back L, Back R
    CEF_CHANNEL_LAYOUT_5_0_BACK = 11,

    // Front L, Front R, Front C, LFE, Back L, Back R
    CEF_CHANNEL_LAYOUT_5_1_BACK = 12,

    // Front L, Front R, Front C, Side L, Side R, Back L, Back R
    CEF_CHANNEL_LAYOUT_7_0 = 13,

    // Front L, Front R, Front C, LFE, Side L, Side R, Back L, Back R
    CEF_CHANNEL_LAYOUT_7_1 = 14,

    // Front L, Front R, Front C, LFE, Side L, Side R, Front LofC, Front RofC
    CEF_CHANNEL_LAYOUT_7_1_WIDE = 15,

    // Stereo L, Stereo R
    CEF_CHANNEL_LAYOUT_STEREO_DOWNMIX = 16,

    // Stereo L, Stereo R, LFE
    CEF_CHANNEL_LAYOUT_2POINT1 = 17,

    // Stereo L, Stereo R, Front C, LFE
    CEF_CHANNEL_LAYOUT_3_1 = 18,

    // Stereo L, Stereo R, Front C, Rear C, LFE
    CEF_CHANNEL_LAYOUT_4_1 = 19,

    // Stereo L, Stereo R, Front C, Side L, Side R, Back C
    CEF_CHANNEL_LAYOUT_6_0 = 20,

    // Stereo L, Stereo R, Side L, Side R, Front LofC, Front RofC
    CEF_CHANNEL_LAYOUT_6_0_FRONT = 21,

    // Stereo L, Stereo R, Front C, Rear L, Rear R, Rear C
    CEF_CHANNEL_LAYOUT_HEXAGONAL = 22,

    // Stereo L, Stereo R, Front C, LFE, Side L, Side R, Rear Center
    CEF_CHANNEL_LAYOUT_6_1 = 23,

    // Stereo L, Stereo R, Front C, LFE, Back L, Back R, Rear Center
    CEF_CHANNEL_LAYOUT_6_1_BACK = 24,

    // Stereo L, Stereo R, Side L, Side R, Front LofC, Front RofC, LFE
    CEF_CHANNEL_LAYOUT_6_1_FRONT = 25,

    // Front L, Front R, Front C, Side L, Side R, Front LofC, Front RofC
    CEF_CHANNEL_LAYOUT_7_0_FRONT = 26,

    // Front L, Front R, Front C, LFE, Back L, Back R, Front LofC, Front RofC
    CEF_CHANNEL_LAYOUT_7_1_WIDE_BACK = 27,

    // Front L, Front R, Front C, Side L, Side R, Rear L, Back R, Back C.
    CEF_CHANNEL_LAYOUT_OCTAGONAL = 28,

    // Channels are not explicitly mapped to speakers.
    CEF_CHANNEL_LAYOUT_DISCRETE = 29,

    // Front L, Front R, Front C. Front C contains the keyboard mic audio. This
    // layout is only intended for input for WebRTC. The Front C channel
    // is stripped away in the WebRTC audio input pipeline and never seen outside
    // of that.
    CEF_CHANNEL_LAYOUT_STEREO_AND_KEYBOARD_MIC = 30,

    // Front L, Front R, Side L, Side R, LFE
    CEF_CHANNEL_LAYOUT_4_1_QUAD_SIDE = 31,

    // Actual channel layout is specified in the bitstream and the actual channel
    // count is unknown at Chromium media pipeline level (useful for audio
    // pass-through mode).
    CEF_CHANNEL_LAYOUT_BITSTREAM = 32,

    // Max value, must always equal the largest entry ever logged.
    CEF_CHANNEL_LAYOUT_MAX = CEF_CHANNEL_LAYOUT_BITSTREAM
}

///
// Structure representing the audio parameters for setting up the audio handler.
///
struct _cef_audio_parameters_t
{
    ///
    // Layout of the audio channels
    ///
    cef_channel_layout_t channel_layout;

    ///
    // Sample rate
    //
    int sample_rate;

    ///
    // Number of frames per buffer
    ///
    int frames_per_buffer;
}

alias cef_audio_parameters_t = _cef_audio_parameters_t;

///
// Result codes for CefMediaRouter::CreateRoute. Should be kept in sync with
// Chromium's media_router::RouteRequestResult::ResultCode type.
///
enum cef_media_route_create_result_t
{
    CEF_MRCR_UNKNOWN_ERROR = 0,
    CEF_MRCR_OK = 1,
    CEF_MRCR_TIMED_OUT = 2,
    CEF_MRCR_ROUTE_NOT_FOUND = 3,
    CEF_MRCR_SINK_NOT_FOUND = 4,
    CEF_MRCR_INVALID_ORIGIN = 5,
    CEF_MRCR_NO_SUPPORTED_PROVIDER = 7,
    CEF_MRCR_CANCELLED = 8,
    CEF_MRCR_ROUTE_ALREADY_EXISTS = 9,

    CEF_MRCR_TOTAL_COUNT = 11 // The total number of values.
}

///
// Connection state for a MediaRoute object.
///
enum cef_media_route_connection_state_t
{
    CEF_MRCS_UNKNOWN = 0,
    CEF_MRCS_CONNECTING = 1,
    CEF_MRCS_CONNECTED = 2,
    CEF_MRCS_CLOSED = 3,
    CEF_MRCS_TERMINATED = 4
}

///
// Icon types for a MediaSink object. Should be kept in sync with Chromium's
// media_router::SinkIconType type.
///
enum cef_media_sink_icon_type_t
{
    CEF_MSIT_CAST = 0,
    CEF_MSIT_CAST_AUDIO_GROUP = 1,
    CEF_MSIT_CAST_AUDIO = 2,
    CEF_MSIT_MEETING = 3,
    CEF_MSIT_HANGOUT = 4,
    CEF_MSIT_EDUCATION = 5,
    CEF_MSIT_WIRED_DISPLAY = 6,
    CEF_MSIT_GENERIC = 7,

    CEF_MSIT_TOTAL_COUNT = 8 // The total number of values.
}

///
// Device information for a MediaSink object.
///
struct _cef_media_sink_device_info_t
{
    cef_string_t ip_address;
    int port;
    cef_string_t model_name;
}

alias cef_media_sink_device_info_t = _cef_media_sink_device_info_t;

///
// Represents commands available to TextField.
///
enum cef_text_field_commands_t
{
    CEF_TFC_CUT = 1,
    CEF_TFC_COPY = 2,
    CEF_TFC_PASTE = 3,
    CEF_TFC_UNDO = 4,
    CEF_TFC_DELETE = 5,
    CEF_TFC_SELECT_ALL = 6
}

// CEF_INCLUDE_INTERNAL_CEF_TYPES_H_

// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=7ce0953f069204a4dd2037c4a05ac9454c5e66a6$
//

extern (C):

///
// Callback structure for cef_request_context_t::ResolveHost.
///
struct _cef_resolve_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called on the UI thread after the ResolveHost request has completed.
    // |result| will be the result code. |resolved_ips| will be the list of
    // resolved IP addresses or NULL if the resolution failed.
    ///
    void function (
        _cef_resolve_callback_t* self,
        cef_errorcode_t result,
        cef_string_list_t resolved_ips) nothrow on_resolve_completed;
}

alias cef_resolve_callback_t = _cef_resolve_callback_t;

///
// A request context provides request handling for a set of related browser or
// URL request objects. A request context can be specified when creating a new
// browser via the cef_browser_host_t static factory functions or when creating
// a new URL request via the cef_urlrequest_t static factory functions. Browser
// objects with different request contexts will never be hosted in the same
// render process. Browser objects with the same request context may or may not
// be hosted in the same render process depending on the process model. Browser
// objects created indirectly via the JavaScript window.open function or
// targeted links will share the same render process and the same request
// context as the source browser. When running in single-process mode there is
// only a single render process (the main process) and so all browsers created
// in single-process mode will share the same request context. This will be the
// first request context passed into a cef_browser_host_t static factory
// function and all other request context objects will be ignored.
///
struct _cef_request_context_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Returns true (1) if this object is pointing to the same context as |that|
    // object.
    ///
    int function (
        _cef_request_context_t* self,
        _cef_request_context_t* other) nothrow is_same;

    ///
    // Returns true (1) if this object is sharing the same storage as |that|
    // object.
    ///
    int function (
        _cef_request_context_t* self,
        _cef_request_context_t* other) nothrow is_sharing_with;

    ///
    // Returns true (1) if this object is the global context. The global context
    // is used by default when creating a browser or URL request with a NULL
    // context argument.
    ///
    int function (_cef_request_context_t* self) nothrow is_global;

    ///
    // Returns the handler for this context if any.
    ///
    _cef_request_context_handler_t* function (
        _cef_request_context_t* self) nothrow get_handler;

    ///
    // Returns the cache path for this object. If NULL an "incognito mode" in-
    // memory cache is being used.
    ///
    // The resulting string must be freed by calling cef_string_userfree_free().
    cef_string_userfree_t function (
        _cef_request_context_t* self) nothrow get_cache_path;

    ///
    // Returns the cookie manager for this object. If |callback| is non-NULL it
    // will be executed asnychronously on the IO thread after the manager's
    // storage has been initialized.
    ///
    _cef_cookie_manager_t* function (
        _cef_request_context_t* self,
        _cef_completion_callback_t* callback) nothrow get_cookie_manager;

    ///
    // Register a scheme handler factory for the specified |scheme_name| and
    // optional |domain_name|. An NULL |domain_name| value for a standard scheme
    // will cause the factory to match all domain names. The |domain_name| value
    // will be ignored for non-standard schemes. If |scheme_name| is a built-in
    // scheme and no handler is returned by |factory| then the built-in scheme
    // handler factory will be called. If |scheme_name| is a custom scheme then
    // you must also implement the cef_app_t::on_register_custom_schemes()
    // function in all processes. This function may be called multiple times to
    // change or remove the factory that matches the specified |scheme_name| and
    // optional |domain_name|. Returns false (0) if an error occurs. This function
    // may be called on any thread in the browser process.
    ///
    int function (
        _cef_request_context_t* self,
        const(cef_string_t)* scheme_name,
        const(cef_string_t)* domain_name,
        _cef_scheme_handler_factory_t* factory) nothrow register_scheme_handler_factory;

    ///
    // Clear all registered scheme handler factories. Returns false (0) on error.
    // This function may be called on any thread in the browser process.
    ///
    int function (_cef_request_context_t* self) nothrow clear_scheme_handler_factories;

    ///
    // Tells all renderer processes associated with this context to throw away
    // their plugin list cache. If |reload_pages| is true (1) they will also
    // reload all pages with plugins.
    // cef_request_context_handler_t::OnBeforePluginLoad may be called to rebuild
    // the plugin list cache.
    ///
    void function (
        _cef_request_context_t* self,
        int reload_pages) nothrow purge_plugin_list_cache;

    ///
    // Returns true (1) if a preference with the specified |name| exists. This
    // function must be called on the browser process UI thread.
    ///
    int function (
        _cef_request_context_t* self,
        const(cef_string_t)* name) nothrow has_preference;

    ///
    // Returns the value for the preference with the specified |name|. Returns
    // NULL if the preference does not exist. The returned object contains a copy
    // of the underlying preference value and modifications to the returned object
    // will not modify the underlying preference value. This function must be
    // called on the browser process UI thread.
    ///
    _cef_value_t* function (
        _cef_request_context_t* self,
        const(cef_string_t)* name) nothrow get_preference;

    ///
    // Returns all preferences as a dictionary. If |include_defaults| is true (1)
    // then preferences currently at their default value will be included. The
    // returned object contains a copy of the underlying preference values and
    // modifications to the returned object will not modify the underlying
    // preference values. This function must be called on the browser process UI
    // thread.
    ///
    _cef_dictionary_value_t* function (
        _cef_request_context_t* self,
        int include_defaults) nothrow get_all_preferences;

    ///
    // Returns true (1) if the preference with the specified |name| can be
    // modified using SetPreference. As one example preferences set via the
    // command-line usually cannot be modified. This function must be called on
    // the browser process UI thread.
    ///
    int function (
        _cef_request_context_t* self,
        const(cef_string_t)* name) nothrow can_set_preference;

    ///
    // Set the |value| associated with preference |name|. Returns true (1) if the
    // value is set successfully and false (0) otherwise. If |value| is NULL the
    // preference will be restored to its default value. If setting the preference
    // fails then |error| will be populated with a detailed description of the
    // problem. This function must be called on the browser process UI thread.
    ///
    int function (
        _cef_request_context_t* self,
        const(cef_string_t)* name,
        _cef_value_t* value,
        cef_string_t* error) nothrow set_preference;

    ///
    // Clears all certificate exceptions that were added as part of handling
    // cef_request_handler_t::on_certificate_error(). If you call this it is
    // recommended that you also call close_all_connections() or you risk not
    // being prompted again for server certificates if you reconnect quickly. If
    // |callback| is non-NULL it will be executed on the UI thread after
    // completion.
    ///
    void function (
        _cef_request_context_t* self,
        _cef_completion_callback_t* callback) nothrow clear_certificate_exceptions;

    ///
    // Clears all HTTP authentication credentials that were added as part of
    // handling GetAuthCredentials. If |callback| is non-NULL it will be executed
    // on the UI thread after completion.
    ///
    void function (
        _cef_request_context_t* self,
        _cef_completion_callback_t* callback) nothrow clear_http_auth_credentials;

    ///
    // Clears all active and idle connections that Chromium currently has. This is
    // only recommended if you have released all other CEF objects but don't yet
    // want to call cef_shutdown(). If |callback| is non-NULL it will be executed
    // on the UI thread after completion.
    ///
    void function (
        _cef_request_context_t* self,
        _cef_completion_callback_t* callback) nothrow close_all_connections;

    ///
    // Attempts to resolve |origin| to a list of associated IP addresses.
    // |callback| will be executed on the UI thread after completion.
    ///
    void function (
        _cef_request_context_t* self,
        const(cef_string_t)* origin,
        _cef_resolve_callback_t* callback) nothrow resolve_host;

    ///
    // Load an extension.
    //
    // If extension resources will be read from disk using the default load
    // implementation then |root_directory| should be the absolute path to the
    // extension resources directory and |manifest| should be NULL. If extension
    // resources will be provided by the client (e.g. via cef_request_handler_t
    // and/or cef_extension_handler_t) then |root_directory| should be a path
    // component unique to the extension (if not absolute this will be internally
    // prefixed with the PK_DIR_RESOURCES path) and |manifest| should contain the
    // contents that would otherwise be read from the "manifest.json" file on
    // disk.
    //
    // The loaded extension will be accessible in all contexts sharing the same
    // storage (HasExtension returns true (1)). However, only the context on which
    // this function was called is considered the loader (DidLoadExtension returns
    // true (1)) and only the loader will receive cef_request_context_handler_t
    // callbacks for the extension.
    //
    // cef_extension_handler_t::OnExtensionLoaded will be called on load success
    // or cef_extension_handler_t::OnExtensionLoadFailed will be called on load
    // failure.
    //
    // If the extension specifies a background script via the "background"
    // manifest key then cef_extension_handler_t::OnBeforeBackgroundBrowser will
    // be called to create the background browser. See that function for
    // additional information about background scripts.
    //
    // For visible extension views the client application should evaluate the
    // manifest to determine the correct extension URL to load and then pass that
    // URL to the cef_browser_host_t::CreateBrowser* function after the extension
    // has loaded. For example, the client can look for the "browser_action"
    // manifest key as documented at
    // https://developer.chrome.com/extensions/browserAction. Extension URLs take
    // the form "chrome-extension://<extension_id>/<path>".
    //
    // Browsers that host extensions differ from normal browsers as follows:
    //  - Can access chrome.* JavaScript APIs if allowed by the manifest. Visit
    //    chrome://extensions-support for the list of extension APIs currently
    //    supported by CEF.
    //  - Main frame navigation to non-extension content is blocked.
    //  - Pinch-zooming is disabled.
    //  - CefBrowserHost::GetExtension returns the hosted extension.
    //  - CefBrowserHost::IsBackgroundHost returns true for background hosts.
    //
    // See https://developer.chrome.com/extensions for extension implementation
    // and usage documentation.
    ///
    void function (
        _cef_request_context_t* self,
        const(cef_string_t)* root_directory,
        _cef_dictionary_value_t* manifest,
        _cef_extension_handler_t* handler) nothrow load_extension;

    ///
    // Returns true (1) if this context was used to load the extension identified
    // by |extension_id|. Other contexts sharing the same storage will also have
    // access to the extension (see HasExtension). This function must be called on
    // the browser process UI thread.
    ///
    int function (
        _cef_request_context_t* self,
        const(cef_string_t)* extension_id) nothrow did_load_extension;

    ///
    // Returns true (1) if this context has access to the extension identified by
    // |extension_id|. This may not be the context that was used to load the
    // extension (see DidLoadExtension). This function must be called on the
    // browser process UI thread.
    ///
    int function (
        _cef_request_context_t* self,
        const(cef_string_t)* extension_id) nothrow has_extension;

    ///
    // Retrieve the list of all extensions that this context has access to (see
    // HasExtension). |extension_ids| will be populated with the list of extension
    // ID values. Returns true (1) on success. This function must be called on the
    // browser process UI thread.
    ///
    int function (
        _cef_request_context_t* self,
        cef_string_list_t extension_ids) nothrow get_extensions;

    ///
    // Returns the extension matching |extension_id| or NULL if no matching
    // extension is accessible in this context (see HasExtension). This function
    // must be called on the browser process UI thread.
    ///
    _cef_extension_t* function (
        _cef_request_context_t* self,
        const(cef_string_t)* extension_id) nothrow get_extension;

    ///
    // Returns the MediaRouter object associated with this context.
    ///
    _cef_media_router_t* function (
        _cef_request_context_t* self) nothrow get_media_router;
}

alias cef_request_context_t = _cef_request_context_t;

///
// Returns the global context object.
///
cef_request_context_t* cef_request_context_get_global_context ();

///
// Creates a new context object with the specified |settings| and optional
// |handler|.
///
cef_request_context_t* cef_request_context_create_context (
    const(_cef_request_context_settings_t)* settings,
    _cef_request_context_handler_t* handler);

///
// Creates a new context object that shares storage with |other| and uses an
// optional |handler|.
///
cef_request_context_t* cef_create_context_shared (
    cef_request_context_t* other,
    _cef_request_context_handler_t* handler);

// CEF_INCLUDE_CAPI_CEF_REQUEST_CONTEXT_CAPI_H_
// Copyright (c) 2020 Marshall A. Greenblatt. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ---------------------------------------------------------------------------
//
// This file was generated by the CEF translator tool and should not edited
// by hand. See the translator.README.txt file in the tools directory for
// more information.
//
// $hash=a13b5b607d5a2108fac5fe75f5ebd2ede7eaef6a$
//

extern (C):

//#include "include/capi/cef_browser_capi.h"

///
// Callback structure used for asynchronous continuation of
// cef_extension_handler_t::GetExtensionResource.
///
struct _cef_get_extension_resource_callback_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Continue the request. Read the resource contents from |stream|.
    ///
    void function (
        _cef_get_extension_resource_callback_t* self,
        _cef_stream_reader_t* stream) nothrow cont;

    ///
    // Cancel the request.
    ///
    void function (_cef_get_extension_resource_callback_t* self) nothrow cancel;
}

alias cef_get_extension_resource_callback_t = _cef_get_extension_resource_callback_t;

///
// Implement this structure to handle events related to browser extensions. The
// functions of this structure will be called on the UI thread. See
// cef_request_context_t::LoadExtension for information about extension loading.
///
struct _cef_extension_handler_t
{
    ///
    // Base structure.
    ///
    cef_base_ref_counted_t base;

    ///
    // Called if the cef_request_context_t::LoadExtension request fails. |result|
    // will be the error code.
    ///
    void function (
        _cef_extension_handler_t* self,
        cef_errorcode_t result) nothrow on_extension_load_failed;

    ///
    // Called if the cef_request_context_t::LoadExtension request succeeds.
    // |extension| is the loaded extension.
    ///
    void function (
        _cef_extension_handler_t* self,
        _cef_extension_t* extension) nothrow on_extension_loaded;

    ///
    // Called after the cef_extension_t::Unload request has completed.
    ///
    void function (
        _cef_extension_handler_t* self,
        _cef_extension_t* extension) nothrow on_extension_unloaded;

    ///
    // Called when an extension needs a browser to host a background script
    // specified via the "background" manifest key. The browser will have no
    // visible window and cannot be displayed. |extension| is the extension that
    // is loading the background script. |url| is an internally generated
    // reference to an HTML page that will be used to load the background script
    // via a <script> src attribute. To allow creation of the browser optionally
    // modify |client| and |settings| and return false (0). To cancel creation of
    // the browser (and consequently cancel load of the background script) return
    // true (1). Successful creation will be indicated by a call to
    // cef_life_span_handler_t::OnAfterCreated, and
    // cef_browser_host_t::IsBackgroundHost will return true (1) for the resulting
    // browser. See https://developer.chrome.com/extensions/event_pages for more
    // information about extension background script usage.
    ///
    int function (
        _cef_extension_handler_t* self,
        _cef_extension_t* extension,
        const(cef_string_t)* url,
        _cef_client_t** client,
        _cef_browser_settings_t* settings) nothrow on_before_background_browser;

    ///
    // Called when an extension API (e.g. chrome.tabs.create) requests creation of
    // a new browser. |extension| and |browser| are the source of the API call.
    // |active_browser| may optionally be specified via the windowId property or
    // returned via the get_active_browser() callback and provides the default
    // |client| and |settings| values for the new browser. |index| is the position
    // value optionally specified via the index property. |url| is the URL that
    // will be loaded in the browser. |active| is true (1) if the new browser
    // should be active when opened.  To allow creation of the browser optionally
    // modify |windowInfo|, |client| and |settings| and return false (0). To
    // cancel creation of the browser return true (1). Successful creation will be
    // indicated by a call to cef_life_span_handler_t::OnAfterCreated. Any
    // modifications to |windowInfo| will be ignored if |active_browser| is
    // wrapped in a cef_browser_view_t.
    ///
    int function (
        _cef_extension_handler_t* self,
        _cef_extension_t* extension,
        _cef_browser_t* browser,
        _cef_browser_t* active_browser,
        int index,
        const(cef_string_t)* url,
        int active,
        _cef_window_info_t* windowInfo,
        _cef_client_t** client,
        _cef_browser_settings_t* settings) nothrow on_before_browser;

    ///
    // Called when no tabId is specified to an extension API call that accepts a
    // tabId parameter (e.g. chrome.tabs.*). |extension| and |browser| are the
    // source of the API call. Return the browser that will be acted on by the API
    // call or return NULL to act on |browser|. The returned browser must share
    // the same cef_request_context_t as |browser|. Incognito browsers should not
    // be considered unless the source extension has incognito access enabled, in
    // which case |include_incognito| will be true (1).
    ///
    _cef_browser_t* function (
        _cef_extension_handler_t* self,
        _cef_extension_t* extension,
        _cef_browser_t* browser,
        int include_incognito) nothrow get_active_browser;

    ///
    // Called when the tabId associated with |target_browser| is specified to an
    // extension API call that accepts a tabId parameter (e.g. chrome.tabs.*).
    // |extension| and |browser| are the source of the API call. Return true (1)
    // to allow access of false (0) to deny access. Access to incognito browsers
    // should not be allowed unless the source extension has incognito access
    // enabled, in which case |include_incognito| will be true (1).
    ///
    int function (
        _cef_extension_handler_t* self,
        _cef_extension_t* extension,
        _cef_browser_t* browser,
        int include_incognito,
        _cef_browser_t* target_browser) nothrow can_access_browser;

    ///
    // Called to retrieve an extension resource that would normally be loaded from
    // disk (e.g. if a file parameter is specified to chrome.tabs.executeScript).
    // |extension| and |browser| are the source of the resource request. |file| is
    // the requested relative file path. To handle the resource request return
    // true (1) and execute |callback| either synchronously or asynchronously. For
    // the default behavior which reads the resource from the extension directory
    // on disk return false (0). Localization substitutions will not be applied to
    // resources handled via this function.
    ///
    int function (
        _cef_extension_handler_t* self,
        _cef_extension_t* extension,
        _cef_browser_t* browser,
        const(cef_string_t)* file,
        _cef_get_extension_resource_callback_t* callback) nothrow get_extension_resource;
}

alias cef_extension_handler_t = _cef_extension_handler_t;

// CEF_INCLUDE_CAPI_CEF_EXTENSION_HANDLER_CAPI_H_
}


version(Windows):
import arsd.simpledisplay;
import arsd.com;
import core.atomic;

import std.stdio;

T callback(T)(typeof(&T.init.Invoke) dg) {
	return new class T {
		extern(Windows):

		static if(is(typeof(T.init.Invoke) R == return))
		static if(is(typeof(T.init.Invoke) P == __parameters))
  		override R Invoke(P _args_) {
			return dg(_args_);
		}

		override HRESULT QueryInterface(const (IID)*riid, LPVOID *ppv) {
			if (IID_IUnknown == *riid) {
				*ppv = cast(void*) cast(IUnknown) this;
			}
			else if (T.iid == *riid) {
				*ppv = cast(void*) cast(T) this;
			}
			else {
				*ppv = null;
				return E_NOINTERFACE;
			}

			AddRef();
			return NOERROR;
		}

		LONG count = 0;             // object reference count
		ULONG AddRef() {
			return atomicOp!"+="(*cast(shared)&count, 1);
		}
		ULONG Release() {
			return atomicOp!"-="(*cast(shared)&count, 1);
		}
	};
}

version(Demo)
void main() {
	//CoInitializeEx(null, COINIT_APARTMENTTHREADED);

	auto window = new SimpleWindow(500, 500, "Webview");//, OpenGlOptions.no, Resizability.allowResizing,;

	auto lib = LoadLibraryW("WebView2Loader.dll"w.ptr);
	typeof(&CreateCoreWebView2EnvironmentWithOptions) func;
	assert(lib);
	func = cast(typeof(func)) GetProcAddress(lib, CreateCoreWebView2EnvironmentWithOptions.mangleof);
	assert(func);

	ICoreWebView2 webview_window;
	ICoreWebView2Environment webview_env;

	auto result = func(null, null, null,
		callback!(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)(
			delegate(error, env) {
				if(error)
					return error;

				webview_env = env;
				env.AddRef();

				env.CreateCoreWebView2Controller(window.impl.hwnd,
					callback!(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)(delegate(error, controller) {
						if(error || controller is null)
							return error;
						controller.AddRef();
						error = controller.get_CoreWebView2(&webview_window);
						webview_window.AddRef();

						ICoreWebView2Settings Settings;
						webview_window.get_Settings(&Settings);
						Settings.put_IsScriptEnabled(TRUE);
						Settings.put_AreDefaultScriptDialogsEnabled(TRUE);
						Settings.put_IsWebMessageEnabled(TRUE);


		EventRegistrationToken ert = EventRegistrationToken(233);
		webview_window.add_NavigationStarting(
			callback!(
				ICoreWebView2NavigationStartingEventHandler,
			)(delegate (sender, args) {
				wchar* t;
				args.get_Uri(&t);
				auto ot = t;

				write("Nav: ");

				while(*t) {
					write(*t);
					t++;
				}

				CoTaskMemFree(ot);

				return S_OK;
			})
			, &ert);

						RECT bounds;
						GetClientRect(window.impl.hwnd, &bounds);
						controller.put_Bounds(bounds);
						error = webview_window.Navigate("https://bing.com/"w.ptr);
						//error = webview_window.NavigateToString("<html><body>Hello</body></html>"w.ptr);
						//error = webview_window.Navigate("http://192.168.1.10/"w.ptr);

						controller.put_IsVisible(true);
						writeln(error, " ", window.impl.hwnd, " window ", webview_window);//, "\n", GetParent(webview_window));

						return S_OK;
					}));


				return S_OK;
			}
		)
	);

	if(result != S_OK) {
		import std.stdio;
		writeln("Failed: ", result);
	}

	window.eventLoop(0);
}


/* ************************************ */

// File generated by idl2d from
//   C:\Users\me\source\repos\webviewtest\packages\Microsoft.Web.WebView2.1.0.664.37\WebView2.idl
//module webview2;

public import core.sys.windows.windows;
public import core.sys.windows.unknwn;
public import core.sys.windows.oaidl;
public import core.sys.windows.objidl;

alias EventRegistrationToken = long;

// Copyright (C) Microsoft Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/+
Copyright (C) Microsoft Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * The name of Microsoft Corporation, or the names of its contributors 
may not be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
+/

// # API Review
// All APIs need API review. List API review documents here with the URI to the
// doc and the change ID of the IDL when the document was created.
// API documents:
//  * 916246ec [WebView2 API Specification](https://aka.ms/WebView2APISpecification)
//
// # Style
// Follow the [Win32 API Design Guidelines](https://aka.ms/Win32APIDesignGuidelines)
// while editing this file. For any style rules unspecified follow the Anaheim
// style. Specifically, follow Anaheim indenting and line limit style rules in
// this file.
//
// # Documentation
// Please ensure that any new API includes complete documentation in its
// JavaDoc comments in this file and sample usage in the Sample App.
// Comments intended for public API documentation should start with 3 slashes.
// The first sentence is the brief the brief description of the API and
// shouldn't include the name of the API. Use markdown to style your public API
// documentation.
//
// # WebView and JavaScript capitalization
//    camel case  | webViewExample  | javaScriptExample
//    Pascal case | WebViewExample  | JavaScriptExample
//    Upper case  | WEBVIEW_EXAMPLE | JAVASCRIPT_EXAMPLE
//
// That said, in API names use the term 'script' rather than 'JavaScript'.
// Script is shorter and there is only one supported scripting language on the
// web so the specificity of JavaScript is unnecessary.
//
// # URI (not URL)
// We use Uri in parameter names and type names
// throughout. URIs identify resources while URLs (a subset of URIs) also
// locates resources. This difference is not generally well understood. Because
// all URLs are URIs we can ignore the conversation of trying to explain the
// difference between the two and still be technically accurate by always using
// the term URI. Additionally, whether a URI is locatable depends on the context
// since end developers can at runtime specify custom URI scheme resolvers.
//
// # Event pattern
// Events have a method to add and to remove event handlers:
// ```
// HRESULT add_{EventName}(
//     ICoreWebView2{EventName}EventHandler* eventHandler,
//     EventRegistrationToken* token);
//
// HRESULT remove_{EventName}(EventRegistrationToken token);
// ```
// Add takes an event handler delegate interface with a single Invoke method.
// ```
// ICoreWebView2{EventName}EventHandler::Invoke(
//     {SenderType}* sender,
//     ICoreWebView2{EventHandler}EventArgs* args);
// ```
// The Invoke method has two parameters. The first is the sender, the object
// which is firing the event. The second is the EventArgs type. It doesn't take
// the event arg parameters directly so we can version interfaces correctly.
// If the event has no properties on its event args type, then the Invoke method
// should take IUnknown* as its event args parameter so it is possible to add
// event args interfaces in the future without requiring a new event. For events
// with no sender (a static event), the Invoke method has only the event args
// parameter.
//
// # Deferrable event pattern
// Generally, events should be deferrable when their event args have settable
// properties. In order for the caller to use asynchronous methods to produce
// the value for those settable properties we must allow the caller to defer
// the WebView reading those properties until asynchronously later. A deferrable
// event should have the following method on its event args interface:
//   `HRESULT GetDeferral([out, retval] ICoreWebView2Deferral** deferral);`
// If called, the event is deferred and calling Complete on the
// ICoreWebView2Deferral ends the deferral.
//
// # Asynchronous method pattern
// Async methods take a final parameter that is the completed handler:
//   `{MethodName}(..., ICoreWebView2{MethodName}CompletedHandler* handler)`
// The handler has a single Invoke method:
//   `ICoreWebView2{MethodName}CompletedHandler::Invoke(
//       HRESULT errorCode, {AsyncReturnType});`
//
// # Property pattern
// For properties with getters in IDL you have
//   `[propget] HRESULT {PropertyName}([out, retval] {PropertyType}*)`
// And for properties which also have setters in IDL you have
//   `[propput] HRESULT {PropertyName}([in] {PropertyType});`
//
// # Versioning
// The loader DLL may be older or newer than the client DLL. We have to deal
// with compatibility across several dimensions:
//  * There's the DLL export contract between the loader DLL and the client
//    DLL as well as the interfaces defined in this IDL that are built into both
//    the app code and the client DLL.
//  * There are two kinds of versioned changes we need to be able to make:
//    compatible changes and breaking changes. In both cases we need to make the
//    change in a safe manner. For compatible that means everything continues to
//    work unchanged despite the loader and client being different versions. For
//    breaking changes this means the host app is unable to create a
//    WebView using the different version browser and receives an associated
//    error message (doesn't crash).
//  * We also need to consider when the loader and host app is using a newer
//    version than the browser and when the loader and host app is using an
//    older version than the browser.
//
// ## Scenario 1: Older SDK in host app, Newer browser, Compatible change
// In order to be compatible the newer client DLL must still support the older
// client DLL exports. Similarly for the interfaces - they must all be exactly
// the same with no modified IIDs, no reordered methods, no modified method
// parameters and so on. The client DLL may have more DLL exports and more interfaces
// but no changes to the older shipped DLL export or interfaces.
// App code doesn't need to do anything special in this case.
//
// ## Scenario 2: Older SDK in host app, Newer browser, Breaking change
// For breaking changes in the DLL export, the client DLL must change the DLL
// export name. The old loader will attempt to use the old client DLL export.
// When the loader finds the export missing it will fail.
// For breaking changes in the interface, we must change the IID of the modified
// interface. Additionally the loader DLL must validate that the returned object
// supports the IID it expects and fail otherwise.
// The app code must ensure that WebView objects succeed in their QueryInterface
// calls. Basically the app code must have error handling for objects failing
// QueryInterface and for the initial creation failing in order to handle
// breaking changes gracefully.
//
// ## Scenario 3: Newer SDK in host app, Older browser, Compatible change
// In order to be compatible, the newer loader DLL must fallback to calling the
// older client DLL exports if the client DLL doesn't have the most recent DLL
// exports.
// For interface versioning the loader DLL shouldn't be impacted.
// The app code must not assume an object supports all newer versioned
// interfaces. Ideally it checks the success of QueryInterface for newer
// interfaces and if not supported turns off associated app features or
// otherwise fails gracefully.
//
// ## Scenario 4: Newer SDK in host app, Older browser, Breaking change
// For breaking changes in the DLL export, a new export name will be used after
// a breaking change and the loader DLL will just not check for pre-breaking
// change exports from the client DLL. If the client DLL doesn't have the
// correct exports, then the loader returns failure to the caller.
// For breaking changes in the interface, the IIDs of broken interfaces will
// have been modified. The loader will validate that the
// object returned supports the correct base interface IID and return failure to
// the caller otherwise.
// The app code must allow for QueryInterface calls to fail if the object
// doesn't support the newer IIDs.
//
// ## Actions
//  * DLL export compatible changes: Create a new DLL export with a new name.
//    Ideally implement the existing DLL export as a call into the new DLL
//    export to reduce upkeep burden.
//  * DLL export breaking changes: Give the modified DLL export a new name and
//    remove all older DLL exports.
//  * Interface compatible changes: Don't modify shipped interfaces. Add a new
//    interface with an incremented version number suffix
//    (ICoreWebView2_3) or feature group name suffix
//    (ICoreWebView2WithNavigationHistory).
//  * Interface breaking changes: After modifying a shipped interface, give it
//    a new IID.
//  * Loader: When finding the client DLL export it must check its known range
//    of compatible exports in order from newest to oldest and use the newest
//    one found. It must not attempt to use an older export from before a
//    breaking change. Before returning objects to the caller, the loader must
//    validate that the object actually implements the expected interface.
//  * App code: Check for error from the DLL export methods as they can fail if
//    the loader is used with an old browser from before a breaking change or
//    with a newer browser that is after a breaking change.
//    Check for errors when calling QueryInterface on a WebView object. The
//    QueryInterface call may fail with E_NOINTERFACE if the object is from an
//    older browser version that doesn't support the newer interface or if
//    using a newer browser version that had a breaking change on that
//    interface.

/+[uuid(26d34152-879f-4065-bea2-3daa2cfadfb8), version(1.0)]+/
version(all)
{ /+ library WebView2 +/

// Interface forward declarations
/+ interface ICoreWebView2AcceleratorKeyPressedEventArgs; +/
/+ interface ICoreWebView2AcceleratorKeyPressedEventHandler; +/
/+ interface ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler; +/
/+ interface ICoreWebView2CallDevToolsProtocolMethodCompletedHandler; +/
/+ interface ICoreWebView2CapturePreviewCompletedHandler; +/
/+ interface ICoreWebView2; +/
/+ interface ICoreWebView2Controller; +/
/+ interface ICoreWebView2ContentLoadingEventArgs; +/
/+ interface ICoreWebView2ContentLoadingEventHandler; +/
/+ interface ICoreWebView2DocumentTitleChangedEventHandler; +/
/+ interface ICoreWebView2ContainsFullScreenElementChangedEventHandler; +/
/+ interface ICoreWebView2CreateCoreWebView2ControllerCompletedHandler; +/
/+ interface ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler; +/
/+ interface ICoreWebView2Deferral; +/
/+ interface ICoreWebView2DevToolsProtocolEventReceivedEventArgs; +/
/+ interface ICoreWebView2DevToolsProtocolEventReceivedEventHandler; +/
/+ interface ICoreWebView2DevToolsProtocolEventReceiver; +/
/+ interface ICoreWebView2Environment; +/
/+ interface ICoreWebView2EnvironmentOptions; +/
/+ interface ICoreWebView2ExecuteScriptCompletedHandler; +/
/+ interface ICoreWebView2FocusChangedEventHandler; +/
/+ interface ICoreWebView2HistoryChangedEventHandler; +/
/+ interface ICoreWebView2HttpHeadersCollectionIterator; +/
/+ interface ICoreWebView2HttpRequestHeaders; +/
/+ interface ICoreWebView2HttpResponseHeaders; +/
/+ interface ICoreWebView2MoveFocusRequestedEventArgs; +/
/+ interface ICoreWebView2MoveFocusRequestedEventHandler; +/
/+ interface ICoreWebView2NavigationCompletedEventArgs; +/
/+ interface ICoreWebView2NavigationCompletedEventHandler; +/
/+ interface ICoreWebView2NavigationStartingEventArgs; +/
/+ interface ICoreWebView2NavigationStartingEventHandler; +/
/+ interface ICoreWebView2NewBrowserVersionAvailableEventHandler; +/
/+ interface ICoreWebView2NewWindowRequestedEventArgs; +/
/+ interface ICoreWebView2NewWindowRequestedEventHandler; +/
/+ interface ICoreWebView2PermissionRequestedEventArgs; +/
/+ interface ICoreWebView2PermissionRequestedEventHandler; +/
/+ interface ICoreWebView2ProcessFailedEventArgs; +/
/+ interface ICoreWebView2ProcessFailedEventHandler; +/
/+ interface ICoreWebView2ScriptDialogOpeningEventArgs; +/
/+ interface ICoreWebView2ScriptDialogOpeningEventHandler; +/
/+ interface ICoreWebView2Settings; +/
/+ interface ICoreWebView2SourceChangedEventArgs; +/
/+ interface ICoreWebView2SourceChangedEventHandler; +/
/+ interface ICoreWebView2WebMessageReceivedEventArgs; +/
/+ interface ICoreWebView2WebMessageReceivedEventHandler; +/
/+ interface ICoreWebView2WebResourceRequest; +/
/+ interface ICoreWebView2WebResourceRequestedEventArgs; +/
/+ interface ICoreWebView2WebResourceRequestedEventHandler; +/
/+ interface ICoreWebView2WebResourceResponse; +/
/+ interface ICoreWebView2WindowCloseRequestedEventHandler; +/
/+ interface ICoreWebView2WindowFeatures; +/
/+ interface ICoreWebView2ZoomFactorChangedEventHandler; +/

// Enums and structs
/// Image format used by the ICoreWebView2::CapturePreview method.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT+/
{
  /// PNG image format.
  COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG,
  /// JPEG image format.
  COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_JPEG,
}
alias int COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT;

/// Kind of JavaScript dialog used in the
/// ICoreWebView2ScriptDialogOpeningEventHandler interface.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_SCRIPT_DIALOG_KIND+/
{
  /// A dialog invoked via the window.alert JavaScript function.
  COREWEBVIEW2_SCRIPT_DIALOG_KIND_ALERT,
  /// A dialog invoked via the window.confirm JavaScript function.
  COREWEBVIEW2_SCRIPT_DIALOG_KIND_CONFIRM,
  /// A dialog invoked via the window.prompt JavaScript function.
  COREWEBVIEW2_SCRIPT_DIALOG_KIND_PROMPT,
  /// A dialog invoked via the beforeunload JavaScript event.
  COREWEBVIEW2_SCRIPT_DIALOG_KIND_BEFOREUNLOAD,
}
alias int COREWEBVIEW2_SCRIPT_DIALOG_KIND;

/// Kind of process failure used in the ICoreWebView2ProcessFailedEventHandler
/// interface.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_PROCESS_FAILED_KIND+/
{
  /// Indicates the browser process terminated unexpectedly.
  /// The WebView automatically goes into the Closed state.
  /// The app has to recreate a new WebView to recover from this failure.
  COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED,

  /// Indicates the render process terminated unexpectedly.
  /// A new render process will be created automatically and navigated to an
  /// error page.
  /// The app can use Reload to try to recover from this failure.
  COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED,

  /// Indicates the render process becomes unresponsive.
  // Note that this does not seem to work right now.
  // Does not fire for simple long running script case, the only related test
  // SitePerProcessBrowserTest::NoCommitTimeoutForInvisibleWebContents is
  // disabled.
  COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE,
}
alias int COREWEBVIEW2_PROCESS_FAILED_KIND;

/// The type of a permission request.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_PERMISSION_KIND+/
{
  /// Unknown permission.
  COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION,

  /// Permission to capture audio.
  COREWEBVIEW2_PERMISSION_KIND_MICROPHONE,

  /// Permission to capture video.
  COREWEBVIEW2_PERMISSION_KIND_CAMERA,

  /// Permission to access geolocation.
  COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION,

  /// Permission to send web notifications.
  /// This permission request is currently auto rejected and
  /// no event is fired for it.
  COREWEBVIEW2_PERMISSION_KIND_NOTIFICATIONS,

  /// Permission to access generic sensor.
  /// Generic Sensor covering ambient-light-sensor, accelerometer, gyroscope
  /// and magnetometer.
  COREWEBVIEW2_PERMISSION_KIND_OTHER_SENSORS,

  /// Permission to read system clipboard without a user gesture.
  COREWEBVIEW2_PERMISSION_KIND_CLIPBOARD_READ,
}
alias int COREWEBVIEW2_PERMISSION_KIND;

/// Response to a permission request.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_PERMISSION_STATE+/
{
  /// Use default browser behavior, which normally prompt users for decision.
  COREWEBVIEW2_PERMISSION_STATE_DEFAULT,

  /// Grant the permission request.
  COREWEBVIEW2_PERMISSION_STATE_ALLOW,

  /// Deny the permission request.
  COREWEBVIEW2_PERMISSION_STATE_DENY,
}
alias int COREWEBVIEW2_PERMISSION_STATE;

/// Error status values for web navigations.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_WEB_ERROR_STATUS+/
{
  /// An unknown error occurred.
  COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN,

  /// The SSL certificate common name does not match the web address.
  COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT,

  /// The SSL certificate has expired.
  COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_EXPIRED,

  /// The SSL client certificate contains errors.
  COREWEBVIEW2_WEB_ERROR_STATUS_CLIENT_CERTIFICATE_CONTAINS_ERRORS,

  /// The SSL certificate has been revoked.
  COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_REVOKED,

  /// The SSL certificate is invalid -- this could mean the certificate did not
  /// match the public key pins for the host name, the certificate is signed by
  /// an untrusted authority or using a weak sign algorithm, the certificate
  /// claimed DNS names violate name constraints, the certificate contains a
  /// weak key, the certificate's validity period is too long, lack of
  /// revocation information or revocation mechanism, non-unique host name, lack
  /// of certificate transparency information, or the certificate is chained to
  /// a [legacy Symantec
  /// root](https://security.googleblog.com/2018/03/distrust-of-symantec-pki-immediate.html).
  COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID,

  /// The host is unreachable.
  COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE,

  /// The connection has timed out.
  COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT,

  /// The server returned an invalid or unrecognized response.
  COREWEBVIEW2_WEB_ERROR_STATUS_ERROR_HTTP_INVALID_SERVER_RESPONSE,

  /// The connection was aborted.
  COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED,

  /// The connection was reset.
  COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_RESET,

  /// The Internet connection has been lost.
  COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED,

  /// Cannot connect to destination.
  COREWEBVIEW2_WEB_ERROR_STATUS_CANNOT_CONNECT,

  /// Could not resolve provided host name.
  COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED,

  /// The operation was canceled.
  COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED,

  /// The request redirect failed.
  COREWEBVIEW2_WEB_ERROR_STATUS_REDIRECT_FAILED,

  /// An unexpected error occurred.
  COREWEBVIEW2_WEB_ERROR_STATUS_UNEXPECTED_ERROR,
}
alias int COREWEBVIEW2_WEB_ERROR_STATUS;

/// Enum for web resource request contexts.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_WEB_RESOURCE_CONTEXT+/
{
  /// All resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL,
  /// Document resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT,
  /// CSS resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_STYLESHEET,
  /// Image resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_IMAGE,
  /// Other media resources such as videos
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_MEDIA,
  /// Font resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_FONT,
  /// Script resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_SCRIPT,
  /// XML HTTP requests
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_XML_HTTP_REQUEST,
  /// Fetch API communication
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_FETCH,
  /// TextTrack resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_TEXT_TRACK,
  /// EventSource API communication
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_EVENT_SOURCE,
  /// WebSocket API communication
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_WEBSOCKET,
  /// Web App Manifests
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_MANIFEST,
  /// Signed HTTP Exchanges
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_SIGNED_EXCHANGE,
  /// Ping requests
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_PING,
  /// CSP Violation Reports
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_CSP_VIOLATION_REPORT,
  /// Other resources
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_OTHER
}
alias int COREWEBVIEW2_WEB_RESOURCE_CONTEXT;

/// Reason for moving focus.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_MOVE_FOCUS_REASON+/
{
  /// Code setting focus into WebView.
  COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC,

  /// Moving focus due to Tab traversal forward.
  COREWEBVIEW2_MOVE_FOCUS_REASON_NEXT,

  /// Moving focus due to Tab traversal backward.
  COREWEBVIEW2_MOVE_FOCUS_REASON_PREVIOUS,
}
alias int COREWEBVIEW2_MOVE_FOCUS_REASON;

/// The type of key event that triggered an AcceleratorKeyPressed event.
/+[v1_enum]+/
enum /+ COREWEBVIEW2_KEY_EVENT_KIND+/
{
  /// Correspond to window message WM_KEYDOWN.
  COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN,

  /// Correspond to window message WM_KEYUP.
  COREWEBVIEW2_KEY_EVENT_KIND_KEY_UP,

  /// Correspond to window message WM_SYSKEYDOWN.
  COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN,

  /// Correspond to window message WM_SYSKEYUP.
  COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_UP,
}
alias int COREWEBVIEW2_KEY_EVENT_KIND;

/// A structure representing the information packed into the LPARAM given
/// to a Win32 key event.  See the documentation for WM_KEYDOWN for details
/// at https://docs.microsoft.com/windows/win32/inputdev/wm-keydown
struct COREWEBVIEW2_PHYSICAL_KEY_STATUS
{
  /// The repeat count for the current message.
  UINT32 RepeatCount;
  /// The scan code.
  UINT32 ScanCode;
  /// Indicates whether the key is an extended key.
  BOOL IsExtendedKey;
  /// The context code.
  BOOL IsMenuKeyDown;
  /// The previous key state.
  BOOL WasKeyDown;
  /// The transition state.
  BOOL IsKeyReleased;
}
// End of enums and structs

/// WebView2 enables you to host web content using the
/// latest Edge web browser technology.
///
/// ## Navigation events
/// The normal sequence of navigation events is NavigationStarting,
/// SourceChanged, ContentLoading and then NavigationCompleted.
/// The following events describe the state of WebView during each navigation:
/// NavigationStarting: WebView is starting to navigate and the navigation will
/// result in a network request. The host can disallow the request at this time.
/// SourceChanged: The source of WebView is changed to a new URL. This may also
/// be due to a navigation that doesn't cause a network request such as a fragment
/// navigation.
/// HistoryChanged: WebView's history has been updated as a result of
/// the navigation.
/// ContentLoading: WebView has started loading new content.
/// NavigationCompleted: WebView has completed loading content on the new page.
/// Developers can track navigations to each new document by the navigation ID.
/// WebView's navigation ID changes every time there is a successful navigation
/// to a new document.
///
///
/// \dot
/// digraph NavigationEvents {
///    node [fontname=Roboto, shape=rectangle]
///    edge [fontname=Roboto]
///
///    NewDocument -> NavigationStarting;
///    NavigationStarting -> SourceChanged -> ContentLoading [label="New Document"];
///    ContentLoading -> HistoryChanged;
///    SameDocument -> SourceChanged;
///    SourceChanged -> HistoryChanged [label="Same Document"];
///    HistoryChanged -> NavigationCompleted;
///    NavigationStarting -> NavigationStarting [label="Redirect"];
///    NavigationStarting -> NavigationCompleted [label="Failure"];
/// }
/// \enddot
///
/// Note that this is for navigation events with the same NavigationId event
/// arg. Navigations events with different NavigationId event args may overlap.
/// For instance, if you start a navigation wait for its NavigationStarting
/// event and then start another navigation you'll see the NavigationStarting
/// for the first navigate followed by the NavigationStarting of the second
/// navigate, followed by the NavigationCompleted for the first navigation and
/// then all the rest of the appropriate navigation events for the second
/// navigation.
/// In error cases there may or may not be a ContentLoading event depending
/// on whether the navigation is continued to an error page.
/// In case of an HTTP redirect, there will be multiple NavigationStarting
/// events in a row, with ones following the first will have their IsRedirect
/// flag set, however navigation ID remains the same. Same document navigations
/// do not result in NavigationStarting event and also do not increment the
/// navigation ID.
///
/// To monitor or cancel navigations inside subframes in the WebView, use
/// FrameNavigationStarting.
///
/// ## Process model
/// WebView2 uses the same process model as the Edge web
/// browser. There is one Edge browser process per specified user data directory
/// in a user session that will serve any WebView2 calling
/// process that specifies that user data directory. This means one Edge browser
/// process may be serving multiple calling processes and one calling
/// process may be using multiple Edge browser processes.
///
/// \dot
/// digraph ProcessModelNClientsNServers {
///     node [fontname=Roboto, shape=rectangle];
///     edge [fontname=Roboto];
///
///     Host1 [label="Calling\nprocess 1"];
///     Host2 [label="Calling\nprocess 2"];
///     Browser1 [label="Edge processes\ngroup 1"];
///     Browser2 [label="Edge processes\ngroup 2"];
///
///     Host1 -> Browser1;
///     Host1 -> Browser2;
///     Host2 -> Browser2;
/// }
/// \enddot
///
/// Associated with each browser process there will be some number of
/// render processes.
/// These are created as
/// necessary to service potentially multiple frames in different WebViews. The
/// number of render processes varies based on the site isolation browser
/// feature and the number of distinct disconnected origins rendered in
/// associated WebViews.
///
/// \dot
/// digraph ProcessModelClientServer {
///     node [fontname=Roboto, shape=rectangle];
///     edge [fontname=Roboto];
///     graph [fontname=Roboto];
///
///     Host [label="Calling process"];
///     subgraph cluster_0 {
///         labeljust = "l";
///         label = "Edge processes group";
///         Browser [label="Edge browser\nprocess"];
///         Render1 [label="Edge render\nprocess 1"];
///         Render2 [label="Edge render\nprocess 2"];
///         RenderN [label="Edge render\nprocess N"];
///         GPU [label="Edge GPU\nprocess"];
///     }
///
///     Host -> Browser;
///     Browser -> Render1;
///     Browser -> Render2;
///     Browser -> RenderN;
///     Browser -> GPU;
/// }
/// \enddot
///
/// You can react to crashes and hangs in these browser and render processes
/// using the ProcessFailure event.
///
/// You can safely shutdown associated browser and render processes using the
/// Close method.
///
/// ## Threading model
/// The WebView2 must be created on a UI thread. Specifically a
/// thread with a message pump. All callbacks will occur on that thread and
/// calls into the WebView must be done on that thread. It is not safe to use
/// the WebView from another thread.
///
/// Callbacks including event handlers and completion handlers execute serially.
/// That is, if you have an event handler running and begin a message loop no
/// other event handlers or completion callbacks will begin executing
/// reentrantly.
///
/// ## Security
/// Always check the Source property of the WebView before using ExecuteScript,
/// PostWebMessageAsJson, PostWebMessageAsString, or any other method to send
/// information into the WebView. The WebView may have navigated to another page
/// via the end user interacting with the page or script in the page causing
/// navigation. Similarly, be very careful with
/// AddScriptToExecuteOnDocumentCreated. All future navigations will run this
/// script and if it provides access to information intended only for a certain
/// origin, any HTML document may have access.
///
/// When examining the result of an ExecuteScript method call, a
/// WebMessageReceived event, always check the Source of the sender, or any
/// other mechanism of receiving information from an HTML document in a WebView
/// validate the URI of the HTML document is what you expect.
///
/// When constructing a message to send into a WebView, prefer using
/// PostWebMessageAsJson and construct the JSON string parameter using a JSON
/// library. This will prevent accidentally encoding information into a JSON string
/// or script, and ensure no attacker controlled input can
/// modify the rest of the JSON message or run arbitrary script.
///
/// ## String types
/// String out parameters are LPWSTR null terminated strings. The callee
/// allocates the string using CoTaskMemAlloc. Ownership is transferred to the
/// caller and it is up to the caller to free the memory using CoTaskMemFree.
///
/// String in parameters are LPCWSTR null terminated strings. The caller ensures
/// the string is valid for the duration of the synchronous function call.
/// If the callee needs to retain that value to some point after the function
/// call completes, the callee must allocate its own copy of the string value.
///
/// ## URI and JSON parsing
/// Various methods provide or accept URIs and JSON as strings. Please use your
/// own preferred library for parsing and generating these strings.
///
/// If WinRT is available for your app you can use `Windows.Data.Json.JsonObject`
/// and `IJsonObjectStatics` to parse or produce JSON strings or `Windows.Foundation.Uri`
/// and `IUriRuntimeClassFactory` to parse and produce URIs. Both of these work
/// in Win32 apps.
///
/// If you use IUri and CreateUri to parse URIs you may want to use the
/// following URI creation flags to have CreateUri behavior more closely match
/// the URI parsing in the WebView:
/// `Uri_CREATE_ALLOW_IMPLICIT_FILE_SCHEME | Uri_CREATE_NO_DECODE_EXTRA_INFO`
///
/// ## Debugging
/// Open DevTools with the normal shortcuts: `F12` or `Ctrl+Shift+I`.
/// You can use the `--auto-open-devtools-for-tabs` command argument switch to
/// have the DevTools window open immediately when first creating a WebView. See
/// CreateCoreWebView2Controller documentation for how to provide additional command
/// line arguments to the browser process.
/// Check out the LoaderOverride registry key in the CreateCoreWebView2Controller
/// documentation.
///
/// ## Versioning
/// After you've used a particular version of the SDK to build your app, your
/// app may end up running with an older or newer version of installed browser
/// binaries. Until version 1.0.0.0 of WebView2 there may be breaking changes
/// during updates that will prevent your SDK from working with different
/// versions of installed browser binaries. After version 1.0.0.0 different
/// versions of the SDK can work with different versions of the installed
/// browser by following these best practices:
///
/// To account for breaking changes to the API be sure to check for failure when
/// calling the DLL export CreateCoreWebView2Environment and when
/// calling QueryInterface on any CoreWebView2 object. A return value of
/// E_NOINTERFACE can indicate the SDK is not compatible with the Edge
/// browser binaries.
///
/// Checking for failure from QueryInterface will also account for cases where
/// the SDK is newer than the version of the Edge browser and your app attempts
/// to use an interface of which the Edge browser is unaware.
///
/// When an interface is unavailable, you can consider disabling the associated
/// feature if possible, or otherwise informing the end user they need to update
/// their browser.
const GUID IID_ICoreWebView2 = ICoreWebView2.iid;

interface ICoreWebView2 : IUnknown
{
    static const GUID iid = { 0x76eceacb,0x0462,0x4d94,[ 0xac,0x83,0x42,0x3a,0x67,0x93,0x77,0x5e ] };
    extern(Windows):
  /// The ICoreWebView2Settings object contains various modifiable settings for
  /// the running WebView.
  /+[ propget]+/
	HRESULT get_Settings(/+[out, retval]+/ ICoreWebView2Settings * settings);

  /// The URI of the current top level document. This value potentially
  /// changes as a part of the SourceChanged event firing for some cases
  /// such as navigating to a different site or fragment navigations. It will
  /// remain the same for other types of navigations such as page reloads or
  /// history.pushState with the same URL as the current page.
  ///
  /// \snippet ControlComponent.cpp SourceChanged
  /+[ propget]+/
	HRESULT get_Source(/+[out, retval]+/ LPWSTR* uri);

  /// Cause a navigation of the top level document to the specified URI. See
  /// the navigation events for more information. Note that this starts a
  /// navigation and the corresponding NavigationStarting event will fire
  /// sometime after this Navigate call completes.
  ///
  /// \snippet ControlComponent.cpp Navigate
  HRESULT Navigate(in LPCWSTR uri);

  /// Initiates a navigation to htmlContent as source HTML of a new
  /// document. The htmlContent parameter may not be larger than 2 MB
  /// in total size. The origin of the new page will be about:blank.
  ///
  /// \snippet SettingsComponent.cpp NavigateToString
  HRESULT NavigateToString(in LPCWSTR htmlContent);

  /// Add an event handler for the NavigationStarting event.
  /// NavigationStarting fires when the WebView main frame is
  /// requesting permission to navigate to a different URI. This will fire for
  /// redirects as well.
  ///
  /// Corresponding navigations can be blocked until the event handler returns.
  ///
  /// \snippet SettingsComponent.cpp NavigationStarting
  HRESULT add_NavigationStarting(
      /+[in]+/ ICoreWebView2NavigationStartingEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_NavigationStarting.
  HRESULT remove_NavigationStarting(
      in EventRegistrationToken token);

  /// Add an event handler for the ContentLoading event.
  /// ContentLoading fires before any content is loaded, including scripts added
  /// with AddScriptToExecuteOnDocumentCreated.
  /// ContentLoading will not fire if a same page navigation occurs
  /// (such as through fragment navigations or history.pushState navigations).
  /// This follows the NavigationStarting and SourceChanged events and
  /// precedes the HistoryChanged and NavigationCompleted events.
  HRESULT add_ContentLoading(
      /+[in]+/ ICoreWebView2ContentLoadingEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_ContentLoading.
  HRESULT remove_ContentLoading(
      in EventRegistrationToken token);

  /// Add an event handler for the SourceChanged event.
  /// SourceChanged fires when the Source property changes.
  /// SourceChanged fires for navigating to a different site or fragment
  /// navigations.
  /// It will not fire for other types of navigations such as page reloads or
  /// history.pushState with the same URL as the current page.
  /// SourceChanged fires before ContentLoading for navigation to a new document.
  ///
  /// \snippet ControlComponent.cpp SourceChanged
  HRESULT add_SourceChanged(
      /+[in]+/ ICoreWebView2SourceChangedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_SourceChanged.
  HRESULT remove_SourceChanged(
      in EventRegistrationToken token);

  /// Add an event handler for the HistoryChanged event.
  /// HistoryChanged listens to the change of navigation history for the top
  /// level document. Use HistoryChanged to check if CanGoBack/CanGoForward
  /// value has changed. HistoryChanged also fires for using GoBack/GoForward.
  /// HistoryChanged fires after SourceChanged and ContentLoading.
  ///
  /// \snippet ControlComponent.cpp HistoryChanged
  HRESULT add_HistoryChanged(
      /+[in]+/ ICoreWebView2HistoryChangedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_HistoryChanged.
  HRESULT remove_HistoryChanged(
      in EventRegistrationToken token);

  /// Add an event handler for the NavigationCompleted event.
  /// NavigationCompleted fires when the WebView has completely loaded
  /// (body.onload has fired) or loading stopped with error.
  ///
  /// \snippet ControlComponent.cpp NavigationCompleted
  HRESULT add_NavigationCompleted(
      /+[in]+/ ICoreWebView2NavigationCompletedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_NavigationCompleted.
  HRESULT remove_NavigationCompleted(
      in EventRegistrationToken token);

  /// Add an event handler for the FrameNavigationStarting event.
  /// FrameNavigationStarting fires when a child frame in the WebView
  /// requests permission to navigate to a different URI. This will fire for
  /// redirects as well.
  ///
  /// Corresponding navigations can be blocked until the event handler returns.
  ///
  /// \snippet SettingsComponent.cpp FrameNavigationStarting
  HRESULT add_FrameNavigationStarting(
      /+[in]+/ ICoreWebView2NavigationStartingEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_FrameNavigationStarting.
  HRESULT remove_FrameNavigationStarting(
      in EventRegistrationToken token);

  /// Add an event handler for the FrameNavigationCompleted event.
  /// FrameNavigationCompleted fires when a child frame has completely
  /// loaded (body.onload has fired) or loading stopped with error.
  ///
  /// \snippet ControlComponent.cpp FrameNavigationCompleted
  HRESULT add_FrameNavigationCompleted(
      /+[in]+/ ICoreWebView2NavigationCompletedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_FrameNavigationCompleted.
  HRESULT remove_FrameNavigationCompleted(
      in EventRegistrationToken token);

  /// Add an event handler for the ScriptDialogOpening event.
  /// ScriptDialogOpening fires when a JavaScript dialog (alert, confirm,
  /// prompt, or beforeunload) will show for the webview. This event only fires
  /// if the ICoreWebView2Settings::AreDefaultScriptDialogsEnabled property is
  /// set to false. The ScriptDialogOpening event can be used to suppress
  /// dialogs or replace default dialogs with custom dialogs.
  ///
  /// If a deferral is not taken on the event args, the subsequent scripts can be
  /// blocked until the event handler returns. If a deferral is taken, then the
  /// scripts are blocked until the deferral is completed.
  ///
  /// \snippet SettingsComponent.cpp ScriptDialogOpening
  HRESULT add_ScriptDialogOpening(
      /+[in]+/ ICoreWebView2ScriptDialogOpeningEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_ScriptDialogOpening.
  HRESULT remove_ScriptDialogOpening(
      in EventRegistrationToken token);

  /// Add an event handler for the PermissionRequested event.
  /// PermissionRequested fires when content in a WebView requests permission to
  /// access some privileged resources.
  ///
  /// If a deferral is not taken on the event args, the subsequent scripts can
  /// be blocked until the event handler returns. If a deferral is taken, then
  /// the scripts are blocked until the deferral is completed.
  ///
  /// \snippet SettingsComponent.cpp PermissionRequested
  HRESULT add_PermissionRequested(
      /+[in]+/ ICoreWebView2PermissionRequestedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_PermissionRequested.
  HRESULT remove_PermissionRequested(
      in EventRegistrationToken token);

  /// Add an event handler for the ProcessFailed event.
  /// ProcessFailed fires when a WebView process is terminated unexpectedly or
  /// becomes unresponsive.
  ///
  /// \snippet ProcessComponent.cpp ProcessFailed
  HRESULT add_ProcessFailed(
      /+[in]+/ ICoreWebView2ProcessFailedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_ProcessFailed.
  HRESULT remove_ProcessFailed(
      in EventRegistrationToken token);

  /// Add the provided JavaScript to a list of scripts that should be executed
  /// after the global object has been created, but before the HTML document has
  /// been parsed and before any other script included by the HTML document is
  /// executed. This method injects a script that runs on all top-level document
  /// and child frame page navigations.
  /// This method runs asynchronously, and you must wait for the completion
  /// handler to finish before the injected script is ready to run. When this
  /// method completes, the handler's `Invoke` method is called with the `id` of
  /// the injected script. `id` is a string. To remove the injected script, use
  /// `RemoveScriptToExecuteOnDocumentCreated`.
  ///
  /// Note that if an HTML document has sandboxing of some kind via
  /// [sandbox](https://developer.mozilla.org/docs/Web/HTML/Element/iframe#attr-sandbox)
  /// properties or the [Content-Security-Policy HTTP
  /// header](https://developer.mozilla.org/docs/Web/HTTP/Headers/Content-Security-Policy)
  /// this will affect the script run here. So, for example, if the
  /// 'allow-modals' keyword is not set then calls to the `alert` function will
  /// be ignored.
  ///
  /// \snippet ScriptComponent.cpp AddScriptToExecuteOnDocumentCreated
  HRESULT AddScriptToExecuteOnDocumentCreated(
      in LPCWSTR javaScript,
      /+[in]+/ ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler handler);

  /// Remove the corresponding JavaScript added using `AddScriptToExecuteOnDocumentCreated`
  /// with the specified script id.
  HRESULT RemoveScriptToExecuteOnDocumentCreated(in LPCWSTR id);

  /// Execute JavaScript code from the javascript parameter in the
  /// current top level document rendered in the WebView. This will execute
  /// asynchronously and when complete, if a handler is provided in the
  /// ExecuteScriptCompletedHandler parameter, its Invoke method will be
  /// called with the result of evaluating the provided JavaScript. The result
  /// value is a JSON encoded string.
  /// If the result is undefined, contains a reference cycle, or otherwise
  /// cannot be encoded into JSON, the JSON null value will be returned as the
  /// string 'null'. Note that a function that has no explicit return value
  /// returns undefined.
  /// If the executed script throws an unhandled exception, then the result is
  /// also 'null'.
  /// This method is applied asynchronously. If the method is called after
  /// NavigationStarting event during a navigation, the script will be executed
  /// in the new document when loading it, around the time ContentLoading is
  /// fired. ExecuteScript will work even if
  /// ICoreWebView2Settings::IsScriptEnabled is set to FALSE.
  ///
  /// \snippet ScriptComponent.cpp ExecuteScript
  HRESULT ExecuteScript(
      in LPCWSTR javaScript,
      /+[in]+/ ICoreWebView2ExecuteScriptCompletedHandler handler);

  /// Capture an image of what WebView is displaying. Specify the
  /// format of the image with the imageFormat parameter.
  /// The resulting image binary data is written to the provided imageStream
  /// parameter. When CapturePreview finishes writing to the stream, the Invoke
  /// method on the provided handler parameter is called.
  ///
  /// \snippet FileComponent.cpp CapturePreview
  HRESULT CapturePreview(
      in COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT imageFormat,
      in IStream* imageStream,
      /+[in]+/ ICoreWebView2CapturePreviewCompletedHandler handler);

  /// Reload the current page. This is similar to navigating to the URI of
  /// current top level document including all navigation events firing and
  /// respecting any entries in the HTTP cache. But, the back/forward history
  /// will not be modified.
  HRESULT Reload();

  /// Post the specified webMessage to the top level document in this WebView.
  /// The top level document's window.chrome.webview's message event fires.
  /// JavaScript in that document may subscribe and unsubscribe to the event
  /// via the following:
  ///
  /// ```
  ///    window.chrome.webview.addEventListener('message', handler)
  ///    window.chrome.webview.removeEventListener('message', handler)
  /// ```
  ///
  /// The event args is an instance of `MessageEvent`.
  /// The ICoreWebView2Settings::IsWebMessageEnabled setting must be true or
  /// this method will fail with E_INVALIDARG.
  /// The event arg's data property is the webMessage string parameter parsed
  /// as a JSON string into a JavaScript object.
  /// The event arg's source property is a reference to the
  /// `window.chrome.webview` object.
  /// See add_WebMessageReceived for information on sending messages from the
  /// HTML document in the WebView to the host.
  /// This message is sent asynchronously. If a navigation occurs before the
  /// message is posted to the page, then the message will not be sent.
  ///
  /// \snippet ScenarioWebMessage.cpp WebMessageReceived
  HRESULT PostWebMessageAsJson(in LPCWSTR webMessageAsJson);

  /// This is a helper for posting a message that is a simple string
  /// rather than a JSON string representation of a JavaScript object. This
  /// behaves in exactly the same manner as PostWebMessageAsJson but the
  /// `window.chrome.webview` message event arg's data property will be a string
  /// with the same value as webMessageAsString. Use this instead of
  /// PostWebMessageAsJson if you want to communicate via simple strings rather
  /// than JSON objects.
  HRESULT PostWebMessageAsString(in LPCWSTR webMessageAsString);

  /// Add an event handler for the WebMessageReceived event.
  /// WebMessageReceived fires when the
  /// ICoreWebView2Settings::IsWebMessageEnabled setting is set and the top
  /// level document of the WebView calls `window.chrome.webview.postMessage`.
  /// The postMessage function is `void postMessage(object)` where
  /// object is any object supported by JSON conversion.
  ///
  /// \snippet ScenarioWebMessage.html chromeWebView
  ///
  /// When postMessage is called, the handler's Invoke method will be called
  /// with the postMessage's object parameter converted to a JSON string.
  ///
  /// \snippet ScenarioWebMessage.cpp WebMessageReceived
  HRESULT add_WebMessageReceived(
      /+[in]+/ ICoreWebView2WebMessageReceivedEventHandler handler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_WebMessageReceived.
  HRESULT remove_WebMessageReceived(
      in EventRegistrationToken token);

  /// Call an asynchronous DevToolsProtocol method. See the
  /// [DevTools Protocol Viewer](https://aka.ms/DevToolsProtocolDocs)
  /// for a list and description of available methods.
  /// The methodName parameter is the full name of the method in the format
  /// `{domain}.{method}`.
  /// The parametersAsJson parameter is a JSON formatted string containing
  /// the parameters for the corresponding method.
  /// The handler's Invoke method will be called when the method asynchronously
  /// completes. Invoke will be called with the method's return object as a
  /// JSON string.
  ///
  /// \snippet ScriptComponent.cpp CallDevToolsProtocolMethod
  HRESULT CallDevToolsProtocolMethod(
      in LPCWSTR methodName,
      in LPCWSTR parametersAsJson,
      /+[in]+/ ICoreWebView2CallDevToolsProtocolMethodCompletedHandler handler);

  /// The process id of the browser process that hosts the WebView.
  /+[ propget]+/
	HRESULT get_BrowserProcessId(/+[out, retval]+/ UINT32* value);

  /// Returns true if the WebView can navigate to a previous page in the
  /// navigation history.
  /// The HistoryChanged event will fire if CanGoBack changes value.
  /+[ propget]+/
	HRESULT get_CanGoBack(/+[out, retval]+/ BOOL* canGoBack);
  /// Returns true if the WebView can navigate to a next page in the navigation
  /// history.
  /// The HistoryChanged event will fire if CanGoForward changes value.
  /+[ propget]+/
	HRESULT get_CanGoForward(/+[out, retval]+/ BOOL* canGoForward);
  /// Navigates the WebView to the previous page in the navigation history.
  HRESULT GoBack();
  /// Navigates the WebView to the next page in the navigation history.
  HRESULT GoForward();

  /// Get a DevTools Protocol event receiver that allows you to subscribe to
  /// a DevTools Protocol event.
  /// The eventName parameter is the full name of the event in the format
  /// `{domain}.{event}`.
  /// See the [DevTools Protocol Viewer](https://aka.ms/DevToolsProtocolDocs)
  /// for a list of DevTools Protocol events description, and event args.
  ///
  /// \snippet ScriptComponent.cpp DevToolsProtocolEventReceived
  HRESULT GetDevToolsProtocolEventReceiver(
      in LPCWSTR eventName,
      /+[out, retval]+/ ICoreWebView2DevToolsProtocolEventReceiver * receiver);

  /// Stop all navigations and pending resource fetches. Does not stop
  /// scripts.
  HRESULT Stop();

  /// Add an event handler for the NewWindowRequested event.
  /// NewWindowRequested fires when content inside the WebView requests to open
  /// a new window, such as through window.open. The app can pass a target
  /// WebView that will be considered the opened window.
  ///
  /// Scripts resulted in the new window requested can be blocked until the
  /// event handler returns if a deferral is not taken on the event args. If a
  /// deferral is taken, then scripts are blocked until the deferral is
  /// completed.
  ///
  /// \snippet AppWindow.cpp NewWindowRequested
  HRESULT add_NewWindowRequested(
      /+[in]+/ ICoreWebView2NewWindowRequestedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_NewWindowRequested.
  HRESULT remove_NewWindowRequested(
      in EventRegistrationToken token);

  /// Add an event handler for the DocumentTitleChanged event.
  /// DocumentTitleChanged fires when the DocumentTitle property of the WebView
  /// changes and may fire before or after the NavigationCompleted event.
  ///
  /// \snippet FileComponent.cpp DocumentTitleChanged
  HRESULT add_DocumentTitleChanged(
      /+[in]+/ ICoreWebView2DocumentTitleChangedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_DocumentTitleChanged.
  HRESULT remove_DocumentTitleChanged(
      in EventRegistrationToken token);

  /// The title for the current top level document.
  /// If the document has no explicit title or is otherwise empty,
  /// a default that may or may not match the URI of the document will be used.
  /+[ propget]+/
	HRESULT get_DocumentTitle(/+[out, retval]+/ LPWSTR* title);

  /// Add the provided host object to script running in the WebView with the
  /// specified name.
  /// Host objects are exposed as host object proxies via
  /// `window.chrome.webview.hostObjects.<name>`.
  /// Host object proxies are promises and will resolve to an object
  /// representing the host object.
  /// The promise is rejected if the app has not added an object with the name.
  /// When JavaScript code access a property or method of the object, a promise
  /// is return, which will resolve to the value returned from the host for the
  /// property or method, or rejected in case of error such as there is no such
  /// property or method on the object or parameters are invalid.
  /// For example, when the application code does the following:
  ///
  /// ```
  ///    VARIANT object;
  ///    object.vt = VT_DISPATCH;
  ///    object.pdispVal = appObject;
  ///    webview->AddHostObjectToScript(L"host_object", &host);
  /// ```
  ///
  /// JavaScript code in the WebView will be able to access appObject as
  /// following and then access attributes and methods of appObject:
  ///
  /// ```
  ///    let app_object = await window.chrome.webview.hostObjects.host_object;
  ///    let attr1 = await app_object.attr1;
  ///    let result = await app_object.method1(parameters);
  /// ```
  ///
  /// Note that while simple types, IDispatch and array are supported, generic
  /// IUnknown, VT_DECIMAL, or VT_RECORD variant is not supported.
  /// Remote JavaScript objects like callback functions are represented as
  /// an VT_DISPATCH VARIANT with the object implementing IDispatch. The
  /// JavaScript callback method may be invoked using DISPID_VALUE for the
  /// DISPID.
  /// Nested arrays are supported up to a depth of 3.
  /// Arrays of by reference types are not supported.
  /// VT_EMPTY and VT_NULL are mapped into JavaScript as null. In JavaScript
  /// null and undefined are mapped to VT_EMPTY.
  ///
  /// Additionally, all host objects are exposed as
  /// `window.chrome.webview.hostObjects.sync.<name>`. Here the host
  /// objects are exposed as synchronous host object proxies. These are not
  /// promises and calls to functions or property access synchronously block
  /// running script waiting to communicate cross process for the host code to
  /// run. Accordingly this can result in reliability issues and it is
  /// recommended that you use the promise based asynchronous
  /// `window.chrome.webview.hostObjects.<name>` API described above.
  ///
  /// Synchronous host object proxies and asynchronous host object proxies
  /// can both proxy the same host object. Remote changes made by one proxy
  /// will be reflected in any other proxy of that same host object whether
  /// the other proxies and synchronous or asynchronous.
  ///
  /// While JavaScript is blocked on a synchronous call to native code, that
  /// native code is unable to call back to JavaScript. Attempts to do so will
  /// fail with HRESULT_FROM_WIN32(ERROR_POSSIBLE_DEADLOCK).
  ///
  /// Host object proxies are JavaScript Proxy objects that intercept all
  /// property get, property set, and method invocations. Properties or methods
  /// that are a part of the Function or Object prototype are run locally.
  /// Additionally any property or method in the array
  /// `chrome.webview.hostObjects.options.forceLocalProperties` will also be
  /// run locally. This defaults to including optional methods that have
  /// meaning in JavaScript like `toJSON` and `Symbol.toPrimitive`. You can add
  /// more to this array as required.
  ///
  /// There's a method `chrome.webview.hostObjects.cleanupSome` that will best
  /// effort garbage collect host object proxies.
  ///
  /// Host object proxies additionally have the following methods which run
  /// locally:
  ///  * applyHostFunction, getHostProperty, setHostProperty: Perform a
  ///    method invocation, property get, or property set on the host object.
  ///    You can use these to explicitly force a method or property to run
  ///    remotely if there is a conflicting local method or property. For
  ///    instance, `proxy.toString()` will run the local toString method on the
  ///    proxy object. But ``proxy.applyHostFunction('toString')`` runs
  ///    `toString` on the host proxied object instead.
  ///  * getLocalProperty, setLocalProperty: Perform property get, or property
  ///    set locally. You can use these methods to force getting or setting a
  ///    property on the host object proxy itself rather than on the host
  ///    object it represents. For instance, `proxy.unknownProperty` will get the
  ///    property named `unknownProperty` from the host proxied object. But
  ///    ``proxy.getLocalProperty('unknownProperty')`` will get the value of the property
  ///    `unknownProperty` on the proxy object itself.
  ///  * sync: Asynchronous host object proxies expose a sync method which
  ///    returns a promise for a synchronous host object proxy for the same
  ///    host object. For example,
  ///    `chrome.webview.hostObjects.sample.methodCall()` returns an
  ///    asynchronous host object proxy. You can use the `sync` method to
  ///    obtain a synchronous host object proxy instead:
  ///    `const syncProxy = await chrome.webview.hostObjects.sample.methodCall().sync()`
  ///  * async: Synchronous host object proxies expose an async method which
  ///    blocks and returns an asynchronous host object proxy for the same
  ///    host object. For example, `chrome.webview.hostObjects.sync.sample.methodCall()` returns a
  ///    synchronous host object proxy. Calling the `async` method on this blocks
  ///    and then returns an asynchronous host object proxy for the same host object:
  ///    `const asyncProxy = chrome.webview.hostObjects.sync.sample.methodCall().async()`
  ///  * then: Asynchronous host object proxies have a then method. This
  ///    allows them to be awaitable. `then` will return a promise that resolves
  ///    with a representation of the host object. If the proxy represents a
  ///    JavaScript literal then a copy of that is returned locally. If
  ///    the proxy represents a function then a non-awaitable proxy is returned.
  ///    If the proxy represents a JavaScript object with a mix of literal
  ///    properties and function properties, then the a copy of the object is
  ///    returned with some properties as host object proxies.
  ///
  /// All other property and method invocations (other than the above Remote
  /// object proxy methods, forceLocalProperties list, and properties on
  /// Function and Object prototypes) are run remotely. Asynchronous host
  /// object proxies return a promise representing asynchronous completion of
  /// remotely invoking the method, or getting the property.
  /// The promise resolves after the remote operations complete and
  /// the promises resolve to the resulting value of the operation.
  /// Synchronous host object proxies work similarly but block JavaScript
  /// execution and wait for the remote operation to complete.
  ///
  /// Setting a property on an asynchronous host object proxy works slightly
  /// differently. The set returns immediately and the return value is the value
  /// that will be set. This is a requirement of the JavaScript Proxy object.
  /// If you need to asynchronously wait for the property set to complete, use
  /// the setHostProperty method which returns a promise as described above.
  /// Synchronous object property set property synchronously blocks until the
  /// property is set.
  ///
  /// For example, suppose you have a COM object with the following interface
  ///
  /// \snippet HostObjectSample.idl AddHostObjectInterface
  ///
  /// We can add an instance of this interface into our JavaScript with
  /// `AddHostObjectToScript`. In this case we name it `sample`:
  ///
  /// \snippet ScenarioAddHostObject.cpp AddHostObjectToScript
  ///
  /// Then in the HTML document we can use this COM object via `chrome.webview.hostObjects.sample`:
  ///
  /// \snippet ScenarioAddHostObject.html HostObjectUsage
  /// Exposing host objects to script has security risk. Please follow
  /// [best practices](https://docs.microsoft.com/microsoft-edge/webview2/concepts/security).
  HRESULT AddHostObjectToScript(in LPCWSTR name, in VARIANT* object);

  /// Remove the host object specified by the name so that it is no longer
  /// accessible from JavaScript code in the WebView.
  /// While new access attempts will be denied, if the object is already
  /// obtained by JavaScript code in the WebView, the JavaScript code will
  /// continue to have access to that object.
  /// Calling this method for a name that is already removed or never added will
  /// fail.
  HRESULT RemoveHostObjectFromScript(in LPCWSTR name);

  /// Opens the DevTools window for the current document in the WebView.
  /// Does nothing if called when the DevTools window is already open.
  HRESULT OpenDevToolsWindow();

  /// Add an event handler for the ContainsFullScreenElementChanged event.
  /// ContainsFullScreenElementChanged fires when the ContainsFullScreenElement
  /// property changes. This means that an HTML element inside the WebView is
  /// entering fullscreen to the size of the WebView or leaving fullscreen. This
  /// event is useful when, for example, a video element requests to go
  /// fullscreen. The listener of ContainsFullScreenElementChanged can then
  /// resize the WebView in response.
  ///
  /// \snippet AppWindow.cpp ContainsFullScreenElementChanged
  HRESULT add_ContainsFullScreenElementChanged(
      /+[in]+/ ICoreWebView2ContainsFullScreenElementChangedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with
  /// add_ContainsFullScreenElementChanged.
  HRESULT remove_ContainsFullScreenElementChanged(
      in EventRegistrationToken token);

  /// Indicates if the WebView contains a fullscreen HTML element.
  /+[ propget]+/
	HRESULT get_ContainsFullScreenElement(
      /+[out, retval]+/ BOOL* containsFullScreenElement);

  /// Add an event handler for the WebResourceRequested event.
  /// WebResourceRequested fires when the WebView is performing a URL request to
  /// a matching URL and resource context filter that was added with
  /// AddWebResourceRequestedFilter. At least one filter must be added for the
  /// event to fire.
  ///
  /// The web resource requested can be blocked until the event handler returns
  /// if a deferral is not taken on the event args. If a deferral is taken, then
  /// the web resource requested is blocked until the deferral is completed.
  ///
  /// \snippet SettingsComponent.cpp WebResourceRequested
  HRESULT add_WebResourceRequested(
    /+[in]+/ ICoreWebView2WebResourceRequestedEventHandler eventHandler,
    /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_WebResourceRequested.
  HRESULT remove_WebResourceRequested(
      in EventRegistrationToken token);

  /// Adds a URI and resource context filter to the WebResourceRequested event.
  /// The URI parameter can be a wildcard string ('*': zero or more, '?':
  /// exactly one). nullptr is equivalent to L"".
  /// See COREWEBVIEW2_WEB_RESOURCE_CONTEXT enum for description of resource
  /// context filters.
  HRESULT AddWebResourceRequestedFilter(
    in LPCWSTR uri,
    in COREWEBVIEW2_WEB_RESOURCE_CONTEXT resourceContext);
  /// Removes a matching WebResource filter that was previously added for the
  /// WebResourceRequested event. If the same filter was added multiple times,
  /// then it will need to be removed as many times as it was added for the
  /// removal to be effective. Returns E_INVALIDARG for a filter that was never
  /// added.
  HRESULT RemoveWebResourceRequestedFilter(
    in LPCWSTR uri,
    in COREWEBVIEW2_WEB_RESOURCE_CONTEXT resourceContext);

  /// Add an event handler for the WindowCloseRequested event.
  /// WindowCloseRequested fires when content inside the WebView requested to
  /// close the window, such as after window.close is called. The app should
  /// close the WebView and related app window if that makes sense to the app.
  ///
  /// \snippet AppWindow.cpp WindowCloseRequested
  HRESULT add_WindowCloseRequested(
      /+[in]+/ ICoreWebView2WindowCloseRequestedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_WindowCloseRequested.
  HRESULT remove_WindowCloseRequested(
      in EventRegistrationToken token);
}

/// This interface is the owner of the CoreWebView2 object, and provides support
/// for resizing, showing and hiding, focusing, and other functionality related
/// to windowing and composition. The CoreWebView2Controller owns the CoreWebView2,
/// and if all references to the CoreWebView2Controller go away, the WebView will
/// be closed.
const GUID IID_ICoreWebView2Controller = ICoreWebView2Controller.iid;

interface ICoreWebView2Controller : IUnknown
{
    static const GUID iid = { 0x4d00c0d1,0x9434,0x4eb6,[ 0x80,0x78,0x86,0x97,0xa5,0x60,0x33,0x4f ] };
    extern(Windows):
  /// The IsVisible property determines whether to show or hide the WebView.
  /// If IsVisible is set to false, the WebView will be transparent and will
  /// not be rendered.  However, this will not affect the window containing
  /// the WebView (the HWND parameter that was passed to CreateCoreWebView2Controller).
  /// If you want that window to disappear too, call ShowWindow on it directly
  /// in addition to modifying the IsVisible property.
  /// WebView as a child window won't get window messages when the top window
  /// is minimized or restored. For performance reason, developer should set
  /// IsVisible property of the WebView to false when the app window is
  /// minimized and back to true when app window is restored. App window can do
  /// this by handling SC_MINIMIZE and SC_RESTORE command upon receiving
  /// WM_SYSCOMMAND message.
  ///
  /// \snippet ViewComponent.cpp ToggleIsVisible
  /+[ propget]+/
	HRESULT get_IsVisible(/+[out, retval]+/ BOOL* isVisible);
  /// Set the IsVisible property.
  ///
  /// \snippet ViewComponent.cpp ToggleIsVisibleOnMinimize
  /+[ propput]+/
	HRESULT put_IsVisible(in BOOL isVisible);

  /// The WebView bounds.
  /// Bounds are relative to the parent HWND. The app has two ways it can
  /// position a WebView:
  /// 1. Create a child HWND that is the WebView parent HWND. Position this
  ///    window where the WebView should be. In this case, use (0, 0) for the
  ///    WebView's Bound's top left corner (the offset).
  /// 2. Use the app's top most window as the WebView parent HWND. Set the
  ///    WebView's Bound's top left corner so that the WebView is positioned
  ///    correctly in the app.
  /// The Bound's values are in the host's coordinate space.
  /+[ propget]+/
	HRESULT get_Bounds(/+[out, retval]+/ RECT* bounds);
  /// Set the Bounds property.
  ///
  /// \snippet ViewComponent.cpp ResizeWebView
  /+[ propput]+/
	HRESULT put_Bounds(in RECT bounds);

  /// The zoom factor for the WebView.
  /// Note that changing zoom factor could cause `window.innerWidth/innerHeight`
  /// and page layout to change.
  /// A zoom factor that is applied by the host by calling ZoomFactor
  /// becomes the new default zoom for the WebView. This zoom factor applies
  /// across navigations and is the zoom factor WebView is returned to when the
  /// user presses ctrl+0. When the zoom factor is changed by the user
  /// (resulting in the app receiving ZoomFactorChanged), that zoom applies
  /// only for the current page. Any user applied zoom is only for the current
  /// page and is reset on a navigation.
  /// Specifying a zoomFactor less than or equal to 0 is not allowed.
  /// WebView also has an internal supported zoom factor range. When a specified
  /// zoom factor is out of that range, it will be normalized to be within the
  /// range, and a ZoomFactorChanged event will be fired for the real
  /// applied zoom factor. When this range normalization happens, the
  /// ZoomFactor property will report the zoom factor specified during the
  /// previous modification of the ZoomFactor property until the
  /// ZoomFactorChanged event is received after WebView applies the normalized
  /// zoom factor.
  /+[ propget]+/
	HRESULT get_ZoomFactor(/+[out, retval]+/ double* zoomFactor);
  /// Set the ZoomFactor property.
  /+[ propput]+/
	HRESULT put_ZoomFactor(in double zoomFactor);

  /// Add an event handler for the ZoomFactorChanged event.
  /// ZoomFactorChanged fires when the ZoomFactor property of the WebView changes.
  /// The event could fire because the caller modified the ZoomFactor property,
  /// or due to the user manually modifying the zoom. When it is modified by the
  /// caller via the ZoomFactor property, the internal zoom factor is updated
  /// immediately and there will be no ZoomFactorChanged event.
  /// WebView associates the last used zoom factor for each site. Therefore, it
  /// is possible for the zoom factor to change when navigating to a different
  /// page. When the zoom factor changes due to this, the ZoomFactorChanged
  /// event fires right after the ContentLoading event.
  ///
  /// \snippet ViewComponent.cpp ZoomFactorChanged
  HRESULT add_ZoomFactorChanged(
      /+[in]+/ ICoreWebView2ZoomFactorChangedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_ZoomFactorChanged.
  HRESULT remove_ZoomFactorChanged(
      in EventRegistrationToken token);

  /// Update Bounds and ZoomFactor properties at the same time. This operation
  /// is atomic from the host's perspective. After returning from this function,
  /// the Bounds and ZoomFactor properties will have both been updated if the
  /// function is successful, or neither will be updated if the function fails.
  /// If Bounds and ZoomFactor are both updated by the same scale (i.e. Bounds
  /// and ZoomFactor are both doubled), then the page will not see a change in
  /// window.innerWidth/innerHeight and the WebView will render the content at
  /// the new size and zoom without intermediate renderings.
  /// This function can also be used to update just one of ZoomFactor or Bounds
  /// by passing in the new value for one and the current value for the other.
  ///
  /// \snippet ViewComponent.cpp SetBoundsAndZoomFactor
  HRESULT SetBoundsAndZoomFactor(in RECT bounds, in double zoomFactor);

  /// Move focus into WebView. WebView will get focus and focus will be set to
  /// correspondent element in the page hosted in the WebView.
  /// For Programmatic reason, focus is set to previously focused element or
  /// the default element if there is no previously focused element.
  /// For Next reason, focus is set to the first element.
  /// For Previous reason, focus is set to the last element.
  /// WebView can also got focus through user interaction like clicking into
  /// WebView or Tab into it.
  /// For tabbing, the app can call MoveFocus with Next or Previous to align
  /// with tab and shift+tab respectively when it decides the WebView is the
  /// next tabbable element. Or, the app can call IsDialogMessage as part of
  /// its message loop to allow the platform to auto handle tabbing. The
  /// platform will rotate through all windows with WS_TABSTOP. When the
  /// WebView gets focus from IsDialogMessage, it will internally put the focus
  /// on the first or last element for tab and shift+tab respectively.
  ///
  /// \snippet App.cpp MoveFocus0
  ///
  /// \snippet ControlComponent.cpp MoveFocus1
  ///
  /// \snippet ControlComponent.cpp MoveFocus2
  HRESULT MoveFocus(in COREWEBVIEW2_MOVE_FOCUS_REASON reason);

  /// Add an event handler for the MoveFocusRequested event.
  /// MoveFocusRequested fires when user tries to tab out of the WebView.
  /// The WebView's focus has not changed when this event is fired.
  ///
  /// \snippet ControlComponent.cpp MoveFocusRequested
  HRESULT add_MoveFocusRequested(
      /+[in]+/ ICoreWebView2MoveFocusRequestedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_MoveFocusRequested.
  HRESULT remove_MoveFocusRequested(
      in EventRegistrationToken token);

  /// Add an event handler for the GotFocus event.
  /// GotFocus fires when WebView got focus.
  HRESULT add_GotFocus(
      /+[in]+/ ICoreWebView2FocusChangedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_GotFocus.
  HRESULT remove_GotFocus(
      in EventRegistrationToken token);

  /// Add an event handler for the LostFocus event.
  /// LostFocus fires when WebView lost focus.
  /// In the case where MoveFocusRequested event is fired, the focus is still
  /// on WebView when MoveFocusRequested event fires. LostFocus only fires
  /// afterwards when app's code or default action of MoveFocusRequested event
  /// set focus away from WebView.
  HRESULT add_LostFocus(
      /+[in]+/ ICoreWebView2FocusChangedEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_LostFocus.
  HRESULT remove_LostFocus(
      in EventRegistrationToken token);

  /// Add an event handler for the AcceleratorKeyPressed event.
  /// AcceleratorKeyPressed fires when an accelerator key or key combo is
  /// pressed or released while the WebView is focused. A key is considered an
  /// accelerator if either:
  ///   1. Ctrl or Alt is currently being held, or
  ///   2. the pressed key does not map to a character.
  /// A few specific keys are never considered accelerators, such as Shift.
  /// The Escape key is always considered an accelerator.
  ///
  /// Autorepeated key events caused by holding the key down will also fire this
  /// event.  You can filter these out by checking the event args'
  /// KeyEventLParam or PhysicalKeyStatus.
  ///
  /// In windowed mode, this event handler is called synchronously. Until you
  /// call Handled() on the event args or the event handler returns, the browser
  /// process will be blocked and outgoing cross-process COM calls will fail
  /// with RPC_E_CANTCALLOUT_ININPUTSYNCCALL. All CoreWebView2 API methods will
  /// work, however.
  ///
  /// In windowless mode, the event handler is called asynchronously.  Further
  /// input will not reach the browser until the event handler returns or
  /// Handled() is called, but the browser process itself will not be blocked,
  /// and outgoing COM calls will work normally.
  ///
  /// It is recommended to call Handled(TRUE) as early as you can know that you want
  /// to handle the accelerator key.
  ///
  /// \snippet ControlComponent.cpp AcceleratorKeyPressed
  HRESULT add_AcceleratorKeyPressed(
    /+[in]+/ ICoreWebView2AcceleratorKeyPressedEventHandler eventHandler,
    /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with add_AcceleratorKeyPressed.
  HRESULT remove_AcceleratorKeyPressed(
    in EventRegistrationToken token);

  /// The parent window provided by the app that this WebView is using to
  /// render content. This API initially returns the window passed into
  /// CreateCoreWebView2Controller.
  /+[ propget]+/
	HRESULT get_ParentWindow(/+[out, retval]+/ HWND* parentWindow);

  /// Set the parent window for the WebView. This will cause the WebView to
  /// reparent its window to the newly provided window.
  /+[ propput]+/
	HRESULT put_ParentWindow(in HWND parentWindow);

  /// This is a notification separate from Bounds that tells WebView its
  /// parent (or any ancestor) HWND moved. This is needed for accessibility and
  /// certain dialogs in WebView to work correctly.
  /// \snippet ViewComponent.cpp NotifyParentWindowPositionChanged
  HRESULT NotifyParentWindowPositionChanged();

  /// Closes the WebView and cleans up the underlying browser instance.
  /// Cleaning up the browser instance will release the resources powering the WebView.
  /// The browser instance will be shut down if there are no other WebViews using it.
  ///
  /// After calling Close, all method calls will fail and event handlers
  /// will stop firing. Specifically, the WebView will release its references
  /// to its event handlers when Close is called.
  ///
  /// Close is implicitly called when the CoreWebView2Controller loses its final
  /// reference and is destructed. But it is best practice to explicitly call
  /// Close to avoid any accidental cycle of references between the WebView
  /// and the app code. Specifically, if you capture a reference to the WebView
  /// in an event handler you will create a reference cycle between the WebView
  /// and the event handler. Calling Close will break this cycle by releasing
  /// all event handlers. But to avoid this situation it is best practice both
  /// to explicitly call Close on the WebView and to not capture a reference to
  /// the WebView to ensure the WebView can be cleaned up correctly.
  ///
  /// \snippet AppWindow.cpp Close
  HRESULT Close();

  /// Gets the CoreWebView2 associated with this CoreWebView2Controller.
  /+[ propget]+/
	HRESULT get_CoreWebView2(/+[out, retval]+/ ICoreWebView2 * coreWebView2);
}

/// This interface is used to complete deferrals on event args that
/// support getting deferrals via their GetDeferral method.
const GUID IID_ICoreWebView2Deferral = ICoreWebView2Deferral.iid;

interface ICoreWebView2Deferral : IUnknown
{
    static const GUID iid = { 0xc10e7f7b,0xb585,0x46f0,[ 0xa6,0x23,0x8b,0xef,0xbf,0x3e,0x4e,0xe0 ] };
    extern(Windows):
  /// Completes the associated deferred event. Complete should only be
  /// called once for each deferral taken.
  HRESULT Complete();
}

/// Defines properties that enable, disable, or modify WebView
/// features. Setting changes made after NavigationStarting event will not
/// apply until the next top level navigation.
const GUID IID_ICoreWebView2Settings = ICoreWebView2Settings.iid;

interface ICoreWebView2Settings : IUnknown
{
    static const GUID iid = { 0xe562e4f0,0xd7fa,0x43ac,[ 0x8d,0x71,0xc0,0x51,0x50,0x49,0x9f,0x00 ] };
    extern(Windows):
  /// Controls if JavaScript execution is enabled in all future
  /// navigations in the WebView.  This only affects scripts in the document;
  /// scripts injected with ExecuteScript will run even if script is disabled.
  /// It is true by default.
  ///
  /// \snippet SettingsComponent.cpp IsScriptEnabled
  /+[ propget]+/
	HRESULT get_IsScriptEnabled(
      /+[out, retval]+/ BOOL* isScriptEnabled);
  /// Set the IsScriptEnabled property.
  /+[ propput]+/
	HRESULT put_IsScriptEnabled(in BOOL isScriptEnabled);

  /// The IsWebMessageEnabled property is used when loading a new
  /// HTML document. If set to true, communication from the host to the
  /// WebView's top level HTML document is allowed via PostWebMessageAsJson,
  /// PostWebMessageAsString, and window.chrome.webview's message event
  /// (see PostWebMessageAsJson documentation for details).
  /// Communication from the WebView's top level HTML document to the host is
  /// allowed via window.chrome.webview's postMessage function and
  /// add_WebMessageReceived method (see add_WebMessageReceived documentation
  /// for details).
  /// If set to false, then communication is disallowed.
  /// PostWebMessageAsJson and PostWebMessageAsString will
  /// fail with E_ACCESSDENIED and window.chrome.webview.postMessage will fail
  /// by throwing an instance of an Error object.
  /// It is true by default.
  ///
  /// \snippet ScenarioWebMessage.cpp IsWebMessageEnabled
  /+[ propget]+/
	HRESULT get_IsWebMessageEnabled(
      /+[out, retval]+/ BOOL* isWebMessageEnabled);
  /// Set the IsWebMessageEnabled property.
  /+[ propput]+/
	HRESULT put_IsWebMessageEnabled(in BOOL isWebMessageEnabled);

  /// AreDefaultScriptDialogsEnabled is used when loading a new HTML document.
  /// If set to false, then WebView won't render the default JavaScript dialog
  /// box (Specifically those shown by the JavaScript alert, confirm, prompt
  /// functions and beforeunload event). Instead, if an event handler is set via
  /// add_ScriptDialogOpening, WebView will send an event that will contain all
  /// of the information for the dialog and allow the host app to show its own
  /// custom UI. It is true by default.
  /+[ propget]+/
	HRESULT get_AreDefaultScriptDialogsEnabled(
      /+[out, retval]+/ BOOL* areDefaultScriptDialogsEnabled);
  /// Set the AreDefaultScriptDialogsEnabled property.
  /+[ propput]+/
	HRESULT put_AreDefaultScriptDialogsEnabled(
      in BOOL areDefaultScriptDialogsEnabled);

  /// IsStatusBarEnabled controls whether the status bar will be displayed. The
  /// status bar is usually displayed in the lower left of the WebView and shows
  /// things such as the URI of a link when the user hovers over it and other
  /// information. It is true by default.
  /+[ propget]+/
	HRESULT get_IsStatusBarEnabled(/+[out, retval]+/ BOOL* isStatusBarEnabled);
  /// Set the IsStatusBarEnabled property.
  /+[ propput]+/
	HRESULT put_IsStatusBarEnabled(in BOOL isStatusBarEnabled);

  /// AreDevToolsEnabled controls whether the user is able to use the context
  /// menu or keyboard shortcuts to open the DevTools window.
  /// It is true by default.
  /+[ propget]+/
	HRESULT get_AreDevToolsEnabled(/+[out, retval]+/ BOOL* areDevToolsEnabled);
  /// Set the AreDevToolsEnabled property.
  /+[ propput]+/
	HRESULT put_AreDevToolsEnabled(in BOOL areDevToolsEnabled);

  /// The AreDefaultContextMenusEnabled property is used to prevent
  /// default context menus from being shown to user in WebView.
  /// It is true by default.
  ///
  /// \snippet SettingsComponent.cpp DisableContextMenu
  /+[ propget]+/
	HRESULT get_AreDefaultContextMenusEnabled(/+[out, retval]+/ BOOL* enabled);
  /// Set the AreDefaultContextMenusEnabled property.
  /+[ propput]+/
	HRESULT put_AreDefaultContextMenusEnabled(in BOOL enabled);

  /// The AreHostObjectsAllowed property is used to control whether
  /// host objects are accessible from the page in WebView.
  /// It is true by default.
  ///
  /// \snippet SettingsComponent.cpp HostObjectsAccess
  /+[ propget]+/
	HRESULT get_AreHostObjectsAllowed(/+[out, retval]+/ BOOL* allowed);
  /// Set the AreHostObjectsAllowed property.
  /+[ propput]+/
	HRESULT put_AreHostObjectsAllowed(in BOOL allowed);

  /// The IsZoomControlEnabled property is used to prevent the user from
  /// impacting the zoom of the WebView. It is true by default.
  /// When disabled, user will not be able to zoom using ctrl+/- or
  /// ctrl+mouse wheel, but the zoom can be set via ZoomFactor API.
  ///
  /// \snippet SettingsComponent.cpp DisableZoomControl
  /+[ propget]+/
	HRESULT get_IsZoomControlEnabled(/+[out, retval]+/ BOOL* enabled);
  /// Set the IsZoomControlEnabled property.
  /+[ propput]+/
	HRESULT put_IsZoomControlEnabled(in BOOL enabled);

  /// The IsBuiltInErrorPageEnabled property is used to disable built in error
  /// page for navigation failure and render process failure. It is true by
  /// default.
  /// When disabled, blank page will be shown when related error happens.
  ///
  /// \snippet SettingsComponent.cpp BuiltInErrorPageEnabled
  /+[ propget]+/
	HRESULT get_IsBuiltInErrorPageEnabled(/+[out, retval]+/ BOOL* enabled);
  /// Set the IsBuiltInErrorPageEnabled property.
  /+[ propput]+/
	HRESULT put_IsBuiltInErrorPageEnabled(in BOOL enabled);
}

/// Event args for the ProcessFailed event.
const GUID IID_ICoreWebView2ProcessFailedEventArgs = ICoreWebView2ProcessFailedEventArgs.iid;

interface ICoreWebView2ProcessFailedEventArgs : IUnknown
{
    static const GUID iid = { 0x8155a9a4,0x1474,0x4a86,[ 0x8c,0xae,0x15,0x1b,0x0f,0xa6,0xb8,0xca ] };
    extern(Windows):
  /// The kind of process failure that has occurred.
  /+[ propget]+/
	HRESULT get_ProcessFailedKind(
      /+[out, retval]+/ COREWEBVIEW2_PROCESS_FAILED_KIND* processFailedKind);
}

/// The caller implements this interface to receive ProcessFailed events.
const GUID IID_ICoreWebView2ProcessFailedEventHandler = ICoreWebView2ProcessFailedEventHandler.iid;

interface ICoreWebView2ProcessFailedEventHandler : IUnknown
{
    static const GUID iid = { 0x79e0aea4,0x990b,0x42d9,[ 0xaa,0x1d,0x0f,0xcc,0x2e,0x5b,0xc7,0xf1 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2ProcessFailedEventArgs args);
}

/// The caller implements this interface to receive ZoomFactorChanged
/// events. Use the ICoreWebView2Controller.ZoomFactor property to get the
/// modified zoom factor.
const GUID IID_ICoreWebView2ZoomFactorChangedEventHandler = ICoreWebView2ZoomFactorChangedEventHandler.iid;

interface ICoreWebView2ZoomFactorChangedEventHandler : IUnknown
{
    static const GUID iid = { 0xb52d71d6,0xc4df,0x4543,[ 0xa9,0x0c,0x64,0xa3,0xe6,0x0f,0x38,0xcb ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event. There are no event args and the args
  /// parameter will be null.
  HRESULT Invoke(/+[in]+/ ICoreWebView2Controller sender, /+[in]+/ IUnknown args);
}

/// Iterator for a collection of HTTP headers. See ICoreWebView2HttpRequestHeaders
/// and ICoreWebView2HttpResponseHeaders.
///
/// \snippet ScenarioWebViewEventMonitor.cpp HttpRequestHeaderIterator
const GUID IID_ICoreWebView2HttpHeadersCollectionIterator = ICoreWebView2HttpHeadersCollectionIterator.iid;

interface ICoreWebView2HttpHeadersCollectionIterator : IUnknown
{
    static const GUID iid = { 0x0702fc30,0xf43b,0x47bb,[ 0xab,0x52,0xa4,0x2c,0xb5,0x52,0xad,0x9f ] };
    extern(Windows):
  /// Get the name and value of the current HTTP header of the iterator. This
  /// method will fail if the last call to MoveNext set hasNext to FALSE.
  HRESULT GetCurrentHeader(/+[out]+/ LPWSTR* name, 
		/+[out]+/ LPWSTR* value);

  /// True when the iterator hasn't run out of headers. If the collection over
  /// which the iterator is iterating is empty or if the iterator has gone past
  /// the end of the collection then this is false.
  /+[ propget]+/
	HRESULT get_HasCurrentHeader(/+[out, retval]+/ BOOL* hasCurrent);

  /// Move the iterator to the next HTTP header in the collection. The hasNext
  /// parameter will be set to FALSE if there are no more HTTP headers. After
  /// this occurs the GetCurrentHeader method will fail if called.
  HRESULT MoveNext(/+[out, retval]+/ BOOL* hasNext);
}

/// HTTP request headers. Used to inspect the HTTP request on
/// WebResourceRequested event and NavigationStarting event.
/// Note, you can modify the HTTP request headers from a WebResourceRequested event,
/// but not from a NavigationStarting event.
const GUID IID_ICoreWebView2HttpRequestHeaders = ICoreWebView2HttpRequestHeaders.iid;

interface ICoreWebView2HttpRequestHeaders : IUnknown
{
    static const GUID iid = { 0xe86cac0e,0x5523,0x465c,[ 0xb5,0x36,0x8f,0xb9,0xfc,0x8c,0x8c,0x60 ] };
    extern(Windows):
  /// Gets the header value matching the name.
  HRESULT GetHeader(in LPCWSTR name, 
		/+[out, retval]+/ LPWSTR* value);
  /// Gets the header value matching the name via an iterator.
  HRESULT GetHeaders(in LPCWSTR name, 
		/+[out, retval]+/ ICoreWebView2HttpHeadersCollectionIterator * iterator);
  /// Checks whether the headers contain an entry matching the header name.
  HRESULT Contains(in LPCWSTR name, 
		/+[out, retval]+/ BOOL* contains);
  /// Adds or updates header that matches the name.
  HRESULT SetHeader(in LPCWSTR name, in LPCWSTR value);
  /// Removes header that matches the name.
  HRESULT RemoveHeader(in LPCWSTR name);
  /// Gets an iterator over the collection of request headers.
  HRESULT GetIterator(
      /+[out, retval]+/ ICoreWebView2HttpHeadersCollectionIterator * iterator);
}

/// HTTP response headers. Used to construct a WebResourceResponse for the
/// WebResourceRequested event.
const GUID IID_ICoreWebView2HttpResponseHeaders = ICoreWebView2HttpResponseHeaders.iid;

interface ICoreWebView2HttpResponseHeaders : IUnknown
{
    static const GUID iid = { 0x03c5ff5a,0x9b45,0x4a88,[ 0x88,0x1c,0x89,0xa9,0xf3,0x28,0x61,0x9c ] };
    extern(Windows):
  /// Appends header line with name and value.
  HRESULT AppendHeader(in LPCWSTR name, in LPCWSTR value);
  /// Checks whether the headers contain entries matching the header name.
  HRESULT Contains(in LPCWSTR name, 
		/+[out, retval]+/ BOOL* contains);
  /// Gets the first header value in the collection matching the name.
  HRESULT GetHeader(in LPCWSTR name, 
		/+[out, retval]+/ LPWSTR* value);
  /// Gets the header values matching the name.
  HRESULT GetHeaders(in LPCWSTR name, 
		/+[out, retval]+/ ICoreWebView2HttpHeadersCollectionIterator * iterator);
  /// Gets an iterator over the collection of entire response headers.
  HRESULT GetIterator(
  /+[out, retval]+/ ICoreWebView2HttpHeadersCollectionIterator * iterator);
}

/// An HTTP request used with the WebResourceRequested event.
const GUID IID_ICoreWebView2WebResourceRequest = ICoreWebView2WebResourceRequest.iid;

interface ICoreWebView2WebResourceRequest : IUnknown
{
    static const GUID iid = { 0x97055cd4,0x512c,0x4264,[ 0x8b,0x5f,0xe3,0xf4,0x46,0xce,0xa6,0xa5 ] };
    extern(Windows):
  /// The request URI.
  /+[ propget]+/
	HRESULT get_Uri(/+[out, retval]+/ LPWSTR* uri);
  /// Set the Uri property.
  /+[ propput]+/
	HRESULT put_Uri(in LPCWSTR uri);

  /// The HTTP request method.
  /+[ propget]+/
	HRESULT get_Method(/+[out, retval]+/ LPWSTR* method);
  /// Set the Method property.
  /+[ propput]+/
	HRESULT put_Method(in LPCWSTR method);

  /// The HTTP request message body as stream. POST data would be here.
  /// If a stream is set, which will override the message body, the stream must
  /// have all the content data available by the time this
  /// response's WebResourceRequested event deferral is completed. Stream
  /// should be agile or be created from a background STA to prevent performance
  /// impact to the UI thread. Null means no content data. IStream semantics
  /// apply (return S_OK to Read calls until all data is exhausted).
  /+[ propget]+/
	HRESULT get_Content(/+[out, retval]+/ IStream** content);
  /// Set the Content property.
  /+[ propput]+/
	HRESULT put_Content(in IStream* content);

  /// The mutable HTTP request headers
  /+[ propget]+/
	HRESULT get_Headers(/+[out, retval]+/ ICoreWebView2HttpRequestHeaders * headers);
}

/// An HTTP response used with the WebResourceRequested event.
const GUID IID_ICoreWebView2WebResourceResponse = ICoreWebView2WebResourceResponse.iid;

interface ICoreWebView2WebResourceResponse : IUnknown
{
    static const GUID iid = { 0xaafcc94f,0xfa27,0x48fd,[ 0x97,0xdf,0x83,0x0e,0xf7,0x5a,0xae,0xc9 ] };
    extern(Windows):
  /// HTTP response content as stream. Stream must have all the
  /// content data available by the time this response's WebResourceRequested
  /// event deferral is completed. Stream should be agile or be created from
  /// a background thread to prevent performance impact to the UI thread.
  /// Null means no content data. IStream semantics
  /// apply (return S_OK to Read calls until all data is exhausted).
  /+[ propget]+/
	HRESULT get_Content(/+[out, retval]+/ IStream** content);
  /// Set the Content property.
  /+[ propput]+/
	HRESULT put_Content(in IStream* content);

  /// Overridden HTTP response headers.
  /+[ propget]+/
	HRESULT get_Headers(/+[out, retval]+/ ICoreWebView2HttpResponseHeaders * headers);

  /// The HTTP response status code.
  /+[ propget]+/
	HRESULT get_StatusCode(/+[out, retval]+/ int* statusCode);
  /// Set the StatusCode property.
  /+[ propput]+/
	HRESULT put_StatusCode(in int statusCode);

  /// The HTTP response reason phrase.
  /+[ propget]+/
	HRESULT get_ReasonPhrase(/+[out, retval]+/ LPWSTR* reasonPhrase);
  /// Set the ReasonPhrase property.
  /+[ propput]+/
	HRESULT put_ReasonPhrase(in LPCWSTR reasonPhrase);
}

/// Event args for the NavigationStarting event.
const GUID IID_ICoreWebView2NavigationStartingEventArgs = ICoreWebView2NavigationStartingEventArgs.iid;

interface ICoreWebView2NavigationStartingEventArgs : IUnknown
{
    static const GUID iid = { 0x5b495469,0xe119,0x438a,[ 0x9b,0x18,0x76,0x04,0xf2,0x5f,0x2e,0x49 ] };
    extern(Windows):
  /// The uri of the requested navigation.
  /+[ propget]+/
	HRESULT get_Uri(/+[out, retval]+/ LPWSTR* uri);

  /// True when the navigation was initiated through a user gesture as opposed
  /// to programmatic navigation.
  /+[ propget]+/
	HRESULT get_IsUserInitiated(/+[out, retval]+/ BOOL* isUserInitiated);

  /// True when the navigation is redirected.
  /+[ propget]+/
	HRESULT get_IsRedirected(/+[out, retval]+/ BOOL* isRedirected);

  /// The HTTP request headers for the navigation.
  /// Note, you cannot modify the HTTP request headers in a NavigationStarting event.
  /+[ propget]+/
	HRESULT get_RequestHeaders(/+[out, retval]+/ ICoreWebView2HttpRequestHeaders * requestHeaders);

  /// The host may set this flag to cancel the navigation.
  /// If set, it will be as if the navigation never happened and the current
  /// page's content will be intact. For performance reasons, GET HTTP requests
  /// may happen, while the host is responding. This means cookies can be set
  /// and used part of a request for the navigation.
  /// Cancellation for navigation to about:blank or frame navigation to srcdoc
  /// is not supported. Such attempts will be ignored.
  /+[ propget]+/
	HRESULT get_Cancel(/+[out, retval]+/ BOOL* cancel);
  /// Set the Cancel property.
  /+[ propput]+/
	HRESULT put_Cancel(in BOOL cancel);

  /// The ID of the navigation.
  /+[ propget]+/
	HRESULT get_NavigationId(/+[out, retval]+/ UINT64* navigationId);
}

/// The caller implements this interface to receive the NavigationStarting
/// event.
const GUID IID_ICoreWebView2NavigationStartingEventHandler = ICoreWebView2NavigationStartingEventHandler.iid;

interface ICoreWebView2NavigationStartingEventHandler : IUnknown
{
    static const GUID iid = { 0x9adbe429,0xf36d,0x432b,[ 0x9d,0xdc,0xf8,0x88,0x1f,0xbd,0x76,0xe3 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2NavigationStartingEventArgs args);
}

/// Event args for the ContentLoading event.
const GUID IID_ICoreWebView2ContentLoadingEventArgs = ICoreWebView2ContentLoadingEventArgs.iid;

interface ICoreWebView2ContentLoadingEventArgs : IUnknown
{
    static const GUID iid = { 0x0c8a1275,0x9b6b,0x4901,[ 0x87,0xad,0x70,0xdf,0x25,0xba,0xfa,0x6e ] };
    extern(Windows):
  /// True if the loaded content is an error page.
  /+[ propget]+/
	HRESULT get_IsErrorPage(/+[out, retval]+/ BOOL* isErrorPage);

  /// The ID of the navigation.
  /+[ propget]+/
	HRESULT get_NavigationId(/+[out, retval]+/ UINT64* navigationId);
}

/// The caller implements this interface to receive the ContentLoading event.
const GUID IID_ICoreWebView2ContentLoadingEventHandler = ICoreWebView2ContentLoadingEventHandler.iid;

interface ICoreWebView2ContentLoadingEventHandler : IUnknown
{
    static const GUID iid = { 0x364471e7,0xf2be,0x4910,[ 0xbd,0xba,0xd7,0x20,0x77,0xd5,0x1c,0x4b ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(/+[in]+/ ICoreWebView2 sender, /+[in]+/ ICoreWebView2ContentLoadingEventArgs args);
}

/// Event args for the SourceChanged event.
const GUID IID_ICoreWebView2SourceChangedEventArgs = ICoreWebView2SourceChangedEventArgs.iid;

interface ICoreWebView2SourceChangedEventArgs : IUnknown
{
    static const GUID iid = { 0x31e0e545,0x1dba,0x4266,[ 0x89,0x14,0xf6,0x38,0x48,0xa1,0xf7,0xd7 ] };
    extern(Windows):
  /// True if the page being navigated to is a new document.
  /+[ propget]+/
	HRESULT get_IsNewDocument(/+[out, retval]+/ BOOL* isNewDocument);
}

/// The caller implements this interface to receive the SourceChanged event.
const GUID IID_ICoreWebView2SourceChangedEventHandler = ICoreWebView2SourceChangedEventHandler.iid;

interface ICoreWebView2SourceChangedEventHandler : IUnknown
{
    static const GUID iid = { 0x3c067f9f,0x5388,0x4772,[ 0x8b,0x48,0x79,0xf7,0xef,0x1a,0xb3,0x7c ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(/+[in]+/ ICoreWebView2 sender, /+[in]+/ ICoreWebView2SourceChangedEventArgs args);
}

/// The caller implements this interface to receive the HistoryChanged event.
const GUID IID_ICoreWebView2HistoryChangedEventHandler = ICoreWebView2HistoryChangedEventHandler.iid;

interface ICoreWebView2HistoryChangedEventHandler : IUnknown
{
    static const GUID iid = { 0xc79a420c,0xefd9,0x4058,[ 0x92,0x95,0x3e,0x8b,0x4b,0xca,0xb6,0x45 ] };
    extern(Windows):
  /// There are no event args and the args parameter will be null.
  HRESULT Invoke(/+[in]+/ ICoreWebView2 sender, /+[in]+/ IUnknown args);
}

/// Event args for the ScriptDialogOpening event.
const GUID IID_ICoreWebView2ScriptDialogOpeningEventArgs = ICoreWebView2ScriptDialogOpeningEventArgs.iid;

interface ICoreWebView2ScriptDialogOpeningEventArgs : IUnknown
{
    static const GUID iid = { 0x7390bb70,0xabe0,0x4843,[ 0x95,0x29,0xf1,0x43,0xb3,0x1b,0x03,0xd6 ] };
    extern(Windows):
  /// The URI of the page that requested the dialog box.
  /+[ propget]+/
	HRESULT get_Uri(/+[out, retval]+/ LPWSTR* uri);

  /// The kind of JavaScript dialog box. Accept, confirm, prompt, or
  /// beforeunload.
  /+[ propget]+/
	HRESULT get_Kind(/+[out, retval]+/ COREWEBVIEW2_SCRIPT_DIALOG_KIND* kind);

  /// The message of the dialog box. From JavaScript this is the first parameter
  /// passed to alert, confirm, and prompt and is empty for beforeunload.
  /+[ propget]+/
	HRESULT get_Message(/+[out, retval]+/ LPWSTR* message);

  /// The host may call this to respond with OK to confirm, prompt, and
  /// beforeunload dialogs or not call this method to indicate cancel. From
  /// JavaScript, this means that the confirm and beforeunload function returns
  /// true if Accept is called. And for the prompt function it returns the value
  /// of ResultText if Accept is called and returns false otherwise.
  HRESULT Accept();

  /// The second parameter passed to the JavaScript prompt dialog. This is the
  /// default value to use for the result of the prompt JavaScript function.
  /+[ propget]+/
	HRESULT get_DefaultText(/+[out, retval]+/ LPWSTR* defaultText);

  /// The return value from the JavaScript prompt function if Accept is called.
  /// This is ignored for dialog kinds other than prompt. If Accept is not
  /// called this value is ignored and false is returned from prompt.
  /+[ propget]+/
	HRESULT get_ResultText(/+[out, retval]+/ LPWSTR* resultText);
  /// Set the ResultText property.
  /+[ propput]+/
	HRESULT put_ResultText(in LPCWSTR resultText);

  /// GetDeferral can be called to return an ICoreWebView2Deferral object.
  /// You can use this to complete the event at a later time.
  HRESULT GetDeferral(/+[out, retval]+/ ICoreWebView2Deferral * deferral);
}

/// The caller implements this interface to receive the ScriptDialogOpening
/// event.
const GUID IID_ICoreWebView2ScriptDialogOpeningEventHandler = ICoreWebView2ScriptDialogOpeningEventHandler.iid;

interface ICoreWebView2ScriptDialogOpeningEventHandler : IUnknown
{
    static const GUID iid = { 0xef381bf9,0xafa8,0x4e37,[ 0x91,0xc4,0x8a,0xc4,0x85,0x24,0xbd,0xfb ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2ScriptDialogOpeningEventArgs args);
}

/// Event args for the NavigationCompleted event.
const GUID IID_ICoreWebView2NavigationCompletedEventArgs = ICoreWebView2NavigationCompletedEventArgs.iid;

interface ICoreWebView2NavigationCompletedEventArgs : IUnknown
{
    static const GUID iid = { 0x30d68b7d,0x20d9,0x4752,[ 0xa9,0xca,0xec,0x84,0x48,0xfb,0xb5,0xc1 ] };
    extern(Windows):
  /// True when the navigation is successful. This
  /// is false for a navigation that ended up in an error page (failures due to
  /// no network, DNS lookup failure, HTTP server responds with 4xx), but could
  /// also be false for additional scenarios such as window.stop() called on
  /// navigated page.
  /+[ propget]+/
	HRESULT get_IsSuccess(/+[out, retval]+/ BOOL* isSuccess);

  /// The error code if the navigation failed.
  /+[ propget]+/
	HRESULT get_WebErrorStatus(/+[out, retval]+/ COREWEBVIEW2_WEB_ERROR_STATUS*
      webErrorStatus);

  /// The ID of the navigation.
  /+[ propget]+/
	HRESULT get_NavigationId(/+[out, retval]+/ UINT64* navigationId);
}

/// The caller implements this interface to receive the NavigationCompleted
/// event.
const GUID IID_ICoreWebView2NavigationCompletedEventHandler = ICoreWebView2NavigationCompletedEventHandler.iid;

interface ICoreWebView2NavigationCompletedEventHandler : IUnknown
{
    static const GUID iid = { 0xd33a35bf,0x1c49,0x4f98,[ 0x93,0xab,0x00,0x6e,0x05,0x33,0xfe,0x1c ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2NavigationCompletedEventArgs args);
}

/// Event args for the PermissionRequested event.
const GUID IID_ICoreWebView2PermissionRequestedEventArgs = ICoreWebView2PermissionRequestedEventArgs.iid;

interface ICoreWebView2PermissionRequestedEventArgs : IUnknown
{
    static const GUID iid = { 0x973ae2ef,0xff18,0x4894,[ 0x8f,0xb2,0x3c,0x75,0x8f,0x04,0x68,0x10 ] };
    extern(Windows):
  /// The origin of the web content that requests the permission.
  /+[ propget]+/
	HRESULT get_Uri(/+[out, retval]+/ LPWSTR* uri);

  /// The type of the permission that is requested.
  /+[ propget]+/
	HRESULT get_PermissionKind(/+[out, retval]+/ COREWEBVIEW2_PERMISSION_KIND* permissionKind);

  /// True when the permission request was initiated through a user gesture.
  /// Note that being initiated through a user gesture doesn't mean that user
  /// intended to access the associated resource.
  /+[ propget]+/
	HRESULT get_IsUserInitiated(/+[out, retval]+/ BOOL* isUserInitiated);

  /// The status of a permission request, i.e. whether the request is granted.
  /// Default value is COREWEBVIEW2_PERMISSION_STATE_DEFAULT.
  /+[ propget]+/
	HRESULT get_State(/+[out, retval]+/ COREWEBVIEW2_PERMISSION_STATE* state);
  /// Set the State property.
  /+[ propput]+/
	HRESULT put_State(in COREWEBVIEW2_PERMISSION_STATE state);

  /// GetDeferral can be called to return an ICoreWebView2Deferral object.
  /// Developer can use the deferral object to make the permission decision
  /// at a later time.
  HRESULT GetDeferral(/+[out, retval]+/ ICoreWebView2Deferral * deferral);
}

/// The caller implements this interface to receive the PermissionRequested
/// event.
const GUID IID_ICoreWebView2PermissionRequestedEventHandler = ICoreWebView2PermissionRequestedEventHandler.iid;

interface ICoreWebView2PermissionRequestedEventHandler : IUnknown
{
    static const GUID iid = { 0x15e1c6a3,0xc72a,0x4df3,[ 0x91,0xd7,0xd0,0x97,0xfb,0xec,0x6b,0xfd ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2PermissionRequestedEventArgs args);
}

/// The caller implements this interface to receive the result of the
/// AddScriptToExecuteOnDocumentCreated method.
const GUID IID_ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler = ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler.iid;

interface ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler : IUnknown
{
    static const GUID iid = { 0xb99369f3,0x9b11,0x47b5,[ 0xbc,0x6f,0x8e,0x78,0x95,0xfc,0xea,0x17 ] };
    extern(Windows):
  /// Called to provide the implementer with the completion status and result
  /// of the corresponding asynchronous method call.
  HRESULT Invoke(in HRESULT errorCode, in LPCWSTR id);
}

/// The caller implements this interface to receive the result of the
/// ExecuteScript method.
const GUID IID_ICoreWebView2ExecuteScriptCompletedHandler = ICoreWebView2ExecuteScriptCompletedHandler.iid;

interface ICoreWebView2ExecuteScriptCompletedHandler : IUnknown
{
    static const GUID iid = { 0x49511172,0xcc67,0x4bca,[ 0x99,0x23,0x13,0x71,0x12,0xf4,0xc4,0xcc ] };
    extern(Windows):
  /// Called to provide the implementer with the completion status and result
  /// of the corresponding asynchronous method call.
  HRESULT Invoke(in HRESULT errorCode, in LPCWSTR resultObjectAsJson);
}

/// Event args for the WebResourceRequested event.
const GUID IID_ICoreWebView2WebResourceRequestedEventArgs = ICoreWebView2WebResourceRequestedEventArgs.iid;

interface ICoreWebView2WebResourceRequestedEventArgs : IUnknown
{
    static const GUID iid = { 0x453e667f,0x12c7,0x49d4,[ 0xbe,0x6d,0xdd,0xbe,0x79,0x56,0xf5,0x7a ] };
    extern(Windows):
  /// The Web resource request. The request object may be missing some headers
  /// that are added by network stack later on.
  /+[ propget]+/
	HRESULT get_Request(/+[out, retval]+/ ICoreWebView2WebResourceRequest * request);

  /// A placeholder for the web resource response object. If this object is set, the
  /// web resource request will be completed with this response.
  /+[ propget]+/
	HRESULT get_Response(/+[out, retval]+/ ICoreWebView2WebResourceResponse * response);
  /// Set the Response property. An empty Web resource response object can be
  /// created with CreateWebResourceResponse and then modified to construct the response.
  /+[ propput]+/
	HRESULT put_Response(/+[in]+/ ICoreWebView2WebResourceResponse response);

  /// Obtain an ICoreWebView2Deferral object and put the event into a deferred state.
  /// You can use the ICoreWebView2Deferral object to complete the request at a
  /// later time.
  HRESULT GetDeferral(/+[out, retval]+/ ICoreWebView2Deferral * deferral);

  /// The web resource request context.
  /+[ propget]+/
	HRESULT get_ResourceContext(/+[out, retval]+/ COREWEBVIEW2_WEB_RESOURCE_CONTEXT* context);
}

/// Fires when a URL request (through network, file etc.) is made in the webview
/// for a Web resource matching resource context filter and URL specified in
/// AddWebResourceRequestedFilter.
/// The host can view and modify the request or provide a response in a similar
/// pattern to HTTP, in which case the request immediately completed.
/// This may not contain any request headers that are added by the network
/// stack, such as Authorization headers.
const GUID IID_ICoreWebView2WebResourceRequestedEventHandler = ICoreWebView2WebResourceRequestedEventHandler.iid;

interface ICoreWebView2WebResourceRequestedEventHandler : IUnknown
{
    static const GUID iid = { 0xab00b74c,0x15f1,0x4646,[ 0x80,0xe8,0xe7,0x63,0x41,0xd2,0x5d,0x71 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2WebResourceRequestedEventArgs args);
}

/// The caller implements this method to receive the result of the
/// CapturePreview method. The result is written to the stream provided in
/// the CapturePreview method call.
const GUID IID_ICoreWebView2CapturePreviewCompletedHandler = ICoreWebView2CapturePreviewCompletedHandler.iid;

interface ICoreWebView2CapturePreviewCompletedHandler : IUnknown
{
    static const GUID iid = { 0x697e05e9,0x3d8f,0x45fa,[ 0x96,0xf4,0x8f,0xfe,0x1e,0xde,0xda,0xf5 ] };
    extern(Windows):
  /// Called to provide the implementer with the completion status
  /// of the corresponding asynchronous method call.
  HRESULT Invoke(in HRESULT errorCode);
}

/// The caller implements this method to receive the GotFocus and LostFocus
/// events. There are no event args for this event.
const GUID IID_ICoreWebView2FocusChangedEventHandler = ICoreWebView2FocusChangedEventHandler.iid;

interface ICoreWebView2FocusChangedEventHandler : IUnknown
{
    static const GUID iid = { 0x05ea24bd,0x6452,0x4926,[ 0x90,0x14,0x4b,0x82,0xb4,0x98,0x13,0x5d ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event. There are no event args and the args
  /// parameter will be null.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2Controller sender,
      /+[in]+/ IUnknown args);
}

/// Event args for the MoveFocusRequested event.
const GUID IID_ICoreWebView2MoveFocusRequestedEventArgs = ICoreWebView2MoveFocusRequestedEventArgs.iid;

interface ICoreWebView2MoveFocusRequestedEventArgs : IUnknown
{
    static const GUID iid = { 0x2d6aa13b,0x3839,0x4a15,[ 0x92,0xfc,0xd8,0x8b,0x3c,0x0d,0x9c,0x9d ] };
    extern(Windows):
  /// The reason for WebView to fire the MoveFocus Requested event.
  /+[ propget]+/
	HRESULT get_Reason(/+[out, retval]+/ COREWEBVIEW2_MOVE_FOCUS_REASON* reason);

  /// Indicate whether the event has been handled by the app.
  /// If the app has moved the focus to its desired location, it should set
  /// Handled property to TRUE.
  /// When Handled property is false after the event handler returns, default
  /// action will be taken. The default action is to try to find the next tab
  /// stop child window in the app and try to move focus to that window. If
  /// there is no other such window to move focus to, focus will be cycled
  /// within the WebView's web content.
  /+[ propget]+/
	HRESULT get_Handled(/+[out, retval]+/ BOOL* value);
  /// Set the Handled property.
  /+[ propput]+/
	HRESULT put_Handled(in BOOL value);
}

/// The caller implements this method to receive the MoveFocusRequested event.
const GUID IID_ICoreWebView2MoveFocusRequestedEventHandler = ICoreWebView2MoveFocusRequestedEventHandler.iid;

interface ICoreWebView2MoveFocusRequestedEventHandler : IUnknown
{
    static const GUID iid = { 0x69035451,0x6dc7,0x4cb8,[ 0x9b,0xce,0xb2,0xbd,0x70,0xad,0x28,0x9f ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2Controller sender,
      /+[in]+/ ICoreWebView2MoveFocusRequestedEventArgs args);
}

/// Event args for the WebMessageReceived event.
const GUID IID_ICoreWebView2WebMessageReceivedEventArgs = ICoreWebView2WebMessageReceivedEventArgs.iid;

interface ICoreWebView2WebMessageReceivedEventArgs : IUnknown
{
    static const GUID iid = { 0x0f99a40c,0xe962,0x4207,[ 0x9e,0x92,0xe3,0xd5,0x42,0xef,0xf8,0x49 ] };
    extern(Windows):
  /// The URI of the document that sent this web message.
  /+[ propget]+/
	HRESULT get_Source(/+[out, retval]+/ LPWSTR* source);

  /// The message posted from the WebView content to the host converted to a
  /// JSON string. Use this to communicate via JavaScript objects.
  ///
  /// For example the following postMessage calls result in the
  /// following WebMessageAsJson values:
  ///
  /// ```
  ///    postMessage({'a': 'b'})      L"{\"a\": \"b\"}"
  ///    postMessage(1.2)             L"1.2"
  ///    postMessage('example')       L"\"example\""
  /// ```
  /+[ propget]+/
	HRESULT get_WebMessageAsJson(/+[out, retval]+/ LPWSTR* webMessageAsJson);

  /// If the message posted from the WebView content to the host is a
  /// string type, this method will return the value of that string. If the
  /// message posted is some other kind of JavaScript type this method will fail
  /// with E_INVALIDARG. Use this to communicate via simple strings.
  ///
  /// For example the following postMessage calls result in the
  /// following WebMessageAsString values:
  ///
  /// ```
  ///    postMessage({'a': 'b'})      E_INVALIDARG
  ///    postMessage(1.2)             E_INVALIDARG
  ///    postMessage('example')       L"example"
  /// ```
  HRESULT TryGetWebMessageAsString(/+[out, retval]+/ LPWSTR* webMessageAsString);
}

/// The caller implements this interface to receive the WebMessageReceived
/// event.
const GUID IID_ICoreWebView2WebMessageReceivedEventHandler = ICoreWebView2WebMessageReceivedEventHandler.iid;

interface ICoreWebView2WebMessageReceivedEventHandler : IUnknown
{
    static const GUID iid = { 0x57213f19,0x00e6,0x49fa,[ 0x8e,0x07,0x89,0x8e,0xa0,0x1e,0xcb,0xd2 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2WebMessageReceivedEventArgs args);
}

/// Event args for the DevToolsProtocolEventReceived event.
const GUID IID_ICoreWebView2DevToolsProtocolEventReceivedEventArgs = ICoreWebView2DevToolsProtocolEventReceivedEventArgs.iid;

interface ICoreWebView2DevToolsProtocolEventReceivedEventArgs : IUnknown
{
    static const GUID iid = { 0x653c2959,0xbb3a,0x4377,[ 0x86,0x32,0xb5,0x8a,0xda,0x4e,0x66,0xc4 ] };
    extern(Windows):
  /// The parameter object of the corresponding DevToolsProtocol event
  /// represented as a JSON string.
  /+[ propget]+/
	HRESULT get_ParameterObjectAsJson(/+[out, retval]+/ LPWSTR*
                                    parameterObjectAsJson);
}

/// The caller implements this interface to receive
/// DevToolsProtocolEventReceived events from the WebView.
const GUID IID_ICoreWebView2DevToolsProtocolEventReceivedEventHandler = ICoreWebView2DevToolsProtocolEventReceivedEventHandler.iid;

interface ICoreWebView2DevToolsProtocolEventReceivedEventHandler : IUnknown
{
    static const GUID iid = { 0xe2fda4be,0x5456,0x406c,[ 0xa2,0x61,0x3d,0x45,0x21,0x38,0x36,0x2c ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2DevToolsProtocolEventReceivedEventArgs args);
}

/// The caller implements this interface to receive CallDevToolsProtocolMethod
/// completion results.
const GUID IID_ICoreWebView2CallDevToolsProtocolMethodCompletedHandler = ICoreWebView2CallDevToolsProtocolMethodCompletedHandler.iid;

interface ICoreWebView2CallDevToolsProtocolMethodCompletedHandler : IUnknown
{
    static const GUID iid = { 0x5c4889f0,0x5ef6,0x4c5a,[ 0x95,0x2c,0xd8,0xf1,0xb9,0x2d,0x05,0x74 ] };
    extern(Windows):
  /// Called to provide the implementer with the completion status and result
  /// of the corresponding asynchronous method call.
  HRESULT Invoke(in HRESULT errorCode, in LPCWSTR returnObjectAsJson);
}

/// The caller implements this interface to receive the CoreWebView2Controller created
/// via CreateCoreWebView2Controller.
const GUID IID_ICoreWebView2CreateCoreWebView2ControllerCompletedHandler = ICoreWebView2CreateCoreWebView2ControllerCompletedHandler.iid;

interface ICoreWebView2CreateCoreWebView2ControllerCompletedHandler : IUnknown
{
    static const GUID iid = { 0x6c4819f3,0xc9b7,0x4260,[ 0x81,0x27,0xc9,0xf5,0xbd,0xe7,0xf6,0x8c ] };
    extern(Windows):
  /// Called to provide the implementer with the completion status and result
  /// of the corresponding asynchronous method call.
  HRESULT Invoke(HRESULT errorCode, ICoreWebView2Controller createdController);
}

/// Event args for the NewWindowRequested event. The event is fired when content
/// inside webview requested to a open a new window (through window.open() and so on.)
const GUID IID_ICoreWebView2NewWindowRequestedEventArgs = ICoreWebView2NewWindowRequestedEventArgs.iid;

interface ICoreWebView2NewWindowRequestedEventArgs : IUnknown
{
    static const GUID iid = { 0x34acb11c,0xfc37,0x4418,[ 0x91,0x32,0xf9,0xc2,0x1d,0x1e,0xaf,0xb9 ] };
    extern(Windows):
  /// The target uri of the NewWindowRequest.
  /+[ propget]+/
	HRESULT get_Uri(/+[out, retval]+/ LPWSTR* uri);

  /// Sets a WebView as a result of the NewWindowRequest. The target
  /// WebView should not be navigated. If the NewWindow is set, its top level
  /// window will return as the opened WindowProxy.
  /+[ propput]+/
	HRESULT put_NewWindow(/+[in]+/ ICoreWebView2 newWindow);
  /// Gets the new window.
  /+[ propget]+/
	HRESULT get_NewWindow(/+[out, retval]+/ ICoreWebView2 * newWindow);

  /// Sets whether the NewWindowRequestedEvent is handled by host. If this is false
  /// and no NewWindow is set, the WebView will open a popup
  /// window and it will be returned as opened WindowProxy.
  /// If set to true and no NewWindow is set for a window.open call, the opened
  /// WindowProxy will be for an dummy window object and no window will load.
  /// Default is false.
  /+[ propput]+/
	HRESULT put_Handled(in BOOL handled);
  /// Gets whether the NewWindowRequestedEvent is handled by host.
  /+[ propget]+/
	HRESULT get_Handled(/+[out, retval]+/ BOOL* handled);

  /// IsUserInitiated is true when the new window request was initiated through
  /// a user gesture such as clicking an anchor tag with target. The Edge
  /// popup blocker is disabled for WebView so the app can use this flag to
  /// block non-user initiated popups.
  /+[ propget]+/
	HRESULT get_IsUserInitiated(/+[out, retval]+/ BOOL* isUserInitiated);

  /// Obtain an ICoreWebView2Deferral object and put the event into a deferred state.
  /// You can use the ICoreWebView2Deferral object to complete the window open
  /// request at a later time.
  /// While this event is deferred the opener window will be returned a WindowProxy
  /// to an unnavigated window, which will navigate when the deferral is complete.
  HRESULT GetDeferral(/+[out, retval]+/ ICoreWebView2Deferral * deferral);

  /// Window features specified by the window.open call.
  /// These features can be considered for positioning and sizing of
  /// new webview windows.
  /+[ propget]+/
	HRESULT get_WindowFeatures(/+[out, retval]+/ ICoreWebView2WindowFeatures * value);
}

/// Window features for a WebView popup window. These fields match the
/// 'windowFeatures' passed to window.open as specified in
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/open#Window_features
/// There is no requirement for you to respect these values. If your app doesn't
/// have corresponding UI features, for example no toolbar, or if all webviews
/// are opened in tabs and so cannot have distinct size or positions, then your
/// app cannot respect these values. You may want to respect values but perhaps
/// only some can apply to your app's UI. Accordingly, it is fine to respect
/// all, some, or none of these properties as appropriate based on your app.
/// For all numeric properties, if the value when passed to window.open is
/// outside the range of an unsigned 32bit int, the value will be mod of the max
/// of unsigned 32bit integer. If the value cannot be parsed as an integer it
/// will be considered 0. If the value is a floating point value, it will be
/// rounded down to an integer.
const GUID IID_ICoreWebView2WindowFeatures = ICoreWebView2WindowFeatures.iid;

interface ICoreWebView2WindowFeatures : IUnknown
{
    static const GUID iid = { 0x5eaf559f,0xb46e,0x4397,[ 0x88,0x60,0xe4,0x22,0xf2,0x87,0xff,0x1e ] };
    extern(Windows):
  /// True if the Left and Top properties were specified. False if at least one
  /// was not specified.
  /+[ propget]+/
	HRESULT get_HasPosition(/+[out, retval]+/ BOOL* value);
  /// True if the Width and Height properties were specified. False if at least
  /// one was not specified.
  /+[ propget]+/
	HRESULT get_HasSize(/+[out, retval]+/ BOOL* value);
  /// The left position of the window. This will fail if HasPosition is false.
  /+[ propget]+/
	HRESULT get_Left(/+[out, retval]+/ UINT32* value);
  /// The top position of the window. This will fail if HasPosition is false.
  /+[ propget]+/
	HRESULT get_Top(/+[out, retval]+/ UINT32* value);
  /// The height of the window. This will fail if HasSize is false.
  /+[ propget]+/
	HRESULT get_Height(/+[out, retval]+/ UINT32* value);
  /// The width of the window. This will fail if HasSize is false.
  /+[ propget]+/
	HRESULT get_Width(/+[out, retval]+/ UINT32* value);
  /// Whether or not to display the menu bar.
  /+[ propget]+/
	HRESULT get_ShouldDisplayMenuBar(/+[out, retval]+/ BOOL* value);
  /// Whether or not to display a status bar.
  /+[ propget]+/
	HRESULT get_ShouldDisplayStatus(/+[out, retval]+/ BOOL* value);
  /// Whether or not to display a toolbar.
  /+[ propget]+/
	HRESULT get_ShouldDisplayToolbar(/+[out, retval]+/ BOOL* value);
  /// Whether or not to display scroll bars.
  /+[ propget]+/
	HRESULT get_ShouldDisplayScrollBars(/+[out, retval]+/ BOOL* value);
}

/// The caller implements this interface to receive NewWindowRequested
/// events.
const GUID IID_ICoreWebView2NewWindowRequestedEventHandler = ICoreWebView2NewWindowRequestedEventHandler.iid;

interface ICoreWebView2NewWindowRequestedEventHandler : IUnknown
{
    static const GUID iid = { 0xd4c185fe,0xc81c,0x4989,[ 0x97,0xaf,0x2d,0x3f,0xa7,0xab,0x56,0x51 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2 sender,
      /+[in]+/ ICoreWebView2NewWindowRequestedEventArgs args);
}

/// The caller implements this interface to receive DocumentTitleChanged
/// events. Use the DocumentTitle property to get the modified
/// title.
const GUID IID_ICoreWebView2DocumentTitleChangedEventHandler = ICoreWebView2DocumentTitleChangedEventHandler.iid;

interface ICoreWebView2DocumentTitleChangedEventHandler : IUnknown
{
    static const GUID iid = { 0xf5f2b923,0x953e,0x4042,[ 0x9f,0x95,0xf3,0xa1,0x18,0xe1,0xaf,0xd4 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event. There are no event args and the args
  /// parameter will be null.
  HRESULT Invoke(/+[in]+/ ICoreWebView2 sender, /+[in]+/ IUnknown args);
}

/// Event args for the AcceleratorKeyPressed event.
const GUID IID_ICoreWebView2AcceleratorKeyPressedEventArgs = ICoreWebView2AcceleratorKeyPressedEventArgs.iid;

interface ICoreWebView2AcceleratorKeyPressedEventArgs : IUnknown
{
    static const GUID iid = { 0x9f760f8a,0xfb79,0x42be,[ 0x99,0x90,0x7b,0x56,0x90,0x0f,0xa9,0xc7 ] };
    extern(Windows):
  /// The key event type that caused the event to be fired.
  /+[ propget]+/
	HRESULT get_KeyEventKind(/+[out, retval]+/ COREWEBVIEW2_KEY_EVENT_KIND* keyEventKind);
  /// The Win32 virtual key code of the key that was pressed or released.
  /// This will be one of the Win32 virtual key constants such as VK_RETURN or
  /// an (uppercase) ASCII value such as 'A'. You can check whether Ctrl or Alt
  /// are pressed by calling GetKeyState(VK_CONTROL) or GetKeyState(VK_MENU).
  /+[ propget]+/
	HRESULT get_VirtualKey(/+[out, retval]+/ UINT* virtualKey);
  /// The LPARAM value that accompanied the window message. See the
  /// documentation for the WM_KEYDOWN and WM_KEYUP messages.
  /+[ propget]+/
	HRESULT get_KeyEventLParam(/+[out, retval]+/ INT* lParam);
  /// A structure representing the information passed in the LPARAM of the
  /// window message.
  /+[ propget]+/
	HRESULT get_PhysicalKeyStatus(
      /+[out, retval]+/ COREWEBVIEW2_PHYSICAL_KEY_STATUS* physicalKeyStatus);
  /// During AcceleratorKeyPressedEvent handler invocation the WebView is blocked
  /// waiting for the decision of if the accelerator will be handled by the host
  /// or not. If the Handled property is set to TRUE then this will
  /// prevent the WebView from performing the default action for this
  /// accelerator key. Otherwise the WebView will perform the default action for
  /// the accelerator key.
  /+[ propget]+/
	HRESULT get_Handled(/+[out, retval]+/ BOOL* handled);
  /// Sets the Handled property.
  /+[ propput]+/
	HRESULT put_Handled(in BOOL handled);
}

/// The caller implements this interface to receive the AcceleratorKeyPressed
/// event.
const GUID IID_ICoreWebView2AcceleratorKeyPressedEventHandler = ICoreWebView2AcceleratorKeyPressedEventHandler.iid;

interface ICoreWebView2AcceleratorKeyPressedEventHandler : IUnknown
{
    static const GUID iid = { 0xb29c7e28,0xfa79,0x41a8,[ 0x8e,0x44,0x65,0x81,0x1c,0x76,0xdc,0xb2 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(
      /+[in]+/ ICoreWebView2Controller sender,
      /+[in]+/ ICoreWebView2AcceleratorKeyPressedEventArgs args);
}

/// The caller implements this interface to receive NewBrowserVersionAvailable events.
const GUID IID_ICoreWebView2NewBrowserVersionAvailableEventHandler = ICoreWebView2NewBrowserVersionAvailableEventHandler.iid;

interface ICoreWebView2NewBrowserVersionAvailableEventHandler : IUnknown
{
    static const GUID iid = { 0xf9a2976e,0xd34e,0x44fc,[ 0xad,0xee,0x81,0xb6,0xb5,0x7c,0xa9,0x14 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event.
  HRESULT Invoke(/+[in]+/ ICoreWebView2Environment webviewEnvironment,
                 /+[in]+/ IUnknown args);
}

/// The caller implements this method to receive the
/// ContainsFullScreenElementChanged events. There are no event args for this
/// event.
const GUID IID_ICoreWebView2ContainsFullScreenElementChangedEventHandler = ICoreWebView2ContainsFullScreenElementChangedEventHandler.iid;

interface ICoreWebView2ContainsFullScreenElementChangedEventHandler : IUnknown
{
    static const GUID iid = { 0xe45d98b1,0xafef,0x45be,[ 0x8b,0xaf,0x6c,0x77,0x28,0x86,0x7f,0x73 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event. There are no event args and the args
  /// parameter will be null.
  HRESULT Invoke(/+[in]+/ ICoreWebView2 sender, /+[in]+/ IUnknown args);
}

/// The caller implements this interface to receive NewWindowRequested
/// events.
const GUID IID_ICoreWebView2WindowCloseRequestedEventHandler = ICoreWebView2WindowCloseRequestedEventHandler.iid;

interface ICoreWebView2WindowCloseRequestedEventHandler : IUnknown
{
    static const GUID iid = { 0x5c19e9e0,0x092f,0x486b,[ 0xaf,0xfa,0xca,0x82,0x31,0x91,0x30,0x39 ] };
    extern(Windows):
  /// Called to provide the implementer with the event args for the
  /// corresponding event. There are no event args and the args
  /// parameter will be null.
  HRESULT Invoke(/+[in]+/ ICoreWebView2 sender, /+[in]+/ IUnknown args);
}

/// This represents the WebView2 Environment. WebViews created from an
/// environment run on the browser process specified with environment parameters
/// and objects created from an environment should be used in the same environment.
/// Using it in different environments are not guaranteed to be compatible and may fail.
const GUID IID_ICoreWebView2Environment = ICoreWebView2Environment.iid;

interface ICoreWebView2Environment : IUnknown
{
    static const GUID iid = { 0xb96d755e,0x0319,0x4e92,[ 0xa2,0x96,0x23,0x43,0x6f,0x46,0xa1,0xfc ] };
    extern(Windows):
  /// Asynchronously create a new WebView.
  ///
  /// parentWindow is the HWND in which the WebView should be displayed and
  /// from which receive input. The WebView will add a child window to the
  /// provided window during WebView creation. Z-order and other things impacted
  /// by sibling window order will be affected accordingly.
  ///
  /// It is recommended that the application set Application User Model ID for
  /// the process or the application window. If none is set, during WebView
  /// creation a generated Application User Model ID is set to root window of
  /// parentWindow.
  /// \snippet AppWindow.cpp CreateCoreWebView2Controller
  ///
  /// It is recommended that the application handles restart manager messages
  /// so that it can be restarted gracefully in the case when the app is using
  /// Edge for WebView from a certain installation and that installation is being
  /// uninstalled. For example, if a user installs Edge from Dev channel and
  /// opts to use Edge from that channel for testing the app, and then uninstalls
  /// Edge from that channel without closing the app, the app will be restarted
  /// to allow uninstallation of the dev channel to succeed.
  /// \snippet AppWindow.cpp RestartManager
  ///
  /// When the application retries CreateCoreWebView2Controller upon failure, it is
  /// recommended that the application restarts from creating a new WebView2
  /// Environment. If an Edge update happens, the version associated with a WebView2
  /// Environment could have been removed and causing the object to no longer work.
  /// Creating a new WebView2 Environment will work as it uses the latest version.
  ///
  /// WebView creation will fail if there is already a running instance using the same
  /// user data folder, and the Environment objects have different EnvironmentOptions.
  /// For example, if there is already a WebView created with one language, trying to
  /// create a WebView with a different language using the same user data folder will
  /// fail.
  HRESULT CreateCoreWebView2Controller(
    HWND parentWindow,
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler handler);

  /// Create a new web resource response object. The headers is the
  /// raw response header string delimited by newline. It's also possible to
  /// create this object with null headers string and then use the
  /// ICoreWebView2HttpResponseHeaders to construct the headers line by line.
  /// For information on other parameters see ICoreWebView2WebResourceResponse.
  ///
  /// \snippet SettingsComponent.cpp WebResourceRequested
  HRESULT CreateWebResourceResponse(
    in IStream* content,
    in int statusCode,
    in LPCWSTR reasonPhrase,
    in LPCWSTR headers,
    /+[out, retval]+/ ICoreWebView2WebResourceResponse * response);

  /// The browser version info of the current ICoreWebView2Environment,
  /// including channel name if it is not the stable channel.
  /// This matches the format of the
  /// GetAvailableCoreWebView2BrowserVersionString API.
  /// Channel names are 'beta', 'dev', and 'canary'.
  ///
  /// \snippet AppWindow.cpp GetBrowserVersionString
  /+[ propget]+/
	HRESULT get_BrowserVersionString(/+[out, retval]+/ LPWSTR* versionInfo);

  /// Add an event handler for the NewBrowserVersionAvailable event.
  /// NewBrowserVersionAvailable fires when a newer version of the
  /// Edge browser is installed and available for use via WebView2.
  /// To use the newer version of the browser you must create a new
  /// environment and WebView.
  /// This event will only be fired for new version from the same Edge channel
  /// that the code is running from. When not running with installed Edge,
  /// no event will be fired.
  ///
  /// Because a user data folder can only be used by one browser process at
  /// a time, if you want to use the same user data folder in the WebViews
  /// using the new version of the browser,
  /// you must close the environment and WebViews that are using the older
  /// version of the browser first. Or simply prompt the user to restart the
  /// app.
  ///
  /// \snippet AppWindow.cpp NewBrowserVersionAvailable
  ///
  HRESULT add_NewBrowserVersionAvailable(
      /+[in]+/ ICoreWebView2NewBrowserVersionAvailableEventHandler eventHandler,
      /+[out]+/ EventRegistrationToken* token);

  /// Remove an event handler previously added with add_NewBrowserVersionAvailable.
  HRESULT remove_NewBrowserVersionAvailable(
      in EventRegistrationToken token);
}

/// Options used to create WebView2 Environment.
///
/// \snippet AppWindow.cpp CreateCoreWebView2EnvironmentWithOptions
///
const GUID IID_ICoreWebView2EnvironmentOptions = ICoreWebView2EnvironmentOptions.iid;

interface ICoreWebView2EnvironmentOptions : IUnknown
{
    static const GUID iid = { 0x2fde08a8,0x1e9a,0x4766,[ 0x8c,0x05,0x95,0xa9,0xce,0xb9,0xd1,0xc5 ] };
    extern(Windows):
  /// AdditionalBrowserArguments can be specified to change the behavior of the
  /// WebView. These will be passed to the browser process as part of
  /// the command line. See
  /// [Run Chromium with Flags](https://aka.ms/RunChromiumWithFlags)
  /// for more information about command line switches to browser
  /// process. If the app is launched with a command line switch
  /// `--edge-webview-switches=xxx` the value of that switch (xxx in
  /// the above example) will also be appended to the browser
  /// process command line. Certain switches like `--user-data-dir` are
  /// internal and important to WebView. Those switches will be
  /// ignored even if specified. If the same switches are specified
  /// multiple times, the last one wins. There is no attempt to
  /// merge the different values of the same switch, except for disabled
  /// and enabled features.  The features specified by `--enable-features`
  /// and `--disable-features` will be merged with simple logic: the features
  /// will be the union of the specified features and built-in features, and if
  /// a feature is disabled, it will be removed from the enabled features list.
  /// App process's command line `--edge-webview-switches` value are processed
  /// after the additionalBrowserArguments parameter is processed. Certain
  /// features are disabled internally and can't be enabled.
  /// If parsing failed for the specified switches, they will be
  /// ignored. Default is to run browser process with no extra flags.
  /+[ propget]+/
	HRESULT get_AdditionalBrowserArguments(/+[out, retval]+/ LPWSTR* value);
  /// Set the AdditionalBrowserArguments property.
  /+[ propput]+/
	HRESULT put_AdditionalBrowserArguments(in LPCWSTR value);

  /// The default language that WebView will run with. It applies to browser UIs
  /// like context menu and dialogs. It also applies to the accept-languages
  /// HTTP header that WebView sends to web sites.
  /// It is in the format of `language[-country]` where `language` is the 2 letter
  /// code from ISO 639 and `country` is the 2 letter code from ISO 3166.
  /+[ propget]+/
	HRESULT get_Language(/+[out, retval]+/ LPWSTR* value);
  /// Set the Language property.
  /+[ propput]+/
	HRESULT put_Language(in LPCWSTR value);

  /// The version of the Edge WebView2 Runtime binaries required to be
  /// compatible with the calling application. This defaults to the Edge
  /// WebView2 Runtime version
  /// that corresponds with the version of the SDK the application is using.
  /// The format of this value is the same as the format of the
  /// BrowserVersionString property and other BrowserVersion values.
  /// Only the version part of the BrowserVersion value is respected. The
  /// channel suffix, if it exists, is ignored.
  /// The version of the Edge WebView2 Runtime binaries actually used may be
  /// different from the specified TargetCompatibleBrowserVersion. They are only
  /// guaranteed to be compatible. You can check the actual version on the
  /// BrowserVersionString property on the ICoreWebView2Environment.
  /+[ propget]+/
	HRESULT get_TargetCompatibleBrowserVersion(/+[out, retval]+/ LPWSTR* value);
  /// Set the TargetCompatibleBrowserVersion property.
  /+[ propput]+/
	HRESULT put_TargetCompatibleBrowserVersion(in LPCWSTR value);

  /// The AllowSingleSignOnUsingOSPrimaryAccount property is used to enable
  /// single sign on with Azure Active Directory (AAD) resources inside WebView
  /// using the logged in Windows account and single sign on with web sites using
  /// Microsoft account associated with the login in Windows account.
  /// Default is disabled.
  /// Universal Windows Platform apps must also declare enterpriseCloudSSO
  /// [restricted capability](https://docs.microsoft.com/windows/uwp/packaging/app-capability-declarations#restricted-capabilities)
  /// for the single sign on to work.
  /+[ propget]+/
	HRESULT get_AllowSingleSignOnUsingOSPrimaryAccount(/+[out, retval]+/ BOOL* allow);
  /// Set the AllowSingleSignOnUsingOSPrimaryAccount property.
  /+[ propput]+/
	HRESULT put_AllowSingleSignOnUsingOSPrimaryAccount(in BOOL allow);
}

/// The caller implements this interface to receive the WebView2Environment created
/// via CreateCoreWebView2Environment.
const GUID IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler = ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler.iid;

interface ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler : IUnknown
{
    static const GUID iid = { 0x4e8a3389,0xc9d8,0x4bd2,[ 0xb6,0xb5,0x12,0x4f,0xee,0x6c,0xc1,0x4d ] };
    extern(Windows):
  /// Called to provide the implementer with the completion status and result
  /// of the corresponding asynchronous method call.
  HRESULT Invoke(HRESULT errorCode, ICoreWebView2Environment createdEnvironment);
}

/// A Receiver is created for a particular DevTools Protocol event and allows
/// you to subscribe and unsubscribe from that event.
/// Obtained from the WebView object via GetDevToolsProtocolEventReceiver.
const GUID IID_ICoreWebView2DevToolsProtocolEventReceiver = ICoreWebView2DevToolsProtocolEventReceiver.iid;

interface ICoreWebView2DevToolsProtocolEventReceiver : IUnknown
{
    static const GUID iid = { 0xb32ca51a,0x8371,0x45e9,[ 0x93,0x17,0xaf,0x02,0x1d,0x08,0x03,0x67 ] };
    extern(Windows):
  /// Subscribe to a DevToolsProtocol event.
  /// The handler's Invoke method will be called whenever the corresponding
  /// DevToolsProtocol event fires. Invoke will be called with
  /// an event args object containing the DevTools Protocol event's parameter
  /// object as a JSON string.
  ///
  /// \snippet ScriptComponent.cpp DevToolsProtocolEventReceived
  HRESULT add_DevToolsProtocolEventReceived(
      /+[in]+/ ICoreWebView2DevToolsProtocolEventReceivedEventHandler handler,
      /+[out]+/ EventRegistrationToken* token);
  /// Remove an event handler previously added with
  /// add_DevToolsProtocolEventReceived.
  HRESULT remove_DevToolsProtocolEventReceived(
      in EventRegistrationToken token);
}

/// DLL export to create a WebView2 environment with a custom version of Edge,
/// user data directory and/or additional options.
///
/// The WebView2 environment and all other WebView2 objects are single threaded
/// and have dependencies on Windows components that require COM to be
/// initialized for a single-threaded apartment. The application is expected to
/// call CoInitializeEx before calling CreateCoreWebView2EnvironmentWithOptions.
///
/// ```
/// CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
/// ```
///
/// If CoInitializeEx was not called or has been previously called with
/// COINIT_MULTITHREADED, CreateCoreWebView2EnvironmentWithOptions will fail
/// with one of the following errors.
///
/// ```
/// CO_E_NOTINITIALIZED (if CoInitializeEx was not called)
/// RPC_E_CHANGED_MODE  (if CoInitializeEx was previously called with
///                      COINIT_MULTITHREADED)
/// ```
///
/// Use `browserExecutableFolder` to specify whether WebView2 controls use a
/// fixed or installed version of the WebView2 Runtime that exists on a client
/// machine. To use a fixed version of the WebView2 Runtime, pass the relative
/// path of the folder that contains the fixed version of the WebView2 Runtime
/// to `browserExecutableFolder`. To create WebView2 controls that use the
/// installed version of the WebView2 Runtime that exists on client machines,
/// pass a null or empty string to `browserExecutableFolder`. In this scenario,
/// the API tries to find a compatible version of the WebView2 Runtime that is
/// installed on the client machine (first at the machine level, and then per
/// user) using the selected channel preference. The path of fixed version of
/// the WebView2 Runtime should not contain `\Edge\Application\`. When such a
/// path is used, the API will fail with ERROR_NOT_SUPPORTED.
///
/// The default channel search order is the WebView2 Runtime, Beta, Dev, and
/// Canary.
/// When there is an override WEBVIEW2_RELEASE_CHANNEL_PREFERENCE environment
/// variable or applicable releaseChannelPreference registry value
/// with the value of 1, the channel search order is reversed.
///
/// userDataFolder can be
/// specified to change the default user data folder location for
/// WebView2. The path can be an absolute file path or a relative file path
/// that is interpreted as relative to the current process's executable.
/// Otherwise, for UWP apps, the default user data folder will be
/// the app data folder for the package; for non-UWP apps,
/// the default user data folder `{Executable File Name}.WebView2`
/// will be created in the same directory next to the app executable.
/// WebView2 creation can fail if the executable is running in a directory
/// that the process doesn't have permission to create a new folder in.
/// The app is responsible to clean up its user data folder
/// when it is done.
///
/// Note that as a browser process might be shared among WebViews,
/// WebView creation will fail with HRESULT_FROM_WIN32(ERROR_INVALID_STATE) if
/// the specified options does not match the options of the WebViews that are
/// currently running in the shared browser process.
///
/// environmentCreatedHandler is the handler result to the async operation
/// which will contain the WebView2Environment that got created.
///
/// The browserExecutableFolder, userDataFolder and additionalBrowserArguments
/// of the environmentOptions may be overridden by
/// values either specified in environment variables or in the registry.
///
/// When creating a WebView2Environment the following environment variables
/// are checked:
///
/// ```
/// WEBVIEW2_BROWSER_EXECUTABLE_FOLDER
/// WEBVIEW2_USER_DATA_FOLDER
/// WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
/// WEBVIEW2_RELEASE_CHANNEL_PREFERENCE
/// ```
///
/// If an override environment variable is found then we use the
/// browserExecutableFolder and userDataFolder values as replacements for the
/// corresponding values in CreateCoreWebView2EnvironmentWithOptions parameters.
/// If additionalBrowserArguments specified in environment variable or in the
/// registry, it will be appended to the correspinding values in
/// CreateCoreWebView2EnvironmentWithOptions parameters.
///
/// While not strictly overrides, there exists additional environment variables
/// that can be set:
///
/// ```
/// WEBVIEW2_WAIT_FOR_SCRIPT_DEBUGGER
/// ```
///
/// When found with a non-empty value, this indicates that the WebView is being
/// launched under a script debugger. In this case, the WebView will issue a
/// `Page.waitForDebugger` CDP command that will cause script execution inside the
/// WebView to pause on launch, until a debugger issues a corresponding
/// `Runtime.runIfWaitingForDebugger` CDP command to resume execution.
/// Note: There is no registry key equivalent of this environment variable.
///
/// ```
/// WEBVIEW2_PIPE_FOR_SCRIPT_DEBUGGER
/// ```
///
/// When found with a non-empty value, this indicates that the WebView is being
/// launched under a script debugger that also supports host applications that
/// use multiple WebViews. The value is used as the identifier for a named pipe
/// that will be opened and written to when a new WebView is created by the host
/// application. The payload will match that of the remote-debugging-port JSON
/// target and can be used by the external debugger to attach to a specific
/// WebView instance.
/// The format of the pipe created by the debugger should be:
/// `\\.\pipe\WebView2\Debugger\{app_name}\{pipe_name}`
/// where:
///
/// - `{app_name}` is the host application exe filename, e.g. WebView2Example.exe
/// - `{pipe_name}` is the value set for WEBVIEW2_PIPE_FOR_SCRIPT_DEBUGGER.
///
/// To enable debugging of the targets identified by the JSON you will also need
/// to set the WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS environment variable to
/// send `--remote-debugging-port={port_num}`
/// where:
///
/// - `{port_num}` is the port on which the CDP server will bind.
///
/// Be aware that setting both the WEBVIEW2_PIPE_FOR_SCRIPT_DEBUGGER and
/// WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS environment variables will cause the
/// WebViews hosted in your application and their contents to be exposed to
/// 3rd party applications such as debuggers.
///
/// Note: There is no registry key equivalent of this environment variable.
///
/// If none of those environment variables exist, then the registry is examined next.
/// The following registry values are checked:
///
/// ```
/// [{Root}]\Software\Policies\Microsoft\Edge\WebView2\BrowserExecutableFolder
/// "{AppId}"=""
///
/// [{Root}]\Software\Policies\Microsoft\Edge\WebView2\ReleaseChannelPreference
/// "{AppId}"=""
///
/// [{Root}]\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments
/// "{AppId}"=""
///
/// [{Root}]\Software\Policies\Microsoft\Edge\WebView2\UserDataFolder
/// "{AppId}"=""
/// ```
///
/// browserExecutableFolder and releaseChannelPreference can be configured using
/// group policy under Administrative Templates > Microsoft Edge WebView2.
/// The old registry location will be deprecated soon:
///
/// ```
/// [{Root}\Software\Policies\Microsoft\EmbeddedBrowserWebView\LoaderOverride\{AppId}]
/// "ReleaseChannelPreference"=dword:00000000
/// "BrowserExecutableFolder"=""
/// "UserDataFolder"=""
/// "AdditionalBrowserArguments"=""
/// ```
///
/// In the unlikely scenario where some instances of WebView are open during
/// a browser update we could end up blocking the deletion of old Edge browsers.
/// To avoid running out of disk space a new WebView creation will fail
/// with the next error if it detects that there are many old versions present.
///
/// ```
/// ERROR_DISK_FULL
/// ```
///
/// The default maximum number of Edge versions allowed is 20.
///
/// The maximum number of old Edge versions allowed can be overwritten with the value
/// of the following environment variable.
///
/// ```
/// WEBVIEW2_MAX_INSTANCES
/// ```
///
/// If the Webview depends on an installed Edge and it is uninstalled
/// any subsequent creation will fail with the next error
///
/// ```
/// ERROR_PRODUCT_UNINSTALLED
/// ```
///
/// First we check with Root as HKLM and then HKCU.
/// AppId is first set to the Application User Model ID of the caller's process,
/// then if there's no corresponding registry key the AppId is set to the
/// executable name of the caller's process, or if that isn't a registry key
/// then '*'. If an override registry key is found, then we use the
/// browserExecutableFolder and userDataFolder registry values as replacements
/// and append additionalBrowserArguments registry values for the corresponding
/// values in CreateCoreWebView2EnvironmentWithOptions parameters.
extern(Windows) HRESULT CreateCoreWebView2EnvironmentWithOptions(PCWSTR browserExecutableFolder, PCWSTR userDataFolder, ICoreWebView2EnvironmentOptions environmentOptions, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler environmentCreatedHandler);

/// Creates an evergreen WebView2 Environment using the installed Edge version.
/// This is equivalent to calling CreateCoreWebView2EnvironmentWithOptions with
/// nullptr for browserExecutableFolder, userDataFolder,
/// additionalBrowserArguments. See CreateCoreWebView2EnvironmentWithOptions for
/// more details.
extern(Windows) HRESULT CreateCoreWebView2Environment(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler environmentCreatedHandler);

/// Get the browser version info including channel name if it is not the stable channel
/// or the Embedded Edge.
/// Channel names are beta, dev, and canary.
/// If an override exists for the browserExecutableFolder or the channel preference,
/// the override will be used.
/// If there isn't an override, then the parameter passed to
/// GetAvailableCoreWebView2BrowserVersionString is used.
extern(Windows) HRESULT GetAvailableCoreWebView2BrowserVersionString(PCWSTR browserExecutableFolder, LPWSTR* versionInfo);

/// This method is for anyone want to compare version correctly to determine
/// which version is newer, older or same. It can be used to determine whether
/// to use webview2 or certain feature base on version.
/// Sets the value of result to -1, 0 or 1 if version1 is less than, equal or
/// greater than version2 respectively.
/// Returns E_INVALIDARG if it fails to parse any of the version strings or any
/// input parameter is null.
/// Input can directly use the versionInfo obtained from
/// GetAvailableCoreWebView2BrowserVersionString, channel info will be ignored.
extern(Windows) HRESULT CompareBrowserVersions(PCWSTR version1, PCWSTR version2, int* result);

}
