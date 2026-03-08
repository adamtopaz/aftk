import AFTK.FileWorker
import AFTK.Server.Transport
import LeanWorker

open Std.Internal.IO.Async

unsafe def main (args : List String) : IO Unit := do
  let [path] := args
    | throw <| IO.userError "Usage: lake exe aftk_file_worker <path>"
  let worker ← AFTK.FileWorker.Context.build path {}
  let transport ← AFTK.Server.Transport.serverTransportFromStdio
  let runtime : AFTK.FileWorker.Handlers.RuntimeContext := {
    worker := worker
    transport := transport
  }
  let state ← Std.Mutex.new ({ } : AFTK.FileWorker.TacticState.State)
  let server := LeanWorker.Server.run (AFTK.FileWorker.Handlers.server transport) runtime state
  try
    server.block
  finally
    let _ ← transport.outbox.close.toBaseIO
    let _ ← transport.inbox.close.toBaseIO
    pure ()
