import AFTK.Server.Protocol
import AFTK.FileWorker.Context
import AFTK.FileWorker.Informal
import Lean
import Lean.Server.InfoUtils
import LeanWorker

namespace AFTK.FileWorker.Queries

open Lean
open Lean.Parser
open Lean.Elab
open AFTK.Server.Protocol
open AFTK.FileWorker.Context
open LeanWorker.JsonRpc


def toPosition (pos : Lean.Position) : SourcePosition :=
  { line := pos.line, col := pos.column + 1 }


def toRange (fileMap : FileMap) (range : Syntax.Range) : SourceRange :=
  {
    start := toPosition (fileMap.toPosition range.start)
    stop := toPosition (fileMap.toPosition range.stop)
  }


def rangeContainsHoverPos
    (fileMap : FileMap)
    (range : Syntax.Range)
    (hoverPos : String.Pos.Raw)
    (includeStop : Bool := false) : Bool :=
  let isRangeAtEOF := range.stop == fileMap.source.rawEndPos
  range.contains hoverPos (includeStop := includeStop || isRangeAtEOF)


def rawPosAt (ctx : WorkerContext) (line col : Nat) : Except LeanWorker.JsonRpc.Error String.Pos.Raw := do
  if line == 0 then
    throw <| invalidParamsError "line must be >= 1"
  if col == 0 then
    throw <| invalidParamsError "col must be >= 1"
  pure <| ctx.inputCtx.fileMap.ofPosition { line := line, column := col - 1 }


def commandTreesAt (ctx : WorkerContext) (rawPos : String.Pos.Raw) : Array CommandTree := Id.run do
  let strict := ctx.commandTrees.filter fun command =>
    command.range?.any fun range => rangeContainsHoverPos ctx.inputCtx.fileMap range rawPos
  if !strict.isEmpty then
    return strict
  let boundary := ctx.commandTrees.filter fun command =>
    command.range?.any fun range =>
      rangeContainsHoverPos ctx.inputCtx.fileMap range rawPos (includeStop := true)
  if !boundary.isEmpty then
    return boundary
  return ctx.commandTrees


def parserDocAt? (ctx : WorkerContext) (stx : Syntax) (rawPos : String.Pos.Raw) : IO (Option (String × Syntax.Range)) := do
  let stack? := stx.findStack? (fun stx => stx.getRange?.any (fun range => range.contains rawPos))
  match stack? with
  | none =>
      pure none
  | some stack =>
      stack.findSomeM? fun (stx, _) => do
        let .node _ kind _ := stx
          | pure none
        let docStr ← findDocString? ctx.env kind
        pure <| docStr.map fun doc => (doc, stx.getRange?.get!)


def hoverInCommandAt? (ctx : WorkerContext) (command : CommandTree) (rawPos : String.Pos.Raw) : IO (Option HoverResult) := do
  let stxDoc? ← parserDocAt? ctx command.stx rawPos
  let infoResult? := command.infoTree.hoverableInfoAtM? (m := Id) rawPos

  let richHover? ←
    AFTK.FileWorker.Informal.richHoverAt?
      ctx command rawPos (infoResult?.map (·.ctx.options) |>.getD {})
  if richHover?.isSome then
    return richHover?

  if let some result := infoResult? then
    if let some range := result.info.range? then
      if stxDoc?.all fun (_, stxRange) => stxRange.includes range then
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

  pure none


def getHoverAt? (ctx : WorkerContext) (rawPos : String.Pos.Raw) : IO (Option HoverResult) := do
  let mut hover? := none
  for command in commandTreesAt ctx rawPos do
    if hover?.isNone then
      hover? ← hoverInCommandAt? ctx command rawPos
  pure hover?


def goalsAtPosition (ctx : WorkerContext) (rawPos : String.Pos.Raw) : Array GoalsAtResult :=
  (commandTreesAt ctx rawPos).map (fun command =>
    command.infoTree.goalsAt? ctx.inputCtx.fileMap rawPos |>.toArray)
  |>.flatten


private def ppGoals (ctxInfo : ContextInfo) (goals : List MVarId) : IO (Array String) :=
  ctxInfo.runMetaM {} do
    let rendered ← goals.mapM fun goal => goal.withContext do
      let ppGoal ← Meta.ppGoal goal
      pure ppGoal.pretty
    pure rendered.toArray


def getPlainGoalAt? (ctx : WorkerContext) (rawPos : String.Pos.Raw) : IO (Option PlainGoalResult) := do
  let goals := goalsAtPosition ctx rawPos
  if goals.isEmpty then
    return none

  let mut renderedGoals : Array String := #[]
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
      String.intercalate "\n\n---\n\n" renderedGoals.toList

  return some { goals := renderedGoals, rendered := rendered }


def getPlainTermGoalAt? (ctx : WorkerContext) (rawPos : String.Pos.Raw) : IO (Option PlainTermGoalResult) := do
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
            pure ppGoal.pretty
        return some {
          goal := goal
          range? := i.range?.map (toRange ctx.inputCtx.fileMap)
        }
    | _ =>
        pure ()
  return none


def getInfoViewAt (ctx : WorkerContext) (rawPos : String.Pos.Raw) : IO InfoViewResult :=
  return {
    hover? := ← getHoverAt? ctx rawPos
    plainGoal? := ← getPlainGoalAt? ctx rawPos
    plainTermGoal? := ← getPlainTermGoalAt? ctx rawPos
  }

end AFTK.FileWorker.Queries
