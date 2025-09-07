/**
	This module includes functions to work with HTML and CSS in a more specialized manner than [arsd.dom]. Most of this is obsolete from my really old D web stuff, but there's still some useful stuff. View source before you decide to use it, as the implementations may suck more than you want to use.

	It publically imports the DOM module to get started.
	Then it adds a number of functions to enhance html
	DOM documents and make other changes, like scripts
	and stylesheets.
*/
module arsd.html;

import arsd.core : encodeUriComponent;

import std.string : indexOf, startsWith, endsWith, strip;

public import arsd.dom;
import arsd.color;

import std.array;
import std.string;
import std.variant;
import core.vararg;
import std.exception;


/// This is a list of features you can allow when using the sanitizedHtml function.
enum HtmlFeatures : uint {
	images = 1, 	/// The <img> tag
	links = 2, 	/// <a href=""> tags
	css = 4, 	/// Inline CSS
	cssLinkedResources = 8, // FIXME: implement this
	video = 16, 	/// The html5 <video> tag. autoplay is always stripped out.
	audio = 32, 	/// The html5 <audio> tag. autoplay is always stripped out.
	objects = 64, 	/// The <object> tag, which can link to many things, including Flash.
	iframes = 128, 	/// The <iframe> tag. sandbox and restrict attributes are always added.
	classes = 256, 	/// The class="" attribute
	forms = 512, 	/// HTML forms
}

/// The things to allow in links, images, css, and aother urls.
/// FIXME: implement this for better flexibility
enum UriFeatures : uint {
	http, 		/// http:// protocol absolute links
	https, 		/// https:// protocol absolute links
	data, 		/// data: url links to embed content. On some browsers (old Firefoxes) this was a security concern.
	ftp, 		/// ftp:// protocol links
	relative, 	/// relative links to the current location. You might want to rebase them.
	anchors 	/// #anchor links
}

string[] htmlTagWhitelist = [
	"span", "div",
	"p", "br",
	"b", "i", "u", "s", "big", "small", "sub", "sup", "strong", "em", "tt", "blockquote", "cite", "ins", "del", "strike",
	"ol", "ul", "li", "dl", "dt", "dd",
	"q",
	"table", "caption", "tr", "td", "th", "col", "thead", "tbody", "tfoot",
	"hr",
	"h1", "h2", "h3", "h4", "h5", "h6",
	"abbr",

	"img", "object", "audio", "video", "a", "source", // note that these usually *are* stripped out - see HtmlFeatures-  but this lets them get into stage 2

	"form", "input", "textarea", "legend", "fieldset", "label", // ditto, but with HtmlFeatures.forms
	// style isn't here
];

string[] htmlAttributeWhitelist = [
	// style isn't here
		/*
		if style, expression must be killed
		all urls must be checked for javascript and/or vbscript
		imports must be killed
		*/
	"style",

	"colspan", "rowspan",
	"title", "alt", "class",

	"href", "src", "type", "name",
	"id",
	"method", "enctype", "value", "type", // for forms only FIXME

	"align", "valign", "width", "height",
];

/// This returns an element wrapping sanitized content, using a whitelist for html tags and attributes,
/// and a blacklist for css. Javascript is never allowed.
///
/// It scans all URLs it allows and rejects
///
/// You can tweak the allowed features with the HtmlFeatures enum.
///
/// Note: you might want to use innerText for most user content. This is meant if you want to
/// give them a big section of rich text.
///
/// userContent should just be a basic div, holding the user's actual content.
///
/// FIXME: finish writing this
Element sanitizedHtml(/*in*/ Element userContent, string idPrefix = null, HtmlFeatures allow = HtmlFeatures.links | HtmlFeatures.images | HtmlFeatures.css) {
	auto div = Element.make("div");
	div.addClass("sanitized user-content");

	auto content = div.appendChild(userContent.cloned);
	startOver:
	foreach(e; content.tree) {
		if(e.nodeType == NodeType.Text)
			continue; // text nodes are always fine.

		e.tagName = e.tagName.toLower(); // normalize tag names...

		if(!(e.tagName.isInArray(htmlTagWhitelist))) {
			e.stripOut;
			goto startOver;
		}

		if((!(allow & HtmlFeatures.links) && e.tagName == "a")) {
			e.stripOut;
			goto startOver;
		}

		if((!(allow & HtmlFeatures.video) && e.tagName == "video")
		  ||(!(allow & HtmlFeatures.audio) && e.tagName == "audio")
		  ||(!(allow & HtmlFeatures.objects) && e.tagName == "object")
		  ||(!(allow & HtmlFeatures.iframes) && e.tagName == "iframe")
		  ||(!(allow & HtmlFeatures.forms) && (
		  	e.tagName == "form" ||
		  	e.tagName == "input" ||
		  	e.tagName == "textarea" ||
		  	e.tagName == "label" ||
		  	e.tagName == "fieldset" ||
		  	e.tagName == "legend"
			))
		) {
			e.innerText = e.innerText; // strips out non-text children
			e.stripOut;
			goto startOver;
		}

		if(e.tagName == "source" && (e.parentNode is null || e.parentNode.tagName != "video" || e.parentNode.tagName != "audio")) {
			// source is only allowed in the HTML5 media elements
			e.stripOut;
			goto startOver;
		}

		if(!(allow & HtmlFeatures.images) && e.tagName == "img") {
			e.replaceWith(new TextNode(null, e.alt));
			continue; // images not allowed are replaced with their alt text
		}

		foreach(k, v; e.attributes) {
			e.removeAttribute(k);
			k = k.toLower();
			if(!(k.isInArray(htmlAttributeWhitelist))) {
				// not allowed, don't put it back
				// this space is intentionally left blank
			} else {
				// it's allowed but let's make sure it's completely valid
				if(k == "class" && (allow & HtmlFeatures.classes)) {
					e.setAttribute("class", v);
				} else if(k == "id") {
					if(idPrefix !is null)
						e.setAttribute(k, idPrefix ~ v);
					// otherwise, don't allow user IDs
				} else if(k == "style") {
					if(allow & HtmlFeatures.css) {
						e.setAttribute(k, sanitizeCss(v));
					}
				} else if(k == "href" || k == "src") {
					e.setAttribute(k, sanitizeUrl(v));
				} else
					e.setAttribute(k, v); // allowed attribute
			}
		}

		if(e.tagName == "iframe") {
			// some additional restrictions for supported browsers
			e.attrs.security = "restricted";
			e.attrs.sandbox = "";
		}
	}
	return div;
}

///
Element sanitizedHtml(in Html userContent, string idPrefix = null, HtmlFeatures allow = HtmlFeatures.links | HtmlFeatures.images | HtmlFeatures.css) {
	auto div = Element.make("div");
	div.innerHTML = userContent.source;
	return sanitizedHtml(div, idPrefix, allow);
}

string sanitizeCss(string css) {
	// FIXME: do a proper whitelist here; I should probably bring in the parser from html.d
	// FIXME: sanitize urls inside too
	return css.replace("expression", "");
}

///
string sanitizeUrl(string url) {
	// FIXME: support other options; this is more restrictive than it has to be
	if(url.startsWith("http://") || url.startsWith("https://") || url.startsWith("//"))
		return url;
	return null;
}

/// This is some basic CSS I suggest you copy/paste into your stylesheet
/// if you use the sanitizedHtml function.
string recommendedBasicCssForUserContent = `
	.sanitized.user-content {
		position: relative;
		overflow: hidden;
	}

	.sanitized.user-content * {
		max-width: 100%;
		max-height: 100%;
	}
`;

/++
	Given arbitrary user input, find links and add `<a href>` wrappers, otherwise just escaping the rest of it for HTML display.
+/
Html linkify(string text) {
	auto div = Element.make("div");

	while(text.length) {
		auto idx = text.indexOf("http");
		if(idx == -1) {
			idx = text.length;
		}

		div.appendText(text[0 .. idx]);
		text = text[idx .. $];

		if(text.length) {
			// where does it end? whitespace I guess
			auto idxSpace = text.indexOf(" ");
			if(idxSpace == -1) idxSpace = text.length;
			auto idxLine = text.indexOf("\n");
			if(idxLine == -1) idxLine = text.length;


			auto idxEnd = idxSpace < idxLine ? idxSpace : idxLine;

			auto link = text[0 .. idxEnd];
			text = text[idxEnd .. $];

			div.addChild("a", link, link);
		}
	}

	return Html(div.innerHTML);
}

/// Given existing encoded HTML, turns \n\n into `<p>`.
Html paragraphsToP(Html html) {
	auto text = html.source;
	string total;
	foreach(p; text.split("\n\n")) {
		total ~= "<p>";
		auto lines = p.splitLines;
		foreach(idx, line; lines)
			if(line.strip.length) {
				total ~= line;
				if(idx != lines.length - 1)
					total ~= "<br />";
			}
		total ~= "</p>";
	}
	return Html(total);
}

/// Given user text, converts newlines to `<br>` and encodes the rest.
Html nl2br(string text) {
	auto div = Element.make("div");

	bool first = true;
	foreach(line; splitLines(text)) {
		if(!first)
			div.addChild("br");
		else
			first = false;
		div.appendText(line);
	}

	return Html(div.innerHTML);
}

/// Returns true of the string appears to be html/xml - if it matches the pattern
/// for tags or entities.
bool appearsToBeHtml(string src) {
	import std.regex;
	return cast(bool) match(src, `.*\<[A-Za-z]+>.*`);
}

/// Get the favicon out of a document, or return the default a browser would attempt if it isn't there.
string favicon(Document document) {
	auto item = document.querySelector("link[rel~=icon]");
	if(item !is null)
		return item.href;
	return "/favicon.ico"; // it pisses me off that the fucking browsers do this.... but they do, so I will too.
}

///
Element checkbox(string name, string value, string label, bool checked = false) {
	auto lbl = Element.make("label");
	auto input = lbl.addChild("input");
	input.type = "checkbox";
	input.name = name;
	input.value = value;
	if(checked)
		input.checked = "checked";

	lbl.appendText(" ");
	lbl.addChild("span", label);

	return lbl;
}

/++ Convenience function to create a small <form> to POST, but the creation function is more like a link
    than a DOM form.

    The idea is if you have a link to a page which needs to be changed since it is now taking an action,
    this should provide an easy way to do it.

    You might want to style these with css. The form these functions create has no class - use regular
    dom functions to add one. When styling, hit the form itself and form > [type=submit]. (That will
    cover both input[type=submit] and button[type=submit] - the two possibilities the functions may create.)

    Param:
    	href: the link. Query params (if present) are converted into hidden form inputs and the rest is used as the form action
	innerText: the text to show on the submit button
	params: additional parameters for the form
+/
Form makePostLink(string href, string innerText, string[string] params = null) {
	auto submit = Element.make("input");
	submit.type = "submit";
	submit.value = innerText;

	return makePostLink_impl(href, params, submit);
}

/// Similar to the above, but lets you pass HTML rather than just text. It puts the html inside a <button type="submit"> element.
///
/// Using html strings imo generally sucks. I recommend you use plain text or structured Elements instead most the time.
Form makePostLink(string href, Html innerHtml, string[string] params = null) {
	auto submit = Element.make("button");
	submit.type = "submit";
	submit.innerHTML = innerHtml;

	return makePostLink_impl(href, params, submit);
}

/// Like the Html overload, this uses a <button> tag to get fancier with the submit button. The element you pass is appended to the submit button.
Form makePostLink(string href, Element submitButtonContents, string[string] params = null) {
	auto submit = Element.make("button");
	submit.type = "submit";
	submit.appendChild(submitButtonContents);

	return makePostLink_impl(href, params, submit);
}

import arsd.cgi;
import std.range;

Form makePostLink_impl(string href, string[string] params, Element submitButton) {
	auto form = require!Form(Element.make("form"));
	form.method = "POST";

	auto idx = href.indexOf("?");
	if(idx == -1) {
		form.action = href;
	} else {
		form.action = href[0 .. idx];
		foreach(k, arr; decodeVariables(href[idx + 1 .. $]))
			form.addValueArray(k, arr);
	}

	foreach(k, v; params)
		form.setValue(k, v);

	form.appendChild(submitButton);

	return form;
}

/++ Given an existing link, create a POST item from it.
    You can use this to do something like:

    auto e = document.requireSelector("a.should-be-post"); // get my link from the dom
    e.replaceWith(makePostLink(e)); // replace the link with a nice POST form that otherwise does the same thing

    It passes all attributes of the link on to the form, though I could be convinced to put some on the submit button instead.
++/
Form makePostLink(Element link) {
	Form form;
	if(link.childNodes.length == 1) {
		auto fc = link.firstChild;
		if(fc.nodeType == NodeType.Text)
			form = makePostLink(link.href, fc.nodeValue);
		else
			form = makePostLink(link.href, fc);
	} else {
		form = makePostLink(link.href, Html(link.innerHTML));
	}

	assert(form !is null);

	// auto submitButton = form.requireSelector("[type=submit]");

	foreach(k, v; link.attributes) {
		if(k == "href" || k == "action" || k == "method")
			continue;

		form.setAttribute(k, v); // carries on class, events, etc. to the form.
	}

	return form;
}

/// Translates validate="" tags to inline javascript. "this" is the thing
/// being checked.
void translateValidation(Document document) {
	int count;
	foreach(f; document.getElementsByTagName("form")) {
	count++;
		string formValidation = "";
		string fid = f.getAttribute("id");
		if(fid is null) {
			fid = "automatic-form-" ~ to!string(count);
			f.setAttribute("id", "automatic-form-" ~ to!string(count));
		}
		foreach(i; f.tree) {
			if(i.tagName != "input" && i.tagName != "select")
				continue;
			if(i.getAttribute("id") is null)
				i.id = "form-input-" ~ i.name;
			auto validate = i.getAttribute("validate");
			if(validate is null)
				continue;

			auto valmsg = i.getAttribute("validate-message");
			if(valmsg !is null) {
				i.removeAttribute("validate-message");
				valmsg ~= `\n`;
			}

			string valThis = `
			var currentField = elements['`~i.name~`'];
			if(!(`~validate.replace("this", "currentField")~`)) {
						currentField.style.backgroundColor = '#ffcccc';
						if(typeof failedMessage != 'undefined')
							failedMessage += '`~valmsg~`';
						if(failed == null) {
							failed = currentField;
						}
						if('`~valmsg~`' != '') {
							var msgId = '`~i.name~`-valmsg';
							var msgHolder = document.getElementById(msgId);
							if(!msgHolder) {
								msgHolder = document.createElement('div');
								msgHolder.className = 'validation-message';
								msgHolder.id = msgId;

								msgHolder.innerHTML = '<br />';
								msgHolder.appendChild(document.createTextNode('`~valmsg~`'));

								var ele = currentField;
								ele.parentNode.appendChild(msgHolder);
							}
						}
					} else {
						currentField.style.backgroundColor = '#ffffff';
						var msgId = '`~i.name~`-valmsg';
						var msgHolder = document.getElementById(msgId);
						if(msgHolder)
							msgHolder.innerHTML = '';
					}`;

			formValidation ~= valThis;

			string oldOnBlur = i.getAttribute("onblur");
			i.setAttribute("onblur", `
				var form = document.getElementById('`~fid~`');
				var failed = null;
				with(form) { `~valThis~` }
			` ~ oldOnBlur);

			i.removeAttribute("validate");
		}

		if(formValidation != "") {
			auto os = f.getAttribute("onsubmit");
			f.attrs.onsubmit = `var failed = null; var failedMessage = ''; with(this) { ` ~ formValidation ~ '\n' ~ ` if(failed != null) { alert('Please complete all required fields.\n' + failedMessage); failed.focus(); return false; } `~os~` return true; }`;
		}
	}
}

/// makes input[type=date] to call displayDatePicker with a button
void translateDateInputs(Document document) {
	foreach(e; document.getElementsByTagName("input")) {
		auto type = e.getAttribute("type");
		if(type is null) continue;
		if(type == "date") {
			auto name = e.getAttribute("name");
			assert(name !is null);
			auto button = document.createElement("button");
			button.type = "button";
			button.attrs.onclick = "displayDatePicker('"~name~"');";
			button.innerText = "Choose...";
			e.parentNode.insertChildAfter(button, e);

			e.type = "text";
			e.setAttribute("class", "date");
		}
	}
}

/// finds class="striped" and adds class="odd"/class="even" to the relevant
/// children
void translateStriping(Document document) {
	foreach(item; document.querySelectorAll(".striped")) {
		bool odd = false;
		string selector;
		switch(item.tagName) {
			case "ul":
			case "ol":
				selector = "> li";
			break;
			case "table":
				selector = "> tbody > tr";
			break;
			case "tbody":
				selector = "> tr";
			break;
			default:
		 		selector = "> *";
		}
		foreach(e; item.getElementsBySelector(selector)) {
			if(odd)
				e.addClass("odd");
			else
				e.addClass("even");

			odd = !odd;
		}
	}
}

/// tries to make an input to filter a list. it kinda sucks.
void translateFiltering(Document document) {
	foreach(e; document.querySelectorAll("input[filter_what]")) {
		auto filterWhat = e.attrs.filter_what;
		if(filterWhat[0] == '#')
			filterWhat = filterWhat[1..$];

		auto fw = document.getElementById(filterWhat);
		assert(fw !is null);

		foreach(a; fw.getElementsBySelector(e.attrs.filter_by)) {
			a.addClass("filterable_content");
		}

		e.removeAttribute("filter_what");
		e.removeAttribute("filter_by");

		e.attrs.onkeydown = e.attrs.onkeyup = `
			var value = this.value;
			var a = document.getElementById("`~filterWhat~`");
			var children = a.childNodes;
			for(var b = 0; b < children.length; b++) {
				var child = children[b];
				if(child.nodeType != 1)
					continue;

				var spans = child.getElementsByTagName('span'); // FIXME
				for(var i = 0; i < spans.length; i++) {
					var span = spans[i];
					if(hasClass(span, "filterable_content")) {
						if(value.length && span.innerHTML.match(RegExp(value, "i"))) { // FIXME
							addClass(child, "good-match");
							removeClass(child, "bad-match");
							//if(!got) {
							//	holder.scrollTop = child.offsetTop;
							//	got = true;
							//}
						} else {
							removeClass(child, "good-match");
							if(value.length)
								addClass(child, "bad-match");
							else
								removeClass(child, "bad-match");
						}
					}
				}
			}
		`;
	}
}

enum TextWrapperWhitespaceBehavior {
	wrap,
	ignore,
	stripOut
}

/// This wraps every non-empty text mode in the document body with
/// <t:t></t:t>, and sets an xmlns:t to the html root.
///
/// If you use it, be sure it's the last thing you do before
/// calling toString
///
/// Why would you want this? Because CSS sucks. If it had a
/// :text pseudoclass, we'd be right in business, but it doesn't
/// so we'll hack it with this custom tag.
///
/// It's in an xml namespace so it should affect or be affected by
/// your existing code, while maintaining excellent browser support.
///
/// To style it, use myelement > t\:t { style here } in your css.
///
/// Note: this can break the css adjacent sibling selector, first-child,
/// and other structural selectors. For example, if you write
/// <span>hello</span> <span>world</span>, normally, css span + span would
/// select "world". But, if you call wrapTextNodes, there's a <t:t> in the
/// middle.... so now it no longer matches.
///
/// Of course, it can also have an effect on your javascript, especially,
/// again, when working with siblings or firstChild, etc.
///
/// You must handle all this yourself, which may limit the usefulness of this
/// function.
///
/// The second parameter, whatToDoWithWhitespaceNodes, tries to mitigate
/// this somewhat by giving you some options about what to do with text
/// nodes that consist of nothing but whitespace.
///
/// You can: wrap them, like all other text nodes, you can ignore
/// them entirely, leaving them unwrapped, and in the document normally,
/// or you can use stripOut to remove them from the document.
///
/// Beware with stripOut: <span>you</span> <span>rock</span> -- that space
/// between the spans is a text node of nothing but whitespace, so it would
/// be stripped out - probably not what you want!
///
/// ignore is the default, since this should break the least of your
/// expectations with document structure, while still letting you use this
/// function.
void wrapTextNodes(Document document, TextWrapperWhitespaceBehavior whatToDoWithWhitespaceNodes = TextWrapperWhitespaceBehavior.ignore) {
	enum ourNamespace = "t";
	enum ourTag = ourNamespace ~ ":t";
	document.root.setAttribute("xmlns:" ~ ourNamespace, null);
	foreach(e; document.mainBody.tree) {
		if(e.tagName == "script")
			continue;
		if(e.nodeType != NodeType.Text)
			continue;
		auto tn = cast(TextNode) e;
		if(tn is null)
			continue;

		if(tn.contents.length == 0)
			continue;

		if(tn.parentNode !is null
			&& tn.parentNode.tagName == ourTag)
		{
			// this is just a sanity check to make sure
			// we don't double wrap anything
			continue;
		}

		final switch(whatToDoWithWhitespaceNodes) {
			case TextWrapperWhitespaceBehavior.wrap:
				break; // treat it like all other text
			case TextWrapperWhitespaceBehavior.stripOut:
				// if it's actually whitespace...
				if(tn.contents.strip().length == 0) {
					tn.removeFromTree();
					continue;
				}
			break;
			case TextWrapperWhitespaceBehavior.ignore:
				// if it's actually whitespace...
				if(tn.contents.strip().length == 0)
					continue;
		}

		tn.replaceWith(Element.make(ourTag, tn.contents));
	}
}


void translateInputTitles(Document document) {
	translateInputTitles(document.root);
}

/// find <input> elements with a title. Make the title the default internal content
void translateInputTitles(Element rootElement) {
	foreach(form; rootElement.getElementsByTagName("form")) {
		string os;
		foreach(e; form.getElementsBySelector("input[type=text][title], input[type=email][title], textarea[title]")) {
			if(e.hasClass("has-placeholder"))
				continue;
			e.addClass("has-placeholder");
			e.attrs.onfocus = e.attrs.onfocus ~ `
				removeClass(this, 'default');
				if(this.value == this.getAttribute('title'))
					this.value = '';
			`;

			e.attrs.onblur = e.attrs.onblur ~ `
				if(this.value == '') {
					addClass(this, 'default');
					this.value = this.getAttribute('title');
				}
			`;

			os ~= `
				temporaryItem = this.elements["`~e.name~`"];
				if(temporaryItem.value == temporaryItem.getAttribute('title'))
					temporaryItem.value = '';
			`;

			if(e.tagName == "input") {
				if(e.value == "") {
					e.attrs.value = e.attrs.title;
					e.addClass("default");
				}
			} else {
				if(e.innerText.length == 0) {
					e.innerText = e.attrs.title;
					e.addClass("default");
				}
			}
		}

		form.attrs.onsubmit = os ~ form.attrs.onsubmit;
	}
}


/// Adds some script to run onload
/// FIXME: not implemented
void addOnLoad(Document document) {

}






mixin template opDispatches(R) {
	auto opDispatch(string fieldName)(...) {
		if(_arguments.length == 0) {
			// a zero argument function call OR a getter....
			// we can't tell which for certain, so assume getter
			// since they can always use the call method on the returned
			// variable
			static if(is(R == Variable)) {
				auto v = *(new Variable(name ~ "." ~ fieldName, group));
			} else {
				auto v = *(new Variable(fieldName, vars));
			}
			return v;
		} else {
			// we have some kind of assignment, but no help from the
			// compiler to get the type of assignment...

			// FIXME: once Variant is able to handle this, use it!
			static if(is(R == Variable)) {
				auto v = *(new Variable(this.name ~ "." ~ name, group));
			} else
				auto v = *(new Variable(fieldName, vars));

			string attempt(string type) {
				return `if(_arguments[0] == typeid(`~type~`)) v = va_arg!(`~type~`)(_argptr);`;
			}

			mixin(attempt("int"));
			mixin(attempt("string"));
			mixin(attempt("double"));
			mixin(attempt("Element"));
			mixin(attempt("ClientSideScript.Variable"));
			mixin(attempt("real"));
			mixin(attempt("long"));

			return v;
		}
	}

	auto opDispatch(string fieldName, T...)(T t) if(T.length != 0) {
		static if(is(R == Variable)) {
			auto tmp = group.codes.pop;
			scope(exit) group.codes.push(tmp);
			return *(new Variable(callFunction(name ~ "." ~ fieldName, t).toString[1..$-2], group)); // cut off the ending ;\n
		} else {
			return *(new Variable(callFunction(fieldName, t).toString, vars));
		}
	}


}



/**
	This wraps up a bunch of javascript magic. It doesn't
	actually parse or run it - it just collects it for
	attachment to a DOM document.

	When it returns a variable, it returns it as a string
	suitable for output into Javascript source.


	auto js = new ClientSideScript;

	js.myvariable = 10;

	js.somefunction = ClientSideScript.Function(


	js.block = {
		js.alert("hello");
		auto a = "asds";

		js.alert(a, js.somevar);
	};

	Translates into javascript:
		alert("hello");
		alert("asds", somevar);


	The passed code is evaluated lazily.
*/

/+
class ClientSideScript : Element {
	private Stack!(string*) codes;
	this(Document par) {
		codes = new Stack!(string*);
		vars = new VariablesGroup;
		vars.codes = codes;
		super(par, "script");
	}

	string name;

	struct Source { string source; string toString() { return source; } }

	void innerCode(void delegate() theCode) {
		myCode = theCode;
	}

	override void innerRawSource(string s) {
		myCode = null;
		super.innerRawSource(s);
	}

	private void delegate() myCode;

	override string toString() const {
		auto HACK = cast(ClientSideScript) this;
		if(HACK.myCode) {
			string code;

			HACK.codes.push(&code);
			HACK.myCode();
			HACK.codes.pop();

			HACK.innerRawSource = "\n" ~ code;
		}

		return super.toString();
	}

	enum commitCode = ` if(!codes.empty) { auto magic = codes.peek; (*magic) ~= code; }`;

	struct Variable {
		string name;
		VariablesGroup group;

		// formats it for use in an inline event handler
		string inline() {
			return name.replace("\t", "");
		}

		this(string n, VariablesGroup g) {
			name = n;
			group = g;
		}

		Source set(T)(T t) {
			string code = format("\t%s = %s;\n", name, toJavascript(t));
			if(!group.codes.empty) {
				auto magic = group.codes.peek;
				(*magic) ~= code;
			}

			//Variant v = t;
			//group.repository[name] = v;

			return Source(code);
		}

		Variant _get() {
			return (group.repository)[name];
		}

		Variable doAssignCode(string code) {
			if(!group.codes.empty) {
				auto magic = group.codes.peek;
				(*magic) ~= "\t" ~ code ~ ";\n";
			}
			return * ( new Variable(code, group) );
		}

		Variable opSlice(size_t a, size_t b) {
			return * ( new Variable(name ~ ".substring("~to!string(a) ~ ", " ~ to!string(b)~")", group) );
		}

		Variable opBinary(string op, T)(T rhs) {
			return * ( new Variable(name ~ " " ~ op ~ " " ~ toJavascript(rhs), group) );
		}
		Variable opOpAssign(string op, T)(T rhs) {
			return doAssignCode(name ~ " " ~  op ~ "= " ~ toJavascript(rhs));
		}
		Variable opIndex(T)(T i) {
			return * ( new Variable(name ~ "[" ~ toJavascript(i)  ~ "]" , group) );
		}
		Variable opIndexOpAssign(string op, T, R)(R rhs, T i) {
			return doAssignCode(name ~ "[" ~ toJavascript(i) ~ "] " ~ op ~ "= " ~ toJavascript(rhs));
		}
		Variable opIndexAssign(T, R)(R rhs, T i) {
			return doAssignCode(name ~ "[" ~ toJavascript(i) ~ "]" ~ " = " ~ toJavascript(rhs));
		}
		Variable opUnary(string op)() {
			return * ( new Variable(op ~ name, group) );
		}

		void opAssign(T)(T rhs) {
			set(rhs);
		}

		// used to call with zero arguments
		Source call() {
			string code = "\t" ~ name ~ "();\n";
			if(!group.codes.empty) {
				auto magic = group.codes.peek;
				(*magic) ~= code;
			}
			return Source(code);
		}
		mixin opDispatches!(Variable);

		// returns code to call a function
		Source callFunction(T...)(string name, T t) {
			string code = "\t" ~ name ~ "(";

			bool outputted = false;
			foreach(v; t) {
				if(outputted)
					code ~= ", ";
				else
					outputted = true;

				code ~= toJavascript(v);
			}

			code ~= ");\n";

			if(!group.codes.empty) {
				auto magic = group.codes.peek;
				(*magic) ~= code;
			}
			return Source(code);
		}


	}

	// this exists only to allow easier access
	class VariablesGroup {
		/// If the variable is a function, we call it. If not, we return the source
		@property Variable opDispatch(string name)() {
			return * ( new Variable(name, this) );
		}

		Variant[string] repository;
		Stack!(string*) codes;
	}

	VariablesGroup vars;

	mixin opDispatches!(ClientSideScript);

	// returns code to call a function
	Source callFunction(T...)(string name, T t) {
		string code = "\t" ~ name ~ "(";

		bool outputted = false;
		foreach(v; t) {
			if(outputted)
				code ~= ", ";
			else
				outputted = true;

			code ~= toJavascript(v);
		}

		code ~= ");\n";

		mixin(commitCode);
		return Source(code);
	}

	Variable thisObject() {
		return Variable("this", vars);
	}

	Source setVariable(T)(string var, T what) {
		auto v = Variable(var, vars);
		return v.set(what);
	}

	Source appendSource(string code) {
		mixin(commitCode);
		return Source(code);
	}

	ref Variable var(string name) {
		string code = "\tvar " ~ name ~ ";\n";
		mixin(commitCode);

		auto v = new Variable(name, vars);

		return *v;
	}
}
+/

/*
	Interesting things with scripts:


	set script value with ease
	get a script value we've already set
	set script functions
	set script events
	call a script on pageload

	document.scripts


	set styles
	get style precedence
	get style thing

*/

import std.conv;

/+
void main() {
	auto document = new Document("<lol></lol>");
	auto js = new ClientSideScript(document);

	auto ele = document.createElement("a");
	document.root.appendChild(ele);

	int dInt = 50;

	js.innerCode = {
		js.var("funclol") = "hello, world"; // local variable definition
		js.funclol = "10";    // parens are (currently) required when setting
		js.funclol = 10;      // works with a variety of basic types
		js.funclol = 10.4;
		js.funclol = js.rofl; // can also set to another js variable
		js.setVariable("name", [10, 20]); // try setVariable for complex types
		js.setVariable("name", 100); // it can also set with strings for names
		js.alert(js.funclol, dInt); // call functions with js and D arguments
		js.funclol().call;       // to call without arguments, use the call method
		js.funclol(10);        // calling with arguments looks normal
		js.funclol(10, "20");  // including multiple, varied arguments
		js.myelement = ele;    // works with DOM references too
		js.a = js.b + js.c;    // some operators work too
		js.a() += js.d; // for some ops, you need the parens to please the compiler
		js.o = js.b[10]; // indexing works too
		js.e[10] = js.a; // so does index assign
		js.e[10] += js.a; // and index op assign...

		js.eles = js.document.getElementsByTagName("as"); // js objects are accessible too
		js.aaa = js.document.rofl.copter; // arbitrary depth

		js.ele2 = js.myelement;

		foreach(i; 0..5) 	// loops are done on the server - it may be unrolled
			js.a() += js.w; // in the script outputted, or not work properly...

		js.one = js.a[0..5];

		js.math = js.a + js.b - js.c; // multiple things work too
		js.math = js.a + (js.b - js.c); // FIXME: parens to NOT work.

		js.math = js.s + 30; // and math with literals
		js.math = js.s + (40 + dInt) - 10; // and D variables, which may be
					// optimized by the D compiler with parens

	};

	write(js.toString);
}
+/
import std.stdio;















// helper for json


import std.json;
import std.traits;

/+
string toJavascript(T)(T a) {
	static if(is(T == ClientSideScript.Variable)) {
		return a.name;
	} else static if(is(T : Element)) {
		if(a is null)
			return "null";

		if(a.id.length == 0) {
			static int count;
			a.id = "javascript-referenced-element-" ~ to!string(++count);
		}

		return `document.getElementById("`~ a.id  ~`")`;
	} else {
		auto jsonv = toJsonValue(a);
		return toJSON(&jsonv);
	}
}

import arsd.web; // for toJsonValue

/+
string passthrough(string d)() {
	return d;
}

string dToJs(string d)(Document document) {
	auto js = new ClientSideScript(document);
	mixin(passthrough!(d)());
	return js.toString();
}

string translateJavascriptSourceWithDToStandardScript(string src)() {
	// blocks of D { /* ... */ } are executed. Comments should work but
	// don't.

	int state = 0;

	int starting = 0;
	int ending = 0;

	int startingString = 0;
	int endingString = 0;

	int openBraces = 0;


	string result;

	Document document = new Document("<root></root>");

	foreach(i, c; src) {
		switch(state) {
			case 0:
				if(c == 'D') {
					endingString = i;
					state++;
				}
			break;
			case 1:
				if(c == ' ') {
					state++;
				} else {
					state = 0;
				}
			break;
			case 2:
				if(c == '{') {
					state++;
					starting = i;
					openBraces = 1;
				} else {
					state = 0;
				}
			break;
			case 3:
				// We're inside D
				if(c == '{')
					openBraces++;
				if(c == '}') {
					openBraces--;
					if(openBraces == 0) {
						state = 0;
						ending = i + 1;

						// run some D..

						string str = src[startingString .. endingString];

						startingString = i + 1;
						string d = src[starting .. ending];


						result ~= str;

						//result ~= dToJs!(d)(document);

						result ~= "/* " ~ d ~ " */";
					}
				}
			break;
		}
	}

	result ~= src[startingString .. $];

	return result;
}
+/
+/

abstract class CssPart {
	string comment;
	override string toString() const;
	CssPart clone() const;
}

class CssAtRule : CssPart {
	this() {}
	this(ref string css) {
		assert(css.length);
		assert(css[0] == '@');

		auto cssl = css.length;
		int braceCount = 0;
		int startOfInnerSlice = -1;

		foreach(i, c; css) {
			if(braceCount == 0 && c == ';') {
				content = css[0 .. i + 1];
				css = css[i + 1 .. $];

				opener = content;
				break;
			}

			if(c == '{') {
				braceCount++;
				if(startOfInnerSlice == -1)
					startOfInnerSlice = cast(int) i;
			}
			if(c == '}') {
				braceCount--;
				if(braceCount < 0)
					throw new Exception("Bad CSS: mismatched }");

				if(braceCount == 0) {
					opener = css[0 .. startOfInnerSlice];
					inner = css[startOfInnerSlice + 1 .. i];

					content = css[0 .. i + 1];
					css = css[i + 1 .. $];
					break;
				}
			}
		}

		if(cssl == css.length) {
			throw new Exception("Bad CSS: unclosed @ rule. " ~ to!string(braceCount) ~ " brace(s) uncloced");
		}

		innerParts = lexCss(inner, false);
	}

	string content;

	string opener;
	string inner;

	CssPart[] innerParts;

	override CssAtRule clone() const {
		auto n = new CssAtRule();
		n.content = content;
		n.opener = opener;
		n.inner = inner;
		foreach(part; innerParts)
			n.innerParts ~= part.clone();
		return n;
	}
	override string toString() const {
		string c;
		if(comment.length)
			c ~= "/* " ~ comment ~ "*/\n";
		c ~= opener.strip();
		if(innerParts.length) {
			string i;
			foreach(part; innerParts)
				i ~= part.toString() ~ "\n";

			c ~= " {\n";
			foreach(line; i.splitLines)
				c ~= "\t" ~ line ~ "\n";
			c ~= "}";
		}
		return c;
	}
}

class CssRuleSet : CssPart {
	this() {}

	this(ref string css) {
		auto idx = css.indexOf("{");
		assert(idx != -1);
		foreach(selector; css[0 .. idx].split(","))
			selectors ~= selector.strip;

		css = css[idx .. $];
		int braceCount = 0;
		string content;
		size_t f = css.length;
		foreach(i, c; css) {
			if(c == '{')
				braceCount++;
			if(c == '}') {
				braceCount--;
				if(braceCount == 0) {
					f = i;
					break;
				}
			}
		}

		content = css[1 .. f]; // skipping the {
		if(f < css.length && css[f] == '}')
			f++;
		css = css[f .. $];

		contents = lexCss(content, false);
	}

	string[] selectors;
	CssPart[] contents;

	override CssRuleSet clone() const {
		auto n = new CssRuleSet();
		n.selectors = selectors.dup;
		foreach(part; contents)
			n.contents ~= part.clone();
		return n;
	}

	CssRuleSet[] deNest(CssRuleSet outer = null) const {
		CssRuleSet[] ret;

		CssRuleSet levelOne = new CssRuleSet();
		ret ~= levelOne;
		if(outer is null)
			levelOne.selectors = selectors.dup;
		else {
			foreach(outerSelector; outer.selectors.length ? outer.selectors : [""])
			foreach(innerSelector; selectors) {
				/*
					it would be great to do a top thing and a bottom, examples:
					.awesome, .awesome\& {
						.something img {}
					}

					should give:
						.awesome .something img, .awesome.something img { }

					And also
					\&.cool {
						.something img {}
					}

					should give:
						.something img.cool {}

					OR some such syntax.


					The idea though is it will ONLY apply to end elements with that particular class. Why is this good? We might be able to isolate the css more for composited files.

					idk though.
				*/
				/+
				// FIXME: this implementation is useless, but the idea of allowing combinations at the top level rox.
				if(outerSelector.length > 2 && outerSelector[$-2] == '\\' && outerSelector[$-1] == '&') {
					// the outer one is an adder... so we always want to paste this on, and if the inner has it, collapse it
					if(innerSelector.length > 2 && innerSelector[0] == '\\' && innerSelector[1] == '&')
						levelOne.selectors ~= outerSelector[0 .. $-2] ~ innerSelector[2 .. $];
					else
						levelOne.selectors ~= outerSelector[0 .. $-2] ~ innerSelector;
				} else
				+/

				// we want to have things like :hover, :before, etc apply without implying
				// a descendant.

				// If you want it to be a descendant pseudoclass, use the *:something - the
				// wildcard tag - instead of just a colon.

				// But having this is too useful to ignore.
				if(innerSelector.length && innerSelector[0] == ':')
					levelOne.selectors ~= outerSelector ~ innerSelector;
				// we also allow \&something to get them concatenated
				else if(innerSelector.length > 2 && innerSelector[0] == '\\' && innerSelector[1] == '&')
					levelOne.selectors ~= outerSelector ~ innerSelector[2 .. $].strip;
				else
					levelOne.selectors ~= outerSelector ~ " " ~ innerSelector; // otherwise, use some other operator...
			}
		}

		foreach(part; contents) {
			auto set = cast(CssRuleSet) part;
			if(set is null)
				levelOne.contents ~= part.clone();
			else {
				// actually gotta de-nest this
				ret ~= set.deNest(levelOne);
			}
		}

		return ret;
	}

	override string toString() const {
		string ret;


		if(comment.length)
			ret ~= "/* " ~ comment ~ "*/\n";

		bool outputtedSelector = false;
		foreach(selector; selectors) {
			if(outputtedSelector)
				ret ~= ", ";
			else
				outputtedSelector = true;

			ret ~= selector;
		}

		ret ~= " {\n";
		foreach(content; contents) {
			auto str = content.toString();
			if(str.length)
				str = "\t" ~ str.replace("\n", "\n\t") ~ "\n";

			ret ~= str;
		}
		ret ~= "}";

		return ret;
	}
}

class CssRule : CssPart {
	this() {}

	this(ref string css, int endOfStatement) {
		content = css[0 .. endOfStatement];
		if(endOfStatement < css.length && css[endOfStatement] == ';')
			endOfStatement++;

		css = css[endOfStatement .. $];
	}

	// note: does not include the ending semicolon
	string content;

	string key() const {
		auto idx = content.indexOf(":");
		if(idx == -1)
			throw new Exception("Bad css, missing colon in " ~ content);
		return content[0 .. idx].strip.toLower;
	}

	string value() const {
		auto idx = content.indexOf(":");
		if(idx == -1)
			throw new Exception("Bad css, missing colon in " ~ content);

		return content[idx + 1 .. $].strip;
	}

	override CssRule clone() const {
		auto n = new CssRule();
		n.content = content;
		return n;
	}

	override string toString() const {
		string ret;
		if(strip(content).length == 0)
			ret = "";
		else
			ret = key ~ ": " ~ value ~ ";";

		if(comment.length)
			ret ~= " /* " ~ comment ~ " */";

		return ret;
	}
}

// Never call stripComments = false unless you have already stripped them.
// this thing can't actually handle comments intelligently.
CssPart[] lexCss(string css, bool stripComments = true) {
	if(stripComments) {
		import std.regex;
		css = std.regex.replace(css, regex(r"\/\*[^*]*\*+([^/*][^*]*\*+)*\/", "g"), "");
	}

	CssPart[] ret;
	css = css.stripLeft();

	int cnt;

	while(css.length > 1) {
		CssPart p;

		if(css[0] == '@') {
			p = new CssAtRule(css);
		} else {
			// non-at rules can be either rules or sets.
			// The question is: which comes first, the ';' or the '{' ?

			auto endOfStatement = css.indexOfCssSmart(';');
			if(endOfStatement == -1)
				endOfStatement = css.indexOf("}");
			if(endOfStatement == -1)
				endOfStatement = css.length;

			auto beginningOfBlock = css.indexOf("{");
			if(beginningOfBlock == -1 || endOfStatement < beginningOfBlock)
				p = new CssRule(css, cast(int) endOfStatement);
			else
				p = new CssRuleSet(css);
		}

		assert(p !is null);
		ret ~= p;

		css = css.stripLeft();
	}

	return ret;
}

// This needs to skip characters inside parens or quotes, so it
// doesn't trip up on stuff like data uris when looking for a terminating
// character.
ptrdiff_t indexOfCssSmart(string i, char find) {
	int parenCount;
	char quote;
	bool escaping;
	foreach(idx, ch; i) {
		if(escaping) {
			escaping = false;
			continue;
		}
		if(quote != char.init) {
			if(ch == quote)
				quote = char.init;
			continue;
		}
		if(ch == '\'' || ch == '"') {
			quote = ch;
			continue;
		}

		if(ch == '(')
			parenCount++;

		if(parenCount) {
			if(ch == ')')
				parenCount--;
			continue;
		}

		// at this point, we are not in parenthesis nor are we in
		// a quote, so we can actually search for the relevant character

		if(ch == find)
			return idx;
	}
	return -1;
}

string cssToString(in CssPart[] css) {
	string ret;
	foreach(c; css) {
		if(ret.length) {
			if(ret[$ -1] == '}')
				ret ~= "\n\n";
			else
				ret ~= "\n";
		}
		ret ~= c.toString();
	}

	return ret;
}

/// Translates nested css
const(CssPart)[] denestCss(CssPart[] css) {
	CssPart[] ret;
	foreach(part; css) {
		auto at = cast(CssAtRule) part;
		if(at is null) {
			auto set = cast(CssRuleSet) part;
			if(set is null)
				ret ~= part;
			else {
				ret ~= set.deNest();
			}
		} else {
			// at rules with content may be denested at the top level...
			// FIXME: is this even right all the time?

			if(at.inner.length) {
				auto newCss = at.opener ~ "{\n";

					// the whitespace manipulations are just a crude indentation thing
				newCss ~= "\t" ~ (cssToString(denestCss(lexCss(at.inner, false))).replace("\n", "\n\t").replace("\n\t\n\t", "\n\n\t"));

				newCss ~= "\n}";

				ret ~= new CssAtRule(newCss);
			} else {
				ret ~= part; // no inner content, nothing special needed
			}
		}
	}

	return ret;
}

/*
	Forms:

	¤var
	¤lighten(¤foreground, 0.5)
	¤lighten(¤foreground, 0.5); -- exactly one semicolon shows up at the end
	¤var(something, something_else) {
		final argument
	}

	¤function {
		argument
	}


	Possible future:

	Recursive macros:

	¤define(li) {
		<li>¤car</li>
		list(¤cdr)
	}

	¤define(list) {
		¤li(¤car)
	}


	car and cdr are borrowed from lisp... hmm
	do i really want to do this...



	But if the only argument is cdr, and it is empty the function call is cancelled.
	This lets you do some looping.


	hmmm easier would be

	¤loop(macro_name, args...) {
		body
	}

	when you call loop, it calls the macro as many times as it can for the
	given args, and no more.



	Note that set is a macro; it doesn't expand it's arguments.
	To force expansion, use echo (or expand?) on the argument you set.
*/

// Keep in mind that this does not understand comments!
class MacroExpander {
	dstring delegate(dstring[])[dstring] functions;
	dstring[dstring] variables;

	/// This sets a variable inside the macro system
	void setValue(string key, string value) {
		variables[to!dstring(key)] = to!dstring(value);
	}

	struct Macro {
		dstring name;
		dstring[] args;
		dstring definition;
	}

	Macro[dstring] macros;

	// FIXME: do I want user defined functions or something?

	this() {
		functions["get"] = &get;
		functions["set"] = &set;
		functions["define"] = &define;
		functions["loop"] = &loop;

		functions["echo"] = delegate dstring(dstring[] args) {
			dstring ret;
			bool outputted;
			foreach(arg; args) {
				if(outputted)
					ret ~= ", ";
				else
					outputted = true;
				ret ~= arg;
			}

			return ret;
		};

		functions["uriEncode"] = delegate dstring(dstring[] args) {
			return to!dstring(encodeUriComponent(to!string(args[0])));
		};

		functions["test"] = delegate dstring(dstring[] args) {
			assert(0, to!string(args.length) ~ " args: " ~ to!string(args));
		};

		functions["include"] = &include;
	}

	string[string] includeFiles;

	dstring include(dstring[] args) {
		string s;
		foreach(arg; args) {
			string lol = to!string(arg);
			s ~= to!string(includeFiles[lol]);
		}

		return to!dstring(s);
	}

	// the following are used inside the user text

	dstring define(dstring[] args) {
		enforce(args.length > 1, "requires at least a macro name and definition");

		Macro m;
		m.name = args[0];
		if(args.length > 2)
			m.args = args[1 .. $ - 1];
		m.definition = args[$ - 1];

		macros[m.name] = m;

		return null;
	}

	dstring set(dstring[] args) {
		enforce(args.length == 2, "requires two arguments. got " ~ to!string(args));
		variables[args[0]] = args[1];
		return "";
	}

	dstring get(dstring[] args) {
		enforce(args.length == 1);
		if(args[0] !in variables)
			return "";
		return variables[args[0]];
	}

	dstring loop(dstring[] args) {
		enforce(args.length > 1, "must provide a macro name and some arguments");
		auto m = macros[args[0]];
		args = args[1 .. $];
		dstring returned;

		size_t iterations = args.length;
		if(m.args.length != 0)
			iterations = (args.length + m.args.length - 1) / m.args.length;

		foreach(i; 0 .. iterations) {
			returned ~= expandMacro(m, args);
			if(m.args.length < args.length)
				args = args[m.args.length .. $];
			else
				args = null;
		}

		return returned;
	}

	/// Performs the expansion
	string expand(string srcutf8) {
		auto src = expand(to!dstring(srcutf8));
		return to!string(src);
	}

	private int depth = 0;
	/// ditto
	dstring expand(dstring src) {
		return expandImpl(src, null);
	}

	// FIXME: the order of evaluation shouldn't matter. Any top level sets should be run
	// before anything is expanded.
	private dstring expandImpl(dstring src, dstring[dstring] localVariables) {
		depth ++;
		if(depth > 10)
			throw new Exception("too much recursion depth in macro expansion");

		bool doneWithSetInstructions = false; // this is used to avoid double checks each loop
		for(;;) {
			// we do all the sets first since the latest one is supposed to be used site wide.
			// this allows a later customization to apply to the entire document.
			auto idx = doneWithSetInstructions ? -1 : src.indexOf("¤set");
			if(idx == -1) {
				doneWithSetInstructions = true;
				idx = src.indexOf("¤");
			}
			if(idx == -1) {
				depth--;
				return src;
			}

			// the replacement goes
			// src[0 .. startingSliceForReplacement] ~ new ~ src[endingSliceForReplacement .. $];
			sizediff_t startingSliceForReplacement, endingSliceForReplacement;

			dstring functionName;
			dstring[] arguments;
			bool addTrailingSemicolon;

			startingSliceForReplacement = idx;
			// idx++; // because the star in UTF 8 is two characters. FIXME: hack -- not needed thx to dstrings
			auto possibility = src[idx + 1 .. $];
			size_t argsBegin;

			bool found = false;
			foreach(i, c; possibility) {
				if(!(
					// valid identifiers
					(c >= 'A' && c <= 'Z')
					||
					(c >= 'a' && c <= 'z')
					||
					(c >= '0' && c <= '9')
					||
					c == '_'
				)) {
					// not a valid identifier means
					// we're done reading the name
					functionName = possibility[0 .. i];
					argsBegin = i;
					found = true;
					break;
				}
			}

			if(!found) {
				functionName = possibility;
				argsBegin = possibility.length;
			}

			auto endOfVariable = argsBegin + idx + 1; // this is the offset into the original source

			bool checkForAllArguments = true;

			moreArguments:

			assert(argsBegin);

			endingSliceForReplacement = argsBegin + idx + 1;

			while(
				argsBegin < possibility.length && (
				possibility[argsBegin] == ' ' ||
				possibility[argsBegin] == '\t' ||
				possibility[argsBegin] == '\n' ||
				possibility[argsBegin] == '\r'))
			{
				argsBegin++;
			}

			if(argsBegin == possibility.length) {
				endingSliceForReplacement = src.length;
				goto doReplacement;
			}

			switch(possibility[argsBegin]) {
				case '(':
					if(!checkForAllArguments)
						goto doReplacement;

					// actually parsing the arguments
					size_t currentArgumentStarting = argsBegin + 1;

					int open;

					bool inQuotes;
					bool inTicks;
					bool justSawBackslash;
					foreach(i, c; possibility[argsBegin .. $]) {
						if(c == '`')
							inTicks = !inTicks;

						if(inTicks)
							continue;

						if(!justSawBackslash && c == '"')
							inQuotes = !inQuotes;

						if(c == '\\')
							justSawBackslash = true;
						else
							justSawBackslash = false;

						if(inQuotes)
							continue;

						if(open == 1 && c == ',') { // don't want to push a nested argument incorrectly...
							// push the argument
							arguments ~= possibility[currentArgumentStarting .. i + argsBegin];
							currentArgumentStarting = argsBegin + i + 1;
						}

						if(c == '(')
							open++;
						if(c == ')') {
							open--;
							if(open == 0) {
								// push the last argument
								arguments ~= possibility[currentArgumentStarting .. i + argsBegin];

								endingSliceForReplacement = argsBegin + idx + 1 + i;
								argsBegin += i + 1;
								break;
							}
						}
					}

					// then see if there's a { argument too
					checkForAllArguments = false;
					goto moreArguments;
				case '{':
					// find the match
					int open;
					foreach(i, c; possibility[argsBegin .. $]) {
						if(c == '{')
							open ++;
						if(c == '}') {
							open --;
							if(open == 0) {
								// cutting off the actual braces here
								arguments ~= possibility[argsBegin + 1 .. i + argsBegin];
									// second +1 is there to cut off the }
								endingSliceForReplacement = argsBegin + idx + 1 + i + 1;

								argsBegin += i + 1;
								break;
							}
						}
					}

					goto doReplacement;
				default:
					goto doReplacement;
			}

			doReplacement:
				if(endingSliceForReplacement < src.length && src[endingSliceForReplacement] == ';') {
					endingSliceForReplacement++;
					addTrailingSemicolon = true; // don't want a doubled semicolon
					// FIXME: what if it's just some whitespace after the semicolon? should that be
					// stripped or no?
				}

				foreach(ref argument; arguments) {
					argument = argument.strip();
					if(argument.length > 2 && argument[0] == '`' && argument[$-1] == '`')
						argument = argument[1 .. $ - 1]; // strip ticks here
					else
					if(argument.length > 2 && argument[0] == '"' && argument[$-1] == '"')
						argument = argument[1 .. $ - 1]; // strip quotes here

					// recursive macro expanding
					// these need raw text, since they expand later. FIXME: should it just be a list of functions?
					if(functionName != "define" && functionName != "quote" && functionName != "set")
						argument = this.expandImpl(argument, localVariables);
				}

				dstring returned = "";
				if(functionName in localVariables) {
					/*
					if(functionName == "_head")
						returned = arguments[0];
					else if(functionName == "_tail")
						returned = arguments[1 .. $];
					else
					*/
						returned = localVariables[functionName];
				} else if(functionName in functions)
					returned = functions[functionName](arguments);
				else if(functionName in variables) {
					returned = variables[functionName];
					// FIXME
					// we also need to re-attach the arguments array, since variable pulls can't have args
					assert(endOfVariable > startingSliceForReplacement);
					endingSliceForReplacement = endOfVariable;
				} else if(functionName in macros) {
					returned = expandMacro(macros[functionName], arguments);
				}

				if(addTrailingSemicolon && returned.length > 1 && returned[$ - 1] != ';')
					returned ~= ";";

				src = src[0 .. startingSliceForReplacement] ~ returned ~ src[endingSliceForReplacement .. $];
		}
		assert(0); // not reached
	}

	dstring expandMacro(Macro m, dstring[] arguments) {
		dstring[dstring] locals;
		foreach(i, arg; m.args) {
			if(i == arguments.length)
				break;
			locals[arg] = arguments[i];
		}

		return this.expandImpl(m.definition, locals);
	}
}


class CssMacroExpander : MacroExpander {
	this() {
		super();

		functions["prefixed"] = &prefixed;

		functions["lighten"] = &(colorFunctionWrapper!lighten);
		functions["darken"] = &(colorFunctionWrapper!darken);
		functions["moderate"] = &(colorFunctionWrapper!moderate);
		functions["extremify"] = &(colorFunctionWrapper!extremify);
		functions["makeTextColor"] = &(oneArgColorFunctionWrapper!makeTextColor);

		functions["oppositeLightness"] = &(oneArgColorFunctionWrapper!oppositeLightness);

		functions["rotateHue"] = &(colorFunctionWrapper!rotateHue);

		functions["saturate"] = &(colorFunctionWrapper!saturate);
		functions["desaturate"] = &(colorFunctionWrapper!desaturate);

		functions["setHue"] = &(colorFunctionWrapper!setHue);
		functions["setSaturation"] = &(colorFunctionWrapper!setSaturation);
		functions["setLightness"] = &(colorFunctionWrapper!setLightness);
	}

	// prefixed(border-radius: 12px);
	dstring prefixed(dstring[] args) {
		dstring ret;
		foreach(prefix; ["-moz-"d, "-webkit-"d, "-o-"d, "-ms-"d, "-khtml-"d, ""d])
			ret ~= prefix ~ args[0] ~ ";";
		return ret;
	}

	/// Runs the macro expansion but then a CSS densesting
	string expandAndDenest(string cssSrc) {
		return cssToString(denestCss(lexCss(this.expand(cssSrc))));
	}

	// internal things
	dstring colorFunctionWrapper(alias func)(dstring[] args) {
		auto color = readCssColor(to!string(args[0]));
		auto percentage = readCssNumber(args[1]);
		return "#"d ~ to!dstring(func(color, percentage).toString());
	}

	dstring oneArgColorFunctionWrapper(alias func)(dstring[] args) {
		auto color = readCssColor(to!string(args[0]));
		return "#"d ~ to!dstring(func(color).toString());
	}
}


real readCssNumber(dstring s) {
	s = s.replace(" "d, ""d);
	if(s.length == 0)
		return 0;
	if(s[$-1] == '%')
		return (to!real(s[0 .. $-1]) / 100f);
	return to!real(s);
}

import std.format;

class JavascriptMacroExpander : MacroExpander {
	this() {
		super();
		functions["foreach"] = &foreachLoop;
	}


	/**
		¤foreach(item; array) {
			// code
		}

		so arg0 .. argn-1 is the stuff inside. Conc
	*/

	int foreachLoopCounter;
	dstring foreachLoop(dstring[] args) {
		enforce(args.length >= 2, "foreach needs parens and code");
		dstring parens;
		bool outputted = false;
		foreach(arg; args[0 .. $ - 1]) {
			if(outputted)
				parens ~= ", ";
			else
				outputted = true;
			parens ~= arg;
		}

		dstring variableName, arrayName;

		auto it = parens.split(";");
		variableName = it[0].strip;
		arrayName = it[1].strip;

		dstring insideCode = args[$-1];

		dstring iteratorName;
		iteratorName = "arsd_foreach_loop_counter_"d ~ to!dstring(++foreachLoopCounter);
		dstring temporaryName = "arsd_foreach_loop_temporary_"d ~ to!dstring(++foreachLoopCounter);

		auto writer = appender!dstring();

		formattedWrite(writer, "
			var %2$s = %5$s;
			if(%2$s != null)
			for(var %1$s = 0; %1$s < %2$s.length; %1$s++) {
				var %3$s = %2$s[%1$s];
				%4$s
		}"d, iteratorName, temporaryName, variableName, insideCode, arrayName);

		auto code = writer.data;

		return to!dstring(code);
	}
}

string beautifyCss(string css) {
	css = css.replace(":", ": ");
	css = css.replace(":  ", ": ");
	css = css.replace("{", " {\n\t");
	css = css.replace(";", ";\n\t");
	css = css.replace("\t}", "}\n\n");
	return css.strip;
}

int fromHex(string s) {
	int result = 0;

	int exp = 1;
	foreach(c; retro(s)) {
		if(c >= 'A' && c <= 'F')
			result += exp * (c - 'A' + 10);
		else if(c >= 'a' && c <= 'f')
			result += exp * (c - 'a' + 10);
		else if(c >= '0' && c <= '9')
			result += exp * (c - '0');
		else
			throw new Exception("invalid hex character: " ~ cast(char) c);

		exp *= 16;
	}

	return result;
}

Color readCssColor(string cssColor) {
	cssColor = cssColor.strip().toLower();

	if(cssColor.startsWith("#")) {
		cssColor = cssColor[1 .. $];
		if(cssColor.length == 3) {
			cssColor = "" ~ cssColor[0] ~ cssColor[0]
					~ cssColor[1] ~ cssColor[1]
					~ cssColor[2] ~ cssColor[2];
		}

		if(cssColor.length == 6)
			cssColor ~= "ff";

		/* my extension is to do alpha */
		if(cssColor.length == 8) {
			return Color(
				fromHex(cssColor[0 .. 2]),
				fromHex(cssColor[2 .. 4]),
				fromHex(cssColor[4 .. 6]),
				fromHex(cssColor[6 .. 8]));
		} else
			throw new Exception("invalid color " ~ cssColor);
	} else if(cssColor.startsWith("rgba")) {
		assert(0); // FIXME: implement
		/*
		cssColor = cssColor.replace("rgba", "");
		cssColor = cssColor.replace(" ", "");
		cssColor = cssColor.replace("(", "");
		cssColor = cssColor.replace(")", "");

		auto parts = cssColor.split(",");
		*/
	} else if(cssColor.startsWith("rgb")) {
		assert(0); // FIXME: implement
	} else if(cssColor.startsWith("hsl")) {
		assert(0); // FIXME: implement
	} else
		return Color.fromNameString(cssColor);
	/*
	switch(cssColor) {
		default:
			// FIXME let's go ahead and try naked hex for compatibility with my gradient program
			assert(0, "Unknown color: " ~ cssColor);
	}
	*/
}

/*
Copyright: Adam D. Ruppe, 2010 - 2015
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions by Nick Sabalausky and Trass3r

        Copyright Adam D. Ruppe 2010-2015.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
        http://www.boost.org/LICENSE_1_0.txt)
*/
