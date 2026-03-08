# Toolkit Server Client Design

## Status

Component plan and implementation-status document for the TypeScript client for the rewrite server protocol.
This document refines the overall toolkit-layer plan in `plans/toolkit.md` and works together with `plans/toolkit/layout.md`, `plans/toolkit/runtime.md`, `plans/toolkit/lean-tools.md`, `plans/toolkit/knowledgebase-tools.md`, `plans/toolkit/informal-tools.md`, `plans/toolkit/pi-integration.md`, `plans/toolkit/output.md`, and `plans/toolkit/testing.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: research against the main-worktree managed hub client in `/home/dev/aftk/lambda/src/aftk-tools.ts`, plus the rewrite server protocol and lifecycle docs in `docs/server/protocol.md`, `docs/server/overview.md`, `plans/server/protocol.md`, `plans/server/hub.md`, `AFTK/Server/Protocol.lean`, and `AFTK/Server/Main.lean`

## Purpose

This document defines the TypeScript client layer that talks to the rewrite’s public server process:

```text
lake exe aftk_server
```

It is about:

- the TypeScript mirror of the public server protocol
- the shape of the reusable managed hub client
- request/response typing
- JSON-RPC envelope handling
- request correlation and pending-request bookkeeping
- protocol and operational error mapping
- lifecycle behavior at the client layer
- and compatibility expectations with the rewrite server protocol

The goal is to make the Lean-facing server boundary usable from TypeScript as a first-class library surface, rather than forcing every later tool family or host adapter to hand-roll its own JSON-RPC plumbing.

## Design goals

The server client should:

- preserve strong compatibility with the current main-worktree Lean-facing method family
- mirror the rewrite’s documented public hub protocol faithfully
- expose a reusable client surface below any `pi`-specific tool registration
- remain focused on the **public hub protocol**, not the internal worker protocol
- support concurrent outstanding requests with reliable request/response correlation
- keep lifecycle behavior explicit: start, running state, shutdown, and forced stop
- preserve typed error information instead of flattening all failures into plain strings
- treat protocol corruption or malformed stdout as a serious client/runtime failure
- fit cleanly on top of the shared runtime/process layer from `plans/toolkit/runtime.md`
- stay semantically thin: no tool formatting, no path shims for `pi`, no agent-specific abstractions

## Scope and non-scope

### In scope

- TypeScript request/response types for the public `aftk_server` protocol
- JSON-RPC envelope handling over newline-delimited stdio
- managed hub lifecycle from the client side
- request-id allocation and pending-request tracking
- typed convenience methods for the public server method family
- client-side error classification for protocol vs server vs process/runtime failures
- compatibility commitments to the documented rewrite server behavior

### Out of scope

- the internal hub↔worker protocol as a public TypeScript surface
- tool parameter schemas and agent-facing descriptions
- host-specific `pi` registration logic
- formatting hover/goal/tactic results for human consumption
- knowledge-base and informal CLI integration
- the server’s internal Lean algorithms, worker lifecycle internals, or session logic beyond what is externally observable

Those are covered by the server-layer docs or other toolkit component docs.

## Research basis and design consequences

This client plan is based on explicit research in both worktrees.

### Main-worktree reference points

Primary file studied:

- `/home/dev/aftk/lambda/src/aftk-tools.ts`

Important client-side observations from that implementation:

- The current main-worktree toolkit already contains a working managed hub client shape in `AftkHubClient`.
- It starts `lake exe aftk_server` lazily and talks newline-delimited JSON-RPC over stdio.
- It tracks pending requests by id in a map.
- It uses monotonic numeric ids.
- It rejects pending requests when the child exits.
- It exposes a generic `request<T>(method, params, options?)` helper.
- It wraps server JSON-RPC errors in a dedicated `HubRpcError` carrying:
  - `method`
  - `code`
  - `message`
  - `data`
- It distinguishes graceful `shutdown` RPC from forced child termination.
- It currently performs very little runtime validation of response payload shapes beyond JSON parsing and envelope inspection.
- It currently ignores malformed non-empty stdout lines rather than treating them as protocol failure.
- It currently mirrors hub stderr directly to the parent stderr stream.

Main consequences for the rewrite:

- the rewrite should preserve the overall managed-client pattern,
- but improve it by:
  - moving it into a dedicated `server/` module area,
  - aligning it explicitly with the rewrite protocol docs,
  - tightening protocol-failure handling,
  - and building a clearer typed protocol surface below tool definitions.

### Rewrite-worktree reference points

Files studied:

- `docs/server/protocol.md`
- `docs/server/overview.md`
- `plans/server/protocol.md`
- `plans/server/hub.md`
- `AFTK/Server/Protocol.lean`
- `AFTK/Server/Main.lean`
- `plans/toolkit/runtime.md`

Important rewrite observations:

- The rewrite preserves the main Lean-facing public method family:
  - `open`
  - `close`
  - `load_node`
  - `get_hover`
  - `get_plain_goal`
  - `get_plain_term_goal`
  - `get_infoview`
  - `get_goals`
  - `run_tactic`
  - `run_tactic_steps`
  - `shutdown`
- The server is the public operational boundary; the worker protocol remains internal.
- The rewrite protocol explicitly defines public result shapes, including:
  - `OpenResult`
  - `CloseResult`
  - `LoadNodeResult`
  - `HoverResult`
  - `PlainGoalResult`
  - `PlainTermGoalResult`
  - `InfoViewResult`
  - `GetGoalsResult`
  - `RunTacticResult`
  - `RunTacticStepsResult`
  - `ShutdownResult`
- The rewrite protocol explicitly defines stable AFTK-specific error codes:
  - `-32001` tactic failed
  - `-32010` file not open
  - `-32011` file changed; reopen required
  - `-32012` worker unavailable
  - `-32013` stale or unknown node id
- `AFTK/Server/Protocol.lean` also makes the current error-data payloads concrete:
  - tactic failure carries the rendered tactic-failure message as a string,
  - file-open/file-changed/worker-unavailable errors carry the path string,
  - stale-node errors carry the failing node id string.
- `AFTK/Server/Main.lean` currently accepts no CLI flags, always serves over stdio, and drains sessions on exit.
- The server docs explicitly say:
  - transport is JSON-RPC 2.0
  - messages are newline-delimited UTF-8 JSON objects over stdio
  - params are object-shaped
  - and line/column positions are 1-based
- The hub owns session lifecycle and file freshness checks; the client should not try to reconstruct or second-guess those semantics.
- `run_tactic_steps` is a public hub convenience method and should remain first-class in the client surface.

Main consequences for the rewrite:

- the client should mirror the **public hub contract** directly and should not bypass it;
- the typed protocol definitions should be built from the documented public JSON shape, using `AFTK/Server/Protocol.lean` only as an implementation cross-check;
- and the client error model must preserve the rewrite’s named operational error codes because those are part of the higher-layer contract.

## Core client decisions

The v1 server-client design should make the following choices explicit.

### 1. Speak only the public hub protocol

The TypeScript server client should only target:

```text
lake exe aftk_server
```

and the public method family documented in `docs/server/protocol.md`.

It should **not** expose the internal worker protocol as part of the toolkit’s public TypeScript API.
That means:

- no direct `aftk_file_worker` spawning from the toolkit client layer
- no worker-local method wrappers in the public client
- no TypeScript-side assumptions about internal worker request routing

This preserves the public boundary already defined by the rewrite server layer.

### 2. Mirror the documented JSON protocol in TypeScript

The client should define TypeScript protocol types that mirror the public server contract directly.
That includes:

- public request parameter types
- public response result types
- shared value types such as `SourcePosition` and `SourceRange`
- the known server error-code set

The primary source of truth for the TypeScript-facing shape should be:

- `docs/server/protocol.md`

with:

- `AFTK/Server/Protocol.lean`
- and `plans/server/protocol.md`

used as implementation cross-checks.

This matters because Lean internal field naming details such as `range?`, `hover?`, `plainGoal?`, and `plainTermGoal?` should not accidentally become the TypeScript compatibility story when the documented external JSON shape is already clearer.

### 3. Preserve the public method family exactly where practical

The client should preserve the public hub method names exactly:

- `open`
- `close`
- `load_node`
- `get_hover`
- `get_plain_goal`
- `get_plain_term_goal`
- `get_infoview`
- `get_goals`
- `run_tactic`
- `run_tactic_steps`
- `shutdown`

This is important for:

- parity with the rewrite server docs
- compatibility with the current main-worktree tool family
- and keeping the Lean-facing toolkit surface easy to map back to the server protocol

### 4. Expose both a generic typed request API and named convenience methods

The client should support two levels of use.

#### Generic request path

The foundational API should look conceptually like:

```ts
request<M extends AftkServerMethod>(method: M, params: ParamsFor<M>, options?): Promise<ResultFor<M>>
```

This is useful for:

- tests
- future advanced integrations
- keeping one direct expression of the protocol map

#### Named convenience methods

The client should also expose ergonomic named methods such as:

- `open(params)`
- `close(params)`
- `loadNode(params)`
- `getHover(params)`
- `getPlainGoal(params)`
- `getPlainTermGoal(params)`
- `getInfoView(params)`
- `getGoals(params)`
- `runTactic(params)`
- `runTacticSteps(params)`
- `shutdown()`

This gives later toolkit code a pleasant API without duplicating method names and result types everywhere.

### 5. Let the client own request correlation, not semantic serialization

The client should support multiple outstanding JSON-RPC requests by maintaining:

- a monotonic request-id counter
- a map from id to pending-request bookkeeping

However, it should **not** add a second semantic serialization layer on top of the hub’s own session semantics.

So the client should:

- allow concurrent outstanding requests in principle
- correlate replies by id reliably
- leave per-file request ordering to the hub, which already serializes requests within a session

This keeps the client focused on transport/protocol responsibilities.

### 6. Use numeric request ids and keep them opaque to consumers

The client should continue using monotonically increasing numeric JSON-RPC request ids.
This matches the main-worktree implementation and keeps the request bookkeeping simple.

Consumers should not be exposed to request ids as part of the public API.
They are a client-internal correlation mechanism.

### 7. Validate JSON-RPC envelopes strongly

The client should strongly validate the JSON-RPC response envelope before treating a response as successful.
At minimum, for each response line it should require:

- a parseable JSON object
- `jsonrpc: "2.0"`
- an `id`
- exactly one of:
  - `result`
  - `error`

If a response with a known pending id violates that structure, the corresponding request should reject with a protocol error.

### 8. Treat malformed non-empty stdout as protocol failure, not ignorable noise

The main-worktree implementation currently ignores malformed non-empty stdout lines.
The rewrite should be stricter.

Because server stdout is the protocol channel, a non-empty malformed line should be treated as a protocol-level failure.
A good v1 rule is:

- ignore empty lines
- buffer partial lines until newline
- if a completed non-empty line is not valid protocol JSON, treat the managed connection as corrupted
- reject all pending requests and stop using that child process

This is stricter than the current main-worktree behavior, but it matches the documented server transport contract and makes failures easier to detect.

### 9. Tolerate late responses for already-abandoned requests

If a request timed out locally or was locally canceled and removed from the pending map, a later response for that id may still arrive.
The client should tolerate that by ignoring responses whose ids no longer match a pending request.

This is not a protocol success path; it is a practical consequence of local timeout/cancel behavior and the lack of server-side cancellation.

### 10. Distinguish protocol shutdown from process cleanup

The server protocol includes a public `shutdown` method.
But the client also has library-level responsibility for process ownership and cleanup.

So the client surface should distinguish between:

- `shutdown()` — a semantic protocol call to the hub that returns `ShutdownResult`
- `stop(graceful?)` — lifecycle cleanup for the owned child process

This mirrors the architectural split already visible in the main-worktree toolset.
Higher layers can then choose whether they want:

- a real semantic server shutdown operation,
- or just best-effort cleanup of an owned child at host/session shutdown time.

### 11. Preserve known server error codes as typed client errors

The client should preserve the rewrite’s known public server error codes as first-class client-visible information.
At minimum, it should recognize:

- `-32001` tactic failed
- `-32010` file not open
- `-32011` file changed; reopen required
- `-32012` worker unavailable
- `-32013` stale or unknown node id

The client should not force higher layers to scrape error message strings to recover this information.

### 12. Keep cancellation honest

The client should accept `AbortSignal` in request methods, but it should be explicit that:

- local waiting can be canceled
- local pending-request bookkeeping can be removed
- the server request itself is not necessarily canceled remotely

This matches the settled runtime policy from `plans/toolkit/runtime.md`.

### 13. Preserve method-level result quirks where they are part of compatibility

The client should preserve certain awkward but established protocol details because they are part of the public compatibility contract.

Most notably:

- `LoadNodeResult` should still use field name `id`, even though the value is an array of node ids
- position/result fields should stay compatible with the public docs
- `get_hover`, `get_plain_goal`, and `get_plain_term_goal` should preserve their optional/null result behavior

The client should not “clean these up” by changing protocol-facing types.
If higher layers want nicer abstractions, they can wrap the client.

## Protocol type surface

A practical TypeScript protocol module should expose types like the following.
The exact names can still evolve, but the underlying contract should not.

### Shared public value types

- `SourcePosition`
- `SourceRange`
- `HoverResult`
- `PlainGoalResult`
- `PlainTermGoalResult`
- `InfoViewResult`

### Public request parameter types

- `OpenParams`
- `CloseParams`
- `FileLocationParams`
- `FileNodeParams`
- `RunTacticParams`
- `RunTacticStepsParams`
- `ShutdownParams`

### Public result types

- `OpenResult`
- `CloseResult`
- `LoadNodeResult`
- `GetGoalsResult`
- `RunTacticResult`
- `RunTacticStepsResult`
- `ShutdownResult`

### Method map type

The protocol module should define one explicit method map, conceptually like:

```ts
interface AftkServerProtocolMap {
  open: { params: OpenParams; result: OpenResult };
  close: { params: CloseParams; result: CloseResult };
  load_node: { params: FileLocationParams; result: LoadNodeResult };
  get_hover: { params: FileLocationParams; result: HoverResult | null };
  get_plain_goal: { params: FileLocationParams; result: PlainGoalResult | null };
  get_plain_term_goal: { params: FileLocationParams; result: PlainTermGoalResult | null };
  get_infoview: { params: FileLocationParams; result: InfoViewResult };
  get_goals: { params: FileNodeParams; result: GetGoalsResult };
  run_tactic: { params: RunTacticParams; result: RunTacticResult };
  run_tactic_steps: { params: RunTacticStepsParams; result: RunTacticStepsResult };
  shutdown: { params: ShutdownParams; result: ShutdownResult };
}
```

This should be the central source for generic request typing.

### Error-code type surface

The protocol module should also expose a typed known-code surface, such as:

- `AftkServerErrorCode.TacticFailed = -32001`
- `AftkServerErrorCode.FileNotOpen = -32010`
- `AftkServerErrorCode.FileChanged = -32011`
- `AftkServerErrorCode.WorkerUnavailable = -32012`
- `AftkServerErrorCode.StaleNode = -32013`

plus helpers for classifying an arbitrary JSON-RPC error code into:

- known AFTK server error
- standard JSON-RPC error
- unknown server-family error

## Result-shape tolerance rules

The client should be faithful to the documented public JSON shapes, but it also needs a pragmatic tolerance policy.

### Optional/null results

The server docs explicitly allow optional or null result behavior in places such as:

- `get_hover`
- `get_plain_goal`
- `get_plain_term_goal`
- subfields of `InfoViewResult`

So the TypeScript client should tolerate:

- explicit `null`
- omitted optional subfields where the docs allow omission for forward compatibility

### 1-based positions

The client’s types and documentation should preserve the server’s 1-based position convention.
The client should not silently convert to 0-based coordinates.

### Preserve documented field names

Even when Lean implementation details use internal names like `range?` or `hover?`, the TypeScript-facing contract should follow the documented external JSON shape:

- `range`
- `hover`
- `plainGoal`
- `plainTermGoal`

with optionality represented in the TypeScript way.

## Client state model

A practical managed hub client should revolve around a small amount of operational state.

### Owned child process

The client owns at most one managed hub child process at a time.
That child is started from the resolved runtime command spec for the hub executable.

### Startup deduplication

If multiple callers request startup concurrently, the client should deduplicate startup through one shared in-flight start promise.
That preserves the useful main-worktree behavior and avoids racing duplicate `aftk_server` children.

### Pending request registry

The client should maintain a map keyed by request id.
Each pending entry should carry at least:

- method name
- resolve callback
- reject callback
- local timeout handle
- optional local metadata useful for debugging/tests

### Stdout line buffer

The client should maintain a line-oriented stdout buffer for assembling newline-delimited JSON-RPC responses.
Partial lines should remain buffered until completed.

### Running/not-running state

The client should expose a cheap running-state query such as `isRunning()`.
That state should reflect whether the owned child is presently alive and usable, not whether sessions are open inside the hub.

## Recommended client API surface

A practical public client surface should include at least:

- `start(): Promise<void>`
- `isRunning(): boolean`
- `request<M>(method, params, options?): Promise<ResultFor<M>>`
- named convenience methods for each public server method
- `shutdown(options?): Promise<ShutdownResult>`
- `stop(graceful?: boolean): Promise<void>`

### `start()`

Starts the managed hub eagerly if it is not already running.
Useful for tests and hosts that want explicit startup validation.

### `request(...)`

Sends one typed JSON-RPC request.
By default it should auto-start the hub if needed.
It should accept per-call overrides such as:

- `timeoutMs`
- `signal`

A public `request` call should normally assume `autoStart = true`.
Any non-auto-start option should remain an internal/advanced concern.

### Named convenience methods

These should be thin wrappers over `request(...)`, not separate protocol stacks.

### `shutdown()`

Sends the semantic hub `shutdown` request and returns its typed result.
After a successful `shutdown`, the client should ensure its owned child state is cleaned up.

### `stop(graceful?)`

Performs owned-child cleanup regardless of whether the caller wants a semantic `shutdown` operation result.
This is what host adapters should use for best-effort session cleanup.

## Response parsing and request correlation

The client should parse hub stdout as newline-delimited UTF-8 text.

### On each stdout chunk

- append the chunk to the stdout buffer
- repeatedly extract complete lines ending in `\n`
- ignore empty lines
- parse each non-empty line as JSON-RPC response data

### On successful response for a pending id

- remove the pending entry
- clear its timeout
- resolve with the typed result payload

### On error response for a pending id

- remove the pending entry
- clear its timeout
- reject with a typed server-RPC error carrying code/message/data/method

### On response for an unknown id

- ignore it
- optionally emit a debug event if runtime debug hooks are enabled

This covers cases such as late replies after local timeout/cancel cleanup.

### On malformed completed non-empty line

- treat the connection as protocol-corrupted
- reject all pending requests with a protocol error
- mark the child unusable and stop using it

That is the main robustness improvement over the current main-worktree behavior.

## Response validation policy

The client should validate enough to catch protocol drift without turning the client into a heavyweight schema engine.

### Envelope validation is mandatory

The JSON-RPC envelope should always be validated.

### Result validation should be lightweight but method-aware

A good v1 compromise is:

- define lightweight result guards/decoders per public method in `protocol.ts`
- use them when resolving results from `request(...)`
- fail fast with a protocol/result-shape error when the server returns an impossible or incompatible result shape

This is better than a blind cast and still lightweight enough for a first-party local client.

Examples of important method-level checks:

- `open` returns `{ path: string, opened: boolean }`
- `load_node` returns `{ id: string[] }`
- `run_tactic` returns `{ goals: string[], nextId: string }`
- `shutdown` returns `{ stopped: number }`
- `get_hover` returns either `null` or a hover-result object of the documented shape

The client does not need to validate every nested field with maximum paranoia, but it should validate enough to make protocol mismatches immediately visible in tests.

## Error model

The client should distinguish several kinds of failure.

### Runtime/process failures

These come from the shared runtime layer and include things like:

- project-root misconfiguration
- spawn failures
- start failures
- timeout failures
- cancellation failures
- unexpected child exit

The server client should preserve these rather than wrapping everything into one opaque client error.

### JSON-RPC server errors

When the hub returns a valid JSON-RPC error response, the client should reject with a dedicated server-RPC error type carrying at least:

- `method`
- `code`
- `message`
- `data`
- a classification helper or `kind`

This is the TypeScript-side analogue of the current main-worktree `HubRpcError`, but aligned explicitly with the rewrite error-code set.

### Recommended classification helpers

The client should expose helpers such as:

- `isAftkServerRpcError(error)`
- `isAftkErrorCode(error, AftkServerErrorCode.FileChanged)`
- `classifyAftkServerErrorCode(code)`

That lets higher layers write logic like:

- reopen on `FileChanged`
- explain stale-node invalidation specially
- distinguish tactic failure from operational failure

without message scraping.

### Protocol-shape failures

The client should also define a dedicated error kind for:

- malformed stdout lines
- invalid JSON-RPC envelopes
- impossible response shape for a known method

These are not ordinary server-domain errors.
They indicate protocol drift, corruption, or a bug.

### Shutdown/lifecycle failures

If graceful shutdown fails and forced termination is required, the client should preserve enough metadata for tests and diagnostics, even if the final `stop()` call succeeds operationally.

## Compatibility expectations

The server client should preserve the following compatibility expectations.

### With the rewrite server docs

- method names match `docs/server/protocol.md`
- request/result shapes match `docs/server/protocol.md`
- line and column remain 1-based
- known AFTK-specific error codes remain typed and visible
- `run_tactic_steps` remains a first-class client method

### With the main-worktree toolkit surface

- the overall managed-hub pattern remains familiar
- a generic `request(...)` capability still exists
- lazy startup remains the default
- graceful shutdown plus forced termination fallback remains the lifecycle model
- server-family errors are surfaced in a dedicated error type

### Intentional improvements over the main-worktree implementation

The rewrite client should intentionally improve the current main-worktree client in at least these ways:

- dedicated module boundaries instead of one giant file
- explicit protocol type surface in `server/protocol.ts`
- stronger response-envelope and result-shape validation
- malformed stdout treated as protocol failure rather than silently ignored
- clearer distinction between runtime/process errors and server JSON-RPC errors
- stderr capture delegated to the shared runtime layer rather than unconditionally mirrored

## Recommended module responsibilities

Within the layout settled in `plans/toolkit/layout.md`, the server client area should likely be refined as follows.

### `src/toolkit/server/protocol.ts`

Own:

- public request/result/shared-value TypeScript types
- method-name unions and protocol-map types
- known server error-code constants/enums
- lightweight result guards/decoders
- small protocol-classification helpers

This file should not own process lifecycle or child management.

### `src/toolkit/server/client.ts`

Own:

- the managed hub client class
- lazy/eager startup hooks using the runtime layer
- stdout line parsing and JSON-RPC response handling
- pending-request bookkeeping
- generic typed `request(...)`
- named convenience methods
- semantic `shutdown()` and lifecycle `stop(...)`

This file should depend on:

- `src/toolkit/runtime/`
- `src/toolkit/server/protocol.ts`

and should not depend on tool families or `pi` APIs.

## Boundaries and anti-patterns

The server-client layer should explicitly avoid the following mistakes.

### 1. No direct worker client as the public toolkit surface

The toolkit should not bypass the hub and start talking to `aftk_file_worker` directly for ordinary use.

### 2. No tool-formatting logic in the client layer

Formatting hover blocks, goal text, or tactic summaries belongs in the Lean-tool layer above this client.

### 3. No path-shimming policy in the client layer

Things like stripping a leading `@` are tool/host integration concerns, not server-client concerns.
The client should transmit protocol paths faithfully.

### 4. No message-string scraping for structured server behavior

Known error codes should drive program logic, not brittle message text matching.

### 5. No blind `as T` trust of server results without at least lightweight method-aware validation

Because the server and client are being rewritten together, protocol drift should fail fast in tests.

### 6. No silent protocol corruption tolerance

Malformed stdout from the hub should be treated as a real failure, not background noise.

### 7. No hidden session replay after hub restart

If the managed hub dies and later restarts, the client may lazily start a fresh process on a new request, but it must not pretend that previously open file sessions or node ids were preserved.

## Initial implementation checklist for this server-client design

Before the server-client layer can be considered in place, the rewrite should reach at least this baseline:

- public TypeScript protocol types exist for the documented hub method family
- known AFTK server error codes are represented explicitly in TypeScript
- a managed hub client exists on top of the shared runtime layer
- startup is lazy by default and deduplicated across concurrent callers
- request ids and pending-request bookkeeping work for multiple outstanding requests
- JSON-RPC envelope validation is implemented
- method-aware lightweight result validation is implemented
- malformed non-empty stdout lines are treated as protocol failure
- semantic `shutdown()` and lifecycle `stop(graceful?)` are distinct
- named convenience methods exist for the public server method family
- the client depends only on runtime/protocol modules, not on tool or `pi` modules

## Summary

The rewrite toolkit needs a dedicated TypeScript client for the public `aftk_server` protocol.
That client should preserve the successful operational pattern already visible in the main worktree — managed child process, lazy startup, pending-request tracking, dedicated RPC errors — while aligning much more explicitly with the rewrite server’s documented public contract.

So the rewrite server-client layer should:

- speak only to the public hub process,
- define explicit TypeScript protocol types and known error codes,
- provide both generic typed requests and named convenience methods,
- validate envelopes and important result shapes,
- treat malformed stdout as protocol failure,
- preserve structured server error information,
- and separate semantic server shutdown from owned-process cleanup.

That gives the later Lean-tool layer a solid, reusable, testable foundation instead of a one-file pile of JSON-RPC plumbing.
