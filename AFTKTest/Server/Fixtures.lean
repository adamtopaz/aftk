import AFTK.FileWorker
import AFTKTest.Server.Assert
import Lean

namespace AFTKTest.Server.Fixtures

open Lean
open AFTKTest.Server

abbrev HubChild := IO.Process.Child { stdin := .piped, stdout := .piped, stderr := .inherit }

structure RpcProcess where
  child : HubChild
  stdin : IO.FS.Stream
  stdout : IO.FS.Stream
  nextId : IO.Ref Nat

@[inline] def semanticsPath : TestM System.FilePath := do
  pure <| (← liftIO IO.currentDir) / "tests" / "server" / "fixtures" / "lean" / "Semantics.lean"

@[inline] def informalPath : TestM System.FilePath := do
  pure <| (← liftIO IO.currentDir) / "tests" / "server" / "fixtures" / "lean" / "Informal.lean"

@[inline] def knowledgeBaseRoot : TestM System.FilePath := do
  pure <| (← liftIO IO.currentDir) / "tests" / "server" / "fixtures" / "knowledgebase" / "basic-valid"

@[inline] def hoverLine : Nat := 5
@[inline] def hoverCol : Nat := 26
@[inline] def termGoalLine : Nat := 8
@[inline] def termGoalCol : Nat := 3
@[inline] def tacticLine : Nat := 11
@[inline] def tacticCol : Nat := 3
@[inline] def tacticStepsLine : Nat := 14
@[inline] def tacticStepsCol : Nat := 3
@[inline] def informalLine : Nat := 7
@[inline] def informalCol : Nat := 38

unsafe def buildWorkerContext (path : System.FilePath) : TestM AFTK.FileWorker.Context.WorkerContext :=
  liftIO <| AFTK.FileWorker.Context.build path {}

unsafe def semanticsContext : TestM AFTK.FileWorker.Context.WorkerContext := do
  buildWorkerContext (← semanticsPath)

unsafe def informalContext : TestM AFTK.FileWorker.Context.WorkerContext := do
  buildWorkerContext (← informalPath)

private def jsonField? (json : Json) (field : String) : Option Json :=
  match json with
  | .obj obj => obj.get? field
  | _ => none

private def errorCode? (json : Json) : Option Int := do
  let err ← jsonField? json "error"
  let code ← jsonField? err "code"
  code.getInt?.toOption

private def errorMessage? (json : Json) : Option String := do
  let err ← jsonField? json "error"
  let msg ← jsonField? err "message"
  msg.getStr?.toOption

private def errorDataString? (json : Json) : Option String := do
  let err ← jsonField? json "error"
  let data := jsonField? err "data"
  match data with
  | some (.str text) => some text
  | _ => none

private def result? (json : Json) : Option Json :=
  jsonField? json "result"

@[inline] def responseResult (json : Json) : TestM Json :=
  match result? json with
  | some result => pure result
  | none =>
      fail s!"expected JSON-RPC result, got: {json.compress}"

@[inline] def responseErrorCode (json : Json) : TestM Int :=
  match errorCode? json with
  | some code => pure code
  | none => fail s!"expected JSON-RPC error code, got: {json.compress}"

@[inline] def responseErrorMessage (json : Json) : TestM String :=
  match errorMessage? json with
  | some message => pure message
  | none => fail s!"expected JSON-RPC error message, got: {json.compress}"

@[inline] def responseErrorDataString (json : Json) : TestM String :=
  match errorDataString? json with
  | some text => pure text
  | none => fail s!"expected JSON-RPC error data string, got: {json.compress}"

private def mkRequestJson (id : Nat) (method : String) (params : Json) : Json :=
  Json.mkObj [
    ("jsonrpc", toJson "2.0"),
    ("id", toJson id),
    ("method", toJson method),
    ("params", params)
  ]

private def stopHubIO (rpc : RpcProcess) : IO Unit := do
  let _ ← rpc.stdin.flush.toBaseIO
  let _ ← rpc.child.kill.toBaseIO
  let _ ← rpc.child.wait.toBaseIO
  pure ()

@[inline] def stopHub (rpc : RpcProcess) : TestM Unit :=
  liftIO <| stopHubIO rpc

@[inline] def startHub : TestM RpcProcess := do
  let cwd ← liftIO IO.currentDir
  let child ← liftIO <| IO.Process.spawn {
    cmd := "lake"
    args := #["exe", "aftk_server"]
    cwd := some cwd
    stdin := .piped
    stdout := .piped
    stderr := .inherit
  }
  let nextId ← liftIO <| IO.mkRef 0
  pure {
    child := child
    stdin := IO.FS.Stream.ofHandle child.stdin
    stdout := IO.FS.Stream.ofHandle child.stdout
    nextId := nextId
  }

@[inline] def withHub {α : Type} (f : RpcProcess → TestM α) : TestM α := do
  let rpc ← startHub
  try
    f rpc
  finally
    discard <| liftIO <| stopHubIO rpc

@[inline] def RpcProcess.request (rpc : RpcProcess) (method : String) (params : Json := Json.mkObj []) : TestM Json := do
  let id ← liftIO <| rpc.nextId.modifyGet fun id => (id, id + 1)
  let payload := (mkRequestJson id method params).compress ++ "\n"
  liftIO <| rpc.stdin.putStr payload
  liftIO <| rpc.stdin.flush
  let line ← liftIO <| rpc.stdout.getLine
  if line.isEmpty then
    fail s!"unexpected EOF while waiting for response to {method}"
  assertJsonParses line.trimAscii.toString

@[inline] def RpcProcess.requestResult (rpc : RpcProcess) (method : String) (params : Json := Json.mkObj []) : TestM Json := do
  responseResult (← rpc.request method params)

@[inline] def copySemanticsFixtureTo (dir : System.FilePath) : TestM System.FilePath := do
  let src ← semanticsPath
  let dst := dir / "SemanticsCopy.lean"
  let text ← liftIO <| IO.FS.readFile src
  liftIO <| IO.FS.writeFile dst text
  pure dst

@[inline] def killWorkerFor (path : System.FilePath) : TestM Unit := do
  let cwd ← liftIO IO.currentDir
  let output ← liftIO <| IO.Process.output {
    cmd := "bash"
    args := #["-lc", s!"pgrep -f 'aftk_file_worker {path}' | head -n 1"]
    cwd := some cwd
  }
  let pidText := output.stdout.trimAscii.toString
  if pidText.isEmpty then
    fail s!"failed to locate worker pid for {path}"
  let pid := pidText.toNat?.getD 0
  if pid == 0 then
    fail s!"invalid worker pid '{pidText}'"
  let _ ← liftIO <| IO.Process.output {
    cmd := "kill"
    args := #["-TERM", toString pid]
    stdin := .null
    stdout := .null
    stderr := .null
  }
  liftIO <| IO.sleep 200

end AFTKTest.Server.Fixtures
