/++
	A small extension module to [arsd.minigu] that adds
	functions for creating widgets and windows from short
	XML descriptions.

	If you choose to use this, it will require [arsd.dom]
	to be compiled into your project too.

	---
	import arsd.minigui_xml;
	Window window = createWindow(`
		<MainWindow>
			<Button label="Hi!" />
		</MainWindow>
	`);
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
		static if(is(Member == class) && !isAbstractClass!Member && is(Member : Widget)) {
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


