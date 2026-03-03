module

public import Lean
public import Informalize.Axiom
public import Informalize.Extension
public meta import Informalize.Extension
public meta import Init.Data.String.Legacy

public section

open Lean Elab Term Meta

namespace Informalize

syntax (name := informalTermWithLoc) "informal[" ident "]" (ppSpace term:max)* : term
syntax (name := informalTermNoLoc) "informal" (ppSpace term:max)* : term

private meta def renderId (components : Array String) : String :=
  ".".intercalate components.toList

private meta def mkNameFromComponents (components : Array String) : Name :=
  components.foldl (init := .anonymous) fun acc component =>
    .str acc component

private meta def nameComponents (name : Name) : Except String (Array String) := do
  let rec go : Name -> Except String (List String)
    | .anonymous =>
      pure []
    | .str parent component => do
      let parts ← go parent
      pure (parts ++ [component])
    | .num _ _ =>
      throw "numeric components are not supported in informal ids"
  return (← go name).toArray

private meta def parseIdComponents
    (idStx : TSyntax `ident) : TermElabM (String × String × Name) := do
  let components ←
    match nameComponents idStx.getId with
    | .ok components =>
      pure components
    | .error err =>
      throwErrorAt idStx err
  if components.size < 2 then
    throwErrorAt idStx s!"informal id `{renderId components}` must have at least two components (`Directory.File`)"
  let pathComponents := Id.run do
    let mut path : Array String := #[]
    for idx in [0:components.size] do
      match components[idx]? with
      | some component =>
        if idx + 1 == components.size then
          path := path.push s!"{component}.md"
        else
          path := path.push component
      | none =>
        pure ()
    return path
  let filePath := s!"informal/{"/".intercalate pathComponents.toList}"
  return (filePath, renderId components, mkNameFromComponents components)

private structure ResolvedInformalId where
  locationName : Name
  markdown : String

private meta def resolveInformalId (idStx : TSyntax `ident) : TermElabM ResolvedInformalId := do
  let (filePath, renderedId, locationName) ← parseIdComponents idStx
  let pathExists ← (System.FilePath.pathExists filePath : IO Bool)
  if !pathExists then
    throwErrorAt idStx s!"informal id `{renderedId}` points to missing file `{filePath}`"
  let markdown ←
    try
      (IO.FS.readFile filePath : IO String)
    catch _ =>
      throwErrorAt idStx s!"unable to read `{filePath}` for informal id `{renderedId}`"
  return {
    locationName
    markdown
  }

private meta def addLocationHoverInfo
    (idStx : TSyntax `ident)
    (locationName : Name)
    (markdown : String) : TermElabM Unit := do
  let info : DelabTermInfo := {
    elaborator := `Informalize.resolveInformalId
    stx := idStx
    lctx := (← getLCtx)
    expectedType? := some (mkConst ``Name)
    expr := toExpr locationName
    docString? := some markdown
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
      addLocationHoverInfo location resolved.locationName resolved.markdown
      pure (some resolved.locationName)
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
