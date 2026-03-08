import AFTKTest.KnowledgeBase.Assert

namespace AFTKTest.KnowledgeBase.Validation

open AFTK.KnowledgeBase

open AFTKTest.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

private def mkId (raw : String) : TestM NodeId :=
  match NodeId.ofString? raw with
  | .ok id => pure id
  | .error err => fail err

private def brokenRelationshipDetected : TestCase := {
  name := "validation.brokenRelationshipDetected"
  run := withTempDir fun dir => do
    let root := dir / "knowledgebase"
    let paths ← liftKB <| Storage.initRoot root
    let openSetId ← mkId "topology.open_set"
    let coverId ← mkId "topology.open_cover"
    let _ ← liftKB <| Storage.createNode paths openSetId "Open set" "Definition" .definition .draft
    let _ ← liftKB <| Storage.createNode paths coverId "Open cover" "Definition" .definition .draft
    let missingId ← mkId "topology.missing_target"
    let metadata := {
      schemaVersion := 1
      id := coverId
      title := "Open cover"
      kind := .definition
      relationships := #[{ kind := .dependsOn, target := missingId }]
    }
    let _ ← liftKB <| Storage.replaceNodeMetadata paths coverId metadata
    let report ← liftIO <| Validation.validateAll root
    assertFalse report.ok "validation should fail when a relationship target is missing"
    assertTrue (report.issues.any (fun issue => issue.code == "relationships.targetNotFound")) "expected relationships.targetNotFound issue"
}


def tests : List TestCase :=
  [brokenRelationshipDetected]

end AFTKTest.KnowledgeBase.Validation
