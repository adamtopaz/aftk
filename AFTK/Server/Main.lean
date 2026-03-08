module

public import AFTK.Server
public import LeanWorker

public section


unsafe def main (args : List String) : IO Unit := do
  let [] := args
    | throw <| IO.userError "Usage: lake exe aftk_server"
  let transport ← AFTK.Server.Transport.serverTransportFromStdio
  let state ← Std.Mutex.new ({ } : AFTK.Server.Hub.State)
  let ctx : AFTK.Server.Hub.Context := {
    state := state
  }
  let server := LeanWorker.Server.run (AFTK.Server.Hub.server transport) ctx <| ← Std.Mutex.new ()
  try
    server.block
  finally
    for session in (← AFTK.Server.Hub.drainSessions state) do
      AFTK.Server.Hub.stopSessionIO session
