MODULE HostRegistry;
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

	IMPORT KERNEL32, ADVAPI32, HostFiles, Dialog, Strings;
	
	VAR localeId*: INTEGER;

	PROCEDURE ReadString* (
		key: ARRAY OF SHORTCHAR; VAR str: ARRAY OF SHORTCHAR; VAR res: INTEGER
	);
		VAR r, len: INTEGER; sw, comp, appl, vers: ADVAPI32.Handle; an: ARRAY 32 OF SHORTCHAR;
	BEGIN
		res := ADVAPI32.RegOpenKeyA(ADVAPI32.KeyCurrentUser, "Software", sw);
		IF res = 0 THEN
			res := ADVAPI32.RegOpenKeyA(sw, "Oberon", comp);
			IF res = 0 THEN
				an := SHORT(Dialog.appName$);
				res := ADVAPI32.RegOpenKeyA(comp, an, appl);
				IF res = 0 THEN
					res := ADVAPI32.RegOpenKeyA(appl, "CurrentVersion", vers);
					IF res = 0 THEN
						len := LEN(str);
						res := ADVAPI32.RegQueryValueA(vers, key, str, len);
						r := ADVAPI32.RegCloseKey(vers)
					END;
					r := ADVAPI32.RegCloseKey(appl)
				END;
				r := ADVAPI32.RegCloseKey(comp)
			END;
			r := ADVAPI32.RegCloseKey(sw)
		END
	END ReadString;
	
	PROCEDURE ReadInt* (key: ARRAY OF SHORTCHAR; VAR x: INTEGER; VAR res: INTEGER);
		VAR str: ARRAY 64 OF SHORTCHAR; s: ARRAY 64 OF CHAR;
	BEGIN
		ReadString(key, str, res); s := str$;
		IF res = 0 THEN Strings.StringToInt(s, x, res) END;
	END ReadInt;
	
	PROCEDURE ReadBool* (key: ARRAY OF SHORTCHAR; VAR x: BOOLEAN; VAR res: INTEGER);
		VAR str: ARRAY 4 OF SHORTCHAR;
	BEGIN
		ReadString(key, str, res);
		IF res = 0 THEN x := str = "1" END
	END ReadBool;
	
	PROCEDURE ReadIntList* (key: ARRAY OF SHORTCHAR; VAR x: ARRAY OF INTEGER; VAR res: INTEGER);
		VAR i, n, val, sig: INTEGER; str: ARRAY 256 OF SHORTCHAR;
	BEGIN
		ReadString(key, str, res);
		IF res = 0 THEN
			n := 0; i := 0;
			WHILE str[i] # 0X DO
				IF n >= LEN(x) THEN res := 2; RETURN END;
				val := 0; sig := 1;
				IF str[i] = "-" THEN sig := -1; INC(i) END;
				WHILE (str[i] >= "0") & (str[i] <= "9") DO val := 10 * val + ORD(str[i]) - ORD("0"); INC(i) END;
				x[n] := sig * val;
				IF str[i] = "," THEN INC(i)
				ELSIF str[i] # 0X THEN res := 1; RETURN
				END;
				INC(n)
			END
		END
	END ReadIntList;
	
	PROCEDURE WriteString* (key: ARRAY OF SHORTCHAR; str: ARRAY OF SHORTCHAR);
		VAR res, n: INTEGER; sw, comp, appl, vers: ADVAPI32.Handle; an: ARRAY 32 OF SHORTCHAR;
	BEGIN
		res := ADVAPI32.RegCreateKeyA(ADVAPI32.KeyCurrentUser, "Software", sw);
		IF res = 0 THEN
			res := ADVAPI32.RegCreateKeyA(sw, "Oberon", comp);
			IF res = 0 THEN
				an := SHORT(Dialog.appName$);
				res := ADVAPI32.RegCreateKeyA(comp, an, appl);
				IF res = 0 THEN
					res := ADVAPI32.RegCreateKeyA(appl, "CurrentVersion", vers);
					IF res = 0 THEN
						n := 0;
						WHILE (n < LEN(str)) & (str[n] # 0X) DO INC(n) END;
						res := ADVAPI32.RegSetValueA(vers, key, 1, str, n);
					END;
					res := ADVAPI32.RegCloseKey(appl)
				END;
				res := ADVAPI32.RegCloseKey(comp)
			END;
			res := ADVAPI32.RegCloseKey(sw)
		END
	END WriteString;
	
	PROCEDURE WriteInt* (key: ARRAY OF SHORTCHAR; x: INTEGER);
		VAR str: ARRAY 64 OF CHAR;
	BEGIN
		Strings.IntToString(x, str);
		WriteString(key, SHORT(str))
	END WriteInt;
	
	PROCEDURE WriteBool* (key: ARRAY OF SHORTCHAR; x: BOOLEAN);
	BEGIN
		IF x THEN WriteString(key, "1") ELSE WriteString(key, "0") END
	END WriteBool;
	
	PROCEDURE WriteIntList* (key: ARRAY OF SHORTCHAR; VAR x: ARRAY OF INTEGER);
		VAR i,j,  n: INTEGER; str: ARRAY 256 OF SHORTCHAR; s: ARRAY 16 OF CHAR;
	BEGIN
		n := 0; i := 0;
		WHILE n < LEN(x) DO
			IF (n > 0) & (i < LEN(str)) THEN str[i] := ","; INC(i) END;
			Strings.IntToString(x[n], s); j := 0;
			WHILE (s[j] # 0X) & (i < LEN(str)) DO str[i] := SHORT(s[j]); INC(i); INC(j) END;
			INC(n)
		END;
		IF i < LEN(str) THEN str[i] := 0X ELSE str[LEN(str) - 1] := 0X END;
		WriteString(key, str)
	END WriteIntList;
	

	PROCEDURE ReadMeasure;
		VAR res, len: INTEGER; cp, int: ADVAPI32.Handle; str: ARRAY 4 OF SHORTCHAR;
	BEGIN
		res := KERNEL32.GetProfileIntA("intl", "iMeasure", 1);
		Dialog.metricSystem := res = 0
	END ReadMeasure;
	
	PROCEDURE Init;
		VAR name, bname: Dialog.String; res, i, v: INTEGER;
	BEGIN
		v := KERNEL32.GetVersion();
		localeId := 1024;	(* user default *)
		name := HostFiles.appName$;
		bname := "BLACKBOX"; i := 0;
		WHILE (i < 8) & (CAP(name[i]) = bname[i]) DO INC(i) END;
		IF i = 8 THEN
			name := "BlackBox"
		ELSIF (v < 0) & (v MOD 256 < 4) THEN
			i := 1;
			WHILE name[i] # 0X DO
				IF (name[i] >= "A") & (name[i] <= "Z") THEN name[i] := CHR(ORD(name[i]) + ORD("a") - ORD("A")) END;
				INC(i)
			END
		END;
		Dialog.appName := name$;
		Dialog.version := 15;
		Dialog.Call("Startup.Setup", "", res);
		ReadMeasure
	END Init;

BEGIN
	Init
END HostRegistry.