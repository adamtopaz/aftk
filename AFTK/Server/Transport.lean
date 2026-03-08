import AFTK.Server.Protocol
import LeanWorker

namespace AFTK.Server.Transport

open Lean
open LeanWorker
open LeanWorker.JsonRpc
open Std.Internal.IO.Async
open AFTK.Server.Protocol

abbrev JsonTransport := LeanWorker.Transport.Transport

abbrev WorkerChild :=
  IO.Process.Child { stdin := .piped, stdout := .piped, stderr := .inherit }

abbrev RpcClient := LeanWorker.Client.Client


def objParams (fields : List (String × Json)) : Json.Structured :=
  match Json.mkObj fields with
  | .obj kvs => .obj kvs
  | _ => .obj {}


def serverTransportFromStdio : IO JsonTransport := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  Async.block <| LeanWorker.Transport.serverTransportFromStreams
    stdin stdout .newline LeanWorker.Transport.silentLogger


def clientTransportFromChild (child : WorkerChild) : IO JsonTransport := do
  let stdin := IO.FS.Stream.ofHandle child.stdin
  let stdout := IO.FS.Stream.ofHandle child.stdout
  Async.block <| LeanWorker.Transport.clientTransportFromStreams
    stdout stdin .newline LeanWorker.Transport.silentLogger


def clientFromChild (child : WorkerChild) : IO RpcClient := do
  let transport ← clientTransportFromChild child
  Async.block <| LeanWorker.Client.getClient transport


def requestJson (client : RpcClient) (method : String) (params? : Option Json.Structured := none) : IO Json := do
  match ← (EAsync.block <| client.request method params?).toBaseIO with
  | .ok json =>
      pure json
  | .error err =>
      throw <| IO.userError s!"{err.message}"


def decodeResult [FromJson α] (json : Json) : Except String α :=
  fromJson? (α := α) json


private partial def waitForExitLoop (child : WorkerChild) (remainingMs pollMs : Nat) : IO Bool := do
  match ← child.tryWait.toBaseIO with
  | .ok (some _) =>
      pure true
  | .ok none =>
      if remainingMs == 0 then
        pure false
      else
        let nap := Nat.min remainingMs pollMs
        IO.sleep (UInt32.ofNat nap)
        waitForExitLoop child (remainingMs - nap) pollMs
  | .error _ =>
      pure true


def waitForExit (child : WorkerChild) (timeoutMs : Nat := 1500) (pollMs : Nat := 50) : IO Bool :=
  waitForExitLoop child timeoutMs pollMs


def sendShutdownRequest (client : RpcClient) : IO Unit := do
  let _ ← (EAsync.block <| client.request "shutdown" (some (objParams []))).toBaseIO
  pure ()


def forceKill (child : WorkerChild) : IO Unit := do
  let _ ← IO.Process.output {
    cmd := "kill"
    args := #["-KILL", toString child.pid]
    stdin := .null
    stdout := .null
    stderr := .null
  }
  pure ()


def stopChildGracefully (child : WorkerChild) (client : RpcClient) (timeoutMs : Nat := 1500) : IO Unit := do
  let _ ← (sendShutdownRequest client).toBaseIO
  if ← waitForExit child timeoutMs then
    let _ ← (Async.block client.shutdown).toBaseIO
    pure ()
  else
    let _ ← child.kill.toBaseIO
    if ← waitForExit child timeoutMs then
      let _ ← (Async.block client.shutdown).toBaseIO
      pure ()
    else
      forceKill child
      discard <| child.wait.toBaseIO
      let _ ← (Async.block client.shutdown).toBaseIO
      pure ()


def closeTransport (transport : JsonTransport) : IO Unit := do
  let _ ← transport.outbox.close.toBaseIO
  let _ ← transport.inbox.close.toBaseIO
  pure ()

end AFTK.Server.Transport
