MODULE Mechanisms;
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

	IMPORT Kernel, Views;

	CONST
		(** FocusBorderCursor/SelBorderCursor result **)
		inside* = -1; outside* = -2;	(** plus defined Ports cursors **)

		(** TrackToResize op **)
		cancelResize* = 0; resize* = 1;

		(** TrackToDrop op **)
		cancelDrop* = 0; copy* = 1; move* = 2; link* = 3;

		(** TrackToPick op **)
		cancelPick* = 0; pick* = 1; pickForeign* = 2;

	TYPE
		Hook* = POINTER TO ABSTRACT RECORD (Kernel.Hook) END;

	VAR hook: Hook;

	PROCEDURE SetHook*(h: Hook);
	BEGIN
		hook := h
	END SetHook;

	PROCEDURE (hook: Hook) MarkFocusBorder* (host: Views.Frame;
										focus: Views.View; l, t, r, b: INTEGER;
										show: BOOLEAN), NEW, ABSTRACT;
	PROCEDURE (hook: Hook) MarkSingletonBorder* (host: Views.Frame;
										view: Views.View; l, t, r, b: INTEGER;
										show: BOOLEAN), NEW, ABSTRACT;

	PROCEDURE (hook: Hook) FocusBorderCursor* (host: Views.Frame;
										view: Views.View; l, t, r, b: INTEGER;
										x, y: INTEGER): INTEGER, NEW, ABSTRACT;
	PROCEDURE (hook: Hook) SelBorderCursor* (host: Views.Frame;
										view: Views.View; l, t, r, b: INTEGER;
										x, y: INTEGER): INTEGER, NEW, ABSTRACT;

	PROCEDURE (hook: Hook) TrackToResize* (host: Views.Frame; view: Views.View;
										minW, maxW, minH, maxH: INTEGER;
										VAR l, t, r, b: INTEGER; VAR op: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET), NEW, ABSTRACT;
	PROCEDURE (hook: Hook) TrackToDrop* (source: Views.Frame; view: Views.View;
										isSingle: BOOLEAN; w, h, rx, ry: INTEGER;
										VAR dest: Views.Frame; VAR destX, destY: INTEGER;
										VAR op: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET), NEW, ABSTRACT;
	PROCEDURE (hook: Hook) TrackToPick* (source: Views.Frame;
										VAR dest: Views.Frame; VAR destX, destY: INTEGER;
										VAR op: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET), NEW, ABSTRACT;

	PROCEDURE (hook: Hook) PopUpAndSelect* (f: Views.Frame;
										n, this: INTEGER;
										s: ARRAY OF ARRAY OF CHAR;
										enabled, checked: ARRAY OF BOOLEAN;
										VAR i: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET), NEW, ABSTRACT;

	PROCEDURE MarkFocusBorder* (host: Views.Frame;
										focus: Views.View; l, t, r, b: INTEGER;
										show: BOOLEAN);
	BEGIN
		hook.MarkFocusBorder(host, focus, l, t, r, b, show)
	END MarkFocusBorder;

	PROCEDURE MarkSingletonBorder* (host: Views.Frame;
										view: Views.View; l, t, r, b: INTEGER;
										show: BOOLEAN);
	BEGIN
		hook.MarkSingletonBorder(host, view, l, t, r, b, show)
	END MarkSingletonBorder;

	PROCEDURE FocusBorderCursor* (host: Views.Frame;
										view: Views.View; l, t, r, b: INTEGER;
										x, y: INTEGER): INTEGER;
	BEGIN
		RETURN hook.FocusBorderCursor(host, view, l, t, r, b, x, y)
	END FocusBorderCursor;

	PROCEDURE SelBorderCursor* (host: Views.Frame;
										view: Views.View; l, t, r, b: INTEGER;
										x, y: INTEGER): INTEGER;
	BEGIN
		RETURN hook.SelBorderCursor(host, view, l, t, r, b, x, y)
	END SelBorderCursor;

	PROCEDURE TrackToResize* (host: Views.Frame; view: Views.View;
										minW, maxW, minH, maxH: INTEGER;
										VAR l, t, r, b: INTEGER; VAR op: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET);
	BEGIN
		hook.TrackToResize(host, view, minW, maxW, minH, maxH, l, t, r, b, op, x, y, buttons)
	END TrackToResize;

	PROCEDURE TrackToDrop* (source: Views.Frame; view: Views.View;
										isSingle: BOOLEAN; w, h, rx, ry: INTEGER;
										VAR dest: Views.Frame; VAR destX, destY: INTEGER;
										VAR op: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET);
	BEGIN
		hook.TrackToDrop(source, view, isSingle, w, h, rx, ry, dest, destX, destY, op, x, y, buttons)
	END TrackToDrop;

	PROCEDURE TrackToPick* (source: Views.Frame;
										VAR dest: Views.Frame; VAR destX, destY: INTEGER;
										VAR op: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET);
	BEGIN
		hook.TrackToPick(source, dest, destX, destY, op, x, y, buttons)
	END TrackToPick;

	PROCEDURE PopUpAndSelect* (f: Views.Frame;
										n, this: INTEGER;
										s: ARRAY OF ARRAY OF CHAR;
										enabled, checked: ARRAY OF BOOLEAN;
										VAR i: INTEGER;
										VAR x, y: INTEGER; VAR buttons: SET);
	BEGIN
		hook.PopUpAndSelect(f, n, this, s, enabled, checked, i, x, y, buttons)
	END PopUpAndSelect;

END Mechanisms.
