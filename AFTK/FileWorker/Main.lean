module

public import AFTK.FileWorker
public import AFTK.Server.Transport
public import LeanWorker

public section


unsafe def main (args : List String) : IO Unit := do
  let [path] := args
    | throw <| IO.userError "Usage: lake exe aftk_file_worker <path>"
  let worker ← AFTK.FileWorker.Context.build path {}
  let transport ← AFTK.Server.Transport.serverTransportFromStdio
  let runtime : AFTK.FileWorker.Handlers.RuntimeContext := {
    worker := worker
  }
  let state ← Std.Mutex.new ({ } : AFTK.FileWorker.TacticState.State)
  let server := LeanWorker.Server.run (AFTK.FileWorker.Handlers.server transport) runtime state
  server.block
