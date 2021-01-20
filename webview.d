/++
	A thin wrapper around common system webviews.
	Based on: https://github.com/zserge/webview

	Work in progress. DO NOT USE YET as I am prolly gonna break everything.
+/
module arsd.webview;


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

version(cef) {


	import arsd.simpledisplay;

	void main() {
		auto window = new SimpleWindow;

		window.eventLoop(0);
	}


} else {

version(Windows)
	version=WEBVIEW_EDGE;
else version(linux)
	version=WEBVIEW_GTK;
else version(OSX)
	version=WEBVIEW_COCOA;

version(Demo)
void main() {
	auto wv = new WebView(true, null);
	wv.navigate("http://dpldocs.info/");
	wv.setTitle("omg a D webview");
	wv.setSize(500, 500, true);
	wv.eval("console.log('just testing');");
	wv.run();
}
}

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

version(cef) {
// from derelict-cef
/*

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

*/
// module derelict.cef.types;

private {
    import core.stdc.stddef;
    // import derelict.util.system;
}

// cef_string_*.h
alias void* cef_string_list_t;
alias void* cef_string_map_t;
alias void* cef_string_multimap_t;

struct cef_string_wide_t {
    wchar_t* str;
    size_t length;
    extern( C ) @nogc nothrow void function( wchar* ) dtor;
}

struct cef_string_utf8_t {
    char* str;
    size_t length;
    extern( C ) @nogc nothrow void function( char* ) dtor;
}

struct cef_string_utf16_t {
    wchar* str;
    size_t length;
    extern( C ) @nogc nothrow void function( wchar* ) dtor;
}

alias cef_string_userfree_wide_t = cef_string_wide_t*;
alias cef_string_userfree_utf8_t = cef_string_utf8_t*;
alias cef_string_userfree_utf16_t = cef_string_utf16_t*;

version( DerelictCEF_WideStrings ) {
    enum CEF_STRING_TYPE_WIDE = true;
    enum CEF_STRING_TYPE_UTF16 = false;
    enum CEF_STRING_TYPE_UTF8 = false;
    alias cef_char_t = wchar_t;
    alias cef_string_t = cef_string_wide_t;
    alias cef_string_userfree_t = cef_string_userfree_wide_t;
} else version( DerelictCEF_UTF8Strings ) {
    enum CEF_STRING_TYPE_WIDE = false;
    enum CEF_STRING_TYPE_UTF16 = false;
    enum CEF_STRING_TYPE_UTF8 = true;
    alias cef_char_t = char;
    alias cef_string_t = cef_string_utf8_t;
    alias cef_string_userfree_t = cef_string_userfree_utf8_t;
} else {
    // CEF builds with UTF16 strings by default.
    enum CEF_STRING_TYPE_WIDE = false;
    enum CEF_STRING_TYPE_UTF16 = true;
    enum CEF_STRING_TYPE_UTF8 = false;
    alias cef_char_t = wchar;
    alias cef_string_t = cef_string_utf16_t;
    alias cef_string_userfree_t = cef_string_userfree_utf16_t;
}

// cef_time.h
struct cef_time_t {
    int year;
    int month;
    int day_of_week;
    int day_of_month;
    int hour;
    int minute;
    int second;
    int millisecond;
}

// cef_types.h
alias int64 = long;
alias uint64 = ulong;
alias int32 = int;
alias uint32 = uint;
alias cef_color_t = uint32;
alias char16 = wchar;

alias cef_log_severity_t = int;
enum {
    LOGSEVERITY_DEFAULT,
    LOGSEVERITY_VERBOSE,
    LOGSEVERITY_DEBUG,
    LOGSEVERITY_INFO,
    LOGSEVERITY_WARNING,
    LOGSEVERITY_ERROR,
    LOGSEVERITY_FATAL,
    LOGSEVERITY_DISABLE = 99
}

alias cef_state_t = int;
enum {
    STATE_DEFAULT = 0,
    STATE_ENABLED,
    STATE_DISABLED,
}

struct cef_settings_t {
    size_t size;
    int no_sandbox;
    cef_string_t browser_subprocess_path;
    cef_string_t framework_dir_path;
    int multi_threaded_message_loop;
    int external_message_pump;
    int windowless_rendering_enabled;
    int command_line_args_disabled;
    cef_string_t cache_path;
    cef_string_t user_data_path;
    int persist_session_cookies;
    int persist_user_preferences;
    cef_string_t user_agent;
    cef_string_t product_version;
    cef_string_t locale;
    cef_string_t log_file;
    cef_log_severity_t log_severity;
    cef_string_t javascript_flags;
    cef_string_t resources_dir_path;
    cef_string_t locales_dir_path;
    int pack_loading_disabled;
    int remote_debugging_port;
    int uncaught_exception_stack_size;
    int ignore_certificate_errors;
    int enable_net_security_expiration;
    cef_color_t background_color;
    cef_string_t accept_language_list;
}

struct cef_request_context_settings_t {
    size_t size;
    cef_string_t cache_path;
    int persist_session_cookies;
    int persist_user_preferences;
    int ignore_certificate_errors;
    int enable_net_security_expiration;
    cef_string_t accept_language_list;
}

struct cef_browser_settings_t {
    size_t size;
    int windowless_frame_rate;
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
    cef_string_t default_encoding;
    cef_state_t remote_fonts;
    cef_state_t javascript;
    cef_state_t javascript_close_windows;
    cef_state_t javascript_access_clipboard;
    cef_state_t javascript_dom_paste;
    cef_state_t plugins;
    cef_state_t universal_access_from_file_urls;
    cef_state_t file_access_from_file_urls;
    cef_state_t web_security;
    cef_state_t image_loading;
    cef_state_t image_shrink_standalone_to_fit;
    cef_state_t text_area_resize;
    cef_state_t tab_to_links;
    cef_state_t local_storage;
    cef_state_t databases;
    cef_state_t application_cache;
    cef_state_t webgl;
    cef_color_t background_color;
    cef_string_t accept_language_list;
}

alias cef_return_value_t = int;
enum {
    RV_CANCEL = 0,
    RV_CONTINUE,
    RV_CONTINUE_ASYNC,
}

struct cef_urlparts_t {
    cef_string_t spec;
    cef_string_t scheme;
    cef_string_t username;
    cef_string_t password;
    cef_string_t host;
    cef_string_t port;
    cef_string_t origin;
    cef_string_t path;
    cef_string_t query;
}

struct cef_cookie_t {
    cef_string_t name;
    cef_string_t value;
    cef_string_t domain;
    cef_string_t path;
    int secure;
    int httponly;
    cef_time_t creation;
    cef_time_t last_access;
    int has_expires;
    cef_time_t expires;
}

alias cef_termination_status_t = int;
enum {
    TS_ABNORMAL_TERMINATION,
    TS_PROCESS_WAS_KILLED,
    TS_PROCESS_CRASHED,
    TS_PROCESS_OOM,
}

alias cef_path_key_t = int;
enum {
    PK_DIR_CURRENT,
    PK_DIR_EXE,
    PK_DIR_MODULE,
    PK_DIR_TEMP,
    PK_FILE_EXE,
    PK_FILE_MODULE,
    PK_LOCAL_APP_DATA,
    PK_USER_DATA,
    PK_DIR_RESOURCES,
}

alias cef_storage_type_t = int;
enum {
    ST_LOCALSTORAGE = 0,
    ST_SESSIONSTORAGE,
}

alias cef_errorcode_t = int;
enum {
    ERR_NONE = 0,
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
    ERR_CERT_COMMON_NAME_INVALID = -200,
    ERR_CERT_DATE_INVALID = -201,
    ERR_CERT_AUTHORITY_INVALID = -202,
    ERR_CERT_CONTAINS_ERRORS = -203,
    ERR_CERT_NO_REVOCATION_MECHANISM = -204,
    ERR_CERT_UNABLE_TO_CHECK_REVOCATION = -205,
    ERR_CERT_REVOKED = -206,
    ERR_CERT_INVALID = -207,
    ERR_CERT_END = -208,
    ERR_INVALID_URL = -300,
    ERR_DISALLOWED_URL_SCHEME = -301,
    ERR_UNKNOWN_URL_SCHEME = -302,
    ERR_TOO_MANY_REDIRECTS = -310,
    ERR_UNSAFE_REDIRECT = -311,
    ERR_UNSAFE_PORT = -312,
    ERR_INVALID_RESPONSE = -320,
    ERR_INVALID_CHUNKED_ENCODING = -321,
    ERR_METHOD_NOT_SUPPORTED = -322,
    ERR_UNEXPECTED_PROXY_AUTH = -323,
    ERR_EMPTY_RESPONSE = -324,
    ERR_RESPONSE_HEADERS_TOO_BIG = -325,
    ERR_CACHE_MISS = -400,
    ERR_INSECURE_RESPONSE = -501,
}

alias cef_cert_status_t = int;
enum {
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
    CERT_STATUS_CT_COMPLIANCE_FAILED = 1 << 20,
}

alias cef_window_open_disposition_t = int;
enum {
    WOD_UNKNOWN,
    WOD_CURRENT_TAB,
    WOD_SINGLETON_TAB,
    WOD_NEW_FOREGROUND_TAB,
    WOD_NEW_BACKGROUND_TAB,
    WOD_NEW_POPUP,
    WOD_NEW_WINDOW,
    WOD_SAVE_TO_DISK,
    WOD_OFF_THE_RECORD,
    WOD_IGNORE_ACTION
}


alias cef_drag_operations_mask_t = int;
enum {
    DRAG_OPERATION_NONE = 0,
    DRAG_OPERATION_COPY = 1,
    DRAG_OPERATION_LINK = 2,
    DRAG_OPERATION_GENERIC = 4,
    DRAG_OPERATION_PRIVATE = 8,
    DRAG_OPERATION_MOVE = 16,
    DRAG_OPERATION_DELETE = 32,
    DRAG_OPERATION_EVERY = uint.max,
}

alias cef_v8_accesscontrol_t = int;
enum {
    V8_ACCESS_CONTROL_DEFAULT = 0,
    V8_ACCESS_CONTROL_ALL_CAN_READ = 1,
    V8_ACCESS_CONTROL_ALL_CAN_WRITE = 1<<1,
    V8_ACCESS_CONTROL_PROHIBITS_OVERWRITING = 1<<2
}

alias cef_v8_propertyattribute_t = int;
enum {
    V8_PROPERTY_ATTRIBUTE_NONE       = 0,
    V8_PROPERTY_ATTRIBUTE_READONLY   = 1<<0,
    V8_PROPERTY_ATTRIBUTE_DONTENUM   = 1<<1,
    V8_PROPERTY_ATTRIBUTE_DONTDELETE = 1<<2
}

alias cef_postdataelement_type_t = int;
enum {
    PDE_TYPE_EMPTY = 0,
    PDE_TYPE_BYTES,
    PDE_TYPE_FILE,
}

alias cef_resource_type_t = int;
enum {
    RT_MAIN_FRAME = 0,
    RT_SUB_FRAME,
    RT_STYLESHEET,
    RT_SCRIPT,
    RT_IMAGE,
    RT_FONT_RESOURCE,
    RT_SUB_RESOURCE,
    RT_OBJECT,
    RT_MEDIA,
    RT_WORKER,
    RT_SHARED_WORKER,
    RT_PREFETCH,
    RT_FAVICON,
    RT_XHR,
    RT_PING,
    RT_SERVICE_WORKER,
    RT_CSP_REPORT,
    RT_PLUGIN_RESOURCE,
}

alias cef_transition_type_t = int;
enum {
    TT_LINK = 0,
    TT_EXPLICIT = 1,
    TT_AUTO_SUBFRAME = 3,
    TT_MANUAL_SUBFRAME = 4,
    TT_FORM_SUBMIT = 7,
    TT_RELOAD = 8,
    TT_SOURCE_MASK = 0xFF,
    TT_BLOCKED_FLAG = 0x00800000,
    TT_FORWARD_BACK_FLAG = 0x01000000,
    TT_CHAIN_START_FLAG = 0x10000000,
    TT_CHAIN_END_FLAG = 0x20000000,
    TT_CLIENT_REDIRECT_FLAG = 0x40000000,
    TT_SERVER_REDIRECT_FLAG = 0x80000000,
    TT_IS_REDIRECT_MASK = 0xC0000000,
    TT_QUALIFIER_MASK = 0xFFFFFF00,
}

alias cef_urlrequest_flags_t = int;
enum {
    UR_FLAG_NONE = 0,
    UR_FLAG_SKIP_CACHE = 1 << 0,
    UR_FLAG_ONLY_FROM_CACHE = 1 << 1,
    UR_FLAG_ALLOW_STORED_CREDENTIALS = 1 << 2,
    UR_FLAG_REPORT_UPLOAD_PROGRESS = 1 << 3,
    UR_FLAG_NO_DOWNLOAD_DATA = 1 << 4,
    UR_FLAG_NO_RETRY_ON_5XX = 1 << 5,
    UR_FLAG_STOP_ON_REDIRECT = 1 << 6,
}

alias cef_urlrequest_status_t = int;
enum {
    UR_UNKNOWN = 0,
    UR_SUCCESS,
    UR_IO_PENDING,
    UR_CANCELED,
    UR_FAILED,
}

struct cef_point_t {
    int x;
    int y;
}

struct cef_rect_t {
    int x;
    int y;
    int width;
    int height;
}

struct cef_size_t {
    int width;
    int height;
}

struct cef_range_t {
    int from;
    int to;
}

struct cef_insets_t {
  int top;
  int left;
  int bottom;
  int right;
}

struct cef_draggable_region_t {
    cef_rect_t bounds;
    int draggable;
}

alias cef_process_id_t = int;
enum {
    PID_BROWSER,
    PID_RENDERER,
}

alias cef_thread_id_t = int;
enum {
    TID_UI,
    TID_DB,
    TID_FILE,
    TID_FILE_USER_BLOCKING,
    TID_PROCESS_LAUNCHER,
    TID_CACHE,
    TID_IO,
    TID_RENDERER,
}

alias cef_thread_priority_t = int;
enum {
    TP_BACKGROUND,
    TP_NORMAL,
    TP_DISPLAY,
    TP_REALTIME_AUDIO,
}

alias cef_message_loop_type_t = int;
enum {
    ML_TYPE_DEFAULT,
    ML_TYPE_UI,
    ML_TYPE_IO,
}

alias cef_com_init_mode_t = int;
enum {
    COM_INIT_MODE_NONE,
    COM_INIT_MODE_STA,
    COM_INIT_MODE_MTA,
}

alias cef_value_type_t = int;
enum {
    VTYPE_INVALID = 0,
    VTYPE_NULL,
    VTYPE_BOOL,
    VTYPE_INT,
    VTYPE_DOUBLE,
    VTYPE_STRING,
    VTYPE_BINARY,
    VTYPE_DICTIONARY,
    VTYPE_LIST,
}

alias cef_jsdialog_type_t = int;
enum {
    JSDIALOGTYPE_ALERT = 0,
    JSDIALOGTYPE_CONFIRM,
    JSDIALOGTYPE_PROMPT,
}

struct cef_screen_info_t {
    float device_scale_factor;
    int depth;
    int depth_per_component;
    int is_monochrome;
    cef_rect_t rect;
    cef_rect_t available_rect;
}

alias cef_menu_id_t = int;
enum {
    MENU_ID_BACK = 100,
    MENU_ID_FORWARD = 101,
    MENU_ID_RELOAD = 102,
    MENU_ID_RELOAD_NOCACHE = 103,
    MENU_ID_STOPLOAD = 104,
    MENU_ID_UNDO = 110,
    MENU_ID_REDO = 111,
    MENU_ID_CUT = 112,
    MENU_ID_COPY = 113,
    MENU_ID_PASTE = 114,
    MENU_ID_DELETE = 115,
    MENU_ID_SELECT_ALL = 116,
    MENU_ID_FIND = 130,
    MENU_ID_PRINT = 131,
    MENU_ID_VIEW_SOURCE = 132,
    MENU_ID_SPELLCHECK_SUGGESTION_0 = 200,
    MENU_ID_SPELLCHECK_SUGGESTION_1 = 201,
    MENU_ID_SPELLCHECK_SUGGESTION_2 = 202,
    MENU_ID_SPELLCHECK_SUGGESTION_3 = 203,
    MENU_ID_SPELLCHECK_SUGGESTION_4 = 204,
    MENU_ID_SPELLCHECK_SUGGESTION_LAST = 204,
    MENU_ID_NO_SPELLING_SUGGESTIONS = 205,
    MENU_ID_ADD_TO_DICTIONARY = 206,
    MENU_ID_CUSTOM_FIRST = 220,
    MENU_ID_CUSTOM_LAST = 250,
    MENU_ID_USER_FIRST = 26500,
    MENU_ID_USER_LAST = 28500,
}

alias cef_mouse_button_type_t = int;
enum {
    MBT_LEFT = 0,
    MBT_MIDDLE,
    MBT_RIGHT,
}

struct cef_mouse_event_t {
    int x;
    int y;
    uint32 modifiers;
}

alias cef_paint_element_type_t = int;
enum {
    PET_VIEW = 0,
    PET_POPUP,
}

alias cef_event_flags_t = int;
enum {
    EVENTFLAG_NONE = 0,
    EVENTFLAG_CAPS_LOCK_ON = 1<<0,
    EVENTFLAG_SHIFT_DOWN = 1<<1,
    EVENTFLAG_CONTROL_DOWN = 1<<2,
    EVENTFLAG_ALT_DOWN = 1<<3,
    EVENTFLAG_LEFT_MOUSE_BUTTON = 1<<4,
    EVENTFLAG_MIDDLE_MOUSE_BUTTON = 1<<5,
    EVENTFLAG_RIGHT_MOUSE_BUTTON = 1<<6,
    EVENTFLAG_COMMAND_DOWN = 1<<7,
    EVENTFLAG_NUM_LOCK_ON = 1<<8,
    EVENTFLAG_IS_KEY_PAD = 1<<9,
    EVENTFLAG_IS_LEFT = 1<<10,
    EVENTFLAG_IS_RIGHT = 1<<11,
}

alias cef_menu_item_type_t = int;
enum {
    MENUITEMTYPE_NONE,
    MENUITEMTYPE_COMMAND,
    MENUITEMTYPE_CHECK,
    MENUITEMTYPE_RADIO,
    MENUITEMTYPE_SEPARATOR,
    MENUITEMTYPE_SUBMENU,
}

alias cef_context_menu_type_flags_t = int;
enum {
    CM_TYPEFLAG_NONE = 0,
    CM_TYPEFLAG_PAGE = 1<<0,
    CM_TYPEFLAG_FRAME = 1<<1,
    CM_TYPEFLAG_LINK = 1<<2,
    CM_TYPEFLAG_MEDIA = 1<<3,
    CM_TYPEFLAG_SELECTION = 1<<4,
    CM_TYPEFLAG_EDITABLE = 1<<5,
}

alias cef_context_menu_media_type_t = int;
enum {
    CM_MEDIATYPE_NONE,
    CM_MEDIATYPE_IMAGE,
    CM_MEDIATYPE_VIDEO,
    CM_MEDIATYPE_AUDIO,
    CM_MEDIATYPE_FILE,
    CM_MEDIATYPE_PLUGIN,
}

alias cef_context_menu_media_state_flags_t = int;
enum {
    CM_MEDIAFLAG_NONE = 0,
    CM_MEDIAFLAG_ERROR = 1<<0,
    CM_MEDIAFLAG_PAUSED = 1<<1,
    CM_MEDIAFLAG_MUTED = 1<<2,
    CM_MEDIAFLAG_LOOP = 1<<3,
    CM_MEDIAFLAG_CAN_SAVE = 1<<4,
    CM_MEDIAFLAG_HAS_AUDIO = 1<<5,
    CM_MEDIAFLAG_HAS_VIDEO = 1<<6,
    CM_MEDIAFLAG_CONTROL_ROOT_ELEMENT = 1<<7,
    CM_MEDIAFLAG_CAN_PRINT = 1<<8,
    CM_MEDIAFLAG_CAN_ROTATE = 1<<9,
}

alias cef_context_menu_edit_state_flags_t = int;
enum {
    CM_EDITFLAG_NONE = 0,
    CM_EDITFLAG_CAN_UNDO = 1<<0,
    CM_EDITFLAG_CAN_REDO = 1<<1,
    CM_EDITFLAG_CAN_CUT = 1<<2,
    CM_EDITFLAG_CAN_COPY = 1<<3,
    CM_EDITFLAG_CAN_PASTE = 1<<4,
    CM_EDITFLAG_CAN_DELETE = 1<<5,
    CM_EDITFLAG_CAN_SELECT_ALL = 1<<6,
    CM_EDITFLAG_CAN_TRANSLATE = 1<<7,
}

alias cef_key_event_type_t = int;
enum {
    KEYEVENT_RAWKEYDOWN = 0,
    KEYEVENT_KEYDOWN,
    KEYEVENT_KEYUP,
    KEYEVENT_CHAR
}

struct cef_key_event_t {
    cef_key_event_type_t type;
    uint32 modifiers;
    int windows_key_code;
    int native_key_code;
    int is_system_key;
    char16 character;
    char16 unmodified_character;
    int focus_on_editable_field;
}

alias cef_focus_source_t = int;
enum {
    FOCUS_SOURCE_NAVIGATION = 0,
    FOCUS_SOURCE_SYSTEM,
}

alias cef_navigation_type_t = int;
enum {
    NAVIGATION_LINK_CLICKED = 0,
    NAVIGATION_FORM_SUBMITTED,
    NAVIGATION_BACK_FORWARD,
    NAVIGATION_RELOAD,
    NAVIGATION_FORM_RESUBMITTED,
    NAVIGATION_OTHER,
}

alias cef_xml_encoding_type_t = int;
enum {
    XML_ENCODING_NONE = 0,
    XML_ENCODING_UTF8,
    XML_ENCODING_UTF16LE,
    XML_ENCODING_UTF16BE,
    XML_ENCODING_ASCII,
}

alias cef_xml_node_type_t = int;
enum {
    XML_NODE_UNSUPPORTED = 0,
    XML_NODE_PROCESSING_INSTRUCTION,
    XML_NODE_DOCUMENT_TYPE,
    XML_NODE_ELEMENT_START,
    XML_NODE_ELEMENT_END,
    XML_NODE_ATTRIBUTE,
    XML_NODE_TEXT,
    XML_NODE_CDATA,
    XML_NODE_ENTITY_REFERENCE,
    XML_NODE_WHITESPACE,
    XML_NODE_COMMENT,
}

struct cef_popup_features_t {
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

alias cef_dom_document_type_t = int;
enum {
    DOM_DOCUMENT_TYPE_UNKNOWN = 0,
    DOM_DOCUMENT_TYPE_HTML,
    DOM_DOCUMENT_TYPE_XHTML,
    DOM_DOCUMENT_TYPE_PLUGIN,
}

alias cef_dom_event_category_t = int;
enum {
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
    DOM_EVENT_CATEGORY_XMLHTTPREQUEST_PROGRESS = 0x8000,
}

alias cef_dom_event_phase_t = int;
enum {
    DOM_EVENT_PHASE_UNKNOWN = 0,
    DOM_EVENT_PHASE_CAPTURING,
    DOM_EVENT_PHASE_AT_TARGET,
    DOM_EVENT_PHASE_BUBBLING,
}

alias cef_dom_node_type_t = int;
enum {
    DOM_NODE_TYPE_UNSUPPORTED = 0,
    DOM_NODE_TYPE_ELEMENT,
    DOM_NODE_TYPE_ATTRIBUTE,
    DOM_NODE_TYPE_TEXT,
    DOM_NODE_TYPE_CDATA_SECTION,
    DOM_NODE_TYPE_PROCESSING_INSTRUCTIONS,
    DOM_NODE_TYPE_COMMENT,
    DOM_NODE_TYPE_DOCUMENT,
    DOM_NODE_TYPE_DOCUMENT_TYPE,
    DOM_NODE_TYPE_DOCUMENT_FRAGMENT
}

alias cef_file_dialog_mode_t = int;
enum {
    FILE_DIALOG_OPEN,
    FILE_DIALOG_OPEN_MULTIPLE,
    FILE_DIALOG_OPEN_FOLDER,
    FILE_DIALOG_SAVE,
    FILE_DIALOG_TYPE_MASK = 0xFF,
    FILE_DIALOG_OVERWRITEPROMPT_FLAG = 0x01000000,
    FILE_DIALOG_HIDEREADONLY_FLAG = 0x02000000,
}

alias cef_color_model_t = int;
enum {
    COLOR_MODEL_UNKNOWN,
    COLOR_MODEL_GRAY,
    COLOR_MODEL_COLOR,
    COLOR_MODEL_CMYK,
    COLOR_MODEL_CMY,
    COLOR_MODEL_KCMY,
    COLOR_MODEL_CMY_K,  // CMY_K represents CMY+K.
    COLOR_MODEL_BLACK,
    COLOR_MODEL_GRAYSCALE,
    COLOR_MODEL_RGB,
    COLOR_MODEL_RGB16,
    COLOR_MODEL_RGBA,
    COLOR_MODEL_COLORMODE_COLOR,              // Used in samsung printer ppds.
    COLOR_MODEL_COLORMODE_MONOCHROME,         // Used in samsung printer ppds.
    COLOR_MODEL_HP_COLOR_COLOR,               // Used in HP color printer ppds.
    COLOR_MODEL_HP_COLOR_BLACK,               // Used in HP color printer ppds.
    COLOR_MODEL_PRINTOUTMODE_NORMAL,          // Used in foomatic ppds.
    COLOR_MODEL_PRINTOUTMODE_NORMAL_GRAY,     // Used in foomatic ppds.
    COLOR_MODEL_PROCESSCOLORMODEL_CMYK,       // Used in canon printer ppds.
    COLOR_MODEL_PROCESSCOLORMODEL_GREYSCALE,  // Used in canon printer ppds.
    COLOR_MODEL_PROCESSCOLORMODEL_RGB,        // Used in canon printer ppds
}

alias cef_duplex_mode_t = int;
enum {
    DUPLEX_MODE_UNKNOWN = -1,
    DUPLEX_MODE_SIMPLEX,
    DUPLEX_MODE_LONG_EDGE,
    DUPLEX_MODE_SHORT_EDGE,
}

alias cef_cursor_type_t = int;
enum {
    CT_POINTER = 0,
    CT_CROSS,
    CT_HAND,
    CT_IBEAM,
    CT_WAIT,
    CT_HELP,
    CT_EASTRESIZE,
    CT_NORTHRESIZE,
    CT_NORTHEASTRESIZE,
    CT_NORTHWESTRESIZE,
    CT_SOUTHRESIZE,
    CT_SOUTHEASTRESIZE,
    CT_SOUTHWESTRESIZE,
    CT_WESTRESIZE,
    CT_NORTHSOUTHRESIZE,
    CT_EASTWESTRESIZE,
    CT_NORTHEASTSOUTHWESTRESIZE,
    CT_NORTHWESTSOUTHEASTRESIZE,
    CT_COLUMNRESIZE,
    CT_ROWRESIZE,
    CT_MIDDLEPANNING,
    CT_EASTPANNING,
    CT_NORTHPANNING,
    CT_NORTHEASTPANNING,
    CT_NORTHWESTPANNING,
    CT_SOUTHPANNING,
    CT_SOUTHEASTPANNING,
    CT_SOUTHWESTPANNING,
    CT_WESTPANNING,
    CT_MOVE,
    CT_VERTICALTEXT,
    CT_CELL,
    CT_CONTEXTMENU,
    CT_ALIAS,
    CT_PROGRESS,
    CT_NODROP,
    CT_COPY,
    CT_NONE,
    CT_NOTALLOWED,
    CT_ZOOMIN,
    CT_ZOOMOUT,
    CT_GRAB,
    CT_GRABBING,
    CT_CUSTOM,
}

struct cef_cursor_info_t {
    cef_point_t hotspot;
    float image_scale_factor;
    void* buffer;
    cef_size_t size;
}

alias cef_uri_unescape_rule_t = int;
enum {
    UU_NONE = 0,
    UU_NORMAL = 1 << 0,
    UU_SPACES = 1 << 1,
    UU_PATH_SEPARATORS = 1 << 2,
    UU_URL_SPECIAL_CHARS_EXCEPT_PATH_SEPARATORS = 1 << 3,
    UU_SPOOFING_AND_CONTROL_CHARS = 1 << 4,
    UU_REPLACE_PLUS_WITH_SPACE = 1 << 5,
}

alias cef_json_parser_options_t = int;
enum {
    JSON_PARSER_RFC = 0,
    JSON_PARSER_ALLOW_TRAILING_COMMAS = 1 << 0,
}

alias cef_json_parser_error_t = int;
enum {
    JSON_NO_ERROR = 0,
    JSON_INVALID_ESCAPE,
    JSON_SYNTAX_ERROR,
    JSON_UNEXPECTED_TOKEN,
    JSON_TRAILING_COMMA,
    JSON_TOO_MUCH_NESTING,
    JSON_UNEXPECTED_DATA_AFTER_ROOT,
    JSON_UNSUPPORTED_ENCODING,
    JSON_UNQUOTED_DICTIONARY_KEY,
    JSON_PARSE_ERROR_COUNT
}

alias cef_json_writer_options_t = int;
enum {
    JSON_WRITER_DEFAULT = 0,
    JSON_WRITER_OMIT_BINARY_VALUES = 1 << 0,
    JSON_WRITER_OMIT_DOUBLE_TYPE_PRESERVATION = 1 << 1,
    JSON_WRITER_PRETTY_PRINT = 1 << 2,
}

alias cef_pdf_print_margin_type_t = int;
enum {
    PDF_PRINT_MARGIN_DEFAULT,
    PDF_PRINT_MARGIN_NONE,
    PDF_PRINT_MARGIN_MINIMUM,
    PDF_PRINT_MARGIN_CUSTOM,
}

struct cef_pdf_print_settings_t {
    cef_string_t header_footer_title;
    cef_string_t header_footer_url;
    int page_width;
    int page_height;
    int scale_factor;
    double margin_top;
    double margin_right;
    double margin_bottom;
    double margin_left;
    cef_pdf_print_margin_type_t margin_type;
    int header_footer_enabled;
    int selection_only;
    int landscape;
    int backgrounds_enabled;
}

alias cef_scale_factor_t = int;
enum {
    SCALE_FACTOR_NONE = 0,
    SCALE_FACTOR_100P,
    SCALE_FACTOR_125P,
    SCALE_FACTOR_133P,
    SCALE_FACTOR_140P,
    SCALE_FACTOR_150P,
    SCALE_FACTOR_180P,
    SCALE_FACTOR_200P,
    SCALE_FACTOR_250P,
    SCALE_FACTOR_300P,
}

alias cef_plugin_policy_t = int;
enum {
    PLUGIN_POLICY_ALLOW,
    PLUGIN_POLICY_DETECT_IMPORTANT,
    PLUGIN_POLICY_BLOCK,
    PLUGIN_POLICY_DISABLE,
}

alias cef_referrer_policy_t = int;
enum {
    REFERRER_POLICY_CLEAR_REFERRER_ON_TRANSITION_FROM_SECURE_TO_INSECURE,
    REFERRER_POLICY_DEFAULT,
    REFERRER_POLICY_REDUCE_REFERRER_GRANULARITY_ON_TRANSITION_CROSS_ORIGIN,
    REFERRER_POLICY_ORIGIN_ONLY_ON_TRANSITION_CROSS_ORIGIN,
    REFERRER_POLICY_NEVER_CLEAR_REFERRER,
    REFERRER_POLICY_ORIGIN,
    REFERRER_POLICY_CLEAR_REFERRER_ON_TRANSITION_CROSS_ORIGIN,
    REFERRER_POLICY_ORIGIN_CLEAR_ON_TRANSITION_FROM_SECURE_TO_INSECURE,
    REFERRER_POLICY_NO_REFERRER,
    REFERRER_POLICY_LAST_VALUE,
}

alias cef_response_filter_status_t = int;
enum {
    RESPONSE_FILTER_NEED_MORE_DATA,
    RESPONSE_FILTER_DONE,
    RESPONSE_FILTER_ERROR
}

alias cef_color_type_t = int;
enum {
    CEF_COLOR_TYPE_RGBA_8888,
    CEF_COLOR_TYPE_BGRA_8888,
}

alias cef_alpha_type_t = int;
enum {
    CEF_ALPHA_TYPE_OPAQUE,
    CEF_ALPHA_TYPE_PREMULTIPLIED,
    CEF_ALPHA_TYPE_POSTMULTIPLIED,
}

alias cef_text_style_t = int;
enum {
    CEF_TEXT_STYLE_BOLD,
    CEF_TEXT_STYLE_ITALIC,
    CEF_TEXT_STYLE_STRIKE,
    CEF_TEXT_STYLE_DIAGONAL_STRIKE,
    CEF_TEXT_STYLE_UNDERLINE,
}

alias cef_main_axis_alignment_t = int;
enum {
    CEF_MAIN_AXIS_ALIGNMENT_START,
    CEF_MAIN_AXIS_ALIGNMENT_CENTER,
    CEF_MAIN_AXIS_ALIGNMENT_END,
}

alias cef_cross_axis_alignment_t = int;
enum {
    CEF_CROSS_AXIS_ALIGNMENT_STRETCH,
    CEF_CROSS_AXIS_ALIGNMENT_START,
    CEF_CROSS_AXIS_ALIGNMENT_CENTER,
    CEF_CROSS_AXIS_ALIGNMENT_END,
}

struct cef_box_layout_settings_t {
    int horizontal;
    int inside_border_horizontal_spacing;
    int inside_border_vertical_spacing;
    cef_insets_t inside_border_insets;
    int between_child_spacing;
    cef_main_axis_alignment_t main_axis_alignment;
    cef_cross_axis_alignment_t cross_axis_alignment;
    int minimum_cross_axis_size;
    int default_flex;
}

alias cef_button_state_t = int;
enum {
    CEF_BUTTON_STATE_NORMAL,
    CEF_BUTTON_STATE_HOVERED,
    CEF_BUTTON_STATE_PRESSED,
    CEF_BUTTON_STATE_DISABLED,
}

alias cef_horizontal_alignment_t = int;
enum {
    CEF_HORIZONTAL_ALIGNMENT_LEFT,
    CEF_HORIZONTAL_ALIGNMENT_CENTER,
    CEF_HORIZONTAL_ALIGNMENT_RIGHT,
}

alias cef_menu_anchor_position_t = int;
enum {
  CEF_MENU_ANCHOR_TOPLEFT,
  CEF_MENU_ANCHOR_TOPRIGHT,
  CEF_MENU_ANCHOR_BOTTOMCENTER,
}

alias cef_menu_color_type_t = int;
enum {
    CEF_MENU_COLOR_TEXT,
    CEF_MENU_COLOR_TEXT_HOVERED,
    CEF_MENU_COLOR_TEXT_ACCELERATOR,
    CEF_MENU_COLOR_TEXT_ACCELERATOR_HOVERED,
    CEF_MENU_COLOR_BACKGROUND,
    CEF_MENU_COLOR_BACKGROUND_HOVERED,
    CEF_MENU_COLOR_COUNT,
}

alias cef_ssl_version_t = int;
enum {
    SSL_CONNECTION_VERSION_UNKNOWN = 0,
    SSL_CONNECTION_VERSION_SSL2 = 1,
    SSL_CONNECTION_VERSION_SSL3 = 2,
    SSL_CONNECTION_VERSION_TLS1 = 3,
    SSL_CONNECTION_VERSION_TLS1_1 = 4,
    SSL_CONNECTION_VERSION_TLS1_2 = 5,
    SSL_CONNECTION_VERSION_QUIC = 7,
}

alias cef_ssl_content_status_t = int;
enum {
    SSL_CONTENT_NORMAL_CONTENT = 0,
    SSL_CONTENT_DISPLAYED_INSECURE_CONTENT = 1 << 0,
    SSL_CONTENT_RAN_INSECURE_CONTENT = 1 << 1,
}

alias cef_cdm_registration_error_t = int;
enum {
    CEF_CDM_REGISTRATION_ERROR_NONE,
    CEF_CDM_REGISTRATION_ERROR_INCORRECT_CONTENTS,
    CEF_CDM_REGISTRATION_ERROR_INCOMPATIBLE,
    CEF_CDM_REGISTRATION_ERROR_NOT_SUPPORTED,
}

struct cef_composition_underline_t {
    cef_range_t range;
    cef_color_t color;
    cef_color_t background_color;
    int thick;
}

// cef_types_win.h
alias cef_cursor_handle_t = void*;
alias cef_event_handle_t = void*;
alias cef_window_handle_t = void*;
alias cef_text_input_context_t = void*;

static if( Derelict_OS_Windows ) {
    struct cef_main_args_t {
        void* instance;
    }

    struct cef_window_info_t {
        uint ex_style;
        cef_string_t window_name;
        uint style;
        int x;
        int y;
        int width;
        int height;
        cef_window_handle_t parent_window;
        void* menu;
        int window_rendering_disabled;
        int transparent_painting;
        cef_window_handle_t window;
    }
} else static if( Derelict_OS_Linux ) {
    struct cef_main_args_t {
        int argc;
        char** argv;
    }

    struct cef_window_info_t {
        cef_window_handle_t parent_widget;
        int window_rendering_disabled;
        int transparent_painting;
        cef_window_handle_t widget;
    }
} else static if( Derelict_OS_Mac ) {
    struct cef_main_args_t {
        int argc;
        char** argv;
    }

    struct cef_window_info_t {
        cef_string_t window_name;
        int x;
        int y;
        int width;
        int height;
        int hidden;
        cef_window_handle_t parent_view;
        int window_rendering_disabled;
        int transparent_painting;
        cef_window_handle_t view;
    }
} else {
    static assert( 0, "Platform-specific types not yet implemented on this platform." );
}

// cef_accessibility_handler_capi.h
struct cef_accessibility_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_accessibility_handler_t* , cef_value_t* ) on_accessibility_tree_change;
        void function( cef_accessibility_handler_t*, cef_value_t* ) on_accessibility_location_change;
    }
}

// cef_app_capi.h
struct cef_app_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_app_t*,const( cef_string_t )*,cef_command_line_t* ) on_before_command_line_processing;
        void function( cef_app_t*,cef_scheme_registrar_t* ) on_register_custom_schemes;
        cef_resource_bundle_handler_t* function( cef_app_t* ) get_resource_bundle_handler;
        cef_browser_process_handler_t* function( cef_app_t* ) get_browser_process_handler;
        cef_render_process_handler_t* function( cef_app_t* ) get_render_process_handler;
    }
}

// cef_auth_callback_capi.h
struct cef_auth_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_auth_callback_t*, const( cef_string_t )*, const( cef_string_t )* ) cont;
        void function( cef_auth_callback_t* ) cancel;
    }
}

// cef_base_capi.h
struct cef_base_t {
    size_t size;
    extern( System ) @nogc nothrow {
        int function( cef_base_t* ) add_ref;
        int function( cef_base_t* ) release;
        int function( cef_base_t* ) has_one_ref;
        int function( cef_base_t* ) has_at_least_one_ref;
    }
}

struct cef_base_scoped_t {
    size_t size;
    extern( System ) @nogc nothrow void function( cef_base_scoped_t* ) del;
}

// cef_browser_capi.h
static if( Derelict_OS_Windows ) {
    alias cef_platform_thread_id_t = uint;
    alias cef_platform_thread_handle_t = uint;
} else static if( Derelict_OS_Posix ) {
    import core.sys.posix.unistd: pid_t;
    alias cef_platform_thread_id_t = pid_t;
    alias cef_platform_thread_handle_t = pid_t;
} else {
    static assert( 0, "Platform-specific types not yet implemented on this platform." );
}

struct cef_browser_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_browser_host_t* function( cef_browser_t* ) get_host;
        int function( cef_browser_t* ) can_go_back;
        void function( cef_browser_t* ) go_back;
        int function( cef_browser_t* ) can_go_forward;
        void function( cef_browser_t* ) go_forward;
        int function( cef_browser_t* ) is_loading;
        void function( cef_browser_t* ) reload;
        void function( cef_browser_t* ) reload_ignore_cache;
        void function( cef_browser_t* ) stop_load;
        int function( cef_browser_t* ) get_identifier;
        int function( cef_browser_t*,cef_browser_t* ) is_same;
        int function( cef_browser_t* ) is_popup;
        int function( cef_browser_t* ) has_document;
        cef_frame_t* function( cef_browser_t* ) get_main_frame;
        cef_frame_t* function( cef_browser_t* ) get_focused_frame;
        cef_frame_t* function( cef_browser_t*,int64 ) get_frame_byident;
        cef_frame_t* function( cef_browser_t*,const( cef_string_t )* ) get_frame;
        size_t function( cef_browser_t* ) get_frame_count;
        void function( cef_browser_t*,size_t*,int64* ) get_frame_identifiers;
        void function( cef_browser_t*,cef_string_list_t ) get_frame_names;
        int function( cef_browser_t*,cef_process_id_t,cef_process_message_t* ) send_process_message;
    }
}

struct cef_run_file_dialog_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_run_file_dialog_callback_t*,cef_browser_host_t*,cef_string_list_t ) cont;
}

struct cef_navigation_entry_visitor_t {
    cef_base_t base;
    extern( System ) @nogc nothrow int function( cef_navigation_entry_visitor_t*, cef_navigation_entry_t*, int, int, int ) visit;
}

struct cef_pdf_print_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_pdf_print_callback_t*, const( cef_string_t )*, int ) on_pdf_print_finished;
}

struct cef_download_image_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_download_image_callback_t*, const( cef_string_t )*, int, cef_image_t* ) on_download_image_finished;
}

struct cef_browser_host_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_browser_t* function( cef_browser_host_t* ) get_browser;
        void function( cef_browser_host_t*, int ) close_browser;
        int function( cef_browser_host_t* ) try_close_browser;
        void function( cef_browser_host_t*, int ) set_focus;
        cef_window_handle_t function( cef_browser_host_t* ) get_window_handle;
        cef_window_handle_t function( cef_browser_host_t* ) get_opener_window_handle;
        int function( cef_browser_host_t* ) has_view;
        cef_client_t* function( cef_browser_host_t* ) get_client;
        cef_request_context_t* function( cef_browser_host_t* ) get_request_context;
        double function( cef_browser_host_t* ) get_zoom_level;
        void function( cef_browser_host_t*, double ) set_zoom_level;
        void function( cef_browser_host_t*, cef_file_dialog_mode_t, const( cef_string_t )*, const( cef_string_t )*, cef_string_list_t, int, cef_run_file_dialog_callback_t* ) run_file_dialog;
        void function( cef_browser_host_t*, const( cef_string_t )* ) start_download;
        void function( cef_browser_host_t*, const( cef_string_t )*, int, uint32, int, cef_download_image_callback_t* ) download_image;
        void function( cef_browser_host_t* ) print;
        void function( cef_browser_host_t*, const( cef_string_t )*, const( cef_pdf_print_settings_t )* settings, cef_pdf_print_callback_t* ) print_to_pdf;
        void function( cef_browser_host_t*, int, const( cef_string_t )*, int, int, int ) find;
        void function( cef_browser_host_t*, int ) stop_finding;
        void function( cef_browser_host_t*, const( cef_window_info_t )*, cef_client_t*, const( cef_browser_settings_t )*, const( cef_point_t )* ) show_dev_tools;
        void function( cef_browser_host_t* ) close_dev_tools;
        int function( cef_browser_host_t* ) has_dev_tools;
        void function( cef_browser_host_t*, cef_navigation_entry_visitor_t*, int ) get_navigation_entries;
        void function( cef_browser_host_t*, int ) set_mouse_cursor_change_disabled;
        int function( cef_browser_host_t* ) is_mouse_cursor_change_disabled;
        void function( cef_browser_host_t*, const( cef_string_t )* ) replace_misspelling;
        void function( cef_browser_host_t*, const( cef_string_t )* ) add_word_to_dictionary;
        int function( cef_browser_host_t* ) is_window_rendering_disabled;
        void function( cef_browser_host_t* ) was_resized;
        void function( cef_browser_host_t*, int ) was_hidden;
        void function( cef_browser_host_t* ) notify_screen_info_changed;
        void function( cef_browser_host_t*, cef_paint_element_type_t ) invalidate;
        void function( cef_browser_host_t* ) send_external_begin_frame;
        void function( cef_browser_host_t*, const( cef_key_event_t )* ) send_key_event;
        void function( cef_browser_host_t*, const( cef_mouse_event_t )*, cef_mouse_button_type_t, int, int ) send_mouse_click_event;
        void function( cef_browser_host_t*, const( cef_mouse_event_t )*, int ) send_mouse_move_event;
        void function( cef_browser_host_t* self, const( cef_mouse_event_t )*, int, int ) send_mouse_wheel_event;
        void function( cef_browser_host_t*, int ) send_focus_event;
        void function( cef_browser_host_t* ) send_capture_lost_event;
        void function( cef_browser_host_t* ) notify_move_or_resize_started;
        int function( cef_browser_host_t* ) get_windowless_frame_rate;
        void function( cef_browser_host_t*, int ) set_windowless_frame_rate;
        void function( cef_browser_host_t*, const( cef_string_t )*, size_t, const( cef_composition_underline_t* ), const( cef_range_t )*, const( cef_range_t )* ) ime_set_composition;
        void function( cef_browser_host_t*, const( cef_string_t )*, const( cef_range_t )*, int ) ime_commit_text;
        void function( cef_browser_host_t*, int ) ime_finish_composing_text;
        void function( cef_browser_host_t* ) ime_cancel_composition;
        void function( cef_browser_host_t*, cef_drag_data_t*, const( cef_mouse_event_t )*, cef_drag_operations_mask_t ) drag_target_drag_enter;
        void function( cef_browser_host_t*, const( cef_mouse_event_t )*, cef_drag_operations_mask_t ) drag_target_drag_over;
        void function( cef_browser_host_t* ) drag_target_drag_leave;
        void function( cef_browser_host_t*, const( cef_mouse_event_t )* ) drag_target_drop;
        void function( cef_browser_host_t*, int, int, cef_drag_operations_mask_t ) drag_source_ended_at;
        void function( cef_browser_host_t* ) drag_source_system_drag_ended;
        cef_navigation_entry_t* function( cef_browser_host_t* ) get_visible_navigation_entry;
        void function( cef_browser_host_t*, cef_state_t ) set_accessibility_state;
        void function( cef_browser_host_t*, int, const( cef_size_t )*, const( cef_size_t)* ) set_auto_resize_enabled;
        cef_extension_t* function( cef_browser_host_t* ) get_extension;
        int function( cef_browser_host_t* ) is_background_host;
    }
}

// cef_browser_process_handler_capi
struct cef_browser_process_handler_t  {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_browser_process_handler_t* ) on_context_initialized;
        void function( cef_browser_process_handler_t*,cef_command_line_t* ) on_before_child_process_launch;
        void function( cef_browser_process_handler_t*,cef_list_value_t* ) on_render_process_thread_created;
        cef_print_handler_t* function( cef_browser_process_handler_t* ) get_print_handler;
        void function( cef_browser_process_handler_t*, ulong ) on_schedule_message_pump_work;
    }
}

// cef_callback_capi.h
struct cef_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_callback_t* ) cont;
        void function( cef_callback_t* ) cancel;
    }
}

struct cef_completion_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_completion_callback_t* ) on_complete;
}

// cef_client_capi.h
struct cef_client_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_context_menu_handler_t* function( cef_client_t* ) get_context_menu_handler;
        cef_dialog_handler_t* function( cef_client_t* ) get_dialog_handler;
        cef_display_handler_t* function( cef_client_t* ) get_display_handler;
        cef_download_handler_t* function( cef_client_t* ) get_download_handler;
        cef_drag_handler_t* function( cef_client_t* ) get_drag_handler;
        cef_find_handler_t* function( cef_client_t* ) get_find_handler;
        cef_focus_handler_t* function( cef_client_t* ) get_focus_handler;
        cef_jsdialog_handler_t* function( cef_client_t* ) get_jsdialog_handler;
        cef_keyboard_handler_t* function( cef_client_t* ) get_keyboard_handler;
        cef_life_span_handler_t* function( cef_client_t* ) get_life_span_handler;
        cef_load_handler_t* function( cef_client_t* ) get_load_handler;
        cef_render_handler_t* function( cef_client_t* ) get_render_handler;
        cef_request_handler_t* function( cef_client_t*) get_request_handler;
        int function( cef_client_t*,cef_browser_t*,cef_process_id_t,cef_process_message_t* ) on_process_message_received;
    }
}

// cef_command_line_capi.h
struct cef_command_line_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_command_line_t* ) is_valid;
        int function( cef_command_line_t* ) is_read_only;
        cef_command_line_t* function( cef_command_line_t* ) copy;
        void function( cef_command_line_t*,int,const( char* )* ) init_from_argv;
        void function( cef_command_line_t*,const( cef_string_t )* ) init_from_string;
        void function( cef_command_line_t* ) reset;
        void function( cef_command_line_t*,cef_string_list_t ) get_argv;
        cef_string_userfree_t function( cef_command_line_t* ) get_command_line_string;
        cef_string_userfree_t function( cef_command_line_t* ) get_program;
        void function( cef_command_line_t*,const( cef_string_t )* ) set_program;
        int function( cef_command_line_t* ) has_switches;
        int function( cef_command_line_t*,const( cef_string_t )* ) has_switch;
        cef_string_userfree_t function( cef_command_line_t*,const( cef_string_t )* ) get_switch_value;
        void function( cef_command_line_t*,cef_string_map_t ) get_switches;
        void function( cef_command_line_t*,const( cef_string_t )* ) append_switch;
        void function( cef_command_line_t*,const( cef_string_t )*,const( cef_string_t )* ) append_switch_with_value;
        int function( cef_command_line_t* ) has_arguments;
        void function( cef_command_line_t*,cef_string_list_t ) get_arguments;
        void function( cef_command_line_t*,const( cef_string_t )* ) append_argument;
        void function( cef_command_line_t*,const( cef_string_t )* ) prepend_wrapper;
    }
}

// cef_context_menu_handler_capi.h
struct cef_run_context_menu_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_run_context_menu_callback_t*, int, cef_event_flags_t ) cont;
        void function( cef_run_context_menu_callback_t* ) cancel;
    }
}

struct cef_context_menu_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_context_menu_handler_t*,cef_browser_t*,cef_frame_t*,cef_context_menu_params_t*,cef_menu_model_t* ) on_before_context_menu;
        int function( cef_context_menu_handler_t*, cef_browser_t*, cef_frame_t*, cef_context_menu_params_t*, cef_menu_model_t*, cef_run_context_menu_callback_t* ) run_context_menu;
        int function( cef_context_menu_handler_t*,cef_browser_t*,cef_frame_t*,cef_context_menu_params_t*,int,cef_event_flags_t ) on_context_menu_command;
        int function( cef_context_menu_handler_t*,cef_browser_t*,cef_frame_t* ) on_context_menu_dismissed;
    }
}

struct cef_context_menu_params_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_context_menu_params_t* ) get_xcoord;
        int function( cef_context_menu_params_t* ) get_ycoord;
        cef_context_menu_type_flags_t function( cef_context_menu_params_t* ) get_type_flags;
        cef_string_userfree_t function( cef_context_menu_params_t* ) get_link_url;
        cef_string_userfree_t function( cef_context_menu_params_t* ) get_unfiltered_link_url;
        cef_string_userfree_t function( cef_context_menu_params_t* ) get_source_url;
        int function( cef_context_menu_params_t* ) has_image_contents;
        cef_string_userfree_t function( cef_context_menu_params_t* ) get_page_url;
        cef_string_userfree_t function( cef_context_menu_params_t* ) get_frame_url;
        cef_string_userfree_t function( cef_context_menu_params_t* ) get_frame_charset;
        cef_context_menu_media_type_t function( cef_context_menu_params_t* ) get_media_type;
        cef_context_menu_media_state_flags_t function( cef_context_menu_params_t* ) get_media_state_flags;
        cef_string_userfree_t function( cef_context_menu_params_t* ) get_selection_text;
        int function( cef_context_menu_params_t*) is_editable;
        int function( cef_context_menu_params_t* ) is_speech_input_enabled;
        cef_context_menu_edit_state_flags_t function( cef_context_menu_params_t* ) get_edit_state_flags;
    }
}

// cef_cookie_capi.h
struct cef_cookie_manager_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_cookie_manager_t*,cef_string_list_t ) set_supported_schemes;
        int function( cef_cookie_manager_t*,cef_cookie_visitor_t* ) visit_all_cookies;
        int function( cef_cookie_manager_t*,cef_cookie_visitor_t* ) visit_url_cookies;
        int function( cef_cookie_manager_t*,const( cef_string_t )*,const( cef_cookie_t )* ) set_cookie;
        int function( cef_cookie_manager_t*,const( cef_string_t )*,const( cef_string_t )* ) delete_cookie;
        int function( cef_cookie_manager_t*,const( cef_string_t )*,int ) set_storage_path;
        int function( cef_cookie_manager_t*,cef_completion_callback_t* ) flush_store;
    }
}

struct cef_cookie_visitor_t {
    cef_base_t base;
    extern( System ) @nogc nothrow int function( cef_cookie_visitor_t*,const( cef_cookie_t )*,int,int,int* ) visit;
}

// cef_dialog_handler_capi.h
struct cef_file_dialog_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_file_dialog_callback_t*,cef_string_list_t ) cont;
        void function( cef_file_dialog_callback_t* ) cancel;
    }
}

struct cef_dialog_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow int function( cef_dialog_handler_t*,cef_browser_t*,cef_file_dialog_mode_t,const( cef_string_t )*,const( cef_string_t )*,cef_string_list_t,cef_file_dialog_callback_t* ) on_file_dialog;
}

// cef_display_handler_capi.h
struct cef_display_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_display_handler_t*,cef_browser_t*,cef_frame_t*,const( cef_string_t )* ) on_address_change;
        void function( cef_display_handler_t*,cef_browser_t*,const( cef_string_t )* ) on_title_change;
        void function( cef_display_handler_t*, cef_browser_t*, cef_string_list_t ) on_favicon_urlchange;
        void function( cef_display_handler_t*, cef_browser_t* , int ) on_fullscreen_mode_change;
        int function( cef_display_handler_t*, cef_browser_t,cef_string_t* ) on_tooltip;
        void function( cef_display_handler_t*,cef_browser_t*,const( cef_string_t )* ) on_status_message;
        int function( cef_display_handler_t*,cef_browser_t*,const( cef_string_t )*,const( cef_string_t )*,int ) on_console_message;
        int function( cef_display_handler_t*, cef_browser_t*, const( cef_size_t )* ) on_auto_resize;
        void function( cef_display_handler_t*, cef_browser_t*, double ) on_loading_progress_change;
    }
}

// cef_dom_capi.h
struct cef_domvisitor_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_domvisitor_t*,cef_domdocument_t* ) visit;
}
struct cef_domdocument_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_dom_document_type_t function( cef_domdocument_t* ) get_type;
        cef_domnode_t* function( cef_domdocument_t* ) get_document;
        cef_domnode_t* function( cef_domdocument_t* ) get_body;
        cef_domnode_t* function( cef_domdocument_t* ) get_head;
        cef_string_userfree_t function( cef_domdocument_t* ) get_title;
        cef_domnode_t* function( cef_domdocument_t*,const( cef_string_t )* ) get_element_by_id;
        cef_domnode_t* function( cef_domdocument_t* ) get_focused_node;
        int function( cef_domdocument_t* ) has_selection;
        int function( cef_domdocument_t* ) get_selection_start_offset;
        int function( cef_domdocument_t* ) get_selection_end_offset;
        cef_string_userfree_t function( cef_domdocument_t* ) get_selection_as_markup;
        cef_string_userfree_t function( cef_domdocument_t* ) get_selection_as_text;
        cef_string_userfree_t function( cef_domdocument_t* ) get_base_url;
        cef_string_userfree_t function( cef_domdocument_t*,const( cef_string_t )* ) get_complete_url;
    }
}

struct cef_domnode_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_dom_node_type_t function( cef_domnode_t* ) get_type;
        int function( cef_domnode_t* ) is_text;
        int function( cef_domnode_t* ) is_element;
        int function( cef_domnode_t* ) is_editable;
        int function( cef_domnode_t* ) is_form_control_element;
        cef_string_userfree_t function( cef_domnode_t* ) get_form_control_element_type;
        int function( cef_domnode_t*,cef_domnode_t* ) is_same;
        cef_string_userfree_t function( cef_domnode_t* ) get_name;
        cef_string_userfree_t function( cef_domnode_t* ) get_value;
        int function( cef_domnode_t*,const( cef_string_t )* ) set_value;
        cef_string_userfree_t function( cef_domnode_t* ) get_as_markup;
        cef_domdocument_t* function( cef_domnode_t* ) get_document;
        cef_domnode_t* function( cef_domnode_t* ) get_parent;
        cef_domnode_t* function( cef_domnode_t* ) get_previous_sibling;
        cef_domnode_t* function( cef_domnode_t* ) get_next_sibling;
        int function( cef_domnode_t* ) has_children;
        cef_domnode_t* function( cef_domnode_t* ) get_first_child;
        cef_domnode_t* function( cef_domnode_t* ) get_last_child;
        cef_string_userfree_t function( cef_domnode_t* ) get_element_tag_name;
        int function( cef_domnode_t* ) has_element_attributes;
        int function( cef_domnode_t*,const( cef_string_t )* ) has_element_attribute;
        cef_string_userfree_t function( cef_domnode_t*,const( cef_string_t )* ) get_element_attribute;
        void function( cef_domnode_t*,cef_string_map_t ) get_element_attributes;
        int function( cef_domnode_t* ,const( cef_string_t )*,const( cef_string_t )* ) set_element_attribute;
        cef_string_userfree_t function( cef_domnode_t* ) get_element_inner_text;
        cef_rect_t function( cef_domnode_t* ) get_element_bounds;
    }
}

struct cef_domevent_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_string_userfree_t function( cef_domevent_t* ) get_type;
        cef_dom_event_category_t function( cef_domevent_t* ) get_category;
        cef_dom_event_phase_t function( cef_domevent_t* ) get_phase;
        int function( cef_domevent_t* ) can_bubble;
        int function( cef_domevent_t* ) can_cancel;
        cef_domdocument_t* function( cef_domevent_t* ) get_document;
        cef_domnode_t* function( cef_domevent_t* ) get_target;
        cef_domnode_t* function( cef_domevent_t* ) get_current_target;
    }
}

struct cef_domevent_listener_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_domevent_listener_t*,cef_domevent_t* ) handle_event;
}

// cef_download_handler_capi.h
struct cef_before_download_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_before_download_callback_t,const( cef_string_t )*,int ) cont;
}

struct cef_download_item_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_download_item_callback_t* ) cancel;
        void function( cef_download_item_callback_t* ) pause;
        void function( cef_download_item_callback_t* ) resume;
    }
}

struct cef_download_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_download_handler_t*,cef_browser_t*,cef_download_item_t*,const( cef_string_t )*,cef_before_download_callback_t* ) on_before_download;
        void function( cef_download_handler_t*,cef_browser_t*,cef_download_item_t*,cef_download_item_callback_t* ) on_download_updated;
    }
}

// cef_download_item_capi.h
struct cef_download_item_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_download_item_t* ) is_valid;
        int function( cef_download_item_t* ) is_in_progress;
        int function( cef_download_item_t* ) is_complete;
        int function( cef_download_item_t* ) is_canceled;
        int64 function( cef_download_item_t* ) get_current_speed;
        int function( cef_download_item_t* ) get_percent_complete;
        int64 function( cef_download_item_t* ) get_total_bytes;
        int64 function( cef_download_item_t* ) get_received_bytes;
        cef_time_t function( cef_download_item_t* ) get_start_time;
        cef_time_t function( cef_download_item_t* ) get_end_time;
        cef_string_userfree_t function( cef_download_item_t* ) get_full_path;
        uint32 function( cef_download_item_t* ) get_id;
        cef_string_userfree_t function( cef_download_item_t* ) get_url;
        cef_string_userfree_t function( cef_download_item_t* ) get_suggested_file_name;
        cef_string_userfree_t function( cef_download_item_t* ) get_content_disposition;
        cef_string_userfree_t function( cef_download_item_t* ) get_mime_type;
    }
}

// cef_drag_data_capi.h
struct cef_drag_data_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_drag_data_t* function( cef_drag_data_t* ) clone;
        int function( cef_drag_data_t* ) is_read_only;
        int function( cef_drag_data_t* ) is_link;
        int function( cef_drag_data_t* ) is_fragment;
        int function( cef_drag_data_t* ) is_file;
        int function( cef_drag_data_t* ) get_link_url;
        cef_string_userfree_t function( cef_drag_data_t* ) get_link_title;
        cef_string_userfree_t function( cef_drag_data_t* ) get_link_metadata;
        cef_string_userfree_t function( cef_drag_data_t* ) get_fragment_text;
        cef_string_userfree_t function( cef_drag_data_t* ) get_fragment_html;
        cef_string_userfree_t function( cef_drag_data_t* ) get_fragment_base_url;
        cef_string_userfree_t function( cef_drag_data_t* ) get_file_name;
        size_t function( cef_drag_data_t*, cef_stream_writer_t* ) get_file_contents;
        int function( cef_drag_data_t*, cef_string_list_t ) get_file_names;
        void function( cef_drag_data_t*, const( cef_string_t )* ) set_link_url;
        void function( cef_drag_data_t*, const( cef_string_t )* ) set_link_title;
        void function( cef_drag_data_t*, const( cef_string_t )* ) set_link_metadata;
        void function( cef_drag_data_t*, const( cef_string_t )* ) set_fragment_text;
        void function( cef_drag_data_t*, const( cef_string_t )* ) set_fragment_html;
        void function( cef_drag_data_t*, const( cef_string_t )* ) set_fragment_base_url;
        void function( cef_drag_data_t* ) reset_file_contents;
        void function( cef_drag_data_t*, const( cef_string_t )*, const( cef_string_t )* ) add_file;
        cef_image_t* function( cef_drag_data_t* ) get_image;
        cef_point_t function( cef_drag_data_t* ) get_image_hotspot;
        int function( cef_drag_data_t* ) has_image;
    }
}

// cef_drag_handler_capi.h
struct cef_drag_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_drag_handler_t*,cef_browser_t*,cef_drag_data_t*,cef_drag_operations_mask_t ) on_drag_enter;
        void function( cef_drag_handler_t*, cef_browser_t*, size_t, const( cef_draggable_region_t*) ) on_draggable_regions_changed;
    }
}

// cef_extension_capi.h
struct cef_extension_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_string_userfree_t function( cef_extension_t* ) get_identifier;
        cef_string_userfree_t function( cef_extension_t* ) get_path;
        cef_dictionary_value_t* function( cef_extension_t* ) get_manifest;
        int function( cef_extension_t*, cef_extension_t* ) is_same;
        cef_extension_handler_t* function( cef_extension_t* ) get_handler;
        cef_request_context_t* function( cef_extension_t* ) get_loader_context;
        int function( cef_extension_t* ) is_loaded;
        void function( cef_extension_t* ) unload;
    }
}

// cef_extension_handler_capi.h
struct cef_get_extension_resource_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_get_extension_resource_callback_t*, cef_stream_reader_t* ) cont;
        void function( cef_get_extension_resource_callback_t* ) cancel;
    }
}

struct cef_extension_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_extension_handler_t*, cef_errorcode_t ) on_extension_load_failed;
        void function( cef_extension_handler_t*, cef_extension_t* ) on_extension_loaded;
        void function( cef_extension_handler_t*, cef_extension_t* ) on_extension_unloaded;
        int function( cef_extension_handler_t*, cef_extension_t*, const( cef_string_t )*, cef_client_t**, cef_browser_settings_t* ) on_before_background_browser;
        int function( cef_extension_handler_t*, cef_extension_t*, cef_browser_t*, cef_browser_t*, int, const( cef_string_t )*, int, cef_window_info_t*, cef_client_t**, cef_browser_settings_t* ) on_before_browser;
        cef_browser_t* function( cef_extension_handler_t*, cef_extension_t*, cef_browser_t*, int ) get_active_browser;
        int function( cef_extension_handler_t*, cef_extension_t*, cef_browser_t*, int, cef_browser_t* ) can_access_browser;
        int function( cef_extension_handler_t*, cef_extension_t*, cef_browser_t*, const( cef_string_t )*, cef_get_extension_resource_callback_t* ) get_extension_resource;
    }
}

// cef_find_handler_capi.h
struct cef_find_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_find_handler_t*, cef_browser_t*, int, int, const( cef_rect_t )*, int, int ) on_find_result;
}

// cef_focus_handler_capi.h
struct cef_focus_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_focus_handler_t*,cef_browser_t*,int ) on_take_focus;
        int function( cef_focus_handler_t*,cef_browser_t*,cef_focus_source_t* ) on_set_focus;
        void function( cef_focus_handler_t*,cef_browser_t* ) on_get_focus;
    }
}

// cef_frame_capi.h
struct cef_frame_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_frame_t* ) is_valid;
        void function( cef_frame_t* ) undo;
        void function( cef_frame_t* ) redo;
        void function( cef_frame_t* ) cut;
        void function( cef_frame_t* ) copy;
        void function( cef_frame_t* ) paste;
        void function( cef_frame_t* ) del;
        void function( cef_frame_t*cef_drag_handler_t ) select_all;
        void function( cef_frame_t* ) view_source;
        void function( cef_frame_t*,cef_string_visitor_t* ) get_source;
        void function( cef_frame_t*,cef_string_visitor_t* ) get_text;
        void function( cef_frame_t*,cef_request_t* ) load_request;
        void function( cef_frame_t*,const( cef_string_t )* ) load_url;
        void function( cef_frame_t*,const( cef_string_t )*,const( cef_string_t )* ) load_string;
        void function( cef_frame_t*,const( cef_string_t )*,const( cef_string_t )*,int ) execute_java_script;
        int function( cef_frame_t* ) is_main;
        int function( cef_frame_t* ) is_focused;
        cef_string_userfree_t function( cef_frame_t* ) get_name;
        int64 function( cef_frame_t* ) get_identifier;
        cef_frame_t* function( cef_frame_t* ) get_parent;
        cef_string_userfree_t function( cef_frame_t* ) get_url;
        cef_browser_t* function( cef_frame_t* ) get_browser;
        cef_v8context_t* function( cef_frame_t* ) get_v8context;
        void function( cef_frame_t*,cef_domvisitor_t* ) visit_dom;

    }
}

// cef_image_capi.h
struct cef_image_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_image_t* ) is_empty;
        int function( cef_image_t*, cef_image_t* ) is_same;
        int function( cef_image_t*, float, int, int, cef_color_type_t, cef_alpha_type_t, const( void )*, size_t ) add_bitmap;
        int function( cef_image_t*, float, const( void )*, size_t ) add_png;
        int function( cef_image_t*, float, const( void )*, size_t ) add_jpeg;
        size_t function( cef_image_t* ) get_width;
        size_t function( cef_image_t* ) get_height;
        int function( cef_image_t*, float ) has_representation;
        int function( cef_image_t*, float ) remove_representation;
        int function( cef_image_t*, float, float*, int*, int* ) get_representation_info;
        cef_binary_value_t* function( cef_image_t*, float, cef_color_type_t, cef_alpha_type_t, int*, int* ) get_as_bitmap;
        cef_binary_value_t* function( cef_image_t*, float, int, int*, int* ) get_as_png;
        cef_binary_value_t* function( cef_image_t*, float, int, int*, int* ) get_as_jpeg;
    }
};

// cef_jsdialog_handler_capi.h
struct cef_jsdialog_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_jsdialog_callback_t*,int,const( cef_string_t )* ) cont;
}

struct cef_jsdialog_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_jsdialog_handler_t*,cef_browser_t*,const( cef_string_t )*,const( cef_string_t )*,cef_jsdialog_type_t,const( cef_string_t )*,cef_jsdialog_callback_t*,int* ) on_jsdialog;
        int function( cef_jsdialog_handler_t*,cef_browser_t*,const( cef_string_t )*,int,cef_jsdialog_callback_t* ) on_before_unload_dialog;
        void function( cef_jsdialog_handler_t*,cef_browser_t* ) on_reset_dialog_state;
        void function( cef_jsdialog_handler_t*,cef_browser_t* ) on_dialog_closed;
    }
}

// cef_keyboard_handler_capi.h
struct cef_keyboard_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_keyboard_handler_t*,cef_browser_t*,const( cef_key_event_t )*,cef_event_handle_t,int* ) on_pre_key_event;
        int function( cef_keyboard_handler_t*,cef_browser_t*,const( cef_key_event_t )*,cef_event_handle_t ) on_key_event;
    }
}

// cef_life_span_handler_capi.h
struct cef_life_span_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_life_span_handler_t*,cef_browser_t*,cef_frame_t*,const( cef_string_t )*,const( cef_string_t )*,const( cef_popup_features_t )*,cef_window_info_t*,cef_client_t**,cef_browser_settings_t*,int* ) on_before_popup;
        void function( cef_life_span_handler_t*,cef_browser_t* ) on_after_created;
        void function( cef_life_span_handler_t*,cef_browser_t* ) run_modal;
        int function( cef_life_span_handler_t*,cef_browser_t* ) do_close;
        void function( cef_life_span_handler_t*,cef_browser_t* ) on_before_close;
    }
}

// cef_load_handler_capi.h
struct cef_load_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_load_handler_t*,cef_browser_t*,int,int,int ) on_loading_state_change;
        void function( cef_load_handler_t*,cef_browser_t*,cef_frame_t* ) on_load_start;
        void function( cef_load_handler_t*,cef_browser_t*,cef_frame_t*,int ) on_load_end;
        void function( cef_load_handler_t*,cef_browser_t*,cef_frame_t*,cef_errorcode_t,const( cef_string_t )*,const( cef_string_t )* ) on_load_error;
    }
}

// cef_menu_model_capi.h
struct cef_menu_model_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_menu_model_t* ) is_sub_menu;
        int function( cef_menu_model_t* ) clear;
        int function( cef_menu_model_t* ) get_count;
        int function( cef_menu_model_t* ) add_separator;
        int function( cef_menu_model_t*,int,const( cef_string_t )* ) add_item;
        int function( cef_menu_model_t*,int,const( cef_string_t )* ) add_check_item;
        int function( cef_menu_model_t*,int,const( cef_string_t )*,int ) add_radio_item;
        cef_menu_model_t* function( cef_menu_model_t*,int,const( cef_string_t )* ) add_sub_menu;
        int function( cef_menu_model_t*,int ) insert_separator_at;
        int function( cef_menu_model_t*,int,int,const( cef_string_t )* ) insert_item_at;
        int function( cef_menu_model_t*,int,int,const( cef_string_t )* ) insert_check_item_at;
        int function( cef_menu_model_t*,int,int,const( cef_string_t )*,int ) insert_radio_item_at;
        cef_menu_model_t* function( cef_menu_model_t*,int,int,const( cef_string_t )* ) insert_submenu_at;
        int function( cef_menu_model_t*,int ) remove;
        int function( cef_menu_model_t*,int ) remove_at;
        int function( cef_menu_model_t*,int ) get_index_of;
        int function( cef_menu_model_t*,int ) get_command_id_at;
        int function( cef_menu_model_t*,int,int ) set_command_id_at;
        cef_string_userfree_t function( cef_menu_model_t*,int ) get_label;
        cef_string_userfree_t function( cef_menu_model_t*,int ) get_label_at;
        int function( cef_menu_model_t*,int,const( cef_string_t )* ) set_label;
        int function( cef_menu_model_t*,int,const( cef_string_t )* ) set_label_at;
        cef_menu_item_type_t function( cef_menu_model_t*,int ) get_type;
        cef_menu_item_type_t function( cef_menu_model_t*,int ) get_type_at;
        int function( cef_menu_model_t*,int ) get_group_id;
        int function( cef_menu_model_t*,int ) get_group_id_at;
        int function( cef_menu_model_t*,int,int ) set_group_id;
        int function( cef_menu_model_t*,int,int ) set_group_id_at;
        cef_menu_model_t* function( cef_menu_model_t*,int ) get_sub_menu;
        cef_menu_model_t* function( cef_menu_model_t*,int ) get_sub_menu_at;
        int function( cef_menu_model_t*,int ) is_visible;
        int function( cef_menu_model_t*,int ) is_visible_at;
        int function( cef_menu_model_t*,int,int ) set_visible;
        int function( cef_menu_model_t*,int,int ) set_visible_at;
        int function( cef_menu_model_t*,int ) is_enabled;
        int function( cef_menu_model_t*,int ) is_enabled_at;
        int function( cef_menu_model_t*,int,int ) set_enabled;
        int function( cef_menu_model_t*,int,int ) set_enabled_at;
        int function( cef_menu_model_t*,int ) is_checked;
        int function( cef_menu_model_t*,int ) is_checked_at;
        int function( cef_menu_model_t*,int,int ) set_checked;
        int function( cef_menu_model_t*,int,int ) set_checked_at;
        int function( cef_menu_model_t*,int ) has_accelerator;
        int function( cef_menu_model_t*,int ) has_accelerator_at;
        int function( cef_menu_model_t*,int,int,int,int,int ) set_accelerator;
        int function( cef_menu_model_t*,int,int,int,int,int ) set_accelerator_at;
        int function( cef_menu_model_t*,int ) remove_accelerator;
        int function( cef_menu_model_t*,int ) remove_accelerator_at;
        int function( cef_menu_model_t*,int,int*,int*,int*,int* ) get_accelerator;
        int function( cef_menu_model_t*,int,int*,int*,int*,int* ) get_accelerator_at;
        int function( cef_menu_model_t*, int, cef_menu_color_type_t, cef_color_t ) set_color;
        int function( cef_menu_model_t*, int, cef_menu_color_type_t, cef_color_t ) set_color_at;
        int function( cef_menu_model_t*, int, cef_menu_color_type_t, cef_color_t* ) get_color;
        int function( cef_menu_model_t*, int, cef_menu_color_type_t, cef_color_t* ) get_color_at;
        int function( cef_menu_model_t*, int, const( cef_string_t )* ) set_font_list;
        int function( cef_menu_model_t*, int, const( cef_string_t )* ) set_font_list_at;
    }
}

// cef_menu_model_delegate_capi.h
struct cef_menu_model_delegate_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_menu_model_delegate_t*, cef_menu_model_t*, int, cef_event_flags_t ) execute_command;
        void function( cef_menu_model_delegate_t*, cef_menu_model_t*, const( cef_point_t)* ) mouse_outside_menu;
        void function( cef_menu_model_delegate_t*, cef_menu_model_t*, int ) unhandled_open_submenu;
        void function( cef_menu_model_delegate_t*, cef_menu_model_t*, int ) unhandled_close_submenu;
        void function( cef_menu_model_delegate_t*, cef_menu_model_t* ) menu_will_show;
        void function( cef_menu_model_delegate_t*, cef_menu_model_t* ) menu_closed;
        int function( cef_menu_model_delegate_t*, cef_menu_model_t*, cef_string_t* ) format_label;
    }
}

// cef_navigation_entry_capi.h
struct cef_navigation_entry_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_navigation_entry_t* self) is_valid;
        cef_string_userfree_t function( cef_navigation_entry_t* ) get_url;
        cef_string_userfree_t function( cef_navigation_entry_t* ) get_display_url;
        cef_string_userfree_t function( cef_navigation_entry_t* ) get_original_url;
        cef_string_userfree_t function( cef_navigation_entry_t* ) get_title;
        cef_transition_type_t function( cef_navigation_entry_t* ) get_transition_type;
        int function( cef_navigation_entry_t* ) has_post_data;
        cef_time_t function( cef_navigation_entry_t* ) get_completion_time;
        int function( cef_navigation_entry_t* ) get_http_status_code;
        cef_sslstatus_t* function( cef_navigation_entry_t* ) get_sslstatus;
    }
}

// cef_print_handler_capi.h
struct cef_print_dialog_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_print_dialog_callback_t*, cef_print_settings_t* ) cont;
        void function( cef_print_dialog_callback_t* ) cancel;
    }
} 

struct cef_print_job_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_print_job_callback_t* ) cont;
}

struct cef_print_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_print_handler_t*, cef_browser_t* ) on_print_start;
        void function( cef_print_handler_t*, cef_browser_t*, cef_print_settings_t*, int ) on_print_settings;
        int function( cef_print_handler_t*, cef_browser_t*, int, cef_print_dialog_callback_t* ) on_print_dialog;
        int function( cef_print_handler_t*, cef_browser_t*, const( cef_string_t )*, const( cef_string_t )* , cef_print_job_callback_t* ) on_print_job;
        void function( cef_print_handler_t*, cef_browser_t* ) on_print_reset;
        cef_size_t function( cef_print_handler_t*, int ) get_pdf_paper_size;
    }
}

// cef_print_settings_capi.h
struct cef_print_settings_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_print_settings_t* ) is_valid;
        int function( cef_print_settings_t* ) is_read_only;
        cef_print_settings_t* function(  cef_print_settings_t* ) copy;
        void function( cef_print_settings_t*, int ) set_orientation;
        int function( cef_print_settings_t* ) is_landscape;
        void function( cef_print_settings_t*, const( cef_size_t )*, const( cef_rect_t )* , int ) set_printer_printable_area;
        void function( cef_print_settings_t*, const( cef_string_t )* ) set_device_name;
        cef_string_userfree_t function( cef_print_settings_t* ) get_device_name;
        void function( cef_print_settings_t*, int ) set_dpi;
        int function( cef_print_settings_t* ) get_dpi;
        void function( cef_print_settings_t*, size_t, const( cef_range_t )* ) set_page_ranges;
        size_t function( cef_print_settings_t* ) get_page_ranges_count;
        void function( cef_print_settings_t*, size_t*, cef_range_t* ) get_page_ranges;
        void function( cef_print_settings_t*, int ) set_selection_only;
        int function( cef_print_settings_t* ) is_selection_only;
        void function( cef_print_settings_t*, int ) set_collate;
        int function( cef_print_settings_t* ) will_collate;
        void function( cef_print_settings_t*, cef_color_model_t ) set_color_model;
        cef_color_model_t function( cef_print_settings_t* ) get_color_model;
        void function( cef_print_settings_t*, int ) set_copies;
        int function( cef_print_settings_t* ) get_copies;
        void function( cef_print_settings_t*, cef_duplex_mode_t mode ) set_duplex_mode;
        cef_duplex_mode_t function( cef_print_settings_t* ) get_duplex_mode;
    }
}

// cef_process_message_capi.h
struct cef_process_message_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_process_message_t* ) is_valid;
        int function( cef_process_message_t* ) is_read_only;
        cef_process_message_t* function( cef_process_message_t* ) copy;
        cef_string_userfree_t function( cef_process_message_t* ) get_name;
        cef_list_value_t* function( cef_process_message_t* ) get_argument_list;
    }
}

// cef_render_handler_capi.h
struct cef_render_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_accessibility_handler_t* function( cef_render_handler_t* ) get_accessibility_handler;
        int function( cef_render_handler_t*,cef_browser_t*,cef_rect_t* ) get_root_screen_rect;
        int function( cef_render_handler_t*,cef_browser_t*,cef_rect_t* ) get_view_rect;
        int function( cef_render_handler_t*,cef_browser_t*,int,int,int*,int* ) get_screen_point;
        int function( cef_render_handler_t*,cef_browser_t*,cef_screen_info_t* ) get_screen_info;
        void function( cef_render_handler_t*,cef_browser_t*,int ) on_popup_show;
        void function( cef_render_handler_t*,cef_browser_t*,const( cef_rect_t )* ) on_popup_size;
        void function( cef_render_handler_t*,cef_browser_t*,cef_paint_element_type_t,size_t,const( cef_rect_t* ),const( void )*,int,int ) on_paint;
        void function( cef_render_handler_t*, cef_browser_t*, cef_paint_element_type_t, size_t , const( cef_rect_t* ), void* ) on_accelerated_paint;
        void function( cef_render_handler_t*,cef_browser_t*,cef_cursor_handle_t ) on_cursor_change;
        int function( cef_render_handler_t*, cef_browser_t*, cef_drag_data_t*, cef_drag_operations_mask_t, int, int ) start_dragging;
        void function( cef_render_handler_t*, cef_browser_t*, cef_drag_operations_mask_t ) update_drag_cursor;
        void function( cef_render_handler_t*, cef_browser_t*, double, double ) on_scroll_offset_changed;
        void function( cef_render_handler_t*, cef_browser_t*, const( cef_range_t )*, size_t, const( cef_rect_t* ) ) on_ime_composition_range_changed;
        void function( cef_render_handler_t*, cef_browser_t*, const( cef_string_t )*, const( cef_range_t )* ) on_text_selection_changed;
    }
}

// cef_render_process_handler_capi.h
struct cef_render_process_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_render_process_handler_t*,cef_list_value_t* ) on_render_thread_created;
        void function( cef_render_process_handler_t* ) on_web_kit_initialized;
        void function( cef_render_process_handler_t*,cef_browser_t* ) on_browser_created;
        void function( cef_render_process_handler_t*,cef_browser_t* ) on_browser_destroyed;
        cef_load_handler_t* function( cef_render_process_handler_t* ) get_load_handler;
        int function( cef_render_process_handler_t*,cef_browser_t*,cef_frame_t*,cef_request_t*,cef_navigation_type_t,int ) on_before_navigation;
        void function( cef_render_process_handler_t*,cef_browser_t*,cef_frame_t*,cef_v8context_t* ) on_context_created;
        void function( cef_render_process_handler_t*,cef_browser_t*,cef_frame_t*,cef_v8context_t* ) on_context_released;
        void function( cef_render_process_handler_t*,cef_browser_t*,cef_frame_t*,cef_v8context_t*,cef_v8exception_t*,cef_v8stack_trace_t* ) on_uncaught_exception;
        void function( cef_render_process_handler_t*,cef_browser_t*,cef_frame_t*,cef_domnode_t* ) on_focused_node_changed;
        int function( cef_render_process_handler_t*,cef_browser_t*,cef_process_id_t,cef_process_message_t* ) on_process_message_received;
    }
}

// cef_request_capi.h
struct cef_request_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_request_t* ) is_read_only;
        cef_string_userfree_t function( cef_request_t* ) get_url;
        void function( cef_request_t*,const( cef_string_t )* ) set_url;
        cef_string_userfree_t function( cef_request_t* ) get_method;
        void function( cef_request_t*,const( cef_string_t )* ) set_method;
        void function( cef_request_t*, const( cef_string_t )*, cef_referrer_policy_t ) set_referrer;
        cef_string_userfree_t function( cef_request_t* ) get_referrer_url;
        cef_referrer_policy_t function( cef_request_t* ) get_referrer_policy;
        cef_post_data_t* function( cef_request_t* ) get_post_data;
        void function( cef_request_t*, cef_post_data_t* ) set_post_data;
        void function( cef_request_t*,cef_string_multimap_t ) get_header_map;
        void function( cef_request_t*,cef_string_multimap_t ) set_header_map;
        void function( cef_request_t*,const( cef_string_t )*,const( cef_string_t )*,cef_post_data_t*,cef_string_multimap_t ) set;
        int function( cef_request_t* ) get_flags;
        void function( cef_request_t*,int ) set_flags;
        cef_string_userfree_t function( cef_request_t* ) get_first_party_for_cookies;
        void function( cef_request_t*,const( cef_string_t )* ) set_first_party_for_cookies;
        cef_resource_type_t function( cef_request_t* ) get_resource_type;
        cef_transition_type_t function( cef_request_t* ) get_transition_type;
        ulong function( cef_request_t* ) get_identifier;
    }
}

struct cef_post_data_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_post_data_t* ) is_read_only;
        int function( cef_post_data_t* ) has_excluded_elements;
        size_t function( cef_post_data_t* ) get_element_count;
        void function( cef_post_data_t*,size_t*,cef_post_data_element_t** ) get_elements;
        int function( cef_post_data_t*,cef_post_data_element_t* ) remove_element;
        int function( cef_post_data_t*,cef_post_data_element_t* ) add_element;
        void function( cef_post_data_t* ) remove_elements;
    }
}

struct cef_post_data_element_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_post_data_element_t* ) is_read_only;
        void function( cef_post_data_element_t* ) set_to_empty;
        void function( cef_post_data_element_t*,const( cef_string_t )* ) set_to_file;
        void function( cef_post_data_element_t*,size_t,const( void )* ) set_to_bytes;
        cef_postdataelement_type_t function( cef_post_data_element_t* ) get_type;
        cef_string_userfree_t function( cef_post_data_element_t* ) get_file;
        size_t function( cef_post_data_element_t* ) get_bytes_count;
        size_t function( cef_post_data_element_t*,size_t,void* ) get_bytes;
    }
}

// cef_request_context_capi.h
struct cef_resolve_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_resolve_callback_t*, cef_errorcode_t, cef_string_list_t ) on_resolve_completed;
}

struct cef_request_context_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_request_context_t* self, cef_request_context_t* ) is_same;
        int function( cef_request_context_t*, cef_request_context_t* ) is_sharing_with;
        int function( cef_request_context_t* ) is_global;
        cef_request_context_handler_t* function( cef_request_context_t* ) get_handler;
        cef_string_userfree_t function( cef_request_context_t* ) get_cache_path;
        cef_cookie_manager_t* function( cef_request_context_t*, cef_completion_callback_t* ) get_default_cookie_manager;
        int function( cef_request_context_t*, const( cef_string_t )*, const( cef_string_t )*, cef_scheme_handler_factory_t* ) register_scheme_handler_factory;
        int function( cef_request_context_t* ) clear_scheme_handler_factories;
        void function( cef_request_context_t*, int ) purge_plugin_list_cache;
        int function( cef_request_context_t*, const( cef_string_t )* name) has_preference;
        cef_value_t* function( cef_request_context_t*, cef_string_t* ) get_preference;
        cef_dictionary_value_t* function( cef_request_context_t*, int ) get_all_preferences;
        int function( cef_request_context_t*, const( cef_string_t )* ) can_set_preference;
        int function( cef_request_context_t*, const( cef_string_t )*, cef_value_t*, cef_string_t* ) set_preference;
        void function( cef_request_context_t*, cef_completion_callback_t* ) clear_certificate_exceptions;
        void function( cef_request_context_t*, cef_completion_callback_t* ) close_all_connections;
        void function( cef_request_context_t*, const( cef_string_t )*, cef_resolve_callback_t* ) resolve_host;
        cef_errorcode_t function( cef_request_context_t*, const( cef_string_t )*, cef_string_list_t ) resolve_host_cached;
        void function( cef_request_context_t*, const( cef_string_t )*, cef_dictionary_value_t*, cef_extension_handler_t* ) load_extension;
        int function( cef_request_context_t*, const( cef_string_t )* ) did_load_extension;
        int function( cef_request_context_t*, const( cef_string_t )* ) has_extension;
        int function( cef_request_context_t*, cef_string_list_t ) get_extensions;
        cef_extension_t* function( cef_request_context_t*, const( cef_string_t )* ) get_extension;
    }
}

// cef_request_context_handler_capi.h
struct cef_request_context_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_request_context_handler_t*, cef_request_context_t* ) on_request_context_initialized;
        cef_cookie_manager_t* function( cef_request_context_handler_t* ) get_cookie_manager;
        int function( cef_request_context_handler_t*, const( cef_string_t )*, const( cef_string_t )*, int, const( cef_string_t )*, cef_web_plugin_info_t*, cef_plugin_policy_t* ) on_before_plugin_load;
    }
}

// cef_request_handler_capi.h
struct cef_request_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_request_callback_t*,int ) cont;
        void function( cef_request_callback_t* ) cancel;
    }
}

struct cef_select_client_certificate_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_select_client_certificate_callback_t*, cef_x509certificate_t* ) select;
}

struct cef_request_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_request_handler_t*,cef_browser_t*,cef_frame_t*,cef_request_t*,int ) on_before_browse;
        int function( cef_request_handler_t*, cef_browser_t*, cef_frame_t*, const( cef_string_t )*, cef_window_open_disposition_t, int ) on_open_urlfrom_tab;
        int function( cef_request_handler_t*,cef_browser_t*,cef_frame_t*,cef_request_t* ) on_before_resource_load;
        cef_resource_handler_t* function( cef_request_handler_t*,cef_browser_t*,cef_frame_t*,cef_request_t* ) get_resource_handler;
        void function( cef_request_handler_t*,cef_browser_t*,cef_frame_t*,const( cef_string_t )*,cef_string_t* ) on_resource_redirect;
        int function( cef_request_handler_t*, cef_browser_t*, cef_frame_t*, cef_request_t*, cef_response_t* ) on_resource_response;
        cef_response_filter_t* function( cef_request_handler_t*, cef_browser_t*, cef_frame_t*, cef_request_t*, cef_response_t* ) get_resource_response_filter;
        void function( cef_request_handler_t*, cef_browser_t*, cef_frame_t*, cef_request_t*, cef_response_t*, cef_urlrequest_status_t, ulong ) on_resource_load_complete;
        int function( cef_request_handler_t*,cef_browser_t*,cef_frame_t*,int,const( cef_string_t )*,int,const( cef_string_t )*,const( cef_string_t )*,cef_auth_callback_t* ) get_auth_credentials;
        int function( cef_request_handler_t*, cef_browser_t*, cef_frame_t*, cef_request_t* ) can_get_cookies;
        int function( cef_request_handler_t*, cef_browser_t*, cef_frame_t*, cef_request_t*, const( cef_cookie_t )* ) can_set_cookie;
        int function( cef_request_handler_t*, cef_browser_t*, const( cef_string_t )*, ulong, cef_request_callback_t* ) on_quota_request;
        void function( cef_request_handler_t*, cef_browser_t*, const( cef_string_t )*, int* ) on_protocol_execution;
        int function( cef_request_handler_t*, cef_browser_t*, cef_errorcode_t, const( cef_string_t )*, cef_sslinfo_t*, cef_request_callback_t* ) on_certificate_error;
        int function( cef_request_handler_t*, cef_browser_t*, int, const( cef_string_t )*, int, size_t, const( cef_x509certificate_t*), cef_select_client_certificate_callback_t* ) on_select_client_certificate;
        void function( cef_request_handler_t*, cef_browser_t*, const( cef_string_t )* ) on_plugin_crashed;
        void function( cef_request_handler_t*, cef_browser_t* ) on_render_view_ready;
        void function( cef_request_handler_t*,cef_browser_t*,cef_termination_status_t ) on_render_process_terminated;
    }
}

// cef_resource_bundle_capi.h
struct cef_resource_bundle_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_string_userfree_t function( cef_resource_bundle_t*, int ) get_localized_string;
        int function( cef_resource_bundle_t*, int, void**, size_t* ) get_data_resource;
        int function( cef_resource_bundle_t*, int, cef_scale_factor_t, void**, size_t* ) get_data_resource_for_scale;
    }
}

// cef_resource_bundle_handler_capi.h
struct cef_resource_bundle_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_resource_bundle_handler_t*,int,cef_string_t* ) get_localized_string;
        int function( cef_resource_bundle_handler_t*,int,void**,size_t* ) get_data_resource;
        int function( cef_resource_bundle_handler_t*, int, cef_scale_factor_t, void**, size_t* ) get_data_resource_for_scale;
    }
}

// cef_resource_handler_capi.h
struct cef_resource_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_resource_handler_t*,cef_request_t*,cef_callback_t* ) process_request;
        void function( cef_resource_handler_t*,cef_response_t*,int64*,cef_string_t* ) get_response_headers;
        int function( cef_resource_handler_t*,void*,int,int*,cef_callback_t* ) read_response;
        int function( cef_resource_handler_t*,const( cef_cookie_t )* ) can_get_cookie;
        int function( cef_resource_handler_t*,const( cef_cookie_t )* ) can_set_cookie;
        void function( cef_resource_handler_t* ) cancel;
    }
}

// cef_reponse_capi.h
struct cef_response_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_response_t* ) is_read_only;
        cef_errorcode_t function( cef_response_t* ) get_error;
        void function( cef_response_t*,cef_errorcode_t ) set_error;
        int function( cef_response_t* ) get_status;
        void function( cef_response_t*,int ) set_status;
        cef_string_userfree_t function( cef_response_t* ) get_status_text;
        void function( cef_response_t*,const( cef_string_t )* ) set_status_text;
        cef_string_userfree_t function( cef_response_t* ) get_mime_type;
        void function( cef_response_t*,const( cef_string_t )* ) set_mime_type;
        cef_string_userfree_t function( cef_response_t*,const( cef_string_t )* ) get_header;
        void function( cef_response_t*,cef_string_multimap_t ) get_header_map;
        void function( cef_response_t*,cef_string_multimap_t ) set_header_map;
        cef_string_userfree_t function( cef_response_t* ) get_url;
        void function( cef_response_t*, const( cef_string_t )* ) set_url;
    }
}

// cef_response_filter_capi.h
struct cef_response_filter_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_response_filter_t* ) init_filter;
        cef_response_filter_status_t function( cef_response_filter_t*, void*, size_t, size_t*, void*, size_t, size_t* ) filter;
    }
}

// cef_scheme_capi.h
struct cef_scheme_registrar_t {
    cef_base_t base;
    extern( System ) @nogc nothrow int function( cef_scheme_registrar_t*,const( cef_string_t )*,int,int,int,int,int,int ) add_custom_scheme;
}

struct cef_scheme_handler_factory_t {
    cef_base_t base;
    extern( System ) @nogc nothrow cef_resource_handler_t* function( cef_scheme_handler_factory_t*,cef_browser_t*,cef_frame_t*,const( cef_string_t )*,cef_request_t* ) create;
}

// cef_server_capi.h
struct cef_server_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_task_runner_t* function( cef_server_t* ) get_task_runner;
        void function( cef_server_t* ) shutdown;
        int function( cef_server_t* ) is_running;
        cef_string_userfree_t function( cef_server_t* ) get_address;
        int function( cef_server_t* ) has_connection;
        int function( cef_server_t*, int ) is_valid_connection;
        void function( cef_server_t*, int, const( cef_string_t )*, const( void )*, size_t ) send_http200response;
        void function( cef_server_t*, int ) send_http404response;
        void function( cef_server_t*, int, const( cef_string_t )* ) send_http500response;
        void function( cef_server_t*, int, int , const( cef_string_t )*, ulong, cef_string_multimap_t ) send_http_response;
        void function( cef_server_t*, int, const( void )*, size_t ) send_raw_data;
        void function( cef_server_t*, int ) close_connection;
        void function( cef_server_t*, int, const( void )*, size_t ) send_web_socket_message;
    }
}

struct cef_server_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_server_handler_t*, cef_server_t* ) on_server_created;
        void function( cef_server_handler_t*, cef_server_t* ) on_server_destroyed;
        void function( cef_server_handler_t*, cef_server_t*, int ) on_client_connected;
        void function( cef_server_handler_t*, cef_server_t*, int ) on_client_disconnected;
        void function( cef_server_handler_t*, cef_server_t*, int, const( cef_string_t )*, cef_request_t* ) on_http_request;
        void function( cef_server_handler_t*, cef_server_t*, int, const( cef_string_t )*, cef_request_t*, cef_callback_t* ) on_web_socket_request;
        void function( cef_server_handler_t*, cef_server_t* server, int ) on_web_socket_connected;
        void function( cef_server_handler_t*, cef_server_t*, int, const( void )*, size_t ) on_web_socket_message;
    }
}

// cef_ssl_info_capi.h
struct cef_sslinfo_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_cert_status_t function( cef_sslinfo_t* ) get_cert_status;
        cef_x509certificate_t* function( cef_sslinfo_t* self) get_x509certificate;
    }
}

// cef_ssl_status_capi.h
struct cef_sslstatus_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_sslstatus_t* ) is_secure_connection;
        cef_cert_status_t function( cef_sslstatus_t* ) get_cert_status;
        cef_ssl_version_t function( cef_sslstatus_t* ) get_sslversion;
        cef_ssl_content_status_t function( cef_sslstatus_t* ) get_content_status;
        cef_x509certificate_t* function( cef_sslstatus_t* ) get_x509certificate;
    }
}

// cef_stream_capi.h
struct cef_read_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        size_t function( cef_read_handler_t*, void*, size_t, size_t ) read;
        int function( cef_read_handler_t*, ulong, int ) seek;
        ulong function( cef_read_handler_t* ) tell;
        int function( cef_read_handler_t* ) eof;
        int function( cef_read_handler_t* ) may_block;
    }
}

struct cef_stream_reader_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        size_t function( cef_stream_reader_t*, void*, size_t, size_t ) read;
        int function( cef_stream_reader_t*, ulong, int ) seek;
        ulong function( cef_stream_reader_t* ) tell;
        int function( cef_stream_reader_t* ) eof;
        int function( cef_stream_reader_t* ) may_block;
    }
}

struct cef_write_handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        size_t function( cef_write_handler_t*, const( void )*, size_t, size_t ) write;
        int function( cef_write_handler_t*, ulong, int ) seek;
        ulong function( cef_write_handler_t* ) tell;
        int function( cef_write_handler_t* ) flush;
        int function( cef_write_handler_t* ) may_block;
    }
}

struct cef_stream_writer_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        size_t function( cef_stream_writer_t*, const( void )*, size_t, size_t ) write;
        int function( cef_stream_writer_t*, ulong, int ) seek;
        ulong function( cef_stream_writer_t* ) tell;
        int function( cef_stream_writer_t* ) flush;
        int function( cef_stream_writer_t* ) may_block;
    }
}

// cef_string_visitor_capi.h
struct cef_string_visitor_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_string_visitor_t*, const( cef_string_t )* ) visit;
}

// cef_task_capi.h
struct cef_task_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_task_t* ) execute;
} 

struct cef_task_runner_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_task_runner_t*, cef_task_runner_t* ) is_same;
        int function( cef_task_runner_t* ) belongs_to_current_thread;
        int function( cef_task_runner_t*, cef_thread_id_t ) belongs_to_thread;
        int function( cef_task_runner_t*, cef_task_t* ) post_task;
        int function( cef_task_runner_t*, cef_task_t*, ulong ) post_delayed_task;
    }
}

// cef_thread_capi.h
struct cef_thread_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_task_runner_t* function( cef_thread_t* ) get_task_runner;
        cef_platform_thread_id_t function( cef_thread_t* ) get_platform_thread_id;
        void function( cef_thread_t* ) stop;
        int function( cef_thread_t* ) is_running;
    }
}

// cef_trace_capi.h
struct cef_end_tracing_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_end_tracing_callback_t*, const( cef_string_t )* ) on_end_tracing_complete;
}

// cef_urlrequest_capi.h
struct cef_urlrequest_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_request_t* function( cef_urlrequest_t* ) get_request;
        cef_urlrequest_client_t* function( cef_urlrequest_t* ) get_client;
        cef_urlrequest_status_t function( cef_urlrequest_t* ) get_request_status;
        cef_errorcode_t function( cef_urlrequest_t* ) get_request_error;
        cef_response_t* function( cef_urlrequest_t* ) get_response;
        int function( cef_urlrequest_t* ) response_was_cached;
        void function( cef_urlrequest_t* ) cancel;
    }
}

struct cef_urlrequest_client_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_urlrequest_client_t*, cef_urlrequest_t* ) on_request_complete;
        void function( cef_urlrequest_client_t*, cef_urlrequest_t*, ulong, ulong ) on_upload_progress;
        void function( cef_urlrequest_client_t*, cef_urlrequest_t*, ulong, ulong ) on_download_progress;
        void function( cef_urlrequest_client_t*, cef_urlrequest_t*, const( void )*, size_t) on_download_data;
        int function( cef_urlrequest_client_t*, int, const( cef_string_t )*, int, const( cef_string_t )*, const( cef_string_t )*, cef_auth_callback_t* ) get_auth_credentials;
    }
}

// cef_v8_capi.h
struct cef_v8context_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_task_runner_t* function( cef_v8context_t* slf) get_task_runner;
        int function( cef_v8context_t* ) is_valid;
        cef_browser_t* function( cef_v8context_t* ) get_browser;
        cef_frame_t* function( cef_v8context_t* ) get_frame;
        cef_v8value_t* function( cef_v8context_t* ) get_global;
        int function( cef_v8context_t* ) enter;
        int function( cef_v8context_t* ) exit;
        int function( cef_v8context_t*, cef_v8context_t* ) is_same;
        int function( cef_v8context_t*, const( cef_string_t )*, const( cef_string_t )*, int, cef_v8value_t**, cef_v8exception_t** ) eval;
    }
}

struct cef_v8handler_t {
    cef_base_t base;
    extern( System ) @nogc nothrow int function( cef_v8handler_t*, const( cef_string_t )*, cef_v8value_t*, size_t, const( cef_v8value_t* ), cef_v8value_t**, cef_string_t* ) execute;
}

struct cef_v8accessor_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_v8accessor_t*, const( cef_string_t )*, cef_v8value_t*, cef_v8value_t**, cef_string_t* ) get;
        int function( cef_v8accessor_t*, const( cef_string_t )*, cef_v8value_t*, cef_v8value_t*, cef_string_t* ) set;
    }
}

struct cef_v8interceptor_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_v8interceptor_t*, const( cef_string_t )*, cef_v8value_t*, cef_v8value_t**, cef_string_t* ) get_byname;
        int function( cef_v8interceptor_t*, int, cef_v8value_t*, cef_v8value_t**, cef_string_t* ) get_byindex;
        int function( cef_v8interceptor_t*, const( cef_string_t )*, cef_v8value_t*, cef_v8value_t*, cef_string_t* ) set_byname;
        int function( cef_v8interceptor_t*, int, cef_v8value_t*, cef_v8value_t*, cef_string_t* ) set_byindex;
    }
}

struct cef_v8exception_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_string_userfree_t function( cef_v8exception_t* ) get_message;
        cef_string_userfree_t function( cef_v8exception_t* ) get_source_line;
        cef_string_userfree_t function( cef_v8exception_t* ) get_script_resource_name;
        int function( cef_v8exception_t* ) get_line_number;
        int function( cef_v8exception_t* ) get_start_position;
        int function( cef_v8exception_t* ) get_end_position;
        int function( cef_v8exception_t* ) get_start_column;
        int function( cef_v8exception_t* ) get_end_column;
    }
}

struct cef_v8array_buffer_release_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow  void function( cef_v8array_buffer_release_callback_t*, void* ) release_buffer;
}

struct cef_v8value_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_v8value_t* ) is_valid;
        int function( cef_v8value_t* ) is_undefined;
        int function( cef_v8value_t* ) is_null;
        int function( cef_v8value_t* ) is_bool;
        int function( cef_v8value_t* ) is_int;
        int function( cef_v8value_t* ) is_uint;
        int function( cef_v8value_t* ) is_double;
        int function( cef_v8value_t* ) is_date;
        int function( cef_v8value_t* ) is_string;
        int function( cef_v8value_t* ) is_object;
        int function( cef_v8value_t* ) is_array;
        int function( cef_v8value_t* ) is_array_buffer;
        int function( cef_v8value_t* ) is_function;
        int function( cef_v8value_t*, cef_v8value_t* ) is_same;
        int function( cef_v8value_t* ) get_bool_value;
        int32 function( cef_v8value_t* ) get_int_value;
        uint32 function( cef_v8value_t* ) get_uint_value;
        double function( cef_v8value_t* ) get_double_value;
        cef_time_t function( cef_v8value_t* ) get_date_value;
        cef_string_userfree_t function( cef_v8value_t* ) get_string_value;
        int function( cef_v8value_t* ) is_user_created;
        int function( cef_v8value_t* ) has_exception;
        cef_v8exception_t* function( cef_v8value_t* ) get_exception;
        int function( cef_v8value_t* ) clear_exception;
        int function( cef_v8value_t* ) will_rethrow_exceptions;
        int function( cef_v8value_t*, int ) set_rethrow_exceptions;
        int function( cef_v8value_t*, const( cef_string_t )* ) has_value_bykey;
        int function( cef_v8value_t*, int ) has_value_byindex;
        int function( cef_v8value_t*, const( cef_string_t )* ) delete_value_bykey;
        int function( cef_v8value_t*, int ) delete_value_byindex;
        cef_v8value_t* function( cef_v8value_t*, const( cef_string_t )* ) get_value_bykey;
        cef_v8value_t* function( cef_v8value_t*, int ) get_value_byindex;
        int function( cef_v8value_t*, const( cef_string_t )*, cef_v8value_t*, cef_v8_propertyattribute_t ) set_value_bykey;
        int function( cef_v8value_t*, int, cef_v8value_t* ) set_value_byindex;
        int function( cef_v8value_t*, const( cef_string_t )*, cef_v8_accesscontrol_t, cef_v8_propertyattribute_t ) set_value_byaccessor;
        int function( cef_v8value_t*, cef_string_list_t ) get_keys;
        int function( cef_v8value_t*, cef_base_t* ) set_user_data;
        cef_base_t* function( cef_v8value_t* ) get_user_data;
        int function( cef_v8value_t* ) get_externally_allocated_memory;
        int function( cef_v8value_t*, int ) adjust_externally_allocated_memory;
        int function( cef_v8value_t* ) get_array_length;
        cef_v8array_buffer_release_callback_t* function( cef_v8value_t* ) get_array_buffer_release_callback;
        int function( cef_v8value_t* ) neuter_array_buffer;
        cef_string_userfree_t function( cef_v8value_t* ) get_function_name;
        cef_v8handler_t* function( cef_v8value_t* ) get_function_handler;
        cef_v8value_t* function( cef_v8value_t*, cef_v8value_t*, size_t, const( cef_v8value_t* ) ) execute_function;
        cef_v8value_t* function( cef_v8value_t*, cef_v8context_t*, cef_v8value_t*, size_t, const( cef_v8value_t* )) execute_function_with_context;
    }
}

struct cef_v8stack_trace_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_v8stack_trace_t* ) is_valid;
        int function( cef_v8stack_trace_t* ) get_frame_count;
        cef_v8stack_frame_t* function( cef_v8stack_trace_t*, int ) get_frame;
    }
}

struct cef_v8stack_frame_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_v8stack_frame_t* ) is_valid;
        cef_string_userfree_t function( cef_v8stack_frame_t* ) get_script_name;
        cef_string_userfree_t function( cef_v8stack_frame_t* ) get_script_name_or_source_url;
        cef_string_userfree_t function( cef_v8stack_frame_t* ) get_function_name;
        int function( cef_v8stack_frame_t* ) get_line_number;
        int function( cef_v8stack_frame_t* ) get_column;
        int function( cef_v8stack_frame_t* ) is_eval;
        int function( cef_v8stack_frame_t* ) is_constructor;
    }
}


// cef_values_capi.h
struct cef_value_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_value_t* ) is_valid;
        int function( cef_value_t* ) is_owned;
        int function( cef_value_t* ) is_read_only;
        int function( cef_value_t*, cef_value_t* ) is_same;
        int function( cef_value_t*, cef_value_t* ) is_equal;
        cef_value_t* function( cef_value_t* ) copy;
        cef_value_type_t function( cef_value_t* ) get_type;
        int function( cef_value_t* ) get_bool;
        int function( cef_value_t* ) get_int;
        double function( cef_value_t* ) get_double;
        cef_string_userfree_t function( cef_value_t* ) get_string;
        cef_binary_value_t* function( cef_value_t* ) get_binary;
        cef_dictionary_value_t* function( cef_value_t* ) get_dictionary;
        cef_list_value_t* function( cef_value_t* ) get_list;
        int function( cef_value_t* ) set_null;
        int function( cef_value_t*, int ) set_bool;
        int function( cef_value_t*, int ) set_int;
        int function( cef_value_t*, double ) set_double;
        int function( cef_value_t*, const( cef_string_t )* ) set_string;
        int function( cef_value_t*, cef_binary_value_t* ) set_binary;
        int function( cef_value_t*, cef_dictionary_value_t* ) set_dictionary;
        int function( cef_value_t*, cef_list_value_t* ) set_list;
    }
}

struct cef_binary_value_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_binary_value_t* ) is_valid;
        int function( cef_binary_value_t* ) is_owned;
        int function( cef_binary_value_t*, cef_binary_value_t* ) is_same;
        int function( cef_binary_value_t*, cef_binary_value_t* ) is_equal;
        cef_binary_value_t* function( cef_binary_value_t* ) copy;
        size_t function( cef_binary_value_t* ) get_size;
        size_t function( cef_binary_value_t*, void*, size_t, size_t ) get_data;
    }
}

struct cef_dictionary_value_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_dictionary_value_t* ) is_valid;
        int function( cef_dictionary_value_t* ) is_owned;
        int function( cef_dictionary_value_t* ) is_read_only;
        int function( cef_dictionary_value_t*, cef_dictionary_value_t* ) is_same;
        int function( cef_dictionary_value_t*, cef_dictionary_value_t* ) is_equal;
        cef_dictionary_value_t* function( cef_dictionary_value_t*, int ) copy;
        size_t function( cef_dictionary_value_t* ) get_size;
        int function( cef_dictionary_value_t* ) clear;
        int function( cef_dictionary_value_t*, const( cef_string_t )* ) has_key;
        int function( cef_dictionary_value_t*, cef_string_list_t ) get_keys;
        int function( cef_dictionary_value_t*, const( cef_string_t )* ) remove;
        cef_value_type_t function( cef_dictionary_value_t*, const( cef_string_t )* ) get_type;
        cef_value_t* function( cef_dictionary_value_t*, const( cef_string_t )* ) get_value;
        int function( cef_dictionary_value_t*, const( cef_string_t )* ) get_bool;
        int function( cef_dictionary_value_t*, const( cef_string_t )* ) get_int;
        double function( cef_dictionary_value_t*, const( cef_string_t )* ) get_double;
        cef_string_userfree_t function( cef_dictionary_value_t*, const( cef_string_t )* ) get_string;
        cef_binary_value_t* function( cef_dictionary_value_t* self, const( cef_string_t )* key) get_binary;
        cef_dictionary_value_t* function( cef_dictionary_value_t* self, const( cef_string_t )* key) get_dictionary;
        cef_list_value_t* function( cef_dictionary_value_t*, const( cef_string_t )* ) get_list;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, cef_value_t* ) set_value;
        int function( cef_dictionary_value_t*, const( cef_string_t )* ) set_null;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, int ) set_bool;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, int ) set_int;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, double ) set_double;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, const( cef_string_t )* ) set_string;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, cef_binary_value_t* ) set_binary;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, cef_dictionary_value_t* ) set_dictionary;
        int function( cef_dictionary_value_t*, const( cef_string_t )*, cef_list_value_t* ) set_list;
    }
}

struct cef_list_value_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_list_value_t* ) is_valid;
        int function( cef_list_value_t* ) is_owned;
        int function( cef_list_value_t* ) is_read_only;
        int function( cef_list_value_t*, cef_list_value_t* ) is_same;
        int function( cef_list_value_t*, cef_list_value_t* ) is_equal;
        cef_list_value_t* function( cef_list_value_t* ) copy;
        int function( cef_list_value_t*, size_t ) set_size;
        size_t function( cef_list_value_t* ) get_size;
        int function( cef_list_value_t* ) clear;
        int function( cef_list_value_t*, size_t ) remove;
        cef_value_type_t function( cef_list_value_t*, size_t ) get_type;
        cef_value_t* function( cef_list_value_t*, size_t ) get_value;
        int function( cef_list_value_t*, size_t ) get_bool;
        int function( cef_list_value_t*, size_t ) get_int;
        double function( cef_list_value_t*, size_t ) get_double;
        cef_string_userfree_t function( cef_list_value_t*, size_t ) get_string;
        cef_binary_value_t* function( cef_list_value_t*, size_t ) get_binary;
        cef_dictionary_value_t* function( cef_list_value_t*, size_t ) get_dictionary;
        cef_list_value_t* function( cef_list_value_t*, size_t ) get_list;
        int function( cef_list_value_t*, size_t, cef_value_t* ) set_value;
        int function( cef_list_value_t*, size_t ) set_null;
        int function( cef_list_value_t*, size_t, int ) set_bool;
        int function( cef_list_value_t*, size_t, int ) set_int;
        int function( cef_list_value_t*, size_t, double ) set_double;
        int function( cef_list_value_t*, size_t, const( cef_string_t )* ) set_string;
        int function( cef_list_value_t*, size_t, cef_binary_value_t* ) set_binary;
        int function( cef_list_value_t*, size_t, cef_dictionary_value_t*value) set_dictionary;
        int function( cef_list_value_t*, size_t, cef_list_value_t* ) set_list;
    }
}

// cef_waitable_event_capi.h
struct cef_waitable_event_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_waitable_event_t* ) reset;
        void function( cef_waitable_event_t* ) signal;
        int function( cef_waitable_event_t* ) is_signaled;
        void function( cef_waitable_event_t* ) wait;
        int function( cef_waitable_event_t*, ulong ) timed_wait;
    }
}

// cef_web_plugin_capi.h
struct cef_web_plugin_info_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_string_userfree_t function( cef_web_plugin_info_t* ) get_name;
        cef_string_userfree_t function( cef_web_plugin_info_t* ) get_path;
        cef_string_userfree_t function( cef_web_plugin_info_t* ) get_version;
        cef_string_userfree_t function( cef_web_plugin_info_t* ) get_description;
    }
}

struct cef_web_plugin_info_visitor_t {
    cef_base_t base;
    extern( System ) @nogc nothrow int function( cef_web_plugin_info_visitor_t*,cef_web_plugin_info_t*,int,int ) visit;
}

struct cef_web_plugin_unstable_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_web_plugin_unstable_callback_t,const( cef_string_t )*,int ) is_unstable;
}

struct cef_register_cdm_callback_t {
    cef_base_t base;
    extern( System ) @nogc nothrow void function( cef_register_cdm_callback_t*, cef_cdm_registration_error_t, const ( cef_string_t )* ) on_cdm_registration_complete;
}

// cef_x509_certificate_capi.h
struct cef_x509cert_principal_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_string_userfree_t function( cef_x509cert_principal_t* ) get_display_name;
        cef_string_userfree_t function( cef_x509cert_principal_t* ) get_common_name;
        cef_string_userfree_t function( cef_x509cert_principal_t* ) get_locality_name;
        cef_string_userfree_t function( cef_x509cert_principal_t* ) get_state_or_province_name;
        cef_string_userfree_t function( cef_x509cert_principal_t* ) get_country_name;
        void function( cef_x509cert_principal_t*, cef_string_list_t ) get_street_addresses;
        void function( cef_x509cert_principal_t*, cef_string_list_t ) get_organization_names;
        void function( cef_x509cert_principal_t*, cef_string_list_t ) get_organization_unit_names;
        void function( cef_x509cert_principal_t*, cef_string_list_t ) get_domain_components;
    }
}

struct cef_x509certificate_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_x509cert_principal_t* function( cef_x509certificate_t* ) get_subject;
        cef_x509cert_principal_t* function( cef_x509certificate_t* ) get_issuer;
        cef_binary_value_t* function( cef_x509certificate_t* ) get_serial_number;
        cef_time_t function( cef_x509certificate_t* ) get_valid_start;
        cef_time_t function( cef_x509certificate_t* ) get_valid_expiry;
        cef_binary_value_t* function( cef_x509certificate_t* ) get_derencoded;
        cef_binary_value_t* function( cef_x509certificate_t* ) get_pemencoded;
        size_t function( cef_x509certificate_t* ) get_issuer_chain_size;
        void function( cef_x509certificate_t*, size_t*, cef_binary_value_t** ) get_derencoded_issuer_chain;
        void function( cef_x509certificate_t*, size_t*, cef_binary_value_t** ) get_pemencoded_issuer_chain;
    }
}

// cef_xml_reader_capi.h
struct cef_xml_reader_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_xml_reader_t* ) move_to_next_node;
        int function( cef_xml_reader_t* ) close;
        int function( cef_xml_reader_t* ) has_error;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_error;
        cef_xml_node_type_t function( cef_xml_reader_t* ) get_type;
        int function( cef_xml_reader_t* ) get_depth;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_local_name;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_prefix;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_qualified_name;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_namespace_uri;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_base_uri;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_xml_lang;
        int function( cef_xml_reader_t* ) is_empty_element;
        int function( cef_xml_reader_t* ) has_value;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_value;
        int function( cef_xml_reader_t* ) has_attributes;
        size_t function( cef_xml_reader_t* ) get_attribute_count;
        cef_string_userfree_t function( cef_xml_reader_t*,int ) get_attribute_byindex;
        cef_string_userfree_t function( cef_xml_reader_t*,const( cef_string_t )* ) get_attribute_byqname;
        cef_string_userfree_t function( cef_xml_reader_t*,const( cef_string_t )*,const( cef_string_t )* ) get_attribute_bylname;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_inner_xml;
        cef_string_userfree_t function( cef_xml_reader_t* ) get_outer_xml;
        int function( cef_xml_reader_t* ) get_line_number;
        int function( cef_xml_reader_t*,int ) move_to_attribute_by_index;
        int function( cef_xml_reader_t*,const( cef_string_t )* ) move_to_attribute_byqname;
        int function( cef_xml_reader_t*,const( cef_string_t )*,const( cef_string_t )* ) move_to_attribute_bylname;
        int function( cef_xml_reader_t* ) move_to_first_attribute;
        int function( cef_xml_reader_t* ) move_to_next_attribute;
        int function( cef_xml_reader_t* ) move_to_carrying_element;
    }
}

// cef_zip_reader_capi.h
struct cef_zip_reader_t {
    import core.stdc.time : time_t;

    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_zip_reader_t* ) move_to_first_file;
        int function( cef_zip_reader_t* ) move_to_next_file;
        int function( cef_zip_reader_t*,const( cef_string_t )*,int ) move_to_file;
        int function( cef_zip_reader_t* ) close;
        cef_string_userfree_t function( cef_zip_reader_t* ) get_file_name;
        int64 function( cef_zip_reader_t* ) get_file_size;
        time_t function( cef_zip_reader_t* ) get_file_last_modified;
        int function( cef_zip_reader_t*,const( cef_string_t )* ) open_file;
        int function( cef_zip_reader_t* ) close_file;
        int function( cef_zip_reader_t*,void*,size_t ) read_file;
        int64 function( cef_zip_reader_t* ) tell;
        int function( cef_zip_reader_t* ) eof;
    }
}

// test/cef_translator_test_capi.h
struct cef_translator_test_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        void function( cef_translator_test_t* ) get_void;
        int function( cef_translator_test_t* ) get_bool;
        int function( cef_translator_test_t* ) get_int;
        double function( cef_translator_test_t* ) get_double;
        long function( cef_translator_test_t* ) get_long;
        size_t function( cef_translator_test_t* ) get_sizet;
        int function( cef_translator_test_t* ) set_void;
        int function( cef_translator_test_t*, int ) set_bool;
        int function( cef_translator_test_t*, int ) set_int;
        int function( cef_translator_test_t*, double ) set_double;
        int function( cef_translator_test_t*, long ) set_long;
        int function( cef_translator_test_t*, size_t ) set_sizet;
        int function( cef_translator_test_t*, size_t, const( int* ) ) set_int_list;
        int function( cef_translator_test_t*, size_t*, int* ) get_int_list_by_ref;
        size_t function( cef_translator_test_t* ) get_int_list_size;
        cef_string_userfree_t function( cef_translator_test_t* ) get_string;
        int function( cef_translator_test_t*, const( cef_string_t )* ) set_string;
        void function( cef_translator_test_t*, cef_string_t* ) get_string_by_ref;
        int function( cef_translator_test_t*, cef_string_list_t ) set_string_list;
        int function( cef_translator_test_t*, cef_string_list_t ) get_string_list_by_ref;
        int function( cef_translator_test_t*, cef_string_map_t ) set_string_map;
        int function( cef_translator_test_t*, cef_string_map_t ) get_string_map_by_ref;
        int function( cef_translator_test_t*, cef_string_multimap_t ) set_string_multimap;
        int function( cef_translator_test_t*, cef_string_multimap_t ) get_string_multimap_by_ref;
        cef_point_t function( cef_translator_test_t* ) get_point;
        int function( cef_translator_test_t*, const( cef_point_t )* ) set_point;
        void function( cef_translator_test_t*, cef_point_t* ) get_point_by_ref;
        int function( cef_translator_test_t*, size_t, const( cef_point_t* ) val) set_point_list;
        int function( cef_translator_test_t*, size_t*, cef_point_t* ) get_point_list_by_ref;
        size_t function( cef_translator_test_t* ) get_point_list_size;
        cef_translator_test_ref_ptr_library_t* function( cef_translator_test_t*, int ) get_ref_ptr_library;
        int function( cef_translator_test_t*, cef_translator_test_ref_ptr_library_t* ) set_ref_ptr_library;
        cef_translator_test_ref_ptr_library_t* function( cef_translator_test_t*, cef_translator_test_ref_ptr_library_t* ) set_ref_ptr_library_and_return;
        int function( cef_translator_test_t*, cef_translator_test_ref_ptr_library_child_t* ) set_child_ref_ptr_library;
        cef_translator_test_ref_ptr_library_t* function( cef_translator_test_t*, cef_translator_test_ref_ptr_library_child_t* ) set_child_ref_ptr_library_and_return_parent;
        int function( cef_translator_test_t*, size_t, const( cef_translator_test_ref_ptr_library_t* ) val, int , int ) set_ref_ptr_library_list;
        int function( cef_translator_test_t*, size_t*, cef_translator_test_ref_ptr_library_t**, int, int ) get_ref_ptr_library_list_by_ref;
        size_t function( cef_translator_test_t* ) get_ref_ptr_library_list_size;
        int function( cef_translator_test_t*, cef_translator_test_ref_ptr_client_t* ) set_ref_ptr_client;
        cef_translator_test_ref_ptr_client_t* function( cef_translator_test_t* self, cef_translator_test_ref_ptr_client_t* ) set_ref_ptr_client_and_return;
        int function( cef_translator_test_t*, cef_translator_test_ref_ptr_client_child_t* ) set_child_ref_ptr_client;
        cef_translator_test_ref_ptr_client_t* function( cef_translator_test_t*, cef_translator_test_ref_ptr_client_child_t* ) set_child_ref_ptr_client_and_return_parent;
        int function( cef_translator_test_t*, size_t, const( cef_translator_test_ref_ptr_client_t* ) val, int, int ) set_ref_ptr_client_list;
        int function( cef_translator_test_t*, size_t*, cef_translator_test_ref_ptr_client_t**, cef_translator_test_ref_ptr_client_t*, cef_translator_test_ref_ptr_client_t* ) get_ref_ptr_client_list_by_ref;
        size_t function( cef_translator_test_t* ) get_ref_ptr_client_list_size;
        cef_translator_test_scoped_library_t* function( cef_translator_test_t*, int ) get_own_ptr_library;
        int function( cef_translator_test_t*, cef_translator_test_scoped_library_t* ) set_own_ptr_library;
        cef_translator_test_scoped_library_t* function( cef_translator_test_t*, cef_translator_test_scoped_library_t* ) set_own_ptr_library_and_return;
        int function( cef_translator_test_t*, cef_translator_test_scoped_library_child_t* ) set_child_own_ptr_library;
        cef_translator_test_scoped_library_t* function( cef_translator_test_t*, cef_translator_test_scoped_library_child_t* ) set_child_own_ptr_library_and_return_parent;
        int function( cef_translator_test_t*, cef_translator_test_scoped_client_t* ) set_own_ptr_client;
        cef_translator_test_scoped_client_t* function( cef_translator_test_t*, cef_translator_test_scoped_client_t* ) set_own_ptr_client_and_return;
        int function( cef_translator_test_t*, cef_translator_test_scoped_client_child_t* ) set_child_own_ptr_client;
        cef_translator_test_scoped_client_t* function( cef_translator_test_t*, cef_translator_test_scoped_client_child_t* ) set_child_own_ptr_client_and_return_parent;
        int function( cef_translator_test_t*, cef_translator_test_scoped_library_t* ) set_raw_ptr_library;
        int function( cef_translator_test_t*, cef_translator_test_scoped_library_child_t* ) set_child_raw_ptr_library;
        int function( cef_translator_test_t*, size_t, const( cef_translator_test_scoped_library_t* ), int, int ) set_raw_ptr_library_list;
        int function( cef_translator_test_t*, cef_translator_test_scoped_client_t* ) set_raw_ptr_client;
        int function( cef_translator_test_t*, cef_translator_test_scoped_client_child_t* ) set_child_raw_ptr_client;
        int function( cef_translator_test_t*, size_t, const( cef_translator_test_scoped_client_t* ), int, int ) set_raw_ptr_client_list;
    }
}

struct cef_translator_test_ref_ptr_library_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_translator_test_ref_ptr_library_t* ) get_value;
        void function( cef_translator_test_ref_ptr_library_t*, int ) set_value;
    }
}

struct cef_translator_test_ref_ptr_library_child_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        int function( cef_translator_test_ref_ptr_library_child_t* ) get_other_value;
        void function( cef_translator_test_ref_ptr_library_child_t*, int ) set_other_value;
    }
}

struct cef_translator_test_ref_ptr_library_child_child_t {
    cef_translator_test_ref_ptr_library_t base;
    extern( System ) @nogc nothrow {
        int function( cef_translator_test_ref_ptr_library_child_child_t* ) get_other_other_value;
        void function( cef_translator_test_ref_ptr_library_child_child_t*, int ) set_other_other_value;
    }
}

struct cef_translator_test_ref_ptr_client_t {
    cef_base_t base;
    extern( System ) @nogc nothrow int function( cef_translator_test_ref_ptr_client_t* ) get_value;
}

struct cef_translator_test_ref_ptr_client_child_t {
    cef_translator_test_ref_ptr_client_t base;
    extern( System ) @nogc nothrow int function( cef_translator_test_ref_ptr_client_child_t* ) get_other_value;
}

struct cef_translator_test_scoped_library_t {
    cef_base_scoped_t base;
    extern( System ) @nogc nothrow {
        int function( cef_translator_test_scoped_library_t* ) get_value;
        void function( cef_translator_test_scoped_library_t*, int ) set_value;
    }
}

struct cef_translator_test_scoped_library_child_t {
    cef_translator_test_scoped_library_t base;
    extern( System ) @nogc nothrow {
        int function( cef_translator_test_scoped_library_child_t* ) get_other_value;
        void function( cef_translator_test_scoped_library_child_t*, int ) set_other_value;
    }
}

struct cef_translator_test_scoped_library_child_child_t {
    cef_translator_test_scoped_library_child_t base;
    extern( System ) @nogc nothrow {
        int function( cef_translator_test_scoped_library_child_child_t* ) get_other_other_value;
        void function( cef_translator_test_scoped_library_child_child_t*, int ) set_other_other_value;
    }
}

struct cef_translator_test_scoped_client_t {
    cef_base_scoped_t base;
    extern( System ) @nogc nothrow int function( cef_translator_test_scoped_client_t* ) get_value;
}

struct cef_translator_test_scoped_client_child_t {
    cef_translator_test_scoped_client_t base;
    extern( System ) @nogc nothrow int function( cef_translator_test_scoped_client_child_t* ) get_other_value;
}

// views/cef_box_layout_capi.h
struct cef_box_layout_t {
    cef_layout_t base;
    extern( System ) @nogc nothrow {
        void function( cef_box_layout_t*, cef_view_t*, int ) set_flex_for_view;
        void function( cef_box_layout_t*, cef_view_t* ) clear_flex_for_view;
    }
}

// views/cef_browser_view_capi.h
struct cef_browser_view_t {
    cef_view_t base;
    extern( System ) @nogc nothrow {
        cef_browser_t* function( cef_browser_view_t* ) get_browser;
        void function( cef_browser_view_t* , int ) set_prefer_accelerators;
    }
}

// views/cef_browser_view_delegate_capi.h
struct cef_browser_view_delegate_t {
    cef_view_delegate_t base;
    extern( System ) @nogc nothrow {
        void function( cef_browser_view_delegate_t*, cef_browser_view_t*, cef_browser_t* ) on_browser_created;
        void function( cef_browser_view_delegate_t*, cef_browser_view_t*, cef_browser_t* ) on_browser_destroyed;
        cef_browser_view_delegate_t* function( cef_browser_view_delegate_t*, cef_browser_view_t*, const( cef_browser_settings_t )*, cef_client_t*, int ) get_delegate_for_popup_browser_view;
        int function( cef_browser_view_delegate_t*, cef_browser_view_t*, cef_browser_view_t*, int is_devtools) on_popup_browser_view_created;
    }
}

// views/cef_button_capi.h
struct cef_button_t {
    cef_view_t base;
    extern( System ) @nogc nothrow {
        cef_label_button_t* function( cef_button_t* ) as_label_button;
        void function( cef_button_t*, cef_button_state_t ) set_state;
        cef_button_state_t function( cef_button_t* ) get_state;
        void function( cef_button_t*, int ) set_ink_drop_enabled;
        void function( cef_button_t*, const( cef_string_t )* ) set_tooltip_text;
        void function( cef_button_t*, const( cef_string_t )* ) set_accessible_name;
    }
}

// views/cef_button_delegate_capi.h
struct cef_button_delegate_t {
    cef_view_delegate_t base;
    extern( System ) @nogc nothrow {
        void function( cef_button_delegate_t*, cef_button_t* ) on_button_pressed;
        void function( cef_button_delegate_t*, cef_button_t* ) on_button_state_changed;
    }
}

// views/cef_display_capi.h
struct cef_display_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        long function( cef_display_t* )get_id;
        float function( cef_display_t* ) get_device_scale_factor;
        void function( cef_display_t*, cef_point_t* ) convert_point_to_pixels;
        void function( cef_display_t*, cef_point_t* ) convert_point_from_pixels;
        cef_rect_t function( cef_display_t* ) get_bounds;
        cef_rect_t function( cef_display_t* ) get_work_area;
        int function( cef_display_t* ) get_rotation;
    }
}

// views/cef_fill_layout_capi.h
struct cef_fill_layout_t {
    cef_layout_t base;
}

// views/cef_label_button_capi.h
struct cef_label_button_t {
    cef_button_t base;
    extern( System ) @nogc nothrow {
        cef_menu_button_t* function( cef_label_button_t* ) as_menu_button;
        void function( cef_label_button_t*, const( cef_string_t )* ) set_text;
        cef_string_userfree_t function( cef_label_button_t* ) get_text;
        void function( cef_label_button_t*, cef_button_state_t, cef_image_t* ) set_image;
        cef_image_t* function( cef_label_button_t*, cef_button_state_t ) get_image;
        void function( cef_label_button_t*, cef_button_state_t, cef_color_t ) set_text_color;
        void function( cef_label_button_t* , cef_color_t ) set_enabled_text_colors;
        void function( cef_label_button_t* , const( cef_string_t )* ) set_font_list;
        void function( cef_label_button_t*, cef_horizontal_alignment_t ) set_horizontal_alignment;
        void function( cef_label_button_t*, const( cef_size_t )* size) set_minimum_size;
        void function( cef_label_button_t*, const( cef_size_t )* ) set_maximum_size;
    }
}

// views/cef_layout_capi.h
struct cef_layout_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_box_layout_t* function( cef_layout_t* ) as_box_layout;
        cef_fill_layout_t* function( cef_layout_t* ) as_fill_layout;
        int function( cef_layout_t* ) is_valid;
    }
}

// views/cef_menu_button_capi.h
struct cef_menu_button_t {
    cef_label_button_t base;
    extern( System ) @nogc nothrow {
        void function( cef_menu_button_t*, cef_menu_model_t*, const( cef_point_t )* , cef_menu_anchor_position_t ) show_menu;
        void function( cef_menu_button_t* ) trigger_menu;
    }
}

// views/cef_menu_button_delegate_capi.h
struct cef_menu_button_pressed_lock_t {
    cef_base_t base;
}

struct cef_menu_button_delegate_t {
    cef_button_delegate_t base;
    extern( System ) @nogc nothrow void function( cef_menu_button_delegate_t* self, cef_menu_button_t*, const( cef_point_t )*, cef_menu_button_pressed_lock_t* ) on_menu_button_pressed;
}

// views/cef_panel_capi.h
struct cef_panel_t {
    cef_view_t base;
    extern( System ) @nogc nothrow {
        cef_window_t* function( cef_panel_t* ) as_window;
        cef_fill_layout_t* function( cef_panel_t* ) set_to_fill_layout;
        cef_box_layout_t* function( cef_panel_t*, const( cef_box_layout_settings_t )* ) set_to_box_layout;
        cef_layout_t* function( cef_panel_t* ) get_layout;
        void function( cef_panel_t* ) layout;
        void function( cef_panel_t*, cef_view_t* ) add_child_view;
        void function( cef_panel_t*, cef_view_t*, int ) add_child_view_at;
        void function( cef_panel_t*, cef_view_t*, int ) reorder_child_view;
        void function( cef_panel_t*, cef_view_t* ) remove_child_view;
        void function( cef_panel_t* ) remove_all_child_views;
        size_t function( cef_panel_t* ) get_child_view_count;
        cef_view_t* function( cef_panel_t*, int ) get_child_view_at;
    }
}

// views/cef_panel_delegate_capi.h
struct cef_panel_delegate_t {
    cef_view_delegate_t base;
}

// views/cef_scroll_view_capi.h
struct cef_scroll_view_t {
    cef_view_t base;
    extern( System ) @nogc nothrow {
        void function( cef_scroll_view_t*, cef_view_t* ) set_content_view;
        cef_view_t* function( cef_scroll_view_t* ) get_content_view;
        cef_rect_t function( cef_scroll_view_t* ) get_visible_content_rect;
        int function( cef_scroll_view_t* ) has_horizontal_scrollbar ;
        int function( cef_scroll_view_t* ) get_horizontal_scrollbar_height;
        int function( cef_scroll_view_t* ) has_vertical_scrollbar;
        int function( cef_scroll_view_t* ) get_vertical_scrollbar_width;
    }
}

// views/cef_scroll_view_capi.h
struct cef_textfield_t {
    cef_view_t base;
    extern( System ) @nogc nothrow {
        void function( cef_textfield_t*, int ) set_password_input;
        int function( cef_textfield_t* ) is_password_input;
        void function( cef_textfield_t*, int ) set_read_only;
        int function( cef_textfield_t* ) is_read_only;
        cef_string_userfree_t function( cef_textfield_t* ) get_text;
        void function( cef_textfield_t* , const( cef_string_t )* ) set_text;
        void function( cef_textfield_t*, const( cef_string_t )* ) append_text;
        void function( cef_textfield_t*, const( cef_string_t )* ) insert_or_replace_text;
        int function( cef_textfield_t* ) has_selection;
        cef_string_userfree_t function( cef_textfield_t* ) get_selected_text;
        void function( cef_textfield_t*, int ) select_all;
        void function( cef_textfield_t*) clear_selection;
        cef_range_t function( cef_textfield_t* ) get_selected_range;
        void function( cef_textfield_t*, const( cef_range_t )* ) select_range;
        size_t function( cef_textfield_t* ) get_cursor_position;
        void function( cef_textfield_t*, cef_color_t ) set_text_color;
        cef_color_t function( cef_textfield_t* ) get_text_color;
        void function( cef_textfield_t*, cef_color_t ) set_selection_text_color;
        cef_color_t function( cef_textfield_t* ) get_selection_text_color; 
        void function( cef_textfield_t*, cef_color_t ) set_selection_background_color;
        cef_color_t function( cef_textfield_t* ) get_selection_background_color;
        void function( cef_textfield_t*, cef_string_t* ) set_font_list;
        void function( cef_textfield_t*, cef_color_t, const( cef_range_t )* ) apply_text_color;
        void function( cef_textfield_t*, cef_text_style_t, int, const( cef_range_t )* ) apply_text_style;
        int function( cef_textfield_t*, int ) is_command_enabled;
        void function( cef_textfield_t*, int ) execute_command;
        void function( cef_textfield_t* )clear_edit_history;
        void function( cef_textfield_t*, const( cef_string_t )* text) set_placeholder_text;
        cef_string_userfree_t function( cef_textfield_t* ) get_placeholder_text;
        void function( cef_textfield_t*, cef_color_t ) set_placeholder_text_color;
        void function( cef_textfield_t*, const( cef_string_t )* ) set_accessible_name;
    }
}

// views/cef_textfield_delegate_capi.h
struct cef_textfield_delegate_t {
    cef_view_delegate_t base;
    extern( System ) @nogc nothrow {
        int function( cef_textfield_delegate_t*, cef_textfield_t*, const( cef_key_event_t )* ) on_key_event;
        void function( cef_textfield_delegate_t*, cef_textfield_t* ) on_after_user_action;
    }
}

// views/cef_view_capi.h
struct cef_view_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_browser_view_t* function( cef_view_t* ) as_browser_view;
        cef_button_t* function( cef_view_t* ) as_button;
        cef_panel_t* function( cef_view_t* ) as_panel;
        cef_scroll_view_t* function( cef_view_t* ) as_scroll_view;
        cef_textfield_t* function( cef_view_t* ) as_textfield;
        cef_string_userfree_t function( cef_view_t* ) get_type_string;
        cef_string_userfree_t function( cef_view_t* , int ) to_string;
        int function( cef_view_t* ) is_valid;
        int function( cef_view_t* ) is_attached;
        int function( cef_view_t*, cef_view_t* ) is_same;
        cef_view_delegate_t* function( cef_view_t* ) get_delegate;
        cef_window_t* function( cef_view_t* ) get_window;
        int function( cef_view_t* ) get_id;
        void function( cef_view_t*, int ) set_id;
        int function( cef_view_t*) get_group_id;
        void function( cef_view_t*, int ) set_group_id;
        cef_view_t* function( cef_view_t* ) get_parent_view;
        cef_view_t* function( cef_view_t*, int ) get_view_for_id;
        void function( cef_view_t*, const( cef_rect_t )* ) set_bounds;
        cef_rect_t function( cef_view_t* ) get_bounds;
        cef_rect_t function( cef_view_t* ) get_bounds_in_screen;
        void function( cef_view_t*, const( cef_size_t )* ) set_size;
        cef_size_t function( cef_view_t* ) get_size;
        void function( cef_view_t*, const( cef_point_t )* ) set_position;
        cef_point_t function( cef_view_t* ) get_position;
        cef_size_t function( cef_view_t* ) get_preferred_size;
        void function( cef_view_t* ) size_to_preferred_size;
        cef_size_t function( cef_view_t* ) get_minimum_size;
        cef_size_t function( cef_view_t* ) get_maximum_size;
        int function( cef_view_t*, int) get_height_for_width;
        void function( cef_view_t* ) invalidate_layout;
        void function( cef_view_t*, int ) set_visible;
        int function( cef_view_t* ) is_visible;
        int function( cef_view_t* ) is_drawn;
        void function( cef_view_t* , int ) set_enabled;
        int function( cef_view_t* ) is_enabled;
        void function( cef_view_t* , int ) set_focusable;
        int function( cef_view_t* ) is_focusable;
        int function( cef_view_t* ) is_accessibility_focusable;
        void function( cef_view_t* ) request_focus;
        void function( cef_view_t*, cef_color_t ) set_background_color;
        cef_color_t function( cef_view_t* ) get_background_color;
        int function( cef_view_t*, cef_point_t* ) convert_point_to_screen;
        int function( cef_view_t*, cef_point_t* ) convert_point_from_screen;
        int function( cef_view_t*, cef_point_t* ) convert_point_to_window;
        int function( cef_view_t*, cef_point_t* ) convert_point_from_window;
        int function( cef_view_t* , cef_view_t*, cef_point_t* ) convert_point_to_view;
        int function( cef_view_t*, cef_view_t*, cef_point_t* ) convert_point_from_view;
    }
}

// views/cef_view_delegate_capi.h
struct cef_view_delegate_t {
    cef_base_t base;
    extern( System ) @nogc nothrow {
        cef_size_t function( cef_view_delegate_t*, cef_view_t* ) get_preferred_size;
        cef_size_t function( cef_view_delegate_t*, cef_view_t* ) get_minimum_size;
        cef_size_t function( cef_view_delegate_t*, cef_view_t*) get_maximum_size;
        int function( cef_view_delegate_t*, cef_view_t*, int ) get_height_for_width;
        void function( cef_view_delegate_t*, cef_view_t*, int , cef_view_t* ) on_parent_view_changed;
        void function( cef_view_delegate_t*, cef_view_t*, int, cef_view_t* ) on_child_view_changed;
        void function( cef_view_delegate_t* , cef_view_t* ) on_focus;
        void function( cef_view_delegate_t*, cef_view_t* ) on_blur;
    }
}

// views/cef_window_capi.h
struct  cef_window_t {
    cef_panel_t base;
    extern( System ) @nogc nothrow {
        void function( cef_window_t* ) show;
        void function( cef_window_t* ) hide;
        void function( cef_window_t*, const( cef_size_t )* ) center_window;
        void function( cef_window_t* ) close;
        int function( cef_window_t* ) is_closed;
        void function( cef_window_t* ) activate;
        void function( cef_window_t* ) deactivate;
        int function( cef_window_t* ) is_active;
        void function( cef_window_t* ) bring_to_top;
        void function( cef_window_t*, int ) set_always_on_top;
        int function( cef_window_t* ) is_always_on_top;
        void function( cef_window_t* ) maximize;
        void function( cef_window_t* ) minimize;
        void function( cef_window_t* ) restore;
        void function( cef_window_t*, int ) set_fullscreen;
        int function( cef_window_t*) is_maximized;
        int function( cef_window_t* ) is_minimized;
        int function( cef_window_t* ) is_fullscreen;
        void function( cef_window_t*, const( cef_string_t )* ) set_title;
        cef_string_userfree_t function( cef_window_t* ) get_title;
        void function( cef_window_t*, cef_image_t* ) set_window_icon;
        cef_image_t* function( cef_window_t* ) get_window_icon;
        void function( cef_window_t*, cef_image_t* ) set_window_app_icon;
        cef_image_t* function( cef_window_t* ) get_window_app_icon;
        void function( cef_window_t*, cef_menu_model_t*, const( cef_point_t )* , cef_menu_anchor_position_t ) show_menu;
        void function( cef_window_t* ) cancel_menu;
        cef_display_t* function( cef_window_t* ) get_display;
        cef_rect_t function( cef_window_t* ) get_client_area_bounds_in_screen;
        void function( cef_window_t* , size_t, const( cef_draggable_region_t* ) ) set_draggable_regions;
        cef_window_handle_t function( cef_window_t* ) get_window_handle;
        void function( cef_window_t*, int, uint ) send_key_press;
        void function( cef_window_t*, int, int ) send_mouse_move;
        void function( cef_window_t*, cef_mouse_button_type_t, int, int ) send_mouse_events;
        void function( cef_window_t*, int, int, int, int, int ) set_accelerator;
        void function( cef_window_t*, int ) remove_accelerator;
        void function( cef_window_t* ) remove_all_accelerators;
    }
}

// views/cef_window_delegate_capi.h
struct cef_window_delegate_t {
    cef_panel_delegate_t base;
    extern( System ) @nogc nothrow {
        void function( cef_window_delegate_t*, cef_window_t* ) on_window_created;
        void function( cef_window_delegate_t*, cef_window_t* ) on_window_destroyed;
        cef_window_t* function( cef_window_delegate_t*, cef_window_t*, int*, int* ) get_parent_window;
        int function( cef_window_delegate_t*, cef_window_t* ) is_frameless;
        int function( cef_window_delegate_t*, cef_window_t* ) can_resize;
        int function( cef_window_delegate_t*, cef_window_t* ) can_maximize;
        int function( cef_window_delegate_t*, cef_window_t* ) can_minimize;
        int function( cef_window_delegate_t*, cef_window_t* ) can_close;
        int function( cef_window_delegate_t*, cef_window_t*, int ) on_accelerator;
        int function( cef_window_delegate_t*, cef_window_t*, const( cef_key_event_t )* ) on_key_event;
    }
}
}
