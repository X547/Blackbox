MODULE DtfApi ["DTFSW3"];
(**
	project	= "BlackBox"
	organization	= "www.oberon.ch"
	contributors	= "Oberon microsystems, Werner Braun"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	purpose	= "Interface for the dtF-Single-User-8K Version 1.74"
	changes	= ""
	issues	= ""

**)

	(* Header-Files of dtF 1.74 (cref.pdf, 2-3)
	used => corresponding entries in this module
	dtfattr.h	functions to set or querey database-, connection- or table-realted attributes
	dtfcr.h	functions to create and repair databases
	dtfedc.h	all definitions of error codes
	dtflvl2.h	level 2 functions
	dtfreslt.h	types and functions for accessing SQL-results
	dtftypes.h	types
	dtfwin.h	include file for single user versions
		
		not used => no corresponding entries in this module
		dtfenv.h	os / complier specific macros
		dtfhdr.h	general include file
		dtflwin.h	include file for multi-user-versions
	*)
	(* Annotation to the header-Files
		The header-files include many declarations according to the
		several plattforms / compilers / single-user vs. multi-user
		These are not reflected here
		compiler => there is only one within the BB
		platform => this module is only for the windows version
		single/multi => solved by two different Driver + glue modules
	*)

	IMPORT SYSTEM;

	(* general definitions *)
	TYPE
		Byte* = SHORTCHAR;
		Word* = SHORTINT;
		LongWord* = INTEGER;
		HugeWord* = LONGINT;
		SignedByte* = BYTE;
		SignedWord* = SHORTINT;
		SignedLongWord* = INTEGER;

	(* dtfattr.h *)
	CONST
		(* Attribute Domain *)
		keyDomainNone* = 00000H; (* undefined domain *)
		keyDomainDatabase* = 00001H; (* persistent attributes stored in database *)
		keyDomainWorkspace* = 00002H; (* workspace attributes stored in ws properties *)
		keyDomainConnection* = 00003H; (* connection attributes *)
		(* Attribute Data Dypes *)
		keyDatatypeString* = 00001H;
		keyDatatypeInteger* = 00002H;
		(* Database Domain Keys *)
		keyNoBlobfile* = 00001H;
		keyDbType* = 00002H;
		keyDbCreator* = 00003H;
		keyBitType* = 00004H;
		keyBitCreator* = 00005H;
		keyAutorecover* = 00006H; (* server only: automatically recover *)
		keyAutoconnect* = 00007H; (* server only: automatically connect *)
		keyR4Mode* = 00008H; (* R4 transaction logging *)
		keyR4State* = 00009H;
		keyR4Verbosity* = 0000AH;
		keyR4Path* = 0000BH;
		keyR4Backuppath* = 0000CH;
		keyR4Logfilesize* = 0000DH;
		keySrvsetupstr* = 0000EH;
		keySbbuffers* = 0000FH;
		keyPgalgo* = 00010H;
		(* Connection Domain keys *)
		keyServername* = 00040H;
		keyFilename* = 00041H;
		keyR4RestoreActive* = 00042H;
		keyWsresult* = 00043H;
		(* Workspace Domain keys *)
		(* Flags *)
		keyFlagNone* = 00000H;
		keyFlagNodefaults* = 00001H;
	(* dtfattr.h - end *)

	(* dtfedc.h *)
	CONST
		(* Error groups as provided to the caller. *)
		grpFatal* = 01000H;
		grpToken* = 01010H;
		grpSyntax* = 01020H;
		grpIntToken* = 01030H;
		grpIntSyntax* = 01040H;
		grpIntRuntime* = 01050H;
		grpTrans* = 01060H;
		grpRelation* = 01070H;
		grpAuthorization* = 01080H;
		grpRefInteger* = 01090H;
		grpBadIo* = 01100H;
		grpBadMemory* = 01110H;
		grpBadStartup* = 01120H;
		grpIntegrityErr* = 01130H;
		grpNetErr* = 01140H;
		grpMathErr* = 01150H;
		grpResultErr* = 01160H;
		grpCompatErr* = 01180H;
		grpSystemRes* = 01190H;
		grpSaaErr* = 011A0H;
		(* Error Description Codes sent by the Server *)
		(* General *)
		edcNoErr0* = 02000H;
		edcNoDesc0* = 02001H;
		edcNoFeature* = 02002H;
		edcBadCmd0* = 02003H;
		edcErrLock0* = 02008H;
		edcNoDatabase1* = 02009H;
		edcTaSysEnded0* = 0200DH;
		edcNoAccount0* = 0200EH;
		edcTaEnded0* = 0200FH;
		(* Token / Syntax *)
		edcEofReached0* = 02110H;
		edcEofExp1* = 02111H;
		edcKwExp2* = 02112H;
		edcExpCmd1* = 02113H;
		edcExpTbl1* = 02114H;
		edcExpCol1* = 02115H;
		edcExpType1* = 02116H;
		edcExpUsr1* = 02117H;
		edcExpPsw1* = 02118H;
		edcExpAcc1* = 02119H;
		edcExpVal1* = 0211AH;
		edcExpCond1* = 0211BH;
		edcExpFactor1* = 0211CH;
		edcExpNumber1* = 0211DH;
		(* Internal Runtime *)
		edcNoMem0* = 02200H;
		edcOverflow0* = 02201H;
		edcBadNewRec0* = 02202H;
		edcBadNewCol1* = 02203H;
		edcBadNewIdx1* = 02204H;
		edcBadAcc1* = 02205H;
		edcLockFull0* = 02210H;
		edcTAtblFull0* = 02211H;
		edcDBFull0* = 02212H;
		edcScanFull0* = 02213H;
		edcRAstackFull0* = 02214H;
		edcColumnsFull0* = 02215H;
		edcProjFull0* = 02216H;
		(* Runtime / Parameters *)
		edcParam0* = 02300H;
		edcBadVal1* = 02301H;
		edcBadTypeX1* = 02302H;
		edcBadFunc1* = 02303H;
		edcDivByZero0* = 02304H;
		edcConvtRange1* = 02305H;
		edcConvtBad1* = 02306H;
		edcConvtSigned1* = 02307H;
		edcParam1* = 02308H;
		edcNoConvert1* = 02309H;
		edcBadSumAgg* = 0230AH;
		edcBadParam1* = 0230BH;
		edcBadTyRange1* = 0230CH;
		(* Transactions *)
		edcNoNestT0* = 0240H;
		edcNoT0* = 0240H;
		edcTaStopped0* = 0240H;
		(* Relation *)
		edcNoTbl1* = 02500H;
		edcBadCol1* = 02501H;
		edcNoIdx1* = 02502H;
		edcNoUsr1* = 02503H;
		edcNoPk1* = 02504H;
		edcExsTbl1* = 02510H;
		edcExsCol1* = 02511H;
		edcExsIdx1* = 02512H;
		edcTooManyTbls0* = 02520H;
		edcTooManyCols0* = 02521H;
		edcTooManyUsr0* = 02522H;
		edcTooManyPK1* = 02523H;
		edcTooManyFK2* = 02524H;
		edcBadVal0* = 02530H;
		edcBadColTypes2* = 02531H;
		edcBadType1* = 02532H;
		edcBadPkFkType2* = 02533H;
		edcDblTblVar1* = 02540H;
		edcDoubleCol1* = 02541H;
		edcTooLarge1* = 02542H;
		edcBadJoin1* = 025F0H;
		edcBadTbl* = 025F1H;
		edcNoJoin2* = 025F2H;
		edcJoinErr2* = 025F3H;
		edcKeyJoinErr1* = 025F4H;
		(* Authorization *)
		edcNoAccess0* = 02600H;
		edcNoAccRight1* = 02601H;
		edcNoCreat1* = 02602H;
		(* Referential integrity *)
		edcBadNull1* = 02700H;
		edcBadUnique1* = 02701H;
		edcBadNoPkVal2* = 02702H;
		edcBadPkisUsed1* = 02703H;
		(* Blob / Raw Data *)
		edcBadBlob0* = 02800H;
		(* Server Memory Errors *)
		edcSErrMem0* = 02F00H;
		edcSErrVMem0* = 02F01H;
		edcSErrVFull0* = 02F02H;
		edcSErrVMemFull0* = 02F03H;
		edcSErrVMemSlot0* = 02F04H;
		edcSErrNoManager1* = 02F05H;
		edcSErrManager1* = 02F06H;
		(* Error Description Codes of the Client and Initialization *)
		(* I/O Problems *)
		edcErrIO0* = 03001H;
		edcErrNoFile1* = 03002H;
		edcErrAccFile1* = 03003H;
		edcErrCrtFile1* = 03004H;
		edcErrClsFile0* = 03005H;
		edcErrWrtFile0* = 03006H;
		edcErrReaFile0* = 03007H;
		edcErrNoPath1* = 03008H;
		(* Startup and Setupfile Problems *)
		edcErrSyntax2* = 03200H;
		edcNoSection1* = 03201H;
		edcEofTooSoon0* = 03202H;
		edcNoParam1* = 03203H;
		edcNoSwitch1* = 03204H;
		edcBadSecParam2* = 03205H;
		(* Integrity *)
		edcErrInteg0* = 03300H;
		edcBadSize0* = 03301H;
		edcBadCheck0* = 03302H;
		edcBadCounter0* = 03303H;
		edcBadRecords0* = 03304H;
		edcDBinUse1* = 03305H;
		edcBadParam* = 03306H;
		edcTooManyPg0* = 03310H;
		edcIntInteg0* = 03311H;
		edcBadCluster0* = 03312H;
		edcBadIndex1* = 03320H;
		edcBadRecord1* = 03321H;
		edcBadObjects0* = 03330H;
		(* Net-problems *)
		edcErrNet0* = 03400H;
		edcErrNoNet0* = 03401H;
		edcErrComm2* = 03402H;
		edcErrSync1* = 03403H;
		edcErrServer0* = 03410H;
		edcErrSrvName1* = 03411H;
		edcErrNoReset0* = 03412H;
		edcErrNetRes0* = 03413H;
		edcErrDatabase1* = 03414H;
		edcErrNoServer1* = 03415H;
		edcErrSrvAbort0* = 03416H;
		edcTaStoppedC0* = 03430H;
		edcSrvStopped0* = 03431H;
		edcNoProt0* = 03440H;
		edcBadPbId1* = 03450H;
		(* Math *)
		edcErrMath0* = 03500H;
		edcDDivByZero0* = 03501H;
		edcStrongType2* = 03502H;
		edcDecStrForm1* = 03503H;
		(* Level2 result *)
		edcErrResult0* = 03600H;
		edcErrNoResult0* = 03601H;
		edcErrEmptyTbl0* = 03602H;
		edcErrCrsrRange0* = 03603H;
		edcErrColRange0* = 03604H;
		edcErrBufOver1* = 03605H;
		edcErrValRange0* = 03606H;
		edcErrNoRecs0* = 03607H;
		(* Compatibility  *)
		edcErrCompat0* = 03800H;
		edcErrBadVer2* = 03801H;
		edcErrBadType0* = 03802H;
		(* System resource *)
		edcErrSys0* = 03900H;
		edcErrSys1* = 03901H;
		edcErrResFull0* = 03902H;
		edcErrTMFull0* = 03903H;
		edcErrTMBuffer0* = 03904H;
		(* dtF saa *)
		edcErrSaa0* = 03A00H;
		edcSaaObjFull0* = 03A01H;
		edcSaaPropFull0* = 03A02H;
		edcSaaNoProp2* = 03A03H;
		edcSaaNoObj1* = 03A04H;
		edcSaaBadParent2* = 03A05H;
		(* Client Memory Errors *)
		edcCErrMem0* = 03F00H;
		edcCErrVMem0* = 03F01H;
		edcCErrVFull0* = 03F02H;
		edcCErrVMemFull0* = 03F03H;
		edcCErrVMemSlot0* = 03F04H;
		edcCErrNoManager1* = 03F05H;
		edcCErrManager1* = 03F06H;
		CedcErrMem1* = 03F07H;
	(* dtfedc.h - end *)

	(* dtftypes.h *)
	TYPE
		boolean* = SHORTINT;
	CONST
		False* = 0;
		True* = 1;
	TYPE
		WordPtr* = POINTER TO ARRAY [untagged] OF Word;
		MemPtr* = POINTER TO ARRAY [untagged] OF SHORTCHAR;
	TYPE
		ErrType* = Word;
	CONST
		(* Error Codes *)
		ErrOK* = 000H;
		ErrBAD* = 001H;
		ErrFATAL* = 002H;
		ErrOther* = 003H;
		ErrBadId* = 004H;
		ErrLock* = 005H;
		ErrNoSeg* = 006H;
		ErrNoPage* = 007H;
		ErrNoBuffer* = 008H;
		ErrIO* = 009H;
		ErrFull* = 00AH;
		ErrNoFile* = 00BH;
		ErrRange* = 00CH;
		ErrFile* = 00DH;
		ErrMemory* = 00EH;
		ErrIntegrity* = 00FH;
		ErrNoScan* = 010H;
		ErrNoMoreRecords* = 011H;
		ErrBufferFull* = 012H;
		ErrExists* = 013H;
		ErrDoesNotExist* = 014H;
		ErrServer* = 015H;
		ErrClient* = 016H;
		ErrSync* = 017H;
		ErrNet* = 018H;
		ErrStopped* = 019H;
		ErrPassword* = 01AH;
		ErrAccess* = 01BH;
		ErrDivByZero* = 01CH;
		ErrConversion* = 01DH;
		ErrRessource* = 01EH;
		ErrResource* = 01EH;
		ErrTMFull* = 01FH;
		ErrVersion* = 020H;
		ErrLogReady* = 021H;
	(* dtftypes.h - end *)

	(* dtfrslt.h *)
	CONST
		maxFieldLen* = 251;
		maxRelations* = 120;
		maxFieldsPerRel* = 128;
		colInfoSize* = 128;
		nameSize* = 28 (* eigentlich ja 25, ist für 4-Byte Alignment *);
		pwSize* = 16; (* eigentlich 17 *)
	TYPE
		fieldRange* = Byte;
		recordLen* = Word;
		fieldLen1* = Byte;
	TYPE
		colTypeRange* = Word;
	CONST
		colTypeDecimal* = 00000H;
		colTypeByte* = 00F00H;
		colTypeWord* = 00F01H;
		colTypeLongWord* = 00F02H;
		colTypeChar* = 00F03H;
		colTypeShort* = 00F04H;
		colTypeLong* = 00F05H;
		colTypeReal* = 00F06H;
		colTypeShortString* = 00F07H;
		colTypeHugeString* = 00F08H;
		colTypeDate* = 00F09H;
		colTypeTime* = 00F0AH;
		colTypeBit* = 00F80H;
		colTypeUndefined* = 00FFFH;
		colTypeNull* = 00100H;
		colTypes* = 14;
		decimalRanges* = 256;
	TYPE
		cinfoEntry* = RECORD [untagged]
			table*, column*: ARRAY nameSize OF SHORTCHAR;
			type*, fulltype*: colTypeRange;
			exttype*: Word;
		END;
		time* = SignedLongWord;
		date* = SignedLongWord;
	CONST
		extDecimalBytes* = 19;
		extDecimalDigits* = 16;
		NOPREC* = 0FFH;
		RESULTERR* = 0FFH;
	TYPE
		decimal* = RECORD [untagged]
			value*: HugeWord;
			prec*: Byte;
		END;
	(* dtfrslt.h - end *)

	(* dtflvl2.h *)
	TYPE
		fieldLen2* = INTEGER;
		wsHandle* = Word;
	CONST
		badWS* = 0FFFFH;
	TYPE
		moveType* = Word;
	CONST
		moveStart* = 0;
		moveEnd* = 1;
		moveCurrent* = 2;
	TYPE
		exceptionProc* = PROCEDURE (code: Word; group, desc, sqlstr: MemPtr; errpos: Word): ErrType;
	(* dtflvl2.h - end *)

	(* dtfcr.h *)
	PROCEDURE [ccall] recoverDatabase* ["dtFrecoverDatabase"] (fname: MemPtr; expandfl: boolean): ErrType;
	PROCEDURE [ccall] createDatabase* ["dtFcreateDatabase"] (fname: MemPtr): ErrType;
	PROCEDURE [ccall] getCRErrorMsg* ["dtFgetCRErrorMsg"] (bufg, bufd: MemPtr; pEDC : WordPtr ): ErrType;
	PROCEDURE [ccall] crSetProject* ["dtFcrSetProject"] (proj: MemPtr): ErrType;
	(* dtfcr.h - end *)

	(* dtfreslt.h *)
	(* Data Conversion Routines *)
	PROCEDURE [ccall] convtFromDate* ["dtFconvtFromDate"] (d: date; VAR day, month, year: Word);
	PROCEDURE [ccall] convtFromTime* ["dtFconvtFromTime"] (t: time; VAR second, minute, hour: Word);
	PROCEDURE [ccall] convtToStr* ["dtFconvtToStr"] (type: colTypeRange; bufPtr, valPtr: MemPtr; bufsize, alignmentWord : Word): MemPtr;
	(* dtfreslt.h - end *)

	(* dtfwin.h *)
	PROCEDURE [ccall] winSetInstance* ["dtFwinSetInstance"] (hInstance: INTEGER): ErrType;
	(* dtfwin.h - end *)

	(* dtflvl2.h *)
	(* Current Release Information *)
	PROCEDURE [ccall] getVersion* ["dtF2getVersion"] (): MemPtr;
	PROCEDURE [ccall] getVersionNo* ["dtF2getVersionNo"] (): Word;

	(* Exception Handling *)
	PROCEDURE [ccall] setCritical* ["dtF2setCritical"] (func: exceptionProc): exceptionProc;
	PROCEDURE [ccall] setError* ["dtF2setError"] (func: exceptionProc): exceptionProc;
	PROCEDURE [ccall] setWarning* ["dtF2setWarning"] (func: exceptionProc): exceptionProc;
	(* Workspace Handling Functions *)
	PROCEDURE [ccall] getWS* ["dtF2getWS"] (): wsHandle;
	PROCEDURE [ccall] releaseWS* ["dtF2releaseWS"] (wsh: wsHandle): ErrType;
	PROCEDURE [ccall] setDefaultWS* ["dtF2setDefaultWS"] (wsh: wsHandle): wsHandle;
	(* Login Functions *)
	PROCEDURE [ccall] ident* ["dtF2ident"] (IN name, passwd: ARRAY [untagged] OF SHORTCHAR): ErrType;
	(* Level 2 Main Service Functions *)
	PROCEDURE [ccall] start* ["dtF2start"] (): ErrType;
	PROCEDURE [ccall] stop* ["dtF2stop"] (): ErrType;
	PROCEDURE [ccall] exec* ["dtF2exec"] (IN sqlstring: ARRAY [untagged] OF SHORTCHAR): ErrType;
	PROCEDURE [ccall] resultAvailable* ["dtF2resultAvailable"] (): boolean;
	PROCEDURE [ccall] getField* ["dtF2getField"] (field: fieldRange; valptr: INTEGER; valsize: fieldLen2; VAR [nil] vallen: fieldLen2; VAR [nil] valtype: colTypeRange): ErrType;
	PROCEDURE [ccall] getFieldInfo* ["dtF2getFieldInfo"] (field: fieldRange; VAR [nil] vallen: fieldLen2; VAR [nil] valtype: colTypeRange): ErrType;
	PROCEDURE [ccall] rows* ["dtF2rows"] (): LongWord;
	PROCEDURE [ccall] cols* ["dtF2cols"] (): fieldRange;
	PROCEDURE [ccall] cinfoP* ["dtF2cinfoP"] (colnr: fieldRange; VAR info: cinfoEntry): ErrType;
	PROCEDURE [ccall] setMove* ["dtF2setMove"] (range: SignedLongWord): SignedLongWord;
	PROCEDURE [ccall] move* ["dtF2move"] (move: moveType; range: SignedLongWord): ErrType;
	PROCEDURE [ccall] pos* ["dtF2pos"] (): LongWord;
	PROCEDURE [ccall] setBlob* ["dtF2setBlob"] (blob: MemPtr; length: fieldLen2): MemPtr;
	PROCEDURE [ccall] setRandomAccess* ["dtF2setRandomAccess"] (): ErrType;

	(* Level 2 Main Service Functions Using Workspace *)
	PROCEDURE [ccall] execWS* ["dtF2execWS"] (wsh: wsHandle; IN sqlstring: ARRAY [untagged] OF SHORTCHAR): ErrType;
	PROCEDURE [ccall] resultAvailableWS* ["dtF2resultAvailableWS"] (wsh: wsHandle): boolean;
	PROCEDURE [ccall] getFieldWS* ["dtF2getFieldWS"] (wsh: wsHandle; field: fieldRange; valptr: INTEGER; valsize: fieldLen2; VAR [nil] vallen: fieldLen2; VAR [nil] valtype: colTypeRange): ErrType;
	PROCEDURE [ccall] getFieldInfoWS* ["dtF2getFieldInfoWS"] (wsh: wsHandle; field: fieldRange; VAR [nil] vallen: fieldLen2; VAR [nil] valtype: colTypeRange): ErrType;
	PROCEDURE [ccall] rowsWS* ["dtF2rowsWS"] (wsh: wsHandle): LongWord;
	PROCEDURE [ccall] colsWS* ["dtF2colsWS"] (wsh: wsHandle): fieldRange;
	PROCEDURE [ccall] cinfoPWS* ["dtF2cinfoPWS"] (wsh: wsHandle; colnr: fieldRange; VAR info: cinfoEntry): ErrType;
	PROCEDURE [ccall] setMoveWS* ["dtF2setMoveWS"] (wsh: wsHandle; move: SignedLongWord): SignedLongWord;
	PROCEDURE [ccall] moveWS* ["dtF2moveWS"] (wsh: wsHandle; type: moveType; offset: SignedLongWord): ErrType;
	PROCEDURE [ccall] posWS* ["dtF2posWS"] (wsh: wsHandle): LongWord;
	PROCEDURE [ccall] setBlobWS* ["dtF2setBlobWS"] (wsh: wsHandle; blob: MemPtr; length: fieldLen2): MemPtr;
	PROCEDURE [ccall] setRandomAccessWS* ["dtF2setRandomAccessWS"] (wsh: wsHandle): ErrType;

	(* Attribute Set Functions *)
	PROCEDURE [ccall] setAttribInt* ["dtF2setAttribInt"] (domain : INTEGER; key : INTEGER; value : INTEGER): ErrType;
	PROCEDURE [ccall] setAttribStr* ["dtF2setAttribStr"] (domain : INTEGER; key : INTEGER; IN value : ARRAY [untagged] OF SHORTCHAR): ErrType;
	PROCEDURE [ccall] setAttribIntWS* ["dtF2setAttribIntWS"] (wsh: wsHandle; domain : INTEGER; key : INTEGER; value : INTEGER): ErrType;
	PROCEDURE [ccall] setAttribStrWS* ["dtF2setAttribStrWS"] (wsh: wsHandle; domain : INTEGER; key : INTEGER; IN value : ARRAY [untagged] OF SHORTCHAR): ErrType;

	(* Attribute Get Functions *)
	PROCEDURE [ccall] getAttribInt* ["dtF2getAttribInt"] (domain : INTEGER; key : INTEGER; VAR value : INTEGER): ErrType;
	PROCEDURE [ccall] getAttribStr* ["dtF2getAttribStr"] (domain : INTEGER; key : INTEGER; VAR [nil] value : ARRAY [untagged] OF SHORTCHAR; VAR maxBytes : INTEGER): ErrType;
	PROCEDURE [ccall] getAttribIntWS* ["dtF2getAttribIntWS"] (wsh: wsHandle; domain : INTEGER; key : INTEGER; VAR value : INTEGER): ErrType;
	PROCEDURE [ccall] getAttribStrWS* ["dtF2getAttribStrWS"] (wsh: wsHandle; domain : INTEGER; key : INTEGER; VAR [nil] value : ARRAY [untagged] OF SHORTCHAR; VAR maxBytes : INTEGER): ErrType;

	(* Configuration Functions *)
	PROCEDURE [ccall] setTimeOut* ["dtF2setTimeOut"] (timeout: SignedLongWord): SignedLongWord;
	PROCEDURE [ccall] setMessageFile* ["dtF2setMessageFile"] (fname: MemPtr): MemPtr;
	PROCEDURE [ccall] setSetupFile* ["dtF2setSetupFile"] (fname: MemPtr): MemPtr;
	PROCEDURE [ccall] setProject* ["dtF2setProject"] (proj: MemPtr): MemPtr;
	(* dtflvl2.h - end *)

END DtfApi.
