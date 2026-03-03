module

public import LeanWorker

namespace AFTK

open Lean
open LeanWorker
open LeanWorker.JsonRpc
open Std.Internal.IO.Async

structure Context where

abbrev WorkerChild :=
  IO.Process.Child { stdin := .piped, stdout := .piped, stderr := .inherit }

structure FileStamp where
  modified : IO.FS.SystemTime
  byteSize : UInt64
deriving BEq, Repr

structure WorkerSession where
  path : String
  stamp : FileStamp
  child : WorkerChild
  client : LeanWorker.Client.Client

structure State where
  sessions : Std.TreeMap String WorkerSession := {}

abbrev HubM := LeanWorker.Server.StatefulHandlerM Context State

def invalidParamsError (message : String) : LeanWorker.JsonRpc.Error :=
  LeanWorker.JsonRpc.Error.withData LeanWorker.JsonRpc.Error.invalidParams (.str message)

def internalError (message : String) : LeanWorker.JsonRpc.Error :=
  LeanWorker.JsonRpc.Error.withData LeanWorker.JsonRpc.Error.internalError (.str message)

def fileNotOpenError (path : String) : LeanWorker.JsonRpc.Error :=
  { code := -32010, message := "File is not open", data? := some (.str path) }

def fileChangedError (path : String) : LeanWorker.JsonRpc.Error :=
  { code := -32011, message := "File changed; reopen required", data? := some (.str path) }

def workerUnavailableError (path : String) : LeanWorker.JsonRpc.Error :=
  { code := -32012, message := "File worker is unavailable", data? := some (.str path) }

def liftIO (action : IO α)
    (onError : IO.Error → LeanWorker.JsonRpc.Error := fun err => internalError (toString err)) :
    HubM α := do
  match ← action.toBaseIO with
  | .ok value => return value
  | .error err => throw <| onError err

def normalizePathIO (rawPath : String) : IO String := do
  let path := System.FilePath.mk rawPath
  let absolute ←
    if path.isAbsolute then
      pure path
    else
      pure ((← IO.Process.getCurrentDir) / path)
  return absolute.normalize.toString

def canonicalizePath (rawPath : String) : HubM String := do
  let path := System.FilePath.mk rawPath
  match ← (IO.FS.realPath path).toBaseIO with
  | .ok realPath =>
    return realPath.toString
  | .error _ =>
    liftIO (normalizePathIO rawPath)
      (fun err => invalidParamsError s!"invalid path '{rawPath}': {err}")

def readFileStampIO (path : String) : IO FileStamp := do
  let metadata ← (System.FilePath.mk path).metadata
  if metadata.type != .file then
    throw <| IO.userError s!"not a regular file: {path}"
  return { modified := metadata.modified, byteSize := metadata.byteSize }

def sessionFileChanged (session : WorkerSession) : BaseIO Bool := do
  match ← (readFileStampIO session.path).toBaseIO with
  | .ok stamp =>
    return stamp != session.stamp
  | .error _ =>
    return true

def sessionIsDead (session : WorkerSession) : BaseIO Bool := do
  match ← session.child.tryWait.toBaseIO with
  | .ok none =>
    return false
  | .ok (some _) =>
    return true
  | .error _ =>
    return true

def spawnWorkerProcess (path : String) : IO WorkerChild := do
  IO.Process.spawn {
    cmd := "lake"
    args := #["exe", "aftk_file_worker", path]
    stdin := .piped
    stdout := .piped
    stderr := .inherit
    setsid := true
  }

def spawnSessionIO (path : String) (stamp : FileStamp) : IO WorkerSession := do
  let child ← spawnWorkerProcess path
  let stdin := IO.FS.Stream.ofHandle child.stdin
  let stdout := IO.FS.Stream.ofHandle child.stdout
  let transport ← Async.block <| LeanWorker.Transport.clientTransportFromStreams stdout stdin
  let client ← Async.block <| LeanWorker.Client.getClient transport
  return { path, stamp, child, client }

def spawnSession (path : String) : HubM WorkerSession := do
  let stamp ← liftIO (readFileStampIO path)
    (fun err => invalidParamsError s!"cannot read file '{path}': {err}")
  liftIO (spawnSessionIO path stamp)
    (fun err => internalError s!"failed to spawn file worker for '{path}': {err}")

def stopSession (session : WorkerSession) : BaseIO Unit := do
  let _ ← (Async.block session.client.shutdown).toBaseIO
  match ← session.child.tryWait.toBaseIO with
  | .ok (some _) =>
    return
  | _ =>
    let _ ← session.child.kill.toBaseIO
    let _ ← session.child.wait.toBaseIO
    return

def stopAllSessions : HubM Nat := do
  let sessions := (← get).sessions.toArray
  modify fun s => { s with sessions := {} }
  for (_, session) in sessions do
    stopSession session
  return sessions.size

def ensureSessionReady (path : String) : HubM WorkerSession := do
  let some session := (← get).sessions.get? path
    | throw <| fileNotOpenError path

  if ← sessionIsDead session then
    modify fun s => { s with sessions := s.sessions.erase path }
    stopSession session
    throw <| workerUnavailableError path

  if ← sessionFileChanged session then
    modify fun s => { s with sessions := s.sessions.erase path }
    stopSession session
    throw <| fileChangedError path

  return session

def forwardToWorker (path method : String) (params? : Option Json.Structured) : HubM Json := do
  let session ← ensureSessionReady path
  match ← (EAsync.block <| session.client.request method params?).toBaseIO with
  | .ok result =>
    return result
  | .error err =>
    if ← sessionIsDead session then
      modify fun s => { s with sessions := s.sessions.erase path }
      stopSession session
    throw err

def forwardBatchToWorker
    (path : String)
    (items : Array (String × Option Json.Structured × LeanWorker.Client.Kind)) :
    HubM (Array <| Option <| Except LeanWorker.JsonRpc.Error Json) := do
  let session ← ensureSessionReady path
  match ← (EAsync.block <| session.client.batch items).toBaseIO with
  | .ok result =>
    return result
  | .error err =>
    if ← sessionIsDead session then
      modify fun s => { s with sessions := s.sessions.erase path }
      stopSession session
    throw err

def decodeWorkerResult [FromJson α] (path method : String) (json : Json) : HubM α := do
  match fromJson? (α := α) json with
  | .ok value =>
    return value
  | .error err =>
    throw <| internalError s!"invalid result from worker for '{path}' ({method}): {err}"

def objParams (fields : List (String × Json)) : Json.Structured :=
  match Json.mkObj fields with
  | .obj kvs => .obj kvs
  | _ => .obj {}

structure OpenParam where
  path : String
deriving FromJson

structure OpenResult where
  path : String
  opened : Bool
deriving ToJson

structure CloseParam where
  path : String
deriving FromJson

structure CloseResult where
  path : String
  closed : Bool
deriving ToJson

structure LoadNodeParam where
  path : String
  line : Nat
  col : Nat
deriving FromJson

structure GetGoalsParam where
  path : String
  id : String
deriving FromJson

structure RunTacticParam where
  path : String
  id : String
  tactic : String
deriving FromJson

structure RunTacticStepsParam where
  path : String
  id : String
  tactics : Array String
deriving FromJson

structure LoadNodeResult where
  id : Array String
deriving ToJson, FromJson

structure GetGoalsResult where
  goals : List String
deriving ToJson, FromJson

structure RunTacticResult where
  goals : List String
  nextId : String
deriving ToJson, FromJson

structure RunTacticStepsResult where
  results : Array RunTacticResult
deriving ToJson

structure ShutdownResult where
  stopped : Nat
deriving ToJson

def openFile : LeanWorker.Server.StatefulHandler Context State OpenParam OpenResult := fun param => do
  let some ⟨rawPath⟩ := param
    | throw <| invalidParamsError "params object required"

  let path ← canonicalizePath rawPath

  match (← get).sessions.get? path with
  | some session =>
    let dead ← sessionIsDead session
    let changed : Bool ←
      if dead then
        pure false
      else
        sessionFileChanged session

    if !dead && !changed then
      return ⟨path, false⟩

    modify fun s => { s with sessions := s.sessions.erase path }
    stopSession session

    let nextSession ← spawnSession path
    modify fun s => { s with sessions := s.sessions.insert path nextSession }
    return ⟨path, true⟩

  | none =>
    let session ← spawnSession path
    modify fun s => { s with sessions := s.sessions.insert path session }
    return ⟨path, true⟩

def closeFile : LeanWorker.Server.StatefulHandler Context State CloseParam CloseResult := fun param => do
  let some ⟨rawPath⟩ := param
    | throw <| invalidParamsError "params object required"

  let path ← canonicalizePath rawPath

  let some session := (← get).sessions.get? path
    | return ⟨path, false⟩

  modify fun s => { s with sessions := s.sessions.erase path }
  stopSession session
  return ⟨path, true⟩

def loadNode : LeanWorker.Server.StatefulHandler Context State LoadNodeParam LoadNodeResult := fun param => do
  let some ⟨rawPath, line, col⟩ := param
    | throw <| invalidParamsError "params object required"

  let path ← canonicalizePath rawPath
  let workerParams := objParams [
    ("line", toJson line),
    ("col", toJson col)
  ]
  let json ← forwardToWorker path "load_node" (some workerParams)
  decodeWorkerResult path "load_node" json

def getGoals : LeanWorker.Server.StatefulHandler Context State GetGoalsParam GetGoalsResult := fun param => do
  let some ⟨rawPath, id⟩ := param
    | throw <| invalidParamsError "params object required"

  let path ← canonicalizePath rawPath
  let workerParams := objParams [
    ("id", toJson id)
  ]
  let json ← forwardToWorker path "get_goals" (some workerParams)
  decodeWorkerResult path "get_goals" json

def runTactic : LeanWorker.Server.StatefulHandler Context State RunTacticParam RunTacticResult := fun param => do
  let some ⟨rawPath, id, tactic⟩ := param
    | throw <| invalidParamsError "params object required"

  let path ← canonicalizePath rawPath
  let workerParams := objParams [
    ("id", toJson id),
    ("tactic", toJson tactic)
  ]
  let json ← forwardToWorker path "run_tactic" (some workerParams)
  decodeWorkerResult path "run_tactic" json

def runTacticSteps : LeanWorker.Server.StatefulHandler Context State RunTacticStepsParam RunTacticStepsResult :=
    fun param => do
  let some ⟨rawPath, initialId, tactics⟩ := param
    | throw <| invalidParamsError "params object required"

  if tactics.isEmpty then
    throw <| invalidParamsError "tactics must be non-empty"

  let path ← canonicalizePath rawPath

  let mut currentId := initialId
  let mut results : Array RunTacticResult := #[]

  for tactic in tactics do
    let workerParams := objParams [
      ("id", toJson currentId),
      ("tactic", toJson tactic)
    ]
    let items := #[("run_tactic", some workerParams, LeanWorker.Client.Kind.request)]
    let batchResults ← forwardBatchToWorker path items

    if batchResults.size != 1 then
      throw <| internalError "invalid batch response size from file worker"

    let entry? := batchResults[0]!
    let json ←
      match entry? with
      | none =>
        throw <| internalError "missing batch response entry from file worker"
      | some result =>
        match result with
        | Except.error err =>
          throw err
        | Except.ok json =>
          pure json

    let result : RunTacticResult ← decodeWorkerResult path "run_tactic" json
    currentId := result.nextId
    results := results.push result

  return ⟨results⟩

def shutdownHub : LeanWorker.Server.StatefulHandler Context State Json.Structured ShutdownResult :=
    fun _ => do
  return ⟨← stopAllSessions⟩

def server (transport : LeanWorker.Transport.Transport) : LeanWorker.Server.Server Context State where
  handlers := LeanWorker.Server.HandlerRegistry.empty
    |>.addStateful "open" openFile
    |>.addStateful "close" closeFile
    |>.addStateful "load_node" loadNode
    |>.addStateful "get_goals" getGoals
    |>.addStateful "run_tactic" runTactic
    |>.addStateful "run_tactic_steps" runTacticSteps
    |>.addStateful "shutdown" shutdownHub
  notifications := .empty
  transport := transport

private def drainSessions (state : Std.Mutex State) : BaseIO (Array WorkerSession) :=
  state.atomically do
    let current ← get
    let sessions := current.sessions.toArray.map Prod.snd
    set { current with sessions := {} }
    return sessions

end AFTK

public def main (args : List String) : IO Unit := do
  let [] := args | throw <| .userError "Invalid args"
  let transport ← LeanWorker.Transport.serverTransportFromStdio |>.block
  let state : Std.Mutex AFTK.State ← Std.Mutex.new { sessions := {} }
  let server := LeanWorker.Server.run (AFTK.server transport) {} state
  try
    server.block
  finally
    for session in (← AFTK.drainSessions state) do
      AFTK.stopSession session
