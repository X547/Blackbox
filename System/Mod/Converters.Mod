MODULE Converters;
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

	IMPORT Meta, Files, Stores, Dialog;

	CONST
		(* hints *)
		importAll* = 0;	(* can import all file types *)
		canceled = 8;

	TYPE
		Importer* = PROCEDURE (f: Files.File; OUT s: Stores.Store);
		Exporter* = PROCEDURE (s: Stores.Store; f: Files.File);
		Converter* = POINTER TO RECORD
			next*: Converter;
			imp-, exp-: Dialog.String;
			storeType-: Stores.TypeName;
			fileType-: Files.Type;
			opts-: SET
		END;

		ImpVal = RECORD (Meta.Value) p: Importer END;
		ExpVal = RECORD (Meta.Value) p: Exporter END;

	VAR
		list-: Converter;
		doc: Converter;

	PROCEDURE GetCommand (name: Dialog.String; VAR val: Meta.Value; VAR ok: BOOLEAN);
		VAR i: Meta.Item;
	BEGIN
		Meta.LookupPath(name, i);
		IF (i.obj = Meta.procObj) OR (i.obj = Meta.varObj) & (i.typ = Meta.procTyp) THEN
			i.GetVal(val, ok)
		ELSE ok := FALSE
		END
	END GetCommand;


	PROCEDURE Register* (imp, exp: Dialog.String; storeType: Stores.TypeName; fileType: Files.Type; opts: SET);
		VAR e, f: Converter;
	BEGIN
		ASSERT((imp # "") OR (exp # ""), 20); ASSERT(fileType # "", 21);
		NEW(e); e.next := NIL;
		e.imp := imp; e.exp := exp; e.fileType := fileType; e.storeType := storeType; e.opts := opts;
		IF (storeType = "") & (doc = NIL) THEN doc := e END;
		IF list = NIL THEN list := e
		ELSE f := list;
			WHILE f.next # NIL DO f := f.next END;
			f.next := e
		END
	END Register;


	PROCEDURE Import* (loc: Files.Locator; name: Files.Name; VAR conv: Converter; OUT s: Stores.Store);
		VAR file: Files.File; val: ImpVal; ok: BOOLEAN;
	BEGIN
		ASSERT(loc # NIL, 20); ASSERT(name # "", 21);
		file := Files.dir.Old(loc, name, Files.shared); s := NIL;
		IF file # NIL THEN
			IF conv = NIL THEN
				conv := list;
				WHILE (conv # NIL) & ((conv.fileType # file.type) OR (conv.imp = "")) DO conv := conv.next END;
				IF conv = NIL THEN
					conv := list; WHILE (conv # NIL) & ~(importAll IN conv.opts) DO conv := conv.next END
				END
			ELSE ASSERT(conv.imp # "", 22)
			END;
			IF conv # NIL THEN
				GetCommand(conv.imp, val, ok);
				IF ok THEN val.p(file, s)
				ELSE Dialog.ShowMsg("#System:ConverterFailed")
				END
			ELSE Dialog.ShowMsg("#System:NoConverterFound")
			END
		END
	END Import;

	PROCEDURE Export* (loc: Files.Locator; name: Files.Name; conv: Converter; s: Stores.Store);
		VAR res: INTEGER; file: Files.File; val: ExpVal; ok: BOOLEAN;
	BEGIN
		ASSERT(s # NIL, 20); ASSERT(~(s IS Stores.Alien), 21);
		ASSERT(loc # NIL, 22); ASSERT(name # "", 23);
		file := Files.dir.New(loc, Files.ask); (* fileLoc := loc; *)
		IF file # NIL THEN
			IF conv = NIL THEN
				conv := doc
			ELSE ASSERT(conv.exp # "", 24)
			END;
			GetCommand(conv.exp, val, ok);
			IF ok THEN
				val.p(s, file);
				IF loc.res # canceled THEN
					file.Register(name, conv.fileType, Files.ask, res); loc.res := res
				END
			ELSE Dialog.ShowMsg("#System:ConverterFailed"); loc.res := canceled
			END
		END
	END Export;

BEGIN
	list := NIL
END Converters.
