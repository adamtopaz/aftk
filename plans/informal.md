# Informal Layer Plan

## Status

Overall plan for the second layer of the `aftk` rewrite.
This document is intentionally architectural and serves as the top-level plan for the informal layer.
Detailed subdesigns should live in component plan files under `plans/informal/`.

## Plan implementation status

- Overall status: Not implemented
- Fully implemented: No
- Last updated basis: rewrite worktree currently has no dedicated informal-layer code; this plan is based on the overall rewrite architecture in `plan.md` and on the current main-worktree `Informalize` implementation in `/home/dev/aftk`

This section is the single place for tracking whether the informal layer plan has been fully implemented.
It should be updated whenever the implementation meaningfully changes.

A practical definition of fully implemented for this plan is:

- `informal[...]` elaboration exists in the rewrite worktree
- bracketed informal references resolve through the knowledge-base layer rather than a separate `informal/` sidecar store
- occurrence tracking and query APIs exist for Lean declarations that use `informal[...]`
- the layer exposes an initial `lake exe aftk informal ...` CLI surface
- the layer provides Lean-facing presentation support for referenced knowledge-base content
- the library and CLI behavior are covered by appropriate tests

## Purpose

The informal layer sits directly on top of the knowledge base.
Its job is to connect natural-language knowledge-base nodes to Lean declarations, proofs, and metaprogramming workflows.

The most important architectural commitment of this layer is:

> The knowledge base remains the single source of truth for natural-language content.

The informal layer therefore should not introduce a second natural-language storage model.
It should instead provide the Lean-side machinery for:

- referring to knowledge-base nodes from Lean,
- elaborating placeholders such as `informal[...]`,
- tracking where those placeholders occur,
- surfacing the linked informal content inside Lean tooling,
- and exposing query/tooling support around those links.

## Position in the layered architecture

The overall rewrite stack is:

1. Knowledge base layer
2. Informal layer
3. Server and file-worker layer
4. Toolkit layer
5. AI autoformalization agent layer

The informal layer is the first layer above the knowledge base.
It depends on stable knowledge-base node identities and knowledge-base read/query operations.
Higher layers should rely on the informal layer for Lean-facing informal/formal bridging rather than reimplementing that logic themselves.

## Relationship to the main-branch worktree

The current main-branch worktree at `/home/dev/aftk` contains the reference implementation we should study before writing the rewrite.
The most relevant existing files are:

- `/home/dev/aftk/Informalize/Elaborator.lean`
- `/home/dev/aftk/Informalize/Axiom.lean`
- `/home/dev/aftk/Informalize/Extension.lean`
- `/home/dev/aftk/Informalize/Location.lean`
- `/home/dev/aftk/Informalize/Metadata.lean`
- `/home/dev/aftk/Informalize/Cli.lean`
- `/home/dev/aftk/docs/informalize/README.md`
- `/home/dev/aftk/docs/informalize/IdReference.md`

That implementation currently provides several behaviors worth preserving in spirit:

- bracketed `informal[...]` surface syntax
- typed placeholder elaboration using an unsound axiom plus unique tags
- declaration-level occurrence tracking via a persistent environment extension
- derived declaration and location dependency queries
- hover/info support that surfaces linked informal content in Lean tooling
- a CLI for querying tracked occurrences and related bridge state

However, the rewrite must deliberately change one major aspect of the design:

- the main worktree stores informal prose and metadata under `informal/.../*.md` and `informal/.../*.json`
- the rewrite must not reintroduce that duplicated storage model
- bracketed informal references should instead resolve through `AFTK.KnowledgeBase` node ids and canonical knowledge-base storage

In other words, the rewrite should borrow the useful elaboration/tracking/tooling ideas from `Informalize`, while replacing its sidecar-backed content store with knowledge-base-backed resolution.

## Core responsibilities

The informal layer should eventually provide the following capabilities:

- elaborate `informal[...]` in Lean
- resolve bracketed references against knowledge-base nodes
- support typed placeholders during gradual formalization
- track declaration-level use of informal placeholders
- expose library APIs for querying tracked declarations and linked nodes
- derive declaration-level and directly projected node-level dependency views useful for scaffold inspection and higher-layer tooling
- surface linked informal content inside Lean editor/tooling experiences
- expose these capabilities through a Lean-native CLI

## Architectural commitments

### 1. Knowledge-base-backed references only

A bracketed informal reference such as:

```text
informal[a.b.c]
```

should resolve through the knowledge-base layer.
The informal layer should not define a second canonical mapping from ids to markdown/json sidecars.

### 2. Preserve the placeholder-driven Lean workflow

The current main-worktree `Informalize` system is useful because `informal[...]` behaves like a typed Lean term that can stand in for unfinished proofs or definitions.
The rewrite should preserve that workflow shape, even if the internal implementation details evolve.

### 3. Keep bridge-specific state separate from natural-language content

The knowledge base owns natural-language content and its canonical metadata.
If the informal layer needs additional state, it should be clearly limited to bridge-specific concerns such as:

- occurrence tracking
- declaration-to-node associations
- derived dependency/index data
- Lean-facing presentation support

The informal layer should not become a second content store.

### 4. Make occurrence and dependency information queryable

The main-worktree implementation is valuable not only because elaboration succeeds, but also because later tooling can ask:

- which declarations contain `informal`
- which knowledge-base nodes they reference
- what tracked declarations depend on which others
- what node-to-node views can be derived from those declaration dependencies

The rewrite should preserve that queryability.

### 5. Keep the reusable library separate from the CLI

As with the knowledge-base layer, the main informal-layer logic should live in reusable library modules.
The CLI should be a thin wrapper over those library APIs.

## Conceptual model

At a high level, the informal layer revolves around a small set of concepts:

- an **informal reference** appearing in Lean syntax
- a **resolved knowledge-base node** that the reference points to
- a **typed placeholder term** used during gradual formalization
- an **occurrence record** connecting a Lean declaration to one or more references
- a **derived dependency view** over tracked declarations and referenced nodes
- a **Lean-facing presentation layer** for rendering linked informal content in hover/info contexts

The exact concrete types should be refined in the component plans below.
The important point is that the informal layer is fundamentally a bridge between:

- Lean declarations and proofs on one side, and
- knowledge-base nodes on the other.

## Component plans

The following component plans should live under `plans/informal/`.
These are the main design documents currently needed for this layer.

- `plans/informal/elaboration.md` — surface syntax, supported forms, elaboration contexts, expected-type behavior, argument handling, unique-tag generation, placeholder construction, and user-facing error behavior for `informal[...]`
- `plans/informal/references.md` — the reference/id model for bracketed informal references, validation rules, how references resolve through the knowledge-base library, and how this replaces the main-worktree `LocationId` + sidecar-path scheme
- `plans/informal/placeholder.md` — the core placeholder mechanism (axiom or equivalent), distinctness requirements, soundness boundary, reduction/unification expectations, and future replacement/removal assumptions
- `plans/informal/tracking.md` — persistent environment extension design, occurrence deduplication rules, import/merge behavior, declaration-level query APIs, and any derived in-memory/indexed representations needed by later tooling
- `plans/informal/dependencies.md` — declaration-dependency semantics, node-dependency projection semantics, leaf/frontier-oriented derived views, determinism rules, and boundaries between informal-layer dependency analysis and higher-layer scaffold orchestration
- `plans/informal/presentation.md` — how knowledge-base content should be surfaced inside Lean tooling, including hover/info-tree rendering, summary formatting, lazy-vs-eager loading choices, and what context should appear at an `informal[...]` site
- `plans/informal/bridge-state.md` — what state belongs in the informal layer versus the knowledge base, including declaration↔node linkage data, any bridge-local caches/indexes, and explicit non-duplication rules for metadata/workflow state
- `plans/informal/cli.md` — the `lake exe aftk informal ...` command structure, command families, module-loading model, JSON/text output design, mutation/query behavior, and error/exit-code policy
- `plans/informal/layout.md` — Lean module and namespace layout, dependency boundaries between the knowledge-base library and the informal layer, and the split between reusable library code, CLI code, and tests
- `plans/informal/testing.md` — unit/integration/fixture strategy for elaboration, reference resolution, tracking, dependency queries, CLI behavior, and knowledge-base-backed presentation flows

Likely future component plans include:

- none currently identified beyond the component docs listed above

## Relationship to adjacent layers

### Knowledge base layer

The informal layer depends directly on the knowledge base.
It should treat knowledge-base node ids, storage, validation, and query APIs as foundational rather than rebuilding them.

### Server and file-worker layer

The server and file-worker layer should build on the informal layer’s library/CLI APIs when it needs Lean-aware access to knowledge-base-backed informal references.

### Toolkit and AI layers

Higher layers should be able to ask informal-layer questions through stable interfaces such as:

- which declarations reference which nodes
- what linked informal content should be shown for a placeholder site
- what dependency views are currently derived from tracked declarations

## Boundaries and non-goals

The informal layer is an important bridge, but it still has a limited scope.

### In scope

- Lean syntax and elaboration behavior for informal placeholders
- knowledge-base-backed informal reference resolution
- occurrence tracking and dependency derivation
- Lean-facing presentation of linked informal content
- an informal-layer CLI for query/tooling support

### Out of scope for this layer

- canonical natural-language storage itself
- source ingestion or source-packet management
- knowledge extraction logic
- server orchestration protocols
- TypeScript toolkit abstractions
- AI-agent control-loop logic
- full scaffold orchestration above declaration/node dependency derivation

Those belong to other layers.

## Design constraints

As the component plans are written, the informal layer should preserve the following constraints:

- preserve the central `informal[...]` bridge concept
- avoid duplicating knowledge-base content or metadata
- keep the knowledge-base dependency one-directional
- make placeholder behavior explicit and testable
- make derived occurrence/dependency views deterministic
- keep user-facing Lean behavior understandable for humans and automation alike
- provide a CLI surface suitable for both interactive use and machine consumption

## Design clarifications resolved so far

The following initial design questions are now considered settled for this layer overview:

- Bare `informal` support should be removed; the informal layer should center on bracketed `informal[...]` references only.
- Bracketed references should support the full knowledge-base node-id grammar directly rather than being restricted to Lean `ident` syntax.
- The informal layer should not define its own metadata model for informal content; it should use the metadata already provided by the knowledge base.
- Occurrence tracking exposed by the informal layer should remain declaration-level rather than introducing a per-site public tracking surface.
- Elaboration should load only the minimum linked knowledge-base information needed to validate the reference and attach a compact presentation summary; richer body/content rendering should be deferred to hover/query time.
- The informal layer should own declaration-level dependency analysis and direct projections from declaration dependencies to referenced-node dependencies, while frontier computation, readiness classification, prioritization, and broader scaffold orchestration should remain higher-layer responsibilities.

## Detailed implementation plan

The component plan suite under `plans/informal/` is now in place.
So the main remaining task is not architectural discovery, but disciplined implementation sequencing.
The informal layer should be built in a phased way that follows the dependency structure settled in the component docs and matches the current rewrite codebase, which already has:

- the `AFTK.KnowledgeBase` library,
- a working knowledge-base CLI split under `AFTK/KnowledgeBase/Cli/*`,
- a project-local test harness under `AFTKTest/KnowledgeBase/*`,
- and a thin top-level `Main.lean` dispatcher.

The implementation plan below is intended to be the execution order for the first complete informal-layer landing.

### Phase 0 — project scaffolding and integration points

Before implementing behavior, add the structural homes the rest of the work will use.

#### Files/modules to add

- `AFTK/Informal.lean`
- `AFTK/Informal/Syntax.lean`
- `AFTK/Informal/Placeholder.lean`
- `AFTK/Informal/References.lean`
- `AFTK/Informal/Tracking.lean`
- `AFTK/Informal/Dependencies.lean`
- `AFTK/Informal/Presentation.lean`
- `AFTK/Informal/Elaborator.lean`
- `AFTK/Informal/Cli/Types.lean`
- `AFTK/Informal/Cli/Parse.lean`
- `AFTK/Informal/Cli/Render.lean`
- `AFTK/Informal/Cli/Main.lean`
- `AFTKTest/Informal.lean`
- `AFTKTest/Informal/Main.lean`
- `AFTKTest/Informal/Assert.lean`
- `AFTKTest/Informal/Fixtures.lean`

#### Existing files to update

- `AFTK.lean` — re-export `AFTK.Informal` once the public library root exists
- `Main.lean` — add top-level dispatch for `lake exe aftk informal ...` once the CLI exists
- `AFTKTest.lean` and/or the package test-driver main — aggregate the informal suite alongside the knowledge-base suite
- `lakefile.toml` — point the test driver at an aggregate `AFTKTest` main once both suites exist

#### Phase-0 deliverable

The codebase should build with empty or skeletal `AFTK.Informal.*` modules in place, and the public module tree should match `plans/informal/layout.md` before substantial behavior is added.

### Phase 1 — implement the bottom-of-stack library pieces

This phase should land the smallest reusable pieces first, with no elaborator or CLI logic yet.

#### 1. Placeholder primitive

Implement `AFTK/Informal/Placeholder.lean` following `plans/informal/placeholder.md`:

- define `axiom AFTK.Informal.Informal.{u} (tag : Lean.Name) (α : Sort u) : α`
- keep the module dependency-light
- add basic tests for universe polymorphism and non-reduction expectations where practical

#### 2. Reference model and resolution helpers

Implement `AFTK/Informal/References.lean` following `plans/informal/references.md`:

- define `InformalReference`
- define `ResolvedInformalReference`
- add validation helpers from raw bracket text via `AFTK.KnowledgeBase.NodeId.ofString?`
- add exact-match resolution helpers using:
  - `AFTK.KnowledgeBase.PathLayout.resolveRootPath`
  - `AFTK.KnowledgeBase.Storage.resolveInitializedRoot`
  - `AFTK.KnowledgeBase.Storage.loadStoredNode`
- keep the reference object root-independent
- make string/ordering/JSON behavior delegate to the underlying `NodeId`

#### 3. Syntax surface

Implement `AFTK/Informal/Syntax.lean` following `plans/informal/elaboration.md` and `plans/informal/references.md`:

- declare the dedicated `informalNodeId` syntax category
- define bracketed `informal[...]` term syntax only
- do not add bare `informal`
- keep syntax extraction helpers small and reusable

#### 4. Early unit tests

Add the first test modules under `AFTKTest/Informal/` for:

- valid and invalid node-id parsing
- one-segment node-id acceptance
- exact-match reference resolution against fixture knowledge-base roots
- placeholder-level invariants that can be tested without the elaborator

#### Phase-1 deliverable

At the end of this phase, the informal layer should have a reusable validated reference type, exact knowledge-base-backed resolution helpers, the dedicated placeholder primitive, and the bracketed syntax declaration.
Nothing in this phase should read from or recreate an `informal/` sidecar model.

### Phase 2 — implement compact presentation and tracking foundations

This phase should build the reusable derived-view pieces that elaboration will consume.

#### 1. Presentation summary core

Implement the compact presentation path in `AFTK/Informal/Presentation.lean` following `plans/informal/presentation.md`:

- define `InformalPresentationSummary`
- define richer payload types such as `InformalBodyPresentation` and `InformalPresentationPayload`
- implement compact-summary builders from `ResolvedInformalReference`
- implement deterministic text renderers for:
  - compact summary text
  - richer payload text with preview/full-body policy
- derive summary fields from `NodeMetadata` using existing knowledge-base accessors such as `titleOrId`, `kind`, `status`, and `summary?`

The compact summary builder should be ready before the elaborator lands, so the elaborator can attach useful hover info immediately.

#### 2. Tracking extension

Implement `AFTK/Informal/Tracking.lean` following `plans/informal/tracking.md`:

- define `InformalOccurrence`
- define the declaration-keyed aggregated state
- register a `SimplePersistentEnvExtension`
- add declaration-centric queries:
  - `allInformalDeclEntries`
  - `informalDeclEntry?`
- add reverse reference-centric queries:
  - `allInformalReferenceEntries`
  - `informalReferenceEntry?`
- keep persistent state limited to declaration↔reference linkage
- derive reverse lookup on demand in v1
- sort all public outputs deterministically

#### 3. Tracking tests

Add direct tests for:

- aggregation by declaration
- deduplication of repeated references within a declaration
- imported-state union behavior
- deterministic ordering
- absence of empty tracked declaration rows

#### Phase-2 deliverable

At the end of this phase, the project should have the reusable pieces needed for elaboration to record successful bridge occurrences and attach compact presentation summaries without yet having the elaborator itself.

### Phase 3 — implement the term elaborator

This phase is the first user-visible Lean integration milestone.
It should follow `plans/informal/elaboration.md` closely and reuse the already-landed reference, placeholder, tracking, and presentation modules.

#### 1. Elaborator behavior

Implement `AFTK/Informal/Elaborator.lean` with the following pipeline:

1. accept only bracketed `informal[...]` syntax
2. recover the enclosing declaration name with `Term.getDeclName?`
3. reject pseudo-declaration contexts such as `_check`, `_reduce`, `_synth_cmd`, and similar command-generated names
4. parse and validate the bracket payload as a knowledge-base node id
5. resolve it through the knowledge-base layer
6. elaborate written term arguments normally with `elabTerm arg none`
7. determine the placeholder result type from the expected type or a fresh type metavariable
8. build the curried placeholder type with `mkForall`
9. generate a site-unique tag using source-location information in the style of `SorryLabelView.encode`
10. construct the placeholder term `AFTK.Informal.Informal tag α` and apply explicit arguments
11. attach compact presentation info to the info tree
12. record the successful occurrence in the tracking extension
13. synthesize/instantiate metavariables before returning

#### 2. Important implementation rules

- Do not support bare `informal`.
- Do not treat the bracket payload as `Lean.Name` or `ident` semantically.
- Do not infer Lean result types from node metadata or body text.
- Do not attach full node bodies eagerly during elaboration.
- Do not record partial tracking state on failed elaboration.
- Do not inspect or scan source files to reconstruct tracking; tracking must come from successful elaboration.

#### 3. Root/context plumbing rule

The elaborator must resolve references through the knowledge-base library without inventing a second informal-specific root scheme.
In implementation terms, that means:

- the reusable resolver APIs should accept explicit root/context input when called directly,
- the elaborator should use the same knowledge-base root policy as the rest of the rewrite by default,
- and tests should be able to run elaboration against fixture roots without mutating the repository’s canonical knowledge base.

If a small shared bridge-context helper becomes necessary to keep this clean, add it as an implementation convenience without changing the ownership boundary described in `plans/informal/bridge-state.md`.

#### 4. Elaboration tests

Add the first real Lean fixture modules under `AFTKTest/Informal/Fixtures/` covering:

- one declaration with one `informal[...]`
- one declaration with repeated identical references
- one declaration with multiple distinct references
- proof-context usage
- invalid-context failure via subprocess tests
- malformed node-id failure via subprocess tests
- missing-node failure via subprocess tests
- malformed-node failure via subprocess tests

Also add a light hover/info smoke test path once the elaborator can attach compact summaries.

#### Phase-3 deliverable

At the end of this phase, users should be able to write `informal[node.id]` in declaration values and proofs, have it elaborate to a typed placeholder, get compact hover/info support, and query declaration-level tracking data from imported modules.
This is the minimum viable informal library milestone.

### Phase 4 — implement derived dependency analysis

Once tracking exists, add `AFTK/Informal/Dependencies.lean` following `plans/informal/dependencies.md`.

#### 1. Declaration dependency view

Implement:

- `InformalDeclDependencyEntry`
- `allInformalDeclDependencyEntries`
- `informalDeclDependencyEntry?`
- `informalDeclDependencyLeaves`

using Lean declaration-usage traversal based on `ConstantInfo.getUsedConstantsAsSet` or the equivalent current Lean API.
The traversal should:

- recurse transitively,
- continue through untracked intermediates,
- collect only tracked declarations in final results,
- remove self-dependencies,
- and use a visited set for cycle safety.

#### 2. Reference dependency view

Implement:

- `InformalReferenceDependencyEntry`
- `allInformalReferenceDependencyEntries`
- `informalReferenceDependencyEntry?`
- `informalReferenceDependencyLeaves`

by projecting declaration dependencies through declaration→reference tracking data.
This should remain a declaration-level projection, not a second canonical graph or a knowledge-base relationship graph.

#### 3. Dependency tests

Add fixture modules with tracked declarations, untracked helpers, and imports so the suite can verify:

- transitive tracked-declaration reachability through untracked declarations
- cycle-safe traversal
- projected reference dependencies
- deterministic ordering
- leaf computation
- empty-state behavior

#### Phase-4 deliverable

At the end of this phase, the informal library should expose deterministic declaration and reference dependency views derived from the Lean environment plus tracking state, with no persisted dependency graph beyond the environment extension’s declaration↔reference linkage.

### Phase 5 — implement the informal CLI

The CLI should be built only after the reusable library APIs above are in place.
Its structure should mirror the existing knowledge-base CLI split under `AFTK/KnowledgeBase/Cli/*`.

#### 1. CLI types and parsing

Implement:

- `AFTK/Informal/Cli/Types.lean`
- `AFTK/Informal/Cli/Parse.lean`

with support for the v1 command surface from `plans/informal/cli.md`:

- `status`
- `decls`
- `decl <Decl.Name>`
- `refs`
- `ref <NodeId>`
- `deps`
- `present <NodeId>`

Global options should include at least:

- `--module <Module.Name>` (repeatable) for environment-backed commands
- `--root <path>` for knowledge-base-backed presentation
- `--format text|json`

#### 2. CLI rendering

Implement `AFTK/Informal/Cli/Render.lean` with:

- stable text renderers
- stable JSON envelopes
- stronger compatibility expectations for JSON than for text
- deterministic row ordering at output boundaries

#### 3. CLI main/dispatch

Implement `AFTK/Informal/Cli/Main.lean` with two execution paths:

- environment-backed commands that import requested modules with `loadExts := true`
- direct knowledge-base presentation commands that resolve references through the knowledge-base library

For environment-backed commands, reuse the same Lean CLI import setup pattern already used by the knowledge-base layer where applicable:

- `Lean.findSysroot`
- `Lean.initSearchPath`
- `Lean.enableInitializersExecution`
- `Lean.importModules ... (loadExts := true)`

Do not use `withImportModules` for tracked-state queries, because it disables extension loading.

#### 4. Top-level integration

Once `AFTK.Informal.Cli.Main` exists:

- update `Main.lean` to dispatch `informal`
- update help text to advertise both `knowledgebase` and `informal`
- keep `Main.lean` thin; do not move informal logic into the executable entrypoint

#### 5. CLI tests

Add end-to-end tests for:

- successful text and JSON output for each major command
- missing required `--module`
- invalid `--by`, `--mode`, or `--body` values
- targeted not-found failures for `decl` and `ref`
- invalid, missing, and malformed-node failures for `present`

#### Phase-5 deliverable

At the end of this phase, the rewrite should expose the first complete `lake exe aftk informal ...` CLI backed by reusable library APIs rather than ad hoc duplicated logic.

### Phase 6 — finalize the test tree and package-level integration

The final phase is to make the whole layer easy to maintain and safe to evolve.

#### 1. Complete the test layout

Finish the test tree described in `plans/informal/testing.md`:

- `AFTKTest/Informal/References.lean`
- `AFTKTest/Informal/Placeholder.lean`
- `AFTKTest/Informal/Tracking.lean`
- `AFTKTest/Informal/Dependencies.lean`
- `AFTKTest/Informal/Presentation.lean`
- `AFTKTest/Informal/Elaboration.lean`
- `AFTKTest/Informal/Cli.lean`
- filesystem fixtures under `tests/informal/knowledgebase-fixtures/`
- compile-fail fixtures under `tests/informal/compile-fail/`
- optional goldens under `tests/informal/golden/`

#### 2. Aggregate test driver

Update the package test driver so `lake test` runs both suites.
A reasonable shape is:

- `AFTKTest/Main.lean` as an aggregate runner
- `AFTKTest.lean` re-exporting both `AFTKTest.KnowledgeBase` and `AFTKTest.Informal`
- `lakefile.toml` pointing `testDriver` at the aggregate main

#### 3. Regression policy

From this point on, bugs in:

- parser acceptance/rejection,
- elaboration context handling,
- tracking determinism,
- dependency projection,
- presentation formatting,
- and CLI JSON shape

should get regression tests in the matching informal test module or fixture set.

#### Phase-6 deliverable

At the end of this phase, the informal layer should be fully integrated into the project’s ordinary `lake test` workflow with realistic fixture coverage across library, elaboration, subprocess failure, and CLI paths.

## Cross-cutting implementation rules

The phased plan above should be carried out under the following non-negotiable rules drawn from the component docs.

### 1. No second natural-language store

No phase should introduce:

- an `informal/` authored content directory,
- sidecar markdown/json lookup helpers on informal references,
- copied node-body snapshots in tracking state,
- or a second metadata/workflow schema owned by the informal layer.

### 2. Library-first, CLI-second

Every CLI command should be a thin consumer of reusable library APIs.
If a behavior is only implemented in `Cli/Main.lean`, that is a design smell and should usually be pushed down into `AFTK.Informal.*` first.

### 3. Declaration-level public semantics

Public tracking and dependency APIs should remain declaration-level in v1.
Per-site tags and source positions may exist internally for elaboration and hover, but they should not silently become the public query model.

### 4. Deterministic outputs everywhere

All public arrays and rendered rows should be explicitly sorted at API or rendering boundaries.
Do not rely on hash-map or hash-set iteration order.

### 5. Test each phase as it lands

Do not defer testing until the end.
Each phase above should land together with the direct tests and fixtures that protect its public behavior.

## Completion checklist for this plan

The informal layer overview in this file should count as implemented only when all of the following are true in the rewrite worktree:

- `AFTK/Informal/*` exists with the module structure described in `plans/informal/layout.md`
- bracketed `informal[...]` elaboration exists and bare `informal` does not
- bracketed references validate against `KnowledgeBase.NodeId` and resolve through `AFTK.KnowledgeBase`
- placeholders are implemented via the explicit `AFTK.Informal.Informal` axiom
- successful elaboration records declaration-level tracking entries through a persistent environment extension
- compact Lean-facing presentation is attached at `informal[...]` sites
- derived declaration and reference dependency queries exist
- `lake exe aftk informal ...` exposes the initial read-oriented CLI surface
- `Main.lean` dispatches both `knowledgebase` and `informal`
- `lake test` runs informal-layer tests alongside the existing knowledge-base suite

Until then, the implementation status at the top of this file should remain "Not implemented" or be updated only to reflect partial completion honestly.

## Summary

The informal layer is the Lean-facing bridge between the rewrite’s knowledge base and its formal Lean development.
It should preserve the useful parts of the current main-worktree `Informalize` design—typed placeholders, occurrence tracking, dependency queries, and Lean-facing presentation—while replacing the old sidecar-backed content store with direct knowledge-base integration.

The next step is to execute the phased implementation plan above, using the component design docs under `plans/informal/` as the detailed blueprint for each `AFTK/Informal/` module and its tests.
