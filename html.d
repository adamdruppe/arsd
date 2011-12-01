/**
	This module includes functions to work with HTML.

	It publically imports the DOM module to get started.
	Then it adds a number of functions to enhance html
	DOM documents and make other changes, like scripts
	and stylesheets.
*/
module arsd.html;

public import arsd.dom;
import std.array;
import std.string;
import std.variant;
import core.vararg;
import std.exception;

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
				i.id = i.name;
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
			f.onsubmit = `var failed = null; var failedMessage = ''; with(this) { ` ~ formValidation ~ '\n' ~ ` if(failed != null) { alert('Please complete all required fields.\n' + failedMessage); failed.focus(); return false; } `~os~` return true; }`;
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
			button.onclick = "displayDatePicker('"~name~"');";
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
	foreach(item; document.getElementsBySelector(".striped")) {
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
	foreach(e; document.getElementsBySelector("input[filter_what]")) {
		auto filterWhat = e.filter_what;
		if(filterWhat[0] == '#')
			filterWhat = filterWhat[1..$];

		auto fw = document.getElementById(filterWhat);
		assert(fw !is null);

		foreach(a; fw.getElementsBySelector(e.filter_by)) {
			a.addClass("filterable_content");
		}

		e.removeAttribute("filter_what");
		e.removeAttribute("filter_by");

		e.onkeydown = e.onkeyup = `
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

void translateInputTitles(Document document) {
	translateInputTitles(document.root);
}

/// find <input> elements with a title. Make the title the default internal content
void translateInputTitles(Element rootElement) {
	foreach(form; rootElement.getElementsByTagName("form")) {
		string os;
		foreach(e; form.getElementsBySelector("input[type=text][title]")) {
			if(e.hasClass("has-placeholder"))
				continue;
			e.addClass("has-placeholder");
			e.onfocus = e.onfocus ~ `
				removeClass(this, 'default');
				if(this.value == this.getAttribute('title'))
					this.value = '';
			`;

			e.onblur = e.onblur ~ `
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

			if(e.value == "") {
				e.value = e.title;
				e.addClass("default");
			}
		}

		form.onsubmit = os ~ form.onsubmit;
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

abstract class CssPart {
	override string toString() const;
	CssPart clone() const;
}

class CssAtRule : CssPart {
	this() {}
	this(ref string css) {
		assert(css.length);
		assert(css[0] == '@');

		int braceCount = 0;

		foreach(i, c; css) {
			if(braceCount == 0 && c == ';') {
				content = css[0 .. i + 1];
				css = css[i + 1 .. $];
				break;
			}

			if(c == '{')
				braceCount++;
			if(c == '}') {
				braceCount--;
				if(braceCount < 0)
					throw new Exception("Bad CSS: mismatched }");

				if(braceCount == 0) {
					content = css[0 .. i + 1];
					css = css[i + 1 .. $];
					break;
				}
			}
		}
	}

	string content;

	override CssAtRule clone() const {
		auto n = new CssAtRule();
		n.content = content;
		return n;
	}
	override string toString() const { return content; }
}

import std.stdio;

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

		contents = lexCss(content);
	}

	string[] selectors;
	CssPart[] contents;

	override CssRuleSet clone() const {
		auto n = new CssRuleSet();
		n.selectors = selectors.dup;
		n.contents = contents.dup;
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
			foreach(innerSelector; selectors)
				levelOne.selectors ~= outerSelector ~ " " ~ innerSelector;
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

	override CssRule clone() const {
		auto n = new CssRule();
		n.content = content;
		return n;
	}

	override string toString() const { return content ~ ";"; }
}

CssPart[] lexCss(string css) {
	import std.regex;
	css = std.regex.replace(css, regex(r"\/\*[^*]*\*+([^/*][^*]*\*+)*\/", "g"), "");

	CssPart[] ret;
	css = css.stripLeft();

	while(css.length > 1) {
		CssPart p;

		if(css[0] == '@') {
			p = new CssAtRule(css);
		} else {
			// non-at rules can be either rules or sets.
			// The question is: which comes first, the ';' or the '{' ?

			auto endOfStatement = css.indexOf(";");
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
		auto set = cast(CssRuleSet) part;
		if(set is null)
			ret ~= part;
		else {
			ret ~= set.deNest();
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

		functions["test"] = delegate dstring(dstring[] args) {
			assert(0, to!string(args.length) ~ " args: " ~ to!string(args));
			return null;
		};
	}

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

	string expand(string srcutf8) {
		auto src = expand(to!dstring(srcutf8));
		return to!string(src);
	}

	private int depth = 0;
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
					(c >= '0' && c <= '0')
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
				break;
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
				break;
				default:
					goto doReplacement;
			}

			doReplacement:
				if(endingSliceForReplacement < src.length && src[endingSliceForReplacement] == ';') {
					endingSliceForReplacement++;
					addTrailingSemicolon = true; // don't want a doubled semicolon
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
				else if(functionName in variables)
					returned = variables[functionName];
				else if(functionName in macros) {
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
	}

	// prefixed(border-radius: 12px);
	dstring prefixed(dstring[] args) {
		dstring ret;
		foreach(prefix; ["-moz-"d, "-webkit-"d, "-o-"d, "-ms-"d, "-khtml-"d, ""d])
			ret ~= prefix ~ args[0] ~ ";";
		return ret;
	}

	string expandAndDenest(string cssSrc) {
		return cssToString(denestCss(lexCss(this.expand(cssSrc))));
	}
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
			for(var %1$s = 0; %1$s < %2$s.length; %1$s++) {
				var %3$s = %2$s[%1$s];
				%4$s
		}"d, iteratorName, temporaryName, variableName, insideCode, arrayName);

		auto code = writer.data;

		return to!dstring(code);
	}
}

string beautifyCss(string css) {
	css = css.replace("{", " {\n\t");
	css = css.replace(";", ";\n\t");
	css = css.replace("\t}", "}\n\n");
	return css.strip;
}

/+
void main() {
	import std.stdio;

	writeln((denestCss(`
		label {
			color: black;
			span {
				background-color: red;
			}

			> input {
				orange;
			}
		}

		span { hate: vile; }

		@import url('adasdsa/asdsa');

		cool,
		that {
			color: white;
			this {
				border: none;
			}
		}
	`)));
}
+/

/++
	This adds nesting, named blocks, and simple macros to css, provided
	you follow some rules.

	Since it doesn't do a real parsing, you need to put the right
	tokens on the right line so it knows what is going on.

	1) When nesting, always put the { on the same line.
	2) Don't put { on lines without selectors


	Examples:

		NESTING:

			label {
				color: red;

				span {

				}
			}

		NAMED BLOCKS (for mixing in):

			@name(test) {
				color: green;
			}

			input {
				@mixin(test);
			}

		VARIABLES:

			@let(a = red); // note these are immutable

			div {
				color: @var(a); // it's just text replacement...
			}

		FUNCTIONS:

			Functions are pre-defined. The closest you can get
			to your own are mixins.

			@funname(arg, args...);

			OR

			@funname(arg, args...) { final_arg }


			Unknown function names are passed through without
			modification.


	It works by extracting mixins first, then expanding nested items,
	then mixing in the mixins, and finally, doing variable replacement.

	But, you'll see that aside from nesting, it's all done the same
	way.


	Alas, this doesn't do extra useful things like accessing the
	dynamic inherit values because it's just text replacement on
	the stylesheet.


	@foreach(k; v) {

	}

	for(var counter_1 = 0 < counter_1 < v.length; counter_1++) {
		var k = v[counter_1];
		/*[original code]*/
	}
+/
string improveCss(string css) {
	return null;
}
