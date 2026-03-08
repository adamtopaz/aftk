module

public import AFTK.Informal.References
public import Lean

public section


namespace AFTK.Informal

open Lean

structure InformalOccurrence where
  declName : Name
  ref : InformalReference
  deriving Repr, Inhabited, BEq, Hashable

abbrev InformalTrackingState := Std.HashMap Name (Std.HashSet InformalReference)

structure InformalDeclEntry where
  declName : Name
  refs : Array InformalReference
  deriving Repr, Inhabited

structure InformalReferenceEntry where
  ref : InformalReference
  declNames : Array Name
  deriving Repr, Inhabited

private def addOccurrenceToState
    (state : InformalTrackingState)
    (occurrence : InformalOccurrence) : InformalTrackingState :=
  let refs := (state.getD occurrence.declName {}).insert occurrence.ref
  state.insert occurrence.declName refs

private def mkStateFromImported
    (imported : Array (Array InformalOccurrence)) : InformalTrackingState := Id.run do
  let mut state : InformalTrackingState := {}
  for importedOccurrences in imported do
    for occurrence in importedOccurrences do
      state := addOccurrenceToState state occurrence
  return state

initialize informalExt : SimplePersistentEnvExtension InformalOccurrence InformalTrackingState ←
  registerSimplePersistentEnvExtension {
    name := `AFTK.Informal.informalExt
    addEntryFn := addOccurrenceToState
    addImportedFn := mkStateFromImported
    toArrayFn := fun entries => entries.toArray
    asyncMode := .sync
  }

private def getInformalState : CoreM InformalTrackingState := do
  return informalExt.getState (← getEnv)

private def refLt (a b : InformalReference) : Bool :=
  compare a b == .lt

private def nameLt (a b : Name) : Bool :=
  toString a < toString b

private def nameArrayFromSet (names : NameSet) : Array Name := Id.run do
  let mut namesArr : Array Name := #[]
  for name in names do
    namesArr := namesArr.push name
  namesArr.qsort nameLt

private def refArrayFromSet (refs : Std.HashSet InformalReference) : Array InformalReference := Id.run do
  let mut refsArr : Array InformalReference := #[]
  for ref in refs do
    refsArr := refsArr.push ref
  refsArr.qsort refLt

private def reverseIndexFromState
    (state : InformalTrackingState) : Std.HashMap InformalReference NameSet := Id.run do
  let mut index : Std.HashMap InformalReference NameSet := {}
  for (declName, refs) in state do
    for ref in refs do
      let declNames := (index.getD ref {}).insert declName
      index := index.insert ref declNames
  index

/-- Record one successful `informal[...]` elaboration occurrence. -/
def addInformalOccurrence (declName : Name) (ref : InformalReference) : CoreM Unit := do
  modifyEnv fun env =>
    informalExt.addEntry env { declName, ref }

/-- Return all tracked declarations together with their deduplicated references. -/
def allInformalDeclEntries : CoreM (Array InformalDeclEntry) := do
  let state ← getInformalState
  let mut entries : Array InformalDeclEntry := #[]
  for (declName, refs) in state do
    if !refs.isEmpty then
      entries := entries.push {
        declName,
        refs := refArrayFromSet refs
      }
  pure <| entries.qsort fun a b => nameLt a.declName b.declName

/-- Look up the tracked references for a single declaration. -/
def informalDeclEntry? (declName : Name) : CoreM (Option InformalDeclEntry) := do
  let state ← getInformalState
  match state.get? declName with
  | some refs =>
      if refs.isEmpty then
        pure none
      else
        pure <| some {
          declName,
          refs := refArrayFromSet refs
        }
  | none =>
      pure none

/-- Return all tracked references together with the declarations that reference them. -/
def allInformalReferenceEntries : CoreM (Array InformalReferenceEntry) := do
  let index := reverseIndexFromState (← getInformalState)
  let mut entries : Array InformalReferenceEntry := #[]
  for (ref, declNames) in index do
    entries := entries.push {
      ref,
      declNames := nameArrayFromSet declNames
    }
  pure <| entries.qsort fun a b => refLt a.ref b.ref

/-- Look up the declarations that reference one tracked node. -/
def informalReferenceEntry? (ref : InformalReference) : CoreM (Option InformalReferenceEntry) := do
  let index := reverseIndexFromState (← getInformalState)
  match index.get? ref with
  | some declNames =>
      pure <| some {
        ref,
        declNames := nameArrayFromSet declNames
      }
  | none =>
      pure none

end AFTK.Informal
