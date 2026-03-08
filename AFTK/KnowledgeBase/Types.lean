module

public import Lean.Data.Json.FromToJson
public import Std.Time.DateTime

public section


namespace AFTK.KnowledgeBase

open Lean

abbrev Markdown := String

def defaultSchemaVersion : Nat := 1

def defaultManifestKind : String := "aftk-knowledge-base"
def defaultNodesDirName : String := "nodes"
def defaultInternalDirName : String := ".aftk"
def defaultKnowledgeBaseRoot : System.FilePath := "knowledgebase"

structure KnowledgeBaseError where
  code : String
  message : String
  exitCode : UInt8 := 1
  deriving Repr, Inhabited

instance : ToString KnowledgeBaseError where
  toString err := s!"{err.code}: {err.message}"

namespace KnowledgeBaseError

def generic (code message : String) (exitCode : UInt8 := 1) : KnowledgeBaseError :=
  { code, message, exitCode }

def usage (message : String) : KnowledgeBaseError :=
  generic "usage.invalid" message 2

def notFound (code message : String) : KnowledgeBaseError :=
  generic code message 3

def validation (code message : String) : KnowledgeBaseError :=
  generic code message 4

def conflict (code message : String) : KnowledgeBaseError :=
  generic code message 5

end KnowledgeBaseError

abbrev KBIO := EIO KnowledgeBaseError

structure NodeId where
  value : String
  deriving Repr, DecidableEq, Inhabited, BEq, Hashable

instance : ToString NodeId where
  toString id := id.value

instance : Ord NodeId where
  compare a b := compare a.value b.value

namespace NodeId

private def isAsciiLower (c : Char) : Bool :=
  'a' ≤ c && c ≤ 'z'

private def isDigit (c : Char) : Bool :=
  '0' ≤ c && c ≤ '9'

private def isSegmentTail (c : Char) : Bool :=
  isAsciiLower c || isDigit c || c == '_'

private def validateSegment (segment : String) : Except String Unit := do
  if segment.isEmpty then
    throw "node id segments must be nonempty"
  if segment == "." || segment == ".." then
    throw "node id segments may not be '.' or '..'"
  let chars := segment.toList
  let some head := chars.head?
    | throw "node id segments must be nonempty"
  unless isAsciiLower head do
    throw s!"node id segment '{segment}' must start with a lowercase ASCII letter"
  for c in chars.tail do
    unless isSegmentTail c do
      throw s!"node id segment '{segment}' contains invalid character '{c}'"

private def containsForbiddenChars (s : String) : Bool :=
  s.toList.any fun c => c == '/' || c == '\\' || c.isWhitespace

private def splitSegments (s : String) : List String :=
  s.splitOn "."


def validateString (s : String) : Except String NodeId := do
  if s.isEmpty then
    throw "node id must be nonempty"
  if s.startsWith "." || s.endsWith "." then
    throw "node id may not start or end with '.'"
  if containsForbiddenChars s then
    throw "node id may not contain path separators or whitespace"
  let segments := splitSegments s
  if segments.isEmpty then
    throw "node id must contain at least one segment"
  for segment in segments do
    validateSegment segment
  return ⟨s⟩


def ofString? (s : String) : Except String NodeId :=
  validateString s


def segments (id : NodeId) : List String :=
  splitSegments id.value


def startsWithSegmentPrefix (id : NodeId) (pref : String) : Bool :=
  id.value == pref || id.value.startsWith (pref ++ ".")

end NodeId

instance : ToJson NodeId where
  toJson id := Json.str id.value

instance : FromJson NodeId where
  fromJson? j := do
    let s ← Json.getStr? j
    NodeId.ofString? s

structure Timestamp where
  value : String
  deriving Repr, DecidableEq, Inhabited, BEq, Hashable

instance : ToString Timestamp where
  toString ts := ts.value

namespace Timestamp

private def substring (s : String) (start stop : Nat) : String :=
  String.ofList <| (s.toList.drop start).take (stop - start)

private def fixedAt? (s : String) (idx : Nat) (expected : Char) : Bool :=
  substring s idx (idx + 1) == toString expected

private def parseNatSlice? (s : String) (start stop : Nat) : Option Nat :=
  (substring s start stop).toNat?

private def leftPad (width : Nat) (s : String) : String :=
  if s.length >= width then s else String.ofList (List.replicate (width - s.length) '0') ++ s

private def asNatString (n : Int) : String :=
  toString n

private def validateRange (label : String) (n lower upper : Nat) : Except String Unit := do
  unless lower ≤ n && n ≤ upper do
    throw s!"timestamp {label} is out of range"


def validateString (s : String) : Except String Timestamp := do
  unless s.length == 20 do
    throw "timestamp must have the form YYYY-MM-DDTHH:MM:SSZ"
  unless fixedAt? s 4 '-' && fixedAt? s 7 '-' && fixedAt? s 10 'T' &&
      fixedAt? s 13 ':' && fixedAt? s 16 ':' && fixedAt? s 19 'Z' do
    throw "timestamp must have the form YYYY-MM-DDTHH:MM:SSZ"
  let some year := parseNatSlice? s 0 4 | throw "timestamp year must be numeric"
  let some month := parseNatSlice? s 5 7 | throw "timestamp month must be numeric"
  let some day := parseNatSlice? s 8 10 | throw "timestamp day must be numeric"
  let some hour := parseNatSlice? s 11 13 | throw "timestamp hour must be numeric"
  let some minute := parseNatSlice? s 14 16 | throw "timestamp minute must be numeric"
  let some second := parseNatSlice? s 17 19 | throw "timestamp second must be numeric"
  unless year > 0 do
    throw "timestamp year must be positive"
  validateRange "month" month 1 12
  validateRange "day" day 1 31
  validateRange "hour" hour 0 23
  validateRange "minute" minute 0 59
  validateRange "second" second 0 59
  return ⟨s⟩


def ofString? (s : String) : Except String Timestamp :=
  validateString s


def now : IO Timestamp := do
  let ts ← Std.Time.Timestamp.now
  let pdt := Std.Time.Timestamp.toPlainDateTimeAssumingUTC ts
  let year := leftPad 4 (asNatString pdt.date.year)
  let month := leftPad 2 (toString pdt.date.month.val)
  let day := leftPad 2 (toString pdt.date.day.val)
  let hour := leftPad 2 (toString pdt.time.hour.val)
  let minute := leftPad 2 (toString pdt.time.minute.val)
  let second := leftPad 2 (toString pdt.time.second.val)
  return ⟨s!"{year}-{month}-{day}T{hour}:{minute}:{second}Z"⟩

end Timestamp

instance : ToJson Timestamp where
  toJson ts := Json.str ts.value

instance : FromJson Timestamp where
  fromJson? j := do
    let s ← Json.getStr? j
    Timestamp.ofString? s

inductive NodeKind
  | note
  | definition
  | theorem
  | proofSketch
  | example
  | explanation
  | concept
  | documentation
  deriving Repr, DecidableEq, Inhabited, BEq

namespace NodeKind

def asString : NodeKind → String
  | .note => "note"
  | .definition => "definition"
  | .theorem => "theorem"
  | .proofSketch => "proofSketch"
  | .example => "example"
  | .explanation => "explanation"
  | .concept => "concept"
  | .documentation => "documentation"


def ofString? : String → Except String NodeKind
  | "note" => return .note
  | "definition" => return .definition
  | "theorem" => return .theorem
  | "proofSketch" => return .proofSketch
  | "example" => return .example
  | "explanation" => return .explanation
  | "concept" => return .concept
  | "documentation" => return .documentation
  | s => throw s!"unknown node kind '{s}'"

end NodeKind

instance : ToString NodeKind where
  toString := NodeKind.asString

instance : ToJson NodeKind where
  toJson kind := Json.str kind.asString

instance : FromJson NodeKind where
  fromJson? j := do
    let s ← Json.getStr? j
    NodeKind.ofString? s

inductive NodeStatus
  | draft
  | active
  | deprecated
  | archived
  deriving Repr, DecidableEq, Inhabited, BEq

namespace NodeStatus

def asString : NodeStatus → String
  | .draft => "draft"
  | .active => "active"
  | .deprecated => "deprecated"
  | .archived => "archived"


def ofString? : String → Except String NodeStatus
  | "draft" => return .draft
  | "active" => return .active
  | "deprecated" => return .deprecated
  | "archived" => return .archived
  | s => throw s!"unknown node status '{s}'"

end NodeStatus

instance : ToString NodeStatus where
  toString := NodeStatus.asString

instance : ToJson NodeStatus where
  toJson status := Json.str status.asString

instance : FromJson NodeStatus where
  fromJson? j := do
    let s ← Json.getStr? j
    NodeStatus.ofString? s

inductive RelationshipKind
  | relatedTo
  | dependsOn
  | elaborates
  | refines
  | exampleOf
  | hasExample
  | seeAlso
  deriving Repr, DecidableEq, Inhabited, BEq

namespace RelationshipKind

def asString : RelationshipKind → String
  | .relatedTo => "relatedTo"
  | .dependsOn => "dependsOn"
  | .elaborates => "elaborates"
  | .refines => "refines"
  | .exampleOf => "exampleOf"
  | .hasExample => "hasExample"
  | .seeAlso => "seeAlso"


def ofString? : String → Except String RelationshipKind
  | "relatedTo" => return .relatedTo
  | "dependsOn" => return .dependsOn
  | "elaborates" => return .elaborates
  | "refines" => return .refines
  | "exampleOf" => return .exampleOf
  | "hasExample" => return .hasExample
  | "seeAlso" => return .seeAlso
  | s => throw s!"unknown relationship kind '{s}'"

end RelationshipKind

instance : ToString RelationshipKind where
  toString := RelationshipKind.asString

instance : ToJson RelationshipKind where
  toJson kind := Json.str kind.asString

instance : FromJson RelationshipKind where
  fromJson? j := do
    let s ← Json.getStr? j
    RelationshipKind.ofString? s

structure Relationship where
  kind : RelationshipKind
  target : NodeId
  label? : Option String := none
  note? : Option String := none
  deriving Repr, DecidableEq, Inhabited

instance : ToJson Relationship where
  toJson rel :=
    Json.mkObj <|
      [ ("kind", toJson rel.kind)
      , ("target", toJson rel.target)
      ] ++ Json.opt "label" rel.label? ++ Json.opt "note" rel.note?

structure LeanDeclRef where
  module? : Option String := none
  declaration : String
  kind? : Option String := none
  deriving Repr, DecidableEq, Inhabited

instance : ToJson LeanDeclRef where
  toJson ref :=
    Json.mkObj <|
      Json.opt "module" ref.module? ++
      [ ("declaration", toJson ref.declaration) ] ++
      Json.opt "kind" ref.kind?

structure NodeMetadata where
  schemaVersion : Nat := defaultSchemaVersion
  id : NodeId
  title : String
  kind : NodeKind := .note
  status : NodeStatus := .draft
  summary? : Option String := none
  tags : Array String := #[]
  authors : Array String := #[]
  createdAt? : Option Timestamp := none
  updatedAt? : Option Timestamp := none
  relationships : Array Relationship := #[]
  leanRefs : Array LeanDeclRef := #[]
  deriving Repr, DecidableEq

namespace NodeMetadata

@[inline] def withUpdatedAt (metadata : NodeMetadata) (ts : Timestamp) : NodeMetadata :=
  { metadata with updatedAt? := some ts }

@[inline] def withId (metadata : NodeMetadata) (id : NodeId) : NodeMetadata :=
  { metadata with id := id }

@[inline] def hasTag (metadata : NodeMetadata) (tag : String) : Bool :=
  metadata.tags.contains tag

@[inline] def titleOrId (metadata : NodeMetadata) : String :=
  if metadata.title.trimAscii.isEmpty then metadata.id.value else metadata.title

end NodeMetadata

instance : ToJson NodeMetadata where
  toJson metadata :=
    Json.mkObj <|
      [ ("schemaVersion", toJson metadata.schemaVersion)
      , ("id", toJson metadata.id)
      , ("title", toJson metadata.title)
      ] ++
      (if metadata.kind != .note then [("kind", toJson metadata.kind)] else []) ++
      (if metadata.status != .draft then [("status", toJson metadata.status)] else []) ++
      Json.opt "summary" metadata.summary? ++
      (if metadata.tags.isEmpty then [] else [("tags", toJson metadata.tags)]) ++
      (if metadata.authors.isEmpty then [] else [("authors", toJson metadata.authors)]) ++
      Json.opt "createdAt" metadata.createdAt? ++
      Json.opt "updatedAt" metadata.updatedAt? ++
      (if metadata.relationships.isEmpty then [] else [("relationships", toJson metadata.relationships)]) ++
      (if metadata.leanRefs.isEmpty then [] else [("leanRefs", toJson metadata.leanRefs)])

structure Node where
  metadata : NodeMetadata
  body : Markdown
  deriving Repr, DecidableEq

instance : ToJson Node where
  toJson node := Json.mkObj [
    ("metadata", toJson node.metadata),
    ("body", toJson node.body)
  ]

structure NodePaths where
  markdownPath : System.FilePath
  metadataPath : System.FilePath
  deriving Repr, DecidableEq, Inhabited

instance : ToJson NodePaths where
  toJson paths := Json.mkObj [
    ("markdownPath", toJson paths.markdownPath),
    ("metadataPath", toJson paths.metadataPath)
  ]

structure StoredNode where
  node : Node
  paths : NodePaths
  deriving Repr, DecidableEq

instance : ToJson StoredNode where
  toJson stored := Json.mkObj [
    ("node", toJson stored.node),
    ("paths", toJson stored.paths)
  ]

structure DiscoveredNodeFiles where
  stem : System.FilePath
  markdownPath? : Option System.FilePath := none
  metadataPath? : Option System.FilePath := none
  deriving Repr, DecidableEq, Inhabited

instance : ToJson DiscoveredNodeFiles where
  toJson files :=
    Json.mkObj <|
      [ ("stem", toJson files.stem) ] ++
      Json.opt "markdownPath" files.markdownPath? ++
      Json.opt "metadataPath" files.metadataPath?

structure StorageManifest where
  schemaVersion : Nat := defaultSchemaVersion
  kind : String := defaultManifestKind
  nodesDir : String := defaultNodesDirName
  internalDir : String := defaultInternalDirName
  deriving Repr, DecidableEq, Inhabited

instance : ToJson StorageManifest where
  toJson manifest := Json.mkObj [
    ("schemaVersion", toJson manifest.schemaVersion),
    ("kind", toJson manifest.kind),
    ("nodesDir", toJson manifest.nodesDir),
    ("internalDir", toJson manifest.internalDir)
  ]

structure KnowledgeBaseStoragePaths where
  rootDir : System.FilePath
  manifestPath : System.FilePath
  nodesDir : System.FilePath
  internalDir : System.FilePath
  indexDir : System.FilePath
  cacheDir : System.FilePath
  tmpDir : System.FilePath
  deriving Repr, DecidableEq, Inhabited

instance : ToJson KnowledgeBaseStoragePaths where
  toJson paths := Json.mkObj [
    ("rootDir", toJson paths.rootDir),
    ("manifestPath", toJson paths.manifestPath),
    ("nodesDir", toJson paths.nodesDir),
    ("internalDir", toJson paths.internalDir),
    ("indexDir", toJson paths.indexDir),
    ("cacheDir", toJson paths.cacheDir),
    ("tmpDir", toJson paths.tmpDir)
  ]

end AFTK.KnowledgeBase
