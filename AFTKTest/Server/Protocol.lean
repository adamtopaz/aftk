module

public import AFTK.Server.Protocol
public import AFTKTest.Server.Assert

public section


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
    assertEq ErrorCode.domainNotFound (-32020)
    assertEq ErrorCode.domainValidation (-32021)
    assertEq ErrorCode.domainConflict (-32022)
    assertEq ErrorCode.domainError (-32023)
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

private def informalDeclDtoRoundTrip : TestCase := {
  name := "server.protocol.informalDeclDtoRoundTrip"
  run := do
    let value : InformalDeclDto := {
      declName := "Demo.basic"
      refs := #[{ nodeId := ⟨"group.basic.definition"⟩ }]
      refCount := 1
    }
    let json := toJson value
    let decoded ←
      match fromJson? (α := InformalDeclDto) json with
      | .ok decoded => pure decoded
      | .error err => fail err
    assertEq decoded value
}

private def domainErrorShape : TestCase := {
  name := "server.protocol.domainErrorShape"
  run := do
    let err := knowledgeBaseError "knowledgebase" <| AFTK.KnowledgeBase.KnowledgeBaseError.notFound "node.notFound" "missing node"
    assertEq err.code ErrorCode.domainNotFound
    let data := err.data?.getD Json.null
    let text := data.compress
    assertContains text "\"layer\":\"knowledgebase\""
    assertContains text "\"code\":\"node.notFound\""
    assertContains text "\"exitCode\":3"
}


def tests : List TestCase :=
  [errorCodes, runTacticResultRoundTrip, hoverJsonShape, informalDeclDtoRoundTrip, domainErrorShape]

end AFTKTest.Server.Protocol
