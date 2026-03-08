module

public import AFTK.KnowledgeBase.Types

public section


namespace AFTK.KnowledgeBase

open System

namespace PathLayout

private def pathOfParts (parts : List String) : FilePath :=
  System.mkFilePath parts

private def withSuffix (path : FilePath) (suffix : String) : FilePath :=
  FilePath.mk (path.toString ++ suffix)


def resolveRootPath (root? : Option FilePath := none) : IO FilePath := do
  let cwd ← IO.currentDir
  let root := root?.getD defaultKnowledgeBaseRoot
  let resolved := if root.isAbsolute then root else cwd / root
  pure resolved.normalize


def defaultManifest : StorageManifest := {}


def storagePathsForRoot (root : FilePath) (manifest : StorageManifest := defaultManifest) : KnowledgeBaseStoragePaths :=
  let nodesDir := root / manifest.nodesDir
  let internalDir := root / manifest.internalDir
  {
    rootDir := root
    manifestPath := root / "manifest.json"
    nodesDir := nodesDir
    internalDir := internalDir
    indexDir := internalDir / "index"
    cacheDir := internalDir / "cache"
    tmpDir := internalDir / "tmp"
  }


def nodeIdToRelativeStem (id : NodeId) : FilePath :=
  pathOfParts id.segments


def nodePaths (paths : KnowledgeBaseStoragePaths) (id : NodeId) : NodePaths :=
  let stem := paths.nodesDir / nodeIdToRelativeStem id
  {
    markdownPath := withSuffix stem ".md"
    metadataPath := withSuffix stem ".json"
  }

private def stripPrefixComponents? (pref path : FilePath) : Option (List String) :=
  let prefixComps := pref.normalize.components
  let pathComps := path.normalize.components
  if pathComps.take prefixComps.length == prefixComps then
    some (pathComps.drop prefixComps.length)
  else
    none


def relativeToNodesDir? (nodesDir path : FilePath) : Option FilePath := do
  let parts ← stripPrefixComponents? nodesDir path
  some <| pathOfParts parts


def stemFromRelativeNodeFile? (relativeFile : FilePath) : Option FilePath := do
  match relativeFile.extension with
  | some "md" => some <| relativeFile.withExtension ""
  | some "json" => some <| relativeFile.withExtension ""
  | _ => none


def stemFromAbsoluteNodeFile? (nodesDir path : FilePath) : Option FilePath := do
  let relative ← relativeToNodesDir? nodesDir path
  stemFromRelativeNodeFile? relative


def pathStemToNodeId? (stem : FilePath) : Except String NodeId := do
  let parts := stem.normalize.components
  if parts.isEmpty then
    throw "empty node path stem"
  NodeId.ofString? <| String.intercalate "." parts


def nodeIdFromNodeFilePath? (nodesDir path : FilePath) : Except String NodeId := do
  let some stem := stemFromAbsoluteNodeFile? nodesDir path
    | throw s!"path is not a canonical node file under {nodesDir}: {path}"
  pathStemToNodeId? stem


def discoveredPathId? (_paths : KnowledgeBaseStoragePaths) (files : DiscoveredNodeFiles) : Except String NodeId :=
  pathStemToNodeId? files.stem

end PathLayout

end AFTK.KnowledgeBase
