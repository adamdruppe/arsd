/++
	Module for helping to make command line interface programs.


	You make an object with methods. Those methods take arguments and it reads them automatically for you. Or, you just make one function.

	./yourprogram args...

	or

	./yourprogram class_method_name args....

	Args go to:
		bool: --name or --name=true|false
		string/int/float/enum: --name=arg or --name arg
		int[]: --name=arg,arg,arg or --name=arg --name=arg that you can repeat
		string[] : remainder; the name is ignored, these are any args not already consumed by args
		FilePath and FilePath[]: not yet supported

		`--` always stops populating names and puts the remaining in the final string[] args param (if there is one)
		`--help` always

	Return values:
		int is the return value to the cli
		string is output, returns 0
		other types are converted to string except for CliResult, which lets you specify output, error, and code in one struct.
	Exceptions:
		are printed with fairly minimal info to the stderr, cause program to return 1 unless it has a code attached

	History:
		Added May 23, 2025
+/
module arsd.cli;

		// stdin:

/++
	You can pass a function to [runCli] and it will parse command line arguments
	into its arguments, then turn its return value (if present) into a cli return.
+/
unittest {
	static // exclude from docs
	void func(int a, string[] otherArgs) {
		// because we run the test below with args "--a 5"
		assert(a == 5);
		assert(otherArgs.length == 0);
	}

	int main(string[] args) {
		// make your main function forward to runCli!your_handler
		return runCli!func(args);
	}

	assert(main(["unittest", "--a", "5"]) == 0);
}

/++
	You can also pass a class to [runCli], and its public methods will be made
	available as subcommands.
+/
unittest {
	static // exclude from docs
	class Thing {
		void func(int a, string[] args) {
			assert(a == 5);
			assert(args.length == 0);
		}

		// int return values are forwarded to `runCli`'s return value
		int other(bool flag) {
			return flag ? 1 : 0;
		}
	}

	int main(string[] args) {
		// make your main function forward to runCli!your_handler
		return runCli!Thing(args);
	}

	assert(main(["unittest", "func", "--a", "5"]) == 0);
	assert(main(["unittest", "other"]) == 0);
	assert(main(["unittest", "other", "--flag"]) == 1);
}

import arsd.core;

/++

+/
int runCli(alias handler)(string[] args) {
	CliHandler thing;

	static if(is(handler == class)) {
		CliHandler[] allOptions;

		scope auto instance = new handler();
		foreach(memberName; __traits(derivedMembers, handler)) {
			static if(memberName != "__ctor" && memberName != "__dtor") {
				alias member = __traits(getMember, handler, memberName);
				static if(__traits(getProtection, member) == "public") {
					static if(is(typeof(member) == return)) {
						auto ourthing = createCliHandler!member();
						if(args.length > 1 && ourthing.uda.name == args[1]) {
							thing = ourthing;
							break;
						}
						allOptions ~= ourthing;
					}
				}
			}
		}

		if(args.length && args[1] == "--help") {
			foreach(option; allOptions)
				writeln(option.printHelp());

			return 0;
		}

		if(args.length)
			args = args[1 .. $]; // cut off the original args(0) as irrelevant now, the command is the new args[0]
	} else {
		auto instance = null;
		thing = createCliHandler!handler();
	}

	if(!thing.uda.unprocessed && args.length > 1 && args[1] == "--help") {
		writeln(thing.printHelp());
		return 0;
	}

	if(thing.handler is null) {
		throw new CliArgumentException("subcommand", "no handler found");
	}

	auto ret = thing.handler(thing, instance, args);
	if(ret.output.length)
		writeln(ret.output);
	if(ret.error.length)
		writelnStderr(ret.error);
	return ret.returnValue;
}

/++

+/
class CliArgumentException : object.Exception {
	this(string argument, string message) {
		super(argument ~ ": " ~ message);
	}
}

/++
	If your function returns `CliResult`, you can return a value and some output in one object.

	Note that output and error are written to stdout and stderr, in addition to whatever the function
	did inside. It does NOT represent captured stuff, it is just a function return value.
+/
struct CliResult {
	int returnValue;
	string output;
	string error;
}

/++
	Can be attached as a UDA to override defaults
+/
struct Cli {
	string name;

	string summary;
	string help;

	// only valid on function - passes the original args without processing them at all, not even --help
	bool unprocessed; // FIXME mostly not implemented
	// only valid on function - instead of erroring on unknown arg, just pass them unmodified to the catch-all array
	bool passthroughUnrecognizedArguments; // FIXME not implemented


	// only valid on arguments
	dchar shortName; // bool things can be combined and if it is int it can take one like -O2. maybe.
	int required = 2;
	int arg0 = 2;
	int consumesRemainder = 2;
	int holdsAllArgs = 2; // FIXME: not implemented
	string[] options; // FIXME if it is not one of the options and there are options, should it error?
}


version(sample)
void handler(bool sweetness, @Cli(arg0: true) string programName, float f, @Cli(required: true) int a, @Cli(name: "opend-to-build") string[] magic, int[] foo, string[] remainder) {
	import arsd.core;

	if(a == 4)
		throw ArsdException!"lol"(4, 6);

	mixin(dumpParams);
	debug dump(__traits(parameters));
	debug dump(i"$programName");

	static struct Test {
		int a;
		string b;
		float c;
	}

	debug dump(Test(a: 5, b: "omg", c: 7.5));
}

version(sample)
int main(string[] args) {
	/+
	import arsd.core;
	auto e = extractCliArgs(args, false, ["a":true]);
	foreach(a; e)
		writeln(a.name, a.values);
	return 0;
	+/

	return runCli!handler(args);
}

private enum SupportedCliTypes {
	String,
	Int,
	Float,
	Bool,
	IntArray,
	StringArray
}

private struct CliArg {
	Cli uda;
	string argumentName;
	string ddoc;
	SupportedCliTypes type;
	//string default;
}

private struct CliHandler {
	CliResult function(CliHandler info, Object _this, string[] args) handler;
	Cli uda;
	CliArg[] args;

	string methodName;
	string ddoc;

	string printHelp() {
		string help = uda.name;
		if(help.length)
			help ~= ": ";
		help ~= uda.help;
		foreach(arg; args) {
			if(!arg.uda.required)
				help ~= "[";
			if(arg.uda.consumesRemainder)
				help ~= "args...";
			else if(arg.type == SupportedCliTypes.Bool)
				help ~= "--" ~ arg.uda.name;
			else
				help ~= "--" ~ arg.uda.name ~ "=" ~ enumNameForValue(arg.type);
			if(!arg.uda.required)
				help ~= "]";
			help ~= " ";
		}

		// FIXME: print the help details for the args

		return help;
	}
}

private template CliTypeForD(T) {
	static if(is(T == enum))
		enum CliTypeForD = SupportedCliTypes.String;
	else static if(is(T == string))
		enum CliTypeForD = SupportedCliTypes.String;
	else static if(is(T == bool))
		enum CliTypeForD = SupportedCliTypes.Bool;
	else static if(is(T : long))
		enum CliTypeForD = SupportedCliTypes.Int;
	else static if(is(T : double))
		enum CliTypeForD = SupportedCliTypes.Float;
	else static if(is(T : int[]))
		enum CliTypeForD = SupportedCliTypes.IntArray;
	else static if(is(T : string[]))
		enum CliTypeForD = SupportedCliTypes.StringArray;
	else
		static assert(0, "Unsupported type for CLI: " ~ T.stringof);
}

private CliHandler createCliHandler(alias handler)() {
	CliHandler ret;

	ret.methodName = __traits(identifier, handler);
	version(D_OpenD)
		ret.ddoc = __traits(docComment, handler);

	foreach(uda; __traits(getAttributes, handler))
		static if(is(typeof(uda) == Cli))
			ret.uda = uda;

	if(ret.uda.name is null)
		ret.uda.name = ret.methodName;
	if(ret.uda.help is null)
		ret.uda.help = ret.ddoc;
	if(ret.uda.summary is null)
		ret.uda.summary = ret.uda.help; // FIXME: abbreviate

	static if(is(typeof(handler) Params == __parameters))
	foreach(idx, param; Params) {
		CliArg arg;

		arg.argumentName = __traits(identifier, Params[idx .. idx + 1]);
		// version(D_OpenD) arg.ddoc = __traits(docComment, Params[idx .. idx + 1]);

		arg.type = CliTypeForD!param;

		foreach(uda; __traits(getAttributes, Params[idx .. idx + 1]))
			static if(is(typeof(uda) == Cli)) {
				arg.uda = uda;
				// import std.stdio; writeln(cast(int) uda.arg0);
			}


		// if not specified by user, replace with actual defaults
		if(arg.uda.consumesRemainder == 2) {
			if(idx + 1 == Params.length && is(param == string[]))
				arg.uda.consumesRemainder = true;
			else
				arg.uda.consumesRemainder = false;
		} else {
			assert(0,  "do not set consumesRemainder explicitly at least not at this time");
		}
		if(arg.uda.arg0 == 2)
			arg.uda.arg0 = false;
		if(arg.uda.required == 2)
			arg.uda.required = false;
		if(arg.uda.holdsAllArgs == 2)
			arg.uda.holdsAllArgs = false;
		static if(is(param == enum))
		if(arg.uda.options is null)
			arg.uda.options = [__traits(allMembers, param)];

		if(arg.uda.name is null)
			arg.uda.name = arg.argumentName;

		ret.args ~= arg;
	}

	ret.handler = &cliForwarder!handler;

	return ret;
}

private struct ExtractedCliArgs {
	string name;
	string[] values;
}

private ExtractedCliArgs[] extractCliArgs(string[] args, bool needsCommandName, bool[string] namesThatTakeSeparateArguments) {
	// FIXME: if needsCommandName, args[1] should be that
	ExtractedCliArgs[] ret;
	if(args.length == 0)
		return [ExtractedCliArgs(), ExtractedCliArgs()];

	ExtractedCliArgs remainder;

	ret ~= ExtractedCliArgs(null, [args[0]]); // arg0 is a bit special, always the first one
	args = args[1 .. $];

	ref ExtractedCliArgs byName(string name) {
		// FIXME: could actually do a map to index thing if i had to
		foreach(ref r; ret)
			if(r.name == name)
				return r;
		ret ~= ExtractedCliArgs(name);
		return ret[$-1];
	}

	string nextArgName = null;

	void appendPossibleEmptyArg() {
		if(nextArgName is null)
			return;
		byName(nextArgName).values ~= null;
		nextArgName = null;
	}

	foreach(idx, arg; args) {
		if(arg == "--") {
			remainder.values ~= args[idx + 1 .. $];
			break;
		}

		if(arg[0] == '-') {
			// short name or short nameINT_VALUE
			// -longname or -longname=VALUE. if -longname, next arg is its value unless next arg starts with -.

			if(arg.length == 1) {
				// plain - often represents stdin or whatever, treat it as a normal filename arg
				remainder.values ~= arg;
			} else {
				appendPossibleEmptyArg();

				string value;
				if(arg[1] == '-') {
					// long name...
					import arsd.string;
					auto equal = arg.indexOf("=");
					if(equal != -1) {
						nextArgName = arg[2 .. equal];
						value = arg[equal + 1 .. $];
					} else {
						nextArgName = arg[2 .. $];
					}
				} else {
					// short name
					nextArgName = arg[1 .. $]; // FIXME what if there's bundled? or an arg?
				}
				byName(nextArgName);
				if(value !is null) {
					byName(nextArgName).values ~= value;
					nextArgName = null;
				} else if(!namesThatTakeSeparateArguments.get(nextArgName, false)) {
					byName(nextArgName).values ~= null; // just so you can see how many times it appeared
					nextArgName = null;
				}
			}
		} else {
			if(nextArgName !is null) {
				byName(nextArgName).values ~= arg;

				nextArgName = null;
			} else {
				remainder.values ~= arg;
			}
		}
	}

	appendPossibleEmptyArg();

	ret ~= remainder; // remainder also a bit special, always the last one

	return ret;
}

// FIXME: extractPrefix for stuff like --opend-to-build and --DRT- stuff

private T extractCliArgsT(T)(CliArg info, ExtractedCliArgs[] args) {
	try {
		import arsd.conv;
		if(info.uda.arg0) {
			static if(is(T == string)) {
				return args[0].values[0];
			} else {
				assert(0, "arg0 consumers must be type string");
			}
		}

		if(info.uda.consumesRemainder)
			static if(is(T == string[])) {
				return args[$-1].values;
			} else {
				assert(0, "remainder consumers must be type string[]");
			}

		foreach(arg; args)
			if(arg.name == info.uda.name) {
				static if(is(T == string[]))
					return arg.values;
				else static if(is(T == int[])) {
					int[] ret;
					ret.length = arg.values.length;
					foreach(i, a; arg.values)
						ret[i] = to!int(a);

					return ret;
				} else static if(is(T == bool)) {
					// if the argument is present, that means it is set unless the value false was explicitly given
					if(arg.values.length)
						return arg.values[$-1] != "false";
					return true;
				} else {
					if(arg.values.length == 1)
						return to!T(arg.values[$-1]);
					else
						throw ArsdException!"wrong number of args"(arg.values.length);
				}
			}

		return T.init;
	} catch(Exception e) {
		throw new CliArgumentException(info.uda.name, e.toString);
	}
}

private CliResult cliForwarder(alias handler)(CliHandler info, Object this_, string[] args) {
	try {
		static if(is(typeof(handler) Params == __parameters))
			Params params;

		assert(Params.length == info.args.length);

		bool[string] map;
		foreach(a; info.args)
			if(a.type != SupportedCliTypes.Bool)
				map[a.uda.name] = true;
		auto eargs = extractCliArgs(args, false, map);

		/+
		import arsd.core;
		foreach(a; eargs)
			writeln(a.name, a.values);
		+/

		foreach(a; eargs[1 .. $-1]) {
			bool found;
			foreach(a2; info.args)
				if(a.name == a2.uda.name) {
					found = true;
					break;
				}
			if(!found)
				throw new CliArgumentException(a.name, "Invalid arg");
		}

		// FIXME: look for missing required argument
		foreach(a; info.args) {
			if(a.uda.required) {
				bool found = false;
				foreach(a2; eargs[1 .. $-1]) {
					if(a2.name == a.uda.name) {
						found = true;
						break;
					}
				}
				if(!found)
					throw new CliArgumentException(a.uda.name, "Missing required arg");
			}
		}

		foreach(idx, ref param; params) {
			param = extractCliArgsT!(typeof(param))(info.args[idx], eargs);
		}

		auto callit() {
			static if(is(__traits(parent, handler) Parent == class)) {
				auto instance = cast(Parent) this_;
				assert(instance !is null);
				return __traits(child, instance, handler)(params);
			} else {
				return handler(params);
			}
		}

		static if(is(typeof(handler) Return == return)) {
			static if(is(Return == void)) {
				callit();
				return CliResult(0);
			} else static if(is(Return == int)) {
				return CliResult(callit());
			} else static if(is(Return == string)) {
				return CliResult(0, callit());
			} else static assert(0, "Invalid return type on handler: " ~ Return.stringof);
		} else static assert(0, "bad handler");
	} catch(CliArgumentException e) {
		auto str = e.msg;
		auto idx = str.indexOf("------");
		if(idx != -1)
			str = str[0 .. idx];
		str = str.stripInternal();
		return CliResult(1, null, str);
	} catch(Throwable t) {
		auto str = t.toString;
		auto idx = str.indexOf("------");
		if(idx != -1)
			str = str[0 .. idx];
		str = str.stripInternal();
		return CliResult(1, null, str);
	}
}
