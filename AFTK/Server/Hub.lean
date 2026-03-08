import AFTK.Server.Protocol
import AFTK.Server.Transport
import LeanWorker

namespace AFTK.Server.Hub

open Lean
open LeanWorker
open LeanWorker.JsonRpc
open Std.Internal.IO.Async
open AFTK.Server.Protocol
open AFTK.Server.Transport

structure FileIdentity where
  normalizedPath : System.FilePath
  canonicalPath : System.FilePath
  deriving Repr, Inhabited

structure FileStamp where
  modified : IO.FS.SystemTime
  byteSize : UInt64
  deriving Repr, BEq

structure WorkerSession where
  sessionId : Nat
  identity : FileIdentity
  stamp : FileStamp
  child : WorkerChild
  client : RpcClient
  lock : Std.Mutex Unit

structure State where
  sessions : Std.TreeMap String WorkerSession := {}
  aliases : Std.TreeMap String String := {}
  nextSessionId : Nat := 0

structure Context where
  state : Std.Mutex State
  transport : JsonTransport

abbrev HubM := LeanWorker.Server.StatelessHandlerM Context

private def canonicalKey (identity : FileIdentity) : String :=
  identity.canonicalPath.toString

private def normalizedKey (identity : FileIdentity) : String :=
  identity.normalizedPath.toString

private def eraseSession (state : State) (session : WorkerSession) : State :=
  { state with
    sessions := state.sessions.erase (canonicalKey session.identity)
    aliases := state.aliases.erase (normalizedKey session.identity)
  }

private def insertSession (state : State) (session : WorkerSession) : State :=
  { state with
    sessions := state.sessions.insert (canonicalKey session.identity) session
    aliases := state.aliases.insert (normalizedKey session.identity) (canonicalKey session.identity)
  }

private def lookupSession (state : State) (identity : FileIdentity) : Option WorkerSession :=
  match state.sessions.get? (canonicalKey identity) with
  | some session =>
      some session
  | none =>
      match state.aliases.get? (normalizedKey identity) with
      | some canonical => state.sessions.get? canonical
      | none => none

private def liftIO (action : IO α) (onError : IO.Error → JsonRpc.Error := fun err => internalError (toString err)) : HubM α := do
  match ← action.toBaseIO with
  | .ok value =>
      pure value
  | .error err =>
      throw <| onError err


def normalizePathIO (rawPath : String) : IO System.FilePath := do
  let path := System.FilePath.mk rawPath
  let absolute ←
    if path.isAbsolute then
      pure path
    else
      pure ((← IO.Process.getCurrentDir) / path)
  pure absolute.normalize


def resolveFileIdentityIO (rawPath : String) : IO FileIdentity := do
  let normalizedPath ← normalizePathIO rawPath
  let canonicalPath ←
    match ← (IO.FS.realPath normalizedPath).toBaseIO with
    | .ok canonical => pure canonical.normalize
    | .error _ => pure normalizedPath
  pure { normalizedPath, canonicalPath }


def readFileStampIO (path : System.FilePath) : IO (Except JsonRpc.Error FileStamp) := do
  match ← path.metadata.toBaseIO with
  | .error err =>
      pure <| .error <| invalidParamsError s!"cannot read file '{path}': {err}"
  | .ok metadata =>
      if metadata.type != .file then
        pure <| .error <| invalidParamsError s!"cannot read file '{path}': not a regular file"
      else
        pure <| .ok { modified := metadata.modified, byteSize := metadata.byteSize }


def sessionFileChanged (session : WorkerSession) : IO Bool := do
  match ← readFileStampIO session.identity.canonicalPath with
  | .ok stamp =>
      pure (stamp != session.stamp)
  | .error _ =>
      pure true


def sessionIsDead (session : WorkerSession) : IO Bool := do
  match ← session.child.tryWait.toBaseIO with
  | .ok none =>
      pure false
  | .ok (some _) =>
      pure true
  | .error _ =>
      pure true


def spawnWorkerProcess (path : System.FilePath) : IO WorkerChild := do
  IO.Process.spawn {
    cmd := "lake"
    args := #["exe", "aftk_file_worker", path.toString]
    stdin := .piped
    stdout := .piped
    stderr := .inherit
    setsid := true
  }


def spawnSessionIO (sessionId : Nat) (identity : FileIdentity) : IO (Except JsonRpc.Error WorkerSession) := do
  let stampResult ← readFileStampIO identity.canonicalPath
  match stampResult with
  | .error err =>
      pure (.error err)
  | .ok stamp =>
      match ← (do
        let child ← spawnWorkerProcess identity.canonicalPath
        let client ← clientFromChild child
        let lock ← Std.Mutex.new ()
        pure ({ sessionId, identity, stamp, child, client, lock } : WorkerSession)).toBaseIO with
      | .error err =>
          pure <| .error <| internalError s!"failed to spawn file worker for '{identity.canonicalPath}': {err}"
      | .ok session =>
          if ← sessionIsDead session then
            stopChildGracefully session.child session.client
            pure <| .error <| workerUnavailableError (canonicalKey identity)
          else
            pure <| .ok session


def stopSessionIO (session : WorkerSession) : IO Unit :=
  stopChildGracefully session.child session.client


def removeSessionIfCurrentIO (stateRef : Std.Mutex State) (session : WorkerSession) : IO Unit := do
  stateRef.atomically do
    let current ← get
    match current.sessions.get? (canonicalKey session.identity) with
    | some liveSession =>
        if liveSession.sessionId == session.sessionId then
          set (eraseSession current session)
    | none =>
        pure ()


def drainSessions (stateRef : Std.Mutex State) : IO (Array WorkerSession) := do
  stateRef.atomically do
    let current ← get
    let sessions := current.sessions.toArray.map Prod.snd
    set ({ } : State)
    pure sessions


def stopAllSessions (stateRef : Std.Mutex State) : IO Nat := do
  let sessions ← drainSessions stateRef
  for session in sessions do
    stopSessionIO session
  pure sessions.size

private def decodeWorkerResult [FromJson α] (path method : String) (json : Json) : Except JsonRpc.Error α := do
  match fromJson? (α := α) json with
  | .ok value =>
      pure value
  | .error err =>
      throw <| internalError s!"invalid result from worker for '{path}' ({method}): {err}"

private def lookupSessionForPath (ctx : Context) (rawPath : String) : IO (String × Option WorkerSession) := do
  let identity ← resolveFileIdentityIO rawPath
  ctx.state.atomically do
    let state ← get
    let session? := lookupSession state identity
    let path := session?.map (canonicalKey ·.identity) |>.getD (canonicalKey identity)
    pure (path, session?)

private def withCheckedSessionIO (ctx : Context) (session : WorkerSession)
    (k : WorkerSession → IO (Except JsonRpc.Error α)) : IO (Except JsonRpc.Error α) := do
  session.lock.atomically do
    if ← sessionIsDead session then
      removeSessionIfCurrentIO ctx.state session
      stopSessionIO session
      pure <| .error <| workerUnavailableError (canonicalKey session.identity)
    else if ← sessionFileChanged session then
      removeSessionIfCurrentIO ctx.state session
      stopSessionIO session
      pure <| .error <| fileChangedError (canonicalKey session.identity)
    else
      let result ← k session
      match result with
      | .ok value =>
          pure (.ok value)
      | .error err =>
          if ← sessionIsDead session then
            removeSessionIfCurrentIO ctx.state session
            stopSessionIO session
            pure <| .error <| workerUnavailableError (canonicalKey session.identity)
          else
            pure (.error err)

private def requestWorkerDecodedIO [FromJson α]
    (session : WorkerSession)
    (method : String)
    (params? : Option Json.Structured := none) : IO (Except JsonRpc.Error α) := do
  match ← (EAsync.block <| session.client.request method params?).toBaseIO with
  | .error err =>
      pure <| .error err
  | .ok json =>
      pure <| decodeWorkerResult (canonicalKey session.identity) method json

private def requestWorkerJsonIO
    (session : WorkerSession)
    (method : String)
    (params? : Option Json.Structured := none) : IO (Except JsonRpc.Error Json) := do
  match ← (EAsync.block <| session.client.request method params?).toBaseIO with
  | .error err =>
      pure <| .error err
  | .ok json =>
      pure <| .ok json


def openFileIO (ctx : Context) (rawPath : String) : IO (Except JsonRpc.Error OpenResult) := do
  let identity ← resolveFileIdentityIO rawPath
  ctx.state.atomically do
    let state ← get
    match lookupSession state identity with
    | some session =>
        let dead ← sessionIsDead session
        let changed ← if dead then pure false else sessionFileChanged session
        if !dead && !changed then
          pure <| .ok { path := canonicalKey session.identity, opened := false }
        else
          let nextId := state.nextSessionId
          set { eraseSession state session with nextSessionId := nextId + 1 }
          stopSessionIO session
          match ← spawnSessionIO nextId identity with
          | .error err =>
              pure (.error err)
          | .ok nextSession =>
              modify fun state => insertSession state nextSession
              pure <| .ok { path := canonicalKey nextSession.identity, opened := true }
    | none =>
        let nextId := state.nextSessionId
        set { state with nextSessionId := nextId + 1 }
        match ← spawnSessionIO nextId identity with
        | .error err =>
            pure (.error err)
        | .ok session =>
            modify fun state => insertSession state session
            pure <| .ok { path := canonicalKey session.identity, opened := true }


def closeFileIO (ctx : Context) (rawPath : String) : IO (Except JsonRpc.Error CloseResult) := do
  let identity ← resolveFileIdentityIO rawPath
  ctx.state.atomically do
    let state ← get
    match lookupSession state identity with
    | none =>
        pure <| .ok { path := canonicalKey identity, closed := false }
    | some session =>
        set (eraseSession state session)
        stopSessionIO session
        pure <| .ok { path := canonicalKey session.identity, closed := true }


def shutdownIO (ctx : Context) : IO (Except JsonRpc.Error ShutdownResult) := do
  let stopped ← stopAllSessions ctx.state
  let _ ← ctx.transport.inbox.close.toBaseIO
  pure <| .ok { stopped := stopped }

private def withFileSession [FromJson α]
    (ctx : Context)
    (rawPath : String)
    (k : WorkerSession → IO (Except JsonRpc.Error α)) : IO (Except JsonRpc.Error α) := do
  let (path, session?) ← lookupSessionForPath ctx rawPath
  let some session := session?
    | pure <| .error <| fileNotOpenError path
  withCheckedSessionIO ctx session k


def loadNodeIO (ctx : Context) (rawPath : String) (line col : Nat) : IO (Except JsonRpc.Error LoadNodeResult) :=
  withFileSession ctx rawPath fun session =>
    requestWorkerDecodedIO session "load_node" (some <| objParams [("line", toJson line), ("col", toJson col)])


def getHoverIO (ctx : Context) (rawPath : String) (line col : Nat) : IO (Except JsonRpc.Error (Option HoverResult)) :=
  withFileSession ctx rawPath fun session =>
    requestWorkerDecodedIO session "get_hover" (some <| objParams [("line", toJson line), ("col", toJson col)])


def getPlainGoalIO (ctx : Context) (rawPath : String) (line col : Nat) : IO (Except JsonRpc.Error (Option PlainGoalResult)) :=
  withFileSession ctx rawPath fun session =>
    requestWorkerDecodedIO session "get_plain_goal" (some <| objParams [("line", toJson line), ("col", toJson col)])


def getPlainTermGoalIO (ctx : Context) (rawPath : String) (line col : Nat) : IO (Except JsonRpc.Error (Option PlainTermGoalResult)) :=
  withFileSession ctx rawPath fun session =>
    requestWorkerDecodedIO session "get_plain_term_goal" (some <| objParams [("line", toJson line), ("col", toJson col)])


def getInfoViewIO (ctx : Context) (rawPath : String) (line col : Nat) : IO (Except JsonRpc.Error InfoViewResult) :=
  withFileSession ctx rawPath fun session =>
    requestWorkerDecodedIO session "get_infoview" (some <| objParams [("line", toJson line), ("col", toJson col)])


def getGoalsIO (ctx : Context) (rawPath : String) (id : String) : IO (Except JsonRpc.Error GetGoalsResult) :=
  withFileSession ctx rawPath fun session =>
    requestWorkerDecodedIO session "get_goals" (some <| objParams [("id", toJson id)])


def runTacticIO (ctx : Context) (rawPath : String) (id tactic : String) : IO (Except JsonRpc.Error RunTacticResult) :=
  withFileSession ctx rawPath fun session =>
    requestWorkerDecodedIO session "run_tactic" (some <| objParams [("id", toJson id), ("tactic", toJson tactic)])


def runTacticStepsIO
    (ctx : Context)
    (rawPath : String)
    (initialId : String)
    (tactics : Array String) : IO (Except JsonRpc.Error RunTacticStepsResult) := do
  if tactics.isEmpty then
    return .error <| invalidParamsError "tactics must be non-empty"
  withFileSession ctx rawPath fun session => do
    let mut currentId := initialId
    let mut results : Array RunTacticResult := #[]
    for tactic in tactics do
      match ← requestWorkerJsonIO session "run_tactic"
          (some <| objParams [("id", toJson currentId), ("tactic", toJson tactic)]) with
      | .error err =>
          return .error err
      | .ok json =>
          match decodeWorkerResult (canonicalKey session.identity) "run_tactic" json with
          | .error err =>
              return .error err
          | .ok result =>
              currentId := result.nextId
              results := results.push result
    return .ok { results := results }

private def fromIOResult (action : IO (Except JsonRpc.Error α)) : HubM α := do
  match ← action.toBaseIO with
  | .error err =>
      throw <| internalError (toString err)
  | .ok (.error err) =>
      throw err
  | .ok (.ok value) =>
      pure value


def openFile : LeanWorker.Server.StatelessHandler Context OpenParam OpenResult := fun param => do
  let some ⟨path⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| openFileIO ctx path


def closeFile : LeanWorker.Server.StatelessHandler Context CloseParam CloseResult := fun param => do
  let some ⟨path⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| closeFileIO ctx path


def loadNode : LeanWorker.Server.StatelessHandler Context FileLocationParam LoadNodeResult := fun param => do
  let some ⟨path, line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| loadNodeIO ctx path line col


def getHover : LeanWorker.Server.StatelessHandler Context FileLocationParam (Option HoverResult) := fun param => do
  let some ⟨path, line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| getHoverIO ctx path line col


def getPlainGoal : LeanWorker.Server.StatelessHandler Context FileLocationParam (Option PlainGoalResult) := fun param => do
  let some ⟨path, line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| getPlainGoalIO ctx path line col


def getPlainTermGoal : LeanWorker.Server.StatelessHandler Context FileLocationParam (Option PlainTermGoalResult) := fun param => do
  let some ⟨path, line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| getPlainTermGoalIO ctx path line col


def getInfoView : LeanWorker.Server.StatelessHandler Context FileLocationParam InfoViewResult := fun param => do
  let some ⟨path, line, col⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| getInfoViewIO ctx path line col


def getGoals : LeanWorker.Server.StatelessHandler Context FileNodeParam GetGoalsResult := fun param => do
  let some ⟨path, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| getGoalsIO ctx path id


def runTactic : LeanWorker.Server.StatelessHandler Context RunTacticParam RunTacticResult := fun param => do
  let some ⟨path, id, tactic⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runTacticIO ctx path id tactic


def runTacticSteps : LeanWorker.Server.StatelessHandler Context RunTacticStepsParam RunTacticStepsResult := fun param => do
  let some ⟨path, id, tactics⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runTacticStepsIO ctx path id tactics


def shutdownHub : LeanWorker.Server.StatelessHandler Context ShutdownParam ShutdownResult := fun _ => do
  let ctx ← read
  fromIOResult <| shutdownIO ctx


def server (transport : JsonTransport) : LeanWorker.Server.Server Context Unit where
  handlers := LeanWorker.Server.HandlerRegistry.empty
    |>.addStateless "open" openFile
    |>.addStateless "close" closeFile
    |>.addStateless "load_node" loadNode
    |>.addStateless "get_hover" getHover
    |>.addStateless "get_plain_goal" getPlainGoal
    |>.addStateless "get_plain_term_goal" getPlainTermGoal
    |>.addStateless "get_infoview" getInfoView
    |>.addStateless "get_goals" getGoals
    |>.addStateless "run_tactic" runTactic
    |>.addStateless "run_tactic_steps" runTacticSteps
    |>.addStateless "shutdown" shutdownHub
  notifications := .empty
  transport := transport

end AFTK.Server.Hub
