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
			throw new DatabaseConnectionException("Unable to allocate PG connection object");
		if(PQstatus(conn) != CONNECTION_OK) {
			this.connectionOk = false;
			throw new DatabaseConnectionException(error());
		}
		query("SET NAMES 'utf8'"); // D does everything with utf8
		this.connectionOk = true;
	}

	string connectionString;

	~this() {
		PQfinish(conn);
	}

	string sysTimeToValue(SysTime s) {
		return "'" ~ escape(s.toISOExtString()) ~ "'::timestamptz";
	}

	private bool connectionOk;
	override bool isAlive() {
		if(conn is null)
			return false;

		if(PQstatus(conn) != CONNECTION_OK) {
			return false;
		}

		return connectionOk;
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
			static if(!is(typeof(arg) == typeof(null)))
				argsStrings[idx] = toStringz(argToPostgresString(arg));
			// else make it null
		}

		bool first_retry = true;
		retry:
		auto res = PQexecPrepared(conn, toStringz(name), argsStrings.length, argsStrings.ptr, null, null, 0);

		int ress = PQresultStatus(res);
		if(ress != PGRES_TUPLES_OK
			&& ress != PGRES_COMMAND_OK)
		{
			if(first_retry && retryConnection()) {
				first_retry = false;
				goto retry;
			}
			throw new DatabaseException(error());
		}

		return new PostgresResult(res);

	}

	///
	override void startTransaction() {
		query("START TRANSACTION");
	}

	private bool retryConnection(bool forceTry = false) {
		if(forceTry || PQstatus(conn) != CONNECTION_OK) {
			// try to reconnect...
			PQfinish(conn);
			conn = PQconnectdb(toStringz(connectionString));
			if(conn is null)
				throw new DatabaseConnectionException("Unable to allocate PG connection object");
			if(PQstatus(conn) != CONNECTION_OK) {
				this.connectionOk = false;
				throw new DatabaseConnectionException(error());
			}
			return true;
		}
		return false;
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
			if(first_retry && retryConnection()) {
				first_retry = false;
				goto retry;
			}
			throw new SqlException(error());
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

	SqlState sqlState(ResultSet rs) {
		auto r = cast(PostgresResult) rs;
		if(r is null)
			return SqlState.init;
		return SqlState(getSqlState(r.res));
	}

	private char[5] getSqlState(PGresult* res) @trusted {
		auto ret = PQresultErrorField(res, PG_DIAG_SQLSTATE);
		char[5] buffer = 0;
		if(ret is null)
			return buffer;
		int pos = 0;
		while(*ret) {
			assert(pos < 5);
			buffer[pos++] = *ret;
			ret++;
		}
		return buffer;
	}

	package bool checkQueries(immutable(QueryMetadataBase[]) registeredQueries) {
		int count;
		bool succeeded = true;
		import arsd.core;
		import arsd.conv;

		if(!PQenterPipelineMode(this.conn))
			throw new DatabaseConnectionException(this.error());
		scope(exit)
			PQexitPipelineMode(this.conn);
		PQsetnonblocking(this.conn, 1);

		scope(exit) {
			if(!PQexitPipelineMode(this.conn))
				throw new DatabaseConnectionException(this.error());
			// FIXME error check
			PQsetnonblocking(this.conn, 0);
		}


		foreach(q; registeredQueries) {
			string dbSpecificSql;
			int placeholderNumber = 1;
			size_t lastCopied = 0;
			foreach(idx, ch; q.sql) {
				if(ch == '?') {
					dbSpecificSql ~= q.sql[lastCopied .. idx];
					lastCopied = idx + 1;
					dbSpecificSql ~= "$" ~ to!string(placeholderNumber);
					placeholderNumber++;
				}
			}
			dbSpecificSql ~= q.sql[lastCopied .. $];

			if(!PQsendPrepare(this.conn, "arsd_test", dbSpecificSql.toStringz, 0, null))
				{ writeln("wtf1"); assert(0); }
			if(!PQsendDescribePrepared(this.conn, "arsd_test"))
				{ writeln("wtf2"); assert(0); }
			//if(!PQsendClosePrepared(this.conn, "arsd_test"))
			if(!PQsendQueryParams(this.conn, "DEALLOCATE arsd_test", 0, null, null, null, null, 0))
				{ writeln("wtf3"); assert(0); }

			// PQsendPipelineSync introduced some time after postgres 16...
			if(!PQpipelineSync(this.conn))
				{ writeln("wtf4"); assert(0); }
		}

		if(!PQsendFlushRequest(this.conn)) {
			assert(0);
		}
		auto flushResult = PQflush(this.conn);
		assert(flushResult == 0); // FIXME: if it is 1 i need to wait for it to be ready to write more and do PQconsumeInput too

		DatabaseSchemaValidationException[] problems;

		// and now get the result
		foreach(q; registeredQueries) {
			// send prepare
			{
				while(auto result = PQgetResult(this.conn)) {
					int ress = PQresultStatus(result);
					if(ress == PGRES_FATAL_ERROR) {
						writeln(q.file, "(", q.line, "): ", fixupPostgresErrorString(q.file, q.line, this.error()));
						succeeded = false;
					}
					PQclear(result);
				}
			}
			// describe prepared
			{
				while(auto res = PQgetResult(this.conn)) {
					int ress = PQresultStatus(res);
					if(ress == PGRES_COMMAND_OK) {
						// good

						PreparedStatementResult[] ret;

						// PQnparams PQparamtype for params
						auto numFields = PQnfields(res);
						foreach(num; 0 .. numFields) {
							auto typeId = PQftype(res, num);
							DatabaseDatum dd;
							dd.platformSpecificTag = typeId;
							dd.storage = sampleForOid(typeId);
							ret ~= PreparedStatementResult(
								copyCString(PQfname(res, num)),
								dd,
							);
						}

						PQclear(res);

						auto desca = PreparedStatementDescription(ret);

						LimitedVariant[string] byName;
						foreach(col; desca.result) {
							byName[col.fieldName] = col.type.storage;
						}

						foreach(name; q.names) {
							if(name.name !in byName) {
								problems ~= new DatabaseSchemaValidationException(
									"unknown field",
									null,
									arsd.conv.to!string(name.sampleData.contains),
									name.name,
									name.file,
									name.line
								);
								continue;
							}
							if(name.assumedType.length == 0)
								continue;
							if(byName[name.name].contains != name.sampleData.contains) {
								problems ~= new DatabaseSchemaValidationException(
									"type mismatch",
									arsd.conv.to!string(byName[name.name].contains),
									arsd.conv.to!string(name.sampleData.contains),
									name.name,
									name.file,
									name.line,
								);
							}

							// i think this is redundant
							if(name.assumedType.length && name.actualType.length && name.actualType != name.assumedType) {
								problems ~= new DatabaseSchemaValidationException(
									"usage mismatch",
									name.actualType,
									name.assumedType,
									name.name,
									name.file,
									name.line
								);
							}
						}
					}
				}
			}
			// deallocate prepared
			{
				while(auto result = PQgetResult(this.conn)) {
					int ress = PQresultStatus(result);
					PQclear(result);
					if(ress == PGRES_COMMAND_OK) {
						// good
					}
				}
			}

			// pipeline sync
			{
				while(auto result = PQgetResult(this.conn)) {
					int ress = PQresultStatus(result);
					PQclear(result);
					if(ress == PGRES_PIPELINE_SYNC)
						break;
					else
						assert(0);
				}
			}
		}


		foreach(e; problems) {
			writeln(e.file, "(", e.line, "): ", e.message, ": `", e.dType ~ " ", e.fieldName, "`", e.dbType.length ? (" should be `" ~ e.dbType ~ "`") : null);
			succeeded = false;
		}

		if(!succeeded)
			writeln("db check failed.");

		return succeeded;

	}

	private:
		PGconn* conn;

		PostgresPipeline activePipeline;
}

private string fixupPostgresErrorString(string dFile, size_t startingLine, const(char)[] em) {
	import std.string;
	import std.conv;
	string fixed;
	int previousColon;
	int previousNewColon;
	foreach(line; splitLines(em)) {
		if(fixed.length)
			fixed ~= "\n";
		if(line.startsWith("LINE ")) {
			auto colon = line.indexOf(":");
			if(colon <= 5) {
				fixed ~= line;
				continue;
			}
			previousColon = cast(int) colon;
			int lineHere  = to!int(line[5 .. colon]);
			string newLine;
			newLine ~= dFile;
			newLine ~= "(";
			newLine ~= to!string(startingLine + lineHere - 1);
			previousNewColon = cast(int) newLine.length + 1;
			newLine ~= "):    ";
			newLine ~= line[colon + 1 .. $];
			fixed ~= newLine;
		} else if(line.startsWith("     ")) {
			auto carat = line.indexOf("^");
			if(carat != -1) {
				foreach(i; 0 .. previousNewColon - previousColon)
					fixed ~= " ";
				fixed ~= "    ";
				foreach(i; 0 .. carat)
					fixed ~= " ";
				fixed ~= "^";
			} else {
				fixed ~= line;
				continue;
			}
		} else {
			fixed ~= line;
		}

	}
	return fixed;
}


/++
	It will send as many parts as possible down a pipe and call the handle result method on each one as it arrives.

	Returns when the whole thing is finished. The connection will be switched to and from pipeline mode for each call.
+/
class PostgresPipeline {
	// you CAN append to the pipeline while it is executing and it will send the request asap
	// you can abort a pipeline when it is running.
	// you can NOT modify or remove an item already in the pipeline

	void abort() {

	}

	void append(PipelineComponent component) {
		components ~= component;
	}

	private static import arsd.core;
	auto append(Args...)(arsd.core.InterpolationHeader ihead, Args args, arsd.core.InterpolationFooter ifoot) {
		struct secret {
			private PipelineComponent* ptr;

			void forEach(void delegate(Row row) dg) {
				ptr.forEach = dg;
			}
			void onNone(void delegate() dg) {
				ptr.onNone = dg;
			}
			void onError(void delegate() dg) {
				ptr.onError = dg;
			}
			void onComplete(void delegate() dg) {
				ptr.onComplete = dg;
			}
		}
		auto piq = ParsedInterpolatedQuery(ihead, args, ifoot);
		components ~= PipelineComponent(piq.sql, piq.args);
		return secret(&components[$-1]);
	}

	/++
		You can only have one pipeline executor active for any individual database connection active at a time.
	+/
	@(arsd.core.mustuse)
	static struct PostgresPipelineExecutor {
		private PostgresPipeline pipeline;
		private PostgreSql db;
		private bool sent;
		private this(PostgresPipeline pipeline, PostgreSql db) {
			assert(db.activePipeline is null, "only one pipeline can be active at a time");
			this.pipeline = pipeline;
			this.db = db;

			if(!PQenterPipelineMode(db.conn))
				throw new DatabaseConnectionException(db.error());
			scope(failure)
				PQexitPipelineMode(db.conn);

			PQsetnonblocking(db.conn, 1);

			db.activePipeline = pipeline;
		}
		@disable this(this);

		/++
		+/
		void send() {
			pipeline.send(db);
			sent = true;
		}

		/++
		+/
		void waitForCompletion() {
			if(!sent)
				send();
			pipeline.finish(db);
		}

		~this() {
			db.activePipeline = null;

			if(!PQexitPipelineMode(db.conn))
				throw new DatabaseConnectionException(db.error());
			// FIXME error check
			PQsetnonblocking(db.conn, 0);
		}
	}

	/++
		History:
			Added September 15, 2026
	+/
	PostgresPipelineExecutor getExecutor(PostgreSql db) {
		return PostgresPipelineExecutor(this, db);
	}

	/++
	+/
	void execute(PostgreSql db) {
		auto executor = getExecutor(db);
		executor.send();
		executor.waitForCompletion();
	}

	private void send(PostgreSql db) {
		bool first_retry = true;
		retry:

		while(sendLocation < components.length) {
			import std.string;
			PipelineComponent toSend = components[sendLocation];
			arsd.core.CharzBuffer sql = toSend.query;
			//import arsd.core; writeln("sending: ",stringz(sql.ptr));
			char*[] paramValues;
			paramValues.length = toSend.args.length;
			foreach(idx, arg; toSend.args)
				paramValues[idx] = cast(char*) toStringz(variantToPostgresString(arg));
			auto ret = PQsendQueryParams(db.conn, sql.ptr, cast(int) toSend.args.length, null /* infer types */, paramValues.ptr, null /* it is zero terminated things */, null /* assume all text */, 0 /* get text format response */);
			if(ret)
				sendLocation++;
			else
				break; // FIXME: handle buffer full? or other errors?

		}

		//PQsendPipelineSync(db.conn); // apparently my libpq is not new enough for this but flush request is better than nothing
		if(!PQsendFlushRequest(db.conn)) {
			if(first_retry && db.retryConnection(true)) {
				first_retry = false;
				goto retry;
			}
			throw new DatabaseConnectionException(db.error());
		}
		auto flushResult = PQflush(db.conn);
		assert(flushResult == 0); // FIXME: if it is 1 i need to wait for it to be ready to write more and do PQconsumeInput too
	}

	private void finish(PostgreSql db) {
		bool first_retry = true;

		more:

		/+
		while(PQisBusy(db.conn))
		PQconsumeInput(db.conn);

		import arsd.core; writeln(PQisBusy(db.conn));
		+/

		string[] errors;
		while(receiveLocation < sendLocation) {
			// FIXME: onError ?
			while(auto result = PQgetResult(db.conn)) {
				int ress = PQresultStatus(result);

				if(ress != PGRES_TUPLES_OK
					&& ress != PGRES_COMMAND_OK)
				{

					// this looks like a connection died before we actually did any work. safe to restart.
					// but if receiveLocation != 0, we have some partial results accumulated, and need to throw
					// to ensure consistency; a retry part way through might double something up that the user
					// won't understand. an exception lets them clear out before retrying.
					if(first_retry && ress == PGRES_FATAL_ERROR && receiveLocation == 0 && db.retryConnection()) {
						first_retry = false;
						receiveLocation = 0;
						sendLocation = 0;

						// reinitialize the connection details
						if(!PQenterPipelineMode(db.conn))
							throw new DatabaseConnectionException(db.error());

						PQsetnonblocking(db.conn, 1);

						send(db);
						goto more;
					}


					// prolly gonna get PGRES_FATAL_ERROR followed by PGRES_PIPELINE_ABORTED
					auto oe = components[receiveLocation].onError;
					if(oe) {
						// if a user handler is there, let them handle it
						oe();
					} else {
						// otherwise, we need to consume the pipeline still, but
						// log this for later and we'll throw at the end so it isn't ignored
						errors ~= db.error();
					}
					continue;
				}

				auto resultObject = new PostgresResult(result);
				if(resultObject.empty()) {
					auto dg = components[receiveLocation].onNone;
					if(dg)
						dg();
				} else {
					if(components[receiveLocation].onResult) {
						components[receiveLocation].onResult(resultObject);
					} else {
						foreach(row; resultObject) {
							components[receiveLocation].forEach(row);
						}
					}
				}
				.destroy(resultObject); // the dtor calls PQclear(result);
			}
			auto oc = components[receiveLocation].onComplete;
			if(oc)
				oc();
			receiveLocation++;
		}

		if(sendLocation < components.length) {
			send(db);
			goto more;
		}
		if(errors.length) {
			string combined;
			foreach(error; errors) {
				if(combined.length)
					combined ~= "\n";
				combined ~= error;
			}
			throw new DatabaseException(combined);
		}
	}

	/+
	void start() {

	}

	void waitForCompletion() {

	}
	+/

	private PipelineComponent[] components;
	private int sendLocation;
	private int receiveLocation;
}

/// ditto
struct PipelineComponent {
	string query;
	Variant[] args;
	void delegate(Row) forEach;
	void delegate() onNone;
	void delegate() onError;
	void delegate() onComplete;
	private void delegate(ResultSet) onResult;
}

///
unittest {
	/+
	scope p = new PostgresPipeline();
	int foo = 100;
	p.append(i"SELECT * FROM test WHERE id < $(foo)")
		.forEach((row) { string s = row["id"]; import arsd.core; writeln(row.id); })
	;
	p.append(PipelineComponent(
		query: "SELECT * FROM test",
		forEach: (row) { import arsd.core; writeln(row["id"]); }
	));
	p.append(PipelineComponent(
		query: "SELECT * FROM test",
		forEach: (row) { import arsd.core; writeln("Second: ", row["id"]); }
	));
	p.execute(new PostgreSql("dbname=me"));
	+/
}

// a factory function could return some magic and i could maybe use an alias param...

class PostgresPipelineFor(PooledConnection) {
	PostgresPipeline pipeline;
	this() {
		pipeline = new PostgresPipeline();
	}

	private static import arsd.core;
	auto append(string file = __FILE__, size_t line = __LINE__, Args...)(arsd.core.InterpolationHeader ihead, Args args, arsd.core.InterpolationFooter ifoot) {
		auto queryFunc = &PooledConnection.query!(file, line, arsd.core.InterpolationHeader, Args, arsd.core.InterpolationFooter);

		static if(is(typeof(queryFunc) Return == return)) {
			static struct secret {
				private PipelineComponent* ptr;

				private this(PipelineComponent* ptr) {
					this.ptr = ptr;

					ptr.onResult = &this.onResult;
				}

				private void onResult(ResultSet rs) {
					auto it = new Return(rs);
					foreach(arg; it)
						if(forEachDg)
							forEachDg(arg);
				}

				private void delegate(typeof(Return.front()) row) forEachDg;

				typeof(this) forEach(void delegate(typeof(Return.front()) row) dg) {
					this.forEachDg = dg;
					return this;
				}
				typeof(this) forEach(T, string file = __FILE__, size_t line = __LINE__)(void delegate(T row) dg) {
					void helper(typeof(Return.front()) row) {
						dg(row.to!(T, file, line));
					}
					this.forEach = &helper;
					return this;
				}
				typeof(this) onNone(void delegate() dg) {
					ptr.onNone = dg;
					return this;
				}
				typeof(this) onError(void delegate() dg) {
					ptr.onError = dg;
					return this;
				}
				typeof(this) onComplete(void delegate() dg) {
					ptr.onComplete = dg;
					return this;
				}
			}
			auto piq = ParsedInterpolatedQuery(ihead, args, ifoot);
			pipeline.components ~= PipelineComponent(piq.sql, piq.args);
			return secret(&pipeline.components[$-1]);
		} else static assert(0, "some kind of invalid args i guess idk");
	}

	void execute(ref PooledConnection conn) {
		pipeline.execute(conn.borrow);
	}

	PostgresPipeline.PostgresPipelineExecutor getExecutor(ref PooledConnection conn) {
		return PostgresPipeline.PostgresPipelineExecutor(pipeline, conn.borrow);
	}
}

/+
///
unittest {
	// need the interpolated queries
	// but also rt queries w/ params

	db.executePipeline(PipelineComponent(
		i"SELECT foo from bar",
		(result) { foreach(row; result) { } }
	), PipelineComponent(
		i"SELECT foo from bar",
		(row) => row....

	));

	// put it in pipeline mode and call each opApply....
	foreach(item; myList) {
		pipeline ~= PipelineComponent()
	}

	db.executePipeline(pipeline)
}
+/

/+
# when it changes from lowercase to upper case, call that a new word. or when it goes to/from anything else and underscore or dashes.
+/

struct PreparedStatementDescription {
	PreparedStatementResult[] result;
}

struct PreparedStatementResult {
	string fieldName;
	DatabaseDatum type;
}

PreparedStatementDescription describePrepared(PostgreSql db, string name) {
	auto res = PQdescribePrepared(db.conn, name.toStringz);

	PreparedStatementResult[] ret;

	// PQnparams PQparamtype for params
	auto numFields = PQnfields(res);
	foreach(num; 0 .. numFields) {
		auto typeId = PQftype(res, num);
		DatabaseDatum dd;
		dd.platformSpecificTag = typeId;
		dd.storage = sampleForOid(typeId);
		ret ~= PreparedStatementResult(
			copyCString(PQfname(res, num)),
			dd,
		);
	}

	PQclear(res);

	return PreparedStatementDescription(ret);
}

import arsd.core : LimitedVariant, PackedDateTime, SimplifiedUtcTimestamp;
LimitedVariant sampleForOid(int platformSpecificTag) {
	switch(platformSpecificTag) {
		case BOOLOID:
			return LimitedVariant(false);
		case BYTEAOID:
			return LimitedVariant(cast(const(ubyte)[]) null);
		case TEXTOID:
		case VARCHAROID:
			return LimitedVariant("");
		case INT4OID:
			return LimitedVariant(0);
		case INT8OID:
			return LimitedVariant(0L);
		case FLOAT4OID:
			return LimitedVariant(0.0f);
		case FLOAT8OID:
			return LimitedVariant(0.0);
		case TIMESTAMPOID:
		case TIMESTAMPTZOID:
			return LimitedVariant(SimplifiedUtcTimestamp(0));
		case DATEOID:
			PackedDateTime d;
			d.hasDate = true;
			return LimitedVariant(d); // might want a different type so contains shows the thing without checking hasDate and hasTime
		case TIMETZOID: // possibly wrong... the tz isn't in my packed thing
		case TIMEOID:
			PackedDateTime d;
			d.hasTime = true;
			return LimitedVariant(d);
		case INTERVALOID:
			// months, days, and microseconds

		case NUMERICOID: // aka decimal
		default:
			// when in doubt, assume it is just a string
			return LimitedVariant("sample");
	}
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

string argToPostgresString(T)(T arg) {
	import std.conv;
	return to!string(arg);
}

string variantToPostgresString(Variant b) {
	if(b.peek!(int[]))
		return "{"~b.toString()[1 ..$-1]~"}";
	return b.toString;
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
	int PQsendQueryPrepared(PGconn*, const char* stmtName, int nParams, const char** paramValues, const int* paramLengths, const int* paramFormats, int resultFormat);
	int PQsendClosePrepared(PGconn* conn, const char* name); // introduced in postgres 17...

	int PQresultStatus(PGresult*); // FIXME check return value

	char* PQresultErrorField(const PGresult* res, int fieldcode);
	enum int PG_DIAG_SQLSTATE = 'C';


	int PQnfields(PGresult*); // number of fields in a result
	const(char*) PQfname(PGresult*, int); // name of field

	int PQntuples(PGresult*); // number of rows in result
	const(char*) PQgetvalue(PGresult*, int row, int column);

	size_t PQescapeString (char *to, const char *from, size_t length);

	enum int CONNECTION_OK = 0;

	enum int PGRES_EMPTY_QUERY = 0;
	enum int PGRES_COMMAND_OK = 1;
	enum int PGRES_TUPLES_OK = 2;
	enum int PGRES_COPY_OUT = 3;
	enum int PGRES_COPY_IN = 4;
	enum int PGRES_BAD_RESPONSE = 5;
	enum int PGRES_NONFATAL_ERROR = 6;
	enum int PGRES_FATAL_ERROR = 7;
	enum int PGRES_COPY_BOTH = 8;
	enum int PGRES_SINGLE_TUPLE = 9;
	enum int PGRES_PIPELINE_SYNC = 10;
	enum int PGRES_PIPELINE_ABORTED = 11;
	// looks like chunks was added in pq version 17...

	int PQsetSingleRowMode(PGconn* conn);

	// https://www.postgresql.org/docs/current/libpq-notify.html

	enum int PGRES_POLLING_FAILED = 0;
	enum int PGRES_POLLING_READING = 1;
	enum int PGRES_POLLING_WRITING = 2;
	enum int PGRES_POLLING_OK = 3;
	PGconn* PQconnectStart(const char* connInfo);
	int PQconnectPoll(PGconn* conn);

	int PQgetlength(const PGresult *res,
			int row_number,
			int column_number);
	int PQgetisnull(const PGresult *res,
			int row_number,
			int column_number);

	int PQfformat(const PGresult *res, int column_number);

	alias Oid = int;
	enum BOOLOID = 16;
	enum BYTEAOID = 17;
	enum TEXTOID = 25;
	enum INT4OID = 23; // integer
	enum INT8OID = 20; // bigint
	enum NUMERICOID = 1700;
	enum FLOAT4OID = 700;
	enum FLOAT8OID = 701;
	enum VARCHAROID = 1043;
	enum DATEOID = 1082;
	enum TIMEOID = 1083;
	enum TIMESTAMPOID = 1114;
	enum TIMESTAMPTZOID = 1184;
	enum INTERVALOID = 1186;
	enum TIMETZOID = 1266;

	Oid PQftype(const PGresult* res, int column_number);

	char *PQescapeByteaConn(PGconn *conn,
                                 const ubyte *from,
                                 size_t from_length,
                                 size_t *to_length);
	char *PQunescapeBytea(const char *from, size_t *to_length);
	void PQfreemem(void *ptr);

	char* PQcmdTuples(PGresult *res);

	int PQsendQuery(PGconn* conn, const char* command); // incompatible with pipeline
	int PQsendQueryParams(PGconn* conn, const char* command, int params, const Oid* paramTypes, const char** paramValues, const int* paramLengths, const int* paramFormats, int resultFormat);

	PGresult *PQdescribePrepared(PGconn *conn, const char *stmtName);
	int PQsendDescribePrepared(PGconn *conn, const char *stmtName);

	PGresult* PQgetResult(PGconn* conn); // call until it returns null

	int PQenterPipelineMode(PGconn* conn); // returns 1 on success
	int PQexitPipelineMode(PGconn* conn); // ditto
	PGpipelineStatus PQpipelineStatus(const PGconn* conn);
	enum PGpipelineStatus {
		// FIXME: confirm values
		PQ_PIPELINE_ON,
		PQ_PIPELINE_OFF,
		PQ_PIPELINE_ABORTED
	}
	int PQpipelineSync(PGconn* conn);
	int PQsendPipelineSync(PGconn* conn);
	int PQsendFlushRequest(PGconn* conn);
	int PQsendPrepare(PGconn *conn, const char *stmtName, const char *query, int nParams, const Oid *paramTypes);

	int PQconsumeInput(PGconn* conn);
	int PQisBusy(PGconn* conn);

	int PQsetnonblocking(PGconn* conn, int arg);
	int PQflush(PGconn* conn); // if returns 1, wait for socket readiness

	int PQsocket(const PGconn* conn); // returns a fd
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
