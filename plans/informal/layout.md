# Informal Library Layout

## Status

Component plan and implementation-status document for the Lean library layout of the informal layer.
This document refines the overall informal-layer plan in `plans/informal.md` and complements the elaboration, references, placeholder, tracking, dependencies, presentation, CLI, and testing component plans.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: rewrite worktree currently has no `AFTK/Informal/*` module tree; this document is based on the current knowledge-base layout under `AFTK/KnowledgeBase/*`, the current top-level executable shape in `Main.lean`, and the informal-layer component plans already added under `plans/informal/`

## Purpose

This document describes how the informal layer should be laid out in the Lean source tree.
It is about **library/module structure**, not about the canonical storage layout of knowledge-base nodes.
That storage remains defined by the knowledge-base layer.

The goal is to make implementation start from a clear module tree rather than accumulating informal-layer logic ad hoc in:

- `Main.lean`
- one oversized `AFTK/Informal.lean` file
- or CLI code that mixes parsing, module loading, knowledge-base resolution, and rendering in one place

## Design goals

The informal-layer layout should:

- present a clear reusable import surface for the rest of the system
- separate reusable informal-layer logic from CLI-only concerns
- depend on the knowledge-base library without depending on the knowledge-base CLI
- keep dependency direction simple and acyclic
- reflect the actual component boundaries already defined in the design docs
- keep the placeholder primitive and syntax/elaboration machinery easy to find
- make testing and later server/file-worker integration straightforward
- avoid premature fragmentation while still keeping responsibilities clear

Lean module and namespace naming for this layer should use `Informal`, not `Informalize`.

## Scope and non-scope

### In scope

- Lean module and file layout under `AFTK/Informal/`
- the boundary between reusable informal-layer library code and executable/CLI code
- recommended dependency direction between informal-layer module groups
- the public import surface for the informal layer
- how the top-level `aftk` executable should dispatch to the informal CLI
- recommended test-module layout for the informal layer

### Out of scope

- the on-disk storage layout of knowledge-base nodes
- the exact `informal[...]` syntax and parser rules
- the exact CLI command surface
- the exact test cases and fixture contents

Those are covered respectively by:

- `plans/knowledgebase/storage.md`
- `plans/informal/elaboration.md` and `plans/informal/references.md`
- `plans/informal/cli.md`
- `plans/informal/testing.md`

## Naming conventions

The intended Lean naming conventions for this layer are:

- namespace root: `AFTK.Informal`
- library modules: `AFTK/Informal/...`
- CLI-specific modules: `AFTK/Informal/Cli/...`
- public library root module: `AFTK/Informal.lean`

The public executable should be invoked through:

```text
lake exe aftk informal ...
```

That is a CLI naming decision.
The library layout should support it, but should not collapse all informal-layer logic into the executable entrypoint.

## Layout principles

### 1. Keep the reusable library separate from the executable

The informal layer should be usable from:

- the `aftk` executable
- later Lean code in the server/file-worker layer
- tests
- small internal integration utilities

Accordingly, the main informal-layer logic should live in ordinary library modules under `AFTK/Informal/`.
`Main.lean` should remain only a thin executable dispatcher.

### 2. Depend one-way on the knowledge-base library

The informal layer depends on the knowledge base.
The knowledge base must not depend back on the informal layer.

That means:

- informal-layer library modules may import `AFTK.KnowledgeBase`
- informal-layer library modules should not import `AFTK.KnowledgeBase.Cli.*`
- knowledge-base library modules should not import `AFTK.Informal.*`

### 3. Keep the placeholder primitive near the bottom of the dependency graph

The kernel-facing placeholder primitive is tiny and foundational.
It should live in a very small module with almost no dependencies.

Higher-level modules such as elaboration, tracking, dependencies, presentation, and CLI should build on it, not the other way around.

### 4. Separate syntax/elaboration from tracking and presentation

`informal[...]` syntax and elaboration are one concern.
Persistent declaration-level tracking is another.
Presentation rendering is a third.

Those parts work together, but they should not be fused into one giant module.
A module split along these lines will make the code easier to test and easier to evolve.

### 5. Keep low-level reference semantics separate from CLI parsing

The informal-layer reference type should be reusable outside the CLI.
So the semantic reference model and knowledge-base resolution code should live in library modules, not inside CLI command parsing or rendering files.

### 6. Keep derived dependency logic above tracking

Dependency views depend on:

- the tracking layer’s declaration↔reference linkage, and
- Lean environment dependency information.

So dependency modules should sit above tracking modules, not the other way around.

### 7. Keep presentation as a reusable derived-view layer

Presentation should be reusable from:

- elaboration-time hover/info attachment
- the informal CLI `present` command
- later AFTK/file-worker or server integrations

So presentation builders and renderers should live in reusable library modules, not only inside the CLI.

### 8. Confine CLI-only dependencies to `Cli/*`

Any CLI-specific parsing, text rendering, JSON envelope shaping, command dispatch, or optional `Lake.Util` usage should remain under `AFTK/Informal/Cli/*`.
The reusable library should not depend on those pieces.

### 9. Start coarse-grained, then split later if needed

The first implementation should not create a separate file for every tiny helper.
A modest number of modules with clear boundaries is better than over-fragmentation.

If one coarse module later grows too large, it can be split without changing the overall dependency direction established here.

## Recommended initial module layout

A good initial module layout for the informal layer is:

```text
AFTK.lean
AFTK/Informal.lean
AFTK/Informal/Syntax.lean
AFTK/Informal/Placeholder.lean
AFTK/Informal/References.lean
AFTK/Informal/Tracking.lean
AFTK/Informal/Dependencies.lean
AFTK/Informal/Presentation.lean
AFTK/Informal/Elaborator.lean
AFTK/Informal/Cli/Types.lean
AFTK/Informal/Cli/Parse.lean
AFTK/Informal/Cli/Render.lean
AFTK/Informal/Cli/Main.lean
Main.lean
AFTKTest/Informal.lean
AFTKTest/Informal/Main.lean
AFTKTest/Informal/References.lean
AFTKTest/Informal/Tracking.lean
AFTKTest/Informal/Dependencies.lean
AFTKTest/Informal/Presentation.lean
AFTKTest/Informal/Elaboration.lean
AFTKTest/Informal/Cli.lean
```

This is intentionally pragmatic rather than maximally granular.
It is enough structure to keep responsibilities clear without forcing the first implementation into unnecessary fragmentation.

## Module responsibilities

### `AFTK.lean`

This is the root of the `AFTK` library.
As the project grows, it should import stable library entrypoints such as:

- `AFTK.KnowledgeBase`
- `AFTK.Informal`

It should not import executable-only modules.

### `AFTK/Informal.lean`

This should be the curated public root for the informal-layer library.
It should re-export the reusable modules that other Lean code may reasonably import.

A good initial public surface would typically import:

- `AFTK.Informal.Syntax`
- `AFTK.Informal.Placeholder`
- `AFTK.Informal.References`
- `AFTK.Informal.Tracking`
- `AFTK.Informal.Dependencies`
- `AFTK.Informal.Presentation`
- `AFTK.Informal.Elaborator`

It should not import `AFTK.Informal.Cli.*`.
The CLI is a consumer of the library, not part of the reusable library surface.

### `AFTK/Informal/Syntax.lean`

This module should hold syntax categories and syntax declarations related to `informal[...]`, including:

- the dedicated bracketed node-id parser category
- the `informal[...]` term syntax declaration
- small syntax-extraction helpers if they are reusable across elaboration/tests

This module should stay lightweight and should avoid depending on tracking, presentation, or CLI code.

### `AFTK/Informal/Placeholder.lean`

This should hold the kernel-facing placeholder primitive, namely the explicit unsound axiom used during gradual formalization.

It should be a very small module that depends only on Lean basics.
It should not depend on:

- the knowledge-base library
- tracking
- dependencies
- presentation
- CLI code

### `AFTK/Informal/References.lean`

This should define the semantic reference model for bracketed informal references, including:

- `InformalReference`
- `ResolvedInformalReference`
- authoritative conversion/validation through `KnowledgeBase.NodeId`
- exact-match resolution through reusable knowledge-base APIs

This module is where the knowledge-base-native meaning of bracketed references should live.
It should depend on the knowledge-base library, but it should not depend on tracking, dependencies, presentation rendering, or CLI code.

### `AFTK/Informal/Tracking.lean`

This should define the persistent environment extension and the declaration-level query APIs, including things like:

- `InformalOccurrence`
- `InformalTrackingState`
- `InformalDeclEntry`
- `InformalReferenceEntry`
- extension initialization and merge logic
- declaration-centric and reference-centric query functions

This module should depend on `References` but should not depend on:

- `Dependencies`
- `Presentation`
- `Cli/*`

### `AFTK/Informal/Dependencies.lean`

This should define the derived dependency views, including:

- declaration dependency entries
- reference dependency entries
- dependency-leaf helpers
- traversal over Lean constant-usage information plus tracking state

This module should depend on `Tracking` and Lean environment APIs.
It should not depend on presentation or CLI modules.

### `AFTK/Informal/Presentation.lean`

This should define the reusable presentation view models and render helpers, including:

- compact summaries
- richer presentation payloads
- body preview/full-body policy helpers
- text-oriented renderers for hover/query use

This module should depend on `References` and the knowledge-base library.
It may optionally depend on `Tracking` only if a concrete helper truly needs it, but the preferred direction is to keep it independent of tracking so it can render directly from resolved references.

### `AFTK/Informal/Elaborator.lean`

This should define the term elaborator for `informal[...]` and integrate:

- syntax use
- reference validation/resolution
- placeholder construction
- presentation attachment to the info tree
- tracking hooks

This module is the most integration-heavy library module of the informal layer.
It should sit above:

- `Syntax`
- `Placeholder`
- `References`
- `Tracking`
- `Presentation`

It should not import `Cli/*`.

## CLI module layout

The informal CLI should live under `AFTK/Informal/Cli/`.
A reasonable initial split is:

```text
AFTK/Informal/Cli/Types.lean
AFTK/Informal/Cli/Parse.lean
AFTK/Informal/Cli/Render.lean
AFTK/Informal/Cli/Main.lean
```

### `AFTK/Informal/Cli/Types.lean`

This should define CLI-only types such as:

- command enumerations
- output-mode enumerations
- parsed config structures
- small CLI-specific request/response envelope helpers

### `AFTK/Informal/Cli/Parse.lean`

This should implement argument parsing and validation for:

- global options such as `--module`, `--root`, and `--format`
- command selection
- command-specific flags such as `--by`, `--prefix`, `--mode`, and `--body`

This module should stay focused on parsing and should not perform the real query work itself.

### `AFTK/Informal/Cli/Render.lean`

This should implement:

- text rendering for command results
- JSON envelope construction for command results
- stable deterministic ordering at output boundaries if needed

Keeping rendering separate from parsing makes the CLI easier to test and evolve.

### `AFTK/Informal/Cli/Main.lean`

This should be the CLI dispatcher.
It should:

- parse args
- import requested modules when needed
- call reusable library queries
- call presentation builders
- choose text vs JSON rendering
- map errors to exit behavior

This module should be the only informal CLI module that needs to orchestrate the whole command flow.

## Top-level executable integration

`Main.lean` should remain a thin dispatcher.
Once the informal CLI exists, the top-level executable should dispatch both major command families, for example:

```text
lake exe aftk knowledgebase ...
lake exe aftk informal ...
```

So `Main.lean` should eventually import and dispatch to:

- `AFTK.KnowledgeBase.Cli.Main`
- `AFTK.Informal.Cli.Main`

without absorbing informal-layer logic directly.

## Recommended dependency direction

A good high-level dependency direction is:

```text
KnowledgeBase library
        ↑
References    Placeholder    Syntax
     ↑            ↑            ↑
     └──────┬─────┴──────┬─────┘
            │            │
        Tracking     Presentation
            │            ↑
            └────┬───────┘
                 │
            Dependencies
                 │
             Elaborator
                 │
             Cli/*
                 │
              Main.lean
```

This diagram is schematic rather than literal, but the main constraints should hold:

- `Placeholder` stays near the bottom
- `References` owns knowledge-base-backed reference semantics
- `Tracking` sits below `Dependencies`
- `Presentation` is reusable from both elaboration and CLI code
- `Cli/*` depends on library modules, never the reverse

## Notes on the dependency graph

### `Dependencies` should not depend on `Elaborator`

Dependency views are derived from environments and tracking state, not from the elaborator implementation.

### `Tracking` should not depend on `Presentation`

Tracking owns declaration↔reference linkage, not rendering.

### `References` should not depend on `Tracking`

Reference identity and resolution are lower-level concerns than declaration-level tracking.

### `Presentation` should not depend on `Cli/*`

Presentation must be reusable from hover/info attachment and later server/file-worker integrations.

## Optional future module splits

The initial layout above should be enough for the first implementation.
If modules later grow too large, sensible later splits could include:

- splitting `References.lean` into identity vs resolution helpers
- splitting `Presentation.lean` into view models vs renderers
- splitting `Dependencies.lean` into declaration vs reference projection helpers
- adding an `AFTK/Informal/BridgeState.lean` module if noncanonical bridge-local caches/indexes become substantial enough to deserve their own home

None of these splits are required before the first implementation.

## Test layout

The informal-layer tests should live under the project-wide `AFTKTest/` tree, parallel to the knowledge-base tests.

A good initial structure is:

```text
AFTKTest/Informal.lean
AFTKTest/Informal/Main.lean
AFTKTest/Informal/References.lean
AFTKTest/Informal/Tracking.lean
AFTKTest/Informal/Dependencies.lean
AFTKTest/Informal/Presentation.lean
AFTKTest/Informal/Elaboration.lean
AFTKTest/Informal/Cli.lean
```

This keeps test modules aligned with the library/module boundaries.

If the package test driver later grows into a project-wide aggregator, it can import both the knowledge-base and informal test mains.
The layout here should not assume a particular final test-driver wiring, only a clear place for the informal tests to live.

## Public import policy

The intended public library import surface is:

- broad import: `AFTK.Informal`
- narrow imports when implementation code wants tighter boundaries, such as:
  - `AFTK.Informal.References`
  - `AFTK.Informal.Tracking`
  - `AFTK.Informal.Dependencies`
  - `AFTK.Informal.Presentation`

The CLI modules should import narrow library modules as needed rather than always importing the broad root blindly.
That helps keep dependencies honest.

## Design decisions for v1

The following layout decisions are recommended for the first rewrite implementation:

1. Create a dedicated `AFTK/Informal/` module tree.
2. Add `AFTK/Informal.lean` as the public library root.
3. Keep `Syntax`, `Placeholder`, `References`, `Tracking`, `Dependencies`, `Presentation`, and `Elaborator` as separate reusable modules.
4. Keep CLI modules under `AFTK/Informal/Cli/*`.
5. Keep `Main.lean` as a thin dispatcher only.
6. Update `AFTK.lean` to re-export `AFTK.Informal` once the informal layer lands.
7. Keep informal tests under `AFTKTest/Informal/*`, parallel to the knowledge-base test tree.
8. Do not import knowledge-base CLI modules into informal library modules.
9. Do not let CLI-only parsing/rendering code leak into the reusable informal library.

## Lean 4 and current-project reuse findings

The current project layout already supports the basic pattern this design wants:

- `AFTK/KnowledgeBase/*` already demonstrates a good library-vs-CLI split
- `AFTK.lean` already acts as a small public library root
- `Main.lean` is already a thin top-level dispatcher
- `AFTKTest/KnowledgeBase/*` already demonstrates the project-wide test-tree style

Core Lean adds one structural reminder for the CLI split: module-import code for environment-backed commands needs search-path setup and `importModules ... (loadExts := true)`, which is another reason to keep that operational logic under `AFTK/Informal/Cli/*` rather than leaking it into the reusable library root.

The informal layer should mirror those successful structural choices rather than inventing a very different layout style.

## Open questions for later refinement

- Should `Syntax.lean` remain separate from `Elaborator.lean`, or should it be merged if the syntax surface remains very small?
- Should presentation text renderers live in `Presentation.lean` directly, or later split into `Presentation/Render.lean` if richer output formats accumulate?
- Should the project eventually move to a single aggregate `AFTKTest.Main` test driver spanning multiple layers?

These are layout refinements, not blockers for the initial implementation.

## Summary

The informal layer should be implemented as a dedicated reusable library under `AFTK/Informal/`, with clear module boundaries for:

- syntax,
- placeholder primitive,
- reference semantics and resolution,
- declaration-level tracking,
- derived dependency views,
- presentation,
- elaboration,
- and CLI code.

The key structural rule is that reusable library modules stay separate from CLI modules and depend one-way on the knowledge-base library. `Main.lean` should remain only a thin dispatcher, and the informal test tree should live under `AFTKTest/Informal/*` parallel to the existing knowledge-base tests.
