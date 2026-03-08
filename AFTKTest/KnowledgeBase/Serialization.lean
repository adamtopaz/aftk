module

public import AFTKTest.KnowledgeBase.Assert

public section


namespace AFTKTest.KnowledgeBase.Serialization

open AFTK.KnowledgeBase

open AFTKTest.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

private def sampleMetadata : TestM NodeMetadata := do
  let id ← match NodeId.ofString? "topology.open_cover" with
    | .ok id => pure id
    | .error err => fail err
  let createdAt ← match Timestamp.ofString? "2026-03-07T21:49:18Z" with
    | .ok ts => pure ts
    | .error err => fail err
  pure {
    id := id
    title := "Open cover"
    kind := .definition
    status := .active
    summary? := some "Definition of an open cover."
    tags := #["topology"]
    authors := #["aftk"]
    createdAt? := some createdAt
    updatedAt? := some createdAt
  }

private def manifestGolden : TestCase := {
  name := "serialization.manifest.golden"
  run := do
    let expected ← readGolden "manifest.json"
    assertEq (Serialization.renderStorageManifest defaultManifest) expected
}

private def metadataGolden : TestCase := {
  name := "serialization.metadata.golden"
  run := do
    let expected ← readGolden "node-metadata.json"
    let metadata ← sampleMetadata
    assertEq (Serialization.renderNodeMetadata metadata) expected
}

private def metadataUnknownFieldRejected : TestCase := {
  name := "serialization.metadata.unknownFieldRejected"
  run := do
    let text := "{\n  \"schemaVersion\": 1,\n  \"id\": \"topology.open_cover\",\n  \"title\": \"Open cover\",\n  \"extra\": true\n}\n"
    assertExceptErrorContains (Serialization.parseNodeMetadataText text) "unknown field: extra"
}

private def manifestUnknownFieldRejected : TestCase := {
  name := "serialization.manifest.unknownFieldRejected"
  run := do
    let text := "{\n  \"schemaVersion\": 1,\n  \"kind\": \"aftk-knowledge-base\",\n  \"nodesDir\": \"nodes\",\n  \"internalDir\": \".aftk\",\n  \"extra\": true\n}\n"
    assertExceptErrorContains (Serialization.parseStorageManifestText text) "unknown field: extra"
}


def tests : List TestCase :=
  [manifestGolden, metadataGolden, metadataUnknownFieldRejected, manifestUnknownFieldRejected]

end AFTKTest.KnowledgeBase.Serialization
