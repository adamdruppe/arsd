module arsd.file;

import arsd.core;

// file name stuff
alias FilePath = arsd.core.FilePath;

// the basics
alias writeFile = arsd.core.writeFile;
alias readTextFile = arsd.core.readTextFile;
alias readBinaryFile = arsd.core.readBinaryFile;

// read lines

// directory listing
alias getFiles = arsd.core.getFiles;
alias DirectoryWatcher = arsd.core.DirectoryWatcher;
// stat?
// exists?
// symlink?
// remove?
// rename?
// copy?

// file objects
// alias AsyncFile = arsd.core.AsyncFile;

/+
unittest {
	writeFile("sample.txt", "this is a test file");
	assert(readTextFile("sample.txt") == "this is a test file");
}
+/
