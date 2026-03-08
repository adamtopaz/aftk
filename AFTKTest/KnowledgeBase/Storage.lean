import AFTKTest.KnowledgeBase.Assert

namespace AFTKTest.KnowledgeBase.Storage

open AFTK.KnowledgeBase

open AFTKTest.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

private def mkId (raw : String) : TestM NodeId :=
  match NodeId.ofString? raw with
  | .ok id => pure id
  | .error err => fail err

private def createLoadRenameDelete : TestCase := {
  name := "storage.create.load.rename.delete"
  run := withTempDir fun dir => do
    let root := dir / "knowledgebase"
    let paths ← liftKB <| Storage.initRoot root
    let id ← mkId "topology.open_cover"
    let created ← liftKB <| Storage.createNode paths id "Open cover" "Initial body" .definition .draft
    assertEq created.node.metadata.id id
    assertTrue (← liftIO created.paths.markdownPath.pathExists) "markdown file should exist after create"
    assertTrue (← liftIO created.paths.metadataPath.pathExists) "metadata file should exist after create"

    let loaded ← liftKB <| Storage.loadStoredNode paths id
    assertEq loaded.node.body "Initial body\n"
    assertEq loaded.node.metadata.title "Open cover"

    let updated ← liftKB <| Storage.setNodeBody paths id "Updated body"
    assertEq updated.node.body "Updated body\n"

    let renamedId ← mkId "topology.open_cover_note"
    let renamed ← liftKB <| Storage.renameNode paths id renamedId
    assertEq renamed.node.metadata.id renamedId
    assertFalse (← liftIO created.paths.markdownPath.pathExists) "old markdown path should be removed after rename"
    assertTrue (← liftIO renamed.paths.markdownPath.pathExists) "new markdown path should exist after rename"

    liftKB <| Storage.deleteNode paths renamedId
    assertFalse (← liftIO renamed.paths.markdownPath.pathExists) "markdown path should be removed after delete"
    assertFalse (← liftIO renamed.paths.metadataPath.pathExists) "metadata path should be removed after delete"
}


def tests : List TestCase :=
  [createLoadRenameDelete]

end AFTKTest.KnowledgeBase.Storage
