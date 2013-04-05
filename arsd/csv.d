module arsd.csv;

import std.string;
import std.array;

string[][] readCsv(string data) {
	data = data.replace("\r", "");

	auto idx = data.indexOf("\n");
	//data = data[idx + 1 .. $]; // skip headers

	string[] fields;
	string[][] records;

	string[] current;

	int state = 0;
	string field;
	foreach(c; data) {
		tryit: switch(state) {
			default: assert(0);
			case 0: // normal
				if(c == '"')
					state = 1;
				else if(c == ',') {
					// commit field
					current ~= field;
					field = null;
				} else if(c == '\n') {
					// commit record
					current ~= field;

					records ~= current;
					current = null;
					field = null;
				} else
					field ~= c;
			break;
			case 1: // in quote
				if(c == '"')
					state = 2;
				else
					field ~= c;
			break;
			case 2: // is it a closing quote or an escaped one?
				if(c == '"') {
					field ~= c;
					state = 1;
				} else {
					state = 0;
					goto tryit;
				}
		}
	}


	return records;
}
