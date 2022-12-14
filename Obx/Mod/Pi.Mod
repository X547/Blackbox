MODULE ObxPi;
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

	IMPORT Int := Integers, StdLog;

	PROCEDURE Pi* (digits: INTEGER): Int.Integer;	(* entier(pi * 10^digits) *)
		VAR p1, p2, inc, sum: Int.Integer; guard, div: INTEGER;
	BEGIN
		(* pi = 16 * atan(1/5) - 4 * atan(1/239) *)
		(* atan(x) = x - x^3/3 + x^5/5 - x^7/7 + ... *)
		guard := 8;
		p1 := Int.Quotient(Int.Product(Int.Power(Int.Long(10), digits + guard), Int.Long(16)), Int.Long(5));
		p2 := Int.Quotient(Int.Product(Int.Power(Int.Long(10), digits + guard), Int.Long(-4)), Int.Long(239));
		sum := Int.Sum(p1, p2);
		div := 1;
		REPEAT
			p1 := Int.Quotient(p1, Int.Long(-5 * 5));
			p2 := Int.Quotient(p2, Int.Long(-239 * 239));
			INC(div, 2);
			inc := Int.Quotient(Int.Sum(p1, p2), Int.Long(div));
			sum := Int.Sum(sum, inc)
		UNTIL Int.Sign(inc) = 0;
		RETURN Int.Quotient(sum, Int.Power(Int.Long(10), guard))
	END Pi;

	PROCEDURE WritePi* (digits: INTEGER);
		VAR i: Int.Integer; s: ARRAY 10000 OF CHAR;
	BEGIN
		i := Pi(digits);
		Int.ConvertToString(i, s);
		StdLog.String(s); StdLog.Ln
	END WritePi;

END ObxPi.
