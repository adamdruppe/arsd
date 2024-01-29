/++
	This provides a kind of web template support, built on top of [arsd.dom] and [arsd.script], in support of [arsd.cgi].

	```html
		<main>
			<%=HTML some_var_with_html %>
			<%= some_var %>

			<if-true cond="whatever">
				whatever == true
			</if-true>
			<or-else>
				whatever == false
			</or-else>

			<for-each over="some_array" as="item" index="idx">
				<%= item %>
			</for-each>
			<or-else>
				there were no items.
			</or-else>

			<form>
				<!-- new on July 17, 2021 (dub v10.3) -->
				<hidden-form-data from="data_var" name="arg_name" />
			</form>

			<render-template file="partial.html" />

			<document-fragment></document-fragment>

			<script>
				var a = <%= some_var %>; // it will be json encoded in a script tag, so it can be safely used from Javascript
			</script>
		</main>
	```

	Functions available:
		`encodeURIComponent`, `formatDate`, `dayOfWeek`, `formatTime`, `filterKeys`

	History:
		Things inside script tag were added on January 7, 2022.

		This module was added to dub on September 11, 2023 (dub v11.2).

		It was originally written in July 2019 to support a demonstration of moving a ruby on rails app to D.
+/
module arsd.webtemplate;

// FIXME: make script exceptions show line from the template it was in too

import arsd.script;
import arsd.dom;

public import arsd.jsvar : var;

// FIXME: want to show additional info from the exception, neatly integrated, whenever possible.
class TemplateException : Exception {
	string templateName;
	var context;
	Exception e;
	this(string templateName, var context, Exception e) {
		this.templateName = templateName;
		this.context = context;
		this.e = e;

		super("Exception in template " ~ templateName ~ ": " ~ e.msg);
	}
}

void addDefaultFunctions(var context) {
	import std.conv;
	// FIXME: I prolly want it to just set the prototype or something

	/+
		foo |> filterKeys(["foo", "bar"]);

		It needs to match the filter, then if it is -pattern, it is removed and if it is +pattern, it is retained.

		First one that matches applies to the key, so the last one in the list is your default.

		Default is to reject. Putting a "*" at the end will keep everything not removed though.

		["-foo", "*"] // keep everything except foo
	+/
	context.filterKeys = function var(var f, string[] filters) {
		import std.path;
		var o = var.emptyObject;
		foreach(k, v; f) {
			bool keep = false;
			foreach(filter; filters) {
				if(filter.length == 0)
					throw new Exception("invalid filter");
				bool filterOff = filter[0] == '-';
				if(filterOff)
					filter = filter[1 .. $];
				if(globMatch(k.get!string, filter)) {
					keep = !filterOff;
					break;
				}
			}
			if(keep)
				o[k] = v;
		}
		return o;
	};

	context.encodeURIComponent = function string(var f) {
		import std.uri;
		return encodeComponent(f.get!string);
	};

	context.formatDate = function string(string s) {
		if(s.length < 10)
			return s;
		auto year = s[0 .. 4];
		auto month = s[5 .. 7];
		auto day = s[8 .. 10];

		return month ~ "/" ~ day ~ "/" ~ year;
	};

	context.dayOfWeek = function string(string s) {
		import std.datetime;
		return daysOfWeekFullNames[Date.fromISOExtString(s[0 .. 10]).dayOfWeek];
	};

	context.formatTime = function string(string s) {
		if(s.length < 20)
			return s;
		auto hour = s[11 .. 13].to!int;
		auto minutes = s[14 .. 16].to!int;
		auto seconds = s[17 .. 19].to!int;

		auto am = (hour >= 12) ? "PM" : "AM";
		if(hour > 12)
			hour -= 12;

		return hour.to!string ~ (minutes < 10 ? ":0" : ":") ~ minutes.to!string ~ " " ~ am;
	};

	// don't want checking meta or data to be an error
	if(context.meta == null)
		context.meta = var.emptyObject;
	if(context.data == null)
		context.data = var.emptyObject;
}

/++
	A loader object for reading raw template, so you can use something other than files if you like.

	See [TemplateLoader.forDirectory] to a pre-packaged class that implements a loader for a particular directory.

	History:
		Added December 11, 2023 (dub v11.3)
+/
interface TemplateLoader {
	/++
		This is the main method to look up a template name and return its HTML as a string.

		Typical implementation is to just `return std.file.readText(directory ~ name);`
	+/
	string loadTemplateHtml(string name);

	/++
		Returns a loader for files in the given directory.
	+/
	static TemplateLoader forDirectory(string directoryName) {
		if(directoryName.length && directoryName[$-1] != '/')
			directoryName ~= "/";

		return new class TemplateLoader {
			string loadTemplateHtml(string name) {
				import std.file;
				return readText(directoryName ~ name);
			}
		};
	}
}

/++
	Loads a template from the template directory, applies the given context variables, and returns the html document in dom format. You can use [Document.toString] to make a string.

	Parameters:
		templateName = the name of the main template to load. This is usually a .html filename in the `templates` directory (but see also the `loader` param)
		context = the global object available to scripts inside the template
		skeletonContext = the global object available to the skeleton template
		skeletonName = the name of the skeleton template to load. This is usually a .html filename in the `templates` directory (but see also the `loader` param), and the skeleton file has the boilerplate html and defines placeholders for the main template
		loader = a class that defines how to load templates by name. If you pass `null`, it uses a default implementation that loads files from the `templates/` directory.

	History:
		Parameter `loader` was added on December 11, 2023 (dub v11.3)
+/
Document renderTemplate(string templateName, var context = var.emptyObject, var skeletonContext = var.emptyObject, string skeletonName = null, TemplateLoader loader = null) {
	import arsd.cgi;

	if(loader is null)
		loader = TemplateLoader.forDirectory("templates/");

	try {
		addDefaultFunctions(context);
		addDefaultFunctions(skeletonContext);

		if(skeletonName.length == 0)
			skeletonName = "skeleton.html";

		auto skeleton = new Document(loader.loadTemplateHtml(skeletonName), true, true);
		auto document = new Document();
		document.parseSawAspCode = (string) => true; // enable adding <% %> to the dom
		document.parse("<root>" ~ loader.loadTemplateHtml(templateName) ~ "</root>", true, true);

		expandTemplate(skeleton.root, skeletonContext, loader);

		foreach(nav; skeleton.querySelectorAll("nav[data-relative-to]")) {
			auto r = nav.getAttribute("data-relative-to");
			foreach(a; nav.querySelectorAll("a")) {
				a.attrs.href = Uri(a.attrs.href).basedOn(Uri(r));// ~ a.attrs.href;
			}
		}

		expandTemplate(document.root, context, loader);

		// also do other unique elements and move them over.
		// and have some kind of <document-fragment> that can be just reduced when going out in the final result.

		// and try partials.

		auto templateMain = document.requireSelector(":root > main");
		if(templateMain.hasAttribute("body-class")) {
			skeleton.requireSelector("body").addClass(templateMain.getAttribute("body-class"));
			templateMain.removeAttribute("body-class");
		}

		skeleton.requireSelector("main").replaceWith(templateMain.removeFromTree);

		if(auto title = document.querySelector(":root > title"))
			skeleton.requireSelector(":root > head > title").innerHTML = title.innerHTML;

		// also allow top-level unique id replacements
		foreach(item; document.querySelectorAll(":root > [id]"))
			skeleton.requireElementById(item.id).replaceWith(item.removeFromTree);

		foreach(df; skeleton.querySelectorAll("document-fragment"))
			df.stripOut();

		debug
		skeleton.root.prependChild(new HtmlComment(null, templateName ~ " inside skeleton.html"));

		return skeleton;
	} catch(Exception e) {
		throw new TemplateException(templateName, context, e);
		//throw e;
	}
}

/++
	Shows how top-level things from the template are moved to their corresponding items on the  skeleton.
+/
unittest {
	// for the unittest, we want to inject a loader that uses plain strings instead of files.
	auto testLoader = new class TemplateLoader {
		string loadTemplateHtml(string name) {
			switch(name) {
				case "skeleton":
					return `
						<html>
							<head>
								<!-- you can define replaceable things with ids -->
								<!-- including <document-fragment>s which are stripped out when the template is finalized -->
								<document-fragment id="header-stuff" />
							</head>
							<body>
								<main></main>
							</body>
						</html>
					`;
				case "main":
					return `
						<main>Hello</main>
						<document-fragment id="header-stuff">
							<title>My title</title>
						</document-fragment>
					`;
				default: assert(0);
			}
		}
	};

	Document doc = renderTemplate("main", var.emptyObject, var.emptyObject, "skeleton", testLoader);

	assert(doc.querySelector("document-fragment") is null); // the <document-fragment> items are stripped out
	assert(doc.querySelector("title") !is null); // but the stuff from inside it is brought in
	assert(doc.requireSelector("main").textContent == "Hello"); // and the main from the template is moved to the skeelton
}

private void expandTemplate(Element root, var context, TemplateLoader loader) {
	import std.string;

	string replaceThingInString(string v) {
		auto idx = v.indexOf("<%=");
		if(idx == -1)
			return v;
		auto n = v[0 .. idx];
		auto r = v[idx + "<%=".length .. $];

		auto end = r.indexOf("%>");
		if(end == -1)
			throw new Exception("unclosed asp code in attribute");
		auto code = r[0 .. end];
		r = r[end + "%>".length .. $];

		import arsd.script;
		auto res = interpret(code, context).get!string;

		return n ~ res ~ replaceThingInString(r);
	}

	foreach(k, v; root.attributes) {
		if(k == "onrender") {
			continue;
		}

		v = replaceThingInString(v);

		root.setAttribute(k, v);
	}

	bool lastBoolResult;

	foreach(ele; root.children) {
		if(ele.tagName == "if-true") {
			auto fragment = new DocumentFragment(null);
			import arsd.script;
			auto got = interpret(ele.attrs.cond, context).opCast!bool;
			if(got) {
				ele.tagName = "root";
				expandTemplate(ele, context, loader);
				fragment.stealChildren(ele);
			}
			lastBoolResult = got;
			ele.replaceWith(fragment);
		} else if(ele.tagName == "or-else") {
			auto fragment = new DocumentFragment(null);
			if(!lastBoolResult) {
				ele.tagName = "root";
				expandTemplate(ele, context, loader);
				fragment.stealChildren(ele);
			}
			ele.replaceWith(fragment);
		} else if(ele.tagName == "for-each") {
			auto fragment = new DocumentFragment(null);
			var nc = var.emptyObject(context);
			lastBoolResult = false;
			auto got = interpret(ele.attrs.over, context);
			foreach(k, item; got) {
				lastBoolResult = true;
				nc[ele.attrs.as] = item;
				if(ele.attrs.index.length)
					nc[ele.attrs.index] = k;
				auto clone = ele.cloneNode(true);
				clone.tagName = "root"; // it certainly isn't a for-each anymore!
				expandTemplate(clone, nc, loader);

				fragment.stealChildren(clone);
			}
			ele.replaceWith(fragment);
		} else if(ele.tagName == "render-template") {
			import std.file;
			auto templateName = ele.getAttribute("file");
			auto document = new Document();
			document.parseSawAspCode = (string) => true; // enable adding <% %> to the dom
			document.parse("<root>" ~ loader.loadTemplateHtml(templateName) ~ "</root>", true, true);

			var obj = var.emptyObject;
			obj.prototype = context;

			// FIXME: there might be other data you pass from the parent...
			if(auto data = ele.getAttribute("data")) {
				obj["data"] = var.fromJson(data);
			}

			expandTemplate(document.root, obj, loader);

			auto fragment = new DocumentFragment(null);

			debug fragment.appendChild(new HtmlComment(null, templateName));
			fragment.stealChildren(document.root);
			debug fragment.appendChild(new HtmlComment(null, "end " ~ templateName));

			ele.replaceWith(fragment);
		} else if(ele.tagName == "hidden-form-data") {
			auto from = interpret(ele.attrs.from, context);
			auto name = ele.attrs.name;

			auto form = new Form(null);

			populateForm(form, from, name);

			auto fragment = new DocumentFragment(null);
			fragment.stealChildren(form);

			ele.replaceWith(fragment);
		} else if(auto asp = cast(AspCode) ele) {
			auto code = asp.source[1 .. $-1];
			auto fragment = new DocumentFragment(null);
			if(code[0] == '=') {
				import arsd.script;
				if(code.length > 5 && code[1 .. 5] == "HTML") {
					auto got = interpret(code[5 .. $], context);
					if(auto native = got.getWno!Element)
						fragment.appendChild(native);
					else
						fragment.innerHTML = got.get!string;
				} else {
					auto got = interpret(code[1 .. $], context).get!string;
					fragment.innerText = got;
				}
			}
			asp.replaceWith(fragment);
		} else if(ele.tagName == "script") {
			auto source = ele.innerHTML;
			string newCode;
			check_more:
			auto idx = source.indexOf("<%=");
			if(idx != -1) {
				newCode ~= source[0 .. idx];
				auto remaining = source[idx + 3 .. $];
				idx = remaining.indexOf("%>");
				if(idx == -1)
					throw new Exception("unclosed asp code in script");
				auto code = remaining[0 .. idx];

				auto data = interpret(code, context);
				newCode ~= data.toJson();

				source = remaining[idx + 2 .. $];
				goto check_more;
			}

			if(newCode is null)
				{} // nothing needed
			else {
				newCode ~= source;
				ele.innerRawSource = newCode;
			}
		} else {
			expandTemplate(ele, context, loader);
		}
	}

	if(root.hasAttribute("onrender")) {
		var nc = var.emptyObject(context);
		nc["this"] = wrapNativeObject(root);
		nc["this"]["populateFrom"] = delegate var(var this_, var[] args) {
			auto form = cast(Form) root;
			if(form is null) return this_;
			foreach(k, v; args[0]) {
				populateForm(form, v, k.get!string);
			}
			return this_;
		};
		interpret(root.getAttribute("onrender"), nc);

		root.removeAttribute("onrender");
	}
}

void populateForm(Form form, var obj, string name) {
	import std.string;

	if(obj.payloadType == var.Type.Object) {
		form.setValue(name, "");
		foreach(k, v; obj) {
			auto fn = name.replace("%", k.get!string);
			// should I unify structs and assoctiavite arrays?
			populateForm(form, v, fn ~ "["~k.get!string~"]");
			//populateForm(form, v, fn ~"."~k.get!string);
		}
	} else {
		//import std.stdio; writeln("SET ", name, " ", obj, " ", obj.payloadType);
		form.setValue(name, obj.get!string);
	}

}

/++
	Replaces `things[0]` with `things[1]` in `what` all at once.
	Returns the new string.

	History:
		Added February 12, 2022. I might move it later.
+/
string multiReplace(string what, string[] things...) {
	import std.string; // FIXME: indexOf not actually ideal but meh
	if(things.length == 0)
		return what;

	assert(things.length % 2 == 0);

	string n;

	while(what.length) {
		int nextIndex = cast(int) what.length;
		int nextThing = -1;

		foreach(i, thing; things) {
			if(i & 1)
				continue;

			auto idx = what.indexOf(thing);
			if(idx != -1 && idx < nextIndex) {
				nextIndex = cast(int) idx;
				nextThing = cast(int) i;
			}
		}

		if(nextThing == -1) {
			n ~= what;
			what = null;
		} else {
			n ~= what[0 .. nextIndex];
			what = what[nextIndex + things[nextThing].length .. $];
			n ~= things[nextThing + 1];
			continue;
		}
	}

	return n;
}

immutable daysOfWeekFullNames = [
	"Sunday",
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday"
];

/++
	UDA to put on a method when using [WebPresenterWithTemplateSupport]. Overrides default generic element formatting and instead uses the specified template name to render the return value.

	Inside the template, the value returned by the function will be available in the context as the variable `data`.
+/
struct Template {
	string name;
}
/++
	UDA to put on a method when using [WebPresenterWithTemplateSupport]. Overrides the default template skeleton file name.
+/
struct Skeleton {
	string name;
}

/++
	UDA to attach runtime metadata to a function. Will be available in the template.

	History:
		Added July 12, 2021
+/
struct meta {
	string name;
	string value;
}

/++
	Can be used as a return value from one of your own methods when rendering websites with [WebPresenterWithTemplateSupport].
+/
struct RenderTemplate {
	string name;
	var context = var.emptyObject;
	var skeletonContext = var.emptyObject;
	string skeletonName;
}


/++
	Make a class that inherits from this with your further customizations, or minimally:
	---
	class MyPresenter : WebPresenterWithTemplateSupport!MyPresenter { }
	---
+/
template WebPresenterWithTemplateSupport(CTRP) {
	import arsd.cgi;
	class WebPresenterWithTemplateSupport : WebPresenter!(CTRP) {
		override Element htmlContainer() {
			try {
				auto skeleton = renderTemplate("generic.html", var.emptyObject, var.emptyObject, "skeleton.html", templateLoader());
				return skeleton.requireSelector("main");
			} catch(Exception e) {
				auto document = new Document("<html><body><p>generic.html trouble: <span id=\"ghe\"></span></p> <main></main></body></html>");
				document.requireSelector("#ghe").textContent = e.msg;
				return document.requireSelector("main");
			}
		}

		static struct Meta {
			typeof(null) at;
			string templateName;
			string skeletonName;
			string[string] meta;
			Form function(WebPresenterWithTemplateSupport presenter) automaticForm;
			alias at this;
		}
		template methodMeta(alias method) {
			static Meta helper() {
				Meta ret;

				// ret.at = typeof(super).methodMeta!method;

				foreach(attr; __traits(getAttributes, method))
					static if(is(typeof(attr) == Template))
						ret.templateName = attr.name;
					else static if(is(typeof(attr) == Skeleton))
						ret.skeletonName = attr.name;
					else static if(is(typeof(attr) == .meta))
						ret.meta[attr.name] = attr.value;

				ret.automaticForm = function Form(WebPresenterWithTemplateSupport presenter) {
					return presenter.createAutomaticFormForFunction!(method, typeof(&method))(null);
				};

				return ret;
			}
			enum methodMeta = helper();
		}

		/// You can override this
		void addContext(Cgi cgi, var ctx) {}

		/++
			You can override this. The default is "templates/". Your returned string must end with '/'.
			(in future versions it will probably allow a null return too, but right now it must be a /).

			History:
				Added December 6, 2023 (dub v11.3)
		+/
		TemplateLoader templateLoader() {
			return null;
		}

		void presentSuccessfulReturnAsHtml(T : RenderTemplate)(Cgi cgi, T ret, Meta meta) {
			addContext(cgi, ret.context);
			auto skeleton = renderTemplate(ret.name, ret.context, ret.skeletonContext, ret.skeletonName, templateLoader());
			cgi.setResponseContentType("text/html; charset=utf8");
			cgi.gzipResponse = true;
			cgi.write(skeleton.toString(), true);
		}

		void presentSuccessfulReturnAsHtml(T)(Cgi cgi, T ret, Meta meta) {
			if(meta.templateName.length) {
				var sobj = var.emptyObject;

				var obj = var.emptyObject;

				obj.data = ret;

				/+
				sobj.meta = var.emptyObject;
				foreach(k,v; meta.meta)
					sobj.meta[k] = v;
				+/

				obj.meta = var.emptyObject;
				foreach(k,v; meta.meta)
					obj.meta[k] = v;

				obj.meta.currentPath = cgi.pathInfo;
				obj.meta.automaticForm = { return meta.automaticForm(this).toString; };

				presentSuccessfulReturnAsHtml(cgi, RenderTemplate(meta.templateName, obj, sobj, meta.skeletonName), meta);
			} else
				super.presentSuccessfulReturnAsHtml(cgi, ret, meta);
		}
	}
}

/++
	Serves up a directory of template files as html. This is meant to be used for some near-static html in the midst of an application, giving you a little bit of dynamic content and conveniences with the ease of editing files without recompiles.

	Parameters:
		urlPrefix = the url prefix to trigger this handler, relative to the current dispatcher base
		directory = the directory, under the template directory, to find the template files
		skeleton = the name of the skeleton file inside the template directory
		extension = the file extension to add to the url name to get the template name

	To get the filename of the template from the url, it will:

	1) Strip the url prefixes off to get just the filename

	2) Concatenate the directory with the template directory

	3) Add the extension to the givenname

	$(PITFALL
		The `templateDirectory` parameter may be removed or changed in the near future.
	)

	History:
		Added July 28, 2021 (documented dub v11.0)
+/
auto serveTemplateDirectory()(string urlPrefix, string directory = null, string skeleton = null, string extension = ".html", string templateDirectory = "templates/") {
	import arsd.cgi;
	import std.file;

	assert(urlPrefix[0] == '/');
	assert(urlPrefix[$-1] == '/');

	assert(templateDirectory[$-1] == '/');

	static struct DispatcherDetails {
		string directory;
		string skeleton;
		string extension;
		string templateDirectory;
	}

	if(directory is null)
		directory = urlPrefix[1 .. $];

	if(directory.length == 0)
		directory = "./";

	assert(directory[$-1] == '/');

	static bool internalHandler(string urlPrefix, Cgi cgi, Object presenter, DispatcherDetails details) {
		auto file = cgi.pathInfo[urlPrefix.length .. $];
		if(file.indexOf("/") != -1 || file.indexOf("\\") != -1)
			return false;

		auto fn = details.templateDirectory ~ details.directory ~ file ~ details.extension;
		if(std.file.exists(fn)) {
			cgi.setResponseExpiresRelative(600, true); // 10 minute cache expiration by default, FIXME it should be configurable
			auto doc = renderTemplate(fn[details.templateDirectory.length.. $], var.emptyObject, var.emptyObject, details.skeleton, TemplateLoader.forDirectory(details.templateDirectory));
			cgi.gzipResponse = true;
			cgi.write(doc.toString, true);
			return true;
		} else {
			return false;
		}
	}

	return DispatcherDefinition!(internalHandler, DispatcherDetails)(urlPrefix, false, DispatcherDetails(directory, skeleton, extension, templateDirectory));
}
