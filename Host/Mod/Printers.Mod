MODULE HostPrinters;
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
		SYSTEM, KERNEL32, GDI32, USER32, COMDLG32,
		Kernel, Files, Dialog, Ports, HostPorts, Stores, Models, Views, Controllers,
		Properties, Printers, Printing, Documents, Windows, HostWindows;
	
	CONST
		eduMsgH = 30 * Ports.point;

		dialogCommand = "StdCmds.OpenToolDialog('HostPrinters.printing', '#Host:Print')";
	
	TYPE
		Printer = POINTER TO RECORD (Printers.Printer)
			w, h: INTEGER;
			(* port: HostPorts.Port;	(* port to which forwarding occurs *) *)
			devNames, devMode: GDI32.Handle;	(* printer description *)
			clean: TrapCleaner;
			cancel: Windows.Window	(* cancel dialog *)
		END;

(*
		Rider = POINTER TO RECORD (HostPorts.Rider)
			p: Printer
		END;
*)
		Directory = POINTER TO RECORD (Printers.Directory) END;
		
		TrapCleaner = POINTER TO RECORD (Kernel.TrapCleaner)
			p: Printer
		END;


	VAR
		printing*: RECORD
			pnum-: INTEGER;
			Cancel*: PROCEDURE
		END;

		dir: Directory;
		current: Printers.Printer;
		aborted: BOOLEAN;

		sa, sb, sc: ARRAY 64 OF CHAR;
		err: INTEGER;


	PROCEDURE PrinterDC (devNames, devMode: GDI32.Handle): GDI32.Handle;
		VAR adr: INTEGER; i: SHORTINT; a, b, c: GDI32.StringPtr; dc: GDI32.Handle; dm: GDI32.DevModePtr;
	BEGIN
		adr := KERNEL32.GlobalLock(devNames);
		dm := SYSTEM.VAL(GDI32.DevModePtr, KERNEL32.GlobalLock(devMode));
		SYSTEM.GET(adr + 0, i); a := SYSTEM.VAL(GDI32.StringPtr, adr + i);
		SYSTEM.GET(adr + 2, i); b := SYSTEM.VAL(GDI32.StringPtr, adr + i);
		SYSTEM.GET(adr + 4, i); c := SYSTEM.VAL(GDI32.StringPtr, adr + i);
		dc := GDI32.CreateDCA(a, b, c, dm^);
		IF dc = 0 THEN dc := GDI32.CreateDCA(a, b, c, NIL) END;
		adr := KERNEL32.GlobalUnlock(devMode);
		adr := KERNEL32.GlobalUnlock(devNames);
		RETURN dc
	END PrinterDC;
(*
	PROCEDURE GetPaperSize (id, orient: LONGINT; VAR w, h: LONGINT);
		VAR x, y: LONGINT;
	BEGIN
		CASE id OF
		| 1, 2, 18: x := 17 * Ports.inch DIV 2; y := 11 * Ports.inch
		| 3, 4: x := 11 * Ports.inch; y := 17 * Ports.inch
		| 5: x := 17 * Ports.inch DIV 2; y := 14 * Ports.inch
		| 6: x := 11 * Ports.inch DIV 2; y := 17 * Ports.inch DIV 2
		| 7: x := 29 * Ports.inch DIV 4; y := 21 * Ports.inch DIV 2
		| 8: x := 297 * Ports.mm; y := 420 * Ports.mm
		| 9, 10: x := 210 * Ports.mm; y := 297 * Ports.mm
		| 11: x := 148 * Ports.mm; y := 210 * Ports.mm
		| 12: x := 250 * Ports.mm; y := 354 * Ports.mm
		| 13: x := 182 * Ports.mm; y := 257 * Ports.mm
		| 14, 41: x := 17 * Ports.inch DIV 2; y := 13 * Ports.inch
		| 15: x := 215 * Ports.mm; y := 275 * Ports.mm
		| 16: x := 10 * Ports.inch; y := 14 * Ports.inch
		| 17: x := 11 * Ports.inch; y := 17 * Ports.inch
		| 19: x := 31 * Ports.inch DIV 8; y := 71 * Ports.inch DIV 8
		| 20: x := 33 * Ports.inch DIV 8; y := 19 * Ports.inch DIV 2
		| 21: x := 9 * Ports.inch DIV 2; y := 83 * Ports.inch DIV 8
		| 22: x := 19 * Ports.inch DIV 4; y := 11 * Ports.inch
		| 23: x := 5 * Ports.inch; y := 23 * Ports.inch DIV 2
		| 24: x := 17 * Ports.inch; y := 22 * Ports.inch
		| 25: x := 22 * Ports.inch; y := 34 * Ports.inch
		| 26: x := 34 * Ports.inch; y := 44 * Ports.inch
		| 27: x := 110 * Ports.mm; y := 220 * Ports.mm
		| 28: x := 162 * Ports.mm; y := 229 * Ports.mm
		| 29: x := 324 * Ports.mm; y := 458 * Ports.mm
		| 30: x := 229 * Ports.mm; y := 324 * Ports.mm
		| 31: x := 114 * Ports.mm; y := 162 * Ports.mm
		| 32: x := 114 * Ports.mm; y := 229 * Ports.mm
		| 33: x := 250 * Ports.mm; y := 353 * Ports.mm
		| 34: x := 176 * Ports.mm; y := 250 * Ports.mm
		| 35: x := 125 * Ports.mm; y := 176 * Ports.mm
		| 36: x := 110 * Ports.mm; y := 230 * Ports.mm
		| 37: x := 31 * Ports.inch DIV 8; y := 15 * Ports.inch DIV 2
		| 38: x := 29 * Ports.inch DIV 8; y := 13 * Ports.inch DIV 2
		| 39: x := 119 * Ports.inch DIV 8; y := 11 * Ports.inch
		| 40: x := 17 * Ports.inch DIV 2; y := 12 * Ports.inch
		ELSE orient := 0
		END;
		IF orient = 1 THEN w := x; h := y
		ELSIF orient = 2 THEN w := y; h := x
		END
	END GetPaperSize;
*)
	PROCEDURE NewPrinter* (devNames, devMode: GDI32.Handle): Printers.Printer;
		VAR p: Printer; res, w, h, pw, ph, nx, ny, unit, ux, uy: INTEGER;
			dc: GDI32.Handle; m: GDI32.DevModePtr; pt: GDI32.Point;
			port: HostPorts.Port;
	BEGIN
		ASSERT(devNames # 0, 20);
		dc := PrinterDC(devNames, devMode);
		IF dc # 0 THEN
			NEW(p);
			p.devNames := devNames; p.devMode := devMode;
			w := GDI32.GetDeviceCaps(dc, GDI32.HorzRes);
			h := GDI32.GetDeviceCaps(dc, GDI32.VertRes);
			nx := GDI32.GetDeviceCaps(dc, GDI32.LogPixelsX);
			ny := GDI32.GetDeviceCaps(dc, GDI32.LogPixelsY);
			ux := (Ports.inch + nx DIV 2) DIV nx;
			uy := (Ports.inch + ny DIV 2) DIV ny;
			unit := ux;
			IF nx < ny THEN
(*
				res := GDI32.SetMapMode(dc, 8);	(* anisotropic *)
				res := GDI32.SetWindowExtEx(dc, 1, nx, NIL);	(* does not scale fonts correctly !!! *)
				res := GDI32.SetViewportExtEx(dc, 1, ny, NIL);
*)
				h := h * nx DIV ny
			ELSIF nx > ny THEN
(*
				res := GDI32.SetMapMode(dc, 8);	(* anisotropic *)
				res := GDI32.SetWindowExtEx(dc, ny, 1, NIL);	(* does not scale fonts correctly !!! *)
				res := GDI32.SetViewportExtEx(dc, nx, 1, NIL);
*)
				w := w * ny DIV nx; unit := uy
			END;
(*
			m := SYSTEM.VAL(GDI32.DevModePtr, KERNEL32.GlobalLock(devMode));
			wu := w * unit; hu := h * unit; pw := wu; ph := hu;	(* port as default *)
			GetPaperSize(m.paperSize, m.orientation, pw, ph);
			res := KERNEL32.GlobalUnlock(devMode);
			IF pw < wu THEN pw := wu END;
			IF ph < hu THEN ph := hu END;
*)
			pw := GDI32.GetDeviceCaps(dc, GDI32.PhysicalWidth);
			ph := GDI32.GetDeviceCaps(dc, GDI32.PhysicalHeight);
			IF (pw = 0) OR (ph = 0) THEN
				res := GDI32.Escape(dc, 12, 0, NIL, pt);
				ASSERT(res > 0, 100);
				pw := pt.x; ph := pt.y
			END;
			pw := pw * ux; ph := ph * uy;
			nx := GDI32.GetDeviceCaps(dc, GDI32.PhysicalOffsetX);
			ny := GDI32.GetDeviceCaps(dc, GDI32.PhysicalOffsetY);
			IF (nx = 0) OR (ny = 0) THEN
				res := GDI32.Escape(dc, 13, 0, NIL, pt);
				ASSERT(res > 0, 100);
				nx := pt.x; ny := pt.y
			END;
			nx := nx * ux; ny := ny * uy;
			(*
			p.Init(unit);
			p.SetSize(w, h);
			*)
			p.InitPrinter(-nx, -ny, pw - nx, ph - ny);
			NEW(port); p.InitPort(port);
			port.Init(unit, Ports.printer);
			port.SetSize(w, h);
			res := GDI32.DeleteDC(dc)
		ELSE p := NIL
		END;
		RETURN p
	END NewPrinter;
	
	PROCEDURE SetCurrent* (devNames, devMode: GDI32.Handle);	(* used in HostDialog *)
	BEGIN
		IF devNames # 0 THEN
			current := NewPrinter(devNames, devMode)
		END;
	END SetCurrent;
	
	PROCEDURE GetPage* (p: Printers.Printer; VAR w, h: INTEGER);
		VAR l, t, r, b: INTEGER;
	BEGIN
		WITH p: Printer DO
			p.GetRect(l, t, r, b);
			w := r - l;
			h := b - t
		END
	END GetPage;


	PROCEDURE Error (res: INTEGER): INTEGER;
	BEGIN
		IF res = -1 THEN res := KERNEL32.GetLastError()
		ELSIF aborted THEN res := 1
		ELSE res := 0
		END;
		RETURN res
	END Error;
	
	PROCEDURE Cancel;
	BEGIN
		aborted := TRUE
	END Cancel;
	
	PROCEDURE [2] AbortHandler (dc: GDI32.Handle; error: INTEGER): INTEGER;
		VAR res: INTEGER; msg: USER32.Message; s: ARRAY 32 OF CHAR;
	BEGIN
		WHILE USER32.PeekMessageA(msg, 0, 0, 0, 1) # 0 DO
			res := USER32.TranslateMessage(msg);
(*
			IF msg.message = USER32.WMPaint THEN
				res := USER32.GetClassNameA(msg.wnd, s, LEN(s));
				IF (s # "Oberon Doc") & (s # "Oberon Aux") THEN
					res := USER32.DispatchMessageA(msg)
				END
			ELSE
				res := USER32.DispatchMessageA(msg)
			END
*)
			res := USER32.DispatchMessageA(msg)
		END;
		IF aborted THEN RETURN 0 ELSE RETURN 1 END
	END AbortHandler;
	
	PROCEDURE (c: TrapCleaner) Cleanup;
		VAR res: INTEGER; p: Printer;
	BEGIN
		p := c.p;
		res := GDI32.AbortDoc(p.ThisPort()(HostPorts.Port).dc);
		res := GDI32.DeleteDC(p.ThisPort()(HostPorts.Port).dc);
		res := USER32.EnableWindow(HostWindows.main, 1);
		HostPorts.ResetColors;
		IF p.cancel # NIL THEN Windows.dir.Close(p.cancel); p.cancel := NIL END
	END Cleanup;


	(* Printer *)
(*
	PROCEDURE (p: Printer) NewRider (): Rider;
		VAR r: Rider;
	BEGIN
		ASSERT(p.port # NIL, 20); ASSERT(p.port.dc # 0, 21);
		NEW(r); r.p := p; r.InitPort(p.port); 
		RETURN r
	END NewRider;
*)
	PROCEDURE (p: Printer) OpenJob (VAR copies: INTEGER; name: ARRAY OF CHAR);
		VAR res: INTEGER; info: GDI32.DocInfo; s: Stores.Store; sn: ARRAY 256 OF SHORTCHAR;
			port: HostPorts.Port;
	BEGIN
		aborted := FALSE; copies := 1;
		port := p.ThisPort()(HostPorts.Port);
		port.SetDC(PrinterDC(p.devNames, p.devMode), 0);
		p.res := Error(GDI32.SetAbortProc(port.dc, AbortHandler));
		IF p.res = 0 THEN
			(* open cancel dialog *)
			printing.pnum := 0;
			HostWindows.dir.unmoveable := TRUE;
			Dialog.Call(dialogCommand, " ", res);
			HostWindows.dir.unmoveable := FALSE;
			p.cancel := Windows.dir.First();
			(* install trap cleaner *)
			NEW(p.clean); p.clean.p := p;
			Kernel.PushTrapCleaner(p.clean);
			(* start printing *)
			info.size := SIZE(GDI32.DocInfo);
			sn := SHORT(name$);
			info.docName := sn;
			info.output := NIL;
			p.res := Error(GDI32.StartDocA(port.dc, info));
			HostPorts.SetPrinterColors;
			res := USER32.EnableWindow(HostWindows.main, 0)
		END;
		port.SetDC(port.dc, 0)	(* reinitialize dc *)
	END OpenJob;

	PROCEDURE (p: Printer) CloseJob;
		VAR res: INTEGER; port: HostPorts.Port;
	BEGIN
		port := p.ThisPort()(HostPorts.Port);
		IF aborted THEN p.res := Error(GDI32.AbortDoc(port.dc))
		ELSE p.res := Error(GDI32.EndDoc(port.dc))
		END;
		res := GDI32.DeleteDC(port.dc);
		res := USER32.EnableWindow(HostWindows.main, 1);
		HostPorts.ResetColors;
		IF p.cancel # NIL THEN Windows.dir.Close(p.cancel); p.cancel := NIL END;
		Kernel.PopTrapCleaner(p.clean)
	END CloseJob;
	
	PROCEDURE (p: Printer) OpenPage;
		VAR res: INTEGER; port: HostPorts.Port;
	BEGIN
		port := p.ThisPort()(HostPorts.Port);
		IF ~aborted THEN p.res := Error(GDI32.StartPage(port.dc)) END;
		printing.pnum := Printing.Current() (* Printing.par.page.current *) + 1;
		Dialog.Update(printing);
		res := USER32.UpdateWindow(p.cancel(HostWindows.Window).wnd);
		port.SetDC(port.dc, 0)	(* reinitialize dc *)
	END OpenPage;

	PROCEDURE (p: Printer) ClosePage;
	BEGIN
		IF ~aborted THEN p.res := Error(GDI32.EndPage(p.ThisPort()(HostPorts.Port).dc)) END
	END ClosePage;

(*
	PROCEDURE (p: Printer) SetSize (w, h: INTEGER);
	BEGIN
		p.w := w; p.h := h
	END SetSize;
	
	PROCEDURE (p: Printer) OpenBuffer (l, t, r, b: INTEGER);
	END OpenBuffer;
	
	PROCEDURE (p: Printer) CloseBuffer;
	END CloseBuffer;
	
	PROCEDURE (p: Printer) GetSize (OUT w, h: INTEGER);
	BEGIN
		w := p.w; h := p.h
	END GetSize;
*)
	

	(* Rider *)
(*
	PROCEDURE (rd: Rider) Base (): Ports.Port;
	BEGIN
		RETURN rd.p
	END Base;
*)

	(* Directory *)

	PROCEDURE (d: Directory) Default (): Printers.Printer;
		VAR res: INTEGER; prt: COMDLG32.PrintDlgData;
	BEGIN
		prt.size := SIZE(COMDLG32.PrintDlgData);
		prt.devMode := 0; prt.devNames := 0; prt.owner := 0;
		prt.flags := {7, 10};	(* no warning, return default *)
		res := COMDLG32.PrintDlgA(prt);
		IF res # 0 THEN
			RETURN NewPrinter(prt.devNames, prt.devMode)
		ELSE
(*
			res := COMDLG32.CommDlgExtendedError();
			ASSERT(res = 1008H, 100);	(* no default printer *)
*)
			RETURN NIL
		END
	END Default;
	
	PROCEDURE (d: Directory) Current (): Printers.Printer;
	BEGIN
		RETURN current
	END Current;

	PROCEDURE (d: Directory) Available (): BOOLEAN;
	BEGIN
		RETURN current # NIL
	END Available;
	
	
	PROCEDURE Init;
		VAR prt: COMDLG32.PrintDlgData;
	BEGIN
		printing.Cancel := Cancel;
		NEW(dir); Printers.SetDir(dir);
		current := dir.Default()
	END Init;

BEGIN
	Init
END HostPrinters.

