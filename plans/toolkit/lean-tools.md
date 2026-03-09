# Lean-Facing Toolkit Tools Design

## Status

Component design/status document for the Lean-facing `aftk_*` tool family built on the public server client.
This file now records the rationale for the tool family that exists in code and the follow-on work that may still be added later.

Authoritative implementation docs live in:

- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
- `docs/toolkit/testing.md`

## Component implementation status

- Overall status: Implemented (initial v1), with deferred follow-ons
- Implemented in code: Yes
- Last updated basis: the current Lean-tool implementation in `src/toolkit/tools/lean.ts`, the server client in `src/toolkit/server/**`, the shared output/runtime layers, and `tests/toolkit/**`
- Main deferred follow-ons: any future additions driven by new server methods, structured diagnostics, or richer tactic/proof-exploration surfaces

The core Lean-tool design questions in this file are now answered by the implemented `aftk_*` family.
Historical sections below may still describe pre-implementation expectations; read them as rationale rather than as current-state descriptions.

## Purpose

This document defines the Lean-facing tool family built on top of the rewrite server client.
It is about:

- which `aftk_*` tools exist in v1
- how those tools map to the public server methods
- parameter schema rules
- path normalization policy
- node-id handling policy
- text rendering policy for Lean results
- structured details policy for Lean tool results
- and which main-worktree behaviors should be preserved or improved

The goal is to preserve the already useful Lean-facing tool surface from the main worktree while reimplementing it more cleanly on top of the rewrite’s dedicated runtime, server-client, and output layers.

## Design goals

The Lean-facing tool family should:

- preserve strong compatibility with the existing `aftk_*` tool names where that materially helps migration
- map directly and transparently onto the public `aftk_server` protocol
- remain a thin semantic layer above the reusable server client, not a second client implementation
- provide concise, stable text renderings for direct use by agents
- preserve structured server result data in normalized details payloads
- make file/session lifecycle explicit rather than hiding it behind magical auto-open behavior
- keep path normalization minimal and predictable
- treat node ids as opaque transient handles owned by the server layer
- surface known server errors in a more actionable way than the current main-worktree generic error formatting
- remain focused on Lean-facing query and proof-exploration workflows, not on knowledge-base or informal CLI queries outside the server surface

## Scope and non-scope

### In scope

- the Lean-facing `aftk_*` tool family built on the server client
- parameter schemas and tool descriptions for those tools
- mapping from tool calls to server methods
- concise text rendering rules for Lean query and tactic results
- tool-level path normalization rules
- tool-level node-id handling rules
- tool-level error presentation built on normalized output helpers

### Out of scope

- the underlying managed hub client and JSON-RPC protocol handling
- the generic cross-tool output contract
- knowledge-base CLI-backed tool definitions
- informal CLI-backed tool definitions outside the server hover/infoview surface
- `pi`-specific registration and extension wiring
- future new server methods that do not yet exist in the rewrite protocol

Those are covered by companion documents.

## Research basis and design consequences

This tool-family plan is based on explicit research in both worktrees.

### Main-worktree reference points

Primary files studied:

- `../aftk/lambda/src/aftk-tools.ts`
- `../aftk/docs/aftk/README.md`
- `../aftk/docs/agent-playbook.md`
- `../aftk/docs/future/autoformalization-tools.md`

Important observations from the current main-worktree tool family:

- The existing Lean-facing TypeScript tool surface is already practical and coherent.
- The current tool names are:
  - `aftk_open`
  - `aftk_close`
  - `aftk_load_node`
  - `aftk_get_hover`
  - `aftk_get_plain_goal`
  - `aftk_get_plain_term_goal`
  - `aftk_get_infoview`
  - `aftk_get_goals`
  - `aftk_run_tactic`
  - `aftk_run_tactic_steps`
  - `aftk_shutdown`
- The tool family is a thin semantic wrapper over server methods of the same meaning.
- The current implementation already has useful shared parameter-schema fragments:
  - path only
  - path + line + col
  - path + node id
  - path + node id + tactic
  - path + node id + tactics[]
- The current tool layer performs one integration-specific path normalization step:
  - strip one leading `@` from paths
- The current text renderers are intentionally simple:
  - numbered goals
  - hover text plus optional range
  - term goal plus optional range
  - an infoview section bundle
  - stepwise tactic blocks
- The current tools preserve structured `details` from the server result.
- The current error rendering is still fairly generic and could be more actionable.
- The current `aftk_shutdown` implementation also makes one useful lifecycle choice explicit: after the semantic `shutdown` request succeeds, it clears owned process state with a separate local stop call rather than assuming the client state cleaned itself up.
- The main-worktree playbook shows the intended agent loop clearly:
  - explicit `aftk_open`
  - `aftk_get_hover` on `informal[...]`
  - `aftk_load_node`
  - `aftk_get_goals`
  - tactic exploration via `aftk_run_tactic_steps`
- The future-tool roadmap identifies possible later additions such as:
  - structured goals/context
  - diagnostics
  - tactic candidate branching

Main consequences for the rewrite:

- AFTK should preserve the existing `aftk_*` family in v1;
- it should preserve the explicit session-oriented workflow rather than auto-hiding `open` / `reopen`;
- it should preserve the useful text renderers in spirit;
- but it should improve the family by:
  - placing it on top of the dedicated server client and shared output helpers,
  - defining clearer result and error envelopes,
  - and making tool-level responsibilities more explicit than they are in the current one-file implementation.

### Repository reference points

Files studied:

- `docs/server/protocol.md`
- `plans/toolkit/server-client.md`
- `plans/toolkit/output.md`
- `docs/knowledgebase/cli.md`
- `docs/informal/cli.md`

Important rewrite observations:

- The rewrite server intentionally preserves the current Lean-facing public method family.
- Public positions remain 1-based.
- `load_node` still returns `{ id: string[] }` for compatibility.
- `AFTK/Server/Protocol.lean` fixes the current known-error data payloads as simple strings:
  - file-related errors carry a path string,
  - stale-node errors carry a node-id string,
  - tactic failures carry a rendered message string.
- Hover may already include richer `informal[...]` presentation through the server layer.
- `run_tactic_steps` is a first-class public hub method and not just a client-side convenience rewrite.
- The toolkit output contract now explicitly treats structured details as the stronger compatibility surface.
- The toolkit architecture now has room for other tool families too, so the Lean-facing `aftk_*` names should remain a clearly scoped server-backed family rather than becoming the default prefix for every toolkit operation.

Main consequences for the rewrite:

- the Lean-facing `aftk_*` family should continue to correspond specifically to the server-backed Lean surface;
- these tools should not absorb knowledge-base or informal CLI queries that are outside the server protocol;
- and their details payloads should use the shared normalized output envelope while preserving the underlying server result shapes.

## Core tool-family decisions

The v1 Lean-tools design should make the following choices explicit.

### 1. Preserve the existing `aftk_*` Lean-facing tool names

AFTK should preserve the current Lean-facing tool names exactly:

- `aftk_open`
- `aftk_close`
- `aftk_load_node`
- `aftk_get_hover`
- `aftk_get_plain_goal`
- `aftk_get_plain_term_goal`
- `aftk_get_infoview`
- `aftk_get_goals`
- `aftk_run_tactic`
- `aftk_run_tactic_steps`
- `aftk_shutdown`

This is the most important compatibility target from the main-worktree TypeScript surface.

### 2. Keep the `aftk_*` prefix scoped to the server-backed Lean family in v1

The rewrite toolkit will eventually contain multiple tool families.
So the `aftk_*` prefix should remain associated with the Lean/server-compatible family unless a later design explicitly broadens that convention.

That means:

- knowledge-base CLI-backed tools should use a separate naming convention
- informal CLI-backed tools should use a separate naming convention
- future new `aftk_*` names should normally correspond to new public server methods, not to unrelated toolkit helpers

### 3. Keep the tool family explicit and session-oriented

The server protocol intentionally includes:

- `open`
- `close`
- and `shutdown`

The Lean tool family should preserve that explicit lifecycle rather than auto-opening files behind the user’s back.

So the v1 policy should be:

- `aftk_open` exists and is expected to be used explicitly
- file-scoped query and tactic tools do **not** auto-open missing sessions
- if the file is not open, the tool returns a structured failure reflecting server error `-32010`
- if the file changed, the tool returns a structured failure reflecting `-32011`, and the caller is expected to reopen explicitly

This matches the rewrite server’s settled semantics and keeps agent workflows easier to reason about.

### 4. Build all Lean tools on the reusable server client

The Lean tool family should not own JSON-RPC parsing, child-process management, or request-id bookkeeping.
It should depend on the reusable server client from `plans/toolkit/server-client.md`.

In practice this means:

- tool execution calls named client methods or generic typed requests
- the tool family does not spawn `aftk_server` itself directly
- lifecycle cleanup is delegated through the client’s `stop(graceful?)` surface

### 5. Keep path normalization minimal and tool-specific

The main-worktree tool family strips one leading `@` from paths before calling the server.
That is still useful for `pi`-style path passing and should be preserved.

The v1 path-normalization policy should therefore be:

- if the provided `path` begins with a single leading `@`, strip exactly that leading `@`
- otherwise preserve the path string as given
- do not canonicalize, absolutize, or otherwise reinterpret the path at the tool layer
- let the server own file identity and path resolution semantics after this small integration shim

This keeps the tool layer practical without creating a second path-resolution policy that could drift from the server.

### 6. Treat node ids as opaque transient server-owned handles

The Lean tools should never parse, rewrite, or synthesize node ids.
They should treat them as opaque strings returned by the server.

That means:

- `aftk_load_node` exposes the array returned by the server
- `aftk_get_goals`, `aftk_run_tactic`, and `aftk_run_tactic_steps` accept node ids exactly as provided
- stale-node failures are surfaced through the normalized error contract, not worked around in the tool layer
- the tool layer should not cache or reinterpret node ids beyond passing them through request details where useful

### 7. Preserve current method-level compatibility quirks where they are part of the contract

The tool family should preserve certain awkward-but-settled protocol facts rather than trying to clean them up at the boundary.

Most notably:

- `aftk_load_node` should preserve the server’s `id: string[]` result shape in structured details
- the location-based query tools should preserve the server’s optional/null result behavior
- `run_tactic_steps` should remain a first-class tool rather than being removed in favor of manual repeated calls

Any nicer convenience abstractions should live above this family, not replace it.

### 8. Use shared output helpers and a shared normalized result envelope

The Lean tool family should not invent its own return shape.
It should use the shared output contract from `plans/toolkit/output.md`.

So each Lean tool should return:

- one plain-text content block
- a normalized success or failure `details` payload
- `family: "lean"`
- backend metadata identifying the server method used

### 9. Improve error text while preserving structured error details

The main-worktree toolkit currently formats most server errors generically.
AFTK should improve the text layer by rendering known server errors more actionably.

For example, failure text should distinguish cases like:

- file not open
- file changed; reopen required
- worker unavailable
- stale node id
- tactic failed

while still preserving exact codes and raw error data in structured details.

### 10. Keep the Lean tool family focused on query and exploration, not final proof editing

These tools exist for:

- file/session lifecycle
- semantic queries
- transient tactic exploration

They do **not** exist to:

- edit files
- commit proof text
- manage knowledge-base nodes directly
- manage informal CLI tracking directly

That focus should remain explicit.

## Canonical tool list and mapping

The Lean tool family in v1 should consist of exactly the following tools.

| Tool name | Server method | Primary role |
| --- | --- | --- |
| `aftk_open` | `open` | Open or reuse a file session |
| `aftk_close` | `close` | Close a file session |
| `aftk_load_node` | `load_node` | Capture tactic node ids at a source position |
| `aftk_get_hover` | `get_hover` | Query hover text at a source position |
| `aftk_get_plain_goal` | `get_plain_goal` | Query pretty-printed tactic goals at a source position |
| `aftk_get_plain_term_goal` | `get_plain_term_goal` | Query expected type/term goal at a source position |
| `aftk_get_infoview` | `get_infoview` | Query the bundled info-view result |
| `aftk_get_goals` | `get_goals` | Inspect goals for a previously loaded node id |
| `aftk_run_tactic` | `run_tactic` | Run one tactic from a node id |
| `aftk_run_tactic_steps` | `run_tactic_steps` | Run a sequence of tactics from a node id |
| `aftk_shutdown` | `shutdown` | Semantically stop the hub and its workers |

The tool family should not silently add extra Lean-facing names in v1.
If the server grows new public methods later, they can be added deliberately in a follow-on update.

## Shared parameter-schema decisions

The Lean tools should reuse a small number of shared parameter-schema fragments.
The exact schema library can be finalized in implementation, but the schema content should match the following design.

### Path-only schema

Used by:

- `aftk_open`
- `aftk_close`

Conceptual fields:

- `path: string`

Description style:

- path to the Lean source file

### Location schema

Used by:

- `aftk_load_node`
- `aftk_get_hover`
- `aftk_get_plain_goal`
- `aftk_get_plain_term_goal`
- `aftk_get_infoview`

Conceptual fields:

- `path: string`
- `line: integer >= 1`
- `col: integer >= 1`

Important rule:

- line and column are **1-based** in both schema descriptions and behavior

### Node-id schema

Used by:

- `aftk_get_goals`

Conceptual fields:

- `path: string`
- `id: string`

### One-tactic schema

Used by:

- `aftk_run_tactic`

Conceptual fields:

- `path: string`
- `id: string`
- `tactic: string`

Recommended validation improvement over the current main-worktree tool:

- require a non-empty tactic string at the tool-schema level where the chosen schema system makes that practical

### Multi-tactic schema

Used by:

- `aftk_run_tactic_steps`

Conceptual fields:

- `path: string`
- `id: string`
- `tactics: string[]`

Validation rules:

- `tactics` must be non-empty
- each tactic string should be non-empty

### Empty schema

Used by:

- `aftk_shutdown`

Conceptual fields:

- no fields

## Parameter normalization policy

The Lean tool family should make the following normalization decisions explicit.

### `path`

Normalize only by stripping one leading `@` if present.
Do not perform additional path rewriting in the tool layer.

### `line` and `col`

Do not convert coordinates.
Validate that they are at least `1` in the tool schema and pass them through unchanged.

### `id`

Do not normalize or parse node ids.
Pass them through unchanged.

### `tactic` and `tactics`

Do not rewrite tactic strings.
Preserve exactly what the caller provided, except for any minimal non-empty validation at the schema layer.

## Tool-factory API decisions

The Lean tool family should have a dedicated factory rather than living only inside a catch-all aggregate.

### Canonical dedicated factory

The canonical implementation surface for this component should be something like:

```ts
createAftkLeanTools(options?)
```

returning conceptually:

```ts
{
  tools,
  shutdown(graceful?)
}
```

This preserves the useful integration pattern from the main worktree while making the family-specific implementation explicit.

### Compatibility alias policy

If the package also wants to preserve a top-level compatibility surface like:

```ts
createAFTKTools(...)
```

that may exist as a convenience alias or aggregate wrapper.
But it should **not** be the canonical implementation home of the Lean tool family.

The canonical implementation for this component should remain a dedicated Lean-tools factory that later aggregates can call.

## Per-tool behavior

The following sections settle the intended behavior of each Lean-facing tool.

### Lifecycle tools

#### `aftk_open`

##### Purpose

Open or reuse a server session for a Lean file.

##### Input

- `path`

##### Normalization

- strip one leading `@` if present

##### Server call

- `open { path }`

##### Success details

- normalized success envelope
- `family: "lean"`
- `backend: { kind: "server", method: "open" }`
- `result: OpenResult`

##### Success text

Use the server-returned canonical path in text.
Preferred wording:

- when `opened = true`: `Opened file worker: <canonical path>`
- when `opened = false`: `File already open: <canonical path>`

This preserves current main-worktree phrasing closely.

#### `aftk_close`

##### Purpose

Close a server session for a Lean file.

##### Input

- `path`

##### Normalization

- strip one leading `@` if present

##### Server call

- `close { path }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "close" }`
- `result: CloseResult`

##### Success text

Use the server-returned canonical path in text.
Preferred wording:

- when `closed = true`: `Closed file worker: <canonical path>`
- when `closed = false`: `File was not open: <canonical path>`

#### `aftk_shutdown`

##### Purpose

Semantically shut down the hub and stop all managed file workers.

##### Input

- no fields

##### Server call

- `shutdown {}`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "shutdown" }`
- `result: ShutdownResult`

##### Success text

Preferred wording:

- `Stopped <n> file worker(s).`

##### Lifecycle note

After a successful semantic shutdown, the tool family should ensure the underlying owned client process state is cleaned up.
That cleanup should use the server-client/runtime lifecycle surfaces rather than duplicating process logic in the tool layer.

### Location-query tools

#### `aftk_load_node`

##### Purpose

Capture tactic node ids at a source location.

##### Input

- `path`
- `line`
- `col`

##### Server call

- `load_node { path, line, col }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "load_node" }`
- `result: LoadNodeResult`

##### Success text

The tool text should be explicit about the fact that multiple node ids may be returned.

Preferred rendering rules:

- if exactly one id: `Node id: <id>`
- if more than one id:

```text
Loaded 2 node ids:
1. <id1>
2. <id2>
```

- if the server ever returns an empty array, render a clear empty message such as:
  - `No tactic nodes found at this location.`

This is a small improvement over the current main-worktree slash-joined rendering while preserving the raw structured result unchanged.

#### `aftk_get_hover`

##### Purpose

Fetch hover text at a source location.

##### Input

- `path`
- `line`
- `col`

##### Server call

- `get_hover { path, line, col }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "get_hover" }`
- `result: HoverResult | null`

##### Success text

Preferred rendering rules:

- if result is `null`: `No hover information at this location.`
- otherwise render:
  - the hover `text`
  - optionally followed by range information in a compact suffix if `range` exists

The tool should not try to reinterpret or summarize the hover payload further.
This matters because the server may already be returning rich `informal[...]`-aware hover text.

#### `aftk_get_plain_goal`

##### Purpose

Fetch pretty-printed tactic-goal text at a source location.

##### Input

- `path`
- `line`
- `col`

##### Server call

- `get_plain_goal { path, line, col }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "get_plain_goal" }`
- `result: PlainGoalResult | null`

##### Success text

Preferred rendering rules:

- if result is `null`: `No goal information at this location.`
- otherwise:
  - use `rendered` if it is non-empty after trimming
  - otherwise fall back to rendering the `goals` array deterministically

This preserves the current main-worktree behavior and matches the server protocol’s intent that `rendered` is convenience text while `goals` is the stronger structured field.

#### `aftk_get_plain_term_goal`

##### Purpose

Fetch expected-type/term-goal text at a source location.

##### Input

- `path`
- `line`
- `col`

##### Server call

- `get_plain_term_goal { path, line, col }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "get_plain_term_goal" }`
- `result: PlainTermGoalResult | null`

##### Success text

Preferred rendering rules:

- if result is `null`: `No term goal information at this location.`
- otherwise render the `goal` text and append compact range information if present

#### `aftk_get_infoview`

##### Purpose

Fetch the bundled infoview-style result at a source location.

##### Input

- `path`
- `line`
- `col`

##### Server call

- `get_infoview { path, line, col }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "get_infoview" }`
- `result: InfoViewResult`

##### Success text

The text should use a stable multi-section rendering in the style already visible in the main-worktree implementation.
A good v1 format is:

```text
Hover
-----
...

Goal
----
...

Term goal
---------
...
```

Each section should use the same renderer as the corresponding individual tool, including explicit no-result wording where necessary.

This keeps `aftk_get_infoview` readable without requiring callers to inspect JSON manually.

### Node-state and tactic tools

#### `aftk_get_goals`

##### Purpose

Fetch current goals for a previously loaded node id.

##### Input

- `path`
- `id`

##### Server call

- `get_goals { path, id }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "get_goals" }`
- `result: GetGoalsResult`

##### Success text

Use a deterministic goal renderer shared with other Lean tools.
Preferred behavior:

- no goals -> `No goals.`
- one or more goals -> numbered goal blocks in stable order

#### `aftk_run_tactic`

##### Purpose

Run one tactic from a node id.

##### Input

- `path`
- `id`
- `tactic`

##### Server call

- `run_tactic { path, id, tactic }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "run_tactic" }`
- `result: RunTacticResult`

##### Success text

The text should front-load the newly allocated node id and then show the resulting goals.
A good v1 rendering is:

```text
nextId: <nextId>

<goal rendering>
```

This preserves the current main-worktree behavior closely.

#### `aftk_run_tactic_steps`

##### Purpose

Run a sequence of tactics from a node id.

##### Input

- `path`
- `id`
- `tactics[]`

##### Server call

- `run_tactic_steps { path, id, tactics }`

##### Success details

- normalized success envelope
- `backend: { kind: "server", method: "run_tactic_steps" }`
- `result: RunTacticStepsResult`

##### Success text

The text should render one deterministic block per step, preserving current main-worktree style in spirit.
A good v1 format is:

```text
Step 1 nextId: <id1>
-------------------
<goal rendering>

Step 2 nextId: <id2>
-------------------
<goal rendering>
```

If the server ever returns an empty `results` array unexpectedly, render a clear fallback such as:

- `No step results returned.`

## Shared Lean text-rendering rules

The Lean tool family should share a small set of renderers rather than formatting each tool ad hoc.

### Goals renderer

The shared goals renderer should:

- return `No goals.` for an empty goal list
- number goals when there are one or more
- separate multi-goal blocks with blank lines
- preserve the exact goal text itself

### Range renderer

The shared range renderer should render compactly, e.g.:

- `(range: 10:26-10:34)`

It should be appended only when range information exists.

### Compound infoview renderer

The shared infoview renderer should preserve a stable section order:

1. Hover
2. Goal
3. Term goal

This should not vary by what happens to be present.
Missing sections should still render with explicit no-result wording.

## Error behavior for Lean tools

The Lean tool family should use the shared normalized failure envelope from `plans/toolkit/output.md`, with Lean-specific text renderers for known server errors.

### Failure backend metadata

Failures should identify at least:

- `family: "lean"`
- `backend: { kind: "server", method: <method> }`

### Known server-error rendering rules

The following known server errors deserve specific, actionable text.
In the current repository protocol, their `error.data` payloads are simple strings, so the Lean tool family may safely treat them as concise path/id/message context when present.

#### File not open (`-32010`)

Preferred text style:

- `File is not open. Use aftk_open first.`

If the server error data includes a path, include it succinctly.

#### File changed; reopen required (`-32011`)

Preferred text style:

- `File changed; reopen required.`

If a path is available, include it.
This is one of the most important actionable Lean-tool failures.

#### Worker unavailable (`-32012`)

Preferred text style:

- `File worker is unavailable. Reopen the file and try again.`

#### Stale or unknown node id (`-32013`)

Preferred text style:

- `Stale or unknown node id. Load a fresh node and try again.`

If the failing id is available, include it briefly.
This wording should remind callers that node ids are transient.

#### Tactic failed (`-32001`)

Preferred text style:

- `Tactic failed.`
- followed by a short rendered message excerpt when the server supplied one

This should remain distinct from operational failures like stale sessions or dead workers.

### Unknown or generic failures

For unknown server RPC errors, runtime failures, or protocol errors, the Lean tool family should fall back to the shared generic error rendering helpers from the output layer.

### Error details policy

Even when the text is concise and actionable, the structured details should preserve:

- error kind/category
- exact server code when present
- raw server data when present
- relevant runtime diagnostics when the failure is not a server-domain error

## Relationship to lower-layer richness

The Lean tool family should not duplicate lower-layer knowledge-base or informal queries directly.
But it should preserve and expose the richness the server already injects.

### Hover and `informal[...]`

If the server’s hover result already includes rich `informal[...]` presentation text, `aftk_get_hover` should display it faithfully rather than trying to re-query the informal CLI itself.

### Infoview bundles

Similarly, `aftk_get_infoview` should remain a thin bundle over the server result.
It should not try to augment the result with extra CLI calls in v1.

## Compatibility vs improvements

The Lean tool family should preserve the following current behaviors.

### Behaviors to preserve closely

- exact `aftk_*` tool names
- explicit `open` / `close` / `shutdown` lifecycle tools
- 1-based line and column semantics
- leading-`@` path stripping
- simple human-readable renderers for hover/goals/infoview/tactic steps
- returning structured result data alongside text

### Behaviors to improve deliberately

- more explicit multi-id rendering for `aftk_load_node`
- more actionable rendering for known server error codes
- stronger shared success/failure details envelope
- clearer separation between server-client code and tool-definition code
- dedicated family-specific factory rather than only a monolithic `createAFTKTools(...)`

## Future Lean-tool extensions that are not part of v1

The main-worktree future roadmap mentions possible additions such as:

- structured goal/context queries
- diagnostics
- one-call tactic candidate branching

Those are plausible future Lean-tool additions **if and when the server protocol adds the necessary public methods**.
They are not part of this v1 design doc.

So this component should not invent tools like:

- `aftk_get_goal_structured`
- `aftk_get_diagnostics`
- `aftk_run_tactic_candidates`

until the lower-layer server surface exists and is planned/documented.

## Recommended module responsibilities

Within the layout settled in `plans/toolkit/layout.md`, the Lean tool family should likely live in:

### `src/toolkit/tools/lean.ts`

This module should own:

- Lean-tool parameter schemas
- shared Lean text renderers or imports of them from shared output helpers
- the `aftk_*` tool definitions themselves
- the dedicated Lean-tools factory
- Lean-family-specific error-text mapping built on normalized errors

It should depend on:

- `src/toolkit/server/client.ts`
- `src/toolkit/output/`
- shared runtime/config option types where needed

It should not own:

- JSON-RPC parsing
- child-process management
- `pi` registration
- knowledge-base or informal CLI tool definitions

## Boundaries and anti-patterns

The Lean tool family should explicitly avoid the following mistakes.

### 1. No hidden auto-open behavior for file-scoped tools

That would blur the server’s explicit session model and make reopen-on-change behavior harder to reason about.

### 2. No parsing or reinterpretation of node ids

They are opaque transient server-owned handles.

### 3. No duplication of server-client logic in the tool layer

The tool family should call the reusable client, not reimplement request handling.

### 4. No path canonicalization policy beyond leading-`@` stripping

The server owns actual path/session semantics.

### 5. No CLI-side augmentation for hover/goals in this family

This family should stay server-backed and thin.
If knowledge-base or informal CLI-backed enrichments are needed, they belong in those tool families or in future composite tools.

### 6. No collapse of all failures into generic prose

Known server codes should remain structured and should receive more actionable text.

### 7. No expansion of the `aftk_*` namespace to unrelated non-server tools by accident

That namespace is valuable precisely because it already means “Lean-facing server-compatible tool family.”

## Initial implementation checklist for this Lean tool design

Before the Lean tool family can be considered in place, AFTK should reach at least this baseline:

- a dedicated Lean-tools factory exists on top of the server client
- the full existing `aftk_*` tool set is implemented
- parameter schemas exist for all tools with 1-based location validation
- leading-`@` path stripping is implemented in the tool layer
- all tools return one text content block plus normalized details
- all tools use `family: "lean"` backend metadata
- the tool family preserves raw server result shapes inside `details.result`
- known server errors get actionable text while preserving exact codes/data in details
- `aftk_shutdown` performs semantic shutdown and owned-client cleanup coherently
- no Lean tool depends on `pi`-specific registration code

## Summary

AFTK should preserve the existing `aftk_*` Lean-facing tool family as the practical migration target from the main worktree.
Those tools should remain a thin but useful semantic layer over the public `aftk_server` protocol:

- explicit file lifecycle,
- location queries,
- transient node inspection,
- and tactic exploration.

AFTK should keep the successful parts of the current tool family:

- stable names,
- simple path normalization,
- concise text renderers,
- and structured results.

But it should improve the design by placing those tools on top of the dedicated server client and shared output contract, using a dedicated Lean-tools factory, and rendering known server errors in a more actionable way.

That gives the rewrite a clean, reusable Lean-facing tool surface without losing the compatibility and everyday utility that already make the current `aftk_*` tools valuable.
