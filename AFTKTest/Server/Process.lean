module

public import AFTK.Server.Protocol
public import AFTKTest.Server.Assert
public import AFTKTest.Server.Fixtures

public section


namespace AFTKTest.Server.Process

open Lean
open AFTK.Server.Protocol
open AFTKTest.Server
open AFTKTest.Server.Fixtures

private def decodeJson {α : Type} [FromJson α] (json : Json) : TestM α :=
  match fromJson? (α := α) json with
  | .ok value => pure value
  | .error err => fail err

private def obj (fields : List (String × Json)) : Json :=
  Json.mkObj fields

private def getField (json : Json) (field : String) : TestM Json :=
  match json.getObjVal? field with
  | .ok value => pure value
  | .error err => fail err

private def getStrField (json : Json) (field : String) : TestM String := do
  match (← getField json field).getStr? with
  | .ok value => pure value
  | .error err => fail err

private def getBoolField (json : Json) (field : String) : TestM Bool := do
  match (← getField json field).getBool? with
  | .ok value => pure value
  | .error err => fail err

private def getNatField (json : Json) (field : String) : TestM Nat := do
  match (← getField json field).getNat? with
  | .ok value => pure value
  | .error err => fail err

private def getArrayField (json : Json) (field : String) : TestM (Array Json) := do
  match (← getField json field).getArr? with
  | .ok value => pure value
  | .error err => fail err

private def openReuseCloseShutdown : TestCase := {
  name := "server.process.openReuseCloseShutdown"
  run := withHub fun rpc => do
    let path := (← semanticsPath).toString

    let firstJson ← rpc.requestResult "open" (obj [("path", toJson path)])
    let first : OpenResult ← decodeJson firstJson
    assertTrue first.opened "first open should spawn a worker"

    let secondJson ← rpc.requestResult "open" (obj [("path", toJson path)])
    let second : OpenResult ← decodeJson secondJson
    assertFalse second.opened "second open should reuse the worker"

    let closedJson ← rpc.requestResult "close" (obj [("path", toJson path)])
    let closed : CloseResult ← decodeJson closedJson
    assertTrue closed.closed "close should stop the open worker"

    let closedAgainJson ← rpc.requestResult "close" (obj [("path", toJson path)])
    let closedAgain : CloseResult ← decodeJson closedAgainJson
    assertFalse closedAgain.closed "close should be idempotent"

    let shutdownJson ← rpc.requestResult "shutdown" (obj [])
    let shutdown : ShutdownResult ← decodeJson shutdownJson
    assertEq shutdown.stopped 0
}

private def queryAndTacticFlow : TestCase := {
  name := "server.process.queryAndTacticFlow"
  run := withHub fun rpc => do
    let path := (← semanticsPath).toString

    let openJson ← rpc.requestResult "open" (obj [("path", toJson path)])
    let _open : OpenResult ← decodeJson openJson

    let hoverJson ← rpc.requestResult "get_hover"
      (obj [("path", toJson path), ("line", toJson hoverLine), ("col", toJson hoverCol)])
    let hover : HoverResult ← decodeJson hoverJson
    assertContains hover.text "Nat.succ"

    let termGoalJson ← rpc.requestResult "get_plain_term_goal"
      (obj [("path", toJson path), ("line", toJson termGoalLine), ("col", toJson termGoalCol)])
    let termGoal : PlainTermGoalResult ← decodeJson termGoalJson
    assertContains termGoal.goal "⊢ Nat"

    let plainGoalJson ← rpc.requestResult "get_plain_goal"
      (obj [("path", toJson path), ("line", toJson tacticLine), ("col", toJson tacticCol)])
    let plainGoal : PlainGoalResult ← decodeJson plainGoalJson
    assertContains plainGoal.rendered "⊢ n + 0 = n"

    let loadNodeJson ← rpc.requestResult "load_node"
      (obj [("path", toJson path), ("line", toJson tacticLine), ("col", toJson tacticCol)])
    let loadNode : LoadNodeResult ← decodeJson loadNodeJson
    assertEq loadNode.id.size 1
    let nodeId := loadNode.id[0]!

    let goalsJson ← rpc.requestResult "get_goals"
      (obj [("path", toJson path), ("id", toJson nodeId)])
    let goals : GetGoalsResult ← decodeJson goalsJson
    assertEq goals.goals.size 1
    assertContains goals.goals[0]! "⊢ n + 0 = n"

    let runTacticJson ← rpc.requestResult "run_tactic"
      (obj [("path", toJson path), ("id", toJson nodeId), ("tactic", toJson "simpa")])
    let runTactic : RunTacticResult ← decodeJson runTacticJson
    assertTrue runTactic.goals.isEmpty "simpa should solve the goal"

    let stepNodeJson ← rpc.requestResult "load_node"
      (obj [("path", toJson path), ("line", toJson tacticStepsLine), ("col", toJson tacticStepsCol)])
    let stepNode : LoadNodeResult ← decodeJson stepNodeJson
    let stepsJson ← rpc.requestResult "run_tactic_steps"
      (obj [
        ("path", toJson path),
        ("id", toJson stepNode.id[0]!),
        ("tactics", toJson #["intro h", "exact And.intro h.right h.left"])
      ])
    let steps : RunTacticStepsResult ← decodeJson stepsJson
    assertEq steps.results.size 2
    assertTrue steps.results[1]!.goals.isEmpty "second tactic step should solve the goal"

    let shutdownJson ← rpc.requestResult "shutdown" (obj [])
    let shutdown : ShutdownResult ← decodeJson shutdownJson
    assertEq shutdown.stopped 1
}

private def invalidPositionParams : TestCase := {
  name := "server.process.invalidPositionParams"
  run := withHub fun rpc => do
    let path := (← semanticsPath).toString
    let openJson ← rpc.requestResult "open" (obj [("path", toJson path)])
    let _open : OpenResult ← decodeJson openJson

    let response ← rpc.request "get_hover" (obj [("path", toJson path), ("line", toJson 0), ("col", toJson 1)])
    assertEq (← responseErrorCode response) (-32602)
    let msg ← responseErrorMessage response
    assertEq msg "Invalid params"
    let data ← responseErrorDataString response
    assertContains data "line must be >= 1"

    let shutdownJson ← rpc.requestResult "shutdown" (obj [])
    let _shutdown : ShutdownResult ← decodeJson shutdownJson
    pure ()
}

private def fileChangedInvalidation : TestCase := {
  name := "server.process.fileChangedInvalidation"
  run := withTempDir fun dir => withHub fun rpc => do
    let path ← copySemanticsFixtureTo dir
    let pathStr := path.toString

    let openJson ← rpc.requestResult "open" (obj [("path", toJson pathStr)])
    let _open : OpenResult ← decodeJson openJson

    let loadNodeJson ← rpc.requestResult "load_node"
      (obj [("path", toJson pathStr), ("line", toJson tacticLine), ("col", toJson tacticCol)])
    let loadNode : LoadNodeResult ← decodeJson loadNodeJson
    let staleId := loadNode.id[0]!

    let text ← liftIO <| IO.FS.readFile path
    liftIO <| IO.FS.writeFile path (text ++ "\n-- changed\n")

    let changedResp ← rpc.request "get_hover"
      (obj [("path", toJson pathStr), ("line", toJson hoverLine), ("col", toJson hoverCol)])
    assertEq (← responseErrorCode changedResp) ErrorCode.fileChanged

    let reopenedJson ← rpc.requestResult "open" (obj [("path", toJson pathStr)])
    let reopened : OpenResult ← decodeJson reopenedJson
    assertTrue reopened.opened "reopen after file change should spawn a fresh worker"

    let staleResp ← rpc.request "get_goals" (obj [("path", toJson pathStr), ("id", toJson staleId)])
    assertEq (← responseErrorCode staleResp) ErrorCode.staleNode

    let shutdownJson ← rpc.requestResult "shutdown" (obj [])
    let _shutdown : ShutdownResult ← decodeJson shutdownJson
    pure ()
}

private def workerUnavailable : TestCase := {
  name := "server.process.workerUnavailable"
  run := withTempDir fun dir => withHub fun rpc => do
    let src ← semanticsPath
    let uniquePath := dir / "UniqueSemanticsKill.lean"
    let text ← liftIO <| IO.FS.readFile src
    liftIO <| IO.FS.writeFile uniquePath text
    let pathStr := uniquePath.toString

    let openJson ← rpc.requestResult "open" (obj [("path", toJson pathStr)])
    let _open : OpenResult ← decodeJson openJson

    killWorkerFor uniquePath

    let unavailableResp ← rpc.request "get_hover"
      (obj [("path", toJson pathStr), ("line", toJson hoverLine), ("col", toJson hoverCol)])
    assertEq (← responseErrorCode unavailableResp) ErrorCode.workerUnavailable

    let shutdownJson ← rpc.requestResult "shutdown" (obj [])
    let _shutdown : ShutdownResult ← decodeJson shutdownJson
    pure ()
}

private def knowledgeBaseFixtureReadFlow : TestCase := {
  name := "server.process.knowledgeBaseFixtureReadFlow"
  run := withHub fun rpc => do
    let root := (← knowledgeBaseRoot).toString

    let statusJson ← rpc.requestResult "knowledgebase_status" (obj [("root", toJson root)])
    assertTrue (← getBoolField statusJson "initialized") "fixture root should be initialized"
    assertEq (← getNatField statusJson "nodeCount") 1

    let listJson ← rpc.requestResult "knowledgebase_list"
      (obj [("root", toJson root), ("prefix", toJson "group.basic")])
    let nodes ← getArrayField listJson "nodes"
    assertEq nodes.size 1

    let showJson ← rpc.requestResult "knowledgebase_show"
      (obj [("root", toJson root), ("id", toJson "group.basic.definition")])
    let nodeJson ← getField showJson "node"
    let metadataJson ← getField nodeJson "metadata"
    assertEq (← getStrField metadataJson "title") "Definition of group"

    let bodyJson ← rpc.requestResult "knowledgebase_get_body"
      (obj [("root", toJson root), ("id", toJson "group.basic.definition")])
    let body := (← getStrField bodyJson "body").trimAscii.toString
    assertContains body "every element has an inverse"

    let pathsJson ← rpc.requestResult "knowledgebase_get_paths"
      (obj [("root", toJson root), ("id", toJson "group.basic.definition")])
    let pathsObj ← getField pathsJson "paths"
    let metadataPath := (← getStrField pathsObj "metadataPath")
    assertContains metadataPath "group/basic/definition.json"

    let searchJson ← rpc.requestResult "knowledgebase_search_text"
      (obj [("root", toJson root), ("query", toJson "inverse")])
    let hits ← getArrayField searchJson "hits"
    assertEq hits.size 1
}

private def knowledgeBaseWriteFlow : TestCase := {
  name := "server.process.knowledgeBaseWriteFlow"
  run := withTempDir fun dir => withHub fun rpc => do
    let root := (dir / "knowledgebase").toString

    let _initJson ← rpc.requestResult "knowledgebase_init" (obj [("root", toJson root)])

    let createJson ← rpc.requestResult "knowledgebase_create" (obj [
      ("root", toJson root),
      ("id", toJson "analysis.uniform_continuity"),
      ("title", toJson "Uniform continuity"),
      ("kind", toJson "definition"),
      ("body", toJson "A uniformly continuous function preserves nearby points.\n")
    ])
    let createdNodeJson ← getField createJson "node"
    let createdMetadataJson ← getField createdNodeJson "metadata"
    assertEq (← getStrField createdMetadataJson "title") "Uniform continuity"

    let setBodyJson ← rpc.requestResult "knowledgebase_set_body" (obj [
      ("root", toJson root),
      ("id", toJson "analysis.uniform_continuity"),
      ("body", toJson "Updated body text\n")
    ])
    let updatedNodeJson ← getField setBodyJson "node"
    assertContains (← getStrField updatedNodeJson "body") "Updated body text"

    let metadataPayload := Json.mkObj [
      ("schemaVersion", toJson (1 : Nat)),
      ("id", toJson "analysis.uniform_continuity"),
      ("title", toJson "Uniform continuity (updated)"),
      ("kind", toJson "definition"),
      ("status", toJson "active"),
      ("summary", toJson "Updated summary"),
      ("tags", toJson #["analysis"])
    ]
    let replaceJson ← rpc.requestResult "knowledgebase_replace_metadata" (obj [
      ("root", toJson root),
      ("id", toJson "analysis.uniform_continuity"),
      ("metadata", metadataPayload)
    ])
    let replaceNodeJson ← getField replaceJson "node"
    let replaceMetadataJson ← getField replaceNodeJson "metadata"
    assertEq (← getStrField replaceMetadataJson "title") "Uniform continuity (updated)"
    assertEq (← getStrField replaceMetadataJson "summary") "Updated summary"

    let renameJson ← rpc.requestResult "knowledgebase_rename" (obj [
      ("root", toJson root),
      ("oldId", toJson "analysis.uniform_continuity"),
      ("newId", toJson "analysis.uniform_continuity.updated")
    ])
    let storedJson ← getField renameJson "stored"
    let storedNodeJson ← getField storedJson "node"
    let storedMetadataJson ← getField storedNodeJson "metadata"
    assertEq (← getStrField storedMetadataJson "id") "analysis.uniform_continuity.updated"

    let validateJson ← rpc.requestResult "knowledgebase_validate_all" (obj [("root", toJson root)])
    assertTrue (← getBoolField validateJson "ok") "temp knowledgebase should validate cleanly"

    let deleteJson ← rpc.requestResult "knowledgebase_delete"
      (obj [("root", toJson root), ("id", toJson "analysis.uniform_continuity.updated")])
    assertTrue (← getBoolField deleteJson "deleted") "delete should report success"
}

private def knowledgeBaseDomainErrors : TestCase := {
  name := "server.process.knowledgeBaseDomainErrors"
  run := withHub fun rpc => do
    let root := (← knowledgeBaseRoot).toString

    let missingResp ← rpc.request "knowledgebase_show"
      (obj [("root", toJson root), ("id", toJson "group.basic.missing")])
    assertEq (← responseErrorCode missingResp) ErrorCode.domainNotFound
    let missingData ← responseErrorData missingResp
    assertEq (← getStrField missingData "layer") "knowledgebase"
    assertEq (← getStrField missingData "code") "node.notFound"
    assertEq (← getNatField missingData "exitCode") 3

    let malformedResp ← rpc.request "knowledgebase_replace_metadata" (obj [
      ("root", toJson root),
      ("id", toJson "group.basic.definition"),
      ("metadata", Json.mkObj [("id", toJson "group.basic.definition")])
    ])
    assertEq (← responseErrorCode malformedResp) (-32602)
    let malformedData ← responseErrorDataString malformedResp
    assertContains malformedData "invalid metadata payload"
}

private def informalFlow : TestCase := {
  name := "server.process.informalFlow"
  run := withHub fun rpc => do
    let modules : Array String := #["AFTKTest.Informal.Fixtures.Basic"]
    let kbRoot := (← knowledgeBaseRoot).toString

    let statusJson ← rpc.requestResult "informal_status" (obj [("modules", toJson modules)])
    assertEq (← getNatField statusJson "trackedDeclarations") 8
    assertEq (← getNatField statusJson "trackedReferences") 5

    let declsJson ← rpc.requestResult "informal_decls"
      (obj [("modules", toJson modules), ("ref", toJson "group.basic.definition")])
    let decls : InformalDeclsResult ← decodeJson declsJson
    assertTrue (!decls.entries.isEmpty) "decls filtered by ref should be non-empty"

    let declJson ← rpc.requestResult "informal_decl" (obj [
      ("modules", toJson modules),
      ("declName", toJson "AFTKTest.Informal.Fixtures.Basic.multiRef")
    ])
    let decl : InformalDeclResult ← decodeJson declJson
    assertEq decl.entry.refCount 2

    let refsJson ← rpc.requestResult "informal_refs"
      (obj [("modules", toJson modules), ("prefix", toJson "group.basic")])
    let refs : InformalRefsResult ← decodeJson refsJson
    assertTrue (refs.entries.any fun entry => toString entry.ref == "group.basic.definition")
      "refs should include group.basic.definition"

    let refJson ← rpc.requestResult "informal_ref"
      (obj [("modules", toJson modules), ("ref", toJson "group.basic.definition")])
    let ref : InformalRefResult ← decodeJson refJson
    assertTrue (ref.entry.declCount > 0) "group.basic.definition should have referring declarations"

    let declDepsJson ← rpc.requestResult "informal_decl_deps" (obj [("modules", toJson modules)])
    let declDeps : InformalDeclDepsResult ← decodeJson declDepsJson
    assertTrue (!declDeps.rows.isEmpty) "decl dependency rows should be non-empty"

    let refDepsJson ← rpc.requestResult "informal_ref_deps" (obj [("modules", toJson modules)])
    let refDeps : InformalRefDepsResult ← decodeJson refDepsJson
    assertTrue (!refDeps.rows.isEmpty) "ref dependency rows should be non-empty"

    let presentJson ← rpc.requestResult "informal_present" (obj [
      ("root", toJson kbRoot),
      ("ref", toJson "group.basic.definition"),
      ("mode", toJson "rich"),
      ("bodyMode", toJson "preview")
    ])
    assertEq (← getStrField presentJson "mode") "rich"
    let summaryJson ← getField presentJson "summary"
    assertEq (← getStrField summaryJson "title") "Definition of group"
    let payloadJson ← getField presentJson "payload"
    let bodyJson ← getField payloadJson "body"
    assertEq (← getStrField bodyJson "kind") "preview"
}

private def informalDomainErrors : TestCase := {
  name := "server.process.informalDomainErrors"
  run := withHub fun rpc => do
    let modules : Array String := #["AFTKTest.Informal.Fixtures.Basic"]

    let missingModulesResp ← rpc.request "informal_status" (obj [("modules", toJson (#[] : Array String))])
    assertEq (← responseErrorCode missingModulesResp) (-32602)
    let missingModulesData ← responseErrorDataString missingModulesResp
    assertContains missingModulesData "modules must be non-empty"

    let missingDeclResp ← rpc.request "informal_decl" (obj [
      ("modules", toJson modules),
      ("declName", toJson "AFTKTest.Informal.Fixtures.Basic.missing")
    ])
    assertEq (← responseErrorCode missingDeclResp) ErrorCode.domainNotFound
    let missingDeclData ← responseErrorData missingDeclResp
    assertEq (← getStrField missingDeclData "layer") "informal"
    assertEq (← getStrField missingDeclData "code") "informal.notTracked"
    assertEq (← getNatField missingDeclData "exitCode") 3
}


def tests : List TestCase :=
  [ openReuseCloseShutdown
  , queryAndTacticFlow
  , invalidPositionParams
  , fileChangedInvalidation
  , workerUnavailable
  , knowledgeBaseFixtureReadFlow
  , knowledgeBaseWriteFlow
  , knowledgeBaseDomainErrors
  , informalFlow
  , informalDomainErrors
  ]

end AFTKTest.Server.Process
