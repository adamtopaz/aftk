import AFTK.Server.Protocol
import Lean
import Lean.Server.InfoUtils
import LeanWorker

namespace AFTK.FileWorker.TacticState

open Lean
open Lean.Parser
open Lean.Elab
open AFTK.Server.Protocol
open LeanWorker

structure StateNode where
  coreState : Core.State
  coreCtx : Core.Context
  metaState : Meta.State
  metaCtx : Meta.Context
  termState : Term.State
  termCtx : Term.Context
  tacticState : Tactic.State
  tacticCtx : Tactic.Context

structure State where
  nodes : Std.TreeMap String StateNode := {}
  nextId : Nat := 0

namespace StateNode

/-- Run a tactic computation from a stored state snapshot, returning the output and the next snapshot. -/
def runTacticM (node : StateNode) (go : Tactic.TacticM α) : IO (α × StateNode) := do
  let go := go.run node.tacticCtx
  let go := go.run node.tacticState
  let go := go.run node.termCtx node.termState
  let go := go.run node.metaCtx node.metaState
  let go := go.toIO node.coreCtx node.coreState
  let ((((value, tacticState), termState), metaState), coreState) ← go
  let nextNode : StateNode := {
    node with
    coreState := coreState
    metaState := metaState
    termState := termState
    tacticState := tacticState
  }
  pure (value, nextNode)

end StateNode

private def captureNodeM (_goal : GoalsAtResult) : Tactic.TacticM StateNode := do
  return {
    coreCtx := ← readThe Core.Context
    metaCtx := ← readThe Meta.Context
    termCtx := ← readThe Term.Context
    tacticCtx := ← readThe Tactic.Context
    coreState := ← getThe Core.State
    metaState := ← getThe Meta.State
    termState := ← getThe Term.State
    tacticState := ← getThe Tactic.State
  }


def captureNode (goal : GoalsAtResult) : IO StateNode := do
  let mctx := if goal.useAfter then goal.tacticInfo.mctxAfter else goal.tacticInfo.mctxBefore
  let goals := if goal.useAfter then goal.tacticInfo.goalsAfter else goal.tacticInfo.goalsBefore
  let action : IO StateNode :=
    { goal.ctxInfo with mctx := mctx }.runMetaM {} <|
      (captureNodeM goal).run { elaborator := .anonymous } |>.run' { goals := goals } |>.run'
  action


def goalsOfNode (node : StateNode) : IO (Array String) := do
  let (goals, _) ← node.runTacticM do
    let goalIds ← Tactic.getUnsolvedGoals
    let goals ← goalIds.mapM fun goal => goal.withContext do
      let ppGoal ← Meta.ppGoal goal
      pure ppGoal.pretty
    pure goals.toArray
  pure goals


private def parseTactic (node : StateNode) (tactic : String) : Except JsonRpc.Error Syntax :=
  match Parser.runParserCategory node.coreState.env `tactic tactic with
  | .ok parsed =>
      .ok parsed
  | .error err =>
      .error <| invalidParamsError s!"failed to parse tactic: {err}"


def runTacticOnNode (node : StateNode) (tactic : String) : ExceptT JsonRpc.Error IO (Array String × StateNode) := do
  let parsed ←
    match parseTactic node tactic with
    | .ok parsed =>
        pure parsed
    | .error err =>
        throw err
  let result ←
    match ← (node.runTacticM do
      Tactic.evalTactic parsed
      let goalIds ← Tactic.getUnsolvedGoals
      let goals ← goalIds.mapM fun goal => goal.withContext do
        let ppGoal ← Meta.ppGoal goal
        pure ppGoal.pretty
      pure goals.toArray).toBaseIO with
    | .ok result =>
        pure result
    | .error err =>
        throw <| tacticFailedError (toString err)
  pure result


abbrev HandlerM (Context : Type) := LeanWorker.Server.StatefulHandlerM Context State


def freshId : HandlerM Context String := do
  let current ← get
  let nextId := current.nextId
  set { current with nextId := nextId + 1 }
  pure s!"node-{nextId}"


def insertNode (node : StateNode) : HandlerM Context String := do
  let id ← freshId
  modify fun state => { state with nodes := state.nodes.insert id node }
  pure id


def insertNodes (nodes : Array StateNode) : HandlerM Context (Array String) := do
  let mut ids := #[]
  for node in nodes do
    ids := ids.push (← insertNode node)
  pure ids


def getNode (id : String) : HandlerM Context StateNode := do
  let some node := (← get).nodes.get? id
    | throw <| staleNodeError id
  pure node


def getGoals (id : String) : HandlerM Context GetGoalsResult := do
  let node ← getNode id
  let goals ←
    match ← (goalsOfNode node).toBaseIO with
    | .ok goals =>
        pure goals
    | .error err =>
        throw <| internalError (toString err)
  pure { goals := goals }


def runTactic (id : String) (tactic : String) : HandlerM Context RunTacticResult := do
  let node ← getNode id
  let (goals, nextNode) ←
    match ← (runTacticOnNode node tactic).run.toBaseIO with
    | .ok (.ok result) =>
        pure result
    | .ok (.error err) =>
        throw err
    | .error err =>
        throw <| internalError (toString err)
  let nextId ← insertNode nextNode
  pure { goals := goals, nextId := nextId }

end AFTK.FileWorker.TacticState
