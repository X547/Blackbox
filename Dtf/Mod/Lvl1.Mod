MODULE DtfLvl1 ["DTFSW3L1"];	(* single user vesion *)
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

	IMPORT SYSTEM;

	(* Oberon Interface for dtF-Libraries by Oberon microsystems, Inc. based on:
		*  DTFLVL1.H - dtF Level 1 Application Development / Common File
		*  (C) Copyright 1990-1994 by sLAB Banzhaf & Soltau GbR.
		*  All Rights Reserved.
	*)

	TYPE
		Byte* = SHORTCHAR;
		Word* = SHORTINT;
		LongWord* = INTEGER;
		HugeWord* = LONGINT;
		SignedByte* = BYTE;
		SignedWord* = SHORTINT;
		SignedLongWord* = INTEGER;
		
	CONST
		False* = 0;
		True* = 1;
		
	TYPE
		boolean* = SHORTINT;

	TYPE
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

	TYPE
		MemPtr* = POINTER TO ARRAY [untagged] OF SHORTCHAR;

	TYPE
		ErrType* = Word;
   
	CONST
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
		ErrTMFull* = 01FH;

	CONST
		maxFieldLen* = 251;
		maxRelations* = 120;
		maxFieldsPerRel* = 128;
		
		colInfoSize* = 64;
		nameSize* = 28;
		pwSize* = 16;
		
	TYPE
		fieldRange* = Byte;
		recordLen* = Word;
		fieldLen* = Byte;
		
	CONST
		colTypeDecimal* = 00000H;
		decimalRanges* = 256;

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
		
	TYPE
		colTypeRange* = Word;

	(* Data Conversion Routines *)

	PROCEDURE [ccall] convtFromDate* ["dtFconvtFromDate"] (d: date; VAR day, month, year: Word);
	PROCEDURE [ccall] convtFromTime* ["dtFconvtFromTime"] (t: time; VAR second, minute, hour: Word);
	PROCEDURE [ccall] winSetInstance* ["dtFwinSetInstance"] (hInstance: INTEGER): ErrType;
	PROCEDURE [ccall] convtToStr* ["dtFconvtToStr"] (type: colTypeRange; bufPtr, valPtr: MemPtr; bufsize, alignmentWord: Word): MemPtr;

END DtfLvl1.


/************************************************************************/

/* Function Prototypes
 */

/*----------------------------------------------------------------------*/

/* General Functions
 */

/*----------------------------------------------------------------------*/

/* Generic Memory Handling
 */

extern MemIdRange DTFENTRY dtFmemAlloc(LongWord);
extern ErrType DTFENTRY dtFmemRealloc(MemIdRange, Word);
extern ErrType DTFENTRY dtFmemRelease(MemIdRange);
extern MemPtr DTFENTRY dtFmemLock(MemIdRange);
extern ErrType DTFENTRY dtFmemUnlock(MemIdRange);
extern LongWord DTFENTRY dtFqueryFreeMemory(void);

/************************************************************************/

/* Initializationfile handling
 */

#if ! ( DTF32B )
typedef enum {
   dtFinitApps, dtFinitUser
} dtFinitRange;                   /* possible initialization situations */
#else
typedef Word dtFinitRange;
#define dtFinitApps ((dtFinitRange)WordNoBits)
#define dtFinitUser ((dtFinitRange)(WordNoBits + 1))
#endif

extern MemPtr DTFENTRY SCgetInitString(dtFinitRange type,
   MemPtr fname, MemPtr parameter);

/************************************************************************/

/* Communication and Named Pipe
 */

#define dtFpipeName "\\PIPE\\dtF.pip"

/*----------------------------------------------------------------------*/

/* Different Server Priority Levels
 */

#if ! ( DTF32B )
typedef enum {
   dtFlowPrio, dtFmediumPrio, dtFhighPrio, dtFsystemPrio
} dtFprioRange;
#else
typedef Word dtFprioRange;
#define dtFlowPrio    ((dtFprioRange)WordNoBits)
#define dtFmediumPrio ((dtFprioRange)(WordNoBits + 1))
#define dtFhighPrio   ((dtFprioRange)(WordNoBits + 2))
#define dtFsystemPrio ((dtFprioRange)(WordNoBits + 3))
#endif
   
/************************************************************************/

/* Definitions for Client/Server Data Exchange
 */

/*----------------------------------------------------------------------*/

/* Request and Result Format Identifiers
 */

#define SCrequests             3      /* # of known request formats     */
#define SCreqUndefined    0x0000      /* Undefined Request              */
#define SCreqNulSQL       0x0001      /* NUL SQL                        */
#define SCreqRelAlgebra   0x0002      /* Relational Algebra             */

#define dtFresNone        0x0000      /* No data result provided        */
#define dtFresError       0x0001      /* Error description provided     */
#define dtFresRecEnum     0x0002      /* Direct record enumeration      */
#define dtFresObject      0x0003      /* Object ID returned             */
#define dtFresObjectData  0x0004      /* Object Data returned           */

/*----------------------------------------------------------------------*/

/* Request and Result Handling Definitions
 */

#define dtFpageSize 4096

typedef MemPtr SCresPagePtr;          /* DO NOT USE, may change         */
typedef SCresPagePtr dtFresPtr;       /* Result page pointer            */

typedef Word dtFrequestHandle;        /* Request handle identifier      */

typedef Word dtFpbid,                 /* Mailbox identifier at server   */
             *dtFpbidPtr;             /* Pointer to dtfPbid             */

/*----------------------------------------------------------------------*/

/* Different Request Status Values 
 */

#if ! ( DTF32B )
typedef enum {
   dtFreqUnused,                      /* client memory overflow         */
   dtFreqSent,                        /* req. sent, accepted by server  */
   dtFreqRunning,                     /* server actually works on req.  */
   dtFreqFinished,                    /* req. is successfully finished  */
   dtFreqRejected,                    /* error occured, r. not accepted */
   dtFreqTAEnded                      /* TA ended, pbid no longer valid */
} dtFrequestStatus;
#else
typedef Word dtFrequestStatus;
#define dtFreqUnused    ((dtFrequestStatus)WordNoBits)
#define dtFreqSent      ((dtFrequestStatus)(WordNoBits + 1))
#define dtFreqRunning   ((dtFrequestStatus)(WordNoBits + 2))
#define dtFreqFinished  ((dtFrequestStatus)(WordNoBits + 3))
#define dtFreqRejected  ((dtFrequestStatus)(WordNoBits + 4))
#define dtFreqTAEnded   ((dtFrequestStatus)(WordNoBits + 5))
#endif
   
/************************************************************************/

/* Constants and Definitions for Client Cursor Functionality
 */

/*----------------------------------------------------------------------*/

/* Global Error Variable
 */

extern ErrType DTFSEG dtFerr;         /* Error variable of the client   */

/*----------------------------------------------------------------------*/

/* Independent Constants for Cursor Purpose
 */

#define dtFbadCursor LongWordNoBits         /* Cursor definition failed */
#define dtFnoRecords LongWordNoBits         /* Opened cursor is empty   */

/*----------------------------------------------------------------------*/

/* Types for Cursor Purpose
 */

typedef LongWord dtFcursorSize;       /* # of records within one cursor */
typedef LongWord dtFcursorHandle;     /* Handle of a defined cursor     */

/*----------------------------------------------------------------------*/

/* Different Cursor Types
 */

#if ! ( DTF32B )
typedef enum {
   dtFrawCursor,                      /* Raw cursor, size is 1 record   */
   dtFndxCursor,                      /* Raw cursor, indexed            */
   dtFunused1, dtFunused2             /* RESERVED                       */
} dtFcursorType;
#else
typedef Word dtFcursorType;
#define dtFrawCursor  ((dtFcursorType)WordNoBits)
#define dtFndxCursor  ((dtFcursorType)(WordNoBits + 1))
#define dtFunused1    ((dtFcursorType)(WordNoBits + 2))
#define dtFunused2    ((dtFcursorType)(WordNoBits + 3))

#endif
   
/*----------------------------------------------------------------------*/

/* Different Cursor Movements
 */

#if ! ( DTF32B )
typedef enum {
   dtFmvRecRel,                       /* Move to absolute record pos.   */
   dtFmvRecAbs,                       /* Move relative by # records     */
   dtFmvPageRel,                      /* Move to absolute page number   */
   dtFmvPageAbs                       /* Move relative by # pages       */
} dtFmoveType;
#else
typedef Word dtFmoveType;
#define dtFmvRecRel   ((dtFmoveType)WordNoBits)
#define dtFmvRecAbs   ((dtFmoveType)(WordNoBits + 1))
#define dtFmvPageRel  ((dtFmoveType)(WordNoBits + 2))
#define dtFmvPageAbs  ((dtFmoveType)(WordNoBits + 3))
#endif
   
typedef SignedLongWord dtFcursorRange;/* Range to move within cursor    */

/************************************************************************/

/* Constants and Definitions for Record and Field Functionality
 */

/************************************************************************/

/* Record and Field Types
 */

#define dtFmaxFieldLen           251  /* Standard fields max. length
                                       * 250 chars + trailing 0 */
#define dtFmaxRelations          120  /* Max. # of relations of one db. */
#define dtFmaxFieldsPerRel       128  /* Max. # of fields of one rel.   */

#define dtFcolInfoSize            64  /* SCresRecEnum: max # of res.col */
#define dtFnameSize               24  /* SCresRecEnum: name string size */
#define dtFpwSize                 16  /* Length of password */

typedef Byte dtFfieldRange;           /* Type for # of fields of 1 rec. */

typedef Word dtFrecordLen,            /* Record length type             */
             *dtFrecordLenPtr;        /* Pointer for record length type */

typedef Byte dtFfieldLen,             /* Field length type              */
             *dtFfieldLenPtr;         /* Pointer for field length type  */

/*----------------------------------------------------------------------*/

/* Constants Describing User Column Types
 */


#if ! ( DTF32B )
typedef enum {
   dtFcolTypeDecimal   = 0x0000,         /* Decimal type */
   dtFcolTypeByte      = 0x0f00,         /* Byte type */
   dtFcolTypeWord,                       /* Word type */
   dtFcolTypeLongWord,                   /* LongWord type */
   dtFcolTypeChar,                       /* Character type */
   dtFcolTypeShort,                      /* ShortInteger type */
   dtFcolTypeLong,                       /* LongInteger type */
   dtFcolTypeReal,                       /* Real Type */
   dtFcolTypeShortString,                /* ShortString type */
   dtFcolTypeHugeString,                 /* HugeString type */
   dtFcolTypeDate,                       /* Date type */
   dtFcolTypeTime,                       /* Time type */
   dtFcolTypeBit       = 0x0f80,         /* Raw blob type */
   dtFcolTypeUndefined = 0x0fff          /* Undefined type */
} dtFcolTypeRange, *dtFcolTypeRangePtr;
#else
typedef Word dtFcolTypeRange, *dtFcolTypeRangePtr;
#define dtFcolTypeDecimal     0x0000         /* Decimal type */
#define dtFcolTypeByte        0x0f00         /* Byte type */
#define dtFcolTypeWord        0x0f01         /* Word type */
#define dtFcolTypeLongWord    0x0f02         /* LongWord type */
#define dtFcolTypeChar        0x0f03         /* Character type */
#define dtFcolTypeShort       0x0f04         /* ShortInteger type */
#define dtFcolTypeLong        0x0f05         /* LongInteger type */
#define dtFcolTypeReal        0x0f06         /* Real Type */
#define dtFcolTypeShortString 0x0f07         /* ShortString type */
#define dtFcolTypeHugeString  0x0f08         /* HugeString type */
#define dtFcolTypeDate        0x0f09         /* Date type */
#define dtFcolTypeTime        0x0f0a         /* Time type */
#define dtFcolTypeBit         0x0f80         /* Raw blob type */
#define dtFcolTypeUndefined   0x0fff         /* Undefined type */
#endif


#define dtFcolTypes 14

#define dtFdecimalRanges 256

#define dtFdecimalPre(type)  ((Byte)(((Byte)type >> 4))+1)
#define dtFdecimalPost(type) ((Byte)((Byte)type & 0x0f))

#define dtFisExtendedDataType(type)   ((type & 0xf000) != 0)
#define dtFgetBaseDataType(type)       (type & 0x0fff)

/************************************************************************/

/* The following definitions are not for public usage by developers.
 */

/*----------------------------------------------------------------------*/

/* Private Low Level Function Prototypes of the Client, DO NOT USE
 */

extern ErrType DTFENTRY CUinitDtf(MemPtr);
extern ErrType DTFENTRY CUendWorkDtf(void);

extern dtFrequestHandle DTFENTRY dtFsend(dtFpbidPtr, MemPtr);
extern dtFresPtr DTFENTRY dtFgetErrorPage(dtFrequestHandle);

/************************************************************************/

/* Public Function Prototypes For Client Interface
 */

/*----------------------------------------------------------------------*/

/* Module Initialization and Endwork
 */

extern ErrType DTFENTRY dtFinit(MemPtr);
extern ErrType DTFENTRY dtFendWork();
extern ErrType DTFENTRY dtFconnectServer(dtFpbidPtr, MemPtr, MemPtr);
extern ErrType DTFENTRY dtFclearPbId(void);

/*----------------------------------------------------------------------*/

/* Request Send, Status, Wait and Drop Functions 
 */

#define dtFasyncRequest(pbid, request) dtFsend(pbid, request)

#define dtFsyncRequest(pbid, request, time) \
   dtFwaitForResult(dtFsend(pbid, request), time)

extern dtFrequestStatus DTFENTRY dtFstatus(dtFrequestHandle,
   dtFpbidPtr);
extern dtFrequestHandle DTFENTRY dtFwaitForResult(
   dtFrequestHandle, SignedLongWord);
extern ErrType DTFENTRY dtFdropResult(dtFrequestHandle);
extern Word DTFENTRY dtFresultFormat(dtFrequestHandle);
extern LongWord DTFENTRY dtFperformedRecords(dtFrequestHandle);

/*----------------------------------------------------------------------*/

/* Header Page Functions
 */

extern dtFresPtr DTFENTRY dtFlockHeader(dtFrequestHandle);
extern ErrType DTFENTRY dtFunlockHeader(dtFrequestHandle);
extern dtFcursorSize DTFENTRY dtFgetRecords(dtFresPtr);
extern dtFfieldRange DTFENTRY dtFgetColumns(dtFresPtr);
extern MemPtr DTFENTRY dtFgetRelName(dtFresPtr,dtFfieldRange);
extern MemPtr DTFENTRY dtFgetColName(dtFresPtr,dtFfieldRange);
extern dtFcolTypeRange DTFENTRY dtFgetColType(dtFresPtr,dtFfieldRange);
extern Word DTFENTRY dtFgetExtColType(dtFresPtr,dtFfieldRange);
extern dtFboolean DTFENTRY dtFisSorted(dtFresPtr);

/*----------------------------------------------------------------------*/

/* Cursor Functions
 */

extern dtFcursorHandle DTFENTRY dtFdefineCursor(dtFcursorSize,
   dtFcursorType);
extern ErrType DTFENTRY dtFdropCursor(dtFcursorHandle);
extern MemPtr DTFENTRY dtFopenCursor(dtFcursorHandle,dtFrequestHandle);
extern ErrType DTFENTRY dtFcloseCursor(dtFcursorHandle);
extern MemPtr DTFENTRY dtFmoveCursor(dtFcursorHandle, dtFmoveType, 
   dtFcursorRange);
extern dtFcursorRange DTFENTRY dtFcrsrPos(dtFcursorHandle);



/*----------------------------------------------------------------------*/
/* Object support functions are not for public usage by developers.
 */

typedef struct {
   Word      page;
   Byte      index;
   Byte      cluster;
} dtFoid;

typedef struct {
   dtFoid oid;
   LongWord size;
} dtFrawBlobHdl, *dtFrawBlobHdlPtr;

#if ! (DTF32B | DTFMAC)
typedef enum {
   BLbegin,
   BLcommit,
   BLabort,
   BLdelete,
   BLread,
   BLwrite,
   BLstorePg,
   BLstoreLast,
   BLinfo,
   BLnoReq
} dtFobjCmD;
#else
typedef Word dtFobjCmD;
#define BLbegin		0x0001
#define BLcommit	0x0002
#define BLabort		0x0003
#define BLdelete	0x0004
#define BLread		0x0005
#define BLwrite		0x0006
#define BLstorePg	0x0007
#define BLstoreLast	0x0008
#define BLinfo		0x0009
#define BLnoReq		0x000A

#endif

extern dtFrequestHandle DTFENTRY dtFobjRequest(dtFpbidPtr,
    dtFobjCmD, dtFoid, MemPtr, LongWord);
extern dtFoid DTFENTRY dtFgetOid(dtFrequestHandle);
extern LongWord DTFENTRY dtFgetObjSize(dtFrequestHandle);
extern LongWord DTFENTRY dtFgetObjData(dtFrequestHandle, MemPtr, LongWord);

/************************************************************************/

/* Several Help Functions
 */

/*----------------------------------------------------------------------*/

/* Error Handling 
 */

extern MemPtr DTFENTRY dtFgetError(ErrType);
extern ErrType DTFENTRY dtFgetErrorMsg(MemPtr, MemPtr,
   dtFrequestHandle, MemPtr);
extern ErrType DTFENTRY dtFgetErrorMsgX(MemPtr, MemPtr, WordPtr,
   MemPtrPtr, WordPtr, dtFrequestHandle, MemPtr);
extern dtFboolean DTFENTRY dtFaccountFailed(dtFrequestHandle);

/*----------------------------------------------------------------------*/

/* Retrieving Field Values 
 */

extern dtFfieldRange DTFENTRY dtFscanCrsr(dtFresPtr, MemPtr, ...);
extern dtFfieldRange DTFENTRY dtFscanCrsrL(dtFresPtr, MemPtr, ...);
extern dtFfieldRange DTFENTRY dtFscanCrsrX(dtFresPtr, MemPtr, ...);
extern MemPtr DTFENTRY dtFgetField(
   dtFresPtr, MemPtr, dtFfieldRange, MemPtr, dtFfieldLenPtr);

/************************************************************************/

/* Decimal Arithmetic Functions
 */

/*----------------------------------------------------------------------*/

/* Decimal Functions implemented as macros
 */

#define dtFdecPlus(op1, op2)        dtFdecimalPlus(NOPREC, (op1), (op2))
#define dtFdecMinus(op1, op2)       dtFdecimalMinus(NOPREC, (op1), (op2))
#define dtFdecTimes(op1, op2)       dtFdecimalTimes(NOPREC, (op1), (op2))
#define dtFdecDiv(op1, op2)         dtFdecimalDiv(NOPREC, (op1), (op2))

/*----------------------------------------------------------------------*/

/* Check for decimal error condition
 */

#define dtFdecimalIsErr(op)         ((op).prec == RESULTERR)

/*----------------------------------------------------------------------*/

/* Decimal Functions
 */

extern dtFdecimal DTFENTRY dtFdecAbs(dtFdecimal operand);

extern dtFdecimal DTFENTRY dtFdecimalPlus(
   Byte ergprec, dtFdecimal operand1, dtFdecimal operand2);
extern dtFdecimal DTFENTRY dtFdecimalMinus(
   Byte ergprec, dtFdecimal operand1, dtFdecimal operand2);
extern dtFdecimal DTFENTRY dtFdecimalTimes(
   Byte ergprec, dtFdecimal operand1, dtFdecimal operand2);
extern dtFdecimal DTFENTRY dtFdecimalDiv(
   Byte ergprec, dtFdecimal operand1, dtFdecimal operand2);
extern dtFdecimal DTFENTRY dtFdecimalNorm(Byte ergprec, 
  dtFdecimal operand);

/*----------------------------------------------------------------------*/

/* Decimal Conversion Routines
 */

extern dtFdecimal DTFENTRY dtFdecimalConst(MemPtr numstring);
extern MemPtr DTFENTRY dtFdecimalToStr(
   MemPtr strbuf, Word buflen, dtFdecimal value, Word length);
extern dtFdecimal DTFENTRY dtFlongToDecimal(Byte ergprec,
   SignedLongWord value);

/*----------------------------------------------------------------------*/

/* Decimal Comparison Routines
 */

extern dtFboolean DTFENTRY dtFdecimalEq(dtFdecimal value1,
   dtFdecimal value2);
extern dtFboolean DTFENTRY dtFdecimalLeq(dtFdecimal value1,
   dtFdecimal value2);
extern dtFboolean DTFENTRY dtFdecimalGt(dtFdecimal value1,
   dtFdecimal value2);

/************************************************************************/

#if ( _CPLUSPLUS | _cplusplus | __CPLUSPLUS | __cplusplus )
}
#endif


/************************************************************************/

#endif
