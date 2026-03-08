# Server Protocol Design

## Status

Component plan and implementation-status document for the public and internal request/response protocol of the server/file-worker layer.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/transport.md`, `plans/server/hub.md`, `plans/server/worker.md`, `plans/server/lean-integration.md`, `plans/server/integration.md`, `plans/server/layout.md`, and `plans/server/testing.md`.

## Component implementation status

- Overall status: Planned
- Implemented in code: No
- Last updated basis: the rewrite worktree now has a server-layer overview and component design docs, but still has no shared server/file-worker protocol module or executable implementation.

## Purpose

This document defines the machine-facing contract for the server/file-worker layer.
It covers:

- public hub method names
- internal worker method names
- request/response shapes
- common shared types
- JSON encoding expectations
- position and range conventions
- error codes and failure semantics

This is the main API contract that higher layers should be able to depend on.

## Design goals

The protocol should:

- preserve the useful current main-worktree method family where practical
- be explicit about what is public and what is worker-internal
- keep request and response shapes small and deterministic
- keep path and position semantics unambiguous
- distinguish operational invalidation from tactic or query failures
- remain easy to call from TypeScript and test harnesses
- allow implementation to evolve internally without constantly changing the external contract

## Scope and non-scope

### In scope

- hub public methods
- worker internal methods
- common JSON value shapes
- node-id, position, range, and text-result conventions
- stable error codes for public consumers
- compatibility expectations for the existing TypeScript wrapper surface

### Out of scope

- the wire framing rules in detail
- worker spawn and lifecycle implementation details
- internal Lean algorithms used to compute results
- lower-layer integration internals beyond what appears in responses

Those are covered by companion documents.

## Core protocol decisions

The v1 protocol should make the following choices explicit.

### 1. Preserve the main Lean-facing public method family

The public hub should continue to expose this method family:

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

This is an important compatibility target for higher-layer migration.

### 2. Keep the public protocol Lean-centric in v1

The v1 public surface should remain centered on:

- file lifecycle,
- source-position semantic queries,
- and transient proof-state exploration.

The server layer may enrich those results using the knowledge-base and informal layers, but it should **not** add separate first-class knowledge-base or informal RPC methods in v1.

### 3. Keep worker methods mostly parallel to hub methods, but file-local

The internal worker protocol should expose file-local methods corresponding to the worker’s own responsibilities:

- `load_node`
- `get_hover`
- `get_plain_goal`
- `get_plain_term_goal`
- `get_infoview`
- `get_goals`
- `run_tactic`
- `shutdown`

Notably:

- worker requests do **not** take a `path`
- `open` / `close` remain hub responsibilities
- `run_tactic_steps` remains a hub convenience method, not a primitive worker capability

### 4. Preserve 1-based line/column positions

All externally visible source positions should use:

- 1-based `line`
- 1-based `col`

This matches the main worktree and the existing TypeScript tooling assumptions.

### 5. Make stale node invalidation a named protocol error

The current main-worktree worker treats unknown node ids like invalid params.
The rewrite should improve this by giving stale-or-unknown transient node ids their own explicit server-family error code.

That makes worker-restart and file-change invalidation easier for callers to reason about.

## Shared value types

The shared protocol module should define common value types used by both hub and worker handlers.

## Common request fragments

### File path parameter

```json
{"path":"Example.lean"}
```

Used by public hub methods that target a file.

### Source location parameter

```json
{"path":"Example.lean","line":12,"col":7}
```

Used by public position-based methods.

### Worker-local source location parameter

```json
{"line":12,"col":7}
```

Used by the internal worker methods.

### Node-id parameter

```json
{"path":"Example.lean","id":"d3f0..."}
```

or worker-local:

```json
{"id":"d3f0..."}
```

Node ids are opaque strings.
Clients must not parse them.

## Shared response value types

### Source position

A source position is:

```json
{"line":12,"col":7}
```

### Source range

A source range is:

```json
{
  "start": {"line": 12, "col": 7},
  "stop":  {"line": 12, "col": 19}
}
```

The range should be treated as a Lean-source span reported through `FileMap` conversions.
Callers should not assume more than:

- the positions are 1-based,
- `start` precedes or equals `stop`,
- and the range is suitable for editor highlighting.

### Hover result

```json
{
  "text": "...",
  "range": {
    "start": {"line": 12, "col": 7},
    "stop":  {"line": 12, "col": 19}
  }
}
```

If no hover content is available, the method returns `null` rather than an empty object.

### Plain goal result

```json
{
  "goals": ["goal text 1", "goal text 2"],
  "rendered": "goal text 1\\n\\n---\\n\\ngoal text 2"
}
```

The `goals` array is the primary structured field.
`rendered` is convenience text for human-facing callers.

### Plain term-goal result

```json
{
  "goal": "expected type text",
  "range": {
    "start": {"line": 12, "col": 7},
    "stop":  {"line": 12, "col": 19}
  }
}
```

If no term goal is available, the method returns `null`.

### Info-view result

```text
{
  "hover": <HoverResult or null>,
  "plainGoal": <PlainGoalResult or null>,
  "plainTermGoal": <PlainTermGoalResult or null>
}
```

The v1 server should emit explicit `null` values for absent optional subresults where that is natural for the chosen encoder.
Callers should also tolerate omission of an optional field for forward compatibility.

### Load-node result

```json
{"id":["node-a","node-b"]}
```

The field name should remain `id` for compatibility with the existing main-worktree surface, even though it contains an array of node ids.

Semantics:

- empty array -> no tactic node available at the requested location
- one element -> exactly one initial tactic state
- multiple elements -> multiple goal states were available at that location

### Get-goals result

```json
{"goals":["goal text 1","goal text 2"]}
```

### Run-tactic result

```json
{
  "goals": ["remaining goal text"],
  "nextId": "node-next"
}
```

### Run-tactic-steps result

```json
{
  "results": [
    {"goals": ["..."], "nextId": "node-1"},
    {"goals": ["..."], "nextId": "node-2"}
  ]
}
```

### Shutdown result

Public hub shutdown returns:

```json
{"stopped":2}
```

meaning that two worker sessions were stopped.

Internal worker shutdown may return a smaller acknowledgement object, but the shared protocol module should still define it explicitly rather than relying on an ad hoc empty response.

## Public hub methods

## `open`

### Request

```json
{"path":"Example.lean"}
```

### Response

```json
{"path":"/abs/Example.lean","opened":true}
```

Semantics:

- `path` in the response is the hub’s normalized/canonical file identity string
- `opened = true` means a new worker was spawned or an invalid old session was replaced
- `opened = false` means an existing fresh session was reused

## `close`

### Request

```json
{"path":"Example.lean"}
```

### Response

```json
{"path":"/abs/Example.lean","closed":true}
```

Semantics:

- `closed = true` means an existing session was closed
- `closed = false` means no session was open for that file identity

## `load_node`

### Request

```json
{"path":"Example.lean","line":12,"col":7}
```

### Response

```json
{"id":["node-a","node-b"]}
```

## `get_hover`

### Request

```json
{"path":"Example.lean","line":12,"col":7}
```

### Response

- `null`, or
- a `HoverResult`

## `get_plain_goal`

### Request

```json
{"path":"Example.lean","line":12,"col":7}
```

### Response

- `null`, or
- a `PlainGoalResult`

## `get_plain_term_goal`

### Request

```json
{"path":"Example.lean","line":12,"col":7}
```

### Response

- `null`, or
- a `PlainTermGoalResult`

## `get_infoview`

### Request

```json
{"path":"Example.lean","line":12,"col":7}
```

### Response

An `InfoViewResult` containing hover, goal, and term-goal subresults.

## `get_goals`

### Request

```json
{"path":"Example.lean","id":"node-a"}
```

### Response

```json
{"goals":["goal text 1","goal text 2"]}
```

## `run_tactic`

### Request

```json
{"path":"Example.lean","id":"node-a","tactic":"simp"}
```

### Response

```json
{"goals":["..."],"nextId":"node-b"}
```

## `run_tactic_steps`

### Request

```json
{"path":"Example.lean","id":"node-a","tactics":["simp","assumption"]}
```

### Response

```json
{
  "results": [
    {"goals": ["..."], "nextId": "node-b"},
    {"goals": [], "nextId": "node-c"}
  ]
}
```

Semantics:

- the hub executes the steps sequentially
- each step uses the previous step’s `nextId`
- if a step fails, the whole request fails with the corresponding error
- partial success results are not returned on failure in v1

## `shutdown`

### Request

```json
{}
```

### Response

```json
{"stopped":2}
```

## Internal worker methods

The worker-internal methods mirror the hub’s file-local capabilities and omit `path`.

### Worker `load_node`

```json
{"line":12,"col":7}
```

### Worker `get_hover`

```json
{"line":12,"col":7}
```

### Worker `get_plain_goal`

```json
{"line":12,"col":7}
```

### Worker `get_plain_term_goal`

```json
{"line":12,"col":7}
```

### Worker `get_infoview`

```json
{"line":12,"col":7}
```

### Worker `get_goals`

```json
{"id":"node-a"}
```

### Worker `run_tactic`

```json
{"id":"node-a","tactic":"simp"}
```

### Worker `shutdown`

```json
{}
```

The worker does not expose `open`, `close`, or `run_tactic_steps` as primitives in v1.

## Path semantics

The protocol should define path behavior explicitly.

### Request path handling

For public hub methods:

- the caller may supply relative or absolute paths
- the hub resolves them to its settled file identity policy before routing
- all operational session matching happens on the hub’s resolved file identity, not on the caller’s raw string

### Response path handling

Where the hub returns a `path`, it should return the hub-resolved canonical/normalized identity string, not merely the raw input.

## Position semantics

The protocol should preserve these rules:

- `line >= 1`
- `col >= 1`
- position conversion is delegated to Lean `FileMap` logic inside the worker
- callers should not send zero-based lines or columns

Out-of-range positions should produce a normal method result such as `null` where appropriate, not undefined behavior.
Clearly malformed positions such as `line = 0` or `col = 0` should produce invalid-params errors.

## Error model

The protocol should use ordinary JSON-RPC error envelopes and make the important AFTK-specific error codes explicit.

## Standard JSON-RPC errors used in v1

The layer should use standard JSON-RPC codes for generic envelope problems such as:

- parse error (`-32700`)
- invalid request (`-32600`)
- method not found (`-32601`)
- invalid params (`-32602`)
- internal error (`-32603`)

## AFTK-specific server-family errors

The following codes should be treated as part of the stable contract.

- `-32001` — tactic failed
- `-32010` — file not open
- `-32011` — file changed; reopen required
- `-32012` — worker unavailable
- `-32013` — stale or unknown node id

### Error meanings

#### `-32001` tactic failed

The request was semantically valid, but tactic execution failed.
The `data` field should contain human-meaningful failure text where available.

#### `-32010` file not open

The caller attempted a file-scoped request for a file that has no open hub session.

#### `-32011` file changed; reopen required

The hub detected that the file backing the session no longer matches the session’s freshness stamp.
The session should be considered invalid and the caller must reopen the file.

#### `-32012` worker unavailable

The worker process died or became unusable.
The caller should normally reopen the file.

#### `-32013` stale or unknown node id

The caller referenced a transient proof-state node id that is no longer valid for the current worker session.
Common causes include:

- worker restart,
- file change and reopen,
- or an id from a different file/session.

This should be distinguished from generic invalid params because it is an expected operational invalidation mode.

## Text stability expectations

Some fields are machine-stable in shape but not guaranteed to have byte-for-byte stable human text across Lean upgrades.
Examples include:

- hover text
- rendered goal text
- tactic failure prose

The stable contract is therefore:

- field presence and meaning are stable
- exact text formatting may evolve with Lean or presentation improvements

Tests should reflect that distinction.

## Compatibility policy

The public protocol should aim for main-worktree compatibility in these respects:

- method names
- 1-based line/column inputs
- overall request/response families
- hub-level file invalidation errors
- worker-local transient node semantics

The rewrite may improve the protocol where it materially helps correctness, especially by making stale node invalidation explicit.

## Additional implementation findings from the main worktree

The current main-worktree code in `../aftk/AFTK/Server.lean` and `../aftk/AFTK/FileWorker.lean` fixes several small compatibility details that are easy to miss during implementation.

- The currently exposed result structures are named exactly `OpenResult`, `CloseResult`, `LoadNodeResult`, `GetGoalsResult`, `RunTacticResult`, `RunTacticStepsResult`, `HoverResult`, `PlainGoalResult`, `PlainTermGoalResult`, `InfoViewResult`, and `ShutdownResult`.
- The compatibility-sensitive field names are exactly:
  - `LoadNodeResult.id : Array String`
  - `RunTacticResult.nextId : String`
  - `ShutdownResult.stopped : Nat`
  - optional range/hover slots encoded as `range?`, `hover?`, `plainGoal?`, and `plainTermGoal?` on the Lean side.
- Because the current main-worktree uses derived `ToJson` on structures with `Option` fields, absent optional fields should be treated as potentially omitted by the encoder rather than requiring explicit JSON `null`.
- The current hub error helpers emit these exact messages:
  - `-32010` -> `"File is not open"`
  - `-32011` -> `"File changed; reopen required"`
  - `-32012` -> `"File worker is unavailable"`
  - `-32001` -> `"Tactic failed"`
- Current invalid-params messages that are already useful compatibility references include:
  - `"params object required"`
  - `"line must be >= 1"`
  - `"col must be >= 1"`
  - `"tactics must be non-empty"`
  - `"failed to parse tactic: {err}"`
  - `"unknown node id: {id}"`

The rewrite does not need to preserve every incidental wording forever, but these strings are the current observable surface and should be treated as the baseline compatibility target unless a documented improvement replaces them.
The deliberate exception already settled in these plans is stale-node handling, where the rewrite should prefer dedicated error `-32013` over the current generic invalid-params behavior.

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the rewrite worktree:

- a shared protocol module defines the settled request/response types
- the public hub methods listed above are implemented with the documented method names
- worker-internal methods are defined explicitly and used by the hub
- the AFTK-specific error codes are emitted as documented
- the implementation uses 1-based line/column positions consistently
- protocol tests cover both successful responses and representative failures

## Summary

The v1 protocol should stay close to the main-worktree Lean-facing surface while tightening the contract where it matters:

- public file lifecycle plus query/tactic methods on the hub,
- file-local worker methods underneath,
- stable small JSON shapes,
- explicit 1-based source positions,
- and named operational errors for file invalidation, worker failure, tactic failure, and stale node ids.
