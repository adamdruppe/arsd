module arsd.database;

public import std.variant;
import std.string;

import core.vararg;

interface Database {
	/// Actually implements the query for the database. The query() method
	/// below might be easier to use.
	ResultSet queryImpl(string sql, Variant[] args...);

	/// Escapes data for inclusion into an sql string literal
	string escape(string sqlData);

	/// query to start a transaction, only here because sqlite is apparently different in syntax...
	void startTransaction();

	// FIXME: this would be better as a template, but can't because it is an interface

	/// Just executes a query. It supports placeholders for parameters
	/// by using ? in the sql string. NOTE: it only accepts string, int, long, and null types.
	/// Others will fail runtime asserts.
	final ResultSet query(string sql, ...) {
		Variant[] args;
		foreach(arg; _arguments) {
			string a;
			if(arg == typeid(string)) {
				a = va_arg!(string)(_argptr);
			} else if(arg == typeid(immutable(string))) {
				a = va_arg!(immutable(string))(_argptr);
			} else if(arg == typeid(const(immutable(char)[]))) {
				a = va_arg!(const(immutable(char)[]))(_argptr);
			} else if (arg == typeid(int)) {
				auto e = va_arg!(int)(_argptr);
				a = to!string(e);
			} else if (arg == typeid(immutable(int))) {
				auto e = va_arg!(immutable(int))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(const(int))) {
				auto e = va_arg!(const(int))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(immutable(char))) {
				auto e = va_arg!(immutable(char))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(long)) {
				auto e = va_arg!(long)(_argptr);
				a = to!string(e);
			} else if (arg == typeid(const(long))) {
				auto e = va_arg!(const(long))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(immutable(long))) {
				auto e = va_arg!(immutable(long))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(void*)) {
				auto e = va_arg!(void*)(_argptr);
				assert(e is null, "can only pass null pointer");
				a = null;
			} else assert(0, "invalid type " ~ arg.toString );

			args ~= Variant(a);
		}

		return queryImpl(sql, args);
	}
}
import std.stdio;

struct Row {
	package string[] row;
	package ResultSet resultSet;

	string opIndex(size_t idx) {
		if(idx >= row.length)
			throw new Exception(text("index ", idx, " is out of bounds on result"));
		return row[idx];
	}

	string opIndex(string idx) {
		return row[resultSet.getFieldIndex(idx)];
	}

	string toString() {
		return to!string(row);
	}

	string[string] toAA() {
		string[string] a;

		string[] fn = resultSet.fieldNames();

		foreach(i, r; row)
			a[fn[i]] = r;

		return a;
	}

	int opApply(int delegate(ref string, ref string) dg) {
		foreach(a, b; toAA)
			mixin(yield("a, b"));

		return 0;
	}



	string[] toStringArray() {
		return row;
	}
}
import std.conv;

interface ResultSet {
	// name for associative array to result index
	int getFieldIndex(string field);
	string[] fieldNames();

	// this is a range that can offer other ranges to access it
	bool empty();
	Row front();
	void popFront();
	int length();

	/* deprecated */ final ResultSet byAssoc() { return this; }
}

class DatabaseException : Exception {
	this(string msg) {
		super(msg);
	}

	this(string msg, string file, size_t line) {
		super(msg, file, line);
	}
}




// ///////////////////////////////////////////////////////


/// Note: ?n params are zero based!
string escapedVariants(Database db, in string sql, Variant[] t) {

	string toSql(Variant a) {
		auto v = a.peek!(void*);
		if(v && (*v is null))
			return "NULL";
		else {
			string str = to!string(a);
			return '\'' ~ db.escape(str) ~ '\'';
		}

		assert(0);
	}



	// if nothing to escape or nothing to escape with, don't bother
	if(t.length > 0 && sql.indexOf("?") != -1) {
		string fixedup;
		int currentIndex;
		int currentStart = 0;
		foreach(i, dchar c; sql) {
			if(c == '?') {
				fixedup ~= sql[currentStart .. i];

				int idx = -1;
				currentStart = i + 1;
				if((i + 1) < sql.length) {
					auto n = sql[i + 1];
					if(n >= '0' && n <= '9') {
						currentStart = i + 2;
						idx = n - '0';
					}
				}
				if(idx == -1) {
					idx = currentIndex;
					currentIndex++;
				}

				if(idx < 0 || idx >= t.length)
					throw new Exception("SQL Parameter index is out of bounds: " ~ to!string(idx) ~ " at `"~sql[0 .. i]~"`");

				fixedup ~= toSql(t[idx]);
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
	bool insert = false;

	final switch(mode) {
		case UpdateOrInsertMode.CheckForMe:
			auto res = db.query("SELECT "~key~" FROM `"~db.escape(table)~"` WHERE " ~ where);
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
		string insertSql = "INSERT INTO `" ~ db.escape(table) ~ "` ";

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
			cs ~= "`" ~ column ~ "`"; // FIXME: possible insecure
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
		string updateSql = "UPDATE `"~db.escape(table)~"` SET ";

		bool outputted = false;
		foreach(column, value; values) {
			if(column is null)
				continue;
			if(outputted)
				updateSql ~= ", ";
			else
				outputted = true;

			updateSql ~= "`" ~ db.escape(column) ~ "` = '" ~ db.escape(value) ~ "'";
		}

		if(!outputted)
			return 0;

		updateSql ~= " WHERE " ~ where;

		db.query(updateSql);
		return 0;
	}
}





string fixupSqlForDataObjectUse(string sql) {

	string[] tableNames;

	string piece = sql;
	int idx;
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
			p = p.strip;
			start = 0;
			i = 0;
			while(i < p.length && p[i] != ' ' && p[i] != '\n' && p[i] != '\t' && p[i] != ',')
				i++;

			tableNames ~= strip(p[start..i]);
		}

		string sqlToAdd;
		foreach(tbl; tableNames) {
			if(tbl.length) {
				sqlToAdd ~= ", " ~ tbl ~ ".id" ~ " AS " ~ "id_from_" ~ tbl;
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

string yield(string what) { return `if(auto result = dg(`~what~`)) return result;`; }

import std.typecons;
import std.json; // for json value making
class DataObject {
	// lets you just free-form set fields, assuming they all come from the given table
	// note it doesn't try to handle joins for new rows. you've gotta do that yourself
	this(Database db, string table) {
		assert(db !is null);
		this.db = db;
		this.table = table;

		mode = UpdateOrInsertMode.CheckForMe;
	}

	JSONValue makeJsonValue() {
		JSONValue val;
		val.type = JSON_TYPE.OBJECT;
		foreach(k, v; fields) {
			JSONValue s;
			s.type = JSON_TYPE.STRING;
			s.str = v;
			val.object[k] = s;
		}
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

	// vararg hack so property assignment works right, even with null
	string opDispatch(string field)(...)
		if((field.length < 8 || field[0..8] != "id_from_") && field != "popFront")
	{
		if(_arguments.length == 0) {
			if(field !in fields)
				throw new Exception("no such field " ~ field);

			return fields[field];
		} else if(_arguments.length == 1) {
			auto arg = _arguments[0];

			string a;
			if(arg == typeid(string)) {
				a = va_arg!(string)(_argptr);
			} else if(arg == typeid(immutable(string))) {
				a = va_arg!(immutable(string))(_argptr);
			} else if(arg == typeid(const(immutable(char)[]))) {
				a = va_arg!(const(immutable(char)[]))(_argptr);
			} else if (arg == typeid(int)) {
				auto e = va_arg!(int)(_argptr);
				a = to!string(e);
			} else if (arg == typeid(immutable(int))) {
				auto e = va_arg!(immutable(int))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(const(int))) {
				auto e = va_arg!(const(int))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(immutable(char))) {
				auto e = va_arg!(immutable(char))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(long)) {
				auto e = va_arg!(long)(_argptr);
				a = to!string(e);
			} else if (arg == typeid(const(long))) {
				auto e = va_arg!(const(long))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(immutable(long))) {
				auto e = va_arg!(immutable(long))(_argptr);
				a = to!string(e);
			} else if (arg == typeid(void*)) {
				auto e = va_arg!(void*)(_argptr);
				assert(e is null, "can only pass null pointer");
				a = null;
			} else assert(0, "invalid type " ~ arg.toString );


			auto setTo = a;
			setImpl(field, setTo);

			return setTo;

		} else assert(0, "too many arguments");

		assert(0); // should never be reached
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


	string opIndex(string field) {
		if(field !in fields)
			throw new DatabaseException("No such field in data object: " ~ field);
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

					where ~= keyField ~ " = '"~db.escape(key in fields ? fields[key] : null)~"'" ;
					if(keyFieldToPass.length)
						keyFieldToPass ~= ", ";

					keyFieldToPass ~= keyField;
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
		INTEGER, SMALLINT, MEDIUMINT -> D's int
		TINYINT -> D's bool
		BIGINT -> D's long
		TEXT, VARCHAR -> D's string
		FLOAT, DOUBLE -> D's double

	It also reads DEFAULT values to pass to D, except for NULL.
	It ignores any length restrictions.

	Bugs:
		Skips all constraints
		Doesn't handle nullable fields, except with strings
		It only handles SQL keywords if they are all caps

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
	Field[] fields;

	string word = readWord(sql);
	Field current;
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
				current = Field();
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
