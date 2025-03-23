/++
	Uses libpq implement the [arsd.database.Database] interface.

	Requires the official pq library from Postgres to be installed to build
	and to use. Note that on Windows, it is often distributed as `libpq.lib`.
	You will have to copy or rename that to `pq.lib` for dub or dmd to automatically
	find it. You will also likely need to add the lib search path yourself on
	both Windows and Linux systems (on my Linux box, it is `-L-L/usr/local/pgsql/lib`
	to dmd. You can also list things your app's dub.json's lflags too. Note on the
	Microsoft linker, the flag is called `/LIBPATH`.)

	For example, for the default Postgres install on Windows, try:

	```
		"lflags-windows": [ "/LIBPATH:C:/Program Files/PostgreSQL/<VERSION>/lib" ],
	```

	In your dub.json.

	When you distribute your application, the user will want to install libpq client on
	Linux, and on Windows, you may want to include the libpq.dll in your distribution.
	Note it may also depend on OpenSSL ssl and crypto dlls and libintl.dll as well. These
	should be found in the PostgreSQL lib and/or bin folders (check them both!).
+/
module arsd.postgres;

version(Windows)
	pragma(lib, "libpq");
else
	pragma(lib, "pq");

public import arsd.database;

import std.string;
import std.exception;

// remember to CREATE DATABASE name WITH ENCODING 'utf8'
//
// http://www.postgresql.org/docs/8.0/static/libpq-exec.html
// ExecParams, PQPrepare, PQExecPrepared
//
// SQL: `DEALLOCATE name` is how to dealloc a prepared statement.

/++
	The PostgreSql implementation of the [Database] interface.

	You should construct this class, but then use it through the
	interface functions.

	---
	auto db = new PostgreSql("dbname=name");
	foreach(row; db.query("SELECT id, data FROM table_name"))
		writeln(row[0], " = ", row[1]);
	---
+/
class PostgreSql : Database {
	/// `dbname=your_database_name` is probably the most common connection string. See section "33.1.1.1. Keyword/Value Connection Strings" on https://www.postgresql.org/docs/10/libpq-connect.html
	this(string connectionString) {
		this.connectionString = connectionString;
		conn = PQconnectdb(toStringz(connectionString));
		if(conn is null)
			throw new DatabaseException("Unable to allocate PG connection object");
		if(PQstatus(conn) != CONNECTION_OK)
			throw new DatabaseException(error());
		query("SET NAMES 'utf8'"); // D does everything with utf8
	}

	string connectionString;

	~this() {
		PQfinish(conn);
	}

	string sysTimeToValue(SysTime s) {
		return "'" ~ escape(s.toISOExtString()) ~ "'::timestamptz";
	}

	/**
		Prepared statement support

		This will be added to the Database interface eventually in some form,
		but first I need to implement it for all my providers.

		The common function of those 4 will be what I put in the interface.
	*/

	ResultSet executePreparedStatement(T...)(string name, T args) {
		const(char)*[args.length] argsStrings;

		foreach(idx, arg; args) {
			// FIXME: optimize to remove allocations here
			import std.conv;
			static if(!is(typeof(arg) == typeof(null)))
				argsStrings[idx] = toStringz(to!string(arg));
			// else make it null
		}

		auto res = PQexecPrepared(conn, toStringz(name), argsStrings.length, argsStrings.ptr, null, null, 0);

		int ress = PQresultStatus(res);
		if(ress != PGRES_TUPLES_OK
			&& ress != PGRES_COMMAND_OK)
			throw new DatabaseException(error());

		return new PostgresResult(res);

	}

	///
	override void startTransaction() {
		query("START TRANSACTION");
	}

	ResultSet queryImpl(string sql, Variant[] args...) {
		sql = escapedVariants(this, sql, args);

		bool first_retry = true;

		retry:

		auto res = PQexec(conn, toStringz(sql));
		int ress = PQresultStatus(res);
		// https://www.postgresql.org/docs/current/libpq-exec.html
		// FIXME: PQresultErrorField can get a lot more info in a more structured way
		if(ress != PGRES_TUPLES_OK
			&& ress != PGRES_COMMAND_OK)
		{
			if(first_retry && error() == "no connection to the server\n") {
				first_retry = false;
				// try to reconnect...
				PQfinish(conn);
				conn = PQconnectdb(toStringz(connectionString));
				if(conn is null)
					throw new DatabaseException("Unable to allocate PG connection object");
				if(PQstatus(conn) != CONNECTION_OK)
					throw new DatabaseException(error());
				goto retry;
			}
			throw new DatabaseException(error());
		}

		return new PostgresResult(res);
	}

	string escape(string sqlData) {
		char* buffer = (new char[sqlData.length * 2 + 1]).ptr;
		ulong size = PQescapeString (buffer, sqlData.ptr, sqlData.length);

		string ret = assumeUnique(buffer[0.. cast(size_t) size]);

		return ret;
	}

	string escapeBinaryString(const(ubyte)[] data) {
		// must include '\x ... ' here
		size_t len;
		char* buf = PQescapeByteaConn(conn, data.ptr, data.length, &len);
		if(buf is null)
			throw new Exception("pgsql out of memory escaping binary string");

		string res;
		if(len == 0)
			res = "''";
		else
			res = cast(string) ("'" ~ buf[0 .. len - 1] ~ "'"); // gotta cut the zero terminator off

		PQfreemem(buf);

		return res;
	}


	///
	string error() {
		return copyCString(PQerrorMessage(conn));
	}

	private:
		PGconn* conn;
}

private string toLowerFast(string s) {
	import std.ascii : isUpper;
	foreach (c; s)
		if (c >= 0x80 || isUpper(c))
			return toLower(s);
	return s;
}

///
class PostgresResult : ResultSet {
	// name for associative array to result index
	int getFieldIndex(string field) {
		if(mapping is null)
			makeFieldMapping();
		field = field.toLowerFast;
		if(field in mapping)
			return mapping[field];
		else throw new Exception("no mapping " ~ field);
	}


	string[] fieldNames() {
		if(mapping is null)
			makeFieldMapping();
		return columnNames;
	}

	// this is a range that can offer other ranges to access it
	bool empty() {
		return position == numRows;
	}

	Row front() {
		return row;
	}

	int affectedRows() @system {
		auto g = PQcmdTuples(res);
		if(g is null)
			return 0;
		int num;
		while(*g) {
			num *= 10;
			num += *g - '0';
			g++;
		}
		return num;
	}

	void popFront() {
		position++;
		if(position < numRows)
			fetchNext();
	}

	override size_t length() {
		return numRows;
	}

	this(PGresult* res) {
		this.res = res;
		numFields = PQnfields(res);
		numRows = PQntuples(res);

		if(numRows)
			fetchNext();
	}

	~this() {
		PQclear(res);
	}

	private:
		PGresult* res;
		int[string] mapping;
		string[] columnNames;
		int numFields;

		int position;

		int numRows;

		Row row;

		void fetchNext() {
			Row r;
			r.resultSet = this;
			DatabaseDatum[] row;

			for(int i = 0; i < numFields; i++) {
				string a;

				if(PQgetisnull(res, position, i))
					a = null;
				else {
					switch(PQfformat(res, i)) {
						case 0: // text representation
							switch(PQftype(res, i)) {
								case BYTEAOID:
									size_t len;
									char* c = PQunescapeBytea(PQgetvalue(res, position, i), &len);

									a = cast(string) c[0 .. len].idup;

									PQfreemem(c);
								break;
								default:
									a = copyCString(PQgetvalue(res, position, i), PQgetlength(res, position, i));
							}
						break;
						case 1: // binary representation
							throw new Exception("unexpected format returned by pq");
						default:
							throw new Exception("unknown pq format");
					}

				}
				row ~= DatabaseDatum(a);
			}

			r.row = row;
			this.row = r;
		}

		void makeFieldMapping() {
			for(int i = 0; i < numFields; i++) {
				string a = copyCString(PQfname(res, i));

				columnNames ~= a;
				mapping[a] = i;
			}

		}
}

string copyCString(const char* c, int actualLength = -1) @system {
	const(char)* a = c;
	if(a is null)
		return null;

	string ret;
	if(actualLength == -1)
		while(*a) {
			ret ~= *a;
			a++;
		}
	else {
		ret = a[0..actualLength].idup;
	}

	return ret;
}

extern(C) {
	struct PGconn {};
	struct PGresult {};

	void PQfinish(PGconn*);
	PGconn* PQconnectdb(const char*);

	int PQstatus(PGconn*); // FIXME check return value

	const (char*) PQerrorMessage(PGconn*);

	PGresult* PQexec(PGconn*, const char*);
	void PQclear(PGresult*);

	PGresult* PQprepare(PGconn*, const char* stmtName, const char* query, int nParams, const void* paramTypes);

	PGresult* PQexecPrepared(PGconn*, const char* stmtName, int nParams, const char** paramValues, const int* paramLengths, const int* paramFormats, int resultFormat);

	int PQresultStatus(PGresult*); // FIXME check return value

	int PQnfields(PGresult*); // number of fields in a result
	const(char*) PQfname(PGresult*, int); // name of field

	int PQntuples(PGresult*); // number of rows in result
	const(char*) PQgetvalue(PGresult*, int row, int column);

	size_t PQescapeString (char *to, const char *from, size_t length);

	enum int CONNECTION_OK = 0;
	enum int PGRES_COMMAND_OK = 1;
	enum int PGRES_TUPLES_OK = 2;

	int PQgetlength(const PGresult *res,
			int row_number,
			int column_number);
	int PQgetisnull(const PGresult *res,
			int row_number,
			int column_number);

	int PQfformat(const PGresult *res, int column_number);

	alias Oid = int;
	enum BYTEAOID = 17;
	Oid PQftype(const PGresult* res, int column_number);

	char *PQescapeByteaConn(PGconn *conn,
                                 const ubyte *from,
                                 size_t from_length,
                                 size_t *to_length);
	char *PQunescapeBytea(const char *from, size_t *to_length);
	void PQfreemem(void *ptr);

	char* PQcmdTuples(PGresult *res);

}

/*
import std.stdio;
void main() {
	auto db = new PostgreSql("dbname = test");

	db.query("INSERT INTO users (id, name) values (?, ?)", 30, "hello mang");

	foreach(line; db.query("SELECT * FROM users")) {
		writeln(line[0], line["name"]);
	}
}
*/
