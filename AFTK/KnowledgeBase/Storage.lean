module

public import AFTK.KnowledgeBase.Serialization
public import Std.Data.HashMap

public section


namespace AFTK.KnowledgeBase

open System
open PathLayout
open Serialization

namespace Storage

private def throwError {α : Type} (code message : String) (exitCode : UInt8 := 1) : KBIO α :=
  throw <| KnowledgeBaseError.generic code message exitCode

private def liftIO {α : Type} (action : IO α) : KBIO α :=
  action.toEIO (fun err => KnowledgeBaseError.generic "io.error" err.toString 1)

private def parentDir (path : FilePath) : FilePath :=
  path.parent.getD "."

private def ensurePathExists (path : FilePath) (code message : String) : KBIO Unit := do
  unless ← liftIO path.pathExists do
    throwError code message

private def tempPathFor (path : FilePath) : IO FilePath := do
  let nonce := toString (Std.Time.Timestamp.toNanosecondsSinceUnixEpoch (← Std.Time.Timestamp.now))
  let name := path.fileName.getD "tmp"
  pure <| parentDir path / s!".{name}.tmp.{nonce}"

private def writeTextAtomically (path : FilePath) (content : String) : IO Unit := do
  IO.FS.createDirAll (parentDir path)
  let tmp ← tempPathFor path
  IO.FS.writeFile tmp content
  IO.FS.rename tmp path

private def writeMarkdownAtomically (path : FilePath) (body : String) : IO Unit :=
  writeTextAtomically path (normalizeMarkdownForWrite body)

private def writeMetadataAtomically (path : FilePath) (metadata : NodeMetadata) : IO Unit :=
  writeTextAtomically path (renderNodeMetadata metadata)

private def writeManifestAtomically (path : FilePath) (manifest : StorageManifest) : IO Unit :=
  writeTextAtomically path (renderStorageManifest manifest)


def initRoot (root : FilePath) : KBIO KnowledgeBaseStoragePaths := do
  let manifest := defaultManifest
  let paths := storagePathsForRoot root manifest
  if ← liftIO paths.manifestPath.pathExists then
    throw <| KnowledgeBaseError.conflict "storage.alreadyInitialized" s!"Knowledge base already initialized at {root}"
  liftIO <| IO.FS.createDirAll paths.nodesDir
  liftIO <| IO.FS.createDirAll paths.indexDir
  liftIO <| IO.FS.createDirAll paths.cacheDir
  liftIO <| IO.FS.createDirAll paths.tmpDir
  liftIO <| writeManifestAtomically paths.manifestPath manifest
  pure paths


def loadManifestAt (manifestPath : FilePath) : KBIO StorageManifest := do
  ensurePathExists manifestPath "storage.manifestMissing" s!"Manifest not found: {manifestPath}"
  let text ← liftIO <| IO.FS.readFile manifestPath
  match parseStorageManifestText text with
  | .ok manifest => pure manifest
  | .error err => throw <| KnowledgeBaseError.validation "storage.manifestParseError" s!"Invalid manifest at {manifestPath}: {err}"


def resolveInitializedRoot (root : FilePath) : KBIO (KnowledgeBaseStoragePaths × StorageManifest) := do
  let provisional := storagePathsForRoot root
  unless ← liftIO provisional.rootDir.pathExists do
    throwError "storage.rootMissing" s!"Knowledge base root not found: {root}"
  let manifest ← loadManifestAt provisional.manifestPath
  let paths := storagePathsForRoot root manifest
  unless ← liftIO paths.nodesDir.pathExists do
    throwError "storage.nodesDirMissing" s!"Nodes directory not found: {paths.nodesDir}"
  pure (paths, manifest)


def ensureInternalDirs (paths : KnowledgeBaseStoragePaths) : IO Unit := do
  IO.FS.createDirAll paths.indexDir
  IO.FS.createDirAll paths.cacheDir
  IO.FS.createDirAll paths.tmpDir


def nodeExists (paths : KnowledgeBaseStoragePaths) (id : NodeId) : IO Bool := do
  let nodePaths := nodePaths paths id
  return (← nodePaths.markdownPath.pathExists) || (← nodePaths.metadataPath.pathExists)


def loadMetadataAtPath (metadataPath : FilePath) : KBIO NodeMetadata := do
  let text ← liftIO <| IO.FS.readFile metadataPath
  match parseNodeMetadataText text with
  | .ok metadata => pure metadata
  | .error err => throw <| KnowledgeBaseError.validation "metadata.parseError" s!"Invalid metadata at {metadataPath}: {err}"


def loadStoredNode (paths : KnowledgeBaseStoragePaths) (id : NodeId) : KBIO StoredNode := do
  let resolved := nodePaths paths id
  let markdownExists ← liftIO <| resolved.markdownPath.pathExists
  let metadataExists ← liftIO <| resolved.metadataPath.pathExists
  if !markdownExists && !metadataExists then
    throw <| KnowledgeBaseError.notFound "node.notFound" s!"Node not found: {id}"
  if !markdownExists then
    throw <| KnowledgeBaseError.validation "node.markdownMissing" s!"Markdown file missing for node {id}: {resolved.markdownPath}"
  if !metadataExists then
    throw <| KnowledgeBaseError.validation "node.metadataMissing" s!"Metadata file missing for node {id}: {resolved.metadataPath}"
  let body ← liftIO <| readMarkdownFile resolved.markdownPath
  let metadata ← loadMetadataAtPath resolved.metadataPath
  if metadata.id != id then
    throw <| KnowledgeBaseError.validation "node.idPathMismatch" s!"Metadata id {metadata.id} does not match expected path id {id}"
  pure {
    node := { metadata := metadata, body := body }
    paths := resolved
  }


def createNode
    (paths : KnowledgeBaseStoragePaths)
    (id : NodeId)
    (title : String)
    (body : String := "")
    (kind : NodeKind := .note)
    (status : NodeStatus := .draft)
    (summary? : Option String := none)
    (tags : Array String := #[])
    (authors : Array String := #[]) : KBIO StoredNode := do
  let resolved := nodePaths paths id
  if ← liftIO (nodeExists paths id) then
    throw <| KnowledgeBaseError.conflict "node.alreadyExists" s!"Node already exists: {id}"
  let timestamp ← liftIO Timestamp.now
  let metadata : NodeMetadata := {
    id := id
    title := title
    kind := kind
    status := status
    summary? := summary?
    tags := tags
    authors := authors
    createdAt? := some timestamp
    updatedAt? := some timestamp
  }
  liftIO <| IO.FS.createDirAll (parentDir resolved.markdownPath)
  liftIO <| IO.FS.createDirAll (parentDir resolved.metadataPath)
  liftIO <| writeMarkdownAtomically resolved.markdownPath body
  liftIO <| writeMetadataAtomically resolved.metadataPath metadata
  loadStoredNode paths id


def setNodeBody (paths : KnowledgeBaseStoragePaths) (id : NodeId) (body : String) : KBIO StoredNode := do
  let stored ← loadStoredNode paths id
  let updatedAt ← liftIO Timestamp.now
  let metadata := stored.node.metadata.withUpdatedAt updatedAt
  liftIO <| writeMarkdownAtomically stored.paths.markdownPath body
  liftIO <| writeMetadataAtomically stored.paths.metadataPath metadata
  loadStoredNode paths id


def replaceNodeMetadata (paths : KnowledgeBaseStoragePaths) (id : NodeId) (replacement : NodeMetadata) : KBIO StoredNode := do
  let stored ← loadStoredNode paths id
  if replacement.id != id then
    throw <| KnowledgeBaseError.conflict "metadata.idMismatch" s!"Replacement metadata id {replacement.id} does not match target id {id}"
  let updatedAt ← liftIO Timestamp.now
  let replacement := replacement.withUpdatedAt updatedAt
  liftIO <| writeMetadataAtomically stored.paths.metadataPath replacement
  loadStoredNode paths id


def renameNode (paths : KnowledgeBaseStoragePaths) (oldId newId : NodeId) : KBIO StoredNode := do
  let stored ← loadStoredNode paths oldId
  if ← liftIO (nodeExists paths newId) then
    throw <| KnowledgeBaseError.conflict "node.alreadyExists" s!"Target node already exists: {newId}"
  let newPaths := nodePaths paths newId
  let updatedAt ← liftIO Timestamp.now
  let metadata := stored.node.metadata.withId newId |>.withUpdatedAt updatedAt
  liftIO <| IO.FS.createDirAll (parentDir newPaths.markdownPath)
  liftIO <| IO.FS.createDirAll (parentDir newPaths.metadataPath)
  liftIO <| writeMarkdownAtomically newPaths.markdownPath stored.node.body
  liftIO <| writeMetadataAtomically newPaths.metadataPath metadata
  liftIO <| IO.FS.removeFile stored.paths.markdownPath
  liftIO <| IO.FS.removeFile stored.paths.metadataPath
  loadStoredNode paths newId


def deleteNode (paths : KnowledgeBaseStoragePaths) (id : NodeId) : KBIO Unit := do
  let stored ← loadStoredNode paths id
  liftIO <| IO.FS.removeFile stored.paths.markdownPath
  liftIO <| IO.FS.removeFile stored.paths.metadataPath

private def insertDiscovered
    (found : Std.HashMap String DiscoveredNodeFiles)
    (stem : FilePath)
    (path : FilePath)
    (isMarkdown : Bool) : Std.HashMap String DiscoveredNodeFiles :=
  let key := stem.toString
  let current := match found.get? key with
    | some entry => entry
    | none => { stem := stem }
  let updated :=
    if isMarkdown then
      { current with markdownPath? := some path }
    else
      { current with metadataPath? := some path }
  found.insert key updated

partial def scanCanonicalNodeFiles (paths : KnowledgeBaseStoragePaths) : KBIO (Array DiscoveredNodeFiles) := do
  let rec walk (dir : FilePath) (found : Std.HashMap String DiscoveredNodeFiles) : IO (Std.HashMap String DiscoveredNodeFiles) := do
    let mut found := found
    for entry in (← dir.readDir) do
      let path := entry.path
      if ← path.isDir then
        found ← walk path found
      else
        match stemFromAbsoluteNodeFile? paths.nodesDir path with
        | some stem =>
            let isMarkdown := path.extension == some "md"
            let isMetadata := path.extension == some "json"
            if isMarkdown || isMetadata then
              found := insertDiscovered found stem path isMarkdown
        | none => pure ()
    pure found
  let found ← liftIO <| walk paths.nodesDir {}
  let mut files := found.toList.map Prod.snd |>.toArray
  files := files.qsort (fun a b => a.stem.toString < b.stem.toString)
  pure files


def loadAllStoredNodes (paths : KnowledgeBaseStoragePaths) : KBIO (Array StoredNode) := do
  let discovered ← scanCanonicalNodeFiles paths
  let mut nodes := #[]
  for files in discovered do
    match files.markdownPath?, files.metadataPath? with
    | some _, some _ =>
        let id ← match pathStemToNodeId? files.stem with
          | .ok id => pure id
          | .error err => throw <| KnowledgeBaseError.validation "node.invalidPathId" s!"Invalid canonical node path {files.stem}: {err}"
        nodes := nodes.push (← loadStoredNode paths id)
    | some markdownPath, none =>
        throw <| KnowledgeBaseError.validation "node.orphanMarkdown" s!"Orphan markdown file without metadata: {markdownPath}"
    | none, some metadataPath =>
        throw <| KnowledgeBaseError.validation "node.orphanMetadata" s!"Orphan metadata file without markdown: {metadataPath}"
    | none, none => pure ()
  pure nodes


def loadAllMetadata (paths : KnowledgeBaseStoragePaths) : KBIO (Array NodeMetadata) := do
  return (← loadAllStoredNodes paths).map (·.node.metadata)

end Storage

end AFTK.KnowledgeBase
