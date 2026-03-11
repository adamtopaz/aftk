module

public import AFTK.KnowledgeBase.Search
public import AFTK.KnowledgeBase.Validation

public section


namespace AFTK.KnowledgeBase
namespace Service

open Lean
open PathLayout

structure StatusInfo where
  root : System.FilePath
  manifest : StorageManifest
  initialized : Bool
  nodeCount : Nat
  internalDirExists : Bool
  indexDirExists : Bool
  cacheDirExists : Bool
  tmpDirExists : Bool
  deriving Repr, DecidableEq, Inhabited

instance : ToJson StatusInfo where
  toJson info := Json.mkObj [
    ("root", toJson info.root),
    ("manifest", toJson info.manifest),
    ("initialized", toJson info.initialized),
    ("nodeCount", toJson info.nodeCount),
    ("internalDirExists", toJson info.internalDirExists),
    ("indexDirExists", toJson info.indexDirExists),
    ("cacheDirExists", toJson info.cacheDirExists),
    ("tmpDirExists", toJson info.tmpDirExists)
  ]

private def liftIO {α : Type} (action : IO α) : KBIO α :=
  action.toEIO (fun err => KnowledgeBaseError.generic "io.error" err.toString 1)


def resolveRoot (root? : Option System.FilePath := none) : KBIO System.FilePath :=
  liftIO <| PathLayout.resolveRootPath root?


def statusInfoForRoot (root : System.FilePath) : KBIO StatusInfo := do
  let provisional := storagePathsForRoot root
  if !(← liftIO <| provisional.rootDir.pathExists) || !(← liftIO <| provisional.manifestPath.pathExists) then
    let internalDirExists ← liftIO <| provisional.internalDir.pathExists
    let indexDirExists ← liftIO <| provisional.indexDir.pathExists
    let cacheDirExists ← liftIO <| provisional.cacheDir.pathExists
    let tmpDirExists ← liftIO <| provisional.tmpDir.pathExists
    return {
      root := root
      manifest := defaultManifest
      initialized := false
      nodeCount := 0
      internalDirExists := internalDirExists
      indexDirExists := indexDirExists
      cacheDirExists := cacheDirExists
      tmpDirExists := tmpDirExists
    }
  let (paths, manifest) ← Storage.resolveInitializedRoot root
  let discovered ← Storage.scanCanonicalNodeFiles paths
  let nodeCount := discovered.foldl (init := 0) fun count files =>
    if files.markdownPath?.isSome && files.metadataPath?.isSome then count + 1 else count
  let internalDirExists ← liftIO <| paths.internalDir.pathExists
  let indexDirExists ← liftIO <| paths.indexDir.pathExists
  let cacheDirExists ← liftIO <| paths.cacheDir.pathExists
  let tmpDirExists ← liftIO <| paths.tmpDir.pathExists
  return {
    root := root
    manifest := manifest
    initialized := true
    nodeCount := nodeCount
    internalDirExists := internalDirExists
    indexDirExists := indexDirExists
    cacheDirExists := cacheDirExists
    tmpDirExists := tmpDirExists
  }


def status (root? : Option System.FilePath := none) : KBIO StatusInfo := do
  statusInfoForRoot (← resolveRoot root?)


def initAtRoot (root : System.FilePath) : KBIO KnowledgeBaseStoragePaths :=
  Storage.initRoot root


def init (root? : Option System.FilePath := none) : KBIO KnowledgeBaseStoragePaths := do
  initAtRoot (← resolveRoot root?)


def requireInitialized (root : System.FilePath) : KBIO (KnowledgeBaseStoragePaths × StorageManifest) :=
  Storage.resolveInitializedRoot root

private def filterListNodes
    (nodes : Array NodeMetadata)
    (prefix? : Option String := none)
    (kind? : Option NodeKind := none)
    (status? : Option NodeStatus := none)
    (tag? : Option String := none) : Array NodeMetadata :=
  nodes.filter fun metadata =>
    let prefixOk := match prefix? with
      | some pref => NodeId.startsWithSegmentPrefix metadata.id pref
      | none => true
    let kindOk := match kind? with | some kind => metadata.kind == kind | none => true
    let statusOk := match status? with | some status => metadata.status == status | none => true
    let tagOk := match tag? with | some tag => metadata.tags.contains tag | none => true
    prefixOk && kindOk && statusOk && tagOk


def listAtRoot
    (root : System.FilePath)
    (prefix? : Option String := none)
    (kind? : Option NodeKind := none)
    (status? : Option NodeStatus := none)
    (tag? : Option String := none) : KBIO (Array NodeMetadata) := do
  let (paths, _) ← requireInitialized root
  let metadata ← Storage.loadAllMetadata paths
  pure <| filterListNodes metadata prefix? kind? status? tag?


def list
    (root? : Option System.FilePath := none)
    (prefix? : Option String := none)
    (kind? : Option NodeKind := none)
    (status? : Option NodeStatus := none)
    (tag? : Option String := none) : KBIO (Array NodeMetadata) := do
  listAtRoot (← resolveRoot root?) prefix? kind? status? tag?


def showNodeAtRoot (root : System.FilePath) (id : NodeId) : KBIO StoredNode := do
  let (paths, _) ← requireInitialized root
  Storage.loadStoredNode paths id


def showNode (id : NodeId) (root? : Option System.FilePath := none) : KBIO StoredNode := do
  showNodeAtRoot (← resolveRoot root?) id


def getBodyAtRoot (root : System.FilePath) (id : NodeId) : KBIO String := do
  return (← showNodeAtRoot root id).node.body


def getBody (id : NodeId) (root? : Option System.FilePath := none) : KBIO String := do
  getBodyAtRoot (← resolveRoot root?) id


def getMetadataAtRoot (root : System.FilePath) (id : NodeId) : KBIO NodeMetadata := do
  return (← showNodeAtRoot root id).node.metadata


def getMetadata (id : NodeId) (root? : Option System.FilePath := none) : KBIO NodeMetadata := do
  getMetadataAtRoot (← resolveRoot root?) id


def getPathsAtRoot (root : System.FilePath) (id : NodeId) : KBIO NodePaths := do
  let (paths, _) ← requireInitialized root
  let _ ← Storage.loadStoredNode paths id
  pure <| nodePaths paths id


def getPaths (id : NodeId) (root? : Option System.FilePath := none) : KBIO NodePaths := do
  getPathsAtRoot (← resolveRoot root?) id


def createAtRoot
    (root : System.FilePath)
    (id : NodeId)
    (title : String)
    (body : String := "")
    (kind : NodeKind := .note)
    (status : NodeStatus := .draft)
    (summary? : Option String := none)
    (tags : Array String := #[])
    (authors : Array String := #[]) : KBIO StoredNode := do
  let (paths, _) ← requireInitialized root
  Storage.createNode paths id title body kind status summary? tags authors


def create
    (id : NodeId)
    (title : String)
    (body : String := "")
    (kind : NodeKind := .note)
    (status : NodeStatus := .draft)
    (summary? : Option String := none)
    (tags : Array String := #[])
    (authors : Array String := #[])
    (root? : Option System.FilePath := none) : KBIO StoredNode := do
  createAtRoot (← resolveRoot root?) id title body kind status summary? tags authors


def renameAtRoot (root : System.FilePath) (oldId newId : NodeId) : KBIO StoredNode := do
  let (paths, _) ← requireInitialized root
  Storage.renameNode paths oldId newId


def rename
    (oldId newId : NodeId)
    (root? : Option System.FilePath := none) : KBIO StoredNode := do
  renameAtRoot (← resolveRoot root?) oldId newId


def deleteAtRoot (root : System.FilePath) (id : NodeId) : KBIO Unit := do
  let (paths, _) ← requireInitialized root
  Storage.deleteNode paths id


def delete (id : NodeId) (root? : Option System.FilePath := none) : KBIO Unit := do
  deleteAtRoot (← resolveRoot root?) id


def setBodyAtRoot (root : System.FilePath) (id : NodeId) (body : String) : KBIO StoredNode := do
  let (paths, _) ← requireInitialized root
  Storage.setNodeBody paths id body


def setBody (id : NodeId) (body : String) (root? : Option System.FilePath := none) : KBIO StoredNode := do
  setBodyAtRoot (← resolveRoot root?) id body


def replaceMetadataAtRoot
    (root : System.FilePath)
    (id : NodeId)
    (metadata : NodeMetadata) : KBIO StoredNode := do
  let (paths, _) ← requireInitialized root
  Storage.replaceNodeMetadata paths id metadata


def replaceMetadata
    (id : NodeId)
    (metadata : NodeMetadata)
    (root? : Option System.FilePath := none) : KBIO StoredNode := do
  replaceMetadataAtRoot (← resolveRoot root?) id metadata


def validateMetadataAtRoot (root : System.FilePath) (id : NodeId) : KBIO Validation.ValidationReport :=
  liftIO <| Validation.validateMetadata root id


def validateMetadata (id : NodeId) (root? : Option System.FilePath := none) : KBIO Validation.ValidationReport := do
  validateMetadataAtRoot (← resolveRoot root?) id


def validateStorageAtRoot (root : System.FilePath) : KBIO Validation.ValidationReport :=
  liftIO <| Validation.validateStorage root


def validateStorage (root? : Option System.FilePath := none) : KBIO Validation.ValidationReport := do
  validateStorageAtRoot (← resolveRoot root?)


def validateNodeAtRoot (root : System.FilePath) (id : NodeId) : KBIO Validation.ValidationReport :=
  liftIO <| Validation.validateNode root id


def validateNode (id : NodeId) (root? : Option System.FilePath := none) : KBIO Validation.ValidationReport := do
  validateNodeAtRoot (← resolveRoot root?) id


def validateAllAtRoot (root : System.FilePath) : KBIO Validation.ValidationReport :=
  liftIO <| Validation.validateAll root


def validateAll (root? : Option System.FilePath := none) : KBIO Validation.ValidationReport := do
  validateAllAtRoot (← resolveRoot root?)


def searchTextAtRoot
    (root : System.FilePath)
    (query : String)
    (limit? : Option Nat := none) : KBIO Search.SearchResult := do
  let (paths, _) ← requireInitialized root
  Search.searchText paths query limit?


def searchText
    (query : String)
    (limit? : Option Nat := none)
    (root? : Option System.FilePath := none) : KBIO Search.SearchResult := do
  searchTextAtRoot (← resolveRoot root?) query limit?


def searchTagAtRoot
    (root : System.FilePath)
    (tag : String)
    (limit? : Option Nat := none) : KBIO Search.SearchResult := do
  let (paths, _) ← requireInitialized root
  Search.searchTag paths tag limit?


def searchTag
    (tag : String)
    (limit? : Option Nat := none)
    (root? : Option System.FilePath := none) : KBIO Search.SearchResult := do
  searchTagAtRoot (← resolveRoot root?) tag limit?


def outgoingRelationshipsAtRoot (root : System.FilePath) (id : NodeId) : KBIO (Array Relationship) := do
  let (paths, _) ← requireInitialized root
  Search.outgoingRelationships paths id


def outgoingRelationships (id : NodeId) (root? : Option System.FilePath := none) : KBIO (Array Relationship) := do
  outgoingRelationshipsAtRoot (← resolveRoot root?) id


def incomingRelationshipsAtRoot (root : System.FilePath) (id : NodeId) : KBIO (Array Search.IncomingRelationship) := do
  let (paths, _) ← requireInitialized root
  Search.incomingRelationships paths id


def incomingRelationships (id : NodeId) (root? : Option System.FilePath := none) : KBIO (Array Search.IncomingRelationship) := do
  incomingRelationshipsAtRoot (← resolveRoot root?) id


def relatedRelationshipsAtRoot (root : System.FilePath) (id : NodeId) : KBIO Search.RelatedRelationships := do
  let (paths, _) ← requireInitialized root
  Search.relatedRelationships paths id


def relatedRelationships (id : NodeId) (root? : Option System.FilePath := none) : KBIO Search.RelatedRelationships := do
  relatedRelationshipsAtRoot (← resolveRoot root?) id

end Service
end AFTK.KnowledgeBase
