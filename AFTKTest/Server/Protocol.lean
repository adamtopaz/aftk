import AFTK.Server.Protocol
import AFTKTest.Server.Assert

namespace AFTKTest.Server.Protocol

open Lean
open AFTK.Server.Protocol
open AFTKTest.Server

private def errorCodes : TestCase := {
  name := "server.protocol.errorCodes"
  run := do
    assertEq ErrorCode.tacticFailed (-32001)
    assertEq ErrorCode.fileNotOpen (-32010)
    assertEq ErrorCode.fileChanged (-32011)
    assertEq ErrorCode.workerUnavailable (-32012)
    assertEq ErrorCode.staleNode (-32013)
}

private def runTacticResultRoundTrip : TestCase := {
  name := "server.protocol.runTacticResultRoundTrip"
  run := do
    let value : RunTacticResult := { goals := #["⊢ True"], nextId := "node-1" }
    let json := toJson value
    let decoded ←
      match fromJson? (α := RunTacticResult) json with
      | .ok decoded => pure decoded
      | .error err => fail err
    assertEq decoded value
}

private def hoverJsonShape : TestCase := {
  name := "server.protocol.hoverJsonShape"
  run := do
    let value : HoverResult := {
      text := "hello"
      range? := some {
        start := { line := 1, col := 2 }
        stop := { line := 1, col := 7 }
      }
    }
    let text := (toJson value).compress
    assertContains text "\"text\":\"hello\""
    assertContains text "\"range\""
}


def tests : List TestCase :=
  [errorCodes, runTacticResultRoundTrip, hoverJsonShape]

end AFTKTest.Server.Protocol
