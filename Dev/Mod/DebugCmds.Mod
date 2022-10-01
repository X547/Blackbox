MODULE DevDebugCmds;
(**
	Interface for attaching a run-time debugger.
	project	= "BlackBox"
	organization	= "blackboxframework.org"
	contributors	= "BlackBox Framework Center"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""

**)

	IMPORT SYSTEM, WinApi, HostFiles, Kernel, HostRegistry, HostDialog,
		Strings, Dialog, TextControllers, TextMappers, DevReferences;

	CONST
		RegKey_cmdLine = "DevDebugCmds\cmdLine";
	
	PROCEDURE GetCmdLineInfo(VAR startupDir, exeName, usePath: HostFiles.FullName);
		VAR p, exeNamePtr: WinApi.PtrWSTR; i, res, res1: INTEGER; attr: SET;
			opt, s: HostFiles.FullName;
	BEGIN
		p := WinApi.GetCommandLineW(); i := 0; res := 1;
		HostFiles.GetName(p, i, s, opt);
		ASSERT(WinApi.GetFullPathNameW(s, LEN(startupDir), startupDir, exeNamePtr) # 0);
		exeName := exeNamePtr$;
		startupDir[LEN(startupDir$) - LEN(exeName$) - 1] := 0X;
		REPEAT (* copied from HostFiles.Init *)
			HostFiles.GetName(p, i, usePath, opt);
			IF opt = "/USE" THEN
				HostFiles.GetName(p, i, usePath, opt);
				res1 := WinApi.ExpandEnvironmentStringsW(usePath, s, LEN(s) - 2);
				IF (res1 = 0) OR (res1 > LEN(s) - 2) THEN s := usePath ELSE usePath := s$ END;
				res1 := WinApi.GetFullPathNameW(s, LEN(usePath), usePath, NIL);
				attr := BITS(WinApi.GetFileAttributesW(usePath));
				IF (attr # {0..MAX(SET)}) & (WinApi.FILE_ATTRIBUTE_DIRECTORY * attr # {}) THEN res := 0
				ELSIF (usePath[1] = ":") & ((usePath[2] = 0X) OR (usePath[2] = "\") & (usePath[3] = 0X))
					& (WinApi.GetDriveTypeW(s) >= 2) THEN res := 0
				END
			END
		UNTIL (res = 0) OR (p[i] < " ");
		IF res = 0 THEN
			i := LEN(usePath$) - 1;
			IF (usePath[i] = "/") OR (usePath[i] = "\") THEN usePath[i] := 0X END
		ELSE usePath := ""
		END;
	END GetCmdLineInfo;
	
	PROCEDURE RegisterDebugger*(IN cmdLine: ARRAY OF CHAR);
	BEGIN
		HostRegistry.WriteString(RegKey_cmdLine, cmdLine)
	END RegisterDebugger;
	
	PROCEDURE AttachDebugger*;
		CONST sleep = 50; timeout = 10000; (*msecs*)
		VAR res, dt: INTEGER;
			process: WinApi.PROCESS_INFORMATION; info: WinApi.STARTUPINFOW;
			pid, tid, base: ARRAY 32 OF CHAR; cmdLine, rootDir, exeName, usePath: HostFiles.FullName;
			msgPrefix: Dialog.String;
	BEGIN
		IF WinApi.IsDebuggerPresent() = 0 THEN (* no debugger attached *)
			WinApi.GetStartupInfoW(info);
			GetCmdLineInfo(rootDir, exeName, usePath);
			Strings.IntToString(WinApi.GetCurrentProcessId(), pid);
			Strings.IntToString(WinApi.GetCurrentThreadId(), tid);
			Strings.IntToString(SYSTEM.ADR(Kernel.modList), base);
			HostRegistry.ReadString(RegKey_cmdLine, cmdLine, res);
			IF (res # 0) OR (cmdLine = "") THEN cmdLine := '"' + rootDir + "\" + exeName + '"' END;
			cmdLine := cmdLine + " /LOAD DevRTDebug";
			ASSERT(WinApi.SetEnvironmentVariableW("BLACKBOX_DBG_PID", pid) # 0);
			ASSERT(WinApi.SetEnvironmentVariableW("BLACKBOX_DBG_TID", tid) # 0);
			ASSERT(WinApi.SetEnvironmentVariableW("BLACKBOX_DBG_BASE", base) # 0);
			ASSERT(WinApi.SetEnvironmentVariableW("BLACKBOX_DBG_ROOT", rootDir) # 0);
			ASSERT(WinApi.SetEnvironmentVariableW("BLACKBOX_DBG_USE", usePath) # 0);
			res := WinApi.CreateProcessW(NIL, cmdLine, NIL, NIL, 0, {}, 0, NIL, info, process);
			IF res = 0 THEN
				Dialog.MapString("#Dev:AttachDebuggerFailed", msgPrefix);
				HostDialog.ShowErrorDialog(WinApi.GetLastError(), cmdLine, "%2", "%3", msgPrefix + 0DX + 0DX);
				HALT(128)
			END;
			dt := 0;
			WHILE (dt < timeout) & (WinApi.IsDebuggerPresent() = 0) DO (* wait for debugger to start *)
				WinApi.Sleep(sleep); INC(dt, sleep)
			END;
			ASSERT(WinApi.SetEnvironmentVariableW("BLACKBOX_DBG_PID", NIL) # 0) (* cleanup *)
		END;
		IF WinApi.IsDebuggerPresent() = 0 THEN
			Dialog.ShowMsg("#Dev:AttachDebuggerFailed");
			HALT(128)
		END
	END AttachDebugger;

	PROCEDURE DbgCmd* (IN modName, procName: ARRAY OF CHAR);
		VAR dbgStr: ARRAY 256 OF SHORTCHAR;
			numStr: ARRAY 20 OF CHAR; cmd: Kernel.Command;
	BEGIN
		IF Kernel.ThisMod(modName) # NIL THEN
			cmd := Kernel.ThisCommand(Kernel.ThisMod(modName), procName);
			IF cmd # NIL THEN
				AttachDebugger;
				Strings.IntToString(SYSTEM.VAL(INTEGER, cmd), numStr);
				dbgStr := "BlackBox debug [continueTo=" + SHORT(numStr$) + "]";
				WinApi.OutputDebugStringA(dbgStr);
				cmd
			ELSE
				Dialog.ShowParamMsg("#System:CommandNotFoundIn", procName, modName, "")
			END
		ELSE
			Dialog.ShowParamMsg("#Dev:ModuleNotFound", modName, "", "")
		END
	END DbgCmd;

	PROCEDURE DebugCommand*;
		VAR beg, end: INTEGER; c: TextControllers.Controller;
			s: TextMappers.Scanner; modName: TextMappers.String;
	BEGIN
		c := TextControllers.Focus();
		IF (c # NIL) & c.HasSelection() THEN
			c.GetSelection(beg, end);
			s.ConnectTo(c.text); s.SetPos(beg); s.Scan;
			IF s.type = TextMappers.string THEN modName := s.string$; s.Scan;
				IF (s.type = TextMappers.char) & (s.char = ".") THEN s.Scan;
					IF s.type = TextMappers.string THEN
						DevReferences.ResolveImportAlias(modName, c.text);
						DbgCmd(modName, s.string);
						RETURN
					END
				END
			END;
			Dialog.ShowMsg("#Dev:InvalidCmdSyntax")
		ELSE Dialog.ShowMsg("#Dev:NoSelectionFound")
		END
	END DebugCommand;
	
	PROCEDURE DbgMod* (IN modName: ARRAY OF CHAR);
		VAR res: INTEGER; dbgStr: ARRAY 256 OF SHORTCHAR;
	BEGIN
		IF Kernel.ThisMod(modName) # NIL THEN
			AttachDebugger;
			Strings.StringToUtf8( "BlackBox debug [module=" + modName + "]", dbgStr, res);
			ASSERT(res = 0);
			WinApi.OutputDebugStringA(dbgStr)
		ELSE
			Dialog.ShowParamMsg("#Dev:ModuleNotFound", modName, "", "")
		END
	END DbgMod;

	PROCEDURE DebugModule*;
		VAR beg, end: INTEGER; c: TextControllers.Controller; s: TextMappers.Scanner;
	BEGIN
		c := TextControllers.Focus();
		IF (c # NIL) & c.HasSelection() THEN
			c.GetSelection(beg, end);
			s.ConnectTo(c.text); s.SetPos(beg); s.Scan;
			IF s.type = TextMappers.string THEN
				DevReferences.ResolveImportAlias(s.string, c.text);
				DbgMod(s.string)
			ELSE
				Dialog.ShowMsg("#Dev:NoModuleNameSelected")
			END
		ELSE Dialog.ShowMsg("#Dev:NoSelectionFound")
		END
	END DebugModule;

END DevDebugCmds.
