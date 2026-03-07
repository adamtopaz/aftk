module

public import Lean
public import AFTK.Query

public section

open Lean

namespace AFTK.Cli

inductive StoreAction where
  | init
  | validate
  | stats
  deriving Inhabited, Repr, BEq

inductive SourceAction where
  | list
  | show
  | validate
  | register
  | update
  | remove
  deriving Inhabited, Repr, BEq

inductive PacketAction where
  | list
  | show
  | validate
  | ingest
  | update
  | remove
  deriving Inhabited, Repr, BEq

inductive KbAction where
  | list
  | show
  | validate
  | query
  | create
  | update
  | remove
  | addLink
  | removeLink
  | addTag
  | removeTag
  | addScaffoldRef
  | removeScaffoldRef
  deriving Inhabited, Repr, BEq

inductive CliCommand where
  | store (action : StoreAction)
  | source (action : SourceAction)
  | packet (action : PacketAction)
  | kb (action : KbAction)
  deriving Inhabited, Repr, BEq

inductive OutputMode where
  | plainText
  | jsonText
  deriving Inhabited, Repr, BEq

structure Config where
  command : CliCommand
  storeRoot? : Option System.FilePath := none
  outputMode : OutputMode := .plainText
  sourceId? : Option SourceId := none
  packetId? : Option PacketId := none
  knowledgeId? : Option KnowledgeId := none
  sourceKind? : Option SourceKind := none
  knowledgeKind? : Option KnowledgeKind := none
  knowledgeBasis? : Option KnowledgeBasis := none
  title? : Option String := none
  summary? : Option String := none
  bodyFile? : Option System.FilePath := none
  fromJson? : Option System.FilePath := none
  authors : Array String := #[]
  tags : Array String := #[]
  sourceRefs : Array SourceId := #[]
  packetRefs : Array PacketId := #[]
  scaffoldRefs : Array Informalize.LocationId := #[]
  anchorIds : Array String := #[]
  provAnchorIds : Array String := #[]
  provLocator? : Option String := none
  provNote? : Option String := none
  locatorPath? : Option String := none
  locatorUri? : Option String := none
  locatorNote? : Option String := none
  version? : Option String := none
  contentHash? : Option String := none
  license? : Option String := none
  note? : Option String := none
  relation? : Option String := none
  targetKnowledgeId? : Option KnowledgeId := none
  queryIdPrefix? : Option String := none
  queryTag? : Option String := none
  querySource? : Option SourceId := none
  queryPacket? : Option PacketId := none
  queryLocation? : Option Informalize.LocationId := none
  relatedTo? : Option KnowledgeId := none
  queryText? : Option String := none
  limit? : Option Nat := none
  deriving Inhabited, Repr

structure InvocationResult where
  exitCode : UInt32
  stdout : String := ""
  stderr : String := ""
  deriving Inhabited, Repr

inductive RenderedOutput where
  | plain (text : String)
  | json (value : Json)

namespace RenderedOutput

def render : RenderedOutput → String
  | .plain text => text
  | .json value => value.pretty

end RenderedOutput

def usage : String :=
  "\n".intercalate [
    "AFTK knowledge-base CLI",
    "",
    "Usage:",
    "  lake exe aftk <namespace> <command> [options]",
    "",
    "Namespaces:",
    "  store init | validate | stats",
    "  source list | show | validate | register | update | remove",
    "  packet list | show | validate | ingest | update | remove",
    "  kb list | show | validate | query | create | update | remove | add-link | remove-link | add-tag | remove-tag | add-scaffold-ref | remove-scaffold-ref",
    "",
    "Common options:",
    "  --store <Path>         Explicit store root (directory containing store.json)",
    "  --json                 Emit machine-readable JSON output",
    "",
    "Store commands:",
    "  lake exe aftk store init",
    "  lake exe aftk store validate",
    "  lake exe aftk store stats --json",
    "",
    "Source commands:",
    "  lake exe aftk source register --id src.paper.demo --kind paper --title \"Demo\" --path docs/demo.md",
    "  lake exe aftk source update --id src.paper.demo --from-json tmp/source.json",
    "  lake exe aftk source show --id src.paper.demo",
    "",
    "Packet commands:",
    "  lake exe aftk packet ingest --id pkt.paper.demo.excerpt --source src.paper.demo --title \"Excerpt\" --body-file tmp/excerpt.md --anchor theorem-1",
    "  lake exe aftk packet update --id pkt.paper.demo.excerpt --from-json tmp/packet.json --body-file tmp/excerpt.md",
    "",
    "Knowledge commands:",
    "  lake exe aftk kb create --id kb.demo.definition --kind definition --basis source_backed --title \"Definition\" --body-file tmp/body.md --source src.paper.demo",
    "  lake exe aftk kb query --source src.paper.demo --tag algebra --json",
    "  lake exe aftk kb update --id kb.demo.definition --from-json tmp/kb.json --body-file tmp/body.md",
    "",
    "Important query filters:",
    "  --id-prefix <Prefix>   Prefix match on knowledge ids",
    "  --kind <Kind>          Source kind for `source register`; knowledge kind for `kb create/query`",
    "  --basis <Basis>        `source_backed` or `derived` for knowledge commands",
    "  --tag <Tag>            Repeatable for create/register; filter for `kb query`; single tag for add/remove-tag",
    "  --source <SourceId>    Packet owner, knowledge ref, or query filter",
    "  --packet <PacketId>    Knowledge ref or query filter",
    "  --location <Id>        Knowledge scaffold ref or query filter",
    "  --related-to <KbId>    `kb query` link filter",
    "  --text <Text>          Case-insensitive substring query over id/title/summary/body",
    "  --limit <Nat>          Bound query result count"
  ]

private def parseSourceId (raw : String) : Except String SourceId :=
  SourceId.ofString raw

private def parsePacketId (raw : String) : Except String PacketId :=
  PacketId.ofString raw

private def parseKnowledgeId (raw : String) : Except String KnowledgeId :=
  KnowledgeId.ofString raw

private def parseLocationId (raw : String) : Except String Informalize.LocationId :=
  Informalize.LocationId.ofDottedString raw

private def parseSourceKind (raw : String) : Except String SourceKind :=
  fromJson? (.str (AFTK.normalizeText raw))

private def parseKnowledgeKind (raw : String) : Except String KnowledgeKind :=
  fromJson? (.str (AFTK.normalizeText raw))

private def parseKnowledgeBasis (raw : String) : Except String KnowledgeBasis :=
  fromJson? (.str (AFTK.normalizeText raw))

private def parseNatOption (label raw : String) : Except String Nat := do
  match raw.toNat? with
  | some n => pure n
  | none => throw s!"invalid {label} `{raw}`"

private def parseText (label raw : String) : Except String String :=
  AFTK.nonEmptyText label raw

private def parseStoreAction (raw : String) : Except String StoreAction :=
  match raw with
  | "init" => .ok .init
  | "validate" => .ok .validate
  | "stats" => .ok .stats
  | other => .error s!"unknown store command `{other}`"

private def parseSourceAction (raw : String) : Except String SourceAction :=
  match raw with
  | "list" => .ok .list
  | "show" => .ok .show
  | "validate" => .ok .validate
  | "register" => .ok .register
  | "update" => .ok .update
  | "remove" => .ok .remove
  | other => .error s!"unknown source command `{other}`"

private def parsePacketAction (raw : String) : Except String PacketAction :=
  match raw with
  | "list" => .ok .list
  | "show" => .ok .show
  | "validate" => .ok .validate
  | "ingest" => .ok .ingest
  | "update" => .ok .update
  | "remove" => .ok .remove
  | other => .error s!"unknown packet command `{other}`"

private def parseKbAction (raw : String) : Except String KbAction :=
  match raw with
  | "list" => .ok .list
  | "show" => .ok .show
  | "validate" => .ok .validate
  | "query" => .ok .query
  | "create" => .ok .create
  | "update" => .ok .update
  | "remove" => .ok .remove
  | "add-link" => .ok .addLink
  | "remove-link" => .ok .removeLink
  | "add-tag" => .ok .addTag
  | "remove-tag" => .ok .removeTag
  | "add-scaffold-ref" => .ok .addScaffoldRef
  | "remove-scaffold-ref" => .ok .removeScaffoldRef
  | other => .error s!"unknown kb command `{other}`"

private def parseTopLevelCommand (args : List String) : Except String (Option (Config × List String)) := do
  match args with
  | [] =>
    return none
  | "--help" :: _ | "-h" :: _ =>
    return none
  | "store" :: action :: rest =>
    return some ({ command := .store (← parseStoreAction action) }, rest)
  | "source" :: action :: rest =>
    return some ({ command := .source (← parseSourceAction action) }, rest)
  | "packet" :: action :: rest =>
    return some ({ command := .packet (← parsePacketAction action) }, rest)
  | "kb" :: action :: rest =>
    return some ({ command := .kb (← parseKbAction action) }, rest)
  | ns :: _ =>
    throw s!"unknown namespace `{ns}`"

private def currentSourceAction? (cfg : Config) : Option SourceAction :=
  match cfg.command with
  | .source action => some action
  | _ => none

private def currentPacketAction? (cfg : Config) : Option PacketAction :=
  match cfg.command with
  | .packet action => some action
  | _ => none

private def currentKbAction? (cfg : Config) : Option KbAction :=
  match cfg.command with
  | .kb action => some action
  | _ => none

private def parseKindOption (cfg : Config) (raw : String) : Except String Config := do
  match cfg.command with
  | .source .register =>
    return { cfg with sourceKind? := some (← parseSourceKind raw) }
  | .kb .create | .kb .query =>
    return { cfg with knowledgeKind? := some (← parseKnowledgeKind raw) }
  | _ =>
    throw "`--kind` is only valid for `source register`, `kb create`, or `kb query`"

private partial def parseOptions (cfg : Config) (args : List String) : Except String (Option Config) := do
  match args with
  | [] =>
    return some cfg
  | "--help" :: _ | "-h" :: _ =>
    return none
  | "--json" :: rest =>
    parseOptions { cfg with outputMode := .jsonText } rest
  | "--store" :: path :: rest =>
    parseOptions { cfg with storeRoot? := some (System.FilePath.mk path) } rest
  | "--store" :: [] =>
    throw "expected path after `--store`"
  | "--id" :: raw :: rest =>
    match cfg.command with
    | .source _ =>
      parseOptions { cfg with sourceId? := some (← parseSourceId raw) } rest
    | .packet _ =>
      parseOptions { cfg with packetId? := some (← parsePacketId raw) } rest
    | .kb _ =>
      parseOptions { cfg with knowledgeId? := some (← parseKnowledgeId raw) } rest
    | .store _ =>
      throw "`--id` is not valid for store commands"
  | "--id" :: [] =>
    throw "expected id after `--id`"
  | "--kind" :: raw :: rest =>
    parseOptions (← parseKindOption cfg raw) rest
  | "--kind" :: [] =>
    throw "expected value after `--kind`"
  | "--basis" :: raw :: rest =>
    match cfg.command with
    | .kb .create | .kb .query =>
      parseOptions { cfg with knowledgeBasis? := some (← parseKnowledgeBasis raw) } rest
    | _ =>
      throw "`--basis` is only valid for `kb create` or `kb query`"
  | "--basis" :: [] =>
    throw "expected value after `--basis`"
  | "--title" :: raw :: rest =>
    parseOptions { cfg with title? := some (← parseText "title" raw) } rest
  | "--title" :: [] =>
    throw "expected value after `--title`"
  | "--summary" :: raw :: rest =>
    parseOptions { cfg with summary? := some (← parseText "summary" raw) } rest
  | "--summary" :: [] =>
    throw "expected value after `--summary`"
  | "--body-file" :: raw :: rest =>
    parseOptions { cfg with bodyFile? := some (System.FilePath.mk raw) } rest
  | "--body-file" :: [] =>
    throw "expected path after `--body-file`"
  | "--from-json" :: raw :: rest =>
    parseOptions { cfg with fromJson? := some (System.FilePath.mk raw) } rest
  | "--from-json" :: [] =>
    throw "expected path after `--from-json`"
  | "--author" :: raw :: rest =>
    parseOptions { cfg with authors := cfg.authors.push (← parseText "author" raw) } rest
  | "--author" :: [] =>
    throw "expected value after `--author`"
  | "--tag" :: raw :: rest =>
    match cfg.command with
    | .kb .query =>
      parseOptions { cfg with queryTag? := some (← parseText "tag" raw) } rest
    | _ =>
      parseOptions { cfg with tags := cfg.tags.push (← parseText "tag" raw) } rest
  | "--tag" :: [] =>
    throw "expected value after `--tag`"
  | "--source" :: raw :: rest =>
    match cfg.command with
    | .packet .list =>
      parseOptions { cfg with querySource? := some (← parseSourceId raw) } rest
    | .packet .ingest =>
      parseOptions { cfg with sourceRefs := cfg.sourceRefs.push (← parseSourceId raw) } rest
    | .kb .create =>
      parseOptions { cfg with sourceRefs := cfg.sourceRefs.push (← parseSourceId raw) } rest
    | .kb .query =>
      parseOptions { cfg with querySource? := some (← parseSourceId raw) } rest
    | _ =>
      throw "`--source` is only valid for `packet list|ingest`, `kb create`, or `kb query`"
  | "--source" :: [] =>
    throw "expected source id after `--source`"
  | "--packet" :: raw :: rest =>
    match cfg.command with
    | .kb .create =>
      parseOptions { cfg with packetRefs := cfg.packetRefs.push (← parsePacketId raw) } rest
    | .kb .query =>
      parseOptions { cfg with queryPacket? := some (← parsePacketId raw) } rest
    | _ =>
      throw "`--packet` is only valid for `kb create` or `kb query`"
  | "--packet" :: [] =>
    throw "expected packet id after `--packet`"
  | "--location" :: raw :: rest =>
    match cfg.command with
    | .kb .create | .kb .addScaffoldRef | .kb .removeScaffoldRef =>
      parseOptions { cfg with scaffoldRefs := cfg.scaffoldRefs.push (← parseLocationId raw) } rest
    | .kb .query =>
      parseOptions { cfg with queryLocation? := some (← parseLocationId raw) } rest
    | _ =>
      throw "`--location` is only valid for `kb` commands"
  | "--location" :: [] =>
    throw "expected location id after `--location`"
  | "--anchor" :: raw :: rest =>
    parseOptions { cfg with anchorIds := cfg.anchorIds.push (← parseText "anchor" raw) } rest
  | "--anchor" :: [] =>
    throw "expected anchor after `--anchor`"
  | "--prov-anchor" :: raw :: rest =>
    parseOptions { cfg with provAnchorIds := cfg.provAnchorIds.push (← parseText "provenance anchor" raw) } rest
  | "--prov-anchor" :: [] =>
    throw "expected anchor after `--prov-anchor`"
  | "--prov-locator" :: raw :: rest =>
    parseOptions { cfg with provLocator? := some (← parseText "provenance locator" raw) } rest
  | "--prov-locator" :: [] =>
    throw "expected locator after `--prov-locator`"
  | "--prov-note" :: raw :: rest =>
    parseOptions { cfg with provNote? := some (← parseText "provenance note" raw) } rest
  | "--prov-note" :: [] =>
    throw "expected note after `--prov-note`"
  | "--path" :: raw :: rest =>
    parseOptions { cfg with locatorPath? := some (← parseText "path" raw) } rest
  | "--path" :: [] =>
    throw "expected value after `--path`"
  | "--uri" :: raw :: rest =>
    parseOptions { cfg with locatorUri? := some (← parseText "uri" raw) } rest
  | "--uri" :: [] =>
    throw "expected value after `--uri`"
  | "--locator-note" :: raw :: rest =>
    parseOptions { cfg with locatorNote? := some (← parseText "locator note" raw) } rest
  | "--locator-note" :: [] =>
    throw "expected value after `--locator-note`"
  | "--version" :: raw :: rest =>
    parseOptions { cfg with version? := some (← parseText "version" raw) } rest
  | "--version" :: [] =>
    throw "expected value after `--version`"
  | "--content-hash" :: raw :: rest =>
    parseOptions { cfg with contentHash? := some (← parseText "content hash" raw) } rest
  | "--content-hash" :: [] =>
    throw "expected value after `--content-hash`"
  | "--license" :: raw :: rest =>
    parseOptions { cfg with license? := some (← parseText "license" raw) } rest
  | "--license" :: [] =>
    throw "expected value after `--license`"
  | "--note" :: raw :: rest =>
    parseOptions { cfg with note? := some (← parseText "note" raw) } rest
  | "--note" :: [] =>
    throw "expected value after `--note`"
  | "--relation" :: raw :: rest =>
    parseOptions { cfg with relation? := some (← parseText "relation" raw) } rest
  | "--relation" :: [] =>
    throw "expected value after `--relation`"
  | "--target" :: raw :: rest =>
    parseOptions { cfg with targetKnowledgeId? := some (← parseKnowledgeId raw) } rest
  | "--target" :: [] =>
    throw "expected value after `--target`"
  | "--id-prefix" :: raw :: rest =>
    parseOptions { cfg with queryIdPrefix? := some (← parseText "id prefix" raw) } rest
  | "--id-prefix" :: [] =>
    throw "expected value after `--id-prefix`"
  | "--related-to" :: raw :: rest =>
    parseOptions { cfg with relatedTo? := some (← parseKnowledgeId raw) } rest
  | "--related-to" :: [] =>
    throw "expected value after `--related-to`"
  | "--text" :: raw :: rest =>
    parseOptions { cfg with queryText? := some (← parseText "text query" raw) } rest
  | "--text" :: [] =>
    throw "expected value after `--text`"
  | "--limit" :: raw :: rest =>
    parseOptions { cfg with limit? := some (← parseNatOption "limit" raw) } rest
  | "--limit" :: [] =>
    throw "expected value after `--limit`"
  | other :: _ =>
    throw s!"unknown option `{other}`"

private def validateSingleLocatorChoice (cfg : Config) : Except String Unit := do
  let count := [cfg.locatorPath?, cfg.locatorUri?, cfg.locatorNote?].foldl (init := 0) fun acc opt => if opt.isSome then acc + 1 else acc
  if count == 0 then
    throw "expected one of `--path`, `--uri`, or `--locator-note`"
  if count > 1 then
    throw "`--path`, `--uri`, and `--locator-note` are mutually exclusive"

private def validateConfig (cfg : Config) : Except String Config := do
  match cfg.command with
  | .store .init | .store .validate | .store .stats => pure ()
  | .source .list => pure ()
  | .source .show | .source .validate | .source .remove | .source .update =>
    if cfg.sourceId?.isNone then
      throw "missing required option `--id <SourceId>`"
    if cfg.command == .source .update && cfg.fromJson?.isNone then
      throw "missing required option `--from-json <Path>` for `source update`"
  | .source .register =>
    if cfg.sourceId?.isNone then throw "missing required option `--id <SourceId>`"
    if cfg.sourceKind?.isNone then throw "missing required option `--kind <Kind>`"
    if cfg.title?.isNone then throw "missing required option `--title <Title>`"
    validateSingleLocatorChoice cfg
  | .packet .list => pure ()
  | .packet .show | .packet .validate | .packet .remove | .packet .update =>
    if cfg.packetId?.isNone then throw "missing required option `--id <PacketId>`"
    if cfg.command == .packet .update && cfg.fromJson?.isNone then
      throw "missing required option `--from-json <Path>` for `packet update`"
  | .packet .ingest =>
    if cfg.packetId?.isNone then throw "missing required option `--id <PacketId>`"
    if cfg.title?.isNone then throw "missing required option `--title <Title>`"
    if cfg.sourceRefs.size != 1 then throw "`packet ingest` requires exactly one `--source <SourceId>`"
    if cfg.bodyFile?.isNone then throw "missing required option `--body-file <Path>`"
  | .kb .list | .kb .query => pure ()
  | .kb .show | .kb .validate | .kb .remove | .kb .update =>
    if cfg.knowledgeId?.isNone then throw "missing required option `--id <KnowledgeId>`"
    if cfg.command == .kb .update && cfg.fromJson?.isNone then
      throw "missing required option `--from-json <Path>` for `kb update`"
  | .kb .create =>
    if cfg.knowledgeId?.isNone then throw "missing required option `--id <KnowledgeId>`"
    if cfg.knowledgeKind?.isNone then throw "missing required option `--kind <KnowledgeKind>`"
    if cfg.knowledgeBasis?.isNone then throw "missing required option `--basis <KnowledgeBasis>`"
    if cfg.title?.isNone then throw "missing required option `--title <Title>`"
    if cfg.bodyFile?.isNone then throw "missing required option `--body-file <Path>`"
  | .kb .addLink | .kb .removeLink =>
    if cfg.knowledgeId?.isNone then throw "missing required option `--id <KnowledgeId>`"
    if cfg.relation?.isNone then throw "missing required option `--relation <Relation>`"
    if cfg.targetKnowledgeId?.isNone then throw "missing required option `--target <KnowledgeId>`"
  | .kb .addTag | .kb .removeTag =>
    if cfg.knowledgeId?.isNone then throw "missing required option `--id <KnowledgeId>`"
    if cfg.tags.size != 1 then throw "expected exactly one `--tag <Tag>`"
  | .kb .addScaffoldRef | .kb .removeScaffoldRef =>
    if cfg.knowledgeId?.isNone then throw "missing required option `--id <KnowledgeId>`"
    if cfg.scaffoldRefs.size != 1 then throw "expected exactly one `--location <LocationId>`"
  return cfg

private def parseArgs (args : Array String) : Except String (Option Config) := do
  match ← parseTopLevelCommand args.toList with
  | none =>
    return none
  | some (cfg, rest) =>
    match ← parseOptions cfg rest with
    | none => return none
    | some cfg => return some (← validateConfig cfg)

private def resolveStoreOrError (cfg : Config) : IO Store := do
  match ← resolveStoreRoot cfg.storeRoot? with
  | .ok store =>
    pure store
  | .error err =>
    throw <| IO.userError err

private def loadStoreDataOrError (cfg : Config) : IO LoadedStoreData := do
  let store ← resolveStoreOrError cfg
  match ← loadStoreData store with
  | .ok data =>
    pure data
  | .error err =>
    throw <| IO.userError err

private def emit (cfg : Config) (text : String) (json : Json) : RenderedOutput :=
  match cfg.outputMode with
  | .plainText => .plain text
  | .jsonText => .json json

private def readBodyFileOrError (path : System.FilePath) : IO String := do
  match ← AFTK.readTextFile "body" path with
  | .ok body =>
    pure body
  | .error err =>
    throw <| IO.userError err

private def readJsonTypedOrError {α : Type} [FromJson α] (label : String) (path : System.FilePath) : IO α := do
  match ← AFTK.readJsonFile label path with
  | .error err =>
    throw <| IO.userError err
  | .ok json =>
    match fromJson? (α := α) json with
    | .ok value =>
      pure value
    | .error err =>
      throw <| IO.userError s!"invalid {label} `{path}`: {err}"

private def sourceLocatorFromConfig (cfg : Config) : Except String SourceLocator := do
  if let some path := cfg.locatorPath? then
    return { kind := .path, value := path }
  if let some uri := cfg.locatorUri? then
    return { kind := .uri, value := uri }
  if let some note := cfg.locatorNote? then
    return { kind := .note, value := note }
  throw "expected one of `--path`, `--uri`, or `--locator-note`"

private def autoKnowledgeProvenance (cfg : Config) : Array ProvenanceRef :=
  let sourceProv := cfg.sourceRefs.map fun source => ({ targetId := source.raw, targetKind := .source : ProvenanceRef })
  let packetProv := cfg.packetRefs.map fun packet => ({ targetId := packet.raw, targetKind := .packet : ProvenanceRef })
  sourceProv ++ packetProv

private def autoPacketProvenance (cfg : Config) (source : SourceId) : Array PacketProvenance :=
  #[{
    source,
    locator? := cfg.provLocator?,
    anchors := cfg.provAnchorIds,
    note? := cfg.provNote?
  }]

private def jsonWithBody (recordField : String) (record : Json) (bodyPath : System.FilePath) (body : String) : Json :=
  Json.mkObj [
    (recordField, record),
    ("bodyPath", .str (toString bodyPath)),
    ("body", .str body)
  ]

private def renderSourceList (sources : Array SourceRecord) : String :=
  let items := sources.qsort (fun a b => a.id.raw < b.id.raw)
  let lines := items.toList.map fun source => s!"- {source.id} ({source.kind}) — {source.title}"
  "\n".intercalate <| [s!"Sources ({items.size}):"] ++ lines

private def renderPacketList (packets : Array SourcePacket) : String :=
  let items := packets.qsort (fun a b => a.id.raw < b.id.raw)
  let lines := items.toList.map fun packet => s!"- {packet.id} ({packet.source}) — {packet.title}"
  "\n".intercalate <| [s!"Packets ({items.size}):"] ++ lines

private def renderKnowledgeList (entries : Array KnowledgeEntry) : String :=
  let items := entries.qsort (fun a b => a.id.raw < b.id.raw)
  let lines := items.toList.map fun entry => s!"- {entry.id} ({entry.kind}, {entry.basis}) — {entry.title}"
  "\n".intercalate <| [s!"Knowledge entries ({items.size}):"] ++ lines

private def ensureSourceExists (data : LoadedStoreData) (id : SourceId) : IO Unit := do
  unless hasSource data id do
    throw <| IO.userError s!"unknown source id `{id}`"

private def ensurePacketExists (data : LoadedStoreData) (id : PacketId) : IO Unit := do
  unless hasPacket data id do
    throw <| IO.userError s!"unknown packet id `{id}`"

private def ensureKnowledgeExists (data : LoadedStoreData) (id : KnowledgeId) : IO Unit := do
  unless hasKnowledge data id do
    throw <| IO.userError s!"unknown knowledge id `{id}`"

private def sourceShowJson (record : SourceRecord) : Json :=
  Json.mkObj [("source", toJson record)]

private def packetShowJson (root : System.FilePath) (record : SourcePacket) (body : String) : Json :=
  jsonWithBody "packet" (toJson record) (record.id.bodyPath root) body

private def knowledgeShowJson (root : System.FilePath) (entry : KnowledgeEntry) (body : String) : Json :=
  jsonWithBody "knowledge" (toJson entry) (entry.id.bodyPath root) body

private def validatePacketRecord (data : LoadedStoreData) (packet : SourcePacket) : IO Unit := do
  match packet.validate with
  | .ok () => pure ()
  | .error err => throw <| IO.userError err
  unless hasSource data packet.source do
    throw <| IO.userError s!"packet `{packet.id}` references missing source `{packet.source}`"
  for prov in packet.provenance do
    unless hasSource data prov.source do
      throw <| IO.userError s!"packet `{packet.id}` provenance references missing source `{prov.source}`"
  unless (← (packet.id.bodyPath data.store.root).pathExists) do
    throw <| IO.userError s!"missing packet body file `{packet.id.bodyPath data.store.root}`"

private def validateKnowledgeRecord (data : LoadedStoreData) (entry : KnowledgeEntry) : IO Unit := do
  match entry.validate with
  | .ok () => pure ()
  | .error err => throw <| IO.userError err
  for sourceId in entry.sourceRefs do
    unless hasSource data sourceId do
      throw <| IO.userError s!"knowledge `{entry.id}` references missing source `{sourceId}`"
  for packetId in entry.packetRefs do
    unless hasPacket data packetId do
      throw <| IO.userError s!"knowledge `{entry.id}` references missing packet `{packetId}`"
  for link in entry.links do
    unless hasKnowledge data link.target do
      throw <| IO.userError s!"knowledge `{entry.id}` has dangling link target `{link.target}`"
  for prov in entry.provenance do
    match prov.targetKind with
    | .source =>
      let sourceId ←
        match SourceId.ofString prov.targetId with
        | .ok sourceId => pure sourceId
        | .error err => throw <| IO.userError err
      unless hasSource data sourceId do
        throw <| IO.userError s!"knowledge `{entry.id}` provenance references missing source `{sourceId}`"
    | .packet =>
      let packetId ←
        match PacketId.ofString prov.targetId with
        | .ok packetId => pure packetId
        | .error err => throw <| IO.userError err
      unless hasPacket data packetId do
        throw <| IO.userError s!"knowledge `{entry.id}` provenance references missing packet `{packetId}`"
    | .knowledge =>
      let targetId ←
        match KnowledgeId.ofString prov.targetId with
        | .ok targetId => pure targetId
        | .error err => throw <| IO.userError err
      unless hasKnowledge data targetId do
        throw <| IO.userError s!"knowledge `{entry.id}` provenance references missing knowledge `{targetId}`"
    | .scaffold =>
      match Informalize.LocationId.ofDottedString prov.targetId with
      | .ok _ => pure ()
      | .error err => throw <| IO.userError err
  unless (← (entry.id.bodyPath data.store.root).pathExists) do
    throw <| IO.userError s!"missing knowledge body file `{entry.id.bodyPath data.store.root}`"

private def runStoreCommand (cfg : Config) : IO RenderedOutput := do
  match cfg.command with
  | .store .init =>
    let root := cfg.storeRoot?.getD (defaultStoreRoot (← IO.currentDir))
    match (← initStore root) with
    | .ok (manifestPath, created) =>
      return emit cfg
        ("\n".intercalate [
          s!"store-root: {root}",
          s!"store-manifest: {manifestPath}",
          s!"created: {created}"
        ])
        (Json.mkObj [
          ("storeRoot", .str (toString root)),
          ("storeManifest", .str (toString manifestPath)),
          ("created", toJson created)
        ])
    | .error err =>
      throw <| IO.userError err
  | .store .stats =>
    let data ← loadStoreDataOrError cfg
    let stats := AFTK.stats data
    return emit cfg
      ("\n".intercalate [
        s!"store-root: {data.store.root}",
        s!"sources: {stats.sourceCount}",
        s!"packets: {stats.packetCount}",
        s!"knowledge: {stats.knowledgeCount}"
      ])
      (Json.mkObj [
        ("storeRoot", .str (toString data.store.root)),
        ("stats", toJson stats)
      ])
  | .store .validate =>
    let data ← loadStoreDataOrError cfg
    let issues ← validateStoreData data
    if !issues.isEmpty then
      throw <| IO.userError <| String.intercalate "\n" issues.toList
    let stats := AFTK.stats data
    return emit cfg
      ("\n".intercalate [
        s!"store-root: {data.store.root}",
        "valid: true",
        s!"sources: {stats.sourceCount}",
        s!"packets: {stats.packetCount}",
        s!"knowledge: {stats.knowledgeCount}"
      ])
      (Json.mkObj [
        ("storeRoot", .str (toString data.store.root)),
        ("valid", .bool true),
        ("stats", toJson stats)
      ])
  | _ =>
    throw <| IO.userError "internal error: not a store command"

private def runSourceCommand (cfg : Config) : IO RenderedOutput := do
  let data ← loadStoreDataOrError cfg
  match cfg.command with
  | .source .list =>
    let sources := data.sources.qsort (fun a b => a.id.raw < b.id.raw)
    return emit cfg (renderSourceList sources) (Json.mkObj [("sources", toJson sources)])
  | .source .show =>
    let some id := cfg.sourceId? | throw <| IO.userError "missing source id"
    let source ←
      match findSource? data id with
      | some source => pure source
      | none => throw <| IO.userError s!"unknown source id `{id}`"
    return emit cfg source.renderSummary (sourceShowJson source)
  | .source .validate =>
    let some id := cfg.sourceId? | throw <| IO.userError "missing source id"
    let source ←
      match findSource? data id with
      | some source => pure source
      | none => throw <| IO.userError s!"unknown source id `{id}`"
    match source.validate with
    | .ok () =>
      return emit cfg
        ("\n".intercalate [s!"id: {id}", "valid: true"])
        (Json.mkObj [("id", toJson id), ("valid", .bool true)])
    | .error err =>
      throw <| IO.userError err
  | .source .register =>
    let some id := cfg.sourceId? | throw <| IO.userError "missing source id"
    if hasSource data id then
      throw <| IO.userError s!"source `{id}` already exists"
    let locator ←
      match sourceLocatorFromConfig cfg with
      | .ok locator => pure locator
      | .error err => throw <| IO.userError err
    let record ←
      match SourceRecord.normalize {
        id,
        kind := cfg.sourceKind?.get!,
        title := cfg.title?.get!,
        authors := cfg.authors,
        locator,
        version? := cfg.version?,
        contentHash? := cfg.contentHash?,
        license? := cfg.license?,
        tags := cfg.tags,
        note? := cfg.note?
      } with
      | .ok record => pure record
      | .error err => throw <| IO.userError err
    match (← saveSourceRecord data.store.root record) with
    | .ok path =>
      return emit cfg
        ("\n".intercalate ["action: register", s!"id: {record.id}", s!"path: {path}"])
        (Json.mkObj [("action", .str "register"), ("id", toJson record.id), ("path", .str (toString path)), ("source", toJson record)])
    | .error err =>
      throw <| IO.userError err
  | .source .update =>
    let some id := cfg.sourceId? | throw <| IO.userError "missing source id"
    unless hasSource data id do
      throw <| IO.userError s!"unknown source id `{id}`"
    let record : SourceRecord ← readJsonTypedOrError "source record" cfg.fromJson?.get!
    if record.id != id then
      throw <| IO.userError s!"source update id mismatch: expected `{id}`, got `{record.id}`"
    match (← saveSourceRecord data.store.root record) with
    | .ok path =>
      return emit cfg
        ("\n".intercalate ["action: update", s!"id: {record.id}", s!"path: {path}"])
        (Json.mkObj [("action", .str "update"), ("id", toJson record.id), ("path", .str (toString path)), ("source", toJson record)])
    | .error err =>
      throw <| IO.userError err
  | .source .remove =>
    let some id := cfg.sourceId? | throw <| IO.userError "missing source id"
    unless hasSource data id do
      throw <| IO.userError s!"unknown source id `{id}`"
    match checkCanRemoveSource data id with
    | .error err => throw <| IO.userError err
    | .ok () => pure ()
    let path := id.jsonPath data.store.root
    IO.FS.removeFile path
    return emit cfg
      ("\n".intercalate ["action: remove", s!"id: {id}", s!"path: {path}"])
      (Json.mkObj [("action", .str "remove"), ("id", toJson id), ("path", .str (toString path))])
  | _ =>
    throw <| IO.userError "internal error: not a source command"

private def runPacketCommand (cfg : Config) : IO RenderedOutput := do
  let data ← loadStoreDataOrError cfg
  match cfg.command with
  | .packet .list =>
    let packets :=
      match cfg.querySource? with
      | some sourceId => data.packets.filter (·.source == sourceId)
      | none => data.packets
    return emit cfg (renderPacketList packets) (Json.mkObj [("packets", toJson packets)])
  | .packet .show =>
    let some id := cfg.packetId? | throw <| IO.userError "missing packet id"
    let packet ←
      match findPacket? data id with
      | some packet => pure packet
      | none => throw <| IO.userError s!"unknown packet id `{id}`"
    let body ←
      match (← readPacketBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    return emit cfg
      ("\n\n".intercalate [packet.renderSummary, body])
      (packetShowJson data.store.root packet body)
  | .packet .validate =>
    let some id := cfg.packetId? | throw <| IO.userError "missing packet id"
    let packet ←
      match findPacket? data id with
      | some packet => pure packet
      | none => throw <| IO.userError s!"unknown packet id `{id}`"
    validatePacketRecord data packet
    return emit cfg
      ("\n".intercalate [s!"id: {id}", "valid: true"])
      (Json.mkObj [("id", toJson id), ("valid", .bool true)])
  | .packet .ingest =>
    let some id := cfg.packetId? | throw <| IO.userError "missing packet id"
    if hasPacket data id then
      throw <| IO.userError s!"packet `{id}` already exists"
    let source := cfg.sourceRefs[0]!
    ensureSourceExists data source
    let body ← readBodyFileOrError cfg.bodyFile?.get!
    let packet ←
      match SourcePacket.normalize {
        id,
        source,
        title := cfg.title?.get!,
        summary? := cfg.summary?,
        anchors := cfg.anchorIds.map fun anchor => ({ id := anchor : PacketAnchor }),
        provenance := autoPacketProvenance cfg source,
        tags := cfg.tags
      } with
      | .ok packet => pure packet
      | .error err => throw <| IO.userError err
    match (← saveSourcePacket data.store.root packet body) with
    | .ok (jsonPath, bodyPath) =>
      return emit cfg
        ("\n".intercalate ["action: ingest", s!"id: {packet.id}", s!"json-path: {jsonPath}", s!"body-path: {bodyPath}"])
        (Json.mkObj [
          ("action", .str "ingest"),
          ("id", toJson packet.id),
          ("jsonPath", .str (toString jsonPath)),
          ("bodyPath", .str (toString bodyPath)),
          ("packet", toJson packet)
        ])
    | .error err =>
      throw <| IO.userError err
  | .packet .update =>
    let some id := cfg.packetId? | throw <| IO.userError "missing packet id"
    unless hasPacket data id do
      throw <| IO.userError s!"unknown packet id `{id}`"
    let packet : SourcePacket ← readJsonTypedOrError "packet record" cfg.fromJson?.get!
    if packet.id != id then
      throw <| IO.userError s!"packet update id mismatch: expected `{id}`, got `{packet.id}`"
    ensureSourceExists data packet.source
    for prov in packet.provenance do
      ensureSourceExists data prov.source
    let body ←
      match cfg.bodyFile? with
      | some path => readBodyFileOrError path
      | none =>
        match (← readPacketBody data.store.root id) with
        | .ok body => pure body
        | .error err => throw <| IO.userError err
    match (← saveSourcePacket data.store.root packet body) with
    | .ok (jsonPath, bodyPath) =>
      return emit cfg
        ("\n".intercalate ["action: update", s!"id: {packet.id}", s!"json-path: {jsonPath}", s!"body-path: {bodyPath}"])
        (Json.mkObj [
          ("action", .str "update"),
          ("id", toJson packet.id),
          ("jsonPath", .str (toString jsonPath)),
          ("bodyPath", .str (toString bodyPath)),
          ("packet", toJson packet)
        ])
    | .error err =>
      throw <| IO.userError err
  | .packet .remove =>
    let some id := cfg.packetId? | throw <| IO.userError "missing packet id"
    unless hasPacket data id do
      throw <| IO.userError s!"unknown packet id `{id}`"
    match checkCanRemovePacket data id with
    | .ok () => pure ()
    | .error err => throw <| IO.userError err
    let jsonPath := id.jsonPath data.store.root
    let bodyPath := id.bodyPath data.store.root
    if (← jsonPath.pathExists) then IO.FS.removeFile jsonPath
    if (← bodyPath.pathExists) then IO.FS.removeFile bodyPath
    return emit cfg
      ("\n".intercalate ["action: remove", s!"id: {id}", s!"json-path: {jsonPath}", s!"body-path: {bodyPath}"])
      (Json.mkObj [("action", .str "remove"), ("id", toJson id), ("jsonPath", .str (toString jsonPath)), ("bodyPath", .str (toString bodyPath))])
  | _ =>
    throw <| IO.userError "internal error: not a packet command"

private def runKbCommand (cfg : Config) : IO RenderedOutput := do
  let data ← loadStoreDataOrError cfg
  match cfg.command with
  | .kb .list =>
    return emit cfg (renderKnowledgeList data.knowledge) (Json.mkObj [("knowledge", toJson data.knowledge)])
  | .kb .show =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    let body ←
      match (← readKnowledgeBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    return emit cfg
      ("\n\n".intercalate [entry.renderSummary, body])
      (knowledgeShowJson data.store.root entry body)
  | .kb .validate =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    validateKnowledgeRecord data entry
    return emit cfg
      ("\n".intercalate [s!"id: {id}", "valid: true"])
      (Json.mkObj [("id", toJson id), ("valid", .bool true)])
  | .kb .query =>
    let query : KbQuery := {
      idPrefix := cfg.queryIdPrefix?,
      kind := cfg.knowledgeKind?,
      basis := cfg.knowledgeBasis?,
      tag := cfg.queryTag?,
      source := cfg.querySource?,
      packet := cfg.queryPacket?,
      location := cfg.queryLocation?,
      relatedTo := cfg.relatedTo?,
      text := cfg.queryText?,
      limit := cfg.limit?
    }
    let results ←
      match ← queryKnowledge data query with
      | .ok results => pure results
      | .error err => throw <| IO.userError err
    let plainItems := results.toList.map fun (entry, body) =>
      "\n\n".intercalate [entry.renderSummary, body]
    let jsonItems := results.map fun (entry, body) =>
      Json.mkObj [
        ("knowledge", toJson entry),
        ("bodyPath", .str (toString (entry.id.bodyPath data.store.root))),
        ("body", .str body)
      ]
    return emit cfg
      ("\n\n".intercalate <| [s!"Knowledge query results ({results.size}):"] ++ plainItems)
      (Json.mkObj [("results", Json.arr jsonItems)])
  | .kb .create =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    if hasKnowledge data id then
      throw <| IO.userError s!"knowledge `{id}` already exists"
    for sourceId in cfg.sourceRefs do
      ensureSourceExists data sourceId
    for packetId in cfg.packetRefs do
      ensurePacketExists data packetId
    let body ← readBodyFileOrError cfg.bodyFile?.get!
    let entry ←
      match KnowledgeEntry.normalize {
        id,
        kind := cfg.knowledgeKind?.get!,
        basis := cfg.knowledgeBasis?.get!,
        title := cfg.title?.get!,
        summary? := cfg.summary?,
        packetRefs := cfg.packetRefs,
        sourceRefs := cfg.sourceRefs,
        scaffoldRefs := cfg.scaffoldRefs,
        provenance := autoKnowledgeProvenance cfg,
        links := #[],
        tags := cfg.tags
      } with
      | .ok entry => pure entry
      | .error err => throw <| IO.userError err
    match (← saveKnowledgeEntry data.store.root entry body) with
    | .ok (jsonPath, bodyPath) =>
      return emit cfg
        ("\n".intercalate ["action: create", s!"id: {entry.id}", s!"json-path: {jsonPath}", s!"body-path: {bodyPath}"])
        (Json.mkObj [
          ("action", .str "create"),
          ("id", toJson entry.id),
          ("jsonPath", .str (toString jsonPath)),
          ("bodyPath", .str (toString bodyPath)),
          ("knowledge", toJson entry)
        ])
    | .error err =>
      throw <| IO.userError err
  | .kb .update =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    unless hasKnowledge data id do
      throw <| IO.userError s!"unknown knowledge id `{id}`"
    let entry : KnowledgeEntry ← readJsonTypedOrError "knowledge record" cfg.fromJson?.get!
    if entry.id != id then
      throw <| IO.userError s!"knowledge update id mismatch: expected `{id}`, got `{entry.id}`"
    for sourceId in entry.sourceRefs do
      ensureSourceExists data sourceId
    for packetId in entry.packetRefs do
      ensurePacketExists data packetId
    for link in entry.links do
      ensureKnowledgeExists data link.target
    let body ←
      match cfg.bodyFile? with
      | some path => readBodyFileOrError path
      | none =>
        match (← readKnowledgeBody data.store.root id) with
        | .ok body => pure body
        | .error err => throw <| IO.userError err
    match (← saveKnowledgeEntry data.store.root entry body) with
    | .ok (jsonPath, bodyPath) =>
      return emit cfg
        ("\n".intercalate ["action: update", s!"id: {entry.id}", s!"json-path: {jsonPath}", s!"body-path: {bodyPath}"])
        (Json.mkObj [
          ("action", .str "update"),
          ("id", toJson entry.id),
          ("jsonPath", .str (toString jsonPath)),
          ("bodyPath", .str (toString bodyPath)),
          ("knowledge", toJson entry)
        ])
    | .error err =>
      throw <| IO.userError err
  | .kb .remove =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    unless hasKnowledge data id do
      throw <| IO.userError s!"unknown knowledge id `{id}`"
    match checkCanRemoveKnowledge data id with
    | .ok () => pure ()
    | .error err => throw <| IO.userError err
    let jsonPath := id.jsonPath data.store.root
    let bodyPath := id.bodyPath data.store.root
    if (← jsonPath.pathExists) then IO.FS.removeFile jsonPath
    if (← bodyPath.pathExists) then IO.FS.removeFile bodyPath
    return emit cfg
      ("\n".intercalate ["action: remove", s!"id: {id}", s!"json-path: {jsonPath}", s!"body-path: {bodyPath}"])
      (Json.mkObj [("action", .str "remove"), ("id", toJson id), ("jsonPath", .str (toString jsonPath)), ("bodyPath", .str (toString bodyPath))])
  | .kb .addTag =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    let body ←
      match (← readKnowledgeBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    let updated := { entry with tags := AFTK.addUnique entry.tags cfg.tags[0]! }
    match (← saveKnowledgeEntry data.store.root updated body) with
    | .ok _ =>
      return emit cfg
        ("\n".intercalate ["action: add-tag", s!"id: {id}", s!"tags: {", ".intercalate updated.tags.toList}"])
        (Json.mkObj [("action", .str "add-tag"), ("id", toJson id), ("knowledge", toJson updated)])
    | .error err => throw <| IO.userError err
  | .kb .removeTag =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    let body ←
      match (← readKnowledgeBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    let updated := { entry with tags := AFTK.removeAll entry.tags cfg.tags[0]! }
    match (← saveKnowledgeEntry data.store.root updated body) with
    | .ok _ =>
      return emit cfg
        ("\n".intercalate ["action: remove-tag", s!"id: {id}", s!"tags: {", ".intercalate updated.tags.toList}"])
        (Json.mkObj [("action", .str "remove-tag"), ("id", toJson id), ("knowledge", toJson updated)])
    | .error err => throw <| IO.userError err
  | .kb .addLink =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    let target := cfg.targetKnowledgeId?.get!
    ensureKnowledgeExists data target
    let body ←
      match (← readKnowledgeBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    let updated := { entry with links := AFTK.addUnique entry.links { relation := cfg.relation?.get!, target } }
    match (← saveKnowledgeEntry data.store.root updated body) with
    | .ok _ =>
      return emit cfg
        ("\n".intercalate ["action: add-link", s!"id: {id}", s!"relation: {cfg.relation?.get!}", s!"target: {target}"])
        (Json.mkObj [("action", .str "add-link"), ("id", toJson id), ("knowledge", toJson updated)])
    | .error err => throw <| IO.userError err
  | .kb .removeLink =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    let body ←
      match (← readKnowledgeBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    let target := cfg.targetKnowledgeId?.get!
    let updated := { entry with links := entry.links.filter fun link => !(link.relation == cfg.relation?.get! && link.target == target) }
    match (← saveKnowledgeEntry data.store.root updated body) with
    | .ok _ =>
      return emit cfg
        ("\n".intercalate ["action: remove-link", s!"id: {id}", s!"relation: {cfg.relation?.get!}", s!"target: {target}"])
        (Json.mkObj [("action", .str "remove-link"), ("id", toJson id), ("knowledge", toJson updated)])
    | .error err => throw <| IO.userError err
  | .kb .addScaffoldRef =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    let body ←
      match (← readKnowledgeBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    let updated := { entry with scaffoldRefs := AFTK.addUnique entry.scaffoldRefs cfg.scaffoldRefs[0]! }
    match (← saveKnowledgeEntry data.store.root updated body) with
    | .ok _ =>
      return emit cfg
        ("\n".intercalate ["action: add-scaffold-ref", s!"id: {id}", s!"location: {cfg.scaffoldRefs[0]!}"])
        (Json.mkObj [("action", .str "add-scaffold-ref"), ("id", toJson id), ("knowledge", toJson updated)])
    | .error err => throw <| IO.userError err
  | .kb .removeScaffoldRef =>
    let some id := cfg.knowledgeId? | throw <| IO.userError "missing knowledge id"
    let entry ←
      match findKnowledge? data id with
      | some entry => pure entry
      | none => throw <| IO.userError s!"unknown knowledge id `{id}`"
    let body ←
      match (← readKnowledgeBody data.store.root id) with
      | .ok body => pure body
      | .error err => throw <| IO.userError err
    let updated := { entry with scaffoldRefs := AFTK.removeAll entry.scaffoldRefs cfg.scaffoldRefs[0]! }
    match (← saveKnowledgeEntry data.store.root updated body) with
    | .ok _ =>
      return emit cfg
        ("\n".intercalate ["action: remove-scaffold-ref", s!"id: {id}", s!"location: {cfg.scaffoldRefs[0]!}"])
        (Json.mkObj [("action", .str "remove-scaffold-ref"), ("id", toJson id), ("knowledge", toJson updated)])
    | .error err => throw <| IO.userError err
  | _ =>
    throw <| IO.userError "internal error: not a kb command"

private def runCommand (cfg : Config) : IO RenderedOutput := do
  match cfg.command with
  | .store _ => runStoreCommand cfg
  | .source _ => runSourceCommand cfg
  | .packet _ => runPacketCommand cfg
  | .kb _ => runKbCommand cfg

def invoke (args : Array String) : IO InvocationResult := do
  match parseArgs args with
  | .error err =>
    return {
      exitCode := 1
      stderr := s!"error: {err}\n\n{usage}"
    }
  | .ok none =>
    return {
      exitCode := 0
      stdout := usage
    }
  | .ok (some cfg) =>
    try
      let output ← runCommand cfg
      return {
        exitCode := 0
        stdout := output.render
      }
    catch ex =>
      return {
        exitCode := 1
        stderr := s!"error: {ex}"
      }

end AFTK.Cli
