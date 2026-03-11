module

public import AFTK.KnowledgeBase.Service
public import AFTK.Informal.Service
public import LeanWorker

public section


namespace AFTK.Server.Protocol

open Lean
open LeanWorker
open LeanWorker.JsonRpc
open AFTK.KnowledgeBase
open AFTK.Informal

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

structure KnowledgeBaseRootParam where
  root? : Option String := none
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseNodeParam where
  root? : Option String := none
  id : NodeId
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseListParam where
  root? : Option String := none
  prefix? : Option String := none
  kind? : Option NodeKind := none
  status? : Option NodeStatus := none
  tag? : Option String := none
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseCreateParam where
  root? : Option String := none
  id : NodeId
  title : String
  body? : Option String := none
  kind? : Option NodeKind := none
  status? : Option NodeStatus := none
  summary? : Option String := none
  tags? : Option (Array String) := none
  authors? : Option (Array String) := none
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseRenameParam where
  root? : Option String := none
  oldId : NodeId
  newId : NodeId
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseSetBodyParam where
  root? : Option String := none
  id : NodeId
  body : String
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseReplaceMetadataParam where
  root? : Option String := none
  id : NodeId
  metadata : Json
  deriving Inhabited, FromJson

structure KnowledgeBaseSearchTextParam where
  root? : Option String := none
  query : String
  limit? : Option Nat := none
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseSearchTagParam where
  root? : Option String := none
  tag : String
  limit? : Option Nat := none
  deriving Repr, Inhabited, FromJson

structure KnowledgeBaseListResult where
  nodes : Array NodeMetadata := #[]
  deriving Repr, Inhabited, ToJson

structure KnowledgeBaseBodyResult where
  id : NodeId
  body : String
  deriving Repr, Inhabited, ToJson

structure KnowledgeBasePathsResult where
  id : NodeId
  paths : NodePaths
  deriving Repr, Inhabited, ToJson

structure KnowledgeBaseRenameResult where
  oldId : NodeId
  stored : StoredNode
  deriving Repr, ToJson

structure KnowledgeBaseDeleteResult where
  id : NodeId
  deleted : Bool := true
  deriving Repr, Inhabited, ToJson

structure KnowledgeBaseOutgoingRelationshipsResult where
  id : NodeId
  relationships : Array Relationship := #[]
  deriving Repr, Inhabited, ToJson

structure KnowledgeBaseIncomingRelationshipsResult where
  id : NodeId
  relationships : Array Search.IncomingRelationship := #[]
  deriving Repr, Inhabited, ToJson

structure InformalModulesParam where
  modules : Array String
  deriving Repr, Inhabited, FromJson

structure InformalDeclsParam where
  modules : Array String
  prefix? : Option String := none
  ref? : Option InformalReference := none
  deriving Repr, Inhabited, FromJson

structure InformalDeclParam where
  modules : Array String
  declName : String
  deriving Repr, Inhabited, FromJson

structure InformalRefsParam where
  modules : Array String
  prefix? : Option String := none
  deriving Repr, Inhabited, FromJson

structure InformalRefParam where
  modules : Array String
  ref : InformalReference
  deriving Repr, Inhabited, FromJson

structure InformalDepsParam where
  modules : Array String
  onlyLeaves? : Option Bool := none
  deriving Repr, Inhabited, FromJson

structure InformalPresentParam where
  root? : Option String := none
  ref : InformalReference
  mode? : Option PresentationMode := none
  bodyMode? : Option BodyRenderMode := none
  deriving Repr, Inhabited, FromJson

structure InformalDeclDto where
  declName : String
  refs : Array InformalReference := #[]
  refCount : Nat
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure InformalRefDto where
  ref : InformalReference
  declNames : Array String := #[]
  declCount : Nat
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure InformalDeclDependencyDto where
  declName : String
  dependencies : Array String := #[]
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure InformalRefDependencyDto where
  ref : InformalReference
  dependencies : Array InformalReference := #[]
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

structure InformalDeclsResult where
  entries : Array InformalDeclDto := #[]
  deriving Repr, Inhabited, ToJson, FromJson

structure InformalDeclResult where
  entry : InformalDeclDto
  deriving Repr, Inhabited, ToJson, FromJson

structure InformalRefsResult where
  entries : Array InformalRefDto := #[]
  deriving Repr, Inhabited, ToJson, FromJson

structure InformalRefResult where
  entry : InformalRefDto
  deriving Repr, Inhabited, ToJson, FromJson

structure InformalDeclDepsResult where
  rows : Array InformalDeclDependencyDto := #[]
  leaves : Array String := #[]
  deriving Repr, Inhabited, ToJson, FromJson

structure InformalRefDepsResult where
  rows : Array InformalRefDependencyDto := #[]
  leaves : Array InformalReference := #[]
  deriving Repr, Inhabited, ToJson, FromJson

abbrev InformalStatusResult := AFTK.Informal.Service.StatusInfo
abbrev InformalPresentResult := AFTK.Informal.Service.PresentResult
abbrev KnowledgeBaseStatusResult := AFTK.KnowledgeBase.Service.StatusInfo

structure DomainErrorData where
  layer : String
  code : String
  message : String
  exitCode : Nat
  deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

namespace ErrorCode

def tacticFailed : Int := -32001

def fileNotOpen : Int := -32010

def fileChanged : Int := -32011

def workerUnavailable : Int := -32012

def staleNode : Int := -32013

def domainNotFound : Int := -32020

def domainValidation : Int := -32021

def domainConflict : Int := -32022

def domainError : Int := -32023

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

private def domainErrorData (layer : String) (err : KnowledgeBaseError) : DomainErrorData :=
  {
    layer := layer
    code := err.code
    message := err.message
    exitCode := err.exitCode.toNat
  }


def knowledgeBaseError (layer : String) (err : KnowledgeBaseError) : JsonRpc.Error :=
  match err.exitCode.toNat with
  | 2 => invalidParamsError err.message
  | 3 => {
      code := ErrorCode.domainNotFound
      message := err.message
      data? := some <| toJson (domainErrorData layer err)
    }
  | 4 => {
      code := ErrorCode.domainValidation
      message := err.message
      data? := some <| toJson (domainErrorData layer err)
    }
  | 5 => {
      code := ErrorCode.domainConflict
      message := err.message
      data? := some <| toJson (domainErrorData layer err)
    }
  | _ => {
      code := ErrorCode.domainError
      message := err.message
      data? := some <| toJson (domainErrorData layer err)
    }

end AFTK.Server.Protocol
