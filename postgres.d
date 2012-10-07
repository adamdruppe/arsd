module arsd.postgres;
pragma(lib, "pq");

public import arsd.database;

import std.string;
import std.exception;

// remember to CREATE DATABASE name WITH ENCODING 'utf8'

class PostgreSql : Database {
	// dbname = name  is probably the most common connection string
	this(string connectionString) {
		conn = PQconnectdb(toStringz(connectionString));
		if(conn is null)
			throw new DatabaseException("Unable to allocate PG connection object");
		if(PQstatus(conn) != CONNECTION_OK)
			throw new DatabaseException(error());
		query("SET NAMES 'utf8'"); // D does everything with utf8
	}

	~this() {
		PQfinish(conn);
	}

	override void startTransaction() {
		query("START TRANSACTION");
	}

	ResultSet queryImpl(string sql, Variant[] args...) {
		sql = escapedVariants(this, sql, args);

		auto res = PQexec(conn, toStringz(sql));
		int ress = PQresultStatus(res);
		if(ress != PGRES_TUPLES_OK
			&& ress != PGRES_COMMAND_OK)
			throw new DatabaseException(error());

		return new PostgresResult(res);
	}

	string escape(string sqlData) {
		char* buffer = (new char[sqlData.length * 2 + 1]).ptr;
		ulong size = PQescapeString (buffer, sqlData.ptr, sqlData.length);

		string ret = assumeUnique(buffer[0.. cast(size_t) size]);

		return ret;
	}


	string error() {
		return copyCString(PQerrorMessage(conn));
	}

	private:
		PGconn* conn;
}

class PostgresResult : ResultSet {
	// name for associative array to result index
	int getFieldIndex(string field) {
		if(mapping is null)
			makeFieldMapping();
		return mapping[field];
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
			fetchNext;
	}

	int length() {
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
