MODULE Sequencers;
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

	IMPORT Stores;

	CONST
		clean* = 0; 
		notUndoable* = 1; 
		invisible* = 2;

	TYPE
		Message* = ABSTRACT RECORD END;
		
		Notifier* = POINTER TO ABSTRACT RECORD
			next: Notifier
		END;

		Sequencer* = POINTER TO ABSTRACT RECORD
			notifiers: Notifier
		END;

		CloseMsg* = RECORD (Message)
			sticky*: BOOLEAN	(** OUT, preset to FALSE **)
		END;

		RemoveMsg* = RECORD (Message) END;

		Directory* = POINTER TO ABSTRACT RECORD END;

	VAR dir*: Directory;

	(** Directory **)
	PROCEDURE (dir: Directory) New* (): Sequencer, NEW, ABSTRACT;

	PROCEDURE SetDir* (d: Directory);
	BEGIN
		ASSERT(d # NIL, 20); dir := d
	END SetDir;


	(** Notifier **)

	PROCEDURE (f: Notifier) Notify* (VAR msg: Message), NEW, EMPTY;


	(** Sequencer **)

	PROCEDURE (s: Sequencer) Dirty* (): BOOLEAN, NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) SetDirty* (dirty: BOOLEAN), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) BeginScript* (IN name: Stores.OpName;
																VAR script: Stores.Operation), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) Do* (st: Stores.Store; IN name: Stores.OpName;
														op: Stores.Operation), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) LastOp* (st: Stores.Store): Stores.Operation, NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) Bunch* (st: Stores.Store), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) EndScript* (script: Stores.Operation), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) StopBunching* (), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) BeginModification* (type: INTEGER; st: Stores.Store), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) EndModification* (type: INTEGER; st: Stores.Store), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) CanUndo* (): BOOLEAN, NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) CanRedo* (): BOOLEAN, NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) GetUndoName* (VAR name: Stores.OpName), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) GetRedoName* (VAR name: Stores.OpName), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) Undo* (), NEW, ABSTRACT;
	PROCEDURE (s: Sequencer) Redo* (), NEW, ABSTRACT;

	PROCEDURE (s: Sequencer) Handle* (VAR msg: ANYREC), NEW, EMPTY;

	PROCEDURE (s: Sequencer) Notify* (VAR msg: Message), NEW;
		VAR n: Notifier;
	BEGIN
		n := s.notifiers;
		WHILE n # NIL DO
			n.Notify(msg);
			n := n.next
		END
	END Notify;

	PROCEDURE (s: Sequencer) InstallNotifier* (n: Notifier), NEW;
	BEGIN
		n.next := s.notifiers; s.notifiers := n
	END InstallNotifier;

END Sequencers.
