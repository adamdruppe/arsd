/++
	Facilities for working with external processes.

	See_Also:
		[arsd.shell], [std.process]
	History:
		Added October 19, 2026
+/
module arsd.process;

import arsd.core;

version(Windows) {
	alias NativeProcessArguments = string;

	NativeProcessArguments toNativeProcessArguments(string cmdLine) {
		return cmdLine;
	}

	NativeProcessArguments toNativeProcessArguments(string[] argv) {
		// does NOT try to encode things... because we don't know how to encode it. really should make the user do it.
		string cmdLine;
		foreach(arg; argv) {
			if(cmdLine.length)
				cmdLine ~= " ";
			cmdLine ~= arg;
		}
		return cmdLine;
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
class ExecuteFuture {
	private ExternalProcess process;

	private ubyte[] stdout;
	private ubyte[] stderr;

	private ubyte[] stdoutBuffer;
	private ubyte[] stderrBuffer;

	private AsyncReadRequest stdoutRead;
	private void readMoreStdout() {
		stdoutRead = process.stdout.read(stdoutBuffer);
		stdoutRead.oncomplete = &readDone;
		stdoutRead.start();
	}
	private void readDone(AsyncReadRequest request) {
		auto result = request.waitForCompletion();
		if(result.wasSuccessful) {
			if(request is stdoutRead) {
				stdout ~= result.bufferRead[];
				request.repeat(stdoutBuffer);
			} else {
				stderr ~= result.bufferRead[];
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
			if(input.length) {
				request.repeat(cast(ubyte[]) input);
			} else
				process.stdin.close();
		}
	}

	private this(ExternalProcess process, const(void)[] input) {
		this.process = process;

		stdoutBuffer = new ubyte[](64 * 1024);
		stderrBuffer = new ubyte[](64 * 1024);

		process.start();

		this.input = input;
		if(input.length)
			writeMoreStdin();
		else
			process.stdin.close();

		readMoreStdout();
		readMoreStderr();
	}

	/++
	+/
	ExecuteResult waitForCompletion() {
		process.waitForCompletion();
		return ExecuteResult(stdout, stderr, process.status);
	}
}

/++

+/
ExecuteFuture execute(string command, NativeProcessArguments args, const(void)[] input = null) {
	static if(is(NativeProcessArguments == string[]))
		args = [command] ~ args;
	else
		args = command ~ " " ~ args;

	ExternalProcess process = new ExternalProcess(searchPathForCommand(command), args);
	return new ExecuteFuture(process, input);
}

version(on_adrs_computer)
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

