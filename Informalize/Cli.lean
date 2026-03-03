module

public import Lean
public import Informalize.Extension

public section

open Lean

namespace Informalize.Cli

inductive Command where
  | status
  | deps
  | decls
  | decl
  | locations
  | location
  deriving Inhabited, Repr, BEq

inductive DeclsFilter where
  | all
  | bareOnly
  | withLocations
  deriving Inhabited, Repr, BEq

structure Config where
  command : Command
  modules : Array Name
  declName? : Option Name := none
  locationName? : Option Name := none
  declsFilter : DeclsFilter := .all
  deriving Inhabited, Repr

structure InvocationResult where
  exitCode : UInt32
  stdout : String := ""
  stderr : String := ""
  deriving Inhabited, Repr

def usage : String :=
  "\n".intercalate [
    "Informalize CLI",
    "",
    "Usage:",
    "  lake exe informalize <command> --module <Module.Name> [options]",
    "",
    "Commands:",
    "  status                 Show summary of tracked declarations and locations",
    "  deps                   Show transitive dependencies and dependency leaves",
    "  decls                  List tracked declarations",
    "  decl                   Show tracked locations for one declaration",
    "  locations              List markdown locations and referencing declarations",
    "  location               Show declarations referencing one markdown location",
    "",
    "Required:",
    "  -m, --module <Module>  Import module before running command (repeatable)",
    "",
    "Options:",
    "  --decl <Decl.Name>     Required for `decl`",
    "  --location <Location>  Required for `location`",
    "  --bare-only            Filter `decls` output to declarations with empty location sets",
    "  --with-locations       Filter `decls` output to declarations with non-empty location sets",
    "",
    "Examples:",
    "  lake exe informalize status --module Tests.Integration.Imports.Top",
    "  lake exe informalize deps --module Tests.Integration.Deps",
    "  lake exe informalize decls --module Tests.Integration.Imports.Top --with-locations",
    "  lake exe informalize decl --module Tests.Integration.Imports.Top --decl Tests.Integration.Imports.Base.baseLoc",
    "  lake exe informalize locations --module Tests.Integration.Imports.Top",
    "  lake exe informalize location --module Tests.Integration.Imports.Top --location Foo.bar"
  ]

private def parseDottedName (kind : String) (raw : String) : Except String Name := do
  let trimmed := raw.trimAscii.toString
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

private def parseLocationName (raw : String) : Except String Name :=
  parseDottedName "location" raw

private def parseCommand (raw : String) : Except String Command :=
  match raw with
  | "status" => .ok .status
  | "deps" => .ok .deps
  | "decls" => .ok .decls
  | "decl" => .ok .decl
  | "locations" => .ok .locations
  | "location" => .ok .location
  | other => .error s!"unknown command `{other}`"

private def validateConfig (cfg : Config) : Except String Config := do
  if cfg.modules.isEmpty then
    throw "missing required option `--module <Module.Name>`"
  match cfg.command with
  | .decl =>
    if cfg.declName?.isNone then
      throw "missing required option `--decl <Decl.Name>` for `decl`"
  | .location =>
    if cfg.locationName?.isNone then
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
  | "--module" :: moduleRaw :: rest =>
    parseOptions { cfg with modules := cfg.modules.push (← parseModuleName moduleRaw) } rest
  | "--module" :: [] =>
    throw "expected module name after `--module`"
  | "-m" :: moduleRaw :: rest =>
    parseOptions { cfg with modules := cfg.modules.push (← parseModuleName moduleRaw) } rest
  | "-m" :: [] =>
    throw "expected module name after `-m`"
  | "--decl" :: declRaw :: rest =>
    if cfg.command != .decl then
      throw "`--decl` is only valid for the `decl` command"
    else
      parseOptions { cfg with declName? := some (← parseDeclName declRaw) } rest
  | "--decl" :: [] =>
    throw "expected declaration name after `--decl`"
  | "--location" :: locationRaw :: rest =>
    if cfg.command != .location then
      throw "`--location` is only valid for the `location` command"
    else
      parseOptions { cfg with locationName? := some (← parseLocationName locationRaw) } rest
  | "--location" :: [] =>
    throw "expected location name after `--location`"
  | "--bare-only" :: rest =>
    if cfg.command != .decls then
      throw "`--bare-only` is only valid for the `decls` command"
    else if cfg.declsFilter == .withLocations then
      throw "`--bare-only` and `--with-locations` cannot be combined"
    else
      parseOptions { cfg with declsFilter := .bareOnly } rest
  | "--with-locations" :: rest =>
    if cfg.command != .decls then
      throw "`--with-locations` is only valid for the `decls` command"
    else if cfg.declsFilter == .bareOnly then
      throw "`--bare-only` and `--with-locations` cannot be combined"
    else
      parseOptions { cfg with declsFilter := .withLocations } rest
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
  | commandRaw :: rest =>
    parseOptions { command := (← parseCommand commandRaw), modules := #[] } rest

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
  | .all =>
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

private def sortedLocationRows
    (index : Std.HashMap Name (Array Name)) : Array (Name × Array Name) := Id.run do
  let mut rows : Array (Name × Array Name) := #[]
  for (location, decls) in index do
    rows := rows.push (location, decls.qsort Name.quickLt)
  return rows.qsort (fun a b => Name.quickLt a.1 b.1)

private def renderStatusSummary
    (entries : Array Informalize.InformalDeclEntry) : String :=
  let trackedDecls := entries.size
  let withLocations := entries.foldl (init := 0) fun count entry =>
    if locationCount entry.locations > 0 then
      count + 1
    else
      count
  let bareDecls := trackedDecls - withLocations
  let uniqueLocations := locationCount (collectUniqueLocations entries)
  "\n".intercalate [
    "Informal extension status:",
    s!"- tracked declarations: {trackedDecls}",
    s!"- declarations with locations: {withLocations}",
    s!"- declarations with empty locations: {bareDecls}",
    s!"- unique markdown locations: {uniqueLocations}"
  ]

private def renderDecls
    (entries : Array Informalize.InformalDeclEntry)
    (filter : DeclsFilter) : String :=
  let entries := filterDecls entries filter
  let header :=
    match filter with
    | .all =>
      s!"Tracked declarations ({entries.size}):"
    | .bareOnly =>
      s!"Tracked declarations with empty locations ({entries.size}):"
    | .withLocations =>
      s!"Tracked declarations with locations ({entries.size}):"
  if entries.isEmpty then
    header
  else
    "\n".intercalate (header :: (entries.map declLine).toList)

private def renderDecl
    (declName : Name)
    (entry : Informalize.InformalDeclEntry) : String :=
  let count := locationCount entry.locations
  let locations := nameSetToSortedArray entry.locations
  let lines := locations.map fun location => s!"- {location}"
  let locationSection :=
    if lines.isEmpty then
      ["- (none)"]
    else
      lines.toList
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

private def renderLocationLookup
    (entries : Array Informalize.InformalDeclEntry)
    (location : Name) : String :=
  let decls := (locationDeclIndex entries).getD location #[]
  let decls := decls.qsort Name.quickLt
  let header := s!"Location {location} ({decls.size}):"
  if decls.isEmpty then
    "\n".intercalate [header, "- (none)"]
  else
    "\n".intercalate (header :: (decls.map fun declName => s!"- {declName}").toList)

private def renderDependencies
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
    if leaves.isEmpty then
      ["- (none)"]
    else
      (leaves.map fun declName => s!"- {declName}").toList
  "\n".intercalate <|
    [
      s!"Dependencies ({depLines.size}):"
    ] ++ depLines.toList ++
    [
      "",
      s!"Leaves ({leaves.size}):"
    ] ++ leafLines

private def runCommand (cfg : Config) : CoreM String := do
  let entries ← Informalize.allInformalDeclEntries
  match cfg.command with
  | .status =>
    return renderStatusSummary entries
  | .deps =>
    return renderDependencies (← getEnv) entries
  | .decls =>
    return renderDecls entries cfg.declsFilter
  | .decl =>
    let some declName := cfg.declName?
      | return "error: missing declaration"
    let some entry ← Informalize.informalDeclEntry? declName
      | throwError s!"declaration `{declName}` is not tracked by the informal extension"
    return renderDecl declName entry
  | .locations =>
    return renderLocationIndex entries
  | .location =>
    let some locationName := cfg.locationName?
      | return "error: missing location"
    return renderLocationLookup entries locationName

private unsafe def importEnvironment (modules : Array Name) : IO Environment := do
  let sysroot ← Lean.findSysroot
  Lean.initSearchPath sysroot
  Lean.enableInitializersExecution
  let imports := modules.map fun moduleName => ({ module := moduleName : Import })
  Lean.importModules imports {} (loadExts := true)

private def runCoreInEnv (env : Environment) (x : CoreM String) : IO String := do
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
      let env ← unsafe importEnvironment cfg.modules
      let output ← runCoreInEnv env (runCommand cfg)
      return {
        exitCode := 0
        stdout := output
      }
    catch ex =>
      return {
        exitCode := 1
        stderr := s!"error: {ex}"
      }

end Informalize.Cli
