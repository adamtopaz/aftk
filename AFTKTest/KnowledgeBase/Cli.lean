import AFTKTest.KnowledgeBase.Assert
import Lean.Data.Json.Parser

namespace AFTKTest.KnowledgeBase.Cli

open AFTK.KnowledgeBase

open Lean
open AFTKTest.KnowledgeBase

private def runAftkCli (args : Array String) (input? : Option String := none) : TestM IO.Process.Output := do
  let cwd ← liftIO IO.currentDir
  liftIO <| IO.Process.output {
    cmd := "lake"
    args := #["exe", "aftk", "knowledgebase"] ++ args
    cwd := some cwd
  } input?

private def cliInitCreateShowJson : TestCase := {
  name := "cli.initCreateShowJson"
  run := withTempDir fun dir => do
    let root := dir / "knowledgebase"
    let initOut ← runAftkCli #["--root", root.toString, "init"]
    assertEq initOut.exitCode 0
    let createOut ← runAftkCli #["--root", root.toString, "create", "topology.open_cover", "--title", "Open cover", "--kind", "definition"]
    assertEq createOut.exitCode 0
    let showOut ← runAftkCli #["--root", root.toString, "--format", "json", "show", "topology.open_cover"]
    assertEq showOut.exitCode 0
    let json ← assertJsonParses showOut.stdout
    let ok : Bool ← match json.getObjVal? "ok" >>= Json.getBool? with
      | .ok ok => pure ok
      | .error err => fail err
    assertTrue ok "expected JSON response with ok = true"
    let command : String ← match json.getObjVal? "command" >>= Json.getStr? with
      | .ok command => pure command
      | .error err => fail err
    assertEq command "show"
    assertContains showOut.stdout "topology.open_cover"
}


def tests : List TestCase :=
  [cliInitCreateShowJson]

end AFTKTest.KnowledgeBase.Cli
