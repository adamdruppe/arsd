/++
	Implementation of the [arsd.database.Database] interface for
	accessing MySQL (and MariaDB) databases. Uses the official MySQL client
	library, and thus needs that installed to compile and run.

	$(PITFALL
		If you're using MySQL client library v5.0 or less,
		you must pass this to dmd: `-version=Less_Than_MySQL_51`
		This is important - otherwise you will see bizarre segfaults!
	)
+/
module arsd.mysql;


//version(MySQL_51) {
	// we good
/*} else*/ version(Less_Than_MySQL_51) {
	// we good
} else {
	// default now is mysql 5.1 or up - it has been long
	// enough that surely most everyone uses it and we don't
	// need the pragma warning anymore. Of course, the old is
	// still available if you need to explicitly opt in.
	version = MySQL_51;
}

version(Windows) {
	pragma(lib, "libmysql");
}
else {
	pragma(lib, "mysqlclient");
}

public import arsd.database;

import std.stdio;
import std.exception;
import std.string;
import std.conv;
import std.typecons;
import core.stdc.config;

/++
	Represents a query result. You can loop over this with a
	`foreach` statement to access individual [Row|rows].

	[Row]s expose both an index and associative array interface,
	so you can get `row[0]` for the first item, or `row["name"]`
	to get a column by name from the result set.
+/
class MySqlResult : ResultSet {
	private int[string] mapping;
	private MYSQL_RES* result;

	private int itemsTotal;
	private int itemsUsed;

	string sql;

	this(MYSQL_RES* r, string sql) {
		result = r;
		itemsTotal = cast(int) length();
		itemsUsed = 0;

		this.sql = sql;

		// prime it
		if(itemsTotal)
			fetchNext();
	}

	~this() {
		if(result !is null)
			mysql_free_result(result);
	}


	MYSQL_FIELD[] fields() {
		int numFields = mysql_num_fields(result);
		auto fields = mysql_fetch_fields(result);

		MYSQL_FIELD[] ret;
		for(int i = 0; i < numFields; i++) {
			ret ~= fields[i];
		}

		return ret;
	}


	/// The number of returned rows
	override size_t length() {
		if(result is null)
			return 0;
		return cast(int) mysql_num_rows(result);
	}

	/// Range primitive used by `foreach`
	/// You may also use this to check if there was any result.
	override bool empty() {
		return itemsUsed == itemsTotal;
	}

	/// Range primitive used by `foreach`
	override Row front() {
		return row;
	}

	/// Range primitive used by `foreach`
	override void popFront() {
		itemsUsed++;
		if(itemsUsed < itemsTotal) {
			fetchNext();
		}
	}

	override int getFieldIndex(string field) {
		if(mapping is null)
			makeFieldMapping();
		debug {
			if(field !in mapping)
				throw new Exception(field ~ " not in result");
		}
		return mapping[field];
	}

	private void makeFieldMapping() {
		int numFields = mysql_num_fields(result);
		auto fields = mysql_fetch_fields(result);

		if(fields is null)
			return;

		for(int i = 0; i < numFields; i++) {
			if(fields[i].name !is null)
				mapping[fromCstring(fields[i].name, fields[i].name_length)] = i;
		}
	}

	private void fetchNext() {
		assert(result);
		auto r = mysql_fetch_row(result);
		if(r is null)
			throw new Exception("there is no next row");
		uint numFields = mysql_num_fields(result);
		auto lengths = mysql_fetch_lengths(result);
		string[] row;
		// potential FIXME: not really binary safe

		columnIsNull.length = numFields;
		for(int a = 0; a < numFields; a++) {
			if(*(r+a) is null) {
				row ~= null;
				columnIsNull[a] = true;
			} else {
				row ~= fromCstring(*(r+a), *(lengths + a));
				columnIsNull[a] = false;
			}
		}

		this.row.row = row;
		this.row.resultSet = this;
	}


	override string[] fieldNames() {
		int numFields = mysql_num_fields(result);
		auto fields = mysql_fetch_fields(result);

		string[] names;
		for(int i = 0; i < numFields; i++) {
			names ~= fromCstring(fields[i].name, fields[i].name_length);
		}

		return names;
	}



	bool[] columnIsNull;
	Row row;
}

/++
	The main class for accessing the MySql database.

	---
		// connect to database with the constructor
		auto db = new MySql("localhost", "my_user", "my_password", "my_database_name");
		// use the query function to execute sql...
		// use ? for data placeholders...
		db.query("INSERT INTO people (id, name) VALUES (?, ?)", 10, "My Name");
		// and use foreach to loop over result sets
		foreach(row; db.query("SELECT id, name FROM people ORDER BY name LIMIT 10"))
			writeln(row[0], " ", row["name"]); // index and name supported
	---
+/
class MySql : Database {
	this(string host, string user, string pass, string db, uint port = 0) {
		mysql = enforce!(DatabaseException)(
			mysql_init(null),
			"Couldn't init mysql");
		enforce!(DatabaseException)(
			mysql_real_connect(mysql, toCstring(host), toCstring(user), toCstring(pass), toCstring(db), port, null, 0),
			error());

		dbname = db;

		// we want UTF8 for everything

		query("SET NAMES 'utf8'");
		//query("SET CHARACTER SET utf8");
	}

	string dbname;

	///
	override void startTransaction() {
		query("START TRANSACTION");
	}


	string sysTimeToValue(SysTime s) {
		return "cast('" ~ escape(s.toISOExtString()) ~ "' as datetime)";
	}

	string error() {
		return fromCstring(mysql_error(mysql));
	}

	void close() {
		if(mysql) {
			mysql_close(mysql);
			mysql = null;
		}
	}

	~this() {
		close();
	}

	///
	int lastInsertId() {
		return cast(int) mysql_insert_id(mysql);
	}



	/// Builds and executes an INERT INTO statement
	int insert(string table, MySqlResult result, string[string] columnsToModify, string[] columnsToSkip) {
		assert(!result.empty);
		string sql = "INSERT INTO `" ~ table ~ "` ";

		string cols = "(";
		string vals = "(";
		bool outputted = false;

		string[string] columns;
		auto cnames = result.fieldNames;
		foreach(i, col; result.front.toStringArray) {
			bool skipMe = false;
			foreach(skip; columnsToSkip) {
				if(cnames[i] == skip) {
					skipMe = true;
					break;
				}
			}
			if(skipMe)
				continue;

			if(outputted) {
				cols ~= ",";
				vals ~= ",";
			} else
				outputted = true;

			cols ~= cnames[i];

			if(result.columnIsNull[i] && cnames[i] !in columnsToModify)
				vals ~= "NULL";
			else {
				string v = col;
				if(cnames[i] in columnsToModify)
					v = columnsToModify[cnames[i]];

				vals ~= "'" ~ escape(v) ~ "'";

			}
		}

		cols ~= ")";
		vals ~= ")";

		sql ~= cols ~ " VALUES " ~ vals;

		query(sql);

		result.popFront;

		return lastInsertId;
	}

	string escape(string str) {
		ubyte[] buffer = new ubyte[str.length * 2 + 1];
		buffer.length = mysql_real_escape_string(mysql, buffer.ptr, cast(cstring) str.ptr, cast(uint) str.length);

		return cast(string) buffer;
	}

	string escapeBinaryString(const(ubyte)[] data) {
		return tohexsql(data);
	}

	string escaped(T...)(string sql, T t) {
		static if(t.length > 0) {
			string fixedup;
			int pos = 0;


			void escAndAdd(string str, int q) {
				ubyte[] buffer = new ubyte[str.length * 2 + 1];
				buffer.length = mysql_real_escape_string(mysql, buffer.ptr, cast(cstring) str.ptr, str.length);

				fixedup ~= sql[pos..q] ~ '\'' ~ cast(string) buffer ~ '\'';

			}

			foreach(a; t) {
				int q = sql[pos..$].indexOf("?");
				if(q == -1)
					break;
				q += pos;

				static if(__traits(compiles, t is null)) {
					if(t is null)
						fixedup  ~= sql[pos..q] ~ "NULL";
					else
						escAndAdd(to!string(*a), q);
				} else {
					string str = to!string(a);
					escAndAdd(str, q);
				}

				pos = q+1;
			}

			fixedup ~= sql[pos..$];

			sql = fixedup;

			//writefln("\n\nExecuting sql: %s", sql);
		}

		return sql;
	}


	/// Gets a minimal ORM object from a query
	ResultByDataObject!R queryDataObject(R = DataObject, T...)(string sql, T t) {
		// modify sql for the best data object grabbing
		sql = fixupSqlForDataObjectUse(sql);

		auto magic = query(sql, t);
		return ResultByDataObject!R(cast(MySqlResult) magic, this);
	}


	/// ditto
	ResultByDataObject!R queryDataObjectWithCustomKeys(R = DataObject, T...)(string[string] keyMapping, string sql, T t) {
		sql = fixupSqlForDataObjectUse(sql, keyMapping);

		auto magic = query(sql, t);
		return ResultByDataObject!R(cast(MySqlResult) magic, this);
	}



	///
	int affectedRows() {
		return cast(int) mysql_affected_rows(mysql);
	}

	override ResultSet queryImpl(string sql, Variant[] args...) {
		sql = escapedVariants(this, sql, args);

		enforce!(DatabaseException)(
			!mysql_query(mysql, toCstring(sql)),
		error() ~ " :::: " ~ sql);

		return new MySqlResult(mysql_store_result(mysql), sql);
	}
/+
	Result queryOld(T...)(string sql, T t) {
		sql = escaped(sql, t);

		if(sql.length == 0)
			throw new DatabaseException("empty query");
		/*
		static int queryCount = 0;
		queryCount++;
		if(sql.indexOf("INSERT") != -1)
			stderr.writefln("%d: %s", queryCount, sql.replace("\n", " ").replace("\t", ""));
		*/

		version(dryRun) {
			pragma(msg, "This is a dry run compile, no queries will be run");
			writeln(sql);
			return Result(null, null);
		}

		enforceEx!(DatabaseException)(
			!mysql_query(mysql, toCstring(sql)),
		error() ~ " :::: " ~ sql);

		return Result(mysql_store_result(mysql), sql);
	}
+/
/+
	struct ResultByAssoc {
		this(Result* r) {
			result = r;
			fields = r.fieldNames();
		}

		ulong length() { return result.length; }
		bool empty() { return result.empty; }
		void popFront() { result.popFront(); }
		string[string] front() {
			auto r = result.front;
			string[string] ret;
			foreach(i, a; r) {
				ret[fields[i]] = a;
			}

			return ret;
		}

		@disable this(this) { }

		string[] fields;
		Result* result;
	}


	struct ResultByStruct(T) {
		this(Result* r) {
			result = r;
			fields = r.fieldNames();
		}

		ulong length() { return result.length; }
		bool empty() { return result.empty; }
		void popFront() { result.popFront(); }
		T front() {
			auto r = result.front;
			string[string] ret;
			foreach(i, a; r) {
				ret[fields[i]] = a;
			}

			T s;
			// FIXME: should use tupleOf
			foreach(member; s.tupleof) {
				if(member.stringof in ret)
					member = to!(typeof(member))(ret[member]);
			}

			return s;
		}

		@disable this(this) { }

		string[] fields;
		Result* result;
	}
+/

/+


	struct Result {
		private Result* heaped() {
			auto r = new Result(result, sql, false);

			r.tupleof = this.tupleof;

			this.itemsTotal = 0;
			this.result = null;

			return r;
		}

		this(MYSQL_RES* r, string sql, bool prime = true) {
			result = r;
			itemsTotal = length;
			itemsUsed = 0;
			this.sql = sql;
			// prime it here
			if(prime && itemsTotal)
				fetchNext();
		}

		string sql;

		~this() {
			if(result !is null)
			mysql_free_result(result);
		}

		/+
		string[string][] fetchAssoc() {

		}
		+/

		ResultByAssoc byAssoc() {
			return ResultByAssoc(&this);
		}

		ResultByStruct!(T) byStruct(T)() {
			return ResultByStruct!(T)(&this);
		}

		string[] fieldNames() {
			int numFields = mysql_num_fields(result);
			auto fields = mysql_fetch_fields(result);

			string[] names;
			for(int i = 0; i < numFields; i++) {
				names ~= fromCstring(fields[i].name);
			}

			return names;
		}

		MYSQL_FIELD[] fields() {
			int numFields = mysql_num_fields(result);
			auto fields = mysql_fetch_fields(result);

			MYSQL_FIELD[] ret;
			for(int i = 0; i < numFields; i++) {
				ret ~= fields[i];
			}

			return ret;
		}

		ulong length() {
			if(result is null)
				return 0;
			return mysql_num_rows(result);
		}

		bool empty() {
			return itemsUsed == itemsTotal;
		}

		Row front() {
			return row;
		}

		void popFront() {
			itemsUsed++;
			if(itemsUsed < itemsTotal) {
				fetchNext();
			}
		}

		void fetchNext() {
			auto r = mysql_fetch_row(result);
			uint numFields = mysql_num_fields(result);
			uint* lengths = mysql_fetch_lengths(result);
			row.length = 0;
			// potential FIXME: not really binary safe

			columnIsNull.length = numFields;
			for(int a = 0; a < numFields; a++) {
				if(*(r+a) is null) {
					row ~= null;
					columnIsNull[a] = true;
				} else {
					row ~= fromCstring(*(r+a), *(lengths + a));
					columnIsNull[a] = false;
				}
			}
		}

		@disable this(this) {}
		private MYSQL_RES* result;

		ulong itemsTotal;
		ulong itemsUsed;

		alias string[] Row;

		Row row;
		bool[] columnIsNull; // FIXME: should be part of the row
	}
+/
	MYSQL* getHandle() {
		return mysql;
	}

  private:
	MYSQL* mysql;
}

struct ResultByDataObject(ObjType) if (is(ObjType : DataObject)) {
	this(MySqlResult r, MySql mysql) {
		result = r;
		auto fields = r.fields();
		this.mysql = mysql;

		foreach(i, f; fields) {
			string tbl = fromCstring(f.org_table is null ? f.table : f.org_table, f.org_table is null ? f.table_length : f.org_table_length);
			mappings[fromCstring(f.name)] = tuple(
					tbl,
					fromCstring(f.org_name is null ? f.name : f.org_name, f.org_name is null ? f.name_length : f.org_name_length));
		}


	}

	Tuple!(string, string)[string] mappings;

	ulong length() { return result.length; }
	bool empty() { return result.empty; }
	void popFront() { result.popFront(); }
	ObjType front() {
		return new ObjType(mysql, result.front.toAA, mappings);
	}
	// would it be good to add a new() method? would be valid even if empty
	// it'd just fill in the ID's at random and allow you to do the rest

	@disable this(this) { }

	MySqlResult result;
	MySql mysql;
}


// thanks to 0xEAB on discord for sending me initial prepared statement support

struct Statement
{
    ~this()
    {
        if (this.statement !is null)
        {
            this.statement.mysql_stmt_close();
            this.statement = null;
        }
    }

    void reset()
    {
	mysql_stmt_reset(statement);
    }

private:
    MYSQL_STMT* statement;
    MYSQL_BIND[] params;
}

Statement* prepare(MySql m, string query) @trusted
{
    MYSQL_STMT* s = m.getHandle.mysql_stmt_init();
    immutable x = s.mysql_stmt_prepare(query.toStringz, cast(int) query.length);

    if (x != 0)
    {
        throw new Exception(m.getHandle.mysql_error.fromCstring);
    }

    return new Statement(s);
}

import std.traits : isNumeric;

void bindParameter(T)(Statement* s, ref T value) if (isNumeric!T)
{
    import std.traits : isUnsigned;

    MYSQL_BIND p = MYSQL_BIND();

    p.buffer = &value;
    p.buffer_type = mySqlType!T;
    p.is_unsigned = isUnsigned!T;

    s.params ~= p;
    immutable x = s.statement.mysql_stmt_bind_param(&(s.params[$ - 1]));

    if (x != 0)
    {
        throw new Exception(s.statement.mysql_stmt_error.fromStringz.to!string);
    }
}

void bindParameterNull(Statement* s)
{
    MYSQL_BIND p = MYSQL_BIND();

    p.buffer_type = enum_field_types.MYSQL_TYPE_NULL;

    s.params ~= p;
    immutable x = s.statement.mysql_stmt_bind_param(null);

    if (x != 0)
    {
        throw new Exception(s.statement.mysql_stmt_error.fromStringz.to!string);
    }
}

void bindParameter(T)(Statement* s, T value) if (is(T == string))
{
    import std.traits : isUnsigned;

    MYSQL_BIND p = MYSQL_BIND();

    p.buffer = cast(void*) value.toCstring();
    p.buffer_type = mySqlType!string;
    p.buffer_length = value.length;

    s.params ~= p;
    immutable x = s.statement.mysql_stmt_bind_param(&s.params[$ - 1]);

    if (x != 0)
    {
        throw new Exception(s.statement.mysql_stmt_error.fromStringz.to!string);
    }
}

void execute(Statement* s) @trusted
{
    immutable x = s.statement.mysql_stmt_execute();

    if (x != 0)
    {
        throw new Exception(s.statement.mysql_stmt_error.fromStringz.to!string);
    }
}


extern(System) {
	/*
		from <my_alloc.h>
		original header actually contains members,
		but guess we don't need them here
	*/
	struct USED_MEM;

	/*
		from <my_alloc.h>
	*/
	struct MEM_ROOT
	{
		USED_MEM* free; /* blocks with free memory in it */
		USED_MEM* used; /* blocks almost without free memory */
		USED_MEM* pre_alloc; /* preallocated block */
		/* if block have less memory it will be put in 'used' list */
		size_t min_malloc;
		size_t block_size; /* initial block size */
		uint block_num; /* allocated blocks counter */
		/*
		first free block in queue test counter (if it exceed
		MAX_BLOCK_USAGE_BEFORE_DROP block will be dropped in 'used' list)
		*/
		uint first_block_usage;

		void function () error_handler;
	}

	/*
		from <mysql_com.h>

		original header actually contains members,
		but guess we don't need them here
	*/
	struct NET;

	/* from <mysql_com.h> */
	enum MYSQL_ERRMSG_SIZE = 512;

	/* from <mysql_com.h> */
	enum enum_field_types {
		MYSQL_TYPE_DECIMAL, MYSQL_TYPE_TINY,
		MYSQL_TYPE_SHORT,  MYSQL_TYPE_LONG,
		MYSQL_TYPE_FLOAT,  MYSQL_TYPE_DOUBLE,
		MYSQL_TYPE_NULL,   MYSQL_TYPE_TIMESTAMP,
		MYSQL_TYPE_LONGLONG,MYSQL_TYPE_INT24,
		MYSQL_TYPE_DATE,   MYSQL_TYPE_TIME,
		MYSQL_TYPE_DATETIME, MYSQL_TYPE_YEAR,
		MYSQL_TYPE_NEWDATE, MYSQL_TYPE_VARCHAR,
		MYSQL_TYPE_BIT,

			/*
				mysql-5.6 compatibility temporal types.
				They're only used internally for reading RBR
				mysql-5.6 binary log events and mysql-5.6 frm files.
				They're never sent to the client.
			*/
			MYSQL_TYPE_TIMESTAMP2,
			MYSQL_TYPE_DATETIME2,
			MYSQL_TYPE_TIME2,

			MYSQL_TYPE_NEWDECIMAL=246,

		MYSQL_TYPE_ENUM=247,
		MYSQL_TYPE_SET=248,
		MYSQL_TYPE_TINY_BLOB=249,
		MYSQL_TYPE_MEDIUM_BLOB=250,
		MYSQL_TYPE_LONG_BLOB=251,
		MYSQL_TYPE_BLOB=252,
		MYSQL_TYPE_VAR_STRING=253,
		MYSQL_TYPE_STRING=254,
		MYSQL_TYPE_GEOMETRY=255
	}

	/* from <my_list.h>*/
	struct LIST
	{
		LIST* prev;
		LIST* next;
		void* data;
	}

	struct MYSQL;
	struct MYSQL_RES;
	/* typedef */ alias const(ubyte)* cstring;

	alias my_bool = char;
	alias my_ulonglong = ulong;

	struct MYSQL_FIELD {
		  cstring name;                 /* Name of column */
		  cstring org_name;             /* Original column name, if an alias */
		  cstring table;                /* Table of column if column was a field */
		  cstring org_table;            /* Org table name, if table was an alias */
		  cstring db;                   /* Database for table */
		  cstring catalog;	      /* Catalog for table */
		  cstring def;                  /* Default value (set by mysql_list_fields) */
		  c_ulong length;       /* Width of column (create length) */
		  c_ulong max_length;   /* Max width for selected set */
		  uint name_length;
		  uint org_name_length;
		  uint table_length;
		  uint org_table_length;
		  uint db_length;
		  uint catalog_length;
		  uint def_length;
		  uint flags;         /* Div flags */
		  uint decimals;      /* Number of decimals in field */
		  uint charsetnr;     /* Character set */
		  uint type; /* Type of field. See mysql_com.h for types */
		  // type is actually an enum btw

		version(MySQL_51) {
			void* extension;
		}
	}

	struct MYSQL_ROWS
	{
		MYSQL_ROWS* next; /* list of rows */
		MYSQL_ROW data;
		c_ulong length;
	}

	alias MYSQL_ROW_OFFSET = MYSQL_ROWS*; /* offset to current row */

	struct EMBEDDED_QUERY_RESULT;

	struct MYSQL_DATA
	{
		MYSQL_ROWS* data;
		EMBEDDED_QUERY_RESULT* embedded_info;
		MEM_ROOT alloc;
		my_ulonglong rows;
		uint fields;

		version(MySQL_51) {
			/* extra info for embedded library */
			void* extension;
		}
	}

	/* statement state */
	enum enum_mysql_stmt_state
	{
		MYSQL_STMT_INIT_DONE = 1,
		MYSQL_STMT_PREPARE_DONE = 2,
		MYSQL_STMT_EXECUTE_DONE = 3,
		MYSQL_STMT_FETCH_DONE = 4
	}

	enum enum_stmt_attr_type
	{
		/**
			When doing mysql_stmt_store_result calculate max_length attribute
			of statement metadata. This is to be consistent with the old API,
			where this was done automatically.
			In the new API we do that only by request because it slows down
			mysql_stmt_store_result sufficiently.
		*/
		STMT_ATTR_UPDATE_MAX_LENGTH = 0,
		/**
			unsigned long with combination of cursor flags (read only, for update, etc)
		*/
		STMT_ATTR_CURSOR_TYPE = 1,
		/**
			Amount of rows to retrieve from server per one fetch if using cursors.
			Accepts unsigned long attribute in the range 1 - ulong_max
		*/
		STMT_ATTR_PREFETCH_ROWS = 2
	}

	struct MYSQL_BIND
	{
		c_ulong* length; /* output length pointer */
		my_bool* is_null; /* Pointer to null indicator */
		void* buffer; /* buffer to get/put data */
		/* set this if you want to track data truncations happened during fetch */
		my_bool* error;
		ubyte* row_ptr; /* for the current data position */
		void function (NET* net, MYSQL_BIND* param) store_param_func;
		void function (MYSQL_BIND*, MYSQL_FIELD*, ubyte** row) fetch_result;
		void function (MYSQL_BIND*, MYSQL_FIELD*, ubyte** row) skip_result;
		/* output buffer length, must be set when fetching str/binary */
		c_ulong buffer_length;
		c_ulong offset; /* offset position for char/binary fetch */
		c_ulong length_value; /* Used if length is 0 */
		uint param_number; /* For null count and error messages */
		uint pack_length; /* Internal length for packed data */
		enum_field_types buffer_type; /* buffer type */
		my_bool error_value; /* used if error is 0 */
		my_bool is_unsigned; /* set if integer type is unsigned */
		my_bool long_data_used; /* If used with mysql_send_long_data */
		my_bool is_null_value; /* Used if is_null is 0 */
		void* extension;
	}

	struct st_mysql_stmt_extension;

	/* statement handler */
	struct MYSQL_STMT
	{
		MEM_ROOT mem_root; /* root allocations */
		LIST list; /* list to keep track of all stmts */
		MYSQL* mysql; /* connection handle */
		MYSQL_BIND* params; /* input parameters */
		MYSQL_BIND* bind; /* output parameters */
		MYSQL_FIELD* fields; /* result set metadata */
		MYSQL_DATA result; /* cached result set */
		MYSQL_ROWS* data_cursor; /* current row in cached result */
		/*
		mysql_stmt_fetch() calls this function to fetch one row (it's different
		for buffered, unbuffered and cursor fetch).
		*/
		int function (MYSQL_STMT* stmt, ubyte** row) read_row_func;
		/* copy of mysql->affected_rows after statement execution */
		my_ulonglong affected_rows;
		my_ulonglong insert_id; /* copy of mysql->insert_id */
		c_ulong stmt_id; /* Id for prepared statement */
		c_ulong flags; /* i.e. type of cursor to open */
		c_ulong prefetch_rows; /* number of rows per one COM_FETCH */
		/*
		Copied from mysql->server_status after execute/fetch to know
		server-side cursor status for this statement.
		*/
		uint server_status;
		uint last_errno; /* error code */
		uint param_count; /* input parameter count */
		uint field_count; /* number of columns in result set */
		enum_mysql_stmt_state state; /* statement state */
		char[MYSQL_ERRMSG_SIZE] last_error; /* error message */
		char[6] sqlstate;
		/* Types of input parameters should be sent to server */
		my_bool send_types_to_server;
		my_bool bind_param_done; /* input buffers were supplied */
		ubyte bind_result_done; /* output buffers were supplied */
		/* mysql_stmt_close() had to cancel this result */
		my_bool unbuffered_fetch_cancelled;
		/*
		Is set to true if we need to calculate field->max_length for
		metadata fields when doing mysql_stmt_store_result.
		*/
		my_bool update_max_length;
		st_mysql_stmt_extension* extension;
	}

	/* typedef */ alias cstring* MYSQL_ROW;

	cstring mysql_get_client_info();
	MYSQL* mysql_init(MYSQL*);
	uint mysql_errno(MYSQL*);
	cstring mysql_error(MYSQL*);

	MYSQL* mysql_real_connect(MYSQL*, cstring, cstring, cstring, cstring, uint, cstring, c_ulong);

	int mysql_query(MYSQL*, cstring);

	void mysql_close(MYSQL*);

	ulong mysql_num_rows(MYSQL_RES*);
	uint mysql_num_fields(MYSQL_RES*);
	bool mysql_eof(MYSQL_RES*);

	ulong mysql_affected_rows(MYSQL*);
	ulong mysql_insert_id(MYSQL*);

	MYSQL_RES* mysql_store_result(MYSQL*);
	MYSQL_RES* mysql_use_result(MYSQL*);

	MYSQL_ROW mysql_fetch_row(MYSQL_RES *);
	c_ulong* mysql_fetch_lengths(MYSQL_RES*);
	MYSQL_FIELD* mysql_fetch_field(MYSQL_RES*);
	MYSQL_FIELD* mysql_fetch_fields(MYSQL_RES*);

	uint mysql_real_escape_string(MYSQL*, ubyte* to, cstring from, c_ulong length);

	void mysql_free_result(MYSQL_RES*);

	MYSQL_STMT* mysql_stmt_init (MYSQL* mysql);
	int mysql_stmt_prepare (MYSQL_STMT* stmt, const(char)* query, c_ulong length);
	int mysql_stmt_execute (MYSQL_STMT* stmt);
	my_bool mysql_stmt_bind_param (MYSQL_STMT* stmt, MYSQL_BIND* bnd);
	my_bool mysql_stmt_close (MYSQL_STMT* stmt);
	my_bool mysql_stmt_free_result (MYSQL_STMT* stmt);
	my_bool mysql_stmt_reset (MYSQL_STMT* stmt);
	uint mysql_stmt_errno (MYSQL_STMT* stmt);
	const(char)* mysql_stmt_error (MYSQL_STMT* stmt);
	const(char)* mysql_stmt_sqlstate (MYSQL_STMT* stmt);
	my_ulonglong mysql_stmt_num_rows (MYSQL_STMT* stmt);
	my_ulonglong mysql_stmt_affected_rows (MYSQL_STMT* stmt);
	my_ulonglong mysql_stmt_insert_id (MYSQL_STMT* stmt);

}

import std.string;
cstring toCstring(string c) {
	return cast(cstring) toStringz(c);
}

import std.array;
string fromCstring(cstring c, size_t len = size_t.max) {
	string ret;
	if(c is null)
		return null;
	if(len == 0)
		return "";
	if(len == size_t.max) {
		auto iterator = c;
		len = 0;
		while(*iterator) {
			iterator++;
			len++;
		}
		assert(len >= 0);
	}

	ret = cast(string) (c[0 .. len].idup);

	return ret;
}

enum_field_types getMySqlType(T)() {
	static if (is(T == bool))
		return enum_field_types.MYSQL_TYPE_TINY;

	static if (is(T == char))
		return enum_field_types.MYSQL_TYPE_TINY;

		static if (is(T == byte) || is(T == ubyte))
		return enum_field_types.MYSQL_TYPE_TINY;

	else static if (is(T == short) || is(T == ushort))
		return enum_field_types.MYSQL_TYPE_SHORT;

	else static if (is(T == int) || is(T == uint))
		return enum_field_types.MYSQL_TYPE_LONG;

	else static if (is(T == long) || is(T == ulong))
		return enum_field_types.MYSQL_TYPE_LONGLONG;

	else static if (is(T == string))
		return enum_field_types.MYSQL_TYPE_STRING;

	else static if (is(T == float))
		return enum_field_types.MYSQL_TYPE_FLOAT;

	else static if (is(T == double))
		return enum_field_types.MYSQL_TYPE_DOUBLE;

	//else static if (is(T == byte[]))
	//	return enum_field_types.MYSQL_TYPE_BLOB;

	else
		static assert("No MySQL equivalent known for " ~ T);
}

enum enum_field_types mySqlType(T) = getMySqlType!T;

// FIXME: this should work generically with all database types and them moved to database.d
///
Ret queryOneRow(Ret = Row, DB, string file = __FILE__, size_t line = __LINE__, T...)(DB db, string sql, T t) if(
	(is(DB : Database))
	// && (is(Ret == Row) || is(Ret : DataObject)))
	)
{
	static if(is(Ret : DataObject) && is(DB == MySql)) {
		auto res = db.queryDataObject!Ret(sql, t);
		if(res.empty)
			throw new EmptyResultException("result was empty", file, line);
		return res.front;
	} else static if(is(Ret == Row)) {
		auto res = db.query(sql, t);
		if(res.empty)
			throw new EmptyResultException("result was empty", file, line);
		return res.front;
	} else static assert(0, "Unsupported single row query return value, " ~ Ret.stringof);
}

///
class EmptyResultException : Exception {
	this(string message, string file = __FILE__, size_t line = __LINE__) {
		super(message, file, line);
	}
}


/*
void main() {
	auto mysql = new MySql("localhost", "uname", "password", "test");
	scope(exit) delete mysql;

	mysql.query("INSERT INTO users (id, password) VALUES (?, ?)", 10, "lol");

	foreach(row; mysql.query("SELECT * FROM users")) {
		writefln("%s %s %s %s", row["id"], row[0], row[1], row["username"]);
	}
}
*/

/*
struct ResultByStruct(T) {
	this(MySql.Result* r) {
		result = r;
		fields = r.fieldNames();
	}

	ulong length() { return result.length; }
	bool empty() { return result.empty; }
	void popFront() { result.popFront(); }
	T front() {
		auto r = result.front;
		T ret;
		foreach(i, a; r) {
			ret[fields[i]] = a;
		}

		return ret;
	}

	@disable this(this) { }

	string[] fields;
	MySql.Result* result;
}
*/


/+
	mysql.linq.tablename.field[key] // select field from tablename where id = key

	mysql.link["name"].table.field[key] // select field from table where name = key


	auto q = mysql.prepQuery("select id from table where something");
	q.sort("name");
	q.limit(start, count);
	q.page(3, pagelength = ?);

	q.execute(params here); // returns the same Result range as query
+/

/*
void main() {
	auto db = new MySql("localhost", "uname", "password", "test");
	foreach(item; db.queryDataObject("SELECT users.*, username
		FROM users, password_manager_accounts
		WHERE password_manager_accounts.user_id =  users.id LIMIT 5")) {
		writefln("item: %s, %s", item.id, item.username);
		item.first = "new";
		item.last = "new2";
		item.username = "kill";
		//item.commitChanges();
	}
}
*/


/*
Copyright: Adam D. Ruppe, 2009 - 2011
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Adam D. Ruppe, with contributions from Nick Sabalausky

        Copyright Adam D. Ruppe 2009 - 2011.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
        http://www.boost.org/LICENSE_1_0.txt)
*/

