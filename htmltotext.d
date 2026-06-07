/++
	Converts HTML to plain text. Can also output VT escape sequences for terminal output.

	The exact output of this is subject to change - it is just what appears nice for me. (I actually use this on my personal email setup.)
+/
module arsd.htmltotext;

import arsd.dom;
import arsd.color;
import std.string;

import std.uni : isWhite;
import std.string : indexOf, startsWith, endsWith, strip;

///
class HtmlConverter {
	int width;

	/++
		Will enable color output using VT codes. Determines color through dom.d's css support, which means you need to apply a stylesheet first.

		---
		import arsd.dom;

		auto document = new Document(source_code_for_html);
		auto stylesheet = new Stylesheet(source_code_for_css);
		stylesheet.apply(document);
		---
	+/
	bool enableVtOutput;


	string color;
	string backgroundColor;

	///
	void htmlToText(Element element, bool preformatted, int width) {
		string color, backgroundColor;
		if(enableVtOutput) {
			color = element.computedStyle.getValue("color");
			backgroundColor = element.computedStyle.getValue("background-color");
		}

		string originalColor = this.color, originalBackgroundColor = this.backgroundColor;

		this.color = color.length ? color : this.color;
		this.backgroundColor = backgroundColor.length ? backgroundColor : this.backgroundColor;

		scope(exit) {
			// the idea is as we pop working back up the tree, it restores what it was here
			this.color = originalColor;
			this.backgroundColor = originalBackgroundColor;
		}


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
				case "trlol":
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
				case "tr":
					startBlock(2);
					sinkChildren();
					endBlock();
				break;
				case "td":
					startBlock(0);
					sinkChildren();
					endBlock();
				break;
				case "a":
					sinkChildren();
					if(element.href != element.innerText) {
						sink(' ', false);
						sink('<', false);
						// I want the link itself to NOT word wrap
						// to make for easier double-clicking of it in
						// the terminal
						foreach(dchar ch; element.href)
							sink(ch, false, int.max);
						sink('>', false);
					}
				break;
				case "span":
					if(enableVtOutput) {
						auto csc = color; // element.computedStyle.getValue("color");
						if(csc.length) {
							auto c = Color.fromString(csc);
							s ~= format("\033[38;2;%d;%d;%dm", c.r, c.g, c.b);
						}

						bool bold = element.computedStyle.getValue("font-weight") == "bold";

						if(bold)
							s ~= "\033[1m";

						sinkChildren();

						if(bold)
							s ~= "\033[0m";
						if(csc.length)
							s ~= "\033[39m";
					} else {
						sinkChildren();
					}
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
					if(enableVtOutput) {
						s ~= "\033[1m";
						sinkChildren();
						s ~= "\033[0m";
					} else {
						sink('*', false);
						sinkChildren();
						sink('*', false);
					}
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
					startBlock(2);
					sinkChildren();
					endBlock();
					ulDepth--;
				break;
				case "ol":
					olDepth++;
					startBlock(2);
					sinkChildren();
					endBlock();
					olDepth--;
				break;
				case "li":
					startBlock();

					//sink('\t', true);
					/*
					foreach(cnt; 0 .. olDepth + ulDepth) {
						sink(' ', true);
						sink(' ', true);
					}
					*/
					if(olDepth)
						sink('*', false);
					if(ulDepth)
						sink('*', false);
					sink(' ', true);

					sinkChildren();

					endBlock();
				break;

				case "dl":
				case "dt":
				case "dd":
					startBlock(element.tagName == "dd" ? 2 : 0);
					sinkChildren();
					endBlock();
				break;

				case "h1":
					startBlock();
					sink('#', true);
					sink('#', true);
					sink(' ', true);
					sinkChildren();
					sink(' ', true);
					sink('#', true);
					sink('#', true);
					endBlock();
				break;
				case "h2", "h3":
					startBlock();
					sinkChildren();
					sink('\n', true);
					foreach(dchar ch; element.innerText)
						sink(element.tagName == "h2" ? '=' : '-', false);
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
					startBlock(4);
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

	///
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

		return convert(start, wantWordWrap, wrapAmount);
	}

	///
	string convert(Element start, bool wantWordWrap = true, int wrapAmount = 74) {
		htmlToText(start, false, wrapAmount);
		return s;
	}

	///
	void reset() {
		s = null;
		justOutputWhitespace = true;
		justOutputBlock = true;
		justOutputMargin = true;
	}

	///
	string s;
	bool justOutputWhitespace = true;
	bool justOutputBlock = true;
	bool justOutputMargin = true;
	int lineLength;

	void sink(dchar item, bool preformatted, int lineWidthOverride = int.min) {

		if(needsIndent && item != '\n') {
			lineLength += doIndent();
			needsIndent = false;
		}

		int width = lineWidthOverride == int.min ? this.width : lineWidthOverride;
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
					lineLength = cast(int)(os[idx+1..$].length);
					lineLength += doIndent();
					s ~= os[idx + 1 .. $];
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
				needsIndent = true;
				justOutputWhitespace = true;
			}

		}


		if(item == '\n') {
			lineLength = 0;
			needsIndent = true;
		} else
			lineLength ++;


		if(!justOutputWhitespace) {
			justOutputBlock = false;
			justOutputMargin = false;
		}
	}

	int doIndent() {
		int cnt = 0;
		foreach(i; indentStack)
			foreach(lol; 0 .. i) {
				s ~= ' ';
				cnt++;
			}
		return cnt;
	}

	int[] indentStack;
	bool needsIndent = false;

	void startBlock(int indent = 0) {

		indentStack ~= indent;

		if(!justOutputBlock) {
			s ~= "\n";
			lineLength = 0;
			needsIndent = true;
			justOutputBlock = true;
		}
		if(!justOutputMargin) {
			s ~= "\n";
			lineLength = 0;
			needsIndent = true;
			justOutputMargin = true;
		}
	}
	void endBlock() {
		if(indentStack.length)
			indentStack = indentStack[0 .. $ - 1];

		if(!justOutputMargin) {
			s ~= "\n";
			lineLength = 0;
			needsIndent = true;
			justOutputMargin = true;
		}
	}
}

///
string htmlToText(string html, bool wantWordWrap = true, int wrapAmount = 74) {
	auto converter = new HtmlConverter();
	return converter.convert(html, wantWordWrap, wrapAmount);
}

