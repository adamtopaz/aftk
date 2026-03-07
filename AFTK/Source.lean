module

public import Lean
public import AFTK.Id
public import AFTK.Filesystem

public section

open Lean

namespace AFTK

inductive SourceKind where
  | paper
  | book
  | notes
  | priorFormalization
  | web
  | localFile
  | other
  deriving Inhabited, Repr, BEq

namespace SourceKind

def encoded : SourceKind → String
  | .paper => "paper"
  | .book => "book"
  | .notes => "notes"
  | .priorFormalization => "prior_formalization"
  | .web => "web"
  | .localFile => "local_file"
  | .other => "other"

instance : ToString SourceKind := ⟨encoded⟩

instance : ToJson SourceKind where
  toJson kind := .str (toString kind)

instance : FromJson SourceKind where
  fromJson?
    | .str "paper" => .ok .paper
    | .str "book" => .ok .book
    | .str "notes" => .ok .notes
    | .str "prior_formalization" => .ok .priorFormalization
    | .str "web" => .ok .web
    | .str "local_file" => .ok .localFile
    | .str "other" => .ok .other
    | .str raw => .error s!"invalid source kind `{raw}`"
    | _ => .error "expected source kind string"

end SourceKind

inductive SourceLocatorKind where
  | path
  | uri
  | note
  deriving Inhabited, Repr, BEq

namespace SourceLocatorKind

def encoded : SourceLocatorKind → String
  | .path => "path"
  | .uri => "uri"
  | .note => "note"

instance : ToString SourceLocatorKind := ⟨encoded⟩

instance : ToJson SourceLocatorKind where
  toJson kind := .str (toString kind)

instance : FromJson SourceLocatorKind where
  fromJson?
    | .str "path" => .ok .path
    | .str "uri" => .ok .uri
    | .str "note" => .ok .note
    | .str raw => .error s!"invalid source locator kind `{raw}`"
    | _ => .error "expected source locator kind string"

end SourceLocatorKind

structure SourceLocator where
  kind : SourceLocatorKind
  value : String
  deriving Inhabited, Repr, BEq

namespace SourceLocator

def normalize (locator : SourceLocator) : Except String SourceLocator := do
  return {
    locator with
    value := ← nonEmptyText "source locator value" locator.value
  }

instance : ToJson SourceLocator where
  toJson locator :=
    Json.mkObj [
      ("kind", toJson locator.kind),
      ("value", .str locator.value)
    ]

instance : FromJson SourceLocator where
  fromJson? json := do
    let kind ← json.getObjValAs? SourceLocatorKind "kind"
    let value ← json.getObjValAs? String "value"
    normalize { kind, value }

instance : ToString SourceLocator where
  toString locator := s!"{locator.kind}:{locator.value}"

end SourceLocator

structure SourceRecord where
  id : SourceId
  kind : SourceKind
  title : String
  authors : Array String := #[]
  locator : SourceLocator
  version? : Option String := none
  contentHash? : Option String := none
  license? : Option String := none
  tags : Array String := #[]
  note? : Option String := none
  deriving Inhabited, Repr, BEq

namespace SourceRecord

def normalize (record : SourceRecord) : Except String SourceRecord := do
  let title ← nonEmptyText "source title" record.title
  let authors ← normalizeStringArray "author" record.authors
  let locator ← record.locator.normalize
  let version? ←
    match record.version? with
    | some version => some <$> nonEmptyText "source version" version
    | none => pure none
  let contentHash? ←
    match record.contentHash? with
    | some hash => some <$> nonEmptyText "source content hash" hash
    | none => pure none
  let license? ←
    match record.license? with
    | some license => some <$> nonEmptyText "source license" license
    | none => pure none
  let tags ← normalizeStringArray "source tag" record.tags
  let note? ←
    match record.note? with
    | some note => some <$> nonEmptyText "source note" note
    | none => pure none
  return {
    record with
    title,
    authors,
    locator,
    version?,
    contentHash?,
    license?,
    tags,
    note?
  }

instance : ToJson SourceRecord where
  toJson record :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[("id", toJson record.id), ("kind", toJson record.kind), ("title", .str record.title), ("locator", toJson record.locator)]
      if !record.authors.isEmpty then
        fields := fields.push ("authors", toJson record.authors)
      if let some version := record.version? then
        fields := fields.push ("version", .str version)
      if let some contentHash := record.contentHash? then
        fields := fields.push ("contentHash", .str contentHash)
      if let some license := record.license? then
        fields := fields.push ("license", .str license)
      if !record.tags.isEmpty then
        fields := fields.push ("tags", toJson record.tags)
      if let some note := record.note? then
        fields := fields.push ("note", .str note)
      return fields
    Json.mkObj fields.toList

instance : FromJson SourceRecord where
  fromJson? json := do
    let id ← json.getObjValAs? SourceId "id"
    let kind ← json.getObjValAs? SourceKind "kind"
    let title ← json.getObjValAs? String "title"
    let authors? ← json.getObjValAs? (Option (Array String)) "authors"
    let locator ← json.getObjValAs? SourceLocator "locator"
    let version? ← json.getObjValAs? (Option String) "version"
    let contentHash? ← json.getObjValAs? (Option String) "contentHash"
    let license? ← json.getObjValAs? (Option String) "license"
    let tags? ← json.getObjValAs? (Option (Array String)) "tags"
    let note? ← json.getObjValAs? (Option String) "note"
    normalize {
      id,
      kind,
      title,
      authors := authors?.getD #[],
      locator,
      version?,
      contentHash?,
      license?,
      tags := tags?.getD #[],
      note?
    }

/-- Validate invariants local to a source record. -/
def validate (record : SourceRecord) : Except String Unit := do
  discard <| normalize record

/-- Render a concise human-readable block. -/
def renderSummary (record : SourceRecord) : String :=
  let authorPart :=
    if record.authors.isEmpty then
      "(none)"
    else
      ", ".intercalate record.authors.toList
  let tagPart :=
    if record.tags.isEmpty then
      "(none)"
    else
      ", ".intercalate record.tags.toList
  "\n".intercalate <| [
    s!"id: {record.id}",
    s!"kind: {record.kind}",
    s!"title: {record.title}",
    s!"locator: {record.locator}",
    s!"authors: {authorPart}",
    s!"tags: {tagPart}"
  ] ++
  (match record.version? with | some version => [s!"version: {version}"] | none => []) ++
  (match record.contentHash? with | some hash => [s!"content-hash: {hash}"] | none => []) ++
  (match record.license? with | some license => [s!"license: {license}"] | none => []) ++
  (match record.note? with | some note => [s!"note: {note}"] | none => [])

end SourceRecord

def loadSourceRecordFromFile (path : System.FilePath) : IO (Except String SourceRecord) := do
  match ← readJsonFile "source record" path with
  | .error err =>
    return .error err
  | .ok json =>
    match fromJson? (α := SourceRecord) json with
    | .ok record =>
      return .ok record
    | .error err =>
      return .error s!"invalid source record `{path}`: {err}"

def loadSourceRecord (root : System.FilePath) (id : SourceId) : IO (Except String SourceRecord) :=
  loadSourceRecordFromFile (id.jsonPath root)

def saveSourceRecord (root : System.FilePath) (record : SourceRecord) : IO (Except String System.FilePath) := do
  match record.validate with
  | .error err =>
    return .error err
  | .ok () =>
    let path := record.id.jsonPath root
    try
      writeJsonAtomic path (toJson record)
      return .ok path
    catch _ =>
      return .error s!"unable to write source record `{path}`"

end AFTK
