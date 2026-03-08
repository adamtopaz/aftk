module

public import AFTK.KnowledgeBase.Storage
public import Std.Data.HashMap
public import Std.Data.HashSet

public section


namespace AFTK.KnowledgeBase

open Lean
open PathLayout
open Serialization

namespace Validation

inductive ValidationSeverity
  | error
  | warning
  | info
  deriving Repr, DecidableEq, Inhabited, BEq

instance : ToJson ValidationSeverity where
  toJson
    | .error => Json.str "error"
    | .warning => Json.str "warning"
    | .info => Json.str "info"

inductive ValidationScope
  | storage
  | node (id : NodeId)
  | metadata (id : NodeId)
  | relationships (id : NodeId)
  | wholeKnowledgeBase
  deriving Repr, DecidableEq, Inhabited

instance : ToJson ValidationScope where
  toJson
    | .storage => Json.mkObj [("kind", Json.str "storage")]
    | .node id => Json.mkObj [("kind", Json.str "node"), ("id", toJson id)]
    | .metadata id => Json.mkObj [("kind", Json.str "metadata"), ("id", toJson id)]
    | .relationships id => Json.mkObj [("kind", Json.str "relationships"), ("id", toJson id)]
    | .wholeKnowledgeBase => Json.mkObj [("kind", Json.str "wholeKnowledgeBase")]

structure ValidationIssue where
  code : String
  severity : ValidationSeverity
  scope : ValidationScope
  message : String
  path? : Option System.FilePath := none
  relatedNodeId? : Option NodeId := none
  deriving Repr, DecidableEq, Inhabited

instance : ToJson ValidationIssue where
  toJson issue :=
    Json.mkObj <|
      [ ("code", toJson issue.code)
      , ("severity", toJson issue.severity)
      , ("scope", toJson issue.scope)
      , ("message", toJson issue.message)
      ] ++
      Json.opt "path" issue.path? ++
      Json.opt "relatedNodeId" issue.relatedNodeId?

structure ValidationReport where
  ok : Bool
  issues : Array ValidationIssue := #[]
  deriving Repr, DecidableEq, Inhabited

instance : ToJson ValidationReport where
  toJson report := Json.mkObj [
    ("ok", toJson report.ok),
    ("issues", toJson report.issues)
  ]

private def mkIssue
    (code : String)
    (severity : ValidationSeverity)
    (scope : ValidationScope)
    (message : String)
    (path? : Option System.FilePath := none)
    (relatedNodeId? : Option NodeId := none) : ValidationIssue :=
  { code, severity, scope, message, path?, relatedNodeId? }

private def reportOfIssues (issues : Array ValidationIssue) : ValidationReport :=
  let ok := !issues.any (fun issue => issue.severity == .error)
  { ok, issues }

private def metadataLocalIssues (metadata : NodeMetadata) : Array ValidationIssue := Id.run do
  let mut issues := #[]
  if metadata.title.trimAscii.isEmpty then
    issues := issues.push <| mkIssue
      "metadata.emptyTitle"
      .error
      (.metadata metadata.id)
      s!"Metadata title is empty for node {metadata.id}"
  let mut seen : Std.HashSet String := {}
  for rel in metadata.relationships do
    let key := s!"{rel.kind.asString}|{rel.target.value}|{rel.label?.getD ""}|{rel.note?.getD ""}"
    if seen.contains key then
      issues := issues.push <| mkIssue
        "relationships.duplicateEdge"
        .warning
        (.relationships metadata.id)
        s!"Duplicate relationship from {metadata.id} to {rel.target} ({rel.kind})"
        (relatedNodeId? := some rel.target)
    else
      seen := seen.insert key
    if rel.target == metadata.id then
      issues := issues.push <| mkIssue
        "relationships.selfEdgeWarning"
        .warning
        (.relationships metadata.id)
        s!"Relationship from {metadata.id} points to itself ({rel.kind})"
        (relatedNodeId? := some rel.target)
  issues

private def probeRoot (root : System.FilePath) : IO (Array ValidationIssue × Option (KnowledgeBaseStoragePaths × StorageManifest)) := do
  let mut issues := #[]
  let provisional := storagePathsForRoot root
  if !(← provisional.rootDir.pathExists) then
    issues := issues.push <| mkIssue
      "storage.rootMissing"
      .error
      .storage
      s!"Knowledge base root does not exist: {root}"
      (path? := some root)
    return (issues, none)
  if !(← provisional.manifestPath.pathExists) then
    issues := issues.push <| mkIssue
      "storage.manifestMissing"
      .error
      .storage
      s!"Manifest is missing: {provisional.manifestPath}"
      (path? := some provisional.manifestPath)
    return (issues, none)
  let manifestText ← try
    IO.FS.readFile provisional.manifestPath
  catch e =>
    let issues' := issues.push <| mkIssue
      "storage.manifestReadError"
      .error
      .storage
      s!"Failed to read manifest {provisional.manifestPath}: {e.toString}"
      (path? := some provisional.manifestPath)
    return (issues', none)
  let manifest ← match parseStorageManifestText manifestText with
    | .ok manifest => pure manifest
    | .error err =>
        let issues' := issues.push <| mkIssue
          "storage.manifestParseError"
          .error
          .storage
          s!"Invalid manifest {provisional.manifestPath}: {err}"
          (path? := some provisional.manifestPath)
        return (issues', none)
  let paths := storagePathsForRoot root manifest
  if !(← paths.nodesDir.pathExists) then
    issues := issues.push <| mkIssue
      "storage.nodesDirMissing"
      .error
      .storage
      s!"Nodes directory is missing: {paths.nodesDir}"
      (path? := some paths.nodesDir)
  if !(← paths.internalDir.pathExists) then
    issues := issues.push <| mkIssue
      "storage.internalDirMissing"
      .info
      .storage
      s!"Internal directory is missing and may be created lazily: {paths.internalDir}"
      (path? := some paths.internalDir)
  let result := if issues.any (fun issue => issue.severity == .error) then none else some (paths, manifest)
  return (issues, result)


def validateStorage (root : System.FilePath) : IO ValidationReport := do
  let (issues, _) ← probeRoot root
  return reportOfIssues issues


def validateMetadata (root : System.FilePath) (id : NodeId) : IO ValidationReport := do
  let (storageIssues, rootInfo?) ← probeRoot root
  match rootInfo? with
  | none => return reportOfIssues storageIssues
  | some (paths, _) =>
      let path := (nodePaths paths id).metadataPath
      let mut issues := storageIssues
      if !(← path.pathExists) then
        issues := issues.push <| mkIssue
          "node.metadataMissing"
          .error
          (.metadata id)
          s!"Metadata file is missing for node {id}: {path}"
          (path? := some path)
        return reportOfIssues issues
      let text ← try
        IO.FS.readFile path
      catch e =>
        issues := issues.push <| mkIssue
          "metadata.readError"
          .error
          (.metadata id)
          s!"Failed to read metadata {path}: {e.toString}"
          (path? := some path)
        return reportOfIssues issues
      match parseNodeMetadataText text with
      | .error err =>
          issues := issues.push <| mkIssue
            "metadata.parseError"
            .error
            (.metadata id)
            s!"Invalid metadata for node {id}: {err}"
            (path? := some path)
      | .ok metadata =>
          if metadata.id != id then
            issues := issues.push <| mkIssue
              "node.idPathMismatch"
              .error
              (.metadata id)
              s!"Metadata id {metadata.id} does not match requested node id {id}"
              (path? := some path)
              (relatedNodeId? := some metadata.id)
          issues := issues ++ metadataLocalIssues metadata
      return reportOfIssues issues


def validateNode (root : System.FilePath) (id : NodeId) : IO ValidationReport := do
  let (storageIssues, rootInfo?) ← probeRoot root
  match rootInfo? with
  | none => return reportOfIssues storageIssues
  | some (paths, _) =>
      let resolved := nodePaths paths id
      let mut issues := storageIssues
      if !(← resolved.markdownPath.pathExists) then
        issues := issues.push <| mkIssue
          "node.markdownMissing"
          .error
          (.node id)
          s!"Markdown file is missing for node {id}: {resolved.markdownPath}"
          (path? := some resolved.markdownPath)
      if !(← resolved.metadataPath.pathExists) then
        issues := issues.push <| mkIssue
          "node.metadataMissing"
          .error
          (.node id)
          s!"Metadata file is missing for node {id}: {resolved.metadataPath}"
          (path? := some resolved.metadataPath)
      if issues.any (fun issue => issue.severity == .error && issue.scope == .node id) then
        return reportOfIssues issues
      try
        let _ ← readMarkdownFile resolved.markdownPath
        pure ()
      catch e =>
        issues := issues.push <| mkIssue
          "node.markdownReadError"
          .error
          (.node id)
          s!"Failed to read markdown {resolved.markdownPath}: {e.toString}"
          (path? := some resolved.markdownPath)
      let metadataIssues ← validateMetadata root id
      let combinedIssues := issues ++ metadataIssues.issues.filter (fun issue => issue.scope != .storage)
      return reportOfIssues combinedIssues

private structure LoadedNodeInfo where
  pathId : NodeId
  metadata : NodeMetadata
  files : DiscoveredNodeFiles


def validateAll (root : System.FilePath) : IO ValidationReport := do
  let (storageIssues, rootInfo?) ← probeRoot root
  match rootInfo? with
  | none => return reportOfIssues storageIssues
  | some (paths, _) =>
      let mut issues := storageIssues
      let discoveredResult ← (Storage.scanCanonicalNodeFiles paths).toIO'
      let discovered ← match discoveredResult with
        | Except.ok discovered => pure discovered
        | Except.error err =>
            let issues' := issues.push <| mkIssue
              "storage.scanFailed"
              .error
              .wholeKnowledgeBase
              s!"Failed to scan canonical node files: {err.message}"
              (path? := some paths.nodesDir)
            return reportOfIssues issues'
      let mut loaded : Array LoadedNodeInfo := #[]
      let mut seenIds : Std.HashMap String System.FilePath := {}
      for files in discovered do
        let some pathId := (match pathStemToNodeId? files.stem with | .ok id => some id | .error _ => none)
          | let path? := files.markdownPath?.orElse (fun _ => files.metadataPath?)
            issues := issues.push <| mkIssue
              "node.invalidPathId"
              .error
              .wholeKnowledgeBase
              s!"Canonical stem does not map to a valid node id: {files.stem}"
              (path? := path?)
            continue
        match files.markdownPath?, files.metadataPath? with
        | some markdownPath, some metadataPath =>
            try
              let _ ← readMarkdownFile markdownPath
            catch e =>
              issues := issues.push <| mkIssue
                "node.markdownReadError"
                .error
                (.node pathId)
                s!"Failed to read markdown {markdownPath}: {e.toString}"
                (path? := some markdownPath)
            let metadataText ← try
              IO.FS.readFile metadataPath
            catch e =>
              issues := issues.push <| mkIssue
                "metadata.readError"
                .error
                (.metadata pathId)
                s!"Failed to read metadata {metadataPath}: {e.toString}"
                (path? := some metadataPath)
              continue
            match parseNodeMetadataText metadataText with
            | .error err =>
                issues := issues.push <| mkIssue
                  "metadata.parseError"
                  .error
                  (.metadata pathId)
                  s!"Invalid metadata for node {pathId}: {err}"
                  (path? := some metadataPath)
            | .ok metadata =>
                if metadata.id != pathId then
                  issues := issues.push <| mkIssue
                    "node.idPathMismatch"
                    .error
                    (.node pathId)
                    s!"Metadata id {metadata.id} does not match path-derived id {pathId}"
                    (path? := some metadataPath)
                    (relatedNodeId? := some metadata.id)
                issues := issues ++ metadataLocalIssues metadata
                match seenIds.get? metadata.id.value with
                | some firstPath =>
                    issues := issues.push <| mkIssue
                      "node.duplicateId"
                      .error
                      .wholeKnowledgeBase
                      s!"Duplicate node id found: {metadata.id}"
                      (path? := some metadataPath)
                      (relatedNodeId? := some metadata.id)
                    issues := issues.push <| mkIssue
                      "node.duplicateId"
                      .error
                      .wholeKnowledgeBase
                      s!"Duplicate node id also present at {firstPath}"
                      (path? := some firstPath)
                      (relatedNodeId? := some metadata.id)
                | none =>
                    seenIds := seenIds.insert metadata.id.value metadataPath
                loaded := loaded.push { pathId := pathId, metadata := metadata, files := files }
        | some markdownPath, none =>
            issues := issues.push <| mkIssue
              "node.orphanMarkdown"
              .error
              (.node pathId)
              s!"Markdown file has no matching metadata file: {markdownPath}"
              (path? := some markdownPath)
        | none, some metadataPath =>
            issues := issues.push <| mkIssue
              "node.orphanMetadata"
              .error
              (.node pathId)
              s!"Metadata file has no matching markdown file: {metadataPath}"
              (path? := some metadataPath)
        | none, none => pure ()
      let validIds : Std.HashSet String := loaded.foldl (init := {}) fun set info => set.insert info.metadata.id.value
      for info in loaded do
        for rel in info.metadata.relationships do
          if !validIds.contains rel.target.value then
            issues := issues.push <| mkIssue
              "relationships.targetNotFound"
              .error
              (.relationships info.metadata.id)
              s!"Relationship target {rel.target} referenced from {info.metadata.id} does not exist"
              (path? := info.files.metadataPath?)
              (relatedNodeId? := some rel.target)
      return reportOfIssues issues

end Validation

end AFTK.KnowledgeBase
