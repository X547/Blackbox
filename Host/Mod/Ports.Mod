MODULE HostPorts;
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
		SYSTEM, WinApi, KERNEL32, GDI32, USER32,
		Kernel, Fonts, Ports, Dialog, HostFonts;
	
	CONST
		resizeHCursor* = 16; resizeVCursor* = 17; resizeLCursor* = 18; resizeRCursor* = 19; resizeCursor* = 20;
		busyCursor* = 21; stopCursor* = 22;
		moveCursor* = 23; copyCursor* = 24; linkCursor* = 25; pickCursor* = 26;
		focusPat* = 5;
		
		extend = 1; modify = 2; (* same as Controllers.extend and Controllers.modify  !!! *)

		(** buttons **)
		left* = 16; middle* = 17; right* = 18;
		shift* = 24; ctrl* = 25; opt* = 26; cmd* = 27; alt* = 28;
		
		copy = 00CC0020H;	(* raster code for source copy *)
		xor = 00A50065H;	(* raster code for xor function *)
		figureSpace = 8FX;
		
	TYPE
		Port* = POINTER TO RECORD (Ports.Port)
			w-, h-: INTEGER;
			dc-: USER32.Handle;	(* actual dc *)
			wnd-: USER32.Handle;	(* used for invalidation, may be null *)
			homedc-: USER32.Handle;	(* unbuffered dc *)
			map: GDI32.Handle;	(* buffer bitmap *)
			bl, bt, br, bb: INTEGER;	(* buffer rectangle *)
			bx, by: INTEGER	(* bitmap pattern offset *)
		END;

		Rider* = POINTER TO EXTENSIBLE RECORD (Ports.Rider)
			l-, t-, r-, b-: INTEGER;
			port-: Port;
			dx, dy: INTEGER;	(* scroll offset *)
			map: GDI32.Handle;	(* save bitmap *)
			dc: USER32.Handle;	(* save dc *)
			sl, st, sr, sb: INTEGER	(* save rect *)
		END;


	VAR
		(* system colors *)
		textCol-, selBackground-, selTextCol-,
		dialogTextCol-, dialogShadowCol-, dialogLightCol-: Ports.Color;
		
		dialogBrush*, dim50Brush-: GDI32.Handle;
		
		debug*, noBuffer*, flag*: BOOLEAN;

		cursors-: ARRAY 32 OF USER32.Handle;
		
		nullBrush, nullPen: GDI32.Handle;
		invertBrush, dim25Brush, dim75Brush, focusBrush: GDI32.Handle;
		grgn: GDI32.Handle;
		mx, my: INTEGER;	(* actual mouse coordinates *)
		mb: SET;	(* actual mouse buttons & modifiers *)
		

	PROCEDURE Wait;
		VAR t: LONGINT;
	BEGIN
		t := Kernel.Time() + Kernel.timeResolution;
		REPEAT UNTIL Kernel.Time() > t
	END Wait;
	
		
	(** Port **)

	PROCEDURE (p: Port) SetSize* (w, h: INTEGER);
	BEGIN
		ASSERT(w >= 0, 20); ASSERT(h >= 0, 21);
		p.w := w; p.h := h
	END SetSize;
	
	PROCEDURE (p: Port) GetSize* (OUT w, h: INTEGER);
	BEGIN
		w := p.w; h := p.h
	END GetSize;
	
	PROCEDURE (p: Port) NewRider* (): Rider;
		VAR h: Rider;
	BEGIN
		NEW(h); h.port := p; RETURN h
	END NewRider;
	
	PROCEDURE (p: Port) SetDC* (dc, wnd: GDI32.Handle), NEW;
		VAR res: INTEGER;
	BEGIN
		ASSERT(p.unit # 0, 20); ASSERT(dc # 0, 21);
		p.dc := dc; p.homedc := dc;
		res := GDI32.SetBkMode(dc, GDI32.Transparent);
		res := GDI32.SetTextAlign(dc, 24);
		res := GDI32.SetPolyFillMode(dc, 2);
		res := GDI32.SelectObject(dc, nullPen);
		res := GDI32.SelectObject(dc, nullBrush);
		p.wnd := wnd
	END SetDC;

	PROCEDURE (p: Port) OpenBuffer* (l, t, r, b: INTEGER);
		VAR res: INTEGER; dc: USER32.Handle; pt: USER32.Point;
	BEGIN
		ASSERT(p.dc # 0, 20);
		IF l < 0 THEN l := 0 END;
		IF t < 0 THEN t := 0 END;
		IF r > p.w THEN r := p.w END;
		IF b > p.h THEN b := p.h END;
		IF (l < r) & (t < b) THEN
			p.bl := l; p.bt := t; p.br := r; p.bb := b;
			IF ~noBuffer THEN
				dc := GDI32.CreateCompatibleDC(p.homedc);
				IF dc # 0 THEN
					IF p.wnd # 0 THEN	(* byte align bitmap to screen *)
						pt.x := l; pt.y := 0;
						res := USER32.ClientToScreen(p.wnd, pt);
						pt.x := pt.x DIV 8 * 8;
						res := USER32.ScreenToClient(p.wnd, pt);
						l := pt.x
					END;
					p.map := GDI32.CreateCompatibleBitmap(p.homedc, r - l, b - t);
					IF p.map # 0 THEN
						res := GDI32.SelectObject(dc, p.map);
						res := GDI32.SetBkMode(dc, GDI32.Transparent);
						res := GDI32.SetTextAlign(dc, 24);
						res := GDI32.SetPolyFillMode(dc, 2);
						res := GDI32.SetWindowOrgEx(dc, l, t, NIL);
						res := GDI32.SelectObject(dc, nullPen);
						res := GDI32.SelectObject(dc, nullBrush);
						p.dc := dc; p.bx := l; p.by := t;
					ELSE
						res := GDI32.DeleteDC(dc)
					END
				END
			END
		END
	END OpenBuffer;
	
	PROCEDURE (p: Port) CloseBuffer*;
		VAR res: INTEGER; rect: USER32.Rect;
	BEGIN
		IF p.map # 0 THEN
			res := GDI32.SelectClipRgn(p.homedc, 0);
			res := GDI32.BitBlt(p.homedc, p.bl, p.bt, p.br - p.bl, p.bb - p.bt, p.dc, p.bl, p.bt, copy);
			res := GDI32.DeleteDC(p.dc);
			res := GDI32.DeleteObject(p.map)
		END;
		IF p.wnd # 0 THEN
			rect.left := p.bl; rect.top := p.bt; rect.right := p.br; rect.bottom := p.bb;
			res := USER32.ValidateRect(p.wnd, rect)
		END;
		p.dc := p.homedc; p.map := 0;
		p.bx := 0; p.by := 0
	END CloseBuffer;
	

	(** Rider **)

	PROCEDURE (rd: Rider) Base* (): Ports.Port, EXTENSIBLE;
	BEGIN
		ASSERT(rd.port # NIL, 20); ASSERT(rd.port.dc # 0, 21);
		RETURN rd.port
	END Base;

	PROCEDURE (rd: Rider) SetRect* (l, t, r, b: INTEGER);
	BEGIN
		ASSERT((l <= r) & (t <= b), 20);
		ASSERT(rd.port # NIL, 21);
		rd.l := l; rd.t := t; rd.r := r; rd.b := b
	END SetRect;

	PROCEDURE (rd: Rider) GetRect* (OUT l, t, r, b: INTEGER);
	BEGIN
		l := rd.l; t := rd.t; r := rd.r; b := rd.b
	END GetRect;

	PROCEDURE SetClipRegion (rd: Rider; dc: USER32.Handle);
		VAR res, res1: INTEGER; rect: USER32.Rect; rgn: GDI32.Handle; pts: ARRAY 2 OF GDI32.Point;
	BEGIN
		IF rd.port.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
	END SetClipRegion;

	PROCEDURE (rd: Rider) InitPort* (port: Port), NEW;
	BEGIN
		ASSERT(rd.port = NIL, 20); ASSERT(port # NIL, 21); ASSERT(port.dc # 0, 22);
		rd.port := port; rd.dx := 0; rd.dy := 0
	END InitPort;

	PROCEDURE (rd: Rider) Move* (dx, dy: INTEGER);
	BEGIN
		INC(rd.dx, dx); INC(rd.dy, dy)
	END Move;

	PROCEDURE (rd: Rider) DrawRect* (l, t, r, b, s: INTEGER; col: Ports.Color);
		VAR res, h: INTEGER; p: Port; dc, oldb, oldp: USER32.Handle; pt: GDI32.Point;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port; dc := p.dc;
		IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		IF col = Ports.defaultColor THEN col := textCol END;
		IF s = 0 THEN s := 1 END;
		IF (s < 0) OR (r-l < 2*s) OR (b-t < 2*s) THEN
			INC(r); INC(b);
			IF (col # textCol) & (col # Ports.background) THEN
				IF (Dialog.platform = 11) & (p.dc = p.homedc) & (p.wnd # 0) THEN	(* win32s *)
					pt.x := 0; pt.y := 0; res := USER32.ClientToScreen(p.wnd, pt);
					res := GDI32.FixBrushOrgEx(dc, (rd.dx + pt.x) MOD 8, (rd.dy + pt.y) MOD 8, NIL)
				ELSE
					res := GDI32.SetBrushOrgEx(dc, (rd.dx - p.bx) MOD 8, (rd.dy - p.by) MOD 8, NIL)
				END
			END;
			oldb := GDI32.SelectObject(dc, GDI32.CreateSolidBrush(col));
			oldp := GDI32.SelectObject(dc, nullPen);
			res := GDI32.Rectangle(dc, l, t, r, b);
			res := GDI32.DeleteObject(GDI32.SelectObject(dc, oldb));
			res := GDI32.SelectObject(dc, oldp)
		ELSE
			h := s DIV 2; INC(l, h); INC(t, h); h := (s-1) DIV 2; DEC(r, h); DEC(b, h);
			oldb := GDI32.SelectObject(dc, nullBrush);
			oldp := GDI32.SelectObject(dc, GDI32.CreatePen(GDI32.PSSolid, s, col));
			res := GDI32.Rectangle(dc, l, t, r, b);
			res := GDI32.SelectObject(dc, oldb);
			res := GDI32.DeleteObject(GDI32.SelectObject(dc, oldp))
		END;
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
		;IF debug THEN Wait END
	END DrawRect;

	PROCEDURE (rd: Rider) DrawOval* (l, t, r, b, s: INTEGER; col: Ports.Color);
		VAR res, h: INTEGER; p: Port; dc, oldb, oldp: USER32.Handle; pt: GDI32.Point; rect: GDI32.Rect;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port; dc := p.dc;
		IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		IF col = Ports.defaultColor THEN col := textCol END;
		IF s < 0 THEN
			INC(r); INC(b);
			IF (col # textCol) & (col # Ports.background) THEN
				IF (Dialog.platform = 11) & (p.dc = p.homedc) & (p.wnd # 0) THEN	(* win32s *)
					pt.x := 0; pt.y := 0; res := USER32.ClientToScreen(p.wnd, pt);
					res := GDI32.FixBrushOrgEx(dc, (rd.dx + pt.x) MOD 8, (rd.dy + pt.y) MOD 8, NIL)
				ELSE
					res := GDI32.SetBrushOrgEx(dc, (rd.dx - p.bx) MOD 8, (rd.dy - p.by) MOD 8, NIL)
				END
			END;
			oldb := GDI32.SelectObject(dc, GDI32.CreateSolidBrush(col));
			oldp := GDI32.SelectObject(dc, nullPen);
			res := GDI32.Ellipse(dc, l, t, r, b);
			res := GDI32.DeleteObject(GDI32.SelectObject(dc, oldb));
			res := GDI32.SelectObject(dc, oldp)
		ELSE
			IF s = 0 THEN s := 1 END;
			h := s DIV 2; INC(l, h); INC(t, h); h := (s-1) DIV 2; DEC(r, h); DEC(b, h);
			oldb := GDI32.SelectObject(dc, nullBrush);
			oldp := GDI32.SelectObject(dc, GDI32.CreatePen(GDI32.PSSolid, s, col));
			res := GDI32.Ellipse(dc, l, t, r, b);
			res := GDI32.SelectObject(dc, oldb);
			res := GDI32.DeleteObject(GDI32.SelectObject(dc, oldp))
		END;
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
		;IF debug THEN Wait END
	END DrawOval;

	PROCEDURE (rd: Rider) DrawLine* (x0, y0, x1, y1, s: INTEGER; col: Ports.Color);
		VAR res: INTEGER; pt: GDI32.Point; p: Port; dc, oldb, oldp: GDI32.Handle;
	BEGIN
		ASSERT(s >= 0, 20);
		ASSERT(rd.port # NIL, 100);
		p := rd.port; dc := p.dc;
		IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		IF col = Ports.defaultColor THEN col := textCol END;
		IF s <= 0 THEN s := 1 END;
		oldp := GDI32.SelectObject(dc, GDI32.CreatePen(GDI32.PSSolid, s, col));
		res := GDI32.MoveToEx(dc, x0, y0, pt);
		res := GDI32.LineTo(dc, x1, y1);
		res := GDI32.DeleteObject(GDI32.SelectObject(dc, oldp));
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
		;IF debug THEN Wait END
	END DrawLine;
	
	PROCEDURE (rd: Rider) DrawPath* (
		IN pts: ARRAY OF Ports.Point; n, s: INTEGER; col: Ports.Color; path: INTEGER
	);

		TYPE
			PAP = POINTER TO ARRAY [1] OF GDI32.Point;

		VAR
			res, i, j, k: INTEGER; p: Port; dc, oldp, oldb: GDI32.Handle;
			pap: PAP; pt: GDI32.Point; poly: ARRAY 256 OF GDI32.Point;
			polyPtr: POINTER TO ARRAY OF Ports.Point; polyLen: INTEGER;

		PROCEDURE Bezier(x0, y0, xd0, yd0, x1, y1, xd1, yd1: INTEGER);
			VAR x, y, xd, yd, i: INTEGER;
		BEGIN
			IF ABS(x0 + xd0 - x1) + ABS(x0 + xd1 - x1) + ABS(y0 + yd0 - y1) + ABS(y0 + yd1 - y1) < 8 THEN
				IF k > polyLen - 2 THEN
					NEW(polyPtr, polyLen * 2);
					i := 0; WHILE i < polyLen DO polyPtr[i] := SYSTEM.VAL(Ports.Point, pap[i]); INC(i) END;
					polyLen := polyLen * 2; pap := SYSTEM.VAL(PAP, SYSTEM.ADR(polyPtr^))
				END;
				pap[k].x := x0; pap[k].y := y0; INC(k)
			ELSE
				x := ((xd0 - xd1) DIV 4 + x0 + x1 + 1) DIV 2;
				y := ((yd0 - yd1) DIV 4 + y0 + y1 + 1) DIV 2;
				xd := ((x1 - x0) * 3 - (xd0 + xd1) DIV 2 + 2) DIV 4;
				yd := ((y1 - y0) * 3 - (yd0 + yd1) DIV 2 + 2) DIV 4;
				Bezier(x0, y0, xd0 DIV 2, yd0 DIV 2, x, y, xd, yd);
				Bezier(x, y, xd, yd, x1, y1, xd1 DIV 2, yd1 DIV 2)
			END
		END Bezier;
	
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port; dc := p.dc;
		IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		IF col = Ports.defaultColor THEN col := textCol END;
		pap := SYSTEM.VAL(PAP, SYSTEM.ADR(pts));
		
		ASSERT(n >= 0, 20); ASSERT(n <= LEN(pts), 21);
		ASSERT(s >= Ports.fill, 23);
		IF s < 0 THEN
			IF (Dialog.platform = 11) & (p.dc = p.homedc) & (p.wnd # 0) THEN	(* win32s *)
				pt.x := 0; pt.y := 0; res := USER32.ClientToScreen(p.wnd, pt);
				res := GDI32.FixBrushOrgEx(dc, (rd.dx + pt.x) MOD 8, (rd.dy + pt.y) MOD 8, NIL)
			ELSE
				res := GDI32.SetBrushOrgEx(dc, (rd.dx - p.bx) MOD 8, (rd.dy - p.by) MOD 8, NIL)
			END;
			oldb := GDI32.SelectObject(dc, GDI32.CreateSolidBrush(col));
			oldp := GDI32.SelectObject(dc, nullPen);
			IF path = Ports.closedPoly THEN
				ASSERT(n >= 2, 20);
				res := GDI32.Polygon(dc, pap^, n)
			ELSE
				ASSERT(n >= 3, 20);
				ASSERT(path = Ports.closedBezier, 22);
				ASSERT(n MOD 3 = 0, 24);
				pap := SYSTEM.VAL(PAP, SYSTEM.ADR(poly)); polyLen := LEN(poly);
				i := 0; k := 0;
				WHILE i < n DO
					j := i+3;
					IF j = n THEN j := 0 END;
					Bezier(pts[i].x, pts[i].y, (pts[i+1].x - pts[i].x) * 3, (pts[i+1].y - pts[i].y) * 3,
							pts[j].x, pts[j].y, (pts[j].x - pts[i+2].x) * 3, (pts[j].y - pts[i+2].y) * 3);
					INC(i, 3)
				END;
				res := GDI32.Polygon(dc, pap^, k)
			END;
			res := GDI32.DeleteObject(GDI32.SelectObject(dc, oldb));
			res := GDI32.SelectObject(dc, oldp)
		ELSE
			IF s = 0 THEN s := 1 END;
			oldb := GDI32.SelectObject(dc, nullBrush);
			oldp := GDI32.SelectObject(dc, GDI32.CreatePen(GDI32.PSSolid, s, col));
			IF path = Ports.closedPoly THEN
				ASSERT(n >= 2, 20);
				res := GDI32.Polygon(dc, pap^, n)
			ELSIF path = Ports.openPoly THEN
				ASSERT(n >= 2, 20);
				res := GDI32.Polyline(dc, pap^, n)
			ELSE
				IF path = Ports.closedBezier THEN
					ASSERT(n >= 3, 20);
					ASSERT(n MOD 3 = 0, 24)
				ELSE
					ASSERT(n >= 4, 20);
					ASSERT(path = Ports.openBezier, 25);
					ASSERT(n MOD 3 = 1, 24)
				END;
				pap := SYSTEM.VAL(PAP, SYSTEM.ADR(poly)); polyLen := LEN(poly);
				i := 0;
				WHILE i < n-2 DO
					k := 0; j := i+3;
					IF j = n THEN j := 0 END;
					Bezier(pts[i].x, pts[i].y, (pts[i+1].x - pts[i].x) * 3, (pts[i+1].y - pts[i].y) * 3,
							pts[j].x, pts[j].y, (pts[j].x - pts[i+2].x) * 3, (pts[j].y - pts[i+2].y) * 3);
					pap[k].x := pts[j].x; pap[k].y := pts[j].y; INC(k);
					res := GDI32.Polyline(dc, pap^, k);
					INC(i, 3)
				END
			END;
			res := GDI32.SelectObject(dc, oldb);
			res := GDI32.DeleteObject(GDI32.SelectObject(dc, oldp))
		END;
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
		;IF debug THEN Wait END
	END DrawPath;

	PROCEDURE (rd: Rider) MarkRect* (l, t, r, b, s, mode: INTEGER; show: BOOLEAN);
		VAR res: INTEGER; p: Port; dc, old: GDI32.Handle; pt: GDI32.Point;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port; dc := p.dc;
		IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		IF (Dialog.platform = 11) & (p.dc = p.homedc) & (p.wnd # 0) THEN	(* win32s *)
			pt.x := 0; pt.y := 0; res := USER32.ClientToScreen(p.wnd, pt);
			res := GDI32.FixBrushOrgEx(dc, (rd.dx + pt.x) MOD 8, (rd.dy + pt.y) MOD 8, NIL)
		ELSE
			res := GDI32.SetBrushOrgEx(dc, (rd.dx - p.bx) MOD 8, (rd.dy - p.by) MOD 8, NIL)
		END;
		IF (mode = Ports.invert) OR (mode = Ports.hilite) THEN
			old := GDI32.SelectObject(dc, invertBrush)
		ELSIF mode = Ports.dim25 THEN
			res := GDI32.UnrealizeObject(dim25Brush); old := GDI32.SelectObject(dc, dim25Brush)
		ELSIF mode = Ports.dim50 THEN
			res := GDI32.UnrealizeObject(dim50Brush); old := GDI32.SelectObject(dc, dim50Brush)
		ELSIF mode = Ports.dim75 THEN
			res := GDI32.UnrealizeObject(dim75Brush); old := GDI32.SelectObject(dc, dim75Brush)
		ELSE (* mode = focusPat *)
			res := GDI32.UnrealizeObject(focusBrush); old := GDI32.SelectObject(dc, focusBrush)
		END;
		res := GDI32.SetTextColor(dc, Ports.black);
		
		IF l < -32768 THEN l := -32768 END;	(* ??? *)
		IF t < -32768 THEN t := -32768 END;
		IF r > 32767 THEN r := 32767 END;
		IF b > 32767 THEN b := 32767 END;
		
		IF s = 0 THEN s := 1 END;
		IF (s < 0) OR (r-l < 2*s) OR (b-t < 2*s) THEN
			res := GDI32.PatBlt(dc, l, t, r-l, b-t, xor);
		ELSE
			res := GDI32.PatBlt(dc, l, t, s, b-t, xor); DEC(r, s);
			res := GDI32.PatBlt(dc, r, t, s, b-t, xor); INC(l, s);
			res := GDI32.PatBlt(dc, l, t, r-l, s, xor); DEC(b, s);
			res := GDI32.PatBlt(dc, l, b, r-l, s, xor);
		END;
		old := GDI32.SelectObject(dc, old);
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
		;IF debug THEN Wait END
	END MarkRect;

	
	PROCEDURE (rd: Rider) Scroll* (dx, dy: INTEGER);
		VAR res: INTEGER; p: Port; dc, par: GDI32.Handle; rect, rt: GDI32.Rect; pt: GDI32.Point;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port; dc := p.dc;
(*
		IF p.wnd # 0 THEN res := USER32.UpdateWindow(p.wnd) END;
*)
		IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		rect.left := rd.l; rect.top := rd.t; rect.right := rd.r; rect.bottom := rd.b;
		res := USER32.ScrollDC(dc, dx, dy, rect, rect, grgn, rt);
		IF p.wnd # 0 THEN
			res := USER32.InvalidateRgn(p.wnd, grgn, 1);
			par := USER32.GetParent(p.wnd);
			IF (par # 0) & (USER32.GetTopWindow(par) # p.wnd) THEN
				res := USER32.UpdateWindow(p.wnd)
			END
		END;
		(* pattern origin correction *)
		INC(rd.dx, dx); INC(rd.dy, dy);
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
		;IF debug THEN Wait END
	END Scroll;


	PROCEDURE (rd: Rider) SetCursor* (cursor: INTEGER);
		VAR old: USER32.Handle;
	BEGIN
		old := USER32.SetCursor(cursors[cursor])
	END SetCursor;
	
	PROCEDURE SetMouseState* (x, y: INTEGER; but: SET; isDown: BOOLEAN);
	BEGIN
		mx := x; my := y; mb := but
	END SetMouseState;
	
	PROCEDURE (rd: Rider) Input* (OUT x, y: INTEGER; OUT modifiers: SET; OUT isDown: BOOLEAN);
		VAR msg: USER32.Message; wnd, mw: USER32.Handle; pt: USER32.Point; res: INTEGER; set: SET;
	BEGIN
		wnd := rd.port.wnd; mw := USER32.GetCapture();
		IF USER32.PeekMessageA(msg, mw, USER32.WMMouseMove, USER32.WMMButtonDblClk, 1) # 0 THEN
			mx := (msg.lParam + 32768) MOD 65536 - 32768; my := msg.lParam DIV 65536;
			IF (mw # 0) & (wnd # mw) THEN
				pt.x := mx; pt.y := my; res := USER32.ClientToScreen(mw, pt);
				res := USER32.ScreenToClient(wnd, pt); mx := pt.x; my := pt.y
			END;
			mb := {};
			set := SYSTEM.VAL(SET, msg.wParam);
			IF WinApi.MK_LBUTTON * set # {} THEN INCL(mb, left) END;
			IF WinApi.MK_MBUTTON * set # {} THEN INCL(mb, middle) END;
			IF WinApi.MK_RBUTTON * set # {} THEN INCL(mb, right) END;
			IF WinApi.MK_CONTROL * set # {} THEN INCL(mb, ctrl) END;
			IF WinApi.MK_SHIFT * set # {} THEN INCL(mb, shift) END;
			IF USER32.GetAsyncKeyState(12H) < 0 THEN INCL(mb, alt) END;
(*
			Windows.dir.Update(NIL)
*)
		END;
		IF WinApi.GetSystemMetrics(WinApi.SM_SWAPBUTTON) # 0 THEN
			IF USER32.GetAsyncKeyState(1) >= 0 THEN EXCL(mb, right) END;
			IF USER32.GetAsyncKeyState(2) >= 0 THEN EXCL(mb, left) END
		ELSE
			IF USER32.GetAsyncKeyState(1) >= 0 THEN EXCL(mb, left) END;
			IF USER32.GetAsyncKeyState(2) >= 0 THEN EXCL(mb, right) END
		END;
		IF USER32.GetAsyncKeyState(4) >= 0 THEN EXCL(mb, middle) END;
		IF WinApi.GetAsyncKeyState(WinApi.VK_SHIFT) < 0 THEN
			mb := mb + {shift, extend} ELSE  mb := mb - {shift, extend}
		END;
		IF WinApi.GetAsyncKeyState(WinApi.VK_CONTROL) < 0 THEN
			mb := mb + {ctrl, modify} ELSE  mb := mb - {ctrl, modify}
		END;
		IF WinApi.GetAsyncKeyState(WinApi.VK_MENU) < 0 THEN INCL(mb, alt) ELSE EXCL(mb, alt) END;
				
(*
		(* alt handling *)
		res := USER32.PeekMessageA(msg, 0, USER32.WMSysKeyDown, USER32.WMSysKeyDown, 1);
*)
		x := mx; y := my; modifiers := mb; isDown := mb * {left, middle, right} # {}
	END Input;
	
	PROCEDURE (rd: Rider) DrawSString* (
		x, y: INTEGER; col: Ports.Color; IN s: ARRAY OF SHORTCHAR; font: Fonts.Font
	);
		VAR res, i, a, b, c, w, u, n: INTEGER; p: Port; dc, old: GDI32.Handle; ch: SHORTCHAR;
			df: HostFonts.DevFont; dx: ARRAY 1024 OF INTEGER; s1: ARRAY 1024 OF SHORTCHAR; fsp: BOOLEAN;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		WITH font: HostFonts.Font DO
			p := rd.port; dc := p.dc; u := p.unit;
			IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
			ELSE res := GDI32.SelectClipRgn(dc, 0);
			END;
			res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
			df := font.dev;
			WHILE (df # NIL) & (df.unit # u) DO df := df.next END;
			IF df = NIL THEN HostFonts.InsertDevFont(dc, font, df, u) 
			ELSE old := GDI32.SelectObject(dc, df.id)
			END;
			IF col = Ports.defaultColor THEN col := textCol END;
			res := GDI32.SetTextColor(dc, col);
			IF df.noGap THEN INC(x) END;	(* caret pos optimization *)
			INC(x, font.ftab[ORD(s[0])] DIV u);
			a := LEN(s) - 1; n := 0; ch := s[0]; fsp := FALSE;
			WHILE (n < a) & (ch # 0X) DO
				IF ch = figureSpace THEN fsp := TRUE END;
				INC(n); ch := s[n]
			END;
			IF (df.id = font.id) & ~fsp THEN	(* native metric *)
				res := GDI32.TextOutA(dc, x, y, s, n)
			ELSE	(* adapt to meta metric *)
				a := 0; b := 0; i := 0; ch := s[0];
				WHILE i < n DO
					c := df.wtab[ORD(ch)]; INC(a, c); dx[i] := c;
					INC(b, font.wtab[ORD(ch)]);
					s1[i] := s[i];
					IF ch = figureSpace THEN s1[i] := " " END;
					INC(i); ch := s[i]
				END;
				n := i; c := b DIV u - a; i := 0; w := 0; a := 0;
				WHILE i < n DO
					INC(w, c); b := w DIV n; INC(dx[i], b - a); a := b; INC(i)
				END;
				res := GDI32.ExtTextOutA(dc, x, y, {}, NIL, s1, n, dx)
			END
		END;
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
	END DrawSString;

	PROCEDURE (rd: Rider) SCharIndex* (
		x, pos: INTEGER; IN s: ARRAY OF SHORTCHAR; font: Fonts.Font
	): INTEGER;
		VAR d, u, i, n, a, b, c, w: INTEGER; df: HostFonts.DevFont; ch: SHORTCHAR; dc: GDI32.Handle;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		WITH font: HostFonts.Font DO
			u := rd.port.unit; df := font.dev;
			WHILE (df # NIL) & (df.unit # u) DO df := df.next END;
			IF df = NIL THEN HostFonts.InsertDevFont(rd.port.dc, font, df, u) END;
			a := 0; b := 0; n := LEN(s) - 1; i := 0; ch := s[0];
			WHILE (i < n) & (ch # 0X) DO
				INC(a, df.wtab[ORD(ch)]);
				INC(b, font.wtab[ORD(ch)]);
				INC(i); ch := s[i]
			END;
			n := i; c := b DIV u - a; i := 0; w := 0; a := 0;
			INC(x, font.ftab[ORD(s[0])] DIV u);
			d := df.wtab[ORD(s[0])];
			WHILE (i < n) & (pos > x + d DIV 2) DO
				INC(w, c); b := w DIV n; INC(d, b - a); a := b;
				INC(i); INC(x, d); d := df.wtab[ORD(s[i])]
			END
		END;
		RETURN i
	END SCharIndex;

	PROCEDURE (rd: Rider) SCharPos* (
		x, index: INTEGER; IN s: ARRAY OF SHORTCHAR; font: Fonts.Font
	): INTEGER;
		VAR i, u, n, a, b, c, w: INTEGER; df: HostFonts.DevFont; ch: SHORTCHAR;
	BEGIN
		ASSERT(rd.port # NIL, 100); ASSERT(index <= LEN(s), 101);
		WITH font: HostFonts.Font DO
			u := rd.port.unit; df := font.dev;
			WHILE (df # NIL) & (df.unit # u) DO df := df.next END;
			IF df = NIL THEN HostFonts.InsertDevFont(rd.port.dc, font, df, u) END;
			a := 0; b := 0; n := LEN(s) - 1; i := 0; ch := s[0];
			WHILE (i < n) & (ch # 0X) DO
				INC(a, df.wtab[ORD(ch)]);
				INC(b, font.wtab[ORD(ch)]);
				INC(i); ch := s[i]
			END;
			n := i; c := b DIV u - a; i := 0; w := 0; a := 0;
			INC(x, font.ftab[ORD(s[0])] DIV u);
			WHILE (i < n) & (i < index) DO
				INC(w, c); b := w DIV n; INC(x, b - a); a := b;
				INC(x, df.wtab[ORD(s[i])]); INC(i)
			END
		END;
		RETURN x
	END SCharPos;

	PROCEDURE (rd: Rider) DrawString* (
		x, y: INTEGER; col: Ports.Color; IN s: ARRAY OF CHAR; font: Fonts.Font
	);
		VAR res, i, a, b, c, n, w, u: INTEGER; p: Port; dc, old: GDI32.Handle; ch: SHORTCHAR;
			str: ARRAY 1024 OF SHORTCHAR;
			df: HostFonts.DevFont; dx: ARRAY 1024 OF INTEGER; wt: ARRAY 1 OF INTEGER;
	BEGIN
		IF ~HostFonts.isUnicode THEN
			ch := 1X;
			res := KERNEL32.WideCharToMultiByte(0, {}, s, -1, str, LEN(str), ch, NIL);
			str[res] := 0X;
			rd.DrawSString(x, y, col, str, font);
			RETURN
		END;
		ASSERT(rd.port # NIL, 100);
		WITH font: HostFonts.Font DO
			p := rd.port; dc := p.dc; u := p.unit;
			IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
			ELSE res := GDI32.SelectClipRgn(dc, 0);
			END;
			res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
			IF col = Ports.defaultColor THEN col := textCol END;
			df := font.dev;
			WHILE (df # NIL) & (df.unit # u) DO df := df.next END;
			IF (df # NIL) & (df.id = font.id) THEN	(* native metric *)
				n := LEN(s) - 1; i := 0;
				WHILE (i < n) & (s[i] # 0X) DO INC(i) END;
				res := GDI32.SelectObject(dc, df.id);
				IF df.noGap THEN INC(x) END;	(* caret pos optimization *)
				res := GDI32.SetTextColor(dc, col);
				res := GDI32.TextOutW(dc, x, y, s, i)
			ELSE	(* adapt to meta metric *)
				old := GDI32.SelectObject(dc, font.id);
				a := 0; b := 0; n := LEN(s) - 1; i := 0;
				WHILE (i < n) & (s[i] # 0X) DO INC(b, font.wTab(dc, s[i])); INC(i) END;
				INC(x, font.fTab(dc, s[0]) DIV u);
				IF df = NIL THEN HostFonts.InsertDevFont(dc, font, df, u)
				ELSE res := GDI32.SelectObject(dc, df.id)
				END;
				n := i; i := 0;
				WHILE i < n DO
					res := GDI32.GetCharWidth32W(dc, ORD(s[i]), ORD(s[i]), wt);
					IF res = 0 THEN res := GDI32.GetCharWidthW(dc, ORD(s[i]), ORD(s[i]), wt) END;
					IF res # 0 THEN c := wt[0] ELSE c := df.wtab[1] END;
					INC(a, c); dx[i] := c; INC(i)
				END;
				c := b DIV u - a; i := 0; w := 0; a := 0;
				WHILE i < n DO
					INC(w, c); b := w DIV n; INC(dx[i], b - a); a := b; INC(i)
				END;
				res := GDI32.SetTextColor(dc, col);
				IF df.noGap THEN INC(x) END;	(* caret pos optimization *)
				res := GDI32.ExtTextOutW(dc, x, y, {}, NIL, s, n, dx)
			END
		END;
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
	END DrawString;

	PROCEDURE (rd: Rider) CharIndex* (x, pos: INTEGER; IN s: ARRAY OF CHAR; font: Fonts.Font): INTEGER;
		VAR res, d, u, i, a, b, c, w, n: INTEGER; ch: SHORTCHAR; str: ARRAY 1024 OF SHORTCHAR;
			df: HostFonts.DevFont; dc: USER32.Handle; wt: ARRAY 1 OF INTEGER;
	BEGIN
		IF ~HostFonts.isUnicode THEN
			ch := 1X;
			res := KERNEL32.WideCharToMultiByte(0, {}, s, -1, str, LEN(str), ch, NIL);
			str[res] := 0X;
			RETURN rd.SCharIndex(x, pos, str, font)
		END;
		ASSERT(rd.port # NIL, 100);
		dc := rd.port.dc;
		WITH font: HostFonts.Font DO
			res := GDI32.SelectObject(dc, font.id);
			u := rd.port.unit; df := font.dev;
			WHILE (df # NIL) & (df.unit # u) DO df := df.next END;
			a := 0; b := 0; n := LEN(s) - 1; i := 0;
			WHILE (i < n) & (s[i] # 0X) DO INC(b, font.wTab(dc, s[i])); INC(i) END;
			INC(x, font.fTab(dc, s[0]) DIV u);
			IF df = NIL THEN HostFonts.InsertDevFont(dc, font, df, u)
			ELSE res := GDI32.SelectObject(dc, df.id)
			END;
			n := i; i := 0;
			WHILE i < n DO
				res := GDI32.GetCharWidth32W(dc, ORD(s[i]), ORD(s[i]), wt);
				IF res = 0 THEN res := GDI32.GetCharWidthW(dc, ORD(s[i]), ORD(s[i]), wt) END;
				IF res # 0 THEN c := wt[0] ELSE c := df.wtab[1] END;
				INC(a, c); INC(i)
			END;
			c := b DIV u - a; i := 0; w := 0; a := 0;
			res := GDI32.GetCharWidth32W(dc, ORD(s[0]), ORD(s[0]), wt);
			IF res = 0 THEN res := GDI32.GetCharWidthW(dc, ORD(s[0]), ORD(s[0]), wt) END;
			IF res # 0 THEN d := wt[0] ELSE d := df.wtab[1] END;
			WHILE (i < n) & (pos > x + d DIV 2) DO
				INC(w, c); b := w DIV n; INC(d, b - a); a := b;
				INC(i); INC(x, d);
				res := GDI32.GetCharWidth32W(dc, ORD(s[i]), ORD(s[i]), wt);
				IF res = 0 THEN res := GDI32.GetCharWidthW(dc, ORD(s[i]), ORD(s[i]), wt) END;
				IF res # 0 THEN d := wt[0] ELSE d := df.wtab[1] END;
			END
		END;
		RETURN i
	END CharIndex;

	PROCEDURE (rd: Rider) CharPos* (x, index: INTEGER; IN s: ARRAY OF CHAR; font: Fonts.Font): INTEGER;
		VAR res, i, u, a, b, c, w, d, n: INTEGER; ch: SHORTCHAR; str: ARRAY 1024 OF SHORTCHAR;
			df: HostFonts.DevFont; dc: USER32.Handle; wt: ARRAY 1 OF INTEGER;
	BEGIN
		IF ~HostFonts.isUnicode THEN
			ch := 1X;
			res := KERNEL32.WideCharToMultiByte(0, {}, s, -1, str, LEN(str), ch, NIL);
			str[res] := 0X;
			RETURN rd.SCharPos(x, index, str, font)
		END;
		ASSERT(rd.port # NIL, 100); ASSERT(index <= LEN(s), 101);
		dc := rd.port.dc;
		WITH font: HostFonts.Font DO
			res := GDI32.SelectObject(dc, font.id);
			u := rd.port.unit; df := font.dev;
			WHILE (df # NIL) & (df.unit # u) DO df := df.next END;
			a := 0; b := 0; n := LEN(s) - 1; i := 0;
			WHILE (i < n) & (s[i] # 0X) DO INC(b, font.wTab(dc, s[i])); INC(i) END;
			INC(x, font.fTab(dc, s[0]) DIV u);
			IF df = NIL THEN HostFonts.InsertDevFont(dc, font, df, u)
			ELSE res := GDI32.SelectObject(dc, df.id)
			END;
			n := i; i := 0;
			WHILE i < n DO
				res := GDI32.GetCharWidth32W(dc, ORD(s[i]), ORD(s[i]), wt);
				IF res = 0 THEN res := GDI32.GetCharWidthW(dc, ORD(s[i]), ORD(s[i]), wt) END;
				IF res # 0 THEN c := wt[0] ELSE c := df.wtab[1] END;
				INC(a, c); INC(i)
			END;
			c := b DIV u - a; i := 0; w := 0; a := 0;
			WHILE (i < n) & (i < index) DO
				INC(w, c); b := w DIV n; INC(x, b - a); a := b;
				res := GDI32.GetCharWidth32W(dc, ORD(s[i]), ORD(s[i]), wt);
				IF res = 0 THEN res := GDI32.GetCharWidthW(dc, ORD(s[i]), ORD(s[i]), wt) END;
				IF res # 0 THEN d := wt[0] ELSE d := df.wtab[1] END;
				INC(x, d); INC(i)
			END
		END;
		RETURN x
	END CharPos;
	
	PROCEDURE (rd: Rider) SaveRect* (l, t, r, b: INTEGER; VAR res: INTEGER);
		VAR rs: INTEGER; p: Port;
	BEGIN
		res := 1; p := rd.port;
		ASSERT(p.dc # 0, 20);
		IF l < 0 THEN l := 0 END;
		IF t < 0 THEN t := 0 END;
		IF r > p.w THEN r := p.w END;
		IF b > p.h THEN b := p.h END;
		IF (l < r) & (t < b) THEN
			rd.sl := l; rd.st := t; rd.sr := r; rd.sb := b;
			rd.dc := GDI32.CreateCompatibleDC(p.dc);
			IF rd.dc # 0 THEN
				rd.map := GDI32.CreateCompatibleBitmap(p.dc, r - l, b - t);
				IF rd.map # 0 THEN
					rs := GDI32.SelectObject(rd.dc, rd.map);
					rs := GDI32.BitBlt(rd.dc, 0, 0, r - l, b - t, p.dc, l, t, copy);
					res := 0
				ELSE
					rs := GDI32.DeleteDC(rd.dc); rd.dc := 0
				END
			END
		END
	END SaveRect;
	
	PROCEDURE (rd: Rider) RestoreRect* (l, t, r, b: INTEGER; dispose: BOOLEAN);
		VAR res: INTEGER; p: Port; dc: GDI32.Handle;
	BEGIN
		IF rd.dc # 0 THEN
			p := rd.port; dc := p.dc;
			IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
			ELSE res := GDI32.SelectClipRgn(dc, 0);
			END;
			res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
			IF l < rd.sl THEN l := rd.sl END;
			IF t < rd.st THEN t := rd.st END;
			IF r > rd.sr THEN r := rd.sr END;
			IF b > rd.sb THEN b := rd.sb END;
			res := GDI32.BitBlt(dc, l, t, r - l, b - t, rd.dc, l - rd.sl, t - rd.st, copy);
			IF dispose THEN
				res := GDI32.DeleteDC(rd.dc);
				res := GDI32.DeleteObject(rd.map);
				rd.dc := 0; rd.map := 0
			END;
			IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
		END
	END RestoreRect;
	
	PROCEDURE (rd: Rider) CopyFrom* (sdc: GDI32.Handle; x, y: INTEGER), NEW;
		VAR res: INTEGER; p: Port; dc: GDI32.Handle;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port; dc := p.dc;
		IF p.wnd = 0 THEN res := GDI32.SaveDC(dc)
		ELSE res := GDI32.SelectClipRgn(dc, 0);
		END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		res := GDI32.BitBlt(dc, rd.l, rd.t, rd.r - rd.l, rd.b - rd.t, sdc, x, y, copy);
		IF p.wnd = 0 THEN res := GDI32.RestoreDC(dc, -1) END
	END CopyFrom;
	
	PROCEDURE (rd: Rider) DrawBitmap* (bmdc: GDI32.Handle; bw, bh, x, y, w, h: INTEGER), NEW;
		VAR res, u: INTEGER; p: Port; dc: GDI32.Handle;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port;
		dc := p.dc; u := p.unit;
		res := GDI32.SaveDC(dc);
		IF p.wnd # 0 THEN res := GDI32.SelectClipRgn(dc, 0) END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		IF (bw * u = w) & (bh * u = h) THEN
			res := GDI32.BitBlt(dc, x DIV u, y DIV u, bw, bh, bmdc, 0, 0, copy)
		ELSE
			res := GDI32.StretchBlt(dc, x DIV u, y DIV u, w DIV u, h DIV u, bmdc, 0, 0, bw, bh, copy)
		END;
		res := GDI32.RestoreDC(dc, -1)
	END DrawBitmap;
	
	PROCEDURE (rd: Rider) DrawMetafile* (mf: GDI32.Handle; mode, x, y, w, h: INTEGER), NEW;
		VAR res, oldMode, u: INTEGER; p: Port; dc: GDI32.Handle;
	BEGIN
		ASSERT(rd.port # NIL, 100);
		p := rd.port;
		p.CloseBuffer;
		dc := p.dc; u := p.unit;
		res := GDI32.SaveDC(dc);
		IF p.wnd # 0 THEN res := GDI32.SelectClipRgn(dc, 0) END;
		res := GDI32.IntersectClipRect(dc, rd.l, rd.t, rd.r, rd.b);
		oldMode := GDI32.SetMapMode(dc, mode);
		res := GDI32.SetViewportOrgEx(dc, x DIV u, y DIV u, NIL);
		res := GDI32.SetViewportExtEx(dc, w DIV u, h DIV u, NIL);
		res := GDI32.SetTextAlign(dc, 0);
		res := GDI32.PlayMetaFile(dc, mf);
		res := GDI32.SetViewportOrgEx(dc, 0, 0, NIL);
		res := GDI32.SetMapMode(dc, oldMode);
		res := GDI32.RestoreDC(dc, -1)
	END DrawMetafile;
	
	PROCEDURE (rd: Rider) FixOrigin*, NEW;
		VAR p: Port; res: INTEGER; pt: GDI32.Point;
	BEGIN
		p := rd.port;
		IF (Dialog.platform = 11) & (p.dc = p.homedc) & (p.wnd # 0) THEN	(* win32s *)
			pt.x := 0; pt.y := 0; res := USER32.ClientToScreen(p.wnd, pt);
			res := GDI32.FixBrushOrgEx(p.dc, (rd.dx + pt.x) MOD 8, (rd.dy + pt.y) MOD 8, NIL)
		ELSE
			res := GDI32.SetBrushOrgEx(p.dc, (rd.dx - p.bx) MOD 8, (rd.dy - p.by) MOD 8, NIL)
		END
	END FixOrigin;

	
	(** miscellaneous **)

	PROCEDURE ResetColors*;
	BEGIN
		Ports.background := USER32.GetSysColor(5);
		textCol := USER32.GetSysColor(8);
		selBackground := USER32.GetSysColor(13);
		selTextCol := USER32.GetSysColor(14);
		Ports.dialogBackground := USER32.GetSysColor(15);
		dialogTextCol := USER32.GetSysColor(18);
		dialogShadowCol := USER32.GetSysColor(16);
		dialogLightCol := USER32.GetSysColor(20);
	END ResetColors;
	
	PROCEDURE SetPrinterColors*;
	BEGIN
		Ports.background := Ports.white;
		textCol := Ports.black;
		selBackground := Ports.white;
		selTextCol := Ports.black;
		Ports.dialogBackground := Ports.white
	END SetPrinterColors;

	PROCEDURE ToggleDebug*;
	BEGIN
		debug := ~debug; noBuffer := debug
	END ToggleDebug;
	
	PROCEDURE ToggleBuffer*;
	BEGIN
		noBuffer := ~noBuffer
	END ToggleBuffer;
	
	PROCEDURE Init;
		VAR i: INTEGER; instance, bm: KERNEL32.Handle; pat: ARRAY 12 OF SHORTINT;
	BEGIN
		instance := KERNEL32.GetModuleHandleA(NIL);
		ResetColors;
		grgn := GDI32.CreateRectRgn(0, 0, 0, 0);
		nullBrush := GDI32.GetStockObject(GDI32.NullBrush);
		nullPen := GDI32.GetStockObject(GDI32.NullPen);
		cursors[Ports.arrowCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCArrow));
		cursors[Ports.textCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCIBeam));
		cursors[Ports.graphicsCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCCross));
		cursors[Ports.bitmapCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCCross));
		cursors[Ports.tableCursor] := USER32.LoadCursorA(instance, USER32.MakeIntRsrc(7));
		IF cursors[Ports.tableCursor] = 0 THEN cursors[Ports.tableCursor] := cursors[Ports.graphicsCursor] END;
		cursors[Ports.refCursor] := USER32.LoadCursorA(instance, USER32.MakeIntRsrc(6));
		cursors[resizeHCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCSizeWE));
		cursors[resizeVCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCSizeNS));
		cursors[resizeLCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCSizeNWSE));
		cursors[resizeRCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCSizeNESW));
		cursors[resizeCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCSizeAll));
		cursors[busyCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCWait));
		cursors[stopCursor] := USER32.LoadCursorA(0, USER32.MakeIntRsrc(USER32.IDCNo));
		cursors[moveCursor] := USER32.LoadCursorA(instance, USER32.MakeIntRsrc(1));
		cursors[copyCursor] := USER32.LoadCursorA(instance, USER32.MakeIntRsrc(2));
		cursors[linkCursor] := USER32.LoadCursorA(instance, USER32.MakeIntRsrc(3));
		cursors[pickCursor] := USER32.LoadCursorA(instance, USER32.MakeIntRsrc(4));
		IF cursors[stopCursor] = 0 THEN
			cursors[stopCursor] := USER32.LoadCursorA(instance, USER32.MakeIntRsrc(5))
		END;
		i := 0;
		WHILE i < LEN(cursors) DO
			IF cursors[i] = 0 THEN cursors[i] := cursors[Ports.arrowCursor] END;
			INC(i)
		END;
		pat[0] := 0EEH; pat[1] := 0DDH; pat[2] := 0BBH; pat[3] := 077H;
		pat[4] := 0EEH; pat[5] := 0DDH; pat[6] := 0BBH; pat[7] := 077H;
		bm := GDI32.CreateBitmap(8, 8, 1, 1, SYSTEM.ADR(pat));
		focusBrush := GDI32.CreatePatternBrush(bm);
		pat[0] := 0EEH; pat[1] := 0BBH; pat[2] := 0DDH; pat[3] := 077H;
		pat[4] := 0EEH; pat[5] := 0BBH; pat[6] := 0DDH; pat[7] := 077H;
		bm := GDI32.CreateBitmap(8, 8, 1, 1, SYSTEM.ADR(pat));
		dim25Brush := GDI32.CreatePatternBrush(bm);
		pat[0] := 0AAH; pat[1] := 055H; pat[2] := 0AAH; pat[3] := 055H;
		pat[4] := 0AAH; pat[5] := 055H; pat[6] := 0AAH; pat[7] := 055H;
		bm := GDI32.CreateBitmap(8, 8, 1, 1, SYSTEM.ADR(pat));
		dim50Brush := GDI32.CreatePatternBrush(bm);
		pat[0] := 011H; pat[1] := 044H; pat[2] := 022H; pat[3] := 088H;
		pat[4] := 011H; pat[5] := 044H; pat[6] := 022H; pat[7] := 088H;
		bm := GDI32.CreateBitmap(8, 8, 1, 1, SYSTEM.ADR(pat));
		dim75Brush := GDI32.CreatePatternBrush(bm);
		invertBrush := GDI32.GetStockObject(GDI32.BlackBrush);
	END Init;

BEGIN
	Init
END HostPorts.
