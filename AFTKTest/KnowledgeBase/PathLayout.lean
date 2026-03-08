import AFTKTest.KnowledgeBase.Assert

namespace AFTKTest.KnowledgeBase.PathLayout

open AFTK.KnowledgeBase

open AFTKTest.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

private def nodeIdToStemRoundTrip : TestCase := {
  name := "pathLayout.nodeId.roundTrip"
  run := do
    let id ← match NodeId.ofString? "topology.open_cover" with
      | .ok id => pure id
      | .error err => fail err
    let stem := nodeIdToRelativeStem id
    assertEq stem.toString "topology/open_cover"
    let roundTrip ← match pathStemToNodeId? stem with
      | .ok id => pure id
      | .error err => fail err
    assertEq roundTrip id
}

private def canonicalNodePaths : TestCase := {
  name := "pathLayout.nodePaths.canonical"
  run := do
    let root := ("/tmp/kb-root" : System.FilePath)
    let paths := storagePathsForRoot root
    let id ← match NodeId.ofString? "group.basic.definition" with
      | .ok id => pure id
      | .error err => fail err
    let nodePaths := PathLayout.nodePaths paths id
    assertEq nodePaths.markdownPath.toString "/tmp/kb-root/nodes/group/basic/definition.md"
    assertEq nodePaths.metadataPath.toString "/tmp/kb-root/nodes/group/basic/definition.json"
}


def tests : List TestCase :=
  [nodeIdToStemRoundTrip, canonicalNodePaths]

end AFTKTest.KnowledgeBase.PathLayout
