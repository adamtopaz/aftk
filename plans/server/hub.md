# Hub Lifecycle and Session Design

## Status

Component plan and implementation-status document for the hub/server responsibilities of the server/file-worker layer.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/transport.md`, `plans/server/protocol.md`, `plans/server/worker.md`, `plans/server/lean-integration.md`, `plans/server/integration.md`, `plans/server/layout.md`, and `plans/server/testing.md`.

## Component implementation status

- Overall status: Planned
- Implemented in code: No
- Last updated basis: the rewrite worktree still has no hub/session implementation, but the server-layer architecture and component decisions are now documented.

## Purpose

This document defines the operational behavior of the hub/server process.
The hub is responsible for:

- owning open-file sessions
- resolving file identity
- spawning and stopping workers
- deciding when sessions are fresh or stale
- forwarding requests to the correct worker
- and surfacing operational failures to callers in a stable way

The hub should remain operationally central but semantically thin.

## Design goals

The hub design should:

- preserve the useful main-worktree model of one worker per open file
- keep file identity explicit and deterministic
- make session invalidation and cleanup rules easy to reason about
- isolate operational lifecycle from Lean semantic query code
- make worker failures visible as protocol-level events rather than silent corruption
- support independent concurrency across different files while remaining deterministic within one file session
- keep the first implementation small enough to land without importing the full complexity of Lean’s own language server

## Scope and non-scope

### In scope

- open-file session records
- path resolution and lookup policy
- file freshness checks
- worker spawn, stop, and restart policy
- per-session request serialization
- request forwarding and cleanup rules
- public lifecycle methods `open`, `close`, and `shutdown`

### Out of scope

- the detailed worker query algorithms
- the wire framing implementation itself
- the worker’s lower-layer hover enrichment logic
- incremental editable-document support beyond recording future extension points

## Core hub decisions

The v1 hub should make the following decisions explicit.

### 1. One worker process per open file

Each open Lean file should correspond to at most one live worker session.
Different files should use different worker processes.

### 2. The hub owns file identity

The worker should be file-local but not file-identity-authoritative.
The hub is the layer that decides:

- which raw paths refer to the same file session
- whether a request belongs to an existing session
- and when a session has become stale

### 3. The hub remains semantically thin

The hub should not reimplement Lean semantic logic.
Its main job is:

- routing,
- lifecycle,
- freshness checking,
- and public API stability.

### 4. v1 uses explicit reopen-on-change semantics

The v1 hub should preserve the main-worktree operational rule:

- if the underlying file changes, the current session becomes invalid
- subsequent file-scoped requests fail with `-32011`
- the caller must `open` the file again to get a fresh worker

The rewrite should keep its internal boundaries clean enough that a later versioned document model can replace this.
But reopen-on-change is the settled v1 rule.

### 5. Serialize all requests within one session

Each worker session should own a request queue or mutex.
Requests for the same file must be serialized before being forwarded.
This includes reads and tactic-state operations.

That avoids race conditions around:

- worker restart,
- stale node ids,
- and multi-step tactic execution.

## Session data model

A practical v1 hub state should revolve around the following concepts.

## File identity

A file identity should record at least:

- a normalized absolute input path
- a canonical real path when available at open time

The hub should prefer canonical real paths for stable identity, but it should also remember a normalized absolute alias so that requests can still map back to the same session even if later path resolution becomes weaker because the file was removed or renamed.

A practical conceptual model is:

```lean
structure FileIdentity where
  normalizedPath : FilePath
  canonicalPath  : FilePath
```

with lookup support for both keys.

The response `path` returned by public methods should be the canonical identity string.

## File stamp

The hub should record a file stamp when a session is opened.
For v1, a practical stamp is:

- modification time,
- plus byte size.

This preserves the main-worktree behavior and is easy to compute.

## Worker session

A worker session should record at least:

- file identity
- file stamp
- child-process handle
- worker RPC client/channel
- per-session serialization primitive

A conceptual model is:

```lean
structure WorkerSession where
  identity : FileIdentity
  stamp    : FileStamp
  child    : WorkerChild
  client   : WorkerClient
  lock     : SessionLock
```

## Hub state

The hub state should contain a session registry keyed by canonical identity, together with any secondary alias index needed for robust lookup.

A practical v1 design is:

- primary map: canonical path -> session
- secondary alias map: normalized absolute path -> canonical path

## Path resolution policy

The hub should define a two-step path policy.

### Step 1: normalize the raw request path

The hub should:

- resolve relative paths against the hub’s current working directory
- turn them into absolute normalized filesystem paths

### Step 2: resolve canonical identity when possible

When opening a file, the hub should also attempt to compute its real filesystem path.
If that succeeds, the real path becomes the canonical identity.

### Why keep both normalized and canonical forms?

Because later requests may happen after the file:

- changes,
- disappears,
- or becomes harder to canonicalize.

Remembering the normalized alias makes stale-session lookup more robust than relying only on successful `realPath` calls after the fact.

## Public lifecycle methods

## `open`

`open` should behave as follows.

### If no session exists

- resolve the file identity
- validate that the target is a readable regular file
- compute the file stamp
- spawn the worker
- register the session
- return `opened = true`

### If a fresh live session already exists

- reuse it
- return `opened = false`

### If an existing session is dead or stale

- remove it from the registry
- stop/clean up any remaining process resources
- spawn a fresh worker
- replace the session
- return `opened = true`

This preserves the main-worktree meaning of `open` as both initial open and repair/reopen entrypoint.

## `close`

`close` should:

- resolve the request path through the same identity policy
- if no session exists, return `closed = false`
- if a session exists, remove it, stop the worker, and return `closed = true`

`close` should be idempotent from the caller’s perspective.

## `shutdown`

`shutdown` should:

- atomically detach all sessions from hub state
- stop them all gracefully with forced-kill fallback
- return how many sessions were stopped
- and allow the process to exit cleanly

## Request forwarding policy

For all file-scoped semantic requests, the hub should follow this sequence.

1. resolve request path to the matching session
2. acquire the session’s serialization primitive
3. verify the worker is still alive
4. verify the file stamp still matches the open-session stamp
5. forward the request to the worker
6. if forwarding reveals a dead worker, clean up the session
7. return or translate the result/error

The important point is that the liveness and freshness checks happen **before** forwarding.

## File freshness policy

The v1 hub should preserve explicit freshness checks on every file-scoped request.

### Freshness rule

A session is fresh if and only if the current file stamp matches the session’s open-time file stamp.

### If the file changed

The hub should:

- remove the session from the registry
- stop the worker
- return `-32011` file changed; reopen required

### Why invalidate eagerly instead of letting the worker continue?

Because the v1 worker is a one-shot snapshot built from the file contents at startup.
Once the file on disk changes, the worker’s semantic state no longer matches the file that higher layers think they are querying.

## Worker liveness policy

The hub should detect worker failure in two places.

### Before forwarding

If the child process has already exited, the hub should:

- remove the session
- clean up process resources
- return `-32012` worker unavailable

### After forwarding errors

If an RPC or pipe error occurs while forwarding, the hub should re-check worker liveness.
If the worker died, the hub should remove the session and surface `-32012`.
If the worker is still alive and returned a semantic error, that semantic error should pass through unchanged.

## Multi-step tactic execution

`run_tactic_steps` should remain a hub-level convenience method in v1.

### Semantics

The hub should:

- acquire the same session serialization lock used for other requests
- execute each tactic step in order against the worker
- feed each returned `nextId` into the next step
- stop and fail the overall request on the first error

### Why keep this at the hub?

Because:

- it preserves the current public surface
- it avoids making the worker implement an additional orchestration primitive
- and it lets the hub present one stable convenience method to higher layers

## Cleanup policy

The hub should centralize cleanup in a small number of helpers rather than scattering process-stop logic across handlers.

A good v1 split is:

- spawn helper
- graceful stop helper
- remove-and-stop helper
- stop-all-sessions helper

The hub executable should also run a final cleanup path on abnormal server exit so that child workers do not remain orphaned.

## What the hub should not do

The hub should not:

- parse or elaborate Lean files itself
- store proof-state nodes directly
- read knowledge-base files directly as a parallel storage system
- invent separate hover/goal heuristics
- depend on file-worker internals more than necessary to forward protocol requests

That discipline keeps the layer maintainable.

## Future evolution boundary

The main future architectural change this design should allow is a move from:

- file-stamp-based reopen-on-change semantics

to:

- versioned editable documents and richer snapshot handling.

To preserve that option, the hub should keep:

- path/session management,
- worker supervision,
- and protocol routing

cleanly separated from the worker’s document model.

## Additional implementation findings from the main worktree

Research in `../aftk/AFTK/Server.lean` shows the concrete helper split that is likely worth preserving in spirit.

- The current hub state is intentionally small:
  - `WorkerSession` stores `path`, `stamp`, `child`, and `client`
  - `State` stores `sessions : Std.TreeMap String WorkerSession`
- Path handling currently goes through:
  - `normalizePathIO`
  - `canonicalizePath`
  - `readFileStampIO`
- `canonicalizePath` first tries `IO.FS.realPath`; on failure it falls back to normalized absolute-path resolution rather than failing immediately.
- `readFileStampIO` uses exactly `metadata.modified` plus `metadata.byteSize`, and rejects non-files with `not a regular file: {path}`.
- `sessionFileChanged` treats any failure to restamp the file as `true`.
- `sessionIsDead` treats any `tryWait` error as dead.
- `open` reuses an existing session only when it is both alive and unchanged; otherwise it erases the old entry, stops the session, and respawns.
- `ensureSessionReady` checks liveness before freshness, and `forwardToWorker` performs dead-session cleanup after request failures if the child exited while the RPC was in flight.
- `main` uses a `finally` block plus `drainSessions` to detach all sessions from the mutex before stopping them, which avoids cleanup racing with normal state access.

The rewrite should preserve these conservative operational rules, while still keeping the deliberate improvements already documented here:

- add alias lookup rather than relying only on one canonical path string
- add explicit per-session serialization
- and add an explicit worker `shutdown` request instead of relying only on transport-package shutdown behavior.

## Implementation guidance for the next code phase

The first hub code should likely implement:

- file identity and stamp types
- session registry state
- `open`, `close`, and `shutdown`
- worker spawn/stop helpers
- per-session request serialization
- generic request forwarding helpers

Only after that should the full semantic method family be wired through.

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the rewrite worktree:

- the hub manages one worker session per open file
- file identity resolution is explicit and tested
- file freshness checks invalidate stale sessions deterministically
- dead workers are detected and cleaned up deterministically
- `open`, `close`, and `shutdown` implement the documented lifecycle behavior
- `run_tactic_steps` is implemented as a hub-level sequential orchestration method
- per-session request serialization exists and is tested

## Summary

The hub in the rewrite should stay small and operationally authoritative:

- one worker per open file,
- explicit file identity and freshness tracking,
- deterministic cleanup and restart behavior,
- serialized request routing per session,
- and a settled v1 reopen-on-change policy.

The hub is the layer that makes the rest of the system safe to depend on as a long-running service, even though the semantic intelligence remains in the worker.
