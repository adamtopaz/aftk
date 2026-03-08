module

public import LeanWorker

public section


namespace AFTK.Server.Protocol

open Lean
open LeanWorker
open LeanWorker.JsonRpc

/-! Shared request/response types and error helpers for the AFTK server layer. -/

structure OpenParam where
  path : String
  deriving Repr, Inhabited, FromJson

structure OpenResult where
  path : String
  opened : Bool
  deriving Repr, Inhabited, ToJson, FromJson

structure CloseParam where
  path : String
  deriving Repr, Inhabited, FromJson

structure CloseResult where
  path : String
  closed : Bool
  deriving Repr, Inhabited, ToJson, FromJson

structure FileLocationParam where
  path : String
  line : Nat
  col : Nat
  deriving Repr, Inhabited, FromJson

structure WorkerLocationParam where
  line : Nat
  col : Nat
  deriving Repr, Inhabited, FromJson

structure FileNodeParam where
  path : String
  id : String
  deriving Repr, Inhabited, FromJson

structure WorkerNodeParam where
  id : String
  deriving Repr, Inhabited, FromJson

structure RunTacticParam where
  path : String
  id : String
  tactic : String
  deriving Repr, Inhabited, FromJson

structure WorkerRunTacticParam where
  id : String
  tactic : String
  deriving Repr, Inhabited, FromJson

structure RunTacticStepsParam where
  path : String
  id : String
  tactics : Array String
  deriving Repr, Inhabited, FromJson

structure ShutdownParam where
  deriving Repr, Inhabited, FromJson

structure SourcePosition where
  line : Nat
  col : Nat
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure SourceRange where
  start : SourcePosition
  stop : SourcePosition
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure HoverResult where
  text : String
  range? : Option SourceRange := none
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure PlainGoalResult where
  goals : Array String
  rendered : String
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure PlainTermGoalResult where
  goal : String
  range? : Option SourceRange := none
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure InfoViewResult where
  hover? : Option HoverResult := none
  plainGoal? : Option PlainGoalResult := none
  plainTermGoal? : Option PlainTermGoalResult := none
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure LoadNodeResult where
  id : Array String
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure GetGoalsResult where
  goals : Array String
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure RunTacticResult where
  goals : Array String
  nextId : String
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure RunTacticStepsResult where
  results : Array RunTacticResult
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure ShutdownResult where
  stopped : Nat
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure WorkerShutdownResult where
  shuttingDown : Bool := true
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

namespace ErrorCode

def tacticFailed : Int := -32001

def fileNotOpen : Int := -32010

def fileChanged : Int := -32011

def workerUnavailable : Int := -32012

def staleNode : Int := -32013

end ErrorCode

def invalidParamsError (message : String) : JsonRpc.Error :=
  JsonRpc.Error.withData JsonRpc.Error.invalidParams (.str message)


def internalError (message : String) : JsonRpc.Error :=
  JsonRpc.Error.withData JsonRpc.Error.internalError (.str message)


def tacticFailedError (message : String) : JsonRpc.Error :=
  { code := ErrorCode.tacticFailed, message := "Tactic failed", data? := some (.str message) }


def fileNotOpenError (path : String) : JsonRpc.Error :=
  { code := ErrorCode.fileNotOpen, message := "File is not open", data? := some (.str path) }


def fileChangedError (path : String) : JsonRpc.Error :=
  { code := ErrorCode.fileChanged, message := "File changed; reopen required", data? := some (.str path) }


def workerUnavailableError (path : String) : JsonRpc.Error :=
  { code := ErrorCode.workerUnavailable, message := "File worker is unavailable", data? := some (.str path) }


def staleNodeError (id : String) : JsonRpc.Error :=
  { code := ErrorCode.staleNode, message := "Stale or unknown node id", data? := some (.str id) }

end AFTK.Server.Protocol
