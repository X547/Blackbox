MODULE Fonts;
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

	CONST
		(** universal units **)
		mm* = 36000;
		point* = 12700;	(** 1/72 inch **)

		italic* = 0; underline* = 1; strikeout* = 2;	(** style elements **)

		normal* = 400; bold* = 700;
		
		default* = "*";

	TYPE
		Typeface* = ARRAY 64 OF CHAR;

		Font* = POINTER TO ABSTRACT RECORD
			typeface-: Typeface;
			size-: INTEGER;
			style-: SET;
			weight-: INTEGER
		END;

		TypefaceInfo* = POINTER TO RECORD
			next*: TypefaceInfo;
			typeface*: Typeface
		END;

		Directory* = POINTER TO ABSTRACT RECORD
		END;
		
	VAR dir-: Directory;

	PROCEDURE (f: Font) Init* (typeface: Typeface; size: INTEGER; style: SET; weight: INTEGER), NEW;
	BEGIN
		ASSERT(f.size = 0, 20); ASSERT(size # 0, 21);
		f.typeface := typeface$; f.size := size; f.style := style; f.weight := weight
	END Init;

	PROCEDURE (f: Font) GetBounds* (OUT asc, dsc, w: INTEGER), NEW, ABSTRACT;
	PROCEDURE (f: Font) StringWidth* (IN s: ARRAY OF CHAR): INTEGER, NEW, ABSTRACT;
	PROCEDURE (f: Font) SStringWidth* (IN s: ARRAY OF SHORTCHAR): INTEGER, NEW, ABSTRACT;
	PROCEDURE (f: Font) IsAlien* (): BOOLEAN, NEW, ABSTRACT;
	
	PROCEDURE (d: Directory) This* (typeface: Typeface; size: INTEGER; style: SET; weight: INTEGER): Font, NEW, ABSTRACT;
	PROCEDURE (d: Directory) Default* (): Font, NEW, ABSTRACT;
	PROCEDURE (d: Directory) TypefaceList* (): TypefaceInfo, NEW, ABSTRACT;
	
	PROCEDURE SetDir* (d: Directory);
	BEGIN
		ASSERT(d # NIL, 20);
		dir := d
	END SetDir;

END Fonts.

