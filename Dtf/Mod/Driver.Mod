MODULE DtfDriver;
(**
	project	= "BlackBox"
	organization	= "www.oberon.ch"
	contributors	= "Oberon microsystems, Werner Braun"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""

**)

	IMPORT Log,
		SYSTEM, WinApi, Kernel, Strings, Dates, Dialog,
		SqlDrivers, Dtf := DtfApi;

	CONST
		connectionsExceeded = 4;
		outOfTables = 5;
		notExecutable = 6;
		cannotOpenDB = 7;
		wrongIdentification = 8;
		tooManyBlobs = 9;
		deadLock = 10;

		converted = 1;
		truncated = 2;
		overflow = 3;
		incompatible = 4;

		connecting = 1;
		connected = 2;
		executing = 3;
		closed = 4;
		
	TYPE
		Driver = POINTER TO RECORD (SqlDrivers.Driver)
			state: SHORTINT;	(* connecting, connected, executing, closed *)
			actWsh: Dtf.wsHandle;
			string: POINTER TO ARRAY OF SHORTCHAR	(* cached temp string *)
		END;

		Table = POINTER TO RECORD (SqlDrivers.Table)
			rows, columns: INTEGER;
			wsh: Dtf.wsHandle;
			driver: Driver
		END;

	VAR
		debug*: BOOLEAN;
		showErrors: BOOLEAN;	(* show error messages *)
		drivers: SHORTINT;	(* number of allocated drivers *)
		actDatasource: ARRAY 32 OF CHAR;	(* actual database *)
		

	(* platform specific code *)

	PROCEDURE HandleException (code: Dtf.Word; group, desc, sqlstr: Dtf.MemPtr;
													errpos: Dtf.Word): Dtf.ErrType;
		VAR s: ARRAY 32 OF SHORTCHAR; str: ARRAY 512 OF SHORTCHAR; res, i: INTEGER; ns: ARRAY 16 OF CHAR;
		CONST groupMax = 100; descMax = LEN(str) - 100; sqlMax = LEN(str) - 1;
	BEGIN
		IF showErrors THEN
			SYSTEM.MOVE(group, SYSTEM.ADR(str), groupMax); str[groupMax] := 0X;
			i := LEN(str$); str[i] := 0DX; INC(i); str[i] := 0AX; INC(i);
			SYSTEM.MOVE(desc, SYSTEM.ADR(str[i]), descMax - i); str[descMax] := 0X;
			i := LEN(str$); str[i] := 0DX; INC(i); str[i] := 0AX; INC(i);
			SYSTEM.MOVE(sqlstr, SYSTEM.ADR(str[i]), sqlMax - i); str[sqlMax] := 0X;
			Strings.IntToString(code, ns); 
			s := "SQL Error " + SHORT(ns$);
			res := WinApi.MessageBox(0, str, s, {})
		ELSIF debug THEN
			SYSTEM.MOVE(group, SYSTEM.ADR(str), LEN(str)); str[LEN(str) - 1] := 0X;
			Log.String(str$); Log.Ln;
			SYSTEM.MOVE(desc, SYSTEM.ADR(str), LEN(str)); str[LEN(str) - 1] := 0X;
			Log.String(str$); Log.Ln;
			SYSTEM.MOVE(sqlstr, SYSTEM.ADR(str), LEN(str)); str[LEN(str) - 1] := 0X;
			Log.String(str$); Log.Ln;
		END;
		RETURN code
	END HandleException;
	
	PROCEDURE ShortString (IN str: ARRAY OF CHAR; VAR static: ARRAY OF SHORTCHAR): Dtf.MemPtr;
		VAR p: Dtf.MemPtr; sp: POINTER TO ARRAY OF SHORTCHAR;
	BEGIN
		IF LEN(str) <= LEN(static) THEN static := SHORT(str$); p := static
		ELSE NEW(sp, LEN(str)); sp^ := SHORT(str$); p := sp^
		END;
		RETURN p
	END ShortString;
	
	PROCEDURE TempString (d: Driver; len: INTEGER): POINTER TO ARRAY OF SHORTCHAR;
	BEGIN
		IF (d.string = NIL) OR (LEN(d.string) < len) THEN NEW(d.string, len) END;
		RETURN d.string
	END TempString;
	
	(* end of platform specific code *)


	(* Driver *)

	PROCEDURE (d: Driver) Ready (): BOOLEAN;
	BEGIN
		RETURN d.state # closed
	END Ready;

	PROCEDURE (d: Driver) EndOpen (OUT res: INTEGER);
	(* Pre: d.Ready()	20 *)
	BEGIN
		d.state := connected; res := 0
	END EndOpen;

	PROCEDURE (d: Driver) BeginExec (IN statement: ARRAY OF CHAR; data: SqlDrivers.Blob;
														async, showErr: BOOLEAN; OUT res: INTEGER);
	(* Pre: statement # ""	20
				no other execution started	21 *)
	(* Post: res = 0 <=> execution has started and should be completed later with EndExec
				~async => d.Ready() *)
		VAR wsh: Dtf.wsHandle; ignore: INTEGER; p : Dtf.MemPtr; ss: ARRAY 256 OF SHORTCHAR;
	BEGIN
		ASSERT(statement # "", 20); ASSERT(d.state = connected, 21);
		IF debug THEN Log.String(statement); Log.Ln END;
		IF (data = NIL) OR (data.next = NIL) THEN
			wsh := Dtf.getWS();
			IF wsh = 0 THEN
				Kernel.Collect; wsh := Dtf.getWS()
			END;
			IF wsh # 0 THEN
				IF data # NIL THEN
					p := SYSTEM.VAL(Dtf.MemPtr, SYSTEM.ADR(data.data^));
					p := Dtf.setBlobWS(wsh, p, data.len)
				END;
				showErrors := showErr;
				res := Dtf.execWS(wsh, ShortString(statement, ss));
				showErrors := FALSE;
				IF res = 0 THEN
					d.state := executing; d.actWsh := wsh
				ELSE	(* execution failed *)
					ignore := Dtf.releaseWS(wsh);
					IF (res = Dtf.edcTaSysEnded0) OR (res = Dtf.edcTaStoppedC0) THEN
						res := deadLock
					ELSE
						res := notExecutable
					END
				END
			ELSE	(* no workspace available *)
				res := outOfTables
			END
		ELSE res := tooManyBlobs
		END
	END BeginExec;

	PROCEDURE (d: Driver) EndExec (VAR t: SqlDrivers.Table; OUT rows, columns, res: INTEGER);
	(* Pre: execution must have been started successfully with BeginExec	20
				d.Ready()	21 *)
	(* Post: res = 0  <=>  (t # NIL) OR (rows = 0) & (columns = 0) *)
		VAR h: Table; ignore: INTEGER;
	BEGIN
		ASSERT(d.state = executing, 20);
		d.state := connected;
		IF Dtf.resultAvailableWS(d.actWsh) = Dtf.True THEN	(* SELECT statement *)
			NEW(h); h.Init(d); h.driver := d;
			h.rows := Dtf.rowsWS(d.actWsh);
			h.columns := ORD(Dtf.colsWS(d.actWsh)); ASSERT(h.columns > 0, 102);
			h.wsh := d.actWsh;
			t := h; columns := h.columns; rows := h.rows; res := 0
		ELSE
			ignore := Dtf.releaseWS(d.actWsh);
			t := NIL; columns := 0; rows := 0; res := 0
		END
	END EndExec;

	PROCEDURE (d: Driver) Commit (accept: BOOLEAN; OUT res: INTEGER);
	BEGIN
		IF accept THEN res := Dtf.exec("commit")
		ELSE res := Dtf.exec("rollback")
		END;
		IF res # 0 THEN res := notExecutable END
	END Commit;

	PROCEDURE (d: Driver) Cleanup;
		VAR res: SHORTINT; (* War mal Integer, gab Probleme beim Stop *)
	BEGIN
		DEC(drivers);
		IF drivers = 0 THEN res := Dtf.stop() END;
		d.state := closed;
	END Cleanup;
	

	(* Table *)
	
	PROCEDURE (t: Table) ReadInteger (row, column: INTEGER; OUT val: INTEGER);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res, len: INTEGER; i: SHORTINT; s: BYTE; type: Dtf.colTypeRange;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF len = 0 THEN val := 0
		ELSIF (type = Dtf.colTypeLong) OR (type = Dtf.colTypeLongWord) THEN
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(val), 4, NIL, NIL);
			ASSERT(res = 0, 102);
			IF (type = Dtf.colTypeLongWord) & (val < 0) THEN
				val := 0; t.res := overflow
			END
		ELSIF (type = Dtf.colTypeShort) OR (type = Dtf.colTypeWord) THEN
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(i), 2, NIL, NIL); val := i;
			ASSERT(res = 0, 102);
			IF (type = Dtf.colTypeWord) & (val < 0) THEN val := val + 65536 END
		ELSIF (type = Dtf.colTypeChar) OR (type = Dtf.colTypeByte) THEN
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(s), 1, NIL, NIL); val := s;
			ASSERT(res = 0, 102);
			IF (type = Dtf.colTypeByte) & (val < 0) THEN val := val + 256 END
		ELSE val := 0; t.res := incompatible
		END;
	END ReadInteger;

	PROCEDURE (t: Table) ReadReal (row, column: INTEGER; OUT val: REAL);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res, len: INTEGER; type: Dtf.colTypeRange;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF len = 0 THEN val := 0
		ELSIF type = Dtf.colTypeReal THEN
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(val), 8, NIL, NIL);
			ASSERT(res = 0, 102)
		ELSE val := 0; t.res := incompatible
		END
	END ReadReal;

	PROCEDURE (t: Table) ReadDate (row, column: INTEGER; OUT val: Dates.Date);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res, len: INTEGER; date: Dtf.date; type: Dtf.colTypeRange; d, m, y: SHORTINT;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF (len > 0) & (type = Dtf.colTypeDate) THEN
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(date), SIZE(Dtf.date), NIL, NIL);
			ASSERT(res = 0, 102);
			Dtf.convtFromDate(date, d, m, y);
			val.day := d; val.month := m; val.year := y
		ELSE
			val.day := 0; val.month := 0; val.year := 0;
			IF len > 0 THEN t.res := incompatible END
		END
	END ReadDate;

	PROCEDURE (t: Table) ReadTime (row, column: INTEGER; OUT val: Dates.Time);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res, len: INTEGER; time: Dtf.time; type: Dtf.colTypeRange; s, m, h: SHORTINT;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF (len > 0) & (type = Dtf.colTypeTime) THEN
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(time), SIZE(Dtf.time), NIL, NIL);
			ASSERT(res = 0, 102);
			Dtf.convtFromTime(time, s, m, h);
			val.second := s; val.minute := m; val.hour := h
		ELSE
			val.second := 0; val.minute := 0; val.hour := 0;
			IF len > 0 THEN t.res := incompatible END
		END
	END ReadTime;

	PROCEDURE (t: Table) ReadCurrency (row, column: INTEGER; OUT val: Dialog.Currency);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res, len: INTEGER; decimal: Dtf.decimal; type: Dtf.colTypeRange;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF (len > 0) & (type >= Dtf.colTypeDecimal) & (type < Dtf.colTypeDecimal + Dtf.decimalRanges) THEN
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(decimal), SIZE(Dtf.decimal), NIL, NIL);
			ASSERT(res = 0, 102);
			val.val := decimal.value; val.scale := ORD(decimal.prec)
		ELSE
			val.val := 0; val.scale := 0;
			IF len > 0 THEN t.res := incompatible END
		END
	END ReadCurrency;

	PROCEDURE (t: Table) ReadString (row, column: INTEGER; OUT str: ARRAY OF CHAR);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res, len: INTEGER; time: Dtf.decimal; type: Dtf.colTypeRange;
			p: POINTER TO ARRAY OF SHORTCHAR; buf, s: ARRAY 64 OF SHORTCHAR;
			mp: Dtf.MemPtr; ns: ARRAY 16 OF CHAR;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF len = 0 THEN	(* NULL value *)
			str := ""
		ELSIF (type = Dtf.colTypeShortString) OR (type = Dtf.colTypeHugeString) THEN
			IF LEN(str) >= len THEN
				p := TempString(t.driver, LEN(str));
				res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(p^), LEN(str), NIL, NIL);
				ASSERT(res = 0, 102)
			ELSE	(* truncate string *)
				p := TempString(t.driver, len);
				res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(p^), len, NIL, NIL);
				ASSERT(res = 0, 102);
				p[LEN(str) - 1] := 0X; t.res := truncated
			END;
			str := p$
		ELSE
			IF type = Dtf.colTypeBit THEN
				Strings.IntToString(len, ns); s := SHORT(ns$) + " byte blob"
			ELSE
				res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(buf), LEN(buf), NIL, NIL);
				ASSERT(res = 0, 102);
				mp := Dtf.convtToStr(type, s, buf, LEN(s), 0);
				ASSERT(mp # NIL, 103)
			END;
			len := LEN(s$) + 1;
			t.res := converted;
			IF LEN(str) < len THEN
				s[LEN(str) - 1] := 0X;
				t.res := truncated
			END;
			str := s$
		END
	END ReadString;

	PROCEDURE (t: Table) ReadVarString (row, column: INTEGER; OUT str: SqlDrivers.String);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res, len: INTEGER; buf, s: ARRAY 64 OF SHORTCHAR; type: Dtf.colTypeRange; p: Dtf.MemPtr;
			sp: POINTER TO ARRAY OF SHORTCHAR; ns: ARRAY 16 OF CHAR;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF len = 0 THEN	(* NULL value *)
			IF str = NIL THEN NEW(str, 1) END;
			str^ := ""
		ELSIF (type = Dtf.colTypeShortString) OR (type = Dtf.colTypeHugeString) THEN
			IF (str = NIL) OR (LEN(str^) < len) THEN NEW(str, len) END;
			sp := TempString(t.driver, LEN(str));
			res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(sp^), len, NIL, NIL);
			str^ := sp$;
			ASSERT(res = 0, 102)
		ELSE
			IF type = Dtf.colTypeBit THEN
				Strings.IntToString(len, ns); s := SHORT(ns$) + " byte blob"
			ELSE
				res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(buf), LEN(buf), NIL, NIL);
				ASSERT(res = 0, 102);
				p := Dtf.convtToStr(type, s, buf, LEN(s), 0);
				ASSERT(p # NIL, 103)
			END;
			len := LEN(s$) + 1;
			IF (str = NIL) OR (LEN(str^) < len) THEN NEW(str, len) END;
			str^ := s$;
			t.res := converted
		END
	END ReadVarString;

	PROCEDURE (t: Table) ReadBlob (row, column: INTEGER; OUT len: INTEGER;
														OUT data: POINTER TO ARRAY OF BYTE);
	(** Pre: row >= 0	20
				row < rows	21
				column >= 0	22
				column < columns	23 **)
		VAR res: INTEGER; type: Dtf.colTypeRange;
	BEGIN
		ASSERT(row >= 0, 20); ASSERT(row < t.rows, 21);
		ASSERT(column >= 0, 22); ASSERT(column < t.columns, 23);
		ASSERT(t.wsh # 0, 24);
		res := Dtf.moveWS(t.wsh, Dtf.moveStart, row); ASSERT(res = 0, 100);
		res := Dtf.getFieldInfoWS(t.wsh, SHORT(CHR(column)), len, type); ASSERT(res = 0, 101);
		IF len > 0 THEN
			IF type = Dtf.colTypeBit THEN
				IF (data = NIL) OR (LEN(data^) < len) THEN NEW(data, len) END;
				IF data # NIL THEN
					res := Dtf.getFieldWS(t.wsh, SHORT(CHR(column)), SYSTEM.ADR(data^), len, NIL, NIL);
					ASSERT(res = 0, 102)
				END
			ELSE t.res := incompatible
			END
		END
	END ReadBlob;

	PROCEDURE (t: Table) ReadName (column: INTEGER; OUT str: SqlDrivers.String);
	(** Pre: column >= 0	20
				column < columns	21 **)
		VAR info: Dtf.cinfoEntry; len, res: INTEGER;
	BEGIN
		ASSERT(column >= 0, 20); ASSERT(column < t.columns, 21);
		ASSERT(t.wsh # 0, 22);
		res := Dtf.cinfoPWS(t.wsh, SHORT(CHR(column)), info);
		ASSERT(res = 0, 100);
		len := LEN(info.column$) + 1;
		IF (str = NIL) OR (LEN(str^) < len) THEN NEW(str, len) END;
		str^ := info.column$
	END ReadName;

	PROCEDURE (t: Table) ReadType (column: INTEGER; OUT str: SqlDrivers.String);
	(** Pre: column >= 0	20
				column < columns	21 **)
		VAR info: Dtf.cinfoEntry; s: ARRAY 32 OF CHAR; len, res: INTEGER;
	BEGIN
		ASSERT(column >= 0, 20); ASSERT(column < t.columns, 21);
		ASSERT(t.wsh # 0, 22);
		res := Dtf.cinfoPWS(t.wsh, SHORT(CHR(column)), info);
		ASSERT(res = 0, 100);
		IF (info.type >= Dtf.colTypeDecimal)
			& (info.type < Dtf.colTypeDecimal+Dtf.decimalRanges) THEN s := "Currency"
		ELSIF info.type = Dtf.colTypeByte THEN s := "BYTE"
		ELSIF info.type = Dtf.colTypeWord THEN s := "SHORTINT"
		ELSIF info.type = Dtf.colTypeLongWord THEN s := "INTEGER"
		ELSIF info.type = Dtf.colTypeChar THEN s := "BYTE"
		ELSIF info.type = Dtf.colTypeShort THEN s := "SHORTINT"
		ELSIF info.type = Dtf.colTypeLong THEN s := "INTEGER"
		ELSIF info.type = Dtf.colTypeReal THEN s := "REAL"
		ELSIF info.type = Dtf.colTypeShortString THEN s := "String"
		ELSIF info.type = Dtf.colTypeHugeString THEN s := "String"
		ELSIF info.type = Dtf.colTypeDate THEN s := "Date"
		ELSIF info.type = Dtf.colTypeTime THEN s := "Time"
		ELSIF info.type = Dtf.colTypeBit THEN s := "Binary"
		ELSIF info.type = Dtf.colTypeUndefined THEN s := "undefined"
		ELSE s := "unknown"
		END;
		len := LEN(s$) + 1;
		IF (str = NIL) OR (LEN(str^) < len) THEN NEW(str, len) END;
		str^ := s$
	END ReadType;

	PROCEDURE (t: Table) Cleanup;
		VAR res: INTEGER;
	BEGIN
		ASSERT(t.wsh # 0, 100);
		res := Dtf.releaseWS(t.wsh);
		t.wsh := 0
	END Cleanup;


	PROCEDURE Open* (id, password, datasource: ARRAY OF CHAR;
									async, showErr: BOOLEAN; OUT d: SqlDrivers.Driver; OUT res: INTEGER);
		VAR h: Driver; s1, s2: ARRAY 256 OF SHORTCHAR; m: Dtf.MemPtr; p: Dtf.exceptionProc;
	BEGIN
		showErrors := showErr;
		IF (drivers = 0) OR (datasource = actDatasource) THEN
			IF drivers = 0 THEN
				IF datasource # "" THEN
					(* Only use datasource, if provided, otherwise use default *)
					res := Dtf.setAttribStr(Dtf.keyDomainConnection,Dtf.keyFilename,ShortString(datasource, s1)^);
				END;
				p := Dtf.setCritical(HandleException);
				p := Dtf.setError(HandleException);
				p := Dtf.setWarning(HandleException);
				res := Dtf.ident(ShortString(id, s1)^, ShortString(password, s2)^);
				IF res = 0 THEN
					showErrors := FALSE;
					res := Dtf.start();
					showErrors := showErr;
					IF res # 0 THEN	(* try to recover database *)
						res := Dtf.recoverDatabase(NIL, Dtf.True);
						res := Dtf.start()
					END;
					IF res = 0 THEN actDatasource := datasource$
					ELSIF res =  8206 THEN res := wrongIdentification
					ELSE res := cannotOpenDB
					END
				ELSE res := wrongIdentification
				END
			ELSE res := 0
			END
		ELSE res := connectionsExceeded
		END;
		IF res = 0 THEN
			NEW(h); h.Init("BLOB");
			h.state := connecting; d := h;
			INC(drivers)
		ELSE d := NIL
		END;
		showErrors := FALSE
	END Open;

END DtfDriver.
