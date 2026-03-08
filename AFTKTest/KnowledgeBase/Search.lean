import AFTKTest.KnowledgeBase.Assert

namespace AFTKTest.KnowledgeBase.Search

open AFTK.KnowledgeBase

open AFTKTest.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

private def mkId (raw : String) : TestM NodeId :=
  match NodeId.ofString? raw with
  | .ok id => pure id
  | .error err => fail err

private def textAndTagSearch : TestCase := {
  name := "search.textAndTag"
  run := withTempDir fun dir => do
    let root := dir / "knowledgebase"
    let paths ← liftKB <| Storage.initRoot root
    let openSetId ← mkId "topology.open_set"
    let coverId ← mkId "topology.open_cover"
    let _ ← liftKB <| Storage.createNode paths openSetId "Open set" "A set is open if ..." .definition .draft none #["topology"]
    let _ ← liftKB <| Storage.createNode paths coverId "Open cover" "An open cover is a family of open sets." .definition .draft none #["topology", "cover"]
    let textResult ← liftKB <| Search.searchText paths "open cover"
    assertEq textResult.hits.size 1
    assertEq textResult.hits[0]!.id coverId
    let tagResult ← liftKB <| Search.searchTag paths "topology"
    assertEq tagResult.hits.size 2
}


def tests : List TestCase :=
  [textAndTagSearch]

end AFTKTest.KnowledgeBase.Search
