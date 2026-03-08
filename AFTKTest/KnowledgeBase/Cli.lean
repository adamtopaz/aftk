import AFTKTest.KnowledgeBase.Assert
import AFTK.KnowledgeBase.Cli.Parse
import AFTK.KnowledgeBase.Cli.Render
import Lean.Data.Json.Parser

namespace AFTKTest.KnowledgeBase.Cli

open AFTK.KnowledgeBase
open AFTK.KnowledgeBase.Cli
open Lean
open AFTKTest.KnowledgeBase

private def runTopLevelAftkCli (args : Array String) (input? : Option String := none) : TestM IO.Process.Output := do
  let cwd ← liftIO IO.currentDir
  liftIO <| IO.Process.output {
    cmd := "lake"
    args := #["exe", "aftk"] ++ args
    cwd := some cwd
  } input?

private def runKnowledgeBaseCli (args : Array String) (input? : Option String := none) : TestM IO.Process.Output :=
  runTopLevelAftkCli (#["knowledgebase"] ++ args) input?

private def cliInitCreateShowJson : TestCase := {
  name := "cli.initCreateShowJson"
  run := withTempDir fun dir => do
    let root := dir / "knowledgebase"
    let initOut ← runKnowledgeBaseCli #["--root", root.toString, "init"]
    assertEq initOut.exitCode 0
    let createOut ← runKnowledgeBaseCli #["--root", root.toString, "create", "topology.open_cover", "--title", "Open cover", "--kind", "definition"]
    assertEq createOut.exitCode 0
    let showOut ← runKnowledgeBaseCli #["--root", root.toString, "--format", "json", "show", "topology.open_cover"]
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

private def cliHelpTopicsParse : TestCase := {
  name := "cli.helpTopics.parse"
  run := do
    let cases : List (List String × HelpTopic) := [
      (["--help"], .knowledgebase),
      (["--root", "knowledgebase", "--help"], .knowledgebase),
      (["init", "--help"], .init),
      (["status", "--help"], .status),
      (["list", "--help"], .list),
      (["show", "--help"], .show),
      (["show", "topology.open_cover", "--help"], .show),
      (["create", "--help"], .create),
      (["rename", "--help"], .rename),
      (["delete", "--help"], .delete),
      (["body", "--help"], .body),
      (["body", "show", "--help"], .bodyShow),
      (["body", "set", "--help"], .bodySet),
      (["metadata", "--help"], .metadata),
      (["metadata", "show", "--help"], .metadataShow),
      (["metadata", "replace", "--help"], .metadataReplace),
      (["metadata", "validate", "--help"], .metadataValidate),
      (["validate", "--help"], .validate),
      (["validate", "storage", "--help"], .validateStorage),
      (["validate", "node", "--help"], .validateNode),
      (["validate", "all", "--help"], .validateAll),
      (["search", "--help"], .search),
      (["search", "text", "--help"], .searchText),
      (["search", "tag", "--help"], .searchTag),
      (["relationships", "--help"], .relationships),
      (["relationships", "outgoing", "--help"], .relationshipsOutgoing),
      (["relationships", "incoming", "--help"], .relationshipsIncoming),
      (["relationships", "related", "--help"], .relationshipsRelated)
    ]
    for (args, expected) in cases do
      let actual ← match AFTK.KnowledgeBase.Cli.Parse.parseHelpTopic? args with
        | .ok actual => pure actual
        | .error err => fail s!"unexpected help-parse error for {repr args}: {err}"
      assertEq actual (some expected) s!"args: {repr args}"
}

private def cliHelpTextRendered : TestCase := {
  name := "cli.helpText.rendered"
  run := do
    let topics : List HelpTopic := [
      .knowledgebase,
      .init,
      .status,
      .list,
      .show,
      .create,
      .rename,
      .delete,
      .body,
      .bodyShow,
      .bodySet,
      .metadata,
      .metadataShow,
      .metadataReplace,
      .metadataValidate,
      .validate,
      .validateStorage,
      .validateNode,
      .validateAll,
      .search,
      .searchText,
      .searchTag,
      .relationships,
      .relationshipsOutgoing,
      .relationshipsIncoming,
      .relationshipsRelated
    ]
    for topic in topics do
      let rendered := AFTK.KnowledgeBase.Cli.Render.renderHelp topic
      assertContains rendered "Usage:" s!"topic: {repr topic}"
      assertContains rendered "--help" s!"topic: {repr topic}"
}

private def cliHelpFlags : TestCase := {
  name := "cli.helpFlags"
  run := do
    let topLevelOut ← runTopLevelAftkCli #["--help"]
    assertEq topLevelOut.exitCode 0
    assertContains topLevelOut.stdout "lake exe aftk <command> ..."
    assertContains topLevelOut.stdout "knowledgebase"

    let rootHelpOut ← runKnowledgeBaseCli #["--help"]
    assertEq rootHelpOut.exitCode 0
    assertContains rootHelpOut.stdout "lake exe aftk knowledgebase [global-options] <command> ..."
    assertContains rootHelpOut.stdout "Run `lake exe aftk knowledgebase <command> --help`"

    let createHelpOut ← runKnowledgeBaseCli #["create", "--help"]
    assertEq createHelpOut.exitCode 0
    assertContains createHelpOut.stdout "lake exe aftk knowledgebase [global-options] create <id> --title <title> [options]"
    assertContains createHelpOut.stdout "--body-file <path>"

    let bodySetHelpOut ← runKnowledgeBaseCli #["body", "set", "--help"]
    assertEq bodySetHelpOut.exitCode 0
    assertContains bodySetHelpOut.stdout "lake exe aftk knowledgebase [global-options] body set <id> (--from <path> | --stdin)"

    let validateNodeHelpOut ← runKnowledgeBaseCli #["validate", "node", "--help"]
    assertEq validateNodeHelpOut.exitCode 0
    assertContains validateNodeHelpOut.stdout "lake exe aftk knowledgebase [global-options] validate node <id>"
}


def tests : List TestCase :=
  [cliInitCreateShowJson, cliHelpTopicsParse, cliHelpTextRendered, cliHelpFlags]

end AFTKTest.KnowledgeBase.Cli
