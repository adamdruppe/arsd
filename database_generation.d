/++
	Helper functions for generating database stuff.

	Note: this is heavily biased toward Postgres
+/
module arsd.database_generation;

/*

	FIXME: support partial indexes and maybe "using"
	FIXME: support views

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

@UDA struct ForeignKey(alias toWhat, string behavior) {
	alias ReferencedTable = __traits(parent, toWhat);
}

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

	T toArsdJsvar() { return value; }
}

struct Timestamp {
	string value;
	string toArsdJsvar() { return value; }

	// FIXME: timezone
	static Timestamp fromStrings(string date, string time) {
	        if(time.length < 6)
			time ~= ":00";
		import std.datetime;
		return Timestamp(SysTime.fromISOExtString(date ~ "T" ~ time).toISOExtString());
	}
}

SysTime parseDbTimestamp(string s) {
	if(s.length == 0) return SysTime.init;
	auto date = s[0 .. 10];
	auto time = s[11 .. 20];
	auto tz = s[20 .. $];
	return SysTime.fromISOExtString(date ~ "T" ~ time ~ tz);
}

struct Constraint(string sql) {}

struct Index(Fields...) {}
struct UniqueIndex(Fields...) {}

struct Serial {
	int value;
	int toArsdJsvar() { return value; }
	int getValue() { return value; }
	alias getValue this;
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
		version(dbgenerate_sqlite) {} else { // FIXME: make it work here too, it is the specifics of the constraint strings
			if(outputted) {
				sql ~= ",";
			}
			sql ~= "\n";
			sql ~= "\tCONSTRAINT " ~ memberName;
			sql ~= " ";
			sql ~= constraintSql;
			outputted = true;
		}
		} else static if(is(typeof(member) == Index!Fields, Fields...)) {
			string fields = "";
			static foreach(field; Fields) {
				if(fields.length)
					fields ~= ", ";
				fields ~= __traits(identifier, field);
			}
			addAfterTableSql("CREATE INDEX " ~ tableName ~ "_" ~ memberName ~ " ON " ~ tableName ~ "("~fields~")");
		} else static if(is(typeof(member) == UniqueIndex!Fields, Fields...)) {
			string fields = "";
			static foreach(field; Fields) {
				if(fields.length)
					fields ~= ", ";
				fields ~= __traits(identifier, field);
			}
			addAfterTableSql("CREATE UNIQUE INDEX " ~ tableName ~ "_" ~ memberName ~ " ON " ~ tableName ~ "("~fields~")");
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
			else static if(is(T == Serial)) {
				version(dbgenerate_sqlite)
					sql ~= " INTEGER PRIMARY KEY AUTOINCREMENT";
				else
					sql ~= " SERIAL"; // FIXME postgresism
			} else static if(is(T == string))
				sql ~= " TEXT NOT NULL";
			else static if(is(T == double))
				sql ~= " FLOAT NOT NULL";
			else static if(is(T == bool))
				sql ~= " BOOLEAN NOT NULL";
			else static if(is(T == Timestamp)) {
				version(dbgenerate_sqlite)
					sql ~= " TEXT NOT NULL";
				else
					sql ~= " TIMESTAMPTZ NOT NULL"; // FIXME: postgresism
			} else static if(is(T == enum))
				sql ~= " INTEGER NOT NULL"; // potentially crap but meh

			static foreach(attr; __traits(getAttributes, member)) {
				static if(is(typeof(attr) == Default)) {
					// FIXME: postgresism there, try current_timestamp in sqlite
					version(dbgenerate_sqlite) {
						import std.string;
						sql ~= " DEFAULT " ~ std.string.replace(attr.sql, "now()", "current_timestamp");
					} else
						sql ~= " DEFAULT " ~ attr.sql;
				} else static if(is(attr == Unique)) {
					sql ~= " UNIQUE";
				} else static if(is(attr == PrimaryKey)) {
					version(dbgenerate_sqlite) {
						static if(is(T == Serial)) {} // skip, it is done above
						else
						addPostSql("PRIMARY KEY(" ~ memberName ~ ")");
					} else
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
/++

+/
void save(O)(ref O t, Database db) {
	t.insert(db);
}

/++

+/
void insert(O)(ref O t, Database db) {
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
			else static if(is(T == Serial)) {
				auto v = __traits(getMember, t, memberName).value;
				if(v) {
					builder.addVariable(memberName, v);
				} else {
					// skip and let it auto-fill
				}
			} else static if(is(T == string)) {
				builder.addVariable(memberName, __traits(getMember, t, memberName));
			} else static if(is(T == double))
				builder.addVariable(memberName, __traits(getMember, t, memberName));
			else static if(is(T == bool))
				builder.addVariable(memberName, __traits(getMember, t, memberName));
			else static if(is(T == Timestamp)) {
				auto v = __traits(getMember, t, memberName).value;
				if(v.length)
					builder.addVariable(memberName, v);
			} else static if(is(T == enum))
				builder.addVariable(memberName, cast(int) __traits(getMember, t, memberName));
		}
	}}

	import std.conv;
	version(dbgenerate_sqlite) {
		builder.execute(db);
		foreach(row; db.query("SELECT max(id) FROM " ~ toTableName(O.stringof)))
			t.id.value = to!int(row[0]);
	} else {
		foreach(row; builder.execute(db, "RETURNING id")) // FIXME: postgres-ism
			t.id.value = to!int(row[0]);
	}
}

///
class RecordNotFoundException : Exception {
	this() { super("RecordNotFoundException"); }
}

/++
	Returns a given struct populated from the database. Assumes types known to this module.

	MyItem item = db.find!(MyItem.id)(3);

	If you just give a type, it assumes the relevant index is "id".

+/
auto find(alias T)(Database db, int id) {

	// FIXME: if T is an index, search by it.
	// if it is unique, return an individual item.
	// if not, return the array

	foreach(record; db.query("SELECT * FROM " ~ toTableName(T.stringof) ~ " WHERE id = ?", id)) {
		T t;
		populateFromDbRow(t, record);

		return t;
		// if there is ever a second record, that's a wtf, but meh.
	}
	throw new RecordNotFoundException();
}

private void populateFromDbRow(T)(ref T t, Row record) {
	foreach(field, value; record) {
		sw: switch(field) {
			static foreach(memberName; __traits(allMembers, T)) {
				case memberName:
					static if(is(typeof(__traits(getMember, T, memberName)))) {
						populateFromDbVal(__traits(getMember, t, memberName), value);
					}
				break sw;
			}
			default:
				// intentionally blank
		}
	}
}

private void populateFromDbVal(V)(ref V val, string value) {
	import std.conv;
	static if(is(V == Constraint!constraintSql, string constraintSql)) {

	} else static if(is(V == Nullable!P, P)) {
		// FIXME
		if(value.length && value != "null") {
			val.isNull = false;
			val.value = to!P(value);
		}
	} else static if(is(V == bool)) {
		val = value == "t" || value == "1" || value == "true";
	} else static if(is(V == int) || is(V == string) || is(V == double)) {
		val = to!V(value);
	} else static if(is(V == enum)) {
		val = cast(V) to!int(value);
	} else static if(is(V == Timestamp)) {
		val.value = value;
	} else static if(is(V == Serial)) {
		val.value = to!int(value);
	}
}

/++
	Gets all the children of that type. Specifically, it looks in T for a ForeignKey referencing B and queries on that.

	To do a join through a many-to-many relationship, you could get the children of the join table, then get the children of that...
	Or better yet, use real sql. This is more intended to get info where there is one parent row and then many child
	rows, not for a combined thing.
+/
QueryBuilderHelper!(T[]) children(T, B)(B base) {
	int countOfAssociations() {
		int count = 0;
		static foreach(memberName; __traits(allMembers, T))
		static foreach(attr; __traits(getAttributes, __traits(getMember, T, memberName))) {{
			static if(is(attr == ForeignKey!(K, policy), alias K, string policy)) {
				static if(is(attr.ReferencedTable == B))
					count++;
			}
		}}
		return count;
	}
	static assert(countOfAssociations() == 1, T.stringof ~ " does not have exactly one foreign key of type " ~ B.stringof);
	string keyName() {
		static foreach(memberName; __traits(allMembers, T))
		static foreach(attr; __traits(getAttributes, __traits(getMember, T, memberName))) {{
			static if(is(attr == ForeignKey!(K, policy), alias K, string policy)) {
				static if(is(attr.ReferencedTable == B))
					return memberName;
			}
		}}
	}

	return QueryBuilderHelper!(T[])(toTableName(T.stringof)).where!(mixin(keyName ~ " => base.id"));
}

/++
	Finds the single row associated with a foreign key in `base`.

	`T` is used to find the key, unless ambiguous, in which case you must pass `key`.

	To do a join through a many-to-many relationship, go to [children] or use real sql.
+/
T associated(B, T, string key = null)(B base, Database db) {
	int countOfAssociations() {
		int count = 0;
		static foreach(memberName; __traits(allMembers, B))
		static foreach(attr; __traits(getAttributes, __traits(getMember, B, memberName))) {
			static if(is(attr == ForeignKey!(K, policy), alias K, string policy)) {
				static if(is(attr.ReferencedTable == T))
					static if(key is null || key == memberName)
						count++;
			}
		}
		return count;
	}

	static if(key is null) {
		enum coa = countOfAssociations();
		static assert(coa != 0, B.stringof ~ " has no association of type " ~ T);
		static assert(coa == 1, B.stringof ~ " has multiple associations of type " ~ T ~ "; please specify the key you want");
		static foreach(memberName; __traits(allMembers, B))
		static foreach(attr; __traits(getAttributes, __traits(getMember, B, memberName))) {
			static if(is(attr == ForeignKey!(K, policy), alias K, string policy)) {
				static if(is(attr.ReferencedTable == T))
					return db.find!T(__traits(getMember, base, memberName));
			}
		}
	} else {
		static assert(countOfAssociations() == 1, B.stringof ~ " does not have a key named " ~ key ~ " of type " ~ T);
		static foreach(attr; __traits(getAttributes, __traits(getMember, B, memberName))) {
			static if(is(attr == ForeignKey!(K, policy), alias K, string policy)) {
				static if(is(attr.ReferencedTable == T)) {
					return db.find!T(__traits(getMember, base, key));
				}
			}
		}
		assert(0);
	}
}


/++
	It will return an aggregate row with a member of type of each table in the join.

	Could do an anonymous object for other things in the sql...
+/
auto join(TableA, TableB, ThroughTable = void)() {}

/++

+/
struct QueryBuilderHelper(T) {
	static if(is(T == R[], R))
		alias TType = R;
	else
		alias TType = T;

	SelectBuilder selectBuilder;

	this(string tableName) {
		selectBuilder = new SelectBuilder();
		selectBuilder.table = tableName;
		selectBuilder.fields = ["*"];
	}

	T execute(Database db) {
		selectBuilder.db = db;
		static if(is(T == R[], R)) {

		} else {
			selectBuilder.limit = 1;
		}

		T ret;
		bool first = true;
		foreach(row; db.query(selectBuilder.toString())) {
			TType t;
			populateFromDbRow(t, row);

			static if(is(T == R[], R))
				ret ~= t;
			else {
				if(first) {
					ret = t;
					first = false;
				} else {
					assert(0);
				}
			}
		}
		return ret;
	}

	///
	typeof(this) orderBy(string criterion)() {
		string name() {
			int idx = 0;
			while(idx < criterion.length && criterion[idx] != ' ')
				idx++;
			return criterion[0 .. idx];
		}

		string direction() {
			int idx = 0;
			while(idx < criterion.length && criterion[idx] != ' ')
				idx++;
			import std.string;
			return criterion[idx .. $].strip;
		}

		static assert(is(typeof(__traits(getMember, TType, name()))), TType.stringof ~ " has no field " ~ name());
		static assert(direction().length == 0 || direction() == "ASC" || direction() == "DESC", "sort direction must be empty, ASC, or DESC");

		selectBuilder.orderBys ~= criterion;
		return this;
	}
}

QueryBuilderHelper!(T[]) from(T)() {
	return QueryBuilderHelper!(T[])(toTableName(T.stringof));
}

/// ditto
template where(conditions...) {
	Qbh where(Qbh)(Qbh this_, string[] sqlCondition...) {
		assert(this_.selectBuilder !is null);

		static string extractName(string s) {
			if(s.length == 0) assert(0);
			auto i = s.length - 1;
			while(i) {
				if(s[i] == ')') {
					// got to close paren, now backward to non-identifier char to get name
					auto end = i;
					while(i) {
						if(s[i] == ' ')
							return s[i + 1 .. end];
						i--;
					}
					assert(0);
				}
				i--;
			}
			assert(0);
		}

		static foreach(idx, cond; conditions) {{
			// I hate this but __parameters doesn't work here for some reason
			// see my old thread: https://forum.dlang.org/post/awjuoemsnmxbfgzhgkgx@forum.dlang.org
			enum name = extractName(typeof(cond!int).stringof);
			auto value = cond(null);

			// FIXME: convert the value as necessary
			static if(is(typeof(value) == Serial))
				auto dbvalue = value.value;
			else static if(is(typeof(value) == enum))
				auto dbvalue = cast(int) value;
			else
				auto dbvalue = value;

			import std.conv;

			static assert(is(typeof(__traits(getMember, Qbh.TType, name))), Qbh.TType.stringof ~ " has no member " ~ name);
			static if(is(typeof(__traits(getMember, Qbh.TType, name)) == int)) {
				static if(is(typeof(value) : const(int)[])) {
					string s;
					foreach(v; value) {
						if(s.length) s ~= ", ";
						s ~= to!string(v);
					}
					this_.selectBuilder.wheres ~= name ~ " IN (" ~ s ~ ")";
				} else {
					static assert(is(typeof(value) : const(int)) || is(typeof(value) == Serial), Qbh.TType.stringof ~ " is a integer key, but you passed an incompatible " ~ typeof(value).stringof);

					auto placeholder = "?_internal" ~ to!string(idx);
					this_.selectBuilder.wheres ~= name ~ " = " ~ placeholder;
					this_.selectBuilder.setVariable(placeholder, dbvalue);
				}
			} else static if(is(typeof(__traits(getMember, Qbh.TType, name)) == Nullable!int)) {
				static if(is(typeof(value) : const(int)[])) {
					string s;
					foreach(v; value) {
						if(s.length) s ~= ", ";
						s ~= to!string(v);
					}
					this_.selectBuilder.wheres ~= name ~ " IN (" ~ s ~ ")";
				} else {
					static assert(is(typeof(value) : const(int)) || is(typeof(value) == Serial), Qbh.TType.stringof ~ " is a integer key, but you passed an incompatible " ~ typeof(value).stringof);

					auto placeholder = "?_internal" ~ to!string(idx);
					this_.selectBuilder.wheres ~= name ~ " = " ~ placeholder;
					this_.selectBuilder.setVariable(placeholder, dbvalue);
				}
			} else static if(is(typeof(__traits(getMember, Qbh.TType, name)) == Serial)) {
				static if(is(typeof(value) : const(int)[])) {
					string s;
					foreach(v; value) {
						if(s.length) s ~= ", ";
						s ~= to!string(v);
					}
					this_.selectBuilder.wheres ~= name ~ " IN (" ~ s ~ ")";
				} else {
					static assert(is(typeof(value) : const(int)) || is(typeof(value) == Serial), Qbh.TType.stringof ~ " is a integer key, but you passed an incompatible " ~ typeof(value).stringof);

					auto placeholder = "?_internal" ~ to!string(idx);
					this_.selectBuilder.wheres ~= name ~ " = " ~ placeholder;
					this_.selectBuilder.setVariable(placeholder, dbvalue);
				}


			} else {
				static assert(is(typeof(__traits(getMember, Qbh.TType, name)) == typeof(value)), Qbh.TType.stringof ~ "." ~ name ~ " is not of type " ~ typeof(value).stringof);

				auto placeholder = "?_internal" ~ to!string(idx);
				this_.selectBuilder.wheres ~= name ~ " = " ~ placeholder;
				this_.selectBuilder.setVariable(placeholder, dbvalue);
			}
		}}

		this_.selectBuilder.wheres ~= sqlCondition;
		return this_;
	}
}
