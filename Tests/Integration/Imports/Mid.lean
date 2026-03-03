import Tests.Integration.Imports.Base

open Lean Elab Command

namespace Tests.Integration.Imports.Mid

noncomputable def midLoc : Nat :=
  informal[Foo.bar.baz] Tests.Integration.Imports.Base.baseLoc

noncomputable def midBare : Nat :=
  informal Tests.Integration.Imports.Base.baseBare

private def entryFor?
    (entries : Array Informalize.InformalDeclEntry)
    (declName : Name) : Option Informalize.InformalDeclEntry :=
  entries.find? (·.declName == declName)

private def locationCount (locations : NameSet) : Nat := Id.run do
  let mut count := 0
  for _ in locations do
    count := count + 1
  return count

run_cmd do
  let entries ← liftCoreM Informalize.allInformalDeclEntries
  unless entries.size == 4 do
    throwError s!"expected 4 tracked declarations in mid module, got {entries.size}"

  let some baseLoc := entryFor? entries ``Tests.Integration.Imports.Base.baseLoc
    | throwError "missing imported entry for `Base.baseLoc`"
  unless locationCount baseLoc.locations == 1 && baseLoc.locations.contains `Foo.bar do
    throwError "unexpected location set for `Base.baseLoc` in mid module"

  let some midLocEntry := entryFor? entries ``Tests.Integration.Imports.Mid.midLoc
    | throwError "missing local entry for `Mid.midLoc`"
  unless locationCount midLocEntry.locations == 1 && midLocEntry.locations.contains `Foo.bar.baz do
    throwError "unexpected location set for `Mid.midLoc`"

end Tests.Integration.Imports.Mid
