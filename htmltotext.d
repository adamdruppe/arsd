///
module arsd.htmltotext;

import arsd.dom;
import arsd.color;
import std.string;

import std.uni : isWhite;

class HtmlConverter {
	int width;

	void htmlToText(Element element, bool preformatted, int width) {
		this.width = width;
		if(auto tn = cast(TextNode) element) {
			foreach(dchar ch; tn.nodeValue) {
				sink(ch, preformatted);
			}
		} else {
			void sinkChildren() {
				foreach(child; element.childNodes)
					htmlToText(child, preformatted, width);
			}
			switch(element.tagName) {
				case "head", "script", "style":
					// intentionally blank
				break;
				// The table stuff is removed right now because while it looks
				// ok for test tables, it isn't working well for the emails I have
				// - it handles data ok but not really nested layouts.
				case "trfixme":
					auto children = element.childElements;

					auto tdWidth = (width - cast(int)(children.length)*3) / cast(int)(children.length);
					if(tdWidth < 12) {
						// too narrow to be reasonable
						startBlock();
						sinkChildren();
						endBlock();
					} else {
						string[] tdBlocks;
						int longestBlock;
						foreach(child; children) {
							auto fmt = new HtmlConverter();

							fmt.htmlToText(child, false, tdWidth);
							tdBlocks ~= fmt.s;
							int lineCount = 1;
							foreach(ch; fmt.s)
								if(ch == '\n')
									lineCount++;
							if(lineCount > longestBlock)
								longestBlock = lineCount;
						}

						if(s.length && s[$-1] != '\n')
							s ~= '\n';
						foreach(lineNumber; 0 .. longestBlock) {
							foreach(bidx, ref block; tdBlocks) {
								auto ob = block;
								if(bidx)
									s ~= " | ";
								if(block.length) {
									auto idx = block.indexOf("\n");
									if(idx == -1)
										idx = block.length;

									s ~= block[0 .. idx];

									if(idx == block.length)
										block = block[$..$];
									else
										block = block[idx + 1 .. $];
								}

								if(ob.length < tdWidth)
								foreach(a; 0 .. tdWidth - block.length)
									s ~= " ";

							}
							s ~= "\n";
						}

						foreach(a; 0 .. children.length) {
							foreach(w; 0 .. tdWidth) {
								s ~= "-";
							}
							if(a +1 != children.length)
								s ~= "-+-";
						}
						s ~= "\n";
					}
				break;
				case "a":
					sinkChildren();
					if(element.href != element.innerText) {
						sink(' ', false);
						sink('<', false);
						foreach(dchar ch; element.href)
							sink(ch, false);
						sink('>', false);
					}
				break;
				case "span":
					/*
					auto csc = element.computedStyle.getValue("color");
					if(csc.length) {
						auto c = Color.fromString(csc);
						s ~= format("\033[38;2;%d;%d;%dm", c.r, c.g, c.b);
					}
					sinkChildren();

					if(csc.length)
						s ~= "\033[39m";
					*/
				break;
				case "p":
					startBlock();
					sinkChildren();
					endBlock();
				break;
				case "b", "strong":
				case "em", "i":
					if(element.innerText.length == 0)
						break;
					sink('*', false);
					sinkChildren();
					sink('*', false);
				break;
				case "u":
					if(element.innerText.length == 0)
						break;
					sink('_', false);
					sinkChildren();
					sink('_', false);
				break;
				case "ul":
					ulDepth++;
					sinkChildren();
					ulDepth--;
				break;
				case "ol":
					olDepth++;
					sinkChildren();
					olDepth--;
				break;
				case "li":
					startBlock();

					//sink('\t', true);
					sink(' ', true);
					sink(' ', true);
					if(olDepth)
						sink('*', false);
					if(ulDepth)
						sink('*', false);
					sink(' ', true);

					sinkChildren();

					endBlock();
				break;

				case "h1", "h2":
					startBlock();
					sinkChildren();
					sink('\n', true);
					foreach(dchar ch; element.innerText)
						sink(element.tagName == "h1" ? '=' : '-', false);
					endBlock();
				break;

				case "hr":
					startBlock();
					foreach(i; 0 .. width / 4)
						sink(' ', true);
					foreach(i; 0 .. width / 2)
						sink('-', false);
					endBlock();
				break;

				case "br":
					sink('\n', true);
				break;
				case "div":
					startBlock();

					/*
					auto csc = element.computedStyle.getValue("background-color");
					if(csc.length) {
						auto c = Color.fromString(csc);
						s ~= format("\033[48;2;%d;%d;%dm", c.r, c.g, c.b);
					}
					*/

					sinkChildren();

					/*
					if(csc.length)
						s ~= "\033[49m";
					*/

					endBlock();
				break;
				case "pre":
					startBlock();
					foreach(child; element.childNodes)
						htmlToText(child, true, width);
					endBlock();
				break;
				default:
					sinkChildren();
			}
		}
	}

	int olDepth;
	int ulDepth;

	string convert(string html, bool wantWordWrap = true, int wrapAmount = 74) {
		Document document = new Document;

		document.parse("<roottag>" ~ html ~ "</roottag>");

		Element start;
		auto bod = document.getElementsByTagName("body");
		if(bod.length)
			start = bod[0];
		else
			start = document.root;

		//import std.file;
		//auto stylesheet = new StyleSheet(readText("/var/www/dpldocs.info/experimental-docs/style.css"));
		//stylesheet.apply(document);

		htmlToText(start, false, wrapAmount);
		return s;
	}

	void reset() {
		s = null;
		justOutputWhitespace = true;
		justOutputBlock = true;
		justOutputMargin = true;
	}

	string s;
	bool justOutputWhitespace = true;
	bool justOutputBlock = true;
	bool justOutputMargin = true;
	int lineLength;

	void sink(dchar item, bool preformatted) {
		if(!preformatted && isWhite(item)) {
			if(!justOutputWhitespace) {
				item = ' ';
				justOutputWhitespace = true;
			} else {
				return;
			}
		} else {
			// if it is preformatted, we still need to keep track of if it is whitespace
			// so stuff like <br> is somewhat sane
			justOutputWhitespace = preformatted && isWhite(item);
		}

		s ~= item;

		if(lineLength >= width) {
			// rewind to the nearest space, if there is one, to break on a word boundary
			int c =  lineLength;
			bool broken;
			foreach_reverse(idx, char ch; s) {
				if(ch == '\n')
					break;
				if(ch == ' ') {
					auto os = s;
					s = os[0 .. idx];
					s ~= '\n';
					s ~= os[idx + 1 .. $];
					lineLength = cast(int)(os[idx+1..$].length);
					broken = true;
					break;
				}
				c--;
				if(c < 5)
					break;
			}

			if(!broken) {
				s ~= '\n';
				lineLength = 0;
				justOutputWhitespace = true;
			}

		}


		if(item == '\n')
			lineLength = 0;
		else
			lineLength ++;


		if(!justOutputWhitespace) {
			justOutputBlock = false;
			justOutputMargin = false;
		}
	}
	void startBlock() {
		if(!justOutputBlock) {
			s ~= "\n";
			lineLength = 0;
			justOutputBlock = true;
		}
		if(!justOutputMargin) {
			s ~= "\n";
			lineLength = 0;
			justOutputMargin = true;
		}
	}
	void endBlock() {
		if(!justOutputMargin) {
			s ~= "\n";
			lineLength = 0;
			justOutputMargin = true;
		}
	}
}

string htmlToText(string html, bool wantWordWrap = true, int wrapAmount = 74) {
	auto converter = new HtmlConverter();
	return converter.convert(html, true, wrapAmount);
}

string repeat(string s, ulong num) {
	string ret;
	foreach(i; 0 .. num)
		ret ~= s;
	return ret;
}

import std.stdio;
version(none)
void penis() {

    again:
    	string result = "";
	foreach(ele; start.tree) {
		if(ele is start) continue;
		if(ele.nodeType != 1) continue;

		switch(ele.tagName) {
				goto again;
			case "h1":
				ele.innerText = "\r" ~ ele.innerText ~ "\n" ~ repeat("=", ele.innerText.length) ~ "\r";
				ele.stripOut();
				goto again;
			case "h2":
				ele.innerText = "\r" ~ ele.innerText ~ "\n" ~ repeat("-", ele.innerText.length) ~ "\r";
				ele.stripOut();
				goto again;
			case "h3":
				ele.innerText = "\r" ~ ele.innerText.toUpper ~ "\r";
				ele.stripOut();
				goto again;
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
				if(href && !ele.hasClass("no-brackets")) {
					if(ele.hasClass("href-text"))
						ele.innerText = href;
					else {
						if(ele.innerText != href)
							ele.innerText = ele.innerText ~ " <" ~ href ~ "> ";
					}
				}
				ele.stripOut();
				goto again;
			case "ol":
			case "ul":
				ele.innerHTML = "\r" ~ ele.innerHTML ~ "\r";
			break;
			case "li":
				if(!ele.innerHTML.startsWith("* "))
					ele.innerHTML = "* " ~ ele.innerHTML ~ "\r";
				// ele.stripOut();
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
	//start.innerHTML = start.innerHTML().replace("\u0001", "\n");

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
		} else if(ele.tagName == "li") {
			auto part = ele.innerText;
			part = strip( wantWordWrap ? wrap(part, wrapAmount - 2) : part );
			part = "  " ~ part.replace("\n", "\n\v") ~ "\r";
			ele.innerText = part;
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

	result = result.replace("\v", "  ");

	result = result.replace("&#33303;", "'"); // HACK: this shouldn't be needed, but apparently is in practice surely due to a bug elsewhere
	result = result.replace("&quot;", "\""); // HACK: this shouldn't be needed, but apparently is in practice surely due to a bug elsewhere
	//result = htmlEntitiesDecode(result);  // for special chars mainly

	result = result.replace("\u0001 ", "\n");
	result = result.replace("\u0001", "\n");

	//a = std.regex.replace(a, std.regex.regex("(\n\t)+", "g"), "\n"); //\t");
	return result.strip;
}
