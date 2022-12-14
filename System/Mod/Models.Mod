MODULE Models;
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
	
	IMPORT Kernel, Stores, Sequencers;

	CONST
		minVersion = 0; maxVersion = 0;

		clean* = Sequencers.clean; 
		notUndoable* = Sequencers.notUndoable;
		invisible* = Sequencers.invisible; 

	TYPE
		Model* = POINTER TO ABSTRACT RECORD (Stores.Store)
			era: INTEGER;	(* stable era >= x *)
			guard: INTEGER	(* = TrapCount()+1 if model is addressee of ongoing broadcast *)
		END;

		Context* = POINTER TO ABSTRACT RECORD END;

		Proposal* = ABSTRACT RECORD END;


		Message* = ABSTRACT RECORD
			model-: Model;
			era-: INTEGER
		END;

		NeutralizeMsg* = RECORD (Message) END;

		UpdateMsg* = EXTENSIBLE RECORD (Message) END;

		
	VAR domainGuard: INTEGER;	(* = TrapCount()+1 if domain is addressee of ongoing domaincast *)


	(** Model **)

	PROCEDURE (m: Model) Internalize- (VAR rd: Stores.Reader), EXTENSIBLE;
		VAR thisVersion: INTEGER;
	BEGIN
		m.Internalize^(rd);
		IF rd.cancelled THEN RETURN END;
		rd.ReadVersion(minVersion, maxVersion, thisVersion)
	END Internalize;

	PROCEDURE (m: Model) Externalize- (VAR wr: Stores.Writer), EXTENSIBLE;
	BEGIN
		m.Externalize^(wr);
		wr.WriteVersion(maxVersion)
	END Externalize;
	

	(** Context **)

	PROCEDURE (c: Context) ThisModel* (): Model, NEW, ABSTRACT;
	PROCEDURE (c: Context) Normalize* (): BOOLEAN, NEW, ABSTRACT;
	PROCEDURE (c: Context) GetSize* (OUT w, h: INTEGER), NEW, ABSTRACT;
	PROCEDURE (c: Context) SetSize* (w, h: INTEGER), NEW, EMPTY;
	PROCEDURE (c: Context) MakeVisible* (l, t, r, b: INTEGER), NEW, EMPTY;
	PROCEDURE (c: Context) Consider* (VAR p: Proposal), NEW, EMPTY;


	(** miscellaneous **)

	PROCEDURE Era* (m: Model): INTEGER;
	BEGIN
		ASSERT(m # NIL, 20);
		RETURN m.era
	END Era;


	PROCEDURE CopyOf* (m: Model): Model;
	BEGIN
		ASSERT(m # NIL, 20);
		RETURN Stores.CopyOf(m)(Model)
	END CopyOf;

	PROCEDURE BeginScript* (m: Model; name: Stores.OpName; OUT script: Stores.Operation);
	(** post: (script # NIL) iff (m.domain # NIL) **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20);
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				seq.BeginScript(name, script)
			ELSE
			END
		ELSE script := NIL
		END
	END BeginScript;

	PROCEDURE Do* (m: Model; name: Stores.OpName; op: Stores.Operation);
	(** pre: m # NIL, op # NIL, ~op.inUse **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20); ASSERT(op # NIL, 21); (* ASSERT(~op.inUse, 22); *)
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				seq.Do(m, name, op)
			ELSE
				op.Do
			END
		ELSE
			op.Do
		END
	END Do;

	PROCEDURE LastOp* (m: Model): Stores.Operation;
	(** pre: m # NIL **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20);
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				RETURN seq.LastOp(m)
			ELSE
				RETURN NIL
			END
		ELSE
			RETURN NIL
		END
	END LastOp;

	PROCEDURE Bunch* (m: Model);
	(** pre: m # NIL, m.Domain() # NIL **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20); ASSERT(m.Domain() # NIL, 21);
		seq := m.Domain().GetSequencer();
		ASSERT(seq # NIL, 22);
		WITH seq: Sequencers.Sequencer DO
			seq.Bunch(m)
		ELSE
		END
	END Bunch;

	PROCEDURE StopBunching* (m: Model);
	(** pre: m # NIL **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20);
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				seq.StopBunching
			ELSE
			END
		END
	END StopBunching;

	PROCEDURE EndScript* (m: Model; script: Stores.Operation);
	(** pre: (script # NIL) iff (m.seq # NIL) **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20);
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			ASSERT(script # NIL, 21);
			WITH seq: Sequencers.Sequencer DO
				seq.EndScript(script)
			ELSE
				ASSERT(script = NIL, 21)
			END
		ELSE
			ASSERT(script = NIL, 21)
		END
	END EndScript;


	PROCEDURE BeginModification* (type: INTEGER; m: Model);
	(** pre: m # NIL **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20);
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				seq.BeginModification(type, m)
			ELSE
			END
		END
	END BeginModification;

	PROCEDURE EndModification* (type: INTEGER; m: Model);
	(** pre: m # NIL **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20);
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				seq.EndModification(type, m)
			ELSE
			END
		END
	END EndModification;

	PROCEDURE SetDirty* (m: Model);
	(** pre: m # NIL **)
		VAR seq: ANYPTR;
	BEGIN
		ASSERT(m # NIL, 20);
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				seq.SetDirty(TRUE)
			ELSE
			END
		END
	END SetDirty;

	PROCEDURE Domaincast* (d: Stores.Domain; VAR msg: Message);
		VAR g: INTEGER; seq: ANYPTR;
	BEGIN
		IF d # NIL THEN
			seq := d.GetSequencer();
			IF (seq # NIL) & (seq IS Sequencers.Sequencer) THEN
				msg.model := NIL; msg.era := -1;
				g := Kernel.trapCount + 1;
				IF domainGuard > 0 THEN ASSERT(domainGuard # g, 20) END;
				domainGuard := g;
				seq(Sequencers.Sequencer).Handle(msg);
				domainGuard := 0
			END
		END
	END Domaincast;

	PROCEDURE Broadcast* (m: Model; VAR msg: Message);
	(** pre: model # NIL **)
	(** post: model.era > model.era', msg.model = model, msg.era = model.era' + 1,
		model.seq # NIL => msg sent to seq **)
		VAR seq: ANYPTR; g: INTEGER;
	BEGIN
		ASSERT(m # NIL, 20);
		msg.model := m;
		IF m.Domain() # NIL THEN seq := m.Domain().GetSequencer() ELSE seq := NIL END;
		IF seq # NIL THEN
			WITH seq: Sequencers.Sequencer DO
				INC(m.era); msg.era := m.era;
				g := Kernel.trapCount + 1;
				IF m.guard > 0 THEN ASSERT(m.guard # g, 21) END;
				m.guard := g;
				seq.Handle(msg);
				m.guard := 0
			ELSE
			END
		END
	END Broadcast;

BEGIN
	domainGuard := 0
END Models.
