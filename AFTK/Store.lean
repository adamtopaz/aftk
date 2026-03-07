module

public import Lean
public import Lean.Util.Path
public import AFTK.Knowledge

public section

open Lean

namespace AFTK

structure StoreManifest where
  schemaVersion : Nat := 1
  deriving Inhabited, Repr, BEq

namespace StoreManifest

instance : ToJson StoreManifest where
  toJson manifest := Json.mkObj [("schemaVersion", toJson manifest.schemaVersion)]

instance : FromJson StoreManifest where
  fromJson? json := do
    let schemaVersion? ← json.getObjValAs? (Option Nat) "schemaVersion"
    let manifest : StoreManifest := { schemaVersion := schemaVersion?.getD 1 }
    if manifest.schemaVersion != 1 then
      throw s!"unsupported store schemaVersion `{manifest.schemaVersion}`"
    return manifest

end StoreManifest

structure Store where
  root : System.FilePath
  manifest : StoreManifest
  deriving Inhabited, Repr

structure LoadedStoreData where
  store : Store
  sources : Array SourceRecord
  packets : Array SourcePacket
  knowledge : Array KnowledgeEntry
  deriving Inhabited, Repr

structure StoreStats where
  sourceCount : Nat
  packetCount : Nat
  knowledgeCount : Nat
  deriving Inhabited, Repr, BEq

namespace StoreStats

instance : ToJson StoreStats where
  toJson stats := Json.mkObj [
    ("sources", toJson stats.sourceCount),
    ("packets", toJson stats.packetCount),
    ("knowledge", toJson stats.knowledgeCount)
  ]

end StoreStats

def storeJsonPath (root : System.FilePath) : System.FilePath :=
  root / "store.json"

def defaultStoreRoot (cwd : System.FilePath) : System.FilePath :=
  cwd / "aftk-data"

private partial def discoverStoreRootFrom? (dir : System.FilePath) : IO (Option System.FilePath) := do
  let candidate := defaultStoreRoot dir
  if (← (storeJsonPath candidate).pathExists) then
    return some candidate
  match dir.parent with
  | some parent =>
    if parent.normalize == dir.normalize then
      return none
    discoverStoreRootFrom? parent
  | none =>
    return none

private def loadStoreManifest (root : System.FilePath) : IO (Except String StoreManifest) := do
  match ← readJsonFile "store manifest" (storeJsonPath root) with
  | .error err =>
    return .error err
  | .ok json =>
    match fromJson? (α := StoreManifest) json with
    | .ok manifest =>
      return .ok manifest
    | .error err =>
      return .error s!"invalid store manifest `{storeJsonPath root}`: {err}"

/-- Resolve a store root either from `--store` or by searching ancestor directories. -/
def resolveStoreRoot (override? : Option System.FilePath := none) : IO (Except String Store) := do
  let root ←
    match override? with
    | some root =>
      pure root
    | none =>
      match ← discoverStoreRootFrom? (← IO.currentDir) with
      | some root => pure root
      | none =>
        return .error "no AFTK knowledge store found (expected aftk-data/store.json in this directory or an ancestor)"
  match ← loadStoreManifest root with
  | .ok manifest =>
    return .ok { root, manifest }
  | .error err =>
    return .error err

/-- Initialize a new empty store at the given root. -/
def initStore (root : System.FilePath) : IO (Except String (System.FilePath × Bool)) := do
  let manifestPath := storeJsonPath root
  let existed ← manifestPath.pathExists
  if existed then
    return .ok (manifestPath, false)
  try
    IO.FS.createDirAll (root / "sources")
    IO.FS.createDirAll (root / "packets")
    IO.FS.createDirAll (root / "knowledge")
    writeJsonAtomic manifestPath (toJson ({ schemaVersion := 1 : StoreManifest }))
    return .ok (manifestPath, true)
  catch _ =>
    return .error s!"unable to initialize AFTK store at `{root}`"

private def scanJsonFiles (dir : System.FilePath) : IO (Array System.FilePath) := do
  if !(← dir.isDir) then
    return #[]
  return (← dir.walkDir).filter (·.extension == some "json")

private def loadAllSources (root : System.FilePath) : IO (Except String (Array SourceRecord)) := do
  let paths ← scanJsonFiles (root / "sources")
  let mut records : Array SourceRecord := #[]
  for path in paths.qsort (fun a b => toString a < toString b) do
    match ← loadSourceRecordFromFile path with
    | .ok record =>
      records := records.push record
    | .error err =>
      return .error err
  return .ok records

private def loadAllPackets (root : System.FilePath) : IO (Except String (Array SourcePacket)) := do
  let paths ← scanJsonFiles (root / "packets")
  let mut records : Array SourcePacket := #[]
  for path in paths.qsort (fun a b => toString a < toString b) do
    match ← loadPacketRecordFromFile path with
    | .ok record =>
      records := records.push record
    | .error err =>
      return .error err
  return .ok records

private def loadAllKnowledge (root : System.FilePath) : IO (Except String (Array KnowledgeEntry)) := do
  let paths ← scanJsonFiles (root / "knowledge")
  let mut records : Array KnowledgeEntry := #[]
  for path in paths.qsort (fun a b => toString a < toString b) do
    match ← loadKnowledgeEntryFromFile path with
    | .ok record =>
      records := records.push record
    | .error err =>
      return .error err
  return .ok records

/-- Load every record in the store. -/
def loadStoreData (store : Store) : IO (Except String LoadedStoreData) := do
  let sources ← loadAllSources store.root
  let packets ← loadAllPackets store.root
  let knowledge ← loadAllKnowledge store.root
  match sources, packets, knowledge with
  | .ok sources, .ok packets, .ok knowledge =>
    return .ok { store, sources, packets, knowledge }
  | .error err, _, _ =>
    return .error err
  | _, .error err, _ =>
    return .error err
  | _, _, .error err =>
    return .error err

def stats (data : LoadedStoreData) : StoreStats := {
  sourceCount := data.sources.size,
  packetCount := data.packets.size,
  knowledgeCount := data.knowledge.size
}

def hasSource (data : LoadedStoreData) (id : SourceId) : Bool :=
  data.sources.any (·.id == id)

def hasPacket (data : LoadedStoreData) (id : PacketId) : Bool :=
  data.packets.any (·.id == id)

def hasKnowledge (data : LoadedStoreData) (id : KnowledgeId) : Bool :=
  data.knowledge.any (·.id == id)

def findSource? (data : LoadedStoreData) (id : SourceId) : Option SourceRecord :=
  data.sources.find? (·.id == id)

def findPacket? (data : LoadedStoreData) (id : PacketId) : Option SourcePacket :=
  data.packets.find? (·.id == id)

def findKnowledge? (data : LoadedStoreData) (id : KnowledgeId) : Option KnowledgeEntry :=
  data.knowledge.find? (·.id == id)

private def validateUniqueIds [BEq α] [ToString α]
    (label : String) (ids : Array α) (issues : Array String) : Array String := Id.run do
  let mut seen : Array α := #[]
  let mut issues := issues
  for id in ids do
    if seen.contains id then
      issues := issues.push s!"duplicate {label} id `{id}`"
    else
      seen := seen.push id
  return issues

private def validatePureIssues (data : LoadedStoreData) : Array String := Id.run do
  let mut issues : Array String := #[]
  issues := validateUniqueIds "source" (data.sources.map (·.id)) issues
  issues := validateUniqueIds "packet" (data.packets.map (·.id)) issues
  issues := validateUniqueIds "knowledge" (data.knowledge.map (·.id)) issues

  for source in data.sources do
    match source.validate with
    | .error err =>
      issues := issues.push s!"source `{source.id}`: {err}"
    | .ok () =>
      pure ()

  for packet in data.packets do
    match packet.validate with
    | .error err =>
      issues := issues.push s!"packet `{packet.id}`: {err}"
    | .ok () =>
      pure ()
    if !hasSource data packet.source then
      issues := issues.push s!"packet `{packet.id}` references missing source `{packet.source}`"
    for prov in packet.provenance do
      if !hasSource data prov.source then
        issues := issues.push s!"packet `{packet.id}` provenance references missing source `{prov.source}`"

  for entry in data.knowledge do
    match entry.validate with
    | .error err =>
      issues := issues.push s!"knowledge `{entry.id}`: {err}"
    | .ok () =>
      pure ()
    for sourceId in entry.sourceRefs do
      if !hasSource data sourceId then
        issues := issues.push s!"knowledge `{entry.id}` references missing source `{sourceId}`"
    for packetId in entry.packetRefs do
      if !hasPacket data packetId then
        issues := issues.push s!"knowledge `{entry.id}` references missing packet `{packetId}`"
    for link in entry.links do
      if !hasKnowledge data link.target then
        issues := issues.push s!"knowledge `{entry.id}` has dangling link target `{link.target}`"
    for prov in entry.provenance do
      match prov.targetKind with
      | .source =>
        match SourceId.ofString prov.targetId with
        | .ok sourceId =>
          if !hasSource data sourceId then
            issues := issues.push s!"knowledge `{entry.id}` provenance references missing source `{sourceId}`"
        | .error err =>
          issues := issues.push s!"knowledge `{entry.id}` provenance: {err}"
      | .packet =>
        match PacketId.ofString prov.targetId with
        | .ok packetId =>
          if !hasPacket data packetId then
            issues := issues.push s!"knowledge `{entry.id}` provenance references missing packet `{packetId}`"
        | .error err =>
          issues := issues.push s!"knowledge `{entry.id}` provenance: {err}"
      | .knowledge =>
        match KnowledgeId.ofString prov.targetId with
        | .ok targetId =>
          if !hasKnowledge data targetId then
            issues := issues.push s!"knowledge `{entry.id}` provenance references missing knowledge `{targetId}`"
        | .error err =>
          issues := issues.push s!"knowledge `{entry.id}` provenance: {err}"
      | .scaffold =>
        match Informalize.LocationId.ofDottedString prov.targetId with
        | .ok _ => pure ()
        | .error err =>
          issues := issues.push s!"knowledge `{entry.id}` provenance: {err}"
  return issues

/-- Return structural validation issues for the whole store. -/
def validateStoreData (data : LoadedStoreData) : IO (Array String) := do
  let mut issues := validatePureIssues data
  for packet in data.packets do
    if !(← packet.id.bodyPath data.store.root |>.pathExists) then
      issues := issues.push s!"packet `{packet.id}` is missing body file `{packet.id.bodyPath data.store.root}`"
  for entry in data.knowledge do
    if !(← entry.id.bodyPath data.store.root |>.pathExists) then
      issues := issues.push s!"knowledge `{entry.id}` is missing body file `{entry.id.bodyPath data.store.root}`"
  return issues

def requireValidStoreData (data : LoadedStoreData) : IO (Except String LoadedStoreData) := do
  let issues ← validateStoreData data
  if issues.isEmpty then
    return .ok data
  else
    return .error <| String.intercalate "\n" issues.toList

def checkCanRemoveSource (data : LoadedStoreData) (id : SourceId) : Except String Unit := do
  for packet in data.packets do
    if packet.source == id || packet.provenance.any (·.source == id) then
      throw s!"cannot remove source `{id}` because packet `{packet.id}` still references it"
  for entry in data.knowledge do
    if entry.sourceRefs.contains id then
      throw s!"cannot remove source `{id}` because knowledge `{entry.id}` still references it"
    if entry.provenance.any fun prov => prov.targetKind == .source && prov.targetId == id.raw then
      throw s!"cannot remove source `{id}` because knowledge `{entry.id}` provenance still references it"


def checkCanRemovePacket (data : LoadedStoreData) (id : PacketId) : Except String Unit := do
  for entry in data.knowledge do
    if entry.packetRefs.contains id then
      throw s!"cannot remove packet `{id}` because knowledge `{entry.id}` still references it"
    if entry.provenance.any fun prov => prov.targetKind == .packet && prov.targetId == id.raw then
      throw s!"cannot remove packet `{id}` because knowledge `{entry.id}` provenance still references it"


def checkCanRemoveKnowledge (data : LoadedStoreData) (id : KnowledgeId) : Except String Unit := do
  for entry in data.knowledge do
    if entry.links.any (·.target == id) then
      throw s!"cannot remove knowledge `{id}` because knowledge `{entry.id}` still links to it"
    if entry.provenance.any fun prov => prov.targetKind == .knowledge && prov.targetId == id.raw then
      throw s!"cannot remove knowledge `{id}` because knowledge `{entry.id}` provenance still references it"

end AFTK
