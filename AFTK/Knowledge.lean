module

public import Lean
public import AFTK.Packet

public section

open Lean

namespace AFTK

inductive KnowledgeBasis where
  | sourceBacked
  | derived
  deriving Inhabited, Repr, BEq

namespace KnowledgeBasis

def encoded : KnowledgeBasis → String
  | .sourceBacked => "source_backed"
  | .derived => "derived"

instance : ToString KnowledgeBasis := ⟨encoded⟩

instance : ToJson KnowledgeBasis where
  toJson basis := .str (toString basis)

instance : FromJson KnowledgeBasis where
  fromJson?
    | .str "source_backed" => .ok .sourceBacked
    | .str "derived" => .ok .derived
    | .str raw => .error s!"invalid knowledge basis `{raw}`"
    | _ => .error "expected knowledge basis string"

end KnowledgeBasis

inductive KnowledgeKind where
  | definition
  | theoremStatement
  | proofSketch
  | notation
  | example
  | counterexample
  | dependencyHint
  | planNote
  | formalizationOutcome
  | other
  deriving Inhabited, Repr, BEq

namespace KnowledgeKind

def encoded : KnowledgeKind → String
  | .definition => "definition"
  | .theoremStatement => "theorem_statement"
  | .proofSketch => "proof_sketch"
  | .notation => "notation"
  | .example => "example"
  | .counterexample => "counterexample"
  | .dependencyHint => "dependency_hint"
  | .planNote => "plan_note"
  | .formalizationOutcome => "formalization_outcome"
  | .other => "other"

instance : ToString KnowledgeKind := ⟨encoded⟩

instance : ToJson KnowledgeKind where
  toJson kind := .str (toString kind)

instance : FromJson KnowledgeKind where
  fromJson?
    | .str "definition" => .ok .definition
    | .str "theorem_statement" => .ok .theoremStatement
    | .str "proof_sketch" => .ok .proofSketch
    | .str "notation" => .ok .notation
    | .str "example" => .ok .example
    | .str "counterexample" => .ok .counterexample
    | .str "dependency_hint" => .ok .dependencyHint
    | .str "plan_note" => .ok .planNote
    | .str "formalization_outcome" => .ok .formalizationOutcome
    | .str "other" => .ok .other
    | .str raw => .error s!"invalid knowledge kind `{raw}`"
    | _ => .error "expected knowledge kind string"

end KnowledgeKind

structure ProvenanceRef where
  targetId : String
  targetKind : ProvenanceTargetKind
  anchors : Array String := #[]
  locator? : Option String := none
  note? : Option String := none
  quote? : Option String := none
  deriving Inhabited, Repr, BEq

namespace ProvenanceRef

def normalize (ref : ProvenanceRef) : Except String ProvenanceRef := do
  let targetId ← nonEmptyText "provenance target id" ref.targetId
  let _ ← validateTargetIdForKind ref.targetKind targetId
  let anchors ← normalizeStringArray "provenance anchor" ref.anchors
  let locator? ←
    match ref.locator? with
    | some locator => some <$> nonEmptyText "provenance locator" locator
    | none => pure none
  let note? ←
    match ref.note? with
    | some note => some <$> nonEmptyText "provenance note" note
    | none => pure none
  let quote? ←
    match ref.quote? with
    | some quote => some <$> nonEmptyText "provenance quote" quote
    | none => pure none
  return {
    targetId,
    targetKind := ref.targetKind,
    anchors,
    locator?,
    note?,
    quote?
  }

instance : ToJson ProvenanceRef where
  toJson ref :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[("targetId", .str ref.targetId), ("targetKind", toJson ref.targetKind)]
      if !ref.anchors.isEmpty then
        fields := fields.push ("anchors", toJson ref.anchors)
      if let some locator := ref.locator? then
        fields := fields.push ("locator", .str locator)
      if let some note := ref.note? then
        fields := fields.push ("note", .str note)
      if let some quote := ref.quote? then
        fields := fields.push ("quote", .str quote)
      return fields
    Json.mkObj fields.toList

instance : FromJson ProvenanceRef where
  fromJson? json := do
    let targetId ← json.getObjValAs? String "targetId"
    let targetKind ← json.getObjValAs? ProvenanceTargetKind "targetKind"
    let anchors? ← json.getObjValAs? (Option (Array String)) "anchors"
    let locator? ← json.getObjValAs? (Option String) "locator"
    let note? ← json.getObjValAs? (Option String) "note"
    let quote? ← json.getObjValAs? (Option String) "quote"
    normalize {
      targetId,
      targetKind,
      anchors := anchors?.getD #[],
      locator?,
      note?,
      quote?
    }

end ProvenanceRef

structure KnowledgeLink where
  relation : String
  target : KnowledgeId
  deriving Inhabited, Repr, BEq

namespace KnowledgeLink

def normalize (link : KnowledgeLink) : Except String KnowledgeLink := do
  return {
    relation := ← nonEmptyText "knowledge link relation" link.relation,
    target := link.target
  }

instance : ToJson KnowledgeLink where
  toJson link :=
    Json.mkObj [
      ("relation", .str link.relation),
      ("target", toJson link.target)
    ]

instance : FromJson KnowledgeLink where
  fromJson? json := do
    let relation ← json.getObjValAs? String "relation"
    let target ← json.getObjValAs? KnowledgeId "target"
    normalize { relation, target }

end KnowledgeLink

structure KnowledgeEntry where
  id : KnowledgeId
  kind : KnowledgeKind
  basis : KnowledgeBasis
  title : String
  summary? : Option String := none
  packetRefs : Array PacketId := #[]
  sourceRefs : Array SourceId := #[]
  scaffoldRefs : Array Informalize.LocationId := #[]
  provenance : Array ProvenanceRef := #[]
  links : Array KnowledgeLink := #[]
  tags : Array String := #[]
  deriving Inhabited, Repr, BEq

namespace KnowledgeEntry

def normalize (entry : KnowledgeEntry) : Except String KnowledgeEntry := do
  let title ← nonEmptyText "knowledge title" entry.title
  let summary? ←
    match entry.summary? with
    | some summary => some <$> nonEmptyText "knowledge summary" summary
    | none => pure none
  let packetRefs := dedupePreservingOrder entry.packetRefs
  let sourceRefs := dedupePreservingOrder entry.sourceRefs
  let scaffoldRefs := dedupePreservingOrder entry.scaffoldRefs
  let provenance ← entry.provenance.mapM ProvenanceRef.normalize
  let links ← entry.links.mapM KnowledgeLink.normalize
  let tags ← normalizeStringArray "knowledge tag" entry.tags
  return {
    entry with
    title,
    summary?,
    packetRefs,
    sourceRefs,
    scaffoldRefs,
    provenance,
    links,
    tags
  }

instance : ToJson KnowledgeEntry where
  toJson entry :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[("id", toJson entry.id), ("kind", toJson entry.kind), ("basis", toJson entry.basis), ("title", .str entry.title)]
      if let some summary := entry.summary? then
        fields := fields.push ("summary", .str summary)
      if !entry.packetRefs.isEmpty then
        fields := fields.push ("packetRefs", toJson entry.packetRefs)
      if !entry.sourceRefs.isEmpty then
        fields := fields.push ("sourceRefs", toJson entry.sourceRefs)
      if !entry.scaffoldRefs.isEmpty then
        fields := fields.push ("scaffoldRefs", toJson entry.scaffoldRefs)
      if !entry.provenance.isEmpty then
        fields := fields.push ("provenance", toJson entry.provenance)
      if !entry.links.isEmpty then
        fields := fields.push ("links", toJson entry.links)
      if !entry.tags.isEmpty then
        fields := fields.push ("tags", toJson entry.tags)
      return fields
    Json.mkObj fields.toList

instance : FromJson KnowledgeEntry where
  fromJson? json := do
    let id ← json.getObjValAs? KnowledgeId "id"
    let kind ← json.getObjValAs? KnowledgeKind "kind"
    let basis ← json.getObjValAs? KnowledgeBasis "basis"
    let title ← json.getObjValAs? String "title"
    let summary? ← json.getObjValAs? (Option String) "summary"
    let packetRefs? ← json.getObjValAs? (Option (Array PacketId)) "packetRefs"
    let sourceRefs? ← json.getObjValAs? (Option (Array SourceId)) "sourceRefs"
    let scaffoldRefs? ← json.getObjValAs? (Option (Array Informalize.LocationId)) "scaffoldRefs"
    let provenance? ← json.getObjValAs? (Option (Array ProvenanceRef)) "provenance"
    let links? ← json.getObjValAs? (Option (Array KnowledgeLink)) "links"
    let tags? ← json.getObjValAs? (Option (Array String)) "tags"
    normalize {
      id,
      kind,
      basis,
      title,
      summary?,
      packetRefs := packetRefs?.getD #[],
      sourceRefs := sourceRefs?.getD #[],
      scaffoldRefs := scaffoldRefs?.getD #[],
      provenance := provenance?.getD #[],
      links := links?.getD #[],
      tags := tags?.getD #[]
    }

private def hasSourceOrPacketSupport (entry : KnowledgeEntry) : Bool :=
  !entry.sourceRefs.isEmpty || !entry.packetRefs.isEmpty ||
    entry.provenance.any fun prov =>
      prov.targetKind == .source || prov.targetKind == .packet

/-- Validate invariants local to a knowledge record. -/
def validate (entry : KnowledgeEntry) : Except String Unit := do
  let normalized ← normalize entry
  let mut linkPairs : Std.HashSet (String × String) := {}
  for link in normalized.links do
    let key := (link.relation, link.target.raw)
    if linkPairs.contains key then
      throw s!"duplicate knowledge link `{link.relation}` -> `{link.target}`"
    linkPairs := linkPairs.insert key
  if normalized.basis == .sourceBacked && !hasSourceOrPacketSupport normalized then
    throw "source-backed knowledge must reference at least one source or packet"

/-- Render a concise human-readable block. -/
def renderSummary (entry : KnowledgeEntry) : String :=
  let tagPart := if entry.tags.isEmpty then "(none)" else ", ".intercalate entry.tags.toList
  let sourcePart := if entry.sourceRefs.isEmpty then "(none)" else ", ".intercalate (entry.sourceRefs.toList.map toString)
  let packetPart := if entry.packetRefs.isEmpty then "(none)" else ", ".intercalate (entry.packetRefs.toList.map toString)
  let scaffoldPart := if entry.scaffoldRefs.isEmpty then "(none)" else ", ".intercalate (entry.scaffoldRefs.toList.map toString)
  "\n".intercalate <| [
    s!"id: {entry.id}",
    s!"kind: {entry.kind}",
    s!"basis: {entry.basis}",
    s!"title: {entry.title}",
    s!"sources: {sourcePart}",
    s!"packets: {packetPart}",
    s!"scaffold-refs: {scaffoldPart}",
    s!"provenance: {entry.provenance.size}",
    s!"links: {entry.links.size}",
    s!"tags: {tagPart}"
  ] ++
  (match entry.summary? with | some summary => [s!"summary: {summary}"] | none => [])

end KnowledgeEntry

def loadKnowledgeEntryFromFile (path : System.FilePath) : IO (Except String KnowledgeEntry) := do
  match ← readJsonFile "knowledge record" path with
  | .error err =>
    return .error err
  | .ok json =>
    match fromJson? (α := KnowledgeEntry) json with
    | .ok entry =>
      return .ok entry
    | .error err =>
      return .error s!"invalid knowledge record `{path}`: {err}"

def loadKnowledgeEntry (root : System.FilePath) (id : KnowledgeId) : IO (Except String KnowledgeEntry) :=
  loadKnowledgeEntryFromFile (id.jsonPath root)

def readKnowledgeBody (root : System.FilePath) (id : KnowledgeId) : IO (Except String String) :=
  readTextFile "knowledge body" (id.bodyPath root)

def saveKnowledgeEntry
    (root : System.FilePath)
    (entry : KnowledgeEntry)
    (body : String) : IO (Except String (System.FilePath × System.FilePath)) := do
  match entry.validate with
  | .error err =>
    return .error err
  | .ok () =>
    let body ←
      match nonEmptyText "knowledge body" body with
      | .ok body => pure body
      | .error err => return .error err
    let jsonPath := entry.id.jsonPath root
    let bodyPath := entry.id.bodyPath root
    try
      writeJsonAtomic jsonPath (toJson entry)
      writeFileAtomic bodyPath (body ++ if body.endsWith "\n" then "" else "\n")
      return .ok (jsonPath, bodyPath)
    catch _ =>
      return .error s!"unable to write knowledge entry `{entry.id}`"

end AFTK
