module

public import Lean
public import AFTK.Source

public section

open Lean

namespace AFTK

structure PacketAnchor where
  id : String
  kind? : Option String := none
  label? : Option String := none
  locator? : Option String := none
  deriving Inhabited, Repr, BEq

namespace PacketAnchor

def normalize (anchor : PacketAnchor) : Except String PacketAnchor := do
  let id ← nonEmptyText "packet anchor id" anchor.id
  let kind? ←
    match anchor.kind? with
    | some kind => some <$> nonEmptyText "packet anchor kind" kind
    | none => pure none
  let label? ←
    match anchor.label? with
    | some label => some <$> nonEmptyText "packet anchor label" label
    | none => pure none
  let locator? ←
    match anchor.locator? with
    | some locator => some <$> nonEmptyText "packet anchor locator" locator
    | none => pure none
  return {
    id,
    kind?,
    label?,
    locator?
  }

instance : ToJson PacketAnchor where
  toJson anchor :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[("id", .str anchor.id)]
      if let some kind := anchor.kind? then
        fields := fields.push ("kind", .str kind)
      if let some label := anchor.label? then
        fields := fields.push ("label", .str label)
      if let some locator := anchor.locator? then
        fields := fields.push ("locator", .str locator)
      return fields
    Json.mkObj fields.toList

instance : FromJson PacketAnchor where
  fromJson? json := do
    let id ← json.getObjValAs? String "id"
    let kind? ← json.getObjValAs? (Option String) "kind"
    let label? ← json.getObjValAs? (Option String) "label"
    let locator? ← json.getObjValAs? (Option String) "locator"
    normalize { id, kind?, label?, locator? }

end PacketAnchor

structure PacketProvenance where
  source : SourceId
  locator? : Option String := none
  anchors : Array String := #[]
  note? : Option String := none
  deriving Inhabited, Repr, BEq

namespace PacketProvenance

def normalize (prov : PacketProvenance) : Except String PacketProvenance := do
  let locator? ←
    match prov.locator? with
    | some locator => some <$> nonEmptyText "packet provenance locator" locator
    | none => pure none
  let anchors ← normalizeStringArray "packet provenance anchor" prov.anchors
  let note? ←
    match prov.note? with
    | some note => some <$> nonEmptyText "packet provenance note" note
    | none => pure none
  return {
    prov with
    locator?,
    anchors,
    note?
  }

instance : ToJson PacketProvenance where
  toJson prov :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[("source", toJson prov.source)]
      if let some locator := prov.locator? then
        fields := fields.push ("locator", .str locator)
      if !prov.anchors.isEmpty then
        fields := fields.push ("anchors", toJson prov.anchors)
      if let some note := prov.note? then
        fields := fields.push ("note", .str note)
      return fields
    Json.mkObj fields.toList

instance : FromJson PacketProvenance where
  fromJson? json := do
    let source ← json.getObjValAs? SourceId "source"
    let locator? ← json.getObjValAs? (Option String) "locator"
    let anchors? ← json.getObjValAs? (Option (Array String)) "anchors"
    let note? ← json.getObjValAs? (Option String) "note"
    normalize {
      source,
      locator?,
      anchors := anchors?.getD #[],
      note?
    }

end PacketProvenance

structure SourcePacket where
  id : PacketId
  source : SourceId
  title : String
  summary? : Option String := none
  anchors : Array PacketAnchor := #[]
  provenance : Array PacketProvenance := #[]
  tags : Array String := #[]
  deriving Inhabited, Repr, BEq

namespace SourcePacket

def normalize (packet : SourcePacket) : Except String SourcePacket := do
  let title ← nonEmptyText "packet title" packet.title
  let summary? ←
    match packet.summary? with
    | some summary => some <$> nonEmptyText "packet summary" summary
    | none => pure none
  let anchors ← packet.anchors.mapM PacketAnchor.normalize
  let provenance ← packet.provenance.mapM PacketProvenance.normalize
  let tags ← normalizeStringArray "packet tag" packet.tags
  return {
    packet with
    title,
    summary?,
    anchors,
    provenance,
    tags
  }

instance : ToJson SourcePacket where
  toJson packet :=
    let fields := Id.run do
      let mut fields : Array (String × Json) := #[("id", toJson packet.id), ("source", toJson packet.source), ("title", .str packet.title)]
      if let some summary := packet.summary? then
        fields := fields.push ("summary", .str summary)
      if !packet.anchors.isEmpty then
        fields := fields.push ("anchors", toJson packet.anchors)
      if !packet.provenance.isEmpty then
        fields := fields.push ("provenance", toJson packet.provenance)
      if !packet.tags.isEmpty then
        fields := fields.push ("tags", toJson packet.tags)
      return fields
    Json.mkObj fields.toList

instance : FromJson SourcePacket where
  fromJson? json := do
    let id ← json.getObjValAs? PacketId "id"
    let source ← json.getObjValAs? SourceId "source"
    let title ← json.getObjValAs? String "title"
    let summary? ← json.getObjValAs? (Option String) "summary"
    let anchors? ← json.getObjValAs? (Option (Array PacketAnchor)) "anchors"
    let provenance? ← json.getObjValAs? (Option (Array PacketProvenance)) "provenance"
    let tags? ← json.getObjValAs? (Option (Array String)) "tags"
    normalize {
      id,
      source,
      title,
      summary?,
      anchors := anchors?.getD #[],
      provenance := provenance?.getD #[],
      tags := tags?.getD #[]
    }

/-- Validate invariants local to a packet record. -/
def validate (packet : SourcePacket) : Except String Unit := do
  let normalized ← normalize packet
  let mut anchorIds : Std.HashSet String := {}
  for anchor in normalized.anchors do
    if anchorIds.contains anchor.id then
      throw s!"duplicate packet anchor id `{anchor.id}`"
    anchorIds := anchorIds.insert anchor.id

/-- Render a concise human-readable block. -/
def renderSummary (packet : SourcePacket) : String :=
  let tagPart :=
    if packet.tags.isEmpty then "(none)" else ", ".intercalate packet.tags.toList
  let anchorPart :=
    if packet.anchors.isEmpty then "(none)"
    else ", ".intercalate <| packet.anchors.toList.map (·.id)
  let provenancePart :=
    if packet.provenance.isEmpty then "0" else toString packet.provenance.size
  "\n".intercalate <| [
    s!"id: {packet.id}",
    s!"source: {packet.source}",
    s!"title: {packet.title}",
    s!"anchors: {anchorPart}",
    s!"provenance: {provenancePart}",
    s!"tags: {tagPart}"
  ] ++
  (match packet.summary? with | some summary => [s!"summary: {summary}"] | none => [])

end SourcePacket

def loadPacketRecordFromFile (path : System.FilePath) : IO (Except String SourcePacket) := do
  match ← readJsonFile "packet record" path with
  | .error err =>
    return .error err
  | .ok json =>
    match fromJson? (α := SourcePacket) json with
    | .ok packet =>
      return .ok packet
    | .error err =>
      return .error s!"invalid packet record `{path}`: {err}"

def loadSourcePacket (root : System.FilePath) (id : PacketId) : IO (Except String SourcePacket) :=
  loadPacketRecordFromFile (id.jsonPath root)

def readPacketBody (root : System.FilePath) (id : PacketId) : IO (Except String String) :=
  readTextFile "packet body" (id.bodyPath root)

def saveSourcePacket
    (root : System.FilePath)
    (packet : SourcePacket)
    (body : String) : IO (Except String (System.FilePath × System.FilePath)) := do
  match packet.validate with
  | .error err =>
    return .error err
  | .ok () =>
    let body ←
      match nonEmptyText "packet body" body with
      | .ok body => pure body
      | .error err => return .error err
    let jsonPath := packet.id.jsonPath root
    let bodyPath := packet.id.bodyPath root
    try
      writeJsonAtomic jsonPath (toJson packet)
      writeFileAtomic bodyPath (body ++ if body.endsWith "\n" then "" else "\n")
      return .ok (jsonPath, bodyPath)
    catch _ =>
      return .error s!"unable to write packet `{packet.id}`"

end AFTK
