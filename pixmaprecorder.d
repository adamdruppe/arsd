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
		Piping frame data into an independent copy of FFmpeg
		enables this library to be used with a wide range of versions of said
		third-party program
		and (hopefully) helps to reduce the potential for breaking changes.

		It also allows end-users to upgrade their possibilities by swapping the
		accompanying copy FFmpeg.

		This could be useful in cases where software distributors can only
		provide limited functionality in their bundled binaries because of
		legal requirements like patent licenses.
		Keep in mind, support for more formats can be added to FFmpeg by
		linking it against external libraries; such can also come with
		additional distribution requirements that must be considered.
		These things might be perceived as extra burdens and can make their
		inclusion a matter of viability for distributors.
	)

	### Tips and tricks

	$(TIP
		The FFmpeg binary to be used can be specified by the optional
		constructor parameter `ffmpegExecutablePath`.

		It defaults to `ffmpeg`; this will trigger the usual lookup procedures
		of the system the application runs on.
		On POSIX this usually means searching for FFmpeg in the directories
		specified by the environment variable PATH.
		On Windows it will also look for an executable file with that name in
		the current working directory.
	)

	$(TIP
		The value of the `outputFormat` parameter of various constructor
		overloads is passed to FFmpeg via the `-f` (“format”) option.

		Run `ffmpeg -formats` to get a list of available formats.
	)

	$(TIP
		To pass additional options to FFmpeg, use the
		[PixmapRecorder.advancedFFmpegAdditionalOutputArgs|additional-output-args property].
	)

	$(TIP
		Combining this module with [arsd.pixmappresenter|Pixmap Presenter]
		is really straightforward.

		In the most simplistic case, set up a [PixmapRecorder] before running
		the presenter.
		Then call
		[PixmapRecorder.put|pixmapRecorder.record(presenter.framebuffer)]
		at the end of the drawing callback in the eventloop.

		---
		auto recorder = new PixmapRecorder(60, /* … */);
		scope(exit) {
			const recorderStatus = recorder.stopRecording();
		}

		return presenter.eventLoop(delegate() {
			// […]
			recorder.record(presenter.framebuffer);
			return LoopCtrl.redrawIn(16);
		}
		---
	)

	$(TIP
		To use this module with [arsd.color] (which includes the image file
		loading functionality provided by other arsd modules),
		convert the
		[arsd.color.TrueColorImage|TrueColorImage] or
		[arsd.color.MemoryImage|MemoryImage] to a
		[arsd.pixmappaint.Pixmap|Pixmap] first by calling
		[arsd.pixmappaint.Pixmap.fromTrueColorImage|Pixmap.fromTrueColorImage()]
		or
		[arsd.pixmappaint.Pixmap.fromMemoryImage|Pixmap.fromMemoryImage()]
		respectively.
	)

	### Examples

	#### Getting started

	1. Install FFmpeg (the CLI version).
		- Debian derivatives (with FFmpeg in their repos): `apt install ffmpeg`
		- Homebew: `brew install ffmpeg`
		- Chocolatey: `choco install ffmpeg`
		- Links to pre-built binaries can be found on <https://ffmpeg.org/download.html>.
	2. Determine where you’ve installed FFmpeg to.
	   Ideally, it’s somewhere within “PATH” so it can be run from the
	   command-line by just doing `ffmpeg`.
	   Otherwise, you’ll need the specific path to the executable to pass it
	   to the constructor of [PixmapRecorder].

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
import std.range : isOutputRange, OutputRange;
import std.sumtype;
import std.stdio : File;

private @safe {

	auto stderrFauxSafe() @trusted {
		import std.stdio : stderr;

		return stderr;
	}

	auto stderr() {
		return stderrFauxSafe;
	}

	alias RecorderOutput = SumType!(string, File);
}

/++
	Video file encoder

	Feed in video data frame by frame to encode video files
	in one of the various formats supported by FFmpeg.

	This is a convenience wrapper for piping pixmaps into FFmpeg.
	FFmpeg will render an actual video file from the frame data.
	This uses the CLI version of FFmpeg, no linking is required.
 +/
final class PixmapRecorder : OutputRange!(const(Pixmap)) {

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
		Prepares a recorder for encoding a video file into the provided pipe.

		$(WARNING
			FFmpeg cannot produce certain formats in pipes.
			Look out for error messages such as:

			$(BLOCKQUOTE
				`[mp4 @ 0xdead1337beef] muxer does not support non-seekable output`
			)

			This is not a limitation of this library (but rather one of FFmpeg).

			Nevertheless, it’s still possible to use the affected formats.
			Let FFmpeg output the video to the file path instead;
			check out the other constructor overloads.
		)

		Params:
			frameRate     = Framerate of the video output; in frames per second.
			output        = File handle to write the video output to.
			outputFormat  = Video (container) format to output.
			                This value is passed to FFmpeg via the `-f` option.
			log           = Target file for the stderr log output of FFmpeg.
			                This is where error messages are written to.
			ffmpegExecutablePath  = Path to the FFmpeg executable
			                        (e.g. `ffmpeg`, `ffmpeg.exe` or `/usr/bin/ffmpeg`).

		$(COMMENT Keep this table in sync with the ones of other overloads.)
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
		Prepares a recorder for encoding a video file
		saved to the specified path.

		$(TIP
			This allows FFmpeg to seek through the output file
			and enables the creation of file formats otherwise not supported
			when using piped output.
		)

		Params:
			frameRate     = Framerate of the video output; in frames per second.
			outputPath    = File path to write the video output to.
			                Existing files will be overwritten.
			                FFmpeg will use this to autodetect the format
			                when no `outputFormat` is provided.
			log           = Target file for the stderr log output of FFmpeg.
			                This is where error messages are written to, as well.
			outputFormat  = Video (container) format to output.
			                This value is passed to FFmpeg via the `-f` option.
			                If `null`, the format is not provided and FFmpeg
			                will try to autodetect the format from the filename
			                of the `outputPath`.
			ffmpegExecutablePath  = Path to the FFmpeg executable
			                        (e.g. `ffmpeg`, `ffmpeg.exe` or `/usr/bin/ffmpeg`).

		$(COMMENT Keep this table in sync with the ones of other overloads.)
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

		// Sanitize the output path
		// if it were to get confused with a command-line arg.
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
		Additional command-line arguments to be passed to FFmpeg.

		$(WARNING
			The values provided through this property function are not
			validated and passed verbatim to FFmpeg.
		)

		$(PITFALL
			If code makes use of this and FFmpeg errors,
			check the arguments provided here first.
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

	/// ditto
	alias isRecording = isOpen;

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
			nor by most real-world applications.
		)

		$(NOTE
			This function is called by [put|put()] automatically.
			There’s usually no need to call this manually.
		)
	 +/
	void open(const Size resolution)
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
		Supplies the next frame to the video encoder.

		$(TIP
			This function automatically calls [open|open()] if necessary.
		)
	 +/
	void put(const Pixmap frame) {
		if (!this.isOpen) {
			this.open(frame.size);
		} else {
			assert(frame.size == _resolution, "Variable resolutions are not supported.");
		}

		_input.writeEnd.rawWrite(frame.data);
	}

	/// ditto
	alias record = put;

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

// self-test
private {
	static assert(isOutputRange!(PixmapRecorder, Pixmap));
	static assert(isOutputRange!(PixmapRecorder, const(Pixmap)));
}
