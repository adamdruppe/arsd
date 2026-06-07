/+
	== arsd.pixmappaint_addons.gamut ==
	Copyright Elias Batek (0xEAB) 2024.
	Distributed under the Boost Software License, Version 1.0.
 +/
/++
	[Gamut](https://github.com/AuburnSounds/gamut) integration add-on for [arsd.pixmappaint].

	See_Also:
		<https://github.com/AuburnSounds/gamut>

	History:
		Added June 7, 2026.
 +/
module arsd.pixmappaint_addons.gamut;

import arsd.core;
import arsd.pixmappaint;
static import gamut;

alias GamutImage = gamut.Image;

/++
	This means that something went wrong using the $(I Gamut) integration of Pixmap Paint.
 +/
class GamutIntegrationException : ArsdExceptionBase
{
	this(string operation, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @trusted
	{
		super(operation, file, line, next);
	}
}

/++
	Creates a Pixmap copying the pixel data from the provided [GamutImage].

	---
	// Load image using Gamut
	import gamut;
	Image img;
	img.loadFromFile("dunes.jpg");

	// Convert to Pixmap
	Pixmap pixmap = img.toPixmap();
	---
 +/
bool toPixmap(ref GamutImage source, out Pixmap result) @trusted nothrow
in (source.isValid)
{
	import gamut;

	enum supportedLayout = (LAYOUT_GAPLESS | LAYOUT_VERT_STRAIGHT);
	enum supportedFormat = PixelType.rgba8;

	immutable bool needsConversion = (
		(source.layoutConstraints != supportedLayout)
			|| (source.type != supportedFormat)
	);

	if (needsConversion) {
		source = source.clone();

		immutable conversionSuccessful = source.convertTo(supportedFormat, supportedLayout);
		if (!conversionSuccessful) {
			return false;
		}
	}

	Pixel[] data = source.allPixelsAtOnce()
		.castTo!(void[])
		.castTo!(Pixel[])
		.dup;

	result = Pixmap(data, source.width);
	return true;
}

/++
	Creates a Pixmap copying the pixel data from the provided [GamutImage].
 +/
Pixmap toPixmap(ref GamutImage source) @safe
{
	if (source.isError) {
		import std.format : format;

		throw new GamutIntegrationException(format!"Invalid source image. Gamut reports: \"%s\""(source.errorMessage));
	}

	Pixmap result;
	const success = toPixmap(source, result);

	if (!success) {
		throw new GamutIntegrationException("Failed to convert `gamut`.`Image` to a supported format.");
	}

	return result;
}
