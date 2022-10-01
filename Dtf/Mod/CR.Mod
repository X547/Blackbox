MODULE DtfCR ["DTFSW3CR"];	(* single user vesion *)
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

	IMPORT SYSTEM, DtfLvl1;

	PROCEDURE [ccall] recoverDatabase* ["dtFrecoverDatabase"] (fname: DtfLvl1.MemPtr; expandfl: DtfLvl1.boolean): DtfLvl1.ErrType;
	PROCEDURE [ccall] createDatabase* ["dtFcreateDatabase"] (fname: DtfLvl1.MemPtr): DtfLvl1.ErrType;
	PROCEDURE [ccall] getCRErrorMsg* ["dtFgetCRErrorMsg"] (bufg, bufd: DtfLvl1.MemPtr): DtfLvl1.ErrType;
	PROCEDURE [ccall] crSetProject* ["dtFcrSetProject"] (proj: DtfLvl1.MemPtr): DtfLvl1.ErrType;

END DtfCR.
