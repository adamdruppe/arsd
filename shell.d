/++
	Support functions to build a custom unix-style shell.


	$(PITFALL
		Do NOT use this to try to sanitize, escape, or otherwise parse what another shell would do with a string! Every shell is different and this implements my rules which may differ in subtle ways from any other common shell.

		If you want to use this to understand a command, also use it to execute that command so you get what you expect.
	)

	History:
		Added October 18, 2025

	Bugs:
	$(LIST
		* < and > redirections are not implemented at all
		* >> not implemented
		* | on Windows is not implemented
		* glob expansion is minimal - * works, but no ?, no {item,other}, no {start..end}
		* ~ expansion is not implemented
		* `substitution` and $(...) is not implemented
		* variable expansion is not implemented. can do $IDENT and ${IDENT} i think
		* built-ins don't exist - `set`, want `for` and then like `export` and a way to hook in basic utilities polyfills especially on Windows (ls, rm, grep, etc)
			* built-ins should have a pipe they can read/write to and return an int. integrate with arsd.cli?
		* no !history recall. or history command in general
		* job control is rudimentary - no fg, bg, jobs, &, ctrl+z, etc.
		* set -o ignoreeof
		* the path search is hardcoded
		* prompt could be cooler
			PS1 = normal prompt
			PS2 = continuation prompt
			Bash shell executes the content of the PROMPT_COMMAND just before displaying the PS1 variable.

			bash does it with `\u` and stuff but i kinda thiink using `$USER` and such might make more sense.
		* it prints command return values when you might not want that
		* LS_COLORS env var is not set
		* && and || is not implemented
		* the api is not very good
		* ulimit? sourcing things too. aliases.
		* see my bash rc for other little things. maybe i want a deeshrc
		* permission denied when hitting tab on Windows
		* tab complete of available commands not implemented - get it from path search.
		* some vars dynamic like $_ being the most recent command, $? being its return value, etc
	)

	Questionable_ideas:
	$(LIST
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

/++
	Holds some context needed for shell expansions.
+/
struct ShellContext {
	string[string] vars;
	string cwd;
	string[string] userHomes;
}

enum QuoteStyle {
	none,
	nonExpanding, // 'thing'
	expanding, // "thing"
	subcommand, // `thing`
}

/++

+/
alias Globber = string[] delegate(string str, ShellContext context);

/++
	Represents one component of a shell command line as a precursor to parsing.
+/
struct ShellLexeme {
	string l;
	QuoteStyle quoteStyle;

	string toEscapedFormat() {
		if(quoteStyle == QuoteStyle.nonExpanding) {
			string ret;
			ret.reserve(l.length);
			foreach(ch; l) {
				if(ch == '*')
					ret ~= "\\*";
				else
					ret ~= ch;
			}

			return ret;
		} else {
			return l;
		}
	}
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
					case ' ':
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
					case '|', '<', '>', '&':
						if(first != idx)
							ret ~= ShellLexeme(commandLine[first .. idx]);
						ret ~= ShellLexeme(commandLine[idx .. idx + 1]); // shell special symbol
						endWord();
						continue;
					default:
						// keep searching
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
		if(state != State.readingWord && state != State.readingComment)
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
}

class ShellCommand {
	ShellIo stdin;
	ShellIo stdout;
	ShellIo stderr;
	// yes i know in unix you can do other fds too. do i care?

	private ExternalProcess externalProcess;

	string exePath;
	string cwd;
	string[] argv;
	EnvironmentPair[] environmentPairs;

	/++
		The return value may be null! Some things can be executed without external processes.

		This function is absolutely NOT pure. It may modify your shell context, run external processes, and generally carry out operations outside the shell.
	+/
	ExternalProcess execute(ref ShellContext context) {
		return null;
	}
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
				lexemes[pos].l == "\n"
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

string expandSingleArg(string escapedArg, ShellContext context) {
	return escapedArg;
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
	}
	ParseState parseState = ParseState.lookingForVarAssignment;

	while(lexemes.length) {
		auto component = nextComponent(lexemes);
		if(component.length) {
			if(currentCommand is null)
				currentCommand = new ShellCommand();
			if(firstCommand is null)
				firstCommand = currentCommand;

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
			+/

			bool thisWasEnvironmentPair = false;
			EnvironmentPair environmentPair;
			bool thisWasRedirection = false;
			bool thisWasPipe = false;
			string arg;

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

			foreach(lexeme; component) {
				again:
				final switch(parseState) {
					case ParseState.lookingForVarAssignment:
						if(thisWasEnvironmentPair) {
							environmentPair.assignedValue ~= lexeme.toEscapedFormat();
						} else {
							// assume there is no var until we prove otherwise
							parseState = ParseState.lookingForArg;
							if(lexeme.quoteStyle == QuoteStyle.none) {
								foreach(idx, ch; lexeme.l) {
									if(ch == '=') {
										// actually found one!
										thisWasEnvironmentPair = true;
										environmentPair.environmentVariableName = lexeme.l[0 .. idx];
										environmentPair.assignedValue = lexeme.l[idx + 1 .. $];
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
							if(lexeme.l == "<" || lexeme.l == ">")
								thisWasRedirection = true;
							if(lexeme.l == "|")
								thisWasPipe = true;
						}
						arg ~= lexeme.toEscapedFormat();
					break;
				}
			}

			if(thisWasEnvironmentPair) {
				environmentPair.assignedValue = expandSingleArg(environmentPair.assignedValue, context);
				currentCommand.environmentPairs ~= environmentPair;
			} else if(thisWasRedirection) {
				// FIXME: read the fd off this arg
				// FIXME: read the filename off the next arg, new parse state
				assert(0);
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
	string[] globber(string s, ShellContext context) {
		return [s];
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

class Shell {
	protected ShellContext context;

	this() {
		context.cwd = getCurrentWorkingDirectory().toString;
		prompt = "[deesh]" ~ context.cwd ~ "$ ";
	}

	public string prompt;

	protected string[] glob(string s) {
		string[] ret;
		getFiles(context.cwd, (string name, bool isDirectory) {
			if(name.length && name[0] == '.' && (s.length == 0 || s[0] != '.'))
				return; // skip hidden unless specifically requested
			if(name.matchesFilePattern(s))
				ret ~= name;
		});
		if(ret.length == 0)
			return [s];
		else
			return ret;
	}

	private final string[] globberForwarder(string s, ShellContext context) {
		return glob(s);
	}

	void dumpCommand(ShellCommand command) {
		foreach(ep; command.environmentPairs)
			writeln(ep.toString());
		writeln(command.argv);
		if(command.stdout.kind == ShellIo.Kind.pipedCommand) {
			writeln(" | ");
			dumpCommand(command.stdout.pipedCommand);
		}
	}

	FilePath searchPathForCommand(string arg0) {
		if(arg0.indexOf("/") != -1)
			return FilePath(arg0);
		// could also be built-ins and cmdlets...
		// and on Windows we should check .exe, .com, .bat, or ask the OS maybe

		version(Posix) { // FIXME
		immutable searchPaths = ["/usr/bin", "/bin", "/usr/local/bin", "/home/me/bin"]; // FIXME
		foreach(path; searchPaths) {
			auto t = FilePath(arg0).makeAbsolute(FilePath(path));
			import core.sys.posix.sys.stat;
			stat_t sbuf;

			CharzBuffer buf = t.toString();
			auto ret = stat(buf.ptr, &sbuf);
			if(ret != -1)
				return t;
		}
		}
		return FilePath(null);
	}

	version(Windows)
	private ExternalProcess startCommand(ShellCommand command, int inheritedPipe, int pgid) {
		string windowsCommandLine;
		foreach(arg; command.argv) {
			if(windowsCommandLine.length)
				windowsCommandLine ~= " ";
			windowsCommandLine ~= arg;
		}

		auto fp = searchPathForCommand(command.argv[0]);

		auto proc = new ExternalProcess(fp, windowsCommandLine);
		command.externalProcess = proc;
		proc.start;
		return proc;
	}

	version(Posix)
	private ExternalProcess startCommand(ShellCommand command, int inheritedPipe, int pgid) {
		auto fp = searchPathForCommand(command.argv[0]);
		if(fp.isNull()) {
			throw new Exception("Command not found");
		}

		import core.sys.posix.unistd;

		int[2] pipes;
		if(command.stdout.pipedCommand) {
			auto ret = pipe(pipes);

			setCloExec(pipes[0]);
			setCloExec(pipes[1]);

			import core.stdc.errno;

			if(ret == -1)
				throw new ErrnoApiException("stdin pipe", errno);
		} else {
			pipes[0] = inheritedPipe;
			pipes[1] = 1;
		}

		auto proc = new ExternalProcess(fp, command.argv);
		if(command.stdout.pipedCommand) {
			proc.beforeExec = () {
				// reset ignored signals to default behavior
				import core.sys.posix.signal;
				signal (SIGINT, SIG_DFL);
				signal (SIGQUIT, SIG_DFL);
				signal (SIGTSTP, SIG_DFL);
				signal (SIGTTIN, SIG_DFL);
				signal (SIGTTOU, SIG_DFL);
				signal (SIGCHLD, SIG_DFL);
			};
		}
		proc.pgid = pgid; // 0 here means to lead the group, all subsequent pipe programs should inherit the leader
		// and inherit the standard handles
		proc.overrideStdinFd = inheritedPipe;
		proc.overrideStdoutFd = pipes[1];
		proc.overrideStderrFd = 2;
		command.externalProcess = proc;
		proc.start;

		if(command.stdout.pipedCommand) {
			startCommand(command.stdout.pipedCommand, pipes[0], pgid ? pgid : proc.pid);

			// we're done with them now
			close(pipes[0]);
			close(pipes[1]);
			pipes[] = -1;
		}

		return proc;
	}

	int waitForCommand(ShellCommand command) {
		command.externalProcess.waitForCompletion();
		writeln(command.externalProcess.status);
		if(auto cmd = command.stdout.pipedCommand)
			waitForCommand(cmd);
		return command.externalProcess.status;
	}

	public void execute(string commandLine) {
		auto commands = parseShellCommand(lexShellCommandLine(commandLine), context, &globberForwarder);
		foreach(command; commands)
		try {
			dumpCommand(command);

			version(Posix) {
				import core.sys.posix.unistd;
				import core.sys.posix.signal;

				auto proc = startCommand(command, 0, 0);

				// put the child group in control of the tty
				ErrnoEnforce!tcsetpgrp(1, proc.pid);
				kill(-proc.pid, SIGCONT); // and if it beat us to the punch and is waiting, go ahead and wake it up (this is harmless if it is already running
				waitForCommand(command);
				// reassert control of the tty to the shell
				ErrnoEnforce!tcsetpgrp(1, getpid());
			}

			version(Windows) {
				auto proc = startCommand(command, 0, 0);
				waitForCommand(command);
			}
		} catch(ArsdExceptionBase e) {
			string more;
			e.getAdditionalPrintableInformation((string name, in char[] value) {
				more ~= ", ";
				more ~= name ~ ": " ~ value;
			});
			writeln("deesh: ", command.argv.length ? command.argv[0] : "", ": ", e.message, more);
		} catch(Exception e) {
			writeln("deesh: ", command.argv.length ? command.argv[0] : "", ": ", e.msg);
		}
	}
}

/++
	Constructs an instance of [arsd.terminal.LineGetter] appropriate for use in a repl for this shell.
+/
auto constructLineGetter()() {
	return null;
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
