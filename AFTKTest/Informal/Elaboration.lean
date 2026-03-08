import AFTKTest.Informal.Assert
import AFTKTest.Informal.Fixtures

namespace AFTKTest.Informal.Elaboration

open AFTKTest.Informal
open AFTK.Informal

private unsafe def trackedProofAndOneSegmentRef : TestCase := {
  name := "informal.elaboration.trackedProofAndOneSegmentRef"
  run := do
    let theoremEntry? ← runCoreInModules basicModules <| informalDeclEntry? `AFTKTest.Informal.Fixtures.Basic.theoremWithRef
    let theoremEntry ← assertSome theoremEntry? "expected theoremWithRef to be tracked"
    assertEq (theoremEntry.refs.map toString) #["proof.sketch"]

    let oneSegmentEntry? ← runCoreInModules basicModules <| informalDeclEntry? `AFTKTest.Informal.Fixtures.Basic.oneSegmentRef
    let oneSegmentEntry ← assertSome oneSegmentEntry? "expected oneSegmentRef to be tracked"
    assertEq (oneSegmentEntry.refs.map toString) #["group"]
}

private unsafe def elaboratedDefinitionsUsePlaceholderPrimitive : TestCase := {
  name := "informal.elaboration.placeholderPrimitive"
  run := withImportedModules basicModules fun env => do
    let some _ := placeholderTagOfConstant? env `AFTKTest.Informal.Fixtures.Basic.oneRef
      | fail "expected oneRef to elaborate to the placeholder primitive"
    let some _ := placeholderTagOfConstant? env `AFTKTest.Informal.Fixtures.Basic.appliedRef
      | fail "expected appliedRef to elaborate to the placeholder primitive"
    pure ()
}

private unsafe def hoverInfoSmoke : TestCase := {
  name := "informal.elaboration.hoverInfoSmoke"
  run := do
    let root ← basicRoot
    let input := String.intercalate "\n" [
      "import AFTK",
      s!"set_option aftk.informal.root \"{root}\"",
      "def hoverSmoke : Nat := informal[group.basic.definition]",
      ""
    ]
    let docs ← liftIO <| collectDocStringsFromSource input
    assertTrue (!docs.isEmpty) "expected at least one hover docstring"
    let joined := String.intercalate "\n\n" docs.toList
    assertContains joined "Informal node: group.basic.definition"
    assertContains joined "Title: Definition of group"
}

private def compileFailFixture (name : String) (expected : String) : TestCase := {
  name := s!"informal.elaboration.compileFail.{name}"
  run := do
    let out ← runCompileFixture ((← liftIO IO.currentDir) / "tests" / "informal" / "compile-fail" / s!"{name}.lean")
    assertFalse (out.exitCode == 0) s!"expected compile failure for {name}"
    let combined := out.stdout ++ "\n" ++ out.stderr
    assertContains combined expected s!"compile-fail fixture: {name}"
}


unsafe def tests : List TestCase :=
  [ trackedProofAndOneSegmentRef
  , elaboratedDefinitionsUsePlaceholderPrimitive
  , hoverInfoSmoke
  , compileFailFixture "invalid-node-id" "Invalid informal node id 'Group.basic.definition'"
  , compileFailFixture "missing-node" "Node not found: missing.node"
  , compileFailFixture "malformed-node" "Metadata id broken.other does not match expected path id broken.node"
  , compileFailFixture "invalid-context-check" "may only be used inside declaration values or proofs"
  ]

end AFTKTest.Informal.Elaboration
