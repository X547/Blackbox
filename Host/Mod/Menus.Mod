MODULE HostMenus;
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

	IMPORT Log, Services,
		SYSTEM, KERNEL32, GDI32, USER32, SHELL32, WinApi, Kernel,
		Fonts, Files, Strings, Ports, Stores, Properties, Printers, Dialog,
		Models, Views, Controllers, Containers, Converters,
		Documents, Windows, Controls,
		StdDialog, StdInterpreter, StdCmds, HostFonts, HostPorts, 
		HostFiles, HostWindows, HostDialog, HostClipboard, HostCmds, HostCFrames;

	CONST
		debug = FALSE;
		
		idlePeriod = 50; (* ms *)
		gcCycle = 100;
		titleLen = 64;

		(* hints *)
		impAll = 0;	(* can import all file types *)
		expDoc = 1;	(* imported view should be stored as document *)

		HYPHEN = 90X; NBHYPHEN = 91X; SOFTHYPHEN = 0ADX;
		NBSPACE = 0A0X; NUMSPACE = 8FX;

		iClose = 100; (* known in HostWindows *)
		iUndo = 112; iCut = 114; iCopy = 115; iPaste = 116;
		iObject = 120; iPopup = 160; iProperties = 163;
		iObjEdit = 161; iObjOpen = 162; iVerb0 = 200;
		iOpen = 102; iUpdateMenus = 111; iExit = 110;

		(* custom menus *)
		firstId = 300;
		
		(* apllication states *)
		running = 0; hidden = 1; embedded = 2; noAppWin = 3;
		
		(* File for specifying command line options *)
		cmdLinePath = "System/Rsrc"; cmdLineFile = "CommandLine.txt";
		

	TYPE
		Item* = POINTER TO RECORD (StdDialog.Item)
			id-, code-: INTEGER;
			shift-, ctrl-, del: BOOLEAN
		END;

		Menu* = POINTER TO RECORD
			next-: Menu;
			menu-, type-: Dialog.String;
			firstItem-, lastItem: Item;
			menuH-: USER32.Handle;
			isWinMenu-: BOOLEAN;
			isPopup-: BOOLEAN;
			class-: INTEGER;
			hot, maxId: INTEGER
		END;
		
		TypeMsg* = EXTENSIBLE RECORD (Properties.Message)
			type*: ARRAY 64 OF CHAR	(** OUT, preset to "" **)
		END;
		

	VAR
		(* active menu bar state *)
		menus-: Menu;
		menuBar-: USER32.Handle;
		lastId-: INTEGER;	(* last custom menu id *)
		
		disablePipe*: BOOLEAN;
		
		winMenu, popMenu: USER32.Handle;
		type: Stores.TypeName;

		(* new menu bar state *)
		newMenuBar, newWinMenu, newPopMenu: USER32.Handle;
		nextId: INTEGER;	(* id of next menu item *)
		firstMenu, lastMenu, curMenu: Menu;
		
		gc: INTEGER;	(* how many events must be executed before next GC *)
		defMenu: USER32.Handle;	(* default menu *)
		objMenu: USER32.Handle;	(* object menu (verbs) *)
		shiftStr, ctrlStr, spaceStr: Dialog.String;
		minusCode: INTEGER;	(* key code for "-" *)
		num: INTEGER;
		msgId: INTEGER;
		
		locks-: INTEGER;
		state: INTEGER;
		
		openUsed: BOOLEAN;
		openParam: ARRAY 256 OF SHORTCHAR;
		
		isCont*, isObj*: BOOLEAN;
		
		UpdateOleMenus*: PROCEDURE;
		TranslateOleKeys1*: PROCEDURE (VAR msg: WinApi.MSG; VAR done: BOOLEAN);
		TranslateOleKeys2*: PROCEDURE (VAR msg: WinApi.MSG; VAR done: BOOLEAN);
		

	PROCEDURE [1] FINIT 0DBH, 0E3H;
	PROCEDURE [1] FCLEX 0DBH, 0E2H;
	PROCEDURE [1] FLDCW 0D9H, 06DH, 0FCH;	(* -4, FP *)
	PROCEDURE [1] FSTCW 0D9H, 07DH, 0FCH;	(* -4, FP *)
	PROCEDURE [1] FSTSW 0DDH, 07DH, 0FCH;	(* -4, FP *)
	
	PROCEDURE CheckFpu;
		VAR cw: SET;
	BEGIN
		FSTCW;
		IF cw * {0..5, 8..11} # {1, 2, 3, 4, 5, 8, 9} THEN
			cw := cw - {0..5, 8..11} + {1, 2, 3, 4, 5, 8, 9};
			FCLEX; FLDCW
		END
	END CheckFpu;
	

	PROCEDURE Collect*;
	BEGIN
		gc := 0
	END Collect;


	(* hidden application support *)
	
	PROCEDURE Lock*;
	BEGIN
		INC(locks);
		IF state = embedded THEN state := hidden END
	END Lock;
	
	PROCEDURE Unlock*;
		VAR res: INTEGER;
	BEGIN
		DEC(locks);
		IF (state = hidden) & (locks = 0) THEN
			HostClipboard.Flush;
			res := USER32.DestroyWindow(HostWindows.main)
		END
	END Unlock;
	

	(* shortcut support *)

	PROCEDURE Append (VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR);	(* a := a + b *)
		VAR i, j: INTEGER;
	BEGIN
		i := 0; j := 0;
		WHILE a[i] # 0X DO INC(i) END;
		WHILE b[j] # 0X DO a[i] := b[j]; INC(i); INC(j) END;
		a[i] := 0X
	END Append;
	
	PROCEDURE SetShortcut (VAR i: Item; VAR name: Dialog.String);
		VAR j, n: INTEGER; ch, nch: CHAR; a: ARRAY 4 OF CHAR;
	BEGIN
		i.shift := FALSE; i.ctrl := FALSE; i.code := 0; j := 0; ch := i.shortcut[0];
		WHILE (ch # 0X) & (i.code = 0) DO INC(j);
			IF (ch >= "a") & (ch <= "z") THEN ch := CAP(ch) END;
			nch := i.shortcut[j];
			IF ch = "*" THEN i.shift := TRUE
			ELSIF ch = "^" THEN i.ctrl := TRUE
			ELSIF (ch >= "A") & (ch <= "Z") OR (ch >= "0") & (ch <= "9") OR (ch = " ") THEN
				IF (nch >= "a") & (nch <= "z") THEN nch := CAP(nch) END;
				IF nch = 0X THEN i.code := ORD(ch); i.ctrl := TRUE
				ELSIF ch = "F" THEN
					n := 0;
					WHILE (nch >= "0") & (nch <= "9") DO
						n := 10 * n + ORD(nch) - ORD("0"); INC(j); nch := i.shortcut[j]
					END;
					IF (n >= 1) & (n <= 16) THEN i.code := 70H - 1 + n END
				END
			END;
			ch := nch
		END;
		IF i.code # 0 THEN
			Append(name, "	");	(* tab *)
			IF i.shift THEN Append(name, shiftStr) END;
			IF i.ctrl THEN Append(name, ctrlStr) END;
			IF i.code >= 70H THEN
				a[0] := "F"; n := i.code - 70H + 1; j := 1;
				IF n > 9 THEN a[1] := "1"; DEC(n, 10); INC(j) END;
				a[j] := CHR(n + ORD("0")); a[j+1] := 0X;
				Append(name, a)
			ELSIF i.code = ORD(" ") THEN Append(name, spaceStr)
			ELSE a[0] := CHR(i.code); a[1] := 0X; Append(name, a)
			END
		END
	END SetShortcut;
	
	(* hotkey support *)

	PROCEDURE NextWord (VAR name: Dialog.String; i: INTEGER): INTEGER;
	BEGIN
		WHILE (name[i] # 0X) & (name[i] # " ") DO INC(i) END;
		WHILE name[i] = " " DO INC(i) END;
		IF (CAP(name[i]) < "A") OR (CAP(name[i]) > "Z") THEN i := -1 END;
		RETURN i
	END NextWord;
	
	PROCEDURE SetHotkey (VAR name: Dialog.String; i: INTEGER);
		VAR j: INTEGER;
	BEGIN
		IF name[i] # "&" THEN
			j := i;
			WHILE name[j] # 0X DO INC(j) END;
			WHILE j >= i DO name[j+1] := name[j]; DEC(j) END;
			name[i] := "&"
		END
	END SetHotkey;
	
	PROCEDURE GetHotkey (VAR name: Dialog.String; VAR pos: INTEGER; VAR used: SET);
		VAR i: INTEGER; ch: CHAR;
	BEGIN
		i := 0; ch := name[0];
		WHILE ch # 0X DO
			IF ch = "&" THEN
				ch := name[i + 1];
				IF ch = "&" THEN INC(i)
				ELSE
					pos := i; ch := CAP(ch);
					IF (ch >= "A") & (ch <= "Z") THEN INCL(used, ORD(ch) - ORD("A")) END;
					RETURN 
				END
			END;
			INC(i); ch := name[i]
		END;
		pos := -1
	END GetHotkey;
	
	PROCEDURE FirstFree (VAR name: Dialog.String; VAR used: SET): INTEGER;
		VAR i: INTEGER; ch: CHAR;
	BEGIN
		i := 0; ch := CAP(name[0]);
		WHILE (name[i] # 0X) & ((ch < "A") OR (ch > "Z") OR (ORD(ch) - ORD("A") IN used)) DO
			INC(i); ch := CAP(name[i])
		END;
		IF ch # 0X THEN INCL(used, ORD(ch) - ORD("A"))
		ELSE i := -1
		END;
		RETURN i
	END FirstFree;

	PROCEDURE SetHotkeys (VAR tab: ARRAY OF Dialog.String; n: INTEGER);
		VAR i, j: INTEGER; ch: CHAR; pos: POINTER TO ARRAY OF INTEGER; used: SET;
	BEGIN
		NEW(pos, LEN(tab));
		used := {}; i := 0;
		WHILE i < n DO GetHotkey(tab[i], pos[i], used); INC(i) END;
		i := 0;
		WHILE i < n DO
			IF pos[i] = -1 THEN
				ch := CAP(tab[i, 0]);
				IF (ch >= "A") & (ch <= "Z") & ~(ORD(ch) - ORD("A") IN used) THEN
					INCL(used, ORD(ch) - ORD("A"));
					pos[i] := 0
				END
			END;
			INC(i)
		END;
		i := 0;
		WHILE i < n DO
			IF pos[i] = -1 THEN
				j := NextWord(tab[i], 0);
				WHILE j >= 0 DO
					ch := CAP(tab[i, j]);
					IF ~(ORD(ch) - ORD("A") IN used) THEN
						INCL(used, ORD(ch) - ORD("A"));
						pos[i] := j; j := -1
					ELSE
						j := NextWord(tab[i], j)
					END
				END
			END;
			INC(i)
		END;
		i := 0;
		WHILE i < n DO
			IF pos[i] = -1 THEN pos[i] := FirstFree(tab[i], used) END;
			IF pos[i] >= 0 THEN SetHotkey(tab[i], pos[i]) END;
			INC(i)
		END
	END SetHotkeys;
	
	PROCEDURE UpdateHotkey (VAR old, new: Dialog.String);
		VAR i, j: INTEGER; used: SET; ch: CHAR;
	BEGIN
		GetHotkey(new, i, used);
		IF i = -1 THEN
			used := {}; GetHotkey(old, i, used);
			IF used # {} THEN
				used := -used; i := -1; j := 0;
				WHILE j >= 0 DO
					ch := CAP(new[j]);
					IF ~(ORD(ch) - ORD("A") IN used) THEN
						i := j; j := -1
					ELSE
						j := NextWord(new, j)
					END
				END;
				IF i = -1 THEN i := FirstFree(new, used) END;
				IF i >= 0 THEN SetHotkey(new, i) END
			END
		END
	END UpdateHotkey;
	

	(* custom menus *)
	
	PROCEDURE AppendMenu (menu: USER32.Handle; id: INTEGER; name: Dialog.String);
		VAR res: INTEGER; ss: ARRAY 256 OF SHORTCHAR;
	BEGIN
		Dialog.MapString(name, name); ss := SHORT(name$);
		res := USER32.AppendMenuA(menu, {}, id, ss)
	END AppendMenu;

	PROCEDURE FirstMenu* (): Menu;
	BEGIN
		RETURN menus
	END FirstMenu;

	PROCEDURE DeleteAll*;
	BEGIN
		WHILE USER32.RemoveMenu(menuBar, 0, {USER32.MFByPosition}) # 0 DO END;
		firstMenu := NIL; lastMenu := NIL; curMenu := NIL;
		newWinMenu := 0; newPopMenu := 0;
		nextId := firstId
	END DeleteAll;

	PROCEDURE Open* (menu, type: ARRAY OF CHAR);
	BEGIN
		ASSERT(curMenu = NIL, 20); ASSERT(menu # "", 21);
		NEW(curMenu); curMenu.next := NIL;
		curMenu.menuH := USER32.CreatePopupMenu();
		(* curMenu.menu := menu$; *)
		Dialog.MapString(menu, curMenu.menu);
		curMenu.type := type$;
		curMenu.firstItem := NIL
	END Open;
	
	PROCEDURE AddItem* (item, string, shortcut, filter: Dialog.String);
		VAR i: Item; id: INTEGER;
	BEGIN
		ASSERT(curMenu # NIL, 20); ASSERT(item # "", 21); ASSERT(string # "", 22);
		IF string = "HostMenus.WindowList" THEN
			curMenu.isWinMenu := TRUE
		ELSE
			NEW(i); i.next := NIL;
			IF curMenu.lastItem = NIL THEN curMenu.firstItem := i ELSE curMenu.lastItem.next := i END;
			curMenu.lastItem := i;
			StdDialog.AddItem(i, item, string, filter, shortcut);
			IF string = "HostMenus.ObjectMenu" THEN id := iObject
			ELSE id := nextId; INC(nextId)
			END;
			i.id := id;
			IF id > curMenu.maxId THEN curMenu.maxId := id END
		END
	END AddItem;

	PROCEDURE ChangeItem (m: Menu; i: Item; VAR name: Dialog.String);
		VAR res: INTEGER; old: Dialog.String; so: ARRAY 256 OF SHORTCHAR;
	BEGIN
		res := USER32.GetMenuStringA(m.menuH, i.id, so, LEN(old), {}); old := so$;
		UpdateHotkey(old, name);
		SetShortcut(i, name)
	END ChangeItem;

	PROCEDURE AddSeparator*;
		VAR i: Item;
	BEGIN
		ASSERT(curMenu # NIL, 20);
		NEW(i); i.next := NIL;
		IF curMenu.lastItem = NIL THEN curMenu.firstItem := i ELSE curMenu.lastItem.next := i END;
		curMenu.lastItem := i;
		StdDialog.AddItem(i, "", "", "", "");
		i.id := 0
	END AddSeparator;
	
	PROCEDURE Close*;
		VAR res, j, n: INTEGER; i: StdDialog.Item;
			tab: POINTER TO ARRAY OF Dialog.String; ss: ARRAY 256 OF SHORTCHAR;
	BEGIN
		ASSERT(curMenu # NIL, 20);
		i := curMenu.firstItem; n := 0;
		WHILE i # NIL DO i := i.next; INC(n) END;
		NEW(tab, n);
		i := curMenu.firstItem; j := 0;
		WHILE i # NIL DO Dialog.MapString(i.item, tab[j]); (* tab[j] := i.item^$; *)i := i.next; INC(j) END;
		SetHotkeys(tab, j);
		i := curMenu.firstItem; j := 0;
		WHILE i # NIL DO
			WITH i: Item DO
				IF i.item^ # "" THEN
					SetShortcut(i, tab[j]); ss := SHORT(tab[j]$);
					IF i.id = iObject THEN
						res := USER32.AppendMenuA(curMenu.menuH, {USER32.MFPopup}, objMenu, ss)
					ELSE
						res := USER32.AppendMenuA(curMenu.menuH, {}, i.id, ss)
					END
				ELSIF i.next # NIL THEN
					res := USER32.AppendMenuA(curMenu.menuH, {USER32.MFSeparator}, 0, NIL)
				END
			END;
			i := i.next; INC(j)
		END;
		IF curMenu.menu = "*" THEN curMenu.isPopup := TRUE END;
		IF curMenu.type = "WindowMenu" THEN curMenu.isWinMenu := TRUE; curMenu.type := "" END;
		IF curMenu.isWinMenu THEN newWinMenu := curMenu.menuH
		ELSIF curMenu.type = "PopupMenu" THEN newPopMenu := curMenu.menuH
		END;
		IF lastMenu = NIL THEN firstMenu := curMenu ELSE lastMenu.next := curMenu END;
		lastMenu := curMenu; curMenu := NIL
	END Close;

	PROCEDURE InitMenus*;
		VAR m, n, old: Menu; res, i: INTEGER; used, u: SET; tp: Stores.TypeName; oldBar: USER32.Handle;
			ss: ARRAY 256 OF SHORTCHAR;
	BEGIN
		ASSERT(curMenu = NIL, 20);
		IF firstMenu # NIL THEN
			used := {}; m := firstMenu;
			WHILE m # NIL DO GetHotkey(m.menu, m.hot, used); m := m.next END;
			m := firstMenu; i := 0;
			WHILE m # NIL DO
				IF (m.hot = -1) & (m.type = "") THEN m.hot := FirstFree(m.menu, used) END;
				IF m.isWinMenu THEN m.class := 4; i := 100
				ELSIF m.isPopup THEN m.class := 10
				ELSIF i = 0 THEN m.class := 0
				ELSIF i < 3 THEN m.class := 1
				ELSIF i < 100 THEN m.class := 3
				ELSE m.class := 5
				END;
				m := m.next; INC(i)
			END;
			m := firstMenu;
			WHILE m # NIL DO
				IF m.hot = -1 THEN
					tp := m.type$; u := used; n := m;
					WHILE n # NIL DO
						IF (n.hot = -1) & (n.type = tp) THEN n.hot := FirstFree(n.menu, u) END;
						n := n.next
					END
				END;
				IF m.hot >= 0 THEN SetHotkey(m.menu, m.hot) END;
				m := m.next
			END;
			newMenuBar := USER32.CreateMenu();
			m := firstMenu;
			WHILE m # NIL DO
				IF ((m.type = "") OR (m.type = type)) & ~m.isPopup THEN
					ss := SHORT(m.menu$);
					res := USER32.AppendMenuA(newMenuBar, {USER32.MFPopup}, m.menuH, ss)
				END;
				m := m.next
			END;
			oldBar := menuBar; menuBar := newMenuBar;
			winMenu := newWinMenu; popMenu := newPopMenu;
			old := menus; menus := firstMenu; lastId := nextId;
			IF UpdateOleMenus # NIL THEN UpdateOleMenus() END;
			res := USER32.SendMessageA(HostWindows.client, USER32.WMMDISetMenu, menuBar, winMenu);
			IF res # 0 THEN
				res := USER32.DrawMenuBar(HostWindows.main);
				m := old;
				WHILE m # NIL DO	(* prevent submenus from being deleted *)
					WHILE USER32.RemoveMenu(m.menuH, 0, {USER32.MFByPosition}) # 0 DO END;
					res := USER32.DestroyMenu(m.menuH);
					m := m.next
				END;
				res := USER32.DestroyMenu(oldBar)
			END
		END
	END InitMenus;
	

	(* Menu Dispatching *)

	PROCEDURE Cascade*;
		VAR res: INTEGER;
	BEGIN
		res := USER32.SendMessageA(HostWindows.client, USER32.WMMDICascade, 2, 0)
	END Cascade;
	
	PROCEDURE TileHorizontal*;
		VAR res: INTEGER;
	BEGIN
		res := USER32.SendMessageA(HostWindows.client, USER32.WMMDITile, 3, 0)
	END TileHorizontal;
	
	PROCEDURE TileVertical*;
		VAR res: INTEGER;
	BEGIN
		res := USER32.SendMessageA(HostWindows.client, USER32.WMMDITile, 2, 0)
	END TileVertical;
	
	PROCEDURE ArrangeIcons*;
		VAR res: INTEGER;
	BEGIN
		res := USER32.SendMessageA(HostWindows.client, USER32.WMMDIIconArrange, 0, 0)
	END ArrangeIcons;
	
	
	PROCEDURE Exit*;
		VAR res: INTEGER;
	BEGIN
		res := USER32.SendMessageA(HostWindows.main, USER32.WMClose, 0, 0)
	END Exit;
	

	PROCEDURE SetFocus;
		VAR c: Containers.Controller; f: Views.Frame; v, s: Views.View;
	BEGIN
		f := Controllers.FocusFrame(); v := f.view;
		WITH v: Containers.View DO
			c := v.ThisController();
			s := c.Singleton();
			IF s # NIL THEN c.SetFocus(s) END
		ELSE
		END
	END SetFocus;
	
	PROCEDURE OpenWindow;
		VAR c: Containers.Controller; f: Views.Frame; v, s: Views.View; doc: Documents.Document;
			win: Windows.Window; title: Views.Title;
	BEGIN
		f := Controllers.FocusFrame(); v := f.view;
		WITH v: Containers.View DO
			c := v.ThisController();
			s := c.Singleton();
			IF (s # NIL) & (s.ThisModel() # NIL) THEN
				win := Windows.dir.Focus(Controllers.frontPath); ASSERT(win # NIL, 100);
				doc := win.doc.DocCopyOf(s);
				c := doc.ThisController();
				c.SetOpts(c.opts - {Documents.pageWidth, Documents.pageHeight}
										+ {Documents.winWidth, Documents.winHeight});
				(* Stores.InitDomain(doc, v.domain); done by DocCopyOf *)
				win.GetTitle(title);
				Windows.dir.OpenSubWindow(Windows.dir.New(), doc, {Windows.isAux}, title)
			END
		ELSE
		END
	END OpenWindow;
	
	PROCEDURE HandleVerb (n: INTEGER);
		VAR v: Views.View; dvm: Properties.DoVerbMsg;
	BEGIN
		v := Containers.FocusSingleton();
		IF v # NIL THEN
			dvm.frame := Views.ThisFrame(Controllers.FocusFrame(), v);
			dvm.verb := SHORT(n);
			Views.HandlePropMsg(v, dvm)
		END
	END HandleVerb;
	
	PROCEDURE CheckVerb (v: Views.View; n: INTEGER; VAR pvm: Properties.PollVerbMsg);
	BEGIN
		pvm.verb := SHORT(n);
		pvm.label := "";
		pvm.disabled := FALSE; pvm.checked := FALSE;
		Views.HandlePropMsg(v, pvm)
	END CheckVerb;
	
	PROCEDURE PrimaryVerb*;
		VAR v: Views.View; pvm: Properties.PollVerbMsg;
	BEGIN
		v := Containers.FocusSingleton();
		IF v # NIL THEN
			CheckVerb(v, 0, pvm);
			IF pvm.label # "" THEN HandleVerb(0)
			ELSE  SetFocus
			END
		END
	END PrimaryVerb;
(*	
	PROCEDURE ObjProperties*;
		VAR res: INTEGER; p, q: Properties.Property; s: Views.View;
	BEGIN
		Properties.CollectProp(p);
		s := Containers.FocusSingleton();
		IF s # NIL THEN
			q := p;
			WHILE (q # NIL) & ~(q IS Controls.Prop) DO q := q.next END;
			IF q # NIL THEN
				Dialog.Call(
				"DevInspector.InitDialog; StdCmds.OpenToolDialog('DevInspector.inspect', '#Host:ControlInspector')"
				, "", res);
				IF res = 0 THEN RETURN END
			END
		END;
		q := p;
		WHILE (q # NIL) & ~(q IS Properties.StdProp) DO q := q.next END;
		IF (q # NIL) & (Properties.typeface IN p.known) THEN
			HostDialog.FontDialog
		END
	END ObjProperties;
*)	
	PROCEDURE ObjectMenu*;
	BEGIN
		HALT(127)
	END ObjectMenu;
	
	PROCEDURE WindowList*;
	BEGIN
		HALT(127)
	END WindowList;
(*	
	PROCEDURE PropertiesGuard* (VAR par: Dialog.Par);
		VAR res: INTEGER; p, q: Properties.Property; s: Views.View;
	BEGIN
		Properties.CollectProp(p);
		s := Containers.FocusSingleton();
		IF s # NIL THEN
			q := p;
			WHILE (q # NIL) & ~(q IS Controls.Prop) DO q := q.next END;
			IF q # NIL THEN RETURN END
		END;
		q := p;
		WHILE (q # NIL) & ~(q IS Properties.StdProp) DO q := q.next END;
		IF (q # NIL) & (Properties.typeface IN p.known) THEN RETURN END;
		par.disabled := TRUE
	END PropertiesGuard;
*)	
	PROCEDURE ObjectMenuGuard* (VAR par: Dialog.Par);
		VAR v: Views.View; pvm: Properties.PollVerbMsg; i, id, res: INTEGER; msg: TypeMsg; str: Dialog.String;
	BEGIN
		v := Containers.FocusSingleton();
		IF v # NIL THEN
			(* remove old object menu entries *)
			WHILE USER32.RemoveMenu(objMenu, 0, {USER32.MFByPosition}) # 0 DO END;
			(* insert verbs *)
			i := 0; id := iVerb0;
			CheckVerb(v, 0, pvm);
			IF pvm.label = "" THEN
				AppendMenu(objMenu, iObjEdit, "#Host:Edit");
				AppendMenu(objMenu, iObjOpen, "#Host:Open");
				IF v.ThisModel() = NIL THEN
					res := USER32.EnableMenuItem(objMenu, iObjOpen, {USER32.MFGrayed})
				END;
				INC(i); INC(id);
				CheckVerb(v, i, pvm)
			END;
			WHILE (id < firstId) & (pvm.label # "") DO
				str := pvm.label$;
				AppendMenu(objMenu, id, str);
				IF pvm.disabled THEN res := USER32.EnableMenuItem(objMenu, id, {USER32.MFGrayed}) END;
				IF pvm.checked THEN res := USER32.CheckMenuItem(objMenu, id, {USER32.MFChecked}) END;
				INC(i); INC(id);
				CheckVerb(v, i, pvm)
			END;
			msg.type := "";
			Views.HandlePropMsg(v, msg);
			IF msg.type # "" THEN
				Dialog.MapString("#Host:Object", str);
				par.label := msg.type + " " + str
			ELSE
				Dialog.MapString("#Host:Object", par.label)
			END
		ELSE
			par.disabled := TRUE;
			Dialog.MapString("#Host:Object", par.label)
		END
	END ObjectMenuGuard;

	PROCEDURE PopupMenu*;
		VAR f: Views.Frame; res, x, y: INTEGER; d: BOOLEAN; pt: USER32.Point; m: SET;
			menu: Menu; menuH: USER32.Handle;
	BEGIN
		f := Controllers.FocusFrame();
		IF (f # NIL) & f.front THEN
			menu := menus;
			WHILE (menu # NIL) & (~menu.isPopup OR (menu.type # "") & (menu.type # type)) DO
				menu := menu.next
			END;
			IF menu # NIL THEN menuH := menu.menuH ELSE menuH := popMenu END;
			IF USER32.GetCapture() # 0 THEN f.Input(x, y, m, d)
			ELSE x := (f.l + f.r) DIV 2; y := (f.t + f.b) DIV 2
			END;
			pt.x := (x + f.gx) DIV f.unit; pt.y := (y + f.gy) DIV f.unit;
			res := USER32.ClientToScreen(f.rider(HostPorts.Rider).port.wnd, pt);
			res := USER32.TrackPopupMenu(menuH, {1}, pt.x, pt.y + 2, 0, HostWindows.main, NIL)
		END
	END PopupMenu;
	
	
	(* menu dispatching *)

	PROCEDURE PrepareMenu (wnd, menu: USER32.Handle; lParam: INTEGER);
	(* this procedure is called after the user has clicked into the menu bar, but before
		showing the menu; to prepare item enabling/disabling, check marks, etc. *)
		VAR res, n: INTEGER; failed, ok: BOOLEAN; par: Dialog.Par; m: Menu; i: StdDialog.Item; str: Dialog.String;
			ss: ARRAY 256 OF SHORTCHAR;
	BEGIN
		m := menus;
		WHILE (m # NIL) & (m.menuH # menu) DO m := m.next END;
		IF m # NIL THEN
			i := m.firstItem; n := 0;
			WHILE i # NIL DO
				WITH i: Item DO
					IF i.filter^ # "" THEN	(* custom menu item with custom guard *)
						StdDialog.CheckFilter(i, failed, ok, par);
						IF ~failed THEN
							IF par.label = "-" THEN
								IF ~i.del THEN
									res := USER32.RemoveMenu(m.menuH, n, {USER32.MFByPosition});
									i.del := TRUE
								END;
								DEC(n)
							ELSE
								IF i.del THEN
									res := USER32.InsertMenuA(m.menuH, n, {USER32.MFByPosition}, i.id, "+");
									i.del := FALSE
								END;
								IF par.label # i.item$ THEN
									Dialog.MapString(par.label, str);
									ChangeItem(m, i, str); ss := SHORT(str$);
									IF i.id = iObject THEN
										res := USER32.ModifyMenuA(
											m.menuH, n, {USER32.MFByPosition, USER32.MFPopup}, objMenu, ss)
									ELSE
										res := USER32.ModifyMenuA(m.menuH, n, {USER32.MFByPosition}, i.id, ss)
									END
								END;
								IF par.disabled THEN
									res := USER32.EnableMenuItem(
										m.menuH, n, {USER32.MFByPosition, USER32.MFGrayed})
								ELSE
									res := USER32.EnableMenuItem(m.menuH, n, {USER32.MFByPosition})
								END;
								IF par.checked & ~ODD(USER32.GetMenuState(m.menuH, n, {USER32.MFByPosition}))
								THEN
									res := USER32.CheckMenuItem(
										m.menuH, n, {USER32.MFByPosition, USER32.MFChecked})
								ELSE
									res := USER32.CheckMenuItem(m.menuH, n, {USER32.MFByPosition})
								END;
								IF ~ok THEN
									(* mark with "?" !!! *)
									res := USER32.EnableMenuItem(
										m.menuH, n, {USER32.MFByPosition, USER32.MFGrayed})
								END
							END
						END
					END
				END;
				i := i.next; INC(n)
			END
		END
	END PrepareMenu;
	
	PROCEDURE HandleCustomMenu (id: INTEGER);
		VAR m: Menu; i: StdDialog.Item; 
	BEGIN
		m := menus;
		WHILE (m # NIL) & (m.maxId < id) DO m := m.next END;
		IF m # NIL THEN i := m.firstItem;
			WHILE (i # NIL) & (i(Item).id # id) DO i := i.next END;
			IF i # NIL THEN StdDialog.HandleItem(i) END
		END
	END HandleCustomMenu;

	PROCEDURE MenuCommand (wnd: USER32.Handle; wParam, lParam: INTEGER);
		VAR res, id: INTEGER; old: USER32.Handle;
	BEGIN

		old := USER32.SetCursor(HostPorts.cursors[HostPorts.busyCursor]);
		Dialog.ShowStatus("");

		DEC(gc); id := wParam MOD 65536;
		CASE id OF
		| iClose: HostCmds.Close
		| iUndo: StdCmds.Undo
		| iCut: HostCmds.Cut
		| iCopy: HostCmds.Copy
		| iPaste: HostCmds.Paste
		| iOpen: HostCmds.Open
		| iExit: Exit
		| iUpdateMenus: Dialog.Call("StdMenuTool.UpdateAllMenus", "", res)
		| iPopup: PopupMenu
		| iObjEdit: SetFocus
		| iObjOpen: OpenWindow
		| iProperties: StdCmds.ShowProp
		ELSE
			IF id < firstId THEN HandleVerb(id - iVerb0)
			ELSE
				res := 0;	(* prevent from parasitic anchors on stack *)
				HandleCustomMenu(id)
			END
		END;
		Properties.IncEra;

		old := USER32.SetCursor(old)

	END MenuCommand;
	
	
	PROCEDURE TranslateAccelerators (VAR msg: USER32.Message; filter: SET; VAR done: BOOLEAN);
		VAR m: Menu; i: StdDialog.Item; id, code: INTEGER; ctrl, shift, alt: BOOLEAN; ch: CHAR;
			failed, ok: BOOLEAN; par: Dialog.Par;
	BEGIN
		IF (msg.message = USER32.WMSysKeyDown) OR (msg.message = USER32.WMKeyDown) THEN
			code := msg.wParam; id := 0; ch := 0X;
			shift := USER32.GetKeyState(10H) < 0;
			ctrl := USER32.GetKeyState(11H) < 0;
			alt := ODD(msg.lParam DIV 20000000H);
			IF 1 IN filter THEN
				IF shift & (code = 79H) THEN id := iPopup	(* shift F10 *)
				ELSIF alt THEN
					IF code = 08H THEN id := iUndo	(* alt bs *)
					ELSIF code = 0DH THEN id := iProperties	(* alt enter *)
					ELSIF code = 5DH THEN id := iProperties	(* alt application *)
					ELSIF (code = minusCode) & shift THEN ch := NBHYPHEN
					ELSIF (code = ORD(" ")) & shift THEN ch := NBSPACE
					END
				ELSIF ctrl THEN
					IF code = ORD(" ") THEN
						IF shift THEN ch := NUMSPACE END
					ELSIF code = 2DH THEN
						id := iCopy	(* ctrl insert *)
					ELSIF code = minusCode THEN
						IF shift THEN ch := SOFTHYPHEN ELSE ch := HYPHEN END
					END
				ELSIF shift THEN
					IF code = 2EH THEN id := iCut	(* shift delete *)
					ELSIF code = 2DH THEN id := iPaste	(* shift insert *)
					END
				ELSIF code = 5DH THEN id := iPopup	(* application *)
				ELSIF code = 1BH THEN done := TRUE	(* esc *)
				END
			END;
			IF (id = 0) & ~alt & (ctrl OR (code >= 70H) & (code <= 7FH)) (* function key *) THEN
				m := menus;
				WHILE (m # NIL) & (id = 0) DO
					IF ((m.type = "") OR (m.type = type)) & ~m.isPopup & (m.class IN filter) THEN
						i := m.firstItem;
						WHILE (i # NIL) &
							((i(Item).code # code) OR (i(Item).ctrl # ctrl) OR (i(Item).shift # shift)) DO i := i.next END;
						IF i # NIL THEN
							IF i.filter^ # "" THEN StdDialog.CheckFilter(i, failed, ok , par) END;
							IF (i.filter^ = "") OR ~failed & ~par.disabled THEN id := i(Item).id END
						END
					END;
					m := m.next
				END
			END;
			IF id # 0 THEN
				msg.message := USER32.WMCommand; msg.wParam := id + 65536;
				msg.wnd := HostWindows.main; msg.lParam := 0; done := TRUE
			ELSIF ch # 0X THEN
				msg.message := USER32.WMChar; msg.wParam := ORD(ch); done := TRUE
			END
		END
	END TranslateAccelerators;


	PROCEDURE OpenFile (VAR name: ARRAY OF SHORTCHAR; l, t, r, b: INTEGER; VAR ok: BOOLEAN);
		VAR res: INTEGER; loc: Files.Locator; np: KERNEL32.StringPtr; path: HostFiles.FullName;
			file: Files.Name; v: Views.View; conv: Converters.Converter; f: Files.File;
			sp: ARRAY 260 OF SHORTCHAR;
	BEGIN
		ok := FALSE;
		res := KERNEL32.GetFullPathNameA(name, LEN(path), sp, np);
		IF np # NIL THEN
			file := np^$;
			IF file # "" THEN
				DEC(SYSTEM.VAL(INTEGER, np)); np^[0] := 0X; path := sp$;
				loc := HostFiles.NewLocator(path);
				f := Files.dir.Old(loc, file, Files.shared);
				IF f # NIL THEN
					conv := Converters.list;
					WHILE (conv # NIL) & (conv.fileType # f.type) DO conv := conv.next END;
					IF conv = NIL THEN
						conv := Converters.list;
						WHILE (conv # NIL) & ~(impAll IN conv.opts) DO conv := conv.next END
					END;
					IF f.type = "" THEN file := file + "." END;
					v := Views.Old(Views.dontAsk, loc, file, conv);
					IF v # NIL THEN
						HostWindows.dir.l := l; HostWindows.dir.t := t; HostWindows.dir.r := r; HostWindows.dir.b := b;
						Views.Open(v, loc, file, conv); ok := TRUE;
						HostWindows.dir.l := 0; HostWindows.dir.t := 0; HostWindows.dir.r := 0; HostWindows.dir.b := 0
					END
				END
			END
		END
	END OpenFile;
	
	PROCEDURE IncludingFileCommandLine(
		IN line: ARRAY [untagged] OF SHORTCHAR
	): POINTER TO ARRAY OF SHORTCHAR;
		VAR f: Files.File; r: Files.Reader; i, len: INTEGER; 
			header: ARRAY 12 OF BYTE; keyword: ARRAY 12 OF CHAR;
			b: POINTER TO ARRAY OF BYTE;
			l2: POINTER TO ARRAY OF SHORTCHAR;
	BEGIN
		len := LEN(line$);
		f := Files.dir.Old(Files.dir.This(cmdLinePath), cmdLineFile, Files.shared);
		IF (f # NIL) & (f.Length() > LEN(header)) THEN
			r := f.NewReader(NIL); r.ReadBytes(header, 0, LEN(header));
			FOR i := 0 TO LEN(header) - 1 DO keyword[i] := CHR(header[i]) END;
			keyword[LEN(keyword) - 1] := 0X;
			IF keyword = 'COMMANDLINE' THEN
				NEW(b, f.Length() - LEN(header)); NEW(l2, LEN(b) + len + 1);
				r.ReadBytes(b, 0, LEN(b));
				FOR i := 0 TO len - 1 DO l2[i] := line[i] END; l2[i] := " ";
				FOR i := 0 TO LEN(b) - 1 DO l2[i + len + 1] := SHORT(CHR(b[i])) END;
				RETURN l2
			END
		END;
		NEW(l2, len); 
		FOR i := 0 TO len - 1 DO l2[i] := line[i] END;
		RETURN l2
	END IncludingFileCommandLine;
	
	PROCEDURE ReadCommandLine (IN line: ARRAY [untagged] OF SHORTCHAR; open: BOOLEAN);
		VAR name, opt: ARRAY 260 OF SHORTCHAR; i, l, t, r, b, res: INTEGER;
			ok: BOOLEAN; ln: ARRAY 260 OF CHAR;
		
		PROCEDURE CopyName;
			VAR ch, tch: SHORTCHAR; j: INTEGER;
		BEGIN
			j := 0; ch := line[i]; tch := " ";
			WHILE ch = " " DO INC(i); ch := line[i] END;
			IF (ch = "'") OR (ch = '"') THEN tch := ch; INC(i); ch := line[i] END;
			WHILE (ch >= " ") & (ch # tch) DO
				name[j] := ch;
				IF (ch >= "a") & (ch <= "z") OR (ch >= "à") & (ch <= "ö") OR (ch >= "ø") & (ch <= "þ") THEN ch := CAP(ch)
				ELSIF ch = "-" THEN ch := "/"
				END;
				opt[j] := ch; INC(j); INC(i); ch := line[i]
			END;
			IF ch > " " THEN INC(i); ch := line[i] END;
			WHILE (ch # 0X) & (ch <= " ") DO INC(i); ch := line[i] END;
			name[j] := 0X; opt[j] := 0X
		END CopyName;
		
	BEGIN
		l := 0; t := 0; r := 0; b := 0; i := 0;
		CopyName;	(* skip program name *)
		WHILE line[i] > " " DO
			CopyName;
			IF opt = "/LOAD" THEN	(* load module *)
				CopyName; ln := name$;
				IF open THEN Kernel.LoadMod(ln) END
			ELSIF opt = "/USE" THEN	(* use directory *)
				CopyName	(* working directory: handled in HostFiles *)
			ELSIF opt = "/P" THEN	(* print file *)	(* to be completed !!! *)
				CopyName;
				IF open THEN
					OpenFile(name, 0, 0, 0, 0, ok);
					IF ok THEN HostCmds.Print END
				END
			ELSIF opt = "/PT" THEN	(* print file to printer *)
				CopyName; CopyName; CopyName; CopyName	(* to be completed !!! *)
			ELSIF opt = "/EMBEDDING" THEN	(* start as server *)
				IF ~open THEN state := embedded END
			ELSIF opt = "/NOAPPWIN" THEN	(* start without application window *)
				IF ~open THEN state := noAppWin; HostWindows.noAppWin := TRUE END
			ELSIF opt = "/NOSCROLL" THEN	(* no scroll bars in  application window *)
				HostWindows.noClientScroll := TRUE
			ELSIF opt = "/FULLSIZE" THEN
				HostWindows.fullSize := TRUE
			ELSIF opt = "/LTRB" THEN	(* window position *)
				CopyName; ln := name$; Strings.StringToInt(ln, l, res);
				CopyName; ln := name$; Strings.StringToInt(ln, t, res);
				CopyName; ln := name$; Strings.StringToInt(ln, r, res);
				CopyName; ln := name$; Strings.StringToInt(ln, b, res)
			ELSIF opt = "/LANG" THEN
				CopyName; ln := name$;
				IF LEN(ln$) = 2 THEN Strings.ToLower(ln, ln); Dialog.SetLanguage(ln$, Dialog.nonPersistent) END
			ELSIF opt = "/O" THEN	(* open file *)
				CopyName; openUsed := TRUE;
				IF open THEN OpenFile(name, l, t, r, b, ok) END;
				openParam := '/O "' + name$ + '"';
				l := 0; t := 0; r := 0; b := 0
			ELSIF opt = "/PAR" THEN
				CopyName;
				Dialog.commandLinePars := name$
			ELSE	(* open file *)
				IF open THEN OpenFile(name, l, t, r, b, ok) END;
				l := 0; t := 0; r := 0; b := 0
			END
		END
	END ReadCommandLine;

	PROCEDURE DropFiles (wnd: USER32.Handle; wParam, lParam: INTEGER);
		VAR i, n, res: INTEGER; name: ARRAY 260 OF SHORTCHAR; ok: BOOLEAN;
	BEGIN
		IF state = noAppWin THEN RETURN END;
		n := SHELL32.DragQueryFileA(wParam, -1, name, LEN(name)); i := 0;
		WHILE i < n DO
			res := SHELL32.DragQueryFileA(wParam, i, name, LEN(name));
			OpenFile(name, 0, 0, 0, 0, ok);
			IF ok THEN res := USER32.SetForegroundWindow(HostWindows.main) END;
			INC(i)
		END;
		SHELL32.DragFinish(wParam)
	END DropFiles;


	(* main window handler *)
	
	PROCEDURE Quit (wnd: USER32.Handle; wParam, lParam: INTEGER);
	BEGIN
		HostCmds.Quit
	END Quit;
	
	PROCEDURE UpdateMenus;
		VAR res: INTEGER; m: Menu; old: USER32.Handle; ss: ARRAY 256 OF SHORTCHAR;
	BEGIN
		old := menuBar; menuBar := USER32.CreateMenu();
		m := menus;
		WHILE m # NIL DO
			IF ((m.type = "") OR (m.type = type)) & ~m.isPopup THEN
				ss := SHORT(m.menu$);
				res := USER32.AppendMenuA(menuBar, {USER32.MFPopup},  m.menuH, ss)
			END;
			m := m.next
		END;
		res := USER32.SendMessageA(HostWindows.client, USER32.WMMDISetMenu, menuBar, winMenu);
		res := USER32.DrawMenuBar(HostWindows.main);
		WHILE USER32.RemoveMenu(old, 0, {USER32.MFByPosition}) # 0 DO END;
		res := USER32.DestroyMenu(old)
	END UpdateMenus;

	PROCEDURE TimerTick (wnd: USER32.Handle; wParam, lParam: INTEGER);
		VAR ops: Controllers.PollOpsMsg;
	BEGIN
		IF ~Log.synch THEN Log.FlushBuf END;
		IF ~HostCFrames.inHandleMouse THEN HostWindows.Idle END;
		Controllers.SetCurrentPath(Controllers.targetPath);
		Controllers.PollOps(ops);
		IF (ops.type # type) & (menus # NIL) & (USER32.GetMenu(HostWindows.main) = menuBar) THEN
			type := ops.type$;
			UpdateMenus
		END;
		Controllers.ResetCurrentPath()
	END TimerTick;
	
	PROCEDURE Flush (wnd: USER32.Handle; wParam, lParam: INTEGER);
	BEGIN
		HostClipboard.Flush
	END Flush;
	
	
	PROCEDURE [2] ApplWinHandler (wnd: USER32.Handle; message, wParam, lParam: INTEGER): INTEGER;
		TYPE PPS = POINTER TO USER32.PaintStruct; PR = POINTER TO USER32.Rect;
		VAR res: INTEGER; w: USER32.Handle; r: USER32.Rect; hit: BOOLEAN;
			Proc: PROCEDURE; s: ARRAY 256 OF SHORTCHAR;
	BEGIN
		Controllers.SetCurrentPath(Controllers.targetPath);
		CASE message OF
		| USER32.WMClose, USER32.WMQueryEndSession:
			Kernel.Try(Quit, wnd, wParam, lParam);
			IF HostCmds.quit THEN
				HostWindows.SaveWindowState;
				IF locks = 0 THEN
					Kernel.Try(Flush, wnd, 0, 0)
				ELSE
					state := hidden;
					res := USER32.ShowWindow(HostWindows.main, USER32.SWHide);
					Controllers.ResetCurrentPath();
					RETURN 0
				END
			ELSE gc := 0;
				Controllers.ResetCurrentPath();
				RETURN 0
			END
		| USER32.WMDestroy:
			USER32.PostQuitMessage(0);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMActivate:
			IF debug THEN Log.String("activate hack"); Log.Ln END;
			res := USER32.GetUpdateRect(wnd, r, 1);	(* forces a WMEraseBkGnd msg (fixes bug in Win32s!) *)
			IF wParam MOD 65536 # 0 THEN HostWindows.ActivateMain(TRUE) END
		| USER32.WMNCActivate:
			IF wParam MOD 65536 = 0 THEN HostWindows.ActivateMain(FALSE) END
		| USER32.WMCommand:
			Controllers.SetCurrentPath(Controllers.frontPath);
			(* prevent from parasitic anchors on stack *)
			res := 0; w := 0; r.left := 0; r.top := 0; r.right := 0; r.bottom := 0; hit := FALSE; 
			Kernel.Try(MenuCommand, wnd, wParam, lParam);
			Controllers.ResetCurrentPath()
		| USER32.WMInitMenuPopup:
			Controllers.SetCurrentPath(Controllers.frontPath);
			Kernel.Try(PrepareMenu, wnd, wParam, lParam);
			Controllers.ResetCurrentPath()
(*
		| USER32.WMRenderFormat:
			Kernel.Try(Export, wnd, wParam, 0)
		| USER32.WMRenderAllFormats:
			Kernel.Try(Export, wnd, 0, 0)
		| USER32.WMPaintClipboard:
			pps := SYSTEM.VAL(PPS, KERNEL32.GlobalLock(lParam));
			HostWindows.PaintClipboard(wParam, pps^);
			res := KERNEL32.GlobalUnlock(lParam);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMSizeClipboard:
			pr := SYSTEM.VAL(PR, KERNEL32.GlobalLock(lParam));
			HostWindows.SizeClipboard(wParam, pr.right, pr.bottom);
			res := KERNEL32.GlobalUnlock(lParam);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMHScrollClipboard:
			HostWindows.ScrollClipboard(wParam, lParam MOD 65536, lParam DIV 65536 MOD 65536, FALSE);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMVScrollClipboard:
			HostWindows.ScrollClipboard(wParam, lParam MOD 65536, lParam DIV 65536 MOD 65536, TRUE);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMAskCBFormatName:
			SYSTEM.MOVE(SYSTEM.ADR("BlackBox"), lParam, 9);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMDestroyClipboard:
			HostClipboard.Destroy;
			Controllers.ResetCurrentPath();
			RETURN 0
*)
		| USER32.WMSysColorChange:
			IF HostWindows.ctl3d # 0 THEN
				SYSTEM.PUT(
					SYSTEM.ADR(Proc), KERNEL32.GetProcAddress(HostWindows.ctl3d, "Ctl3dColorChange"));
				IF Proc # NIL THEN Proc() END
			END;
			HostPorts.ResetColors;
			res := GDI32.DeleteObject(HostPorts.dialogBrush);
			HostPorts.dialogBrush := GDI32.CreateSolidBrush(Ports.dialogBackground)
		| USER32.WMDropFiles:
			Kernel.Try(DropFiles, wnd, wParam, lParam);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMTimer:
			Kernel.Try(TimerTick, wnd, wParam, lParam);
			Controllers.ResetCurrentPath();
			RETURN 0
		| USER32.WMSize:
			HostWindows.ResizeMainWindow(wParam, lParam MOD 65536, lParam DIV 65536);
			Controllers.ResetCurrentPath();
			IF HostWindows.mainHook # NIL THEN
				HostWindows.mainHook.Resize(lParam MOD 65536, lParam DIV 65536)
			END;
			RETURN 0
		| USER32.WMSetFocus:
			IF HostWindows.mainHook # NIL THEN HostWindows.mainHook.Focus(TRUE) END
		| USER32.WMKillFocus:
			IF HostWindows.mainHook # NIL THEN HostWindows.mainHook.Focus(FALSE) END
		| USER32.WMActivateApp:
			IF HostWindows.mainHook # NIL THEN HostWindows.mainHook.Activate(wParam # 0) END
		| USER32.WMCtlColorStatic:	(* status bar colors *)
			res := GDI32.SetTextColor(wParam, HostPorts.dialogTextCol);
			res := GDI32.SetBkColor(wParam, Ports.dialogBackground);
			Controllers.ResetCurrentPath();
			RETURN HostPorts.dialogBrush
		ELSE
			IF (message = msgId) & ~disablePipe THEN
				IF (wParam >= 0FFFFC000H) & (wParam < 0) THEN
					HostWindows.ShowMain; state := running;
					IF USER32.IsIconic(HostWindows.main) # 0 THEN
						res := USER32.ShowWindow(HostWindows.main, WinApi.SW_RESTORE)
					END;
					res := WinApi.GlobalGetAtomName(SHORT(wParam), s, LEN(s));
					ReadCommandLine(s, TRUE);
					res := WinApi.GlobalAddAtom("<file_opened>");
					res := WinApi.GlobalDeleteAtom(SHORT(wParam))
				END;
				Controllers.ResetCurrentPath();
				RETURN 0
			END
		END;
		Controllers.ResetCurrentPath();
		RETURN USER32.DefFrameProcA(wnd, HostWindows.client, message, wParam, lParam)
	END ApplWinHandler;


	(* Initialization *)
	
	PROCEDURE CreateDefaultMenu;
		VAR res: INTEGER;
	BEGIN
		defMenu := USER32.CreatePopupMenu();
		res := USER32.AppendMenuA(defMenu, {}, iOpen, "&Open");
		res := USER32.AppendMenuA(defMenu, {}, iUpdateMenus, "&Menu");
		res := USER32.AppendMenuA(defMenu, {USER32.MFSeparator}, 0, NIL);
		res := USER32.AppendMenuA(defMenu, {}, iExit, "E&xit");
		menuBar := USER32.CreateMenu(); winMenu := 0; popMenu := 0;
		res := USER32.AppendMenuA(menuBar, {USER32.MFPopup}, defMenu, "&File")
	END CreateDefaultMenu;
	
	PROCEDURE DestroyMenus;	(* module terminator *)
		VAR res: INTEGER; m: Menu; Proc: PROCEDURE(i: USER32.Handle);
	BEGIN
		m := menus;
		WHILE m # NIL DO
			res := USER32.DestroyMenu(m.menuH);
			m := m.next
		END;
		IF HostWindows.ctl3d # 0 THEN
			SYSTEM.PUT(SYSTEM.ADR(Proc), KERNEL32.GetProcAddress(HostWindows.ctl3d, "Ctl3dUnregister"));
			IF Proc # NIL THEN Proc(KERNEL32.GetModuleHandleA(NIL)) END
		END
	END DestroyMenus;
	

	(* main event loop *)
	
	PROCEDURE Loop;
		VAR res, n: INTEGER; msg: USER32.Message; done: BOOLEAN; f: SET; w: HostWindows.Window;
	BEGIN
		HostWindows.dir.invisible := FALSE;
		IF state = hidden THEN HostWindows.ShowMain; state := running END;
		gc := 0; n := 0;
		WHILE USER32.GetMessageA(msg, 0, 0, 0) # 0 DO
			CheckFpu;
			IF USER32.IsWindowVisible(HostWindows.main) # 0 THEN state := running END;
			done := FALSE;
			IF isCont & (TranslateOleKeys1 # NIL) THEN
				TranslateOleKeys1(SYSTEM.VAL(WinApi.MSG, msg), done)
			END;
			IF ~done & ~isObj THEN
				done := USER32.TranslateMDISysAccel(HostWindows.client, msg) # 0
			END;
			IF ~done THEN
				IF isObj THEN f := {1, 3, 5} ELSIF isCont THEN f := {0, 2, 4} ELSE f := {0..5} END;
				TranslateAccelerators(msg, f, done);
				IF ~done & isObj & (TranslateOleKeys2 # NIL) THEN
					TranslateOleKeys2(SYSTEM.VAL(WinApi.MSG, msg), done)
				ELSE done := FALSE
				END;
				IF ~done THEN
					res := USER32.TranslateMessage(msg);
					res := USER32.DispatchMessageA(msg)
				END;
				Services.actionHook.Loop
			END;
			INC(n);
			IF (n > num) OR (USER32.PeekMessageA(msg, 0, 0, 0, 0) = 0) THEN
				Windows.dir.Update(NIL); n := 0
			END;
			IF state = hidden THEN DEC(gc) END;
			IF ((gc <= 0) OR Kernel.WouldFinalize()) & ~HostCmds.quit THEN
				msg.message := 0; msg.wnd := 0; msg.wParam := 0; msg.lParam := 0;
				msg.time := 0; msg.pt.x := 0; msg.pt.y := 0; res := 0;
				Kernel.Collect; gc := gcCycle
			END;
			IF state = noAppWin THEN
				w := HostWindows.dir.First();
				WHILE (w # NIL) & ~(Windows.isTool IN w.flags) DO w := HostWindows.dir.Next(w) END;
				IF w = NIL THEN Exit ELSE w := NIL END
			END
		END;
		Kernel.Quit(msg.wParam)
		(* never returns *)
	END Loop;
	
	PROCEDURE OpenApp*;
		VAR res: INTEGER; Proc: PROCEDURE(i: USER32.Handle); atom: SHORTINT;
	BEGIN
		IF HostWindows.ctl3d # 0 THEN
			SYSTEM.PUT(
				SYSTEM.ADR(Proc), KERNEL32.GetProcAddress(HostWindows.ctl3d, "Ctl3dAutoSubclass"));
			IF Proc # NIL THEN Proc(KERNEL32.GetModuleHandleA(NIL)) END
		END;
		ReadCommandLine(IncludingFileCommandLine(KERNEL32.GetCommandLineA()), FALSE);
		IF openUsed THEN
			atom := WinApi.GlobalAddAtom(openParam);
			IF atom # 0 THEN
				res := WinApi.SendMessage(-1, msgId, atom, 0);
				KERNEL32.Sleep(100);
				res := WinApi.GlobalDeleteAtom(atom);
				atom := WinApi.GlobalFindAtom("<file_opened>");
				IF atom # 0 THEN res := WinApi.GlobalDeleteAtom(atom) END;
				IF (atom # 0) OR (res # 0) THEN Kernel.Quit(1) END
			END
		END;
		HostWindows.CreateMainWindows(menuBar, winMenu, ApplWinHandler);
		IF state = running THEN HostWindows.ShowMain END;
		res := USER32.SetTimer(HostWindows.main, 1, idlePeriod, NIL);
		SHELL32.DragAcceptFiles(HostWindows.main, 1);
		HostWindows.dir.invisible := TRUE
	END OpenApp;
	
	PROCEDURE Run*;
	BEGIN
		ReadCommandLine(IncludingFileCommandLine(KERNEL32.GetCommandLineA()), TRUE);
		Kernel.Start(Loop)
	END Run;


	PROCEDURE SetNum* (n: INTEGER);
	BEGIN
		num := n
	END SetNum;


	PROCEDURE Init;
		VAR res: INTEGER; s: ARRAY 256 OF SHORTCHAR;
	BEGIN
		state := running;
		HostCmds.quit := FALSE;
		CreateDefaultMenu;
		objMenu := USER32.CreatePopupMenu();
		lastId := firstId; menus := NIL;
		type := "undef";
		HostPorts.dialogBrush := GDI32.CreateSolidBrush(Ports.dialogBackground);
		minusCode := USER32.VkKeyScanA("-");
		IF minusCode # -1 THEN minusCode := minusCode MOD 256 END;
		Dialog.MapString("#Host:Shift", shiftStr);
		Dialog.MapString("#Host:Ctrl", ctrlStr);
		Dialog.MapString("#Host:Space", spaceStr);
		gc := 0; num := 10;
		res := KERNEL32.GetModuleFileNameA(0, s, LEN(s));
		msgId := WinApi.RegisterWindowMessage(s)
	END Init;

BEGIN
	Kernel.InstallCleaner(Collect);
	Init
CLOSE
	Kernel.RemoveCleaner(Collect);
	DestroyMenus
END HostMenus.
