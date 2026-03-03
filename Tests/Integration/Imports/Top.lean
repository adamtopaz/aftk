import Tests.Integration.Imports.Mid

open Lean Elab Command

namespace Tests.Integration.Imports.Top

noncomputable def topLoc : Nat :=
  informal[Alpha.root.child.grandchild] Tests.Integration.Imports.Mid.midLoc

noncomputable def topBare : Nat :=
  informal Tests.Integration.Imports.Mid.midBare

private def entryFor?
    (entries : Array Informalize.InformalDeclEntry)
    (declName : Name) : Option Informalize.InformalDeclEntry :=
  entries.find? (·.declName == declName)

private def locationCount (locations : NameSet) : Nat := Id.run do
  let mut count := 0
  for _ in locations do
    count := count + 1
  return count

private def assertLocationSet
    (entries : Array Informalize.InformalDeclEntry)
    (declName : Name)
    (expectedCount : Nat)
    (required : List Name) : CommandElabM Unit := do
  let some entry := entryFor? entries declName
    | throwError s!"missing tracked declaration `{declName}`"
  unless locationCount entry.locations == expectedCount do
    throwError s!"unexpected location count for `{declName}`"
  for location in required do
    unless entry.locations.contains location do
      throwError s!"expected `{declName}` to contain location `{location}`"

run_cmd do
  let entries ← liftCoreM Informalize.allInformalDeclEntries
  unless entries.size == 6 do
    throwError s!"expected 6 tracked declarations in top module, got {entries.size}"

  assertLocationSet entries ``Tests.Integration.Imports.Base.baseBare 0 []
  assertLocationSet entries ``Tests.Integration.Imports.Base.baseLoc 1 [`Foo.bar]
  assertLocationSet entries ``Tests.Integration.Imports.Mid.midBare 0 []
  assertLocationSet entries ``Tests.Integration.Imports.Mid.midLoc 1 [`Foo.bar.baz]
  assertLocationSet entries ``Tests.Integration.Imports.Top.topBare 0 []
  assertLocationSet entries ``Tests.Integration.Imports.Top.topLoc 1 [`Alpha.root.child.grandchild]

run_cmd do
  let some baseLoc ← liftCoreM <| Informalize.informalDeclEntry? ``Tests.Integration.Imports.Base.baseLoc
    | throwError "missing per-declaration query result for imported `Base.baseLoc`"
  unless locationCount baseLoc.locations == 1 && baseLoc.locations.contains `Foo.bar do
    throwError "unexpected per-declaration location set for imported `Base.baseLoc`"

end Tests.Integration.Imports.Top
