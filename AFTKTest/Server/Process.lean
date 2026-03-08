import AFTK.Server.Protocol
import AFTKTest.Server.Assert
import AFTKTest.Server.Fixtures

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


def tests : List TestCase :=
  [ openReuseCloseShutdown
  , queryAndTacticFlow
  , invalidPositionParams
  , fileChangedInvalidation
  , workerUnavailable
  ]

end AFTKTest.Server.Process
