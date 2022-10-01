MODULE DevRTDebug;
(**
	project	= "BlackBox"
	organization	= "www.oberon.ch"
	contributors	= "Oberon microsystems,bh, x512,denisov,jtempl"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""
	
	For a description of the Windows debug API see for example this codeproject article
	or this  microsoft press article.
**)

	IMPORT
		SYSTEM, WinApi, Kernel, HostFiles, HostWindows, HostRegistry, HostDialog,
		Windows, StdFolds, StdLinks, Strings, Dates, Files, Services, Fonts, Ports, Stores, Converters,
		Models, Views, Controllers, Properties, Dialog, Containers, Controls, DevReferences,
		TextModels, TextMappers, TextControllers, TextViews, TextRulers, StdApi, TextCmds;
	
	CONST
		refViewSize = 9 * Ports.point;
		
		heap = 1; source = 2; module = 3; modules = 4;	(* RefView types *)
		open = 1; undo = 2; update = 3;	(* RefView commands *)
		
		(* additional scanner types *)
		import = 100; smodule = 101; semicolon = 102; becomes  = 103; stop = 104; comEnd = 105; 
		
		running = 1000;
		maxStackFrames = 200; (* the maximum number of stack frames shown *)

		DBG_CMD = "DevDebugCmds.DbgCmd";
		
		WinPos_Left = 0;
		WinPos_Top = 1;
		WinPos_Right = 2;
		WinPos_Bottom = 3;
		
		(* stepOut.state enumeration; stepOut.pc set for StepOut_retFrom* *)
		StepOut_start = 0;
		StepOut_syscode = 1;	
		StepOut_retFromSys = 2;
		StepOut_BBcode = 3;
		StepOut_retFromBB = 4;
		
		
	TYPE
		Name = Kernel.Name;
		
		Type = INTEGER;
		Module = INTEGER;
		Object= INTEGER;
		ArrayPtr = INTEGER;
		Cluster = INTEGER;
		
		RefView = POINTER TO RECORD (Views.View)
			type: SHORTINT;
			command: SHORTINT;
			back: RefView;
			adr: INTEGER;
			desc: Type;
			ptr: ArrayPtr;
			name: Name
		END;
		
		(* the core debugger action *)
		DebugAction = POINTER TO RECORD (Services.Action) END;
		
		(* ensures that the debug tool dialog is always open *)
		OpenToolAction = POINTER TO RECORD (Services.Action) END; 
		
		BrkPt = RECORD
			path*: Name;
			adr*, size*: INTEGER
		END;
		
		FoldContext = RECORD
			prevText: TextModels.Model;
		END;
		
		WinPos = ARRAY 4 OF INTEGER;


	VAR
		(* interactors *)
		singleSource*: BOOLEAN; (* use a single source window only *)
		expandAll*: BOOLEAN; (* expand all frames in the state view or only the top-most *)
		breakpoints: ARRAY 3 OF BrkPt;
		
		out: TextMappers.Formatter;
		path: ARRAY 4 OF Ports.Point;
		empty: Name;
		
		stateText: TextModels.Model;
		
		err, pc, sp, fp, stack, val: INTEGER;
		procId, threadId, dbgBase: INTEGER;
		procHandle, threadHandle: WinApi.HANDLE; (* handles for procId and threadId *)
		toolDlg: Views.View;
		toolWindow: HostWindows.Window;
		
		skipCalls: BOOLEAN;	(* step over is running *)
		skipMode: INTEGER;	(* # -1: delayed ContinueExec(200, skipMode) *)
		stopping: BOOLEAN; (* for hard stopping even special cases such as ObxTrap.Hang *)
		
		framePc, frameFp, frameCnt: INTEGER;
		
		cache: ARRAY 256 OF SHORTCHAR;
		cacheLine: INTEGER;
		modCache: Module;
		
		(* for singleSource *)
		remoteSourceView: TextViews.View;
		remoteSourceModule: Name;
		
		showSrc: BOOLEAN; (* parameter of ShowStackFrame *)

		rootDir, usePath: HostFiles.FullName; (* dirs for source file lookup *)
		
		(* configurable window positions *)
		winpos: RECORD
			debug, state, source: WinPos;
		END;

		(* state machine for finding the StepOut pc *)
		stepOut: RECORD
			state, pc: INTEGER;
		END;

	(* remote memory access *)
	
	PROCEDURE  IsReadable (from, to: INTEGER): BOOLEAN;
		VAR data: ARRAY 100 OF SHORTCHAR; res: INTEGER;
	BEGIN
		res := WinApi.ReadProcessMemory(procHandle, from, SYSTEM.ADR(data), to - from, NIL);
		RETURN res # 0
	END IsReadable;
	
	PROCEDURE GetByte (adr: INTEGER; VAR x: SHORTCHAR);
		VAR res: INTEGER;
	BEGIN
		IF adr DIV LEN(cache) = cacheLine THEN
			x := cache[adr MOD LEN(cache)]
		ELSE
			res := WinApi.ReadProcessMemory(procHandle, adr - adr MOD LEN(cache),
															SYSTEM.ADR(cache), LEN(cache), NIL);
			IF res # 0 THEN
				x := cache[adr MOD LEN(cache)];
				cacheLine := adr DIV LEN(cache)
			ELSE
				cacheLine := 0;
				res := WinApi.ReadProcessMemory(procHandle, adr, SYSTEM.ADR(x), 1, NIL);
				IF res = 0 THEN x := 0X END
			END
		END
	END GetByte;
	
	PROCEDURE GetShort (adr: INTEGER; VAR x: SHORTINT);
		VAR res: INTEGER;
	BEGIN
		IF ODD(adr) THEN
			res := WinApi.ReadProcessMemory(procHandle, adr, SYSTEM.ADR(x), 2, NIL);
			IF res = 0 THEN x := 0 END
		ELSIF adr DIV LEN(cache) = cacheLine THEN
			SYSTEM.GET(SYSTEM.ADR(cache) + adr MOD LEN(cache), x)
		ELSE
			res := WinApi.ReadProcessMemory(procHandle, adr - adr MOD LEN(cache),
															SYSTEM.ADR(cache), LEN(cache), NIL);
			IF res # 0 THEN
				SYSTEM.GET(SYSTEM.ADR(cache) + adr MOD LEN(cache), x);
				cacheLine := adr DIV LEN(cache)
			ELSE
				cacheLine := 0;
				res := WinApi.ReadProcessMemory(procHandle, adr, SYSTEM.ADR(x), 2, NIL);
				IF res = 0 THEN x := 0 END
			END
		END
	END GetShort;

	PROCEDURE GetInt (adr: INTEGER; VAR x: INTEGER);
		VAR res: INTEGER;
	BEGIN
		IF adr MOD 4 # 0 THEN
			res := WinApi.ReadProcessMemory(procHandle, adr, SYSTEM.ADR(x), 4, NIL);
			IF res = 0 THEN x := 0 END
		ELSIF adr DIV LEN(cache) = cacheLine THEN
			SYSTEM.GET(SYSTEM.ADR(cache) + adr MOD LEN(cache), x)
		ELSE
			res := WinApi.ReadProcessMemory(procHandle, adr - adr MOD LEN(cache),
															SYSTEM.ADR(cache), LEN(cache), NIL);
			IF res # 0 THEN
				SYSTEM.GET(SYSTEM.ADR(cache) + adr MOD LEN(cache), x);
				cacheLine := adr DIV LEN(cache)
			ELSE
				cacheLine := 0;
				res := WinApi.ReadProcessMemory(procHandle, adr, SYSTEM.ADR(x), 4, NIL);
				IF res = 0 THEN x := 0 END
			END
		END
	END GetInt;
	
	PROCEDURE GetReal (adr: INTEGER; VAR x: REAL);
		VAR res: INTEGER;
	BEGIN
		res := WinApi.ReadProcessMemory(procHandle, adr, SYSTEM.ADR(x), 8, NIL);
		IF res = 0 THEN x := 0 END
	END GetReal;
	
	PROCEDURE GetName (adr: INTEGER; VAR name: Name);
		VAR res: INTEGER; uname: Kernel.Utf8Name;
	BEGIN
		name := "";
		res := WinApi.ReadProcessMemory(procHandle, adr, SYSTEM.ADR(uname), LEN(uname), NIL);
		IF res # 0 THEN Kernel.Utf8ToString(uname, name, res); IF res # 0 THEN name := "" END END;
	END GetName;


(* Kernel data *)

	PROCEDURE ModList (): Module; (* Kernel.modList *)
		VAR m: Module;
	BEGIN
		ASSERT(dbgBase # 0);
		GetInt(dbgBase, m); 
		RETURN m
	END ModList;
	
	PROCEDURE Root (): Cluster; (* Kernel.root *)
		VAR c: Cluster;
	BEGIN
		ASSERT(dbgBase # 0);
		GetInt(dbgBase + 4, c); RETURN c
	END Root;
	
	PROCEDURE Stack (): INTEGER; (* Kernel.baseStack *)
		VAR stk: INTEGER;
	BEGIN
		ASSERT(dbgBase # 0);
		GetInt(dbgBase + 8, stk); RETURN stk
	END Stack;
	
(* Kernel.Module fields *)

	PROCEDURE ModNext (m: Module): Module; 
		VAR next: Module;
	BEGIN
		GetInt(m + 0, next); RETURN next
	END ModNext;
	
	PROCEDURE ModCnt (m: Module): INTEGER; 
		VAR refcnt: INTEGER;
	BEGIN
		GetInt(m + 8, refcnt); RETURN refcnt
	END ModCnt;
	
	PROCEDURE ModCode (m: Module): INTEGER; 
		VAR code: INTEGER;
	BEGIN
		GetInt(m + 64, code); RETURN code
	END ModCode;
	
	PROCEDURE ModCSize (m: Module): INTEGER; 
		VAR csize: INTEGER;
	BEGIN
		GetInt(m + 52, csize); RETURN csize
	END ModCSize;
	
	(* Kernel.Type fields *)
	PROCEDURE TypeSize (t: Type): INTEGER;
		VAR size: INTEGER;
	BEGIN
		GetInt(t + 0, size); RETURN size
	END TypeSize;
	
	PROCEDURE TypeMod (t: Type): Module;
		VAR mod: Module;
	BEGIN
		GetInt(t + 4, mod); RETURN mod
	END TypeMod;
	
	PROCEDURE TypeId (t: Type): INTEGER;
		VAR id: INTEGER;
	BEGIN
		GetInt(t + 8, id); RETURN id
	END TypeId;
	
	PROCEDURE TypeBase (t: Type; i: INTEGER): Type;
		VAR base: Type;
	BEGIN
		GetInt(t + 12 + i * 4, base); RETURN base
	END TypeBase;
	
(* Kernel.proc *)			
	PROCEDURE ThisMod (IN name: ARRAY OF CHAR): Module;	(* loaded modules only *)
		VAR m: Module; n: Name;
	BEGIN
		m := ModList(); GetName(m + 100, n);
		WHILE (m # 0) & ((n # name) OR (ModCnt(m) < 0)) DO 
			m := ModNext(m); GetName(m + 100, n) 
		END;
		RETURN m
	END ThisMod;

	PROCEDURE RefCh (VAR ref: INTEGER; VAR ch: SHORTCHAR);
	BEGIN
		GetByte(ref, ch); INC(ref)
	END RefCh;
	
	PROCEDURE RefNum (VAR ref: INTEGER; VAR x: INTEGER);
		VAR s, n: INTEGER; ch: SHORTCHAR;
	BEGIN
		s := 0; n := 0; RefCh(ref, ch);
		WHILE ORD(ch) >= 128 DO INC(n, ASH(ORD(ch) - 128, s) ); INC(s, 7); RefCh(ref, ch) END;
		x := n + ASH(ORD(ch) MOD 64 - ORD(ch) DIV 64 * 64, s)
	END RefNum;
	
	PROCEDURE RefName (VAR ref: INTEGER; VAR n: Name);
		VAR i: INTEGER; ch: SHORTCHAR; uname: Kernel.Utf8Name;
	BEGIN
		i := 0; RefCh(ref, ch);
		WHILE ch # 0X DO uname[i] := ch; INC(i); RefCh(ref, ch) END;
		uname[i] := 0X;
		Strings.Utf8ToString(uname, n, i)
	END RefName;
	

	PROCEDURE GetObjName (mod: Module; obj: Object; VAR name: Name);
		VAR names, id: INTEGER;
	BEGIN
		GetInt(mod + 84, names);	(* mod.names *)
		GetInt(obj + 8, id);	
		GetName(names + id DIV 256, name)
	END GetObjName;

	PROCEDURE GetTypeName (t: Type; VAR name: Name);
		VAR names: INTEGER;
	BEGIN
		GetInt(TypeMod(t) + 84, names);	(* t.mod.names *)
		GetName(names + TypeId(t) DIV 256, name)
	END GetTypeName;
	
	PROCEDURE  GetRefProc (VAR ref, adr: INTEGER; VAR name: Name);
		VAR ch: SHORTCHAR;
	BEGIN
		GetByte(ref, ch);
		WHILE ch >= 0FDX DO	(* skip variables *)
			INC(ref); RefCh(ref, ch);
			IF ch = 10X THEN INC(ref, 4) END;
			RefNum(ref, adr); RefName(ref, name); GetByte(ref, ch)
		END;
		WHILE (ch > 0X) & (ch < 0FCX) DO	(* skip source refs *)
			INC(ref); RefNum(ref, adr); GetByte(ref, ch)
		END;
		IF ch = 0FCX THEN INC(ref); RefNum(ref, adr); RefName(ref, name);
		ELSE adr := 0
		END
	END GetRefProc;
	
	PROCEDURE  GetRefVar (VAR ref: INTEGER; VAR mode, form: SHORTCHAR; VAR desc: Type; 
											VAR adr: INTEGER; VAR name: Name);
	BEGIN
		GetByte(ref, mode); desc := 0;
		IF mode >= 0FDX THEN
			mode := SHORT(CHR(ORD(mode) - 0FCH));
			INC(ref); RefCh(ref, form);
			IF form = 10X THEN
				GetInt(ref, desc); INC(ref, 4); form := SHORT(CHR(16 + TypeId(desc) MOD 4))
			END;
			RefNum(ref, adr); RefName(ref, name)
		ELSE
			mode := 0X; form := 0X; adr := 0
		END
	END GetRefVar;
	
	PROCEDURE  SearchProcVar (var: INTEGER; VAR m: Module; VAR adr: INTEGER);
	BEGIN
		adr := var; m := 0;
		IF var # 0 THEN
			m := ModList();
			WHILE (m # 0) & ((adr < ModCode(m)) OR (adr >= ModCode(m) + ModCSize(m))) DO
				m := ModNext(m)
			END;
			IF m # 0 THEN DEC(adr, ModCode(m)) END
		END
	END SearchProcVar;
	
	(* ------------------------------- *)
	
	PROCEDURE ShowLastError;
		VAR lastError: INTEGER;
	BEGIN
		lastError := WinApi.GetLastError();
		HostDialog.ShowErrorDialog(lastError, "%1", "%2", "%3", "");
		HALT(99)
	END ShowLastError;
	
	PROCEDURE Check(res: INTEGER);
		VAR lastError: INTEGER;
	BEGIN
		IF res = 0 THEN ShowLastError END
	END Check;
	
	PROCEDURE Valid (): BOOLEAN;
		VAR res, code: INTEGER;
	BEGIN
		res := WinApi.GetExitCodeProcess(procHandle, code);
		RETURN (res # 0) & (code = WinApi.STILL_ACTIVE)
	END Valid;
	
	PROCEDURE Suspend;
		VAR res: INTEGER;
	BEGIN
		res := WinApi.SuspendThread(threadHandle);
		IF res = -1 THEN ShowLastError END
	END Suspend;
	
	PROCEDURE Resume;
		VAR res: INTEGER;
	BEGIN
		res := WinApi.ResumeThread(threadHandle);
		IF res = -1 THEN ShowLastError END
	END Resume;

	(* ------------------------------- *)
		
	PROCEDURE SetPreferredWinPos(IN winpos: WinPos);
	BEGIN
		HostWindows.dir.l := winpos[WinPos_Left];
		HostWindows.dir.t := winpos[WinPos_Top];
		HostWindows.dir.r := winpos[WinPos_Right];
		HostWindows.dir.b := winpos[WinPos_Bottom]
	END SetPreferredWinPos;

	PROCEDURE NewRuler (): TextRulers.Ruler;
		CONST mm = Ports.mm; 
		VAR r: TextRulers.Ruler;
	BEGIN
		r := TextRulers.dir.New(NIL);
		TextRulers.SetRight(r, 140 * mm);
		TextRulers.AddTab(r, 4 * mm); TextRulers.AddTab(r, 34 * mm); TextRulers.AddTab(r, 80 * mm);
		RETURN r
	END NewRuler;

	PROCEDURE NewModRuler (): TextRulers.Ruler;
		CONST mm = Ports.mm; 
		VAR r: TextRulers.Ruler;
	BEGIN
		r := TextRulers.dir.New(NIL);
		IF Dialog.IsMac() THEN
			TextRulers.SetRight(r, 154 * mm);
			TextRulers.AddTab(r, 48 * mm); TextRulers.MakeRightTab(r);
			TextRulers.AddTab(r, 64 * mm); TextRulers.MakeRightTab(r);
			TextRulers.AddTab(r, 76 * mm); TextRulers.AddTab(r, 115 * mm)
		ELSE
			TextRulers.SetRight(r, 144 * mm);
			TextRulers.AddTab(r, 48 * mm); TextRulers.MakeRightTab(r);
			TextRulers.AddTab(r, 64 * mm); TextRulers.MakeRightTab(r);
			TextRulers.AddTab(r, 76 * mm); TextRulers.AddTab(r, 110 * mm)
		END;
		RETURN r
	END NewModRuler;

	PROCEDURE OpenViewer (t: TextModels.Model; IN title: Views.Title; ruler:TextRulers.Ruler);
		VAR v: TextViews.View; c: Containers.Controller;
	BEGIN
		v := TextViews.dir.New(t);
		v.SetDefaults(ruler, TextViews.dir.defAttr);
		c := v.ThisController();
		IF c # NIL THEN
			c.SetOpts(c.opts - {Containers.noFocus, Containers.noSelection} + {Containers.noCaret})
		END;
		Views.OpenAux(v, title)
	END OpenViewer;
	
	PROCEDURE OpenFold (OUT fc: FoldContext);
	BEGIN
		fc.prevText := out.rider.Base();
		out.ConnectTo(TextModels.CloneOf(stateText))
	END OpenFold;

	PROCEDURE CloseFold (IN fc: FoldContext; collapsed: BOOLEAN; IN hidden: ARRAY OF CHAR);
		VAR fold: StdFolds.Fold; t: TextModels.Model; w: TextMappers.Formatter; hiddenx: ARRAY 32 OF CHAR;
	BEGIN
		Dialog.MapString(hidden, hiddenx);
		(* avoid expensive fold.Flip operation *)
		IF collapsed THEN
			fold := StdFolds.dir.New(StdFolds.collapsed, "", out.rider.Base());
			out.ConnectTo(fc.prevText);
			out.WriteView(fold);
			out.WriteString(hiddenx)
		ELSE
			t := TextModels.CloneOf(stateText);
			w.ConnectTo(t); w.WriteString(hiddenx);
			fold := StdFolds.dir.New(StdFolds.expanded, "", t);
			t := out.rider.Base();
			out.ConnectTo(fc.prevText);
			out.WriteView(fold);
			fc.prevText.Insert(out.Pos(), t, 0, t.Length());
			out.SetPos(out.rider.Base().Length())
		END;
		fold := StdFolds.dir.New(collapsed, "", NIL);
		out.WriteView(fold)
	END CloseFold;

	PROCEDURE WriteHex (n: INTEGER);
	BEGIN
		out.WriteIntForm(n, Strings.hexadecimal, 9, "0", TextMappers.showBase)
	END WriteHex;
	
	PROCEDURE WriteString (adr, len, base: INTEGER; zterm, unicode: BOOLEAN);
		CONST beg = 0; char = 1; code = 2;
		VAR ch: SHORTCHAR; val, mode: SHORTINT; str: ARRAY 16 OF CHAR;
	BEGIN
		mode := beg;
		IF base = 2 THEN GetShort(adr, val) ELSE GetByte(adr, ch); val := ORD(ch) END;
		IF zterm & (val = 0) THEN out.WriteString('""')
		ELSE
			REPEAT
				IF (val >= ORD(" ")) & (val < 7FH) OR (val > 0A0H) & (val < 100H) THEN
					IF mode # char THEN
						IF mode = code THEN out.WriteString(", ") END;
						out.WriteChar(22X); mode := char
					END;
					out.WriteChar(CHR(val))
				ELSE
					IF mode = char THEN out.WriteChar(22X) END;
					IF mode # beg THEN out.WriteString(", ") END;
					mode := code; Strings.IntToStringForm(val, Strings.hexadecimal, 1, "0", FALSE, str);
					IF str[0] > "9" THEN out.WriteChar("0") END;
					out.WriteString(str); out.WriteChar("X")
				END;
				INC(adr, base); DEC(len);
				IF base = 2 THEN GetShort(adr, val) ELSE GetByte(adr, ch); val := ORD(ch) END
			UNTIL (len = 0) OR zterm & (val = 0)
		END;
		IF mode = char THEN out.WriteChar(22X) END
	END WriteString;
	
	PROCEDURE OutString (IN s: ARRAY OF CHAR);
		VAR str: Dialog.String;
	BEGIN
		Dialog.MapString(s, str);
		out.WriteString(str);
	END OutString;

	(* -------------------  variable display ------------------- *)
	
	PROCEDURE FormOf (t: Type): SHORTCHAR;
	BEGIN
		IF t DIV 256 = 0 THEN
			RETURN SHORT(CHR(t))
		ELSE
			RETURN SHORT(CHR(16 + TypeId(t) MOD 4))
		END
	END FormOf;
	
	PROCEDURE LenOf (t: Type; ptr: ArrayPtr): INTEGER;
		VAR size, len: INTEGER;
	BEGIN
		size := TypeSize(t);
		IF size # 0 THEN RETURN size
		ELSIF ptr # 0 THEN
			GetInt(ptr + 12 + (TypeId(t) DIV 16 MOD 16 - 1) * 4, len);	
				(* ptr.len[id DIV 16 MOD 16 - 1] *)
			RETURN len
		ELSE RETURN 0
		END
	END LenOf;
	
	PROCEDURE SizeOf (t: Type; ptr: ArrayPtr): INTEGER;
	BEGIN
		CASE FormOf(t) OF
		| 0BX: RETURN 0
		| 1X, 2X, 4X: RETURN 1
		| 3X, 5X: RETURN 2
		| 8X, 0AX: RETURN 8
		| 11X: RETURN TypeSize(t)
		| 12X: RETURN LenOf(t, ptr) * SizeOf(TypeBase(t, 0), ptr)
		ELSE RETURN 4
		END
	END SizeOf;

	PROCEDURE WriteName (t: Type; ptr: ArrayPtr);
		VAR modName, name: Name; mod: Module; f: SHORTCHAR;
	BEGIN
		f := FormOf(t);
		CASE f OF
		| 0X: OutString("#Dev:Unknown")
		| 1X: out.WriteString("BOOLEAN")
		| 2X: out.WriteString("SHORTCHAR")
		| 3X: out.WriteString("CHAR")
		| 4X: out.WriteString("BYTE")
		| 5X: out.WriteString("SHORTINT")
		| 6X: out.WriteString("INTEGER")
		| 7X: out.WriteString("SHORTREAL")
		| 8X: out.WriteString("REAL")
		| 9X: out.WriteString("SET")
		| 0AX: out.WriteString("LONGINT")
		| 0BX: out.WriteString("ANYREC")
		| 0CX: out.WriteString("ANYPTR")
		| 0DX: out.WriteString("POINTER")
		| 0EX: out.WriteString("PROCEDURE")
		| 0FX: out.WriteString("STRING")
		| 10X..13X:
			mod := TypeMod(t);
			IF (mod # 0) & (TypeId(t) DIV 256 # 0) & (ModCnt(mod) >= 0) THEN
				GetTypeName(t, name);
				IF name = "!" THEN
					IF f = 11X THEN out.WriteString("RECORD")
					ELSIF f = 12X THEN out.WriteString("ARRAY")
					ELSE OutString("#Dev:Unknown")
					END
				ELSE
					GetName(mod + 100, modName);
					out.WriteString(modName); out.WriteChar("."); out.WriteString(name)
				END
			ELSIF f = 11X THEN
				IF mod # 0 THEN GetName(mod + 100, modName); out.WriteString(modName); out.WriteChar(".") END;
				out.WriteString("RECORD");
			ELSIF f = 12X THEN
				out.WriteString("ARRAY "); out.WriteInt(LenOf(t, ptr)); t := TypeBase(t, 0);
				WHILE (FormOf(t) = 12X) & ((TypeId(t) DIV 256 = 0) OR (mod = 0) OR (ModCnt(mod) < 0)) DO
					out.WriteString(", "); out.WriteInt(LenOf(t, ptr)); t := TypeBase(t, 0)
				END;
				out.WriteString(" OF "); WriteName(t, ptr)
			ELSIF f = 13X THEN
				out.WriteString("POINTER")
			ELSE
				out.WriteString("PROCEDURE")
			END
		| 20X: out.WriteString("COM.IUnknown")
		| 21X: out.WriteString("COM.GUID")
		| 22X: out.WriteString("COM.RESULT")
		ELSE OutString("#Dev:UnknownFormat"); out.WriteInt(ORD(f))
		END
	END WriteName;
	
	PROCEDURE WriteGuid (a: INTEGER);
	
		PROCEDURE Hex (a: INTEGER);
			VAR x: SHORTCHAR;
		BEGIN
			GetByte(a, x);
			out.WriteIntForm(ORD(x), TextMappers.hexadecimal, 2, "0", FALSE)
		END Hex;
		
	BEGIN
		out.WriteChar("{");
		Hex(a + 3); Hex(a + 2); Hex(a + 1); Hex(a);
		out.WriteChar("-");
		Hex(a + 5); Hex(a + 4);
		out.WriteChar("-");
		Hex(a + 7); Hex(a + 6);
		out.WriteChar("-");
		Hex(a + 8);
		Hex(a + 9);
		out.WriteChar("-");
		Hex(a + 10);
		Hex(a + 11);
		Hex(a + 12);
		Hex(a + 13);
		Hex(a + 14);
		Hex(a + 15);
		out.WriteChar("}")
	END WriteGuid;
	
	PROCEDURE^ ShowVar (ad, ind: INTEGER; f, c: SHORTCHAR; desc: Type; ptr: ArrayPtr; back: RefView; VAR name, sel: Name);
	
	PROCEDURE^ NewRefView (type, command: SHORTINT; adr: INTEGER; back: RefView;
												desc: Type; ptr: ArrayPtr; name: Name): RefView;

	PROCEDURE^ InsertRefView (type, command: SHORTINT; adr: INTEGER; back: RefView;
												desc: Type; ptr: ArrayPtr; name: Name);

	PROCEDURE ShowRecord (a, ind: INTEGER; desc: Type; back: RefView; VAR sel: Name);
		VAR name: Name; i, j, n, dir, num, offs: INTEGER; base, struct: Type; obj: Object;
			fc: FoldContext;
	BEGIN
		WriteName(desc, 0); out.WriteTab;
		IF ModCnt(TypeMod(desc)) >= 0 THEN
			OpenFold(fc);
			n := TypeId(desc) DIV 16 MOD 16; j := 0;
			WHILE j <= n DO
				base := TypeBase(desc, j);
				IF base # 0 THEN
					GetInt(base + 76, dir);	(* base.fields *)
					GetInt(dir, num);	(* dir.num *)
					i := 0;
					WHILE i < num DO
						obj := dir + 4 + i * 16;	(* ADR(dir.obj[i]) *)
						GetObjName(TypeMod(base), obj, name);
						GetInt(obj + 4, offs);	(* obj.offs *)
						GetInt(obj + 12, struct);	(* obj.struct *)
						ShowVar(a + offs, ind, FormOf(struct), 1X, struct, 0, back, name, sel);
						INC(i)
					END
				END;
				INC(j)
			END;
			out.WriteString("   ");
			CloseFold(fc, (ind > 1) OR (sel # ""), "#Dev:Fields")
		ELSE
			OutString("#Dev:Unloaded")
		END
	END ShowRecord;
	
	PROCEDURE ShowArray (a, ind: INTEGER; desc: Type; ptr: ArrayPtr; back: RefView; VAR sel: Name);
		VAR f: SHORTCHAR; i, n, m, size, len: INTEGER; name: Name; eltyp, t: Type; 
			vi: SHORTINT; vs: SHORTCHAR;  str: Dialog.String; high: BOOLEAN;
			fc: FoldContext;
	BEGIN
		WriteName(desc, ptr); out.WriteTab;
		len := LenOf(desc, ptr); eltyp := TypeBase(desc, 0); f := FormOf(eltyp); size := SizeOf(eltyp, ptr);
		IF (f = 2X) OR (f = 3X) THEN	(* string *)
			n := 0; m := len;
			high := FALSE;
			IF f = 2X THEN
				REPEAT GetByte(a + n, vs); INC(n) UNTIL (n = 32) OR (n = len) OR (vs = 0X);
				REPEAT DEC(m); GetByte(a + m, vs) UNTIL (m = 0) OR (vs # 0X)
			ELSE
				REPEAT 
					GetShort(a + n * 2, vi); INC(n);
					IF vi DIV 256 # 0 THEN high := TRUE END 
				UNTIL (n = len) OR (vi = 0);
				n := MIN(n, 32);
				REPEAT DEC(m); GetShort(a + m * 2, vi) UNTIL (m = 0) OR (vi # 0)
			END;
			WriteString(a, n, size, TRUE, TRUE);
			INC(m, 2);
			IF m > len THEN m := len END;
			IF high OR (m > n) THEN
				out.WriteString("   "); OpenFold(fc);
				out.WriteLn;
					IF high & (n = 32) THEN
						WriteString(a, m, size, TRUE, TRUE);
						out.WriteLn; out.WriteLn
					END;
				WriteString(a, m, size, FALSE, FALSE);
				IF m < len THEN out.WriteString(", ..., 0X") END;
				out.WriteString("   ");
				CloseFold(fc, TRUE, "...")
			END
		ELSE
			t := eltyp;
			WHILE FormOf(t) = 12X DO t := TypeBase(t, 0) END;
			IF FormOf(t) # 0X THEN
				OpenFold(fc);
				i := 0;
				WHILE i < len DO
					Strings.IntToString(i, str);
					name := "[" + SHORT(str$) + "]";
					ShowVar(a, ind, f, 1X, eltyp, ptr, back, name, sel);
					INC(i); INC(a, size)
				END;
				out.WriteString("   ");
				CloseFold(fc, StdFolds.collapsed, "#Dev:Elements")
			END
		END
	END ShowArray;
	
	PROCEDURE ShowProcVar (a: INTEGER);
		VAR vi, n, ref: INTEGER; m: Module; modName, name: Name;
	BEGIN
		GetInt(a, vi);
		SearchProcVar(vi, m, vi);
		IF m = 0 THEN
			IF vi = 0 THEN out.WriteString("NIL")
			ELSE WriteHex(vi)
			END
		ELSE
			IF ModCnt(m) >= 0 THEN
				GetName(m + 100, modName);
				out.WriteString(modName); GetInt(m + 72, ref);	(* m.refs *)
				REPEAT GetRefProc(ref, n, name) UNTIL (n = 0) OR (vi < n);
				IF vi < n THEN out.WriteChar("."); out.WriteString(name) END
			ELSE
				OutString("#Dev:ProcInUnloadedMod");
				GetName(m + 100, modName);
				out.WriteString(modName); out.WriteString(" !!!")
			END
		END
	END ShowProcVar;

	PROCEDURE ShowPointer (a: INTEGER; f: SHORTCHAR; desc: Type; back: RefView; VAR sel: Name);
		VAR adr, x, size: INTEGER; ptr: ArrayPtr; c: Cluster; btyp: Type;
	BEGIN
		GetInt(a, adr);
		IF f = 13X THEN btyp := TypeBase(desc, 0) ELSE btyp := 0 END;
		IF adr = 0 THEN out.WriteString("NIL")
		ELSIF f = 20X THEN
			out.WriteChar("["); WriteHex(adr); out.WriteChar("]");
			out.WriteChar(" "); 
			c := Root(); GetInt(c + 0, size);	(* c.size *)
			WHILE (c # 0) & ((adr < c) OR (adr >= c + size)) DO 
				GetInt(c + 4, c); (* c.next *) 
				GetInt(c + 0, size) 
			END;
			IF c # 0 THEN
				ptr := adr;
				InsertRefView(heap, open, adr, back, btyp, ptr, sel)
			END
		ELSE
			IF (f = 13X) OR (f = 0CX) THEN x := adr - 4 ELSE x := adr END;
			IF IsReadable(x, adr + 16) THEN
				out.WriteChar("["); WriteHex(adr); out.WriteChar("]");
				IF (f = 13X) OR (f = 0CX) THEN
					out.WriteChar(" "); 
					c := Root(); GetInt(c + 0, size);	(* c.size *)
					WHILE (c # 0) & ((adr < c) OR (adr >= c + size)) DO GetInt(c + 4, c); (* c.next *) GetInt(c + 0, size) 
					END;
					IF c # 0 THEN
						ptr := adr;
						IF (f = 13X) & (FormOf(btyp) = 12X) THEN	(* array *)
							adr := ptr + 12 + (TypeId(btyp) DIV 16 MOD 16) * 4;	(* ADR(ptr.len[btyp.id DIV 16 MOD 16]) *)
						END;
						InsertRefView(heap, open, adr, back, btyp, ptr, sel)
					ELSE OutString("#Dev:IllegalPointer");
					END
				END
			ELSE OutString("#Dev:IllegalAddress"); WriteHex(adr)
			END
		END
	END ShowPointer;
	
	PROCEDURE ShowSelector (ref: RefView);
		VAR b: RefView; n: SHORTINT; a, a0: TextModels.Attributes;
	BEGIN
		b := ref.back; n := 1;
		IF b # NIL THEN
			WHILE (b.name = ref.name) & (b.back # NIL) DO INC(n); b := b.back END;
			ShowSelector(b);
			IF n > 1 THEN out.WriteChar("(") END;
			out.WriteChar(".")
		END;
		out.WriteString(ref.name);
		IF ref.type = heap THEN out.WriteChar("^") END;
		IF n > 1 THEN
			out.WriteChar(")");
			a0 := out.rider.attr; a := TextModels.NewOffset(a0, 2 * Ports.point);
			out.rider.SetAttr(a);
			out.WriteInt(n); out.rider.SetAttr(a0)
		END;
	END ShowSelector;
	
	PROCEDURE ShowVar (ad, ind: INTEGER; f, c: SHORTCHAR; desc: Type; ptr: ArrayPtr; back: RefView; VAR name, sel: Name);
		VAR i, j,  a: INTEGER; tsel: Name; a0: TextModels.Attributes;
				vi: INTEGER; vc: SHORTCHAR;  vsi: SHORTINT;  vr: REAL; 
	BEGIN
		out.WriteLn; out.WriteTab; i := 0;
		WHILE i < ind DO out.WriteString("  "); INC(i) END;
		a := ad; i := 0; j := 0;
		IF sel # "" THEN
			WHILE sel[i] # 0X DO tsel[i] := sel[i]; INC(i) END;
			IF (tsel[i-1] # ":") & (name[0] # "[") THEN tsel[i] := "."; INC(i) END
		END;
		WHILE name[j] # 0X DO tsel[i] := name[j]; INC(i); INC(j) END;
		tsel[i] := 0X;
		a0 := out.rider.attr;
		IF c = 3X THEN	(* varpar *)
			GetInt(ad, a);
			out.rider.SetAttr(TextModels.NewStyle(a0, {Fonts.italic}))
		END;
		IF name[0] # "[" THEN out.WriteChar(".") END;
		out.WriteString(name);
		out.rider.SetAttr(a0); out.WriteTab;
		IF (c = 3X) & (a >= 0) & (a < 65536) THEN 
			out.WriteTab; out.WriteString("NIL VARPAR");
		ELSIF f = 11X THEN
			GetTypeName(desc, name);
			IF (c = 3X) & (name[0] # "!") THEN GetInt(ad + 4, desc) END;	(* dynamic type *)
			ShowRecord(a, ind + 1, desc, back, tsel)
		ELSIF (c = 3X) & (f = 0BX) THEN	(* VAR anyrecord *)
			GetInt(ad + 4, desc);
			ShowRecord(a, ind + 1, desc, back, tsel)
		ELSIF f = 12X THEN
			IF (TypeSize(desc) = 0) & (ptr = 0) THEN GetInt(ad, a) END;	(* dyn array val par *)
			IF ptr = 0 THEN ptr := ad - 8 END;
			ShowArray(a, ind + 1, desc, ptr, back, tsel)
		ELSE
			IF desc = 0 THEN desc := ORD(f) END;
			WriteName(desc, 0); out.WriteTab;
			CASE f OF
			| 0X: (* GetInt(a, vi); WriteHex(vi) *)
			| 1X: GetByte(a, vc); 
				IF vc = 0X THEN out.WriteString("FALSE")
				ELSIF vc = 1X THEN out.WriteString("TRUE")
				ELSE OutString("#Dev:Undefined"); out.WriteInt(ORD(vc))
				END
			| 2X: WriteString(a, 1, 1, FALSE, FALSE)
			| 3X: WriteString(a, 1, 2, FALSE, TRUE)
			| 4X: GetByte(a, vc); out.WriteInt(SYSTEM.VAL(BYTE, vc))
			| 5X: GetShort(a, vsi); out.WriteInt(vsi)
			| 6X: GetInt(a, vi); out.WriteInt(vi)
			| 7X: GetInt(a, vi); out.WriteReal(SYSTEM.VAL(SHORTREAL, vi))
			| 8X: GetReal(a, vr); out.WriteReal(vr)
			| 9X: GetInt(a, vi); out.WriteSet(SYSTEM.VAL(SET, vi))
			| 0AX: GetInt(a, vi); GetInt(a + 4, i);
				IF (vi >= 0) & (i = 0) OR (vi < 0) & (i = -1) THEN out.WriteInt(vi)
				ELSE out.WriteIntForm(i, Strings.hexadecimal, 8, "0", TextMappers.hideBase); WriteHex(vi)
				END
			| 0CX, 0DX, 13X, 20X: ShowPointer(a, f, desc, back, tsel)
			| 0EX, 10X: ShowProcVar(a)
			| 0FX: WriteString(a, 256, 1, TRUE, FALSE)
			| 21X: WriteGuid(a)
			| 22X: GetInt(a, vi); WriteHex(vi)
			ELSE 
			END
		END
	END ShowVar;
	
	PROCEDURE WriteTimeStamp (adr: INTEGER);
		VAR d: Dates.Date; t: Dates.Time; x: SHORTINT; str: ARRAY 64 OF CHAR;
	BEGIN
		GetShort(adr, x); d.year := x;
		IF d.year = 0 THEN
			out.WriteString("      "); OutString("#Dev:Linked")
		ELSE
			GetShort(adr + 2, x); d.month := x;
			GetShort(adr + 4, x); d.day := x;
			GetShort(adr + 6, x); t.hour := x;
			GetShort(adr + 8, x); t.minute := x;
			GetShort(adr + 10, x); t.second := x;
			Dates.DateToString(d, Dates.short, str);
			out.WriteString(str); out.WriteString("  ");
			Dates.TimeToString(t, str);
			out.WriteString(str); 
		END
	END WriteTimeStamp;

	PROCEDURE ShowModules;
		VAR m, m1: Module; a0: TextModels.Attributes; n, h, t, h1, name: Name; x, y: INTEGER;
	BEGIN
		cacheLine := 0;
		a0 := out.rider.attr;
		out.rider.SetAttr(TextModels.NewStyle(a0, {Fonts.italic}));
		OutString("#Dev:ModuleName"); out.WriteTab;
		OutString("#Dev:BytesUsed"); out.WriteTab;
		OutString("#Dev:Clients"); out.WriteTab;
		OutString("#Dev:Compiled"); out.WriteTab;
		OutString("#Dev:Loaded");
		out.rider.SetAttr(a0); out.WriteTab; out.WriteTab;
		out.rider.SetAttr(TextModels.NewStyle(out.rider.attr, {Fonts.underline}));
		out.rider.SetAttr(TextModels.NewColor(out.rider.attr, Ports.blue));
		
		out.WriteView(StdLinks.dir.NewLink("DevRTDebug.UpdateModules"));
		OutString("#Dev:Update");
		out.WriteView(StdLinks.dir.NewLink(""));
		out.rider.SetAttr(a0); out.WriteLn;
		m := ModList();
		WHILE m # 0 DO
			IF ModCnt(m) >= 0 THEN
				GetName(m + 100, name);	(* m.name *)
				n := name$; Kernel.SplitName(n, h, t);
				m1 := ModList(); h1 := "*";
				WHILE (m1 # m) & (h1 # h) DO
					IF ModCnt(m1) >= 0 THEN GetName(m1 + 100, name);
						n := name$; Kernel.SplitName(n, h1, t) END;
					m1 := ModNext(m1)
				END;
				IF h1 # h THEN
					out.WriteLn;
					m1 := m;
					WHILE m1 # 0 DO
						GetName(m1 + 100, name);	(* m1.name *)
						n := name$; Kernel.SplitName(n, h1, t);
						IF (h1 = h) & (ModCnt(m1) >= 0) THEN
							out.WriteString(name); out.WriteTab;
							GetInt(m1 + 52, x);	(* m1.csize *)
							GetInt(m1 + 56, y); x := x + y;	(* m1.dsize *)
							GetInt(m1 + 60, y); x := x + y;	(* m1.rsize *)
							out.WriteIntForm(x, 10, 6, TextModels.digitspace, TextMappers.hideBase);
							out.WriteTab;
							out.WriteIntForm(ModCnt(m1), 10, 3, TextModels.digitspace, TextMappers.hideBase);
							out.WriteTab;
							WriteTimeStamp(m1 + 12);	(* m1.compTime *)
							out.WriteTab;
							WriteTimeStamp(m1 + 24);	(* m1.loadTime *)
							out.WriteLn
						END;
						m1 := ModNext(m1)
					END
				END
			END;
			m := ModNext(m)
		END
	END ShowModules;
	
	PROCEDURE ShowGlobals (mod: Module);
		VAR ref, x, data: INTEGER; m, f: SHORTCHAR; name: ARRAY 256 OF CHAR; modName, vname: Name;
			d: Type; v: RefView; a0: TextModels.Attributes;
	BEGIN
		IF mod # 0 THEN
			cacheLine := 0;
			GetName(mod + 100, modName);	(* mod.name *)
			out.WriteString(modName);
			out.WriteTab; out.WriteTab; out.WriteTab;
			a0 := out.rider.attr;
			out.rider.SetAttr(TextModels.NewStyle(out.rider.attr, {Fonts.underline}));
			out.rider.SetAttr(TextModels.NewColor(out.rider.attr, Ports.blue));
			name := "DevRTDebug.UpdateGlobals('" + modName + "')";
			out.WriteView(StdLinks.dir.NewLink(name));
			OutString("#Dev:Update");
			out.WriteView(StdLinks.dir.NewLink(""));
			out.rider.SetAttr(a0); out.WriteLn;
			GetInt(mod + 72, ref); GetRefProc(ref, x, vname);	(* get body *)
			IF x # 0 THEN
				v := NewRefView (module, open, 0, NIL, 0, 0, modName);
				GetRefVar(ref, m, f, d, x, vname);
				WHILE m = 1X DO
					GetInt(mod + 68, data);	(* mod.data *)
					ShowVar(data + x, 0, f, m, d, 0, v, vname, empty);
					GetRefVar(ref, m, f, d, x, vname)
				END
			END;
			out.WriteLn
		END
	END ShowGlobals;
	
	PROCEDURE ShowObject (adr: INTEGER);
		VAR eltyp: Type; ptr: ArrayPtr; desc: ARRAY 64 OF INTEGER; i, n, lev, elsize, fields, first: INTEGER; name: Name;
	BEGIN
		GetInt(adr - 4, eltyp);
		IF ODD(eltyp DIV 2) THEN
		(*8<*)
			DEC(eltyp, 2); ptr := adr;
			elsize := TypeSize(eltyp);
			GetName(TypeMod(eltyp) + 100, name);
			IF name = "Kernel" THEN
				GetInt(eltyp + 76, fields);	(* eltyp.fields *)
				GetInt(fields, n);	(* fields.num *)
				IF n = 1 THEN
					GetInt(fields + 4 + 12, eltyp)	(* fields.obj[0].struct *)
				END
			END;
			GetInt(ptr + 8, first);	(* ptr.first *)
			GetInt(ptr + 0, n);	(* ptr.last *)
			n := (n - first) DIV elsize + 1;
			lev := (first - adr - 12) DIV 4; i := 0;
			WHILE lev > 0 DO	(* dynamic levels *)
				DEC(lev);
				GetInt(ptr + 12 + lev * 4, desc[i]);	(* ptr.len[lev] *)	(* size *)
				n := n DIV desc[i]; INC(i);
				desc[i] := 0; INC(i);	(* module *)
				desc[i] := 2; INC(i);	(* id *)
				desc[i] := SYSTEM.ADR(desc[i+1]); INC(i)	(* desc *)
			END;
			IF n > 1 THEN	(* static level *)
				desc[i] := n; INC(i);	(* size *)
				desc[i] := 0; INC(i);	(* module *)
				desc[i] := 2; INC(i);	(* id *)
			ELSE DEC(i)
			END;
			desc[i] := eltyp;	(* desc *)
			ShowArray(first, 1, SYSTEM.ADR(desc), ptr, NIL, empty);
			out.WriteLn
			(*>8*)
		ELSE ShowRecord(adr, 1, eltyp, NIL, empty)
		END;
	END ShowObject;
	
	PROCEDURE ShowPtrDeref (ref: RefView);
		VAR b: RefView; typ: Type;
	BEGIN
		ShowSelector(ref); b := ref.back;
		IF b # NIL THEN
			out.WriteChar(" ");
			InsertRefView(b.type, undo, b.adr, b.back, b.desc, b.ptr, b.name)
		END;
		out.WriteLn; out.WriteLn;
		out.WriteChar("["); WriteHex(ref.adr); out.WriteChar("]"); out.WriteTab;
		IF ref.desc = 0 THEN
			ShowObject(ref.adr)
		ELSIF FormOf(ref.desc) = 12X THEN
			ShowArray(ref.adr, 1, ref.desc, ref.ptr, ref, empty)
		ELSE
			GetInt(ref.ptr - 4, typ);	(* TypeOf(ref.ptr *)
			ShowRecord(ref.adr, 1, typ, ref, empty)
		END;
		out.WriteLn
	END ShowPtrDeref;

	
	PROCEDURE GetSourcePos (mod: Module; codePos: INTEGER; VAR cadr, spos: INTEGER);
		VAR ref, pos, ad, d: INTEGER; ch: SHORTCHAR; name: Name;
	BEGIN
		GetInt(mod + 72, ref);	(* mod.refs *)
		pos := 0; ad := 0; GetByte(ref, ch);
		WHILE ch # 0X DO
			WHILE (ch > 0X) & (ch < 0FCX) DO
				INC(ad, LONG(ORD(ch))); INC(ref); RefNum(ref, d);
				IF ad > codePos THEN cadr := ad; spos := pos; RETURN END;
				INC(pos, d); GetByte(ref, ch)
			END;
			IF ch = 0FCX THEN
				INC(ref); RefNum(ref, d); RefName(ref, name); GetByte(ref, ch);
				IF (d > codePos) & (pos > 0) THEN cadr := d + 1; spos := pos; RETURN END;
			END;
			WHILE ch >= 0FDX DO	(* skip variables *)
				INC(ref); RefCh(ref, ch);
				IF ch = 10X THEN INC(ref, 4) END;
				RefNum(ref, d); RefName(ref, name); GetByte(ref, ch)
			END
		END;
		cadr := -1; spos := -1
	END GetSourcePos;
	
	PROCEDURE Scan (VAR s: TextMappers.Scanner);
	BEGIN
		s.Scan;
		IF s.type = TextMappers.string THEN
			IF s.string = "IMPORT" THEN s.type := import
			ELSIF s.string = "MODULE" THEN s.type := smodule
			ELSIF s.string = "THEN" THEN s.type := stop
			ELSIF s.string = "OF" THEN s.type := stop
			ELSIF s.string = "DO" THEN s.type := stop
			ELSIF s.string = "END" THEN s.type := stop
			ELSIF s.string = "ELSE" THEN s.type := stop
			ELSIF s.string = "ELSIF" THEN s.type := stop
			ELSIF s.string = "UNTIL" THEN s.type := stop
			ELSIF s.string = "TO" THEN s.type := stop
			ELSIF s.string = "BY" THEN s.type := stop
			END
		ELSIF s.type = TextMappers.char THEN
			IF s.char = ";" THEN s.type := semicolon
			ELSIF s.char = "|" THEN s.type := stop
			ELSIF s.char = ":" THEN
				IF s.rider.char = "=" THEN s.rider.Read; s.type := becomes END
			ELSIF s.char = "(" THEN
				IF s.rider.char = "*" THEN
					s.rider.Read;
					REPEAT Scan(s) UNTIL (s.type = TextMappers.eot) OR (s.type = comEnd);
					Scan(s)
				END
			ELSIF s.char = "*" THEN
				IF s.rider.char = ")" THEN s.rider.Read; s.type := comEnd END
			END
		END	
	END Scan;
	
	PROCEDURE GetSubLoc (IN mod: ARRAY OF CHAR;
											OUT loc: Files.Locator; OUT name: Files.Name);
		VAR sub: Files.Name;
	BEGIN
		Kernel.SplitName(mod, sub, name); Kernel.MakeFileName(name, ""); loc := NIL;
		IF usePath # "" THEN
			IF sub = "" THEN
				loc := Files.dir.This(usePath + "/Mod");
				IF Files.dir.Old(loc, name, Files.shared) # NIL THEN RETURN END;
				loc := Files.dir.This(usePath + "/System/Mod");
				IF Files.dir.Old(loc, name, Files.shared) # NIL THEN RETURN END;
			ELSE
				loc := Files.dir.This(usePath + "/" + sub + "/Mod");
				IF Files.dir.Old(loc, name, Files.shared) # NIL THEN RETURN END;
			END
		END;
		IF (loc = NIL) OR (loc.res # 0) THEN
			IF sub = "" THEN
				loc := Files.dir.This(rootDir + "/Mod");
				IF Files.dir.Old(loc, name, Files.shared) # NIL THEN RETURN END;
				loc := Files.dir.This(rootDir + "/System/Mod");
				IF Files.dir.Old(loc, name, Files.shared) # NIL THEN RETURN END;
			ELSE
				loc := Files.dir.This(rootDir + "/" + sub + "/Mod");
				IF Files.dir.Old(loc, name, Files.shared) # NIL THEN RETURN END;
			END
		END;
	END GetSubLoc;

	PROCEDURE ShowSourceWindow (name: Name; adr: INTEGER; auto: BOOLEAN);
		VAR loc: Files.Locator; fname: Files.Name; v: Views.View; m: Models.Model; conv: Converters.Converter;
			c: Containers.Controller; a, beg, end: INTEGER; 
			s: TextMappers.Scanner; 
			w, fw: Windows.Window;
	BEGIN
		GetSubLoc(name$, loc, fname); 
		m := NIL;
		IF auto THEN
			w := Windows.dir.First(); fw := w;
			WHILE Windows.isTool IN fw.flags DO fw := Windows.dir.Next(fw) END;
			WHILE (w # NIL) & ((w.loc = NIL) OR (w.name = "") OR (w.loc.res = 77) OR
									~Files.dir.SameFile(loc, fname, w.loc, w.name) OR (w.conv # Converters.list)) DO
				w := Windows.dir.Next(w)
			END;
			IF w # NIL THEN
				v := w.doc.ThisView();
				m := v.ThisModel();
				IF ~(m IS TextModels.Model) THEN m := NIL END;
				IF m # NIL THEN
					IF w # fw THEN
						Windows.dir.Select(w, Windows.lazy);
						Windows.dir.Select(toolWindow, Windows.lazy)
					END
				END
			END
		END;
		IF m = NIL THEN
			v := Views.OldView(loc, fname);
			IF v # NIL THEN
				Views.Open(v, loc, fname, NIL);
				Windows.dir.Select(toolWindow, Windows.lazy);
				m := v.ThisModel();
				IF ~(m IS TextModels.Model) THEN m := NIL END
			END
		END;
		IF m = NIL THEN
			(* search in open windows *)
			w := Windows.dir.First();
			WHILE (w # NIL) & (m = NIL) DO
				v := w.doc.ThisView();
				m := v.ThisModel();
				IF m # NIL THEN
					WITH m: TextModels.Model DO
						s.ConnectTo(m); s.SetPos(0);
						REPEAT
							REPEAT s.Scan UNTIL s.rider.eot OR (s.type = TextMappers.string) & (s.string = "MODULE");
							s.Scan;
						UNTIL s.rider.eot OR (s.type = TextMappers.string) & (s.string = name);
						IF s.rider.eot THEN m := NIL END
					ELSE m := NIL
					END
				END;
				w := Windows.dir.Next(w)
			END
		END;
		IF (m = NIL) & ~auto THEN
			(* ask user for source file *)
			conv := NIL; v := Views.Old(Views.ask, loc, fname, conv);
			IF v # NIL THEN
				Views.Open(v, loc, fname, conv);
				m := v.ThisModel();
				IF ~(m IS TextModels.Model) THEN m := NIL END
			END
		END;
		IF m # NIL THEN
			(* mark error position in text *)
			WITH m: TextModels.Model DO
				GetSourcePos(ThisMod(name), adr, a, beg);
				IF beg >= 0 THEN
					IF beg > m.Length() THEN beg := m.Length() - 10 END;
					s.ConnectTo(m); s.SetPos(beg);
					Scan(s); beg := s.start; end := beg + 3;
					IF s.type = stop THEN end := s.Pos() - 1
					ELSE
						WHILE (s.type # TextMappers.eot) & (s.type # stop) & (s.type # semicolon) DO
							end := s.Pos() - 1; Scan(s)
						END
					END;
					c := v(TextViews.View).ThisController();
					v(TextViews.View).ShowRange(beg, end, TextViews.any);
					c(TextControllers.Controller).SetSelection(beg, end);
				END
			END
		ELSIF ~auto THEN
			Dialog.ShowParamMsg("#Dev:SourcefileNotFound", name, "", "")
		END
	END ShowSourceWindow;
	
	PROCEDURE OpenRemoteSource(bringToFront: BOOLEAN);
		VAR w: Windows.Window;
	BEGIN
		w := Windows.dir.First();
		WHILE (w # NIL) & ((w.doc = NIL) OR (w.doc.ThisView() # remoteSourceView)) DO
			w := Windows.dir.Next(w)
		END;
		IF w # NIL THEN
			IF bringToFront THEN Windows.dir.Select(w, Windows.lazy) END
		ELSE
			remoteSourceView := TextViews.dir.New(remoteSourceView.ThisModel()(TextModels.Model));
			SetPreferredWinPos(winpos.source);
			Views.OpenAux(remoteSourceView, "#Dev:RemoteSource")
		END
	END OpenRemoteSource;

	PROCEDURE ShowRemoteSource (IN name: Name; adr: INTEGER);
		VAR loc: Files.Locator; fname: Files.Name; v: Views.View; m: Models.Model;
			sourceText: TextModels.Model; s: TextMappers.Scanner;
			c: Containers.Controller; a, beg, end: INTEGER;
			defRuler, defRulerCopy: TextRulers.Ruler; defAttr, defAttrCopy: TextModels.Attributes;
	BEGIN
		OpenRemoteSource(FALSE);
		sourceText := remoteSourceView.ThisModel();
		GetSubLoc(name, loc, fname); 
		v := Views.OldView(loc, fname); m := NIL;
		IF v # NIL THEN
			m := v.ThisModel();
			IF (m # NIL) & ~(m IS TextModels.Model) THEN m := NIL END
		END;
		IF m # NIL THEN
			(* mark error position in text *)
			WITH m: TextModels.Model DO
				IF name # remoteSourceModule THEN
					Models.BeginModification(Models.notUndoable, sourceText);
					sourceText.Delete(0, sourceText.Length());
					v(TextViews.View).PollDefaults(defRuler, defAttr);
					defRulerCopy := TextRulers.CopyOf(defRuler, FALSE);
					NEW(defAttrCopy); defAttrCopy.InitFromProp(defAttr.Prop());
					remoteSourceView.SetDefaults(defRulerCopy, defAttr);
					sourceText.InsertCopy(0, m, 0, m.Length());
					Models.EndModification(Models.notUndoable, sourceText);
					remoteSourceModule := name
				END
			END;
			GetSourcePos(ThisMod(name), adr, a, beg);
			IF beg >= 0 THEN
				IF beg > sourceText.Length() THEN beg := sourceText.Length() - 10 END;
				s.ConnectTo(sourceText); s.SetPos(beg);
				Scan(s); beg := s.start; end := beg + 3;
				IF s.type = stop THEN end := s.Pos() - 1
				ELSE
					WHILE (s.type # TextMappers.eot) & (s.type # stop) & (s.type # semicolon) DO
						end := s.Pos() - 1; Scan(s)
					END
				END;
				c := remoteSourceView.ThisController();
				remoteSourceView.ShowRange(beg, end, TextViews.any);
				c(TextControllers.Controller).SetSelection(beg, end);
			END;
		ELSE
			sourceText.Delete(0, sourceText.Length()); remoteSourceModule := "";
			Dialog.ShowParamMsg("#Dev:SourcefileNotFound", name, "", "")
		END
	END ShowRemoteSource;
	
	PROCEDURE ShowSourcePos (IN name: Name; adr: INTEGER; auto: BOOLEAN);
	BEGIN
		IF singleSource THEN ShowRemoteSource(name, adr)
		ELSE ShowSourceWindow(name, adr, auto)
		END
	END ShowSourcePos;

	(* -------------------  RefView ------------------- *)
	
	PROCEDURE (v: RefView) Internalize (VAR rd: Stores.Reader);
		VAR  thisVersion: INTEGER;
	BEGIN
		v.Internalize^(rd); IF rd.cancelled THEN RETURN END;
		rd.ReadVersion(1, 1, thisVersion); IF rd.cancelled THEN RETURN END;
		v.command := open;
		rd.ReadSInt(v.type);
		IF v.type = source THEN
			rd.ReadInt(v.adr);
			rd.ReadString(v.name)
		ELSIF v.type = module THEN
			rd.ReadString(v.name)
		ELSIF v.type # modules THEN
			v.type := 0
		END
	END Internalize;

	PROCEDURE (v: RefView) Externalize (VAR wr: Stores.Writer);
		VAR t: SHORTINT;
	BEGIN
		v.Externalize^(wr);
		wr.WriteVersion(1);
		t := v.type;
		IF v.command # open THEN t := 0 END;
		wr.WriteSInt(t);
		IF t = source THEN
			wr.WriteInt(v.adr);
			wr.WriteString(v.name)
		ELSIF t = module THEN
			wr.WriteString(v.name)
		END
	END Externalize;

	PROCEDURE (v: RefView) CopyFromSimpleView (source: Views.View);
	BEGIN
		(* v.CopyFrom^(source); *)
		WITH source: RefView DO
			v.type := source.type; v.command := source.command; v.adr := source.adr; v.back := source.back;
			v.desc := source.desc; v.ptr := source.ptr; v.name := source.name$;
		END
	END CopyFromSimpleView;

	PROCEDURE (v: RefView) Restore (f: Views.Frame; l, t, r, b: INTEGER);
	BEGIN
		f.DrawPath(path, 4, Ports.fill, Ports.green, Ports.closedPoly)
	END Restore;
	
	PROCEDURE (v: RefView) GetBackground (VAR color: Ports.Color);
	BEGIN
		color := Ports.background
	END GetBackground;

	PROCEDURE (v: RefView) HandleCtrlMsg (f: Views.Frame; VAR msg: Controllers.Message; VAR focus: Views.View);
		VAR t, t0: TextModels.Model; m: Models.Model; x, y: INTEGER;
			isDown, new: BOOLEAN; mo: SET; script: Stores.Operation;
	BEGIN
		WITH msg: Controllers.TrackMsg DO
			IF v.type > 0 THEN
				REPEAT
					f.MarkRect(0, 0, refViewSize, refViewSize, Ports.fill, Ports.hilite, Ports.show);
					IF v.command = undo THEN Dialog.ShowStatus("#Dev:ShowPrecedingObject")
					ELSIF v.command = update THEN Dialog.ShowStatus("#Dev:UpdateWindow")
					ELSIF v.type = module THEN Dialog.ShowStatus("#Dev:ShowGlobalVariables")
					ELSIF v.type = source THEN Dialog.ShowStatus("#Dev:ShowSourcePosition")
					ELSIF v.type = heap THEN Dialog.ShowStatus("#Dev:ShowReferencedObject")
					END;
					REPEAT
						f.Input(x, y, mo, isDown)
					UNTIL (x < 0) OR (x > refViewSize) OR (y < 0) OR (y > refViewSize) OR ~isDown;
					f.MarkRect(0, 0, refViewSize, refViewSize, Ports.fill, Ports.hilite, Ports.hide);
					Dialog.ShowStatus("");
					WHILE isDown & ((x < 0) OR (x > refViewSize) OR (y < 0) OR (y > refViewSize)) DO
						f.Input(x, y, mo, isDown)
					END
				UNTIL ~isDown;
				IF (x >= 0) & (x <= refViewSize) & (y >= 0) & (y <= refViewSize) THEN
					IF v.type = source THEN ShowSourcePos(v.name, v.adr, FALSE)
					ELSIF Valid() THEN
						Suspend;
						m := v.context.ThisModel();
						new := (v.command = open) & (v.back = NIL)
							OR (Controllers.modify IN msg.modifiers) & (v.command # update)
							OR ~(m IS TextModels.Model) ;
						IF new THEN
							t := TextModels.dir.New(); t0 := NIL
						ELSE
							t0 := m(TextModels.Model); t := TextModels.CloneOf(t0);
						END;
						out.ConnectTo(t);
						IF v.type = heap THEN  ShowPtrDeref(v)
						ELSIF v.type = module THEN ShowGlobals(ThisMod(v.name))
						ELSIF v.type = modules THEN ShowModules
						END;
						out.ConnectTo(NIL);
						IF new THEN
							OpenViewer(t, "#Dev:RemoteVariables", NewRuler())
						ELSE
							Models.BeginScript(t0, "#Dev:Change", script);
							t0.Delete(0, t0.Length()); t0.Insert(0, t, 0, t.Length());
							Models.EndScript(t0, script)
						END;
						Resume
					END
				END
			END
		| msg: Controllers.PollCursorMsg DO
			msg.cursor := Ports.refCursor
		ELSE
		END
	END HandleCtrlMsg;
	
	PROCEDURE (v: RefView) HandlePropMsg (VAR msg: Properties.Message);
	BEGIN
		WITH msg: Properties.Preference DO
			WITH msg: Properties.ResizePref DO msg.fixed := TRUE
			| msg: Properties.SizePref DO msg.w := refViewSize; msg.h := refViewSize
			| msg: Properties.FocusPref DO msg.hotFocus := TRUE
			ELSE
			END
		ELSE
		END
	END HandlePropMsg;
	
	PROCEDURE NewRefView (type, command: SHORTINT; adr: INTEGER; back: RefView;
												desc: Type; ptr: ArrayPtr; name: Name): RefView;
		VAR v: RefView;
	BEGIN
		NEW(v); v.type := type; v.command := command; v.adr := adr; v.back := back;
		v.desc := desc; v.ptr := ptr; v.name := name$;
		RETURN v
	END NewRefView;

	PROCEDURE InsertRefView (type, command: SHORTINT; adr: INTEGER; back: RefView;
												desc: Type; ptr: ArrayPtr; name: Name);
		VAR v: RefView; a0: TextModels.Attributes;
	BEGIN
		v := NewRefView(type, command, adr, back, desc, ptr, name);
		a0 := out.rider.attr;
		out.rider.SetAttr(TextModels.NewOffset(a0, Ports.point));
		out.WriteView(v);
		out.rider.SetAttr(a0)
	END InsertRefView;
	

	PROCEDURE GetMod (VAR mod: Module);
		VAR c: TextControllers.Controller; s: TextMappers.Scanner; beg, end: INTEGER;
	BEGIN
		mod := 0;
		c := TextControllers.Focus();
		IF (c # NIL) & c.HasSelection() THEN
			c.GetSelection(beg, end);
			s.ConnectTo(c.text); s.SetPos(beg); s.Scan;
			IF s.type = TextMappers.string THEN
				mod := ThisMod(s.string);
				IF mod = 0 THEN
					Dialog.ShowParamMsg("#Dev:ModuleNotFound", s.string, "", "")
				END				
			ELSE Dialog.ShowMsg("#Dev:NoModuleNameSelected")
			END
		ELSE Dialog.ShowMsg("#Dev:NoSelectionFound")
		END
	END GetMod;

	PROCEDURE ShowStackFrame (buf: TextModels.Model);
		VAR ref, end, i, j, x: INTEGER; m, f: SHORTCHAR; mod: Module; name, sel, mname: Name; d: Type;
			fc: FoldContext; firstLocals: BOOLEAN;
	BEGIN
		out.ConnectTo(buf); out.SetPos(buf.Length());
		mod := ModList();
		WHILE (mod # 0) & ((framePc < ModCode(mod)) OR (framePc >= ModCode(mod) + ModCSize(mod))) DO
			mod := ModNext(mod)
		END;
		IF mod # 0 THEN
			CASE stepOut.state OF
			| StepOut_start: stepOut.state := StepOut_BBcode;
			| StepOut_syscode: stepOut.state := StepOut_retFromSys; stepOut.pc := framePc + 1
			| StepOut_BBcode: stepOut.state := StepOut_retFromBB; stepOut.pc := framePc + 1
			ELSE
			END;
			DEC(framePc, ModCode(mod));
			GetName(mod + 100, mname);	(* mod.name *)
			IF ModCnt(mod) >= 0 THEN x := buf.Length();
				InsertRefView(module, open, 0, NIL, 0, 0, mname);
				out.WriteChar(" "); out.WriteString(mname); GetInt(mod + 72, ref);	(* mod.refs *)
				REPEAT GetRefProc(ref, end, name) UNTIL (end = 0) OR (framePc < end);
				IF framePc < end THEN
					IF mname + "." + name = DBG_CMD THEN
						frameCnt := 0; out.ConnectTo(NIL); buf.Delete(x, buf.Length()); RETURN
					END;
					out.WriteChar("."); out.WriteString(name);
					sel := mname$; i := 0;
					WHILE sel[i] # 0X DO INC(i) END;
					sel[i] := "."; INC(i); j := 0;
					WHILE name[j] # 0X DO sel[i] := name[j]; INC(i); INC(j) END;
					sel[i] := ":"; sel[i+1] := 0X;
					(*out.WriteString("   ["); WriteHex(framePc);
					out.WriteString("] "); *)out.WriteString(" ");
					GetSourcePos(mod, 0, j, i);
					firstLocals := FALSE;
					IF i >= 0 THEN
						InsertRefView(source, open, framePc, NIL, 0, 0, mname);
						IF showSrc THEN
							ShowSourcePos(mname, framePc, TRUE);
							showSrc := FALSE; firstLocals := TRUE
						END
					END;
					IF name # "$$" THEN
						IF ~firstLocals & ~expandAll THEN out.WriteChar(" "); OpenFold(fc) END;
						GetRefVar(ref, m, f, d, x, name);
						WHILE m # 0X DO
							IF name[0] # "@" THEN 
								ShowVar(frameFp + x, 0, f, m, d, 0, NIL, name, sel) 
							END;
							GetRefVar(ref, m, f, d, x, name);
						END;
						IF ~firstLocals & ~expandAll THEN
							out.WriteLn; out.WriteTab; CloseFold(fc, TRUE, "#Dev:Locals")
						END;
					END
				ELSE out.WriteString(".???")
				END;
				out.WriteLn
			ELSE
				out.WriteChar("("); out.WriteString(mname);
				out.WriteString(")   (pc="); WriteHex(framePc);
				out.WriteString(",  fp="); WriteHex(frameFp); out.WriteChar(")");
				out.WriteLn
			END
		ELSE
			CASE stepOut.state OF
			| StepOut_start: stepOut.state := StepOut_syscode;
			| StepOut_BBcode: stepOut.state := StepOut_retFromBB; stepOut.pc := framePc + 1
			ELSE
			END;
			out.WriteTab; out.WriteString("<system>   (pc="); WriteHex(framePc);
			out.WriteString(",  fp="); WriteHex(frameFp); out.WriteChar(")");
			out.WriteLn
		END;
		IF (frameFp >= fp) & (frameFp < stack) THEN
			GetInt(frameFp+4, framePc);	(* stacked pc *)
			GetInt(frameFp, frameFp);	(* dynamic link *)
			DEC(framePc); DEC(frameCnt)
		ELSE frameCnt := 0
		END;
		out.ConnectTo(NIL)
	END ShowStackFrame;

	PROCEDURE ThisControl(C: Containers.Controller; link: ARRAY OF CHAR): Views.View;
		VAR V: Views.View; P: Properties.Property;
	BEGIN
		IF C # NIL THEN
			C.GetFirstView(FALSE, V);
			WHILE V # NIL DO
				IF V IS Controls.Control THEN
					P := V(Controls.Control).prop;
					WHILE P # NIL DO
						WITH P: Controls.Prop DO
							IF P.link = link THEN RETURN V END
						ELSE
						END ;
						P := P.next
					END
				END ;
				C.GetNextView(FALSE, V)
			END
		END ;
		RETURN NIL
	END ThisControl;

	PROCEDURE FocusThisControl(link: ARRAY OF CHAR);
		VAR F: Containers.Controller; V: Views.View;
	BEGIN
		Controllers.SetCurrentPath(Controllers.frontPath);
		F := Containers.Focus();
		IF F # NIL THEN V := ThisControl(F, link); F.SetFocus(V) END;
		Controllers.ResetCurrentPath;
	END FocusThisControl;

	PROCEDURE SetRunning;
	BEGIN
		stateText.Delete(0, stateText.Length());
		out.ConnectTo(stateText);
		out.rider.SetAttr(TextModels.NewWeight(out.rider.attr, Fonts.bold));
		OutString("#Dev:running"); out.WriteLn;
		out.ConnectTo(NIL);
		err := running;
		frameCnt := 0
	END SetRunning;
	
	PROCEDURE SetTerminated;
	BEGIN
		stateText.Delete(0, stateText.Length());
		out.ConnectTo(stateText);
		out.rider.SetAttr(TextModels.NewWeight(out.rider.attr, Fonts.bold));
		OutString("#Dev:terminated"); out.WriteLn;
		out.ConnectTo(NIL);
		Dialog.ShowMsg("#Dev:Detached")
	END SetTerminated;
	
	PROCEDURE SetBP (VAR bp: BrkPt; n: INTEGER; VAR context: WinApi.CONTEXT);
		VAR ctrl: SET;
	BEGIN
		ctrl := SYSTEM.VAL(SET, context.Dr7);
		IF bp.adr # 0 THEN
			IF n = 0 THEN context.Dr0 := bp.adr
			ELSIF n = 1 THEN context.Dr1 := bp.adr
			ELSE context.Dr2 := bp.adr
			END;
			INCL(ctrl, 2 * n);
			IF bp.size # 0 THEN INCL(ctrl, 16 + 4 * n); INCL(ctrl, 8) END;
			IF bp.size > 0 THEN INCL(ctrl, 17 + 4 * n) END;
			IF ABS(bp.size) > 1 THEN INCL(ctrl, 18 + 4 * n) END;
			IF ABS(bp.size) > 2 THEN INCL(ctrl, 19 + 4 * n) END;
		ELSE EXCL(ctrl, 2 * n)
		END;
		context.Dr7 := SYSTEM.VAL(INTEGER, ctrl)
	END SetBP;
	
	PROCEDURE ContinueExec (err, adr: INTEGER);	(* adr = -1: step; adr = 0: continue; adr > 0: goto *)
		VAR bp: INTEGER; context: WinApi.CONTEXT; b0, b1: SHORTCHAR;
	BEGIN
		context.ContextFlags := WinApi.CONTEXT_CONTROL + WinApi.CONTEXT_DEBUG_REGISTERS;
		Check(WinApi.GetThreadContext(threadHandle, context));
		IF (err >= 0) & (err <= 127) THEN INC(context.Eip, 3) END;	(* correct trap pc *)
		EXCL(SYSTEM.VAL(SET, context.EFlags), 8);	(* reset trace flag *)
		context.Dr6 := 0;	(* clear debug status register *)
		context.Dr7 := 0;	(* clear debug control register *)
		skipMode := -1;
		IF breakpoints[0].adr = context.Eip THEN skipMode := adr ELSE SetBP(breakpoints[0], 0, context) END;
		IF breakpoints[1].adr = context.Eip THEN skipMode := adr ELSE SetBP(breakpoints[1], 1, context) END;
		IF breakpoints[2].adr = context.Eip THEN skipMode := adr ELSE SetBP(breakpoints[2], 2, context) END;
		
		IF adr > 0 THEN
			context.Dr3 := adr; INCL(SYSTEM.VAL(SET, context.Dr7), 6)	(* set breakpoint 3 *)
		ELSIF adr = -1 THEN
			GetByte(context.Eip, b0); GetByte(context.Eip + 1, b1);
			IF skipCalls & ((b0 = 0E8X) OR (b0 = 0FFX) & (ORD(b1) DIV 8 MOD 8 = 2)) THEN
				(* place breakpoint after call *)
				IF b0 = 0E8X THEN	(* call direct *)
					bp := context.Eip + 5
				ELSIF ORD(b1) DIV 64 = 0 THEN	(* call indirect (no offset) *)
					IF b1 = 14X THEN	(* s-i-b byte present *)
						GetByte(context.Eip + 2, b1);
						IF ORD(b1) MOD 8 = 5 THEN bp := context.Eip + 7	(* absolute *)
						ELSE bp := context.Eip + 3
						END
					ELSIF b1 = 15X THEN bp := context.Eip + 6	(* absolute *)
					ELSE bp := context.Eip + 2
					END
				ELSIF ORD(b1) DIV 64 = 1 THEN	(* call indirect (8 bit offset) *)
					IF b1 = 54X THEN bp := context.Eip + 4	(* s-i-b byte present *)
					ELSE bp := context.Eip + 3
					END
				ELSIF ORD(b1) DIV 64 = 2 THEN	(* call indirect (32 bit offset) *)
					IF b1 = 94X THEN bp := context.Eip + 7	(* s-i-b byte present *)
					ELSE bp := context.Eip + 6
					END
				ELSE	(* call indirect (register) *)
					bp := context.Eip + 2
				END;
				context.Dr3 := bp; INCL(SYSTEM.VAL(SET, context.Dr7), 6)	(* set breakpoint 3 *)
			ELSE
				INCL(SYSTEM.VAL(SET, context.EFlags), 8)	(* set trace flag *)
			END
		END;
		IF skipMode # -1 THEN INCL(SYSTEM.VAL(SET, context.EFlags), 8) END;	(* set trace flag *)
		Check(WinApi.SetThreadContext(threadHandle, context));
		Check(WinApi.ContinueDebugEvent(procId, threadId, WinApi.DBG_CONTINUE))
	END ContinueExec;
	
	PROCEDURE IsStopped(): BOOLEAN;
	BEGIN
		RETURN Valid() & ((err = 200) OR (err = 207))
	END IsStopped;


	(* ---------- breakpoints ---------- *)
		PROCEDURE GetCodePos (mod: Module; srcPos: INTEGER; VAR codePos: INTEGER);
		VAR ref, pos, ad, d, min: INTEGER; ch: SHORTCHAR; name: Name;
	BEGIN
		GetInt(mod + 72, ref);	(* mod.refs *)
		pos := 0; ad := 0; min := MAX(INTEGER); codePos := 0; GetByte(ref, ch);
		WHILE ch # 0X DO
			WHILE (ch > 0X) & (ch < 0FCX) DO
				INC(ad, LONG(ORD(ch))); INC(ref); RefNum(ref, d); INC(pos, d);
				IF (pos >= srcPos) & (pos < min) THEN
					min := pos; codePos := ad
				END;
				GetByte(ref, ch) 
			END;
			IF ch = 0FCX THEN INC(ref); RefNum(ref, d); RefName(ref, name); GetByte(ref, ch) END;
			WHILE ch >= 0FDX DO	(* skip variables *)
				INC(ref); RefCh(ref, ch);
				IF ch = 10X THEN INC(ref, 4) END;
				RefNum(ref, d); RefName(ref, name); GetByte(ref, ch)
			END
		END
	END GetCodePos;

	PROCEDURE GetBreakPos (VAR adr, size: INTEGER; VAR path: ARRAY OF CHAR);
		VAR c: TextControllers.Controller; s: TextMappers.Scanner; beg, end, ref, x, data: INTEGER;
			m, f: SHORTCHAR; name: Name; d: Type; mod: Module;
	BEGIN
		adr := 0; size := 0; path := "";
		c := TextControllers.Focus();
		IF c # NIL THEN
			IF c.HasSelection() THEN
				c.GetSelection(beg, end);
				s.ConnectTo(c.text);
				s.SetOpts(s.opts - {TextMappers.returnQualIdents});
				s.SetPos(beg); s.Scan;
				IF s.type = TextMappers.string THEN
					mod := ThisMod(s.string);
					IF mod # 0 THEN
						path := s.string$;
						s.Scan;
						IF (s.type = TextMappers.char) & (s.char = ".") THEN
							path := path + ".";
							s.Scan;
							IF s.type = TextMappers.string THEN
								GetInt(mod + 72, ref); GetRefProc(ref, x, name);	(* get body *)
								IF x # 0 THEN
									REPEAT
										GetRefVar(ref, m, f, d, x, name)
									UNTIL (m # 1X) OR (name = s.string);
									IF m = 1X THEN
										IF (f = 1X) OR (f = 2X) OR (f = 4X) THEN size := 1
										ELSIF (f = 3X) OR (f = 5X) THEN size := 2
										ELSIF (f # 0FX) & (f # 11X) & (f # 12X) THEN size := 4
										END;
										IF size > 0 THEN
											GetInt(mod + 68, data);	(* mod.data *)
											adr := data + x;
											path := path + s.string$;
											s.Scan;
											IF (s.type = TextMappers.char) & (s.char = "-") THEN size := -size END
										ELSE Dialog.ShowParamMsg("#Dev:NoBasicType", s.string, "", "")
										END
									ELSE Dialog.ShowParamMsg("#Dev:NoVariable", s.string, "", "")
									END
								ELSE Dialog.ShowParamMsg("#Dev:NoVariable", s.string, "", "")
								END
							ELSE Dialog.ShowMsg("#Dev:NoVarName")
							END
						ELSE Dialog.ShowMsg("#Dev:NoQualident")
						END
					ELSE Dialog.ShowParamMsg("#Dev:NoModule", s.string, "", "")
					END
				ELSE Dialog.ShowMsg("#Dev:NoModuleName")
				END
			ELSIF c.HasCaret() THEN
				beg := c.CaretPos();
				s.ConnectTo(c.text); s.SetPos(0); s.Scan;
				WHILE ~s.rider.eot & ((s.type # TextMappers.string) OR (s.string # "MODULE")) DO s.Scan END;
				s.Scan; mod := 0;
				IF s.type = TextMappers.string THEN
					mod := ThisMod(s.string);
					IF mod # 0 THEN
						GetCodePos(mod, beg, adr);
						IF adr # 0 THEN
							INC(adr, ModCode(mod)); path := s.string$
						ELSE Dialog.ShowParamMsg("#Dev:NoSourcePosInfoIn", s.string, "", "")
						END
					ELSE Dialog.ShowParamMsg("#Dev:NoModule", s.string, "", "")
					END
				ELSE Dialog.ShowMsg("#Dev:NoModuleSource")
				END
			ELSE Dialog.ShowMsg("#Dev:NoSelectionOrCaret")
			END
		ELSE Dialog.ShowMsg("#Dev:NoText")
		END
	END GetBreakPos;

(* -------------------- *)
	PROCEDURE IsBadSourcePos (adr: INTEGER): BOOLEAN;
		VAR ad, p: INTEGER; mod: Module;
	BEGIN
		IF (modCache # 0) & (ModCnt(modCache) >= 0)
				& (adr >= ModCode(modCache)) & (adr < ModCode(modCache) + ModCSize(modCache)) THEN
			mod := modCache
		ELSE
			mod := ModList();
			WHILE (mod # 0) & ((adr < ModCode(mod)) OR (adr >= ModCode(mod) + ModCSize(mod))) DO
				mod := ModNext(mod)
			END
		END;
		IF mod # 0 THEN
			modCache := mod;
			DEC(adr, ModCode(mod));
			GetSourcePos(mod, adr - 1, ad, p);
			RETURN ad > adr
		ELSE
			RETURN TRUE
		END
	END IsBadSourcePos;

	PROCEDURE OutAdr (adr: INTEGER);
	BEGIN
		out.WriteString(" ("); OutString("#System:adr"); out.WriteString(" = "); WriteHex(adr); out.WriteChar(")")
	END OutAdr;

	PROCEDURE Trap;
		VAR a0: TextModels.Attributes; t: TextModels.Model;
	BEGIN
		cacheLine := 0;
		t := TextModels.CloneOf(stateText);
		out.ConnectTo(t);
		a0 := out.rider.attr;
		(* output header *)
		out.rider.SetAttr(TextModels.NewWeight(a0, Fonts.bold));
		IF err = 129 THEN OutString("#System:invalid WITH")
		ELSIF err = 130 THEN OutString("#System:invalid CASE")
		ELSIF err = 131 THEN OutString("#System:function without RETURN")
		ELSIF err = 132 THEN OutString("#System:type guard")
		ELSIF err = 133 THEN OutString("#System:implied type guard")
		ELSIF err = 134 THEN OutString("#System:value out of range")
		ELSIF err = 135 THEN OutString("#System:index out of range")
		ELSIF err = 136 THEN OutString("#System:string too long")
		ELSIF err = 137 THEN OutString("#System:stack overflow")
		ELSIF err = 138 THEN OutString("#System:integer overflow")
		ELSIF err = 139 THEN OutString("#System:division by zero")
		ELSIF err = 140 THEN OutString("#System:infinite real result")
		ELSIF err = 141 THEN OutString("#System:real underflow")
		ELSIF err = 142 THEN OutString("#System:real overflow")
		ELSIF err = 143 THEN
			OutString("#System:undefined real result"); out.WriteString(" (");
			out.WriteIntForm(val MOD 10000H, TextMappers.hexadecimal, 4, "0", TextMappers.hideBase);
			out.WriteString(", ");
			out.WriteIntForm(val DIV 10000H, TextMappers.hexadecimal, 3, "0", TextMappers.hideBase);
			out.WriteChar(")")
		ELSIF err = 144 THEN OutString("#System:not a number")
		ELSIF err = 200 THEN
			IF val = 0 THEN OutString("#Dev:stopped")
			ELSIF val > 0 THEN OutString("#Dev:breakpoint"); out.WriteChar(" "); out.WriteInt(val)
			ELSE OutString("#Dev:data breakpoint"); out.WriteChar(" "); out.WriteInt(-val)
			END
		ELSIF err = 201 THEN OutString("#System:NIL dereference")
		ELSIF err = 202 THEN
			OutString("#System:illegal instruction"); out.WriteString(": ");
			out.WriteIntForm(val, TextMappers.hexadecimal, 5, "0", TextMappers.showBase)
		ELSIF err = 203 THEN
			IF (val >= -4) & (val < 65536) THEN OutString("#System:NIL dereference (read)")
			ELSE OutString("#System:illegal memory read"); OutAdr(val)
			END
		ELSIF err = 204 THEN
			IF (val >= -4) & (val < 65536) THEN OutString("#System:NIL dereference (write)")
			ELSE OutString("#System:illegal memory write"); OutAdr(val)
			END
		ELSIF err = 205 THEN
			IF (val >= -4) & (val < 65536) THEN OutString("#System:NIL procedure call")
			ELSE OutString("#System:illegal execution"); OutAdr(val)
			END
		ELSIF err = 207 THEN OutString("#System:keyboard interrupt")
		ELSIF err = 257 THEN OutString("#System:out of memory")
		ELSIF err = 10001H THEN OutString("#System:bus error")
		ELSIF err = 10002H THEN OutString("#System:address error")
		ELSIF err = 10007H THEN OutString("#System:fpu error")
		ELSIF err < 0 THEN
			OutString("#System:Exception"); out.WriteChar(" ");
			out.WriteIntForm(-err, TextMappers.hexadecimal, 3, "0", TextMappers.showBase)
		ELSE
			OutString("#System:TRAP"); out.WriteChar(" "); out.WriteInt(err);
			IF err = 126 THEN
				out.WriteString("  ("); OutString("#System:not yet implemented");  out.WriteChar(")")
			ELSIF err = 125 THEN
				out.WriteString("  ("); OutString("#System:call of obsolete procedure"); out.WriteChar(")")
			ELSIF err >= 100 THEN
				out.WriteString("  ("); OutString("#System:invariant violated");  out.WriteChar(")")
			ELSIF err >= 60 THEN
				out.WriteString("  ("); OutString("#System:postcondition violated");  out.WriteChar(")")
			ELSIF err >= 20 THEN
				out.WriteString("  ("); OutString("#System:precondition violated");  out.WriteChar(")")
			END
		END;
		out.WriteLn; out.rider.SetAttr(a0); out.WriteLn;
		(* output stack frames *)
		framePc := pc; frameFp := fp; frameCnt := maxStackFrames; showSrc := TRUE; stepOut.state := 0;
		WHILE frameCnt > 0 DO ShowStackFrame(t) END;
		(* update stateText *)
		Models.BeginModification(Models.notUndoable, stateText);
		stateText.Replace(0, stateText.Length(), t, 0, t.Length());
		Models.EndModification(Models.notUndoable, stateText);
	END Trap;
	
	PROCEDURE OpenDebugTool(bringToFront: BOOLEAN);
		VAR res: INTEGER; w: Windows.Window; title: Views.Title;
	BEGIN
		(* we try to avoid flickering effects *)
		IF (toolWindow = NIL) OR (toolWindow.wnd = 0) THEN (* closed *)
			SetPreferredWinPos(winpos.debug);
			StdApi.OpenToolDialog("Dev/Rsrc/RTDebug", "#Dev:RTDebugTool", toolDlg);
			w := Windows.dir.First();
			WHILE w # NIL DO
				w.GetTitle(title);
				IF (Windows.isTool IN w.flags) & (title = "#Dev:RTDebugTool") THEN
					toolWindow := w(HostWindows.Window); w := NIL
				ELSE w := Windows.dir.Next(w)
				END
			END
		END;
		ASSERT((toolWindow # NIL) & (toolWindow.wnd # 0));
		IF bringToFront THEN res := WinApi.SetForegroundWindow(toolWindow.wnd) END
	END OpenDebugTool;

	PROCEDURE HandleException (VAR event: WinApi.DEBUG_EVENT);
		VAR exCode: INTEGER; context: WinApi.CONTEXT; s: SET;
	BEGIN
		stopping := FALSE;
		IF event.u.Exception.dwFirstChance # 0 THEN END;
		context.ContextFlags := WinApi.CONTEXT_CONTROL + WinApi.CONTEXT_DEBUG_REGISTERS;
		Check(WinApi.GetThreadContext(threadHandle, context));
		pc := context.Eip;
		sp := context.Esp;
		fp := context.Ebp;
		IF dbgBase # 0 THEN stack := Stack() ELSE stack := 0 END;
		exCode := event.u.Exception.ExceptionRecord.ExceptionCode;
		IF exCode = WinApi.EXCEPTION_BREAKPOINT THEN err := 207
		ELSIF exCode = WinApi.EXCEPTION_SINGLE_STEP THEN err := 200;
			s := SYSTEM.VAL(SET, context.Dr6);
			IF 0 IN s THEN val := 1
			ELSIF 1 IN s THEN val := 2
			ELSIF 2 IN s THEN val := 3
			ELSE val := 0
			END;
			IF (val > 0) & (breakpoints[val-1].size # 0) THEN val := -val; DEC(pc) END	(* watchpoint *)
		ELSIF exCode = WinApi.EXCEPTION_ACCESS_VIOLATION THEN
			val := event.u.Exception.ExceptionRecord.ExceptionInformation[1];
			IF val = pc THEN	(* call to undef adr *)
				err := 205; GetInt(sp, pc); INC(sp, 4); DEC(pc)
			ELSIF event.u.Exception.ExceptionRecord.ExceptionInformation[0] = 0 THEN	(* illegal read *)
				err := 203
			ELSE	(* illegal write *)
				err := 204
			END
		ELSIF (exCode = WinApi.EXCEPTION_ILLEGAL_INSTRUCTION)
			OR (exCode = WinApi.EXCEPTION_ILLEGAL_INSTRUCTION + 1(*TODO JT required*)) THEN
			err := 202; 
			val := 0;
			GetInt(event.u.Exception.ExceptionRecord.ExceptionAddress, val);
			IF val MOD 100H = 8DH THEN	(* lea reg,reg *)
				IF val DIV 100H MOD 100H = 0F0H THEN	(* trap *)
					err := val DIV 10000H MOD 100H
				ELSIF val DIV 1000H MOD 10H = 0EH THEN	(* run time error *)
					err := 128 + val DIV 100H MOD 10H
				END
			END
		ELSIF exCode = WinApi.EXCEPTION_FLT_DIVIDE_BY_ZERO THEN DEC(pc); err := 140
		ELSIF exCode = WinApi.EXCEPTION_FLT_INVALID_OPERATION THEN DEC(pc); err := 143
		ELSIF exCode = WinApi.EXCEPTION_FLT_OVERFLOW THEN DEC(pc); err := 142
		ELSIF exCode = WinApi.EXCEPTION_FLT_UNDERFLOW THEN DEC(pc); err := 141
		ELSIF exCode = WinApi.EXCEPTION_INT_DIVIDE_BY_ZERO THEN err := 139
		ELSIF exCode = WinApi.EXCEPTION_INT_OVERFLOW THEN err := 138
		ELSIF (exCode = WinApi.EXCEPTION_GUARD_PAGE)
			OR (exCode = WinApi.EXCEPTION_STACK_OVERFLOW) THEN err := 137
		ELSE err := -(exCode MOD 256)
		END;
		OpenDebugTool(TRUE);
		Trap
	END HandleException;

	PROCEDURE ScanConst(IN s, const: ARRAY OF CHAR; VAR pos: INTEGER): BOOLEAN;
		VAR cpos: INTEGER;
	BEGIN
		Strings.Find(s, const, pos, cpos);
		IF cpos = pos THEN INC(pos, LEN(const$)); RETURN TRUE
		ELSE RETURN FALSE
		END
	END ScanConst;

	PROCEDURE ScanName(IN s, const: ARRAY OF CHAR; VAR pos: INTEGER; OUT name: ARRAY OF CHAR): BOOLEAN;
		VAR cpos: INTEGER;
	BEGIN
		Strings.Find(s, const, pos, cpos);
		IF cpos # -1 THEN Strings.Extract(s, pos, cpos - pos, name); pos := cpos + LEN(const$); RETURN TRUE
		ELSE RETURN FALSE
		END
	END ScanName;

	PROCEDURE ScanInt(IN s: ARRAY OF CHAR; VAR pos, val: INTEGER): BOOLEAN;
		VAR i, res: INTEGER; ch: CHAR; num: ARRAY 24 OF CHAR;
	BEGIN
		ch := s[pos]; i := 0;
		WHILE (ch >= "0") & (ch <= "9") DO num[i] := ch; INC(i); ch := s[pos + i] END;
		num[i] := 0X;
		Strings.StringToInt(num, val, res);
		IF res = 0 THEN INC(pos, i) END;
		RETURN res = 0
	END ScanInt;
	
	PROCEDURE HandleDebugStringEvent(lpDebugStringData: WinApi.PtrSTR): BOOLEAN;
		VAR pos, adr: INTEGER; string, modName: Name;
	BEGIN
		GetName(SYSTEM.VAL(INTEGER, lpDebugStringData), string);
		pos := 0;
		IF ScanConst(string, "BlackBox debug [continueTo=", pos) THEN
			IF ScanInt(string, pos, adr) & (adr > 0) THEN
				ContinueExec(err, adr);
				SetRunning;
				OpenDebugTool(TRUE);
				RETURN TRUE
			END
		ELSIF ScanConst(string, "BlackBox debug [module=", pos) THEN
			IF ScanName(string, "]", pos, modName) THEN
				ShowSourcePos(modName, MAX(INTEGER), TRUE);
				ContinueExec(err, 0);
				SetRunning;
				OpenDebugTool(TRUE);
				RETURN TRUE
			ELSE HALT(99) (* internal error *)
			END
		END;
		RETURN FALSE
	END HandleDebugStringEvent;

	PROCEDURE HandleEvent (VAR event: WinApi.DEBUG_EVENT);
		VAR exCode, adr: INTEGER; context: WinApi.CONTEXT; 
	BEGIN
		(*Log.String("HandleEvent: event.dwDebugEventCode="); Log.Int(event.dwDebugEventCode); Log.Ln;*)
		IF event.dwDebugEventCode = WinApi.EXCEPTION_DEBUG_EVENT THEN
			IF (threadId = event.dwThreadId) & (procId = event.dwProcessId) THEN
				exCode := event.u.Exception.ExceptionRecord.ExceptionCode;
				adr := event.u.Exception.ExceptionRecord.ExceptionAddress;
				IF (exCode = WinApi.EXCEPTION_BREAKPOINT) THEN
					IF stopping THEN (* debug event created by DebugBreakProcess under wine *)
						HandleException(event)
					ELSE
						Check(WinApi.ContinueDebugEvent(event.dwProcessId, event.dwThreadId, 
																			WinApi.DBG_CONTINUE))
					END
				ELSIF exCode = WinApi.EXCEPTION_SINGLE_STEP THEN
					context.ContextFlags := WinApi.CONTEXT_DEBUG_REGISTERS;
					Check(WinApi.GetThreadContext(threadHandle, context));
					IF (context.Dr6 MOD 8 = 0) & ~stopping & ((skipMode # -1) OR IsBadSourcePos(adr)) THEN
						ContinueExec(200, skipMode)
					ELSE
						HandleException(event)
					END
				ELSE
					HandleException(event)
				END
			ELSIF stopping THEN (* debug event created by DebugBreakProcess under Windows *)
				context.ContextFlags := WinApi.CONTEXT_CONTROL + WinApi.CONTEXT_DEBUG_REGISTERS;
				Check(WinApi.GetThreadContext(threadHandle, context));
				context.Dr3 := context.Eip; INCL(SYSTEM.VAL(SET, context.Dr7), 6);	(* set breakpoint 3 *)
				Check(WinApi.SetThreadContext(threadHandle, context));
				Check(WinApi.ContinueDebugEvent(event.dwProcessId, event.dwThreadId, WinApi.DBG_CONTINUE))
			ELSE
				Check(WinApi.ContinueDebugEvent(event.dwProcessId, event.dwThreadId,
																	WinApi.DBG_EXCEPTION_NOT_HANDLED))
			END
		ELSE
			CASE event.dwDebugEventCode OF
			| WinApi.CREATE_PROCESS_DEBUG_EVENT :
				IF event.dwProcessId = procId THEN procHandle := event.u.CreateProcessInfo.hProcess END;
				IF event.dwThreadId = threadId THEN threadHandle := event.u.CreateProcessInfo.hThread END;
				context.ContextFlags := WinApi.CONTEXT_DEBUG_REGISTERS;
				Check(WinApi.GetThreadContext(threadHandle, context));
				context.Dr6 := 0; context.Dr7 := 0;
				Check(WinApi.SetThreadContext(threadHandle, context))
			| WinApi.CREATE_THREAD_DEBUG_EVENT:
				IF event.dwThreadId = threadId THEN threadHandle := event.u.CreateThread.hThread END;
				context.ContextFlags := WinApi.CONTEXT_DEBUG_REGISTERS;
				Check(WinApi.GetThreadContext(threadHandle, context));
				context.Dr6 := 0; context.Dr7 := 0;
				Check(WinApi.SetThreadContext(threadHandle, context))
			| WinApi.EXIT_PROCESS_DEBUG_EVENT:
				IF event.dwProcessId = procId THEN SetTerminated END
			| WinApi.EXIT_THREAD_DEBUG_EVENT:
				IF event.dwThreadId = threadId THEN SetTerminated END
			| WinApi.LOAD_DLL_DEBUG_EVENT:
			| WinApi.UNLOAD_DLL_DEBUG_EVENT:
			| WinApi.OUTPUT_DEBUG_STRING_EVENT:
				IF (event.u.DebugString.fUnicode = 0) & (event.dwProcessId = procId) THEN
					IF HandleDebugStringEvent(event.u.DebugString.lpDebugStringData) THEN RETURN END
				END
			ELSE
				Dialog.ShowMsg("#Dev:UnknownEvent")
			END;
			Check(WinApi.ContinueDebugEvent(event.dwProcessId, event.dwThreadId, WinApi.DBG_CONTINUE))
		END
	END HandleEvent;

(* ---------- Action ---------- *)

	PROCEDURE ActionDo;
		VAR event: WinApi.DEBUG_EVENT; t0: LONGINT; (* t: TextModels.Model; *)
	BEGIN
		t0 := Services.Ticks();
		WHILE (Services.Ticks() - t0 < 500) & (WinApi.WaitForDebugEvent(event, 20) # 0) DO
			HandleEvent(event)
		END;
		(*
		IF frameCnt > 0 THEN
			t := TextModels.CloneOf(stateText);
			ShowStackFrame(t);
			Models.BeginModification(Models.notUndoable, stateText);
			stateText.Insert(stateText.Length(), t, 0, t.Length());
			Models.EndModification(Models.notUndoable, stateText)
		END;
		*)
		Dialog.UpdateInt(err); (* dummy op for forcing immediate guard evaluation *)
	END ActionDo;
	
	PROCEDURE (a: DebugAction) Do;
	BEGIN
		IF (*starting up*)(procId # 0) & (procHandle = 0) OR Valid() THEN ActionDo;
			Services.DoLater(a, Services.now)
		ELSE stateText := NIL
		END
	END Do;

(* ---------- commands ---------- *)
	
	PROCEDURE StepOut*;
	BEGIN
		IF IsStopped() THEN
			FocusThisControl("DevRTDebug.DEFOCUS");
			IF stepOut.state IN {2, 4} THEN (* step out from system code *)
				ContinueExec(err, stepOut.pc);
			END;
			SetRunning;
			ActionDo;
			IF err = running THEN FocusThisControl("DevRTDebug.Stop") END
		END
	END StepOut;
	
	(* TODO this does not work sometimes when stepping over <system> code.  The debugger
		may loose control, i.e. there are no debugging events generated and the debugged thread
		continues running. The reason is not clear. It may even be a bug in the Windows debug API. *)
	PROCEDURE StepInto*;
	BEGIN
		IF stepOut.state = 2 THEN
			StepOut
		ELSIF IsStopped() THEN
			FocusThisControl("DevRTDebug.DEFOCUS");
			skipCalls := FALSE;
			ContinueExec(err, -1);
			SetRunning;
			ActionDo;
			IF err = 200 THEN FocusThisControl("DevRTDebug.StepInto") END
		END
	END StepInto;
	
	PROCEDURE StepOver*;
	BEGIN
		IF stepOut.state = 2 THEN
			StepOut
		ELSIF IsStopped() THEN
			FocusThisControl("DevRTDebug.DEFOCUS");
			skipCalls := TRUE;
			ContinueExec(err, -1);
			SetRunning;
			ActionDo;
			IF err = running THEN FocusThisControl("DevRTDebug.Stop") END
		END
	END StepOver;
	
	PROCEDURE Continue*;
	BEGIN
		IF IsStopped() THEN
			FocusThisControl("DevRTDebug.DEFOCUS");
			ContinueExec(err, 0);
			SetRunning;
			ActionDo;
			IF err = 200 THEN FocusThisControl("DevRTDebug.Continue") END
		END
	END Continue;
	
	PROCEDURE ContinueTo*;
		VAR adr, size: INTEGER; path: Name;
	BEGIN
		IF IsStopped() THEN
			GetBreakPos(adr, size, path);
			IF (adr # 0) & (size = 0) THEN
				FocusThisControl("DevRTDebug.DEFOCUS");
				ContinueExec(err, adr);
				SetRunning;
				ActionDo
			ELSIF stepOut.state IN {2, 4} THEN
				StepOut
			END
		END
	END ContinueTo;

	PROCEDURE Handle*;
		VAR res: INTEGER;
	BEGIN
		IF Valid() & (err # running) & (err # 200) & (err # 207) THEN
			FocusThisControl("DevRTDebug.DEFOCUS");
			res := WinApi.ContinueDebugEvent(procId, threadId, WinApi.DBG_EXCEPTION_NOT_HANDLED);
			SetRunning;
			ActionDo;
			IF err = running THEN FocusThisControl("DevRTDebug.Stop") END
		END
	END Handle;

	PROCEDURE Stop*;
		
		(* original ominc version; after Win10 upgrade only stops thread reliably when executing in BlackBox code *)
		PROCEDURE WineStop;
			VAR res: INTEGER; context: WinApi.CONTEXT;
		BEGIN
			Suspend;
			context.ContextFlags := WinApi.CONTEXT_CONTROL;
			Check(WinApi.GetThreadContext(threadHandle, context));
			INCL(SYSTEM.VAL(SET, context.EFlags), 8);	(* set trace flag *)
			Check(WinApi.SetThreadContext(threadHandle, context));
			Resume
		END WineStop;
		
	BEGIN
		IF Valid() & (err = running) THEN
			FocusThisControl("DevRTDebug.DEFOCUS");
			stopping := TRUE;
			IF Dialog.IsWine() THEN
				WineStop
			ELSE
				Check(WinApi.DebugBreakProcess(procHandle));
			END;
			ActionDo
		END
	END Stop;

	PROCEDURE ShowLoadedModules*;
	BEGIN
		IF Valid() THEN
			Suspend;
			out.ConnectTo(TextModels.dir.New());
			ShowModules;
			OpenViewer(out.rider.Base(), "#Dev:RemoteModules", NewModRuler());
			out.ConnectTo(NIL);
			Resume
		END
	END ShowLoadedModules;
	
	PROCEDURE UpdateModules*;
		VAR t, t0: TextModels.Model; script: Stores.Operation;
	BEGIN
		IF Valid() THEN
			Suspend;
			t0 := TextViews.FocusText();
			Models.BeginScript(t0, "#Dev:Change", script);
			t := TextModels.CloneOf(t0);
			out.ConnectTo(t);
			ShowModules;
			t0.Delete(0, t0.Length()); t0.Insert(0, t, 0, t.Length());
			Models.EndScript(t0, script);
			out.ConnectTo(NIL);
			Resume
		END
	END UpdateModules;

	PROCEDURE ShowGlobalVariables*;
		VAR mod: Module;
	BEGIN
		IF Valid() THEN
			Suspend;
			GetMod(mod);
			IF mod # 0 THEN
				out.ConnectTo(TextModels.dir.New());
				ShowGlobals(mod);
				OpenViewer(out.rider.Base(), "#Dev:RemoteVariables", NewRuler());
				out.ConnectTo(NIL)
			END;
			Resume
		END
	END ShowGlobalVariables;
	
	PROCEDURE UpdateGlobals* (name: ARRAY OF CHAR);
		VAR t, t0: TextModels.Model; script: Stores.Operation; mod: Module;
	BEGIN
		IF Valid() THEN
			Suspend;
			mod := ThisMod(name);
			IF mod # 0 THEN
				t0 := TextViews.FocusText();
				Models.BeginScript(t0, "#Dev:Change", script);
				t := TextModels.CloneOf(t0);
				out.ConnectTo(t);
				ShowGlobals(mod);
				Stores.Join(t, t0);
				t0.Delete(0, t0.Length()); t0.Insert(0, t, 0, t.Length());
				Models.EndScript(t0, script);
				out.ConnectTo(NIL)
			END;
			Resume
		END
	END UpdateGlobals;

	PROCEDURE Terminate*;
		VAR res: INTEGER;
	BEGIN
		IF Valid() THEN
			FocusThisControl("DevRTDebug.DEFOCUS");
			Check(WinApi.TerminateProcess(procHandle, 1));
			res := WinApi.DebugActiveProcessStop(procId);
			SetTerminated
		END
	END Terminate;
	
	PROCEDURE Breakpoint* (n: INTEGER);
		VAR adr, size, res: INTEGER; context: WinApi.CONTEXT; path: Name;
	BEGIN
		ASSERT((n >= 0) & (n < 3), 20);
		IF Valid() THEN
			IF err = running THEN
				Suspend;
				context.ContextFlags := WinApi.CONTEXT_DEBUG_REGISTERS;
				res := WinApi.GetThreadContext(threadHandle, context)
			END;
			IF breakpoints[n].adr = 0 THEN
				GetBreakPos(adr, size, path);
				IF adr # 0 THEN
					breakpoints[n].path := path;
					breakpoints[n].adr := adr;
					breakpoints[n].size := size
				END
			ELSE
				breakpoints[n].path := "";
				breakpoints[n].adr := 0;
				breakpoints[n].size := 0
			END;
			IF err = running THEN
				SetBP(breakpoints[n], n, context);
				res := WinApi.SetThreadContext(threadHandle, context);
				Resume
			END
		END
	END Breakpoint;
	
	PROCEDURE ShowBreakpoint* (n: INTEGER);
		VAR brk: BrkPt; num: ARRAY 10 OF CHAR; path: Dialog.String;
	BEGIN
		ASSERT((n >= 0) & (n < 3), 20);
		brk := breakpoints[n];
		IF brk.adr # 0 THEN
			IF brk.size = 0 THEN
				ShowSourcePos(brk.path, brk.adr - ModCode(ThisMod(brk.path)), FALSE)
			ELSE
				Strings.IntToString(n + 1, num);
				path := brk.path$;
				IF brk.size < 0 THEN path := path + "-" END;
				Dialog.ShowParamMsg("#Dev:DataBreakpoint", num, path, "")
			END
		END
	END ShowBreakpoint;

	PROCEDURE RemoteState*;
		VAR w: Windows.Window;
	BEGIN
		w := Windows.dir.First();
		WHILE (w # NIL) & ((w.doc = NIL) OR (w.doc.ThisView() = NIL)
														OR (w.doc.ThisView().ThisModel() # stateText)) DO
			w := Windows.dir.Next(w)
		END;
		IF w # NIL THEN
			Windows.dir.Select(w, Windows.lazy);
		ELSE
			SetPreferredWinPos(winpos.state);
			OpenViewer(stateText, "#Dev:RemoteState", NewRuler())
		END
	END RemoteState;

	PROCEDURE RemoteSource*;
		VAR c: TextControllers.Controller; s: TextMappers.Scanner; beg, end: INTEGER;
			w: Windows.Window;
	BEGIN
		c := TextControllers.Focus();
		IF c # NIL THEN
			IF c.HasSelection() THEN
				c.GetSelection(beg, end); s.ConnectTo(c.text); s.SetPos(beg); Scan(s);
				IF (s.type = TextMappers.string) & (s.Pos() >= end) THEN
					DevReferences.ResolveImportAlias(s.string, c.text);
					ShowSourceWindow(s.string$, MAX(INTEGER)(*no adr*), FALSE);
					RETURN
				END
			END
		END;
		OpenRemoteSource(TRUE)
	END RemoteSource;

	PROCEDURE RemoteStateGuard* (VAR par: Dialog.Par);
		VAR state: Dialog.String;
	BEGIN
		IF ~Valid() THEN state := "#Dev:terminated"
		ELSIF err = running THEN state := "#Dev:running"
		ELSIF err = 200 THEN state := "#Dev:stopped"
		ELSIF err = 207 THEN state := "#System:keyboard interrupt"
		ELSE state := "#Dev:trapped"
		END;
		Dialog.MapString(state, state);
		Dialog.MapParamString("#Dev:RemoteState:", state, "", "", par.label)
	END RemoteStateGuard;
	
	PROCEDURE ContinueGuard* (VAR par: Dialog.Par);
	BEGIN
		IF ~IsStopped() THEN par.disabled := TRUE END
	END ContinueGuard;

	PROCEDURE HandleGuard* (VAR par: Dialog.Par);
	BEGIN
		IF ~Valid() OR (err = running) OR (err = 200) OR (err = 207) THEN par.disabled := TRUE END
	END HandleGuard;
	
	PROCEDURE ValidGuard* (VAR par: Dialog.Par);
	BEGIN
		IF ~Valid() THEN par.disabled := TRUE END
	END ValidGuard;
	
	PROCEDURE GlobalVariablesGuard* (VAR par: Dialog.Par);
	BEGIN
		ValidGuard(par);
		TextCmds.SelectionGuard(par)
	END GlobalVariablesGuard;
	
	PROCEDURE StopGuard* (VAR par: Dialog.Par);
	BEGIN
		IF ~Valid() OR (err # running) THEN par.disabled := TRUE END
	END StopGuard;
	
	PROCEDURE BreakLabelGuard* (n: INTEGER; VAR par: Dialog.Par);
	BEGIN
		ASSERT((n >= 0) & (n < 3), 20);
		par.readOnly := TRUE;
		IF ~Valid() THEN par.disabled := TRUE END;
		IF breakpoints[n].adr # 0 THEN
			IF breakpoints[n].size = 0 THEN par.label := "code"
			ELSIF breakpoints[n].size > 0 THEN par.label := "data"
			ELSE par.label := "data write"
			END
		ELSE par.label := "---"
		END
	END BreakLabelGuard;
	
	PROCEDURE ShowBreakpointGuard* (n: INTEGER; VAR par: Dialog.Par);
	BEGIN
		ASSERT((n >= 0) & (n < 3), 20);
		IF breakpoints[n].adr = 0 THEN par.disabled := TRUE END
	END ShowBreakpointGuard;

	PROCEDURE BreakpointGuard* (n: INTEGER; VAR par: Dialog.Par);
	BEGIN
		ASSERT((n >= 0) & (n < 3), 20);
		IF ~Valid() THEN par.disabled := TRUE END;
		IF breakpoints[n].adr # 0 THEN par.checked := TRUE END
	END BreakpointGuard;

(* ---------- initialization ---------- *)
	
	PROCEDURE GetWinPos(w: Windows.Window; VAR winpos: WinPos);
		VAR winp: WinApi.WINDOWPLACEMENT; res: INTEGER;
	BEGIN
		WITH w: HostWindows.Window DO
			winp.length := SIZE(WinApi.WINDOWPLACEMENT);
			res := WinApi.GetWindowPlacement(w.wnd, winp);
			winpos[WinPos_Left] := MAX(winp.rcNormalPosition.left, 0);
			winpos[WinPos_Top] := MAX(winp.rcNormalPosition.top, 0);
			winpos[WinPos_Right] := winpos[WinPos_Left]
				+ (winp.rcNormalPosition.right - winp.rcNormalPosition.left);
			winpos[WinPos_Bottom] := winpos[WinPos_Top] 
				+ (winp.rcNormalPosition.bottom - winp.rcNormalPosition.top);
		END
	END GetWinPos;
	
	PROCEDURE (this: OpenToolAction) Do;
		VAR w, n: Windows.Window; title: Views.Title; toolFound: BOOLEAN;
	BEGIN
		Services.DoLater(this, Services.Ticks() + 100); toolFound := FALSE;
		w := Windows.dir.First();
		WHILE w # NIL DO
			w.GetTitle(title);
			IF title = "#Dev:RTDebugTool" THEN GetWinPos(w, winpos.debug); toolFound:= TRUE
			ELSIF (title = "#Dev:RemoteState") THEN GetWinPos(w, winpos.state)
			ELSIF (title = "#Dev:RemoteSource") THEN GetWinPos(w, winpos.source)
			END;
			w := Windows.dir.Next(w)
		END;
		IF ~toolFound THEN
			w := Windows.dir.First();
			WHILE w # NIL DO
				w.GetTitle(title);
				IF (title # "#Dev:RTDebugTool")
				& (title # "#Dev:RemoteState")
				& (title # "#Dev:RemoteSource")
				& (title # "#Dev:Log") 
				& (~w.seq.Dirty() OR ((Windows.neverDirty IN w.flags))) THEN
					n := Windows.dir.Next(w); HostWindows.dir.Close(w); w := n; n := NIL
				ELSE
					w := Windows.dir.Next(w)
				END;
			END;
			Kernel.Cleanup;
			OpenDebugTool(FALSE)
		END
	END Do;
	
	PROCEDURE ReadWinPos(IN titleKey: ARRAY OF CHAR; VAR winpos: WinPos; defaultLeft, defaultTop: INTEGER);
		VAR res: INTEGER;
	BEGIN
		HostRegistry.ReadIntList("DevRTDebug\winpos_" + titleKey, winpos, res);
		IF res # 0 THEN
			winpos[WinPos_Left] := defaultLeft;
			winpos[WinPos_Top] := defaultTop;
			winpos[WinPos_Right] := -1;
			winpos[WinPos_Bottom] := -1;
		END
	END ReadWinPos;

	(* setup this process as debugger for another BlackBox process *)
	PROCEDURE InitDbg;
		VAR pid, tid, base: ARRAY 32 OF CHAR;
			res: INTEGER; da: DebugAction; ta: OpenToolAction;
	BEGIN
		(* get params via environment variables *)
		IF WinApi.GetEnvironmentVariableW("BLACKBOX_DBG_PID", pid, LEN(pid)) = 0 THEN
			RETURN (* not started as debugger *)
		END;
		ASSERT(WinApi.GetEnvironmentVariableW("BLACKBOX_DBG_TID", tid, LEN(tid)) # 0);
		ASSERT(WinApi.GetEnvironmentVariableW("BLACKBOX_DBG_BASE", base, LEN(base)) # 0);
		ASSERT(WinApi.GetEnvironmentVariableW("BLACKBOX_DBG_ROOT", rootDir, LEN(rootDir)) # 0);
		res := WinApi.GetEnvironmentVariableW("BLACKBOX_DBG_USE", usePath, LEN(usePath)); (* optional *)
		Strings.StringToInt(pid, procId, res); ASSERT(res = 0);
		Strings.StringToInt(tid, threadId, res); ASSERT(res = 0);
		Strings.StringToInt(base, dbgBase, res); ASSERT(res = 0);
		(* connect via Windows user mode debugging API *)
		res := WinApi.DebugActiveProcess(procId);
		res := WinApi.DebugSetProcessKillOnExit(0); (* do not kill client on debugger exit *)
		stateText := TextModels.dir.New();
		remoteSourceView := TextViews.dir.New(TextModels.dir.New());
		SetRunning;
		(* get registry settings *)
		HostRegistry.ReadBool("DevRTDebug\singleSource", singleSource, res);
		IF res # 0 THEN singleSource := TRUE (* default *) END;
		HostRegistry.ReadBool("DevRTDebug\expandAll", expandAll, res);
		IF res # 0 THEN expandAll := FALSE (* default *) END;
		ReadWinPos("RTDebugTool", winpos.debug, -1, -1);
		ReadWinPos("RemoteState", winpos.state, HostWindows.mainW DIV 5, 0);
		ReadWinPos("RemoteSource", winpos.source, HostWindows.mainW, 0);
		(* open windows and start background actions *)
		RemoteState;
		IF singleSource THEN OpenRemoteSource(FALSE) END;
		OpenDebugTool(FALSE);
		NEW(da); Services.DoLater(da, Services.now); (* the debugger action *)
		NEW(ta); Services.DoLater(ta, Services.now); (* for keeping the debug tool open *)
		Dialog.ShowParamMsg("#Dev:Debugging", pid, "", "")
	END InitDbg;
	
	PROCEDURE RegisterWinPos(IN titleKey: ARRAY OF CHAR; IN winpos: WinPos);
	BEGIN
		HostRegistry.WriteIntList("DevRTDebug\winpos_" + titleKey, winpos)
	END RegisterWinPos;

	PROCEDURE FiniDbg;
	BEGIN
		val := WinApi.DebugActiveProcessStop(procId);
		HostRegistry.WriteBool("DevRTDebug\singleSource", singleSource);
		HostRegistry.WriteBool("DevRTDebug\expandAll", expandAll);
		RegisterWinPos("RTDebugTool", winpos.debug);
		RegisterWinPos("RemoteState", winpos.state);
		RegisterWinPos("RemoteSource", winpos.source);
	END FiniDbg;

BEGIN
	empty := "";
	path[0].x := refViewSize DIV 2; path[0].y := 0;
	path[1].x := refViewSize; path[1].y := refViewSize DIV 2;
	path[2].x := refViewSize DIV 2; path[2].y := refViewSize;
	path[3].x := 0; path[3].y := refViewSize DIV 2;
	skipMode := -1; stopping := FALSE; procId := 0;
	InitDbg
CLOSE
	IF procId # 0 THEN FiniDbg END
END DevRTDebug.
