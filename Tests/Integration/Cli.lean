import Informalize.Cli
import Tests.Integration.Deps
import Tests.Integration.Imports.Top

namespace Tests.Integration.Cli

private def failNow (label message : String) : IO α :=
  throw <| IO.userError s!"{label}: {message}"

private def assertContains (label output needle : String) : IO Unit := do
  unless output.contains needle do
    failNow label s!"expected output to contain `{needle}`"

private def assertNotContains (label output needle : String) : IO Unit := do
  if output.contains needle then
    failNow label s!"expected output to not contain `{needle}`"

private def assertExitCode
    (label : String)
    (result : Informalize.Cli.InvocationResult)
    (expected : UInt32) : IO Unit := do
  unless result.exitCode == expected do
    failNow label s!"expected exit code {expected}, got {result.exitCode}"

private def assertPathExists (label : String) (path : System.FilePath) : IO Unit := do
  unless (← path.pathExists) do
    failNow label s!"expected path to exist: {path}"

private def assertPathMissing (label : String) (path : System.FilePath) : IO Unit := do
  if (← path.pathExists) then
    failNow label s!"expected path to be absent: {path}"

private def importsTop : Array String :=
  #["--module", "Tests.Integration.Imports.Top"]

private def importsDeps : Array String :=
  #["--module", "Tests.Integration.Deps"]

private def invokeWithTop (commandArgs : Array String) : IO Informalize.Cli.InvocationResult := do
  Informalize.Cli.invoke (commandArgs ++ importsTop)

private def invokeWithDeps (commandArgs : Array String) : IO Informalize.Cli.InvocationResult := do
  Informalize.Cli.invoke (commandArgs ++ importsDeps)

private def runtimeMetadataPath : System.FilePath :=
  System.FilePath.mk "informal/TestRuntime/metaDemo.json"

private def cleanupRuntimeMetadata : IO Unit := do
  if (← runtimeMetadataPath.pathExists) then
    IO.FS.removeFile runtimeMetadataPath

private def withCleanRuntimeMetadata (action : IO Unit) : IO Unit := do
  cleanupRuntimeMetadata
  try
    action
  finally
    cleanupRuntimeMetadata

private def runHelpCase : IO Unit := do
  let help ← Informalize.Cli.invoke #["--help"]
  assertExitCode "help" help 0
  assertContains "help" help.stdout "Informalize CLI"
  assertContains "help" help.stdout "status"
  assertContains "help" help.stdout "deps"
  assertContains "help" help.stdout "meta show"

private def runMissingModuleCase : IO Unit := do
  let missingModule ← Informalize.Cli.invoke #["status"]
  assertExitCode "missing module" missingModule 1
  assertContains "missing module" missingModule.stderr "missing required option `--module <Module.Name>`"

private def runUnknownCommandCase : IO Unit := do
  let unknownCommand ← Informalize.Cli.invoke #["bogus", "--module", "Tests.Integration.Imports.Top"]
  assertExitCode "unknown command" unknownCommand 1
  assertContains "unknown command" unknownCommand.stderr "unknown command `bogus`"

private def runStatusCase : IO Unit := do
  let status ← invokeWithTop #["status"]
  assertExitCode "status" status 0
  assertContains "status" status.stdout "tracked declarations: 6"
  assertContains "status" status.stdout "declarations with locations: 3"
  assertContains "status" status.stdout "declarations with empty locations: 3"
  assertContains "status" status.stdout "unique markdown locations: 3"

private def runTopDepsCase : IO Unit := do
  let topDeps ← invokeWithTop #["deps"]
  assertExitCode "top deps" topDeps 0
  assertContains "top deps" topDeps.stdout "Dependencies (6):"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Mid.midLoc -> Tests.Integration.Imports.Base.baseLoc"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Top.topLoc -> Tests.Integration.Imports.Base.baseLoc, Tests.Integration.Imports.Mid.midLoc"
  assertContains "top deps" topDeps.stdout "Leaves (2):"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Base.baseLoc"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Base.baseBare"

private def runTopLocationDepsCase : IO Unit := do
  let topDeps ← invokeWithTop #["deps", "--by", "location"]
  assertExitCode "top location deps" topDeps 0
  assertContains "top location deps" topDeps.stdout "Location dependencies (3):"
  assertContains "top location deps" topDeps.stdout "Alpha.root.child.grandchild -> Foo.bar, Foo.bar.baz"
  assertContains "top location deps" topDeps.stdout "Foo.bar -> (none)"
  assertContains "top location deps" topDeps.stdout "Foo.bar.baz -> Foo.bar"
  assertContains "top location deps" topDeps.stdout "Leaves (1):"
  assertContains "top location deps" topDeps.stdout "Foo.bar"

private def runDepsCase : IO Unit := do
  let deps ← invokeWithDeps #["deps"]
  assertExitCode "deps" deps 0
  assertContains "deps" deps.stdout "Dependencies (3):"
  assertContains "deps" deps.stdout "Tests.Integration.Deps.first -> (none)"
  assertContains "deps" deps.stdout "Tests.Integration.Deps.last -> Tests.Integration.Deps.first"
  assertContains "deps" deps.stdout "Tests.Integration.Deps.isolated -> (none)"
  assertNotContains "deps" deps.stdout "Tests.Integration.Deps.step1"
  assertNotContains "deps" deps.stdout "Tests.Integration.Deps.step4"
  assertContains "deps" deps.stdout "Leaves (2):"
  assertContains "deps" deps.stdout "Tests.Integration.Deps.first"
  assertContains "deps" deps.stdout "Tests.Integration.Deps.isolated"

private def runDeclsCase : IO Unit := do
  let decls ← invokeWithTop #["decls"]
  assertExitCode "decls" decls 0
  assertContains "decls" decls.stdout "Tracked declarations (6):"
  assertContains "decls" decls.stdout "Tests.Integration.Imports.Base.baseLoc"
  assertContains "decls" decls.stdout "Foo.bar"

private def runDeclsBareOnlyCase : IO Unit := do
  let bareOnly ← invokeWithTop #["decls", "--bare-only"]
  assertExitCode "decls bare-only" bareOnly 0
  assertContains "decls bare-only" bareOnly.stdout "Tracked declarations with empty locations (3):"
  assertContains "decls bare-only" bareOnly.stdout "Tests.Integration.Imports.Base.baseBare"
  assertContains "decls bare-only" bareOnly.stdout "Tests.Integration.Imports.Top.topBare"
  assertNotContains "decls bare-only" bareOnly.stdout "Tests.Integration.Imports.Base.baseLoc"

private def runDeclsWithLocationsCase : IO Unit := do
  let withLocations ← invokeWithTop #["decls", "--with-locations"]
  assertExitCode "decls with-locations" withLocations 0
  assertContains "decls with-locations" withLocations.stdout "Tracked declarations with locations (3):"
  assertContains "decls with-locations" withLocations.stdout "Tests.Integration.Imports.Base.baseLoc"
  assertContains "decls with-locations" withLocations.stdout "Tests.Integration.Imports.Top.topLoc"
  assertNotContains "decls with-locations" withLocations.stdout "Tests.Integration.Imports.Base.baseBare"

private def runDeclsConflictingFiltersCase : IO Unit := do
  let badFilter ← invokeWithTop #["decls", "--bare-only", "--with-locations"]
  assertExitCode "decls conflicting filters" badFilter 1
  assertContains "decls conflicting filters" badFilter.stderr "cannot be combined"

private def runDeclCase : IO Unit := do
  let decl ← invokeWithTop #[
    "decl",
    "--decl", "Tests.Integration.Imports.Mid.midLoc"
  ]
  assertExitCode "decl" decl 0
  assertContains "decl" decl.stdout "Declaration: Tests.Integration.Imports.Mid.midLoc"
  assertContains "decl" decl.stdout "location-count: 1"
  assertContains "decl" decl.stdout "Foo.bar.baz"

private def runDeclMissingOptionCase : IO Unit := do
  let missingDecl ← invokeWithTop #["decl"]
  assertExitCode "decl missing option" missingDecl 1
  assertContains "decl missing option" missingDecl.stderr "missing required option `--decl <Decl.Name>`"

private def runDeclUnknownCase : IO Unit := do
  let unknownDecl ← invokeWithTop #[
    "decl",
    "--decl", "Tests.Integration.Imports.Top.notTracked"
  ]
  assertExitCode "decl unknown" unknownDecl 1
  assertContains "decl unknown" unknownDecl.stderr "is not tracked by the informal extension"

private def runLocationsCase : IO Unit := do
  let locations ← invokeWithTop #["locations"]
  assertExitCode "locations" locations 0
  assertContains "locations" locations.stdout "Locations (3):"
  assertContains "locations" locations.stdout "Foo.bar"
  assertContains "locations" locations.stdout "Foo.bar.baz"
  assertContains "locations" locations.stdout "Alpha.root.child.grandchild"

private def runLocationFooBarCase : IO Unit := do
  let locationFooBar ← invokeWithTop #["location", "--location", "Foo.bar"]
  assertExitCode "location Foo.bar" locationFooBar 0
  assertContains "location Foo.bar" locationFooBar.stdout "Location Foo.bar (1):"
  assertContains "location Foo.bar" locationFooBar.stdout "Tests.Integration.Imports.Base.baseLoc"

private def runLocationMissingCase : IO Unit := do
  let locationMissing ← invokeWithTop #["location", "--location", "Foo.missing"]
  assertExitCode "location missing" locationMissing 0
  assertContains "location missing" locationMissing.stdout "Location Foo.missing (0):"

private def runStatusBadFlagCase : IO Unit := do
  let badFlag ← invokeWithTop #["status", "--decl", "Tests.Integration.Imports.Top.topLoc"]
  assertExitCode "status bad flag" badFlag 1
  assertContains "status bad flag" badFlag.stderr "`--decl` is only valid for the `decl` command"

private def runMetaShowDefaultCase : IO Unit := do
  let showDefault ← Informalize.Cli.invoke #["meta", "show", "--location", "Foo.bar.baz"]
  assertExitCode "meta show default" showDefault 0
  assertContains "meta show default" showDefault.stdout "metadata-origin: default"
  assertContains "meta show default" showDefault.stdout "status: scaffolded"

private def runMetaShowFileBackedCase : IO Unit := do
  let showFile ← Informalize.Cli.invoke #["meta", "show", "--location", "Foo.bar"]
  assertExitCode "meta show file" showFile 0
  assertContains "meta show file" showFile.stdout "metadata-origin: file"
  assertContains "meta show file" showFile.stdout "status: ready"
  assertContains "meta show file" showFile.stdout "knowledge-ref-items: kb.fixture.foo_bar"

private def runMetaShowJsonCase : IO Unit := do
  let showJson ← Informalize.Cli.invoke #["meta", "show", "--location", "Foo.bar", "--json"]
  assertExitCode "meta show json" showJson 0
  assertContains "meta show json" showJson.stdout "\"metadataOrigin\": \"file\""
  assertContains "meta show json" showJson.stdout "\"status\": \"ready\""

private def runMetaValidateBadCase : IO Unit := do
  let validateBad ← Informalize.Cli.invoke #["meta", "validate", "--location", "Bad.metadata"]
  assertExitCode "meta validate bad" validateBad 1
  assertContains "meta validate bad" validateBad.stderr "invalid metadata in `informal/Bad/metadata.json`"
  assertContains "meta validate bad" validateBad.stderr "totally_bogus"

private def runMetaInitCase : IO Unit := do
  withCleanRuntimeMetadata do
    let before ← Informalize.Cli.invoke #["meta", "show", "--location", "TestRuntime.metaDemo"]
    assertExitCode "meta init before show" before 0
    assertContains "meta init before show" before.stdout "metadata-origin: default"
    assertPathMissing "meta init before show" runtimeMetadataPath

    let init1 ← Informalize.Cli.invoke #["meta", "init", "--location", "TestRuntime.metaDemo"]
    assertExitCode "meta init first" init1 0
    assertContains "meta init first" init1.stdout "created: true"
    assertPathExists "meta init first" runtimeMetadataPath

    let init2 ← Informalize.Cli.invoke #["meta", "init", "--location", "TestRuntime.metaDemo"]
    assertExitCode "meta init second" init2 0
    assertContains "meta init second" init2.stdout "created: false"

private def runMetaMutationCase : IO Unit := do
  withCleanRuntimeMetadata do
    let setStatus ← Informalize.Cli.invoke #[
      "meta", "set-status",
      "--location", "TestRuntime.metaDemo",
      "--status", "ready"
    ]
    assertExitCode "meta set-status" setStatus 0
    assertContains "meta set-status" setStatus.stdout "action: set-status"
    assertContains "meta set-status" setStatus.stdout "status: ready"
    assertPathExists "meta set-status" runtimeMetadataPath

    let addTag ← Informalize.Cli.invoke #[
      "meta", "add-tag",
      "--location", "TestRuntime.metaDemo",
      "--tag", "runtime"
    ]
    assertExitCode "meta add-tag" addTag 0
    assertContains "meta add-tag" addTag.stdout "tags: 1"

    let addSource ← Informalize.Cli.invoke #[
      "meta", "add-source",
      "--location", "TestRuntime.metaDemo",
      "--source-id", "runtime.paper",
      "--anchor", "Thm. 1",
      "--role", "primary"
    ]
    assertExitCode "meta add-source" addSource 0
    assertContains "meta add-source" addSource.stdout "sources: 1"

    let addIssue ← Informalize.Cli.invoke #[
      "meta", "add-issue",
      "--location", "TestRuntime.metaDemo",
      "--id", "runtime-gap",
      "--kind", "source",
      "--note", "Need one more source anchor.",
      "--ref", "runtime.paper"
    ]
    assertExitCode "meta add-issue" addIssue 0
    assertContains "meta add-issue" addIssue.stdout "issues: 1"

    let setParent ← Informalize.Cli.invoke #[
      "meta", "set-parent",
      "--location", "TestRuntime.metaDemo",
      "--parent", "Foo.bar"
    ]
    assertExitCode "meta set-parent" setParent 0
    assertContains "meta set-parent" setParent.stdout "parent: Foo.bar"

    let showJson ← Informalize.Cli.invoke #[
      "meta", "show",
      "--location", "TestRuntime.metaDemo",
      "--json"
    ]
    assertExitCode "meta show runtime json" showJson 0
    assertContains "meta show runtime json" showJson.stdout "\"metadataOrigin\": \"file\""
    assertContains "meta show runtime json" showJson.stdout "\"status\": \"ready\""
    assertContains "meta show runtime json" showJson.stdout "\"parent\": \"Foo.bar\""
    assertContains "meta show runtime json" showJson.stdout "\"runtime-gap\""

    let onDisk ← IO.FS.readFile runtimeMetadataPath
    assertContains "meta mutation file" onDisk "\"status\": \"ready\""
    assertContains "meta mutation file" onDisk "\"parent\": \"Foo.bar\""
    assertContains "meta mutation file" onDisk "\"runtime\""
    assertContains "meta mutation file" onDisk "\"runtime.paper\""

    let removeIssue ← Informalize.Cli.invoke #[
      "meta", "remove-issue",
      "--location", "TestRuntime.metaDemo",
      "--id", "runtime-gap"
    ]
    assertExitCode "meta remove-issue" removeIssue 0
    assertContains "meta remove-issue" removeIssue.stdout "issues: 0"

    let removeTag ← Informalize.Cli.invoke #[
      "meta", "remove-tag",
      "--location", "TestRuntime.metaDemo",
      "--tag", "runtime"
    ]
    assertExitCode "meta remove-tag" removeTag 0
    assertContains "meta remove-tag" removeTag.stdout "tags: 0"

    let clearParent ← Informalize.Cli.invoke #[
      "meta", "clear-parent",
      "--location", "TestRuntime.metaDemo"
    ]
    assertExitCode "meta clear-parent" clearParent 0
    assertContains "meta clear-parent" clearParent.stdout "parent: (none)"

private def runStep (label : String) (action : IO Unit) : IO Unit := do
  IO.println s!"[cli-tests] start {label}"
  action
  IO.println s!"[cli-tests] ok {label}"


def run : IO Unit := do
  runStep "help" runHelpCase
  runStep "missing-module" runMissingModuleCase
  runStep "unknown-command" runUnknownCommandCase
  runStep "status" runStatusCase
  runStep "top-deps" runTopDepsCase
  runStep "top-location-deps" runTopLocationDepsCase
  runStep "deps" runDepsCase
  runStep "decls" runDeclsCase
  runStep "decls-bare-only" runDeclsBareOnlyCase
  runStep "decls-with-locations" runDeclsWithLocationsCase
  runStep "decls-conflicting-filters" runDeclsConflictingFiltersCase
  runStep "decl" runDeclCase
  runStep "decl-missing-option" runDeclMissingOptionCase
  runStep "decl-unknown" runDeclUnknownCase
  runStep "locations" runLocationsCase
  runStep "location-foo-bar" runLocationFooBarCase
  runStep "location-missing" runLocationMissingCase
  runStep "status-bad-flag" runStatusBadFlagCase
  runStep "meta-show-default" runMetaShowDefaultCase
  runStep "meta-show-file-backed" runMetaShowFileBackedCase
  runStep "meta-show-json" runMetaShowJsonCase
  runStep "meta-validate-bad" runMetaValidateBadCase
  runStep "meta-init" runMetaInitCase
  runStep "meta-mutation" runMetaMutationCase

end Tests.Integration.Cli
