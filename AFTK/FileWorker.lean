module

public import LeanWorker

namespace AFTK

open Lean Parser Elab

structure Context where
  inputCtx : InputContext
  infoTrees : PersistentArray InfoTree

structure StateNode where
  coreState : Core.State
  coreCtx : Core.Context
  metaState : Meta.State
  metaCtx :  Meta.Context
  termState : Term.State
  termCtx : Term.Context
  tacticState : Tactic.State
  tacticCtx : Tactic.Context

structure State where
  nodes : Std.TreeMap String StateNode

def StateNode.runTacticM (s : StateNode) (go : Tactic.TacticM α) : 
    IO (α × StateNode) := do 
  let go := go.run s.tacticCtx
  let go := go.run s.tacticState
  let go := go.run s.termCtx s.termState
  let go := go.run s.metaCtx s.metaState
  let go := go.toIO s.coreCtx s.coreState
  let ((((a, tacticState), termState), metaState),coreState) ← go
  let nextState : StateNode := { s with coreState, metaState, termState, tacticState }
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

def mkId : BaseIO String := do
  let hexDigits : Array Char := #['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']
  let variantDigits : Array Char := #['8', '9', 'a', 'b']

  let randHex : BaseIO Char := do
    let i ← IO.rand 0 15
    return hexDigits[i]!

  let mkPart (len : Nat) : BaseIO String := do
    let mut out := ""
    for _ in [:len] do
      out := out.push (← randHex)
    return out

  let p1 ← mkPart 8
  let p2 ← mkPart 4
  let p3 ← mkPart 3
  let p4 ← mkPart 3
  let p5 ← mkPart 12

  let variantIdx ← IO.rand 0 3
  let variant := variantDigits[variantIdx]!

  return s!"{p1}-{p2}-4{p3}-{variant}{p4}-{p5}"

def invalidParamsError (message : String) : LeanWorker.JsonRpc.Error :=
  LeanWorker.JsonRpc.Error.withData LeanWorker.JsonRpc.Error.invalidParams (.str message)

def internalError (message : String) : LeanWorker.JsonRpc.Error :=
  LeanWorker.JsonRpc.Error.withData LeanWorker.JsonRpc.Error.internalError (.str message)

def tacticFailedError (message : String) : LeanWorker.JsonRpc.Error :=
  { code := -32001, message := "Tactic failed", data? := some (.str message) }

def runTacticM (id : String) (go : Tactic.TacticM α)
    (onError : String → LeanWorker.JsonRpc.Error := internalError) :
    LeanWorker.Server.StatefulHandlerM Context State (α × String) := do
  let some s := (← get).nodes.get? id
    | throw <| invalidParamsError s!"unknown node id: {id}"
  match ← s.runTacticM go |>.toBaseIO with
  | .ok (out, nextState) =>
    let nextId ← mkId
    modify fun s => { nodes := s.nodes.insert nextId nextState }
    return (out, nextId)
  | .error err =>
    throw <| onError (toString err)

structure GetGoalsParam where
  id : String

structure GetGoalsResult where
  goals : List String
deriving ToJson

instance : LeanWorker.JsonRpc.FromStructured GetGoalsParam where fromStructured?
  | .obj kvs => do
    let id : String ←
      match kvs.get? "id" with
      | some (.str id) => pure id
      | some _ => throw "id must be a string"
      | none => throw "id field required"
    return ⟨id⟩
  | .arr _ => throw "object expected"

structure RunTacticParam where
  id : String
  tactic : String

instance : LeanWorker.JsonRpc.FromStructured RunTacticParam where fromStructured?
  | .obj kvs => do
    let id : String ←
      match kvs.get? "id" with
      | some (.str id) => pure id
      | some _ => throw "id must be a string"
      | none => throw "id field required"
    let tactic : String ←
      match kvs.get? "tactic" with
      | some (.str tactic) => pure tactic
      | some _ => throw "tactic must be a string"
      | none => throw "tactic field required"
    return ⟨id, tactic⟩
  | .arr _ => throw "object expected"

structure RunTacticResult where
  goals : List String
  nextId : String
deriving ToJson

structure LoadNodeParam where
  line : Nat
  col : Nat

instance : LeanWorker.JsonRpc.FromStructured LoadNodeParam where fromStructured?
  | .obj kvs => do
    let line ←
      match kvs.get? "line" with
      | some json => json.getNat?
      | none => throw "line field required"
    let col ←
      match kvs.get? "col" with
      | some json => json.getNat?
      | none => throw "col field required"
    return ⟨line, col⟩
  | .arr _ => throw "object expected"

structure LoadNodeResult where
  id : Array String
deriving ToJson

def getGoals : LeanWorker.Server.StatefulHandler Context State GetGoalsParam GetGoalsResult := fun param => do
  let some ⟨id⟩ := param
    | throw <| invalidParamsError "params object required"
  Prod.fst <$> runTacticM id do
    let goals ← Tactic.getUnsolvedGoals 
    let goals : List String ← goals.mapM fun goal => goal.withContext do
      let ppGoal ← Meta.ppGoal goal
      return ppGoal.pretty
    return ⟨goals⟩

def runTactic : LeanWorker.Server.StatefulHandler Context State RunTacticParam RunTacticResult := fun param => do
  let some ⟨id, tacStr⟩ := param
    | throw <| invalidParamsError "params object required"
  let currentNodes := (← get).nodes
  let some node := currentNodes.get? id
    | throw <| invalidParamsError s!"unknown node id: {id}"
  let tac : Syntax ←
    match Parser.runParserCategory node.coreState.env `tactic tacStr with
    | .ok tac => pure tac
    | .error err => throw <| invalidParamsError s!"failed to parse tactic: {err}"
  let ⟨goals, nextId⟩ ← runTacticM id (onError := tacticFailedError) do
    Tactic.evalTactic tac
    let goals ← Tactic.getUnsolvedGoals
    let goals : List String ← goals.mapM fun goal => goal.withContext do
      let ppGoal ← Meta.ppGoal goal
      return ppGoal.pretty
    return goals
  return ⟨goals, nextId⟩

def mkNextState (goal : GoalsAtResult) : LeanWorker.Server.StatefulHandlerM Context State StateNode := do
  let go : Tactic.TacticM StateNode := do
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
  let go : IO StateNode := { goal.ctxInfo with mctx := goal.tacticInfo.mctxBefore }.runMetaM {} <|
    go.run { elaborator := .anonymous } |>.run' { goals := goal.tacticInfo.goalsBefore } |>.run'
  match ← go.toBaseIO with
  | .ok out => return out
  | .error err => throw <| internalError (toString err)

def loadNode : LeanWorker.Server.StatefulHandler Context State LoadNodeParam LoadNodeResult := fun param => do
  let some ⟨line, column⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  let rawPos := (← read).inputCtx.fileMap.ofPosition {line, column}
  let goals : Array GoalsAtResult := (ctx.infoTrees.map fun tree => 
    tree.goalsAt? ctx.inputCtx.fileMap rawPos |>.toArray).toArray |>.flatten
  let nodes ← goals.mapM mkNextState
  let result ← nodes.mapM fun node => do 
    let nextId ← mkId
    modify fun s => { nodes := s.nodes.insert nextId node }
    return nextId
  return .mk result

def server (transport : LeanWorker.Transport.Transport) : LeanWorker.Server.Server Context State where
  handlers := LeanWorker.Server.HandlerRegistry.empty 
    |>.addStateful "get_goals" getGoals
    |>.addStateful "run_tactic" runTactic
    |>.addStateful "load_node" loadNode
  notifications := .empty
  transport := transport

end AFTK

public unsafe
def main (args : List String) : IO Unit := do
  let [path] := args | throw <| .userError "Invalid args"
  let ctx ← AFTK.getContext path {}
  let transport ← LeanWorker.Transport.serverTransportFromStdio |>.block
  let server := LeanWorker.Server.run (AFTK.server transport) ctx <| ← Std.Mutex.new <| .mk {}
  server.block

