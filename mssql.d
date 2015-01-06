// NOTE: I haven't even tried to use this for a test yet!
// It's probably godawful, if it works at all.

module arsd.mssql;

version(Windows):

pragma(lib, "odbc32");

public import arsd.database;

import std.string;
import std.exception;

import win32.sql;
import win32.sqlext;

class MsSql : Database {
	// dbname = name  is probably the most common connection string
	this(string connectionString) {
		SQLAllocHandle(SQL_HANDLE_ENV, cast(void*)SQL_NULL_HANDLE, &env);
		enforce(env !is null);
		scope(failure)
			SQLFreeHandle(SQL_HANDLE_ENV, env);
		SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, cast(void *) SQL_OV_ODBC3, 0);
		SQLAllocHandle(SQL_HANDLE_DBC, env, &conn);
		scope(failure)
			SQLFreeHandle(SQL_HANDLE_DBC, conn);
		enforce(conn !is null);

		auto ret = SQLDriverConnect(
			conn, null, cast(ubyte*)connectionString.ptr, SQL_NTS,
			null, 0, null,
			SQL_DRIVER_NOPROMPT );

		if ((ret != SQL_SUCCESS_WITH_INFO) && (ret != SQL_SUCCESS))
			throw new DatabaseException("Unable to connect to ODBC object: " ~ getSQLError(SQL_HANDLE_DBC, conn)); // FIXME: print error

		//query("SET NAMES 'utf8'"); // D does everything with utf8
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
		auto returned = SQLAllocHandle(SQL_HANDLE_STMT, conn, &statement);

		enforce(returned == SQL_SUCCESS);

		returned = SQLExecDirect(statement, cast(ubyte*)sql.ptr, SQL_NTS);
		if(returned != SQL_SUCCESS)
			throw new DatabaseException(error());

		return new MsSqlResult(statement);
	}

	string escape(string sqlData) { // FIXME
		return ""; //FIX ME
		//return ret.replace("'", "''");
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
		if (field !in mapping)
			return -1;
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

	int length()
	{
		return 1; //FIX ME
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
					if(SQLGetData(statement, cast(ushort)(i+1), SQL_CHAR, buf.ptr, 255, &ptr) != SQL_SUCCESS)
						throw new DatabaseException("get data: " ~ getSQLError(SQL_HANDLE_STMT, statement));

					assert(ptr != SQL_NO_TOTAL);
					if(ptr == SQL_NULL_DATA)
						a = null;
					else {
						a ~= cast(string) buf[0 .. ptr > 255 ? 255 : ptr].idup;
						ptr -= ptr > 255 ? 255 : ptr;
						if(ptr)
							goto more;
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
				auto ret = SQLDescribeCol(statement,
					cast(ushort)(i+1),
					cast(ubyte*)buf.ptr,
					255,
					&len,
					null, null, null, null);
				if (ret != SQL_SUCCESS)
					throw new DatabaseException("Field mapping error: " ~ getSQLError(SQL_HANDLE_STMT, statement));
				
				string a = cast(string) buf[0 .. len].idup;

				columnNames ~= a;
				mapping[a] = i;
			}

		}
}

private string getSQLError(short handletype, SQLHANDLE handle)
{
	char sqlstate[32];
	char message[256]; 
	SQLINTEGER nativeerror=0;
	SQLSMALLINT textlen=0;			
	auto ret = SQLGetDiagRec(handletype, handle, 1, 
			cast(ubyte*)sqlstate.ptr, 
			cast(int*)&nativeerror, 
			cast(ubyte*)message.ptr, 
			256, 
			&textlen);

	return message.idup;
}

/*
import std.stdio;
void main() {
	//auto db = new MsSql("Driver={SQL Server};Server=<host>[\\<optional-instance-name>]>;Database=dbtest;Trusted_Connection=Yes");
	auto db = new MsSql("Driver={SQL Server Native Client 10.0};Server=<host>[\\<optional-instance-name>];Database=dbtest;Trusted_Connection=Yes")

	db.query("INSERT INTO users (id, name) values (30, 'hello mang')");

	foreach(line; db.query("SELECT * FROM users")) {
		writeln(line[0], line["name"]);
	}
}
*/
