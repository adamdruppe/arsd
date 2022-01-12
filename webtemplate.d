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

			<for-each over="some_array" as="item">
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

			<script>
				var a = <%= some_var %>; // it will be json encoded in a script tag, so it can be safely used from Javascript
			</script>
		</main>
	```

	Functions available:
		`encodeURIComponent`, `formatDate`, `dayOfWeek`, `formatTime`

	History:
		Things inside script tag were added on January 7, 2022.
+/
module arsd.webtemplate;

// FIXME: make script exceptions show line from the template it was in too

import arsd.script;
import arsd.dom;

public import arsd.jsvar : var;

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

Document renderTemplate(string templateName, var context = var.emptyObject, var skeletonContext = var.emptyObject) {
	import std.file;
	import arsd.cgi;

	try {
		addDefaultFunctions(context);
		addDefaultFunctions(skeletonContext);

		auto skeleton = new Document(readText("templates/skeleton.html"), true, true);
		auto document = new Document();
		document.parseSawAspCode = (string) => true; // enable adding <% %> to the dom
		document.parse("<root>" ~ readText("templates/" ~ templateName) ~ "</root>", true, true);

		expandTemplate(skeleton.root, skeletonContext);

		foreach(nav; skeleton.querySelectorAll("nav[data-relative-to]")) {
			auto r = nav.getAttribute("data-relative-to");
			foreach(a; nav.querySelectorAll("a")) {
				a.attrs.href = Uri(a.attrs.href).basedOn(Uri(r));// ~ a.attrs.href;
			}
		}

		expandTemplate(document.root, context);

		// also do other unique elements and move them over.
		// and try partials.

		auto templateMain = document.requireSelector(":root > main");
		if(templateMain.hasAttribute("body-class")) {
			skeleton.requireSelector("body").addClass(templateMain.getAttribute("body-class"));
			templateMain.removeAttribute("body-class");
		}

		skeleton.requireSelector("main").replaceWith(templateMain.removeFromTree);
		if(auto title = document.querySelector(":root > title"))
			skeleton.requireSelector(":root > head > title").innerHTML = title.innerHTML;

		debug
		skeleton.root.prependChild(new HtmlComment(null, templateName ~ " inside skeleton.html"));

		return skeleton;
	} catch(Exception e) {
		throw new TemplateException(templateName, context, e);
		//throw e;
	}
}

// I don't particularly like this
void expandTemplate(Element root, var context) {
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
				expandTemplate(ele, context);
				fragment.stealChildren(ele);
			}
			lastBoolResult = got;
			ele.replaceWith(fragment);
		} else if(ele.tagName == "or-else") {
			auto fragment = new DocumentFragment(null);
			if(!lastBoolResult) {
				ele.tagName = "root";
				expandTemplate(ele, context);
				fragment.stealChildren(ele);
			}
			ele.replaceWith(fragment);
		} else if(ele.tagName == "for-each") {
			auto fragment = new DocumentFragment(null);
			var nc = var.emptyObject(context);
			lastBoolResult = false;
			auto got = interpret(ele.attrs.over, context);
			foreach(item; got) {
				lastBoolResult = true;
				nc[ele.attrs.as] = item;
				auto clone = ele.cloneNode(true);
				clone.tagName = "root"; // it certainly isn't a for-each anymore!
				expandTemplate(clone, nc);

				fragment.stealChildren(clone);
			}
			ele.replaceWith(fragment);
		} else if(ele.tagName == "render-template") {
			import std.file;
			auto templateName = ele.getAttribute("file");
			auto document = new Document();
			document.parseSawAspCode = (string) => true; // enable adding <% %> to the dom
			document.parse("<root>" ~ readText("templates/" ~ templateName) ~ "</root>", true, true);

			expandTemplate(document.root, context);

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
				newCode = source[0 .. idx];
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
			expandTemplate(ele, context);
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
			auto skeleton = renderTemplate("generic.html");
			return skeleton.requireSelector("main");
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

		void presentSuccessfulReturnAsHtml(T : RenderTemplate)(Cgi cgi, T ret, Meta meta) {
			addContext(cgi, ret.context);
			auto skeleton = renderTemplate(ret.name, ret.context, ret.skeletonContext);
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

				presentSuccessfulReturnAsHtml(cgi, RenderTemplate(meta.templateName, obj, sobj), meta);
			} else
				super.presentSuccessfulReturnAsHtml(cgi, ret, meta);
		}
	}
}

auto serveTemplateDirectory()(string urlPrefix, string directory = null, string skeleton = null, string extension = ".html") {
	import arsd.cgi;
	import std.file;

	assert(urlPrefix[0] == '/');
	assert(urlPrefix[$-1] == '/');

	static struct DispatcherDetails {
		string directory;
		string skeleton;
		string extension;
	}

	if(directory is null)
		directory = urlPrefix[1 .. $];

	assert(directory[$-1] == '/');

	static bool internalHandler(string urlPrefix, Cgi cgi, Object presenter, DispatcherDetails details) {
		auto file = cgi.pathInfo[urlPrefix.length .. $];
		if(file.indexOf("/") != -1 || file.indexOf("\\") != -1)
			return false;

		auto fn = "templates/" ~ details.directory ~ file ~ details.extension;
		if(std.file.exists(fn)) {
			cgi.setCache(true);
			auto doc = renderTemplate(fn["templates/".length.. $]);
			cgi.gzipResponse = true;
			cgi.write(doc.toString, true);
			return true;
		} else {
			return false;
		}
	}

	return DispatcherDefinition!(internalHandler, DispatcherDetails)(urlPrefix, false, DispatcherDetails(directory, skeleton, extension));
}
