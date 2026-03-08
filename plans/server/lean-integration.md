# Lean 4 Integration Design for the Server/File-Worker Layer

## Status

Component plan and implementation-status document for how the rewrite’s server/file-worker layer should reuse Lean 4 core APIs.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/transport.md`, `plans/server/protocol.md`, `plans/server/hub.md`, `plans/server/worker.md`, `plans/server/integration.md`, `plans/server/layout.md`, and `plans/server/testing.md`.

## Component implementation status

- Overall status: Implemented
- Implemented in code: Yes
- Last updated basis: the rewrite worker now uses the documented one-shot Lean frontend path (`parseHeader`, `processHeader`, `processCommands`) together with Lean core info-tree query utilities for hover, goal, and term-goal lookup.

## Purpose

This document records how the rewrite should reuse Lean 4 core functionality rather than re-deriving behavior from scratch.
It addresses three related questions:

1. which Lean core APIs the worker should call directly in v1,
2. how closely the rewrite should mirror Lean core’s own server architecture,
3. and whether the rewrite should adopt a one-shot or incremental document model initially.

## Design goals

Lean integration for this layer should:

- reuse Lean core query heuristics wherever practical
- start from the simplest implementation that preserves the current useful AFTK behavior
- avoid wrapping the entire Lean language server when only a smaller semantic surface is needed
- keep the worker’s document model isolated enough that future incremental editing support remains possible
- align lower-layer-aware hover behavior with Lean’s own info-tree mechanisms rather than bypassing them

## Scope and non-scope

### In scope

- frontend context-construction APIs
- info-tree-based query helpers
- tactic parsing and execution entrypoints
- Lean-core server modules studied for future extension
- the v1 choice between one-shot and incremental file handling

### Out of scope

- transport framing details
- public protocol shapes in detail
- hub lifecycle policy in detail
- lower-layer integration policy except where it affects Lean API reuse

## Research summary

The relevant Lean 4 core sources include at least:

- `Lean/Server/README.md`
- `Lean/Server/Snapshots.lean`
- `Lean/Server/Requests.lean`
- `Lean/Server/InfoUtils.lean`
- `Lean/Server/FileWorker.lean`
- `Lean/Server/FileWorker/RequestHandling.lean`
- `Lean/Server/FileWorker/Utils.lean`
- `Lean/Parser/Module.lean`
- `Lean/Elab/Import.lean`

That research supports two high-level conclusions.

### 1. Lean core validates the hub/worker split

Lean’s own language-server stack also uses a watchdog/worker split.
So preserving a hub plus per-file worker architecture is not an AFTK-specific accident.
It is a sound direction for the rewrite.

### 2. Lean core’s full editable-document model is richer than what AFTK needs for v1

Lean core supports:

- editable documents
- snapshot chains
- asynchronous elaboration waiting
- cancellation-aware request handling
- diagnostics and progress flows

Those are important reference points, but they are significantly richer than the current main-worktree AFTK worker.
The rewrite should not import that full complexity immediately unless it materially improves the first deliverable.

## Settled v1 decision: one-shot worker snapshots, not incremental documents

The main architectural choice that needed settling is now:

- **v1 should use a one-shot file snapshot model with reopen-on-change behavior**
- **not** an immediate Lean-core-style incremental editable-document model

## Why this is the right v1 choice

### 1. It matches the current useful AFTK behavior

The main-worktree server/file-worker pair already provides useful Lean semantic querying and transient tactic exploration with a one-shot worker model.
That is the behavior higher layers already know how to consume.

### 2. The rewrite’s bigger immediate job is lower-layer integration

The rewrite is not just porting old server code.
It also has to integrate the server layer with the new:

- knowledge-base layer
- and informal layer.

Adding a full incremental document model at the same time would combine too many moving parts in the first implementation.

### 3. A one-shot model is enough for the initial public surface

The initial public surface is still centered on:

- hover/info queries,
- plain goal queries,
- transient tactic-state loading,
- and tactic execution from those loaded states.

That surface does not require true in-memory edit streams on day one.

### 4. The upgrade path can still remain open

Choosing a one-shot v1 model does not require hard-coding a dead end.
The worker can still isolate context construction and query logic so that a later document/snapshot backend can be swapped in.

## Lean APIs the v1 worker should use directly

The v1 worker should directly reuse the lower-level frontend path already proven in the main worktree.

## Frontend context construction

The worker should build its one-shot file snapshot using the same general stages as the main worktree:

- `Parser.parseHeader`
- `Elab.processHeader`
- command processing that records info trees

In practice this means using the ordinary Lean frontend path that yields:

- environment
- messages
- command syntax
- and info trees

for the file being processed.

The exact helper chosen in code may be a small project-local wrapper, but its semantic basis should remain this explicit frontend flow.

## Query heuristics

The worker should use Lean core query helpers for positional semantics, especially:

- `InfoTree.hoverableInfoAtM?`
- `InfoTree.goalsAt?`
- `InfoTree.termGoalAt?`

This is one of the strongest conclusions from the research.
The rewrite should not invent a separate ad hoc position-selection algorithm for hover and goal queries.

## Goal and term pretty-printing

Goal text should continue to be rendered through Lean pretty-printing such as:

- `Meta.ppGoal`
- expected-type pretty-printing in term-goal contexts

This keeps the worker’s output aligned with Lean itself.

## Tactic parsing and execution

The worker should continue to:

- parse tactic text against the current environment using the Lean `tactic` parser category
- evaluate parsed tactics inside captured tactic states
- and use Lean’s own tactic/goal machinery for post-step state inspection

That preserves both correctness and compatibility with the current main-worktree semantics.

## How closely the rewrite should follow Lean’s own server internals

The rewrite should follow Lean core’s server architecture **selectively**, not wholesale.

## What to copy in spirit

The rewrite should copy in spirit:

- the hub/worker split
- reuse of info-tree query helpers
- the idea that worker semantic state is distinct from public transport
- the separation between document model and request handling

## What not to copy wholesale in v1

The rewrite should not immediately copy wholesale:

- the full editable-document snapshot pipeline
- diagnostics/progress flows
- request cancellation machinery
- the entire LSP-oriented request surface
- or the whole Lean server module tree

That would overshoot the rewrite’s current scope.

## Recommended worker backend boundary

To leave room for future evolution, the worker should hide its document backend behind a small project-local abstraction.
A conceptual split is:

- `Context` / `Snapshot` construction
- query helpers operating on that snapshot
- tactic-state capture/execution layered above the snapshot

In v1, the backend implementation behind that boundary is:

- one-shot startup elaboration from a file on disk

A future backend could instead be:

- versioned in-memory documents backed by Lean snapshot chains

without rewriting the rest of the worker API surface.

## When the rewrite should revisit the one-shot choice

The rewrite should revisit the document model only if real needs arise such as:

- higher layers needing in-memory edits without reopening
- a strong need for cancellation of expensive elaboration requests
- clear evidence that restart-on-change is materially harming usability
- or a desire to align more closely with editor/live-buffer workflows

Until then, reopen-on-change is the right complexity budget.

## Relationship to the informal layer’s existing info attachments

The current rewrite’s informal elaborator already attaches compact presentation summaries to info trees via `DelabTermInfo.docString?`.
That is exactly the kind of Lean-native mechanism the worker should continue to leverage.

This matters because it shows that lower-layer integration does not require bypassing Lean’s own info-tree model.
The worker can enrich hover behavior while still using Lean-facing info infrastructure as the primary path.

## Future Lean-core-inspired improvements to keep in mind

Even though v1 chooses the simpler model, the research still suggests useful future directions.

### Snapshot waiting patterns

If the worker later becomes incremental, it should study Lean patterns such as:

- `withWaitFindSnap`
- `withWaitFindSnapAtPos`

from `Lean.Server.Requests`.

### Incremental document processing

If true edit support becomes necessary, the rewrite should study:

- `Lean.Server.Snapshots`
- `Lean.Server.FileWorker`
- `Lean.Server.FileWorker.Utils`

rather than inventing incremental elaboration infrastructure from scratch.

### Diagnostics and progress

If richer live-edit behavior is adopted later, a separate component plan may be warranted for:

- diagnostics
- progress reporting
- cancellation

But those are intentionally not part of the first server-layer implementation plan.

## Additional implementation findings from Lean core

The Lean 4 core sources suggest several small implementation details that are easy to miss but directly useful.

- `Lean.FileMap.rangeContainsHoverPos` in `Lean/Server/Requests.lean` handles the EOF edge case where a cursor at end-of-file should still count as inside a range ending at EOF. If the rewrite keeps one-shot command-range search helpers, it should either reuse this function or reproduce its EOF behavior explicitly.
- `SnapshotTree.findInfoTreeAtPos` and `findCmdDataAtPos` search snapshot trees pre-order, skip subtrees whose syntax range cannot contain the position, and fall back to the command’s elaboration info tree when no nested snapshot-specific tree is found. Even in a one-shot worker, that search strategy is a good reference for future-proof query helper design.
- `InfoTree.hoverableInfoAtM?` in `Lean/Server/InfoUtils.lean` already bakes in several heuristics the rewrite gets “for free” by calling it directly:
  - skip auxiliary `nullKind` / `evalWithAnnotateState` nodes
  - prefer smaller enclosing ranges
  - prefer constants over variables when spans overlap
  - prefer non-partial term info
  - suppress synthetic-sorry hover
- `InfoTree.goalsAt?` does more than “find a tactic info at a point”. It includes trailing whitespace and EOF behavior, tracks indentation, and can request post-tactic state via `useAfter` when the cursor is after a tactic and no nested tactic after the cursor should take precedence.
- `InfoTree.termGoalAt?` includes a filter specifically to prefer the goal of the whole application in cases like `f a b`, rather than returning the goal for the identifier `f` alone.
- `Parser.parseHeader` and `Elab.processHeader` are the correct frontend entrypoints for one-shot context construction, but the main-worktree-style command pass still needs `infoState.enabled := true` in the `Command.State` or the worker will not have the info trees that all later queries depend on.

A smaller but still useful parity note from Lean’s request handlers is that `handleHover` applies `Hover.rewriteExamples` before returning markdown.
The rewrite does not need to adopt every LSP formatting detail in v1, but that function is worth remembering if Lean-generated hover example formatting later looks worse than expected.

## Implementation guidance for the next code phase

The first Lean-facing code for this design should likely implement:

1. one-shot context construction from file path
2. info-tree capture and command-range filtering
3. hover/goal/term-goal queries via Lean core helpers
4. proof-state capture from goal info
5. tactic parsing/execution against stored states

Only after those basics work should the rewrite spend effort on hypothetical incremental editing support.

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the rewrite worktree:

- the worker reuses the documented Lean frontend and info-tree query path in v1
- the worker’s v1 document model is one-shot startup elaboration with reopen-on-change handled by the hub
- the code structure leaves a clear boundary where a future incremental backend could live
- worker queries and tactic execution are covered by tests over real Lean fixture files
- no unnecessary dependency on Lean’s full language-server stack has been introduced for the initial implementation

## Summary

The rewrite should treat Lean core as a guide and a toolbox, not as an all-or-nothing implementation template.
For v1, the right choice is:

- preserve the hub/worker architecture,
- reuse Lean’s frontend and info-tree query APIs directly,
- keep the worker as a one-shot file snapshot,
- and postpone full incremental editable-document support until there is a concrete need.
