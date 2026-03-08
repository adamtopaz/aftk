import AFTK.Informal
import AFTK.FileWorker.Context
import AFTK.Server.Protocol
import Lean

namespace AFTK.FileWorker.Informal

open Lean
open AFTK.Informal
open AFTK.Server.Protocol
open AFTK.FileWorker.Context

private def toPosition (pos : Lean.Position) : SourcePosition :=
  { line := pos.line, col := pos.column + 1 }

private def toRange (fileMap : FileMap) (range : Syntax.Range) : SourceRange :=
  {
    start := toPosition (fileMap.toPosition range.start)
    stop := toPosition (fileMap.toPosition range.stop)
  }

structure InformalSite where
  rawRef : String
  range? : Option Syntax.Range := none

private def configuredKnowledgeBaseRoot? (opts : Options) : Option System.FilePath :=
  let raw := AFTK.Informal.aftk.informal.root.get opts
  let trimmed := raw.trimAscii.toString
  if trimmed.isEmpty then none else some trimmed


def informalSiteAt? (command : CommandTree) (rawPos : String.Pos.Raw) : Option InformalSite := do
  let stack ← command.stx.findStack? (fun stx => stx.getRange?.any (fun range => range.contains rawPos (includeStop := true)))
  stack.findSome? fun (stx, _) => do
    match stx with
    | `(informal[$ref:informalNodeId] $[$_args:term]*) =>
        let rawRef ← informalNodeIdString? ref.raw
        some {
          rawRef := rawRef
          range? := ref.raw.getRange? <|> stx.getRange?
        }
    | _ =>
        none


def richHoverAt?
    (ctx : WorkerContext)
    (command : CommandTree)
    (rawPos : String.Pos.Raw)
    (opts : Options := {}) : IO (Option HoverResult) := do
  let some site := informalSiteAt? command rawPos
    | return none
  let some ref :=
      match informalReferenceOfString? site.rawRef with
      | .ok ref => some ref
      | .error _ => none
    | return none
  let root? := configuredKnowledgeBaseRoot? opts
  match ← (resolveInformalReference ref root?).toIO' with
  | .ok resolved =>
      let text := renderPresentationText resolved .rich .preview
      return some {
        text := text
        range? := site.range?.map (toRange ctx.inputCtx.fileMap)
      }
  | .error _ =>
      return none

end AFTK.FileWorker.Informal
