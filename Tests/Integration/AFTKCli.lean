import AFTK.Cli

namespace Tests.Integration.AFTKCli

private def failNow (label message : String) : IO α :=
  throw <| IO.userError s!"{label}: {message}"

private def assertContains (label output needle : String) : IO Unit := do
  unless output.contains needle do
    failNow label s!"expected output to contain `{needle}`"

private def assertExitCode
    (label : String)
    (result : AFTK.Cli.InvocationResult)
    (expected : UInt32) : IO Unit := do
  unless result.exitCode == expected do
    failNow label s!"expected exit code {expected}, got {result.exitCode}; stderr={result.stderr}"

private def assertPathExists (label : String) (path : System.FilePath) : IO Unit := do
  unless (← path.pathExists) do
    failNow label s!"expected path to exist: {path}"

private def assertPathMissing (label : String) (path : System.FilePath) : IO Unit := do
  if (← path.pathExists) then
    failNow label s!"expected path to be absent: {path}"

private def invoke (args : Array String) : IO AFTK.Cli.InvocationResult :=
  AFTK.Cli.invoke args

private def testRoot : System.FilePath :=
  System.FilePath.mk "/tmp/aftk-cli-tests"

private def bodyPath : System.FilePath :=
  testRoot / "tmp" / "body.md"

private def sourceJsonPath : System.FilePath :=
  testRoot / "tmp" / "source.json"

private def packetJsonPath : System.FilePath :=
  testRoot / "tmp" / "packet.json"

private def kbJsonPath : System.FilePath :=
  testRoot / "tmp" / "knowledge.json"

private def bodyPathStr : String :=
  toString bodyPath

private def sourceJsonPathStr : String :=
  toString sourceJsonPath

private def packetJsonPathStr : String :=
  toString packetJsonPath

private def kbJsonPathStr : String :=
  toString kbJsonPath

private def sourcePath : System.FilePath :=
  testRoot / "aftk-data" / "sources" / "paper" / "smith2024.json"

private def packetPath : System.FilePath :=
  testRoot / "aftk-data" / "packets" / "paper" / "smith2024" / "thm_2_3.json"

private def packetBodyPath : System.FilePath :=
  testRoot / "aftk-data" / "packets" / "paper" / "smith2024" / "thm_2_3.md"

private def kbPath : System.FilePath :=
  testRoot / "aftk-data" / "knowledge" / "group" / "definition.json"

private def kbBodyPath : System.FilePath :=
  testRoot / "aftk-data" / "knowledge" / "group" / "definition.md"

private def cleanup : IO Unit := do
  if (← testRoot.pathExists) then
    IO.FS.removeDirAll testRoot

private def withTempStore (action : IO Unit) : IO Unit := do
  cleanup
  IO.FS.createDirAll (testRoot / "tmp")
  IO.FS.writeFile bodyPath "# Body\n\nSome source-backed content.\n"
  let cwd ← IO.Process.getCurrentDir
  try
    IO.Process.setCurrentDir testRoot
    action
  finally
    IO.Process.setCurrentDir cwd
    cleanup

private def runHelpCase : IO Unit := do
  let result ← invoke #[]
  assertExitCode "help" result 0
  assertContains "help" result.stdout "AFTK knowledge-base CLI"
  assertContains "help" result.stdout "store init"
  assertContains "help" result.stdout "kb create"

private def runStoreInitAndStatsCase : IO Unit := do
  let init ← invoke #["store", "init"]
  assertExitCode "store init" init 0
  assertContains "store init" init.stdout "created: true"
  assertPathExists "store init manifest" (testRoot / "aftk-data" / "store.json")

  let stats ← invoke #["store", "stats", "--json"]
  assertExitCode "store stats" stats 0
  assertContains "store stats" stats.stdout "\"sources\": 0"
  assertContains "store stats" stats.stdout "\"packets\": 0"
  assertContains "store stats" stats.stdout "\"knowledge\": 0"

private def runSourceCase : IO Unit := do
  let register ← invoke #[
    "source", "register",
    "--id", "src.paper.smith2024",
    "--kind", "paper",
    "--title", "Smith 2024",
    "--path", "sources/smith2024.txt",
    "--author", "Alice Smith",
    "--tag", "algebra"
  ]
  assertExitCode "source register" register 0
  assertContains "source register" register.stdout "action: register"
  assertPathExists "source register path" sourcePath

  let showResult ← invoke #["source", "show", "--id", "src.paper.smith2024"]
  assertExitCode "source show" showResult 0
  assertContains "source show" showResult.stdout "title: Smith 2024"
  assertContains "source show" showResult.stdout "locator: path:sources/smith2024.txt"

  let validate ← invoke #["source", "validate", "--id", "src.paper.smith2024"]
  assertExitCode "source validate" validate 0
  assertContains "source validate" validate.stdout "valid: true"

private def runPacketCase : IO Unit := do
  let ingest ← invoke #[
    "packet", "ingest",
    "--id", "pkt.paper.smith2024.thm_2_3",
    "--source", "src.paper.smith2024",
    "--title", "Theorem 2.3 excerpt",
    "--body-file", bodyPathStr,
    "--anchor", "thm-2-3",
    "--prov-locator", "Theorem 2.3"
  ]
  assertExitCode "packet ingest" ingest 0
  assertContains "packet ingest" ingest.stdout "action: ingest"
  assertPathExists "packet record path" packetPath
  assertPathExists "packet body path" packetBodyPath

  let showResult ← invoke #["packet", "show", "--id", "pkt.paper.smith2024.thm_2_3", "--json"]
  assertExitCode "packet show" showResult 0
  assertContains "packet show" showResult.stdout "\"title\": \"Theorem 2.3 excerpt\""
  assertContains "packet show" showResult.stdout "\"body\": \"# Body"

  let list ← invoke #["packet", "list", "--source", "src.paper.smith2024"]
  assertExitCode "packet list" list 0
  assertContains "packet list" list.stdout "pkt.paper.smith2024.thm_2_3"

private def runKnowledgeCase : IO Unit := do
  let create ← invoke #[
    "kb", "create",
    "--id", "kb.group.definition",
    "--kind", "definition",
    "--basis", "source_backed",
    "--title", "Definition of group",
    "--body-file", bodyPathStr,
    "--source", "src.paper.smith2024",
    "--packet", "pkt.paper.smith2024.thm_2_3",
    "--location", "Foo.bar",
    "--tag", "algebra"
  ]
  assertExitCode "kb create" create 0
  assertContains "kb create" create.stdout "action: create"
  assertPathExists "kb record path" kbPath
  assertPathExists "kb body path" kbBodyPath

  let showResult ← invoke #["kb", "show", "--id", "kb.group.definition"]
  assertExitCode "kb show" showResult 0
  assertContains "kb show" showResult.stdout "title: Definition of group"
  assertContains "kb show" showResult.stdout "Foo.bar"

  let queryBySource ← invoke #["kb", "query", "--source", "src.paper.smith2024", "--json"]
  assertExitCode "kb query source" queryBySource 0
  assertContains "kb query source" queryBySource.stdout "kb.group.definition"

  let queryByLocation ← invoke #["kb", "query", "--location", "Foo.bar"]
  assertExitCode "kb query location" queryByLocation 0
  assertContains "kb query location" queryByLocation.stdout "Knowledge query results (1):"

  let addLink ← invoke #[
    "kb", "add-link",
    "--id", "kb.group.definition",
    "--relation", "related",
    "--target", "kb.group.definition"
  ]
  assertExitCode "kb add-link" addLink 0
  assertContains "kb add-link" addLink.stdout "action: add-link"

  let removeLink ← invoke #[
    "kb", "remove-link",
    "--id", "kb.group.definition",
    "--relation", "related",
    "--target", "kb.group.definition"
  ]
  assertExitCode "kb remove-link" removeLink 0
  assertContains "kb remove-link" removeLink.stdout "action: remove-link"

  let removeTag ← invoke #[
    "kb", "remove-tag",
    "--id", "kb.group.definition",
    "--tag", "algebra"
  ]
  assertExitCode "kb remove-tag" removeTag 0
  assertContains "kb remove-tag" removeTag.stdout "action: remove-tag"

  let addTag ← invoke #[
    "kb", "add-tag",
    "--id", "kb.group.definition",
    "--tag", "algebra"
  ]
  assertExitCode "kb add-tag" addTag 0
  assertContains "kb add-tag" addTag.stdout "action: add-tag"

private def runUpdateCase : IO Unit := do
  IO.FS.writeFile sourceJsonPath <| "\n".intercalate [
    "{",
    "  \"id\": \"src.paper.smith2024\",",
    "  \"kind\": \"paper\",",
    "  \"title\": \"Smith 2024 revised\",",
    "  \"authors\": [\"Alice Smith\"],",
    "  \"locator\": { \"kind\": \"path\", \"value\": \"sources/smith2024-v2.txt\" },",
    "  \"tags\": [\"algebra\", \"revised\"]",
    "}"
  ]
  let sourceUpdate ← invoke #[
    "source", "update",
    "--id", "src.paper.smith2024",
    "--from-json", sourceJsonPathStr
  ]
  assertExitCode "source update" sourceUpdate 0
  assertContains "source update" sourceUpdate.stdout "action: update"

  IO.FS.writeFile packetJsonPath <| "\n".intercalate [
    "{",
    "  \"id\": \"pkt.paper.smith2024.thm_2_3\",",
    "  \"source\": \"src.paper.smith2024\",",
    "  \"title\": \"Theorem 2.3 excerpt updated\",",
    "  \"summary\": \"Updated packet summary\",",
    "  \"anchors\": [{ \"id\": \"thm-2-3\" }],",
    "  \"provenance\": [{ \"source\": \"src.paper.smith2024\" }],",
    "  \"tags\": [\"updated\"]",
    "}"
  ]
  let packetUpdate ← invoke #[
    "packet", "update",
    "--id", "pkt.paper.smith2024.thm_2_3",
    "--from-json", packetJsonPathStr,
    "--body-file", bodyPathStr
  ]
  assertExitCode "packet update" packetUpdate 0
  assertContains "packet update" packetUpdate.stdout "action: update"

  IO.FS.writeFile kbJsonPath <| "\n".intercalate [
    "{",
    "  \"id\": \"kb.group.definition\",",
    "  \"kind\": \"definition\",",
    "  \"basis\": \"source_backed\",",
    "  \"title\": \"Definition of group updated\",",
    "  \"packetRefs\": [\"pkt.paper.smith2024.thm_2_3\"],",
    "  \"sourceRefs\": [\"src.paper.smith2024\"],",
    "  \"scaffoldRefs\": [\"Foo.bar\"],",
    "  \"provenance\": [",
    "    { \"targetId\": \"src.paper.smith2024\", \"targetKind\": \"source\" },",
    "    { \"targetId\": \"pkt.paper.smith2024.thm_2_3\", \"targetKind\": \"packet\" }",
    "  ],",
    "  \"tags\": [\"algebra\"]",
    "}"
  ]
  let kbUpdate ← invoke #[
    "kb", "update",
    "--id", "kb.group.definition",
    "--from-json", kbJsonPathStr,
    "--body-file", bodyPathStr
  ]
  assertExitCode "kb update" kbUpdate 0
  assertContains "kb update" kbUpdate.stdout "action: update"

private def runValidationAndFailureCases : IO Unit := do
  let validate ← invoke #["store", "validate"]
  assertExitCode "store validate" validate 0
  assertContains "store validate" validate.stdout "valid: true"

  let badCreate ← invoke #[
    "kb", "create",
    "--id", "kb.group.bad",
    "--kind", "definition",
    "--basis", "source_backed",
    "--title", "Bad entry",
    "--body-file", bodyPathStr
  ]
  assertExitCode "kb bad create" badCreate 1
  assertContains "kb bad create" badCreate.stderr "source-backed knowledge must reference at least one source or packet"

  let removeSource ← invoke #["source", "remove", "--id", "src.paper.smith2024"]
  assertExitCode "source remove blocked" removeSource 1
  assertContains "source remove blocked" removeSource.stderr "cannot remove source `src.paper.smith2024`"

private def runDiscoveryCase : IO Unit := do
  IO.FS.createDirAll (testRoot / "nested" / "child")
  let cwd ← IO.Process.getCurrentDir
  try
    IO.Process.setCurrentDir (testRoot / "nested" / "child")
    let stats ← invoke #["store", "stats"]
    assertExitCode "store stats discovery" stats 0
    assertContains "store stats discovery" stats.stdout "sources: 1"
  finally
    IO.Process.setCurrentDir cwd

private def runRemoveCase : IO Unit := do
  let removeLink ← invoke #[
    "kb", "remove-link",
    "--id", "kb.group.definition",
    "--relation", "related",
    "--target", "kb.group.definition"
  ]
  assertExitCode "kb remove-link cleanup" removeLink 0

  let removeKb ← invoke #["kb", "remove", "--id", "kb.group.definition"]
  assertExitCode "kb remove" removeKb 0
  assertPathMissing "kb removed json" kbPath
  assertPathMissing "kb removed body" kbBodyPath

  let removePacket ← invoke #["packet", "remove", "--id", "pkt.paper.smith2024.thm_2_3"]
  assertExitCode "packet remove" removePacket 0
  assertPathMissing "packet removed json" packetPath
  assertPathMissing "packet removed body" packetBodyPath

  let removeSource ← invoke #["source", "remove", "--id", "src.paper.smith2024"]
  assertExitCode "source remove" removeSource 0
  assertPathMissing "source removed json" sourcePath

private def emitProgress (message : String) : IO Unit := do
  let stdout ← IO.getStdout
  stdout.putStrLn message
  stdout.flush

private def runStep (label : String) (action : IO Unit) : IO Unit := do
  emitProgress s!"[aftk-cli-tests] start {label}"
  action
  emitProgress s!"[aftk-cli-tests] ok {label}"

def run : IO Unit :=
  withTempStore do
    runStep "help" runHelpCase
    runStep "store-init-stats" runStoreInitAndStatsCase
    runStep "source" runSourceCase
    runStep "packet" runPacketCase
    runStep "knowledge" runKnowledgeCase
    runStep "updates" runUpdateCase
    runStep "validation-failures" runValidationAndFailureCases
    runStep "discovery" runDiscoveryCase
    runStep "remove" runRemoveCase

end Tests.Integration.AFTKCli
