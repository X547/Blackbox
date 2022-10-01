MODULE DtfCLvl2 ["DTFLW3L2"];	(* server version *)
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

	IMPORT SYSTEM, DtfLvl1 := DtfCLvl1;

	(* Oberon Interface for dtF-Libraries by Oberon microsystems, Inc. based on:
		*  DTFLVL2.H - dtF Level 2 Application Development / Common File
		*  (C) Copyright 1990-1994 by sLAB Banzhaf & Soltau GbR. 
		*  All Rights Reserved.
	*)

	CONST
		badWS* = 0FFFFH;

	TYPE
		fieldLen* = INTEGER;
		wsHandle* = DtfLvl1.Word;

		cinfoEntry* = RECORD [untagged]
			table*, column*: ARRAY DtfLvl1.nameSize OF SHORTCHAR;
			type*: DtfLvl1.colTypeRange;
			exttype*: DtfLvl1.Word;
		END;

	CONST
		moveStart* = 0;
		moveEnd* = 1;
		moveCurrent* = 2;
		
	TYPE
		moveType* = DtfLvl1.Word;
		exceptionProc* = PROCEDURE (code: DtfLvl1.Word; group, desc, sqlstr: DtfLvl1.MemPtr; errpos: DtfLvl1.Word): DtfLvl1.ErrType;

(*
	/*----------------------------------------------------------------------*/

	/* Function Prototype Definition for Exception Handling Functions
  */

	typedef DtfLvl1.ErrType ( *dtF2exceptionPtr)(Word code, MemPtr group, MemPtr desc,
     MemPtr sqlstr, Word errpos);

	/************************************************************************/

	/* Function Prototypes
  */

	/*----------------------------------------------------------------------*/

	/* Exception Handling Functions
  */

	extern dtF2exceptionPtr DTFENTRY dtF2setCritical(dtF2exceptionPtr func);
	extern dtF2exceptionPtr DTFENTRY dtF2setError(dtF2exceptionPtr func);
	extern dtF2exceptionPtr DTFENTRY dtF2setWarning(dtF2exceptionPtr func);
*)
	PROCEDURE [ccall] setCritical* ["dtF2setCritical"] (func: exceptionProc): exceptionProc;
	PROCEDURE [ccall] setError* ["dtF2setError"] (func: exceptionProc): exceptionProc;
	PROCEDURE [ccall] setWarning* ["dtF2setWarning"] (func: exceptionProc): exceptionProc;

(*
	/*----------------------------------------------------------------------*/

	/* Exception Handling Functions  Using Workspace
  */

	extern dtF2exceptionPtr DTFENTRY dtF2setCriticalWS(dtF2wsHandle wsh,
    dtF2exceptionPtr func);
	extern dtF2exceptionPtr DTFENTRY dtF2setErrorWS(dtF2wsHandle wsh,
    dtF2exceptionPtr func);
	extern dtF2exceptionPtr DTFENTRY dtF2setWarningWS(dtF2wsHandle wsh,
    dtF2exceptionPtr func);

*)

	(* Workspace Handling Functions *)
	PROCEDURE [ccall] getWS* ["dtF2getWS"] (): wsHandle;
	PROCEDURE [ccall] releaseWS* ["dtF2releaseWS"] (wsh: wsHandle): DtfLvl1.ErrType;
	PROCEDURE [ccall] setDefaultWS* ["dtF2setDefaultWS"] (wsh: wsHandle): wsHandle;

	(* Login Functions *)
	PROCEDURE [ccall] ident* ["dtF2ident"] (IN name, passwd: ARRAY [untagged] OF SHORTCHAR): DtfLvl1.ErrType;

	(* Level 2 Main Service Functions *)
	PROCEDURE [ccall] start* ["dtF2start"] (): DtfLvl1.ErrType;
	PROCEDURE [ccall] stop* ["dtF2stop"] (): DtfLvl1.ErrType;
	PROCEDURE [ccall] exec* ["dtF2exec"] (IN sqlstring: ARRAY [untagged] OF SHORTCHAR): DtfLvl1.ErrType;
	PROCEDURE [ccall] resultAvailable* ["dtF2resultAvailable"] (): DtfLvl1.boolean;
	(*
	PROCEDURE [ccall] into* ["dtF2into"] (cols: DtfLvl1.dtFfieldRange; valptr: LONGINT; valsize: fieldLen; ...): DtfLvl1.ErrType;
	END into;
	*)
	(*
	PROCEDURE [ccall] intoL* ["dtF2intoL"] (cols: DtfLvl1.dtFfieldRange; valptr: LONGINT; valsize: fieldLen; VAR [nil] vallen fieldLen; ...): DtfLvl1.ErrType;
	END intoL;
	*)
	PROCEDURE [ccall] getField* ["dtF2getField"] (field: DtfLvl1.fieldRange; valptr: INTEGER; valsize: fieldLen; VAR [nil] vallen: fieldLen; VAR [nil] valtype: DtfLvl1.colTypeRange): DtfLvl1.ErrType;
	PROCEDURE [ccall] getFieldInfo* ["dtF2getFieldInfo"] (field: DtfLvl1.fieldRange; VAR [nil] vallen: fieldLen; VAR [nil] valtype: DtfLvl1.colTypeRange): DtfLvl1.ErrType;

	PROCEDURE [ccall] rows* ["dtF2rows"] (): DtfLvl1.LongWord;
	PROCEDURE [ccall] cols* ["dtF2cols"] (): DtfLvl1.fieldRange;
	PROCEDURE [ccall] cinfoP* ["dtF2cinfoP"] (colnr: DtfLvl1.fieldRange; VAR info: cinfoEntry): DtfLvl1.ErrType;
	PROCEDURE [ccall] setMove* ["dtF2setMove"] (range: DtfLvl1.SignedLongWord): DtfLvl1.SignedLongWord;
	PROCEDURE [ccall] move* ["dtF2move"] (move: moveType; range: DtfLvl1.SignedLongWord): DtfLvl1.ErrType;
	PROCEDURE [ccall] pos* ["dtF2pos"] (): DtfLvl1.LongWord;
	PROCEDURE [ccall] setBlob* ["dtF2setBlob"] (blob: DtfLvl1.MemPtr; length: fieldLen): DtfLvl1.MemPtr;
	PROCEDURE [ccall] setRandomAccess* ["dtF2setRandomAccess"] (): DtfLvl1.ErrType;

	(* Level 2 Main Service Functions Using Workspace *)
	PROCEDURE [ccall] execWS* ["dtF2execWS"] (wsh: wsHandle; IN sqlstring: ARRAY [untagged] OF SHORTCHAR): DtfLvl1.ErrType;
	PROCEDURE [ccall] resultAvailableWS* ["dtF2resultAvailableWS"] (wsh: wsHandle): DtfLvl1.boolean;
	(*
	PROCEDURE [ccall] intoWS* ["dtF2intoWS"] (wsh: wsHandle; cols: DtfLvl1.fieldRange; valptr: LONGINT; valsize: fieldLen; ...): DtfLvl1.ErrType;
	END intoWS;
	*)
	(*
	PROCEDURE [ccall] intoLWS* ["dtF2intoLWS"] (wsHandle wsh, DtfLvl1.fieldRange cols,  LONGINT valptr, fieldLen valsize, fieldLenPtr vallenptr, ...): DtfLvl1.ErrType;
	END intoLWS;
	*)
	PROCEDURE [ccall] getFieldWS* ["dtF2getFieldWS"] (wsh: wsHandle; field: DtfLvl1.fieldRange; valptr: INTEGER; valsize: fieldLen; VAR [nil] vallen: fieldLen; VAR [nil] valtype: DtfLvl1.colTypeRange): DtfLvl1.ErrType;
	PROCEDURE [ccall] getFieldInfoWS* ["dtF2getFieldInfoWS"] (wsh: wsHandle; field: DtfLvl1.fieldRange; VAR [nil] vallen: fieldLen; VAR [nil] valtype: DtfLvl1.colTypeRange): DtfLvl1.ErrType;

	PROCEDURE [ccall] rowsWS* ["dtF2rowsWS"] (wsh: wsHandle): DtfLvl1.LongWord;
	PROCEDURE [ccall] colsWS* ["dtF2colsWS"] (wsh: wsHandle): DtfLvl1.fieldRange;
	PROCEDURE [ccall] cinfoPWS* ["dtF2cinfoPWS"] (wsh: wsHandle; colnr: DtfLvl1.fieldRange; VAR info: cinfoEntry): DtfLvl1.ErrType;
	PROCEDURE [ccall] setMoveWS* ["dtF2setMoveWS"] (wsh: wsHandle; move: DtfLvl1.SignedLongWord): DtfLvl1.SignedLongWord;
	PROCEDURE [ccall] moveWS* ["dtF2moveWS"] (wsh: wsHandle; type: moveType; offset: DtfLvl1.SignedLongWord): DtfLvl1.ErrType;
	PROCEDURE [ccall] posWS* ["dtF2posWS"] (wsh: wsHandle): DtfLvl1.LongWord;
	PROCEDURE [ccall] setBlobWS* ["dtF2setBlobWS"] (wsh: wsHandle; blob: DtfLvl1.MemPtr; length: fieldLen): DtfLvl1.MemPtr;
	PROCEDURE [ccall] setRandomAccessWS* ["dtF2setRandomAccessWS"] (wsh: wsHandle): DtfLvl1.ErrType;

	(* Configuration Functions *)
	PROCEDURE [ccall] setTimeOut* ["dtF2setTimeOut"] (timeout: DtfLvl1.SignedLongWord): DtfLvl1.SignedLongWord;
	PROCEDURE [ccall] setMessageFile* ["dtF2setMessageFile"] (fname: DtfLvl1.MemPtr): DtfLvl1.MemPtr;
	PROCEDURE [ccall] setSetupFile* ["dtF2setSetupFile"] (fname: DtfLvl1.MemPtr): DtfLvl1.MemPtr;
	PROCEDURE [ccall] setProject* ["dtF2setProject"] (proj: DtfLvl1.MemPtr): DtfLvl1.MemPtr;

END DtfCLvl2.
