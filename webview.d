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

version(Windows)
	version=WEBVIEW_EDGE;
else version(linux)
	version=WEBVIEW_GTK;
else version(OSX)
	version=WEBVIEW_COCOA;

version(WEBVIEW_MSHTML)
	version=WindowsWindow;
version(WEBVIEW_EDGE)
	version=WindowsWindow;

version(Demo)
void main() {
	auto wv = new WebView(true, null);
	wv.navigate("http://dpldocs.info/");
	wv.setTitle("omg a D webview");
	wv.setSize(500, 500, true);
	wv.eval("console.log('just testing');");
	wv.run();
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

} else version(WindowsWindow) {
/+

	//
	// ====================================================================
	//
	// This implementation uses Win32 API to create a native window. It can
	// use either MSHTML or EdgeHTML backend as a browser engine.
	//
	// ====================================================================
	//

	#define WIN32_LEAN_AND_MEAN
	#include <windows.h>

	pragma(lib, "user32");

	class browser_window {
	public:
	  browser_window(msg_cb_t cb, void *window) : m_cb(cb) {
	    if (window is null) {
	      WNDCLASSEX wc;
	      ZeroMemory(&wc, sizeof(WNDCLASSEX));
	      wc.cbSize = sizeof(WNDCLASSEX);
	      wc.hInstance = GetModuleHandle(null);
	      wc.lpszClassName = "webview";
	      wc.lpfnWndProc =
		  (WNDPROC)(+[](HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) -> int {
		    auto w = (browser_window *)GetWindowLongPtr(hwnd, GWLP_USERDATA);
		    switch (msg) {
		    case WM_SIZE:
		      w->resize();
		      break;
		    case WM_CLOSE:
		      DestroyWindow(hwnd);
		      break;
		    case WM_DESTROY:
		      w->terminate();
		      break;
		    default:
		      return DefWindowProc(hwnd, msg, wp, lp);
		    }
		    return 0;
		  });
	      RegisterClassEx(&wc);
	      m_window = CreateWindow("webview", "", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
				      CW_USEDEFAULT, 640, 480, null, null,
				      GetModuleHandle(null), null);
	      SetWindowLongPtr(m_window, GWLP_USERDATA, (LONG_PTR)this);
	    } else {
	      m_window = *(static_cast<HWND *>(window));
	    }

	    ShowWindow(m_window, SW_SHOW);
	    UpdateWindow(m_window);
	    SetFocus(m_window);
	  }

	  void run() {
	    MSG msg;
	    BOOL res;
	    while ((res = GetMessage(&msg, null, 0, 0)) != -1) {
	      if (msg.hwnd) {
		TranslateMessage(&msg);
		DispatchMessage(&msg);
		continue;
	      }
	      if (msg.message == WM_APP) {
		auto f = (dispatch_fn_t *)(msg.lParam);
		(*f)();
		delete f;
	      } else if (msg.message == WM_QUIT) {
		return;
	      }
	    }
	  }

	  void terminate() { PostQuitMessage(0); }
	  void dispatch(dispatch_fn_t f) {
	    PostThreadMessage(m_main_thread, WM_APP, 0, (LPARAM) new dispatch_fn_t(f));
	  }

	  void setTitle(const char *title) { SetWindowText(m_window, title); }

	  void setSize(int width, int height, bool resizable) {
	    RECT r;
	    r.left = 50;
	    r.top = 50;
	    r.right = width;
	    r.bottom = height;
	    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, 0);
	    SetWindowPos(m_window, null, r.left, r.top, r.right - r.left,
			 r.bottom - r.top,
			 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
	  }

	protected:
	  virtual void resize() {}
	  HWND m_window;
	  DWORD m_main_thread = GetCurrentThreadId();
	  msg_cb_t m_cb;
	};
+/
}

version(WEBVIEW_MSHTML) {
/+
	#include <exdisp.h>
	#include <exdispid.h>
	#include <mshtmhst.h>
	#include <mshtml.h>
	#include <shobjidl.h>
	pragma(lib, "ole32");
	pragma(lib, "oleaut32");

	#define DISPID_EXTERNAL_INVOKE 0x1000

	class browser_engine : public browser_window,
			       public IOleClientSite,
			       public IOleInPlaceSite,
			       public IOleInPlaceFrame,
			       public IDocHostUIHandler,
			       public DWebBrowserEvents2 {
	public:
	  browser_engine(msg_cb_t cb, bool dbg, void *window)
	      : browser_window(cb, window) {
	    RECT rect;
	    LPCLASSFACTORY cf = null;
	    IOleObject *obj = null;

	    fix_ie_compat_mode();

	    OleInitialize(null);
	    CoGetClassObject(CLSID_WebBrowser,
			     CLSCTX_INPROC_SERVER | CLSCTX_INPROC_HANDLER, null,
			     IID_IClassFactory, (void **)&cf);
	    cf->CreateInstance(null, IID_IOleObject, (void **)&obj);
	    cf->Release();

	    obj->SetClientSite(this);
	    OleSetContainedObject(obj, TRUE);
	    GetWindowRect(m_window, &rect);
	    obj->DoVerb(OLEIVERB_INPLACEACTIVATE, null, this, -1, m_window, &rect);
	    obj->QueryInterface(IID_IWebBrowser2, (void **)&m_webview);

	    IConnectionPointContainer *cpc;
	    IConnectionPoint *cp;
	    DWORD cookie;
	    m_webview->QueryInterface(IID_IConnectionPointContainer, (void **)&cpc);
	    cpc->FindConnectionPoint(DIID_DWebBrowserEvents2, &cp);
	    cpc->Release();
	    cp->Advise(static_cast<IOleClientSite *>(this), &cookie);

	    resize();
	    navigate("about:blank");
	  }

	  ~browser_engine() { OleUninitialize(); }

	  void navigate(const char *url) {
	    VARIANT v;
	    DWORD size = MultiByteToWideChar(CP_UTF8, 0, url, -1, 0, 0);
	    WCHAR *ws = (WCHAR *)GlobalAlloc(GMEM_FIXED, sizeof(WCHAR) * size);
	    MultiByteToWideChar(CP_UTF8, 0, url, -1, ws, size);
	    VariantInit(&v);
	    v.vt = VT_BSTR;
	    v.bstrVal = SysAllocString(ws);
	    m_webview->Navigate2(&v, null, null, null, null);
	    VariantClear(&v);
	  }

	  void eval(const char *js) {
	    // TODO
	  }

	private:
	  IWebBrowser2 *m_webview;

	  int fix_ie_compat_mode() {
	    const char *WEBVIEW_KEY_FEATURE_BROWSER_EMULATION =
		"Software\\Microsoft\\Internet "
		"Explorer\\Main\\FeatureControl\\FEATURE_BROWSER_EMULATION";
	    HKEY hKey;
	    DWORD ie_version = 11000;
	    TCHAR appname[MAX_PATH + 1];
	    TCHAR *p;
	    if (GetModuleFileName(null, appname, MAX_PATH + 1) == 0) {
	      return -1;
	    }
	    for (p = &appname[strlen(appname) - 1]; p != appname && *p != '\\'; p--) {
	    }
	    p++;
	    if (RegCreateKey(HKEY_CURRENT_USER, WEBVIEW_KEY_FEATURE_BROWSER_EMULATION,
			     &hKey) != ERROR_SUCCESS) {
	      return -1;
	    }
	    if (RegSetValueEx(hKey, p, 0, REG_DWORD, (BYTE *)&ie_version,
			      sizeof(ie_version)) != ERROR_SUCCESS) {
	      RegCloseKey(hKey);
	      return -1;
	    }
	    RegCloseKey(hKey);
	    return 0;
	  }

	  // Inheruted via browser_window
	  void resize() override {
	    RECT rect;
	    GetClientRect(m_window, &rect);
	    m_webview->put_Left(0);
	    m_webview->put_Top(0);
	    m_webview->put_Width(rect.right);
	    m_webview->put_Height(rect.bottom);
	    m_webview->put_Visible(VARIANT_TRUE);
	  }

	  // Inherited via IUnknown
	  ULONG __stdcall AddRef(void) override { return 1; }
	  ULONG __stdcall Release(void) override { return 1; }
	  HRESULT __stdcall QueryInterface(REFIID riid, void **obj) override {
	    if (riid == IID_IUnknown || riid == IID_IOleClientSite) {
	      *obj = static_cast<IOleClientSite *>(this);
	      return S_OK;
	    }
	    if (riid == IID_IOleInPlaceSite) {
	      *obj = static_cast<IOleInPlaceSite *>(this);
	      return S_OK;
	    }
	    if (riid == IID_IDocHostUIHandler) {
	      *obj = static_cast<IDocHostUIHandler *>(this);
	      return S_OK;
	    }
	    if (riid == IID_IDispatch || riid == DIID_DWebBrowserEvents2) {
	      *obj = static_cast<IDispatch *>(this);
	      return S_OK;
	    }
	    *obj = null;
	    return E_NOINTERFACE;
	  }

	  // Inherited via IOleClientSite
	  HRESULT __stdcall SaveObject(void) override { return E_NOTIMPL; }
	  HRESULT __stdcall GetMoniker(DWORD dwAssign, DWORD dwWhichMoniker,
				       IMoniker **ppmk) override {
	    return E_NOTIMPL;
	  }
	  HRESULT __stdcall GetContainer(IOleContainer **ppContainer) override {
	    *ppContainer = null;
	    return E_NOINTERFACE;
	  }
	  HRESULT __stdcall ShowObject(void) override { return S_OK; }
	  HRESULT __stdcall OnShowWindow(BOOL fShow) override { return S_OK; }
	  HRESULT __stdcall RequestNewObjectLayout(void) override { return E_NOTIMPL; }

	  // Inherited via IOleInPlaceSite
	  HRESULT __stdcall GetWindow(HWND *phwnd) override {
	    *phwnd = m_window;
	    return S_OK;
	  }
	  HRESULT __stdcall ContextSensitiveHelp(BOOL fEnterMode) override {
	    return E_NOTIMPL;
	  }
	  HRESULT __stdcall CanInPlaceActivate(void) override { return S_OK; }
	  HRESULT __stdcall OnInPlaceActivate(void) override { return S_OK; }
	  HRESULT __stdcall OnUIActivate(void) override { return S_OK; }
	  HRESULT __stdcall GetWindowContext(
	      IOleInPlaceFrame **ppFrame, IOleInPlaceUIWindow **ppDoc,
	      LPRECT lprcPosRect, LPRECT lprcClipRect,
	      LPOLEINPLACEFRAMEINFO lpFrameInfo) override {
	    *ppFrame = static_cast<IOleInPlaceFrame *>(this);
	    *ppDoc = null;
	    lpFrameInfo->fMDIApp = FALSE;
	    lpFrameInfo->hwndFrame = m_window;
	    lpFrameInfo->haccel = 0;
	    lpFrameInfo->cAccelEntries = 0;
	    return S_OK;
	  }
	  HRESULT __stdcall Scroll(SIZE scrollExtant) override { return E_NOTIMPL; }
	  HRESULT __stdcall OnUIDeactivate(BOOL fUndoable) override { return S_OK; }
	  HRESULT __stdcall OnInPlaceDeactivate(void) override { return S_OK; }
	  HRESULT __stdcall DiscardUndoState(void) override { return E_NOTIMPL; }
	  HRESULT __stdcall DeactivateAndUndo(void) override { return E_NOTIMPL; }
	  HRESULT __stdcall OnPosRectChange(LPCRECT lprcPosRect) override {
	    IOleInPlaceObject *inplace;
	    m_webview->QueryInterface(IID_IOleInPlaceObject, (void **)&inplace);
	    inplace->SetObjectRects(lprcPosRect, lprcPosRect);
	    return S_OK;
	  }

	  // Inherited via IDocHostUIHandler
	  HRESULT __stdcall ShowContextMenu(DWORD dwID, POINT *ppt,
					    IUnknown *pcmdtReserved,
					    IDispatch *pdispReserved) override {
	    return S_OK;
	  }
	  HRESULT __stdcall GetHostInfo(DOCHOSTUIINFO *pInfo) override {
	    pInfo->dwDoubleClick = DOCHOSTUIDBLCLK_DEFAULT;
	    pInfo->dwFlags = DOCHOSTUIFLAG_NO3DBORDER;
	    return S_OK;
	  }
	  HRESULT __stdcall ShowUI(DWORD dwID, IOleInPlaceActiveObject *pActiveObject,
				   IOleCommandTarget *pCommandTarget,
				   IOleInPlaceFrame *pFrame,
				   IOleInPlaceUIWindow *pDoc) override {
	    return S_OK;
	  }
	  HRESULT __stdcall HideUI(void) override { return S_OK; }
	  HRESULT __stdcall UpdateUI(void) override { return S_OK; }
	  HRESULT __stdcall EnableModeless(BOOL fEnable) override { return S_OK; }
	  HRESULT __stdcall OnDocWindowActivate(BOOL fActivate) override {
	    return S_OK;
	  }
	  HRESULT __stdcall OnFrameWindowActivate(BOOL fActivate) override {
	    return S_OK;
	  }
	  HRESULT __stdcall ResizeBorder(LPCRECT prcBorder,
					 IOleInPlaceUIWindow *pUIWindow,
					 BOOL fRameWindow) override {
	    return S_OK;
	  }
	  HRESULT __stdcall GetOptionKeyPath(LPOLESTR *pchKey, DWORD dw) override {
	    return S_FALSE;
	  }
	  HRESULT __stdcall GetDropTarget(IDropTarget *pDropTarget,
					  IDropTarget **ppDropTarget) override {
	    return E_NOTIMPL;
	  }
	  HRESULT __stdcall GetExternal(IDispatch **ppDispatch) override {
	    *ppDispatch = static_cast<IDispatch *>(this);
	    return S_OK;
	  }
	  HRESULT __stdcall TranslateUrl(DWORD dwTranslate, LPWSTR pchURLIn,
					 LPWSTR *ppchURLOut) override {
	    *ppchURLOut = null;
	    return S_FALSE;
	  }
	  HRESULT __stdcall FilterDataObject(IDataObject *pDO,
					     IDataObject **ppDORet) override {
	    *ppDORet = null;
	    return S_FALSE;
	  }
	  HRESULT __stdcall TranslateAcceleratorA(LPMSG lpMsg,
						  const GUID *pguidCmdGroup,
						  DWORD nCmdID) {
	    return S_FALSE;
	  }

	  // Inherited via IOleInPlaceFrame
	  HRESULT __stdcall GetBorder(LPRECT lprectBorder) override { return S_OK; }
	  HRESULT __stdcall RequestBorderSpace(LPCBORDERWIDTHS pborderwidths) override {
	    return S_OK;
	  }
	  HRESULT __stdcall SetBorderSpace(LPCBORDERWIDTHS pborderwidths) override {
	    return S_OK;
	  }
	  HRESULT __stdcall SetActiveObject(IOleInPlaceActiveObject *pActiveObject,
					    LPCOLESTR pszObjName) override {
	    return S_OK;
	  }
	  HRESULT __stdcall InsertMenus(HMENU hmenuShared,
					LPOLEMENUGROUPWIDTHS lpMenuWidths) override {
	    return S_OK;
	  }
	  HRESULT __stdcall SetMenu(HMENU hmenuShared, HOLEMENU holemenu,
				    HWND hwndActiveObject) override {
	    return S_OK;
	  }
	  HRESULT __stdcall RemoveMenus(HMENU hmenuShared) override { return S_OK; }
	  HRESULT __stdcall SetStatusText(LPCOLESTR pszStatusText) override {
	    return S_OK;
	  }
	  HRESULT __stdcall TranslateAcceleratorA(LPMSG lpmsg, WORD wID) {
	    return S_OK;
	  }

	  // Inherited via IDispatch
	  HRESULT __stdcall GetTypeInfoCount(UINT *pctinfo) override { return S_OK; }
	  HRESULT __stdcall GetTypeInfo(UINT iTInfo, LCID lcid,
					ITypeInfo **ppTInfo) override {
	    return S_OK;
	  }
	  HRESULT __stdcall GetIDsOfNames(REFIID riid, LPOLESTR *rgszNames, UINT cNames,
					  LCID lcid, DISPID *rgDispId) override {
	    *rgDispId = DISPID_EXTERNAL_INVOKE;
	    return S_OK;
	  }
	  HRESULT __stdcall Invoke(DISPID dispIdMember, REFIID riid, LCID lcid,
				   WORD wFlags, DISPPARAMS *pDispParams,
				   VARIANT *pVarResult, EXCEPINFO *pExcepInfo,
				   UINT *puArgErr) override {
	    if (dispIdMember == DISPID_NAVIGATECOMPLETE2) {
	    } else if (dispIdMember == DISPID_DOCUMENTCOMPLETE) {
	    } else if (dispIdMember == DISPID_EXTERNAL_INVOKE) {
	    }
	    return S_OK;
	  }
	};
+/
} else version(WEBVIEW_EDGE) {
/+
	#include <objbase.h>
	#include <winrt/Windows.Foundation.h>
	#include <winrt/Windows.Web.UI.Interop.h>

	#pragma comment(lib, "windowsapp")

	using namespace winrt;
	using namespace Windows::Foundation;
	using namespace Windows::Web::UI;
	using namespace Windows::Web::UI::Interop;

	class browser_engine : public browser_window {
	public:
	  browser_engine(msg_cb_t cb, bool dbg, void *window)
	      : browser_window(cb, window) {
	    init_apartment(winrt::apartment_type::single_threaded);
	    m_process = WebViewControlProcess();
	    auto op = m_process.CreateWebViewControlAsync(
		reinterpret_cast<int64_t>(m_window), Rect());
	    if (op.Status() != AsyncStatus::Completed) {
	      handle h(CreateEvent(null, false, false, null));
	      op.Completed([h = h.get()](auto, auto) { SetEvent(h); });
	      HANDLE hs[] = {h.get()};
	      DWORD i;
	      CoWaitForMultipleHandles(COWAIT_DISPATCH_WINDOW_MESSAGES |
					   COWAIT_DISPATCH_CALLS |
					   COWAIT_INPUTAVAILABLE,
				       INFINITE, 1, hs, &i);
	    }
	    m_webview = op.GetResults();
	    m_webview.Settings().IsScriptNotifyAllowed(true);
	    m_webview.IsVisible(true);
	    m_webview.ScriptNotify([=](auto const &sender, auto const &args) {
	      std::string s = winrt::to_string(args.Value());
	      m_cb(s.c_str());
	    });
	    m_webview.NavigationStarting([=](auto const &sender, auto const &args) {
	      m_webview.AddInitializeScript(winrt::to_hstring(init_js));
	    });
	    init("window.external.invoke = s => window.external.notify(s)");
	    resize();
	  }

	  void navigate(const char *url) {
	    Uri uri(winrt::to_hstring(url));
	    // TODO: if url starts with 'data:text/html,' prefix then use it as a string
	    m_webview.Navigate(uri);
	    // m_webview.NavigateToString(winrt::to_hstring(url));
	  }
	  void init(const char *js) {
	    init_js = init_js + "(function(){" + js + "})();";
	  }
	  void eval(const char *js) {
	    m_webview.InvokeScriptAsync(
		L"eval", single_threaded_vector<hstring>({winrt::to_hstring(js)}));
	  }

	private:
	  void resize() {
	    RECT r;
	    GetClientRect(m_window, &r);
	    Rect bounds(r.left, r.top, r.right - r.left, r.bottom - r.top);
	    m_webview.Bounds(bounds);
	  }
	  WebViewControlProcess m_process;
	  WebViewControl m_webview = null;
	  std::string init_js = "";
	};
+/
}

