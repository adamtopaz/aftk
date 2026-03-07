module

public import Lean
public import Informalize.Extension
public import Informalize.Location
public import Informalize.Metadata

public section

open Lean

namespace Informalize.Cli

inductive MetaAction where
  | show
  | validate
  | init
  | setStatus
  | setParent
  | clearParent
  | setKind
  | clearKind
  | addTag
  | removeTag
  | addKnowledgeRef
  | removeKnowledgeRef
  | addSource
  | removeSource
  | addIssue
  | removeIssue
  deriving Inhabited, Repr, BEq

inductive CliCommand where
  | status
  | deps
  | decls
  | decl
  | locations
  | location
  | metadata (action : MetaAction)
  deriving Inhabited, Repr, BEq

inductive DeclsFilter where
  | allDecls
  | bareOnly
  | withLocations
  deriving Inhabited, Repr, BEq

inductive DepsView where
  | byDecl
  | byLocation
  deriving Inhabited, Repr, BEq

inductive OutputMode where
  | plainText
  | jsonText
  deriving Inhabited, Repr, BEq

structure Config where
  command : CliCommand
  modules : Array Name := #[]
  declName? : Option Name := none
  location? : Option LocationId := none
  declsFilter : DeclsFilter := .allDecls
  depsView : DepsView := .byDecl
  outputMode : OutputMode := .plainText
  status? : Option NodeStatus := none
  parent? : Option LocationId := none
  kind? : Option String := none
  tag? : Option String := none
  knowledgeRef? : Option String := none
  sourceId? : Option String := none
  sourceAnchors : Array String := #[]
  sourceLocator? : Option String := none
  sourceRole? : Option String := none
  issueId? : Option String := none
  issueKind? : Option String := none
  issueNote? : Option String := none
  issueRefs : Array String := #[]
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
  | .plain text =>
    text
  | .json value =>
    value.pretty

end RenderedOutput

def usage : String :=
  "\n".intercalate [
    "Informalize CLI",
    "",
    "Usage:",
    "  lake exe informalize <command> [options]",
    "  lake exe informalize meta <subcommand> [options]",
    "",
    "Commands:",
    "  status                 Show summary of tracked declarations and locations",
    "  deps                   Show transitive dependencies (--by decl|location)",
    "  decls                  List tracked declarations",
    "  decl                   Show tracked locations for one declaration",
    "  locations              List markdown locations and referencing declarations",
    "  location               Show declarations referencing one markdown location",
    "  meta show              Show effective metadata for one location",
    "  meta validate          Validate effective metadata for one location",
    "  meta init              Materialize default metadata JSON for one location",
    "  meta set-status        Set metadata status",
    "  meta set-parent        Set metadata parent location",
    "  meta clear-parent      Clear metadata parent",
    "  meta set-kind          Set metadata kind",
    "  meta clear-kind        Clear metadata kind",
    "  meta add-tag           Add one metadata tag",
    "  meta remove-tag        Remove one metadata tag",
    "  meta add-knowledge-ref Add one knowledge reference",
    "  meta remove-knowledge-ref Remove one knowledge reference",
    "  meta add-source        Add one source reference",
    "  meta remove-source     Remove source references by source id[/locator]",
    "  meta add-issue         Add one workflow issue",
    "  meta remove-issue      Remove one workflow issue by id",
    "",
    "Module-based commands require:",
    "  -m, --module <Module>  Import module before running command (repeatable)",
    "",
    "Common options:",
    "  --json                 Emit machine-readable JSON output",
    "",
    "Query options:",
    "  --decl <Decl.Name>     Required for `decl`",
    "  --location <Location>  Required for `location` and all `meta` commands",
    "  --by <decl|location>   Optional for `deps` (default: decl)",
    "  --bare-only            Filter `decls` output to declarations with empty location sets",
    "  --with-locations       Filter `decls` output to declarations with non-empty location sets",
    "",
    "Metadata mutation options:",
    "  --status <Status>      Required for `meta set-status`",
    "  --parent <Location>    Required for `meta set-parent`",
    "  --kind <Kind>          Required for `meta set-kind`; also issue kind for `meta add-issue`",
    "  --tag <Tag>            Required for `meta add-tag` / `meta remove-tag`",
    "  --ref <Ref>            Required for knowledge-ref commands; repeatable for `meta add-issue`",
    "  --source-id <Id>       Required for source commands",
    "  --anchor <Anchor>      Repeatable for `meta add-source`",
    "  --locator <Locator>    Optional for source commands",
    "  --role <Role>          Optional for `meta add-source`",
    "  --id <IssueId>         Required for issue commands",
    "  --note <Note>          Required for `meta add-issue`",
    "",
    "Status values:",
    "  scaffolded | needs_sources | needs_refinement | ready | formalizing | formalized | blocked",
    "",
    "Examples:",
    "  lake exe informalize status --module Tests.Integration.Imports.Top",
    "  lake exe informalize deps --module Tests.Integration.Imports.Top --by location",
    "  lake exe informalize decl --module Tests.Integration.Imports.Top --decl Tests.Integration.Imports.Base.baseLoc",
    "  lake exe informalize location --module Tests.Integration.Imports.Top --location Foo.bar",
    "  lake exe informalize meta show --location Foo.bar",
    "  lake exe informalize meta set-status --location Foo.bar --status ready",
    "  lake exe informalize meta add-source --location Foo.bar --source-id smith2024 --anchor \"Thm. 2.3\" --role primary",
    "  lake exe informalize meta add-issue --location Foo.bar --id missing-proof --kind source --note \"Need source-backed proof sketch\" --ref smith2024"
  ]

private def parseDottedName (kind : String) (raw : String) : Except String Name := do
  let trimmed := normalizeText raw
  if trimmed.isEmpty then
    throw s!"{kind} name must be non-empty"
  let parts := trimmed.splitOn "."
  if parts.any String.isEmpty then
    throw s!"invalid {kind} name `{raw}`"
  return parts.foldl (init := Name.anonymous) Name.str

private def parseModuleName (raw : String) : Except String Name :=
  parseDottedName "module" raw

private def parseDeclName (raw : String) : Except String Name :=
  parseDottedName "declaration" raw

private def parseLocationName (raw : String) : Except String LocationId :=
  LocationId.ofDottedString raw

private def parseNodeStatus (raw : String) : Except String NodeStatus :=
  fromJson? (.str (normalizeText raw))

private def parseDepsView (raw : String) : Except String DepsView :=
  match normalizeText raw with
  | "decl" =>
    .ok .byDecl
  | "location" =>
    .ok .byLocation
  | other =>
    .error s!"invalid dependency mode `{other}` (expected `decl` or `location`)"

private def parseMetaAction (raw : String) : Except String MetaAction :=
  match raw with
  | "show" => .ok .show
  | "validate" => .ok .validate
  | "init" => .ok .init
  | "set-status" => .ok .setStatus
  | "set-parent" => .ok .setParent
  | "clear-parent" => .ok .clearParent
  | "set-kind" => .ok .setKind
  | "clear-kind" => .ok .clearKind
  | "add-tag" => .ok .addTag
  | "remove-tag" => .ok .removeTag
  | "add-knowledge-ref" => .ok .addKnowledgeRef
  | "remove-knowledge-ref" => .ok .removeKnowledgeRef
  | "add-source" => .ok .addSource
  | "remove-source" => .ok .removeSource
  | "add-issue" => .ok .addIssue
  | "remove-issue" => .ok .removeIssue
  | other => .error s!"unknown metadata subcommand `{other}`"

private def parseCliCommand (raw : String) : Except String CliCommand :=
  match raw with
  | "status" => .ok CliCommand.status
  | "deps" => .ok CliCommand.deps
  | "decls" => .ok CliCommand.decls
  | "decl" => .ok CliCommand.decl
  | "locations" => .ok CliCommand.locations
  | "location" => .ok CliCommand.location
  | other => .error s!"unknown command `{other}`"

private def isMetaCommand (command : CliCommand) : Bool :=
  match command with
  | CliCommand.metadata _ => true
  | _ => false

private def requireMetaAction (command : CliCommand) : Except String MetaAction :=
  match command with
  | CliCommand.metadata action => .ok action
  | _ => .error "internal error: expected metadata command"

private def parseLooseText (label raw : String) : Except String String :=
  nonEmptyText label raw

private def validateConfig (cfg : Config) : Except String Config := do
  match cfg.command with
  | CliCommand.status | CliCommand.deps | CliCommand.decls | CliCommand.decl | CliCommand.locations | CliCommand.location =>
    if cfg.modules.isEmpty then
      throw "missing required option `--module <Module.Name>`"
  | CliCommand.metadata action =>
    if !cfg.modules.isEmpty then
      throw "`--module` is not valid for `meta` commands"
    if cfg.location?.isNone then
      throw "missing required option `--location <Location>` for `meta` commands"
    match action with
    | .show | .validate | .init | .clearParent | .clearKind =>
      pure ()
    | .setStatus =>
      if cfg.status?.isNone then
        throw "missing required option `--status <Status>` for `meta set-status`"
    | .setParent =>
      if cfg.parent?.isNone then
        throw "missing required option `--parent <Location>` for `meta set-parent`"
    | .setKind =>
      if cfg.kind?.isNone then
        throw "missing required option `--kind <Kind>` for `meta set-kind`"
    | .addTag =>
      if cfg.tag?.isNone then
        throw "missing required option `--tag <Tag>` for `meta add-tag`"
    | .removeTag =>
      if cfg.tag?.isNone then
        throw "missing required option `--tag <Tag>` for `meta remove-tag`"
    | .addKnowledgeRef =>
      if cfg.knowledgeRef?.isNone then
        throw "missing required option `--ref <Ref>` for `meta add-knowledge-ref`"
    | .removeKnowledgeRef =>
      if cfg.knowledgeRef?.isNone then
        throw "missing required option `--ref <Ref>` for `meta remove-knowledge-ref`"
    | .addSource =>
      if cfg.sourceId?.isNone then
        throw "missing required option `--source-id <Id>` for `meta add-source`"
    | .removeSource =>
      if cfg.sourceId?.isNone then
        throw "missing required option `--source-id <Id>` for `meta remove-source`"
    | .addIssue =>
      if cfg.issueId?.isNone then
        throw "missing required option `--id <IssueId>` for `meta add-issue`"
      if cfg.issueKind?.isNone then
        throw "missing required option `--kind <Kind>` for `meta add-issue`"
      if cfg.issueNote?.isNone then
        throw "missing required option `--note <Note>` for `meta add-issue`"
    | .removeIssue =>
      if cfg.issueId?.isNone then
        throw "missing required option `--id <IssueId>` for `meta remove-issue`"
  match cfg.command with
  | CliCommand.decl =>
    if cfg.declName?.isNone then
      throw "missing required option `--decl <Decl.Name>` for `decl`"
  | CliCommand.location =>
    if cfg.location?.isNone then
      throw "missing required option `--location <Location>` for `location`"
  | _ =>
    pure ()
  return cfg

private partial def parseOptions
    (cfg : Config)
    (args : List String) : Except String (Option Config) := do
  match args with
  | [] =>
    return some (← validateConfig cfg)
  | "--help" :: _ =>
    return none
  | "-h" :: _ =>
    return none
  | "--json" :: rest =>
    parseOptions { cfg with outputMode := .jsonText } rest
  | "--module" :: moduleRaw :: rest =>
    parseOptions { cfg with modules := cfg.modules.push (← parseModuleName moduleRaw) } rest
  | "--module" :: [] =>
    throw "expected module name after `--module`"
  | "-m" :: moduleRaw :: rest =>
    parseOptions { cfg with modules := cfg.modules.push (← parseModuleName moduleRaw) } rest
  | "-m" :: [] =>
    throw "expected module name after `-m`"
  | "--decl" :: declRaw :: rest =>
    if cfg.command != CliCommand.decl then
      throw "`--decl` is only valid for the `decl` command"
    else
      parseOptions { cfg with declName? := some (← parseDeclName declRaw) } rest
  | "--decl" :: [] =>
    throw "expected declaration name after `--decl`"
  | "--location" :: locationRaw :: rest =>
    match cfg.command with
    | CliCommand.location | CliCommand.metadata _ =>
      parseOptions { cfg with location? := some (← parseLocationName locationRaw) } rest
    | _ =>
      throw "`--location` is only valid for the `location` command or `meta` commands"
  | "--location" :: [] =>
    throw "expected location name after `--location`"
  | "--by" :: byRaw :: rest =>
    if cfg.command != CliCommand.deps then
      throw "`--by` is only valid for the `deps` command"
    else
      parseOptions { cfg with depsView := (← parseDepsView byRaw) } rest
  | "--by" :: [] =>
    throw "expected dependency mode after `--by`"
  | "--bare-only" :: rest =>
    if cfg.command != CliCommand.decls then
      throw "`--bare-only` is only valid for the `decls` command"
    else if cfg.declsFilter == DeclsFilter.withLocations then
      throw "`--bare-only` and `--with-locations` cannot be combined"
    else
      parseOptions { cfg with declsFilter := .bareOnly } rest
  | "--with-locations" :: rest =>
    if cfg.command != CliCommand.decls then
      throw "`--with-locations` is only valid for the `decls` command"
    else if cfg.declsFilter == DeclsFilter.bareOnly then
      throw "`--bare-only` and `--with-locations` cannot be combined"
    else
      parseOptions { cfg with declsFilter := .withLocations } rest
  | "--status" :: statusRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .setStatus =>
      parseOptions { cfg with status? := some (← parseNodeStatus statusRaw) } rest
    | _ =>
      throw "`--status` is only valid for `meta set-status`"
  | "--status" :: [] =>
    throw "expected status after `--status`"
  | "--parent" :: parentRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .setParent =>
      parseOptions { cfg with parent? := some (← parseLocationName parentRaw) } rest
    | _ =>
      throw "`--parent` is only valid for `meta set-parent`"
  | "--parent" :: [] =>
    throw "expected location after `--parent`"
  | "--kind" :: kindRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .setKind =>
      parseOptions { cfg with kind? := some (← parseLooseText "kind" kindRaw) } rest
    | CliCommand.metadata .addIssue =>
      parseOptions { cfg with issueKind? := some (← parseLooseText "issue kind" kindRaw) } rest
    | _ =>
      throw "`--kind` is only valid for `meta set-kind` and `meta add-issue`"
  | "--kind" :: [] =>
    throw "expected kind after `--kind`"
  | "--tag" :: tagRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addTag | CliCommand.metadata .removeTag =>
      parseOptions { cfg with tag? := some (← parseLooseText "tag" tagRaw) } rest
    | _ =>
      throw "`--tag` is only valid for `meta add-tag` and `meta remove-tag`"
  | "--tag" :: [] =>
    throw "expected tag after `--tag`"
  | "--ref" :: refRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addKnowledgeRef | CliCommand.metadata .removeKnowledgeRef =>
      parseOptions { cfg with knowledgeRef? := some (← parseLooseText "knowledge ref" refRaw) } rest
    | CliCommand.metadata .addIssue =>
      parseOptions { cfg with issueRefs := cfg.issueRefs.push (← parseLooseText "issue ref" refRaw) } rest
    | _ =>
      throw "`--ref` is only valid for knowledge-ref commands and `meta add-issue`"
  | "--ref" :: [] =>
    throw "expected reference after `--ref`"
  | "--source-id" :: sourceIdRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addSource | CliCommand.metadata .removeSource =>
      parseOptions { cfg with sourceId? := some (← parseLooseText "source id" sourceIdRaw) } rest
    | _ =>
      throw "`--source-id` is only valid for source metadata commands"
  | "--source-id" :: [] =>
    throw "expected source id after `--source-id`"
  | "--anchor" :: anchorRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addSource =>
      parseOptions { cfg with sourceAnchors := cfg.sourceAnchors.push (← parseLooseText "source anchor" anchorRaw) } rest
    | _ =>
      throw "`--anchor` is only valid for `meta add-source`"
  | "--anchor" :: [] =>
    throw "expected anchor after `--anchor`"
  | "--locator" :: locatorRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addSource | CliCommand.metadata .removeSource =>
      parseOptions { cfg with sourceLocator? := some (← parseLooseText "source locator" locatorRaw) } rest
    | _ =>
      throw "`--locator` is only valid for source metadata commands"
  | "--locator" :: [] =>
    throw "expected locator after `--locator`"
  | "--role" :: roleRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addSource =>
      parseOptions { cfg with sourceRole? := some (← parseLooseText "source role" roleRaw) } rest
    | _ =>
      throw "`--role` is only valid for `meta add-source`"
  | "--role" :: [] =>
    throw "expected role after `--role`"
  | "--id" :: issueIdRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addIssue | CliCommand.metadata .removeIssue =>
      parseOptions { cfg with issueId? := some (← parseLooseText "issue id" issueIdRaw) } rest
    | _ =>
      throw "`--id` is only valid for issue metadata commands"
  | "--id" :: [] =>
    throw "expected issue id after `--id`"
  | "--note" :: noteRaw :: rest =>
    match cfg.command with
    | CliCommand.metadata .addIssue =>
      parseOptions { cfg with issueNote? := some (← parseLooseText "issue note" noteRaw) } rest
    | _ =>
      throw "`--note` is only valid for `meta add-issue`"
  | "--note" :: [] =>
    throw "expected issue note after `--note`"
  | arg :: _ =>
    throw s!"unknown option `{arg}`"

def parseArgs (args : Array String) : Except String (Option Config) := do
  match args.toList with
  | [] =>
    return none
  | "--help" :: _ =>
    return none
  | "-h" :: _ =>
    return none
  | "help" :: _ =>
    return none
  | "meta" :: [] =>
    return none
  | "meta" :: actionRaw :: rest =>
    parseOptions { command := CliCommand.metadata (← parseMetaAction actionRaw) } rest
  | commandRaw :: rest =>
    parseOptions { command := (← parseCliCommand commandRaw) } rest

private def nameSetToSortedArray (locations : NameSet) : Array Name := Id.run do
  let mut result : Array Name := #[]
  for location in locations do
    result := result.push location
  return result.qsort Name.quickLt

private def nameSetToList (locations : NameSet) : List Name := Id.run do
  let mut result : List Name := []
  for location in locations do
    result := location :: result
  return result

private def locationCount (locations : NameSet) : Nat :=
  (nameSetToSortedArray locations).size

private def renderNameList (names : Array Name) : String :=
  ", ".intercalate (names.toList.map toString)

private def namesJson (names : Array Name) : Json :=
  toJson (names.map toString)

private def renderLocations (locations : NameSet) : String :=
  let names := nameSetToSortedArray locations
  if names.isEmpty then
    "-"
  else
    renderNameList names

private def declLine (entry : Informalize.InformalDeclEntry) : String :=
  let count := locationCount entry.locations
  s!"- {entry.declName} [{count}] {renderLocations entry.locations}"

private def filterDecls
    (entries : Array Informalize.InformalDeclEntry)
    (filter : DeclsFilter) : Array Informalize.InformalDeclEntry :=
  match filter with
  | .allDecls =>
    entries
  | .bareOnly =>
    entries.filter fun entry => locationCount entry.locations == 0
  | .withLocations =>
    entries.filter fun entry => locationCount entry.locations > 0

private def collectUniqueLocations
    (entries : Array Informalize.InformalDeclEntry) : NameSet := Id.run do
  let mut locations : NameSet := {}
  for entry in entries do
    for location in entry.locations do
      locations := locations.insert location
  return locations

private def trackedDeclNameSet
    (entries : Array Informalize.InformalDeclEntry) : NameSet :=
  entries.foldl (init := {}) fun declNames entry =>
    declNames.insert entry.declName

private def usedConstants
    (env : Environment)
    (declName : Name) : NameSet :=
  match env.find? declName with
  | some cinfo =>
    cinfo.getUsedConstantsAsSet
  | none =>
    {}

private partial def collectReachableTracked
    (env : Environment)
    (trackedDecls : NameSet)
    (root : Name)
    (todo : List Name)
    (visited : NameSet)
    (deps : NameSet) : NameSet :=
  match todo with
  | [] =>
    deps
  | declName :: rest =>
    if declName == root || visited.contains declName then
      collectReachableTracked env trackedDecls root rest visited deps
    else
      let visited := visited.insert declName
      let deps :=
        if trackedDecls.contains declName then
          deps.insert declName
        else
          deps
      let next := nameSetToList (usedConstants env declName)
      collectReachableTracked env trackedDecls root (next ++ rest) visited deps

private def transitiveDepIndex
    (env : Environment)
    (entries : Array Informalize.InformalDeclEntry) : Std.HashMap Name NameSet := Id.run do
  let trackedDecls := trackedDeclNameSet entries
  let mut index : Std.HashMap Name NameSet := {}
  for entry in entries do
    let initial := nameSetToList (usedConstants env entry.declName)
    let deps := collectReachableTracked env trackedDecls entry.declName initial {} {}
    index := index.insert entry.declName deps
  return index

private def locationDeclIndex
    (entries : Array Informalize.InformalDeclEntry) : Std.HashMap Name (Array Name) := Id.run do
  let mut index : Std.HashMap Name (Array Name) := {}
  for entry in entries do
    for location in entry.locations do
      let decls := index.getD location #[]
      let decls :=
        if decls.contains entry.declName then
          decls
        else
          decls.push entry.declName
      index := index.insert location decls
  return index

private def declLocationIndex
    (entries : Array Informalize.InformalDeclEntry) : Std.HashMap Name NameSet := Id.run do
  let mut index : Std.HashMap Name NameSet := {}
  for entry in entries do
    index := index.insert entry.declName entry.locations
  return index

private def locationDependencyIndex
    (env : Environment)
    (entries : Array Informalize.InformalDeclEntry) : Std.HashMap Name NameSet := Id.run do
  let declDeps := transitiveDepIndex env entries
  let byLocation := locationDeclIndex entries
  let byDecl := declLocationIndex entries
  let mut index : Std.HashMap Name NameSet := {}
  for (location, decls) in byLocation do
    let mut deps : NameSet := {}
    for declName in decls do
      for depDecl in declDeps.getD declName {} do
        for depLocation in byDecl.getD depDecl {} do
          deps := deps.insert depLocation
    deps := deps.erase location
    index := index.insert location deps
  return index

private def sortedLocationRows
    (index : Std.HashMap Name (Array Name)) : Array (Name × Array Name) := Id.run do
  let mut rows : Array (Name × Array Name) := #[]
  for (location, decls) in index do
    rows := rows.push (location, decls.qsort Name.quickLt)
  return rows.qsort (fun a b => Name.quickLt a.1 b.1)

private def sortedNameSetRows
    (index : Std.HashMap Name NameSet) : Array (Name × Array Name) := Id.run do
  let mut rows : Array (Name × Array Name) := #[]
  for (name, deps) in index do
    rows := rows.push (name, nameSetToSortedArray deps)
  return rows.qsort (fun a b => Name.quickLt a.1 b.1)

private def renderStatusSummary
    (entries : Array Informalize.InformalDeclEntry) : String :=
  let trackedDecls := entries.size
  let withLocations := entries.foldl (init := 0) fun count entry =>
    if locationCount entry.locations > 0 then count + 1 else count
  let bareDecls := trackedDecls - withLocations
  let uniqueLocations := locationCount (collectUniqueLocations entries)
  "\n".intercalate [
    "Informal extension status:",
    s!"- tracked declarations: {trackedDecls}",
    s!"- declarations with locations: {withLocations}",
    s!"- declarations with empty locations: {bareDecls}",
    s!"- unique markdown locations: {uniqueLocations}"
  ]

private def statusJson
    (entries : Array Informalize.InformalDeclEntry) : Json :=
  let trackedDecls := entries.size
  let withLocations := entries.foldl (init := 0) fun count entry =>
    if locationCount entry.locations > 0 then count + 1 else count
  let bareDecls := trackedDecls - withLocations
  let uniqueLocations := locationCount (collectUniqueLocations entries)
  Json.mkObj [
    ("trackedDeclarations", toJson trackedDecls),
    ("declarationsWithLocations", toJson withLocations),
    ("declarationsWithEmptyLocations", toJson bareDecls),
    ("uniqueMarkdownLocations", toJson uniqueLocations)
  ]

private def renderDecls
    (entries : Array Informalize.InformalDeclEntry)
    (filter : DeclsFilter) : String :=
  let entries := filterDecls entries filter
  let header :=
    match filter with
    | .allDecls =>
      s!"Tracked declarations ({entries.size}):"
    | .bareOnly =>
      s!"Tracked declarations with empty locations ({entries.size}):"
    | .withLocations =>
      s!"Tracked declarations with locations ({entries.size}):"
  if entries.isEmpty then
    header
  else
    "\n".intercalate (header :: (entries.map declLine).toList)

private def entryJson (entry : Informalize.InformalDeclEntry) : Json :=
  Json.mkObj [
    ("declName", .str (toString entry.declName)),
    ("locationCount", toJson (locationCount entry.locations)),
    ("locations", namesJson (nameSetToSortedArray entry.locations))
  ]

private def declsJson
    (entries : Array Informalize.InformalDeclEntry)
    (filter : DeclsFilter) : Json :=
  let filtered := filterDecls entries filter
  let filterName :=
    match filter with
    | .allDecls => "all"
    | .bareOnly => "bare_only"
    | .withLocations => "with_locations"
  Json.mkObj [
    ("filter", .str filterName),
    ("entries", Json.arr <| filtered.map entryJson)
  ]

private def renderDecl
    (declName : Name)
    (entry : Informalize.InformalDeclEntry) : String :=
  let count := locationCount entry.locations
  let locations := nameSetToSortedArray entry.locations
  let lines := locations.map fun location => s!"- {location}"
  let locationSection :=
    if lines.isEmpty then ["- (none)"] else lines.toList
  "\n".intercalate <|
    [
      s!"Declaration: {declName}",
      s!"location-count: {count}",
      "locations:"
    ] ++ locationSection

private def renderLocationIndex
    (entries : Array Informalize.InformalDeclEntry) : String :=
  let rows := sortedLocationRows (locationDeclIndex entries)
  let header := s!"Locations ({rows.size}):"
  if rows.isEmpty then
    header
  else
    let lines := rows.map fun (location, decls) =>
      s!"- {location} ({decls.size}): {renderNameList decls}"
    "\n".intercalate (header :: lines.toList)

private def locationIndexJson
    (entries : Array Informalize.InformalDeclEntry) : Json :=
  let rows := sortedLocationRows (locationDeclIndex entries)
  Json.mkObj [
    ("locations", Json.arr <| rows.map fun (location, decls) =>
      Json.mkObj [
        ("location", .str (toString location)),
        ("declCount", toJson decls.size),
        ("declarations", namesJson decls)
      ])
  ]

private def renderLocationLookup
    (entries : Array Informalize.InformalDeclEntry)
    (location : Name) : String :=
  let decls := ((locationDeclIndex entries).getD location #[]).qsort Name.quickLt
  let header := s!"Location {location} ({decls.size}):"
  if decls.isEmpty then
    "\n".intercalate [header, "- (none)"]
  else
    "\n".intercalate (header :: (decls.map fun declName => s!"- {declName}").toList)

private def locationLookupJson
    (entries : Array Informalize.InformalDeclEntry)
    (location : Name) : Json :=
  let decls := ((locationDeclIndex entries).getD location #[]).qsort Name.quickLt
  Json.mkObj [
    ("location", .str (toString location)),
    ("declCount", toJson decls.size),
    ("declarations", namesJson decls)
  ]

private def dependencyJsonRows
    (index : Std.HashMap Name NameSet) : Json × Json :=
  let rows := sortedNameSetRows index
  let rowJson := Json.arr <| rows.map fun (name, deps) =>
    Json.mkObj [
      ("name", .str (toString name)),
      ("dependencies", namesJson deps)
    ]
  let leaves := Json.arr <| rows.filterMap fun (name, deps) =>
    if deps.isEmpty then some (.str (toString name)) else none
  (rowJson, leaves)

private def renderDeclDependencies
    (env : Environment)
    (entries : Array Informalize.InformalDeclEntry) : String :=
  let declNames := entries.map (·.declName)
  let transitive := transitiveDepIndex env entries
  let depLines := declNames.map fun declName =>
    let deps := nameSetToSortedArray (transitive.getD declName {})
    if deps.isEmpty then
      s!"- {declName} -> (none)"
    else
      s!"- {declName} -> {renderNameList deps}"
  let leaves := declNames.filter fun declName =>
    locationCount (transitive.getD declName {}) == 0
  let leafLines :=
    if leaves.isEmpty then ["- (none)"]
    else (leaves.map fun declName => s!"- {declName}").toList
  "\n".intercalate <|
    [s!"Dependencies ({depLines.size}):"] ++ depLines.toList ++
    ["", s!"Leaves ({leaves.size}):"] ++ leafLines

private def declDependenciesJson
    (env : Environment)
    (entries : Array Informalize.InformalDeclEntry) : Json :=
  let index := transitiveDepIndex env entries
  let (rows, leaves) := dependencyJsonRows index
  Json.mkObj [
    ("mode", .str "decl"),
    ("rows", rows),
    ("leaves", leaves)
  ]

private def renderLocationDependencies
    (env : Environment)
    (entries : Array Informalize.InformalDeclEntry) : String :=
  let index := locationDependencyIndex env entries
  let rows := sortedNameSetRows index
  let depLines := rows.map fun (location, deps) =>
    if deps.isEmpty then
      s!"- {location} -> (none)"
    else
      s!"- {location} -> {renderNameList deps}"
  let leaves := rows.filterMap fun (location, deps) =>
    if deps.isEmpty then some location else none
  let leafLines :=
    if leaves.isEmpty then ["- (none)"]
    else (leaves.map fun location => s!"- {location}").toList
  "\n".intercalate <|
    [s!"Location dependencies ({depLines.size}):"] ++ depLines.toList ++
    ["", s!"Leaves ({leaves.size}):"] ++ leafLines

private def locationDependenciesJson
    (env : Environment)
    (entries : Array Informalize.InformalDeclEntry) : Json :=
  let index := locationDependencyIndex env entries
  let (rows, leaves) := dependencyJsonRows index
  Json.mkObj [
    ("mode", .str "location"),
    ("rows", rows),
    ("leaves", leaves)
  ]

private def chooseOutput
    (mode : OutputMode)
    (plain : String)
    (json : Json) : RenderedOutput :=
  match mode with
  | .plainText => .plain plain
  | .jsonText => .json json

private def runTrackedCommand (cfg : Config) : CoreM RenderedOutput := do
  let entries ← Informalize.allInformalDeclEntries
  match cfg.command with
  | CliCommand.status =>
    return chooseOutput cfg.outputMode (renderStatusSummary entries) (statusJson entries)
  | CliCommand.deps =>
    let env ← getEnv
    match cfg.depsView with
    | DepsView.byDecl =>
      return chooseOutput cfg.outputMode (renderDeclDependencies env entries) (declDependenciesJson env entries)
    | DepsView.byLocation =>
      return chooseOutput cfg.outputMode (renderLocationDependencies env entries) (locationDependenciesJson env entries)
  | CliCommand.decls =>
    return chooseOutput cfg.outputMode (renderDecls entries cfg.declsFilter) (declsJson entries cfg.declsFilter)
  | CliCommand.decl =>
    let some declName := cfg.declName?
      | throwError "missing declaration"
    let some entry ← Informalize.informalDeclEntry? declName
      | throwError s!"declaration `{declName}` is not tracked by the informal extension"
    return chooseOutput cfg.outputMode (renderDecl declName entry) (entryJson entry)
  | CliCommand.locations =>
    return chooseOutput cfg.outputMode (renderLocationIndex entries) (locationIndexJson entries)
  | CliCommand.location =>
    let some location := cfg.location?
      | throwError "missing location"
    return chooseOutput cfg.outputMode (renderLocationLookup entries location.name) (locationLookupJson entries location.name)
  | CliCommand.metadata _ =>
    throwError "internal error: metadata command dispatched as tracked command"

private def ensureLocationMarkdown (location : LocationId) : IO Unit := do
  match ← location.ensureMarkdownExists with
  | .ok () =>
    pure ()
  | .error err =>
    throw <| IO.userError err

private def loadLocationMetadata (location : LocationId) : IO LoadedMetadata := do
  ensureLocationMarkdown location
  match ← loadEffectiveMetadata location with
  | .ok loaded =>
    pure loaded
  | .error err =>
    throw <| IO.userError err

private def persistLocationMetadata
    (location : LocationId)
    (metadata : Metadata) : IO LoadedMetadata := do
  match ← writeMetadata location metadata with
  | .ok () =>
    pure {
      metadata,
      origin := .file
    }
  | .error err =>
    throw <| IO.userError err

private def metadataEnvelopeJson
    (location : LocationId)
    (loaded : LoadedMetadata) : Json :=
  Json.mkObj [
    ("location", toJson location),
    ("markdownPath", .str (toString (LocationId.markdownPath location))),
    ("metadataPath", .str (toString (LocationId.metadataPath location))),
    ("metadataOrigin", toJson loaded.origin),
    ("metadata", toJson loaded.metadata)
  ]

private def metadataEnvelopeText
    (location : LocationId)
    (loaded : LoadedMetadata) : String :=
  "\n".intercalate [
    s!"Location: {location}",
    s!"markdown-path: {LocationId.markdownPath location}",
    s!"metadata-path: {LocationId.metadataPath location}",
    s!"metadata-origin: {loaded.origin}",
    Metadata.renderSummary loaded.metadata
  ]

private def metadataActionJson
    (action : String)
    (location : LocationId)
    (loaded : LoadedMetadata)
    (extra : Array (String × Json) := #[]) : Json :=
  Json.mkObj <| ([
    ("action", .str action),
    ("location", toJson location),
    ("markdownPath", .str (toString (LocationId.markdownPath location))),
    ("metadataPath", .str (toString (LocationId.metadataPath location))),
    ("metadataOrigin", toJson loaded.origin),
    ("metadata", toJson loaded.metadata)
  ] ++ extra.toList)

private def metadataActionText
    (action : String)
    (location : LocationId)
    (loaded : LoadedMetadata)
    (extra : List String := []) : String :=
  "\n".intercalate <| [
    s!"action: {action}",
    s!"location: {location}",
    s!"markdown-path: {LocationId.markdownPath location}",
    s!"metadata-path: {LocationId.metadataPath location}",
    s!"metadata-origin: {loaded.origin}"
  ] ++ extra ++ [Metadata.renderSummary loaded.metadata]

private def updateMetadata
    (location : LocationId)
    (f : Metadata → Except String Metadata) : IO LoadedMetadata := do
  let loaded ← loadLocationMetadata location
  let metadata ←
    match f loaded.metadata with
    | .ok metadata =>
      pure metadata
    | .error err =>
      throw <| IO.userError err
  persistLocationMetadata location metadata

private def removeAllEq [BEq α] (xs : Array α) (target : α) : Array α :=
  xs.filter (· != target)

private def addUnique [BEq α] (xs : Array α) (value : α) : Array α :=
  if xs.contains value then xs else xs.push value

private def removeSourceMatches
    (metadata : Metadata)
    (sourceId : String)
    (locator? : Option String) : Metadata :=
  let sources := metadata.sources.filter fun source =>
    if source.sourceId != sourceId then
      true
    else
      match locator? with
      | some locator =>
        source.locator? != some locator
      | none =>
        false
  { metadata with sources }

private def addIssueOrError
    (metadata : Metadata)
    (issue : WorkflowIssue) : Except String Metadata := do
  if metadata.issues.any (·.id == issue.id) then
    throw s!"issue `{issue.id}` already exists"
  return { metadata with issues := metadata.issues.push issue }

private def ensureParentMarkdown (location : LocationId) : IO Unit :=
  ensureLocationMarkdown location

private def runMetadataCommand (cfg : Config) : IO RenderedOutput := do
  let some location := cfg.location?
    | throw <| IO.userError "missing location"
  let action ←
    match requireMetaAction cfg.command with
    | .ok action =>
      pure action
    | .error err =>
      throw <| IO.userError err
  let emit := fun plain json => chooseOutput cfg.outputMode plain json
  match action with
  | .show =>
    let loaded ← loadLocationMetadata location
    return emit (metadataEnvelopeText location loaded) (metadataEnvelopeJson location loaded)
  | .validate =>
    let loaded ← loadLocationMetadata location
    return emit
      ("\n".intercalate [metadataEnvelopeText location loaded, "validation: ok"])
      (metadataActionJson "validate" location loaded #[("valid", toJson true)])
  | .init =>
    ensureLocationMarkdown location
    let pathExists ← (LocationId.metadataPath location).pathExists
    if pathExists then
      let loaded ← loadLocationMetadata location
      return emit
        (metadataActionText "init" location loaded ["created: false"])
        (metadataActionJson "init" location loaded #[("created", toJson false)])
    else
      let loaded ← persistLocationMetadata location Metadata.default
      return emit
        (metadataActionText "init" location loaded ["created: true"])
        (metadataActionJson "init" location loaded #[("created", toJson true)])
  | .setStatus =>
    let some status := cfg.status?
      | throw <| IO.userError "missing status"
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with status }
    return emit
      (metadataActionText "set-status" location loaded)
      (metadataActionJson "set-status" location loaded)
  | .setParent =>
    let some parent := cfg.parent?
      | throw <| IO.userError "missing parent"
    ensureParentMarkdown parent
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with parent? := some parent }
    return emit
      (metadataActionText "set-parent" location loaded)
      (metadataActionJson "set-parent" location loaded)
  | .clearParent =>
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with parent? := none }
    return emit
      (metadataActionText "clear-parent" location loaded)
      (metadataActionJson "clear-parent" location loaded)
  | .setKind =>
    let some kind := cfg.kind?
      | throw <| IO.userError "missing kind"
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with kind? := some kind }
    return emit
      (metadataActionText "set-kind" location loaded)
      (metadataActionJson "set-kind" location loaded)
  | .clearKind =>
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with kind? := none }
    return emit
      (metadataActionText "clear-kind" location loaded)
      (metadataActionJson "clear-kind" location loaded)
  | .addTag =>
    let some tag := cfg.tag?
      | throw <| IO.userError "missing tag"
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with tags := addUnique metadata.tags tag }
    return emit
      (metadataActionText "add-tag" location loaded)
      (metadataActionJson "add-tag" location loaded)
  | .removeTag =>
    let some tag := cfg.tag?
      | throw <| IO.userError "missing tag"
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with tags := removeAllEq metadata.tags tag }
    return emit
      (metadataActionText "remove-tag" location loaded)
      (metadataActionJson "remove-tag" location loaded)
  | .addKnowledgeRef =>
    let some ref := cfg.knowledgeRef?
      | throw <| IO.userError "missing knowledge ref"
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with knowledgeRefs := addUnique metadata.knowledgeRefs ref }
    return emit
      (metadataActionText "add-knowledge-ref" location loaded)
      (metadataActionJson "add-knowledge-ref" location loaded)
  | .removeKnowledgeRef =>
    let some ref := cfg.knowledgeRef?
      | throw <| IO.userError "missing knowledge ref"
    let loaded ← updateMetadata location fun metadata =>
      pure { metadata with knowledgeRefs := removeAllEq metadata.knowledgeRefs ref }
    return emit
      (metadataActionText "remove-knowledge-ref" location loaded)
      (metadataActionJson "remove-knowledge-ref" location loaded)
  | .addSource =>
    let some sourceId := cfg.sourceId?
      | throw <| IO.userError "missing source id"
    let source ←
      match SourceRef.normalize {
        sourceId,
        anchors := cfg.sourceAnchors,
        locator? := cfg.sourceLocator?,
        role? := cfg.sourceRole?
      } with
      | .ok source =>
        pure source
      | .error err =>
        throw <| IO.userError err
    let loaded ← updateMetadata location fun metadata =>
      pure {
        metadata with
        sources := addUnique metadata.sources source
      }
    return emit
      (metadataActionText "add-source" location loaded)
      (metadataActionJson "add-source" location loaded)
  | .removeSource =>
    let some sourceId := cfg.sourceId?
      | throw <| IO.userError "missing source id"
    let loaded ← updateMetadata location fun metadata =>
      pure <| removeSourceMatches metadata sourceId cfg.sourceLocator?
    return emit
      (metadataActionText "remove-source" location loaded)
      (metadataActionJson "remove-source" location loaded)
  | .addIssue =>
    let some issueId := cfg.issueId?
      | throw <| IO.userError "missing issue id"
    let some issueKind := cfg.issueKind?
      | throw <| IO.userError "missing issue kind"
    let some issueNote := cfg.issueNote?
      | throw <| IO.userError "missing issue note"
    let issue ←
      match WorkflowIssue.normalize {
        id := issueId,
        kind := issueKind,
        refs := cfg.issueRefs,
        note := issueNote
      } with
      | .ok issue =>
        pure issue
      | .error err =>
        throw <| IO.userError err
    let loaded ← updateMetadata location fun metadata =>
      addIssueOrError metadata issue
    return emit
      (metadataActionText "add-issue" location loaded)
      (metadataActionJson "add-issue" location loaded)
  | .removeIssue =>
    let some issueId := cfg.issueId?
      | throw <| IO.userError "missing issue id"
    let loaded ← updateMetadata location fun metadata =>
      pure {
        metadata with
        issues := metadata.issues.filter (·.id != issueId)
      }
    return emit
      (metadataActionText "remove-issue" location loaded)
      (metadataActionJson "remove-issue" location loaded)

private unsafe def importEnvironment (modules : Array Name) : IO Environment := do
  let sysroot ← Lean.findSysroot
  Lean.initSearchPath sysroot
  Lean.enableInitializersExecution
  let imports := modules.map fun moduleName => ({ module := moduleName : Import })
  Lean.importModules imports {} (loadExts := true)

initialize importedEnvCache : IO.Ref (Std.HashMap (Array Name) Environment) ← IO.mkRef {}

private unsafe def cachedEnvironment (modules : Array Name) : IO Environment := do
  let cache ← importedEnvCache.get
  match cache.get? modules with
  | some env =>
    pure env
  | none =>
    let env ← importEnvironment modules
    importedEnvCache.modify fun cache => cache.insert modules env
    pure env

private def runCoreInEnv (env : Environment) (x : CoreM RenderedOutput) : IO RenderedOutput := do
  let ctx : Core.Context := {
    fileName := "<informalize-cli>"
    fileMap := FileMap.ofString ""
    options := {}
  }
  let state : Core.State := { env := env }
  x.toIO' ctx state

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
      let output ←
        if isMetaCommand cfg.command then
          runMetadataCommand cfg
        else do
          let env ← unsafe cachedEnvironment cfg.modules
          runCoreInEnv env (runTrackedCommand cfg)
      return {
        exitCode := 0
        stdout := output.render
      }
    catch ex =>
      return {
        exitCode := 1
        stderr := s!"error: {ex}"
      }

end Informalize.Cli
