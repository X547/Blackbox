MODULE Init;
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

	IMPORT Kernel, Dialog, Files, Converters, HostMenus;

	PROCEDURE Splash;	(* Splash screen for educational and evaluation releases *)
		VAR f: Files.File; res: INTEGER;
	BEGIN
		IF Files.dir # NIL THEN
			f := Files.dir.Old(Files.dir.This('System/Rsrc'), 'Open.odc', Files.shared);
			IF f # NIL THEN
				Dialog.Call("StdCmds.OpenToolDialog('System/Rsrc/Open.odc', 'BlackBox Component Builder')", "", res)
			END
		END
	END Splash;

	PROCEDURE Init;
		VAR res: INTEGER; m: Kernel.Module;
	BEGIN
		HostMenus.OpenApp;
		m := Kernel.ThisMod("DevDebug");
		IF m = NIL THEN Kernel.LoadMod("StdDebug") END;
		Converters.Register("Documents.ImportDocument", "Documents.ExportDocument", "", "odc", {});
		Dialog.Call("StdMenuTool.UpdateAllMenus", "", res);
		Kernel.LoadMod("OleServer");
		Dialog.Call("Config.Setup", "", res);
		Splash;
		HostMenus.Run
	END Init;

BEGIN
	Init
END Init.
