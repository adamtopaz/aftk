# File-Worker Design

## Status

Component plan and implementation-status document for the per-file worker portion of the server/file-worker layer.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/transport.md`, `plans/server/protocol.md`, `plans/server/hub.md`, `plans/server/lean-integration.md`, `plans/server/integration.md`, `plans/server/layout.md`, and `plans/server/testing.md`.

## Component implementation status

- Overall status: Implemented
- Implemented in code: Yes
- Last updated basis: the repository now has a one-shot per-file worker, source-position query handlers, transient tactic-state support, worker shutdown handling, and lower-layer-aware informal hover integration.

## Purpose

This document defines what one file worker should do for one Lean source file.
The worker is responsible for:

- building a semantic snapshot of one file
- answering source-position semantic queries against that snapshot
- creating transient proof-state handles from tactic positions
- running tactic steps against those handles
- and exposing lower-layer-aware hover/info behavior where appropriate

The worker should remain file-local and snapshot-local.

## Design goals

The file-worker design should:

- preserve the useful one-file query model of the earlier implementation
- keep the v1 document model simple enough to implement reliably
- reuse Lean core selection heuristics instead of inventing new ones
- treat transient proof-state nodes as explicit worker-local state
- make source-position, node-id, and invalidation behavior explicit
- provide a clean place for lower-layer-aware hover enrichment
- leave room for a later richer document/snapshot model

## Scope and non-scope

### In scope

- worker startup from one file path
- the in-memory semantic snapshot owned by the worker
- source-position query methods
- transient proof-state node creation and tactic execution
- worker-local invalidation behavior
- the internal `shutdown` method

### Out of scope

- public file-session lifecycle and path canonicalization
- public hub request routing
- transport framing in detail
- full incremental edit support in v1

## Core worker decisions

The v1 worker should make the following choices explicit.

### 1. One worker owns one one-shot file snapshot

The v1 worker should read and elaborate the target file once at startup and keep the resulting semantic data in memory for the life of the process.

That means the worker is not responsible for:

- applying text edits,
- tracking multiple file versions,
- or re-elaborating after on-disk change.

Those concerns remain outside the worker in v1 and are handled operationally by the hub through reopen-on-change semantics.

### 2. Keep the worker file-local

A worker should only know about one file snapshot and its transient state graph.
It should not manage a global open-file table.

### 3. Reuse Lean info-tree query utilities directly

The worker’s hover/goal/term-goal queries should be built on Lean core utilities such as:

- `InfoTree.hoverableInfoAtM?`
- `InfoTree.goalsAt?`
- `InfoTree.termGoalAt?`

This keeps AFTK aligned with Lean’s own editor semantics.

### 4. Keep transient node ids opaque and immutable

A proof-state node id should be:

- opaque to callers
- allocated freshly by the worker
- and treated as a handle to one immutable stored state snapshot

Running a tactic from node `A` should create a new node `B`, not mutate `A` in place.

### 5. Unknown node ids are operational invalidation, not just bad input

The worker should report unknown/stale node ids using the dedicated stale-node protocol error rather than generic invalid params.

## Worker semantic snapshot

A practical v1 worker context should contain at least:

- the input context and file map
- the elaborated environment
- the command-level info trees
- command syntax/range associations for position filtering
- any lightweight helpers needed for lower-layer-aware hover enrichment

A conceptual shape is:

```lean
structure WorkerContext where
  inputCtx     : Parser.InputContext
  env          : Environment
  infoTrees    : PersistentArray InfoTree
  commandTrees : Array CommandTree
```

where each `CommandTree` records:

- the root command syntax
- the associated `InfoTree`
- the command range, if available

## Startup model

At startup, the worker should:

1. receive one file path argument from the hub
2. read the file from disk
3. build the Lean frontend context for that file
4. store the resulting semantic snapshot in memory
5. start its JSON-RPC request loop

If startup elaboration fails, the worker should fail clearly rather than running with a partial context.
The hub should treat such startup failure as worker-unavailable/open failure.

## Source-position handling

The worker should preserve the following rules.

### Input positions

Worker query methods take:

- `line >= 1`
- `col >= 1`

### Internal conversion

The worker converts those to Lean file-map positions using the same `FileMap` conventions Lean uses internally.
The worker should reject zero line/column values as invalid params.

### Position filtering strategy

The worker should preserve the earlier strategy of preferring command trees in this order:

1. commands whose range strictly contains the raw position
2. commands whose range contains the position when stop-boundary inclusion is allowed
3. all commands as a fallback

This keeps lookup behavior robust near command boundaries.

## Query methods

The worker should implement the following file-local query methods.

## `get_hover`

The worker should answer hover queries by combining:

- standard Lean hoverable-info lookup,
- parser-doc fallback where appropriate,
- and lower-layer-aware enrichment logic for informal references where applicable.

When an AFTK-specific lower-layer presentation should take precedence, that decision should be made in the worker’s integration helper rather than in the hub.

## `get_plain_goal`

The worker should use Lean goal-info selection to gather tactic goals at the position and render them with Lean pretty-printing.

The result should include both:

- a structured array of goal strings, and
- a joined `rendered` string for convenience.

## `get_plain_term_goal`

The worker should use Lean term-goal selection to recover the expected type at the queried term site when available.

## `get_infoview`

The worker should aggregate:

- hover
- plain goal
- plain term goal

into one combined response.

This is a convenience method, not a new semantic primitive.

## `load_node`

`load_node` should:

- inspect tactic-goal info at the queried position
- capture one `StateNode` per goal context available there
- allocate one fresh opaque id per captured state
- return the resulting id array in stable order

The implemented worker uses `GoalsAtResult.useAfter` when choosing the captured tactic state, so a cursor position that Lean core interprets as “after the tactic” loads the corresponding post-tactic state rather than always forcing the pre-tactic state.

The worker should return an empty array if no tactic node can be loaded at that location.

## Transient tactic-state model

The worker should own a map from node ids to captured tactic states.

A practical v1 `StateNode` should record the contexts and states needed to resume tactic execution, including:

- `Core.Context` and `Core.State`
- `Meta.Context` and `Meta.State`
- `Term.Context` and `Term.State`
- `Tactic.Context` and `Tactic.State`

This preserves the earlier concept and keeps each node self-contained.

## `get_goals`

Given a valid node id, the worker should:

- resume the stored tactic state
- inspect unsolved goals
- pretty-print them
- return the current goals without allocating a new node id

## `run_tactic`

Given a valid node id and tactic text, the worker should:

1. parse the tactic text against the current environment using the Lean `tactic` parser category
2. resume the stored tactic state
3. run the parsed tactic
4. collect the resulting unsolved goals
5. capture the resulting next state
6. allocate a fresh `nextId`
7. store that next state under `nextId`
8. return the goals plus `nextId`

If tactic parsing fails, the worker should return invalid params.
If tactic execution fails after parsing, the worker should return the dedicated tactic-failed error.

## Node-id semantics

The worker’s node ids should follow these rules.

### Opaque

Callers must treat them as opaque strings.

### File-local

A node id is only meaningful within the worker process that created it.
It is not portable across files.

### Session-local

A node id becomes invalid when the worker exits or the file is reopened in a fresh worker.

### Immutable

A node id always names the same captured state snapshot.
Running tactics creates new ids rather than mutating the old one.

## Error behavior

The worker should distinguish clearly among:

- invalid request parameters
- stale or unknown node ids
- tactic failure
- internal worker failure

### Stale node ids

Unknown node ids should use the dedicated stale-node error.
This includes ids that once existed in an earlier worker generation.

### Tactic failure

A tactic that parses but fails during execution should use the tactic-failed error and should not allocate a new node id.

### Internal failures

Unexpected exceptions while building or querying the worker context should surface as internal errors.

## Text-result expectations

The worker’s text payloads are primarily human-facing and Lean-derived.
Therefore:

- exact strings are useful and should be reasonably stable within one Lean version
- but callers should rely more strongly on field structure than on exact prose across Lean upgrades

This especially applies to:

- hover text
- rendered goals
- term-goal text
- tactic failure text

## Internal shutdown

The worker should implement an internal `shutdown` request that:

- acknowledges the request
- stops accepting new work
- and exits cleanly

This should be the normal path used by the hub before any forced process termination.

## What the worker should not do

The worker should not:

- decide whether a file is open
- canonicalize global file identity for the public API
- watch the filesystem for changes in v1
- persist proof-state nodes into canonical project storage
- expose knowledge-base mutation commands
- emulate the entirety of Lean’s language server protocol

## Future evolution boundary

The main future change the worker may need is a move from:

- one-shot startup elaboration

to:

- versioned document snapshots with incremental elaboration reuse.

To preserve that option, the worker code should keep the following concerns distinct:

- context construction
- source-position query logic
- tactic-state capture/execution
- lower-layer-aware hover enrichment
- RPC handler wiring

## Additional implementation findings from the earlier implementation

Research in `../aftk/AFTK/FileWorker.lean` gives the concrete one-shot implementation skeleton AFTK can follow.

- `getContext` currently performs:
  1. `IO.FS.readFile path`
  2. `mkInputContext input "<AFTK>"`
  3. `initSearchPath (← findSysroot)`
  4. `enableInitializersExecution`
  5. `Parser.parseHeader`
  6. `processHeader`
  7. `IO.processCommands` from a `Command.mkState ...` with `infoState.enabled := true`
- The worker extracts command-level query roots by traversing each `InfoTree` with `rootCommandStx?` and storing `stx.getRangeWithTrailing? (canonicalOnly := true)` in `CommandTree.range?`.
- The earlier implementation uses placeholder file name `"<AFTK>"` in `mkInputContext`; AFTK should decide explicitly whether to preserve that or use the real file path for more accurate messages and diagnostics.
- The current `commandTreesAt` helper uses exactly the three-tier filtering policy already captured elsewhere in this document:
  1. strict containment
  2. boundary-inclusive containment
  3. full fallback to all commands
- Hover currently uses a two-stage fallback:
  - parser docstrings from `findDocString?` over the syntax stack
  - then `InfoTree.hoverableInfoAtM?`, with the info-tree result winning only if its range is at least as specific as the parser-doc range
- Term-goal rendering currently follows Lean LSP practice closely: it instantiates the expected type, pops the binder local context when `ti.isBinder`, creates a fresh mvar with `Meta.mkFreshExprMVar`, and renders it through `Meta.ppGoal`.
- Tactic parsing uses `Parser.runParserCategory` with parser category `tactic` in the stored node environment.

Two earlier quirks are especially important **not** to copy accidentally.

- `get_goals` currently calls the shared helper `runTacticM`, which allocates and stores a fresh hidden node even though `get_goals` does not return a new id.
- `load_node` currently builds `StateNode`s from `goal.tacticInfo.goalsBefore` / `mctxBefore` unconditionally in `mkNextState`, so it does not honor `GoalsAtResult.useAfter` even when `get_plain_goal` would display the post-tactic state at the same cursor position.
- The current worker server registers no explicit `shutdown` handler; AFTK should add one instead of relying only on transport-level shutdown behavior.

AFTK should make both semantic choices explicit instead of inheriting them by accident:

- `get_goals` should inspect a stored node without allocating another one
- and `load_node` should either intentionally preserve current before-state behavior for compatibility or deliberately switch to `useAfter`-aware loading and document that change.

## Implementation guidance for the next code phase

The first worker code should likely land in this order:

1. context construction and command-tree capture
2. position conversion helpers
3. hover/goal/term-goal queries
4. `load_node`
5. node-store plus `get_goals`
6. `run_tactic`
7. internal `shutdown`
8. lower-layer-aware hover enrichment

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the repository:

- the worker starts from one file path and builds one semantic snapshot
- `get_hover`, `get_plain_goal`, `get_plain_term_goal`, `get_infoview`, and `load_node` work over real fixture files
- transient node ids are allocated and stored as documented
- `get_goals` and `run_tactic` work over stored tactic states
- stale node ids and tactic failures are reported with the documented errors
- the worker exposes an internal `shutdown` path and shuts down cleanly under hub control

## Summary

AFTK's file worker should remain conceptually simple and file-local:

- build one semantic snapshot at startup,
- answer Lean source-position queries from stored info trees,
- own an immutable transient proof-state graph,
- and provide lower-layer-aware hover/info behavior where appropriate.

Its state is intentionally ephemeral, and the hub remains responsible for deciding when that ephemeral state must be discarded and rebuilt.
