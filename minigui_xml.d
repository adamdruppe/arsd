/++
	A small extension module to [arsd.minigui] that adds
	functions for creating widgets and windows from short
	XML descriptions.

	If you choose to use this, it will require [arsd.dom]
	to be compiled into your project too.

	---
	import arsd.minigui_xml;
	Window window = createWindowFromXml(`
		<MainWindow>
			<Button label="Hi!" />
		</MainWindow>
	`);
	---


	To add custom widgets to the minigui_xml factory, you need
	to register them with FIXME.

	You can attach some events right in the XML using attributes.
	The attribute names are `onEVENTNAME` or `ondirectEVENTNAME`
	and the values are one of the following three value types:

	$(LIST
		* If it starts with `&`, it is a delegate you need
		  to register using the FIXME function.

		* If it starts with `(`, it is a string passed to
		  the [arsd.dom.querySelector] function to get an
		  element reference

		* Otherwise, it tries to call a script function (if
		  scripting is available).
	)

	Keep in mind
	For example, to make a page widget that changes based on a
	drop down selection, you may:

	```xml
		<DropDownSelection onchange="$(+PageWidget).setCurrentTab">
			<option>Foo</option>
			<option>Bar</option>
		</DropDownSelection>
		<PageWidget name="mypage">
			<!-- contents elided -->
		</PageWidget>
	```

	That will create a select widget that when it changes, it will
	look for the next PageWidget sibling (that's the meaning of `+PageWidget`,
	see css selector syntax for more) and call its `setCurrentTab`
	method.

	Since the function knows `setCurrentTab` takes an integer, it will
	automatically pull the `intValue` member out of the event and pass
	it to the method.

	The given XML is the same as the following D:

	---
		auto select = new DropDownSelection(parent);
		select.addOption("Foo");
		select.addOption("Bar");
		auto page = new PageWidget(parent);
		page.name = "mypage";

		select.addEventListener("change", (Event event)
		{
			page.setCurrentTab(event.intValue);
		});
	---
+/
module arsd.minigui_xml;

public import arsd.minigui;
public import arsd.minigui : Event;

import arsd.textlayouter;

import arsd.dom;

import std.conv;
import std.exception;
import std.functional : toDelegate;
import std.string : strip;
import std.traits;

private template ident(T...)
{
	static if(is(T[0]))
		alias ident = T[0];
	else
		alias ident = void;
}

enum ParseContinue { recurse, next, abort }

alias WidgetFactory = ParseContinue delegate(Widget parent, Element element, out Widget result);
alias WidgetTextHandler = void delegate(Widget widget, string text);

WidgetFactory[string] widgetFactoryFunctions;
WidgetTextHandler[string] widgetTextHandlers;

void delegate(string eventName, Widget, Event, string content) xmlScriptEventHandler;
static this()
{
	xmlScriptEventHandler = toDelegate(&nullScriptEventHandler);
}

void nullScriptEventHandler(string eventName, Widget w, Event e, string)
{
	import std.stdio : stderr;

	stderr.writeln("Ignoring event ", eventName, " ", e, " on widget ", w.elementName, " because xmlScriptEventHandler is not set");
}

private bool startsWith(T)(T[] doesThis, T[] startWithThis)
{
	return doesThis.length >= startWithThis.length && doesThis[0 .. startWithThis.length] == startWithThis;
}

private bool isLower(char c)
{
	return c >= 'a' && c <= 'z';
}

private bool isUpper(char c)
{
	return c >= 'A' && c <= 'Z';
}

private char assumeLowerToUpper(char c)
{
	return cast(char)(c - 'a' + 'A');
}

private char assumeUpperToLower(char c)
{
	return cast(char)(c - 'A' + 'a');
}

string hyphenate(string argname)
{
	int hyphen;
	foreach (i, char c; argname)
		if (c.isUpper && (i == 0 || !argname[i - 1].isUpper))
			hyphen++;

	if (hyphen == 0)
		return argname;
	char[] ret = new char[argname.length + hyphen];
	int i;
	bool prevUpper;
	foreach (char c; argname)
	{
		bool upper = c.isUpper;
		if (upper)
		{
			if (!prevUpper)
				ret[i++] = '-';
			ret[i++] = c.assumeUpperToLower;
		}
		else
		{
			ret[i++] = c;
		}
		prevUpper = upper;
	}
	assert(i == ret.length);
	return cast(string) ret;
}

string unhyphen(string argname)
{
	int hyphen;
	foreach (i, char c; argname)
		if (c == '-' && (i == 0 || argname[i - 1] != '-'))
			hyphen++;

	if (hyphen == 0)
		return argname;
	char[] ret = new char[argname.length - hyphen];
	int i;
	char prev;
	foreach (char c; argname)
	{
		if (c != '-')
		{
			if (prev == '-' && c.isLower)
				ret[i++] = c.assumeLowerToUpper;
			else
				ret[i++] = c;
		}
		prev = c;
	}
	assert(i == ret.length);
	return cast(string) ret;
}

void initMinigui(Modules...)()
{
	import std.traits;
	import std.conv;

	static foreach (alias Module; Modules)
	{
		//pragma(msg, Module.stringof);
		appendMiniguiModule!Module;
	}
}

void appendMiniguiModule(alias Module, string prefix = null)()
{
	foreach(memberName; __traits(allMembers, Module)) static if(!__traits(isDeprecated, __traits(getMember, Module, memberName)))
	static if(memberName != "seperator")
	{
		alias Member = ident!(__traits(getMember, Module, memberName));
		static if(is(Member == class) && !isAbstractClass!Member && is(Member : Widget) && __traits(getProtection, Member) != "private")
		{
			widgetFactoryFunctions[prefix ~ memberName] = (Widget parent, Element element, out Widget widget)
			{
				static if(is(Member : MessageBox))
				{
					widget = new MessageBox("");
				}
				else static if(is(Member : Dialog))
				{
					widget = new Member(null, 0, 0); // FIXME
				}
				else static if(is(Member : Menu))
				{
					widget = new Menu(null, null);
				}
				else static if(is(Member : TooltipWindow))
				{
					widget = null;
				}
				else static if(is(Member : Window))
				{
					widget = new Member("test");
				}
				else
				{
					string[string] args;
					foreach(k, v; element.attributes)
						args[k] = v;

					enum paramNames = ParameterIdentifierTuple!(__traits(getMember, Member, "__ctor"));
					Parameters!(__traits(getMember, Member, "__ctor")) params;
					static assert(paramNames.length, Member);
					bool[cast(int)paramNames.length - 1] requiredParams;

					static foreach (idx, param; params[0 .. $-1])
					{{
						enum hyphenated = paramNames[idx].hyphenate;
						if (auto arg = hyphenated in args)
						{
							enforce(!requiredParams[idx], "May pass required parameter " ~ hyphenated ~ " only exactly once");
							requiredParams[idx] = true;
							static if(is(typeof(param) == MemoryImage))
							{

							}
							else static if(is(typeof(param) == Color))
							{
								params[idx] = Color.fromString(*arg);
							}
							else static if(is(typeof(param) == TextLayouter))
								params[idx] = null;
							else static if(is(typeof(param) == class))
								params[idx] = null;
							else static if(is(typeof(param) == delegate))
								params[idx] = null;
							else
								params[idx] = to!(typeof(param))(*arg);
						}
						else
						{
							enforce(false, "Missing required parameter " ~ hyphenated ~ " for Widget " ~ memberName);
							assert(false);
						}
					}}

					params[$-1] = cast(typeof(params[$-1])) parent;

					auto member = new Member(params);
					widget = member;

					foreach (argName, argValue; args)
					{
						if (argName.startsWith("on-"))
						{
							auto eventName = argName[3 .. $].unhyphen;
							widget.addEventListener(eventName, (event) { xmlScriptEventHandler(eventName, member, event, argValue); });
						}
						else if (argName == "name")
							member.name = argValue;
						else if (argName == "statusTip")
							member.statusTip = argValue;
						else
						{
							argName = argName.unhyphen;
							switch (argName)
							{
								static foreach (idx, param; params[0 .. $-1])
								{
									case paramNames[idx]:
								}
									break;
								static if (is(typeof(Member.addParameter)))
								{
								default:
									member.addParameter(argName, argValue);
									break;
								}
								else
								{
									// TODO: add generic parameter setting here (iterate by UDA maybe)
								default:
									enforce(false, "Unknown parameter " ~ argName ~ " for Widget " ~ memberName);
									assert(false);
								}
							}
						}
					}
				}
				return ParseContinue.recurse;
			};

			enum hasText = is(typeof(Member.text) == string) || is(typeof(Member.text()) == string);
			enum hasContent = is(typeof(Member.content) == string) || is(typeof(Member.content()) == string);
			enum hasLabel = is(typeof(Member.label) == string) || is(typeof(Member.label()) == string);
			static if (hasText || hasContent || hasLabel)
			{
				enum member = hasText ? "text" : hasContent ? "content" : hasLabel ? "label" : null;
				widgetTextHandlers[memberName] = (Widget widget, string text)
				{
					auto w = cast(Member)widget;
					assert(w, "Called widget text handler with widget of type "
						~ typeid(widget).name ~ " but it was registered for "
						~ memberName ~ " which is incompatible");
					mixin("w.", member, " = w.", member, " ~ text;");
				};
			}

			// TODO: might want to check for child methods/structs that register as child nodes
		}
	}
}

///
Widget makeWidgetFromString(string xml, Widget parent)
{
	auto document = new Document(xml, true, true);
	auto r = document.root;
	return miniguiWidgetFromXml(r, parent);
}

///
Window createWindowFromXml(string xml)
{
	return createWindowFromXml(new Document(xml, true, true));
}
///
Window createWindowFromXml(Document document)
{
	auto r = document.root;
	return cast(Window) miniguiWidgetFromXml(r, null);
}
///
Widget miniguiWidgetFromXml(Element element, Widget parent)
{
	Widget w;
	miniguiWidgetFromXml(element, parent, w);
	return w;
}
///
ParseContinue miniguiWidgetFromXml(Element element, Widget parent, out Widget w)
{
	assert(widgetFactoryFunctions !is null, "No widget factories have been registered, register them using initMinigui!(arsd.minigui); at startup");

	if (auto factory = element.tagName in widgetFactoryFunctions)
	{
		auto c = (*factory)(parent, element, w);

		if (c == ParseContinue.recurse)
		{
			c = ParseContinue.next;
			Widget dummy;
			foreach (child; element.children)
				if (miniguiWidgetFromXml(child, w, dummy) == ParseContinue.abort)
				{
					c = ParseContinue.abort;
					break;
				}
		}
		return c;
	}
	else if (element.tagName == "#text")
	{
		string text = element.nodeValue.strip;
		if (text.length)
		{
			assert(parent, "got xml text without parent, make sure you only pass elements!");
			if (auto factory = parent.elementName in widgetTextHandlers)
				(*factory)(parent, text);
			else
			{
				import std.stdio : stderr;

				stderr.writeln("WARN: no text handler for widget ", parent.elementName, " ~= ", [text]);
			}
		}
		return ParseContinue.next;
	}
	else
	{
		enforce(false, "Unknown tag " ~ element.tagName);
		assert(false);
	}
}

string elementName(Widget w)
{
	if (w is null)
		return null;
	auto name = typeid(w).name;
	foreach_reverse (i, char c; name)
		if (c == '.')
			return name[i + 1 .. $];
	return name;
}

