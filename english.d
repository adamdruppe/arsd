module arsd.english;

string plural(int count, string word, string pluralWord = null) {
	if(count == 1 || word.length == 0)
		return word; // it isn't actually plural

	if(pluralWord !is null)
		return pluralWord;

	switch(word[$ - 1]) {
		case 's':
		case 'a', 'e', 'i', 'o', 'u':
			return word ~ "es";
		case 'f':
			return word[0 .. $-1] ~ "ves";
		case 'y':
			return word[0 .. $-1] ~ "ies";
		default:
			return word ~ "s";
	}
}

string numberToEnglish(long number) {
	string word;
	if(number == 0)
		return "zero";

	if(number < 0) {
		word = "negative";
		number = -number;
	}

	while(number) {
		if(number < 100) {
			if(number < singleWords.length) {
				word ~= singleWords[cast(int) number];
				break;
			} else {
				auto tens = number / 10;
				word ~= tensPlaceWords[cast(int) tens];
				number = number % 10;
				if(number)
					word ~= "-";
			}
		} else if(number < 1000) {
			auto hundreds = number / 100;
			word ~= onesPlaceWords[cast(int) hundreds] ~ " hundred";
			number = number % 100;
			if(number)
				word ~= " and ";
		} else if(number < 1000000) {
			auto thousands = number / 1000;
			word ~= numberToEnglish(thousands) ~ " thousand";
			number = number % 1000;
			if(number)
				word ~= ", ";
		} else if(number < 1_000_000_000) {
			auto millions = number / 1000000;
			word ~= numberToEnglish(millions) ~ " million";
			number = number % 1000000;
			if(number)
				word ~= ", ";
		} else if(number < 1_000_000_000_000) {
			auto n = number / 1000000000;
			word ~= numberToEnglish(n) ~ " billion";
			number = number % 1000000000;
			if(number)
				word ~= ", ";
		} else if(number < 1_000_000_000_000_000) {
			auto n = number / 1000000000000;
			word ~= numberToEnglish(n) ~ " trillion";
			number = number % 1000000000000;
			if(number)
				word ~= ", ";
		} else {
			import std.conv;
			return to!string(number);
		}
	}

	return word;
}

unittest {
	assert(numberToEnglish(1) == "one");
	assert(numberToEnglish(5) == "five");
	assert(numberToEnglish(13) == "thirteen");
	assert(numberToEnglish(54) == "fifty-four");
	assert(numberToEnglish(178) == "one hundred and seventy-eight");
	assert(numberToEnglish(592) == "five hundred and ninety-two");
	assert(numberToEnglish(1234) == "one thousand, two hundred and thirty-four");
	assert(numberToEnglish(10234) == "ten thousand, two hundred and thirty-four");
	assert(numberToEnglish(105234) == "one hundred and five thousand, two hundred and thirty-four");
}

enum onesPlaceWords = [
	"zero",
	"one",
	"two",
	"three",
	"four",
	"five",
	"six",
	"seven",
	"eight",
	"nine",
];

enum singleWords = onesPlaceWords ~ [
	"ten",
	"eleven",
	"twelve",
	"thirteen",
	"fourteen",
	"fifteen",
	"sixteen",
	"seventeen",
	"eighteen",
	"nineteen",
];

enum tensPlaceWords = [
	null,
	"ten",
	"twenty",
	"thirty",
	"forty",
	"fifty",
	"sixty",
	"seventy",
	"eighty",
	"ninety",
];

/*
void main() {
	import std.stdio;
	foreach(i; 3433000 ..3433325)
	writeln(numberToEnglish(i));
}
*/
