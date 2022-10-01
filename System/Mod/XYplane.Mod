MODULE XYplane;
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

	IMPORT Ports, Stores, Views, Properties, HostPorts, HostWindows, GDI32, USER32;

	CONST
		erase* = 0; draw* = 1;
		maxW = 256; maxH = 256;

	TYPE
		View = POINTER TO RECORD (Views.View)
			dc: GDI32.Handle;
			map: GDI32.Handle
		END;

	VAR
		X*, Y*, W*, H*: INTEGER;
		current: View;
		frame: Views.Frame;

	PROCEDURE (v: View) FINALIZE;
		VAR res: INTEGER;
	BEGIN
		res := GDI32.DeleteDC(v.dc);
		res := GDI32.DeleteObject(v.map);
		v.dc := 0; v.map := 0
	END FINALIZE;

	PROCEDURE Open*;
		VAR res: INTEGER; v: View; dc: GDI32.Handle;
	BEGIN
		NEW(v);
		dc := USER32.GetDC(0);
		v.dc := GDI32.CreateCompatibleDC(dc);
		v.map := GDI32.CreateCompatibleBitmap(dc, W, H);
		res := GDI32.SelectObject(v.dc, v.map);
		res := USER32.ReleaseDC(0, dc);
		res := GDI32.SelectObject(v.dc, GDI32.GetStockObject(GDI32.WhiteBrush));
		res := GDI32.SelectObject(v.dc, GDI32.GetStockObject(GDI32.NullPen));
		res := GDI32.Rectangle(v.dc, 0, 0, W + 1, H + 1);
		Views.OpenAux(v, "XYplane");
		current := v
	END Open;

	PROCEDURE Dot* (x, y, mode: INTEGER);
		VAR res, u: INTEGER; p: HostPorts.Port; col: Ports.Color;
	BEGIN
		IF (x >= 0) & (x < maxW) & (y >= 0) & (y < maxH) THEN
			y := maxH - 1 - y;
			IF mode = draw THEN col := Ports.black ELSE col := Ports.white END;
			res := GDI32.SetPixel(current.dc, x, y, col);
			IF (frame # NIL) & (frame.rider # NIL) THEN
				u := frame.unit; p := frame.rider(HostPorts.Rider).port;
				res := GDI32.SetPixel(p.dc, frame.gx DIV u + x, frame.gy DIV u + y, col);
				IF res = -1 THEN
					frame.DrawRect(x * u, y * u, (x + 1) * u, (y + 1) * u, Ports.fill, col)
				END
			END
		END
	END Dot;

	PROCEDURE IsDot* (x, y: INTEGER): BOOLEAN;
	BEGIN
		RETURN GDI32.GetPixel(current.dc, x, maxH - 1 - y) # Ports.white
	END IsDot;

	PROCEDURE ReadKey* (): CHAR;
		VAR res: INTEGER; msg: USER32.Message;
	BEGIN
		IF USER32.PeekMessageA(msg, 0, USER32.WMKeyDown, USER32.WMChar, 1) # 0 THEN
			IF msg.message = USER32.WMChar THEN
				RETURN CHR(msg.wParam)
			ELSE
				res := USER32.TranslateMessage(msg);
				res := USER32.DispatchMessageA(msg)
			END
		END;
		RETURN 0X
	END ReadKey;

	PROCEDURE Clear*;
		VAR res: INTEGER;
	BEGIN
		res := GDI32.Rectangle(current.dc, 0, 0, W + 1, H + 1);
		Views.Update(current, Views.keepFrames)
	END Clear;


	PROCEDURE (v: View) Internalize (VAR rd: Stores.Reader);
		VAR version: INTEGER; res, x, y, i: INTEGER; dc: GDI32.Handle; s: SET;
	BEGIN
		v.Internalize^(rd);
		IF ~rd.cancelled THEN
			rd.ReadVersion(0, 0, version);
			IF ~rd.cancelled THEN
				dc := USER32.GetDC(0);
				v.dc := GDI32.CreateCompatibleDC(dc);
				v.map := GDI32.CreateCompatibleBitmap(dc, W, H);
				res := GDI32.SelectObject(v.dc, v.map);
				res := USER32.ReleaseDC(0, dc);
				res := GDI32.SelectObject(v.dc, GDI32.GetStockObject(GDI32.WhiteBrush));
				res := GDI32.SelectObject(v.dc, GDI32.GetStockObject(GDI32.NullPen));
				res := GDI32.Rectangle(v.dc, 0, 0, W + 1, H + 1);
				y := 0;
				WHILE y < maxH DO
					x := 0;
					WHILE x < maxW DO
						rd.ReadSet(s); i := 0;
						WHILE i < 32 DO
							IF i IN s THEN res := GDI32.SetPixel(v.dc, x, y, Ports.black) END;
							INC(i); INC(x)
						END
					END;
					INC(y)
				END
			END
		END
	END Internalize;

	PROCEDURE (v: View) Externalize (VAR wr: Stores.Writer);
		VAR x, y, i: INTEGER; s: SET;
	BEGIN
		v.Externalize^(wr);
		wr.WriteVersion(0);
		y := 0;
		WHILE y < maxH DO
			x := 0;
			WHILE x < maxW DO
				i := 0; s := {};
				WHILE i < 32 DO
					IF GDI32.GetPixel(v.dc, x, y) # Ports.white THEN INCL(s, i) END;
					INC(i); INC(x)
				END;
				wr.WriteSet(s)
			END;
			INC(y)
		END
	END Externalize;

	PROCEDURE (v: View) CopyFromSimpleView (source: Views.View);
		VAR res: INTEGER;
	BEGIN
		WITH source: View DO v.dc := source.dc; 
			v.dc := GDI32.CreateCompatibleDC(source.dc);
			v.map := GDI32.CreateCompatibleBitmap(source.dc, W, H);
			res := GDI32.SelectObject(v.dc, v.map);
			res := GDI32.BitBlt(v.dc, 0, 0, W, H, source.dc, 0, 0, 00CC0020H)
		END
	END CopyFromSimpleView;

	PROCEDURE (v: View) Restore (f: Views.Frame; l, t, r, b: INTEGER);
		VAR rd: HostPorts.Rider; x, y, u, rl, rt, rr, rb: INTEGER;
	BEGIN
		rd := f.rider(HostPorts.Rider);
		IF rd.port.wnd # 0 THEN	(* copy to screen *)
			frame := f;
			f.rider.GetRect(rl, rt, rr, rb);
			rd.CopyFrom(v.dc, rl - f.gx DIV f.unit, rt - f.gy DIV f.unit)
		ELSE	(* copy to printer *)
			u := HostWindows.unit; y := 0;
			WHILE y < maxH DO
				x := 0;
				WHILE x < maxW DO
					IF GDI32.GetPixel(v.dc, x, y) # Ports.white THEN
						f.DrawRect(x * u, y * u, (x + 1) * u, (y + 1) * u, Ports.fill, Ports.black)
					END;
					INC(x)
				END;
				INC(y)
			END
		END
	END Restore;
	
	PROCEDURE (v: View) HandlePropMsg (VAR msg: Properties.Message);
	BEGIN
		WITH msg: Properties.SizePref DO
			msg.w := W * HostWindows.unit;
			msg.h := H * HostWindows.unit
		| msg: Properties.ResizePref DO
			msg.fixed := TRUE
		ELSE
		END
	END HandlePropMsg;
	
BEGIN
	X := 0; Y := 0; W := maxW; H := maxH
END XYplane.
