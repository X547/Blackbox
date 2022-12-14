MODULE StdDialog;
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

	IMPORT
		Kernel, Meta, Strings, Files, Stores, Models, Sequencers, Views,
		Containers, Dialog, Properties, Documents, Converters, Windows;


	TYPE
		Item* = POINTER TO EXTENSIBLE RECORD
			next*: Item;
			item-, string-, filter-: POINTER TO ARRAY OF CHAR;
			shortcut-: ARRAY 8 OF CHAR;
			privateFilter-, failed, trapped: BOOLEAN;	(* filter call failed, caused a trap *)
			res: INTEGER	(* result code of failed filter *)
		END;
		
		FilterProcVal = RECORD (Meta.Value) p: Dialog.GuardProc END;
		FilterProcPVal = RECORD (Meta.Value) p: PROCEDURE(n: INTEGER; VAR p: Dialog.Par) END;

		ViewHook = POINTER TO RECORD (Views.ViewHook) END;


	VAR curItem-: Item;	(** IN parameter for item filters **)


	PROCEDURE GetSubLoc* (mod: ARRAY OF CHAR; cat: Files.Name;
											OUT loc: Files.Locator; OUT name: Files.Name);
		VAR sub: Files.Name; file: Files.File; type: Files.Type;
	BEGIN
		IF (cat[0] = "S") & (cat[1] = "y") & (cat[2] = "m") THEN type := Kernel.symType
		ELSIF (cat[0] = "C") & (cat[1] = "o") & (cat[2] = "d") & (cat[3] = "e") THEN type := Kernel.objType
		ELSE type := ""
		END;
		Kernel.SplitName(mod, sub, name); Kernel.MakeFileName(name, type);
		loc := Files.dir.This(sub); file := NIL;
		IF loc.res = 0 THEN
			loc := loc.This(cat);
			IF sub = "" THEN
				IF loc.res = 0 THEN
					file := Files.dir.Old(loc, name, Files.shared);
					IF file = NIL THEN loc := NIL END
				END;
				IF (loc = NIL) OR (loc.res # 0) THEN
					loc := Files.dir.This("System");
					IF loc.res = 0 THEN loc := loc.This(cat) END
				END
			END
		END
	END GetSubLoc;


	PROCEDURE Len (VAR str: ARRAY OF CHAR): INTEGER;
		VAR i: INTEGER;
	BEGIN
		i := 0; WHILE str[i] # 0X DO INC(i) END;
		RETURN i
	END Len;

	PROCEDURE AddItem* (i: Item; item, string, filter, shortcut: ARRAY OF CHAR);
		VAR j: INTEGER; ch: CHAR;
	BEGIN
		ASSERT(i # NIL, 20);
		NEW(i.item, Len(item) + 1);
		NEW(i.string, Len(string) + 1);
		NEW(i.filter, Len(filter) + 1);
		ASSERT((i.item # NIL) & (i.string # NIL) & (i.filter # NIL), 100);
		i.item^ := item$;
		i.string^ := string$;
		i.filter^ := filter$;
		i.shortcut := shortcut$;
		j := 0; ch := filter[0]; WHILE (ch # ".") & (ch # 0X) DO INC(j); ch := filter[j] END;
		i.privateFilter := (j > 0) & (ch = 0X);
		i.failed := FALSE; i.trapped := FALSE
	END AddItem;

	PROCEDURE ClearGuards* (i: Item);
	BEGIN
		i.failed := FALSE; i.trapped := FALSE
	END ClearGuards;

	PROCEDURE GetGuardProc (name: ARRAY OF CHAR; VAR i: Meta.Item;
														VAR par: BOOLEAN; VAR n: INTEGER);
		VAR j, k: INTEGER; num: ARRAY 32 OF CHAR;
	BEGIN
		j := 0;
		WHILE (name[j] # 0X) & (name[j] # "(") DO INC(j) END;
		IF name[j] = "(" THEN
			name[j] := 0X; INC(j); k := 0;
			WHILE (name[j] # 0X) & (name[j] # ")") DO num[k] := name[j]; INC(j); INC(k) END;
			IF (name[j] = ")") & (name[j+1] = 0X) THEN
				num[k] := 0X; Strings.StringToInt(num, n, k);
				IF k = 0 THEN Meta.LookupPath(name, i); par := TRUE
				ELSE Meta.Lookup("", i)
				END
			ELSE Meta.Lookup("", i)
			END
		ELSE
			Meta.LookupPath(name, i); par := FALSE
		END
	END GetGuardProc;
	
	PROCEDURE CheckFilter* (i: Item; VAR failed, ok: BOOLEAN; VAR par: Dialog.Par);
		VAR x: Meta.Item; v: FilterProcVal; vp: FilterProcPVal; p: BOOLEAN; n: INTEGER;
	BEGIN
		IF ~i.failed THEN
			curItem := i;
			par.disabled := FALSE; par.checked := FALSE; par.label := i.item$;
			par.undef := FALSE; par.readOnly := FALSE;
			i.failed := TRUE; i.trapped := TRUE;
			GetGuardProc(i.filter^, x, p, n);
			IF (x.obj = Meta.procObj) OR (x.obj = Meta.varObj) & (x.typ = Meta.procTyp) THEN
				IF p THEN
					x.GetVal(vp, ok);
					IF ok THEN vp.p(n, par) END
				ELSE
					x.GetVal(v, ok);
					IF ok THEN v.p(par) END
				END
			ELSE ok := FALSE
			END;
			IF ok THEN i.res := 0 ELSE i.res := 1 END;
			i.trapped := FALSE; i.failed := ~ok
		END;
		failed := i.failed
	END CheckFilter;

	PROCEDURE HandleItem* (i: Item);
		VAR res: INTEGER;
	BEGIN
		IF ~i.failed THEN
			Views.ClearQueue; res := 0;
			Dialog.Call(i.string^, " ", res)
		ELSIF (i # NIL) & i.failed THEN
			IF i.trapped THEN
				Dialog.ShowParamMsg("#System:ItemFilterTrapped", i.string^, i.filter^, "")
			ELSE
				Dialog.ShowParamMsg("#System:ItemFilterNotFound", i.string^, i.filter^, "")
			END
		END
	END HandleItem;

	PROCEDURE RecalcView* (v: Views.View);
	(* recalc size of all subviews of v, then v itself *)
	VAR m: Models.Model; v1: Views.View; c: Containers.Controller;
		minW, maxW, minH, maxH, w, h, w0, h0: INTEGER;
	BEGIN
		IF v IS Containers.View THEN
			c := v(Containers.View).ThisController();
			IF c # NIL THEN
				v1 := NIL; c.GetFirstView(Containers.any, v1);
				WHILE v1 # NIL DO
					RecalcView(v1);
					c.GetNextView(Containers.any, v1)
				END
			END
		END;
		IF v.context # NIL THEN
			m := v.context.ThisModel();
			IF (m # NIL) & (m IS Containers.Model) THEN
				m(Containers.Model).GetEmbeddingLimits(minW, maxW, minH, maxH);
				v.context.GetSize(w0, h0); w := w0; h := h0;
				Properties.PreferredSize(v, minW, maxW, minH, maxH, w, h, w, h);
				IF (w # w0) OR (h # h0) THEN v.context.SetSize(w, h) END
			END
		END
	END RecalcView;


	PROCEDURE Open* (v: Views.View; title: ARRAY OF CHAR;
									loc: Files.Locator; name: Files.Name; conv: Converters.Converter;
									asTool, asAux, noResize, allowDuplicates, neverDirty: BOOLEAN);
		VAR t: Views.Title; flags, opts: SET; done: BOOLEAN; d: Documents.Document; i: INTEGER;
			win: Windows.Window; c: Containers.Controller; seq: ANYPTR;
	BEGIN
		IF conv = NIL THEN conv := Converters.list END;	(* use document converter *)
		ASSERT(v # NIL, 20);
		flags := {}; done := FALSE;
		IF noResize THEN
			flags := flags + {Windows.noResize, Windows.noHScroll, Windows.noVScroll}
		END;
		IF asTool THEN INCL(flags, Windows.isTool) END;
		IF asAux THEN INCL(flags, Windows.isAux) END;
		IF neverDirty THEN INCL(flags, Windows.neverDirty) END;
		i := 0;
		WHILE (i < LEN(t) - 1) & (title[i] # 0X) DO t[i] := title[i]; INC(i) END;
		t[i] := 0X;
		IF ~allowDuplicates THEN
			Windows.SelectBySpec(loc, name, conv, flags, done);
			IF ~done & (title # "") & (loc = NIL) & (name = "") THEN
				Windows.SelectByTitle(v, flags, t, done)
			END
		ELSE
			INCL(flags, Windows.allowDuplicates)
		END;
		IF ~done THEN
			IF v IS Documents.Document THEN
				IF v.context # NIL THEN
					d := Documents.dir.New(
								Views.CopyOf(v(Documents.Document).ThisView(), Views.shallow), 
								Views.undefined, Views.undefined)
				ELSE
					d := v(Documents.Document)
				END;
				ASSERT(d.context = NIL, 22);
				v := d.ThisView(); ASSERT(v # NIL, 23)
			ELSIF v.context # NIL THEN
				ASSERT(v.context IS Documents.Context, 24);
				d := v.context(Documents.Context).ThisDoc();
				IF d.context # NIL THEN
					d := Documents.dir.New(Views.CopyOf(v, Views.shallow), Views.undefined, Views.undefined)
				END;
				ASSERT(d.context = NIL, 25)
				(*IF d.Domain() = NIL THEN Stores.InitDomain(d, v.Domain()) END (for views opened via Views.Old *)
			ELSE
				d := Documents.dir.New(v, Views.undefined, Views.undefined)
			END;
			IF asTool OR asAux THEN
				c := d.ThisController();
				c.SetOpts(c.opts + {Containers.noSelection})
			END;
			ASSERT(d.Domain() = v.Domain(), 100);
			ASSERT(d.Domain() # NIL, 101);
			seq := d.Domain().GetSequencer();
			IF neverDirty & (seq # NIL) THEN
				ASSERT(seq IS Sequencers.Sequencer, 26);
				seq(Sequencers.Sequencer).SetDirty(FALSE)
			END;
			IF neverDirty THEN
				(* change "fit to page" to "fit to window" in secondary windows *)
				c := d.ThisController(); opts := c.opts;
				IF Documents.pageWidth IN opts THEN
					opts := opts - {Documents.pageWidth} + {Documents.winWidth}
				END;
				IF Documents.pageHeight IN opts THEN
					opts := opts - {Documents.pageHeight} + {Documents.winHeight}
				END;
				c.SetOpts(opts)
			END;
			win := Windows.dir.New();
			IF seq # NIL THEN
				Windows.dir.OpenSubWindow(win, d, flags, t)
			ELSE
				Windows.dir.Open(win, d, flags, t, loc, name, conv)
			END
		END
	END Open;
	
	PROCEDURE (h: ViewHook) Open (v: Views.View; title: ARRAY OF CHAR;
								loc: Files.Locator; name: Files.Name; conv: Converters.Converter;
								asTool, asAux, noResize, allowDuplicates, neverDirty: BOOLEAN);
	BEGIN
		Open(v, title, loc, name, conv, asTool, asAux, noResize, allowDuplicates, neverDirty)
	END Open;

	PROCEDURE (h: ViewHook) OldView (loc: Files.Locator; name: Files.Name;
																VAR conv: Converters.Converter): Views.View;
		VAR w: Windows.Window; s: Stores.Store; c: Converters.Converter;
	BEGIN
		ASSERT(loc # NIL, 20); ASSERT(name # "", 21);
		Kernel.MakeFileName(name, ""); s := NIL;
		c := conv;
		IF c = NIL THEN c := Converters.list END;	(* use document converter *)
		w := Windows.GetBySpec(loc, name, c, {});
		IF w # NIL THEN s := w.doc.ThisView() END;
		IF s = NIL THEN
			Converters.Import(loc, name, conv, s);
			IF s # NIL THEN RecalcView(s(Views.View)) END
		END;
		IF s # NIL THEN RETURN s(Views.View) ELSE RETURN NIL END
	END OldView;

	PROCEDURE (h: ViewHook) RegisterView (v: Views.View; 
															loc: Files.Locator; name: Files.Name; conv: Converters.Converter);
	BEGIN
		ASSERT(v # NIL, 20); ASSERT(loc # NIL, 21); ASSERT(name # "", 22);
		Kernel.MakeFileName(name, "");
		Converters.Export(loc, name, conv, v)
	END RegisterView;

	PROCEDURE Init;
		VAR h: ViewHook;
	BEGIN
		NEW(h); Views.SetViewHook(h)
	END Init;

BEGIN
	Init
END StdDialog.
