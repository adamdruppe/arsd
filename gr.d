#!/usr/bin/env -S rdmd -version=ArsdGrCalculatorMain
/+
	== arsd.gr ==
	Copyright Mindy Batek (0xEAB) 2026.
	Distributed under the Boost Software License, Version 1.0.
 +/
/++
	Math library providing constants and functions for working with
	[the golden ratio](https://en.wikipedia.org/wiki/Golden_ratio).

	$(RAW_HTML <math style="margin-left:2em">
		<mrow>
			<mi>φ</mi>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mfrac>
				<mrow>
					<mi>a</mi>
					<mo>+</mo>
					<mi>b</mi>
				</mrow>
				<mi>a</mi>
			</mfrac>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mfrac>
				<mi>a</mi>
				<mi>b</mi>
			</mfrac>
		</mrow>
	</math>)

	---
	import arsd.gr;

	void main() {
		import std.conv;
		import std.string;
		import std.stdio;

		// `arsd.gr.goldenRatio` is a compile-time constant
		// holding the value representing the golden ratio.
		float gr = goldenRatio;
		writeln(i"The golden ratio is $(gr).");

		while (true) {
			// Prompt user to enter a length.
			write("\nEnter combined length: ");
			string rawUserInput = readln().chomp();

			// Parse user input string into a numeric floating-point value.
			float combinedLength;
			try {
				combinedLength = rawUserInput.to!float;
			}
			catch (Exception) {
				// Print error message and continue with another prompt.
				writeln("Bad input.");
				continue;
			}

			// Construct a GoldenRatioLengths structure.
			GoldenRatioLengths!float lengths = goldenRatioLengthsFromAB(combinedLength);

			// Calculate and print lengths.
			writeln(i"AB: $(lengths.ab)");
			writeln(i"a:  $(lengths.a)");
			writeln(i"b:  $(lengths.b)");
		}
	}
	---

	## Command-line calculator app

	To build the command-line app for the golden ratio calculator,
	run one of the following commands.

	```sh
	# Run it directly from your favorite compiler.
	dmd     -version=ArsdGrCalculatorMain -run gr.d -- <args>
	ldc2 --d-version=ArsdGrCalculatorMain -run gr.d -- <args>

	# Using rdmd works, too.
	rdmd    -version=ArsdGrCalculatorMain      gr.d -- <args>

	# Run it with DUB, either by fetching it from the registry or directly from its folder.
	dub run --config=calculator  arsd-official:gr   -- <args>
	dub run --config=calculator               :gr   -- <args>

	# Or just execute this very file. (POSIX only)
	./gr.d  <args>
	```

	A short help text with usage instructions can be printed by running the command-line app with argument `--help`.

	## Terminology

	In mathematics, the golden ratio — usually denoted by Greek lowercase letter phi `φ` —
	is the partitioning ratio of a line segment in two subsegments that share the same ratio to each other
	as the combined line segment to the longer subsegment.

	$(RAW_HTML <math style="margin-left:2em">
		<mrow>
			<mi>φ</mi>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mfrac>
				<mrow>
					<mi>a</mi>
					<mo>+</mo>
					<mi>b</mi>
				</mrow>
				<mi>a</mi>
			</mfrac>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mfrac>
				<mi>a</mi>
				<mi>b</mi>
			</mfrac>
		</mrow>
	</math>)

	$(TABLE_ROWS
		Variable declarations
		* + Symbol
		+ Meaning
		* + φ
		- Golden ratio
		* + AB
		- A combined line segment whose length is the sum of its two subsegments in the golden ratio.
		* + a
		- Longer subsegment of the combined line segment `AB` in the golden ratio.
		* + b
		- Shorter subsegment of combined line segment `AB` in the golden ratio.
	)

	$(RAW_HTML <svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="270" height="135" viewBox="0 0 270 135">
		<!-- Based on <https://commons.wikimedia.org/wiki/File:Golden_ratio_line.svg>. -->
		<g fill="#F53B57">
			<path d="M100.18 39.07h-1.62q-1.15 0-1.87-.47-.72-.5-1.05-1.37-.32-.86-.32-1.98V35l1.12 1.04h-1.26q-.58 1.7-2.02 2.6-1.4.86-3.35.86-2.95 0-4.6-1.51-1.63-1.51-1.63-4.1 0-1.77.87-2.96.86-1.22 2.6-1.83 1.75-.65 4.45-.65h3.68V26.6q0-1.98-1.08-3.02-1.08-1.05-3.32-1.05-1.65 0-2.8.76-1.16.76-1.91 2.02l-1.73-1.62q.76-1.48 2.41-2.56t4.18-1.08q3.35 0 5.22 1.66 1.9 1.65 1.9 4.6v10.23h2.13zm-5-8.46h-3.82q-2.45 0-3.6.72t-1.15 2.09v.75q0 1.37 1 2.13 1.01.75 2.67.75 1.44 0 2.52-.43 1.12-.47 1.73-1.22.65-.8.65-1.73z"/>
			<path d="m16.22 39.5-.88.9-3.96 3.98-.88.87.88.9 3.96 3.98.88.87.9-.87 3.63-3.63h138.16l3.65 3.63.88.87v-3.53l-2.19-2.22 2.19-2.19V39.5l-.88.9-3.65 3.66V44H20.72l-3.6-3.6zm0 3.56 2.22 2.19-2.22 2.22-2.19-2.22z"/>
		</g>
		<g fill="#3C40C6">
			<path d="M200.15 39.07V12.43h2.88v11.09h.14q.72-1.77 2.13-2.6 1.4-.86 3.3-.86 2.35 0 4.04 1.19 1.7 1.19 2.6 3.38.93 2.16.93 5.15 0 2.95-.94 5.15-.9 2.2-2.59 3.38-1.69 1.19-4.03 1.19-1.9 0-3.28-.86-1.33-.87-2.16-2.6h-.14v3.03zm7.67-2.16q2.45 0 3.85-1.51 1.4-1.55 1.4-4.04V28.2q0-2.49-1.4-4-1.4-1.55-3.85-1.55-1.3 0-2.41.47-1.08.47-1.73 1.26-.65.8-.65 1.84v6.9q0 1.2.65 2.06.65.83 1.73 1.3 1.11.43 2.4.43"/>
			<path d="M163.44 39.5v3.56l2.22 2.19-2.22 2.22V51l.9-.87 3.63-3.63h81.28l3.66 3.63.87.87.88-.87 3.97-3.97.9-.91-.9-.87-3.97-3.97-.88-.91-.87.9-3.63 3.6h-81.34l-3.6-3.6zm90.34 3.56 2.22 2.19-2.22 2.22-2.22-2.22z"/>
		</g>
		<g fill="#05C46B">
			<path d="M16.74 55.44c.53 10.8 11.13 19.13 34.5 18.87h56.65c21.07 0 24.65 7.84 27.32 13.75 2.67-5.9 6.24-13.75 27.3-13.75h56.66c23.38.26 33.97-8.07 34.5-18.87-3.84 7.36-8.5 16-29.78 16h-63.62c-16.9 0-22.68 6.66-25.06 9.65-2.39-3-8.17-9.65-25.07-9.65H46.52c-21.27 0-25.94-8.64-29.78-16"/>
			<path d="M123.34 114.7h-1.62q-1.16 0-1.88-.47-.72-.5-1.04-1.36t-.33-1.98v-.26l1.12 1.05h-1.26q-.58 1.69-2.02 2.59-1.4.86-3.34.86-2.96 0-4.61-1.5-1.62-1.52-1.62-4.11 0-1.77.86-2.95.87-1.23 2.6-1.84 1.76-.65 4.46-.65h3.67v-1.83q0-1.98-1.08-3.03t-3.31-1.04q-1.66 0-2.8.75t-1.92 2.02l-1.73-1.62q.76-1.48 2.42-2.56t4.17-1.08q3.35 0 5.22 1.66 1.91 1.65 1.91 4.6v10.23h2.12zm-5-8.46h-3.83q-2.44 0-3.6.72t-1.15 2.09v.76q0 1.36 1.01 2.12t2.66.76q1.44 0 2.52-.44 1.12-.47 1.73-1.22.65-.8.65-1.73zm18.2 6.23h-2.73v-7.53h-7.02v-2.44h7.02v-7.53h2.74v7.53h7.02v2.44h-7.02zm12.5 2.23V88.06h2.88v11.09h.14q.72-1.77 2.13-2.6 1.4-.86 3.3-.86 2.35 0 4.04 1.2t2.6 3.37q.93 2.16.93 5.15 0 2.95-.94 5.15-.9 2.2-2.59 3.38t-4.03 1.2q-1.9 0-3.28-.87-1.33-.87-2.16-2.6h-.14v3.03zm7.67-2.16q2.45 0 3.85-1.51 1.4-1.55 1.4-4.03v-3.17q0-2.48-1.4-4-1.4-1.54-3.85-1.54-1.3 0-2.41.46-1.08.47-1.73 1.26t-.65 1.84v6.91q0 1.19.65 2.05.65.83 1.73 1.3 1.11.43 2.4.43"/>
		</g>
	</svg>)

	The golden ratio can be calculated using the positive solution of following formula:

	$(RAW_HTML <math style="margin-left:2em">
		<mrow>
			<mi>φ</mi>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<msup>
				<mi>φ</mi>
				<mn>2</mn>
			</msup>
			<mo>-</mo>
			<mn>1</mn>
		</mrow>
	</math>)

	$(RAW_HTML <math style="margin-left:2em">
		<mrow>
			<mi>φ</mi>
			<mo style="margin:0 0.25rem">=</mo>
		</mrow>
		<mrow>
			<mfrac>
				<mrow>
					<mn>1</mn>
					<mo>+</mo>
					<msqrt>
						<mn>5</mn>
					</msqrt>
				</mrow>
				<mn>2</mn>
			</mfrac>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mn>1.61803<mo>…</mo></mn>
		</mrow>
	</math>)

	From this it follows that for a line segment `AB` the longer subsegment `a` can be calculated with this formula:
	$(RAW_HTML <math style="margin-left:2em">
		<mrow>
			<mi>a</mi>
			<mo>(</mo>
			<mover accent="true">
				<mi>AB</mi>
				<mo>—</mo>
			</mover>
			<mo>)</mo>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mfrac>
				<mover accent="true">
					<mi>AB</mi>
					<mo>—</mo>
				</mover>
				<mn>2</mn>
			</mfrac>
			<mo>&#x2062;</mo>
			<mo>(</mo>
			<msqrt>
				<mn>5</mn>
			</msqrt>
			<mo>-</mo>
			<mn>1</mn>
			<mo>)</mo>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mover accent="true">
				<mi>AB</mi>
				<mo>—</mo>
			</mover>
			<mo>&times;</mo>
			<mi>0.61803<mo>…</mo></mi>
		</mrow>
	</math>)

	The shorter subsegment `b` of a line segment `AB` is therefore calculated as follows:
	$(RAW_HTML <math style="margin-left:2em">
		<mrow>
			<mi>b</mi>
			<mo>(</mo>
			<mover accent="true">
				<mi>AB</mi>
				<mo>—</mo>
			</mover>
			<mo>)</mo>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mfrac>
				<mover accent="true">
					<mi>AB</mi>
					<mo>—</mo>
				</mover>
				<mn>2</mn>
			</mfrac>
			<mo>&#x2062;</mo>
			<mo>(</mo>
			<mn>3</mn>
			<mo>-</mo>
			<msqrt>
				<mn>5</mn>
			</msqrt>
			<mo>)</mo>
		</mrow>
		<mo style="margin:0 0.25rem">=</mo>
		<mrow>
			<mover accent="true">
				<mi>AB</mi>
				<mo>—</mo>
			</mover>
			<mo>&times;</mo>
			<mi>0.38196<mo>…</mo></mi>
		</mrow>
	</math>)
 +/
module arsd.gr;

static import std.math;
static import std.stdio;
static import std.traits;

/++
	The golden ratio.

	$(RAW_HTML <math>
		<mi>φ</mi>
		<mo>=</mo>
		<mn>1.61803<mo>…</mo></mn>
	</math>)

	See_also:
		[GoldenRatio.ratio]
 +/
enum goldenRatio = GoldenRatioLengths!(real).ratio;

@safe pure nothrow @nogc {
	/++
		Constructs a [GoldenRatioLengths] structure from the provided value for `AB`.
	 +/
	GoldenRatioLengths!Float goldenRatioLengthsFromAB(Float)(Float value)
	if (std.traits.isFloatingPoint!Float) {
		return GoldenRatioLengths!Float.fromAB(value);
	}

	/++
		Constructs a [GoldenRatioLengths] structure from the provided value for `a`.
	 +/
	GoldenRatioLengths!Float goldenRatioLengthsFromA(Float)(Float value)
	if (std.traits.isFloatingPoint!Float) {
		return GoldenRatioLengths!Float.fromA(value);
	}

	/++
		Constructs a [GoldenRatioLengths] structure from the provided value for `b`.
	 +/
	GoldenRatioLengths!Float goldenRatioLengthsFromB(Float)(Float value)
	if (std.traits.isFloatingPoint!Float) {
		return GoldenRatioLengths!Float.fromB(value);
	}
}

/++
	Golden ratio line segment lengths.
 +/
struct GoldenRatioLengths(Float)
if (std.traits.isFloatingPoint!Float) {
	// constants
	public {
		/++
			The golden ratio.

			$(RAW_HTML <math>
				<mi>φ</mi>
				<mo>=</mo>
				<mn>1.61803<mo>…</mo></mn>
			</math>)

			See_also:
				[goldenRatio]
		 +/
		enum Float ratio = (UnitLengths.half * (UnitLengths.ab + sqrt5));

		///
		enum UnitLengths {
			///
			zero = Float(0),

			/++
				The unit length.
			 +/
			one = Float(1),

			/++
				One half of the unit length —
				that is, a length of `0.5`.
			 +/
			half = (one / 2),

			/++
				Length of line segment `a` as fraction of the unit length —
				that is, a length of `0.61803…`.
			 +/
			a = (half * (sqrt5 - Float(1))),

			/++
				Length of line segment `b` as fraction of the unit length —
				that is, a length of `0.38196…`.
			 +/
			b = (half * (Float(3) - sqrt5)),

			/++
				Unit length of line segment `AB` —
				that is, a length of `1`.
			 +/
			ab = Float(one),
		}

		/++
			The square root of `5`.
			An important number in golden ratio math.
		 +/
		enum Float sqrt5 = std.math.sqrt(Float(5));
	}

	private {
		Float _ab;
	}

@safe pure nothrow @nogc:

	/++
		Constructs a [GoldenRatioLengths] structure from the provided value for `AB`.
	 +/
	this(Float ab) {
		_ab = ab;
	}

	public {
		/++
			Combined line segment `AB`.
		 +/
		Float ab() const {
			return _ab;
		}

		/// ditto
		void ab(Float value) {
			_ab = value;
		}

		/++
			Line segment `a` —
			that is, the longer subsegment of the combined line segment.
		 +/
		Float a() const {
			return (_ab * UnitLengths.a);
		}

		/// ditto
		void a(Float value) {
			_ab = (value / UnitLengths.a);
		}

		/++
			Line segment `b` —
			that is, the shorter subsegment of the combined line segment.
		 +/
		Float b() const {
			return (_ab * UnitLengths.b);
		}

		/// ditto
		void b(Float value) {
			_ab = (value / UnitLengths.b);
		}
	}

	public static {
		/++
			Constructs a [GoldenRatioLengths] structure from the provided value for `AB`.

			See_also:
				[goldenRatioLengthsFromAB]
		 +/
		typeof(this) fromAB(Float value) {
			return typeof(this)(value);
		}

		/++
			Constructs a [GoldenRatioLengths] structure from the provided value for `a`.

			See_also:
				[goldenRatioLengthsFromA]
		 +/
		typeof(this) fromA(Float value) {
			const valueAB = (value / UnitLengths.a);
			return fromAB(valueAB);
		}

		/++
			Constructs a [GoldenRatioLengths] structure from the provided value for `b`.

			See_also:
				[goldenRatioLengthsFromB]
		 +/
		typeof(this) fromB(Float value) {
			const valueAB = (value / UnitLengths.b);
			return fromAB(valueAB);
		}
	}
}

/++
	Standard I/O pipes
 +/
private struct StdIO {
	///
	alias Pipe = std.stdio.File;

	///
	Pipe stdin;
	///
	Pipe stdout;
	///
	Pipe stderr;
}

/++
	Portable entrypoint of the command-line calculator app.

	---
	import arsd.gr;
	import std.stdio;
	int main(string[] args) => runGoldenRatioCalculatorApp!()(args, stdin, stdout, stderr);
	---

	You can also define version `ArsdGrAppMain` to use the library-provided `main()` function instead.
 +/
int runGoldenRatioCalculatorApp(Float = real)(
	string[] args,
	std.stdio.File stdin,
	std.stdio.File stdout,
	std.stdio.File stderr,
) @safe
if (std.traits.isFloatingPoint!Float) {
	return runGoldenRatioCalculatorApp!Float(args, StdIO(stdin, stderr, stdout));
}

private int runGoldenRatioCalculatorApp(Float = real)(string[] args, StdIO io) @safe
if (std.traits.isFloatingPoint!Float) {
	return CalculatorApp!(Float).runApp(args, io);
}

private template CalculatorApp(Float)
if (std.traits.isFloatingPoint!Float) {
	static import std.conv;
	static import std.format;

	alias GR = GoldenRatioLengths!Float;
	alias to = std.conv.to;

	static immutable errorTooManyArguments = "Error: Too many arguments.";

	struct UserInput {
		bool helpWanted = false;
		string error = null;

		private {
			string _ab = null;
			string _a = null;
			string _b = null;
		}

		@safe pure nothrow @nogc {
			string ab() const => _ab;
			string a() const => _a;
			string b() const => _b;

			void ab(string value) {
				if (_ab !is null) {
					error = "Argument `AB` has been provided multiple times.";
				}
				_ab = value;
			}

			void a(string value) {
				if (_a !is null) {
					error = "Argument `a` has been provided multiple times.";
				}
				_a = value;
			}

			void b(string value) {
				if (_b !is null) {
					error = "Argument `b` has been provided multiple times.";
				}
				_b = value;
			}
		}
	}

@safe:

	int runApp(string[] args, StdIO io) {
		const userInput = parseArgs(args);

		if (userInput.helpWanted) {
			io.stdout.writeHelp(args[0]);
			return 0;
		}

		if (userInput.error !is null) {
			io.stderr.writeln("Error: ", userInput.error);
			return 1;
		}

		if (userInput.ab !is null) {
			return runAB(userInput, io);
		}

		if (userInput.a !is null) {
			return runA(userInput, io);
		}

		if (userInput.b !is null) {
			return runB(userInput, io);
		}

		io.stderr.writeHelp(args[0]);
		io.stderr.writeln("Exiting: Nothing to do.");
		return 1;
	}

	int runAB(UserInput userInput, StdIO io) {
		if ((userInput.a !is null) || (userInput.b !is null)) {
			io.stderr.writeln(errorTooManyArguments);
			return 1;
		}

		Float parsedAB;
		try {
			parsedAB = userInput.ab.to!Float();
		}
		catch (Exception ex) {
			io.stderr.writeln("Error: ", ex.msg);
			return 1;
		}

		const gr = GR.fromAB(parsedAB);
		io.stdout.writeResult(gr);
		return 0;
	}

	int runA(UserInput userInput, StdIO io) {
		if ((userInput.ab !is null) || (userInput.b !is null)) {
			io.stderr.writeln(errorTooManyArguments);
			return 1;
		}

		Float parsedA;
		try {
			parsedA = userInput.a.to!Float();
		}
		catch (Exception ex) {
			io.stderr.writeln("Error: ", ex.msg);
			return 1;
		}

		const gr = GR.fromA(parsedA);
		io.stdout.writeResult(gr);
		return 0;
	}

	int runB(UserInput userInput, StdIO io) {
		if ((userInput.ab !is null) || (userInput.a !is null)) {
			io.stderr.writeln(errorTooManyArguments);
			return 1;
		}

		Float parsedB;
		try {
			parsedB = userInput.b.to!Float();
		}
		catch (Exception ex) {
			io.stderr.writeln("Error: ", ex.msg);
			return 1;
		}

		const gr = GR.fromB(parsedB);
		io.stdout.writeResult(gr);
		return 0;
	}

	UserInput parseArgs(string[] args) {
		import std.conv : text;
		import std.string : indexOf, isNumeric, toLower;

		auto userInput = UserInput();

		if (args.length < 1) {
			userInput.error = "No arguments provided.";
			return userInput;
		}

		args = args[1 .. $];

		bool skip = false;

		foreach (idx, arg; args) {
			string captureNext() {
				skip = true;
				const idxNext = idx + 1;
				if (idxNext == args.length) {
					userInput.error = i"No value provided for argument `$(arg)`.".text;
					return null;
				}

				return args[idxNext];
			}

			if (skip) {
				skip = false;
				continue;
			}

			arg = arg.toLower();

			const idxSep = arg.indexOf('=');
			if (idxSep > 0) {
				const key = arg[0 .. idxSep];
				const value = arg[idxSep + 1 .. $];

				switch (key) {
				default:
					userInput.error = i"`$(key)` is not a supported argument.".text;
					return userInput;

				case "ab":
				case "-ab":
				case "--ab":
					userInput.ab = value;
					break;

				case "a":
				case "-a":
				case "--a":
					userInput.a = value;
					break;

				case "b":
				case "-b":
				case "--b":
					userInput.b = value;
					break;
				}

				continue;
			}

			switch (arg) {
			default:
				if ((idx == 0) && (args.length == 1) && arg.isNumeric) {
					userInput.ab = arg;
					break;
				}
				userInput.error = i"`$(arg)` is not a supported argument.".text;
				return userInput;

			case "--help":
			case "-h":
			case "-?":
			case "help":
				userInput.helpWanted = true;
				return userInput;

			case "ab":
			case "-ab":
			case "--ab":
				userInput.ab = captureNext();
				break;

			case "a":
			case "-a":
			case "--a":
				userInput.a = captureNext();
				break;

			case "b":
			case "-b":
			case "--b":
				userInput.b = captureNext();
				break;
			}
		}

		return userInput;
	}

	void writeHelp(StdIO.Pipe target, string arg0) {
		static string formatNum(Float value) => std.format.format!"%.3f"(value);
		static string formatPct(Float value) => std.format.format!"%.3f %%"(value * 100);
		enum strGR = formatNum(GR.ratio);
		enum strUA = formatPct(GR.UnitLengths.a);
		enum strUB = formatPct(GR.UnitLengths.b);

		const helpText = "gr - ARSD Golden ratio calculator"
			~ "\n"
			~ "\nUsage:"
			~ "\n\t" ~ arg0 ~ "             <AB>  - Calculate `a` and `b`."
			~ "\n\t" ~ arg0 ~ "      ab     <AB>  - Calculate `a` and `b`."
			~ "\n\t" ~ arg0 ~ "       a      <a>  - Calculate `AB` and `b`."
			~ "\n\t" ~ arg0 ~ "       b      <b>  - Calculate `AB` and `a`."
			~ "\n\t" ~ arg0 ~ "  --help           - Display this help text."
			~ "\n"
			~ "\nVariables:"
			~ "\n\t              a :=      longer subsegment"
			~ "\n\t              b :=     shorter subsegment"
			~ "\n\t             AB :=  combined line segment"
			~ "\nConstants:"
			~ "\n\t   golden ratio :=  ~ " ~ strGR
			~ "\n\t unit-length(a) :=  ~ " ~ strUA
			~ "\n\t unit-length(b) :=  ~ " ~ strUB
			~ "\n";

		target.writeln(helpText);
	}

	void writeResult(StdIO.Pipe target, GR result) {
		static string formatNum(Float value) => std.format.format!"%.6f"(value);

		const strA = formatNum(result.a);
		const strB = formatNum(result.b);
		const strC = formatNum(result.ab);

		target.write(
			"AB :=  ", strC, "\n",
			" a :=  ",
		);
		foreach (_; strA.length .. strC.length) {
			target.write(' ');
		}
		target.write(
			strA, "\n",
			" b :=  ",
		);
		foreach (_; strB.length .. strC.length) {
			target.write(' ');
		}
		target.writeln(strB);
	}
}

version (ArsdGrCalculatorMain) {
	/++
		This is the $(I optional) library-provided `main()` function for the built-in calculator app.

		Supply `-version=ArsdGrCalculatorMain` to the compiler to enable it.

		The calculator app can also be launched from the library API.

		See_also:
			[runGoldenRatioCalculatorApp]

		$(ALWAYS_DOCUMENT)
	 +/
	private int main(string[] args) @safe {
		auto io = (() @trusted => StdIO(std.stdio.stdin, std.stdio.stdout, std.stdio.stderr))();
		return runGoldenRatioCalculatorApp!real(args, io);
	}
}
