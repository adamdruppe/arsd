/++
	Facilities for working with external processes.

	See_Also:
		[arsd.shell], [std.process]
	History:
		Added October 19, 2026
+/
module arsd.process;

import arsd.core;

string argvToConventionalWindowsCommandLine(string[] argv) {
	string cmdLine;
	foreach(idx, arg; argv) {
		if(idx)
			cmdLine ~= " ";

		if(argv.length == 0) {
			cmdLine ~= `""`;
			continue;
		}

		bool needsEscape;
		foreach(ch; arg) {
			if(ch == '"' || ch == ' ' || ch == '\t') {
				needsEscape = true;
				break;
			}
		}

		if(needsEscape) {
			cmdLine ~= '"';
			foreach(chIdx, ch; arg) {
				if(ch == '\\') {
					// FIXME: would prolly be better to do this in reverse just like Phobos...
					bool followedByQuote = true;
					foreach(following; arg[chIdx + 1 .. $]) {
						if(following == '\\')
							continue;
						if(following != '"')
							followedByQuote = false;
						break;
					}
					if(followedByQuote)
						cmdLine ~= "\\";
				} else if(ch == '"')
					cmdLine ~= "\\";
				cmdLine ~= ch;
			}
			cmdLine ~= '"';
		} else {
			cmdLine ~= arg;
		}
	}
	return cmdLine;
}
unittest {
	/+
	import std.process;
	assert(escapeWindowsArgument(`c:\program files\"`) == `"c:\program files\\\""`);
	assert(escapeWindowsArgument(`c:\program files\`) == `"c:\program files\\"`);
	+/

	assert(argvToConventionalWindowsCommandLine(["foo", "bar"]) == "foo bar");
	assert(argvToConventionalWindowsCommandLine([`c:\foo`, "bar"]) == "c:\\foo bar");
	assert(argvToConventionalWindowsCommandLine([`c:\program files\`, "bar"]) == `"c:\program files\\" bar`);
	assert(argvToConventionalWindowsCommandLine([`c:\program files\"`, "bar"]) == `"c:\program files\\\"" bar`);
}

version(Windows) {
	struct RawCommandLine {
		string commandLine;
		alias commandLine this;
	}

	alias NativeProcessArguments = RawCommandLine;

	NativeProcessArguments toNativeProcessArguments(string cmdLine) {
		return RawCommandLine(cmdLine);
	}

	RawCommandLine toNativeProcessArguments(string[] argv) {
		return RawCommandLine(argvToConventionalWindowsCommandLine(argv));
	}
} else {
	alias NativeProcessArguments = string[];

	NativeProcessArguments toNativeProcessArguments(string cmdLine) {
		// i could do it with arsd.shell tbh
		assert(0, "not implemented");
	}

	NativeProcessArguments toNativeProcessArguments(string[] argv) {
		return argv;
	}
}

/++

+/
struct ExecuteResult {
	ubyte[] stdout;
	ubyte[] stderr;
	int status;
}

/++
+/
class ExecuteFuture : Future!ExecuteResult {
	private ExternalProcess process;

	private ubyte[] stdout;
	private ubyte[] stderr;

	private ubyte[] stdoutBuffer;
	private ubyte[] stderrBuffer;

	private void delegate(in ubyte[]) onStdoutReceived;
	private void delegate(in ubyte[]) onStderrReceived;

	private AsyncReadRequest stdoutRead;
	private void readMoreStdout() {
		stdoutRead = process.stdout.read(stdoutBuffer);
		stdoutRead.oncomplete = &readDone;
		stdoutRead.start();
	}
	private void readDone(AsyncReadRequest request) {
		auto result = request.waitForCompletion();
		if(result.wasSuccessful && result.bufferRead.length > 0) {
			if(request is stdoutRead) {
				onStdoutReceived(result.bufferRead[]);
				request.repeat(stdoutBuffer);
			} else {
				onStderrReceived(result.bufferRead[]);
				request.repeat(stderrBuffer);
			}
		}
	}

	private AsyncReadRequest stderrRead;
	private void readMoreStderr() {
		stderrRead = process.stderr.read(stderrBuffer);
		stderrRead.oncomplete = &readDone;
		stderrRead.start();
	}

	private AsyncWriteRequest stdinWrite;
	private const(void)[] input;
	private void writeMoreStdin() {
		stdinWrite = process.stdin.write(input);
		stdinWrite.oncomplete = &writeDone;
		stdinWrite.start();
	}
	private void writeDone(AsyncWriteRequest request) {
		auto result = request.waitForCompletion();
		if(result.wasSuccessful) {
			input = input[result.bufferWritten.length .. $];
			if(input.length && result.bufferWritten.length) {
				request.repeat(cast(ubyte[]) input);
			} else if(closeStdInputWhenDoneWithQueue) {
				process.stdin.close();
			}
		}
	}

	private void forwardOnResolution() {
		if(this.onresolution)
			this.onresolution();
	}

	private this(ExternalProcess process, void delegate(in ubyte[]) onStdoutReceived, void delegate(in ubyte[]) onStderrReceived) {
		this.process = process;

		process.onresolution = &forwardOnResolution;

		process.start();

		this.onStdoutReceived = onStdoutReceived;
		if(onStdoutReceived !is null) {
			stdoutBuffer = new ubyte[](64 * 1024);
			readMoreStdout();
		} else {
			process.stdout.close();
		}

		this.onStderrReceived = onStderrReceived;
		if(onStderrReceived !is null) {
			stderrBuffer = new ubyte[](64 * 1024);
			readMoreStderr();
		} else {
			process.stderr.close();
		}
	}

	/++
	+/
	override ExecuteResult waitForCompletion() {
		process.waitForCompletion();
		if(!process.stdin.isClosed())
			process.stdin.close();

		// FIXME: what if there's unread data left in the buffer? should we wait for it to drain?
		if(!process.stdout.isClosed())
			process.stdout.close();
		if(!process.stderr.isClosed())
			process.stderr.close();

		return ExecuteResult(stdout, stderr, process.status);
	}

	private bool stdoutWriteQueued = false;
	/++
	+/
	void queueStdInput(const(void)[] data) {
		input ~= data;
		if(!stdoutWriteQueued) {
			writeMoreStdin();
			stdoutWriteQueued = true;
		}
	}

	private bool closeStdInputWhenDoneWithQueue;

	/++
	+/
	void closeStdInput() {
		if(input.length)
			closeStdInputWhenDoneWithQueue = true;
		else {
			process.stdin.close();
		}

	}
}

/+
enum Flags {
	emptyEnvironment
}
+/

enum StderrBehavior {
	keepSeparate,
	//mergeIntoStdout,
	//inheritFromParent,
}

/++
	Executes the given process, giving it your `input`. It returns the process you can wait on, and when it is finished, you get its status, stdout, and stderr as byte arrays.
+/
ExecuteFuture execute(string command, NativeProcessArguments args, const(void)[] input = null, StderrBehavior stderrBehavior = StderrBehavior.keepSeparate) {
	ExecuteFuture future;

	future = pipeProcess(command, args, (buffer) { future.stdout ~= buffer; }, (buffer) { future.stderr ~=  buffer; });

	if(input.length)
		future.queueStdInput(input);

	future.closeStdInput();

	return future;
}

/++
	Returns a process execution object with custom input and output available.

	The returned object's stdout and stderr arrays will be empty, because it passes it to your delegates instead.
+/
ExecuteFuture pipeProcess(string command, NativeProcessArguments args, void delegate(in ubyte[]) onStdoutReceived, void delegate(in ubyte[]) onStderrReceived, string[string] environmentVariableModifications = null) {
	static if(is(NativeProcessArguments == string[]))
		args = [command] ~ args;
	else
		args = command ~ " " ~ args;

	ExternalProcess process = new ExternalProcess(searchPathForCommand(command), args);

	process.setEnvironmentWithModifications(environmentVariableModifications);

	auto future = new ExecuteFuture(process, onStdoutReceived, onStderrReceived);

	return future;
}

version(on_adrs_computer)
version(actually_run_processes)
unittest {
	version(Windows)
	auto promise = execute("z:/home/me/program/deesh/cat.exe", "-help", "hey\ni wanna\ntest");
	else
	auto promise = execute("cat", [], "hey");
	auto result = promise.waitForCompletion();
	writeln(cast(string) result.stdout);
	writeln(cast(string) result.stderr);
	assert(result.status == 1);
}

/++
	Searches the PATH environment variable to find the executable for the arg0, if present, and returns it. If not found, returns FilePath(null)
+/
FilePath searchPathForCommand(string arg0) {
	version(Windows)
		import core.sys.windows.windows;

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

