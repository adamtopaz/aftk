module

public import AFTK.Informal.Syntax
public import AFTK.Informal.Placeholder
public import AFTK.Informal.References
public import AFTK.Informal.Tracking
public import AFTK.Informal.Presentation
public import AFTK.Informal.Options
public import Lean
public meta import AFTK.Informal.Syntax
public meta import AFTK.Informal.Placeholder
public meta import AFTK.Informal.References
public meta import AFTK.Informal.Tracking
public meta import AFTK.Informal.Presentation
public meta import AFTK.Informal.Options
public meta import Lean

public section


namespace AFTK.Informal

open Lean Elab Term Meta
open AFTK.KnowledgeBase

private meta def configuredKnowledgeBaseRoot? : CoreM (Option System.FilePath) := do
  let raw := aftk.informal.root.get (← getOptions)
  let trimmed := raw.trimAscii.toString
  pure <| if trimmed.isEmpty then none else some trimmed

private meta def nameContainsComponent (name : Name) (target : String) : Bool :=
  match name with
  | .anonymous => false
  | .str parent component => component == target || nameContainsComponent parent target
  | .num parent _ => nameContainsComponent parent target

private meta def isCommandPseudoDeclName (declName : Name) : Bool :=
  declName == `_check ||
    declName == `_reduce ||
    declName == `_synth_cmd ||
    nameContainsComponent declName "_eval"

private meta def mkUniqueTag : TermElabM Name := do
  let ref ← getRef
  if let (some startSPos, some endSPos) := (ref.getPos?, ref.getTailPos?) then
    let fileMap ← getFileMap
    SorryLabelView.encode {
      module? := some {
        module := (← getMainModule)
        range := {
          pos := fileMap.toPosition startSPos
          endPos := fileMap.toPosition endSPos
          charUtf16 := (fileMap.utf8PosToLspPos startSPos).character
          endCharUtf16 := (fileMap.utf8PosToLspPos endSPos).character
        }
      }
    }
  else
    SorryLabelView.encode {}

private meta def resolveReferenceAt
    (refStx : Syntax)
    (ref : InformalReference) : TermElabM ResolvedInformalReference := do
  let root? ← configuredKnowledgeBaseRoot?
  let result ← liftM <| (resolveInformalReference ref root?).toIO'
  match result with
  | .ok resolved =>
      pure resolved
  | .error err =>
      throwErrorAt refStx s!"{err.message}"

private meta def mkInformalExpr (expectedType : Expr) (argExprs : Array Expr) : TermElabM Expr := do
  let expectedType ← instantiateMVars expectedType
  let argExprs ← argExprs.mapM instantiateMVars
  let argTypes ← argExprs.mapM fun argExpr => do
    instantiateMVars (← inferType argExpr)
  let α := argTypes.foldr (init := expectedType) fun argType body =>
    mkForall `arg .default argType body
  let tag ← mkUniqueTag
  let level ← Meta.getLevel α
  let informalConst := Lean.mkConst ``AFTK.Informal.Informal [level]
  pure <| mkAppN (mkApp2 informalConst (toExpr tag) α) argExprs

private meta def addReferenceHoverInfo
    (stx : Syntax)
    (summary : InformalPresentationSummary)
    (expr : Expr)
    (expectedType? : Option Expr) : TermElabM Unit := do
  let info : DelabTermInfo := {
    elaborator := `AFTK.Informal.elabInformalTermWithRef
    stx := stx
    lctx := (← getLCtx)
    expectedType? := expectedType?
    expr := expr
    docString? := some (renderSummaryText summary)
  }
  Elab.pushInfoLeaf <| .ofDelabTermInfo info

private meta def elabInformalTerm
    (stx : Syntax)
    (refStx : Syntax)
    (args : Array (TSyntax `term))
    (expectedType? : Option Expr) : TermElabM Expr := do
  let some declName := (← getDeclName?)
    | throwError "`informal[...]` may only be used inside declaration values or proofs"
  if isCommandPseudoDeclName declName then
    throwError "`informal[...]` may only be used inside declaration values or proofs"

  let some rawRef := informalNodeIdString? refStx
    | throwErrorAt refStx "invalid `informal[...]` reference syntax"
  let ref ←
    match informalReferenceOfString? rawRef with
    | .ok ref => pure ref
    | .error err => throwErrorAt refStx s!"Invalid informal node id '{rawRef}': {err}"
  let resolved ← resolveReferenceAt refStx ref
  let argExprs ← args.mapM fun arg => withRef arg <| elabTerm arg none
  let expectedType ←
    match expectedType? with
    | some expectedType => instantiateMVars expectedType
    | none => mkFreshTypeMVar
  let expr ← mkInformalExpr expectedType argExprs
  Term.synthesizeSyntheticMVarsNoPostponing
  let expr ← instantiateMVars expr
  let expectedType? := some (← instantiateMVars expectedType)
  let summary := summaryOfResolved resolved
  addReferenceHoverInfo stx summary expr expectedType?
  addInformalOccurrence declName ref
  pure expr

@[term_elab informalTermWithRef] meta def elabInformalTermWithRef : TermElab := fun stx expectedType? => do
  match stx with
  | `(informal[$ref:informalNodeId] $[$args:term]*) =>
      elabInformalTerm stx ref.raw args expectedType?
  | _ =>
      throwUnsupportedSyntax

end AFTK.Informal
