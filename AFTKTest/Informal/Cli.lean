module

public import AFTKTest.Informal.Assert
public import AFTKTest.Informal.Fixtures
public import Lean.Data.Json.Parser

public section


namespace AFTKTest.Informal.Cli

open Lean
open AFTKTest.Informal

private def cliStatusText : TestCase := {
  name := "informal.cli.statusText"
  run := do
    let out ← runInformalCli #["status", "--module", "AFTKTest.Informal.Fixtures.Basic"]
    assertEq out.exitCode 0
    assertContains out.stdout "Tracked declarations: 8"
    assertContains out.stdout "Tracked references: 5"
}

private def cliDeclsJson : TestCase := {
  name := "informal.cli.declsJson"
  run := do
    let out ← runInformalCli #["decls", "--module", "AFTKTest.Informal.Fixtures.Basic", "--format", "json"]
    assertEq out.exitCode 0
    let json ← assertJsonParses out.stdout
    let command : String ← match json.getObjVal? "command" >>= Json.getStr? with
      | .ok value => pure value
      | .error err => fail err
    assertEq command "decls"
    let entries : Array Json ← match json.getObjVal? "data" >>= (·.getObjVal? "entries") >>= Json.getArr? with
      | .ok entries => pure entries
      | .error err => fail err
    assertEq entries.size 8
}

private def cliDeclTargeted : TestCase := {
  name := "informal.cli.declTargeted"
  run := do
    let out ← runInformalCli #[
      "decl",
      "AFTKTest.Informal.Fixtures.Basic.multiRef",
      "--module", "AFTKTest.Informal.Fixtures.Basic"
    ]
    assertEq out.exitCode 0
    assertContains out.stdout "Declaration: AFTKTest.Informal.Fixtures.Basic.multiRef"
    assertContains out.stdout "group.basic.operation_note"
}

private def cliRefsText : TestCase := {
  name := "informal.cli.refsText"
  run := do
    let out ← runInformalCli #["refs", "--module", "AFTKTest.Informal.Fixtures.Basic", "--prefix", "group.basic"]
    assertEq out.exitCode 0
    assertContains out.stdout "group.basic.definition"
    assertContains out.stdout "group.basic.operation_note"
}

private def cliDepsJson : TestCase := {
  name := "informal.cli.depsJson"
  run := do
    let out ← runInformalCli #["deps", "--module", "AFTKTest.Informal.Fixtures.Imports.Top", "--by", "decl", "--format", "json"]
    assertEq out.exitCode 0
    let json ← assertJsonParses out.stdout
    let mode : String ← match json.getObjVal? "mode" >>= Json.getStr? with
      | .ok value => pure value
      | .error err => fail err
    assertEq mode "decl"
    let leaves : Array Json ← match json.getObjVal? "data" >>= (·.getObjVal? "leaves") >>= Json.getArr? with
      | .ok leaves => pure leaves
      | .error err => fail err
    assertEq leaves.size 1
    let leaf : String ← match leaves[0]!.getStr? with
      | .ok leaf => pure leaf
      | .error err => fail err
    assertEq leaf "AFTKTest.Informal.Fixtures.Imports.Base.baseTracked"
}

private def cliRefDepsLeaves : TestCase := {
  name := "informal.cli.refDepsLeaves"
  run := do
    let out ← runInformalCli #["deps", "--module", "AFTKTest.Informal.Fixtures.Imports.Top", "--by", "ref", "--only-leaves"]
    assertEq out.exitCode 0
    assertContains out.stdout "Leaves (1)"
    assertContains out.stdout "group.basic.definition"
}

private def cliPresentTextAndJson : TestCase := {
  name := "informal.cli.presentTextAndJson"
  run := do
    let textOut ← runInformalCli #[
      "present", "analysis.uniform_continuity",
      "--root", "tests/informal/knowledgebase-fixtures/long-body",
      "--mode", "rich",
      "--body", "preview"
    ]
    assertEq textOut.exitCode 0
    assertContains textOut.stdout "Uniform continuity"
    assertContains textOut.stdout "[truncated]"

    let jsonOut ← runInformalCli #[
      "present", "analysis.uniform_continuity",
      "--root", "tests/informal/knowledgebase-fixtures/long-body",
      "--mode", "compact",
      "--format", "json"
    ]
    assertEq jsonOut.exitCode 0
    let json ← assertJsonParses jsonOut.stdout
    let mode : String ← match json.getObjVal? "mode" >>= Json.getStr? with
      | .ok value => pure value
      | .error err => fail err
    assertEq mode "compact"
}

private def cliHelpFlags : TestCase := {
  name := "informal.cli.helpFlags"
  run := do
    let topLevelOut ← runTopLevelAftkCli #["--help"]
    assertEq topLevelOut.exitCode 0
    assertContains topLevelOut.stdout "informal"

    let rootHelpOut ← runInformalCli #["--help"]
    assertEq rootHelpOut.exitCode 0
    assertContains rootHelpOut.stdout "lake exe aftk_cli informal [global-options] <command> ..."

    let presentHelpOut ← runInformalCli #["present", "--help"]
    assertEq presentHelpOut.exitCode 0
    assertContains presentHelpOut.stdout "lake exe aftk_cli informal present <NodeId>"
}

private def cliFailurePaths : TestCase := {
  name := "informal.cli.failurePaths"
  run := do
    let missingModule ← runInformalCli #["status"]
    assertEq missingModule.exitCode 2
    assertContains missingModule.stderr "missing required option '--module <Module.Name>'"

    let invalidBy ← runInformalCli #["deps", "--module", "AFTKTest.Informal.Fixtures.Basic", "--by", "bogus"]
    assertEq invalidBy.exitCode 2
    assertContains invalidBy.stderr "expected decl or ref"

    let missingDecl ← runInformalCli #["decl", "AFTKTest.Informal.Fixtures.Basic.missing", "--module", "AFTKTest.Informal.Fixtures.Basic"]
    assertEq missingDecl.exitCode 3
    assertContains missingDecl.stderr "is not tracked"

    let missingRef ← runInformalCli #["ref", "missing.node", "--module", "AFTKTest.Informal.Fixtures.Basic"]
    assertEq missingRef.exitCode 3
    assertContains missingRef.stderr "is not tracked"

    let invalidPresent := #["present", "Bad.node"]
    let invalidPresentOut ← runInformalCli invalidPresent
    assertEq invalidPresentOut.exitCode 2
    assertContains invalidPresentOut.stderr "Invalid node id 'Bad.node'"

    let malformedPresentOut ← runInformalCli #["present", "broken.node", "--root", "tests/informal/knowledgebase-fixtures/malformed-node"]
    assertEq malformedPresentOut.exitCode 4
    assertContains malformedPresentOut.stderr "Metadata id broken.other does not match expected path id broken.node"
}


def tests : List TestCase :=
  [ cliStatusText
  , cliDeclsJson
  , cliDeclTargeted
  , cliRefsText
  , cliDepsJson
  , cliRefDepsLeaves
  , cliPresentTextAndJson
  , cliHelpFlags
  , cliFailurePaths
  ]

end AFTKTest.Informal.Cli
