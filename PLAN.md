# Plan: Implement `AFTK/Server.lean` as a hub over multiple `file_worker` subprocesses

## 1. What I found (research summary)

### LeanWorker framework essentials
- `LeanWorker.Server.run` hosts JSON-RPC handlers over a `Transport`.
- `HandlerRegistry.addStateful` runs handlers with a **single shared state mutex** for each handler invocation.
- `LeanWorker.Client.getClient` gives a client with:
  - `request : String → Option Json.Structured → EAsync JsonRpc.Error Json`
  - `notify`, `batch`, `shutdown`
- `LeanWorker.Transport.clientTransportFromStreams` is the intended way to connect to a spawned subprocess via piped stdio.
- `LeanWorkerTest/TestClient.lean` demonstrates the subprocess pattern:
  1. `IO.Process.spawn` with `stdin := .piped`, `stdout := .piped`
  2. wrap handles with `IO.FS.Stream.ofHandle`
  3. build transport via `clientTransportFromStreams`
  4. build client via `getClient`

### Existing `AFTK/FileWorker.lean`
The file worker currently serves methods:
- `load_node` with params `{ line, col }` → result `{ id : Array String }`
- `get_goals` with params `{ id }` → result `{ goals : List String }`
- `run_tactic` with params `{ id, tactic }` → result `{ goals : List String, nextId : String }`

`main` expects exactly one CLI argument: file path.

---

## 2. Target behavior for the hub server

The hub server in `AFTK/Server.lean` should:
1. expose `open` to spawn/manage a per-file worker;
2. route file-scoped requests to the corresponding worker;
3. support multiple open files at once;
4. stop a worker when its file changes;
5. cleanly terminate all workers on hub shutdown.

---

## 3. Proposed hub JSON-RPC API (v1)

### Required
- `open`
  - params: `{ path : String }`
  - result: `{ path : String, opened : Bool }`
    - `opened = true`: spawned new worker
    - `opened = false`: already open and reused

### Routing methods (typed wrappers around file-worker methods)
- `load_node`
  - params: `{ path : String, line : Nat, col : Nat }`
  - forwarded to worker method `load_node` with `{ line, col }`
- `get_goals`
  - params: `{ path : String, id : String }`
  - forwarded to worker method `get_goals` with `{ id }`
- `run_tactic`
  - params: `{ path : String, id : String, tactic : String }`
  - forwarded to worker method `run_tactic` with `{ id, tactic }`

### Strongly recommended (for lifecycle hygiene)
- `close`
  - params: `{ path : String }`
  - result: `{ closed : Bool }`

(You can implement `close` now or as immediate follow-up; it simplifies cleanup and testing.)

---

## 4. Internal architecture

## 4.1 Core data structures
- `FileStamp` (for change detection)
  - `modified : IO.FS.SystemTime`
  - `byteSize : UInt64`
- `WorkerSession`
  - canonical path
  - current `FileStamp`
  - spawned process handle (`IO.Process.Child ...`)
  - `LeanWorker.Client.Client`
  - optional per-session mutex for stop/request race protection
- `HubState`
  - `sessions : Std.TreeMap String WorkerSession` keyed by canonical path

## 4.2 Context/config
- worker launch command config (initially simplest path):
  - dev mode: spawn `lake exe file_worker -- <path>`
  - later optimization: spawn `.lake/build/bin/file_worker` directly
- optional logger from `Transport.stderrLogger` for debugging.

---

## 5. Lifecycle helpers to implement

1. `canonicalizePath : String → EIO JsonRpc.Error String`
   - convert to `System.FilePath`, normalize via `IO.FS.realPath`.

2. `readStamp : System.FilePath → EIO JsonRpc.Error FileStamp`
   - use `path.metadata`; capture `modified` + `byteSize`.

3. `spawnSession : canonicalPath → EIO JsonRpc.Error WorkerSession`
   - spawn child with piped stdin/stdout
   - build streams (`IO.FS.Stream.ofHandle`)
   - `clientTransportFromStreams` + `Client.getClient`
   - store initial stamp

4. `stopSession : WorkerSession → BaseIO Unit`
   - best-effort shutdown sequence:
     - `client.shutdown` (catch/log)
     - `child.kill` (catch/log)
     - `child.wait` (catch/log)
   - never throw during cleanup path.

5. `ensureUnchangedOrStop : WorkerSession → EIO JsonRpc.Error WorkerSession`
   - recompute stamp
   - if changed: stop session + signal error (e.g. `content modified; reopen`)
   - if unchanged: return session.

6. `forwardToWorker`
   - arguments: `(path, method, params?)`
   - lookup session
   - verify unchanged
   - `EAsync.block <| client.request method params?`
   - on transport/crash error: remove session from map and rethrow.

---

## 6. Handler behavior details

### `open`
1. canonicalize input path.
2. if existing session:
   - if file unchanged and process alive -> reuse (`opened := false`).
   - if changed or dead -> stop old, remove, then respawn.
3. if missing -> spawn and insert.
4. return canonical path.

### `load_node` / `get_goals` / `run_tactic`
1. canonicalize path.
2. call `forwardToWorker` with file-worker method + stripped params.
3. decode forwarded JSON to expected result type (or return JSON directly if you prefer pass-through).

### `close` (if included)
1. canonicalize path.
2. if present: remove from map, stop subprocess, return `closed := true`.
3. else `closed := false`.

---

## 7. Concurrency strategy

Important LeanWorker fact: stateful handlers run under one global mutex.

Recommended approach for this hub:
- Keep hub handlers **stateful** for simplicity first.
- Accept serialized handling for v1 correctness.
- If this becomes a bottleneck, switch to stateless handlers + explicit mutexes (global map mutex + per-session mutex).

Even with serialized hub handlers, multiple workers are still correctly managed; requests are just not maximally parallel.

---

## 8. Error model

Use explicit JSON-RPC errors (similar to `AFTK/FileWorker.lean` helpers):
- `invalidParams` for malformed path/fields
- custom “file not open” error (server error code range, e.g. `-32010`)
- custom “file changed; reopened required” error (e.g. `-32011`)
- propagate worker-side errors from forwarded `client.request`

---

## 9. Implementation checklist

1. Create `AFTK/Server.lean`.
2. Define hub param/result structures + `FromStructured`/`ToJson`.
3. Define session/state/context types.
4. Implement helper functions (`canonicalizePath`, `readStamp`, `spawnSession`, `stopSession`, `forwardToWorker`).
5. Implement handlers (`open`, `load_node`, `get_goals`, `run_tactic`, optional `close`).
6. Register handlers in `server` value.
7. Add `main` for hub server (`serverTransportFromStdio`, `Server.run`).
8. Update `AFTK.lean` exports.
9. Add lake executable target for hub in `lakefile.toml`.
10. Manual integration test pass.

---

## 10. Manual test plan

1. Start hub server.
2. `open` two different files; ensure both succeed.
3. For each file, call `load_node` then `get_goals`/`run_tactic`; confirm routed correctly.
4. Modify one opened file on disk.
5. Next request for that file should fail with “file changed” and subprocess should be stopped.
6. Requests for other file should still work.
7. Re-`open` changed file; routing works again.
8. Shutdown hub; verify no orphan file_worker processes remain.

---

This plan intentionally keeps v1 straightforward and robust, while leaving a clean path to add stronger parallelism and richer routing later.