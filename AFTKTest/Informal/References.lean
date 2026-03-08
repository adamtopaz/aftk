module

public import AFTKTest.Informal.Assert
public import AFTKTest.Informal.Fixtures

public section


namespace AFTKTest.Informal.References

open AFTK.Informal
open AFTKTest.Informal

private def validReference : TestCase := {
  name := "informal.references.valid"
  run := do
    let ref ← match informalReferenceOfString? "group.basic.definition" with
      | .ok ref => pure ref
      | .error err => fail err
    assertEq ref.nodeId.value "group.basic.definition"
}

private def invalidReference : TestCase := {
  name := "informal.references.invalid"
  run := do
    assertExceptErrorContains (informalReferenceOfString? "Group.basic.definition") "lowercase ASCII letter"
    assertExceptErrorContains (informalReferenceOfString? "group/basic") "path separators or whitespace"
}

private def oneSegmentAccepted : TestCase := {
  name := "informal.references.oneSegmentAccepted"
  run := do
    let ref ← match informalReferenceOfString? "group" with
      | .ok ref => pure ref
      | .error err => fail err
    assertEq ref.nodeId.value "group"
}

private def resolveExistingNode : TestCase := {
  name := "informal.references.resolveExistingNode"
  run := do
    let root ← basicRoot
    let resolved ← resolveRefAt root "group.basic.definition"
    assertEq resolved.ref.nodeId.value "group.basic.definition"
    assertEq resolved.storedNode.node.metadata.title "Definition of group"
}

private def missingNodeFails : TestCase := {
  name := "informal.references.missingNode"
  run := do
    let root ← basicRoot
    let ref ← match informalReferenceOfString? "missing.node" with
      | .ok ref => pure ref
      | .error err => fail err
    let result ← liftIO <| (resolveInformalReferenceAtRoot root ref).toIO'
    match result with
    | .ok _ => fail "expected missing node resolution failure"
    | .error err => assertContains err.message "Node not found: missing.node"
}

private def jsonRendering : TestCase := {
  name := "informal.references.jsonRendering"
  run := do
    let ref ← match informalReferenceOfString? "group.basic.definition" with
      | .ok ref => pure ref
      | .error err => fail err
    let json := Lean.toJson ref
    let rendered ← match json.getStr? with
      | .ok value => pure value
      | .error err => fail err
    assertEq rendered "group.basic.definition"
}

def tests : List TestCase :=
  [validReference, invalidReference, oneSegmentAccepted, resolveExistingNode, missingNodeFails, jsonRendering]

end AFTKTest.Informal.References
