module

public import AFTK.FileWorker
public import AFTKTest.Server.Assert
public import AFTKTest.Server.Fixtures

public section


namespace AFTKTest.Server.Worker

open AFTKTest.Server
open AFTKTest.Server.Fixtures

private def rawPosOrFail (ctx : AFTK.FileWorker.Context.WorkerContext) (line col : Nat) : TestM String.Pos.Raw :=
  match AFTK.FileWorker.Queries.rawPosAt ctx line col with
  | .ok pos => pure pos
  | .error err => fail s!"{err.code}: {err.message}"

private unsafe def hover : TestCase := {
  name := "server.worker.hover"
  run := do
    let ctx ← semanticsContext
    let rawPos ← rawPosOrFail ctx hoverLine hoverCol
    let hover? ← liftIO <| AFTK.FileWorker.Queries.getHoverAt? ctx rawPos
    let hover ← assertSome hover? "expected hover result"
    assertContains hover.text "Nat.succ"
}

private unsafe def termGoal : TestCase := {
  name := "server.worker.termGoal"
  run := do
    let ctx ← semanticsContext
    let rawPos ← rawPosOrFail ctx termGoalLine termGoalCol
    let goal? ← liftIO <| AFTK.FileWorker.Queries.getPlainTermGoalAt? ctx rawPos
    let goal ← assertSome goal? "expected term-goal result"
    assertContains goal.goal "⊢ Nat"
}

private unsafe def plainGoal : TestCase := {
  name := "server.worker.plainGoal"
  run := do
    let ctx ← semanticsContext
    let rawPos ← rawPosOrFail ctx tacticLine tacticCol
    let goal? ← liftIO <| AFTK.FileWorker.Queries.getPlainGoalAt? ctx rawPos
    let goal ← assertSome goal? "expected plain-goal result"
    assertEq goal.goals.size 1
    assertContains goal.rendered "⊢ n + 0 = n"
}

private unsafe def captureAndRunTactic : TestCase := {
  name := "server.worker.captureAndRunTactic"
  run := do
    let ctx ← semanticsContext
    let rawPos ← rawPosOrFail ctx tacticLine tacticCol
    let goals := AFTK.FileWorker.Queries.goalsAtPosition ctx rawPos
    assertEq goals.size 1
    let some goal := goals.toList.head?
      | fail "expected one goal"
    let node ← liftIO <| AFTK.FileWorker.TacticState.captureNode goal
    let currentGoals ← liftIO <| AFTK.FileWorker.TacticState.goalsOfNode node
    assertEq currentGoals.size 1
    assertContains currentGoals[0]! "⊢ n + 0 = n"
    let result ← liftIO <| (AFTK.FileWorker.TacticState.runTacticOnNode node "simpa").run
    match result with
    | .error err => fail s!"{err.code}: {err.message}"
    | .ok (goals, _nextNode) => assertTrue goals.isEmpty "simpa should solve the goal"
}


unsafe def tests : List TestCase :=
  [hover, termGoal, plainGoal, captureAndRunTactic]

end AFTKTest.Server.Worker
