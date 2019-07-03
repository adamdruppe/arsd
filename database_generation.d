/++
	Helper functions for generating database stuff.

	Note: this is heavily biased toward Postgres
+/
module arsd.database_generation;

/*
	Let's put indexes in there too and make index functions be the preferred way of doing a query
	by making them convenient af.
*/

private enum UDA;

@UDA struct PrimaryKey {
	string sql;
}

@UDA struct Default {
	string sql;
}

@UDA struct Unique { }

@UDA struct ForeignKey(alias toWhat, string behavior) {}

enum CASCADE = "ON UPDATE CASCADE ON DELETE CASCADE";
enum NULLIFY = "ON UPDATE CASCADE ON DELETE SET NULL";
enum RESTRICT = "ON UPDATE CASCADE ON DELETE RESTRICT";

@UDA struct DBName { string name; }

struct Nullable(T) {
	bool isNull = true;
	T value;

	void opAssign(typeof(null)) {
		isNull = true;
	}

	void opAssign(T v) {
		isNull = false;
		value = v;
	}
}

struct Timestamp {

}

struct Constraint(string sql) {}

struct Index(Fields...) {}
struct UniqueIndex(Fields...) {}

struct Serial {
	int value;
}


string generateCreateTableFor(alias O)() {
	enum tableName = toTableName(O.stringof);
	string sql = "CREATE TABLE " ~ tableName ~ " (";
	string postSql;
	bool outputtedPostSql = false;

	string afterTableSql;

	void addAfterTableSql(string s) {
		afterTableSql ~= s;
		afterTableSql ~= "\n";
	}

	void addPostSql(string s) {
		if(outputtedPostSql) {
			postSql ~= ",";
		}
		postSql ~= "\n";
		postSql ~= "\t" ~ s;
		outputtedPostSql = true;
	}

	bool outputted = false;
	static foreach(memberName; __traits(allMembers, O)) {{
		alias member = __traits(getMember, O, memberName);
		static if(is(typeof(member) == Constraint!constraintSql, string constraintSql)) {
			if(outputted) {
				sql ~= ",";
			}
			sql ~= "\n";
			sql ~= "\tCONSTRAINT " ~ memberName;
			sql ~= " ";
			sql ~= constraintSql;
			outputted = true;
		} else static if(is(typeof(member) == Index!Fields, Fields...)) {
			string fields = "";
			foreach(field; Fields) {
				if(fields.length)
					fields ~= ", ";
				fields ~= __traits(identifier, field);
			}
			addAfterTableSql("CREATE INDEX " ~ memberName ~ " ON " ~ tableName ~ "("~fields~")");
		} else static if(is(typeof(member) == UniqueIndex!Fields, Fields...)) {
			string fields = "";
			static foreach(field; Fields) {
				if(fields.length)
					fields ~= ", ";
				fields ~= __traits(identifier, field);
			}
			addAfterTableSql("CREATE UNIQUE INDEX " ~ memberName ~ " ON " ~ tableName ~ "("~fields~")");
		} else static if(is(typeof(member) T)) {
			if(outputted) {
				sql ~= ",";
			}
			sql ~= "\n";
			sql ~= "\t" ~ memberName;

			static if(is(T == Nullable!P, P)) {
				static if(is(P == int))
					sql ~= " INTEGER NULL";
				else static if(is(P == string))
					sql ~= " TEXT NULL";
				else static if(is(P == double))
					sql ~= " FLOAT NULL";
				else static if(is(P == Timestamp))
					sql ~= " TIMESTAMPTZ NULL";
				else static assert(0, P.stringof);
			} else static if(is(T == int))
				sql ~= " INTEGER NOT NULL";
			else static if(is(T == Serial))
				sql ~= " SERIAL"; // FIXME postgresism
			else static if(is(T == string))
				sql ~= " TEXT NOT NULL";
			else static if(is(T == double))
				sql ~= " FLOAT NOT NULL";
			else static if(is(T == bool))
				sql ~= " BOOLEAN NOT NULL";
			else static if(is(T == Timestamp))
				sql ~= " TIMESTAMPTZ NOT NULL"; // FIXME: postgresism
			else static if(is(T == enum))
				sql ~= " INTEGER NOT NULL"; // potentially crap but meh

			static foreach(attr; __traits(getAttributes, member)) {
				static if(is(typeof(attr) == Default)) {
					sql ~= " DEFAULT " ~ attr.sql;
				} else static if(is(attr == Unique)) {
					sql ~= " UNIQUE";
				} else static if(is(attr == PrimaryKey)) {
					addPostSql("PRIMARY KEY(" ~ memberName ~ ")");
				} else static if(is(attr == ForeignKey!(to, sqlPolicy), alias to, string sqlPolicy)) {
					string refTable = toTableName(__traits(parent, to).stringof);
					string refField = to.stringof;
					addPostSql("FOREIGN KEY(" ~ memberName ~ ") REFERENCES "~refTable~"("~refField~(sqlPolicy.length ? ") " : ")") ~ sqlPolicy);
				}
			}

			outputted = true;
		}
	}}

	if(postSql.length && outputted)
		sql ~= ",\n";

	sql ~= postSql;
	sql ~= "\n);\n";
	sql ~= afterTableSql;

	return sql;
}

string toTableName(string t) {
	return plural(50, beautify(t, '_', true));
}

// copy/pasted from english.d
private string plural(int count, string word, string pluralWord = null) {
	if(count == 1 || word.length == 0)
		return word; // it isn't actually plural

	if(pluralWord !is null)
		return pluralWord;

	switch(word[$ - 1]) {
		case 's':
			return word ~ "es";
		case 'f':
			return word[0 .. $-1] ~ "ves";
		case 'y':
			return word[0 .. $-1] ~ "ies";
		case 'a', 'e', 'i', 'o', 'u':
		default:
			return word ~ "s";
	}
}

// copy/pasted from cgi
private string beautify(string name, char space = ' ', bool allLowerCase = false) {
	if(name == "id")
		return allLowerCase ? name : "ID";

	char[160] buffer;
	int bufferIndex = 0;
	bool shouldCap = true;
	bool shouldSpace;
	bool lastWasCap;
	foreach(idx, char ch; name) {
		if(bufferIndex == buffer.length) return name; // out of space, just give up, not that important

		if((ch >= 'A' && ch <= 'Z') || ch == '_') {
			if(lastWasCap) {
				// two caps in a row, don't change. Prolly acronym.
			} else {
				if(idx)
					shouldSpace = true; // new word, add space
			}

			lastWasCap = true;
		} else {
			lastWasCap = false;
		}

		if(shouldSpace) {
			buffer[bufferIndex++] = space;
			if(bufferIndex == buffer.length) return name; // out of space, just give up, not that important
			shouldSpace = false;
		}
		if(shouldCap) {
			if(ch >= 'a' && ch <= 'z')
				ch -= 32;
			shouldCap = false;
		}
		if(allLowerCase && ch >= 'A' && ch <= 'Z')
			ch += 32;
		buffer[bufferIndex++] = ch;
	}
	return buffer[0 .. bufferIndex].idup;
}

import arsd.database;
void save(O)(ref O t, Database db) {
	auto builder = new InsertBuilder;
	builder.setTable(toTableName(O.stringof));

	static foreach(memberName; __traits(allMembers, O)) {{
		alias member = __traits(getMember, O, memberName);
		static if(is(typeof(member) T)) {

			static if(is(T == Nullable!P, P)) {
				auto v = __traits(getMember, t, memberName);
				if(v.isNull)
					builder.addFieldWithSql(memberName, "NULL");
				else
					builder.addVariable(memberName, v.value);
			} else static if(is(T == int))
				builder.addVariable(memberName, __traits(getMember, t, memberName));
			else static if(is(T == Serial))
				{} // skip, let it auto-fill
			else static if(is(T == string))
				builder.addVariable(memberName, __traits(getMember, t, memberName));
			else static if(is(T == double))
				builder.addVariable(memberName, __traits(getMember, t, memberName));
			else static if(is(T == bool))
				builder.addVariable(memberName, __traits(getMember, t, memberName));
			else static if(is(T == Timestamp))
				{} // skipping... for now at least
			else static if(is(T == enum))
				builder.addVariable(memberName, cast(int) __traits(getMember, t, memberName));
		}
	}}

	import std.conv;
	foreach(row; builder.execute(db, "RETURNING id")) // FIXME: postgres-ism
		t.id.value = to!int(row[0]);
}

class RecordNotFoundException : Exception {
	this() { super("RecordNotFoundException"); }
}

/++
	Returns a given struct populated from the database. Assumes types known to this module.
+/
T find(T)(Database db, int id) {
	import std.conv;
	foreach(record; db.query("SELECT * FROM " ~ toTableName(T.stringof) ~ " WHERE id = ?", id)) {
	T t;
	foreach(field, value; record) {
		sw: switch(field) {
			static foreach(memberName; __traits(allMembers, T)) {
				case memberName:
					static if(is(typeof(__traits(getMember, T, memberName)))) {
						typeof(__traits(getMember, t, memberName)) val;
						alias V = typeof(val);

						static if(is(V == Constraint!constraintSql, string constraintSql)) {

						} else static if(is(V == Nullable!P, P)) {
							// FIXME
							if(value.length) {
								val.isNull = false;
								val.value = to!P(value);
							}
						} else static if(is(V == int) || is(V == string) || is(V == bool) || is(V == double)) {
							val = to!V(value);
						} else static if(is(V == enum)) {
							val = cast(V) to!int(value);
						} else static if(is(T == Timestamp)) {
							// FIXME
						} else static if(is(V == Serial)) {
							val.value = to!int(value);
						}

						__traits(getMember, t, memberName) = val;
					}
				break sw;
			}
			default:
				// intentionally blank
		}
	}
	return t;
	// if there is ever a second record, that's a wtf, but meh.
	}
	throw new RecordNotFoundException();
}
