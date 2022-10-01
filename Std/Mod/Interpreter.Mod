MODULE StdInterpreter;
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
	
	IMPORT Kernel, Meta, Strings, Views, Dialog;

	TYPE
		(* command procedure types *)
		Proc = PROCEDURE;
		ProcI = PROCEDURE(x: INTEGER);
		ProcII = PROCEDURE(x, y: INTEGER);
		ProcS = PROCEDURE(s: ARRAY OF CHAR);
		ProcSI = PROCEDURE(s: ARRAY OF CHAR; x: INTEGER);
		ProcSII = PROCEDURE(s: ARRAY OF CHAR; x, y: INTEGER);
		ProcSS = PROCEDURE(s, t: ARRAY OF CHAR);
		ProcSSI = PROCEDURE(s, t: ARRAY OF CHAR; x: INTEGER);
		ProcSSII = PROCEDURE(s, t: ARRAY OF CHAR; x, y: INTEGER);
		ProcR = PROCEDURE(IN s: ARRAY OF CHAR);
		ProcRI = PROCEDURE(IN s: ARRAY OF CHAR; x: INTEGER);
		ProcRII = PROCEDURE(IN s: ARRAY OF CHAR; x, y: INTEGER);
		ProcRS = PROCEDURE(IN s: ARRAY OF CHAR; t: ARRAY OF CHAR);
		ProcRSI = PROCEDURE(IN s: ARRAY OF CHAR; t: ARRAY OF CHAR; x: INTEGER);
		ProcRSII = PROCEDURE(IN s: ARRAY OF CHAR; t: ARRAY OF CHAR; x, y: INTEGER);
		ProcSR = PROCEDURE(s: ARRAY OF CHAR; IN t: ARRAY OF CHAR);
		ProcSRI = PROCEDURE(s: ARRAY OF CHAR; IN t: ARRAY OF CHAR; x: INTEGER);
		ProcSRII = PROCEDURE(s: ARRAY OF CHAR; IN t: ARRAY OF CHAR; x, y: INTEGER);
		ProcRR = PROCEDURE(IN s, t: ARRAY OF CHAR);
		ProcRRI = PROCEDURE(IN s, t: ARRAY OF CHAR; x: INTEGER);
		ProcRRII = PROCEDURE(IN s, t: ARRAY OF CHAR; x, y: INTEGER);
		(* corresponding meta values *)
		ProcVal = RECORD (Meta.Value) p: Proc END;
		ProcIVal = RECORD (Meta.Value) p: ProcI END;
		ProcIIVal = RECORD (Meta.Value) p: ProcII END;
		ProcSVal = RECORD (Meta.Value) p: ProcS END;
		ProcSIVal = RECORD (Meta.Value) p: ProcSI END;
		ProcSIIVal = RECORD (Meta.Value) p: ProcSII END;
		ProcSSVal = RECORD (Meta.Value) p: ProcSS END;
		ProcSSIVal = RECORD (Meta.Value) p: ProcSSI END;
		ProcSSIIVal = RECORD (Meta.Value) p: ProcSSII END;
		ProcRVal = RECORD (Meta.Value) p: ProcR END;
		ProcRIVal = RECORD (Meta.Value) p: ProcRI END;
		ProcRIIVal = RECORD (Meta.Value) p: ProcRII END;
		ProcRSVal = RECORD (Meta.Value) p: ProcRS END;
		ProcRSIVal = RECORD (Meta.Value) p: ProcRSI END;
		ProcRSIIVal = RECORD (Meta.Value) p: ProcRSII END;
		ProcSRVal = RECORD (Meta.Value) p: ProcSR END;
		ProcSRIVal = RECORD (Meta.Value) p: ProcSRI END;
		ProcSRIIVal = RECORD (Meta.Value) p: ProcSRII END;
		ProcRRVal = RECORD (Meta.Value) p: ProcRR END;
		ProcRRIVal = RECORD (Meta.Value) p: ProcRRI END;
		ProcRRIIVal = RECORD (Meta.Value) p: ProcRRII END;
		
		CallHook = POINTER TO RECORD (Dialog.CallHook) END;

		
	PROCEDURE (hook: CallHook) Call (IN proc, errorMsg: ARRAY OF CHAR; VAR res: INTEGER);
		TYPE Ident = ARRAY 32 OF CHAR;
		CONST
			modNotFound = 10; procNotFound = 11; identExpected = 12; unknownIdent = 13;
			depositExpected = 14; noDepositExpected = 15; syntaxError = 16;
			lparenExpected = 17; rparenExpected = 18; containerExpected = 19; quoteExpected = 20;
			fileNotFound = 21; noController = 22; noDialog = 23; cannotUnload = 24; commaExpected = 25;
			incompParList = 26;
		CONST
			 ident = 0; dot = 1; semicolon = 2; eot = 3; lparen = 4; rparen = 5; quote = 6; comma = 7; int = 8;
			parI = 1; parII = 2; parS = 3; parSI = 4; parSII = 5; parSS = 6; parSSI = 7; parSSII = 8;
		VAR
			i, type: INTEGER; ch: CHAR; id: Ident; e, f, g: ARRAY 64 OF CHAR; x: INTEGER;
			s0, s1: Dialog.String; i0, i1: INTEGER;	(* variable param lists *)
			par0: Dialog.String; par1: Views.Title;	(* fix param lists *)

		PROCEDURE Concat (a, b: ARRAY OF CHAR; VAR c: ARRAY OF CHAR);
			VAR i, j: INTEGER; ch: CHAR;
		BEGIN
			IF a = " " THEN Dialog.MapString("#System:CommandError", c) ELSE c := a$ END;
			i := 0; WHILE c[i] # 0X DO INC(i) END;
			c[i] := " "; INC(i);
			j := 0; ch := b[0]; WHILE ch # 0X DO c[i] := ch; INC(i); INC(j); ch := b[j] END;
			c[i] := 0X
		END Concat;

		PROCEDURE Error (n: INTEGER; msg, par0, par1: ARRAY OF CHAR);
			VAR e, f: ARRAY 256 OF CHAR;
		BEGIN
			IF res = 0 THEN
				res := n;
				IF errorMsg # "" THEN
					Dialog.MapString(errorMsg, e);
					Dialog.MapParamString(msg, par0, par1, "", f);
					Concat(e, f, f);
					Dialog.ShowMsg(f)
				END
			END
		END Error;
		
		PROCEDURE Init (VAR s: ARRAY OF CHAR);
			VAR i: INTEGER;
		BEGIN
			i := 0; WHILE i < LEN(s) DO s[i] := 0X; INC(i) END
		END Init;

		PROCEDURE CallProc (mod, proc: Ident; parType: INTEGER);
			VAR mn, pn: Meta.Name; i: Meta.Item; ok, a, b, c: BOOLEAN;
				v: ProcVal; vi: ProcIVal; vii: ProcIIVal;
				vs: ProcSVal; vsi: ProcSIVal; vsii: ProcSIIVal;
				vss: ProcSSVal; vssi: ProcSSIVal; vssii: ProcSSIIVal;
				vr: ProcRVal; vri: ProcRIVal; vrii: ProcRIIVal;
				vrs: ProcRSVal; vrsi: ProcRSIVal; vrsii: ProcRSIIVal;
				vsr: ProcSRVal; vsri: ProcSRIVal; vsrii: ProcSRIIVal;
				vrr: ProcRRVal; vrri: ProcRRIVal; vrrii: ProcRRIIVal;
				res: INTEGER;
				importing, imported, object: ARRAY 256 OF CHAR;
		BEGIN
			(* prevent from parasitic anchors on stack *)
			Init(mn); Init(pn); ok := FALSE; a := FALSE; b := FALSE; c := FALSE;
			mn := mod$; pn := proc$;
			Meta.Lookup(mn, i);
			IF i.obj = Meta.modObj THEN
				i.Lookup(pn, i);
				IF i.obj = Meta.procObj THEN
					CASE parType OF
					| 0: i.GetVal(v, ok); IF ok THEN v.p() END
					| parI: i.GetVal(vi, ok); IF ok THEN vi.p(i0) END
					| parII: i.GetVal(vii, ok); IF ok THEN vii.p(i0, i1) END
					| parS: i.GetVal(vs, ok); 
						IF ok THEN vs.p(s0) 
						ELSE i.GetVal(vr, ok); IF ok THEN vr.p(s0) END
						END
					| parSI: i.GetVal(vsi, ok); 
						IF ok THEN vsi.p(s0, i0) 
						ELSE i.GetVal(vri, ok); IF ok THEN vri.p(s0, i0) END
						END
					| parSII: i.GetVal(vsii, ok); 
						IF ok THEN vsii.p(s0, i0, i1) 
						ELSE i.GetVal(vrii, ok); IF ok THEN vrii.p(s0, i0, i1) END
						END
					| parSS: i.GetVal(vss, ok); 
						IF ok THEN vss.p(s0, s1) 
						ELSE i.GetVal(vrr, ok); IF ok THEN vrr.p(s0, s1)
						ELSE i.GetVal(vsr, ok); IF ok THEN vsr.p(s0, s1)
						ELSE i.GetVal(vrs, ok); IF ok THEN vrs.p(s0, s1)
						END END END END
					| parSSI: i.GetVal(vssi, ok); 
						IF ok THEN vssi.p(s0, s1, i0) 
						ELSE i.GetVal(vrri, ok); IF ok THEN vrri.p(s0, s1, i0)
						ELSE i.GetVal(vsri, ok); IF ok THEN vsri.p(s0, s1, i0)
						ELSE i.GetVal(vrsi, ok); IF ok THEN vrsi.p(s0, s1, i0)
						END END END END
					| parSSII: i.GetVal(vssii, ok); 
						IF ok THEN vssii.p(s0, s1, i0, i1) 
						ELSE i.GetVal(vrrii, ok); IF ok THEN vrrii.p(s0, s1, i0, i1)
						ELSE i.GetVal(vsrii, ok); IF ok THEN vsrii.p(s0, s1, i0, i1)
						ELSE i.GetVal(vrsii, ok); IF ok THEN vrsii.p(s0, s1, i0, i1)
						END END END END
					END;
					IF ~ok THEN
						Error(incompParList, "#System:IncompatibleParList", mod, proc)
					END
				ELSE
					Error(Kernel.commNotFound, "#System:CommandNotFoundIn", proc, mod)
				END
			ELSE
				Kernel.GetLoaderResult(res, importing, imported, object);
				CASE res OF
				| Kernel.fileNotFound:
					Error(Kernel.fileNotFound, "#System:CodeFileNotFound", imported, "")
				| Kernel.syntaxError:
					Error(Kernel.syntaxError, "#System:CorruptedCodeFileFor", imported, "")
				| Kernel.objNotFound:
					Error(Kernel.objNotFound, "#System:ObjNotFoundImpFrom", imported, importing)
				| Kernel.illegalFPrint:
					Error(Kernel.illegalFPrint, "#System:ObjInconsImpFrom", imported, importing)
				| Kernel.cyclicImport:
					Error(Kernel.cyclicImport, "#System:CyclicImpFrom", imported, importing)
				| Kernel.noMem:
					Error(Kernel.noMem, "#System:NotEnoughMemoryFor", imported, "")
				ELSE
					Error(res, "#System:CannotLoadModule", mod, "")
				END
			END
		END CallProc;

		PROCEDURE GetCh;
		BEGIN
			IF i < LEN(proc) THEN ch := proc[i]; INC(i) ELSE ch := 0X END
		END GetCh;

		PROCEDURE Scan;
			VAR j: INTEGER; num: ARRAY 32 OF CHAR; r: INTEGER;
		BEGIN
			IF res = 0 THEN
				WHILE (ch # 0X) & (ch <= " ") DO GetCh END;
				IF ch = 0X THEN
					type := eot
				ELSIF ch = "." THEN
					type := dot; GetCh
				ELSIF ch = ";" THEN
					type := semicolon; GetCh
				ELSIF ch = "(" THEN
					type := lparen; GetCh
				ELSIF ch = ")" THEN
					type := rparen; GetCh
				ELSIF ch = "'" THEN
					type := quote; GetCh
				ELSIF ch = "," THEN
					type := comma; GetCh
				ELSIF (ch >= "0") & (ch <= "9") OR (ch = "-") THEN
					type := int; j := 0;
					REPEAT num[j] := ch; INC(j); GetCh UNTIL (ch < "0") OR (ch > "9") & (ch < "A") OR (ch > "H");
					num[j] := 0X; Strings.StringToInt(num, x, r)
				ELSIF (ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z") OR
						(ch >= 0C0X) & (ch # "×") & (ch # "÷") & (ch <= 0FFX) OR (ch = "_") THEN
					type := ident;
					id[0] := ch; j := 1; GetCh;
					WHILE (ch # 0X) & (i < LEN(proc)) &
								((ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z") OR
								(ch >= 0C0X) & (ch # "×") & (ch # "÷") & (ch <= 0FFX) OR
								(ch = "_") OR (ch >= "0") & (ch <= "9")) DO
						id[j] := ch; INC(j); GetCh
					END;
					id[j] := 0X
				ELSE Error(syntaxError, "#System:SyntaxError", "", "")
				END
			END
		END Scan;
		
		PROCEDURE String (VAR s: ARRAY OF CHAR);
			VAR j: INTEGER;
		BEGIN
			IF type = quote THEN
				j := 0;
				WHILE (ch # 0X) & (ch # "'") & (j < LEN(s) - 1) DO s[j] := ch; INC(j); GetCh END; s[j] := 0X;
				IF ch = "'" THEN
					GetCh; Scan
				ELSE Error(quoteExpected, "#System:QuoteExpected", "", "")
				END
			ELSE Error(quoteExpected, "#System:QuoteExpected", "", "")
			END
		END String;

		PROCEDURE ParamList (VAR parType: INTEGER);
		BEGIN
			parType := 0;
			IF type = lparen THEN Scan;
				IF type = quote THEN
					String(s0);
					IF type= comma THEN Scan;
						IF type = quote THEN
							String(s1);
							IF type = comma THEN Scan;
								IF type = int THEN
									i0 := x; Scan;
									IF type = comma THEN Scan;
										IF type = int THEN
											i1 := x; parType := parSSII; Scan
										ELSE Error(syntaxError, "#System:SyntaxError", "", "")
										END
									ELSE parType := parSSI
									END
								ELSE Error(syntaxError, "#System:SyntaxError", "", "")
								END
							ELSE parType := parSS
							END
						ELSIF type = int THEN
							i0 := x; Scan;
							IF type = comma THEN Scan;
								IF type = int THEN
									i1 := x; parType := parSII; Scan
								ELSE Error(syntaxError, "#System:SyntaxError", "", "")
								END
							ELSE parType := parSI
							END
						ELSE Error(syntaxError, "#System:SyntaxError", "", "")
						END
					ELSE parType := parS
					END
				ELSIF type = int THEN
					i0 := x; Scan;
					IF type = comma THEN Scan;
						IF type = int THEN
							i1 := x; parType := parII; Scan
						ELSE Error(syntaxError, "#System:SyntaxError", "", "")
						END
					ELSE parType := parI
					END
				END;
				IF type = rparen THEN Scan
				ELSE Error(rparenExpected, "#System:RParenExpected", "", "")
				END
			END
		END ParamList;

		PROCEDURE Command;
			VAR left, right: Ident; ptype: INTEGER;
		BEGIN
			(* protect from parasitic anchors on stack *)
			Init(left); Init(right); ptype := 0;
			left := id; Scan;
			IF type = dot THEN	(* Oberon command *)
				Scan;
				IF type = ident THEN
					right := id; Scan; ParamList(ptype);
					CallProc(left, right, ptype)
				ELSE Error(identExpected, "#System:IdentExpected", "", "")
				END
			ELSE Error(unknownIdent, "#System:UnknownIdent", id, "")
			END
		END Command;

	BEGIN
		(* protect from parasitic anchors on stack *)
		i := 0; type := 0; Init(id); Init(e); Init(f); Init(g); x := 0; Init(s0); Init(s1); i0 := 0; i1 := 0; Init(par0); Init(par1);
		Views.ClearQueue;
		res := 0; i := 0; GetCh;
		Scan;
		IF type = ident THEN
			Command; WHILE (type = semicolon) & (res = 0) DO Scan; Command END;
			IF type # eot THEN Error(syntaxError, "#System:SyntaxError", "", "") END
		ELSE Error(syntaxError, "#System:SyntaxError", "", "")
		END;
		IF (res = 0) & (Views.Available() > 0) THEN
			Error(noDepositExpected, "#System:NoDepositExpected", "", "")
		END;
		Views.ClearQueue
	END Call;
	
	PROCEDURE Init;
		VAR hook: CallHook;
	BEGIN
		NEW(hook); Dialog.SetCallHook(hook)
	END Init;

BEGIN
	Init
END StdInterpreter.
