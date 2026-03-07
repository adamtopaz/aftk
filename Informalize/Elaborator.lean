module

public import Lean
public import Informalize.Axiom
public import Informalize.Extension
public import Informalize.Location
public import Informalize.Metadata
public meta import Informalize.Extension
public meta import Informalize.Location
public meta import Informalize.Metadata
public meta import Init.Data.String.Legacy

public section

open Lean Elab Term Meta

namespace Informalize

syntax (name := informalTermWithLoc) "informal[" ident "]" (ppSpace term:max)* : term
syntax (name := informalTermNoLoc) "informal" (ppSpace term:max)* : term

private structure ResolvedInformalId where
  location : LocationId
  markdown : String
  loadedMetadata : LoadedMetadata

private meta def parseLocationId (idStx : TSyntax `ident) : TermElabM LocationId := do
  match LocationId.ofName idStx.getId with
  | .ok location =>
    pure location
  | .error err =>
    throwErrorAt idStx err

private meta def resolveInformalId (idStx : TSyntax `ident) : TermElabM ResolvedInformalId := do
  let location ← parseLocationId idStx
  let markdown ←
    match ← location.readMarkdown with
    | .ok markdown =>
      pure markdown
    | .error err =>
      throwErrorAt idStx err
  let loadedMetadata ←
    match ← loadEffectiveMetadata location with
    | .ok loadedMetadata =>
      pure loadedMetadata
    | .error err =>
      throwErrorAt idStx err
  return {
    location,
    markdown,
    loadedMetadata
  }

private meta def addLocationHoverInfo
    (idStx : TSyntax `ident)
    (location : LocationId)
    (markdown : String)
    (loadedMetadata : LoadedMetadata) : TermElabM Unit := do
  let info : DelabTermInfo := {
    elaborator := `Informalize.resolveInformalId
    stx := idStx
    lctx := (← getLCtx)
    expectedType? := some (mkConst ``Name)
    expr := toExpr location.name
    docString? := some (LoadedMetadata.renderHoverText location loadedMetadata markdown)
  }
  Elab.pushInfoLeaf <| .ofDelabTermInfo info

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

private meta def nameContainsComponent (name : Name) (target : String) : Bool :=
  match name with
  | .anonymous =>
    false
  | .str parent component =>
    component == target || nameContainsComponent parent target
  | .num parent _ =>
    nameContainsComponent parent target

private meta def isCommandPseudoDeclName (declName : Name) : Bool :=
  declName == `_check ||
    declName == `_reduce ||
    declName == `_synth_cmd ||
    nameContainsComponent declName "_eval"

private meta def mkInformalExpr (expectedType : Expr) (argExprs : Array Expr) : TermElabM Expr := do
  let expectedType ← instantiateMVars expectedType
  let argExprs ← argExprs.mapM instantiateMVars
  let argTypes ← argExprs.mapM fun argExpr => do
    instantiateMVars (← Meta.inferType argExpr)
  let alpha := argTypes.foldr (init := expectedType) fun argType body =>
    mkForall `arg .default argType body
  let tag ← mkUniqueTag
  let level ← Meta.getLevel alpha
  let informalConst := Lean.mkConst ``Informalize.Informal [level]
  let informalExpr := mkApp2 informalConst (toExpr tag) alpha
  return mkAppN informalExpr argExprs

private meta def runInformalElab
    (location? : Option (TSyntax `ident))
    (args : Array (TSyntax `term))
    (expectedType? : Option Expr) : TermElabM Expr := do
  let some declName := (← getDeclName?)
    | throwError "`informal` may only be used inside declaration values or proofs"
  if isCommandPseudoDeclName declName then
    throwError "`informal` may only be used inside declaration values or proofs"
  let locationId? ←
    match location? with
    | some location =>
      let resolved ← resolveInformalId location
      addLocationHoverInfo location resolved.location resolved.markdown resolved.loadedMetadata
      pure (some resolved.location.name)
    | none =>
      pure none
  let argExprs ← args.mapM fun arg =>
    withRef arg <| elabTerm arg none
  let expectedType ←
    match expectedType? with
    | some expectedType =>
      instantiateMVars expectedType
    | none =>
      mkFreshTypeMVar
  let expr ← mkInformalExpr expectedType argExprs
  Term.synthesizeSyntheticMVarsNoPostponing
  let expr ← instantiateMVars expr
  addInformalOccurrence declName locationId?
  return expr

@[term_elab informalTermWithLoc] meta def elabInformalTermWithLoc : TermElab := fun stx expectedType? => do
  match stx with
  | `(informal[$id:ident] $[$args:term]*) =>
    runInformalElab (some id) args expectedType?
  | _ =>
    throwUnsupportedSyntax

@[term_elab informalTermNoLoc] meta def elabInformalTermNoLoc : TermElab := fun stx expectedType? => do
  match stx with
  | `(informal $[$args:term]*) =>
    runInformalElab none args expectedType?
  | _ =>
    throwUnsupportedSyntax

end Informalize
