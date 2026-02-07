/++
	Support functions to build a custom unix-style shell.


	$(PITFALL
		Do NOT use this to try to sanitize, escape, or otherwise parse what another shell would do with a string! Every shell is different and this implements my rules which may differ in subtle ways from any other common shell.

		If you want to use this to understand a command, also use it to execute that command so you get what you expect.
	)

	Some notes about this shell syntax:
	$(LIST
		* An "execution batch" is a set of command submitted to be run. This is typically a single command line or shell script.
		* ; means "execute the current command and wait for it to complete". If it returns a non-zero errorlevel, the current execution batch is aborted.
		* ;; means the same as ;, except that if it returned a non-zero errorlevel, the current batch is allowed to proceed.
		* & means "execute current command in the background"
		* ASCII space, tab, and newline outside of quotes are all collapsed to a single space, html style. If you want multiple commands in a single execution, use ;. Interactively, pressing enter usually means a new execution, but in a script, you need to use ; (or &, &&, or ||), not just newline, to separate commands.
	)

	History:
		Added October 18, 2025

	Bugs:
	$(LIST
		* a failure in a pipeline at any point should mark that command as failing, not just the first command.
		* `sleep 1 && sleep 1 &` only puts the second sleep in the background.
		* bash supports $'\e' which follows C escape rules inside the single quotes. want?
		* ${name:use_if_unset} not implemented. might not bother.
		* glob expansion is minimal - * works, but no ?, no [stuff]. The * is all i personally care about.
		* `substitution` and $(...) is not implemented
		* variable expansion ${IDENT} is not implemented.
		* no !history recall. or history command in general
		* job control is rudimentary - no fg, bg, jobs, ctrl+z, etc.
		* i'd like it to automatically set -o ignoreeof in some circumstances
		* prompt could be cooler
			PS1 = normal prompt
			PS2 = continuation prompt
			Bash shell executes the content of the PROMPT_COMMAND just before displaying the PS1 variable.

			bash does it with `\u` and stuff but i kinda think using `$USER` and such might make more sense.
		* i do `alias thing args...` instead of `alias thing="args..."`. i kinda prefer it this way tho
		* the api is not very good
		* ulimit? sourcing things too. aliases.
		* deeshrc is pulled from cwd
		* tab complete of available commands not implemented - get it from path search.
	)

	Questionable_ideas:
	$(LIST
		* be able to receive an external command, e.g. from vim hotkey

		* separate stdout and stderr more by default, allow stderr pipes.
		* custom completion scripts? prolly not bash compatible since the scripts would be more involved
		* some kind of scriptable cmdlet? a full on script language with shell stuff embeddable?
			see https://hush-shell.github.io/cmd/index.html for some ok ideas
		* do something fun with job control. idk what tho really.
		* can terminal emulators get notifications when the foreground process group changes? i don't think so but i could make a "poll again now" sequence since i control shell and possibly terminal emulator now.
		* change DISPLAY and such when attaching remote sessions
	)
+/
module arsd.shell;

import arsd.core;

import core.thread.fiber;

/++
	Holds some context needed for shell expansions.
+/
struct ShellContext {
	// stuff you set to interface with OS data
	string delegate(scope const(char)[] name) getEnvironmentVariable;
	string delegate(scope const(char)[] username) getUserHome; // for ~ expansion. if the username is null, it should look up the current user.

	// something you inform it of
	//bool isInteractive;

	// state you can set ahead of time and the shell context executor can modify
	string scriptName; // $0, special
	string[] scriptArgs; // $*, $@, $1...$n, $#. `shift` modifies it.
	string[string] vars;
	string[][string] aliases;
	int mostRecentCommandStatus; // $?

	// state managed internally whilst running
	ShellCommand[] jobs;
	string[] directoryStack;
	ShellLoop[] loopStack;

	bool exitRequested;

	private SchedulableTask jobToForeground;
}

struct ShellLoop {
	string[] args;
	int position;
	ShellLoop[] commands;
}

enum QuoteStyle {
	none, // shell might do special treatment of characters
	nonExpanding, // 'thing'. everything is unmodified in output
	expanding, // "thing". $variables can be expanded, but not {a,b}, {1..3}, ~, ? or * or similar glob stuff. note the ~ and {} expansions happen regardless of if such a file exists. ? and * remains ? and * unless there is a match. "thing" can also expand to multiple arguments, but not just because it has a space in it, only if the variable has a space in it. what madness lol. $* and $@ need to expand to multiple args tho
	/+
		$* = all args as a single string, but can be multiple args when interpreted (basically the command line)
		"$*" = the command line as a single arg
		$@ = the argv is preserved without converting back into string but any args with spaces can still be split
		"$@" = the only sane one tbh, forwards the args as argv w/o modification i think

		$1, $2, etc. $# is count of args
	+/
}

/++

+/
alias Globber = string[] delegate(ShellLexeme[] str, ShellContext context);

private bool isVarChar(char next) {
	return (next >= 'A' && next <= 'Z') || (next >= 'a' && next <= 'z') || next == '_' || (next >= '0' && next <= '9');
}

/++
	Represents one component of a shell command line as a precursor to parsing.
+/
struct ShellLexeme {
	string l;
	QuoteStyle quoteStyle;

	/++
		Expands shell arguments and escapes the glob characters, if necessary
	+/
	string[] toExpansions(ShellContext context) {
		final switch(quoteStyle) {
			case QuoteStyle.none:
			case QuoteStyle.expanding:
				// FIXME: if it is none it can return multiple arguments...
				// and subcommands can be executed here. `foo` and "`foo"` are things.

				/+
					Expanded in here both cases:
						* $VARs
						* ${VAR}s
						* $?, $@, etc.
						* `subcommand` and $(subcommand)
						* $((math))
					ONLY IF QuoteStyle.none:
						* {1..3}
						* {a,b}
						* ~, ~name

						* bash does glob expansions iff files actually match? but i think that's premature for us here. because `*'.d'` should work and we're only going to see the part inside or outside of the quote at this stage. hence why in non-expanding it escapes the glob chars.

						..... but echo "*" prints a * so it shouldn't be trying to glob in the expanding context either. glob is only possible if the star appears in the unquoted thing. maybe it is unquoted * and ? that gets the magic internal chars that are forbidden elsewhere instead of escaping the rest
				+/

				string[] ret;
				ret ~= null;
				size_t lastIndex = 0;
				for(size_t idx = 0; idx < l.length; idx++) {
					char ch = l[idx];

					if(ch == '$') {
						if(idx + 1 < l.length) {
							char next = l[idx + 1];
							string varName;
							size_t finalIndex;
							if(isVarChar(next)) {
								finalIndex = idx + 1;
								while(finalIndex < l.length && isVarChar(l[finalIndex])) {
									finalIndex++;
								}
								varName = l[idx + 1 .. finalIndex];
								finalIndex--; // it'll get ++'d again later
							} else if(next == '{') {
								// FIXME - var name enclosed in {}
							} else if(next == '(') {
								// FIXME - command substitution or arithmetic
							} else if(next == '?' || next == '*' || next == '@' || next == '#') {
								varName = l[idx + 1 .. idx + 2];
								finalIndex = idx + 1;
							}

							if(varName.length) {
								assert(finalIndex > 0);
								string varContent;
								bool useVarContent = true;

								foreach(ref r; ret)
									r ~= l[lastIndex .. idx];

								// if we're not in double quotes, these are allowed to expand to multiple args
								// but if we are they should be just one. in a normal unix shell anyway. idk
								switch(varName) {
									case "0":
										varContent = context.scriptName;
									break;
									case "?":
										varContent = toStringInternal(context.mostRecentCommandStatus);
									break;
									case "*":
										import arsd.string;
										varContent = join(context.scriptArgs, " ");
									break;
									case "@":
										// needs to expand similarly to {a,b,c}
										if(context.scriptArgs.length) {
											useVarContent = false;

											auto origR = ret.length;

											// FIXME: if quoteStyle ==  none, we can split each script arg on spaces too...

											foreach(irrelevant; 0 .. context.scriptArgs.length - 1)
												for(size_t i = 0; i < origR; i++)
													ret ~= ret[0].dup;

											foreach(exp; 0 .. context.scriptArgs.length)
												foreach(ref r; ret[origR * exp .. origR * (exp + 1)])
													r ~= context.scriptArgs[exp];
										}
									break;
									case "#":
										varContent = toStringInternal(context.scriptArgs.length);
									break;
									default:
									bool wasAllNumbers = true;
									foreach(char chn; varName) {
										if(!(chn >= '0' && chn <= '9')) {
											wasAllNumbers = false;
											break;
										}
									}

									if(wasAllNumbers) {
										import arsd.conv;
										auto idxn = to!int(varName);
										if(idxn == 0 || idxn > context.scriptArgs.length)
											throw new Exception("Shell variable argument out of range: " ~ varName);
										varContent = context.scriptArgs[idxn - 1];
									} else {
										if(varName !in context.vars) {
											if(context.getEnvironmentVariable) {
												auto ev = context.getEnvironmentVariable(varName);
												if(ev is null)
													throw new Exception("No such shell or environment variable: " ~ varName);
												varContent = ev;
											} else {
												throw new Exception("No such shell variable: " ~ varName);
											}
										} else {
											varContent = context.vars[varName];
										}
									}
								}

								if(useVarContent) {
									// FIXME: if quoteStyle ==  none, we can split varContent on spaces too...
									foreach(ref r; ret)
										r ~= varContent;
								}
								idx = finalIndex; // will get ++'d next time through the for loop
								lastIndex = finalIndex + 1;
							}
						}

						continue; // dollar sign standing alone is not something to expand
					}

					if(quoteStyle == QuoteStyle.none) {
						if(ch == '{') {
							// expand like {a,b} stuff
							// FIXME
							foreach(ref r; ret)
								r ~= l[lastIndex .. idx];

							int count = 0;
							size_t finalIndex;
							foreach(i2, ch2; l[idx .. $]) {
								if(ch2 == '{')
									count++;
								if(ch2 == '}')
									count--;
								if(count == 0) {
									finalIndex = idx + i2;
									break;
								}
							}

							if(finalIndex == 0)
								throw new Exception("unclosed {");

							auto expansionInnards = l[idx + 1 .. finalIndex];

							lastIndex = finalIndex + 1; // skip the closing }
							idx = finalIndex;

							auto origR = ret.length;

							import arsd.string;
							string[] expandedTo = expansionInnards.split(",");

							assert(expandedTo.length > 0);

							// FIXME: bash expands all of the first ones before doing any of the next ones
							// do i want to do it that way too? or do i not care?
							// {a,b}{c,d}
							// i do      ac bc ad bd
							// bash does ac ad bc bd

							// duplicate the original for each item beyond the first
							foreach(irrelevant; 0 .. expandedTo.length - 1)
								for(size_t i = 0; i < origR; i++)
									ret ~= ret[0].dup;

							foreach(exp; 0 .. expandedTo.length)
								foreach(ref r; ret[origR * exp .. origR * (exp + 1)])
									r ~= expandedTo[exp];

						} else if(ch == '~') {
							// expand home dir stuff

							size_t finalIndex = idx + 1;
							while(finalIndex < l.length && isVarChar(l[finalIndex])) {
								finalIndex++;
							}

							auto replacement = context.getUserHome(l[idx + 1 .. finalIndex]);
							if(replacement is null) {
								// no replacement done
							} else {
								foreach(ref r; ret)
									r ~= replacement;
								idx = finalIndex - 1;
								lastIndex = finalIndex;
							}
						}
					}
				}
				if(lastIndex)
					foreach(ref r; ret)
						r ~= l[lastIndex .. $];
				else if(ret.length == 1 && ret[0] is null) // was no expansion, reuse the original string
					ret[0] = l;

				return ret;
			case QuoteStyle.nonExpanding:
				return [l];
		}
	}
}

unittest {
	ShellContext context;
	context.mostRecentCommandStatus = 0;
	assert(ShellLexeme("$", QuoteStyle.none).toExpansions(context) == ["$"]); // stand alone = no replacement
	assert(ShellLexeme("$?", QuoteStyle.none).toExpansions(context) == ["0"]);

	context.getUserHome = (username) => (username == "me" || username.length == 0) ? "/home/me" : null;
	assert(ShellLexeme("~", QuoteStyle.none).toExpansions(context) == ["/home/me"]);
	assert(ShellLexeme("~me", QuoteStyle.none).toExpansions(context) == ["/home/me"]);
	assert(ShellLexeme("~/lol", QuoteStyle.none).toExpansions(context) == ["/home/me/lol"]);
	assert(ShellLexeme("~me/lol", QuoteStyle.none).toExpansions(context) == ["/home/me/lol"]);
	assert(ShellLexeme("~other", QuoteStyle.none).toExpansions(context) == ["~other"]); // not found = no replacement
}

/+
	/++
		The second thing should be have toSingleArg called on it
	+/
	EnvironmentPair toEnvironmentPair(ShellLexeme context) {
		assert(quoteStyle == QuoteStyle.none);

		size_t splitPoint = l.length;
		foreach(size_t idx, char ch; l) {
			if(ch == '=') {
				splitPoint = idx;
				break;
			}
		}

		if(splitPoint != l.length) {
			return EnvironmentPair(l[0 .. splitPoint], ShellLexeme(l[splitPoint + 1 .. $]));
		} else {
			return EnvironmentPair(null, ShellLexeme.init);
		}
	}

	/++
		Expands variables but not globs while replacing quotes and such. Note it is NOT safe to pass an expanded single arg to another shell
	+/
	string toExpandedSingleArg(ShellContext context) {
		return l;
	}

	/++
		Returns the value as an argv array, after shell expansion of variables, tildes, and globs

		Does NOT attempt to execute `subcommands`.
	+/
	string[] toExpandedArgs(ShellContext context, Globber globber) {
		return null;
	}
+/

/++
	This function in pure in all but formal annotation; it does not interact with the outside world.
+/
ShellLexeme[] lexShellCommandLine(string commandLine) {
	ShellLexeme[] ret;

	enum State {
		consumingWhitespace,
		readingWord,
		readingSingleQuoted,
		readingEscaped,
		readingExpandingContextEscaped,
		readingDoubleQuoted,
		readingSpecialSymbol,
		// FIXME: readingSubcommand for `thing`
		readingComment,
	}

	State state = State.consumingWhitespace;
	size_t first = commandLine.length;

	void endWord() {
		state = State.consumingWhitespace;
		first = commandLine.length; // we'll rewind upon encountering the next word, if there is one
	}

	foreach(size_t idx, char ch; commandLine) {
		again:
		final switch(state) {
			case State.consumingWhitespace:
				switch(ch) {
					case ' ', '\t', '\n':
						// the arg separators should all be collapsed to exactly one
						if(ret.length && !(ret[$-1].quoteStyle == QuoteStyle.none && ret[$-1].l == " "))
							ret ~= ShellLexeme(" ");
						continue;
					case '#':
						state = State.readingComment;
						continue;
					default:
						first = idx;
						state = State.readingWord;
						goto again;
				}
			case State.readingWord:
				switch(ch) {
					case '\'':
						if(first != idx)
							ret ~= ShellLexeme(commandLine[first .. idx]);
						first = idx + 1;
						state = State.readingSingleQuoted;
						break;
					case '\\':
						// a \ch can be treated as just a single quoted single char...
						if(first != idx)
							ret ~= ShellLexeme(commandLine[first .. idx]);
						first = idx + 1;
						state = State.readingEscaped;
						break;
					case '"':
						if(first != idx)
							ret ~= ShellLexeme(commandLine[first .. idx]);
						first = idx + 1;
						state = State.readingDoubleQuoted;
						break;
					case ' ':
						ret ~= ShellLexeme(commandLine[first .. idx]);
						ret ~= ShellLexeme(" "); // an argument separator
						endWord();
						continue;
					/+
					// single char special symbols
					case ';':
						if(first != idx)
							ret ~= ShellLexeme(commandLine[first .. idx]);
						ret ~= ShellLexeme(commandLine[idx .. idx + 1]);
						endWord();
						continue;
					break;
					+/
					// two-char special symbols
					case '|', '<', '>', '&', ';':
						if(first != idx)
							ret ~= ShellLexeme(commandLine[first .. idx]);
						first = idx;
						state = State.readingSpecialSymbol;
						break;
					default:
						// keep searching
				}
			break;
			case State.readingSpecialSymbol:
				switch(ch) {
					case '|', '<', '>', '&', ';':
						// include this as a two-char lexeme
						ret ~= ShellLexeme(commandLine[first .. idx + 1]);
						endWord();
						continue;
					default:
						// only include the previous char and send this back up
						ret ~= ShellLexeme(commandLine[first .. idx]);
						endWord();
						goto again;
				}
			break;
			case State.readingComment:
				if(ch == '\n') {
					endWord();
				}
			break;
			case State.readingSingleQuoted:
				switch(ch) {
					case '\'':
						ret ~= ShellLexeme(commandLine[first .. idx], QuoteStyle.nonExpanding);
						endWord();
					break;
					default:
				}
			break;
			case State.readingDoubleQuoted:
				switch(ch) {
					case '"':
						ret ~= ShellLexeme(commandLine[first .. idx], QuoteStyle.expanding);
						endWord();
					break;
					case '\\':
						state = State.readingExpandingContextEscaped;
						break;
					default:
				}
			break;
			case State.readingEscaped:
				if(ch >= 0x80 && ch <= 0xBF) {
					// continuation byte
					continue;
				} else if(first == idx) {
					// first byte, keep searching for continuations
					continue;
				} else {
					// same as if the user wrote the escaped character in single quotes
					ret ~= ShellLexeme(commandLine[first .. idx], QuoteStyle.nonExpanding);

					if(state == State.readingExpandingContextEscaped) {
						state = State.readingDoubleQuoted;
						first = idx;
					} else {
						endWord();
					}
					goto again;
				}
			case State.readingExpandingContextEscaped:
				if(ch == '"') {
					// the -1 trims out the \
					ret ~= ShellLexeme(commandLine[first .. idx - 1], QuoteStyle.expanding);
					state = State.readingDoubleQuoted;
					first = idx; // we need to INCLUDE the " itself
				} else {
					// this was actually nothing special, the backslash is kept in the double quotes
					state = State.readingDoubleQuoted;
				}
			break;
		}
	}

	if(first != commandLine.length) {
		if(state != State.readingWord && state != State.readingComment && state != State.readingSpecialSymbol)
			throw new Exception("ran out of data in inappropriate state");
		ret ~= ShellLexeme(commandLine[first .. $]);
	}

	return ret;
}

unittest {
	ShellLexeme[] got;

	got = lexShellCommandLine("FOO=bar");
	assert(got.length == 1);
	assert(got[0].l == "FOO=bar");

	// comments can only happen at whitespace contexts, not at the end of a single word
	got = lexShellCommandLine("FOO=bar#commentspam");
	assert(got.length == 1);
	assert(got[0].l == "FOO=bar#commentspam");

	got = lexShellCommandLine("FOO=bar #commentspam");
	assert(got.length == 2);
	assert(got[0].l == "FOO=bar");
	assert(got[1].l == " "); // arg separator still there even tho there is no arg cuz of the comment, but that's semantic

	got = lexShellCommandLine("#commentspam");
	assert(got.length == 0, got[0].l);

	got = lexShellCommandLine("FOO=bar ./prog");
	assert(got.length == 3);
	assert(got[0].l == "FOO=bar");
	assert(got[1].l == " "); // argument separator
	assert(got[2].l == "./prog");

	// all whitespace should be collapsed to a single argument separator
	got = lexShellCommandLine("FOO=bar          ./prog");
	assert(got.length == 3);
	assert(got[0].l == "FOO=bar");
	assert(got[1].l == " "); // argument separator
	assert(got[2].l == "./prog");

	got = lexShellCommandLine("'foo'bar");
	assert(got.length == 2);
	assert(got[0].l == "foo");
	assert(got[0].quoteStyle == QuoteStyle.nonExpanding);
	assert(got[1].l == "bar");
	assert(got[1].quoteStyle == QuoteStyle.none);

	// escaped single char works as if you wrote it in single quotes
	got = lexShellCommandLine("test\\'bar");
	assert(got.length == 3);
	assert(got[0].l == "test");
	assert(got[1].l == "'");
	assert(got[2].l == "bar");

	// checking for utf-8 decode of escaped char
	got = lexShellCommandLine("test\\\&raquo;bar");
	assert(got.length == 3);
	assert(got[0].l == "test");
	assert(got[1].l == "\&raquo;");
	assert(got[2].l == "bar");

	got = lexShellCommandLine(`"ok"`);
	assert(got.length == 1);
	assert(got[0].l == "ok");
	assert(got[0].quoteStyle == QuoteStyle.expanding);

	got = lexShellCommandLine(`"ok\"after"`);
	assert(got.length == 2);
	assert(got[0].l == "ok");
	assert(got[0].quoteStyle == QuoteStyle.expanding);
	assert(got[1].l == "\"after");
	assert(got[1].quoteStyle == QuoteStyle.expanding);

	got = lexShellCommandLine(`FOO=bar ./thing 'my ard' second_arg "quoted\"thing"`);
	assert(got.length == 10); // because quoted\"thing is two in this weird system
	assert(got[0].l == "FOO=bar");
	assert(got[1].l == " ");
	assert(got[2].l == "./thing");
	assert(got[3].l == " ");
	assert(got[4].l == "my ard");
	assert(got[5].l == " ");
	assert(got[6].l == "second_arg");
	assert(got[7].l == " ");
	assert(got[8].l == "quoted");
	assert(got[9].l == "\"thing");

	got = lexShellCommandLine("a | b c");
	assert(got.length == 7);

	got = lexShellCommandLine("a && b c");
	assert(got.length == 7);

	got = lexShellCommandLine("a > b c");
	assert(got.length == 7);

	got = lexShellCommandLine("a 2>&1 b c");
	assert(got.length == 9); // >& is also considered a special thing

}

struct ShellIo {
	enum Kind {
		inherit,
		fd,
		filename,
		pipedCommand,
		memoryBuffer
	}

	Kind kind;
	int fd;
	string filename;
	ShellCommand pipedCommand;

	bool append;
}

class ShellCommand {
	ShellIo stdin;
	ShellIo stdout;
	ShellIo stderr;
	// yes i know in unix you can do other fds too. do i care?

	string[] argv;
	EnvironmentPair[] environmentPairs;

	string terminatingToken;

	// set by the runners
	ShellContext* shellContext;
	private RunningCommand runningCommand;
	FilePath exePath; /// may be null in which case you might search or do built in, depending on the executor.

	private SchedulableTask shellTask;
}

/++
	A shell component - which is likely an argument, but that is a semantic distinction we can't make until parsing - may be made up of several lexemes. Think `foo'bar'`. This will extract them from the given array up to and including the next unquoted space or newline char.
+/
ShellLexeme[] nextComponent(ref ShellLexeme[] lexemes) {
	if(lexemes.length == 0)
		return lexemes[$ .. $];

	int pos;
	while(
		pos < lexemes.length &&
		!(
			// identify an arg or command separator
			lexemes[pos].quoteStyle == QuoteStyle.none &&
			(
				lexemes[pos].l == " " ||
				lexemes[pos].l == ";" ||
				lexemes[pos].l == ";;" ||
				lexemes[pos].l == "&" ||
				lexemes[pos].l == "&&" ||
				lexemes[pos].l == "||" ||
				false
			)
		)
	) {
		pos++;
	}

	if(pos == 0)
		pos++; // include the termination condition as its own component

	auto ret = lexemes[0 .. pos];
	lexemes = lexemes[pos .. $];

	return ret;
}

struct EnvironmentPair {
	string environmentVariableName;
	string assignedValue;

	string toString() {
		return environmentVariableName ~ "=" ~ assignedValue;
	}
}

string expandSingleArg(ShellContext context, ShellLexeme[] lexeme) {
	string s;
	foreach(lex; lexeme) {
		auto expansions = lex.toExpansions(context);
		if(expansions.length != 1)
			throw new Exception("only single argument allowed here");
		s ~= expansions[0];
	}
	return s;
}

/++
	Parses a set of lexemes into set of command objects.

	This function in pure in all but formal annotation; it does not interact with the outside world, except through the globber delegate you provide (which should not make any changes to the outside world!).
+/
ShellCommand[] parseShellCommand(ShellLexeme[] lexemes, ShellContext context, Globber globber) {
	ShellCommand[] ret;

	ShellCommand currentCommand;
	ShellCommand firstCommand;

	enum ParseState {
		lookingForVarAssignment,
		lookingForArg,
		lookingForStdinFilename,
		lookingForStdoutFilename,
		lookingForStderrFilename,
	}
	ParseState parseState = ParseState.lookingForVarAssignment;

	commandLoop: while(lexemes.length) {
		auto component = nextComponent(lexemes);
		if(component.length) {
			/+
				Command syntax in bash is basically:

				Zero or more `ENV=value` sets, separated by whitespace, followed by zero or more arg things.
				OR
				a shell builtin which does special things to the rest of the command, and may even require subsequent commands

				Argv[0] can be a shell built in which reads the rest of argv separately. It may even require subsequent commands!

				For some shell built in keywords, you should not actually do expansion:
					$ for $i in one two; do ls $i; done
					bash: `$i': not a valid identifier

				So there must be some kind of intermediate representation of possible expansions.


				BUT THIS IS MY SHELL I CAN DO WHAT I WANT!!!!!!!!!!!!

				shell the vars are ... not recursively expanded, it is just already expanded at assignment
			+/

			bool thisWasEnvironmentPair = false;
			EnvironmentPair environmentPair;
			bool thisWasRedirection = false;
			bool thisWasPipe = false;
			ShellLexeme[] arg;

			if(component.length == 0) {
				// nothing left, should never happen
				break;
			}
			if(component.length == 1) {
				if(component[0].quoteStyle == QuoteStyle.none && component[0].l == " ") {
					// just an arg separator
					continue;
				}
			}

			if(currentCommand is null)
				currentCommand = new ShellCommand();
			if(firstCommand is null)
				firstCommand = currentCommand;

			foreach(lexeme; component) {
				again:
				final switch(parseState) {
					case ParseState.lookingForVarAssignment:
						if(thisWasEnvironmentPair) {
							arg ~= lexeme;
						} else {
							// assume there is no var until we prove otherwise
							parseState = ParseState.lookingForArg;
							if(lexeme.quoteStyle == QuoteStyle.none) {
								foreach(idx, ch; lexeme.l) {
									if(ch == '=') {
										// actually found one!
										thisWasEnvironmentPair = true;
										environmentPair.environmentVariableName = lexeme.l[0 .. idx];
										arg ~= ShellLexeme(lexeme.l[idx + 1 .. $], QuoteStyle.none);
										parseState = ParseState.lookingForVarAssignment;
									}
								}
							}

							if(parseState == ParseState.lookingForArg)
								goto case;
						}
					break;
					case ParseState.lookingForArg:
						if(lexeme.quoteStyle == QuoteStyle.none) {
							if(lexeme.l == "<" || lexeme.l == ">" || lexeme.l == ">>" || lexeme.l == ">&")
								thisWasRedirection = true;
							if(lexeme.l == "|")
								thisWasPipe = true;
							if(lexeme.l == ";" || lexeme.l == ";;" || lexeme.l == "&" || lexeme.l == "&&" || lexeme.l == "||") {
								if(firstCommand) {
									firstCommand.terminatingToken = lexeme.l;
									ret ~= firstCommand;
								}
								firstCommand = null;
								currentCommand = null;
								continue commandLoop;
							}
						}
						arg ~= lexeme;
					break;
					case ParseState.lookingForStdinFilename:
					case ParseState.lookingForStdoutFilename:
					case ParseState.lookingForStderrFilename:
						if(lexeme.quoteStyle == QuoteStyle.none) {
							if(lexeme.l == "<" || lexeme.l == ">")
								throw new Exception("filename needed, not a redirection");
							if(lexeme.l == "|")
								throw new Exception("filename needed, not a pipe");
						}
						arg ~= lexeme;
					break;
				}
			}

			switch(parseState) {
				case ParseState.lookingForStdinFilename:
					currentCommand.stdin.filename = expandSingleArg(context, arg);
					parseState = ParseState.lookingForArg;
				continue;
				case ParseState.lookingForStdoutFilename:
					currentCommand.stdout.filename = expandSingleArg(context, arg);
					parseState = ParseState.lookingForArg;
				continue;
				case ParseState.lookingForStderrFilename:
					currentCommand.stderr.filename = expandSingleArg(context, arg);
					parseState = ParseState.lookingForArg;
				continue;
				default:
					break;
			}

			if(thisWasEnvironmentPair) {
				environmentPair.assignedValue = expandSingleArg(context, arg);
				currentCommand.environmentPairs ~= environmentPair;
			} else if(thisWasRedirection) {
				// FIXME: read the fd off this arg
				// FIXME: read the filename off the next arg, new parse state
				//assert(0, component);

				string cmd;
				foreach(item; component)
					cmd ~= item.l;

				switch(cmd) {
					case ">":
					case ">>":
						if(currentCommand.stdout.kind != ShellIo.Kind.inherit)
							throw new Exception("command has already been redirected");
						currentCommand.stdout.kind = ShellIo.Kind.filename;
						if(cmd == ">>")
							currentCommand.stdout.append = true;
						parseState = ParseState.lookingForStdoutFilename;
					break;
					case "2>":
					case "2>>":
						if(currentCommand.stderr.kind != ShellIo.Kind.inherit)
							throw new Exception("command has already had stderr redirected");
						currentCommand.stderr.kind = ShellIo.Kind.filename;
						if(cmd == "2>>")
							currentCommand.stderr.append = true;
						parseState = ParseState.lookingForStderrFilename;
					break;
					case "2>&1":
						if(currentCommand.stderr.kind != ShellIo.Kind.inherit)
							throw new Exception("command has already had stderr redirected");
						currentCommand.stderr.kind = ShellIo.Kind.fd;
						currentCommand.stderr.fd = 1;
					break;
					case "<":
						if(currentCommand.stdin.kind != ShellIo.Kind.inherit)
							throw new Exception("command has already had stdin assigned");
						currentCommand.stdin.kind = ShellIo.Kind.filename;
						parseState = ParseState.lookingForStdinFilename;
					break;
					default:
						throw new Exception("bad redirection try adding spaces around parts of " ~ cmd);
				}
			} else if(thisWasPipe) {
				// FIXME: read the fd? i kinda wanna support 2| and such
				auto newCommand = new ShellCommand();
				currentCommand.stdout.kind = ShellIo.Kind.pipedCommand;
				currentCommand.stdout.pipedCommand = newCommand;
				newCommand.stdin.kind = ShellIo.Kind.pipedCommand;
				newCommand.stdin.pipedCommand = currentCommand;

				currentCommand = newCommand;
			} else {
				currentCommand.argv ~= globber(arg, context);
			}
		}
	}

	if(firstCommand)
		ret ~= firstCommand;

	return ret;
}

unittest {
	string[] globber(ShellLexeme[] s, ShellContext context) {
		string g;
		foreach(l; s)
			g ~= l.toExpansions(context)[0];
		return [g];
	}
	ShellContext context;
	ShellCommand[] commands;

	commands = parseShellCommand(lexShellCommandLine("foo bar"), context, &globber);
	assert(commands.length == 1);
	assert(commands[0].argv.length == 2);
	assert(commands[0].argv[0] == "foo");
	assert(commands[0].argv[1] == "bar");

	commands = parseShellCommand(lexShellCommandLine("foo bar'baz'"), context, &globber);
	assert(commands.length == 1);
	assert(commands[0].argv.length == 2);
	assert(commands[0].argv[0] == "foo");
	assert(commands[0].argv[1] == "barbaz");

}

/+
interface OSInterface {
	setEnv
	getEnv
	getAllEnv

	runCommand
	waitForCommand
}
+/

version(Windows) {
	import core.sys.windows.windows;
	HANDLE duplicate(HANDLE handle) {
		HANDLE n;
		// FIXME: check for error
		DuplicateHandle(
			GetCurrentProcess(),
			handle,
			GetCurrentProcess(),
			&n,
			0,
			false,
			DUPLICATE_SAME_ACCESS
		);
		return n;
	}
}
version(Posix) {
	import unistd = core.sys.posix.unistd;
	alias HANDLE = int;
	int CloseHandle(HANDLE fd) {
		import core.sys.posix.unistd;
		return close(fd);
	}

	HANDLE duplicate(HANDLE fd) {
		import unix = core.sys.posix.unistd;
		auto n = unix.dup(fd);
		// FIXME: check for error
		setCloExec(n);
		return n;
	}
}

struct CommandRunningContext {
	// FIXME: environment?

	HANDLE stdin;
	HANDLE stdout;
	HANDLE stderr;

	int pgid;
}

class Shell {
	protected ShellContext context;

	bool exitRequested() {
		return context.exitRequested;
	}

	this() {
		setCommandExecutors([
			// providing for, set, export, cd, etc
			cast(Shell.CommandExecutor) new ShellControlExecutor(),
			// runs external programs
			cast(Shell.CommandExecutor) new ExternalCommandExecutor(),
			// runs built-in simplified versions of some common commands
			cast(Shell.CommandExecutor) new CoreutilFallbackExecutor()
		]);

		context.getEnvironmentVariable = toDelegate(&getEnvironmentVariable);
		context.getUserHome = toDelegate(&getUserHome);

		context.scriptArgs = ["one 1", "two 2", "three 3"];
	}

	static private string getUserHome(scope const(char)[] user) {
		if(user.length == 0) {
			import core.stdc.stdlib;
			version(Windows)
				return (stringz(getenv("HOMEDRIVE")).borrow ~ stringz(getenv("HOMEPATH")).borrow).idup;
			else
				return (stringz(getenv("HOME")).borrow).idup;
		}
		// FIXME: look it up from the OS
		return null;
	}


	public string prompt() {
		return "[deesh]" ~ getCurrentWorkingDirectory().toString() ~ "$ ";
	}

	/++
		Expands shell input with filename wildcards into a list of matching filenames or unmodified names in the shell's current context.
	+/
	protected string[] glob(ShellLexeme[] ls, ShellContext context) {
		if(ls.length == 0)
			return null;

		static struct Helper {
			string[] expansions;
			bool mayHaveSpecialCharInterpretation;
			Helper* next;
		}

		Helper[] expansions;
		expansions.length = ls.length;
		foreach(idx, ref expansion; expansions)
			expansion = Helper(ls[idx].toExpansions(context), ls[0].quoteStyle == QuoteStyle.none, idx + 1 < expansions.length ? &expansions[idx + 1] : null);

		string[] helper(Helper* h) {
			import arsd.string;
			string[] ret;
			foreach(exp; h.expansions) {
				if(h.next)
				foreach(next; helper(h.next))
					ret ~= (h.mayHaveSpecialCharInterpretation ? replace(exp, "*", "\xff") : exp) ~ next;
				else
					ret ~= h.mayHaveSpecialCharInterpretation ? replace(exp, "*", "\xff") : exp;
			}
			return ret;
		}

		string[] res = helper(&expansions[0]);

		string[] ret;
		foreach(ref r; res) {
			bool needsGlob;
			foreach(ch; r) {
				if(ch == 0xff) {
					needsGlob = true;
					break;
				}
			}

			if(needsGlob) {
				string[] matchingFiles;

				// FIXME: wrong dir if there's a slash in the pattern...
				getFiles(".", (string name, bool isDirectory) {
					if(name.length && name[0] == '.' && (r.length == 0 || r[0] != '.'))
						return; // skip hidden unless specifically requested
					if(name.matchesFilePattern(r, '\xff'))
						matchingFiles ~= name;

				});

				if(matchingFiles.length == 0) {
					import arsd.string;
					ret ~= r.replace("\xff", "*");
				} else {
					ret ~= matchingFiles;
				}
			} else {
				ret ~= r;
			}
		}

		return ret;
	}

	private final string[] globberForwarder(ShellLexeme[] ls, ShellContext context) {
		return glob(ls, context);
	}

	/++
		Sets the command runners for this shell. It will try each executor in the order given, running the first that can succeed. If none can, it will issue a command not found error.

		I suggest you try

		---
		setCommandExecutors([
			// providing for, set, export, cd, etc
			new ShellControlExecutor(),
			// runs external programs
			new ExternalCommandExecutor(),
			// runs built-in simplified versions of some common commands
			new CoreutilFallbackExecutor()
		]);
		---

		If you are writing your own executor, you should generally not match on any command that includes a slash, thus reserving those full paths for the external command executor.
	+/
	public void setCommandExecutors(CommandExecutor[] commandExecutors) {
		this.commandExecutors = commandExecutors;
	}

	private CommandExecutor[] commandExecutors;

	static interface CommandExecutor {
		/++
			Returns the condition if this executor will try to run the command.

			Tip: when implementing, if there is a slash in the argument, you should generally not attempt to match unless you are implementing an external command runner.

			Returns:
				[MatchesResult.no] if this executor never matches the given command.

				[MatchesResult.yes] if this executor always matches the given command. If it is unable to run it, including for cases like file not found or file not executable, this is an error and it will not attempt to fall back to the next executor.

				[MatchesResult.yesIfSearchSucceeds] means the shell should call [searchPathForCommand] before proceeding. If `searchPathForCommand` returns `FilePath(null)`, the shell will try the next executor. For any other return, it will try to run the command, storing the result in `command.exePath`.
		+/
		MatchesResult matches(string arg0);

		/// ditto
		enum MatchesResult {
			no,
			yes,
			yesIfSearchSucceeds
		}
		/++
			Returns the [FilePath] to be executed by the command, if there is one. Should be `FilePath(null)` if it does not match or does not use an external file.
		+/
		FilePath searchPathForCommand(string arg0);
		/++

		+/
		RunningCommand startCommand(ShellCommand command, CommandRunningContext crc);

		/++
		string[] completionCandidatesForCommandName(string arg0);
		string[] completionCandidatesForArgument(string[] args
		+/
	}

	void dumpCommand(ShellCommand command, bool includeNl = true) {
		foreach(ep; command.environmentPairs)
			writeln(ep.toString());

		writeStdout(command.argv);

		final switch(command.stdin.kind) {
			case ShellIo.Kind.inherit:
			case ShellIo.Kind.memoryBuffer:
			case ShellIo.Kind.pipedCommand:
			break;
			case ShellIo.Kind.fd:
				writeStdout(" <", command.stdin.fd);
			break;
			case ShellIo.kind.filename:
				writeStdout(" < ", command.stdin.filename);
		}
		final switch(command.stderr.kind) {
			case ShellIo.Kind.inherit:
			case ShellIo.Kind.memoryBuffer:
			break;
			case ShellIo.Kind.fd:
				writeStdout(" 2>&", command.stderr.fd);
			break;
			case ShellIo.kind.filename:
				writeStdout(command.stderr.append ? " 2>> " : " 2> ", command.stderr.filename);
			break;
			case ShellIo.Kind.pipedCommand:
				writeStderr(" 2| ");
				dumpCommand(command.stderr.pipedCommand, false);
			break;
		}
		final switch(command.stdout.kind) {
			case ShellIo.Kind.inherit:
			case ShellIo.Kind.memoryBuffer:
			break;
			case ShellIo.Kind.fd:
				writeStdout(" >&", command.stdout.fd);
			break;
			case ShellIo.kind.filename:
				writeStdout(command.stdout.append ? " >> " : " > ", command.stdout.filename);
			break;
			case ShellIo.Kind.pipedCommand:
				writeStdout(" | ");
				dumpCommand(command.stdout.pipedCommand, false);
			break;
		}

		writeStdout(command.terminatingToken);

		writeln();
	}

	static struct WaitResult {
		enum Change {
			stop,
			resume,
			complete
		}
		Change change;
		int status;
	}
	WaitResult waitForCommand(ShellCommand command) {
		//command.runningCommand.waitForChange();
		command.runningCommand.waitForChange();
		if(auto cmd = command.stdout.pipedCommand) {
			waitForCommand(cmd);
		}
		if(command.runningCommand.isComplete)
			return WaitResult(WaitResult.Change.complete, command.runningCommand.status);
		else if(command.runningCommand.isStopped)
			return WaitResult(WaitResult.Change.stop, command.runningCommand.status);
		else
			return WaitResult(WaitResult.Change.resume, command.runningCommand.status);
	}

	package RunningCommand startCommand(ShellCommand command, CommandRunningContext crc) {
		if(command.argv.length == 0)
			throw new Exception("empty command");

		CommandExecutor matchingExecutor;
		executorLoop: foreach(executor; commandExecutors) {
			final switch(executor.matches(command.argv[0])) {
				case CommandExecutor.MatchesResult.no:
					continue;
				case CommandExecutor.MatchesResult.yesIfSearchSucceeds:
					auto result = executor.searchPathForCommand(command.argv[0]);
					if(result.isNull())
						continue;
					command.exePath = result;
					goto case;
				case CommandExecutor.MatchesResult.yes:
					matchingExecutor = executor;
					break executorLoop;
			}
		}
		if(matchingExecutor is null)
			throw new Exception("command not found");

		command.shellContext = &context;

		HANDLE[2] pipes;
		File[3] redirections;

		// FIXME: if it is a memory buffer we want the pipe too, just we will read the other side of it

		final switch(command.stdin.kind) {
			case ShellIo.Kind.pipedCommand:
				// do nothing, set up from the pipe origin
			break;
			case ShellIo.Kind.inherit:
				// nothing here, will be set with stdout blow
			break;
			case ShellIo.kind.filename:
				redirections[0] = new File(FilePath(command.stdin.filename), File.OpenMode.readOnly);
				crc.stdin = redirections[0].nativeHandle;

				version(Windows)
				if(!SetHandleInformation(crc.stdin, 1/*HANDLE_FLAG_INHERIT*/, 1))
					throw new WindowsApiException("SetHandleInformation", GetLastError());
			break;
			case ShellIo.Kind.memoryBuffer:
				throw new NotYetImplementedException("stdin redirect from mem not implemented");
			break;
			case ShellIo.Kind.fd:
				throw new NotYetImplementedException("stdin redirect from fd not implemented");
			break;
		}

		final switch(command.stdout.kind) {
			case ShellIo.Kind.inherit:
				pipes[0] = crc.stdin;
				pipes[1] = crc.stdout;
			break;
			case ShellIo.Kind.memoryBuffer:
				throw new NotYetImplementedException("stdout redirect to mem not implemented");
			break;
			case ShellIo.Kind.fd:
				throw new NotYetImplementedException("stdout redirect to fd not implemented");
			break;
			case ShellIo.kind.filename:
				pipes[0] = crc.stdin;
				redirections[1] = new File(FilePath(command.stdout.filename), command.stdout.append ? File.OpenMode.appendOnly : File.OpenMode.writeWithTruncation);
				pipes[1] = redirections[1].nativeHandle;

				version(Windows)
				if(!SetHandleInformation(pipes[1], 1/*HANDLE_FLAG_INHERIT*/, 1))
					throw new WindowsApiException("SetHandleInformation", GetLastError());
			break;
			case ShellIo.Kind.pipedCommand:
				assert(command.stdout.pipedCommand);
				version(Posix) {
					import core.sys.posix.unistd;
					auto ret = pipe(pipes);

					setCloExec(pipes[0]);
					setCloExec(pipes[1]);

					import core.stdc.errno;

					if(ret == -1)
						throw new ErrnoApiException("stdin pipe", errno);
				} else version(Windows) {
					SECURITY_ATTRIBUTES saAttr;
					saAttr.nLength = SECURITY_ATTRIBUTES.sizeof;
					saAttr.bInheritHandle = true;
					saAttr.lpSecurityDescriptor = null;

					if(MyCreatePipeEx(&pipes[0], &pipes[1], &saAttr, 0, 0, 0 /* flags */) == 0)
						throw new WindowsApiException("CreatePipe", GetLastError());

					// don't inherit the read side for the first process
					if(!SetHandleInformation(pipes[0], 1/*HANDLE_FLAG_INHERIT*/, 0))
						throw new WindowsApiException("SetHandleInformation", GetLastError());
				}
			break;
		}

		auto original_stderr = crc.stderr;
		final switch(command.stderr.kind) {
			case ShellIo.Kind.pipedCommand:
				throw new NotYetImplementedException("stderr redirect to pipe not implemented");
			break;
			case ShellIo.Kind.inherit:
				// nothing here, just keep it
			break;
			case ShellIo.kind.filename:
				redirections[2] = new File(FilePath(command.stderr.filename), command.stderr.append ? File.OpenMode.appendOnly : File.OpenMode.writeWithTruncation);
				crc.stderr = redirections[2].nativeHandle;
			break;
			case ShellIo.Kind.memoryBuffer:
				throw new NotYetImplementedException("stderr redirect to mem not implemented");
			break;
			case ShellIo.Kind.fd:
				assert(command.stderr.fd == 1);
				crc.stderr = duplicate(pipes[1]);
				redirections[2] = new File(crc.stderr); // so we can close it easily later

				version(Windows)
				if(!SetHandleInformation(crc.stderr, 1/*HANDLE_FLAG_INHERIT*/, 1))
					throw new WindowsApiException("SetHandleInformation", GetLastError());
			break;
		}

		auto proc = matchingExecutor.startCommand(command, CommandRunningContext(crc.stdin, pipes[1], crc.stderr, crc.pgid));
		assert(command.runningCommand is proc);

		version(Windows) {
			// can't inherit stdin or modified stderr again beyond this
			if(redirections[0] && !SetHandleInformation(redirections[0].nativeHandle, 1/*HANDLE_FLAG_INHERIT*/, 0))
				throw new WindowsApiException("SetHandleInformation", GetLastError());
			if(redirections[2] && !SetHandleInformation(redirections[2].nativeHandle, 1/*HANDLE_FLAG_INHERIT*/, 0))
				throw new WindowsApiException("SetHandleInformation", GetLastError());
		}

		if(command.stdout.pipedCommand) {
			version(Windows) {
				// but swap inheriting for the second one
				if(!SetHandleInformation(pipes[0], 1/*HANDLE_FLAG_INHERIT*/, 1))
					throw new WindowsApiException("SetHandleInformation", GetLastError());
				if(!SetHandleInformation(pipes[1], 1/*HANDLE_FLAG_INHERIT*/, 0))
					throw new WindowsApiException("SetHandleInformation", GetLastError());
			}

			startCommand(command.stdout.pipedCommand, CommandRunningContext(pipes[0], crc.stdout, original_stderr, crc.pgid ? crc.pgid : proc.pid));

			// we're done with them now, important to close so the receiving program doesn't think more data might be coming down the pipe
			// but if we pass it to a built in command in a thread, it needs to remain... maybe best to duplicate the handle in that case.
			CloseHandle(pipes[0]); // FIXME: check for error?
			CloseHandle(pipes[1]);
		}

		foreach(ref r; redirections) {
			if(r)
				r.close();
			r = null;
		}

		return proc;
	}

	public int executeScript(string commandLine) {
		auto fiber = executeInteractiveCommand(commandLine);
		assert(fiber is null);
		return context.mostRecentCommandStatus;
	}

	public SchedulableTask executeInteractiveCommand(string commandLine) {
		SchedulableTask fiber;
		bool backgrounded;
		fiber = new SchedulableTask(() {

		ShellCommand[] commands;

		try {
			commands = parseShellCommand(lexShellCommandLine(commandLine), context, &globberForwarder);
		} catch(ArsdExceptionBase e) {
			string more;
			e.getAdditionalPrintableInformation((string name, in char[] value) {
				more ~= ", ";
				more ~= name ~ ": " ~ value;
			});
			writelnStderr("deesh: ", e.message, more);
		} catch(Exception e) {
			writelnStderr("deesh: ", e.msg);
		}

		bool aborted;
		bool skipToNextStatement;
		int errorLevel;

		commandLoop: foreach(command; commands)
		try {
			if(context.exitRequested)
				return;

			if(aborted) {
				writelnStderr("Execution aborted");
				break;
			}
			if(skipToNextStatement) {
				switch(command.terminatingToken) {
					case "", ";", "&":
						skipToNextStatement = false;
						if(errorLevel)
							aborted = true;
						continue commandLoop;
					case ";;":
						skipToNextStatement = false;
						continue commandLoop;
					default:
						assert(0);
				}
			}

			if(command.argv[0] in context.aliases) {
				command.argv = context.aliases[command.argv[0]] ~ command.argv[1 .. $];
			}

			debug dumpCommand(command);

			version(Posix) {
				auto crc = CommandRunningContext(0, 1, 2, 0);
			} else version(Windows) {
				auto crc = CommandRunningContext(GetStdHandle(STD_INPUT_HANDLE), GetStdHandle(STD_OUTPUT_HANDLE), GetStdHandle(STD_ERROR_HANDLE));
			}

			auto proc = this.startCommand(command, crc);

			if(command.terminatingToken == "&") {
				context.jobs ~= command;
				command.shellTask = fiber;
				backgrounded = true;
				Fiber.yield();
				goto waitMore;
			} else {
				waitMore:
				proc.makeForeground();
				auto waitResult = waitForCommand(command);
				final switch(waitResult.change) {
					case WaitResult.Change.complete:
						break;
					case WaitResult.Change.stop:
						command.shellTask = fiber;
						context.jobs ~= command;
						reassertControlOfTerminal();
						Fiber.yield();
						goto waitMore;
					case WaitResult.Change.resume:
						goto waitMore;
				}

				auto cmdStatus = waitResult.status;

				errorLevel = cmdStatus;
				context.mostRecentCommandStatus = cmdStatus;
				reassertControlOfTerminal();

				switch(command.terminatingToken) {
					case "", ";":
						// by default, throw if the command failed
						if(cmdStatus)
							aborted = true;
					break;
					case "||":
						// if this command succeeded, we skip the rest of this block to the next ;, ;;, or &
						// if it failed, we run the next command
						if(cmdStatus == 0)
							skipToNextStatement = true;
					break;
					case "&&":
						// opposite of ||, if this command *fails*, we proceed
						if(cmdStatus != 0)
							skipToNextStatement = true;
					break;
					case ";;": // on error resume next, let the script inspect
						aborted = false;
					break;
					case "&":
						// handled elsewhere
						break;
					default:
						throw new Exception("invalid command terminator: " ~ command.terminatingToken);
				}
			}

		} catch(ArsdExceptionBase e) {
			string more;
			e.getAdditionalPrintableInformation((string name, in char[] value) {
				more ~= ", ";
				more ~= name ~ ": " ~ value;
			});
			writelnStderr("deesh: ", command.argv.length ? command.argv[0] : "", ": ", e.message, more);
		} catch(Exception e) {
			writelnStderr("deesh: ", command.argv.length ? command.argv[0] : "", ": ", e.msg);
		}
		});

		fiber.call();

		if(fiber.state == Fiber.State.HOLD) {
			if(backgrounded) {
				// user typed &, they should know
			} else {
				writeStdout("Stopped");
			}
		}

		auto fg = context.jobToForeground;
		context.jobToForeground = null;
		return fg;
	}

	bool pendingJobs() {
		return context.jobs.length > 0;
	}

	void reassertControlOfTerminal() {
		version(Posix) {
			import core.sys.posix.unistd;
			import core.sys.posix.signal;

			// reassert control of the tty to the shell
			ErrnoEnforce!tcsetpgrp(1, getpid());
		}
	}
}

class RunningCommand {
	void waitForChange() {}
	int status() { return 0; }
	void makeForeground() {}

	int pid() { return 0; }

	abstract bool isComplete();
	bool isStopped() { return false; }
}

class ExternalProcessWrapper : RunningCommand {
	ExternalProcess proc;
	this(ExternalProcess proc) {
		this.proc = proc;
	}

	override void waitForChange() {
		this.proc.waitForChange();
	}

	override int status() {
		return this.proc.status;
	}

	override void makeForeground() {
		// FIXME: save/restore terminal state associated with shell and this process too
		version(Posix) {
			assert(proc.pid > 0);
			import core.sys.posix.unistd;
			import core.sys.posix.signal;
			// put the child group in control of the tty
			ErrnoEnforce!tcsetpgrp(1, proc.pid);
			// writeln(proc.pid);
			kill(-proc.pid, SIGCONT); // and if it beat us to the punch and is waiting, go ahead and wake it up (this is harmless if it is already running)
		}
	}

	override int pid() { version(Posix) return proc.pid; else return 0; }

	override bool isStopped() { return proc.isStopped; }
	override bool isComplete() { return proc.isComplete; }
}
class ExternalCommandExecutor : Shell.CommandExecutor {
	MatchesResult matches(string arg0) {
		if(arg0.indexOf("/") != -1)
			return MatchesResult.yes;
		return MatchesResult.yesIfSearchSucceeds;
	}
	FilePath searchPathForCommand(string arg0) {
		if(arg0.indexOf("/") != -1)
			return FilePath(arg0);
		// could also be built-ins and cmdlets...
		// and on Windows we should check .exe, maybe .com, .bat, .cmd but note these need to be called through cmd.exe as the process and do a -c arg so maybe i won't allow it.

		// so if .exe is not there i should add it.

		string exeName;
		version(Posix)
			exeName = arg0;
		else version(Windows) {
			exeName = arg0;
			if(exeName.length < 4 || (exeName[$ - 4 .. $] != ".exe" && exeName[$ - 4 .. $] != ".EXE"))
				exeName ~= ".exe";
		} else static assert(0);

		import arsd.string;
		version(Posix)
			auto searchPaths = getEnvironmentVariable("PATH").split(":");
		else version(Windows)
			auto searchPaths = getEnvironmentVariable("PATH").split(";");

		//version(Posix) immutable searchPaths = ["/usr/bin", "/bin", "/usr/local/bin", "/home/me/bin"]; // FIXME
		//version(Windows) immutable searchPaths = [`c:/windows`, `c:/windows/system32`, `./`]; // FIXME
		foreach(path; searchPaths) {
			auto t = FilePath(exeName).makeAbsolute(FilePath(path));

			version(Posix) {
				import core.sys.posix.sys.stat;
				stat_t sbuf;

				CharzBuffer buf = t.toString();
				auto ret = stat(buf.ptr, &sbuf);
				if(ret != -1)
					return t;
			} else version(Windows) {
				WCharzBuffer nameBuffer = t.toString();
				auto ret = GetFileAttributesW(nameBuffer.ptr);
				if(ret != INVALID_FILE_ATTRIBUTES)
					return t;
			}
		}
		return FilePath(null);
	}

	RunningCommand startCommand(ShellCommand command, CommandRunningContext crc) {

		auto fp = command.exePath;
		if(fp.isNull())
			fp = searchPathForCommand(command.argv[0]);

		if(fp.isNull()) {
			throw new Exception("Command not found");
		}

		version(Windows) {
			string windowsCommandLine;
			foreach(arg; command.argv) {
				// FIXME: this prolly won't be interpreted right on the other side
				if(windowsCommandLine.length)
					windowsCommandLine ~= " ";
				if(arg.indexOf(" ") != -1)
					windowsCommandLine ~= "\"" ~ arg ~ "\"";
				else
					windowsCommandLine ~= arg;
			}

			auto proc = new ExternalProcess(fp, windowsCommandLine);
		} else {
			auto proc = new ExternalProcess(fp, command.argv);
			proc.beforeExec = () {
				// reset ignored signals to default behavior
				import core.sys.posix.signal;
				signal (SIGINT, SIG_DFL);
				signal (SIGQUIT, SIG_DFL);
				signal (SIGTSTP, SIG_DFL);
				signal (SIGTTIN, SIG_DFL);
				signal (SIGTTOU, SIG_DFL);
				signal (SIGCHLD, SIG_DFL);

				//signal (SIGWINCH, SIG_DFL);
				signal (SIGHUP, SIG_DFL);
				signal (SIGCONT, SIG_DFL);
			};
			proc.pgid = crc.pgid; // 0 here means to lead the group, all subsequent pipe programs should inherit the leader
		}

		// and inherit the standard handles
		proc.overrideStdin = crc.stdin;
		proc.overrideStdout = crc.stdout;
		proc.overrideStderr = crc.stderr;

		string[string] envOverride;
		foreach(ep; command.environmentPairs)
			envOverride[ep.environmentVariableName] = ep.assignedValue;

		if(command.environmentPairs.length)
			proc.setEnvironmentWithModifications(envOverride);

		command.runningCommand = new ExternalProcessWrapper(proc);
		proc.start;

		return command.runningCommand;
	}
}

class ImmediateCommandWrapper : RunningCommand {
	override void waitForChange() {
		// it is already complete
	}

	override int status() {
		return status_;
	}

	override void makeForeground() {
		// do nothing, immediate commands complete too fast anyway but are also part of the shell
	}

	private int status_;
	this(int status) {
		this.status_ = status;
	}

	override bool isStopped() { return false; }
	override bool isComplete() { return true; }
}

class ShellControlExecutor : Shell.CommandExecutor {
	static struct ShellControlContext {
		ShellContext* context;
		string[] args;

		HANDLE stdin;
		HANDLE stdout;
		HANDLE stderr;
	}
	__gshared int function(ShellControlContext scc)[string] runners;
	shared static this() {
		runners = [
			"cd": (scc) {
				version(Windows) {
					WCharzBuffer bfr = scc.args.length > 1 ? scc.args[1] : Shell.getUserHome(null);
					if(!SetCurrentDirectory(bfr.ptr))
						// FIXME print the info
						return GetLastError();
					return 0;
				} else {
					import core.sys.posix.unistd;
					import core.stdc.errno;
					CharzBuffer bfr = scc.args.length > 1 ? scc.args[1] : Shell.getUserHome(null);
					if(chdir(bfr.ptr) == -1)
						// FIXME print the info
						return errno;
					return 0;
				}
			},
			"true": (scc) => 0,
			"false": (scc) => 1,
			"alias": (scc) {
				if(scc.args.length <= 1) {
					// FIXME: print all aliases
					return 0;
				} else if(scc.args.length == 2) {
					// FIXME: print the content of aliases[scc.args[1]]
					return 0;
				} else if(scc.args.length >= 3) {
					scc.context.aliases[scc.args[1]] = scc.args[2..$];
					return 0;
				} else {
					// FIXME: print error
					return 1;
				}
			},
			"unalias": (scc) {
				scc.context.aliases.remove(scc.args[1]);
				return 0;
			},
			"shift": (scc) {
				auto n = 1;
				// FIXME: error check and get n off the args if present
				scc.context.scriptArgs = scc.context.scriptArgs[n .. $];
				return 0;
			},
			/++ Assigns a variable to the shell environment for use in this execution context, but that will not be passed to child process' environment. +/
			"let": (scc) {
				scc.context.vars[scc.args[1]] = scc.args[2];
				return 0;
			},
			"exit": (scc) {
				scc.context.exitRequested = true;
				return 0;
			},
			// "pushd" / "popd" / "dirs"
			// "time" - needs the process handle to get more info
			// "which"
			// "set"
			// "export"
			// "source" -- run a script in the current environment
			// "builtin" / "execute" ?
			// "history"
			// "help"
			"jobs": (scc) {
				// FIXME: show the job status (running, done, etc)
				foreach(idx, job; scc.context.jobs)
					writeln(idx, " ", job.argv);
				return 0;
			},
			"fg": (scc) {
				auto task = scc.context.jobs[0].shellTask;
				if(task.state == Fiber.State.HOLD) {
					scc.context.jobToForeground = task;
				} else {
					writeln("Task completed");
					scc.context.jobs = scc.context.jobs[1 .. $];
				}
				return 0;
			},
			"bg": (scc) {
				version(Posix) {
					import core.sys.posix.signal;
					auto pid = scc.context.jobs[0].runningCommand.pid();
					return kill(-pid, SIGCONT);
				}
				return -1; // not implemented on Windows since processes don't stop there anyway
			},
			"wait": (scc) {
				// FIXME: can wait for specific job
				foreach(job; scc.context.jobs) {
					if(job.runningCommand.isStopped) {
						writeln("A job is stopped, waiting would never end. Restart it first with `bg`");
						return 1;
					}
				}
				foreach(job; scc.context.jobs) {
					while(!job.runningCommand.isComplete)
						job.runningCommand.waitForChange();
				}
				scc.context.jobs = null;

				return 0;
			},
			// "for" / "do" / "done" - i kinda prefer not having do but bash requires it so ... idk. maybe "break" and "continue" too.
			// "if" ?
			// "ulimit"
			// "umask" ?
			//
			// "prompt" ?

			// "start" ? on Windows especially to shell execute.

		];
	}


	MatchesResult matches(string arg0) {
		return (arg0 in runners) ? MatchesResult.yes : MatchesResult.no;
	}
	FilePath searchPathForCommand(string arg0) {
		return FilePath(null);
	}
	RunningCommand startCommand(ShellCommand command, CommandRunningContext crc) {
		assert(command.shellContext !is null);

		int ret = 1;

		try {
			ret = runners[command.argv[0]](ShellControlContext(command.shellContext, command.argv, crc.stdin, crc.stdout, crc.stderr));
		} catch(Exception e) {
			// FIXME
		}

		command.runningCommand = new ImmediateCommandWrapper(ret);
		return command.runningCommand;
	}
}


class InternalCommandWrapper : RunningCommand {
	import core.thread;
	Thread thread;
	this(Thread thread) {
		this.thread = thread;
	}

	override void waitForChange() {
		auto t = thread.join();
		if(t is null)
			status_ = 0;
		else
			status_ = 1;
	}

	private int status_ = -1;

	override int status() {
		return status_;
	}

	override void makeForeground() {
		// do nothing, built ins share terminal with the shell (maybe)
	}

	override bool isStopped() { return false; }
	override bool isComplete() { return status_ != -1; }
}

class CoreutilFallbackExecutor : Shell.CommandExecutor {
	static class Commands {
		private {
			CommandRunningContext crc;
			version(Posix)
				import core.stdc.errno;

			void writeln(scope const(char)[] msg) {
				msg ~= "\n";
				version(Posix) {
					import unix = core.sys.posix.unistd;
					import core.stdc.errno;
					auto ret = unix.write(crc.stdout, msg.ptr, msg.length);
					if(ret < 0)
						throw new ErrnoApiException("write", errno);
				}
				version(Windows) {
					// FIXME: if it is a console we should convert to wchars and use WriteConsole
					DWORD ret;
					if(!WriteFile(crc.stdout, msg.ptr, cast(int) msg.length, &ret, null))
						throw new WindowsApiException("WriteFile", GetLastError());
				}
				if(ret != msg.length)
					throw new Exception("write failed to do all"); // FIXME
			}

			void foreachLine(HANDLE file, void delegate(scope const(char)[]) dg) {
				char[] buffer = new char[](1024 * 32 - 512);
				bool eof;
				char[] leftover;

				getMore:

				version(Posix) {
					import unix = core.sys.posix.unistd;
					import core.stdc.errno;
					auto ret = unix.read(file, buffer.ptr, buffer.length);
					if(ret < 0)
						throw new ErrnoApiException("read", errno);
				}
				version(Windows) {
					DWORD ret;
					if(!ReadFile(file, buffer.ptr, cast(int) buffer.length, &ret, null)) {
						auto error = GetLastError();
						if(error == ERROR_BROKEN_PIPE)
							eof = true;
						else
							throw new WindowsApiException("ReadFile", error);
					}
				}

				if(ret == 0)
					eof = true;

				auto used = leftover;
				if(used.length && ret > 0)
					used ~= buffer[0 .. ret];
				else
					used = buffer[0 .. ret];

				moreInBuffer:
				auto eol = used.indexOf("\n");
				if(eol != -1) {
					auto line = used[0 .. eol + 1];
					used = used[eol + 1 .. $];
					dg(line);
					goto moreInBuffer;
				} else if(eof) {
					dg(used);
					return;
				} else {
					leftover = used;
					goto getMore;
				}
			}

			package this(CommandRunningContext crc) {
				this.crc = crc;
			}
		}

		public:

		int find(string[] dirs) {
			void delegate(string, bool) makeHandler(string dir) {
				void handler(string name, bool isDirectory) {
					if(name == "." || name == "..")
						return;
					auto fullName = dir;
					if(fullName.length >0 && fullName[$-1] != '/')
						fullName ~= "/";
					fullName ~= name;
					if(isDirectory)
						getFiles(fullName, makeHandler(fullName));
					else
						writeln(fullName);
				}
				return &handler;
			}

			foreach(dir; dirs)
				getFiles(dir, makeHandler(dir));
			if(dirs.length == 0)
				getFiles(".", makeHandler("."));

			return 0;
		}

		// FIXME: need -i and maybe -R at least
		int grep(string[] args) {
			if(args.length) {
				auto find = args[0];
				auto files = args[1 .. $];
				foreachLine(crc.stdin, (line) {
					import arsd.string;
					if(line.indexOf(find) != -1)
						writeln(line.stripRight);
				});
				return 0;
			} else {
				return 1;
			}
		}

		int echo(string[] args) {
			import arsd.string;
			writeln(args.join(" "));
			return 0;
		}

		// FIXME: -R, -l, -h all useful to me. also --sort is nice. maybe --color
		int ls(bool a, string[] args) {
			void handler(string name, bool isDirectory) {
				if(!a && name.length && name[0] == '.')
					return;
				writeln(name);
			}
			foreach(arg; args)
				getFiles(arg, &handler);
			if(args.length == 0)
				getFiles(".", &handler);
			return 0;
		}

		void pwd() {
			writeln(getCurrentWorkingDirectory().toString);
		}

		void rm(bool R, string[] files) {
			if(R)
				throw new Exception("rm -R not implemented");
			foreach(file; files) {
				version(Windows) {
					WCharzBuffer bfr = file;
					if(!DeleteFileW(bfr.ptr))
						throw new WindowsApiException("DeleteFileW", GetLastError());
				} else version(Posix) {
					CharzBuffer bfr = file;
					if(unistd.unlink(bfr.ptr) == -1)
						throw new ErrnoApiException("unlink", errno);
				}
			}
		}

		void touch(string[] files) {
			foreach(file; files) {
				auto fo = new File(FilePath(file));
				fo.close();
			}
		}

		void uniq() {
			const(char)[] previousLine;
			import arsd.string;
			foreachLine(crc.stdin, (line) {
				line = line.stripRight;
				if(line == previousLine)
					return;
				previousLine = line.dup; // dup since the foreach might reuse the buffer
				writeln(line);
			});
		}

		// FIXME: only prints utc, should do local time by default
		void date() {
			writeln(SimplifiedUtcTimestamp.now.toString);
		}

		void cat(string[] files) {
			void handler(HANDLE handle) {
				// FIXME actually imprecise af here and inefficient as the lines don't matter
				foreachLine(handle, (line) {
					import arsd.string;
					writeln(line.stripRight);
				});
			}

			foreach(file; files) {
				auto fo = new File(FilePath(file));
				handler(fo.nativeHandle);
				fo.close();
			}
			if(files.length == 0) {
				handler(crc.stdin);
			}
		}

		// could do -p which removes parents too
		void rmdir(string[] dirs) {
			foreach(dir; dirs) {
				version(Windows) {
					WCharzBuffer bfr = dir;
					if(!RemoveDirectoryW(bfr.ptr))
						throw new WindowsApiException("DeleteDirectoryW", GetLastError());
				} else version(Posix) {
					CharzBuffer bfr = dir;
					if(unistd.rmdir(bfr.ptr) == -1)
						throw new ErrnoApiException("rmdir", errno);
				}
			}
		}

		// -p is kinda useful
		void mkdir(string[] dirs) {
			foreach(dir; dirs) {
				version(Windows) {
					WCharzBuffer bfr = dir;
					if(!CreateDirectoryW(bfr.ptr, null))
						throw new WindowsApiException("CreateDirectoryW", GetLastError());
				} else version(Posix) {
					import unix = core.sys.posix.sys.stat;
					CharzBuffer bfr = dir;
					if(unix.mkdir(bfr.ptr, 0x1ff /* 0o777 */) == -1)
						throw new ErrnoApiException("mkdir", errno);
				}
			}
		}

		// maybe just take off the extension, whatever it is
		int basename(string[] args) {
			if(args.length < 1 || args.length > 2) {
				// FIXME use stderr
				writeln("bad arg count");
				return 1;
			}
			auto path = FilePath(args[0]);
			auto fn = path.filename;
			if(args.length > 1) {
				auto tocut = args[1];
				if(fn.length > tocut.length && fn[$ - tocut.length .. $] == tocut)
					fn = fn[0 .. $ - tocut.length];
			}
			writeln(fn);
			return 0;
		}
	}

	/+
		gonna want some kind of:
			mv
				rename(2)
				MoveFileW
			cp
				copy_file_range introduced linux 2016.
				CopyFileW
			sort

			nc
			xsel

			du ?

			env ?

			no chmod, ln, or unlink because Windows doesn't do them anyway...
	+/
	MatchesResult matches(string arg0) {
		switch(arg0) {
			foreach(memberName; __traits(derivedMembers, Commands))
				static if(__traits(getProtection, __traits(getMember, Commands, memberName)) == "public")
					case memberName:
						return MatchesResult.yes;
			default:
				return MatchesResult.no;
		}
	}
	FilePath searchPathForCommand(string arg0) {
		return FilePath(null);
	}
	RunningCommand startCommand(ShellCommand command, CommandRunningContext crc) {
		// basically using a thread as a fake process

		auto stdin = duplicate(crc.stdin);
		auto stdout = duplicate(crc.stdout);
		auto stderr = duplicate(crc.stderr);
		import core.thread;
		void runner() {
			scope(exit) {
				CloseHandle(stdin);
				CloseHandle(stdout);
				CloseHandle(stderr);
			}

			import arsd.cli;
			// FIXME: forward status through
			runCli!Commands(["builtin"] ~ command.argv, CommandRunningContext(stdin, stdout, stderr));
		}

		auto thread = new Thread(&runner);
		thread.start();
		command.runningCommand = new InternalCommandWrapper(thread);
		return command.runningCommand;
	}

}

// builtin commands should just be run in a helper thread so they can be as close to the original as reasonable
class BuiltinShellCommand {
	abstract int run(string[] args, AsyncAnonymousPipe stdin, AsyncAnonymousPipe stdout, AsyncAnonymousPipe stderr);
}

/++
	Constructs an instance of [arsd.terminal.LineGetter] appropriate for use in a repl for this shell.
+/
auto constructLineGetter()() {
	return null;
}

/++
	Sets up signal handling and progress groups to become an interactive shell.
+/
void enableInteractiveShell() {
	version(Posix) {
		// copy/pasted this from the bash manual
		import core.sys.posix.unistd;
		import core.sys.posix.signal;
		/* Loop until we are in the foreground.  */
		int shell_pgid;
		while (tcgetpgrp (0) != (shell_pgid = getpgrp ()))
			kill (- shell_pgid, SIGTTIN);

		/* Ignore interactive and job-control signals.  */
		signal (SIGINT, SIG_IGN); // ctrl+c
		signal (SIGQUIT, SIG_IGN); // ctrl+\
		signal (SIGTSTP, SIG_IGN); // ctrl+z. should stop the foreground process. send CONT to continue it. shell can do waitpid on it to get flags if it is suspended.
		signal (SIGTTIN, SIG_IGN);
		signal (SIGTTOU, SIG_IGN);
		signal (SIGCHLD, SIG_IGN); // arsd.core takes care of this

		/* Put ourselves in our own process group.  */
		shell_pgid = getpid ();
		if (setpgid (shell_pgid, shell_pgid) < 0)
		{
			throw new Exception ("Couldn't put the shell in its own process group");
		}

		/* Grab control of the terminal.  */
		tcsetpgrp (0, shell_pgid);

		/* Save default terminal attributes for shell.  */
		//tcgetattr (0, &shell_tmodes);
	}
}

/+
	Parts of bash I like:

		glob expansion
		! command recall
		redirection
		f{1..3} expand to f1 f2 f3. can add ..incr btw
		f{a,b,c} expand to fa fb fc
		for i in *; do cmd; done
		`command expansion`. also $( cmd ) is a thing
		~ expansion

		foo && bar
		foo || bar

		$(( maybe arithmetic but idk ))

		ENV=whatever cmd.
		$ENV ...?

		tab complete!

	PATH lookup. if requested.

	Globbing could insert -- before if there's any - in there.

	Or better yet all the commands must either start with ./
	or be found internally. Internal can be expanded by definition
	files that tell how to expand the real thing.

		* flags
		* arguments
		* command line
		* i/o
+/
