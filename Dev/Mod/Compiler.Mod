MODULE DevCompiler;
(**
	project	= "BlackBox"
	organization	= "www.oberon.ch"
	contributors	= "Oberon microsystems"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	references	= "http://e-collection.library.ethz.ch/eserv/eth:39386/eth-39386-02.pdf"
	changes	= ""
	issues	= ""

**)

	IMPORT Kernel,
		Files, Strings, Views, Dialog, Controls,
		TextModels, TextMappers, TextViews, TextControllers,
		StdLog, StdDialog,
		DevMarkers, DevCommanders, DevSelectors,
		DevCPM, DevCPT, DevCPB, DevCPP, DevCPE, DevCPV := DevCPV486, DevCPS;

	CONST
		(* compiler options: *)
		checks = 0; allchecks = 1; assert = 2; obj = 3; ref = 4; allref = 5; srcpos = 6; reallib = 7; signatures = 8;
		hint = 29; oberon = 30; errorTrap = 31;
		defopt = {checks, assert, obj, ref, allref, srcpos, signatures};

		(* additional scanner types *)
		module = 101; comEnd = 104;

		(*symbol values*)
		comma = 20; rbrak = 24; lbrak = 41; becomes = 44; ident = 48; semicolon = 49;
		import = 74; moduleSym = 75; eof = 76;

	TYPE
		String = POINTER TO ARRAY OF CHAR;
		NameNode = POINTER TO RECORD next: NameNode; name: String END;

	VAR
		sourceR: TextModels.Reader;
		s: TextMappers.Scanner;
		str: Dialog.String;
		found: BOOLEAN;	(* DevComDebug was found -> DTC *)

	PROCEDURE Module (source: TextModels.Reader; opt: SET; log: TextModels.Model; VAR error: BOOLEAN);
		VAR ext, new: BOOLEAN; p: DevCPT.Node;
	BEGIN
		DevCPM.Init(source, log);
		IF found THEN INCL(DevCPM.options, DevCPM.comAware) END;
		IF errorTrap IN opt THEN INCL(DevCPM.options, DevCPM.trap) END;
		IF oberon IN opt THEN INCL(DevCPM.options, DevCPM.oberon) END;
		DevCPT.Init(opt);
		DevCPB.typSize := DevCPV.TypeSize;
		DevCPT.processor := DevCPV.processor;
		DevCPP.Module(p);
		IF DevCPM.noerr THEN
			IF DevCPT.libName # "" THEN EXCL(opt, obj) END;
(*
			IF errorTrap IN opt THEN DevCPDump.DumpTree(p) END;
*)
			DevCPV.Init(opt); DevCPV.Allocate; DevCPT.Export(ext, new);
			IF DevCPM.noerr & (obj IN opt) THEN
				DevCPV.Module(p)
			END;
			DevCPV.Close
		END;
		IF DevCPM.noerr & (new OR ext) THEN DevCPM.RegisterNewSym
		ELSE DevCPM.DeleteNewSym
		END;
		DevCPT.Close;
		error := ~DevCPM.noerr;
		DevCPM.Close;
		p := NIL;
		Kernel.FastCollect;
		IF error THEN
			DevCPM.InsertMarks(source.Base());
			DevCPM.LogWLn; DevCPM.LogWStr(" ");
			IF DevCPM.errors = 1 THEN
				Dialog.MapString("#Dev:OneErrorDetected", str)
			ELSE
				DevCPM.LogWNum(DevCPM.errors, 0); Dialog.MapString("#Dev:ErrorsDetected", str)
			END;
			StdLog.String(str)
		ELSE
			IF hint IN opt THEN DevCPM.InsertMarks(source.Base()) END;
			DevCPM.LogWStr("  "); DevCPM.LogWNum(DevCPE.pc, 8);
			DevCPM.LogWStr("  "); DevCPM.LogWNum(DevCPE.dsize, 8)
		END;
		DevCPM.LogWLn
	END Module;

	PROCEDURE Scan (VAR s: TextMappers.Scanner);
	BEGIN
		s.Scan;
		IF s.type = TextMappers.string THEN
			IF s.string = "MODULE" THEN s.type := module END
		ELSIF s.type = TextMappers.char THEN
			IF s.char = "(" THEN
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

	PROCEDURE Do (source, log: TextModels.Model; beg: INTEGER; opt: SET; VAR error: BOOLEAN);
		VAR s: TextMappers.Scanner;
	BEGIN
		Dialog.MapString("#Dev:Compiling", str);
		StdLog.String(str); StdLog.Char(" ");
		s.ConnectTo(source); s.SetPos(beg);
		Scan(s);
		WHILE (s.type # TextMappers.eot) & (s.type # module) DO Scan(s) END;
		IF s.type = module THEN
			Scan(s);
			IF s.type = TextMappers.string THEN
				StdLog.Char('"'); StdLog.String(s.string); StdLog.Char('"')
			END
		END;
		sourceR := source.NewReader(NIL); sourceR.SetPos(beg);
		Module(sourceR, opt, log, error)
	END Do;


	PROCEDURE Open;
	BEGIN
		Dialog.ShowStatus("#Dev:Compiling");
		StdLog.buf.Delete(0, StdLog.buf.Length())
	END Open;

	PROCEDURE Close;
	BEGIN
		StdLog.text.Append(StdLog.buf);
		IF DevCPM.noerr THEN Dialog.ShowStatus("#Dev:Ok")
		END;
		sourceR := NIL;
		Kernel.Cleanup
	END Close;

	PROCEDURE Compile*;
		VAR t: TextModels.Model; error: BOOLEAN;
	BEGIN
		Open;
		t := TextViews.FocusText();
		IF t # NIL THEN
			Do(t, StdLog.text, 0, defopt, error);
			IF error THEN DevMarkers.ShowFirstError(t, TextViews.focusOnly) END
		ELSE Dialog.ShowMsg("#Dev:NoTextViewFound")
		END;
		Close
	END Compile;

	PROCEDURE CompileOpt* (opt: ARRAY OF CHAR);
		VAR t: TextModels.Model; error: BOOLEAN; i: INTEGER; opts: SET;
	BEGIN
		i := 0; opts := defopt;
		WHILE opt[i] # 0X DO
			IF opt[i] = "-" THEN
				IF srcpos IN opts THEN EXCL(opts, srcpos)
				ELSIF allref IN opts THEN EXCL(opts, allref)
				ELSIF ref IN opts THEN EXCL(opts, ref)
				ELSE EXCL(opts, obj)
				END
			ELSIF opt[i] = "!" THEN
				IF assert IN opts THEN EXCL(opts, assert)
				ELSE EXCL(opts, checks)
				END
			ELSIF opt[i] = "+" THEN INCL(opts, allchecks)
			ELSIF opt[i] = "?" THEN INCL(opts, hint)
			ELSIF opt[i] = "@" THEN INCL(opts, errorTrap)
			ELSIF opt[i] = "$" THEN INCL(opts, oberon)
			END;
			INC(i)
		END;
		Open;
		t := TextViews.FocusText();
		IF t # NIL THEN
			Do(t, StdLog.text, 0, opts, error);
			IF error THEN DevMarkers.ShowFirstError(t, TextViews.focusOnly) END
		ELSE Dialog.ShowMsg("#Dev:NoTextViewFound")
		END;
		Close
	END CompileOpt;

	PROCEDURE CompileText* (text: TextModels.Model; beg: INTEGER; OUT error: BOOLEAN);
	BEGIN
		ASSERT(text # NIL, 20); ASSERT((beg >= 0) & (beg <= text.Length()), 21);
		Open;
		Do(text, StdLog.text, beg, defopt, error);
		IF error THEN DevMarkers.ShowFirstError(text, TextViews.focusOnly) END;
		Close
	END CompileText;

	PROCEDURE CompileAndUnload*;
		VAR t: TextModels.Model; error: BOOLEAN; mod: Kernel.Module; 
			n: ARRAY LEN(DevCPT.Name) OF CHAR; res: INTEGER;
	BEGIN
		Open;
		t := TextViews.FocusText();
		IF t # NIL THEN
			Do(t, StdLog.text, 0, defopt, error);
			IF error THEN DevMarkers.ShowFirstError(t, TextViews.focusOnly)
			ELSE
				Strings.Utf8ToString(DevCPT.SelfName, n, res);
				mod := Kernel.ThisLoadedMod(n);
				IF mod # NIL THEN
					Kernel.UnloadMod(mod);
					Strings.Utf8ToString(DevCPT.SelfName, n, res);
					IF mod.refcnt < 0 THEN
						Dialog.MapParamString("#Dev:Unloaded", n, "", "", str);
						StdLog.String(str); StdLog.Ln;
						Controls.Relink
					ELSE
						Dialog.MapParamString("#Dev:UnloadingFailed", n, "", "", str);
						StdLog.String(str); StdLog.Ln
					END
				END
			END
		ELSE Dialog.ShowMsg("#Dev:NoTextViewFound")
		END;
		Close
	END CompileAndUnload;

	PROCEDURE CompileSelection*;
		VAR c: TextControllers.Controller; t: TextModels.Model; beg, end: INTEGER; error: BOOLEAN;
	BEGIN
		Open;
		c := TextControllers.Focus();
		IF c # NIL THEN
			t := c.text;
			IF c.HasSelection() THEN
				c.GetSelection(beg, end); Do(t, StdLog.text, beg, defopt, error);
				IF error THEN DevMarkers.ShowFirstError(t, TextViews.focusOnly) END
			ELSE Dialog.ShowMsg("#Dev:NoSelectionFound")
			END
		ELSE Dialog.ShowMsg("#Dev:NoTextViewFound")
		END;
		Close
	END CompileSelection;

	PROCEDURE CompileList (beg, end: INTEGER; c: TextControllers.Controller);
		VAR v: Views.View; i: INTEGER; error, one: BOOLEAN; name: Files.Name; loc: Files.Locator;
			t: TextModels.Model; opts: SET; title, entry: ARRAY 64 OF CHAR;
	BEGIN
		s.SetPos(beg); s.Scan; one := FALSE;
		WHILE (s.start < end) & (s.type = TextMappers.string) & (s.len < LEN(name)) DO
			s.Scan; one := TRUE;
			WHILE (s.start < end) & (s.type = TextMappers.char) &
				((s.char = "-") OR (s.char = "+") OR
				(s.char = "!") OR (s.char = "*") OR (s.char = "?") OR (s.char = "^") OR (s.char = "("))
			DO
				IF s.char = "(" THEN
					WHILE (s.start < end) & ((s.type # TextMappers.char) OR (s.char # ")")) DO s.Scan END
				END;
				s.Scan
			END
		END;
		IF one & (s.start >= end) THEN
			s.SetPos(beg); s.Scan; error := FALSE;
			WHILE (s.start < end) & (s.type = TextMappers.string) & ~error DO
				i := 0; WHILE i < LEN(name) DO name[i] := 0X; INC(i) END;
				StdDialog.GetSubLoc(s.string, "Mod", loc, name);
				t := NIL;
				IF loc.res = 0 THEN
					v := Views.OldView(loc, name);
					IF v # NIL THEN
						WITH v: TextViews.View DO t := v.ThisModel()
						ELSE Dialog.ShowParamMsg("#Dev:NoTextFileFound", name, "", ""); error := TRUE
						END
					ELSE Dialog.ShowParamMsg("#Dev:CannotOpenFile", name, "", ""); error := TRUE
					END
				ELSE Dialog.ShowParamMsg("#System:FileNotFound", name, "", ""); error := TRUE
				END;
				s.Scan; opts := defopt;
				WHILE (s.start < end) & (s.type = TextMappers.char) DO
					IF s.char = "-" THEN
						IF srcpos IN opts THEN EXCL(opts, srcpos)
						ELSIF allref IN opts THEN EXCL(opts, allref)
						ELSIF ref IN opts THEN EXCL(opts, ref)
						ELSE EXCL(opts, obj)
						END
					ELSIF s.char = "!" THEN
						IF assert IN opts THEN EXCL(opts, assert)
						ELSE EXCL(opts, checks)
						END
					ELSIF s.char = "+" THEN INCL(opts, allchecks)
					ELSIF s.char = "?" THEN INCL(opts, hint)
					ELSIF s.char = "@" THEN INCL(opts, errorTrap)
					ELSIF s.char = "$" THEN INCL(opts, oberon)
					ELSIF s.char = "(" THEN
						s.Scan;
						WHILE (s.start < end) & (s.type = TextMappers.string) DO
							title := s.string$; s.Scan;
							IF (s.start < end) & (s.type = TextMappers.char) & (s.char = ":") THEN
								s.Scan;
								IF (s.start < end) & (s.type = TextMappers.string) THEN
									entry := s.string$; s.Scan;
									IF t # NIL THEN DevSelectors.ChangeTo(t, title, entry) END
								END
							END;
							IF (s.start < end) & (s.type = TextMappers.char) & (s.char = ",") THEN s.Scan END
						END
					END;
					s.Scan
				END;
				IF t # NIL THEN
					Do(t, StdLog.text, 0, opts, error)
				END
			END
		ELSE Dialog.ShowMsg("#Dev:NotOnlyFileNames")
		END;
		s.ConnectTo(NIL);
		IF error & (c # NIL) & c.HasSelection() & (s.start < end) THEN
			c.SetSelection(s.start, end)
		END;
		IF error & (v # NIL) THEN
			Views.Open(v, loc, name, NIL);
			DevMarkers.ShowFirstError(t, TextViews.any)
		END
	END CompileList;

	PROCEDURE CompileModuleList*;
		VAR c: TextControllers.Controller; beg, end: INTEGER;
	BEGIN
		Open;
		c := TextControllers.Focus();
		IF c # NIL THEN
			s.ConnectTo(c.text);
			IF c.HasSelection() THEN c.GetSelection(beg, end)
			ELSE beg := 0; end := c.text.Length()
			END;
			CompileList(beg, end, c)
		ELSE Dialog.ShowMsg("#Dev:NoTextViewFound")
		END;
		Close
	END CompileModuleList;

	PROCEDURE CompileThis*;
		VAR p: DevCommanders.Par; beg, end: INTEGER;
	BEGIN
		Open;
		p := DevCommanders.par;
		IF p # NIL THEN
			DevCommanders.par := NIL;
			s.ConnectTo(p.text); beg := p.beg; end := p.end;
			CompileList(beg, end, NIL)
		ELSE Dialog.ShowMsg("#Dev:NoTextViewFound")
		END;
		Close
	END CompileThis;

	PROCEDURE ContainsName(list: NameNode; IN name: ARRAY OF CHAR): BOOLEAN;
	BEGIN
		WHILE (list # NIL) & (list.name^ # name) DO list := list.next END;
		RETURN list # NIL
	END ContainsName;
	
	PROCEDURE NewName(IN name: ARRAY OF CHAR): NameNode;
		VAR n: NameNode;
	BEGIN NEW(n); NEW(n.name, LEN(name$) + 1); n.name^ := name$; RETURN n
	END NewName;
	
	PROCEDURE AppendName(VAR list: NameNode; IN name: ARRAY OF CHAR);
		VAR n, last: NameNode;
	BEGIN
		n := NewName(name);
		IF list = NIL THEN list := n
		ELSE last := list; WHILE last.next # NIL DO last := last.next END; last.next := n
		END
	END AppendName;

	PROCEDURE CheckSym(VAR sym: BYTE; expected: SHORTINT);
	BEGIN
		IF sym = expected THEN DevCPS.Get(sym) ELSE DevCPM.err(expected) END
	END CheckSym;

	PROCEDURE SplitName(name: ARRAY OF CHAR; VAR head, tail: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch, lch: CHAR;
	BEGIN
		ASSERT(name # "");
		i := 0; ch := name[0];
		REPEAT
			head[i] := ch; lch := ch; INC(i); ch := name[i]
		UNTIL (ch = 0X) OR Strings.IsUpper(ch) & ~Strings.IsUpper(lch);
		head[i] := 0X; j := 0;
		WHILE ch # 0X DO tail[j] := ch; INC(i); INC(j); ch := name[i] END;
		tail[j] := 0X;
		IF tail = "" THEN tail := head$; head := "System" END
	END SplitName;

	PROCEDURE MakeFile(subList, importPath: NameNode; VAR fileList: NameNode;
										loc: Files.Locator; IN sub, file: ARRAY OF CHAR);
		VAR v: Views.View; source: TextModels.Model; sym: BYTE;
			fileName, impName: Files.Name; importList: NameNode;
			impNameUtf8: DevCPT.Name; res: INTEGER; p: NameNode;

		PROCEDURE ProcessFile;
			VAR import: NameNode; impSub, impFile: Files.Name;
		BEGIN
			p := NewName(fileName); p.next := importPath; importPath := p; (* push *)
			import := importList;
			WHILE import # NIL DO
				SplitName(import.name, impSub, impFile);
				IF ContainsName(subList, impSub) & ~ContainsName(fileList, import.name) THEN
					MakeFile(subList, importPath, fileList, Files.dir.This(impSub + "/Mod"), impSub, impFile)
				END;
				import := import.next
			END;
			IF ~ContainsName(fileList, fileName) THEN
				AppendName(fileList, fileName)
			END;
		END ProcessFile;
		
		PROCEDURE Terminate;
		BEGIN
			DevCPM.InsertMarks(source); Views.Open(v, loc, file$, NIL);
			DevMarkers.ShowFirstError(source, TextViews.any); DevCPM.Close;
			HALT(128) (* silent halt *)
		END Terminate;

	BEGIN
		IF sub # "System" THEN fileName := sub + file ELSE fileName := file$ END;
		v := Views.OldView(loc, file$);
		IF v # NIL THEN
			WITH v: TextViews.View DO
				source := v.ThisModel();
				DevCPM.Init(source.NewReader(NIL), StdLog.text); DevCPS.Init;
				DevCPS.Get(sym);
				IF sym = moduleSym THEN DevCPS.Get(sym);
					IF sym = ident THEN
						DevCPS.Get(sym);
						IF sym = lbrak THEN
							REPEAT DevCPS.Get(sym) UNTIL (sym = rbrak) OR (sym = eof);
							CheckSym(sym, rbrak)
						END;
						CheckSym(sym, semicolon);
						p := NewName(fileName); p.next := importPath; importPath := p; (* push *)
						importList := NIL;  (* compiler cannot be invoked recursively; therefore we use an auxiliary list *)
						IF sym = import THEN DevCPS.Get(sym);
							LOOP
								IF sym = ident THEN
									impNameUtf8 := DevCPS.name$; DevCPS.Get(sym);
									IF sym = becomes THEN DevCPS.Get(sym);
										IF sym = ident THEN impNameUtf8 := DevCPS.name$; DevCPS.Get(sym);
										ELSE DevCPM.err(ident)
										END
									END;
									Strings.Utf8ToString(impNameUtf8, impName, res); ASSERT(res = 0);
									IF ContainsName(importPath, impName) THEN
										DevCPM.err(154)
									ELSIF (impName # "SYSTEM") & (impName # "COM") THEN
										AppendName(importList, impName)
									END
								ELSE DevCPM.err(ident)
								END;
								IF sym = comma THEN DevCPS.Get(sym)
								ELSIF sym = ident THEN DevCPM.err(comma)
								ELSE EXIT
								END
							END; (* LOOP *)
							CheckSym(sym, semicolon)
						END
					ELSE DevCPM.err(ident)
					END;
					IF DevCPM.noerr THEN ProcessFile; importPath := importPath.next (* pop *) ELSE Terminate END
				(* ELSE ignore non module texts *)
				END
			(* ELSE ignore non text files *)
			END
		ELSE Dialog.ShowParamMsg("#Dev:SourcefileNotFound", fileName, "", "");
			AppendName(fileList, fileName); (* report missing module only once *)
		END
	END MakeFile;

	PROCEDURE MakeSubsystem(subList: NameNode; VAR fileList: NameNode;
												IN sub: ARRAY OF CHAR);
		VAR loc: Files.Locator; files: Files.FileInfo; importPath: NameNode;
	BEGIN
		loc := Files.dir.This(sub + "/Mod");
		files := Files.dir.FileList(loc);
		WHILE files # NIL DO
			IF files.type = Files.docType THEN
				files.name[LEN(files.name$) -4] := 0X; (* strip off extension, note: file name may differ from module name *)
				importPath := NIL; MakeFile(subList, importPath, fileList, loc, sub, files.name)
			(* ELSE ignore e.g. temporary files *)
			END;
			files := files.next
		END
	END MakeSubsystem;

	PROCEDURE AppendSubs(VAR subList: NameNode; IN excl: ARRAY OF CHAR);
		VAR dirs: Files.LocInfo; i, pos: INTEGER;
	BEGIN
		dirs := Files.dir.LocList(Files.dir.This(""));
		WHILE dirs # NIL DO (* check first if this directory name is a possible subsystem *)
			IF Strings.IsIdentStart(dirs.name[0]) THEN i := 1;
				WHILE Strings.IsIdent(dirs.name[i]) DO INC(i) END;
				IF dirs.name[i] = 0X THEN
					Strings.Find(excl, ":" + dirs.name + ":", 0, pos);
					IF pos < 0 THEN AppendName(subList, dirs.name) END
				END
			END;
			dirs := dirs.next
		END
	END AppendSubs;

	(* uses the compiler for analyzing module headers; terminates command in case of syntax error *)
	PROCEDURE MakeSubsystems(OUT subList: NameNode; OUT fileList: NameNode);
		CONST
			noneSubs = ":Code:Docu:Sym:";
			baseSubs = ":Com:Comm:Ctl:Dev:Form:Host:Obx:Ole:Sql:Std:System:Text:Win:Xhtml:";
		VAR par: DevCommanders.Par; beg, end: INTEGER; s: TextMappers.Scanner;
			sub: NameNode;
	BEGIN
		par := DevCommanders.par; subList := NIL; fileList := NIL;
		IF par # NIL THEN
			DevCommanders.par := NIL;
			s.ConnectTo(par.text); beg := par.beg; end := par.end;
			s.SetPos(beg); s.Scan;
			WHILE (s.start < end)
			& ((s.type = TextMappers.string) OR (s.type = TextMappers.char) & ((s.char = "+") OR (s.char = "*")))  DO
				IF s.type = TextMappers.string THEN AppendName(subList, s.string)
				ELSIF s.char = "+" THEN AppendSubs(subList, baseSubs + noneSubs)
				ELSIF s.char = "*" THEN AppendSubs(subList, noneSubs)
				END;
				s.Scan;
			END;
			sub := subList;
			WHILE sub # NIL DO
				MakeSubsystem(subList, fileList, sub.name);
				sub := sub.next
			END;
			DevCPM.Close
		ELSE Dialog.ShowMsg("#Dev:NoTextViewFound")
		END
	END MakeSubsystems;

	PROCEDURE MakeList*;
		VAR subList: NameNode (* in textual order *); fileList: NameNode; (* in compile order *)
			t: TextModels.Model; f: TextMappers.Formatter; v: TextViews.View;
			file: NameNode; title: Views.Title; sub: NameNode; pos: INTEGER;
	BEGIN
		MakeSubsystems(subList, fileList);
		t := TextModels.dir.New();
		f.ConnectTo(t);
		file := fileList;
		WHILE file # NIL DO f.WriteString(file.name); f.WriteLn; file := file.next END;
		v := TextViews.dir.New(t);
		Dialog.MapString("#Dev:MakeList", title);
		sub := subList;
		WHILE (sub # NIL) & (LEN(title + " " + sub.name) < LEN(title)) DO
			title := title + " " + sub.name; sub := sub.next
		END;
		IF sub # NIL THEN pos := MIN(LEN(Views.Title) - 4, LEN(title$));
			title[pos] := "."; title[pos + 1] := "."; title[pos + 2] := "."; title[pos + 3] := 0X
		END;
		Views.OpenAux(v, title$)
	END MakeList;

	PROCEDURE CompileSubs*;
		VAR subList: NameNode (* in textual order *); fileList: NameNode; (* in compile order *)
			file: NameNode; loc: Files.Locator; name: Files.Name;
			v: Views.View; t: TextModels.Model; error: BOOLEAN;
	BEGIN
		MakeSubsystems(subList, fileList);
		file := fileList;
		WHILE file # NIL DO
			StdDialog.GetSubLoc(file.name, "Mod", loc, name);
			v := Views.OldView(loc, name);
			IF (v # NIL) & (v IS TextViews.View) THEN
				t := v(TextViews.View).ThisModel();
				Do(t, StdLog.text, 0, defopt, error);
				IF error THEN Views.Open(v, loc, name, NIL);
					DevMarkers.ShowFirstError(t, TextViews.any);
					RETURN
				END
			END;
			file := file.next
		END
	END CompileSubs;

	PROCEDURE Init;
		VAR loc: Files.Locator; f: Files.File;
	BEGIN
		loc := Files.dir.This("Dev"); loc := loc.This("Code");
		f := Files.dir.Old(loc, "ComDebug.ocf", TRUE);
		found := f # NIL;
		IF f # NIL THEN f.Close END
	END Init;

BEGIN
	Init
END DevCompiler.
