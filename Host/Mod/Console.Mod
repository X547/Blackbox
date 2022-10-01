MODULE HostConsole;

(**
	project	= "BlackBox"
	organization	= "blackboxframework.org/"
	contributors	= "A. V. Shiryaev"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""

**)

	IMPORT WinApi, SYSTEM;

	VAR
		open: BOOLEAN;
		stdIn, stdOut: INTEGER;
		
		(* for logging *)
		on, showPrefix, lineStarted: BOOLEAN;
		lineNr, indent, offAtLineNr: INTEGER;


	(* ------ interface to console I/O ------ *)

	PROCEDURE Open*;
		VAR res: INTEGER;
	BEGIN
		IF ~open THEN
			res := WinApi.AllocConsole();
			stdIn := WinApi.GetStdHandle(WinApi.STD_INPUT_HANDLE);
			ASSERT(stdIn # WinApi.INVALID_HANDLE_VALUE);
			stdOut := WinApi.GetStdHandle(WinApi.STD_OUTPUT_HANDLE);
			ASSERT(stdOut # WinApi.INVALID_HANDLE_VALUE);
			open := TRUE
		END
	END Open;

	PROCEDURE ReadLn* (OUT line: ARRAY OF CHAR);
		VAR buf: ARRAY 256 OF SHORTCHAR; res, read: INTEGER;
	BEGIN
		Open; line := "";
		res := WinApi.ReadFile(stdIn, SYSTEM.ADR(buf), LEN(buf), read, NIL);
		IF (res # 0) & (read >= 2) THEN buf[read - 2] := 0X; (* removes CRLF *)
			IF buf # "" THEN
				res := WinApi.MultiByteToWideChar(WinApi.CP_OEMCP, {}, buf, LEN(buf$), line, LEN(line) - 1);
				IF (res > 0) & (res < LEN(line)) THEN line[res] := 0X ELSE line := "" END
			END
		END
	END ReadLn;

	PROCEDURE WriteStr* (IN str: ARRAY OF CHAR);
		VAR res, remaining, i, n: INTEGER; si: WinApi.PtrWSTR;
			buf: ARRAY 256 OF SHORTCHAR;
	BEGIN
		Open;
		remaining := LEN(str$); i := 0;
		WHILE remaining > 0 DO
			n := MIN(remaining, LEN(buf) DIV 2);
			si := SYSTEM.VAL(WinApi.PtrWSTR, SYSTEM.ADR(str[i]));
			res := WinApi.WideCharToMultiByte(WinApi.CP_OEMCP, {}, si, n, buf, LEN(buf), NIL, NIL);
			IF ~((res > 0) & (res <= LEN(buf))) THEN
				buf := "*** WideCharToMultiByte error in HostConsole.WriteStr ***"; res := LEN(buf$);
			END;
			res := WinApi.WriteFile(stdOut, SYSTEM.ADR(buf), res, NIL, NIL);
			res := WinApi.FlushFileBuffers(stdOut);
			INC(i, n); DEC(remaining, n)
		END
	END WriteStr;

	PROCEDURE WriteSStr* (IN str: ARRAY OF SHORTCHAR);
		VAR res: INTEGER;
	BEGIN
		Open;
		res := WinApi.WriteFile(stdOut, SYSTEM.ADR(str), LEN(str$), NIL, NIL);
		res := WinApi.FlushFileBuffers(stdOut)
	END WriteSStr;

	PROCEDURE WriteLn*;
		VAR crlf: ARRAY 2 OF SHORTCHAR; res: INTEGER;
	BEGIN
		Open;
		crlf[0] := 0DX; crlf[1] := 0AX;
		res := WinApi.WriteFile(stdOut, SYSTEM.ADR(crlf), LEN(crlf), NIL, NIL);
	END WriteLn;


	(* ------ logging support ------ *)
	
	PROCEDURE^ LinePrefix;

	PROCEDURE OpenLog*;
	BEGIN
		Open; showPrefix := TRUE
	END OpenLog;

	PROCEDURE On*;
	BEGIN
		offAtLineNr := -1; on := TRUE
	END On;

	PROCEDURE OnFor*(nofLines: INTEGER);
	BEGIN
		offAtLineNr := lineNr + nofLines; on := TRUE
	END OnFor;

	PROCEDURE Off*;
	BEGIN
		on := FALSE
	END Off;

	PROCEDURE Indent*;
	BEGIN
		INC(indent)
	END Indent;

	PROCEDURE Undent*;
	BEGIN
		DEC(indent)
	END Undent;

	PROCEDURE String*(IN str: ARRAY OF CHAR);
	BEGIN
		IF on & (str # "") THEN LinePrefix; WriteStr(str) END
	END String;

	PROCEDURE Char*(ch: CHAR);
		VAR s: ARRAY 2 OF CHAR;
	BEGIN
		s[0] := ch; s[1] := 0X; String(s)
	END Char;

	PROCEDURE Bool*(x: BOOLEAN);
	BEGIN
		IF x THEN String(" $TRUE") ELSE String(" $FALSE") END
	END Bool;

	PROCEDURE IntToString(x: LONGINT; OUT s: ARRAY OF CHAR); (* copied from Strings *)
		CONST minLongIntRev = "8085774586302733229";
		VAR j, k: INTEGER; ch: CHAR; a: ARRAY 32 OF CHAR;
	BEGIN
		IF x # MIN(LONGINT) THEN
			IF x < 0 THEN s[0] := "-"; k := 1; x := -x ELSE k := 0 END;
			j := 0; REPEAT a[j] := CHR(x MOD 10 + ORD("0")); x := x DIV 10; INC(j) UNTIL x = 0
		ELSE
			a := minLongIntRev; s[0] := "-"; k := 1; j := LEN(minLongIntRev);
		END;
		ASSERT(k + j < LEN(s), 23);
		REPEAT DEC(j); ch := a[j]; s[k] := ch; INC(k) UNTIL j = 0;
		s[k] := 0X
	END IntToString;

	PROCEDURE Int*(x: LONGINT);
		VAR str: ARRAY 24 OF CHAR;
	BEGIN
		IntToString(x, str); String(" " + str)
	END Int;

	(* outputs the line number and indentation level followed by repeated "  " according to indentation level *)
	PROCEDURE LinePrefix;
		VAR i: INTEGER; lStr, iStr: ARRAY 12 OF CHAR;
	BEGIN
		IF ~lineStarted THEN
			lineStarted := TRUE;
			IF showPrefix THEN
				IntToString(lineNr, lStr);
				IntToString(indent, iStr); String(lStr + ":" + iStr + " ")
			END;
			FOR i := 1 TO indent DO String("  ") END
		END
	END LinePrefix;

	PROCEDURE Ln*;
	BEGIN
		IF on THEN
			LinePrefix; WriteLn;
			INC(lineNr); lineStarted := FALSE;
			IF (offAtLineNr # -1) & (lineNr >= offAtLineNr) THEN on := FALSE END
		END
	END Ln;

	PROCEDURE Pause*;
		VAR line: ARRAY 256 OF CHAR;
	BEGIN
		WriteSStr("Press RETURN to continue . . ."); WriteLn;
		ReadLn(line);
		IF line = "HALT" THEN HALT(0) END
	END Pause;

	PROCEDURE Reset*;
	BEGIN
		On;
		IF lineStarted THEN Ln END;
		lineNr := 1; indent := 0
	END Reset;

BEGIN Reset
END HostConsole.
