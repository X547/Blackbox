MODULE Log;
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

	IMPORT Kernel;

	TYPE
		Hook* = POINTER TO ABSTRACT RECORD (Kernel.Hook) END;

	VAR
		synch*: BOOLEAN;	(* ~synch => output only on FlushBuf *)
		force*: BOOLEAN;	(* force => every call causes a Views.Restore *)

		hook: Hook;

	PROCEDURE (log: Hook) Guard* (o: ANYPTR): BOOLEAN, NEW, ABSTRACT;

	PROCEDURE (log: Hook) ClearBuf*, NEW, ABSTRACT;
	PROCEDURE (log: Hook) FlushBuf*, NEW, ABSTRACT;

	PROCEDURE (log: Hook) Beep*, NEW, ABSTRACT;
	PROCEDURE (log: Hook) Char* (ch: CHAR), NEW, ABSTRACT;
	PROCEDURE (log: Hook) Int* (n: INTEGER), NEW, ABSTRACT;
	PROCEDURE (log: Hook) Real* (x: REAL), NEW, ABSTRACT;
	PROCEDURE (log: Hook) String* (IN str: ARRAY OF CHAR), NEW, ABSTRACT;
	PROCEDURE (log: Hook) Bool* (x: BOOLEAN), NEW, ABSTRACT;
	PROCEDURE (log: Hook) Set* (x: SET), NEW, ABSTRACT;
	PROCEDURE (log: Hook) IntForm* (x: INTEGER; base, minWidth: INTEGER; fillCh: CHAR;
														showBase: BOOLEAN), NEW, ABSTRACT;
	PROCEDURE (log: Hook) RealForm* (x: REAL; precision, minW, expW: INTEGER;
																fillCh: CHAR), NEW, ABSTRACT;
	PROCEDURE (log: Hook) Tab*, NEW, ABSTRACT;
	PROCEDURE (log: Hook) Ln*, NEW, ABSTRACT;
	PROCEDURE (log: Hook) Para*, NEW, ABSTRACT;
	PROCEDURE (log: Hook) View* (v: ANYPTR), NEW, ABSTRACT;
	PROCEDURE (log: Hook) ViewForm* (v: ANYPTR; w, h: INTEGER), NEW, ABSTRACT;
	PROCEDURE (log: Hook) ParamMsg* (IN s, p0, p1, p2: ARRAY OF CHAR), NEW, ABSTRACT;


	PROCEDURE SetHook*(h: Hook);
	BEGIN
		hook := h
	END SetHook;

	PROCEDURE ClearBuf*;
	BEGIN
		IF hook # NIL THEN hook.ClearBuf END
	END ClearBuf;

	PROCEDURE FlushBuf*;
	BEGIN
		IF hook # NIL THEN hook.FlushBuf END
	END FlushBuf;

	PROCEDURE Guard* (o: ANYPTR): BOOLEAN;
	BEGIN
		RETURN (hook # NIL) & hook.Guard(o)
	END Guard;


	PROCEDURE Beep*;
	BEGIN
		IF hook # NIL THEN hook.Beep() END
	END Beep;

	PROCEDURE Char* (ch: CHAR);
	BEGIN
		IF hook # NIL THEN hook.Char(ch) END
	END Char;

	PROCEDURE Int* (n: INTEGER);
	BEGIN
		IF hook # NIL THEN hook.Int(n) END
	END Int;

	PROCEDURE Real* (x: REAL);
	BEGIN
		IF hook # NIL THEN hook.Real(x) END
	END Real;

	PROCEDURE String* (str: ARRAY OF CHAR);
	BEGIN
		IF hook # NIL THEN hook.String(str) END
	END String;

	PROCEDURE Bool* (x: BOOLEAN);
	BEGIN
		IF hook # NIL THEN hook.Bool(x) END
	END Bool;

	PROCEDURE Set* (x: SET);
	BEGIN
		IF hook # NIL THEN hook.Set(x) END
	END Set;

	PROCEDURE IntForm* (x: INTEGER; base, minWidth: INTEGER; fillCh: CHAR; showBase: BOOLEAN);
	BEGIN
		IF hook # NIL THEN hook.IntForm(x, base, minWidth, fillCh, showBase) END
	END IntForm;

	PROCEDURE RealForm* (x: REAL; precision, minW, expW: INTEGER; fillCh: CHAR);
	BEGIN
		IF hook # NIL THEN hook.RealForm(x, precision, minW, expW, fillCh) END
	END RealForm;

	PROCEDURE Tab*;
	BEGIN
		IF hook # NIL THEN hook.Tab END
	END Tab;

	PROCEDURE Ln*;
	BEGIN
		IF hook # NIL THEN hook.Ln END
	END Ln;

	PROCEDURE Para*;
	BEGIN
		IF hook # NIL THEN hook.Para END
	END Para;

	PROCEDURE View* (v: ANYPTR);
	BEGIN
		IF hook # NIL THEN hook.View(v) END
	END View;

	PROCEDURE ViewForm* (v: ANYPTR; w, h: INTEGER);
	BEGIN
		IF hook # NIL THEN hook.ViewForm(v, w, h) END
	END ViewForm;

	PROCEDURE ParamMsg* (s, p0, p1, p2: ARRAY OF CHAR);
	BEGIN
		IF hook # NIL THEN hook.ParamMsg(s, p0, p1, p2) END
	END ParamMsg;

	PROCEDURE Msg* (s: ARRAY OF CHAR);
	BEGIN
		ParamMsg(s, "", "", "")
	END Msg;

BEGIN
	synch := TRUE; force := FALSE
END Log.
