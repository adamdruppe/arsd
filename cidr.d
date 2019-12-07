/// Some helper functions for using CIDR format network ranges.
module arsd.cidr;

///
uint addressToUint(string address) {
	import std.algorithm.iteration, std.conv;

	uint result;
	int place = 3;
	foreach(part; splitter(address, ".")) {
		assert(place >= 0);
		result |= to!int(part) << (place * 8);
		place--;
	}

	return result;
}

///
string uintToAddress(uint addr) {
	import std.conv;
	string res;
	res ~= to!string(addr >> 24);
	res ~= ".";
	res ~= to!string((addr >> 16) & 0xff);
	res ~= ".";
	res ~= to!string((addr >> 8) & 0xff);
	res ~= ".";
	res ~= to!string((addr >> 0) & 0xff);

	return res;
}

///
struct IPv4Block {
	this(string cidr) {
		import std.algorithm.searching, std.conv;
		auto parts = findSplit(cidr, "/");
		this.currentAddress = addressToUint(parts[0]);
		auto count = to!int(parts[2]);

		if(count != 0) {
			this.netmask = ((1L << count) - 1) & 0xffffffff;
			this.netmask <<= 32-count;
		}

		this.startingAddress = this.currentAddress & this.netmask;

		validate();

		restart();
	}

	this(string address, string netmask) {
		this.currentAddress = addressToUint(address);
		this.netmask = addressToUint(netmask);
		this.startingAddress = this.currentAddress & this.netmask;

		validate();

		restart();
	}

	void validate() {
		if(!isValid())
			throw new Exception("invalid");
	}

	bool isValid() {
		return (startingAddress & netmask) == (currentAddress & netmask);
	}

	void restart() {
		remaining = ~this.netmask - (currentAddress - startingAddress);
	}

	@property string front() {
		return uintToAddress(currentAddress);
	}

	@property bool empty() {
		return remaining < 0;
	}

	void popFront() {
		currentAddress++;
		remaining--;
	}

	string toString() {
		import std.conv;
		return uintToAddress(startingAddress) ~ "/" ~ to!string(maskBits);
	}

	int maskBits() {
		import core.bitop;
		if(netmask == 0)
			return 0;
		return 32-bsf(netmask);
	}

	int numberOfAddresses() {
		return ~netmask + 1;
	}

	uint startingAddress;
	uint netmask;

	uint currentAddress;
	int remaining;
}

version(none)
void main() {
	// make one with cidr or address + mask notation

	// auto i = IPv4Block("192.168.1.0", "255.255.255.0");
	auto i = IPv4Block("192.168.1.50/29");

	// loop over all addresses in the block
	import std.stdio;
	foreach(addr; i)
		writeln(addr);

	// show info about the block too
	writefln("%s netmask %s", uintToAddress(i.startingAddress), uintToAddress(i.netmask));
	writeln(i);
	writeln(i.numberOfAddresses, " addresses in block");
}
