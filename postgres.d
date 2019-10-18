/// minimal libpq wrapper
module arsd.postgres;
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
	/// dbname = name  is probably the most common connection string
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
		char*[args.length] argsStrings;

		foreach(idx, arg; args) {
			// FIXME: optimize to remove allocations here
			static if(!is(typeof(arg) == typeof(null)))
				argsStrings[idx] = toStringz(to!string(arg));
			// else make it null
		}

		auto res = PQexecPrepared(conn, toStringz(name), argsStrings.length, argStrings.ptr, 0, null, 0);

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


	///
	string error() {
		return copyCString(PQerrorMessage(conn));
	}

	private:
		PGconn* conn;
}

///
class PostgresResult : ResultSet {
	// name for associative array to result index
	int getFieldIndex(string field) {
		if(mapping is null)
			makeFieldMapping();
		field = field.toLower;
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
			string[] row;

			for(int i = 0; i < numFields; i++) {
				string a;

				if(PQgetisnull(res, position, i))
					a = null;
				else {
					a = copyCString(PQgetvalue(res, position, i), PQgetlength(res, position, i));

				}
				row ~= a;
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

string copyCString(const char* c, int actualLength = -1) {
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
