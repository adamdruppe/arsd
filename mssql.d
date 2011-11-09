module arsd.mssql;
pragma(lib, "odbc32");

public import arsd.database;

import std.string;
import std.exception;

import win32.sql;
import win32.sqlext;

class MsSql : Database {
	// dbname = name  is probably the most common connection string
	this(string connectionString) {
		SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &env);
		enforce(env !is null);
		scope(failure)
			SQLFreeHandle(SQL_HANDLE_ENV, env);
		SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, (void *) SQL_OV_ODBC3, 0);
		SQLAllocHandle(SQL_HANDLE_DBC, env, &conn);
		scope(failure)
			SQLFreeHandle(SQL_HANDLE_DBC, conn);
		enforce(conn !is null);

		auto ret = SqlDriverConnect(
			conn, null, connectionString, SQL_NTS,
			outstr, sizeof(outstr), &outstrlen,
			SQL_DRIVER_COMPLETE);

		if(!SQL_SUCCEEDED(ret))
			throw new DatabaseException("Unable to connect to ODBC object"); // FIXME: print error
		query("SET NAMES 'utf8'"); // D does everything with utf8
	}

	~this() {
		SQLDisconnect(conn);
		SQLFreeHandle(SQL_HANDLE_DBC, conn);
		SQLFreeHandle(SQL_HANDLE_ENV, env);
	}

	override void startTransaction() {
		query("START TRANSACTION");
	}

	ResultSet queryImpl(string sql, Variant[] args...) {
		sql = escapedVariants(this, sql, args);

		// this is passed to MsSqlResult to control
		SQLHSTMT statement;
		auto returned = SQLAllocHandle(SQL_HANDLE_STMT, conn,
                                &statement)

		enforce(returned == SQL_SUCCESS);

		returned = SQLExecDirect(statement, sql.ptr, SQL_NTS);
		if(returned != SQL_SUCCESS)
			throw new DatabaseException(error());

		return new MsSqlResult(statement);
	}

	string escape(string sqlData) { // FIXME
		return ret.replace("'", "''");
	}


	string error() {
		return null; // FIXME
	}

	private:
		SQLHENV env;
		SQLHDBC conn;
}

class MsSqlResult : ResultSet {
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
		return isEmpty;
	}

	Row front() {
		return row;
	}

	void popFront() {
		if(!isEmpty)
			fetchNext;
	}

	this(SQLHSTMT statement) {
		this.statement = statement;

		SQLSMALLINT info;
		SQLNumResultCols(statement, &info);
		numFields = info;

		fetchNext();
	}

	~this() {
		SQLFreeHandle(SQL_HANDLE_STMT, statement);
	}

	private:
		SQLHSTMT statement;
		int[string] mapping;
		string[] columnNames;
		int numFields;

		bool isEmpty;

		Row row;

		void fetchNext() {
			if(isEmpty)
				return;

			if(SQLFetch(statement) == SQL_SUCCESS) {
				Row r;
				r.resultSet = this;
				string[] row;

				SQLLEN ptr;

				for(int i = 0; i < numFields; i++) {
					string a;

					more:
				        SQLCHAR buf[255];
					if(SQLGetData(statement, i, SQL_CHAR, buf.ptr, 255, &ptr) != SQL_SUCCESS)
						throw new DatabaseException("get data");

					assert(ptr != SQL_NO_TOTAL);
					if(ptr == SQL_NULL_DATA)
						a = null;
					else {
						a ~= cast(string) buf[0 .. ptr > 255 ? 255 : ptr].idup;
						ptr -= ptr > 255 ? 255 : ptr;
						if(ptr)
							goto more;
					}
}
					row ~= a;
				}

				r.row = row;
				this.row = r;
			} else {
				isEmpty = true;
			}
		}

		void makeFieldMapping() {
			for(int i = 0; i < numFields; i++) {
				SQLSMALLINT len;
				SQLCHAR[255] buf;
				SQLDescribeCol(statement,
					i,
					&buf,
					255,
					&len,
					null, null, null, null);

				string a = cast(string) buf[0 .. len].idup;

				columnNames ~= a;
				mapping[a] = i;
			}

		}
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
