# Server Transport Design

## Status

Component plan and implementation-status document for the transport and process boundary of the server/file-worker layer.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/protocol.md`, `plans/server/hub.md`, `plans/server/worker.md`, `plans/server/lean-integration.md`, `plans/server/integration.md`, `plans/server/layout.md`, and `plans/server/testing.md`.

## Component implementation status

- Overall status: Implemented
- Implemented in code: Yes
- Last updated basis: the rewrite worktree now depends on `lean_worker`, has an `AFTK.Server.Transport` integration module, and ships standalone `aftk_server` / `aftk_file_worker` executables over newline-delimited JSON-RPC on stdio.

## Purpose

This document defines how bytes move between:

- external clients and the hub/server process,
- the hub/server process and per-file workers,
- and the process-management layer and the semantic logic above it.

The transport design should make the operational boundary clear without letting transport details leak into:

- Lean semantic query code,
- lower-layer integration code,
- or tactic-state management code.

## Design goals

The transport layer should:

- preserve the overall hub/server plus per-file worker process topology
- use a small, explicit, machine-facing protocol boundary
- remain simple enough for a first implementation in this rewrite worktree
- use `lean_worker` directly as the transport dependency for JSON-RPC client/server plumbing
- keep deeper hub and worker semantic logic from being cluttered by repeated transport boilerplate
- make graceful shutdown and forced termination behavior explicit
- keep request ordering deterministic within one worker session
- be testable both in-process and via real subprocesses
- leave room for future incremental editing or cancellation work without forcing a complete transport rewrite

## Scope and non-scope

### In scope

- process topology and parent/child relationships
- the on-wire framing between client↔hub and hub↔worker
- JSON-RPC envelope use in v1
- worker subprocess startup and shutdown boundaries
- how to use `lean_worker` directly and cleanly as a dependency
- request ordering, buffering, and shutdown rules at the transport level

### Out of scope

- the semantic meaning of individual methods
- file-identity rules and session freshness policy in detail
- the file-worker’s Lean query algorithms
- lower-layer hover/presentation enrichment policy in detail
- test-case contents in detail

Those belong primarily to the companion protocol, hub, worker, integration, and testing documents.

## Core transport decisions

The v1 transport design should make the following choices explicit.

### 1. Keep two JSON-RPC process boundaries

The rewrite should preserve two process boundaries:

1. **public boundary:** external client ↔ `aftk_server`
2. **internal boundary:** `aftk_server` ↔ `aftk_file_worker`

This matches both:

- the current main-worktree shape, and
- Lean core’s watchdog/worker architecture in spirit.

### 2. Use newline-delimited UTF-8 JSON-RPC 2.0 messages over stdio

The v1 wire format should be a restricted JSON-RPC 2.0 subset carried over stdio using:

- UTF-8 text,
- one complete JSON object per line,
- no pretty-printing on the wire,
- and no out-of-band framing beyond the trailing newline.

That means a typical request looks like:

```json
{"jsonrpc":"2.0","id":1,"method":"open","params":{"path":"Example.lean"}}
```

and a typical response looks like:

```json
{"jsonrpc":"2.0","id":1,"result":{"path":"/abs/Example.lean","opened":true}}
```

### 3. Use `lean_worker` directly as the transport dependency in v1

The rewrite should explicitly depend on `lean_worker` for the hub/server and file-worker transport plumbing.
That means `lean_worker` should be treated as part of the intended implementation of this layer, not as a dependency to avoid.

Reasons:

- the main worktree already demonstrates that `lean_worker` is a good fit for this exact hub/worker JSON-RPC process model
- it reduces implementation risk and avoids spending time rebuilding generic client/server transport machinery the project already knows how to use
- it matches the executable/process structure higher layers already expect
- and it lets the rewrite focus effort on protocol clarity, hub lifecycle, worker semantics, and lower-layer integration rather than on reinventing RPC infrastructure

This does **not** mean transport concerns should be scattered everywhere.
The rewrite should still keep most transport-specific helper code collected in `AFTK.Server.Transport`, but that module should be understood as an AFTK-specific integration layer **over `lean_worker`**, not as an attempt to replace or abstract away the dependency.

### 4. Support only single-request envelopes in v1

The v1 transport should intentionally support only **single JSON-RPC request/response objects**, not general JSON-RPC batch arrays.

Reasons:

- the existing TypeScript client only needs single requests
- the public hub protocol does not currently need public batch requests
- `run_tactic_steps` is semantically sequential anyway
- and dropping batch support keeps both parser and tests smaller

If batch arrays are added later, they should be added within the same `lean_worker`-based transport layer without changing the semantic handler APIs.

### 5. Add explicit `shutdown` handlers on both public and internal boundaries

The rewrite should not rely on transport-package-specific shutdown behavior.
Instead:

- the hub should expose a public `shutdown` request,
- the file worker should expose an internal `shutdown` request,
- and the hub should use that worker request during graceful teardown.

After a bounded grace period, the hub may escalate to process termination.

### 6. Serialize requests per worker session

The transport layer and hub should jointly ensure that requests targeting one worker session are processed in a deterministic order.

A good v1 rule is:

- requests for different files may proceed independently,
- but requests for the same open file should be serialized through one worker-session queue or mutex.

This avoids ordering races around transient tactic nodes and restart behavior.

## Topology

### External/public boundary

The public topology should be:

```text
client -> aftk_server
```

over stdio JSON-RPC.

The hub/server is the only long-running public process callers should need to manage directly.
Higher layers should not spawn file workers themselves.

### Internal hub↔worker boundary

The internal topology should be:

```text
aftk_server -> aftk_file_worker <path>
```

with the worker using:

- piped stdin,
- piped stdout,
- and inherited stderr by default.

Inherited stderr is useful in v1 because it keeps crashes and elaboration failures visible in logs without contaminating the JSON-RPC stdout channel.

## Framing and wire rules

The v1 wire rules should be deliberately simple.

### Required request fields

Every request must contain:

- `jsonrpc` with value `"2.0"`
- `id`
- `method`
- optional `params`

### Required response fields

Every response must contain:

- `jsonrpc` with value `"2.0"`
- matching `id`
- exactly one of:
  - `result`
  - `error`

### `params` shape

The server/file-worker layer should accept only **object-shaped params** in v1.
Positional-array params should be rejected as invalid params.

### Encoding and buffering rules

- messages are UTF-8
- each message occupies exactly one line on stdout
- request writers must append a final `\\n`
- readers may ignore empty lines
- malformed JSON lines should produce a JSON-RPC parse error when a response can still be emitted sensibly

### Object key order

The transport layer should emit deterministic JSON where practical, but callers must treat object key order as non-semantic.
The stable contract is the field set and meaning, not key order.

## Recommended `AFTK.Server.Transport` layer over `lean_worker`

A good initial local transport module is still small and pragmatic.
It does not need to model the full JSON-RPC ecosystem because `lean_worker` already provides the underlying client/server transport machinery.

### Suggested responsibilities for `AFTK.Server.Transport`

The transport module should centralize AFTK-specific integration with `lean_worker`, including things like:

- common helpers for constructing `lean_worker` stdio transports
- small request/response helper functions built on `lean_worker` client/server APIs
- shared JSON/object-param helper utilities used by the hub and worker
- request-id or client-call helper code where AFTK needs a stable local wrapper
- parse-error and invalid-request helper behavior where AFTK wants a consistent local convention
- bounded graceful shutdown helpers for child processes

### What it should not own

It should **not** own:

- file-session state
- file freshness checks
- Lean elaboration or query logic
- knowledge-base or informal resolution logic
- tactic-state graphs

Those belong above the transport layer.

## Process startup policy

### Hub process startup

The rewrite’s TypeScript tools and tests should continue to be able to start the hub with:

```text
lake exe aftk_server
```

from the project root.

The hub should not require any extra command-line configuration in v1 beyond the defaults already needed to run inside the repository worktree.

### Worker process startup

The hub should start workers with:

```text
lake exe aftk_file_worker <canonical-or-normalized-path>
```

where the path identity is already settled by the hub before the process is spawned.

The worker should remain file-scoped in v1:

- one worker process,
- one file snapshot,
- one transient node graph.

## Shutdown policy

### Graceful worker shutdown

When a session is being closed or the hub exits, the hub should:

1. send worker `shutdown`
2. wait a short bounded grace period
3. if the worker still runs, send `SIGTERM`
4. if still running after another short wait, send `SIGKILL`

This policy should live in the transport/process-management layer, not be open-coded repeatedly across hub handlers.

### Graceful hub shutdown

On public `shutdown`, the hub should:

1. stop accepting new work
2. drain and remove all sessions
3. gracefully stop workers
4. return a response reporting how many sessions were stopped
5. exit cleanly

### Abnormal termination

If a worker exits unexpectedly:

- the hub should mark the session dead,
- clean it up,
- and surface the appropriate protocol-level error on the affected request.

If the hub itself exits unexpectedly, clients should treat all pending requests as failed.

## Ordering and concurrency

The transport design should define two levels of ordering.

### Cross-file concurrency

Requests for different open files may execute independently.
That is one of the main reasons to keep per-file workers.

### Intra-file serialization

Requests for the same file should be serialized by the hub before reaching the worker.
This should include:

- semantic reads,
- `load_node`,
- `get_goals`,
- `run_tactic`,
- and hub-level `run_tactic_steps`.

The important goal is deterministic behavior for transient node ids and session invalidation.

## Error handling at the transport boundary

The transport layer should distinguish between:

- malformed JSON / invalid request envelopes,
- protocol-level request errors,
- subprocess I/O failures,
- and semantic method failures reported by handlers.

### Transport-owned failures

Examples:

- unreadable/malformed request line
- missing `jsonrpc` / `id` / `method`
- non-object `params`
- broken pipe to worker process
- EOF while waiting for response

These should map to standard JSON-RPC errors where appropriate, or to transport/client failures inside the hub when speaking to workers.

### Semantic failures

Examples:

- file not open
- file changed
- worker unavailable
- stale node id
- tactic failure

These belong to the protocol and handler layers and should pass through the transport unchanged except for ordinary JSON-RPC envelope wrapping.

## Why a direct `lean_worker` commitment is the right v1 choice

Using `lean_worker` directly is the right design choice for this rewrite stage.
It keeps the implementation aligned with:

- the main-worktree operational model,
- the expected JSON-RPC-over-stdio process topology,
- and the project’s immediate need to deliver hub lifecycle, worker semantics, and lower-layer integration rather than bespoke RPC infrastructure.

The important architectural distinction is therefore not:

- “depend on `lean_worker`” versus “avoid `lean_worker`”,

but rather:

- “use `lean_worker` in a controlled, centralized way” versus “scatter transport mechanics throughout hub and worker semantic code”.

This document chooses the first option.
`lean_worker` should be an explicit dependency, while `AFTK.Server.Transport` remains the place where most AFTK-specific transport glue lives.

## Future-compatible extension points

The transport layer should leave room for later additions such as:

- explicit request cancellation
- progress/diagnostic notifications
- optional batch arrays
- alternate transports for tests
- richer worker supervision metadata

The v1 implementation should not block those, but it also should not implement them speculatively.

## Additional implementation findings from the main worktree

Research in `../aftk/AFTK/Server.lean`, `../aftk/AFTK/FileWorker.lean`, `../aftk/lakefile.lean`, and `../aftk/lambda/src/aftk-tools.ts` adds the following concrete implementation notes.

- The existing Lean implementation already uses the exact `lean_worker` API family the rewrite can adopt: `LeanWorker.Transport.serverTransportFromStdio`, `LeanWorker.Transport.clientTransportFromStreams`, `LeanWorker.Client.getClient`, `LeanWorker.Server.run`, and `LeanWorker.Server.HandlerRegistry.addStateful`.
- The hub spawns workers with `IO.Process.spawn { cmd := "lake", args := #["exe", "aftk_file_worker", path], stdin := .piped, stdout := .piped, stderr := .inherit, setsid := true }`.
- Hub→worker RPC currently goes through `session.client.request`; the current `run_tactic_steps` implementation uses `session.client.batch` even though it submits a single `run_tactic` item per loop iteration.
- The current hub keeps cleanup centralized through `stopSession`, `stopAllSessions`, and a `drainSessions` helper used from `finally` in `main`.
- The TypeScript wrapper in `../aftk/lambda/src/aftk-tools.ts` writes exactly one `JSON.stringify(...) ++ "\\n"` request per call, line-buffers stdout by splitting on `"\n"`, ignores empty lines, and applies a `SIGTERM`/`SIGKILL` fallback with 1500 ms waits.

One important implementation gap in the current main worktree is also worth recording.

- The current worker does **not** expose an explicit internal `shutdown` handler; hub cleanup relies on `session.client.shutdown` plus process termination fallback.
- The rewrite should keep the same `lean_worker` transport path, but add the explicit worker `shutdown` method already settled elsewhere in these plans.

## Implementation guidance for the next code phase

The first code added for this document should likely be:

- the `lakefile.toml` dependency on `lean_worker`
- a small `AFTK.Server.Transport` layer that wraps the needed `lean_worker` transport/client/server helpers
- shared JSON/object-param helper utilities
- a subprocess RPC client helper for hub↔worker communication
- bounded graceful child-stop helpers

Only after that `lean_worker`-based transport skeleton exists should the hub and worker semantic handlers be wired in.

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the rewrite worktree:

- `lakefile.toml` declares the `lean_worker` dependency used by this layer
- an `AFTK.Server.Transport` integration module exists and is used by both hub and worker executables
- the public client↔hub and internal hub↔worker boundaries both use the settled wire format through `lean_worker`
- both hub and worker expose explicit `shutdown` handling at their respective boundaries
- per-session request serialization is implemented and tested
- abnormal worker exit and forced-kill fallback behavior are tested
- direct `lean_worker` usage is documented and kept reasonably centralized rather than scattered through unrelated semantic modules

## Summary

The rewrite should keep the existing two-process-level architecture, keep JSON-RPC over stdio, and intentionally use a small restricted transport surface in v1:

- UTF-8,
- one JSON object per line,
- object params only,
- no public batch arrays,
- explicit shutdown on both boundaries,
- and deterministic per-session request ordering.

The key architectural choice in this document is to use `lean_worker` directly as the transport dependency while keeping the AFTK-specific transport glue collected in `AFTK.Server.Transport` instead of scattering it throughout the hub and worker semantic code.
