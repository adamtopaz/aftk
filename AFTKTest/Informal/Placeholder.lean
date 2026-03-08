import AFTKTest.Informal.Assert
import AFTKTest.Informal.Fixtures

namespace AFTKTest.Informal.Placeholder

open AFTKTest.Informal
open AFTK.Informal

private unsafe def distinctTagsAcrossDefinitions : TestCase := {
  name := "informal.placeholder.distinctTagsAcrossDefinitions"
  run := withImportedModules basicModules fun env => do
    let some tagOne := placeholderTagOfConstant? env `AFTKTest.Informal.Fixtures.Basic.oneRef
      | fail "missing placeholder tag for oneRef"
    let some tagTwo := placeholderTagOfConstant? env `AFTKTest.Informal.Fixtures.Basic.anotherOneRef
      | fail "missing placeholder tag for anotherOneRef"
    assertFalse (tagOne == tagTwo) "different source occurrences should get distinct placeholder tags"
}

private unsafe def directPrimitiveCompilesAtMultipleUniverses : TestCase := {
  name := "informal.placeholder.directPrimitiveCompilesAtMultipleUniverses"
  run := withImportedModules directPlaceholderModules fun env => do
    let some _ := placeholderTagOfConstant? env `AFTKTest.Informal.Fixtures.DirectPlaceholder.directPlaceholderNat
      | fail "expected directPlaceholderNat to elaborate to the placeholder primitive"
    let some _ := placeholderTagOfConstant? env `AFTKTest.Informal.Fixtures.DirectPlaceholder.directPlaceholderType
      | fail "expected directPlaceholderType to elaborate to the placeholder primitive"
    pure ()
}

private unsafe def directPrimitiveIsNotTracked : TestCase := {
  name := "informal.placeholder.directPrimitiveIsNotTracked"
  run := do
    let entries ← runCoreInModules directPlaceholderModules allInformalDeclEntries
    assertEq entries.size 0
}

unsafe def tests : List TestCase :=
  [distinctTagsAcrossDefinitions, directPrimitiveCompilesAtMultipleUniverses, directPrimitiveIsNotTracked]

end AFTKTest.Informal.Placeholder
