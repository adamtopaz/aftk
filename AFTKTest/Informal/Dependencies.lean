import AFTKTest.Informal.Assert
import AFTKTest.Informal.Fixtures

namespace AFTKTest.Informal.Dependencies

open AFTKTest.Informal
open AFTK.Informal

private def findDeclDep (entries : Array InformalDeclDependencyEntry) (declName : Lean.Name) : TestM InformalDeclDependencyEntry := do
  let some entry := entries.find? fun entry => entry.declName == declName
    | fail s!"missing declaration dependency entry {declName}"
  pure entry

private def findRefDep (entries : Array InformalReferenceDependencyEntry) (refValue : String) : TestM InformalReferenceDependencyEntry := do
  let some entry := entries.find? fun entry => toString entry.ref == refValue
    | fail s!"missing reference dependency entry {refValue}"
  pure entry

private unsafe def declarationDependenciesAcrossImports : TestCase := {
  name := "informal.dependencies.declarationAcrossImports"
  run := do
    let rows ← runCoreInModules importsTopModules allInformalDeclDependencyEntries
    let baseTracked ← findDeclDep rows `AFTKTest.Informal.Fixtures.Imports.Base.baseTracked
    let midTracked ← findDeclDep rows `AFTKTest.Informal.Fixtures.Imports.Mid.midTracked
    assertEq baseTracked.dependencies.size 0
    assertEq midTracked.dependencies #[`AFTKTest.Informal.Fixtures.Imports.Base.baseTracked]
}

private unsafe def referenceDependenciesAcrossImports : TestCase := {
  name := "informal.dependencies.referenceAcrossImports"
  run := do
    let rows ← runCoreInModules importsTopModules allInformalReferenceDependencyEntries
    let monoid ← findRefDep rows "algebra.monoid.definition"
    let group ← findRefDep rows "group.basic.definition"
    assertEq (monoid.dependencies.map toString) #["group.basic.definition"]
    assertEq group.dependencies.size 0
}

private unsafe def leavesAcrossImports : TestCase := {
  name := "informal.dependencies.leavesAcrossImports"
  run := do
    let declLeaves ← runCoreInModules importsTopModules informalDeclDependencyLeaves
    let refLeaves ← runCoreInModules importsTopModules informalReferenceDependencyLeaves
    assertEq declLeaves #[`AFTKTest.Informal.Fixtures.Imports.Base.baseTracked]
    assertEq (refLeaves.map toString) #["group.basic.definition"]
}

private unsafe def cycleSafeTraversal : TestCase := {
  name := "informal.dependencies.cycleSafeTraversal"
  run := do
    let declRows ← runCoreInModules cycleModules allInformalDeclDependencyEntries
    assertEq declRows.size 2
    for row in declRows do
      assertFalse (row.dependencies.contains row.declName) "cycle handling should remove self-dependencies"

    let refRows ← runCoreInModules cycleModules allInformalReferenceDependencyEntries
    assertEq refRows.size 2
    for row in refRows do
      assertFalse (row.dependencies.contains row.ref) "projected cycle handling should remove self-dependencies"
}

private unsafe def emptyStateBehavior : TestCase := {
  name := "informal.dependencies.emptyStateBehavior"
  run := do
    let declRows ← runCoreInModules directPlaceholderModules allInformalDeclDependencyEntries
    let refRows ← runCoreInModules directPlaceholderModules allInformalReferenceDependencyEntries
    assertEq declRows.size 0
    assertEq refRows.size 0
}


unsafe def tests : List TestCase :=
  [declarationDependenciesAcrossImports, referenceDependenciesAcrossImports, leavesAcrossImports, cycleSafeTraversal, emptyStateBehavior]

end AFTKTest.Informal.Dependencies
