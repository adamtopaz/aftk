module

public import Lean

public section

namespace Informalize

open Lean

structure InformalOccurrence where
  declName : Name
  location? : Option Name := none
  deriving Inhabited, Repr, BEq

abbrev InformalState := Std.HashMap Name NameSet

structure InformalDeclEntry where
  declName : Name
  locations : NameSet := {}
  deriving Inhabited

private def mergeLocation
    (locations : NameSet)
    (location? : Option Name) : NameSet :=
  match location? with
  | some location =>
    locations.insert location
  | none =>
    locations

private def addOccurrenceToState
    (state : InformalState)
    (occurrence : InformalOccurrence) : InformalState :=
  let locations := mergeLocation (state.getD occurrence.declName {}) occurrence.location?
  state.insert occurrence.declName locations

private def mkStateFromImported
    (imported : Array (Array InformalOccurrence)) : InformalState := Id.run do
  let mut state : InformalState := {}
  for importedOccurrences in imported do
    for occurrence in importedOccurrences do
      state := addOccurrenceToState state occurrence
  return state

initialize informalExt : SimplePersistentEnvExtension InformalOccurrence InformalState ←
  registerSimplePersistentEnvExtension {
    name := `Informalize.informalExt
    addEntryFn := addOccurrenceToState
    addImportedFn := mkStateFromImported
    toArrayFn := fun entries => entries.toArray
    asyncMode := .sync
  }

def addInformalOccurrence
    (declName : Name)
    (location? : Option Name := none) : CoreM Unit :=
  modifyEnv fun env =>
    informalExt.addEntry env {
      declName
      location?
    }

private def getInformalState : CoreM InformalState := do
  let env ← getEnv
  return informalExt.getState env

private def declEntryLt (a b : InformalDeclEntry) : Bool :=
  Name.quickLt a.declName b.declName

def allInformalDeclEntries : CoreM (Array InformalDeclEntry) := do
  let state ← getInformalState
  let mut entries : Array InformalDeclEntry := #[]
  for (declName, locations) in state do
    entries := entries.push {
      declName
      locations
    }
  return entries.qsort declEntryLt

def informalDeclEntry? (declName : Name) : CoreM (Option InformalDeclEntry) := do
  let state ← getInformalState
  match state.get? declName with
  | some locations =>
    return some {
      declName
      locations
    }
  | none =>
    return none

end Informalize
