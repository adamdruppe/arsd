/++
	Generic interface for RDBMS access. Use with one of the implementations in [arsd.mysql], [arsd.sqlite], [arsd.postgres], or [arsd.mssql]. I'm sorry the docs are not good, but a little bit goes a long way:

	---
	auto db = new Sqlite("file.db"); // see the implementations for constructors
	// then the interface, for any impl can be as simple as:

	foreach(row; db.query("SELECT id, name FROM people")) {
             string id = row[0];
	     string name = row[1];
	}

	db.query("INSERT INTO people (id, name) VALUES (?, ?)", 5, "Adam");
	---

	To convert to other types, just use [std.conv.to] since everything comes out of this as simple strings with the exception of binary data,
	which you'll want to cast to const(ubyte)[].

	History:
		Originally written prior to 2011.

		On August 2, 2022, the behavior of BLOB (or BYTEA in postgres) changed significantly.
		Before, it would convert to strings with `to!string(bytes)` on insert and platform specific
		on query. It didn't really work at all.

		It now actually stores ubyte[] as a blob and retrieves it without modification. Note you need to
		cast it.

		This is potentially breaking, but since it didn't work much before I doubt anyone was using it successfully
		but this might be a problem. I advise you to retest.

		Be aware I don't like this string interface much anymore and want to change it significantly but idk
		how to work it in without breaking a decade of code.

		On June 7, 2023 (dub 11.0), I started the process of moving away from strings as the inner storage unit. This is a potentially breaking change, but you can use `.toString` to convert as needed and `alias this` will try to do this automatically in many situations. See [DatabaseDatum] for details. This transition is not yet complete.

		Notably, passing it to some std.string functions will cause errors referencing DatabaseDatum like:

		$(CONSOLE
		Error: template `std.array.replace` cannot deduce function from argument types `!()(string, string, DatabaseDatum)`
		path/phobos/std/array.d(2459):        Candidates are: `replace(E, R1, R2)(E[] subject, R1 from, R2 to)`
		  with `E = immutable(char),
		       R1 = string,
		       R2 = DatabaseDatum`
		)

		Because templates do not trigger alias this - you will need to call `.toString()` yourself at the usage site.
+/
module arsd.database;

// FIXME: add some kind of connection pool thing we can easily use

// I should do a prepared statement as a template string arg

public import std.variant;
import std.string;
public import std.datetime;

static import arsd.core;
private import arsd.core : LimitedVariant;

/*
	Database 2.0 plan, WIP:

	// Do I want to do some kind of RAII?
	auto database = Database(new MySql("connection info"));

	* Prepared statement support
	* Queries with separate args whenever we can with consistent interface
	* Query returns some typed info when we can.
	* ....?


	PreparedStatement prepareStatement(string sql);

	Might be worth looking at doing the preparations in static ctors
	so they are always done once per program...
*/

///
interface Database {
	/// Actually implements the query for the database. The query() method
	/// below might be easier to use.
	ResultSet queryImpl(string sql, Variant[] args...);

	/// Escapes data for inclusion into an sql string literal
	string escape(string sqlData);
	/// Escapes binary data for inclusion into a sql string. Note that unlike `escape`, the returned string here SHOULD include the quotes.
	string escapeBinaryString(const(ubyte)[] sqlData);

	/// query to start a transaction, only here because sqlite is apparently different in syntax...
	void startTransaction();

	/// Just executes a query. It supports placeholders for parameters
	final ResultSet query(T...)(string sql, T t) {
		Variant[] args;
		foreach(arg; t) {
			Variant a;
			static if(__traits(compiles, a = arg))
				a = arg;
			else
				a = to!string(t);
			args ~= a;
		}
		return queryImpl(sql, args);
	}

	final ResultSet query(Args...)(arsd.core.InterpolationHeader header, Args args, arsd.core.InterpolationFooter footer) {
		import arsd.core;
		Variant[] vargs;
		string sql;
		foreach(arg; args) {
			static if(is(typeof(arg) == InterpolatedLiteral!str, string str)) {
				sql ~= str;
			} else static if(is(typeof(arg) == InterpolatedExpression!str, string str)) {
				// intentionally blank
			} else static if(is(typeof(arg) == InterpolationHeader) || is(typeof(arg) == InterpolationFooter)) {
				static assert(0, "Nested interpolations not allowed at this time");
			} else {
				sql ~= "?";
				vargs ~= Variant(arg);
			}
		}
		return queryImpl(sql, vargs);
	}

	/// turns a systime into a value understandable by the target database as a timestamp to be concated into a query. so it should be quoted and escaped etc as necessary
	string sysTimeToValue(SysTime);

	/// Prepared statement api
	/*
	PreparedStatement prepareStatement(string sql, int numberOfArguments);

	*/
}
import std.stdio;

// Added Oct 26, 2021
Row queryOneRow(string file = __FILE__, size_t line = __LINE__, T...)(Database db, string sql, T t) {
	auto res = db.query(sql, t);
	import arsd.core;
	if(res.empty)
		throw ArsdException!("no row in result")(sql, t, file, line);
	auto row = res.front;
	return row;
}

Ret queryOneColumn(Ret, string file = __FILE__, size_t line = __LINE__, T...)(Database db, string sql, T t) {
	auto row = queryOneRow(db, sql, t);
	return to!Ret(row[0]);
}

struct Query {
	ResultSet result;
	this(T...)(Database db, string sql, T t) if(T.length!=1 || !is(T[0]==Variant[])) {
		result = db.query(sql, t);
	}
    // Version for dynamic generation of args: (Needs to be a template for coexistence with other constructor.
    this(T...)(Database db, string sql, T args) if (T.length==1 && is(T[0] == Variant[])) {
        result = db.queryImpl(sql, args);
    }

	int opApply(T)(T dg) if(is(T == delegate)) {
		import std.traits;
		foreach(row; result) {
			ParameterTypeTuple!dg tuple;

			foreach(i, item; tuple) {
				tuple[i] = to!(typeof(item))(row[i]);
			}

			if(auto result = dg(tuple))
				return result;
		}

		return 0;
	}
}

/++
	Represents a single item in a result. A row is a set of these `DatabaseDatum`s.

	History:
		Added June 2, 2023 (dub v11.0). Prior to this, it would always use `string`. This has `alias toString this` to try to maintain compatibility.
+/
struct DatabaseDatum {
	int platformSpecificTag;
	LimitedVariant storage;

	/++
		These are normally constructed by the library, so you shouldn't need these constructors. If you're writing a new database implementation though, here it is.
	+/
	package this(string s) {
		storage = s;
	}

	/++
		Returns `true` if the item was `NULL` in the database.
	+/
	bool isNull() {
		return storage.contains == LimitedVariant.Contains.null_;
	}

	/++
		Converts the datum to a string in a format specified by the database.
	+/
	string toString() {
		if(isNull())
			return null;

		return storage.toString();
	}
	/++
		For compatibility with earlier versions of the api, all data can easily convert to string implicitly and opCast keeps to!x(this) working.

		The toArsdJsVar one is in particular subject to change.
	+/
	alias toString this;

	/// ditto
	T opCast(T)() {
		import std.conv;
		return to!T(this.toString);
	}

	/// ditto
	string toArsdJsVar() { return this.toString; }
}

unittest {
	// tbh this is more of a phobos test but rvaluerefparam has messed it up before
	auto db = DatabaseDatum("1234567");
	assert(to!int(db) == 1234567);
}

/++
	A row in a result set from a query.

	You can access this as either an array or associative array:

	---
		foreach(Row row; db.query("SELECT id, name FROM mytable")) {
			// can access by index or by name
			row[0] == row["id"];
			row[1] == row["name"];

			// can also iterate over the results
			foreach(name, data; row) {
				 // will send name = "id", data = the thing
				 // and then next loop will be name = "name", data = the thing
			}
		}
	---
+/
struct Row {
	package DatabaseDatum[] row;
	package ResultSet resultSet;

	/++
		Allows for access by index or column name.
	+/
	DatabaseDatum opIndex(size_t idx, string file = __FILE__, int line = __LINE__) {
		if(idx >= row.length)
			throw new Exception(text("index ", idx, " is out of bounds on result"), file, line);
		return row[idx];
	}

	/// ditto
	DatabaseDatum opIndex(string name, string file = __FILE__, int line = __LINE__) {
		auto idx = resultSet.getFieldIndex(name);
		if(idx >= row.length)
			throw new Exception(text("no field ", name, " in result"), file, line);
		return row[idx];
	}

	/++
		Provides a string representation of the row, for quick eyeball debugging. You probably won't want the format this prints in (and don't rely upon it, as it is subject to change at any time without notice!), but it might be useful for use with `writeln`.
	+/
	string toString() {
		return to!string(row);
	}

	/++
		Allows iteration over the columns with the `foreach` statement.

		History:
			Prior to June 11, 2023 (dub v11.0), the order of iteration was undefined. It is now guaranteed to be in the same order as it was returned by the database (which is determined by your original query). Additionally, prior to this date, the datum was typed `string`. `DatabaseDatum` should implicitly convert to string, so your code is unlikely to break, but if you did specify the type explicitly you may need to update your code.

			The overload with one argument, having just the datum without the name, was also added on June 11, 2023 (dub v11.0).
	+/
	int opApply(int delegate(string, DatabaseDatum) dg) {
		string[] fn = resultSet.fieldNames();
		foreach(idx, item; row)
			mixin(yield("fn[idx], item"));

		return 0;
	}

	/// ditto
	int opApply(int delegate(DatabaseDatum) dg) {
		foreach(item; row)
			mixin(yield("item"));
		return 0;
	}

	/++
		Hacky conversion to simpler types.

		I'd recommend against using these in new code. I wrote them back around 2011 as a hack for something I was doing back then. Among the downsides of these is type information loss in both functions (since strings discard the information tag) and column order loss in `toAA` (since D associative arrays do not maintain any defined order). Additionally, they to make an additional copy of the result row, which you may be able to avoid by looping over it directly.

		I may formally deprecate them in a future release.
	+/
	string[] toStringArray() {
		string[] row;
		foreach(item; this.row)
			row ~= item;
		return row;
	}

	/// ditto
	string[string] toAA() {
		string[string] a;

		string[] fn = resultSet.fieldNames();

		foreach(i, r; row)
			a[fn[i]] = r;

		return a;
	}

}
import std.conv;

interface ResultSet {
	// name for associative array to result index
	int getFieldIndex(string field);
	string[] fieldNames();

	// this is a range that can offer other ranges to access it
	bool empty() @property;
	Row front() @property;
	void popFront() ;
	size_t length() @property;

	/* deprecated */ final ResultSet byAssoc() { return this; }
}

class DatabaseException : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__) {
		super(msg, file, line);
	}
}



abstract class SqlBuilder { }

class InsertBuilder : SqlBuilder {
	private string table;
	private string[] fields;
	private string[] fieldsSetSql;
	private Variant[] values;

	///
	void setTable(string table) {
		this.table = table;
	}

	/// same as adding the arr as values one by one. assumes DB column name matches AA key.
	void addVariablesFromAssociativeArray(in string[string] arr, string[] names...) {
		foreach(name; names) {
			fields ~= name;
			if(name in arr) {
				fieldsSetSql ~= "?";
				values ~= Variant(arr[name]);
			} else {
				fieldsSetSql ~= "null";
			}
		}
	}

	///
	void addVariable(T)(string name, T value) {
		fields ~= name;
		fieldsSetSql ~= "?";
		values ~= Variant(value);
	}

	/// if you use a placeholder, be sure to [addValueForHandWrittenPlaceholder] immediately
	void addFieldWithSql(string name, string sql) {
		fields ~= name;
		fieldsSetSql ~= sql;
	}

	/// for addFieldWithSql that includes a placeholder
	void addValueForHandWrittenPlaceholder(T)(T value) {
		values ~= Variant(value);
	}

	/// executes the query
	auto execute(Database db, string supplementalSql = null) {
		return db.queryImpl(this.toSql() ~ supplementalSql, values);
	}

	string toSql() {
		string sql = "INSERT INTO\n";
		sql ~= "\t" ~ table ~ " (\n";
		foreach(idx, field; fields) {
			sql ~= "\t\t" ~ field ~ ((idx != fields.length - 1) ? ",\n" : "\n");
		}
		sql ~= "\t) VALUES (\n";
		foreach(idx, field; fieldsSetSql) {
			sql ~= "\t\t" ~ field ~ ((idx != fieldsSetSql.length - 1) ? ",\n" : "\n");
		}
		sql ~= "\t)\n";
		return sql;
	}
}

/// WARNING: this is as susceptible to SQL injections as you would be writing it out by hand
class SelectBuilder : SqlBuilder {
	string[] fields;
	string table;
	string[] joins;
	string[] wheres;
	string[] orderBys;
	string[] groupBys;

	int limit;
	int limitStart;

	Variant[string] vars;
	void setVariable(T)(string name, T value) {
		assert(name.length);
		if(name[0] == '?')
			name = name[1 .. $];
		vars[name] = Variant(value);
	}

	Database db;
	this(Database db = null) {
		this.db = db;
	}

	/*
		It would be nice to put variables right here in the builder

		?name

		will prolly be the syntax, and we'll do a Variant[string] of them.

		Anything not translated here will of course be in the ending string too
	*/

	SelectBuilder cloned() {
		auto s = new SelectBuilder(this.db);
		s.fields = this.fields.dup;
		s.table = this.table;
		s.joins = this.joins.dup;
		s.wheres = this.wheres.dup;
		s.orderBys = this.orderBys.dup;
		s.groupBys = this.groupBys.dup;
		s.limit = this.limit;
		s.limitStart = this.limitStart;

		foreach(k, v; this.vars)
			s.vars[k] = v;

		return s;
	}

	override string toString() {
		string sql = "SELECT ";

		// the fields first
		{
			bool outputted = false;
			foreach(field; fields) {
				if(outputted)
					sql ~= ", ";
				else
					outputted = true;

				sql ~= field; // "`" ~ field ~ "`";
			}
		}

		sql ~= " FROM " ~ table;

		if(joins.length) {
			foreach(join; joins)
				sql ~= " " ~ join;
		}

		if(wheres.length) {
			bool outputted = false;
			sql ~= " WHERE ";
			foreach(w; wheres) {
				if(outputted)
					sql ~= " AND ";
				else
					outputted = true;
				sql ~= "(" ~ w ~ ")";
			}
		}

		if(groupBys.length) {
			bool outputted = false;
			sql ~= " GROUP BY ";
			foreach(o; groupBys) {
				if(outputted)
					sql ~= ", ";
				else
					outputted = true;
				sql ~= o;
			}
		}

		if(orderBys.length) {
			bool outputted = false;
			sql ~= " ORDER BY ";
			foreach(o; orderBys) {
				if(outputted)
					sql ~= ", ";
				else
					outputted = true;
				sql ~= o;
			}
		}

		if(limit) {
			sql ~= " LIMIT ";
			if(limitStart)
				sql ~= to!string(limitStart) ~ ", ";
			sql ~= to!string(limit);
		}

		if(db is null)
			return sql;

		return escapedVariants(db, sql, vars);
	}
}


// /////////////////////sql//////////////////////////////////

package string tohexsql(const(ubyte)[] b) {
	char[] x;
	x.length = b.length * 2 + 3;
	int pos = 0;
	x[pos++] = 'x';
	x[pos++] = '\'';

	char tohex(ubyte a) {
		if(a < 10)
			return cast(char)(a + '0');
		else
			return cast(char)(a - 10 + 'A');
	}

	foreach(item; b) {
		x[pos++] = tohex(item >> 4);
		x[pos++] = tohex(item & 0x0f);
	}

	x[pos++] = '\'';

	return cast(string) x;
}

// used in the internal placeholder thing
string toSql(Database db, Variant a) {

	string binary(const(ubyte)[] b) {
		if(b is null)
			return "NULL";
		else
			return db.escapeBinaryString(b);
	}

	auto v = a.peek!(void*);
	if(v && (*v is null)) {
		return "NULL";
	} else if(auto t = a.peek!(SysTime)) {
		return db.sysTimeToValue(*t);
	} else if(auto t = a.peek!(DateTime)) {
		// FIXME: this might be broken cuz of timezones!
		return db.sysTimeToValue(cast(SysTime) *t);
	} else if(auto t = a.peek!(ubyte[])) {
		return binary(*t);
	} else if(auto t = a.peek!(immutable(ubyte)[])) {
		return binary(*t);
	} else if(auto t = a.peek!string) {
		auto str = *t;
		if(str is null)
			return "NULL";
		else
			return '\'' ~ db.escape(str) ~ '\'';
	} else {
		string str = to!string(a);
		return '\'' ~ db.escape(str) ~ '\'';
	}

	assert(0);
}

// just for convenience; "str".toSql(db);
string toSql(string s, Database db) {
	//if(s is null)
		//return "NULL";
	return '\'' ~ db.escape(s) ~ '\'';
}

string toSql(long s, Database db) {
	return to!string(s);
}

string escapedVariants(Database db, in string sql, Variant[string] t) {
	if(t.keys.length <= 0 || sql.indexOf("?") == -1) {
		return sql;
	}

	string fixedup;
	int currentStart = 0;
// FIXME: let's make ?? render as ? so we have some escaping capability
	foreach(i, dchar c; sql) {
		if(c == '?') {
			fixedup ~= sql[currentStart .. i];

			int idxStart = cast(int) i + 1;
			int idxLength;

			bool isFirst = true;

			while(idxStart + idxLength < sql.length) {
				char C = sql[idxStart + idxLength];

				if((C >= 'a' && C <= 'z') || (C >= 'A' && C <= 'Z') || C == '_' || (!isFirst && C >= '0' && C <= '9'))
					idxLength++;
				else
					break;

				isFirst = false;
			}

			auto idx = sql[idxStart .. idxStart + idxLength];

			if(idx in t) {
				fixedup ~= toSql(db, t[idx]);
				currentStart = idxStart + idxLength;
			} else {
				// just leave it there, it might be done on another layer
				currentStart = cast(int) i;
			}
		}
	}

	fixedup ~= sql[currentStart .. $];

	return fixedup;
}

/// Note: ?n params are zero based!
string escapedVariants(Database db, in string sql, Variant[] t) {
// FIXME: let's make ?? render as ? so we have some escaping capability
	// if nothing to escape or nothing to escape with, don't bother
	if(t.length > 0 && sql.indexOf("?") != -1) {
		string fixedup;
		int currentIndex;
		int currentStart = 0;
		foreach(i, dchar c; sql) {
			if(c == '?') {
				fixedup ~= sql[currentStart .. i];

				int idx = -1;
				currentStart = cast(int) i + 1;
				if((i + 1) < sql.length) {
					auto n = sql[i + 1];
					if(n >= '0' && n <= '9') {
						currentStart = cast(int) i + 2;
						idx = n - '0';
					}
				}
				if(idx == -1) {
					idx = currentIndex;
					currentIndex++;
				}

				if(idx < 0 || idx >= t.length)
					throw new Exception("SQL Parameter index is out of bounds: " ~ to!string(idx) ~ " at `"~sql[0 .. i]~"`");

				fixedup ~= toSql(db, t[idx]);
			}
		}

		fixedup ~= sql[currentStart .. $];

		return fixedup;
		/*
		string fixedup;
		int pos = 0;


		void escAndAdd(string str, int q) {
			fixedup ~= sql[pos..q] ~ '\'' ~ db.escape(str) ~ '\'';

		}

		foreach(a; t) {
			int q = sql[pos..$].indexOf("?");
			if(q == -1)
				break;
			q += pos;

			auto v = a.peek!(void*);
			if(v && (*v is null))
				fixedup  ~= sql[pos..q] ~ "NULL";
			else {
				string str = to!string(a);
				escAndAdd(str, q);
			}

			pos = q+1;
		}

		fixedup ~= sql[pos..$];

		sql = fixedup;
		*/
	}

	return sql;
}






enum UpdateOrInsertMode {
	CheckForMe,
	AlwaysUpdate,
	AlwaysInsert
}


// BIG FIXME: this should really use prepared statements
int updateOrInsert(Database db, string table, string[string] values, string where, UpdateOrInsertMode mode = UpdateOrInsertMode.CheckForMe, string key = "id") {

	string identifierQuote = "";

	bool insert = false;

	final switch(mode) {
		case UpdateOrInsertMode.CheckForMe:
			auto res = db.query("SELECT "~key~" FROM "~identifierQuote~db.escape(table)~identifierQuote~" WHERE " ~ where);
			insert = res.empty;

		break;
		case UpdateOrInsertMode.AlwaysInsert:
			insert = true;
		break;
		case UpdateOrInsertMode.AlwaysUpdate:
			insert = false;
		break;
	}


	if(insert) {
		string insertSql = "INSERT INTO " ~identifierQuote ~ db.escape(table) ~ identifierQuote ~ " ";

		bool outputted = false;
		string vs, cs;
		foreach(column, value; values) {
			if(column is null)
				continue;
			if(outputted) {
				vs ~= ", ";
				cs ~= ", ";
			} else
				outputted = true;

			//cs ~= "`" ~ db.escape(column) ~ "`";
			cs ~= identifierQuote ~ column ~ identifierQuote; // FIXME: possible insecure
			if(value is null)
				vs ~= "NULL";
			else
				vs ~= "'" ~ db.escape(value) ~ "'";
		}

		if(!outputted)
			return 0;


		insertSql ~= "(" ~ cs ~ ")";
		insertSql ~= " VALUES ";
		insertSql ~= "(" ~ vs ~ ")";

		db.query(insertSql);

		return 0; // db.lastInsertId;
	} else {
		string updateSql = "UPDATE "~identifierQuote~db.escape(table)~identifierQuote~" SET ";

		bool outputted = false;
		foreach(column, value; values) {
			if(column is null)
				continue;
			if(outputted)
				updateSql ~= ", ";
			else
				outputted = true;

			if(value is null)
				updateSql ~= identifierQuote ~ db.escape(column) ~ identifierQuote ~ " = NULL";
			else
				updateSql ~= identifierQuote ~ db.escape(column) ~ identifierQuote ~ " = '" ~ db.escape(value) ~ "'";
		}

		if(!outputted)
			return 0;

		updateSql ~= " WHERE " ~ where;

		db.query(updateSql);
		return 0;
	}
}





string fixupSqlForDataObjectUse(string sql, string[string] keyMapping = null) {

	string[] tableNames;

	string piece = sql;
	sizediff_t idx;
	while((idx = piece.indexOf("JOIN")) != -1) {
		auto start = idx + 5;
		auto i = start;
		while(piece[i] != ' ' && piece[i] != '\n' && piece[i] != '\t' && piece[i] != ',')
			i++;
		auto end = i;

		tableNames ~= strip(piece[start..end]);

		piece = piece[end..$];
	}

	idx = sql.indexOf("FROM");
	if(idx != -1) {
		auto start = idx + 5;
		auto i = start;
		start = i;
		while(i < sql.length && !(sql[i] > 'A' && sql[i] <= 'Z')) // if not uppercase, except for A (for AS) to avoid SQL keywords (hack)
			i++;

		auto from = sql[start..i];
		auto pieces = from.split(",");
		foreach(p; pieces) {
			p = p.strip();
			start = 0;
			i = 0;
			while(i < p.length && p[i] != ' ' && p[i] != '\n' && p[i] != '\t' && p[i] != ',')
				i++;

			tableNames ~= strip(p[start..i]);
		}

		string sqlToAdd;
		foreach(tbl; tableNames) {
			if(tbl.length) {
				string keyName = "id";
				if(tbl in keyMapping)
					keyName = keyMapping[tbl];
				sqlToAdd ~= ", " ~ tbl ~ "." ~ keyName ~ " AS " ~ "id_from_" ~ tbl;
			}
		}

		sqlToAdd ~= " ";

		sql = sql[0..idx] ~ sqlToAdd ~ sql[idx..$];
	}

	return sql;
}





/*
	This is like a result set


	DataObject res = [...];

	res.name = "Something";

	res.commit; // runs the actual update or insert


	res = new DataObject(fields, tables







	when doing a select, we need to figure out all the tables and modify the query to include the ids we need


	search for FROM and JOIN
	the next token is the table name

	right before the FROM, add the ids of each table


	given:
		SELECT name, phone FROM customers LEFT JOIN phones ON customer.id = phones.cust_id

	we want:
		SELECT name, phone, customers.id AS id_from_customers, phones.id AS id_from_phones FROM customers LEFT JOIN phones ON customer.id[...];

*/

mixin template DataObjectConstructors() {
	this(Database db, string[string] res, Tuple!(string, string)[string] mappings) {
		super(db, res, mappings);
	}
}

private string yield(string what) { return `if(auto result = dg(`~what~`)) return result;`; }

import std.typecons;
import std.json; // for json value making
class DataObject {
	// lets you just free-form set fields, assuming they all come from the given table
	// note it doesn't try to handle joins for new rows. you've gotta do that yourself
	this(Database db, string table, UpdateOrInsertMode mode = UpdateOrInsertMode.CheckForMe) {
		assert(db !is null);
		this.db = db;
		this.table = table;

		this.mode = mode;
	}

	JSONValue makeJsonValue() {
		JSONValue val;
		JSONValue[string] valo;
		//val.type = JSON_TYPE.OBJECT;
		foreach(k, v; fields) {
			JSONValue s;
			//s.type = JSON_TYPE.STRING;
			s.str = v;
			valo[k] = s;
		}
		val = valo;
		return val;
	}

	this(Database db, string[string] res, Tuple!(string, string)[string] mappings) {
		this.db = db;
		this.mappings = mappings;
		this.fields = res;

		mode = UpdateOrInsertMode.AlwaysUpdate;
	}

	string table;
	//     table,  column  [alias]
	Tuple!(string, string)[string] mappings;

	// value [field] [table]
	string[string][string] multiTableKeys; // note this is not set internally tight now
						// but it can be set manually to do multi table mappings for automatic update


	string opDispatch(string field, string file = __FILE__, size_t line = __LINE__)()
		if((field.length < 8 || field[0..8] != "id_from_") && field != "popFront")
	{
		if(field !in fields)
			throw new Exception("no such field " ~ field, file, line);

		return fields[field];
	}

	string opDispatch(string field, T)(T t)
		if((field.length < 8 || field[0..8] != "id_from_") && field != "popFront")
	{
		static if(__traits(compiles, t is null)) {
			if(t is null)
				setImpl(field, null);
			else
				setImpl(field, to!string(t));
		} else
			setImpl(field, to!string(t));

		return fields[field];
	}


	private void setImpl(string field, string value) {
		if(field in fields) {
			if(fields[field] != value)
				changed[field] = true;
		} else {
			changed[field] = true;
		}

		fields[field] = value;
	}

	public void setWithoutChange(string field, string value) {
		fields[field] = value;
	}

	int opApply(int delegate(ref string) dg) {
		foreach(a; fields)
			mixin(yield("a"));

		return 0;
	}

	int opApply(int delegate(ref string, ref string) dg) {
		foreach(a, b; fields)
			mixin(yield("a, b"));

		return 0;
	}


	string opIndex(string field, string file = __FILE__, size_t line = __LINE__) {
		if(field !in fields)
			throw new DatabaseException("No such field in data object: " ~ field, file, line);
		return fields[field];
	}

	string opIndexAssign(string value, string field) {
		setImpl(field, value);
		return value;
	}

	string* opBinary(string op)(string key)  if(op == "in") {
		return key in fields;
	}

	string[string] fields;
	bool[string] changed;

	void commitChanges() {
		commitChanges(cast(string) null, null);
	}

	void commitChanges(string key, string keyField) {
		commitChanges(key is null ? null : [key], keyField is null ? null : [keyField]);
	}

	void commitChanges(string[] keys, string[] keyFields = null) {
		string[string][string] toUpdate;
		int updateCount = 0;
		foreach(field, c; changed) {
			if(c) {
				string tbl, col;
				if(mappings is null) {
					tbl = this.table;
					col = field;
				} else {
					if(field !in mappings)
						assert(0, "no such mapping for " ~ field);
					auto m = mappings[field];
					tbl = m[0];
					col = m[1];
				}

				toUpdate[tbl][col] = fields[field];
				updateCount++;
			}
		}

		if(updateCount) {
			db.startTransaction();
			scope(success) db.query("COMMIT");
			scope(failure) db.query("ROLLBACK");

			foreach(tbl, values; toUpdate) {
				string where, keyFieldToPass;

				if(keys is null) {
					keys = [null];
				}

				if(multiTableKeys is null || tbl !in multiTableKeys)
				foreach(i, key; keys) {
					string keyField;

					if(key is null) {
						key = "id_from_" ~ tbl;
						if(key !in fields)
							key = "id";
					}

					if(i >= keyFields.length || keyFields[i] is null) {
						if(key == "id_from_" ~ tbl)
							keyField = "id";
						else
							keyField = key;
					} else {
						keyField = keyFields[i];
					}


					if(where.length)
						where ~= " AND ";

					auto f = key in fields ? fields[key] : null;
					if(f is null)
						where ~= keyField ~ " = NULL";
					else
						where ~= keyField ~ " = '"~db.escape(f)~"'" ;
					if(keyFieldToPass.length)
						keyFieldToPass ~= ", ";

					keyFieldToPass ~= keyField;
				}
				else {
					foreach(keyField, v; multiTableKeys[tbl]) {
						if(where.length)
							where ~= " AND ";

						where ~= keyField ~ " = '"~db.escape(v)~"'" ;
						if(keyFieldToPass.length)
							keyFieldToPass ~= ", ";

						keyFieldToPass ~= keyField;
					}
				}



				updateOrInsert(db, tbl, values, where, mode, keyFieldToPass);
			}

			changed = null;
		}
	}

	void commitDelete() {
		if(mode == UpdateOrInsertMode.AlwaysInsert)
			throw new Exception("Cannot delete an item not in the database");

		assert(table.length); // FIXME, should work with fancy items too

		// FIXME: escaping and primary key questions
		db.query("DELETE FROM " ~ table ~ " WHERE id = '" ~ db.escape(fields["id"]) ~ "'");
	}

	string getAlias(string table, string column) {
		string ali;
		if(mappings is null) {
			if(this.table is null) {
				mappings[column] = tuple(table, column);
				return column;
			} else {
				assert(table == this.table);
				ali = column;
			}
		} else {
			foreach(a, what; mappings)
				if(what[0] == table && what[1] == column
				  && a.indexOf("id_from_") == -1) {
					ali = a;
					break;
				}
		}

		return ali;
	}

	void set(string table, string column, string value) {
		string ali = getAlias(table, column);
		//assert(ali in fields);
		setImpl(ali, value);
	}

	string select(string table, string column) {
		string ali = getAlias(table, column);
		//assert(ali in fields);
		if(ali in fields)
			return fields[ali];
		return null;
	}

	DataObject addNew() {
		auto n = new DataObject(db, null);

		n.db = this.db;
		n.table = this.table;
		n.mappings = this.mappings;

		foreach(k, v; this.fields)
			if(k.indexOf("id_from_") == -1)
				n.fields[k] = v;
			else
				n.fields[k] = null; // don't copy ids

		n.mode = UpdateOrInsertMode.AlwaysInsert;

		return n;
	}

	Database db;
	UpdateOrInsertMode mode;
}

/**
	You can subclass DataObject if you want to
	get some compile time checks or better types.

	You'll want to disable opDispatch, then forward your
	properties to the super opDispatch.
*/

/*mixin*/ string DataObjectField(T, string table, string column, string aliasAs = null)() {
	string aliasAs_;
	if(aliasAs is null)
		aliasAs_ = column;
	else
		aliasAs_ = aliasAs;
	return `
		@property void `~aliasAs_~`(`~T.stringof~` setTo) {
			super.set("`~table~`", "`~column~`", to!string(setTo));
		}

		@property `~T.stringof~` `~aliasAs_~` () {
			return to!(`~T.stringof~`)(super.select("`~table~`", "`~column~`"));
		}
	`;
}

mixin template StrictDataObject() {
	// disable opdispatch
	string opDispatch(string name)(...) if (0) {}
}


string createDataObjectFieldsFromAlias(string table, fieldsToUse)() {
	string ret;

	fieldsToUse f;
	foreach(member; __traits(allMembers, fieldsToUse)) {
		ret ~= DataObjectField!(typeof(__traits(getMember, f, member)), table, member);
	}

	return ret;
}


/**
	This creates an editable data object out of a simple struct.

	struct MyFields {
		int id;
		string name;
	}

	alias SimpleDataObject!("my_table", MyFields) User;


	User a = new User(db);

	a.id = 30;
	a.name = "hello";
	a.commitChanges(); // tries an update or insert on the my_table table


	Unlike the base DataObject class, this template provides compile time
	checking for types and names, based on the struct you pass in:

	a.id = "aa"; // compile error

	a.notAField; // compile error
*/
class SimpleDataObject(string tableToUse, fieldsToUse) : DataObject {
	mixin StrictDataObject!();

	mixin(createDataObjectFieldsFromAlias!(tableToUse, fieldsToUse)());

	this(Database db) {
		super(db, tableToUse);
	}
}

/**
	Given some SQL, it finds the CREATE TABLE
	instruction for the given tableName.
	(this is so it can find one entry from
	a file with several SQL commands. But it
	may break on a complex file, so try to only
	feed it simple sql files.)

	From that, it pulls out the members to create a
	simple struct based on it.

	It's not terribly smart, so it will probably
	break on complex tables.

	Data types handled:

	```
		INTEGER, SMALLINT, MEDIUMINT -> D's int
		TINYINT -> D's bool
		BIGINT -> D's long
		TEXT, VARCHAR -> D's string
		FLOAT, DOUBLE -> D's double
	```

	It also reads DEFAULT values to pass to D, except for NULL.
	It ignores any length restrictions.

	Bugs:
	$(LIST
		* Skips all constraints
		* Doesn't handle nullable fields, except with strings
		* It only handles SQL keywords if they are all caps
	)

	This, when combined with SimpleDataObject!(),
	can automatically create usable D classes from
	SQL input.
*/
struct StructFromCreateTable(string sql, string tableName) {
	mixin(getCreateTable(sql, tableName));
}

string getCreateTable(string sql, string tableName) {
   skip:
	while(readWord(sql) != "CREATE") {}

	assert(readWord(sql) == "TABLE");

	if(readWord(sql) != tableName)
		goto skip;

	assert(readWord(sql) == "(");

	int state;
	int parens;

	struct Field {
		string name;
		string type;
		string defaultValue;
	}
	Field*[] fields;

	string word = readWord(sql);
	Field* current = new Field(); // well, this is interesting... under new DMD, not using new breaks it in CTFE because it overwrites the one entry!
	while(word != ")" || parens) {
		if(word == ")") {
			parens --;
			word = readWord(sql);
			continue;
		}
		if(word == "(") {
			parens ++;
			word = readWord(sql);
			continue;
		}
		switch(state) {
		    default: assert(0);
		    case 0:
		    	if(word[0] >= 'A' && word[0] <= 'Z') {
				state = 4;
				break; // we want to skip this since it starts with a keyword (we hope)
			}
			current.name = word;
			state = 1;
		    break;
		    case 1:
		    	current.type ~= word;
			state = 2;
		    break;
		    case 2:
		    	if(word == "DEFAULT")
				state = 3;
			else if (word == ",") {
				fields ~= current;
				current = new Field();
				state = 0; // next
			}
		    break;
		    case 3:
		    	current.defaultValue = word;
			state = 2; // back to skipping
		    break;
		    case 4:
		    	if(word == ",")
				state = 0;
		}

		word = readWord(sql);
	}

	if(current.name !is null)
		fields ~= current;


	string structCode;
	foreach(field; fields) {
		structCode ~= "\t";

		switch(field.type) {
			case "INTEGER":
			case "SMALLINT":
			case "MEDIUMINT":
			case "SERIAL": // added Oct 23, 2021
				structCode ~= "int";
			break;
			case "BOOLEAN":
			case "TINYINT":
				structCode ~= "bool";
			break;
			case "BIGINT":
				structCode ~= "long";
			break;
			case "CHAR":
			case "char":
			case "VARCHAR":
			case "varchar":
			case "TEXT":
			case "text":
			case "TIMESTAMPTZ": // added Oct 23, 2021
				structCode ~= "string";
			break;
			case "FLOAT":
			case "DOUBLE":
				structCode ~= "double";
			break;
			default:
				assert(0, "unknown type " ~ field.type ~ " for " ~ field.name);
		}

		structCode ~= " ";
		structCode ~= field.name;

		if(field.defaultValue !is null) {
			structCode ~= " = " ~ field.defaultValue;
		}

		structCode ~= ";\n";
	}

	return structCode;
}

string readWord(ref string src) {
   reset:
	while(src[0] == ' ' || src[0] == '\t' || src[0] == '\n')
		src = src[1..$];
	if(src.length >= 2 && src[0] == '-' && src[1] == '-') { // a comment, skip it
		while(src[0] != '\n')
			src = src[1..$];
		goto reset;
	}

	int start, pos;
	if(src[0] == '`') {
		src = src[1..$];
		while(src[pos] != '`')
			pos++;
		goto gotit;
	}


	while(
		(src[pos] >= 'A' && src[pos] <= 'Z')
		||
		(src[pos] >= 'a' && src[pos] <= 'z')
		||
		(src[pos] >= '0' && src[pos] <= '9')
		||
		src[pos] == '_'
	)
		pos++;
	gotit:
	if(pos == 0)
		pos = 1;

	string tmp = src[0..pos];

	if(src[pos] == '`')
		pos++; // skip the ending quote;

	src = src[pos..$];

	return tmp;
}

/// Combines StructFromCreateTable and SimpleDataObject into a one-stop template.
/// alias DataObjectFromSqlCreateTable(import("file.sql"), "my_table") MyTable;
template DataObjectFromSqlCreateTable(string sql, string tableName) {
	alias SimpleDataObject!(tableName, StructFromCreateTable!(sql, tableName)) DataObjectFromSqlCreateTable;
}

/+
class MyDataObject : DataObject {
	this() {
		super(new Database("localhost", "root", "pass", "social"), null);
	}

	mixin StrictDataObject!();

	mixin(DataObjectField!(int, "users", "id"));
}

void main() {
	auto a = new MyDataObject;

	a.fields["id"] = "10";

	a.id = 34;

	a.commitChanges;
}
+/

/*
alias DataObjectFromSqlCreateTable!(import("db.sql"), "users") Test;

void main() {
	auto a = new Test(null);

	a.cool = "way";
	a.value = 100;
}
*/

void typeinfoBugWorkaround() {
	assert(0, to!string(typeid(immutable(char[])[immutable(char)[]])));
}

mixin template DatabaseOperations(string table) {
	DataObject getAsDb(Database db) {
		return objectToDataObject!(typeof(this))(this, db, table);
	}

	static typeof(this) fromRow(Row row) {
		return rowToObject!(typeof(this))(row);
	}

	static typeof(this) fromId(Database db, long id) {
		auto query = new SelectBuilder(db);
		query.table = table;
		query.fields ~= "*";
		query.wheres ~= "id = ?0";
		auto res = db.query(query.toString(), id);
		if(res.empty)
			throw new Exception("no such row");
		return fromRow(res.front);
	}

}

string toDbName(string s) {
	import std.string;
	return s.toLower ~ "s";
}

/++
	Easy interop with [arsd.cgi] serveRestObject classes.

	History:
		Added October 31, 2021.

	Warning: not stable/supported at this time.
+/
mixin template DatabaseRestObject(alias getDb) {
	override void save() {
		this.id = this.saveToDatabase(getDb());
	}

	override void load(string urlId) {
		import std.conv;
		this.id = to!int(urlId);
		this.loadFromDatabase(getDb());
	}
}

void loadFromDatabase(T)(T t, Database database, string tableName = toDbName(__traits(identifier, T))) {
	static assert(is(T == class), "structs wont work for this function, try rowToObject instead for now and complain to me adding struct support is easy enough");
	auto query = new SelectBuilder(database);
	query.table = tableName;
	query.fields ~= "*";
	query.wheres ~= "id = ?0";
	auto res = database.query(query.toString(), t.id);
	if(res.empty)
		throw new Exception("no such row");

	rowToObject(res.front, t);
}

auto saveToDatabase(T)(T t, Database database, string tableName = toDbName(__traits(identifier, T))) {
	DataObject obj = objectToDataObject(t, database, tableName, t.id ? UpdateOrInsertMode.AlwaysUpdate : UpdateOrInsertMode.AlwaysInsert);
	if(!t.id) {
		import std.random; // omg i hate htis
		obj.id = uniform(2, int.max);
	}
	obj.commitChanges;
	return t.id;
}

/+ +
	auto builder = UpdateBuilder("rooms");
	builder.player_one_selection = challenge;
	builder.execute(db, id);
+/
private struct UpdateBuilder {
	this(T)(string table, T id) {
		this.table = table;
		import std.conv;
		this.id = to!string(id);
	}

}

import std.traits, std.datetime;
enum DbSave;
enum DbNullable;
alias AliasHelper(alias T) = T;

T rowToObject(T)(Row row) {
	T t;
	static if(is(T == class))
		t = new T();
	rowToObject(row, t);
	return t;
}

void rowToObject(T)(Row row, ref T t) {
	import arsd.dom, arsd.cgi;

	foreach(memberName; __traits(allMembers, T)) {
		alias member = AliasHelper!(__traits(getMember, t, memberName));
		foreach(attr; __traits(getAttributes, member)) {
			static if(is(attr == DbSave)) {
				static if(is(typeof(member) == enum))
					__traits(getMember, t, memberName) = cast(typeof(member)) to!int(row[memberName]);
				else static if(is(typeof(member) == bool)) {
					__traits(getMember, t, memberName) = row[memberName][0] == 't';
				} else static if(is(typeof(member) == Html)) {
					__traits(getMember, t, memberName).source = row[memberName];
				} else static if(is(typeof(member) == DateTime))
					__traits(getMember, t, memberName) = cast(DateTime) dTimeToSysTime(to!long(row[memberName]));
				else {
					if(row[memberName].length)
						__traits(getMember, t, memberName) = to!(typeof(member))(row[memberName]);
					// otherwise, we'll leave it as .init - most likely null
				}
			}
		}
	}
}

DataObject objectToDataObject(T)(T t, Database db, string table, UpdateOrInsertMode mode = UpdateOrInsertMode.CheckForMe) {
	import arsd.dom, arsd.cgi;

	DataObject obj = new DataObject(db, table, mode);
	foreach(memberName; __traits(allMembers, T)) {
		alias member = AliasHelper!(__traits(getMember, t, memberName));
		foreach(attr; __traits(getAttributes, member)) {
			static if(is(attr == DbSave)) {
				static if(is(typeof(member) == enum))
					obj.opDispatch!memberName(cast(int) __traits(getMember, t, memberName));
				else static if(is(typeof(member) == Html)) {
					obj.opDispatch!memberName(__traits(getMember, t, memberName).source);
				} else static if(is(typeof(member) == DateTime))
					obj.opDispatch!memberName(dateTimeToDTime(__traits(getMember, t, memberName)));
				else {
					bool done;
					foreach(attr2; __traits(getAttributes, member)) {
						static if(is(attr2 == DbNullable)) {
							if(__traits(getMember, t, memberName) == 0)
								done = true;
						}
					}

					if(!done) {
						static if(memberName == "id") {
							if(__traits(getMember, t, memberName)) {
								// maybe i shouldn't actually set the id but idk
								obj.opDispatch!memberName(__traits(getMember, t, memberName));
							} else {
								// it is null, let the system do something about it like auto increment

							}
						} else
							obj.opDispatch!memberName(__traits(getMember, t, memberName));
					}
				}
			}
		}
	}
	return obj;
}



void fillData(T)(string delegate(string, string) setter, T obj, string name) {
	fillData( (k, v) { setter(k, v); }, obj, name);
}

void fillData(T)(void delegate(string, string) setter, T obj, string name) {
	import arsd.dom, arsd.cgi;

	import std.traits;
	static if(!isSomeString!T && isArray!T) {
		// FIXME: indexing
		foreach(o; obj)
			fillData(setter, o, name);
	} else static if(is(T == DateTime)) {
		 fillData(setter, obj.toISOExtString(), name);
	} else static if(is(T == Html)) {
		 fillData(setter, obj.source, name);
	} else static if(is(T == struct)) {
		foreach(idx, memberName; __traits(allMembers, T)) {
			alias member = AliasHelper!(__traits(getMember, obj, memberName));
			static if(!is(typeof(member) == function))
				fillData(setter, __traits(getMember, obj, memberName), name ~ "." ~ memberName);
			else static if(is(typeof(member) == function)) {
				static if(functionAttributes!member & FunctionAttribute.property) {
					fillData(setter, __traits(getMember, obj, memberName)(), name ~ "." ~ memberName);
				}
			}
		}
	} else {
		auto value = to!string(obj);
		setter(name, value);
	}
}

struct varchar(size_t max) {
	private string payload;

	this(string s, string file = __FILE__, size_t line = __LINE__) {
		opAssign(s, file, line);
	}

	typeof(this) opAssign(string s, string file = __FILE__, size_t line = __LINE__) {
		if(s.length > max)
			throw new Exception(s ~ " :: too long", file, line);
		payload = s;

		return this;
	}

	string asString() {
		return payload;

	}
	alias asString this;
}

version (unittest)
{
	/// Unittest utility that returns a predefined set of values
	package (arsd) final class PredefinedResultSet : ResultSet
	{
		string[] fields;
		Row[] rows;
		size_t current;

		this(string[] fields, Row[] rows)
		{
			this.fields = fields;
			this.rows = rows;
			foreach (ref row; rows)
				row.resultSet = this;
		}

		int getFieldIndex(const string field) const
		{
			foreach (const idx, const val; fields)
				if (val == field)
					return cast(int) idx;

			assert(false, "No field with name: " ~ field);
		}

		string[] fieldNames()
		{
			return fields;
		}

		@property bool empty() const
		{
			return current == rows.length;
		}

		Row front() @property
		{
			assert(!empty);
			return rows[current];
		}

		void popFront()
		{
			assert(!empty);
			current++;
		}

		size_t length() @property
		{
			return rows.length - current;
		}
	}
}
