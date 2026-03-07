module

public import Lean
public import Informalize.Location
public import Init.Data.String.Legacy

public section

open Lean

namespace Informalize

/-- Trim surrounding ASCII whitespace from a string. -/
def normalizeText (raw : String) : String :=
  raw.trimAscii.toString

/-- Require a trimmed string to be non-empty. -/
def nonEmptyText (label raw : String) : Except String String := do
  let trimmed := normalizeText raw
  if trimmed.isEmpty then
    throw s!"{label} must be non-empty"
  return trimmed

inductive MetadataOrigin where
  | default
  | file
  deriving Inhabited, Repr, BEq

namespace MetadataOrigin

instance : ToString MetadataOrigin where
  toString
    | .default => "default"
    | .file => "file"

instance : ToJson MetadataOrigin where
  toJson origin := .str (toString origin)

end MetadataOrigin

inductive NodeStatus where
  | scaffolded
  | needsSources
  | needsRefinement
  | ready
  | formalizing
  | formalized
  | blocked
  deriving Inhabited, Repr, BEq

namespace NodeStatus

def encoded : NodeStatus → String
  | .scaffolded => "scaffolded"
  | .needsSources => "needs_sources"
  | .needsRefinement => "needs_refinement"
  | .ready => "ready"
  | .formalizing => "formalizing"
  | .formalized => "formalized"
  | .blocked => "blocked"

instance : ToString NodeStatus := ⟨encoded⟩

instance : ToJson NodeStatus where
  toJson status := .str (toString status)

instance : FromJson NodeStatus where
  fromJson?
    | .str "scaffolded" =>
      .ok .scaffolded
    | .str "needs_sources" =>
      .ok .needsSources
    | .str "needs_refinement" =>
      .ok .needsRefinement
    | .str "ready" =>
      .ok .ready
    | .str "formalizing" =>
      .ok .formalizing
    | .str "formalized" =>
      .ok .formalized
    | .str "blocked" =>
      .ok .blocked
    | .str other =>
      .error s!"invalid node status `{other}`"
    | _ =>
      .error "expected node status string"

end NodeStatus

structure SourceRef where
  sourceId : String
  anchors : Array String := #[]
  locator? : Option String := none
  role? : Option String := none
  deriving Inhabited, Repr, BEq

namespace SourceRef

def normalize (source : SourceRef) : Except String SourceRef := do
  let sourceId ← nonEmptyText "sourceId" source.sourceId
  let anchors ← source.anchors.mapM (nonEmptyText "source anchor")
  let locator? ←
    match source.locator? with
    | some locator =>
      some <$> nonEmptyText "source locator" locator
    | none =>
      pure none
  let role? ←
    match source.role? with
    | some role =>
      some <$> nonEmptyText "source role" role
    | none =>
      pure none
  return {
    sourceId,
    anchors,
    locator?,
    role?
  }

instance : ToJson SourceRef where
  toJson source :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[
        ("sourceId", .str source.sourceId)
      ]
      if !source.anchors.isEmpty then
        fields := fields.push ("anchors", toJson source.anchors)
      if let some locator := source.locator? then
        fields := fields.push ("locator", .str locator)
      if let some role := source.role? then
        fields := fields.push ("role", .str role)
      return fields
    Json.mkObj fields.toList

instance : FromJson SourceRef where
  fromJson? json := do
    let sourceId ← json.getObjValAs? String "sourceId"
    let anchors? ← json.getObjValAs? (Option (Array String)) "anchors"
    let locator? ← json.getObjValAs? (Option String) "locator"
    let role? ← json.getObjValAs? (Option String) "role"
    normalize {
      sourceId,
      anchors := anchors?.getD #[],
      locator?,
      role?
    }

/-- Render a compact human-readable source summary. -/
def renderSummary (source : SourceRef) : String :=
  let anchorPart :=
    if source.anchors.isEmpty then
      ""
    else
      s!" anchors=[{", ".intercalate source.anchors.toList}]"
  let locatorPart :=
    match source.locator? with
    | some locator =>
      s!" locator={locator}"
    | none =>
      ""
  let rolePart :=
    match source.role? with
    | some role =>
      s!" role={role}"
    | none =>
      ""
  s!"{source.sourceId}{anchorPart}{locatorPart}{rolePart}"

end SourceRef

structure WorkflowIssue where
  id : String
  kind : String
  refs : Array String := #[]
  note : String
  deriving Inhabited, Repr, BEq

namespace WorkflowIssue

def normalize (issue : WorkflowIssue) : Except String WorkflowIssue := do
  let id ← nonEmptyText "issue id" issue.id
  let kind ← nonEmptyText "issue kind" issue.kind
  let refs ← issue.refs.mapM (nonEmptyText "issue ref")
  let note ← nonEmptyText "issue note" issue.note
  return {
    id,
    kind,
    refs,
    note
  }

instance : ToJson WorkflowIssue where
  toJson issue :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[
        ("id", .str issue.id),
        ("kind", .str issue.kind),
        ("note", .str issue.note)
      ]
      if !issue.refs.isEmpty then
        fields := fields.push ("refs", toJson issue.refs)
      return fields
    Json.mkObj fields.toList

instance : FromJson WorkflowIssue where
  fromJson? json := do
    let id ← json.getObjValAs? String "id"
    let kind ← json.getObjValAs? String "kind"
    let refs? ← json.getObjValAs? (Option (Array String)) "refs"
    let note ← json.getObjValAs? String "note"
    normalize {
      id,
      kind,
      refs := refs?.getD #[],
      note
    }

/-- Render a compact human-readable issue summary. -/
def renderSummary (issue : WorkflowIssue) : String :=
  let refsPart :=
    if issue.refs.isEmpty then
      ""
    else
      s!" refs=[{", ".intercalate issue.refs.toList}]"
  s!"{issue.id} ({issue.kind}){refsPart}: {issue.note}"

end WorkflowIssue

structure Metadata where
  schemaVersion : Nat := 1
  kind? : Option String := none
  status : NodeStatus := .scaffolded
  parent? : Option LocationId := none
  sources : Array SourceRef := #[]
  knowledgeRefs : Array String := #[]
  issues : Array WorkflowIssue := #[]
  tags : Array String := #[]
  deriving Inhabited, Repr, BEq

namespace Metadata

def normalize (metadata : Metadata) : Except String Metadata := do
  let kind? ←
    match metadata.kind? with
    | some kind =>
      some <$> nonEmptyText "kind" kind
    | none =>
      pure none
  let knowledgeRefs ← metadata.knowledgeRefs.mapM (nonEmptyText "knowledge ref")
  let tags ← metadata.tags.mapM (nonEmptyText "tag")
  let sources ← metadata.sources.mapM SourceRef.normalize
  let issues ← metadata.issues.mapM WorkflowIssue.normalize
  return {
    metadata with
    kind?,
    sources,
    knowledgeRefs,
    issues,
    tags
  }

/-- The default effective metadata used when no JSON sidecar exists. -/
def default : Metadata := {}

/-- Validate metadata fields that are independent of the owning location id. -/
def validateGeneral (metadata : Metadata) : Except String Unit := do
  if metadata.schemaVersion != 1 then
    throw s!"unsupported metadata schemaVersion `{metadata.schemaVersion}`"
  let mut issueIds : Std.HashSet String := {}
  for issue in metadata.issues do
    if issueIds.contains issue.id then
      throw s!"duplicate issue id `{issue.id}`"
    issueIds := issueIds.insert issue.id

/-- Validate metadata using the location it belongs to. -/
def validateForLocation (location : LocationId) (metadata : Metadata) : Except String Unit := do
  validateGeneral metadata
  if let some parent := metadata.parent? then
    if parent == location then
      throw "metadata parent cannot equal the location itself"

instance : ToJson Metadata where
  toJson metadata :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[
        ("schemaVersion", toJson metadata.schemaVersion),
        ("status", toJson metadata.status)
      ]
      if let some kind := metadata.kind? then
        fields := fields.push ("kind", .str kind)
      if let some parent := metadata.parent? then
        fields := fields.push ("parent", toJson parent)
      if !metadata.sources.isEmpty then
        fields := fields.push ("sources", toJson metadata.sources)
      if !metadata.knowledgeRefs.isEmpty then
        fields := fields.push ("knowledgeRefs", toJson metadata.knowledgeRefs)
      if !metadata.issues.isEmpty then
        fields := fields.push ("issues", toJson metadata.issues)
      if !metadata.tags.isEmpty then
        fields := fields.push ("tags", toJson metadata.tags)
      return fields
    Json.mkObj fields.toList

instance : FromJson Metadata where
  fromJson? json := do
    let schemaVersion? ← json.getObjValAs? (Option Nat) "schemaVersion"
    let kind? ← json.getObjValAs? (Option String) "kind"
    let status? ← json.getObjValAs? (Option NodeStatus) "status"
    let parent? ← json.getObjValAs? (Option LocationId) "parent"
    let sources? ← json.getObjValAs? (Option (Array SourceRef)) "sources"
    let knowledgeRefs? ← json.getObjValAs? (Option (Array String)) "knowledgeRefs"
    let issues? ← json.getObjValAs? (Option (Array WorkflowIssue)) "issues"
    let tags? ← json.getObjValAs? (Option (Array String)) "tags"
    let metadata ← normalize {
      schemaVersion := schemaVersion?.getD 1,
      kind?,
      status := status?.getD .scaffolded,
      parent?,
      sources := sources?.getD #[],
      knowledgeRefs := knowledgeRefs?.getD #[],
      issues := issues?.getD #[],
      tags := tags?.getD #[]
    }
    validateGeneral metadata
    return metadata

/-- Render effective metadata as a concise human-readable block. -/
def renderSummary (metadata : Metadata) : String :=
  let baseLines := [
    s!"status: {metadata.status}",
    s!"kind: {metadata.kind?.getD "(none)"}",
    s!"parent: {metadata.parent?.map toString |>.getD "(none)"}",
    s!"sources: {metadata.sources.size}",
    s!"knowledgeRefs: {metadata.knowledgeRefs.size}",
    s!"issues: {metadata.issues.size}",
    s!"tags: {metadata.tags.size}"
  ]
  let sourceLines :=
    if metadata.sources.isEmpty then
      []
    else
      "source-items:" :: (metadata.sources.toList.map fun source => s!"- {SourceRef.renderSummary source}")
  let knowledgeLines :=
    if metadata.knowledgeRefs.isEmpty then
      []
    else
      [s!"knowledge-ref-items: {", ".intercalate metadata.knowledgeRefs.toList}"]
  let issueLines :=
    if metadata.issues.isEmpty then
      []
    else
      "issue-items:" :: (metadata.issues.toList.map fun issue => s!"- {WorkflowIssue.renderSummary issue}")
  let tagLines :=
    if metadata.tags.isEmpty then
      []
    else
      [s!"tag-items: {", ".intercalate metadata.tags.toList}"]
  "\n".intercalate <| baseLines ++ sourceLines ++ knowledgeLines ++ issueLines ++ tagLines

end Metadata

structure LoadedMetadata where
  metadata : Metadata
  origin : MetadataOrigin
  deriving Inhabited, Repr, BEq

namespace LoadedMetadata

/-- Render hover text combining location, metadata, and markdown notes. -/
def renderHoverText
    (location : LocationId)
    (loaded : LoadedMetadata)
    (markdown : String) : String :=
  "\n".intercalate [
    s!"Informalize location: {location}",
    s!"Metadata source: {loaded.origin}",
    "",
    "Metadata",
    "--------",
    loaded.metadata.renderSummary,
    "",
    "Notes",
    "-----",
    markdown
  ]

end LoadedMetadata

private def wrapMetadataError
    (path : System.FilePath)
    (location : LocationId)
    (message : String) : String :=
  s!"invalid metadata in `{path}` for location `{location}`: {message}"

private def parseMetadataContents
    (location : LocationId)
    (path : System.FilePath)
    (contents : String) : Except String Metadata := do
  let json ←
    match Json.parse contents with
    | .ok json =>
      pure json
    | .error err =>
      throw <| wrapMetadataError path location err
  let metadata ←
    match fromJson? (α := Metadata) json with
    | .ok metadata =>
      pure metadata
    | .error err =>
      throw <| wrapMetadataError path location err
  match metadata.validateForLocation location with
  | .ok () =>
    pure metadata
  | .error err =>
    throw <| wrapMetadataError path location err

/-- Load persisted metadata if a metadata sidecar exists. -/
def loadPersistedMetadata?
    (location : LocationId) : IO (Except String (Option Metadata)) := do
  let path := location.metadataPath
  let pathExists ← path.pathExists
  if !pathExists then
    return .ok none
  let contents ←
    try
      pure <| Except.ok (← IO.FS.readFile path)
    catch _ =>
      pure <| Except.error s!"unable to read metadata file `{path}` for location `{location}`"
  match contents with
  | .error err =>
    return .error err
  | .ok contents =>
    return (parseMetadataContents location path contents).map some

/-- Load the effective metadata for a location, falling back to defaults when the JSON sidecar is absent. -/
def loadEffectiveMetadata
    (location : LocationId) : IO (Except String LoadedMetadata) := do
  match ← loadPersistedMetadata? location with
  | .error err =>
    return .error err
  | .ok (some metadata) =>
    return .ok {
      metadata,
      origin := .file
    }
  | .ok none =>
    return .ok {
      metadata := Metadata.default,
      origin := .default
    }

private def metadataJsonText (metadata : Metadata) : String :=
  (toJson metadata).pretty ++ "\n"

/-- Write canonical metadata JSON for a location, creating parent directories as needed. -/
def writeMetadata
    (location : LocationId)
    (metadata : Metadata) : IO (Except String Unit) := do
  match metadata.validateForLocation location with
  | .error err =>
    return .error s!"invalid metadata for location `{location}`: {err}"
  | .ok () =>
    let path := location.metadataPath
    let tempPath := System.FilePath.mk s!"{path}.tmp"
    try
      if let some dir := path.parent then
        IO.FS.createDirAll dir
      if (← tempPath.pathExists) then
        try
          IO.FS.removeFile tempPath
        catch _ =>
          pure ()
      IO.FS.writeFile tempPath (metadataJsonText metadata)
      IO.FS.rename tempPath path
      return .ok ()
    catch _ =>
      return .error s!"unable to write metadata file `{path}` for location `{location}`"

end Informalize
