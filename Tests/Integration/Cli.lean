import Informalize.Cli
import Tests.Integration.Deps
import Tests.Integration.Imports.Top

open Lean Elab Command

private def assertContains (label output needle : String) : CommandElabM Unit := do
  unless output.contains needle do
    throwError s!"{label}: expected output to contain `{needle}`"

private def assertNotContains (label output needle : String) : CommandElabM Unit := do
  if output.contains needle then
    throwError s!"{label}: expected output to not contain `{needle}`"

private def assertExitCode
    (label : String)
    (result : Informalize.Cli.InvocationResult)
    (expected : UInt32) : CommandElabM Unit := do
  unless result.exitCode == expected do
    throwError s!"{label}: expected exit code {expected}, got {result.exitCode}"

private def importsTop : Array String :=
  #["--module", "Tests.Integration.Imports.Top"]

private def importsDeps : Array String :=
  #["--module", "Tests.Integration.Deps"]

private def invokeWithTop (commandArgs : Array String) : IO Informalize.Cli.InvocationResult := do
  Informalize.Cli.invoke (commandArgs ++ importsTop)

private def invokeWithDeps (commandArgs : Array String) : IO Informalize.Cli.InvocationResult := do
  Informalize.Cli.invoke (commandArgs ++ importsDeps)

run_cmd do
  let help := ← liftIO <| Informalize.Cli.invoke #["--help"]
  assertExitCode "help" help 0
  assertContains "help" help.stdout "Informalize CLI"
  assertContains "help" help.stdout "status"
  assertContains "help" help.stdout "deps"
  assertContains "help" help.stdout "decls"
  assertContains "help" help.stdout "locations"

run_cmd do
  let missingModule := ← liftIO <| Informalize.Cli.invoke #["status"]
  assertExitCode "missing module" missingModule 1
  assertContains "missing module" missingModule.stderr "missing required option `--module <Module.Name>`"

run_cmd do
  let unknownCommand := ← liftIO <| Informalize.Cli.invoke #["bogus", "--module", "Tests.Integration.Imports.Top"]
  assertExitCode "unknown command" unknownCommand 1
  assertContains "unknown command" unknownCommand.stderr "unknown command `bogus`"

run_cmd do
  let status := ← liftIO <| invokeWithTop #["status"]
  assertExitCode "status" status 0
  assertContains "status" status.stdout "tracked declarations: 6"
  assertContains "status" status.stdout "declarations with locations: 3"
  assertContains "status" status.stdout "declarations with empty locations: 3"
  assertContains "status" status.stdout "unique markdown locations: 3"

run_cmd do
  let topDeps := ← liftIO <| invokeWithTop #["deps"]
  assertExitCode "top deps" topDeps 0
  assertContains "top deps" topDeps.stdout "Dependencies (6):"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Mid.midLoc -> Tests.Integration.Imports.Base.baseLoc"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Top.topLoc -> Tests.Integration.Imports.Base.baseLoc, Tests.Integration.Imports.Mid.midLoc"
  assertContains "top deps" topDeps.stdout "Leaves (2):"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Base.baseLoc"
  assertContains "top deps" topDeps.stdout "Tests.Integration.Imports.Base.baseBare"

run_cmd do
  let deps := ← liftIO <| invokeWithDeps #["deps"]
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

run_cmd do
  let decls := ← liftIO <| invokeWithTop #["decls"]
  assertExitCode "decls" decls 0
  assertContains "decls" decls.stdout "Tracked declarations (6):"
  assertContains "decls" decls.stdout "Tests.Integration.Imports.Base.baseLoc"
  assertContains "decls" decls.stdout "Foo.bar"

run_cmd do
  let bareOnly := ← liftIO <| invokeWithTop #["decls", "--bare-only"]
  assertExitCode "decls bare-only" bareOnly 0
  assertContains "decls bare-only" bareOnly.stdout "Tracked declarations with empty locations (3):"
  assertContains "decls bare-only" bareOnly.stdout "Tests.Integration.Imports.Base.baseBare"
  assertContains "decls bare-only" bareOnly.stdout "Tests.Integration.Imports.Top.topBare"
  assertNotContains "decls bare-only" bareOnly.stdout "Tests.Integration.Imports.Base.baseLoc"

run_cmd do
  let withLocations := ← liftIO <| invokeWithTop #["decls", "--with-locations"]
  assertExitCode "decls with-locations" withLocations 0
  assertContains "decls with-locations" withLocations.stdout "Tracked declarations with locations (3):"
  assertContains "decls with-locations" withLocations.stdout "Tests.Integration.Imports.Base.baseLoc"
  assertContains "decls with-locations" withLocations.stdout "Tests.Integration.Imports.Top.topLoc"
  assertNotContains "decls with-locations" withLocations.stdout "Tests.Integration.Imports.Base.baseBare"

run_cmd do
  let badFilter := ← liftIO <| invokeWithTop #["decls", "--bare-only", "--with-locations"]
  assertExitCode "decls conflicting filters" badFilter 1
  assertContains "decls conflicting filters" badFilter.stderr "cannot be combined"

run_cmd do
  let decl := ← liftIO <| invokeWithTop #[
    "decl",
    "--decl", "Tests.Integration.Imports.Mid.midLoc"
  ]
  assertExitCode "decl" decl 0
  assertContains "decl" decl.stdout "Declaration: Tests.Integration.Imports.Mid.midLoc"
  assertContains "decl" decl.stdout "location-count: 1"
  assertContains "decl" decl.stdout "Foo.bar.baz"

run_cmd do
  let missingDecl := ← liftIO <| invokeWithTop #["decl"]
  assertExitCode "decl missing option" missingDecl 1
  assertContains "decl missing option" missingDecl.stderr "missing required option `--decl <Decl.Name>`"

run_cmd do
  let unknownDecl := ← liftIO <| invokeWithTop #[
    "decl",
    "--decl", "Tests.Integration.Imports.Top.notTracked"
  ]
  assertExitCode "decl unknown" unknownDecl 1
  assertContains "decl unknown" unknownDecl.stderr "is not tracked by the informal extension"

run_cmd do
  let locations := ← liftIO <| invokeWithTop #["locations"]
  assertExitCode "locations" locations 0
  assertContains "locations" locations.stdout "Locations (3):"
  assertContains "locations" locations.stdout "Foo.bar"
  assertContains "locations" locations.stdout "Foo.bar.baz"
  assertContains "locations" locations.stdout "Alpha.root.child.grandchild"

run_cmd do
  let locationFooBar := ← liftIO <| invokeWithTop #["location", "--location", "Foo.bar"]
  assertExitCode "location Foo.bar" locationFooBar 0
  assertContains "location Foo.bar" locationFooBar.stdout "Location Foo.bar (1):"
  assertContains "location Foo.bar" locationFooBar.stdout "Tests.Integration.Imports.Base.baseLoc"

run_cmd do
  let locationMissing := ← liftIO <| invokeWithTop #["location", "--location", "Foo.missing"]
  assertExitCode "location missing" locationMissing 0
  assertContains "location missing" locationMissing.stdout "Location Foo.missing (0):"

run_cmd do
  let badFlag := ← liftIO <| invokeWithTop #["status", "--decl", "Tests.Integration.Imports.Top.topLoc"]
  assertExitCode "status bad flag" badFlag 1
  assertContains "status bad flag" badFlag.stderr "`--decl` is only valid for the `decl` command"
