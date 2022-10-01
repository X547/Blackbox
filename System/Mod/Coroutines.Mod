MODULE Coroutines;
(**
	project	= "BlackBox"
	organization	= "blackboxframework.org/"
	contributors	= "Josef Templ, Dmitry V.Dagaev"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	changes	= ""
	issues	= ""

**)

	IMPORT Kernel, Services;

	CONST
		(* Coroutine state *)
		uninitialized* = 0; suspended* = 1; running* = 2; returned* = 3; trapped* = 4;
		sleep0base = 48;
		
	TYPE
		Coroutine* = POINTER TO ABSTRACT RECORD
			state-: INTEGER; (* Coroutine state *)
			parent-, source-: Coroutine;
			impl: Kernel.Coroutine;
		END;
		
		Iterator* = POINTER TO ABSTRACT RECORD (Coroutine)
		END;
		
		Action = POINTER TO RECORD (Services.Action)
			target: Coroutine
		END;
		
		Task* = POINTER TO ABSTRACT RECORD (Coroutine)
			action: Action;
			time: LONGINT;
		END;
		
		MainCoroutine = POINTER TO RECORD (Coroutine) END;
		
	VAR
		main-, current-: Coroutine;
		stackMin-, stackMax-: INTEGER;
		nofTasks, sleep0: INTEGER;

	PROCEDURE (this: Coroutine) Run- (), NEW, ABSTRACT;

	PROCEDURE (this: MainCoroutine) Run ();
	BEGIN HALT(20) (* must never be called *)
	END Run;

	PROCEDURE TryHandler (a, b, c: INTEGER);
		VAR this: Coroutine;
	BEGIN
		this := current;
		Kernel.SetCoroutineBase(this.impl);
		WITH this: Task DO
			this.time := Services.Ticks(); INC(nofTasks); sleep0 := sleep0base DIV nofTasks;
		ELSE
		END;
		this.parent := this.source;
		this.Run();
		(* coroutine returned; transfer to parent *)
		this.state := returned;
		IF this IS Task THEN DEC(nofTasks); sleep0 := sleep0base DIV MAX(nofTasks, 1) END;
		ASSERT(this.parent.state = suspended, 80); (* parent not alive *)
		current := this.parent;
		current.state := running;
		current.source := this;
		Kernel.RemoveCoroutine(this.impl);
		Kernel.TransferCoroutine(current.impl)
	END TryHandler;

	PROCEDURE Start (par: INTEGER);
		VAR this: Coroutine;
	BEGIN
		this := current;
		Kernel.Try(TryHandler, 0, 0, 0);
		(* coroutine trapped; transfer to main *)
		this.state := trapped;
		IF this IS Task THEN DEC(nofTasks); sleep0 := sleep0base DIV MAX(nofTasks, 1)  END;
		main.state := running;
		main.source := this;
		current := main;
		Kernel.RemoveCoroutine(this.impl);
		Kernel.TransferCoroutine(main.impl)
	END Start;

	PROCEDURE SetStackSize* (min, max: INTEGER);
	BEGIN
		stackMin := min; stackMax := max
	END SetStackSize;
	
	PROCEDURE Cleanup*;
	BEGIN
		IF main # NIL THEN main.source := NIL END
	END Cleanup;

	PROCEDURE InitMain;
		VAR m: MainCoroutine;
	BEGIN
		NEW(m); NEW(m.impl);
		Kernel.BeginCoroutines(m.impl);
		ASSERT(m.impl # NIL); (* no coroutine support *)
		m.state := running;
		main := m; current := m
	END InitMain;

	PROCEDURE Init* (this: Coroutine);
		VAR done: BOOLEAN;
	BEGIN
		ASSERT(this # NIL, 20);
		ASSERT(this.state = uninitialized, 21);
		IF main = NIL THEN InitMain END;
		NEW(this.impl);
		Kernel.AddCoroutine(this.impl, Start, 0, stackMin, stackMax, done);
		IF ~done THEN (* out of stack space; Kernel.Collect may free some stacks *)
			Kernel.Collect();
			Kernel.AddCoroutine(this.impl, Start, 0, stackMin, stackMax, done);
			IF ~done THEN
				(* if the stack space is still exhausted the trap window may fail to open.
				Therefore we clean up and collect again before trapping. *)
				Cleanup; Kernel.Collect()
			END
		END;
		IF done THEN this.state := suspended
		ELSE ASSERT(done, 80)	(* stack space exhausted *)
		END
	END Init;

	PROCEDURE Transfer* (target: Coroutine);
	BEGIN
		ASSERT(target.state = suspended, 20); (* => target # current *)
		current.state := suspended;
		target.source := current;
		target.state := running;
		current := target;
		Kernel.TransferCoroutine(target.impl)
	END Transfer;
	
	PROCEDURE (this: Iterator) Next*, NEW;
	BEGIN
		IF this.state = uninitialized THEN Init(this) END;
		Transfer(this);
		ASSERT(current.source = this, 80);
		ASSERT(this.state # trapped, 81)
	END Next;
	
	PROCEDURE (this: Iterator) Yield*, NEW;
	BEGIN
		Transfer(this.parent);
		ASSERT(this.source = this.parent, 80)
	END Yield;

	PROCEDURE (this: Action) Do;
	BEGIN
		Transfer(this.target)
	END Do;

	PROCEDURE (this: Task) Start*, NEW;
	BEGIN
		ASSERT(this.parent = NIL, 20);
		ASSERT(current = main, 21);
		IF this.state = uninitialized THEN Init(this) END;
		Transfer(this);
		ASSERT(this.source = main, 80)
	END Start;

	PROCEDURE (this: Task) Sleep* (msecs: LONGINT), NEW;
	BEGIN
		ASSERT(this.state = running, 20);
		IF this.action = NIL THEN NEW(this.action); this.action.target := this END;
		IF msecs = 0 THEN (* continue this task until timeout *)
			IF Services.Ticks() < this.time + sleep0 THEN RETURN (* this.source is unchanged *)
			ELSE Services.DoLater(this.action, Services.now)
			END
		ELSIF msecs > 0 THEN
			Services.DoLater(this.action, Services.Ticks() + msecs)
		ELSE
			ASSERT(msecs >= 0, 21)
		END;
		Transfer(main); this.time := Services.Ticks();
		ASSERT(this.source = main, 80)
	END Sleep;

	PROCEDURE FiniMain;
	BEGIN
		IF main # NIL THEN
			ASSERT(current = main, 20);
			main.state := uninitialized; main.impl := NIL;
			Kernel.EndCoroutines
		END
	END FiniMain;

CLOSE FiniMain
END Coroutines.
