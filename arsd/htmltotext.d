module arsd.htmltotext;

import arsd.dom;
import std.string;
import std.array : replace;

string repeat(string s, int num) {
	string ret;
	foreach(i; 0 .. num)
		ret ~= s;
	return ret;
}

import std.stdio;

static import std.regex;
string htmlToText(string html, bool wantWordWrap = true, int wrapAmount = 74) {
	Document document = new Document;


	html = html.replace("&nbsp;", " ");
	html = html.replace("&#160;", " ");
	html = html.replace("&#xa0;", " ");
	html = html.replace("\n", " ");
	html = html.replace("\r", " ");
	html = std.regex.replace(html, std.regex.regex("[\n\r\t \u00a0]+", "gm"), " ");

	document.parse("<roottag>" ~ html ~ "</roottag>");

	Element start;
	auto bod = document.getElementsByTagName("body");
	if(bod.length)
		start = bod[0];
	else
		start = document.root;

	start.innerHTML = start.innerHTML().replace("<br />", "\u0001");

    again:
    	string result = "";
	foreach(ele; start.tree) {
		if(ele is start) continue;
		if(ele.nodeType != 1) continue;

		switch(ele.tagName) {
			case "b":
			case "strong":
				ele.innerText = "*" ~ ele.innerText ~ "*";
				ele.stripOut();
				goto again;
			break;
			case "i":
			case "em":
				ele.innerText = "/" ~ ele.innerText ~ "/";
				ele.stripOut();
				goto again;
			break;
			case "u":
				ele.innerText = "_" ~ ele.innerText ~ "_";
				ele.stripOut();
				goto again;
			break;
			case "h1":
				ele.innerText = "\r" ~ ele.innerText ~ "\n" ~ repeat("=", ele.innerText.length) ~ "\r";
				ele.stripOut();
				goto again;
			break;
			case "h2":
				ele.innerText = "\r" ~ ele.innerText ~ "\n" ~ repeat("-", ele.innerText.length) ~ "\r";
				ele.stripOut();
				goto again;
			break;
			case "h3":
				ele.innerText = "\r" ~ ele.innerText.toUpper ~ "\r";
				ele.stripOut();
				goto again;
			break;
			case "td":
			case "p":
			/*
				if(ele.innerHTML.length > 1)
					ele.innerHTML = "\r" ~ wrap(ele.innerHTML) ~ "\r";
				ele.stripOut();
				goto again;
			*/
			break;
			case "a":
				string href = ele.getAttribute("href");
				if(href) {
					if(ele.innerText != href)
						ele.innerText = ele.innerText ~ " <" ~ href ~ "> ";
				}
				ele.stripOut();
				goto again;
			break;
			case "ol":
			case "ul":
				ele.innerHTML = "\r" ~ ele.innerHTML ~ "\r";
			break;
			case "li":
				ele.innerHTML = "\t* " ~ ele.innerHTML ~ "\r";
				ele.stripOut();
			break;
			case "sup":
				ele.innerText = "^" ~ ele.innerText;
				ele.stripOut();
			break;
			/*
			case "img":
				string alt = ele.getAttribute("alt");
				if(alt)
					result ~= ele.alt;
			break;
			*/
			default:
				ele.stripOut();
				goto again;
		}
	}

    again2:
	start.innerHTML = start.innerHTML().replace("\u0001", "\n");

	foreach(ele; start.tree) {
		if(ele.tagName == "td") {
			if(ele.directText().strip().length) {
				ele.prependText("\r");
				ele.appendText("\r");
			}
			ele.stripOut();
			goto again2;
		} else if(ele.tagName == "p") {
			if(strip(ele.innerText()).length > 1) {
				string res = "";
				string all = ele.innerText().replace("\n \n", "\n\n");
				foreach(part; all.split("\n\n"))
					res ~= "\r" ~ strip( wantWordWrap ? wrap(part, /*74*/ wrapAmount) : part ) ~ "\r";
				ele.innerText = res;
			} else
				ele.innerText = strip(ele.innerText);
			ele.stripOut();
			goto again2;
		}
	}

	result = start.innerText();
	result = squeeze(result, " ");

	result = result.replace("\r ", "\r");
	result = result.replace(" \r", "\r");

	//result = result.replace("\u00a0", " ");


	result = squeeze(result, "\r");
	result = result.replace("\r", "\n\n");

	result = result.replace("&#33303;", "'"); // HACK: this shouldn't be needed, but apparently is in practice surely due to a bug elsewhere
	result = result.replace("&quot;", "\""); // HACK: this shouldn't be needed, but apparently is in practice surely due to a bug elsewhere
	//result = htmlEntitiesDecode(result);  // for special chars mainly

	//a = std.regex.replace(a, std.regex.regex("(\n\t)+", "g"), "\n"); //\t");
	return result.strip;
}
