module

public import AFTK.Server.Protocol
public import AFTK.Server.Transport
public import AFTK.FileWorker.Context
public import AFTK.FileWorker.Queries
public import AFTK.FileWorker.TacticState
public import LeanWorker

public section


namespace AFTK.FileWorker.Handlers

open Lean
open LeanWorker
open AFTK.Server.Protocol
open AFTK.FileWorker.Context
open AFTK.FileWorker.Queries
open AFTK.FileWorker.TacticState

structure RuntimeContext where
  worker : WorkerContext

abbrev HandlerM := LeanWorker.Server.StatefulHandlerM RuntimeContext State

private def withRawPos (ctx : WorkerContext) (line col : Nat) (k : String.Pos.Raw → HandlerM α) : HandlerM α := do
  match rawPosAt ctx line col with
  | .ok rawPos =>
      k rawPos
  | .error err =>
      throw err

private def liftIO (action : IO α) : HandlerM α := do
  match ← action.toBaseIO with
  | .ok value =>
      pure value
  | .error err =>
      throw <| internalError (toString err)


def handleGetHover : LeanWorker.Server.StatefulHandler RuntimeContext State WorkerLocationParam (Option HoverResult) :=
  fun param => do
    let some ⟨line, col⟩ := param
      | throw <| invalidParamsError "params object required"
    let worker := (← read).worker
    withRawPos worker line col fun rawPos =>
      liftIO <| getHoverAt? worker rawPos


def handleGetPlainGoal : LeanWorker.Server.StatefulHandler RuntimeContext State WorkerLocationParam (Option PlainGoalResult) :=
  fun param => do
    let some ⟨line, col⟩ := param
      | throw <| invalidParamsError "params object required"
    let worker := (← read).worker
    withRawPos worker line col fun rawPos =>
      liftIO <| getPlainGoalAt? worker rawPos


def handleGetPlainTermGoal : LeanWorker.Server.StatefulHandler RuntimeContext State WorkerLocationParam (Option PlainTermGoalResult) :=
  fun param => do
    let some ⟨line, col⟩ := param
      | throw <| invalidParamsError "params object required"
    let worker := (← read).worker
    withRawPos worker line col fun rawPos =>
      liftIO <| getPlainTermGoalAt? worker rawPos


def handleGetInfoView : LeanWorker.Server.StatefulHandler RuntimeContext State WorkerLocationParam InfoViewResult :=
  fun param => do
    let some ⟨line, col⟩ := param
      | throw <| invalidParamsError "params object required"
    let worker := (← read).worker
    withRawPos worker line col fun rawPos =>
      liftIO <| getInfoViewAt worker rawPos


def handleLoadNode : LeanWorker.Server.StatefulHandler RuntimeContext State WorkerLocationParam LoadNodeResult :=
  fun param => do
    let some ⟨line, col⟩ := param
      | throw <| invalidParamsError "params object required"
    let worker := (← read).worker
    withRawPos worker line col fun rawPos => do
      let goals := goalsAtPosition worker rawPos
      let nodes ← liftIO <| goals.mapM captureNode
      let ids ← insertNodes nodes
      pure { id := ids }


def handleGetGoals : LeanWorker.Server.StatefulHandler RuntimeContext State WorkerNodeParam GetGoalsResult :=
  fun param => do
    let some ⟨id⟩ := param
      | throw <| invalidParamsError "params object required"
    TacticState.getGoals id


def handleRunTactic : LeanWorker.Server.StatefulHandler RuntimeContext State WorkerRunTacticParam RunTacticResult :=
  fun param => do
    let some ⟨id, tactic⟩ := param
      | throw <| invalidParamsError "params object required"
    TacticState.runTactic id tactic


def server (transport : AFTK.Server.Transport.JsonTransport) : LeanWorker.Server.Server RuntimeContext State where
  handlers := LeanWorker.Server.HandlerRegistry.empty
    |>.addStateful "load_node" handleLoadNode
    |>.addStateful "get_hover" handleGetHover
    |>.addStateful "get_plain_goal" handleGetPlainGoal
    |>.addStateful "get_plain_term_goal" handleGetPlainTermGoal
    |>.addStateful "get_infoview" handleGetInfoView
    |>.addStateful "get_goals" handleGetGoals
    |>.addStateful "run_tactic" handleRunTactic
  notifications := .empty
  transport := transport

end AFTK.FileWorker.Handlers
