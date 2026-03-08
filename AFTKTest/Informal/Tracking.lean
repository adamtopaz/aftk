module

public import AFTKTest.Informal.Assert
public import AFTKTest.Informal.Fixtures

public section


namespace AFTKTest.Informal.Tracking

open AFTKTest.Informal
open AFTK.Informal

private def findDecl (entries : Array InformalDeclEntry) (declName : Lean.Name) : TestM InformalDeclEntry := do
  let some entry := entries.find? fun entry => entry.declName == declName
    | fail s!"missing declaration entry {declName}"
  pure entry

private def findRef (entries : Array InformalReferenceEntry) (refValue : String) : TestM InformalReferenceEntry := do
  let some entry := entries.find? fun entry => toString entry.ref == refValue
    | fail s!"missing reference entry {refValue}"
  pure entry

private unsafe def basicDeclEntries : TestCase := {
  name := "informal.tracking.basicDeclEntries"
  run := do
    let entries ← runCoreInModules basicModules allInformalDeclEntries
    let oneRef ← findDecl entries `AFTKTest.Informal.Fixtures.Basic.oneRef
    assertEq oneRef.refs.size 1
    assertEq (toString oneRef.refs[0]!) "group.basic.definition"

    let repeatedRef ← findDecl entries `AFTKTest.Informal.Fixtures.Basic.repeatedRef
    assertEq repeatedRef.refs.size 1
    assertEq (toString repeatedRef.refs[0]!) "group.basic.definition"

    let multiRef ← findDecl entries `AFTKTest.Informal.Fixtures.Basic.multiRef
    assertEq multiRef.refs.size 2
    assertEq (multiRef.refs.map toString) #["group.basic.definition", "group.basic.operation_note"]
}

private unsafe def reverseReferenceEntries : TestCase := {
  name := "informal.tracking.reverseReferenceEntries"
  run := do
    let entries ← runCoreInModules basicModules allInformalReferenceEntries
    let groupDef ← findRef entries "group.basic.definition"
    assertTrue (groupDef.declNames.contains `AFTKTest.Informal.Fixtures.Basic.oneRef) "expected oneRef in reverse index"
    assertTrue (groupDef.declNames.contains `AFTKTest.Informal.Fixtures.Basic.repeatedRef) "expected repeatedRef in reverse index"
    assertTrue (groupDef.declNames.contains `AFTKTest.Informal.Fixtures.Basic.multiRef) "expected multiRef in reverse index"
}

private unsafe def importedUnionAndDeterminism : TestCase := {
  name := "informal.tracking.importedUnionAndDeterminism"
  run := do
    let declEntries ← runCoreInModules importsTopModules allInformalDeclEntries
    assertEq (declEntries.map (fun entry => entry.declName.toString)) #[
      "AFTKTest.Informal.Fixtures.Imports.Base.baseTracked",
      "AFTKTest.Informal.Fixtures.Imports.Mid.midTracked"
    ]
    let refEntries ← runCoreInModules importsTopModules allInformalReferenceEntries
    assertEq (refEntries.map (fun entry => toString entry.ref)) #[
      "algebra.monoid.definition",
      "group.basic.definition"
    ]
}

private unsafe def noEmptyTrackedRows : TestCase := {
  name := "informal.tracking.noEmptyTrackedRows"
  run := do
    let entries ← runCoreInModules importsTopModules allInformalDeclEntries
    assertTrue (entries.all fun entry => !entry.refs.isEmpty) "tracked declarations should never have empty ref sets"
}


unsafe def tests : List TestCase :=
  [basicDeclEntries, reverseReferenceEntries, importedUnionAndDeterminism, noEmptyTrackedRows]

end AFTKTest.Informal.Tracking
