import AFTK.FileWorker
import AFTKTest.Server.Assert
import AFTKTest.Server.Fixtures

namespace AFTKTest.Server.Integration

open AFTKTest.Server
open AFTKTest.Server.Fixtures

private def rawPosOrFail (ctx : AFTK.FileWorker.Context.WorkerContext) (line col : Nat) : TestM String.Pos.Raw :=
  match AFTK.FileWorker.Queries.rawPosAt ctx line col with
  | .ok pos => pure pos
  | .error err => fail s!"{err.code}: {err.message}"

private unsafe def richInformalHover : TestCase := {
  name := "server.integration.richInformalHover"
  run := do
    let ctx ← informalContext
    let rawPos ← rawPosOrFail ctx informalLine informalCol
    let hover? ← liftIO <| AFTK.FileWorker.Queries.getHoverAt? ctx rawPos
    let hover ← assertSome hover? "expected informal hover result"
    assertContains hover.text "Informal node: group.basic.definition"
    assertContains hover.text "Title: Definition of group"
    assertContains hover.text "Body"
}


unsafe def tests : List TestCase :=
  [richInformalHover]

end AFTKTest.Server.Integration
