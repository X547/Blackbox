MODULE SqlOdbc;
(**
	project	= "BlackBox"
	organization	= "www.oberon.ch"
	contributors	= "Oberon microsystems"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""

**)

	IMPORT SYSTEM, WinApi, WinSql, Services, Dates, Dialog, Log, SqlDrivers, HostWindows;

	(* ODBC functions used:
		core:
			SQLAllocEnv
			SQLAllocConnect
			SQLAllocStmt
			SQLFreeStmt
			SQLFreeConnect
			SQLFreeEnv
			SQLConnect
			SQLDisconnect
			SQLPrepare
			SQLExecute
			SQLDescribeCol
			SQLNumResultCols
			SQLRowCount
			SQLTransact
			SQLError
		level 1:
			SQLBindParameter	(* for blobs *)
			SQLSetStmtOption
			SQLGetStmtOption
			SQLSetConnectOption
			SQLGetData
			SQLGetInfo
		level 2:
			SQLExtendedFetch
	*)

	(* The major problem with ODBC is that many of its functions, or many uses of them, are optional.
		This means that one can never rely on a function to be really implemented by the current ODBC driver.
		As a result, one often has to try the best approach first, then back off if necessary to the next best, etc.
		This is cumbersome and difficult to test exhaustively. *)

	CONST
		outOfTables = 5;
		notExecutable = 6;
		cannotOpenDB = 7;
		wrongIdentification = 8;
		tooManyBlobs = 9;
		(* not public *)
		invalidTransaction = 10;

		truncated = 2;
		overflow = 3;
		incompatible = 4;
		noData = 5;

		connecting = 1;
		connected = 2;
		preparing = 3;
		executing = 4;
		executed = 5;
		closed = 6;

	TYPE
		Driver = POINTER TO RECORD (SqlDrivers.Driver)
			state: INTEGER;	(* IN {connecting, connected, executing, closed} *)
			showErr: BOOLEAN;
			actStmt: WinSql.HSTMT;
			actRes: INTEGER;	(* result of async operation *)
			dbc: WinSql.HDBC;
			directions: SET;	(* supported Fetch directions *)
			string: POINTER TO ARRAY OF SHORTCHAR	(* cached temp string *)
		END;

		Table = POINTER TO RECORD (SqlDrivers.Table)
			rows, columns: INTEGER;
			actRow, actCol: INTEGER;
			stmt: WinSql.HSTMT;
			driver: Driver
		END;


	VAR
		debug*: BOOLEAN;			(* if TRUE, show more information about what's happening *)
		autoCommit*: BOOLEAN;	(* by default, automatic commit is disabled *)
		rowcount*: INTEGER;			(* number of rows affected in last update, insert, delete *)
		environment: WinSql.HENV;	(* ODBC environment, in which everything happens *)
		numConnections: INTEGER;	(* free the environment, if the number of connections goes to zero *)


	(* miscellaneous *)

	PROCEDURE ShortString (IN str: ARRAY OF CHAR; VAR static: ARRAY OF SHORTCHAR): WinApi.PtrSTR;
		VAR p: WinApi.PtrSTR; sp: POINTER TO ARRAY OF SHORTCHAR;
	BEGIN	(* use static if it is long enough, otherwise allocate a string variable on the heap *)
		IF LEN(str) <= LEN(static) THEN
			static := SHORT(str$); p := static
		ELSE
			NEW(sp, LEN(str)); sp^ := SHORT(str$); p := sp^
		END;
		RETURN p
	END ShortString;

	PROCEDURE TempString (d: Driver; len: INTEGER): POINTER TO ARRAY OF SHORTCHAR;
	BEGIN	(* make d.string large enough, if necessary *)
		IF (d.string = NIL) OR (LEN(d.string) < len) THEN NEW(d.string, len) END;
		RETURN d.string
	END TempString;

	PROCEDURE Check (ret: INTEGER; d: Driver; stmt: WinSql.HSTMT; OUT res: INTEGER);
		VAR err: INTEGER; len: SHORTINT; state, msg: ARRAY 256 OF SHORTCHAR; dbc: WinSql.HDBC;
	BEGIN
		CASE ret OF
		| WinSql.SQL_SUCCESS:
			res := 0
		| WinSql.SQL_SUCCESS_WITH_INFO:
			IF d # NIL THEN dbc := d.dbc ELSE dbc := 0 END;
			res := WinSql.SQLError(environment, dbc, stmt, state, err, msg, LEN(msg), len);
			IF debug THEN Log.String(msg$); Log.Ln END;
			IF state = "01004" THEN res := truncated ELSE res := 0 END
		| WinSql.SQL_ERROR:
			IF d # NIL THEN dbc := d.dbc ELSE dbc := 0 END;
			res := WinSql.SQLError(environment, dbc, stmt, state, err, msg, LEN(msg), len);
			IF (d # NIL) & d.showErr THEN
				res := WinApi.MessageBox(0, msg, "ODBC Error", {})
			ELSIF debug THEN Log.String(msg$); Log.Ln
			END;
			IF state = "01004" THEN res := truncated
			ELSIF state = "28000" THEN res := wrongIdentification
			ELSIF state = "07006" THEN res := incompatible
			ELSIF state = "22003" THEN res := overflow
			ELSIF state = "22005" THEN res := overflow
			ELSIF state = "22008" THEN res := overflow
			ELSIF state = "25000" THEN res := invalidTransaction
			ELSE res := noData	(* default error *)
			END
		| WinSql.SQL_NO_DATA_FOUND:
			res := noData
		| WinSql.SQL_INVALID_HANDLE:
			HALT(100)
		| WinSql.SQL_STILL_EXECUTING:
			 HALT(101)
		| WinSql.SQL_NEED_DATA:
			HALT(102)
		END
	END Check;

	PROCEDURE GetTableSize (t: Table; VAR n: INTEGER);
		VAR res, x: INTEGER; stat: SHORTINT;
	BEGIN
		res := -1;
		IF t.driver.directions * (WinSql.SQL_FD_FETCH_LAST + WinSql.SQL_FD_FETCH_ABSOLUTE) # {} THEN
			IF t.driver.directions * WinSql.SQL_FD_FETCH_LAST # {} THEN
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_LAST, 0, x, stat), NIL, t.stmt, res)
			ELSE
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_ABSOLUTE, -1, x, stat), NIL, t.stmt, res)
			END;
			IF res = noData THEN n := 0; res := 0
			ELSIF res = 0 THEN
				Check(WinSql.SQLGetStmtOption(t.stmt, WinSql.SQL_ROW_NUMBER, SYSTEM.ADR(n)), NIL, t.stmt, res)
			END;
			t.actRow := -2	(* undefined *)
		END;
		IF (res # 0) & (t.driver.directions * WinSql.SQL_FD_FETCH_FIRST # {}) THEN
			Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_FIRST, 0, x, stat), NIL, t.stmt, res);
			n := 0;
			WHILE res = 0 DO
				INC(n);
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_NEXT, 0, x, stat), NIL, t.stmt, res)
			END;
			IF res = noData THEN res := 0 END;
			t.actRow := -2	(* undefined *)
		END;
		IF res # 0 THEN
			Check(WinSql.SQLRowCount(t.stmt, n), NIL, t.stmt, res);
			IF (res # 0) OR (n < 0) THEN n := MAX(INTEGER) END	(* row count is not known *)
		END
	END GetTableSize;

	PROCEDURE SetPos (t: Table; row, col: INTEGER; OUT res: INTEGER);
		VAR fetched: INTEGER; status: SHORTINT;
	BEGIN
		res := 0;
		IF (row # t.actRow) OR (col <= t.actCol) THEN
			IF row = t.actRow + 1 THEN
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_NEXT, 0, fetched, status), NIL, t.stmt, res);
				IF res = 0 THEN INC(t.actRow) END
			ELSIF (row = 0) & (t.driver.directions * WinSql.SQL_FD_FETCH_FIRST # {}) THEN
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_FIRST, 0, fetched, status), NIL, t.stmt, res);
				IF res = 0 THEN t.actRow := 0 END
			ELSIF t.driver.directions * WinSql.SQL_FD_FETCH_ABSOLUTE # {} THEN
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_ABSOLUTE,
																	row + 1, fetched, status), NIL, t.stmt, res);
				IF res = 0 THEN t.actRow := row END
			ELSIF t.driver.directions * WinSql.SQL_FD_FETCH_RELATIVE # {} THEN
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_RELATIVE, row - t.actRow, fetched, status),
						NIL, t.stmt, res);
				IF res = 0 THEN t.actRow := row END
			ELSIF row <= t.actRow THEN
				IF (row > t.actRow DIV 2) & (t.driver.directions * WinSql.SQL_FD_FETCH_PRIOR # {}) THEN
					REPEAT
						Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_PRIOR, 0, fetched, status),
																			NIL, t.stmt, res);
						IF res = 0 THEN DEC(t.actRow) END
					UNTIL (t.actRow <= row) OR (res # 0)
				ELSE
					Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_FIRST, 0, fetched, status),
																		NIL, t.stmt, res);
					IF res = 0 THEN t.actRow := 0 END
				END
			END;
			WHILE (t.actRow < row) & (res = 0) DO
				Check(WinSql.SQLExtendedFetch(t.stmt, WinSql.SQL_FETCH_NEXT, 0, fetched, status), NIL, t.stmt, res);
				IF res = 0 THEN INC(t.actRow) END
			END
		END;
		IF res = 0 THEN t.actCol := col ELSE res := noData END
	END SetPos;


	(* Driver *)

	PROCEDURE (d: Driver) Ready (): BOOLEAN;
		VAR res: INTEGER;
	BEGIN
		IF d.state = preparing THEN
			d.actRes := WinSql.SQLPrepare(d.actStmt, "", WinSql.SQL_NTS);
			IF d.actRes = WinSql.SQL_SUCCESS THEN
				d.actRes := WinSql.SQLExecute(d.actStmt); d.state := executing
			ELSIF d.actRes = WinSql.SQL_SUCCESS_WITH_INFO THEN
				Check(d.actRes, d, d.actStmt, res);
				d.actRes := WinSql.SQLExecute(d.actStmt); d.state := executing
			END;
			IF d.actRes # WinSql.SQL_STILL_EXECUTING THEN d.state := executed END
		ELSIF d.state = executing THEN
			d.actRes := WinSql.SQLExecute(d.actStmt);
			IF d.actRes # WinSql.SQL_STILL_EXECUTING THEN d.state := executed END
		END;
		RETURN d.state IN {connecting, connected, executed}
	END Ready;

	PROCEDURE (d: Driver) EndOpen (OUT res: INTEGER);
	BEGIN
		d.state := connected; res := 0
	END EndOpen;

	PROCEDURE (d: Driver) BeginExec (IN statement: ARRAY OF CHAR; data: SqlDrivers.Blob;
													async, showErr: BOOLEAN; OUT res: INTEGER);
	(* Pre: statement # ""	20 *)
	(* Post: res = 0 <=> execution has started and should be completed later with EndExec *)
		VAR stmt: WinSql.HSTMT; r: INTEGER; p: SHORTINT;
			ss: ARRAY 256 OF SHORTCHAR;
	BEGIN
		IF debug THEN Log.String(statement); Log.Ln END;
		ASSERT(statement # "", 20); ASSERT(d.state = connected, 21);
		d.showErr := showErr;
		res := WinSql.SQLAllocStmt(d.dbc, stmt);
		IF res # WinSql.SQL_SUCCESS THEN
			Services.Collect; res := WinSql.SQLAllocStmt(d.dbc, stmt)
		END;
		Check(res, d, 0, res);
		IF res = 0 THEN
			Check(WinSql.SQLSetStmtOption(stmt, WinSql.SQL_CURSOR_TYPE, WinSql.SQL_CURSOR_STATIC),
																NIL, stmt, res);
			p :=1;
			WHILE data # NIL DO	(* handle blobs *)
				Check(WinSql.SQLBindParameter(stmt, SHORT(p), WinSql.SQL_PARAM_INPUT, WinSql.SQL_C_BINARY,
							WinSql.SQL_LONGVARBINARY, 0, 0, SYSTEM.ADR(data.data^), data.len, data.len), d, stmt, res);
				IF res # 0 THEN
					Check(WinSql.SQLFreeStmt(stmt, WinSql.SQL_DROP), NIL, stmt, r);
					res := tooManyBlobs; RETURN
				END;
				data := data.next; INC(p)
			END;
			IF async THEN
				Check(WinSql.SQLSetStmtOption(stmt, WinSql.SQL_ASYNC_ENABLE,
																	WinSql.SQL_ASYNC_ENABLE_ON), NIL, stmt, r)
			END;
			d.actStmt := stmt;
			d.actRes := WinSql.SQLPrepare(stmt, ShortString(statement, ss), WinSql.SQL_NTS);
			IF d.actRes = WinSql.SQL_STILL_EXECUTING THEN
				d.state := preparing; res := 0
			ELSE
				Check(d.actRes, d, stmt, res);
				IF res = 0 THEN
					d.actRes := WinSql.SQLExecute(stmt);
					IF d.actRes = WinSql.SQL_STILL_EXECUTING THEN
						d.state := executing; res := 0
					ELSE
						Check(d.actRes, d, stmt, res);
						IF res = 0 THEN d.state := executed END
					END
				END
			END;
			IF res # 0 THEN	(* execution failed *)
				Check(WinSql.SQLFreeStmt(stmt, WinSql.SQL_DROP), NIL, stmt, r);
				res := notExecutable
			END
		ELSE	(* no workspace available *)
			res := outOfTables
		END
	END BeginExec;

	PROCEDURE (d: Driver) EndExec (VAR t: SqlDrivers.Table; OUT rows, columns, res: INTEGER);
	(* Pre: execution must have been started successfully with BeginExec	20 *)
	(* Post: res = 0  <=>  t # NIL & res = 0 *)
		VAR h: Table; cols: SHORTINT;
	BEGIN
		ASSERT(d.state # connected, 20); ASSERT(d.state = executed, 21);
		d.state := connected;
		Check(d.actRes, d, d.actStmt, res);
		IF res = 0 THEN
			Check(WinSql.SQLNumResultCols(d.actStmt, cols), d, d.actStmt, res);
			IF (res = 0) & (cols > 0) THEN	(* legal statement returning a result set *)
				NEW(h); h.Init(d); h.driver := d;
				h.columns := cols; h.actRow := -1;
				Check(WinSql.SQLSetStmtOption(d.actStmt, WinSql.SQL_ASYNC_ENABLE,
																	WinSql.SQL_ASYNC_ENABLE_OFF),
						NIL, d.actStmt, res);
				h.stmt := d.actStmt;
				GetTableSize(h, h.rows);
				t := h; columns := h.columns; rows := h.rows; res := 0
			ELSE
				Check(WinSql.SQLRowCount(d.actStmt, rowcount), NIL, d.actStmt, res);
				Check(WinSql.SQLFreeStmt(d.actStmt, WinSql.SQL_DROP), NIL, d.actStmt, res);
				t := NIL; columns := 0; rows := 0; res := 0
			END
		ELSE
			Check(WinSql.SQLFreeStmt(d.actStmt, WinSql.SQL_DROP), NIL, d.actStmt, res);
			t := NIL; columns := 0; rows := 0; res := notExecutable
		END
	END EndExec;

	PROCEDURE (d: Driver) Commit (accept: BOOLEAN; OUT res: INTEGER);
		VAR op: SHORTINT;
	BEGIN
		IF accept THEN op := WinSql.SQL_COMMIT ELSE op := WinSql.SQL_ROLLBACK END;
		Check(WinSql.SQLTransact(environment, d.dbc, op), d, 0, res);
		IF res # 0 THEN res := notExecutable END
	END Commit;

	PROCEDURE (d: Driver) Cleanup;
		VAR res: INTEGER;
	BEGIN
		d.showErr := FALSE;
		Check(WinSql.SQLDisconnect(d.dbc), d, 0, res);
		IF res = invalidTransaction THEN
			Check(WinSql.SQLTransact(environment, d.dbc, WinSql.SQL_ROLLBACK), d, 0, res);
			Check(WinSql.SQLDisconnect(d.dbc), d, 0, res)
		END;
		Check(WinSql.SQLFreeConnect(d.dbc), d, 0, res);
		d.dbc := 0; DEC(numConnections);
		IF numConnections = 0 THEN
			Check(WinSql.SQLFreeEnv(environment), NIL, 0, res)
		END;
		d.state := closed
	END Cleanup;


	(* Table *)

	PROCEDURE (t: Table) ReadInteger (row, column: INTEGER; OUT val: INTEGER);
		VAR res, len: INTEGER;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_LONG,
														SYSTEM.ADR(val), 0, len), NIL, t.stmt, res);
			IF len = WinSql.SQL_NULL_DATA THEN val := 0 END
		END;
		t.res := res
	END ReadInteger;

	PROCEDURE (t: Table) ReadReal (row, column: INTEGER; OUT val: REAL);
		VAR res, len: INTEGER;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_DOUBLE,
														SYSTEM.ADR(val), 0, len), NIL, t.stmt, res);
			IF len = WinSql.SQL_NULL_DATA THEN val := 0 END
		END;
		t.res := res
	END ReadReal;

	PROCEDURE (t: Table) ReadDate (row, column: INTEGER; OUT val: Dates.Date);
		VAR res, len: INTEGER; date: RECORD y, m, d: SHORTINT END;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_DATE,
														SYSTEM.ADR(date), 0, len), NIL, t.stmt, res);
			IF len = WinSql.SQL_NULL_DATA THEN val.day := 0; val.month := 0; val.year := 0
			ELSE val.day := date.d; val.month := date.m; val.year := date.y
			END
		END;
		t.res := res
	END ReadDate;

	PROCEDURE (t: Table) ReadTime (row, column: INTEGER; OUT val: Dates.Time);
		VAR res, len: INTEGER; time: RECORD h, m, s: SHORTINT END;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_TIME,
														SYSTEM.ADR(time), 0, len), NIL, t.stmt, res);
			IF len = WinSql.SQL_NULL_DATA THEN val.second := 0; val.minute := 0; val.hour := 0
			ELSE val.second := time.s; val.minute := time.m; val.hour := time.h
			END
		END;
		t.res := res
	END ReadTime;

	PROCEDURE (t: Table) ReadCurrency (row, column: INTEGER; OUT val: Dialog.Currency);
		VAR res, len, i, j: INTEGER; str: ARRAY 32 OF SHORTCHAR; a, b, c, scale: SHORTINT; x: LONGINT;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			Check(WinSql.SQLDescribeCol(t.stmt, SHORT(column + 1), str, LEN(str), a, b, i, scale, c), NIL, t.stmt, res);
			IF scale < 0 THEN scale := 0 END;
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_CHAR,
														SYSTEM.ADR(str), LEN(str), len),
					NIL, t.stmt, res);
			IF len # WinSql.SQL_NULL_DATA THEN
				x := 0; i := 0;
				IF str[0] < "." THEN INC(i) END;
				WHILE (i < len) & (str[i] # ".") DO
					x := x * 10 + ORD(str[i]) - ORD("0"); INC(i)
				END;
				INC(i); j := 0;
				WHILE j < scale DO
					x := x * 10;
					IF i < len THEN x := x + ORD(str[i]) - ORD("0"); INC(i) END;
					INC(j)
				END;
				IF str[0] = "-" THEN x := -x END;
				val.val := x; val.scale := scale
			ELSE
				val.val := 0; val.scale := 0
			END
		END;
		t.res := res
	END ReadCurrency;

	PROCEDURE (t: Table) ReadString (row, column: INTEGER; OUT str: ARRAY OF CHAR);
		VAR res, len: INTEGER; sp: POINTER TO ARRAY OF SHORTCHAR;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			sp := TempString(t.driver, LEN(str));
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_CHAR,
														SYSTEM.ADR(sp^), LEN(str), len),
					NIL, t.stmt, res);
			IF (len = 0) OR (len = WinSql.SQL_NULL_DATA) THEN str := "" ELSE str := sp$ END
		END;
		t.res := res
	END ReadString;

	PROCEDURE (t: Table) ReadVarString (row, column: INTEGER; OUT str: SqlDrivers.String);
		VAR res, len: INTEGER; s: ARRAY 257 OF SHORTCHAR;	(* odd for correct conversion of binary data *)
			sp: POINTER TO ARRAY OF SHORTCHAR;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_CHAR,
														SYSTEM.ADR(s), LEN(s), len),
					NIL, t.stmt, res);
			IF res # noData THEN
				IF (len = 0) OR (len = WinSql.SQL_NULL_DATA) THEN
					IF str = NIL THEN NEW(str, 1) END;
					str^ := ""
				ELSIF len = WinSql.SQL_NO_TOTAL THEN
					(* how to improve handling of strings with undefined length? *)
					IF (str = NIL) OR (LEN(str^) < LEN(s)) THEN NEW(str, LEN(s)) END;
					str^ := s$
				ELSE
					IF (str = NIL) OR (LEN(str^) < len + 1) THEN NEW(str, len + 1) END;
					IF len >= LEN(s) THEN
						sp := TempString(t.driver, LEN(str^)); sp^ := s$;
						Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_CHAR,
												SYSTEM.ADR(sp^) + (LEN(s) - 1), LEN(str^) - (LEN(s) - 1), len), NIL, t.stmt, res);
						str^ := sp$
					ELSE
						str^ := s$
					END
				END
			END
		END;
		t.res := res
	END ReadVarString;

	PROCEDURE (t: Table) ReadBlob (row, column: INTEGER; OUT len: INTEGER;
														OUT data: POINTER TO ARRAY OF BYTE);
		VAR res, x: INTEGER; s: ARRAY 128000 OF BYTE;
	(* This version fails for some large blobs for an unknown reason. Buffer is so large that error happens rarely *)
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.stmt # 0, 24);
		SetPos(t, row, column, res);
		IF res = 0 THEN
			Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_BINARY,
														SYSTEM.ADR(s), LEN(s), len),
					NIL, t.stmt, res);
			IF res # noData THEN
				IF len = WinSql.SQL_NULL_DATA THEN len := 0
				ELSIF len = WinSql.SQL_NO_TOTAL THEN len := 256
				END;
				IF len > 0 THEN
					IF len > LEN(s) THEN
						IF (data = NIL) OR (LEN(data^) < len) THEN
						(* brute force unblock the connection for the following NEW, which may invoke finalizers that access
							the connection: *)
							IF row = 0 THEN SetPos(t, row+1, column, res) ELSE SetPos(t, row-1, column, res) END ;
							(* TODO: what happens if the table has only one row?*)
							SetPos(t, row, column, res);
							NEW(data, len);
							(* read all data at once *)
							Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_BINARY,
															SYSTEM.ADR(data^), len, x), NIL, t.stmt, res)
						ELSE
							SYSTEM.MOVE(SYSTEM.ADR(s), SYSTEM.ADR(data^), LEN(s));
							Check(WinSql.SQLGetData(t.stmt, SHORT(column + 1), WinSql.SQL_C_BINARY,
															SYSTEM.ADR(data^) + LEN(s), len - LEN(s), x), NIL, t.stmt, res)
						END
					ELSE
						IF (data = NIL) OR (LEN(data^) < len) THEN NEW(data, len) END;
						SYSTEM.MOVE(SYSTEM.ADR(s), SYSTEM.ADR(data^), len);
					END
				END
			END
		END;
		t.res := res
	END ReadBlob;

	PROCEDURE (t: Table) ReadName (column: INTEGER; OUT str: SqlDrivers.String);
		VAR res, len: INTEGER; nlen, sqlType, scale, null: SHORTINT; name: ARRAY 64 OF SHORTCHAR;
			ss: POINTER TO ARRAY OF SHORTCHAR;
	BEGIN
		ASSERT(column >= 0, 20); ASSERT(column < t.columns, 21);
		ASSERT(t.stmt # 0, 22);
		Check(WinSql.SQLDescribeCol(t.stmt, SHORT(column + 1), name, LEN(name),
														nlen, sqlType, len, scale, null), NIL, t.stmt, res);
		IF (nlen = 0) OR (res = noData) THEN nlen := 0; name := "" END;
		IF (str = NIL) OR (LEN(str^) < nlen + 1) THEN NEW(str, nlen + 1) END;
		IF nlen >= LEN(name) THEN
			ss := TempString(t.driver, LEN(str));
			Check(WinSql.SQLDescribeCol(t.stmt, SHORT(column + 1), ss^, SHORT(LEN(str^)),
															nlen, sqlType, len, scale, null),
					NIL, t.stmt, res);
			str^ := ss$
		ELSE str^ := name$
		END;
		t.res := res
	END ReadName;

	PROCEDURE (t: Table) ReadType (column: INTEGER; OUT str: SqlDrivers.String);
		VAR res, len: INTEGER; nlen, sqlType, scale, null: SHORTINT;
	BEGIN
		ASSERT(column >= 0, 20); ASSERT(column < t.columns, 21);
		ASSERT(t.stmt # 0, 22);
		IF (str = NIL) OR (LEN(str^) < 10) THEN NEW(str, 10) END;
		Check(WinSql.SQLDescribeCol(t.stmt, SHORT(column + 1), NIL, 0, nlen, sqlType, len, scale, null),
														NIL, t.stmt, res);
		IF res # noData THEN
			CASE sqlType OF
			| WinSql.SQL_BIT: str^ := "BOOLEAN"
			| WinSql.SQL_TINYINT: str^ := "BYTE"
			| WinSql.SQL_SMALLINT: str^ := "SHORTINT"
			| WinSql.SQL_INTEGER: str^ := "INTEGER"
			| WinSql.SQL_BIGINT: str^ := "String"
			| WinSql.SQL_DATE: str^ := "Date"
			| WinSql.SQL_TIME: str^ := "Time"
			| WinSql.SQL_TIMESTAMP: str^ := "Time&Date"
			| WinSql.SQL_REAL: str^ := "SHORTREAL"
			| WinSql.SQL_DOUBLE, WinSql.SQL_FLOAT: str^ := "REAL"
			| WinSql.SQL_DECIMAL, WinSql.SQL_NUMERIC: str^ := "Currency"
			| WinSql.SQL_CHAR, WinSql.SQL_VARCHAR, WinSql.SQL_LONGVARCHAR: str^ := "String"
			| WinSql.SQL_BINARY, WinSql.SQL_VARBINARY, WinSql.SQL_LONGVARBINARY: str^ := "Binary"
			ELSE str^ := "unknown"
			END
		ELSE str^ := "unknown"
		END
	END ReadType;

	PROCEDURE (t: Table) Cleanup;
		VAR res: INTEGER;
	BEGIN
		Check(WinSql.SQLFreeStmt(t.stmt, WinSql.SQL_DROP), NIL, t.stmt, res)
	END Cleanup;


	PROCEDURE Open* (id, password, datasource: ARRAY OF CHAR; async, showErr: BOOLEAN;
											OUT d: SqlDrivers.Driver; OUT res: INTEGER);
		VAR h: Driver; ss1, ss2, ss3: ARRAY 256 OF SHORTCHAR; r: INTEGER; len: SHORTINT;
	BEGIN
		NEW(h); d := NIL;
		res := WinSql.SQL_SUCCESS;
		IF numConnections = 0 THEN
			res := WinSql.SQLAllocEnv(environment);
		END;
		IF res = WinSql.SQL_SUCCESS THEN
			h.showErr := showErr;
			Check(WinSql.SQLAllocConnect(environment, h.dbc), h, 0, res);
			Check(WinSql.SQLSetConnectOption(h.dbc, WinSql.SQL_QUIET_MODE, HostWindows.main), h, 0, r);
			IF res = 0 THEN
				Check(WinSql.SQLConnect(h.dbc, ShortString(datasource, ss1), WinSql.SQL_NTS,
													ShortString(id, ss2), WinSql.SQL_NTS,
													ShortString(password, ss3), WinSql.SQL_NTS), h, 0, res);
				IF res = 0 THEN
					h.Init("?");
					Check(WinSql.SQLGetInfo(h.dbc, WinSql.SQL_FETCH_DIRECTION,
															SYSTEM.ADR(h.directions), 4, len), h, 0, r);
					(* ODBC default is SQL_AUTOCOMMIT_ON *) 
					IF ~autoCommit THEN
						Check(WinSql.SQLSetConnectOption(h.dbc, WinSql.SQL_AUTOCOMMIT,
																				WinSql.SQL_AUTOCOMMIT_OFF), h, 0, r);
					END;
					Check(WinSql.SQLSetConnectOption(h.dbc, 1200+4, 1), h, 0,r);	(* set Preserve Cursors ON *)
					h.showErr := showErr;
					h.state := connecting; d := h; INC(numConnections)
				ELSE
					Check(WinSql.SQLFreeConnect(h.dbc), h, 0, r);
					IF numConnections = 0 THEN
						Check(WinSql.SQLFreeEnv(environment), NIL, 0, r)
					END;
					IF res # wrongIdentification THEN res := cannotOpenDB END
				END
			ELSE
				IF numConnections = 0 THEN
					Check(WinSql.SQLFreeEnv(environment), NIL, 0, r)
				END;
				res := cannotOpenDB
			END
		ELSE res := cannotOpenDB
		END
	END Open;

	PROCEDURE SetMode* (d: SqlDrivers.Driver; autocommit: BOOLEAN; OUT res: INTEGER);
		(* implicit COMMIT *)
		VAR h: Driver;
	BEGIN
		h := d(Driver);
		IF autocommit THEN
			Check(WinSql.SQLSetConnectOption(h.dbc, WinSql.SQL_AUTOCOMMIT,
																	WinSql.SQL_AUTOCOMMIT_ON), h, 0, res)
		ELSE
			Check(WinSql.SQLSetConnectOption(h.dbc, WinSql.SQL_AUTOCOMMIT,
																	WinSql.SQL_AUTOCOMMIT_OFF), h, 0, res)
		END
	END SetMode;

END SqlOdbc.