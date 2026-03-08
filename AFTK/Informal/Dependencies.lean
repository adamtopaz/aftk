import AFTK.Informal.Tracking
import Lean

namespace AFTK.Informal

open Lean

structure InformalDeclDependencyEntry where
  declName : Name
  dependencies : Array Name
  deriving Repr, Inhabited

structure InformalReferenceDependencyEntry where
  ref : InformalReference
  dependencies : Array InformalReference
  deriving Repr, Inhabited

private def refLt (a b : InformalReference) : Bool :=
  compare a b == .lt

private def nameLt (a b : Name) : Bool :=
  toString a < toString b

private def usedConstants (env : Environment) (declName : Name) : NameSet :=
  match env.find? declName with
  | some cinfo => cinfo.getUsedConstantsAsSet
  | none => {}

private def nameSetToList (names : NameSet) : List Name := Id.run do
  let mut out : List Name := []
  for name in names do
    out := name :: out
  return out

private def nameSetToSortedArray (names : NameSet) : Array Name := Id.run do
  let mut out : Array Name := #[]
  for name in names do
    out := out.push name
  out.qsort nameLt

private def refSetToSortedArray (refs : Std.HashSet InformalReference) : Array InformalReference := Id.run do
  let mut out : Array InformalReference := #[]
  for ref in refs do
    out := out.push ref
  out.qsort refLt

private partial def collectReachableTracked
    (env : Environment)
    (trackedDecls : NameSet)
    (root : Name)
    (todo : List Name)
    (visited : NameSet)
    (deps : NameSet) : NameSet :=
  match todo with
  | [] => deps
  | declName :: rest =>
      if declName == root || visited.contains declName then
        collectReachableTracked env trackedDecls root rest visited deps
      else
        let visited := visited.insert declName
        let deps := if trackedDecls.contains declName then deps.insert declName else deps
        let next := nameSetToList (usedConstants env declName)
        collectReachableTracked env trackedDecls root (next ++ rest) visited deps

private def transitiveDeclDependencyIndex
    (env : Environment)
    (entries : Array InformalDeclEntry) : Std.HashMap Name NameSet := Id.run do
  let trackedDecls := entries.foldl (init := {}) fun acc entry => acc.insert entry.declName
  let mut index : Std.HashMap Name NameSet := {}
  for entry in entries do
    let initial := nameSetToList (usedConstants env entry.declName)
    let deps := collectReachableTracked env trackedDecls entry.declName initial {} {}
    index := index.insert entry.declName deps
  return index

private def declReferenceIndex
    (entries : Array InformalDeclEntry) : Std.HashMap Name (Std.HashSet InformalReference) := Id.run do
  let mut index : Std.HashMap Name (Std.HashSet InformalReference) := {}
  for entry in entries do
    let mut refs : Std.HashSet InformalReference := {}
    for ref in entry.refs do
      refs := refs.insert ref
    index := index.insert entry.declName refs
  return index

private def referenceDeclIndex
    (entries : Array InformalReferenceEntry) : Std.HashMap InformalReference NameSet := Id.run do
  let mut index : Std.HashMap InformalReference NameSet := {}
  for entry in entries do
    let mut declNames : NameSet := {}
    for declName in entry.declNames do
      declNames := declNames.insert declName
    index := index.insert entry.ref declNames
  return index

private def referenceDependencyIndex
    (declDeps : Std.HashMap Name NameSet)
    (declRefs : Std.HashMap Name (Std.HashSet InformalReference))
    (refDecls : Std.HashMap InformalReference NameSet) : Std.HashMap InformalReference (Std.HashSet InformalReference) := Id.run do
  let mut index : Std.HashMap InformalReference (Std.HashSet InformalReference) := {}
  for (ref, declNames) in refDecls do
    let mut deps : Std.HashSet InformalReference := {}
    for declName in declNames do
      for depDecl in declDeps.getD declName {} do
        for depRef in declRefs.getD depDecl {} do
          deps := deps.insert depRef
    deps := deps.erase ref
    index := index.insert ref deps
  return index

/-- Return the derived declaration-dependency view for all tracked declarations. -/
def allInformalDeclDependencyEntries : CoreM (Array InformalDeclDependencyEntry) := do
  let entries ← allInformalDeclEntries
  let index := transitiveDeclDependencyIndex (← getEnv) entries
  pure <| entries.map (fun entry => {
    declName := entry.declName
    dependencies := nameSetToSortedArray (index.getD entry.declName {})
  })

/-- Look up one derived declaration-dependency row. -/
def informalDeclDependencyEntry? (declName : Name) : CoreM (Option InformalDeclDependencyEntry) := do
  let rows ← allInformalDeclDependencyEntries
  pure <| rows.find? fun row => row.declName == declName

/-- Return the tracked declarations whose derived dependency sets are empty. -/
def informalDeclDependencyLeaves : CoreM (Array Name) := do
  let rows ← allInformalDeclDependencyEntries
  pure <| (rows.filterMap fun row => if row.dependencies.isEmpty then some row.declName else none).qsort nameLt

/-- Return the projected reference-dependency view for all tracked references. -/
def allInformalReferenceDependencyEntries : CoreM (Array InformalReferenceDependencyEntry) := do
  let declEntries ← allInformalDeclEntries
  let refEntries ← allInformalReferenceEntries
  let declDeps := transitiveDeclDependencyIndex (← getEnv) declEntries
  let declRefs := declReferenceIndex declEntries
  let refDecls := referenceDeclIndex refEntries
  let refDeps := referenceDependencyIndex declDeps declRefs refDecls
  pure <| refEntries.map (fun entry => {
    ref := entry.ref
    dependencies := refSetToSortedArray (refDeps.getD entry.ref {})
  })

/-- Look up one projected reference-dependency row. -/
def informalReferenceDependencyEntry? (ref : InformalReference) : CoreM (Option InformalReferenceDependencyEntry) := do
  let rows ← allInformalReferenceDependencyEntries
  pure <| rows.find? fun row => row.ref == ref

/-- Return the tracked references whose projected dependency sets are empty. -/
def informalReferenceDependencyLeaves : CoreM (Array InformalReference) := do
  let rows ← allInformalReferenceDependencyEntries
  pure <| (rows.filterMap fun row => if row.dependencies.isEmpty then some row.ref else none).qsort refLt

end AFTK.Informal
