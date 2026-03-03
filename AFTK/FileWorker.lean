module

public import LeanWorker

namespace AFTK

open Lean Parser Elab

structure CommandTree where
  stx : Syntax
  infoTree : InfoTree
  range? : Option Syntax.Range

structure Context where
  inputCtx : InputContext
  env : Environment
  infoTrees : PersistentArray InfoTree
  commandTrees : Array CommandTree

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

partial
def rootCommandStx? : InfoTree → Option Syntax
  | .context _ t => rootCommandStx? t
  | .node (.ofCommandInfo ci) _ => some ci.stx
  | .node _ children => children.toArray.findSome? rootCommandStx?
  | .hole _ => none

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
  let infoTrees := s.commandState.infoState.trees
  let commandTrees := infoTrees.toArray.filterMap fun infoTree => do
    let stx ← rootCommandStx? infoTree
    return {
      stx
      infoTree
      range? := stx.getRangeWithTrailing? (canonicalOnly := true)
    }
  return {
    inputCtx := ctx
    env := s.commandState.env
    infoTrees
    commandTrees
  }

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

structure Position where
  line : Nat
  col : Nat
deriving ToJson, FromJson

structure Range where
  start : Position
  stop : Position
deriving ToJson, FromJson

structure HoverResult where
  text : String
  range? : Option Range := none
deriving ToJson, FromJson

structure PlainGoalResult where
  goals : List String
  rendered : String
deriving ToJson, FromJson

structure PlainTermGoalResult where
  goal : String
  range? : Option Range := none
deriving ToJson, FromJson

structure InfoViewResult where
  hover? : Option HoverResult := none
  plainGoal? : Option PlainGoalResult := none
  plainTermGoal? : Option PlainTermGoalResult := none
deriving ToJson, FromJson

def toPosition (pos : Lean.Position) : Position :=
  ⟨pos.line, pos.column + 1⟩

def toRange (fileMap : FileMap) (r : Syntax.Range) : Range :=
  .mk (toPosition (fileMap.toPosition r.start)) (toPosition (fileMap.toPosition r.stop))

def rawPosAt (ctx : Context) (line col : Nat) :
    LeanWorker.Server.StatefulHandlerM Context State String.Pos.Raw := do
  if line == 0 then
    throw <| invalidParamsError "line must be >= 1"
  if col == 0 then
    throw <| invalidParamsError "col must be >= 1"
  let column := col - 1
  return ctx.inputCtx.fileMap.ofPosition { line, column }

def liftIO (action : IO α) : LeanWorker.Server.StatefulHandlerM Context State α := do
  match ← action.toBaseIO with
  | .ok value => return value
  | .error err => throw <| internalError (toString err)

def commandTreesAt (ctx : Context) (rawPos : String.Pos.Raw) : Array CommandTree := Id.run do
  let strict := ctx.commandTrees.filter (fun command =>
    command.range?.any (·.contains rawPos))
  if !strict.isEmpty then
    return strict
  let boundary := ctx.commandTrees.filter (fun command =>
    command.range?.any (·.contains rawPos (includeStop := true)))
  if !boundary.isEmpty then
    return boundary
  return ctx.commandTrees

def parserDocAt? (ctx : Context) (stx : Syntax) (rawPos : String.Pos.Raw) : IO (Option (String × Syntax.Range)) := do
  let stack? := stx.findStack? (·.getRange?.any (·.contains rawPos))
  match stack? with
  | none =>
    return none
  | some stack =>
    stack.findSomeM? fun (stx, _) => do
      let .node _ kind _ := stx
        | return none
      let docStr ← findDocString? ctx.env kind
      return docStr.map (·, stx.getRange?.get!)

def hoverInCommandAt? (ctx : Context) (command : CommandTree) (rawPos : String.Pos.Raw) : IO (Option HoverResult) := do
  let stxDoc? ← parserDocAt? ctx command.stx rawPos

  if let some result := command.infoTree.hoverableInfoAtM? (m := Id) rawPos then
    if let some range := result.info.range? then
      if stxDoc?.all (fun (_, stxRange) => stxRange.includes range) then
        if let some hoverFmt ← result.info.fmtHover? result.ctx then
          return some {
            text := toString hoverFmt.fmt
            range? := some <| toRange ctx.inputCtx.fileMap range
          }

  if let some (doc, range) := stxDoc? then
    return some {
      text := doc
      range? := some <| toRange ctx.inputCtx.fileMap range
    }

  return none

def getHoverAt? (ctx : Context) (rawPos : String.Pos.Raw) : IO (Option HoverResult) := do
  let mut hover? : Option HoverResult := none
  for command in commandTreesAt ctx rawPos do
    if hover?.isNone then
      hover? ← hoverInCommandAt? ctx command rawPos
  return hover?

def ppGoals (ctxInfo : ContextInfo) (goals : List MVarId) : IO (List String) :=
  ctxInfo.runMetaM {} do
    goals.mapM fun goal => goal.withContext do
      let ppGoal ← Meta.ppGoal goal
      return ppGoal.pretty

def getPlainGoalAt? (ctx : Context) (rawPos : String.Pos.Raw) : IO (Option PlainGoalResult) := do
  let goals : Array GoalsAtResult :=
    (commandTreesAt ctx rawPos).map (fun command =>
      command.infoTree.goalsAt? ctx.inputCtx.fileMap rawPos |>.toArray)
    |>.flatten

  if goals.isEmpty then
    return none

  let mut renderedGoals : List String := []
  for goal in goals do
    let beforeCtx := { goal.ctxInfo with mctx := goal.tacticInfo.mctxBefore }
    let afterCtx := { goal.ctxInfo with mctx := goal.tacticInfo.mctxAfter }
    let activeCtx := if goal.useAfter then afterCtx else beforeCtx
    let goalIds := if goal.useAfter then goal.tacticInfo.goalsAfter else goal.tacticInfo.goalsBefore
    renderedGoals := renderedGoals ++ (← ppGoals activeCtx goalIds)

  let rendered :=
    if renderedGoals.isEmpty then
      "no goals"
    else
      String.intercalate "\n\n---\n\n" renderedGoals

  return some { goals := renderedGoals, rendered }

def getPlainTermGoalAt? (ctx : Context) (rawPos : String.Pos.Raw) : IO (Option PlainTermGoalResult) := do
  for command in commandTreesAt ctx rawPos do
    match command.infoTree.termGoalAt? rawPos with
    | some { ctx := ci, info := i@(Info.ofTermInfo ti), .. } =>
      let ty ← ci.runMetaM i.lctx do
        instantiateMVars <| ti.expectedType?.getD (← Meta.inferType ti.expr)
      let lctx := if ti.isBinder then i.lctx.pop else i.lctx
      let goal ← ci.runMetaM lctx do
        let mvar ← Meta.mkFreshExprMVar ty
        mvar.mvarId!.withContext do
          let ppGoal ← Meta.ppGoal mvar.mvarId!
          return ppGoal.pretty
      return some {
        goal
        range? := i.range?.map (toRange ctx.inputCtx.fileMap)
      }
    | _ =>
      pure ()
  return none

def getInfoViewAt (ctx : Context) (rawPos : String.Pos.Raw) : IO InfoViewResult := do
  return {
    hover? := ← getHoverAt? ctx rawPos
    plainGoal? := ← getPlainGoalAt? ctx rawPos
    plainTermGoal? := ← getPlainTermGoalAt? ctx rawPos
  }

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
  let some ⟨line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  let rawPos ← rawPosAt ctx line col
  let goals : Array GoalsAtResult :=
    (commandTreesAt ctx rawPos).map (fun command =>
      command.infoTree.goalsAt? ctx.inputCtx.fileMap rawPos |>.toArray)
    |>.flatten
  let nodes ← goals.mapM mkNextState
  let result ← nodes.mapM fun node => do
    let nextId ← mkId
    modify fun s => { nodes := s.nodes.insert nextId node }
    return nextId
  return .mk result

def getHover : LeanWorker.Server.StatefulHandler Context State LoadNodeParam (Option HoverResult) := fun param => do
  let some ⟨line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  let rawPos ← rawPosAt ctx line col
  liftIO <| getHoverAt? ctx rawPos

def getPlainGoal : LeanWorker.Server.StatefulHandler Context State LoadNodeParam (Option PlainGoalResult) := fun param => do
  let some ⟨line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  let rawPos ← rawPosAt ctx line col
  liftIO <| getPlainGoalAt? ctx rawPos

def getPlainTermGoal : LeanWorker.Server.StatefulHandler Context State LoadNodeParam (Option PlainTermGoalResult) := fun param => do
  let some ⟨line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  let rawPos ← rawPosAt ctx line col
  liftIO <| getPlainTermGoalAt? ctx rawPos

def getInfoView : LeanWorker.Server.StatefulHandler Context State LoadNodeParam InfoViewResult := fun param => do
  let some ⟨line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  let rawPos ← rawPosAt ctx line col
  liftIO <| getInfoViewAt ctx rawPos

def server (transport : LeanWorker.Transport.Transport) : LeanWorker.Server.Server Context State where
  handlers := LeanWorker.Server.HandlerRegistry.empty
    |>.addStateful "get_goals" getGoals
    |>.addStateful "run_tactic" runTactic
    |>.addStateful "load_node" loadNode
    |>.addStateful "get_hover" getHover
    |>.addStateful "get_plain_goal" getPlainGoal
    |>.addStateful "get_plain_term_goal" getPlainTermGoal
    |>.addStateful "get_infoview" getInfoView
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

