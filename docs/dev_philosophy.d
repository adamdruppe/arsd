// just docs: Development Philosophy
/++
	This document aims to describe how things work here, what kind of bugs you can expect, how you can ask for new features, and my views on breaking changes and code organization.

	You can read more in my (aspirationally) weekly blog here: http://dpldocs.info/this-week-in-d/Blog.html


	$(H2 How it is developed)

	This library is mostly developed as a means to an end for me. As such, it might work for you but might not since I usually do just what I need to do to get the job done then move on. I often focus on laying groundwork moreso than "completing" things, since then I can usually add things for myself pretty quickly as I go.

	If you need something, feel free to contact me and I might be able to help code it up fairly quickly and get it to you, then I'll commit later for other people with similar needs.

	$(H2 Code organization)

	The arsd library is more like your public library than most software packages. Like a book library, there's no expectation that every module in here is actually useful to you - you should just browse the available modules and then only use the ones you need.

	Modules usually aim to have as few dependencies as I can, often importing just one or two (or zero!) other modules from the repo. They almost never will import anything from outside this repo or the D standard library. This makes it easy for you to even just download a few individual files from here and use them without the others even being present.

	$(H2 Breaking changes and versioning)

	Typically, once I document something, I try hard to never break it. If I say you can "just download file.d", that's a commitment to never make it import anything else. If I break that commitment, I'll advertise it as a breaking change, add a note to the README file, and bump the package major version on the dub repo, even if nothing else is broken.

	A add things regularly, but until they are documented in a tagged release, I make no promises it won't break. After it is though, I'll maintain it indefinitely (to the extent possible), unless I specifically say otherwise in the documentation comment.

	$(H2 Licensing)

	Everything in here is provided with no warranty of any kind, has no support contract whatsoever, and you assume full responsibility for using it.

	Each file in here may be under a different license, since some of them are adopted ports of other people's code (if I do decide to use a library, I will adopt it and take responsibility for maintaining it myself to ensure our users never have to worry about third-party breakage). Some individual functions will import code with a different license, so you may choose not to use those functions. The documentation will call this out in those specific cases.

	In some cases, different `-version` switches will compile in or version out code with different licenses. Your final result should be assumed to be under the most restrictive license included by any part. I will call this out in the documentation of the modules, if necessary.

	If the documentation and/or source code comments don't say otherwise, you can assume all files are written by me and released under the Boost Software License, 1.0.

	$(WARNING
		dub's package format does not necessarily cover the nuance of optional functions. The documentation and copyright notices in the code are authoritative, not the dub package metadata.
	)

	Nothing in this repo will be licensed incompatibly with the GNU Affero GPL.

	$(H2 FAQs)

	$(H3 What does ARSD stand for?)

	Adam Ruppe's Software Development. It was a fake company I made up in my youth and decided to keep the name here as it is generic enough to fit, but not so general it is easily confused with other people's projects.

	$(H3 Why aren't all the modules on dub?)

	dub is not really compatible with my development practices and is bolted on after-the-fact. Since dub requires so much redundant duplication and doesn't benefit me in general, I just haven't done the tedious busy work of filling in its forms for everything.

	I generally accept pull requests though if you want to add one. Use the other subpackages as a template.

	$(H3 Why no arsd/ or source/arsd subdirectories?)

	The repo is $(I already) such a directory. Adding a second one is just a pointless complication. Similarly, the whole directory is source, no need to be redundant, and being redundant actually harms usability.

	If you were to git clone to some directory, all the files here will be placed in their own directory automatically. If you then passed that parent directory as an argument to `dmd -I`, the files in here are found and can be used automatically. You can even clone other repos that use this same layout in there and have all these libraries available, with no complicated setup or build system.

	If I had my way, ALL D projects would use this layout. It makes optional dependencies just work at no cost, C libraries are automatically linked in (thanks to `pragma(lib)`) as-needed, and there's no configuration required.

	$(CONSOLE
		$ mkdir libs
		$ cd libs
		$ git clone git://arsd
		$ git clone git://whatever_else
		$ dmd -i -I/path/to/libs anything.d # just works! On my computer, I aliased this to `dmdi`
	)

	That's the way I do things on my computer and it works beautifully. Any change now would break that flow without benefiting me at all.

	$(H3 Why are there mixes of spaces and tabs in the code?)

	I use tabs myself, but you can find several parts in the repo with spaces because I do not reject contributions over trivial style differences.

	If I edit contributed code after merging it, I usually keep using the same style as the rest of that function, but sometimes my code editor automatically inserts something else. I don't really care.
+/
module arsd.docs.dev_philosophy;
