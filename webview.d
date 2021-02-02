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

version(linux):

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

version(linux)

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
