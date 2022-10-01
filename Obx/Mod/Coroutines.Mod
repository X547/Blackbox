MODULE ObxCoroutines;
(**
	project	= "BlackBox"
	organization	= "blackboxframework.org/"
	contributors	= "BlackBox framework center"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""

**)

	IMPORT Coroutines, StdLog, DevCommanders, TextMappers, Services, Math;

	TYPE
		Plain = POINTER TO RECORD (Coroutines.Coroutine)
			next: INTEGER
		END;
		
		Primes = POINTER TO RECORD (Coroutines.Task)
			to: INTEGER;
		END;

		Tree = POINTER TO RECORD
			left, right: Tree; (* NIL for leaf node *)
			name: ARRAY 16 OF CHAR (* only for leaf node *)
		END;

		Fringe = POINTER TO RECORD (Coroutines.Iterator)
			tree, next: Tree;
		END;

	PROCEDURE (this: Plain) Run;
		VAR i: INTEGER;
	BEGIN
		StdLog.String("BEGIN Plain"); StdLog.Ln;
		FOR i := 0 TO 9 DO
			this.next := i; Coroutines.Transfer(this.parent)
		END;
		StdLog.String("END Plain"); StdLog.Ln
	END Run;

	PROCEDURE RunPlainCoroutine*;
		VAR p: Plain;
	BEGIN
		NEW(p); Coroutines.Init(p);
		Coroutines.Transfer(p);
		WHILE p.state = Coroutines.suspended DO
			StdLog.String("next ="); StdLog.Int(p.next); StdLog.Ln;
			Coroutines.Transfer(p)
		END
	END RunPlainCoroutine;

	PROCEDURE (this: Primes) Run;
		VAR t0: LONGINT; n, current, divisor, sqrtCur: INTEGER;
	BEGIN
		StdLog.String("BEGIN Primes"); StdLog.Ln;
		t0 := Services.Ticks();
		IF this.to < 2 THEN n := 0 ELSE n := 1 END;
		current := 3;
		WHILE current <= this.to DO
			divisor := 3;
			sqrtCur := SHORT(ENTIER(Math.Sqrt(current)));
			WHILE (divisor <= sqrtCur) & (current MOD divisor # 0) DO 
				IF divisor MOD 256 = 1 THEN this.Sleep(0) END;
				divisor := divisor + 2
			END;
			IF divisor > sqrtCur THEN (* current is prime *) INC(n) END;
			current := current + 2
		END;
		StdLog.String("END Primes: n ="); StdLog.Int(n);
		StdLog.String(", "); StdLog.RealForm((Services.Ticks() - t0) / 1000., 10, 0, -2, " "); 
		StdLog.String(" seconds"); StdLog.Ln
	END Run;

	PROCEDURE RunPrimes*;
		VAR scanner: TextMappers.Scanner; p: Primes;
	BEGIN
		scanner.ConnectTo(DevCommanders.par.text);
		scanner.SetPos(DevCommanders.par.beg);
		scanner.Scan;
		ASSERT(scanner.type = TextMappers.int);
		NEW(p); p.to := scanner.int; p.Start
	END RunPrimes;

	PROCEDURE (this: Fringe) Enumerate(t: Tree), NEW;
	BEGIN
		IF t # NIL THEN
			IF (t.left = NIL) & (t.right = NIL) THEN (* leaf *)
				this.next := t; this.Yield
			ELSE
				this.Enumerate(t.left); this.Enumerate(t.right)
			END
		END
	END Enumerate;

	PROCEDURE (this: Fringe) Run;
	BEGIN
		this.Enumerate(this.tree);
		this.next := NIL
	END Run;

	PROCEDURE ParseTree(VAR s: TextMappers.Scanner; OUT t: Tree);
	BEGIN
		IF (s.type = TextMappers.char) & (s.char = "~") THEN t := NIL
		ELSIF s.type = TextMappers.string THEN (* leaf *) NEW(t); t.name := s.string$
		ELSIF (s.type = TextMappers.char) & (s.char = "[") THEN NEW(t); s.Scan;
			ParseTree(s, t.left); ParseTree(s, t.right);
			IF (s.type # TextMappers.char) OR (s.char # "]") THEN
				StdLog.String("syntax error"); StdLog.Ln; HALT(128)
			END
		ELSE StdLog.String("syntax error"); StdLog.Ln; HALT(128)
		END;
		s.Scan
	END ParseTree;

	PROCEDURE RunSameFringe*;
		VAR scanner: TextMappers.Scanner; x, y: Fringe;
	BEGIN
		scanner.ConnectTo(DevCommanders.par.text);
		scanner.SetPos(DevCommanders.par.beg);
		scanner.Scan;		
		NEW(x); ParseTree(scanner, x.tree);
		NEW(y); ParseTree(scanner, y.tree);
		x.Next; y.Next;
		WHILE (x.next # NIL) & (y.next # NIL) & (x.next.name = y.next.name) DO
			x.Next; y.Next;
		END;
		StdLog.Bool((x.next = NIL) & (y.next = NIL)); StdLog.Ln
	END RunSameFringe;

END ObxCoroutines.
