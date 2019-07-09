/++
	This provides a kind of web template support, built on top of [arsd.dom] and [arsd.script], in support of [arsd.cgi].
+/
module arsd.webtemplate;

// FIXME: make script exceptions show line from the template it was in too

import arsd.script;
import arsd.dom;

public import arsd.jsvar : var;

struct RenderTemplate {
	string name;
	var context = var.emptyObject;
	var skeletonContext = var.emptyObject;
}

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

Document renderTemplate(string templateName, var context = var.emptyObject, var skeletonContext = var.emptyObject) {
	import std.file;
	import arsd.cgi;

	try {
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
			return daysOfWeekFullNames[DateTime.fromISOExtString(s).dayOfWeek];
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
			auto got = interpret(ele.attrs.cond, context).get!bool;
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
		} else {
			expandTemplate(ele, context);
		}
	}

	if(root.hasAttribute("onrender")) {
		var nc = var.emptyObject(context);
		nc["this"] = wrapNativeObject(root);
		nc["this"]["populateFrom"]._function = delegate var(var this_, var[] args) {
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
		foreach(k, v; obj) {
			auto fn = name.replace("%", k.get!string);
			populateForm(form, v, fn ~ "["~k.get!string~"]");
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


/+
mixin template WebTemplatePresenterSupport() {

}
+/
