module

public import AFTKTest.KnowledgeBase.Assert

public section


namespace AFTKTest.KnowledgeBase.Types

open AFTK.KnowledgeBase

open AFTKTest.KnowledgeBase

private def validNodeId : TestCase := {
  name := "types.nodeId.valid"
  run := do
    let id ← match NodeId.ofString? "topology.open_cover" with
      | .ok id => pure id
      | .error err => fail err
    assertEq id.value "topology.open_cover"
    assertEq id.segments ["topology", "open_cover"]
}

private def invalidNodeIds : TestCase := {
  name := "types.nodeId.invalid"
  run := do
    assertExceptErrorContains (NodeId.ofString? "Topology.open_cover") "must start with a lowercase ASCII letter"
    assertExceptErrorContains (NodeId.ofString? "topology..open_cover") "segments must be nonempty"
    assertExceptErrorContains (NodeId.ofString? "topology/open_cover") "path separators or whitespace"
}

private def timestampValidation : TestCase := {
  name := "types.timestamp.validation"
  run := do
    let ts ← match Timestamp.ofString? "2026-03-07T21:49:18Z" with
      | .ok ts => pure ts
      | .error err => fail err
    assertEq ts.value "2026-03-07T21:49:18Z"
    assertExceptErrorContains (Timestamp.ofString? "2026-03-07 21:49:18Z") "YYYY-MM-DDTHH:MM:SSZ"
}


def tests : List TestCase :=
  [validNodeId, invalidNodeIds, timestampValidation]

end AFTKTest.KnowledgeBase.Types
