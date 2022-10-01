MODULE Console;
(**
	project	= "BlackBox"
	organization	= "Blackbox Framework Center"
	contributors	= "A. V. Shiryaev"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""

**)

	IMPORT HostConsole, Strings;

	PROCEDURE Open*;
	BEGIN
		HostConsole.Open
	END Open;

	PROCEDURE WriteStr* (IN str: ARRAY OF CHAR);
	BEGIN
		HostConsole.WriteStr(str)
	END WriteStr;

	PROCEDURE WriteChar* (ch: CHAR);
		VAR str: ARRAY 2 OF CHAR;
	BEGIN
		str[0] := ch; str[1] := 0X;
		HostConsole.WriteStr(str)
	END WriteChar;

	PROCEDURE WriteInt* (i: LONGINT);
		VAR str: ARRAY 24 OF CHAR;
	BEGIN
		Strings.IntToString(i, str);
		HostConsole.WriteStr(str)
	END WriteInt;

	PROCEDURE WriteLn*;
	BEGIN
		HostConsole.WriteLn
	END WriteLn;

	PROCEDURE ReadLn* (OUT line: ARRAY OF CHAR);
	BEGIN
		HostConsole.ReadLn(line)
	END ReadLn;

END Console.
