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

		select.addEventListener("change", (Event event) {
			page.setCurrentTab(event.intValue);
		});
	---
+/
module arsd.minigui_xml;

public import arsd.minigui;

import arsd.dom;

private template ident(T...) {
	static if(is(T[0]))
		alias ident = T[0];
	else
		alias ident = void;
}

private
Widget delegate(string[string] args, Widget parent)[string] widgetFactoryFunctions;

private
void loadMiniguiPublicClasses() {
	if(widgetFactoryFunctions !is null)
		return;

	import std.traits;
	import std.conv;

	foreach(memberName; __traits(allMembers, mixin("arsd.minigui"))) static if(__traits(compiles, __traits(getMember, mixin("arsd.minigui"), memberName))) {
		alias Member = ident!(__traits(getMember, mixin("arsd.minigui"), memberName));
		static if(is(Member == class) && !isAbstractClass!Member && is(Member : Widget) && __traits(getProtection, Member) != "private") {
			widgetFactoryFunctions[memberName] = (string[string] args, Widget parent) {
				static if(is(Member : Dialog)) {
					return new Member();
				} else static if(is(Member : Window)) {
					return new Member("test");
				} else {
					auto paramNames = ParameterIdentifierTuple!(__traits(getMember, Member, "__ctor"));
					Parameters!(__traits(getMember, Member, "__ctor")) params;

					foreach(idx, param; params[0 .. $-1]) {
						if(auto arg = paramNames[idx] in args)
							params[idx] = to!(typeof(param))(*arg);
					}

					params[$-1] = parent;

					auto widget = new Member(params);

					if(auto st = "statusTip" in args)
						widget.statusTip = *st;
					if(auto st = "name" in args)
						widget.name = *st;
					return widget;
				}
			};
		}
	}
}

///
Widget makeWidgetFromString(string xml, Widget parent) {
	auto document = new Document(xml, true, true);
	auto r = document.root;
	return miniguiWidgetFromXml(r, parent);
}

///
Window createWindowFromXml(string xml) {
	return createWindowFromXml(new Document(xml, true, true));
}
///
Window createWindowFromXml(Document document) {
	auto r = document.root;
	return cast(Window) miniguiWidgetFromXml(r, null);
}
///
Widget miniguiWidgetFromXml(Element element, Widget parent) {
	if(widgetFactoryFunctions is null)
		loadMiniguiPublicClasses();
	if(auto factory = element.tagName in widgetFactoryFunctions) {
		auto p = (*factory)(element.attributes, parent);
		foreach(child; element.children)
			if(child.tagName != "#text")
				miniguiWidgetFromXml(child, p);
		return p;
	} else {
		import std.stdio;
		writeln("Unknown class: ", element.tagName);
		return null;
	}
}


