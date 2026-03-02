module

public import LeanWorker

namespace AFTK

open Lean Parser Elab

structure Context where
  inputCtx : InputContext
  infoTrees : PersistentArray InfoTree

structure State where
  coreState : Core.State
  coreCtx : Core.Context
  metaState : Meta.State
  metaCtx :  Meta.Context
  termState : Term.State
  termCtx : Term.Context
  tacticState : Tactic.State
  tacticCtx : Tactic.Context

def State.runTacticM (s : State) (go : Tactic.TacticM α) : 
    IO (α × State) := do 
  let go := go.run s.tacticCtx
  let go := go.run s.tacticState
  let go := go.run s.termCtx s.termState
  let go := go.run s.metaCtx s.metaState
  let go := go.toIO s.coreCtx s.coreState
  let ((((a, tacticState), termState), metaState),coreState) ← go
  let nextState : State := { s with coreState, metaState, termState, tacticState }
  return (a, nextState)

unsafe
def getContext (path : System.FilePath) (opts : Options) : IO Context := do
  let input ← IO.FS.readFile path
  let ctx := mkInputContext input "<AFTK>"
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let (header, parserState, messages) ← Parser.parseHeader <| ctx
  let (env, messages) ← processHeader header opts messages <| ctx
  let commandState := { Command.mkState env messages opts with infoState.enabled := true }
  let s ← IO.processCommands ctx parserState commandState
  return .mk ctx s.commandState.infoState.trees

def runTacticM (go : Tactic.TacticM α) : LeanWorker.Server.StatefulHandlerM Context State α := do
  let s ← get
  match ← s.runTacticM go |>.toBaseIO with
  | .ok (out, nextState) => 
    set nextState
    return out
  | .error err => 
    throw <| {
      code := -4000,
      message := toString err
    }

structure RunTacticParam where
  tactic : String

structure Goals where
  goals : List String
deriving ToJson

def getGoals : LeanWorker.Server.StatefulHandler Context State Json.Structured Goals := fun _ => do
  runTacticM do 
    let goals ← Tactic.getUnsolvedGoals 
    let goals : List String ← goals.mapM fun goal => goal.withContext do
      let ppGoal ← Meta.ppGoal goal
      return ppGoal.pretty
    return ⟨goals⟩

def runTactic : LeanWorker.Server.StatefulHandler Context State RunTacticParam Goals := fun param => do
  let some ⟨tac⟩ := param | throw { code := -4000, message := "Invalid param" }
  runTacticM do 
    let .ok tac := Parser.runParserCategory (← getEnv) `tacitc tac | throwError "Failed to parse tactic"
    Tactic.evalTactic tac 
    let goals ← Tactic.getUnsolvedGoals 
    let goals : List String ← goals.mapM fun goal => goal.withContext do
      let ppGoal ← Meta.ppGoal goal
      return ppGoal.pretty
    return ⟨goals⟩

def server (transport : LeanWorker.Transport.Transport) : LeanWorker.Server.Server Context State where
  handlers := LeanWorker.Server.HandlerRegistry.empty 
    |>.addStateful "get_goals" getGoals
  notifications := .empty
  transport := transport

end AFTK

public unsafe
def main : IO Unit := do
  let ctx ← AFTK.getContext "Test.lean" {}
  let mut idx : Nat := 0
  while True do
    for tree in ctx.infoTrees do
      let ⟨ctxInfo, tacInfo, _, _, _⟩ :: _ := Lean.Elab.InfoTree.goalsAt? ctx.inputCtx.fileMap tree ⟨idx⟩ | continue
      let s : AFTK.State ← { ctxInfo with mctx := tacInfo.mctxBefore }.runMetaM {} do 
        let go : Lean.Elab.Tactic.TacticM AFTK.State := 
          return {
            coreCtx := ← readThe Lean.Core.Context
            metaCtx := ← readThe Lean.Meta.Context
            termCtx := ← readThe Lean.Elab.Term.Context
            tacticCtx := ← readThe Lean.Elab.Tactic.Context
            coreState := ← getThe Lean.Core.State
            metaState := ← getThe Lean.Meta.State
            termState := ← getThe Lean.Elab.Term.State
            tacticState := ← getThe Lean.Elab.Tactic.State
          }
        let go := go.run { elaborator := .anonymous }
        let go := go.run' { goals := tacInfo.goalsBefore }
        go.run'
      let transport ← LeanWorker.Transport.serverTransportFromStdio |>.block
      let server := LeanWorker.Server.run (AFTK.server transport) ctx <| ← Std.Mutex.new s
      server.block
    idx := idx + 1

