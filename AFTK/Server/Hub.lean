module

public import AFTK.Server.Protocol
public import AFTK.Server.Transport
public import LeanWorker

public section


namespace AFTK.Server.Hub

open Lean
open LeanWorker
open LeanWorker.JsonRpc
open Std.Internal.IO.Async
open AFTK.Server.Protocol
open AFTK.Server.Transport
open AFTK.KnowledgeBase
open AFTK.Informal

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
  knowledgeBaseLock : Std.Mutex Unit

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

private def rootPathOf? (root? : Option String) : Option System.FilePath :=
  root?.map System.FilePath.mk

private def withKnowledgeBaseLockIO (ctx : Context) (action : IO (Except JsonRpc.Error α)) : IO (Except JsonRpc.Error α) :=
  ctx.knowledgeBaseLock.atomically action

private def runDomainEIO
    (ctx : Context)
    (layer : String)
    (action : KBIO α)
    (useLock : Bool := true) : IO (Except JsonRpc.Error α) := do
  let run := do
    match ← action.toIO' with
    | .ok value => pure <| .ok value
    | .error err => pure <| .error <| knowledgeBaseError layer err
  if useLock then
    withKnowledgeBaseLockIO ctx run
  else
    run

private def runDomainIO
    (ctx : Context)
    (layer : String)
    (action : IO (Except KnowledgeBaseError α))
    (useLock : Bool := false) : IO (Except JsonRpc.Error α) := do
  let run := do
    match ← action.toBaseIO with
    | .error err => pure <| .error <| internalError (toString err)
    | .ok (.ok value) => pure <| .ok value
    | .ok (.error err) => pure <| .error <| knowledgeBaseError layer err
  if useLock then
    withKnowledgeBaseLockIO ctx run
  else
    run

private def mapExcept (f : α → β) : Except ε α → Except ε β
  | .ok value => .ok (f value)
  | .error err => .error err

private def nameString (name : Name) : String :=
  toString name

private def informalDeclDtoOf (entry : InformalDeclEntry) : InformalDeclDto :=
  {
    declName := nameString entry.declName
    refs := entry.refs
    refCount := entry.refs.size
  }

private def informalRefDtoOf (entry : InformalReferenceEntry) : InformalRefDto :=
  {
    ref := entry.ref
    declNames := entry.declNames.map nameString
    declCount := entry.declNames.size
  }

private def informalDeclDependencyDtoOf (entry : InformalDeclDependencyEntry) : InformalDeclDependencyDto :=
  {
    declName := nameString entry.declName
    dependencies := entry.dependencies.map nameString
  }

private def informalRefDependencyDtoOf (entry : InformalReferenceDependencyEntry) : InformalRefDependencyDto :=
  {
    ref := entry.ref
    dependencies := entry.dependencies
  }

private def parseModuleNamesHub (modules : Array String) : HubM (Array Name) := do
  if modules.isEmpty then
    throw <| invalidParamsError "modules must be non-empty"
  match AFTK.Informal.Service.parseModuleNames modules with
  | .ok parsed => pure parsed
  | .error err => throw <| knowledgeBaseError "informal" err

private def parseDeclNameHub (raw : String) : HubM Name := do
  match AFTK.Informal.Service.parseDeclName raw with
  | .ok name => pure name
  | .error err => throw <| knowledgeBaseError "informal" err

private def decodeMetadataReplacement (json : Json) : HubM NodeMetadata := do
  match AFTK.KnowledgeBase.Serialization.parseNodeMetadataJson json with
  | .ok metadata => pure metadata
  | .error err => throw <| invalidParamsError s!"invalid metadata payload: {err}"


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


def knowledgeBaseInit : LeanWorker.Server.StatelessHandler Context KnowledgeBaseRootParam KnowledgeBaseStoragePaths := fun param => do
  let some ⟨root?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.init (rootPathOf? root?)


def knowledgeBaseStatus : LeanWorker.Server.StatelessHandler Context KnowledgeBaseRootParam KnowledgeBaseStatusResult := fun param => do
  let some ⟨root?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.status (rootPathOf? root?)


def knowledgeBaseList : LeanWorker.Server.StatelessHandler Context KnowledgeBaseListParam KnowledgeBaseListResult := fun param => do
  let some ⟨root?, prefix?, kind?, status?, tag?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" do
    let nodes ← AFTK.KnowledgeBase.Service.list (rootPathOf? root?) prefix? kind? status? tag?
    pure { nodes }


def knowledgeBaseShow : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam StoredNode := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.showNode id (rootPathOf? root?)


def knowledgeBaseGetBody : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam KnowledgeBaseBodyResult := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" do
    let body ← AFTK.KnowledgeBase.Service.getBody id (rootPathOf? root?)
    pure { id, body }


def knowledgeBaseGetMetadata : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam NodeMetadata := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.getMetadata id (rootPathOf? root?)


def knowledgeBaseGetPaths : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam KnowledgeBasePathsResult := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" do
    let paths ← AFTK.KnowledgeBase.Service.getPaths id (rootPathOf? root?)
    pure { id, paths }


def knowledgeBaseCreate : LeanWorker.Server.StatelessHandler Context KnowledgeBaseCreateParam StoredNode := fun param => do
  let some ⟨root?, id, title, body?, kind?, status?, summary?, tags?, authors?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <|
    AFTK.KnowledgeBase.Service.create id title
      (body?.getD "")
      (kind?.getD .note)
      (status?.getD .draft)
      summary?
      (tags?.getD #[])
      (authors?.getD #[])
      (rootPathOf? root?)


def knowledgeBaseRename : LeanWorker.Server.StatelessHandler Context KnowledgeBaseRenameParam KnowledgeBaseRenameResult := fun param => do
  let some ⟨root?, oldId, newId⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" do
    let stored ← AFTK.KnowledgeBase.Service.rename oldId newId (rootPathOf? root?)
    pure { oldId, stored }


def knowledgeBaseDelete : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam KnowledgeBaseDeleteResult := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" do
    AFTK.KnowledgeBase.Service.delete id (rootPathOf? root?)
    pure { id, deleted := true }


def knowledgeBaseSetBody : LeanWorker.Server.StatelessHandler Context KnowledgeBaseSetBodyParam StoredNode := fun param => do
  let some ⟨root?, id, body⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.setBody id body (rootPathOf? root?)


def knowledgeBaseReplaceMetadata : LeanWorker.Server.StatelessHandler Context KnowledgeBaseReplaceMetadataParam StoredNode := fun param => do
  let some ⟨root?, id, metadataJson⟩ := param
    | throw <| invalidParamsError "params object required"
  let metadata ← decodeMetadataReplacement metadataJson
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.replaceMetadata id metadata (rootPathOf? root?)


def knowledgeBaseValidateMetadata : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam Validation.ValidationReport := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.validateMetadata id (rootPathOf? root?)


def knowledgeBaseValidateStorage : LeanWorker.Server.StatelessHandler Context KnowledgeBaseRootParam Validation.ValidationReport := fun param => do
  let some ⟨root?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.validateStorage (rootPathOf? root?)


def knowledgeBaseValidateNode : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam Validation.ValidationReport := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.validateNode id (rootPathOf? root?)


def knowledgeBaseValidateAll : LeanWorker.Server.StatelessHandler Context KnowledgeBaseRootParam Validation.ValidationReport := fun param => do
  let some ⟨root?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.validateAll (rootPathOf? root?)


def knowledgeBaseSearchText : LeanWorker.Server.StatelessHandler Context KnowledgeBaseSearchTextParam Search.SearchResult := fun param => do
  let some ⟨root?, query, limit?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.searchText query limit? (rootPathOf? root?)


def knowledgeBaseSearchTag : LeanWorker.Server.StatelessHandler Context KnowledgeBaseSearchTagParam Search.SearchResult := fun param => do
  let some ⟨root?, tag, limit?⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.searchTag tag limit? (rootPathOf? root?)


def knowledgeBaseRelationshipsOutgoing : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam KnowledgeBaseOutgoingRelationshipsResult := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" do
    let relationships ← AFTK.KnowledgeBase.Service.outgoingRelationships id (rootPathOf? root?)
    pure { id, relationships }


def knowledgeBaseRelationshipsIncoming : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam KnowledgeBaseIncomingRelationshipsResult := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" do
    let relationships ← AFTK.KnowledgeBase.Service.incomingRelationships id (rootPathOf? root?)
    pure { id, relationships }


def knowledgeBaseRelationshipsRelated : LeanWorker.Server.StatelessHandler Context KnowledgeBaseNodeParam Search.RelatedRelationships := fun param => do
  let some ⟨root?, id⟩ := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "knowledgebase" <| AFTK.KnowledgeBase.Service.relatedRelationships id (rootPathOf? root?)


unsafe def informalStatus : LeanWorker.Server.StatelessHandler Context InformalModulesParam InformalStatusResult := fun param => do
  let some ⟨modulesRaw⟩ := param
    | throw <| invalidParamsError "params object required"
  let modules ← parseModuleNamesHub modulesRaw
  let ctx ← read
  fromIOResult <| runDomainIO ctx "informal" <| AFTK.Informal.Service.status modules


unsafe def informalDecls : LeanWorker.Server.StatelessHandler Context InformalDeclsParam InformalDeclsResult := fun param => do
  let some declsParam := param
    | throw <| invalidParamsError "params object required"
  let modules ← parseModuleNamesHub declsParam.modules
  let prefixRawOpt := declsParam.prefix?
  let declPrefixOpt ←
    match prefixRawOpt with
    | .some prefText => do
        let parsed ← parseDeclNameHub prefText
        pure (some parsed)
    | .none =>
        pure none
  let refOpt := declsParam.ref?
  let ctx ← read
  fromIOResult <| runDomainIO ctx "informal" do
    let opts : AFTK.Informal.Service.DeclsOptions := {
      prefix? := declPrefixOpt
      ref? := refOpt
    }
    let entriesResult ← AFTK.Informal.Service.decls modules opts
    pure <| mapExcept (fun values => { entries := values.map informalDeclDtoOf }) entriesResult


unsafe def informalDecl : LeanWorker.Server.StatelessHandler Context InformalDeclParam InformalDeclResult := fun param => do
  let some ⟨modulesRaw, declNameRaw⟩ := param
    | throw <| invalidParamsError "params object required"
  let modules ← parseModuleNamesHub modulesRaw
  let declName ← parseDeclNameHub declNameRaw
  let ctx ← read
  fromIOResult <| runDomainIO ctx "informal" do
    let entryResult ← AFTK.Informal.Service.decl modules declName
    pure <| mapExcept (fun entry => { entry := informalDeclDtoOf entry }) entryResult


unsafe def informalRefs : LeanWorker.Server.StatelessHandler Context InformalRefsParam InformalRefsResult := fun param => do
  let some refsParam := param
    | throw <| invalidParamsError "params object required"
  let modules ← parseModuleNamesHub refsParam.modules
  let prefixOpt := refsParam.prefix?
  let ctx ← read
  fromIOResult <| runDomainIO ctx "informal" do
    let opts : AFTK.Informal.Service.RefsOptions := {
      prefix? := prefixOpt
    }
    let entriesResult ← AFTK.Informal.Service.refs modules opts
    pure <| mapExcept (fun entries => { entries := entries.map informalRefDtoOf }) entriesResult


unsafe def informalRef : LeanWorker.Server.StatelessHandler Context InformalRefParam InformalRefResult := fun param => do
  let some ⟨modulesRaw, ref⟩ := param
    | throw <| invalidParamsError "params object required"
  let modules ← parseModuleNamesHub modulesRaw
  let ctx ← read
  fromIOResult <| runDomainIO ctx "informal" do
    let entryResult ← AFTK.Informal.Service.ref modules ref
    pure <| mapExcept (fun entry => { entry := informalRefDtoOf entry }) entryResult


unsafe def informalDeclDeps : LeanWorker.Server.StatelessHandler Context InformalDepsParam InformalDeclDepsResult := fun param => do
  let some depsParam := param
    | throw <| invalidParamsError "params object required"
  let modules ← parseModuleNamesHub depsParam.modules
  let onlyLeaves := depsParam.onlyLeaves?.getD false
  let ctx ← read
  fromIOResult <| runDomainIO ctx "informal" do
    let resultE ← AFTK.Informal.Service.declDependencies modules onlyLeaves
    pure <| mapExcept (fun result => {
      rows := result.rows.map informalDeclDependencyDtoOf
      leaves := result.leaves.map nameString
    }) resultE


unsafe def informalRefDeps : LeanWorker.Server.StatelessHandler Context InformalDepsParam InformalRefDepsResult := fun param => do
  let some depsParam := param
    | throw <| invalidParamsError "params object required"
  let modules ← parseModuleNamesHub depsParam.modules
  let onlyLeaves := depsParam.onlyLeaves?.getD false
  let ctx ← read
  fromIOResult <| runDomainIO ctx "informal" do
    let resultE ← AFTK.Informal.Service.refDependencies modules onlyLeaves
    pure <| mapExcept (fun result => {
      rows := result.rows.map informalRefDependencyDtoOf
      leaves := result.leaves
    }) resultE


def informalPresent : LeanWorker.Server.StatelessHandler Context InformalPresentParam InformalPresentResult := fun param => do
  let some presentParam := param
    | throw <| invalidParamsError "params object required"
  let ctx ← read
  fromIOResult <| runDomainEIO ctx "informal"
    (AFTK.Informal.Service.present presentParam.ref
      (presentParam.mode?.getD .rich)
      (presentParam.bodyMode?.getD .preview)
      (rootPathOf? presentParam.root?))


def shutdownHub : LeanWorker.Server.StatelessHandler Context ShutdownParam ShutdownResult := fun _ => do
  let ctx ← read
  fromIOResult <| shutdownIO ctx


unsafe def server (transport : JsonTransport) : LeanWorker.Server.Server Context Unit where
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
    |>.addStateless "knowledgebase_init" knowledgeBaseInit
    |>.addStateless "knowledgebase_status" knowledgeBaseStatus
    |>.addStateless "knowledgebase_list" knowledgeBaseList
    |>.addStateless "knowledgebase_show" knowledgeBaseShow
    |>.addStateless "knowledgebase_get_body" knowledgeBaseGetBody
    |>.addStateless "knowledgebase_get_metadata" knowledgeBaseGetMetadata
    |>.addStateless "knowledgebase_get_paths" knowledgeBaseGetPaths
    |>.addStateless "knowledgebase_create" knowledgeBaseCreate
    |>.addStateless "knowledgebase_rename" knowledgeBaseRename
    |>.addStateless "knowledgebase_delete" knowledgeBaseDelete
    |>.addStateless "knowledgebase_set_body" knowledgeBaseSetBody
    |>.addStateless "knowledgebase_replace_metadata" knowledgeBaseReplaceMetadata
    |>.addStateless "knowledgebase_validate_metadata" knowledgeBaseValidateMetadata
    |>.addStateless "knowledgebase_validate_storage" knowledgeBaseValidateStorage
    |>.addStateless "knowledgebase_validate_node" knowledgeBaseValidateNode
    |>.addStateless "knowledgebase_validate_all" knowledgeBaseValidateAll
    |>.addStateless "knowledgebase_search_text" knowledgeBaseSearchText
    |>.addStateless "knowledgebase_search_tag" knowledgeBaseSearchTag
    |>.addStateless "knowledgebase_relationships_outgoing" knowledgeBaseRelationshipsOutgoing
    |>.addStateless "knowledgebase_relationships_incoming" knowledgeBaseRelationshipsIncoming
    |>.addStateless "knowledgebase_relationships_related" knowledgeBaseRelationshipsRelated
    |>.addStateless "informal_status" informalStatus
    |>.addStateless "informal_decls" informalDecls
    |>.addStateless "informal_decl" informalDecl
    |>.addStateless "informal_refs" informalRefs
    |>.addStateless "informal_ref" informalRef
    |>.addStateless "informal_decl_deps" informalDeclDeps
    |>.addStateless "informal_ref_deps" informalRefDeps
    |>.addStateless "informal_present" informalPresent
    |>.addStateless "shutdown" shutdownHub
  notifications := .empty
  transport := transport

end AFTK.Server.Hub
