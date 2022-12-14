MODULE DevSelectors;
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
		Ports, Stores, Models, Views, Controllers, Fonts, Properties, TextModels, TextViews, TextSetters;
		

	CONST
		left* = 1; middle* = 2; right* = 3;

		minVersion = 0; currentVersion = 0;
		
		changeSelectorsKey = "#Dev:Change Selectors";


	TYPE
		Selector* = POINTER TO RECORD (Views.View)
			position-: INTEGER;	(* left, middle, right *)
			leftHidden: TextModels.Model;	(* valid iff (position = left) *)
			rightHidden: TextModels.Model	(* valid iff (position = left) *)
		END;

		Directory* = POINTER TO ABSTRACT RECORD END;

		StdDirectory = POINTER TO RECORD (Directory) END;
		
		
	VAR
		dir-, stdDir-: Directory;


		PROCEDURE (d: Directory) New* (position: INTEGER): Selector, NEW, ABSTRACT;


	PROCEDURE GetFirst (selector: Selector; OUT first: Selector; OUT pos: INTEGER);
		VAR c: Models.Context; rd: TextModels.Reader; v: Views.View; nest: INTEGER;
	BEGIN
		c := selector.context; first := NIL; pos := 0;
		WITH c: TextModels.Context DO
			IF selector.position = left THEN
				first := selector
			ELSE
				rd := c.ThisModel().NewReader(NIL); rd.SetPos(c.Pos());
				nest := 1; pos := 1; rd.ReadPrevView(v);
				WHILE (v # NIL) & (nest > 0) DO
					WITH v: Selector DO
						IF v.position = left THEN DEC(nest);
							IF nest = 0 THEN first := v END
						ELSIF v.position = right THEN INC(nest)
						ELSIF nest = 1 THEN INC(pos)
						END
					ELSE
					END;
					rd.ReadPrevView(v)
				END
			END
		ELSE (* selector not embedded in a text *)
		END;
		ASSERT((first = NIL) OR (first.position = left), 100)
	END GetFirst;
	
	PROCEDURE GetNext (rd: TextModels.Reader; OUT next: Selector);
		VAR nest: INTEGER; v: Views.View;
	BEGIN
		nest := 1; next := NIL; rd.ReadView(v);
		WHILE v # NIL DO
			WITH v: Selector DO
				IF v.position = left THEN INC(nest)
				ELSIF nest = 1 THEN next := v; RETURN
				ELSIF v.position = right THEN DEC(nest)
				END
			ELSE
			END;
			rd.ReadView(v)
		END
	END GetNext;

	PROCEDURE CalcSize (f: Selector; OUT w, h: INTEGER);
		VAR c: Models.Context; a: TextModels.Attributes; font: Fonts.Font; asc, dsc, fw: INTEGER;
	BEGIN
		c := f.context;
		IF (c # NIL) & (c IS TextModels.Context) THEN
			a := c(TextModels.Context).Attr();
			font := a.font
		ELSE font := Fonts.dir.Default();
		END;
		font.GetBounds(asc, dsc, fw);
		h := asc + dsc; w := 3 * h DIV 4
	END CalcSize;

	PROCEDURE GetSection (first: Selector; rd: TextModels.Reader; n: INTEGER; OUT name: ARRAY OF CHAR);
		VAR i, p0, p1: INTEGER; ch: CHAR; sel: Selector;
	BEGIN
		sel := first;
		IF first.leftHidden.Length() > 0 THEN
			rd := first.leftHidden.NewReader(rd); rd.SetPos(0);
			REPEAT p0 := rd.Pos(); GetNext(rd, sel); DEC(n) UNTIL (n < 0) OR (sel = NIL);
			IF sel = NIL THEN INC(n) END;
			p1 := rd.Pos() - 1
		END;
		IF n >= 0 THEN
			rd := first.context(TextModels.Context).ThisModel().NewReader(rd);
			rd.SetPos(first.context(TextModels.Context).Pos() + 1);
			REPEAT p0 := rd.Pos(); GetNext(rd, sel); DEC(n) UNTIL (n < 0) OR (sel = NIL) OR (sel.position = right);
			p1 := rd.Pos() - 1
		END;
		IF (n >= 0) & (first.rightHidden.Length() > 0) THEN
			rd := first.rightHidden.NewReader(rd); rd.SetPos(1);
			REPEAT p0 := rd.Pos(); GetNext(rd, sel); DEC(n) UNTIL (n < 0) OR (sel = NIL);
			p1 := rd.Pos() - 1;
			IF sel = NIL THEN p1 := first.rightHidden.Length() END
		END;
		IF n < 0 THEN
			rd.SetPos(p0); rd.ReadChar(ch); i := 0;
			WHILE (ch <= " ") & (rd.Pos() <= p1) DO rd.ReadChar(ch) END;
			WHILE (i < LEN(name) - 1) & (rd.Pos() <= p1) & (ch # 0X) DO
				IF ch >= " " THEN name[i] := ch; INC(i) END;
				rd.ReadChar(ch)
			END;
			WHILE (i > 0) & (name[i - 1] = " ") DO DEC(i) END;
			name[i] := 0X
		ELSE
			name := 7FX + ""
		END
	END GetSection;
	

	PROCEDURE ChangeSelector (first: Selector; rd: TextModels.Reader; selection: INTEGER);
		VAR pos, p0, len, s: INTEGER; text: TextModels.Model; sel: Selector;
	BEGIN
		text := rd.Base();
		pos := first.context(TextModels.Context).Pos() + 1;
		(* expand *)
		rd.SetPos(pos);
		REPEAT GetNext(rd, sel) UNTIL (sel = NIL) OR (sel.position = right);
		IF sel # NIL THEN
			len := first.rightHidden.Length();
			IF len > 0 THEN text.Insert(rd.Pos() - 1, first.rightHidden, 0, len) END;
			len := first.leftHidden.Length();
			IF len > 0 THEN text.Insert(pos, first.leftHidden, 0, len) END;
			IF selection # 0 THEN	(* collapse *)
				rd.SetPos(pos); s := 0;
				REPEAT GetNext(rd, sel); INC(s) UNTIL (s = selection) OR (sel = NIL) OR (sel.position = right);
				IF (sel # NIL) & (sel.position = middle) THEN
					first.leftHidden.Insert(0, text, pos, rd.Pos());
					rd.SetPos(pos); GetNext(rd, sel);
					p0 := rd.Pos() - 1;
					WHILE (sel # NIL) & (sel.position # right) DO GetNext(rd, sel) END;
					IF sel # NIL THEN
						first.rightHidden.Insert(0, text, p0, rd.Pos() - 1)
					END
				END
			END
		END;
		rd.SetPos(pos)
	END ChangeSelector;
	
	PROCEDURE ChangeThis (
		text: TextModels.Model; rd, rd1: TextModels.Reader; title: ARRAY OF CHAR; selection: INTEGER
	);
		VAR v: Views.View; str: ARRAY 256 OF CHAR;
	BEGIN
		rd := text.NewReader(rd);
		rd.SetPos(0); rd.ReadView(v);
		WHILE v # NIL DO
			WITH v: Selector DO
				IF v.position = left THEN
					GetSection(v, rd1, 0, str);
					IF str = title THEN
						ChangeSelector(v, rd, selection)
					END;
					IF v.leftHidden.Length() > 0 THEN ChangeThis(v.leftHidden, NIL, rd1, title, selection) END;
					IF v.rightHidden.Length() > 0 THEN ChangeThis(v.rightHidden, NIL, rd1, title, selection) END
				END
			ELSE
			END;
			rd.ReadView(v)
		END
	END ChangeThis;
	
	PROCEDURE Change* (text: TextModels.Model; title: ARRAY OF CHAR; selection: INTEGER);
		VAR rd, rd1: TextModels.Reader; script: Stores.Operation;
	BEGIN
		rd := text.NewReader(NIL);
		rd1 := text.NewReader(NIL);
		Models.BeginModification(Models.clean, text);
		Models.BeginScript(text, changeSelectorsKey, script);
		ChangeThis(text, rd, rd1, title, selection);
		Models.EndScript(text, script);
		Models.EndModification(Models.clean, text);
	END Change;
	
	PROCEDURE ChangeTo* (text: TextModels.Model; title, entry: ARRAY OF CHAR);
		VAR rd, rd1: TextModels.Reader; str: ARRAY 256 OF CHAR; v: Views.View; sel: INTEGER;
	BEGIN
		rd := text.NewReader(NIL);
		rd1 := text.NewReader(NIL);
		rd.SetPos(0); rd.ReadView(v);
		WHILE v # NIL DO
			WITH v: Selector DO
				IF v.position = left THEN
					GetSection(v, rd1, 0, str);
					IF title = str THEN
						sel := 0;
						REPEAT
							INC(sel); GetSection(v, rd1, sel, str)
						UNTIL (str[0] = 7FX) OR (str = entry);
						IF str[0] # 7FX THEN
							Change(text, title, sel);
							RETURN
						END
					END
				END
			ELSE
			END;
			rd.ReadView(v)
		END
	END ChangeTo;


	PROCEDURE (selector: Selector) HandlePropMsg- (VAR msg: Properties.Message);
		VAR c: Models.Context; a: TextModels.Attributes; asc, w: INTEGER;
	BEGIN
		WITH msg: Properties.SizePref DO CalcSize(selector, msg.w, msg.h)
		| msg: Properties.ResizePref DO msg.fixed := TRUE;
		| msg: Properties.FocusPref DO msg.hotFocus := TRUE;
		| msg: TextSetters.Pref DO c := selector.context;
			IF (c # NIL) & (c IS TextModels.Context) THEN
				a := c(TextModels.Context).Attr();
				a.font.GetBounds(asc, msg.dsc, w)
			END
		ELSE (*selector.HandlePropMsg^(msg);*)
		END
	END HandlePropMsg;

	PROCEDURE Track (selector: Selector; f: Views.Frame; x, y: INTEGER; buttons: SET; VAR hit: BOOLEAN);
		VAR a: TextModels.Attributes; font: Fonts.Font; c: Models.Context;
			w, h, asc, dsc, fw: INTEGER; isDown, in, in0: BOOLEAN; modifiers: SET;
	BEGIN
		c := selector.context; hit := FALSE;
		WITH c: TextModels.Context DO
			a := c.Attr(); font := a.font;
			c.GetSize(w, h); in0 := FALSE;
			in := (0 <= x) & (x < w) & (0 <= y) & (y < h);
			REPEAT
				IF in # in0 THEN
					f.MarkRect(0, 0, w, h, Ports.fill, Ports.hilite, FALSE); in0 := in
				END;
				f.Input(x, y, modifiers, isDown);
				in := (0 <= x) & (x < w) & (0 <= y) & (y < h)
			UNTIL ~isDown;
			IF in0 THEN hit := TRUE;
				font.GetBounds(asc, dsc, fw);
				f.MarkRect(0, 0, w, asc + dsc, Ports.fill, Ports.hilite, FALSE);
			END
		ELSE
		END
	END Track;

	PROCEDURE (selector: Selector) HandleCtrlMsg* (
		f: Views.Frame; VAR msg: Views.CtrlMessage; VAR focus: Views.View
	);
		VAR hit: BOOLEAN; sel, pos: INTEGER; text: TextModels.Model; title: ARRAY 256 OF CHAR; first: Selector;
	BEGIN
		WITH msg: Controllers.TrackMsg DO
			IF selector.context IS TextModels.Context THEN
				Track(selector, f, msg.x, msg.y, msg.modifiers, hit);
				IF hit THEN
					text := selector.context(TextModels.Context).ThisModel();
					GetFirst(selector, first, pos);
					IF first # NIL THEN
						GetSection(first, NIL, 0, title);
						IF selector.position = middle THEN sel := pos ELSE sel := 0 END;
						Change(text, title, sel);
						text := selector.context(TextModels.Context).ThisModel();
						IF TextViews.FocusText() = text THEN
							pos := selector.context(TextModels.Context).Pos();
							TextViews.ShowRange(text, pos, pos+1, TRUE)
						END
					END
				END
			END
		| msg: Controllers.PollCursorMsg DO
			msg.cursor := Ports.refCursor;
		ELSE
		END
	END HandleCtrlMsg;

	PROCEDURE (selector: Selector) Restore* (f: Views.Frame; l, t, r, b: INTEGER);
		VAR w, h, d: INTEGER;
	BEGIN
		selector.context.GetSize(w, h);
(*
		GetFirst(selector, first, pos);
*)
		w := w - w MOD f.unit; d := 2 * f.dot;
		f.DrawLine(d, d, w - d, d, d, Ports.grey25);
		f.DrawLine(d, h - d, w - d, h - d, d, Ports.grey25);
		IF selector.position # right THEN f.DrawLine(d, d, d, h - d, d, Ports.grey25) END;
		IF selector.position # left THEN f.DrawLine(w - d, d, w - d, h - d, d, Ports.grey25) END
	END Restore;

	PROCEDURE (selector: Selector) CopyFromSimpleView- (source: Views.View);
	BEGIN
		(* selector.CopyFrom^(source); *)
		WITH source: Selector DO
			selector.position := source.position;
			IF source.leftHidden # NIL THEN
				selector.leftHidden := TextModels.CloneOf(source.leftHidden);
				selector.leftHidden.InsertCopy(0, source.leftHidden, 0, source.leftHidden.Length());
				Stores.Join(selector, selector.leftHidden)
			END;
			IF source.rightHidden # NIL THEN
				selector.rightHidden := TextModels.CloneOf(source.rightHidden);
				selector.rightHidden.InsertCopy(0, source.rightHidden, 0, source.rightHidden.Length());
				Stores.Join(selector, selector.rightHidden)
			END
		END
	END CopyFromSimpleView;

	PROCEDURE (selector: Selector) InitContext* (context: Models.Context);
	BEGIN
		selector.InitContext^(context);
		IF selector.position = left THEN
			WITH context: TextModels.Context DO
				IF selector.leftHidden = NIL THEN 
					selector.leftHidden := TextModels.CloneOf(context.ThisModel());
					Stores.Join(selector, selector.leftHidden);
				END;
				IF selector.rightHidden = NIL THEN
					selector.rightHidden := TextModels.CloneOf(context.ThisModel());
					Stores.Join(selector, selector.rightHidden)
				END
			ELSE
			END
		END
	END InitContext;
	
	PROCEDURE (selector: Selector) Internalize- (VAR rd: Stores.Reader);
		VAR version: INTEGER; store: Stores.Store;
	BEGIN
		selector.Internalize^(rd);
		IF rd.cancelled THEN RETURN END;
		rd.ReadVersion(minVersion, currentVersion, version);
		IF rd.cancelled THEN RETURN END;
		rd.ReadInt(selector.position);
		rd.ReadStore(store);
		IF store # NIL THEN selector.leftHidden := store(TextModels.Model)
		ELSE selector.leftHidden := NIL
		END;
		rd.ReadStore(store);
		IF store # NIL THEN selector.rightHidden := store(TextModels.Model)
		ELSE selector.rightHidden := NIL
		END
	END Internalize;

	PROCEDURE (selector: Selector) Externalize- (VAR wr: Stores.Writer);
	BEGIN
		selector.Externalize^(wr);
		wr.WriteVersion(currentVersion);
		wr.WriteInt(selector.position);
		wr.WriteStore(selector.leftHidden);
		wr.WriteStore(selector.rightHidden)
	END Externalize;


	PROCEDURE (d: StdDirectory) New (position: INTEGER): Selector;
		VAR selector: Selector;
	BEGIN
		NEW(selector);
		selector.position := position;
		RETURN selector
	END  New;

	PROCEDURE SetDir* (d: Directory);
	BEGIN
		ASSERT(d # NIL, 20);
		dir := d
	END SetDir;
	

	PROCEDURE DepositLeft*;
	BEGIN
		Views.Deposit(dir.New(left))
	END DepositLeft;

	PROCEDURE DepositMiddle*;
	BEGIN
		Views.Deposit(dir.New(middle))
	END DepositMiddle;

	PROCEDURE DepositRight*;
	BEGIN
		Views.Deposit(dir.New(right))
	END DepositRight;


	PROCEDURE InitMod;
		VAR d: StdDirectory;
	BEGIN
		NEW(d); dir := d; stdDir := d;
	END InitMod;

BEGIN
	InitMod
END DevSelectors.