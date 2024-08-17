/+
	== pixmaprecorder ==
	Copyright Elias Batek (0xEAB) 2024.
	Distributed under the Boost Software License, Version 1.0.
 +/
/++
	$(B Pixmap Recorder) is an auxiliary library for rendering video files from
	[arsd.pixmappaint.Pixmap|Pixmap] frames by piping them to
	[FFmpeg](https://ffmpeg.org/about.html).

	$(SIDEBAR
		Piping frame data to an independent copy of FFmpeg enables this library
		to be used with a wide range of verions of said third-party program
		and (hopefully) helps to reduce the chances of breaking changes.

		It also allows end-users to upgrade their possibilities by swapping the
		accompanying copy FFmpeg.
		This could be useful in cases where software distributors can only
		provide limited functionality in their bundled binaries because of
		legal requirements like patent licenses.
	)

	$(TIP
		The value of the `outputFormat` parameter of the constructor overloads
		is passed to FFmpeg via the `-f` option.

		Run `ffmpeg -formats` to get a list of available formats.
	)

	$(TIP
		To pass additional options to FFmpeg, use the
		[PixmapRecorder.advancedFFmpegAdditionalOutputArgs|additional-output-args property].
	)

	---
	import arsd.pixmaprecorder;
	import arsd.pixmappaint;

	/++
		This demo renders a 1280×720 video at 30 FPS
		fading from white (#FFF) to blue (#00F).
	 +/
	int main() {
		// Instantiate a recorder.
		auto recorder = new PixmapRecorder(
			30,        // Video framerate [=FPS]
			"out.mkv", // Output path to write the video file to.
		);

		// We will use this framebuffer later on to provide image data
		// to the encoder.
		auto frame = Pixmap(1280, 720);

		for (int light = 0xFF; light >= 0; --light) {
			auto color = Color(light, light, 0xFF);
			frame.clear(color);

			// Record the current frame.
			// The video resolution to use is derived from the first frame.
			recorder.put(frame);
		}

		// End and finalize the recording process.
		return recorder.stopRecording();
	}
	---
 +/
module arsd.pixmaprecorder;

import arsd.pixmappaint;

import std.format;
import std.path : buildPath;
import std.process;
import std.sumtype;
import std.stdio : File;

private @safe {

	auto stderrFauxSafe() @trusted {
		import std.stdio : stderr;

		return stderr;
	}

	auto stdoutFauxSafe() @trusted {
		import std.stdio : stderr;

		return stderr;
	}

	auto stderr() {
		return stderrFauxSafe;
	}

	auto stdout() {
		return stderrFauxSafe;
	}

	alias RecorderOutput = SumType!(string, File);
}

final class PixmapRecorder {

@safe:

	private {
		string _ffmpegExecutablePath;
		double _frameRate;
		string _outputFormat;
		RecorderOutput _output;
		File _log;
		string[] _outputAdditionalArgs;

		Pid _pid;
		Pipe _input;
		Size _resolution;
		bool _outputIsOurs = false;
	}

	private this(
		string ffmpegExecutablePath,
		double frameRate,
		string outputFormat,
		RecorderOutput output,
		File log,
	) {
		_ffmpegExecutablePath = ffmpegExecutablePath;
		_frameRate = frameRate;
		_outputFormat = outputFormat;
		_output = output;
		_log = log;
	}

	/++
		Prepares a recorder for encoding video frames
		into the specified file pipe.

		$(WARNING
			Certain formats cannot be produced in pipes by FFmpeg.
			Look out for error message like such:

			($BLOCKQUOTE
				`[mp4 @ 0xdead1337beef] muxer does not support non seekable output`
			)

			This is not a limitation of this library (but rather one of FFmpeg).
			Let FFmpeg output the video to file path instead;
			check out the other overloads of this constructor.
		)

		Params:
			frameRate     = Framerate of the video output; in frames per second.
			output        = File handle to write the video output to.
			outputFormat  = Video (container) format to output.
			                This is value passed to FFmpeg via the `-f` option.
			log           = Target file for the stderr log output of FFmpeg.
			                This is where error messages are written to.
			ffmpegExecutablePath  = Path to the FFmpeg executable
			                        (e.g. `ffmpeg`, `ffmpeg.exe` or `/usr/bin/ffmpeg`).
			/* Keep this table in sync with the ones of other overloads. */
	 +/
	public this(
		double frameRate,
		File output,
		string outputFormat,
		File log = stderr,
		string ffmpegExecutablePath = "ffmpeg",
	)
	in (frameRate > 0)
	in (output.isOpen)
	in (outputFormat != "")
	in (log.isOpen)
	in (ffmpegExecutablePath != "") {
		this(
			ffmpegExecutablePath,
			frameRate,
			outputFormat,
			RecorderOutput(output),
			log,
		);
	}

	/++
		Prepares a recorder for encoding video frames
		into a video file saved to the specified path.

		Params:
			frameRate     = Framerate of the video output; in frames per second.
			outputPath    = File path to write the video output to.
			                Existing files will be overwritten.
			                FFmpeg will use this to autodetect the format
			                when no `outputFormat` is provided.
			log           = Target file for the stderr log output of FFmpeg.
			                This is where error messages are written to.
			outputFormat  = Video (container) format to output.
			                This is value passed to FFmpeg via the `-f` option.
			                If `null`, the format is not provided and FFmpeg
			                will try to autodetect the format from the filename
			                of the `outputPath`.
			ffmpegExecutablePath  = Path to the FFmpeg executable
			                        (e.g. `ffmpeg`, `ffmpeg.exe` or `/usr/bin/ffmpeg`).
			/* Keep this table in sync with the ones of other overloads. */
	 +/
	public this(
		double frameRate,
		string outputPath,
		File log = stderr,
		string outputFormat = null,
		string ffmpegExecutablePath = "ffmpeg",
	)
	in (frameRate > 0)
	in ((outputPath != "") && (outputPath != "-"))
	in (log.isOpen)
	in ((outputFormat is null) || outputFormat != "")
	in (ffmpegExecutablePath != "") {

		// Sanitize output path
		// if it would get confused with a command-line arg.
		// Otherwise a relative path like `-my.mkv` would make FFmpeg complain
		// about an “Unrecognized option 'out.mkv'”.
		if (outputPath[0] == '-') {
			outputPath = buildPath(".", outputPath);
		}

		this(
			ffmpegExecutablePath,
			frameRate,
			null,
			RecorderOutput(outputPath),
			log,
		);
	}

	/++
		$(I Advanced users only:)
		Additional command-line arguments passed to FFmpeg.

		$(WARNING
			The values provided through this property function are not
			validated and passed verbatim to FFmpeg.
		)

		$(PITFAL
			If code makes use of this and FFmpeg errors,
			check the arguments provided here this first.
		)
	 +/
	void advancedFFmpegAdditionalOutputArgs(string[] args) {
		_outputAdditionalArgs = args;
	}

	/++
		Determines whether the recorder is active
		(which implies that an output file is open).
	 +/
	bool isOpen() {
		return _input.writeEnd.isOpen;
	}

	private string[] buildFFmpegCommand() pure {
		// Build resolution as understood by FFmpeg.
		const string resolutionString = format!"%sx%s"(
			_resolution.width,
			_resolution.height,
		);

		// Convert framerate to string.
		const string frameRateString = format!"%s"(_frameRate);

		// Build command-line argument list.
		auto cmd = [
			_ffmpegExecutablePath,
			"-y",
			"-r",
			frameRateString,
			"-f",
			"rawvideo",
			"-pix_fmt",
			"rgba",
			"-s",
			resolutionString,
			"-i",
			"-",
		];

		if (_outputFormat !is null) {
			cmd ~= "-f";
			cmd ~= _outputFormat;
		}

		if (_outputAdditionalArgs.length > 0) {
			cmd = cmd ~ _outputAdditionalArgs;
		}

		cmd ~= _output.match!(
			(string filePath) => filePath,
			(ref File file) => "-",
		);

		return cmd;
	}

	/++
		Starts the video encoding process.
		Launches FFmpeg.

		This function sets the video resolution for the encoding process.
		All frames to record must match it.
		
		$(SIDEBAR
			Variable/dynamic resolution is neither supported by this library
			nor most real-world applications.
		)

		$(NOTE
			This function is called by [put|put()] automatically.
			There’s usually no need to call this manually.
		)
	 +/
	void open(Size resolution)
	in (!this.isOpen) {
		// Save resolution for sanity checks.
		_resolution = resolution;

		const string[] cmd = buildFFmpegCommand();

		// Prepare arsd → FFmpeg I/O pipe.
		_input = pipe();

		// Launch FFmpeg.
		const processConfig = (
			Config.suppressConsole
				| Config.newEnv
		);

		// dfmt off
		_pid = _output.match!(
			delegate(string filePath) {
				auto stdout = pipe();
				stdout.readEnd.close();
				return spawnProcess(
					cmd,
					_input.readEnd,
					stdout.writeEnd,
					_log,
					null,
					processConfig,
				);
			},
			delegate(File file) {
				auto stdout = pipe();
				stdout.readEnd.close();
				return spawnProcess(
					cmd,
					_input.readEnd,
					file,
					_log,
					null,
					processConfig,
				);
			}
		);
		// dfmt on
	}

	/// ditto
	alias startRecording = close;

	/++
		Provides the next video frame to encode.

		$(TIP
			This function automatically calls [open|open()] if necessary.
		)
	 +/
	void put(Pixmap frame) {
		if (!this.isOpen) {
			this.open(frame.size);
		} else {
			assert(frame.size == _resolution, "Variable resolutions are not supported.");
		}

		_input.writeEnd.rawWrite(frame.data);
	}

	/++
		Ends the recording process.

		$(NOTE
			Waits for the FFmpeg process to exit in a blocking way.
		)

		Returns:
			The status code provided by the FFmpeg program.
	 +/
	int close() {
		if (!this.isOpen) {
			return 0;
		}

		_input.writeEnd.flush();
		_input.writeEnd.close();
		scope (exit) {
			_input.close();
		}

		return wait(_pid);
	}

	/// ditto
	alias stopRecording = close;
}
