/++

+/
module arsd.uda;

/++

+/
Blueprint extractUdas(Blueprint, Udas...)(Blueprint defaults) {
	foreach(alias uda; Udas) {
		static if(is(typeof(uda) == Blueprint)) {
			defaults = uda;
		} else {
			foreach(ref member; defaults.tupleof)
				static if(is(typeof(member) == typeof(uda)))
					member = uda;
		}
	}

	return defaults;
}

unittest {
	import core.attribute;
	static struct Name {
		@implicit this(string name) { this.name = name; }
		string name;
	}

	static struct Priority {
		@implicit this(int priority) { this.priority = priority; }
		int priority;
	}

	static struct Blueprint {
		Name name;
		Priority priority;
	}

	static class A {
		@Name("a") int a;
		@Priority(44) int b;
		int c;
		@Priority(33) @Name("d") int d;
		// @(wtf => wtf) int e; // won't compile when trying to get the blueprint...

		@Blueprint(name: "foo", priority: 44) int g;
	}

	auto bp2 = Blueprint(name: "foo", priority: 44);

	foreach(memberName; __traits(derivedMembers, A)) {
		alias member = __traits(getMember, A, memberName);
		auto bp = extractUdas!(Blueprint, __traits(getAttributes, member))(Blueprint.init);
		import std.stdio; writeln(memberName, " ", bp);
	}
}
