# Server and File-Worker Layer Plan

## Status

Overall design/status document for the third layer of `aftk`.
This file now mainly records the rationale and follow-on roadmap for an implemented layer.
Detailed subdesigns live under `plans/server/`, while current implementation behavior is documented under `docs/server/`.

## Plan implementation status

- Overall status: Implemented (initial v1)
- Fully implemented: Yes, for the current v1 baseline
- Last updated basis: the implemented `AFTK.Server` / `AFTK.FileWorker` module trees, standalone executables, lower-layer-aware hover integration, and server-layer test coverage integrated into `lake test`

This section is the authoritative status summary for this layer.
Historical comparison sections below remain useful as design rationale, but `docs/server/**` is the source of truth for current implementation behavior.

## Purpose

The server and file-worker layer is the operational service layer of AFTK.
It sits above the knowledge base and informal layer and below the TypeScript toolkit and AI-agent layers.

Its job is to provide long-running process-backed services for:

- Lean file inspection,
- Lean proof-state exploration,
- lower-layer-aware presentation and lookup behavior,
- and stable machine-facing interfaces that higher layers can build on.

In the earlier implementation, this role is filled by `aftk_server` and `aftk_file_worker`.
AFTK should preserve the useful parts of that design while adapting it to the current layered architecture, where the server layer is expected to understand not only Lean files, but also the knowledge-base and informal layers that now sit below it.

## Position in the layered architecture

The overall architecture stack is:

1. Knowledge base layer
2. Informal layer
3. Server and file-worker layer
4. Toolkit layer
5. AI autoformalization agent layer

The server/file-worker layer depends directly on the first two layers.
Higher layers should depend on it for long-running interactive behavior instead of reimplementing file management, Lean semantic queries, or transient proof-state exploration themselves.

## Relationship to the earlier implementation

The earlier implementation in `../aftk` remains a useful reference point for design comparison and historical context.
The most relevant files are:

- `../aftk/AFTK/Server.lean`
- `../aftk/AFTK/FileWorker.lean`
- `../aftk/lambda/src/aftk-tools.ts`
- `../aftk/docs/aftk/README.md`
- `../aftk/README.md`
- `../aftk/lakefile.lean`

### Main-worktree behavior worth preserving in spirit

Research against those files shows that the current server/file-worker layer has a clear and useful shape.
AFTK should preserve the following ideas unless there is a specific architectural reason to change them.

- A separate hub/server process manages one file worker per open Lean file.
- Worker sessions are keyed by canonicalized file paths.
- The hub exposes a small JSON-RPC method surface centered on:
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
- Source-position methods use **1-based** `line`/`col` coordinates.
- The hub is responsible for path canonicalization, worker spawn/stop, liveness checks, and forwarding requests to the correct worker.
- The hub reports explicit server-level failures for:
  - file not open (`-32010`)
  - file changed; reopen required (`-32011`)
  - worker unavailable (`-32012`)
- The file worker owns transient proof-state nodes.
  These are produced by `load_node` and extended by `run_tactic` / `run_tactic_steps`.
- Those proof states are intentionally ephemeral and disappear when the worker is restarted or closed.

### Main-worktree implementation findings

Research against `../aftk/AFTK/Server.lean` and `../aftk/AFTK/FileWorker.lean` also shows more detailed implementation decisions that should directly inform AFTK design.

#### Hub/server side

The current `AFTK.Server` implementation:

- canonicalizes requested paths before using them as session keys,
- records a per-session file stamp using modification time plus byte size,
- spawns workers as child processes via `lake exe aftk_file_worker <path>`,
- creates a JSON-RPC client for each worker,
- checks both child liveness and file freshness before forwarding requests,
- removes and stops sessions when workers die or files change,
- forwards most methods directly to the worker after path normalization,
- and implements `run_tactic_steps` as a hub-level loop over repeated `run_tactic` requests.

In other words, the current hub is deliberately small.
Its main role is session and lifecycle management, not semantic Lean analysis.

#### File-worker side

The current `AFTK.FileWorker` implementation:

- reads the file from disk once at startup,
- builds a one-shot Lean context using:
  - `Parser.parseHeader`
  - `Elab.processHeader`
  - `IO.processCommands`
- stores command-level `InfoTree` data and filtered command ranges,
- answers hover and goal-style requests from those stored trees,
- uses Lean’s info-tree utilities such as:
  - `hoverableInfoAtM?`
  - `goalsAt?`
  - `termGoalAt?`
- captures tactic-state snapshots by storing the `Core`, `Meta`, `Term`, and `Tactic` contexts and states in a `StateNode`,
- parses tactic text with `Parser.runParserCategory` against the Lean `tactic` parser category,
- and allocates fresh transient node ids for every new proof-state branch.

That means the current worker is conceptually:

- a one-file semantic snapshot built from the Lean frontend,
- plus a worker-local transient proof-state graph.

### Main-worktree limitations to revisit deliberately

AFTK should not blindly port every current limitation.
The most important limitations to revisit deliberately are:

- the worker currently reads the file from disk once instead of handling in-memory versioned edits,
- file changes currently force explicit reopen behavior,
- diagnostics/progress and request cancellation are much simpler than in Lean core’s own language server,
- the current public method surface is still mostly Lean-centric,
- and transport/lifecycle code is tightly coupled to the current `lean_worker`-based implementation.

These limitations are acceptable reference points, but they should be revisited consciously in the component design docs instead of being copied forward by inertia.

## Lean 4 core research and reuse strategy

Research against the Lean 4 v4.28.0 sources bundled under:

```text
/home/dev/.elan/toolchains/leanprover--lean4---v4.28.0/src/lean
```

shows that AFTK should study Lean core’s own server implementation carefully rather than treating the earlier code as the only reference.

The most relevant Lean core files are:

- `Lean/Server/README.md`
- `Lean/Server/Snapshots.lean`
- `Lean/Server/Requests.lean`
- `Lean/Server/InfoUtils.lean`
- `Lean/Server/FileWorker/RequestHandling.lean`
- `Lean/Server/FileWorker/Utils.lean`
- `Lean/Server/FileWorker.lean`
- `Lean/Parser/Module.lean`
- `Lean/Elab/Import.lean`

### Lean core findings most relevant to this layer

#### 1. Lean core also uses a watchdog/worker split

`Lean/Server/README.md` confirms that Lean’s own language server is built around a watchdog process plus per-file worker processes.
That strongly supports preserving a hub/worker split in AFTK rather than collapsing the whole layer into one monolithic executable.

#### 2. Lean core has a richer snapshot-based file model than the current the AFTK worker

`Lean/Server/FileWorker.lean`, `Lean/Server/FileWorker/Utils.lean`, and `Lean/Server/Snapshots.lean` show Lean core’s more sophisticated model:

- editable documents,
- asynchronous snapshot trees,
- incremental elaboration reuse across edits,
- request waiting on not-yet-ready snapshots,
- diagnostics/progress reporting,
- and cancellation-aware request handling.

This is an important design reference because the earlier `AFTK.FileWorker` currently uses a simpler one-shot file load.
AFTK should explicitly decide whether v1 remains reopen-on-change or whether it adopts some version of Lean core’s editable-document model.

#### 3. Lean core already encodes the right hover/goal heuristics

`Lean/Server/InfoUtils.lean` defines the main positional-selection logic for:

- `InfoTree.hoverableInfoAtM?`
- `InfoTree.goalsAt?`
- `InfoTree.termGoalAt?`

The earlier file worker already uses these utilities directly.
AFTK should continue to do so, or otherwise mirror their behavior intentionally, rather than inventing new ad hoc heuristics for hover and goal lookup.

#### 4. Lean core request handling is a strong model for future incremental behavior

`Lean/Server/Requests.lean` provides useful patterns such as:

- `withWaitFindSnap`
- `withWaitFindSnapAtPos`
- request tasks that can wait for elaboration progress,
- and explicit handling of file-changed situations while requests are in flight.

Even if AFTK starts with the simpler reopen-on-change model from the earlier implementation, its module boundaries should leave room for later adoption of these patterns.

#### 5. The earlier file worker is reusing a lower-level frontend path that Lean core exposes explicitly

`Lean/Parser/Module.parseHeader` and `Lean/Elab.processHeader` document the lower-level frontend steps that the current file worker mirrors directly.
That means AFTK does not need to treat the current `getContext` implementation as mysterious or magical; it can be understood as a simplified one-shot frontend path.

### Immediate design conclusions from the Lean-core research

The research above suggests the following for AFTK.

- The hub/worker process split should remain the default architectural direction.
- Hover and goal lookup should continue to be grounded in Lean core info-tree utilities and their existing heuristics.
- The worker’s document model should be isolated behind clear module boundaries so AFTK can choose between:
  - a earlier-style one-shot file snapshot, and
  - a Lean-core-style versioned incremental snapshot model.
- Transport concerns should be separated from semantic worker logic as much as practical.
- AFTK should preserve today’s useful public behaviors first, while still borrowing architectural ideas from Lean core where they improve future extensibility.

## Core responsibilities

The server/file-worker layer should eventually provide the following capabilities:

- manage a long-running hub/server process
- manage per-file worker processes or their settled equivalent
- canonicalize file identity and control worker lifecycle
- expose a stable machine-facing request surface for higher layers
- answer Lean semantic queries at source positions
- create and manage transient proof-state handles for tactic exploration
- integrate lower-layer knowledge-base and informal presentation behavior where appropriate
- make invalidation, restart, and error behavior explicit to callers
- provide a foundation that the toolkit layer can use directly

## Architectural commitments

As this layer is designed in detail, it should preserve the following commitments.

### 1. Preserve a hub/worker split

AFTK should keep a distinct hub/server process and per-file worker model unless a later design document gives a compelling reason to change it.
Both the current AFTK implementation and Lean core’s server architecture support this direction.

### 2. Keep reusable library code separate from executable entrypoints

The implementation should not collapse everything into `main` functions.
Reusable logic should live in ordinary Lean modules below the executable wrappers.
That is especially important because later layers and tests may need to reuse server/file-worker internals.

### 3. Preserve the current Lean-facing public method family where practical

The current hub methods are already consumed by the TypeScript tool layer in the earlier implementation.
So AFTK should treat that method family as an important compatibility target, especially for:

- `open` / `close` / `shutdown`
- `load_node`
- `get_hover`
- `get_plain_goal`
- `get_plain_term_goal`
- `get_infoview`
- `get_goals`
- `run_tactic`
- `run_tactic_steps`

This does not forbid adding new methods later, but compatibility should be an explicit design goal rather than an accident.

### 4. Keep transient proof-state nodes worker-local and non-persistent

Transient proof exploration belongs to the file worker.
It should not be persisted into the knowledge base or treated as canonical project data.
Restarting or reopening a worker may invalidate these nodes, and that invalidation should remain an explicit part of the contract.

### 5. Make file identity and invalidation rules explicit

The layer must define, not merely imply:

- how file paths are canonicalized,
- what counts as “the same open file,”
- when a worker is considered stale,
- what happens on file changes,
- and what errors callers should expect when a worker becomes invalid.

The exact v1 choice between file-stamp checking and versioned document updates remains a design topic, but the rules must be explicit and testable.

### 6. Reuse lower-layer libraries rather than duplicating their data

The knowledge base and informal layers already own their respective data and semantics.
The server layer should call into those libraries where needed.
It should not introduce a second store for knowledge-base content, informal metadata, or declaration-tracking state.

### 7. Reuse Lean core query heuristics where possible

AFTK should continue to rely on Lean core’s `InfoTree`, `FileMap`, and `Lean.Server.InfoUtils` behavior for hover and goal lookup unless there is a specific reason not to.
This keeps the server layer aligned with Lean’s own editor semantics.

### 8. Keep the protocol and error model stable and explicit

Higher layers need stable machine-facing contracts.
So request/response shapes, error codes, and invalidation behavior should be treated as design-level API decisions, not just implementation details.

### 9. Start from the simplest viable operational model, but leave room for richer editing support

A earlier-style reopen-on-change worker model may still be the right v1 implementation choice.
If so, AFTK should still structure its internals so that a later move toward Lean-core-style editable documents and request cancellation does not require a total redesign.

## Conceptual model

At a high level, this layer revolves around a small set of concepts:

- a **hub/server** that owns worker sessions and external routing
- a **worker session** associated with one canonical Lean file identity
- an **open document identity** whose freshness and validity rules must be explicit
- a **source-position query** addressed by file plus 1-based line/column
- a **proof-state handle** created from a source position and then extended by tactic execution
- a **lower-layer augmentation path** that can enrich Lean-facing results using the knowledge-base and informal layers
- a **machine-facing protocol** that higher layers can treat as stable

The exact concrete types should be refined in the component plans under `plans/server/`.
The important point is that the hub owns operational lifecycle, while the worker owns file-local semantic state.

## Component plans

The main component design documents for this layer now live under `plans/server/`.
They are:

- `plans/server/transport.md` — process topology, IPC framing, JSON-RPC transport choices, how to use `lean_worker` cleanly as a dependency, batching support, shutdown behavior, and how transport concerns stay separate from semantic worker logic
- `plans/server/protocol.md` — the public method surface, request/response types, JSON encoding rules, compatibility targets from the earlier implementation, line/column conventions, error-code policy, and which behaviors are part of the stable contract
- `plans/server/hub.md` — hub/server responsibilities, path canonicalization, session registry design, worker spawn/restart/stop behavior, file-freshness checks, request forwarding, per-session serialization, and cleanup semantics
- `plans/server/worker.md` — file-worker responsibilities, one-file context model, command/info-tree lookup behavior, source-position query semantics, proof-state-node semantics, tactic execution behavior, and worker-local invalidation rules
- `plans/server/lean-integration.md` — how the worker should reuse Lean 4 core APIs such as `parseHeader`, `processHeader`, snapshot/query utilities, and `InfoUtils`; the settled v1 choice between one-shot file loading and incremental editable-document models; and how closely AFTK should follow Lean core server architecture internally
- `plans/server/integration.md` — how this layer should integrate with the knowledge-base and informal layers, including hover/presentation enrichment, whether any first-class server methods should expose lower-layer functionality directly, and what lower-layer state must remain non-duplicated
- `plans/server/layout.md` — Lean module and namespace layout, dependency boundaries between reusable server/file-worker code and executable wrappers, expected executable names such as `aftk_server` and `aftk_file_worker`, and the test-tree split for this layer
- `plans/server/testing.md` — unit, subprocess, and end-to-end process testing strategy; fixture Lean files; protocol golden tests; file-change and restart cases; and how this layer should fit into `lake test`

Likely future component plans include:

- no additional component plans are clearly required yet beyond the list above, though a dedicated diagnostics/progress design document may become useful if the implementation later adopts Lean-core-style incremental editing behavior

## Relationship to adjacent layers

### Knowledge base layer

The server layer may need knowledge-base data, but it should obtain that data through `AFTK.KnowledgeBase` library APIs.
It should not bypass the knowledge-base layer with ad hoc file reads or its own competing storage logic.

### Informal layer

The server layer should treat the informal layer as the source of Lean-aware informal/formal bridge behavior.
For example, hover over `informal[...]` sites should reuse informal-layer presentation/resolution support rather than rebuilding it independently in the worker.

### Toolkit and AI layers

The toolkit and AI layers need stable, long-running, machine-facing services.
This server layer is where those services should live.
Those higher layers should not need to manage worker processes, transient proof-state ids, or Lean position-query semantics themselves.

## Boundaries and non-goals

The server/file-worker layer is important, but it still has a limited scope.

### In scope

- long-running hub/server and file-worker behavior
- process lifecycle and per-file worker management
- Lean semantic source-position queries
- transient tactic exploration
- explicit invalidation and restart behavior
- lower-layer-aware presentation and selected integration points
- stable machine-facing protocol design for higher layers

### Out of scope for this layer

- canonical knowledge-base storage and mutation logic itself
- `informal[...]` elaboration and declaration-tracking internals themselves
- TypeScript toolkit abstractions
- AI-agent orchestration logic
- a full replacement for Lean’s own language server surface
- persisted proof-search history or proof-state storage in canonical project data
- remote multi-user service design

Those belong to other layers or later work.

## Design constraints

As the component plans are written, this layer should preserve the following constraints.

- keep dependencies one-directional: server/file-worker depends on knowledge base and informal, not vice versa
- avoid duplicating knowledge-base or informal canonical data
- keep the public protocol deterministic and stable enough for automation
- make invalidation and restart behavior explicit rather than implicit
- keep transient proof-state storage clearly worker-local
- preserve useful earlier-implementation compatibility where it materially benefits higher-layer migration
- study Lean core server internals before inventing new query or lifecycle mechanisms from scratch
- implement reusable library modules first and keep executable wrappers thin
- add process-level tests rather than relying only on pure unit tests
- continue following AFTK policy of selective borrowing from `../aftk` rather than wholesale file copying

## Design clarifications resolved so far

The following design points are now considered settled at the overview level and are documented in the component plans under `plans/server/`.

- AFTK should preserve a hub/server plus per-file worker split.
- The current Lean-facing method family should be treated as an important compatibility target.
- External source-position APIs should continue to use 1-based `line`/`col` coordinates.
- Transient proof-state handles should remain worker-local and non-persistent.
- Lower-layer awareness should be added through integration with `AFTK.KnowledgeBase` and `AFTK.Informal`, not through a second server-owned natural-language store.
- The first implementation should prioritize the Lean-facing interactive surface and lower-layer presentation integration before trying to mirror every lower-layer CLI command into a long-running server API.
- The v1 transport boundary should remain JSON-RPC over stdio and should use `lean_worker` directly as the transport dependency, with `AFTK.Server.Transport` acting as a thin AFTK-specific integration layer over it.
- The v1 file/document model should remain a one-shot worker snapshot with explicit reopen-on-change behavior at the hub level.
- The v1 public protocol should remain Lean-centric; lower-layer integration should happen mainly through enriched hover/infoview behavior rather than through new first-class lower-layer RPC methods.
- Main-worktree compatibility should be strong at the method-family and response-shape level where it materially benefits higher-layer migration, while still allowing explicit improvements such as a dedicated stale-node error.

## Remaining design work before implementation

The major architectural questions that were still open in the overview phase are now settled in the component plans under `plans/server/`.
That means implementation can begin against explicit design decisions rather than against open-ended alternatives.

The remaining design work before implementation is comparatively narrow:

- keep `plans/server.md` and the component docs aligned if implementation reveals a better module split or helper naming
- add a diagnostics/progress design document later only if the implementation moves beyond the settled reopen-on-change model toward Lean-core-style incremental documents
- refine any structured hover payload ideas only if higher-layer consumers prove they need more than the current plain-text enriched hover contract

In other words, the next step is no longer to decide the main architecture; it is to implement the settled architecture and update the docs honestly if experience forces a deliberate revision.

## Detailed phased implementation plan

Implementation should proceed bottom-up from shared protocol/types and lifecycle logic to file-worker semantics and only then to lower-layer integration.
The key sequencing rules should be:

- code should land in buildable increments rather than one giant merge of hub, worker, and tests
- protocol and lifecycle invariants should be coded before broad semantic handler coverage
- transport/process concerns should remain separate from Lean semantic logic
- the worker’s Lean query behavior should be implemented before richer lower-layer integration
- each phase should add the tests that make the new behavior safe to build on in the next phase
- if implementation experience forces a real design change, the relevant component doc should be updated before the next phase proceeds

The phase breakdown below is intentionally more concrete than the component docs.
Its job is to describe the implementation order, not just the final architecture.

### Phase 0 — establish the module skeleton, executables, and test tree

Purpose:

- create the structural homes this layer will use
- keep implementation from accreting ad hoc in one or two giant files
- make room for process-level testing from the beginning

Primary component docs:

- `plans/server/layout.md`
- `plans/server/testing.md`

Concrete deliverables:

- add library roots and submodules matching the settled layout, including:
  - `AFTK/Server.lean`
  - `AFTK/Server/Protocol.lean`
  - `AFTK/Server/Transport.lean`
  - `AFTK/Server/Hub.lean`
  - `AFTK/Server/Main.lean`
  - `AFTK/FileWorker.lean`
  - `AFTK/FileWorker/Context.lean`
  - `AFTK/FileWorker/Queries.lean`
  - `AFTK/FileWorker/TacticState.lean`
  - `AFTK/FileWorker/Informal.lean`
  - `AFTK/FileWorker/Handlers.lean`
  - `AFTK/FileWorker/Main.lean`
- add `aftk_server` and `aftk_file_worker` targets to `lakefile.toml`
- add the server test tree under `AFTKTest/Server/`
- add checked-in fixture directories under `tests/server/fixtures/` and `tests/server/golden/`
- update `AFTK.lean` and `AFTKTest.Main` when the new modules are ready to participate in the normal build/test flow

Recommended order inside the phase:

1. add the directory/module skeleton and minimal imports
2. add executable targets and make sure the project still builds
3. add `AFTKTest/Server/*` placeholders and fixture directories
4. wire the empty or skeletal server suite into `aftk_test`

Minimum tests before moving on:

- the project still builds with the new module tree present
- `lake test` still runs the existing suites and includes the new server-suite entrypoint, even if that suite is still mostly skeletal

Exit criteria:

- the project builds with skeletal server/file-worker modules in place
- executable targets exist, even if many handlers are still stubs
- the project has a dedicated place for server-layer tests and fixtures

### Phase 1 — define shared protocol types and the `lean_worker` transport layer

Purpose:

- stabilize the machine-facing contract before semantic logic spreads through the implementation
- centralize the `lean_worker` dependency before hub and worker code start calling it ad hoc

Primary component docs:

- `plans/server/protocol.md`
- `plans/server/transport.md`
- `plans/server/layout.md`

Concrete deliverables:

- declare the `lean_worker` dependency in `lakefile.toml`
- implement `AFTK.Server.Protocol` with:
  - shared request/response structures for the settled public and worker-internal method families
  - shared position/range/result types
  - AFTK-specific error-code constants/helpers
  - JSON codec instances for the settled shapes
- implement `AFTK.Server.Transport` with:
  - wrappers around the needed `lean_worker` client/server transport constructors
  - shared object-param helpers
  - shared result-decoding helpers
  - bounded child-stop helpers for graceful shutdown plus forced-kill fallback
- encode the already settled v1 transport/protocol choices explicitly in code:
  - newline-delimited JSON-RPC over stdio
  - object-shaped params only
  - no general public batch arrays
  - explicit `shutdown` request types on both hub and worker boundaries

Recommended order inside the phase:

1. add the shared protocol structures and codecs first
2. add error helpers and common JSON/object-param utilities
3. add `lean_worker`-based server/client transport wrappers
4. add child-stop/shutdown helpers
5. add protocol and transport unit tests before wiring nontrivial hub or worker logic

Minimum tests before moving on:

- protocol codec tests for representative request/response types
- tests covering the stable AFTK-specific error family
- direct tests for the small transport helpers that do not require full hub/worker semantics

Exit criteria:

- the core method family has shared types and codecs
- error codes and major protocol invariants are explicit in code
- `lean_worker` usage is centralized behind `AFTK.Server.Transport`
- explicit public and internal `shutdown` request types exist in the shared protocol

### Phase 2 — implement hub lifecycle and worker-session management

Purpose:

- land the operational heart of the hub before the worker grows complex
- make file identity, liveness, freshness, and cleanup rules executable rather than merely documented

Primary component docs:

- `plans/server/hub.md`
- `plans/server/transport.md`
- `plans/server/layout.md`

Concrete deliverables:

- implement hub-side file identity types and helpers, including:
  - normalized absolute path handling
  - canonical path handling when available
  - alias lookup from normalized path to canonical session identity
- implement file-stamp reading with modification time plus byte size
- implement worker spawn helpers using the settled process form:
  - `lake exe aftk_file_worker <path>`
- implement worker stop helpers using:
  - worker `shutdown`
  - bounded wait
  - `SIGTERM`
  - `SIGKILL` fallback
- implement session registry state with one session per open file
- implement per-session serialization primitives
- implement the public lifecycle methods:
  - `open`
  - `close`
  - `shutdown`
- implement generic hub forwarding helpers that perform:
  - path lookup
  - session lock acquisition
  - worker liveness check
  - file-freshness check
  - cleanup on dead-worker forwarding failure

Recommended order inside the phase:

1. implement file identity and file-stamp helpers
2. implement worker spawn/stop/drain helpers
3. implement the hub state and session registry
4. implement `open`, `close`, and `shutdown`
5. implement generic forwarding helpers for later semantic methods
6. add a final cleanup path in `AFTK.Server.Main`

Minimum tests before moving on:

- unit tests for path normalization/canonicalization behavior
- unit tests for file-stamp freshness checks
- lifecycle tests for `open`, `close`, and `shutdown`
- tests that dead or stale sessions are cleaned up deterministically

Exit criteria:

- the hub can manage per-file worker sessions reliably
- worker lifecycle is explicit and testable
- file-changed and worker-unavailable invalidation behavior exists at the hub boundary
- per-session serialization exists before tactic/node semantics are layered on top

### Phase 3 — implement the one-shot file-worker semantic query core

Purpose:

- reproduce the main useful Lean semantic query behavior before tactic exploration and richer integration
- implement the already settled v1 one-shot worker model rather than reopening the document-model question

Primary component docs:

- `plans/server/worker.md`
- `plans/server/lean-integration.md`
- `plans/server/protocol.md`

Concrete deliverables:

- implement `AFTK.FileWorker.Context` for one-shot startup elaboration from a file path using:
  - `Parser.parseHeader`
  - `processHeader`
  - command processing with `infoState.enabled := true`
- implement command-tree capture and position-conversion helpers
- implement query helpers for:
  - command selection by source position
  - parser-doc fallback
  - Lean hover lookup
  - plain-goal lookup
  - term-goal lookup
  - infoview aggregation
- implement worker handlers for:
  - `get_hover`
  - `get_plain_goal`
  - `get_plain_term_goal`
  - `get_infoview`
  - `load_node`
  - internal `shutdown`
- make the `load_node` semantic choice explicit in code and tests, especially regarding before-state versus any possible `useAfter`-aware loading

Recommended order inside the phase:

1. implement one-shot context construction and command-tree extraction
2. implement position conversion plus command filtering helpers
3. implement `get_hover` and `get_plain_term_goal`
4. implement `get_plain_goal` and `get_infoview`
5. implement `load_node`
6. wire the worker handler registry and real worker main loop
7. add direct worker tests and first end-to-end open/query/close process tests

Minimum tests before moving on:

- direct worker tests over real fixture files for hover, plain goal, term goal, and infoview
- tests that malformed `line`/`col` values fail as invalid params
- tests that `load_node` returns stable structured results on fixture files
- at least one subprocess smoke test that opens a file through the hub and executes a read-only semantic query successfully

Exit criteria:

- the worker can answer the core source-position queries over real Lean fixture files
- position semantics are stable and tested
- `load_node` can create initial transient proof-state handles
- the worker exposes an internal `shutdown` handler and cleanly exits under hub control

### Phase 4 — implement transient tactic exploration

Purpose:

- add the proof-search behavior that distinguishes the file worker from a read-only semantic query service
- finish the transient node semantics that higher layers rely on for exploration

Primary component docs:

- `plans/server/worker.md`
- `plans/server/protocol.md`
- `plans/server/hub.md`
- `plans/server/testing.md`

Concrete deliverables:

- implement `AFTK.FileWorker.TacticState` with:
  - node-id allocation
  - stored-node map/state
  - state capture from goal info
  - stale-node handling
- implement worker-side:
  - `get_goals`
  - `run_tactic`
- ensure `get_goals` inspects a stored node without allocating hidden fresh nodes
- implement tactic parsing against the stored node environment using the Lean `tactic` parser category
- implement the hub-side `run_tactic_steps` orchestration loop as sequential repeated worker `run_tactic` calls under the same session lock
- emit the settled error distinctions:
  - `-32001` tactic failed
  - `-32013` stale or unknown node id

Recommended order inside the phase:

1. implement the node store and capture-from-goal logic used by `load_node`
2. implement `get_goals`
3. implement `run_tactic`
4. add stale-node and tactic-failure error mapping
5. implement hub-side `run_tactic_steps`
6. add branching and multi-step regression tests

Minimum tests before moving on:

- direct worker tests for `get_goals` and `run_tactic`
- tests that tactic parse failure and tactic execution failure are distinguished
- tests that stale node ids yield `-32013`
- end-to-end tests for `load_node` -> `get_goals` -> `run_tactic`
- end-to-end tests for `run_tactic_steps`

Exit criteria:

- tactic exploration behavior reaches earlier-implementation parity in spirit
- transient node ids are allocated, chained, and invalidated correctly
- `run_tactic_steps` exists at the hub layer rather than as a worker primitive
- failure behavior is explicit and test-covered

### Phase 5 — integrate the knowledge-base and informal layers

Purpose:

- make this layer aware of AFTK's lower layers rather than stopping at Lean-only parity
- land the worker-side hover enrichment that is specific to AFTK architecture

Primary component docs:

- `plans/server/integration.md`
- `plans/server/worker.md`
- `plans/server/testing.md`

Concrete deliverables:

- implement `AFTK.FileWorker.Informal`
- detect recognized `informal[...]` syntax at queried sites
- validate and resolve references through existing informal-layer APIs
- honor the existing lower-layer root option `aftk.informal.root`
- render richer hover text with the settled preview-oriented presentation path
- apply the precedence rule that successful rich informal hover replaces generic hover at recognized `informal[...]` sites
- keep `get_infoview` aligned with the same hover policy
- avoid introducing new first-class lower-layer RPC methods in v1 unless a later design revision explicitly changes that plan
- avoid introducing snapshot-independent caches as a hidden second source of truth

Recommended order inside the phase:

1. add syntax-site detection and raw-reference recovery
2. reuse `informalReferenceOfString?` and `resolveInformalReference`
3. render rich preview text through `AFTK.Informal.Presentation`
4. integrate the result into hover precedence and infoview behavior
5. add integration tests over real `informal[...]` fixture files and knowledge-base roots
6. only consider worker-local caching after the uncached path works and is tested

Minimum tests before moving on:

- tests that ordinary Lean hover still works on non-informal sites
- tests that compact informal summary behavior still appears at `informal[...]` sites
- tests that recognized `informal[...]` sites can produce the richer preview-style hover
- tests that rich-hover resolution failure falls back to ordinary Lean hover rather than failing the request

Exit criteria:

- the server/file-worker layer is genuinely integrated with the lower layers
- hover and infoview can surface lower-layer-aware information when appropriate
- no second content store or duplicated bridge state has been introduced

### Phase 6 — harden lifecycle behavior, process tests, and higher-layer readiness

Purpose:

- make the first implementation reliable enough for the toolkit layer to build on
- turn the architectural guarantees in the design docs into tested operational guarantees

Primary component docs:

- `plans/server/testing.md`
- `plans/server/transport.md`
- `plans/server/hub.md`
- `plans/server/protocol.md`

Concrete deliverables:

- add a reusable subprocess JSON-RPC test client/helper for the server suite
- add end-to-end tests for:
  - repeated `open` reuse behavior
  - `close` on open and unopened files
  - `shutdown` with zero and nonzero session counts
  - malformed envelopes and unknown methods
  - invalid params such as `line = 0` / `col = 0`
  - file-change invalidation returning `-32011`
  - worker-unavailable behavior returning `-32012`
  - stale-node behavior after reopen/restart
  - public JSON shape stability for representative success and failure responses
- verify graceful shutdown and forced-kill fallback behavior
- clean up any remaining public-boundary determinism problems in error text, response shape, or lifecycle handling
- document any compatibility assumptions that the TypeScript wrapper or higher layers will rely on

Recommended order inside the phase:

1. finish the reusable subprocess harness
2. add end-to-end success-path tests
3. add negative and invalidation-path tests
4. add worker-unavailable and forced-shutdown-path tests
5. tighten any remaining protocol or lifecycle inconsistencies found by the tests

Minimum tests before moving on:

- the server suite covers protocol, worker, hub, integration, and full subprocess behavior
- file-change invalidation and worker-unavailable cases are explicitly covered
- the aggregate `aftk_test` run stays green with the server suite enabled

Exit criteria:

- the server/file-worker layer has realistic process-level test coverage
- the protocol and failure behavior are stable enough for higher-layer consumption
- the implementation satisfies the top-level completion checklist below, except for any intentionally deferred optional work

### Phase 7 — optional richer editing support if v1 intentionally stays reopen-on-change

Purpose:

- keep a clear place for future improvement without confusing it with the required v1 work

Primary component docs:

- `plans/server/lean-integration.md`
- `plans/server/transport.md`
- any future diagnostics/progress addendum if one is written later

Concrete deliverables if this phase is ever pursued:

- revisit the worker backend boundary and verify it is sufficient for an incremental implementation
- study Lean-core-style snapshot waiting patterns and editable-document backends
- add cancellation and diagnostics/progress only if there is a concrete higher-layer need
- extend the protocol only when the added behavior clearly justifies the compatibility cost

Important non-goal for v1:

- this phase is explicitly optional and must not block completion of the first usable current implementation described in Phases 0–6

Exit criteria:

- either the richer editing model is implemented,
- or it remains explicitly deferred with the boundary clearly preserved for future work

## Completion checklist for this plan

The server/file-worker layer overview in this file should count as implemented only when all of the following are true in the current repository:

- reusable `AFTK.Server` and `AFTK.FileWorker` module trees exist with the structure settled in `plans/server/layout.md`
- executable targets exist for the server and file worker, or a deliberately settled equivalent compatibility surface exists
- the hub manages per-file worker sessions and supports open/close/shutdown lifecycle operations
- the Lean-facing semantic query surface exists and is tested
- transient tactic exploration exists and is tested
- invalidation behavior for changed files, dead workers, and stale node ids is explicit and tested
- lower-layer integration with the knowledge-base and informal layers exists where the component docs specify it should
- `lake test` runs a server-layer test suite alongside the existing lower-layer suites

Until then, the implementation status at the top of this file should remain “Not implemented” or be updated only to reflect partial completion honestly.

## Summary

The server and file-worker layer is AFTK's operational service layer.
It should preserve the useful current architecture of a hub process plus per-file workers, preserve the core Lean-facing query and tactic-exploration surface from the earlier implementation, and integrate that surface with AFTK's knowledge-base and informal layers.

The main design tension identified by the research is clear:

- the earlier implementation offers a small, useful, reopen-on-change model,
- while Lean core offers a richer snapshot-based editable-document architecture.

The next step is therefore to implement against the component design docs now living under `plans/server/`, especially the transport, protocol, hub, worker, and Lean-integration designs, so that code lands from explicit decisions rather than from accidental drift.
