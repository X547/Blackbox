MODULE DevCPH;
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

	IMPORT DevCPT;
	
	CONST
		(* UseCalls options *)
		longMop* = 0; longDop* = 1; longConv* = 2; longOdd* = 3;
		realMop* = 8; realDop* = 9; realConv* = 10;
		intMulDiv* = 11;
		force = 16; hide = 17;
	
		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
		Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
		Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
		Nifelse =20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
		Nreturn = 26; Nwith = 27; Ntrap = 28; Ncomp = 30;
		Ndrop = 50; Nlabel = 51; Ngoto = 52; Njsr = 53; Nret = 54; Ncmp = 55;
		
		(*function number*)
		assign = 0; newfn = 1; incfn = 13; decfn = 14;
		inclfn = 15; exclfn = 16; copyfn = 18; assertfn = 32;
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;
		
		(* symbol values and ops *)
		times = 1; slash = 2; div = 3; mod = 4;
		and = 5; plus = 6; minus = 7; or = 8; eql = 9;
		neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;
		in = 15; is = 16; ash = 17; msk = 18; len = 19;
		conv = 20; abs = 21; cap = 22; odd = 23; not = 33;
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;
		min = 34; max = 35; typfn = 36;
		thisrecfn = 45; thisarrfn = 46;
		shl = 50; shr = 51; lshr = 52; xor = 53;

		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char8 = 3; Int8 = 4; Int16 = 5; Int32 = 6;
		Real32 = 7; Real64 = 8; Set = 9; String8 = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		Char16 = 16; String16 = 17; Int64 = 18;
		VString16to8 = 29; VString8 = 30; VString16 = 31;
		realSet = {Real32, Real64};
		Basic = 1; Array = 2; DynArr = 3; Record = 4;

		

	PROCEDURE UseThisCall (n: DevCPT.Node; IN name: ARRAY OF SHORTCHAR);
		VAR mod, nm, moda: DevCPT.Name; mobj, obj: DevCPT.Object; done: BOOLEAN;
	BEGIN
		IF (n.typ.form = Real64) OR (n.left.typ.form = Real64) THEN mod := "Real"
		ELSIF (n.typ.form = Real32) OR (n.left.typ.form = Real32) THEN mod := "SReal"
		ELSIF (n.typ.form = Int64) OR (n.left.typ.form = Int64) THEN mod := "Long"
		ELSE mod := "Int"
		END;
		moda := mod + "%";
		DevCPT.Find(moda, mobj);
		IF mobj = NIL THEN
			DevCPT.Import(moda, mod, done);
			IF done THEN DevCPT.Find(moda, mobj) END
		END;
		nm := name$; DevCPT.FindImport(nm, mobj, obj);
		n.class := Ncall; n.subcl := 0; n.obj := obj.link;
		n.left.link := n.right; n.right := n.left;
		n.left := DevCPT.NewNode(Nproc);
		n.left.obj := obj; n.left.typ := obj.typ;
		ASSERT(n.typ.form = obj.typ.form)
	END UseThisCall;
	
	PROCEDURE Convert (n: DevCPT.Node; typ: DevCPT.Struct);
		VAR new: DevCPT.Node; r: REAL;
	BEGIN
		IF n.class = Nconst THEN
			ASSERT((n.typ.form IN {Int32, Int64}) & (typ = DevCPT.intrealtyp));
			r := n.conval.realval + n.conval.intval;
			IF r = n.conval.realval + n.conval.intval THEN
				n.conval.realval := r; n.conval.intval := -1; n.typ := typ; n.obj := NIL
			END
		END;
		IF (n.typ # typ)
			& ((n.class # Nmop) OR (n.subcl # conv)
				OR ~DevCPT.Includes(n.typ.form, n.left.typ.form) & ~DevCPT.Includes(n.typ.form, typ.form)) THEN
			new := DevCPT.NewNode(0); new^ := n^;
			n.class := Nmop; n.subcl := conv; n.left := new; n.right := NIL; n.obj := NIL
		END;
		n.typ := typ
	END Convert;
	
	PROCEDURE UseCallForComp (n: DevCPT.Node);
		VAR new: DevCPT.Node;
	BEGIN
		new := DevCPT.NewNode(0);
		new.left := n.left; new.right := n.right;
		new.typ := DevCPT.int32typ;
		UseThisCall(new, "Comp");
		n.left := new;
		n.right := DevCPT.NewNode(Nconst); n.right.conval := DevCPT.NewConst();
		n.right.conval.intval := 0; n.right.conval.realval := 0; n.right.typ := DevCPT.int32typ;
	END UseCallForComp;
	
	PROCEDURE UseCallForConv (n: DevCPT.Node; opts: SET);
		VAR f, g: INTEGER; typ: DevCPT.Struct;
	BEGIN
		typ := n.typ; f := typ.form; g := n.left.typ.form;
		IF realConv IN opts THEN
			IF f IN realSet THEN
				IF g = Real32 THEN UseThisCall(n, "Long")
				ELSIF g = Real64 THEN UseThisCall(n, "Short")
				ELSIF g = Int64 THEN UseThisCall(n, "LFloat")
				ELSIF g = Int32 THEN UseThisCall(n, "Float")
				ELSE Convert(n.left, DevCPT.int32typ); UseThisCall(n, "Float")
				END
			ELSIF g IN realSet THEN
				IF f = Int64 THEN UseThisCall(n, "LFloor")
				ELSIF f = Int32 THEN UseThisCall(n, "Floor")
				ELSE n.typ := DevCPT.int32typ; UseThisCall(n, "Floor"); Convert(n, typ)
				END
			END
		END;
		IF longConv IN opts THEN
			IF f = Int64 THEN
				IF g = Int32 THEN UseThisCall(n, "Long")
				ELSIF ~(g IN realSet) THEN Convert(n.left, DevCPT.int32typ); UseThisCall(n, "IntToLong")
				END
			ELSIF g = Int64 THEN
				IF f = Int32 THEN UseThisCall(n, "Short")
				ELSIF ~(f IN realSet) THEN n.typ := DevCPT.int32typ; UseThisCall(n, "LongToInt"); Convert(n, typ)
				END
			END
		END
	END UseCallForConv;
		
	PROCEDURE UseCallForMop (n: DevCPT.Node; opts: SET);
	BEGIN
		CASE n.subcl OF
		| minus:
			IF (realMop IN opts) & (n.typ.form IN realSet) OR (longMop IN opts) & (n.typ.form = Int64) THEN
				UseThisCall(n, "Neg")
			END
		| abs:
			IF (realMop IN opts) & (n.typ.form IN realSet) OR (longMop IN opts) & (n.typ.form = Int64) THEN
				UseThisCall(n, "Abs")
			END
		| odd:
			IF (longOdd IN opts) & (n.left.typ.form = Int64) THEN UseThisCall(n, "Odd") END
		| conv:
			UseCallForConv(n, opts)
		ELSE
		END
	END UseCallForMop;
		
	PROCEDURE UseCallForDop (n: DevCPT.Node; opts: SET);
	BEGIN
		IF (realDop IN opts) & (n.left.typ.form IN realSet)
				OR (longDop IN opts) & (n.left.typ.form = Int64)
				OR (intMulDiv IN opts) & (n.subcl IN {times, div, mod}) & (n.typ.form = Int32) THEN
			CASE n.subcl OF
			| times: UseThisCall(n, "Mul")
			| slash: UseThisCall(n, "Div")
			| div: UseThisCall(n, "Div")
			| mod: UseThisCall(n, "Mod")
			| plus: UseThisCall(n, "Add")
			| minus: UseThisCall(n, "Sub")
			| ash: UseThisCall(n, "Ash")
			| min: UseThisCall(n, "Min")
			| max: UseThisCall(n, "Max")
			| eql..geq: UseCallForComp(n)
			ELSE
			END
		END
	END UseCallForDop;
	
	PROCEDURE UseCallForMove (n: DevCPT.Node; typ: DevCPT.Struct; opts: SET);
		VAR f, g: INTEGER;
	BEGIN
		f := n.typ.form; g := typ.form;
		IF f # g THEN
			IF (realConv IN opts) & ((f IN realSet) OR (g IN realSet))
					OR (longConv IN opts) & ((f = Int64) OR (g = Int64)) THEN
				Convert(n, typ);
				UseCallForConv(n, opts)
			END
		END
	END UseCallForMove;
		
	PROCEDURE UseCallForAssign (n: DevCPT.Node; opts: SET);
	BEGIN
		IF n.subcl = assign THEN UseCallForMove(n.right, n.left.typ, opts) END
	END UseCallForAssign;
	
	PROCEDURE UseCallForReturn (n: DevCPT.Node; opts: SET);
	BEGIN
		IF (n.left # NIL) & (n.obj # NIL) THEN UseCallForMove(n.left, n.obj.typ, opts) END
	END UseCallForReturn;
	
	PROCEDURE UseCallForParam (n: DevCPT.Node; fp: DevCPT.Object; opts: SET);
	BEGIN
		WHILE n # NIL DO
			UseCallForMove(n, fp.typ, opts);
			n := n.link; fp := fp.link
		END
	END UseCallForParam;
	
	PROCEDURE UseCalls* (n: DevCPT.Node; opts: SET);
	BEGIN
		WHILE n # NIL DO
			CASE n.class OF
			| Nmop:
				UseCalls(n.left, opts); UseCallForMop(n, opts)
			| Ndop:
				UseCalls(n.left, opts); UseCalls(n.right, opts); UseCallForDop(n, opts)
			| Ncase:
				UseCalls(n.left, opts); UseCalls(n.right.left, opts); UseCalls(n.right.right, opts)
			| Nassign:
				UseCalls(n.left, opts); UseCalls(n.right, opts); UseCallForAssign(n, opts)
			| Ncall:
				UseCalls(n.left, opts); UseCalls(n.right, opts); UseCallForParam(n.right, n.obj, opts)
			| Nreturn:
				UseCalls(n.left, opts); UseCallForReturn(n, opts)
			| Ncasedo:
				UseCalls(n.right, opts)
			| Ngoto, Ndrop, Nloop, Nfield, Nderef, Nguard:
				UseCalls(n.left, opts)
			| Nenter, Nifelse, Nif, Nwhile, Nrepeat, Nwith, Ncomp, Nupto, Nindex:
				UseCalls(n.left, opts); UseCalls(n.right, opts)
			| Njsr, Nret, Nlabel, Ntrap, Nexit, Ninittd, Ntype, Nproc, Nconst, Nvar, Nvarpar:
			END;
			n := n.link
		END
	END UseCalls;
	
		
	PROCEDURE UseReals* (n: DevCPT.Node; opts: SET);
	BEGIN
		WHILE n # NIL DO
			CASE n.class OF
			| Nmop:
				IF (longMop IN opts) & (n.typ.form = Int64) & ((n.subcl = abs) OR (n.subcl = minus)) THEN
					UseReals(n.left, opts - {hide} + {force}); n.typ := DevCPT.intrealtyp
				ELSIF n.subcl = conv THEN UseReals(n.left, opts - {force} + {hide})
				ELSE UseReals(n.left, opts - {force, hide})
				END
			| Ndop:
				IF (longDop IN opts) & (n.left.typ.form = Int64) THEN
					UseReals(n.left, opts - {hide} + {force}); UseReals(n.right, opts - {hide} + {force});
					IF n.typ.form = Int64 THEN n.typ := DevCPT.intrealtyp END
				ELSE UseReals(n.left, opts - {force, hide}); UseReals(n.right, opts - {force, hide})
				END
			| Ncase:
				UseReals(n.left, opts - {force, hide}); UseReals(n.right.left, opts - {force, hide});
				UseReals(n.right.right, opts - {force, hide})
			| Ncasedo:
				UseReals(n.right, opts - {force, hide})
			| Ngoto, Ndrop, Nloop, Nreturn, Nfield, Nderef, Nguard:
				UseReals(n.left, opts - {force, hide})
			| Nenter, Nassign, Ncall, Nifelse, Nif, Nwhile, Nrepeat, Nwith, Ncomp, Nupto, Nindex:
				UseReals(n.left, opts - {force, hide}); UseReals(n.right, opts - {force, hide})
			| Njsr, Nret, Nlabel, Ntrap, Nexit, Ninittd, Ntype, Nproc, Nconst, Nvar, Nvarpar:
			END;
			IF force IN opts THEN Convert(n, DevCPT.intrealtyp)
			ELSIF ~(hide IN opts) & (n.typ = DevCPT.intrealtyp) THEN Convert(n, DevCPT.int64typ)
			END;
			n := n.link
		END
	END UseReals;
		
END DevCPH.




	PROCEDURE Traverse (n: DevCPT.Node; opts: SET);
	BEGIN
		WHILE n # NIL DO
			CASE n.class OF
			| Ncase:
				Traverse(n.left, opts); Traverse(n.right.left, opts); Traverse(n.right.right, opts)
			| Ncasedo:
				Traverse(n.right, opts)
			| Ngoto, Ndrop, Nloop, Nreturn, Nmop, Nfield, Nderef, Nguard:
				Traverse(n.left, opts)
			| Nenter, Nassign, Ncall, Nifelse, Nif, Nwhile, Nrepeat, Nwith, Ncomp, Ndop, Nupto, Nindex:
				Traverse(n.left, opts); Traverse(n.right, opts)
			| Njsr, Nret, Nlabel, Ntrap, Nexit, Ninittd, Ntype, Nproc, Nconst, Nvar, Nvarpar:
			END;
			n := n.link
		END
	END Traverse;
		
