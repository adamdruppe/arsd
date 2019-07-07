/**
	Compile with version=sqlite_extended_metadata_available
	if your sqlite is compiled with the
	 SQLITE_ENABLE_COLUMN_METADATA C-preprocessor symbol.

	If you enable that, you get the ability to use the
	queryDataObject() function with sqlite. (You can still
	use DataObjects, but you'll have to set up the mappings
	manually without the extended metadata.)
*/
module arsd.sqlite;
version(static_sqlite) {} else
pragma(lib, "sqlite3");
version(linux)
pragma(lib, "dl"); // apparently sqlite3 depends on this
public import arsd.database;

import std.exception;

import std.string;

import core.stdc.stdlib;
import core.exception;
import core.memory;
import std.file;
import std.conv;
/*
	NOTE:

	This only works correctly on INSERTs if the user can grow the
	database file! This means he must have permission to write to
	both the file and the directory it is in.

*/


/**
	The Database interface provides a consistent and safe way to access sql RDBMSs.

	Why are all the classes scope? To ensure the database connection is closed when you are done with it.
	The destructor cleans everything up.

	(maybe including rolling back a transaction if one is going and it errors.... maybe, or that could bne
	scope(exit))
*/

Sqlite openDBAndCreateIfNotPresent(string filename, string sql, void delegate(Sqlite db) initialize = null){
	if(exists(filename))
		return new Sqlite(filename);
	else {
		auto db = new Sqlite(filename);
		db.exec(sql);
		if(initialize !is null)
			initialize(db);
		return db;
	}
}

/*
import std.stdio;
void main() {
	Database db = new Sqlite("test.sqlite.db");

	db.query("CREATE TABLE users (id integer, name text)");

	db.query("INSERT INTO users values (?, ?)", 1, "hello");

	foreach(line; db.query("SELECT * FROM users")) {
		writefln("%s %s", line[0], line["name"]);
	}
}
*/

class Sqlite : Database {
  public:
	this(string filename, int flags = SQLITE_OPEN_READWRITE) {
	/+
		int error = sqlite3_open_v2(toStringz(filename), &db, flags, null);
		if(error == SQLITE_CANTOPEN)
			throw new DatabaseException("omg cant open");
		if(error != SQLITE_OK)
			throw new DatabaseException("db open " ~ error());
	+/
		int error = sqlite3_open(toStringz(filename), &db);
		if(error != SQLITE_OK)
			throw new DatabaseException(this.error());
	}

	~this(){
		if(sqlite3_close(db) != SQLITE_OK)
			throw new DatabaseException(error());
	}

	// my extension for easier editing
	version(sqlite_extended_metadata_available) {
		ResultByDataObject queryDataObject(T...)(string sql, T t) {
			// modify sql for the best data object grabbing
			sql = fixupSqlForDataObjectUse(sql);

			auto s = Statement(this, sql);
			foreach(i, arg; t) {
				s.bind(i + 1, arg);
			}

			auto magic = s.execute(true); // fetch extended metadata

			return ResultByDataObject(cast(SqliteResult) magic, magic.extendedMetadata, this);
		}
	}

	override void startTransaction() {
		query("BEGIN TRANSACTION");
	}

	override ResultSet queryImpl(string sql, Variant[] args...) {
		auto s = Statement(this, sql);
		foreach(i, arg; args) {
			s.bind(cast(int) i + 1, arg);
		}

		return s.execute();
	}

	override string escape(string sql) {
		if(sql is null)
			return null;
		char* got = sqlite3_mprintf("%q", toStringz(sql)); // FIXME: might have to be %Q, need to check this, but I think the other impls do the same as %q
		auto orig = got;
		string esc;
		while(*got) {
			esc ~= (*got);
			got++;
		}

		sqlite3_free(orig);

		return esc;
	}

	string error(){
		import core.stdc.string : strlen;
		char* mesg = sqlite3_errmsg(db);
		char[] m;
		sizediff_t a = strlen(mesg);
		m.length = a;
		for(int v = 0; v < a; v++)
			m[v] = mesg[v];

		return assumeUnique(m);
	}

	int affectedRows(){
		return sqlite3_changes(db);
	}

	int lastInsertId(){
		return cast(int) sqlite3_last_insert_rowid(db);
	}


	int exec(string sql, void delegate (char[][char[]]) onEach = null) {
		char* mesg;
		if(sqlite3_exec(db, toStringz(sql), &callback, &onEach, &mesg) != SQLITE_OK) {
			import core.stdc.string : strlen;
			char[] m;
			sizediff_t a = strlen(mesg);
			m.length = a;
			for(int v = 0; v < a; v++)
				m[v] = mesg[v];

			sqlite3_free(mesg);
			throw new DatabaseException("exec " ~ m.idup);
		}

		return 0;
	}
/*
	Statement prepare(string sql){
		sqlite3_stmt * s;
		if(sqlite3_prepare_v2(db, toStringz(sql), cast(int) sql.length, &s, null) != SQLITE_OK)
			throw new DatabaseException("prepare " ~ error());

		Statement a = new Statement(s);

		return a;
	}
*/
  private:
	sqlite3* db;
}






class SqliteResult :  ResultSet {
	int getFieldIndex(string field) {
		foreach(i, n; columnNames)
			if(n == field)
				return cast(int) i;
		throw new Exception("no such field " ~ field);
	}

	string[] fieldNames() {
		return columnNames;
	}

	// this is a range that can offer other ranges to access it
	bool empty() {
		return position == rows.length;
	}

	Row front() {
		Row r;

		r.resultSet = this;
		if(rows.length <= position)
			throw new Exception("Result is empty");
		foreach(c; rows[position]) {
			r.row ~= c.coerce!(string);
		}

		return r;
	}

	void popFront() {
		position++;
	}

	override size_t length() {
		return rows.length;
	}

	this(Variant[][] rows, char[][] columnNames) {
		this.rows = rows;
		foreach(c; columnNames)
			this.columnNames ~= c.idup;
	}

    private:
	string[] columnNames;
	Variant[][] rows;
	int position = 0;
}






struct Statement {
	private this(Sqlite db, sqlite3_stmt * S) {
		this.db = db;
		s = S;
		finalized = false;
	}

	Sqlite db;

	this(Sqlite db, string sql) {
		this.db = db;
		if(sqlite3_prepare_v2(db.db, toStringz(sql), cast(int) sql.length, &s, null) != SQLITE_OK)
			throw new DatabaseException(db.error());
	}

	version(sqlite_extended_metadata_available)
		Tuple!(string, string)[string] extendedMetadata;

	ResultSet execute(bool fetchExtendedMetadata = false) {
		bool first = true;
		int count;
		int numRows = 0;
		int r = 0;
		// FIXME: doesn't handle busy database
		while( SQLITE_ROW == sqlite3_step(s) ){
			numRows++;
			if(numRows >= rows.length)
				rows.length = rows.length + 8;

			if(first){
				count = sqlite3_column_count(s);

				columnNames.length = count;
				for(int a = 0; a < count; a++){
					import core.stdc.string : strlen;
					char* str = sqlite3_column_name(s, a);
					sizediff_t l = strlen(str);
					columnNames[a].length = l;
					for(int b = 0; b < l; b++)
						columnNames[a][b] = str[b];

					version(sqlite_extended_metadata_available) {
					if(fetchExtendedMetadata) {
						string origtbl;
						string origcol;

						const(char)* rofl;

						rofl = sqlite3_column_table_name(s, a);
						if(rofl is null)
							throw new Exception("null table name pointer");
						while(*rofl) {
							origtbl ~= *rofl;
							rofl++;
						}
						rofl = sqlite3_column_origin_name(s, a);
						if(rofl is null)
							throw new Exception("null colum name pointer");
						while(*rofl) {
							origcol ~= *rofl;
							rofl++;
						}
						extendedMetadata[columnNames[a].idup] = tuple(origtbl, origcol);
					}
					}
				}

				first = false;
			}


			rows[r].length = count;

			for(int a = 0; a < count; a++){
				Variant v;
				final switch(sqlite3_column_type(s, a)){
					case SQLITE_INTEGER:
						v = sqlite3_column_int64(s, a);
					break;
					case SQLITE_FLOAT:
						v = sqlite3_column_double(s, a);
					break;
					case SQLITE3_TEXT:
						char* str = sqlite3_column_text(s, a);
						char[] st;

						import core.stdc.string : strlen;
						sizediff_t l = strlen(str);
						st.length = l;
						for(int aa = 0; aa < l; aa++)
							st[aa] = str[aa];

						v = assumeUnique(st);
					break;
					case SQLITE_BLOB:
						byte* str = cast(byte*) sqlite3_column_blob(s, a);
						byte[] st;

						int l = sqlite3_column_bytes(s, a);
						st.length = l;
						for(int aa = 0; aa < l; aa++)
							st[aa] = str[aa];

						v = assumeUnique(st);

					break;
					case SQLITE_NULL:
						v = null;
					break;
				}

				rows[r][a] = v;
			}

			r++;
		}

		rows.length = numRows;
		length = numRows;
		position = 0;
		executed = true;
		reset();

		return new SqliteResult(rows.dup, columnNames);
	}

/*
template extract(A, T, R...){
	void extract(A args, out T t, out R r){
		if(r.length + 1 != args.length)
			throw new DatabaseException("wrong places");
		args[0].to(t);
		static if(r.length)
			extract(args[1..$], r);
	}
}
*/
/*
	bool next(T, R...)(out T t, out R r){
		if(position == length)
			return false;

		extract(rows[position], t, r);

		position++;
		return true;
	}
*/
	bool step(out Variant[] row){
		assert(executed);
		if(position == length)
			return false;

		row = rows[position];
		position++;

		return true;
	}

	bool step(out Variant[char[]] row){
		assert(executed);
		if(position == length)
			return false;

		for(int a = 0; a < length; a++)
			row[columnNames[a].idup] = rows[position][a];

		position++;

		return true;
	}

	void reset(){
		if(sqlite3_reset(s) != SQLITE_OK)
			throw new DatabaseException("reset " ~ db.error());
	}

	void resetBindings(){
		sqlite3_clear_bindings(s);
	}

	void resetAll(){
		reset;
		resetBindings;
		executed = false;
	}

	int bindNameLookUp(const char[] name){
		int a = sqlite3_bind_parameter_index(s, toStringz(name));
		if(a == 0)
			throw new DatabaseException("bind name lookup failed " ~ db.error());
		return a;
	}

	bool next(T, R...)(out T t, out R r){
		assert(executed);
		if(position == length)
			return false;

		extract(rows[position], t, r);

		position++;
		return true;
	}

	template bindAll(T, R...){
		void bindAll(T what, R more){
			bindAllHelper(1, what, more);
		}
	}

	template exec(T, R...){
		void exec(T what, R more){
			bindAllHelper(1, what, more);
			execute();
		}
	}

	void bindAllHelper(A, T, R...)(A where, T what, R more){
		bind(where, what);
		static if(more.length)
			bindAllHelper(where + 1, more);
	}

	//void bind(T)(string name, T value) {
		//bind(bindNameLookUp(name), value);
	//}

		// This should be a template, but grrrr.
		void bind (const char[] name, const char[] value){ bind(bindNameLookUp(name), value); }
		void bind (const char[] name, int value){ bind(bindNameLookUp(name), value); }
		void bind (const char[] name, float value){ bind(bindNameLookUp(name), value); }
		void bind (const char[] name, const byte[] value){ bind(bindNameLookUp(name), value); }

	void bind(int col, const char[] value){
		if(value is null) {
			if(sqlite3_bind_null(s, col) != SQLITE_OK)
				throw new DatabaseException("bind " ~ db.error());
		} else {
			if(sqlite3_bind_text(s, col, value.ptr, cast(int) value.length, cast(void*)-1) != SQLITE_OK)
				throw new DatabaseException("bind " ~ db.error());
		}
	}

	void bind(int col, float value){
		if(sqlite3_bind_double(s, col, value) != SQLITE_OK)
			throw new DatabaseException("bind " ~ db.error());
	}
	
	void bind(int col, int value){
		if(sqlite3_bind_int(s, col, value) != SQLITE_OK)
			throw new DatabaseException("bind " ~ db.error());
	}
	
	void bind(int col, long value){
		if(sqlite3_bind_int64(s, col, value) != SQLITE_OK)
			throw new DatabaseException("bind " ~ db.error());
	}
	
	void bind(int col, const byte[] value){
		if(value is null) {
			if(sqlite3_bind_null(s, col) != SQLITE_OK)
				throw new DatabaseException("bind " ~ db.error());
		} else {
			if(sqlite3_bind_blob(s, col, cast(void*)value.ptr, cast(int) value.length, cast(void*)-1) != SQLITE_OK)
				throw new DatabaseException("bind " ~ db.error());
		}
	}

	void bind(int col, Variant v) {
		if(v.peek!long)
			bind(col, v.get!long);
		if(v.peek!ulong)
			bind(col, v.get!ulong);
		if(v.peek!int)
			bind(col, v.get!int);
		if(v.peek!string)
			bind(col, v.get!string);
		if(v.peek!float)
			bind(col, v.get!float);
		if(v.peek!(byte[]))
			bind(col, v.get!(byte[]));
		if(v.peek!(void*) && v.get!(void*) is null)
			bind(col, cast(string) null);
	}

	~this(){
		if(!finalized)
			finalize();
	}

	void finalize(){
		if(finalized)
			return;
		if(sqlite3_finalize(s) != SQLITE_OK)
			throw new DatabaseException("finalize " ~ db.error());
		finalized = true;
	}
  private:
	Variant[][] rows;
	char[][]  columnNames;
	int length;
	int position;
	bool finalized;

	sqlite3_stmt * s;

	bool executed;

}



version(sqlite_extended_metadata_available) {
import std.typecons;
struct ResultByDataObject {
	this(SqliteResult r, Tuple!(string, string)[string] mappings, Sqlite db) {
		result = r;
		this.db = db;
		this.mappings = mappings;
	}

	Tuple!(string, string)[string] mappings;

	ulong length() { return result.length; }
	bool empty() { return result.empty; }
	void popFront() { result.popFront(); }
	DataObject front() {
		return new DataObject(db, result.front.toAA, mappings);
	}
	// would it be good to add a new() method? would be valid even if empty
	// it'd just fill in the ID's at random and allow you to do the rest

	@disable this(this) { }

	SqliteResult result;
	Sqlite db;
}
}










extern(C) int callback(void* cb, int howmany, char** text, char** columns){
	if(cb is null)
		return 0;

	void delegate(char[][char[]]) onEach = *cast(void delegate(char[][char[]])*)cb;


	char[][char[]] row;
	import core.stdc.string : strlen;

	for(int a = 0; a < howmany; a++){
		sizediff_t b = strlen(columns[a]);
		char[] buf;
		buf.length = b;
		for(int c = 0; c < b; c++)
			buf[c] = columns[a][c];

		sizediff_t d = strlen(text[a]);
		char[] t;
		t.length = d;
		for(int c = 0; c < d; c++)
			t[c] = text[a][c];

		row[buf.idup] = t;
	}

	onEach(row);

	return 0;
}










extern(C){
	alias void sqlite3;
	alias void sqlite3_stmt;
	int sqlite3_changes(sqlite3*);
	int sqlite3_close(sqlite3 *);
	int sqlite3_exec(
			sqlite3*,                                  /* An open database */
			const(char) *sql,                           /* SQL to be evaluted */
			int function(void*,int,char**,char**),  /* Callback function */
			void *,                                    /* 1st argument to callback */
			char **errmsg                              /* Error msg written here */
			);
			
	int sqlite3_open(
			const(char) *filename,   /* Database filename (UTF-8) */
			sqlite3 **ppDb          /* OUT: SQLite db handle */
			);
			
/+
int sqlite3_open_v2(
  char *filename,   /* Database filename (UTF-8) */
  sqlite3 **ppDb,         /* OUT: SQLite db handle */
  int flags,              /* Flags */
  char *zVfs        /* Name of VFS module to use */
);
+/
	int sqlite3_prepare_v2(
  sqlite3 *db,            /* Database handle */
  const(char) *zSql,       /* SQL statement, UTF-8 encoded */
  int nByte,              /* Maximum length of zSql in bytes. */
  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
  char **pzTail     /* OUT: Pointer to unused portion of zSql */
);
int sqlite3_finalize(sqlite3_stmt *pStmt);
int sqlite3_step(sqlite3_stmt*);
long sqlite3_last_insert_rowid(sqlite3*);

const int SQLITE_OK = 0;
const int SQLITE_ROW = 100;
const int SQLITE_DONE = 101;

const int SQLITE_INTEGER = 1; // int
const int SQLITE_FLOAT = 2;   // float
const int SQLITE3_TEXT = 3;   // char[]
const int SQLITE_BLOB = 4;    // byte[]
const int SQLITE_NULL = 5;    // void* = null

char *sqlite3_mprintf(const char*,...);


int sqlite3_reset(sqlite3_stmt *pStmt);
int sqlite3_clear_bindings(sqlite3_stmt*);
int sqlite3_bind_parameter_index(sqlite3_stmt*, const(char) *zName);

int sqlite3_bind_blob(sqlite3_stmt*, int, void*, int n, void*);
//int sqlite3_bind_blob(sqlite3_stmt*, int, void*, int n, void(*)(void*));
int sqlite3_bind_double(sqlite3_stmt*, int, double);
int sqlite3_bind_int(sqlite3_stmt*, int, int);
int sqlite3_bind_int64(sqlite3_stmt*, int, long);
int sqlite3_bind_null(sqlite3_stmt*, int);
int sqlite3_bind_text(sqlite3_stmt*, int, const(char)*, int n, void*);
//int sqlite3_bind_text(sqlite3_stmt*, int, char*, int n, void(*)(void*));

void *sqlite3_column_blob(sqlite3_stmt*, int iCol);
int sqlite3_column_bytes(sqlite3_stmt*, int iCol);
double sqlite3_column_double(sqlite3_stmt*, int iCol);
int sqlite3_column_int(sqlite3_stmt*, int iCol);
long sqlite3_column_int64(sqlite3_stmt*, int iCol);
char *sqlite3_column_text(sqlite3_stmt*, int iCol);
int sqlite3_column_type(sqlite3_stmt*, int iCol);
char *sqlite3_column_name(sqlite3_stmt*, int N);

int sqlite3_column_count(sqlite3_stmt *pStmt);
void sqlite3_free(void*);
 char *sqlite3_errmsg(sqlite3*);

 const int SQLITE_OPEN_READONLY = 0x1;
 const int SQLITE_OPEN_READWRITE = 0x2;
 const int SQLITE_OPEN_CREATE = 0x4;
 const int SQLITE_CANTOPEN = 14;


// will need these to enable support for DataObjects here
const (char *)sqlite3_column_database_name(sqlite3_stmt*,int);
const (char *)sqlite3_column_table_name(sqlite3_stmt*,int);
const (char *)sqlite3_column_origin_name(sqlite3_stmt*,int);
}

