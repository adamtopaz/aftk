module

public import AFTK.KnowledgeBase.PathLayout
public import Lean.Data.Json.Parser

public section


namespace AFTK.KnowledgeBase

open Lean

namespace Serialization

abbrev JsonObject := Std.TreeMap.Raw String Json compare
abbrev RenderFn := Nat → String

private def indent (n : Nat) : String :=
  String.ofList (List.replicate (n * 2) ' ')

private def quoted (s : String) : String :=
  Json.compress (Json.str s)

private def addTrailingCommas : List String → List String
  | [] => []
  | [line] => [line]
  | line :: rest => (line ++ ",") :: addTrailingCommas rest

private def renderObject (level : Nat) (fields : List (String × RenderFn)) : String :=
  if fields.isEmpty then
    "{}"
  else
    let child := level + 1
    let rendered := fields.map fun (key, valueFn) =>
      indent child ++ quoted key ++ ": " ++ valueFn child
    let rendered := addTrailingCommas rendered
    "{\n" ++ String.intercalate "\n" rendered ++ "\n" ++ indent level ++ "}"

private def renderArray (level : Nat) (items : List RenderFn) : String :=
  if items.isEmpty then
    "[]"
  else
    let child := level + 1
    let rendered := items.map fun itemFn =>
      indent child ++ itemFn child
    let rendered := addTrailingCommas rendered
    "[\n" ++ String.intercalate "\n" rendered ++ "\n" ++ indent level ++ "]"

private def renderScalar [ToJson α] (value : α) : RenderFn :=
  fun _ => Json.compress (toJson value)

private def renderCompactArray [ToJson α] (values : Array α) : RenderFn :=
  fun _ =>
    "[" ++ String.intercalate ", " (values.toList.map (fun value => Json.compress (toJson value))) ++ "]"

private def renderRelationship (rel : Relationship) : RenderFn :=
  fun level =>
    renderObject level <|
      [ ("kind", renderScalar rel.kind)
      , ("target", renderScalar rel.target)
      ] ++
      (match rel.label? with | some label => [("label", renderScalar label)] | none => []) ++
      (match rel.note? with | some note => [("note", renderScalar note)] | none => [])

private def renderLeanDeclRef (ref : LeanDeclRef) : RenderFn :=
  fun level =>
    renderObject level <|
      (match ref.module? with | some moduleName => [("module", renderScalar moduleName)] | none => []) ++
      [ ("declaration", renderScalar ref.declaration) ] ++
      (match ref.kind? with | some kind => [("kind", renderScalar kind)] | none => [])

private def renderNodeMetadataFields (metadata : NodeMetadata) : List (String × RenderFn) :=
  [ ("schemaVersion", renderScalar metadata.schemaVersion)
  , ("id", renderScalar metadata.id)
  , ("title", renderScalar metadata.title)
  ] ++
  (if metadata.kind != .note then [("kind", renderScalar metadata.kind)] else []) ++
  (if metadata.status != .draft then [("status", renderScalar metadata.status)] else []) ++
  (match metadata.summary? with | some summary => [("summary", renderScalar summary)] | none => []) ++
  (if metadata.tags.isEmpty then [] else [("tags", renderCompactArray metadata.tags)]) ++
  (if metadata.authors.isEmpty then [] else [("authors", renderCompactArray metadata.authors)]) ++
  (match metadata.createdAt? with | some createdAt => [("createdAt", renderScalar createdAt)] | none => []) ++
  (match metadata.updatedAt? with | some updatedAt => [("updatedAt", renderScalar updatedAt)] | none => []) ++
  (if metadata.relationships.isEmpty then [] else [("relationships", fun level => renderArray level (metadata.relationships.toList.map renderRelationship))]) ++
  (if metadata.leanRefs.isEmpty then [] else [("leanRefs", fun level => renderArray level (metadata.leanRefs.toList.map renderLeanDeclRef))])


def renderStorageManifest (manifest : StorageManifest) : String :=
  renderObject 0
    [ ("schemaVersion", renderScalar manifest.schemaVersion)
    , ("kind", renderScalar manifest.kind)
    , ("nodesDir", renderScalar manifest.nodesDir)
    , ("internalDir", renderScalar manifest.internalDir)
    ] ++ "\n"


def renderNodeMetadata (metadata : NodeMetadata) : String :=
  renderObject 0 (renderNodeMetadataFields metadata) ++ "\n"


def normalizeLineEndings (text : String) : String :=
  (text.replace "\r\n" "\n").replace "\r" "\n"


def ensureTrailingNewline (text : String) : String :=
  if text.endsWith "\n" then text else text ++ "\n"


def normalizeMarkdownForWrite (text : String) : String :=
  ensureTrailingNewline (normalizeLineEndings text)


def normalizeMarkdownForRead (text : String) : String :=
  normalizeLineEndings text

private def parseJsonText (text : String) : Except String Json :=
  Json.parse text

private def requireObject (json : Json) : Except String JsonObject :=
  json.getObj?

private def rejectUnknownFields (obj : JsonObject) (allowed : List String) : Except String Unit := do
  for (key, _) in obj.toList do
    unless allowed.contains key do
      throw s!"unknown field: {key}"

private def requireField (obj : JsonObject) (field : String) : Except String Json :=
  match obj.get? field with
  | some value => return value
  | none => throw s!"missing required field: {field}"

private def optionalField (obj : JsonObject) (field : String) : Option Json :=
  obj.get? field

private def requireFieldAs [FromJson α] (obj : JsonObject) (field : String) : Except String α := do
  let value ← requireField obj field
  fromJson? value

private def optionalFieldAs [FromJson α] (obj : JsonObject) (field : String) : Except String (Option α) :=
  match optionalField obj field with
  | some value => some <$> fromJson? value
  | none => pure none

private def defaultFieldAs [FromJson α] (obj : JsonObject) (field : String) (default : α) : Except String α := do
  match optionalField obj field with
  | some value => fromJson? value
  | none => pure default

private def parseRelationshipJson (json : Json) : Except String Relationship := do
  let obj ← requireObject json
  rejectUnknownFields obj ["kind", "target", "label", "note"]
  return {
    kind := ← requireFieldAs obj "kind"
    target := ← requireFieldAs obj "target"
    label? := ← optionalFieldAs obj "label"
    note? := ← optionalFieldAs obj "note"
  }

private def parseLeanDeclRefJson (json : Json) : Except String LeanDeclRef := do
  let obj ← requireObject json
  rejectUnknownFields obj ["module", "declaration", "kind"]
  return {
    module? := ← optionalFieldAs obj "module"
    declaration := ← requireFieldAs obj "declaration"
    kind? := ← optionalFieldAs obj "kind"
  }

private def parseRelationshipArray (json : Json) : Except String (Array Relationship) := do
  let arr ← json.getArr?
  arr.mapM parseRelationshipJson

private def parseLeanDeclRefArray (json : Json) : Except String (Array LeanDeclRef) := do
  let arr ← json.getArr?
  arr.mapM parseLeanDeclRefJson


def parseStorageManifestJson (json : Json) : Except String StorageManifest := do
  let obj ← requireObject json
  rejectUnknownFields obj ["schemaVersion", "kind", "nodesDir", "internalDir"]
  let schemaVersion : Nat ← requireFieldAs obj "schemaVersion"
  if schemaVersion != defaultSchemaVersion then
    throw s!"unsupported schema version: {schemaVersion}"
  let kind : String ← requireFieldAs obj "kind"
  if kind != defaultManifestKind then
    throw s!"unsupported manifest kind: {kind}"
  let nodesDir : String ← requireFieldAs obj "nodesDir"
  let internalDir : String ← requireFieldAs obj "internalDir"
  return {
    schemaVersion := schemaVersion
    kind := kind
    nodesDir := nodesDir
    internalDir := internalDir
  }


def parseStorageManifestText (text : String) : Except String StorageManifest := do
  parseStorageManifestJson (← parseJsonText text)


def parseNodeMetadataJson (json : Json) : Except String NodeMetadata := do
  let obj ← requireObject json
  rejectUnknownFields obj [
    "schemaVersion", "id", "title", "kind", "status", "summary", "tags", "authors",
    "createdAt", "updatedAt", "relationships", "leanRefs"
  ]
  let schemaVersion : Nat ← requireFieldAs obj "schemaVersion"
  if schemaVersion != defaultSchemaVersion then
    throw s!"unsupported schema version: {schemaVersion}"
  let id : NodeId ← requireFieldAs obj "id"
  let title : String ← requireFieldAs obj "title"
  let kind : NodeKind ← defaultFieldAs obj "kind" .note
  let status : NodeStatus ← defaultFieldAs obj "status" .draft
  let summary? : Option String ← optionalFieldAs obj "summary"
  let tags : Array String ← defaultFieldAs obj "tags" #[]
  let authors : Array String ← defaultFieldAs obj "authors" #[]
  let createdAt? : Option Timestamp ← optionalFieldAs obj "createdAt"
  let updatedAt? : Option Timestamp ← optionalFieldAs obj "updatedAt"
  let relationships : Array Relationship ←
    match optionalField obj "relationships" with
    | some value => parseRelationshipArray value
    | none => pure #[]
  let leanRefs : Array LeanDeclRef ←
    match optionalField obj "leanRefs" with
    | some value => parseLeanDeclRefArray value
    | none => pure #[]
  return {
    schemaVersion := schemaVersion
    id := id
    title := title
    kind := kind
    status := status
    summary? := summary?
    tags := tags
    authors := authors
    createdAt? := createdAt?
    updatedAt? := updatedAt?
    relationships := relationships
    leanRefs := leanRefs
  }


def parseNodeMetadataText (text : String) : Except String NodeMetadata := do
  parseNodeMetadataJson (← parseJsonText text)


def readMarkdownFile (path : System.FilePath) : IO String := do
  return normalizeMarkdownForRead (← IO.FS.readFile path)


def writeMarkdownFile (path : System.FilePath) (body : String) : IO Unit := do
  IO.FS.writeFile path (normalizeMarkdownForWrite body)


def writeManifestFile (path : System.FilePath) (manifest : StorageManifest) : IO Unit := do
  IO.FS.writeFile path (renderStorageManifest manifest)


def writeMetadataFile (path : System.FilePath) (metadata : NodeMetadata) : IO Unit := do
  IO.FS.writeFile path (renderNodeMetadata metadata)

end Serialization

end AFTK.KnowledgeBase
