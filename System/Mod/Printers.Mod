MODULE Printers;
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

	IMPORT Ports;

	TYPE
		Printer* = POINTER TO ABSTRACT RECORD
			l, t, r, b: INTEGER;	(** paper rect relative to port coords **)
			res*: INTEGER;
			port: Ports.Port
		END;

		Directory* = POINTER TO ABSTRACT RECORD END;

	VAR dir-, stdDir-: Directory;


	PROCEDURE (p: Printer) OpenJob* (VAR copies: INTEGER; name: ARRAY OF CHAR), NEW, ABSTRACT;
	PROCEDURE (p: Printer) CloseJob* (), NEW, ABSTRACT;
	PROCEDURE (p: Printer) OpenPage* (), NEW, ABSTRACT;
	PROCEDURE (p: Printer) ClosePage* (), NEW, ABSTRACT;

	PROCEDURE (p: Printer) SetOrientation* (landscape: BOOLEAN), NEW, EMPTY;

	PROCEDURE (p: Printer) InitPort* (port: Ports.Port), NEW;
	BEGIN
		ASSERT((p.port = NIL) OR (p.port = port), 20);
		p.port := port
	END InitPort;

	PROCEDURE (p: Printer) ThisPort* (): Ports.Port, NEW;
	BEGIN
		RETURN p.port
	END ThisPort;

	PROCEDURE (p: Printer) GetRect* (OUT l, t, r, b: INTEGER), NEW;
	BEGIN
		l := p.l; t := p.t; r:= p.r; b := p.b
	END GetRect;

	PROCEDURE (p: Printer) InitPrinter* (l, t, r, b: INTEGER), NEW;
	BEGIN
		ASSERT(l <= r, 20); ASSERT(t <= b, 21);
		p.l := l; p.t := t; p.r := r; p.b := b;
		p.res := 0
	END InitPrinter;


	PROCEDURE (d: Directory) Default* (): Printer, NEW, ABSTRACT;
	PROCEDURE (d: Directory) Current* (): Printer, NEW, ABSTRACT;
	PROCEDURE (d: Directory) Available* (): BOOLEAN, NEW, ABSTRACT;


	PROCEDURE SetDir* (d: Directory);
	BEGIN
		ASSERT(d # NIL, 20);
		dir := d;
		IF stdDir = NIL THEN stdDir := d END
	END SetDir;

END Printers.
